#!/usr/bin/env swift

import AppKit
import ApplicationServices
import Foundation

private struct Options {
    let threadID: String
    let shouldSelect: Bool
    let shouldInject: Bool

    static func parse(_ arguments: [String]) throws -> Options {
        var threadID: String?
        var select = false
        var confirmSelect = false
        var inject = false
        var confirmInject = false
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--thread-id":
                index += 1
                guard index < arguments.count else { throw ProbeError.invalidArguments }
                threadID = arguments[index]
            case "--select":
                select = true
            case "--confirm-select":
                confirmSelect = true
            case "--inject":
                inject = true
            case "--confirm-inject":
                confirmInject = true
            default:
                throw ProbeError.invalidArguments
            }
            index += 1
        }

        guard let threadID, !threadID.isEmpty else { throw ProbeError.invalidArguments }
        guard select == confirmSelect else { throw ProbeError.selectionRequiresConfirmation }
        guard inject == confirmInject else { throw ProbeError.injectionRequiresConfirmation }
        guard !inject || select else { throw ProbeError.injectionRequiresSelection }
        return Options(
            threadID: threadID,
            shouldSelect: select && confirmSelect,
            shouldInject: inject && confirmInject
        )
    }
}

private enum ProbeError: Error, CustomStringConvertible {
    case invalidArguments
    case selectionRequiresConfirmation
    case injectionRequiresConfirmation
    case injectionRequiresSelection
    case accessibilityNotGranted
    case codexNotRunning
    case sessionIndexUnavailable
    case threadNameUnavailable
    case threadNameNotUnique(Int)
    case taskRowNotUnique(Int)
    case selectionFailed(AXError)
    case targetHeaderNotUnique(Int)
    case composerNotUnique(Int)
    case composerNotEmpty
    case composerValueNotSettable
    case injectionFailed(AXError)
    case injectionReadbackFailed(expected: Int, actual: Int)
    case cleanupFailed(AXError)
    case cleanupReadbackFailed

    var description: String {
        switch self {
        case .invalidArguments:
            return "用法：swift Tools/AccessibilityProbe/main.swift --thread-id <ID> [--select --confirm-select [--inject --confirm-inject]]"
        case .selectionRequiresConfirmation:
            return "切换任务必须同时提供 --select 和 --confirm-select"
        case .injectionRequiresConfirmation:
            return "注入验证必须同时提供 --inject 和 --confirm-inject"
        case .injectionRequiresSelection:
            return "注入验证前必须先启用任务切换双确认"
        case .accessibilityNotGranted:
            return "当前执行进程未获得 macOS Accessibility 权限"
        case .codexNotRunning:
            return "未发现正在运行的 Codex App"
        case .sessionIndexUnavailable:
            return "无法读取 ~/.codex/session_index.jsonl"
        case .threadNameUnavailable:
            return "未找到该任务的 rename 标题"
        case let .threadNameNotUnique(count):
            return "rename 标题无法唯一映射到任务 ID，同名任务数：\(count)"
        case let .taskRowNotUnique(count):
            return "目标任务按钮无法唯一定位，候选数：\(count)"
        case let .selectionFailed(error):
            return "切换目标任务失败：AXError \(error.rawValue)"
        case let .targetHeaderNotUnique(count):
            return "切换后无法在 Codex 标题栏唯一确认目标任务，候选数：\(count)"
        case let .composerNotUnique(count):
            return "消息输入框无法唯一定位，候选数：\(count)"
        case .composerNotEmpty:
            return "消息输入框已有内容，拒绝覆盖"
        case .composerValueNotSettable:
            return "消息输入框的 AXValue 不可写"
        case let .injectionFailed(error):
            return "写入固定提示词失败：AXError \(error.rawValue)"
        case let .injectionReadbackFailed(expected, actual):
            return "写入后的 AXValue 回读不一致，期望长度：\(expected)，实际长度：\(actual)"
        case let .cleanupFailed(error):
            return "清空固定提示词失败：AXError \(error.rawValue)"
        case .cleanupReadbackFailed:
            return "清空后的 AXValue 回读仍有内容"
        }
    }
}

private struct AXSnapshot {
    let titleMatchCount: Int
    let actionableRows: [AXUIElement]
    let headerTitleMatchCount: Int
    let textAreas: [AXUIElement]
}

private struct ThreadIdentity {
    let title: String
    let matchingThreadCount: Int
}

