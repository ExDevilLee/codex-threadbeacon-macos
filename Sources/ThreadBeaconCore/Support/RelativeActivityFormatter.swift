import Foundation

public enum RelativeActivityFormatter {
    public static func string(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case 0..<60:
            return "刚刚"
        case 60..<3_600:
            return "\(seconds / 60) 分钟前"
        case 3_600..<86_400:
            return "\(seconds / 3_600) 小时前"
        default:
            return "\(seconds / 86_400) 天前"
        }
    }
}
