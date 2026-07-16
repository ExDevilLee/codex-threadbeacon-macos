# ThreadBeacon Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the private macOS POC to `ThreadBeacon for Codex`, make every local technical identifier consistent, and rename its private GitHub repository to `codex-threadbeacon-macos` without changing runtime behavior.

**Architecture:** Keep `ThreadBeacon` as the Swift package, executable, App bundle, process, and visible App name. Use `ThreadBeacon for Codex` in discovery-oriented README copy, while retaining Codex data paths and the unofficial-project disclaimer. Perform and verify the local rename before changing the GitHub repository name, so a failed remote rename can be retried without leaving an unverified build.

**Tech Stack:** Swift 6.1, SwiftPM, SwiftUI/AppKit, Bash packaging scripts, Git, GitHub CLI.

---

## Tasks

### Task 1: Finalize the approved naming contract

**Files:**

- Modify: `docs/superpowers/specs/2026-07-16-threadbeacon-naming-design.md`
- Create: `docs/superpowers/plans/2026-07-16-threadbeacon-rename.md`

- [ ] **Step 1: Record the final public and technical names**

The design must contain this exact naming contract:

```text
Product: ThreadBeacon for Codex
App display name: ThreadBeacon
Swift package/executable: ThreadBeacon
Bundle identifier: io.github.exdevillee.threadbeacon.macos
GitHub repository: ExDevilLee/codex-threadbeacon-macos
Visibility: PRIVATE
```

- [ ] **Step 2: Run the Markdown check**

Run from the parent `CodexClawProj` repository:

```bash
npm run lint:md -- \
  poc/codex-thread-status-macos/docs/superpowers/specs/2026-07-16-threadbeacon-naming-design.md \
  poc/codex-thread-status-macos/docs/superpowers/plans/2026-07-16-threadbeacon-rename.md
```

Expected: `Summary: 0 error(s)`.

- [ ] **Step 3: Commit the planning checkpoint**

```bash
git add docs/superpowers/specs/2026-07-16-threadbeacon-naming-design.md \
  docs/superpowers/plans/2026-07-16-threadbeacon-rename.md
git diff --cached --check
git commit -m "docs: finalize ThreadBeacon naming plan"
```

Expected: one docs-only commit containing the revised spec and this plan.

### Task 2: Add an executable App identity verification contract

**Files:**

- Create: `script/verify_app_identity.sh`

- [ ] **Step 1: Write the verification script before changing the build**

Create an executable script with this contract:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/ThreadBeacon.app"
PLIST="$APP/Contents/Info.plist"

test -d "$APP"
test -x "$APP/Contents/MacOS/ThreadBeacon"
test "$(plutil -extract CFBundleExecutable raw "$PLIST")" = "ThreadBeacon"
test "$(plutil -extract CFBundleIdentifier raw "$PLIST")" = \
    "io.github.exdevillee.threadbeacon.macos"
test "$(plutil -extract CFBundleName raw "$PLIST")" = "ThreadBeacon"
test "$(plutil -extract CFBundleDisplayName raw "$PLIST")" = "ThreadBeacon"

