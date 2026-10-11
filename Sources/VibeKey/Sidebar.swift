import SwiftUI
import VibeKeyCore

struct Sidebar: View {
    @EnvironmentObject var state: AppState
    let topInset: CGFloat
    @State private var query = ""
    @State private var collapsed: Set<String> = []

    /// Button/Knob tabs follow the selected control.
    private var tab: Binding<Int> {
        Binding(get: { state.selected.isKnob ? 1 : 0 }, set: { newValue in
            if newValue == 1 { state.select(.knob) } else if state.selected.isKnob { state.select(.mic) }
        })
    }

    private var items: [PaletteItem] {
        let base = state.selected.isKnob ? PaletteItem.knobItems + PaletteItem.buttonItems : PaletteItem.buttonItems
        guard !query.isEmpty else { return base }
        return base.filter { $0.label.localizedCaseInsensitiveContains(query) || $0.section.localizedCaseInsensitiveContains(query) }
    }

    private var sections: [String] {
        var seen: [String] = []
        for item in items where !seen.contains(item.section) { seen.append(item.section) }
        return seen
    }

    var body: some View {
        VStack(spacing: 0) {
            // The title-bar band above the sidebar holds the toolbar's header controls.
            Color.clear
                .frame(height: topInset)
                .background(WindowDragArea())
            Hairline()
            VStack(alignment: .leading, spacing: 12) {
                SearchField(text: $query)
                PillSegments(options: [0, 1], selection: tab,
                             title: { $0 == 0 ? "Button" : "Knob" },
                             icon: { $0 == 0 ? "square.grid.2x2" : "dial.medium" },
                             stretch: true)
                AssigningHint()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(sections, id: \.self) { sectionCard($0) }
                    if items.isEmpty {
                        Text("No actions match “\(query)”")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.tertiary)
                            .padding(.top, 30)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .scrollIndicators(.never)
            Hairline()
            Text("Click an action to assign it, or drag it onto a control.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiary)
                .multilineTextAlignment(.center)
                .padding(.vertical, 11)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
        }
        .background(Theme.sidebar)
    }

    private func sectionCard(_ section: String) -> some View {
        let open = !collapsed.contains(section) || !query.isEmpty
        let rows = items.filter { $0.section == section }
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    if collapsed.contains(section) { collapsed.remove(section) } else { collapsed.insert(section) }
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.tertiary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .frame(width: 10)
                    Image(systemName: PaletteItem.sectionSymbols[section] ?? "square")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 18)
                    Text(section)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Text("\(rows.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.tertiary)
                }
                .padding(.horizontal, 11)
                .frame(height: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                VStack(spacing: 1) {
                    ForEach(rows) { PaletteRow(item: $0, assigned: isAssigned($0)) }
                }
                .padding(.horizontal, 5)
                .padding(.bottom, 6)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.07)))
    }

    private func isAssigned(_ item: PaletteItem) -> Bool {
        let cfg = state.profile[state.selected]
        if let turn = item.knobTurn {
            return state.selected.isKnob && cfg.left == turn.left && cfg.right == turn.right
        }
        let turnSlot = state.slot == .left || state.slot == .right
        if state.selected.isKnob && turnSlot && PaletteItem.knobItems.contains(where: { $0.knobTurn.map { cfg.left == $0.left && cfg.right == $0.right } ?? false }) {
            return false
        }
        return item.type != nil && cfg[state.slot]?.type == item.type
    }
}

private struct AssigningHint: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        HStack(spacing: 6) {
            Text("Assigning to")
                .foregroundStyle(Theme.tertiary)
            Image(systemName: state.selected.symbol)
                .foregroundStyle(Theme.teal)
            Text("\(state.selected.displayName) · \(state.slot.shortLabel)")
                .foregroundStyle(Theme.text.opacity(0.9))
        }
        .font(.system(size: 11.5, weight: .medium))
        .padding(.leading, 2)
    }
}

private struct PaletteRow: View {
    @EnvironmentObject var state: AppState
    let item: PaletteItem
    let assigned: Bool
    @State private var hover = false

    var body: some View {
        Button {
            state.assign(item, to: item.knobTurn != nil ? .knob : state.selected)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 13))
                    .frame(width: 20)
                Text(item.label)
                    .font(.system(size: 13))
                Spacer()
                if assigned {
                    Image(systemName: "checkmark").font(.system(size: 10.5, weight: .bold))
                } else if hover {
                    Image(systemName: "plus").font(.system(size: 10.5, weight: .bold)).foregroundStyle(Theme.tertiary)
                }
            }
            .foregroundStyle(assigned ? Theme.teal : Theme.text.opacity(0.88))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(assigned ? Theme.teal.opacity(0.10) : Color.white.opacity(hover ? 0.06 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .draggable(item.id) {
            Label(item.label, systemImage: item.symbol)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.onTeal)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Theme.teal))
        }
    }
}

private struct SearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.tertiary)
            TextField("", text: $text, prompt: Text("Search actions").foregroundColor(Theme.tertiary))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .modifier(FieldBackground(focused: focused))
        .background(
            // ⌘F focuses the search field.
            Button("") { focused = true }
                .keyboardShortcut("f")
                .opacity(0)
                .allowsHitTesting(false)
        )
    }
}
