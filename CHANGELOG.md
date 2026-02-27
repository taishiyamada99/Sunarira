# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.2] - 2026-02-27

### Added

- Startup setting to toggle launch at login from the Settings window.
- Launch-at-login status feedback message in Settings when macOS approval is required or unavailable.
- About section in Settings with app version display.

### Changed

- Marketing version updated to `0.2.2`.
- Settings now display release label as `v0.2.2`.
- Internal App Server stdio client metadata version updated from `0.2.2-alpha` to `0.2.2`.

## [0.2.1] - 2026-02-27

### Added

- Transform result notification for every successful transform with:
  - source character count
  - transformed character count
  - compression percentage (`output/input*100`, floored integer)
- In-app top-right toast for transform result, with auto-hide behavior (about 2.5s).
- In-app top-right toast for transform failures (including accessibility-not-granted failures).
- Interface language selector switched from segmented control to pull-down menu.
- Added interface language support for German, Spanish, and French.

### Changed

- Successful transform notifications now use compact single-line message format:
  - Japanese: `100→80文字(80%,1.2秒)`
  - English: `100→80 chars (80%, 1.2s)`
- Toast presentation now dynamically resizes by message length/language to avoid clipping.
- Settings layout reorganized:
  - basic sections remain visible for regular users (language/modes/keyboard shortcuts/accessibility)
  - advanced sections (`App Server`, `Logs`) are hidden behind an Administrator Mode toggle
- Keyboard shortcut model changed:
  - removed dedicated `Mode cycle` keyboard shortcut
  - added per-mode direct keyboard shortcuts (`Mode 1`..`Mode 5`)
  - pressing a mode keyboard shortcut switches to that mode and runs transform

## [0.2.0] - 2026-02-26

### Added

- User-defined transform modes (1 to 5), each with editable display name,
  prompt template, and model.
- Model refresh flow using App Server `model/list`.
- Runtime status indicator in menu bar icon (idle/capturing/waiting/applying).
- Logs view in settings and optional sensitive text logging toggle.
- CI workflow for macOS build/tests via GitHub Actions.
- Open-source governance docs:
  - `LICENSE` (MIT)
  - `ASSETS_LICENSE.md`
  - `CONTRIBUTING.md`
  - `CODE_OF_CONDUCT.md`
  - `SECURITY.md`
  - `PRIVACY.md`

### Changed

- App Server transport unified to stdio JSON-RPC with:
  - `initialize`
  - `model/list`
  - `thread/start`
  - `turn/start`
  - `thread/read`
- Default model policy prefers non-codex latest models when available, while
  preserving fallback behavior.
- Localized UI coverage expanded for English/Japanese settings and menu items.
- Transform latency logging now records request-to-completion in milliseconds.

### Removed

- Legacy fixed transform menus (structure/emoji/language fixed hierarchy).
- Legacy transport methods (`newConversation` / `sendUserTurn`).

### Notes

- Preferences schema reset behavior remains intentional for legacy config.
- Accessibility + clipboard fallback behavior remains unchanged by this release.
