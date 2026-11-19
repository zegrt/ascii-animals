#!/bin/bash
# Energy measurement: mean CPU% of the wallpaper app and WindowServer, and the app's memory.
#   Tools/energy.sh <ocean|web> <15|30|60> [seconds=60]   measure ASCII Animals
#   Tools/energy.sh baseline [seconds=60]                 WindowServer with no wallpaper app running
# "WindowServer added" = (with the app) - (baseline).
# Run it with the desktop UNCOVERED (a covered desktop pauses the wallpaper and reads ~0%).
# Settings (defaults key settings.v2) are saved byte-for-byte, backed up to build/ before anything
# changes, and restored on exit, Ctrl-C or error. 15 fps is a plain setting (the same rate as
# PowerPolicy.economyFPS), so nothing needs forcing on AC.
# Test hooks (never needed for a real run): ENERGY_DOMAIN=<throwaway defaults domain>,
# ENERGY_DRY=1 (save/modify/restore only: no app launch, no Sharks handling, no sampling),
# ENERGY_DRY_SLEEP=<s> (how long a dry run idles with settings modified, for a Ctrl-C test).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/ASCII Animals.app"
DOMAIN="${ENERGY_DOMAIN:-local.ascii-animals.wallpaper}"
DRY="${ENERGY_DRY:-0}"
KEY="settings.v2"
PLKEY="settings\.v2"   # plutil key path: the dot must be escaped
SHARKS_ID="local.ascii-sharks.wallpaper"
SHARKS_APP="$HOME/Applications/ASCII Sharks.app"
BACKUP="$ROOT/build/energy-settings.$DOMAIN.backup.hex"
SETTLE=10

if [ "$DRY" = 1 ] && [ "$DOMAIN" = local.ascii-animals.wallpaper ]; then
  echo "ENERGY_DRY=1 is refused for the real domain; set ENERGY_DOMAIN to a throwaway one" >&2; exit 1
fi

for tool in jq xxd plutil base64 defaults top osascript; do
  command -v "$tool" >/dev/null 2>&1 || { echo "energy.sh needs '$tool' on the PATH" >&2; exit 1; }
done

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
# KEYSTATE: unknown until the save positively establishes present (a data value) or absent.
KEYSTATE=unknown; SAVED_HEX=""; TOUCHED=0; DONE=0; SHARKS_WAS_RUNNING=0

app_pids() { pgrep -x ASCIIAnimals || true; }
sharks_running() { pgrep -f "ASCII Sharks.app/Contents/MacOS" >/dev/null 2>&1; }
# Returns 0 only once no ASCIIAnimals process is left.
quit_app() {
  [ -z "$(app_pids)" ] && return 0
  osascript -e 'quit app id "local.ascii-animals.wallpaper"' >/dev/null 2>&1 || true
  local i; for i in 1 2 3 4 5 6 7 8 9 10; do [ -z "$(app_pids)" ] && return 0; sleep 1; done
  pkill -x ASCIIAnimals 2>/dev/null || true
  for i in 1 2 3 4 5; do [ -z "$(app_pids)" ] && return 0; sleep 1; done
  return 1
}
current_hex() { # hex of the stored value, "ABSENT" if no such key, "ERROR" otherwise
  local f="$TMP/now.plist" err
  defaults export "$DOMAIN" "$f" >/dev/null 2>&1 || { echo ERROR; return; }
  if err="$(plutil -extract "$PLKEY" raw -o - "$f" 2>&1 >"$TMP/now.b64")"; then
    base64 -D <"$TMP/now.b64" 2>/dev/null | xxd -p | tr -d '\n' || echo ERROR
  else
    case "$err" in *"No value at that key path"*) echo ABSENT ;; *) echo ERROR ;; esac
  fi
}
cleanup() {
  [ "$DONE" = 1 ] && return 0; DONE=1
  set +e; trap - EXIT INT TERM
  local ok=1
  if [ "$DRY" != 1 ] && ! quit_app; then
    echo "WARNING: ASCIIAnimals would not quit; NOT restoring settings while it is alive." >&2
    ok=0
  fi
  if [ "$TOUCHED" = 1 ] && [ "$ok" = 1 ]; then
    case "$KEYSTATE" in
      present) defaults write "$DOMAIN" "$KEY" -data "$SAVED_HEX" ;;
      absent) defaults delete "$DOMAIN" "$KEY" 2>/dev/null ;;
      *) ok=0 ;;   # unreachable: TOUCHED is only set after the state is known
    esac
    local want="$SAVED_HEX"; [ "$KEYSTATE" = absent ] && want=ABSENT
    if [ "$ok" = 1 ] && [ "$(current_hex)" = "$want" ]; then
      echo "settings restored (identical)"; rm -f "$BACKUP"
    else ok=0; fi
  fi
  if [ "$TOUCHED" = 1 ] && [ "$ok" = 0 ]; then
    echo "WARNING: settings were NOT verified restored. Backup kept at: $BACKUP" >&2
    echo "  restore with: defaults write $DOMAIN $KEY -data \"\$(cat '$BACKUP')\"   (or, if it says ABSENT: defaults delete $DOMAIN $KEY)" >&2
  fi
  if [ "$SHARKS_WAS_RUNNING" = 1 ] && [ "$DRY" != 1 ]; then open -a "$SHARKS_APP" && echo "ASCII Sharks relaunched"; fi
  rm -rf "$TMP"
}
trap cleanup EXIT
trap 'echo "interrupted" >&2; exit 130' INT TERM

