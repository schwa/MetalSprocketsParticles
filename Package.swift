// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MetalSprocketsParticles",
    platforms: [.macOS(.v26), .iOS(.v26), .visionOS(.v26)],
    products: [
        .library(name: "MetalSprocketsParticles", targets: ["MetalSprocketsParticles"]),
        .executable(name: "particles-render", targets: ["particles-render"]),
    ],
    dependencies: [
        .package(url: "https://github.com/schwa/MetalSprockets", .upToNextMinor(from: "0.2.3")),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/schwa/GoldenImage", .upToNextMinor(from: "0.1.6")),
        .package(url: "https://github.com/schwa/MetalCompilerPlugin", .upToNextMinor(from: "0.4.1")),
    ],
    targets: [
        .target(
            name: "MetalSprocketsParticles",
            dependencies: [
                "MetalSprocketsParticlesShaders",
                .product(name: "MetalSprockets", package: "MetalSprockets"),
            ]
        ),
        .target(
            name: "MetalSprocketsParticlesShaders",
            dependencies: [.product(name: "MetalSprocketsShaders", package: "MetalSprockets")],
            exclude: ["Metal"],
            cSettings: [.define("METAL_COMPILER_PLUGIN_DEBUG", .when(configuration: .debug))],
            plugins: [.plugin(name: "MetalCompilerPlugin", package: "MetalCompilerPlugin")]
        ),
        .testTarget(
            name: "MetalSprocketsParticlesTests",
            dependencies: [
                "MetalSprocketsParticles",
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "GoldenImage", package: "GoldenImage"),
            ],
            resources: [.copy("Golden Images")]
        ),
        .executableTarget(
            name: "particles-render",
            dependencies: [
                "MetalSprocketsParticles",
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
