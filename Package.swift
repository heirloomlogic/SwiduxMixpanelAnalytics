// swift-tools-version: 6.2

import PackageDescription

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
        .package(url: "https://github.com/HeirloomLogic/SwiftFormatPlugin", from: "1.6.1"),
        .package(url: "https://github.com/mixpanel/mixpanel-swift", from: "4.3.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "SwiduxMixpanelAnalytics",
            dependencies: [
                .product(name: "SwiduxAnalytics", package: "Swidux"),
                .product(name: "Mixpanel", package: "mixpanel-swift"),
            ],
            plugins: [
                .plugin(name: "SwiftFormatBuildToolPlugin", package: "SwiftFormatPlugin")
            ]
        ),
        .testTarget(
            name: "SwiduxMixpanelAnalyticsTests",
            dependencies: [
                "SwiduxMixpanelAnalytics",
                .product(name: "SwiduxAnalytics", package: "Swidux"),
            ],
            plugins: [
                .plugin(name: "SwiftFormatBuildToolPlugin", package: "SwiftFormatPlugin")
            ]
        ),
    ]
)
