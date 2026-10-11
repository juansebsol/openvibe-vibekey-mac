import AppKit
import SwiftUI

/// Small notification-style card shown at the top right of the screen when the active profile
/// changes, so you know which profile the device is on. Never takes focus or clicks.
@MainActor
final class ProfileHUD {
    static let shared = ProfileHUD()

    private var panel: NSPanel?
    private var host: NSHostingView<ProfileHUDCard>?
    private var hideWork: DispatchWorkItem?
    private var visible = false

    private static let margin: CGFloat = 14
    private static let displaySeconds = 1.9

    func show(name: String, index: Int, count: Int) {
        let card = ProfileHUDCard(name: name, index: index, count: count)
        let (panel, host) = ensurePanel()
        host.rootView = card
        let size = host.fittingSize
        let target = Self.frame(for: size)

        if visible {
            // Rapid switching: update in place, keep it up a little longer.
            panel.setFrame(target, display: true)
        } else {
            panel.setFrame(target.offsetBy(dx: 18, dy: 0), display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            panel.invalidateShadow()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.24
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
                panel.animator().setFrame(target, display: true)
                panel.animator().alphaValue = 1
            }
            visible = true
        }

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.displaySeconds, execute: work)
    }

    private func hide() {
        guard let panel, visible else { return }
        visible = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 0
            panel.animator().setFrame(panel.frame.offsetBy(dx: 10, dy: 0), display: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                if self?.visible == false { panel.orderOut(nil) }
            }
        })
    }

    /// Top right of the screen the user is working on, just under the menu bar.
    private static func frame(for size: NSSize) -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(x: visible.maxX - size.width - margin, y: visible.maxY - size.height - margin,
                      width: size.width, height: size.height)
    }

    private func ensurePanel() -> (NSPanel, NSHostingView<ProfileHUDCard>) {
        if let panel, let host { return (panel, host) }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 64),
                        styleMask: [.nonactivatingPanel, .borderless],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.appearance = NSAppearance(named: .darkAqua)

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 16
        blur.layer?.cornerCurve = .continuous
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 1
        blur.layer?.borderColor = NSColor.white.withAlphaComponent(0.09).cgColor

        let h = NSHostingView(rootView: ProfileHUDCard(name: "", index: 0, count: 1))
        h.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(h)
        NSLayoutConstraint.activate([
            h.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            h.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            h.topAnchor.constraint(equalTo: blur.topAnchor),
            h.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        p.contentView = blur
        panel = p
        host = h
        return (p, h)
    }
}

struct ProfileHUDCard: View {
    let name: String
    let index: Int
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.teal, Theme.tealOnLight], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "person.crop.rectangle.stack.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.onTeal)
            }
            .frame(width: 38, height: 38)
            .shadow(color: Theme.teal.opacity(0.35), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 3) {
                Text("PROFILE")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Color.white.opacity(0.5))
                Text(name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Spacer(minLength: 14)

            if count > 1 && count <= 10 {
                HStack(spacing: 5) {
                    ForEach(0..<count, id: \.self) { i in
                        Capsule()
                            .fill(i == index ? Theme.teal : Color.white.opacity(0.22))
                            .frame(width: i == index ? 14 : 6, height: 6)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: index)
            } else if count > 10 {
                Text("\(index + 1)/\(count)")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.55))
            }
        }
        .padding(.leading, 13)
        .padding(.trailing, 16)
        .padding(.vertical, 12)
        .frame(minWidth: 280)
        // Dark tint over the blur so the card reads the same on any wallpaper.
        .background(LinearGradient(colors: [Color(red: 0.13, green: 0.135, blue: 0.155).opacity(0.82),
                                            Color(red: 0.08, green: 0.085, blue: 0.10).opacity(0.86)],
                                   startPoint: .top, endPoint: .bottom))
        .fixedSize()
    }
}
