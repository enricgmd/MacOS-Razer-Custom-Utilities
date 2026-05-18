// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "RazerCustomUtilities",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .executable(
            name: "RazerCustomUtilities",
            targets: ["RazerCustomUtilities"]
        ),
        .executable(
            name: "razer-hid-tool",
            targets: ["RazerHIDTool"]
        ),
        .library(
            name: "RazerCustomUtilitiesCore",
            targets: ["RazerCustomUtilitiesCore"]
        )
    ],
    targets: [
        .target(
            name: "RazerCustomUtilities",
            dependencies: ["RazerCustomUtilitiesCore"],
            path: "Sources/RazerCustomUtilities"
        ),
        .target(
            name: "RazerCustomUtilitiesCore",
            path: "Sources/RazerCustomUtilitiesCore",
            resources: [
                .copy("Resources/graphics")
            ]
        ),
        .target(
            name: "RazerHIDTool",
            path: "Sources/RazerHIDTool"
        )
    ]
)
