import ThreadBeaconCore
import SwiftUI

struct AutoRecoverySettingsView: View {
    @ObservedObject var settingsStore: AutoRecoverySettingsStore
    @ObservedObject var logStore: AutoRecoveryLogStore
    @ObservedObject var circuitBreakerStore: AutoRecoveryCircuitBreakerStore
    @ObservedObject var accessibilityPermissionStore: AccessibilityPermissionStore
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    #if DEBUG
    @State private var showsDeveloperDiagnostics = false
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                masterSection
                Divider()
                rulesSection
                if !openCircuitStates.isEmpty {
                    Divider()
                    openCircuitsSection
                }
                Divider()
                logSection

                #if DEBUG
                Divider()
                DisclosureGroup(
                    localized("开发者诊断"),
                    isExpanded: $showsDeveloperDiagnostics
                ) {
                    AutoRecoveryDiagnosticsView(
                        accessibilityPermissionStore: accessibilityPermissionStore
                    )
                    .padding(.top, 10)
                }
                .font(.headline)
                #endif
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 4)
        }
        .onAppear {
            accessibilityPermissionStore.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                accessibilityPermissionStore.refresh()
            }
        }
    }

    private var masterSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle(
                localized("启用自动恢复"),
                isOn: Binding(
                    get: { settingsStore.settings.isEnabled },
                    set: { isEnabled in
                        settingsStore.setEnabled(isEnabled)
                    }
                )
            )
            .font(.headline)

            Text(localized("检测到已启用的终止异常时，通过 Codex App 输入框发送对应提示词。"))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Label(
                    localized(accessibilityPermissionStore.isAuthorized ? "已授权" : "未授权"),
                    systemImage: accessibilityPermissionStore.isAuthorized
                        ? "checkmark.circle.fill"
                        : "hand.raised.circle.fill"
                )
                .foregroundStyle(accessibilityPermissionStore.isAuthorized ? .green : .secondary)

                Spacer()

                if !accessibilityPermissionStore.isAuthorized {
                    Button(localized("请求授权")) {
                        accessibilityPermissionStore.requestAuthorization()
                    }
                    Button(localized("打开辅助功能设置")) {
                        accessibilityPermissionStore.openSystemSettings()
                    }
                }
            }
            .font(.caption)

            if !accessibilityPermissionStore.isAuthorized {
                Text(localized("未授权时不会发送，也不会使用外部 CLI；已启用规则的新异常会记录为未发送。"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized("异常规则"))
                .font(.headline)

            Text(localized("仅终止型异常会触发；Codex 正在自动重试时不会发送。"))
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(AutoRecoveryIncidentType.allCases, id: \.self) { type in
                AutoRecoveryRuleEditor(settingsStore: settingsStore, type: type)
                if type != AutoRecoveryIncidentType.allCases.last {
                    Divider()
                }
            }
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(localized("异常自动恢复记录"))
                    .font(.headline)
                Spacer()
                Button(localized("清空记录")) {
                    logStore.clear()
                }
                .disabled(logStore.entries.isEmpty)
            }

            if logStore.entries.isEmpty {
                ContentUnavailableView(
                    localized("暂无自动恢复记录"),
                    systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                    description: Text(localized("检测到新的异常后，处理结果会显示在这里。"))
                )
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(logStore.entries) { entry in
                        AutoRecoveryLogRow(entry: entry)
                        if entry.id != logStore.entries.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var openCircuitStates: [AutoRecoveryCircuitState] {
        circuitBreakerStore.states.filter { state in
            let rule = settingsStore.settings.rule(for: state.incidentType)
            return rule.isCircuitBreakerEnabled
                && state.attemptCount >= rule.maximumConsecutiveAttempts
        }
    }

    private var openCircuitsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localized("当前熔断"))
                .font(.headline)
            Text(localized("达到上限的任务不会继续自动发送；正常完成任务或手动解除后恢复。"))
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(openCircuitStates) { state in
                HStack(spacing: 8) {
                    Image(systemName: "pause.octagon.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.incidentType.localizedTitle(locale: locale))
                            .font(.caption.weight(.medium))
                        Text(state.threadID)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("\(state.attemptCount)/\(settingsStore.settings.rule(for: state.incidentType).maximumConsecutiveAttempts)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button(localized("解除")) {
                        circuitBreakerStore.reset(
                            threadID: state.threadID,
                            incidentType: state.incidentType
                        )
                    }
                    .controlSize(.small)
                }
                .padding(.vertical, 3)
            }
        }
    }

    private func localized(_ source: String) -> String {
        AppLocalization.string(source, locale: locale)
    }
}