# Never run two wallpaper apps at once (abort rather than measure with both alive).
if [ "$DRY" != 1 ]; then
  if [ -n "$(app_pids)" ]; then
    echo "an ASCII Animals is already running; quitting it first"
    quit_app || { echo "could not quit the running ASCII Animals; aborting" >&2; exit 1; }
  fi
  if sharks_running; then
    SHARKS_WAS_RUNNING=1; echo "quitting ASCII Sharks (will relaunch afterwards)"
    osascript -e "quit app id \"$SHARKS_ID\"" >/dev/null 2>&1 || true
    for i in 1 2 3 4 5 6 7 8 9 10; do sharks_running || break; sleep 1; done
    sharks_running && { echo "ASCII Sharks would not quit; aborting (nothing changed)" >&2; SHARKS_WAS_RUNNING=0; exit 1; }
    sleep 2
  fi
fi

# One-second top samples; the first (since-boot) sample is dropped.
# Prints "app_cpu_mean ws_cpu_mean app_mb_mean app_mb_peak".
sample_top() {
  top -l "$((SECS+1))" -s 1 -stats pid,command,cpu,mem -n 400 -o cpu 2>/dev/null > "$TMP/top.txt"
  awk '
    function mb(s,  v) { v = s + 0; if (s ~ /K/) v /= 1024; else if (s ~ /G/) v *= 1024; return v }
    /^Processes:/ { sample++ }
    sample >= 2 && $2 ~ /^ASCIIAnimals/ { a[sample] += $3; m[sample] += mb($4) }
    sample >= 2 && $2 ~ /^WindowServer/ { w[sample] += $3 }
    END {
      n = 0; sa = 0; sw = 0; sm = 0; pk = 0
      for (i = 2; i <= sample; i++) { n++; sa += a[i]; sw += w[i]; sm += m[i]; if (m[i] > pk) pk = m[i] }
      if (n == 0) n = 1
      printf "%.2f %.2f %.1f %.1f\n", sa / n, sw / n, sm / n, pk
    }' "$TMP/top.txt"
}

if [ "$MODE" = baseline ]; then
  echo "baseline: no wallpaper app; settling ${SETTLE}s, sampling WindowServer ${SECS}s"
  sleep "$SETTLE"
  read -r _ WS _ _ < <(sample_top)
  echo "baseline WindowServer mean CPU: ${WS}%"
  exit 0
fi

[ "$DRY" = 1 ] || [ -d "$APP" ] || { echo "missing $APP (run Tools/build.sh)" >&2; exit 1; }

