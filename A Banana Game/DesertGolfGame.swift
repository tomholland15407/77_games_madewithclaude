//
//  DesertGolfGame.swift
//  GOGs
//
//  Reflex — Desert Golf, after Desert Golfing: a minimalist side-view course of flat-shaded sand
//  under a flat pastel sky. Drag back from anywhere like a slingshot (the dotted line shows aim and
//  power), let go to shoot, and sink every hole of the level within its stroke budget. The ball
//  bounces low and rolls in the sand; the hole is a real notch in the ground, so a fast ball can
//  skip right over it. Leaving the course costs a penalty stroke. Run out of strokes, or time, and
//  it's back to level 1.
//
//  Every hole is generated and then VERIFIED with the game's own deterministic physics: a shot
//  search must find a robust hole-in-one (its neighbouring angles/powers sink too), so even the
//  near-impossible budgets are fair. Built during the countdown via `BoardCache`. The palette slides
//  from midday to night as the levels climb.
//

import SwiftUI

enum DesertGolfGame {
    static let definition = GameDefinition(
        id: "desert-golf",
        title: "Sunset Putt",
        emoji: "🍌",
        genre: .reflex,
        levelCount: 7,
        locksFeed: true,
        manual: GameManual(
            bullets: [
                "Drag back anywhere to aim, like a slingshot; the dotted line shows direction and power.",
                "Let go to shoot, then sink the ball in the hole.",
                "Clear every hole of the level within the stroke budget; leaving the course costs a stroke.",
                "Run out of strokes, or time, and you're back to level 1.",
            ],
            bulletsVI: [
                "Kéo ngược ở bất kỳ đâu để nhắm như ná cao su; đường chấm cho thấy hướng và lực.",
                "Thả tay để đánh, rồi đưa bóng vào lỗ.",
                "Hoàn thành mọi lỗ của cấp trong số gậy cho phép; bóng ra ngoài sân bị phạt một gậy.",
                "Hết gậy, hoặc hết giờ, bạn về lại cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(DesertGolfView(level: level, onWin: onWin, onFail: onFail))
        },
        prefetch: { level in DesertGolfView(level: level, onWin: {}, onFail: {}).prefetchCourse() }
    )
}

// MARK: - Physics & course

/// One hole. Units: the play area's width is 1.0; y points UP from the bottom edge.
nonisolated struct DGHole: Sendable {
    var xs: [Double]
    var ys: [Double]
    var teeX: Double
    var teeY: Double          // ground height at the tee
    var cupL: Double
    var cupR: Double
    var lipY: Double          // green height at the cup
    var floorY: Double        // cup bottom
}

nonisolated struct DGBall: Sendable {
    var x: Double, y: Double
    var vx = 0.0, vy = 0.0
    var rest = 0.0
    var time = 0.0
}

nonisolated enum DGOutcome: Sendable { case moving, rest, sunk, out }

nonisolated enum DGPhysics {
    static let r = 0.013
    static let g = 1.8
    static let vmax = 1.7
    static let dt = 1.0 / 60

    /// One fixed 1/60 s frame (8 substeps) of flight/rolling against the course polyline.
    static func step(_ b: inout DGBall, _ h: DGHole) -> DGOutcome {
        let sub = 8
        let hs = dt / Double(sub)
        var contact = false
        var slope = 0.0
        var wedged = false
        for _ in 0..<sub {
            b.vy -= g * hs
            b.x += b.vx * hs
            b.y += b.vy * hs
            var touched = false
            var loNx = 9.0, hiNx = -9.0     // the sideways lean of the ground pushing on the ball this substep
            for i in 0..<(h.xs.count - 1) {
                let x0 = h.xs[i], x1 = h.xs[i + 1]
                if max(x0, x1) < b.x - r || min(x0, x1) > b.x + r { continue }
                let y0 = h.ys[i], y1 = h.ys[i + 1]
                let dx = x1 - x0, dy = y1 - y0
                let len2 = dx * dx + dy * dy
                var t = len2 > 0 ? ((b.x - x0) * dx + (b.y - y0) * dy) / len2 : 0
                t = min(max(t, 0), 1)
                let cx = x0 + t * dx, cy = y0 + t * dy
                var nx = b.x - cx, ny = b.y - cy
                let d = (nx * nx + ny * ny).squareRoot()
                guard d < r else { continue }
                if d > 1e-9 { nx /= d; ny /= d } else {
                    let l = len2.squareRoot(); nx = -dy / l; ny = dx / l
                }
                b.x = cx + nx * r
                b.y = cy + ny * r
                let vn = b.vx * nx + b.vy * ny
                if vn < 0 {
                    // Sand: a low bounce on hard hits, none on soft ones, plus impact drag.
                    let e = vn < -0.35 ? 0.32 : 0.0
                    b.vx -= (1 + e) * vn * nx
                    b.vy -= (1 + e) * vn * ny
                    let tx = -ny, ty = nx
                    let vt = b.vx * tx + b.vy * ty
                    let loss = min(1, 0.3 * -vn / max(abs(vt), 1e-6))
                    b.vx -= tx * vt * loss
                    b.vy -= ty * vt * loss
                }
                touched = true
                if abs(dx) > 1e-9 { slope = abs(dy / dx) } else { slope = 99 }
                if ny > -0.05 { loNx = min(loNx, nx); hiNx = max(hiNx, nx) }
            }
            // Held from both sides (the two walls of a crack, or the floor and the foot of a wall): gravity
            // can't roll it out. A ball tipping over one edge (a ridge, the cup's lip) pushes against a
            // single point, so its normals agree and it isn't wedged.
            if hiNx - loNx > 0.2 && loNx < 0.05 && hiNx > -0.05 { wedged = true }
            if touched {
                contact = true
                let k = 1 - 1.5 * hs          // rolling resistance in sand
                b.vx *= k
                b.vy *= k
            }
        }
        b.time += dt
        let speed = (b.vx * b.vx + b.vy * b.vy).squareRoot()

        // In the cup below the lip and slow enough: holed.
        if b.x > h.cupL && b.x < h.cupR && b.y < h.lipY && speed < 0.9 { return .sunk }
        if b.x < -0.03 || b.x > 1.03 { return .out }
        // Static friction: a slow ball on a gentle slope stops. A slow ball wedged in a crack or against
        // the foot of a wall is at rest too (it used to jiggle there until the 9 s cap, ignoring drags).
        if contact && speed < 0.035 && (slope < 0.5 || wedged) {
            if slope < 0.5 { b.vx = 0; b.vy = 0 }
            b.rest += dt
            if b.rest > 0.3 { return .rest }
        } else {
            b.rest = 0
        }
        if b.time > 9 { return .rest }
        return .moving
    }

    static func launch(from h: DGHole, x: Double, y: Double, angle: Double, power: Double) -> DGBall {
        let v = vmax * min(max(power, 0), 1)
        return DGBall(x: x, y: y, vx: cos(angle) * v, vy: sin(angle) * v)
    }

    static func simulate(_ h: DGHole, x: Double, y: Double, angle: Double, power: Double) -> DGOutcome {
        var b = launch(from: h, x: x, y: y, angle: angle, power: power)
        while true {
            let o = step(&b, h)
            if o != .moving { return o }
        }
    }
}

nonisolated enum DGGen {
    struct Params: Sendable {
        let cupRange: ClosedRange<Double>
        let amp: Double
        let features: Int       // 0 none, 1 mound, 2 mound/wall/plateau, 3 + pits & fall-offs
    }

    /// A shot (angle, power) that sinks the hole AND keeps sinking under small nudges.
    static func robustShot(_ h: DGHole, deterministic: Bool = false) -> (angle: Double, power: Double)? {
        let x = h.teeX, y = h.teeY + DGPhysics.r
        var angles = Array(stride(from: 10.0, through: 80.0, by: 2.0))
        var powers = Array(stride(from: 0.2, through: 1.0, by: 0.04))
        if !deterministic { angles.shuffle(); powers.shuffle() }
        for a in angles {
            for p in powers where DGPhysics.simulate(h, x: x, y: y, angle: a * .pi / 180, power: p) == .sunk {
                let nudges = [(a - 1, p), (a + 1, p), (a, p - 0.02), (a, p + 0.02)]
                let ok = nudges.filter { DGPhysics.simulate(h, x: x, y: y, angle: $0.0 * .pi / 180, power: $0.1) == .sunk }.count
                if ok >= 2 { return (a * .pi / 180, p) }
            }
        }
        return nil
    }

    static func hole(_ p: Params) -> DGHole {
        for _ in 0..<40 {
            let h = build(p)
            if robustShot(h) != nil { return h }
        }
        return fallback()
    }

    static func build(_ p: Params) -> DGHole {
        let teeX = Double.random(in: 0.08...0.13)
        let teeY = Double.random(in: 0.2...0.36)
        let cupX = Double.random(in: p.cupRange)
        let cupW = 0.05, depth = 0.032
        var greenY = Double.random(in: 0.18...0.4)

        var xs: [Double] = [-0.06, teeX + 0.055]
        var ys: [Double] = [teeY, teeY]
        // Rolling middle ground.
        let startX = teeX + 0.1, endX = cupX - 0.13
        let n = max(2, Int((endX - startX) / 0.075))
        var feature = -1
        if p.features >= 1 && n >= 3 { feature = Int.random(in: 1..<(n - 1)) }
        let kind = p.features >= 2 ? Int.random(in: 0..<3) : 0   // 0 mound, 1 wall, 2 raised green
        if p.features >= 2 && kind == 2 { greenY = min(0.52, greenY + Double.random(in: 0.08...0.16)) }
        for k in 0..<n {
            let f = Double(k) / Double(max(1, n - 1))
            let x = startX + (endX - startX) * f
            // Random relief fades out toward the tee and the green so both sit on level ground.
            var y = teeY + (greenY - teeY) * f + Double.random(in: -p.amp...p.amp) * sin(.pi * min(1, 0.15 + f * 0.85))
            if k == feature {
                if kind == 1 {
                    // A near-vertical wall: two close vertices, the far one tall.
                    xs.append(x); ys.append(max(0.08, y))
                    y = min(0.62, max(y, greenY) + Double.random(in: 0.12...0.2))
                    xs.append(x + 0.012); ys.append(y)
                    continue
                }
                y = min(0.62, max(y, teeY, greenY) + Double.random(in: 0.08...0.16) + p.amp * 0.5)
            }
            if p.features >= 3 && k == n - 1 && Bool.random() {
                y = max(0.06, greenY - Double.random(in: 0.08...0.15))     // a pit in front of the green
            }
            xs.append(x); ys.append(min(0.62, max(0.06, y)))
        }
        // Green with the cup notch.
        xs += [cupX - 0.1, cupX - cupW / 2, cupX - cupW / 2, cupX + cupW / 2, cupX + cupW / 2, cupX + 0.09]
        ys += [greenY, greenY, greenY - depth, greenY - depth, greenY, greenY]
        // Beyond the hole: a backstop on easy holes, flat or falling away on hard ones.
        let behind: Double = p.features <= 1 ? Double.random(in: 0.06...0.14) : (p.features == 2 ? 0 : -Double.random(in: 0.05...0.12))
        var x = cupX + 0.16
        while x < 1.08 {
            xs.append(x)
            ys.append(min(0.66, max(0.05, greenY + behind * ((x - cupX) / 0.3) + Double.random(in: -0.02...0.02))))
            x += 0.08
        }
        xs.append(1.12); ys.append(ys.last ?? greenY)
        return DGHole(xs: xs, ys: ys, teeX: teeX, teeY: teeY, cupL: cupX - cupW / 2, cupR: cupX + cupW / 2,
                      lipY: greenY, floorY: greenY - depth)
    }

    /// A gentle known-good hole (never needed in practice; the verifier almost always succeeds).
    static func fallback() -> DGHole {
        let xs = [-0.06, 0.18, 0.3, 0.45, 0.55, 0.575, 0.575, 0.625, 0.625, 0.7, 0.85, 1.12]
        let ys = [0.3, 0.3, 0.26, 0.24, 0.24, 0.24, 0.208, 0.208, 0.24, 0.24, 0.32, 0.36]
        return DGHole(xs: xs, ys: ys, teeX: 0.11, teeY: 0.3, cupL: 0.575, cupR: 0.625, lipY: 0.24, floorY: 0.208)
    }

    static func course(_ p: Params, holes: Int) -> [DGHole] { (0..<holes).map { _ in hole(p) } }
}

// MARK: - View

struct DesertGolfView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void
    @Environment(\.isDemo) private var isDemo

