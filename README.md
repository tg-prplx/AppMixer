# AppMixer

Experimental native macOS menu bar audio mixer inspired by EarTrumpet.

AppMixer explores per-application volume control on modern macOS using Apple's Core Audio process tap APIs. It is intentionally small: a SwiftUI menu bar popover, live system output controls, active audio-process discovery, and a CoreAudio tap backend.

> Status: experimental prototype. Useful as a learning/reference project, not a polished daily-driver audio utility yet.

## Features

- Menu bar popover mixer.
- Default output volume and mute control.
- Active audio-process list from Core Audio process objects.
- Per-process volume through `AudioHardwareCreateProcessTap`.
- System Audio Recording permission gate.
- macOS 26 Liquid Glass background through `NSGlassEffectView`.
- Fallback blur background through `NSVisualEffectView` on older macOS versions.
- Swift Package Manager project with a simple `.app` packaging script.

## Requirements

- macOS 14.2 or newer for Core Audio process taps.
- Swift 6 / Xcode or Command Line Tools.
- System Audio Recording permission for per-app capture.

## Build

```sh
make build
```

## Package as a Menu Bar App

```sh
make package
open dist/AppMixer.app
```

Use the packaged `.app` for audio testing. Running through `swift run` can attach macOS privacy permissions to Terminal or SwiftPM instead of AppMixer, which makes process taps behave incorrectly.

## Development Run

```sh
make run
```

This is fine for UI iteration, but not recommended for validating audio capture permissions.

## Permissions

The first time AppMixer starts a process tap, macOS needs System Audio Recording access.

If the prompt does not appear:

```sh
tccutil reset AudioCapture dev.local.AppMixer
```

If that service name is not accepted on your macOS build:

```sh
tccutil reset All dev.local.AppMixer
```

Then launch the packaged app again:

```sh
open dist/AppMixer.app
```

## How It Works

macOS does not expose a Windows-style per-app volume session API. AppMixer uses the newer Core Audio process tap route:

1. Discover active audio-producing processes through `kAudioHardwarePropertyProcessObjectList`.
2. Create a private `CATapDescription` for the selected process.
3. Start an aggregate device containing the tap.
4. Read tap audio in an IOProc.
5. Apply per-process gain.
6. Write the adjusted audio back through the aggregate output path.

## Known Issues

- Browser audio often appears as helper processes, such as WebKit or Chromium helpers, not just "Safari" or "Chrome".
- Permission behavior is fragile when launched from Terminal or `swift run`.
- Energy use increases for every active tap session.
- The audio backend still needs more real-world testing across devices, sample rates, and multi-channel outputs.
- This is not notarized or signed for distribution.

## Product Notes

For a production-grade mixer, the backend should be split into a dedicated audio engine/helper, with cleaner lifecycle management, debounce-based tap shutdown, live meters, and app/helper grouping.

If you just need a stable end-user app today, look at mature projects such as Background Music, FineTune, VolumeHub, SoundSource, or eqMac instead of relying on this prototype.

## License

No license has been chosen yet. Treat the code as private/prototype code until a license is added.
