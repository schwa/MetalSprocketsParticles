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
    ],
    targets: [
        .target(
            name: "MetalSprocketsParticles",
            dependencies: [.product(name: "MetalSprockets", package: "MetalSprockets")],
            resources: [.copy("Shaders/Particles.metal")]
        ),
        .testTarget(
            name: "MetalSprocketsParticlesTests",
            dependencies: [
                "MetalSprocketsParticles",
                .product(name: "MetalSprockets", package: "MetalSprockets"),
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
