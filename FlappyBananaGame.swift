//
//  FlappyBananaGame.swift
//  A Banana Game
//
//  Reflex — a Flappy Bird homage. A winged banana falls under gravity; TAP ANYWHERE
//  to flap upward and thread the gaps between scrolling pipes. Clear the level's quota
//  of pipes to win; clip a pipe, the ceiling, or the ground and you fail back to level 1.
//  7 levels: the gap shrinks, the pipes come faster and closer, and the sky darkens from
//  a clear day to a red storm — by 6–7 it's a needle's eye.
//
//  Drawn as the original Flappy Bird: a flat teal sky over a cream cloud band, a pale city and
//  green bushes that never move, banded green pipes with dark outlines and wide lips, a tan
//  ground whose striped grass top scrolls with the pipes, and the white outlined pixel score.
//  The hero is a crescent banana with Flappy's big eye, orange lips and a flapping wing. The day
//  turns to sunset, dusk and Flappy's night city, then a rain storm with red pipes at 6–7.
//

import SwiftUI

enum FlappyBananaGame {
    static let definition = GameDefinition(
        id: "flappy-banana",
        title: "Banana Flutter",
        emoji: "🍌",
        genre: .reflex,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "A winged banana falls under gravity.",
                "Tap anywhere to flap upward and thread the gaps between the scrolling pipes.",
                "Clear the level's quota of pipes to win.",
                "Clip a pipe, the ceiling, or the ground and you're back to level 1.",
            ],
            bulletsVI: [
                "Quả chuối có cánh rơi theo trọng lực.",
                "Chạm bất kỳ đâu để vỗ cánh bay lên và luồn qua khe giữa các ống cuộn tới.",
                "Vượt đủ số ống của cấp để thắng.",
                "Chạm ống, trần, hoặc mặt đất sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(FlappyBananaView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct FlappyBananaView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    // MARK: Difficulty
    private var pipeSpeed: CGFloat { [0.34, 0.40, 0.46, 0.52, 0.58, 0.65, 0.72][min(level, 7) - 1] }
    private var gapHalf: CGFloat { [0.20, 0.175, 0.155, 0.14, 0.125, 0.11, 0.10][min(level, 7) - 1] }
    private var pipeSpacing: CGFloat { [0.62, 0.58, 0.54, 0.50, 0.47, 0.44, 0.42][min(level, 7) - 1] }
    private var target: Int { [4, 5, 6, 7, 8, 9, 10][min(level, 7) - 1] }

    // Layout / physics (all in play-area fractions).
    private let birdX: CGFloat = 0.28
    private let groundY: CGFloat = 0.88
    private let pipeWidth: CGFloat = 0.15
    private let birdHalfY: CGFloat = 0.05
    private let gravity: CGFloat = 2.8
    private let flapV: CGFloat = -0.95

    // MARK: State
    private struct Pipe: Identifiable { let id = UUID(); var x: CGFloat; let gapCenter: CGFloat; var passed = false }

    @State private var birdY: CGFloat = 0.42
    @State private var vy: CGFloat = 0
    @State private var pipes: [Pipe] = []
    @State private var score = 0
    @State private var done = false
    @State private var loopTask: Task<Void, Never>?
    @State private var demoGapIdx = 0      // demo: fixed gap sequence instead of random
    @State private var demoTapID = 0       // demo: bumps per flap → a fresh DemoTapRipple

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Sky, clouds, city and bushes never move in Flappy Bird: one static layer.
                FBBackdrop(level: level, size: geo.size).equatable()

                // Pipes, the scrolling ground, rain, the banana and the score: one Canvas.
                Canvas { ctx, size in
                    drawScene(ctx, size: size, now: Date().timeIntervalSinceReferenceDate)
                }

                // Demo: a ripple for each tap-anywhere flap.
                if isDemo && demoTapID > 0 {
                    DemoTapRipple().id(demoTapID).position(x: w * 0.72, y: h * 0.62)
                }
            }
            .frame(width: w, height: h)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { flap() }
        }
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
    }

    /// Everything that moves, drawn at the exact collision geometry: each pipe spans the field
    /// fraction `step()` tests, and the ground line is `groundY`.
    private func drawScene(_ ctx: GraphicsContext, size: CGSize, now: Double) {
        let w = size.width, h = size.height
        let pal = FBArt.palette(level)

        for p in pipes {
            let topH = max(0, p.gapCenter - gapHalf) * h
            let gapBot = (p.gapCenter + gapHalf) * h
            let botH = max(0, groundY * h - gapBot)
            FBArt.pipe(ctx, midX: p.x * w, top: 0, bottom: topH, width: pipeWidth * w, lipAtBottom: true, red: pal.redPipes)
            FBArt.pipe(ctx, midX: p.x * w, top: gapBot, bottom: gapBot + botH, width: pipeWidth * w, lipAtBottom: false, red: pal.redPipes)
        }

        // The grass stripes scroll at pipe speed; they stop with everything else when the run ends.
        FBArt.ground(ctx, size: size, top: groundY * h, scroll: CGFloat(now) * pipeSpeed * w, dim: pal.groundDim)
        if pal.rain { FBArt.rain(ctx, size: size, now: now) }

        let wing = done ? 1 : [0, 1, 2, 1][Int(now * 11) % 4]
        FBArt.bird(ctx, at: CGPoint(x: birdX * w, y: birdY * h), height: h * 0.09,
                   angle: .degrees(Double(max(-25, min(55, vy * 45)))), wing: wing)

        FBArt.score(ctx, score, of: target, midX: w / 2, top: h * 0.06, pixel: max(3, w * 0.0135))
    }

    // MARK: - Flow
    private func run() async {
        setup()
        var last = Date()
        loopTask = Task {
            while !Task.isCancelled && !done {
                try? await Task.sleep(for: .seconds(0.016))
                let now = Date()
                let dt = CGFloat(min(0.05, now.timeIntervalSince(last)))
                last = now
                step(dt: dt)
            }
        }
    }

    private func setup() {
        birdY = 0.42; vy = 0; score = 0; done = false
        pipes = [makePipe(at: 1.15)]
    }

    private func makePipe(at x: CGFloat) -> Pipe {
        if isDemo {
            defer { demoGapIdx += 1 }
            return Pipe(x: x, gapCenter: Self.demoGaps[demoGapIdx % Self.demoGaps.count])
        }
        let lo = gapHalf + 0.08
        let hi = groundY - gapHalf - 0.06
        return Pipe(x: x, gapCenter: CGFloat.random(in: lo...max(lo, hi)))
    }

    // MARK: - Demo (live manual clip)
    // Level 1 (4 pipes) on a fixed gap sequence, stepped at a fixed 1/60s through the real `step`.
    // Autopilot: tap (the real `flap`) whenever the banana sinks below the next gap's line (aimed a
    // touch under centre) while not already rising. Clears every pipe with ~7% of the field to
    // spare (checked offline); the 4th pipe is the real win().
    private static let demoGaps: [CGFloat] = [0.40, 0.58, 0.32, 0.55, 0.45]

    private func runDemo() async {
        let dt: CGFloat = 1.0 / 60.0
        while !Task.isCancelled {
            demoGapIdx = 0
            setup()
            try? await Task.sleep(for: .seconds(0.5))
            while !Task.isCancelled && !done {
                let next = pipes.filter { $0.x + pipeWidth / 2 + 0.03 > birdX }.min(by: { $0.x < $1.x })
                let aim = (next?.gapCenter ?? 0.45) + 0.07
                if birdY > aim && vy > 0 { flap(); demoTapID += 1 }
                step(dt: dt)
                try? await Task.sleep(for: .seconds(0.016))
            }
            // Pipe quota cleared → the real win() ran (onWin is a no-op). Hold, then loop.
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    private func step(dt: CGFloat) {
        guard !done else { return }
        vy += gravity * dt
        birdY += vy * dt

        for i in pipes.indices { pipes[i].x -= pipeSpeed * dt }

        // Spawn / cull.
        if let last = pipes.map(\.x).max(), last < 1.15 - pipeSpacing {
            pipes.append(makePipe(at: 1.15))
        }
        pipes.removeAll { $0.x < -0.25 }

        // Bounds.
        if birdY <= 0.02 { fail(); return }
        if birdY >= groundY - birdHalfY { fail(); return }

        // Scoring + pipe collision.
        for i in pipes.indices {
            if !pipes[i].passed && pipes[i].x < birdX {
                pipes[i].passed = true
                score += 1
                Haptics.tap(); SoundManager.shared.tap()
                if score >= target { win(); return }
            }
            if abs(pipes[i].x - birdX) < pipeWidth / 2 + 0.03 {
                if birdY - birdHalfY < pipes[i].gapCenter - gapHalf ||
                   birdY + birdHalfY > pipes[i].gapCenter + gapHalf { fail(); return }
            }
        }
    }

    private func flap() {
        guard !done else { return }
        vy = flapV
        Haptics.tap(); SoundManager.shared.tap()
    }

    private func win() {
        guard !done else { return }
        done = true
        loopTask?.cancel()
        onWin()
    }

    private func fail() {
        guard !done else { return }
        done = true
        loopTask?.cancel()
        SoundManager.shared.error()
        onFail()
    }
}

// MARK: - Flappy Bird art

private func fbRGB(_ r: Double, _ g: Double, _ b: Double) -> Color {
    Color(red: r / 255, green: g / 255, blue: b / 255)
}

/// One level's look. Day, late afternoon, sunset and dusk, then Flappy's night city and two storms.
private struct FBPalette {
    let skyTop: Color, skyBottom: Color
    let cloud: Color, cloudEdge: Color
    let city: Color, cityShade: Color, window: Color, litWindows: Bool
    let bush: Color, bushEdge: Color
    let stars: Bool, rain: Bool, redPipes: Bool
    let groundDim: Double
}

private enum FBArt {
    static let ink = fbRGB(84, 56, 71)

    static func palette(_ level: Int) -> FBPalette {
        switch min(max(level, 1), 7) {
        case 1:
            return FBPalette(skyTop: fbRGB(113, 197, 207), skyBottom: fbRGB(113, 197, 207),
                             cloud: fbRGB(234, 252, 219), cloudEdge: fbRGB(200, 235, 217),
                             city: fbRGB(219, 241, 201), cityShade: fbRGB(196, 230, 184), window: fbRGB(170, 222, 196), litWindows: false,
                             bush: fbRGB(132, 227, 140), bushEdge: fbRGB(104, 196, 124),
                             stars: false, rain: false, redPipes: false, groundDim: 0)
        case 2:
            return FBPalette(skyTop: fbRGB(98, 184, 206), skyBottom: fbRGB(168, 214, 204),
                             cloud: fbRGB(250, 245, 216), cloudEdge: fbRGB(226, 224, 198),
                             city: fbRGB(232, 232, 196), cityShade: fbRGB(214, 214, 178), window: fbRGB(196, 212, 176), litWindows: false,
                             bush: fbRGB(122, 214, 122), bushEdge: fbRGB(96, 184, 104),
                             stars: false, rain: false, redPipes: false, groundDim: 0)
        case 3:
            return FBPalette(skyTop: fbRGB(236, 118, 98), skyBottom: fbRGB(252, 196, 130),
                             cloud: fbRGB(255, 228, 198), cloudEdge: fbRGB(242, 192, 164),
                             city: fbRGB(218, 146, 134), cityShade: fbRGB(198, 124, 116), window: fbRGB(252, 214, 150), litWindows: true,
                             bush: fbRGB(106, 178, 108), bushEdge: fbRGB(80, 148, 90),
                             stars: false, rain: false, redPipes: false, groundDim: 0.05)
        case 4:
            return FBPalette(skyTop: fbRGB(64, 54, 118), skyBottom: fbRGB(194, 118, 150),
                             cloud: fbRGB(214, 164, 188), cloudEdge: fbRGB(176, 128, 162),
                             city: fbRGB(96, 80, 140), cityShade: fbRGB(80, 66, 122), window: fbRGB(250, 214, 122), litWindows: true,
                             bush: fbRGB(62, 132, 102), bushEdge: fbRGB(44, 102, 82),
                             stars: true, rain: false, redPipes: false, groundDim: 0.15)
        case 5:
            return FBPalette(skyTop: fbRGB(8, 58, 82), skyBottom: fbRGB(10, 122, 138),
                             cloud: fbRGB(24, 108, 124), cloudEdge: fbRGB(44, 132, 142),
                             city: fbRGB(12, 76, 92), cityShade: fbRGB(8, 62, 78), window: fbRGB(248, 214, 110), litWindows: true,
                             bush: fbRGB(26, 118, 86), bushEdge: fbRGB(16, 90, 68),
                             stars: true, rain: false, redPipes: false, groundDim: 0.25)
        case 6:
            return FBPalette(skyTop: fbRGB(24, 30, 42), skyBottom: fbRGB(64, 76, 90),
                             cloud: fbRGB(72, 84, 98), cloudEdge: fbRGB(94, 104, 116),
                             city: fbRGB(34, 42, 54), cityShade: fbRGB(26, 32, 44), window: fbRGB(232, 200, 122), litWindows: true,
                             bush: fbRGB(40, 74, 58), bushEdge: fbRGB(30, 56, 46),
                             stars: false, rain: true, redPipes: true, groundDim: 0.35)
        default:
            return FBPalette(skyTop: fbRGB(34, 6, 14), skyBottom: fbRGB(112, 26, 34),
                             cloud: fbRGB(94, 34, 42), cloudEdge: fbRGB(122, 50, 58),
                             city: fbRGB(48, 14, 22), cityShade: fbRGB(36, 10, 16), window: fbRGB(255, 124, 92), litWindows: true,
                             bush: fbRGB(60, 30, 28), bushEdge: fbRGB(44, 20, 18),
                             stars: false, rain: true, redPipes: true, groundDim: 0.42)
        }
    }

    // MARK: Pipes

    /// Flappy's banded pipe, highlights on the left and shade on the right (hard gradient stops).
    private static func bands(_ red: Bool) -> [Gradient.Stop] {
        let c: [Color] = red
            ? [fbRGB(250, 168, 112), fbRGB(255, 212, 166), fbRGB(240, 132, 84), fbRGB(206, 88, 48),
               fbRGB(232, 116, 72), fbRGB(214, 80, 40), fbRGB(150, 50, 22), fbRGB(154, 56, 26)]
            : [fbRGB(177, 236, 103), fbRGB(216, 250, 132), fbRGB(157, 231, 90), fbRGB(126, 201, 58),
               fbRGB(148, 223, 81), fbRGB(116, 192, 45), fbRGB(81, 127, 34), fbRGB(84, 120, 34)]
        let edges: [(CGFloat, CGFloat, Int)] = [(0, 0.06, 0), (0.06, 0.12, 1), (0.12, 0.26, 2), (0.26, 0.30, 3),
                                                (0.30, 0.36, 4), (0.36, 0.76, 5), (0.76, 0.80, 6), (0.80, 0.85, 5), (0.85, 1, 7)]
        var stops: [Gradient.Stop] = []
        for (a, b, i) in edges {
            stops.append(.init(color: c[i], location: a))
            stops.append(.init(color: c[i], location: b))
        }
        return stops
    }

    static func pipe(_ ctx: GraphicsContext, midX: CGFloat, top: CGFloat, bottom: CGFloat, width pw: CGFloat,
                     lipAtBottom: Bool, red: Bool) {
        guard bottom - top > 1 else { return }
        let outline = red ? fbRGB(92, 38, 40) : fbRGB(94, 73, 73)
        let shine = red ? fbRGB(255, 222, 176) : fbRGB(231, 255, 142)
        let lipW = pw * 1.1, lipH = min(bottom - top, pw * 0.46)
        let body = CGRect(x: midX - pw / 2, y: top, width: pw, height: bottom - top)
        let lip = CGRect(x: midX - lipW / 2, y: lipAtBottom ? bottom - lipH : top, width: lipW, height: lipH)
        let stops = bands(red)
        ctx.fill(Path(body), with: .linearGradient(Gradient(stops: stops), startPoint: CGPoint(x: body.minX, y: 0),
                                                   endPoint: CGPoint(x: body.maxX, y: 0)))
        ctx.stroke(Path(body.insetBy(dx: 1, dy: -2)), with: .color(outline), lineWidth: 2)
        ctx.fill(Path(lip), with: .linearGradient(Gradient(stops: stops), startPoint: CGPoint(x: lip.minX, y: 0),
                                                  endPoint: CGPoint(x: lip.maxX, y: 0)))
        // The light rim on the edge that faces the gap.
        let rimY = lipAtBottom ? lip.maxY - 5 : lip.minY + 2
        ctx.fill(Path(CGRect(x: lip.minX + 2, y: rimY, width: lip.width - 4, height: 3)), with: .color(shine.opacity(0.9)))
        ctx.stroke(Path(lip.insetBy(dx: 1, dy: 1)), with: .color(outline), lineWidth: 2)
    }

    // MARK: Ground

    static func ground(_ ctx: GraphicsContext, size: CGSize, top gy: CGFloat, scroll: CGFloat, dim: Double) {
        let w = size.width
        func d(_ c: Color) -> Color { dim > 0 ? c.mix(with: .black, by: dim) : c }
        let band = max(8, w * 0.028), period = max(14, w * 0.048)
        ctx.fill(Path(CGRect(x: 0, y: gy, width: w, height: size.height - gy)), with: .color(d(fbRGB(221, 216, 148))))
        ctx.fill(Path(CGRect(x: 0, y: gy, width: w, height: 2)), with: .color(fbRGB(84, 64, 64)))
        ctx.fill(Path(CGRect(x: 0, y: gy + 2, width: w, height: 2)), with: .color(d(fbRGB(217, 244, 132))))
        let by = gy + 4
        ctx.fill(Path(CGRect(x: 0, y: by, width: w, height: band)), with: .color(d(fbRGB(112, 190, 44))))
        var stripes = Path()
        var x = -(scroll.truncatingRemainder(dividingBy: period)) - period
        while x < w + period {
            stripes.move(to: CGPoint(x: x + band * 0.7, y: by))
            stripes.addLine(to: CGPoint(x: x + band * 0.7 + period * 0.5, y: by))
            stripes.addLine(to: CGPoint(x: x + period * 0.5, y: by + band))
            stripes.addLine(to: CGPoint(x: x, y: by + band))
            stripes.closeSubpath()
            x += period
        }
        ctx.fill(stripes, with: .color(d(fbRGB(155, 229, 87))))
        ctx.fill(Path(CGRect(x: 0, y: by + band, width: w, height: 2)), with: .color(d(fbRGB(93, 151, 39))))
        ctx.fill(Path(CGRect(x: 0, y: by + band + 2, width: w, height: 2)), with: .color(d(fbRGB(206, 170, 86))))
        // A soft darker floor so the sand doesn't read as a flat slab.
        ctx.fill(Path(CGRect(x: 0, y: size.height - 6, width: w, height: 6)), with: .color(d(fbRGB(200, 194, 128))))
    }

    static func hash(_ n: Double) -> Double {
        let v = sin(n * 12.9898) * 43758.5453
        return v - floor(v)
    }

    static func rain(_ ctx: GraphicsContext, size: CGSize, now: Double) {
        var p = Path()
        let h = Double(size.height), w = Double(size.width)
        for i in 0..<46 {
            let k = Double(i)
            let speed = h * (1.3 + hash(k + 7) * 0.5)
            let len = 10 + hash(k + 3) * 12
            let y = (hash(k) * h * 1.2 + now * speed).truncatingRemainder(dividingBy: h * 1.2) - h * 0.1
            let x = (hash(k + 11) * w * 1.2 - y * 0.22).truncatingRemainder(dividingBy: w * 1.2)
            let xx = x < 0 ? x + w * 1.2 : x
            p.move(to: CGPoint(x: xx, y: y))
            p.addLine(to: CGPoint(x: xx - len * 0.22, y: y + len))
        }
        ctx.stroke(p, with: .color(.white.opacity(0.32)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
    }

    // MARK: The banana

    /// A banana lying like a smile: stem at the back, a dark nub on the front tip, and Flappy's big
    /// eye, orange lips and flapping wing. `height` is the drawn height (`birdHalfY` is the hit box).
    static func bird(_ ctx: GraphicsContext, at c: CGPoint, height s: CGFloat, angle: Angle, wing: Int) {
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: angle)
        g.scaleBy(x: s, y: s)
        let lw: CGFloat = 0.055
        let stemBrown = fbRGB(150, 118, 52)

        // Stem at the back tip.
        var stem = Path()
        stem.move(to: CGPoint(x: -0.6, y: -0.3))
        stem.addQuadCurve(to: CGPoint(x: -0.8, y: -0.46), control: CGPoint(x: -0.74, y: -0.32))
        g.stroke(stem, with: .color(ink), style: StrokeStyle(lineWidth: 0.19, lineCap: .round))
        g.stroke(stem, with: .color(stemBrown), style: StrokeStyle(lineWidth: 0.1, lineCap: .round))
        g.fill(Path(ellipseIn: CGRect(x: -0.87, y: -0.53, width: 0.12, height: 0.12)), with: .color(fbRGB(74, 52, 30)))

        // Crescent body: both edges curve the same way, the tips curl up.
        var body = Path()
        body.move(to: CGPoint(x: -0.62, y: -0.26))
        body.addCurve(to: CGPoint(x: 0.6, y: -0.3), control1: CGPoint(x: -0.56, y: 0.64), control2: CGPoint(x: 0.52, y: 0.6))
        body.addCurve(to: CGPoint(x: -0.62, y: -0.26), control1: CGPoint(x: 0.36, y: -0.05), control2: CGPoint(x: -0.36, y: -0.03))
        body.closeSubpath()
        g.fill(body, with: .linearGradient(Gradient(colors: [fbRGB(255, 240, 128), fbRGB(255, 214, 58), fbRGB(236, 162, 22)]),
                                           startPoint: CGPoint(x: 0, y: -0.2), endPoint: CGPoint(x: 0, y: 0.4)))
        // The banana's side ridge, a highlight along the top and a few sugar spots.
        var ridge = Path()
        ridge.move(to: CGPoint(x: -0.52, y: -0.12))
        ridge.addCurve(to: CGPoint(x: 0.5, y: -0.16), control1: CGPoint(x: -0.44, y: 0.4), control2: CGPoint(x: 0.42, y: 0.38))
        g.stroke(ridge, with: .color(fbRGB(214, 138, 20).opacity(0.75)), style: StrokeStyle(lineWidth: 0.04, lineCap: .round))
        var shine = Path()
        shine.move(to: CGPoint(x: -0.42, y: -0.13))
        shine.addQuadCurve(to: CGPoint(x: 0.04, y: 0.06), control: CGPoint(x: -0.24, y: 0.06))
        g.stroke(shine, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 0.055, lineCap: .round))
        for (x, y, r) in [(-0.34, 0.2, 0.03), (-0.2, 0.3, 0.022), (0.02, 0.33, 0.026)] as [(CGFloat, CGFloat, CGFloat)] {
            g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(fbRGB(170, 108, 28).opacity(0.7)))
        }
        g.stroke(body, with: .color(ink), lineWidth: lw)
        g.fill(Path(ellipseIn: CGRect(x: 0.55, y: -0.36, width: 0.11, height: 0.11)), with: .color(fbRGB(74, 52, 30)))

        // Lips (upper light, lower dark), like the bird's.
        let upper = Path(roundedRect: CGRect(x: 0.36, y: -0.05, width: 0.36, height: 0.13), cornerRadius: 0.06)
        let lower = Path(roundedRect: CGRect(x: 0.33, y: 0.07, width: 0.31, height: 0.12), cornerRadius: 0.06)
        g.fill(lower, with: .color(fbRGB(226, 76, 28)))
        g.stroke(lower, with: .color(ink), lineWidth: lw * 0.8)
        g.fill(upper, with: .color(fbRGB(250, 128, 50)))
        g.stroke(upper, with: .color(ink), lineWidth: lw * 0.8)

        // Big eye with a tall pupil looking ahead.
        let eye = Path(ellipseIn: CGRect(x: 0.1, y: -0.3, width: 0.3, height: 0.3))
        g.fill(eye, with: .color(.white))
        g.stroke(eye, with: .color(ink), lineWidth: lw * 0.8)
        g.fill(Path(roundedRect: CGRect(x: 0.27, y: -0.23, width: 0.07, height: 0.15), cornerRadius: 0.03), with: .color(ink))

        // Wing: up, level, down.
        let tilt: Double = [-30, 0, 26][max(0, min(2, wing))]
        var wg = g
        wg.translateBy(x: -0.2, y: 0.14)
        wg.rotate(by: .degrees(tilt))
        let wingPath = Path(ellipseIn: CGRect(x: -0.25, y: -0.11, width: 0.4, height: 0.21))
        wg.fill(wingPath, with: .linearGradient(Gradient(colors: [fbRGB(255, 252, 238), fbRGB(242, 226, 190)]),
                                                startPoint: CGPoint(x: 0, y: -0.11), endPoint: CGPoint(x: 0, y: 0.1)))
        wg.stroke(wingPath, with: .color(ink), lineWidth: lw * 0.8)
    }

    // MARK: Pixel score

    /// Chunky 8-row digits with 2-pixel strokes, like Flappy's score font.
    private static let glyphs: [Character: [String]] = [
        "0": [".####.", "##..##", "##..##", "##..##", "##..##", "##..##", "##..##", ".####."],
        "1": [".##", "###", ".##", ".##", ".##", ".##", ".##", ".##"],
        "2": [".####.", "##..##", "....##", "...##.", "..##..", ".##...", "##....", "######"],
        "3": ["#####.", "....##", "....##", ".####.", "....##", "....##", "....##", "#####."],
        "4": ["...##.", "..###.", ".####.", "##.##.", "######", "...##.", "...##.", "...##."],
        "5": ["######", "##....", "##....", "#####.", "....##", "....##", "##..##", ".####."],
        "6": [".####.", "##....", "##....", "#####.", "##..##", "##..##", "##..##", ".####."],
        "7": ["######", "....##", "...##.", "...##.", "..##..", "..##..", ".##...", ".##..."],
        "8": [".####.", "##..##", "##..##", ".####.", "##..##", "##..##", "##..##", ".####."],
        "9": [".####.", "##..##", "##..##", "##..##", ".#####", "....##", "....##", ".####."],
        "/": ["....##", "...##.", "...##.", "..##..", "..##..", ".##...", ".##...", "##...."],
    ]

    private static func advance(_ text: String) -> CGFloat {
        CGFloat(text.reduce(0) { $0 + (glyphs[$1]?.first?.count ?? 6) + 1 } - 1)
    }

    /// Lit pixel rects of `text` (one pixel between glyphs) starting at `origin`.
    private static func pixels(_ text: String, origin: CGPoint, px: CGFloat) -> [CGRect] {
        var out: [CGRect] = []
        var x = origin.x
        for ch in text {
            guard let rows = glyphs[ch] else { continue }
            for (r, row) in rows.enumerated() {
                for (k, bit) in row.enumerated() where bit == "#" {
                    out.append(CGRect(x: x + CGFloat(k) * px, y: origin.y + CGFloat(r) * px, width: px, height: px))
                }
            }
            x += px * CGFloat((rows.first?.count ?? 6) + 1)
        }
        return out
    }

    /// White pixel digits with a thick dark outline, big score + small "/target".
    static func score(_ ctx: GraphicsContext, _ n: Int, of target: Int, midX: CGFloat, top: CGFloat, pixel px: CGFloat) {
        let big = "\(n)", small = "/\(target)"
        let sp = px * 0.55
        let bigW = advance(big) * px, smallW = advance(small) * sp
        let x0 = midX - (bigW + sp * 2 + smallW) / 2
        let lit = pixels(big, origin: CGPoint(x: x0, y: top), px: px)
            + pixels(small, origin: CGPoint(x: x0 + bigW + sp * 2, y: top + px * 8 - sp * 8), px: sp)
        var outline = Path(), fill = Path()
        for r in lit {
            outline.addRect(r.insetBy(dx: -px * 0.42, dy: -px * 0.42))
            fill.addRect(r.insetBy(dx: -0.15, dy: -0.15))
        }
        ctx.fill(outline, with: .color(fbRGB(40, 28, 34)))
        ctx.fill(fill, with: .color(.white))
    }
}

