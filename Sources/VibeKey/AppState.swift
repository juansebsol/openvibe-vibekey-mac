import SwiftUI
import AppKit
import ServiceManagement
import VibeKeyCore

/// What the calibration sheet shows. Driven by the Calibrator's callbacks.
struct CalibrationProgress {
    enum Phase: Equatable { case intro, step(Int), done }
    var phase: Phase = .intro
    var captured: [(event: RawEvent, code: String)] = []
    var notes: [String] = []
}

enum SettingsTab: String, CaseIterable, Hashable {
    case general = "General", voice = "Voice", device = "Device"
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .voice: return "waveform"
        case .device: return "dial.medium"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    let engine: VibeEngine
    /// False in snapshot mode: the UI can be driven freely without touching config.json.
    let persist: Bool

    @Published var config: AppConfig {
        didSet {
            if persist && !applyingExternal && config != oldValue { engine.update(config) }
            // Device, menu bar or editor: whatever changed the profile, say so.
            if config.activeProfile != oldValue.activeProfile && config.showProfileHUD {
                ProfileHUD.shared.show(name: config.activeProfile, index: config.activeIndex, count: config.profiles.count)
            }
        }
    }
    @Published var connected = false
    @Published var paused = false { didSet { engine.paused = paused } }
    @Published var live: Set<Control> = []
    /// Accumulated knob rotation, so the drawing turns with the real knob.
    @Published var knobAngle: Double = 0
    @Published var selected: Control = .mic
    @Published var slot: Slot = .tap
    @Published var showCalibration = false
    @Published var showSettings = false
    @Published var settingsTab: SettingsTab = .general
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var accessibilityTrusted = Accessibility.trusted
    /// The calibration wizard saved a custom control layout (otherwise the protocol's standard one).
    @Published var customLayout: Bool
    @Published var calibratedAt: Date?
    @Published var battery: Int?
    @Published var recording = false
    @Published var ulanziRunning = false
    @Published var lastLog = ""
    @Published var calibration = CalibrationProgress()

    private var applyingExternal = false
    private var liveTokens: [Control: Int] = [:]
    private var calibrator: Calibrator?

    /// `liveDevice: false` renders the UI without touching the device, prompting, or saving (snapshots).
    init(liveDevice: Bool = true) {
        let engine = VibeEngine()
        self.engine = engine
        persist = liveDevice
        config = engine.config
        customLayout = engine.layout.isCustom
        calibratedAt = engine.layout.calibratedAt
        connected = engine.isConnected

        engine.onConnectionChange = { [weak self] c in
            MainActor.assumeIsolated {
                self?.connected = c
                if !c { self?.battery = nil }
            }
        }
        engine.onBattery = { [weak self] pct in MainActor.assumeIsolated { self?.battery = pct } }
        engine.onConfigChange = { [weak self] cfg in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.applyingExternal = true
                self.config = cfg
                self.applyingExternal = false
            }
        }
        engine.onRawEvent = { [weak self] ev in MainActor.assumeIsolated { self?.flash(ev) } }
        engine.onLog = { [weak self] msg in MainActor.assumeIsolated { self?.lastLog = msg } }
        engine.recorder.onStateChange = { [weak self] r in MainActor.assumeIsolated { self?.recording = r } }
        guard liveDevice else { return }
        engine.start()
        watchForUlanziStudio()

