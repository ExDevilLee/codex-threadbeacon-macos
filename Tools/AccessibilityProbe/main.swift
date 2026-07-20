#!/usr/bin/env swift

import AppKit
import ApplicationServices
import Foundation

private struct Options {
    let threadID: String
    let shouldSelect: Bool

    static func parse(_ arguments: [String]) throws -> Options {
        var threadID: String?
        var select = false
        var confirmSelect = false
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
            default:
                throw ProbeError.invalidArguments
            }
            index += 1
        }

        guard let threadID, !threadID.isEmpty else { throw ProbeError.invalidArguments }
        guard select == confirmSelect else { throw ProbeError.selectionRequiresConfirmation }
        return Options(threadID: threadID, shouldSelect: select && confirmSelect)
    }
}

private enum ProbeError: Error, CustomStringConvertible {
    case invalidArguments
    case selectionRequiresConfirmation
    case accessibilityNotGranted
    case codexNotRunning
    case sessionIndexUnavailable
    case threadNameUnavailable
    case taskRowNotUnique(Int)
    case selectionFailed(AXError)

    var description: String {
        switch self {
        case .invalidArguments:
            return "用法：swift Tools/AccessibilityProbe/main.swift --thread-id <ID> [--select --confirm-select]"
        case .selectionRequiresConfirmation:
            return "切换任务必须同时提供 --select 和 --confirm-select"
        case .accessibilityNotGranted:
            return "当前执行进程未获得 macOS Accessibility 权限"
        case .codexNotRunning:
            return "未发现正在运行的 Codex App"
        case .sessionIndexUnavailable:
            return "无法读取 ~/.codex/session_index.jsonl"
        case .threadNameUnavailable:
            return "未找到该任务的 rename 标题"
        case let .taskRowNotUnique(count):
            return "目标任务按钮无法唯一定位，候选数：\(count)"
        case let .selectionFailed(error):
            return "切换目标任务失败：AXError \(error.rawValue)"
        }
    }
}

private struct AXSnapshot {
    let titleMatchCount: Int
    let actionableRows: [AXUIElement]
    let textAreaCount: Int
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

private func snapshot(processID: pid_t, targetTitle: String) -> AXSnapshot {
    var stack = [AXUIElementCreateApplication(processID)]
    var visitedNodes = 0
    var titleMatchCount = 0
    var actionableRows: [AXUIElement] = []
    var textAreaCount = 0

    while let element = stack.popLast(), visitedNodes < 10_000 {
        visitedNodes += 1
        let role = stringValue(element, kAXRoleAttribute as CFString)
        if role == kAXTextAreaRole as String {
            textAreaCount += 1
        }

        let titleMatches = stringValue(element, kAXTitleAttribute as CFString) == targetTitle
        let valueMatches = stringValue(element, kAXValueAttribute as CFString) == targetTitle
        if titleMatches || valueMatches {
            titleMatchCount += 1
            if let row = actionableAncestor(of: element) {
                appendUnique(row, to: &actionableRows)
            }
        }

        stack.append(contentsOf: children(of: element))
    }

    return AXSnapshot(
        titleMatchCount: titleMatchCount,
        actionableRows: actionableRows,
        textAreaCount: textAreaCount
    )
}

private func latestThreadName(threadID: String) throws -> String {
    let indexURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".codex/session_index.jsonl")
    guard let contents = try? String(contentsOf: indexURL, encoding: .utf8) else {
        throw ProbeError.sessionIndexUnavailable
    }

    var latestName: String?
    for line in contents.split(whereSeparator: \.isNewline) {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["id"] as? String == threadID,
              let name = object["thread_name"] as? String,
              !name.isEmpty else {
            continue
        }
        latestName = name
    }

    guard let latestName else { throw ProbeError.threadNameUnavailable }
    return latestName
}

private func run() throws {
    let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
    guard AXIsProcessTrusted() else { throw ProbeError.accessibilityNotGranted }
    guard let app = NSRunningApplication.runningApplications(
        withBundleIdentifier: "com.openai.codex"
    ).first else {
        throw ProbeError.codexNotRunning
    }

    let targetTitle = try latestThreadName(threadID: options.threadID)
    let initial = snapshot(processID: app.processIdentifier, targetTitle: targetTitle)

    print("permission=granted")
    print("title-matches=\(initial.titleMatchCount)")
    print("actionable-task-rows=\(initial.actionableRows.count)")
    print("composer-textareas=\(initial.textAreaCount)")

    guard options.shouldSelect else {
        print("selection=not-requested")
        print("message-input=disabled-by-design")
        return
    }

    guard initial.actionableRows.count == 1 else {
        throw ProbeError.taskRowNotUnique(initial.actionableRows.count)
    }
    let result = AXUIElementPerformAction(initial.actionableRows[0], kAXPressAction as CFString)
    guard result == .success else { throw ProbeError.selectionFailed(result) }

    RunLoop.current.run(until: Date().addingTimeInterval(0.8))
    let selected = snapshot(processID: app.processIdentifier, targetTitle: targetTitle)
    print("selection=performed")
    print("composer-after-selection=\(selected.textAreaCount)")
    print("message-input=disabled-by-design")
}

do {
    try run()
} catch {
    fputs("Accessibility POC 失败：\(error)\n", stderr)
    exit(1)
}
