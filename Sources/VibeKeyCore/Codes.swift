import Foundation

/// Which physical index (from decoded key notices) belongs to which control.
/// The protocol's standard layout is used unless the calibration wizard saved a custom one
/// to layout.json (e.g. if a firmware update ever reorders the controls).
public struct ControlLayout: Codable, Equatable, Sendable {
    /// Keyed by role: mic, check, x, knobPress, knobRight, knobLeft.
    public var indices: [String: Int]
    public var calibratedAt: Date?

    public static let roles = ["mic", "check", "x", "knobPress", "knobRight", "knobLeft"]
    public static let standard = ControlLayout(indices: ["mic": 0, "check": 1, "x": 2, "knobPress": 3, "knobRight": 4, "knobLeft": 5])

    public init(indices: [String: Int], calibratedAt: Date? = nil) {
        self.indices = indices
        self.calibratedAt = calibratedAt
    }

    public var isCustom: Bool { calibratedAt != nil }

    /// Maps a decoded key notice to a logical event. Knob turns only report "down".
    public func event(index: Int, down: Bool) -> RawEvent? {
        guard let role = indices.first(where: { $0.value == index })?.key else { return nil }
        switch role {
        case "mic": return down ? .micPress : .micRelease
        case "check": return down ? .checkPress : .checkRelease
        case "x": return down ? .xPress : .xRelease
        case "knobPress": return down ? .knobPress : .knobRelease
        case "knobRight": return down ? .knobRight : nil
        case "knobLeft": return down ? .knobLeft : nil
        default: return nil
        }
    }

    public static func load() -> ControlLayout {
        guard let data = try? Data(contentsOf: Paths.layoutFile),
              let layout = try? JSONDecoder.iso.decode(ControlLayout.self, from: data),
              Set(layout.indices.keys) == Set(roles) else { return .standard }
        return layout
    }

    public func save() throws {
        let enc = JSON.encoder
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(self).write(to: Paths.layoutFile, options: .atomic)
    }

    public static func reset() {
        try? FileManager.default.removeItem(at: Paths.layoutFile)
    }
}

extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

/// Calibration wizard: prompts for each control and records which physical index it reports.
/// Works on decoded key-down notices only, so battery/status messages and releases can't be
/// mistaken for a press.
public final class Calibrator {
    public struct Step {
        public let role: String
        public let press: RawEvent
        public let prompt: String
    }

    public static let steps: [Step] = [
        Step(role: "knobRight", press: .knobRight, prompt: "Turn the knob RIGHT (clockwise) one click"),
        Step(role: "knobLeft", press: .knobLeft, prompt: "Turn the knob LEFT (counter-clockwise) one click"),
        Step(role: "knobPress", press: .knobPress, prompt: "Press and release the KNOB"),
        Step(role: "mic", press: .micPress, prompt: "Press and release the MIC button"),
        Step(role: "check", press: .checkPress, prompt: "Press and release the CHECK (Confirm) button"),
        Step(role: "x", press: .xPress, prompt: "Press and release the X (Cancel) button"),
    ]

    /// `step` is 1-based.
    public var onPrompt: ((_ step: Int, _ total: Int, _ text: String) -> Void)?
    public var onCapture: ((RawEvent, String) -> Void)?
    public var onNote: ((String) -> Void)?
    public var onFinish: ((ControlLayout) -> Void)?

    public private(set) var captured: [String: Int] = [:]
    public private(set) var finished = false
    private var index = 0

    public init() {}

    public func start() {
        index = 0
        captured = [:]
        finished = false
        promptCurrent()
    }

    public func feed(index physical: Int, down: Bool) {
        guard down, !finished, index < Self.steps.count else { return }
        if captured.values.contains(physical) {
            onNote?("That control is already assigned — \(Self.steps[index].prompt.lowercased()).")
            return
        }
        let step = Self.steps[index]
        captured[step.role] = physical
        onCapture?(step.press, "index \(physical)")
        index += 1
        promptCurrent()
    }

    private func promptCurrent() {
        if index >= Self.steps.count {
            finished = true
            onFinish?(ControlLayout(indices: captured, calibratedAt: Date()))
            return
        }
        onPrompt?(index + 1, Self.steps.count, Self.steps[index].prompt)
    }
}
