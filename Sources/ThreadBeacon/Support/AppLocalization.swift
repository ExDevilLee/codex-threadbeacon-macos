import Foundation

enum AppLocalization {
    #if SWIFT_PACKAGE
    private static let bundle = Bundle.module
    #else
    private static let bundle = Bundle.main
    #endif

    static func string(_ source: String, locale: Locale) -> String {
        let language = locale.language.languageCode?.identifier == "zh" ? "zh-Hans" : "en"
        if let path = bundle.path(forResource: language, ofType: "lproj"),
           let localizedBundle = Bundle(path: path) {
            return NSLocalizedString(source, bundle: localizedBundle, comment: "")
        }
        return source
    }

    static func formatted(_ source: String, locale: Locale, _ arguments: CVarArg...) -> String {
        String(format: string(source, locale: locale), locale: locale, arguments: arguments)
    }

    static func relativeActivity(since date: Date, now: Date = Date(), locale: Locale) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case 0..<60:
            return string("刚刚", locale: locale)
        case 60..<3_600:
            return formatted("%lld 分钟前", locale: locale, seconds / 60)
        case 3_600..<86_400:
            return formatted("%lld 小时前", locale: locale, seconds / 3_600)
        default:
            return formatted("%lld 天前", locale: locale, seconds / 86_400)
        }
    }

    static func userFacing(_ source: String, locale: Locale) -> String {
        guard locale.language.languageCode?.identifier != "zh" else { return source }

        let catalogBackedMessages: Set<String> = [
            "线程数量必须大于 0",
            "Codex 数据库包含无法读取的线程记录",
            "Codex 日志数据库包含无法读取的记录",
            "无法打开数据库",
            "未知 SQLite 错误",
            "Rename 索引不可用，已回退原始标题",
            "服务异常日志不可用，服务错误状态可能缺失",
            "任务数据库不可用",
            "Codex 任务数据库不可用",
            "未找到 Codex CLI，请先安装 Codex CLI，或确认它位于受支持的安装目录。",
            "当前 Codex CLI 不支持恢复归档任务，请升级 Codex CLI 后重试。",
            "Codex CLI 未能恢复该任务。",
            "Codex CLI 已接受提示词（进程退出码 0）",
            "Codex App 已确认恢复消息并启动新任务",
            "发送恢复提示失败",
            "未找到 Codex CLI",
            "Codex CLI 执行失败",
            "无法启动 Codex CLI",
            "需要 macOS Accessibility 授权",
            "无法安全定位并确认目标任务",
            "无法读取目标任务 rollout",
            "目标输入框已有草稿",
            "目标输入框不可写",
            "无法写入恢复提示词",
            "恢复提示词回读不一致",
            "无法确认目标输入框已清空",
            "发送按钮执行失败",
            "已触发发送，但 rollout 未在时限内确认",
            "已有恢复操作正在执行，或辅助功能权限已失效"
        ]
        if catalogBackedMessages.contains(source) {
            return string(source, locale: locale)
        }

        let prefixedTranslations: [(String, String)] = [
            ("读取 Codex 数据库失败：", "读取 Codex 数据库失败：%@"),
            ("读取 Codex 日志数据库失败：", "读取 Codex 日志数据库失败：%@"),
            ("无法开启登录时启动：", "无法开启登录时启动：%@"),
            ("无法关闭登录时启动：", "无法关闭登录时启动：%@"),
            ("恢复失败：", "恢复失败：%@"),
            ("无法启动 Codex CLI：", "无法启动 Codex CLI：%@")
        ]
        for (prefix, catalogKey) in prefixedTranslations where source.hasPrefix(prefix) {
            return formatted(catalogKey, locale: locale, String(source.dropFirst(prefix.count)))
        }

        let sendButtonCountPrefix = "发送按钮候选数量异常："
        if source.hasPrefix(sendButtonCountPrefix),
           let count = Int(source.dropFirst(sendButtonCountPrefix.count)) {
            return formatted("发送按钮候选数量异常：%lld", locale: locale, count)
        }

        let circuitPrefix = "连续自动恢复已达到 "
        let circuitSuffix = " 次，已停止发送"
        if source.hasPrefix(circuitPrefix), source.hasSuffix(circuitSuffix) {
            let counts = source
                .dropFirst(circuitPrefix.count)
                .dropLast(circuitSuffix.count)
                .split(separator: "/")
            if counts.count == 2,
               let attempts = Int(counts[0]),
               let limit = Int(counts[1]) {
                return formatted(
                    "连续自动恢复已达到 %lld/%lld 次，已停止发送",
                    locale: locale,
                    attempts,
                    limit
                )
            }
        }

        let rolloutMarker = " 个任务的 Rollout 不可用，状态可能回退"
        if source.hasSuffix(rolloutMarker),
           let count = Int(source.dropLast(rolloutMarker.count)) {
            return count == 1
                ? string("1 个任务的 Rollout 不可用，状态可能回退", locale: locale)
                : formatted("%lld 个任务的 Rollout 不可用，状态可能回退", locale: locale, count)
        }

        return source
    }
}
