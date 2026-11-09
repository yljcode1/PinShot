import Carbon

final class HotKeyService {
    private let id: UInt32
    private var onRelease: (() -> Void)?
    init(id: UInt32 = 1) { self.id = id }
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var onTrigger: (() -> Void)?
    private var registeredConfiguration: HotKeyConfiguration?

    func register(configuration: HotKeyConfiguration, onRelease: (() -> Void)? = nil, handler: @escaping () -> Void) -> Bool {
        if registeredConfiguration == configuration, hotKeyRef != nil {
            onTrigger = handler
            self.onRelease = onRelease
            return true
        }

        if handlerRef == nil {
            var eventTypes = [kEventHotKeyPressed, kEventHotKeyReleased].map {
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32($0))
            }
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
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

                guard status == noErr, let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
                guard hotKeyID.signature == OSType(0x50494E53), hotKeyID.id == service.id else {
                    return OSStatus(eventNotHandledErr)
                }
                if GetEventKind(event) == UInt32(kEventHotKeyReleased) { service.onRelease?() }
                else { service.onTrigger?() }
                return noErr
            }, 2, &eventTypes, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
            guard status == noErr else { return false }
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x50494E53), id: id)
        var newHotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            configuration.keyCode,
            configuration.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newHotKeyRef
        )
        guard status == noErr, let newHotKeyRef else { return false }
        // Keep the working shortcut until the replacement is registered.
        unregister()
        hotKeyRef = newHotKeyRef
        registeredConfiguration = configuration
        self.onRelease = onRelease
        onTrigger = handler
        return true
    }

    func unregister() {
        registeredConfiguration = nil
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    deinit {
        unregister()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }
}