        if !Accessibility.trusted { Accessibility.requestIfNeeded() }
        // Accessibility can be granted at any time in System Settings; poll cheaply.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let t = Accessibility.trusted
                if t != self.accessibilityTrusted { self.accessibilityTrusted = t }
            }
        }
    }

    // MARK: Live highlight

    private func flash(_ ev: RawEvent) {
        let c = ev.control
        if ev == .knobLeft { knobAngle -= 15 }
        if ev == .knobRight { knobAngle += 15 }
        if ev.isRelease { live.remove(c); return }
        live.insert(c)
        let token = (liveTokens[c] ?? 0) + 1
        liveTokens[c] = token
        // Turns and presses without a release code clear themselves.
        let delay = ev.isPress ? 1.5 : 0.3
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            if self?.liveTokens[c] == token { self?.live.remove(c) }
        }
    }

    // MARK: Profile helpers

    var profile: Profile {
        get { config.current }
        set { config.profiles[config.activeIndex] = newValue }
    }

    func controlBinding(_ c: Control) -> Binding<ControlConfig> {
        Binding(get: { self.profile[c] }, set: { self.profile[c] = $0 })
    }

    func actionBinding(_ c: Control, _ s: Slot) -> Binding<Action?> {
        Binding(get: { self.profile[c][s] }, set: { self.profile[c][s] = $0 })
    }

    func select(_ c: Control) {
        guard c != selected || !Slot.slots(for: c).contains(slot) else { return }
        selected = c
        // Show the first slot that has something bound, else the default.
        slot = Slot.slots(for: c).first { profile[c][$0] != nil } ?? Slot.slots(for: c)[0]
    }

    func assign(_ item: PaletteItem, to c: Control) {
        select(c)
        var cc = profile[c]
        if let turn = item.knobTurn {
            guard c.isKnob else { return }
            cc.left = turn.left
            cc.right = turn.right
            slot = .left
        } else {
            if !Slot.slots(for: c).contains(slot) { slot = .tap }
            cc[slot] = item.make()
        }
        if cc.title.isEmpty { cc.title = item.label }
        profile[c] = cc
    }

    func setActiveProfile(_ name: String) {
        guard config.profiles.contains(where: { $0.name == name }) else { return }
        config.activeProfile = name
    }

    func addProfile() {
        var cfg = config
        var name = "Profile \(cfg.profiles.count + 1)"
        while cfg.profiles.contains(where: { $0.name == name }) { name += "′" }
        var p = cfg.current
        p.name = name
        cfg.profiles.append(p)
        cfg.activeProfile = name
        config = cfg
    }

    func renameProfile(_ newName: String) {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !config.profiles.contains(where: { $0.name == n }) else { return }
        var cfg = config
        let old = cfg.activeProfile
        cfg.profiles[cfg.activeIndex].name = n
        cfg.activeProfile = n
        // Keep switchProfile actions pointing at the renamed profile.
        for i in cfg.profiles.indices {
            for (k, var cc) in cfg.profiles[i].controls {
                for s in Slot.allCases where cc[s]?.profile == old { cc[s]?.profile = n }
                cfg.profiles[i].controls[k] = cc
            }
        }
        config = cfg
    }

    func deleteProfile() {
        guard config.profiles.count > 1 else { return }
        var cfg = config
        cfg.profiles.remove(at: cfg.activeIndex)
        cfg.activeProfile = cfg.profiles[0].name
        config = cfg
    }

    // MARK: Calibration

    func openCalibration() {
        if calibration.phase == .done { calibration = CalibrationProgress() }
        showCalibration = true
    }

    func startCalibration() {
        let cal = Calibrator()
        calibration = CalibrationProgress(phase: .step(1))
        cal.onPrompt = { [weak self] i, _, _ in
            MainActor.assumeIsolated { self?.calibration.phase = .step(i) }
        }
        cal.onCapture = { [weak self] ev, code in
            MainActor.assumeIsolated { self?.calibration.captured.append((ev, code)) }
        }
        cal.onNote = { [weak self] note in
            MainActor.assumeIsolated { self?.calibration.notes.append(note) }
        }
        cal.onFinish = { [weak self] map in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.calibration.phase = .done
                self.customLayout = map.isCustom
                self.calibratedAt = map.calibratedAt
                self.calibrator = nil
            }
        }
        calibrator = cal
        engine.startCalibration(cal)
    }

    func resetLayout() {
        engine.resetLayout()
        customLayout = false
        calibratedAt = nil
    }

    func cancelCalibration() {
        if calibration.phase != .done && calibration.phase != .intro { engine.cancelCalibration() }
        calibrator = nil
        calibration = CalibrationProgress()
    }

    // MARK: Ulanzi Studio

    /// Ulanzi Studio reacts to the same device, so every press would fire twice.
    private func watchForUlanziStudio() {
        refreshUlanzi()
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshUlanzi() }
            }
        }
    }

    private var ulanziApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            [app.bundleIdentifier, app.localizedName].compactMap { $0?.lowercased() }.contains { $0.contains("ulanzi") }
        }
    }

    private func refreshUlanzi() { ulanziRunning = !ulanziApps.isEmpty }

    func quitUlanzi() {
        ulanziApps.forEach { $0.terminate() }
    }

    // MARK: System

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            lastLog = "Launch at login failed: \(error.localizedDescription) (run from the bundled .app)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func requestAccessibility() {
        Accessibility.requestIfNeeded()
        Accessibility.openSettings()
    }
}
