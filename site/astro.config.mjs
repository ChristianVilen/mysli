import tailwind from "@astrojs/tailwind";
import { defineConfig } from "astro/config";

export default defineConfig({
	site: "https://christianvilen.github.io",
	base: "/ku-ka",
	integrations: [tailwind()],
});
