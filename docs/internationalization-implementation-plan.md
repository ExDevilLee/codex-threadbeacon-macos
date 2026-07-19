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

- [x] Add tests for explicit Chinese, explicit English, Chinese system resolution, English system resolution and unsupported-language English fallback.
- [x] Implement `AppLanguage.system`, `.simplifiedChinese` and `.english`, plus deterministic locale resolution from preferred language identifiers.
- [x] Persist the raw language value under `DisplayPreferenceKeys.appLanguage`, defaulting invalid or missing values to `.system`.
- [x] Run `./script/test.sh` and confirm all tests pass.

## Task 2: App locale injection and Settings picker

**Files:**

- Modify: `Sources/ThreadBeacon/App/ThreadBeaconApp.swift`
- Modify: `Sources/ThreadBeacon/Views/ThreadBeaconSettingsView.swift`

- [x] Add `@AppStorage(DisplayPreferenceKeys.appLanguage)` at the App scene root.
- [x] Resolve the stored value with `Locale.preferredLanguages` and inject the locale into both `WindowGroup` and `Settings` content.
- [x] Add a General Settings language Picker with three stable raw-value tags.
- [x] Build the Xcode App target and confirm it compiles.

## Task 3: String catalog and visible UI coverage

**Files:**

- Create: `Resources/Localizable.xcstrings`
- Modify: `ThreadBeacon.xcodeproj/project.pbxproj`
- Modify: `Sources/ThreadBeacon/Views/*.swift`
- Modify: `Sources/ThreadBeacon/Support/RelativeTimeFormatter.swift`
- Modify: selected semantic formatters under `Sources/ThreadBeaconCore/Support/`

- [x] Add the string catalog to the App target Resources build phase with `zh-Hans` as source language and English translations.
- [x] Replace dynamic status, duration, activity and count strings with localized rendering.
- [x] Cover the primary tooltips, accessibility labels, context menus, Settings, Token/Subagent details and empty states.
- [x] Keep task titles, Agent aliases, model values, HTTP codes and raw diagnostic payloads verbatim.
- [x] Build the Xcode target and inspect the built bundle for compiled `en.lproj`; Simplified Chinese uses the catalog source strings as the development language.

## Task 4: Runtime and regression verification

**Files:**

- Modify: `ROADMAP.md`
- Modify: `README.md`
- Modify: `README-EN.md`

- [x] Run `./script/test.sh`; 118 tests pass, including the new language tests.
- [x] Run `./script/build_and_run.sh --verify`; the Apple Development-signed Xcode App stays running.
- [ ] Select each of the three language settings and visually verify immediate main-window and Settings updates.
- [x] Simulate unsupported preferred languages through the pure resolver test and confirm English fallback.
- [x] Update ROADMAP to mark Chinese/English MVP complete and state that more languages will be added later.
- [x] Run Markdown lint on all modified documentation and `git diff --check`.
