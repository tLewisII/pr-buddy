// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "pr-buddy",
    platforms: [
        .macOS("26.1")
    ],
    products: [
        .executable(name: "pr-buddy", targets: ["pr-buddyCLI"])
    ],
    targets: [
        .target(
            name: "pr-buddy",
            path: "pr-buddy"
        ),
        .executableTarget(
            name: "pr-buddyCLI",
            dependencies: ["pr-buddy"],
            path: "pr-buddyCLI"
        ),
        .testTarget(
            name: "pr-buddyTests",
            dependencies: ["pr-buddy"],
            path: "pr-buddyTests"
        )
    ]
)
