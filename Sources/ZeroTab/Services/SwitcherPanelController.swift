import SwiftUI

private final class SwitcherPanel: NSPanel {
    var previewAllowsKey = false
    override var canBecomeKey: Bool { previewAllowsKey }
    override var canBecomeMain: Bool { false }
}

private final class SwitcherHostingView: NSHostingView<SwitcherView> {
    override var isOpaque: Bool { false }
    // The live panel stays non-key, but its first click must still reach a button.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class SwitcherPanelController {
    let presentation = Presentation()
    private let panel: NSPanel
    private let glass = NSGlassEffectView()
    private var lastPointerLocation = NSEvent.mouseLocation

    init(onSelect: @escaping (String) -> Void, onHover: @escaping (String) -> Void) {
        panel = SwitcherPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.setAccessibilityLabel("ZeroTab 切换器")
        panel.title = "ZeroTab 切换器"
        glass.style = .clear
        glass.cornerRadius = 32
        let hosting = SwitcherHostingView(rootView: SwitcherView(model: presentation, onSelect: onSelect,
            onHover: { [weak self] id in
                guard let self, self.isVisible else { return }
                let location = NSEvent.mouseLocation
                // Opening or updating a view under a stationary pointer must not undo
                // the initial keyboard selection or subsequent arrow/Tab navigation.
                guard location != self.lastPointerLocation else { return }
                self.lastPointerLocation = location
                onHover(id)
            }))
        hosting.sizingOptions = []
        glass.contentView = hosting
        panel.contentView = glass
    }

    func show(on screen: NSScreen, forPreview: Bool = false) {
        lastPointerLocation = NSEvent.mouseLocation
        (panel as? SwitcherPanel)?.previewAllowsKey = forPreview
        let size = NSSize(width: presentation.width, height: presentation.height)
        panel.setContentSize(size)
        if let glass = panel.contentView as? NSGlassEffectView {
            glass.contentView?.frame = NSRect(origin: .zero, size: size)
        }
        let rect = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        if forPreview { panel.makeKeyAndOrderFront(nil) }
        else { panel.orderFrontRegardless() }
    }

    func hide() { panel.orderOut(nil); (panel as? SwitcherPanel)?.previewAllowsKey = false }
    var isVisible: Bool { panel.isVisible }
    var window: NSWindow { panel }
}
