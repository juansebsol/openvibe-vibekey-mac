import AppKit
import SwiftUI
import VibeKeyCore

/// Development aid for reviewing the UI without Screen Recording permission (an app may always
/// capture its own windows):
///
///     VIBEKEY_SNAPSHOT_DIR=/tmp/shots build/VibeKey.app/Contents/MacOS/VibeKey
///
/// Walks the editor through a series of states, writes one PNG per window per state, then quits.
/// The device is not opened and nothing is saved to config.json.
@MainActor
enum DebugSnapshot {
    static let directory = ProcessInfo.processInfo.environment["VIBEKEY_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    static var isActive: Bool { directory != nil }

    private struct Step {
        let name: String?
        let act: (AppState) -> Void
    }

    private static let steps: [Step] = [
        Step(name: "01-banners") { s in
            s.connected = false; s.accessibilityTrusted = false; s.ulanziRunning = true
        },
        Step(name: "02-mic") { s in
            s.accessibilityTrusted = true; s.ulanziRunning = false; s.connected = true; s.battery = 90
            s.select(.mic)
        },
        Step(name: "03-knob-live") { s in s.select(.knob); s.live = [.knob]; s.knobAngle = 45 },
        Step(name: "04-check-pressed") { s in s.select(.check); s.live = [.check] },
        Step(name: "05-x-longpress-empty") { s in s.live = []; s.select(.x); s.slot = .longPress },
        Step(name: "06-multi") { s in
            s.select(.check); s.slot = .tap
            s.profile[.check].tap = Action(type: .multi, actions: [
                Action(type: .hotkey, keys: "cmd+a"), Action(type: .text, text: "hello"), Action(type: .media, media: .playPause),
            ], delay: 0.1)
        },
        Step(name: "07-text") { s in s.profile[.check].tap = Action(type: .text, text: "Thanks, looks great!") },
        Step(name: "08-settings-general") { s in s.settingsTab = .general; s.showSettings = true },
        Step(name: "09-settings-voice") { s in s.settingsTab = .voice },
        Step(name: "10-settings-device") { s in s.settingsTab = .device },
        Step(name: nil) { s in s.showSettings = false },
        Step(name: "11-calibrate-intro") { s in s.calibration = CalibrationProgress(); s.showCalibration = true },
        Step(name: "12-calibrate-step") { s in
            s.calibration = CalibrationProgress(phase: .step(4), captured: [
                (.knobRight, "24a1c3d5e6f70812"), (.knobLeft, "9b8a7c6d5e4f3021"),
                (.knobPress, "5566778899aabbcc"), (.knobRelease, "ccbbaa9988776655"),
            ])
        },
        Step(name: "13-calibrate-done") { s in s.calibration.phase = .done },
    ]

    static func run(_ state: AppState) {
        guard let dir = directory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { perform(0, state, dir) }
    }

    private static func perform(_ i: Int, _ state: AppState, _ dir: URL) {
        guard i < steps.count else { exit(0) }
        steps[i].act(state)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if let name = steps[i].name { capture(name, dir) }
            perform(i + 1, state, dir)
        }
    }

    private static func capture(_ name: String, _ dir: URL) {
        let windows = NSApp.windows.filter { $0.isVisible && $0.frame.width > 300 }
        for (n, window) in windows.enumerated() {
            let suffix = n == 0 ? "" : "-sheet"
            if let img = windowImage(CGWindowID(window.windowNumber)) {
                write(NSBitmapImageRep(cgImage: img), dir.appendingPathComponent("\(name)\(suffix).png"))
            } else if let view = window.contentView?.superview,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                write(rep, dir.appendingPathComponent("\(name)\(suffix)-cached.png"))
            }
        }
    }

    private static func write(_ rep: NSBitmapImageRep, _ url: URL) {
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// CGWindowListCreateImage is deprecated in the SDK but still the simplest way to grab our own window.
    private typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    private static func windowImage(_ id: CGWindowID) -> CGImage? {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        let fn = unsafeBitCast(sym, to: CreateImage.self)
        // optionIncludingWindow; boundsIgnoreFraming | bestResolution
        return fn(.null, 1 << 3, id, (1 << 0) | (1 << 3))?.takeRetainedValue()
    }
}