private func copyValue(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &result) == .success else {
        return nil
    }
    return result
}

private func stringValue(_ element: AXUIElement, _ attribute: CFString) -> String {
    copyValue(element, attribute) as? String ?? ""
}

private func children(of element: AXUIElement) -> [AXUIElement] {
    copyValue(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
}

private func actionNames(of element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
    return names as? [String] ?? []
}

private func actionableAncestor(of element: AXUIElement) -> AXUIElement? {
    var current: AXUIElement? = element

    for _ in 0..<8 {
        guard let candidate = current else { return nil }
        let role = stringValue(candidate, kAXRoleAttribute as CFString)
        if role == kAXButtonRole as String,
           actionNames(of: candidate).contains(kAXPressAction as String) {
            return candidate
        }

        guard let parent = copyValue(candidate, kAXParentAttribute as CFString) else {
            return nil
        }
        current = (parent as! AXUIElement)
    }

    return nil
}

private func appendUnique(_ element: AXUIElement, to elements: inout [AXUIElement]) {
    guard !elements.contains(where: { CFEqual($0, element) }) else { return }
    elements.append(element)
}

private func attributeNames(of element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyAttributeNames(element, &names) == .success else { return [] }
    return names as? [String] ?? []
}

private func reportsThreadID(_ value: CFTypeRef, threadID: String) -> Bool {
    if let string = value as? String {
        return string.contains(threadID)
    }
    if let url = value as? URL {
        return url.absoluteString.contains(threadID)
    }
    if let strings = value as? [String] {
        return strings.contains(where: { $0.contains(threadID) })
    }
    return false
}

private func inspectThreadIDEvidence(processID: pid_t, threadID: String) {
    var stack = [AXUIElementCreateApplication(processID)]
    var visited = 0
    var matches: [(role: String, attribute: String)] = []

    while let element = stack.popLast(), visited < 10_000 {
        visited += 1
        for attribute in attributeNames(of: element) {
            guard let value = copyValue(element, attribute as CFString),
                  reportsThreadID(value, threadID: threadID) else {
                continue
            }
            matches.append((
                role: stringValue(element, kAXRoleAttribute as CFString),
                attribute: attribute
            ))
        }
        stack.append(contentsOf: children(of: element))
    }

    print("thread-id-evidence=\(matches.count)")
    for match in matches {
        print("thread-id-match role=\(match.role) attribute=\(match.attribute)")
    }
}

private func hasAncestorDOMClass(_ element: AXUIElement, className: String) -> Bool {
    var current: AXUIElement? = element

    for _ in 0..<8 {
        guard let candidate = current else { return false }
        let classes = copyValue(candidate, "AXDOMClassList" as CFString) as? [String] ?? []
        if classes.contains(className) { return true }

        guard let parent = copyValue(candidate, kAXParentAttribute as CFString) else {
            return false
        }
        current = (parent as! AXUIElement)
    }

    return false
}

private func snapshot(processID: pid_t, targetTitle: String) -> AXSnapshot {
    var stack = [AXUIElementCreateApplication(processID)]
    var visitedNodes = 0
    var titleMatchCount = 0
    var actionableRows: [AXUIElement] = []
    var headerTitleMatchCount = 0
    var textAreas: [AXUIElement] = []

    while let element = stack.popLast(), visitedNodes < 10_000 {
        visitedNodes += 1
        let role = stringValue(element, kAXRoleAttribute as CFString)
        if role == kAXTextAreaRole as String {
            appendUnique(element, to: &textAreas)
        }

        let titleMatches = stringValue(element, kAXTitleAttribute as CFString) == targetTitle
        let valueMatches = stringValue(element, kAXValueAttribute as CFString) == targetTitle
        if titleMatches || valueMatches {
            titleMatchCount += 1
            if hasAncestorDOMClass(element, className: "app-header-tint") {
                headerTitleMatchCount += 1
            }
            if let row = actionableAncestor(of: element) {
                appendUnique(row, to: &actionableRows)
            }
        }

        stack.append(contentsOf: children(of: element))
    }

    return AXSnapshot(
        titleMatchCount: titleMatchCount,
        actionableRows: actionableRows,
        headerTitleMatchCount: headerTitleMatchCount,
        textAreas: textAreas
    )
}

private func isAttributeSettable(_ element: AXUIElement, _ attribute: CFString) -> Bool {
    var settable = DarwinBoolean(false)
    guard AXUIElementIsAttributeSettable(element, attribute, &settable) == .success else {
        return false
    }
    return settable.boolValue
}

private func normalizedComposerValue(_ composer: AXUIElement) -> String {
    stringValue(composer, kAXValueAttribute as CFString)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func isEmptyComposer(_ composer: AXUIElement) -> Bool {
    let value = normalizedComposerValue(composer)
    return value.isEmpty || value == "随心输入"
}

private func parent(of element: AXUIElement) -> AXUIElement? {
    guard let value = copyValue(element, kAXParentAttribute as CFString) else {
        return nil
    }
    return (value as! AXUIElement)
}

private func sanitizedAttribute(_ element: AXUIElement, _ attribute: CFString) -> String {
    stringValue(element, attribute)
        .replacingOccurrences(of: "\n", with: " ")
        .prefix(80)
        .description
}

private func inspectSendControlContext(around composer: AXUIElement) {
    print("composer-actions=\(actionNames(of: composer).sorted().joined(separator: ","))")

    var current: AXUIElement? = composer
    for depth in 0..<8 {
        guard let element = current else { break }
        let role = sanitizedAttribute(element, kAXRoleAttribute as CFString)
        let title = sanitizedAttribute(element, kAXTitleAttribute as CFString)
        let description = sanitizedAttribute(element, kAXDescriptionAttribute as CFString)
        let identifier = sanitizedAttribute(element, kAXIdentifierAttribute as CFString)
        let classes = copyValue(element, "AXDOMClassList" as CFString) as? [String] ?? []
        let actions = actionNames(of: element).sorted()
        print(
            "ancestor[\(depth)] role=\(role) title=\(title) description=\(description) "
                + "identifier=\(identifier) classes=\(classes.joined(separator: ",")) "
                + "actions=\(actions.joined(separator: ",")) children=\(children(of: element).count)"
        )

        for (index, child) in children(of: element).enumerated() {
            let childRole = sanitizedAttribute(child, kAXRoleAttribute as CFString)
            let childTitle = sanitizedAttribute(child, kAXTitleAttribute as CFString)
            let childDescription = sanitizedAttribute(child, kAXDescriptionAttribute as CFString)
            let childIdentifier = sanitizedAttribute(child, kAXIdentifierAttribute as CFString)
            let childClasses = copyValue(child, "AXDOMClassList" as CFString) as? [String] ?? []
            let childActions = actionNames(of: child).sorted()
            print(
                "ancestor[\(depth)].child[\(index)] role=\(childRole) title=\(childTitle) "
                    + "description=\(childDescription) identifier=\(childIdentifier) "
                    + "classes=\(childClasses.joined(separator: ",")) "
                    + "actions=\(childActions.joined(separator: ","))"
            )
        }
        current = parent(of: element)
    }
}

private func inspectTaskRowIdentity(_ row: AXUIElement) {
    var stack: [(AXUIElement, Int)] = [(row, 0)]
    var visited = 0

    while let (element, depth) = stack.popLast(), visited < 100, depth < 6 {
        visited += 1
        let role = sanitizedAttribute(element, kAXRoleAttribute as CFString)
        let identifier = sanitizedAttribute(element, kAXIdentifierAttribute as CFString)
        let domIdentifier = sanitizedAttribute(element, "AXDOMIdentifier" as CFString)
        let url = sanitizedAttribute(element, kAXURLAttribute as CFString)
        let classes = copyValue(element, "AXDOMClassList" as CFString) as? [String] ?? []
        let actions = actionNames(of: element).sorted()
        print(
            "task-row-node[\(visited)] depth=\(depth) role=\(role) identifier=\(identifier) "
                + "dom-id=\(domIdentifier) url=\(url) classes=\(classes.joined(separator: ",")) "
                + "actions=\(actions.joined(separator: ","))"
        )
        stack.append(contentsOf: children(of: element).reversed().map { ($0, depth + 1) })
    }
}

private func verifyInjection(in composer: AXUIElement) throws {
    let fixedPrompt = "刚才中断了，请继续未完成的任务"
    guard isEmptyComposer(composer) else {
        throw ProbeError.composerNotEmpty
    }
    guard isAttributeSettable(composer, kAXValueAttribute as CFString) else {
        throw ProbeError.composerValueNotSettable
    }

    let writeResult = AXUIElementSetAttributeValue(
        composer,
        kAXValueAttribute as CFString,
        fixedPrompt as CFString
    )
    guard writeResult == .success else { throw ProbeError.injectionFailed(writeResult) }

    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    let readback = normalizedComposerValue(composer)
    guard readback == fixedPrompt else {
        let clearResult = AXUIElementSetAttributeValue(
            composer,
            kAXValueAttribute as CFString,
            "" as CFString
        )
        guard clearResult == .success else { throw ProbeError.cleanupFailed(clearResult) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        guard isEmptyComposer(composer) else { throw ProbeError.cleanupReadbackFailed }
        throw ProbeError.injectionReadbackFailed(
            expected: fixedPrompt.count,
            actual: readback.count
        )
    }
    print("injection=verified")
    inspectSendControlContext(around: composer)

    let clearResult = AXUIElementSetAttributeValue(
        composer,
        kAXValueAttribute as CFString,
        "" as CFString
    )
    guard clearResult == .success else { throw ProbeError.cleanupFailed(clearResult) }
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    guard isEmptyComposer(composer) else {
        throw ProbeError.cleanupReadbackFailed
    }
    print("cleanup=verified")
}

private func threadIdentity(threadID: String) throws -> ThreadIdentity {
    let indexURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".codex/session_index.jsonl")
    guard let contents = try? String(contentsOf: indexURL, encoding: .utf8) else {
        throw ProbeError.sessionIndexUnavailable
    }

    var latestNames: [String: String] = [:]
    for line in contents.split(whereSeparator: \.isNewline) {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String,
              let name = object["thread_name"] as? String,
              !name.isEmpty else {
            continue
        }
        latestNames[id] = name
    }

    guard let targetName = latestNames[threadID] else { throw ProbeError.threadNameUnavailable }
    return ThreadIdentity(
        title: targetName,
        matchingThreadCount: latestNames.values.filter { $0 == targetName }.count
    )
}

private func run() throws {
    let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
    guard AXIsProcessTrusted() else { throw ProbeError.accessibilityNotGranted }
    guard let app = NSRunningApplication.runningApplications(
        withBundleIdentifier: "com.openai.codex"
    ).first else {
        throw ProbeError.codexNotRunning
    }

    let identity = try threadIdentity(threadID: options.threadID)
    guard !options.shouldSelect || identity.matchingThreadCount == 1 else {
        throw ProbeError.threadNameNotUnique(identity.matchingThreadCount)
    }
    let initial = snapshot(processID: app.processIdentifier, targetTitle: identity.title)

    print("permission=granted")
    print("title-matches=\(initial.titleMatchCount)")
    print("actionable-task-rows=\(initial.actionableRows.count)")
    print("header-title-matches=\(initial.headerTitleMatchCount)")
    print("composer-textareas=\(initial.textAreas.count)")
    inspectThreadIDEvidence(processID: app.processIdentifier, threadID: options.threadID)

    guard options.shouldSelect else {
        print("selection=not-requested")
        print("message-input=disabled-by-design")
        return
    }

    guard initial.actionableRows.count == 1 else {
        throw ProbeError.taskRowNotUnique(initial.actionableRows.count)
    }
    inspectTaskRowIdentity(initial.actionableRows[0])
    let result = AXUIElementPerformAction(initial.actionableRows[0], kAXPressAction as CFString)
    guard result == .success else { throw ProbeError.selectionFailed(result) }

    RunLoop.current.run(until: Date().addingTimeInterval(0.8))
    let selected = snapshot(processID: app.processIdentifier, targetTitle: identity.title)
    print("selection=performed")
    print("header-after-selection=\(selected.headerTitleMatchCount)")
    print("composer-after-selection=\(selected.textAreas.count)")

    guard options.shouldInject else {
        print("message-input=disabled-by-design")
        return
    }
    guard selected.textAreas.count == 1 else {
        throw ProbeError.composerNotUnique(selected.textAreas.count)
    }
    guard selected.headerTitleMatchCount == 1 else {
        throw ProbeError.targetHeaderNotUnique(selected.headerTitleMatchCount)
    }
    try verifyInjection(in: selected.textAreas[0])
    print("message-send=disabled-by-design")
}

do {
    try run()
} catch {
    fputs("Accessibility POC 失败：\(error)\n", stderr)
    exit(1)
}
