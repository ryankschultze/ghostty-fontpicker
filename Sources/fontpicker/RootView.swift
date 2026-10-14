import FontPickerCore
import SwiftUI

/// The whole window: a toolbar over three columns.
struct RootView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme.of(colorScheme)
        VStack(spacing: 0) {
            ToolbarView()
            Rectangle().fill(theme.rule).frame(height: 1)
            HStack(alignment: .top, spacing: 20) {
                RailView()
                    .frame(width: 230)
                    .padding(.bottom, 18)
                ScrollView {
                    CenterView().padding(.bottom, 32)
                }
                ScrollView {
                    DeskView().padding(.bottom, 32).padding(.trailing, 2)
                }
                .frame(width: 320)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
        }
        .font(.system(size: 13))
        .foregroundStyle(theme.ink)
        .tint(theme.accent)
        .background(theme.bg)
        .environment(\.theme, theme)
        .alert("Let FontPicker manage Ghostty's font?", isPresented: $state.askToLink) {
            Button("Add the line and apply") { state.apply(confirmed: true) }
            Button("Cancel", role: .cancel) { state.declineLink() }
        } message: {
            Text("""
                This adds one line to the end of \(state.configPath):

                \(GhosttyInstaller.includeLine)

                The font settings themselves go in \(GhosttyPaths.includeName) beside it, which overrides \
                any font set earlier in your config. Nothing else in your config is changed, and \
                “fontpicker reset” takes both back out.
                """)
        }
    }
}

private struct ToolbarView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 18) {
            Text("Ghostty Font Picker")
                .font(.system(size: 20, weight: .semibold))
                .lineLimit(1)
                .fixedSize()

            HStack(spacing: 7) {
                Text("Size").fixedSize()
                SnappingSlider(value: $state.prefs.size, range: 10...24, step: 1).frame(width: 110)
                Text("\(Int(state.prefs.size)) pt").monospacedDigit().foregroundStyle(theme.muted).frame(width: 36, alignment: .leading)
            }
            HStack(spacing: 7) {
                Text("Ligatures").fixedSize()
                Segmented(options: [(true, "On"), (false, "Off")], selection: $state.prefs.ligatures)
            }
            HStack(spacing: 7) {
                Text("Pane").fixedSize()
                Segmented(options: [(false, "Dark"), (true, "Light")], selection: $state.prefs.lightPane)
            }
            HStack(spacing: 7) {
                Text("Fonts").fixedSize()
                Segmented(options: [(FontScope.nerd, "Nerd"), (FontScope.all, "All")], selection: $state.prefs.scope)
                    .help("Nerd Fonts only, or every fixed-width family on this Mac")
            }
            Spacer(minLength: 0)
            Text("↑ ↓ fonts · space drift · ⌘↩ apply")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.muted)
                .lineLimit(1)
                .layoutPriority(-1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}
