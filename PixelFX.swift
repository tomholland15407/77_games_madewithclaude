//
//  PixelFX.swift
//  A Banana Game
//
//  Shared visual-polish toolkit for the pixel-art games. See GAMES_VISUAL_DESIGN.md.
//  The `PixelSprite` renderer only draws flat squares, so "crafted" looks come from
//  three levers layered here: sprite craft (outline + shade ramps), environment
//  (PixelScene: gradient + vignette + scanlines), and juice (bursts, shake, squash).
//
//  Nothing here owns game logic — it's all presentation, reused by every pixel game.
//

import SwiftUI

// MARK: - Color shade ramps

extension Color {
    /// Darker shade — mix toward black. Use for the bottom-right (away-from-light) pixels.
    func shade(_ by: Double) -> Color { self.mix(with: .black, by: by) }
    /// Lighter tint — mix toward white. Use for the top-left (lit) pixels + specular glint.
    func lit(_ by: Double) -> Color { self.mix(with: .white, by: by) }
}

// MARK: - Outlined sprite (the single biggest "crafted vs cheap" upgrade)

/// A `PixelSprite` wrapped in a 1px dark contour so it never blends into the black feed.
/// Draws the silhouette (via `tint`) offset in 8 directions behind the real sprite.
/// Author art normally; the outline is added for free. Scales to fill its `.frame`.
struct OutlinedPixelSprite: View {
    let rows: [String]
    let palette: [Character: Color]
    var outline: Color = Color(red: 0.05, green: 0.05, blue: 0.09)
    var width: CGFloat = 1

    var body: some View {
        ZStack {
            ForEach(0..<8) { i in
                let a = Double(i) * .pi / 4
                PixelSprite(rows: rows, palette: palette, tint: outline)
                    .offset(x: cos(a) * width, y: sin(a) * width)
            }
            PixelSprite(rows: rows, palette: palette)
        }
    }
}

// MARK: - Glow

extension View {
    /// Additive-looking bloom for bright/hot things (tiles, lasers, the ball, slice trails,
    /// the mascot). Two stacked shadows give a soft falloff that reads as emission on black.
    func neonGlow(_ color: Color, radius: CGFloat = 8) -> some View {
        self
            .shadow(color: color.opacity(0.9), radius: radius)
            .shadow(color: color.opacity(0.5), radius: radius * 2)
    }

    /// Squash & stretch. Positive `s` stretches vertically (takeoff); negative squashes
    /// (landing/impact). Anchor at the feet by default so it "plants".
    func squash(_ s: CGFloat, anchor: UnitPoint = .bottom) -> some View {
        scaleEffect(x: 1 - s, y: 1 + s, anchor: anchor)
    }
}

// MARK: - PixelScene (the background stack every world sits in)

/// Gradient sky + your world + optional CRT scanlines + edge vignette. Fills its space.
/// Parallax bands are game-specific (clouds vs. machinery) — draw them inside `content`
/// as `Canvas` shapes offset by `worldX * speed` (far 0.2 / mid 0.5 / near 1.0).
struct PixelScene<Content: View>: View {
    let top: Color
    let bottom: Color
    var vignette: Double = 0.35
    var scanlines: Bool = false
    let content: Content

    init(top: Color, bottom: Color, vignette: Double = 0.35, scanlines: Bool = false,
         @ViewBuilder content: () -> Content) {
        self.top = top
        self.bottom = bottom
        self.vignette = vignette
        self.scanlines = scanlines
        self.content = content()
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
            content
            if scanlines { ScanlineOverlay() }
            VignetteOverlay(strength: vignette)
        }
        .clipped()
    }
}

/// Radial darkening at the edges so the eye centers on the action.
struct VignetteOverlay: View {
    var strength: Double = 0.35
    var body: some View {
        GeometryReader { geo in
            let minD = min(geo.size.width, geo.size.height)
            let maxD = max(geo.size.width, geo.size.height)
            RadialGradient(colors: [.clear, .black.opacity(strength)],
                           center: .center,
                           startRadius: minD * 0.35,
                           endRadius: maxD * 0.75)
        }
        .allowsHitTesting(false)
    }
}

