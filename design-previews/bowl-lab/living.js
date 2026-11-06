import { ingredients, art, bowl } from "./art.js";
import { move } from "./motion.js";

const stage = document.getElementById("bowl-stage");
const layer = document.getElementById("ingredients");
const index = document.getElementById("ingredient-index");
const intro = document.getElementById("intro");
const sheet = document.getElementById("feature-sheet");
const reduce = matchMedia("(prefers-reduced-motion:reduce)");
const positions = {
	screenshots: { left: 64, top: 47, r: 13 },
	clipboard: { left: 38, top: 42, r: -21 },
	windows: { left: 49, top: 37, r: -8 },
	awake: { left: 26, top: 48, r: -27 },
	meetings: { left: 74, top: 40, r: 12 },
};
const buttons = new Map();
let selected = null;
let returnFocus = null;
let entrance = 0;
let paperAnimation = null;
let pencilAnimations = [];
document.getElementById("bowl-back").innerHTML = bowl();
document.getElementById("bowl-lip").innerHTML = bowl();

for (const item of ingredients) {
	const position = positions[item.id];
	const piece = document.createElement("button");
	piece.type = "button";
	piece.className = "ingredient-piece";
	piece.style.left = position.left + "%";
	piece.style.top = position.top + "%";
	piece.dataset.id = item.id;
	piece.setAttribute("aria-label", "Explore " + item.name);
	piece.setAttribute("aria-pressed", "false");
	piece.innerHTML =
		art(item.id) + '<span class="piece-label">' + item.name + "</span>";
	piece.addEventListener("click", (event) =>
		select(item.id, event.currentTarget),
	);
	piece.addEventListener("pointerenter", () => {
		if (!selected) move(piece, { y: -17, r: position.r + 4, s: 1.07 });
	});
	piece.addEventListener("pointerleave", () => layout());
	piece.addEventListener("focus", () => {
		if (!selected) move(piece, { y: -12, r: position.r + 2, s: 1.05 });
	});
	piece.addEventListener("blur", () => layout());
	layer.append(piece);
	buttons.set(item.id, piece);
	move(piece, { x: 0, y: 0, r: position.r, s: 1 }, { immediate: true });
	const label = document.createElement("button");
	label.type = "button";
	label.style.setProperty("--piece-color", item.color);
	label.textContent = item.name;
	label.dataset.id = item.id;
	label.setAttribute("aria-pressed", "false");
	label.addEventListener("click", (event) =>
		select(item.id, event.currentTarget),
	);
	index.append(label);
}

function layout(immediate = false) {
	const bounds = stage.getBoundingClientRect();
	for (const [id, element] of buttons) {
		const home = positions[id];
		const active = selected === id;
		element.classList.toggle("is-selected", active);
		element.setAttribute("aria-pressed", String(active));
		const x = active
			? bounds.width * (0.5 - home.left / 100)
			: selected
				? home.left > 50
					? 8
					: -8
				: 0;
		const y = active
			? bounds.height * (0.15 - home.top / 100)
			: selected
				? 8
				: 0;
		move(
			element,
			{ x, y, r: active ? -4 : home.r, s: active ? 1.33 : selected ? 0.96 : 1 },
			{ immediate },
		);
	}
	index
		.querySelectorAll("button")
		.forEach((button) =>
			button.setAttribute(
				"aria-pressed",
				String(button.dataset.id === selected),
			),
		);
	stage.classList.toggle("has-selection", Boolean(selected));
}

