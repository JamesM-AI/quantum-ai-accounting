// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GlucoseCore",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "GlucoseCore", targets: ["GlucoseCore"])
    ],
    targets: [
        .target(name: "GlucoseCore")
    ]
)
