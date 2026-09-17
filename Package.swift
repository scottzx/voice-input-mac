// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "voice-input-mac",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "VoiceInputMac", targets: ["VoiceInputMac"]),
        .library(name: "VoiceInputCore", targets: ["VoiceInputCore"]),
    ],
    dependencies: [
        .package(path: "../../../mac_app/TranscribeKit"),
    ],
    targets: [
        .target(
            name: "VoiceInputCore",
            dependencies: [
                .product(name: "TranscribeKit", package: "TranscribeKit"),
            ],
            path: "Sources/VoiceInputCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .executableTarget(
            name: "VoiceInputMac",
            dependencies: ["VoiceInputCore"],
            path: "Sources/VoiceInputMac",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .testTarget(
            name: "VoiceInputMacTests",
            dependencies: ["VoiceInputCore"],
            path: "Tests/VoiceInputMacTests"
        ),
    ]
)
