import Cocoa
import Carbon.HIToolbox

enum DictationKeyMode: String, CaseIterable { case fn, carbon }
enum DictationKeyFailure: Error, Equatable { case permission, source, carbon }

enum FnKeyEvent {
    case flagsChanged(keyCode: UInt16, fn: Bool)
    case keyDown(UInt16)
    case lost
}

@MainActor
protocol FnEventSource: AnyObject {
    var isAvailable: Bool { get }
    func requestPermission() -> Bool
    func start(_ receive: @escaping (FnKeyEvent) -> Void) throws
    func stop()
}

@MainActor
final class SystemDictationKeyInput: DictationKeyInput {
    private enum FnHold { case up, down, cancelled }
    private let manager: HotkeyManager
    private let source: any FnEventSource
    private var receive: (@MainActor (DictationKeyEvent) -> Void)?
    private var generation = UUID()
    private var hold = FnHold.up
    private var cancellable = false
    private var updatingCarbon = false
    private(set) var mode: DictationKeyMode
    private(set) var failure: DictationKeyFailure?
    private var retainedIssues: [HotkeyRegistrationIssue] = []
    var onAvailabilityChange: (() -> Void)?

    init(manager: HotkeyManager, source: any FnEventSource = PassiveFnEventSource(),
         mode: DictationKeyMode = .fn) {
        self.manager = manager
        self.source = source
        self.mode = mode
    }

    isolated deinit { stop() }

    var isAvailable: Bool {
        switch mode {
        case .fn: return source.isAvailable
        case .carbon:
            return manager.isRunning && manager.dictationEnabled && !manager.issues.contains {
                $0.shortcut == .dictation || (cancellable && $0.shortcut == .dictationEscape)
            }
        }
    }

    @discardableResult
    func requestPermission() -> Bool {
        guard mode == .fn else { return true }
        let granted = source.requestPermission()
        onAvailabilityChange?()
        return granted
    }

    /// Stops input. The owner starts it again in the new mode.
    func configure(mode: DictationKeyMode) {
        guard mode != self.mode else { return }
        stop()
        retainedIssues = []
        self.mode = mode
        onAvailabilityChange?()
    }

    func start(_ receive: @escaping @MainActor (DictationKeyEvent) -> Void) throws {
        stop()
        retainedIssues = []
        failure = nil
        let token = UUID()
        generation = token
        self.receive = receive
        do {
            switch mode {
            case .fn:
                guard source.isAvailable else { throw DictationKeyFailure.permission }
                try source.start { [weak self] event in
                    guard let self, self.generation == token, self.receive != nil else { return }
                    self.handle(event)
                }
            case .carbon:
                manager.onDictation = { [weak self] event in
                    guard let self, self.generation == token, let receive = self.receive else { return }
                    receive(event)
                }
                manager.onDictationAvailabilityChange = { [weak self] in
                    guard let self, self.generation == token, self.receive != nil,
                          !self.updatingCarbon else { return }
                    self.onAvailabilityChange?()
                    if !self.isAvailable { self.fail() }
                }
                updatingCarbon = true
                manager.dictationEnabled = true
                updatingCarbon = false
                guard isAvailable, self.receive != nil else { throw DictationKeyFailure.carbon }
            }
        } catch {
            retainedIssues = manager.issues.filter { $0.shortcut == .dictation || $0.shortcut == .dictationEscape }
            stop()
            failure = error as? DictationKeyFailure
            onAvailabilityChange?()
            throw error
        }
        onAvailabilityChange?()
    }

    func setCancellable(_ cancellable: Bool) throws {
        guard self.cancellable != cancellable else { return }
        guard receive != nil else {
            if cancellable { throw failure ?? DictationKeyFailure.source }
            return
        }
        self.cancellable = cancellable
        guard mode == .carbon else { return }
        updatingCarbon = true
        manager.dictationCancellable = cancellable
        updatingCarbon = false
        guard !cancellable || isAvailable else {
            retainedIssues = manager.issues.filter { $0.shortcut == .dictation || $0.shortcut == .dictationEscape }
            self.cancellable = false
            manager.dictationCancellable = false
            failure = .carbon
            onAvailabilityChange?()
            throw DictationKeyFailure.carbon
        }
        if cancellable {
            failure = nil
            retainedIssues = []
        }
    }

