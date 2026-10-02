// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DexcomShareClient",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "DexcomShareClient", targets: ["DexcomShareClient"])
    ],
    dependencies: [
        .package(path: "../GlucoseCore")
    ],
    targets: [
        .target(name: "DexcomShareClient", dependencies: [
            .product(name: "GlucoseCore", package: "GlucoseCore")
        ])
    ]
)
