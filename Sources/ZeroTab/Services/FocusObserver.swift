import AppKit
import ApplicationServices

/// One observer for the front application. Title metadata is refreshed when a session starts.
final class FocusObserver {
    private var observer: AXObserver?
    private var observedPID: pid_t?
    var onChange: ((pid_t) -> Void)?

    func observe(pid: pid_t) {
        guard pid != observedPID, AXIsProcessTrusted() else { return }
        stop()
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, context in
            guard let context else { return }
            let owner = Unmanaged<FocusObserver>.fromOpaque(context).takeUnretainedValue()
            if let pid = owner.observedPID { owner.onChange?(pid) }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
        observedPID = pid; observer = created
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        for notification in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification, kAXWindowCreatedNotification] {
            AXObserverAddNotification(created, app, notification as CFString, Unmanaged.passUnretained(self).toOpaque())
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
    }

    func stop() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil; observedPID = nil
    }

    deinit { stop() }
}
