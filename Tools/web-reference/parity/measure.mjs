// Chrome's metrics for the page's font: measureText("|") at 13 and 26 px with the alphabetic and middle baselines,
// and which Geist Mono faces the page loaded.   node measure.mjs
import { launch, open } from "./chrome.mjs";

const browser = await launch();
const page = await open(browser, { w: 400, h: 40, scale: 1, query: "seed=1&still=1" });
console.log(JSON.stringify(await page.evaluate(() => {
  const c = document.createElement("canvas").getContext("2d");
  const out = {};
  for (const px of [13, 26]) {
    c.font = `600 ${px}px "Geist Mono"`;
    out[px] = {};
    for (const base of ["alphabetic", "middle"]) {
      c.textBaseline = base;
      const m = c.measureText("|");
      out[px][base] = { fontAscent: m.fontBoundingBoxAscent, fontDescent: m.fontBoundingBoxDescent,
        inkAscent: m.actualBoundingBoxAscent, inkDescent: m.actualBoundingBoxDescent, width: m.width };
    }
  }
  return { metrics: out, fonts: [...document.fonts].map((f) => `${f.family} ${f.weight} ${f.status} ${f.unicodeRange}`) };
}), null, 1));
await browser.close();