    func registrationIssues(enabled: Bool) -> [HotkeyRegistrationIssue] {
        enabled && mode == .carbon ? retainedIssues : []
    }

    func stop() {
        receive = nil
        generation = UUID()
        hold = .up
        cancellable = false
        source.stop()
        manager.onDictation = nil
        manager.onDictationAvailabilityChange = nil
        manager.dictationCancellable = false
        manager.dictationEnabled = false
    }

    private func fail() {
        retainedIssues = manager.issues.filter { $0.shortcut == .dictation || $0.shortcut == .dictationEscape }
        let callback = receive
        receive = nil
        stop()
        failure = mode == .fn ? .source : .carbon
        callback?(.unavailable)
        onAvailabilityChange?()
    }

    private func handle(_ event: FnKeyEvent) {
        switch event {
        case .lost: fail()
        case .flagsChanged(let keyCode, let fn):
            guard keyCode == UInt16(kVK_Function) else {
                if hold == .down { cancelHold() }
                return
            }
            if !fn {
                let wasHeld = hold == .down
                hold = .up
                if wasHeld { receive?(.released) }
            } else if hold == .up {
                hold = .down
                receive?(.pressed)
            }
        case .keyDown(let keyCode):
            if hold == .down { cancelHold() }
            else if keyCode == UInt16(kVK_Escape), cancellable { receive?(.cancelled) }
        }
    }

    private func cancelHold() {
        hold = .cancelled
        receive?(.cancelled)
    }
}

@MainActor
final class PassiveFnEventSource: FnEventSource {
    private final class Owner {
        weak var value: PassiveFnEventSource?
        init(_ value: PassiveFnEventSource) { self.value = value }
    }
    private static var owners: [ObjectIdentifier: Owner] = [:]
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var receive: ((FnKeyEvent) -> Void)?

    var isAvailable: Bool { CGPreflightListenEventAccess() }
    func requestPermission() -> Bool { CGRequestListenEventAccess() }

    func start(_ receive: @escaping (FnKeyEvent) -> Void) throws {
        stop()
        guard isAvailable else { throw DictationKeyFailure.permission }
        let mask = (CGEventMask(1) << CGEventType.flagsChanged.rawValue) |
            (CGEventMask(1) << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                         options: .listenOnly, eventsOfInterest: mask,
                                         callback: { _, type, event, context in
            if let context {
                MainActor.assumeIsolated {
                    Unmanaged<PassiveFnEventSource>.fromOpaque(context).takeUnretainedValue()
                        .handle(type, event: event)
                }
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            throw DictationKeyFailure.source
        }
        self.receive = receive
        self.tap = tap
        runLoopSource = source
        // The port's context belongs to Core Graphics, not the event callback's userInfo.
        Self.owners[ObjectIdentifier(tap)] = Owner(self)
        CFMachPortSetInvalidationCallBack(tap) { port, _ in
            guard let port else { return }
            Task { @MainActor in
                PassiveFnEventSource.owners[ObjectIdentifier(port)]?.value?.lost()
            }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        receive = nil
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        runLoopSource = nil
        if let tap {
            Self.owners[ObjectIdentifier(tap)] = nil
            CFMachPortSetInvalidationCallBack(tap, nil)
            CFMachPortInvalidate(tap)
        }
        tap = nil
    }

    isolated deinit { stop() }

    private func lost() {
        let callback = receive
        stop()
        callback?(.lost)
    }

    private func handle(_ type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput: lost()
        case .flagsChanged:
            receive?(.flagsChanged(keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                                   fn: event.flags.contains(.maskSecondaryFn)))
        case .keyDown: receive?(.keyDown(UInt16(event.getIntegerValueField(.keyboardEventKeycode))))
        default: break
        }
    }
}
