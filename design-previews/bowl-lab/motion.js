const states = new WeakMap();
const moving = new Set();
const reduce = matchMedia("(prefers-reduced-motion: reduce)");
let frame = 0;
let previous = 0;

function paint(element, state) {
	element.style.transform = `translate(-50%, -50%) translate3d(${state.x}px, ${state.y}px, 0) rotate(${state.r}deg) scale(${state.s})`;
}

function tick(now) {
	const elapsed = Math.min((now - previous) / 1000 || 0.016, 0.033);
	previous = now;
	for (const element of moving) {
		const state = states.get(element);
		let atRest = true;
		for (const property of ["x", "y", "r", "s"]) {
			const velocity = property + "v";
			const distance = state.target[property] - state[property];
			state[velocity] += (distance * 190 - state[velocity] * 24) * elapsed;
			state[property] += state[velocity] * elapsed;
			if (
				Math.abs(distance) + Math.abs(state[velocity]) >
				(property === "s" ? 0.002 : 0.05)
			)
				atRest = false;
		}
		if (atRest || reduce.matches) {
			Object.assign(state, state.target, { xv: 0, yv: 0, rv: 0, sv: 0 });
			moving.delete(element);
			element.style.willChange = "";
		}
		paint(element, state);
	}
	if (moving.size) frame = requestAnimationFrame(tick);
	else {
		frame = 0;
		previous = 0;
	}
}

export function move(element, target, { immediate = false } = {}) {
	let state = states.get(element);
	if (!state) {
		state = {
			x: 0,
			y: 0,
			r: 0,
			s: 1,
			xv: 0,
			yv: 0,
			rv: 0,
			sv: 0,
			target: { x: 0, y: 0, r: 0, s: 1 },
		};
		states.set(element, state);
	}
	Object.assign(state.target, target);
	if (immediate || reduce.matches) {
		Object.assign(state, state.target, { xv: 0, yv: 0, rv: 0, sv: 0 });
		moving.delete(element);
		paint(element, state);
		return;
	}
	moving.add(element);
	element.style.willChange = "transform";
	if (!frame) frame = requestAnimationFrame(tick);
}

reduce.addEventListener("change", () => {
	if (reduce.matches)
		for (const element of moving) move(element, {}, { immediate: true });
});
