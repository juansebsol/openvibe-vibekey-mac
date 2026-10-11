import SwiftUI
import VibeKeyCore

/// Vector drawing of the AU05 in a fixed 150×540 coordinate space (scaled by the caller).
struct DeviceArt: View {
    var selected: Control? = nil
    var live: Set<Control> = []
    var knobAngle: Double = 0
    /// Calibration: pulse this control and optionally badge it with a hint symbol.
    var target: Control? = nil
    var targetSymbol: String? = nil
    var interactive = true
    var onSelect: (Control) -> Void = { _ in }
    var onDrop: (Control, [String]) -> Bool = { _, _ in false }

    static let width: CGFloat = 150
    static let height: CGFloat = 540
    static let knobDiameter: CGFloat = 116
    static let well: CGFloat = 80
    static let cap: CGFloat = 58

    static func centerY(_ c: Control) -> CGFloat {
        switch c {
        case .knob: return 170
        case .mic: return 302
        case .check: return 391
        case .x: return 480
        }
    }

    static func capSymbol(_ c: Control) -> String {
        switch c {
        case .mic: return "mic"
        case .check: return "checkmark.circle"
        case .x: return "xmark.circle"
        case .knob: return "dial.medium"
        }
    }

    @State private var hovered: Control?
    @State private var dropTarget: Control?

