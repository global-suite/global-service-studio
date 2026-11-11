// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GlobalServiceStudio",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "GSSCore", targets: ["GSSCore"]),
    ],
    targets: [
        .target(name: "GSSCore"),
        .testTarget(name: "GSSCoreTests", dependencies: ["GSSCore"]),
    ]
)
