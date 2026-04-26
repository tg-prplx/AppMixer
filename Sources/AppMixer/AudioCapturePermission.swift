import Foundation

final class AudioCapturePermission: @unchecked Sendable {
    enum Status: String {
        case unknown
        case denied
        case authorized
    }

    static let shared = AudioCapturePermission()

    private typealias PreflightFunction = @convention(c) (CFString, CFDictionary?) -> Int32
    private typealias RequestFunction = @convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void

    private let service = "kTCCServiceAudioCapture" as CFString

    private lazy var frameworkHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)
    }()

    private lazy var preflight: PreflightFunction? = {
        guard let frameworkHandle, let symbol = dlsym(frameworkHandle, "TCCAccessPreflight") else {
            return nil
        }
        return unsafeBitCast(symbol, to: PreflightFunction.self)
    }()

    private lazy var requestAccess: RequestFunction? = {
        guard let frameworkHandle, let symbol = dlsym(frameworkHandle, "TCCAccessRequest") else {
            return nil
        }
        return unsafeBitCast(symbol, to: RequestFunction.self)
    }()

    private init() {}

    func currentStatus() -> Status {
        guard let preflight else { return .unknown }

        switch preflight(service, nil) {
        case 0:
            return .authorized
        case 1:
            return .denied
        default:
            return .unknown
        }
    }

    func request(completion: @escaping (Status) -> Void) {
        guard let requestAccess else {
            completion(currentStatus())
            return
        }

        requestAccess(service, nil) { [weak self] granted in
            if granted {
                completion(.authorized)
            } else {
                completion(self?.currentStatus() ?? .denied)
            }
        }
    }
}