/// The part of Flappy's world that never moves: sky, stars, the cloud band, the city and bushes.
private struct FBBackdrop: View, Equatable {
    let level: Int
    let size: CGSize

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let pal = FBArt.palette(level)
            let groundY: CGFloat = 0.88 * h
            let cloudTop = groundY - h * 0.2, cityTop = groundY - h * 0.15, bushTop = groundY - h * 0.065

            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [pal.skyTop, pal.skyBottom]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: cloudTop + h * 0.05)))
            if pal.stars {
                for i in 0..<42 {
                    let k = Double(i)
                    let r = CGFloat(0.6 + FBArt.hash(k + 5) * 1.3)
                    let p = CGPoint(x: CGFloat(FBArt.hash(k)) * w, y: CGFloat(FBArt.hash(k + 2)) * cloudTop * 0.95)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                             with: .color(.white.opacity(0.35 + FBArt.hash(k + 9) * 0.5)))
                }
            }

            // Cloud band: a bumpy top, flat below.
            var clouds = Path()
            var x: CGFloat = -10
            var i = 0.0
            while x < w + 20 {
                let r = h * (0.028 + CGFloat(FBArt.hash(i + 31)) * 0.022)
                clouds.addEllipse(in: CGRect(x: x - r, y: cloudTop + h * 0.03 - r, width: r * 2, height: r * 2))
                x += r * 1.3
                i += 1
            }
            clouds.addRect(CGRect(x: 0, y: cloudTop + h * 0.03, width: w, height: groundY - cloudTop))
            ctx.fill(clouds, with: .color(pal.cloudEdge))
            ctx.translateBy(x: 0, y: 2)
            ctx.fill(clouds, with: .color(pal.cloud))
            ctx.translateBy(x: 0, y: -2)

            // City skyline with windows.
            x = 0
            i = 0
            while x < w {
                let bw = w * (0.06 + CGFloat(FBArt.hash(i + 51)) * 0.06)
                let bh = (bushTop - cityTop) * (0.45 + CGFloat(FBArt.hash(i + 71)) * 0.55) + h * 0.02
                let rect = CGRect(x: x, y: bushTop + h * 0.02 - bh, width: bw - 1, height: bh)
                ctx.fill(Path(rect), with: .color(Int(i) % 3 == 1 ? pal.cityShade : pal.city))
                let win = max(2.5, w * 0.009)
                var wy = rect.minY + win * 1.5
                var row = 0.0
                while wy < bushTop - win {
                    var wx = rect.minX + win
                    var col = 0.0
                    while wx < rect.maxX - win * 1.5 {
                        let lit = pal.litWindows && FBArt.hash(i * 17 + row * 5 + col) > 0.45
                        ctx.fill(Path(CGRect(x: wx, y: wy, width: win, height: win)),
                                 with: .color(pal.litWindows ? (lit ? pal.window : pal.cityShade.opacity(0.9)) : pal.window))
                        wx += win * 2
                        col += 1
                    }
                    wy += win * 2.2
                    row += 1
                }
                x += bw
                i += 1
            }

            // Bushes: a scalloped hedge down to the ground line.
            var bushes = Path()
            x = -6
            i = 0
            while x < w + 20 {
                let r = h * (0.022 + CGFloat(FBArt.hash(i + 91)) * 0.016)
                bushes.addEllipse(in: CGRect(x: x - r, y: bushTop + h * 0.02 - r, width: r * 2, height: r * 2))
                x += r * 1.25
                i += 1
            }
            bushes.addRect(CGRect(x: 0, y: bushTop + h * 0.02, width: w, height: groundY - bushTop))
            ctx.fill(bushes, with: .color(pal.bushEdge))
            ctx.translateBy(x: 0, y: 2)
            ctx.fill(bushes, with: .color(pal.bush))
        }
    }
}
