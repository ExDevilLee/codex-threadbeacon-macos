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
            "服务异常日志不可用，429/503 状态可能缺失",
            "任务数据库不可用",
            "Codex 任务数据库不可用",
            "未找到 Codex CLI，请先安装 Codex CLI，或确认它位于受支持的安装目录。",
            "当前 Codex CLI 不支持恢复归档任务，请升级 Codex CLI 后重试。",
            "Codex CLI 未能恢复该任务。"
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
