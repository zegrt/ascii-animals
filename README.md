# ASCII Sharks — a live wallpaper for macOS

The [ascii-sharks](https://github.com/stackedlol/ascii-sharks) ocean (sharks hunting schools of fish, drawn in ASCII), running natively behind your desktop icons.

- **Native.** Swift simulation and a three-pass Metal renderer. There's no WebKit.
- **Power-aware.**
  - It pauses when covered, locked, asleep, or behind the screensaver.
  - It drops to 15 fps on battery and under thermal pressure.
  - In Low Power Mode it holds a still, unless you turn on "Keep animating in Low Power Mode".
  - Reduce Motion shows a settled still.
- **Feels like a wallpaper.**
  - It fades in, and keeps swimming through display changes.
  - The lock screen, Mission Control and menu bar get a matching still.
  - Your own wallpaper comes back when the app quits.
- **Interactive.** Moving the pointer over bare desktop leaves a wake, and a click makes a splash. Clicks still go to the desktop.
- **Settings.** You can change:
  - The shark line-up (1–8 of 8 species) and fish density.
  - Speed, and the look (dark, light or match system; calm; grid; wake colour).
  - The frame rate, and Open at Login.

## Build and install

You need the Command Line Tools only; Xcode isn't required.

```sh
Tools/build.sh      # runs the checks, builds a universal app, renders the icon, signs ad hoc
Tools/install.sh    # copies it to ~/Applications and launches it
```

Find it in the menu bar under the fish icon.

## Develop

```sh
swift run -c release OceanChecks                 # all checks (domain + headless Metal renders)
swift run -c release OceanTool still out.png 1440x900 [--light] [--calm] [--sharks mako,tiger]
swift run -c release OceanTool bench             # simulation cost
OCEAN_DEBUG=1 .build/out/Products/Release/ASCIISharks   # log run-mode changes
```

The code is in three layers:

| Layer | Where | What it does |
|---|---|---|
| Domain | `Sources/OceanKit/Domain` | The simulation, settings, power policy, pointer routing, frame packing and wallpaper memory. Pure Swift, fully checked. |
| Render | `Sources/OceanKit/Render` | The MSL shaders (wake, cells, compose), glyph atlas and offscreen stills. |
| Host | `Sources/ASCIISharks` | AppKit: desktop-level windows, display links, system signals, menu, settings and system wallpaper. |

The plan and its revisions are in `docs/plans/`.

## Measured

These were measured on an M5 Pro MacBook Pro on battery, in Low Power Mode with animation allowed, at 15 fps:
- The app uses about 2.5% CPU.
- WindowServer's extra compositing is within measurement noise.
- Memory is about 84 MB paused and about 210 MB live.

The WebKit prototype used about 14% CPU and about 355 MB. Its figure doesn't include WindowServer.

At 30 fps the app uses 5.5%, and WindowServer adds about 15% to recomposite the desktop. That's why 15 fps is the economy rate. Most of the cost of any live wallpaper is WindowServer redrawing everything above it.

## Limits

- **Spaces:** macOS changes wallpapers one Space at a time and gives apps no way to identify Spaces. So the matching still goes on the Space where the app starts. Wallpapers it doesn't recognise are left alone, and only what it set is restored.
- **Aerial and dynamic wallpapers:** these come back as whatever image macOS reports for them.
- **Signing:** the app is signed ad hoc. To share it, sign it with a Developer ID and notarize it.
- **Not built yet:** the screensaver version and one ocean spanning several displays are planned for v2.

## Credits

- Ocean simulation and look: ascii-sharks by drewdi and Stephen Zhang, MIT (see `LICENSE`).
- Font: Geist Mono, SIL OFL 1.1 (see `Resources/OFL.txt`).
