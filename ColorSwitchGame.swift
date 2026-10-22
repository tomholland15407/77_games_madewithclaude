//
//  ColorSwitchGame.swift
//  A Banana Game
//
//  Reflex — a Color Switch homage. TAP anywhere to hop the banana ball upward against
//  gravity, climbing through a tower of rotating multi-coloured rings. You may only
//  touch the arc segment that matches your ball's CURRENT colour — brush a wrong colour
//  and you fail back to level 1. Little switch dots between the rings recolour the ball,
//  so you must re-read every gap. Clear the level's quota of rings to win; if the ball
//  falls off the bottom, that's a fail too. 7 levels: faster spin, more arcs/colours,
//  tighter rings — the neon tower deepens in hue as you climb.
//
//  Drawn as Color Switch: a charcoal void, thick rings in the game's cyan / yellow / purple / pink
//  (orange and green join for the 5- and 6-arc levels), the quartered colour-switcher dot, a small
//  solid ball, the thin white score, and the ball bursting into coloured dots when it dies. Each
//  ring is drawn centred on `ringRadius` and exactly `2 × ringThick` thick — the band `step()`
//  tests — and colours are looked up in the full palette, never the level-sized slice.
//

import SwiftUI

enum ColorSwitchGame {
    static let definition = GameDefinition(
        id: "color-switch",
        title: "Prism Pass",
        emoji: "🍌",
        genre: .reflex,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Tap to hop the ball up through a tower of rotating multi-colored rings.",
                "Only pass through the arc segment matching your ball's current color.",
                "Switch dots between rings recolor the ball, so re-read every gap.",
                "Brush a wrong color, or fall off the bottom, and you're back to level 1.",
            ],
            bulletsVI: [
                "Chạm để nảy bóng lên qua một tháp các vòng nhiều màu đang xoay.",
                "Chỉ được đi qua đoạn cung khớp với màu hiện tại của bóng.",
                "Chấm đổi màu giữa các vòng sẽ tô lại màu bóng, nên hãy đọc kỹ mỗi khe.",
                "Chạm sai màu, hoặc rơi khỏi đáy, sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(ColorSwitchView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct ColorSwitchView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void
    @Environment(\.isDemo) private var isDemo

    // The shared colour set: Color Switch's own four, then two extras for the 5–6 arc levels.
    // Higher levels use more of it → smaller arcs, harder reads.
    private static let allColors: [Color] = [
        Color(red: 0.20, green: 0.89, blue: 0.95),   // cyan
        Color(red: 0.96, green: 0.87, blue: 0.05),   // yellow
        Color(red: 0.50, green: 0.16, blue: 0.86),   // purple
        Color(red: 0.98, green: 0.02, blue: 0.52),   // pink
        Color(red: 1.00, green: 0.50, blue: 0.08),   // orange
        Color(red: 0.24, green: 0.82, blue: 0.36)    // green
    ]

    // MARK: Difficulty
    private var arcCount: Int        { [4, 4, 4, 5, 5, 6, 6][min(level, 7) - 1] }
    private var toClear: Int         { [3, 4, 5, 6, 7, 8, 9][min(level, 7) - 1] }
    private var ringRadius: CGFloat  { [0.17, 0.16, 0.15, 0.14, 0.13, 0.12, 0.11][min(level, 7) - 1] }
    private var rotSpeed: CGFloat    { [0.9, 1.1, 1.3, 1.6, 1.9, 2.3, 2.7][min(level, 7) - 1] }
    private var colorsUsed: [Color]  { Array(Self.allColors.prefix(arcCount)) }
    // Generous safety-net clock so you can't just hover forever (CLAUDE.md: always a fail).
    private var timeLimit: Double    { Double(18 + toClear * 6) }

    // Spacing derives from the ring size so the colour dot (placed at the midpoint) always
    // clears each neighbouring ring by ~0.22 world-units, regardless of level.
    private var ringSpacing: CGFloat { 2 * (ringRadius + 0.22) }
    private let ballX: CGFloat = 0.5
    private let ballR: CGFloat = 0.028
    private let ringThick: CGFloat = 0.02
    private let anchor: CGFloat = 0.34        // ball's screen-y at the highwater mark
    private let gravity: CGFloat = 1.5
    private let bounceV: CGFloat = 0.34       // very small hop — creep up with fine control
    private let fallLimit: CGFloat = 0.80     // world units below highwater before it's a fall

    // MARK: Model
    private struct Ring: Identifiable {
        let id = UUID()
        let worldY: CGFloat
        let speed: CGFloat
        let dir: CGFloat
        var passed = false
    }
    private struct Dot: Identifiable {
        let id = UUID()
        let worldY: CGFloat
        var used = false
    }

    @State private var rings: [Ring] = []
    @State private var dots: [Dot] = []
    @State private var ballWorldY: CGFloat = 0
    @State private var cam: CGFloat = 0
    @State private var vy: CGFloat = 0
    @State private var ballColorIndex: Int = 0
    @State private var t: Double = 0
    @State private var passedCount = 0
    @State private var timeLeft: Double = 0
    @State private var done = false
    @State private var loopTask: Task<Void, Never>?
    @State private var demoRecolors: [Int] = []   // demo: fixed dot recolours instead of random
    @State private var demoTapID = 0              // demo: bumps per hop → a fresh DemoTapRipple

    private func screenY(_ worldY: CGFloat, _ h: CGFloat) -> CGFloat {
        (anchor + (cam - worldY)) * h
    }
    /// Which segment (palette index) sits at screen angle `phi` on ring `ring`.
    private func colorIndexAt(_ phi: CGFloat, _ ring: Ring) -> Int {
        let seg = (2 * CGFloat.pi) / CGFloat(arcCount)
        let rot = CGFloat(t) * ring.speed * ring.dir
        var a = (phi - rot).truncatingRemainder(dividingBy: 2 * .pi)
        if a < 0 { a += 2 * .pi }
        return Int(a / seg) % arcCount
    }

    @State private var deathY: CGFloat? = nil     // presentation: where the ball burst (field fraction)

    /// Render-time colour: always the full palette (see the ColorBump crash note), never `colorsUsed`.
    private func swatch(_ i: Int) -> Color {
        Self.allColors[max(0, min(i, Self.allColors.count - 1))]
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height

            ZStack(alignment: .topLeading) {
                CSArt.backdrop

                // Rings, switcher dots and the ball: one Canvas.
                Canvas { ctx, size in drawTower(ctx, size: size) }

                CSScore(passed: passedCount, total: toClear, fraction: isDemo ? nil : (timeLimit > 0 ? timeLeft / timeLimit : 0),
                        scale: isDemo ? 0.62 : 1)
                    .padding(.leading, isDemo ? 12 : 18)
                    .padding(.top, isDemo ? 6 : 12)
                    .allowsHitTesting(false)

                Color.clear.contentShape(Rectangle())
                    .onTapGesture { hop() }

                if let dy = deathY {
                    CSBurst(colors: Array(Self.allColors.prefix(4)), size: ballR * 2 * h)
                        .position(x: ballX * w, y: dy * h)
                        .allowsHitTesting(false)
                }

                if isDemo && demoTapID > 0 {
                    DemoTapRipple().id(demoTapID).position(x: w * 0.74, y: h * 0.80)
                }
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
        // Any end short of the quota (a wrong colour, a fall, the clock): the ball bursts.
        .onChange(of: done) { _, isDone in
            deathY = isDone && passedCount < toClear ? anchor + (cam - ballWorldY) : nil
        }
    }

    private func drawTower(_ ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        let seg = 2 * Double.pi / Double(arcCount)
        for ring in rings {
            let c = CGPoint(x: ballX * w, y: screenY(ring.worldY, h))
            guard c.y > -ringRadius * h - 40, c.y < h + ringRadius * h + 40 else { continue }
            let rot = Double(CGFloat(t) * ring.speed * ring.dir)
            for i in 0..<arcCount {
                var arc = Path()
                arc.addArc(center: c, radius: ringRadius * h, startAngle: .radians(rot + Double(i) * seg),
                           endAngle: .radians(rot + Double(i + 1) * seg), clockwise: false)
                ctx.stroke(arc, with: .color(swatch(i)), style: StrokeStyle(lineWidth: ringThick * 2 * h, lineCap: .butt))
            }
        }
        for dot in dots where !dot.used {
            CSArt.switcher(ctx, at: CGPoint(x: ballX * w, y: screenY(dot.worldY, h)), radius: ballR * h * 0.95,
                           colors: (0..<arcCount).map { swatch($0) })
        }
        if deathY == nil {
            let p = CGPoint(x: ballX * w, y: screenY(ballWorldY, h))
            let r = ballR * h
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(swatch(ballColorIndex)))
        }
    }

    // MARK: Input
    private func hop() {
        guard !done else { return }
        vy = bounceV
        SoundManager.shared.tap(); Haptics.tap()
    }

    // MARK: - Flow
    private func run() async {
        setup()
        var last = Date()
        let start = Date()
        loopTask = Task {
            while !Task.isCancelled && !done {
                try? await Task.sleep(for: .seconds(0.016))
                let now = Date()
                let dt = CGFloat(min(0.05, now.timeIntervalSince(last)))
                last = now
                timeLeft = max(0, timeLimit - now.timeIntervalSince(start))
                if timeLeft <= 0 { fail(); break }
                step(dt: dt)
            }
        }
    }

    private func setup() {
        ballWorldY = 0; cam = 0; vy = bounceV; t = 0; passedCount = 0; done = false
        timeLeft = timeLimit
        ballColorIndex = Int.random(in: 0..<arcCount)
        var r: [Ring] = []
        var d: [Dot] = []
        var y: CGFloat = 0.5
        for i in 0..<(toClear + 1) {
            r.append(Ring(worldY: y, speed: rotSpeed * CGFloat.random(in: 0.85...1.2),
                          dir: Bool.random() ? 1 : -1))
            if i < toClear { d.append(Dot(worldY: y + ringSpacing / 2)) }
            y += ringSpacing
        }
        rings = r; dots = d
    }

    private func step(dt: CGFloat) {
        guard !done else { return }
        t += Double(dt)

        // Vertical motion (world up is positive).
        vy -= gravity * dt
        ballWorldY += vy * dt
        if ballWorldY > cam { cam = ballWorldY }               // camera tracks highwater

        // Fell off the bottom.
        if cam - ballWorldY > fallLimit { fail(); return }

        // Colour dots.
        for i in dots.indices where !dots[i].used {
            if abs(dots[i].worldY - ballWorldY) < ballR + 0.02 {
                dots[i].used = true
                if isDemo, !demoRecolors.isEmpty {
                    ballColorIndex = demoRecolors.removeFirst()
                } else {
                    ballColorIndex = (0..<arcCount).filter { $0 != ballColorIndex }.randomElement() ?? ballColorIndex
                }
                SoundManager.shared.tap(); Haptics.tap()
            }
        }

        // Ring contact — vertical crossing, so contact angle is ±90°.
        for i in rings.indices {
            let d = abs(ballWorldY - rings[i].worldY)
            if abs(d - ringRadius) < ballR + ringThick {
                let phi: CGFloat = ballWorldY < rings[i].worldY ? .pi / 2 : -.pi / 2
                if colorIndexAt(phi, rings[i]) != ballColorIndex { fail(); return }
            }
            // Counted once fully above the ring.
            if !rings[i].passed && ballWorldY > rings[i].worldY + ringRadius {
                rings[i].passed = true
                passedCount += 1
                SoundManager.shared.tap(); Haptics.tap()
                if passedCount >= toClear { win(); return }
            }
        }
    }

    // MARK: - Demo (live manual clip)
    // The closing stretch of level 1: ring 1 already cleared (1/3) and the ball just above it,
    // then two more rings through the real `hop`/`step` at a fixed 1/60s. Ring speeds (all 1.08,
    // inside L1's random 0.765…1.08 band), directions, starting colour, the one dot recolour and the
    // tap frames came from an offline time-optimal search (≥8 frames between taps, like a human
    // thumb) with safety margins; an exact replay of `step` wins on frame 486 (~8.1s) with ≥0.27 rad
    // of segment slack at every crossing. A full L1 run can't beat ~10.5s: each ring makes you
    // hover until your colour swings from the bottom arc round to the top one.
    private static let demoTaps: Set<Int> = [
        10, 18, 26, 34, 42, 50, 58, 66, 74, 82, 90, 98, 108, 118, 128, 151, 160, 183,
        202, 210, 218, 226, 234, 242, 250, 258, 266, 274, 282, 290, 298, 306, 314, 322,
        330, 338, 346, 354, 362, 370, 378, 386, 406, 436, 445, 457, 469, 477, 485
    ]

    private func demoSetup() {
        cam = 0.80; ballWorldY = 0.80; vy = bounceV; passedCount = 1; done = false
        t = 4.0                                   // ring phase offset (all rings share it)
        timeLeft = timeLimit
        ballColorIndex = 1
        demoRecolors = [3]
        let dirs: [CGFloat] = [1, 1, -1, 1]
        var r: [Ring] = []
        var d: [Dot] = []
        var y: CGFloat = 0.5
        for i in 0..<(toClear + 1) {
            r.append(Ring(worldY: y, speed: 1.08, dir: dirs[i % dirs.count], passed: i == 0))
            if i < toClear { d.append(Dot(worldY: y + ringSpacing / 2, used: i == 0)) }
            y += ringSpacing
        }
        rings = r; dots = d
    }

    private func runDemo() async {
        let dt: CGFloat = 1.0 / 60.0
        while !Task.isCancelled {
            demoSetup()
            try? await Task.sleep(for: .seconds(0.4))
            var frame = 0
            while !Task.isCancelled && !done && frame < 900 {
                frame += 1
                if Self.demoTaps.contains(frame) { hop(); demoTapID += 1 }
                step(dt: dt)
                try? await Task.sleep(for: .seconds(0.016))
            }
            // 3/3 → the real win() ran (onWin is a no-op). Hold, then loop.
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    private func win() {
        guard !done else { return }
        done = true; loopTask?.cancel(); onWin()
    }
    private func fail() {
        guard !done else { return }
        done = true; loopTask?.cancel(); SoundManager.shared.error(); onFail()
    }
}

// MARK: - Color Switch art

private enum CSArt {
    static let backdrop = RadialGradient(colors: [Color(red: 0.18, green: 0.18, blue: 0.19), Color(red: 0.14, green: 0.14, blue: 0.15)],
                                         center: .center, startRadius: 40, endRadius: 520)

    /// The colour switcher: a small disc cut into one wedge per colour.
    static func switcher(_ ctx: GraphicsContext, at c: CGPoint, radius r: CGFloat, colors: [Color]) {
        let n = max(1, colors.count)
        for (i, col) in colors.enumerated() {
            var wedge = Path()
            wedge.move(to: c)
            wedge.addArc(center: c, radius: r, startAngle: .radians(-.pi / 2 + Double(i) / Double(n) * 2 * .pi),
                         endAngle: .radians(-.pi / 2 + Double(i + 1) / Double(n) * 2 * .pi), clockwise: false)
            wedge.closeSubpath()
            ctx.fill(wedge, with: .color(col))
        }
    }
}

/// The thin white score (rings cleared / quota) with a hairline clock under it while playing.
private struct CSScore: View {
    let passed: Int
    let total: Int
    let fraction: Double?
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 5 * scale) {
            HStack(alignment: .lastTextBaseline, spacing: 3 * scale) {
                Text("\(passed)").font(.system(size: 44 * scale, weight: .light, design: .rounded)).monospacedDigit()
                Text("/\(total)").font(.system(size: 18 * scale, weight: .regular, design: .rounded)).opacity(0.55)
            }
            .foregroundStyle(.white)
            if let f = fraction {
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule().fill(f < 0.3 ? Color(red: 0.98, green: 0.02, blue: 0.52) : .white.opacity(0.85))
                        .frame(width: 90 * max(0, min(1, f)))
                }
                .frame(width: 90, height: 3)
            }
        }
    }
}

/// The ball bursting into little coloured balls (once).
private struct CSBurst: View {
    let colors: [Color]
    let size: CGFloat
    @State private var go = false

    var body: some View {
        ZStack {
            ForEach(0..<22, id: \.self) { i in
                let a: Double = Double(i) / 22 * 2 * .pi + Double(i % 3) * 0.2
                let d: CGFloat = size * (1.6 + 0.9 * CGFloat(i % 4))
                let dot: CGFloat = size * (0.28 + 0.08 * CGFloat(i % 3))
                let dx: CGFloat = go ? CGFloat(cos(a)) * d : 0
                let dy: CGFloat = go ? CGFloat(sin(a)) * d + size * 0.8 : 0
                Circle()
                    .fill(colors[i % max(1, colors.count)])
                    .frame(width: dot, height: dot)
                    .offset(x: dx, y: dy)
                    .opacity(go ? 0 : 1)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.8)) { go = true } }
    }
}
