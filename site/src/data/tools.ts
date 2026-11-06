export type ToolId = "screenshots" | "clipboard" | "windows" | "awake" | "meetings";

export type Tool = {
	id: ToolId;
	name: string;
	description: string;
	/** The handwritten line on the tool's paper sheet. */
	note: string;
	/** The friendlier description on the tool's paper sheet. */
	pitch: string;
	/** The shortcut or entry point in words. Screen readers read this instead of the keycaps. */
	shortcut: string;
	/** Each inner list is one key combination, drawn as keycaps. */
	keys?: string[][];
	limit: string;
	color: string;
};

export const tools: Tool[] = [
	{
		id: "screenshots",
		name: "Screenshots",
		description: "Capture a screen, a window or a region. Crop, draw and copy.",
		note: "Keep the good bit.",
		pitch:
			"A screen, a window or just the useful bit. Capture it, crop it, and it is already on your clipboard.",
		shortcut: "Shift Command 3 or Shift Command 4",
		keys: [
			["⇧", "⌘", "3"],
			["⇧", "⌘", "4"],
		],
		limit: "Freehand drawing and crop; no full image editor.",
		color: "#d8aa47",
	},
	{
		id: "clipboard",
		name: "Clipboard history",
		description: "Find text and images you copied earlier. Paste them again.",
		note: "A second helping.",
		pitch: "The words and images you copied earlier, ready when you need them again.",
		shortcut: "Shift Command C",
		keys: [["⇧", "⌘", "C"]],
		limit: "In memory only. History clears when you quit.",
		color: "#8da876",
	},
	{
		id: "windows",
		name: "Window tiling",
		description: "Put a window on either half of the screen, or fill it.",
		note: "Room to think.",
		pitch: "Give your windows a little order. Left, right, or all the room they need.",
		shortcut: "Control Option Left Arrow, Right Arrow or Return",
		keys: [
			["⌃", "⌥", "←"],
			["⌃", "⌥", "→"],
			["⌃", "⌥", "↩"],
		],
		limit: "A small set of fixed layouts and shortcuts.",
		color: "#7699b9",
	},
	{
		id: "awake",
		name: "Keep Awake",
		description: "Keep your Mac awake while a long task finishes.",
		note: "One more cup.",
		pitch: "A little company for the long build. Your Mac stays awake until the work is done.",
		shortcut: "From the menu bar, for 30 minutes to 4 hours, or until off",
		limit: "Closing the lid still sleeps a laptop, unless it has power and an external display.",
		color: "#855c43",
	},
	{
		id: "meetings",
		name: "Meeting notes",
		description: "Record a call. Write notes. Get a transcript and a summary.",
		note: "Good thoughts, kept.",
		pitch:
			"Stay in the conversation. Mysli writes the transcript on your Mac, and the AI tool you choose writes the summary.",
		shortcut: "Start from the menu bar",
		limit: "Local transcription. AI summaries use an external provider.",
		color: "#ba3851",
	},
];
