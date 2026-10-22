//
//  LaserDodgeGame.swift
//  A Banana Game
//
//  Reflex — an Entrapment-style laser room. Emitters around the walls sweep long rotating laser
//  beams across the arena; each beam runs the full way until it strikes a solid block, which casts
//  a moving safe shadow. Steer the banana with the joystick under the vault, weave through the
//  beams, and duck behind the blocks as they sweep. Survive until the bar empties. Touch a beam and
//  it's back to level 1.
//
//  7 levels: more emitters, faster spins, thicker beams — with a few blocks to hide behind from
//  level 1.
//
//  The joystick is the shared `FloatingJoystick`: touch anywhere in the strip under the vault and it
//  centres under your thumb; it's tuned to be sensitive (full speed after a short push, brisk light
//  pushes, instant reversals). Its base rests on the left, clear of the page's skip button in the
//  middle. (It used to be a drag on the vault itself, which hid the banana and the beams around it
//  under your finger.) The joystick is a drag, which would fight the feed's vertical pager, so this
//  game sets `locksFeed: true`.
//
//  Drawn as a museum vault's laser hallway: polished dark stone and red haze inside a steel bezel
//  (drawn outside the field), red beams with white-hot cores, wall turrets whose heads swing with
//  their beams, a display plinth with a prize under glass on every cover block, and a masked banana
//  with the bright hitbox core. The joystick is a vault console control: a steel bezel ring with red
//  sensor-lamp arrows that light toward the push, and a black rubber knob with a red lens.
//

import SwiftUI

