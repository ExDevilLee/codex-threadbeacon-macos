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

## 发送消息 POC

`send-message.mjs` 用于验证指定会话的写入链路。默认是 Dry Run：只执行
`thread/resume`，不会发送消息。

```bash
node Tools/AppServerProbe/send-message.mjs \
  --thread-id <THREAD_ID> \
  --message '刚才中断了，请继续'
```

真实发送必须显式增加两个开关：

```bash
node Tools/AppServerProbe/send-message.mjs \
  --thread-id <THREAD_ID> \
  --message '刚才中断了，请继续' \
  --send --confirm-send
```

注意：该 POC 启动的是独立 app-server。它可能把线程加载到独立运行时，不能证明消息会
出现在已经运行的 Codex App 实例侧边栏或当前窗口中；不要对生产任务盲目执行真实发送。

运行一次快照：

```bash
node Tools/AppServerProbe/probe.mjs
```

持续观察通知 30 秒：

```bash
node Tools/AppServerProbe/probe.mjs --watch-seconds 30
```
