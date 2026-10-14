import Foundation
import Testing

@testable import FontPickerCore

@Suite struct ConfigTextTests {
    @Test func snippetForAPlainChoiceIsFamilyAndSize() {
        let text = GhosttyConfig.snippet(FontSelection(family: "FiraCode Nerd Font"))
        #expect(text == "font-family = \"FiraCode Nerd Font\"\nfont-size = 14")
    }

    @Test func snippetListsEverythingThatWasChosen() {
        let selection = FontSelection(
            family: "Monoid Nerd Font", features: ["ss05": 1, "cv01": 3, "ss02": 1, "zero": 0],
            ligatures: false, style: "Retina", italicFamily: "VictorMono Nerd Font", size: 13.5)
        #expect(GhosttyConfig.snippet(selection) == """
            font-family = "Monoid Nerd Font"
            font-feature = cv01=3, ss02, ss05
            font-feature = -calt, -liga, -dlig
            font-style = Retina
            font-family-italic = "VictorMono Nerd Font"
            font-family-bold-italic = "VictorMono Nerd Font"
            font-size = 13.5
            """)
    }

    @Test func regularStyleAndOwnItalicsAreLeftOut() {
        let selection = FontSelection(family: "Menlo", style: "Regular", italicFamily: "Menlo")
        let text = GhosttyConfig.snippet(selection)
        #expect(!text.contains("font-style"))
        #expect(!text.contains("font-family-italic"))
    }

    /// The include is loaded after the user's config, where these keys append rather than
    /// replace. Each has to be emptied before it is set.
    @Test func managedFileEmptiesEveryListBeforeSettingIt() throws {
        let lines = GhosttyConfig.managedFile(FontSelection(family: "Menlo", features: ["ss01": 1]))
            .split(separator: "\n").map(String.init)
        let set = try #require(lines.firstIndex(of: "font-family = \"Menlo\""))
        for key in ["font-family", "font-family-bold", "font-family-italic", "font-family-bold-italic"] {
            let reset = try #require(lines.firstIndex(of: "\(key) = \"\""))
            #expect(reset < set)
        }
        let featureReset = try #require(lines.firstIndex(of: "font-feature = \"\""))
        let featureSet = try #require(lines.firstIndex(of: "font-feature = ss01"))
        #expect(featureReset < featureSet)
        // A style left over in the main config must not survive either.
        #expect(lines.contains("font-style = default"))
    }

    @Test func featureListsRoundTrip() {
        let features = ["ss01": 1, "cv10": 3, "zero": 1]
        #expect(GhosttyConfig.parseFeatures(GhosttyConfig.featureList(features)) == features)
        #expect(GhosttyConfig.parseFeatures("ss01,ss02 , cv01=2") == ["ss01": 1, "ss02": 1, "cv01": 2])
        #expect(GhosttyConfig.parseFeatures("") == [:])
    }

    @Test func wholeSizesHaveNoDecimalPoint() {
        #expect(GhosttyConfig.sizeString(14) == "14")
        #expect(GhosttyConfig.sizeString(13.5) == "13.5")
    }
}

@Suite struct ConfigLocationTests {
    let home: URL

    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("fontpicker-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    private var appSupport: URL { home.appendingPathComponent("Library/Application Support/com.mitchellh.ghostty") }
    private var xdg: URL { home.appendingPathComponent(".config/ghostty") }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func mainConfig(xdgHome: String? = nil) -> URL {
        GhosttyPaths.mainConfig(environment: xdgHome.map { ["XDG_CONFIG_HOME": $0] } ?? [:], home: home)
    }

    @Test func nothingInstalledMeansApplicationSupport() {
        #expect(mainConfig() == appSupport.appendingPathComponent("config.ghostty"))
    }

    @Test func applicationSupportWinsOverXDG() throws {
        try write("a = 1\n", to: appSupport.appendingPathComponent("config.ghostty"))
        try write("a = 1\n", to: xdg.appendingPathComponent("config.ghostty"))
        #expect(mainConfig() == appSupport.appendingPathComponent("config.ghostty"))
    }

    /// Ghostty creates an empty `config.ghostty` on first launch. It doesn't count.
    @Test func anEmptyFileIsTreatedAsMissing() throws {
        try write("", to: appSupport.appendingPathComponent("config.ghostty"))
        try write("a = 1\n", to: xdg.appendingPathComponent("config"))
        #expect(mainConfig() == xdg.appendingPathComponent("config"))
    }

    @Test func theOldFileNameIsUsedWhenItIsTheOnlyOne() throws {
        try write("a = 1\n", to: appSupport.appendingPathComponent("config"))
        #expect(mainConfig() == appSupport.appendingPathComponent("config"))
    }

    @Test func xdgConfigHomeIsHonoured() throws {
        let custom = home.appendingPathComponent("elsewhere")
        try write("a = 1\n", to: custom.appendingPathComponent("ghostty/config.ghostty"))
        #expect(mainConfig(xdgHome: custom.path) == custom.appendingPathComponent("ghostty/config.ghostty"))
    }

    @Test func linkingAppendsOneLineAndLeavesTheRestAlone() throws {
        let config = appSupport.appendingPathComponent("config.ghostty")
        try write("theme = dark\nfont-family = \"Menlo\"", to: config)
        let installer = GhosttyInstaller(mainConfig: config)
        #expect(!installer.isLinked)

        try installer.link()
        try installer.link()
        let text = try String(contentsOf: config, encoding: .utf8)
        #expect(text.hasPrefix("theme = dark\nfont-family = \"Menlo\"\n"))
        #expect(text.components(separatedBy: GhosttyInstaller.includeLine).count == 2)
        #expect(installer.isLinked)
    }

    @Test func linkingCreatesAMissingConfig() throws {
        let installer = GhosttyInstaller(mainConfig: xdg.appendingPathComponent("config.ghostty"))
        try installer.link()
        #expect(installer.isLinked)
    }

    @Test func aHandWrittenIncludeLineCountsAsLinked() throws {
        let config = appSupport.appendingPathComponent("config.ghostty")
        for line in ["config-file = fontpicker.ghostty", "config-file=\"?fontpicker.ghostty\"", "config-file = ?/abs/path/fontpicker.ghostty"] {
            try write(line + "\n", to: config)
            #expect(GhosttyInstaller(mainConfig: config).isLinked, "\(line)")
        }
        try write("config-file = other.ghostty\n# config-file = ?fontpicker.ghostty\n", to: config)
        #expect(!GhosttyInstaller(mainConfig: config).isLinked)
    }

    @Test func writeThenRestorePutsThePreviousIncludeBack() throws {
        let installer = GhosttyInstaller(mainConfig: appSupport.appendingPathComponent("config.ghostty"))
        let first = try installer.write(FontSelection(family: "Menlo"))
        #expect(first == nil)
        let second = try installer.write(FontSelection(family: "Monaco"))
        #expect(second == GhosttyConfig.managedFile(FontSelection(family: "Menlo")))

        try installer.restore(second)
        #expect(try String(contentsOf: installer.include, encoding: .utf8) == second)
        try installer.restore(nil)
        #expect(!FileManager.default.fileExists(atPath: installer.include.path))
    }

    @Test func unlinkingRemovesTheIncludeAndItsLine() throws {
        let config = appSupport.appendingPathComponent("config.ghostty")
        try write("theme = dark\n", to: config)
        let installer = GhosttyInstaller(mainConfig: config)
        try installer.write(FontSelection(family: "Menlo"))
        try installer.link()

        try installer.unlink()
        #expect(try String(contentsOf: config, encoding: .utf8) == "theme = dark\n")
        #expect(!FileManager.default.fileExists(atPath: installer.include.path))
    }
}

@Suite struct ReloadSignalTests {
    /// Signalling a Ghostty that doesn't handle SIGUSR2 would terminate it, so anything
    /// that can't be shown to be 1.2.0 or later has to be refused.
    @Test(arguments: [
        ("1.2.0", true), ("1.2.3", true), ("1.3.1", true), ("2.0", true), ("1.10.0", true),
        ("1.1.3", false), ("1.0.0", false), ("0.9", false), ("", false), ("tip", false),
    ])
    func onlyVersionsWithTheHandlerAreSignalled(version: String, expected: Bool) {
        #expect(GhosttyApp.supportsReloadSignal(version) == expected)
    }

    @Test func anUnknownVersionIsNeverSignalled() {
        #expect(!GhosttyApp.supportsReloadSignal(nil))
    }
}
