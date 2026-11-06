import { type Demo, setUpDemo } from "./demos";
import { move, type Pose } from "./spring";

type Piece = { id: string; element: HTMLElement; left: number; top: number; turn: number };

const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)");
// Keep in step with the breakpoint in global.css where the tool sheet moves below the bowl.
const stacked = matchMedia("(max-width: 900px)");

const hero = document.querySelector<HTMLElement>("[data-bowl]");
const stage = hero?.querySelector<HTMLElement>("[data-stage]");
const intro = hero?.querySelector<HTMLElement>("[data-intro]");
if (hero && stage && intro) setUpBowl(hero, stage, intro);

function setUpBowl(hero: HTMLElement, stage: HTMLElement, intro: HTMLElement) {
	const pieces: Piece[] = [...hero.querySelectorAll<HTMLElement>("[data-piece]")].map(
		(element) => ({
			id: element.dataset.piece ?? "",
			element,
			left: Number(element.dataset.left),
			top: Number(element.dataset.top),
			turn: Number(element.dataset.turn),
		}),
	);
	const pickers = new Map(
		[...hero.querySelectorAll<HTMLButtonElement>("[data-open]")].map((button) => [
			button.dataset.open ?? "",
			button,
		]),
	);
	const sheets = new Map(
		[...hero.querySelectorAll<HTMLElement>("[data-sheet]")].map((sheet) => [
			sheet.dataset.sheet ?? "",
			sheet,
		]),
	);
	const demos = new Map<string, Demo>();
	for (const [id, sheet] of sheets) {
		// Without the script the sheets stay hidden. With it, the is-open class shows one.
		sheet.hidden = false;
		const root = sheet.querySelector<HTMLElement>("[data-demo]");
		if (root) demos.set(id, setUpDemo(root));
	}

	let selected: string | null = null;
	let lifted: string | null = null;
	let returnFocus: HTMLElement | null = null;
	let run = 0;
	let size = { width: 0, height: 0 };
	let sheetAnimation: Animation | undefined;
	let pencil: Animation[] = [];

	function pose(piece: Piece): Pose {
		if (selected === piece.id) {
			return {
				x: size.width * (0.5 - piece.left / 100),
				y: size.height * (0.15 - piece.top / 100),
				r: -4,
				s: 1.33,
			};
		}
		if (selected) return { x: piece.left > 50 ? 8 : -8, y: 8, r: piece.turn, s: 0.96 };
		if (lifted === piece.id) return { x: 0, y: -17, r: piece.turn + 4, s: 1.07 };
		return { x: 0, y: 0, r: piece.turn, s: 1 };
	}

	function place(piece: Piece, immediate = false) {
		piece.element.classList.toggle("is-selected", selected === piece.id);
		piece.element.classList.toggle("is-lifted", !selected && lifted === piece.id);
		move(piece.element, pose(piece), { immediate });
	}

	function layout(immediate = false) {
		for (const piece of pieces) place(piece, immediate);
		for (const [id, picker] of pickers)
			picker.setAttribute("aria-expanded", String(id === selected));
		hero.classList.toggle("has-sheet", selected !== null);
	}

	function lift(id: string | null) {
		if (lifted === id) return;
		const before = lifted;
		lifted = id;
		for (const piece of pieces) if (piece.id === before || piece.id === id) place(piece);
	}

	function showSheet(id: string, switching: boolean) {
		const sheet = sheets.get(id);
		if (!sheet) return;
		sheet.classList.add("is-open");
		demos.get(id)?.open();
		sheetAnimation?.cancel();
		const still = reduceMotion.matches;
		sheetAnimation = sheet.animate(
			still
				? [{ opacity: 0.4 }, { opacity: 1 }]
				: [
						{
							opacity: 0,
							transform: switching
								? "translate(10px, 6px) rotate(1deg)"
								: "translate(18px, 12px) rotate(2deg)",
						},
						{ opacity: 1, transform: "none" },
					],
			{ duration: still ? 160 : 430, easing: "cubic-bezier(.16,.8,.25,1)" },
		);
	}

	function hideSheet(id: string) {
		const sheet = sheets.get(id);
		sheet?.classList.remove("is-open");
		demos.get(id)?.close();
	}

	function open(id: string, trigger: HTMLElement) {
		run++;
		if (selected === id) {
			close();
			return;
		}
		const sheet = sheets.get(id);
		if (!sheet) return;
		const switching = selected !== null;
		if (selected) hideSheet(selected);
		selected = id;
		lifted = null;
		// Pieces are hidden from assistive technology, so focus returns to the matching picker.
		returnFocus = trigger.dataset.piece ? (pickers.get(id) ?? null) : trigger;
		showSheet(id, switching);
		layout();
		sheet.querySelector<HTMLElement>("h2")?.focus({ preventScroll: true });
		if (stacked.matches) {
			sheet.scrollIntoView({
				block: "nearest",
				behavior: reduceMotion.matches ? "auto" : "smooth",
			});
		}
	}

	function close() {
		if (!selected) return;
		const previous = selected;
		const hadFocus = sheets.get(previous)?.contains(document.activeElement) ?? false;
		selected = null;
		sheetAnimation?.cancel();
		hideSheet(previous);
		layout();
		if (!stacked.matches) {
			intro.animate(
				reduceMotion.matches
					? [{ opacity: 0.4 }, { opacity: 1 }]
					: [
							{ opacity: 0, transform: "translateY(7px)" },
							{ opacity: 1, transform: "none" },
						],
				{ duration: 260, easing: "ease-out" },
			);
		}
		if (hadFocus) {
			const target = returnFocus?.isConnected ? returnFocus : pickers.get(previous);
			target?.focus({ preventScroll: true });
		}
	}

	function assemble() {
		close();
		const current = ++run;
		for (const animation of pencil) animation.cancel();
		pencil = [];
		lifted = null;
		stage.classList.add("is-live");
		if (reduceMotion.matches) {
			layout(true);
			return;
		}
		hero.querySelectorAll<SVGPathElement>("[data-pencil]").forEach((path, index) => {
			const length = path.getTotalLength();
			path.style.strokeDasharray = String(length);
			pencil.push(
				path.animate([{ strokeDashoffset: length }, { strokeDashoffset: 0 }], {
					duration: 650,
					delay: 240 + index * 27,
					easing: "cubic-bezier(.22,.7,.25,1)",
					fill: "backwards",
				}),
			);
		});
		pieces.forEach((piece, index) => {
			move(
				piece.element,
				{
					x: (index - 2) * size.width * 0.15,
					y: -size.width * 0.52 - 60,
					r: piece.turn + (index % 2 ? 40 : -30),
					s: 0.75,
				},
				{ immediate: true },
			);
			window.setTimeout(
				() => {
					if (current === run) place(piece);
				},
				80 + index * 95,
			);
		});
		window.setTimeout(() => {
			if (current !== run) return;
			for (const art of hero.querySelectorAll<HTMLElement>("[data-bowl-art]")) {
				art.animate(
					[
						{ transform: "translateY(0) rotate(0)" },
						{ transform: "translateY(2px) rotate(.25deg)", offset: 0.4 },
						{ transform: "translateY(0) rotate(0)" },
					],
					{ duration: 360, easing: "ease-out" },
				);
			}
		}, 1050);
	}

	function measure() {
		const box = stage.getBoundingClientRect();
		const changed = box.width !== size.width || box.height !== size.height;
		size = { width: box.width, height: box.height };
		return changed;
	}

	for (const piece of pieces) {
		const { element, id } = piece;
		element.addEventListener("click", () => open(id, element));
		element.addEventListener("pointerenter", () => {
			if (!selected) lift(id);
		});
		element.addEventListener("pointerleave", () => {
			if (lifted === id) lift(null);
		});
	}
	for (const [id, picker] of pickers) {
		picker.addEventListener("click", () => open(id, picker));
		picker.addEventListener("pointerenter", () => {
			if (!selected) lift(id);
		});
		picker.addEventListener("pointerleave", () => {
			if (lifted === id) lift(null);
		});
		picker.addEventListener("focus", () => {
			if (!selected && picker.matches(":focus-visible")) lift(id);
		});
		picker.addEventListener("blur", () => {
			if (lifted === id) lift(null);
		});
	}
	for (const button of hero.querySelectorAll<HTMLElement>("[data-start]")) {
		button.addEventListener("click", () => open(button.dataset.start ?? "", button));
	}
	for (const button of hero.querySelectorAll<HTMLElement>("[data-close]")) {
		button.addEventListener("click", () => close());
	}
	hero.querySelector("[data-replay]")?.addEventListener("click", assemble);
	document.addEventListener("keydown", (event) => {
		if (event.key === "Escape" && selected) close();
	});
	reduceMotion.addEventListener("change", () => {
		run++;
		for (const animation of pencil) animation.cancel();
		layout(true);
	});

	measure();
	for (const piece of pieces) move(piece.element, pose(piece), { immediate: true });
	new ResizeObserver(() => {
		if (measure()) layout(true);
	}).observe(stage);

	// The pieces arrive only when the visitor can see the bowl. Otherwise they are already in it.
	const begin = () => {
		const observer = new IntersectionObserver(
			([entry]) => {
				observer.disconnect();
				if (entry?.isIntersecting) assemble();
				else {
					stage.classList.add("is-live");
					layout(true);
				}
			},
			{ threshold: 0.2 },
		);
		observer.observe(stage);
	};
	if (document.visibilityState === "visible") begin();
	else document.addEventListener("visibilitychange", begin, { once: true });
}
