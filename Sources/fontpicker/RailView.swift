import FontPickerCore
import SwiftUI

/// The font list on the left: a filter and every family, named in its own face.
struct RailView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.theme) private var theme
    @FocusState private var filterFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            TextField("Filter fonts", text: $state.filter)
                .textFieldStyle(.plain)
                .focused($filterFocused)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(filterFocused ? theme.accent : theme.rule))
                .onChange(of: state.focusFilter) { filterFocused = true }
                .onSubmit { filterFocused = false }
                .onExitCommand { filterFocused = false }

            ScrollViewReader { proxy in
                ScrollView {
                    list
                }
                .background(theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.rule))
                .onChange(of: state.prefs.font) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id)
                }
                .onChange(of: state.isLoading) {
                    if let id = state.prefs.font { proxy.scrollTo(id, anchor: .center) }
                }
                .onAppear {
                    if let id = state.prefs.font { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    @ViewBuilder private var list: some View {
        let groups = state.groups
        if state.isLoading {
            Text("Measuring installed fonts…").foregroundStyle(theme.muted).padding(12)
        } else if groups.isEmpty {
            Text(state.filter.isEmpty ? "No fixed-width fonts found." : "No fonts match “\(state.filter)”.")
                .foregroundStyle(theme.muted)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LazyVStack(alignment: .leading, spacing: 1, pinnedViews: [.sectionHeaders]) {
                ForEach(groups, id: \.group) { entry in
                    Section {
                        ForEach(entry.families) { family in
                            RailRow(family: family, detail: state.details[family.id], isCurrent: family.id == state.prefs.font) {
                                state.select(family.id)
                            }
                            .id(family.id)
                        }
                    } header: {
                        CapsLabel(entry.group.title)
                            .padding(.horizontal, 10)
                            .padding(.top, 7)
                            .padding(.bottom, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.surface)
                    }
                }
            }
        }
    }
}

private struct RailRow: View {
    let family: FontFamily
    let detail: FontDetail?
    let isCurrent: Bool
    let action: () -> Void

    @Environment(\.theme) private var theme
    @Local private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(family.short)
                    .font(UIFonts.font(family.family, size: 15))
                    .lineLimit(1)
                Text(meta)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(theme.muted)
            }
            .padding(.vertical, 6)
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isCurrent ? theme.chipOn : hovering ? theme.chip : .clear)
            .overlay(alignment: .leading) {
                Rectangle().fill(isCurrent ? theme.accent : .clear).frame(width: 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(family.short), \(meta)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    /// Counts of what's worth knowing at a glance. Once the family has been probed, sets
    /// that change nothing visible are left out of the count.
    private var meta: String {
        let sets = detail.map { $0.features.filter { FontProbe.isStylisticSet($0.tag) }.count } ?? family.stylisticSetCount
        let parts = [
            family.ligMax > 0 ? "\(family.ligMax) lig" : nil,
            sets > 0 ? "\(sets) sets" : nil,
            family.cvTags.isEmpty ? nil : "\(family.cvTags.count) cv",
        ].compactMap { $0 }
        return parts.isEmpty ? "plain" : parts.joined(separator: " · ")
    }
}
