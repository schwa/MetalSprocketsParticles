import Foundation
@testable import MetalSprocketsParticles

/// `modules` encoded as an effect file and decoded again.
func roundTrip(_ modules: EmitterModules, resources: EffectResources = EffectResources()) throws -> EmitterModules {
    let json = try resources.encoder().encode(modules)
    return try EffectResources(files: resources.files).decoder().decode(EmitterModules.self, from: json)
}
