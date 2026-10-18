// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MetalSprocketsParticlesDemoSupport",
    platforms: [.macOS(.v26), .iOS(.v26), .visionOS(.v26)],
    products: [
        .library(name: "MetalSprocketsParticlesDemoSupport", targets: ["MetalSprocketsParticlesDemoSupport"]),
    ],
    dependencies: [
        .package(path: "../../../.."),
        // main until a release includes RenderViewContext.depthTexture (MetalSprockets #530).
        .package(url: "https://github.com/schwa/MetalSprockets", branch: "main"),
        .package(url: "https://github.com/schwa/Interaction3D", .upToNextMinor(from: "0.1.15")),
        .package(url: "https://github.com/schwa/SwiftMesh", .upToNextMinor(from: "0.0.10")),
    ],
    targets: [
        .target(
            name: "MetalSprocketsParticlesDemoSupport",
            dependencies: [
                .product(name: "MetalSprocketsParticles", package: "MetalSprocketsParticles"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSprocketsUI", package: "MetalSprockets"),
                .product(name: "Interaction3D", package: "Interaction3D"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ]
        ),
        .testTarget(
            name: "MetalSprocketsParticlesDemoSupportTests",
            dependencies: ["MetalSprocketsParticlesDemoSupport"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
