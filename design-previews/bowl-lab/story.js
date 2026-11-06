import { ingredients, art, bowl } from "./art.js";

const chapters = [...document.querySelectorAll(".chapter")];
const navigation = document.querySelector("#chapter-nav");
const cloud = document.querySelector("#ingredient-cloud");
const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
const captions = [
	"A moment, saved.",
	"There it is.",
	"Everything in its place.",
	"A little more time.",
	"A good conversation, kept.",
];
const shortNames = ["Capture", "Clipboard", "Windows", "Awake", "Meetings"];
const positions = [
	[-51, 31, -18],
	[32, 16, 15],
	[76, 53, -8],
	[-12, 73, 23],
	[48, 78, -20],
];
let current = -1;
let pending = false;

document.querySelector("#bowl-art").innerHTML = bowl({ top: false });
ingredients.forEach((ingredient, index) => {
	const button = document.createElement("button");
	button.type = "button";
	button.innerHTML = `<span aria-hidden="true"></span>${shortNames[index]}`;
	button.style.setProperty("--ingredient-color", ingredient.color);
	button.setAttribute("aria-controls", ingredient.id);
	button.addEventListener("click", () => {
		document
			.getElementById(ingredient.id)
			.scrollIntoView({
				behavior: reducedMotion.matches ? "instant" : "smooth",
				block: "start",
			});
	});
	navigation.append(button);
	const piece = document.createElement("div");
	piece.className = "flying-ingredient";
	piece.innerHTML = art(ingredient.id);
	cloud.append(piece);
});

const pieces = [...cloud.children];
const buttons = [...navigation.children];
const waveform = document.querySelector(".waveform");
[
	6, 12, 8, 20, 28, 14, 22, 10, 17, 25, 12, 7, 19, 29, 17, 10, 21, 15, 8, 12,
	24, 18, 9, 5, 12, 20, 11, 7, 16, 23, 14, 8,
].forEach((height) => {
	const bar = document.createElement("i");
	bar.style.height = `${height}px`;
	waveform.append(bar);
});

const demoObserver = new ResizeObserver((entries) => {
	entries.forEach(({ target, contentRect }) => {
		target.style.setProperty(
			"--demo-scale",
			String(Math.min(1, contentRect.width / 430)),
		);
	});
});
document.querySelectorAll(".feature-demo").forEach((demo) => {
	const canvas = document.createElement("div");
	canvas.className = "demo-canvas";
	canvas.append(...demo.childNodes);
	demo.append(canvas);
	demo.style.setProperty(
		"--demo-height",
		demo.classList.contains("meeting-demo") ? "335px" : "310px",
	);
	demo.style.setProperty(
		"--demo-scale",
		String(Math.min(1, demo.clientWidth / 430)),
	);
	demoObserver.observe(demo);
});

function draw() {
	pending = false;
	const viewport = innerHeight;
	const compact = innerWidth <= 720;
	let nearest = 0;
	let distance = Infinity;
	const activity = chapters.map((chapter, index) => {
		const box = chapter.getBoundingClientRect();
		const focus = compact ? 170 : viewport * 0.4;
		const delta = Math.abs(box.top + (compact ? 90 : 210) - focus);
		if (delta < distance) {
			distance = delta;
			nearest = index;
		}
		const progress = Math.min(
			1,
			Math.max(0, (viewport * 0.9 - box.top) / (viewport * 0.72)),
		);
		chapter.style.setProperty(
			"--scene",
			reducedMotion.matches ? 1 : progress.toFixed(3),
		);
		return Math.max(
			0,
			1 - Math.abs(box.top + 220 - viewport * 0.45) / (viewport * 0.8),
		);
	});

	if (current !== nearest) {
		current = nearest;
		buttons.forEach((button, index) =>
			button.setAttribute("aria-current", String(index === current)),
		);
		if (compact)
			navigation.scrollTo({
				left: buttons[current].offsetLeft - navigation.offsetLeft - 20,
				behavior: reducedMotion.matches ? "instant" : "smooth",
			});
		document.querySelector("#current-chapter").textContent = String(
			current + 1,
		);
		document.querySelector("#bowl-caption").textContent = captions[current];
	}

	pieces.forEach((piece, index) => {
		const [baseX, baseY, rotation] = positions[index];
		const flight = reducedMotion.matches
			? index === current
				? 0.8
				: 0
			: activity[index];
		const factor = compact ? 0.34 : innerWidth <= 1020 ? 0.72 : 1;
		const x = (baseX + flight * (index % 2 ? 135 : 105)) * factor;
		const y = (baseY - Math.sin((flight * Math.PI) / 2) * 205) * factor;
		piece.style.transform = `translate(${x}px, ${y}px) rotate(${rotation + flight * (index % 2 ? 32 : -38)}deg) scale(${0.83 + flight * 0.25})`;
		piece.style.zIndex = index === current ? "6" : String(index + 1);
	});
	const line = document.querySelector(".flight-lines");
	line.style.opacity = reducedMotion.matches
		? "0"
		: String(0.2 + activity[current] * 0.6);
}

function scheduleDraw() {
	if (!pending) {
		pending = true;
		requestAnimationFrame(draw);
	}
}

addEventListener("scroll", scheduleDraw, { passive: true });
addEventListener("resize", scheduleDraw);
reducedMotion.addEventListener("change", scheduleDraw);
draw();
