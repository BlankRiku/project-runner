// swift-tools-version: 6.0
import PackageDescription

// L'app è SwiftUI. Il manifest gira sull'host: su Linux restano libreria e test.
#if os(macOS)
let devRunnerProducts: [Product] = [
    .library(name: "DevRunnerCore", targets: ["DevRunnerCore"]),
    .executable(name: "DevRunner", targets: ["DevRunner"])
]
let devRunnerTargets: [Target] = [
    .target(name: "DevRunnerCore"),
    .executableTarget(
        name: "DevRunner",
        dependencies: ["DevRunnerCore"],
        resources: [.process("Resources")]
    ),
    .testTarget(name: "DevRunnerCoreTests", dependencies: ["DevRunnerCore"])
]
#else
let devRunnerProducts: [Product] = [
    .library(name: "DevRunnerCore", targets: ["DevRunnerCore"])
]
let devRunnerTargets: [Target] = [
    .target(name: "DevRunnerCore"),
    .testTarget(name: "DevRunnerCoreTests", dependencies: ["DevRunnerCore"])
]
#endif

let package = Package(
    name: "DevRunner",
    platforms: [
        .macOS(.v13)
    ],
    products: devRunnerProducts,
    targets: devRunnerTargets
)
