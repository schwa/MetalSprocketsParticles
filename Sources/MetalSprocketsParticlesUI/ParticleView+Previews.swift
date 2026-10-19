import MetalSprocketsParticles
import SwiftUI

// 2D effects over ordinary SwiftUI controls: each uses the overlay camera, so emitter positions are in the view's
// points (origin top left, y down), and lets taps pass through to the controls underneath.

/// One effect with a runtime the caller drives: bursts on demand, emitting continuously, or both.
@MainActor
private final class PreviewEffect {
    let system: ParticleSystem
    let runtime: ParticleSystemRuntime?

    init(_ name: String, _ emitter: ParticleEmitter, sprite: ParticleSprite = .softDot, capacity: Int = 2_000) {
        system = ParticleSystem(name, layers: [EmitterDescription(name, settings: emitter, sprite: sprite, capacity: capacity)])
        let runtime = try? ParticleSystemRuntime(capacity: capacity)
        try? runtime?.apply(system, rebuild: true)
        self.runtime = runtime
    }

    func burst(_ count: Int, at point: CGPoint) {
        runtime?.emitters.first?.burst(count, at: [Float(point.x), Float(point.y), 0])
    }

    @ViewBuilder var view: some View {
        if let runtime {
            ParticleView(runtime: runtime, system: system)
                .camera(.overlay)
                .allowsHitTesting(false)
        }
    }
}

// MARK: Like button

private struct LikeButtonPreview: View {
    @State private var isLiked = false
    @State private var hearts: PreviewEffect = {
        var emitter = ParticleEmitter.default2D
        emitter.birthRate = 0
        emitter.velocity = [0, -260, 0]
        emitter.velocitySpread = 220
        emitter.speedVariation = 80
        emitter.gravity = [0, 420, 0]
        emitter.drag = 1
        emitter.lifetime = 0.7...1.1
        emitter.sizeOverLife = .linear(from: 22, to: 12)
        emitter.opacityOverLife = .linear(from: 1, to: 0)
        emitter.colorOverLife = .constant([1, 1, 1, 1])
        emitter.angleVariation = 0.6
        return PreviewEffect("Hearts", emitter, sprite: .heart, capacity: 200)
    }()

    static let effectSize: CGFloat = 240

    var body: some View {
        Button {
            isLiked.toggle()
            if isLiked {
                hearts.burst(18, at: CGPoint(x: Self.effectSize / 2, y: Self.effectSize / 2))
            }
        } label: {
            Label(isLiked ? "Liked" : "Like", systemImage: isLiked ? "heart.fill" : "heart")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderedProminent)
        .tint(isLiked ? .pink : .gray)
        .controlSize(.large)
        .overlay {
            hearts.view
                .frame(width: Self.effectSize, height: Self.effectSize)
        }
        .frame(width: 360, height: 300)
    }
}

#Preview("Like Button") {
    LikeButtonPreview()
}

// MARK: Confetti card

private struct PaymentSentPreview: View {
    @State private var confetti: PreviewEffect = {
        var emitter = ParticleEmitter.default2D
        emitter.birthRate = 0
        emitter.shape = .box(size: [120, 1, 0])
        emitter.velocity = [0, -520, 0]
        emitter.velocitySpread = 380
        emitter.speedVariation = 160
        emitter.gravity = [0, 650, 0]
        emitter.drag = 1.4
        emitter.lifetime = 2...3
        emitter.sizeOverLife = .constant(9)
        emitter.colorOverLife = .constant([0.6, 0.6, 0.6, 1])
        emitter.colorVariation = [0.4, 0.4, 0.4, 0]
        emitter.opacityOverLife = ParticleCurve([.init(0, 1), .init(0.8, 1), .init(1, 0)])
        emitter.angleVariation = .pi
        emitter.angularSpeed = 6
        emitter.angularSpeedVariation = 6
        return PreviewEffect("Confetti", emitter, sprite: .triangle)
    }()

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Payment Sent")
                    .font(.title.bold())
                Text("$42.00 to Alex")
                    .foregroundStyle(.secondary)
                Button("Celebrate Again") {
                    celebrate(in: geometry.size)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                confetti.view
            }
            .onAppear {
                celebrate(in: geometry.size)
            }
        }
        .frame(width: 360, height: 420)
    }

    private func celebrate(in size: CGSize) {
        confetti.burst(250, at: CGPoint(x: size.width / 2, y: size.height * 0.45))
    }
}

#Preview("Payment Sent") {
    PaymentSentPreview()
}

// MARK: Snowy weather card

private struct WeatherCardPreview: View {
    static let size = CGSize(width: 300, height: 380)

    @State private var snow: PreviewEffect = {
        var emitter = ParticleEmitter.default2D
        emitter.shape = .box(size: [Float(Self.size.width) + 40, 1, 0])
        emitter.position = [Float(Self.size.width) / 2, -10, 0]
        emitter.birthRate = 40
        emitter.velocity = [0, 45, 0]
        emitter.velocitySpread = 18
        emitter.speedVariation = 15
        emitter.gravity = .zero
        emitter.drag = 0
        emitter.lifetime = 8...10
        emitter.sizeOverLife = .constant(4)
        emitter.sizeVariation = 0.5
        emitter.colorOverLife = .constant([1, 1, 1, 0.9])
        emitter.warmupDuration = 8
        return PreviewEffect("Snow", emitter, capacity: 1_000)
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reykjavík")
                .font(.title2.bold())
            Text("-3°")
                .font(.system(size: 72, weight: .thin))
            Label("Light snow", systemImage: "cloud.snow.fill")
            Spacer()
            HStack {
                ForEach(["Mon", "Tue", "Wed", "Thu"], id: \.self) { day in
                    VStack {
                        Text(day).font(.caption)
                        Image(systemName: "snowflake")
                            .accessibilityLabel("Snow")
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(24)
        .foregroundStyle(.white)
        .frame(width: Self.size.width, height: Self.size.height)
        .background {
            ZStack {
                LinearGradient(colors: [.indigo, .blue.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                snow.view
            }
        }
        .clipShape(.rect(cornerRadius: 24))
        .padding()
    }
}

#Preview("Weather Card") {
    WeatherCardPreview()
}

// MARK: Sparkling badge

private struct ProBadgePreview: View {
    static let size = CGSize(width: 220, height: 120)

    @State private var sparkles: PreviewEffect = {
        var emitter = ParticleEmitter.default2D
        emitter.shape = .box(size: [130, 50, 0])
        emitter.position = [Float(Self.size.width) / 2, Float(Self.size.height) / 2, 0]
        emitter.birthRate = 14
        emitter.velocity = .zero
        emitter.velocitySpread = 6
        emitter.speedVariation = 0
        emitter.gravity = .zero
        emitter.lifetime = 0.6...1.2
        emitter.sizeOverLife = ParticleCurve([.init(0, 0), .init(0.4, 14), .init(1, 0)])
        emitter.colorOverLife = .constant([1, 0.9, 0.5, 1])
        emitter.angularSpeed = 2
        return PreviewEffect("Sparkles", emitter, sprite: .star, capacity: 100)
    }()

    var body: some View {
        Text("PRO")
            .font(.title.bold())
            .padding(.horizontal, 22)
            .padding(.vertical, 8)
            .background(.orange.gradient, in: .capsule)
            .foregroundStyle(.white)
            .frame(width: Self.size.width, height: Self.size.height)
            .overlay {
                sparkles.view
            }
    }
}

#Preview("Pro Badge") {
    ProBadgePreview()
}
