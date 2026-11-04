import AppKit
import ZeroTabCore
import OSLog

final class SwitchCoordinator {
    private var panelStorage: SwitcherPanelController?
    var panel: SwitcherPanelController {
        if let panelStorage { return panelStorage }
        let created = SwitcherPanelController(); panelStorage = created; return created
    }
    let catalog = WindowCatalog()
    private let activation = ActivationService()
    private let applicationOpener = ApplicationOpener()
    private let focusObserver = FocusObserver()
    private let model: AppModel
    private var applications: [NSRunningApplication] = []
    private var appAttention: [pid_t: UInt64] = [:]
    private var sequence: UInt64 = 0
    private var selection = Selection(count: 0)
    private var generation: UInt64 = 0
    private var pendingActions: [InputAction] = []
    private var loading = false
    private var sessionActive = false
    private var sessionMode = SwitchMode.applications
    private var observers: [NSObjectProtocol] = []
    private var previewMonitor: Any?
    private var clickMonitor: Any?
    private var localClickMonitor: Any?
    private var previewing = false
    private var focusRefresh: DispatchWorkItem?
    private var observingPID: pid_t?
    private let logger = Logger(subsystem: "dev.hitomeng.ZeroTab", category: "Switcher")

    init(model: AppModel) {
        self.model = model
        activation.onFeedback = { [weak model] in model?.lastFeedback = $0 }
        applicationOpener.onFeedback = { [weak model] in model?.lastFeedback = $0 }
        refreshApps()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in self?.workspaceChanged(note) })
        }
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            // Do not update a frozen session after the user changes desktop independently.
            self?.cancel()
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.cancel() })
        focusObserver.onChange = { [weak self] pid in self?.refreshFocus(pid) }
    }

    func permissionsChanged() {
        guard model.accessibilityGranted else {
            focusObserver.stop(); observingPID = nil; return
        }
        if let app = NSWorkspace.shared.frontmostApplication,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            guard observingPID != app.processIdentifier else { return }
            observingPID = app.processIdentifier
            focusObserver.observe(pid: app.processIdentifier)
            refreshFocus(app.processIdentifier)
        }
    }

    private func refreshApps() {
        let own = ProcessInfo.processInfo.processIdentifier
        applications = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != own && !$0.isTerminated
        }.sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != own {
            sequence &+= 1; appAttention[front.processIdentifier] = sequence
        }
    }

    private func workspaceChanged(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if notification.name == NSWorkspace.didTerminateApplicationNotification {
            appAttention[app.processIdentifier] = nil
            catalog.forget(pid: app.processIdentifier)
        }
        refreshApps()
        if notification.name == NSWorkspace.didActivateApplicationNotification,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            if model.accessibilityGranted {
                observingPID = app.processIdentifier
                focusObserver.observe(pid: app.processIdentifier); refreshFocus(app.processIdentifier)
            }
        }
    }

    private func refreshFocus(_ pid: pid_t) {
        focusRefresh?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.catalog.query(pid: pid) { _ in } }
        focusRefresh = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: task)
    }

    func handle(_ action: InputAction) {
        if case .begin(let mode, let backwards) = action { begin(mode, backwards: backwards); return }
        guard sessionActive else { return }
        if action == .cancel { cancel(); return }
        if loading { pendingActions.append(action); return }
        apply(action)
    }

    private func begin(_ mode: SwitchMode, backwards: Bool) {
        cancel()
        cancelPendingActivation()
        generation &+= 1
        let token = generation
        sessionMode = mode; sessionActive = true
        let screen = NSScreen.main ?? NSScreen.screens.first!
        if mode == .applications {
            refreshApps()
            let ordered = applications.enumerated().sorted {
                let left = appAttention[$0.element.processIdentifier, default: 0]
                let right = appAttention[$1.element.processIdentifier, default: 0]
                return left == right ? $0.offset < $1.offset : left > right
            }.map(\.element)
            let items = ordered.map { makeItem(app: $0) }
            ready(items, screen: screen, backwards: backwards, currentID: nil)
        } else {
            guard let app = NSWorkspace.shared.frontmostApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { cancel(); return }
            loading = true
            catalog.query(pid: app.processIdentifier, continueDiscovery: true) { [weak self] result in
                guard let self, self.sessionActive, self.generation == token, !app.isTerminated else { return }
                switch result {
                case .unavailable(let text): self.model.lastFeedback = text; self.cancel()
                case .success(let windows):
                    guard !windows.isEmpty else {
                        self.model.lastFeedback = "当前应用没有可切换的窗口，可用 ⌘ Tab 重新打开应用。"
                        self.cancel(); return
                    }
                    let ranked = windows.enumerated().map {
                        RankedItem(id: $0.element.id, location: $0.element.location, attention: $0.element.attention, ordinal: $0.offset)
                    }
                    let order = CandidateOrder.sorted(ranked).map(\.id)
                    let byID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
                    let items = order.compactMap { byID[$0] }.map { self.makeItem(app: app, window: $0) }
                    let focused = windows.first(where: \.focused).map { $0.id.uuidString }
                    self.ready(items, screen: screen, backwards: backwards, currentID: focused)
                }
            }
        }
    }

    private func makeItem(app: NSRunningApplication, window: WindowRecord? = nil) -> SwitchItem {
        let icon = app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!
        return SwitchItem(id: window?.id.uuidString ?? "app-\(app.processIdentifier)-\(app.launchDate?.timeIntervalSince1970 ?? 0)",
            title: window?.title ?? app.localizedName ?? "应用", application: app, icon: icon, window: window)
    }

    private func ready(_ items: [SwitchItem], screen: NSScreen, backwards: Bool, currentID: String?) {
        loading = false
        panel.presentation.configure(items: items, mode: sessionMode, overflow: model.preferences.overflow, screen: screen)
        let initial = currentID.flatMap { id in items.firstIndex(where: { $0.id == id }) } ?? 0
        selection = Selection(count: items.count, columns: panel.presentation.columns, index: initial)
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let currentIsRepresented = currentID != nil || (sessionMode == .applications && items.contains { $0.application.processIdentifier == frontPID })
        if currentIsRepresented || backwards { selection.cycle(backwards ? -1 : 1) }
        panel.presentation.index = selection.index
        let buffered = pendingActions; pendingActions.removeAll()
        // A completed quick chord need not flash the panel while its AX query finishes.
        if items.count > 1 && !buffered.contains(.commit) { panel.show(on: screen) }
        for action in buffered {
            guard sessionActive else { break }
            apply(action)
        }
    }

    private func apply(_ action: InputAction) {
        switch action {
        case .cycle(let delta): selection.cycle(delta)
        case .move(let direction):
            selection.move(direction, linear: sessionMode == .windows || !panel.presentation.isGrid)
        case .commit:
            let items = panel.presentation.items
            let target = items.indices.contains(selection.index) ? items[selection.index] : nil
            let mode = sessionMode
            cancel()
            guard let target else { return }
            switch mode {
            case .applications: applicationOpener.open(target.application)
            case .windows:
                if let window = target.window { activation.activate(window, app: target.application) }
            }
        case .cancel: cancel()
        case .begin: break
        }
        panel.presentation.index = selection.index
    }

    func cancel() {
        if previewing { logger.info("Preview closed") }
        generation &+= 1; sessionActive = false; loading = false
        pendingActions.removeAll(); panelStorage?.hide()
        if let previewMonitor { NSEvent.removeMonitor(previewMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        previewMonitor = nil; clickMonitor = nil; localClickMonitor = nil; previewing = false
    }

    func cancelPendingActivation() {
        applicationOpener.cancelPending()
        activation.cancelPending()
    }

    func preview() {
        cancel(); cancelPendingActivation(); refreshApps()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        panel.presentation.configure(items: applications.map { makeItem(app: $0) }, mode: .applications,
            overflow: model.preferences.overflow, screen: screen)
        selection = Selection(count: applications.count, columns: panel.presentation.columns)
        previewing = true; panel.show(on: screen, forPreview: true)
        logger.info("Preview shown; visible=\(self.panel.isVisible), count=\(self.applications.count)")
        previewMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.previewing else { return event }
            switch event.keyCode {
            case 53: self.cancel()
            case 48: self.selection.cycle(event.modifierFlags.contains(.shift) ? -1 : 1)
            case 123: self.selection.move(.left, linear: !self.panel.presentation.isGrid)
            case 124: self.selection.move(.right, linear: !self.panel.presentation.isGrid)
            case 125: self.selection.move(.down, linear: !self.panel.presentation.isGrid)
            case 126: self.selection.move(.up, linear: !self.panel.presentation.isGrid)
            default: return event
            }
            self.panel.presentation.index = self.selection.index
            return nil
        }
        // Register after the opening button's event has finished dispatching.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.previewing else { return }
            self.clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.cancel() }
            self.localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                self?.cancel(); return event
            }
        }
    }

    deinit {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0); NotificationCenter.default.removeObserver($0) }
        focusObserver.stop()
    }
}
