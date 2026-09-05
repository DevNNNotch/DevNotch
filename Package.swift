// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DevNotchCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DevNotchCore", targets: ["DevNotchCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/Defaults", from: "9.0.2")
    ],
    targets: [
        .target(
            name: "DevNotchCore",
            dependencies: [
                .product(name: "Defaults", package: "Defaults")
            ],
            path: "boringNotch/DevNotch",
            sources: [
                "DeveloperWorkspaceModel.swift",
                "Models/UsageSample.swift",
                "Models/DeveloperEvent.swift",
                "Models/SystemSnapshot.swift",
                "Models/DeveloperDefaults.swift",
                "Services/KeychainStore.swift",
                "Services/SystemMonitor.swift",
                "Services/UsageProvider.swift",
                "Services/CodexUsageCollector.swift",
                "Services/OpenAIUsageProvider.swift",
                "Services/OllamaService.swift",
                "Services/VLLMService.swift",
                "Services/LocalAPIModels.swift",
                "Services/LocalAPIRouter.swift",
                "Services/LocalAPIServer.swift",
                "Features/ClipboardClassifier.swift",
                "Features/ClipboardMonitor.swift",
                "Features/AIAction.swift",
                "Features/DeveloperDashboardView.swift",
                "Features/UsageDashboardView.swift",
                "Features/DeveloperSettingsView.swift"
            ]
        ),
        .testTarget(
            name: "DevNotchCoreTests",
            dependencies: ["DevNotchCore"],
            path: "Tests/DevNotchCoreTests"
        )
    ]
)
