import AudioToolbox
import CoreAudio
import Foundation

final class SystemAudioController {
    var outputVolume: Float {
        getScalarProperty(selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume) ?? 0
    }

    var isOutputMuted: Bool {
        (getUInt32Property(selector: kAudioDevicePropertyMute) ?? 0) != 0
    }

    func setOutputVolume(_ value: Float) {
        setScalarProperty(
            selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            value: max(0, min(1, value))
        )
    }

    func setOutputMuted(_ muted: Bool) {
        var value: UInt32 = muted ? 1 : 0
        setUInt32Property(selector: kAudioDevicePropertyMute, value: &value)
    }

    private var defaultOutputDeviceID: AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        return status == noErr ? deviceID : nil
    }

    private func getScalarProperty(selector: AudioObjectPropertySelector) -> Float? {
        var value = Float32()
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = outputAddress(selector: selector)

        guard let deviceID = defaultOutputDeviceID else { return nil }
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private func getUInt32Property(selector: AudioObjectPropertySelector) -> UInt32? {
        var value = UInt32()
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = outputAddress(selector: selector)

        guard let deviceID = defaultOutputDeviceID else { return nil }
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private func setScalarProperty(selector: AudioObjectPropertySelector, value: Float) {
        var scalar = Float32(value)
        setFloat32Property(selector: selector, value: &scalar)
    }

    private func setFloat32Property(selector: AudioObjectPropertySelector, value: inout Float32) {
        var address = outputAddress(selector: selector)
        guard let deviceID = defaultOutputDeviceID else { return }

        AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float32>.size),
            &value
        )
    }

    private func setUInt32Property(selector: AudioObjectPropertySelector, value: inout UInt32) {
        var address = outputAddress(selector: selector)
        guard let deviceID = defaultOutputDeviceID else { return }

        AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &value
        )
    }

    private func outputAddress(selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
