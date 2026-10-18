// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MetalSprocketsParticles",
    platforms: [.macOS(.v26), .iOS(.v26), .visionOS(.v26)],
    products: [
        .library(name: "MetalSprocketsParticles", targets: ["MetalSprocketsParticles"]),
        // SwiftUI views, kept apart so the core library has no UI dependency.
        .library(name: "MetalSprocketsParticlesUI", targets: ["MetalSprocketsParticlesUI"]),
        .executable(name: "particles-render", targets: ["particles-render"]),
        .executable(name: "particles-bench", targets: ["particles-bench"]),
    ],
    dependencies: [
        // main until a release includes RenderViewContext.depthTexture (MetalSprockets #530).
        .package(url: "https://github.com/schwa/MetalSprockets", branch: "main"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/schwa/GoldenImage", .upToNextMinor(from: "0.1.6")),
        .package(url: "https://github.com/schwa/MetalCompilerPlugin", .upToNextMinor(from: "0.4.1")),
        .package(url: "https://github.com/schwa/SwiftMesh", .upToNextMinor(from: "0.0.10")),
    ],
    targets: [
        .target(
            name: "MetalSprocketsParticles",
            dependencies: [
                "MetalSprocketsParticlesShaders",
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ],
            resources: [.copy("Resources/Presets")]
        ),
        .target(
            name: "MetalSprocketsParticlesUI",
            dependencies: [
                "MetalSprocketsParticles",
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSprocketsUI", package: "MetalSprockets"),
            ]
        ),
        .testTarget(
            name: "MetalSprocketsParticlesUITests",
            dependencies: ["MetalSprocketsParticlesUI", "MetalSprocketsParticles"]
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
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ],
            resources: [.copy("Golden Images")]
        ),
        .executableTarget(
            name: "particles-bench",
            dependencies: [
                "MetalSprocketsParticles",
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
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
