// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GlucoseAnalytics",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "GlucoseAnalytics", targets: ["GlucoseAnalytics"])
    ],
    dependencies: [
        .package(path: "../GlucoseCore")
    ],
    targets: [
        .target(
            name: "GlucoseAnalytics",
            dependencies: [
                .product(name: "GlucoseCore", package: "GlucoseCore")
            ]
        )
    ]
)
