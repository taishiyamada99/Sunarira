#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/build/Release/Sunarira.app}"
BUNDLE_ID="dev.sunarira.app"
LOG_PREDICATE='subsystem == "dev.sunarira.app"'
LOG_START="$(date '+%Y-%m-%d %H:%M:%S')"
RUN_ID="$(date '+%Y%m%d%H%M%S')-$RANDOM"
SMOKE_OUTPUT="SMOKE_OK_${RUN_ID}"
WAIT_SECONDS="${WAIT_SECONDS:-2.2}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "E2E ERROR: app not found at $APP_PATH"
  exit 1
fi

tmp_prefs="$(mktemp /tmp/sunarira-e2e-smoke-prefs.XXXXXX.plist)"
tmp_backup="$(mktemp /tmp/sunarira-e2e-smoke-backup.XXXXXX.plist)"
mock_server="$(mktemp /tmp/sunarira-e2e-mock-server.XXXXXX.sh)"

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

  rm -f "$tmp_prefs" "$tmp_backup" "$mock_server"
}

trap cleanup EXIT

cat >"$mock_server" <<EOF
#!/usr/bin/env bash
set -euo pipefail

SMOKE_OUTPUT="$SMOKE_OUTPUT"

while IFS= read -r line; do
  id=\$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("id",""))' "\$line" 2>/dev/null || true)
  method=\$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("method",""))' "\$line" 2>/dev/null || true)
  if [[ -z "\$id" ]]; then
    id="fallback-id"
  fi

  if [[ "\$method" == "initialize" ]]; then
    printf '{"jsonrpc":"2.0","id":"%s","result":{"status":"ok"}}\n' "\$id"
  elif [[ "\$method" == "model/list" ]]; then
    printf '{"jsonrpc":"2.0","id":"%s","result":{"data":[{"model":"gpt-5.2"}]}}\n' "\$id"
    break
  elif [[ "\$method" == "thread/start" ]]; then
    printf '{"jsonrpc":"2.0","id":"%s","result":{"thread":{"id":"thread-1"}}}\n' "\$id"
  elif [[ "\$method" == "turn/start" ]]; then
    printf '{"jsonrpc":"2.0","id":"%s","result":{"turn":{"id":"turn-1","status":"inProgress"}}}\n' "\$id"
    printf '{"method":"turn/started","params":{"threadId":"thread-1","turn":{"id":"turn-1"}}}\n'
    printf '{"method":"item/agentMessage/delta","params":{"threadId":"thread-1","turnId":"turn-1","delta":"%s"}}\n' "\$SMOKE_OUTPUT"
    printf '{"method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"completed"}}}\n'
  elif [[ "\$method" == "thread/read" ]]; then
    printf '{"jsonrpc":"2.0","id":"%s","result":{"thread":{"id":"thread-1","turns":[{"id":"turn-1","items":[{"type":"assistant_message","content":[{"type":"output_text","text":"%s"}]}]}]}}}\n' "\$id" "\$SMOKE_OUTPUT"
    break
  fi
done
EOF
chmod +x "$mock_server"

mode_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
prefs_json=$(cat <<JSON
{"schemaVersion":2,"interfaceLanguage":"english","transformModes":[{"id":"$mode_id","displayName":"Smoke","promptTemplate":"Return deterministic smoke output only.","model":"gpt-5.2","isEnabled":true}],"activeModeID":"$mode_id","stdioCommand":"$mock_server","includeSensitiveTextInLogs":false}
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

read_textedit_selection() {
  osascript <<APPLESCRIPT
tell application "TextEdit"
    activate
    if (count of documents) = 0 then
        make new document
    end if
    set text of front document to "SMOKE-TE-SEL-$RUN_ID 背景説明と次アクション。"
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

read_textedit_full() {
  osascript <<APPLESCRIPT
tell application "TextEdit"
    activate
    if (count of documents) = 0 then
        make new document
    end if
    set text of front document to "SMOKE-TE-FULL-$RUN_ID 長めの本文。複数行の前提と課題。"
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

read_notes_selection() {
  osascript <<APPLESCRIPT
set the clipboard to "SMOKE-NOTES-SEL-$RUN_ID 要点と確認事項。"

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

read_notes_full() {
  osascript <<APPLESCRIPT
set the clipboard to "SMOKE-NOTES-FULL-$RUN_ID 本文全体を置換するテスト。"

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

te_sel_after="$(read_textedit_selection)"
te_full_after="$(read_textedit_full)"
notes_sel_after="$(read_notes_selection)"
notes_full_after="$(read_notes_full)"

check_equal() {
  local label="$1"
  local observed="$2"
  if [[ "$observed" == "$SMOKE_OUTPUT" ]]; then
    printf '%s: PASS\n' "$label"
    return 0
  fi
  printf '%s: FAIL\n' "$label"
  return 1
}

echo "=== E2E Smoke (local mock stdio) ==="

pass_count=0
fail_count=0

if check_equal "TextEdit selection in-place" "$te_sel_after"; then pass_count=$((pass_count + 1)); else fail_count=$((fail_count + 1)); fi
if check_equal "TextEdit full in-place" "$te_full_after"; then pass_count=$((pass_count + 1)); else fail_count=$((fail_count + 1)); fi
if check_equal "Notes selection in-place" "$notes_sel_after"; then pass_count=$((pass_count + 1)); else fail_count=$((fail_count + 1)); fi
if check_equal "Notes full in-place" "$notes_full_after"; then pass_count=$((pass_count + 1)); else fail_count=$((fail_count + 1)); fi

echo
echo "Observed outputs:"
echo "TE_SEL_AFTER=[$te_sel_after]"
echo "TE_FULL_AFTER=[$te_full_after]"
echo "NOTES_SEL_AFTER=[$notes_sel_after]"
echo "NOTES_FULL_AFTER=[$notes_full_after]"
echo
echo "Recent app logs:"
/usr/bin/log show --info --style compact --start "$LOG_START" --predicate "$LOG_PREDICATE" || true
echo
echo "Summary: pass=$pass_count fail=$fail_count"

if [[ "$fail_count" -eq 0 ]]; then
  exit 0
fi

exit 2
