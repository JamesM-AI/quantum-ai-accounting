// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ActivityInsights",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ActivityInsights", targets: ["ActivityInsights"])
    ],
    dependencies: [
        .package(path: "../GlucoseCore"),
        .package(path: "../RatioLearning")
    ],
    targets: [
        .target(
            name: "ActivityInsights",
            dependencies: [
                .product(name: "GlucoseCore", package: "GlucoseCore"),
                .product(name: "RatioLearning", package: "RatioLearning")
            ]
        )
    ]
)
