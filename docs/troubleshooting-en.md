# ThreadBeacon Troubleshooting

[简体中文](troubleshooting.md)

This guide applies to the ThreadBeacon macOS technical preview downloaded from GitHub
Releases. Before troubleshooting, confirm that you are running macOS 14 or later and that
Codex Desktop or Codex CLI has run at least one task.

## macOS Blocks The App

The current preview is ad-hoc signed and has not been notarized by Apple. Gatekeeper may block
the first launch:

1. Move `ThreadBeacon.app` to `/Applications`.
2. Control-click the app in Finder and select **Open**.
3. If it is still blocked, open **System Settings > Privacy & Security** and follow the prompt
   that specifically refers to ThreadBeacon.

Do not disable Gatekeeper or run untrusted `xattr` or system-security bypass commands.

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
- `justCompleted` lasts for 60 seconds and then becomes `idle`.
- Paused monitoring does not refresh automatically, but manual refresh remains available.

If the Rollout source is degraded or unavailable, report only its health category and
success/failure counts. Do not attach rollout files.

## No 429/503 Warning Appears

Incident detection reads structured 429/503 evidence for visible primary tasks from only three
allowlisted log targets. Logs can rotate, so old incidents may disappear. ThreadBeacon does not
infer failures from silence, conversation text, or ordinary timeouts, and it cannot yet detect
approval waiting reliably.

## A Notification Sound Does Not Play

1. In Settings > Sounds, enable the master switch and the relevant event switch.
2. Use the preview button to verify the app and system output volume.
3. If a custom file is moved, deleted, or unsupported, the app falls back to the selected built-in
   sound.
4. App launch, manual refresh, and resumed monitoring do not replay historical events.
5. Archived favorites do not trigger completion or incident sounds.

## Subagent Counts Or Details Look Unexpected

The count represents historical direct Subagent relationships, not the number currently running.
Direct child details are read only while a primary task is expanded. Deeper trees and aggregated
parent-child Tokens are outside the current version.

## Launch At Login Is Unavailable

Launch at login depends on macOS accepting a stably signed app bundle. The current preview has no
Developer ID Application signature or notarization, so this feature is not guaranteed. Do not use
a custom LaunchAgent to bypass the system state. The project will test it again after formal
signing is available.

## Upgrade, Roll Back, Or Uninstall

To upgrade, quit ThreadBeacon, download the new version, and replace the old
`/Applications/ThreadBeacon.app`. There is no in-app automatic updater yet.

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
