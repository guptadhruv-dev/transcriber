import SwiftUI
import AVFoundation
import FluidAudio
import Accelerate

enum OllamaStatus {
    case offline, idle, loaded
}

@Observable
final class TranscriberModel {

    var isRecording = false
    var statusMessage = "Ready"
    var lastTranscript = ""
    var isModelReady = false
    var ollamaStatus: OllamaStatus = .offline
    var launchAtLogin = LaunchAtLogin()
    var lastError: String? = nil

    func clearError() { lastError = nil }

    private func recordError(_ detail: String) {
        lastError = detail
        print("[Transcriber] \(detail)")
    }

    var refinementLevel: RefinementLevel = {
        let raw = UserDefaults.standard.string(forKey: "refinementLevel") ?? "quick"
        return RefinementLevel(rawValue: raw) ?? .quick
    }() {
        didSet { UserDefaults.standard.set(refinementLevel.rawValue, forKey: "refinementLevel") }
    }

    let hotkey = HotkeyService()
    private var recorder = AudioRecorder()
    private let asr = AsrManager()
    private let refiner = TextRefiner()
    private var vad: VadManager?
    private var currentJobID = UUID()
    private var isStartingRecording = false
    private var startAttemptID = UUID()

    init() {
        wireInterruption()
        activate()
        observeSleepWake()
        startOllamaPolling()
    }

