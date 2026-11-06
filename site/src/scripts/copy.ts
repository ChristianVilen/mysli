for (const btn of document.querySelectorAll<HTMLButtonElement>("button[data-copy]")) {
	let reset = 0;
	btn.addEventListener("click", async () => {
		window.clearTimeout(reset);
		try {
			await navigator.clipboard.writeText(btn.dataset.copy ?? "");
			btn.textContent = "Copied ✓";
			btn.dataset.state = "copied";
		} catch {
			btn.textContent = "Copy failed";
			delete btn.dataset.state;
		}
		reset = window.setTimeout(() => {
			btn.textContent = "Copy";
			delete btn.dataset.state;
		}, 2000);
	});
}
