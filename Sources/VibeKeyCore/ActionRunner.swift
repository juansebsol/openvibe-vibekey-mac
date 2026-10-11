import AppKit

public enum Phase: Sendable { case fire, down, up }

public final class ActionRunner {
    public let voice: VoiceRecorder
    public var switchProfile: ((String) -> Void)?
    public var log: ((String) -> Void)?

    public init(voice: VoiceRecorder) { self.voice = voice }

    public func perform(_ action: Action, phase: Phase) {
        switch action.type {
        case .hotkey:
            guard let hk = Hotkey(string: action.keys ?? "") else { log?("Invalid hotkey '\(action.keys ?? "")'"); return }
            switch phase {
            case .fire: KeySender.tap(hk)
            case .down: KeySender.post(hk, down: true)
            case .up: KeySender.post(hk, down: false)
            }
        case .voice:
            switch phase {
            case .down: voice.start()
            case .up: voice.stop()
            case .fire: voice.toggle()
            }
        default:
            guard phase != .up else { return }
            fire(action)
        }
    }

    private func fire(_ a: Action) {
        switch a.type {
        case .text:
            if let t = a.text, !t.isEmpty { KeySender.type(t) }
        case .open:
            guard let app = a.app, !app.isEmpty else { return }
            Shell.run("/usr/bin/open", ["-a", app])
        case .website:
            guard var s = a.url?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return }
            if !s.contains("://") { s = "https://" + s }
            if let u = URL(string: s) { NSWorkspace.shared.open(u) }
        case .shell:
            if let c = a.command, !c.isEmpty { Shell.run("/bin/zsh", ["-lc", c]) }
        case .media:
            if let m = a.media { KeySender.media(m) }
        case .scroll:
            KeySender.scroll(lines: a.amount ?? 3)
        case .multi:
            var t = 0.0
            for sub in a.actions ?? [] {
                DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in self?.perform(sub, phase: .fire) }
                t += a.delay ?? 0.1
            }
        case .random:
            if let sub = a.actions?.randomElement() { perform(sub, phase: .fire) }
        case .switchProfile:
            if let p = a.profile, !p.isEmpty { switchProfile?(p) }
        case .hotkey, .voice:
            perform(a, phase: .fire)
        }
    }
}

public enum Shell {
    /// Fire-and-forget process launch.
    public static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    /// Runs a zsh command and returns (status, stdout). Blocking; call off the main thread.
    public static func capture(_ command: String) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", command]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    public static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
