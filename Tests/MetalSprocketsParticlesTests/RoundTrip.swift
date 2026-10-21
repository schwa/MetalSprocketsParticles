import Foundation
@testable import MetalSprocketsParticles

/// `emitter` saved and loaded the way effect files store it: as modules (#218).
func roundTrip(_ emitter: ParticleEmitter, resources: EffectResources = EffectResources()) throws -> ParticleEmitter {
    let json = try resources.encoder().encode(EmitterModules(emitter))
    return try EffectResources(files: resources.files).decoder().decode(EmitterModules.self, from: json).lowered()
}

/// `modules` encoded as an effect file and decoded again.
func roundTrip(_ modules: EmitterModules, resources: EffectResources = EffectResources()) throws -> EmitterModules {
    let json = try resources.encoder().encode(modules)
    return try EffectResources(files: resources.files).decoder().decode(EmitterModules.self, from: json)
}
