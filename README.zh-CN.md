# Astrolabe（星盘）

[English](README.md) | 简体中文

Astrolabe 是一款面向 AI 编码智能体的运行时 UI 检查工具。它结合 Swift
CLI、本地 MCP Server 和配套的 Agent Skill，用于检查和验证正在运行的移动端界面。

Android View 检查通过 [Astrolabe Runtime for Android](https://github.com/regulusleow/astrolabe-runtime-android) 提供。

## 功能

- 发现运行在 iOS 模拟器、Android 模拟器或 USB 连接设备上的受支持 App。
- 检查 UIKit、Core Animation 和 Android View 层级、节点 Frame、可见性、文本、样式、语义角色和
  详细运行时属性。
- 检查 SwiftUI 语义节点、文字样式、线性渐变、图片元数据和文本基础可见性。
- 获取原生分辨率截图，并与预期图片或已记录的 Baseline 进行比较。
- 查询节点，并校验样式、布局和节点详情是否符合预期。
- 通过冻结的页面快照，让相关层级操作始终基于同一个页面状态。
- 在 Debug 构建中应用白名单内的内存临时表现补丁，并支持还原，不修改源代码或持久化状态。
- 通过 CLI 命令、MCP Tools 和配套的 `astrolabe` Skill 提供一致的检查工作流。

## 环境要求

- 运行 macOS 13 或更高版本的 Apple Silicon Mac
- Node.js 22 或更高版本
- 检查 Android App 时需要 Android Platform Tools（ADB）
- 在 Debug 构建中启用了 Astrolabe Runtime SDK 的受支持 App

## 安装

使用 Homebrew 安装 Astrolabe：

```bash
brew install regulusleow/tap/astrolabe
```

为指定 AI 客户端配置 Astrolabe：

```bash
astrolabe install --client codex
astrolabe install --client opencode
astrolabe install --client claude-code
```

如需一次配置所有已检测到的 AI 客户端：

```bash
astrolabe install --all-detected
```

Homebrew 的安装、升级和卸载操作不会修改 AI 客户端配置。执行 `astrolabe install` 后，
请重启已配置的 AI 客户端。

源码构建需要支持 Swift 5.9 或更高版本的 Xcode。克隆仓库后，为需要使用的 AI 客户端安装 Astrolabe：

```bash
git clone https://github.com/regulusleow/astrolabe.git
cd astrolabe
npm run install:codex
npm run install:opencode
npm run install:claude-code
```

Codex、OpenCode 和 Claude Code 可以单独安装，也可以一次安装。多客户端安装只会构建一次共享 Package：

```bash
node scripts/install.mjs --client codex --client opencode --client claude-code
```

源码安装器会将共享产物放在 `~/.astrolabe/distributions/source`，并把配套 Skill 链接到各客户端
支持的用户级 Skill 目录。每个客户端适配器只管理自己的 MCP 配置：Codex 使用
`~/.codex/config.toml`，OpenCode 使用 `~/.config/opencode/opencode.json`，Claude Code
使用 `~/.claude.json`。安装或卸载某个客户端不会删除其他客户端的配置或仍在使用的 Skill 链接。

安装完成后，请重启已配置的 AI 客户端。

Brew 安装后，通过已安装的 CLI 检查或移除客户端的 Astrolabe 接入。以下以 Codex 为例，
可将 `codex` 替换为 `opencode` 或 `claude-code`：

```bash
astrolabe check --client codex
astrolabe uninstall --client codex
```

源码安装请在克隆的仓库目录中执行以下管理命令：

```bash
npm run reinstall:codex
npm run check:codex
npm run uninstall:codex

npm run reinstall:opencode
npm run check:opencode
npm run uninstall:opencode

npm run reinstall:claude-code
npm run check:claude-code
npm run uninstall:claude-code
```

## 快速开始

启动包含受支持 Runtime SDK 的 Debug 构建，抓取 UI 时保持 App 正在前台运行。先发现 App：

```bash
astrolabe list-apps --json
```

使用返回的 `appId` 执行检查命令：

```bash
astrolabe inspect-screen <app-id> --json
astrolabe capture-hierarchy <app-id> --json
astrolabe find-nodes <app-id> --role text --visible-only --limit 20 --json
astrolabe inspect-node <app-id> --oid <oid> --json
astrolabe node-detail <app-id> <oid> --json
astrolabe capture-screenshot <app-id> --output /tmp/screen.png --source auto --json
```

层级命令会返回 `snapshotId`，后续查询复用它以使用同一份层级数据。SwiftUI 语义详情来自对应的
冻结快照；原生节点详情首次查询时读取实时 Runtime 状态，随后在该快照内缓存。
截图和视觉对比命令始终使用最新页面。

安装后的 MCP Server 会向 Codex、OpenCode 和 Claude Code 提供相同的能力。配套 Skill 指导 AI
进行只读界面检查，并依据开发者提供的设计参考进行一致性验收。

### SwiftUI

使用支持 SwiftUI 检查的 iOS Runtime。抓取时添加 `--include-semantics`，再复用返回的
`snapshotId` 查找和检查 SwiftUI 节点：

```bash
astrolabe capture-hierarchy <app-id> --include-semantics --json
astrolabe find-nodes <app-id> --snapshot-id <page-snapshot-id> --role text --json
astrolabe inspect-node <app-id> --snapshot-id <page-snapshot-id> --oid <semantic-oid> --json
astrolabe check-style <app-id> --snapshot-id <page-snapshot-id> --oid <semantic-oid> --expect fontSize 28 --json
```

存在多个可检查窗口时，在抓取命令中添加 `--window-id <window-id>`。SwiftUI 节点详情属于对应快照，
后续检查时需同时保留该快照的 `snapshotId` 和节点 ID。

通过 MCP 使用时，为 `capture_hierarchy` 设置 `includeSemantics: true`，再将返回的
`snapshotId` 传给 `find_nodes` 和 `inspect_node`。

`--visible-only` 仅包含基础可见性已确认的节点。样式信息缺失或存在歧义时，返回
`verification=unableToVerify`。

## 开发

安装依赖并运行测试：

```bash
npm ci
npm --prefix mcp-adapter ci
npm test
swift test --parallel
```

构建 Release CLI：

```bash
swift build -c release --product astrolabe
```

在受支持 App 正在运行时执行端到端冒烟测试：

```bash
npm run test:smoke
npm run test:usb
```

## 相关仓库

- [astrolabe-protocol](https://github.com/regulusleow/astrolabe-protocol)：与平台无关的
  Wire Protocol、Schema、Fixture，以及 Swift/Kotlin DTO 和 Codec。
- [astrolabe-runtime-ios](https://github.com/regulusleow/astrolabe-runtime-ios)：在 Debug 构建中检查
  UIKit、Core Animation 和 SwiftUI 的 Runtime SDK。
- [astrolabe-runtime-android](https://github.com/regulusleow/astrolabe-runtime-android)：
  仅用于 Debug 构建的 Android View Runtime SDK。

Astrolabe Host 直接使用共享协议，不依赖具体平台的 Runtime 实现 Package。

## 路线图

- 支持 Jetpack Compose Runtime 检查。
- 集成更多 AI 编码平台。

## 许可证

Astrolabe 使用 [Apache License 2.0](LICENSE) 许可。派生自第三方项目的组件仍受其原始许可证
约束，详见 [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES)。
