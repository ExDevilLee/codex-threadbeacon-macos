# App Server 只读探针

该目录用于验证独立 `codex app-server` 是否能读取或订阅 Codex Desktop 主任务状态，
不属于 ThreadBeacon 正式运行时。

探针只发送以下请求：

- `initialize`
- `initialized`
- `thread/list`
- `thread/loaded/list`
- `thread/read`，且 `includeTurns` 固定为 `false`

它不会调用 `thread/resume`、`turn/start`、审批响应或文件写入接口。输出只保留线程 ID、
父线程 ID、来源、状态和通知方法等元数据，不输出标题、cwd、消息正文或 turn items。

运行一次快照：

```bash
node Tools/AppServerProbe/probe.mjs
```

持续观察通知 30 秒：

```bash
node Tools/AppServerProbe/probe.mjs --watch-seconds 30
```
