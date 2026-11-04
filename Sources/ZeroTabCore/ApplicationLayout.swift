import Foundation

/// Shared geometry for the panel and its cells; independent of screens and AppKit.
public struct ApplicationLayout: Sendable {
    public static let padding: Double = 22
    public static let rowSpacing: Double = 20
    public static let iconGap: Double = 8
    public static let nameHeight: Double = 16
    // Use the icon canvas's transparent lower edge to balance the caption's gaps.
    public static let captionOverlap: Double = 2
    public let iconSize: Double
    public let columns: Int
    public let width: Double
    public let height: Double
    public var cellWidth: Double { iconSize }
    public var cellHeight: Double { iconSize }

    public init(count: Int, maxWidth: Double, maxHeight: Double, wrap: Bool, rowSpacing: Double = Self.rowSpacing) {
        let count = max(1, count)
        let available = max(1, maxWidth - Self.padding * 2)
        iconSize = wrap ? 104 : min(104, max(56, (available + Self.iconGap) / Double(count) - Self.iconGap))
        columns = wrap ? min(count, max(1, Int((available + Self.iconGap) / (iconSize + Self.iconGap)))) : count
        width = min(maxWidth, Double(columns) * iconSize + Double(columns - 1) * Self.iconGap + Self.padding * 2)
        let rows = wrap ? (count + columns - 1) / columns : 1
        height = min(maxHeight, Double(rows) * iconSize + Double(rows - 1) * rowSpacing + Self.padding * 2)
    }
}
