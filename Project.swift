import ProjectDescription

let macOSDeploymentTarget = "14.0"

func moduleSettings(_ moduleName: String, productName: String? = nil, base: SettingsDictionary = [:]) -> Settings {
    var settings = base
    settings["PRODUCT_MODULE_NAME"] = .string(moduleName)

    if let productName {
        settings["PRODUCT_NAME"] = .string(productName)
    }

    return .settings(base: settings)
}

let project = Project(
    name: "pr-buddy",
    packages: [
        .remote(
            url: "https://github.com/apple/swift-argument-parser",
            requirement: .upToNextMajor(from: "1.5.0")
        ),
    ],
    settings: .settings(
        base: [
            "MACOSX_DEPLOYMENT_TARGET": .string(macOSDeploymentTarget),
            "SWIFT_VERSION": "6.0",
            "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
            "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY": "YES",
        ],
        defaultSettings: .recommended
    ),
    targets: [
        .target(
            name: "pr-buddy",
            destinations: .macOS,
            product: .staticLibrary,
            bundleId: "com.terrylewis.pr-buddy.core",
            deploymentTargets: .macOS(macOSDeploymentTarget),
            sources: ["pr-buddy/**"],
            dependencies: [
                .package(product: "ArgumentParser"),
            ],
            settings: moduleSettings("pr_buddy")
        ),
        .target(
            name: "pr-buddyCLI",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "com.terrylewis.pr-buddy",
            deploymentTargets: .macOS(macOSDeploymentTarget),
            sources: ["pr-buddyCLI/**"],
            dependencies: [
                .target(name: "pr-buddy"),
            ],
            settings: moduleSettings("pr_buddyCLI", productName: "pr-buddy")
        ),
        .target(
            name: "pr-buddyTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.terrylewis.pr-buddyTests",
            deploymentTargets: .macOS(macOSDeploymentTarget),
            sources: ["pr-buddyTests/**/*.swift"],
            resources: ["pr-buddyTests/__Snapshots__/**"],
            dependencies: [
                .target(name: "pr-buddy"),
            ],
            settings: moduleSettings("pr_buddyTests")
        ),
    ],
    schemes: [
        .scheme(
            name: "pr-buddy",
            shared: true,
            buildAction: .buildAction(targets: ["pr-buddyCLI"]),
            testAction: .targets(["pr-buddyTests"]),
            runAction: .runAction(executable: "pr-buddyCLI")
        ),
    ]
)
