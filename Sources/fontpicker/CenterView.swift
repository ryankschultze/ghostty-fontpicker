import FontPickerCore
import SwiftUI

/// The middle column: the selected font's name, the terminal stage, drift, and the shortlist.
struct CenterView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let family = state.current {
                header(family)
                StageView(family: family)
                DriftPanel(family: family)
            } else if !state.isLoading {
                Text("No fixed-width fonts are installed.").foregroundStyle(theme.muted)
            }
            ShortlistView()
            Text("Previews are drawn with Core Text, the font engine Ghostty uses on macOS, on a cell grid sized by Ghostty's rules. Apply writes the choice to Ghostty and reloads it, so every open terminal shows the real thing.")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.muted)
                .frame(maxWidth: 620, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(_ family: FontFamily) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(family.short)
                .font(UIFonts.font(family.family, size: 24))
                .lineLimit(1)
            Text(family.family)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.muted)
                .lineLimit(1)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button(state.isShortlisted ? "★ Shortlist" : "☆ Shortlist") { state.toggleShortlist() }
                .buttonStyle(BenchButtonStyle(active: state.isShortlisted))
                .help(state.isShortlisted ? "Remove from the shortlist" : "Keep this font to compare against others")
        }
    }
}

/// The terminal pane. Changes crossfade so a feature flipping is easy to spot.
private struct StageView: View {
    let family: FontFamily
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let spec = state.renderSpec(for: family)
        let palette = state.palette(appIsDark: theme.isDark)
        let drifting = state.drift.mode != .off
        ScrollView(.horizontal) {
            ZStack(alignment: .topLeading) {
                TerminalCanvas(lines: Sample.main, spec: spec, palette: palette)
                    .id(spec)
                    .transition(.opacity)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: spec)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bg.color)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.edge.color))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.glow, lineWidth: 3).padding(-3).opacity(drifting ? 1 : 0))
        .overlay(alignment: .bottomTrailing) {
            if drifting, let caption = state.drift.caption {
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.fg.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(palette.bg.color.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                    .padding(.trailing, 10)
                    .padding(.bottom, 8)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Lets the features play by themselves: one at a time, on slow waves, or at random.
private struct DriftPanel: View {
    let family: FontFamily
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        let mode = state.drift.mode
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                CapsLabel("Drift").fixedSize()
                Segmented(
                    options: DriftMode.allCases.map { ($0, $0.title) },
                    selection: Binding(get: { mode }, set: { state.setDrift($0) }))
                Spacer(minLength: 0)
                if mode != .off {
                    Button("Keep this") { state.keepDrift() }.buttonStyle(BenchButtonStyle(primary: true))
                        .help("Freeze what's on screen into the config")
                }
            }
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Text("Rate").fixedSize()
                    SnappingSlider(value: $state.drift.rate, range: 0.25...4, step: 0.25).frame(width: 100)
                    Text(rateLabel).monospacedDigit().foregroundStyle(theme.muted).frame(width: 40, alignment: .leading)
                }
                if mode == .lfo {
                    HStack(spacing: 6) {
                        Text("Density").fixedSize()
                        SnappingSlider(value: $state.drift.density, range: 0.1...0.9, step: 0.05).frame(width: 100)
                        Text("\(Int((state.drift.density * 100).rounded()))%").monospacedDigit().foregroundStyle(theme.muted)
                            .frame(width: 34, alignment: .leading)
                    }
                }
                Toggle("Fonts too", isOn: $state.drift.fontsToo).toggleStyle(.checkbox).fixedSize()
                    .help("Move on to the next font as well")
                Spacer(minLength: 0)
            }
            if mode != .off {
                DriftScope(family: family)
            }
            Text("Tour steps through the font's features one at a time. LFO gives every feature its own slow sine wave and switches it on above the density line; the periods never line up, so the pattern never quite repeats. Random flips a feature or two each beat. Keep this freezes whatever is on screen into the config.")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.rule))
    }

    private var rateLabel: String {
        let rate = state.drift.rate
        return (rate == rate.rounded() ? String(Int(rate)) : String(rate)) + "×"
    }
}

/// One column per feature: a dot that sits high when the feature is on. In LFO mode the
/// dots ride their waves and the dashed line is the level they switch on at.
private struct DriftScope: View {
    let family: FontFamily
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: state.drift.mode != .lfo)) { timeline in
            let features = state.driftFeatures(for: family)
            let live = state.liveFeatures(for: family)
            let time = timeline.date.timeIntervalSince(state.drift.start)
            Canvas { context, size in
                guard !features.isEmpty else {
                    context.draw(
                        Text("nothing to modulate in this font").font(.system(size: 12)).foregroundColor(theme.muted),
                        at: CGPoint(x: 4, y: 28), anchor: .leading)
                    return
                }
                let column = min(44, size.width / Double(features.count))
                let left = (size.width - column * Double(features.count)) / 2
                let isLFO = state.drift.mode == .lfo
                if isLFO {
                    let threshold = 1 - 2 * state.drift.density
                    let y = 6 + (1 - threshold) / 2 * 32
                    var line = Path()
                    line.move(to: CGPoint(x: left, y: y))
                    line.addLine(to: CGPoint(x: left + column * Double(features.count), y: y))
                    context.stroke(line, with: .color(theme.rule), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                for (index, feature) in features.enumerated() {
                    let x = left + column * (Double(index) + 0.5)
                    let on = (live[feature.tag] ?? 0) > 0
                    var track = Path()
                    track.move(to: CGPoint(x: x, y: 6))
                    track.addLine(to: CGPoint(x: x, y: 38))
                    context.stroke(track, with: .color(theme.rule), lineWidth: 1)

                    let y = isLFO ? 6 + (1 - state.lfoValue(index, at: time)) / 2 * 32 : (on ? 10.0 : 34.0)
                    let radius = on ? 4.5 : 3.0
                    let dot = Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                    context.fill(dot, with: .color(on ? theme.accent : theme.muted.opacity(0.45)))
                    if column >= 26 {
                        context.draw(
                            Text(feature.tag).font(.system(size: 9.5, design: .monospaced)).foregroundColor(on ? theme.accent : theme.muted),
                            at: CGPoint(x: x, y: 49))
                    }
                }
            }
            .frame(height: 56)
            .accessibilityHidden(true)
        }
    }
}

/// Starred fonts stacked with the same three lines of text, each with its own switches.
private struct ShortlistView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shortlist").font(.system(size: 13, weight: .semibold))
            let entries = state.prefs.shortlist.compactMap(state.family)
            if entries.isEmpty {
                Text("Star a font to line it up here against the others. Each row keeps its own feature switches.")
                    .foregroundStyle(theme.muted)
            } else {
                let palette = state.palette(appIsDark: theme.isDark)
                ForEach(entries) { family in
                    HStack(spacing: 10) {
                        Button { state.select(family.id) } label: {
                            Text(family.short)
                                .font(UIFonts.font(family.family, size: 15))
                                .lineLimit(1)
                                .frame(width: 150, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Show \(family.short) on the stage")

                        ScrollView(.horizontal) {
                            TerminalCanvas(
                                lines: Sample.compare, spec: state.renderSpec(for: family, live: false),
                                palette: palette, padding: CGSize(width: 16, height: 8))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(palette.bg.color)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(palette.edge.color))

                        Button("×") { state.prefs.shortlist.removeAll { $0 == family.id } }
                            .buttonStyle(BenchButtonStyle())
                            .accessibilityLabel("Remove \(family.short)")
                    }
                }
            }
        }
        .padding(.top, 6)
    }
}
