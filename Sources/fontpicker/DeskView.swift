import FontPickerCore
import SwiftUI

/// The right column: feature switches, the config they produce, and facts about the font.
struct DeskView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let family = state.current {
                FeaturesBlock(family: family)
                ConfigBlock(family: family)
                AboutBlock(family: family)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FeaturesBlock: View {
    let family: FontFamily
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var theme
    @Local private var showVariants = false

    var body: some View {
        let detail = state.details[family.id]
        let live = state.liveFeatures(for: family)
        Block(title: "Features") {
            Button("Clear") { state.clearFeatures() }
                .buttonStyle(LinkButtonStyle())
                .disabled(live.isEmpty)
                .opacity(live.isEmpty ? 0.4 : 1)
        } content: {
            if let detail {
                Text(detail.features.isEmpty
                    ? "This font has no optional features. Ligatures, if any, are on by default."
                    : "Left glyphs are the feature off, right glyphs on. Click to switch.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                chips(detail.features, live: live)
                if !detail.variants.isEmpty {
                    DisclosureGroup("Character variants (\(detail.variants.count))", isExpanded: $showVariants) {
                        chips(detail.variants, live: live).padding(.top, 6)
                    }
                    .foregroundStyle(theme.muted)
                }
            } else {
                Text("Working out what each feature changes…").font(.system(size: 12.5)).foregroundStyle(theme.muted)
            }
        }
    }

    private func chips(_ features: [FontFeature], live: [String: Int]) -> some View {
        VStack(spacing: 4) {
            ForEach(features) { feature in
                FeatureChip(
                    family: family, feature: feature, value: live[feature.tag] ?? 0,
                    isHot: state.drift.mode == .tour && state.drift.overlay?.hot == feature.tag
                ) { state.cycle(feature) }
            }
        }
    }
}

/// One feature: its tag, a before-and-after strip in the font itself, and its name.
private struct FeatureChip: View {
    let family: FontFamily
    let feature: FontFeature
    let value: Int
    let isHot: Bool
    let action: () -> Void

    @Environment(\.theme) private var theme
    @Local private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(value > 1 ? "\(feature.tag)=\(value)" : feature.tag)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .frame(width: 52, alignment: .leading)
                HStack(spacing: 6) {
                    Text(sample).font(UIFonts.font(family.family, size: 15, feature: feature.tag, value: 0))
                    Text("→").font(.system(size: 12)).foregroundStyle(theme.muted)
                    Text(sample)
                        .font(UIFonts.font(family.family, size: 15, feature: feature.tag, value: max(1, value)))
                        .foregroundStyle(theme.accent)
                }
                .lineLimit(1)
                .fixedSize()
                // The name gets whatever the strip leaves and truncates if that isn't enough.
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(value > 0 ? theme.chipOn : theme.chip, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(value > 0 || hovering || isHot ? theme.accent : theme.rule))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.glow, lineWidth: 2).padding(-2).opacity(isHot ? 1 : 0))
            .contentShape(Rectangle())
            .clipped()
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tooltip)
        .accessibilityLabel("\(feature.tag)\(feature.name.map { ", \($0)" } ?? "")")
        .accessibilityValue(value == 0 ? "off" : value == 1 ? "on" : "variant \(value)")
    }

    /// A few of the glyphs the feature touches, short enough that both the before and the
    /// after fit beside the name. Whole-face restyles get a fixed sample.
    private var sample: String {
        let budget = 6
        if feature.chars.count > 10 { return "aegr0" }
        var text = ""
        for item in [feature.chars] + feature.sequences where !item.isEmpty {
            if text.isEmpty {
                text = String(item.prefix(budget))
            } else if text.count + 1 + item.count <= budget {
                text += " " + item
            } else {
                break
            }
        }
        return text.isEmpty ? feature.tag : text
    }

    private var caption: String {
        feature.name ?? (feature.alternates > 1 ? "\(feature.alternates) variants" : "")
    }

    private var tooltip: String {
        let affects = [feature.chars.map(String.init).joined(separator: " "), feature.sequences.joined(separator: " ")]
            .filter { !$0.isEmpty }.joined(separator: "  ")
        return (feature.name.map { "\($0). " } ?? "") + "Affects \(affects)"
            + (feature.alternates > 1 ? ". \(feature.alternates) variants, click to step through" : "")
    }
}

