#!/bin/bash
# Energy measurement with the ENERGY-TEST COPY of ASCII Animals (Tools/build.sh --test builds it):
# "build/ASCII Animals Test.app", bundle ID local.ascii-animals.energy-test, its own defaults domain, and no updater,
# Sharks hand-over, uninstaller, system-wallpaper match or login item (AppIdentity in OceanKit). Its log, its crash
# marker and everything this script makes live in one folder, build/energy-test.
#
#   Tools/energy.sh baseline [seconds=60]                        WindowServer with no wallpaper app running
#   Tools/energy.sh <ocean|web|meadow> <15|30|60> [seconds=60] [count]
#                                                                one habitat; count = the Meadow's butterflies
#                                                                (1-12; default: the app's default)
#   Tools/energy.sh preview                                      the what's-new card once, on the live desktop;
#                                                                fails before asking if the card's drawn check
#                                                                (its own window's pixels) finds it empty; done
#                                                                when the director types "seen"
#   Tools/energy.sh calibrate [count]                            the Meadow on the built-in display alone; done
#                                                                when the director types the count they chose
#   Tools/energy.sh status                                       what is running, the lock, leftovers (no change)
#   Tools/energy.sh recover                                      after a killed run: quit this checkout's test
#                                                                copy, delete the test domain, clear a dead lock
# "WindowServer added" = (with the app) - (baseline). Run with the desktop UNCOVERED (a covered desktop pauses).
#
# THE DIRECTOR'S OWN APPS ARE NEVER TOUCHED. This script never quits, signals or opens ASCII Animals or ASCII Sharks;
# a live mode refuses to start (and a run is invalid) while either is running: the director quits them from their
# menus first and reopens them after. The only process it ever signals is the test copy it launched, its identity
# (executable path from the kernel, bundle ID, start time) checked again right before each signal.
#
# Every live run: one at a time (a lock directory, build/energy-test/lock, made atomically; nothing inherited can skip
# it); the test domain is deleted, written for this run (habitat, fps, count; the wallpaper match and update checks
# off) and deleted again at the end, verified; the test copy is launched with every test flag set (1 or 0) and its
# logged plan checked against the mode; the sampled minute must be complete (top rows, the copy's readings, the power
# state), every display at the asked rate, the displays drawn = the displays attached and the same set throughout,
# plugged in, Low Power Mode off, and no wallpaper app (ASCII Animals, ASCII Sharks, another test copy) seen at any
# look during the sampling. Each launch gets its own id (ASCII_ANIMALS_ENERGY_LAUNCH): the plan, the card and the
# readings count only when they carry it, so an old log line, a reused pid or an offscreen probe never counts.
# build/energy-test and its parents inside the checkout must be real folders (a symbolic link there is refused).
#
# Test hooks (never for a real run): ENERGY_DRY=1 does the lock, the test domain and the read-only checks only
# (nothing launched, quit or sampled); with it, ENERGY_TEST_DOMAIN=local.ascii-animals.energy-test.<word> picks a
# throwaway domain in the test namespace, ENERGY_DRY_SLEEP=<s> idles with the domain written (a Ctrl-C test), and
# ENERGY_DRY_COUNT=<n> stands in for the count the director picks while calibrating. `ENERGY_DRY=1 Tools/energy.sh
# selftest` runs the parsers on canned input.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
TEST_ID="local.ascii-animals.energy-test"
TEST_EXE="ASCIIAnimalsEnergyTest"
TEST_NAME="ASCII Animals Test"
REAL_ID="local.ascii-animals.wallpaper"
SHARKS_ID="local.ascii-sharks.wallpaper"
REAL_EXES="ASCIIAnimals ASCIISharks"
APP="$ROOT/build/$TEST_NAME.app"
TEST_EXEC="$APP/Contents/MacOS/$TEST_EXE"
FOLDER="$ROOT/build/energy-test"      # everything: the lock, the scratch, the test copy's log, the results
LOCK="$FOLDER/lock"                   # a directory: mkdir is atomic
RUN="$FOLDER/run"                     # this run's scratch, removed at the end
APPLOG="$FOLDER/app/ascii-animals.log"
RESULTS="$FOLDER/results.log"
KEY="settings.v2"
PLKEY="settings\.v2"   # plutil key path: the dot must be escaped
SETTLE=10
QUIT_MSG="Quit ASCII Animals and ASCII Sharks from their menus first"
# Nothing inherited may change a mode: each launch sets every flag itself.
unset ASCII_ANIMALS_QUIET_LAUNCH ASCII_ANIMALS_PREVIEW_WHATSNEW ASCII_ANIMALS_BUILTIN_DISPLAY_ONLY ASCII_ANIMALS_SNAPSHOT_LIGHT
CONFIRM_FIXTURE=""   # set by the selftest only (it answers at once instead of waiting a second per look)
LAUNCH_ID=""         # this launch's id, made in launch_test

die() { echo "energy.sh: $*" >&2; exit 1; }

# A pre-check, not a general filesystem guard: build/ and build/energy-test (and what this script makes in it) must not
# be symbolic links, or the lock, the scratch and the test copy's files could land outside the checkout.
for linkcheck in "$ROOT/build" "$FOLDER" "$LOCK" "$RUN" "$FOLDER/selftest" "$FOLDER/app" "$RESULTS"; do
  [ ! -L "$linkcheck" ] || die "refused: ${linkcheck#"$ROOT"/} is a symbolic link; build/energy-test and its parents must be real folders"
done

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

for tool in jq xxd plutil base64 defaults top ps open lsof lsappinfo pgrep pmset codesign od; do
  command -v "$tool" >/dev/null 2>&1 || die "needs '$tool' on the PATH"
done

usage() {
  echo "usage: $0 baseline [s] | $0 <ocean|web|meadow> <15|30|60> [s] [count] | $0 preview | $0 calibrate [count] | $0 status | $0 recover" >&2
  exit 2
}
[ $# -ge 1 ] || usage
MODE="$1"; HABITAT=""; FPS=""; SECS=60; COUNT=""
case "$MODE" in
  baseline) [ $# -le 2 ] || usage; SECS="${2:-60}" ;;
  ocean|web|meadow)
    [ $# -ge 2 ] && [ $# -le 4 ] || usage
    HABITAT="$MODE"; FPS="$2"; SECS="${3:-60}"; COUNT="${4:-}"
    case "$FPS" in 15|30|60) ;; *) usage ;; esac
    MODE=measure ;;
  preview) [ $# = 1 ] || usage ;;
  calibrate) [ $# -le 2 ] || usage; HABITAT=meadow; FPS=30; COUNT="${2:-}" ;;
  status|recover|selftest) [ $# = 1 ] || usage ;;
  *) usage ;;
esac
case "$SECS" in ''|*[!0-9]*) usage ;; esac
if [ "$MODE" = measure ] || [ "$MODE" = baseline ]; then
  [ "$SECS" -ge 20 ] && [ "$SECS" -le 600 ] || die "seconds must be 20-600 (a reading comes every 5 s)"
fi
if [ -n "$COUNT" ]; then
  case "$COUNT" in *[!0-9]*) usage ;; esac
  [ "$COUNT" -ge 1 ] && [ "$COUNT" -le 12 ] || die "count must be 1-12"
  [ "$HABITAT" = meadow ] || die "a count is for the Meadow only"
fi
[ "$DRY" = 1 ] && [ "$MODE" = baseline ] && die "a dry run has nothing to measure; baseline is live only"
[ "$MODE" = selftest ] && [ "$DRY" != 1 ] && die "selftest is a dry-run hook: ENERGY_DRY=1"

utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ---- Processes: what runs, by kernel executable path and LaunchServices bundle ID ----

alive() { kill -0 "$1" 2>/dev/null; }
proc_start() { ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed -e 's/^ //' -e 's/ $//' || true; }
# The executable the kernel maps for the process (not argv[0], which any process can set).
exe_path() { lsof -a -p "$1" -d txt -Fn 2>/dev/null | awk '/^n/ { print substr($0, 2); exit }' || true; }
ls_bundle_id() { lsappinfo info -app "$1" -only bundleid 2>/dev/null | sed -n 's/^"CFBundleIdentifier"="\(.*\)"$/\1/p' | head -1 || true; }
plist_id() { plutil -extract CFBundleIdentifier raw -o - "$1/Contents/Info.plist" 2>/dev/null || true; }
plist_exe() { plutil -extract CFBundleExecutable raw -o - "$1/Contents/Info.plist" 2>/dev/null || true; }
pids_for_bundle_id() { # every process LaunchServices knows with bundle ID $1
  local asn
  lsappinfo find "bundleid=$1" 2>/dev/null | grep -oE 'ASN:0x[0-9a-fA-F]+-0x[0-9a-fA-F]+' | while read -r asn; do
    lsappinfo info -only pid "$asn" 2>/dev/null | sed -n 's/^"pid"=\([0-9][0-9]*\)$/\1/p'
  done
  return 0
}
REAL_TEST_EXEC=""   # the test executable's path with links resolved, once the bundle is checked
real_test_exec() { [ -x "$TEST_EXEC" ] && realpath "$TEST_EXEC" 2>/dev/null || true; }

