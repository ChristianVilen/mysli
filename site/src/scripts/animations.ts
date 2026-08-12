// Page interactions: copy buttons + the hero capture demo.
// The hero entrance is pure CSS (see global.css) — no JS reveals anywhere.

const motionOK = window.matchMedia("(prefers-reduced-motion: no-preference)").matches;

/* ---------- Copy buttons ---------- */
for (const btn of document.querySelectorAll<HTMLButtonElement>("button[data-copy]")) {
	btn.addEventListener("click", async () => {
		try {
			await navigator.clipboard.writeText(btn.dataset.copy ?? "");
			btn.textContent = "Copied ✓";
		} catch {
			btn.textContent = "Copy failed";
		}
		setTimeout(() => {
			btn.textContent = "Copy";
		}, 2000);
	});
}

/* ---------- Hero capture demo — drag anywhere, like ⇧⌘4 ---------- */
const hero = document.querySelector<HTMLElement>("[data-capture-zone]");

if (hero) {
	const selEl = document.createElement("div");
	selEl.className = "capture-sel";
	selEl.hidden = true;
	const dimsEl = document.createElement("div");
	dimsEl.className = "capture-dims";
	dimsEl.hidden = true;
	const flashEl = document.createElement("div");
	flashEl.className = "capture-flash";
	const thumbsBox = document.createElement("div");
	thumbsBox.className = "capture-thumbs";
	document.body.append(selEl, dimsEl, flashEl, thumbsBox);

	// Apple-style spring (damping ratio + response), semi-implicit Euler.
	function spring(opts: { damping: number; response: number; onUpdate: (t: number) => void }) {
		const w0 = (2 * Math.PI) / opts.response;
		let x = 0;
		let v = 0;
		let last = performance.now();
		function step(now: number) {
			const dt = Math.min((now - last) / 1000, 1 / 30);
			last = now;
			v += (-w0 * w0 * (x - 1) - 2 * opts.damping * w0 * v) * dt;
			x += v * dt;
			if (Math.abs(x - 1) < 0.001 && Math.abs(v) < 0.001) {
				opts.onUpdate(1);
				return;
			}
			opts.onUpdate(x);
			requestAnimationFrame(step);
		}
		requestAnimationFrame(step);
	}

	type Rect = { x: number; y: number; w: number; h: number };
	let start: { x: number; y: number } | null = null;
	let dragging = false;
	let cur: Rect | null = null;

	hero.addEventListener("pointerdown", (e) => {
		if (e.button !== 0 || (e.target as HTMLElement).closest("a, button")) return;
		e.preventDefault();
		start = { x: e.clientX, y: e.clientY };
		hero.setPointerCapture(e.pointerId);
	});

	hero.addEventListener("pointermove", (e) => {
		if (!start) return;
		const dx = e.clientX - start.x;
		const dy = e.clientY - start.y;
		if (!dragging) {
			if (Math.hypot(dx, dy) < 4) return; // threshold before committing to a drag
			dragging = true;
			document.body.classList.add("capturing");
			selEl.hidden = false;
			dimsEl.hidden = false;
		}
		cur = {
			x: Math.min(start.x, e.clientX),
			y: Math.min(start.y, e.clientY),
			w: Math.abs(dx),
			h: Math.abs(dy),
		};
		selEl.style.left = `${cur.x}px`;
		selEl.style.top = `${cur.y}px`;
		selEl.style.width = `${cur.w}px`;
		selEl.style.height = `${cur.h}px`;
		dimsEl.textContent = `${Math.round(cur.w)} × ${Math.round(cur.h)}`;
		dimsEl.style.left = `${Math.min(e.clientX + 14, innerWidth - 96)}px`;
		dimsEl.style.top = `${Math.min(e.clientY + 18, innerHeight - 36)}px`;
	});

	function endDrag(commit: boolean) {
		if (dragging && commit && cur && cur.w >= 24 && cur.h >= 24) capture(cur);
		start = null;
		dragging = false;
		cur = null;
		selEl.hidden = true;
		dimsEl.hidden = true;
		document.body.classList.remove("capturing");
	}
	hero.addEventListener("pointerup", () => endDrag(true));
	hero.addEventListener("pointercancel", () => endDrag(false));

	addEventListener("keydown", (e) => {
		if (e.key === "Escape") endDrag(false);
	});

	// Mirrors ThumbnailStackManager.swift: thumbs are 200px wide (height by
	// aspect), newest at the visual top, a Combine pill between each adjacent
	// pair. Newest first in this array = top-to-bottom DOM order.
	const THUMB_W = 200;
	type Thumb = { el: HTMLElement; img: HTMLElement; w: number; h: number };
	const thumbs: Thumb[] = [];

	// Rebuild the column: thumb, gap+pill, thumb, gap+pill, …
	function layout() {
		thumbsBox.replaceChildren();
		thumbs.forEach((t, i) => {
			thumbsBox.appendChild(t.el);
			if (i < thumbs.length - 1) {
				const gap = document.createElement("div");
				gap.className = "capture-gap";
				const btn = document.createElement("button");
				btn.type = "button";
				btn.className = "capture-combine";
				btn.textContent = "Combine";
				btn.addEventListener("click", () => combinePair(i));
				gap.appendChild(btn);
				thumbsBox.appendChild(gap);
			}
		});
	}

	function removeThumb(t: Thumb) {
		const i = thumbs.indexOf(t);
		if (i > -1) thumbs.splice(i, 1);
		if (motionOK) {
			t.el.animate([{ opacity: 1 }, { opacity: 0 }], {
				duration: 180,
				easing: "ease-out",
			}).onfinish = () => layout();
		} else {
			layout();
		}
	}

	function makeThumbShell(w: number, h: number, img: HTMLElement): Thumb {
		const el = document.createElement("div");
		el.className = "capture-thumb";
		el.style.width = `${w}px`;
		el.style.height = `${h}px`;
		el.appendChild(img);

		// Like the app: trash.circle.fill top-left, xmark.circle.fill top-right.
		const trash = document.createElement("button");
		trash.type = "button";
		trash.className = "capture-thumb-btn capture-thumb-btn--trash";
		trash.setAttribute("aria-label", "Delete screenshot");
		trash.innerHTML =
			'<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M3 6h18M8 6V4h8v2M6 6l1 15h10l1-15M10 11v6M14 11v6"/></svg>';
		const close = document.createElement("button");
		close.type = "button";
		close.className = "capture-thumb-btn capture-thumb-btn--close";
		close.setAttribute("aria-label", "Close preview");
		close.textContent = "×";
		el.append(trash, close);

		const t: Thumb = { el, img, w, h };
		close.addEventListener("click", () => removeThumb(t));
		trash.addEventListener("click", () => removeThumb(t));
		return t;
	}

	function flyIn(t: Thumb, from: Rect) {
		const dest = t.el.getBoundingClientRect();
		const s0 = from.w / t.w;
		const dx = from.x - dest.left;
		const dy = from.y - dest.top;
		t.el.style.transformOrigin = "0 0";
		if (motionOK) {
			spring({
				damping: 0.9,
				response: 0.45,
				onUpdate: (p) => {
					const sc = s0 + (1 - s0) * p;
					t.el.style.transform = `translate(${dx * (1 - p)}px,${dy * (1 - p)}px) scale(${sc})`;
				},
			});
		} else {
			t.el.style.opacity = "0";
			requestAnimationFrame(() => {
				t.el.style.transition = "opacity 200ms ease";
				t.el.style.opacity = "1";
			});
		}
	}

	function capture(rect: Rect) {
		if (motionOK) {
			flashEl.animate([{ opacity: 0.45 }, { opacity: 0 }], { duration: 300, easing: "ease-out" });
		}
		const heroRect = hero.getBoundingClientRect();
		// Fixed 200px width like the app; height follows the capture's aspect.
		const s = THUMB_W / rect.w;
		const h = rect.h * s;

		// The "screenshot": a clone of the hero, scaled and offset to the selection.
		const img = document.createElement("div");
		img.className = "capture-thumb-img";
		img.style.width = `${THUMB_W}px`;
		img.style.height = `${h}px`;
		const clone = hero.cloneNode(true) as HTMLElement;
		clone.removeAttribute("id");
		clone.style.cssText =
			`width:${heroRect.width}px;height:${heroRect.height}px;min-height:0;margin:0;` +
			`background:var(--color-paper);pointer-events:none;transform-origin:0 0;` +
			`transform:scale(${s}) translate(${-(rect.x - heroRect.left)}px,${-(rect.y - heroRect.top)}px);`;
		img.appendChild(clone);

		const t = makeThumbShell(THUMB_W, h, img);
		thumbs.unshift(t); // newest on top
		if (thumbs.length > 5) thumbs.pop()?.el.remove();
		layout();
		flyIn(t, rect);
	}

	// Combine an adjacent pair, older capture on top — mirrors combine(upperIndex:lowerIndex:).
	function combinePair(upper: number) {
		const newer = thumbs[upper];
		const older = thumbs[upper + 1];
		if (!newer || !older) return;

		const img = document.createElement("div");
		img.className = "capture-thumb-img";
		img.style.width = `${THUMB_W}px`;
		img.style.height = `${older.h + newer.h}px`;
		img.append(older.img, newer.img); // both already 200px wide

		const t = makeThumbShell(THUMB_W, older.h + newer.h, img);
		thumbs.splice(upper, 2, t);
		layout();
		if (motionOK) {
			t.el.animate(
				[
					{ opacity: 0, transform: "scale(0.94)" },
					{ opacity: 1, transform: "scale(1)" },
				],
				{ duration: 220, easing: "cubic-bezier(0.16, 1, 0.3, 1)" },
			);
		}
	}
}
