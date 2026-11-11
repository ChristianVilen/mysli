actor AudioTestSignal {
    private var sent = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func value() async {
        if sent { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func send() {
        sent = true
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }
}
