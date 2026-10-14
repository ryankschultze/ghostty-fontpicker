import CoreText
import Foundation

/// The whole "use this font in Ghostty" step, shared by the window and the CLI.
public enum FontApplier {
    public struct Result: Sendable {
        /// The include file that was written.
        public var include: URL
        /// True when this call added the `config-file` line to the main config.
        public var linkedNow: Bool
        /// What the include held before, for undoing.
        public var previous: String?
        /// Nil when the reload was skipped.
        public var reload: GhosttyApp.ReloadOutcome?
    }

    public enum Failure: Error, LocalizedError {
        /// Ghostty's validator refused the generated file. The previous one is back in place.
        case rejected(String)

        public var errorDescription: String? {
            switch self {
            case .rejected(let detail): return "Ghostty rejected the generated config:\n\(detail)"
            }
        }
    }

    /// Writes the include, checks it with Ghostty's validator, links it from the main
    /// config, and asks Ghostty to reload.
    public static func apply(
        _ selection: FontSelection, installer: GhosttyInstaller = GhosttyInstaller(), reload: Bool = true
    ) throws -> Result {
        let previous = try installer.write(selection)
        if let complaint = GhosttyApp.validate(installer.include) {
            try? installer.restore(previous)
            throw Failure.rejected(complaint)
        }
        let wasLinked = installer.isLinked
        try installer.link()
        return Result(
            include: installer.include, linkedNow: !wasLinked, previous: previous,
            reload: reload ? GhosttyApp.reload() : nil)
    }
}

/// Remembers the per-feature breakdown between launches, since probing a family with a
/// hundred character variants takes a noticeable moment.
public final class DetailCache: @unchecked Sendable {
    private struct Entry: Codable {
        var stamp: String
        var detail: FontDetail
    }

    /// Bump when the probe changes what it reports.
    private static let version = 2

    private let url: URL
    private let lock = NSLock()
    private var entries: [String: Entry]

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FontPicker")
        url = base.appendingPathComponent("details-v\(Self.version).json")
        entries = (try? JSONDecoder().decode([String: Entry].self, from: Data(contentsOf: url))) ?? [:]
    }

    /// The cached detail, or a fresh probe if the font file has changed since.
    public func detail(for family: FontFamily) -> FontDetail {
        let stamp = Self.stamp(for: family)
        lock.lock()
        let cached = entries[family.family]
        lock.unlock()
        if let cached, cached.stamp == stamp { return cached.detail }

        let detail = FontProbe.detail(for: family)
        lock.lock()
        entries[family.family] = Entry(stamp: stamp, detail: detail)
        let snapshot = entries
        lock.unlock()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        return detail
    }

    /// Changes when the font file is replaced, e.g. by a Homebrew upgrade.
    static func stamp(for family: FontFamily) -> String {
        guard let font = FontFactory.font(family: family.family, size: FontProbe.probeSize),
              let file = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL else { return "missing" }
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(file.path)|\(Int(modified))|\(attributes?[.size] as? Int ?? 0)"
    }
}
