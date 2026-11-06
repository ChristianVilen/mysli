import type { ToolId } from "../data/tools";

const ink = "#303333";
let serial = 0;

/** Where each piece rests in the bowl: its centre as a percentage of a 640 × 500 stage, and its tilt in degrees. */
export const restingPlaces: Record<ToolId, { left: number; top: number; turn: number }> = {
	screenshots: { left: 64, top: 50, turn: 13 },
	clipboard: { left: 38, top: 45, turn: -21 },
	windows: { left: 49, top: 40, turn: -8 },
	awake: { left: 26, top: 50, turn: -27 },
	meetings: { left: 74, top: 42, turn: 12 },
};

function specks(seed: number, count: number, bounds: number[], color: string, opacity = 0.3) {
	let value = seed;
	const random = () => {
		value = (value * 16807) % 2147483647;
		return value / 2147483647;
	};
	const [left, top, width, height] = bounds;
	return Array.from({ length: count }, () => {
		const x = left + random() * width;
		const y = top + random() * height;
		const length = 1 + random() * 3;
		return `<path d="M${x.toFixed(1)} ${y.toFixed(1)}l${length.toFixed(1)} -.8" stroke="${color}" opacity="${opacity}" stroke-width=".7"/>`;
	}).join("");
}

function drawing(id: ToolId, key: string) {
	switch (id) {
		case "screenshots":
			return `<defs><clipPath id="${key}-clip"><path d="M39 30 134 25 154 42 149 139 131 154 37 148 24 130 27 47Z"/></clipPath></defs>
      <path d="M36 34 137 29 157 45 153 144 134 158 33 151 20 131 24 44Z" fill="#F7F5ED"/>
      <path d="M39 30 134 25 154 42 149 139 131 154 37 148 24 130 27 47Z" fill="#E6BF64" stroke="${ink}" stroke-width="2" stroke-linejoin="round"/>
      <g clip-path="url(#${key}-clip)">${Array.from({ length: 13 }, (_, i) => `<path d="M${10 + i * 13} 20l-22 146" stroke="#846C35" opacity=".18" stroke-width="1"/>`).join("")}${specks(41, 100, [25, 25, 132, 132], "#645736", 0.33)}</g>
      <path d="M53 70V53h20m35-1h19v19m-1 38v19h-20m-37-1H51v-20" fill="none" stroke="${ink}" stroke-width="5.5" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="m42 34 88-4m20 18-5 89M36 142l85 5" fill="none" stroke="#FFF0B9" stroke-width="2" opacity=".8"/>
      <path d="M57 89 72 84 84 89 96 84 115 89" fill="none" stroke="#9A7B35" stroke-width="1" opacity=".5"/>`;
		case "clipboard":
			return `<g transform="rotate(-20 77 96)"><path d="M43 35C61 15 96 20 110 40c17 27 20 67 3 96-16 25-41 26-60 1C35 115 27 54 43 35Z" fill="#8DA876" stroke="${ink}" stroke-width="1.8"/><path d="M65 36c-9 33-3 72 17 100M45 59l23 14m-27 8 31 13m-26 9 33 11m12-68L67 66m34 1L70 88m36 0-32 24" fill="none" stroke="#536F48" stroke-width="1.1" opacity=".65"/></g>
      <g transform="rotate(14 103 89)"><path d="M64 27C86 10 122 21 136 49c13 27 9 59-8 87-15 23-43 26-59 4C51 116 45 48 64 27Z" fill="#B5CC98" stroke="${ink}" stroke-width="1.7"/><path d="M91 29c-9 25-6 70 14 108M68 49 86 62m-25 5 27 15m-24 5 28 17m-24 1 31 18m25-79L88 64m42 0L89 84m44-1-39 22m31 0-25 20" fill="none" stroke="#66834D" stroke-width="1"/><path d="M69 35c-9 11-11 31-10 44" fill="none" stroke="#E9F0D4" stroke-width="2"/>${specks(23, 65, [59, 27, 80, 118], "#617B4F", 0.3)}</g>`;
		case "windows":
			return `<path d="M21 44 150 34 161 139 32 150Z" fill="#F7F7F2"/>
      <path d="M24 39 150 32 157 137 31 146Z" fill="#A9C1D2" stroke="${ink}" stroke-width="2" stroke-linejoin="round"/>
      <path d="M34 47 87 44 90 131 40 136Z" fill="#D0DFE7"/><path d="M97 43 141 39 147 127 101 132Z" fill="#789DB7"/>
      <path d="m91 35 8 102M28 63l122-7" fill="none" stroke="${ink}" stroke-width="2.6"/>
      <path d="m39 82 35-2m-34 9 27-2m-27 10 32-2m37-17 26-2m-26 10 28-2" stroke="#3A5E76" stroke-width="1.2" opacity=".5"/>
      <path d="m32 38 109-6m-99 110 108-10" fill="none" stroke="#EDF4F5" stroke-width="1.6"/>
      <g opacity=".3">${specks(72, 60, [32, 40, 114, 91], "#324C5B", 0.5)}</g>
      <circle cx="40" cy="52" r="2" fill="#536775"/><circle cx="49" cy="51.5" r="2" fill="#536775"/>`;
		case "awake":
			return `<path d="M32 55C47 24 89 13 123 30c38 18 48 58 24 89-22 30-65 44-99 25C14 126 11 90 32 55Z" fill="#F4F4EE"/>
      <path d="M30 51C48 21 87 14 122 31c35 17 45 55 21 86-23 30-64 43-97 25C15 125 11 85 30 51Z" fill="#855C43" stroke="${ink}" stroke-width="2"/>
      <path d="M125 33c-8 23-42 26-53 46-15 28 15 36-22 61" fill="none" stroke="#493023" stroke-width="7" stroke-linecap="round"/>
      <path d="M119 34c-7 24-39 29-46 48-8 22 4 35-22 52" fill="none" stroke="#BA9673" stroke-width="2" opacity=".85"/>
      <path d="M34 59c-14 22-12 40-2 54m10-64-8 15m108 26c-8 24-20 32-40 43" fill="none" stroke="#DBC2A0" stroke-width="1.4" opacity=".8"/>
      ${specks(90, 75, [30, 39, 108, 91], "#DFC5A4", 0.3)}`;
		case "meetings":
			return `<path d="M46 40C72 12 122 17 144 52c22 34 14 76-22 96-37 21-83 4-95-29C13 84 22 58 46 40Z" fill="#F7EDEB"/>
      <path d="M42 38C71 14 119 18 141 49c25 34 16 76-19 96-33 20-79 8-95-24C10 87 17 60 42 38Z" fill="#C95362" stroke="${ink}" stroke-width="2"/>
      <path d="M44 48C28 68 27 92 35 110" fill="none" stroke="#F2B1AA" stroke-width="5" stroke-linecap="round"/>
      <path d="M50 36c24-12 56-9 73 7m12 72c-11 18-33 27-53 27" fill="none" stroke="#8D3143" stroke-width="1.5" opacity=".6"/>
      <path d="M71 24 74 12 85 22 97 10 100 26 115 28 99 37 89 33 78 39 72 31Z" fill="#879C7D" stroke="${ink}" stroke-width="1.6" stroke-linejoin="round"/>
      ${specks(54, 75, [37, 45, 98, 90], "#752D3E", 0.27)}
      <path d="M59 72c4-2 8 0 6 4m24 31c3-3 7-1 6 3m22-37c3 0 4 3 2 5m-59 43c2-3 7-3 7 1" fill="none" stroke="#F8C5B6" stroke-width="1.5"/>`;
	}
}

