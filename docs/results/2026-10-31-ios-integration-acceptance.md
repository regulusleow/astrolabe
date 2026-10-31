# iOS、Host 与 Protocol 联调验收

日期：2026-10-31。本轮完成依赖安全修复、MCP 校验迁移和模拟器 CI 修复，并验证真机与模拟器同时发现、语义快照隔离、只读重复采集和真机安全输入。SwiftUI 私有解析仍遵守既定平台限制，不能将这些结果解释为 iOS 27.2 已支持完整 SwiftUI 文本检查。

## 范围与实现

- Host 基线 `3d534812a62fa2739b71a6f773e824df10ef2b79`，修复提交 `bf2a2de`：`fix(mcp): update vulnerable validation dependencies`。
- iOS Runtime 基线 `3c6b7c672c602d1db7a2d7d8f5f2a5f2bc54d3df`，CI 修复提交 `05ecde7`：`fix(ci): select devices supported by the simulator runtime`。
- Protocol 为 `8893e2da3247e0d7e8dfb060156f5d42fb9f75d1`，本轮没有契约变更。
- 用户明确将 Android Runtime 开发排除在本轮之外。先前启动的范围外检查已停止，模拟器已关闭，本地 SDK 配置已恢复，Android 源码未改动。

变更位于已有边界：MCP 继续复用共同的快照标识 schema，图查询通过 unwrap 保持必填；环境解析、Runtime 私有 ABI 桥、Wire 字段和投影层保持现有职责。CI 从所选 Runtime 的 supportedDeviceTypes 中选机型，新增 Runtime/机型时沿用同一路径，不维护新的映射表。

## 安全依赖与迁移

初始生产依赖审计为 5 项漏洞（2 high、3 moderate），涉及 Zod、body-parser、ip-address、qs 和 @hono/node-server。直接 Zod 要求更新为 `^4.6.7`；根 workspace 与 standalone Adapter 的锁文件均更新到以下修补版本：

| 依赖 | 锁定版本 |
| --- | --- |
| zod | 4.6.7 |
| @hono/node-server | 2.1.5 |
| body-parser | 2.4.0 |
| ip-address | 10.7.5 |
| qs | 6.17.1 |

MCP SDK 保留 1.32.0，其 peer 要求支持 Zod 4。record 改为显式字符串键；Zod 4 的严格 UUID 校验会拒绝原生 Host 接受的 UUID 形状，现使用 z.guid 对齐原生规则。原有图查询测试和新增公共 schema 回归均实测 RED→GREEN，非 UUID 字符串仍被拒绝。

根目录和 standalone 的生产审计均为零。在独立干净目录再次执行 npm ci、npm ls --omit=dev 和 npm audit --omit=dev，也全部退出 0，依赖树没有 problems。原工作目录先后安装两种布局后存在 extraneous 条目，因此干净安装证据取自 CleanWorkspace/CleanAdapter。两锁原有的 @types/node、express-rate-limit 版本差异保留，未宣称全部依赖版本相同。

这些是本地工作分支结果。GitHub 默认分支告警需代码合入后重新评估，本轮未推送或手动关闭告警。

## 自动化验证

| 仓库/入口 | 结果 |
| --- | --- |
| Host npm test | 根工具 143 项、Adapter 45 项通过 |
| Host Adapter typecheck | 通过 |
| Host swift test --parallel | 289 项通过 |
| Host Debug/Release CLI 构建 | 通过 |
| Protocol npm test | Schema/Fixture、Swift Fixture 与 15 项 Node 检查通过 |
| Protocol swift test --parallel / Release 构建 | 31 项通过，构建成功 |
| iOS npm test | 10 项通过 |
| iOS swift test --parallel / Release 构建 | 69 项通过，构建成功 |
| iOS 完整模拟器测试 | xcresult 确认 134 项通过、0 failed、0 skipped |
| iOS 自动启动 Framework 产物检查 | 动态库及 Bootstrap 符号检查通过 |
| iOS 硬件 Framework / 专用 Demo 构建与签名 | 通过 |

CI 的实际失败是选中最新 iOS 27.1 Runtime 后仍使用全局优先的 iPhone 16 Pro，simctl create 返回 Incompatible device。该 Runtime 仅支持 iPhone Duo。行为回归先复现失败，再验证最新 Runtime 的支持机型、原有兼容机型偏好、构建退出码和设备清理；真实脚本随后在 iOS 27.1 (24A94425) 上跑完 134 项测试，并清理临时 CI 设备。未新增 UI 单元测试。

## 真机与模拟器

采用源码 CLI 与真实 MCP SDK stdio，工具数为 23。先检查 list_apps 的 compatible，再 inspect_screen 确认页面；详情均使用同一 appId/snapshotId/oid。截图与具体 Runtime 快照分别记录时间，截图不宣称与旧快照同步。

| 目标 | 系统 / PID | Host snapshot | Runtime snapshot |
| --- | --- | --- | --- |
| iPhone 16 Pro Max，USB | iOS 27.2 (24B119) / 13824 | 1B94A1CA-C991-4EAE-BC65-71B9D1C8A4E2 | 91F79209-4B57-44B5-95F7-720ADFFE6DF0 |
| iPhone 18 Pro，模拟器 | iOS 27.0 (24A434) / 18078 | 98766426-0B94-4C5C-9BA9-53382613E541 | AB4943E8-8735-4E93-BC13-C2CFBDA8DA83 |

