#!/bin/bash
# Energy measurement: mean CPU% of the wallpaper app and WindowServer, and the app's memory.
#   Tools/energy.sh <ocean|web> <15|30|60> [seconds=60]   measure ASCII Animals
#   Tools/energy.sh baseline [seconds=60]                 WindowServer with no wallpaper app running
# "WindowServer added" = (with the app) - (baseline).
# Run it with the desktop UNCOVERED (a covered desktop pauses the wallpaper and reads ~0%).
# Settings (defaults key settings.v2) are saved byte-for-byte and restored on exit, Ctrl-C or error.
# 15 fps is a plain setting (Settings.fpsOptions = 15/30/60), the same frame rate the battery cap
# (PowerPolicy.economyFPS = 15) gives, so nothing needs forcing on AC.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/ASCII Animals.app"
DOMAIN="local.ascii-animals.wallpaper"
KEY="settings.v2"
PLKEY="settings\.v2"   # plutil key path: the dot must be escaped
SHARKS_ID="local.ascii-sharks.wallpaper"
SHARKS_APP="$HOME/Applications/ASCII Sharks.app"
SETTLE=10

usage() { echo "usage: $0 <ocean|web> <15|30|60> [seconds]  |  $0 baseline [seconds]" >&2; exit 2; }
[ $# -ge 1 ] || usage
MODE="$1"; HABITAT=""; FPS=""
if [ "$MODE" = baseline ]; then
  SECS="${2:-60}"
else
  [ $# -ge 2 ] || usage
  HABITAT="$MODE"; FPS="$2"; SECS="${3:-60}"
  case "$HABITAT" in ocean|web) ;; *) usage ;; esac
  case "$FPS" in 15|30|60) ;; *) usage ;; esac
fi
case "$SECS" in ''|*[!0-9]*|0) usage ;; esac

TMP="$(mktemp -d)"
SAVED_HEX=""; HAD_KEY=0; SHARKS_WAS_RUNNING=0; TOUCHED=0; DONE=0

app_pids() { pgrep -x ASCIIAnimals || true; }
sharks_running() { pgrep -f "ASCII Sharks.app/Contents/MacOS" >/dev/null 2>&1; }
quit_app() {
  osascript -e 'quit app id "local.ascii-animals.wallpaper"' >/dev/null 2>&1 || true
  local i; for i in 1 2 3 4 5 6 7 8 9 10; do [ -z "$(app_pids)" ] && return 0; sleep 1; done
  pkill -x ASCIIAnimals 2>/dev/null || true; sleep 1
}
cleanup() {
  [ "$DONE" = 1 ] && return 0; DONE=1
  set +e; trap - EXIT INT TERM
  [ -n "$(app_pids)" ] && quit_app
  if [ "$TOUCHED" = 1 ]; then
    if [ "$HAD_KEY" = 1 ]; then defaults write "$DOMAIN" "$KEY" -data "$SAVED_HEX"
    else defaults delete "$DOMAIN" "$KEY" 2>/dev/null; fi
    NOW="$(defaults export "$DOMAIN" - 2>/dev/null | plutil -extract "$PLKEY" raw -o - - 2>/dev/null | base64 -D | xxd -p | tr -d '\n')"
    if [ "$HAD_KEY" = 1 ] && [ "$NOW" = "$SAVED_HEX" ]; then echo "settings restored (byte-identical)"
    elif [ "$HAD_KEY" = 0 ] && [ -z "$NOW" ]; then echo "settings restored (key removed, as before)"
    else echo "WARNING: settings restore mismatch" >&2; fi
  fi
  if [ "$SHARKS_WAS_RUNNING" = 1 ]; then open -a "$SHARKS_APP" && echo "ASCII Sharks relaunched"; fi
  rm -rf "$TMP"
}
trap cleanup EXIT
trap 'echo "interrupted" >&2; exit 130' INT TERM

