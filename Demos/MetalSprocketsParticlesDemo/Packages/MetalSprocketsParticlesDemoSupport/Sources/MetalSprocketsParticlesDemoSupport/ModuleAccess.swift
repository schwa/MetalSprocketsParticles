import MetalSprocketsParticles

// Typed access to modules the demo reads and edits outside the module sections: sub-emitters and triggers (the
// outline), event reporting (event bursts), and user functions. Setting a value adds, replaces, or removes its module.

extension EmitterModules {
    var subEmitters: [SubEmitter] {
        get {
            update.compactMap { if case let .subEmitters(module) = $0.module { module.emitters } else { nil } }.flatMap(\.self)
        }
        set {
            update.removeAll { if case .subEmitters = $0.module { true } else { false } }
            if !newValue.isEmpty {
                update.append(ModuleSlot(.subEmitters(SubEmittersModule(emitters: newValue))))
            }
        }
    }

    var triggers: [EmissionTrigger] {
        get {
            update.compactMap { if case let .triggers(module) = $0.module { module.triggers } else { nil } }.flatMap(\.self)
        }
        set {
            update.removeAll { if case .triggers = $0.module { true } else { false } }
            if !newValue.isEmpty {
                update.append(ModuleSlot(.triggers(TriggersModule(triggers: newValue))))
            }
        }
    }

    /// The enabled events module's settings.
    var events: EventsModule? {
        for slot in update where slot.isEnabled {
            if case let .events(module) = slot.module {
                return module
            }
        }
        return nil
    }

    /// `slot`'s user function. Setting nil removes it.
    subscript(function slot: UserFunctionSlot) -> ParticleFunction? {
        get {
            switch slot {
            case .spawn:
                for case let .function(module) in spawn.map(\.module) {
                    return module.function
                }
            case .update, .collision, .death:
                for module in update.map(\.module) {
                    switch (slot, module) {
                    case let (.update, .function(module)): return module.function
                    case let (.collision, .collisionFunction(module)): return module.function
                    case let (.death, .deathFunction(module)): return module.function
                    default: continue
                    }
                }
            }
            return nil
        }
        set {
            switch slot {
            case .spawn:
                let index = spawn.firstIndex { if case .function = $0.module { true } else { false } }
                let module = newValue.map { SpawnModule.function(SpawnFunctionModule(function: $0)) }
                spawn.replace(at: index, with: module)
            case .update, .collision, .death:
                let index = update.firstIndex { slot.matches($0.module) }
                let module: UpdateModule? = newValue.map { function in
                    switch slot {
                    case .update: .function(UpdateFunctionModule(function: function))
                    case .collision: .collisionFunction(CollisionFunctionModule(function: function))
                    default: .deathFunction(DeathFunctionModule(function: function))
                    }
                }
                update.replace(at: index, with: module)
            }
        }
    }

    /// Whether `slot` has a function. Turning it on starts from the slot's template.
    subscript(hasFunction slot: UserFunctionSlot) -> Bool {
        get { self[function: slot] != nil }
        set { self[function: slot] = newValue ? (self[function: slot] ?? slot.template) : nil }
    }

    /// `slot`'s function, or its template when there is none. Setting it turns the slot on.
    subscript(editableFunction slot: UserFunctionSlot) -> ParticleFunction {
        get { self[function: slot] ?? slot.template }
        set { self[function: slot] = newValue }
    }

    /// `customAttributeCount` as a slider value, kept to 1...4.
    var editableCustomAttributeCount: Float {
        get { Float(customAttributeCount) }
        set { customAttributeCount = min(max(Int(newValue.rounded()), 1), ParticleFunction.maximumCustomAttributes) }
    }
}

extension EmitterModules {
    /// Removes the module at `index` in `stage`, unless it is required or out of range.
    mutating func removeModule(stage: ModuleStage, at index: Int) {
        switch stage {
        case .spawn:
            if spawn.indices.contains(index), !spawn[index].module.isRequired {
                spawn.remove(at: index)
            }
        case .update:
            if update.indices.contains(index), !update[index].module.isRequired {
                update.remove(at: index)
            }
        case .render:
            if render.indices.contains(index), !render[index].module.isRequired {
                render.remove(at: index)
            }
        }
    }
}

extension UserFunctionSlot {
    func matches(_ module: UpdateModule) -> Bool {
        switch (self, module) {
        case (.update, .function), (.collision, .collisionFunction), (.death, .deathFunction): true
        default: false
        }
    }
}

private extension Array {
    /// Replaces the slot at `index` with `module`, appends it when there is no slot, or removes the slot for nil.
    mutating func replace<Module: StageModule>(at index: Int?, with module: Module?) where Element == ModuleSlot<Module> {
        switch (index, module) {
        case let (index?, module?): self[index].module = module
        case let (index?, nil): remove(at: index)
        case let (nil, module?): append(ModuleSlot(module))
        case (nil, nil): break
        }
    }
}
