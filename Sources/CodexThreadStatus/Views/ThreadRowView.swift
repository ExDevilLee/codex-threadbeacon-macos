import CodexThreadStatusCore
import SwiftUI

struct ThreadRowView: View {
    let snapshot: ThreadSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusDotView(status: snapshot.status)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 5) {
                Text(snapshot.title.isEmpty ? "未命名任务" : snapshot.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    Text(snapshot.status.displayName)
                        .fontWeight(.medium)
                        .foregroundStyle(snapshot.status.color)
                    Text("·")
                    Text(RelativeTimeFormatter.statusDuration(since: snapshot.statusChangedAt))
                }
                .font(.caption)
                .foregroundStyle(.secondary)

            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
        .contentShape(Rectangle())
    }
}

extension ThreadDisplayStatus {
    var displayName: String {
        switch self {
        case .error: "错误"
        case .needsAction: "需要操作"
        case .running: "运行中"
        case .justCompleted: "刚完成"
        case .idle: "空闲"
        case .unknown: "未知"
        }
    }

    var color: Color {
        switch self {
        case .error: .red
        case .needsAction: .orange
        case .running: .blue
        case .justCompleted: .green
        case .idle: .secondary
        case .unknown: .yellow
        }
    }
}
