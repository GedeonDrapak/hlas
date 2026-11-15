// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hlas",
    platforms: [.macOS(.v15)],
    dependencies: [
        // Same pin as project.yml: the thinking orb in the status pill.
        .package(url: "https://github.com/Jakubantalik/Libraries.dev", revision: "387b049ca8fe97b5d72999b5bf61a19ab1ccff81")
    ],
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
            dependencies: ["CWhisper", "HlasCore", .product(name: "ThinkingOrbsKit", package: "Libraries.dev")],
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
