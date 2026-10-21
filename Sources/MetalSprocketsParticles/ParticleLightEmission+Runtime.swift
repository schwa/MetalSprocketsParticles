import Metal
import MetalSprocketsParticlesShaders
import simd

extension ParticleSystemRuntime {
    /// Works out which emitters gather lights this frame and where each writes in `particleLightBuffer`.
    func planParticleLights() {
        var gathers: [ParticleLightGatherData] = []
        var lightColorCurves: [[SIMD4<Float>]] = []
        var next = 0
        let maximum = Int(PARTICLE_MAX_PARTICLE_LIGHTS)
        for emitter in allEmitters {
            guard let light = emitter.resolved.light, light.count > 0, next < maximum else {
                continue
            }
            let count = min(light.count, maximum - next, emitter.capacity)
            let window = emitter.liveWindow
            gathers.append(ParticleLightGatherData(
                sliceStart: UInt32(emitter.range.lowerBound),
                capacity: UInt32(emitter.capacity),
                windowStart: UInt32(window.start),
                windowCount: UInt32(window.count),
                count: UInt32(count),
                firstLight: UInt32(next),
                color: light.color * light.intensity,
                range: max(light.range, 0),
                simulationToWorld: emitter.modelTransform,
                picksBrightest: light.picksBrightest ? 1 : 0
            ))
            lightColorCurves.append(Self.bakedColorWithOpacity(emitter.resolved.colorOverLife))
            next += count
        }
        particleLightGathers = gathers
        particleLightColorCurves = lightColorCurves
        particleLightCount = next
    }

    /// Color over life with opacity, as the renderer bakes it.
    static func bakedColorWithOpacity(_ color: ColorOverLifeModule?) -> [SIMD4<Float>] {
        if let color {
            return EmitterDraw.withOpacity(color.color.baked(), color.opacity.baked())
        }
        let neutral = NeutralModules.colorOverLife
        return EmitterDraw.withOpacity(neutral.color.baked(), neutral.opacity.baked())
    }

    /// The particle lights as of the last finished frame, for lighting your own geometry. Lights without a live
    /// particle are left out.
    public func emittedLights() -> [ParticleLight] {
        let lights = particleLightBuffer.contents().bindMemory(to: ParticleLightData.self, capacity: Int(PARTICLE_MAX_PARTICLE_LIGHTS))
        return (0..<particleLightCount).compactMap { index in
            let light = lights[index]
            guard simd_reduce_max(light.color) > 0 else {
                return nil
            }
            return .point(position: light.position, color: light.color, intensity: 1, range: light.range)
        }
    }
}