echo "App identity verification passed"
```

- [ ] **Step 2: Run it to verify the old build fails the new contract**

Run:

```bash
chmod +x script/verify_app_identity.sh
./script/verify_app_identity.sh
```

Expected: non-zero exit because `dist/ThreadBeacon.app` does not exist yet.

### Task 3: Rename SwiftPM modules, sources, tests, and tools

**Files:**

- Modify: `Package.swift`
- Rename: `Sources/CodexThreadStatus/` to `Sources/ThreadBeacon/`
- Rename: `Sources/CodexThreadStatusCore/` to `Sources/ThreadBeaconCore/`
- Rename: `Tests/CodexThreadStatusTests/` to `Tests/ThreadBeaconTests/`
- Rename: `Tools/CodexThreadStatusProbe/` to `Tools/ThreadBeaconProbe/`
- Modify: all Swift files under the renamed source, test, and tool directories

- [ ] **Step 1: Rename the four directories**

```bash
mv Sources/CodexThreadStatus Sources/ThreadBeacon
mv Sources/CodexThreadStatusCore Sources/ThreadBeaconCore
mv Tests/CodexThreadStatusTests Tests/ThreadBeaconTests
mv Tools/CodexThreadStatusProbe Tools/ThreadBeaconProbe
```

- [ ] **Step 2: Replace the SwiftPM manifest with the new target contract**

`Package.swift` must declare:

```swift
let package = Package(
    name: "ThreadBeacon",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ThreadBeacon", targets: ["ThreadBeacon"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "ThreadBeaconCore", dependencies: ["CSQLite"]),
        .executableTarget(
            name: "ThreadBeacon",
            dependencies: ["ThreadBeaconCore"]
        ),
        .executableTarget(
            name: "ThreadBeaconTests",
            dependencies: ["ThreadBeaconCore", "CSQLite"],
            path: "Tests/ThreadBeaconTests"
        ),
        .executableTarget(
            name: "ThreadBeaconProbe",
            dependencies: ["ThreadBeaconCore"],
            path: "Tools/ThreadBeaconProbe"
        )
    ],
    swiftLanguageModes: languageModes
)
```

- [ ] **Step 3: Rename imports and entry-point types**

Every `import CodexThreadStatusCore` becomes:

```swift
import ThreadBeaconCore
```

Rename these entry-point types:

```swift
struct ThreadBeaconApp: App
enum ThreadBeaconProbe
```

The SwiftUI scene title must be:

```swift
WindowGroup("ThreadBeacon")
```

- [ ] **Step 4: Confirm no current technical identifier remains**

Run:

```bash
rg -n "CodexThreadStatus" Package.swift Sources Tests Tools
```

Expected: no matches.

### Task 4: Rename packaging, runtime, and verification scripts

**Files:**

- Modify: `script/build_and_run.sh`
- Modify: `script/probe.sh`
- Modify: `script/test.sh`
- Modify: `script/verify_app_icon.sh`
- Test: `script/verify_app_identity.sh`

- [ ] **Step 1: Update build output and bundle metadata**

`script/build_and_run.sh` must use:

```bash
APP="$ROOT/dist/ThreadBeacon.app"
pkill -x ThreadBeacon 2>/dev/null || true
cp "$BIN_DIR/ThreadBeacon" "$MACOS/ThreadBeacon"
chmod +x "$MACOS/ThreadBeacon"
plutil -insert CFBundleExecutable -string ThreadBeacon "$PLIST"
plutil -insert CFBundleIdentifier -string \
    io.github.exdevillee.threadbeacon.macos "$PLIST"
plutil -insert CFBundleName -string ThreadBeacon "$PLIST"
plutil -insert CFBundleDisplayName -string ThreadBeacon "$PLIST"
```

The `--verify` branch must use `pgrep -x ThreadBeacon` and report
`ThreadBeacon is running` or `ThreadBeacon did not stay running`.

- [ ] **Step 2: Update test and probe target names**

```bash
# script/test.sh
exec "$ROOT/script/swiftpm.sh" run ThreadBeaconTests

# script/probe.sh
exec "$ROOT/script/swiftpm.sh" run ThreadBeaconProbe
```

- [ ] **Step 3: Update icon verification to the new App bundle**

```bash
APP="$ROOT/dist/ThreadBeacon.app"
```

- [ ] **Step 4: Run unit tests**

Run:

```bash
./script/test.sh
```

Expected: all 17 tests pass.

### Task 5: Update current product documentation without rewriting history

**Files:**

- Modify: `README.md`
- Modify: `README-EN.md`
- Modify: `ROADMAP.md`
- Modify: `PRIVACY.md`
- Modify: `SECURITY.md`
- Modify: `docs/prior-art-review.md`

- [ ] **Step 1: Apply the public naming hierarchy**

Use these exact headings and descriptions:

```markdown
# ThreadBeacon for Codex

一个用于集中查看 Codex 主任务状态的原生 macOS 小窗口。
```

```markdown
# ThreadBeacon for Codex

