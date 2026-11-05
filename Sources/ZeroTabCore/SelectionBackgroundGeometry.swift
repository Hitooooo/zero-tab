import Foundation
import CoreGraphics

/// A centered, filled backing behind the icon's transparent canvas margins.
public struct SelectionBackgroundGeometry: Sendable {
    public let rect: CGRect
    public let cornerRadius: CGFloat

    public init(bounds: CGRect) {
        let size = max(0, min(bounds.width, bounds.height))
        // Expand the previous outline by 3 pt at the standard 104 pt icon size.
        let expansion = size / 104 * 3
        let inset = size * 0.05 - expansion
        rect = CGRect(x: bounds.midX - size / 2 + inset, y: bounds.midY - size / 2 + inset,
                      width: size - inset * 2, height: size - inset * 2)
        // Expand the corner with the backing, keeping it parallel to the icon.
        cornerRadius = size * 0.255 + expansion
    }
}
