import Foundation
import VibeKeyCore

/// An entry in the right-hand action list.
struct PaletteItem: Identifiable {
    let id: String
    let label: String
    let symbol: String
    let section: String
    let make: () -> Action
    /// For knob-turn presets: the actions for each direction.
    var knobTurn: (left: Action, right: Action)? = nil
    var type: ActionType? = nil

    static let buttonItems: [PaletteItem] = {
        let order: [ActionType] = [.open, .website, .text, .hotkey, .media, .shell, .multi, .random, .switchProfile, .voice]
        return order.map { t in
            PaletteItem(id: t.rawValue, label: t.label, symbol: t.symbol, section: t.section, make: { .blank(t) }, type: t)
        }
    }()

    static let knobItems: [PaletteItem] = [
        turn("volume", "Volume", "speaker.wave.2", .init(type: .media, media: .volumeDown), .init(type: .media, media: .volumeUp)),
        turn("scroll", "Scroll", "arrow.up.arrow.down", .init(type: .scroll, amount: 3), .init(type: .scroll, amount: -3)),
        turn("tracks", "Previous / Next Track", "forward", .init(type: .media, media: .previous), .init(type: .media, media: .next)),
        turn("brightness", "Brightness", "sun.max", .init(type: .media, media: .brightnessDown), .init(type: .media, media: .brightnessUp)),
        turn("arrows", "Arrow Keys", "arrow.left.arrow.right", .init(type: .hotkey, keys: "left"), .init(type: .hotkey, keys: "right")),
    ]

    private static func turn(_ id: String, _ label: String, _ symbol: String, _ l: Action, _ r: Action) -> PaletteItem {
        PaletteItem(id: "turn.\(id)", label: label, symbol: symbol, section: "Knob Turn", make: { l }, knobTurn: (l, r))
    }

    static func find(_ id: String) -> PaletteItem? {
        (buttonItems + knobItems).first { $0.id == id }
    }

    static let sectionSymbols: [String: String] = [
        "Knob Turn": "dial.medium",
        "System": "desktopcomputer",
        "Multi Action": "square.stack.3d.up",
        "Profiles": "person.crop.rectangle.stack",
        "Voice": "waveform",
    ]
}

extension Control {
    var symbol: String {
        switch self {
        case .knob: return "dial.medium"
        case .mic: return "mic"
        case .check: return "checkmark.circle"
        case .x: return "xmark.circle"
        }
    }
}

extension Slot {
    var shortLabel: String {
        switch self {
        case .tap: return "Press"
        case .longPress: return "Long Press"
        case .hold: return "Hold"
        case .left: return "Turn Left"
        case .right: return "Turn Right"
        }
    }
}

extension MediaKey {
    var symbol: String {
        switch self {
        case .volumeUp: return "speaker.wave.3"
        case .volumeDown: return "speaker.wave.1"
        case .mute: return "speaker.slash"
        case .playPause: return "playpause"
        case .next: return "forward"
        case .previous: return "backward"
        case .brightnessUp: return "sun.max"
        case .brightnessDown: return "sun.min"
        }
    }
}

/// Short human summaries shown on the device pills.
enum Summary {
    static func short(_ a: Action) -> String {
        switch a.type {
        case .hotkey: return Hotkey(string: a.keys ?? "")?.display ?? "Shortcut"
        case .text: return "Type text"
        case .open:
            let app = a.app ?? ""
            return app.isEmpty ? "Open app" : URL(fileURLWithPath: app).deletingPathExtension().lastPathComponent
        case .website: return URL(string: a.url ?? "")?.host ?? "Website"
        case .shell: return "Shell"
        case .media: return a.media?.label ?? "Media"
        case .scroll: return (a.amount ?? 0) >= 0 ? "Scroll up" : "Scroll down"
        case .multi: return "\(a.actions?.count ?? 0) steps"
        case .random: return "Random"
        case .switchProfile: return "→ \(a.profile ?? "")"
        case .voice: return "Record"
        }
    }

    static func control(_ cfg: ControlConfig, _ c: Control) -> String? {
        if c.isKnob, let turn = knobTurn(cfg) { return turn }
        if let hold = cfg.hold { return "Hold · " + short(hold) }
        if let tap = cfg.tap { return short(tap) }
        if let long = cfg.longPress { return "Long · " + short(long) }
        return nil
    }

    private static func knobTurn(_ cfg: ControlConfig) -> String? {
        guard cfg.left != nil || cfg.right != nil else { return nil }
        if let preset = PaletteItem.knobItems.first(where: { $0.knobTurn?.left == cfg.left && $0.knobTurn?.right == cfg.right }) {
            return preset.id == "turn.tracks" ? "Tracks" : preset.label
        }
        return [cfg.left, cfg.right].map { $0.map(short) ?? "—" }.joined(separator: " / ")
    }

    static func icon(_ cfg: ControlConfig, _ c: Control) -> String {
        if c.isKnob, cfg.left != nil || cfg.right != nil,
           let preset = PaletteItem.knobItems.first(where: { $0.knobTurn?.left == cfg.left && $0.knobTurn?.right == cfg.right }) {
            return preset.symbol
        }
        return (cfg.hold ?? cfg.tap ?? cfg.longPress ?? cfg.right ?? cfg.left)?.type.symbol ?? "plus"
    }
}