/// Thin horizontal CRT lines. Subtle — arcade texture, not a filter you notice.
struct ScanlineOverlay: View {
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                         with: .color(.white.opacity(0.05)))
                y += 4
            }
        }
        .allowsHitTesting(false)
        .blendMode(.overlay)
    }
}

/// A field of static twinkly dots for night/space backgrounds. Positions fixed per instance.
struct Starfield: View {
    var count: Int = 40
    var color: Color = .white
    private let stars: [(x: CGFloat, y: CGFloat, r: CGFloat)]

    init(count: Int = 40, color: Color = .white) {
        self.count = count
        self.color = color
        self.stars = (0..<count).map { _ in
            (CGFloat.random(in: 0...1), CGFloat.random(in: 0...1), CGFloat.random(in: 0.6...2.0))
        }
    }

    var body: some View {
        Canvas { ctx, size in
            for s in stars {
                let rect = CGRect(x: s.x * size.width, y: s.y * size.height, width: s.r, height: s.r)
                ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(Double(s.r) / 2.0 * 0.8)))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Juice: particle burst

/// A fire-and-forget burst of tiny pixel squares. Add instances to a `@State` array on
/// game events and remove them via `onDone` — never touches the game's physics loop.
struct ParticleBurstView: View {
    let color: Color
    var count: Int = 12
    var spread: CGFloat = 60
    var gravity: CGFloat = 24
    var onDone: (() -> Void)? = nil

    private struct P: Identifiable {
        let id = UUID()
        let angle: Double
        let dist: CGFloat
        let size: CGFloat
    }
    private let parts: [P]
    @State private var go = false

    init(color: Color, count: Int = 12, spread: CGFloat = 60, gravity: CGFloat = 24,
         onDone: (() -> Void)? = nil) {
        self.color = color
        self.count = count
        self.spread = spread
        self.gravity = gravity
        self.onDone = onDone
        self.parts = (0..<count).map { i in
            P(angle: Double(i) / Double(count) * 2 * .pi + Double.random(in: -0.35...0.35),
              dist: spread * CGFloat.random(in: 0.45...1.0),
              size: CGFloat.random(in: 2...4))
        }
    }

    var body: some View {
        ZStack {
            ForEach(parts) { p in
                Rectangle()
                    .fill(color)
                    .frame(width: p.size * 2, height: p.size * 2)
                    .offset(x: go ? cos(p.angle) * p.dist : 0,
                            y: go ? sin(p.angle) * p.dist + gravity : 0)
                    .opacity(go ? 0 : 1)
            }
        }
        .task {
            withAnimation(.easeOut(duration: 0.5)) { go = true }
            try? await Task.sleep(for: .seconds(0.55))
            onDone?()
        }
    }
}

// MARK: - Juice: screen shake

/// Sinusoidal shake driven by an integer trigger — bump the trigger to shake once.
private struct ShakeEffect: GeometryEffect {
    var amount: CGFloat
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let t = sin(animatableData * .pi * shakes)
        return ProjectionTransform(CGAffineTransform(translationX: amount * t,
                                                     y: amount * 0.6 * t))
    }
}

private struct ShakeModifier: ViewModifier {
    let trigger: Int
    let amount: CGFloat
    @State private var data: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .modifier(ShakeEffect(amount: amount, animatableData: data))
            .onChange(of: trigger) { _, _ in
                data = 0
                withAnimation(.linear(duration: 0.35)) { data = 1 }
            }
    }
}

extension View {
    /// Shake once whenever `trigger` changes (e.g. increment on impact/fail).
    func screenShake(_ trigger: Int, amount: CGFloat = 6) -> some View {
        modifier(ShakeModifier(trigger: trigger, amount: amount))
    }
}
