// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BolusCalculator",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "BolusCalculator", targets: ["BolusCalculator"])
    ],
    dependencies: [
        .package(path: "../GlucoseCore")
    ],
    targets: [
        .target(
            name: "BolusCalculator",
            dependencies: [
                .product(name: "GlucoseCore", package: "GlucoseCore")
            ]
        )
    ]
)
