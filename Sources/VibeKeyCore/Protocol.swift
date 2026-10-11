import Foundation

/// AU05 vendor protocol (usage page 0xFFFC, report 0x55).
///
/// Frames are 64 bytes of plaintext encrypted with TEA (32 rounds, ECB, little-endian words)
/// under a fixed key shared by every unit. This matches the independent write-ups in
/// arumwu/vibekey-lite and MrCroxx/olanzi; the repeating "filler" seen on the wire is simply
/// TEA(00 × 8). On input only the first 7 blocks (56 bytes) can be decrypted.
///
/// Key events (`8b 10 <logical> <state> <index>`) only flow while a host keeps the device in
/// "host online" mode with a heartbeat. Without it the firmware types its stored shortcuts on
/// the standard HID interface instead.
public enum AU05Protocol {
    public static let reportID: UInt8 = 0x55
    public static let frameLength = 64

    public static let heartbeat: [UInt8] = [0x06, 0x01, 0x23, 0x00, 0x01]
    public static func hostOnline(_ on: Bool) -> [UInt8] { [0x01, 0x01, 0x10, 0x00, on ? 0x03 : 0x00] }

    /// Full output report: report ID followed by the first 63 bytes of the encrypted frame.
    public static func outputReport(_ command: [UInt8]) -> [UInt8] {
        var plain = command
        plain += [UInt8](repeating: 0, count: max(0, frameLength - plain.count))
        return [reportID] + TEA.encrypt(Array(plain.prefix(frameLength))).prefix(frameLength - 1)
    }

    /// Decrypts an input payload (report ID already stripped).
    public static func plaintext(_ payload: Data) -> [UInt8] {
        let usable = min(payload.count, 56) / 8 * 8
        return TEA.decrypt(Array(payload.prefix(usable)))
    }
}

/// A decoded message from the device.
public enum DeviceMessage: Equatable, Sendable {
    /// A control changed state. `index`: 0 top/mic, 1 middle/confirm, 2 bottom/cancel,
    /// 3 knob press, 4 knob clockwise, 5 knob counter-clockwise (turns only report `down`).
    case key(index: Int, down: Bool, logical: UInt8)
    case battery(millivolts: Int, percent: Int)
    case other([UInt8])

    public init(plaintext p: [UInt8]) {
        guard p.count >= 6, p[0] & 0x1F == 0x0B else { self = .other(Array(p.prefix(8))); return }
        switch p[1] {
        case 0x10: self = .key(index: Int(p[4]), down: p[3] == 1, logical: p[2])
        case 0x7B: self = .battery(millivolts: Int(p[2]) | Int(p[3]) << 8, percent: Int(p[5]))
        default: self = .other(Array(p.prefix(8)))
        }
    }

    public var summary: String {
        switch self {
        case let .key(index, down, logical):
            return String(format: "key index %d %@ (logical 0x%02x)", index, down ? "down" : "up", logical)
        case let .battery(mv, pct): return "battery \(pct)% (\(mv) mV)"
        case let .other(bytes): return "notice " + bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
        }
    }
}

/// Keeps the device in host mode while connected: the same messages Ulanzi Studio sends.
/// Nothing is persisted on the device; it returns to its own shortcuts when we stop.
public final class HostLink {
    private let watcher: HIDDeviceWatcher
    private var timer: Timer?
    private var ticks = 0
    public var onError: ((String) -> Void)?

    public init(watcher: HIDDeviceWatcher) { self.watcher = watcher }

    public var isActive: Bool { timer != nil }

    public func begin() {
        guard timer == nil else { return }
        send(AU05Protocol.hostOnline(false))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, self.timer != nil else { return }
            self.send(AU05Protocol.hostOnline(true))
            self.send(AU05Protocol.heartbeat)
        }
        let t = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.ticks += 1
            self.send(AU05Protocol.heartbeat)
            // Re-assert host mode now and then in case another program released it.
            if self.ticks % 6 == 0 { self.send(AU05Protocol.hostOnline(true)) }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Stops the heartbeat. `release` also tells the device to go back to its own shortcuts.
    public func end(release: Bool) {
        timer?.invalidate()
        timer = nil
        if release { send(AU05Protocol.hostOnline(false)) }
    }

    private func send(_ command: [UInt8]) {
        let r = watcher.sendOutputReport(AU05Protocol.outputReport(command))
        if r != kIOReturnSuccess && watcher.isConnected {
            onError?(String(format: "Could not send to the AU05 (0x%08x)", r))
        }
    }
}

enum TEA {
    private static let key: [UInt32] = {
        let b: [UInt8] = [0xca, 0xba, 0xa5, 0xca, 0x6d, 0x8a, 0x2a, 0xbc, 0xba, 0x9e, 0x5a, 0xca, 0xca, 0x8b, 0xb8, 0x9b]
        return (0..<4).map { word(b, $0 * 4) }
    }()
    private static let delta: UInt32 = 0x9E37_79B9

    static func encrypt(_ data: [UInt8]) -> [UInt8] { blocks(data, encryptBlock) }
    static func decrypt(_ data: [UInt8]) -> [UInt8] { blocks(data, decryptBlock) }

    private static func blocks(_ data: [UInt8], _ f: (UInt32, UInt32) -> (UInt32, UInt32)) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(data.count)
        var i = 0
        while i + 8 <= data.count {
            let (a, b) = f(word(data, i), word(data, i + 4))
            out += bytes(a) + bytes(b)
            i += 8
        }
        return out
    }

    private static func encryptBlock(_ v0In: UInt32, _ v1In: UInt32) -> (UInt32, UInt32) {
        var v0 = v0In, v1 = v1In, sum: UInt32 = 0
        for _ in 0..<32 {
            sum &+= delta
            v0 &+= ((v1 << 4) &+ key[0]) ^ (v1 &+ sum) ^ ((v1 >> 5) &+ key[1])
            v1 &+= ((v0 << 4) &+ key[2]) ^ (v0 &+ sum) ^ ((v0 >> 5) &+ key[3])
        }
        return (v0, v1)
    }

    private static func decryptBlock(_ v0In: UInt32, _ v1In: UInt32) -> (UInt32, UInt32) {
        var v0 = v0In, v1 = v1In, sum: UInt32 = delta &* 32
        for _ in 0..<32 {
            v1 &-= ((v0 << 4) &+ key[2]) ^ (v0 &+ sum) ^ ((v0 >> 5) &+ key[3])
            v0 &-= ((v1 << 4) &+ key[0]) ^ (v1 &+ sum) ^ ((v1 >> 5) &+ key[1])
            sum &-= delta
        }
        return (v0, v1)
    }

    private static func word(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }

    private static func bytes(_ w: UInt32) -> [UInt8] {
        [UInt8(w & 0xFF), UInt8(w >> 8 & 0xFF), UInt8(w >> 16 & 0xFF), UInt8(w >> 24 & 0xFF)]
    }
}
