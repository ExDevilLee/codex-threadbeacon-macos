# 色盲安全状态标识默认开启设计

## 目标

将“色盲安全状态标识”改为新安装和尚未保存该偏好的用户默认开启，让主任务与 Subagent
在颜色之外继续使用独立形状表达状态。Settings 开关保留，用户可以随时关闭。

## 兼容边界

- `DisplaySettings.defaultColorBlindSafeStatusIndicators` 从 `false` 改为 `true`。
- `DisplaySettingsRepository` 必须区分 UserDefaults 键不存在与已保存 `false`：
  - 键不存在时使用新的默认值 `true`；
  - 键存在时读取并保留对应 Bool 值。
- 不执行版本迁移，不覆盖已有用户主动保存的选择。
- 不修改状态颜色、图标映射、状态文字、排序或状态推导逻辑。

## 验证

- `DisplaySettings` 无显式参数时默认开启。
- Repository 缺少偏好键时返回开启。
- Repository 已保存 `false` 时仍返回关闭。
- 现有显式开启和持久化往返测试继续通过。
- 中英文 README 与 ROADMAP 明确记录“默认开启、可关闭”。
