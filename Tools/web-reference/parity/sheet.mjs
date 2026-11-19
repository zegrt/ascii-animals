// Chrome's glyph sheet: every GlyphAtlas glyph drawn white on black in its own 12 x 17 cell, as renderer.ts draws
// (600 13px Geist Mono, centred, textBaseline "middle" at ch/2 + 1), at 1x and 2x.
//   node sheet.mjs <out dir>   → <out dir>/sheet-chrome-1x.png, sheet-chrome-2x.png (then sheet-boxes.py)
import { mkdirSync } from "node:fs";
import { launch, open } from "./chrome.mjs";

const out = process.argv[2] ?? ".";
mkdirSync(out, { recursive: true });
// GlyphAtlas.glyphs, in order.
const glyphs = [":", ";", "t", "%", "S", "X", "8", "#", "@", ".", "'", ",", "`", "o", "-", "*", "·", "¯", "_", "/", "\\", "|", "+", "x", "O", "°", "v", "0"];
const browser = await launch();
for (const dpr of [1, 2]) {
  const page = await open(browser, { w: 400, h: 40, scale: dpr, query: "seed=1&still=1" });
  await page.evaluate((glyphs, dpr) => {
    document.body.innerHTML = "";
    const c = document.createElement("canvas");
    c.width = 12 * glyphs.length * dpr;
    c.height = 17 * dpr;
    c.style.cssText = `position:fixed;left:0;top:0;width:${12 * glyphs.length}px;height:17px`;
    document.body.appendChild(c);
    const g = c.getContext("2d", { alpha: false });
    g.fillStyle = "#000";
    g.fillRect(0, 0, c.width, c.height);
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    g.font = `600 13px "Geist Mono", ui-monospace, Menlo, monospace`;
    g.textAlign = "center";
    g.textBaseline = "middle";
    g.fillStyle = "#fff";
    glyphs.forEach((s, i) => g.fillText(s, i * 12 + 6, 17 / 2 + 1));
  }, glyphs, dpr);
  await page.screenshot({ path: `${out}/sheet-chrome-${dpr}x.png`, clip: { x: 0, y: 0, width: 12 * glyphs.length, height: 17 } });
}
await browser.close();
