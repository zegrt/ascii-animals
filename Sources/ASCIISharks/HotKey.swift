import Carbon.HIToolbox

/// A system-wide shortcut via Carbon's RegisterEventHotKey: no Accessibility
/// permission needed, and the keystroke is consumed only for this combination.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private static var instances: [UInt32: HotKey] = [:]
    private static let id: UInt32 = 1

    init(action: @escaping () -> Void) { self.action = action }

    /// ⌃⌥⌘P.
    func setEnabled(_ on: Bool) {
        if on, ref == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            HotKey.instances[HotKey.id] = self
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hk)
                HotKey.instances[hk.id]?.action()
                return noErr
            }, 1, &spec, nil, &handler)
            let hid = EventHotKeyID(signature: OSType(0x4153_4B53), id: HotKey.id) // 'ASKS'
            RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(cmdKey | optionKey | controlKey), hid, GetApplicationEventTarget(), 0, &ref)
        } else if !on, let r = ref {
            UnregisterEventHotKey(r)
            ref = nil
            if let h = handler { RemoveEventHandler(h); handler = nil }
            HotKey.instances[HotKey.id] = nil
        }
    }
}
