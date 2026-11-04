import Carbon.HIToolbox

enum HotkeyShortcut: CaseIterable {
    case captureFullScreen, captureArea, clipboardHistory
    case tileLeft, tileRight, maximize, center

    var keyCode: UInt32 {
        switch self {
        case .captureFullScreen: return UInt32(kVK_ANSI_3)
        case .captureArea: return UInt32(kVK_ANSI_4)
        case .clipboardHistory, .center: return UInt32(kVK_ANSI_C)
        case .tileLeft: return UInt32(kVK_LeftArrow)
        case .tileRight: return UInt32(kVK_RightArrow)
        case .maximize: return UInt32(kVK_Return)
        }
    }

    var keycap: Keycap {
        switch self {
        case .captureFullScreen: return Keycap(symbol: "3", name: "3")
        case .captureArea: return Keycap(symbol: "4", name: "4")
        case .clipboardHistory, .center: return Keycap(symbol: "C", name: "C")
        case .tileLeft: return Keycap(symbol: "←", name: "Left Arrow")
        case .tileRight: return Keycap(symbol: "→", name: "Right Arrow")
        case .maximize: return Keycap(symbol: "↵", name: "Return")
        }
    }

    /// In the order macOS menus show modifiers.
    var modifierKeycaps: [Keycap] {
        [(controlKey, Keycap(symbol: "⌃", name: "Control")), (optionKey, Keycap(symbol: "⌥", name: "Option")),
         (shiftKey, Keycap(symbol: "⇧", name: "Shift")), (cmdKey, Keycap(symbol: "⌘", name: "Command"))]
            .filter { modifiers & UInt32($0.0) != 0 }
            .map(\.1)
    }

    var isTiling: Bool {
        switch self {
        case .tileLeft, .tileRight, .maximize, .center: return true
        default: return false
        }
    }

    var isScreenshot: Bool { self == .captureFullScreen || self == .captureArea }

    var modifiers: UInt32 {
        UInt32(isTiling ? controlKey | optionKey : cmdKey | shiftKey)
    }

    var label: String {
        switch self {
        case .captureFullScreen: return "⇧⌘3 (full screen)"
        case .captureArea: return "⇧⌘4 (selected area)"
        case .clipboardHistory: return "⇧⌘C (clipboard history)"
        case .tileLeft: return "⌃⌥← (tile left)"
        case .tileRight: return "⌃⌥→ (tile right)"
        case .maximize: return "⌃⌥Return (maximize)"
        case .center: return "⌃⌥C (center)"
        }
    }

    var action: HotkeyAction {
        switch self {
        case .captureFullScreen: return .captureFullScreen
        case .captureArea: return .captureArea
        case .clipboardHistory: return .showClipboardHistory
        case .tileLeft: return .tile(.leftHalf)
        case .tileRight: return .tile(.rightHalf)
        case .maximize: return .tile(.maximize)
        case .center: return .tile(.center)
        }
    }
}

struct Keycap: Equatable {
    let symbol: String
    /// What VoiceOver says for the symbol.
    let name: String
}

enum HotkeyRegistrationFailure: Equatable {
    case systemConflict
    case systemLookupFailed(OSStatus)
    case registrationFailed(OSStatus)
    case releaseFailed(OSStatus)
}

struct HotkeyRegistrationIssue: Equatable {
    let shortcut: HotkeyShortcut
    let failure: HotkeyRegistrationFailure
}
