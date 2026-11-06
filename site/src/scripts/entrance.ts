import { move } from "./spring";

type Falling = { element: HTMLElement; top: number; turn: number };

/**
 * Plays the arrival: the pencil marks draw in, the pieces drop into the bowl one after another,
 * and the bowl settles. `land` springs a piece to where it belongs now. The returned function
 * stops everything that has not happened yet.
 */
export function playEntrance<T extends Falling>(
	hero: HTMLElement,
	stage: HTMLElement,
	pieces: T[],
	land: (piece: T) => void,
) {
	const timers: number[] = [];
	const pencil = [...hero.querySelectorAll<SVGPathElement>("[data-pencil]")].map((path, index) => {
		const length = path.getTotalLength();
		path.style.strokeDasharray = String(length);
		return path.animate([{ strokeDashoffset: length }, { strokeDashoffset: 0 }], {
			duration: 650,
			delay: 240 + index * 27,
			easing: "cubic-bezier(.22,.7,.25,1)",
			fill: "backwards",
		});
	});

	const box = stage.getBoundingClientRect();
	pieces.forEach((piece, index) => {
		const scale = 0.75;
		const restingTop = box.top + box.height * (piece.top / 100);
		const reach = (piece.element.offsetWidth * scale * Math.SQRT2) / 2;
		// On a phone the bowl sits low on the page, so each piece starts above the window, not above the bowl.
		const aboveWindow = -(restingTop + reach + 24);
		move(
			piece.element,
			{
				x: (index - 2) * box.width * 0.15,
				y: Math.min(-box.width * 0.52 - 60, aboveWindow),
				r: piece.turn + (index % 2 ? 40 : -30),
				s: scale,
			},
			{ immediate: true },
		);
		timers.push(window.setTimeout(() => land(piece), 80 + index * 95));
	});

	timers.push(
		window.setTimeout(() => {
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
		}, 1050),
	);

	return () => {
		for (const timer of timers) window.clearTimeout(timer);
		for (const animation of pencil) animation.cancel();
	};
}