# Anything that might be a test copy, from any folder: by bundle ID, executable name or the kernel's short name.
test_candidates() {
  {
    pids_for_bundle_id "$TEST_ID"
    ps -ax -o pid=,comm= | awk -v exe="$TEST_EXE" '{ pid = $1; sub(/^[ \t]*[0-9]+[ \t]+/, ""); n = split($0, p, "/"); if (p[n] == exe) print pid }'
    pgrep -x "$(printf '%s' "$TEST_EXE" | cut -c1-16)" || true
  } | sort -un
}
# This checkout's test copy: the kernel's executable path is this checkout's test executable and LaunchServices
# gives the test bundle ID. $2 (optional): the start time recorded at launch, so a reused pid never passes.
is_our_test_copy() {
  local pid="$1" start="${2-}" exe
  alive "$pid" || return 1
  [ -z "$start" ] || [ "$(proc_start "$pid")" = "$start" ] || return 1
  [ -n "$REAL_TEST_EXEC" ] || REAL_TEST_EXEC="$(real_test_exec)"
  exe="$(exe_path "$pid")"
  [ -n "$exe" ] && [ "$exe" = "$REAL_TEST_EXEC" ] || return 1
  [ "$(ls_bundle_id "$pid")" = "$TEST_ID" ]
}
# The director's apps, running: "pid what" for every process that is (or may be) ASCII Animals or ASCII Sharks.
real_apps_running() {
  local id pid comm bundle exe
  {
    for id in "$REAL_ID" "$SHARKS_ID"; do
      for pid in $(pids_for_bundle_id "$id"); do echo "$pid $id"; done
    done
    ps -ax -o pid=,comm= | while read -r pid comm; do
      case "$comm" in *.app/Contents/MacOS/*) ;; *) continue ;; esac
      bundle="${comm%%.app/Contents/MacOS/*}.app"
      id="$(plist_id "$bundle")"
      case "$id" in "$REAL_ID"|"$SHARKS_ID") echo "$pid $id ($bundle)" ;; esac
    done
    for exe in $REAL_EXES; do
      for pid in $(pgrep -x "$exe" || true); do echo "$pid executable $exe"; done
    done
  } | sort -un -k1,1
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
  local f="$RUN/now.plist" err type
  if domain_absent; then echo ABSENT; return; fi
  defaults export "$DOMAIN" "$f" >/dev/null 2>&1 || { echo ERROR; return; }
  if err="$(plutil -extract "$PLKEY" raw -o - "$f" 2>&1 >"$RUN/now.b64")"; then
    type="$(plutil -type "$PLKEY" "$f" 2>/dev/null || true)"
    [ "$type" = data ] || { echo ERROR; return; }
    base64 -D <"$RUN/now.b64" 2>/dev/null | xxd -p | tr -d '\n' || echo ERROR
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

# ---- The lock: a directory made with mkdir (atomic), owner "pid start" inside; nothing inherited can skip it ----

LOCKED=0
lock_owner() { cat "$LOCK/owner" 2>/dev/null || true; }
lock_state() { # free | held | dead (the owner is gone) | unowned (no owner file for over 10 s) | starting
  [ -d "$LOCK" ] || { echo free; return; }
  local o pid start age; o="$(lock_owner)"
  if [ -z "$o" ]; then
    age=$(( $(date +%s) - $(stat -f %m "$LOCK" 2>/dev/null || date +%s) ))
    if [ "$age" -gt 10 ]; then echo unowned; else echo starting; fi
    return
  fi
  pid="${o%% *}"; start="${o#* }"
  case "$pid" in ''|*[!0-9]*) echo unowned; return ;; esac
  if alive "$pid" && [ "$(proc_start "$pid")" = "$start" ]; then echo held; else echo dead; fi
}
take_lock() { # $1: 1 to clear a dead or unowned lock first (recover only)
  mkdir -p "$FOLDER"
  local judged aside
  if [ "${1:-0}" = 1 ]; then
    case "$(lock_state)" in
      dead|unowned)
        # Moved aside atomically (one recover wins), then checked it is still the lock judged gone.
        judged="$(lock_owner)"; aside="$FOLDER/lock.gone.$$"
        if mv "$LOCK" "$aside" 2>/dev/null; then
          if [ "$(cat "$aside/owner" 2>/dev/null || true)" = "$judged" ]; then
            echo "cleared a lock left by a run that is gone (${judged:-no owner})"; rm -rf "$aside"
          else
            mv "$aside" "$LOCK" 2>/dev/null || true
          fi
        fi ;;
    esac
  fi
  if mkdir "$LOCK" 2>/dev/null; then
    LOCKED=1
    printf '%s %s\n' "$$" "$(proc_start $$)" >"$LOCK/owner"
    return 0
  fi
  echo "energy.sh: another run holds the lock ($LOCK: $(lock_state), $(lock_owner)); one run at a time." >&2
  echo "  If no run is under way: $0 status, then $0 recover" >&2
  exit 75
}
release_lock() { [ "$LOCKED" = 1 ] && rm -rf "$LOCK"; LOCKED=0; }

# ---- Parsers (the selftest feeds them canned input) ----

# top -l <n> -stats pid,cpu,mem for exact pids. Strict: every sample has one column header and exactly one well-formed
# row per pid asked for, nothing else; the first sample (since boot) is dropped. Prints "app_cpu ws_cpu app_mb
# app_mb_peak", or "INVALID <why>".
parse_top() { # $1 top's output, $2 app pid or "", $3 WindowServer pid, $4 samples expected
  awk -v app="${2:-none}" -v ws="$3" -v want="$4" '
    function mb(s,  v) { v = s + 0; if (s ~ /K/) v /= 1024; else if (s ~ /G/) v *= 1024; else if (s ~ /B/) v /= 1048576; return v }
    function fail(why) { if (bad == "") bad = why; done = 1 }
    done { next }
    /^Processes:/ { n++; rows = 0; next }
    n == 0 { next }
    /^PID[ \t]+%CPU[ \t]+MEM[ \t]*$/ { if (hdr[n]) fail("sample " n " has two column headers"); hdr[n] = 1; next }
    !hdr[n] { next }
    /^[ \t]*$/ { next }
    {
      if ($0 !~ /^[0-9]+[ \t]+[0-9]+(\.[0-9]+)?[ \t]+[0-9]+(\.[0-9]+)?[BKMG][+-]?[ \t]*$/) { fail("sample " n " has a malformed row: " $0); next }
      if ($1 != app && $1 != ws) { fail("sample " n " has a row for pid " $1 ", not asked for"); next }
      if (seen[n, $1]++) { fail("sample " n " has pid " $1 " twice"); next }
      if ($1 == ws) w[n] = $2 + 0; else { a[n] = $2 + 0; m[n] = mb($3) }
    }
    END {
      if (bad != "") { print "INVALID " bad; exit }
      if (n != want) { printf "INVALID %d of %d samples\n", n, want; exit }
      sa = 0; sw = 0; sm = 0; pk = 0
      for (i = 1; i <= n; i++) {
        if (!hdr[i]) { printf "INVALID sample %d has no column header\n", i; exit }
        if (!seen[i, ws]) { printf "INVALID sample %d has no WindowServer row\n", i; exit }
        if (app != "none" && !seen[i, app]) { printf "INVALID sample %d has no test-copy row\n", i; exit }
        if (i == 1) continue
        sa += a[i]; sw += w[i]; sm += m[i]; if (m[i] > pk) pk = m[i]
      }
      k = n - 1
      printf "%.2f %.2f %.1f %.1f\n", sa / k, sw / k, sm / k, pk
    }' "$1"
}

# One power line from `pmset -g batt` and `pmset -g`: "ac=<1|0|?> lowpower=<1|0|?>". Only known values count: a
# source other than 'AC Power' or 'Battery Power', or a mode value other than 0 or 1, is "?" (and a run with it is
# invalid).
power_line() { # $1 pmset -g batt, $2 pmset -g
  local ac="?" lp="?"
  case "$(printf '%s\n' "$1" | head -1)" in *"'AC Power'"*) ac=1 ;; *"'Battery Power'"*) ac=0 ;; esac
  lp="$(printf '%s\n' "$2" | awk '
    function known(x) { return (x == "0" || x == "1") ? x : "?" }
    /^Currently in use:/ { cur = 1; next }
    /^[^ \t]/ { cur = 0 }
    cur && $1 == "lowpowermode" { v = known($2); found = 1 }
    cur && $1 == "powermode" && !found { v = known($2); found = 1 }
    END { print (found ? v : "?") }')"
  echo "ac=$ac lowpower=$lp"
}
power_now() { power_line "$(pmset -g batt 2>/dev/null || true)" "$(pmset -g 2>/dev/null || true)"; }
# The power trace: "<utc> ac=1 lowpower=0" lines, one every 5 s through the sampling. Valid when complete: real UTC
# stamps inside the sampled window, each later than the one before, covering it (no more than 7 s missing at either
# end), and every line plugged in with Low Power Mode off (known values only).
check_power() { # $1 trace, $2 from (UTC), $3 to (UTC), $4 seconds sampled
  awk -v from="$2" -v to="$3" -v secs="$4" '
    function t(s) { return ((substr(s, 6, 2) * 31 + substr(s, 9, 2)) * 86400) + substr(s, 12, 2) * 3600 + substr(s, 15, 2) * 60 + substr(s, 18, 2) }
    function stamp(s) { return s ~ /^20[0-9][0-9]-[01][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]Z$/ }
    { n++ }
    $0 !~ /^[^ ]+ ac=[01?] lowpower=[01?]$/ { bad = "malformed power line: " $0; exit }
    !stamp($1) { bad = "a power reading with a malformed stamp: " $0; exit }
    $1 < from || $1 > to { bad = "a power reading at " $1 ", outside the sampled window " from " to " to; exit }
    n > 1 && $1 <= last { bad = "power readings out of order or repeated at " $1; exit }
    { last = $1; if (n == 1) first = $1 }
    $2 == "ac=?" { bad = "power source unknown at " $1 " (pmset shows neither AC nor battery)"; exit }
    $2 != "ac=1" { bad = "on battery at " $1; exit }
    $3 == "lowpower=?" { bad = "Low Power Mode unknown at " $1 " (pmset shows no known powermode value)"; exit }
    $3 != "lowpower=0" { bad = "Low Power Mode on at " $1; exit }
    END {
      if (bad != "") { print "INVALID " bad; exit }
      if (!stamp(from) || !stamp(to)) { print "INVALID the sampled window is not two UTC stamps"; exit }
      if (n < int(secs / 5)) { printf "INVALID %d power readings for %d s\n", n, secs; exit }
      if (t(first) - t(from) > 7 || t(to) - t(last) > 7) { print "INVALID the power readings do not cover the sampled window"; exit }
      printf "plugged in, Low Power Mode off (%d readings)\n", n
    }' "$1"
}

# The test copy's readings (EnergyLog.reading in OceanKit) between two UTC stamps for one pid. Strict: each line
# has exactly the expected fields, once each, well formed; no duplicate stamps; no gap over 7 s; the window covered.
# Only this launch's readings count (pid and launch id). Kinds: measure (live at the asked rate on every display,
# displays drawn = attached, the same set of displays throughout, never on battery or in Low Power Mode), calibrate
# (one display, built-in, drawn), preview (a built-in display drawn).
check_readings() { # $1 log, $2 pid, $3 launch id, $4 from, $5 to, $6 kind, $7 fps, $8 habitat, $9 count or ""
  [ -f "$1" ] || return 0   # no log yet (the test copy writes its first line a moment after launch): nothing, never an exit
  awk -v pid="$2" -v launch="$3" -v from="$4" -v to="$5" -v kind="$6" -v want="$7" -v hab="$8" -v cnt="$9" '
    function t(s) { return (substr(s, 9, 2) + 0) * 86400 + substr(s, 12, 2) * 3600 + substr(s, 15, 2) * 60 + substr(s, 18, 2) }
    function fail(why) { if (bad == "") bad = why; done = 1 }
    done { next }
    $2 != "energy:" || $1 < from || $1 > to { next }
    $3 != "pid=" pid || $4 != "launch=" launch { next }
    {
      if ($1 !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/) { fail("a reading with a malformed stamp: " $0); next }
      if (NF != 14) { fail("a reading with " NF - 2 " fields, not 12: " $0); next }
      split("pid launch mode setting habitat count attached drawn displays lowPower battery thermal", keys, " ")
      for (i = 1; i <= 12; i++) {
        eq = index($(i + 2), "=")
        if (eq == 0 || substr($(i + 2), 1, eq - 1) != keys[i]) { fail("a reading out of shape at " keys[i] ": " $0); next }
        f[keys[i]] = substr($(i + 2), eq + 1)
      }
      if (f["mode"] !~ /^(live[0-9]+|still|paused)$/ || f["setting"] !~ /^[0-9]+$/ || f["count"] !~ /^[0-9]+$/ \
          || f["attached"] !~ /^[0-9]+$/ || f["drawn"] !~ /^[0-9]+$/ || f["lowPower"] !~ /^(true|false)$/ \
          || f["battery"] !~ /^(true|false)$/ || f["thermal"] !~ /^[a-z]+$/ || f["habitat"] !~ /^[a-z]+$/) {
        fail("a reading with a malformed field: " $0); next
      }
      if ($1 in stamps) { fail("two readings at " $1); next }
      stamps[$1] = 1
      if (n > 0 && t($1) - prev > 7) { fail("no reading for " t($1) - prev " s before " $1); next }
      if (n == 0) first = t($1)
      prev = t($1); n++
      nd = 0; b = 0; delete idsnow
      if (f["displays"] != "none") {
        nd = split(f["displays"], ds, ",")
        for (i = 1; i <= nd; i++) {
          if (ds[i] !~ /^[0-9]+:[be]:[0-9]+\.[0-9]$/) { fail("a malformed display entry " ds[i] " at " $1); next }
          split(ds[i], d, ":")
          if ((d[1], n) in got) { fail("display " d[1] " twice at " $1); next }
          got[d[1], n] = 1; idsnow[i] = d[1] + 0
          if (d[2] == "b" && d[3] + 0 > 0) b++
          if (!(d[1] in sum)) { ids[++nids] = d[1]; kindof[d[1]] = d[2]; low[d[1]] = d[3] + 0 }
          sum[d[1]] += d[3]; cnt_d[d[1]]++
          if (d[3] + 0 < low[d[1]]) low[d[1]] = d[3] + 0
        }
      }
      if (nd != f["drawn"] + 0) { fail("drawn=" f["drawn"] " but " nd " displays listed at " $1); next }
      lastcount = f["count"]
      if (kind == "measure") {
        if (f["mode"] != "live" want) { fail("mode " f["mode"] " at " $1 ", not live" want); next }
        if (f["setting"] != want || f["habitat"] != hab) { fail("set to " f["habitat"] " at " f["setting"] " fps at " $1); next }
        if (cnt != "" && f["count"] != cnt) { fail("count " f["count"] " at " $1 ", not " cnt); next }
        if (f["lowPower"] != "false") { fail("Low Power Mode on at " $1); next }
        if (f["battery"] != "false") { fail("on battery at " $1); next }
        if (f["attached"] + 0 < 1 || f["drawn"] != f["attached"]) { fail(f["drawn"] " of " f["attached"] " displays drawn at " $1); next }
        if (n == 1) screens = f["attached"]; else if (f["attached"] != screens) { fail("the displays changed during the run at " $1); next }
        # The same displays (by id) at every reading, not only the same number.
        for (i = 1; i <= nd; i++) for (j = i + 1; j <= nd; j++) if (idsnow[j] < idsnow[i]) { x = idsnow[i]; idsnow[i] = idsnow[j]; idsnow[j] = x }
        set = ""; for (i = 1; i <= nd; i++) set = set (i > 1 ? "," : "") idsnow[i]
        if (n == 1) firstset = set; else if (set != firstset) { fail("the displays changed during the run at " $1 " (" set ", was " firstset ")"); next }
        for (i = 1; i <= nd; i++) {
          split(ds[i], d, ":")
          if (d[3] + 0 < 0.85 * want || d[3] + 0 > 1.15 * want) { fail("display " d[1] " at " d[3] " fps at " $1 ", asked " want); next }
        }
      } else if (kind == "calibrate") {
        if (f["habitat"] != "meadow") { fail("not the Meadow at " $1); next }
        if (f["drawn"] != "1" || nd != 1 || ds[1] !~ /:b:/) { fail("not the built-in display alone at " $1 " (" f["displays"] ")"); next }
        if (b) builtin++
      } else if (kind == "preview") {
        if (b) builtin++
      }
    }
    END {
      if (bad != "") { print "INVALID " bad; exit }
      if (n == 0) { print "INVALID no readings in the window"; exit }
      if (kind == "measure") {
        if (first - t(from) > 7 || t(to) - prev > 7) { print "INVALID the readings do not cover the window"; exit }
        if (n < int((t(to) - t(from)) / 5) - 1) { printf "INVALID %d readings for %d s\n", n, t(to) - t(from); exit }
      } else if (!builtin) { print "INVALID no built-in display drew a frame"; exit }
      for (i = 1; i <= nids; i++) {
        id = ids[i]
        printf "  display %s (%s): %.1f fps mean, %.1f lowest (%d readings)\n", id, (kindof[id] == "b" ? "built-in" : "external"), sum[id] / cnt_d[id], low[id], cnt_d[id]
      }
      printf "OK %d readings, %d displays, count=%s\n", n, nids, lastcount
    }' "$1"
}

# A result counts only when its parser said so positively (an awk failure prints nothing, and nothing is not a pass).
sampled_ok() { [[ "$1" =~ ^[0-9]+\.[0-9]{2}\ [0-9]+\.[0-9]{2}\ [0-9]+\.[0-9]\ [0-9]+\.[0-9]$ ]]; }
power_ok() { [[ "$1" == "plugged in, Low Power Mode off ("*" readings)" ]]; }
readings_ok() { [[ "$(printf '%s' "$1" | tail -1)" =~ ^OK\ [0-9]+\ readings ]] && [[ "$1" != *INVALID* ]]; }

# This launch's first reading stamped after $4 ("" if none yet): "<count> drew" when it drew live on the built-in
# display alone (one display, built-in, more than 0 fps), else "<count> not-drawn" (paused, still, nothing drawn, an
# external display). $1 log, $2 pid, $3 launch id.
calibration_after() {
  [ -f "$1" ] || return 0   # no log yet (the test copy writes its first line a moment after launch): nothing, never an exit
  awk -v pid="$2" -v launch="$3" -v after="$4" '$2 == "energy:" && $3 == "pid=" pid && $4 == "launch=" launch && $1 > after {
      c = ""; m = ""; dr = ""; ds = ""
      for (i = 5; i <= NF; i++) {
        if ($i ~ /^count=[0-9]+$/) c = substr($i, 7)
        else if ($i ~ /^mode=/) m = substr($i, 6)
        else if ($i ~ /^drawn=/) dr = substr($i, 7)
        else if ($i ~ /^displays=/) ds = substr($i, 10)
      }
      if (c == "") next
      ok = (m ~ /^live[0-9]+$/ && dr == "1" && ds ~ /^[0-9]+:b:[0-9]+\.[0-9]$/ && substr(ds, index(ds, ":b:") + 3) + 0 > 0)
      print c, (ok ? "drew" : "not-drawn"); exit }' "$1"
}

card_shown() { grep -qF "energy-card: pid=$2 launch=$3 shown" "$1" 2>/dev/null; }   # $1 log, $2 pid, $3 launch id
# The card's drawn check (EnergyLog.cardDrawn): this launch's "<share> <w>x<h>", or "" if none (yet). $1 log, $2 pid,
# $3 launch id. Only the exact shape counts.
card_drawn() {
  [ -f "$1" ] || return 0
  awk -v pid="$2" -v launch="$3" 'NF == 6 && $2 == "energy-card:" && $3 == "pid=" pid && $4 == "launch=" launch \
      && $5 ~ /^drawn=[01]\.[0-9][0-9][0-9]$/ && $6 ~ /^size=[0-9]+x[0-9]+$/ { print substr($5, 7), substr($6, 6); exit }' "$1"
}
# The card going (EnergyLog.cardClosed): this launch's "<reason> <seconds after it was shown>", or "". Same arguments.
card_closed() {
  [ -f "$1" ] || return 0
  awk -v pid="$2" -v launch="$3" 'NF == 6 && $2 == "energy-card:" && $3 == "pid=" pid && $4 == "launch=" launch \
      && $5 ~ /^closed=[a-z-]+$/ && $6 ~ /^after=[0-9]+s$/ { print substr($5, 8), substr($6, 7, length($6) - 7); exit }' "$1"
}
# The least share of the card's window that must be drawn. The card covers about 0.98 of it (the rest is the corners
# and the room beside its arrow); an empty card is 0.
DRAWN_MIN=0.5
# Waits up to $4 s for this launch's drawn check (args as card_drawn). Prints "OK <share> <size>", or "FAIL <why>".
card_drawn_check() {
  local i d="" c share size
  for i in $(seq 1 "$4"); do
    d="$(card_drawn "$1" "$2" "$3")"; [ -n "$d" ] && break
    c="$(card_closed "$1" "$2" "$3")"
    if [ -n "$c" ]; then echo "FAIL the card closed (${c% *}, ${c#* } s after it was shown) before its drawn check"; return 0; fi
    [ -n "$CONFIRM_FIXTURE" ] || sleep 1
  done
  [ -n "$d" ] || { echo "FAIL the card logged no drawn check in $4 s"; return 0; }
  read -r share size <<<"$d"
  if awk -v s="$share" -v m="$DRAWN_MIN" 'BEGIN { exit !(s + 0 >= m + 0) }'; then
    echo "OK $share $size"
  else
    echo "FAIL the card drew $share of its window ($size points): empty"
  fi
}
plan_of() { # this launch's logged plan (pid $2, launch id $3): "greeting=<g> builtInOnly=<0|1>"
  [ -f "$1" ] || return 0   # no log yet (the test copy writes its first line a moment after launch): nothing, never an exit
  awk -v pid="$2" -v launch="$3" '$2 == "energy-plan:" && $3 == "pid=" pid && $4 == "launch=" launch { print $5, $6 }' "$1" 2>/dev/null | tail -1
}

# Answers typed by the director, from fd 3 (the terminal). End of input is a failure, never a yes.
ask() { # $1 prompt; prints the answer, trimmed
  local a
  printf '%s' "$1" >&2
  IFS= read -r a <&3 || return 1
  printf '%s' "$a" | tr -d '[:space:]'
}
# Calibration: the director types the count they chose; the test copy's first reading after the answer must show that
# count AND have drawn it live on the built-in display alone (a paused or undrawn reading never confirms). $1 log,
# $2 pid, $3 launch id, $4 seconds to wait for a fresh reading. Prints the count.
confirm_count() {
  local a shown since i sc sd
  while :; do
    a="$(ask "type the butterfly count you settled on (1-12), then Return: ")" || { echo "no answer (end of input)" >&2; return 1; }
    case "$a" in ''|*[!0-9]*) echo "  a number from 1 to 12, please" >&2; continue ;; esac
    if [ "$a" -lt 1 ] || [ "$a" -gt 12 ]; then echo "  a number from 1 to 12, please" >&2; continue; fi
    since="$(utc)"; shown=""
    for i in $(seq 1 "$4"); do
      shown="$(calibration_after "$1" "$2" "$3" "$since")"; [ -n "$shown" ] && break
      [ -n "$CONFIRM_FIXTURE" ] || sleep 1
    done
    [ -n "$shown" ] || { echo "the test copy logged no reading after your answer" >&2; return 1; }
    read -r sc sd <<<"$shown"
    if [ "$sc" = "$a" ] && [ "$sd" = drew ]; then echo "$since" >"$RUN/answered"; echo "$a"; return 0; fi
    if [ "$sc" = "$a" ]; then
      echo "  the test copy shows $a but did not draw it live on the built-in display alone (paused or covered?): resume it, then type $a again" >&2
      continue
    fi
    echo "  the test copy shows $sc, not $a: set it in Settings (or type $sc)" >&2
  done
}
# Calibration's last check: the readings from the director's answer ($4, a UTC stamp) to $6 (default now), at least
# two, waited for up to $5 s. Only these count: the director was in the test copy's Settings and menus before the
# answer, and the count they settled on is what must have drawn on the built-in display alone. Prints check_readings'
# result. $1 log, $2 pid, $3 launch id.
calibration_final() {
  local i out n
  for i in $(seq 1 "$5"); do
    out="$(check_readings "$1" "$2" "$3" "$4" "${6:-$(utc)}" calibrate 30 meadow "")"
    n="$(printf '%s' "$out" | tail -1 | sed -n 's/^OK \([0-9]*\) readings.*/\1/p')"
    readings_ok "$out" && [ "${n:-0}" -ge 2 ] && break
    [ -n "$CONFIRM_FIXTURE" ] || sleep 1
  done
  if readings_ok "$out" && [ "${n:-0}" -lt 2 ]; then echo "INVALID only ${n:-0} reading(s) after the answer in $5 s"; return 0; fi
  printf '%s\n' "$out"
}
# Preview: the director types "seen" (or "no"). Anything else asks again.
confirm_seen() {
  local a
  while :; do
    a="$(ask "type seen once you have seen the card (or no), then Return: ")" || { echo "no answer (end of input)" >&2; return 1; }
    case "$a" in seen) return 0 ;; no) echo "not seen" >&2; return 1 ;; *) echo "  seen or no, please" >&2 ;; esac
  done
}

