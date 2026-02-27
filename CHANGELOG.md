# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
