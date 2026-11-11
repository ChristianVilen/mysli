import Carbon.HIToolbox

/// The five OS calls used by the registrar. Tests replace calls, not registration policy.
struct CarbonHotkeyAPI {
    var copySystemHotkeys: (inout Unmanaged<CFArray>?) -> OSStatus = { CopySymbolicHotKeys(&$0) }
    var register: (HotkeyShortcut, EventHotKeyID, inout EventHotKeyRef?) -> OSStatus = { shortcut, id, reference in
        RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id,
                            GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference)
    }
    var unregister: (EventHotKeyRef) -> OSStatus = { UnregisterEventHotKey($0) }
    var installHandler: (EventHandlerUPP, [EventTypeSpec], UnsafeMutableRawPointer, inout EventHandlerRef?) -> OSStatus = { callback, eventTypes, context, handler in
        var types = eventTypes
        return InstallEventHandler(GetApplicationEventTarget(), callback, types.count, &types, context, &handler)
    }
    var removeHandler: (EventHandlerRef) -> OSStatus = { RemoveEventHandler($0) }
}