真机安装的是单独签名的 `dev.astrolabe.HardwareAcceptance`，嵌入的硬件 Runtime UUID 为 `D539454E-CD45-33BF-88F6-B32D6CBAE5E3`；此 UUID 来自安装产物检查，不宣称通过设备调试器枚举了已加载映像。普通 Demo 与隐私页均仅在临时产物中准备，原 Demo 源码和既有 README/handoff 改动保留。

- 两端同时可发现，分别绑定 USB/模拟器、正确进程和系统版本。真机返回 346 个总节点、97 个 AX 语义节点；模拟器为 340/91。
- UIKit 输入框当前值 SwiftUI 可读。模拟器的 SwiftUI 标题恢复 28 scaledLogical 字号、Rounded Bold 字体和预期 RGB `[0.17,0.24,0.95,1]`，误差小于 0.00001。
- 每端连续 5 次重新采集后，旧语义节点的完整 detail 仍深度相等，detailSource 始终为 runtimeSnapshot。普通 UIKit 渲染节点首次详情来自 liveRuntime，与语义冻结断言分开记录。
- 交叉使用另一端的快照返回 hierarchy_snapshot_mismatch。符合原生 UUID 形状但不存在的标识进入 Host 后返回 hierarchy_snapshot_expired，未被新的 Adapter 校验提前错误拒绝。
- 真机截图通过 source=physical 与显式设备标识采集，1320×2868 px、440×956 logical、scale 3；已人工查看普通页面。

### 真机覆盖边界

iOS 27.2 上普通 Demo 的 SwiftUI 正文标题未被恢复，按标题查询返回 node_not_found。对确实存在的 AX 语义节点检查缺失字号，结果为 passed=false / unableToVerify。其 AX capture availability=complete 仅表示该来源遍历完成，不表示 SwiftUI Text、字体或颜色完整支持。

因此，本轮没有扩大 iOS 27.0 私有布局及 arm64 模拟器层级计算的支持门限。iOS 27.2 真机的 SwiftUI 正文/样式适配仍是独立待完成项。

### 真机安全输入

在临时 Demo 副本构造安全 UITextField，使用合成值。最终夹具读取 accessibilityIdentifier 时通过 UIKit hasText 动态返回已填/空布尔标识，避免仅凭赋值源码或截图推断输入状态。

最终进程 13895，Host snapshot `FE497C00-EA7C-4D0E-878C-28A5C3F514F9`，Runtime snapshot `B63258F6-8419-45DD-AC50-D0260912CEB1`：实抓标识确认为已填值，isSecureTextEntry=true，文本属性缺失，所有采集和详情响应均不含合成原文。普通 UILabel 仍返回 20 logical 字号和预期 `[0.2,0.3,0.4,1]` 色值。截图已保存，但不据此承诺隐藏输入长度或完整 SwiftUI 安全场景覆盖。

早期夹具没有独立的已填值运行证据，不计为已填安全输入验收；最终结论仅使用上述进程与实时 UIKit 布尔检查。

收尾已回装普通 Demo，重新发现为 compatible，进程变为 13916；新 Host snapshot 为 `1073C5C5-5AF6-4A0B-8326-2445CCF2533C`，Runtime snapshot 为 `69302086-0A85-4ECC-A33A-8A3634E5D04D`。原页面再次采集、截图成功，隐私夹具标签已不存在。后续验收从该进程重新发现，不复用前述旧进程标识。

## 有界性能观察

单位为 ms，测量从 MCP 调用到响应的总耗时。两端采集请求同时发出，旧快照详情逐一核对。

| 操作 | 样本数 | p50 | p95 / 最大值 |
| --- | --- | --- | --- |
| 同时发现 USB 与模拟器 | 3 | 2652.5 | 2656.7 |
| USB inspect_screen，含语义 | 5 | 169.4 | 182.3 |
| 模拟器 inspect_screen，含语义 | 5 | 148.0 | 167.7 |

p95 使用 nearest-rank，小样本下等于最大值。这些结果只证明本场景的短时有界观察，不代表长期内存稳定性、主线程帧率或发行性能 SLA。

## 证据与剩余门禁

原始产物目录：`/var/folders/0m/gdyng10s0p3fb_zz561qvsxc0000gn/T/astrolabe-integration-20261031-qug27jez`。

主要证据包括：baseline.json、host-audit-red.json、host-audit-green.json、adapter-audit-green.json、CleanWorkspace/CleanAdapter、uuid-red.log、host-node-green.log、host-swift-tests.log、simulator-selection-red.log、ios-metadata-green.log、ios-xcresult-summary.json、integration-summary.json、hardware-privacy-filled-summary.json、privacy3-*、hardware-restore-summary.json、hardware.png、hardware-privacy-filled.png 和 hardware-restored.png。临时快照会在重启或缓存过期后失效，历史 ID 不用于新进程验收。

代码独立审查未发现阻塞或非阻塞缺陷；补充核对所有工具 schema 的 SDK 转换、必填/可选快照规则和模拟器脚本行为。硬件实抓及最终报告由执行者核对。

剩余发布门禁包括拟声明系统的 SwiftUI 真机支持、较长性能/内存回归、安装升级与 Release 产物检查、版本和发布候选验证。阶段结论以这些明确边界为限。

范围澄清前的 Android 检查未通过：最初为旧本地 SDK 路径，使用当前本地 Protocol 后另遇 RuntimeHierarchyRoutesTest.kt:136 将参数 Companion 当实例传入的编译失败。它不计入本轮通过项，也未在用户排除 Android 后继续修复。
