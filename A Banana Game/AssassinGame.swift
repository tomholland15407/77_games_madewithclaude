//
//  AssassinGame.swift
//  A Banana Game
//
//  Brain/stealth — a top-down shooter-assassination in a spacious arena. Steer your banana with
//  the analog joystick; a little gun points where you're heading. Tap SHOOT to fire a projectile
//  in that direction. Pick off the red targets — down one while it never saw you and it's a clean,
//  consequence-free kill. But every target sweeps a BRIGHT vision cone; step into one and the
//  ALARM trips: reinforcements pour in through the red door in the corner and every target starts
//  shooting back. The alarm generously boosts the clock so the louder fight is still survivable.
//  Down every target to win. Get hit by a bullet, or let the clock run out, and you fall back to
//  level 1. 7 levels: more targets, wider/longer cones, faster patrols, more reinforcements, and
//  quicker enemy fire. Uses the feed lock (joystick drag) + the free skip button.
//
//  Drawn like Hunter Assassin: a top-down tiled floor, bold-outlined concrete walls and shipping
//  containers for cover, a hazard-striped steel door for the reinforcements, flashlight vision cones
//  (red once the alarm trips), guards in red jackets holding their guns, and a banana assassin in a
//  black headband. Chunky joystick and a round SHOOT button.
//

import SwiftUI

enum AssassinGame {
    static let definition = GameDefinition(
        id: "assassin",
        title: "Assassin",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        locksFeed: true,       // joystick drag — lock the pager while playing
        manual: GameManual(
            bullets: [
                "Steer with the joystick; your gun points where you head. Tap SHOOT to fire.",
                "Pick off the red targets — ideally before they see you.",
                "Step into a target's vision cone and the alarm trips: reinforcements storm in firing.",
                "Down every target to win; a bullet, a timeout, or running dry sends you to level 1.",
            ],
            bulletsVI: [
                "Điều khiển bằng cần; súng hướng theo nơi bạn đi. Chạm BẮN để nổ súng.",
                "Hạ các mục tiêu đỏ — tốt nhất là trước khi chúng thấy bạn.",
                "Bước vào tầm nhìn của một mục tiêu là báo động: quân tiếp viện ập vào nổ súng.",
                "Hạ hết mọi mục tiêu để thắng; trúng đạn, hết giờ, hoặc hết đạn sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(AssassinView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct AssassinView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    // Spacious arena — mostly open floor with a few floating cover blocks (never 1-cell tunnels),
    // so the analog joystick has room to breathe.
    private let cols = 13
    private let rows = 17

    // MARK: Difficulty (all derived from `level`)
    private var targetCount: Int          { [1, 2, 2, 3, 3, 4, 4][min(level, 7) - 1] }
    private var patrolSpeed: Double        { [1.4, 1.6, 1.8, 2.0, 2.2, 2.4, 2.6][min(level, 7) - 1] } // cells/sec
    private var chaseSpeed: Double         { patrolSpeed + 1.0 }
    // Opponents see twice as far forward as before — sneaking past a cone is much harder now.
    private var visionRange: Double        { 2 * [3.0, 3.3, 3.6, 3.9, 4.2, 4.5, 4.8][min(level, 7) - 1] } // cells
    private var visionHalfDeg: Double      { [24, 27, 30, 34, 38, 42, 46][min(level, 7) - 1] }        // half-angle
    private var reinforcements: Int        { [1, 1, 2, 2, 3, 3, 4][min(level, 7) - 1] }
    private var guardFireInterval: Double  { [1.7, 1.55, 1.4, 1.2, 1.0, 0.85, 0.7][min(level, 7) - 1] }
    private var coverBlocks: Int           { 4 + level }
    private var baseTime: Double           { Double(26 + targetCount * 10) }
    private var alarmBoost: Double         { Double(12 + reinforcements * 6) }   // generous extra time on alarm
    // A limited-but-generous magazine: enough for ~4 shots at every target AND every possible
    // reinforcement, plus a cushion — so even a tripped alarm leaves more than enough bullets.
    private var bulletBudget: Int          { (targetCount + reinforcements) * 4 + 6 }

    private let playerSpeed = 3.6         // cells/sec
    private let playerShootCD = 0.34      // seconds between the player's shots
    private let playerProjSpeed = 9.0     // cells/sec — fast, so aim reads instantly
    private let guardProjSpeed = 6.0      // cells/sec — dodgeable behind cover
    private let fireRange = 8.0           // an alerted guard only shoots within this range + clear line
    private var visionHalf: Double { visionHalfDeg * .pi / 180.0 }

    private struct P: Hashable { let r: Int; let c: Int }
    private struct Enemy: Identifiable {
        let id = UUID()
        var pos: CGPoint          // continuous cell coords (x = col, y = row)
        var path: [P]             // patrol waypoints (ping-ponged) — empty/1 for reinforcements
        var idx: Int
        var dir: Int
        var facing: Double        // radians, y-down — the cone + gun point this way
        var alerted: Bool         // chasing + shooting after the alarm
        var fireCD: Double
    }
    private struct Shot: Identifiable {
        let id = UUID()
        var pos: CGPoint
        var vel: CGVector         // cells/sec
        var friendly: Bool        // true = the player's bullet
        var life: Double
    }
    private struct Burst: Identifiable { let id = UUID(); let pos: CGPoint; let color: Color }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var walls: [[Bool]] = []
    @State private var enemies: [Enemy] = []
    @State private var shots: [Shot] = []
    @State private var player = CGPoint(x: 1.5, y: 1.5)
    @State private var playerFacing = 0.0
    @State private var stick = CGVector.zero
    @State private var shootCD = 0.0
    @State private var timeLeft = 0.0
    @State private var maxTime = 0.0      // bar denominator — grows with the alarm boost
    @State private var alarmRaised = false
    @State private var ammo = 0
    @State private var doorCell = P(r: 1, c: 1)
    @State private var bursts: [Burst] = []
    @State private var shakeTick = 0
    @State private var built = false
    @State private var demoShoot = false          // demo: SHOOT visibly pressed

    var body: some View {
        VStack(spacing: isDemo ? 6 : 8) {
            if !isDemo { hud }

            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let cell = min(w / CGFloat(cols), h / CGFloat(rows))
                let ox = (w - cell * CGFloat(cols)) / 2
                let oy = (h - cell * CGFloat(rows)) / 2
                let px: (Double) -> CGFloat = { x in ox + CGFloat(x) * cell }
                let py: (Double) -> CGFloat = { y in oy + CGFloat(y) * cell }

                ZStack {
                    HunterMap(walls: walls, doorR: doorCell.r, doorC: doorCell.c, alarm: alarmRaised,
                              cell: cell, ox: ox, oy: oy).equatable()

                    // Cones, bullets, guards and you — everything that moves, in one pass.
                    Canvas { ctx, _ in drawAction(ctx, cell: cell, px: px, py: py) }
                        .allowsHitTesting(false)

                    ForEach(bursts) { b in
                        ParticleBurstView(color: b.color, count: 12, spread: 44) {
                            bursts.removeAll { $0.id == b.id }
                        }
                        .position(x: px(b.pos.x), y: py(b.pos.y))
                    }
                }
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2))
                .screenShake(shakeTick, amount: 6)
            }
            .padding(.horizontal, 12)

            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, isDemo ? 8 : 6)
        .padding(.bottom, isDemo ? 0 : 6)
        .background(Color(red: 0.12, green: 0.13, blue: 0.17))
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
    }

