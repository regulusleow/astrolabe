# SwiftUI 语义检查首个产品切片

日期：2026-10-18。方向已确认：组合现有采集链路，私有读取收口 adapter，新增有类型的语义事实，不放宽现有渲染节点约束。开发在各仓库 develop，允许原子提交，不推送、不合并、不发布。开发者随后要求连续完成本轮；设计、计划与实施在同一轮推进，不逐任务等待确认。

## 目标与边界

把 SwiftUIInspectorTest `94a35d9` 已验证的 AX/Text 读取接入 Protocol、iOS Runtime、Host/CLI/MCP。运行中 App 的目标窗口必须明确；返回值有来源、预算和缺失原因；语义详情属于原捕获，不会随活对象变化。

不是完整 SwiftUI 视图树或像素样式恢复。Mach-O、RemoteMirror、AttributeGraph、绘制闭包、逐 run 字体、继承色补全不进入首版。不增加业务 modifier/ID/wrapper、平台专属 MCP tool、通用插件系统或兼容 shim。不新增 UI 单测；协议、缓存及 Host 纯逻辑测试和真实 App 验证分开。

参考独立 Demo 的 `docs/proposals/2026-10-15-swiftui-astrolabe-integration-handoff.md` 与四份 2026-10-15 工程化/文字边界/动态/状态窗口报告。原生 UIFont/SwiftUI Font 解析值不等于最终 glyph fallback。

## 架构与责任

```text
现有 hierarchySnapshot / nodeDetail
  ├─ 原有请求 → UIKit / CALayer 原链路，不改事实约束
  └─ 语义请求 → 明确窗口 → AX collector → Text adapter
                                ├─ typed semantic capture
                                └─ 冻结详情值 → 有界 snapshot store
Host mapper → 页面快照身份 → 现有检查、搜索与 UI Graph
```

- Protocol 只定义事实、请求、来源和错误，不认识 SwiftUI 私有类型或反射路径实现。
- Runtime Core 管冻结值缓存和请求分派，不依赖 UIKit/SwiftUI。
- Runtime UIKit 负责窗口有效性、AX 对象遍历与具体 SwiftUI adapter；既有 UILabel collector 不扩大含义。
- Host 保留渲染/语义来源，处理快照和使用者输出，不读取目标进程私有对象。
- 复用自动 Runtime bootstrap、传输、typed 属性、弱原生对象 registry 和现有工具。组合点显式注入具体组件，不建设 Provider 插件框架。

## 契约：增量语义分支

保留现有 Wire v2 和 capability 扩展方式；不修改 RuntimeNode、RuntimeNodeGeometry、RuntimeNodeVisibility、RuntimeInteraction 的 required 字段。新增 capability `semanticInspection`。只有 Runtime 声明能力、调用方明确请求时才走新路径；没有能力时明确 capabilityUnavailable，不能把纯 UIKit 结果伪装为 SwiftUI 支持。

SDK 包版本与 Wire major/minor 不混用。本轮不创建发布 tag；Host/Runtime 固定到实际 Protocol 提交 SHA。本地构建可用仓库级 SwiftPM mirror 指向本地 Protocol；不得提交开发机绝对路径或改全局 Git 配置。远程 CI 需要先推送该 Protocol 提交，此操作留给开发者。

### 请求与响应

| 位置 | 新增字段 | 约定 |
| --- | --- | --- |
| RuntimeHierarchySnapshotParameters | semanticCapture: RuntimeSemanticCaptureOptions? | 缺失仍为原有空请求；提供空对象表示请求唯一普通窗口的语义分支 |
| RuntimeSemanticCaptureOptions | windowID: RuntimeOpaqueIdentifier? | 明确目标；缺失且多个有效普通窗口则拒绝 |
| RuntimeHierarchySnapshotPayload | semanticCapture: RuntimeSemanticCapture? | 有类型、可校验的新分支，与原 roots 并存，不存任意 JSON 树 |
| RuntimeNodeDetailParameters | snapshotID: RuntimeOpaqueIdentifier? | 语义详情必须绑定 Runtime 捕获；缺失仍保留原 UIView/CALayer 实时详情语义 |
| RuntimeNodeDetailPayload | semanticContext: RuntimeSemanticDetailContext? | 冻结身份、来源、局部缺失和候选，不塞进 UILabel 属性分组 |

