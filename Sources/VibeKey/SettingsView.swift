import SwiftUI
import AppKit
import VibeKeyCore

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.text)
                Spacer()
                PillSegments(options: SettingsTab.allCases, selection: $state.settingsTab,
                             title: { $0.rawValue }, icon: { $0.symbol })
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 6)

            Form {
                switch state.settingsTab {
                case .general: general
                case .voice: voice
                case .device: device
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 600, height: 520)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
        .tint(Theme.teal)
    }

    // MARK: Tabs

    @ViewBuilder private var general: some View {
        Section {
            Toggle("Launch Vibe Key at login", isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) }))
            Toggle("Open the editor when Vibe Key launches", isOn: $state.config.openEditorAtLaunch)
            Toggle("Show a notification when the profile changes", isOn: $state.config.showProfileHUD)
        }
        Section {
            LabeledContent("Long-press time") {
                HStack(spacing: 12) {
                    Slider(value: Binding(get: { state.config.longPressSeconds },
                                          set: { state.config.longPressSeconds = ($0 * 20).rounded() / 20 }),
                           in: 0.2...1.5)
                        .frame(width: 200)
                    Text(String(format: "%.2f s", state.config.longPressSeconds))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
            }
        } footer: {
            footer("How long a button must be held before its Long Press action fires.")
        }
    }

    @ViewBuilder private var voice: some View {
        Section {
            TextField("Microphone name contains", text: $state.config.voice.deviceName, prompt: Text("AU05"))
            LabeledContent("Save recordings to") {
                HStack(spacing: 8) {
                    Text(saveFolderLabel)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !state.config.voice.saveDirectory.isEmpty {
                        Button("Reset") { state.config.voice.saveDirectory = "" }
                    }
                    Button("Choose…") { chooseFolder() }
                }
            }
        } footer: {
            footer("Recordings are 16 kHz mono WAV files. Your system's default input is never changed.")
        }
        Section {
            TextField("Command", text: $state.config.voice.command,
                      prompt: Text("whisper-cli -m ~/models/ggml-base.en.bin -nt -np -f {file}"), axis: .vertical)
                .labelsHidden()
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1...3)
            Toggle("Type the command's output into the front app", isOn: $state.config.voice.typeResult)
            Toggle("Delete the recording once the command succeeds", isOn: $state.config.voice.deleteAfterCommand)
        } header: {
            Text("After each recording, run")
        } footer: {
            footer("{file} is replaced with the recording's path. Leave empty to just keep the recordings.")
        }
    }

    @ViewBuilder private var device: some View {
        Section {
            LabeledContent("Connection") {
                Text(state.connected ? "Connected" + (state.battery.map { " · battery \($0)%" } ?? "") : "Not connected")
                    .foregroundStyle(Theme.secondary)
            }
            LabeledContent("Control layout") {
                HStack(spacing: 10) {
                    Text(calibrationStatus).foregroundStyle(Theme.secondary)
                    if state.customLayout {
                        Button("Reset") { state.resetLayout() }
                    }
                    Button("Test…") {
                        state.showSettings = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { state.openCalibration() }
                    }
                }
            }
        } header: {
            Text("Device")
        } footer: {
            footer("While Vibe Key runs it keeps the AU05 in host mode with the same heartbeat Ulanzi Studio sends, so the device reports every press and stops typing its own shortcuts. Nothing on the device is changed; it goes back to its own shortcuts when Vibe Key quits.")
        }
        Section("Permissions") {
            LabeledContent("Accessibility") {
                if state.accessibilityTrusted {
                    statusLabel("Allowed", ok: true)
                } else {
                    Button("Allow…") { state.requestAccessibility() }
                }
            }
            LabeledContent("Microphone") {
                Text("Asked the first time you record").foregroundStyle(Theme.tertiary)
            }
        }
        Section("Files") {
            LabeledContent("Configuration") {
                HStack(spacing: 10) {
                    Text("config.json").font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.secondary)
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Paths.configFile]) }
                }
            }
        }
    }

    // MARK: Helpers

    private func footer(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func statusLabel(_ text: String, ok: Bool) -> some View {
        Label(text, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
            .foregroundStyle(ok ? Theme.teal : Theme.amber)
    }

    private var calibrationStatus: String {
        guard state.customLayout, let date = state.calibratedAt else { return "Standard" }
        return "Custom, \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private var saveFolderLabel: String {
        let dir = state.config.voice.saveDirectory
        return dir.isEmpty ? "Application Support (default)" : (dir as NSString).abbreviatingWithTildeInPath
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { state.config.voice.saveDirectory = url.path }
    }
}
