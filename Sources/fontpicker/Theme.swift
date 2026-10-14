import SwiftUI

/// A colour usable from both SwiftUI and Core Graphics.
struct RGB: Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    init(_ hex: UInt32, alpha: Double = 1) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}

/// The workbench palette, carried over from the specimen page.
struct Theme: Equatable {
    var isDark: Bool
    var bg: Color
    var surface: Color
    var ink: Color
    var muted: Color
    var rule: Color
    var accent: Color
    var accentInk: Color
    var chip: Color
    var chipOn: Color
    var glow: Color
    var danger: Color

    static let light = Theme(
        isDark: false, bg: RGB(0xF1F2F5).color, surface: RGB(0xFFFFFF).color, ink: RGB(0x181B21).color,
        muted: RGB(0x5B6270).color, rule: RGB(0xD8DBE2).color, accent: RGB(0x0B6E77).color,
        accentInk: RGB(0xFFFFFF).color, chip: RGB(0xE6E8ED).color, chipOn: RGB(0xD4EDEF).color,
        glow: RGB(0x0B6E77, alpha: 0.18).color, danger: RGB(0xBD3333).color)

    static let dark = Theme(
        isDark: true, bg: RGB(0x131519).color, surface: RGB(0x1B1E24).color, ink: RGB(0xE5E7EC).color,
        muted: RGB(0x99A0AD).color, rule: RGB(0x2D323B).color, accent: RGB(0x62C9D1).color,
        accentInk: RGB(0x08191B).color, chip: RGB(0x272B33).color, chipOn: RGB(0x1F4A4F).color,
        glow: RGB(0x62C9D1, alpha: 0.22).color, danger: RGB(0xEA7B7B).color)

    static func of(_ scheme: ColorScheme) -> Theme { scheme == .dark ? .dark : .light }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.light
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// The eight roles a span of sample text can take.
enum TermColor: Hashable {
    case fg, dim, green, yellow, blue, magenta, red, cyan
}

/// Colours for the terminal panes.
struct TermPalette: Hashable {
    var bg: RGB
    var edge: RGB
    var fg: RGB
    var dim: RGB
    var green: RGB
    var yellow: RGB
    var blue: RGB
    var magenta: RGB
    var red: RGB
    var cyan: RGB

    func color(_ role: TermColor) -> RGB {
        switch role {
        case .fg: return fg
        case .dim: return dim
        case .green: return green
        case .yellow: return yellow
        case .blue: return blue
        case .magenta: return magenta
        case .red: return red
        case .cyan: return cyan
        }
    }

    static func make(lightPane: Bool, appIsDark: Bool) -> TermPalette {
        if lightPane {
            return TermPalette(
                bg: RGB(0xFCFCFD), edge: appIsDark ? RGB(0x2D323B) : RGB(0xD8DBE2), fg: RGB(0x23262D),
                dim: RGB(0x7B8291), green: RGB(0x2C7A39), yellow: RGB(0x946500), blue: RGB(0x2160C4),
                magenta: RGB(0x873DBD), red: RGB(0xBD3333), cyan: RGB(0x0C747D))
        }
        return TermPalette(
            bg: appIsDark ? RGB(0x0B0C0F) : RGB(0x15171C), edge: appIsDark ? RGB(0x2D323B) : RGB(0x15171C),
            fg: RGB(0xDCDFE5), dim: RGB(0x7F8796), green: RGB(0x9AD08A), yellow: RGB(0xE4BF7A),
            blue: RGB(0x7DB2EE), magenta: RGB(0xC79BE6), red: RGB(0xEA7B7B), cyan: RGB(0x6EC6C6))
    }
}
