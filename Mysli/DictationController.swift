import Foundation

@MainActor
final class DictationController {
    @MainActor private final class Work {
        var capture: (any DictationCapture)?
        var task: Task<Void, Never>?
        var timers: [() -> Void] = []

        init(capture: (any DictationCapture)? = nil) { self.capture = capture }
        func cancel() {
            task?.cancel()
            capture?.cancel()
            cancelTimers()
        }
        func cancelTimers() { timers.forEach { $0() }; timers = [] }
    }

    private final class Hold {
        let work: Work
        let startedAt: Double
        var level: Float = 0
        var warning = false
        init(work: Work, startedAt: Double) { self.work = work; self.startedAt = startedAt }
    }

    /// One start of key input. A key callback from an older start holds a different object.
    private final class Input {
        var polishTask: Task<Void, Never>?
    }

    private final class Preparation {
        var task: Task<Void, Never>?
        var input: Input?
    }

    private final class Ready {
        let speech: any DictationSpeechSession
        let preparation: Preparation
        init(speech: any DictationSpeechSession, preparation: Preparation) {
            self.speech = speech
            self.preparation = preparation
        }
    }

    private final class Notice {
        let presentation: DictationPresentation
        var cancelExpiry: (() -> Void)?
        init(_ presentation: DictationPresentation) { self.presentation = presentation }
    }

    private enum Phase {
        case idle, listening(Hold), transcribing(Work), polishing(Work), notice(Notice)

        var work: Work? {
            switch self {
            case .listening(let hold): return hold.work
            case .transcribing(let work), .polishing(let work): return work
            case .idle, .notice: return nil
            }
        }
    }

    private enum State {
        case disabled
        case loading(Preparation)
        case ready(Ready, Phase)
        case failed(Notice)
    }

    private let keys: any DictationKeyInput
    private let recorder: any DictationCapturing
    private let speech: any DictationSpeechPreparing
    private let polisher: any DictationPolishing
    private let paster: any DictationPasting
    private let now: () -> Double
    private let schedule: DictationSchedule
    private let prepareText: (String) async throws -> DictationPolishRequest?
    private var state = State.disabled
    private var hasAccess = true
    private var terminating = false

    private(set) var lastDictation: LastDictation?
    var onChange: (() -> Void)?

    var canPasteLast: Bool {
        guard hasAccess, lastDictation != nil, !paster.isBusy, case .ready(let ready, let phase) = state,
              ready.preparation.input != nil else { return false }
        switch phase {
        case .idle, .notice: return true
        default: return false
        }
    }

    var isListening: Bool {
        if case .ready(_, .listening) = state { return true }
        return false
    }

    init(keys: any DictationKeyInput, recorder: any DictationCapturing,
         speech: any DictationSpeechPreparing, polisher: any DictationPolishing,
         paster: any DictationPasting, now: @escaping () -> Double,
         schedule: @escaping DictationSchedule,
         prepareText: @escaping (String) async throws -> DictationPolishRequest?) {
        self.keys = keys
        self.recorder = recorder
        self.speech = speech
        self.polisher = polisher
        self.paster = paster
        self.now = now
        self.schedule = schedule
        self.prepareText = prepareText
    }

