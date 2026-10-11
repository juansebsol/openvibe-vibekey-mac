import AppKit
import Foundation
import VibeKeyCore

/// `vibekey-cli monitor`: live view of everything the AU05 sends, on both HID channels,
/// for troubleshooting. Also appends to monitor.log so the session can be reviewed later.
final class Monitor {
    private var watchers: [HIDDeviceWatcher] = []
    private let layout = ControlLayout.load()
    private var link: HostLink?
    private var counts: [String: Int] = [:]          // summary key -> count
    private var order: [String] = []
    private var lastTime: Date?
    private var ulanziRunning: Bool?
    private var signalSource: DispatchSourceSignal?
    private let log: FileHandle?
    private let color = isatty(STDOUT_FILENO) != 0

    static let logURL = Paths.supportDir.appendingPathComponent("monitor.log")

    init() {
        FileManager.default.createFile(atPath: Self.logURL.path, contents: nil)
        log = try? FileHandle(forWritingTo: Self.logURL)
    }

    func run() {
        header()
        startWatchers()
        watchUlanzi()
        signal(SIGINT, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        src.setEventHandler { [weak self] in self?.finish() }
        src.resume()
        signalSource = src
    }

    // MARK: Setup

    private func header() {
        let monitoring = InputMonitoring.granted
        emit("")
        emit(paint("VibeKey monitor", .bold) + " — press controls on the AU05 and watch what arrives.")
        emit("  Layout:            " + (layout.isCustom ? "custom (layout.json)" : "standard"))
        emit("  Host mode:         on while running (same heartbeat Ulanzi Studio sends)")
        emit("  Keyboard channel:  " + (monitoring ? paint("shown", .green)
                                        : paint("hidden", .dim) + paint(" (optional: needs Input Monitoring for your terminal)", .dim)))
        emit("  Log file:          \(Self.logURL.path)")
        emit(paint("  Ctrl-C to stop and print a summary.", .dim))
        emit("")
        emit(paint("  time          gap     channel   code / decoded", .dim))
    }

    private func startWatchers() {
        let vendor = HIDDeviceWatcher(usagePage: AU05.vendorUsagePage)
        let link = HostLink(watcher: vendor)
        self.link = link
        vendor.onConnectionChange = { [weak self] connected in
            self?.status(connected ? "AU05 connected — host mode on" : "AU05 disconnected")
            if connected { link.begin() } else { link.end(release: false) }
        }
        vendor.onReport = { [weak self] _, data in self?.vendorReport(data) }
        vendor.start()
        watchers.append(vendor)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            if !vendor.isConnected { self?.status("Waiting for AU05 (VID 0xFFF1, PID 0x00DD)…") }
        }

        guard InputMonitoring.granted else { return }
        let keyboard = HIDDeviceWatcher(usagePage: AU05.firmwareUsagePage)
        keyboard.onConnectionChange = { [weak self] in if $0 { self?.status("keyboard/media channel connected") } }
        keyboard.onReport = { [weak self] id, data in self?.firmwareReport(id, data) }
        let r = keyboard.start()
        if r != kIOReturnSuccess { status(String(format: "keyboard channel could not be opened (0x%08x)", r)) }
        watchers.append(keyboard)
    }

