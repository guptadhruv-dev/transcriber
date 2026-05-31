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
        guard !isRecording else {
            throw NSError(domain: "AudioRecorder", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Recorder is already running."
            ])
        }

        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        recordingURL = url

        do {
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)

            guard format.sampleRate > 0 else {
                throw NSError(domain: "AudioRecorder", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Audio input not ready (sample rate is 0). The selected input device is still waking up or unavailable."
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

            engine.prepare()
            try engine.start()
            isRecording = true
            return url
        } catch {
            cleanup(deleteRecording: true)
            throw error
        }
    }

    func stop() -> URL? {
        let url = recordingURL
        cleanup(deleteRecording: false)
        recordingURL = nil
        return url
    }

    func reset(deleteRecording: Bool = true) {
        cleanup(deleteRecording: deleteRecording)
        engine = AVAudioEngine()
    }

    private func handleConfigChange() {
        cleanup(deleteRecording: true)
        engine = AVAudioEngine()
        onInterruption?()
    }

    private func cleanup(deleteRecording: Bool) {
        if let obs = configObserver {
            NotificationCenter.default.removeObserver(obs)
            configObserver = nil
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil
        isRecording = false
        if deleteRecording, let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }
    }
}
