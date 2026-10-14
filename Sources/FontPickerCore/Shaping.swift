import CoreText
import Foundation

/// Builds Core Text fonts the way Ghostty's config describes them: a family name, an
/// optional named style, and a list of OpenType feature settings.
public enum FontFactory {
    public static func descriptor(family: String, style: String? = nil) -> CTFontDescriptor {
        var attrs: [CFString: Any] = [kCTFontFamilyNameAttribute: family]
        if let style, !style.isEmpty { attrs[kCTFontStyleNameAttribute] = style }
        return CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
    }

    /// Returns nil when the family isn't installed. Core Text would otherwise quietly hand
    /// back a substitute.
    public static func font(family: String, style: String? = nil, size: CGFloat) -> CTFont? {
        let font = CTFontCreateWithFontDescriptor(descriptor(family: family, style: style), size, nil)
        guard (CTFontCopyFamilyName(font) as String) == family else { return nil }
        return font
    }

    /// A copy of `font` with the given features set. Later entries win over earlier ones.
    public static func applying(_ features: [(tag: String, value: Int)], to font: CTFont) -> CTFont {
        guard !features.isEmpty else { return font }
        let settings = features.map {
            [kCTFontOpenTypeFeatureTag: $0.tag, kCTFontOpenTypeFeatureValue: $0.value] as [CFString: Any]
        }
        let descriptor = CTFontDescriptorCreateWithAttributes(
            [kCTFontFeatureSettingsAttribute: settings] as CFDictionary)
        return CTFontCreateCopyWithAttributes(font, 0, nil, descriptor)
    }

    /// The feature list for a selection, in the order Ghostty applies it: the chosen
    /// features, then the ligature switch-offs.
    public static func featureList(_ features: [String: Int], ligatures: Bool) -> [(tag: String, value: Int)] {
        var list = features.filter { $0.value > 0 }.sorted { $0.key < $1.key }.map { (tag: $0.key, value: $0.value) }
        if !ligatures {
            list += GhosttyConfig.ligatureTags.map { (tag: $0, value: 0) }
        }
        return list
    }

    /// The same face with bold and/or italic added, or nil if the family has no such face.
    public static func variant(of font: CTFont, bold: Bool, italic: Bool) -> CTFont? {
        var want: CTFontSymbolicTraits = []
        if bold { want.insert(.traitBold) }
        if italic { want.insert(.traitItalic) }
        let mask: CTFontSymbolicTraits = [.traitBold, .traitItalic]
        guard let copy = CTFontCreateCopyWithSymbolicTraits(font, 0, nil, want, mask) else { return nil }
        // Core Text can return the nearest match rather than failing, so check what came back.
        let got = CTFontGetSymbolicTraits(copy).intersection(mask)
        guard got == want, (CTFontCopyFamilyName(copy) as String) == (CTFontCopyFamilyName(font) as String) else {
            return nil
        }
        return copy
    }
}

/// Shapes text and reports glyph IDs. Comparing the output for two feature settings is how
/// the probe finds out what a feature does, without reading the font's substitution tables.
public enum Shaper {
    public static func glyphs(_ text: String, _ font: CTFont) -> [CGGlyph] {
        let attributed = NSAttributedString(
            string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attributed)
        var out: [CGGlyph] = []
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var buffer = [CGGlyph](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &buffer)
            out += buffer
        }
        return out
    }

    /// The advance of `text`'s first glyph in ems, or nil if the font has no glyph for it.
    public static func advance(_ text: String, _ font: CTFont) -> Double? {
        let units = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        guard CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count), glyphs[0] != 0 else { return nil }
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyphs, &advance, 1)
        return Double(advance.width / CTFontGetSize(font))
    }
}
