// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hlas",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "HlasCore",
            path: "Sources/HlasCore"
        ),
        .target(
            name: "CWhisper",
            path: "Sources/CWhisper",
            cSettings: [
                .unsafeFlags(["-I", "Vendor/include"])
            ]
        ),
        .executableTarget(
            name: "Hlas",
            dependencies: ["CWhisper", "HlasCore"],
            path: "Sources/Hlas",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .unsafeFlags(["-LVendor/lib"]),
                .linkedLibrary("c++"),
                .linkedFramework("Metal"),
                .linkedFramework("Foundation"),
                .linkedFramework("Accelerate"),
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Security"),
                .linkedFramework("CoreText")
            ]
        ),
        .testTarget(
            name: "HlasCoreTests",
            dependencies: ["HlasCore"],
            path: "Tests/HlasCoreTests"
        ),
        .testTarget(name: "HlasIntegrationTests", dependencies: ["Hlas", "HlasCore"],
                    path: "Tests/HlasIntegrationTests", swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
