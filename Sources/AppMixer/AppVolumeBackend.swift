import AppKit
import Foundation

struct AppVolumeTarget: Equatable {
    let bundleIdentifier: String
    let processIdentifier: pid_t
    let localizedName: String
}

enum AppVolumeCapability: Equatable {
    case universalTap
    case unavailable(String)

    var label: String {
        switch self {
        case .universalTap:
            "System tap"
        case .unavailable:
            "Unavailable"
        }
    }
}

protocol AppVolumeBackend {
    func capability(for target: AppVolumeTarget) -> AppVolumeCapability
    func readVolume(for target: AppVolumeTarget) -> Float?
    func setVolume(_ value: Float, for target: AppVolumeTarget) -> Result<Void, AppVolumeError>
}

struct AppVolumeError: Error, Equatable {
    let message: String
}
