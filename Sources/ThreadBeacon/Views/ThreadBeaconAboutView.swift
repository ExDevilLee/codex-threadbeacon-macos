import AppKit
import SwiftUI
import ThreadBeaconCore

struct ThreadBeaconAboutView: View {
    @Environment(\.locale) private var locale
    @ObservedObject var updateCheckStore: UpdateCheckStore
    @State private var linkOpenFailed = false

    private let appInfo: AboutAppInfo

    init(
        updateCheckStore: UpdateCheckStore,
        appInfo: AboutAppInfo = AboutAppInfo(infoDictionary: Bundle.main.infoDictionary)
    ) {
        self.updateCheckStore = updateCheckStore
        self.appInfo = appInfo
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text(verbatim: "ThreadBeacon")
                    .font(.title2.weight(.semibold))

                Text(versionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            updateCheckSection

            Text(localized("用于快速查看 Codex App 与 Codex CLI 任务状态的本地 macOS 工具。"))
                .font(.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(localized("独立开源项目，与 OpenAI 无隶属或官方认可关系。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(spacing: 16) {
                projectLink("GitHub", url: ProjectLinks.repository)
                projectLink("版本记录", url: ProjectLinks.releases)
                projectLink("隐私", url: ProjectLinks.privacy)
                projectLink("MIT License", url: ProjectLinks.license)
            }
            .font(.callout)

            Button {
                open(ProjectLinks.sponsor)
            } label: {
                Label(localized("支持项目"), systemImage: "heart")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Text(verbatim: "Copyright © 2026 ExDevilLee")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 430)
        .alert(localized("无法打开链接"), isPresented: $linkOpenFailed) {
            Button(localized("好"), role: .cancel) {}
        } message: {
            Text(localized("请检查默认浏览器或稍后重试。"))
        }
    }

    private var versionText: String {
        switch (appInfo.version, appInfo.build) {
        case let (.some(version), .some(build)):
            AppLocalization.formatted("版本 %@（构建 %@）", locale: locale, version, build)
        case let (.some(version), nil):
            AppLocalization.formatted("版本 %@", locale: locale, version)
        case let (nil, .some(build)):
            AppLocalization.formatted("构建 %@", locale: locale, build)
        case (nil, nil):
            localized("版本未知")
        }
    }

    @ViewBuilder
    private var updateCheckSection: some View {
        switch updateCheckStore.state {
        case .idle:
            checkForUpdatesButton(localized("检查更新"))
        case .checking:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(localized("正在检查更新…"))
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        case .upToDate:
            HStack(spacing: 8) {
                Label(localized("当前已是最新版本"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                checkForUpdatesButton(localized("再次检查"))
            }
        case let .updateAvailable(update):
            HStack(spacing: 8) {
                Label(updateAvailableLabel(update), systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Button(localized("前往下载")) {
                    open(update.releaseURL)
                }
                .buttonStyle(.borderedProminent)
            }
        case .failed:
            VStack(spacing: 6) {
                Text(localized("暂时无法检查更新，请稍后重试。"))
                    .foregroundStyle(.secondary)
                checkForUpdatesButton(localized("重试"))
            }
        case .currentVersionUnavailable:
            Text(localized("无法确定当前版本。"))
                .foregroundStyle(.secondary)
        }
    }

    private func checkForUpdatesButton(_ title: String) -> some View {
        Button(title) {
            Task { await updateCheckStore.checkManually() }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func updateAvailableLabel(_ update: AvailableUpdate) -> String {
        AppLocalization.formatted(
            "发现新版本 v%@",
            locale: locale,
            update.version.description
        )
    }

    private func projectLink(_ title: String, url: URL) -> some View {
        Button(localized(title)) {
            open(url)
        }
        .buttonStyle(.link)
    }

    private func localized(_ source: String) -> String {
        AppLocalization.string(source, locale: locale)
    }

    private func open(_ url: URL) {
        if !NSWorkspace.shared.open(url) {
            linkOpenFailed = true
        }
    }
}
