import { playEntrance } from "./entrance";
import { SHEET_CLOSED, SHEET_OPENED } from "./sheet-events";
import { move, type Pose, reduceMotion } from "./spring";

type Piece = { id: string; element: HTMLElement; left: number; top: number; turn: number };

const hero = document.querySelector<HTMLElement>("[data-bowl]");
const stage = hero?.querySelector<HTMLElement>("[data-stage]");
if (hero && stage) setUpBowl(hero, stage);

function setUpBowl(hero: HTMLElement, stage: HTMLElement) {
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

	let selected: string | null = null;
	let lifted: string | null = null;
	let returnFocus: HTMLElement | null = null;
	let size = { width: 0, height: 0 };
	let sheetAnimation: Animation | undefined;
	let stopEntrance = () => {};

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

	function showSheet(sheet: HTMLElement, switching: boolean) {
		sheet.classList.add("is-open");
		sheet.dispatchEvent(new Event(SHEET_OPENED));
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
		if (!sheet) return;
		sheet.classList.remove("is-open");
		sheet.dispatchEvent(new Event(SHEET_CLOSED));
	}

	function open(id: string, trigger: HTMLElement) {
		stopEntrance();
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
		showSheet(sheet, switching);
		layout();
		sheet.querySelector<HTMLElement>("h2")?.focus({ preventScroll: true });
		sheet.scrollIntoView({ block: "nearest", behavior: reduceMotion.matches ? "auto" : "smooth" });
	}

	function close() {
		if (!selected) return;
		const previous = selected;
		const hadFocus = sheets.get(previous)?.contains(document.activeElement) ?? false;
		selected = null;
		sheetAnimation?.cancel();
		hideSheet(previous);
		layout();
		if (hadFocus) {
			const target = returnFocus?.isConnected ? returnFocus : pickers.get(previous);
			target?.focus({ preventScroll: true });
		}
	}

	function assemble() {
		close();
		stopEntrance();
		lifted = null;
		stage.classList.add("is-live");
		if (reduceMotion.matches) layout(true);
		else stopEntrance = playEntrance(hero, stage, pieces, (piece) => place(piece));
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
		stopEntrance();
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
