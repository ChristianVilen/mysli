export type Demo = { open(): void; close(): void };

type Behaviour = {
	toggle?(root: HTMLElement, on: boolean): void;
	act?(root: HTMLElement, status: HTMLElement): void;
	open?(root: HTMLElement): void;
	close?(root: HTMLElement): void;
};

const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)");
const clocks = new WeakMap<HTMLElement, number>();

function clockText(seconds: number) {
	const minutes = Math.floor(seconds / 60);
	return `${minutes}:${String(seconds % 60).padStart(2, "0")}`;
}

function startClock(root: HTMLElement, face: HTMLElement, from: number, step: 1 | -1) {
	stopClock(root);
	let seconds = from;
	face.textContent = clockText(seconds);
	clocks.set(
		root,
		window.setInterval(() => {
			seconds = Math.max(0, seconds + step);
			face.textContent = clockText(seconds);
		}, 1000),
	);
}

function stopClock(root: HTMLElement) {
	window.clearInterval(clocks.get(root));
	clocks.delete(root);
}

/** Moves the oldest slip to the front of the stack, animating every slip from where it was. */
function pasteOlder(root: HTMLElement, status: HTMLElement) {
	const stack = root.querySelector<HTMLElement>(".clip-stack");
	const oldest = stack?.firstElementChild;
	if (!stack || !(oldest instanceof HTMLElement)) return;
	const slips = [...stack.children].filter((slip) => slip instanceof HTMLElement);
	const before = new Map(
		slips.map((slip) => [
			slip,
			{ box: slip.getBoundingClientRect(), transform: getComputedStyle(slip).transform },
		]),
	);
	stack.append(oldest);
	// A live region announces only a change, so each paste switches the words.
	status.textContent = status.textContent === "Back on top." ? "Pasted again." : "Back on top.";
	if (reduceMotion.matches) return;
	for (const slip of slips) {
		const first = before.get(slip);
		if (!first) continue;
		const last = slip.getBoundingClientRect();
		const dx = first.box.left + first.box.width / 2 - (last.left + last.width / 2);
		const dy = first.box.top + first.box.height / 2 - (last.top + last.height / 2);
		const from = `translate(${dx}px, ${dy}px) ${first.transform === "none" ? "" : first.transform}`;
		const to = getComputedStyle(slip).transform;
		const frames =
			slip === oldest
				? [
						{ transform: from },
						{ transform: `translate(${dx / 2}px, ${dy / 2 - 46}px) rotate(7deg)`, offset: 0.45 },
						{ transform: to },
					]
				: [{ transform: from }, { transform: to }];
		slip.animate(frames, {
			duration: slip === oldest ? 620 : 420,
			easing: "cubic-bezier(.2,.75,.2,1)",
		});
	}
}

const behaviours: Record<string, Behaviour> = {
	screenshots: {
		toggle(root, on) {
			if (!on || reduceMotion.matches) return;
			root
				.querySelector(".capture-flash")
				?.animate([{ opacity: 0 }, { opacity: 0.85 }, { opacity: 0 }], {
					duration: 320,
					easing: "ease-out",
				});
		},
	},
	clipboard: {
		act: pasteOlder,
		close(root) {
			const stack = root.querySelector(".clip-stack");
			if (!stack) return;
			const slips = [...stack.children];
			slips.sort(
				(a, b) => Number(a.getAttribute("data-order")) - Number(b.getAttribute("data-order")),
			);
			stack.append(...slips);
		},
	},
	awake: {
		toggle(root, on) {
			const face = root.querySelector<HTMLElement>("[data-dial]");
			if (!face) return;
			if (on) startClock(root, face, 60 * 60, -1);
			else {
				stopClock(root);
				face.textContent = "1h";
			}
		},
		close(root) {
			stopClock(root);
			const face = root.querySelector<HTMLElement>("[data-dial]");
			if (face) face.textContent = "1h";
		},
	},
	meetings: {
		open(root) {
			const time = root.querySelector<HTMLElement>(".rec-time");
			if (time) startClock(root, time, 12 * 60 + 34, 1);
		},
		close: stopClock,
		toggle(root, on) {
			const note = root.querySelector<HTMLElement>("[data-note]");
			if (!note) return;
			note.dataset.offNote ??= note.textContent ?? "";
			note.textContent = on ? (note.dataset.onNote ?? "") : note.dataset.offNote;
			if (reduceMotion.matches) return;
			note.animate(
				[
					{ transform: "translateY(7px) rotate(-5deg)", opacity: 0.3 },
					{ transform: "translateY(0) rotate(-2deg)", opacity: 1 },
				],
				{ duration: 350, easing: "cubic-bezier(.2,.8,.2,1)" },
			);
		},
	},
};

export function setUpDemo(root: HTMLElement): Demo {
	const action = root.querySelector<HTMLButtonElement>("[data-demo-action]");
	const status = root.querySelector<HTMLElement>("[data-demo-status]");
	const behaviour = behaviours[root.dataset.demo ?? ""] ?? {};
	if (!action || !status) return { open() {}, close() {} };
	const offLabel = action.textContent ?? "";
	const offStatus = status.textContent ?? "";
	const { onLabel } = action.dataset;
	const { onStatus } = status.dataset;
	root.querySelectorAll(".clip-stack > li").forEach((slip, index) => {
		slip.setAttribute("data-order", String(index));
	});
	let on = false;

	function setOn(value: boolean) {
		on = value;
		root.classList.toggle("is-on", on);
		action.textContent = on && onLabel ? onLabel : offLabel;
		const text = on && onStatus ? onStatus : offStatus;
		if (status.textContent !== text) status.textContent = text;
	}

	action.addEventListener("click", () => {
		if (onLabel) {
			setOn(!on);
			behaviour.toggle?.(root, on);
		} else behaviour.act?.(root, status);
	});

	return {
		open() {
			setOn(false);
			behaviour.close?.(root);
			behaviour.open?.(root);
		},
		close() {
			setOn(false);
			behaviour.close?.(root);
		},
	};
}
