import { cp, mkdir, readdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const source = fileURLToPath(new URL(".", import.meta.url));
const destination = path.resolve(source, "../../site/dist/bowl-lab");
await mkdir(destination, { recursive: true });
for (const file of await readdir(source)) {
	if (/\.(html|css|js|svg)$/.test(file)) {
		await cp(path.join(source, file), path.join(destination, file));
	}
}
console.log("Prototype files prepared in site/dist/bowl-lab.");
console.log("Open /mysli/bowl-lab/ on the URL reported by Astro preview.");
