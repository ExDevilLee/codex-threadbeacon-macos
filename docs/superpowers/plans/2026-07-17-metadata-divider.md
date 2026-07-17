# Metadata Divider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a short native vertical divider between the Subagent count and Token overview when both are visible.

**Architecture:** Keep the change inside the existing title-row `HStack`. Reuse `SubagentCountFormatter.label(for:)` as the badge visibility source and conditionally insert a 12pt SwiftUI `Divider` only when `tokenUsage` also exists.

**Tech Stack:** Swift 6, SwiftUI, SwiftPM, macOS 14+

---

## File Map

- Modify `Sources/ThreadBeacon/Views/ThreadRowView.swift`: conditionally insert the native divider.
- Verify `Tests/ThreadBeaconTests/*`: existing behavioral regression suite remains green.
- Verify `dist/ThreadBeacon.app`: inspect the real dark-mode window at its default width.

### Task 1: Conditional Metadata Divider

**Files:**

- Modify: `Sources/ThreadBeacon/Views/ThreadRowView.swift`

- [ ] **Step 1: Confirm the failing visual state**

Use the supplied screenshot and the current running App to confirm that a row containing both
Subagent count and Token overview renders the two groups without a divider:

```text
branch icon + 3  259.3M + info
```

Expected failure: there is no visible vertical separator between `3` and `259.3M`.

- [ ] **Step 2: Add the minimal conditional divider**

Inside the existing `if let label` block, immediately after `SubagentCountBadge`:

```swift
if let label = SubagentCountFormatter.label(for: snapshot.subagentCount) {
    SubagentCountBadge(label: label)

    if snapshot.tokenUsage != nil {
        Divider()
            .frame(height: 12)
            .accessibilityHidden(true)
    }
}
```

Do not change the later `if let tokenUsage` block. This guarantees:

- Badge plus Token: divider visible.
- Badge without Token: no divider.
- Token without Badge: no divider.
- Neither value: no divider.

- [ ] **Step 3: Run automated regression verification**

Run:

```bash
./script/test.sh
./script/swiftpm.sh build
```

Expected: all existing tests pass and the `ThreadBeacon` target builds without warnings or errors.

- [ ] **Step 4: Build, launch, and verify the real window**

Run:

```bash
./script/build_and_run.sh --verify
```

Inspect the ThreadBeacon window and confirm:

```text
branch icon + 3 | 259.3M + info
```

Acceptance checks:

- The divider appears only on rows containing both metadata groups.
- The divider uses the system separator color in Dark appearance.
- Title, badge, divider, Token, and info do not overlap at default width.
- The divider is absent from the Accessibility tree.

- [ ] **Step 5: Commit the UI adjustment**

```bash
git add Sources/ThreadBeacon/Views/ThreadRowView.swift
git diff --cached --check
git commit -m "fix(ui): separate subagent and token metadata"
```

- [ ] **Step 6: Final repository check**

```bash
git status --short --branch
git log -3 --oneline
```

Expected: no uncommitted files from the divider adjustment and the UI commit is at `HEAD`.
