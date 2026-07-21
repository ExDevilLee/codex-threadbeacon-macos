# 自动恢复默认提示词语言设计

## 目标

自动恢复规则的内置提示词跟随 ThreadBeacon 当前 App 语言。用户主动保存过的提示词属于自定义
内容，切换语言时必须保持不变。

本功能只改变默认提示词的语言与迁移逻辑，不改变异常分类、默认开关、Accessibility 发送链路、
恢复日志或状态灯语义。

## 默认提示词

简体中文沿用现有文本。English 使用以下默认值：

| 异常类型 | English 默认提示词 |
| --- | --- |
| HTTP 400 | `The previous request was interrupted by an error. Please continue the unfinished task.` |
| HTTP 429 | `The previous request was interrupted by rate limiting. Please continue the unfinished task.` |
| HTTP 503 | `The previous request was interrupted because the service was unavailable. Please continue the unfinished task.` |
| 其他 HTTP 错误 | `The previous request was interrupted by an HTTP error. Please continue the unfinished task.` |
| 模型容量异常 | `The previous request was interrupted due to model capacity limits. Please continue the unfinished task.` |

`跟随系统`继续使用现有语言解析规则：系统语言属于中文时使用简体中文，English 使用英文，其他
不支持的系统语言回退英文。

## 数据模型

Core 新增两个稳定枚举：

- `AutoRecoveryPromptLanguage`：`simplifiedChinese`、`english`。
- `AutoRecoveryPromptSource`：`defaultValue`、`custom`。

每条 `AutoRecoveryRule` 持久化 `promptSource`。配置版本从 `1` 升到 `2`：

- 新建规则使用当前 App 语言的默认提示词，并标记为 `defaultValue`。
- 用户点击“保存”后标记为 `custom`，即使保存内容恰好等于某个默认提示词也不再自动切换。
- 单独开启或关闭规则只修改 `isEnabled`，不得改变 `promptSource`。
- 点击“恢复默认”使用当前 App 语言的默认提示词，并重新标记为 `defaultValue`。

## 旧配置迁移

版本 `1` 没有保存提示词来源。解码时按以下规则迁移：

1. 提示词与该异常类型的历史内置简体中文默认值完全一致时，迁移为 `defaultValue`。
2. 其他非空且有效的提示词迁移为 `custom`，不得翻译或覆盖。
3. 缺失或无效规则继续使用安全默认值；自动恢复总开关保持原值，损坏配置仍整体回退为默认关闭。

旧格式无法区分“内置默认值”和“用户手写了完全相同的文本”。本设计优先让历史内置默认值正常
跟随语言，这是唯一有信息依据且影响范围最小的迁移选择。

## 语言切换流程

App 启动时先解析当前 App 语言，再加载自动恢复配置。加载完成后，Store 只更新
`promptSource == defaultValue` 的规则并持久化结果。

运行期间 App 语言变化时执行同一同步动作：

- 默认提示词立即更新为目标语言。
- 自定义提示词保持原文。
- 自动恢复策略立即使用同步后的已保存提示词，不依赖用户打开“自动恢复”页。
- Settings 中未修改的编辑框同步显示新默认值。
- 用户正在编辑但尚未保存的草稿不被覆盖；保存后成为 `custom`，放弃编辑或点击“恢复默认”后再
  回到持久化状态。

## UI 与错误处理

现有界面布局、按钮和字符限制保持不变，不增加额外语言选择器或“默认／自定义”标签。

提示词仍执行非空与最多 500 字符校验。配置解码失败时继续回退到自动恢复总开关关闭的安全默认
状态，不因为语言迁移自动开启任何功能。

## 测试与验收

自动化测试至少覆盖：

- 简体中文与 English 的五类默认提示词。
- 版本 `1` 内置中文文本迁移为默认来源。
- 版本 `1` 非默认文本迁移为自定义来源。
- 默认提示词随语言往返切换，自定义提示词保持不变。
- 开关规则不改变来源，保存文本标记自定义，恢复默认使用当前语言。
- 版本 `2` 配置持久化往返及损坏配置安全回退。
- `跟随系统`在不支持语言下使用英文默认提示词。

手工验收使用 Settings 在简体中文与 English 间切换，分别观察默认规则、自定义规则、未保存草稿
和“恢复默认”的结果。无需制造真实 HTTP 异常；发送策略使用的提示词由 Core 测试覆盖。

## 非目标

- 不自动翻译用户自定义提示词。
- 不根据 Codex 会话语言选择提示词。
- 不为每条规则提供独立语言设置。
- 不改变真实异常端到端验证计划。
