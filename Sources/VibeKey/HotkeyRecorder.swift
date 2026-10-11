import SwiftUI
import AppKit
import VibeKeyCore

/// Click the field and press a key combo. The raw string stays editable (e.g. "ctrl+d")
/// for combos macOS won't let an app record, and a menu offers common keys.
struct HotkeyRecorder: View {
    @Binding var keys: String
    var compact = false
    @State private var recording = false
    @State private var monitor: Any?

    private static let presets = ["return", "escape", "space", "tab", "delete",
                                  "up", "down", "left", "right",
                                  "cmd+c", "cmd+v", "cmd+z", "cmd+shift+z", "cmd+w", "cmd+t", "cmd+tab"]

    var body: some View {
        let parsed = Hotkey(string: keys)
        HStack(spacing: 8) {
            Button { recording ? stop() : start() } label: {
                HStack(spacing: 4) {
                    if recording {
                        Text("Press a shortcut…")
                            .foregroundStyle(Theme.teal)
                    } else if let parsed {
                        ForEach(Array(caps(parsed).enumerated()), id: \.offset) { KeyCap(label: $0.element) }
                    } else {
                        Text("Click to record")
                            .foregroundStyle(Theme.tertiary)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: recording ? "record.circle" : "keyboard")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(recording ? Theme.red : Theme.tertiary)
                }
                .font(.system(size: 13))
                .frame(width: compact ? 150 : 190, alignment: .leading)
                .modifier(FieldBackground(focused: recording))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click, then press the key combination")

            if !compact {
                VKTextField(placeholder: "ctrl+shift+d", text: $keys, mono: true,
                            invalid: !keys.isEmpty && parsed == nil)
                    .frame(width: 150)
                    .help("Or type it: modifiers ctrl, alt, shift, cmd, fn + a key")
            }

            Menu {
                ForEach(Self.presets, id: \.self) { k in
                    Button(Hotkey(string: k)?.display ?? k) { keys = k }
                }
                Divider()
                Button("Clear") { keys = "" }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 30, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.field))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.stroke))
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Common keys")
        }
        .onDisappear(perform: stop)
    }

    private func caps(_ hk: Hotkey) -> [String] {
        let symbols = ["ctrl": "⌃", "alt": "⌥", "shift": "⇧", "cmd": "⌘", "fn": "fn"]
        let key = KeyTable.displayNames[hk.keyName] ?? hk.keyName.uppercased()
        return hk.modifiers.map { symbols[$0] ?? $0 } + [key]
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            keys = Hotkey(keyCode: event.keyCode, flags: flags).string
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
