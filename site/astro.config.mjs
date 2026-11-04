import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "astro/config";

export default defineConfig({
	site: "https://christianvilen.github.io",
	base: "/mysli",
	vite: {
		plugins: [tailwindcss()],
	},
});
