import Carbon.HIToolbox
import Foundation

final class HotkeyManager {
    var onHotkeyPressed: ((HotkeyAction) -> Void)?
    var onRegistrationFailure: ((HotkeyAction, OSStatus) -> Void)?

    private var registeredRefs: [HotkeyAction: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?

    init() {
        installEventHandlerIfNeeded()
    }

    deinit {
        unregisterAll()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func register(_ hotkeys: [HotkeyAction: Hotkey]) {
        unregisterAll()

        for action in HotkeyAction.allCases {
            guard let hotkey = hotkeys[action], hotkey.isValid else { continue }
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: 0x4D425454, id: action.hotKeyID)
            let status = RegisterEventHotKey(
                hotkey.keyCode,
                hotkey.modifiers,
                hotKeyID,
                GetEventDispatcherTarget(),
                0,
                &hotKeyRef
            )

            if status == noErr, let hotKeyRef {
                registeredRefs[action] = hotKeyRef
            } else {
                onRegistrationFailure?(action, status)
            }
        }
    }

    private func unregisterAll() {
        for (_, ref) in registeredRefs {
            UnregisterEventHotKey(ref)
        }
        registeredRefs.removeAll()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyEventHandler,
            1,
            &eventSpec,
            selfPointer,
            &eventHandlerRef
        )
    }

    fileprivate func handleHotKeyEvent(_ event: EventRef?) -> OSStatus {
        guard let event else { return noErr }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr, let action = HotkeyAction(hotKeyID: hotKeyID.id) else {
            return status
        }

        onHotkeyPressed?(action)
        return noErr
    }
}

private let hotKeyEventHandler: EventHandlerUPP = { _, eventRef, userData in
    guard let userData else { return noErr }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    return manager.handleHotKeyEvent(eventRef)
}
