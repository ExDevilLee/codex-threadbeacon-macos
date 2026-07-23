# ThreadBeacon Troubleshooting

[简体中文](troubleshooting.md)

This guide applies to the ThreadBeacon macOS technical preview downloaded from GitHub
Releases. Before troubleshooting, confirm that you are running macOS 14 or later and that
Codex Desktop or Codex CLI has run at least one task.

## macOS Blocks The App

The current preview is ad-hoc signed and has not been notarized by Apple. Gatekeeper may block
the first launch:

1. Confirm that the app came from this project's
   [GitHub Releases](https://github.com/ExDevilLee/codex-threadbeacon-macos/releases) or the
   `ExDevilLee/tap/threadbeacon` cask, and that it is in `/Applications`.
2. If the warning only offers **Move to Trash** and **Done**, select **Done**, not
   **Move to Trash**.
3. Open Finder's **Applications** folder, Control-click `ThreadBeacon.app`, and select **Open**.
4. Select **Open** again in the second confirmation dialog.
5. If **Open** is still unavailable, open **System Settings > Privacy & Security**, scroll to the
   notice that ThreadBeacon was blocked, and select **Open Anyway**. Authenticate with your
   password or Touch ID when requested, then confirm **Open**.

This is a limitation of the current technical-preview signature, not a failed Homebrew install.
Do not disable Gatekeeper or run untrusted `xattr`, quarantine-removal, or system-security bypass
commands. Remove this temporary first-launch guidance after Developer ID Application signing and
Apple notarization are available.

## No Tasks Appear

Check these items in order:

1. Create and run a real primary task in Codex Desktop or Codex CLI.
2. Make sure the ThreadBeacon toolbar is not filtering to favorites only.
3. If the ignored-task control is visible, check whether the task was temporarily ignored.
4. Make sure monitoring is not paused, or use manual refresh.
5. Open the data-source health control in the bottom-right corner and check the task database.

ThreadBeacon shows recent primary tasks and does not list Subagents as independent primary rows.
Settings can change the task limit to `4 / 8 / 12 / 20`. If the task database is unavailable,
confirm that `~/.codex/state_5.sqlite` exists for the current macOS user. Do not edit or replace it.

## A Task Name Is Not The Latest Codex Name

ThreadBeacon prefers the latest valid rename in `~/.codex/session_index.jsonl`. If the Rename
index is unavailable, it safely falls back to the original database title and reports degradation
in data-source health. Refresh and check the Rename index status instead of editing Codex files.

## A Status Stays Unknown Or Does Not Change

- An unresolved turn with no new event for more than 120 seconds becomes `unknown` so an
  interrupted task is not reported as running forever.
- A quiet, long-running tool call may temporarily appear as `unknown`.
- `justCompleted` lasts for 1 minute by default. Settings can select `1-5 minutes`, after which it
  becomes `idle`.
- Paused monitoring does not refresh automatically, but manual refresh remains available.

If the Rollout source is degraded or unavailable, report only its health category and
success/failure counts. Do not attach rollout files.

## Token Numbers Do Not Match Expectations

- Cumulative Tokens represent processing across model calls. They are not the current context
  length or a cost estimate.
- Current-turn usage is the difference between two reliable cumulative snapshots. If the rollout
  tail has no baseline, the UI shows `—` instead of guessing from one call.
- Primary task usage does not aggregate Subagents. Each expanded direct Subagent shows its own
  cumulative usage.
- The cumulative compaction count comes from rollout history. Live compacting state appears only
  after the user explicitly installs the Codex Hook.

## No Service Incident Warning Appears

Incident detection reads structured HTTP 4xx/5xx evidence for visible primary tasks from only three
allowlisted log targets, plus explicit selected-model capacity errors from
`codex_core::session::turn`. HTTP 400 becomes a red failure only when an allowlisted target contains
an explicit structured `Bad Request` record; the same words in conversation text are ignored. Logs
can rotate, so old incidents may disappear. ThreadBeacon does not infer failures from silence,
conversation text, or ordinary timeouts, and it cannot yet detect approval waiting reliably.

## A Notification Sound Does Not Play

1. In Settings > Sounds, enable the master switch and the relevant event switch.
2. Use the preview button to verify the app and system output volume.
3. If a custom file is moved, deleted, or unsupported, the app falls back to the selected built-in
   sound.
4. App launch, manual refresh, and resumed monitoring do not replay historical events.
5. Archived favorites do not trigger completion or incident sounds.

## Subagent Counts Or Details Look Unexpected

The badge uses `active/total`, such as `2/27`. The numerator includes only direct Subagents
confirmed as running from recent rollout evidence, while the denominator is the historical total
created by the primary task. Expanding the task loads direct child details. Deeper trees and
aggregated parent-child Tokens are outside the current version.

## Launch At Login Is Unavailable

Launch at login depends on macOS accepting a stably signed app bundle. The current preview has no
Developer ID Application signature or notarization, so this feature is not guaranteed. Do not use
a custom LaunchAgent to bypass the system state. The project will test it again after formal
signing is available.

## Upgrade, Roll Back, Or Uninstall

ThreadBeacon silently checks GitHub Releases once after launch, and About provides a manual check.
When a newer version is available, the footer shows an update icon that opens the matching Release
page in the default browser. If a check fails, confirm that `api.github.com` is reachable or retry
from About later. A failed update check does not affect task monitoring or Codex data-source health.

To upgrade, quit ThreadBeacon, download the new version, and replace the old
`/Applications/ThreadBeacon.app`. The app only provides a reminder; it does not download or install
updates automatically.

To roll back, download an older GitHub Release, quit the current app, and replace it. Preferences
normally remain in the current macOS user account, but compatibility across every version is not
guaranteed.

To uninstall, first disable launch at login in Settings if it was ever enabled successfully, quit
the app, and delete `/Applications/ThreadBeacon.app`. ThreadBeacon installs no separate daemon or
system service.

## Before Opening An Issue

Safe information to provide:

- ThreadBeacon Release version, such as `v0.1.0`.
- macOS major version and Mac architecture, such as `macOS 15 / Apple Silicon`.
- Codex Desktop or Codex CLI version.
- Data-source health categories and Rollout success/failure counts.
- Redacted steps reproducible from a blank environment.

Never post:

- Task titles, task IDs, conversation bodies, or reasoning.
- `state_5.sqlite`, `logs_2.sqlite`, `session_index.jsonl`, or rollout files.
- Usernames, absolute paths, request IDs, provider URLs, tokens, cookies, or credentials.
- Unredacted desktop screenshots or complete terminal logs.

Follow [`SECURITY.md`](../SECURITY.md) for vulnerabilities. Do not disclose sensitive security
details in a normal public Issue.
