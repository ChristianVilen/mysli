import { animate, inView } from "motion";

// Hero: staggered fade-in + slide up on load
const heroItems = document.querySelectorAll<HTMLElement>('[data-animate="hero-item"]');
heroItems.forEach((el, i) => {
	animate(
		el,
		{ opacity: [0, 1], transform: ["translateY(30px)", "translateY(0)"] },
		{ delay: 0.15 * i, duration: 0.6, easing: "ease-out" },
	);
});

// Install: fade in on scroll
inView(
	'[data-animate="install"]',
	(info) => {
		animate(
			info.target as HTMLElement,
			{ opacity: [0, 1], transform: ["translateY(30px)", "translateY(0)"] },
			{ duration: 0.6, easing: "ease-out" },
		);
	},
	{ amount: 0.3 },
);

// Features: cards stagger in on scroll
inView(
	'[data-animate="features"]',
	() => {
		const cards = document.querySelectorAll<HTMLElement>('[data-animate="feature-card"]');
		cards.forEach((el, i) => {
			animate(
				el,
				{ opacity: [0, 1], transform: ["translateY(40px)", "translateY(0)"] },
				{ delay: 0.08 * i, duration: 0.5, easing: "ease-out" },
			);
		});
	},
	{ amount: 0.2 },
);

// How It Works: steps animate in sequentially
inView(
	'[data-animate="steps"]',
	() => {
		const items = document.querySelectorAll<HTMLElement>('[data-animate="step-item"]');
		items.forEach((el, i) => {
			animate(
				el,
				{ opacity: [0, 1], transform: ["translateY(30px)", "translateY(0)"] },
				{ delay: 0.15 * i, duration: 0.5, easing: "ease-out" },
			);
		});
	},
	{ amount: 0.2 },
);

// Comparison: rows stagger in
inView(
	'[data-animate="comparison"]',
	() => {
		const rows = document.querySelectorAll<HTMLElement>('[data-animate="comparison-row"]');
		rows.forEach((el, i) => {
			animate(
				el,
				{ opacity: [0, 1], transform: ["translateX(-20px)", "translateX(0)"] },
				{ delay: 0.06 * i, duration: 0.4, easing: "ease-out" },
			);
		});
	},
	{ amount: 0.2 },
);

// Footer: simple fade in
inView(
	'[data-animate="footer"]',
	(info) => {
		animate(info.target as HTMLElement, { opacity: [0, 1] }, { duration: 0.6, easing: "ease-out" });
	},
	{ amount: 0.5 },
);
