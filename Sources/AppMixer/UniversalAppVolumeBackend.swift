import AppKit
import CoreAudio
import Foundation

final class UniversalAppVolumeBackend: AppVolumeBackend {
    private var sessions: [String: ProcessTapSession] = [:]
    private var gains: [String: Float] = [:]

    func capability(for target: AppVolumeTarget) -> AppVolumeCapability {
        guard target.processIdentifier > 0 else {
            return .unavailable("App has no process identifier.")
        }

        guard #available(macOS 14.2, *) else {
            return .unavailable("Process taps require macOS 14.2 or newer.")
        }

        guard CoreAudioUtilities.defaultOutputDeviceUID() != nil else {
            return .unavailable("No default output device.")
        }

        switch AudioCapturePermission.shared.currentStatus() {
        case .authorized:
            break
        case .denied:
            return .unavailable("Grant System Audio Recording permission in Privacy & Security.")
        case .unknown:
            return .unavailable("Allow System Audio Recording before lowering app volume.")
        }

        if CoreAudioUtilities.processObjectID(for: target.processIdentifier) == nil {
            return .unavailable("Start audio in this app first, then refresh.")
        }

        return .universalTap
    }

    func readVolume(for target: AppVolumeTarget) -> Float? {
        gains[sessionKey(for: target)]
    }

    func setVolume(_ value: Float, for target: AppVolumeTarget) -> Result<Void, AppVolumeError> {
        let key = sessionKey(for: target)
        let clamped = max(0, min(1, value))
        gains[key] = clamped

        guard #available(macOS 14.2, *) else {
            return .failure(AppVolumeError(message: "Process taps require macOS 14.2 or newer."))
        }

        switch AudioCapturePermission.shared.currentStatus() {
        case .authorized:
            break
        case .denied:
            return .failure(AppVolumeError(message: "System Audio Recording permission is denied. Grant it in Privacy & Security."))
        case .unknown:
            AudioCapturePermission.shared.request { _ in }
            return .failure(AppVolumeError(message: "Allow System Audio Recording, then move the slider again."))
        }

        do {
            if let session = sessions[key] {
                session.gain = clamped
                return .success(())
            }

            let session = try ProcessTapSession(target: target, gain: clamped)
            try session.start()
            sessions[key] = session
            return .success(())
        } catch let error as ProcessTapSession.SessionError {
            return .failure(AppVolumeError(message: error.message))
        } catch {
            return .failure(AppVolumeError(message: String(describing: error)))
        }
    }

    private func sessionKey(for target: AppVolumeTarget) -> String {
        "pid:\(target.processIdentifier)"
    }
}

private final class ProcessTapSession {
    struct SessionError: Error {
        let message: String
    }

    var gain: Float

    private let bundleIdentifier: String
    private let appName: String
    private let processObjectID: AudioObjectID?
    private let tapUUID = UUID()

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var tapFormat: AudioStreamBasicDescription?
    private var isStarted = false

    init(target: AppVolumeTarget, gain: Float) throws {
        guard CoreAudioUtilities.defaultOutputDeviceUID() != nil else {
            throw SessionError(message: "No default output device.")
        }

        self.bundleIdentifier = target.bundleIdentifier
        self.appName = target.localizedName
        self.processObjectID = CoreAudioUtilities.processObjectID(for: target.processIdentifier)
        self.gain = gain
    }

    deinit {
        stop()
    }

    func start() throws {
        guard !isStarted else { return }
        try createTap()
        try createAggregateDevice()
        try createIOProc()

        if let ioProcID {
            let status = AudioDeviceStart(aggregateID, ioProcID)
            guard status == noErr else {
                throw SessionError(message: "AudioDeviceStart failed: \(CoreAudioUtilities.describe(status))")
            }
        }

        isStarted = true
    }

    func stop() {
        if let ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil

        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }

