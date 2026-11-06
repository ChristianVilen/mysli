import { ingredients, art, bowl } from "./art.js";

const pantry = document.querySelector("#ingredient-list");
const slots = document.querySelector("#bowl-slots");
const receipt = document.querySelector("#receipt-items");
const selected = new Set();
const flights = new Map();
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
const copies = {
	screenshots: ["Screenshots", "Capture a little clarity"],
	clipboard: ["Clipboard history", "Keep the things you copy"],
	windows: ["Window tiling", "Give every window a place"],
	awake: ["Keep awake", "Stay on while you need it"],
	meetings: ["Meeting notes", "Record. Transcribe. Summarise."],
};

document.querySelector("#bowl-art").innerHTML = bowl({ top: true });

for (const [index, ingredient] of ingredients.entries()) {
	const [name, detail] = copies[ingredient.id] || [
		ingredient.name,
		ingredient.description,
	];
	const button = document.createElement("button");
	button.type = "button";
	button.className = "ingredient";
	button.dataset.id = ingredient.id;
	button.setAttribute("aria-pressed", "false");
	button.innerHTML = `<span class="ingredient-art" aria-hidden="true">${art(ingredient.id)}</span><span class="ingredient-text"><span class="ingredient-name">${name}</span><span class="ingredient-detail">${detail}</span></span><span class="ingredient-mark" aria-hidden="true">+</span>`;
	button.addEventListener("click", () => toggle(ingredient.id));
	pantry.append(button);

	const piece = document.createElement("button");
	piece.type = "button";
	piece.className = "bowl-piece";
	piece.dataset.id = ingredient.id;
	piece.dataset.index = index;
	piece.setAttribute("aria-label", `Remove ${name} from your mix`);
	piece.hidden = true;
	piece.innerHTML = art(ingredient.id);
	piece.addEventListener("click", () => {
		toggle(ingredient.id);
		button.focus({ preventScroll: true });
	});
	slots.append(piece);
}

function toggle(id) {
	setIngredient(id, !selected.has(id));
}

function setIngredient(id, add, animate = true) {
	if (selected.has(id) === add) return;
	const source = pantry.querySelector(`[data-id="${id}"]`);
	const piece = slots.querySelector(`[data-id="${id}"]`);
	const sourceArt = source.querySelector(".ingredient-art");
	const previous = flights.get(id);
	const currentTransform = previous
		? new DOMMatrix(getComputedStyle(previous.element).transform)
		: null;
	previous?.animation.cancel();
	flights.delete(id);

	add ? selected.add(id) : selected.delete(id);
	source.setAttribute("aria-pressed", String(add));
	source.querySelector(".ingredient-mark").textContent = add ? "✓" : "+";
	piece.hidden = false;
	piece.style.visibility = "visible";
	piece.style.transform = "none";
	const pieceBounds = piece.getBoundingClientRect();
	piece.style.transform = "";
	const sourceBounds = sourceArt.getBoundingClientRect();
	const destination = add ? pieceBounds : sourceBounds;
	const start = previous?.origin || (add ? sourceBounds : pieceBounds);

	if (!animate || reducedMotion.matches) {
		previous?.element.remove();
		piece.hidden = !add;
		updateReceipt();
		return;
	}

	piece.style.visibility = "hidden";
	const flying = previous?.element || document.createElement("div");
	if (!previous) {
		flying.className = "flight";
		flying.setAttribute("aria-hidden", "true");
		flying.innerHTML = art(id);
		flying.style.left = `${start.left}px`;
		flying.style.top = `${start.top}px`;
		flying.style.width = `${start.width}px`;
		flying.style.height = `${start.height}px`;
		document.body.append(flying);
	}
	const dx =
		destination.left + destination.width / 2 - start.left - start.width / 2;
	const dy =
		destination.top + destination.height / 2 - start.top - start.height / 2;
	const scale = destination.width / start.width;
	const pieceAngle =
		Number.parseFloat(
			getComputedStyle(piece).getPropertyValue("--piece-angle"),
		) || 0;
	const angle = add ? pieceAngle : 0;
	const initial = currentTransform
		? {
				x: currentTransform.m41,
				y: currentTransform.m42,
				angle:
					(Math.atan2(currentTransform.m12, currentTransform.m11) * 180) /
					Math.PI,
				scale: Math.hypot(currentTransform.m11, currentTransform.m12),
			}
		: { x: 0, y: 0, angle: add ? 0 : pieceAngle, scale: 1 };
	const animation = flying.animate(
		[
			{
				transform: `translate(${initial.x}px, ${initial.y}px) rotate(${initial.angle}deg) scale(${initial.scale})`,
			},
			{
				transform: `translate(${initial.x + (dx - initial.x) * 0.48}px, ${initial.y + (dy - initial.y) * 0.48 - Math.min(125, Math.abs(dx - initial.x) * 0.3 + 35)}px) rotate(${add ? -18 : 22}deg) scale(${(initial.scale + scale) / 2})`,
				offset: 0.48,
			},
			{
				transform: `translate(${dx}px, ${dy}px) rotate(${angle}deg) scale(${scale})`,
			},
		],
		{ duration: 650, easing: "cubic-bezier(.22,.65,.27,1)", fill: "forwards" },
	);
	const flight = { element: flying, animation, origin: start };
	flights.set(id, flight);
	animation.finished
		.then(() => {
			if (flights.get(id) !== flight) return;
			flying.remove();
			flights.delete(id);
			piece.style.visibility = "visible";
			piece.hidden = !selected.has(id);
			if (selected.has(id))
				piece.animate(
					[
						{ transform: `rotate(${angle}deg) translateY(-3px)` },
						{ transform: `rotate(${angle + 5}deg) translateY(2px)` },
						{ transform: `rotate(${angle}deg) translateY(0)` },
					],
					{ duration: 280, easing: "ease-out" },
				);
		})
		.catch(() => {});
	updateReceipt();
}

