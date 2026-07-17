# ThreadBeacon for Codex

[简体中文](README.md) | English

## Purpose

ThreadBeacon is a native macOS status window for monitoring primary Codex Desktop
and Codex CLI tasks at a glance. The first version tests whether a glanceable status
view reduces the need to repeatedly switch back to Codex. USB displays and Codex
controls are outside the current scope. The current sound feature only covers reliably
detected primary-task completion events and explicit HTTP 429/503 retries or terminal
failures found in local structured logs. Approval waiting still has no reliable read-only
data source.

This is an unofficial community project. It is not affiliated with or endorsed by OpenAI. `Codex` is a trademark of its respective owner.

See [`ROADMAP.md`](ROADMAP.md) for planned features and their proposed validation order.

See the Chinese
[`prior-art review`](docs/prior-art-review.md) for related GitHub projects,
implementation differences, naming risks, and feature candidates.

See the Chinese
[`app-server integration POC`](docs/app-server-integration-poc.md) for evidence about
why an independent app-server cannot currently observe Codex Desktop runtime events.

See the Chinese
[`service incident monitoring design`](docs/service-incident-monitoring.md) for the
429/503 data source, state rules, and privacy boundary.

See the Chinese
[`Codex CLI compatibility POC`](docs/codex-cli-compatibility.md) for the verified data
path and the remaining compatibility boundaries.

## Run

From the project directory:

```bash
./script/build_and_run.sh --verify
```

The script builds and launches:

```text
dist/ThreadBeacon.app
```

Additional verification commands:

```bash
./script/test.sh
./script/probe.sh
```

`probe.sh` prints only the task count and status totals. It does not print task titles or conversation content.

## App Icon

The icon uses the `B1 Graphite / Code Beacon` design: a graphite rounded tile, white braces, and vertically stacked red, amber, and green lights. Assets:

- `Resources/AppIcon-1024.png`: 1024px PNG master.
- `Resources/AppIcon.icns`: standard macOS app icon.

The icon is rendered deterministically with AppKit and can be regenerated locally:

```bash
./script/generate_app_icon.sh
```

`build_and_run.sh` copies the `.icns` file into the app bundle and writes `CFBundleIconFile`. Verify it separately with:

```bash
./script/verify_app_icon.sh
```

## Sound Assets

Beacon, Chime, and Pulse are short sounds generated deterministically by project scripts;
they do not come from a third-party sound pack. Regenerate and verify them with:

```bash
./script/generate_sound_assets.sh
./script/verify_sound_assets.sh
```

## Interface

- Shows the 8 most recent unarchived primary Codex Desktop and Codex CLI tasks by
  default; subagent threads are excluded.
- Each row shows a status light, localized status label, task title, and status duration.
- A primary task that created Subagents shows its direct Subagent count beside the title. This is
  a historical relationship count, not a live running count.
- Click the Subagent count to expand direct children inline. Each row shows
  `agent alias | title`, status, recent activity, and the child's cumulative Token usage. Hover
  over or click the info icon for nickname, role, model, reasoning effort, and Token details.
  Child data is read only while expanded; conversation bodies and deeper task-tree levels are not
  displayed.
- Each row shows a compact cumulative Token total. Hover over the info icon for
  input, cached and uncached input, output, reasoning, current-turn usage, cache
  ratio, and update time; click the icon to keep the details open.
- Task titles prefer the latest renamed value in `session_index.jsonl`, with `threads.title` as fallback.
- The current version does not read or display conversation summaries or message bodies.
- Refreshes automatically every 2 seconds and also supports manual refresh.
- The toolbar can pause or resume automatic monitoring. Manual refresh remains
  available while paused, and monitoring resumes by default after relaunch.
- The pin button keeps the window above other apps and persists the selection across launches.
- The speaker button opens sound settings. Completion and 429/503 incident sounds can be
  disabled and selected independently from Beacon, Chime, and Pulse. Startup, manual refresh,
  and resumed monitoring do not replay historical events.
- Retryable 429/503 incidents appear as yellow `warning`; exhausted retries appear as red
  `error`. One incident episode plays at most one warning sound, and failures suppress a
  misleading completion sound.
- Sort priority is `error`, `needsAction`, `warning`, `running`, `justCompleted`, `idle`, then
  `unknown`.

## Data And Privacy

The app reads only local data:

- `~/.codex/state_5.sqlite`: task metadata, `rollout_path`, cumulative `tokens_used`,
  parent-child relationships, and nickname, role, model, and reasoning effort for expanded direct
  Subagents, opened in SQLite read-only mode.
- `~/.codex/session_index.jsonl`: the latest renamed title matching each task ID.
- Rollout JSONL: at most the final 2 MiB per task, reading only event types,
  timestamps, and numeric Token fields to derive status, usage details, and
  `task_complete` completion events.
- `~/.codex/logs_2.sqlite`: opened read-only and restricted to three allowlisted targets for
  visible tasks. Only turn IDs, HTTP 429/503 status, retry progress, and terminal failure time
  are extracted.

The app does not read `codex_http_client::transport` or extract reasoning summaries,
conversation bodies, full requests, provider URLs, or request IDs. It does not start a network
service, upload data, modify Codex data, or request Accessibility permission. See
[`PRIVACY.md`](PRIVACY.md) for the full privacy statement.

## POC Limitations

- `running` means the latest turn has no later `final` or `final_answer` event and has received a new event within 120 seconds.
- An unresolved turn with no new event for more than 120 seconds becomes `unknown`, preventing interrupted tasks from remaining falsely marked as running. A quiet long-running tool call may also temporarily appear as `unknown`.
- `justCompleted` is retained for 60 seconds, then derived as `idle`.
- Current-turn usage is calculated from two cumulative snapshots. If the rollout
  tail has no reliable baseline, the UI shows `—` instead of guessing from one call.
- Cumulative Tokens represent processing across model calls. They are not the
  current context length and are not a cost estimate.
- The current version plays one completion sound for a new `task_complete` event and one
  incident sound for a new 429/503 episode. A later success clears a retry warning; a terminal
  failure overrides a misleading rollout `task_complete`.
- The app does not infer `error`, `warning`, or `needsAction` from silence, timeouts, or
  conversation text. Current error and warning states require allowlisted 429/503 log evidence;
  approval status is not implemented.
- Codex SQLite, session index, and rollout formats are not stable public APIs and may require adaptation after Codex updates.
- The POC is not sandboxed because it reads `~/.codex`. It is not signed, notarized, or automatically updated.
- The current machine has a SwiftPM Manifest/Test runtime mismatch in Command Line Tools. Project scripts work around it with a temporary, untracked `.build/swiftpm-libs/` copy. Use the provided scripts instead of relying on `swift test` directly.

## Uninstall

Stop the process and remove build artifacts:

```bash
pkill -x ThreadBeacon 2>/dev/null || true
rm -rf dist .build
```

The POC does not install a system service, login item, or global configuration.

## License And Security

- Licensed under the [MIT License](LICENSE).
- See [`SECURITY.md`](SECURITY.md) for security reporting guidance.

## Platform Repositories

ThreadBeacon keeps platform implementations in separate repositories. This
repository contains only the native macOS app. Links under `Related projects`
will be added when another platform implementation actually exists.
