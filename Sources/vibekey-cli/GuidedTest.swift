import AppKit
import Foundation
import VibeKeyCore

/// `vibekey-cli test`: asks for one control at a time, waits for it, and says whether the
/// right event arrived. Actions are not performed. Results also go to test.log.
final class GuidedTest {
    private struct Step {
        let instruction: String
        let expected: RawEvent
        var got: [String] = []
        var passed = false
    }

    private var steps: [Step] = [
        Step(instruction: "Press and release the MIC button", expected: .micPress),
        Step(instruction: "Press and release the ✓ CONFIRM button", expected: .checkPress),
        Step(instruction: "Press and release the ✕ CANCEL button", expected: .xPress),
        Step(instruction: "Turn the KNOB one click RIGHT (clockwise)", expected: .knobRight),
        Step(instruction: "Turn the KNOB one click LEFT (counter-clockwise)", expected: .knobLeft),
        Step(instruction: "PRESS the knob down and release it", expected: .knobPress),
    ]

    private let engine = VibeEngine()
    private var current: Int?
    private var generation = 0
    private let log: FileHandle?
    private let color = isatty(STDOUT_FILENO) != 0

    static let logURL = Paths.supportDir.appendingPathComponent("test.log")
    private static let timeout: TimeInterval = 20

    init() {
        FileManager.default.createFile(atPath: Self.logURL.path, contents: nil)
        log = try? FileHandle(forWritingTo: Self.logURL)
    }

    func run() {
        say(paint("VibeKey device test", .bold) + " — checks each control, one at a time. Nothing is triggered.")
        say("")
        engine.paused = true  // decode only, never run actions
        engine.onMessage = { [weak self] in self?.message($0) }
        engine.onRawEvent = { [weak self] in self?.event($0) }
        engine.start()
        onExit { [engine] in if !vibeKeyAppRunning { engine.shutdown() } }

        // Give IOKit a moment to match the device and host mode to settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
            let ulanzi = NSWorkspace.shared.runningApplications.contains { app in
                [app.bundleIdentifier, app.localizedName].compactMap { $0?.lowercased() }.contains { $0.contains("ulanzi") }
            }
            check(engine.isConnected, "AU05 connected, host mode on", "AU05 not found — plug in the USB receiver and run again")
            check(!ulanzi, "Ulanzi Studio not running", "Ulanzi Studio is running — quit it first (it competes for the device)")
            guard engine.isConnected else { exit(1) }
            say("")
            say("Press " + paint("Enter", .bold) + " to start.")
            DispatchQueue.global().async {
                _ = readLine()
                DispatchQueue.main.async { self.begin(0) }
            }
        }
    }

    private func begin(_ i: Int) {
        guard i < steps.count else { finish(); return }
        current = i
        generation += 1
        let g = generation
        say("")
        say(paint("Step \(i + 1)/\(steps.count)  \(steps[i].instruction)", .bold) + paint("   (waiting up to \(Int(Self.timeout))s)", .dim))
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout) { [self] in
            guard generation == g, current == i else { return }
            say(paint("        ✗ nothing arrived", .yellow))
            next(after: i)
        }
    }

    private func message(_ m: DeviceMessage) {
        guard current != nil else { return }
        switch m {
        case .battery: say(paint("        · \(m.summary)", .dim))
        case .other: say(paint("        · \(m.summary)", .dim))
        case .key: break  // reported via event()
        }
    }

    private func event(_ e: RawEvent) {
        guard let i = current else { return }
        steps[i].got.append(e.rawValue)
        if e == steps[i].expected {
            steps[i].passed = true
            say(paint("        ✓ \(e.rawValue)", .green))
            next(after: i)
        } else if e.isRelease {
            say(paint("        · \(e.rawValue)", .dim))
        } else {
            say(paint("        ✗ got \(e.rawValue), expected \(steps[i].expected.rawValue)", .yellow))
        }
    }

    private func next(after i: Int) {
        current = nil  // the release of this press shouldn't count for the next step
        generation += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in begin(i + 1) }
    }

    private func finish() {
        let passed = steps.filter(\.passed).count
        say("")
        say(paint("Result: \(passed)/\(steps.count) controls OK", .bold))
        for s in steps {
            say("  " + (s.passed ? paint("✓", .green) : paint("✗", .yellow)) + "  "
                + s.expected.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)
                + (s.got.isEmpty ? "nothing arrived" : s.got.joined(separator: ", ")))
        }
        say("")
        say(passed == steps.count ? "Everything works. Open Vibe Key and assign actions."
                                  : "Some controls failed — run `vibekey-cli calibrate` to remap them, then test again.")
        say("Saved to \(Self.logURL.path)")
        if !vibeKeyAppRunning { engine.shutdown() }
        exit(passed == steps.count ? 0 : 1)
    }

    private func check(_ ok: Bool, _ good: String, _ bad: String) {
        say(ok ? paint("  ✓ ", .green) + good : paint("  ✗ ", .yellow) + bad)
    }

    private func say(_ s: String) {
        print(s)
        log?.write(Data((s.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression) + "\n").utf8))
    }

    private enum Style: String { case bold = "1", dim = "2", green = "32", yellow = "33" }
    private func paint(_ s: String, _ style: Style) -> String {
        color ? "\u{1B}[\(style.rawValue)m\(s)\u{1B}[0m" : s
    }
}