整次响应 status 仍只有 success/failure。新数据使用局部 availability：complete/partial/unavailable；complete 仅表示该请求范围处理完，不表示恢复完整 SwiftUI 视觉树。

### 语义模型

所有新增 Swift/Kotlin 模型字段必须有注释；缺失 optional 字段表示未知，不写默认 false/1/零矩形。标识、坐标、颜色、计数沿用现有值类型与合法性限制。

| 类型 | 字段及含义 |
| --- | --- |
| RuntimeSemanticCapture | windowID（原生窗口实例标识）；source（命名空间来源）；availability；issues（有类型的原因列表）；visitedNodeCount；wasTruncated；roots（语义根） |
| RuntimeSemanticNode | nodeID；parentID（根为 null）；siblingIndex；role（开放语义角色）；runtimeType（实际对象类型）；accessibility（公开 AX 事实，可缺失）；frameInScreen（有限 screen/logical AX 区域，可缺失）；availableDetailCategories；children |
| RuntimeInspectionIssue | code（稳定命名空间原因）；path（局部字段路径，可缺失；不含业务值） |
| RuntimeSemanticDetailContext | snapshotID；capturedAtUnixTime（原捕获时间）；source；availability；issues；wasTruncated；textCandidates |
| RuntimeSemanticTextCandidate | source（原始附件/合并缓存来源）；path（原候选路径）；fields（有类型字段）；issues |
| RuntimeSemanticTextField | path（字段来源路径）；attribute（复用 RuntimeAttribute 的 identifier 与 typed value） |
| RuntimeInspectionWindow | windowID；sceneID（可缺失）；runtimeType；bounds（有限 local/logical，可缺失）；level（有限数，可缺失）；exclusionReason（可缺失） |

语义节点不含 local bounds、渲染 opacity、clipsContent 或直接 interactive 结论。AX trait 能描述语义状态，不证明物理可点击、无遮挡或可见。frame 与 viewport 相交也只表示几何相交。

### 身份、树和跨源关系

- 语义 ID 是每次捕获分配的不透明 ID；采集栈内用 ObjectIdentifier 去重，两个不同对象即使 label/frame 相同也保留。不同捕获不承诺稳定业务身份。
- 不把原生对象 registry 的 ID 直接当成语义投影 ID；两者表示不同观察。原 registry 继续管理 View/Layer 弱对象。
- children 是实际 AX 遍历的容器关系，不是布局树、绘制顺序或完整业务列表。循环和重复引用明确报告，保留预算边界，不构造未知节点。
- 当且仅当某语义记录的原对象就是本次 roots 已捕获的 UIView，输出 `ios.accessibility.representsView`，source 为语义 ID、target 为 View ID。关联由活对象身份建立，不按文本、frame 或类型匹配。
- Host 新增 kind=semantic 和 `tree.semanticChild`，不把它当 viewChild。可将两种来源纳入同一图索引，但不合并为一个假 UILabel 节点。

## 窗口与只读政策

请求语义捕获时，选择范围只含 App active、scene foregroundActive、可见、alpha 有限且大于 0、bounds 有效、level=normal 的窗口。唯一候选可自动选；多个候选必须指定 windowID。非普通浮窗只列排除原因，不混入所选窗口。最多枚举 64 窗口；清单超限则拒绝选择，不从不完整候选中挑一个。

windowID 复用弱原生窗口 registry 身份，作用域为当前 Runtime 进程。选择后在读取前与输出前校验同一窗口、scene、前台状态、有效几何和屏幕上下文；不一致返回 `inspection.contextChanged`。语义请求的原有渲染 roots 同样仅捕获选定窗口；原空请求的 UIKit 行为不改变。

