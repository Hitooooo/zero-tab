import SwiftUI
import Carbon
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let logger = Logger(subsystem: "dev.hitomeng.ZeroTab", category: "Lifecycle")
    let model = AppModel()
    private let input = InputService()
    private lazy var coordinator = SwitchCoordinator(model: model)
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var workspaceTokens: [NSObjectProtocol] = []
    private var refreshing = false
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenu()
        model.preferences.onAppearanceChange = { [weak self] in self?.applyAppearance() }
        model.onRefresh = { [weak self] in self?.refreshService() }
        model.onPauseChange = { [weak self] in self?.coordinator.cancel(); self?.refreshService() }
        model.onPreview = { [weak self] in self?.coordinator.preview() }
        input.onAction = { [weak self] in self?.coordinator.handle($0) }
        input.onInterrupted = { [weak self] in
            self?.coordinator.cancel()
            self?.model.lastFeedback = "键盘监听已恢复，本次选择已取消。"
        }
        applyAppearance()
        model.refresh()
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.input.stop(); self?.coordinator.cancel(); self?.model.inputRunning = false
        })
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.model.refresh() })
        let loginLaunch = NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
        if !loginLaunch && !ProcessInfo.processInfo.arguments.contains("--background") { showSettings() }
        logger.info("Application launched; accessibility=\(self.model.accessibilityGranted)")
        logger.info("Read-only Space bridge available=\(ReadOnlySpaceBridge.shared.available)")
    }

    func applicationDidBecomeActive(_ notification: Notification) { model.refresh() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(); return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        input.stop(); coordinator.cancel(); coordinator.activation.cancelPending()
        workspaceTokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        logger.info("Application stopped; no system hotkey preferences modified")
    }

    private func refreshService() {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        if model.paused || !model.accessibilityGranted {
            input.stop(); coordinator.cancel(); model.inputRunning = false
            model.status = model.paused ? "切换已暂停" : "请先允许辅助功能权限"
        } else {
            let running = input.start()
            model.inputRunning = running
            model.status = running ? "切换服务已启用" : "无法监听快捷键，请检查权限后重试"
        }
        coordinator.permissionsChanged()
        updateStatusMenu()
    }

    private func applyAppearance() {
        NSApp.setActivationPolicy(model.preferences.showDock ? .regular : .accessory)
        if model.preferences.showMenuBar {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                item.button?.image = NSImage(systemSymbolName: "rectangle.2.swap", accessibilityDescription: "ZeroTab")
                item.button?.image?.isTemplate = true
                statusItem = item
            }
            updateStatusMenu()
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item); statusItem = nil
        }
    }

    private func updateStatusMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        let state = NSMenuItem(title: model.status, action: nil, keyEquivalent: "")
        state.isEnabled = false; menu.addItem(state)
        menu.addItem(.separator())
        menu.addItem(item("设置…", action: #selector(showSettings), key: ","))
        menu.addItem(item(model.paused ? "恢复切换" : "暂停切换", action: #selector(togglePause)))
        menu.addItem(.separator())
        menu.addItem(item("退出 ZeroTab", action: #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    private func configureMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "ZeroTab")
        appMenu.addItem(item("设置…", action: #selector(showSettings), key: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(item("退出 ZeroTab", action: #selector(quit), key: "q"))
        appItem.submenu = appMenu; menu.addItem(appItem)
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(NSMenuItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileItem.submenu = fileMenu; menu.addItem(fileItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "编辑")
        for (title, action, key) in [("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"),
                                      ("全选", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        editItem.submenu = edit; menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self; return item
    }

    @objc func showSettings() {
        coordinator.cancel()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 460),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "ZeroTab 设置"
            window.identifier = NSUserInterfaceItemIdentifier("settings")
            window.contentView = NSHostingView(rootView: SettingsView(model: model, preferences: model.preferences))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        settingsWindow?.deminiaturize(nil)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.refresh()
        if permissionTimer == nil {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                self?.model.refresh()
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        permissionTimer?.invalidate(); permissionTimer = nil
        settingsWindow = nil
    }

    @objc private func togglePause() { model.togglePause() }
    @objc private func quit() { NSApp.terminate(nil) }
}
