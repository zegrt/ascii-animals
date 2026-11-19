// Reference values for orbWebMatchesOriginal: the original web.ts (89a7721, patched as README.md says),
// with Math.random replaced by the same SplitMix64 stream WebRandom(seed:) draws from (Rng.unit).
// Usage, from inside the patched clone: node <this dir>/web-ref.mjs
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
// Run from inside the patched ascii-spiders clone: its sources are ./src.
const src = (f) => pathToFileURL(resolve("src", f)).href;
const MASK = (1n << 64n) - 1n;
let state = 0n;
function seed(s) { state = BigInt(s) & MASK; }
function next() {
  state = (state + 0x9E3779B97F4A7C15n) & MASK;
  let z = state;
  z = ((z ^ (z >> 30n)) * 0xBF58476D1CE4E5B9n) & MASK;
  z = ((z ^ (z >> 27n)) * 0x94D049BB133111EBn) & MASK;
  return z ^ (z >> 31n);
}
Math.random = () => Number(next() >> 11n) * 2 ** -53;
const { OrbWeb } = await import(src("web.ts"));

const p = (v) => v.toPrecision(12);
function summary(label, w) {
  let sx = 0, sy = 0, sr = 0, on = 0;
  for (let i = 0; i < w.n; i++) { sx += w.x[i]; sy += w.y[i]; on += w.on[i]; }
  for (let l = 0; l < w.m; l++) sr += w.rest[l];
  let dew = 0; for (let l = 0; l < w.m; l++) if (w.dew[l] >= 0) dew++;
  console.log(`${label}: seed=${w.seed} N=${w.N} T=${w.T} n=${w.n} m=${w.m} route=${w.route.length} spiralStart=${w.spiralStart} laid=${w.laid} broken=${w.broken} radialsLaid=${w.radialsLaid} on=${on} dew=${dew}`);
  console.log(`  rin=${p(w.rin)} spacing=${p(w.spacing)} outer=${p(w.outer)} sumX=${p(sx)} sumY=${p(sy)} sumRest=${p(sr)} hub=(${p(w.x[w.hub])}, ${p(w.y[w.hub])})`);
}

function run(label, opts, rngSeed) {
  seed(rngSeed);
  const w = new OrbWeb(opts);
  summary(label + " generated", w);
  w.buildInstant();
  summary(label + " built", w);
  for (let s = 0; s < 600; s++) {
    if (s % 60 === 0) w.pluck(w.x[w.hub], w.y[w.hub], 3, -2, opts.cw * 1.15);
    w.step(s / 60);
  }
  summary(label + " 10s plucked", w);
  // A jolt draws from the stream too.
  w.jolt(w.route[w.spiralStart].link, 0.5, 3);
  w.step(10);
  summary(label + " jolted", w);
}

run("A", { cx: 400, cy: 300, radius: 200, depth: 1, cw: 12, ch: 17 }, 1);
run("B", { cx: 640, cy: 420, radius: 260, depth: 0.5, cw: 9, ch: 18, stab: true }, 42);
run("C", { cx: 500, cy: 400, radius: 180, depth: 0.7, cw: 12, ch: 17, frame: [
  { x: 330, y: 220, mx: 300, my: 150 }, { x: 690, y: 240, mx: 760, my: 180 },
  { x: 700, y: 610, mx: 760, my: 680 }, { x: 310, y: 600, mx: 250, my: 660 } ] }, 7);
// Production size: deeper spiral, longer stabilimentum.
run("D", { cx: 900, cy: 600, radius: 480, depth: 1, cw: 12, ch: 17, stab: true }, 3);
