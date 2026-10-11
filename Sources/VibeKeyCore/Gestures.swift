import Foundation

public enum Gesture: String, Sendable {
    case tap, longPress, holdStart, holdEnd, turnLeft, turnRight
}

/// Turns press/release events into tap / long-press / hold gestures based on what's bound.
/// - `hold` bound: holdStart on press, holdEnd on release.
/// - `longPress` bound: waits; long-press after `longPressSeconds`, otherwise tap on release.
/// - otherwise: tap fires immediately on press (lowest latency).
public final class GestureEngine {
    public var longPressSeconds: Double = 0.5
    public var binding: (Control) -> ControlConfig? = { _ in nil }
    public var onGesture: ((Control, Gesture) -> Void)?

    private var holding: Set<Control> = []
    private var timers: [Control: DispatchWorkItem] = [:]
    private var longFired: Set<Control> = []

    public init() {}

    public func handle(_ event: RawEvent) {
        switch event {
        case .knobLeft: onGesture?(.knob, .turnLeft)
        case .knobRight: onGesture?(.knob, .turnRight)
        default:
            if event.isPress { press(event.control) } else { release(event.control) }
        }
    }

    public func reset() {
        timers.values.forEach { $0.cancel() }
        timers.removeAll(); holding.removeAll(); longFired.removeAll()
    }

    private func press(_ c: Control) {
        let cfg = binding(c)
        if cfg?.hold != nil {
            holding.insert(c)
            onGesture?(c, .holdStart)
        } else if cfg?.longPress != nil {
            timers[c]?.cancel()
            longFired.remove(c)
            let work = DispatchWorkItem { [weak self] in
                self?.longFired.insert(c)
                self?.onGesture?(c, .longPress)
            }
            timers[c] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + longPressSeconds, execute: work)
        } else {
            onGesture?(c, .tap)
        }
    }

    private func release(_ c: Control) {
        if holding.remove(c) != nil {
            onGesture?(c, .holdEnd)
        } else if let work = timers.removeValue(forKey: c) {
            work.cancel()
            if longFired.remove(c) == nil { onGesture?(c, .tap) }
        }
    }
}
