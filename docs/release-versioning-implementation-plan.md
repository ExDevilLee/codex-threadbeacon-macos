# ThreadBeacon Versioning And Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立由语义化 Git Tag 驱动的 ThreadBeacon macOS Universal App 技术预览版发布闭环。

**Architecture:** Xcode 的 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION` 保持为 App 版本事实来源；Shell 脚本提供可在本机与 CI 共用的版本、变更日志、构建和产物验证能力；GitHub Actions 只负责在 Tag 上编排这些脚本并创建 Release。所有上传前检查必须先通过，失败时不生成或覆盖公开 Release。

**Tech Stack:** Xcode/xcodebuild、Bash、SwiftPM tests、macOS `ditto`/`codesign`/`lipo`/`shasum`、GitHub Actions、GitHub CLI。

---

## 文件结构

- `CHANGELOG.md`：人工维护的用户可读版本变更记录，也是 Release notes 的事实来源。
- `script/release_lib.sh`：无构建副作用的 Tag、版本及 Changelog 解析函数。
- `script/test_release_lib.sh`：使用临时 fixture 验证发布元数据规则。
- `script/verify_app_identity.sh`：扩展为可校验指定 App，同时保持原有默认路径兼容。
- `script/verify_release.sh`：验证 App 身份、版本、构建号、双架构及签名。
- `script/package_release.sh`：构建、验证、压缩并反向验证可下载产物。
- `.github/workflows/release.yml`：Tag 驱动的测试、打包与 GitHub Release 编排。
- `README.md`、`README-EN.md`：面向下载用户的安装入口和技术预览边界。
- `ROADMAP.md`、`docs/public-sharing-readiness.md`：同步发布能力状态和后续正式签名工作。

### Task 1: 发布元数据规则与变更日志

**Files:**

- Create: `CHANGELOG.md`
- Create: `script/test_release_lib.sh`
- Create: `script/release_lib.sh`

- [ ] **Step 1: 编写失败的发布规则测试**

创建 `script/test_release_lib.sh`，覆盖合法 Tag、非法 Tag、Tag 到版本转换、存在版本章节、
缺失版本章节和版本说明提取：

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/script/release_lib.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

## [0.1.0] - 2026-07-20

### Added

- First preview.

## [0.0.1] - 2026-07-19
EOF

assert_eq() {
    [[ "$1" == "$2" ]] || {
        echo "Expected '$2', got '$1'" >&2
        exit 1
    }
}

validate_release_tag "v0.1.0"
if validate_release_tag "0.1.0" 2>/dev/null; then
    echo "Expected an invalid tag failure" >&2
    exit 1
fi
assert_eq "$(version_from_tag "v0.1.0")" "0.1.0"
require_changelog_version "$TMP/CHANGELOG.md" "0.1.0"
if require_changelog_version "$TMP/CHANGELOG.md" "0.2.0" 2>/dev/null; then
    echo "Expected a missing changelog version failure" >&2
    exit 1
fi
extract_changelog_version "$TMP/CHANGELOG.md" "0.1.0" > "$TMP/notes.md"
rg -q '^## \[0\.1\.0\]' "$TMP/notes.md"
rg -q 'First preview\.' "$TMP/notes.md"
if rg -q '0\.0\.1' "$TMP/notes.md"; then
    echo "Release notes included the next version" >&2
    exit 1
fi

echo "Release metadata tests passed"
```

- [ ] **Step 2: 运行测试并确认因实现缺失而失败**

Run: `./script/test_release_lib.sh`

Expected: FAIL，提示 `script/release_lib.sh` 不存在。

- [ ] **Step 3: 实现最小发布规则库**

创建 `script/release_lib.sh`：

```bash
#!/usr/bin/env bash

validate_release_tag() {
    local tag="$1"
    [[ "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || {
        echo "Invalid release tag: $tag (expected vMAJOR.MINOR.PATCH)" >&2
        return 1
    }
}

version_from_tag() {
    local tag="$1"
    validate_release_tag "$tag"
    printf '%s\n' "${tag#v}"
}

require_changelog_version() {
    local changelog="$1"
    local version="$2"
    rg -q "^## \\[$version\\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$changelog" || {
        echo "CHANGELOG is missing version $version" >&2
        return 1
    }
}

extract_changelog_version() {
    local changelog="$1"
    local version="$2"
    require_changelog_version "$changelog" "$version"
    awk -v heading="## [$version]" '
        index($0, heading) == 1 { printing = 1 }
        printing && $0 ~ /^## \[/ && index($0, heading) != 1 { exit }
        printing { print }
    ' "$changelog"
}
```

- [ ] **Step 4: 添加首版变更日志**

创建 `CHANGELOG.md`，包含 `Unreleased` 和 `0.1.0`（日期使用实际发版日期）。`0.1.0` 至少
记录主任务状态、Token 详情、Subagent 展开、收藏/置顶/忽略、提示音、Settings、国际化、
主题、多显示器位置恢复、只读隐私边界和技术预览分发限制。

- [ ] **Step 5: 运行发布规则测试**