        if tapID != kAudioObjectUnknown {
            if #available(macOS 14.2, *) {
                AudioHardwareDestroyProcessTap(tapID)
            }
            tapID = AudioObjectID(kAudioObjectUnknown)
        }

        isStarted = false
    }

    private func createTap() throws {
        guard #available(macOS 14.2, *) else {
            throw SessionError(message: "Process taps require macOS 14.2 or newer.")
        }

        guard let processObjectID else {
            throw SessionError(message: "Start audio in \(appName) first, then refresh.")
        }

        let description = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        description.name = "AppMixer \(appName)"
        description.uuid = tapUUID
        description.isPrivate = true
        description.muteBehavior = CATapMuteBehavior(rawValue: 2)!

        var createdTapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &createdTapID)
        guard status == noErr else {
            throw SessionError(message: "Create process tap failed: \(CoreAudioUtilities.describe(status))")
        }

        tapID = createdTapID
        tapFormat = try readTapFormat()
    }

    private func createAggregateDevice() throws {
        let aggregateUID = "dev.local.AppMixer.aggregate.\(tapUUID.uuidString)"
        let tapUID = try readTapUID()
        guard let outputDeviceUID = CoreAudioUtilities.defaultOutputDeviceUID() else {
            throw SessionError(message: "No default output device.")
        }
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AppMixer \(appName)",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [
                    kAudioSubDeviceUIDKey: outputDeviceUID
                ]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: true
                ]
            ]
        ]

        var createdAggregateID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &createdAggregateID)
        guard status == noErr else {
            throw SessionError(message: "Create aggregate device failed: \(CoreAudioUtilities.describe(status))")
        }

        aggregateID = createdAggregateID
    }

    private func createIOProc() throws {
        var createdIOProcID: AudioDeviceIOProcID?
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = AudioDeviceCreateIOProcID(aggregateID, ProcessTapSession.ioProc, context, &createdIOProcID)
        guard status == noErr, let createdIOProcID else {
            throw SessionError(message: "Create IO proc failed: \(CoreAudioUtilities.describe(status))")
        }

        ioProcID = createdIOProcID
    }

    private static let ioProc: AudioDeviceIOProc = { _, _, inputData, _, outputData, _, clientData in
        guard let clientData else { return noErr }
        let session = Unmanaged<ProcessTapSession>.fromOpaque(clientData).takeUnretainedValue()
        session.render(inputData: inputData, outputData: outputData)
        return noErr
    }

    private func render(inputData: UnsafePointer<AudioBufferList>?, outputData: UnsafeMutablePointer<AudioBufferList>) {
        clear(outputData)
        guard let inputData else { return }

        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        let outputs = UnsafeMutableAudioBufferListPointer(outputData)
        guard let firstInput = inputs.first else { return }

        let scalar = gain

        if inputs.count == 1, firstInput.mNumberChannels > 1 {
            renderInterleavedInput(inputs: inputs, outputs: outputs, gain: scalar)
        } else {
            renderPlanarInput(inputs: inputs, outputs: outputs, gain: scalar)
        }
    }

    private func readTapFormat() throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format)
        guard status == noErr else {
            throw SessionError(message: "Read tap format failed: \(CoreAudioUtilities.describe(status))")
        }
        return format
    }

    private func readTapUID() throws -> String {
        guard let tapUID = CoreAudioUtilities.getStringProperty(
            objectID: tapID,
            selector: kAudioTapPropertyUID,
            scope: kAudioObjectPropertyScopeGlobal
        ) else {
            throw SessionError(message: "Read tap UID failed.")
        }
        return tapUID
    }

    private func clear(_ outputData: UnsafeMutablePointer<AudioBufferList>) {
        let outputs = UnsafeMutableAudioBufferListPointer(outputData)
        for index in outputs.indices {
            if let pointer = outputs[index].mData {
                memset(pointer, 0, Int(outputs[index].mDataByteSize))
            }
        }
    }

    private func renderPlanarInput(
        inputs: UnsafeMutableAudioBufferListPointer,
        outputs: UnsafeMutableAudioBufferListPointer,
        gain: Float
    ) {
        for outputIndex in outputs.indices {
            guard let destinationPointer = outputs[outputIndex].mData else { continue }
            let inputIndex = min(outputIndex, inputs.count - 1)
            guard inputIndex >= 0, let sourcePointer = inputs[inputIndex].mData else { continue }

            let sampleCount = min(
                Int(inputs[inputIndex].mDataByteSize),
                Int(outputs[outputIndex].mDataByteSize)
            ) / MemoryLayout<Float32>.size
            let source = sourcePointer.assumingMemoryBound(to: Float32.self)
            let destination = destinationPointer.assumingMemoryBound(to: Float32.self)

            for sampleIndex in 0..<sampleCount {
                destination[sampleIndex] = source[sampleIndex] * gain
            }
        }
    }

    private func renderInterleavedInput(
        inputs: UnsafeMutableAudioBufferListPointer,
        outputs: UnsafeMutableAudioBufferListPointer,
        gain: Float
    ) {
        guard let firstInput = inputs.first, let sourcePointer = firstInput.mData else { return }
        let source = sourcePointer.assumingMemoryBound(to: Float32.self)
        let sourceChannels = max(1, Int(firstInput.mNumberChannels))
        let frameCount = Int(firstInput.mDataByteSize) / (MemoryLayout<Float32>.size * sourceChannels)

        if outputs.count == 1, let destinationPointer = outputs.first?.mData, (outputs.first?.mNumberChannels ?? 0) > 1 {
            let destinationChannels = max(1, Int(outputs[0].mNumberChannels))
            let destination = destinationPointer.assumingMemoryBound(to: Float32.self)
            let count = min(frameCount, Int(outputs[0].mDataByteSize) / (MemoryLayout<Float32>.size * destinationChannels))

            for frame in 0..<count {
                for channel in 0..<destinationChannels {
                    let sourceChannel = min(channel, sourceChannels - 1)
                    destination[(frame * destinationChannels) + channel] = source[(frame * sourceChannels) + sourceChannel] * gain
                }
            }
            return
        }

        for outputIndex in outputs.indices {
            guard let destinationPointer = outputs[outputIndex].mData else { continue }
            let destination = destinationPointer.assumingMemoryBound(to: Float32.self)
            let sourceChannel = min(outputIndex, sourceChannels - 1)
            let count = min(frameCount, Int(outputs[outputIndex].mDataByteSize) / MemoryLayout<Float32>.size)

            for frame in 0..<count {
                destination[frame] = source[(frame * sourceChannels) + sourceChannel] * gain
            }
        }
    }
}
