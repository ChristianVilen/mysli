import type { ToolId } from "../../data/tools";

export type DemoParts = {
	root: HTMLElement;
	button: HTMLButtonElement;
	status: HTMLElement;
	sheet: HTMLElement;
};

/** Finds a demo's box, its button, the status line that screen readers hear, and the tool sheet around it. */
export function findDemo(name: ToolId): DemoParts | null {
	const root = document.querySelector<HTMLElement>(`[data-demo="${name}"]`);
	const button = root?.querySelector<HTMLButtonElement>("[data-demo-button]");
	const status = root?.querySelector<HTMLElement>("[data-demo-status]");
	const sheet = root?.closest<HTMLElement>("[data-sheet]");
	return root && button && status && sheet ? { root, button, status, sheet } : null;
}

/** Shows a ticking minutes:seconds clock on `face`. Returns a function that stops it. */
export function startClock(face: HTMLElement, fromSeconds: number, step: 1 | -1) {
	let seconds = fromSeconds;
	const show = () => {
		face.textContent = `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
	};
	show();
	const timer = window.setInterval(() => {
		seconds = Math.max(0, seconds + step);
		show();
	}, 1000);
	return () => window.clearInterval(timer);
}
