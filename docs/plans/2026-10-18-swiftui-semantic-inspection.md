# SwiftUI Semantic Inspection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 把已验证 AX/Text 能力接入 Astrolabe 的现有检查工具，保留来源、缺失与冻结详情。

**Architecture:** typed semanticCapture 与既有渲染 roots 并存。Core 的显式 semantic provider 管请求/冻结值，UIKit adapter 管平台读取，Host 负责快照关联与输出。不把未知渲染事实填成默认值。

**Tech Stack:** SwiftPM、Swift/Kotlin Protocol、JSON Schema、UIKit/SwiftUI、现有 TypeScript MCP adapter。

**Spec:** `../architecture/2026-10-18-swiftui-semantic-inspection.md`

## Global Constraints

- 三个产品仓库在 develop 开发；允许本任务原子提交，不推送、PR、合并或发布。
- 旧 RuntimeNode 的 required 渲染事实不放宽；新 capability=semanticInspection，旧空请求不改变。
- 业务零埋点，读取器不执行 UI 业务动作；无证据不迁移 Demo 的 AX activation/伪 VoiceOver 通知。
- 私有布局仅启用已验证 iOS 27.0；未知/截断/安全输入不伪装成功；所有模型字段有注释，新增日志仅失败路径且中文。
- 缓存 4 捕获、TTL300秒、单次4MiB、总16MiB；AX/Text/安全扫描预算精确沿用 Spec。
- 不新增 UI 单测、平台 MCP tool、兼容 shim、插件框架；复用现有页面与可执行验证。
- Protocol 完成后消费者固定该实际 SHA；本地仅用仓库级依赖映射，不写入开发机路径或发布版本。

## Review Focus

- 冷启动 AX 数据未物化时不得触发业务动作补救；真实首抓没有 SwiftUI 数据不能算产品通过。
- 对象身份相同/不同与语义投影身份不同，两个同文案同 frame 实例不误合并。
- Host 新 page snapshotId 覆盖 Runtime ID 后，旧详情请求仍准确指向 Runtime 捕获。
- 多窗口/后台/上下文失效错误不含旧 UI，窗口选择诊断可传至调用者。
- 私有样式候选歧义、超界颜色与安全输入不可经别的详情出口绕过。

---

### Task 1: Protocol typed semantic contract

**Repository:** `/Users/machen/Documents/github/astrolabe-protocol`，develop。

**Files:** 新建 Swift `Inspection/Semantics/RuntimeSemanticInspection.swift`，Kotlin `inspection/RuntimeSemanticInspection.kt`；修改 hierarchy/node-detail models、RuntimeCapability、inspection/request/response Schema、PROTOCOL.md/manifest、对应 Swift/Kotlin 契约测试与 fixtures。其余细分文件按单一责任放在相同目录。

**Interfaces:** 提供 Spec 表中 RuntimeSemanticCaptureOptions/Capture/Node/DetailContext/TextCandidate/TextField/InspectionIssue/InspectionWindow；现有 hierarchy 参数新增 semanticCapture?，payload 新增 semanticCapture?，nodeDetail 参数新增 snapshotID?，payload 新增 semanticContext?；RuntimeCapability.semanticInspection。为 error.extensions[common.inspectionTargets] 提供 typed 访问器。所有现有初始化调用仍可省略新增 optional 参数。

- [ ] 先写测试：旧 required 渲染 geometry 不能为 null；新语义节点 frame 可缺失；新参数/局部状态/冻结上下文 round trip；候选属性类型保持；重复 nodeID、父边错配、非法坐标/计数/路径预算拒绝。
- [ ] 运行 `swift test`，确认新增行为在实现前失败，并记录原因。
- [ ] 实现最小 DTO/校验/Schema/访问器，保留既有值类型和开放 role/source；不要新增 wire 顶层 partial 状态。
- [ ] 跑 `swift test`、现有 Kotlin 测试和 Schema fixture 验证（按本仓库 CI 中真实命令）；正反例证明旧请求/渲染约束保留。
- [ ] 自审、原子提交 `feat(protocol): 添加有类型语义检查契约`；报告完整 SHA、公共签名、RED/GREEN 和仍未验证项。

### Task 2: iOS semantic runtime and frozen values

**Repository:** `/Users/machen/Documents/github/astrolabe-runtime-ios`，develop。

**Files:** Package.swift 固定 Task1 SHA；Core 新增 `RuntimeSemanticInspectionProviding.swift` 与 `RuntimeSemanticSnapshotStore.swift`，修改 RuntimeInspectionServices；UIKit 新增 `UIKitRuntimeSemanticInspectionProvider.swift`、`UIKitSemanticAccessibilityCollector.swift`、`SwiftUITextAttachmentProjector.swift` 及其必要局部值模型/预算；修改工厂及 UIKitRuntimeHierarchyProvider 的显式选定上下文入口。纯 Core 测试放 Tests/AstrolabeRuntimeCoreTests。

