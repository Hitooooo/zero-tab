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
    private var refreshed = false

    func refresh(force: Bool = false) {
        let granted = AXIsProcessTrusted()
        let changed = accessibilityGranted != granted || !refreshed
        accessibilityGranted = granted
        refreshed = true
        preferences.refreshLoginStatus()
        if changed || force { onRefresh?() }
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
