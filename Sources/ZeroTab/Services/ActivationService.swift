import AppKit
import ApplicationServices
import OSLog

final class ActivationService {
    private let queue = DispatchQueue(label: "dev.hitomeng.ZeroTab.activation", qos: .userInitiated)
    private let lock = NSLock()
    private var generation: UInt64 = 0
    let catalog: WindowCatalog
    private let logger = Logger(subsystem: "dev.hitomeng.ZeroTab", category: "Activation")
    var onFeedback: ((String) -> Void)?

    init(catalog: WindowCatalog) { self.catalog = catalog }

    func cancelPending() {
        lock.lock(); generation &+= 1; lock.unlock()
    }

    private func current(_ token: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }; return generation == token
    }

    func activate(_ item: SwitchItem) {
        cancelPending()
        lock.lock(); let token = generation; lock.unlock()
        guard !item.application.isTerminated else { onFeedback?("该应用已退出。"); return }
        if let window = item.window {
            activate(window, app: item.application, token: token)
        } else {
            catalog.query(pid: item.application.processIdentifier) { [weak self] result in
                guard let self, self.current(token), !item.application.isTerminated else { return }
                switch result {
                case .success(let windows):
                    if let target = windows.max(by: { $0.attention < $1.attention }) {
                        self.activate(target, app: item.application, token: token)
                    } else { self.reopen(item.application, token: token) }
                case .unavailable(let message):
                    // Query failure cannot justify creating a new window.
                    item.application.unhide()
                    item.application.activate(options: [])
                    self.onFeedback?(message)
                }
            }
        }
    }

    func reopen(_ app: NSRunningApplication) {
        cancelPending()
        lock.lock(); let token = generation; lock.unlock()
        reopen(app, token: token)
    }

    private func reopen(_ app: NSRunningApplication, token: UInt64) {
        guard current(token), !app.isTerminated, let url = app.bundleURL else { return }
        app.unhide()
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self, self.current(token) else { return }
                if error != nil { self.onFeedback?("未能重新打开该应用。"); return }
                self.verifyReopen(app, token: token, attempt: 0)
            }
        }
    }

    private func verifyReopen(_ app: NSRunningApplication, token: UInt64, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.current(token), !app.isTerminated else { return }
            self.catalog.query(pid: app.processIdentifier) { [weak self] result in
                guard let self, self.current(token) else { return }
                if case .success(let windows) = result, !windows.isEmpty { return }
                if attempt < 3 { self.verifyReopen(app, token: token, attempt: attempt + 1) }
                else { self.onFeedback?("该应用尚未打开可用窗口，请从应用菜单打开。") }
            }
        }
    }

    private func activate(_ window: WindowRecord, app: NSRunningApplication, token: UInt64) {
        logger.info("Focus requested; targetAlreadyFocused=\(window.focused), sameApplication=\(NSWorkspace.shared.frontmostApplication?.processIdentifier == window.pid)")
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
            _ = AXAccess.set(window.element, kAXMainAttribute, kCFBooleanTrue)
            _ = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
            guard self.current(token) else { return }
            DispatchQueue.main.async {
                guard self.current(token), !app.isTerminated else { return }
                app.activate(options: [])
                self.queue.async {
                    guard self.current(token) else { return }
                    let axApp = AXUIElementCreateApplication(window.pid)
                    AXUIElementSetMessagingTimeout(axApp, 0.25)
                    let focusResult = AXAccess.set(axApp, kAXFocusedWindowAttribute, window.element)
                    let mainResult = AXAccess.set(window.element, kAXMainAttribute, kCFBooleanTrue)
                    let elementResult = AXAccess.set(window.element, kAXFocusedAttribute, kCFBooleanTrue)
                    let raiseResult = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
                    self.logger.info("Public focus operations: appFocus=\(focusResult.rawValue), main=\(mainResult.rawValue), elementFocus=\(elementResult.rawValue), raise=\(raiseResult.rawValue)")
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
                let matches: Bool
                if let expectedID = window.windowID, let actualID { matches = expectedID == actualID }
                else { matches = focused.map({ CFEqual($0, window.element) }) ?? false }
                if isFront && matches {
                    self.logger.info("Target window focus confirmed")
                    return
                }
                if attempt < 2 { self.verifyFocus(window, app: app, token: token, attempt: attempt + 1) }
                else {
                    self.logger.info("Target focus not confirmed; front=\(isFront), matches=\(matches)")
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
