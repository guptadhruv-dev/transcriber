import SwiftUI

struct MenuView: View {

    @Environment(TranscriberModel.self) private var model

    var body: some View {
        if !model.hotkey.accessibilityGranted {
            accessibilityWarning
            Divider()
        }
        if let error = model.lastError {
            errorBanner(error)
            Divider()
        }
        
        Text(model.statusMessage)
            .padding(.vertical, 4)

        Divider()

        Button {
            model.toggleRecording()
        } label: {
            Text("Toggle Recording")
        }
        .disabled(!model.hotkey.accessibilityGranted || !model.isModelReady)

        if !model.lastTranscript.isEmpty {
            Divider()
            Button("Copy Last Transcript") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.lastTranscript, forType: .string)
            }
            .padding(.vertical, 4)
        }

        Divider()

        Picker("Refinement Effort", selection: Bindable(model).refinementLevel) {
            ForEach(RefinementLevel.allCases) { level in
                Text(level.label).tag(level)
            }
        }

        if model.refinementLevel != .off {
            Text(ollamaStatusLabel)
                .font(.caption)
                .foregroundStyle(ollamaStatusColor)
                .padding(.horizontal, 8)
        }

        Divider()

        Button("Shortcut = \(model.hotkey.config.displayString)") {
            model.hotkey.isMuted = true
            ShortcutRecorder.shared.beginRecording { config in
                model.hotkey.isMuted = false
                if let config { model.hotkey.updateConfig(config) }
            }
        }
        
        Divider()

        Toggle("Launch at Login", isOn: Bindable(model).launchAtLogin.isEnabled)

        Divider()

        Button("Quit Transcriber") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var ollamaStatusLabel: String {
        switch model.ollamaStatus {
        case .offline: return "Ollama: offline"
        case .idle:    return "Ollama: idle"
        case .loaded:  return "Ollama: loaded"
        }
    }

    private var ollamaStatusColor: Color {
        switch model.ollamaStatus {
        case .offline: return .red
        case .idle:    return .orange
        case .loaded:  return .green
        }
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Last Error", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.callout.weight(.medium))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Clear") { model.clearError() }
                .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private var accessibilityWarning: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Accessibility needed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout.weight(.medium))

            Text("Grant access in System Settings\nthen click Retry.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Open System Settings…") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                )
            }
            .font(.caption)

            Button("Retry") {
                model.hotkey.retryInstall()
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}
