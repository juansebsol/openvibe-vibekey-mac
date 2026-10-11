import Foundation

/// Static facts about the Ulanzi AU05 "Vibe Key".
public enum AU05 {
    public static let vendorID = 0xFFF1
    public static let productID = 0x00DD
    /// Vendor-defined interface carrying every control event (no permission needed).
    public static let vendorUsagePage = 0xFFFC
    /// Consumer/keyboard/mouse interface where the firmware emits its own key combos.
    public static let firmwareUsagePage = 0x0C
    public static let vendorReportID: UInt32 = 0x55
    /// Number of leading payload bytes that identify an event.
    public static let fingerprintLength = 8
}

public enum Control: String, Codable, CaseIterable, Identifiable, Sendable {
    case knob, mic, check, x
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .knob: return "Knob"
        case .mic: return "Mic"
        case .check: return "Confirm"
        case .x: return "Cancel"
        }
    }
    public var isKnob: Bool { self == .knob }
}

/// Logical events decoded from the vendor interface.
public enum RawEvent: String, Codable, CaseIterable, Sendable {
    case knobLeft, knobRight, knobPress, knobRelease
    case micPress, micRelease, checkPress, checkRelease, xPress, xRelease

    public var control: Control {
        switch self {
        case .knobLeft, .knobRight, .knobPress, .knobRelease: return .knob
        case .micPress, .micRelease: return .mic
        case .checkPress, .checkRelease: return .check
        case .xPress, .xRelease: return .x
        }
    }
    public var isPress: Bool { [.knobPress, .micPress, .checkPress, .xPress].contains(self) }
    public var isRelease: Bool { [.knobRelease, .micRelease, .checkRelease, .xRelease].contains(self) }
}

public enum Fingerprint {
    /// Hex of the first 8 payload bytes (report ID already stripped).
    public static func of(_ payload: Data) -> String {
        payload.prefix(AU05.fingerprintLength).map { String(format: "%02x", $0) }.joined()
    }
    public static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
