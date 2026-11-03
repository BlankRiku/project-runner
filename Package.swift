// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DevRunner",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "DevRunnerCore", targets: ["DevRunnerCore"]),
        .executable(name: "DevRunner", targets: ["DevRunner"])
    ],
    targets: [
        .target(name: "DevRunnerCore"),
        .executableTarget(name: "DevRunner", dependencies: ["DevRunnerCore"]),
        .testTarget(name: "DevRunnerCoreTests", dependencies: ["DevRunnerCore"])
    ]
)
