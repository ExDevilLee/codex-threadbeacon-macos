import SwiftUI

struct SubagentLoadingRow: View {
    let isRefreshing: Bool
    let hasError: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isRefreshing {
                ProgressView()
                    .controlSize(.mini)
            } else if hasError {
                Image(systemName: "exclamationmark.triangle")
            } else {
                Image(systemName: "clock")
            }

            Text(message)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.leading, 50)
        .padding(.trailing, 14)
        .frame(minHeight: 38)
        .background(Color.secondary.opacity(0.035))
    }

    private var message: String {
        if isRefreshing {
            return "正在读取 Subagent"
        }
        if hasError {
            return "Subagent 读取失败"
        }
        return "等待读取 Subagent"
    }
}
