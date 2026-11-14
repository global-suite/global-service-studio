// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "GlobalServiceStudio",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "GSSCore", targets: ["GSSCore"]),
        .executable(name: "GlobalServiceStudio", targets: ["GlobalServiceStudio"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", .upToNextMinor(from: "7.12.0")),
    ],
    targets: [
        .target(name: "GSSCore"),
        .target(name: "GSSLibrary", dependencies: ["GSSCore", .product(name: "GRDB", package: "GRDB.swift")]),
        .target(name: "GSSApp", dependencies: ["GSSCore", "GSSLibrary"], resources: [.process("Resources")]),
        .executableTarget(name: "GlobalServiceStudio", dependencies: ["GSSApp"]),
        // Developer tool that measures video playback (ADR 0008); not part of the app.
        .executableTarget(name: "GSSVideoBench"),
        .testTarget(name: "GSSCoreTests", dependencies: ["GSSCore"]),
        .testTarget(name: "GSSLibraryTests", dependencies: ["GSSLibrary"]),
        .testTarget(name: "GSSAppTests", dependencies: ["GSSApp", "GSSLibrary"]),
    ],
    swiftLanguageModes: [.v5]
)
