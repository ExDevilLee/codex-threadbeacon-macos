import Foundation
import ThreadBeaconCore

enum AccessibilityTargetSelectionPresentation {
    static func message(
        for result: AccessibilityTargetSelectionResult,
        locale: Locale
    ) -> String {
        switch result {
        case .notAuthorized:
            AppLocalization.string("目标任务验证失败：尚未获得辅助功能权限。", locale: locale)
        case .codexNotRunning:
            AppLocalization.string("目标任务验证失败：Codex App 未运行。", locale: locale)
        case .codexInteractionInProgress:
            AppLocalization.string("目标任务验证已停止：Codex 正在前台，可能存在用户输入。", locale: locale)
        case .invalidThreadID:
            AppLocalization.string("目标任务验证失败：任务 ID 为空。", locale: locale)
        case .sessionIndexUnavailable:
            AppLocalization.string("目标任务验证失败：无法读取 Codex 任务索引。", locale: locale)
        case .titleUnavailable:
            AppLocalization.string("目标任务验证失败：未找到该任务的 rename 标题。", locale: locale)
        case .sourceComposerNotEmpty:
            AppLocalization.string("目标任务验证已停止：当前 Codex 任务输入框已有草稿。", locale: locale)
        case let .sourceComposerNotUnique(count):
            AppLocalization.formatted(
                "目标任务验证已停止：切换前找到 %lld 个输入框。",
                locale: locale,
                count
            )
        case .sourceComposerValueUnavailable:
            AppLocalization.string("目标任务验证已停止：无法确认当前 Codex 输入框是否为空。", locale: locale)
        case .selectionFailed:
            AppLocalization.string("目标任务验证失败：无法切换 Codex 任务。", locale: locale)
        case let .targetHeaderNotUnique(count):
            AppLocalization.formatted(
                "目标任务验证失败：标题栏身份匹配数为 %lld。",
                locale: locale,
                count
            )
        case let .composerNotUnique(count):
            AppLocalization.formatted(
                "目标任务验证失败：切换后找到 %lld 个输入框。",
                locale: locale,
                count
            )
        case .selected:
            AppLocalization.string("目标任务验证通过：已按 ID 打开并确认 rename 名称，未发送消息。", locale: locale)
        }
    }
}

enum TaskOpenPresentation {
    static func message(for result: TaskOpenResult, locale: Locale) -> String {
        switch result {
        case .opened:
            ""
        case .archived:
            AppLocalization.string("已归档任务无法在 Codex App 中打开。", locale: locale)
        case .notAuthorized:
            AppLocalization.string("打开任务失败：尚未获得辅助功能权限。", locale: locale)
        case .interactionInProgress:
            AppLocalization.string("打开任务已停止：另一个辅助功能操作正在执行。", locale: locale)
        case let .selectionFailed(result):
            AccessibilityTargetSelectionPresentation.message(for: result, locale: locale)
        }
    }
}
