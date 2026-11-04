import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences

    var body: some View {
        TabView {
            general.tabItem { Label("通用", systemImage: "slider.horizontal.3") }
            shortcuts.tabItem { Label("切换", systemImage: "rectangle.2.swap") }
            permissions.tabItem { Label("权限与状态", systemImage: "hand.raised") }
        }
        .frame(width: 580, height: 460)
    }

    private var general: some View {
        Form {
            Section("启动与显示") {
                Toggle("在 Dock 中显示", isOn: $preferences.showDock)
                Toggle("在菜单栏显示图标", isOn: $preferences.showMenuBar)
                Toggle("登录时启动", isOn: Binding(get: { preferences.loginEnabled }, set: preferences.setLoginEnabled))
                if let message = preferences.loginMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
            Section {
                Text("手动打开 ZeroTab 会进入设置。关闭此窗口后，切换功能继续在后台运行。")
                if !preferences.showDock && !preferences.showMenuBar {
                    Label("两个图标已隐藏。再次打开 ZeroTab 即可回到此处。", systemImage: "info.circle")
                }
            }.font(.callout).foregroundStyle(.secondary)
            Section {
                HStack {
                    Button(model.paused ? "恢复切换" : "暂停切换", action: model.togglePause)
                    Spacer()
                    Button("退出 ZeroTab") { NSApp.terminate(nil) }
                }
            }
        }.formStyle(.grouped)
    }

    private var shortcuts: some View {
        Form {
            Section("键盘操作") {
                LabeledContent("切换应用", value: "⌘ Tab")
                LabeledContent("切换当前应用的窗口", value: "⌥ Tab")
                LabeledContent("反向选择", value: "Shift + Tab")
                LabeledContent("移动选择", value: "← ↑ ↓ →")
                LabeledContent("确认 / 取消", value: "松开修饰键 / Esc")
            }
            Section("应用图标过多时") {
                Picker("排列方式", selection: $preferences.overflow) {
                    ForEach(OverflowLayout.allCases) { Text($0.title).tag($0) }
                }
                Text(preferences.overflow == .wrap
                     ? "图标自动换行，方向键按网格位置移动。"
                     : "图标统一缩小；达到最小尺寸后，单行滚动。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("查看切换面板") { model.onPreview?() }
                Text("仅查看外观，不切换应用。按 Esc 或点击面板外关闭。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private var permissions: some View {
        Form {
            Section("运行状态") {
                Label(model.status, systemImage: model.inputRunning ? "checkmark.circle.fill" : "info.circle")
                    .foregroundStyle(model.inputRunning ? Color.green : Color.secondary)
                if let feedback = model.lastFeedback { Text(feedback).font(.caption).foregroundStyle(.secondary) }
            }
            Section("辅助功能") {
                LabeledContent("读取窗口名称并切换窗口", value: model.accessibilityGranted ? "已允许" : "尚未允许")
                Button("打开辅助功能设置", action: model.requestAccessibility)
                Text("开发版本更新后，系统可能要求重新授权。授权后若未生效，请退出并重新打开 ZeroTab。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("打开输入监控设置", action: model.requestInputMonitoring)
                Button("重新检查") { model.refresh(force: true) }
                Text("不采集窗口截图。其他桌面的窗口会标记并排在末尾；无法确认位置时单独标记。个别应用可能不提供完整窗口列表，跨桌面精确跳转仍需验证。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}