# Save. Absent is concluded ONLY when the export worked and plutil says "No value at that key path";
# any other failure, or a value that is not data, aborts before anything is touched.
defaults export "$DOMAIN" "$TMP/dom.plist" >/dev/null 2>&1 || { echo "could not export defaults domain $DOMAIN; aborting (nothing changed)" >&2; exit 1; }
if ERR="$(plutil -extract "$PLKEY" raw -o - "$TMP/dom.plist" 2>&1 >"$TMP/key.b64")"; then
  TYPE="$(plutil -type "$PLKEY" "$TMP/dom.plist" 2>&1)" || { echo "plutil -type failed: $TYPE; aborting (nothing changed)" >&2; exit 1; }
  [ "$TYPE" = data ] || { echo "$KEY is of type '$TYPE', not data; aborting (nothing changed)" >&2; exit 1; }
  base64 -D <"$TMP/key.b64" >"$TMP/old.json" || { echo "could not decode $KEY; aborting (nothing changed)" >&2; exit 1; }
  jq -e 'type == "object"' "$TMP/old.json" >/dev/null 2>&1 || { echo "$KEY is not a JSON object; aborting (nothing changed)" >&2; exit 1; }
  SAVED_HEX="$(xxd -p <"$TMP/old.json" | tr -d '\n')"
  KEYSTATE=present
else
  case "$ERR" in
    *"No value at that key path"*) KEYSTATE=absent; echo '{}' >"$TMP/old.json" ;;
    *) echo "could not read $KEY ($ERR); aborting (nothing changed)" >&2; exit 1 ;;
  esac
fi
# A leftover backup means an earlier run did not verify its restore: it holds the TRUE original.
if [ -e "$BACKUP" ]; then
  echo "stale backup exists: $BACKUP (an earlier run did not finish restoring); aborting (nothing changed)" >&2
  echo "  restore with: defaults write $DOMAIN $KEY -data \"\$(cat '$BACKUP')\"   (or, if it says ABSENT: defaults delete $DOMAIN $KEY)" >&2
  echo "  then delete the backup file and rerun" >&2
  exit 1
fi
# Durable backup before the first write.
mkdir -p "$(dirname "$BACKUP")"
if [ "$KEYSTATE" = present ]; then printf '%s' "$SAVED_HEX" >"$BACKUP"; else printf 'ABSENT' >"$BACKUP"; fi
echo "settings saved ($KEYSTATE); backup: $BACKUP"
NEW_HEX="$(jq -c --arg h "$HABITAT" --argjson f "$FPS" '.habitat=$h | .fps=$f | .paused=false' "$TMP/old.json" | tr -d '\n' | xxd -p | tr -d '\n')"
TOUCHED=1
defaults write "$DOMAIN" "$KEY" -data "$NEW_HEX"

if [ "$DRY" = 1 ]; then
  echo "dry run: settings modified, idling ${ENERGY_DRY_SLEEP:-0}s"
  sleep "${ENERGY_DRY_SLEEP:-0}"
  exit 0
fi

echo "launching ASCII Animals: habitat=$HABITAT fps=$FPS"
open --env ASCII_ANIMALS_NO_HANDOVER=1 "$APP"
for i in $(seq 1 20); do [ -n "$(app_pids)" ] && break; sleep 1; done
[ -n "$(app_pids)" ] || { echo "app did not start" >&2; exit 1; }
echo "settling ${SETTLE}s, then sampling ${SECS}s"
sleep "$SETTLE"
read -r APPCPU WS MEM MEMPK < <(sample_top)
echo "habitat=$HABITAT fps=$FPS seconds=$SECS"
echo "  ASCIIAnimals CPU (mean): ${APPCPU}%"
echo "  WindowServer CPU (mean): ${WS}%   (minus the baseline run = added)"
echo "  ASCIIAnimals memory:     ${MEM} MB mean, ${MEMPK} MB peak"
if awk -v a="$APPCPU" 'BEGIN{exit !(a<0.3)}'; then
  echo "  NOTE: app CPU ~ 0 -> looked paused (desktop covered?) -- results invalid"
fi
