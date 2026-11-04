import AppKit
import Carbon
import OSLog

/// Application switching follows the system open/reopen contract. It never
/// enumerates windows or chooses a window on the application's behalf.
final class ApplicationOpener {
    private var generation: UInt64 = 0
    private let logger = Logger(subsystem: "dev.hitomeng.ZeroTab", category: "ApplicationOpen")
    var onFeedback: ((String) -> Void)?

    func cancelPending() { generation &+= 1 }

    func open(_ app: NSRunningApplication) {
        cancelPending()
        let token = generation
        guard !app.isTerminated else { onFeedback?("该应用已退出。"); return }
        guard let url = app.bundleURL else { onFeedback?("无法找到该应用的位置。"); return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.createsNewApplicationInstance = false
        config.appleEvent = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEReopenApplication),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: app.processIdentifier),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        app.unhide()
        if NSApp.isActive { NSApp.yieldActivation(to: app) }
        logger.info("Native application open requested; pid=\(app.processIdentifier)")
        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] opened, error in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                guard error == nil, let opened else {
                    self.onFeedback?("未能打开该应用。"); return
                }
                self.logger.info("Native application open completed; pid=\(opened.processIdentifier)")
                self.verifyFrontmost(opened, token: token, attempt: 0)
            }
        }
    }

    private func verifyFrontmost(_ app: NSRunningApplication, token: UInt64, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.generation == token, !app.isTerminated else { return }
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                // This confirms application activation, not creation of a window.
                self.logger.info("Native application foreground confirmed; pid=\(app.processIdentifier)")
            } else if attempt < 3 {
                self.verifyFrontmost(app, token: token, attempt: attempt + 1)
            } else {
                self.logger.info("Native application foreground not confirmed; pid=\(app.processIdentifier)")
                self.onFeedback?("未能确认该应用已来到前台，请稍后重试。")
            }
        }
    }
}
