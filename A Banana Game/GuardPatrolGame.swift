//
//  GuardPatrolGame.swift
//  A Banana Game
//
//  Brain / stealth — the non-combat cousin of Assassin. Sneak from the entrance at the bottom
//  up to the banana VAULT at the top, threading between the guards' sweeping vision cones. Hold
//  a direction button to creep; step into any red cone and you're spotted — back to level 1.
//  Reach the vault before the clock runs out to win. 7 levels: more guards, faster sweeps, wider
//  cones, and patrolling (not just pivoting) guards — near-impossible by L6–7.
//
//  Drawn as a high-tech vault facility: dark floor panels, hazard-striped side walls holding the
//  sentry turrets (they glow red and fire tracers once the alarm is up), robot sentries sweeping red
//  scanner cones (exactly the old cones), a steel vault chamber — exactly the win box — with a golden
//  banana inside, the entrance lift, and a masked banana thief drawn inside the box the win check
//  uses. The "REACH THE VAULT" line became an alarm lamp of the same height (so the field keeps its
//  size). The facility is an Equatable view; everything that moves is one Canvas.
//

import SwiftUI

enum GuardPatrolGame {
    static let definition = GameDefinition(
        id: "guard-patrol",
        title: "Guard Patrol",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Hold a direction button to creep the banana from the bottom into the vault box at the top.",
                "The whole banana must be inside the vault.",
                "Stay out of the red vision cones — get spotted and the alarm trips.",
                "Then the edge guns open a fierce curtain; a bullet or the clock sends you to level 1.",
            ],
            bulletsVI: [
                "Giữ nút hướng để đưa quả chuối từ dưới lên vào ô két sắt ở trên.",
                "Cả quả chuối phải nằm trọn trong két.",
                "Tránh xa các tầm nhìn đỏ — bị phát hiện là báo động.",
                "Khi đó súng hai bên xả một màn đạn; trúng đạn hoặc hết giờ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(GuardPatrolView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct GuardPatrolView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void
    @Environment(\.isDemo) private var isDemo

    // Difficulty shifted up: the old level 3 is roughly the new level 1, extended past the old top
    // for the new L6–7 (the first two levels used to be near-trivial).
    private var guardN: Int        { [3, 3, 4, 4, 5, 5, 6][min(level, 7) - 1] }
    private var sweepSpeed: Double { [1.3, 1.5, 1.7, 1.9, 2.1, 2.3, 2.5][min(level, 7) - 1] }
    private var coneHalfDeg: Double { [29, 32, 35, 38, 42, 45, 48][min(level, 7) - 1] }
    private var coneRange: CGFloat { [0.30, 0.33, 0.36, 0.39, 0.43, 0.46, 0.50][min(level, 7) - 1] }
    private var movingN: Int       { min(guardN, level) }
    private var timeLimit: Double  { [26, 24, 22, 20, 18, 17, 16][min(level, 7) - 1] }
    private let playerSpeed: CGFloat = 0.36

    private struct Guard: Identifiable {
        let id = UUID()
        var center: CGPoint
        let baseFacing: Double
        let swing: Double
        let moving: Bool
        let patrolHalf: CGFloat
        var t: Double

        /// The cone's current facing: pivoting guards sweep with sin; patrolling guards face
        /// along their motion.
        var currentFacing: Double {
            moving ? (cos(t) >= 0 ? 0 : .pi) : baseFacing + sin(t) * swing
        }

        /// Current position (fractions). Patrolling guards slide horizontally around their base
        /// center; pivoting guards stay put.
        var displayCenter: CGPoint {
            guard moving else { return center }
            let clampedBase = min(0.92 - patrolHalf, max(0.08 + patrolHalf, center.x))
            return CGPoint(x: clampedBase + CGFloat(sin(t)) * patrolHalf, y: center.y)
        }
    }

    /// A tracer round from one of the flanking edge guns that open fire once the alarm is raised.
    private struct SideBullet: Identifiable { let id = UUID(); var pos: CGPoint; var vx: CGFloat }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var guards: [Guard] = []
    @State private var player = CGPoint(x: 0.5, y: 0.92)
    @State private var moveDir = CGVector(dx: 0, dy: 0)
    @State private var timeLeft = 0.0
    @State private var area = CGSize.zero
    @State private var loopTask: Task<Void, Never>?
    @State private var built = false
    // Raised the instant a cone catches the banana: the flanking guns open fire (getting spotted
    // no longer fails instantly — you must now run the gauntlet to the vault).
    @State private var alerted = false
    @State private var bullets: [SideBullet] = []
    @State private var fireAcc = 0.0

    // The vault sits at the top-center; win requires the WHOLE banana inside this tight box.
    private let vaultCenterY: CGFloat = 0.09
    private let vaultHalfX: CGFloat = 0.11
    private let vaultHalfY: CGFloat = 0.07

    // Invisible side walls just inside the gun columns: the banana can never reach the guns, so
    // it can't hug the extreme edge to sneak straight up past the guards.
    private let wallX: CGFloat = 0.12

    // Flanking guns: a column down each far edge that fire a fierce horizontal curtain when alerted.
    private let gunYs: [CGFloat] = [0.14, 0.24, 0.34, 0.44, 0.54, 0.64, 0.74, 0.84]
    private let bulletSpeed: CGFloat = 0.85
    private let fireInterval: Double = 0.16
    private var fireProb: Double { min(0.75, 0.42 + Double(level) * 0.05) }

    var body: some View {
        VStack(spacing: 8) {
            // The alarm lamp: dark until a cone catches the banana, then red. (It keeps the old
            // header's height, so the field — and so the cones' reach across it — is unchanged.)
            GPAlarmLamp(on: alerted)
                .frame(width: isDemo ? 18 : 24, height: isDemo ? 18 : 24)
                .padding(.top, isDemo ? 6 : 0)
            if !isDemo { timeBar.frame(height: 5).padding(.horizontal, 56) }

            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let m = min(w, h)
                ZStack {
                    // Floor panels, side walls, the vault chamber and the entrance never move: drawn once.
                    GPFacility(size: geo.size, wallX: wallX, vaultCenterY: vaultCenterY, vaultHalfX: vaultHalfX, vaultHalfY: vaultHalfY)
                        .equatable()

                    // Turrets, tracers, scanner cones, the sentry bots and the thief: one Canvas.
                    Canvas { ctx, _ in
                        let gunW = m * 0.045
                        for gy in gunYs {
                            GPArt.turret(ctx, at: CGPoint(x: 0.02 * w, y: gy * h), size: gunW, facingRight: true, alerted: alerted)
                            GPArt.turret(ctx, at: CGPoint(x: 0.98 * w, y: gy * h), size: gunW, facingRight: false, alerted: alerted)
                        }
                        for b in bullets {
                            GPArt.tracer(ctx, at: CGPoint(x: b.pos.x * w, y: b.pos.y * h), dir: b.vx >= 0 ? 1 : -1, size: m)
                        }
                        let range = coneRange * m
                        let half = coneHalfDeg * .pi / 180
                        for g in guards {
                            let dc = g.displayCenter
                            GPArt.cone(ctx, at: CGPoint(x: dc.x * w, y: dc.y * h), facing: g.currentFacing, half: half, range: range)
                        }
                        for g in guards {
                            let dc = g.displayCenter
                            GPArt.sentry(ctx, at: CGPoint(x: dc.x * w, y: dc.y * h), facing: g.currentFacing, size: m * 0.05, moving: g.moving)
                        }
                        GPArt.thief(ctx, at: CGPoint(x: player.x * w, y: player.y * h), size: m * 0.06)
                        if alerted {
                            ctx.stroke(Path(roundedRect: CGRect(x: 2, y: 2, width: w - 4, height: h - 4), cornerRadius: 12),
                                       with: .color(Color(red: 1, green: 0.2, blue: 0.2).opacity(0.8)), lineWidth: 4)
                        }
                    }
                    .allowsHitTesting(false)
                }
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .onAppear { area = geo.size }
                .onChange(of: geo.size) { _, v in area = v }
            }
            .padding(.horizontal, isDemo ? 8 : 0)

            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.05, green: 0.06, blue: 0.09))
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
    }

    @ViewBuilder
    private var controls: some View {
        if isDemo {
            // The squat demo card can't spare a 2-row cross: same four buttons, one row.
            HStack(spacing: 6) {
                holdBtn("chevron.left", CGVector(dx: -1, dy: 0))
                holdBtn("chevron.up", CGVector(dx: 0, dy: -1))
                holdBtn("chevron.down", CGVector(dx: 0, dy: 1))
                holdBtn("chevron.right", CGVector(dx: 1, dy: 0))
            }
            .padding(.bottom, 6)
        } else {
            VStack(spacing: 6) {
                holdBtn("chevron.up", CGVector(dx: 0, dy: -1))
                HStack(spacing: 6) {
                    holdBtn("chevron.left", CGVector(dx: -1, dy: 0))
                    holdBtn("chevron.down", CGVector(dx: 0, dy: 1))
                    holdBtn("chevron.right", CGVector(dx: 1, dy: 0))
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func holdBtn(_ icon: String, _ d: CGVector) -> some View {
        // In the demo the held arrow lights up (the planner drives moveDir directly).
        let lit = isDemo && moveDir == d
        return Image(systemName: icon)
            .font(.system(size: isDemo ? 18 : 22, weight: .heavy)).foregroundStyle(lit ? Color(red: 0.2, green: 0.12, blue: 0) : .white)
            .frame(width: isDemo ? 56 : 62, height: isDemo ? 32 : 50)
            .background(GPKey(lit: lit))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(lit ? 0.9 : 1)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if phase == .play { moveDir = d } }
                .onEnded { _ in moveDir = CGVector(dx: 0, dy: 0) })
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(frac < 0.3 ? Color(red: 1, green: 0.3, blue: 0.26) : Color(red: 0.4, green: 0.85, blue: 1))
                    .frame(width: geo.size.width * frac)
            }
        }
    }

    // MARK: - Flow
    private func run() async {
        if !built { setup(); built = true }
        var last = Date(); let start = Date()
        loopTask = Task {
            while !Task.isCancelled && phase == .play {
                try? await Task.sleep(for: .seconds(0.016))
                let now = Date()
                let dt = min(0.05, now.timeIntervalSince(last)); last = now
                timeLeft = max(0, timeLimit - now.timeIntervalSince(start))
                if timeLeft <= 0 { fail(); break }
                step(dt: CGFloat(dt), rate: dt)
            }
        }
    }

    private func setup() {
        player = CGPoint(x: 0.5, y: 0.92)
        moveDir = CGVector(dx: 0, dy: 0)
        var gs: [Guard] = []
        // Spread guards across the middle bands so there's always a gap to time.
        for i in 0..<guardN {
            let band = CGFloat(i) / CGFloat(max(1, guardN))
            let y = 0.24 + band * 0.5 + CGFloat.random(in: -0.03...0.03)
            // Spread across nearly the full playable width so the corridors next to the walls are
            // covered too — no free lane up the edge.
            let x = CGFloat.random(in: (wallX + 0.03)...(1 - wallX - 0.03))
            let moving = i < movingN
            gs.append(Guard(center: CGPoint(x: x, y: y),
                            baseFacing: moving ? 0 : Double.random(in: 0...(2 * .pi)),
                            swing: moving ? 0 : Double.random(in: 0.7...1.1),
                            moving: moving,
                            patrolHalf: CGFloat.random(in: 0.18...0.30),
                            t: Double.random(in: 0...(2 * .pi))))
        }
        guards = gs
        alerted = false; bullets = []; fireAcc = 0
        timeLeft = timeLimit; phase = .play
    }

    // MARK: - Demo (live manual clip)
    // A fixed level-1 room (three guards: one patrolling, two pivoting) played through the real
    // `step` at a fixed 1/60s. The banana creeps ▲ up the middle; a planner looks 0.45s ahead with
    // every cone widened 12% / 8° and, when a sweep is about to cross its lane, lets go and freezes
    // (resuming only after ≥10 frames, so the press reads) — then slips up into the vault.
    // Checked offline on a port of `step` at 9 card sizes (300–360 × 220–280pt): exactly one
    // mid-route freeze, never seen, in the vault in < 5.5s — and a straight dash up gets spotted
    // at every size, so the wait is what wins it.
    private static let demoGuards: [(cx: CGFloat, cy: CGFloat, base: Double, swing: Double,
                                     moving: Bool, half: CGFloat, t: Double)] = [
        (0.2457, 0.2113, 0.0, 0.0, true, 0.251, 4.4174),
        (0.1688, 0.4021, 0.9688, 0.757, false, 0.2998, 5.9271),
        (0.5013, 0.549, 3.1613, 0.7753, false, 0.2389, 5.3294)
    ]

    /// Would the banana at `p` be inside any (margin-widened) cone `k` frames from now?
    private func demoSeen(_ p: CGPoint, framesAhead k: Int) -> Bool {
        let w = area.width, h = area.height
        let range = coneRange * min(w, h) * 1.12
        let half = coneHalfDeg * .pi / 180 + 8 * .pi / 180
        for g0 in guards {
            var g = g0
            g.t += Double(k) / 60.0 * sweepSpeed
            let dc = g.displayCenter
            let dx = (p.x - dc.x) * w, dy = (p.y - dc.y) * h
            let dist = hypot(dx, dy)
            if dist > range || dist < 0.0001 { continue }
            var diff = atan2(dy, dx) - g.currentFacing
            while diff > .pi { diff -= 2 * .pi }
            while diff < -.pi { diff += 2 * .pi }
            if abs(diff) <= half { return true }
        }
        return false
    }

    /// Planner: climb if the next 0.45s of climbing stays clear, else hold still if that's clear,
    /// else back off.
    private func demoWant() -> CGFloat {
        func clear(_ dy: CGFloat) -> Bool {
            for k in 1...27 {
                let q = CGPoint(x: player.x, y: min(0.97, max(0.03, player.y + dy * playerSpeed * CGFloat(k) / 60)))
                if demoSeen(q, framesAhead: k) { return false }
            }
            return true
        }
        if clear(-1) { return -1 }
        if clear(0) { return 0 }
        if clear(1) { return 1 }
        return 0
    }

    private func runDemo() async {
        while !Task.isCancelled {
            player = CGPoint(x: 0.5, y: 0.92)
            moveDir = CGVector(dx: 0, dy: 0)
            guards = Self.demoGuards.map {
                Guard(center: CGPoint(x: $0.cx, y: $0.cy), baseFacing: $0.base, swing: $0.swing,
                      moving: $0.moving, patrolHalf: $0.half, t: $0.t)
            }
            alerted = false; bullets = []; fireAcc = 0
            timeLeft = timeLimit; phase = .play; built = true
            try? await Task.sleep(for: .seconds(0.5))        // (also lets `area` settle)
            var frame = 0, state: CGFloat? = nil, last = 0
            while !Task.isCancelled && phase == .play && frame < 900 {
                frame += 1
                let want = demoWant()
                if state == nil { state = want; last = frame }
                else if want != state, frame - last >= 10 || want != -1 { state = want; last = frame }
                moveDir = CGVector(dx: 0, dy: state ?? 0)
                step(dt: 1.0 / 60.0, rate: 1.0 / 60.0)
                try? await Task.sleep(for: .seconds(0.016))
            }
            // Whole banana inside the vault → the real win() ran (onWin is a no-op). Hold, then loop.
            moveDir = CGVector(dx: 0, dy: 0)
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    private func step(dt: CGFloat, rate: Double) {
        // Move guards.
        for i in guards.indices {
            guards[i].t += rate * sweepSpeed
        }
        // Move player.
        let mag = hypot(moveDir.dx, moveDir.dy)
        if mag > 0 {
            player.x = min(1 - wallX, max(wallX, player.x + moveDir.dx / mag * playerSpeed * dt))
            player.y = min(0.97, max(0.03, player.y + moveDir.dy / mag * playerSpeed * dt))
        }

        guard area.width > 1, area.height > 1 else { return }
        let w = area.width, h = area.height

        // Win: the WHOLE banana must sit inside the vault box (shrink the box by the banana's
        // half-size, converted from points to fractions, so the sprite is fully enclosed).
        let bananaHalf = min(w, h) * 0.03
        let bhx = bananaHalf / w, bhy = bananaHalf / h
        if abs(player.x - 0.5) <= vaultHalfX - bhx && abs(player.y - vaultCenterY) <= vaultHalfY - bhy {
            win(); return
        }

        // Detection raises the alarm (once) instead of failing outright.
        if !alerted {
            let range = coneRange * min(w, h)
            let half = coneHalfDeg * .pi / 180
            let pp = CGPoint(x: player.x * w, y: player.y * h)
            for g in guards {
                let dc = g.displayCenter
                let gc = CGPoint(x: dc.x * w, y: dc.y * h)
                let dx = pp.x - gc.x, dy = pp.y - gc.y
                let dist = hypot(dx, dy)
                if dist > range || dist < 0.0001 { continue }
                var diff = atan2(dy, dx) - g.currentFacing
                while diff > .pi { diff -= 2 * .pi }
                while diff < -.pi { diff += 2 * .pi }
                if abs(diff) <= half {
                    alerted = true
                    SoundManager.shared.error(); Haptics.warning()
                    break
                }
            }
        }

        // Once alerted, the flanking guns pour a fierce horizontal curtain across the field.
        guard alerted else { return }
        fireAcc += rate
        if fireAcc >= fireInterval {
            fireAcc = 0
            for gy in gunYs {
                if Double.random(in: 0...1) < fireProb {
                    bullets.append(SideBullet(pos: CGPoint(x: 0.03, y: gy), vx: bulletSpeed))
                }
                if Double.random(in: 0...1) < fireProb {
                    bullets.append(SideBullet(pos: CGPoint(x: 0.97, y: gy), vx: -bulletSpeed))
                }
            }
            SoundManager.shared.tap()
        }
        for i in bullets.indices { bullets[i].pos.x += bullets[i].vx * dt }
        bullets.removeAll { $0.pos.x < -0.05 || $0.pos.x > 1.05 }
        for b in bullets where abs(b.pos.x - player.x) < 0.028 && abs(b.pos.y - player.y) < 0.03 {
            fail(); return
        }
    }

    private func win() {
        guard phase != .done else { return }
        phase = .done; loopTask?.cancel()
        Haptics.success(); SoundManager.shared.tap()
        onWin()
    }
    private func fail() {
        guard phase != .done else { return }
        phase = .done; loopTask?.cancel()
        SoundManager.shared.error()
        onFail()
    }
}

// MARK: - Vault-facility art

private enum GPArt {
    static let red = Color(red: 1, green: 0.22, blue: 0.22)

    /// A wall-mounted sentry turret; it glows red and flashes once the alarm is up.
    static func turret(_ ctx: GraphicsContext, at p: CGPoint, size s: CGFloat, facingRight: Bool, alerted: Bool) {
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        if !facingRight { g.scaleBy(x: -1, y: 1) }
        let base = CGRect(x: -s * 0.5, y: -s * 0.5, width: s, height: s)
        g.fill(Path(roundedRect: base, cornerRadius: s * 0.2), with: .linearGradient(Gradient(colors: [Color(white: 0.42), Color(white: 0.2)]),
                                                                                     startPoint: CGPoint(x: 0, y: -s * 0.5), endPoint: CGPoint(x: 0, y: s * 0.5)))
        g.fill(Path(roundedRect: CGRect(x: s * 0.2, y: -s * 0.14, width: s * 0.9, height: s * 0.28), cornerRadius: s * 0.08), with: .color(Color(white: 0.16)))
        let eye = CGRect(x: -s * 0.18, y: -s * 0.18, width: s * 0.36, height: s * 0.36)
        g.fill(Path(ellipseIn: eye), with: .color(alerted ? red : Color(white: 0.35)))
        if alerted {
            g.fill(Path(ellipseIn: eye.insetBy(dx: -s * 0.3, dy: -s * 0.3)), with: .radialGradient(Gradient(colors: [red.opacity(0.5), red.opacity(0)]), center: .zero, startRadius: 0, endRadius: s * 0.5))
        }
    }

    /// A tracer round streaking across the floor.
    static func tracer(_ ctx: GraphicsContext, at p: CGPoint, dir: CGFloat, size m: CGFloat) {
        let len = m * 0.06, r = m * 0.013
        var streak = Path()
        streak.move(to: CGPoint(x: p.x - dir * len, y: p.y)); streak.addLine(to: p)
        ctx.stroke(streak, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.6, blue: 0.2).opacity(0), Color(red: 1, green: 0.75, blue: 0.3)]),
                                                 startPoint: CGPoint(x: p.x - dir * len, y: p.y), endPoint: p), style: StrokeStyle(lineWidth: r * 1.4, lineCap: .round))
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(Color(red: 1, green: 0.92, blue: 0.7)))
    }

    /// A red scanner cone — exactly the old cone's apex, reach and angle.
    static func cone(_ ctx: GraphicsContext, at c: CGPoint, facing: Double, half: Double, range: CGFloat) {
        var p = Path()
        p.move(to: c)
        p.addLine(to: CGPoint(x: c.x + CGFloat(cos(facing - half)) * range, y: c.y + CGFloat(sin(facing - half)) * range))
        p.addArc(center: c, radius: range, startAngle: .radians(facing - half), endAngle: .radians(facing + half), clockwise: false)
        p.closeSubpath()
        ctx.fill(p, with: .radialGradient(Gradient(colors: [red.opacity(0.42), red.opacity(0.14)]), center: c, startRadius: 0, endRadius: range))
        var sweep = Path()
        sweep.move(to: c)
        sweep.addLine(to: CGPoint(x: c.x + CGFloat(cos(facing)) * range, y: c.y + CGFloat(sin(facing)) * range))
        ctx.stroke(sweep, with: .color(red.opacity(0.55)), lineWidth: 1)
        ctx.stroke(p, with: .color(red.opacity(0.7)), lineWidth: 1.2)
    }

    /// A sentry bot seen from above: a domed steel body with a red eye on its heading; patrolling
    /// bots ride on a glowing hover ring.
    static func sentry(_ ctx: GraphicsContext, at c: CGPoint, facing: Double, size s: CGFloat, moving: Bool) {
        let r = s / 2
        if moving {
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * 1.25, y: c.y - r * 1.25, width: r * 2.5, height: r * 2.5)), with: .color(Color(red: 0.4, green: 0.85, blue: 1).opacity(0.5)), lineWidth: 2)
        }
        let body = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.fill(body, with: .radialGradient(Gradient(colors: [Color(white: 0.85), Color(white: 0.5), Color(white: 0.25)]),
                                             center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.3), startRadius: 0, endRadius: r * 1.3))
        ctx.stroke(body, with: .color(.black.opacity(0.6)), lineWidth: 1.5)
        let eye = CGPoint(x: c.x + CGFloat(cos(facing)) * r * 0.55, y: c.y + CGFloat(sin(facing)) * r * 0.55)
        ctx.fill(Path(ellipseIn: CGRect(x: eye.x - r * 0.45, y: eye.y - r * 0.45, width: r * 0.9, height: r * 0.9)),
                 with: .radialGradient(Gradient(colors: [red.opacity(0.8), red.opacity(0)]), center: eye, startRadius: 0, endRadius: r * 0.45))
        ctx.fill(Path(ellipseIn: CGRect(x: eye.x - r * 0.2, y: eye.y - r * 0.2, width: r * 0.4, height: r * 0.4)), with: .color(Color(red: 1, green: 0.5, blue: 0.5)))
    }

    /// The thief: a banana in a black eye-mask, drawn inside the same box the win check uses.
    static func thief(_ ctx: GraphicsContext, at p: CGPoint, size s: CGFloat) {
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        g.scaleBy(x: s, y: s)
        let ink = Color(red: 0.14, green: 0.1, blue: 0.03)
        var body = Path()
        body.move(to: CGPoint(x: -0.06, y: -0.48))
        body.addCurve(to: CGPoint(x: 0.1, y: 0.48), control1: CGPoint(x: -0.5, y: -0.2), control2: CGPoint(x: -0.44, y: 0.4))
        body.addCurve(to: CGPoint(x: -0.06, y: -0.48), control1: CGPoint(x: 0.16, y: 0.2), control2: CGPoint(x: 0.24, y: -0.2))
        body.closeSubpath()
        g.fill(body, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.94, blue: 0.45), Color(red: 0.95, green: 0.72, blue: 0.14)]),
                                           startPoint: CGPoint(x: 0.1, y: 0), endPoint: CGPoint(x: -0.35, y: 0)))
        g.stroke(body, with: .color(ink), lineWidth: 0.05)
        g.fill(Path(roundedRect: CGRect(x: -0.34, y: -0.24, width: 0.48, height: 0.14), cornerRadius: 0.06), with: .color(Color(white: 0.08)))
        for x in [-0.22, 0.0] as [CGFloat] {
            g.fill(Path(ellipseIn: CGRect(x: x - 0.04, y: -0.21, width: 0.09, height: 0.08)), with: .color(.white))
        }
        g.fill(Path(roundedRect: CGRect(x: -0.1, y: -0.52, width: 0.08, height: 0.1), cornerRadius: 0.02), with: .color(Color(red: 0.42, green: 0.27, blue: 0.08)))
    }
}

