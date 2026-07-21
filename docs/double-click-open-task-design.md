# 双击主任务并在 Codex App 中打开：设计

## 背景

ThreadBeacon 已经能够集中显示 Codex Desktop 与 Codex CLI 主任务的状态，但用户发现需要处理的
任务后，仍要切回 Codex App 并在侧边栏手动寻找。自动恢复阶段已经验证 `codex://threads/<id>`
可以按任务 ID 打开活跃会话，并可通过 macOS Accessibility 检查当前输入框草稿、核对顶部
rename 标题。

本功能把这条已验证链路开放为主列表的用户主动操作，补齐“查看状态 -> 进入对应任务”的闭环。

## 目标

- 双击未归档的主任务行，在 Codex App 中打开该任务。
- 使用任务 ID 导航；rename 标题只承担目标页面二次确认，不用标题代替 ID 定位。
- 切换前保护 Codex 当前输入框中的草稿，无法判断是否安全时停止。
- 未授权或打开失败时提供简体中文和英文反馈。
- 操作只打开任务，不输入、不发送消息，也不改变 Codex SQLite。

## 非目标

- 不支持双击 Subagent 行。
- 不打开已归档任务，也不重新启用“恢复为激活状态”。
- 不在未授权时绕过 Accessibility 直接打开 deep link。
- 不自动申请 Accessibility 权限；只能由用户进入系统设置授权。
- 不恢复操作前的原前台 App；这是自动恢复链路的独立后续功能。
- 不调用 Codex 私有 IPC，不增加外部 CLI fallback。

## 方案比较

### 方案 A：复用现有受保护的 Accessibility 目标选择链路（采用）

主列表把双击事件交给 `AccessibilityPermissionStore`。Store 检查授权和并发状态后，以
`.userInitiated` 模式调用 `SystemAccessibilityTargetSelector`。Selector 继续负责草稿预检、
任务 ID deep link、rename 标题和唯一输入框确认。

优点是复用已经过同名任务、草稿冲突和真实发送 POC 验证的路径；错误语义也与自动恢复诊断一致。
代价是用户需要单独授权 Accessibility，并继续依赖版本敏感的 Codex AX 结构。

### 方案 B：双击后直接打开 deep link

不要求 Accessibility 权限，只调用 `NSWorkspace.open`。实现简单，但无法在切换前确认当前 Codex
输入框是否有草稿，也无法确认打开后的标题和输入框结构。该方案会丢失现有失败关闭保护，不采用。

### 方案 C：修改 SQLite 或调用 Codex 私有 IPC

可能绕过 UI 自动化，但会扩大写入范围、引入版本和数据一致性风险，也违反当前只读优先边界，
不采用。

## 交互设计

1. 用户双击未归档主任务行。
2. 单击行为保持不变；任务行内的 Subagent、Token info 等按钮继续优先处理自身点击。
3. 操作执行期间忽略同一行的重复双击，避免与自动恢复或另一次打开操作并发。
4. 成功时 Codex App 成为前台并显示目标任务；ThreadBeacon 不再弹出成功提示。
5. 失败时 ThreadBeacon 显示本地化提示：
   - 未授权：说明需要 Accessibility 权限，并提供“打开辅助功能设置”。
   - 当前输入框有草稿：说明为保护草稿已停止切换。
   - 输入框或标题身份不唯一、索引不可用、Codex 未运行、deep link 失败：显示对应原因。
6. 已归档任务和 Subagent 行不触发打开，也不静默尝试恢复。

任务行增加本地化 Tooltip 与 Accessibility 描述，说明“双击在 Codex App 中打开”；已归档行不提供
该操作提示。

## 组件边界

### `ThreadBeaconCore`

增加一个纯值策略，描述主任务是否允许发起打开：未归档且当前没有其他 Accessibility 交互时才
允许。策略不接触 AppKit，使用单元测试覆盖归档和并发边界。

