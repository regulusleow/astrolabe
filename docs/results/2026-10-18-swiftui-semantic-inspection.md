# SwiftUI 语义检查首个产品切片：验收记录

执行日期：2026-10-18 至 2026-10-19。范围为 Protocol → iOS Runtime → Host/CLI/MCP，不修改 Android Runtime、Demo 源码或业务页面。三个产品仓库均在 `develop` 本地提交，不推送、创建 PR、合并或发布。

## 结果与能力边界

现有检查链路增加显式语义采集：`--include-semantics`，对应既有 MCP 捕获工具的 `includeSemantics`；多窗口用 `--window-id` / `windowId` 明确选择。工具数量保持 23。默认请求仍走原生 View/Layer 路径。

可以读取有界 AX 容器关系、实际类型、语义角色、标签、traits、AX screen frame，以及已验证 iOS 27.0 Text 附件中的有限字体、字号、显式颜色和候选。语义节点独立为 `semanticItems` / `kind=semantic`，不合并为 UIView 或伪造 UILabel。

这不是完整 SwiftUI 声明树、布局树或像素样式恢复。未知可见性、透明度、local bounds、遮挡、继承颜色、精确字重、最终 glyph fallback 不补默认值。`partial` 表示局部缺失；只允许已独立证明的 canonical 字段通过断言，候选或歧义字段返回 `unableToVerify`。

## 版本与环境

| 项目 | 验收版本 |
| --- | --- |
| Protocol | `059383703b2fde91b7b1b5f32d0043299a7e9ce5` |
| Runtime 采集与冻结逻辑 | `a39bd629d6ecd67d58cbad1e0e8c517a942e7c8f` |
| Runtime 最终后台错误修复 | `96d6be2a6c49da276e7945fd6e9a0436e3949288` |
| Host 初次真实链路 | `8e92dfdb5fe4390f8531b5c4fcc899639fecfc92` |
| Host 角色复审修复 | `fbf5fed9e0da11ccfb857872ff7f988c042146c3` |
| 模拟器 | iPhone 18 Pro，iOS 27.0，`CD6AFF4C-3BD7-4DA5-AC90-7C3B542CDF47` |
| 工具链 | Xcode 27.1 / build 27A9275；Wire 2.0 |
| Demo | `SwiftUIInspectorTest`，既有 `feat/swiftui-capture` / `94a35d9`，bundle `devplaceholder.R9LMG6O0.SwiftUIInspectorTest` |

通过单次 Simulator launch 的 `DYLD_INSERT_LIBRARIES` 加载本次构建的 Runtime 动态框架，没有修改 Demo 工程、业务源码或全局注入配置。Demo 不带 capture 参数启动，不执行其旧 Inspector 探针，也没有 AX 激活或伪 VoiceOver 预热。

普通启动不等于已就绪：首次 discovery 可能为空，应等待 Runtime listener 就绪后重新发现。恢复前台同样需要等待实际 active，不能把一次 launch 成功当成可采集证明。

## 真实 CLI/MCP 链路

使用源码编译的 `.build/debug/astrolabe` 和 `mcp-adapter/dist/index.js`，通过真实 MCP SDK stdio transport 调用；没有用已安装旧版 MCP 的静态 schema 冒充新参数验收。

首次冷启动进程 `31923`，Runtime instance `B3D9E1BB-1D1D-43EB-94E4-09F169C8C7A0`。`list_apps` 确认 compatible，随后首次 `inspect_screen(includeSemantics=true)` 读取基础页，无页面动作或 AX getter 预热在前。

