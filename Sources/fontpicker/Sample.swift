import Foundation

/// A run of sample text in one colour and style.
struct Span: Hashable {
    var text: String
    var color: TermColor = .fg
    var bold = false
    var italic = false
}

typealias TermLine = [Span]

/// The text shown in the terminal panes: a prompt, a listing with Nerd Font icons, some
/// code, and three rows that put ligatures, lookalikes and the four styles side by side.
enum Sample {
    private enum Icon {
        static let folder = "\u{F07B}", branch = "\u{E0A0}", file = "\u{F15B}", python = "\u{E73C}"
        static let rust = "\u{E7A8}", github = "\u{F09B}", ok = "\u{F00C}", clock = "\u{F017}", bolt = "\u{F0E7}"
    }

    private static func t(_ text: String) -> Span { Span(text: text) }
    private static func c(_ color: TermColor, _ text: String) -> Span { Span(text: text, color: color) }
    private static func b(_ color: TermColor, _ text: String) -> Span { Span(text: text, color: color, bold: true) }
    private static let prompt = c(.green, "❯")

    static let main: [TermLine] = [
        [c(.blue, "\(Icon.folder) ~/src/agents"), t(" "), c(.magenta, "\(Icon.branch) main"), t(" "), prompt, t(" git log --oneline -2")],
        [c(.yellow, "a1f9c3e"), t(" fix: treat 0xFF != 0O17 as distinct (#128)")],
        [c(.yellow, "7be02d4"), t(" feat: retry on 429 with backoff <= 30s "), c(.green, Icon.ok)],
        [prompt, t(" ls")],
        [
            c(.yellow, "\(Icon.python) train.py"), t("  "), c(.red, "\(Icon.rust) main.rs"), t("  "),
            c(.cyan, "\(Icon.file) notes.md"), t("  "), c(.blue, "\(Icon.github) .github"), t("  "),
            c(.dim, "\(Icon.clock) 2m \(Icon.bolt) 98%"),
        ],
        [prompt, t(" cat pipeline.ts")],
        [Span(text: "// Italic comment: résumé, Illegal1 = O0, fn(x) -> y", color: .dim, italic: true)],
        [b(.magenta, "export const"), t(" run = "), b(.magenta, "async"), t(" (xs: "), c(.cyan, "number"), t("[]) => {")],
        [t("  "), b(.magenta, "if"), t(" (xs.length >= 2 && xs[0] !== "), c(.yellow, "null"), t(") "), b(.magenta, "return"), t(" xs |> sum;")],
        [t("  "), b(.magenta, "return"), t(" fetch("), c(.green, "`${api}/v1?id=${id}`"), t(").then(r => r.json());")],
        [t("};")],
        [c(.dim, "ligatures "), t(" -> => != == === >= <= <-> |> :: ... <!-- // /* && || ++ www")],
        [c(.dim, "lookalikes"), t(" 0O 1lI| ag rn fi {}[]() @&$%# *^~ 6 9 7")],
        [
            c(.dim, "styles    "), t(" Regular "), Span(text: "Bold", bold: true), t(" "), Span(text: "Italic", italic: true),
            t(" "), Span(text: "Bold Italic", bold: true, italic: true),
        ],
    ]

    /// The shorter sample used to line shortlisted fonts up against each other.
    static let compare: [TermLine] = [
        [t("if (a !== b && c >= 0x1F) return xs.map(x => x * 2) |> sum; "), c(.dim, "// 0O 1lI|")],
        [Span(text: "The quick brown fox jumps over the lazy dog, in italic", italic: true)],
        [Span(text: "ABCDEFGHIJKLM nopqrstuvwxyz 0123456789 {}[]()<>", bold: true)],
    ]
}
