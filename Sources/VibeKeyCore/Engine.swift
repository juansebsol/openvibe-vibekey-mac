import Foundation

/// Ties together HID listening, host mode, decoding, gestures, config and action execution.
/// All callbacks run on the main thread.
public final class VibeEngine {
    public let store: ConfigStore
    public private(set) var layout: ControlLayout
    public let recorder = VoiceRecorder()
    public let runner: ActionRunner
    public let gestures = GestureEngine()
    public var paused = false

    public var onConnectionChange: ((Bool) -> Void)?
    public var onRawEvent: ((RawEvent) -> Void)?
    /// Every decoded message from the device (keys, battery, status), for diagnostics.
    public var onMessage: ((DeviceMessage) -> Void)?
    public var onBattery: ((Int) -> Void)?
    public var onConfigChange: ((AppConfig) -> Void)?
    public var onLog: ((String) -> Void)?

    private let vendor = HIDDeviceWatcher(usagePage: AU05.vendorUsagePage)
    private let link: HostLink
    private var calibrator: Calibrator?

    public var isConnected: Bool { vendor.isConnected }
    public var config: AppConfig { store.config }

    public init(store: ConfigStore = ConfigStore()) {
        self.store = store
        layout = ControlLayout.load()
        link = HostLink(watcher: vendor)
        runner = ActionRunner(voice: recorder)
        runner.switchProfile = { [weak self] name in self?.setActiveProfile(name) }
        runner.log = { [weak self] in self?.onLog?($0) }
        recorder.log = { [weak self] in self?.onLog?($0) }
        link.onError = { [weak self] in self?.onLog?($0) }
        gestures.binding = { [weak self] c in self?.store.config.current[c] }
        gestures.onGesture = { [weak self] c, g in self?.dispatch(c, g) }
        store.onExternalChange = { [weak self] cfg in
            self?.apply(cfg)
            self?.onConfigChange?(cfg)
        }
        store.onError = { [weak self] in self?.onLog?($0) }
        vendor.onConnectionChange = { [weak self] connected in
            guard let self else { return }
            if connected {
                self.link.begin()
            } else {
                self.link.end(release: false)
                self.gestures.reset()
            }
            self.onConnectionChange?(connected)
        }
        vendor.onReport = { [weak self] _, payload in self?.handle(payload) }
        apply(store.config)
    }

    public func start() {
        let r = vendor.start()
        if r != kIOReturnSuccess { onLog?(String(format: "IOHIDManagerOpen returned 0x%08x", r)) }
        store.startWatching()
    }

    /// Hands the device back to its own shortcuts. Call before quitting.
    public func shutdown() {
        link.end(release: true)
    }

    public func update(_ cfg: AppConfig) {
        store.save(cfg)
        apply(cfg)
    }

    public func setActiveProfile(_ name: String) {
        var cfg = store.config
        guard cfg.profiles.contains(where: { $0.name == name }) else { return }
        cfg.activeProfile = name
        update(cfg)
        onConfigChange?(cfg)
    }

    // MARK: Calibration

    public func startCalibration(_ cal: Calibrator) {
        gestures.reset()
        calibrator = cal
        let finish = cal.onFinish
        cal.onFinish = { [weak self] layout in
            try? layout.save()
            self?.layout = layout
            self?.calibrator = nil
            finish?(layout)
        }
        cal.start()
    }

    public func cancelCalibration() { calibrator = nil }

    public func resetLayout() {
        ControlLayout.reset()
        layout = .standard
    }

    // MARK: Internals

    private func apply(_ cfg: AppConfig) {
        gestures.longPressSeconds = cfg.longPressSeconds
        recorder.settings = cfg.voice
    }

    private func handle(_ payload: Data) {
        let message = DeviceMessage(plaintext: AU05Protocol.plaintext(payload))
        onMessage?(message)
        switch message {
        case let .key(index, down, _):
            if let cal = calibrator { cal.feed(index: index, down: down); return }
            guard let ev = layout.event(index: index, down: down) else { return }
            onRawEvent?(ev)
            guard !paused else { return }
            gestures.handle(ev)
        case let .battery(_, percent):
            onBattery?(percent)
        case .other:
            break
        }
    }

    private func dispatch(_ c: Control, _ g: Gesture) {
        let cfg = store.config.current[c]
        switch g {
        case .tap: cfg.tap.map { runner.perform($0, phase: .fire) }
        case .longPress: cfg.longPress.map { runner.perform($0, phase: .fire) }
        case .holdStart: cfg.hold.map { runner.perform($0, phase: .down) }
        case .holdEnd: cfg.hold.map { runner.perform($0, phase: .up) }
        case .turnLeft: cfg.left.map { runner.perform($0, phase: .fire) }
        case .turnRight: cfg.right.map { runner.perform($0, phase: .fire) }
        }
    }
}