| 场景 | 实际结果 |
| --- | --- |
| 冷启动首抓 | 有 SwiftUI 标题、当前状态 A 等 AX 内容；visited 91，局部 `partial`，未声称完整恢复 |
| 标题样式 | canonical 字号 28 `scaledLogical`，`.AppleSystemUIFontRounded-Bold`，显式 RGBA；字号 28 断言通过 |
| 按钮原始样式与 AX 替换标签 | 原始 Text key“切换样本状态”候选含 16 pt；AX label“运行时状态切换”另存。多原始 Text 作用域不提升 canonical，16 pt 断言为 `unableToVerify` |
| Host 与 Runtime 身份 | Host page `42F60161-E5C2-4D51-83F1-7A11BB386640`，Runtime snapshot `C445EBA7-C55B-4AD4-8472-3CFE001610B8`，不是同一 ID |
| A → B 后首次读取 A 详情 | A 节点详情文件事前不存在，仅标题已缓存。切换 B、新抓 B 后，首次查询旧 A 仍为 A，`detailSource=runtimeSnapshot`，原 Runtime ID 和时间 `1792340999.0956469` 保持 |
| 缺页面上下文 | 裸语义 oid 返回 `invalidParameters`，不自动重抓当前 UI；不依赖 ID 前缀判断来源 |
| 未知可见性 | 同一语义节点 `expectedVisible=true` 与 `false` 都不通过；默认查找仍返回节点 |
| 同文案不同实例 | CLI 新抓边界页，MCP 找到两个“重复文案样例”；不同 oid，详情分别为 14、22 `scaledLogical` |
| 非空安全输入 | 宿主填入非空假密码后，capture 包含 `secureInputContext`；Host 保存的完整树 AX value 数量为 0，假密码不在输出中 |
| 安全详情冻结 | 关闭输入并切换页面后，旧安全快照详情仍是 `runtimeSnapshot`，属性组和 Text 候选均为 0，保持 `secureInputContext` |
| 两个普通窗口 | 自动抓取返回 `inspection.targetAmbiguous`，无 data，typed `common.inspectionTargets` 透传到 MCP |
| 显式窗口 | 主窗口 1 不含第二窗口文案；窗口 411 含“第二窗口内容”。关闭 411 后再抓该 ID 返回 `inspection.targetUnavailable` |

MCP `capture_hierarchy` 的既有默认 nodeLimit=25、最大 200 仍生效。安全页共有 447 节点，默认有界输出不会包含整棵语义树；完整隐私检查另读同次 Host 保存的 hierarchy，以及 Runtime 原始输出，不把截断的 25 节点当作完整树证明。

本轮宿主只对这个专用 Demo 执行已授权的状态准备（切 tab、已有 AX action、标准输入、后台/前台）。这些驱动与 Inspector 产品代码隔离；Runtime 读取器没有导航、点击、写业务状态或执行未知闭包。

## Runtime 专项运行证据

在 `a39bd62` 动态框架（arm64 UUID `F7CEBEE8-31CB-3884-94AF-1303F255DE49`）、普通进程 `24339` 上，另通过只读 Wire 请求验证：

- 安全输入：非空假密码不在 capture/detail；原生与语义 AX value 都省略，Text 附件禁止。既有普通输入的原生 `.text` 仍是原有可见渲染事实，不宣称所有普通文字被隐藏。
- 窗口：普通窗口 1 / 424 要求明确选择；隐藏 424 后新抓拒绝，旧冻结详情仍可读为 24 pt。只证明窗口隐藏，不宣称系统已释放对象。
- 非普通浮窗：level 2001 的窗口 436 被排除；自动抓取主窗口不混入浮窗内容，显式抓 436 被拒绝。整屏截图可能仍看到浮窗，不代表与选定窗口事实同步。
- 后台：语义 capture 与绑定 snapshot 的 detail 都返回 `inspection.applicationInactive`，无 UI payload；恢复前台需等实际 active 后才可读。
- TTL：初次实现 `109713e` 的 A 快照自然超过 300 秒后返回 `inspection.snapshotUnavailable`，没有回退当前 B。最终缓存边界另由 Core 纯逻辑测试覆盖。

旧 `_viewDebugData` / AttributeGraph SIGTRAP 路径不在产品实现内。无 Mach-O、RemoteMirror、未知对象图递归或 body/绘制闭包求值。

## 独立审查与集成修复

