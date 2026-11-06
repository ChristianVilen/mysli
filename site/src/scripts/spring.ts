export type Pose = { x: number; y: number; r: number; s: number };

type State = Pose & { velocity: Pose; target: Pose };

const STIFFNESS = 190;
const DAMPING = 24;
const properties = ["x", "y", "r", "s"] as const;
const states = new WeakMap<HTMLElement, State>();
const moving = new Set<HTMLElement>();
export const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)");
let frame = 0;
let previous = 0;

function paint(element: HTMLElement, pose: Pose) {
	element.style.transform = `translate(-50%, -50%) translate3d(${pose.x}px, ${pose.y}px, 0) rotate(${pose.r}deg) scale(${pose.s})`;
}

function rest(element: HTMLElement, state: State) {
	Object.assign(state, state.target);
	state.velocity = { x: 0, y: 0, r: 0, s: 0 };
	moving.delete(element);
	element.style.willChange = "";
	paint(element, state);
}

function tick(now: number) {
	// A long frame or a tab that was in the background must not throw the pieces off the page.
	const step = previous ? Math.min((now - previous) / 1000, 1 / 30) : 1 / 60;
	previous = now;
	for (const element of moving) {
		const state = states.get(element);
		if (!state) {
			moving.delete(element);
			continue;
		}
		let settled = true;
		for (const property of properties) {
			const distance = state.target[property] - state[property];
			state.velocity[property] +=
				(distance * STIFFNESS - state.velocity[property] * DAMPING) * step;
			state[property] += state.velocity[property] * step;
			const tolerance = property === "s" ? 0.002 : 0.05;
			if (Math.abs(distance) + Math.abs(state.velocity[property]) > tolerance) settled = false;
		}
		if (settled) rest(element, state);
		else paint(element, state);
	}
	frame = moving.size ? requestAnimationFrame(tick) : 0;
	if (!frame) previous = 0;
}

/**
 * Springs the element towards the target. A new target during a movement keeps the
 * current position and velocity, so the movement turns smoothly.
 */
export function move(element: HTMLElement, target: Partial<Pose>, { immediate = false } = {}) {
	let state = states.get(element);
	if (!state) {
		state = {
			x: 0,
			y: 0,
			r: 0,
			s: 1,
			velocity: { x: 0, y: 0, r: 0, s: 0 },
			target: { x: 0, y: 0, r: 0, s: 1 },
		};
		states.set(element, state);
	}
	Object.assign(state.target, target);
	if (immediate || reduceMotion.matches) {
		rest(element, state);
		return;
	}
	moving.add(element);
	element.style.willChange = "transform";
	if (!frame) frame = requestAnimationFrame(tick);
}

reduceMotion.addEventListener("change", () => {
	if (!reduceMotion.matches) return;
	for (const element of moving) {
		const state = states.get(element);
		if (state) rest(element, state);
	}
});