错误代码：`inspection.targetAmbiguous`、`inspection.targetUnavailable`、`inspection.applicationInactive`、`inspection.contextChanged`、`inspection.snapshotUnavailable`、`inspection.captureTooLarge`。参数形状或身份错配使用 invalidParameters；不支持使用 capabilityUnavailable。错误不含 AX、文本、View/Layer 树或上次 UI 值。

歧义/失效目标错误可在现有 error.extensions 的 `common.inspectionTargets` 中附带 RuntimeInspectionWindow 数组。该键必须有专用 Schema 和 Swift/Kotlin typed 编解码访问器；不得用无契约 JSON 掩盖错误语义。Host 必须保留该诊断以便明确选择。

Inspector 不导航、不点击、不滚动、不写业务状态，不执行 body/动作/绘制闭包。Demo 中 UIApplication.accessibilityActivate 和伪造 VoiceOver 状态通知不默认迁移到产品。先验证读取公开 AX getter 的冷启动路径；未就绪则有界等待后 unavailable。没有证据时，不以开启 VoiceOver、调用业务 accessibilityActivate 或发送全局状态通知补救。

## 有界读取与隐私

- AX：最大深度 20、对象 2000、语义元素 500；达到精确边界不误判截断，确有未访问内容才标记 partial。
- 安全扫描：最大深度 32、UIView 2000、每节点子项 100。发现 secure 输入或扫描不完整，整个选定窗口禁止 Text 附件投影并省略 AX value，不从其他来源补原文。
- Text：每节点深度 20、访问 1500、每值子项 50；每请求最多读取 30 个有访问的附件对象、总访问 10000；字符串最多 16384 UTF-8 bytes。输出累计值预算 4 MiB；超限标记 partial 并停止追加。
- 私有字段只启用已验证 iOS 27.0 路径，类型与字段白名单在反射前生效。未知布局停止当前分支，不探测任意对象图。非已验证系统仍可使用原 UIKit 功能。
- 不承诺 Swift catch 能隔离私有 API SIGTRAP。不启用完整 _viewDebugData，不求值 AG 或执行未知闭包。
- 截图仍可能显示安全输入掩码圆点；不承诺隐藏长度。截图与 JSON 不是同一渲染事务。
- 仅失败、nil 早退、条件不满足路径记中文诊断；正常路径不新增日志，日志不含业务文本。

## Text 字段语义

原始 attachmentsStorage 与 cachedCombinedAttachment 分开保留路径。后者不能取代原始 Text 的视觉字体；同一原始 Text 内的字段才共享作用域。未知富文本 run 不强行拆分。

候选中的合法属性复用 common.text.fontName/fontSize/color 等 typed value；localizedKey 用 `ios.swiftui.text.localizedKey`，不能当 common.text.content。verbatim 可保留原文。只有白名单原始附件中唯一 Text 作用域且该字段归属已证明，才能提升到节点 common.text section；多原始 Text、不同值或无法证明作用域时，保留候选并返回 partial，检查结果为不可验证而非通过。合并缓存不参加原始字体的唯一性选择。

字号使用已解析 pointSize 和 common.text.fontSize 的 scaledLogical 单位，不二次缩放 Dynamic Type。Font 的粗体/等宽特征不冒充精确数值字重。颜色仅在当前 RuntimeColor 可表达的有限 [0,1] RGBA 范围投影；扩展色域超界不得截断成看似精确颜色，保留不可用原因。继承色、tint、secondary 缺失不填系统默认。

## 冻结详情与生命周期

采集在 MainActor 内读取活对象，立即冻结成 typed 值；完成前校验上下文，再原子提交本次捕获及详情。缓存键为 Runtime snapshotID + 语义 nodeID，不保存 NSObject、View、Font token 或闭包。

缓存固定最多 4 个捕获、TTL 300 秒、单捕获编码值 4 MiB、总编码值 16 MiB；总字节包含语义结构及冻结详情。按捕获时间驱逐最旧，不因查询续期。编码后超出单次预算则整次失败，不返回声称可查询却未保存的语义节点。进程重启清空。