private struct ConfigBlock: View {
    let family: FontFamily
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        Block(title: "Config") {
            Text(state.configPath)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.muted)
                .lineLimit(1)
                .truncationMode(.head)
                .help(state.installer.mainConfig.path)
        } content: {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("font-style")
                    Picker("font-style", selection: styleBinding) {
                        ForEach(family.styles, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .disabled(family.styles.count < 2)
                }
                GridRow {
                    Text("italic from")
                    Picker("italic from", selection: italicBinding) {
                        Text("this font").tag("")
                        ForEach(state.italicSources(for: family)) { source in
                            Text(source.short + (source.cursive ? " (cursive)" : "")).tag(source.id)
                        }
                    }
                    .labelsHidden()
                }
            }

            Text(GhosttyConfig.snippet(state.selection(for: family)))
                .font(.system(size: 12, design: .monospaced))
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.rule))

            HStack(spacing: 8) {
                Button("Apply to Ghostty") { state.apply() }
                    .buttonStyle(BenchButtonStyle(primary: true))
                    .help("Write this to Ghostty's config and reload it (⌘↩)")
                Button("Copy") { state.copyConfig() }
                    .buttonStyle(BenchButtonStyle())
                if state.canRevert {
                    Button("Revert") { state.revert() }
                        .buttonStyle(BenchButtonStyle())
                        .help("Put Ghostty's font back the way it was when the picker opened")
                }
            }
            Toggle("Live: apply every change as I make it", isOn: Binding(get: { state.live }, set: { state.setLive($0) }))
                .toggleStyle(.checkbox)
                .help("Each change is written to Ghostty and reloaded, so the open terminals follow along")

            if let status = state.status {
                Group {
                    switch status {
                    case .info(let text): Text(text).foregroundStyle(theme.muted)
                    case .error(let text): Text(text).foregroundStyle(theme.danger)
                    }
                }
                .font(.system(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            }
        }
    }

    private var styleBinding: Binding<String> {
        Binding(get: { state.style(for: family) }, set: { state.prefs.style[family.id] = $0 })
    }

    private var italicBinding: Binding<String> {
        Binding(
            get: { state.prefs.italicFrom[family.id].flatMap { state.family($0)?.id } ?? "" },
            set: { state.prefs.italicFrom[family.id] = $0.isEmpty ? nil : $0 })
    }
}

private struct AboutBlock: View {
    let family: FontFamily
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var theme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Block(title: "About this font") { EmptyView() } content: {
            if let note = family.note {
                Text(note).font(.system(size: 12.5)).foregroundStyle(theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 3) {
                fact("Ligatures", ligatures)
                fact("Italic", italic)
                fact("Weights", family.styles.joined(separator: ", "))
                fact("Cell", String(format: "%.2fem wide, x-height %.2f, line %.2f", family.advance, family.xHeight, family.lineHeight))
                fact("Grid", grid)
            }
            .font(.system(size: 12.5))
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        GridRow {
            CapsLabel(label).padding(.top, 2)
            Text(value).monospacedDigit().fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }

    private var ligatures: String {
        let tested = FontProbe.ligatureTests.count
        if family.ligMax == 0 { return "none" }
        if family.ligMax > family.ligDefault {
            return "\(family.ligDefault) of \(tested) by default, \(family.ligMax) with its sets on"
        }
        return "\(family.ligDefault) of \(tested), on by default"
    }

    private var italic: String {
        switch family.italic {
        case .none: return "none, Ghostty slants the upright"
        case .oblique: return "oblique"
        case .italic: return family.cursive ? "cursive italic" : "true italic"
        case .both: return (family.cursive ? "cursive italic" : "true italic") + ", plus oblique"
        }
    }

    /// The actual cell at the chosen size on this display, in device pixels.
    private var grid: String {
        let metrics = FontSet.resolve(state.renderSpec(for: family)).metrics
        let cell = metrics.cell(size: state.prefs.size, scale: displayScale)
        let width = Int((cell.width * displayScale).rounded()), height = Int((cell.height * displayScale).rounded())
        return "\(width) × \(height) px cells at \(GhosttyConfig.sizeString(state.prefs.size)) pt on this display"
    }
}
