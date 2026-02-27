# Sunarira v0.2.0

macOS menu bar app that transforms focused text in place using App Server stdio JSON-RPC.

## What Changed

- Transform UX is now based on user-defined modes only (1 to 5 modes).
- Each mode has:
  - display name
  - prompt template
  - model
- Legacy fixed features were removed:
  - structure/emoji/language fixed menus
  - legacy endpoint mode switches
  - legacy `newConversation` / `sendUserTurn` transport
- Protocol is unified to App Server stdio with:
  - `initialize`
  - `model/list`
  - `thread/start`
  - `turn/start`
  - `thread/read`

## Requirements

- macOS 13.0 or later
- Xcode 16+ (for local build/test workflows)
- Swift toolchain compatible with project settings (`SWIFT_VERSION = 6.0`)
- `codex` CLI installed and available in PATH
- App Server command support (default):
  - `codex app-server --listen stdio://`

Runtime permissions:

- Accessibility permission (required for stable in-place replacement)
- Notification permission (optional; used for user-facing status/error notices)

## Build

```bash
xcodebuild test -project Sunarira.xcodeproj -scheme Sunarira -configuration Debug -derivedDataPath build/DerivedData
xcodebuild build -project Sunarira.xcodeproj -scheme Sunarira -configuration Release SYMROOT=build
```

## CI

GitHub Actions runs macOS build/tests on every push and pull request:

- [`.github/workflows/ci.yml`](.github/workflows/ci.yml)

## Release Management

- Changelog: [CHANGELOG.md](CHANGELOG.md)
- Release procedure: [RELEASE.md](RELEASE.md)

Release app output:

- `build/Release/Sunarira.app`

## Run

```bash
open build/Release/Sunarira.app
```

## Permissions

- Accessibility (`System Settings > Privacy & Security > Accessibility`) is required for stable in-place replace.
- If AX replace fails, the app falls back to clipboard-based replace and notifies the user.

## Security

- Sunarira executes the configured `stdio` launch command via shell (`/bin/zsh -lc`).
- Use only trusted commands in App Server settings.
- See [SECURITY.md](SECURITY.md) for trust boundaries, logging behavior, and safe configuration guidance.

## Privacy

- Sunarira reads focused text (or clipboard fallback) only when a transform is triggered.
- Input/output text preview logging is off by default.
- Clipboard may be temporarily overwritten during fallback/paste workflows and then restored.
- See [PRIVACY.md](PRIVACY.md) for detailed data flow, logging surfaces, and retention notes.

## Defaults

- Default model: `gpt-5.2`
- Default stdio command: `codex app-server --listen stdio://`
- Default modes:
  - `汎用`
  - `超端的`
  - `意味保持短縮`

Default hotkeys:

- Transform: `⌃⌥⌘R`
- Cycle mode: `⌃⌥⌘M`

## Settings

- Interface language: `English` / `日本語`
- Modes section:
  - add/remove mode (bounded to 1..5)
  - reorder mode
  - enable/disable mode
  - edit display name / prompt template / model
  - set active mode
- App Server section:
  - edit stdio launch command
  - refresh models via `model/list`
- Hotkeys section:
  - transform
  - cycle mode
- Logs section:
  - refresh / clear runtime logs
  - optional input/output text logging toggle

## Menu Bar

- Single icon status with runtime phase indicator:
  - idle
  - capturing
  - waiting for model response
  - applying output
- Dropdown includes:
  - Transform Now
  - Current Mode
  - Modes
  - Open Settings...
  - Re-register Hotkeys
  - Accessibility status
  - Quit

## E2E

Smoke (local mock stdio, deterministic):

```bash
./scripts/run_e2e_smoke.sh
```

Production (real App Server stdio):

```bash
./scripts/run_e2e_production.sh
```

Optional overrides:

```bash
MODEL=gpt-5.2 WAIT_SECONDS=20 ./scripts/run_e2e_production.sh
STDIO_COMMAND="codex app-server --listen stdio://" ./scripts/run_e2e_production.sh
```

## Protocol Verification

To verify method names/params against the local App Server schema:

```bash
codex app-server generate-json-schema --out /tmp/codex-appserver-schema
```

Current implementation is aligned to:
- `initialize`
- `model/list`
- `thread/start`
- `turn/start`
- `thread/read`

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).

Design and icon assets under `design/` are also available under MIT. See
[ASSETS_LICENSE.md](ASSETS_LICENSE.md).

## Community

- Contributing guide: [CONTRIBUTING.md](CONTRIBUTING.md)
- Code of Conduct: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- Security reporting: [SECURITY.md](SECURITY.md)

## Notes

- Old preference schema is intentionally reset to new defaults.
- If a selected mode model is unavailable, the app falls back to the recommended available model and notifies.
