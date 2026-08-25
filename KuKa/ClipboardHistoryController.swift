import Foundation

/// What the clipboard panel should currently render: the filtered history
/// list, or the "with/without formatting" chooser for a rich-text item that
/// was just selected. The chooser carries the item it is deciding on, so
/// the panel cannot end up drawing a chooser with nothing to name.
enum ClipboardPanelMode: Equatable {
    case list
    case chooser(item: ClipboardItem)
}

/// Owns everything the clipboard-history feature needs except the AppKit
/// panel itself: the poll timer, the in-memory `ClipboardHistory`, and all
/// state a (dumb, view-only) panel would render. The panel is expected to
/// read this controller's state and forward key events to its entry
/// points; the app's status-menu toggle calls `enable()`/`disable()` to
/// turn the feature on and off.
///
/// macOS has no clipboard-change notification, so production polls
/// `NSPasteboard.general.changeCount` on a 0.5s main-queue timer. Tests skip
/// the timer entirely and call `pollNow()` directly to simulate a tick.
@MainActor
final class ClipboardHistoryController {
    private static let pollInterval: TimeInterval = 0.5

    /// The two chooser rows, in display order. `.withoutFormatting` is
    /// always pre-selected when the chooser opens.
    private enum ChooserOption: Int, CaseIterable {
        case withoutFormatting = 0
        case withFormatting = 1
    }

    /// Internal source of truth for what the panel is doing. `.chooser`
    /// carries both the item being decided on and the list-mode selection
    /// to restore on Esc, so those two facts can never drift out of sync
    /// the way separately-mutable fields could.
    private enum PanelState {
        case list
        case chooser(item: ClipboardItem, savedListSelection: Int)
    }

    private let reader: PasteboardReading
    private let writer: PasteboardWriting
    private let keystrokes: KeystrokeSending
    /// Runs `sendPasteKeystroke()` after a short delay so the previously
    /// focused app regains key focus before the synthetic Cmd+V arrives.
    /// Injected as a plain closure — rather than a `TimeInterval` the
    /// caller awaits, the way `CaptureFlow`'s settle delay works — so
    /// tests can run it synchronously by invoking the closure immediately,
    /// or capture it to run later, as the ordering test does.
    private let delay: (@escaping () -> Void) -> Void

    private var history = ClipboardHistory()
    private var timer: Timer?
    /// The `changeCount` as of the last processed poll (or the baseline
    /// captured at `init`/`enable()`/our own paste). A poll only touches
    /// the reader when the current count differs from this.
    private var lastSeenChangeCount: Int
    private var panelState: PanelState = .list

    private(set) var isEnabled = false
    private(set) var searchQuery = ""
    private(set) var visibleItems: [ClipboardItem] = []
    private(set) var selectionIndex = 0

    /// What the panel should currently render. The only public view of
    /// `panelState` — it drops the saved list selection, which is the
    /// controller's own business, and keeps the item, which the panel
    /// needs to name in the chooser header.
    var mode: ClipboardPanelMode {
        switch panelState {
        case .list: return .list
        case .chooser(let item, _): return .chooser(item: item)
        }
    }

    /// Fired whenever anything the panel renders changes: the item list,
    /// the selection, or the mode.
    var onListChanged: (@MainActor () -> Void)?
    /// Fired when the panel should close: after Esc in list mode, or right
    /// before a paste hands focus back to the previously active app.
    var onPanelShouldClose: (@MainActor () -> Void)?

    init(
        reader: PasteboardReading = SystemPasteboard(),
        writer: PasteboardWriting = SystemPasteboard(),
        keystrokes: KeystrokeSending = CGEventKeystrokeSender(),
        delay: @escaping (@escaping () -> Void) -> Void = { work in
            // A one-shot, non-repeating timer sidesteps GCD's asyncAfter,
            // whose completion handler must be @Sendable — `work` isn't,
            // since callers of `delay` capture plain (non-Sendable) state.
            let timer = Timer(timeInterval: 0.05, repeats: false) { _ in work() }
            RunLoop.main.add(timer, forMode: .common)
        }
    ) {
        self.reader = reader
        self.writer = writer
        self.keystrokes = keystrokes
        self.delay = delay
        // Baseline the change count up front so whatever was already on the
        // pasteboard before launch is never recorded — only changes from
        // here on are.
        self.lastSeenChangeCount = reader.changeCount
    }