private struct AutoRecoveryRuleEditor: View {
    @ObservedObject var settingsStore: AutoRecoverySettingsStore
    let type: AutoRecoveryIncidentType
    @Environment(\.locale) private var locale
    @State private var isExpanded = false
    @State private var draftPrompt: String
    @State private var draftMaximumAttempts: String
    @State private var isDraftDirty = false
    @State private var validationError: AutoRecoveryPromptValidation?
    @FocusState private var isMaximumAttemptsFocused: Bool

    init(settingsStore: AutoRecoverySettingsStore, type: AutoRecoveryIncidentType) {
        self.settingsStore = settingsStore
        self.type = type
        _draftPrompt = State(initialValue: settingsStore.settings.rule(for: type).prompt)
        _draftMaximumAttempts = State(
            initialValue: String(
                settingsStore.settings.rule(for: type).maximumConsecutiveAttempts
            )
        )
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)

                    Toggle(localized("连续失败"), isOn: circuitBreakerEnabledBinding)
                        .font(.caption.weight(.medium))

                    Text(localized("[1～20]"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    TextField("", text: $draftMaximumAttempts)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 44)
                        .multilineTextAlignment(.trailing)
                        .font(.caption.monospacedDigit())
                        .focused($isMaximumAttemptsFocused)
                        .disabled(!storedRule.isCircuitBreakerEnabled)
                        .onSubmit {
                            commitMaximumAttempts()
                        }
                    Text(localized("次后停止"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: false, vertical: true)
                .help(localized("允许输入 1～20，默认 3 次；关闭后将持续尝试自动恢复。"))

                Divider()

                Text(localized("自动恢复提示词"))
                    .font(.caption.weight(.medium))

                TextEditor(text: draftPromptBinding)
                    .font(.body)
                    .frame(minHeight: 58, maxHeight: 82)
                    .padding(4)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(.separator, lineWidth: 1)
                    }

                HStack {
                    Text("\(draftPrompt.count)/\(AutoRecoveryPromptValidation.maximumCharacterCount)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(promptCountColor)

                    Spacer()

                    Button(localized("恢复默认")) {
                        settingsStore.resetRule(for: type)
                        draftPrompt = settingsStore.settings.rule(for: type).prompt
                        isDraftDirty = false
                        validationError = nil
                    }

                    Button(localized("保存")) {
                        savePrompt()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let validationError {
                    Text(validationMessage(validationError))
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Toggle("", isOn: enabledBinding)
                    .labelsHidden()
                    .help(localized("启用或停用此异常的自动恢复"))
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.localizedTitle(locale: locale))
                    Text(type.localizedDetail(locale: locale))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .onChange(of: storedPrompt) { _, newPrompt in
            guard !isDraftDirty else { return }
            draftPrompt = newPrompt
        }
        .onChange(of: storedRule.maximumConsecutiveAttempts) { _, newValue in
            guard !isMaximumAttemptsFocused else { return }
            draftMaximumAttempts = String(newValue)
        }
        .onChange(of: isMaximumAttemptsFocused) { _, isFocused in
            if !isFocused {
                commitMaximumAttempts()
            }
        }
        .onChange(of: storedRule.isCircuitBreakerEnabled) { _, isEnabled in
            if !isEnabled {
                isMaximumAttemptsFocused = false
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.rule(for: type).isEnabled },
            set: { isEnabled in
                settingsStore.setRuleEnabled(isEnabled, for: type)
            }
        )
    }

    private var storedPrompt: String {
        storedRule.prompt
    }

    private var storedRule: AutoRecoveryRule {
        settingsStore.settings.rule(for: type)
    }

    private var circuitBreakerEnabledBinding: Binding<Bool> {
        Binding(
            get: { storedRule.isCircuitBreakerEnabled },
            set: { settingsStore.setCircuitBreakerEnabled($0, for: type) }
        )
    }

    private var draftPromptBinding: Binding<String> {
        Binding(
            get: { draftPrompt },
            set: { newValue in
                draftPrompt = newValue
                isDraftDirty = true
                validationError = nil
            }
        )
    }

    private var promptCountColor: Color {
        draftPrompt.count > AutoRecoveryPromptValidation.maximumCharacterCount ? .red : .secondary
    }

    private func savePrompt() {
        let validation = settingsStore.savePrompt(
            for: type,
            prompt: draftPrompt
        )
        validationError = validation
        if case let .valid(normalizedPrompt) = validation {
            draftPrompt = normalizedPrompt
            isDraftDirty = false
            validationError = nil
        }
    }

    private func commitMaximumAttempts() {
        let normalized = draftMaximumAttempts.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(normalized) else {
            draftMaximumAttempts = String(storedRule.maximumConsecutiveAttempts)
            return
        }
        settingsStore.setMaximumConsecutiveAttempts(value, for: type)
        draftMaximumAttempts = String(storedRule.maximumConsecutiveAttempts)
    }

    private func validationMessage(_ validation: AutoRecoveryPromptValidation) -> String {
        switch validation {
        case .valid:
            ""
        case .empty:
            localized("提示词不能为空")
        case .tooLong:
            localized("提示词不能超过 500 个字符")
        }
    }

    private func localized(_ source: String) -> String {
        AppLocalization.string(source, locale: locale)
    }
}

private struct AutoRecoveryLogRow: View {
    let entry: AutoRecoveryLogEntry
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(
                    entry.status.localizedTitle(locale: locale),
                    systemImage: entry.status.systemImage
                )
                .foregroundStyle(entry.status.color)
                Spacer()
                Text(entry.occurredAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(AppLocalization.formatted("会话 %@", locale: locale, entry.threadID))
                .font(.caption.monospaced())
            Text(entry.incident)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(entry.prompt)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let detail = entry.detail {
                Text(AppLocalization.userFacing(detail, locale: locale))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 7)
    }
}

private extension AutoRecoveryIncidentType {
    func localizedTitle(locale: Locale) -> String {
        let source: String
        switch self {
        case .http400: source = "HTTP 400"
        case .http429: source = "HTTP 429"
        case .http503: source = "HTTP 503"
        case .otherHTTP: source = "其他 HTTP 错误"
        case .modelCapacity: source = "模型容量异常"
        case .streamDisconnected: source = "连接中断"
        }
        return AppLocalization.string(source, locale: locale)
    }

    func localizedDetail(locale: Locale) -> String {
        let source: String
        switch self {
        case .http400: source = "请求参数错误并终止"
        case .http429: source = "频率限制重试耗尽"
        case .http503: source = "服务不可用重试耗尽；默认关闭"
        case .otherHTTP: source = "其他结构化终止型 4xx/5xx"
        case .modelCapacity: source = "模型容量限制导致终止"
        case .streamDisconnected: source = "重新连接重试耗尽后终止"
        }
        return AppLocalization.string(source, locale: locale)
    }
}

private extension AutoRecoveryLogStatus {
    var systemImage: String {
        switch self {
        case .sending: "arrow.triangle.2.circlepath"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .skipped: "hand.raised.circle.fill"
        case .circuitOpen: "pause.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .sending: .orange
        case .succeeded: .green
        case .failed: .red
        case .skipped: .secondary
        case .circuitOpen: .orange
        }
    }

    func localizedTitle(locale: Locale) -> String {
        let source: String
        switch self {
        case .sending: source = "发送中"
        case .succeeded: source = "已发送"
        case .failed: source = "发送失败"
        case .skipped: source = "未发送"
        case .circuitOpen: source = "已熔断"
        }
        return AppLocalization.string(source, locale: locale)
    }
}
