import AppKit
import Foundation

struct AppVolumeItem: Identifiable, Equatable {
    let id: String
    let name: String
    let bundleIdentifier: String
    let processIdentifier: pid_t
    let icon: NSImage?
    let capability: AppVolumeCapability
    var volume: Float
    var lastError: String?

    var isControllable: Bool {
        if case .universalTap = capability {
            return true
        }
        return false
    }
}

@MainActor
final class MixerModel: ObservableObject {
    @Published var outputVolume: Float = 0
    @Published var outputMuted: Bool = false
    @Published var apps: [AppVolumeItem] = []
    @Published var searchText: String = ""
    @Published var statusMessage: String = "Ready"
    @Published var audioCaptureStatus: AudioCapturePermission.Status = .unknown
    @Published var isRequestingAudioCapturePermission: Bool = false

    private let systemAudio = SystemAudioController()
    private let appBackend: AppVolumeBackend = UniversalAppVolumeBackend()
    private let defaults = UserDefaults.standard
    private var monitorTimer: Timer?
    private var appRefreshTicks = 0

    var filteredApps: [AppVolumeItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return apps }
        return apps.filter { app in
            app.name.localizedCaseInsensitiveContains(query)
            || app.bundleIdentifier.localizedCaseInsensitiveContains(query)
            || "\(app.processIdentifier)".contains(query)
        }
    }

    func refresh() {
        refreshOutputStatus()
        audioCaptureStatus = AudioCapturePermission.shared.currentStatus()
        apps = loadRunningApps()
        statusMessage = "Updated \(Date.now.formatted(date: .omitted, time: .shortened))"
    }

    func requestAudioCapturePermission() {
        isRequestingAudioCapturePermission = true
        statusMessage = "Requesting audio capture permission..."

        AudioCapturePermission.shared.request { [weak self] status in
            Task { @MainActor in
                self?.isRequestingAudioCapturePermission = false
                self?.audioCaptureStatus = status
                self?.statusMessage = status == .authorized
                    ? "Audio capture permission granted"
                    : "Audio capture permission is required"
                self?.refresh()
            }
        }
    }

    func openAudioCapturePrivacySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy"
        ]

        for rawURL in urls {
            guard let url = URL(string: rawURL), NSWorkspace.shared.open(url) else { continue }
            statusMessage = "Opened Privacy & Security"
            return
        }

        statusMessage = "Open Privacy & Security manually"
    }

    func startMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.monitorTick()
            }
        }
        RunLoop.main.add(monitorTimer!, forMode: .common)
        refresh()
    }

    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        appRefreshTicks = 0
    }

    func setOutputVolume(_ value: Float) {
        systemAudio.setOutputVolume(value)
        refreshOutputStatus()
    }

    func setOutputMuted(_ muted: Bool) {
        systemAudio.setOutputMuted(muted)
        refreshOutputStatus()
    }

    func setAppVolume(_ item: AppVolumeItem, value: Float) {
        guard let index = apps.firstIndex(where: { $0.id == item.id }) else { return }

        apps[index].volume = value
        defaults.set(value, forKey: defaultsKey(for: item.id))

        switch appBackend.setVolume(value, for: target(for: item)) {
        case .success:
            apps[index].lastError = nil
            statusMessage = "Set \(item.name) to \(Int(value * 100))%"
        case .failure(let error):
            apps[index].lastError = error.message
            statusMessage = error.message
        }
    }

    private func monitorTick() {
        refreshOutputStatus()
        audioCaptureStatus = AudioCapturePermission.shared.currentStatus()

        appRefreshTicks += 1
        if appRefreshTicks >= 8 {
            appRefreshTicks = 0
            apps = loadRunningApps(preservingErrorsFrom: apps)
        }
    }

    private func refreshOutputStatus() {
        outputVolume = systemAudio.outputVolume
        outputMuted = systemAudio.isOutputMuted
    }

    private func loadRunningApps(preservingErrorsFrom currentItems: [AppVolumeItem] = []) -> [AppVolumeItem] {
        let ownPID = NSRunningApplication.current.processIdentifier
        let errorsByID = Dictionary(uniqueKeysWithValues: currentItems.map { ($0.id, $0.lastError) })

        return CoreAudioUtilities.outputAudioProcesses()
            .filter { $0.pid != ownPID }
            .map { process in
                let app = NSRunningApplication(processIdentifier: process.pid)
                let bundleIdentifier = process.bundleIdentifier ?? app?.bundleIdentifier ?? "pid.\(process.pid)"
                let itemID = "pid:\(process.pid)"
                let name = displayName(for: app, process: process, bundleIdentifier: bundleIdentifier)
                let target = AppVolumeTarget(
                    bundleIdentifier: bundleIdentifier,
                    processIdentifier: process.pid,
                    localizedName: name
                )
                let capability = appBackend.capability(for: target)
                let savedVolume = defaults.object(forKey: defaultsKey(for: itemID)) as? Float
                let liveVolume = appBackend.readVolume(for: target)
                let volume = liveVolume ?? savedVolume ?? 1.0
                var lastError = errorsByID[itemID] ?? nil

                if isControllable(capability), volume < 0.999 {
                    switch appBackend.setVolume(volume, for: target) {
                    case .success:
                        lastError = nil
                    case .failure(let error):
                        lastError = error.message
                    }
                }

                return AppVolumeItem(
                    id: itemID,
                    name: name,
                    bundleIdentifier: bundleIdentifier,
                    processIdentifier: process.pid,
                    icon: app?.icon,
                    capability: capability,
                    volume: volume,
                    lastError: lastError
                )
            }
            .sorted { lhs, rhs in
                if lhs.isControllable != rhs.isControllable {
                    return lhs.isControllable && !rhs.isControllable
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func target(for item: AppVolumeItem) -> AppVolumeTarget {
        AppVolumeTarget(
            bundleIdentifier: item.bundleIdentifier,
            processIdentifier: item.processIdentifier,
            localizedName: item.name
        )
    }

    private func displayName(
        for app: NSRunningApplication?,
        process: CoreAudioUtilities.AudioProcessInfo,
        bundleIdentifier: String
    ) -> String {
        if let name = app?.localizedName, !name.isEmpty {
            return name
        }

        if let bundleName = Bundle(identifier: bundleIdentifier)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
            return bundleName
        }

        return bundleIdentifier
            .split(separator: ".")
            .last
            .map(String.init) ?? "PID \(process.pid)"
    }

    private func defaultsKey(for id: String) -> String {
        "app-volume.\(id)"
    }

    private func isControllable(_ capability: AppVolumeCapability) -> Bool {
        if case .universalTap = capability {
            return true
        }
        return false
    }
}
