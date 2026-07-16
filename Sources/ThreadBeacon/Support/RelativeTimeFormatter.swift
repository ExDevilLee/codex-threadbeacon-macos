import Foundation

enum RelativeTimeFormatter {
    static func statusDuration(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case 0..<5:
            return "刚刚"
        case 5..<60:
            return "持续 \(seconds) 秒"
        case 60..<3_600:
            return "持续 \(seconds / 60) 分钟"
        case 3_600..<86_400:
            return "持续 \(seconds / 3_600) 小时"
        default:
            return "持续 \(seconds / 86_400) 天"
        }
    }
}