**Interfaces:** package @MainActor RuntimeSemanticInspectionProviding 定义 `capture(options: RuntimeSemanticCaptureOptions) async throws -> RuntimeHierarchySnapshotPayload`、`detail(nodeID: RuntimeOpaqueIdentifier, snapshotID: RuntimeOpaqueIdentifier) async throws -> RuntimeNodeDetailPayload`。RuntimeInspectionServices 新 optional semantic provider 参数；原 provider 接口含义不变。Core store 接受冻结 capture/detail 值，按 Spec 限制写入和读取；时间可注入纯逻辑测试。

- [ ] 先写纯 Core 测试：A值不随B更新；错快照/节点、300秒过期、第五次捕获驱逐、单次/总字节限制；不调用 live fallback；unsupported semantic route 拒绝。
- [ ] 跑受影响测试观察 RED；实现 store、分派和 explicit provider seam 后 GREEN，保持旧测试通过。
- [ ] 从 Demo 仅迁移已验证 Text 白名单/预算/安全读取政策，输出 Task1 typed 值；不要复制完整探针框架。所有安全出口按 Spec 共同受限。
- [ ] 工厂组合原 UIKit render provider 与 AX/Text adapter；先只读获取 AX 数据，不调用 accessibilityActivate/伪 VoiceOver 通知。contextChanged、窗口歧义/失效/后台拒绝带 typed 诊断。
- [ ] 跑完整 `swift test` 与 iOS Simulator build；无新增 UI 单测。真实运行是否可读由 Task4 验证，不能拿 build 替代。
- [ ] 自审、原子提交 `feat(ios): 接入有界语义采集与冻结详情`；报告 SHA、依赖设置、测试及运行限制。

### Task 3: Host/CLI/MCP semantic workflow

**Repository:** `/Users/machen/Documents/github/astrolabe`，develop。

**Files:** Package.swift 固定 Task1 SHA；RuntimeHostCore client/session/response mapper；CLI hierarchy/detail provider 参数链、PageSnapshotWorkflow、必要 graph kind/edge/adapter；iOS semantic role/detail mapper；既有 MCP tools 参数/输出；对应纯逻辑测试及使用文档。不修改 Android Runtime 采集功能。

**Interfaces:** hierarchy 请求可表达 includeSemantics 与 windowID；`--include-semantics`/`--window-id` 和既有工具 `includeSemantics`/`windowId`。语义 items 保存在 semanticItems，不伪造渲染字段；旧 displayItems 不变。Host 保存 runtimeSnapshotId/runtimeCapturedAtUnixTime，再分配 page snapshot ID。语义 inspect-node 消费已保存的 page snapshot，上送 Runtime snapshotID 并验证返回 semanticContext。

- [ ] 先写测试：capability 缺失拒绝、不忽略 window；缺 page snapshot 不抓当前 UI；runtime/page ID 不混；A→B后请求A不取B；过期不回退；partial/歧义样式不通过；原 iOS/Android output 不变。
- [ ] 运行精确测试观察 RED；实现最小参数传递、mapper、上下文验证和缓存读取，补 graph semantic kind/tree.semanticChild。
- [ ] 保存 error 的 typed 选择诊断、detail.extensions/semanticContext；字典映射不能把 nil 可见性改 true 或伪造 UILabel。
- [ ] 跑完整 `swift test` 和 mcp-adapter 现有测试/类型检查；每组实际命令与结果入报告。
- [ ] 自审、原子提交 `feat(host): 贯通语义快照检查链路`。

### Task 4: Running-App acceptance and final review

**Files:** Host `docs/results/2026-10-18-swiftui-semantic-inspection.md`；必要的最小纯验证脚本。独立 Demo 现有未提交文档与 feat 分支不移动、不提交；产品代码都在 develop。

**Interfaces:** 使用前三项真实产物，Simulator iOS27.0、现有 SwiftUIInspectorTest 页面及既有 Host CLI/MCP；只针对该 Demo 允许宿主准备 UI。Runtime 自身只读。

- [ ] 构建并将 Runtime 加载进现有 Demo，确认持续运行、前台、目标明确。优先零业务源码改动的测试加载；不写全局注入配置。
- [ ] 经真实 CLI/MCP 验证冷启动首抓、原始字体/语义标签、旧快照冻结、同文案不同实例、安全输入、窗口选择/后台拒绝；记录不同构建 UUID 和时间，不能复用旧 Demo JSON 冒充本次验收。
- [ ] 若冷启动只读 AX 路径确实不可用，先调查公开 getter/已验证系统读路径；不越过无业务动作政策。无法证明则报告实际未通过项，不标完成支持。
- [ ] 独立 whole-branch 审查三个 commit 范围；影响正确性的发现走 RED→GREEN 修复并重跑覆盖套件，不新增 UI 单测。
- [ ] 提交报告/必要修复，核对三仓库 develop、diff --check、提交与 upstream 关系；不推送、不合并，交接本地 SHA 与能力边界后停下。
