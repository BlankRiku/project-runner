// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DevRunner",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "DevRunnerCore", targets: ["DevRunnerCore"])
    ],
    targets: [
        .target(name: "DevRunnerCore"),
        .testTarget(name: "DevRunnerCoreTests", dependencies: ["DevRunnerCore"])
    ]
)
