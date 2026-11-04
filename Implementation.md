# ZeroTab 实现研究与路径

日期：2026-11-04。状态：源码研究与实现路径；已开始 SwiftPM 原生 App 开发，实际验证见 Validation.md。

## 1. 参考范围

已阅读用户指定的 [AltTab 仓库](https://github.com/lwouis/alt-tab-macos)，本次下载至临时目录进行静态分析，未构建或执行其代码，未更改系统快捷键或权限。

固定参考提交：[`c500294bdb01186011a5c64a412b04cef9931bef`](https://github.com/lwouis/alt-tab-macos/tree/c500294bdb01186011a5c64a412b04cef9931bef)，提交日期 2026-10-23，提交消息标注发布 11.10.1。以下源码链接固定到此提交，避免后续仓库变化导致结论无法复核。

当前代码包含针对 macOS 26.5、26.6、27 等系统的实测注释；这些不是 macOS 27 的兼容证据。源码注释中的平台结论均按“参考项目观察”处理，需要在目标系统和目标应用上复现。

仓库标注 GPL-3.0。本阶段参考 API、结构与问题分析，不将其实现代码、资源或 vendor 目录复制到 ZeroTab；若以后需要直接复用源码，单独确定许可证与发布方式。

## 2. 研究结论

### 2.1 键盘：触发与松键是两条事件路径

AltTab 的 [`KeyboardEvents.swift`](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/events/KeyboardEvents.swift) 使用 Carbon `RegisterEventHotKey` 接收全局组合键，使用被动 CGEvent tap 观察 `flagsChanged` 等事件，并用本地事件监视器处理面板键盘事件。Esc 另有会话期间才启用的主动 HID tap，以处理系统抢先消费 Esc 的情况。

值得采用的原则：触发、导航、松键提交分别建模；事件回调只收集最少信息，不能执行阻塞的 AX 查询。快速按下并松开时，需保留事件顺序，避免主线程繁忙导致“开始事件晚到、释放事件先处理”而使面板卡住。输入法、安全输入、睡眠唤醒和 tap 被禁用均纳入验证。

### 2.2 系统 ⌘ Tab：普通全局热键不一定能抢到

[`NativeHotkeyResolverSpecs.md`](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/preferences/settings-window/tabs/controls/NativeHotkeyResolverSpecs.md) 记录：原生 `⌘ Tab`／`⌘ Shift Tab` 在 Carbon 应用热键之前被 Dock／WindowServer 消费。AltTab 用 `CGSSetSymbolicHotKeyEnabled` 关闭相应 symbolic hotkeys，再接收 Carbon 热键。

其 [`SkyLight.framework.swift`](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/macos/api-wrappers/SkyLight.framework.swift) 明确注明该开关会在退出后保留；`App.swift` 和 `main.swift` 因而提供正常退出及部分异常退出恢复。这些回调不能覆盖强制终止、进程被杀等所有情况。

ZeroTab 决策：先验证公开 CGEvent 主动过滤 tap 能否在 macOS 27 上抢先消费所需按键，同时保持系统 symbolic hotkeys 原状态。此方案目前是假设，不能仅因 API 存在就视为可行。若不能满足，才评估 AltTab 路径及独立恢复机制；增加辅助进程意味着额外常驻成本，必须实测。不得以“退出时重新启用”宣称崩溃后一定恢复，也不得直接改写用户全局快捷键偏好作为默认实现。

### 2.3 窗口需要结合语义信息与物理信息

AltTab 的 [`windowserver/README.md`](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/windowserver/README.md) 区分：

- AX：用户可读标题、窗口角色、应用内部聚焦窗口、窗口操作。
- WindowServer：窗口存在、层级、空间归属等物理状态。
- 注意力／最近使用模型：根据已确认焦点更新，不能把 z-order 变化直接当成用户切换。

ZeroTab 使用同样的信息边界，但先从小型 AX 服务和按需窗口查询开始，不照搬完整 WindowServer 事件系统。AX 查询失败应记为“未知／无响应”，不是空窗口列表，更不能据此自动创建新窗口。

### 2.4 跨桌面：获取窗口列表和获得可操作 AX 元素是两件事

[`Spaces.swift`](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/switcher/state/Spaces.swift) 使用 `CGSCopyManagedDisplaySpaces`、`CGSManagedDisplayGetCurrentSpace` 获取空间拓扑，并结合每空间窗口列表建立窗口与空间的对应关系。相关封装还声明 `CGSCopySpacesForWindows`。这些是非公开接口。

[`WindowElementAcquisition.swift`](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/windowserver/WindowElementAcquisition.swift) 则处理窗口 ID 到可操作 AX 元素的对应问题。普通 AX 列表可能遗漏其他空间窗口；参考实现先合并 windows、focusedWindow 和 mainWindow，再对遗漏部分尝试非公开 remote-token 枚举。

ZeroTab 建议：

1. 先在 27.0 验证 AX 实际覆盖范围，并缓存通知提供的窗口元素。
2. 空间归属服务预留公开方案及私有桥接的边界；若公开方案无法证明归属，展示状态只能是未知，不能猜成其他桌面。
3. 若确需私有 CGS 查询，用最小独立封装按需读取空间与窗口映射，不直接导入全部接口。
4. 初始方案不默认实现 remote-token 扫描。后续 Chrome 实测出现明确缺口，用户已追加允许有预算上限的句柄发现；当前实现及预算见第 6 节。
5. 不通过切换桌面来“发现”窗口；浏览列表阶段必须保持桌面和焦点不变。

### 2.5 精确激活：activate 应用与让指定窗口接收键盘输入不同

[`Window.swift`](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/switcher/state/Window.swift) 的窗口聚焦路径包含恢复最小化、`_SLPSSetFrontProcessWithOptions`、通过 `SLPSPostEventRecordTo` 构造 make-key 事件、AX raise，以及跨空间的原空间前台状态修复。其复杂程度说明单次 `activate` 调用不能代表“指定窗口已可操作”。

ZeroTab 先验证公开激活与 AX raise／focus 组合；提交后核对前台进程和实际聚焦窗口。失败才分析私有激活路径，不能把 AltTab 的全部步骤无条件照搬。激活请求带代次：用户连续提交新目标时，过期操作不得在稍后把焦点抢回。

### 2.6 无窗口应用：有可参考的公开入口

同一 `Window.swift` 对 windowless app 使用 `NSWorkspace.openApplication(at:configuration:completionHandler:)`，失败时退回应用激活。ZeroTab 可先验证这条公开路径的 reopen 效果，但必须额外检查目标是否真的出现可操作窗口，不能把回调成功当作创建窗口成功。

访达、Chrome、微信、WPS 分别记录：原来确实无窗口、重新打开后出现何种窗口、耗时、是否重复创建。窗口查询未知时不走新建。

### 2.7 面板与性能

[`TilesPanel.swift`](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/switcher/main-window/TilesPanel.swift) 使用 `.nonactivatingPanel` 的 `NSPanel`，避免将切换器作为普通应用激活。非激活面板仍可成为 key window，因此“不激活工具进程”和“不影响键盘事件路由”需要分别验证。

[`AXCallScheduler.swift`](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/macos/AXCallScheduler.swift) 为阻塞 AX IPC 设置并发限额、单进程限额和超时重试隔离。ZeroTab 采用这些原则，先做更小的有界队列及请求合并；不照搬其线程池宽度、超时时间或定时全量扫描。

## 3. ZeroTab 推荐结构

| 模块 | 职责 | 边界 |
| --- | --- | --- |
| InputService | 接收触发、导航、修饰键释放及取消 | 不枚举窗口，不做 UI 布局，不默认改系统热键状态 |
| ApplicationCatalog | 运行中应用及应用最近使用记录 | 包含无窗口应用；按进程生命周期识别对象 |
| WindowCatalog | 按应用查询窗口、接收 AX 通知、缓存标题及状态 | 未知与不存在分开；优先刷新前台及目标应用 |
| SpaceProvider | 可见空间集合、窗口空间归属 | 集中隔离私有接口；结果可为未知或多个空间 |
| SwitchSession | 快照、分组、选中项、方向键及提交／取消 | 纯逻辑；应用模式与窗口模式共用会话框架 |
| ApplicationOpener | 应用级原生打开／重新打开与前台核对 | 无窗口目录依赖，不做按应用适配 |
| ActivationService | 指定窗口的恢复、聚焦与结果核对 | 无应用重开入口，新请求取消过期操作 |
| SwitcherPanelController | 非激活面板生命周期及当前屏幕定位 | AppKit 小范围桥接；内容采用原生 SwiftUI |
| PreferencesStore / Settings | 原生设置、持久化、Dock／菜单栏入口 | 不把底层 API 细节塞给用户 |

数据模型保留：进程代次、窗口身份、标题、最小化状态、空间集合、最近一次确认焦点序号、元数据可信状态。窗口身份不能只用标题，空间不能只用一个“当前／其他”的布尔值，UI 分组由原始事实派生。

事件路径：系统输入 → InputService → SwitchSession → 面板高亮；松键提交 → 按模式进入 ApplicationOpener／ActivationService → 前台／窗口焦点确认 → 最近使用记录。面板高亮变化不写入最近使用记录。启动前历史不可还原时，保留当前应用优先及稳定次序，逐渐建立真实历史。

## 4. 轻量化方案

- 使用原生 SwiftUI 设置及系统框架，AppKit 只负责平台所需边界。
- 不引入 AltTab 的截图采集、预览、搜索、商业化、更新器或统计子系统。
- 初始化只做必要枚举；应用激活／退出与窗口通知驱动更新，触发选择时按需校验。
- 窗口标题与 AX 元素主要按应用惰性获取，进程退出即回收；图标缓存有容量限制。
- 阻塞 IPC 离开主线程，设置有限并发、超时及合并；不能用不断新建线程掩盖阻塞。
- 不保证“无缩略图就一定不需要屏幕录制权限”。标题优先从 AX 获取；窗口元数据的实际权限限制在 27.0 验证，缺权限不应诱发隐式截图或反复系统弹窗。
- 核心切换无需网络服务。性能以 Release 实测为准，不根据删掉多少模块推算内存数字。

## 5. 实现顺序与完成条件

| 阶段 | 工作 | 完成条件 |
| --- | --- | --- |
| P0：平台验证 | 最小原生 App、权限状态、键盘接管实验、窗口与空间元数据探针、激活及 reopen 验证 | 输出 27.0 实测矩阵，明确公开 API 的缺口及是否需要私有桥接 |
| P1：可用切换闭环 | 应用目录、窗口目录、状态机、简单文字面板、松键提交与 Esc、四个目标应用适配 | 两组快捷键可用；跨桌面、恢复及无窗口场景有实际结果；已确认技术取舍 |
| P2：正式界面与设置 | 毛玻璃面板、图标缩小／换行、网格导航、标题滚动、原生设置、Dock／菜单栏与开机启动 | Design.md 的视觉及生命周期规则可交互验收 |
| P3：资源与稳定性 | Release 测量、输入法／快速操作／睡眠唤醒、失效目标、多显示器、权限变更 | 提交实测性能与兼容记录，关键故障有恢复方式 |

P0 期间可先完整验证 `⌥ Tab`，同时验证 `⌘ Tab` 接管，避免为系统热键取舍阻塞其他能力研究。平台探针仅在用户实际触发时执行聚焦／reopen，不自动操作现有工作窗口，不关闭或移动用户窗口。

实际采用 SwiftPM 原生 executable 与独立纯逻辑测试 target，脚本打包为真正的 `.app`，目标系统 27.0，固定 bundle ID `dev.hitomeng.ZeroTab`。无需工程生成器或第三方依赖；可用 Xcode 打开 `Package.swift` 编辑。

## 6. 私有接口的决策点

### 本轮公开 API 实测更新

macOS 27.2 上，用户以实体键盘确认 `⌘ Tab` 与 `⌥ Tab` 两组都能显示并切换；当前构建自身日志同时记录了 `applications`、`windows` 两种触发及目标窗口焦点确认。因此当前系统无需为了这两组基础快捷键关闭系统 symbolic hotkeys。自动化工具发送的按键未进入该全局监听，不能把那次无反应作为方案失败证据。

剩余明确缺口是空间归属：当前 `SpaceProvider` 只能输出已匹配的当前可见或未知，不能输出经过证明的“其他桌面”，所以完整的跨桌面标记与后置尚未实现。

### 已获用户确认的最小只读桥接范围

用户已于本轮明确允许“最小只读桥接，继续完成跨桌面归属”。已在 `ReadOnlySpaceBridge.swift` 集中实现以下窗口 ID 与空间查询：

1. `_AXUIElementGetWindow`：把已有 AX 窗口元素映射到真实 WindowServer window ID，避免依赖标题／坐标猜测。
2. `CGSMainConnectionID`：获取本进程用于查询的 WindowServer connection。
3. `CGSCopyManagedDisplaySpaces`：查询显示器的当前空间与空间拓扑。
4. `CGSCopySpacesForWindows`：查询指定窗口的空间集合，与各显示器当前可见空间取交集，确定当前／其他。

这些查询不截屏、不移动窗口、不切换桌面、不修改系统热键。接口集中到一个可选桥接模块，动态查找符号，未找到或查询失败时保留未知；处理窗口属于多个空间的情况，不把空返回当作不存在。

维护风险是未公开 ABI 与返回结构可能随系统升级改变，需要按系统版本与真实窗口状态回归。此范围不包含 remote-token 暴力枚举或私有聚焦操作；若后续证明仍有跨空间窗口遗漏，再单独说明缺口。它能补足已取得窗口的空间归属，不能单凭这四个接口承诺完整枚举所有其他空间窗口。

第一次授权仅覆盖以上四个只读接口；随后追加的句柄发现授权见下一节。两次授权均不包括私有聚焦或系统热键开关。

### Chrome 冷启动跨桌面发现缺口与已获确认方案

用户实测：同桌面 Chrome 切换经真实窗口 ID 修正后可用；其他桌面窗口在手动访问那个桌面后才出现。这证实已取得窗口的空间查询与聚焦可工作，但 AX 初始窗口列表遗漏尚未观察到的其他空间窗口。

公开 `CGWindowListCopyWindowInfo(.optionAll)` 配合已授权的空间查询能发现 Chrome 的其他空间物理窗口；本机探针过滤透明及极小辅助表面后仍可找到其他空间候选。物理表面不一定就是可操作的用户窗口，不能直接把所有表面加入 UI。

用户随后明确允许“继续补齐冷启动窗口发现”，已独立加入 `_AXUIElementCreateWithRemoteToken`：按进程的 AX 元素 ID 查找句柄，用已有 `_AXUIElementGetWindow` 与缺失物理窗口 ID 匹配，并仅接纳角色为 AXWindow 的根元素。它是逐 ID 枚举，不能包装成无成本查询；不遍历网页内容，不截屏，也不访问其他应用的文档内容。

实现边界：每个补查轮次采用 120 ms 预算，单个元素的消息超时设为 10 ms；在途系统调用可能使实际轮次略超预算，日志记录实际时间。按进程保存扫描游标和已取得元素，只查缺失集合；初次短期补查最多 8 轮、自动轮次间至少 250 ms，达到预算后停止自动补查，避免空闲常驻扫描。授权后先为已运行的 Chrome、访达、微信、WPS 建立窗口缓存；目标集合有新增或实际窗口查询时可继续。匹配成功立即停止该目标的查找。未找到不能作为窗口不存在的证据。

新增授权范围仅限这个句柄构造入口，不包含私有聚焦和系统热键开关。需要实测首次发现时延、CPU 及内存；若特定应用的元素 ID 稀疏且很大，有限枚举仍可能不能完整覆盖，必须如实报告。游标、预算与 token 编码有独立测试，真实发现结果以 Validation.md 为准。

### 已完成的回归修正

- Chrome 同桌面选择与核对统一按真实 WindowServer ID 去重和匹配，公开聚焦顺序调整后用户确认可用；未增加私有聚焦。
- 标记从泛称“其他桌面”改为按拓扑顺序生成的桌面编号；多显示器与全屏空间分别标注，不暴露内部 ID。
- 受限补发现解决未访问过的其他桌面 Chrome 窗口缺失；用户复测确认冷启动可列出并跳转。
- 补发现同时暴露的无标题辅助表面由窗口准入策略过滤。Chrome 要求标准窗口角色及非空标题；远端未确认表面同样需要这两项语义证据，普通原生应用自行发布的无标题窗口仍保留。辅助句柄使用有容量上限的缓存，过滤它们不触发反复补查。
- 用户最终确认多余条目消失、真实窗口与跨桌面正常。19 项基础／发现测试加 2 项准入回归测试，共 21 项通过。

### 0.1.1 build 6：应用打开与精确窗口切换分离

按用户确认的路线重构，执行路径以提交模式明确分开：

- `⌘ Tab` → `ApplicationOpener` → 一次 `NSWorkspace.openApplication`，配置激活、复用实例及标准 `aevt/rapp` 事件。该服务不依赖 AX、窗口目录或桌面查询，不读取窗口清单，也不指定焦点窗口。
- 系统和目标应用负责恢复已有界面或创建默认窗口。后续最多四次、每次间隔 250 ms 只读核对前台进程，不重发打开请求；前台确认不代表窗口已创建。新的快捷键会话取消过期回调。
- `⌥ Tab` → `WindowCatalog` → 仅已有窗口的排序与选择 → `ActivationService` 精确恢复／聚焦。该服务没有应用重开入口；空清单、查询失败和失效目标均不新建。
- 删除 `ApplicationPolicy`、重开白名单、`WindowInventory.mayReopenWhenEmpty`、未解析物理窗口的重开阻断判断，以及空窗口选择转入重开的回退。
- 窗口准入不再检查 bundle ID。由 `kAXWindows` 实际发布的窗口保留无标题和普通对话框；焦点／主窗口提示、历史缓存及远端句柄作为补充来源时，要求有标题的标准窗口证据。发布集合仅来自原始 `kAXWindows`，不再混入提示句柄。
- 删除按应用列表预热；前台应用仍按激活／焦点事件为窗口切换更新缓存，保留受限跨桌面发现和全部既有预算。
- 删除四项已废弃的应用白名单测试，更新两项通用准入回归，保留窗口可见性、导航、桌面归属及发现预算测试；当前 26 项通过。真实快捷键行为以本构建验收为准。
- 本构建用户实体键盘验收通过：访达无窗口时的原生恢复与前台焦点，以及 Chrome 同桌面／跨桌面窗口条目、精确切换及焦点。运行日志同时记录访达原生打开与前台确认、Chrome 目标窗口焦点确认；详细证据与尚未覆盖状态见 Validation.md。

### 0.1.1 build 2–5 恢复探索记录（恢复策略已由 build 6 替代）

0.1.0 基线已提交为 `718c5eb`。后续用户报告微信无窗口恢复失败；在微信 4.1.15 上使用关闭按钮复现后，观察到主窗口的 WindowServer 对象仍保留，仍属于当前桌面，但 `onScreen=false`，应用未隐藏。仅按 AX 对象存在与焦点 ID 判断，会把未显示的窗口当成可操作窗口。

修正将窗口清单与重开许可分开：

- AX 属性查询失败仍返回不可用，不能据此重新打开。
- 已知当前桌面、明确不在屏幕上、明确非最小化且应用未隐藏的窗口，记为未显示，不参与切换。窗口已知不属于任何空间且不在屏幕上的状态也同样处理；查询失败产生的未知状态不作此推断。
- 最小化、隐藏及其他桌面的窗口继续保留；已确认的其他桌面状态不会被矛盾的空空间信号覆盖。
- 微信辅助表面采用与 Chrome 相同的有标题标准窗口准入。空清单且残留未知物理表面时，由集中应用策略决定是否允许主窗口原生重开；微信与后续验证的钉钉在此列表中，其他应用保持保守判断。
- 重新打开通过公开的 `NSWorkspace.OpenConfiguration.appleEvent` 明确发送 `aevt/rapp`，不新建进程、不发送新文稿快捷键；随后重新查询可用窗口并激活、核对焦点及显示状态。
- 同一次查询复用一份公开 WindowServer 快照，减少重复枚举。未增加私有接口。

新增 6 项恢复回归测试，总计 27 项逻辑测试通过；实机结果记录于 Validation.md。

微信在 build 2 已获用户实体键盘确认恢复。钉钉 9.0.2 随后复现另一种拦截：AX 可用清单为空，主窗口及辅助 WindowServer 表面仍保留，导致 `emptyReopenAllowed=false`。原生重开能恢复主界面，build 3 因此将实际 bundle ID `5ZSL2CJU2T.com.dingtalk.mac` 纳入主窗口重开策略。没有对钉钉启用严格的非空标题筛选，以保留无标题文档；AX 查询失败与已有可用窗口仍优先保护。增加 2 项策略回归，合计 29 项测试；未新增私有接口。

build 3 用户确认钉钉可恢复，但从钉钉切换到其他 App 时面板正常、实际前台不变。日志在恢复前后都出现 `front=false`，所以不能直接归因于重开回调。build 4 在窗口聚焦流程中加入公开的应用级 `kAXFrontmostAttribute` 请求；ZeroTab 为活动应用时先 `yieldActivation(to:)`。记录 AppKit 激活返回值、AX 前台返回码及目标进程，仍以实际前台与窗口身份、显示状态核对成功。此候选未扩大私有 API 范围，前台交接已在 build 4 获用户确认。

build 4 前台交接已由用户确认通过，随后报告访达全部窗口关闭时不能重建。探针与日志确定这是可见性证据缺失：Finder 保留无桌面归属的辅助表面，其 `kCGWindowIsOnscreen` 可选字段缺失；原有未知状态保护因此阻断空清单重开。build 5 仅在快照出现缺失字段时，追加一次公开 `.optionOnScreenOnly` 元数据查询，以窗口 ID 集合补足可见性。查询失败或 ID 解析不完整时保留未知；不把字段缺失直接当 false。已知隐藏、最小化及其他桌面窗口仍受原有保护。无需新增应用白名单或私有接口。字段定义参见 Apple 的 [Optional Window List Keys](https://developer.apple.com/documentation/coregraphics/optional-window-list-keys)。

- 空间查询：实测公开方案缺口后，列出需要的最小 CGS 接口及适用范围。
- 精确激活：先测 AX 与公开应用激活组合，再决定是否需要 `_SLPS…`／事件记录路径。
- 系统热键开关：优先级最低，先测无持久状态改动的拦截；确需使用时必须带正常退出、暂停、权限失效及异常终止的恢复设计。
- 所有非公开入口隔离在单独模块，检查符号及系统版本；不可用时不崩溃或吞键，并明确报告功能限制。

若采用私有接口影响分发方式，正式发布前另行验证签名、公证及渠道约束。当前不承诺 Mac App Store 分发，也不因引用 AltTab 就继承其 entitlements。

基础两组切换已由用户实体键盘与应用日志共同验证；只读桥接的具体系统结果及剩余兼容性以 Validation.md 的实测记录为准。
