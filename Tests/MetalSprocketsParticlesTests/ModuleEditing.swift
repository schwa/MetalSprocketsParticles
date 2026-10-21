@testable import MetalSprocketsParticles

extension EmitterModules {
    /// Edits the stack's `Module`. Without `initial` the module must be there already, so a test that expects a
    /// `.standard` module fails loudly instead of silently changing nothing; with it, a missing module is added.
    mutating func edit<Module: ParticleModule>(_: Module.Type, adding initial: Module? = nil, _ body: (inout Module) -> Void) {
        guard var module = self[Module.self] ?? initial else {
            preconditionFailure("No \(Module.kind) module to edit")
        }
        body(&module)
        self[Module.self] = module
    }

    /// `.standard` with the given values changed; nil keeps the standard one. Most simulation tests set a few of these
    /// and then burst particles.
    static func standard(
        position: SIMD3<Float>? = nil,
        shape: EmitterShape? = nil,
        velocity: SIMD3<Float>? = nil,
        spread: Float? = nil,
        gravity: SIMD3<Float>? = nil,
        drag: Float? = nil,
        lifetime: ClosedRange<Float>? = nil,
        birthRate: Float? = nil,
        _ body: (inout Self) -> Void = { _ in }
    ) -> Self {
        var modules = Self.standard
        modules.edit(ShapeModule.self) {
            $0.position = position ?? $0.position
            $0.shape = shape ?? $0.shape
        }
        modules.edit(VelocityModule.self) {
            $0.velocity = velocity ?? $0.velocity
            $0.spread = spread ?? $0.spread
        }
        modules.edit(GravityModule.self) { $0.acceleration = gravity ?? $0.acceleration }
        modules.edit(DragModule.self) { $0.amount = drag ?? $0.amount }
        modules.edit(LifetimeModule.self) { $0.range = lifetime ?? $0.range }
        modules.edit(RateModule.self) { $0.birthRate = birthRate ?? $0.birthRate }
        body(&modules)
        return modules
    }

    /// `.standard` with `body` applied.
    /// `.fountain` with `body` applied.
    static func fountain(_ body: (inout Self) -> Void) -> Self {
        var modules = Self.fountain
        body(&modules)
        return modules
    }
}
