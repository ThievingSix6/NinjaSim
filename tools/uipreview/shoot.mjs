// Renders UI dumps (from the playtest's SCENARIO=uishots run) to PNG screenshots.
//   node shoot.mjs <dumpDir> <outDir> [name ...]
// Needs Playwright's Chromium; images named in assets.json (rbxassetid -> local file) are drawn too.
import { createRequire } from "module";
import { execSync } from "child_process";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const require = createRequire(import.meta.url);
const globalRoot = execSync("npm root -g").toString().trim();
const { chromium } = require(path.join(globalRoot, "playwright"));

const here = path.dirname(fileURLToPath(import.meta.url));
const [dumpDir = "/tmp/claude-0/uishots", outDir = path.join(here, "out"), ...only] = process.argv.slice(2);
fs.mkdirSync(outDir, { recursive: true });

// rbxassetid -> { url, w, h } for images the preview can show (e.g. the icon atlas)
const assets = {};
const assetFile = process.env.UIPREVIEW_ASSETS || path.join(here, "assets.json");
if (fs.existsSync(assetFile)) {
  for (const [id, a] of Object.entries(JSON.parse(fs.readFileSync(assetFile, "utf8")))) {
    const file = path.resolve(path.dirname(assetFile), a.file);
    if (fs.existsSync(file)) assets[id] = { url: "file://" + file, w: a.w, h: a.h };
  }
}

const browser = await chromium.launch({ executablePath: "/opt/pw-browsers/chromium-1194/chrome-linux/chrome" }).catch(() => chromium.launch());
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
await page.goto("file://" + path.join(here, "render.html"));
await page.evaluate(() => document.fonts.ready);
const files = fs.readdirSync(dumpDir).filter(f => f.endsWith(".json")).filter(f => !only.length || only.includes(f.replace(".json", "")));
for (const f of files) {
  const shot = JSON.parse(fs.readFileSync(path.join(dumpDir, f), "utf8"));
  await page.evaluate(([s, a]) => window.renderShot(s, a), [shot, assets]);
  await page.evaluate(() => document.fonts.ready);
  const out = path.join(outDir, f.replace(".json", ".png"));
  await page.screenshot({ path: out });
  console.log("wrote", out);
}
await browser.close();
