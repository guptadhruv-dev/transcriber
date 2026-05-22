import CoreGraphics
import AppKit

struct HotkeyConfig {
    let keyCode: Int64
    let modifiers: CGEventFlags

    static let `default` = HotkeyConfig(
        keyCode: 0x11,
        modifiers: CGEventFlags([.maskControl, .maskAlternate])
    )

    static func load() -> HotkeyConfig {
        guard UserDefaults.standard.object(forKey: "hotkeyKeyCode") != nil else { return .default }
        let keyCode = Int64(UserDefaults.standard.integer(forKey: "hotkeyKeyCode"))
        let raw = UInt64(bitPattern: Int64(UserDefaults.standard.integer(forKey: "hotkeyModifiers")))
        return HotkeyConfig(keyCode: keyCode, modifiers: CGEventFlags(rawValue: raw))
    }

    func save() {
        UserDefaults.standard.set(Int(keyCode), forKey: "hotkeyKeyCode")
        UserDefaults.standard.set(Int(bitPattern: UInt(modifiers.rawValue)), forKey: "hotkeyModifiers")
    }

    var displayString: String {
        var s = ""
        if modifiers.contains(.maskControl)   { s += "⌃" }
        if modifiers.contains(.maskAlternate) { s += "⌥" }
        if modifiers.contains(.maskShift)     { s += "⇧" }
        if modifiers.contains(.maskCommand)   { s += "⌘" }
        s += keyCodeLabel(keyCode)
        return s
    }

    private func keyCodeLabel(_ code: Int64) -> String {
        let map: [Int64: String] = [
            0x00:"A", 0x01:"S", 0x02:"D", 0x03:"F", 0x04:"H", 0x05:"G",
            0x06:"Z", 0x07:"X", 0x08:"C", 0x09:"V", 0x0B:"B", 0x0C:"Q",
            0x0D:"W", 0x0E:"E", 0x0F:"R", 0x10:"Y", 0x11:"T", 0x12:"1",
            0x13:"2", 0x14:"3", 0x15:"4", 0x16:"6", 0x17:"5", 0x1F:"O",
            0x20:"U", 0x22:"I", 0x23:"P", 0x25:"L", 0x26:"J", 0x28:"K",
            0x29:";", 0x2B:",", 0x2C:"/", 0x2D:"N", 0x2E:"M", 0x2F:".",
            0x31:"Space", 0x33:"⌫", 0x35:"⎋",
            0x7A:"F1", 0x78:"F2", 0x63:"F3", 0x76:"F4", 0x60:"F5",
            0x61:"F6", 0x62:"F7", 0x64:"F8", 0x65:"F9", 0x6D:"F10",
            0x67:"F11", 0x6F:"F12"
        ]
        return map[code] ?? "?"
    }
}

@Observable
final class HotkeyService {
    var accessibilityGranted = false
    var config: HotkeyConfig = .load()
    var isMuted = false

    private var eventTap: CFMachPort?
    private weak var model: TranscriberModel?

    func start(model: TranscriberModel) {
        self.model = model
        requestAccessibilityIfNeeded()
        installTap()
    }

    func stop() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        eventTap = nil
    }

    func retryInstall() {
        stop()
        installTap()
    }

    func updateConfig(_ newConfig: HotkeyConfig) {
        config = newConfig
        newConfig.save()
        stop()
        installTap()
    }

    private func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func installTap() {
        accessibilityGranted = AXIsProcessTrusted()
        guard accessibilityGranted else { return }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }

                let service = Unmanaged<HotkeyService>
                    .fromOpaque(refcon)
                    .takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = service.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return nil
                }

                guard !service.isMuted else { return Unmanaged.passUnretained(event) }

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                let relevantMask = CGEventFlags([.maskControl, .maskAlternate, .maskCommand, .maskShift])
                let actualMods = flags.intersection(relevantMask)
                let requiredMods = service.config.modifiers.intersection(relevantMask)

                if keyCode == service.config.keyCode && actualMods == requiredMods {
                    DispatchQueue.main.async { service.model?.toggleRecording() }
                    return nil
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        )

        guard let tap else {
            accessibilityGranted = false
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}
