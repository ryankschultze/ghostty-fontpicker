import CoreText
import FontPickerCore
import SwiftUI

/// View-local state, used wherever `@State` normally would be.
///
/// In the macOS 27 SDK `@State` is a macro, and the compiler plugin that expands it ships
/// with Xcode but not with the Command Line Tools. Wrapping the underlying `State` struct
/// directly behaves the same and keeps the project buildable with `swift build` alone.
@propertyWrapper
struct Local<Value>: DynamicProperty {
    private var storage: State<Value>

    init(wrappedValue: Value) {
        storage = State(initialValue: wrappedValue)
    }

    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> { storage.projectedValue }
}

/// Small-caps style heading used over each block.
struct CapsLabel: View {
    let text: String
    @Environment(\.theme) private var theme

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(theme.muted)
    }
}

/// A row of joined buttons where exactly one is pressed.
struct Segmented<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                if index > 0 { Rectangle().fill(theme.rule).frame(width: 1) }
                Button { selection = option.value } label: {
                    Text(option.title)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(selection == option.value ? theme.accentInk : theme.ink)
                        .background(selection == option.value ? theme.accent : theme.surface)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }
        .fixedSize()
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.rule))
    }
}

/// A slider that snaps to `step`. Passing `step` to `Slider` itself draws a tick mark for
/// every stop, which is a lot of ticks for a control this small.
struct SnappingSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        Slider(
            value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }),
            in: range)
    }
}

/// The bordered button used across the workbench; `primary` fills it with the accent.
struct BenchButtonStyle: ButtonStyle {
    var primary = false
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, filled: primary || active)
    }

    private struct Face: View {
        let configuration: ButtonStyleConfiguration
        let filled: Bool
        @Environment(\.theme) private var theme
        @Environment(\.isEnabled) private var isEnabled
        @Local private var hovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(filled ? theme.accentInk : theme.ink)
                .background(filled ? theme.accent : theme.surface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(filled || hovering ? theme.accent : theme.rule))
                .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.75 : 1)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

/// An underlined text button, for minor actions.
struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration)
    }

    private struct Face: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.theme) private var theme

        var body: some View {
            configuration.label
                .underline()
                .foregroundStyle(theme.accent)
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(Rectangle())
        }
    }
}

/// A titled group in the desk column.
struct Block<Trailing: View, Content: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                trailing
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// SwiftUI fonts for showing a family in its own face. Core Text fonts are kept so views
/// that redraw often don't rebuild them.
@MainActor
enum UIFonts {
    private struct Key: Hashable {
        var family: String
        var size: Double
        var feature: String?
        var value: Int
    }

    private static var cache: [Key: Font] = [:]

    /// The family at a UI size, optionally with one feature forced on or off.
    static func font(_ family: String, size: Double, feature: String? = nil, value: Int = 0) -> Font {
        let key = Key(family: family, size: size, feature: feature, value: value)
        if let hit = cache[key] { return hit }
        var font = FontFactory.font(family: family, size: size) ?? CTFontCreateWithName("Menlo" as CFString, size, nil)
        if let feature { font = FontFactory.applying([(feature, value)], to: font) }
        let result = Font(font)
        cache[key] = result
        return result
    }
}
