import Carbon
import Foundation

private let workspaceBarHotkeySignature: OSType = 0x57534252

private func dispatchWorkspaceZeroShortcut(
    _: EventHandlerCallRef?, event: EventRef?, context: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let context else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &id
    )
    guard status == noErr, id.signature == workspaceBarHotkeySignature else {
        return OSStatus(eventNotHandledErr)
    }
    let controller = Unmanaged<WorkspaceZeroShortcuts>.fromOpaque(context).takeUnretainedValue()
    let move = id.id == 2
    DispatchQueue.main.async { controller.action(move) }
    return noErr
}

struct ShortcutRegistrationError: LocalizedError {
    var errorDescription: String? {
        "⌥0 y ⌥⇧0 están reservados por otra app. Cierra el asistente anterior para que esta app los registre."
    }
}

@MainActor
final class WorkspaceZeroShortcuts {
    let action: (Bool) -> Void
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    init(action: @escaping (Bool) -> Void) {
        self.action = action
    }

    func start() throws {
        let target = GetApplicationEventTarget()
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            target, dispatchWorkspaceZeroShortcut, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        guard status == noErr else { throw ShortcutRegistrationError() }
        do {
            try register(modifiers: UInt32(optionKey), actionId: 1, target: target)
            try register(modifiers: UInt32(optionKey | shiftKey), actionId: 2, target: target)
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        for reference in references { UnregisterEventHotKey(reference) }
        references.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    private func register(modifiers: UInt32, actionId: UInt32, target: EventTargetRef?) throws {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_0), modifiers, EventHotKeyID(signature: workspaceBarHotkeySignature, id: actionId),
            target, 0, &reference
        )
        guard status == noErr, let reference else { throw ShortcutRegistrationError() }
        references.append(reference)
    }
}
