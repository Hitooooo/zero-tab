import SwiftUI

private final class SwitcherPanel: NSPanel {
    var previewAllowsKey = false
    override var canBecomeKey: Bool { previewAllowsKey }
    override var canBecomeMain: Bool { false }
}

final class SwitcherPanelController {
    let presentation = Presentation()
    private let panel: NSPanel

    init() {
        panel = SwitcherPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.setAccessibilityLabel("ZeroTab 切换器")
        panel.title = "ZeroTab 切换器"
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = 24
        let hosting = NSHostingView(rootView: SwitcherView(model: presentation))
        hosting.sizingOptions = []
        glass.contentView = hosting
        panel.contentView = glass
    }

    func show(on screen: NSScreen, forPreview: Bool = false) {
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
}
