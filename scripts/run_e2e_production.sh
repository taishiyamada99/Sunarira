#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/build/Release/Sunarira.app}"
BUNDLE_ID="dev.sunarira.app"
MODEL="${MODEL:-gpt-5.2}"
STDIO_COMMAND="${STDIO_COMMAND:-codex app-server --listen stdio://}"
WAIT_SECONDS="${WAIT_SECONDS:-15}"
LOG_PREDICATE='subsystem == "dev.sunarira.app"'
LOG_START="$(date '+%Y-%m-%d %H:%M:%S')"
RUN_ID="$(date '+%Y%m%d%H%M%S')-$RANDOM"

if [[ ! -d "$APP_PATH" ]]; then
  echo "E2E ERROR: app not found at $APP_PATH"
  exit 1
fi

tmp_prefs="$(mktemp /tmp/sunarira-e2e-prod-prefs.XXXXXX.plist)"
tmp_backup="$(mktemp /tmp/sunarira-e2e-prod-backup.XXXXXX.plist)"

had_existing_prefs=0
if defaults export "$BUNDLE_ID" "$tmp_backup" >/dev/null 2>&1; then
  had_existing_prefs=1
fi

cleanup() {
  if [[ "$had_existing_prefs" -eq 1 ]]; then
    defaults import "$BUNDLE_ID" "$tmp_backup" >/dev/null 2>&1 || true
  else
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
  fi

  rm -f "$tmp_prefs" "$tmp_backup"
}

trap cleanup EXIT

mode_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
prefs_json=$(cat <<JSON
{"schemaVersion":2,"interfaceLanguage":"english","transformModes":[{"id":"$mode_id","displayName":"Production","promptTemplate":"Rewrite the input to be clearer and concise while preserving key facts.","model":"$MODEL","isEnabled":true}],"activeModeID":"$mode_id","stdioCommand":"$STDIO_COMMAND","includeSensitiveTextInLogs":false}
JSON
)
prefs_data="$(printf '%s' "$prefs_json" | base64 | tr -d '\n')"

cat >"$tmp_prefs" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>sunarira.preferences</key>
  <data>
  $prefs_data
  </data>
</dict>
</plist>
PLIST

defaults import "$BUNDLE_ID" "$tmp_prefs"
killall Sunarira TextEdit Notes >/dev/null 2>&1 || true
open -na "$APP_PATH"
sleep 2

te_sel_input="本番選択入力${RUN_ID}。背景として、複数の依頼が同時進行し優先順位が曖昧です。課題は、判断基準が担当者ごとに異なる点です。対応として、評価軸と締切、責任者を明確化します。"
te_full_input="本番全文入力${RUN_ID}。現状、実行計画はあるものの依存タスクの可視化が不足しています。想定リスクは、着手遅れとレビュー滞留です。次のアクションとして、日次確認とエスカレーション条件を定義します。"
notes_sel_input="本番ノート選択${RUN_ID}。要点として、意思決定の前提条件が文書化されていません。影響は、再説明コストと合意遅延です。次の行動として、前提・判断根拠・担当・期限を一枚に整理します。"
notes_full_input="本番ノート全文${RUN_ID}。背景には、運用ルールの更新履歴が追えていない問題があります。リスクは、誤運用と監査対応の遅延です。合意事項として、改定フロー・承認者・公開タイミングを明確化します。"

run_textedit_selection() {
  osascript <<APPLESCRIPT
tell application "TextEdit"
    activate
    if (count of documents) = 0 then
        make new document
    end if
    set text of front document to "$te_sel_input"
end tell

delay 0.5

tell application "System Events"
    keystroke "a" using {command down}
    key code 15 using {control down, option down, command down}
end tell

delay $WAIT_SECONDS

tell application "TextEdit"
    return text of front document
end tell
APPLESCRIPT
}

run_textedit_full() {
  osascript <<APPLESCRIPT
tell application "TextEdit"
    activate
    if (count of documents) = 0 then
        make new document
    end if
    set text of front document to "$te_full_input"
end tell

delay 0.5

tell application "System Events"
    key code 124
    key code 15 using {control down, option down, command down}
end tell

delay $WAIT_SECONDS

tell application "TextEdit"
    return text of front document
end tell
APPLESCRIPT
}