function demoMarkup(id) {
	if (id === "screenshots")
		return '<div class="demo-landscape"><span class="demo-sun"></span><span class="capture-rectangle"></span></div><div class="demo-bottom"><button class="demo-button" data-demo="capture">Capture a little bit</button><span class="demo-status" data-status>Just the useful bit.</span></div>';
	if (id === "clipboard")
		return '<div class="clipboard-stack"><div class="clipboard-slip">The link you meant to keep.</div><div class="clipboard-slip">An idea worth another look.</div><div class="clipboard-slip">That thing you just copied.</div></div><div class="demo-bottom"><button class="demo-button" data-demo="clipboard">Find it again</button><span class="demo-status" data-status>Never far away.</span></div>';
	if (id === "windows")
		return '<div class="tiny-windows"><div class="tiny-window"><span></span><span></span><span></span></div><div class="tiny-window"><span></span><span></span></div></div><div class="demo-bottom"><button class="demo-button" data-demo="windows">Give it more room</button><span class="demo-status" data-status>Nice and tidy.</span></div>';
	if (id === "awake")
		return '<div class="awake-demo"><div class="awake-dial">1h</div><div class="awake-text"><strong>A little longer.</strong>Your build can finish.<br>You can get a coffee.</div></div><div class="demo-bottom"><button class="demo-button" data-demo="awake">Keep it awake</button><span class="demo-status" data-status>Take your time.</span></div>';
	return '<div class="meeting-transcript"><strong>ME / 12:10</strong><br>Let\'s keep the simpler version.<br><strong>THEM / 12:18</strong><br>I\'ll send the sketch today.</div><div class="meeting-note">A good decision, remembered.</div><div class="demo-bottom"><button class="demo-button" data-demo="meetings">Keep a note</button><span class="demo-status" data-status>Stay in the conversation.</span></div>';
}

function renderSheet(item) {
	sheet.hidden = false;
	intro.hidden = true;
	sheet.innerHTML =
		'<button type="button" class="sheet-back">Back to the whole mix</button><h2>' +
		item.name +
		'</h2><p class="handwritten">' +
		item.tag +
		'</p><p class="feature-description">' +
		item.description +
		'</p><div class="mini-demo">' +
		demoMarkup(item.id) +
		'</div><p class="sheet-foot">A little preview of life with Mysli.</p>';
	sheet
		.querySelector(".sheet-back")
		.addEventListener("click", () => close(true));
	const demo = sheet.querySelector(".mini-demo");
	const action = sheet.querySelector("[data-demo]");
	action.addEventListener("click", () => {
		const active = action.getAttribute("aria-pressed") === "true";
		action.setAttribute("aria-pressed", String(!active));
		if (item.id === "screenshots") {
			demo.classList.toggle("is-captured", !active);
			action.textContent = active ? "Capture a little bit" : "Try another";
			demo.querySelector("[data-status]").textContent = active
				? "Just the useful bit."
				: "Captured!";
		}
		if (item.id === "clipboard") {
			const slip = demo.querySelector(".clipboard-slip:last-child");
			slip.animate(
				reduce.matches
					? [{ opacity: 0.5 }, { opacity: 1 }]
					: [
							{ transform: "translateY(0) rotate(-1deg)" },
							{ transform: "translateY(-44px) rotate(4deg)", offset: 0.5 },
							{ transform: "translateY(0) rotate(-1deg)" },
						],
				{
					duration: reduce.matches ? 1 : 600,
					easing: "cubic-bezier(.2,.7,.2,1)",
				},
			);
			demo.querySelector("[data-status]").textContent = "There it is.";
		}
		if (item.id === "windows") {
			demo.classList.toggle("is-full", !active);
			action.textContent = active ? "Give it more room" : "Two windows again";
		}
		if (item.id === "awake") {
			demo.querySelector(".awake-dial").textContent = active ? "1h" : "60:00";
			action.textContent = active ? "Keep it awake" : "Let it rest";
			demo.querySelector("[data-status]").textContent = active
				? "Take your time."
				: "Wide awake.";
		}
		if (item.id === "meetings") {
			const note = demo.querySelector(".meeting-note");
			note.textContent = active
				? "A good decision, remembered."
				: "12:25  Keep the simpler version.";
			note.animate(
				reduce.matches
					? [{ opacity: 0.5 }, { opacity: 1 }]
					: [
							{ transform: "translateY(7px) rotate(-5deg)", opacity: 0.3 },
							{ transform: "translateY(0) rotate(-2deg)", opacity: 1 },
						],
				{
					duration: reduce.matches ? 1 : 350,
					easing: "cubic-bezier(.2,.8,.2,1)",
				},
			);
			demo.querySelector("[data-status]").textContent = active
				? "Stay in the conversation."
				: "Noted.";
		}
	});
	paperAnimation?.cancel();
	paperAnimation = sheet.animate(
		reduce.matches
			? [{ opacity: 0.7 }, { opacity: 1 }]
			: [
					{ opacity: 0, transform: "translate(18px,12px) rotate(2deg)" },
					{ opacity: 1, transform: "translate(0,0) rotate(0)" },
				],
		{
			duration: reduce.matches ? 1 : 430,
			easing: "cubic-bezier(.16,.8,.25,1)",
		},
	);
}