enum LaserDodgeGame {
    static let definition = GameDefinition(
        id: "laser-dodge",
        title: "Laser Dodge",
        emoji: "🍌",
        genre: .reflex,
        levelCount: 7,
        locksFeed: true,
        manual: GameManual(
            bullets: [
                "Steer the banana with the joystick; only the bright center dot is your hitbox.",
                "Wall emitters sweep lethal laser beams across the room.",
                "Solid blocks stop beams and cast moving safe shadows — duck behind them.",
                "Survive until the bar empties; one touch and you're back to level 1.",
            ],
            bulletsVI: [
                "Lái quả chuối bằng cần điều khiển; chỉ chấm sáng ở giữa mới là vùng trúng đòn.",
                "Các bộ phát trên tường quét những tia laser chết người khắp phòng.",
                "Các khối đặc chặn tia và tạo bóng an toàn di động — hãy nấp sau chúng.",
                "Sống sót đến khi thanh cạn; chạm một lần là về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(LaserDodgeView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct LaserDodgeView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    // MARK: Difficulty
    private var surviveTime: Double { [9, 10, 12, 13, 15, 17, 20][min(level, 7) - 1] }
    private var emitterCount: Int   { [3, 4, 5, 6, 7, 8, 10][min(level, 7) - 1] }
    private var blockCount: Int     { [4, 4, 5, 5, 6, 6, 7][min(level, 7) - 1] }
    private var spinSpeed: Double   { [0.5, 0.65, 0.8, 1.0, 1.2, 1.4, 1.7][min(level, 7) - 1] }
    private var thickFrac: CGFloat  { [0.016, 0.018, 0.020, 0.022, 0.024, 0.027, 0.030][min(level, 7) - 1] }
    /// The banana's full-push joystick speed, in vault short sides per second. Fast on purpose: a bot
    /// that sees every sweep coming wins about as often at 1.0–2.0 as it did with the old drag, and the
    /// extra speed is for reacting late, the way people do.
    private let moveSpeed: CGFloat = 1.5

    private struct Emitter: Identifiable {
        let id = UUID()
        let pos: CGPoint
        var angle: Double
        let vel: Double
    }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var field: CGSize = .zero
    @State private var player: CGPoint = .zero
    @State private var emitters: [Emitter] = []
    @State private var blocks: [CGRect] = []
    @State private var stick = CGVector.zero      // joystick: fraction of top speed per axis
    @State private var timeLeft = 0.0
    @State private var grace = 0.0
    @State private var built = false

    var body: some View {
        VStack(spacing: isDemo ? 6 : 8) {
            HStack(spacing: 8) {
                // The vault's "armed" lamp beside the goal.
                Circle()
                    .fill(LDArt.red)
                    .frame(width: isDemo ? 8 : 10, height: isDemo ? 8 : 10)
                    .shadow(color: LDArt.red, radius: 4)
                Text(L("SURVIVE", "SỐNG SÓT"))
                    .font(.system(size: isDemo ? 15 : 22, weight: .black, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.white)
            }
            .padding(.top, isDemo ? 6 : 0)
            if !isDemo { timeBar.frame(height: 6).padding(.horizontal, 48) }
            arena
            FloatingJoystick(vector: $stick, baseSize: isDemo ? 70 : 112, demo: isDemo, active: phase == .play) { push in
                Canvas { ctx, s in LDArt.joystickBase(ctx, size: s, push: push) }
            } knob: {
                Canvas { ctx, s in LDArt.joystickKnob(ctx, size: s) }
            }
            .frame(height: isDemo ? 70 : 112)
            .padding(.bottom, isDemo ? 6 : 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, isDemo ? 0 : 8)
        .background(LDArt.room)
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
    }

    private var arena: some View {
        GeometryReader { outer in
            // A steel bezel frames the vault OUTSIDE the field, so the field is exactly what the
            // beams, blocks and banana live in.
            let t: CGFloat = isDemo ? 5 : 7
            let w: CGFloat = max(1, outer.size.width - t * 2)
            let h: CGFloat = max(1, outer.size.height - t * 2)
            ZStack(alignment: .topLeading) {
                LDBezel(size: outer.size, t: t).equatable()
                ZStack {
                    LDVault(size: CGSize(width: w, height: h), blocks: blocks).equatable()

                    // Beams, turrets and the banana in one pass.
                    Canvas { ctx, size in drawAction(ctx, w: size.width, h: size.height) }
                        .allowsHitTesting(false)
                }
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .offset(x: t, y: t)
            }
            .frame(width: outer.size.width, height: outer.size.height, alignment: .topLeading)
            .onAppear { if field == .zero { field = CGSize(width: w, height: h) } }
        }
        .padding(.horizontal, 12)
    }

    /// Red beams with white-hot cores (the core is the beam's real thickness), the wall turrets
    /// swinging with them, and the banana with its bright hitbox core.
    private func drawAction(_ ctx: GraphicsContext, w: CGFloat, h: CGFloat) {
        let minD = min(w, h)
        let thick = minD * thickFrac
        for e in emitters {
            LDArt.beam(ctx, from: e.pos, to: rayEnd(from: e.pos, angle: e.angle), thick: thick)
        }
        for e in emitters {
            LDArt.turret(ctx, at: e.pos, angle: e.angle, r: max(6, minD * 0.03))
        }
        let p = player == .zero ? CGPoint(x: w / 2, y: h / 2) : player
        var g = ctx
        if grace > 0 { g.opacity = 0.5 }
        LDArt.spyBanana(g, at: p, width: minD * 0.15)
        let hb = minD * 0.014
        g.fill(Path(ellipseIn: CGRect(x: p.x - hb * 2.2, y: p.y - hb * 2.2, width: hb * 4.4, height: hb * 4.4)),
               with: .radialGradient(Gradient(colors: [.white.opacity(0.7), .white.opacity(0)]), center: p, startRadius: hb * 0.8, endRadius: hb * 2.2))
        g.fill(Path(ellipseIn: CGRect(x: p.x - hb, y: p.y - hb, width: hb * 2, height: hb * 2)), with: .color(.white))
        g.stroke(Path(ellipseIn: CGRect(x: p.x - hb, y: p.y - hb, width: hb * 2, height: hb * 2)), with: .color(.black.opacity(0.5)), lineWidth: 0.8)
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac: Double = surviveTime > 0 ? timeLeft / surviveTime : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule().fill(frac < 0.3 ? Color(red: 0.4, green: 0.95, blue: 0.5) : Color(red: 1, green: 0.66, blue: 0.16))
                    .frame(width: geo.size.width * max(0, frac))
            }
        }
    }

    // MARK: - Flow

    private func run() async {
        while field == .zero { try? await Task.sleep(for: .seconds(0.02)) }
        if !built { setup(); built = true }
        var last = Date()
        while !Task.isCancelled && phase == .play {
            try? await Task.sleep(for: .seconds(0.016))
            let now = Date()
            let dt = min(0.05, now.timeIntervalSince(last)); last = now
            step(dt: dt)
        }
    }

    // MARK: - Demo (live manual clip)
    // Level 1 (3 emitters, 4 blocks, 9s) on a fixed layout given in field fractions. The real
    // `step` runs at a fixed 1/60s; your thumb on the joystick is an auto-dodge planner: every frame
    // it predicts each beam ~0.5s ahead (they spin at known rates) and pushes the stick toward a spot
    // in the open lanes that keeps a safe margin (diving for max clearance, often into a block's
    // shadow, when a sweep closes in). The stick it pushes is what moves the banana.
    // It never "fakes" survival: the real beam/hitbox test runs every frame.
    private func demoSetup() {
        let w = field.width, h = field.height, minD = min(w, h)
        player = CGPoint(x: w / 2, y: h / 2)
        blocks = [(0.16, 0.18), (0.66, 0.22), (0.20, 0.64), (0.62, 0.66)].map { fx, fy in
            CGRect(x: w * fx, y: h * fy, width: minD * 0.17, height: minD * 0.15)
        }
        emitters = [
            Emitter(pos: CGPoint(x: w * 0.5, y: h * 0.04), angle: 2.355, vel: spinSpeed),
            Emitter(pos: CGPoint(x: w * 0.04, y: h * 0.45), angle: 4.71, vel: -spinSpeed),
            Emitter(pos: CGPoint(x: w * 0.96, y: h * 0.78), angle: 3.14, vel: spinSpeed),
        ]
        timeLeft = surviveTime
        grace = 0.8
        phase = .play
        built = true
    }

    /// Lanes the demo finger roams between (field fractions), so it plays actively instead of
    /// parking in one quiet corner.
    private static let demoWander: [CGPoint] = [
        CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.3, y: 0.42), CGPoint(x: 0.52, y: 0.3),
        CGPoint(x: 0.78, y: 0.5), CGPoint(x: 0.45, y: 0.82), CGPoint(x: 0.5, y: 0.55),
    ]

    /// Where the finger drags next. Beams are predicted ~0.5s ahead (they spin at known rates);
    /// among reachable spots that keep a safe margin from every predicted beam, head for the
    /// current wander lane — and if nothing nearby is safe, dive for the most clearance.
    private func demoTarget(t: Double) -> CGPoint {
        let w = field.width, h = field.height, minD = min(w, h)
        let hb = minD * 0.014, half = minD * thickFrac / 2
        var segs: [(CGPoint, CGPoint)] = []
        for e in emitters {
            for tau in [0.0, 0.15, 0.3, 0.45, 0.6, 0.8] {
                segs.append((e.pos, rayEnd(from: e.pos, angle: e.angle + e.vel * tau)))
            }
        }
        func clearance(_ c: CGPoint) -> CGFloat {
            segs.map { distToSegment(c, $0.0, $0.1) }.min() ?? .infinity
        }
        let lane = Self.demoWander[Int(t / 1.5) % Self.demoWander.count]
        let goal = CGPoint(x: lane.x * w, y: lane.y * h)
        let safe = half + hb + minD * 0.06
        var cands = [player]
        for r in [0.05, 0.1, 0.16, 0.22] {
            for k in 0..<16 {
                let a = Double(k) / 16 * 2 * .pi
                var c = CGPoint(x: player.x + CGFloat(cos(a)) * minD * r, y: player.y + CGFloat(sin(a)) * minD * r)
                // Stay off the walls — a corner is a trap when a beam sweeps along it.
                c.x = min(w * 0.9, max(w * 0.1, c.x)); c.y = min(h * 0.9, max(h * 0.1, c.y))
                cands.append(resolveBlocks(c, hb: hb))
            }
        }
        // A spot only counts if the drag there is clear too (check the path's midpoint).
        let scored = cands.map { c in
            (c, min(clearance(c), clearance(CGPoint(x: (c.x + player.x) / 2, y: (c.y + player.y) / 2))))
        }
        if let best = scored.filter({ $0.1 >= safe })
            .min(by: { hypot($0.0.x - goal.x, $0.0.y - goal.y) < hypot($1.0.x - goal.x, $1.0.y - goal.y) }) {
            return best.0
        }
        return scored.max(by: { $0.1 < $1.1 })?.0 ?? player
    }

    private func runDemo() async {
        while field == .zero { try? await Task.sleep(for: .seconds(0.02)) }
        let dt = 1.0 / 60.0
        while !Task.isCancelled {
            demoSetup()
            try? await Task.sleep(for: .seconds(0.4))
            var t = 0.0
            while !Task.isCancelled && phase == .play {
                t += dt
                // Push the stick toward the planned spot: full push when it's far, gentler when close.
                let target = demoTarget(t: t)
                let dx = target.x - player.x, dy = target.y - player.y, d = hypot(dx, dy)
                let full = min(field.width, field.height) * moveSpeed * CGFloat(dt)
                let k = d > 0.001 ? min(1, d / full) / d : 0
                stick = CGVector(dx: dx * k, dy: dy * k)
                step(dt: dt)
                try? await Task.sleep(for: .seconds(0.016))
            }
            // Survived the full bar → the real win() ran (onWin is a no-op). Hold, then loop.
            stick = .zero
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    private func setup() {
        let w: CGFloat = field.width, h: CGFloat = field.height
        let minD: CGFloat = min(w, h)
        player = CGPoint(x: w / 2, y: h / 2)

        // Solid blocks, kept clear of the player's start and spaced apart.
        var bs: [CGRect] = []
        var tries = 0
        while bs.count < blockCount && tries < 300 {
            tries += 1
            let bw = CGFloat.random(in: minD * 0.12...minD * 0.22)
            let bh = CGFloat.random(in: minD * 0.12...minD * 0.22)
            let x = CGFloat.random(in: w * 0.10...(w * 0.90 - bw))
            let y = CGFloat.random(in: h * 0.10...(h * 0.90 - bh))
            let r = CGRect(x: x, y: y, width: bw, height: bh)
            if r.insetBy(dx: -minD * 0.10, dy: -minD * 0.10).contains(player) { continue }
            if bs.contains(where: { $0.insetBy(dx: -minD * 0.05, dy: -minD * 0.05).intersects(r) }) { continue }
            bs.append(r)
        }
        blocks = bs

        // Emitters around the border, spaced, not buried in a block.
        var es: [Emitter] = []
        tries = 0
        while es.count < emitterCount && tries < 400 {
            tries += 1
            let side = Int.random(in: 0..<4)
            let p: CGPoint
            switch side {
            case 0: p = CGPoint(x: CGFloat.random(in: w * 0.1...w * 0.9), y: h * 0.04)
            case 1: p = CGPoint(x: CGFloat.random(in: w * 0.1...w * 0.9), y: h * 0.96)
            case 2: p = CGPoint(x: w * 0.04, y: CGFloat.random(in: h * 0.1...h * 0.9))
            default: p = CGPoint(x: w * 0.96, y: CGFloat.random(in: h * 0.1...h * 0.9))
            }
            if blocks.contains(where: { $0.contains(p) }) { continue }
            if es.contains(where: { hypot($0.pos.x - p.x, $0.pos.y - p.y) < minD * 0.22 }) { continue }
            es.append(Emitter(pos: p, angle: Double.random(in: 0...(2 * .pi)),
                              vel: spinSpeed * (Bool.random() ? 1 : -1)))
        }
        emitters = es

        timeLeft = surviveTime
        grace = 0.8
        phase = .play
    }

    private func step(dt: Double) {
        guard phase == .play else { return }
        let w: CGFloat = field.width, h: CGFloat = field.height
        let hb: CGFloat = min(w, h) * 0.014
        let half: CGFloat = min(w, h) * thickFrac / 2

        // Fly with the stick, kept on the floor and off the plinths.
        let v = moveSpeed * min(w, h) * CGFloat(dt)
        player.x = min(w, max(0, player.x + stick.dx * v))
        player.y = min(h, max(0, player.y + stick.dy * v))
        player = resolveBlocks(player, hb: hb)

        for i in emitters.indices { emitters[i].angle += emitters[i].vel * dt }

        if grace > 0 {
            grace -= dt
        } else {
            for e in emitters {
                let end = rayEnd(from: e.pos, angle: e.angle)
                if distToSegment(player, e.pos, end) < half + hb { fail(); return }
            }
        }

        timeLeft -= dt
        if timeLeft <= 0 { win() }
    }

    // MARK: - Geometry

    /// Marches a ray from `o` at `angle` until it leaves the field or enters a block.
    private func rayEnd(from o: CGPoint, angle: Double) -> CGPoint {
        let w: CGFloat = field.width, h: CGFloat = field.height
        let step: CGFloat = max(2, min(w, h) * 0.012)
        let dx = CGFloat(cos(angle)) * step, dy = CGFloat(sin(angle)) * step
        var p = o
        var n = 0
        while n < 3000 {
            n += 1
            let np = CGPoint(x: p.x + dx, y: p.y + dy)
            if np.x < 0 || np.x > w || np.y < 0 || np.y > h { return p }
            if blocks.contains(where: { $0.contains(np) }) { return p }
            p = np
        }
        return p
    }

    private func distToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        if len2 < 0.0001 { return hypot(p.x - a.x, p.y - a.y) }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2
        t = max(0, min(1, t))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// Pushes the player out of any block (expanded by the hitbox) to the nearest edge.
    private func resolveBlocks(_ pos: CGPoint, hb: CGFloat) -> CGPoint {
        var p = pos
        for b in blocks {
            let bb = b.insetBy(dx: -hb, dy: -hb)
            guard bb.contains(p) else { continue }
            let left = p.x - bb.minX, right = bb.maxX - p.x
            let top = p.y - bb.minY, bottom = bb.maxY - p.y
            let m = min(left, right, top, bottom)
            if m == left { p.x = bb.minX }
            else if m == right { p.x = bb.maxX }
            else if m == top { p.y = bb.minY }
            else { p.y = bb.maxY }
        }
        return p
    }

    private func win() {
        guard phase == .play else { return }
        phase = .done
        Haptics.success(); SoundManager.shared.tap()
        onWin()
    }

    private func fail() {
        guard phase == .play else { return }
        phase = .done
        Haptics.warning(); SoundManager.shared.error()
        onFail()
    }
}

// MARK: - Laser vault art

private enum LDArt {
    static let red = Color(red: 1.0, green: 0.16, blue: 0.2)
    static let room = Color(red: 0.05, green: 0.055, blue: 0.08)
    static let ink = Color(red: 0.05, green: 0.05, blue: 0.07)
    static let gold = Color(red: 0.98, green: 0.78, blue: 0.22)

    static func hash(_ n: Double) -> CGFloat {
        let v: Double = sin(n * 12.9898) * 43758.5453
        return CGFloat(v - floor(v))
    }

    static func disc(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    /// A laser in haze: wide soft glow, the red beam at its true thickness, a white-hot core,
    /// and a hot spot where it strikes a plinth or the wall.
    static func beam(_ ctx: GraphicsContext, from a: CGPoint, to b: CGPoint, thick: CGFloat) {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        ctx.stroke(p, with: .color(red.opacity(0.1)), style: StrokeStyle(lineWidth: thick * 5.5, lineCap: .round))
        ctx.stroke(p, with: .color(red.opacity(0.28)), style: StrokeStyle(lineWidth: thick * 2.4, lineCap: .round))
        ctx.stroke(p, with: .color(red), style: StrokeStyle(lineWidth: thick, lineCap: .round))
        ctx.stroke(p, with: .color(Color(red: 1, green: 0.86, blue: 0.86)), style: StrokeStyle(lineWidth: max(0.8, thick * 0.32), lineCap: .round))
        let r = thick * 2.4
        ctx.fill(disc(b, r), with: .radialGradient(Gradient(colors: [.white, red.opacity(0.7), red.opacity(0)]),
                                                   center: b, startRadius: 0, endRadius: r))
    }

    /// A wall turret seen from above: a bolted base and a head that swings with its beam.
    static func turret(_ ctx: GraphicsContext, at p: CGPoint, angle: Double, r: CGFloat) {
        ctx.fill(disc(CGPoint(x: p.x + r * 0.15, y: p.y + r * 0.25), r * 1.05), with: .color(.black.opacity(0.45)))
        ctx.fill(disc(p, r), with: .radialGradient(Gradient(colors: [Color(white: 0.52), Color(white: 0.22)]),
                                                   center: CGPoint(x: p.x - r * 0.3, y: p.y - r * 0.3), startRadius: 0, endRadius: r * 1.4))
        ctx.stroke(disc(p, r), with: .color(ink), lineWidth: 1.2)
        for k in 0..<4 {
            let a = Double(k) * .pi / 2 + .pi / 4
            ctx.fill(disc(CGPoint(x: p.x + CGFloat(cos(a)) * r * 0.72, y: p.y + CGFloat(sin(a)) * r * 0.72), r * 0.1), with: .color(Color(white: 0.7)))
        }
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        g.rotate(by: .radians(angle))
        let head = CGRect(x: -r * 0.55, y: -r * 0.42, width: r * 1.7, height: r * 0.84)
        g.fill(Path(roundedRect: head, cornerRadius: r * 0.3),
               with: .linearGradient(Gradient(colors: [Color(white: 0.6), Color(white: 0.28)]),
                                     startPoint: CGPoint(x: 0, y: -r * 0.42), endPoint: CGPoint(x: 0, y: r * 0.42)))
        g.stroke(Path(roundedRect: head, cornerRadius: r * 0.3), with: .color(ink), lineWidth: 1)
        let lens = CGRect(x: r * 0.95, y: -r * 0.3, width: r * 0.34, height: r * 0.6)
        g.fill(Path(ellipseIn: lens), with: .color(red))
        g.fill(Path(ellipseIn: CGRect(x: lens.minX + r * 0.06, y: lens.minY + r * 0.08, width: r * 0.12, height: r * 0.16)), with: .color(.white.opacity(0.9)))
    }

    /// The joystick's base: a steel bezel ring round a dark rubber well, with four red sensor-lamp
    /// arrows; the ones the stick is pushed toward light up.
    static func joystickBase(_ ctx: GraphicsContext, size s: CGSize, push: CGVector) {
        let c = CGPoint(x: s.width / 2, y: s.height / 2)
        let r = min(s.width, s.height) / 2 - 2
        ctx.fill(disc(CGPoint(x: c.x, y: c.y + 3), r), with: .color(.black.opacity(0.45)))
        ctx.fill(disc(c, r), with: .linearGradient(Gradient(colors: [Color(white: 0.62), Color(white: 0.3), Color(white: 0.16)]),
                                                   startPoint: CGPoint(x: c.x, y: c.y - r), endPoint: CGPoint(x: c.x, y: c.y + r)))
        ctx.stroke(disc(c, r - 0.5), with: .color(.white.opacity(0.25)), lineWidth: 1)
        let well = r * 0.8
        ctx.fill(disc(c, well), with: .radialGradient(Gradient(colors: [Color(red: 0.16, green: 0.08, blue: 0.1), ink]),
                                                      center: c, startRadius: 0, endRadius: well))
        ctx.stroke(disc(c, well), with: .color(.black), lineWidth: 2)
        // Bezel bolts.
        for k in 0..<4 {
            let a = Double(k) * .pi / 2 + .pi / 4
            ctx.fill(disc(CGPoint(x: c.x + CGFloat(cos(a)) * r * 0.9, y: c.y + CGFloat(sin(a)) * r * 0.9), max(1.2, r * 0.045)),
                     with: .color(Color(white: 0.78)))
        }
        for k in 0..<4 {
            let a = Double(k) * .pi / 2 - .pi / 2               // up, right, down, left
            let dx = CGFloat(cos(a)), dy = CGFloat(sin(a))
            let glow = Double(max(0, push.dx * dx + push.dy * dy))
            let tip = CGPoint(x: c.x + dx * well * 0.9, y: c.y + dy * well * 0.9)
            let back = CGPoint(x: c.x + dx * well * 0.68, y: c.y + dy * well * 0.68)
            var arrow = Path()
            arrow.move(to: tip)
            arrow.addLine(to: CGPoint(x: back.x - dy * well * 0.15, y: back.y + dx * well * 0.15))
            arrow.addLine(to: CGPoint(x: back.x + dy * well * 0.15, y: back.y - dx * well * 0.15))
            arrow.closeSubpath()
            if glow > 0.05 {
                let m = CGPoint(x: (tip.x + back.x) / 2, y: (tip.y + back.y) / 2)
                ctx.fill(disc(m, well * 0.26), with: .radialGradient(Gradient(colors: [red.opacity(0.6 * glow), red.opacity(0)]),
                                                                    center: m, startRadius: 0, endRadius: well * 0.26))
            }
            ctx.fill(arrow, with: .color(red.opacity(0.3 + 0.7 * glow)))
        }
    }

    /// The joystick's knob: a black rubber cap with a grip ring and a red lens in the middle.
    static func joystickKnob(_ ctx: GraphicsContext, size s: CGSize) {
        let c = CGPoint(x: s.width / 2, y: s.height / 2)
        let r = min(s.width, s.height) / 2 * 0.92
        ctx.fill(disc(CGPoint(x: c.x + r * 0.08, y: c.y + r * 0.16), r), with: .color(.black.opacity(0.45)))
        ctx.fill(disc(c, r), with: .radialGradient(Gradient(colors: [Color(white: 0.4), Color(white: 0.14), Color(white: 0.06)]),
                                                   center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4), startRadius: 0, endRadius: r * 1.5))
        ctx.stroke(disc(c, r * 0.72), with: .color(.black.opacity(0.7)), lineWidth: max(1, r * 0.08))
        ctx.stroke(disc(c, r * 0.78), with: .color(.white.opacity(0.12)), lineWidth: 1)
        ctx.fill(disc(c, r * 0.3), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.75, blue: 0.75), red, Color(red: 0.45, green: 0.02, blue: 0.05)]),
                                                         center: CGPoint(x: c.x - r * 0.08, y: c.y - r * 0.08), startRadius: 0, endRadius: r * 0.32))
        ctx.fill(disc(CGPoint(x: c.x - r * 0.1, y: c.y - r * 0.11), r * 0.08), with: .color(.white.opacity(0.85)))
        ctx.stroke(disc(c, r), with: .color(.black), lineWidth: 1.2)
    }

