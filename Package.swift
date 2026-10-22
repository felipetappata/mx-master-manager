// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mx-master-manager",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MXMasterManager", targets: ["MXMasterManager"]),
    ],
    targets: [
        .target(name: "MXMasterCore"),
        .executableTarget(
            name: "MXMasterManager",
            dependencies: ["MXMasterCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "MXMasterCoreTests", dependencies: ["MXMasterCore"]),
        .testTarget(name: "MXMasterManagerTests", dependencies: ["MXMasterManager"]),
    ],
    swiftLanguageVersions: [.v5]
)
