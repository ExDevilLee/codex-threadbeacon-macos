import Foundation

enum RelativeTimeFormatter {
    static func statusDuration(since date: Date, now: Date = Date(), locale: Locale = Locale(identifier: "zh-Hans")) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case 0..<5:
            return AppLocalization.string("刚刚", locale: locale)
        case 5..<60:
            return AppLocalization.formatted("持续 %lld 秒", locale: locale, seconds)
        case 60..<3_600:
            return AppLocalization.formatted("持续 %lld 分钟", locale: locale, seconds / 60)
        case 3_600..<86_400:
            return AppLocalization.formatted("持续 %lld 小时", locale: locale, seconds / 3_600)
        default:
            let days = seconds / 86_400
            return days == 1
                ? AppLocalization.string("持续 1 天", locale: locale)
                : AppLocalization.formatted("持续 %lld 天", locale: locale, days)
        }
    }
}