Run: `chmod +x script/test_release_lib.sh && ./script/test_release_lib.sh`

Expected: `Release metadata tests passed`

- [ ] **Step 6: 提交发布元数据基础**

```bash
git add CHANGELOG.md script/release_lib.sh script/test_release_lib.sh
git commit -m "feat(release): add version metadata validation"
```

### Task 2: App 发布验证与 Universal ZIP 打包

**Files:**

- Modify: `script/verify_app_identity.sh`
- Create: `script/verify_release.sh`
- Create: `script/package_release.sh`

- [ ] **Step 1: 让身份校验脚本接受显式 App 路径**

把 `script/verify_app_identity.sh` 的 App 定义改为：

```bash
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/dist/ThreadBeacon.app}"
PLIST="$APP/Contents/Info.plist"
```

其余身份断言保持不变，保证 `./script/verify_app_identity.sh` 的既有调用仍然有效。

- [ ] **Step 2: 编写发布验证脚本**

创建 `script/verify_release.sh`，参数为 App 路径和 Tag。脚本必须：

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/script/release_lib.sh"

APP="${1:?Usage: verify_release.sh APP_PATH TAG}"
TAG="${2:?Usage: verify_release.sh APP_PATH TAG}"
VERSION="$(version_from_tag "$TAG")"
PLIST="$APP/Contents/Info.plist"
EXECUTABLE="$APP/Contents/MacOS/ThreadBeacon"

"$ROOT/script/verify_app_identity.sh" "$APP"

ACTUAL_VERSION="$(plutil -extract CFBundleShortVersionString raw "$PLIST")"
BUILD_NUMBER="$(plutil -extract CFBundleVersion raw "$PLIST")"
[[ "$ACTUAL_VERSION" == "$VERSION" ]]
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]

ARCHS="$(lipo -archs "$EXECUTABLE")"
[[ " $ARCHS " == *" arm64 "* ]]
[[ " $ARCHS " == *" x86_64 "* ]]
codesign --verify --deep --strict "$APP"

echo "Release verification passed: $VERSION ($BUILD_NUMBER), $ARCHS"
```

每个失败断言补充明确错误文本，使 CI 日志能直接指出版本、构建号或架构问题。

- [ ] **Step 3: 编写发布打包脚本**

创建 `script/package_release.sh`，接受一个 Tag，并执行：

```bash
TAG="${1:?Usage: package_release.sh vMAJOR.MINOR.PATCH}"
VERSION="$(version_from_tag "$TAG")"
require_changelog_version "$ROOT/CHANGELOG.md" "$VERSION"

xcodebuild \
    -project "$ROOT/ThreadBeacon.xcodeproj" \
    -scheme ThreadBeacon \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    build
```

然后依次调用 `verify_release.sh`、用 `ditto -c -k --sequesterRsrc --keepParent` 生成 ZIP、
用 `shasum -a 256` 生成校验文件、解压到临时目录并对解压后的 App 再运行一次
`verify_release.sh`。输出目录固定为 `dist/release`，文件名使用设计文档约定；重复运行先清理
同版本临时产物，但不触碰其他版本。

- [ ] **Step 4: 验证错误 Tag 会在构建前失败**

Run: `./script/package_release.sh 0.1.0`

Expected: FAIL，提示必须使用 `vMAJOR.MINOR.PATCH`。

- [ ] **Step 5: 构建并验证真实 Universal 产物**

Run: `chmod +x script/verify_release.sh script/package_release.sh && ./script/package_release.sh v0.1.0`

Expected:

- `Release verification passed: 0.1.0 (1), ... arm64 ... x86_64 ...`
- `dist/release/ThreadBeacon-v0.1.0-macos-universal.zip` 存在且非空。
- 对应 `.sha256` 使用 `shasum -a 256 -c` 返回 `OK`。

- [ ] **Step 6: 提交打包与验证脚本**

```bash
git add script/verify_app_identity.sh script/verify_release.sh script/package_release.sh
git commit -m "feat(release): package universal macOS preview builds"
```

### Task 3: Tag 驱动的 GitHub Release

**Files:**

- Create: `.github/workflows/release.yml`

- [ ] **Step 1: 创建最小权限 Workflow**

创建 `.github/workflows/release.yml`：

```yaml
name: Release

on:
  push:
    tags:
      - "v*"

permissions:
  contents: write

concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false