- Protocol：统一 typed JSON 路径规则、嵌套文本预算和窗口诊断唯一 ID 校验；复审通过。
- Runtime：未知原始字段阻断 canonical、重试不重置 Text 总预算、重复槽位尾部明确截断；复审通过。冷启动标题从候选提升为有证据的 canonical，经新构建真实复验。
- Host：语义角色不得由标签 `01:30` / avatar 等猜测补入。修复后只映射已知 Runtime role，未知 role 原样保留但不增加 Host 角色；原生领域分类不变。纯逻辑 RED 4 项 / 13 断言，GREEN 4 项，复审通过。
- 集成后台错误：真实新 CLI session 先读取 applicationInfo，旧接口在后台先返回 internalFailure，掩盖后续语义拒绝。`96d6be2` 仅在 appInfo 已有“无 active screen”失败分支中，对 inactive App 返回 typed `inspection.applicationInactive`；不改成功路径，不用字符串匹配或旧信息缓存。

### 最终组合复验

`96d6be2` Runtime + `fbf5fed` Host 再次普通冷启动，进程 `34088`，arm64 Runtime UUID `0BAB1033-B5EA-323E-BE00-E0842818CD65`。无 AX 预热，source MCP 首抓成功；标题 28 `scaledLogical` 断言通过。

这次 Host page `3F6A8CDA-D156-4746-B06A-D34530576C58` 对应 Runtime snapshot `10C5C148-60B1-43DA-AB1E-570DD8325F90`，原时间 `1792341589.679974`。A 节点详情事前不存在，仅标题已缓存；宿主切换 B，source CLI 新抓后，MCP 首次读 A 仍返回 A、`runtimeSnapshot` 及原 Runtime 身份/时间。

同进程切后台后，source MCP 新连接的 `inspect_screen(includeSemantics=true)` 返回 `astrolabe_runtime_inspection.applicationInactive`，没有 data。此前同流程的 `internalFailure` 已被真实 GREEN 替代。原始证据为 `final-*.json`；不同构建和进程的结果不混写为同一次捕获。

## 最终门禁与交接

- Protocol：Swift 31、Kotlin 41、62 个 Schema fixtures（32 valid / 30 invalid）、15 项工具测试及 Release build 通过。
- Runtime 采集版本：52 XCTest（Core 39 / UIKit 纯策略 8 / Runtime 3 / ObjC 2），Simulator 动态框架 build 通过。保留基线已有 `Supported platforms for the buildables in the current scheme is empty` 警告；不宣称无警告构建。
- Runtime 最终 `96d6be2`：重新运行 52 XCTest 与同一 Simulator build，均通过；上述既有警告仍在。动态二进制 SHA-256 `5a35993f5c45829e1b3c049f9114d629b6e2fc002136e0abbf4ce2fc5b284eeb`。
- Host 角色修复版本：Swift 287 / 287、MCP 44 / 44、typecheck 与 build 通过，无新警告。新增测试是协议/缓存/映射/命令纯逻辑，不是 UI 单测。

Protocol 尚未推送。Host/Runtime 的 Package.swift 固定完整 Protocol SHA；本地用仓库级 SwiftPM mirror，无 tracked 绝对路径或全局配置修改。开发者推送时先使该 Protocol SHA 远程可获取，再运行消费者 CI / 创建 PR。

原始 JSON、截图、构建日志和只用于本轮 Demo 的宿主驱动保存在 `/tmp/astrolabe-swiftui-20261018.iyQU95` 及本轮 SDD 执行目录；它们是临时诊断证据，可能被系统清理，不作为 SDK 分发内容。本文保留版本、关键值、身份及可重现步骤。

复验顺序：构建并单次加载 Runtime → 保持 App 前台 → `list_apps` 重新取 appId 并检查 compatible → `inspect_screen` 带 `includeSemantics:true` 得到 page snapshotId → `find_nodes` / `inspect_node` / `check_style` 复用该 page snapshotId。状态变化后重新发现和捕获；旧 ID 仅可作为明确的历史冻结检查，不当作当前 UI。

```sh
astrolabe inspect-screen "$appId" --include-semantics --json
astrolabe inspect-node "$appId" --snapshot-id "$pageSnapshotId" --oid "$oid" --json
astrolabe check-style "$appId" --snapshot-id "$pageSnapshotId" --oid "$oid" --expect fontSize 28 --json
```

验证范围仅为本机 iOS 27.0 Simulator。未验证真机、其他系统版本、所有 SwiftUI 控件、富文本逐 run、全量性能或生产集成；不宣称已完成这些支持。正式 App Store 成品必须排除 Runtime 并检查最终产物。
