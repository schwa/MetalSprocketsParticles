import CoreGraphics
import MetalSprocketsParticles

/// The view's long-lived state: its player and the mouse. Rendering reads and writes it every frame, so nothing here is
/// observed.
final class ParticleViewState {
    private(set) var player: ParticlePlayer?
    /// The mouse location as a fraction of the view (0...1, origin top left), or nil when it is outside.
    var pointerLocation: CGPoint?

    /// The player for this frame, set up with the current system, camera, and pointer. A new player when the caller's
    /// runtime changes, or (for the view's own runtime) when the system's name changes; otherwise the system is updated
    /// in place, which keeps the particles.
    func player(system: ParticleSystem, runtime: ParticleSystemRuntime?, seed: UInt32, camera: ParticleCamera, size: CGSize) throws -> ParticlePlayer {
        let player: ParticlePlayer
        if let existing = self.player, runtime.map({ $0 === existing.runtime }) ?? (existing.system.name == system.name) {
            player = existing
            try player.update(system)
        } else if let runtime {
            player = ParticlePlayer(runtime: runtime, system: system)
        } else {
            player = try ParticlePlayer(system: system, seed: seed)
        }
        self.player = player
        player.camera = camera
        let matrices = camera.matrices(for: system, size: size)
        player.pointer = pointerLocation.flatMap {
            PointerProjection.worldPosition(
                of: $0, in: CGSize(width: 1, height: 1), projection: matrices.projection, cameraToWorld: matrices.cameraToWorld, planePoint: matrices.focus
            )
        }
        return player
    }
}
