# ThreadBeacon Internationalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add immediate Simplified Chinese and English UI switching with English fallback for unsupported system languages.

**Architecture:** Store a semantic `AppLanguage` preference in Core, resolve it to `zh-Hans` or `en`, and inject that locale at the SwiftUI scene root. Compile one App-owned `Localizable.xcstrings`; keep task data and model identifiers untranslated while mapping stable UI semantics to localized keys.

**Tech Stack:** Swift 6, SwiftUI, Foundation localization, Xcode string catalogs, UserDefaults, existing SwiftPM test runner.

---

## Task 1: Language preference model

**Files:**

- Create: `Sources/ThreadBeaconCore/Models/AppLanguage.swift`
- Modify: `Sources/ThreadBeaconCore/Stores/DisplaySettingsRepository.swift`
- Modify: `Sources/ThreadBeaconCore/Models/DisplaySettings.swift`
- Test: `Tests/ThreadBeaconTests/AppLanguageTests.swift`
- Test: `Tests/ThreadBeaconTests/DisplaySettingsTests.swift`

- [ ] Add failing tests for explicit Chinese, explicit English, Chinese system resolution, English system resolution and unsupported-language English fallback.
- [ ] Run `./script/test.sh` and confirm the new tests fail because `AppLanguage` is absent.
- [ ] Implement `AppLanguage.system`, `.simplifiedChinese` and `.english`, plus deterministic locale resolution from preferred language identifiers.
- [ ] Persist the raw language value under `DisplayPreferenceKeys.appLanguage`, defaulting invalid or missing values to `.system`.
- [ ] Run `./script/test.sh` and confirm all tests pass.

## Task 2: App locale injection and Settings picker

**Files:**

- Modify: `Sources/ThreadBeacon/App/ThreadBeaconApp.swift`
- Modify: `Sources/ThreadBeacon/Views/ThreadBeaconSettingsView.swift`

- [ ] Add `@AppStorage(DisplayPreferenceKeys.appLanguage)` at the App scene root.
- [ ] Resolve the stored value with `Locale.preferredLanguages` and inject the locale into both `WindowGroup` and `Settings` content.
- [ ] Add a General Settings language Picker with three stable raw-value tags.
- [ ] Build with `xcodebuild -project ThreadBeacon.xcodeproj -scheme ThreadBeacon -configuration Debug -destination 'platform=macOS' build` and confirm the app target compiles.

## Task 3: String catalog and visible UI coverage

**Files:**

- Create: `Resources/Localizable.xcstrings`
- Modify: `ThreadBeacon.xcodeproj/project.pbxproj`
- Modify: `Sources/ThreadBeacon/Views/*.swift`
- Modify: `Sources/ThreadBeacon/Support/RelativeTimeFormatter.swift`
- Modify: selected semantic formatters under `Sources/ThreadBeaconCore/Support/`

- [ ] Add the string catalog to the App target Resources build phase with `zh-Hans` as source language and complete English translations.
- [ ] Replace dynamic verbatim status/health/count strings with stable localization keys or localized SwiftUI interpolations.
- [ ] Cover Tooltip, accessibility labels, context menus, alerts, Settings, Token/Subagent details and empty states.
- [ ] Keep task titles, Agent aliases, model values, HTTP codes and raw diagnostic payloads verbatim.
- [ ] Build the Xcode target and inspect the built bundle for compiled `en.lproj` and `zh-Hans.lproj` localization resources.

## Task 4: Runtime and regression verification

**Files:**

- Modify: `ROADMAP.md`
- Modify: `README.md`
- Modify: `README-EN.md`

- [ ] Run `./script/test.sh`; expected result is the previous 111 tests plus new language tests, all passing.
- [ ] Run `./script/build_and_run.sh --verify`; expected result is a signed or ad hoc Xcode App that stays running.
- [ ] Select each of the three language settings and verify immediate main-window and Settings updates.
- [ ] Simulate an unsupported preferred language through the pure resolver test and confirm English fallback.
- [ ] Update ROADMAP to mark Chinese/English MVP complete and state that more languages will be added later.
- [ ] Run Markdown lint on all modified documentation and `git diff --check`.