    var body: some View {
        ZStack {
            shell
            Text("VibeKey")
                .font(.system(size: 9.5, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(Color.black.opacity(0.32))
                .position(x: Self.width / 2, y: 26)
            grille
                .position(x: Self.width / 2, y: 62)
            knob
                .position(x: Self.width / 2, y: Self.centerY(.knob))
            ForEach([Control.mic, .check, .x]) { c in
                button(c).position(x: Self.width / 2, y: Self.centerY(c))
            }
        }
        .frame(width: Self.width, height: Self.height)
    }

    // MARK: Parts

    private var shell: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return shape
            .fill(LinearGradient(colors: [Color(red: 0.958, green: 0.955, blue: 0.948),
                                          Color(red: 0.890, green: 0.887, blue: 0.879),
                                          Color(red: 0.838, green: 0.835, blue: 0.828)],
                                 startPoint: .top, endPoint: .bottom))
            // Soft side shading so the body reads as rounded, not flat.
            .overlay(shape.fill(LinearGradient(colors: [.black.opacity(0.07), .clear, .clear, .black.opacity(0.09)],
                                               startPoint: .leading, endPoint: .trailing)))
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.15), .black.opacity(0.2)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 1.2))
            .shadow(color: .black.opacity(0.55), radius: 30, y: 20)
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }

    private var grille: some View {
        HStack(spacing: 5) {
            ForEach(0..<9, id: \.self) { _ in
                Capsule()
                    .fill(LinearGradient(colors: [Color(white: 0.09), Color(white: 0.25)], startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.3), lineWidth: 0.5))
                    .frame(width: 6, height: 30)
            }
        }
    }

    private var knob: some View {
        let d = Self.knobDiameter
        let isLive = live.contains(.knob)
        let isSelected = selected == .knob
        let isHovered = hovered == .knob || dropTarget == .knob
        return ZStack {
            // Recess the knob sits in.
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.74), Color(white: 0.94)], startPoint: .top, endPoint: .bottom))
                .frame(width: d + 14, height: d + 14)
            // LED ring: warm when idle, teal while the knob is used.
            Circle()
                .stroke(isLive ? Theme.teal : Color(red: 1.0, green: 0.80, blue: 0.52), lineWidth: isLive ? 7 : 4)
                .frame(width: d + 6, height: d + 6)
                .blur(radius: isLive ? 7 : 5)
                .opacity(isLive ? 1 : 0.5)
            // Face.
            Circle()
                .fill(RadialGradient(colors: [Color(white: 1.0), Color(white: 0.95), Color(white: 0.83)],
                                     center: UnitPoint(x: 0.36, y: 0.28), startRadius: 2, endRadius: d * 0.78))
                .frame(width: d, height: d)
                .shadow(color: .black.opacity(0.30), radius: 5, y: 4)
            // Anodized sheen.
            Circle()
                .fill(AngularGradient(colors: [.white.opacity(0), .white.opacity(0.5), .white.opacity(0), .black.opacity(0.05),
                                               .white.opacity(0), .white.opacity(0.4), .white.opacity(0), .black.opacity(0.05),
                                               .white.opacity(0)],
                                      center: .center))
                .frame(width: d - 4, height: d - 4)
            Knurl(count: 90)
                .stroke(Color.black.opacity(0.09), lineWidth: 1)
                .frame(width: d, height: d)
            Circle()
                .strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
                .frame(width: d, height: d)
            // Marker and ticks turn with the real knob.
            ZStack {
                Capsule().fill(Color(white: 0.5)).frame(width: 3, height: 10).offset(y: -d / 2 + 15)
                ForEach([90.0, 180, 270], id: \.self) { angle in
                    Capsule().fill(Color.black.opacity(0.13)).frame(width: 1.5, height: 6)
                        .offset(y: -d / 2 + 14)
                        .rotationEffect(.degrees(angle))
                }
            }
            .rotationEffect(.degrees(knobAngle))
            .animation(.spring(response: 0.35, dampingFraction: 0.65), value: knobAngle)
            // Selection ring.
            Circle()
                .strokeBorder(Theme.tealOnLight, lineWidth: 2.5)
                .frame(width: d + 24, height: d + 24)
                .opacity(isSelected || target == .knob ? 1 : isHovered ? 0.45 : 0)
            if target == .knob {
                PulseRing(diameter: d + 24)
                if let targetSymbol {
                    hintBadge(targetSymbol).offset(x: d / 2 + 4, y: -d / 2 + 4)
                }
            }
        }
        .frame(width: d + 30, height: d + 30)
        .contentShape(Circle())
        .animation(.easeOut(duration: 0.15), value: isLive)
        .modifier(ControlInteraction(control: .knob, enabled: interactive, hovered: $hovered,
                                     dropTarget: $dropTarget, onSelect: onSelect, onDrop: onDrop))
    }

    private func button(_ c: Control) -> some View {
        let isLive = live.contains(c)
        let isSelected = selected == c
        let isHovered = hovered == c || dropTarget == c
        let well = Self.well
        let cap = Self.cap
        return ZStack {
            // Square well.
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.81), Color(white: 0.91)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.black.opacity(0.14), .white.opacity(0.75)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .frame(width: well, height: well)
            // Cap.
            Circle()
                .fill(RadialGradient(colors: [Color(white: 1.0), Color(white: isLive ? 0.85 : 0.9)],
                                     center: UnitPoint(x: 0.4, y: 0.3), startRadius: 2, endRadius: cap * 0.75))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.07), lineWidth: 1))
                .shadow(color: .black.opacity(isLive ? 0.12 : 0.28), radius: isLive ? 1 : 3, y: isLive ? 0.5 : 2.5)
                .frame(width: cap, height: cap)
                .scaleEffect(isLive ? 0.94 : 1)
                .shadow(color: Theme.teal.opacity(isLive ? 0.9 : 0), radius: 10)
            Image(systemName: Self.capSymbol(c))
                .font(.system(size: c == .mic ? 18 : 20, weight: .light))
                .foregroundStyle(Color(white: isLive ? 0.2 : 0.32))
                .scaleEffect(isLive ? 0.94 : 1)
            Circle()
                .strokeBorder(Theme.tealOnLight, lineWidth: 2.5)
                .frame(width: cap + 14, height: cap + 14)
                .opacity(isSelected || target == c ? 1 : isHovered ? 0.45 : 0)
            if target == c { PulseRing(diameter: cap + 14) }
        }
        .frame(width: well, height: well)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: isLive)
        .modifier(ControlInteraction(control: c, enabled: interactive, hovered: $hovered,
                                     dropTarget: $dropTarget, onSelect: onSelect, onDrop: onDrop))
    }

    private func hintBadge(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Theme.onTeal)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Theme.teal))
            .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
    }
}

private struct ControlInteraction: ViewModifier {
    let control: Control
    let enabled: Bool
    @Binding var hovered: Control?
    @Binding var dropTarget: Control?
    let onSelect: (Control) -> Void
    let onDrop: (Control, [String]) -> Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .onTapGesture { onSelect(control) }
                .onHover { inside in
                    if inside { hovered = control } else if hovered == control { hovered = nil }
                }
                .dropDestination(for: String.self) { items, _ in
                    onDrop(control, items)
                } isTargeted: { targeted in
                    if targeted { dropTarget = control } else if dropTarget == control { dropTarget = nil }
                }
        } else {
            content
        }
    }
}

/// Fine radial grip lines around the knob's edge.
struct Knurl: Shape {
    var count = 72
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        for i in 0..<count {
            let a = Double(i) / Double(count) * 2 * .pi
            p.move(to: CGPoint(x: c.x + cos(a) * (r - 6), y: c.y + sin(a) * (r - 6)))
            p.addLine(to: CGPoint(x: c.x + cos(a) * (r - 1.5), y: c.y + sin(a) * (r - 1.5)))
        }
        return p
    }
}

