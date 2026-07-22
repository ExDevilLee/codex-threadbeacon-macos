import ThreadBeaconCore
import SwiftUI

struct CompactionHookSettingsSection: View {
    @ObservedObject var store: CompactionHookSettingsStore
    @Environment(\.locale) private var locale

    var body: some View {
        Section("实时压缩状态") {
            statusLabel

            Text("未启用 Hook 也可以查看累计压缩次数。启用后会修改 ~/.codex/hooks.json，注册 PreCompact 和 PostCompact；修改前会备份现有配置，停用时只删除 ThreadBeacon 自己的条目。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Codex 首次使用或 Hook 定义变化后仍需由你审核信任。ThreadBeacon 无法读取信任状态，因此“已配置”不代表“已信任”。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Hook 不读取或保存会话正文、压缩摘要、Reasoning、工作目录或 transcript。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if store.status == .configured || store.status == .externallyModified {
                    Button("检查配置") {
                        store.refresh()
                    }
                    Button("停用") {
                        store.uninstall()
                    }
                } else {
                    Button("启用实时压缩状态") {
                        let helperURL = Bundle.main.url(
                            forAuxiliaryExecutable: "ThreadBeaconHookBridge"
                        ) ?? URL(fileURLWithPath: "/__threadbeacon_missing_hook_helper__")
                        store.install(helperSourceURL: helperURL)
                    }
                }
            }

            if let error = store.lastError {
                Label(errorText(error), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch store.status {
        case .notConfigured:
            Label("未启用", systemImage: "circle")
                .foregroundStyle(.secondary)
        case .configured:
            Label("已配置，信任状态请在 Codex 查看", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .externallyModified:
            Label("配置已被外部修改", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private func errorText(_ error: CompactionHookConfigurationError) -> String {
        let source = switch error {
        case .invalidHooksJSON:
            "hooks.json 不是合法 JSON，未进行修改。"
        case .unsafeHooksFile:
            "hooks.json 不是可安全修改的普通文件。"
        case .inlineHooksPresent:
            "config.toml 已包含内联 Hooks，请改用手工配置。"
        case .configurationChanged:
            "写入前检测到 hooks.json 已被其他程序修改，请检查后重试。"
        case .helperUnavailable:
            "App 中缺少 Hook Helper，无法启用实时压缩状态。"
        case .writeFailed:
            "Hook 配置写入失败，现有配置未被覆盖。"
        }
        return AppLocalization.string(source, locale: locale)
    }
}
