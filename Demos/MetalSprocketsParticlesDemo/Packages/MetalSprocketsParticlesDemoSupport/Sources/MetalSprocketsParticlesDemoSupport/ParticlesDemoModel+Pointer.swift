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

    /// The mouse projected onto the plane through the camera target, or nil when it is outside the view (the player then
    /// follows the system's pointerMotion).
    func pointerPosition(projection: simd_float4x4, cameraToWorld: simd_float4x4) -> SIMD3<Float>? {
        pointerLocation.flatMap {
            PointerProjection.worldPosition(of: $0, in: CGSize(width: 1, height: 1), projection: projection, cameraToWorld: cameraToWorld, planePoint: cameraTarget)
        }
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
