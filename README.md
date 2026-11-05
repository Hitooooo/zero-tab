# ZeroTab

原生 Swift 编写的 macOS 应用与窗口切换工具，最低 macOS 27。使用 SwiftUI 原生设置和 AppKit 毛玻璃浮动面板，无第三方依赖，不采集窗口截图。

当前为开发版本。已实现输入、选择、窗口激活及可识别窗口的跨桌面归属；完整跨桌面枚举及四个目标应用兼容性尚未全部验收。真实检查结果与限制见 [Validation.md](Validation.md)。

当前 0.1.1 build 17 修复运行时图标及原地构建后的应用注册刷新；保留 build 16 的 ⌥ Tab 与 ⌘ Tab 共用图标布局、图标正上方独立桌面指示器和下方选中标题，以及 build 14 的单层原生玻璃、系统前景对比轮廓、统一留白与即时选择。当前 build 17 的 37 项逻辑测试通过；实际验证范围见 Validation.md。build 6 用户已确认：访达全部窗口关闭后，⌘ Tab 可恢复窗口并获得前台焦点；Chrome 的 ⌥ Tab 同桌面与跨桌面窗口列表、切换及焦点正常。其余应用特殊状态仍需逐项验收。0.1.0 基线 Release App 包约 0.87 MB，完成切换并打开设置时物理内存采样为 60 MB；这些性能数字未对当前版本重新测量。

## 构建与运行

需要 Xcode 27 工具链，或具备 macOS 27 SDK 的匹配 Swift 工具链。

```sh
./script/build_and_run.sh
```

脚本先停止旧进程，再用 SwiftPM 构建，生成并签名 `dist/ZeroTab.app`，通过 Launch Services 启动。Codex 的 Run 按钮调用相同脚本。也可在 Xcode 中打开 `Package.swift` 查看及编辑源码；GUI 验证使用脚本生成的 `.app`。

```sh
# 仅生成 App
./script/build_and_run.sh --build-only

# Release 构建并启动，确认进程存在
CONFIGURATION=release ./script/build_and_run.sh --verify

# 逻辑测试
./script/test.sh

# 读取本工具自身的诊断事件，不记录窗口标题或按键文本
./script/build_and_run.sh --telemetry
```

脚本还支持 `--debug` 和 `--logs`。构建缓存放在项目 `.build/` 中；App 不包含 `.build/`、测试产物或调试符号包。

应用图标使用蓝紫双卡片精修方案，构建时复制 `Resources/AppIcon.icns` 并通过 `CFBundleIconFile` 声明。打包签名后更新应用目录时间并强制刷新该 App 的 Launch Services 注册；启动时直接加载包内 ICNS 到 AppKit 的运行时图标，覆盖旧占位图。已打开的系统设置可能保留旧图标，本机实测退出并重新打开系统设置后恢复。调整图标后可用 `uv run --with pillow --with numpy python script/generate_app_icon.py --final cards` 再生成；Python 依赖仅用于设计期，运行和常规构建不需要。配套 `Resources/AppIcon-1024.png` 和 `Resources/AppIcon.svg`，当前为静态图标，尚未接入 Icon Composer 自适应外观。

## GitHub Actions 自动构建

