import Foundation
import CoreGraphics

/// The outer boundary and stroke centerline share one concentric geometry.
public struct SelectionOutlineGeometry: Sendable {
    public let outerRect: CGRect
    public let pathRect: CGRect
    public let lineWidth: CGFloat
    public let cornerRadius: CGFloat

    public init(bounds: CGRect) {
        let size = max(0, min(bounds.width, bounds.height))
        lineWidth = size > 0 ? max(1.5, size * 0.026) : 0
        let inset = size * 0.05
        outerRect = CGRect(x: bounds.midX - size / 2 + inset, y: bounds.midY - size / 2 + inset,
                           width: size - inset * 2, height: size - inset * 2)
        pathRect = outerRect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        // Follow the app icon's rounded corner rather than widening the gap there.
        cornerRadius = max(0, size * 0.255 - lineWidth / 2)
    }
}