    /// Targets left / alarm / ammo and the clock (hidden in the manual demo to fit).
    private var hud: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: "scope")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(Color(red: 0.95, green: 0.3, blue: 0.28))
                Text(enemies.isEmpty ? L("ALL TARGETS DOWN", "ĐÃ HẠ HẾT MỤC TIÊU")
                     : L("\(enemies.count) target\(enemies.count == 1 ? "" : "s") left", "còn \(enemies.count) mục tiêu"))
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                if alarmRaised && !enemies.isEmpty {
                    Text(L("ALARM", "BÁO ĐỘNG"))
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color(red: 0.9, green: 0.15, blue: 0.17)))
                        .overlay(Capsule().stroke(.black, lineWidth: 2))
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(Color(red: 0.95, green: 0.78, blue: 0.3))
                    Text(L("AMMO \(ammo)", "ĐẠN \(ammo)"))
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(ammo <= 3 ? Color(red: 1, green: 0.35, blue: 0.3) : .white)
                }
            }
            .padding(.horizontal, 20)
            timeBar.frame(height: 6).padding(.horizontal, 44)
        }
    }

    // MARK: - Rendering

    private func drawAction(_ ctx: GraphicsContext, cell: CGFloat,
                            px: (Double) -> CGFloat, py: (Double) -> CGFloat) {
        // Flashlight cones (same geometry the guards actually see with), warm white — red on alarm.
        for e in enemies {
            let origin = CGPoint(x: px(e.pos.x), y: py(e.pos.y))
            let R = CGFloat(visionRange) * cell
            var cone = Path()
            cone.move(to: origin)
            cone.addArc(center: origin, radius: R, startAngle: .radians(e.facing - visionHalf),
                        endAngle: .radians(e.facing + visionHalf), clockwise: false)
            cone.closeSubpath()
            let col = e.alerted ? Color(red: 1, green: 0.22, blue: 0.2) : Color(red: 1, green: 0.93, blue: 0.62)
            ctx.fill(cone, with: .radialGradient(Gradient(colors: [col.opacity(e.alerted ? 0.55 : 0.6), col.opacity(0.18)]),
                                                 center: origin, startRadius: cell * 0.3, endRadius: R))
            ctx.stroke(cone, with: .color(col.opacity(0.85)), lineWidth: 1.5)
        }
        // Bullets as short tracers.
        for s in shots {
            let p = CGPoint(x: px(s.pos.x), y: py(s.pos.y))
            let speed = max(0.001, hypot(s.vel.dx, s.vel.dy))
            let tail = CGPoint(x: p.x - s.vel.dx / speed * cell * 0.55, y: p.y - s.vel.dy / speed * cell * 0.55)
            let col = s.friendly ? Color(red: 1, green: 0.88, blue: 0.3) : Color(red: 1, green: 0.4, blue: 0.3)
            var streak = Path()
            streak.move(to: tail); streak.addLine(to: p)
            ctx.stroke(streak, with: .linearGradient(Gradient(colors: [col.opacity(0), col]), startPoint: tail, endPoint: p),
                       style: StrokeStyle(lineWidth: cell * 0.16, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - cell * 0.09, y: p.y - cell * 0.09, width: cell * 0.18, height: cell * 0.18)), with: .color(.white))
        }
        // Guards in red jackets.
        for e in enemies {
            HunterArt.guardFigure(ctx, at: CGPoint(x: px(e.pos.x), y: py(e.pos.y)), facing: e.facing, cell: cell, alerted: e.alerted)
        }
        // You: the banana assassin.
        HunterArt.banana(ctx, at: CGPoint(x: px(player.x), y: py(player.y)), facing: playerFacing, cell: cell)
    }

    private var controls: some View {
        HStack {
            AssassinJoystick(vector: $stick, size: isDemo ? 80 : 120, demo: isDemo)
            Spacer()
            Button { shoot() } label: {
                VStack(spacing: 2) {
                    Image(systemName: "scope")
                        .font(.system(size: isDemo ? 22 : 30, weight: .black))
                    Text(L("SHOOT", "BẮN"))
                        .font(.system(size: isDemo ? 11 : 13, weight: .black, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(width: isDemo ? 70 : 92, height: isDemo ? 70 : 92)
            }
            .buttonStyle(ShootButtonStyle(lit: demoShoot))
        }
        .padding(.horizontal, isDemo ? 22 : 28)
        .padding(.bottom, 6)
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac = maxTime > 0 ? timeLeft / maxTime : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule().fill(frac < 0.3 ? Color(red: 0.95, green: 0.25, blue: 0.22) : Color(red: 0.95, green: 0.78, blue: 0.3))
                    .frame(width: geo.size.width * max(0, frac))
            }
        }
    }

    // MARK: - Flow

    private func run() async {
        if !built { setup(); built = true }
        var last = Date()
        while !Task.isCancelled && phase == .play {
            try? await Task.sleep(for: .seconds(0.016))
            let now = Date()
            let dt = min(0.05, now.timeIntervalSince(last)); last = now
            step(dt: dt)
        }
    }

    private func step(dt: Double) {
        guard phase == .play else { return }

        // 1) Player (analog joystick, axis-separated wall collision). Facing follows the stick.
        let vx = Double(stick.dx) * playerSpeed * dt
        let vy = Double(stick.dy) * playerSpeed * dt
        if canStand(player.x + vx, player.y) { player.x += vx }
        if canStand(player.x, player.y + vy) { player.y += vy }
        // Aim follows the joystick: a small deadzone so light nudges still turn the gun, and
        // shortest-angle easing (instead of a hard snap) so the barrel rotates smoothly rather
        // than feeling stiff.
        if hypot(stick.dx, stick.dy) > 0.08 {
            let target = atan2(Double(stick.dy), Double(stick.dx))
            playerFacing += angleDiff(target, playerFacing) * min(1.0, dt * 16.0)
        }
        shootCD = max(0, shootCD - dt)

        // 2) Enemies: patrol (calm) or chase + shoot (alerted).
        for i in enemies.indices {
            if enemies[i].alerted { chase(&enemies[i], dt: dt) }
            else { patrol(&enemies[i], dt: dt) }
            enemies[i].fireCD -= dt
            if enemies[i].alerted {
                let d = hypot(player.x - enemies[i].pos.x, player.y - enemies[i].pos.y)
                if enemies[i].fireCD <= 0, d <= fireRange, losClear(enemies[i].pos, player) {
                    let a = atan2(player.y - enemies[i].pos.y, player.x - enemies[i].pos.x)
                    enemies[i].facing = a
                    enemies[i].fireCD = guardFireInterval
                    shots.append(Shot(pos: enemies[i].pos,
                                      vel: CGVector(dx: cos(a) * guardProjSpeed, dy: sin(a) * guardProjSpeed),
                                      friendly: false, life: 2.4))
                }
            }
        }

        // 3) Spotted? Only the FIRST detection matters — it trips the alarm (no instant fail now).
        if !alarmRaised {
            for e in enemies where spots(e, target: player) { raiseAlarm(); break }
        }

        // 4) Advance bullets + resolve hits (may win or fail).
        if !stepShots(dt: dt) { return }

        // 5) Clock.
        timeLeft -= dt
        if timeLeft <= 0 { timeLeft = 0; fail() }
    }

    /// Moves every bullet and resolves collisions. Returns false if the game just ended.
    private func stepShots(dt: Double) -> Bool {
        var survivors: [Shot] = []
        for var s in shots {
            s.pos.x += Double(s.vel.dx) * dt
            s.pos.y += Double(s.vel.dy) * dt
            s.life -= dt
            if s.life <= 0 { continue }
            if isWall(Int(floor(s.pos.y)), Int(floor(s.pos.x))) { continue }   // absorbed by a wall
            if s.friendly {
                if let hit = enemies.firstIndex(where: {
                    hypot($0.pos.x - s.pos.x, $0.pos.y - s.pos.y) < 0.5
                }) {
                    bursts.append(Burst(pos: enemies[hit].pos, color: Color(red: 1, green: 0.3, blue: 0.3)))
                    enemies.remove(at: hit)
                    shakeTick += 1
                    Haptics.tap(); SoundManager.shared.tap()
                    continue                                                   // bullet consumed
                }
            } else if hypot(player.x - s.pos.x, player.y - s.pos.y) < 0.42 {
                shakeTick += 1
                fail(); return false
            }
            survivors.append(s)
        }
        shots = survivors
        if enemies.isEmpty { win(); return false }
        // Out of bullets with targets still up and nothing left in flight → the run is lost.
        if ammo == 0 && !shots.contains(where: { $0.friendly }) { fail(); return false }
        return true
    }

    private func shoot() {
        guard phase == .play, shootCD <= 0, ammo > 0 else { return }
        shootCD = playerShootCD
        ammo -= 1
        shots.append(Shot(pos: player,
                          vel: CGVector(dx: cos(playerFacing) * playerProjSpeed,
                                        dy: sin(playerFacing) * playerProjSpeed),
                          friendly: true, life: 2.0))
        SoundManager.shared.tap(); Haptics.tap()
    }

    private func raiseAlarm() {
        guard !alarmRaised else { return }
        alarmRaised = true
        // Everyone gets radioed: existing targets turn hostile...
        for i in enemies.indices {
            enemies[i].alerted = true
            enemies[i].fireCD = Double.random(in: 0.2...guardFireInterval)
        }
        // ...and reinforcements storm in through the red door.
        let d = center(doorCell)
        for k in 0..<reinforcements {
            enemies.append(Enemy(pos: d, path: [doorCell], idx: 0, dir: 1,
                                 facing: atan2(player.y - d.y, player.x - d.x),
                                 alerted: true, fireCD: Double(k) * 0.35 + 0.5))
        }
        // A bigger fight deserves more time — boost the clock generously.
        timeLeft += alarmBoost; maxTime += alarmBoost
        shakeTick += 1
        SoundManager.shared.error(); Haptics.warning()
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

    // MARK: - Demo (live manual clip)
    // Level 1: one target. A fixed open arena (border + three cover blocks clear of the middle
    // column); the target patrols row 3 left↔right, so its cone (±24°, 6 cells at L1) always
    // points sideways. You push the stick UP the middle column and stop exactly 4 rows below its
    // row — at that offset any point within 6 cells sits ≥ 41° off its facing, so it can never see
    // you. Then SHOOT straight up with a lead (bullet flight time × its speed) as it crosses:
    // a clean, alarm-free kill through the real `step`/`shoot` at a fixed 1/60s → real win().
    private func demoSetup() {
        var w = Array(repeating: Array(repeating: false, count: cols), count: rows)
        for r in 0..<rows { w[r][0] = true; w[r][cols - 1] = true }
        for c in 0..<cols { w[0][c] = true; w[rows - 1][c] = true }
        for (r, c) in [(7, 2), (7, 3), (8, 2), (8, 3), (11, 9), (11, 10), (13, 3), (14, 3)] { w[r][c] = true }
        walls = w
        doorCell = P(r: rows - 2, c: cols - 2)
        let path = (2...10).map { P(r: 3, c: $0) }
        enemies = [Enemy(pos: center(path[0]), path: path, idx: 0, dir: 1, facing: 0,
                         alerted: false, fireCD: 0)]
        player = center(P(r: 14, c: 6))
        playerFacing = -.pi / 2
        shots = []; stick = .zero; bursts = []
        alarmRaised = false; shootCD = 0; ammo = bulletBudget
        timeLeft = baseTime; maxTime = baseTime
        demoShoot = false
        phase = .play
        built = true
    }

    private func runDemo() async {
        let dt = 1.0 / 60.0
        while !Task.isCancelled {
            demoSetup()
            try? await Task.sleep(for: .seconds(0.6))
            var t = 0.0, fired = false, shootFlash = 0.0
            while !Task.isCancelled && phase == .play && t < 8 {
                t += dt
                // Sneak up the middle column until 4 rows below the patrol row, then hold.
                let holdY = 3.5 + 4
                stick = player.y > holdY + 0.02 ? CGVector(dx: 0, dy: -1) : .zero
                // Fire once, leading the crossing target by the bullet's flight time.
                if !fired, stick == .zero, let e = enemies.first, e.path.count >= 2 {
                    let wp = center(e.path[e.idx])
                    let vx = (wp.x - e.pos.x).sign == .minus ? -patrolSpeed : patrolSpeed
                    let flight = (player.y - e.pos.y) / playerProjSpeed
                    if abs(e.pos.x + vx * flight - player.x) < 0.12 {
                        shoot(); fired = true; shootFlash = 0.16
                    }
                }
                demoShoot = shootFlash > 0
                shootFlash -= dt
                step(dt: dt)
                try? await Task.sleep(for: .seconds(0.016))
            }
            stick = .zero; demoShoot = false
            // The shot downed the last target → the real win() ran (onWin is a no-op).
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    // MARK: - Enemy movement

    private func patrol(_ e: inout Enemy, dt: Double) {
        guard e.path.count >= 2 else { return }
        let wp = center(e.path[e.idx])
        let dx = wp.x - e.pos.x, dy = wp.y - e.pos.y
        let d = hypot(dx, dy)
        let sd = patrolSpeed * dt
        if d <= sd || d < 0.0001 {
            e.pos = wp
            var ni = e.idx + e.dir
            if ni < 0 || ni >= e.path.count { e.dir = -e.dir; ni = e.idx + e.dir }
            ni = max(0, min(e.path.count - 1, ni))
            let nwp = center(e.path[ni])
            e.facing = atan2(nwp.y - e.pos.y, nwp.x - e.pos.x)
            e.idx = ni
        } else {
            e.pos.x += dx / d * sd
            e.pos.y += dy / d * sd
            e.facing = atan2(dy, dx)
        }
    }

    private func chase(_ e: inout Enemy, dt: Double) {
        let dx = player.x - e.pos.x, dy = player.y - e.pos.y
        let d = hypot(dx, dy)
        if d > 0.0001 { e.facing = atan2(dy, dx) }
        guard d > 0.4 else { return }              // don't jitter on top of the player
        let sp = chaseSpeed * dt
        let nx = dx / d * sp, ny = dy / d * sp
        // Axis-separated so it slides along cover instead of sticking.
        if canStand(e.pos.x + nx, e.pos.y) { e.pos.x += nx }
        if canStand(e.pos.x, e.pos.y + ny) { e.pos.y += ny }
    }

    private func center(_ p: P) -> CGPoint { CGPoint(x: Double(p.c) + 0.5, y: Double(p.r) + 0.5) }

    // MARK: - Detection helpers

    private func spots(_ e: Enemy, target: CGPoint) -> Bool {
        let dx = target.x - e.pos.x, dy = target.y - e.pos.y
        let dist = hypot(dx, dy)
        guard dist <= visionRange, dist > 0.0001 else { return false }
        let off = abs(angleDiff(atan2(dy, dx), e.facing))
        guard off <= visionHalf else { return false }
        return losClear(e.pos, target)
    }

    private func angleDiff(_ a: Double, _ b: Double) -> Double {
        var d = a - b
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }

    private func losClear(_ a: CGPoint, _ b: CGPoint) -> Bool {
        let steps = Int(hypot(b.x - a.x, b.y - a.y) / 0.15) + 1
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t
            if isWall(Int(floor(y)), Int(floor(x))) { return false }
        }
        return true
    }

    private func isWall(_ r: Int, _ c: Int) -> Bool {
        guard r >= 0, r < rows, c >= 0, c < cols, walls.count == rows else { return true }
        return walls[r][c]
    }

    /// A disc of the mover's radius stays clear of walls.
    private func canStand(_ x: Double, _ y: Double) -> Bool {
        let rad = 0.28
        for cx in [x - rad, x + rad] {
            for cy in [y - rad, y + rad] {
                if isWall(Int(floor(cy)), Int(floor(cx))) { return false }
            }
        }
        return true
    }

    // MARK: - Setup (spacious arena + patrols + player start)

    private func setup() {
        // 1) Open arena: solid border, floor interior, then a few FLOATING cover blocks. Because
        //    every block keeps a 1-cell all-floor margin, the open area is always fully connected
        //    (you can route around any block) and there are no 1-cell tunnels.
        var w = Array(repeating: Array(repeating: false, count: cols), count: rows)
        for r in 0..<rows { w[r][0] = true; w[r][cols - 1] = true }
        for c in 0..<cols { w[0][c] = true; w[rows - 1][c] = true }
        var placed = 0, tries = 0
        while placed < coverBlocks && tries < 300 {
            tries += 1
            let bw = Int.random(in: 1...3), bh = Int.random(in: 1...3)
            let c0 = Int.random(in: 2...(cols - 2 - bw))
            let r0 = Int.random(in: 2...(rows - 2 - bh))
            var ok = true
            for r in (r0 - 1)...(r0 + bh) where ok {
                for c in (c0 - 1)...(c0 + bw) where w[r][c] { ok = false }
            }
            guard ok else { continue }
            for r in r0..<(r0 + bh) { for c in c0..<(c0 + bw) { w[r][c] = true } }
            placed += 1
        }
        walls = w

        let open = (0..<rows).flatMap { r in (0..<cols).compactMap { c in w[r][c] ? nil : P(r: r, c: c) } }

        func neighbours(_ p: P) -> [P] {
            [P(r: p.r - 1, c: p.c), P(r: p.r + 1, c: p.c), P(r: p.r, c: p.c - 1), P(r: p.r, c: p.c + 1)]
                .filter { $0.r >= 0 && $0.r < rows && $0.c >= 0 && $0.c < cols && !w[$0.r][$0.c] }
        }
        func bfsPath(_ s: P, _ goal: P) -> [P] {
            var prev: [P: P] = [:]; var seen: Set<P> = [s]; var q = [s]; var head = 0
            while head < q.count {
                let cur = q[head]; head += 1
                if cur == goal { break }
                for n in neighbours(cur) where !seen.contains(n) { seen.insert(n); prev[n] = cur; q.append(n) }
            }
            var path: [P] = []; var cur: P? = goal
            while let cc = cur { path.append(cc); if cc == s { break }; cur = prev[cc] }
            return path.reversed()
        }

        // 2) Reinforcement door: the open cell nearest the bottom-right corner.
        let corner = P(r: rows - 2, c: cols - 2)
        doorCell = open.min { manhattan($0, corner) < manhattan($1, corner) } ?? P(r: 1, c: 1)

        // 3) Targets on spaced-out patrol routes.
        var starts: [P] = []
        for cand in open.shuffled() where cand != doorCell {
            if starts.allSatisfy({ manhattan($0, cand) >= 4 }) {
                starts.append(cand)
                if starts.count == targetCount { break }
            }
        }
        while starts.count < targetCount, let any = open.randomElement() { starts.append(any) }

        var es: [Enemy] = []
        for s in starts {
            var path = [s, neighbours(s).first ?? s]
            for goal in open.shuffled() where goal != s {
                let p = bfsPath(s, goal)
                if p.count >= 5 { path = p; break }
            }
            let f = path.count >= 2
                ? atan2(center(path[1]).y - center(path[0]).y, center(path[1]).x - center(path[0]).x)
                : 0
            es.append(Enemy(pos: center(s), path: path, idx: 0, dir: 1, facing: f, alerted: false, fireCD: 0))
        }
        enemies = es

        // 4) Player starts on the open cell farthest from every target.
        let startCell = open.max { minDist($0, starts) < minDist($1, starts) } ?? P(r: 1, c: 1)
        player = center(startCell)
        playerFacing = 0

        shots = []; stick = .zero; bursts = []
        alarmRaised = false; shootCD = 0; ammo = bulletBudget
        timeLeft = baseTime; maxTime = baseTime
        phase = .play
    }

    private func manhattan(_ a: P, _ b: P) -> Int { abs(a.r - b.r) + abs(a.c - b.c) }
    private func minDist(_ p: P, _ set: [P]) -> Int {
        set.map { manhattan($0, p) }.min() ?? .max
    }
}

// MARK: - Virtual joystick

/// A relative analog stick: drag anywhere on the pad; `vector` reports the knob offset as a
/// −1…1 vector (magnitude clamped to 1). Releases snap the knob back to centre.
private struct AssassinJoystick: View {
    @Binding var vector: CGVector
    let size: CGFloat
    /// Manual demo: the knob follows the scripted `vector` and a finger rides it while pushed.
    var demo = false
    @State private var knob: CGSize = .zero

    private var demoKnob: CGSize { CGSize(width: vector.dx * size * 0.30, height: vector.dy * size * 0.30) }

    var body: some View {
        ZStack {
            // Base: a dark ring with four arrow notches.
            Circle().fill(RadialGradient(colors: [Color(white: 0.24), Color(white: 0.1)], center: .center, startRadius: 0, endRadius: size / 2))
                .overlay(Circle().stroke(.black, lineWidth: 3))
                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1.5).padding(4))
            ForEach(0..<4, id: \.self) { k in
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: size * 0.09))
                    .foregroundStyle(.white.opacity(0.35))
                    .offset(y: -size * 0.38)
                    .rotationEffect(.degrees(Double(k) * 90))
            }
            // Knob: a glossy banana-yellow cap.
            Circle().fill(RadialGradient(colors: [Color(red: 1, green: 0.93, blue: 0.55), BananaTheme.banana, Color(red: 0.8, green: 0.58, blue: 0.1)],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.26))
                .frame(width: size * 0.42, height: size * 0.42)
                .overlay(Circle().stroke(.black, lineWidth: 2.5))
                .offset(demo ? demoKnob : knob)
                .animation(.easeOut(duration: 0.12), value: demo ? demoKnob : knob)
            if demo && vector != .zero {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: size * 0.3))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 3)
                    .offset(x: demoKnob.width + size * 0.1, y: demoKnob.height + size * 0.14)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let maxR = size * 0.30
                    var dx = v.translation.width, dy = v.translation.height
                    let len = hypot(dx, dy)
                    if len > maxR { dx = dx / len * maxR; dy = dy / len * maxR }
                    knob = CGSize(width: dx, height: dy)
                    vector = CGVector(dx: dx / maxR, dy: dy / maxR)
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.2)) { knob = .zero }
                    vector = .zero
                }
        )
    }
}