    private func watchUlanzi() {
        func check() {
            let running = NSWorkspace.shared.runningApplications.contains { app in
                [app.bundleIdentifier, app.localizedName].compactMap { $0?.lowercased() }.contains { $0.contains("ulanzi") }
            }
            if running != ulanziRunning {
                status(running ? paint("Ulanzi Studio is RUNNING — quit it, it competes for the device", .yellow)
                               : "Ulanzi Studio is not running")
                ulanziRunning = running
            }
        }
        check()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in check() }
    }

    // MARK: Reports

    private func vendorReport(_ data: Data) {
        let message = DeviceMessage(plaintext: AU05Protocol.plaintext(data))
        switch message {
        case let .key(index, down, _):
            let event = layout.event(index: index, down: down)
            let name = event?.rawValue ?? (down ? "index \(index) down" : "index \(index) up")
            line("KEY     ", paint(name, .green) + paint("  (\(message.summary))", .dim), summaryKey: "KEY       \(name)")
        case .battery:
            line("BATTERY ", paint(message.summary, .dim), summaryKey: "BATTERY")
        case .other:
            line("NOTICE  ", paint(message.summary, .dim), summaryKey: "NOTICE    \(message.summary)")
        }
    }

    private func firmwareReport(_ reportID: UInt32, _ raw: Data) {
        var data = raw
        if let first = data.first, reportID != 0, UInt32(first) == reportID { data.removeFirst() }
        let bytes = [UInt8](data)
        let hex = Fingerprint.hex(data)
        switch reportID {
        case 1:  // Consumer control: 16-bit usage
            let usage = bytes.count >= 2 ? Int(bytes[0]) | Int(bytes[1]) << 8 : Int(bytes.first ?? 0)
            let name = usage == 0 ? "(released)" : (Self.consumerNames[usage] ?? String(format: "usage 0x%04X", usage))
            line("MEDIA   ", paint(name, .cyan) + paint("  [\(hex)]", .dim), summaryKey: "MEDIA     \(name)")
        case 3:  // Keyboard: modifiers, reserved, up to 6 keys
            let mods = bytes.first ?? 0
            let keys = bytes.dropFirst(2).filter { $0 != 0 }
            let text = mods == 0 && keys.isEmpty ? "(all keys released)" : Self.describe(mods: mods, keys: Array(keys))
            line("KEYBOARD", paint(text, .cyan) + paint("  [\(hex)]", .dim), summaryKey: "KEYBOARD  \(text)")
        case 2:  // Mouse: buttons, x, y, wheel, pan
            let s = bytes.map { Int(Int8(bitPattern: $0)) }
            let text = s.count >= 4 ? "buttons=\(bytes[0]) x=\(s[1]) y=\(s[2]) wheel=\(s[3])" + (s.count > 4 ? " pan=\(s[4])" : "") : "mouse"
            line("MOUSE   ", paint(text, .cyan) + paint("  [\(hex)]", .dim), summaryKey: "MOUSE     \(text)")
        default:
            line("HID id=\(reportID)", hex, summaryKey: "HID \(reportID) \(hex)")
        }
    }

    // MARK: Output

    private func line(_ channel: String, _ text: String, summaryKey: String) {
        let now = Date()
        var gap = "        "
        if let last = lastTime {
            let dt = now.timeIntervalSince(last)
            if dt > 1.5 { emit("") }  // blank line between separate physical actions
            gap = String(format: "%+6.3fs", dt).padding(toLength: 8, withPad: " ", startingAt: 0)
        }
        lastTime = now
        emit("  \(Self.stamp(now))  \(paint(gap, .dim))  \(channel)  \(text)")
        if counts[summaryKey] == nil { order.append(summaryKey) }
        counts[summaryKey, default: 0] += 1
    }

    private func status(_ text: String) {
        emit(paint("  ── \(text)", .dim))
    }

    private func finish() {
        if !vibeKeyAppRunning { link?.end(release: true) }
        emit("")
        emit(paint("Summary", .bold) + " (each distinct report, in order of first appearance):")
        if order.isEmpty { emit("  nothing received") }
        for key in order { emit(String(format: "  %4d×  %@", counts[key] ?? 0, key)) }
        emit("Log: \(Self.logURL.path)")
        exit(0)
    }

    private func emit(_ s: String) {
        print(s)
        log?.write(Data((Self.stripANSI(s) + "\n").utf8))
    }

    // MARK: Helpers

    private enum Style: String { case bold = "1", dim = "2", green = "32", yellow = "33", cyan = "36" }

    private func paint(_ s: String, _ style: Style) -> String {
        color ? "\u{1B}[\(style.rawValue)m\(s)\u{1B}[0m" : s
    }

    private static func stripANSI(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
    }

    private static func stamp(_ d: Date, date: Bool = false) -> String {
        let f = DateFormatter()
        f.dateFormat = date ? "yyyy-MM-dd HH:mm" : "HH:mm:ss.SSS"
        return f.string(from: d)
    }

    static func describe(mods: UInt8, keys: [UInt8]) -> String {
        let modNames: [(UInt8, String)] = [(0x01, "⌃"), (0x10, "⌃"), (0x04, "⌥"), (0x40, "⌥"),
                                           (0x02, "⇧"), (0x20, "⇧"), (0x08, "⌘"), (0x80, "⌘")]
        var out = ""
        for (bit, sym) in modNames where mods & bit != 0 && !out.contains(sym) { out += sym }
        let names = keys.map { keyboardNames[$0] ?? String(format: "key 0x%02X", $0) }
        return out + names.joined(separator: "+") + (keys.isEmpty ? " (modifiers only)" : "")
    }

    static let keyboardNames: [UInt8: String] = {
        var m: [UInt8: String] = [:]
        for (i, c) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() { m[UInt8(0x04 + i)] = String(c) }
        for (i, c) in "1234567890".enumerated() { m[UInt8(0x1E + i)] = String(c) }
        for i in 0..<12 { m[UInt8(0x3A + i)] = "F\(i + 1)" }
        let named: [UInt8: String] = [0x28: "Return", 0x29: "Esc", 0x2A: "Delete", 0x2B: "Tab", 0x2C: "Space",
                                      0x2D: "-", 0x2E: "=", 0x2F: "[", 0x30: "]", 0x31: "\\", 0x33: ";", 0x34: "'",
                                      0x35: "`", 0x36: ",", 0x37: ".", 0x38: "/", 0x4A: "Home", 0x4B: "PageUp",
                                      0x4C: "ForwardDelete", 0x4D: "End", 0x4E: "PageDown", 0x4F: "→", 0x50: "←",
                                      0x51: "↓", 0x52: "↑"]
        m.merge(named) { $1 }
        return m
    }()

    static let consumerNames: [Int: String] = [
        0xE9: "Volume Up", 0xEA: "Volume Down", 0xE2: "Mute", 0xCD: "Play/Pause", 0xB5: "Next Track",
        0xB6: "Previous Track", 0xB7: "Stop", 0x6F: "Brightness Up", 0x70: "Brightness Down",
        0x223: "Home", 0x224: "Back", 0x225: "Forward", 0x192: "Calculator", 0x194: "File Browser",
    ]
}