struct PulseRing: View {
    let diameter: CGFloat
    @State private var animate = false

    var body: some View {
        Circle()
            .strokeBorder(Theme.teal, lineWidth: 3)
            .frame(width: diameter, height: diameter)
            .scaleEffect(animate ? 1.3 : 1)
            .opacity(animate ? 0 : 0.95)
            .onAppear {
                withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) { animate = true }
            }
    }
}

// MARK: - Canvas with label pills

struct DeviceCanvas: View {
    @EnvironmentObject var state: AppState
    private let pillsWidth: CGFloat = 256

    var body: some View {
        GeometryReader { geo in
            let groupWidth = DeviceArt.width + 2 + pillsWidth
            let scale = min(1, geo.size.height / (DeviceArt.height + 56), geo.size.width / (groupWidth + 60))
            ZStack {
                // Soft spotlight behind the device.
                RadialGradient(colors: [Color.white.opacity(0.045), .clear], center: .center, startRadius: 0, endRadius: 380)
                    .allowsHitTesting(false)
                DeviceArt(selected: state.selected, live: state.live, knobAngle: state.knobAngle,
                          onSelect: { state.select($0) },
                          onDrop: { c, items in drop(items, on: c) })
                    .overlay(alignment: .topLeading) {
                        pills.offset(x: DeviceArt.width + 2)
                    }
                    .scaleEffect(scale)
                    // Center the device and its pills together, not just the device.
                    .offset(x: -(groupWidth / 2 - DeviceArt.width / 2) * scale)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var pills: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Control.allCases) { c in
                PillRow(control: c) { drop($0, on: c) }
                    .offset(y: DeviceArt.centerY(c) - 17)
            }
        }
        .frame(width: pillsWidth, height: DeviceArt.height, alignment: .topLeading)
    }

    private func drop(_ items: [String], on c: Control) -> Bool {
        guard let id = items.first, let item = PaletteItem.find(id) else { return false }
        if item.knobTurn != nil && !c.isKnob { return false }
        state.assign(item, to: c)
        return true
    }
}

struct PillRow: View {
    @EnvironmentObject var state: AppState
    let control: Control
    let onDrop: ([String]) -> Bool
    @State private var hover = false
    @State private var targeted = false

    var body: some View {
        let cfg = state.profile[control]
        let selected = state.selected == control
        let isLive = state.live.contains(control)
        let accent = selected || isLive || targeted
        let summary = Summary.control(cfg, control)
        let title = cfg.title.isEmpty ? (cfg.isEmpty ? "Assign an action" : control.displayName) : cfg.title

        HStack(spacing: 0) {
            Rectangle()
                .fill(accent ? Theme.teal.opacity(0.7) : Color.white.opacity(0.16))
                .frame(width: 12, height: 1)
            Circle()
                .strokeBorder(accent ? Theme.teal : Color.white.opacity(0.45), lineWidth: 1.2)
                .background(Circle().fill(selected ? Theme.teal : .clear).padding(2.5))
                .frame(width: 10, height: 10)
            Spacer().frame(width: 8)
            HStack(spacing: 8) {
                Image(systemName: Summary.icon(cfg, control))
                    .font(.system(size: 11.5, weight: .medium))
                    .frame(width: 15)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let summary {
                    Text(summary)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(selected ? Theme.teal.opacity(0.75) : Theme.tertiary)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(selected ? Theme.teal : cfg.isEmpty ? Theme.tertiary : Theme.text)
            .padding(.horizontal, 13)
            .frame(width: 226, height: 34)
            .background(Capsule().fill(selected ? Theme.teal.opacity(0.10) : Color.white.opacity(hover ? 0.08 : 0.05)))
            .overlay(
                Capsule().strokeBorder(accent ? Theme.teal : Color.white.opacity(hover ? 0.32 : 0.17),
                                       style: StrokeStyle(lineWidth: 1.2, dash: cfg.isEmpty && !accent ? [4, 3] : []))
            )
            .shadow(color: isLive ? Theme.teal.opacity(0.6) : .clear, radius: 8)
        }
        .contentShape(Rectangle())
        .onTapGesture { state.select(control) }
        .onHover { hover = $0 }
        .dropDestination(for: String.self) { items, _ in onDrop(items) } isTargeted: { targeted = $0 }
        .animation(.easeOut(duration: 0.15), value: accent)
    }
}
