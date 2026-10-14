import FontPickerCore
import Foundation

/// The command-line face of the picker: the same core, without the window.
enum CLI {
    static let usage = """
        fontpicker — preview and choose fonts for Ghostty

        USAGE
          fontpicker                      open the picker window
          fontpicker list [--all] [--json]
                                          fixed-width families (Nerd Fonts unless --all)
          fontpicker info <family> [--json]
                                          features, ligatures and metrics for one family
          fontpicker apply <family> [options]
                                          write the font to Ghostty's config and reload it
          fontpicker reset                remove FontPicker's include and its config-file line
          fontpicker paths                show the config files involved
          fontpicker version              print the version

        APPLY OPTIONS
          --features <list>     e.g. "ss01, ss05, cv10=3"
          --no-ligatures        add -calt, -liga, -dlig
          --style <name>        a named upright style, e.g. Light or Retina
          --italic-from <fam>   take italics from another family
          --size <points>       default 14
          --print               show the config lines and change nothing
          --no-reload           write the files but don't signal Ghostty

        COMMON
          --config <file>       use this Ghostty config instead of the default location
        """

    /// Returns a process exit code.
    @MainActor static func run(_ arguments: [String]) -> Int32 {
        var args = Arguments(arguments)
        // `next()` skips anything starting with `--`, so these two are looked for first.
        if args.flag("--help") { args = Arguments(["help"]) }
        if args.flag("--version") { args = Arguments(["version"]) }
        guard let command = args.next() else { return fail("missing command") }
        do {
            switch command {
            case "list": return try list(&args)
            case "info": return try info(&args)
            case "apply": return try apply(&args)
            case "reset": return try reset(&args)
            case "paths": return try paths(&args)
            case "snapshot": return try Snapshot.run(&args)
            case "help", "-h":
                print(usage)
                return 0
            case "version":
                print(FontPickerVersion.current)
                return 0
            default:
                return fail("unknown command '\(command)'")
            }
        } catch {
            return fail(error.localizedDescription, showUsage: false)
        }
    }

    static func fail(_ message: String, showUsage: Bool = true) -> Int32 {
        FileHandle.standardError.write(Data("fontpicker: \(message)\n".utf8))
        if showUsage { FileHandle.standardError.write(Data("Run 'fontpicker help' for usage.\n".utf8)) }
        return 2
    }

    // MARK: Commands

    static func list(_ args: inout Arguments) throws -> Int32 {
        let all = args.flag("--all"), json = args.flag("--json")
        try args.finish()
        let families = FontCatalog.discover().filter { all || $0.isNerdFont }
        if json { return emit(families) }
        for group in FontGroup.allCases {
            let members = families.filter { $0.group == group }
            guard !members.isEmpty else { continue }
            print(group.title.uppercased())
            for family in members {
                print("  " + family.short.padding(toLength: 26, withPad: " ", startingAt: 0)
                    + family.family.padding(toLength: 34, withPad: " ", startingAt: 0) + meta(family))
            }
        }
        return 0
    }

    static func info(_ args: inout Arguments) throws -> Int32 {
        let json = args.flag("--json")
        guard let name = args.next() else { throw CLIError("info needs a family name") }
        try args.finish()
        let family = try resolve(name)
        let detail = DetailCache().detail(for: family)
        if json {
            struct Info: Encodable { let family: FontFamily; let detail: FontDetail }
            return emit(Info(family: family, detail: detail))
        }
        print("\(family.short)  (\(family.family))")
        if let note = family.note { print(note) }
        print("")
        print("Ligatures  \(family.ligDefault) by default, \(family.ligMax) with its sets on, of \(FontProbe.ligatureTests.count) tested")
        if !family.ligs.isEmpty { print("           \(family.ligs.joined(separator: " "))") }
        print("Italic     \(family.italic.rawValue)\(family.cursive ? " (cursive)" : "")")
        print("Styles     \(family.styles.joined(separator: ", "))")
        print(String(format: "Cell       %.3fem wide, x-height %.3f, line %.3f", family.advance, family.xHeight, family.lineHeight))
        for (title, features) in [("Features", detail.features), ("Character variants", detail.variants)] where !features.isEmpty {
            print("\n\(title)")
            for feature in features {
                let affects = ([feature.chars] + feature.sequences).filter { !$0.isEmpty }.joined(separator: " ")
                let alternates = feature.alternates > 1 ? "  (\(feature.alternates) variants)" : ""
                let name = feature.name.map { "  \($0)" } ?? ""
                print("  \(feature.tag)  \(affects)\(name)\(alternates)")
            }
        }
        if detail.hidden > 0 { print("\n\(detail.hidden) more feature(s) change nothing in the tested characters.") }
        return 0
    }

