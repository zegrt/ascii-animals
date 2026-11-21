#!/bin/bash
# Energy measurement with the ENERGY-TEST COPY of ASCII Animals (Tools/build.sh --test builds it):
# "build/ASCII Animals Test.app", bundle ID local.ascii-animals.energy-test, its own defaults domain, log and crash
# marker, and no updater, Sharks hand-over, uninstaller, system-wallpaper match or login item (AppIdentity in
# OceanKit). This script never writes the app people install's settings, wallpaper or folders.
#
#   Tools/energy.sh baseline [seconds=60]                        WindowServer with no wallpaper app running
#   Tools/energy.sh <ocean|web|meadow> <15|30|60> [seconds=60] [count]
#                                                                one habitat; count = the Meadow's butterflies
#                                                                (1-12; default: the app's default)
#   Tools/energy.sh preview                                      the what's-new card once, on the live desktop
#   Tools/energy.sh calibrate [count]                            the Meadow on the built-in display alone; prints
#                                                                the count chosen in the test copy's Settings
#   Tools/energy.sh status                                       what is running, the lock, leftovers (no change)
#   Tools/energy.sh recover                                      after a killed run: quit the test copy, delete
#                                                                its domain, relaunch what this script quit
# "WindowServer added" = (with the app) - (baseline). Run with the desktop UNCOVERED (a covered desktop pauses).
#
# Every run: one at a time (a lock); the test domain is deleted, then written for this run (habitat, fps, count;
# the wallpaper match and update checks off), and deleted again at the end, verified. The owner's running
# ASCII Animals (and ASCII Sharks, if it was running) is quit with SIGTERM before and relaunched after from the
# bundle that was running (path recorded, launch verified). No Apple Events, so no Automation prompt.
#
# Test hooks (never for a real run): ENERGY_DRY=1 does the lock and the test domain only (no process is quit,
# launched or sampled); with it, ENERGY_TEST_DOMAIN=local.ascii-animals.energy-test.<word> picks a throwaway
# domain in the test namespace, ENERGY_DRY_SLEEP=<s> idles with the domain written (a Ctrl-C test), and
# ENERGY_DRY_COUNT=<n> stands in for a count the director picks while calibrating.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ID="local.ascii-animals.energy-test"
TEST_EXE="ASCIIAnimalsEnergyTest"
TEST_NAME="ASCII Animals Test"
REAL_ID="local.ascii-animals.wallpaper"
SHARKS_ID="local.ascii-sharks.wallpaper"
APP="$ROOT/build/$TEST_NAME.app"
TEST_EXEC="$APP/Contents/MacOS/$TEST_EXE"
TEST_LOG="$HOME/Library/Logs/ASCII Animals Energy Test/ascii-animals.log"
KEY="settings.v2"
PLKEY="settings\.v2"   # plutil key path: the dot must be escaped
RUNDIR="${TMPDIR:-/tmp}"
LOCKFILE="$RUNDIR/ascii-animals-energy-test.lock"
OWNERFILE="$RUNDIR/ascii-animals-energy-test.owner"   # what this script quit, for the relaunch (and `recover`)
SETTLE=10

die() { echo "energy.sh: $*" >&2; exit 1; }

# ---- What this script may touch: the test identity only ----

# Lowercased, trimmed, any folder and a .plist suffix dropped: every spelling of a domain that reaches one file.
canon() {
  local s
  s="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  s="${s##*/}"; s="${s%.plist}"
  printf '%s' "$s"
}
refuse_real() { # $1: a domain or bundle ID about to be used
  local c; c="$(canon "$1")"
  case "$c" in
    "$REAL_ID"|"$SHARKS_ID"|*wallpaper*|"") die "refused: '$1' is (or spells) the app people install or ASCII Sharks; only $TEST_ID is driven here" ;;
  esac
}

