import AppKit
import SwiftUI

struct MixerView: View {
    @ObservedObject var model: MixerModel

    var body: some View {
        ZStack {
            MixerBackdropView()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Divider()

                masterVolume
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                Divider()

                search
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                permissionBanner

                appList

                Divider()

                footer
            }
        }
        .frame(width: 360, height: 540)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("AppMixer")
                    .font(.system(size: 16, weight: .semibold))
                Text("Quick audio mixer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh applications")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit")
        }
        .padding(16)
    }

    private var masterVolume: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("System Output", systemImage: model.outputMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(Int(model.outputVolume * 100))%")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }

            HStack(spacing: 10) {
                Button {
                    model.setOutputMuted(!model.outputMuted)
                } label: {
                    Image(systemName: model.outputMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 18)
                }
                .buttonStyle(.borderless)
                .help(model.outputMuted ? "Unmute" : "Mute")

                Slider(
                    value: Binding(
                        get: { Double(model.outputVolume) },
                        set: { model.setOutputVolume(Float($0)) }
                    ),
                    in: 0...1
                )
            }
        }
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter apps", text: $model.searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var permissionBanner: some View {
        if model.audioCaptureStatus != .authorized {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    model.requestAudioCapturePermission()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: model.isRequestingAudioCapturePermission ? "hourglass" : "checkmark.shield")
                            .foregroundStyle(.yellow)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("System audio capture required")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(model.audioCaptureStatus == .denied ? "Grant access in Privacy & Security." : "Click to request access.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(model.isRequestingAudioCapturePermission ? "..." : "Allow")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.isRequestingAudioCapturePermission)
                .help("Request audio capture permission")

                Button {
                    model.openAudioCapturePrivacySettings()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape")
                        Text("Open Privacy & Security")
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                    }
                    .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Open system privacy settings")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()
        }
    }

    private var appList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.filteredApps) { item in
                    AppVolumeRow(item: item) { newValue in
                        model.setAppVolume(item, value: newValue)
                    }
                    Divider()
                        .padding(.leading, 58)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(model.statusMessage)
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct AppVolumeRow: View {
    let item: AppVolumeItem
    let onChange: (Float) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AppIcon(image: item.icon)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        capabilityBadge
                    }

                    Text(item.bundleIdentifier)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("PID \(item.processIdentifier)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(Int(item.volume * 100))%")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }

            HStack(spacing: 10) {
                Image(systemName: item.isControllable ? "speaker.wave.1.fill" : "lock.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                Slider(
                    value: Binding(
                        get: { Double(item.volume) },
                        set: { onChange(Float($0)) }
                    ),
                    in: 0...1
                )
                .disabled(!item.isControllable)
            }

            if let lastError = item.lastError {
                Text(lastError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if !item.isControllable {
                if case .unavailable(let reason) = item.capability {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } else if item.volume < 0.999 {
                Text("Routing through AppMixer tap")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(item.isControllable ? 1 : 0.72)
    }

    private var capabilityBadge: some View {
        Text(item.capability.label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(item.isControllable ? .green : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
    }
}

private struct AppIcon: View {
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 32, height: 32)
    }
}
