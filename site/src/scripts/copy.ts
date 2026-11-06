for (const btn of document.querySelectorAll<HTMLButtonElement>("button[data-copy]")) {
	btn.addEventListener("click", async () => {
		try {
			await navigator.clipboard.writeText(btn.dataset.copy ?? "");
			btn.textContent = "Copied \u2713";
		} catch {
			btn.textContent = "Copy failed";
		}
		setTimeout(() => {
			btn.textContent = "Copy";
		}, 2000);
	});
}
