import SwiftUI
import ServiceManagement

enum OverflowLayout: String, CaseIterable, Identifiable {
    case shrink, wrap
    var id: String { rawValue }
    var title: String { self == .shrink ? "等比例缩小" : "自动换行" }
}

final class Preferences: ObservableObject {
    private let defaults: UserDefaults
    @Published var showDock: Bool { didSet { defaults.set(showDock, forKey: "showDock"); onAppearanceChange?() } }
    @Published var showMenuBar: Bool { didSet { defaults.set(showMenuBar, forKey: "showMenuBar"); onAppearanceChange?() } }
    @Published var overflow: OverflowLayout { didSet { defaults.set(overflow.rawValue, forKey: "overflow") } }
    @Published private(set) var loginEnabled = false
    @Published var loginMessage: String?
    var onAppearanceChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["showDock": false, "showMenuBar": true, "overflow": "shrink"])
        showDock = defaults.bool(forKey: "showDock")
        showMenuBar = defaults.bool(forKey: "showMenuBar")
        overflow = OverflowLayout(rawValue: defaults.string(forKey: "overflow") ?? "") ?? .shrink
        refreshLoginStatus()
    }

    func refreshLoginStatus() {
        loginEnabled = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
        loginMessage = SMAppService.mainApp.status == .requiresApproval ? "请在系统设置的登录项中允许 ZeroTab。" : nil
    }

    func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLoginStatus()
        } catch {
            refreshLoginStatus()
            loginMessage = "未能修改开机启动设置。请将 App 放在固定位置后重试。"
        }
    }
}
