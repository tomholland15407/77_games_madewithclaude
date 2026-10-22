//
//  DodgeballGame.swift
//  A Banana Game
//
//  Reflex — a bullet-hell dash for the treasure. A gleaming chest sits near the top of the arena,
//  spewing curtains of bullets in waves: expanding rings, aimed fans, and rotating spirals. Steer
//  the banana with the joystick under the court, UP through the storm, and touch the chest to win.
//  Only the tiny bright core at the banana's center is your hitbox — take a single hit, or run out
//  the clock, and you're back to level 1.
//
//  7 levels: more bullets per wave, faster shots, tighter patterns, and less time to reach it.
//
//  The joystick is the shared `FloatingJoystick`: touch anywhere in the strip under the court and it
//  centres under your thumb; it's tuned to be sensitive (full speed after a short push, brisk light
//  pushes, instant reversals). Its base rests on the left, clear of the page's skip button in the
//  middle. It's a drag, which would fight the feed's vertical pager, so this game sets
//  `locksFeed: true`. (It used to be a drag on the court itself, which hid the banana under your
//  thumb.)
//
//  Drawn as a school gym: a blue padded wall with a scoreboard in amber lights, a honey maple court
//  with painted lines and a banana logo in the centre circle, an open treasure chest heaped with gold
//  and spare balls on the far baseline, every bullet a rubber playground ball (red, blue, green or
//  purple per wave), and a banana in a sweatband with the bright hitbox core. The joystick is a red
//  rubber playground ball on a scoreboard-black base with amber arrow lights.
//

import SwiftUI

enum DodgeballGame {
    static let definition = GameDefinition(
        id: "dodgeball",
        title: "Dodgeball",
        emoji: "🍌",
        genre: .reflex,
        levelCount: 7,
        locksFeed: true,
        manual: GameManual(
            bullets: [
                "Steer the banana with the joystick; only the small bright center dot is a hit.",
                "The treasure chest at the top fires waves of bullets — rings, fans, and spirals.",
                "Weave up through the gaps and touch the chest to win.",
                "One touch, or the clock running out, sends you back to level 1.",
            ],
            bulletsVI: [
                "Lái quả chuối bằng cần điều khiển; chỉ chấm sáng nhỏ ở giữa mới trúng đòn.",
                "Rương báu ở trên bắn từng đợt đạn — vòng, quạt và xoắn ốc.",
                "Luồn lên qua các khe hở và chạm vào rương để thắng.",
                "Chạm một lần, hoặc hết giờ, sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(DodgeballView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct DodgeballView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    // MARK: Difficulty
    private var timeLimit: Double     { [20, 19, 18, 17, 16, 15, 14][min(level, 7) - 1] }
    private var spawnInterval: Double { [0.85, 0.72, 0.60, 0.50, 0.42, 0.35, 0.28][min(level, 7) - 1] }
    private var waveSize: Int         { [10, 13, 16, 20, 24, 28, 34][min(level, 7) - 1] }
    /// Bullet speed as a fraction of the field height per second.
    private var bulletSpeed: CGFloat  { [0.26, 0.30, 0.34, 0.39, 0.44, 0.50, 0.57][min(level, 7) - 1] }
    /// The banana's full-tilt joystick speed, in arena short sides per second.
    private let moveSpeed: CGFloat = 0.9

    private struct Bullet: Identifiable {
        let id = UUID()
        var pos: CGPoint
        var vel: CGVector
        let color: Color
    }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var field: CGSize = .zero
    @State private var player: CGPoint = .zero
    @State private var bullets: [Bullet] = []
    @State private var stick = CGVector.zero      // joystick, −1…1 per axis
    @State private var timeLeft = 0.0
    @State private var spawnTimer = 0.0
    @State private var spiralAngle: Double = 0
    @State private var t: Double = 0
    @State private var built = false
    @State private var demoWaveIdx = 0          // demo: fixed wave sequence instead of random

    /// Rubber playground-ball colours, one per wave (colour is only decoration).
    private let palette: [Color] = [
        Color(red: 0.9, green: 0.16, blue: 0.14),
        Color(red: 0.16, green: 0.42, blue: 0.92),
        Color(red: 0.18, green: 0.68, blue: 0.3),
        Color(red: 0.6, green: 0.3, blue: 0.86),
    ]

    private var chestFrac: CGPoint { CGPoint(x: 0.5, y: 0.17) }

    var body: some View {
        VStack(spacing: 0) {
            scoreboard
                .padding(.top, isDemo ? 6 : 10)
                .padding(.bottom, isDemo ? 6 : 10)
            arena
            FloatingJoystick(vector: $stick, baseSize: isDemo ? 76 : 118, demo: isDemo, active: phase == .play) { push in
                Canvas { ctx, s in DBArt.joystickBase(ctx, size: s, push: push) }
            } knob: {
                DBBallSymbol(color: Color(red: 0.9, green: 0.16, blue: 0.14))
            }
            .frame(height: isDemo ? 76 : 118)
            .padding(.bottom, isDemo ? 8 : 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DBWall().equatable())
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
    }

    /// The gym scoreboard on the padded wall: the goal in amber lights over the clock.
    private var scoreboard: some View {
        VStack(spacing: 6) {
            Text(L("REACH THE TREASURE", "ĐẾN CHỖ BÁU VẬT"))
                .font(.system(size: isDemo ? 13 : 17, weight: .black, design: .monospaced))
                .foregroundStyle(DBArt.led)
                .shadow(color: DBArt.led.opacity(0.7), radius: 4)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !isDemo { timeBar.frame(width: 190, height: 6) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isDemo ? 5 : 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.07)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.4), lineWidth: 2))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.black, lineWidth: 1).padding(2))
    }

