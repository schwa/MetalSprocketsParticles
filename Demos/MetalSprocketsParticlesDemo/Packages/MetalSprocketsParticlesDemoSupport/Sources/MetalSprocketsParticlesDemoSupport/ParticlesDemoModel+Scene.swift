import MetalSprocketsParticles
import simd

// Scene-level animation and events: collider spins, event bursts, tracked objects. The model keeps them by item and
// emitter id; these give the index-based forms saved effects use.
extension ParticlesDemoModel {
    var colliderSpins: [ColliderSpin] {
        colliders.enumerated().compactMap { index, item in
            item.spin.map { ColliderSpin(collider: index, axis: $0.axis, speed: $0.speed) }
        }
    }

    /// The event bursts by layer index. Bursts whose emitters are gone are dropped.
    var eventBursts: [EventBurst] {
        eventBurstItems.compactMap { item in
            guard let source = emitters.firstIndex(where: { $0.id == item.sourceID }),
                  let target = emitters.firstIndex(where: { $0.id == item.targetID }) else {
                return nil
            }
            return EventBurst(sourceLayer: source, occasion: item.occasion, targetLayer: target, count: item.count)
        }
    }

    /// Tracked objects by name. Later items win when two share a name.
    var trackedObjects: [String: EmitterMotion] {
        Dictionary(trackedObjectItems.map { ($0.name, $0.motion) }) { _, later in later }
    }

    func addEventBurst() {
        guard let first = emitters.first else {
            return
        }
        eventBurstItems.append(EventBurstItem(sourceID: first.id, occasion: .collision, targetID: (emitters.last ?? first).id, count: 10))
    }

    func addTrackedObject() {
        let names = Set(trackedObjectItems.map(\.name))
        let name = (1...).lazy.map { "Object \($0)" }.first { !names.contains($0) } ?? "Object"
        trackedObjectItems.append(TrackedObjectItem(name: name, motion: EmitterMotion(kind: .circle, radius: 1.5, speed: 1, offset: cameraTarget)))
    }

    // The selected collider's spin, for the inspector. Writes to a collider that no longer exists are dropped.

    var selectedColliderSpins: Bool {
        get { selectedColliderItem?.spin != nil }
        set { updateSelectedCollider { $0.spin = newValue ? ($0.spin ?? SteadySpin()) : nil } }
    }

    var selectedColliderSpin: SteadySpin {
        get { selectedColliderItem?.spin ?? SteadySpin() }
        set { updateSelectedCollider { $0.spin = newValue } }
    }

    private var selectedColliderItem: ColliderItem? {
        guard case let .collider(id) = selection else {
            return nil
        }
        return colliders.first { $0.id == id }
    }

    private func updateSelectedCollider(_ change: (inout ColliderItem) -> Void) {
        if case let .collider(id) = selection, let index = colliders.firstIndex(where: { $0.id == id }) {
            change(&colliders[index])
        }
    }
}
