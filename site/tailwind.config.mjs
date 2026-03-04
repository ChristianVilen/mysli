/** @type {import('tailwindcss').Config} */
export default {
	content: ["./src/**/*.{astro,html,js,ts}"],
	theme: {
		extend: {
			colors: {
				surface: {
					DEFAULT: "#0a0a0f",
					50: "#12121a",
					100: "#1a1a25",
					200: "#252530",
				},
				accent: {
					DEFAULT: "#6366f1",
					light: "#818cf8",
				},
			},
			fontFamily: {
				sans: ['"Inter"', "system-ui", "-apple-system", "sans-serif"],
				mono: ['"SF Mono"', "ui-monospace", "monospace"],
			},
		},
	},
	plugins: [],
};
