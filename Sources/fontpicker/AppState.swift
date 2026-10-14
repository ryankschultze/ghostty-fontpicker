import AppKit
import Combine
import FontPickerCore
import SwiftUI

enum DriftMode: String, CaseIterable {
    case off, tour, lfo, random

    var title: String {
        switch self {
        case .off: return "Off"
        case .tour: return "Tour"
        case .lfo: return "LFO"
        case .random: return "Random"
        }
    }
}

enum FontScope: String, Codable {
    case nerd, all
}

/// The picker's model: what's installed, what's selected, and what gets written to Ghostty.
@MainActor
final class AppState: ObservableObject {
    /// Choices that survive a relaunch. Features, style and italic source are remembered
    /// per family, so flicking between fonts doesn't lose the switches set on each.
    struct Prefs: Codable, Equatable {
        var font: String?
        var features: [String: [String: Int]] = [:]
        var ligatures = true
        var size = 14.0
        var style: [String: String] = [:]
        var italicFrom: [String: String] = [:]
        var shortlist: [String] = []
        var lightPane = false
        var scope = FontScope.nerd

        init() {}

        // Decoded key by key so a file written by an older build still loads.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            font = try c.decodeIfPresent(String.self, forKey: .font)
            features = try c.decodeIfPresent([String: [String: Int]].self, forKey: .features) ?? [:]
            ligatures = try c.decodeIfPresent(Bool.self, forKey: .ligatures) ?? true
            size = try c.decodeIfPresent(Double.self, forKey: .size) ?? 14
            style = try c.decodeIfPresent([String: String].self, forKey: .style) ?? [:]
            italicFrom = try c.decodeIfPresent([String: String].self, forKey: .italicFrom) ?? [:]
            shortlist = try c.decodeIfPresent([String].self, forKey: .shortlist) ?? []
            lightPane = try c.decodeIfPresent(Bool.self, forKey: .lightPane) ?? false
            scope = try c.decodeIfPresent(FontScope.self, forKey: .scope) ?? .nerd
        }
    }

    /// Feature values the drift engine lays over the saved ones while it runs.
    struct Overlay: Equatable {
        var family: String
        var features: [String: Int]
        /// The feature the tour is currently showing off.
        var hot: String?
    }

    struct Drift {
        var mode = DriftMode.off
        var rate = 1.0
        var density = 0.5
        var fontsToo = false
        var start = Date()
        var overlay: Overlay?
        var index = -1
        var lastBeat = -1
        var caption: String?
    }

    enum Status: Equatable {
        case info(String)
        case error(String)
    }

    @Published private(set) var families: [FontFamily] = []
    @Published private(set) var details: [String: FontDetail] = [:]
    @Published private(set) var isLoading = true
    @Published var prefs: Prefs
    @Published var filter = ""
    @Published var drift = Drift()
    @Published var status: Status?
    /// Apply every change to Ghostty as it's made. Starts off on each launch.
    @Published var live = false
    /// Set when applying needs the one-time edit to the main config confirmed.
    @Published var askToLink = false
    /// Bumped to move keyboard focus to the filter field.
    @Published var focusFilter = 0

    let installer: GhosttyInstaller
    private let detailCache = DetailCache()
    private let persists: Bool
    private var byFamily: [String: FontFamily] = [:]
    private var probing: Set<String> = []
    private var subscriptions: Set<AnyCancellable> = []
    private var driftTimer: Timer?
    /// What the include held before this session touched it. The outer optional says
    /// whether anything has been applied yet; the inner one is the file's old contents.
    private var sessionBackup: String??
    private var lastApplied: FontSelection?

    init(persists: Bool = true, installer: GhosttyInstaller = GhosttyInstaller()) {
        self.persists = persists
        self.installer = installer
        prefs = persists ? Self.loadPrefs() : Prefs()

        $prefs.dropFirst()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] prefs in
                guard let self else { return }
                self.savePrefs(prefs)
                if self.live, self.drift.mode == .off { self.apply(quiet: true) }
            }
            .store(in: &subscriptions)
    }

    // MARK: Loading

    /// Measures the installed fonts off the main thread, then picks a starting selection.
    func start() {
        let isFirstRun = prefs.font == nil
        Task.detached(priority: .userInitiated) {
            let families = FontCatalog.discover()
            let configured = GhosttyApp.configuredFont()
            await MainActor.run {
                self.adopt(families, configured: isFirstRun ? configured : (nil, nil))
                self.prefetchDetails()
            }
        }
    }

    /// The same as `start`, blocking. For snapshots, where there's no run loop to wait on.
    func loadNow(selecting family: String? = nil) {
        adopt(FontCatalog.discover(), configured: (nil, nil))
        if let family, let match = families.first(where: { $0.family == family || $0.short == family }) {
            prefs.font = match.id
        }
        for family in families where family.id == prefs.font || prefs.shortlist.contains(family.id) {
            details[family.id] = detailCache.detail(for: family)
        }
    }

    private func adopt(_ families: [FontFamily], configured: (family: String?, size: Double?)) {
        self.families = families
        byFamily = Dictionary(uniqueKeysWithValues: families.map { ($0.id, $0) })
        prefs.shortlist.removeAll { byFamily[$0] == nil }
        if let size = configured.size { prefs.size = min(24, max(10, size.rounded())) }
        if prefs.font.flatMap({ byFamily[$0] }) == nil {
            // First run: start on whatever Ghostty is using now, if it's one we can show.
            let start = configured.family.flatMap { byFamily[$0] } ?? families.first(where: \.isNerdFont) ?? families.first
            prefs.font = start?.id
            if let start, !start.isNerdFont { prefs.scope = .all }
        }
        isLoading = false
        if let current { ensureDetail(current) }
    }

    private func ensureDetail(_ family: FontFamily) {
        guard details[family.id] == nil, !probing.contains(family.id) else { return }
        probing.insert(family.id)
        let cache = detailCache
        Task.detached(priority: .userInitiated) {
            let detail = cache.detail(for: family)
            await MainActor.run {
                self.details[family.id] = detail
                self.probing.remove(family.id)
            }
        }
    }

    /// Probes the rest in the background so stepping through the rail never waits.
    private func prefetchDetails() {
        let pending = families.filter { details[$0.id] == nil }
        let cache = detailCache
        Task.detached(priority: .utility) {
            for family in pending {
                let detail = cache.detail(for: family)
                await MainActor.run {
                    if self.details[family.id] == nil { self.details[family.id] = detail }
                }
            }
        }
    }

    // MARK: Selection

    var current: FontFamily? { prefs.font.flatMap { byFamily[$0] } }

    func family(_ id: String) -> FontFamily? { byFamily[id] }

    /// Families in the chosen scope that match the filter, grouped for the rail.
    var groups: [(group: FontGroup, families: [FontFamily])] {
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let visible = families.filter { family in
            (prefs.scope == .all || family.isNerdFont)
                && (query.isEmpty || family.short.lowercased().contains(query) || family.family.lowercased().contains(query))
        }
        return FontGroup.allCases.compactMap { group in
            let members = visible.filter { $0.group == group }
            return members.isEmpty ? nil : (group, members)
        }
    }

    func select(_ id: String, keepingDrift: Bool = false) {
        guard let family = byFamily[id] else { return }
        prefs.font = id
        if !keepingDrift {
            drift.overlay = nil
            drift.index = -1
        }
        ensureDetail(family)
    }

    /// Moves through the fonts currently listed, wrapping at the ends.
    func step(_ delta: Int, keepingDrift: Bool = false) {
        let ids = groups.flatMap { $0.families.map(\.id) }
        guard !ids.isEmpty else { return }
        let index = prefs.font.flatMap(ids.firstIndex(of:)) ?? 0
        select(ids[(index + delta + ids.count) % ids.count], keepingDrift: keepingDrift)
    }

    var isShortlisted: Bool { prefs.font.map(prefs.shortlist.contains) ?? false }

    func toggleShortlist() {
        guard let id = prefs.font else { return }
        if let index = prefs.shortlist.firstIndex(of: id) { prefs.shortlist.remove(at: index) } else { prefs.shortlist.append(id) }
        if let family = byFamily[id] { ensureDetail(family) }
    }

    // MARK: Features

    /// The saved switches for a family. Until the family has been touched, that's its preset.
    func savedFeatures(for family: FontFamily) -> [String: Int] {
        prefs.features[family.id] ?? Dictionary(uniqueKeysWithValues: family.preset.map { ($0, 1) })
    }

    /// What's on screen: the saved switches with any drift overlay on top.
    func liveFeatures(for family: FontFamily) -> [String: Int] {
        var features = savedFeatures(for: family).filter { $0.value > 0 }
        if drift.mode != .off, let overlay = drift.overlay, overlay.family == family.id {
            for (tag, value) in overlay.features { features[tag] = value > 0 ? value : nil }
        }
        return features
    }

    /// Off, on, then through any alternates, then back to off.
    func cycle(_ feature: FontFeature) {
        guard let family = current else { return }
        var features = savedFeatures(for: family)
        let value = features[feature.tag] ?? 0
        features[feature.tag] = value >= feature.alternates ? nil : value + 1
        prefs.features[family.id] = features
    }

    func clearFeatures() {
        guard let family = current else { return }
        prefs.features[family.id] = [:]
        drift.overlay = nil
    }

    func style(for family: FontFamily) -> String {
        if let chosen = prefs.style[family.id], family.styles.contains(chosen) { return chosen }
        return family.styles.contains("Regular") ? "Regular" : family.styles.first ?? "Regular"
    }

    /// Families whose italics can be borrowed, cursive ones first.
    func italicSources(for family: FontFamily) -> [FontFamily] {
        let candidates = families.filter { $0.id != family.id && ($0.italic == .italic || $0.italic == .both) }
        return candidates.filter(\.cursive) + candidates.filter { !$0.cursive }
    }

    // MARK: Output

    func selection(for family: FontFamily, live: Bool = true) -> FontSelection {
        FontSelection(
            family: family.family,
            features: live ? liveFeatures(for: family) : savedFeatures(for: family).filter { $0.value > 0 },
            ligatures: prefs.ligatures,
            style: style(for: family),
            italicFamily: prefs.italicFrom[family.id].flatMap { byFamily[$0]?.family },
            size: prefs.size)
    }

    func renderSpec(for family: FontFamily, live: Bool = true) -> RenderSpec {
        let selection = selection(for: family, live: live)
        return RenderSpec(
            family: selection.family, style: selection.namedStyle, features: selection.features,
            ligatures: selection.ligatures, italicFamily: selection.italicFamily, size: selection.size)
    }

    func palette(appIsDark: Bool) -> TermPalette {
        TermPalette.make(lightPane: prefs.lightPane, appIsDark: appIsDark)
    }

    var configPath: String {
        (installer.mainConfig.path as NSString).abbreviatingWithTildeInPath
    }

    func copyConfig() {
        guard let family = current else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(GhosttyConfig.snippet(selection(for: family)), forType: .string)
        status = .info("Copied. Paste into \(configPath).")
    }

    // MARK: Applying to Ghostty

    var canRevert: Bool { sessionBackup != nil }

    /// Writes the current choice to Ghostty and reloads it. The first time, that means
    /// adding a line to the user's own config, so it asks before doing so.
    func apply(confirmed: Bool = false, quiet: Bool = false) {
        guard let family = current else { return }
        if !installer.isLinked, !confirmed {
            askToLink = true
            return
        }
        let selection = selection(for: family)
        if quiet, selection == lastApplied { return }
        do {
            let result = try FontApplier.apply(selection, installer: installer)
            if sessionBackup == nil { sessionBackup = .some(result.previous) }
            lastApplied = selection
            status = .info("Applied \(family.short). \(result.reload?.summary ?? "")")
        } catch {
            live = false
            status = .error(error.localizedDescription)
        }
    }

    func setLive(_ on: Bool) {
        live = on
        if on { apply(quiet: true) }
    }

    /// The user turned down the config edit, so nothing can be applied.
    func declineLink() {
        live = false
    }

    /// Puts the include back the way this session found it.
    func revert() {
        guard let backup = sessionBackup else { return }
        do {
            try installer.restore(backup)
            sessionBackup = nil
            lastApplied = nil
            live = false
            status = .info("Reverted. \(GhosttyApp.reload().summary)")
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    // MARK: Drift

    /// The features drift plays with. Character variants join in only when there are few
    /// enough to follow on the scope.
    func driftFeatures(for family: FontFamily) -> [FontFeature] {
        guard let detail = details[family.id] else { return [] }
        return detail.variants.count <= 24 ? detail.all : detail.features
    }

    func setDrift(_ mode: DriftMode) {
        drift.mode = mode
        drift.start = Date()
        drift.lastBeat = -1
        drift.index = -1
        drift.overlay = nil
        drift.caption = nil
        driftTimer?.invalidate()
        driftTimer = nil
        guard mode != .off else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // `.common` so it keeps running while a slider is being dragged.
        RunLoop.main.add(timer, forMode: .common)
        driftTimer = timer
    }

    /// Freezes whatever drift has on screen into the saved switches.
    func keepDrift() {
        guard let family = current else { return }
        prefs.features[family.id] = liveFeatures(for: family)
        setDrift(.off)
    }

    /// One feature's slow sine wave. The periods are spread by the golden ratio so no two
    /// line up and the pattern never quite repeats.
    func lfoValue(_ index: Int, at time: Double) -> Double {
        let spread = (Double(index) * 0.6180339887).truncatingRemainder(dividingBy: 1)
        let period = 7 + 9 * spread
        return sin(2 * .pi * (time * drift.rate) / period + Double(index) * 2.1)
    }

    private func tick() {
        guard drift.mode != .off, let family = current else { return }
        let time = Date().timeIntervalSince(drift.start)
        let features = driftFeatures(for: family)

        if drift.mode == .lfo {
            let threshold = 1 - 2 * drift.density
            var values: [String: Int] = [:]
            for (index, feature) in features.enumerated() {
                let value = lfoValue(index, at: time)
                guard value > threshold else {
                    values[feature.tag] = 0
                    continue
                }
                // Higher on the wave picks a later alternate.
                let lift = (value - threshold) / (1 - threshold)
                values[feature.tag] = feature.alternates > 1 ? min(feature.alternates, 1 + Int(lift * Double(feature.alternates))) : 1
            }
            let overlay = Overlay(family: family.id, features: values)
            if drift.overlay != overlay { drift.overlay = overlay }
            let beat = Int(time * drift.rate / 12)
            if drift.fontsToo, beat != drift.lastBeat {
                drift.lastBeat = beat
                if beat > 0 {
                    step(1, keepingDrift: true)
                    drift.overlay = nil
                }
            }
            return
        }

        let period = (drift.mode == .tour ? 3.2 : 1.6) / drift.rate
        let beat = Int(time / period)
        guard beat != drift.lastBeat else { return }
        drift.lastBeat = beat
        drift.mode == .tour ? tourBeat(features) : randomBeat(beat)
    }

    /// Flips one feature per beat, in order, then moves on.
    private func tourBeat(_ features: [FontFeature]) {
        guard !features.isEmpty else {
            if drift.fontsToo { step(1, keepingDrift: true) }
            drift.caption = "no optional features"
            return
        }
        drift.index += 1
        if drift.index >= features.count {
            drift.index = 0
            if drift.fontsToo { step(1, keepingDrift: true) }
        }
        guard let family = current else { return }
        let list = driftFeatures(for: family)
        guard drift.index < list.count else {
            drift.overlay = nil
            return
        }
        let feature = list[drift.index]
        let saved = savedFeatures(for: family)[feature.tag] ?? 0
        let value = saved > 0 ? 0 : (feature.alternates > 1 ? 1 + drift.index % feature.alternates : 1)
        drift.overlay = Overlay(family: family.id, features: [feature.tag: value], hot: feature.tag)
        let affects = [feature.chars.map(String.init).joined(separator: " "), feature.sequences.joined(separator: " ")]
            .filter { !$0.isEmpty }.joined(separator: "  ")
        drift.caption = "\(feature.tag) \(value > 0 ? "on" : "off") · \(feature.name ?? affects)"
    }

    /// Flips a feature or two at random each beat.
    private func randomBeat(_ beat: Int) {
        if drift.fontsToo, beat % 8 == 7 { step(1, keepingDrift: true) }
        guard let family = current else { return }
        let features = driftFeatures(for: family)
        var values = drift.overlay?.family == family.id ? drift.overlay?.features ?? [:] : [:]
        let saved = savedFeatures(for: family)
        var changes: [String] = []
        for _ in 0..<(Double.random(in: 0..<1) < 0.35 ? 2 : 1) {
            guard let feature = features.randomElement() else { break }
            let value = values[feature.tag] ?? saved[feature.tag] ?? 0
            let next = value > 0 ? 0 : (feature.alternates > 1 ? Int.random(in: 1...feature.alternates) : 1)
            values[feature.tag] = next
            changes.append("\(feature.tag) \(next > 0 ? "on" : "off")")
        }
        drift.overlay = Overlay(family: family.id, features: values)
        drift.caption = changes.isEmpty ? "no optional features" : changes.joined(separator: " · ")
    }

    // MARK: Persistence

    private static var prefsURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FontPicker/state.json")
    }

    private static func loadPrefs() -> Prefs {
        (try? JSONDecoder().decode(Prefs.self, from: Data(contentsOf: prefsURL))) ?? Prefs()
    }

    private func savePrefs(_ prefs: Prefs) {
        guard persists else { return }
        let url = Self.prefsURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(prefs).write(to: url, options: .atomic)
    }
}
