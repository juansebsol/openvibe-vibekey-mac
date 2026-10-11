import AppKit
import ApplicationServices
import CoreGraphics

/// Parsed key combo such as "ctrl+shift+d".
public struct Hotkey: Equatable, Sendable {
    public var keyCode: CGKeyCode
    public var keyName: String
    public var modifiers: [String]  // canonical order: ctrl, alt, shift, cmd, fn

    public static let modifierOrder = ["ctrl", "alt", "shift", "cmd", "fn"]
    static let modifierAliases: [String: String] = [
        "ctrl": "ctrl", "control": "ctrl", "⌃": "ctrl",
        "alt": "alt", "opt": "alt", "option": "alt", "⌥": "alt",
        "shift": "shift", "⇧": "shift",
        "cmd": "cmd", "command": "cmd", "meta": "cmd", "super": "cmd", "⌘": "cmd",
        "fn": "fn",
    ]

    public init?(string: String) {
        let parts = string.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.last, !last.isEmpty else { return nil }
        var mods: [String] = []
        for p in parts.dropLast() {
            guard let m = Self.modifierAliases[p] else { return nil }
            if !mods.contains(m) { mods.append(m) }
        }
        let keyAlias = KeyTable.aliases[last] ?? last
        guard let code = KeyTable.codes[keyAlias] else { return nil }
        keyCode = code
        keyName = keyAlias
        modifiers = Self.modifierOrder.filter { mods.contains($0) }
    }

    public init(keyCode: CGKeyCode, flags: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        keyName = KeyTable.name(for: keyCode) ?? "key\(keyCode)"
        var mods: [String] = []
        if flags.contains(.control) { mods.append("ctrl") }
        if flags.contains(.option) { mods.append("alt") }
        if flags.contains(.shift) { mods.append("shift") }
        if flags.contains(.command) { mods.append("cmd") }
        if flags.contains(.function) && !KeyTable.implicitFn.contains(keyCode) { mods.append("fn") }
        modifiers = mods
    }

    public var string: String { (modifiers + [keyName]).joined(separator: "+") }

    public var display: String {
        let sym: [String: String] = ["ctrl": "⌃", "alt": "⌥", "shift": "⇧", "cmd": "⌘", "fn": "fn "]
        let key = KeyTable.displayNames[keyName] ?? keyName.uppercased()
        return modifiers.map { sym[$0] ?? $0 }.joined() + key
    }

    public var cgFlags: CGEventFlags {
        var f: CGEventFlags = []
        if modifiers.contains("ctrl") { f.insert(.maskControl) }
        if modifiers.contains("alt") { f.insert(.maskAlternate) }
        if modifiers.contains("shift") { f.insert(.maskShift) }
        if modifiers.contains("cmd") { f.insert(.maskCommand) }
        if modifiers.contains("fn") { f.insert(.maskSecondaryFn) }
        return f
    }
}

/// US-ANSI virtual key codes.
public enum KeyTable {
    public static let codes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
        "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31,
        "u": 32, "[": 33, "i": 34, "p": 35, "return": 36, "l": 37, "j": 38, "'": 39, "k": 40,
        ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49,
        "`": 50, "delete": 51, "escape": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111, "f13": 105, "f14": 107, "f15": 113,
        "f16": 106, "f17": 64, "f18": 79, "f19": 80, "f20": 90,
        "home": 115, "pageup": 116, "forwarddelete": 117, "end": 119, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]
    public static let aliases: [String: String] = [
        "enter": "return", "esc": "escape", "backspace": "delete", "del": "forwarddelete",
        "plus": "=", "minus": "-", "pgup": "pageup", "pgdn": "pagedown",
    ]
    public static let displayNames: [String: String] = [
        "return": "↩", "escape": "Esc", "delete": "⌫", "forwarddelete": "⌦", "tab": "⇥",
        "space": "Space", "left": "←", "right": "→", "up": "↑", "down": "↓",
        "pageup": "PgUp", "pagedown": "PgDn", "home": "Home", "end": "End",
    ]
    /// Keys for which macOS sets the fn flag implicitly.
    static let implicitFn: Set<CGKeyCode> = [115, 116, 117, 119, 121, 123, 124, 125, 126,
                                              122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
    public static func name(for code: CGKeyCode) -> String? {
        codes.first { $0.value == code }?.key
    }
}

public enum Accessibility {
    public static var trusted: Bool { AXIsProcessTrusted() }
    @discardableResult
    public static func requestIfNeeded() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
    public static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

/// Synthesizes keyboard, media and scroll events via CGEvent. Needs Accessibility.
public enum KeySender {
    private static let source = CGEventSource(stateID: .hidSystemState)

    public static func post(_ hk: Hotkey, down: Bool) {
        guard let e = CGEvent(keyboardEventSource: source, virtualKey: hk.keyCode, keyDown: down) else { return }
        e.flags = hk.cgFlags
        e.post(tap: .cghidEventTap)
    }

    public static func tap(_ hk: Hotkey) {
        post(hk, down: true)
        post(hk, down: false)
    }

    public static func type(_ text: String) {
        let units = Array(text.utf16)
        var i = 0
        while i < units.count {
            var chunk = Array(units[i..<min(i + 20, units.count)])
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                e.flags = []
                e.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                e.post(tap: .cghidEventTap)
            }
            i += 20
            usleep(2000)
        }
    }

    public static func scroll(lines: Int) {
        CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 1,
                wheel1: Int32(lines), wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
    }

    public static func media(_ key: MediaKey) {
        let code: Int
        switch key {
        case .volumeUp: code = 0       // NX_KEYTYPE_SOUND_UP
        case .volumeDown: code = 1     // NX_KEYTYPE_SOUND_DOWN
        case .brightnessUp: code = 2
        case .brightnessDown: code = 3
        case .mute: code = 7
        case .playPause: code = 16
        case .next: code = 17
        case .previous: code = 18
        }
        for down in [true, false] {
            let flag = down ? 0xa : 0xb
            let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                        modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flag << 8)),
                                        timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                        data1: (code << 16) | (flag << 8), data2: -1)
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
