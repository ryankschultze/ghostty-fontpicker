import Foundation

/// How the rail groups families, in display order.
public enum FontGroup: String, Codable, CaseIterable, Sendable {
    case ligatures = "A"
    case alternates = "B"
    case plain = "C"
    case pixel = "P"

    public var title: String {
        switch self {
        case .ligatures: return "Ligatures and alternates"
        case .alternates: return "Alternates, no ligatures"
        case .plain: return "Plain"
        case .pixel: return "Pixel and bitmap"
        }
    }
}

public enum ItalicKind: String, Codable, Sendable {
    case none, italic, oblique, both
}

/// One switchable OpenType feature and what it visibly changes.
public struct FontFeature: Codable, Hashable, Identifiable, Sendable {
    /// Four-letter OpenType tag, e.g. `ss01` or `cv10`.
    public var tag: String
    /// The font's own name for the feature, when it has one.
    public var name: String?
    /// Single characters whose glyph changes.
    public var chars: String
    /// Tested sequences that change without any of their characters changing alone.
    public var sequences: [String]
    /// Number of "on" values: 1 for a switch, more for a character variant with alternates.
    public var alternates: Int

    public var id: String { tag }

    public init(tag: String, name: String? = nil, chars: String = "", sequences: [String] = [], alternates: Int = 1) {
        self.tag = tag
        self.name = name
        self.chars = chars
        self.sequences = sequences
        self.alternates = alternates
    }
}

/// A fixed-width family as Ghostty would name it, with everything the rail needs.
public struct FontFamily: Codable, Hashable, Identifiable, Sendable {
    /// The value for Ghostty's `font-family`.
    public var family: String
    /// Friendlier display name.
    public var short: String
    public var group: FontGroup
    public var isNerdFont: Bool
    public var note: String?
    /// Features worth switching on the first time the family is selected.
    public var preset: [String]
    public var cursive: Bool
    /// Upright style names, lightest first. Values for Ghostty's `font-style`.
    public var styles: [String]
    public var italic: ItalicKind
    /// Stylistic sets and other optional switches present in the font, sorted by tag.
    public var setTags: [String]
    /// Character variant tags present in the font.
    public var cvTags: [String]
    /// Tested sequences that form a ligature with no configuration.
    public var ligs: [String]
    /// How many tested sequences form a ligature with every optional set switched on.
    public var ligMax: Int
    /// Cell width, x-height and line height in ems.
    public var advance: Double
    public var xHeight: Double
    public var lineHeight: Double

    public var id: String { family }
    public var ligDefault: Int { ligs.count }
    public var stylisticSetCount: Int { setTags.filter(FontProbe.isStylisticSet).count }
}

/// The per-feature breakdown for a family. Slower to compute than `FontFamily`, so it is
/// produced on demand and cached.
public struct FontDetail: Codable, Hashable, Sendable {
    public var features: [FontFeature]
    public var variants: [FontFeature]
    /// Features in the font that change nothing in the tested characters and sequences.
    public var hidden: Int

    public init(features: [FontFeature] = [], variants: [FontFeature] = [], hidden: Int = 0) {
        self.features = features
        self.variants = variants
        self.hidden = hidden
    }

    public var all: [FontFeature] { features + variants }
}

/// Everything that ends up in the Ghostty config for one choice of font.
public struct FontSelection: Codable, Equatable, Sendable {
    public var family: String
    /// Active features by tag. A value of 1 is plain "on"; higher values pick an alternate.
    public var features: [String: Int]
    public var ligatures: Bool
    /// A named upright style such as `Light` or `Retina`. Nil or `Regular` means the default.
    public var style: String?
    /// Take italics from another family.
    public var italicFamily: String?
    /// Points.
    public var size: Double

    public init(
        family: String, features: [String: Int] = [:], ligatures: Bool = true,
        style: String? = nil, italicFamily: String? = nil, size: Double = 14
    ) {
        self.family = family
        self.features = features
        self.ligatures = ligatures
        self.style = style
        self.italicFamily = italicFamily
        self.size = size
    }

    /// The style to hand Ghostty, or nil when the default is right.
    public var namedStyle: String? {
        guard let style, !style.isEmpty, style != "Regular" else { return nil }
        return style
    }
}
