// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ShutTheDuckOff",
    platforms: [.macOS("14.2")],
    targets: [
        .executableTarget(
            name: "ShutTheDuckOff",
            path: "Sources/ShutTheDuckOff",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
            ]
        )
    ]
)
