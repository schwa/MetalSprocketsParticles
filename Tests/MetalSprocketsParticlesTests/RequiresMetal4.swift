// Skips GPU tests on machines without Metal 4, such as GitHub's macOS runners (paravirtual GPU), the way the
// MetalSprockets packages do. MetalSprockets renders only with Metal 4.

import Metal
import Testing

/// True when the default device supports Metal 4.
let supportsMetal4: Bool = MTLCreateSystemDefaultDevice()?.supportsFamily(.metal4) ?? false

extension Trait where Self == ConditionTrait {
    /// Skips a suite or test that needs a Metal 4 GPU when there is none.
    static var requiresMetal4: Self {
        .disabled(if: !supportsMetal4, "Needs a Metal 4 GPU (GitHub runners have none)")
    }
}
