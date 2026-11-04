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
    var appName = ""

    func configure(items: [SwitchItem], mode: SwitchMode, overflow: OverflowLayout, screen: NSScreen) {
        shouldScrollSelection = true
        self.mode = mode
        self.appName = items.first?.application.localizedName ?? "窗口"
        let maxWidth = max(240, screen.visibleFrame.width * 0.94)
        let maxHeight = max(140, screen.visibleFrame.height * 0.72)
        if mode == .applications {
            isGrid = overflow == .wrap
            let layout = ApplicationLayout(count: items.count, maxWidth: maxWidth, maxHeight: maxHeight, wrap: isGrid)
            iconSize = layout.iconSize
            columns = layout.columns
            width = layout.width
            height = layout.height
        } else {
            isGrid = false; columns = 1
            width = min(maxWidth, 620)
            // Reserve room for the heading, hints, spacing and padding even for one row.
            height = min(maxHeight, CGFloat(max(1, items.count)) * 52 + 96)
        }
        self.items = items
        index = 0
    }
}
