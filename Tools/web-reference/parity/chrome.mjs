// Shared by the parity scripts: puppeteer-core (resolved from the current directory, where it is installed, so these
// scripts can stay in the repo) and the Chrome to drive (CHROME, default: Google Chrome's usual macOS path), and the
// page's base URL (PARITY_URL, default the patched clone's vite dev server on :5199).
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";

const require = createRequire(pathToFileURL(process.cwd() + "/").href);
const { default: puppeteer } = await import(pathToFileURL(require.resolve("puppeteer-core")).href);

export const BASE = process.env.PARITY_URL ?? "http://localhost:5199";
export const launch = () =>
  puppeteer.launch({
    executablePath: process.env.CHROME ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    headless: true,
    args: ["--hide-scrollbars"],
  });

/** A page of the parity reference, ready (the webfont loaded, the wall laid out). */
export async function open(browser, { w, h, scale, query }) {
  const page = await browser.newPage();
  await page.setViewport({ width: w, height: h, deviceScaleFactor: scale });
  page.on("pageerror", (e) => console.error("pageerror:", e.message));
  await page.goto(`${BASE}/parity.html?${query}`, { waitUntil: "networkidle0" });
  await page.waitForFunction("window.parityReady === true", { timeout: 30000 });
  return page;
}