    /// The banana thief: a plump banana in a black mask whose body runs through the hitbox point.
    static func spyBanana(_ ctx: GraphicsContext, at p: CGPoint, width w: CGFloat) {
        let h = w * 0.45
        let c = CGPoint(x: p.x, y: p.y - h * 0.043)
        var body = Path()
        body.move(to: CGPoint(x: c.x - w * 0.5, y: c.y - h * 0.4))
        body.addQuadCurve(to: CGPoint(x: c.x + w * 0.5, y: c.y - h * 0.5), control: CGPoint(x: c.x - w * 0.02, y: c.y + h * 1.05))
        body.addQuadCurve(to: CGPoint(x: c.x - w * 0.5, y: c.y - h * 0.4), control: CGPoint(x: c.x, y: c.y + h * 0.02))
        body.closeSubpath()
        ctx.fill(body.offsetBy(dx: w * 0.04, dy: h * 0.2), with: .color(.black.opacity(0.45)))
        ctx.fill(body, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.5), Color(red: 1, green: 0.84, blue: 0.2),
                                                               Color(red: 0.86, green: 0.62, blue: 0.08)]),
                                             startPoint: CGPoint(x: c.x, y: c.y - h * 0.3), endPoint: CGPoint(x: c.x, y: c.y + h * 0.4)))
        // A black mask across the front third, with two white eyes.
        var masked = ctx
        masked.clip(to: body)
        masked.fill(Path(CGRect(x: c.x - w * 0.37, y: c.y - h, width: w * 0.16, height: h * 2)), with: .color(ink))
        for y in [-0.24, -0.06] as [CGFloat] {
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - w * 0.325, y: c.y + h * y, width: w * 0.065, height: h * 0.13)), with: .color(.white))
        }
        ctx.stroke(body, with: .color(Color(red: 0.4, green: 0.26, blue: 0.04)), lineWidth: max(1.2, w * 0.035))
        ctx.fill(Path(roundedRect: CGRect(x: c.x - w * 0.6, y: c.y - h * 0.5, width: w * 0.13, height: h * 0.2), cornerRadius: w * 0.02),
                 with: .color(Color(red: 0.42, green: 0.28, blue: 0.1)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x + w * 0.45, y: c.y - h * 0.57, width: w * 0.08, height: h * 0.15)),
                 with: .color(Color(red: 0.3, green: 0.2, blue: 0.05)))
    }

    /// The prize on a plinth, seen from above: diamond, golden banana idol, ruby, crown or jade vase.
    static func treasure(_ ctx: GraphicsContext, kind: Int, center c: CGPoint, size s: CGFloat) {
        switch kind % 5 {
        case 0:
            var oct = Path()
            for k in 0..<8 {
                let a = Double(k) * .pi / 4 + .pi / 8
                let q = CGPoint(x: c.x + CGFloat(cos(a)) * s * 0.5, y: c.y + CGFloat(sin(a)) * s * 0.5)
                if k == 0 { oct.move(to: q) } else { oct.addLine(to: q) }
            }
            oct.closeSubpath()
            ctx.fill(oct, with: .linearGradient(Gradient(colors: [Color(red: 0.85, green: 0.98, blue: 1), Color(red: 0.35, green: 0.75, blue: 0.95)]),
                                                startPoint: CGPoint(x: c.x - s * 0.4, y: c.y - s * 0.4), endPoint: CGPoint(x: c.x + s * 0.4, y: c.y + s * 0.4)))
            var facets = Path()
            for k in 0..<8 {
                let a = Double(k) * .pi / 4 + .pi / 8
                facets.move(to: c)
                facets.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * s * 0.5, y: c.y + CGFloat(sin(a)) * s * 0.5))
            }
            facets.addRect(CGRect(x: c.x - s * 0.18, y: c.y - s * 0.18, width: s * 0.36, height: s * 0.36))
            ctx.stroke(facets, with: .color(Color(red: 0.2, green: 0.5, blue: 0.7).opacity(0.7)), lineWidth: 0.8)
            ctx.stroke(oct, with: .color(Color(red: 0.12, green: 0.35, blue: 0.5)), lineWidth: 1)
        case 1:
            let h = s * 0.5
            var ban = Path()
            ban.move(to: CGPoint(x: c.x - s * 0.5, y: c.y - h * 0.3))
            ban.addQuadCurve(to: CGPoint(x: c.x + s * 0.5, y: c.y - h * 0.4), control: CGPoint(x: c.x, y: c.y + h * 1.1))
            ban.addQuadCurve(to: CGPoint(x: c.x - s * 0.5, y: c.y - h * 0.3), control: CGPoint(x: c.x, y: c.y + h * 0.35))
            ban.closeSubpath()
            ctx.fill(ban, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.6), gold, Color(red: 0.7, green: 0.48, blue: 0.08)]),
                                                startPoint: CGPoint(x: c.x, y: c.y - h * 0.3), endPoint: CGPoint(x: c.x, y: c.y + h * 0.6)))
            ctx.stroke(ban, with: .color(Color(red: 0.45, green: 0.3, blue: 0.04)), lineWidth: 1)
            ctx.fill(disc(CGPoint(x: c.x - s * 0.15, y: c.y + h * 0.1), s * 0.05), with: .color(.white.opacity(0.9)))
        case 2:
            var gem = Path()
            gem.addRoundedRect(in: CGRect(x: -s * 0.34, y: -s * 0.34, width: s * 0.68, height: s * 0.68), cornerSize: CGSize(width: s * 0.12, height: s * 0.12))
            var g = ctx
            g.translateBy(x: c.x, y: c.y)
            g.rotate(by: .degrees(45))
            g.fill(gem, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.5, blue: 0.55), Color(red: 0.75, green: 0.05, blue: 0.15)]),
                                              startPoint: CGPoint(x: -s * 0.3, y: -s * 0.3), endPoint: CGPoint(x: s * 0.3, y: s * 0.3)))
            g.stroke(Path(roundedRect: CGRect(x: -s * 0.16, y: -s * 0.16, width: s * 0.32, height: s * 0.32), cornerRadius: s * 0.04),
                     with: .color(.white.opacity(0.5)), lineWidth: 0.8)
            g.stroke(gem, with: .color(Color(red: 0.4, green: 0.02, blue: 0.08)), lineWidth: 1)
        case 3:
            var crown = Path()
            for k in 0..<10 {
                let a = Double(k) * .pi / 5 - .pi / 2
                let rr = k % 2 == 0 ? s * 0.5 : s * 0.33
                let q = CGPoint(x: c.x + CGFloat(cos(a)) * rr, y: c.y + CGFloat(sin(a)) * rr)
                if k == 0 { crown.move(to: q) } else { crown.addLine(to: q) }
            }
            crown.closeSubpath()
            ctx.fill(crown, with: .color(gold))
            ctx.stroke(crown, with: .color(Color(red: 0.5, green: 0.34, blue: 0.05)), lineWidth: 1)
            ctx.fill(disc(c, s * 0.2), with: .color(Color(red: 0.55, green: 0.1, blue: 0.2)))
            ctx.fill(disc(c, s * 0.08), with: .color(Color(red: 0.3, green: 0.6, blue: 1)))
        default:
            ctx.fill(disc(c, s * 0.48), with: .radialGradient(Gradient(colors: [Color(red: 0.5, green: 0.85, blue: 0.6), Color(red: 0.1, green: 0.45, blue: 0.3)]),
                                                              center: CGPoint(x: c.x - s * 0.15, y: c.y - s * 0.15), startRadius: 0, endRadius: s * 0.55))
            ctx.stroke(disc(c, s * 0.48), with: .color(Color(red: 0.05, green: 0.25, blue: 0.15)), lineWidth: 1)
            ctx.stroke(disc(c, s * 0.3), with: .color(gold.opacity(0.8)), lineWidth: 1.2)
            ctx.fill(disc(c, s * 0.16), with: .color(Color(red: 0.03, green: 0.12, blue: 0.08)))
        }
    }
}

