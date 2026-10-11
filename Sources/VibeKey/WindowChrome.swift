import AppKit
import SwiftUI

/// The editor lives in an AppKit-managed window so it can be opened from anywhere.
/// An empty unified toolbar gives a 52pt title bar with the traffic lights vertically centered;
/// the SwiftUI header draws inside that band (clicks there still reach SwiftUI).
@MainActor
enum EditorWindow {
    private static var window: NSWindow?
    private static var toolbarDelegate: EditorToolbar?

    static func show(_ state: AppState) {
        let isNew = window == nil
        if isNew { window = make(state) }
        guard let w = window else { return }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        if isNew {
            fitHeaderToTrafficLights(w, state)
            // Don't start with the search field focused.
            DispatchQueue.main.async { w.makeFirstResponder(nil) }
        }
    }

    /// The header is as tall as the title bar band the traffic lights are centered in.
    private static func fitHeaderToTrafficLights(_ w: NSWindow, _ state: AppState) {
        w.layoutIfNeeded()
        guard let close = w.standardWindowButton(.closeButton),
              let zoom = w.standardWindowButton(.zoomButton),
              let host = w.contentView as? EditorHostingView else { return }
        var chrome = EditorChrome()
        let centerFromTop = w.frame.height - close.convert(close.bounds, to: nil).midY
        if centerFromTop > 8 && centerFromTop < 60 { chrome.titlebarHeight = (centerFromTop * 2).rounded() }
        chrome.leadingInset = zoom.convert(zoom.bounds, to: nil).maxX + 16
        if host.rootView.chrome != chrome { host.rootView = EditorRoot(state: state, chrome: chrome) }
    }

    private static func make(_ state: AppState) -> NSWindow {
        let host = EditorHostingView(rootView: EditorRoot(state: state, chrome: .init()))
        host.sizingOptions = [.minSize]
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.contentView = host
        w.title = "Vibe Key"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        // The header's buttons live in real toolbar items: the toolbar band is a window-server drag
        // region, so SwiftUI content drawn underneath it never receives real clicks.
        let toolbar = NSToolbar(identifier: "VibeKeyEditor")
        toolbarDelegate = EditorToolbar(state: state)
        toolbar.delegate = toolbarDelegate
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        w.toolbar = toolbar
        w.toolbarStyle = .unified
        w.titlebarSeparatorStyle = .none
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = NSColor(Theme.canvas)
        w.isReleasedWhenClosed = false
        w.setContentSize(NSSize(width: 1280, height: 820))
        w.setFrameAutosaveName("VibeKeyEditor")
        if !w.setFrameUsingName("VibeKeyEditor") { w.center() }
        return w
    }
}

/// The header sits in the title-bar band. If the hosting view reports that a mouse-down can move
/// the window, the window server treats that whole band as a drag region and real clicks never
/// reach the header's buttons. Dragging is handled explicitly by `WindowDragArea` instead.
final class EditorHostingView: NSHostingView<EditorRoot> {
    override var mouseDownCanMoveWindow: Bool { false }
}

struct EditorChrome: Equatable {
    var titlebarHeight: CGFloat = 52
    var leadingInset: CGFloat = 94
}

struct EditorRoot: View {
    @ObservedObject var state: AppState
    let chrome: EditorChrome

    var body: some View {
        EditorView(chrome: chrome)
            .environmentObject(state)
            .frame(minWidth: 1040, minHeight: 680)
            .preferredColorScheme(.dark)
            .tint(Theme.teal)
    }
}

/// Background for custom title-bar areas: drag to move the window, double-click to zoom/minimize
/// (following the user's "double-click a window's title bar" preference).
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragView: NSView {
        // false so the window server doesn't claim the area (SwiftUI buttons drawn on top of
        // this view are invisible to it); we start the drag ourselves in mouseDown.
        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                case "Minimize": window.performMiniaturize(nil)
                case "None": break
                default: window.performZoom(nil)
                }
            } else {
                window.performDrag(with: event)
            }
        }
    }
}

@MainActor
final class EditorToolbar: NSObject, NSToolbarDelegate {
    static let controls = NSToolbarItem.Identifier("vibekey.controls")
    private let state: AppState

    init(state: AppState) { self.state = state }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.controls]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard id == Self.controls else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.view = NSHostingView(rootView: HeaderControls()
            .environmentObject(state)
            .preferredColorScheme(.dark)
            .tint(Theme.teal))
        item.isBordered = false
        item.label = "Controls"
        return item
    }
}
