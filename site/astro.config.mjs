import tailwindcss from "@tailwindcss/vite";
import { defineConfig, fontProviders } from "astro/config";

export default defineConfig({
	site: "https://christianvilen.github.io",
	base: "/mysli",
	fonts: [
		{
			provider: fontProviders.google(),
			name: "DM Sans",
			cssVariable: "--font-dm-sans",
			weights: ["400 700"],
			styles: ["normal"],
			subsets: ["latin"],
			fallbacks: ["sans-serif"],
		},
		{
			provider: fontProviders.google(),
			name: "Caveat",
			cssVariable: "--font-caveat",
			weights: ["400 700"],
			styles: ["normal"],
			subsets: ["latin"],
			fallbacks: ["cursive"],
		},
	],
	vite: {
		plugins: [tailwindcss()],
	},
});
