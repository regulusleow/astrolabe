# SwiftUI 第二阶段：常用控件与动态场景验收

日期：2026-10-22。结论：本阶段限定的控件角色、冻结 AX 详情及动态场景验证已完成；不是完整 SwiftUI 视图树或视觉属性支持声明。

## 范围与代码状态

延续首个语义检查产品切片，使用既有 Protocol → iOS Runtime → Host/CLI/MCP 链路。两消费者更新 Protocol pin，Runtime 增加公开角色与冻结 AX/control/scroll 详情，Host 增加纯消费者回归。没有新增 Wire 字段、MCP 工具、UI 单测、业务埋点或兼容层。

| 工程 | 验收时基线与状态 |
| --- | --- |
| Host | `develop` / `65e0b24ca249c681f04afdd4abd4b160b5beb2cd`，在此基线上验收切片改动 |
| iOS Runtime | `develop` / `96d6be2a6c49da276e7945fd6e9a0436e3949288`，在此基线上验收切片改动 |
| Protocol | `develop` / `d6315b254cee98712fd7238069118290a379dd6a`，无本轮改动；两个消费者 pin 到该 SHA |
| Android Runtime | 无本轮改动 |
| Demo | `feat/swiftui-capture` / `94a35d9a5689fb1b696d571f906fa2167d75c1c1`；保留既有 README、handoff 改动，未修改源码或工程文件 |

本次续接补齐前轮未完成的运行验收，没有因宿主调试表达式失败追加产品补丁。验收后按开发者要求，在 `develop` 提交 Runtime `db429f060ef1d9976bf9fb40a2b1f4e238779577` 与 Host `b4e13a572614dc0ed5afc86e6d0ba59aa06c6dbd`；未推送、创建 PR、合并或发布。

## 设计边界：复用策略，分离事实与读取

- **纯值投影**：`UIKitSemanticAccessibilityFacts` 只依赖 Protocol DTO，负责角色优先级与已脱敏 AX 属性投影；不依赖 UIKit、不读取活对象、不从文案猜类型，也不拿 Text 候选补 value。
- **同步采集与编排**：`UIKitSemanticAccessibilityCollector` 读取公开 traits，并以真实 UIKit `is/as` 类型证据提供 native role。只有 AX 对象本身是本次 render roots 中同一个 UIView，才复用现有 `UIKitRuntimeAttributeCollectorRegistry` 的 control/scroll 策略。不会把邻近原生 View 的属性嫁接给 SwiftUI AX 代理。
- **冻结与消费**：既有 typed snapshot store 保存纯值，详情不能回退读取当前活对象。Host 继续消费现有属性与角色，不增加平台专用推断分支。
- **扩展方式**：有真实对象身份时复用现有 collector；只获得 AX 代理时只输出可证明的公开语义。没有为未来控件引入额外接口、继承层或配置。

新增详情沿用既有预算与隐私门：AX 深度 20、最多 2,000 次访问、500 个带语义内容节点、4 MiB 捕获与详情上限。公开 AX 元数据与原始 Text 候选仍分开；`partial` 不等于每个已知属性都不可用，但候选、缺失或歧义不能提升为样式事实。

## 运行环境与身份

- iPhone 18 Pro Simulator，iOS 27.0；设备 `CD6AFF4C-3BD7-4DA5-AC90-7C3B542CDF47`。
- 本次重新构建并安装专用 `SwiftUIInspectorTest` Demo，不带其旧 Inspector 捕获参数。
- Runtime arm64 UUID：`CB87EFB1-EF3C-3F0F-B23E-6FE4F94ECBDF`。
- 有效验证进程：`57466`；Runtime instance `3D3ACD4D-0A1F-4C62-9DEC-63DEB1232565`，loopback `47200`。下表均对应此进程和产物，不混用前轮证据。
- 实际使用源码 `.build/debug/astrolabe` 与 `mcp-adapter/dist/index.js`，独立 MCP SDK stdio 连接；工具数仍为 23。
- Runtime 通过单次 `simctl launch` 环境注入，不修改 Homebrew 安装、MCP 配置或全局注入设置。页面准备只作用于用户授权的专用 Demo，不操作真机或 Litmatch。