[Build macOS App](https://github.com/Hitooooo/zero-tab/actions/workflows/build-macos.yml) 在推送到 `main`、向 `main` 提交 Pull Request 或手动点击 **Run workflow** 时运行。使用 GitHub 的 `xcode-27` Apple Silicon 运行器和 Xcode 27.1，先执行逻辑测试，再调用现有脚本生成 Release `ZeroTab.app`；检查 plist、签名、arm64 架构和图标资源后上传构建产物，保留 30 天。

打开对应运行记录，在 **Artifacts** 下载 `ZeroTab-版本-构建号-macOS-arm64`。解压后包含 App ZIP、`SHA256SUMS.txt` 和 `BuildInfo.txt`；再解压 App ZIP 得到 `ZeroTab.app`，保留应用包结构和可执行权限。产物要求 Apple Silicon 与 macOS 27 或更新系统，使用临时签名，尚未配置 Developer ID 签名与公证。CI 的测试及打包通过不代表真实快捷键、权限、跨桌面或其他 GUI 兼容性验收通过。

若任务没有任何构建步骤，报 `The job was not acquired by Runner of type hosted` 或运行器分配阶段的 `Internal server error`，说明 GitHub 没有成功分配机器，可在运行页面选择 **Re-run jobs → Re-run failed jobs**。本项目已在相同工作流重试后完成云端测试、构建和产物上传，实际结果见 [Validation.md](Validation.md)；已开始编译后的报错应按具体日志排查。

## 使用

- `⌘ Tab`：按最近使用顺序选择运行中的应用。
- `⌥ Tab`：以与 ⌘ Tab 相同的图标面板选择前台应用的独立窗口；图标正上方显示小号桌面序号，选中图标下方显示窗口标题。
- 按住 Command／Option 重复按 Tab；加 Shift 反向选择。
- 方向键或鼠标悬停移动高亮；点击目标条目或松开对应修饰键提交；Esc 取消。
- 当前应用只有一个窗口时，`⌥ Tab` 仍显示该窗口并高亮。
- 多行应用或窗口图标中，方向键按网格位置移动；Tab 按行排列顺序循环。
- 设置支持图标统一缩小／自动换行、Dock 和菜单栏图标独立开关、开机启动及暂停。玻璃效果由 macOS 原生组件处理，无需额外调节。
- 两个图标都隐藏后，再次打开 App 即可进入设置。关闭设置窗口不退出 App。
- 设置“切换”页中的“查看切换面板”只展示外观，不激活其他应用。

首次测试需在“系统设置 → 隐私与安全性 → 辅助功能”中允许 `dist/ZeroTab.app`。无法建立键盘监听时，可检查输入监控并点击“重新检查”。不会自动请求屏幕录制权限，也不会更改系统原有快捷键设置。

本机没有可用的开发签名身份时，脚本默认临时签名；重新构建可能使辅助功能授权失效。应对固定的测试版本授权；必要时从辅助功能列表移除旧条目后重新添加当前 App。若有自己的签名身份，可设置 `ZEROTAB_SIGN_IDENTITY` 后构建。正式分发尚未配置 Developer ID 签名与公证。

## 当前能力边界

窗口标题和操作使用 Accessibility，窗口可见性辅助使用 Core Graphics。经用户确认，增加一个最小只读私有桥接：将 AX 元素映射至窗口 ID，查询窗口所属空间及各显示器当前空间。窗口图标带桌面序号，已确认属于其他桌面的窗口后置；符号不可用、结果不完整或编号暂时未知时指示器显示“?”，辅助功能保留“位置未确认”说明。不会把隐藏、最小化或查询失败直接当成其他桌面。

已实现“桌面编号标记并后置”的查询与选择逻辑，以及经用户追加确认的有预算上限的跨桌面 AX 句柄发现。补查每轮预算 120 ms，初次最多 8 轮，间隔至少 250 ms，结果缓存；不做常驻高频扫描。窗口 ID 稀疏或应用无响应时，有限枚举仍可能遗漏，完整兼容性以实测为准。不要以设置页显示“服务已启用”代替实际切换成功的验证。

`⌘ Tab` 松键后直接通过 `NSWorkspace.openApplication` 发出原生打开／重新打开请求，复用已有进程。系统与目标 App 决定如何恢复或创建默认窗口；不先查询窗口、不指定目标窗口、不维护应用恢复白名单、不发送 `⌘ N`。每次提交只发送一次请求，后续只读核对应用是否在前台，不把前台确认称为窗口重建成功。

`⌥ Tab` 保留精确窗口清单、桌面标记与后置、最小化恢复及公开 AX 聚焦。空清单或查询失败会结束本次选择，不转入重开。窗口准入统一依赖实际发布来源、角色、标题和可见状态，不按应用区分。应用正式发布的无标题窗口保留；补充句柄需要有标题的标准窗口证据。具体兼容性与历史修复记录见 Validation.md。

当前未设置窗口内容、文稿路径或隐私窗口的猜测性标签。同名窗口采用稳定标识辅助区分；Chrome 隐私窗口的专门标记尚未实现。

## 代码结构

- `Sources/ZeroTabCore/`：不依赖 AppKit 的输入状态机、列表／网格选择和排序。
- `Sources/ZeroTab/App/`：启动、重新打开、菜单、权限与设置窗口生命周期。
- `Sources/ZeroTab/Services/`：全局输入、AX 窗口查询、公开可见性判断、激活和切换协调。
- `Sources/ZeroTab/Stores/`、`Views/`：偏好、面板呈现模型、原生设置与切换器内容。
- `Tests/ZeroTabCoreTests/`：快速松键、取消锁存、修饰键、导航、分组与排序测试。

产品需求见 [Design.md](Design.md)，底层 API 研究见 [Implementation.md](Implementation.md)，开发约定见 [AGENTS.md](AGENTS.md)。
