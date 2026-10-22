# SwiftUI 采集等待期间的窗口失效验收

日期：2026-10-22。结论：已在真实 Runtime → Host → MCP 链路验证，所选窗口在 AX 就绪等待期间被移除时返回 `inspection.contextChanged`，不返回成功快照；本项不需要产品补丁。

## 范围与产物

- 延续[常用控件与动态场景验收](2026-10-22-swiftui-controls-and-dynamic.md)，补齐原计划中等待后重查上下文的运行证据，不扩大 SwiftUI 样式支持范围。
- Runtime `develop` / `db429f060ef1d9976bf9fb40a2b1f4e238779577`；Host `develop` / `b4e13a572614dc0ed5afc86e6d0ba59aa06c6dbd`。本次只新增验收文档，产品源码及 Protocol 未改。
- iPhone 18 Pro Simulator / iOS 27.0，设备 `CD6AFF4C-3BD7-4DA5-AC90-7C3B542CDF47`；有效竞态验证进程 `65398`，Runtime arm64 UUID `CB87EFB1-EF3C-3F0F-B23E-6FE4F94ECBDF`。
- 使用源码 CLI 和真实 MCP SDK stdio，工具数仍为 23。未更改 Homebrew 安装、全局环境或 MCP 配置；未操作真机或其他 App。

## 触发方法

仅在开发者授权的专用 Demo 中，由宿主调试器创建一个无 root controller、无语义内容的临时普通窗口。正式 `inspect_screen` 显式选择其 `windowID=252`，避免按窗口顺序猜测目标。

在 `UIKitRuntimeSemanticInspectionProvider.swift:55` 的真实 `Task.sleep` 前设置一次性断点，以 Foundation 的延迟 selector 调用公开 `UIWindow.windowScene` setter，在 20 ms 后将临时窗口移出 scene；继续执行。第二个一次性断点位于 `:56`，即等待结束、`validate(context)` 前。

日志确认第一次命中时只为一个临时窗口安排移除；第二次命中时 scene 窗口数已由 2 变为 1。随后脱离调试器，由未修改的 Runtime 完成校验并通过 Host/MCP 返回错误。宿主夹具不进入 SDK，Runtime 不包含导航、变更窗口或调试开关。

## 结果

| 场景 | 实际结果 |
| --- | --- |
| 未指定目标，两个普通窗口 | `astrolabe_runtime_inspection.targetAmbiguous`，包含两个 typed window 候选 |
| 显式选择稳定空窗口 | 请求成功，但语义 `availability=unavailable` / `ios.swiftui.treeUnavailable`；不把空窗口当作 SwiftUI 页面采集成功 |
| 所选窗口在实际等待期间移出 scene | `success=false`，`errorCode=astrolabe_runtime_inspection.contextChanged`；错误 envelope 不含 `data` 或成功快照 ID |
| 再次指定已移除的 `252` | `astrolabe_runtime_inspection.targetUnavailable`；候选只剩主窗口 `1`，不悄悄改查主窗口 |
| 重新采集主窗口 | 成功，91 个语义节点，`availability=partial`；既有样式缺失仍保留，不宣称 complete |

稳定空窗口 Host snapshot 为 `B92AAE98-5671-47E3-B677-C1ADF2DEAFAE`。恢复主窗口的 Host snapshot 为 `99EE35A0-F282-4FDB-8577-DB1BB4C13838`，对应 Runtime snapshot `5684FE31-8091-489A-91AE-EC2309ABBB25`。这些是进程 `65398` 的历史证据，不能在重启后复用。

`context-verify.mjs` 对实际 MCP JSON、目标清单、错误 envelope、两处断点日志及恢复快照执行证据断言，exit 0。预期错误请求自身 exit 1，不将其记作请求成功；断言通过的是错误处理符合契约。

## 失败尝试与边界

此前三个宿主 Swift 表达式尝试未可靠触发窗口变更：跨调试器会话的持久变量不可见；临时字符串标记在脱离会话后读值异常；异步 Swift 表达式执行出现 `EXC_BAD_ACCESS`，调试器将目标恢复到求值前状态。它们返回的成功快照不作为竞态通过证据，也不据此归因于 Runtime。本记录的结论只依赖后续公开 selector 路径和对应断点日志；没有声称修复 LLDB 或定位这些宿主异常的完整根因。

原始证据与失败日志在 `/tmp/astrolabe-swiftui-phase2-20261022.RqB6Lk/context-*`，临时文件可能被系统清理。收尾移除临时窗口、恢复主窗口，并重新启动同一 Demo，清除宿主夹具和调试器临时状态；重启后的身份需重新发现和采集。

收尾重新发现为 `compatible`；新进程 `75788` 的实际 MCP 采集成功，仍为主窗口 `1`、91 个语义节点，保持 App 前台。不复用进程 `65398` 的 appId 或快照作为收尾证据。

本次证明的是已选窗口在等待期间被移除的路径，不代表穷尽所有窗口几何、方向、scene 切换、取消或多请求竞态。未验证真机和其他 iOS 版本；继承文字颜色、富文本逐 run、完整可见/遮挡树仍不在已支持范围。
