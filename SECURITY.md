# Security Notes

This document describes the trust boundaries and security behavior of Sunarira.

For privacy and data-handling details, see [PRIVACY.md](PRIVACY.md).

## Trust Boundary: `stdio` Launch Command

Sunarira launches the configured App Server command through a shell:

- `/bin/zsh -lc "<configured command>"`

The command is executed with the same privileges as the current macOS user.
This means a malicious or untrusted command can execute arbitrary local code.

Only use trusted commands for the `stdio` launch setting.

## Data Flow

At transform time, Sunarira may access:

- Focused text from the active app via Accessibility APIs
- Clipboard content (fallback path if AX replacement is unavailable)

The selected input text is sent to the configured App Server process over local
stdio. Depending on your App Server/model configuration, text may be processed
locally or by remote services.

## Logging and Sensitive Data

- Runtime logs are local and in-memory for the app session.
- Input/output text logging is **off by default**.
- If enabled, logs can contain sensitive text previews and should be treated as
  sensitive data.

## Recommended Safe Configuration

- Keep `stdio` command restricted to trusted binaries and arguments.
- Do not paste or import untrusted command strings into settings.
- Keep sensitive logging disabled in normal use.
- Review your App Server/model provider data handling policy separately.

## Accessibility Permission

Sunarira requires Accessibility permission to perform reliable in-place text
replacement. Grant permission only to trusted builds.

## Reporting Security Issues

If you discover a security issue, avoid posting exploit details publicly first.
Use a private disclosure channel:

- Preferred: GitHub Security Advisories (`Security` tab -> `Report a vulnerability`)
- Fallback: open a public issue only for non-sensitive hardening questions

Please include:

- Affected version/commit
- Reproduction steps
- Impact assessment
- Suggested mitigation (if known)