    private var holes: Int { [2, 3, 3, 4, 4, 5, 5][min(level, 7) - 1] }
    private var budget: Int { [6, 8, 7, 8, 7, 7, 6][min(level, 7) - 1] }
    private var timeLimit: Double { Double(holes) * 26 + 20 }
    private var params: DGGen.Params {
        [DGGen.Params(cupRange: 0.55...0.7, amp: 0.04, features: 0),
         DGGen.Params(cupRange: 0.6...0.8, amp: 0.06, features: 1),
         DGGen.Params(cupRange: 0.65...0.85, amp: 0.08, features: 1),
         DGGen.Params(cupRange: 0.7...0.88, amp: 0.1, features: 2),
         DGGen.Params(cupRange: 0.72...0.9, amp: 0.12, features: 2),
         DGGen.Params(cupRange: 0.75...0.92, amp: 0.14, features: 3),
         DGGen.Params(cupRange: 0.78...0.93, amp: 0.16, features: 3)][min(level, 7) - 1]
    }
    /// Midday → dusk → night, like the original's slowly shifting desert.
    private var palette: (sky: Color, sand: Color, ink: Color) {
        [(Color(red: 0.78, green: 0.86, blue: 0.9), Color(red: 0.87, green: 0.63, blue: 0.36), Color(red: 0.3, green: 0.22, blue: 0.16)),
         (Color(red: 0.82, green: 0.86, blue: 0.86), Color(red: 0.85, green: 0.6, blue: 0.35), Color(red: 0.3, green: 0.22, blue: 0.16)),
         (Color(red: 0.89, green: 0.84, blue: 0.76), Color(red: 0.8, green: 0.54, blue: 0.32), Color(red: 0.3, green: 0.2, blue: 0.14)),
         (Color(red: 0.95, green: 0.78, blue: 0.62), Color(red: 0.74, green: 0.47, blue: 0.3), Color(red: 0.32, green: 0.18, blue: 0.12)),
         (Color(red: 0.86, green: 0.62, blue: 0.57), Color(red: 0.64, green: 0.4, blue: 0.34), Color(red: 0.28, green: 0.14, blue: 0.12)),
         (Color(red: 0.52, green: 0.49, blue: 0.66), Color(red: 0.52, green: 0.36, blue: 0.42), Color(white: 0.96)),
         (Color(red: 0.25, green: 0.29, blue: 0.47), Color(red: 0.4, green: 0.31, blue: 0.44), Color(white: 0.96))][min(level, 7) - 1]
    }

