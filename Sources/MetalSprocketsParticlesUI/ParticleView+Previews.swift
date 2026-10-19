import MetalSprocketsParticles
import SwiftUI

// 2D effects over ordinary SwiftUI controls: each uses the overlay camera, so emitter positions are in the view's
// points (origin top left, y down), and lets taps pass through to the controls underneath.

/// One effect with a runtime the caller drives: bursts on demand, emitting continuously, or both. Changes to `system`
/// reach the runtime on the next frame and keep the particles.
@MainActor
@Observable
private final class PreviewEffect {
    var system: ParticleSystem
    @ObservationIgnored let runtime: ParticleSystemRuntime?

    convenience init(_ name: String, _ emitter: ParticleEmitter, sprite: ParticleSprite = .softDot, capacity: Int = 2_000) {
        self.init(name, layers: [EmitterDescription(name, settings: emitter, sprite: sprite, capacity: capacity)])
    }

    init(_ name: String, layers: [EmitterDescription]) {
        let system = ParticleSystem(name, layers: layers)
        let runtime = try? ParticleSystemRuntime(capacity: 1)
        try? runtime?.apply(system, rebuild: true)
        self.system = system
        self.runtime = runtime
    }

    func burst(_ count: Int, at point: CGPoint, layer: Int = 0) {
        runtime?.emitters[layer].burst(count, at: [Float(point.x), Float(point.y), 0])
    }

    /// A burst at the emitter's own shape (for `.points`, its points).
    func burst(_ count: Int, layer: Int = 0) {
        runtime?.emitters[layer].burst(count)
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

// MARK: Delete into dust

/// Points on the opaque pixels of `image` (rendered at `scale`), placed at `origin` in points and colored like the
/// pixels, for an emitter with the `.points` shape.
@MainActor
private func dustPoints(of image: CGImage, scale: CGFloat, origin: CGPoint, step: Int = 2) -> [EmitterPoint] {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = pixels.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(
            data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard drawn else {
        return []
    }
    var points: [EmitterPoint] = []
    // Rows in the buffer run top to bottom, as in the view.
    for row in stride(from: 0, to: height, by: step) {
        for column in stride(from: 0, to: width, by: step) {
            let index = (row * width + column) * 4
            let alpha = Float(pixels[index + 3]) / 255
            guard alpha > 0.3 else {
                continue
            }
            let color = SIMD4(Float(pixels[index]), Float(pixels[index + 1]), Float(pixels[index + 2]), 255) / 255 / SIMD4(alpha, alpha, alpha, 1)
            let position = SIMD3(Float(origin.x + CGFloat(column) / scale), Float(origin.y + CGFloat(row) / scale), 0)
            points.append(EmitterPoint(position, color: color))
        }
    }
    return points
}

private struct InboxMessage: Identifiable {
    let id = UUID()
    let sender: String
    let subject: String
    let symbol: String
    let color: Color
}

private struct InboxRowView: View {
    let message: InboxMessage

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: message.symbol)
                .font(.title2)
                .foregroundStyle(message.color)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(message.sender).font(.headline)
                Text(message.subject).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

private struct DeleteIntoDustPreview: View {
    @State private var messages = [
        InboxMessage(sender: "Ada", subject: "Lunch on Friday?", symbol: "fork.knife.circle.fill", color: .orange),
        InboxMessage(sender: "Build Bot", subject: "All 381 tests passed", symbol: "checkmark.seal.fill", color: .green),
        InboxMessage(sender: "Grace", subject: "Slides for the talk", symbol: "doc.richtext.fill", color: .blue),
        InboxMessage(sender: "Calendar", subject: "Dentist, 9:30", symbol: "calendar.circle.fill", color: .red),
        InboxMessage(sender: "Linus", subject: "Re: re: re: tabs vs spaces", symbol: "bubble.left.and.bubble.right.fill", color: .purple),
    ]
    @State private var rowFrames: [InboxMessage.ID: CGRect] = [:]
    @State private var dust: PreviewEffect = {
        var emitter = ParticleEmitter.default2D
        emitter.shape = .points
        emitter.birthRate = 0
        // Blown away to the right and up, as if by a breeze.
        emitter.velocity = [140, -50, 0]
        emitter.velocitySpread = 70
        emitter.speedVariation = 90
        emitter.gravity = [40, -60, 0]
        emitter.drag = 0.8
        emitter.lifetime = 0.7...1.6
        emitter.sizeOverLife = .linear(from: 2.5, to: 1)
        emitter.opacityOverLife = .linear(from: 1, to: 0)
        emitter.colorOverLife = .constant([1, 1, 1, 1])
        return PreviewEffect("Dust", emitter, capacity: 20_000)
    }()

    nonisolated static let space = "inbox"

    var body: some View {
        List {
            ForEach(messages) { message in
                InboxRowView(message: message)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { rowFrames[message.id] = $0 }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            delete(message)
                        }
                    }
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            delete(message)
                        }
                    }
            }
        }
        .coordinateSpace(.named(Self.space))
        .overlay {
            dust.view
        }
        .overlay(alignment: .bottom) {
            Text("Swipe or right-click a message to delete it")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
        }
        .frame(width: 380, height: 380)
    }

    private func delete(_ message: InboxMessage) {
        if let frame = rowFrames[message.id] {
            let renderer = ImageRenderer(content: InboxRowView(message: message).frame(width: frame.width, height: frame.height))
            renderer.scale = 2
            if let image = renderer.cgImage {
                let points = dustPoints(of: image, scale: renderer.scale, origin: frame.origin)
                if !points.isEmpty {
                    dust.system.layers[0].points = points
                    dust.burst(points.count)
                }
            }
        }
        withAnimation(.easeOut(duration: 0.25)) {
            messages.removeAll { $0.id == message.id }
        }
    }
}

