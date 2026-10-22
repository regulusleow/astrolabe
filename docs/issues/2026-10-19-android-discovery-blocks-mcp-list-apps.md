# Android 接入时 MCP list_apps 超时

记录日期：2026-10-19。状态：已复现，待排查、修复；本次仅记录。

## 环境与影响

- 实测使用系统 Homebrew Astrolabe `2.2.3`，不是当前 develop 的源码构建。
- iOS：USB 连接的 iPhone 12，App 为 Litmatch（`com.litatom.Litmatch`），Runtime `2.2.0`。
- Android：USB 连接的 OnePlus 9（ADB 型号 `LE2110`）。当时 App/Runtime 的前后台、暂停及响应状态未完整记录，后续需补齐。
- 影响：Android 接入后，MCP 的整体设备发现超时，导致可正常连接的 iOS App 也无法通过该次 `list_apps` 返回。

## 已有证据

同一会话通过实际连接的 MCP 调用 `list_apps {}`，做了插拔对照：

| Android 状态 | 耗时 | MCP 结果 |
| --- | --- | --- |
| 初始接入 | 达到 30 秒超时门限 | `mcp_adapter_cli_timeout` |
| 用户停用/断开后 | 3,050 ms | 成功发现 USB Litmatch，兼容状态 `compatible`，`diagnostics: []` |
| 用户重新插入后 | 30,040 ms | 再次 `mcp_adapter_cli_timeout`，stdout/stderr 均为空 |

失败消息：

```text
Failure: Astrolabe Host timed out after 30000ms
```

另外，直接执行系统 CLI `astrolabe list-apps --json` 最终可返回 iOS Litmatch，但同次结果包含 Android 诊断：

- `astrolabe_runtime_request_timeout`：读取 Android Runtime 响应超时。
- `android_runtime_unavailable`：未发现可用的 Android Runtime。

系统 `astrolabe doctor --verbose --json` 和 `astrolabe check --client codex` 检查通过；iPhone USB 枚举及配对验证通过。未发现系统安装被源码构建替换或全局注入变量残留。本次排查未修改安装、配置、工程代码，也未操作手机 UI。

## 当前判断与边界

插拔对照确认故障与当时 Android 接入状态相关，不等于 iPhone USB/配对失效。Android 发现或握手等待可能使整体 CLI 超过 MCP Adapter 的 30 秒预算；具体阻塞位置、耗时构成及根因尚未确认，不能推断所有 Android 设备接入都会触发。

已核对系统安装的 `mcp-adapter/dist/inspector-cli.js`：普通命令子进程超时为 `30000ms`，超时返回 `mcp_adapter_cli_timeout`。后续可从工程对应的 `mcp-adapter/src/inspector-cli.ts`、`Sources/AstrolabeAndroidHost/AndroidRuntimeConnectionRegistry.swift` 和多平台发现聚合路径继续追踪；develop 源码与已安装版本应分别核对。

## 后续排查与验收

- 保持 iPhone App 前台不变，记录 Android App/Runtime 状态，重复连接、断开、重新连接对照；本记录尚未覆盖 Android 状态矩阵。
- 分段测量 ADB、socket 枚举、端口转发、协议握手及多平台发现聚合耗时，检查超时与取消的资源清理。
- 根据根因处理设备/平台间失败隔离与超时预算，不预先以调大 MCP 总超时作为修复结论。
- 修复验收：Android Runtime 无响应时，仍能在 MCP 超时前返回正常 iOS App，并提供 Android 诊断；两端 Runtime 正常时均可发现；单独连接任一平台不回归。

本问题留待后续单独排查、修复；不在本次 SwiftUI 开发中顺带修改。
