import MetalSprocketsParticlesShaders
import simd

// Modules write their own part of each draw (#226): render uniforms, baked curves, and blending. One pass over the
// enabled modules also finds the ones the draw planner needs, so planning reads modules, not the flat ParticleEmitter.

/// The modules the draw planner looks at, found while contributing.
struct DrawModules {
    var sprite: SpriteModule?
    var mesh: MeshModule?
    var trail: TrailModule?
    var ribbon: RibbonModule?
    var shading: ShadingModule?
    var colorImage: ColorImageModule?
}

extension EmitterModules {
    /// How a sprite module that is missing draws.
    static var neutralSprite: SpriteModule {
        NeutralModules.sprite
    }

    /// Writes every enabled module's part of `draw`, over the values that apply when a module is missing, and returns
    /// the modules the planner needs.
    @discardableResult
    func contribute(to draw: inout EmitterDraw, emitter: ParticleSystemRuntime.Emitter) -> DrawModules {
        let color = NeutralModules.colorOverLife
        draw.colorCurve = EmitterDraw.withOpacity(color.color.baked(), color.opacity.baked())
        draw.sizeCurve = NeutralModules.sizeOverLife.curve.baked()
        draw.extraColorCurves = EmitterDraw.whiteCurves(count: 3)
        let speed = NeutralModules.colorBySpeed.range
        draw.uniforms.speedColorRange = [speed.lowerBound, speed.upperBound]
        draw.uniforms.positionColorStart = NeutralModules.colorByPosition.start
        draw.uniforms.positionColorEnd = NeutralModules.colorByPosition.end
        draw.applySequence(nil, texture: emitter.texture)
        var found = DrawModules()
        Self.neutralSprite.contribute(to: &draw)
        for slot in spawn where slot.isEnabled {
            if case let .colorImage(module) = slot.module {
                found.colorImage = module
            }
        }
        for slot in render where slot.isEnabled {
            switch slot.module {
            case let .sprite(module):
                module.contribute(to: &draw)
                found.sprite = module
            case let .colorOverLife(module):
                module.contribute(to: &draw)
            case let .sizeOverLife(module):
                draw.sizeCurve = module.curve.baked()
            case let .colorBySpeed(module):
                module.contribute(to: &draw)
            case let .colorByPosition(module):
                module.contribute(to: &draw)
            case let .imageSequence(module):
                draw.applySequence(module.sequence, texture: emitter.texture)
            case let .shading(module):
                draw.uniforms.isLit = module.model == .lit ? 1 : 0
                found.shading = module
            case let .levelOfDetail(module):
                if module.scalesSize, emitter.lodRateScale > 0 {
                    draw.uniforms.sizeScale = 1 / emitter.lodRateScale.squareRoot()
                }
            case let .mesh(module):
                found.mesh = module
            case let .trail(module):
                found.trail = module
            case let .ribbon(module):
                found.ribbon = module
            case .light:
                break
            }
        }
        return found
    }
}

extension EmitterDraw {
    /// Color curve samples with each alpha scaled by the opacity curve.
    static func withOpacity(_ colors: [SIMD4<Float>], _ opacity: [Float]) -> [SIMD4<Float>] {
        zip(colors, opacity).map { color, opacity in SIMD4(color.x, color.y, color.z, color.w * opacity) }
    }

    /// `count` curves of white: the extra color curves a module does not set.
    static func whiteCurves(count: Int) -> [SIMD4<Float>] {
        [SIMD4<Float>](repeating: .one, count: count * Int(PARTICLE_CURVE_SAMPLES))
    }

    /// Replaces extra color curve `index` (0 by speed, 1 alternate, 2 by position).
    mutating func setExtraColorCurve(_ index: Int, _ samples: [SIMD4<Float>]) {
        let count = Int(PARTICLE_CURVE_SAMPLES)
        extraColorCurves.replaceSubrange((index * count)..<((index + 1) * count), with: samples)
    }

    /// The sprite sheet layout. Without a texture there is no sheet.
    mutating func applySequence(_ sequence: ImageSequence?, texture: MTLTexture?) {
        let sequence = texture == nil ? ImageSequence() : sequence ?? ImageSequence()
        uniforms.sheetColumns = UInt32(max(sequence.columns, 1))
        uniforms.sheetRows = UInt32(max(sequence.rows, 1))
        uniforms.frameCount = UInt32(max(sequence.frameCount, 1))
        uniforms.sequenceMode = sequence.mode
    }
}

extension SpriteModule {
    func contribute(to draw: inout EmitterDraw) {
        draw.blendMode = blendMode
        draw.uniforms.blendMode = blendMode
        draw.uniforms.fixedNormal = orientation.fixedNormal
        draw.uniforms.velocityStretch = orientation.velocityStretch
        draw.uniforms.orientationMode = orientation.mode
        draw.uniforms.softness = max(softness, 0)
        draw.uniforms.minimumScreenSize = max(minimumScreenSize, 0)
    }
}

extension ColorOverLifeModule {
    func contribute(to draw: inout EmitterDraw) {
        let opacity = self.opacity.baked()
        draw.colorCurve = EmitterDraw.withOpacity(color.baked(), opacity)
        if let alternate {
            draw.setExtraColorCurve(1, EmitterDraw.withOpacity(alternate.baked(), opacity))
            draw.uniforms.hasAlternateColor = 1
        }
    }
}

extension ColorBySpeedModule {
    func contribute(to draw: inout EmitterDraw) {
        draw.uniforms.speedColorRange = [range.lowerBound, range.upperBound]
        if let curve {
            draw.setExtraColorCurve(0, curve.baked())
            draw.uniforms.hasSpeedColor = 1
        }
    }
}

extension ColorByPositionModule {
    func contribute(to draw: inout EmitterDraw) {
        draw.uniforms.positionColorStart = start
        draw.uniforms.positionColorEnd = end
        if let curve {
            draw.setExtraColorCurve(2, curve.baked())
            // At birth, the simulation applies it instead.
            draw.uniforms.hasPositionColor = atBirth ? 0 : 1
        }
    }
}
