import Foundation

/// Turns a `FontSelection` into Ghostty config text.
public enum GhosttyConfig {
    /// Features Ghostty's docs say to switch off to "generally disable most ligatures".
    public static let ligatureTags = ["calt", "liga", "dlig"]

    /// The lines someone would paste into their own config.
    public static func snippet(_ selection: FontSelection) -> String {
        lines(selection).joined(separator: "\n")
    }

    /// The managed include file. Ghostty loads included files after the config that names
    /// them, and `font-family` and `font-feature` are lists that append, so each list is
    /// emptied first. Without that, a font set in the main config would stay primary.
    public static func managedFile(_ selection: FontSelection) -> String {
        var out = [
            "# Written by FontPicker. Changes made here are overwritten the next time you apply a font.",
            "font-family = \"\"",
            "font-family-bold = \"\"",
            "font-family-italic = \"\"",
            "font-family-bold-italic = \"\"",
            "font-feature = \"\"",
        ]
        out += lines(selection, alwaysStyle: true)
        return out.joined(separator: "\n") + "\n"
    }

    static func lines(_ selection: FontSelection, alwaysStyle: Bool = false) -> [String] {
        var out = ["font-family = \(quoted(selection.family))"]
        let features = featureList(selection.features)
        if !features.isEmpty { out.append("font-feature = \(features)") }
        if !selection.ligatures {
            out.append("font-feature = " + ligatureTags.map { "-\($0)" }.joined(separator: ", "))
        }
        if let style = selection.namedStyle {
            out.append("font-style = \(style)")
        } else if alwaysStyle {
            out.append("font-style = default")
        }
        if let italic = selection.italicFamily, !italic.isEmpty, italic != selection.family {
            // Both italic styles, so bold italic doesn't fall back to the upright family.
            out.append("font-family-italic = \(quoted(italic))")
            out.append("font-family-bold-italic = \(quoted(italic))")
        }
        out.append("font-size = \(sizeString(selection.size))")
        return out
    }

    /// `ss01, ss05, cv10=3`, sorted by tag.
    public static func featureList(_ features: [String: Int]) -> String {
        features.filter { $0.value > 0 }
            .sorted { $0.key < $1.key }
            .map { $0.value == 1 ? $0.key : "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
    }

    /// Parses the same syntax back, for `--features` on the command line.
    public static func parseFeatures(_ text: String) -> [String: Int] {
        var out: [String: Int] = [:]
        for part in text.split(whereSeparator: { $0 == "," || $0 == " " }) {
            let pieces = part.split(separator: "=", maxSplits: 1)
            guard let tag = pieces.first, !tag.isEmpty else { continue }
            out[String(tag)] = pieces.count > 1 ? Int(pieces[1]) ?? 1 : 1
        }
        return out
    }

    static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    public static func sizeString(_ size: Double) -> String {
        size == size.rounded() ? String(Int(size)) : String(size)
    }
}

/// Where Ghostty keeps its config on macOS, and where FontPicker keeps its include.
public enum GhosttyPaths {
    public static let includeName = "fontpicker.ghostty"
    public static let bundleIdentifier = "com.mitchellh.ghostty"

    /// The file Ghostty treats as the user's config, following the same order as Ghostty's
    /// own `preferredDefaultFilePath`: Application Support first, then XDG, and within each
    /// `config.ghostty` before the pre-1.3 name `config`. Empty files count as missing.
    public static func mainConfig(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        let appSupport = home.appendingPathComponent("Library/Application Support/\(bundleIdentifier)")
        let xdgRoot = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".config")
        let xdg = xdgRoot.appendingPathComponent("ghostty")

        func preferred(in directory: URL) -> URL {
            let current = directory.appendingPathComponent("config.ghostty")
            let legacy = directory.appendingPathComponent("config")
            if hasContent(current) { return current }
            return hasContent(legacy) ? legacy : current
        }

        let appSupportFile = preferred(in: appSupport)
        if hasContent(appSupportFile) { return appSupportFile }
        let xdgFile = preferred(in: xdg)
        return hasContent(xdgFile) ? xdgFile : appSupportFile
    }

    /// The include sits beside the main config so the relative `config-file` line resolves.
    public static func include(for mainConfig: URL) -> URL {
        mainConfig.deletingLastPathComponent().appendingPathComponent(includeName)
    }

    static func hasContent(_ url: URL) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
        return (size ?? 0) > 0
    }
}

/// Reads and writes the two files involved in applying a font.
public struct GhosttyInstaller {
    public let mainConfig: URL
    public var include: URL { GhosttyPaths.include(for: mainConfig) }

    public static let includeLine = "config-file = ?\(GhosttyPaths.includeName)"

    public init(mainConfig: URL = GhosttyPaths.mainConfig()) {
        self.mainConfig = mainConfig
    }

    /// Whether the main config already pulls in the include.
    public var isLinked: Bool {
        guard let text = try? String(contentsOf: mainConfig, encoding: .utf8) else { return false }
        return text.split(whereSeparator: \.isNewline).contains(where: Self.namesInclude)
    }

    static func namesInclude(_ line: Substring) -> Bool {
        let parts = line.split(separator: "=", maxSplits: 1)
        guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "config-file" else { return false }
        let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " \t\"?"))
        return value == GhosttyPaths.includeName || value.hasSuffix("/" + GhosttyPaths.includeName)
    }

    /// Appends the `config-file` line to the main config if it isn't there, creating the
    /// file when needed. Nothing else in the file is touched.
    public func link() throws {
        guard !isLinked else { return }
        let manager = FileManager.default
        try manager.createDirectory(at: mainConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        var text = (try? String(contentsOf: mainConfig, encoding: .utf8)) ?? ""
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        if !text.isEmpty { text += "\n" }
        text += "# FontPicker keeps the font settings in \(GhosttyPaths.includeName), next to this file.\n"
        text += Self.includeLine + "\n"
        try text.write(to: mainConfig, atomically: true, encoding: .utf8)
    }

    /// Writes the include for `selection`. Returns the previous contents, if any, so a
    /// caller can put them back.
    @discardableResult
    public func write(_ selection: FontSelection) throws -> String? {
        let previous = try? String(contentsOf: include, encoding: .utf8)
        try FileManager.default.createDirectory(at: include.deletingLastPathComponent(), withIntermediateDirectories: true)
        try GhosttyConfig.managedFile(selection).write(to: include, atomically: true, encoding: .utf8)
        return previous
    }

    /// Puts back what `write` replaced, or deletes the include if there was nothing before.
    public func restore(_ previous: String?) throws {
        if let previous {
            try previous.write(to: include, atomically: true, encoding: .utf8)
        } else if FileManager.default.fileExists(atPath: include.path) {
            try FileManager.default.removeItem(at: include)
        }
    }

    /// Deletes the include and takes the `config-file` line (and its comment) back out.
    public func unlink() throws {
        if FileManager.default.fileExists(atPath: include.path) {
            try FileManager.default.removeItem(at: include)
        }
        guard let text = try? String(contentsOf: mainConfig, encoding: .utf8) else { return }
        var kept: [Substring] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if Self.namesInclude(line) {
                if let last = kept.last, last.hasPrefix("# FontPicker keeps the font settings") { kept.removeLast() }
                if let last = kept.last, last.isEmpty, kept.count > 1 { kept.removeLast() }
                continue
            }
            kept.append(line)
        }
        let result = kept.joined(separator: "\n")
        if result != text { try result.write(to: mainConfig, atomically: true, encoding: .utf8) }
    }
}
