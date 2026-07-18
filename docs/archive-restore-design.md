# 已归档收藏恢复设计

## 背景与目标

ThreadBeacon 已能收藏主任务，并在任务被 Codex 归档后继续以只读方式展示。下一阶段补齐
收藏闭环：用户可以从 ThreadBeacon 请求 Codex 将已归档收藏恢复为激活状态。

本功能只调用 Codex 官方 CLI，不直接修改 `~/.codex/state_5.sqlite`。恢复成功后继续保留
ThreadBeacon 收藏状态，不改变置顶和忽略规则。当前不自动打开 Codex 会话，因为真实验证
确认恢复后的旧会话可能无法通过 Codex App 深链加载。

## 当前产品状态

底层 POC 已验证 `codex unarchive` 可以取消归档，但这不足以完成用户所需的“恢复后回到
Codex App 侧边栏并打开任务”。当前 Codex App 不会可靠更新侧边栏排序，任务深链也可能
提示找不到会话，因此 ThreadBeacon 已通过 `ArchiveRestoreAvailability` 暂时隐藏右键
恢复入口。

保留 CLI 解析、恢复服务、Store 编排和测试，作为后续重新启用基础。重新启用的验收条件是
Codex App 提供可靠的公开接口，能够同时恢复侧边栏可见性并打开任务。ThreadBeacon 不直接
修改 `recency_at_ms`，也不调用 Codex App 私有 IPC。

## 范围

已完成的底层 POC 包含：

- 仅为“已归档且已收藏”的主任务设计`恢复为激活状态`右键操作；当前受可用性开关控制，
  入口不显示。
- 执行前显示确认对话框，明确本操作会调用本机 Codex CLI 修改归档状态。
- 异步执行 `codex unarchive <SESSION_ID>`，避免阻塞窗口和自动刷新。
- 执行期间防止同一任务重复提交恢复操作。
- 成功后保留收藏并自动刷新任务列表。
- 失败时保留归档状态，展示可理解的失败原因。

首版不包含：

- 直接写入 Codex SQLite。
- 恢复后自动打开或切换到对应 Codex 会话。
- 批量恢复归档任务。
- 在 Settings 中手动配置 Codex CLI 路径。
- App Sandbox、签名分发和 Mac App Store 兼容改造。

## 方案选择

采用“独立 CLI 解析器 + `Process` 参数化执行”方案。

不固定当前机器上的 NVM 路径，因为 Node 或 Codex 升级会使路径变化；也不通过
`zsh -lic` 执行恢复命令，避免加载用户 Shell 初始化脚本带来的副作用和不可预测耗时。

CLI 解析顺序：

1. 当前进程 `PATH` 中可执行的 `codex`。
2. Homebrew 与常见用户安装目录中的稳定路径。
3. `~/.nvm/versions/node/*/bin/codex` 中可执行的候选，优先选择版本号最高的 Node 目录。

解析结果必须是本机存在且可执行的文件。恢复时使用 `Foundation.Process`，将
`unarchive` 和任务 UUID 作为独立参数传入，不拼接 Shell 命令。启动子进程时把 Codex
可执行文件所在目录放到子进程 `PATH` 首位，确保 NVM 安装的 Codex 脚本能通过
`/usr/bin/env node` 找到同目录 Node，同时不修改 ThreadBeacon 自身环境。

## 组件边界

### `CodexCLIResolver`

负责发现 Codex CLI，不执行恢复。输入为进程环境、用户目录和文件系统候选；输出为可执行
文件 URL，或者结构化的“未找到 CLI”错误。候选生成和优先级应可在测试中注入。

### `CodexArchiveRestoring`

定义恢复操作的最小接口。生产实现使用解析出的 CLI 启动 `Process`，捕获退出码和有限长度的
标准错误。测试使用可控实现验证 Store 和 UI 状态，不真正修改 Codex 数据。

### `ThreadStatusStore`

维护当前正在恢复的任务 ID、最近一次恢复结果和重复提交保护。恢复成功后继续保留
`favoriteThreadIDs`，并触发一次基线刷新；恢复失败不改变任何列表偏好。

### `ContentView`

只负责交互：显示右键入口、确认对话框、恢复中状态和结果提示，不负责解析 CLI 或启动
进程。

## 交互流程

1. 用户右键已归档收藏，选择`恢复为激活状态`。
2. App 显示确认对话框，包含任务当前标题和`恢复`、`取消`按钮。
3. 用户确认后，该任务进入恢复中状态，菜单操作暂时不可重复触发。
4. 后台调用 Codex CLI。
5. 退出码为 `0` 时自动刷新；SQLite 反映任务已激活后，行内`已归档`标记消失，但收藏
   星标保留。
6. 执行失败时任务保持原状，App 显示错误提示，用户可以再次尝试。

成功只以 CLI 退出码为首要判据；刷新后若数据源仍显示归档，不伪造激活状态，而是继续按
SQLite 真实状态展示。

## 错误处理

错误分为：

- `cliNotFound`：没有发现可执行的 Codex CLI，提示用户先安装 Codex CLI，或确保安装在
  支持的路径。
- `unsupportedCommand`：CLI 帮助或执行结果表明不支持 `unarchive`，提示升级 Codex CLI。
- `executionFailed`：CLI 返回非零退出码，显示经过裁剪和清理的错误信息；若没有可用信息，
  使用统一的恢复失败文案。
- `launchFailed`：进程无法启动，显示本机执行错误，不改变任务状态。

错误提示不得包含完整环境变量、用户 Shell 配置、会话正文或其他任务内容。标准输出和标准
错误只在内存中读取，不持久化。

## 测试策略

测试遵循先失败、后实现：

- CLI 解析器按优先级选择候选，并跳过不存在或不可执行的路径。
- NVM 候选按 Node 版本选择，不依赖当前机器的具体版本号。
- 恢复执行器使用准确的可执行文件、`unarchive` 子命令和任务 ID。
- 非零退出码、启动失败和缺少 CLI 映射为稳定的用户错误。
- Store 在执行期间拒绝同一任务的重复恢复。
- 成功后收藏 ID 保留，并请求刷新。
- 失败后收藏、置顶和忽略偏好均不变化。
- UI 入口只出现在已归档收藏行，确认取消不会执行恢复。

最终运行全量 Core 测试、App 构建启动验证，并使用实际 UI 检查右键入口、确认对话框和取消
路径。真实归档任务的恢复操作由 Lee 在验收时选择是否执行。

## 隐私与发布边界

本功能新增一次本机进程调用，但不新增网络请求、遥测、后台服务或持久化内容。任务 UUID 会
作为本机 Codex CLI 参数传递，不离开本机。公开文档需要同步说明该功能会改变 Codex 的本地
归档状态，并继续明确 ThreadBeacon 不直接写入 Codex 数据库。

## Codex App 打开限制

2026-07-18 使用真实旧会话验证后确认：`codex unarchive` 会更新 `archived`、`archived_at`
与 `updated_at`，但不会更新 Codex App 侧边栏近期排序依赖的 `recency_at_ms`。恢复后的会话
仍可由 App 内部索引读取，但不一定重新出现在侧边栏；`codex://threads/<thread-id>` 在
Codex App `26.715.21425` 上还可能提示找不到会话。外部 CLI `0.144.1` 与 Codex App 内置
CLI `0.145.0-alpha.18` 的对照结果一致。

ThreadBeacon 不直接修改 `recency_at_ms`，也不调用 Codex App 私有 IPC。待 OpenAI 提供可以
可靠恢复并打开旧会话的公开接口后，再重新评估自动打开能力。
