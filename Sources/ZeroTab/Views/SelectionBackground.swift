import SwiftUI
import ZeroTabCore

/// A filled selection backing composited with the material behind it.
/// This is not another glass surface and never samples or stores screen images.
struct SelectionBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> SelectionBackgroundView { SelectionBackgroundView() }
    func updateNSView(_ view: SelectionBackgroundView, context: Context) { view.needsDisplay = true }
}

final class SelectionBackgroundView: NSView {
    init() {
        super.init(frame: .zero)
        // Soften the system gray while preserving its native vibrancy response.
        alphaValue = 0.7
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }
    override var isOpaque: Bool { false }
    override var allowsVibrancy: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let size = min(bounds.width, bounds.height)
        guard size > 0 else { return }
        let geometry = SelectionBackgroundGeometry(bounds: bounds)
        let path = NSBezierPath(cgPath: RoundedRectangle(cornerRadius: geometry.cornerRadius, style: .continuous)
            .path(in: geometry.rect).cgPath)
        NSColor.secondaryLabelColor.setFill()
        path.fill()
    }
}
