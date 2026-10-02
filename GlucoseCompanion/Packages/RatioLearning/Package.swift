// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RatioLearning",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "RatioLearning", targets: ["RatioLearning"])
    ],
    dependencies: [
        .package(path: "../GlucoseCore")
    ],
    targets: [
        .target(
            name: "RatioLearning",
            dependencies: [
                .product(name: "GlucoseCore", package: "GlucoseCore")
            ]
        )
    ]
)
