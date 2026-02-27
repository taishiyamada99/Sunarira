# Privacy Notes

This document describes how Sunarira handles text and related data.

## Scope

Sunarira is a local macOS menu bar app that transforms text from the currently
focused app. It does not provide a cloud account system in this repository.

## What Data Sunarira May Access

During normal operation, Sunarira may access:

- Selected or full text from the focused input field (Accessibility path)
- Clipboard text (fallback path, and replacement workflow)
- User settings (for example, transform mode prompts, model names, hotkeys)
- Runtime diagnostics/log data

## How Text Is Processed

When transform is triggered:

1. Sunarira reads text from the focused app (or clipboard fallback).
2. Sunarira sends transform input to the configured App Server process via
   local stdio JSON-RPC.
3. Sunarira receives transformed output and writes it back in place.

Sunarira itself does not directly choose or enforce whether downstream model
processing is local-only or remote. That depends on your configured App Server
and model/provider.

## Clipboard Handling

Clipboard data is used for fallback and paste-based replacement flows.

- The app may temporarily overwrite clipboard content to perform replacement.
- The app attempts to restore the prior clipboard snapshot after replacement.
- Because clipboard is a shared OS resource, other apps may observe clipboard
  changes while replacement is in progress.

## Logging and Sensitive Data

Sunarira has two logging surfaces:

- In-app runtime log buffer (shown in Settings > Logs)
- macOS unified logging (`subsystem: dev.sunarira.app`)

Default behavior:

- Input/output text preview logging is **off by default**.
- Payload metadata (for example length and hash) may still be logged.

If `Include input/output text in logs` is enabled, sensitive text may appear in
logs. Keep this disabled in normal use.

## Permissions

- Accessibility permission is required for reliable in-place text capture and
  replacement.
- Notification permission may be requested for user-facing status/error notices.

## Data Retention

- Preferences are stored locally in macOS user defaults.
- In-app runtime log buffer is session-local and can be cleared from settings.
- macOS unified log retention is managed by the OS, not by Sunarira.

## Third-Party and Provider Policies

If your configured App Server/model sends text to external services, that data
is governed by the respective provider policies and your deployment setup.
Review those policies before processing sensitive content.
