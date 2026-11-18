# Changelog

## 2.2.1
- **The original app icon is back.** 2.2 shipped with a re-rendered icon in which the shark came out vertical. This restores the diagonal shark.

## 2.2
- **A proper welcome.** The first launch is a short, immersive tour you can play with: move the pointer, click for a splash, and pick a look. You can reopen it anytime from the menu.
- **Update notices.** ASCII Sharks checks GitHub once a day for a newer version (just the version number; nothing about you is sent) and tells you in the menu and with a notification. You can turn this off in Settings.
- **About, help and uninstall.** There's an About window. Report a Problem opens a GitHub issue that's already filled in, with no names or file paths, and nothing is sent until you submit it. Copy Diagnostics puts the same details on the clipboard. Uninstall puts your wallpaper back and removes everything.
- **⌃⌥⌘P pauses from anywhere.** You can also hide the menu-bar icon. Opening the app again brings Settings back.
- **A nicer install window.** It has its own artwork and a volume icon.
- If the app quit unexpectedly, the menu says so the next time and offers to report it.

## 2.1
- **One ocean across your displays.** Sharks patrol a screen each and now and then swim to the next one. Gaps between screens count as walls.
- **A redesigned Settings window.** It has a live preview, a shark line-up editor and clearer controls.
- **A status line in the menu.** It shows what the ocean is doing and why it's paused or slowed.

## 2.0
- **A native app.** It's rewritten in Swift and Metal, with no WebKit.
- **Easier on power.** It pauses when the desktop is covered, locked or asleep, and drops to 15 fps on battery.
- **Matches the lock screen.** A matching still becomes the system wallpaper while the app runs, and your own comes back when it quits.
- **Settings, presets, light and calm looks.** Builds are universal (Apple Silicon and Intel).
