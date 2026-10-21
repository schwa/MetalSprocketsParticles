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

    /// `.standard` with `body` applied.
    static func standard(_ body: (inout Self) -> Void) -> Self {
        var modules = Self.standard
        body(&modules)
        return modules
    }

    /// `.fountain` with `body` applied.
    static func fountain(_ body: (inout Self) -> Void) -> Self {
        var modules = Self.fountain
        body(&modules)
        return modules
    }
}
