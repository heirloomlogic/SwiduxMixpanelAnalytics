// swift-tools-version: 6.2

import Foundation
import PackageDescription

let package = Package(
    name: "SwiduxMixpanelAnalytics",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "SwiduxMixpanelAnalytics", targets: ["SwiduxMixpanelAnalytics"])
    ],
    dependencies: [
        .package(url: "https://github.com/HeirloomLogic/Swidux", from: "1.3.0"),
        .package(url: "https://github.com/mixpanel/mixpanel-swift", from: "6.5.1"),
    ],
    targets: [
        .target(
            name: "SwiduxMixpanelAnalytics",
            dependencies: [
                .product(name: "SwiduxAnalytics", package: "Swidux"),
                .product(name: "Mixpanel", package: "mixpanel-swift"),
            ]
        ),
        .testTarget(
            name: "SwiduxMixpanelAnalyticsTests",
            dependencies: [
                "SwiduxMixpanelAnalytics",
                .product(name: "SwiduxAnalytics", package: "Swidux"),
            ]
        ),
    ]
)

// MARK: - Dev-only tooling
//
// Dev-only tooling (the Persnoop swift-format linter and the DocC command plugin) must not
// leak into downstream consumers' dependency graphs. A build-tool plugin attached to a
// shipping target follows that target into every consumer — as a forced "trust and enable"
// prompt in Xcode, not merely a wasted checkout. SwiftPM has no first-class dev
// dependencies, so gate them on a gitignored `.dev-tooling` sentinel, present only in this
// package's own working clone (and created as a CI step, before the first resolve).
//
// `#filePath` anchors the lookup to this manifest's directory, independent of the current
// working directory. Attaching the plugin here, after the package is constructed, keeps the
// target list above free of gating noise.
//
// Toggling the sentinel on an already-evaluated package requires `swift package purge-cache`:
// SwiftPM caches the evaluated manifest keyed on its source text alone, so a gate that reads
// an external file is invisible to that cache key.

let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let devSentinel = packageDir.appendingPathComponent(".dev-tooling").path

if FileManager.default.fileExists(atPath: devSentinel) {
    package.dependencies += [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.5.0"),
        .package(url: "https://github.com/HeirloomLogic/Persnicket", from: "2.0.0"),
    ]
    for target in package.targets where target.type != .plugin && target.type != .binary {
        target.plugins = (target.plugins ?? []) + [.plugin(name: "Persnoop", package: "Persnicket")]
    }
}
