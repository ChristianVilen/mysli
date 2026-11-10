import Foundation

@MainActor
final class DictationController {
    typealias Schedule = (Double, @escaping @MainActor () -> Void) -> () -> Void

    @MainActor private final class Work {
        var capture: (any DictationCapture)?
        var task: Task<Void, Never>?
        var timers: [() -> Void] = []
        var delivering = false

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

    private final class Preparation {
        var task: Task<Void, Never>?
        var polishTask: Task<Void, Never>?
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
        case idle, listening(Hold), transcribing(Work), polishing(Work), settling(Work), notice(Notice)

        var work: Work? {
            switch self {
            case .listening(let hold): return hold.work
            case .transcribing(let work), .polishing(let work), .settling(let work): return work
            case .idle, .notice: return nil
            }
        }
    }

    private enum State {
        case disabled(Work?)
        case loading(Preparation, Work?)
        case ready(Ready, Phase)
        case failed(Notice, Work?)
    }

    private let keys: any DictationKeyInput
    private let recorder: any DictationCapturing
    private let speech: any DictationSpeechPreparing
    private let polisher: any DictationPolishing
    private let paster: any DictationPasting
    private let now: () -> Double
    private let schedule: Schedule
    private let prepareText: (String) async throws -> DictationPolishRequest
    private var state = State.disabled(nil)

    private(set) var lastDictation: LastDictation?
    var onChange: (() -> Void)?

    init(keys: any DictationKeyInput, recorder: any DictationCapturing,
         speech: any DictationSpeechPreparing, polisher: any DictationPolishing,
         paster: any DictationPasting, now: @escaping () -> Double,
         schedule: @escaping Schedule,
         prepareText: @escaping (String) async throws -> DictationPolishRequest) {
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
        case .failed(let notice, _): return notice.presentation
        case .ready(_, let phase):
            switch phase {
            case .idle: return .idle
            case .listening(let hold): return .listening(level: hold.level, warning: hold.warning)
            case .transcribing, .settling: return .transcribing
            case .polishing: return .polishing
            case .notice(let notice): return notice.presentation
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        if !enabled { disable(); return }
        guard case .disabled(let pending) = state else { return }
        let preparation = Preparation()
        state = .loading(preparation, pending)
        do {
            try keys.start { [weak self, weak preparation] event in
                guard let self, let preparation, self.ownsKeys(preparation) else { return }
                self.receive(event)
            }
        } catch {
            keys.stop()
            showStartupError()
            return
        }
        preparation.polishTask = Task { [polisher] in await polisher.prepare() }
        preparation.task = Task { [weak self, speech] in
            do {
                let session = try await speech.prepare()
                guard let self, case .loading(let current, let pending) = self.state,
                      current === preparation else { session.release(); return }
                let ready = Ready(speech: session, preparation: preparation)
                self.state = .ready(ready, pending.map(Phase.settling) ?? .idle)
                self.publish()
            } catch {
                guard let self, case .loading(let current, _) = self.state,
                      current === preparation else { return }
                preparation.polishTask?.cancel()
                self.polisher.stop()
                self.keys.stop()
                self.showStartupError()
            }
        }
        publish()
    }

    private func ownsKeys(_ preparation: Preparation) -> Bool {
        switch state {
        case .loading(let current, _): return current === preparation
        case .ready(let ready, _): return ready.preparation === preparation
        case .disabled, .failed: return false
        }
    }

    func receive(_ event: DictationKeyEvent) {
        switch event {
        case .pressed: press()
        case .released: releaseHold()
        case .cancelled: cancel()
        case .unavailable:
            switch state {
            case .loading(let preparation, _):
                preparation.task?.cancel()
                preparation.polishTask?.cancel()
                polisher.stop()
                keys.stop()
                showStartupError()
            case .ready(let ready, let phase):
                if phase.work?.delivering == true { cancel() }
                else { showNotice(.error, ready: ready, cancelling: phase.work) }
            case .disabled, .failed: break
            }
        }
    }

    private func press() {
        guard case .ready(let ready, let phase) = state else { return }
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
        work.delivering = true
        do {
            try await paster.paste(text)
            work.delivering = false
            guard ownsActive(work) else { settle(work); return }
            if unpolished { showNotice(.unpolished, ready: ready) }
            else { state = .ready(ready, .idle); publish() }
        } catch {
            work.delivering = false
            guard ownsActive(work) else { settle(work); return }
            showNotice(.error, ready: ready)
        }
    }

    func pasteLastAgain() {
        guard let lastDictation, case .ready(let ready, let phase) = state else { return }
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
        state = .ready(ready, work.delivering ? .settling(work) : .idle)
        work.cancel()
        publish()
    }

    func shutdown() { disable() }

    private func disable() {
        let old = state
        let pending: Work?
        switch old {
        case .disabled(let work), .loading(_, let work): pending = work
        case .ready(_, let phase): pending = phase.work.flatMap { $0.delivering ? $0 : nil }
        case .failed(_, let work): pending = work
        }
        state = .disabled(pending)
        keys.stop()
        switch old {
        case .loading(let preparation, _):
            preparation.task?.cancel()
            preparation.polishTask?.cancel()
        case .ready(let ready, let phase):
            phase.work?.cancel()
            if case .notice(let notice) = phase { notice.cancelExpiry?() }
            ready.preparation.polishTask?.cancel()
            ready.speech.release()
        case .failed(let notice, _): notice.cancelExpiry?()
        case .disabled: break
        }
        polisher.stop()
        publish()
    }

    private func owns(_ work: Work) -> Bool {
        guard !Task.isCancelled else { return false }
        return ownsActive(work)
    }

    private func ownsActive(_ work: Work) -> Bool {
        guard case .ready(_, let phase) = state else { return false }
        if case .settling = phase { return false }
        return phase.work === work
    }

    private func settle(_ work: Work) {
        switch state {
        case .disabled(let pending) where pending === work: state = .disabled(nil)
        case .loading(let preparation, let pending) where pending === work: state = .loading(preparation, nil)
        case .failed(let notice, let pending) where pending === work: state = .failed(notice, nil)
        case .ready(let ready, .settling(let pending)) where pending === work: state = .ready(ready, .idle)
        default: return
        }
        publish()
    }

    private func showStartupError() {
        let pending: Work?
        if case .loading(_, let work) = state { pending = work } else { pending = nil }
        let notice = Notice(.error)
        state = .failed(notice, pending)
        notice.cancelExpiry = schedule(2) { [weak self, weak notice] in
            guard let self, let notice, case .failed(let current, let pending) = self.state,
                  current === notice else { return }
            self.state = .disabled(pending)
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