function updateReceipt() {
	receipt.replaceChildren();
	for (const ingredient of ingredients) {
		if (!selected.has(ingredient.id)) continue;
		const name = (copies[ingredient.id] || [ingredient.name])[0];
		const item = document.createElement("li");
		const tick = document.createElement("span");
		tick.className = "receipt-tick";
		tick.textContent = "✓";
		tick.setAttribute("aria-hidden", "true");
		const label = document.createElement("span");
		label.textContent = name;
		const remove = document.createElement("button");
		remove.type = "button";
		remove.textContent = "×";
		remove.setAttribute("aria-label", `Remove ${name}`);
		remove.addEventListener("click", () => {
			setIngredient(ingredient.id, false);
			pantry
				.querySelector(`[data-id="${ingredient.id}"]`)
				.focus({ preventScroll: true });
		});
		item.append(tick, label, remove);
		receipt.append(item);
	}
	document.querySelector("#mix-count").textContent = selected.size;
	document.querySelector("#receipt-empty").hidden = selected.size > 0;
	document
		.querySelector("#empty-bowl-note")
		.classList.toggle("hidden", selected.size > 0);
	document.querySelector("#reset").disabled = selected.size === 0;
	document.querySelector("#whole-mix").disabled =
		selected.size === ingredients.length;
	document.querySelector("#receipt-footer").textContent =
		selected.size === 0
			? "Every mix starts somewhere."
			: selected.size === ingredients.length
				? "A bit of everything. Lovely."
				: "That looks like your kind of day.";
	document.querySelector("#announcement").textContent =
		`${selected.size} of ${ingredients.length} tools in your mix.`;
}

document.querySelector("#whole-mix").addEventListener("click", () => {
	for (const ingredient of ingredients) setIngredient(ingredient.id, true);
});
document.querySelector("#reset").addEventListener("click", () => {
	for (const ingredient of ingredients) setIngredient(ingredient.id, false);
});
function settleFlights() {
	for (const [id, flight] of flights) {
		flight.animation.cancel();
		flight.element.remove();
		const piece = slots.querySelector(`[data-id="${id}"]`);
		piece.hidden = !selected.has(id);
		piece.style.visibility = "visible";
	}
	flights.clear();
}
window.addEventListener("resize", settleFlights);
window.addEventListener("scroll", settleFlights, { passive: true });
reducedMotion.addEventListener("change", () => {
	if (reducedMotion.matches) settleFlights();
});
updateReceipt();
