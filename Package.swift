// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "voice-input-mac",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "VoiceInputMac", targets: ["VoiceInputMac"]),
        .library(name: "VoiceInputCore", targets: ["VoiceInputCore"]),
    ],
    targets: [
        .binaryTarget(
            name: "CTranscribe",
            path: "Vendor/TranscribeCpp.xcframework"
        ),
        .target(
            name: "TranscribeCpp",
            dependencies: ["CTranscribe"],
            path: "vendor/transcribe-cpp/Sources/TranscribeCpp",
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedLibrary("z"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Foundation"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
            ]
        ),
        .target(
            name: "VoiceInputCore",
            dependencies: ["TranscribeCpp"],
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
