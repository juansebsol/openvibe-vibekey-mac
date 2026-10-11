import SwiftUI
import AppKit
import VibeKeyCore

/// Bottom panel: edit the selected control's title and the action bound to the chosen gesture.
struct ControlEditor: View {
    @EnvironmentObject var state: AppState
    @State private var contentHeight: CGFloat = 180

    var body: some View {
        let c = state.selected
        let action = state.actionBinding(c, state.slot)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                HStack(spacing: 7) {
                    Image(systemName: c.symbol).font(.system(size: 12, weight: .semibold))
                    Text(c.displayName.uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.9)
                }
                .foregroundStyle(Theme.secondary)
                .frame(minWidth: 84, alignment: .leading)

                PillSegments(options: Slot.slots(for: c), selection: $state.slot,
                             title: { $0.shortLabel },
                             dot: { state.profile[c][$0] != nil })

                Spacer(minLength: 12)

                if let a = action.wrappedValue {
                    Text("\(a.type.section)  ·  \(a.type.label)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiary)
                    Button { action.wrappedValue = nil } label: { Image(systemName: "trash") }
                        .buttonStyle(IconButtonStyle(destructive: true))
                        .help("Remove this action")
                }
            }
            .frame(height: 52)

            Hairline()

            ScrollView {
                HStack(alignment: .top, spacing: 24) {
                    ActionTile(action: action.wrappedValue,
                               title: state.profile[c].title.isEmpty ? c.displayName : state.profile[c].title)

                    VStack(alignment: .leading, spacing: 10) {
                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                            GridRow {
                                FieldLabel("Title")
                                VKTextField(placeholder: c.displayName, text: state.controlBinding(c).title)
                                    .frame(maxWidth: 420)
                            }
                            GridRow {
                                FieldLabel("Action")
                                ActionTypeMenu(type: Binding(
                                    get: { action.wrappedValue?.type },
                                    set: { t in action.wrappedValue = t.map { Action.blank($0) } }
                                ))
                            }
                            if action.wrappedValue != nil {
                                ActionFields(action: Binding(get: { action.wrappedValue ?? .blank(.hotkey) },
                                                             set: { action.wrappedValue = $0 }),
                                             slot: state.slot)
                            }
                        }
                        footnote(action: action.wrappedValue)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 18)
                .background(GeometryReader { g in
                    Color.clear.preference(key: ContentHeightKey.self, value: g.size.height)
                })
            }
            .scrollIndicators(.never)
            .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 860)
        .frame(maxWidth: .infinity)
        .frame(height: min(max(252, 53 + contentHeight), 440))
        .background(Theme.panel)
        .animation(.easeOut(duration: 0.2), value: contentHeight)
    }

    @ViewBuilder
    private func footnote(action: Action?) -> some View {
        let text: String? = {
            if action == nil { return "Pick an action type, or drag one from the list on the right." }
            if state.slot == .hold {
                return "Hold keeps shortcuts pressed while the button is down (push-to-talk) and records voice while held. It replaces Press and Long Press."
            }
            if state.slot == .longPress { return "Fires after holding for \(String(format: "%.2g", state.config.longPressSeconds))s. A quick press still triggers Press." }
            return nil
        }()
        if let text {
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 74)
        }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct ActionTile: View {
    let action: Action?
    let title: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: action?.type.symbol ?? "plus")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(action == nil ? Theme.tertiary : Theme.text)
                .frame(height: 30)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .padding(.horizontal, 6)
        }
        .frame(width: 96, height: 96)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.field))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(action == nil ? Theme.stroke : Theme.teal.opacity(0.35),
                              style: StrokeStyle(lineWidth: 1, dash: action == nil ? [4, 3] : []))
        )
    }
}

struct ActionTypeMenu: View {
    @Binding var type: ActionType?
    var width: CGFloat = 240
    private let sections = ["System", "Multi Action", "Profiles", "Voice"]