语义 nodeDetail 必须携带对应 snapshotID，且节点属于该捕获；过期、驱逐或不存在返回明确错误，不抓取当前 UI、不回退实时对象。对象已释放但冻结值仍有效时，可以返回原值。查询 Runtime 的新语义接口仍要求 App 前台；Host 已存的历史快照可离线读，但不能标为当前 UI。

UIView/CALayer 实时详情继续走原 provider，不承诺因此冻结所有渲染属性。新 Core semantic provider 作为显式可选服务接缝提供 capture(options) 与 detail(nodeID,snapshotID)，不修改旧 provider 的方法含义。

## Host、CLI 和 MCP

- 在既有捕获工具增加可选 includeSemantics/windowId；CLI 对应 --include-semantics/--window-id。默认不改变旧捕获；windowId 只用于语义请求。没有能力时显式失败，不忽略参数。
- --snapshot-id 读取历史时不允许混入新的目标选择/采集参数；冻结范围不能被修改。语义 inspect-node 必须有 Host page snapshot 上下文，不能暗中重新抓当前页面。
- Mapper 在 Host 改写 snapshotId 之前保存 runtimeSnapshotId 与 runtimeCapturedAtUnixTime；两种 ID、Host 保存时间及 Runtime 捕获时间不能混用。
- 映射语义节点为 kind=semantic，保留真实 runtimeType/runtimeRole、AX 区域及来源；不填 visible=true、alpha=1、bounds 或假的 UIKit 类名。可读来源分支命名 semanticItems，与 displayItems 的渲染事实分开；搜索/检查/图的相应入口显式消费二者。
- 语义角色筛选只映射已知 runtimeRole，不从 AX 标签、类名或旧角色集合追加 timer/avatar 等领域猜测；未知开放 role 原样保留，不强行纳入 Host 已知角色。原生节点的既有领域分类不变。
- nodeID 不透明。新能力 Runtime 的无页面 exact-oid 检查先仅请求 nodeDetail，不自动捕获；Runtime 拒绝或返回未绑定 semanticContext 时立即结束。只有 native 成功才继续原生投影；未知 ID 不以重抓补 registry。旧能力目标按原流程分派，不依赖 ID 命名。
- 语义详情 cache miss 使用保存的 runtimeSnapshotId；校验返回 semanticContext 的 snapshotID、nodeID 和时间，再写入 Host 缓存。新增 detailSource=runtimeSnapshot；capturedAt 使用原捕获时间，不用查询时刻。
- Host 转发 typed semanticContext 与现有 detail.extensions；不丢失候选或来源。样式缺失/歧义必须表现为不可验证，不由默认值通过检查。
- 若明确选定的窗口被其他窗口覆盖，整屏截图仍可能是上层窗口；不得据此宣称截图与目标节点一一对应。

## 交付与验收

1. Protocol：Swift/Kotlin 模型与 Schema/正反例一致；新请求可解码、旧 required 渲染节点约束不变；错误诊断有类型；不支持能力被拒绝。
2. Runtime Core：实际缓存证明 A→B 后 A 值不变；错配、过期、驱逐、字节限制不回退实时；原路由/取消/patch 测试保持通过。
3. Host：参数透传、Runtime/Host ID 区分、冻结详情、unknown 样式、semantic graph 与来源映射均有纯逻辑测试；原 iOS/Android 行为回归。
4. 持续运行的 iOS 27.0 Demo：冷启动不激活动作即可抓取已验证 SwiftUI 文本；标题 28 pt、按钮原始 16 pt、语义替换 label 分开；同文案 14/22 pt 不误合并；A/B 与旧详情冻结；安全输入、窗口歧义/显式选择、后台拒绝按已列样例验证。复用已有页面/驱动，不新增 UI 单测。
5. 完成后独立审查、修复影响正确性的发现、原子提交，停在 develop，不推送/创建 PR/合并/发布。已知 partial 和未验证系统明确交接，不把 Demo 证据当产品验收。

新增能力不要求修改 Android Runtime 功能；共享 Kotlin DTO/契约验证仍须同步。Debug/Beta 可集成 Runtime；正式发行/App Store 成品必须排除并检查最终产物。
