import CoreText
import Foundation

/// The terminal cell a font produces, computed the way Ghostty's Core Text backend does
/// it (`src/font/face/coretext.zig` and `src/font/Metrics.zig` in Ghostty 1.3), so the
/// preview's grid matches the real one.
public struct CellMetrics: Equatable, Sendable {
    /// Widest printable ASCII advance, in ems. Ghostty sizes the cell from the widest
    /// glyph, not the commonest, so one stray wide glyph widens every column.
    public var faceWidth: Double
    /// Ascent, descent (negative) and line gap in ems, from whichever table Ghostty trusts.
    public var ascent: Double
    public var descent: Double
    public var lineGap: Double

    public var lineHeight: Double { ascent - descent + lineGap }

    /// Reads the design metrics from a font. They don't depend on its size.
    public init(_ font: CTFont) {
        let size = Double(CTFontGetSize(font))

        var characters = (0x20...0x7E).map { UniChar($0) }
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count)
        var advances = [CGSize](repeating: .zero, count: glyphs.count)
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyphs, &advances, glyphs.count)
        faceWidth = Double(advances.map(\.width).max() ?? 0) / size

        let vertical = Self.verticalMetrics(font)
        ascent = vertical.ascent
        descent = vertical.descent
        lineGap = vertical.lineGap
    }

    /// The cell in points for a font size and display scale. Ghostty rounds the cell to
    /// whole device pixels and centres the face in whatever the rounding added or removed.
    public func cell(size: Double, scale: Double) -> Cell {
        let pixelsPerEm = size * scale
        let faceWidth = self.faceWidth * pixelsPerEm
        let faceHeight = lineHeight * pixelsPerEm
        let width = max(1, faceWidth.rounded())
        let height = max(1, faceHeight.rounded())
        let faceBaseline = lineGap * pixelsPerEm / 2 - descent * pixelsPerEm
        let baseline = (faceBaseline - (height - faceHeight) / 2).rounded()
        return Cell(
            width: width / scale, height: height / scale, baseline: baseline / scale,
            inset: (width - faceWidth) / 2 / scale)
    }

    public struct Cell: Equatable, Sendable {
        public var width: Double
        public var height: Double
        /// Baseline height above the bottom of the cell.
        public var baseline: Double
        /// Horizontal offset that centres the face in the rounded cell.
        public var inset: Double
    }

    /// Ghostty's order of preference: OS/2 typo metrics when the font asks for them,
    /// otherwise `hhea`, then OS/2 typo, then OS/2 win. Core Text's own numbers are the
    /// fallback when the tables can't be read.
    static func verticalMetrics(_ font: CTFont) -> (ascent: Double, descent: Double, lineGap: Double) {
        let size = Double(CTFontGetSize(font))
        let fallback = (Double(CTFontGetAscent(font)) / size, -Double(CTFontGetDescent(font)) / size, Double(CTFontGetLeading(font)) / size)
        guard let hhea = table("hhea", font), hhea.count >= 10 else { return fallback }

        let unitsPerEm: Double = {
            if let head = table("head", font), head.count >= 20 { return Double(u16(head, 18)) }
            return Double(CTFontGetUnitsPerEm(font))
        }()
        guard unitsPerEm > 0 else { return fallback }
        func ems(_ a: Int, _ d: Int, _ g: Int) -> (Double, Double, Double) {
            (Double(a) / unitsPerEm, Double(d) / unitsPerEm, Double(g) / unitsPerEm)
        }

        let hheaMetrics = ems(i16(hhea, 4), i16(hhea, 6), i16(hhea, 8))
        guard let os2 = table("OS/2", font), os2.count >= 78 else { return hheaMetrics }

        let typo = ems(i16(os2, 68), i16(os2, 70), i16(os2, 72))
        let useTypoMetrics = u16(os2, 62) & 0x80 != 0
        if useTypoMetrics { return typo }
        if i16(hhea, 4) != 0 || i16(hhea, 6) != 0 { return hheaMetrics }
        if i16(os2, 68) != 0 || i16(os2, 70) != 0 { return typo }
        // usWinDescent is positive-down, unlike the other two descents.
        return ems(u16(os2, 74), -u16(os2, 76), 0)
    }

    private static func table(_ tag: String, _ font: CTFont) -> [UInt8]? {
        let code = tag.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return (CTFontCopyTable(font, CTFontTableTag(code), []) as Data?).map { [UInt8]($0) }
    }

    private static func u16(_ bytes: [UInt8], _ offset: Int) -> Int {
        Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
    }

    private static func i16(_ bytes: [UInt8], _ offset: Int) -> Int {
        Int(Int16(bitPattern: UInt16(u16(bytes, offset))))
    }
}
