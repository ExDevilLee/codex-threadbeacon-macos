# 隐私说明

## 数据范围

ThreadBeacon 只在本机读取以下 Codex 数据：

- `~/.codex/state_5.sqlite` 中未归档主任务的 ID、标题、更新时间、累计 Token 和
  rollout 路径。
- `~/.codex/session_index.jsonl` 中与任务 ID 对应的最新 rename 名称。
- rollout JSONL 尾部的事件类型、时间戳和 Token 数字字段，用于判断状态并计算会话
  累计与当前 turn 概览。

App 不提取 reasoning summary、用户消息或助手回复正文。

## 数据处理

- 数据只在当前进程内存中用于生成界面状态。
- App 不上传数据，不启动网络服务，不写入或修改 Codex 数据。
- App 不使用 Accessibility、通讯录、位置、相机或麦克风权限。
- App 只在本地持久化窗口是否钉在最前面、提示音开关与选择，以及最多 256 个完成事件
  ID。事件 ID 只包含主任务 ID、完成时间和事件类别，不包含任务标题、消息正文、
  reasoning、命令或文件内容。

## 已知边界

Codex 本地文件格式不是稳定公开 API，未来版本可能改变字段或路径。读取失败时 App 会
显示错误或未知状态，不会尝试修复或改写源数据。音频播放失败不会影响状态读取。