# ---- selftest (dry): the parsers on canned input; touches nothing outside its scratch ----

if [ "$MODE" = selftest ]; then
  RUN="$FOLDER/selftest"
  rm -rf "$RUN"; mkdir -p "$RUN"
  set +e
  fails=0
  expect() { # $1 description, $2 got, $3 wanted (a glob)
    # shellcheck disable=SC2053
    if [[ "$2" == $3 ]]; then echo "ok    $1: $(printf '%s' "$2" | tail -1)"; else echo "FAIL  $1: got '$2', wanted $3"; fails=$((fails + 1)); fi
  }
  topfile() { # $1 file, then rows per sample ("|" between rows); each sample gets the header block
    local f="$1" sample row; shift
    : >"$f"
    for sample in "$@"; do
      printf 'Processes: 700 total, 3 running\n2026/11/21 10:00:00\nLoad Avg: 2.65, 2.74, 2.81\n\nPID    %%CPU MEM  \n' >>"$f"
      IFS='|' read -r -a rows <<<"$sample"
      for row in "${rows[@]}"; do [ -n "$row" ] && echo "$row" >>"$f"; done
    done
  }
  T="$RUN/top.txt"
  topfile "$T" "412    90.0 800M|501    50.0 100M" "412    20.0 854M |501    10.0 1616K" "501    12.0 120M+|412    30.0 800M"
  expect "full series" "$(parse_top "$T" 501 412 3)" "11.00 25.00 60.8 120.0"
  expect "short series" "$(parse_top "$T" 501 412 4)" "INVALID 3 of 4 samples"
  topfile "$T" "412 90.0 800M|501 50.0 100M" "501 10.0 100M" "412 30.0 800M|501 12.0 120M"
  expect "missing WindowServer row" "$(parse_top "$T" 501 412 3)" "INVALID sample 2 has no WindowServer row"
  topfile "$T" "412 90.0 800M|501 50.0 100M" "412 20.0 800M|501 10.0 100M" "412 30.0 800M|777 12.0 120M"
  expect "another process instead of the test copy" "$(parse_top "$T" 501 412 3)" "INVALID sample 3 has a row for pid 777*"
  topfile "$T" "412 90.0 800M|501 50.0 100M" "412 20.0 800M|501 1O.0 100M" "412 30.0 800M|501 12.0 120M"
  expect "malformed CPU" "$(parse_top "$T" 501 412 3)" "INVALID sample 2 has a malformed row*"
  topfile "$T" "412 90.0 800M|501 50.0 100M" "412 20.0 800M|501 10.0 lots" "412 30.0 800M|501 12.0 120M"
  expect "malformed memory" "$(parse_top "$T" 501 412 3)" "INVALID sample 2 has a malformed row*"
  topfile "$T" "412 90.0 800M|501 50.0 100M" "412 20.0 800M|501 10.0 100M|501 11.0 100M" "412 30.0 800M|501 12.0 120M"
  expect "duplicate row" "$(parse_top "$T" 501 412 3)" "INVALID sample 2 has pid 501 twice"
  topfile "$T" "412 90.0 800M|501 50.0 100M" "412 20.0 800M|501 10.0" "412 30.0 800M|501 12.0 120M"
  expect "truncated row" "$(parse_top "$T" 501 412 3)" "INVALID sample 2 has a malformed row*"
  topfile "$T" "412 90.0 800M|501 50.0 100M" "412 20.0 800M|501 10.0 100M" "412 30.0 800M|501 12.0 120M"
  printf 'Processes: 700 total\n\nPID    %%CPU MEM\n412 1.0 1M\n' >>"$T"
  expect "an extra sample" "$(parse_top "$T" 501 412 3)" "INVALID 4 of 3 samples"
  printf 'Processes: 700 total\nPID    %%CPU MEM\n412 90.0 800M\nProcesses: 700 total\n412 20.0 800M\n' >"$T"
  expect "a sample with no column header" "$(parse_top "$T" "" 412 2)" "INVALID sample 2 has no column header"
  topfile "$T" "412 90.0 800M" "412 20.0 800M" "412 30.0 1.5G"
  expect "baseline (WindowServer only)" "$(parse_top "$T" "" 412 3)" "0.00 25.00 0.0 0.0"

  AC="$(printf "Now drawing from 'AC Power'\n -InternalBattery-0 (id=1)\t80%%; AC attached; not charging present: true")"
  BAT="$(printf "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=1)\t80%%; discharging; 5:00 remaining present: true")"
  G0="$(printf 'System-wide power settings:\n SleepDisabled\t\t0\nCurrently in use:\n standby              1\n powermode            0\n womp                 1')"
  G1="$(printf 'System-wide power settings:\nCurrently in use:\n standby              1\n powermode            1\n')"
  GOLD="$(printf 'Currently in use:\n lowpowermode         1\n powermode            0\n')"
  GNONE="$(printf 'Currently in use:\n standby              1\n')"
  expect "power: plugged in, Low Power off" "$(power_line "$AC" "$G0")" "ac=1 lowpower=0"
  expect "power: on battery" "$(power_line "$BAT" "$G0")" "ac=0 lowpower=0"
  expect "power: Low Power Mode (powermode 1)" "$(power_line "$AC" "$G1")" "ac=1 lowpower=1"
  expect "power: Low Power Mode (lowpowermode 1)" "$(power_line "$AC" "$GOLD")" "ac=1 lowpower=1"
  expect "power: unknown" "$(power_line "$AC" "$GNONE")" "ac=1 lowpower=?"
  G2="$(printf 'Currently in use:\n standby              1\n powermode            2\n')"
  GODD="$(printf 'Currently in use:\n lowpowermode         x\n')"
  UPS="$(printf "Now drawing from 'UPS Power'\n")"
  expect "power: an unknown powermode value is unknown, not off" "$(power_line "$AC" "$G2")" "ac=1 lowpower=?"
  expect "power: an unknown lowpowermode value is unknown" "$(power_line "$AC" "$GODD")" "ac=1 lowpower=?"
  expect "power: an unknown source is unknown, not battery" "$(power_line "$UPS" "$G0")" "ac=? lowpower=0"
  expect "power: no pmset output at all" "$(power_line "" "")" "ac=? lowpower=?"
  P="$RUN/power.txt"
  # A trace from 10:00:00 to 10:01:00, a reading every 5 s from 10:00:01 (stamps $3 onwards override the values).
  ptrace() { local i; : >"$P"; for i in $(seq 0 $(($1 - 1))); do echo "2026-11-21T10:0$(((1 + i * 5) / 60)):$(printf %02d $(((1 + i * 5) % 60)))Z $2" >>"$P"; done; }
  PF=2026-11-21T10:00:00Z; PT=2026-11-21T10:01:00Z
  ptrace 12 "ac=1 lowpower=0"; expect "power trace: complete" "$(check_power "$P" $PF $PT 60)" "plugged in, Low Power Mode off (12 readings)"
  ptrace 3 "ac=1 lowpower=0"; expect "power trace: short" "$(check_power "$P" $PF $PT 60)" "INVALID 3 power readings for 60 s"
  ptrace 11 "ac=1 lowpower=0"; echo "2026-11-21T10:00:59Z ac=0 lowpower=0" >>"$P"
  expect "power trace: unplugged once" "$(check_power "$P" $PF $PT 60)" "INVALID on battery at*"
  ptrace 11 "ac=1 lowpower=0"; echo "2026-11-21T10:00:59Z ac=1 lowpower=1" >>"$P"
  expect "power trace: Low Power once" "$(check_power "$P" $PF $PT 60)" "INVALID Low Power Mode on at*"
  ptrace 12 "ac=1 lowpower=?"; expect "power trace: unknown" "$(check_power "$P" $PF $PT 60)" "INVALID Low Power Mode unknown*"
  ptrace 12 "ac=? lowpower=0"; expect "power trace: source unknown" "$(check_power "$P" $PF $PT 60)" "INVALID power source unknown*"
  : >"$P"; for i in $(seq 1 12); do echo "2026-11-21T10:00:30Z ac=1 lowpower=0" >>"$P"; done
  expect "power trace: twelve identical rows" "$(check_power "$P" $PF $PT 60)" "INVALID power readings out of order or repeated*"
  : >"$P"; for i in $(seq 1 12); do echo "0Z ac=1 lowpower=0" >>"$P"; done
  expect "power trace: zero stamps" "$(check_power "$P" $PF $PT 60)" "INVALID a power reading with a malformed stamp*"
  ptrace 12 "ac=1 lowpower=0"; sed -i '' '6s/^2026-11-21T10:00:26Z/2026-11-21T10:00:21Z/' "$P"
  expect "power trace: a stamp going back" "$(check_power "$P" $PF $PT 60)" "INVALID power readings out of order*"
  ptrace 12 "ac=1 lowpower=0"; echo "2026-11-21T10:05:00Z ac=1 lowpower=0" >>"$P"
  expect "power trace: a stamp after the window" "$(check_power "$P" $PF $PT 60)" "INVALID a power reading at 2026-11-21T10:05:00Z, outside*"
  : >"$P"; for i in $(seq 0 11); do echo "2026-11-21T10:00:$(printf %02d $((i * 2)))Z ac=1 lowpower=0" >>"$P"; done
  expect "power trace: twelve rows bunched at the start" "$(check_power "$P" $PF $PT 60)" "INVALID the power readings do not cover*"
  ptrace 12 "ac=1 lowpower=0"; expect "power trace: a malformed window" "$(check_power "$P" 0Z $PT 60)" "INVALID the sampled window is not two UTC stamps"

  L="$RUN/log.txt"
  LID=0a1b2c3d4e5f6789
  rd() { # $1 stamp, then field overrides as k=v ...; prints one reading in EnergyLog.reading's shape
    local s="$1"; shift
    local pid=501 launch=$LID mode=live30 setting=30 habitat=meadow count=7 attached=2 drawn=2 displays=1:b:29.8,2:e:29.6 lowPower=false battery=false thermal=nominal kv
    for kv in "$@"; do eval "${kv%%=*}=\"\${kv#*=}\""; done
    echo "$s energy: pid=$pid launch=$launch mode=$mode setting=$setting habitat=$habitat count=$count attached=$attached drawn=$drawn displays=$displays lowPower=$lowPower battery=$battery thermal=$thermal"
  }
  minute() { local i; for i in $(seq 0 12); do rd "2026-11-21T10:$(printf %02d $((i * 5 / 60))):$(printf %02d $((i * 5 % 60)))Z" "$@"; done; }
  # The exact line OceanChecks pins (identityEnergyLogShapes):
  expect "the reading shape" "$(rd 2026-11-21T10:00:00Z)" "2026-11-21T10:00:00Z energy: pid=501 launch=0a1b2c3d4e5f6789 mode=live30 setting=30 habitat=meadow count=7 attached=2 drawn=2 displays=1:b:29.8,2:e:29.6 lowPower=false battery=false thermal=nominal"
  F=2026-11-21T10:00:00Z; TO=2026-11-21T10:01:00Z
  minute >"$L"
  out="$(check_readings "$L" 501 $LID $F $TO measure 30 meadow 7)"
  expect "measure: a full minute, two displays" "$out" "*display 1 (built-in): 29.8 fps mean*display 2 (external): 29.6 fps mean*OK 13 readings, 2 displays, count=7"
  minute >"$L"; echo "2026-11-21T10:00:30Z energy: pid=501 launch=$LID mode=live30" >>"$L"
  expect "measure: a truncated reading" "$(check_readings "$L" 501 $LID $F $TO measure 30 meadow 7)" "INVALID a reading with 3 fields*"
  { rd 2026-11-21T10:00:00Z; rd 2026-11-21T10:00:05Z; rd 2026-11-21T10:00:05Z; } >"$L"
  expect "measure: duplicate readings" "$(check_readings "$L" 501 $LID $F $TO measure 30 meadow 7)" "INVALID two readings at*"
  rd 2026-11-21T10:00:30Z >"$L"
  expect "measure: one reading for a minute" "$(check_readings "$L" 501 $LID $F $TO measure 30 meadow 7)" "INVALID the readings do not cover the window"
  { rd 2026-11-21T10:00:00Z; rd 2026-11-21T10:00:20Z; } >"$L"
  expect "measure: a gap" "$(check_readings "$L" 501 $LID $F $TO measure 30 meadow 7)" "INVALID no reading for 20 s*"
  minute >"$L"; sed -i '' '5s/ thermal=nominal$//' "$L"
  expect "measure: a reading missing a field" "$(check_readings "$L" 501 $LID $F $TO measure 30 meadow 7)" "INVALID a reading with 11 fields*"
  minute >"$L"; sed -i '' '5s/count=7/count=/' "$L"
  expect "measure: an empty field" "$(check_readings "$L" 501 $LID $F $TO measure 30 meadow 7)" "INVALID a reading with a malformed field*"
  minute >"$L"; sed -i '' '5s/count=7 attached/attached=2 count/' "$L"
  expect "measure: fields out of order" "$(check_readings "$L" 501 $LID $F $TO measure 30 meadow 7)" "INVALID a reading out of shape*"
  minute battery=true >"$L"
  expect "measure: on battery" "$(check_readings "$L" 501 $LID $F $TO measure 30 meadow 7)" "INVALID on battery at*"
  minute lowPower=true >"$L"
  expect "measure: Low Power Mode" "$(check_readings "$L" 501 $LID $F $TO measure 30 meadow 7)" "INVALID Low Power Mode on at*"
  minute mode=live15 >"$L"
  expect "measure: held at 15 (heat)" "$(check_readings "$L" 501 $LID $F $TO measure 30 meadow 7)" "INVALID mode live15*"
  minute drawn=1 displays=1:b:29.8 >"$L"
  expect "measure: one of two displays drawn" "$(check_readings "$L" 501 $LID $F $TO measure 30 meadow 7)" "INVALID 1 of 2 displays drawn*"
  minute displays=1:b:29.8 >"$L"
  expect "measure: drawn and the list disagree" "$(check_readings "$L" 501 $LID $F $TO measure 30 meadow 7)" "INVALID drawn=2 but 1 displays listed*"
  minute displays=1:b:29.8,2:e:21.0 >"$L"
  expect "measure: one display slow (covered)" "$(check_readings "$L" 501 $LID $F $TO measure 30 meadow 7)" "INVALID display 2 at 21.0 fps*"
  minute displays=1:b:29.8,1:e:29.6 >"$L"
  expect "measure: a display twice" "$(check_readings "$L" 501 $LID $F $TO measure 30 meadow 7)" "INVALID display 1 twice*"
  minute displays=1:b:29.8,2:e:29.6x >"$L"
  expect "measure: a malformed display entry" "$(check_readings "$L" 501 $LID $F $TO measure 30 meadow 7)" "INVALID a malformed display entry*"
  minute >"$L"; sed -i '' '7s/attached=2 drawn=2 displays=1:b:29.8,2:e:29.6/attached=1 drawn=1 displays=1:b:29.8/' "$L"
  expect "measure: a display detached mid-run" "$(check_readings "$L" 501 $LID $F $TO measure 30 meadow 7)" "INVALID the displays changed*"
  minute count=5 >"$L"
  expect "measure: another count" "$(check_readings "$L" 501 $LID $F $TO measure 30 meadow 7)" "INVALID count 5*"
  minute pid=777 >"$L"
  expect "measure: another process's readings" "$(check_readings "$L" 501 $LID $F $TO measure 30 meadow 7)" "INVALID no readings in the window"
  minute launch=ffffffffffffffff >"$L"
  expect "measure: the same pid, another launch's readings" "$(check_readings "$L" 501 $LID $F $TO measure 30 meadow 7)" "INVALID no readings in the window"
  minute launch=none >"$L"
  expect "measure: readings with no launch id (a probe, a hand launch)" "$(check_readings "$L" 501 $LID $F $TO measure 30 meadow 7)" "INVALID no readings in the window"
  minute >"$L"; sed -i '' '7s/displays=1:b:29.8,2:e:29.6/displays=1:b:29.8,3:e:29.6/' "$L"
  expect "measure: a display swapped mid-run (same count)" "$(check_readings "$L" 501 $LID $F $TO measure 30 meadow 7)" "INVALID the displays changed during the run at*"
  minute displays=2:e:29.6,1:b:29.8 >"$L"
  expect "measure: the same displays listed in another order" "$(check_readings "$L" 501 $LID $F $TO measure 30 meadow 7)" "*OK 13 readings, 2 displays*"
  minute >"$L"
  expect "measure: web asked, meadow logged" "$(check_readings "$L" 501 $LID $F $TO measure 30 web "")" "INVALID set to meadow at 30 fps*"
  minute attached=1 drawn=1 displays=1:b:29.9 >"$L"
  expect "calibrate: the built-in alone" "$(check_readings "$L" 501 $LID $F $TO calibrate 30 meadow "")" "*display 1 (built-in)*OK 13 readings, 1 displays, count=7"
  minute attached=2 drawn=1 displays=2:e:29.9 >"$L"
  expect "calibrate: an external drawn" "$(check_readings "$L" 501 $LID $F $TO calibrate 30 meadow "")" "INVALID not the built-in display alone*"
  minute attached=1 drawn=0 displays=none >"$L"
  expect "calibrate: nothing drawn (lid closed)" "$(check_readings "$L" 501 $LID $F $TO calibrate 30 meadow "")" "INVALID not the built-in display alone*"
  minute attached=1 drawn=1 displays=1:b:0.0 mode=paused >"$L"
  expect "calibrate: no frame drawn" "$(check_readings "$L" 501 $LID $F $TO calibrate 30 meadow "")" "INVALID no built-in display drew a frame"
  minute >"$L"
  expect "preview: a built-in display drawn" "$(check_readings "$L" 501 $LID $F $TO preview 30 meadow "")" "*OK 13 readings*"
  minute displays=1:e:29.8,2:e:29.6 >"$L"
  expect "preview: no built-in display" "$(check_readings "$L" 501 $LID $F $TO preview 30 meadow "")" "INVALID no built-in display drew a frame"

  # Typed confirmations, from a file standing in for the terminal (fd 3); the log answers at once.
  CONFIRM_FIXTURE=1
  rd 2099-01-01T00:00:00Z attached=1 drawn=1 displays=1:b:29.9 count=9 >"$L"
  out="$(printf '9\n' | { exec 3<&0; confirm_count "$L" 501 $LID 2 2>/dev/null; })"; rc=$?
  expect "calibrate: the count typed is the count shown" "$rc $out" "0 9"
  out="$(printf 'nine\n13\n7\n9\n' | { exec 3<&0; confirm_count "$L" 501 $LID 2 2>&1; })"; rc=$?
  expect "calibrate: words, out of range and a wrong count ask again" "$rc $(echo "$out" | grep -c 'please\|not 7')" "0 3"
  out="$(printf '' | { exec 3<&0; confirm_count "$L" 501 $LID 2 2>/dev/null; })"; rc=$?
  expect "calibrate: end of input is no answer" "$rc" "1"
  out="$(printf '7\n' | { exec 3<&0; confirm_count "$L" 501 $LID 2 2>/dev/null; })"; rc=$?
  expect "calibrate: a wrong count then end of input fails" "$rc" "1"
  rd 2000-01-01T00:00:00Z count=9 >"$L"
  out="$(printf '9\n' | { exec 3<&0; confirm_count "$L" 501 $LID 2 2>&1; })"; rc=$?
  expect "calibrate: no reading after the answer fails" "$rc $out" "1 *no reading after*"
  # The re-check's case: it drew at 7, then shows 9 while paused. 9 is never confirmed by a paused reading.
  { rd 2000-01-01T00:00:00Z attached=1 drawn=1 displays=1:b:29.9 count=7; rd 2099-01-01T00:00:00Z attached=1 drawn=1 displays=1:b:0.0 mode=paused count=9; } >"$L"
  out="$(printf '9\n' | { exec 3<&0; confirm_count "$L" 501 $LID 2 2>&1; })"; rc=$?
  expect "calibrate: a fresh but paused reading at the count does not confirm" "$rc $(echo "$out" | grep -c 'did not draw it live')" "1 1"
  rd 2099-01-01T00:00:00Z attached=2 drawn=1 displays=2:e:29.9 count=9 >"$L"
  out="$(printf '9\n' | { exec 3<&0; confirm_count "$L" 501 $LID 2 2>/dev/null; })"; rc=$?
  expect "calibrate: a reading drawn on an external display does not confirm" "$rc" "1"
  rd 2099-01-01T00:00:00Z attached=1 drawn=0 displays=none mode=still count=9 >"$L"
  out="$(printf '9\n' | { exec 3<&0; confirm_count "$L" 501 $LID 2 2>/dev/null; })"; rc=$?
  expect "calibrate: a reading with nothing drawn does not confirm" "$rc" "1"
  rd 2099-01-01T00:00:00Z attached=1 drawn=1 displays=1:b:29.9 count=9 launch=ffffffffffffffff >"$L"
  out="$(printf '9\n' | { exec 3<&0; confirm_count "$L" 501 $LID 2 2>&1; })"; rc=$?
  expect "calibrate: another launch's reading does not confirm" "$rc $out" "1 *no reading after*"
  out="$(printf 'yes\nseen\n' | { exec 3<&0; confirm_seen 2>/dev/null; })"; rc=$?
  expect "preview: seen (after a wrong word)" "$rc" "0"
  out="$(printf '' | { exec 3<&0; confirm_seen 2>/dev/null; })"; rc=$?
  expect "preview: end of input is not seen" "$rc" "1"
  out="$(printf 'no\n' | { exec 3<&0; confirm_seen 2>/dev/null; })"; rc=$?
  expect "preview: no" "$rc" "1"
  printf '2026-11-21T10:00:01Z energy-plan: pid=501 launch=%s greeting=quiet builtInOnly=0\n2026-11-21T10:00:02Z energy-card: pid=501 launch=%s shown\n' "$LID" "$LID" >"$L"
  expect "the plan line" "$(plan_of "$L" 501 $LID)" "greeting=quiet builtInOnly=0"
  expect "no plan line for another pid" "$(plan_of "$L" 777 $LID)" ""
  expect "no plan line for another launch (a reused pid)" "$(plan_of "$L" 501 ffffffffffffffff)" ""
  printf '2026-11-21T10:00:01Z energy-plan: pid=501 launch=none greeting=preview builtInOnly=0\n' >"$L"
  expect "a plan with no launch id never counts for a launch" "$(plan_of "$L" 501 $LID)" ""
  printf '2026-11-21T10:00:02Z energy-card: pid=501 shown\n2026-11-21T10:00:03Z energy-card: pid=501 launch=none shown\n2026-11-21T10:00:04Z energy-card: pid=501 launch=ffffffffffffffff shown\n' >"$L"
  card_shown "$L" 501 $LID; expect "an old, unbound or other launch's card line does not count" "$?" "1"
  printf '2026-11-21T10:00:05Z energy-card: pid=501 launch=%s shown\n' "$LID" >>"$L"
  card_shown "$L" 501 $LID; expect "this launch's card line counts" "$?" "0"
  # The card's drawn check (EnergyLog.cardDrawn, cardClosed; OceanChecks pins the shapes).
  printf '2026-11-21T10:00:05Z energy-card: pid=501 launch=%s shown\n2026-11-21T10:00:07Z energy-card: pid=501 launch=%s drawn=0.977 size=460x333\n' "$LID" "$LID" >"$L"
  expect "card: drawn" "$(card_drawn_check "$L" 501 $LID 2)" "OK 0.977 460x333"
  printf '2026-11-21T10:00:05Z energy-card: pid=501 launch=%s shown\n2026-11-21T10:00:07Z energy-card: pid=501 launch=%s drawn=0.000 size=460x333\n' "$LID" "$LID" >"$L"
  expect "card: a drawn share of zero fails the preview" "$(card_drawn_check "$L" 501 $LID 2)" "FAIL the card drew 0.000 of its window*empty"
  printf '2026-11-21T10:00:07Z energy-card: pid=501 launch=%s drawn=0.012 size=460x333\n' "$LID" >"$L"
  expect "card: a drawn share near zero fails the preview" "$(card_drawn_check "$L" 501 $LID 2)" "FAIL the card drew 0.012*"
  printf '2026-11-21T10:00:05Z energy-card: pid=501 launch=%s shown\n' "$LID" >"$L"
  expect "card: no drawn line fails the preview" "$(card_drawn_check "$L" 501 $LID 2)" "FAIL the card logged no drawn check in 2 s"
  printf '2026-11-21T10:00:07Z energy-card: pid=501 launch=ffffffffffffffff drawn=0.977 size=460x333\n2026-11-21T10:00:07Z energy-card: pid=501 launch=none drawn=0.977 size=460x333\n' >"$L"
  expect "card: another launch's or a probe's drawn line does not count" "$(card_drawn_check "$L" 501 $LID 2)" "FAIL the card logged no drawn check*"
  printf '2026-11-21T10:00:07Z energy-card: pid=501 launch=%s drawn=0.98 size=460x333\n2026-11-21T10:00:07Z energy-card: pid=501 launch=%s drawn=0.977\n' "$LID" "$LID" >"$L"
  expect "card: a malformed drawn line does not count" "$(card_drawn_check "$L" 501 $LID 2)" "FAIL the card logged no drawn check*"
  printf '2026-11-21T10:00:05Z energy-card: pid=501 launch=%s shown\n2026-11-21T10:00:06Z energy-card: pid=501 launch=%s closed=timeout after=20s\n' "$LID" "$LID" >"$L"
  expect "card: closed before its drawn check fails the preview" "$(card_drawn_check "$L" 501 $LID 2)" "FAIL the card closed (timeout, 20 s after it was shown)*"
  expect "card: the close line" "$(card_closed "$L" 501 $LID)" "timeout 20"
  expect "card: another launch's close line does not count" "$(card_closed "$L" 501 ffffffffffffffff)" ""
  # Calibration's last check covers the readings from the director's answer on (a menu was open before it).
  { for s in 00 05 10 15 20 34 39 44 49; do rd "2026-11-21T10:00:${s}Z" attached=1 drawn=1 displays=1:b:29.9; done; } >"$L"
  expect "calibrate: a 14 s gap before the answer passes" "$(calibration_final "$L" 501 $LID 2026-11-21T10:00:36Z 2 2026-11-21T10:00:50Z)" "*OK 3 readings, 1 displays, count=7"
  expect "calibrate: the same gap after the answer fails" "$(calibration_final "$L" 501 $LID 2026-11-21T10:00:12Z 2 2026-11-21T10:00:50Z)" "INVALID no reading for 14 s*"
  { for s in 00 05 10 15 20 25; do rd "2026-11-21T10:00:${s}Z" attached=1 drawn=1 displays=1:b:29.9; done; rd 2026-11-21T10:00:30Z attached=2 drawn=1 displays=2:e:29.9; } >"$L"
  expect "calibrate: after the answer, an external display drawn fails" "$(calibration_final "$L" 501 $LID 2026-11-21T10:00:22Z 2 2026-11-21T10:00:40Z)" "INVALID not the built-in display alone*"
  rd 2026-11-21T10:00:40Z attached=1 drawn=1 displays=1:b:29.9 >"$L"
  expect "calibrate: one reading after the answer is too few" "$(calibration_final "$L" 501 $LID 2026-11-21T10:00:36Z 2 2026-11-21T10:00:50Z)" "INVALID only 1 reading(s) after the answer*"
  rd 2026-11-21T10:00:40Z attached=1 drawn=1 displays=1:b:29.9 count=9 >"$L"
  out="$(printf '9\n' | { exec 3<&0; confirm_count "$L" 501 $LID 2 2>/dev/null; })"
  expect "calibrate: a confirmed answer records its time" "$(cat "$RUN/answered" 2>/dev/null)" "20[0-9][0-9]-*Z"
  sampled_ok "11.00 25.00 60.8 120.0"; expect "a sample line passes" "$?" "0"
  sampled_ok ""; expect "an empty sample (a parser failure) does not" "$?" "1"
  sampled_ok "INVALID 3 of 4 samples"; expect "an invalid sample does not" "$?" "1"
  power_ok ""; expect "an empty power result does not pass" "$?" "1"
  readings_ok ""; expect "empty readings do not pass" "$?" "1"
  readings_ok "$(printf '  display 1 (built-in): 29.8 fps mean\nOK 13 readings, 1 displays, count=7')"; expect "OK readings pass" "$?" "0"
  rm -rf "$RUN"
  echo "selftest: $fails failed"
  [ "$fails" = 0 ]
  exit
