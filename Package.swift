// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AppMixer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AppMixer", targets: ["AppMixer"])
    ],
    targets: [
        .executableTarget(
            name: "AppMixer",
            path: "Sources/AppMixer"
        )
    ]
)
