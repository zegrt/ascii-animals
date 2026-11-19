<p align="center">
  <img src="docs/media/icon.png" width="128" alt="ASCII Sharks app icon">
</p>

<h1 align="center">ASCII Sharks · Wallpaper</h1>

<p align="center">
  <b>A live macOS wallpaper of sharks hunting schools of fish, drawn in ASCII.</b><br>
  It runs natively behind your desktop icons.
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111?style=flat-square&logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white">
  <img alt="Metal" src="https://img.shields.io/badge/GPU-Metal-6e7bff?style=flat-square">
  <img alt="Universal" src="https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-universal-444?style=flat-square">
  <img alt="MIT" src="https://img.shields.io/badge/license-MIT-2ea44f?style=flat-square">
</p>

<p align="center">
  <img src="docs/media/hero.gif" width="880" alt="Sharks gliding through an ASCII ocean, scattering schools of fish and leaving a cyan wake">
</p>

> [!NOTE]
> **This is a port.** The ocean is **[ascii-sharks](https://github.com/stackedlol/ascii-sharks)** by
> **[@stackedlol](https://github.com/stackedlol)** (drewdi): the boids, the hunting sharks, the eight species and the whole ASCII look.
> This repo brings it to the Mac as a native live wallpaper. Go star the original. ⭐

---

## Looks

<table>
  <tr>
    <td align="center"><img src="docs/media/dark.png" width="280" alt="Dark"><br><sub><b>Dark</b>, the original look</sub></td>
    <td align="center"><img src="docs/media/light.png" width="280" alt="Light"><br><sub><b>Light</b>, or match the system</sub></td>
    <td align="center"><img src="docs/media/calm.png" width="280" alt="Calm"><br><sub><b>Calm</b>, easier on your icons</sub></td>
  </tr>
</table>

## One ocean across your displays

<p align="center">
  <img src="docs/media/crossing.gif" width="600" alt="A shark swims from the monitor down into the laptop screen, through the bezel">
</p>
<p align="center"><sub>A monitor above a laptop, as one ocean. Sharks patrol a screen each and now and then cross over.<br>
Where no screen is (grey), nothing swims. Turn it off in Settings for a separate ocean per display.</sub></p>

## Settings

<table>
  <tr>
    <td width="46%" valign="top"><img src="docs/media/settings.png" alt="The Settings window: a live preview, the shark line-up, ocean, look and behaviour"></td>
    <td valign="top">

- **Live preview.** It redraws as you change things.
- **Shark line-up.** Choose 1–8 sharks from eight species, biggest first, or pick a preset.
- **Ocean.** Set the number of fish and the speed, and choose one ocean across all displays or one per display.
- **Look.** Dark, Light or Match System. You can also change the wake colour, and turn on calm mode or the grid.
- **Behaviour.** Pointer play, frame rate (15, 30 or 60 fps), Low Power Mode, matching the lock screen, and Open at Login.

The fish in the menu bar shows what it's doing, for example *Swimming · 30 fps* or *Paused, Low Power Mode*. It also gives quick access to presets, appearance and pause.

</td>
  </tr>
</table>

## Why it's nice to live with

<table>
  <tr>
    <td width="50%" valign="top">

**🖥 A real wallpaper**<br>
It sits above the system wallpaper and below your icons, on every Space. It fades in, and keeps swimming when displays change.

**🌊 One ocean across your displays**<br>
With a second monitor, the screens join into one ocean: sharks patrol a screen each and now and then swim across to the next one. Gaps between screens, and the space beside offset ones, count as walls.

**🔋 Gentle on the battery**<br>
It pauses when covered, locked, asleep or behind the screensaver. On battery or when the Mac is hot, it runs at 15 fps. In Low Power Mode it holds a still frame unless you turn animation on.

**🖱 Plays with your pointer**<br>
Fish flee the cursor and leave a wake. Click bare desktop for a splash, and the click still reaches Finder.

</td>
    <td width="50%" valign="top">

**🔒 Matches the lock screen**<br>
While it runs, a matching still becomes the system wallpaper, so the lock screen, Mission Control and the menu bar tint all match. **Your own wallpaper comes back when you quit.**

**🦈 Make the ocean yours**<br>
Pick 1–8 sharks from eight species (classic, hammerhead, great hammerhead, tiger, zebra, mako, thresher, nurse). You can also change the fish density, speed, appearance, grid, wake colour and frame rate.

**⚡️ Native**<br>
The simulation is in Swift and the renderer is a three-pass Metal renderer. There's no WebKit and no Electron. Universal binary.

</td>
  </tr>
</table>

## Install

**Download:** grab **[ASCII-Sharks.dmg](https://github.com/zegrt/ascii-sharks-wallpaper/releases/latest/download/ASCII-Sharks.dmg)** (1.4 MB, universal, macOS 14+) and drag the app to Applications.
The app isn't signed by a registered Apple developer, so the first time you open it, go to **System Settings → Privacy & Security** and click **Open Anyway**.

**Or build it yourself.** The only requirement is Apple's Command Line Tools (`xcode-select --install`). You don't need Xcode.

```sh
git clone https://github.com/zegrt/ascii-sharks-wallpaper
cd ascii-sharks-wallpaper
Tools/build.sh      # runs the checks, builds a universal app, renders its icon
Tools/install.sh    # copies it to ~/Applications and launches it
```

Then find the 🐟 in the menu bar for **Pause**, **Sharks**, **Appearance**, **Settings…** (`⌘,`), **Restore Original Wallpaper** and **Open at Login**.

- **⌃⌥⌘P** pauses and resumes from anywhere.
- **Opening the app again shows Settings.** That's how you get back to it if you've hidden the menu-bar icon, or if the icon is behind the notch.
- **Updates.** ASCII Sharks checks once a day for a newer version and installs it by itself, restarting in a couple of seconds (it waits while Settings is open). Prefer to choose when? Turn off **Install updates automatically** in Settings and use **Update to …** in the menu, or **Check Now…** in Settings.

## Uninstall

Choose **🐟 menu → Uninstall ASCII Sharks…** (or run `Tools/uninstall.sh`). It removes everything, in this order:
1. Puts your own wallpaper back.
2. Removes the login item.
3. Deletes its settings, saved stills and logs.
4. Moves itself to the Trash.

## Privacy

- **No accounts and no analytics.** No tracking of any kind.
- **The only network request:** about once a day, ASCII Sharks asks GitHub for the latest version number of this repo (`api.github.com/repos/zegrt/ascii-sharks-wallpaper/releases/latest`). That request carries the app version and nothing else. You can turn it off in Settings.
- **Watching the pointer and windows.** ASCII Sharks watches the mouse pointer and reads where windows are on screen. It does this only to know when bare desktop is under the pointer, for the wakes and splashes, and when the desktop is covered, so it can pause. It can't see your keystrokes or what's inside your windows, and it needs no special permission for any of it.
- **Logs stay on your Mac.** Logs are at `~/Library/Logs/ASCII Sharks`. **Report a Problem** and **Copy Diagnostics** only run when you choose them. They share your app and macOS versions, displays, power state and settings, with your name and home-folder paths removed. Report a Problem opens a draft issue in your browser, and nothing is sent until you submit it.

## How it works

```mermaid
flowchart LR
  subgraph CPU["CPU · Swift"]
    W["World<br/>boids + sharks<br/>fixed 60 Hz step"] --> P["FramePacker<br/>uniforms + fish grid"]
  end
  subgraph GPU["GPU · Metal (one frame)"]
    A["wake<br/>cols × rows<br/>ripples + eat flashes"] --> B["cells<br/>which shark part<br/>or fish per cell"]
    B --> C["compose<br/>full resolution<br/>grid, glyphs, colour"]
  end
  P --> A
  P --> B
  C --> D["desktop-level window<br/>below your icons"]
```

| Layer | Folder | What it does |
|---|---|---|
| **Domain** | `Sources/OceanKit/Domain` | The simulation, settings, power policy, pointer routing, frame packing and wallpaper bookkeeping. Pure Swift with no AppKit, and fully checked. |
| **Render** | `Sources/OceanKit/Render` | The MSL shaders (compiled at runtime), the Geist Mono glyph atlas and offscreen stills. |
| **Host** | `Sources/ASCIISharks` | AppKit: windows, display links, system signals, the menu, settings and the system wallpaper. |

The ocean is rendered on a grid of ASCII cells. Each frame:
1. The **wake** pass diffuses ripples, once per simulation step, so trails don't depend on the frame rate.
2. The **cells** pass decides what fills each cell: shark body, fin, ridge, eye or markings, or a fish.
3. The **compose** pass draws the grid, wake dots, eat flashes and the glyphs from a font atlas.

## Energy

Measured on an M5 Pro MacBook Pro.

| | App | WindowServer added | Memory |
|---|---|---|---|
| **15 fps** (on battery) | ~2.5% CPU | within noise | ~84 MB |
| **30 fps** (on AC, the default) | ~4–5.5% CPU | ~15% | ~84 MB |
| *WebKit prototype, for comparison* | *~14% CPU* | *not measured* | *~355 MB* |

Most of a live wallpaper's cost is WindowServer redrawing everything above it on every frame. That's why the frame rate is the main lever, and why the economy rate is 15 fps.

## Develop

```sh
swift run -c release OceanChecks                       # 71 checks: domain + headless Metal renders
swift run -c release OceanTool still out.png 1440x900  # --light --calm --sharks mako,tiger --seed 3
swift run -c release OceanTool frames out/ 1080x675    # a continuous run as PNG frames
swift run -c release OceanTool bench                   # simulation cost
OCEAN_DEBUG=1 .build/out/Products/Release/ASCIISharks  # log power-mode decisions
```

The design and its review are in [`docs/plans/`](docs/plans).

## Limits

- **Spaces:** macOS changes wallpapers one Space at a time and gives apps no way to identify Spaces. So the matching still goes on the Space where the app starts. Wallpapers it doesn't recognise are never touched, and only what it set is restored.
- **Aerial and dynamic wallpapers:** these come back as whatever image macOS reports for them.
- **Signing:** the app is signed ad hoc, not by a registered Apple developer. That's why macOS asks you to click Open Anyway the first time you open it.
- **On the list:** a screensaver edition.

## Credits

- **Made by** [XERO WORKS](https://xeroworks.org).
- **The ocean:** [ascii-sharks](https://github.com/stackedlol/ascii-sharks) by [@stackedlol](https://github.com/stackedlol) (drewdi), MIT. The simulation, species, shark shapes and rendering style are ported from it.
- **Font:** [Geist Mono](https://github.com/vercel/geist-font), SIL Open Font License 1.1 ([`Resources/OFL.txt`](Resources/OFL.txt)).
- **License:** MIT ([`LICENSE`](LICENSE)). It keeps the original copyright notice alongside this port's.

<p align="center"><sub>
<pre>
       ;'                .oooo
        %%'    .t;.       %8S8.
  t'   ''XSSS8SSX%XX8#.   %XSX%      ~ swim safe ~
   ::%t%%%S%:;StS%ttSS%tSXSt88@@%8%
</pre>
</sub></p>