run_notes_selection() {
  osascript <<APPLESCRIPT
set the clipboard to "$notes_sel_input"

tell application "Notes"
    activate
end tell

delay 1.0

tell application "System Events"
    keystroke "n" using {command down}
    delay 0.5
    keystroke "v" using {command down}
    delay 0.5
    keystroke "a" using {command down}
    key code 15 using {control down, option down, command down}
end tell

delay $WAIT_SECONDS

tell application "System Events"
    keystroke "a" using {command down}
    delay 0.2
    keystroke "c" using {command down}
end tell

delay 0.4
return the clipboard
APPLESCRIPT
}

run_notes_full() {
  osascript <<APPLESCRIPT
set the clipboard to "$notes_full_input"

tell application "Notes"
    activate
end tell

delay 1.0

tell application "System Events"
    keystroke "n" using {command down}
    delay 0.5
    keystroke "v" using {command down}
    delay 0.5
    key code 124
    key code 15 using {control down, option down, command down}
end tell

delay $WAIT_SECONDS

tell application "System Events"
    keystroke "a" using {command down}
    delay 0.2
    keystroke "c" using {command down}
end tell

delay 0.4
return the clipboard
APPLESCRIPT
}

normalize_text() {
  printf '%s' "$1" | tr '\r' '\n' | sed 's/[[:space:]]\+$//'
}

check_transformed() {
  local label="$1"
  local input="$2"
  local output="$3"

  local input_norm output_norm
  input_norm="$(normalize_text "$input")"
  output_norm="$(normalize_text "$output")"

  if [[ -z "$output_norm" ]]; then
    printf '%s: FAIL (empty output)\n' "$label"
    return 1
  fi

  if [[ "$output_norm" == "$input_norm" ]]; then
    printf '%s: FAIL (unchanged)\n' "$label"
    return 1
  fi

  printf '%s: PASS\n' "$label"
  return 0
}

te_sel_after="$(run_textedit_selection)"
te_full_after="$(run_textedit_full)"
notes_sel_after="$(run_notes_selection)"
notes_full_after="$(run_notes_full)"

echo "=== Production E2E (Codex stdio + $MODEL) ==="

pass_count=0
fail_count=0

if check_transformed "TextEdit selection in-place" "$te_sel_input" "$te_sel_after"; then pass_count=$((pass_count + 1)); else fail_count=$((fail_count + 1)); fi
if check_transformed "TextEdit full in-place" "$te_full_input" "$te_full_after"; then pass_count=$((pass_count + 1)); else fail_count=$((fail_count + 1)); fi
if check_transformed "Notes selection in-place" "$notes_sel_input" "$notes_sel_after"; then pass_count=$((pass_count + 1)); else fail_count=$((fail_count + 1)); fi
if check_transformed "Notes full in-place" "$notes_full_input" "$notes_full_after"; then pass_count=$((pass_count + 1)); else fail_count=$((fail_count + 1)); fi

logs="$(
  /usr/bin/log show --info --style compact --start "$LOG_START" --predicate "$LOG_PREDICATE" || true
)"
ax_permission_fail_count="$(printf '%s\n' "$logs" | grep -c 'AX capture failed: accessibility not granted.' || true)"
ax_capture_count="$(printf '%s\n' "$logs" | grep -c 'Captured text via AX' || true)"
endpoint_error_count="$(printf '%s\n' "$logs" | grep -c 'Transform failed' || true)"

echo
echo "AX log checks:"
if [[ "$ax_permission_fail_count" -eq 0 && "$ax_capture_count" -ge 4 && "$endpoint_error_count" -eq 0 ]]; then
  echo "AX capture log status: PASS (captures=$ax_capture_count, permission_failures=$ax_permission_fail_count, endpoint_errors=$endpoint_error_count)"
else
  echo "AX capture log status: FAIL (captures=$ax_capture_count, permission_failures=$ax_permission_fail_count, endpoint_errors=$endpoint_error_count)"
  fail_count=$((fail_count + 1))
fi

echo
echo "Observed outputs:"
echo "TE_SEL_AFTER=[$te_sel_after]"
echo "TE_FULL_AFTER=[$te_full_after]"
echo "NOTES_SEL_AFTER=[$notes_sel_after]"
echo "NOTES_FULL_AFTER=[$notes_full_after]"
echo
echo "Recent app logs:"
printf '%s\n' "$logs"
echo
echo "Summary: pass=$pass_count fail=$fail_count"

if [[ "$fail_count" -eq 0 ]]; then
  exit 0
fi

exit 2
