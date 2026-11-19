// Reference run for webWorldMatchesOriginal: the original world.ts (89a7721, patched as README.md says: import
// paths given .ts and parameter properties spelled out for node's type stripping, the nav-bar gap dropped and the
// move glide's hang fixed, as the port does), with Math.random replaced by the SplitMix64 stream WebRandom(seed:)
// draws from. A scripted pointer, two clicks and a torn-free fly; prints JSON features at the checkpoints.
// Usage, from inside the patched clone:
//   node <this dir>/world-ref.mjs <seed> <W> <H> <cw> <ch> <steps> [checkpoints,comma,separated] [--trace]
// Optional: WEB_OPTS='{"spiders":["nephila"],"flies":0,"jumper":false,"settled":true}' (spiders given = a roster).
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
// Run from inside the patched ascii-spiders clone: its sources are ./src.
const src = (f) => pathToFileURL(resolve("src", f)).href;
const MASK = (1n << 64n) - 1n;
let state = 0n;
let draws = 0;
function seed(s) { state = BigInt(s) & MASK; }
function next() {
  state = (state + 0x9E3779B97F4A7C15n) & MASK;
  let z = state;
  z = ((z ^ (z >> 30n)) * 0xBF58476D1CE4E5B9n) & MASK;
  z = ((z ^ (z >> 27n)) * 0x94D049BB133111EBn) & MASK;
  return z ^ (z >> 31n);
}
Math.random = () => (draws++, Number(next() >> 11n) * 2 ** -53);
const { World } = await import(src("world.ts"));

const [S, W, H, CW, CH, STEPS] = process.argv.slice(2, 8).map(Number);
const checkpoints = (process.argv[8] ?? "").split(",").filter(Boolean).map(Number);
const trace = process.argv.includes("--trace");
seed(S);
const opts = JSON.parse(process.env.WEB_OPTS ?? "{}");
const w = new World(opts.spiders?.map((kind) => ({ kind })), { flies: opts.flies, jumper: opts.jumper });
w.layout(W, H, CW, CH, !!opts.settled);

const WS = ["build", "idle", "hunt", "wrap", "carry", "return", "eat", "move"];
const JS = ["pause", "burst", "crouch", "jump"];
const FS = ["fly", "rest", "stuck", "wrapped", "held", "gone"];

// engine.ts onPointerMove / onPointerLeave
function move(x, y) {
  const p = w.pointer;
  const inside = x >= 0 && y >= 0 && x <= W && y <= H;
  if (!p.active) (p.lx = x), (p.ly = y);
  p.x = x;
  p.y = y;
  p.active = inside;
}
function leave() { w.pointer.active = false; }

