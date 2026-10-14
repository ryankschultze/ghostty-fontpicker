import CoreText
import FontPickerCore
import SwiftUI

/// Everything that decides how a pane of sample text looks.
struct RenderSpec: Hashable {
    var family: String
    /// A named upright style; nil for the family's default.
    var style: String?
    var features: [String: Int]
    var ligatures: Bool
    var italicFamily: String?
    /// Points.
    var size: Double
}

/// The four faces Ghostty would pick for a spec, built by the same rules: bold and italic
/// come from the family when it has them and are synthesized when it doesn't.
final class FontSet {
    struct Face {
        let font: CTFont
        /// Thicken with a stroke, as Ghostty does when the family has no bold.
        let syntheticBold: Bool
    }

    /// Ghostty's synthetic italic: a 15 degree skew.
    private static let italicSkew = CGAffineTransform(a: 1, b: 0, c: 0.267949, d: 1, tx: 0, ty: 0)

    let regular: Face
    let bold: Face
    let italic: Face
    let boldItalic: Face
    let metrics: CellMetrics

    init(_ spec: RenderSpec) {
        let size = CGFloat(spec.size)
        let base = FontFactory.font(family: spec.family, size: size) ?? CTFontCreateWithName("Menlo" as CFString, size, nil)
        let upright = spec.style.flatMap { FontFactory.font(family: spec.family, style: $0, size: size) } ?? base
        let features = FontFactory.featureList(spec.features, ligatures: spec.ligatures)

        func finished(_ font: CTFont, skewed: Bool = false) -> CTFont {
            let featured = FontFactory.applying(features, to: font)
            guard skewed else { return featured }
            var matrix = Self.italicSkew
            return CTFontCreateCopyWithAttributes(featured, 0, &matrix, nil)
        }

        // `font-style` only renames the regular face. Bold and italic are looked up in the
        // family from its default, the way Ghostty searches for style variants.
        let italicSource = spec.italicFamily.flatMap { FontFactory.font(family: $0, size: size) }
        let italicBase = italicSource ?? base
        let realBold = FontFactory.variant(of: base, bold: true, italic: false)
        let realItalic = FontFactory.variant(of: italicBase, bold: false, italic: true)

        regular = Face(font: finished(upright), syntheticBold: false)
        bold = realBold.map { Face(font: finished($0), syntheticBold: false) }
            ?? Face(font: finished(upright), syntheticBold: true)
        italic = realItalic.map { Face(font: finished($0), syntheticBold: false) }
            ?? Face(font: finished(italicSource ?? upright, skewed: true), syntheticBold: false)

        if let real = FontFactory.variant(of: italicBase, bold: true, italic: true) {
            boldItalic = Face(font: finished(real), syntheticBold: false)
        } else if let realItalic {
            boldItalic = Face(font: finished(realItalic), syntheticBold: true)
        } else if let realBold, italicSource == nil {
            boldItalic = Face(font: finished(realBold, skewed: true), syntheticBold: false)
        } else {
            boldItalic = Face(font: finished(italicSource ?? upright, skewed: true), syntheticBold: true)
        }
        metrics = CellMetrics(regular.font)
    }

    func face(bold: Bool, italic: Bool) -> Face {
        switch (bold, italic) {
        case (false, false): return regular
        case (true, false): return self.bold
        case (false, true): return self.italic
        case (true, true): return boldItalic
        }
    }

    // Views rebuild often and a spec resolves to the same faces every time.
    @MainActor private static var cache: [RenderSpec: FontSet] = [:]

    @MainActor static func resolve(_ spec: RenderSpec) -> FontSet {
        if let hit = cache[spec] { return hit }
        if cache.count > 200 { cache.removeAll() }
        let set = FontSet(spec)
        cache[spec] = set
        return set
    }
}

