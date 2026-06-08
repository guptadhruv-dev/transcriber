import AVFoundation

@Observable
final class AudioRecorder {

    var isRecording = false
    var onInterruption: (() -> Void)?

    private var engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var configObserver: NSObjectProtocol?
    private var converter: AVAudioConverter?
    private var reconfigureWork: DispatchWorkItem?

    private let canonicalFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!
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
            audioFile = try AVAudioFile(forWriting: url, settings: canonicalFormat.settings)
            addConfigObserver()
            try installTapAndStartEngine()
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
    }

    private func addConfigObserver() {
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigChange()
        }
    }

    private func removeConfigObserver() {
        if let obs = configObserver {
            NotificationCenter.default.removeObserver(obs)
            configObserver = nil
        }
    }

    private func installTapAndStartEngine() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(domain: "AudioRecorder", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Audio input not ready (sample rate is 0). The selected input device is still waking up or unavailable."
            ])
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: canonicalFormat) else {
            throw NSError(domain: "AudioRecorder", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "Could not create an audio converter for the selected input device."
            ])
        }
        self.converter = converter

        var startError: Error?
        let exception = ObjCExceptionCatcher.catchException {
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
                self?.append(buffer)
            }
            engine.prepare()
            do {
                try engine.start()
            } catch {
                startError = error
            }
        }

        if let exception { throw exception }
        if let startError { throw startError }
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let audioFile else { return }

        let ratio = canonicalFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: canonicalFormat, frameCapacity: capacity) else { return }

        var fed = false
        converter.convert(to: output, error: nil) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }

        if output.frameLength > 0 {
            try? audioFile.write(from: output)
        }
    }

    private func handleConfigChange() {
        guard isRecording else { return }
        reconfigureWork?.cancel()
        engine.stop()
        scheduleReconfigure(attempt: 1, maxAttempts: 12, delayMs: 0)
    }

    private func scheduleReconfigure(attempt: Int, maxAttempts: Int, delayMs: Int) {
        let work = DispatchWorkItem { [weak self] in
            self?.reconfigure(attempt: attempt, maxAttempts: maxAttempts)
        }
        reconfigureWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs), execute: work)
    }

    private func reconfigure(attempt: Int, maxAttempts: Int) {
        guard isRecording else { return }

        removeConfigObserver()
        engine = AVAudioEngine()
        addConfigObserver()

        do {
            try installTapAndStartEngine()
        } catch {
            guard attempt < maxAttempts else {
                cleanup(deleteRecording: true)
                onInterruption?()
                return
            }
            scheduleReconfigure(attempt: attempt + 1, maxAttempts: maxAttempts, delayMs: min(1000, attempt * 150))
        }
    }

    private func cleanup(deleteRecording: Bool) {
        reconfigureWork?.cancel()
        reconfigureWork = nil
        removeConfigObserver()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil
        converter = nil
        isRecording = false
        if deleteRecording, let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }
    }
}