/// The facility: dark floor panels with light seams, the walls where the turrets sit, the vault
/// chamber (exactly the win box) with a golden banana, and the entrance lift at the bottom.
private struct GPFacility: View, Equatable {
    let size: CGSize
    let wallX: CGFloat
    let vaultCenterY: CGFloat
    let vaultHalfX: CGFloat
    let vaultHalfY: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            let w = size.width, h = size.height
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.1, green: 0.12, blue: 0.17)))
            var seams = Path()
            let tile = min(w, h) * 0.1
            var x = wallX * w
            while x < (1 - wallX) * w {
                seams.move(to: CGPoint(x: x, y: 0)); seams.addLine(to: CGPoint(x: x, y: h)); x += tile
            }
            var y: CGFloat = 0
            while y < h {
                seams.move(to: CGPoint(x: wallX * w, y: y)); seams.addLine(to: CGPoint(x: (1 - wallX) * w, y: y)); y += tile
            }
            ctx.stroke(seams, with: .color(Color(red: 0.4, green: 0.7, blue: 1).opacity(0.12)), lineWidth: 1)
            // Side walls (the banana is kept out of them) with hazard stripes along the inner edge.
            for (x0, x1) in [(0, wallX * w), ((1 - wallX) * w, w)] as [(CGFloat, CGFloat)] {
                let wall = CGRect(x: x0, y: 0, width: x1 - x0, height: h)
                ctx.fill(Path(wall), with: .linearGradient(Gradient(colors: [Color(white: 0.2), Color(white: 0.12)]), startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: x1, y: 0)))
                let edgeX = x0 == 0 ? x1 - 4 : x0
                var stripes = ctx
                stripes.clip(to: Path(CGRect(x: edgeX, y: 0, width: 4, height: h)))
                var k: CGFloat = -8
                while k < h {
                    stripes.fill(Path(CGRect(x: edgeX, y: k, width: 4, height: 6)), with: .color(Color(red: 1, green: 0.78, blue: 0.1)))
                    k += 12
                }
            }
            // Vault chamber — exactly the region the banana must fit inside.
            let vault = CGRect(x: w * (0.5 - vaultHalfX), y: h * (vaultCenterY - vaultHalfY), width: w * vaultHalfX * 2, height: h * vaultHalfY * 2)
            ctx.fill(Path(roundedRect: vault.insetBy(dx: -6, dy: -6), cornerRadius: 12), with: .color(Color(white: 0.3)))
            ctx.fill(Path(roundedRect: vault, cornerRadius: 8), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.85, blue: 0.3).opacity(0.45), Color(red: 0.2, green: 0.16, blue: 0.06)]),
                                                                                    center: CGPoint(x: vault.midX, y: vault.midY), startRadius: 0, endRadius: vault.width * 0.6))
            ctx.stroke(Path(roundedRect: vault, cornerRadius: 8), with: .color(Color(red: 1, green: 0.84, blue: 0.3)), lineWidth: 2)
            var bolts = Path()
            for k in 0..<8 {
                let a = Double(k) / 8 * 2 * .pi
                let q = CGPoint(x: vault.midX + CGFloat(cos(a)) * (vault.width / 2 + 3), y: vault.midY + CGFloat(sin(a)) * (vault.height / 2 + 3))
                bolts.addEllipse(in: CGRect(x: q.x - 2, y: q.y - 2, width: 4, height: 4))
            }
            ctx.fill(bolts, with: .color(Color(white: 0.6)))
            // A golden banana on its plinth in the vault's back corner.
            let gb = CGPoint(x: vault.maxX - vault.width * 0.22, y: vault.minY + vault.height * 0.3)
            var golden = Path()
            golden.move(to: CGPoint(x: gb.x - 7, y: gb.y - 2))
            golden.addQuadCurve(to: CGPoint(x: gb.x + 7, y: gb.y - 3), control: CGPoint(x: gb.x, y: gb.y + 8))
            golden.addQuadCurve(to: CGPoint(x: gb.x - 7, y: gb.y - 2), control: CGPoint(x: gb.x, y: gb.y + 2))
            ctx.fill(golden, with: .color(Color(red: 1, green: 0.84, blue: 0.3)))
            // Entrance lift at the bottom.
            let lift = CGRect(x: w * 0.2, y: 0.945 * h, width: w * 0.6, height: h * 0.05)
            ctx.fill(Path(roundedRect: lift, cornerRadius: 6), with: .color(Color(red: 0.4, green: 0.85, blue: 1).opacity(0.12)))
            ctx.stroke(Path(roundedRect: lift, cornerRadius: 6), with: .color(Color(red: 0.4, green: 0.85, blue: 1).opacity(0.5)), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        }
    }
}

