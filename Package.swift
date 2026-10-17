// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MetalSprocketsParticles",
    platforms: [.macOS(.v26), .iOS(.v26), .visionOS(.v26)],
    products: [
        .library(name: "MetalSprocketsParticles", targets: ["MetalSprocketsParticles"]),
    ],
    dependencies: [
        .package(url: "https://github.com/schwa/MetalSprockets", .upToNextMinor(from: "0.2.3")),
    ],
    targets: [
        .target(
            name: "MetalSprocketsParticles",
            dependencies: [.product(name: "MetalSprockets", package: "MetalSprockets")],
            resources: [.copy("Shaders/Particles.metal")]
        ),
    ]
)