// MARK: - Hunter Assassin art

private enum HunterArt {
    static let ink = Color(red: 0.06, green: 0.06, blue: 0.09)

    static func hash(_ n: Double) -> CGFloat {
        let v: Double = sin(n * 12.9898) * 43758.5453
        return CGFloat(v - floor(v))
    }

    /// A top-down figure: shoulders across, head in the middle, both hands out front on the gun.
    static func figure(_ ctx: GraphicsContext, at p: CGPoint, facing: Double, cell: CGFloat,
                       jacket: Color, skin: Color, hair: Color?, band: Bool) {
        var c = ctx
        c.translateBy(x: p.x, y: p.y)
        c.rotate(by: .radians(facing))
        let s = cell * 1.2          // drawn a touch bigger than the hit disc so figures read at this scale
        let lw: CGFloat = max(1.5, s * 0.07)
        // Gun and arms first so the shoulders overlap them.
        let gun = CGRect(x: s * 0.22, y: -s * 0.06, width: s * 0.5, height: s * 0.12)
        c.fill(Path(roundedRect: gun.insetBy(dx: -lw * 0.5, dy: -lw * 0.5), cornerRadius: s * 0.04), with: .color(ink))
        c.fill(Path(roundedRect: gun, cornerRadius: s * 0.03), with: .color(Color(white: 0.3)))
        var arms = Path()
        arms.move(to: CGPoint(x: 0, y: -s * 0.24)); arms.addLine(to: CGPoint(x: s * 0.28, y: -s * 0.05))
        arms.move(to: CGPoint(x: 0, y: s * 0.24)); arms.addLine(to: CGPoint(x: s * 0.28, y: s * 0.05))
        c.stroke(arms, with: .color(ink), style: StrokeStyle(lineWidth: s * 0.13 + lw, lineCap: .round))
        c.stroke(arms, with: .color(jacket), style: StrokeStyle(lineWidth: s * 0.13, lineCap: .round))
        for y in [-s * 0.05, s * 0.05] {
            c.fill(Path(ellipseIn: CGRect(x: s * 0.23, y: y - s * 0.07, width: s * 0.14, height: s * 0.14)), with: .color(skin))
        }
        // Shoulders.
        let torso = Path(roundedRect: CGRect(x: -s * 0.18, y: -s * 0.33, width: s * 0.36, height: s * 0.66), cornerSize: CGSize(width: s * 0.16, height: s * 0.2))
        c.fill(torso, with: .color(ink))
        c.fill(Path(roundedRect: CGRect(x: -s * 0.18 + lw * 0.5, y: -s * 0.33 + lw * 0.5, width: s * 0.36 - lw, height: s * 0.66 - lw),
                    cornerSize: CGSize(width: s * 0.14, height: s * 0.18)),
               with: .linearGradient(Gradient(colors: [jacket.lit(0.2), jacket.shade(0.2)]), startPoint: CGPoint(x: -s * 0.2, y: 0), endPoint: CGPoint(x: s * 0.2, y: 0)))
        // Head.
        let hr = s * 0.19
        c.fill(Path(ellipseIn: CGRect(x: -hr - lw * 0.5, y: -hr - lw * 0.5, width: (hr + lw * 0.5) * 2, height: (hr + lw * 0.5) * 2)), with: .color(ink))
        c.fill(Path(ellipseIn: CGRect(x: -hr, y: -hr, width: hr * 2, height: hr * 2)), with: .color(skin))
        if let hair {
            var cap = Path()
            cap.addArc(center: .zero, radius: hr, startAngle: .degrees(100), endAngle: .degrees(260), clockwise: false)
            cap.closeSubpath()
            c.fill(cap, with: .color(hair))
        }
        if band {
            // A ninja headband with its tails flying behind.
            c.fill(Path(CGRect(x: -hr * 0.3, y: -hr, width: hr * 0.55, height: hr * 2)), with: .color(ink))
            var tails = Path()
            tails.move(to: CGPoint(x: -hr * 0.2, y: -hr * 0.2)); tails.addQuadCurve(to: CGPoint(x: -hr * 2.1, y: -hr * 0.7), control: CGPoint(x: -hr * 1.2, y: hr * 0.2))
            tails.move(to: CGPoint(x: -hr * 0.2, y: hr * 0.2)); tails.addQuadCurve(to: CGPoint(x: -hr * 2.0, y: hr * 0.6), control: CGPoint(x: -hr * 1.2, y: -hr * 0.1))
            c.stroke(tails, with: .color(ink), style: StrokeStyle(lineWidth: s * 0.07, lineCap: .round))
        }
    }