fi

# ---- status: changes nothing ----

if [ "$MODE" = status ]; then
  echo "energy-test copy: $APP ($( [ -d "$APP" ] && plist_id "$APP" || echo missing))"
  echo "test folder: $FOLDER ($( [ -d "$FOLDER" ] && echo present || echo absent))"
  echo "lock: $(lock_state)$( [ -d "$LOCK" ] && echo " ($(lock_owner))")"
  for p in $(test_candidates); do
    if is_our_test_copy "$p"; then echo "test copy running: pid $p (this checkout's)"; else echo "test copy running: pid $p (NOT this checkout's: $(exe_path "$p"))"; fi
  done
  [ -n "$(test_candidates)" ] || echo "test copy running: none"
  R="$(real_apps_running)"
  if [ -n "$R" ]; then echo "ASCII Animals / ASCII Sharks running (a live run refuses until they are quit):"; echo "$R" | sed 's/^/  pid /'
  else echo "ASCII Animals / ASCII Sharks running: none"; fi
  if domain_absent; then echo "test domain $DOMAIN: absent"; else echo "test domain $DOMAIN: present (recover deletes it)"; fi
  if [ -d "$RUN" ]; then echo "scratch left by a run: $RUN (recover removes it)"; fi
  echo "power now: $(power_now)"
  for d in "$HOME/Library/Caches/$TEST_ID" "$HOME/Library/HTTPStorages/$TEST_ID" "$HOME/Library/Saved Application State/$TEST_ID.savedState"; do
    if [ -e "$d" ]; then echo "macOS's own folder for the test ID (holds nothing of the director's): ${d/#$HOME/~}"; fi
  done
  exit 0