    // MARK: - Enable / disable

    /// Starts polling. Re-baselines the change count so content copied
    /// while the feature was disabled is not recorded either. No-op when
    /// already enabled.
    func enable() {
        guard !isEnabled else { return }
        isEnabled = true
        lastSeenChangeCount = reader.changeCount
        startTimer()
    }

    /// Stops polling and clears the history. No-op when already disabled.
    func disable() {
        guard isEnabled else { return }
        isEnabled = false
        timer?.invalidate()
        timer = nil
        history.clear()
        resetToListMode()
        refilter()
    }

    // MARK: - Polling

    /// Called by the production timer every 0.5s, and directly by tests
    /// simulating a tick. A no-op while disabled, so a tick that races with
    /// `disable()` can't resurrect anything.
    func pollNow() {
        guard isEnabled else { return }
        let currentCount = reader.changeCount
        guard currentCount != lastSeenChangeCount else { return }
        lastSeenChangeCount = currentCount

        // nil covers marked (password manager), oversized, and unsupported
        // content — the reader has already decided; the controller just
        // moves on.
        guard let item = reader.readCurrentItem(now: Date()) else { return }
        history.add(item)
        refilter()
    }

    // MARK: - Panel entry points

    /// Resets to a fresh, unfiltered view before the panel is shown: the
    /// search cleared, the first row selected, and any lingering chooser
    /// state dropped. Call this right before presenting the panel so it
    /// always opens on "everything, newest first, top row highlighted"
    /// regardless of how it was left last time.
    func prepareForPresentation() {
        resetToListMode()
        searchQuery = ""
        refilter()
    }

    /// Mode-aware, so the panel can forward Enter blindly regardless of
    /// what it's currently showing: in list mode, pastes the selected item
    /// at once, or — for text carrying rich flavors — opens the chooser
    /// instead; in chooser mode, delegates to `chooserSelectionConfirmed()`.
    func enterPressed() {
        switch panelState {
        case .chooser:
            chooserSelectionConfirmed()
        case .list:
            guard selectionIndex >= 0, selectionIndex < visibleItems.count else { return }
            let item = visibleItems[selectionIndex]
            if item.hasRichFlavors {
                enterChooserMode(for: item)
            } else {
                paste(item, withFormatting: false)
            }
        }
    }

    /// Pastes the item the chooser captured: without formatting for
    /// selection 0 (the default), with formatting for selection 1. Reached
    /// only through `enterPressed()`, which is the panel's one way in
    /// regardless of the mode it happens to be showing.
    private func chooserSelectionConfirmed() {
        guard case .chooser(let item, _) = panelState else { return }
        paste(item, withFormatting: selectionIndex == ChooserOption.withFormatting.rawValue)
    }

    /// Chooser mode: backs out to the list, restoring the selection that
    /// was active before the chooser opened — clamped, since an item
    /// removed while the chooser was open (e.g. a deleted screenshot) may
    /// have left that saved index past the end. List mode: closes the
    /// panel.
    func escPressed() {
        switch panelState {
        case .chooser(_, let savedListSelection):
            panelState = .list
            selectionIndex = min(max(savedListSelection, 0), maxSelectionIndex)
            onListChanged?()
        case .list:
            onPanelShouldClose?()
        }
    }

    /// Replaces the filter and resets the selection to the top. List mode
    /// only — the chooser has nothing to filter, and typing there must not
    /// disturb what it pre-selected. A caller that owns an editable field
    /// reads `searchQuery` back afterwards to stay in step.
    func setSearchQuery(_ query: String) {
        guard case .list = panelState else { return }
        searchQuery = query
        selectionIndex = 0
        refilter()
    }