    static func guardFigure(_ ctx: GraphicsContext, at p: CGPoint, facing: Double, cell: CGFloat, alerted: Bool) {
        figure(ctx, at: p, facing: facing, cell: cell, jacket: Color(red: 0.86, green: 0.2, blue: 0.2),
               skin: Color(red: 0.93, green: 0.76, blue: 0.6), hair: Color(red: 0.2, green: 0.14, blue: 0.1), band: false)
        if alerted {
            // The "!" over an alerted guard.
            let b = CGRect(x: p.x - cell * 0.18, y: p.y - cell * 1.05, width: cell * 0.36, height: cell * 0.42)
            ctx.fill(Path(roundedRect: b.insetBy(dx: -1.5, dy: -1.5), cornerRadius: cell * 0.1), with: .color(ink))
            ctx.fill(Path(roundedRect: b, cornerRadius: cell * 0.08), with: .color(Color(red: 1, green: 0.85, blue: 0.2)))
            ctx.draw(Text("!").font(.system(size: cell * 0.36, weight: .black)).foregroundColor(ink), at: CGPoint(x: b.midX, y: b.midY))
        }
    }

    static func banana(_ ctx: GraphicsContext, at p: CGPoint, facing: Double, cell: CGFloat) {
        figure(ctx, at: p, facing: facing, cell: cell, jacket: Color(red: 0.14, green: 0.14, blue: 0.18),
               skin: BananaTheme.banana, hair: nil, band: true)
    }
}

