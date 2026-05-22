import AppKit

final class ShortcutRecorder: NSObject, NSWindowDelegate {

    static let shared = ShortcutRecorder()

    private var panel: NSPanel?
    private var monitor: Any?
    private var completion: ((HotkeyConfig?) -> Void)?

    func beginRecording(completion: @escaping (HotkeyConfig?) -> Void) {
        guard panel == nil else { return }
        self.completion = completion

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 110),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Set Shortcut"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 110))

        let label = NSTextField(labelWithString: "Press your new shortcut…")
        label.frame = NSRect(x: 20, y: 64, width: 280, height: 22)
        label.alignment = .center
        label.font = .systemFont(ofSize: 14)

        let hint = NSTextField(labelWithString: "Must include ⌃, ⌥, ⇧, or ⌘")
        hint.frame = NSRect(x: 20, y: 42, width: 280, height: 18)
        hint.alignment = .center
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancelBtn.frame = NSRect(x: 120, y: 10, width: 80, height: 26)
        cancelBtn.bezelStyle = .rounded

        container.addSubview(label)
        container.addSubview(hint)
        container.addSubview(cancelBtn)
        panel.contentView = container

        self.panel = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event)
            return nil
        }
    }

    private static let modifierKeyCodes: Set<UInt16> = [
        0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F
    ]

    private func handleKey(_ event: NSEvent) {
        if event.keyCode == 0x35 {
            finish(with: nil)
            return
        }

        let mods = event.modifierFlags.intersection([.control, .option, .command, .shift])
        guard !mods.isEmpty else { return }
        guard !Self.modifierKeyCodes.contains(event.keyCode) else { return }

        var cgFlags = CGEventFlags()
        if mods.contains(.control) { cgFlags.insert(.maskControl) }
        if mods.contains(.option)  { cgFlags.insert(.maskAlternate) }
        if mods.contains(.command) { cgFlags.insert(.maskCommand) }
        if mods.contains(.shift)   { cgFlags.insert(.maskShift) }

        finish(with: HotkeyConfig(keyCode: Int64(event.keyCode), modifiers: cgFlags))
    }

    @objc private func cancelTapped() { finish(with: nil) }

    func windowWillClose(_ notification: Notification) { finish(with: nil) }

    private func finish(with config: HotkeyConfig?) {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        let captured = panel
        panel = nil
        captured?.close()
        completion?(config)
        completion = nil
    }
}
