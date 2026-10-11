import Foundation
import VibeKeyCore

/// Known-answer tests for the AU05 codec. Vectors come from frames captured on a real unit
/// (and one published vector from arumwu/vibekey-lite).
enum SelfTest {
    static func run() -> Bool {
        var ok = true
        func check(_ name: String, _ got: String, _ want: String) {
            let pass = got == want
            ok = ok && pass
            print("\(pass ? "✓" : "✗") \(name)" + (pass ? "" : "\n    got  \(got)\n    want \(want)"))
        }
        func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }
        func data(_ h: String) -> Data {
            var bytes: [UInt8] = []
            var i = h.startIndex
            while i < h.endIndex { let j = h.index(i, offsetBy: 2); bytes.append(UInt8(h[i..<j], radix: 16)!); i = j }
            // Pad to a full 63-byte payload like the device sends.
            return Data(bytes + [UInt8](repeating: 0, count: 63 - bytes.count))
        }

        let heartbeat = AU05Protocol.outputReport(AU05Protocol.heartbeat)
        check("output report is 64 bytes with report ID 0x55", "\(heartbeat.count) \(heartbeat[0])", "64 85")
        check("filler = encrypted zero block", hex(Array(heartbeat[57..<64])), "3890c499a360aa")
        check("heartbeat ciphertext", hex(Array(heartbeat[1...8])), "24569ef228e145a1")
        check("published vector 01 06 50 01", hex(Array(AU05Protocol.outputReport([0x01, 0x06, 0x50, 0x01])[1...8])), "57df12e602d79dfd")

        let cases: [(String, String, DeviceMessage)] = [
            ("mic down", "3c81720972017506", .key(index: 0, down: true, logical: 0x6f)),
            ("mic up", "9dd350c99eb55a4a", .key(index: 0, down: false, logical: 0x6f)),
            ("knob press up", "5903322353144317", .key(index: 3, down: false, logical: 0x6e)),
            ("knob right", "2f12546e779bb7de", .key(index: 4, down: true, logical: 0x72)),
            ("battery notice", "d1b72e4daeab4c66", .battery(millivolts: 4023, percent: 90)),
        ]
        for (name, cipher, want) in cases {
            let got = DeviceMessage(plaintext: AU05Protocol.plaintext(data(cipher)))
            check("decode \(name)", got.summary, want.summary)
        }
        let layout = ControlLayout.standard
        check("standard layout maps index 4 to knobRight", layout.event(index: 4, down: true)?.rawValue ?? "nil", "knobRight")
        check("knob turns have no release event", layout.event(index: 5, down: false)?.rawValue ?? "nil", "nil")
        print(ok ? "\nAll checks passed." : "\nSome checks FAILED.")
        return ok
    }
}
