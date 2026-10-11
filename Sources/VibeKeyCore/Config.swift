import Foundation

public enum ActionType: String, Codable, CaseIterable, Sendable {
    case hotkey, text, open, website, shell, media, scroll, multi, random, switchProfile, voice

    public var label: String {
        switch self {
        case .hotkey: return "Hotkey"
        case .text: return "Text"
        case .open: return "Open"
        case .website: return "Website"
        case .shell: return "Shell Command"
        case .media: return "Multimedia"
        case .scroll: return "Scroll"
        case .multi: return "Multi Action"
        case .random: return "Random Action"
        case .switchProfile: return "Switch Profile"
        case .voice: return "Voice Record"
        }
    }
    public var section: String {
        switch self {
        case .multi, .random: return "Multi Action"
        case .switchProfile: return "Profiles"
        case .voice: return "Voice"
        default: return "System"
        }
    }
    public var symbol: String {
        switch self {
        case .hotkey: return "command"
        case .text: return "character.cursor.ibeam"
        case .open: return "arrow.up.forward.app"
        case .website: return "globe"
        case .shell: return "terminal"
        case .media: return "playpause"
        case .scroll: return "arrow.up.arrow.down"
        case .multi: return "square.stack.3d.up"
        case .random: return "shuffle"
        case .switchProfile: return "person.crop.rectangle.stack"
        case .voice: return "waveform"
        }
    }
}

public enum MediaKey: String, Codable, CaseIterable, Sendable {
    case volumeUp, volumeDown, mute, playPause, next, previous, brightnessUp, brightnessDown
    public var label: String {
        switch self {
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .mute: return "Mute"
        case .playPause: return "Play / Pause"
        case .next: return "Next Track"
        case .previous: return "Previous Track"
        case .brightnessUp: return "Brightness Up"
        case .brightnessDown: return "Brightness Down"
        }
    }
}

/// One action. Only the fields relevant to `type` are used/written.
public struct Action: Codable, Hashable, Sendable {
    public var type: ActionType
    public var keys: String?        // hotkey, e.g. "ctrl+shift+d"
    public var text: String?        // text to type
    public var app: String?         // app name, bundle path
    public var url: String?         // website
    public var command: String?     // shell
    public var media: MediaKey?
    public var amount: Int?         // scroll lines (+ up, - down)
    public var actions: [Action]?   // multi / random
    public var delay: Double?       // multi: seconds between steps
    public var profile: String?     // switchProfile

    public init(type: ActionType, keys: String? = nil, text: String? = nil, app: String? = nil,
                url: String? = nil, command: String? = nil, media: MediaKey? = nil, amount: Int? = nil,
                actions: [Action]? = nil, delay: Double? = nil, profile: String? = nil) {
        self.type = type; self.keys = keys; self.text = text; self.app = app; self.url = url
        self.command = command; self.media = media; self.amount = amount; self.actions = actions
        self.delay = delay; self.profile = profile
    }

    public static func blank(_ type: ActionType) -> Action {
        switch type {
        case .hotkey: return Action(type: .hotkey, keys: "")
        case .text: return Action(type: .text, text: "")
        case .open: return Action(type: .open, app: "")
        case .website: return Action(type: .website, url: "https://")
        case .shell: return Action(type: .shell, command: "")
        case .media: return Action(type: .media, media: .playPause)
        case .scroll: return Action(type: .scroll, amount: 3)
        case .multi: return Action(type: .multi, actions: [], delay: 0.1)
        case .random: return Action(type: .random, actions: [])
        case .switchProfile: return Action(type: .switchProfile, profile: "")
        case .voice: return Action(type: .voice)
        }
    }

