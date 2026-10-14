import CoreText
import Foundation

/// Works out what a font's optional features do by shaping text with each one off and on.
public enum FontProbe {
    /// Sequences that programming fonts commonly turn into ligatures.
    public static let ligatureTests: [String] = [
        "->", "=>", "!=", "!==", "==", "===", ">=", "<=", "<-", "<->", "<=>", "|>", "<|",
        "::", ":=", "=:=", "..", "...", "<!--", "-->", "//", "/*", "*/", "&&", "||", "++",
        "--", "##", "###", "<>", "~>", "<~", "=~", "!~", ">>", "<<", ">>=", "?.", "www",
        "fi", "fl", "ffi", "0x1F", "1x2",
    ]

    /// Printable ASCII, the characters a feature is checked against one at a time.
    static let asciiCharacters: [String] = (0x21...0x7E).map { String(UnicodeScalar($0)!) }

    /// Optional switches worth offering besides the numbered stylistic sets.
    static let namedSwitches: Set<String> = ["ital", "onum", "salt", "zero", "dlig", "smcp", "c2sc"]

    /// Size used for probing. Substitutions don't depend on it.
    static let probeSize: CGFloat = 16

    public static func isStylisticSet(_ tag: String) -> Bool {
        tag.count == 4 && tag.hasPrefix("ss") && tag.dropFirst(2).allSatisfy(\.isNumber)
    }

    public static func isCharacterVariant(_ tag: String) -> Bool {
        tag.count == 4 && tag.hasPrefix("cv") && tag.dropFirst(2).allSatisfy(\.isNumber)
    }

    // MARK: Feature tags

    /// Feature tags listed in the font's GSUB table, sorted and de-duplicated.
    public static func gsubTags(_ font: CTFont) -> [String] {
        guard let table = CTFontCopyTable(font, CTFontTableTag(kCTFontTableGSUB), []) as Data? else { return [] }
        let bytes = [UInt8](table)
        func u16(_ offset: Int) -> Int? {
            guard offset >= 0, offset + 1 < bytes.count else { return nil }
            return Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
        }
        // Header: version (4 bytes), ScriptList, FeatureList, LookupList offsets.
        guard let featureList = u16(6), let count = u16(featureList) else { return [] }
        var tags = Set<String>()
        for index in 0..<count {
            let record = featureList + 2 + index * 6
            guard record + 4 <= bytes.count else { break }
            if let tag = String(bytes: bytes[record..<record + 4], encoding: .ascii) { tags.insert(tag) }
        }
        return tags.sorted()
    }

    /// Tags offered as switches, sorted by tag.
    public static func optionalTags(in tags: [String]) -> [String] {
        tags.filter { isStylisticSet($0) || namedSwitches.contains($0) }
    }

    struct FeatureLabel {
        var name: String?
        var alternates: Int?
    }

    /// Names and alternate counts as Core Text reports them, keyed by OpenType tag.
    static func labels(_ font: CTFont) -> [String: FeatureLabel] {
        guard let features = CTFontCopyFeatures(font) as? [[String: Any]] else { return [:] }
        let tagKey = "CTFeatureOpenTypeTag"
        var out: [String: FeatureLabel] = [:]
        for feature in features {
            let selectors = feature[kCTFontFeatureTypeSelectorsKey as String] as? [[String: Any]] ?? []
            if let tag = feature[tagKey] as? String {
                // A feature with its own tag lists one selector per value, "Off" included.
                let name = feature[kCTFontFeatureTypeNameKey as String] as? String
                out[tag] = FeatureLabel(name: cleanName(name, tag: tag), alternates: max(1, selectors.count - 1))
            } else {
                for selector in selectors {
                    guard let tag = selector[tagKey] as? String else { continue }
                    let name = selector[kCTFontFeatureSelectorNameKey as String] as? String
                    out[tag] = FeatureLabel(name: cleanName(name, tag: tag), alternates: nil)
                }
            }
        }
        return out
    }

