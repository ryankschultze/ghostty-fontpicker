import CoreText
import Foundation

/// Finds the fixed-width families installed on this Mac and measures them.
public enum FontCatalog {
    /// Every installed family that sits on a cell grid, in rail order: curated families
    /// first in their curated order, then the rest alphabetically.
    public static func discover() -> [FontFamily] {
        let names = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        let installed = Set(names)
        let families = names
            .filter { !$0.hasPrefix(".") && !isRedundantVariant($0, installed: installed) }
            .compactMap(summarize(family:))
        return families.sorted { a, b in
            let ai = SeedCatalog.index[a.family], bi = SeedCatalog.index[b.family]
            switch (ai, bi) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.short.localizedCaseInsensitiveCompare(b.short) == .orderedAscending
            }
        }
    }

    /// Measures one family, or returns nil if it isn't installed or isn't fixed-width.
    public static func summarize(family: String) -> FontFamily? {
        guard let font = FontFactory.font(family: family, size: FontProbe.probeSize),
              isFixedWidth(font) else { return nil }

        let seed = SeedCatalog.entry(for: family)
        let tags = FontProbe.gsubTags(font)
        let setTags = FontProbe.optionalTags(in: tags)
        let cvTags = tags.filter(FontProbe.isCharacterVariant)
        let ligs = FontProbe.ligatures(in: font)

        let ligMax = FontProbe.ligatureCeiling(in: font, defaults: ligs, optionalTags: setTags)

        let members = members(of: family)
        let size = Double(CTFontGetSize(font))
        let metrics = CellMetrics(font)
        return FontFamily(
            family: family,
            short: seed?.short ?? shortName(family),
            group: seed.flatMap { FontGroup(rawValue: $0.group) } ?? guessGroup(ligMax: ligMax, optional: setTags.count + cvTags.count),
            isNerdFont: seed != nil || family.contains("Nerd Font"),
            note: seed?.note,
            preset: seed?.preset.filter(setTags.contains) ?? [],
            cursive: seed?.cursive ?? false,
            styles: members.upright,
            italic: members.italic,
            setTags: setTags,
            cvTags: cvTags,
            ligs: ligs,
            ligMax: ligMax,
            advance: metrics.faceWidth,
            xHeight: Double(CTFontGetXHeight(font)) / size,
            lineHeight: metrics.lineHeight)
    }

    /// Nerd Fonts ship each family three times: plain, "Mono" (icons squeezed to one cell)
    /// and "Propo" (proportional icons). Ghostty resizes Nerd Font icons by its own rules
    /// whichever font they come from, so the three look the same there and only the plain
    /// one is listed when it's installed.
    static func isRedundantVariant(_ family: String, installed: Set<String>) -> Bool {
        for suffix in [" Mono", " Propo"] where family.hasSuffix(" Nerd Font" + suffix) {
            return installed.contains(String(family.dropLast(suffix.count)))
        }
        return false
    }

    /// Whether the font sits on a grid: nearly every printable ASCII character shares one
    /// advance. "Nearly" because real fonts have strays (Code New Roman's i, j and l;
    /// Monofur's hyphen) that a terminal puts on the grid anyway, while duospace designs
    /// with six or more wide letters are left out. Symbol fonts are skipped too. The
    /// font's own "monospaced" flag isn't reliable: Fira Code doesn't set it.
    static func isFixedWidth(_ font: CTFont) -> Bool {
        let fontClass = CTFontGetSymbolicTraits(font).rawValue & CTFontSymbolicTraits.classMaskTrait.rawValue
        guard fontClass != CTFontStylisticClass.symbolicClass.rawValue else { return false }
        var characters = (0x21...0x7E).map { UniChar($0) }
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        guard CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count) else { return false }
        var advances = [CGSize](repeating: .zero, count: glyphs.count)
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyphs, &advances, glyphs.count)

        // Count advances in font units so equal widths compare equal.
        let unitsPerPoint = Double(CTFontGetUnitsPerEm(font)) / Double(CTFontGetSize(font))
        var counts: [Int: Int] = [:]
        for advance in advances { counts[Int((Double(advance.width) * unitsPerPoint).rounded()), default: 0] += 1 }
        guard let mode = counts.max(by: { $0.value < $1.value }), mode.key > 0 else { return false }
        return Double(mode.value) >= 0.95 * Double(glyphs.count)
    }

    /// "FiraCode Nerd Font Mono" to "FiraCode (Mono)". Only used for families with no curated name.
    static func shortName(_ family: String) -> String {
        for (suffix, label) in [(" Nerd Font Mono", " (Mono)"), (" Nerd Font Propo", " (Propo)"), (" Nerd Font", "")] {
            if family.hasSuffix(suffix) { return String(family.dropLast(suffix.count)) + label }
        }
        return family
    }

    static func guessGroup(ligMax: Int, optional: Int) -> FontGroup {
        if ligMax >= 4 { return .ligatures }
        return optional > 0 ? .alternates : .plain
    }

    /// Upright style names (lightest first) and what kind of italics the family ships.
    static func members(of family: String) -> (upright: [String], italic: ItalicKind) {
        let query = FontFactory.descriptor(family: family)
        let matches = CTFontDescriptorCreateMatchingFontDescriptors(query, nil) as? [CTFontDescriptor] ?? []
        var upright: [(name: String, weight: Double)] = []
        var hasItalic = false, hasOblique = false
        for descriptor in matches {
            guard (CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String) == family,
                  let style = CTFontDescriptorCopyAttribute(descriptor, kCTFontStyleNameAttribute) as? String else { continue }
            let traits = CTFontDescriptorCopyAttribute(descriptor, kCTFontTraitsAttribute) as? [String: Any] ?? [:]
            let symbolic = CTFontSymbolicTraits(rawValue: (traits[kCTFontSymbolicTrait as String] as? UInt32) ?? 0)
            let slant = (traits[kCTFontSlantTrait as String] as? Double) ?? 0
            if symbolic.contains(.traitItalic) || slant != 0 {
                if style.localizedCaseInsensitiveContains("oblique") { hasOblique = true } else { hasItalic = true }
            } else if !upright.contains(where: { $0.name == style }) {
                upright.append((style, (traits[kCTFontWeightTrait as String] as? Double) ?? 0))
            }
        }
        upright.sort { ($0.weight, $0.name) < ($1.weight, $1.name) }
        let italic: ItalicKind = hasItalic && hasOblique ? .both : hasItalic ? .italic : hasOblique ? .oblique : .none
        return (upright.map(\.name), italic)
    }
}
