import CoreAudio
import Foundation

enum CoreAudioUtilities {
    struct AudioProcessInfo: Equatable {
        let objectID: AudioObjectID
        let pid: pid_t
        let bundleIdentifier: String?
        let isRunningOutput: Bool
    }

    static let systemObjectID = AudioObjectID(kAudioObjectSystemObject)

    static func defaultOutputDeviceID() -> AudioDeviceID? {
        getAudioObjectID(
            objectID: systemObjectID,
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            scope: kAudioObjectPropertyScopeGlobal
        )
    }

    static func defaultOutputDeviceUID() -> String? {
        guard let deviceID = defaultOutputDeviceID() else { return nil }
        return getStringProperty(
            objectID: deviceID,
            selector: kAudioDevicePropertyDeviceUID,
            scope: kAudioObjectPropertyScopeGlobal
        )
    }

    static func processObjectID(for pid: pid_t) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var processID = pid
        var processObjectID = AudioObjectID(kAudioObjectUnknown)
        var outputSize = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            systemObjectID,
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &processID,
            &outputSize,
            &processObjectID
        )

        guard status == noErr, processObjectID != kAudioObjectUnknown else { return nil }
        return processObjectID
    }

    static func outputAudioProcesses() -> [AudioProcessInfo] {
        audioProcessObjectIDs().compactMap { objectID in
            guard let pid = getPIDProperty(
                objectID: objectID,
                selector: kAudioProcessPropertyPID,
                scope: kAudioObjectPropertyScopeGlobal
            ) else {
                return nil
            }

            let isRunningOutput = (getUInt32Property(
                objectID: objectID,
                selector: kAudioProcessPropertyIsRunningOutput,
                scope: kAudioObjectPropertyScopeGlobal
            ) ?? 0) != 0

            return AudioProcessInfo(
                objectID: objectID,
                pid: pid,
                bundleIdentifier: getStringProperty(
                    objectID: objectID,
                    selector: kAudioProcessPropertyBundleID,
                    scope: kAudioObjectPropertyScopeGlobal
                ),
                isRunningOutput: isRunningOutput
            )
        }
        .filter(\.isRunningOutput)
    }

    private static func audioProcessObjectIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(systemObjectID, &address, 0, nil, &size)
        guard status == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var objectIDs = Array(repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        status = objectIDs.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return kAudioHardwareBadObjectError }
            return AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &size, baseAddress)
        }

        guard status == noErr else { return [] }
        return objectIDs.filter { $0 != kAudioObjectUnknown }
    }

    static func getStringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        let value = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        value.initialize(to: nil)
        defer {
            value.deinitialize(count: 1)
            value.deallocate()
        }
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, value)
        return status == noErr ? value.pointee as String? : nil
    }

    static func getAudioObjectID(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        guard status == noErr, value != kAudioObjectUnknown else { return nil }
        return value
    }

    static func getUInt32Property(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = UInt32()
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    static func getPIDProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = pid_t()
        var size = UInt32(MemoryLayout<pid_t>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    static func describe(_ status: OSStatus) -> String {
        guard status != noErr else { return "noErr" }
        let bigEndian = UInt32(bitPattern: status).bigEndian
        let bytes = [
            UInt8((bigEndian >> 24) & 0xff),
            UInt8((bigEndian >> 16) & 0xff),
            UInt8((bigEndian >> 8) & 0xff),
            UInt8(bigEndian & 0xff)
        ]
        if bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) {
            return "'\(String(bytes: bytes, encoding: .macOSRoman) ?? "????")' (\(status))"
        }
        return "\(status)"
    }
}
