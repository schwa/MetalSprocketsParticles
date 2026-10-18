import CoreGraphics
import MetalSprocketsParticles
import simd

// Pointer bindings: colliders, force fields, and emitters that follow the mouse (or pointerMotion without it).
extension ParticlesDemoModel {
    /// The pointer bindings as a saved effect stores them, by index.
    var pointerBindings: [PointerBinding] {
        colliders.indices.filter { colliders[$0].followsPointer }.map { .collider($0) }
            + forceFields.indices.filter { forceFields[$0].followsPointer }.map { .forceField($0) }
            + emitters.indices.filter { pointerEmitterIDs.contains(emitters[$0].id) }.map { .emitter($0) }
    }

    /// Where the pointer is: the mouse projected onto the plane through the camera target, or `pointerMotion`'s path
    /// when the mouse is outside the view.
    func pointerPosition(time: Float, projection: simd_float4x4, cameraToWorld: simd_float4x4) -> SIMD3<Float> {
        if let pointerLocation, let position = PointerProjection.worldPosition(
            of: pointerLocation, in: CGSize(width: 1, height: 1), projection: projection, cameraToWorld: cameraToWorld, planePoint: cameraTarget
        ) {
            return position
        }
        return pointerMotion.transform(time: time).columns.3.xyz
    }

    /// Works out this frame's pointer and moves pointer-bound force fields there (simulate takes colliders and
    /// transforms, but not fields). Returns the pointer for `frameColliders` and `frameTransforms`.
    func preparePointer(for system: ParticleSystemRuntime, time: Float, projection: simd_float4x4, cameraToWorld: simd_float4x4) -> SIMD3<Float> {
        let pointer = pointerPosition(time: time, projection: projection, cameraToWorld: cameraToWorld)
        if forceFields.contains(where: \.followsPointer) {
            system.forceFields = frameForceFields(pointer: pointer)
        }
        return pointer
    }

    func frameColliders(time: Float, pointer: SIMD3<Float>) -> [Collider] {
        let spun = colliders.map(\.collider).spun(colliderSpins, at: time)
        let animated = animateColliders ? spun.enumerated().map { index, collider in collider.animated(time: time, index: index) } : spun
        return animated.following(pointer, bindings: pointerBindings)
    }

    func frameForceFields(pointer: SIMD3<Float>) -> [ForceField] {
        forceFields.map(\.field).following(pointer, bindings: pointerBindings)
    }

    func frameTransforms(time: Float, pointer: SIMD3<Float>) -> [simd_float4x4] {
        emitters.map { $0.motion.transform(time: time) }.following(pointer, bindings: pointerBindings)
    }

    // Inspector toggles for the selected item. Writes to an item that no longer exists are dropped.

    var selectedColliderFollowsPointer: Bool {
        get {
            guard case let .collider(id) = selection else {
                return false
            }
            return colliders[id: id]?.followsPointer ?? false
        }
        set {
            if case let .collider(id) = selection, let index = colliders.firstIndex(where: { $0.id == id }) {
                colliders[index].followsPointer = newValue
            }
        }
    }

    var selectedForceFieldFollowsPointer: Bool {
        get {
            guard case let .forceField(id) = selection else {
                return false
            }
            return forceFields[id: id]?.followsPointer ?? false
        }
        set {
            if case let .forceField(id) = selection, let index = forceFields.firstIndex(where: { $0.id == id }) {
                forceFields[index].followsPointer = newValue
            }
        }
    }

    var selectedEmitterFollowsPointer: Bool {
        get { pointerEmitterIDs.contains(selectedEmitter.id) }
        set {
            if newValue {
                pointerEmitterIDs.insert(selectedEmitter.id)
            } else {
                pointerEmitterIDs.remove(selectedEmitter.id)
            }
        }
    }
}
