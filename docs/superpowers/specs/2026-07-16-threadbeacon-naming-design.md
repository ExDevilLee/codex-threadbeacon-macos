# ThreadBeacon 命名与迁移设计

## 决策

项目正式名称确定为 `ThreadBeacon`。

- 英文产品名：`ThreadBeacon`
- 中文功能描述：`macOS 上的 Codex 任务状态窗`
- 英文副标题：`A glanceable Codex task monitor for macOS`
- 中文昵称：“Codex 红绿灯”，只作为功能类比，不再作为正式产品名
- 计划中的 GitHub repository slug：`threadbeacon`

截至 2026-07-16，GitHub repository name search 和 Mac App Store search 未发现
完全同名的 `ThreadBeacon`。这只能降低明显重名风险，不等同于商标或所有司法辖区的
完整名称检索；公开发布前仍需再次增量检查。

## 命名理由

`Thread` 对应 App 集中显示的 Codex 主任务线程，`Beacon` 对应一眼可见的状态信号。
名称不直接使用 `Codex` 作为品牌主体，降低与其他 Codex Traffic Light 项目的混淆，
同时通过副标题保留产品用途和搜索可发现性。

现有 `B1 Graphite / Code Beacon` 图标已经采用代码符号与纵向状态灯，因此不需要因
改名重新设计图标。

## 迁移范围

本次采用完整改名，不只修改窗口标题。原因是项目仍处于 POC 和私有仓库阶段，尚未
形成需要兼容的公开 package、命令行接口或安装用户群。

### 用户可见名称

- README 标题和开头描述改为 `ThreadBeacon`。
- App bundle 改为 `ThreadBeacon.app`。
- 窗口标题、`CFBundleName` 和 `CFBundleDisplayName` 改为 `ThreadBeacon`。
- 构建、运行、卸载和验证命令中的 App 与进程名称同步更新。
- ROADMAP、隐私说明和安全文档使用 `ThreadBeacon` 作为产品名。
- prior-art 文档保留旧名称和旧仓库 URL，作为检索结论与开发时间线证据；新增命名
  决策说明，不改写历史事实。

### 技术标识

- Swift package：`ThreadBeacon`
- 主 executable target 和 binary：`ThreadBeacon`
- core target：`ThreadBeaconCore`
- test target：`ThreadBeaconTests`
- probe target：`ThreadBeaconProbe`
- Swift 类型、目录、import 和脚本引用与 target 名称同步迁移。
- bundle identifier：`io.github.exdevillee.threadbeacon`

更换 bundle identifier 会让 macOS 将其视为新的 App 身份，当前通过 `UserDefaults`
保存的窗口置顶选项可能发生一次性重置。项目尚未公开发布，因此接受该 POC 阶段的
一次性重置，不增加旧 bundle identifier 的迁移代码。

### GitHub

- 私有仓库从 `codex-traffic-light` 重命名为 `threadbeacon`。
- 重命名前确认目标 slug 当时仍可用。
- 更新本地 `origin` URL，并验证 fetch、push 和默认分支仍为 `main`。
- GitHub 通常会重定向旧 repository URL，但 README 和内部链接仍应改为新 URL；
  prior-art 文档中的旧提交链接可保留，并验证重定向有效。

## 明确不变的内容

- 不改变任务状态推导、刷新间隔、排序、subagent 过滤或 rename 标题读取逻辑。
- 不改变本地只读和最小数据访问原则。
- 不修改 App 图标视觉设计。
- 不在本次改名中实现 ROADMAP 候选功能。
- 不把 `Codex` 从用途说明、数据路径和非官方声明中删除。

## 验收标准

1. `Package.swift`、Swift target、module import、目录、脚本和测试统一使用新技术标识。
2. 构建产物为 `dist/ThreadBeacon.app`，可执行进程名为 `ThreadBeacon`。
3. App 窗口、Finder 和 bundle metadata 显示 `ThreadBeacon`。
4. 全部现有测试、probe、App 构建启动和图标 bundle 验证通过。
5. README、README-EN、ROADMAP、PRIVACY 和 SECURITY 的当前产品名称一致。
6. 全仓搜索中，旧名称只允许出现在 prior-art 历史说明或必要的迁移记录中。
7. GitHub 私有仓库名称、description、README 链接和本地 `origin` 一致。
8. 仓库保持 private；本次改名不改变可见性。

## 回退方式

代码改名应形成一个独立提交，GitHub repository rename 在代码验证通过后执行。如果
远端重命名失败或目标 slug 被占用，代码提交暂不推送，先恢复或重新决定 repository
slug；不采用代码名与仓库名长期不一致的状态。
