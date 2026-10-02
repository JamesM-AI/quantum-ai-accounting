// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CorrectionLearning",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "CorrectionLearning", targets: ["CorrectionLearning"])
    ],
    dependencies: [
        .package(path: "../GlucoseCore"),
        .package(path: "../RatioLearning")
    ],
    targets: [
        .target(
            name: "CorrectionLearning",
            dependencies: [
                .product(name: "GlucoseCore", package: "GlucoseCore"),
                .product(name: "RatioLearning", package: "RatioLearning")
            ]
        )
    ]
)
