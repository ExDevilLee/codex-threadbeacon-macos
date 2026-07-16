import Foundation

public enum TokenCountFormatter {
    public static func string(for value: Int64) -> String {
        if value < 1_000 {
            return String(value)
        }
        if value < 1_000_000 {
            return decimal(Double(value) / 1_000) + "K"
        }
        return decimal(Double(value) / 1_000_000) + "M"
    }

    public static func percent(_ ratio: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.usesGroupingSeparator = false
        return (formatter.string(from: NSNumber(value: ratio * 100)) ?? "0.0") + "%"
    }

    private static func decimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }
}