function select(id, trigger) {
	entrance++;
	if (selected === id) {
		close();
		return;
	}
	selected = id;
	returnFocus = trigger;
	renderSheet(ingredients.find((item) => item.id === id));
	layout();
	sheet.querySelector(".sheet-back").focus({ preventScroll: true });
}

function close(restoreFocus = false) {
	const previous = selected;
	selected = null;
	paperAnimation?.cancel();
	sheet.hidden = true;
	intro.hidden = false;
	intro.animate(
		reduce.matches
			? [{ opacity: 0.7 }, { opacity: 1 }]
			: [
					{ opacity: 0, transform: "translateY(7px)" },
					{ opacity: 1, transform: "translateY(0)" },
				],
		{ duration: reduce.matches ? 1 : 250 },
	);
	layout();
	if (restoreFocus && previous)
		(returnFocus?.isConnected ? returnFocus : buttons.get(previous)).focus({
			preventScroll: true,
		});
}

function assemble() {
	close();
	const run = ++entrance;
	pencilAnimations.forEach((animation) => animation.cancel());
	pencilAnimations = [];
	if (reduce.matches) {
		layout(true);
		return;
	}
	const width = stage.getBoundingClientRect().width;
	document
		.querySelectorAll(".scribbles path, .headline-mark path")
		.forEach((path, i) => {
			const length = path.getTotalLength();
			path.style.strokeDasharray = String(length);
			pencilAnimations.push(
				path.animate([{ strokeDashoffset: length }, { strokeDashoffset: 0 }], {
					duration: 650,
					delay: 240 + i * 27,
					easing: "cubic-bezier(.22,.7,.25,1)",
					fill: "backwards",
				}),
			);
		});
	ingredients.forEach((item, i) => {
		const element = buttons.get(item.id);
		const home = positions[item.id];
		move(
			element,
			{
				x: (i - 2) * width * 0.15,
				y: -width * 0.52 - 60,
				r: home.r + (i % 2 ? 40 : -30),
				s: 0.75,
			},
			{ immediate: true },
		);
		setTimeout(
			() => {
				if (run === entrance) move(element, { x: 0, y: 0, r: home.r, s: 1 });
			},
			80 + i * 95,
		);
	});
	setTimeout(() => {
		if (run !== entrance || reduce.matches) return;
		document
			.querySelectorAll(".bowl-art")
			.forEach((element) =>
				element.animate(
					[
						{ transform: "translateY(0) rotate(0)" },
						{ transform: "translateY(2px) rotate(.25deg)", offset: 0.4 },
						{ transform: "translateY(0) rotate(0)" },
					],
					{ duration: 360, easing: "ease-out" },
				),
			);
	}, 1050);
}

document.getElementById("replay-mix").addEventListener("click", assemble);
document
	.getElementById("meet-mix")
	.addEventListener("click", (event) =>
		select("screenshots", event.currentTarget),
	);
document.addEventListener("keydown", (event) => {
	if (event.key === "Escape" && selected) close(true);
});
new ResizeObserver(() => layout(true)).observe(stage);
reduce.addEventListener("change", () => {
	entrance++;
	pencilAnimations.forEach((animation) => animation.cancel());
	layout(true);
});
requestAnimationFrame(() => requestAnimationFrame(assemble));
