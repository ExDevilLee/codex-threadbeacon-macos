# 任务行元数据分隔线设计

## 状态

- 日期：2026-07-17
- 状态：已确认
- 关联功能：Feature 5 Subagent 数量标记视觉微调

## 目标

在任务标题右侧同时出现 Subagent 数量和 Token 概览时，用一条短竖线明确区分两个
信息分组，降低连续数字造成的阅读混淆。

## 已确认设计

使用 SwiftUI 原生竖向 `Divider`，不使用文字字符 `｜`。

显示顺序：

```text
Subagent 图标 + 数量 | Token 数量 + info
```

显示规则：

- Subagent 数量和 Token 概览同时存在时显示分隔线。
- 缺少任一信息时不显示分隔线，也不保留空白占位。
- 分隔线高度约 12pt，使用系统 separator 颜色并自动适配 Light / Dark。
- 分隔线不响应点击，且从 Accessibility tree 中隐藏。
- 保持当前标题单行截断、Token 固定尺寸和 info 按钮行为不变。

## 实现边界

仅修改 `ThreadRowView` 的标题行布局。分隔线使用条件渲染，不新增持久化状态、模型
字段、Formatter 或数据查询。

建议代码形态：

```swift
if snapshot.subagentCount > 0, snapshot.tokenUsage != nil {
    Divider()
        .frame(height: 12)
        .accessibilityHidden(true)
}
```

实际实现仍复用现有 `SubagentCountFormatter.label(for:)` 判断 Badge 是否可见，避免 UI
条件与 Formatter 的 `count > 0` 规则发生漂移。

## 验证

- 有 Subagent 和 Token 的行显示一条短竖线。
- 只有 Token 的行不显示竖线。
- 默认窗口宽度下，标题、Subagent、分隔线、Token 和 info 不重叠。
- Dark 外观下分隔线清晰但不抢夺状态灯注意力。
- 完整测试和 App 构建通过。