function features() {
  const f = [];
  f.push(["time", w.time]);
  w.webs.forEach((web, i) => {
    let sx = 0, sy = 0;
    for (let n = 0; n < web.n; n++) { sx += web.x[n]; sy += web.y[n]; }
    f.push([`web${i}.laid`, web.laid], [`web${i}.broken`, web.broken], [`web${i}.gen`, web.gen], [`web${i}.seed`, web.seed],
      [`web${i}.n`, web.n], [`web${i}.held`, web.held], [`web${i}.hubX`, web.x[web.hub]], [`web${i}.hubY`, web.y[web.hub]],
      [`web${i}.sumX`, sx], [`web${i}.sumY`, sy], [`web${i}.prey`, web.prey.length]);
  });
  w.weavers.forEach((v, i) => {
    const sp = v.spider;
    let fx = 0, fy = 0, planted = 0, links = 0;
    for (const l of sp.legs) { fx += l.fx; fy += l.fy; planted += l.planted ? 1 : 0; links += l.link; }
    f.push([`weaver${i}.state`, WS.indexOf(v.state)], [`weaver${i}.step`, v.step], [`weaver${i}.wp`, v.wp], [`weaver${i}.catches`, v.catches],
      [`weaver${i}.age`, v.age], [`weaver${i}.alert`, v.alert], [`weaver${i}.x`, sp.x], [`weaver${i}.y`, sp.y], [`weaver${i}.h`, sp.h],
      [`weaver${i}.hv`, sp.hv], [`weaver${i}.dx`, sp.dx], [`weaver${i}.dy`, sp.dy], [`weaver${i}.still`, sp.still],
      [`weaver${i}.feetX`, fx], [`weaver${i}.feetY`, fy], [`weaver${i}.planted`, planted], [`weaver${i}.links`, links]);
  });
  const j = w.jumper;
  if (j) {
    const sp = j.spider;
    let fx = 0, fy = 0;
    for (const l of sp.legs) { fx += l.fx; fy += l.fy; }
    f.push(["jumper.state", JS.indexOf(j.state)], ["jumper.x", sp.x], ["jumper.y", sp.y], ["jumper.h", sp.h], ["jumper.scale", sp.scale],
      ["jumper.drag", j.drag ? j.drag.life : -1], ["jumper.feetX", fx], ["jumper.feetY", fy]);
  }
  f.push(["flies", w.swarm.flies.length]);
  w.swarm.flies.forEach((fl, i) => {
    f.push([`fly${i}.mode`, FS.indexOf(fl.mode)], [`fly${i}.x`, fl.x], [`fly${i}.y`, fl.y], [`fly${i}.h`, fl.h], [`fly${i}.v`, fl.v]);
  });
  f.push(["heat", w.heat.length]);
  return f;
}

// The script: both sides compute the same inputs from the same state.
const out = {};
const seen = { weaver: new Set(), jumper: new Set(), fly: new Set() };
const near = () => w.weavers[w.weavers.length - 1];
let aim = null;
let cut = false;
for (let s = 1; s <= STEPS; s++) {
  if (s >= 60 && s < 120 && near()) {
    // A pass through the near web, level with its hub, right to left.
    const web = near().web;
    const k = (s - 60) / 60;
    move(web.x[web.hub] + web.outer * (0.6 - 1.2 * k), web.y[web.hub] + 7);
  }
  if (s === 120) leave();
  if (s === 180 && near()) {
    // A fly dropped on the near web's capture spiral: the first laid spiral thread, halfway along.
    const web = near().web;
    for (let l = 0; l < web.m; l++) if (web.state[l] === 1 && web.kind[l] === 5) { const p = web.pos(l, 0.5, { x: 0, y: 0 }); w.release(p.x, p.y); break; }
  }
  if (s === 200) w.release(W * 0.5, 12); // and one into the air
  if (s >= 300 && s < 1500 && w.jumper) {
    // The pointer held still 300 px from where the jumper was.
    if (s === 300) { const sp = w.jumper.spider; aim = { x: Math.min(W - 20, Math.max(20, sp.x + (sp.x < W / 2 ? 300 : -300))), y: sp.y }; }
    move(aim.x, aim.y);
  }
  if (s === 1500) leave();
  if (s >= 2400 && !cut) {
    // The first fly hunted from then on tears free (its thread cut), so its spider turns back: "return".
    const v = w.weavers.find((v) => v.state === "hunt" && v.prey);
    if (v) (v.web.cut(v.prey.link, true), (cut = true));
  }
  w.step(1 / 60);
  w.weavers.forEach((v) => seen.weaver.add(v.state));
  if (w.jumper) seen.jumper.add(w.jumper.state);
  w.swarm.flies.forEach((f) => seen.fly.add(f.mode));
  if (checkpoints.includes(s)) out[s] = features();
  if (trace && s % 60 === 0) console.error(s, Math.round(performance.now()), w.swarm.flies.length, w.heat.length, w.weavers.map((v) => v.state).join(","), w.jumper?.state, w.swarm.flies.map((f) => f.mode[0]).join(""));
}
out.next = Math.random();
out.draws = draws;
out.seen = { weaver: [...seen.weaver], jumper: [...seen.jumper], fly: [...seen.fly] };
console.log(JSON.stringify(out));
