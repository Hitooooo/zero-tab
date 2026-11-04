import SwiftUI
import ZeroTabCore

final class Presentation: ObservableObject {
    @Published var items: [SwitchItem] = []
    @Published var index = 0
    var mode: SwitchMode = .applications
    var columns = 1
    var iconSize: CGFloat = 88
    var width: CGFloat = 600
    var height: CGFloat = 150
    var isGrid = false
    var appName = ""

    func configure(items: [SwitchItem], mode: SwitchMode, overflow: OverflowLayout, screen: NSScreen) {
        self.mode = mode
        self.appName = items.first?.application.localizedName ?? "窗口"
        let maxWidth = max(240, screen.visibleFrame.width * 0.86)
        let maxHeight = max(140, screen.visibleFrame.height * 0.72)
        if mode == .applications {
            isGrid = overflow == .wrap
            iconSize = isGrid ? 88 : min(88, max(36, (maxWidth - 48) / CGFloat(max(items.count, 1)) - 24))
            let cell = iconSize + 24
            columns = isGrid ? max(1, Int((maxWidth - 32) / cell)) : max(1, items.count)
            columns = min(columns, max(1, items.count))
            width = min(maxWidth, CGFloat(columns) * cell + 32)
            let rows = isGrid ? Int(ceil(Double(items.count) / Double(columns))) : 1
            height = min(maxHeight, CGFloat(rows) * (iconSize + 48) + 32)
        } else {
            isGrid = false; columns = 1
            width = min(maxWidth, 620)
            height = min(maxHeight, CGFloat(max(1, items.count)) * 52 + 76)
        }
        self.items = items
        index = 0
    }
}
