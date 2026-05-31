import ProjectDescription

let macOSDeploymentTarget = "26.1"

let project = Project(
    name: "pr-buddy",
    options: .options(
        defaultKnownRegions: ["en", "Base"],
        developmentRegion: "en"
    ),
    packages: [
        .remote(
            url: "https://github.com/apple/swift-argument-parser",
            requirement: .upToNextMajor(from: "1.5.0")
        ),
    ],
    settings: .settings(
        base: [
            "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20",
            "DEVELOPMENT_TEAM": "L98LL2N956",
            "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
            "GCC_C_LANGUAGE_STANDARD": "gnu17",
            "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
            "MACOSX_DEPLOYMENT_TARGET": .string(macOSDeploymentTarget),
            "SDKROOT": "macosx",
            "SWIFT_VERSION": "6.0",
        ],
        configurations: [
            .debug(name: "Debug", settings: [
                "ENABLE_TESTABILITY": "YES",
                "GCC_PREPROCESSOR_DEFINITIONS": [
                    "DEBUG=1",
                    "$(inherited)",
                ],
                "ONLY_ACTIVE_ARCH": "YES",
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
                "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
            ]),
            .release(name: "Release", settings: [
                "SWIFT_COMPILATION_MODE": "wholemodule",
            ]),
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
            infoPlist: .default,
            sources: ["pr-buddy/**"],
            dependencies: [
                .package(product: "ArgumentParser"),
            ],
            settings: .settings(base: [
                "PRODUCT_MODULE_NAME": "pr_buddy",
                "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
                "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY": "YES",
            ])
        ),
        .target(
            name: "pr-buddyCLI",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "com.terrylewis.pr-buddy",
            deploymentTargets: .macOS(macOSDeploymentTarget),
            infoPlist: .default,
            sources: ["pr-buddyCLI/**"],
            dependencies: [
                .target(name: "pr-buddy"),
            ],
            settings: .settings(base: [
                "CODE_SIGN_STYLE": "Automatic",
                "ENABLE_HARDENED_RUNTIME": "YES",
                "PRODUCT_MODULE_NAME": "pr_buddyCLI",
                "PRODUCT_NAME": "pr-buddy",
                "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
                "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY": "YES",
            ])
        ),
        .target(
            name: "pr-buddyTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.terrylewis.pr-buddyTests",
            deploymentTargets: .macOS(macOSDeploymentTarget),
            infoPlist: .default,
            sources: ["pr-buddyTests/**"],
            dependencies: [
                .target(name: "pr-buddy"),
            ],
            settings: .settings(base: [
                "PRODUCT_MODULE_NAME": "pr_buddyTests",
                "PRODUCT_NAME": "pr-buddyTests",
                "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
                "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY": "YES",
            ])
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