/// A pane of sample text laid out on a terminal grid.
struct TerminalCanvas: View {
    let lines: [TermLine]
    let spec: RenderSpec
    let palette: TermPalette
    var padding = CGSize(width: 16, height: 14)

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let fonts = FontSet.resolve(spec)
        let cell = fonts.metrics.cell(size: spec.size, scale: displayScale)
        let columns = lines.map { $0.reduce(0) { $0 + $1.text.count } }.max() ?? 0
        let size = CGSize(
            width: Double(columns) * cell.width + padding.width * 2,
            height: Double(lines.count) * cell.height + padding.height * 2)
        Canvas { context, _ in
            context.withCGContext { cg in
                TerminalRenderer(
                    fonts: fonts, cell: cell, palette: palette, size: size, padding: padding, scale: displayScale
                ).draw(lines, in: cg)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityLabel("Sample text in \(spec.family)")
    }
}

/// Draws text the way a terminal does: Core Text shapes each line, then every glyph is
/// placed in the cell of the character it came from rather than at its natural advance.
/// That keeps columns aligned through icons and through faces borrowed from another
/// family, and it shows ligatures exactly as wide as the characters they replace.
struct TerminalRenderer {
    let fonts: FontSet
    let cell: CellMetrics.Cell
    let palette: TermPalette
    let size: CGSize
    let padding: CGSize
    let scale: CGFloat

    private static let spanKey = NSAttributedString.Key("fontpicker.span")
    private static let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)

    func draw(_ lines: [TermLine], in cg: CGContext) {
        cg.saveGState()
        defer { cg.restoreGState() }
        // SwiftUI hands over a top-left origin; Core Text wants y pointing up.
        cg.translateBy(x: 0, y: size.height)
        cg.scaleBy(x: 1, y: -1)
        cg.textMatrix = .identity
        // Ghostty leaves `font-thicken` off, so no LCD-style smoothing here either.
        cg.setShouldSmoothFonts(false)

        for (row, line) in lines.enumerated() {
            let cellBottom = size.height - padding.height - Double(row + 1) * cell.height
            draw(line, baseline: cellBottom + cell.baseline, cellBottom: cellBottom, in: cg)
        }
    }

    private func draw(_ line: TermLine, baseline: Double, cellBottom: Double, in cg: CGContext) {
        let text = NSMutableAttributedString()
        for (index, span) in line.enumerated() {
            let face = fonts.face(bold: span.bold, italic: span.italic)
            text.append(NSAttributedString(string: span.text, attributes: [Self.fontKey: face.font, Self.spanKey: index]))
        }
        let characters = Array(text.string)
        // UTF-16 offset to column. Every character in the samples is one cell wide.
        var columnAt: [Int] = []
        for (column, character) in characters.enumerated() {
            columnAt.append(contentsOf: repeatElement(column, count: character.utf16.count))
        }

        let shaped = CTLineCreateWithAttributedString(text)
        for run in CTLineGetGlyphRuns(shaped) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = attributes[kCTFontAttributeName as String] as! CTFont
            let span = line[(attributes[Self.spanKey.rawValue] as? Int) ?? 0]
            let face = fonts.face(bold: span.bold, italic: span.italic)

            var glyphs = [CGGlyph](repeating: 0, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)

            let color = palette.color(span.color).cgColor
            cg.setFillColor(color)
            if face.syntheticBold {
                // Ghostty strokes at max(points / 14, 1) device pixels.
                cg.setTextDrawingMode(.fillStroke)
                cg.setStrokeColor(color)
                cg.setLineWidth(max(CTFontGetSize(face.font) / 14, 1) / scale)
            } else {
                cg.setTextDrawingMode(.fill)
            }

            // Core Text swapped in another font for these: the selected one has no glyph.
            let substituted = !CFEqual(runFont, face.font)
            var plainGlyphs: [CGGlyph] = []
            var plainPositions: [CGPoint] = []
            for k in 0..<count {
                let column = columnAt[min(indices[k], columnAt.count - 1)]
                let x = padding.width + Double(column) * cell.width
                let icon = Self.isIcon(characters[column])
                if substituted || icon {
                    var font = runFont
                    var glyph = glyphs[k]
                    // Core Text has nothing to substitute for an icon the font lacks, but
                    // Ghostty does: it carries its own Nerd Font symbols.
                    if substituted, icon, let scalar = characters[column].unicodeScalars.first,
                       let symbol = IconFallback.shared.glyph(for: scalar, size: CTFontGetSize(face.font)) {
                        font = symbol.font
                        glyph = symbol.glyph
                    }
                    // A symbol may spill into the next cell when that cell is blank and the
                    // one before isn't a symbol too.
                    let blankAfter = column + 1 >= characters.count || characters[column + 1] == " "
                    let symbolBefore = column > 0 && Self.isIcon(characters[column - 1])
                    drawFitted(
                        glyph, font: font, x: x, baseline: baseline, cellBottom: cellBottom,
                        cells: icon && blankAfter && !symbolBefore ? 2 : 1, centred: icon, in: cg)
                } else {
                    plainGlyphs.append(glyphs[k])
                    plainPositions.append(CGPoint(x: x + cell.inset, y: baseline))
                }
            }
            if !plainGlyphs.isEmpty {
                CTFontDrawGlyphs(runFont, plainGlyphs, plainPositions, plainGlyphs.count, cg)
            }
        }
    }

    /// Icons and substituted glyphs aren't designed for this grid, so they are scaled down
    /// to fit. Ghostty gives a Nerd Font symbol the full line height when it has two cells
    /// to itself and a height between cap height and line height when it has one, and
    /// centres it vertically; other substitutes keep their baseline.
    private func drawFitted(
        _ glyph: CGGlyph, font: CTFont, x: Double, baseline: Double, cellBottom: Double, cells: Int, centred: Bool,
        in cg: CGContext
    ) {
        var glyph = glyph
        var font = font
        var box = CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyph, nil, 1)
        guard box.width > 0, box.height > 0 else { return }
        let primary = fonts.regular.font
        let faceHeight = fonts.metrics.lineHeight * CTFontGetSize(primary)
        let maxHeight = centred && cells == 1 ? (2 * CTFontGetCapHeight(primary) + faceHeight) / 3 : faceHeight
        let fit = min(1, cell.width * Double(cells) / box.width, maxHeight / box.height)
        if fit < 1 {
            font = CTFontCreateCopyWithAttributes(font, CTFontGetSize(font) * fit, nil, nil)
            box = CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyph, nil, 1)
        }
        // Centre in its own cell unless it needs the second one.
        let left = box.width > cell.width ? x : x + (cell.width - box.width) / 2
        var y = centred ? cellBottom + (cell.height - box.height) / 2 - box.minY : baseline
        // Pull a glyph that pokes out back inside the cell.
        if y + box.minY < cellBottom { y = cellBottom - box.minY }
        if y + box.maxY > cellBottom + cell.height { y = cellBottom + cell.height - box.maxY }
        var position = CGPoint(x: left - box.minX, y: y)
        CTFontDrawGlyphs(font, &glyph, &position, 1, cg)
    }

    /// Private Use Area code points, where Nerd Fonts keep their icons.
    private static func isIcon(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first?.value else { return false }
        return (0xE000...0xF8FF).contains(scalar) || scalar >= 0xF0000
    }
}

