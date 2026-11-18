# Proper App — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make ASCII Sharks feel like a real Mac app across its whole life:
- Install: a crafted drag-to-Applications window.
- First launch: an immersive welcome.
- Daily use: About, a global shortcut, a hideable icon, and reopening the app shows Settings.
- Change: an update notice.
- Failure: crash detection, diagnostics, report a problem.
- Leaving: a clean uninstall.
- Trust: a privacy note.
- Shipping: CI and tagged releases.

**Architecture:** The pure decisions go in OceanKit and are checked:
- Version comparison.
- Parsing the release feed.
- Building the issue report.
- Throttling update checks.

The AppKit host wires them to the OS. The UI surfaces are owned by a design agent that works against stub interfaces committed first (Task 0). Two owners in one checkout commit by explicit path only.

**Company:** Xero Works Pvt Ltd.
- Used in: the copyright line, the About window and the LICENSE.
- Bundle id unchanged (`local.ascii-sharks.wallpaper`): changing it would orphan existing users' settings and wallpaper memory. It changes when a Developer ID exists.

## Global Constraints
- Same toolchain rules as before: Command Line Tools only, no SwiftUI macros, `OceanKit.Settings` must be qualified, and checks are an executable.
- Network only for the update check: `GET https://api.github.com/repos/zegrt/ascii-sharks-wallpaper/releases/latest`, at most once a day plus manual checks, never sending anything about the user.
- Nothing leaves the Mac otherwise. Diagnostics are copied to the clipboard or opened as a GitHub issue draft in the browser, only when the user asks.
- The uninstall must restore the user's wallpaper before deleting anything.

## Interfaces (Task 0 commits these as stubs; the UI agent builds against them)

In `Sources/ASCIISharks/AppInfo.swift`:
```swift
enum AppInfo {
  static var version: String; static var build: String
  static let company = "Xero Works Pvt Ltd"
  static let copyright: String          // "© 2026 Xero Works Pvt Ltd"
  static let repoURL, releasesURL, issuesURL, originalURL: URL   // originalURL = stackedlol/ascii-sharks
}
```

On `AppDelegate`:
```swift
let updates: UpdateService            // .available: LatestRelease?, .state, checkNow(userInitiated:)
var crashedLastTime: Bool
func showAbout(); func showWelcome(); func showSettings()
func reportProblem()                  // opens a prefilled GitHub issue in the browser
func copyDiagnostics()                // diagnostics text -> clipboard
func uninstall()                      // confirm, restore wallpaper, remove login item, files, prefs, trash app, quit
```

In OceanKit:
```swift
struct AppVersion: Comparable { init?(_ s: String) }
enum UpdateFeed { static func parse(_ data: Data) -> LatestRelease? }
struct LatestRelease { version: AppVersion; tag: String; pageURL: URL; dmgURL: URL?; notes: String }
enum UpdatePolicy { static func shouldCheck(lastCheck: Date?, now: Date) -> Bool }   // ≥ 20 h apart
enum IssueReport { static func body(_ d: DiagnosticFacts) -> String; static func url(base: URL, title: String, body: String) -> URL }
```

Settings gain:
- `pauseShortcut: Bool = true` (⌃⌥⌘P toggles pause)
- `showMenuBarIcon: Bool = true`
- `checkForUpdates: Bool = true`

## Tasks

### Task 0 — Stubs and the contract (me)
`AppInfo`, the `AppDelegate` methods (no-op or minimal), the `UpdateService` shape, the Settings fields, and the `Onboarding`/`About` call sites:
- `OnboardingController.showIfNeeded(app:)` is called after start.
- `showWelcome()` and `showAbout()` call the agent's controllers, which start as stub files the agent will own.

Everything builds and is committed. Then the agent is dispatched.

### Task 1 — Updates (me)
- OceanKit: `AppVersion`, `UpdateFeed`, `UpdatePolicy`.
  - Checks:
    - Version ordering: `2.1 < 2.10`, `2.1.0 == 2.1`, and a `v` prefix is allowed.
    - Parsing a real releases/latest payload, including picking the asset that ends in `.dmg`.
    - Policy timing.
