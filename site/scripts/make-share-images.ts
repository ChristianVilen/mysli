// Draws the link preview card and the home screen icon into site/public with headless Chrome.
// Run it again after the bowl art, the pieces or the tagline change:
//   node site/scripts/make-share-images.ts
// It needs Google Chrome (set CHROME to use another binary), macOS sips, and network access for the fonts.

import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { grain } from "../src/art/paper.ts";
import { bowlArt, pieceArt, restingPlaces } from "../src/art/pieces.ts";
import { description, headline } from "../src/data/copy.ts";

const chrome = process.env.CHROME ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const publicFolder = fileURLToPath(new URL("../public/", import.meta.url));
const work = mkdtempSync(path.join(tmpdir(), "mysli-share-"));
const appIcon = readFileSync(path.join(publicFolder, "mysli.svg"), "utf8");
const fonts =
	"https://fonts.googleapis.com/css2?family=Caveat:wght@500;600&family=DM+Sans:opsz,wght@9..40,400;9..40,650;9..40,700&display=block";

const made: string[] = [];

function screenshot(name: string, html: string, width: number, height: number) {
	const page = path.join(work, `${name}.html`);
	const image = path.join(work, `${name}.png`);
	made.push(page, image);
	writeFileSync(page, html);
	execFileSync(chrome, [
		"--headless=new",
		"--hide-scrollbars",
		"--force-device-scale-factor=1",
		`--window-size=${width},${height}`,
		"--virtual-time-budget=5000",
		`--screenshot=${image}`,
		`file://${page}`,
	]);
	return image;
}

const pieces = Object.entries(restingPlaces)
	.map(
		([id, place]) =>
			`<div class="piece" style="left:${place.left}%;top:${place.top}%;transform:translate(-50%,-50%) rotate(${place.turn}deg)">${pieceArt(id as keyof typeof restingPlaces)}</div>`,
	)
	.join("");

const card = `<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="${fonts}"><style>
:root { --font-hand: "Caveat", cursive; }
* { box-sizing: border-box; margin: 0; }
html, body { width: 1200px; height: 630px; overflow: hidden; }
body { position: relative; background: #f7f7f5 ${grain}; color: #272b2c; font-family: "DM Sans", sans-serif; -webkit-font-smoothing: antialiased; }
.copy { position: absolute; left: 76px; top: 66px; width: 520px; }
.brand { display: flex; align-items: center; gap: 14px; font-size: 34px; font-weight: 700; letter-spacing: -0.055em; }
.brand svg { width: 52px; height: 52px; padding: 2px; background: #f5f5f7; border-radius: 14px; box-shadow: 0 1px 3px #0000002a; }
.dot, .stop { color: #b72d48; }
.note { margin-top: 58px; font: 500 34px/1 Caveat, cursive; color: #687a82; transform: rotate(-3deg); transform-origin: left; }
h1 { margin-top: 18px; font-size: 90px; font-weight: 650; line-height: 0.98; letter-spacing: -0.06em; }
.mark { display: block; width: 300px; height: 20px; margin-top: 12px; color: #b72d48; overflow: visible; }
.mark path { fill: none; stroke: currentColor; stroke-width: 2; stroke-linecap: round; }
.description { width: 470px; margin-top: 24px; font-size: 25px; line-height: 1.5; color: #596264; }
.stage { position: absolute; right: 44px; top: 70px; width: 600px; aspect-ratio: 640 / 500; }
.wash { position: absolute; inset: 15% 1% 5%; background: radial-gradient(ellipse, #8cabb321 0%, transparent 70%); }
.bowl { position: absolute; left: 0; bottom: 0; width: 100%; }
.bowl svg { display: block; width: 100%; height: auto; }
.bowl-shadow { fill: #1e2a2d1f; }
.piece { position: absolute; width: 23%; aspect-ratio: 1; filter: drop-shadow(3px 8px 4px #25353b29); }
.piece svg { display: block; width: 100%; height: 100%; overflow: visible; }
.caption { position: absolute; left: 18%; bottom: -3%; font: 500 34px/1 Caveat, cursive; color: #687a82; transform: rotate(-3deg); }
</style></head><body>
<div class="copy">
<div class="brand">${appIcon}<span>Mysli<span class="dot">.</span></span></div>
<p class="note">A little of everything you need.</p>
<h1>${headline[0]}<br>${headline[1]}<span class="stop">.</span></h1>
<svg class="mark" viewBox="0 0 300 20"><path d="M4 12C67 3 148 5 296 8M36 17c93-6 175-5 236-4"/></svg>
<p class="description">${description}</p>
</div>
<div class="stage"><div class="wash"></div><div class="bowl">${bowlArt("back")}</div>${pieces}<div class="bowl">${bowlArt("front")}</div><p class="caption">a mix of good things.</p></div>
</body></html>`;

const icon = `<!doctype html><html><head><meta charset="utf-8"><style>
* { margin: 0; }
html, body { width: 180px; height: 180px; overflow: hidden; background: #f5f5f7; }
svg { display: block; width: 180px; height: 180px; }
</style></head><body>${appIcon}</body></html>`;

try {
	const cardImage = screenshot("share-card", card, 1200, 630);
	execFileSync("sips", [
		"-s",
		"format",
		"jpeg",
		"-s",
		"formatOptions",
		"88",
		cardImage,
		"--out",
		path.join(publicFolder, "share-card.jpg"),
	]);
	const iconImage = screenshot("apple-touch-icon", icon, 180, 180);
	writeFileSync(path.join(publicFolder, "apple-touch-icon.png"), readFileSync(iconImage));
	console.log("Wrote site/public/share-card.jpg and site/public/apple-touch-icon.png.");
} finally {
	for (const file of made) rmSync(file, { force: true });
	rmdirSync(work);
}
