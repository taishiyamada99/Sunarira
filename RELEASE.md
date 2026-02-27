# Release Process

This document defines the release workflow for Sunarira.

## Versioning Policy

Sunarira uses Semantic Versioning (`MAJOR.MINOR.PATCH`).

- MAJOR: incompatible behavior or protocol changes
- MINOR: backward-compatible feature additions
- PATCH: backward-compatible fixes and documentation-only updates

Version sources:

- `project.yml`:
  - `MARKETING_VERSION` -> app version (`CFBundleShortVersionString`)
  - `CURRENT_PROJECT_VERSION` -> build number (`CFBundleVersion`)
- `Sources/App/Info.plist` references these build settings.
- `Sunarira.xcodeproj/project.pbxproj` should be kept in sync if project files
  are not regenerated automatically.

## Pre-Release Checklist

1. Update version/build number in:
   - `project.yml`
   - `Sunarira.xcodeproj/project.pbxproj` (or regenerate project files from `project.yml`)
2. Update `CHANGELOG.md` with a new release section.
3. Run checks:
   - `xcodebuild test -project Sunarira.xcodeproj -scheme Sunarira -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS'`
4. Build release app:
   - `xcodebuild build -project Sunarira.xcodeproj -scheme Sunarira -configuration Release SYMROOT=build`
5. Package artifact (do not commit artifacts into git):
   - `cd build/Release && ditto -c -k --sequesterRsrc --keepParent Sunarira.app Sunarira-v<version>.zip`

## Git Tag and GitHub Release

1. Commit version/changelog updates.
2. Create an annotated tag:
   - `git tag -a v<version> -m "Sunarira v<version>"`
3. Push branch and tag.
4. Create a GitHub Release from the tag:
   - Title: `Sunarira v<version>`
   - Notes: summary from `CHANGELOG.md`
   - Attach `Sunarira-v<version>.zip`

## Signing Policy

Current default:

- Local developer signing (`Sign to Run Locally`) for development/testing.

Distribution options:

- For broader end-user distribution, use Apple Developer signing and notarization.
- Notarization is optional for local/internal use but recommended for public
  download UX and Gatekeeper compatibility.

## Artifact Policy

- Never commit `build/`, `DerivedData/`, `.xcresult`, or packaged `.zip` files.
- Ship binary artifacts through GitHub Releases only.
