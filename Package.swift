// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hlas",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "CWhisper",
            path: "Sources/CWhisper",
            cSettings: [
                .unsafeFlags(["-I", "Vendor/include"])
            ]
        ),
        .executableTarget(
            name: "Hlas",
            dependencies: ["CWhisper"],
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
                .linkedFramework("AVFoundation")
            ]
        )
    ]
)