### `AccessibilityPermissionStore`

增加发布版可调用的“打开任务”入口和独立结果状态：

- 刷新真实授权状态。
- 未授权或已有 Accessibility 操作时失败关闭。
- 调用现有 `SystemAccessibilityTargetSelector`，不触发发送器。
- 操作完成后清理进行中状态，向主窗口返回选择结果。

Debug 设置页现有手工目标验证继续保留；新入口不依赖 Debug UI，也不授予发送资格。

### `ContentView` 与 `ThreadRowView`

- `ThreadBeaconApp` 将同一个 `AccessibilityPermissionStore` 注入主窗口。
- `ThreadRowView` 暴露独立双击回调；归档任务传入禁用状态。
- `ContentView` 发起打开操作，并把失败结果转换为本地化 Alert。
- 不把导航行为放进 `ThreadStatusStore`，避免 Core 状态加载与 AppKit 交互耦合。

### 本地化

在 String Catalog 中增加 Tooltip、权限说明、系统设置按钮和打开失败提示。现有 Debug 目标验证
文案若语义一致，应复用同一映射，避免主窗口与设置页对相同错误给出不同描述。

## 数据流

```text
双击主任务行
  -> 主任务/归档/并发策略检查
  -> Accessibility 授权检查
  -> 当前 Codex composer 草稿预检
  -> codex://threads/<thread-id>
  -> 顶部 rename 标题唯一匹配
  -> 目标 composer 唯一确认
  -> 成功结束，不输入、不发送
```

任务 ID 是导航依据。Accessibility 树目前不暴露任务 ID，因此打开后的 AX 校验只能确认 rename
标题和目标页面结构；已有两个同名任务交换列表位置的真实 POC 继续作为 deep link 按 ID 路由的
兼容性证据。

## 失败与安全边界

- Accessibility 未授权或授权被撤销：停止，不自动弹出系统授权请求。
- Codex App 未运行：停止并提示；本阶段不自动启动 Codex 后再次尝试。
- 当前 composer 有草稿、不可读或数量不唯一：在 deep link 前停止。
- session index 无法读取或缺少目标 rename 标题：停止。
- deep link 打开失败、目标标题或 composer 不唯一：停止并提示。
- 已有自动恢复、Debug 验证或任务打开操作：拒绝新的打开请求。
- 失败后不重试，不回退到 CLI，也不记录任务标题、会话正文或本机路径。

## 测试与验收

### 自动测试

- 活跃、未归档主任务允许发起打开。
- 已归档任务被策略拒绝。
- 已有 Accessibility 操作时拒绝新的双击打开。
- 未授权时不调用目标选择器。
- 打开入口只调用目标选择器，不调用恢复发送器。
- 现有任务 ID deep link、同名 rename 标题、草稿冲突和输入框唯一性测试保持通过。
- 简体中文与英文错误映射覆盖所有 `AccessibilityTargetSelectionResult`。

### 手工验证

1. 双击普通主任务，Codex 打开正确会话。
2. 创建两个同名活跃任务并交换侧边栏位置，双击指定行仍按 ID 打开正确任务。
3. 在当前 Codex 输入框保留草稿，双击另一任务时停止，草稿和当前会话不变。
4. 撤销 Accessibility 权限后双击，ThreadBeacon 不切换任务，并可打开系统辅助功能设置。
5. 双击已归档收藏任务和 Subagent 行，不触发导航。
6. 双击期间重复操作，不产生并发导航。
7. 浅色、深色、简体中文、英文及最小窗口宽度下，Tooltip 和 Alert 文案完整显示。

## 发布边界

该功能继续依赖 Codex 的非公开稳定 deep link 与 Accessibility 结构。若 Codex 更新导致身份确认
失败，ThreadBeacon 应显示失败而不是猜测目标。功能不改变自动恢复的默认关闭状态，也不扩大
本地数据读取和网络范围。