    func activate() {
        hotkey.start(model: self)
        statusMessage = "Loading models…"
        Task {
            do {
                async let vadTask = VadManager(config: VadConfig(defaultThreshold: 0.65))
                async let asrModelsTask = AsrModels.downloadAndLoad(version: .v2)

                let loadedVad = try await vadTask
                let asrModels = try await asrModelsTask
                try await asr.loadModels(asrModels)

                await MainActor.run {
                    self.vad = loadedVad
                    isModelReady = true
                    statusMessage = "Ready"
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Model load failed"
                    recordError("Model load failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func toggleRecording() {
        guard isModelReady else { return }
        guard !isStartingRecording else { return }
        isRecording ? stopRecording() : startRecording()
    }

    // MARK: - Recorder Lifecycle

    private func wireInterruption() {
        recorder.onInterruption = { [weak self] in
            guard let self else { return }
            let wasActive = isRecording || isStartingRecording
            startAttemptID = UUID()
            isStartingRecording = false
            isRecording = false
            statusMessage = "Ready"
            resetRecorder()
            hotkey.refresh()
            if wasActive {
                recordError("Recording stopped because the audio input changed, disconnected, or went to sleep. Wake the mic and press the shortcut again.")
            }
        }
    }

    private func resetRecorder() {
        recorder.reset(deleteRecording: true)
        recorder = AudioRecorder()
        wireInterruption()
    }

    // MARK: - Sleep / Wake

    private func observeSleepWake() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, isRecording || isStartingRecording else { return }
            startAttemptID = UUID()
            if let url = recorder.stop() {
                try? FileManager.default.removeItem(at: url)
            }
            isStartingRecording = false
            isRecording = false
            statusMessage = "Ready"
            resetRecorder()
        }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            startAttemptID = UUID()
            isStartingRecording = false
            isRecording = false
            if isModelReady {
                statusMessage = "Ready"
            }
            resetRecorder()
            hotkey.recoverAfterWake()
        }
    }

    // MARK: - Ollama Status Polling

    private func startOllamaPolling() {
        Task {
            while true {
                await checkOllamaStatus()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func checkOllamaStatus() async {
        guard let url = URL(string: "http://localhost:11434/api/ps") else { return }
        var req = URLRequest(url: url, timeoutInterval: 3)
        req.httpMethod = "GET"
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                await MainActor.run { ollamaStatus = .offline }
                return
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let models = json?["models"] as? [[String: Any]] ?? []
            let loaded = models.contains { ($0["name"] as? String)?.hasPrefix("qwen3:8b") == true }
            await MainActor.run { ollamaStatus = loaded ? .loaded : .idle }
        } catch {
            await MainActor.run { ollamaStatus = .offline }
        }
    }

    // MARK: - Recording

    private func startRecording() {
        guard !isStartingRecording, !isRecording else { return }
        let attemptID = UUID()
        startAttemptID = attemptID
        isStartingRecording = true
        statusMessage = "Starting mic…"

        Task {
            do {
                try await requestMicrophonePermission()
            } catch {
                await MainActor.run {
                    guard startAttemptID == attemptID else { return }
                    isStartingRecording = false
                    statusMessage = "Mic access denied"
                    recordError("Microphone access denied — grant permission in System Settings > Privacy > Microphone.")
                }
                return
            }
            await startEngine(attemptID: attemptID, attempt: 1, maxAttempts: 6)
        }
    }

    private func startEngine(attemptID: UUID, attempt: Int, maxAttempts: Int) async {
        let shouldContinue = await MainActor.run {
            startAttemptID == attemptID && isStartingRecording && !isRecording
        }
        guard shouldContinue else { return }

        do {
            _ = try await MainActor.run { try recorder.start() }
            await MainActor.run {
                guard startAttemptID == attemptID, isStartingRecording else {
                    _ = recorder.stop()
                    return
                }
                isStartingRecording = false
                isRecording = true
                statusMessage = "Listening…"
            }
        } catch {
            let canRetry = await MainActor.run { () -> Bool in
                guard startAttemptID == attemptID, isStartingRecording else { return false }
                resetRecorder()
                return attempt < maxAttempts
            }

            guard canRetry else {
                await MainActor.run {
                    guard startAttemptID == attemptID else { return }
                    isStartingRecording = false
                    isRecording = false
                    statusMessage = "Mic error"
                    recordError("Audio engine failed to start after \(maxAttempts) attempts: \(error.localizedDescription)")
                }
                return
            }

            let delay = min(1_500, attempt * 300)
            try? await Task.sleep(for: .milliseconds(delay))
            await startEngine(attemptID: attemptID, attempt: attempt + 1, maxAttempts: maxAttempts)
        }
    }

    private func stopRecording() {
        startAttemptID = UUID()
        guard let url = recorder.stop() else {
            isStartingRecording = false
            isRecording = false
            statusMessage = "Ready"
            recordError("Recording produced no audio file — audio device may have changed during recording.")
            return
        }
        isStartingRecording = false
        isRecording = false
        statusMessage = "Transcribing…"
        let jobID = UUID()
        currentJobID = jobID
        Task { await transcribe(url: url, jobID: jobID) }
    }

    // MARK: - Transcription

    private func transcribe(url: URL, jobID: UUID) async {
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let samples = try AudioConverter().resampleAudioFile(url)
            var speechSamples = await applyVAD(to: samples)

            guard !speechSamples.isEmpty else {
                await MainActor.run {
                    guard currentJobID == jobID, !isRecording else { return }
                    statusMessage = "No speech detected"
                }
                return
            }

            peakNormalize(&speechSamples, target: 0.90, maxGain: 6.0)

            var decoderState = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
            let result = try await asr.transcribe(speechSamples, decoderState: &decoderState)

            let level = await MainActor.run { refinementLevel }
            if level != .off {
                await MainActor.run {
                    guard currentJobID == jobID, !isRecording else { return }
                    statusMessage = "Refining…"
                }
            }
            let finalText = await refiner.refine(result.text, level: level)

            let didCommit = await MainActor.run { () -> Bool in
                guard currentJobID == jobID, !isRecording else { return false }
                lastTranscript = finalText
                statusMessage = "Ready"
                return true
            }
            if didCommit { await pasteToActiveField(finalText) }
        } catch {
            await MainActor.run {
                guard currentJobID == jobID, !isRecording else { return }
                statusMessage = "Error"
                recordError("Transcription failed: \(error.localizedDescription)")
            }
        }
    }

    private func applyVAD(to samples: [Float]) async -> [Float] {
        guard let vad else { return samples }

        var segConfig = VadSegmentationConfig.default
        segConfig.minSpeechDuration = 0.10
        segConfig.minSilenceDuration = 0.6
        segConfig.speechPadding = 0.25

        do {
            let segments = try await vad.segmentSpeech(samples, config: segConfig)
            guard !segments.isEmpty else { return [] }

            let sr = 16000.0
            let spacer = [Float](repeating: 0, count: Int(0.12 * sr))

            var out: [Float] = []
            out.reserveCapacity(samples.count)
            for (i, segment) in segments.enumerated() {
                let start = max(0, Int(segment.startTime * sr))
                let end = min(samples.count, Int(segment.endTime * sr))
                guard start < end else { continue }
                if i > 0 { out.append(contentsOf: spacer) }
                out.append(contentsOf: samples[start..<end])
            }
            return out
        } catch {
            return samples
        }
    }

    private func peakNormalize(_ samples: inout [Float], target: Float = 0.90, maxGain: Float = 6.0) {
        guard !samples.isEmpty else { return }
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
        guard peak > 0.01 else { return }
        var scale = min(target / peak, maxGain)
        vDSP_vsmul(samples, 1, &scale, &samples, 1, vDSP_Length(samples.count))
    }

    private func pasteToActiveField(_ text: String) async {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        let src = CGEventSource(stateID: .hidSystemState)

        let cmdV = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        cmdV?.flags = .maskCommand
        cmdV?.post(tap: .cgAnnotatedSessionEventTap)

        let cmdVUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        cmdVUp?.flags = .maskCommand
        cmdVUp?.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func requestMicrophonePermission() async throws {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        if !granted { throw TranscriberError.microphoneDenied }
    }
}

enum TranscriberError: Error {
    case microphoneDenied
}
