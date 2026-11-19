// Captures the original through the parity page (see Tools/web-reference/README.md, "Parity with the original").
//   node capture.mjs still <out.png> [--theme dark|light] [--seed N] [--scale 2] [--w 1440] [--h 900]
//   node capture.mjs frames <dir> [--seed N] [--scale 1] [--seconds 20] [--fps 20] [--warmup S] [--interact]
// A still is the engine's still (settled, 120 steps), as `OceanTool still --habitat web`. Frames: warm-up steps
// (at least 1, as OceanTool's FrameRecorder), then 60/fps steps per frame, the script on with --interact, as
// `OceanTool frames --habitat web --warmup S [--interact]`. Prints the page's state and the script's events.
import { mkdirSync } from "node:fs";
import { launch, open } from "./chrome.mjs";

const [cmd, out, ...rest] = process.argv.slice(2);
if (!["still", "frames"].includes(cmd) || !out) throw new Error("usage: capture.mjs still|frames <out> [options]");
const opt = (n, d) => { const i = rest.indexOf(n); return i >= 0 ? rest[i + 1] : d; };
const theme = opt("--theme", "dark"), seed = opt("--seed", "1"), scale = Number(opt("--scale", cmd === "still" ? "2" : "1"));
const W = Number(opt("--w", "1440")), H = Number(opt("--h", "900"));
const browser = await launch();
const page = await open(browser, { w: W, h: H, scale, query: `seed=${seed}&theme=${theme}${cmd === "still" ? "&still=1" : ""}` });
console.error(JSON.stringify(await page.evaluate("({ fontOK: parity.fontOK, draws: parity.draws(), state: parity.state() })")));
const shot = (path) => page.screenshot({ path, clip: { x: 0, y: 0, width: W, height: H } });
if (cmd === "still") {
  await page.evaluate("parity.advance(0, false)");
  await shot(out);
} else {
  mkdirSync(out, { recursive: true });
  const fps = Number(opt("--fps", "20")), seconds = Number(opt("--seconds", "20"));
  const warm = Math.max(1, Math.round(Number(opt("--warmup", "8")) * 60));
  const interact = rest.includes("--interact");
  await page.evaluate(`parity.advance(${warm}, false)`);
  const n = Math.round(seconds * fps);
  for (let i = 0; i < n; i++) {
    await page.evaluate(`parity.advance(${60 / fps}, ${interact})`);
    await shot(`${out}/f${String(i).padStart(4, "0")}.png`);
  }
  console.error(JSON.stringify(await page.evaluate("({ draws: parity.draws(), events: parity.events, state: parity.state() })")));
}
await browser.close();
