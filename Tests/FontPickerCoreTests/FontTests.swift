import CoreText
import Foundation
import Testing

@testable import FontPickerCore

// These run against fonts that ship with macOS, so they hold on any Mac.

@Suite struct CatalogTests {
    @Test func menloIsAFixedWidthFamily() throws {
        let menlo = try #require(FontCatalog.summarize(family: "Menlo"))
        #expect(menlo.styles.contains("Regular"))
        #expect(menlo.styles.contains("Bold"))
        #expect(menlo.italic == .italic)
        #expect(!menlo.isNerdFont)
        #expect(abs(menlo.advance - 0.602) < 0.001)
    }

    @Test func proportionalAndMissingFamiliesAreLeftOut() {
        #expect(FontCatalog.summarize(family: "Helvetica") == nil)
        #expect(FontCatalog.summarize(family: "No Such Family 12345") == nil)
    }

    @Test func aMissingFamilyIsNotQuietlySubstituted() {
        #expect(FontFactory.font(family: "No Such Family 12345", size: 12) == nil)
        #expect(FontFactory.font(family: "Menlo", size: 12) != nil)
    }

    @Test func monoAndPropoVariantsHideOnlyBehindTheirPlainFamily() {
        let installed: Set<String> = ["Foo Nerd Font", "Foo Nerd Font Mono", "Foo Nerd Font Propo", "Bar Nerd Font Mono"]
        #expect(FontCatalog.isRedundantVariant("Foo Nerd Font Mono", installed: installed))
        #expect(FontCatalog.isRedundantVariant("Foo Nerd Font Propo", installed: installed))
        #expect(!FontCatalog.isRedundantVariant("Foo Nerd Font", installed: installed))
        #expect(!FontCatalog.isRedundantVariant("Bar Nerd Font Mono", installed: installed))
        #expect(!FontCatalog.isRedundantVariant("Roboto Mono", installed: installed))
    }

    @Test func shortNamesDropTheNerdFontSuffix() {
        #expect(FontCatalog.shortName("Hack Nerd Font") == "Hack")
        #expect(FontCatalog.shortName("Hack Nerd Font Mono") == "Hack (Mono)")
        #expect(FontCatalog.shortName("Menlo") == "Menlo")
    }

    @Test func everyDiscoveredFamilyIsListedOnce() {
        let families = FontCatalog.discover()
        #expect(families.contains { $0.family == "Menlo" })
        #expect(Set(families.map(\.family)).count == families.count)
    }
}

@Suite struct ProbeTests {
    @Test func tagsAreClassified() {
        #expect(FontProbe.isStylisticSet("ss01"))
        #expect(!FontProbe.isStylisticSet("ssty"))
        #expect(!FontProbe.isStylisticSet("cv01"))
        #expect(FontProbe.isCharacterVariant("cv99"))
        #expect(FontProbe.optionalTags(in: ["calt", "cv01", "liga", "ss02", "zero"]) == ["ss02", "zero"])
    }

    @Test func genericFeatureNamesAreDropped() {
        #expect(FontProbe.cleanName("SS01: Equal Symbols", tag: "ss01") == "Equal Symbols")
        #expect(FontProbe.cleanName("Stylistic Set 3", tag: "ss03") == nil)
        #expect(FontProbe.cleanName("Character Variant 12", tag: "cv12") == nil)
        #expect(FontProbe.cleanName("On", tag: "ital") == nil)
        #expect(FontProbe.cleanName("Slashed Zero", tag: "zero") == "Slashed Zero")
        #expect(FontProbe.cleanName(nil, tag: "ss01") == nil)
    }

    @Test func aFontWithoutSubstitutionsHasNoFeaturesOrLigatures() throws {
        let menlo = try #require(FontCatalog.summarize(family: "Menlo"))
        #expect(menlo.ligs.isEmpty)
        #expect(menlo.ligMax == 0)
        let detail = FontProbe.detail(for: menlo)
        #expect(detail.features.isEmpty)
        #expect(detail.variants.isEmpty)
    }
}

@Suite struct CellMetricsTests {
    /// Ghostty rounds the cell to whole device pixels, never more than half a pixel off
    /// the font's own advance and line height.
    @Test(arguments: [(12.0, 1.0), (13.0, 2.0), (14.0, 2.0), (13.5, 2.0), (17.0, 3.0)])
    func cellsAreWholeDevicePixels(size: Double, scale: Double) throws {
        let font = try #require(FontFactory.font(family: "Menlo", size: 16))
        let metrics = CellMetrics(font)
        let cell = metrics.cell(size: size, scale: scale)
        let width = cell.width * scale, height = cell.height * scale
        #expect(width == width.rounded())
        #expect(height == height.rounded())
        #expect(abs(width - metrics.faceWidth * size * scale) <= 0.5)
        #expect(abs(height - metrics.lineHeight * size * scale) <= 0.5)
        #expect(cell.baseline > 0 && cell.baseline < cell.height)
    }

    @Test func metricsDoNotDependOnTheSizeTheyWereReadAt() throws {
        let small = CellMetrics(try #require(FontFactory.font(family: "Menlo", size: 9)))
        let large = CellMetrics(try #require(FontFactory.font(family: "Menlo", size: 40)))
        #expect(abs(small.faceWidth - large.faceWidth) < 0.0005)
        #expect(abs(small.lineHeight - large.lineHeight) < 0.0005)
        #expect(small.descent < 0)
    }
}
