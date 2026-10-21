import Foundation
@testable import MetalSprocketsParticles

/// `emitter` saved and loaded the way effect files store it: as modules (#218).
func roundTrip(_ emitter: ParticleEmitter, resources: EffectResources = EffectResources()) throws -> ParticleEmitter {
    let json = try resources.encoder().encode(EmitterModules(emitter))
    return try EffectResources(files: resources.files).decoder().decode(EmitterModules.self, from: json).lowered()
}
