import SwiftUI
import ApplicationServices

final class AppModel: ObservableObject {
    @Published var accessibilityGranted = false
    @Published var inputRunning = false
    @Published var paused = false
    @Published var status = "正在检查权限…"
    @Published var lastFeedback: String?
    let preferences = Preferences()
    var onRefresh: (() -> Void)?
    var onPauseChange: (() -> Void)?
    var onPreview: (() -> Void)?
    private let accessibilityCheck: () -> Bool

    init(accessibilityCheck: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.accessibilityCheck = accessibilityCheck
    }

    func refresh() {
        accessibilityGranted = accessibilityCheck()
        preferences.refreshLoginStatus()
        // Permission can stay granted while the event tap has stopped or expired.
        // Every explicit refresh must also reconcile the actual input service.
        onRefresh?()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacy("Privacy_Accessibility")
    }

    func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
        openPrivacy("Privacy_ListenEvent")
    }

    private func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    func togglePause() { paused.toggle(); onPauseChange?() }
}
