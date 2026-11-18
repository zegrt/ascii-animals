// Wallpaper entry: the original engine, untouched, plus a small bridge the
// native app calls. The wallpaper window ignores the mouse (clicks belong to
// the desktop), so the app forwards the cursor here as synthetic pointer events.
import { OceanEngine, type SharkKind, type SharkSpec } from "../../ascii-sharks/src";

declare global {
  interface Window {
    __SHARKS?: string;
    __PAUSED?: boolean;
    wallpaper?: {
      move(x: number, y: number): void;
      down(x: number, y: number): void;
      leave(): void;
      pause(paused: boolean): void;
    };
  }
}

// Canvas text can't trigger a webfont load, so ask for the face directly.
// A page that starts hidden (launched at login behind other windows) may not
// load it, so ask again whenever it becomes visible; the renderer picks the
// face up on its next frame.
const loadFont = () => document.fonts.load('600 16px "Geist Mono"').catch(() => []);
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible") loadFont();
});

async function start() {
  await loadFont();

  const kinds = (window.__SHARKS ?? "").split(",").filter(Boolean) as SharkKind[];
  const sharks: SharkSpec[] | undefined = kinds.length
    ? kinds.map((kind, i) => ({ kind, size: 1 - i * 0.1 }))
    : undefined;

  const engine = new OceanEngine(document.querySelector("canvas")!, sharks);
  // Pausing reuses the engine's own off-screen switch.
  const loop = engine as unknown as { visible: boolean; schedule(): void };

  const pointer = (type: string, x: number, y: number) =>
    window.dispatchEvent(new PointerEvent(type, { clientX: x, clientY: y, pointerType: "mouse" }));

  window.wallpaper = {
    move: (x, y) => pointer("pointermove", x, y),
    down: (x, y) => {
      pointer("pointermove", x, y);
      pointer("pointerdown", x, y);
    },
    leave: () => document.documentElement.dispatchEvent(new PointerEvent("pointerleave")),
    pause: (paused) => {
      loop.visible = !paused;
      loop.schedule();
    },
  };

  if (window.__PAUSED) window.wallpaper.pause(true);
}

start();
