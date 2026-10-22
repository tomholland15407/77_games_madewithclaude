//
//  LineConnectGame.swift
//  A Banana Game
//
//  Visual Memory — Line Connect. Obstacles flash inside a square canvas, then
//  vanish; trace a freeform line from the 🍌 start (left edge) to the goal (right
//  edge) without touching a hidden obstacle. Touch one → fail; reach the goal →
//  win; run out of time → fail. Drag game → locksFeed.
//

import SwiftUI

enum LineConnectGame {
    static let definition = GameDefinition(
        id: "line-connect", title: "Line Connect", emoji: "🍌",
        genre: .brain, levelCount: 7, locksFeed: true,
        manual: GameManual(
            bullets: [
                "Mines flash in the field, then vanish — memorize them.",
                "Drag a freeform line from the 🍌 on the left to the flag on the right.",
                "Touch a hidden mine, or run out of time, and you're back to level 1.",
            ],
            bulletsVI: [
                "Mìn nhấp nháy trên cánh đồng rồi biến mất — hãy ghi nhớ chúng.",
                "Kéo một đường tự do từ 🍌 bên trái đến lá cờ bên phải.",
                "Chạm phải một quả mìn ẩn, hoặc hết giờ, sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(LineConnectView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct LineConnectView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    /// An obstacle, stored in fractional coordinates (0…1) of the square canvas.
    private struct Obstacle: Identifiable {
        let id = UUID()
        var pos: CGPoint
    }

    // MARK: Difficulty (derived from level)
    private var obstacleCount: Int { 1 + level }                     // L1: 2 → L7: 8
    private var obstacleRadiusFrac: CGFloat { 0.05 + CGFloat(level) * 0.006 }
    private var peekTime: Double { max(0.6, 2.8 - Double(level) * 0.32) }
    private var timeLimit: Double { max(3.0, 8.0 - Double(level) * 0.6) }

    // Endpoints live on the left/right edges of the canvas (fractions of it).
    private let startFrac = CGPoint(x: 0.06, y: 0.5)
    private let goalFrac  = CGPoint(x: 0.94, y: 0.5)
    private let endpointRadiusFrac: CGFloat = 0.07

    private enum Phase { case peek, play, done }
    @State private var phase: Phase = .peek
    @State private var obstacles: [Obstacle] = []
    @State private var startY: CGFloat = 0.5
    @State private var goalY: CGFloat = 0.5
    @State private var pathPoints: [CGPoint] = []   // actual points traced
    @State private var armed = false
    @State private var revealObstacles = true
    @State private var timeLeft = 0.0
    @State private var demoPathFrac: [CGPoint] = []   // fractional trace for the manual demo
    // Presentation only: the mine that went off (fractional position) and when.
    private struct Boom { let at: CGPoint; let t0: Date }
    @State private var boom: Boom? = nil

    var body: some View {
        GeometryReader { geo in
            // A centered square canvas keeps the drawing area tight (harder) and
            // gives collision math a single, uniform coordinate space.
            let side = min(geo.size.width, geo.size.height) * 0.86
            let ox = (geo.size.width - side) / 2
            let oy = (geo.size.height - side) / 2
            let obR = obstacleRadiusFrac * side
            let epR = endpointRadiusFrac * side
            let startPt = actual(CGPoint(x: startFrac.x, y: startY), ox, oy, side)
            let goalPt  = actual(CGPoint(x: goalFrac.x, y: goalY), ox, oy, side)
            let tracePts = isDemo ? demoPathFrac.map { actual($0, ox, oy, side) } : pathPoints

            ZStack {
                MinefieldGround(field: CGRect(x: ox, y: oy, width: side, height: side)).equatable()

                TimelineView(.animation(paused: !(revealObstacles || boom != nil))) { tl in
                    Canvas { ctx, _ in
                        MineArt.trail(ctx, tracePts, width: max(8, side * 0.045))
                        MineArt.finish(ctx, at: goalPt, r: epR)
                        MineArt.banana(ctx, at: startPt, size: epR * 1.9)
                        if revealObstacles {
                            let blink = Int(tl.date.timeIntervalSinceReferenceDate * 4) % 2 == 0
                            for ob in obstacles {
                                MineArt.mine(ctx, at: actual(ob.pos, ox, oy, side), r: obR, lit: blink)
                            }
                        }
                        if let b = boom {
                            MineArt.explosion(ctx, at: actual(b.at, ox, oy, side), r: obR * 2.2,
                                              t: tl.date.timeIntervalSince(b.t0))
                        }
                        if isDemo, let f = tracePts.last, phase == .play {
                            var hand = ctx.resolve(Image(systemName: "hand.point.up.left.fill"))
                            hand.shading = .color(.white)
                            var h = ctx
                            h.addFilter(.shadow(color: .black.opacity(0.6), radius: 3))
                            let hw = epR * 1.5
                            h.draw(hand, in: CGRect(x: f.x - hw * 0.28, y: f.y - hw * 0.06, width: hw, height: hw))
                        }
                    }
                }

                if !isDemo {
                    timeBar.frame(height: 6).padding(.horizontal, 48)
                        .frame(maxHeight: .infinity, alignment: .top).padding(.top, 10)
                }

                // Peek phase only: a status chip while the mines are showing.
                if phase == .peek {
                    Text(L("MEMORIZE", "GHI NHỚ"))
                        .font(.system(size: isDemo ? 14 : 17, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(Color(red: 0.2, green: 0.12, blue: 0.02))
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Color(red: 1, green: 0.84, blue: 0.2), in: Capsule())
                        .overlay(Capsule().stroke(Color(red: 0.25, green: 0.15, blue: 0.02), lineWidth: 2))
                        .position(x: geo.size.width / 2,
                                  y: isDemo ? oy + side - 14 : oy + side + (geo.size.height - oy - side) / 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard phase == .play else { return }
                        let p = value.location
                        if !armed {
                            if dist(p, startPt) <= epR * 1.4 {
                                armed = true
                                pathPoints = [startPt, p]
                            }
                            return
                        }
                        // Leaving the canvas cancels the attempt (no unfair fail).
                        if p.x < ox || p.x > ox + side || p.y < oy || p.y > oy + side {
                            armed = false; pathPoints = []; return
                        }
                        pathPoints.append(p)
                        for ob in obstacles where dist(p, actual(ob.pos, ox, oy, side)) <= obR {
                            boom = Boom(at: ob.pos, t0: Date())
                            fail(); return
                        }
                        if dist(p, goalPt) <= epR { win() }
                    }
                    .onEnded { _ in
                        guard phase == .play else { return }
                        armed = false; pathPoints = []
                    }
            )
        }
        .background(Color(red: 0.12, green: 0.2, blue: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
    }
    // MARK: - Demo (live manual clip)

    /// Flash a fixed middle cluster of blocks, hide them, then trace a memorized arc
    /// up and over them from the 🍌 to the goal. The trace is fractional so it maps
    /// onto whatever canvas size the manual card provides.
    private func runDemo() async {
        let route: [CGPoint] = [
            CGPoint(x: 0.06, y: 0.5), CGPoint(x: 0.14, y: 0.36), CGPoint(x: 0.28, y: 0.22),
            CGPoint(x: 0.50, y: 0.18), CGPoint(x: 0.72, y: 0.22), CGPoint(x: 0.86, y: 0.36),
            CGPoint(x: 0.94, y: 0.5),
        ]
        while !Task.isCancelled {
            startY = 0.5; goalY = 0.5
            obstacles = demoObstacles()
            demoPathFrac = []
            revealObstacles = true
            boom = nil
            phase = .peek
            try? await Task.sleep(for: .seconds(peekTime))       // flash the blocks
            guard !Task.isCancelled else { return }
            revealObstacles = false
            phase = .play
            timeLeft = timeLimit
            try? await Task.sleep(for: .seconds(0.4))
            for pt in route {
                guard !Task.isCancelled else { return }
                withAnimation(.linear(duration: 0.12)) { demoPathFrac.append(pt) }
                try? await Task.sleep(for: .seconds(0.16))
            }
            win()                                                // reached the goal
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    /// A fixed central cluster the arc clears — no edge walls (so the route has room).
    private func demoObstacles() -> [Obstacle] {
        [CGPoint(x: 0.40, y: 0.50), CGPoint(x: 0.50, y: 0.50), CGPoint(x: 0.60, y: 0.50),
         CGPoint(x: 0.50, y: 0.38), CGPoint(x: 0.50, y: 0.62)].map { Obstacle(pos: $0) }
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let fraction = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(fraction < 0.3 ? .red : BananaTheme.banana)
                    .frame(width: geo.size.width * max(0, fraction))
            }
        }
    }

    // MARK: - Flow

    private func run() async {
        phase = .peek
        revealObstacles = true
        boom = nil
        armed = false
        pathPoints = []
        startY = CGFloat.random(in: 0.25...0.75)
        goalY = CGFloat.random(in: 0.25...0.75)
        obstacles = makeObstacles()
        try? await Task.sleep(for: .seconds(peekTime))
        guard phase == .peek else { return }
        revealObstacles = false
        phase = .play

        // The countdown timer lives inside this structured task, so it's cancelled
        // automatically when the page recreates/removes the view — no orphaned
        // timer can survive to fire a spurious fail during the next countdown.
        timeLeft = timeLimit
        let start = Date()
        while !Task.isCancelled && phase == .play {
            try? await Task.sleep(for: .seconds(0.05))
            timeLeft = max(0, timeLimit - Date().timeIntervalSince(start))
            if timeLeft <= 0 { fail(); break }
        }
    }

    /// Place obstacles spaced apart and clear of both endpoints, so the player
    /// is never failed by a block sitting right on the start of their path.
    private func makeObstacles() -> [Obstacle] {
        var result: [Obstacle] = []
        let start = CGPoint(x: startFrac.x, y: startY)
        let goal = CGPoint(x: goalFrac.x, y: goalY)
        let minGap = obstacleRadiusFrac * 2 + 0.04
        let endpointClear = obstacleRadiusFrac + endpointRadiusFrac + 0.06
        var attempts = 0
        while result.count < obstacleCount && attempts < 500 {
            attempts += 1
            let cand = CGPoint(x: CGFloat.random(in: 0.2...0.8),
                               y: CGFloat.random(in: 0.12...0.88))
            if dist(cand, start) < endpointClear + 0.06 { continue }
            if dist(cand, goal) < endpointClear + 0.06 { continue }
            if result.contains(where: { dist($0.pos, cand) < minGap }) { continue }
            result.append(Obstacle(pos: cand))
        }

        // Wall off the top and bottom edges with an overlapping row of dots spanning corner to
        // corner. This kills the cheap trick of tracing straight along an edge to dodge every
        // hidden block — with both edges sealed the only route is through the middle, so the
        // player must actually remember and thread the interior obstacles. (Endpoints sit at
        // mid-height, so these edge walls never block the start or goal.)
        let step = obstacleRadiusFrac * 1.5      // < 2r → the dots overlap into a solid barrier
        for yEdge in [CGFloat(0.06), CGFloat(0.94)] {
            var x: CGFloat = 0.04
            while x <= 0.96 {
                let cand = CGPoint(x: x, y: yEdge)
                x += step
                if dist(cand, start) < endpointClear { continue }
                if dist(cand, goal) < endpointClear { continue }
                result.append(Obstacle(pos: cand))
            }
        }
        return result
    }

    private func win() {
        guard phase == .play else { return }
        phase = .done
        Haptics.tap(); SoundManager.shared.tap()
        onWin()
    }

    private func fail() {
        guard phase == .play else { return }
        phase = .done
        revealObstacles = true
        SoundManager.shared.error()
        onFail()
    }

    private func actual(_ f: CGPoint, _ ox: CGFloat, _ oy: CGFloat, _ side: CGFloat) -> CGPoint {
        CGPoint(x: ox + f.x * side, y: oy + f.y * side)
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}

// MARK: - Minefield art

/// A roped-off patch of mown grass: landmines with blinking lights (only while they're showing),
/// a dusty footpath trail, the banana at the start and a checkered flag at the finish.
private enum MineArt {
    static func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    private static func disc(_ p: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }

    /// An anti-personnel mine from above: olive casing, ribbed plate, pressure cap and a red LED.
    static func mine(_ ctx: GraphicsContext, at p: CGPoint, r: CGFloat, lit: Bool) {
        ctx.fill(disc(CGPoint(x: p.x + r * 0.12, y: p.y + r * 0.18), r), with: .color(.black.opacity(0.3)))
        ctx.fill(disc(p, r), with: .radialGradient(Gradient(colors: [c(0.5, 0.52, 0.34), c(0.3, 0.32, 0.2), c(0.2, 0.21, 0.13)]),
                                                  center: CGPoint(x: p.x - r * 0.3, y: p.y - r * 0.35), startRadius: 0, endRadius: r * 1.3))
        ctx.stroke(disc(p, r), with: .color(c(0.1, 0.11, 0.06)), lineWidth: max(1, r * 0.1))
        for k in 0..<8 {
            let a = Double(k) / 8 * 2 * .pi
            var rib = Path()
            rib.move(to: CGPoint(x: p.x + CGFloat(cos(a)) * r * 0.45, y: p.y + CGFloat(sin(a)) * r * 0.45))
            rib.addLine(to: CGPoint(x: p.x + CGFloat(cos(a)) * r * 0.82, y: p.y + CGFloat(sin(a)) * r * 0.82))
            ctx.stroke(rib, with: .color(c(0.15, 0.16, 0.1).opacity(0.7)), lineWidth: max(0.8, r * 0.07))
        }
        ctx.fill(disc(p, r * 0.36), with: .radialGradient(Gradient(colors: [c(0.62, 0.64, 0.6), c(0.3, 0.31, 0.28)]),
                                                         center: CGPoint(x: p.x - r * 0.1, y: p.y - r * 0.1), startRadius: 0, endRadius: r * 0.4))
        let led = CGPoint(x: p.x + r * 0.5, y: p.y - r * 0.5)
        if lit {
            ctx.fill(disc(led, r * 0.5), with: .radialGradient(Gradient(colors: [c(1, 0.2, 0.15).opacity(0.8), c(1, 0.2, 0.15).opacity(0)]),
                                                              center: led, startRadius: 0, endRadius: r * 0.5))
        }
        ctx.fill(disc(led, r * 0.16), with: .color(lit ? c(1, 0.3, 0.25) : c(0.5, 0.08, 0.06)))
    }

    /// The path the player traced: a dusty dirt trail with a scuffed centre.
    static func trail(_ ctx: GraphicsContext, _ pts: [CGPoint], width w: CGFloat) {
        guard let first = pts.first, pts.count > 1 else { return }
        var p = Path()
        p.move(to: first)
        for q in pts.dropFirst() { p.addLine(to: q) }
        ctx.stroke(p, with: .color(c(0.36, 0.26, 0.14).opacity(0.75)), style: StrokeStyle(lineWidth: w * 1.25, lineCap: .round, lineJoin: .round))
        ctx.stroke(p, with: .color(c(0.82, 0.68, 0.44)), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        ctx.stroke(p, with: .color(c(0.66, 0.52, 0.32)), style: StrokeStyle(lineWidth: w * 0.3, lineCap: .round, lineJoin: .round,
                                                                           dash: [w * 0.5, w * 0.7]))
    }

    /// The finish: a chalk ring on the grass with a checkered flag planted in it.
    static func finish(_ ctx: GraphicsContext, at p: CGPoint, r: CGFloat) {
        ctx.fill(disc(p, r), with: .color(.white.opacity(0.18)))
        ctx.stroke(disc(p, r), with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: max(2, r * 0.12), dash: [r * 0.35, r * 0.2]))
        let base = CGPoint(x: p.x - r * 0.1, y: p.y + r * 0.35)
        let poleTop = CGPoint(x: base.x, y: base.y - r * 1.9)
        ctx.fill(Path(ellipseIn: CGRect(x: base.x - r * 0.3, y: base.y - r * 0.08, width: r * 0.6, height: r * 0.18)), with: .color(.black.opacity(0.3)))
        var pole = Path()
        pole.move(to: base); pole.addLine(to: poleTop)
        ctx.stroke(pole, with: .color(c(0.3, 0.3, 0.32)), style: StrokeStyle(lineWidth: max(1.5, r * 0.12), lineCap: .round))
        let fw = r * 1.2, fh = r * 0.8
        let n = 4, m = 3
        for i in 0..<n {
            for j in 0..<m {
                let x0 = poleTop.x + fw * CGFloat(i) / CGFloat(n), x1 = poleTop.x + fw * CGFloat(i + 1) / CGFloat(n)
                let wave0 = CGFloat(sin(Double(i) * 0.9)) * fh * 0.08, wave1 = CGFloat(sin(Double(i + 1) * 0.9)) * fh * 0.08
                let y0 = poleTop.y + fh * CGFloat(j) / CGFloat(m), y1 = poleTop.y + fh * CGFloat(j + 1) / CGFloat(m)
                var cell = Path()
                cell.move(to: CGPoint(x: x0, y: y0 + wave0)); cell.addLine(to: CGPoint(x: x1, y: y0 + wave1))
                cell.addLine(to: CGPoint(x: x1, y: y1 + wave1)); cell.addLine(to: CGPoint(x: x0, y: y1 + wave0))
                cell.closeSubpath()
                ctx.fill(cell, with: .color((i + j) % 2 == 0 ? .white : c(0.1, 0.1, 0.12)))
            }
        }
        ctx.fill(disc(poleTop, max(1.5, r * 0.1)), with: .color(c(0.95, 0.8, 0.25)))
    }

    /// The banana waiting at the start.
    static func banana(_ ctx: GraphicsContext, at c0: CGPoint, size s: CGFloat) {
        ctx.fill(Path(ellipseIn: CGRect(x: c0.x - s * 0.4, y: c0.y + s * 0.12, width: s * 0.8, height: s * 0.22)), with: .color(.black.opacity(0.3)))
        var p = Path()
        p.move(to: CGPoint(x: c0.x - s * 0.1, y: c0.y - s * 0.46))
        p.addQuadCurve(to: CGPoint(x: c0.x - s * 0.08, y: c0.y + s * 0.3), control: CGPoint(x: c0.x - s * 0.52, y: c0.y - s * 0.05))
        p.addQuadCurve(to: CGPoint(x: c0.x - s * 0.1, y: c0.y - s * 0.46), control: CGPoint(x: c0.x + s * 0.48, y: c0.y))
        p.closeSubpath()
        ctx.fill(p, with: .linearGradient(Gradient(colors: [c(1, 0.95, 0.5), c(1, 0.84, 0.2), c(0.86, 0.62, 0.08)]),
                                          startPoint: CGPoint(x: c0.x - s * 0.3, y: c0.y), endPoint: CGPoint(x: c0.x + s * 0.3, y: c0.y)))
        ctx.stroke(p, with: .color(c(0.45, 0.3, 0.05)), lineWidth: max(1, s * 0.04))
        ctx.fill(Path(roundedRect: CGRect(x: c0.x - s * 0.15, y: c0.y - s * 0.56, width: s * 0.1, height: s * 0.14), cornerRadius: s * 0.02),
                 with: .color(c(0.42, 0.28, 0.1)))
    }

    /// A mine going off: fireball, dirt clods and smoke.
    static func explosion(_ ctx: GraphicsContext, at p: CGPoint, r: CGFloat, t: Double) {
        guard t >= 0, t < 1.2 else { return }
        for k in 0..<6 {
            let a = Double(k) * 1.05 + 0.2
            let q = CGPoint(x: p.x + CGFloat(cos(a)) * r * CGFloat(0.3 + t), y: p.y + CGFloat(sin(a)) * r * CGFloat(0.3 + t) - CGFloat(t) * r * 0.6)
            ctx.fill(disc(q, r * CGFloat(0.35 + t * 0.6)), with: .color(Color(white: 0.3).opacity(max(0, 0.55 - t * 0.45))))
        }
        if t < 0.5 {
            let k = t / 0.5
            ctx.fill(disc(p, r * CGFloat(0.5 + k)), with: .radialGradient(Gradient(colors: [.white, c(1, 0.85, 0.3), c(1, 0.4, 0.1), c(0.8, 0.1, 0).opacity(0)]),
                                                                         center: p, startRadius: 0, endRadius: r * CGFloat(0.5 + k)))
        }
        for k in 0..<8 {
            let a = Double(k) * 0.785
            let d = r * CGFloat(0.4 + t * 2.4)
            let q = CGPoint(x: p.x + CGFloat(cos(a)) * d, y: p.y + CGFloat(sin(a)) * d + CGFloat(t * t) * r * 1.5)
            let s = r * 0.14 * CGFloat(max(0, 1 - t / 1.2))
            ctx.fill(disc(q, s), with: .color(c(0.36, 0.24, 0.12)))
        }
    }
}

/// The field (static): mown grass in stripes inside a rope fence on posts, dark scrub outside.
private struct MinefieldGround: View, Equatable {
    let field: CGRect

    var body: some View {
        Canvas { ctx, s in
            ctx.fill(Path(CGRect(origin: .zero, size: s)),
                     with: .radialGradient(Gradient(colors: [MineArt.c(0.2, 0.3, 0.14), MineArt.c(0.08, 0.13, 0.06)]),
                                           center: CGPoint(x: s.width / 2, y: s.height / 2), startRadius: 0, endRadius: max(s.width, s.height) * 0.7))
            let f = field
            ctx.fill(Path(roundedRect: f, cornerRadius: 6),
                     with: .linearGradient(Gradient(colors: [MineArt.c(0.46, 0.68, 0.28), MineArt.c(0.36, 0.58, 0.22)]),
                                           startPoint: CGPoint(x: f.minX, y: f.minY), endPoint: CGPoint(x: f.maxX, y: f.maxY)))
            var g = ctx
            g.clip(to: Path(roundedRect: f, cornerRadius: 6))
            let band = f.width / 8
            for k in 0..<8 where k % 2 == 0 {
                g.fill(Path(CGRect(x: f.minX + CGFloat(k) * band, y: f.minY, width: band, height: f.height)),
                       with: .color(.white.opacity(0.06)))
            }
            for k in 0..<50 {
                let hx = CGFloat((sin(Double(k) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)).magnitude
                let hy = CGFloat((sin(Double(k) * 78.233) * 24634.6345).truncatingRemainder(dividingBy: 1)).magnitude
                let p = CGPoint(x: f.minX + hx * f.width, y: f.minY + hy * f.height)
                var tuft = Path()
                for d in [-1.0, 0.0, 1.0] {
                    tuft.move(to: p)
                    tuft.addLine(to: CGPoint(x: p.x + CGFloat(d) * 2.5, y: p.y - 5))
                }
                g.stroke(tuft, with: .color(MineArt.c(0.24, 0.44, 0.14).opacity(0.8)), lineWidth: 1.2)
                if k % 9 == 0 {
                    g.fill(Path(ellipseIn: CGRect(x: p.x + 4, y: p.y - 3, width: 4, height: 4)),
                           with: .color(k % 2 == 0 ? .white.opacity(0.9) : MineArt.c(1, 0.85, 0.3)))
                }
            }
            // Rope fence on wooden posts, just outside the field.
            let fence = f.insetBy(dx: -8, dy: -8)
            ctx.stroke(Path(roundedRect: fence, cornerRadius: 8), with: .color(MineArt.c(0.85, 0.72, 0.45)),
                       style: StrokeStyle(lineWidth: 2.5, dash: [9, 4]))
            let posts = 6
            for i in 0...posts {
                for p in [CGPoint(x: fence.minX + fence.width * CGFloat(i) / CGFloat(posts), y: fence.minY),
                          CGPoint(x: fence.minX + fence.width * CGFloat(i) / CGFloat(posts), y: fence.maxY),
                          CGPoint(x: fence.minX, y: fence.minY + fence.height * CGFloat(i) / CGFloat(posts)),
                          CGPoint(x: fence.maxX, y: fence.minY + fence.height * CGFloat(i) / CGFloat(posts))] {
                    ctx.fill(Path(roundedRect: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6), cornerRadius: 1.5),
                             with: .color(MineArt.c(0.45, 0.3, 0.16)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