/// The vault's steel bezel with a row of little red sensor lamps (static).
private struct LDBezel: View, Equatable {
    let size: CGSize
    let t: CGFloat

    var body: some View {
        Canvas { ctx, s in
            let r = CGRect(origin: .zero, size: s)
            ctx.fill(Path(roundedRect: r, cornerRadius: 14), with: .linearGradient(Gradient(colors: [Color(white: 0.3), Color(white: 0.12)]),
                                                                                  startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height)))
            ctx.stroke(Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 14), with: .color(.white.opacity(0.18)), lineWidth: 1)
            ctx.stroke(Path(roundedRect: r.insetBy(dx: t - 0.5, dy: t - 0.5), cornerRadius: 10.5), with: .color(.black.opacity(0.8)), lineWidth: 1.5)
            // Sensor lamps along the top and bottom rails.
            var x: CGFloat = 26
            while x < s.width - 20 {
                for y in [t / 2, s.height - t / 2] {
                    ctx.fill(LDArt.disc(CGPoint(x: x, y: y), max(1.2, t * 0.2)), with: .color(LDArt.red.opacity(0.85)))
                }
                x += 34
            }
        }
        .allowsHitTesting(false)
    }
}

/// The vault floor: polished dark stone tiles, a sheen, faint haze — and a display plinth with a
/// prize under glass on every cover block. Static for the level.
private struct LDVault: View, Equatable {
    let size: CGSize
    let blocks: [CGRect]