/// The header's alarm lamp.
private struct GPAlarmLamp: View {
    let on: Bool

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let dome = CGRect(x: w * 0.2, y: h * 0.2, width: w * 0.6, height: h * 0.62)
            if on {
                ctx.fill(Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)), with: .radialGradient(Gradient(colors: [GPArt.red.opacity(0.6), GPArt.red.opacity(0)]),
                                                                                                   center: CGPoint(x: w / 2, y: h / 2), startRadius: 0, endRadius: w / 2))
            }
            var d = Path()
            d.move(to: CGPoint(x: dome.minX, y: dome.maxY))
            d.addArc(center: CGPoint(x: dome.midX, y: dome.maxY), radius: dome.width / 2, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            d.closeSubpath()
            ctx.fill(d, with: .color(on ? GPArt.red : Color(white: 0.35)))
            ctx.fill(Path(roundedRect: CGRect(x: w * 0.14, y: dome.maxY, width: w * 0.72, height: h * 0.14), cornerRadius: 2), with: .color(Color(white: 0.55)))
        }
    }
}

/// Steel d-pad keys (banana yellow while pressed).
private struct GPKey: View {
    let lit: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: lit ? [Color(red: 1, green: 0.9, blue: 0.45), Color(red: 0.95, green: 0.72, blue: 0.16)]
                                                 : [Color(red: 0.3, green: 0.34, blue: 0.42), Color(red: 0.16, green: 0.18, blue: 0.24)],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 12).strokeBorder(.black.opacity(0.5), lineWidth: 2)
            RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(lit ? 0.9 : 0.2), lineWidth: 1).padding(3)
        }
    }
}