    public var summary: String {
        switch type {
        case .hotkey: return Hotkey(string: keys ?? "")?.display ?? "Hotkey"
        case .text: return "Type “\((text ?? "").prefix(20))”"
        case .open: return "Open \(app ?? "")"
        case .website: return url ?? ""
        case .shell: return command ?? ""
        case .media: return media?.label ?? "Media"
        case .scroll: return "Scroll \(amount ?? 0)"
        case .multi: return "\(actions?.count ?? 0) actions"
        case .random: return "Random of \(actions?.count ?? 0)"
        case .switchProfile: return "→ \(profile ?? "")"
        case .voice: return "Record voice"
        }
    }
}

/// Gesture slots a control can be bound to.
public enum Slot: String, Codable, CaseIterable, Identifiable, Sendable {
    case tap, longPress, hold, left, right
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .tap: return "Press"
        case .longPress: return "Long Press"
        case .hold: return "Hold (press→release)"
        case .left: return "Turn Left"
        case .right: return "Turn Right"
        }
    }
    public static func slots(for control: Control) -> [Slot] {
        control.isKnob ? [.left, .right, .tap, .longPress, .hold] : [.tap, .longPress, .hold]
    }
}

public struct ControlConfig: Codable, Hashable, Sendable {
    public var title: String
    public var tap: Action?
    public var longPress: Action?
    /// Hold-to-talk: hotkeys are held down while pressed; voice records while pressed.
    public var hold: Action?
    public var left: Action?
    public var right: Action?

    public init(title: String = "", tap: Action? = nil, longPress: Action? = nil, hold: Action? = nil,
                left: Action? = nil, right: Action? = nil) {
        self.title = title; self.tap = tap; self.longPress = longPress; self.hold = hold
        self.left = left; self.right = right
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        tap = try c.decodeIfPresent(Action.self, forKey: .tap)
        longPress = try c.decodeIfPresent(Action.self, forKey: .longPress)
        hold = try c.decodeIfPresent(Action.self, forKey: .hold)
        left = try c.decodeIfPresent(Action.self, forKey: .left)
        right = try c.decodeIfPresent(Action.self, forKey: .right)
    }

    public subscript(slot: Slot) -> Action? {
        get {
            switch slot {
            case .tap: return tap
            case .longPress: return longPress
            case .hold: return hold
            case .left: return left
            case .right: return right
            }
        }
        set {
            switch slot {
            case .tap: tap = newValue
            case .longPress: longPress = newValue
            case .hold: hold = newValue
            case .left: left = newValue
            case .right: right = newValue
            }
        }
    }

    public var isEmpty: Bool { tap == nil && longPress == nil && hold == nil && left == nil && right == nil }
}

public struct Profile: Codable, Hashable, Identifiable, Sendable {
    public var name: String
    public var controls: [String: ControlConfig]
    public var id: String { name }

    public init(name: String, controls: [String: ControlConfig] = [:]) {
        self.name = name; self.controls = controls
    }

    public subscript(control: Control) -> ControlConfig {
        get { controls[control.rawValue] ?? ControlConfig() }
        set { controls[control.rawValue] = newValue }
    }
}

public struct VoiceSettings: Codable, Hashable, Sendable {
    /// Substring matched against audio input device names. System default input is never changed.
    public var deviceName: String = "AU05"
    /// Where recordings are saved. Empty = Application Support/vibekey-mac/recordings.
    public var saveDirectory: String = ""
    /// Optional command run after each recording; `{file}` is replaced with the quoted WAV path.
    public var command: String = ""
    /// Type the command's stdout into the frontmost app (e.g. a whisper transcript).
    public var typeResult: Bool = false
    /// Delete the WAV after the command succeeds.
    public var deleteAfterCommand: Bool = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VoiceSettings()
        deviceName = try c.decodeIfPresent(String.self, forKey: .deviceName) ?? d.deviceName
        saveDirectory = try c.decodeIfPresent(String.self, forKey: .saveDirectory) ?? d.saveDirectory
        command = try c.decodeIfPresent(String.self, forKey: .command) ?? d.command
        typeResult = try c.decodeIfPresent(Bool.self, forKey: .typeResult) ?? d.typeResult
        deleteAfterCommand = try c.decodeIfPresent(Bool.self, forKey: .deleteAfterCommand) ?? d.deleteAfterCommand
    }
}