    private var arena: some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width
            let h: CGFloat = geo.size.height
            let chest = CGPoint(x: chestFrac.x * w, y: chestFrac.y * h)
            let br: CGFloat = min(w, h) * 0.015
            ZStack {
                DBCourt(size: geo.size, chest: chest, chestSize: min(w, h) * 0.22).equatable()

                // Sparkles over the chest, every ball in flight, and the banana.
                Canvas { ctx, _ in
                    DBArt.sparkles(ctx, chest: chest, size: min(w, h) * 0.22, t: t)
                    let ids = palette.indices
                    for b in bullets {
                        let id = ids.first { palette[$0] == b.color } ?? 0
                        if let ball = ctx.resolveSymbol(id: id) { ctx.draw(ball, at: b.pos) }
                    }
                    let p = player == .zero ? CGPoint(x: w / 2, y: h * 0.85) : player
                    DBArt.sportyBanana(ctx, at: p, width: min(w, h) * 0.15)
                    let hb = min(w, h) * 0.014
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - hb * 2.2, y: p.y - hb * 2.2, width: hb * 4.4, height: hb * 4.4)),
                             with: .radialGradient(Gradient(colors: [.white.opacity(0.75), .white.opacity(0)]), center: p, startRadius: hb * 0.8, endRadius: hb * 2.2))
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - hb, y: p.y - hb, width: hb * 2, height: hb * 2)), with: .color(.white))
                    ctx.stroke(Path(ellipseIn: CGRect(x: p.x - hb, y: p.y - hb, width: hb * 2, height: hb * 2)), with: .color(.black.opacity(0.5)), lineWidth: 0.8)
                } symbols: {
                    ForEach(palette.indices, id: \.self) { i in
                        DBBallSymbol(color: palette[i]).frame(width: br * 2.3, height: br * 2.3).tag(i)
                    }
                }
                .allowsHitTesting(false)
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .onAppear { if field == .zero { field = geo.size } }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, isDemo ? 6 : 10)
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac: Double = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(DBArt.led.opacity(0.15))
                Capsule().fill(frac < 0.3 ? Color(red: 1, green: 0.25, blue: 0.2) : DBArt.led)
                    .frame(width: geo.size.width * max(0, frac))
                    .shadow(color: (frac < 0.3 ? Color.red : DBArt.led).opacity(0.7), radius: 3)
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
            let dt = CGFloat(min(0.05, now.timeIntervalSince(last))); last = now
            step(dt: dt)
        }
    }

    private func setup() {
        player = CGPoint(x: field.width / 2, y: field.height * 0.85)
        bullets = []
        timeLeft = timeLimit
        spawnTimer = 0.5
        spiralAngle = 0
        phase = .play
    }

    private func step(dt: CGFloat) {
        guard phase == .play else { return }
        t += Double(dt)
        let w: CGFloat = field.width, h: CGFloat = field.height
        let margin: CGFloat = h * 0.08
        let hb: CGFloat = min(w, h) * 0.014
        let br: CGFloat = min(w, h) * 0.015

        // Fly with the stick (a fraction of top speed per axis), kept on the court.
        let v = moveSpeed * min(w, h) * dt
        player.x = min(w, max(0, player.x + stick.dx * v))
        player.y = min(h, max(0, player.y + stick.dy * v))

        // Reached the treasure?
        let chest = CGPoint(x: chestFrac.x * w, y: chestFrac.y * h)
        let chestR: CGFloat = min(w, h) * 0.22 * 0.42
        if hypot(player.x - chest.x, player.y - chest.y) < chestR + hb { win(); return }

        // Advance bullets; cull off-field; check hits.
        var survivors: [Bullet] = []
        survivors.reserveCapacity(bullets.count)
        for var b in bullets {
            b.pos.x += b.vel.dx * dt
            b.pos.y += b.vel.dy * dt
            if b.pos.x < -margin || b.pos.x > w + margin || b.pos.y < -margin || b.pos.y > h + margin { continue }
            if hypot(b.pos.x - player.x, b.pos.y - player.y) < hb + br * 0.6 { fail(); return }
            survivors.append(b)
        }
        bullets = survivors

        spawnTimer -= Double(dt)
        if spawnTimer <= 0 {
            spawnTimer = spawnInterval
            fireWave(from: chest)
        }

        timeLeft -= Double(dt)
        if timeLeft <= 0 { fail() }
    }

    // MARK: - Demo (live manual clip)
    // Level 1 on a fixed wave sequence, stepped at a fixed 1/60s through the real `step`. Your
    // thumb on the joystick is a bullet-aware planner: bullets fly straight, so it predicts each one
    // ~0.45s ahead along the banana's path at full stick speed and, among nearby spots that stay
    // clear by a safe margin, heads for its goal (else dives for the most room): it weaves across the
    // lower field through the first waves, then dashes up to the chest. The stick it pushes is what
    // moves the banana, and the real hit test runs every frame.
    private func demoTarget() -> CGPoint {
        let w = field.width, h = field.height, minD = min(w, h)
        let hb = minD * 0.014, br = minD * 0.015
        // Weave across the lower field through the first waves, then make the dash for the chest.
        let chest = t < 2.8 ? CGPoint(x: w * (0.5 + 0.28 * CGFloat(sin(t * 2.2))), y: h * 0.74)
                            : CGPoint(x: chestFrac.x * w, y: chestFrac.y * h)
        let speed = minD * moveSpeed
        let taus: [CGFloat] = [0, 0.1, 0.2, 0.3, 0.45]
        func clearance(_ c: CGPoint) -> CGFloat {
            let dx = c.x - player.x, dy = c.y - player.y, d = hypot(dx, dy)
            var best = CGFloat.infinity
            for tau in taus {
                let k = d > 0.001 ? min(1, tau * speed / d) : 0
                let p = CGPoint(x: player.x + dx * k, y: player.y + dy * k)
                for b in bullets {
                    let q = CGPoint(x: b.pos.x + b.vel.dx * tau, y: b.pos.y + b.vel.dy * tau)
                    best = min(best, hypot(q.x - p.x, q.y - p.y))
                }
            }
            return best
        }
        let safe = hb + br * 0.6 + minD * 0.035
        var cands = [player]
        for r in [0.03, 0.07, 0.12] {
            for k in 0..<16 {
                let a = Double(k) / 16 * 2 * .pi
                cands.append(CGPoint(x: min(w * 0.96, max(w * 0.04, player.x + CGFloat(cos(a)) * minD * r)),
                                     y: min(h * 0.96, max(h * 0.04, player.y + CGFloat(sin(a)) * minD * r))))
            }
        }
        let scored = cands.map { ($0, clearance($0)) }
        if let best = scored.filter({ $0.1 >= safe })
            .min(by: { hypot($0.0.x - chest.x, $0.0.y - chest.y) < hypot($1.0.x - chest.x, $1.0.y - chest.y) }) {
            return best.0
        }
        return scored.max(by: { $0.1 < $1.1 })?.0 ?? player
    }

    private func runDemo() async {
        while field == .zero { try? await Task.sleep(for: .seconds(0.02)) }
        let dt: CGFloat = 1.0 / 60.0
        while !Task.isCancelled {
            demoWaveIdx = 0
            setup()
            try? await Task.sleep(for: .seconds(0.5))
            while !Task.isCancelled && phase == .play {
                // Push the stick toward the planned spot: full tilt when it's far, gentler when close.
                let target = demoTarget()
                let dx = target.x - player.x, dy = target.y - player.y, d = hypot(dx, dy)
                let full = min(field.width, field.height) * moveSpeed * dt
                let k = d > 0.001 ? min(1, d / full) / d : 0
                stick = CGVector(dx: dx * k, dy: dy * k)
                step(dt: dt)
                try? await Task.sleep(for: .seconds(0.016))
            }
            // Touched the chest → the real win() ran (onWin is a no-op). Hold, then loop.
            stick = .zero
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    private func fireWave(from origin: CGPoint) {
        let w: CGFloat = field.width, h: CGFloat = field.height
        let speed: CGFloat = bulletSpeed * h
        // The demo replays a fixed wave sequence (ring → fan → spiral …) so every loop is identical.
        let color = isDemo ? palette[demoWaveIdx % palette.count] : palette.randomElement()!
        let kind = isDemo ? demoWaveIdx % 3 : Int.random(in: 0..<3)
        let demoBase = 0.3 + Double(demoWaveIdx) * 0.7
        if isDemo { demoWaveIdx += 1 }
        switch kind {
        case 0:
            // Expanding ring from the chest.
            let n = waveSize
            let base = isDemo ? demoBase : Double.random(in: 0...(2 * .pi))
            for i in 0..<n {
                let a = base + Double(i) / Double(n) * 2 * .pi
                bullets.append(Bullet(pos: origin,
                                      vel: CGVector(dx: cos(a) * speed, dy: sin(a) * speed), color: color))
            }
        case 1:
            // Aimed fan toward the player.
            let aim = atan2(player.y - origin.y, player.x - origin.x)
            let n = max(5, waveSize / 2)
            let spread = 0.9
            for i in 0..<n {
                let f = n == 1 ? 0.5 : Double(i) / Double(n - 1)
                let a = aim - spread / 2 + spread * f
                bullets.append(Bullet(pos: origin,
                                      vel: CGVector(dx: cos(a) * speed, dy: sin(a) * speed), color: color))
            }
        default:
            // Rotating spiral arms.
            let arms = 3
            let n = max(4, waveSize / arms)
            for k in 0..<arms {
                for i in 0..<n {
                    let a = spiralAngle + Double(k) / Double(arms) * 2 * .pi + Double(i) * 0.12
                    bullets.append(Bullet(pos: origin,
                                          vel: CGVector(dx: cos(a) * speed, dy: sin(a) * speed), color: color))
                }
            }
            spiralAngle += 0.5
        }
        SoundManager.shared.tap()
        _ = w
        if bullets.count > 460 { bullets.removeFirst(bullets.count - 460) }
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

// MARK: - Gym art

private enum DBArt {
    static let led = Color(red: 1.0, green: 0.72, blue: 0.2)
    static let pad = Color(red: 0.13, green: 0.3, blue: 0.66)
    static let line = Color(red: 0.1, green: 0.2, blue: 0.45)
    static let ink = Color(red: 0.12, green: 0.07, blue: 0.03)
    static let gold = Color(red: 1.0, green: 0.8, blue: 0.22)

    static func hash(_ n: Double) -> CGFloat {
        let v: Double = sin(n * 12.9898) * 43758.5453
        return CGFloat(v - floor(v))
    }

    static func disc(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    /// An open treasure chest heaped with gold, gems and spare dodgeballs.
    static func chest(_ ctx: GraphicsContext, at c: CGPoint, size s: CGFloat) {
        ctx.fill(disc(c, s * 0.95), with: .radialGradient(Gradient(colors: [gold.opacity(0.4), gold.opacity(0)]),
                                                         center: c, startRadius: s * 0.1, endRadius: s * 0.95))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.62, y: c.y + s * 0.26, width: s * 1.24, height: s * 0.22)), with: .color(.black.opacity(0.35)))
        let wood = Gradient(colors: [Color(red: 0.66, green: 0.42, blue: 0.2), Color(red: 0.45, green: 0.27, blue: 0.12)])
        let iron = Color(red: 0.25, green: 0.24, blue: 0.26)
        // The lid, flung open behind the body: we see its inside.
        var lid = Path()
        lid.move(to: CGPoint(x: c.x - s * 0.5, y: c.y - s * 0.12))
        lid.addLine(to: CGPoint(x: c.x - s * 0.46, y: c.y - s * 0.56))
        lid.addQuadCurve(to: CGPoint(x: c.x + s * 0.46, y: c.y - s * 0.56), control: CGPoint(x: c.x, y: c.y - s * 0.72))
        lid.addLine(to: CGPoint(x: c.x + s * 0.5, y: c.y - s * 0.12))
        lid.closeSubpath()
        ctx.fill(lid, with: .linearGradient(wood, startPoint: CGPoint(x: c.x, y: c.y - s * 0.6), endPoint: CGPoint(x: c.x, y: c.y - s * 0.1)))
        var lining = Path()
        lining.addRoundedRect(in: CGRect(x: c.x - s * 0.4, y: c.y - s * 0.52, width: s * 0.8, height: s * 0.36), cornerSize: CGSize(width: s * 0.05, height: s * 0.05))
        ctx.fill(lining, with: .color(Color(red: 0.5, green: 0.08, blue: 0.12)))
        ctx.stroke(lid, with: .color(ink), lineWidth: 1.5)
        // The hoard spilling over the rim: coins, two gems and a couple of balls.
        let heap: [(CGFloat, CGFloat, CGFloat)] = [(-0.34, -0.1, 0.1), (-0.18, -0.16, 0.11), (0.0, -0.19, 0.12), (0.18, -0.15, 0.11),
                                                    (0.34, -0.1, 0.1), (-0.26, -0.05, 0.1), (0.26, -0.05, 0.1), (-0.08, -0.08, 0.1), (0.1, -0.08, 0.1)]
        for (i, h) in heap.enumerated() {
            let p = CGPoint(x: c.x + h.0 * s, y: c.y + h.1 * s)
            ctx.fill(disc(p, h.2 * s), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.96, blue: 0.6), gold, Color(red: 0.75, green: 0.5, blue: 0.08)]),
                                                            center: CGPoint(x: p.x - h.2 * s * 0.3, y: p.y - h.2 * s * 0.3), startRadius: 0, endRadius: h.2 * s * 1.3))
            ctx.stroke(disc(p, h.2 * s), with: .color(Color(red: 0.55, green: 0.36, blue: 0.05)), lineWidth: 0.8)
            if i == 2 {
                ctx.fill(disc(CGPoint(x: p.x - s * 0.13, y: p.y - s * 0.04), s * 0.09), with: .color(Color(red: 0.88, green: 0.18, blue: 0.15)))
                ctx.fill(disc(CGPoint(x: p.x + s * 0.15, y: p.y - s * 0.03), s * 0.08), with: .color(Color(red: 0.2, green: 0.45, blue: 0.92)))
            }
        }
        var gem = Path()
        gem.move(to: CGPoint(x: c.x + s * 0.33, y: c.y - s * 0.31))
        gem.addLine(to: CGPoint(x: c.x + s * 0.4, y: c.y - s * 0.23))
        gem.addLine(to: CGPoint(x: c.x + s * 0.33, y: c.y - s * 0.14))
        gem.addLine(to: CGPoint(x: c.x + s * 0.26, y: c.y - s * 0.23))
        gem.closeSubpath()
        ctx.fill(gem, with: .linearGradient(Gradient(colors: [Color(red: 0.75, green: 0.96, blue: 1), Color(red: 0.2, green: 0.6, blue: 0.92)]),
                                            startPoint: CGPoint(x: c.x, y: c.y - s * 0.31), endPoint: CGPoint(x: c.x, y: c.y - s * 0.14)))
        // The front of the chest: planks, iron corner bands and the gold lock plate.
        let front = CGRect(x: c.x - s * 0.52, y: c.y - s * 0.08, width: s * 1.04, height: s * 0.42)
        ctx.fill(Path(roundedRect: front, cornerRadius: s * 0.05), with: .linearGradient(wood, startPoint: CGPoint(x: c.x, y: front.minY), endPoint: CGPoint(x: c.x, y: front.maxY)))
        var planks = Path()
        for k in 1...2 {
            let y = front.minY + front.height * CGFloat(k) / 3
            planks.move(to: CGPoint(x: front.minX + 2, y: y))
            planks.addLine(to: CGPoint(x: front.maxX - 2, y: y))
        }
        ctx.stroke(planks, with: .color(ink.opacity(0.45)), lineWidth: 1)
        for x in [front.minX, front.maxX - s * 0.12] {
            ctx.fill(Path(roundedRect: CGRect(x: x, y: front.minY, width: s * 0.12, height: front.height), cornerRadius: s * 0.03), with: .color(iron))
            ctx.fill(disc(CGPoint(x: x + s * 0.06, y: front.minY + front.height * 0.25), s * 0.022), with: .color(Color(white: 0.6)))
            ctx.fill(disc(CGPoint(x: x + s * 0.06, y: front.maxY - front.height * 0.25), s * 0.022), with: .color(Color(white: 0.6)))
        }
        ctx.fill(Path(CGRect(x: front.minX, y: front.minY, width: front.width, height: s * 0.07)), with: .color(gold.shade(0.1)))
        let lock = CGRect(x: c.x - s * 0.09, y: front.minY + s * 0.02, width: s * 0.18, height: s * 0.2)
        ctx.fill(Path(roundedRect: lock, cornerRadius: s * 0.03), with: .color(gold))
        ctx.stroke(Path(roundedRect: lock, cornerRadius: s * 0.03), with: .color(ink), lineWidth: 1)
        ctx.fill(disc(CGPoint(x: lock.midX, y: lock.midY), s * 0.028), with: .color(ink))
        ctx.stroke(Path(roundedRect: front, cornerRadius: s * 0.05), with: .color(ink), lineWidth: 1.5)
    }

    /// Two twinkles over the gold, pulsing out of step.
    static func sparkles(_ ctx: GraphicsContext, chest c: CGPoint, size s: CGFloat, t: Double) {
        let a = 0.5 + 0.5 * sin(t * 4)
        for (dx, dy, r, k) in [(-0.44, -0.46, 0.09, a), (0.46, -0.02, 0.06, 1 - a)] as [(CGFloat, CGFloat, CGFloat, Double)] {
            let p = CGPoint(x: c.x + dx * s, y: c.y + dy * s)
            var star = Path()
            for i in 0..<8 {
                let ang = Double(i) * .pi / 4
                let rr = i % 2 == 0 ? r * s : r * s * 0.28
                let q = CGPoint(x: p.x + CGFloat(cos(ang)) * rr, y: p.y + CGFloat(sin(ang)) * rr)
                if i == 0 { star.move(to: q) } else { star.addLine(to: q) }
            }
            star.closeSubpath()
            ctx.fill(star, with: .color(.white.opacity(k)))
        }
    }

    /// The joystick's base: a scoreboard-black rubber disc in a grey bezel with four amber arrow lights;
    /// the ones the stick is pushed toward glow.
    static func joystickBase(_ ctx: GraphicsContext, size s: CGSize, push: CGVector) {
        let c = CGPoint(x: s.width / 2, y: s.height / 2)
        let r = min(s.width, s.height) / 2 - 2
        ctx.fill(disc(CGPoint(x: c.x, y: c.y + 3), r), with: .color(.black.opacity(0.35)))
        ctx.fill(disc(c, r), with: .radialGradient(Gradient(colors: [Color(white: 0.2), Color(white: 0.05)]),
                                                   center: CGPoint(x: c.x, y: c.y - r * 0.3), startRadius: 0, endRadius: r * 1.2))
        ctx.stroke(disc(c, r), with: .color(.black), lineWidth: 3)
        ctx.stroke(disc(c, r - 4), with: .color(Color(white: 0.4)), lineWidth: 1.5)
        for k in 0..<4 {
            let a = Double(k) * .pi / 2 - .pi / 2               // up, right, down, left
            let dx = CGFloat(cos(a)), dy = CGFloat(sin(a))
            let glow = Double(max(0, push.dx * dx + push.dy * dy))
            let tip = CGPoint(x: c.x + dx * r * 0.84, y: c.y + dy * r * 0.84)
            let back = CGPoint(x: c.x + dx * r * 0.66, y: c.y + dy * r * 0.66)
            var arrow = Path()
            arrow.move(to: tip)
            arrow.addLine(to: CGPoint(x: back.x - dy * r * 0.13, y: back.y + dx * r * 0.13))
            arrow.addLine(to: CGPoint(x: back.x + dy * r * 0.13, y: back.y - dx * r * 0.13))
            arrow.closeSubpath()
            if glow > 0.05 {
                ctx.fill(disc(CGPoint(x: (tip.x + back.x) / 2, y: (tip.y + back.y) / 2), r * 0.2),
                         with: .radialGradient(Gradient(colors: [led.opacity(0.55 * glow), led.opacity(0)]),
                                               center: CGPoint(x: (tip.x + back.x) / 2, y: (tip.y + back.y) / 2), startRadius: 0, endRadius: r * 0.2))
            }
            ctx.fill(arrow, with: .color(led.opacity(0.28 + 0.72 * glow)))
        }
    }

    /// The banana player: a plump banana in a red sweatband, its body running through the hitbox.
    static func sportyBanana(_ ctx: GraphicsContext, at p: CGPoint, width w: CGFloat) {
        let h = w * 0.45
        let c = CGPoint(x: p.x, y: p.y - h * 0.043)
        var body = Path()
        body.move(to: CGPoint(x: c.x - w * 0.5, y: c.y - h * 0.4))
        body.addQuadCurve(to: CGPoint(x: c.x + w * 0.5, y: c.y - h * 0.5), control: CGPoint(x: c.x - w * 0.02, y: c.y + h * 1.05))
        body.addQuadCurve(to: CGPoint(x: c.x - w * 0.5, y: c.y - h * 0.4), control: CGPoint(x: c.x, y: c.y + h * 0.02))
        body.closeSubpath()
        ctx.fill(body.offsetBy(dx: w * 0.04, dy: h * 0.25), with: .color(.black.opacity(0.3)))
        ctx.fill(body, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.5), Color(red: 1, green: 0.84, blue: 0.2),
                                                               Color(red: 0.86, green: 0.62, blue: 0.08)]),
                                             startPoint: CGPoint(x: c.x, y: c.y - h * 0.3), endPoint: CGPoint(x: c.x, y: c.y + h * 0.4)))
        var band = ctx
        band.clip(to: body)
        band.fill(Path(CGRect(x: c.x + w * 0.2, y: c.y - h, width: w * 0.11, height: h * 2)), with: .color(Color(red: 0.9, green: 0.15, blue: 0.15)))
        band.fill(Path(CGRect(x: c.x + w * 0.235, y: c.y - h, width: w * 0.03, height: h * 2)), with: .color(.white))
        for y in [-0.25, -0.07] as [CGFloat] {
            ctx.fill(Path(ellipseIn: CGRect(x: c.x + w * 0.1, y: c.y + h * y, width: w * 0.06, height: h * 0.13)), with: .color(ink))
        }
        ctx.stroke(body, with: .color(Color(red: 0.4, green: 0.26, blue: 0.04)), lineWidth: max(1.2, w * 0.035))
        ctx.fill(Path(roundedRect: CGRect(x: c.x - w * 0.6, y: c.y - h * 0.5, width: w * 0.13, height: h * 0.2), cornerRadius: w * 0.02),
                 with: .color(Color(red: 0.42, green: 0.28, blue: 0.1)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x + w * 0.45, y: c.y - h * 0.57, width: w * 0.08, height: h * 0.15)),
                 with: .color(Color(red: 0.3, green: 0.2, blue: 0.05)))
    }
}