    static func apply(_ args: inout Arguments) throws -> Int32 {
        let features = args.value("--features").map(GhosttyConfig.parseFeatures) ?? [:]
        let ligatures = !args.flag("--no-ligatures")
        let style = args.value("--style")
        let italicFrom = args.value("--italic-from")
        let size = try args.value("--size").map { text -> Double in
            guard let size = Double(text), size > 0 else { throw CLIError("--size needs a positive number") }
            return size
        } ?? 14
        let printOnly = args.flag("--print"), noReload = args.flag("--no-reload")
        let installer = try installer(&args)
        guard let name = args.next() else { throw CLIError("apply needs a family name") }
        try args.finish()

        let family = try resolve(name)
        if let style, !family.styles.contains(style) {
            throw CLIError("\(family.family) has no '\(style)' style. It has: \(family.styles.joined(separator: ", "))")
        }
        let unknown = features.keys.filter { !family.setTags.contains($0) && !family.cvTags.contains($0) }.sorted()
        if !unknown.isEmpty {
            throw CLIError("\(family.family) has no feature \(unknown.joined(separator: ", "))")
        }
        let selection = FontSelection(
            family: family.family, features: features, ligatures: ligatures, style: style,
            italicFamily: try italicFrom.map { try resolve($0).family }, size: size)

        if printOnly {
            print(GhosttyConfig.snippet(selection))
            return 0
        }
        let result = try FontApplier.apply(selection, installer: installer, reload: !noReload)
        print("Wrote \(result.include.path)")
        if result.linkedNow { print("Added '\(GhosttyInstaller.includeLine)' to \(installer.mainConfig.path)") }
        if let reload = result.reload { print(reload.summary) }
        return 0
    }

    static func reset(_ args: inout Arguments) throws -> Int32 {
        let noReload = args.flag("--no-reload")
        let installer = try installer(&args)
        try args.finish()
        try installer.unlink()
        print("Removed \(installer.include.path) and its line in \(installer.mainConfig.path)")
        if !noReload { print(GhosttyApp.reload().summary) }
        return 0
    }

    static func paths(_ args: inout Arguments) throws -> Int32 {
        let installer = try installer(&args)
        try args.finish()
        print("Ghostty config   \(installer.mainConfig.path)")
        print("FontPicker file  \(installer.include.path)\(installer.isLinked ? "  (linked)" : "  (not linked yet)")")
        print("Ghostty CLI      \(GhosttyApp.binary()?.path ?? "not found")")
        let running = GhosttyApp.running().map { "pid \($0.pid) (\($0.version ?? "unknown version"))" }
        print("Ghostty running  \(running.isEmpty ? "no" : running.joined(separator: ", "))")
        return 0
    }

    // MARK: Helpers

    static func installer(_ args: inout Arguments) throws -> GhosttyInstaller {
        guard let path = args.value("--config") else { return GhosttyInstaller() }
        return GhosttyInstaller(mainConfig: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
    }

    /// Accepts the exact family name, the short name, or either without regard to case.
    static func resolve(_ name: String) throws -> FontFamily {
        if let exact = FontCatalog.summarize(family: name) { return exact }
        let families = FontCatalog.discover()
        let wanted = name.lowercased()
        if let match = families.first(where: { $0.family.lowercased() == wanted || $0.short.lowercased() == wanted }) {
            return match
        }
        let close = families.filter { $0.family.lowercased().contains(wanted) || $0.short.lowercased().contains(wanted) }
        if close.count == 1 { return close[0] }
        let hint = close.isEmpty ? "" : " Did you mean: " + close.prefix(6).map(\.family).joined(separator: ", ") + "?"
        throw CLIError("no installed fixed-width family matches '\(name)'.\(hint)")
    }

    static func meta(_ family: FontFamily) -> String {
        let parts = [
            family.ligMax > 0 ? "\(family.ligMax) lig" : "",
            family.stylisticSetCount > 0 ? "\(family.stylisticSetCount) sets" : "",
            family.cvTags.isEmpty ? "" : "\(family.cvTags.count) cv",
        ].filter { !$0.isEmpty }
        return parts.isEmpty ? "plain" : parts.joined(separator: " · ")
    }

    static func emit<T: Encodable>(_ value: T) -> Int32 {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return fail("couldn't encode JSON", showUsage: false) }
        print(String(decoding: data, as: UTF8.self))
        return 0
    }
}

struct CLIError: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// A small argument reader: flags and `--key value` options can appear anywhere, and
/// whatever is left over is positional.
struct Arguments {
    private var items: [String]

    init(_ items: [String]) { self.items = items }

    mutating func flag(_ name: String) -> Bool {
        guard let index = items.firstIndex(of: name) else { return false }
        items.remove(at: index)
        return true
    }

    /// Accepts both `--key value` and `--key=value`.
    mutating func value(_ name: String) -> String? {
        if let index = items.firstIndex(where: { $0.hasPrefix(name + "=") }) {
            return String(items.remove(at: index).dropFirst(name.count + 1))
        }
        guard let index = items.firstIndex(of: name), index + 1 < items.count else { return nil }
        items.remove(at: index)
        return items.remove(at: index)
    }

    mutating func next() -> String? {
        guard let index = items.firstIndex(where: { !$0.hasPrefix("--") }) else { return nil }
        return items.remove(at: index)
    }

    func finish() throws {
        if let extra = items.first { throw CLIError("unexpected argument '\(extra)'") }
    }
}
