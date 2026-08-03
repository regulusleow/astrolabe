# Astrolabe

[English](README.md) | 简体中文

Astrolabe 是一款面向 AI 编码智能体的运行时 UI 检查工具。它结合 Swift
CLI、本地 MCP Server 和配套的 Agent Skill，用于检查和验证正在运行的移动端界面。

Android View 检查由 Astrolabe Android Runtime 2.0 提供支持。

## 功能

- 发现运行在 iOS 模拟器、Android 模拟器或 USB 连接设备上的受支持 App。
- 检查 UIKit 和 Android View 层级、节点 Frame、可见性、文本、样式、语义角色和
  详细运行时属性。
- 获取原生分辨率截图，并与预期图片或已记录的 Baseline 进行比较。
- 查询节点，并校验样式、布局和节点详情是否符合预期。
- 通过冻结的页面快照，让相关层级操作始终基于同一个页面状态。
- 在 Debug 构建中应用白名单内的内存临时表现补丁，并支持还原，不修改源代码或持久化状态。
- 通过 CLI 命令、MCP Tools 和配套的 `astrolabe` Skill 提供一致的检查工作流。

## 环境要求

- macOS 13 或更高版本
- Swift 5.9 或更高版本
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

如需从源码安装，请克隆仓库，然后为需要使用的 AI 客户端安装 Astrolabe：

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

安装管理命令：

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

启动包含受支持 Runtime SDK 的 Debug 构建，然后发现 App：

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

层级命令会返回 `snapshotId`。将其传递给后续的层级、节点、样式和布局命令，可以让整个工作流始终
基于已捕获的页面。截图和视觉对比命令始终使用最新页面。

安装后的 MCP Server 会向 Codex、OpenCode 和 Claude Code 提供相同的能力。配套 Skill 会引导
AI 完成 App 发现、快照复用、节点选择、运行时检查、截图、视觉对比和临时表现验证。

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
- [astrolabe-runtime-ios](https://github.com/regulusleow/astrolabe-runtime-ios)：仅用于
  Debug 构建的 UIKit Runtime SDK。
- [astrolabe-runtime-android](https://github.com/regulusleow/astrolabe-runtime-android)：
  仅用于 Debug 构建的 Android View Runtime SDK。

Astrolabe Host 直接使用共享协议，不依赖具体平台的 Runtime 实现 Package。

## 路线图

- 支持 Jetpack Compose Runtime 检查。
- 集成更多 AI 编码平台。

## 许可证

Astrolabe 使用 [Apache License 2.0](LICENSE) 许可。派生自第三方项目的组件仍受其原始许可证
约束，详见 [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES)。
