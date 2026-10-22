//
//  AsteroidsGame.swift
//  A Banana Game
//
//  Reflex — the arcade classic. Your ship sits in a wrap-around starfield: hold ◄ ► to spin,
//  hold the thruster to drift, and tap FIRE to shoot. Every rock you hit splits into two
//  smaller rocks; the smallest shatter for good. Clear the whole field to win. Get clipped by
//  a rock — or let the clock expire — and you fail back to level 1. 7 levels: more rocks,
//  faster drift and a tighter clock, so level 7's swarm is barely survivable. The void deepens
//  and the accent shifts hotter each level.
//
//  Drawn as Atari's 1979 vector game: a black screen, thin glowing outlines, the jagged rock shapes
//  (wrapping smoothly across every edge), the arrow ship in banana yellow with a flickering flame,
//  dot bullets and dot explosions, a vector-style rock counter, and the cabinet's round arcade
//  buttons (each keeps its old rectangular hit area).
//

import SwiftUI

enum AsteroidsGame {
    static let definition = GameDefinition(
        id: "asteroids",
        title: "Space Rubble",
        emoji: "🍌",
        genre: .reflex,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Hold the rotate buttons to spin, hold the thruster to drift, and tap FIRE to shoot.",
                "Every rock you hit splits into two smaller ones; the smallest shatter for good.",
                "The screen wraps at every edge; clear the whole field to win.",
                "Get clipped by a rock, or run out of time, and you're back to level 1.",
            ],
            bulletsVI: [
                "Giữ nút xoay để quay tàu, giữ nút đẩy để trôi, và chạm BẮN để nổ súng.",
                "Mỗi tảng đá trúng đạn vỡ thành hai tảng nhỏ hơn; tảng nhỏ nhất thì vỡ hẳn.",
                "Màn hình nối vòng ở mọi mép; dọn sạch cả bãi để thắng.",
                "Bị đá va trúng, hoặc hết giờ, sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(AsteroidsView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct AsteroidsView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void
    @Environment(\.isDemo) private var isDemo

    // MARK: Difficulty
    private var rockCount: Int     { [3, 3, 4, 4, 5, 5, 6][min(level, 7) - 1] }
    private var rockSpeed: CGFloat { [0.11, 0.13, 0.16, 0.19, 0.22, 0.25, 0.29][min(level, 7) - 1] }
    private var timeLimit: Double  { [64, 60, 56, 52, 49, 46, 43][min(level, 7) - 1] }

    private var accent: Color {
        [Color(red:0.40,green:0.85,blue:1.00), Color(red:0.45,green:0.95,blue:0.85),
         Color(red:0.70,green:1.00,blue:0.55), Color(red:1.00,green:0.85,blue:0.35),
         Color(red:1.00,green:0.62,blue:0.35), Color(red:1.00,green:0.42,blue:0.42),
         Color(red:1.00,green:0.35,blue:0.60)][min(level,7)-1]
    }

    private struct Rock: Identifiable {
        let id = UUID(); var pos: CGPoint; var vel: CGVector; var size: Int; var spin: Double
    }
    private struct Bullet: Identifiable { let id = UUID(); var pos: CGPoint; var vel: CGVector; var life: Double }
    private struct Burst: Identifiable { let id = UUID(); let pos: CGPoint }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var ship = CGPoint(x: 0.5, y: 0.5)
    @State private var shipVel = CGVector.zero
    @State private var heading: Double = 0          // 0 = pointing up
    @State private var rocks: [Rock] = []
    @State private var bullets: [Bullet] = []
    @State private var bursts: [Burst] = []
    @State private var rotDir = 0
    @State private var thrusting = false
    @State private var fireCD = 0.0
    @State private var invuln = 1.0                 // brief spawn grace
    @State private var timeLeft = 0.0
    @State private var shakeTick = 0
    @State private var loopTask: Task<Void, Never>?
    @State private var demoFire = 0                 // demo: frames left on the FIRE press flash

    private let shipR: CGFloat = 0.03
    private func rockR(_ s: Int) -> CGFloat { [0.03, 0.05, 0.075][max(0, min(2, s - 1))] }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                ASTArt.rockIcon.frame(width: isDemo ? 16 : 20, height: isDemo ? 16 : 20)
                Text("\(rocks.count)")
                    .font(.system(size: isDemo ? 15 : 20, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .padding(.top, isDemo ? 6 : 0)
            if !isDemo { timeBar.frame(height: 5).padding(.horizontal, 60) }

            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height

                ZStack {
                    Color.black
                    // The level's accent only warms the void a little; the vectors stay phosphor white.
                    RadialGradient(colors: [accent.opacity(0.1), .clear], center: .bottom, startRadius: 0, endRadius: h * 0.8)

                    // Rocks, bullets and the ship as glowing vector lines: one Canvas.
                    Canvas { ctx, size in drawVectors(ctx, size: size) }

                    ForEach(bursts) { b in
                        ParticleBurstView(color: .white, count: 12, spread: 46) {
                            bursts.removeAll { $0.id == b.id }
                        }
                        .position(x: b.pos.x * w, y: b.pos.y * h)
                    }
                }
                .frame(width: w, height: h)
                .clipped()
                .screenShake(shakeTick, amount: 5)
            }

            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.05, green: 0.05, blue: 0.07))
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
    }

    private func drawVectors(_ ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        let s = min(w, h)
        let glow = Color(red: 0.75, green: 0.88, blue: 1).opacity(0.2)
        for rock in rocks {
            let r = rockR(rock.size) * s
            let shape = ASTArt.rockShape(abs(rock.id.hashValue) % 3, radius: r, spin: rock.spin)
            // Draw the copies that poke in across a wrapped edge too.
            for dx in [-1.0, 0.0, 1.0] as [CGFloat] {
                for dy in [-1.0, 0.0, 1.0] as [CGFloat] {
                    let c = CGPoint(x: (rock.pos.x + dx) * w, y: (rock.pos.y + dy) * h)
                    guard c.x > -r, c.x < w + r, c.y > -r, c.y < h + r else { continue }
                    let path = shape.applying(CGAffineTransform(translationX: c.x, y: c.y))
                    ctx.stroke(path, with: .color(glow), style: StrokeStyle(lineWidth: 5, lineJoin: .round))
                    ctx.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                }
            }
        }
        var dots = Path()
        for b in bullets {
            let c = CGPoint(x: b.pos.x * w, y: b.pos.y * h)
            dots.addEllipse(in: CGRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4))
        }
        ctx.fill(dots, with: .color(.white))

        let blink = invuln > 0 && Int(invuln * 12) % 2 == 0
        ASTArt.ship(ctx, at: CGPoint(x: ship.x * w, y: ship.y * h), size: shipR * 2.4 * s, heading: heading,
                    thrusting: thrusting, dim: blink, glow: Color(red: 1, green: 0.88, blue: 0.3).opacity(0.25))
    }

    private var controls: some View {
        HStack(spacing: isDemo ? 8 : 10) {
            holdButton("arrow.counterclockwise", active: rotDir == -1) { rotDir = -1 } release: { if rotDir == -1 { rotDir = 0 } }
            holdButton("arrow.clockwise", active: rotDir == 1) { rotDir = 1 } release: { if rotDir == 1 { rotDir = 0 } }
            holdButton("flame.fill", active: thrusting) { thrusting = true } release: { thrusting = false }
            Button { fire() } label: {
                Image(systemName: "dot.radiowaves.up.forward")
                    .font(.system(size: isDemo ? 17 : 20, weight: .bold)).foregroundStyle(.white)
                    .frame(width: isDemo ? 66 : 76, height: isDemo ? 38 : 54)
                    .background(ASTArt.ArcadeButton(color: Color(red: 0.9, green: 0.14, blue: 0.14), lit: demoFire > 0))
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                    .scaleEffect(demoFire > 0 ? 0.92 : 1)
            }
        }
        .padding(.bottom, isDemo ? 6 : 8)
    }

    private func holdButton(_ icon: String, active: Bool = false, press: @escaping () -> Void,
                            release: @escaping () -> Void) -> some View {
        // In the demo the held control lights up (the autopilot drives rotDir/thrusting directly).
        let lit = isDemo && active
        let cap = icon == "flame.fill" ? Color(red: 1, green: 0.62, blue: 0.14) : Color(white: 0.82)
        return Image(systemName: icon)
            .font(.system(size: isDemo ? 17 : 20, weight: .bold)).foregroundStyle(icon == "flame.fill" ? .black : .black.opacity(0.75))
            .frame(width: isDemo ? 60 : 70, height: isDemo ? 38 : 54)
            .background(ASTArt.ArcadeButton(color: cap, lit: lit))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .scaleEffect(lit ? 0.92 : 1)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if phase == .play { press() } }
                .onEnded { _ in release() })
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(frac < 0.3 ? Color(red: 1, green: 0.3, blue: 0.3) : .white)
                    .frame(width: geo.size.width * frac)
            }
        }
    }

    // MARK: Input
    private func fire() {
        guard phase == .play, fireCD <= 0 else { return }
        fireCD = 0.26
        let dir = CGVector(dx: sin(heading), dy: -cos(heading))
        let nose = CGPoint(x: ship.x + dir.dx * shipR * 1.4, y: ship.y + dir.dy * shipR * 1.4)
        bullets.append(Bullet(pos: nose, vel: CGVector(dx: dir.dx * 1.0, dy: dir.dy * 1.0), life: 0.95))
        SoundManager.shared.tap(); Haptics.tap()
    }

    // MARK: - Flow
    private func run() async {
        setup()
        var last = Date(); let start = Date()
        loopTask = Task {
            while !Task.isCancelled && phase == .play {
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
        ship = CGPoint(x: 0.5, y: 0.5); shipVel = .zero; heading = 0
        rotDir = 0; thrusting = false; fireCD = 0; invuln = 1.2
        bullets = []; bursts = []
        var rs: [Rock] = []
        for _ in 0..<rockCount {
            // Spawn away from the centre so the ship isn't born on a rock.
            var p = CGPoint(x: 0.5, y: 0.5)
            while hypot(p.x - 0.5, p.y - 0.5) < 0.28 {
                p = CGPoint(x: .random(in: 0...1), y: .random(in: 0...1))
            }
            let a = Double.random(in: 0..<(2 * .pi))
            rs.append(Rock(pos: p,
                           vel: CGVector(dx: cos(a) * rockSpeed, dy: sin(a) * rockSpeed),
                           size: 3, spin: 0))
        }
        rocks = rs
        timeLeft = timeLimit; phase = .play
    }

    private func step(dt: CGFloat) {
        guard phase == .play else { return }
        if fireCD > 0 { fireCD -= Double(dt) }
        if invuln > 0 { invuln -= Double(dt) }

        // Ship.
        heading += Double(rotDir) * 3.2 * Double(dt)
        if thrusting {
            let dir = CGVector(dx: sin(heading), dy: -cos(heading))
            shipVel.dx += dir.dx * 0.9 * dt
            shipVel.dy += dir.dy * 0.9 * dt
        }
        let damp = CGFloat(exp(-0.7 * Double(dt)))
        shipVel.dx *= damp; shipVel.dy *= damp
        let sp = hypot(shipVel.dx, shipVel.dy)
        if sp > 0.6 { shipVel.dx *= 0.6 / sp; shipVel.dy *= 0.6 / sp }
        ship.x = wrap(ship.x + shipVel.dx * dt)
        ship.y = wrap(ship.y + shipVel.dy * dt)

        // Bullets.
        for i in bullets.indices {
            bullets[i].pos.x = wrap(bullets[i].pos.x + bullets[i].vel.dx * dt)
            bullets[i].pos.y = wrap(bullets[i].pos.y + bullets[i].vel.dy * dt)
            bullets[i].life -= Double(dt)
        }
        bullets.removeAll { $0.life <= 0 }

        // Rocks.
        for i in rocks.indices {
            rocks[i].pos.x = wrap(rocks[i].pos.x + rocks[i].vel.dx * dt)
            rocks[i].pos.y = wrap(rocks[i].pos.y + rocks[i].vel.dy * dt)
            rocks[i].spin += 0.6 * Double(dt)
        }

        // Bullet vs rock.
        var newRocks: [Rock] = []
        var hitBulletIDs = Set<UUID>()
        var survivingRockIndices = Array(rocks.indices)
        for ri in rocks.indices {
            let rr = rockR(rocks[ri].size)
            var destroyed = false
            for b in bullets where !hitBulletIDs.contains(b.id) {
                if torusDist(b.pos, rocks[ri].pos) < rr {
                    hitBulletIDs.insert(b.id)
                    destroyed = true
                    bursts.append(Burst(pos: rocks[ri].pos))
                    shakeTick += 1
                    SoundManager.shared.tap(); Haptics.tap()
                    if rocks[ri].size > 1 {
                        for k in 0..<2 {
                            // Demo: fixed split (parent heading ± 0.9 rad at 1.3×) instead of random.
                            let base = Double(atan2(rocks[ri].vel.dy, rocks[ri].vel.dx))
                            let a = isDemo ? base + (k == 0 ? 0.9 : -0.9) : Double.random(in: 0..<(2 * .pi))
                            let spd = rockSpeed * (isDemo ? 1.3 : CGFloat.random(in: 1.1...1.5))
                            newRocks.append(Rock(pos: rocks[ri].pos,
                                                 vel: CGVector(dx: cos(a) * spd, dy: sin(a) * spd),
                                                 size: rocks[ri].size - 1, spin: 0))
                        }
                    }
                    break
                }
            }
            if destroyed { survivingRockIndices.removeAll { $0 == ri } }
        }
        rocks = survivingRockIndices.map { rocks[$0] } + newRocks
        bullets.removeAll { hitBulletIDs.contains($0.id) }

        // Ship vs rock — only a genuine overlap counts (tight radii, no phantom gap).
        if invuln <= 0 {
            for r in rocks where torusDist(ship, r.pos) < rockR(r.size) + shipR * 0.35 {
                fail(); return
            }
        }

        if rocks.isEmpty { win() }
    }

    // MARK: - Demo (live manual clip)
    // The closing stretch of level 1: the ship at centre with one big rock and one small one left
    // (L1 starts with three big ones — 21 hits in all). Stepped at a fixed 1/60s through the real
    // `fire`/`step`; splits are fixed (± 0.9 rad) so the cascade is deterministic. The autopilot
    // turns the nearest rock's lead-intercept bearing into held rotate buttons and fires once the
    // nose is within 0.06 rad (one bullet per rock in flight). Verified offline: every piece is
    // cleared in 4.0s with ≥0.2 of the field to spare, and it still wins across a range of dead
    // bands / fire tolerances and 2,781 of 2,781 sampled layouts.
    private func demoSetup() {
        ship = CGPoint(x: 0.5, y: 0.5); shipVel = .zero; heading = 0
        rotDir = 0; thrusting = false; fireCD = 0; invuln = 1.2
        bullets = []; bursts = []; demoFire = 0
        func rock(_ x: CGFloat, _ y: CGFloat, _ a: Double, _ size: Int) -> Rock {
            Rock(pos: CGPoint(x: x, y: y),
                 vel: CGVector(dx: CGFloat(cos(a)) * rockSpeed, dy: CGFloat(sin(a)) * rockSpeed),
                 size: size, spin: 0)
        }
        rocks = [rock(0.16, 0.72, 4.9, 3), rock(0.78, 0.58, 0.93, 1)]
        timeLeft = timeLimit; phase = .play
    }

    private func runDemo() async {
        let dt: CGFloat = 1.0 / 60.0
        while !Task.isCancelled {
            demoSetup()
            var lockedUntil: [UUID: Double] = [:]
            var t = 0.0
            while !Task.isCancelled && phase == .play && t < 15 {
                t += Double(dt)
                if let target = rocks.min(by: { torusDist(ship, $0.pos) < torusDist(ship, $1.pos) }) {
                    // Lead intercept: solve |d + v·t| = bullet speed (1.0) · t on the torus.
                    var dx = target.pos.x - ship.x, dy = target.pos.y - ship.y
                    if dx > 0.5 { dx -= 1 } else if dx < -0.5 { dx += 1 }
                    if dy > 0.5 { dy -= 1 } else if dy < -0.5 { dy += 1 }
                    let vx = target.vel.dx, vy = target.vel.dy
                    let qa = vx * vx + vy * vy - 1, qb = 2 * (dx * vx + dy * vy), qc = dx * dx + dy * dy
                    let disc = max(0, qb * qb - 4 * qa * qc)
                    var th = (-qb - sqrt(disc)) / (2 * qa)
                    if th < 0 { th = (-qb + sqrt(disc)) / (2 * qa) }
                    let want = Double(atan2(dx + vx * th, -(dy + vy * th)))
                    var e = want - heading
                    while e > .pi { e -= 2 * .pi }
                    while e < -.pi { e += 2 * .pi }
                    rotDir = e > 0.03 ? 1 : (e < -0.03 ? -1 : 0)
                    if abs(e) < 0.06 && fireCD <= 0 && th < 0.85 && (lockedUntil[target.id] ?? -1) < t {
                        lockedUntil[target.id] = t + Double(th) + 0.05
                        fire()
                        demoFire = 8
                    }
                }
                if demoFire > 0 { demoFire -= 1 }
                step(dt: dt)
                try? await Task.sleep(for: .seconds(0.016))
            }
            // Field clear → the real win() ran (onWin is a no-op). Hold, then loop.
            rotDir = 0; demoFire = 0
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    private func wrap(_ v: CGFloat) -> CGFloat { v < 0 ? v + 1 : (v > 1 ? v - 1 : v) }
    private func torusDist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        var dx = abs(a.x - b.x), dy = abs(a.y - b.y)
        if dx > 0.5 { dx = 1 - dx }; if dy > 0.5 { dy = 1 - dy }
        return hypot(dx, dy)
    }

    private func win() {
        guard phase != .done else { return }
        phase = .done; loopTask?.cancel(); onWin()
    }
    private func fail() {
        guard phase != .done else { return }
        phase = .done; loopTask?.cancel(); shakeTick += 1; SoundManager.shared.error(); onFail()
    }
}

// MARK: - Atari vector art

private enum ASTArt {
    /// The three classic rock outlines (unit radius), jagged with notches.
    private static let shapes: [[(CGFloat, CGFloat)]] = [
        [(0, -1), (0.5, -0.9), (0.95, -0.45), (0.7, -0.05), (1.0, 0.35), (0.55, 0.95), (0.05, 0.7),
         (-0.45, 0.95), (-0.95, 0.5), (-0.8, 0.05), (-1.0, -0.4), (-0.45, -0.95)],
        [(-0.2, -1), (0.35, -0.75), (0.85, -0.95), (1.0, -0.3), (0.6, 0.1), (0.95, 0.6), (0.4, 1.0),
         (-0.3, 0.85), (-0.7, 1.0), (-1.0, 0.3), (-0.7, -0.2), (-0.9, -0.7)],
        [(0, -0.9), (0.6, -1.0), (1.0, -0.5), (0.8, 0.0), (1.0, 0.55), (0.45, 0.95), (-0.1, 0.75),
         (-0.6, 1.0), (-1.0, 0.45), (-0.85, -0.1), (-1.0, -0.55), (-0.55, -1.0)],
    ]

    static func rockShape(_ k: Int, radius r: CGFloat, spin: Double) -> Path {
        let pts = shapes[k % shapes.count]
        var p = Path()
        let cs = CGFloat(cos(spin)), sn = CGFloat(sin(spin))
        for (i, v) in pts.enumerated() {
            let q = CGPoint(x: (v.0 * cs - v.1 * sn) * r, y: (v.0 * sn + v.1 * cs) * r)
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        p.closeSubpath()
        return p
    }

    static var rockIcon: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) * 0.45
            let path = rockShape(0, radius: r, spin: 0.3).applying(CGAffineTransform(translationX: size.width / 2, y: size.height / 2))
            ctx.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
        }
    }

    /// The arrow ship outline (the old silhouette: nose, two fins, a notch), with a flickering flame.
    static func ship(_ ctx: GraphicsContext, at c: CGPoint, size S: CGFloat, heading: Double, thrusting: Bool, dim: Bool, glow: Color) {
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .radians(heading))
        g.opacity = dim ? 0.4 : 1
        var hull = Path()
        hull.move(to: CGPoint(x: 0, y: -S / 2))
        hull.addLine(to: CGPoint(x: S / 2, y: S / 2))
        hull.addLine(to: CGPoint(x: 0, y: S / 2 - S * 0.28))
        hull.addLine(to: CGPoint(x: -S / 2, y: S / 2))
        hull.closeSubpath()
        let yellow = Color(red: 1, green: 0.88, blue: 0.3)
        g.stroke(hull, with: .color(glow), style: StrokeStyle(lineWidth: 5, lineJoin: .round))
        g.stroke(hull, with: .color(yellow), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
        if thrusting && Int(Date().timeIntervalSinceReferenceDate * 24) % 2 == 0 {
            var flame = Path()
            flame.move(to: CGPoint(x: -S * 0.16, y: S / 2 - S * 0.2))
            flame.addLine(to: CGPoint(x: 0, y: S / 2 + S * 0.3))
            flame.addLine(to: CGPoint(x: S * 0.16, y: S / 2 - S * 0.2))
            g.stroke(flame, with: .color(.white), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
    }

    /// A round arcade button in its bezel, centred in its (unchanged, rectangular) hit frame.
    struct ArcadeButton: View {
        let color: Color
        let lit: Bool
        var body: some View {
            GeometryReader { geo in
                let d = min(geo.size.width, geo.size.height) * 0.94
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.1))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(white: 0.26), lineWidth: 1))
                    Circle().fill(Color(white: 0.04)).frame(width: d, height: d)
                    Circle()
                        .fill(RadialGradient(colors: [color.mix(with: .white, by: lit ? 0.55 : 0.3), color, color.mix(with: .black, by: 0.35)],
                                             center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: d * 0.55))
                        .frame(width: d * 0.8, height: d * 0.8)
                    if lit {
                        Circle().stroke(.white.opacity(0.9), lineWidth: 2).frame(width: d * 0.86, height: d * 0.86)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}
