import Foundation
import ThreadBeaconCore

let dataSourceHealthTests = [
    TestCase(name: "data source health is healthy when every used source succeeds") {
        let report = healthReport()

        try expect(report.overallStatus == .healthy, "successful sources should be healthy")
        try expect(report.summary == "数据源正常", "healthy report should use stable summary")
    },
    TestCase(name: "data source health degrades when an optional source fails") {
        let report = healthReport(
            renameIndex: .degraded("Rename 索引不可用，已回退原始标题")
        )

        try expect(report.overallStatus == .degraded, "optional failure should degrade the report")
        try expect(report.summary == "部分数据源降级", "degraded report should explain reduced trust")
    },
    TestCase(name: "data source health becomes unavailable when the task database fails") {
        let report = healthReport(
            taskDatabase: .unavailable("任务数据库不可用"),
            renameIndex: .notUsed,
            rollout: .notUsed,
            serviceLogs: .notUsed
        )

        try expect(report.overallStatus == .unavailable, "core failure should make the report unavailable")
        try expect(report.summary == "任务数据不可用", "unavailable report should use stable summary")
        try expect(!report.summary.contains("/Users/"), "summary must not expose local paths")
    },
    TestCase(name: "data source health respects a degraded task database") {
        let report = healthReport(taskDatabase: .degraded("部分任务字段不可用"))

        try expect(report.overallStatus == .degraded, "degraded core source should degrade the report")
    },
    TestCase(name: "data source health records the latest successful refresh") {
        let refreshedAt = Date(timeIntervalSince1970: 123)
        let report = healthReport().recordingSuccessfulRefresh(at: refreshedAt)

        try expect(
            report.lastSuccessfulRefreshAt == refreshedAt,
            "successful refresh should be attached without changing source states"
        )
    },
    TestCase(name: "data source status exposes stable labels and details") {
        let degraded = DataSourceHealthStatus.degraded("已使用安全回退")

        try expect(DataSourceHealthStatus.healthy.displayText == "正常", "healthy label should be stable")
        try expect(degraded.displayText == "部分降级", "degraded label should be stable")
        try expect(degraded.detailText == "已使用安全回退", "degraded detail should be retained")
        try expect(DataSourceHealthStatus.notUsed.displayText == "未使用", "unused label should be explicit")
        try expect(DataSourceHealthStatus.notUsed.detailText == nil, "unused source should have no error detail")
    }
]

private func healthReport(
    taskDatabase: DataSourceHealthStatus = .healthy,
    renameIndex: DataSourceHealthStatus = .healthy,
    rollout: DataSourceHealthStatus = .healthy,
    serviceLogs: DataSourceHealthStatus = .healthy
) -> DataSourceHealthReport {
    DataSourceHealthReport(
        taskDatabase: taskDatabase,
        renameIndex: renameIndex,
        rollout: rollout,
        serviceLogs: serviceLogs,
        rolloutSuccessCount: 2,
        rolloutFailureCount: 0,
        lastSuccessfulRefreshAt: nil
    )
}