/// One rubber playground ball (drawn once per colour, then stamped for every ball in flight).
private struct DBBallSymbol: View {
    let color: Color

    var body: some View {
        Canvas { ctx, s in
            let r = min(s.width, s.height) / 2 * 0.86
            let c = CGPoint(x: s.width / 2 - r * 0.06, y: s.height / 2 - r * 0.08)
            ctx.fill(DBArt.disc(CGPoint(x: c.x + r * 0.14, y: c.y + r * 0.22), r), with: .color(.black.opacity(0.3)))
            ctx.fill(DBArt.disc(c, r), with: .radialGradient(Gradient(colors: [color.lit(0.45), color, color.shade(0.4)]),
                                                            center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4), startRadius: 0, endRadius: r * 1.5))
            // The moulded seam round the ball.
            var seam = Path()
            seam.addArc(center: CGPoint(x: c.x + r * 0.9, y: c.y - r * 0.9), radius: r * 1.45, startAngle: .degrees(100), endAngle: .degrees(172), clockwise: false)
            ctx.stroke(seam, with: .color(color.shade(0.5)), lineWidth: max(0.7, r * 0.16))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.55, y: c.y - r * 0.6, width: r * 0.45, height: r * 0.32)), with: .color(.white.opacity(0.75)))
            ctx.stroke(DBArt.disc(c, r), with: .color(.black.opacity(0.55)), lineWidth: 0.8)
        }
    }
}

