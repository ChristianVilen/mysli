import Foundation
import os

@MainActor
protocol DictationClaudeChild: AnyObject {
    func send(_ input: Data, receive: @escaping @MainActor (Result<String, Error>) -> Void)
    func retire(_ reaped: @escaping @MainActor () -> Void)
}

@MainActor
final class DictationPolisher: DictationPolishing {
    private final class Preparation {
        var task: Task<Void, Never>?
    }

    private final class Request {
        let child: any DictationClaudeChild
        let baseline: PasteText
        let continuation: CheckedContinuation<DictationPolishResult, Never>
        let cancelled: OSAllocatedUnfairLock<Bool>
        var cancelDeadline: (() -> Void)?

        init(child: any DictationClaudeChild, baseline: PasteText,
             continuation: CheckedContinuation<DictationPolishResult, Never>, cancelled: OSAllocatedUnfairLock<Bool>) {
            self.child = child
            self.baseline = baseline
            self.continuation = continuation
            self.cancelled = cancelled
        }
    }

    private let launch: () async throws -> any DictationClaudeChild
    private let schedule: DictationSchedule
    private var enabled = false
    private var preparation: Preparation?
    private var idle: (any DictationClaudeChild)?
    private var active: Request?
    private var retiring = 0
    private var launching = 0
    private var launchFailure: DictationPolishFailure?

    init(launch: @escaping () async throws -> any DictationClaudeChild = { try await DictationClaudeProcess.launch() },
         schedule: @escaping DictationSchedule = { DictationTimer.schedule($0, $1) }) {
        self.launch = launch
        self.schedule = schedule
    }

    func prepare() async {
        guard !Task.isCancelled else { return }
        enabled = true
        await prepareIfEnabled()
    }

    private func prepareIfEnabled() async {
        guard enabled, idle == nil, active == nil else { return }
        if let preparation { await preparation.task?.value; return }
        guard retiring + launching < 2 else { return }
        let pending = Preparation()
        preparation = pending
        launching += 1
        pending.task = Task { [weak self, launch] in
            let child: (any DictationClaudeChild)?
            let failure: DictationPolishFailure?
            do { child = try await launch(); failure = nil }
            catch { child = nil; failure = DictationPolishFailure(error) }
            guard let self else { child?.retire({}); return }
            self.launching -= 1
            guard self.preparation === pending, self.enabled else {
                if let child { self.retire(child) }
                self.startSuccessor()
                return
            }
            self.preparation = nil
            self.idle = child
            self.launchFailure = failure
        }
        await pending.task?.value
    }

    func polish(_ request: DictationPolishRequest) async -> DictationPolishResult {
        guard !Task.isCancelled, enabled, active == nil, let child = idle else {
            startSuccessor()
            return .unavailable(noChildReason)
        }
        let input: Data
        do { input = try DictationClaudeWire.input(request) }
        catch {
            startSuccessor()
            return .unavailable(DictationPolishFailure(error))
        }
        idle = nil
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let pending = Request(child: child, baseline: request.localText, continuation: continuation, cancelled: cancelled)
                active = pending
                pending.cancelDeadline = schedule(2.5) { [weak self, weak pending] in
                    guard let pending else { return }
                    self?.finish(pending, .unavailable(.timedOut))
                }
                child.send(input) { [weak self, weak pending] result in
                    guard let self, let pending else { return }
                    switch result {
                    case .success(let output):
                        let accepted = DictationText.accept(output, baseline: pending.baseline)
                        self.finish(pending, accepted.map(DictationPolishResult.polished) ?? .unavailable(.rejected))
                    case .failure(let error):
                        self.finish(pending, .unavailable(DictationPolishFailure(error)))
                    }
                }
                if Task.isCancelled { finish(pending, .unavailable(.cancelled)) }
            }
        } onCancel: {
            cancelled.withLock { $0 = true }
            Task { @MainActor [weak self, weak child] in
                guard let self, let child, let pending = self.active, pending.child === child else { return }
                self.finish(pending, .unavailable(.cancelled))
            }
        }
    }

    private var noChildReason: DictationPolishFailure {
        if Task.isCancelled { return .cancelled }
        guard enabled, active == nil, let launchFailure else { return .notReady }
        return launchFailure
    }

    func stop() {
        enabled = false
        preparation?.task?.cancel()
        preparation = nil
        if let pending = active { finish(pending, .unavailable(.cancelled)) }
        if let child = idle { idle = nil; retire(child) }
    }

    private func finish(_ pending: Request, _ result: DictationPolishResult) {
        guard active === pending else { return }
        active = nil
        pending.cancelDeadline?()
        pending.continuation.resume(returning: pending.cancelled.withLock { $0 } ? .unavailable(.cancelled) : result)
        retire(pending.child)
        startSuccessor()
    }

    private func retire(_ child: any DictationClaudeChild) {
        retiring += 1
        child.retire { [weak self] in
            guard let self else { return }
            self.retiring -= 1
            self.startSuccessor()
        }
    }

    private func startSuccessor() {
        guard enabled else { return }
        Task { [weak self] in await self?.prepareIfEnabled() }
    }
}

extension DictationPolishFailure {
    init(_ error: any Error) {
        switch error as? DictationClaudeFailure {
        case .notInstalled?: self = .notInstalled
        case .notLoggedIn?: self = .notLoggedIn
        case .unavailable?, nil: self = .couldNotStart
        case .ended?: self = .ended
        case .malformed?: self = .unreadable
        case .limit?: self = .tooLong
        }
    }
}
