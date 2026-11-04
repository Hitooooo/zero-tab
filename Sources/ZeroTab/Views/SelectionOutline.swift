import SwiftUI
import ZeroTabCore

/// An ordinary selection outline composited with the material behind it.
/// This is not another glass surface and never samples or stores screen images.
struct SelectionOutline: NSViewRepresentable {
    func makeNSView(context: Context) -> SelectionOutlineView { SelectionOutlineView() }
    func updateNSView(_ view: SelectionOutlineView, context: Context) { view.needsDisplay = true }
}

final class SelectionOutlineView: NSView {
    init() {
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }
    override var isOpaque: Bool { false }
    override var allowsVibrancy: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let size = min(bounds.width, bounds.height)
        guard size > 0 else { return }
        let geometry = SelectionOutlineGeometry(bounds: bounds)
        let path = NSBezierPath(cgPath: RoundedRectangle(cornerRadius: geometry.cornerRadius, style: .continuous)
            .path(in: geometry.pathRect).cgPath)
        path.lineWidth = geometry.lineWidth
        NSColor.secondaryLabelColor.setStroke()
        path.stroke()
    }
}
