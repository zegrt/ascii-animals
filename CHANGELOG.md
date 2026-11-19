# Changelog

## 3.0
- **ASCII Sharks is now ASCII Animals.** A new app with a new name, because the ocean isn't the only place to watch any more. Pick a **habitat** in the 🐟 menu or in Settings.
- **The Web, a new habitat.** Spiders spin orb webs across your desktop, flies wander by and blunder into them, and a jumping spider hunts between the webs. It's a faithful port of [ascii-spiders](https://github.com/stackedlol/ascii-spiders) by @stackedlol. Move the pointer through a web and the silk rings; click bare desktop to drop a fly; hold the pointer still near the jumper and it may pounce. Choose your spiders (garden spiders, wasp spiders, golden orb weavers), and turn the flies or the jumper off if you like.
- **Coming from ASCII Sharks?** Just install ASCII Animals. The first time it opens, it quits ASCII Sharks, brings your settings over, skips the welcome and offers to move ASCII Sharks to the Trash. The two never run at the same time.
- **The Web costs no more than the Ocean.** On a two-display Mac, the Web used about 9.6% CPU at 30 fps against the Ocean's 12.7%, with the same WindowServer cost.
- Everything else carries over: Dark, Light and Calm, one habitat across your displays, the matching lock screen, self-updates and the menu. Logs now live in `~/Library/Logs/ASCII Animals`.

## 2.3
- **Updates install themselves.** When a new version is out, ASCII Sharks downloads it, checks it (GitHub's checksum, that it's this app at that version, its signature), swaps itself out and restarts. It takes a couple of seconds, with no disk image, no dragging and no Open Anyway. It waits while Settings is open. If any step fails, the version you have stays exactly as it was.
- **Or update by hand.** Turn off **Install updates automatically** in Settings and the menu offers **Update to …** instead: one click. **Check Now…** in Settings (or **Check for Updates…** in the menu) looks right away.
- Coming from 2.2.1 or earlier, this one last update is still by hand: download the DMG once more. Every update after that is a click.

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