A native macOS status window for monitoring primary Codex tasks at a glance.
```

Use `ThreadBeacon` as the product subject in ROADMAP, PRIVACY, and SECURITY.
Update paths and process commands to `dist/ThreadBeacon.app` and `ThreadBeacon`.

- [ ] **Step 2: Preserve prior-art provenance**

Keep the old `codex-traffic-light` names and old repository link where they record historical
search results or the initial commit. Add a decision note stating that the current product name
is `ThreadBeacon for Codex` and the macOS repository is `codex-threadbeacon-macos`.

- [ ] **Step 3: Add the cross-platform repository convention**

README should state that platform implementations use separate repositories and that related
repositories will be linked only when they exist. Do not add links to hypothetical repositories.

- [ ] **Step 4: Run Markdown lint**

Run from the parent repository:

```bash
npm run lint:md -- \
  poc/codex-thread-status-macos/README.md \
  poc/codex-thread-status-macos/README-EN.md \
  poc/codex-thread-status-macos/ROADMAP.md \
  poc/codex-thread-status-macos/PRIVACY.md \
  poc/codex-thread-status-macos/SECURITY.md \
  poc/codex-thread-status-macos/docs/prior-art-review.md \
  poc/codex-thread-status-macos/docs/superpowers/specs/2026-07-16-threadbeacon-naming-design.md \
  poc/codex-thread-status-macos/docs/superpowers/plans/2026-07-16-threadbeacon-rename.md
```

Expected: `Summary: 0 error(s)`.

### Task 6: Build and verify the renamed macOS App

**Files:**

- Verify: `dist/ThreadBeacon.app`

- [ ] **Step 1: Build and launch the renamed App**

Run:

```bash
./script/build_and_run.sh --verify
```

Expected: `ThreadBeacon is running`.

- [ ] **Step 2: Verify bundle identity and icon**

Run:

```bash
./script/verify_app_identity.sh
./script/verify_app_icon.sh
./script/probe.sh
```

Expected:

```text
App identity verification passed
App icon bundle verification passed
```

The probe must exit successfully and print only task/status counts.

- [ ] **Step 3: Run final stale-name and privacy scans**

Run:

```bash
rg -n "CodexThreadStatus|Codex 红绿灯|Codex Traffic Light" \
  --glob '!docs/prior-art-review.md' \
  --glob '!docs/superpowers/**' \
  --glob '!dist/**' \
  --glob '!.build/**' .
rg -n -i "WECHAT_MP_COOKIE|gho_|github_pat_|BEGIN .*PRIVATE KEY|/Users/songlinli" \
  --glob '!dist/**' --glob '!.build/**' .
```

Expected: no unintended stale product names and no sensitive values.

- [ ] **Step 4: Commit the local rename**

```bash
git add Package.swift Sources Tests Tools script README.md README-EN.md ROADMAP.md \
  PRIVACY.md SECURITY.md docs/prior-art-review.md
git diff --cached --check
git commit -m "refactor: rename app to ThreadBeacon"
```

Expected: a single reviewable rename commit after the docs planning checkpoint.

### Task 7: Rename and verify the private GitHub repository

**Files:**

- External state: `ExDevilLee/codex-traffic-light`
- Modify: local Git remote `origin`

- [ ] **Step 1: Reconfirm target availability and current visibility**

Run:

```bash
gh api --method GET /search/repositories \
  -f q='codex-threadbeacon-macos in:name'
gh repo view ExDevilLee/codex-traffic-light --json visibility,name,url
```

Expected: no conflicting exact repository name and current visibility `PRIVATE`.

- [ ] **Step 2: Rename the repository without changing visibility**

Run:

```bash
gh repo rename codex-threadbeacon-macos \
  --repo ExDevilLee/codex-traffic-light --yes
```

Expected: repository URL becomes
`https://github.com/ExDevilLee/codex-threadbeacon-macos`.

- [ ] **Step 3: Update origin, description, and push**

Run:

```bash
git remote set-url origin \
  https://github.com/ExDevilLee/codex-threadbeacon-macos.git
gh repo edit ExDevilLee/codex-threadbeacon-macos \
  --description "A native macOS status window for monitoring primary Codex tasks at a glance."
git push origin main
```

Expected: the planning and rename commits are present on the renamed private repository.

- [ ] **Step 4: Verify final local and remote state**

Run:

```bash
git status --short
git rev-parse HEAD
git rev-parse origin/main
git remote -v
gh repo view ExDevilLee/codex-threadbeacon-macos \
  --json visibility,name,url,defaultBranchRef
```

Expected: clean worktree, matching local/remote commit IDs, `main` default branch, and
`PRIVATE` visibility.