DRY="${ENERGY_DRY-0}"
case "$DRY" in 0|1) ;; *) die "ENERGY_DRY must be 1 or unset (got '$DRY')" ;; esac
if [ -n "${ENERGY_TEST_DOMAIN-}" ] && [ "$DRY" != 1 ]; then die "ENERGY_TEST_DOMAIN is a dry-run hook: set ENERGY_DRY=1 with it"; fi
DOMAIN="${ENERGY_TEST_DOMAIN-$TEST_ID}"
refuse_real "$DOMAIN"
# Positively: a plain ID in the test namespace (no capitals, folders, suffixes or spaces).
[[ "$DOMAIN" =~ ^local\.ascii-animals\.energy-test(\.[a-z0-9-]+)?$ ]] && [ "$(canon "$DOMAIN")" = "$DOMAIN" ] \
  && [[ "$DOMAIN" != *.plist ]] || die "refused: '$DOMAIN' is not in the test namespace ($TEST_ID[.<word>])"
[ "$DRY" = 1 ] || [ "$DOMAIN" = "$TEST_ID" ] || die "a live run uses the test copy's own domain only"

for tool in jq xxd plutil base64 defaults top ps open lockf; do
  command -v "$tool" >/dev/null 2>&1 || die "needs '$tool' on the PATH"
done

usage() {
  echo "usage: $0 baseline [s] | $0 <ocean|web|meadow> <15|30|60> [s] [count] | $0 preview | $0 calibrate [count] | $0 status | $0 recover" >&2
  exit 2
}
[ $# -ge 1 ] || usage
MODE="$1"; HABITAT=""; FPS=""; SECS=60; COUNT=""
case "$MODE" in
  baseline) SECS="${2:-60}" ;;
  ocean|web|meadow)
    [ $# -ge 2 ] || usage
    HABITAT="$MODE"; FPS="$2"; SECS="${3:-60}"; COUNT="${4:-}"
    case "$FPS" in 15|30|60) ;; *) usage ;; esac
    MODE=measure ;;
  preview) ;;
  calibrate) HABITAT=meadow; FPS=30; COUNT="${2:-}" ;;
  status|recover|selftest) ;;
  *) usage ;;
esac
case "$SECS" in ''|*[!0-9]*|0) usage ;; esac
if [ -n "$COUNT" ]; then
  case "$COUNT" in *[!0-9]*) usage ;; esac
  [ "$COUNT" -ge 1 ] && [ "$COUNT" -le 12 ] || die "count must be 1-12"
  [ "$HABITAT" = meadow ] || die "a count is for the Meadow only"
fi
[ "$DRY" = 1 ] && [ "$MODE" = baseline ] && die "a dry run has nothing to measure; baseline is live only"
[ "$DRY" = 1 ] && [ "$MODE" = recover ] && die "recover is live only (a dry run quits and launches nothing)"
[ "$MODE" = selftest ] && [ "$DRY" != 1 ] && die "selftest is a dry-run hook: ENERGY_DRY=1"

# ---- Processes, by exact executable path; bundles by their Info.plist ----