    private enum Phase { case loading, aim, flying, sinking, sliding, won, done }

    @State private var phase: Phase = .loading
    @State private var course: [DGHole] = []
    @State private var index = 0
    @State private var ball = DGBall(x: 0.1, y: 0.3)
    @State private var lastRest = (x: 0.1, y: 0.3)
    @State private var strokes = 0
    @State private var aim: (angle: Double, power: Double)? = nil
    @State private var slide = 0.0               // 0…1 while panning to the next hole
    @State private var sinkT = 0.0
    @State private var flash = 0.0               // out-of-bounds flash
    @State private var size: CGSize = .zero
    @State private var timeLeft = 0.0
    @State private var demoFinger: CGPoint? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                palette.sky
                Canvas { ctx, s in draw(ctx, s) }
                hud
            }
            .contentShape(Rectangle())
            .gesture(shotGesture, including: isDemo ? .none : .all)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
    }

    private var hud: some View {
        VStack(spacing: 6) {
            if !isDemo {
                GeometryReader { g in
                    let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.ink.opacity(0.15))
                        Capsule().fill(frac < 0.3 ? .red : palette.ink.opacity(0.7)).frame(width: g.size.width * frac)
                    }
                }
                .frame(height: 5)
                .padding(.horizontal, 40)
            }
            HStack(alignment: .top) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(strokes)")
                        .font(.system(size: isDemo ? 34 : 54, weight: .heavy, design: .rounded))
                        .contentTransition(.numericText())
                    Text("/\(budget)")
                        .font(.system(size: isDemo ? 15 : 22, weight: .bold, design: .rounded))
                        .opacity(0.6)
                }
                Spacer()
                HStack(spacing: 5) {
                    ForEach(0..<max(course.count, 1), id: \.self) { i in
                        Circle()
                            .fill(i < index ? palette.ink.opacity(0.8) : palette.ink.opacity(0.18))
                            .frame(width: isDemo ? 8 : 10, height: isDemo ? 8 : 10)
                    }
                }
                .padding(.top, isDemo ? 10 : 16)
            }
            .foregroundStyle(palette.ink)
            .padding(.horizontal, isDemo ? 12 : 20)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, isDemo ? 4 : 10)
        .allowsHitTesting(false)
    }

    // MARK: Drawing

    /// How far the course is raised off the bottom edge, in widths. The sand below is room to pull the
    /// slingshot back (a full pull is 0.34 widths), so a tall play area gets about half a width, the
    /// near-square demo card a little, and anything wider than 5:4 none.
    private func lift(_ s: CGSize) -> Double {
        guard s.width > 0 else { return 0 }
        return min(0.55, max(0, (Double(s.height / s.width) - 0.8) * 0.5))
    }

    private func screen(_ x: Double, _ y: Double, _ s: CGSize, shift: Double = 0) -> CGPoint {
        CGPoint(x: (x + shift) * s.width, y: s.height - (y + lift(s)) * s.width)
    }

    private func draw(_ ctx: GraphicsContext, _ s: CGSize) {
        guard !course.isEmpty, index < course.count || phase == .won else { return }
        let u = s.width
        // While sliding, the finished hole pans out left and the next one comes in from the right.
        if phase == .sliding, index > 0 {
            drawHole(ctx, course[index - 1], s, shift: -slide)
            if index < course.count { drawHole(ctx, course[index], s, shift: 1 - slide) }
            return
        }
        let hi = min(index, course.count - 1)
        drawHole(ctx, course[hi], s, shift: 0)

        // Aim line: dotted, from the ball, length = power.
        if phase == .aim, let a = aim, a.power > 0.02 {
            let p0 = screen(ball.x, ball.y, s)
            let len = CGFloat(0.06 + 0.2 * a.power) * u
            var line = Path()
            line.move(to: p0)
            line.addLine(to: CGPoint(x: p0.x + CGFloat(cos(a.angle)) * len, y: p0.y - CGFloat(sin(a.angle)) * len))
            ctx.stroke(line, with: .color(.white.opacity(0.9)),
                       style: StrokeStyle(lineWidth: max(2, u * 0.007), lineCap: .round, dash: [0.1, u * 0.02]))
        }

        // Ball (off the top? show a marker at the edge instead).
        if phase != .won {
            let r = CGFloat(DGPhysics.r) * u
            var p = screen(ball.x, ball.y, s)
            if phase == .sinking {
                let h = course[hi]
                p = screen((h.cupL + h.cupR) / 2, h.floorY + DGPhysics.r * (1 - min(1, sinkT / 0.25)), s)
            }
            if p.y < -r {
                var tri = Path()
                tri.move(to: CGPoint(x: p.x, y: 4)); tri.addLine(to: CGPoint(x: p.x - 6, y: 14)); tri.addLine(to: CGPoint(x: p.x + 6, y: 14))
                tri.closeSubpath()
                ctx.fill(tri, with: .color(.white))
            } else {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(.white))
            }
        }
        if flash > 0 {
            ctx.fill(Path(CGRect(origin: .zero, size: s)), with: .color(.white.opacity(flash * 0.5)))
        }

        if let f = demoFinger {
            var hand = ctx.resolve(Image(systemName: "hand.point.up.left.fill"))
            hand.shading = .color(.white)
            var hc = ctx
            hc.addFilter(.shadow(color: .black.opacity(0.5), radius: 3))
            let w = u * 0.11
            hc.draw(hand, in: CGRect(x: f.x - w * 0.28, y: f.y - w * 0.08, width: w, height: w))
        }
    }

    private func drawHole(_ ctx: GraphicsContext, _ h: DGHole, _ s: CGSize, shift: Double) {
        let u = s.width
        // The sand runs down past the bottom edge, however high the course is raised.
        var ground = Path()
        ground.move(to: CGPoint(x: screen(h.xs[0], 0, s, shift: shift).x, y: s.height + 2))
        for i in h.xs.indices { ground.addLine(to: screen(h.xs[i], h.ys[i], s, shift: shift)) }
        ground.addLine(to: CGPoint(x: screen(h.xs[h.xs.count - 1], 0, s, shift: shift).x, y: s.height + 2))
        ground.closeSubpath()
        ctx.fill(ground, with: .color(palette.sand))

        // Flag: a thin pole from the cup floor and a small pennant.
        let cx = (h.cupL + h.cupR) / 2
        let base = screen(cx, h.floorY, s, shift: shift)
        let top = screen(cx, h.lipY + 0.12, s, shift: shift)
        var pole = Path()
        pole.move(to: base); pole.addLine(to: top)
        ctx.stroke(pole, with: .color(palette.ink.opacity(0.85)), lineWidth: max(1.5, u * 0.004))
        var flag = Path()
        flag.move(to: top)
        flag.addLine(to: CGPoint(x: top.x + u * 0.05, y: top.y + u * 0.017))
        flag.addLine(to: CGPoint(x: top.x, y: top.y + u * 0.034))
        flag.closeSubpath()
        ctx.fill(flag, with: .color(Color(red: 0.9, green: 0.28, blue: 0.2)))
    }

    // MARK: Input

    private var shotGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard phase == .aim, size.width > 0 else { return }
                // Pull back: the shot flies opposite the drag.
                let dx = Double(v.startLocation.x - v.location.x)
                let dy = Double(v.location.y - v.startLocation.y)      // screen y is down; world y is up
                let len = (dx * dx + dy * dy).squareRoot()
                let power = min(1, len / Double(size.width * 0.34))
                aim = (atan2(dy, dx), power)
            }
            .onEnded { _ in shoot() }
    }

    private func shoot() {
        guard phase == .aim, let a = aim, a.power > 0.06, index < course.count else { aim = nil; return }
        ball = DGPhysics.launch(from: course[index], x: ball.x, y: ball.y, angle: a.angle, power: a.power)
        strokes += 1
        aim = nil
        phase = .flying
        SoundManager.shared.tap(); Haptics.tap()
    }

    // MARK: Flow

    func prefetchCourse() {
        let p = params, n = holes
        BoardCache.prefetch(boardKey) { DGGen.course(p, holes: n) }
    }
    private var boardKey: String { BoardCache.key("desert-golf", level: level) }

    private func placeOnTee() {
        guard index < course.count else { return }
        let h = course[index]
        ball = DGBall(x: h.teeX, y: h.teeY + DGPhysics.r)
        lastRest = (ball.x, ball.y)
    }

    /// Advances one fixed physics frame; returns true when the level should end (win/fail decided).
    private func tick() -> Bool {
        switch phase {
        case .flying:
            let o = DGPhysics.step(&ball, course[index])
            switch o {
            case .moving: break
            case .sunk:
                phase = .sinking; sinkT = 0
                SoundManager.shared.tap(); Haptics.success()
            case .rest:
                lastRest = (ball.x, ball.y)
                if strokes >= budget { fail(); return true }
                phase = .aim
            case .out:
                strokes += 1          // penalty, back to where it last rested
                flash = 1
                ball = DGBall(x: lastRest.x, y: lastRest.y)
                SoundManager.shared.error()
                if strokes >= budget { fail(); return true }
                phase = .aim
            }
        case .sinking:
            sinkT += DGPhysics.dt
            if sinkT > 0.55 {
                index += 1
                if index >= course.count { phase = .won; return false }
                phase = .sliding; slide = 0
            }
        case .sliding:
            slide = min(1, slide + DGPhysics.dt / 0.6)
            if slide >= 1 { placeOnTee(); phase = .aim }
        default:
            break
        }
        flash = max(0, flash - DGPhysics.dt * 3)
        return false
    }

    private func run() async {
        let p = params, n = holes
        let t0 = Date()
        let built = await BoardCache.take(boardKey) { DGGen.course(p, holes: n) }
        guard !Task.isCancelled else { return }
        await BoardCache.holdBrainstorm(since: t0, minimum: 0.5)
        guard !Task.isCancelled else { return }
        course = built
        index = 0
        strokes = 0
        placeOnTee()
        phase = .aim
        timeLeft = timeLimit
        let start = Date()
        var last = Date()
        var acc = 0.0
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1.0 / 60))
            let now = Date()
            acc += min(0.1, now.timeIntervalSince(last))
            last = now
            while acc >= DGPhysics.dt {
                acc -= DGPhysics.dt
                if tick() { return }
            }
            if phase == .won {
                try? await Task.sleep(for: .seconds(0.4))
                guard !Task.isCancelled else { return }
                phase = .done
                onWin()
                return
            }
            if phase == .done { return }
            timeLeft = max(0, timeLimit - now.timeIntervalSince(start))
            if timeLeft <= 0 { fail(); return }
        }
    }

    private func fail() {
        guard phase != .done && phase != .won else { return }
        phase = .done
        SoundManager.shared.error()
        onFail()
    }

    // MARK: - Demo (live manual clip)
    // A fixed level-1 hole. The shot is found at runtime by the same robust-shot search the
    // generator uses (deterministic order, lowest arc preferred), so it's guaranteed to drop: the
    // finger pulls back from the ball like a slingshot, the dotted aim line grows, it lets go, and
    // the ball lands on the green and rolls into the cup — a hole-in-one through the real physics.
    private nonisolated static let demoHole = DGHole(
        xs: [-0.06, 0.17, 0.26, 0.36, 0.46, 0.55, 0.6, 0.675, 0.675, 0.725, 0.725, 0.8, 0.9, 1.12],
        ys: [0.3, 0.3, 0.27, 0.33, 0.28, 0.24, 0.23, 0.23, 0.198, 0.198, 0.23, 0.23, 0.3, 0.34],
        teeX: 0.11, teeY: 0.3, cupL: 0.675, cupR: 0.725, lipY: 0.23, floorY: 0.198)

    /// Found offline with `demoShot()` (release build): 20°, power 0.57 — robust to ±1° / ±0.01.
    private nonisolated static let demoKnownShot = (angle: 20.0 * .pi / 180, power: 0.57)

    /// The known shot if it still sinks here (one quick sim), else a fresh search.
    private nonisolated static func verifiedDemoShot() -> (angle: Double, power: Double) {
        let h = demoHole, k = demoKnownShot
        if DGPhysics.simulate(h, x: h.teeX, y: h.teeY + DGPhysics.r, angle: k.angle, power: k.power) == .sunk { return k }
        return demoShot()
    }

    private nonisolated static func demoShot() -> (angle: Double, power: Double) {
        let h = demoHole
        let x = h.teeX, y = h.teeY + DGPhysics.r
        var best: (angle: Double, power: Double, apex: Double)? = nil
        for a in stride(from: 20.0, through: 60.0, by: 1.0) {
            for p in stride(from: 0.3, through: 0.9, by: 0.01)
            where DGPhysics.simulate(h, x: x, y: y, angle: a * .pi / 180, power: p) == .sunk {
                let nudged = [(a - 1, p), (a + 1, p), (a, p - 0.01), (a, p + 0.01)].filter {
                    DGPhysics.simulate(h, x: x, y: y, angle: $0.0 * .pi / 180, power: $0.1) == .sunk
                }.count
                guard nudged >= 3 else { continue }
                let v = DGPhysics.vmax * p * sin(a * .pi / 180)
                let apex = v * v / (2 * DGPhysics.g)
                if best == nil || apex < best!.apex { best = (a * .pi / 180, p, apex) }
            }
        }
        return best.map { ($0.angle, $0.power) } ?? (0.8, 0.6)
    }

    private func runDemo() async {
        while size.width == 0 && !Task.isCancelled { try? await Task.sleep(for: .seconds(0.02)) }
        course = [Self.demoHole]
        index = 0
        placeOnTee()
        phase = .aim
        let shot = await Task.detached(priority: .userInitiated) { Self.verifiedDemoShot() }.value
        while !Task.isCancelled {
            course = [Self.demoHole]
            index = 0
            strokes = 0
            placeOnTee()
            phase = .aim
            aim = nil
            demoFinger = nil
            try? await Task.sleep(for: .seconds(0.6))
            // Drag back (a slingshot can start anywhere): from mid-screen, opposite the shot direction.
            let s = size
            let start = screen(ball.x + 0.3, ball.y - 0.02, s)
            let pull = CGFloat(shot.power) * s.width * 0.34
            let end = CGPoint(x: start.x - CGFloat(cos(shot.angle)) * pull, y: start.y + CGFloat(sin(shot.angle)) * pull)
            demoFinger = start
            try? await Task.sleep(for: .seconds(0.25))
            for k in 1...30 {
                guard !Task.isCancelled else { return }
                let t = Double(k) / 30
                let e = CGFloat(1 - pow(1 - t, 2))
                demoFinger = CGPoint(x: start.x + (end.x - start.x) * e, y: start.y + (end.y - start.y) * e)
                aim = (shot.angle, shot.power * t)
                try? await Task.sleep(for: .seconds(1.0 / 50))
            }
            aim = shot
            try? await Task.sleep(for: .seconds(0.3))
            shoot()
            demoFinger = nil
            for _ in 0..<600 where !Task.isCancelled && phase != .won {
                if phase == .aim { break }          // (a miss would rest here; the verified shot never does)
                _ = tick()
                try? await Task.sleep(for: .seconds(1.0 / 60))
            }
            try? await Task.sleep(for: .seconds(1.4))
        }
    }
}