/// The gym's blue padded wall behind the scoreboard and round the court (static).
private struct DBWall: View, Equatable {
    var body: some View {
        Canvas { ctx, s in
            ctx.fill(Path(CGRect(origin: .zero, size: s)), with: .color(DBArt.pad.shade(0.25)))
            let pw: CGFloat = 46
            var x: CGFloat = -8
            while x < s.width {
                let r = CGRect(x: x + 1.5, y: -10, width: pw - 3, height: s.height + 20)
                ctx.fill(Path(roundedRect: r, cornerRadius: 8), with: .linearGradient(Gradient(colors: [DBArt.pad.lit(0.12), DBArt.pad, DBArt.pad.shade(0.18)]),
                                                                                      startPoint: CGPoint(x: r.minX, y: 0), endPoint: CGPoint(x: r.maxX, y: 0)))
                ctx.fill(Path(roundedRect: CGRect(x: r.minX + 5, y: r.minY, width: 3, height: r.height), cornerRadius: 1.5), with: .color(.white.opacity(0.12)))
                x += pw
            }
        }
        .allowsHitTesting(false)
    }
}

/// The court: honey maple boards, painted lines with a banana logo in the centre circle, and the
/// treasure chest on the far baseline (static; the sparkles and balls are drawn live on top).
private struct DBCourt: View, Equatable {
    let size: CGSize
    let chest: CGPoint
    let chestSize: CGFloat