public struct AppConfig: Codable, Hashable, Sendable {
    public var version: Int = 1
    public var activeProfile: String = "Default"
    public var longPressSeconds: Double = 0.5
    /// Show the editor window when the app launches (it always opens on re-launch / reopen).
    public var openEditorAtLaunch: Bool = true
    public var voice = VoiceSettings()
    public var profiles: [Profile] = [AppConfig.defaultProfile]

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig()
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? d.version
        activeProfile = try c.decodeIfPresent(String.self, forKey: .activeProfile) ?? d.activeProfile
        longPressSeconds = try c.decodeIfPresent(Double.self, forKey: .longPressSeconds) ?? d.longPressSeconds
        openEditorAtLaunch = try c.decodeIfPresent(Bool.self, forKey: .openEditorAtLaunch) ?? d.openEditorAtLaunch
        voice = try c.decodeIfPresent(VoiceSettings.self, forKey: .voice) ?? d.voice
        profiles = try c.decodeIfPresent([Profile].self, forKey: .profiles) ?? d.profiles
        if profiles.isEmpty { profiles = d.profiles }
    }

    public var activeIndex: Int {
        profiles.firstIndex { $0.name == activeProfile } ?? 0
    }
    public var current: Profile { profiles[activeIndex] }

    public static let defaultProfile = Profile(name: "Default", controls: [
        Control.knob.rawValue: ControlConfig(title: "Navigation",
                                             tap: Action(type: .media, media: .mute),
                                             left: Action(type: .media, media: .volumeDown),
                                             right: Action(type: .media, media: .volumeUp)),
        Control.mic.rawValue: ControlConfig(title: "Voice Input", tap: Action(type: .hotkey, keys: "ctrl+d")),
        Control.check.rawValue: ControlConfig(title: "Confirm", tap: Action(type: .hotkey, keys: "return")),
        Control.x.rawValue: ControlConfig(title: "Cancel", tap: Action(type: .hotkey, keys: "escape")),
    ])
}

/// Loads/saves config.json and hot-reloads it when edited externally.
public final class ConfigStore {
    public private(set) var config: AppConfig
    public var onExternalChange: ((AppConfig) -> Void)?
    public var onError: ((String) -> Void)?
    public let url: URL

    private var lastData: Data?
    private var source: DispatchSourceFileSystemObject?
    private var dirFD: Int32 = -1

    public init(url: URL = Paths.configFile) {
        self.url = url
        if let data = try? Data(contentsOf: url) {
            if let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) {
                config = cfg
                lastData = data
            } else {
                // Keep the broken file around instead of silently overwriting it.
                let backup = url.deletingPathExtension().appendingPathExtension("broken.json")
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.copyItem(at: url, to: backup)
                config = AppConfig()
                save(config)
            }
        } else {
            config = AppConfig()
            save(config)
        }
    }

    public func save(_ cfg: AppConfig) {
        config = cfg
        guard let data = try? JSON.encoder.encode(cfg), data != lastData else { return }
        lastData = data
        do { try data.write(to: url, options: .atomic) } catch { onError?("Save failed: \(error)") }
    }

    public func reloadFromDisk() {
        guard let data = try? Data(contentsOf: url), data != lastData else { return }
        do {
            let cfg = try JSONDecoder().decode(AppConfig.self, from: data)
            lastData = data
            config = cfg
            onExternalChange?(cfg)
        } catch {
            onError?("config.json has an error and was not loaded: \(error)")
        }
    }

    /// Watch the containing directory (editors usually replace files atomically).
    public func startWatching() {
        guard source == nil else { return }
        dirFD = open(url.deletingLastPathComponent().path, O_EVTONLY)
        guard dirFD >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: dirFD, eventMask: [.write, .rename, .extend], queue: .main)
        src.setEventHandler { [weak self] in
            // Small debounce so we read the finished file.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.reloadFromDisk() }
        }
        let fd = dirFD
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }
}
