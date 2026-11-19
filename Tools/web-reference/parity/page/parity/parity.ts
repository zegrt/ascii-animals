// Parity reference page (Task 11), never part of the port. The demo page (demo.ts: the default cast, no roster) with:
//  - Math.random replaced by the SplitMix64 stream the Swift port's WebRandom(seed:) draws from (as world-ref.mjs);
//  - the engine's own clock stopped, so the page steps only when told (window.parity.advance);
//  - ?theme=light|dark, ?still=1 (the engine's still: laid out settled, 120 steps).
const q = new URLSearchParams(location.search);
const MASK = (1n << 64n) - 1n;
let state = BigInt(q.get("seed") ?? "1") & MASK;
let draws = 0;
function next() {
  state = (state + 0x9e3779b97f4a7c15n) & MASK;
  let z = state;
  z = ((z ^ (z >> 30n)) * 0xbf58476d1ce4e5b9n) & MASK;
  z = ((z ^ (z >> 27n)) * 0x94d049bb133111ebn) & MASK;
  return z ^ (z >> 31n);
}
Math.random = () => (draws++, Number(next() >> 11n) * 2 ** -53);
window.requestAnimationFrame = () => 0;
window.cancelAnimationFrame = () => {};

const theme = (q.get("theme") ?? "dark") as "dark" | "light";
const still = q.has("still");
if (theme === "light") document.documentElement.style.background = document.body.style.background = "#f7f6f3";
const canvas = document.querySelector("canvas")!;
// Canvas text can't trigger a webfont load: load the face first, so every frame is drawn in it.
await document.fonts.load(`600 16px ${getComputedStyle(canvas).fontFamily}`);
const fontOK = document.fonts.check(`600 16px "Geist Mono"`);
const { SpiderEngine } = await import("../src/index.ts");
const engine = new SpiderEngine(canvas, undefined, { theme, still });
const w = engine.world;
const W = w.width;

// engine.ts onPointerMove / onPointerLeave, as world-ref.mjs.
function move(x: number, y: number) {
  const p = w.pointer;
  const inside = x >= 0 && y >= 0 && x <= w.width && y <= w.height;
  if (!p.active) (p.lx = x), (p.ly = y);
  p.x = x;
  p.y = y;
  p.active = inside;
}
const leave = () => (w.pointer.active = false);

// The interaction script, step s counted from the end of the warm-up. Sources/OceanTool/WebScript.swift (OceanTool
// frames --interact) runs the same: change both together.
let aim = { x: 0, y: 0 };
const near = () => w.weavers[w.weavers.length - 1];
const events: string[] = [];
function script(s: number) {
  if (s >= 120 && s < 240 && near()) {
    // The pointer drawn through the near web, level with its hub, right to left: the silk rings.
    const web = near().web;
    const k = (s - 120) / 120;
    move(web.x[web.hub] + web.outer * (0.7 - 1.4 * k), web.y[web.hub] + 7);
  }
  if (s === 240) leave();
  if (s === 300 && near()) {
    // A click on the near web's capture spiral (else its hub): a fly drops there, sticks, and the spider comes.
    const web = near().web;
    let p = { x: web.x[web.hub], y: web.y[web.hub] };
    for (let l = 0; l < web.m; l++) if (web.state[l] === 1 && web.kind[l] === 5) { p = web.pos(l, 0.5, { x: 0, y: 0 }); break; }
    w.release(p.x, p.y);
    events.push(`click ${p.x.toFixed(1)},${p.y.toFixed(1)}`);
  }
  if (s >= 420 && s < 900 && w.jumper) {
    // The pointer held still 260 px from the jumper: it stalks, crouches and pounces.
    if (s === 420) {
      const sp = w.jumper.spider;
      aim = { x: Math.min(W - 20, Math.max(20, sp.x + (sp.x < W / 2 ? 260 : -260))), y: sp.y };
      events.push(`aim ${aim.x.toFixed(1)},${aim.y.toFixed(1)}`);
    }
    move(aim.x, aim.y);
  }
  if (s === 900) leave();
}

let s = 0;
(window as any).parity = {
  fontOK,
  font: getComputedStyle(canvas).fontFamily,
  draws: () => draws,
  events,
  /** n steps of 1/60 s (with the script when asked), then one frame drawn. */
  advance(n: number, interact: boolean) {
    for (let i = 0; i < n; i++) {
      if (interact) script(++s);
      w.step(1 / 60);
    }
    engine.renderer.render(w);
  },
  state: () => ({ time: w.time, webs: w.webs.length, weavers: w.weavers.map((v: any) => v.state), jumper: w.jumper?.state,
    flies: w.swarm.flies.map((f: any) => f.mode), hubs: w.webs.map((b: any) => [b.x[b.hub], b.y[b.hub]]) }),
};
(window as any).parityReady = true;
