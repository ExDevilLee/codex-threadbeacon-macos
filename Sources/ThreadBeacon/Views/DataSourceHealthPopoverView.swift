import ThreadBeaconCore
import SwiftUI

struct DataSourceHealthButton: View {
    @Environment(\.locale) private var locale
    let report: DataSourceHealthReport
    @State private var isShowingDetails = false

    var body: some View {
        Button {
            isShowingDetails.toggle()
        } label: {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .help(localizedSummary)
        .accessibilityLabel(AppLocalization.formatted("数据源健康：%@", locale: locale, localizedSummary))
        .popover(isPresented: $isShowingDetails) {
            DataSourceHealthPopoverView(report: report)
                .environment(\.locale, locale)
        }
    }

    private var iconName: String {
        switch report.overallStatus {
        case .healthy:
            "checkmark.shield"
        case .degraded:
            "exclamationmark.triangle.fill"
        case .unavailable:
            "xmark.octagon.fill"
        }
    }

    private var localizedSummary: String {
        AppLocalization.string(report.summary, locale: locale)
    }

    private var iconColor: Color {
        switch report.overallStatus {
        case .healthy:
            .green
        case .degraded:
            .orange
        case .unavailable:
            .red
        }
    }
}

struct DataSourceHealthPopoverView: View {
    @Environment(\.locale) private var locale
    let report: DataSourceHealthReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg.rectangle")
                Text("数据源健康")
                    .font(.headline)
                Spacer()
                Text(AppLocalization.string(report.summary, locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let refreshedAt = report.lastSuccessfulRefreshAt {
                Text(AppLocalization.formatted(
                    "最后成功刷新：%@",
                    locale: locale,
                    refreshedAt.formatted(
                        Date.FormatStyle(date: .omitted, time: .standard).locale(locale)
                    )
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("尚无成功刷新记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            DataSourceHealthRow(
                title: "任务数据库",
                status: report.taskDatabase
            )
            DataSourceHealthRow(
                title: "Rename 索引",
                status: report.renameIndex
            )
            DataSourceHealthRow(
                title: "Rollout",
                status: report.rollout,
                supplementalText: rolloutCounts
            )
            DataSourceHealthRow(
                title: "服务日志",
                status: report.serviceLogs
            )
        }
        .padding(14)
        .frame(width: 320)
    }

    private var rolloutCounts: String? {
        let total = report.rolloutSuccessCount + report.rolloutFailureCount
        guard total > 0 else { return nil }
        return AppLocalization.formatted(
            "成功 %lld ｜ 失败 %lld",
            locale: locale,
            report.rolloutSuccessCount,
            report.rolloutFailureCount
        )
    }
}

private struct DataSourceHealthRow: View {
    @Environment(\.locale) private var locale
    let title: String
    let status: DataSourceHealthStatus
    var supplementalText: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(AppLocalization.string(title, locale: locale))
                    Spacer()
                    Text(AppLocalization.string(status.displayText, locale: locale))
                        .foregroundStyle(statusTextColor)
                }
                .font(.caption)

                if let detailText = status.detailText {
                    Text(AppLocalization.userFacing(detailText, locale: locale))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let supplementalText {
                    Text(supplementalText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var iconName: String {
        switch status {
        case .healthy:
            "checkmark.circle.fill"
        case .degraded:
            "exclamationmark.triangle.fill"
        case .unavailable:
            "xmark.octagon.fill"
        case .notUsed:
            "minus.circle"
        }
    }

    private var iconColor: Color {
        switch status {
        case .healthy:
            .green
        case .degraded:
            .orange
        case .unavailable:
            .red
        case .notUsed:
            .secondary
        }
    }

    private var statusTextColor: Color {
        switch status {
        case .degraded:
            .orange
        case .unavailable:
            .red
        case .healthy, .notUsed:
            .secondary
        }
    }
}
