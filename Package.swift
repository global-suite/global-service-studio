// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GlobalServiceStudio",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "GSSCore", targets: ["GSSCore"]),
        .executable(name: "GlobalServiceStudio", targets: ["GlobalServiceStudio"]),
    ],
    targets: [
        .target(name: "GSSCore"),
        .target(name: "GSSApp", dependencies: ["GSSCore"], resources: [.process("Resources")]),
        .executableTarget(name: "GlobalServiceStudio", dependencies: ["GSSApp"]),
        .testTarget(name: "GSSCoreTests", dependencies: ["GSSCore"]),
        .testTarget(name: "GSSAppTests", dependencies: ["GSSApp"]),
    ]
)