- Host `UpdateService`:
  - Checks on launch (after 30 s) and then hourly, but the policy limits it to once per 20 h.
  - Uses URLSession with a timeout, and an ETag so repeat checks cost nothing.
  - On a newer version: `available` is set, and one notification per version is posted with UNUserNotificationCenter (asked on first need; if denied, the notice shows in the menu only).
  - Manual check: an alert saying "You're up to date" or "Version X is available — Download".

### Task 2 — Diagnostics, crash detection, report (me)
- **Logging:** `Log` writes to `~/Library/Logs/ASCII Sharks/ascii-sharks.log`, rolled at 512 KB with one backup. `NSLog` call sites move to `Log`.
- **Crash marker:**
  - A `running` file in Application Support is written at launch and removed on clean quit.
  - If it's present at launch: `crashedLastTime = true`, and the menu shows a notice with a report action. The wallpaper still is reconciled as usual.
- **Diagnostics:** `IssueReport.body` (checked: contains version, macOS, displays, power state and settings JSON, and never paths under the home folder or user names). Report a Problem opens `issues/new?title=&body=` with the URL capped at 6000 characters.

### Task 3 — Uninstall, reopen, shortcut, icon (me)
- **Uninstall:**
  1. Ask to confirm.
  2. Restore all wallpapers.
  3. Unregister the login item.
  4. Delete the stills folder, logs and crash marker.
  5. Remove the preferences domain.
  6. Move the app to the Trash.
  7. Quit.
- `applicationShouldHandleReopen` opens Settings, so reopening the app shows it.
- **Global shortcut:** ⌃⌥⌘P toggles pause, using Carbon `RegisterEventHotKey` (no Accessibility permission needed). It's a setting.
- **Hide the menu bar icon:** removing the status item. Reopening the app brings Settings back, and Settings explains how.

### Task 4 — Release engineering (me)
- **Committed assets:** `Resources/AppIcon.icns` is committed, so CI needs no GPU; `Tools/build.sh` regenerates it only with `REGEN_ICON=1`.
- **Proper DMG:** `Tools/package.sh` uses `dmgbuild` (Python, in a tool venv) with:
  - the background art (`Resources/dmg/background.png` and `@2x`)
  - icon positions
  - a 660×420 window, no toolbar
  - the volume icon
  - ULFO compression
- **GitHub Actions:**
  - `ci.yml` runs on push: build, plus checks with `OCEAN_SKIP_GPU=1` (the runners have no Metal device, so the GPU checks are skipped by that flag).
  - `release.yml` runs on a `v*` tag: build universal, package the DMG, and create or attach the release with notes from the CHANGELOG.
- **Docs:**
  - A `CHANGELOG.md`.
  - Issue templates.
  - A README privacy section.
  - The LICENSE port line becomes Xero Works Pvt Ltd.
  - Version 2.2.

### Task 5 — UI (design agent, in parallel)
- **Immersive first launch:**
  - A full-screen window above everything, with a live interactive ocean, typed Geist Mono copy, and a few short steps (meet the ocean, move the pointer, click for a splash, where settings live, pick a look).
  - It ends by dissolving into your real desktop ocean.
  - Shown once, re-openable from the menu.
- **About window:** the icon, the name, the version, "by Xero Works Pvt Ltd", a credits line for @stackedlol and Geist Mono, and links (GitHub, Check for Updates).
- **Menu:**
  - About, Check for Updates…
  - An accented "Update to X available…" item when there is one.
  - Welcome Tour, Report a Problem…, Copy Diagnostics, Uninstall…
  - The crash notice.
- **Settings:** toggles for the pause shortcut, the menu-bar icon and checking for updates.
- **DMG artwork:** `Resources/dmg/background.png` (660×420) and `background@2x.png` (1320×840). It shows the ocean in ASCII, a clear drag arrow, and the labels. The icon slots are fixed: app at (170, 210), Applications at (490, 210), in window points.

### Task 6 — Integrate and ship (me)
- Review the agent's work.
- Build, install and test the uninstall in a scratch copy.
- Tag v2.2 so CI builds and releases it.
- Verify the download, push, and update the README.