    var body: some View {
        Canvas { ctx, s in
            let full = CGRect(origin: .zero, size: s)
            ctx.fill(Path(full), with: .linearGradient(Gradient(colors: [Color(red: 0.1, green: 0.11, blue: 0.15), Color(red: 0.05, green: 0.055, blue: 0.08)]),
                                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height)))
            let tile = max(24, min(s.width, s.height) / 4.5)
            var grid = Path()
            var gx: CGFloat = 0
            while gx <= s.width { grid.move(to: CGPoint(x: gx, y: 0)); grid.addLine(to: CGPoint(x: gx, y: s.height)); gx += tile }
            var gy: CGFloat = 0
            while gy <= s.height { grid.move(to: CGPoint(x: 0, y: gy)); grid.addLine(to: CGPoint(x: s.width, y: gy)); gy += tile }
            ctx.stroke(grid, with: .color(Color(red: 0.17, green: 0.19, blue: 0.25)), lineWidth: 1)
            // Polished sheen across the stone, and a red haze hanging in the air.
            ctx.fill(Path(full), with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.05), .clear]),
                                                       startPoint: CGPoint(x: 0, y: s.height * 0.1), endPoint: CGPoint(x: s.width, y: s.height * 0.7)))
            for k in 0..<3 {
                let c = CGPoint(x: s.width * LDArt.hash(Double(k) * 3.7 + 1), y: s.height * LDArt.hash(Double(k) * 5.1 + 2))
                let r = min(s.width, s.height) * (0.35 + 0.2 * LDArt.hash(Double(k) + 9))
                ctx.fill(LDArt.disc(c, r), with: .radialGradient(Gradient(colors: [LDArt.red.opacity(0.06), .clear]), center: c, startRadius: 0, endRadius: r))
            }
            // Display plinths.
            for (i, b) in blocks.enumerated() {
                let m = min(b.width, b.height)
                ctx.fill(Path(roundedRect: b.offsetBy(dx: m * 0.06, dy: m * 0.09), cornerRadius: m * 0.08), with: .color(.black.opacity(0.5)))
                ctx.fill(Path(roundedRect: b, cornerRadius: m * 0.08),
                         with: .linearGradient(Gradient(colors: [Color(red: 0.62, green: 0.6, blue: 0.58), Color(red: 0.38, green: 0.37, blue: 0.36)]),
                                               startPoint: CGPoint(x: b.minX, y: b.minY), endPoint: CGPoint(x: b.maxX, y: b.maxY)))
                let top = b.insetBy(dx: m * 0.1, dy: m * 0.1)
                ctx.fill(Path(roundedRect: top, cornerRadius: m * 0.05),
                         with: .linearGradient(Gradient(colors: [Color(red: 0.95, green: 0.94, blue: 0.92), Color(red: 0.8, green: 0.79, blue: 0.77)]),
                                               startPoint: CGPoint(x: top.minX, y: top.minY), endPoint: CGPoint(x: top.maxX, y: top.maxY)))
                // Marble veins.
                var vein = Path()
                vein.move(to: CGPoint(x: top.minX + top.width * 0.1, y: top.maxY - top.height * 0.2))
                vein.addQuadCurve(to: CGPoint(x: top.maxX - top.width * 0.15, y: top.minY + top.height * 0.15),
                                  control: CGPoint(x: top.midX + top.width * 0.1 * (LDArt.hash(Double(i)) - 0.5), y: top.midY + top.height * 0.25))
                ctx.stroke(vein, with: .color(Color(white: 0.55).opacity(0.5)), lineWidth: 0.8)
                ctx.stroke(Path(roundedRect: b, cornerRadius: m * 0.08), with: .color(LDArt.ink), lineWidth: 1.2)
                LDArt.treasure(ctx, kind: i, center: CGPoint(x: top.midX, y: top.midY), size: m * 0.46)
                // The glass case over it.
                let glass = top.insetBy(dx: m * 0.05, dy: m * 0.05)
                ctx.stroke(Path(roundedRect: glass, cornerRadius: m * 0.04), with: .color(Color(red: 0.7, green: 0.9, blue: 1).opacity(0.55)), lineWidth: 1)
                var glare = Path()
                glare.move(to: CGPoint(x: glass.minX + glass.width * 0.12, y: glass.minY + glass.height * 0.45))
                glare.addLine(to: CGPoint(x: glass.minX + glass.width * 0.45, y: glass.minY + glass.height * 0.12))
                ctx.stroke(glare, with: .color(.white.opacity(0.45)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
            ctx.fill(Path(full), with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.45)]),
                                                       center: CGPoint(x: s.width / 2, y: s.height / 2),
                                                       startRadius: min(s.width, s.height) * 0.35, endRadius: max(s.width, s.height) * 0.75))
        }
        .allowsHitTesting(false)
    }
}
