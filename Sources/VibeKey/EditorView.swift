import SwiftUI
import VibeKeyCore

struct EditorView: View {
    @EnvironmentObject var state: AppState
    let chrome: EditorChrome

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HeaderBar(leadingInset: chrome.leadingInset)
                    .frame(height: chrome.titlebarHeight)
                Hairline()
                Banners()
                DeviceCanvas()
                Hairline()
                ControlEditor()
            }
            .background(Theme.canvas)
            Hairline(vertical: true)
            Sidebar(topInset: chrome.titlebarHeight)
                .frame(width: 304)
        }
        .ignoresSafeArea()
        .sheet(isPresented: $state.showCalibration, onDismiss: { state.cancelCalibration() }) {
            CalibrationView().environmentObject(state)
        }
        .sheet(isPresented: $state.showSettings) {
            SettingsView().environmentObject(state)
        }
    }
}

// MARK: - Header

struct HeaderBar: View {
    @EnvironmentObject var state: AppState
    var leadingInset: CGFloat

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "dial.medium.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.teal)
                Text("Vibe Key")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.text)
            }
            .allowsHitTesting(false)

            StatusChips()
                .allowsHitTesting(false)

            Spacer(minLength: 16)
        }
        .padding(.leading, leadingInset)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowDragArea())
    }
}

/// Profile menu and header buttons, hosted in a real toolbar item (see EditorToolbar).
struct HeaderControls: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            ProfileMenu()

            HStack(spacing: 2) {
                Button { state.paused.toggle() } label: {
                    Image(systemName: state.paused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(IconButtonStyle(active: state.paused))
                .help(state.paused ? "Resume" : "Pause all actions")

                Button { state.openCalibration() } label: { Image(systemName: "scope") }
                    .buttonStyle(IconButtonStyle())
                    .help("Test & calibrate controls…")

                Button { state.showSettings = true } label: { Image(systemName: "gearshape") }
                    .buttonStyle(IconButtonStyle())
                    .help("Settings")
            }
        }
        .padding(.horizontal, 4)
        .fixedSize()
    }
}

struct StatusChips: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 6) {
            chip {
                Circle()
                    .fill(state.connected ? Theme.teal : Theme.tertiary)
                    .frame(width: 7, height: 7)
                    .shadow(color: state.connected ? Theme.teal.opacity(0.9) : .clear, radius: 4)
                Text(state.connected ? "Connected" : "Disconnected")
            }
            if let battery = state.battery, state.connected {
                chip {
                    Image(systemName: battery > 60 ? "battery.75" : battery > 25 ? "battery.50" : "battery.25")
                        .font(.system(size: 11, weight: .medium))
                    Text("\(battery)%")
                }
                .foregroundStyle(battery > 25 ? Theme.secondary : Theme.amber)
            }
            if state.paused {
                chip {
                    Image(systemName: "pause.fill").font(.system(size: 8, weight: .bold))
                    Text("Paused")
                }
                .foregroundStyle(Theme.amber)
            }
            if state.recording {
                chip {
                    Circle().fill(Theme.red).frame(width: 7, height: 7)
                    Text("Recording")
                }
                .foregroundStyle(Theme.red)
            }
        }
    }

    private func chip<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 6, content: content)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(Color.white.opacity(0.05)))
            .overlay(Capsule().strokeBorder(Theme.stroke))
    }
}

struct ProfileMenu: View {
    @EnvironmentObject var state: AppState
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        Menu {
            Picker("Profile", selection: Binding(get: { state.config.activeProfile }, set: { state.setActiveProfile($0) })) {
                ForEach(state.config.profiles) { Text($0.name).tag($0.name) }
            }
            .pickerStyle(.inline)
            Divider()
            Button("New Profile") { state.addProfile() }
            Button("Rename Profile…") { newName = state.config.activeProfile; renaming = true }
            Button("Delete Profile", role: .destructive) { state.deleteProfile() }
                .disabled(state.config.profiles.count < 2)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.rectangle.stack")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                Text(state.config.activeProfile)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.stroke))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Switch profile")
        .alert("Rename Profile", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Rename") { state.renameProfile(newName) }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Banners

struct Banners: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            if state.ulanziRunning {
                BannerRow(icon: "exclamationmark.triangle.fill", tint: Theme.amber,
                          text: "Ulanzi Studio is running and also reacts to the device, so presses fire twice.",
                          action: "Quit Ulanzi Studio") { state.quitUlanzi() }
            }
            if !state.accessibilityTrusted {
                BannerRow(icon: "hand.raised.fill", tint: Theme.amber,
                          text: "Allow Accessibility so Vibe Key can send shortcuts, text, media keys and scrolling.",
                          action: "Open Settings") { state.requestAccessibility() }
            }
        }
    }
}

struct BannerRow: View {
    let icon: String
    let tint: Color
    let text: String
    let action: String
    let perform: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text.opacity(0.9))
                .lineLimit(1)
            Spacer(minLength: 12)
            Button(action, action: perform)
                .buttonStyle(LinkButtonStyle(tint: tint))
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .frame(height: 36)
        .background(tint.opacity(0.07))
        .overlay(alignment: .bottom) { Hairline() }
    }
}