首次 launch 返回的 `56724` 未加载新 Runtime，不计入验证；显式 `--terminate-running-process` 后已确认新进程的 Runtime image、注入路径和监听端口。App 启动成功本身不是 Runtime 就绪证明，仍以重新发现 compatible 和实际语义捕获为准。

## 实际验收

| 场景 | 实测结果与边界 |
| --- | --- |
| 基础控件角色 | 输入框为 `input`；“允许交互”为 `control`，公开 traits 包含 `button`、`toggleButton`；能查询 `image` 角色。`adjustable` 只证明通用 control，不宣称 Slider 专用支持 |
| Toggle 与禁用态 | Toggle 新快照 value `1 → 0`，旧 A 首次详情仍为 `1` / `runtimeSnapshot`；新值 `0` 的 `check_node_detail` 通过；按钮公开 AX traits 出现 `notEnabled` |
| 普通输入 | 标准输入操作后新值为 `Astrolabe phase2`，旧 A 首次详情仍为 `SwiftUI` / `runtimeSnapshot` |
| List 中部 | 实际滚到索引 80，截图及 AX 包含项目 81–88；同一集合视图的新冻结 offset 为 `{x:0,y:4496.666666666667}`，旧顶部快照首次 `inspect_node` 仍为 `{x:0,y:0}` |
| List 恢复与删除 | 恢复顶部新 offset 为 0；删除首项后标题由 200 项变为 199 项，新 AX 中项目 1 消失并出现项目 9。仍可能保留此前缓存的中部行，不据此宣称完整可见行集合 |
| Lazy | 新快照 offset `0 → 1600 → 0`；滚动后首次读取旧 top 详情仍为 0 / `runtimeSnapshot`；中部 AX 行集合更新，仍受懒加载/缓存影响 |
| Sheet | 关闭时无“当前浮层内容”，打开后出现，关闭后消失；打开时底页文字仍在 AX 树，不能据此推断无遮挡或可点击 |
| Dynamic Type | 正文 `.body` 的 canonical 字号 `17 → 23 → 17 scaledLogical`；固定标题始终为 28；放大后首次读取旧正文详情仍为 17；字号 23 的实际 MCP `check_style` 通过 |
| 深浅色与缺失样式 | 深色下正文 17、固定标题 28；继承红色文本在深/浅色都未伪造 canonical textColor。富文本字号 21 断言返回 `passed=false`、`verification=unableToVerify`，不把候选当整段统一字号 |
| 非空安全输入 | 宿主标准输入填入非空假密码后，保存并检查同次 Host 完整 hierarchy，而非默认 25 节点投影：原生/语义节点 AX value 数量均为 0，假密码不在输出中 |
| 离页后的安全冻结详情 | 关闭安全输入并离开样式页后，首次检查两份 input 和一份原样 Text 的旧详情：均为原 runtime snapshot，无 AX value、common.text 属性、Text 候选或假密码。非敏感 AX label/traits 允许保留，不再沿用首版“全部属性组为 0”的旧断言 |

安全输入的 `secureInputContext` 出现在捕获诊断及禁止 Text 投影的 SwiftUI AX Text 详情中。普通原生输入节点没有走私有 Text 投影，不能要求它也携带 SwiftUI 专属 Text issue；其 AX value 仍须省略。未将“所有详情具有同一 issue”作为安全条件。

### 关键快照身份

| 场景 | Host snapshotId | Runtime snapshotId |
| --- | --- | --- |
| List 顶部 | `1E2E4B81-8A33-41E2-BA3B-A5090FE8B6F2` | `5594D996-652C-44ED-920A-6F0C7C549A2F` |
| List 中部 | `EBE6F8D3-8023-47AE-854E-8CD7991CBADF` | `B724E078-393B-46D8-A40F-87BC0EE1083D` |
| Lazy 顶部 | `E969C84F-D192-4842-AD91-CB49D24B1FD0` | `22155539-79C7-4FD6-93FB-583A75C6D173` |
| Lazy 中部 | `7C94C65A-4F94-48BC-B549-AD3B6372E787` | `4CA24DD0-15B5-48E4-8DC3-60451DFF5029` |
| 安全输入 | `D38B3A4E-A877-4F88-8160-4CCD094BF1AE` | `F6DC993E-1666-447C-BD6C-AB08A860B235` |

