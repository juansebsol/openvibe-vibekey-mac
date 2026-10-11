import AppKit
import Foundation
import VibeKeyCore

setvbuf(stdout, nil, _IOLBF, 0)

let usage = """
vibekey-cli — Ulanzi AU05 Vibe Key tool (local only, no network)

USAGE: vibekey-cli <command>

  test        Guided check: asks for each control one at a time and confirms it arrives
  monitor     Live view of everything the device sends (decoded), with a log file
  calibrate   Remap controls (only needed if a firmware update reorders them)
  listen      Print decoded events and gestures (tap / long press / hold)
  run         Headless mode: perform the configured actions
  raw         Print every vendor report, encrypted and decrypted
  selftest    Check the protocol codec against known vectors (no device needed)
  paths       Show config / layout file locations

While running, the device is kept in host mode (the same heartbeat Ulanzi Studio sends);
on exit it is handed back to its own shortcuts.
"""

let command = CommandLine.arguments.dropFirst().first ?? "help"
var keepAlive: [AnyObject] = []

/// The menu bar app also drives host mode; don't knock it out when a CLI session ends.
var vibeKeyAppRunning: Bool {
    NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "local.openvibe.vibekey-mac" }
}

/// Runs `cleanup` on Ctrl-C / termination, then exits.
func onExit(_ cleanup: @escaping () -> Void) {
    for sig in [SIGINT, SIGTERM] {
        signal(sig, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        src.setEventHandler { cleanup(); exit(0) }
        src.resume()
        keepAlive.append(src as AnyObject)
    }
}

func releaseOnExit(_ engine: VibeEngine) {
    onExit { if !vibeKeyAppRunning { engine.shutdown() } }
}

switch command {
case "test":
    let test = GuidedTest()
    test.run()
    keepAlive.append(test)

case "monitor":
    let monitor = Monitor()
    monitor.run()
    keepAlive.append(monitor)

case "raw":
    let w = HIDDeviceWatcher(usagePage: AU05.vendorUsagePage)
    let link = HostLink(watcher: w)
    w.onConnectionChange = { connected in
        print(connected ? "● AU05 connected — host mode on" : "○ AU05 disconnected")
        if connected { link.begin() } else { link.end(release: false) }
    }
    w.onReport = { id, data in
        let plain = AU05Protocol.plaintext(data)
        print(String(format: "id=0x%02x  %@  →  %@   %@", id, Fingerprint.hex(data.prefix(8)),
                     Fingerprint.hex(Data(plain.prefix(8))), DeviceMessage(plaintext: plain).summary))
    }
    w.start()
    onExit { if !vibeKeyAppRunning { link.end(release: true) } }
    keepAlive.append(w)
    keepAlive.append(link)

case "calibrate":
    let engine = VibeEngine()
    engine.onConnectionChange = { print($0 ? "● AU05 connected" : "○ AU05 disconnected") }
    let cal = Calibrator()
    cal.onPrompt = { i, n, text in print("\n[\(i)/\(n)] \(text)…") }
    cal.onCapture = { ev, code in print("   ✓ \(ev.rawValue) = \(code)") }
    cal.onNote = { print("   ! \($0)") }
    cal.onFinish = { _ in
        print("\nSaved layout to \(Paths.layoutFile.path)")
        if !vibeKeyAppRunning { engine.shutdown() }
        exit(0)
    }
    print("Calibration — follow the prompts on the device. Ctrl-C to abort.")
    engine.start()
    engine.startCalibration(cal)
    releaseOnExit(engine)
    keepAlive.append(engine)
    keepAlive.append(cal)

case "listen", "run":
    let engine = VibeEngine()
    engine.onConnectionChange = { print($0 ? "● AU05 connected — host mode on" : "○ AU05 disconnected — waiting…") }
    engine.onLog = { print("· \($0)") }
    engine.onBattery = { print("· battery \($0)%") }
    engine.onRawEvent = { print("event  \($0.rawValue)") }
    let onGesture = engine.gestures.onGesture
    engine.gestures.onGesture = { c, g in
        print("gesture \(c.rawValue).\(g.rawValue)")
        if command == "run" { onGesture?(c, g) }
    }
    if command == "run" && !Accessibility.trusted {
        print("Accessibility permission is needed to send keystrokes. Prompting…")
        Accessibility.requestIfNeeded()
    }
    engine.start()
    releaseOnExit(engine)
    keepAlive.append(engine)

case "selftest":
    exit(SelfTest.run() ? 0 : 1)

case "paths":
    print("config: \(Paths.configFile.path)")
    print("layout: \(Paths.layoutFile.path)")
    exit(0)

default:
    print(usage)
    exit(command == "help" || command == "--help" || command == "-h" ? 0 : 1)
}

RunLoop.main.run()
