import AppKit
import Foundation

/// Talks to the installed and running Ghostty: asks it to validate and reload config.
public enum GhosttyApp {
    /// Ghostty's macOS app started handling SIGUSR2 as "reload config" in 1.2.0. Before
    /// that the signal's default action applies, which terminates the process, so older
    /// versions must never be signalled.
    public static let firstVersionWithReloadSignal = [1, 2, 0]

    public struct Instance: Equatable, Sendable {
        public var pid: pid_t
        public var version: String?
    }

    public enum ReloadOutcome: Equatable, Sendable {
        /// The signal was delivered to these processes.
        case reloaded([Instance])
        case notRunning
        /// Running, but too old to reload on a signal. The user has to reload by hand.
        case tooOld(String?)
        case failed(String)

        public var summary: String {
            switch self {
            case .reloaded(let instances):
                return instances.count == 1 ? "Ghostty reloaded." : "Reloaded \(instances.count) Ghostty instances."
            case .notRunning:
                return "Ghostty isn't running. It will pick the font up when it starts."
            case .tooOld(let version):
                return "Ghostty \(version ?? "this version") can't reload on request. Press cmd+shift+, in Ghostty."
            case .failed(let reason):
                return "Couldn't signal Ghostty: \(reason). Press cmd+shift+, in Ghostty."
            }
        }
    }

    public static func running() -> [Instance] {
        NSRunningApplication.runningApplications(withBundleIdentifier: GhosttyPaths.bundleIdentifier).map { app in
            let version = app.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String }
            return Instance(pid: app.processIdentifier, version: version)
        }
    }

    /// Asks every running Ghostty to reload its config.
    public static func reload() -> ReloadOutcome {
        let instances = running()
        guard !instances.isEmpty else { return .notRunning }
        let capable = instances.filter { supportsReloadSignal($0.version) }
        guard !capable.isEmpty else { return .tooOld(instances.first?.version) }
        for instance in capable where kill(instance.pid, SIGUSR2) != 0 {
            return .failed(String(cString: strerror(errno)))
        }
        return .reloaded(capable)
    }

    /// An unknown version is treated as too old: guessing wrong would kill the terminal.
    static func supportsReloadSignal(_ version: String?) -> Bool {
        guard let version else { return false }
        let parts = version.split(whereSeparator: { !$0.isNumber }).prefix(3).compactMap { Int($0) }
        guard !parts.isEmpty else { return false }
        for (index, minimum) in firstVersionWithReloadSignal.enumerated() {
            let part = index < parts.count ? parts[index] : 0
            if part != minimum { return part > minimum }
        }
        return true
    }

    /// The `ghostty` executable inside the installed app, or on PATH.
    public static func binary() -> URL? {
        var candidates: [URL] = []
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: GhosttyPaths.bundleIdentifier) {
            candidates.append(app.appendingPathComponent("Contents/MacOS/ghostty"))
        }
        candidates.append(URL(fileURLWithPath: "/Applications/Ghostty.app/Contents/MacOS/ghostty"))
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        candidates += path.split(separator: ":").map { URL(fileURLWithPath: String($0)).appendingPathComponent("ghostty") }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Runs Ghostty's own validator over a config file. Returns its complaints, or nil if
    /// the file is fine or Ghostty's CLI can't be found.
    public static func validate(_ file: URL) -> String? {
        guard let result = run(["+validate-config", "--config-file=\(file.path)"]), result.status != 0 else { return nil }
        let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Ghostty rejected the config." : text
    }

    /// Ghostty's `font-size` when the config doesn't set one.
    public static let defaultFontSize = 13.0

    /// The font Ghostty is currently configured with, read through `+show-config`. The
    /// family is nil when the config leaves it to Ghostty's built-in default.
    public static func configuredFont() -> (family: String?, size: Double?) {
        guard let result = run(["+show-config"]), result.status == 0 else { return (nil, nil) }
        var family: String?
        // `+show-config` only prints what differs from the defaults.
        var size: Double? = defaultFontSize
        for line in result.output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " \t\""))
            // `font-family` repeats for fallbacks; the first is the primary.
            if key == "font-family", family == nil, !value.isEmpty { family = value }
            if key == "font-size" { size = Double(value) }
        }
        return (family, size)
    }

    static func run(_ arguments: [String]) -> (status: Int32, output: String)? {
        guard let binary = binary() else { return nil }
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
