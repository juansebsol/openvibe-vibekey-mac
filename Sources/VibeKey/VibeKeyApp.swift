import SwiftUI
import AppKit
import VibeKeyCore

@main
struct VibeKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent().environmentObject(delegate.state)
        } label: {
            MenuBarLabel(state: delegate.state)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var state = AppState(liveDevice: !DebugSnapshot.isActive)

    func applicationDidFinishLaunching(_ notification: Notification) {
        if DebugSnapshot.isActive {
            EditorWindow.show(state)
            DebugSnapshot.run(state)
        } else if state.config.openEditorAtLaunch {
            EditorWindow.show(state)
        }
    }

    /// Hand the device back to its own shortcuts.
    func applicationWillTerminate(_ notification: Notification) {
        state.engine.shutdown()
    }

    /// Launching the app again (Finder, Spotlight, `open`) while it runs brings the editor back,
    /// so the UI is reachable even when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        EditorWindow.show(state)
        return true
    }
}

struct MenuBarLabel: View {
    @ObservedObject var state: AppState
    var body: some View {
        Image(systemName: state.connected ? (state.paused ? "pause.circle" : "dial.medium.fill") : "dial.medium")
    }
}

struct MenuContent: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Text(state.connected ? "AU05 connected" + (state.battery.map { " · battery \($0)%" } ?? "") : "AU05 disconnected")
        Divider()
        Button("Open Editor…") { EditorWindow.show(state) }.keyboardShortcut(",")
        Picker("Profile", selection: Binding(get: { state.config.activeProfile }, set: { state.setActiveProfile($0) })) {
            ForEach(state.config.profiles) { Text($0.name).tag($0.name) }
        }
        Toggle("Pause", isOn: $state.paused)
        Toggle("Launch at Login", isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) }))
        Button("Calibrate…") { EditorWindow.show(state); state.openCalibration() }
        if !state.accessibilityTrusted {
            Button("Grant Accessibility…") { state.requestAccessibility() }
        }
        Divider()
        Button("Quit Vibe Key") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
