# 隐私说明

## 数据范围

ThreadBeacon 只在本机读取以下 Codex 数据：

- `~/.codex/state_5.sqlite` 中未归档主任务的 ID、标题、更新时间、累计 Token、rollout
  路径和直接父子关系。用户展开主任务时，还会读取其直接 Subagent 的标题、昵称、角色、
  模型、Reasoning effort、更新时间、累计 Token 和 rollout 路径。
- `~/.codex/session_index.jsonl` 中与主任务或已展开直接 Subagent ID 对应的最新 rename
  名称。
- rollout JSONL 尾部的事件类型、时间戳和 Token 数字字段，用于判断状态并计算会话
  累计与当前 turn 概览。
- `~/.codex/logs_2.sqlite` 中当前可见主任务的少量结构化日志。查询仅允许
  `codex_http_client::default_client`、`codex_core::responses_retry` 和
  `codex_core::session::turn` 三个 target，并只提取 turn ID、HTTP 429/503、重试次数和
  最终失败时间。

App 明确不读取 `codex_http_client::transport`，因为该 target 可能包含完整请求上下文。
App 不提取 reasoning summary、用户消息、助手回复正文、完整请求、供应商 URL 或
request ID，也不读取第二层及更深子任务。原始白名单日志行只在当前刷新过程内用于解析，
不会进入任务快照、界面、偏好设置或事件历史。

## 数据处理

- 数据只在当前进程内存中用于生成界面状态。
- App 不上传数据，不启动网络服务，不写入或修改 Codex 数据。
- App 不使用 Accessibility、通讯录、位置、相机或麦克风权限。
- App 只在本地持久化窗口是否钉在最前面、提示音开关与选择，以及最多 256 个通知事件
  ID。事件 ID 只包含主任务 ID、完成时间或异常 episode ID 与事件类别，不包含任务
  标题、HTTP 状态、消息正文、reasoning、命令、URL、request ID 或文件内容。

## 已知边界

Codex 本地文件格式不是稳定公开 API，未来版本可能改变字段或路径。读取失败时 App 会
降级为无服务异常信息或显示未知状态，不会尝试修复或改写源数据。`logs_2.sqlite` 是滚动
日志，历史异常可能随日志轮转消失；该数据源支持当前验证过的 429/503，不代表可以识别
授权等待或所有错误类型。音频播放失败不会影响状态读取。
