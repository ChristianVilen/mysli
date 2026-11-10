import Foundation

actor WhisperInferenceQueue {
    private struct Waiter {
        let id: UUID
        let priority: Bool
        let continuation: CheckedContinuation<Void, Error>
    }

    private var occupied = false
    private var waiters: [Waiter] = []

    var pendingCount: Int { waiters.count }

    func run<Value>(priority: Bool, _ operation: () async throws -> Value) async throws -> Value {
        try await acquire(priority: priority)
        defer { advance() }
        try Task.checkCancellation()
        return try await operation()
    }

    private func acquire(priority: Bool) async throws {
        try Task.checkCancellation()
        if !occupied { occupied = true; return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(Waiter(id: id, priority: priority, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func cancel(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func advance() {
        guard !waiters.isEmpty else { occupied = false; return }
        let index = waiters.firstIndex(where: \.priority) ?? 0
        waiters.remove(at: index).continuation.resume()
    }
}