/// Finds an installed font that has a given Nerd Font icon, standing in for the symbols
/// face built into Ghostty. That face is what makes icons show up in Ghostty even when
/// the chosen font, Menlo say, has none of its own.
final class IconFallback: @unchecked Sendable {
    static let shared = IconFallback()

    private let lock = NSLock()
    private var candidates: [String]?
    private var familyForScalar: [UInt32: String] = [:]

    func glyph(for scalar: Unicode.Scalar, size: CGFloat) -> (font: CTFont, glyph: CGGlyph)? {
        lock.lock()
        defer { lock.unlock() }
        if let family = familyForScalar[scalar.value] {
            return Self.lookUp(scalar, in: family, size: size)
        }
        for family in loadCandidates() {
            if let found = Self.lookUp(scalar, in: family, size: size) {
                familyForScalar[scalar.value] = family
                return found
            }
        }
        return nil
    }

    /// The symbols-only families first, since they are the same glyphs Ghostty embeds.
    private func loadCandidates() -> [String] {
        if let candidates { return candidates }
        let installed = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        let symbolsOnly = ["Symbols Nerd Font Mono", "Symbols Nerd Font"].filter(installed.contains)
        let found = symbolsOnly + installed.filter { $0.contains("Nerd Font") && !symbolsOnly.contains($0) }.sorted()
        candidates = found
        return found
    }

    private static func lookUp(_ scalar: Unicode.Scalar, in family: String, size: CGFloat) -> (font: CTFont, glyph: CGGlyph)? {
        guard let font = FontFactory.font(family: family, size: size) else { return nil }
        let units = Array(String(scalar).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        guard CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count), glyphs[0] != 0 else { return nil }
        return (font, glyphs[0])
    }
}
