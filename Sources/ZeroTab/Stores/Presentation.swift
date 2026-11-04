import SwiftUI
import ZeroTabCore

final class Presentation: ObservableObject {
    @Published var items: [SwitchItem] = []
    @Published var index = 0
    var shouldScrollSelection = true
    var mode: SwitchMode = .applications
    var columns = 1
    var iconSize: CGFloat = 104
    var cellWidth: CGFloat { iconSize }
    var cellHeight: CGFloat { iconSize }
    var width: CGFloat = 600
    var height: CGFloat = 150
    var isGrid = false
    // Keep the upper indicator clear of the previous row's caption.
    var rowSpacing: CGFloat { mode == .windows ? 38 : ApplicationLayout.rowSpacing }

    func configure(items: [SwitchItem], mode: SwitchMode, overflow: OverflowLayout, screen: NSScreen) {
        shouldScrollSelection = true
        self.mode = mode
        let maxWidth = max(240, screen.visibleFrame.width * 0.94)
        let maxHeight = max(140, screen.visibleFrame.height * 0.72)
        isGrid = overflow == .wrap
        let layout = ApplicationLayout(count: items.count, maxWidth: maxWidth, maxHeight: maxHeight,
            wrap: isGrid, rowSpacing: rowSpacing)
        iconSize = layout.iconSize
        columns = layout.columns
        width = layout.width
        height = layout.height
        self.items = items
        index = 0
    }
}