fi

# ---- From here: one run at a time ----

take_lock "$( [ "$MODE" = recover ] && echo 1 || echo 0 )"
rm -rf "$RUN"; mkdir -p "$RUN"
TOUCHED=0; LAUNCHED=0; TEST_PID=""; TEST_START=""; CLEANING=0

# ---- Preflight: the test bundle is what it says; nothing of the director's is running ----

check_bundle() {
  [ -d "$APP" ] || die "missing $APP (run Tools/build.sh --test)"
  local id; id="$(plist_id "$APP")"
  refuse_real "$id"
  [ "$id" = "$TEST_ID" ] || die "refused: $APP has bundle ID '$id', not $TEST_ID"
  [ "$(plist_exe "$APP")" = "$TEST_EXE" ] && [ -x "$TEST_EXEC" ] || die "refused: $APP's executable is not $TEST_EXE"
  codesign --verify --strict "$APP" 2>/dev/null || die "$APP does not verify (rebuild with Tools/build.sh --test)"
  REAL_TEST_EXEC="$(real_test_exec)"
  case "$REAL_TEST_EXEC" in "$ROOT"/build/*) ;; *) die "refused: the test executable resolves outside build/ ($REAL_TEST_EXEC)" ;; esac
}
# Refuses (or, dry, says it would) while ASCII Animals or ASCII Sharks runs, or any test copy from anywhere.
preflight_processes() { # $1: "refuse" or "report"
  local r t p
  r="$(real_apps_running)"
  t="$(test_candidates)"
  if [ -n "$r" ]; then
    echo "$r" | sed 's/^/  running: pid /' >&2
    [ "$1" = report ] && { echo "(dry) a live run would refuse here: $QUIT_MSG"; } || die "$QUIT_MSG (nothing was changed)"
  fi
  if [ -n "$t" ]; then
    for p in $t; do echo "  test copy already running: pid $p ($(exe_path "$p"))" >&2; done
    [ "$1" = report ] && echo "(dry) a live run would refuse here: a test copy is already running" \
      || die "a test copy is already running; quit it from its menu bar icon (\"$TEST_NAME: energy test copy\") or run $0 recover (nothing was changed)"
  fi
  return 0
}

# ---- Cleanup: on exit, error or Ctrl-C; protected from a second Ctrl-C; its failure is the run's failure ----

# SIGTERM (it quits normally on it), then SIGKILL; each signal only after the identity is checked again.
quit_test_copy() { # $1 pid, $2 start time
  local pid="$1" start="$2" i
  is_our_test_copy "$pid" "$start" || { alive "$pid" && echo "WARNING: pid $pid is no longer this checkout's test copy; not signalled" >&2; return 0; }
  kill -TERM "$pid" 2>/dev/null || true
  for i in $(seq 1 15); do alive "$pid" && [ "$(proc_start "$pid")" = "$start" ] || return 0; sleep 1; done
  is_our_test_copy "$pid" "$start" || return 0
  echo "the test copy did not quit in 15 s; SIGKILL" >&2
  kill -KILL "$pid" 2>/dev/null || true
  for i in 1 2 3 4 5; do alive "$pid" && [ "$(proc_start "$pid")" = "$start" ] || return 0; sleep 1; done
  return 1
}
quit_our_test_copies() { # every test copy of this checkout, verified one by one; 0 when none is left
  local p ok=0
  [ -z "$TEST_PID" ] || quit_test_copy "$TEST_PID" "$TEST_START" || ok=1
  for p in $(test_candidates); do
    if is_our_test_copy "$p"; then quit_test_copy "$p" "$(proc_start "$p")" || ok=1; fi
  done
  for p in $(test_candidates); do
    if is_our_test_copy "$p"; then echo "WARNING: the test copy is still running (pid $p)" >&2; ok=1
    else echo "WARNING: a test copy not from this checkout is running (pid $p, $(exe_path "$p")); not signalled. Quit it from its menu bar icon." >&2; ok=1; fi
  done
  return "$ok"
}

cleanup() {
  local rc=$? ok=1 i
  [ "$CLEANING" = 1 ] && return; CLEANING=1
  trap '' INT TERM HUP
  set +e
  { exec 3<&-; } 2>/dev/null   # closes the terminal answers; stderr stays, so every warning below is seen
  if [ "$DRY" != 1 ] && { [ "$LAUNCHED" = 1 ] || [ "$MODE" = recover ]; }; then
    # A launch still registering: give it time to appear, so it is not left behind.
    if [ "$LAUNCHED" = 1 ] && [ -z "$TEST_PID" ]; then
      for i in $(seq 1 20); do find_launched && break; sleep 1; done
    fi
    if quit_our_test_copies; then [ "$LAUNCHED" = 1 ] && echo "test copy quit"; else ok=0; fi
  fi
  if [ "$TOUCHED" = 1 ]; then
    if [ "$ok" = 1 ] && delete_domain; then
      echo "test domain $DOMAIN deleted (verified absent)"
    else
      echo "WARNING: test domain $DOMAIN not verified deleted; run: $0 recover" >&2; ok=0
    fi
  fi
  rm -rf "$RUN"
  release_lock
  [ "$ok" = 1 ] || { echo "energy.sh: cleanup incomplete (see the warnings); $0 status shows what is left" >&2; exit 1; }
  exit "$rc"
}
trap cleanup EXIT
trap 'echo "interrupted; cleaning up (Ctrl-C again is ignored until done)" >&2; exit 130' INT TERM
# The Terminal closed (HUP) or the reader of its output went away (PIPE): those kill a shell without its EXIT trap,
# so they become an ordinary exit too, and the cleanup above runs.
trap 'exit 129' HUP
trap '' PIPE

# ---- recover: a killed run's leftovers (never the director's apps) ----

if [ "$MODE" = recover ]; then
  TOUCHED=1
  [ "$DRY" = 1 ] || check_bundle
  if [ "$DRY" = 1 ]; then echo "recover (dry): deleting the test domain, clearing the scratch; no process is looked at or quit"
  else echo "recover: quitting this checkout's test copy (if running), deleting the test domain, clearing the scratch"; fi
  exit 0   # cleanup does it
fi

# ---- The test copy: launched with every flag set, found by identity, its plan checked ----

find_launched() { # sets TEST_PID and TEST_START when exactly one of this checkout's test copies runs
  local p found=""
  for p in $(test_candidates); do is_our_test_copy "$p" && found="$found $p"; done
  set -- $found
  [ $# = 1 ] || return 1
  TEST_PID="$1"; TEST_START="$(proc_start "$1")"
  [ -n "$TEST_START" ]
}
launch_test() { # $1 quiet, $2 preview, $3 built-in only (each 1 or 0); $4 the greeting the plan must show; $5 "bg":
                # opened in the background (open -g), so the director's app keeps the keyboard (and keeps the
                # screen in focus where it is) and they type their answer without a click
  local want plan i
  preflight_processes refuse
  LAUNCH_ID="$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
  [[ "$LAUNCH_ID" =~ ^[0-9a-f]{16}$ ]] || die "could not make a launch id"
  LAUNCHED=1
  LAUNCH_AT="$(utc)"
  # open runs with Ctrl-C ignored, so a launch is never half done; the trap runs once it returns.
  ( trap '' INT TERM
    exec open ${5:+-g} --env ASCII_ANIMALS_NO_HANDOVER=1 --env "ASCII_ANIMALS_ENERGY_LAUNCH=$LAUNCH_ID" --env "ASCII_ANIMALS_QUIET_LAUNCH=$1" \
      --env "ASCII_ANIMALS_PREVIEW_WHATSNEW=$2" --env "ASCII_ANIMALS_BUILTIN_DISPLAY_ONLY=$3" "$APP" ) \
    || die "could not open the test copy"
  for i in $(seq 1 20); do find_launched && break; sleep 1; done
  [ -n "$TEST_PID" ] || die "the test copy did not start (or more than one is running)"
  echo "test copy running (pid $TEST_PID, launch $LAUNCH_ID, $REAL_TEST_EXEC)"
  want="greeting=$4 builtInOnly=$3"
  for i in $(seq 1 15); do plan="$(plan_of "$APPLOG" "$TEST_PID" "$LAUNCH_ID")"; [ -n "$plan" ] && break; sleep 1; done
  [ "$plan" = "$want" ] || die "the test copy started as '${plan:-no plan logged for launch $LAUNCH_ID}', not '$want' -- stopped"
  echo "test copy plan: $plan"
}
still_ours() { is_our_test_copy "$TEST_PID" "$TEST_START" || die "the test copy (pid $TEST_PID) quit or changed during the run -- results invalid"; }
wait_for_reading() { # $1 kind; waits up to 15 s for a reading that passes it, from the launch on
  local i out
  for i in $(seq 1 15); do
    out="$(check_readings "$APPLOG" "$TEST_PID" "$LAUNCH_ID" "$LAUNCH_AT" "$(utc)" "$1" "$FPS" "${HABITAT:-meadow}" "")"
    readings_ok "$out" && return 0
    sleep 1
  done
  echo "$out" >&2
  return 1
}

# ---- Sampling: top for exact pids, the power state every 5 s alongside ----

# Any wallpaper app other than the test copy being measured ($1, or "" at the baseline): ASCII Animals, ASCII Sharks,
# another test copy. One line, or nothing.
others_running() {
  local t
  { real_apps_running; for t in $(test_candidates); do [ "$t" = "$1" ] || echo "$t test copy"; done; } | tr '\n' ';'
}
sample() { # $1 app pid or "", $2 WindowServer pid; prints parse_top's line (or "INVALID <why>"); the power trace goes
           # to $RUN/power.txt; a look every 3 s for another wallpaper app goes to $RUN/apps.txt
  local args=(-l "$((SECS + 1))" -s 1 -stats pid,cpu,mem -pid "$2") top_pid watch_pid
  [ -n "$1" ] && args+=(-pid "$1")
  : >"$RUN/power.txt"; : >"$RUN/apps.txt"
  top "${args[@]}" >"$RUN/top.txt" 2>/dev/null &
  top_pid=$!
  ( set +e; trap - EXIT
    while kill -0 "$top_pid" 2>/dev/null && kill -0 $$ 2>/dev/null; do
      seen="$(others_running "$1")"
      [ -z "$seen" ] || echo "$(utc) $seen" >>"$RUN/apps.txt"
      sleep 3
    done ) >/dev/null &
  watch_pid=$!
  while kill -0 "$top_pid" 2>/dev/null; do
    echo "$(utc) $(power_now)" >>"$RUN/power.txt"
    sleep 5
  done
  wait "$top_pid" || die "top failed"
  wait "$watch_pid" 2>/dev/null || true
  if [ -s "$RUN/apps.txt" ]; then echo "INVALID a wallpaper app was running during the sampling: $(head -1 "$RUN/apps.txt")"; return 0; fi
  parse_top "$RUN/top.txt" "$1" "$2" "$((SECS + 1))"
}
window_server() {
  local p; p="$(pgrep -x WindowServer || true)"
  [ "$(printf '%s\n' "$p" | grep -c .)" = 1 ] || die "expected one WindowServer, found: $p"
  echo "$p"
}
record() { echo "$(utc) $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo '?') $*" >>"$RESULTS"; }

# ---- The runs ----

if [ "$DRY" = 1 ]; then
  echo "dry run ($MODE): the lock, the test domain and read-only checks; nothing launched, quit or sampled"
  preflight_processes report
  # The test copy's own domain is shared by every checkout: a dry run never deletes it under a running test copy.
  if [ "$DOMAIN" = "$TEST_ID" ] && [ -n "$(test_candidates)" ]; then
    die "a test copy is running, and it uses $DOMAIN; a dry run leaves it alone (use ENERGY_TEST_DOMAIN=$TEST_ID.<word>)"
  fi
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
    echo "(dry) count in the test domain: $(printf '%s' "$hex" | xxd -r -p | jq -r '.meadowCount // "none (the app default)"'); a live run takes the count from the test copy's reading and the director's typed answer"
  fi
  [ "$MODE" = preview ] && { domain_absent || die "the preview wrote to $DOMAIN"; echo "preview: the test domain stayed absent"; }
  exit 0
fi

check_bundle
preflight_processes refuse
TOUCHED=1
delete_domain || die "could not clear the test domain $DOMAIN"

case "$MODE" in
  baseline)
    WS="$(window_server)"
    echo "baseline: no wallpaper app; settling ${SETTLE}s, sampling WindowServer (pid $WS) ${SECS}s"
    sleep "$SETTLE"
    FROM="$(utc)"
    S="$(sample "" "$WS")"
    TO="$(utc)"
    sampled_ok "$S" || die "sampling: ${S#INVALID } -- results invalid, rerun"
    P="$(check_power "$RUN/power.txt" "$FROM" "$TO" "$SECS")"
    power_ok "$P" || die "power: ${P#INVALID } -- results invalid"
    [ -z "$(real_apps_running)$(test_candidates)" ] || die "a wallpaper app started during the baseline -- results invalid"
    read -r _ WSCPU _ _ <<<"$S"
    echo "baseline WindowServer mean CPU: ${WSCPU}%"
    echo "  power: $P"
    record "baseline ${SECS}s: WindowServer ${WSCPU}%; $P"
    ;;
  measure)
    write_settings
    launch_test 1 0 0 quiet
    WS="$(window_server)"
    echo "settling ${SETTLE}s, then sampling ${SECS}s"
    sleep "$SETTLE"
    FROM="$(utc)"
    S="$(sample "$TEST_PID" "$WS")"
    TO="$(utc)"
    sampled_ok "$S" || die "sampling: ${S#INVALID } -- results invalid, rerun"
    still_ours
    [ -z "$(real_apps_running)" ] || die "ASCII Animals or ASCII Sharks started during the run -- results invalid"
    sleep 1   # the log is written off the main thread
    R="$(check_readings "$APPLOG" "$TEST_PID" "$LAUNCH_ID" "$FROM" "$TO" measure "$FPS" "$HABITAT" "$COUNT")"
    P="$(check_power "$RUN/power.txt" "$FROM" "$TO" "$SECS")"
    read -r APPCPU WSCPU MEM MEMPK <<<"$S"
    echo "habitat=$HABITAT fps=$FPS seconds=$SECS count=$(printf '%s\n' "$R" | sed -n 's/.*count=\([0-9]*\)$/\1/p')"
    echo "  test copy CPU (mean):    ${APPCPU}%"
    echo "  WindowServer CPU (mean): ${WSCPU}%   (minus the baseline run = added)"
    echo "  test copy memory:        ${MEM} MB mean, ${MEMPK} MB peak"
    printf '%s\n' "$R" | grep '^  display' || true
    echo "  power: $P"
    if ! readings_ok "$R" || ! power_ok "$P"; then
      echo "  INVALID: readings: $(printf '%s' "$R" | tail -1); power: $P"
      record "$HABITAT $FPS ${SECS}s INVALID: $(printf '%s' "$R" | tail -1); $P"
      die "results invalid (above); rerun"
    fi
    awk -v a="$APPCPU" 'BEGIN{exit !(a<0.3)}' && die "app CPU ~ 0: looked paused (desktop covered?) -- results invalid"
    record "$HABITAT $FPS ${SECS}s $(printf '%s' "$R" | tail -1 | cut -d' ' -f2-): app ${APPCPU}%, WindowServer ${WSCPU}%, memory ${MEM}/${MEMPK} MB; $(printf '%s' "$R" | grep '^  display' | tr -s ' ' | tr '\n' ';')"
    ;;
  preview)
    launch_test 0 1 0 preview bg
    echo "the card appears in a second or two (later if the screen is locked or asleep) on the screen you are working on,"
    echo "under the test copy's menu bar icon if it shows there. It stays 20 s, a line along its bottom draining (the"
    echo "pointer over it pauses that); clicks elsewhere leave it be. Its buttons, its close button and Esc only close it."
    for i in $(seq 1 30); do card_shown "$APPLOG" "$TEST_PID" "$LAUNCH_ID" && break; sleep 1; done
    card_shown "$APPLOG" "$TEST_PID" "$LAUNCH_ID" || die "the test copy logged no card on screen in 30 s -- preview failed"
    echo "the test copy put the card on screen"
    D="$(card_drawn_check "$APPLOG" "$TEST_PID" "$LAUNCH_ID" 10)"
    case "$D" in
      OK*) read -r _ share size <<<"$D"; echo "the card's drawn check: $share of its window drawn ($size points); its image: build/energy-test/card-drawn.png" ;;
      *) die "${D#FAIL } -- preview failed before asking (its image, if any: build/energy-test/card-drawn.png)" ;;
    esac
    echo "look at the top right of the screen you are working on, within 20 s"
    exec 3</dev/tty
    SEEN=0; confirm_seen && SEEN=1
    C="$(card_closed "$APPLOG" "$TEST_PID" "$LAUNCH_ID")"
    if [ -n "$C" ]; then echo "the card closed: ${C% *}, ${C#* } s after it was shown"; else echo "the card was still up at the answer"; fi
    [ "$SEEN" = 1 ] || die "the card was not confirmed seen -- preview failed"
    still_ours
    wait_for_reading preview || die "no built-in display drew a frame -- preview failed"
    domain_absent || die "the preview wrote to $DOMAIN"
    echo "preview: seen by the director; a built-in display drew; the test domain stayed absent"
    ;;
  calibrate)
    write_settings
    launch_test 1 0 1 quiet
    wait_for_reading calibrate || die "the built-in display did not draw the Meadow alone (lid closed?) -- calibration failed"
    echo "the Meadow is on the built-in display alone. Open Settings from the test copy's menu bar icon (its menu starts"
    echo "with \"$TEST_NAME: energy test copy\") and move the butterfly count until it looks right."
    exec 3</dev/tty
    N="$(confirm_count "$APPLOG" "$TEST_PID" "$LAUNCH_ID" 8)" || die "the count was not confirmed -- calibration failed"
    ANSWERED="$(cat "$RUN/answered" 2>/dev/null || true)"
    [ -n "$ANSWERED" ] || die "calibration: the answer's time was not recorded -- failed"
    still_ours
    # From the answer on only: before it, the director was in the test copy's Settings and menus.
    R="$(calibration_final "$APPLOG" "$TEST_PID" "$LAUNCH_ID" "$ANSWERED" 15)"
    readings_ok "$R" || die "calibration: $(printf '%s' "$R" | tail -1) -- failed"
    echo "count used: $N (the test copy drew $N live on the built-in display alone; it is not saved anywhere else)"
    echo "  next: Tools/energy.sh meadow 30 60 $N   and   Tools/energy.sh meadow 15 60 $N"
    record "calibrate: count $N on the built-in display"
    ;;
esac
