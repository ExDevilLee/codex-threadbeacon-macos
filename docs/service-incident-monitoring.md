# 429/503 服务异常监控

## 结论

ThreadBeacon 可以在不接管 Codex 任务、不读取会话正文的前提下，从本机只读日志中识别
当前可见主任务的 HTTP 429/503 自动重试与最终失败。

这个能力补充了 rollout 状态推导，但不改变独立 app-server POC 的结论：不同
app-server 实例仍不能共享 Desktop 运行时事件。授权等待目前也没有可靠数据源。

## 数据源

App 以 SQLite read-only 模式打开：

```text
~/.codex/logs_2.sqlite
```

查询限定当前可见任务 ID，并只允许以下 target：

| Target | 提取字段 | 用途 |
| --- | --- | --- |
| `codex_http_client::default_client` | turn ID、HTTP 200/429/503、时间 | 识别异常与同 turn 恢复 |
| `codex_core::responses_retry` | turn ID、重试次数与上限、时间 | 显示自动重试进度 |
| `codex_core::session::turn` | turn ID、最终 429/503、时间 | 识别重试耗尽 |

`codex_http_client::transport` 被明确排除，因为它可能包含完整请求上下文。查询也不选择
feedback tags、工具输出或其他日志 target。

## 状态规则

| 证据 | 展示 | 提示音 |
| --- | --- | --- |
| 429/503 后仍在自动重试 | 黄色 `warning`，显示 HTTP 状态和可用的 `n/limit` | 每个 turn episode 一次异常音 |
| 同 turn 后续出现 200 | 清除 warning，回到 rollout 推导状态 | 不补播声音 |
| 重试耗尽并出现 `Turn error` | 红色 `error` | 同 episode 已提醒则不重复播放 |
| 更晚出现新的 `task_started` | 清除旧 incident | 新 turn 若再次异常，视为新 episode |

服务 incident 优先于 rollout 的 `task_complete`。这是因为失败 turn 也可能写入通用
`task_complete`；若不覆盖，会把真实失败误报为完成并播放错误的完成音。

## 隐私边界

- 原始白名单日志行仅在一次刷新解析期间存在，不进入 `ThreadSnapshot`、界面或本地偏好。
- App 只保留 turn episode ID、HTTP 状态、重试进度、阶段和时间。
- UI 不显示供应商 URL、request ID、完整请求、日志正文或会话内容。
- 日志数据库读取失败时，App 降级为不显示 incident，不影响现有任务列表。

## 已知限制

- `logs_2.sqlite` 是 Codex 内部滚动日志，不是稳定公开 API，字段、target 或日志形状可能
  随版本变化。
- 日志轮转后，较早的异常证据可能消失。
- 当前只接受已验证的 HTTP 429/503，不把其他状态码、静默、超时或正文关键词推断为
  服务异常。
- 该能力不能识别授权请求、用户输入等待或所有失败类型。

## 验证

自动测试覆盖：

- 503 重试耗尽转为 `error`。
- 429 活跃重试转为 `warning`。
- 同 turn 200 清除 warning。
- `transport` target 即使包含 429 也被忽略。
- incident 覆盖误导性的 `task_complete`。
- 同 episode 只产生一次异常提示音。

运行：

```bash
./script/test.sh
./script/build_and_run.sh --verify
./script/probe.sh
```