    var presentation: DictationPresentation {
        switch state {
        case .disabled: return .disabled
        case .loading: return .loading
        case .failed(let notice): return notice.presentation
        case .ready(_, let phase):
            switch phase {
            case .idle: return .idle
            case .listening(let hold): return .listening(level: hold.level, warning: hold.warning)
            case .transcribing: return .transcribing
            case .polishing: return .polishing
            case .notice(let notice): return notice.presentation
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        if !enabled || terminating { disable(); return }
        guard case .disabled = state else { return }
        let preparation = Preparation()
        state = .loading(preparation)
        try? startInput(preparation)
        preparation.task = Task { [weak self, speech] in
            do {
                let session = try await speech.prepare()
                guard let self, case .loading(let current) = self.state,
                      current === preparation else { session.release(); return }
                let ready = Ready(speech: session, preparation: preparation)
                self.state = .ready(ready, .idle)
                if self.hasAccess, preparation.input == nil {
                    self.showNotice(.error, ready: ready)
                } else { self.publish() }
            } catch {
                guard let self, case .loading(let current) = self.state,
                      current === preparation else { return }
                self.stopInput(preparation)
                self.showStartupError()
            }
        }
        publish()
    }

    func setAccess(_ allowed: Bool) {
        let changed = allowed != hasAccess
        hasAccess = allowed
        guard let preparation else { return }
        if allowed {
            guard preparation.input == nil else { return }
            do { try startInput(preparation) }
            catch { inputLost(); return }
        } else {
            guard changed else { return }
            stopInput(preparation)
            cancel()
        }
        publish()
    }

    /// Starts key input again, for example after a key mode change. The speech session stays loaded.
    func restartInput() {
        guard let preparation else { return }
        stopInput(preparation)
        cancel()
        do { try startInput(preparation) }
        catch { inputLost(); return }
        publish()
    }

    private var preparation: Preparation? {
        switch state {
        case .loading(let preparation): return preparation
        case .ready(let ready, _): return ready.preparation
        case .disabled, .failed: return nil
        }
    }

    /// Does nothing without access. Throws when the keys cannot start.
    private func startInput(_ preparation: Preparation) throws {
        guard hasAccess, preparation.input == nil else { return }
        let input = Input()
        preparation.input = input
        do {
            try keys.start { [weak self, weak preparation, weak input] event in
                guard let self, let input, preparation?.input === input else { return }
                self.receive(event)
            }
        } catch {
            stopInput(preparation)
            throw error
        }
        input.polishTask = Task { [weak preparation, weak input, polisher] in
            guard !Task.isCancelled, let input, preparation?.input === input else { return }
            await polisher.prepare()
        }
    }

    private func stopInput(_ preparation: Preparation) {
        preparation.input?.polishTask?.cancel()
        preparation.input = nil
        polisher.stop()
        keys.stop()
    }

    private func inputLost() {
        guard let preparation else { return }
        stopInput(preparation)
        guard case .ready(let ready, let phase) = state else { return }
        // A paste in progress still restores the clipboard, so it ends quietly.
        if paster.isBusy { cancel() }
        else { showNotice(.error, ready: ready, cancelling: phase.work) }
    }

    func receive(_ event: DictationKeyEvent) {
        switch event {
        case .pressed: press()
        case .released: releaseHold()
        case .cancelled: cancel()
        case .unavailable: inputLost()
        }
    }

    private func press() {
        guard hasAccess, !paster.isBusy, case .ready(let ready, let phase) = state,
              ready.preparation.input != nil else { return }
        switch phase {
        case .idle: break
        case .notice(let notice): notice.cancelExpiry?()
        default: return
        }
        let startedAt = now()
        let work = Work()
        let hold = Hold(work: work, startedAt: startedAt)
        do {
            try keys.setCancellable(true)
            guard case .ready(let current, let currentPhase) = state,
                  current === ready, currentPhase.work == nil else { return }
            let capture = try recorder.begin(level: { [weak self, weak hold] level in
                guard let self, let hold, case .ready(_, .listening(let current)) = self.state,
                      current === hold else { return }
                hold.level = level
                self.publish()
            }, failed: { [weak self, weak work] _ in
                guard let self, let work, self.owns(work) else { return }
                self.showNotice(.error, ready: ready, cancelling: work)
            })
            work.capture = capture
            state = .ready(ready, .listening(hold))
            work.timers.append(schedule(110) { [weak self, weak hold] in
                guard let self, let hold, self.owns(hold.work) else { return }
                hold.warning = true
                self.publish()
            })
            work.timers.append(schedule(120) { [weak self, weak hold] in
                guard let self, let hold, self.owns(hold.work) else { return }
                self.releaseHold()
            })
            publish()
        } catch { showNotice(.error, ready: ready) }
    }

    private func releaseHold() {
        guard case .ready(let ready, .listening(let hold)) = state else { return }
        let work = hold.work
        work.cancelTimers()
        guard now() >= hold.startedAt + 0.3 else {
            state = .ready(ready, .idle)
            work.cancel()
            publish()
            return
        }
        work.capture?.seal()
        state = .ready(ready, .transcribing(work))
        work.task = Task { [weak self] in await self?.process(work, ready: ready) }
        publish()
    }

    private func process(_ work: Work, ready: Ready) async {
        guard owns(work) else { return }
        do {
            guard let capture = work.capture else { return }
            let audio = try await capture.audio()
            guard owns(work) else { return }
            let result = try await ready.speech.transcribe(audio)
            guard owns(work) else { return }
            switch result {
            case .noSpeech:
                state = .ready(ready, .idle)
                publish()
            case .text(let heard):
                let request = try await prepareText(heard)
                guard owns(work) else { return }
                guard let request else {
                    state = .ready(ready, .idle)
                    publish()
                    return
                }
                state = .ready(ready, .polishing(work))
                publish()
                guard owns(work) else { return }
                let result = await polisher.polish(request)
                guard owns(work) else { return }
                let selected: PasteText
                let unpolished: Bool
                switch result {
                case .polished(let text): selected = text; unpolished = false
                case .unavailable: selected = request.localText; unpolished = true
                }
                lastDictation = LastDictation(heardText: heard, selectedText: selected)
                await deliver(selected, work: work, ready: ready, unpolished: unpolished)
            }
        } catch {
            guard owns(work) else { return }
            showNotice(.error, ready: ready)
        }
    }

    private func deliver(_ text: PasteText, work: Work, ready: Ready, unpolished: Bool) async {
        guard owns(work) else { return }
        do {
            try await paster.paste(text)
            guard owns(work) else { return }
            if unpolished { showNotice(.unpolished, ready: ready) }
            else { state = .ready(ready, .idle); publish() }
        } catch {
            guard owns(work) else { return }
            showNotice(.error, ready: ready)
        }
    }

    func pasteLastAgain() {
        guard canPasteLast, let lastDictation, case .ready(let ready, let phase) = state else { return }
        switch phase {
        case .idle: break
        case .notice(let notice): notice.cancelExpiry?()
        default: return
        }
        let work = Work()
        state = .ready(ready, .transcribing(work))
        work.task = Task { [weak self] in
            await self?.deliver(lastDictation.selectedText, work: work, ready: ready, unpolished: false)
        }
        publish()
    }

    func cancel() {
        guard case .ready(let ready, let phase) = state, let work = phase.work else { return }
        state = .ready(ready, .idle)
        work.cancel()
        publish()
    }

    func shutdown() { disable() }

    /// Keeps dictation off while quit waits for the paster, even if a refresh tries to turn it on.
    func shutDownForTermination() {
        terminating = true
        disable()
    }

    private func disable() {
        let old = state
        state = .disabled
        switch old {
        case .loading(let preparation):
            stopInput(preparation)
            preparation.task?.cancel()
        case .ready(let ready, let phase):
            stopInput(ready.preparation)
            phase.work?.cancel()
            if case .notice(let notice) = phase { notice.cancelExpiry?() }
            ready.speech.release()
        case .failed(let notice): notice.cancelExpiry?()
        case .disabled: break
        }
        publish()
    }

    private func owns(_ work: Work) -> Bool {
        guard !Task.isCancelled, case .ready(_, let phase) = state else { return false }
        return phase.work === work
    }

    private func showStartupError() {
        let notice = Notice(.error)
        state = .failed(notice)
        notice.cancelExpiry = schedule(2) { [weak self, weak notice] in
            guard let self, let notice, case .failed(let current) = self.state,
                  current === notice else { return }
            self.state = .disabled
            self.publish()
        }
        publish()
    }

    private func showNotice(_ presentation: DictationPresentation, ready: Ready, cancelling work: Work? = nil) {
        let notice = Notice(presentation)
        state = .ready(ready, .notice(notice))
        work?.cancel()
        notice.cancelExpiry = schedule(2) { [weak self, weak notice] in
            guard let self, let notice, case .ready(let currentReady, .notice(let current)) = self.state,
                  current === notice else { return }
            self.state = .ready(currentReady, .idle)
            self.publish()
        }
        publish()
    }

    private func publish() {
        let cancellable: Bool
        if case .ready(_, let phase) = state {
            switch phase {
            case .listening, .transcribing, .polishing: cancellable = true
            default: cancellable = false
            }
        } else { cancellable = false }
        do { try keys.setCancellable(cancellable) }
        catch { receive(.unavailable) }
        onChange?()
    }
}
