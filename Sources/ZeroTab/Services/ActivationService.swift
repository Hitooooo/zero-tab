import AppKit
import ApplicationServices
import OSLog
import ZeroTabCore

final class ActivationService {
    private let queue = DispatchQueue(label: "dev.hitomeng.ZeroTab.activation", qos: .userInitiated)
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private let logger = Logger(subsystem: "dev.hitomeng.ZeroTab", category: "Activation")
    var onFeedback: ((String) -> Void)?

    func cancelPending() {
        lock.lock(); generation &+= 1; lock.unlock()
    }

    private func current(_ token: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }; return generation == token
    }

    func activate(_ window: WindowRecord, app: NSRunningApplication) {
        cancelPending()
        lock.lock(); let token = generation; lock.unlock()
        guard !app.isTerminated else { onFeedback?("该应用已退出。"); return }
        logger.info("Focus requested; pid=\(window.pid), targetAlreadyFocused=\(window.focused), sameApplication=\(NSWorkspace.shared.frontmostApplication?.processIdentifier == window.pid)")
        app.unhide()
        queue.async { [weak self] in
            guard let self, self.current(token), !app.isTerminated else { return }
            AXUIElementSetMessagingTimeout(window.element, 0.25)
            // An invalid element must not trigger reopen; it may simply have closed during selection.
            guard AXAccess.value(window.element, kAXRoleAttribute) as? String == kAXWindowRole else {
                self.feedback("目标窗口已关闭或暂时无响应。", token: token); return
            }
            if window.minimized { _ = AXAccess.set(window.element, kAXMinimizedAttribute, kCFBooleanFalse) }
            guard self.current(token) else { return }
            let axApp = AXUIElementCreateApplication(window.pid)
            AXUIElementSetMessagingTimeout(axApp, 0.25)
            // Window focus attributes do not make a background application active.
            // Request that separately through the public Accessibility application API.
            let frontmostResult = AXAccess.set(axApp, kAXFrontmostAttribute, kCFBooleanTrue)
            _ = AXAccess.set(window.element, kAXMainAttribute, kCFBooleanTrue)
            _ = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
            guard self.current(token) else { return }
            DispatchQueue.main.async {
                guard self.current(token), !app.isTerminated else { return }
                if NSApp.isActive { NSApp.yieldActivation(to: app) }
                let accepted = app.activate(options: [])
                self.logger.info("Application activation requested; pid=\(window.pid), accepted=\(accepted), axFrontmost=\(frontmostResult.rawValue)")
                self.queue.async {
                    guard self.current(token) else { return }
                    let axApp = AXUIElementCreateApplication(window.pid)
                    AXUIElementSetMessagingTimeout(axApp, 0.25)
                    let frontResult = AXAccess.set(axApp, kAXFrontmostAttribute, kCFBooleanTrue)
                    guard self.current(token) else { return }
                    let focusResult = AXAccess.set(axApp, kAXFocusedWindowAttribute, window.element)
                    let mainResult = AXAccess.set(window.element, kAXMainAttribute, kCFBooleanTrue)
                    let elementResult = AXAccess.set(window.element, kAXFocusedAttribute, kCFBooleanTrue)
                    let raiseResult = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
                    self.logger.info("Public focus operations: pid=\(window.pid), frontmost=\(frontResult.rawValue), appFocus=\(focusResult.rawValue), main=\(mainResult.rawValue), elementFocus=\(elementResult.rawValue), raise=\(raiseResult.rawValue)")
                    self.verifyFocus(window, app: app, token: token, attempt: 0)
                }
            }
        }
    }

    private func verifyFocus(_ window: WindowRecord, app: NSRunningApplication, token: UInt64, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.current(token), !app.isTerminated else { return }
            let isFront = NSWorkspace.shared.frontmostApplication?.processIdentifier == window.pid
            self.queue.async {
                guard self.current(token) else { return }
                let focused = AXAccess.focusedWindow(pid: window.pid)
                let actualID = focused.flatMap { ReadOnlySpaceBridge.shared.identifier(of: $0) }
                let presence = SpaceProvider.snapshot()
                let placement = SpaceProvider.placement(windowID: actualID, pid: window.pid, frame: window.frame, snapshot: presence)
                let minimized = focused.flatMap { AXAccess.value($0, kAXMinimizedAttribute) as? Bool }
                let notPresented = WindowPresence.isNotPresented(location: placement.0,
                    onScreen: presence.onScreen(windowID: actualID), minimized: minimized,
                    applicationHidden: app.isHidden, hasAssignedSpace: placement.2.map { !$0.isEmpty })
                let matches: Bool
                if let expectedID = window.windowID, let actualID { matches = expectedID == actualID }
                else { matches = focused.map({ CFEqual($0, window.element) }) ?? false }
                if isFront && matches && !notPresented {
                    self.logger.info("Target window focus confirmed; pid=\(window.pid)")
                    return
                }
                if attempt < 2 { self.verifyFocus(window, app: app, token: token, attempt: attempt + 1) }
                else {
                    self.logger.info("Target focus not confirmed; pid=\(window.pid), front=\(isFront), matches=\(matches), notPresented=\(notPresented)")
                    self.feedback("未能确认目标窗口已获得焦点，窗口切换可能受限。", token: token)
                }
            }
        }
    }

    private func feedback(_ text: String, token: UInt64) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.current(token) else { return }; self.onFeedback?(text)
        }
    }
}
