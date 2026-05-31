import AVFoundation

@Observable
final class AudioRecorder {

    var isRecording = false
    var onInterruption: (() -> Void)?

    private var engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var configObserver: NSObjectProtocol?

    func start() throws -> URL {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        recordingURL = url

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        guard format.sampleRate > 0 else {
            throw NSError(domain: "AudioRecorder", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Audio input not ready (sample rate is 0) — audio device not initialized yet. Try again in a moment."
            ])
        }
        audioFile = try AVAudioFile(forWriting: url, settings: format.settings)

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            try? self?.audioFile?.write(from: buffer)
        }

        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigChange()
        }

        try engine.start()
        isRecording = true
        return url
    }

    func stop() -> URL? {
        cleanup()
        let url = recordingURL
        recordingURL = nil
        return url
    }

    private func handleConfigChange() {
        cleanup()
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        onInterruption?()
    }

    private func cleanup() {
        if let obs = configObserver {
            NotificationCenter.default.removeObserver(obs)
            configObserver = nil
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil
        isRecording = false
    }
}
