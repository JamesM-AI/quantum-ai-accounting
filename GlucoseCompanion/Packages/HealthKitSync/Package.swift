// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HealthKitSync",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "HealthKitSync", targets: ["HealthKitSync"])
    ],
    dependencies: [
        .package(path: "../GlucoseCore")
    ],
    targets: [
        .target(name: "HealthKitSync", dependencies: [
            .product(name: "GlucoseCore", package: "GlucoseCore")
        ])
    ]
)
