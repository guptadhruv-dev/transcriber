import AppKit
import CoreAudio

final class MediaController {

    private var didPause = false
    private let playPauseKey = 16

    func pauseIfPlaying() {
        guard !didPause, isSystemAudioPlaying() else { return }
        sendPlayPauseKey()
        didPause = true
    }

    func resumeIfPaused() {
        guard didPause else { return }
        didPause = false
        sendPlayPauseKey()
    }

    private func isSystemAudioPlaying() -> Bool {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let deviceStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard deviceStatus == noErr, deviceID != 0 else { return false }

        var isRunning = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere

        let runningStatus = AudioObjectGetPropertyData(
            deviceID, &address, 0, nil, &size, &isRunning
        )
        guard runningStatus == noErr else { return false }
        return isRunning != 0
    }

    private func sendPlayPauseKey() {
        postAuxKey(down: true)
        postAuxKey(down: false)
    }

    private func postAuxKey(down: Bool) {
        let modifier = down ? 0xA00 : 0xB00
        let data1 = (playPauseKey << 16) | modifier
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifier))
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
