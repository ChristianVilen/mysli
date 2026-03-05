import Cocoa

class ThumbnailStackManager {
    private(set) var entries: [(panel: ThumbnailPanel, result: CaptureResult)] = []
    var onEdit: ((CaptureResult) -> Void)?
    var onCombine: ((NSImage, NSImage) -> CaptureResult?)?
    var onDelete: ((CaptureResult) -> Void)?
    private var combineButtons: [CombineButton] = []
    private var currentDuration: TimeInterval = 5.0
    private var currentScreen: NSScreen?
    private static let maxCount = 5

    func add(image: NSImage, result: CaptureResult, screen: NSScreen, duration: TimeInterval) {
        currentDuration = duration
        currentScreen = screen

        let panel = makePanel(image: image)
        entries.insert((panel: panel, result: result), at: 0)

        // Enforce max count — drop oldest (last in array)
        if entries.count > Self.maxCount {
            let oldest = entries.removeLast()
            oldest.panel.cancelDismissTimer()
            oldest.panel.orderOut(nil)
        }

        // Timer logic
        if entries.count > 1 {
            for entry in entries { entry.panel.cancelDismissTimer() }
        } else if duration > 0 {
            panel.startDismissTimer(duration: duration)
        }

        repositionAll(animated: false)
        panel.orderFront(nil)
    }

    func remove(panel: ThumbnailPanel) {
        panel.cancelDismissTimer()
        panel.orderOut(nil)
        entries.removeAll(where: { $0.panel === panel })

        // If back to 1, restart timer
        if entries.count == 1, currentDuration > 0 {
            entries[0].panel.startDismissTimer(duration: currentDuration)
        }

        repositionAll(animated: true)
    }

    func combine(upperIndex: Int, lowerIndex: Int) {
        guard upperIndex < entries.count, lowerIndex < entries.count else { return }

        // entries: index 0 = newest (visual top), last = oldest (visual bottom)
        // Chronological: older on top in combined image
        let olderEntry = entries[max(upperIndex, lowerIndex)]
        let newerEntry = entries[min(upperIndex, lowerIndex)]

        guard let combinedResult = onCombine?(olderEntry.result.image, newerEntry.result.image) else { return }

        // Remove both source panels
        for p in [olderEntry.panel, newerEntry.panel] {
            p.cancelDismissTimer()
            p.orderOut(nil)
        }
        entries.removeAll(where: { e in e.panel === olderEntry.panel || e.panel === newerEntry.panel })

        // Insert combined at the upper position
        let panel = makePanel(image: combinedResult.image)
        let safeIndex = min(min(upperIndex, lowerIndex), entries.count)
        entries.insert((panel: panel, result: combinedResult), at: safeIndex)

        if entries.count == 1, currentDuration > 0 {
            panel.startDismissTimer(duration: currentDuration)
        }

        repositionAll(animated: true)
        panel.orderFront(nil)
    }

    // MARK: - Private

    private func makePanel(image: NSImage) -> ThumbnailPanel {
        let screen = currentScreen ?? NSScreen.main!
        let size = ThumbnailPanel.thumbSize(for: image)
        let frame = NSRect(
            x: screen.visibleFrame.maxX - size.width - ThumbnailPanel.padding,
            y: screen.visibleFrame.minY + ThumbnailPanel.padding,
            width: size.width,
            height: size.height
        )

        let panel = ThumbnailPanel(image: image, frame: frame)

        panel.onDismiss = { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.remove(panel: panel)
        }
        panel.onEdit = { [weak self, weak panel] in
            guard let self, let panel else { return }
            let result = self.entries.first(where: { $0.panel === panel })?.result
            self.remove(panel: panel)
            if let result { self.onEdit?(result) }
        }

        panel.onDelete = { [weak self, weak panel] in
            guard let self, let panel else { return }
            let result = self.entries.first(where: { $0.panel === panel })?.result
            self.remove(panel: panel)
            if let result { self.onDelete?(result) }
        }

        return panel
    }

    private func repositionAll(animated: Bool) {
        guard let screen = currentScreen else { return }

        // Remove old combine buttons
        for btn in combineButtons { btn.orderOut(nil) }
        combineButtons.removeAll()

        let baseX = screen.visibleFrame.maxX - ThumbnailPanel.thumbWidth - ThumbnailPanel.padding
        var y = screen.visibleFrame.minY + ThumbnailPanel.padding

        // Stack from bottom: oldest (last) at bottom, newest (first) at top
        let reversed = Array(entries.enumerated()).reversed()

        for (i, entry) in reversed {
            let size = entry.panel.frame.size
            let newFrame = NSRect(x: baseX, y: y, width: size.width, height: size.height)

            if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.3
                    entry.panel.animator().setFrame(newFrame, display: true)
                }
            } else {
                entry.panel.setFrame(newFrame, display: true)
            }

            y += size.height

            // Add combine button between this panel and the next one above
            let aboveIndex = i - 1
            if aboveIndex >= 0 {
                let btnFrame = NSRect(
                    x: baseX + (ThumbnailPanel.thumbWidth - CombineButton.buttonWidth) / 2,
                    y: y + (ThumbnailPanel.gap - CombineButton.buttonHeight) / 2,
                    width: CombineButton.buttonWidth,
                    height: CombineButton.buttonHeight
                )
                let btn = CombineButton(frame: btnFrame)
                let lower = i
                let upper = aboveIndex
                btn.onCombine = { [weak self] in
                    self?.combine(upperIndex: upper, lowerIndex: lower)
                }
                combineButtons.append(btn)
                btn.orderFront(nil)
            }

            y += ThumbnailPanel.gap
        }
    }
}