jobs:
  release:
    runs-on: macos-15
    steps:
      - name: Check out release tag
        uses: actions/checkout@v4

      - name: Test
        run: |
          ./script/test_release_lib.sh
          ./script/test.sh

      - name: Package universal app
        run: ./script/package_release.sh "$GITHUB_REF_NAME"

      - name: Create GitHub prerelease
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh release create "$GITHUB_REF_NAME" \
            dist/release/*.zip \
            dist/release/*.sha256 \
            --title "ThreadBeacon $GITHUB_REF_NAME" \
            --notes-file dist/release/release-notes.md \
            --prerelease \
            --verify-tag
```

`package_release.sh` 在 Task 2 中同时使用 `extract_changelog_version` 写出
`dist/release/release-notes.md`。不使用可覆盖现有 Release 的参数。

- [ ] **Step 2: 静态检查 Workflow 与关键命令**

Run:

```bash
rg -n 'tags:|contents: write|macos-15|package_release|gh release create|--prerelease|--verify-tag' .github/workflows/release.yml
git diff --check
```

Expected: 所有发布保护项均可找到，`git diff --check` 无输出。

- [ ] **Step 3: 提交 Workflow**

```bash
git add .github/workflows/release.yml script/package_release.sh
git commit -m "ci(release): publish tagged macOS preview builds"
```

### Task 4: 下载、安装和路线图文档

**Files:**

- Modify: `README.md`
- Modify: `README-EN.md`
- Modify: `ROADMAP.md`
- Modify: `docs/public-sharing-readiness.md`

- [ ] **Step 1: 在中文 README 增加下载与安装入口**

在“界面预览”和“运行”之间新增“下载与安装”，包含：

- GitHub Releases 链接。
- 下载 `ThreadBeacon-vX.Y.Z-macos-universal.zip`。
- 可选 SHA-256 验证命令。
- 解压并拖入 `/Applications`。
- 当前 ad-hoc 签名、未公证和 Gatekeeper 首次打开说明。
- 登录时启动暂不承诺可用。
- 从源码运行内容继续保留，并将标题调整为“从源码运行”。

- [ ] **Step 2: 同步英文 README**

在相同位置新增 `Download And Install`，信息范围与中文完全一致，不新增中文版本没有的
兼容承诺。

- [ ] **Step 3: 更新路线图与公开分享检查表**

`ROADMAP.md` 将版本管理、Changelog、Tag、Universal ZIP、SHA-256 和 GitHub Release
标记为已完成的技术预览能力；Developer ID、公证、登录启动发布复验仍保持未完成。

`docs/public-sharing-readiness.md` 将“普通用户无下载产物”和“缺少自动 Release”更新为
已解决，同时明确它尚未满足正式签名、公证的 P0 条件。

- [ ] **Step 4: 检查双语边界和 Markdown**

Run:

```bash
git diff --check
npm run lint:md -- \
  poc/codex-thread-status-macos/CHANGELOG.md \
  poc/codex-thread-status-macos/README.md \
  poc/codex-thread-status-macos/README-EN.md \
  poc/codex-thread-status-macos/ROADMAP.md \
  poc/codex-thread-status-macos/docs/public-sharing-readiness.md
```

第二条命令从 `CodexClawProj` 根目录运行。Expected: 0 errors。

- [ ] **Step 5: 提交公开文档**

```bash
git add README.md README-EN.md ROADMAP.md docs/public-sharing-readiness.md
git commit -m "docs(release): document preview downloads and installation"
```

### Task 5: 首版发布端到端验收

**Files:**

- Verify: `CHANGELOG.md`
- Verify: `.github/workflows/release.yml`
- Verify: `dist/release/ThreadBeacon-v0.1.0-macos-universal.zip`

- [ ] **Step 1: 运行完整本地回归**

Run:

```bash
./script/test_release_lib.sh
./script/test.sh
./script/package_release.sh v0.1.0
cd dist/release && shasum -a 256 -c ThreadBeacon-v0.1.0-macos-universal.zip.sha256
```

Expected: 元数据测试、Core 测试、两次 App 验证及 SHA-256 全部通过。

- [ ] **Step 2: 检查仓库与版本一致性**

Run:

```bash
git diff --check
git status --short
git tag --list v0.1.0
```

Expected: 工作区干净，`v0.1.0` 尚不存在。

- [ ] **Step 3: 推送发布实现提交**

Run: `git push origin main`

Expected: `origin/main` 指向本地最新提交。

- [ ] **Step 4: 创建并推送签名 Tag**

```bash
git tag -s v0.1.0 -m "ThreadBeacon v0.1.0" || \
  git tag -a v0.1.0 -m "ThreadBeacon v0.1.0"
git push origin v0.1.0
```

优先使用本机 Git 签名配置；没有可用签名密钥时退回 annotated Tag，不创建 lightweight
Tag。Expected: GitHub Actions 的 Release Workflow 被触发。

- [ ] **Step 5: 等待并检查 GitHub Actions**

Run: `gh run watch --exit-status`

Expected: Release Workflow 成功；若失败，保留 Tag 和日志证据，修复后使用 GitHub 的
re-run，不移动或重建已经推送的 Tag。

- [ ] **Step 6: 下载 GitHub Release 产物做最终验证**

```bash
TMP="$(mktemp -d)"
gh release download v0.1.0 --dir "$TMP"
cd "$TMP"
shasum -a 256 -c ThreadBeacon-v0.1.0-macos-universal.zip.sha256
ditto -x -k ThreadBeacon-v0.1.0-macos-universal.zip unpacked
```

Run: 对 `unpacked/ThreadBeacon.app` 执行 `script/verify_release.sh ... v0.1.0`。

Expected: 从 GitHub 下载的产物与本地发布规则一致。最后人工从该下载包启动 App，验证主
窗口、Settings、刷新、Subagent 展开和提示音基本链路。