这些 ID 是历史证据，不应在 App 重启后当作当前检查上下文；Host 与 Runtime ID 也不能混用。

## 宿主驱动与失败记录

前轮及本轮 ObjC++ LLDB 几何表达式设置 offset 未生效；最小 CGPoint 表达式还触发了宿主 LLDB 编译器崩溃，Demo 进程未因此崩溃。本轮采用集合视图公开的 [scrollToItem](https://developer.apple.com/documentation/uikit/uicollectionview/scrolltoitem(at:at:animated:)) 完成 List 准备，Swift LLDB 表达式调用公开的 [setContentOffset](https://developer.apple.com/documentation/uikit/uiscrollview/setcontentoffset(_:animated:)) 完成 Lazy 准备，并以实际 capture 验证结果。

这些变化仅在临时宿主驱动，不进入产品 Runtime。未宣称已定位或修复 LLDB 本身的编译/ABI 问题，也不根据失败宿主操作推断 Runtime 故障。

保留失败的构建/脚本日志：初次 Runtime scheme 名称错误，查询实际 `astrolabe-runtime-ios` scheme 后重建通过；旧动态脚本在 Lazy 宿主操作未生效处失败；安全脚本最初误要求原生节点具有 SwiftUI Text issue，按上述边界修正验证条件后通过。没有删除失败证据或把其 exit code 记为通过。

## 新门禁与收尾

- 提交前重新运行：Runtime `swift test` 共 56 项通过；Host `swift test` 共 293 项通过；MCP `npm test` 为 44 passed / 0 failed。Host 按全部 test runner 的总计汇总，修正此前漏计 4 项的 289；原始证据为 `precommit-*-tests.log`。
- Host `swift build`、MCP build/typecheck、Runtime Simulator framework build、Demo build 均 exit 0。Runtime build 保留既有 `Supported platforms for the buildables in the current scheme is empty` 提示，不宣称无警告。
- 真实 MCP 场景断言及最终证据交叉校验通过。富文本的 `unableToVerify` 是预期能力边界，不计作样式匹配通过。
- 独立只读源码审查：Critical 0 / Important 0 / Minor 0，覆盖纯投影、对象身份、隐私门、预算、冻结存储及 Host consumer；动态运行证据由主执行者验证，不以代码审查替代。
- 深浅色和字号设置已恢复为初始 `light` / `large`。收尾重新启动同一 Demo，使临时输入、Toggle、删除状态复位；保持 App 前台。新进程需重新发现，不复用上述 appId/快照。

原始 JSON、截图、日志和宿主驱动在 `/tmp/astrolabe-swiftui-phase2-20261022.RqB6Lk`。包括 `list-*.json`、`lazy-fresh-*`、`sheet-*`、`style-*`、`secure-*`、`controls-*`、`*-acceptance-summary.json`、`code-review.md` 和各新门禁日志。临时目录可能被系统清理，本记录保留关键环境、数字、身份和复验边界；不把宿主脚本作为 SDK 分发内容。

剩余边界：未验证真机、其他 iOS 版本、全部 SwiftUI 控件或性能矩阵；不支持完整声明树、完整可见/遮挡树、富文本逐 run、继承颜色及最终像素样式还原。不能从 `adjustable` 推断 Slider。未加入 `_viewDebugData` / AttributeGraph、Mach-O、RemoteMirror 或业务对象图递归。

[Android 接入导致整体发现超时](../issues/2026-10-19-android-discovery-blocks-mcp-list-apps.md) 仍是独立待排查问题，本轮没有修复或借此修改系统安装。
