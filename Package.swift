// swift-tools-version: 6.2

import PackageDescription
import Foundation

// Dev-only tooling (the Persnoop swift-format linter and the DocC plugin) must not
// leak into downstream consumers' dependency graphs. SwiftPM has no first-class
// dev-dependencies, so gate them on a gitignored `.dev-tooling` sentinel present only
// in this package's own working clone (and created as a step in CI). `#filePath`
// anchors the lookup to this manifest's directory, independent of the working dir.
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let devSentinel = packageDir.appendingPathComponent(".dev-tooling").path
let isDevBuild = FileManager.default.fileExists(atPath: devSentinel)

let devDependencies: [Package.Dependency] = isDevBuild
    ? [
        .package(url: "https://github.com/HeirloomLogic/Persnicket", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.5.0"),
    ]
    : []

let devPlugins: [Target.PluginUsage] = isDevBuild
    ? [.plugin(name: "Persnoop", package: "Persnicket")]
    : []

let package = Package(
    name: "SwiduxMixpanelAnalytics",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "SwiduxMixpanelAnalytics", targets: ["SwiduxMixpanelAnalytics"]),
    ],
    dependencies: [
        .package(url: "https://github.com/HeirloomLogic/Swidux", branch: "main"),
        .package(url: "https://github.com/mixpanel/mixpanel-swift", from: "4.3.0"),
    ] + devDependencies,
    targets: [
        .target(
            name: "SwiduxMixpanelAnalytics",
            dependencies: [
                .product(name: "SwiduxAnalytics", package: "Swidux"),
                .product(name: "Mixpanel", package: "mixpanel-swift"),
            ],
            plugins: devPlugins
        ),
        .testTarget(
            name: "SwiduxMixpanelAnalyticsTests",
            dependencies: [
                "SwiduxMixpanelAnalytics",
                .product(name: "SwiduxAnalytics", package: "Swidux"),
            ],
            plugins: devPlugins
        ),
    ]
)