    var body: some View {
        Menu {
            Picker("", selection: $type) {
                Text("None").tag(ActionType?.none)
                ForEach(sections, id: \.self) { section in
                    Section(section) {
                        ForEach(ActionType.allCases.filter { $0.section == section }, id: \.self) { t in
                            Label(t.label, systemImage: t.symbol).tag(ActionType?.some(t))
                        }
                    }
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            MenuFieldLabel(icon: type?.symbol, text: type?.label ?? "Choose an action…", placeholder: type == nil, width: width)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// Type-specific fields, emitted as GridRows. Recursive for Multi / Random actions.
struct ActionFields: View {
    @EnvironmentObject var state: AppState
    @Binding var action: Action
    var slot: Slot
    var nested = false

    var body: some View {
        switch action.type {
        case .hotkey:
            GridRow {
                label("Shortcut")
                HotkeyRecorder(keys: str(\.keys), compact: nested)
            }
        case .text:
            if nested {
                GridRow {
                    VKTextField(placeholder: "Text to type", text: str(\.text))
                        .frame(width: 260)
                }
            } else {
                GridRow(alignment: .top) {
                    label("Text").padding(.top, 8)
                    VKTextEditor(text: str(\.text))
                        .frame(maxWidth: 420)
                }
            }
        case .open:
            GridRow {
                label("App")
                HStack(spacing: 8) {
                    VKTextField(placeholder: "App name or path, e.g. Safari", text: str(\.app))
                        .frame(maxWidth: 320)
                    Button("Choose…") { chooseApp() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        case .website:
            GridRow {
                label("URL")
                VKTextField(placeholder: "https://example.com", text: str(\.url))
                    .frame(maxWidth: 420)
            }
        case .shell:
            GridRow {
                label("Command")
                VKTextField(placeholder: "open ~/Downloads", text: str(\.command), mono: true)
                    .frame(maxWidth: 420)
            }
        case .media:
            GridRow {
                label("Key")
                ChoiceMenu(selection: Binding(get: { action.media ?? .playPause }, set: { action.media = $0 }),
                           options: MediaKey.allCases, title: { $0.label }, icon: { $0.symbol }, width: nested ? 200 : 240)
            }
        case .scroll:
            GridRow {
                label("Scroll")
                HStack(spacing: 10) {
                    let amount = action.amount ?? 3
                    Text("\(abs(amount)) line\(abs(amount) == 1 ? "" : "s") \(amount >= 0 ? "up" : "down")")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                        .monospacedDigit()
                        .frame(width: 110, alignment: .leading)
                        .modifier(FieldBackground())
                    Stepper("", value: Binding(get: { action.amount ?? 3 }, set: { action.amount = $0 }), in: -30...30)
                        .labelsHidden()
                }
            }
        case .switchProfile:
            GridRow {
                label("Profile")
                ChoiceMenu(selection: str(\.profile), options: [""] + state.config.profiles.map(\.name),
                           title: { $0.isEmpty ? "Choose a profile…" : $0 }, width: nested ? 200 : 240)
            }
        case .voice:
            GridRow {
                label("")
                Text(slot == .hold
                     ? "Records from the AU05 mic while held. Set a transcription command in Settings › Voice."
                     : "Starts or stops recording on each press. Tip: use the Hold slot for push-to-talk.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .multi, .random:
            if action.type == .multi {
                GridRow {
                    label("Delay")
                    HStack(spacing: 8) {
                        TextField("", value: Binding(get: { action.delay ?? 0.1 }, set: { action.delay = max(0, $0) }),
                                  format: .number)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .frame(width: 44)
                            .modifier(FieldBackground())
                        Text("seconds between steps")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.tertiary)
                    }
                }
            }
            GridRow(alignment: .top) {
                label("Steps").padding(.top, 8)
                SubActionList(actions: Binding(get: { action.actions ?? [] }, set: { action.actions = $0 }))
            }
        }
    }

    @ViewBuilder
    private func label(_ text: String) -> some View {
        if !nested { FieldLabel(text) }
    }

    private func str(_ keyPath: WritableKeyPath<Action, String?>) -> Binding<String> {
        Binding(get: { action[keyPath: keyPath] ?? "" }, set: { action[keyPath: keyPath] = $0 })
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        if panel.runModal() == .OK, let url = panel.url { action.app = url.path }
    }
}

/// Steps of a Multi / Random action.
struct SubActionList: View {
    @Binding var actions: [Action]
    private let types = ActionType.allCases.filter { ![.multi, .random, .voice].contains($0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(actions.indices), id: \.self) { i in
                HStack(alignment: .center, spacing: 10) {
                    Text("\(i + 1)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.white.opacity(0.07)))
                    ChoiceMenu(selection: Binding(get: { step(i).type }, set: { setStep(i, .blank($0)) }),
                               options: types, title: { $0.label }, icon: { $0.symbol }, width: 160)
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                        ActionFields(action: Binding(get: { step(i) }, set: { setStep(i, $0) }), slot: .tap, nested: true)
                    }
                    Button { if actions.indices.contains(i) { actions.remove(at: i) } } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(IconButtonStyle(destructive: true, size: 26))
                    .help("Remove step")
                }
            }
            Button { actions.append(.blank(.hotkey)) } label: {
                Label("Add Step", systemImage: "plus")
            }
            .buttonStyle(LinkButtonStyle())
        }
    }

    // Index-safe accessors: rows can briefly outlive a removed step.
    private func step(_ i: Int) -> Action { actions.indices.contains(i) ? actions[i] : .blank(.hotkey) }
    private func setStep(_ i: Int, _ a: Action) { if actions.indices.contains(i) { actions[i] = a } }
}