#Preview("Delete Into Dust") {
    DeleteIntoDustPreview()
}

// MARK: Pull-to-refresh fountain

private struct PullToRefreshPreview: View {
    /// How far the list is pulled down past its top, in points.
    @State private var pull: CGFloat = 0
    @State private var isArmed = false
    @State private var refreshed = Date.now
    @State private var fountain: PreviewEffect = {
        var emitter = ParticleEmitter.default2D
        emitter.shape = .box(size: [60, 1, 0])
        emitter.birthRate = 0
        emitter.velocity = [0, -220, 0]
        emitter.velocitySpread = 90
        emitter.speedVariation = 60
        emitter.gravity = [0, 600, 0]
        emitter.lifetime = 0.5...0.9
        emitter.sizeOverLife = .linear(from: 4, to: 1.5)
        emitter.colorOverLife = .linear(from: [0.4, 0.8, 1, 1], to: [0.2, 0.4, 1, 0])
        return PreviewEffect("Fountain", emitter)
    }()

    static let width: CGFloat = 360
    /// Pull this far, then let go, to refresh.
    static let threshold: CGFloat = 70

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("Updated \(refreshed.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(1...20, id: \.self) { index in
                    Label("Story \(index)", systemImage: "newspaper")
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            max(0, -(geometry.contentOffset.y + geometry.contentInsets.top))
        } action: { _, newPull in
            pulled(to: newPull)
        }
        .overlay {
            fountain.view
        }
        .overlay(alignment: .top) {
            if pull > 8 {
                Text(isArmed ? "Release to refresh" : "Pull to refresh")
                    .font(.caption.bold())
                    .padding(6)
            }
        }
        .frame(width: Self.width, height: 420)
    }

    private func pulled(to newPull: CGFloat) {
        pull = newPull
        // The fountain sits on the gap's lower edge, the content's top, and grows with the pull.
        moveFountain(to: newPull)
        if newPull > Self.threshold {
            isArmed = true
        } else if newPull < 1, isArmed {
            isArmed = false
            refreshed = .now
            fountain.burst(150, at: CGPoint(x: Self.width / 2, y: 4))
        }
    }

    private func moveFountain(to newPull: CGFloat) {
        var settings = fountain.system.layers[0].settings
        settings.position = [Float(Self.width / 2), Float(newPull), 0]
        settings.birthRate = Float(newPull) * 8
        settings.velocity = [0, -Float(120 + newPull * 3), 0]
        fountain.system.layers[0].settings = settings
    }
}

