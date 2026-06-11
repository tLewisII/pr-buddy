// swift-tools-version: 6.0

import PackageDescription

let macOSDeploymentTarget = "14.0"

let package = Package(
    name: "pr-buddy",
    platforms: [
        .macOS(macOSDeploymentTarget)
    ],
    products: [
        .executable(name: "pr-buddy", targets: ["pr-buddyCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "pr-buddy",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "pr-buddy",
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .executableTarget(
            name: "pr-buddyCLI",
            dependencies: ["pr-buddy"],
            path: "pr-buddyCLI"
        ),
        .testTarget(
            name: "pr-buddyTests",
            dependencies: ["pr-buddy"],
            path: "pr-buddyTests",
            resources: [
                .copy("__Snapshots__")
            ]
        )
    ]
)