bundle_id() { plutil -extract CFBundleIdentifier raw -o - "$1/Contents/Info.plist" 2>/dev/null || true; }
# "pid<TAB>bundle path" for every running app (this user's) whose bundle ID is $1.
running_apps() {
  local want="$1" pid comm bundle
  ps -U "$(id -u)" -o pid=,comm= | while read -r pid comm; do
    case "$comm" in *.app/Contents/MacOS/*) ;; *) continue ;; esac
    bundle="${comm%/Contents/MacOS/*}"
    [ "$(bundle_id "$bundle")" = "$want" ] && printf '%s\t%s\n' "$pid" "$bundle"
  done
  return 0
}
pids_at() { # pids whose executable is exactly $1
  ps -U "$(id -u)" -o pid=,comm= | awk -v want="$1" '{ pid = $1; sub(/^[ \t]*[0-9]+[ \t]+/, ""); if ($0 == want) print pid }'
}
alive() { kill -0 "$1" 2>/dev/null; }
# SIGTERM (the apps quit normally on it and put the user's wallpaper back), then wait.
term_and_wait() { # $1 pid, $2 seconds
  local i=0
  alive "$1" || return 0
  kill -TERM "$1" 2>/dev/null || true
  while alive "$1" && [ "$i" -lt "$2" ]; do sleep 1; i=$((i + 1)); done
  ! alive "$1"
}
exec_of() { plutil -extract CFBundleExecutable raw -o - "$1/Contents/Info.plist" 2>/dev/null || true; }
# Opens a recorded bundle and waits for its executable to run. $1 name, $2 bundle, $3.. extra `open` options.
relaunch() {
  local name="$1" bundle="$2"; shift 2
  local exe i; exe="$(exec_of "$bundle")"
  [ -n "$exe" ] && [ -d "$bundle" ] || { echo "WARNING: $name's bundle is gone: $bundle" >&2; return 1; }
  [ -n "$(pids_at "$bundle/Contents/MacOS/$exe")" ] && { echo "$name is already running ($bundle)"; return 0; }
  open "$@" "$bundle" || { echo "WARNING: could not open $name: $bundle" >&2; return 1; }
  for i in $(seq 1 20); do
    [ -n "$(pids_at "$bundle/Contents/MacOS/$exe")" ] && { echo "$name relaunched and running ($bundle)"; return 0; }
    sleep 1
  done
  echo "WARNING: $name did not start: $bundle" >&2
  return 1
}

# ---- The test domain ----

domain_absent() { # 0 when the domain holds nothing; 1 otherwise
  local out; out="$(defaults read "$DOMAIN" 2>&1)" && return 1
  case "$out" in *"does not exist"*) return 0 ;; *) return 1 ;; esac
}
delete_domain() { # deletes and verifies; 0 when verified absent
  domain_absent && return 0
  defaults delete "$DOMAIN" >/dev/null 2>&1 || true
  domain_absent
}
settings_hex() { # hex of the stored settings, "ABSENT", or "ERROR"; checks the type is data
  local f="$TMP/now.plist" err type
  if domain_absent; then echo ABSENT; return; fi
  defaults export "$DOMAIN" "$f" >/dev/null 2>&1 || { echo ERROR; return; }
  if err="$(plutil -extract "$PLKEY" raw -o - "$f" 2>&1 >"$TMP/now.b64")"; then
    type="$(plutil -type "$PLKEY" "$f" 2>/dev/null || true)"
    [ "$type" = data ] || { echo ERROR; return; }
    base64 -D <"$TMP/now.b64" 2>/dev/null | xxd -p | tr -d '\n' || echo ERROR
  else
    case "$err" in *"No value at that key path"*) echo ABSENT ;; *) echo ERROR ;; esac
  fi
}
write_settings() {
  local json hex
  json="$(jq -cn --arg h "$HABITAT" --argjson f "$FPS" --arg c "$COUNT" \
    '{habitat: $h, fps: $f, paused: false, matchSystemWallpaper: false, checkForUpdates: false, autoInstallUpdates: false}
     + (if $c == "" then {} else {meadowCount: ($c | tonumber)} end)')"
  hex="$(printf '%s' "$json" | xxd -p | tr -d '\n')"
  defaults write "$DOMAIN" "$KEY" -data "$hex"
  [ "$(settings_hex)" = "$hex" ] || die "the test domain did not read back what was written"
  echo "test domain $DOMAIN written: $json"
}

# ---- status: changes nothing ----

if [ "$MODE" = status ]; then
  echo "energy-test copy: $APP ($( [ -d "$APP" ] && bundle_id "$APP" || echo missing))"
  echo "running test copy: $(pids_at "$TEST_EXEC" | tr '\n' ' ')"
  echo "running ASCII Animals: $(running_apps "$REAL_ID" | tr '\t\n' ' ;')"
  echo "running ASCII Sharks: $(running_apps "$SHARKS_ID" | tr '\t\n' ' ;')"
  if lockf -k -s -t 0 "$LOCKFILE" true 2>/dev/null; then echo "lock: free"; else echo "lock: held (a run is under way)"; fi
  if [ -s "$OWNERFILE" ]; then echo "to relaunch (a killed run left this; run: $0 recover):"; sed 's/^/  /' "$OWNERFILE"; else echo "to relaunch: nothing"; fi
  if domain_absent; then echo "test domain $DOMAIN: absent"; else echo "test domain $DOMAIN: present (recover deletes it)"; fi
  exit 0
fi

# ---- One run at a time: the rest runs under an exclusive lock, held until it exits (released if it dies) ----

if [ "${ENERGY_LOCK_HELD-}" != "$LOCKFILE" ]; then
  trap ':' INT TERM   # the run below handles Ctrl-C; wait for it
  set +e
  ENERGY_LOCK_HELD="$LOCKFILE" lockf -k -s -t 0 "$LOCKFILE" /bin/bash "$0" "$@"
  rc=$?
  [ "$rc" = 75 ] && echo "energy.sh: another run holds the lock ($LOCKFILE); one run at a time" >&2
  exit "$rc"
fi

TMP="$(mktemp -d)"
TOUCHED=0; LAUNCHED=0; TEST_PID=""; CLEANING=0; OWNER_RECORDED=0

# ---- Preflight (live): the test bundle is what it says ----

if [ "$DRY" != 1 ]; then
  for p in $(ps -U "$(id -u)" -o pid=,comm= | awk '{ pid = $1; sub(/^[ \t]*[0-9]+[ \t]+/, ""); if ($0 ~ /\/Contents\/MacOS\/ASCIIAnimalsEnergyTest$/) print pid }'); do
    [ "$(ps -o comm= -p "$p")" = "$TEST_EXEC" ] || die "a test copy from another folder is running (pid $p); quit it first"
  done
fi
if [ "$DRY" != 1 ] && { [ "$MODE" = measure ] || [ "$MODE" = preview ] || [ "$MODE" = calibrate ]; }; then
  [ -d "$APP" ] || die "missing $APP (run Tools/build.sh --test)"
  ID="$(bundle_id "$APP")"
  refuse_real "$ID"
  [ "$ID" = "$TEST_ID" ] || die "refused: $APP has bundle ID '$ID', not $TEST_ID"
  [ "$(exec_of "$APP")" = "$TEST_EXE" ] && [ -x "$TEST_EXEC" ] || die "refused: $APP's executable is not $TEST_EXE"
  codesign --verify --strict "$APP" 2>/dev/null || die "$APP does not verify (rebuild with Tools/build.sh --test)"
fi

# ---- Cleanup: on exit, error or Ctrl-C; protected from a second Ctrl-C; its failure is the run's failure ----

cleanup() {
  local rc=$? ok=1 p
  [ "$CLEANING" = 1 ] && return; CLEANING=1
  trap '' INT TERM
  set +e
  if [ "$DRY" != 1 ]; then
    # A launch still pending: give its process time to appear, so it is not left behind.
    if [ "$LAUNCHED" = 1 ] && [ -z "$TEST_PID" ]; then
      for _ in 1 2 3 4 5 6 7 8 9 10; do TEST_PID="$(pids_at "$TEST_EXEC" | head -1)"; [ -n "$TEST_PID" ] && break; sleep 1; done
    fi
    for p in $TEST_PID $(pids_at "$TEST_EXEC"); do
      if ! term_and_wait "$p" 15; then kill -KILL "$p" 2>/dev/null; sleep 1; fi
    done
    if [ -n "$(pids_at "$TEST_EXEC")" ]; then
      echo "WARNING: the test copy is still running (pid $(pids_at "$TEST_EXEC" | tr '\n' ' ')); NOT relaunching your apps" >&2
      echo "  quit it, then run: $0 recover" >&2
      ok=0
    elif [ -n "$TEST_PID" ] || [ "$LAUNCHED" = 1 ]; then
      echo "test copy quit"
    fi
  fi
  if [ "$TOUCHED" = 1 ]; then
    if [ "$ok" = 1 ] && delete_domain; then
      echo "test domain $DOMAIN deleted (verified absent)"
    else
      echo "WARNING: test domain $DOMAIN not verified deleted; run: $0 recover" >&2; ok=0
    fi
  fi
  if [ "$DRY" != 1 ] && [ "$ok" = 1 ] && [ "$OWNER_RECORDED" = 1 ] && [ -s "$OWNERFILE" ]; then
    local kind bundle relaunched=1
    while IFS=$'\t' read -r kind bundle; do
      case "$kind" in
        animals) relaunch "ASCII Animals" "$bundle" --env ASCII_ANIMALS_NO_HANDOVER=1 || relaunched=0 ;;
        sharks) relaunch "ASCII Sharks" "$bundle" || relaunched=0 ;;
      esac
    done <"$OWNERFILE"
    if [ "$relaunched" = 1 ]; then rm -f "$OWNERFILE"; else
      echo "WARNING: not everything came back; the list is in $OWNERFILE (run: $0 recover)" >&2; ok=0
    fi
  fi
  rm -rf "$TMP"
  [ "$ok" = 1 ] || exit 1
  exit "$rc"
}
trap cleanup EXIT
trap 'echo "interrupted; cleaning up (Ctrl-C again is ignored until done)" >&2; exit 130' INT TERM

# ---- recover: a killed run's leftovers ----

if [ "$MODE" = recover ]; then
  TOUCHED=1; OWNER_RECORDED=1
  echo "recover: quitting any test copy, deleting the test domain, relaunching what a run quit"
  exit 0   # cleanup does it all
fi

# ---- Quit the owner's apps (recorded first, so an early stop still relaunches them) ----

quit_owner_apps() {
  [ -s "$OWNERFILE" ] && die "a killed run left $OWNERFILE (apps it quit); run: $0 recover"
  local pid bundle
  OWNER_RECORDED=1
  : >"$OWNERFILE"
  running_apps "$REAL_ID" >"$TMP/animals"
  running_apps "$SHARKS_ID" >"$TMP/sharks"
  while IFS=$'\t' read -r pid bundle; do printf 'animals\t%s\n' "$bundle" >>"$OWNERFILE"; done <"$TMP/animals"
  while IFS=$'\t' read -r pid bundle; do printf 'sharks\t%s\n' "$bundle" >>"$OWNERFILE"; done <"$TMP/sharks"
  sort -u -o "$OWNERFILE" "$OWNERFILE"
  [ -s "$OWNERFILE" ] && { echo "your apps, relaunched at the end:"; sed 's/^/  /' "$OWNERFILE"; }
  while IFS=$'\t' read -r pid bundle; do
    echo "quitting ASCII Animals (pid $pid, $bundle)"
    term_and_wait "$pid" 15 || die "ASCII Animals (pid $pid) would not quit; stopping"
  done <"$TMP/animals"
  while IFS=$'\t' read -r pid bundle; do
    echo "quitting ASCII Sharks (pid $pid, $bundle)"
    term_and_wait "$pid" 15 || die "ASCII Sharks (pid $pid) would not quit; stopping"
  done <"$TMP/sharks"
  [ -z "$(running_apps "$REAL_ID")$(running_apps "$SHARKS_ID")" ] || die "a wallpaper app is still running; stopping"
  sleep 2
}

launch_test() { # $@: --env options
  [ -z "$(pids_at "$TEST_EXEC")" ] || die "a test copy is already running"
  LAUNCHED=1
  open "$@" "$APP"
  for _ in $(seq 1 20); do TEST_PID="$(pids_at "$TEST_EXEC" | head -1)"; [ -n "$TEST_PID" ] && break; sleep 1; done
  [ -n "$TEST_PID" ] || die "the test copy did not start"
  [ "$(pids_at "$TEST_EXEC" | wc -l | tr -d ' ')" = 1 ] || die "more than one test copy is running"
  echo "test copy running (pid $TEST_PID)"
}

wait_for_director() { # $1: what to do
  echo "$1"
  echo "press Return here when done (Ctrl-C stops and cleans up)"
  read -r _ </dev/tty || true
}

# ---- Sampling: one-second top samples for exact pids; the first (since-boot) sample is dropped ----

# Prints "app_cpu ws_cpu app_mb app_mb_peak", or fails when any sample misses a row.
sample() { # $1 app pid or "", $2 WindowServer pid
  local args=(-l "$((SECS + 1))" -s 1 -stats pid,cpu,mem -pid "$2")
  [ -n "$1" ] && args+=(-pid "$1")
  top "${args[@]}" >"$TMP/top.txt" 2>/dev/null || die "top failed"
  parse_top "$TMP/top.txt" "$1" "$2" "$((SECS + 1))"
}
parse_top() { # $1 top's output, $2 app pid or "", $3 WindowServer pid, $4 samples expected
  awk -v app="${2:-none}" -v ws="$3" -v want="$4" '
    function mb(s,  v) { v = s + 0; if (s ~ /K/) v /= 1024; else if (s ~ /G/) v *= 1024; return v }
    /^Processes:/ { n++; next }
    n >= 2 && $1 == app { a[n] = $2; m[n] = mb($3); ha[n] = 1 }
    n >= 2 && $1 == ws { w[n] = $2; hw[n] = 1 }
    END {
      if (n != want) { printf "INVALID %d of %d samples\n", n, want; exit }
      sa = 0; sw = 0; sm = 0; pk = 0
      for (i = 2; i <= n; i++) {
        if (!hw[i]) { printf "INVALID sample %d has no WindowServer row\n", i; exit }
        if (app != "none" && !ha[i]) { printf "INVALID sample %d has no test-copy row\n", i; exit }
        sa += a[i]; sw += w[i]; sm += m[i]; if (m[i] > pk) pk = m[i]
      }
      k = n - 1
      printf "%.2f %.2f %.1f %.1f\n", sa / k, sw / k, sm / k, pk
    }' "$1"
}
window_server() {
  local p; p="$(pgrep -x WindowServer || true)"
  [ "$(printf '%s\n' "$p" | grep -c .)" = 1 ] || die "expected one WindowServer, found: $p"
  echo "$p"
}
# The test copy's own log: power mode and frames actually drawn, every 5 s, between two UTC stamps.
frame_report() { # $1 from, $2 to, [$3 log, $4 fps asked: the selftest's]
  local log="${3:-$TEST_LOG}" want="${4:-$FPS}"
  [ -f "$log" ] || { echo "  frame rate: NO LOG ($log) -- results invalid"; return 1; }
  awk -v from="$1" -v to="$2" -v want="$want" '
    $1 >= from && $1 <= to && $2 == "energy:" {
      n++
      for (i = 3; i <= NF; i++) { split($i, kv, "="); f[kv[1]] = kv[2] }
      modes[f["mode"]]++
      fps = f["fps"] + 0; s += fps; if (n == 1 || fps < lo) lo = fps
      last = sprintf("lowPower=%s battery=%s thermal=%s screens=%s", f["lowPower"], f["battery"], f["thermal"], f["screens"])
    }
    END {
      if (n == 0) { print "  frame rate: no lines in the window -- results invalid"; exit 1 }
      ml = ""; for (k in modes) ml = ml (ml == "" ? "" : ", ") k " x" modes[k]
      printf "  actual frame rate:       %.1f fps mean, %.1f lowest per screen (%d readings; asked %s)\n", s / n, lo, n, want
      printf "  power mode:              %s; %s\n", ml, last
      bad = 0; for (k in modes) if (k != "live" want) bad = 1
      if (bad || s / n < 0.85 * want) { print "  NOTE: not running live at the asked rate -- results invalid"; exit 1 }
    }' "$log"
}
utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ---- selftest (dry): the parsers on canned input; touches nothing ----

if [ "$MODE" = selftest ]; then
  set +e
  fails=0
  expect() { # $1 description, $2 got, $3 wanted (a glob)
    # shellcheck disable=SC2053
    if [[ "$2" == $3 ]]; then echo "ok    $1: $2"; else echo "FAIL  $1: got '$2', wanted $3"; fails=$((fails + 1)); fi
  }
  topfile() { # $1 file, then "pid cpu mem" rows per sample separated by "|"
    local f="$1" sample row; shift
    : >"$f"
    for sample in "$@"; do
      printf 'Processes: 700 total\nPID  %%CPU MEM\n' >>"$f"
      IFS='|' read -r -a rows <<<"$sample"
      for row in "${rows[@]}"; do [ -n "$row" ] && echo "$row" >>"$f"; done
    done
  }
  T="$TMP/t.txt"
  topfile "$T" "412 90.0 800M|501 50.0 100M" "412 20.0 800M|501 10.0 100M" "412 30.0 800M|501 12.0 120M"
  expect "full series" "$(parse_top "$T" 501 412 3)" "11.00 25.00 110.0 120.0"
  expect "short series" "$(parse_top "$T" 501 412 4)" "INVALID 3 of 4 samples"
  topfile "$T" "412 90.0 800M|501 50.0 100M" "501 10.0 100M" "412 30.0 800M|501 12.0 120M"
  expect "missing WindowServer row" "$(parse_top "$T" 501 412 3)" "INVALID sample 2 has no WindowServer row"
  topfile "$T" "412 90.0 800M|501 50.0 100M" "412 20.0 800M|501 10.0 100M" "412 30.0 800M|777 12.0 120M"
  expect "another process instead of the test copy" "$(parse_top "$T" 501 412 3)" "INVALID sample 3 has no test-copy row"
  topfile "$T" "412 90.0 800M" "412 20.0 800M" "412 30.0 1.5G"
  expect "baseline (WindowServer only)" "$(parse_top "$T" "" 412 3)" "0.00 25.00 0.0 0.0"
  L="$TMP/log.txt"
  line() { echo "$1 energy: mode=$2 fps=$3 screens=2 setting=30 habitat=meadow count=7 lowPower=false battery=false thermal=$4"; }
  { line 2026-11-21T10:00:00Z live30 12.0 nominal; line 2026-11-21T10:00:15Z live30 29.8 nominal
    line 2026-11-21T10:00:20Z live30 29.6 nominal; line 2026-11-21T10:01:30Z live15 15.0 serious; } >"$L"
  expect "live at 30" "$(frame_report 2026-11-21T10:00:10Z 2026-11-21T10:01:10Z "$L" 30 | head -1)" "*29.7 fps mean, 29.6 lowest*2 readings*"
  out="$(frame_report 2026-11-21T10:00:10Z 2026-11-21T10:01:40Z "$L" 30)"; rc=$?
  expect "held at 15 by heat" "$rc $(echo "$out" | tail -1)" "1 *not running live at the asked rate*"
  out="$(frame_report 2026-11-21T11:00:00Z 2026-11-21T11:01:00Z "$L" 30)"; rc=$?
  expect "no readings" "$rc $out" "1 *no lines in the window*"
  { line 2026-11-21T10:00:15Z live30 21.0 nominal; } >"$L"
  out="$(frame_report 2026-11-21T10:00:10Z 2026-11-21T10:01:10Z "$L" 30)"; rc=$?
  expect "live but slow (a covered screen)" "$rc $(echo "$out" | tail -1)" "1 *not running live*"
  out="$(frame_report 2026-11-21T10:00:10Z 2026-11-21T10:01:10Z "$TMP/none.txt" 30)"; rc=$?
  expect "no log" "$rc $out" "1 *NO LOG*"
  echo "selftest: $fails failed"
  [ "$fails" = 0 ]
  exit
fi

# ---- The runs ----

if [ "$DRY" = 1 ]; then
  echo "dry run ($MODE): the lock and the test domain only; nothing quit, launched or sampled"
  TOUCHED=1
  delete_domain || die "could not clear $DOMAIN"
  if [ "$MODE" = measure ] || [ "$MODE" = calibrate ]; then write_settings; fi
  echo "idling ${ENERGY_DRY_SLEEP:-0}s"
  sleep "${ENERGY_DRY_SLEEP:-0}"
  if [ "$MODE" = calibrate ]; then
    if [ -n "${ENERGY_DRY_COUNT-}" ]; then
      COUNT="$ENERGY_DRY_COUNT"; write_settings >/dev/null   # stands in for the director's choice in Settings
    fi
    hex="$(settings_hex)"
    case "$hex" in ABSENT|ERROR) die "no settings to read the count from ($hex)" ;; esac
    echo "count chosen: $(printf '%s' "$hex" | xxd -r -p | jq -r '.meadowCount // "the default (unchanged)"') (note it; it is not saved anywhere else)"
  fi
  [ "$MODE" = preview ] && { domain_absent || die "the preview wrote to $DOMAIN"; echo "preview: the test domain stayed absent"; }
  exit 0
fi

quit_owner_apps
TOUCHED=1
delete_domain || die "could not clear the test domain $DOMAIN"

case "$MODE" in
  baseline)
    WS="$(window_server)"
    echo "baseline: no wallpaper app; settling ${SETTLE}s, sampling WindowServer (pid $WS) ${SECS}s"
    sleep "$SETTLE"
    S="$(sample "" "$WS")"
    case "$S" in INVALID*) die "sampling ${S#INVALID } -- results invalid, rerun" ;; esac
    read -r _ WSCPU _ _ <<<"$S"
    echo "baseline WindowServer mean CPU: ${WSCPU}%"
    ;;
  measure)
    write_settings
    launch_test --env ASCII_ANIMALS_NO_HANDOVER=1 --env ASCII_ANIMALS_QUIET_LAUNCH=1
    WS="$(window_server)"
    echo "settling ${SETTLE}s, then sampling ${SECS}s"
    sleep "$SETTLE"
    FROM="$(utc)"
    S="$(sample "$TEST_PID" "$WS")"
    TO="$(utc)"
    case "$S" in INVALID*) die "sampling ${S#INVALID } -- results invalid, rerun" ;; esac
    alive "$TEST_PID" || die "the test copy quit during sampling -- results invalid"
    read -r APPCPU WSCPU MEM MEMPK <<<"$S"
    echo "habitat=$HABITAT fps=$FPS seconds=$SECS${COUNT:+ count=$COUNT}"
    echo "  test copy CPU (mean):    ${APPCPU}%"
    echo "  WindowServer CPU (mean): ${WSCPU}%   (minus the baseline run = added)"
    echo "  test copy memory:        ${MEM} MB mean, ${MEMPK} MB peak"
    sleep 1   # the log is written off the main thread
    frame_report "$FROM" "$TO" || VALID=0
    if awk -v a="$APPCPU" 'BEGIN{exit !(a<0.3)}'; then
      echo "  NOTE: app CPU ~ 0 -> looked paused (desktop covered?) -- results invalid"; VALID=0
    fi
    [ "${VALID:-1}" = 1 ] || exit 1
    ;;
  preview)
    launch_test --env ASCII_ANIMALS_NO_HANDOVER=1 --env ASCII_ANIMALS_PREVIEW_WHATSNEW=1
    wait_for_director "the card appears under the test copy's menu bar icon in a second or two. Its buttons and Esc only
close it; a click outside closes it AND reaches whatever was clicked."
    ;;
  calibrate)
    write_settings
    launch_test --env ASCII_ANIMALS_NO_HANDOVER=1 --env ASCII_ANIMALS_QUIET_LAUNCH=1 --env ASCII_ANIMALS_BUILTIN_DISPLAY_ONLY=1
    wait_for_director "the Meadow is on the built-in display alone. Open Settings from the test copy's menu bar icon
(its menu starts with \"$TEST_NAME: energy test copy\") and move the butterfly count until it looks right."
    term_and_wait "$TEST_PID" 15 || die "the test copy would not quit; the count was not read"
    hex="$(settings_hex)"
    case "$hex" in ABSENT|ERROR) die "no settings to read the count from ($hex)" ;; esac
    echo "count chosen: $(printf '%s' "$hex" | xxd -r -p | jq -r '.meadowCount // "the default (unchanged)"') (note it; it is not saved anywhere else)"
    ;;
esac