/** A paper cutout of one tool's ingredient, as an SVG string. */
export function pieceArt(id: ToolId) {
	const key = `piece-${++serial}`;
	const rough = `<filter id="${key}-rough" x="-10%" y="-10%" width="120%" height="120%"><feTurbulence type="fractalNoise" baseFrequency=".042" numOctaves="2" seed="7" result="noise"/><feDisplacementMap in="SourceGraphic" in2="noise" scale=".8"/></filter>`;
	return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 180 180" aria-hidden="true" focusable="false"><defs>${rough}</defs><g filter="url(#${key}-rough)">${drawing(id, key)}</g></svg>`;
}

/**
 * The porcelain bowl. The page draws it twice: "back" behind the pieces, and "front"
 * over them. The front copy shows only what lies below the near edge of the rim, so
 * the pieces look as if they sit inside the bowl.
 */
export function bowlArt(layer: "back" | "front") {
	const key = `bowl-${++serial}`;
	// The arc is the front half of the inner rim ellipse drawn below (cx 320, cy 190, rx 231, ry 50).
	const rim = `<clipPath id="${key}-rim"><path d="M0 190H89A231 50 0 0 0 551 190H640V460H0Z"/></clipPath>`;
	const defs = `<defs><linearGradient id="${key}-body" x1="0" y1="0" x2=".25" y2="1"><stop stop-color="#FAFAF7"/><stop offset=".55" stop-color="#E9ECEB"/><stop offset="1" stop-color="#C8CFD0"/></linearGradient><radialGradient id="${key}-inside"><stop stop-color="#F9FAF8"/><stop offset=".78" stop-color="#E5E9E7"/><stop offset="1" stop-color="#C7CECC"/></radialGradient><filter id="${key}-shadow"><feGaussianBlur stdDeviation="8"/></filter>${layer === "front" ? rim : ""}</defs>`;
	const glaze = Array.from({ length: 18 }, (_, i) => {
		const x = 135 + i * 21;
		const y = 320 + Math.sin((i / 17) * Math.PI) * 39;
		return `<path d="m${x} ${y} 3 8" stroke="#667A80" opacity=".28" stroke-width=".8"/>`;
	}).join("");
	const shadow = `<ellipse class="bowl-shadow" cx="321" cy="394" rx="230" ry="19" filter="url(#${key}-shadow)"/>`;
	const body = `<path d="M61 193C77 304 164 377 318 381c153 4 245-78 260-187Z" fill="#F9F9F3"/>
    <path d="M66 193c17 111 103 180 253 183 147 3 239-73 255-182" fill="url(#${key}-body)" stroke="#414A4A" stroke-width="2.2" stroke-linejoin="round"/>
    <path d="M81 232c36 92 116 136 238 137 121 0 200-45 238-134" fill="none" stroke="#8B9696" stroke-width="1" opacity=".55"/>
    <path d="M111 269c38 55 113 85 208 87m34-1c89-5 151-39 184-84" fill="none" stroke="#FAFCF8" stroke-width="3" opacity=".8"/>
    <path d="M64 193c0-38 108-71 254-72 146-2 258 29 258 69 0 41-112 72-257 73-143 0-255-30-255-70Z" fill="#F4F5F0" stroke="#343D3D" stroke-width="2.1"/>
    <ellipse cx="320" cy="190" rx="231" ry="50" fill="url(#${key}-inside)" stroke="#A8B3B1" stroke-width="1.2"/>
    <path d="M89 193c4-28 98-51 230-51 131-1 226 20 231 47" fill="none" stroke="#FCFEFA" stroke-width="4"/>
    <path d="M77 213c42 29 127 45 242 45 114 0 209-19 244-45" fill="none" stroke="#67859B" stroke-width="2"/>
    <path d="M93 226c48 26 133 41 224 40 99 0 181-15 227-38" fill="none" stroke="#829DAE" stroke-width=".7" opacity=".7"/>
    ${glaze}
    <text x="276" y="338" fill="#70868B" style="font-family: var(--font-hand)" font-size="34" letter-spacing="1" transform="rotate(-3 320 330)" opacity=".8">mysli</text>`;
	const content = layer === "front" ? `<g clip-path="url(#${key}-rim)">${body}</g>` : shadow + body;
	return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 640 460" aria-hidden="true" focusable="false">${defs}${content}</svg>`;
}
