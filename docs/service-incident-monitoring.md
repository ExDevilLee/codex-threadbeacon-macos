# 服务异常监控

## 结论

ThreadBeacon 可以在不接管 Codex 任务、不读取会话正文的前提下，从本机只读日志中识别
当前可见主任务的结构化 HTTP 4xx/5xx 异常、自动重试与最终失败，以及明确记录的所选模型容量错误。

这个能力补充了 rollout 状态推导。检测到新的主任务终止型异常 episode 后，App 会记录固定恢复提示，
但当前版本禁用外部 `codex exec resume` 自动发送，并将记录标记为“未发送：需要 macOS Accessibility 授权”。
HTTP 503 明确排除，其他结构化 HTTP 4xx/5xx 和模型容量异常均可记录。启动时已有的历史异常只登记不发送，同一
episode 每次运行只记录一次。授权等待目前也没有可靠数据源。

## 真实验证记录

2026-07-20 使用一个真实 Codex 主任务进行现场验证：ThreadBeacon 正确把结构化 HTTP 400
关联到可见主任务，并显示红色 `Service failed` 状态、`HTTP 400` 详情和异常持续时间。
该验证同时确认 400 状态不会被 rollout 中可能存在的通用完成事件覆盖。原始会话 ID、任务
标题和日志正文不进入仓库或公开文档；截图仅作为本地验证证据保留。

## 数据源

App 以 SQLite read-only 模式打开：

```text
~/.codex/logs_2.sqlite
```

查询限定当前可见任务 ID，并只允许以下 target：

| Target | 提取字段 | 用途 |
| --- | --- | --- |
| `codex_http_client::default_client` | turn ID、HTTP 状态、时间 | 识别异常与同 turn 恢复 |
| `codex_core::responses_retry` | turn ID、重试次数与上限、时间 | 显示自动重试进度 |
| `codex_core::session::turn` | turn ID、最终 HTTP 状态、模型容量错误、时间 | 识别终止失败 |

`codex_http_client::transport` 被明确排除，因为它可能包含完整请求上下文。查询也不选择
feedback tags、工具输出或其他日志 target。

## 状态规则

| 证据 | 展示 | 提示音 |
| --- | --- | --- |
| 出现结构化 HTTP 4xx/5xx（不含 503） | 红色 `error`，显示 HTTP 状态 | 每个 turn episode 一次异常音 |
| 429/503 后仍在自动重试 | 黄色 `warning`，显示 HTTP 状态和可用的 `n/limit` | 每个 turn episode 一次异常音 |
| 同 turn 后续出现 200 | 清除 warning，回到 rollout 推导状态 | 不补播声音 |
| 重试耗尽并出现 `Turn error` | 红色 `error` | 同 episode 已提醒则不重复播放 |
| 出现明确的所选模型容量 `Turn error` | 红色 `error`，显示“所选模型容量已满” | 每个 turn episode 一次异常音 |
| 更晚出现新的 `task_started` | 清除旧 incident | 新 turn 若再次异常，视为新 episode |

服务 incident 优先于 rollout 的 `task_complete`。这是因为失败 turn 也可能写入通用
`task_complete`；若不覆盖，会把真实失败误报为完成并播放错误的完成音。

恢复提示只使用固定文本，不读取或拼接会话正文；当前不会启动外部 CLI，不改变异常状态，
也不阻塞后续刷新。Accessibility 方案 A 完成授权、定位和结果确认 POC 后，才会评估启用发送。

### Codex App 内可见的恢复

外部 `codex exec resume` 走的是独立 CLI 执行通道，不能保证 Codex App 当前窗口和侧边栏同步显示
消息，因此当前版本不调用它。若要达到“Codex App 会话中可见并继续执行”的效果，需要通过 macOS
Accessibility 控制 Codex App 的输入框和发送动作；这要求用户在系统设置中单独授权 ThreadBeacon。
没有该授权时，App 只记录未发送，不伪装成已完成 Codex App 内恢复。

方案 A 的研究记录见 [`accessibility-recovery-poc.md`](accessibility-recovery-poc.md)。

## 隐私边界

- 原始白名单日志行仅在一次刷新解析期间存在，不进入 `ThreadSnapshot`、界面或本地偏好。
- App 只保留 turn episode ID、HTTP 状态、重试进度、阶段和时间。
- UI 不显示供应商 URL、request ID、完整请求、日志正文或会话内容。
- 日志数据库读取失败时，App 降级为不显示 incident，不影响现有任务列表。

## 已知限制

- `logs_2.sqlite` 是 Codex 内部滚动日志，不是稳定公开 API，字段、target 或日志形状可能
  随版本变化。
- 日志轮转后，较早的异常证据可能消失。
- 当前只接受白名单 target 中明确的 HTTP 4xx/5xx 结构化形态和精确的模型容量 `Turn error`，不把
  2xx、静默、超时或宽泛正文关键词推断为服务异常。日志轮转后，
  过去的异常仍可能无法追溯；现场验证只证明验证时刻的结构化日志链路，不代表历史日志永久可查。
- 该能力不能识别授权请求、用户输入等待或所有失败类型。

## 验证

自动测试覆盖：

- 503 重试耗尽转为 `error`。
- 429 活跃重试转为 `warning`。
- 结构化 400 请求完成记录立即转为 `error`。
- 同 turn 200 清除 warning。
- 明确的所选模型容量错误转为 `error`，且不伪造 HTTP 状态。
- `transport` target 即使包含 429 也被忽略。
- incident 覆盖误导性的 `task_complete`。
- 同 episode 只产生一次异常提示音。
- 新的非 503 终止型 HTTP episode 和模型容量异常只记录一次未发送恢复提示，启动时历史 episode 不发送；HTTP 503 不触发恢复提示。

运行：

```bash
./script/test.sh
./script/build_and_run.sh --verify
./script/probe.sh
```