    func moveSelectionUp() {
        guard selectionIndex > 0 else { return }
        selectionIndex -= 1
        onListChanged?()
    }

    func moveSelectionDown() {
        guard selectionIndex < maxSelectionIndex else { return }
        selectionIndex += 1
        onListChanged?()
    }

    /// Jumps the selection straight to `index`, clamped into whatever the
    /// panel is showing — what a click on a row needs, and one
    /// `onListChanged` instead of the one per row that walking there with
    /// `moveSelectionUp()` / `moveSelectionDown()` would fire.
    ///
    /// Works in both modes, and needs no mode check of its own:
    /// `maxSelectionIndex` already knows whether the rows on screen are
    /// history rows or the chooser's two, so the clamp below lands
    /// correctly either way.
    func selectRow(_ index: Int) {
        selectionIndex = min(max(index, 0), maxSelectionIndex)
        onListChanged?()
    }

    /// Drops one item from the history by content hash — e.g. when the
    /// screenshot it represents is deleted from its thumbnail or editor.
    func removeItem(hash: String) {
        history.remove(hash: hash)
        refilter()
    }

    // MARK: - Paste hand-off

    /// Order matters: the panel is told to close before the write, so the
    /// target app's focus starts settling immediately; the keystroke itself
    /// waits an extra beat (`delay`) so that settling has time to finish
    /// before the synthetic Cmd+V lands.
    ///
    /// `writer.write` returns the change count the write itself produced,
    /// and we adopt that value directly as the new baseline — this is
    /// self-write suppression, and it stops the very next poll from
    /// reading our own write back. Reading `reader.changeCount` back out
    /// afterward instead would leave a gap in which a third-party copy
    /// could land and get recorded under this baseline, silently swallowed
    /// as if it were our own write. We still want the item to move to the
    /// top of the history, though, and with its full flavors intact even
    /// when the paste itself was plain-only — a real pasteboard write-
    /// without-formatting only puts the plain string on the system
    /// pasteboard, so letting a poll re-read it would silently downgrade
    /// the stored item (and the chooser would never offer it again).
    /// Re-adding the original `item` value directly sidesteps that: the
    /// existing dedupe-to-top rule in `ClipboardHistory.add` moves it to
    /// the top without touching what it's made of.
    private func paste(_ item: ClipboardItem, withFormatting: Bool) {
        resetToListMode()
        onPanelShouldClose?()
        lastSeenChangeCount = writer.write(item, withFormatting: withFormatting)

        history.add(item)
        refilter()

        // Captures the seam itself, not self, so the keystroke still fires
        // even if whatever owns this controller has gone away by the time
        // the delay elapses — the pasteboard write above already happened
        // and shouldn't be left half finished.
        let keystrokes = self.keystrokes
        delay { keystrokes.sendPasteKeystroke() }
    }

    // MARK: - Helpers

    private func enterChooserMode(for item: ClipboardItem) {
        panelState = .chooser(item: item, savedListSelection: selectionIndex)
        selectionIndex = ChooserOption.withoutFormatting.rawValue
        onListChanged?()
    }

    private func resetToListMode() {
        panelState = .list
        selectionIndex = 0
    }

    private func refilter() {
        visibleItems = history.filtered(query: searchQuery)
        selectionIndex = min(max(selectionIndex, 0), maxSelectionIndex)
        onListChanged?()
    }

    private var maxSelectionIndex: Int {
        switch panelState {
        case .list: return max(visibleItems.count - 1, 0)
        case .chooser: return ChooserOption.allCases.count - 1
        }
    }

    private func startTimer() {
        timer?.invalidate()
        let newTimer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            // Timers scheduled from the main thread fire on the main run loop.
            MainActor.assumeIsolated { self?.pollNow() }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }
}