    var body: some View {
        Canvas { ctx, s in
            let full = CGRect(origin: .zero, size: s)
            ctx.fill(Path(full), with: .color(Color(red: 0.88, green: 0.7, blue: 0.45)))
            // Boards along the court, each a touch different, with staggered end joints and grain.
            let bw = max(18, s.width / 11)
            var x: CGFloat = 0
            var k = 0
            while x < s.width {
                let tint = DBArt.hash(Double(k) * 1.3)
                let col = Color(red: 0.86 + 0.06 * Double(tint), green: 0.66 + 0.06 * Double(tint), blue: 0.4 + 0.05 * Double(tint))
                ctx.fill(Path(CGRect(x: x, y: 0, width: bw, height: s.height)), with: .color(col))
                var grain = Path()
                for g in 0..<3 {
                    let gx = x + bw * (0.25 + 0.25 * CGFloat(g))
                    grain.move(to: CGPoint(x: gx, y: 0))
                    grain.addCurve(to: CGPoint(x: gx + bw * 0.08, y: s.height), control1: CGPoint(x: gx - bw * 0.12, y: s.height * 0.35), control2: CGPoint(x: gx + bw * 0.15, y: s.height * 0.65))
                }
                ctx.stroke(grain, with: .color(Color(red: 0.62, green: 0.42, blue: 0.2).opacity(0.18)), lineWidth: 0.8)
                var seam = Path()
                seam.move(to: CGPoint(x: x, y: 0)); seam.addLine(to: CGPoint(x: x, y: s.height))
                let jy = s.height * DBArt.hash(Double(k) * 2.9 + 4)
                seam.move(to: CGPoint(x: x, y: jy)); seam.addLine(to: CGPoint(x: x + bw, y: jy))
                ctx.stroke(seam, with: .color(Color(red: 0.55, green: 0.36, blue: 0.16).opacity(0.45)), lineWidth: 1)
                x += bw; k += 1
            }
            // Varnish sheen.
            ctx.fill(Path(full), with: .linearGradient(Gradient(colors: [.white.opacity(0.14), .clear, .white.opacity(0.08)]),
                                                       startPoint: .zero, endPoint: CGPoint(x: s.width, y: s.height)))
            // Painted lines: boundary, centre line and circle, two attack lines.
            let inset = min(s.width, s.height) * 0.045
            let court = full.insetBy(dx: inset, dy: inset)
            ctx.stroke(Path(court), with: .color(DBArt.line), lineWidth: 3)
            var mid = Path()
            mid.move(to: CGPoint(x: court.minX, y: s.height * 0.5)); mid.addLine(to: CGPoint(x: court.maxX, y: s.height * 0.5))
            ctx.stroke(mid, with: .color(DBArt.line), lineWidth: 3)
            let cr = min(s.width, s.height) * 0.14
            let cc = CGPoint(x: s.width / 2, y: s.height * 0.5)
            ctx.fill(DBArt.disc(cc, cr), with: .color(Color(red: 0.95, green: 0.8, blue: 0.3).opacity(0.35)))
            ctx.stroke(DBArt.disc(cc, cr), with: .color(DBArt.line), lineWidth: 3)
            var attack = Path()
            for fy in [0.3, 0.7] as [CGFloat] {
                attack.move(to: CGPoint(x: court.minX, y: s.height * fy)); attack.addLine(to: CGPoint(x: court.maxX, y: s.height * fy))
            }
            ctx.stroke(attack, with: .color(Color(red: 0.85, green: 0.2, blue: 0.15).opacity(0.8)), style: StrokeStyle(lineWidth: 2, dash: [10, 7]))
            // The home team's banana painted in the centre circle.
            var logo = ctx
            logo.opacity = 0.55
            var ban = Path()
            let lw = cr * 1.2, lh = lw * 0.42
            ban.move(to: CGPoint(x: cc.x - lw * 0.5, y: cc.y - lh * 0.5))
            ban.addQuadCurve(to: CGPoint(x: cc.x + lw * 0.5, y: cc.y - lh * 0.6), control: CGPoint(x: cc.x, y: cc.y + lh * 1.1))
            ban.addQuadCurve(to: CGPoint(x: cc.x - lw * 0.5, y: cc.y - lh * 0.5), control: CGPoint(x: cc.x, y: cc.y + lh * 0.05))
            ban.closeSubpath()
            logo.fill(ban, with: .color(Color(red: 1, green: 0.84, blue: 0.1)))
            logo.stroke(ban, with: .color(DBArt.line), lineWidth: 2)
            DBArt.chest(ctx, at: chest, size: chestSize)
            ctx.fill(Path(full), with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.28)]),
                                                       center: CGPoint(x: s.width / 2, y: s.height * 0.45),
                                                       startRadius: min(s.width, s.height) * 0.4, endRadius: max(s.width, s.height) * 0.75))
        }
        .allowsHitTesting(false)
    }
}