# Never run two wallpaper apps at once.
if [ -n "$(app_pids)" ]; then echo "an ASCII Animals is already running; quitting it first"; quit_app; fi
if sharks_running; then
  SHARKS_WAS_RUNNING=1; echo "quitting ASCII Sharks (will relaunch afterwards)"
  osascript -e "quit app id \"$SHARKS_ID\"" >/dev/null 2>&1 || true
  for i in 1 2 3 4 5 6 7 8 9 10; do sharks_running || break; sleep 1; done
  sleep 2
fi

# One-second top samples; the first (since-boot) sample is dropped. Prints "app_cpu ws_cpu app_mb".
sample_top() {
  top -l "$((SECS+1))" -s 1 -stats pid,command,cpu,mem -n 400 -o cpu 2>/dev/null > "$TMP/top.txt"
  awk '
    /^Processes:/ { sample++ }
    sample >= 2 && $2 ~ /^ASCIIAnimals/ { a[sample] += $3 }
    sample >= 2 && $2 ~ /^WindowServer/ { w[sample] += $3 }
    sample >= 2 && $2 ~ /^ASCIIAnimals/ { m = $4 }
    END {
      n = 0; sa = 0; sw = 0
      for (i = 2; i <= sample; i++) { n++; sa += a[i]; sw += w[i] }
      mem = m + 0; if (m ~ /K/) mem = mem / 1024; if (m ~ /G/) mem = mem * 1024
      if (n == 0) n = 1
      printf "%.2f %.2f %.1f\n", sa / n, sw / n, mem
    }' "$TMP/top.txt"
}

if [ "$MODE" = baseline ]; then
  echo "baseline: no wallpaper app; settling ${SETTLE}s, sampling WindowServer ${SECS}s"
  sleep "$SETTLE"
  read -r _ WS _ < <(sample_top)
  echo "baseline WindowServer mean CPU: ${WS}%"
  exit 0
fi

[ -d "$APP" ] || { echo "missing $APP (run Tools/build.sh)" >&2; exit 1; }

# Save settings byte-for-byte, then write a modified copy (only habitat and fps change).
if defaults export "$DOMAIN" "$TMP/dom.plist" >/dev/null 2>&1 && plutil -extract "$PLKEY" raw -o - "$TMP/dom.plist" >"$TMP/key.b64" 2>/dev/null; then
  HAD_KEY=1
  SAVED_HEX="$(base64 -D <"$TMP/key.b64" | xxd -p | tr -d '\n')"
  base64 -D <"$TMP/key.b64" >"$TMP/old.json"
else
  echo '{}' >"$TMP/old.json"
fi
TOUCHED=1
NEW_HEX="$(jq -c --arg h "$HABITAT" --argjson f "$FPS" '.habitat=$h | .fps=$f | .paused=false' "$TMP/old.json" | tr -d '\n' | xxd -p | tr -d '\n')"
defaults write "$DOMAIN" "$KEY" -data "$NEW_HEX"

echo "launching ASCII Animals: habitat=$HABITAT fps=$FPS"
open --env ASCII_ANIMALS_NO_HANDOVER=1 "$APP"
for i in $(seq 1 20); do [ -n "$(app_pids)" ] && break; sleep 1; done
[ -n "$(app_pids)" ] || { echo "app did not start" >&2; exit 1; }
echo "settling ${SETTLE}s, then sampling ${SECS}s"
sleep "$SETTLE"
read -r APPCPU WS MEM < <(sample_top)
echo "habitat=$HABITAT fps=$FPS seconds=$SECS"
echo "  ASCIIAnimals CPU (mean): ${APPCPU}%"
echo "  WindowServer CPU (mean): ${WS}%   (minus the baseline run = added)"
echo "  ASCIIAnimals memory:     ${MEM} MB"
if awk -v a="$APPCPU" 'BEGIN{exit !(a<0.3)}'; then
  echo "  NOTE: app CPU ~ 0 -> looked paused (desktop covered?) -- results invalid"
fi