#Preview("Pull to Refresh") {
    PullToRefreshPreview()
}

// MARK: Typing sparks

private struct TypingSparksPreview: View {
    @State private var name = ""
    @State private var password = ""
    @State private var failures = 0
    @State private var nameWidth: CGFloat = 0
    @State private var passwordWidth: CGFloat = 0
    @State private var fieldFrames: [Int: CGRect] = [:]
    @State private var sparks: PreviewEffect = {
        var spark = ParticleEmitter.default2D
        spark.birthRate = 0
        spark.velocity = [0, -90, 0]
        spark.velocitySpread = 140
        spark.speedVariation = 50
        spark.gravity = [0, 320, 0]
        spark.drag = 1
        spark.lifetime = 0.25...0.5
        spark.sizeOverLife = .linear(from: 5, to: 1)
        spark.colorOverLife = .linear(from: [1, 0.85, 0.4, 1], to: [1, 0.3, 0.1, 0])
        var error = spark
        error.shape = .box(size: [240, 24, 0])
        error.velocity = .zero
        error.velocitySpread = 120
        error.gravity = [0, 200, 0]
        error.lifetime = 0.4...0.8
        error.sizeOverLife = .linear(from: 4, to: 1)
        error.colorOverLife = .linear(from: [1, 0.2, 0.2, 1], to: [0.6, 0, 0, 0])
        return PreviewEffect("Sparks", layers: [
            EmitterDescription("Keystroke", settings: spark, sprite: .spark, capacity: 2_000),
            EmitterDescription("Wrong Password", settings: error, capacity: 2_000),
        ])
    }()

    nonisolated static let space = "form"
    static let fieldPadding: CGFloat = 8

    var body: some View {
        VStack(spacing: 14) {
            Text("Sign In").font(.title.bold())
            field(0) {
                TextField("Name", text: $name)
            }
            field(1) {
                SecureField("Password (it is swordfish)", text: $password)
            }
            .keyframeAnimator(initialValue: CGFloat.zero, trigger: failures) { content, offset in
                content.offset(x: offset)
            } keyframes: { _ in
                for offset: CGFloat in [-10, 9, -7, 5, -3, 0] {
                    LinearKeyframe(offset, duration: 0.05)
                }
            }
            Button("Sign In", action: signIn)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(30)
        .frame(width: 340)
        .coordinateSpace(.named(Self.space))
        .overlay {
            sparks.view
        }
        // The typed text's width puts the sparks at the end of it, where the insertion point usually is.
        .background {
            VStack {
                Text(name).fixedSize().onGeometryChange(for: CGFloat.self, of: \.size.width) { nameWidth = $0 }
                Text(String(repeating: "•", count: password.count)).fixedSize().onGeometryChange(for: CGFloat.self, of: \.size.width) { passwordWidth = $0 }
            }
            .hidden()
        }
        .onChange(of: name) { old, new in
            if new.count > old.count {
                spark(field: 0, width: nameWidth)
            }
        }
        .onChange(of: password) { old, new in
            if new.count > old.count {
                spark(field: 1, width: passwordWidth)
            }
        }
    }

    private func field(_ index: Int, @ViewBuilder content: () -> some View) -> some View {
        content()
            .textFieldStyle(.plain)
            .padding(Self.fieldPadding)
            .background(.quaternary, in: .rect(cornerRadius: 8))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { fieldFrames[index] = $0 }
    }

    private func spark(field index: Int, width: CGFloat) {
        guard let frame = fieldFrames[index] else {
            return
        }
        sparks.burst(8, at: CGPoint(x: frame.minX + Self.fieldPadding + width, y: frame.midY))
    }

    private func signIn() {
        guard password != "swordfish", let frame = fieldFrames[1] else {
            return
        }
        failures += 1
        sparks.burst(220, at: CGPoint(x: frame.midX, y: frame.midY), layer: 1)
    }
}

#Preview("Typing Sparks") {
    TypingSparksPreview()
}
