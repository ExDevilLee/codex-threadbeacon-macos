import Foundation

public enum DataSourceHealthStatus: Equatable, Sendable {
    case healthy
    case degraded(String)
    case unavailable(String)
    case notUsed

    public var displayText: String {
        switch self {
        case .healthy:
            "正常"
        case .degraded:
            "部分降级"
        case .unavailable:
            "不可用"
        case .notUsed:
            "未使用"
        }
    }

    public var detailText: String? {
        switch self {
        case let .degraded(message), let .unavailable(message):
            message
        case .healthy, .notUsed:
            nil
        }
    }

    fileprivate var reducesOverallHealth: Bool {
        switch self {
        case .degraded, .unavailable:
            true
        case .healthy, .notUsed:
            false
        }
    }
}

public enum OverallDataSourceHealth: Equatable, Sendable {
    case healthy
    case degraded
    case unavailable
}

public struct DataSourceHealthReport: Equatable, Sendable {
    public let taskDatabase: DataSourceHealthStatus
    public let renameIndex: DataSourceHealthStatus
    public let rollout: DataSourceHealthStatus
    public let serviceLogs: DataSourceHealthStatus
    public let rolloutSuccessCount: Int
    public let rolloutFailureCount: Int
    public let lastSuccessfulRefreshAt: Date?

    public init(
        taskDatabase: DataSourceHealthStatus,
        renameIndex: DataSourceHealthStatus,
        rollout: DataSourceHealthStatus,
        serviceLogs: DataSourceHealthStatus,
        rolloutSuccessCount: Int,
        rolloutFailureCount: Int,
        lastSuccessfulRefreshAt: Date?
    ) {
        self.taskDatabase = taskDatabase
        self.renameIndex = renameIndex
        self.rollout = rollout
        self.serviceLogs = serviceLogs
        self.rolloutSuccessCount = max(0, rolloutSuccessCount)
        self.rolloutFailureCount = max(0, rolloutFailureCount)
        self.lastSuccessfulRefreshAt = lastSuccessfulRefreshAt
    }

    public var overallStatus: OverallDataSourceHealth {
        if case .unavailable = taskDatabase {
            return .unavailable
        }
        let sources = [taskDatabase, renameIndex, rollout, serviceLogs]
        return sources.contains(where: \.reducesOverallHealth) ? .degraded : .healthy
    }

    public var summary: String {
        switch overallStatus {
        case .healthy:
            "数据源正常"
        case .degraded:
            "部分数据源降级"
        case .unavailable:
            "任务数据不可用"
        }
    }

    public func recordingSuccessfulRefresh(at date: Date) -> DataSourceHealthReport {
        DataSourceHealthReport(
            taskDatabase: taskDatabase,
            renameIndex: renameIndex,
            rollout: rollout,
            serviceLogs: serviceLogs,
            rolloutSuccessCount: rolloutSuccessCount,
            rolloutFailureCount: rolloutFailureCount,
            lastSuccessfulRefreshAt: date
        )
    }
}

public struct ThreadStatusLoadResult: Equatable, Sendable {
    public let snapshots: [ThreadSnapshot]
    public let health: DataSourceHealthReport

    public init(snapshots: [ThreadSnapshot], health: DataSourceHealthReport) {
        self.snapshots = snapshots
        self.health = health
    }
}

public struct ThreadStatusLoadFailure: Error, LocalizedError, Sendable {
    public let health: DataSourceHealthReport

    public init(health: DataSourceHealthReport) {
        self.health = health
    }

    public var errorDescription: String? {
        "Codex 任务数据库不可用"
    }
}