    /// Drops the generic names Core Text makes up ("Stylistic Set 3") and the tag prefix
    /// some fonts repeat ("SS01: Equal Symbols").
    static func cleanName(_ raw: String?, tag: String) -> String? {
        guard var name = raw?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        let prefix = tag.uppercased() + ":"
        if name.uppercased().hasPrefix(prefix) {
            name = String(name.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        let generic = ["Stylistic Set ", "Character Variant ", "Stylistic Alternates", "Alternative Stylistic Sets"]
        if name.isEmpty || name == "On" || generic.contains(where: { name.hasPrefix($0) }) { return nil }
        return name
    }

    // MARK: Ligatures

    /// Tested sequences that `font` draws differently from its characters shaped one by one.
    public static func ligatures(in font: CTFont) -> [String] {
        var single: [Character: [CGGlyph]] = [:]
        return ligatureTests.filter { sequence in
            let apart = sequence.flatMap { character -> [CGGlyph] in
                if let cached = single[character] { return cached }
                let glyphs = Shaper.glyphs(String(character), font)
                single[character] = glyphs
                return glyphs
            }
            return Shaper.glyphs(sequence, font) != apart
        }
    }

    /// How many tested sequences can form a ligature: the defaults plus whatever each
    /// optional set adds. Sets are tried one at a time because they interfere with each
    /// other (Geist's ss10 reshapes the brackets that its ss11 ligatures are built from).
    public static func ligatureCeiling(in font: CTFont, defaults: [String], optionalTags: [String]) -> Int {
        var reachable = Set(defaults)
        for tag in optionalTags where isStylisticSet(tag) || tag == "dlig" {
            reachable.formUnion(ligatures(in: FontFactory.applying([(tag, 1)], to: font)))
        }
        return reachable.count
    }

    // MARK: Per-feature detail

    /// What each optional feature of `family` changes. Shapes a few hundred strings per
    /// feature, so call it off the main thread.
    public static func detail(for family: FontFamily) -> FontDetail {
        guard let base = FontFactory.font(family: family.family, size: probeSize) else { return FontDetail() }
        let labels = labels(base)
        var detail = FontDetail()
        for tag in family.setTags {
            if let feature = probe(tag: tag, base: base, label: labels[tag]) { detail.features.append(feature) } else { detail.hidden += 1 }
        }
        for tag in family.cvTags {
            if let feature = probe(tag: tag, base: base, label: labels[tag]) { detail.variants.append(feature) } else { detail.hidden += 1 }
        }
        return detail
    }

    /// Returns nil when the feature changes nothing we test.
    static func probe(tag: String, base: CTFont, label: FeatureLabel?) -> FontFeature? {
        let off = FontFactory.applying([(tag, 0)], to: base)
        let on = FontFactory.applying([(tag, 1)], to: base)
        let chars = asciiCharacters.filter { Shaper.glyphs($0, on) != Shaper.glyphs($0, off) }
        let changed = Set(chars.map { Character($0) })
        let sequences = ligatureTests.filter { sequence in
            !sequence.contains(where: changed.contains) && Shaper.glyphs(sequence, on) != Shaper.glyphs(sequence, off)
        }
        guard !chars.isEmpty || !sequences.isEmpty else { return nil }

        let samples = chars + sequences
        let alternates = label?.alternates ?? countAlternates(tag: tag, base: base, samples: samples, off: off, on: on)
        return FontFeature(tag: tag, name: label?.name, chars: chars.joined(), sequences: sequences, alternates: alternates)
    }

    /// Steps the feature value up until the output stops changing or falls back to "off".
    static func countAlternates(tag: String, base: CTFont, samples: [String], off: CTFont, on: CTFont) -> Int {
        guard isCharacterVariant(tag) || tag == "salt" else { return 1 }
        let offGlyphs = samples.map { Shaper.glyphs($0, off) }
        var previous = samples.map { Shaper.glyphs($0, on) }
        var count = 1
        for value in 2...12 {
            let font = FontFactory.applying([(tag, value)], to: base)
            let glyphs = samples.map { Shaper.glyphs($0, font) }
            if glyphs == offGlyphs || glyphs == previous { break }
            previous = glyphs
            count = value
        }
        return count
    }
}