/// The level map: tiled floor, concrete border walls, containers for cover, and the reinforcement
/// door. Redrawn only when the layout or the alarm changes.
private struct HunterMap: View, Equatable {
    let walls: [[Bool]]
    let doorR: Int
    let doorC: Int
    let alarm: Bool
    let cell: CGFloat
    let ox: CGFloat
    let oy: CGFloat

    var body: some View {
        Canvas { ctx, s in
            let rows = walls.count
            guard rows > 0 else { return }
            let cols = walls[0].count
            ctx.fill(Path(CGRect(origin: .zero, size: s)), with: .color(Color(red: 0.16, green: 0.17, blue: 0.21)))
            func rect(_ r: Int, _ c: Int) -> CGRect { CGRect(x: ox + CGFloat(c) * cell, y: oy + CGFloat(r) * cell, width: cell, height: cell) }
            // Floor tiles.
            for r in 0..<rows {
                for c in 0..<cols where !walls[r][c] {
                    let light = (r + c) % 2 == 0
                    ctx.fill(Path(rect(r, c).insetBy(dx: -0.3, dy: -0.3)),
                             with: .color(light ? Color(red: 0.4, green: 0.46, blue: 0.54) : Color(red: 0.36, green: 0.42, blue: 0.5)))
                }
            }
            var grout = Path()
            for r in 0...rows { grout.move(to: CGPoint(x: ox, y: oy + CGFloat(r) * cell)); grout.addLine(to: CGPoint(x: ox + CGFloat(cols) * cell, y: oy + CGFloat(r) * cell)) }
            for c in 0...cols { grout.move(to: CGPoint(x: ox + CGFloat(c) * cell, y: oy)); grout.addLine(to: CGPoint(x: ox + CGFloat(c) * cell, y: oy + CGFloat(rows) * cell)) }
            ctx.stroke(grout, with: .color(Color(red: 0.26, green: 0.3, blue: 0.36)), lineWidth: 0.8)
            // Walls: border walls in concrete, interior blocks as shipping containers.
            let isBorder: (Int, Int) -> Bool = { r, c in r == 0 || c == 0 || r == rows - 1 || c == cols - 1 }
            var seen = Set<Int>()
            for r in 0..<rows {
                for c in 0..<cols where walls[r][c] {
                    let rc = rect(r, c)
                    if isBorder(r, c) {
                        ctx.fill(Path(rc.insetBy(dx: -0.3, dy: -0.3)), with: .color(Color(red: 0.62, green: 0.64, blue: 0.68)))
                        // The inner lip is darker, as if the wall stands up out of the floor.
                        let inner = CGRect(x: rc.minX, y: rc.maxY - cell * 0.28, width: cell, height: cell * 0.28)
                        if r + 1 < rows && !walls[r + 1][c] { ctx.fill(Path(inner), with: .color(Color(red: 0.42, green: 0.44, blue: 0.5))) }
                        continue
                    }
                    guard !seen.contains(r * cols + c) else { continue }
                    // Flood the block to find its extent (blocks are rectangles).
                    var stack = [(r, c)], cells: [(Int, Int)] = []
                    seen.insert(r * cols + c)
                    while let (cr, cc) = stack.popLast() {
                        cells.append((cr, cc))
                        for (nr, nc) in [(cr - 1, cc), (cr + 1, cc), (cr, cc - 1), (cr, cc + 1)]
                        where nr >= 0 && nr < rows && nc >= 0 && nc < cols && walls[nr][nc] && !isBorder(nr, nc) && !seen.contains(nr * cols + nc) {
                            seen.insert(nr * cols + nc); stack.append((nr, nc))
                        }
                    }
                    let minR = cells.map(\.0).min()!, maxR = cells.map(\.0).max()!, minC = cells.map(\.1).min()!, maxC = cells.map(\.1).max()!
                    let box = rect(minR, minC).union(rect(maxR, maxC)).insetBy(dx: cell * 0.05, dy: cell * 0.05)
                    let tint: [Color] = [Color(red: 0.2, green: 0.55, blue: 0.55), Color(red: 0.72, green: 0.26, blue: 0.2), Color(red: 0.85, green: 0.55, blue: 0.2)]
                    let col = tint[Int(HunterArt.hash(Double(minR * 17 + minC)) * 3) % 3]
                    ctx.fill(Path(roundedRect: box.offsetBy(dx: cell * 0.08, dy: cell * 0.14), cornerRadius: cell * 0.12), with: .color(.black.opacity(0.35)))
                    ctx.fill(Path(roundedRect: box, cornerRadius: cell * 0.1), with: .color(HunterArt.ink))
                    let body = box.insetBy(dx: cell * 0.06, dy: cell * 0.06)
                    ctx.fill(Path(roundedRect: body, cornerRadius: cell * 0.07),
                             with: .linearGradient(Gradient(colors: [col.lit(0.2), col.shade(0.15)]), startPoint: CGPoint(x: 0, y: body.minY), endPoint: CGPoint(x: 0, y: body.maxY)))
                    var ridges = Path()
                    let vertical = body.height >= body.width
                    var k: CGFloat = cell * 0.22
                    while k < (vertical ? body.height : body.width) - cell * 0.1 {
                        if vertical { ridges.move(to: CGPoint(x: body.minX + 3, y: body.minY + k)); ridges.addLine(to: CGPoint(x: body.maxX - 3, y: body.minY + k)) }
                        else { ridges.move(to: CGPoint(x: body.minX + k, y: body.minY + 3)); ridges.addLine(to: CGPoint(x: body.minX + k, y: body.maxY - 3)) }
                        k += cell * 0.22
                    }
                    ctx.stroke(ridges, with: .color(col.shade(0.4).opacity(0.6)), lineWidth: 1.2)
                }
            }
            // The reinforcement door: steel with hazard stripes and a warning light.
            let d = rect(doorR, doorC).insetBy(dx: cell * 0.04, dy: cell * 0.04)
            ctx.fill(Path(roundedRect: d, cornerRadius: cell * 0.08), with: .color(HunterArt.ink))
            let plate = d.insetBy(dx: cell * 0.07, dy: cell * 0.07)
            ctx.fill(Path(plate), with: .color(Color(red: 0.95, green: 0.78, blue: 0.1)))
            var stripes = ctx
            stripes.clip(to: Path(plate))
            var diag = Path()
            var x = plate.minX - plate.height
            while x < plate.maxX { diag.move(to: CGPoint(x: x, y: plate.maxY)); diag.addLine(to: CGPoint(x: x + plate.height, y: plate.minY)); x += cell * 0.26 }
            stripes.stroke(diag, with: .color(HunterArt.ink), lineWidth: cell * 0.1)
            let lamp = CGPoint(x: d.midX, y: d.midY)
            if alarm {
                ctx.fill(Path(ellipseIn: CGRect(x: lamp.x - cell * 1.1, y: lamp.y - cell * 1.1, width: cell * 2.2, height: cell * 2.2)),
                         with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.15, blue: 0.1).opacity(0.55), .clear]), center: lamp, startRadius: 0, endRadius: cell * 1.1))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: lamp.x - cell * 0.16, y: lamp.y - cell * 0.16, width: cell * 0.32, height: cell * 0.32)),
                     with: .color(alarm ? Color(red: 1, green: 0.2, blue: 0.15) : Color(red: 0.45, green: 0.1, blue: 0.1)))
            ctx.stroke(Path(ellipseIn: CGRect(x: lamp.x - cell * 0.16, y: lamp.y - cell * 0.16, width: cell * 0.32, height: cell * 0.32)), with: .color(HunterArt.ink), lineWidth: 1.5)
            // Soft vignette.
            ctx.fill(Path(CGRect(origin: .zero, size: s)), with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.35)]),
                                                                              center: CGPoint(x: s.width / 2, y: s.height / 2),
                                                                              startRadius: min(s.width, s.height) * 0.35, endRadius: max(s.width, s.height) * 0.75))
        }
        .allowsHitTesting(false)
    }
}

/// The round red SHOOT button (a real press and the demo's `lit` press look the same).
private struct ShootButtonStyle: ButtonStyle {
    var lit: Bool
    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed || lit
        return configuration.label
            .background(Circle().fill(RadialGradient(colors: down ? [Color(red: 1, green: 0.45, blue: 0.4), Color(red: 0.7, green: 0.1, blue: 0.1)]
                                                                  : [Color(red: 1, green: 0.38, blue: 0.34), Color(red: 0.62, green: 0.08, blue: 0.08)],
                                                     center: UnitPoint(x: 0.4, y: 0.3), startRadius: 0, endRadius: 60)))
            .overlay(Circle().stroke(.black, lineWidth: 3))
            .overlay(Circle().stroke(.white.opacity(down ? 0.95 : 0.35), lineWidth: down ? 3 : 1.5).padding(5))
            .scaleEffect(down ? 0.9 : 1)
    }
}

