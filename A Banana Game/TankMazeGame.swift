//
//  TankMazeGame.swift
//  A Banana Game
//
//  Reflex — a top-down Combat-style tank duel in a spacious block maze. Drive your
//  tank with the joystick; the turret points where you steer. Tap FIRE to launch a
//  shell that RICOCHETS off the walls and stays live for several seconds — so every
//  shot (yours included) is a threat long after you pull the trigger. Destroy every
//  enemy tank to win. Get clipped by any bouncing shell, or let the clock run out,
//  and you fall back to level 1.
//
//  7 levels: more enemy tanks, faster patrols, quicker enemy fire, and a busier maze
//  criss-crossed with more ricochets — by 6–7 the arena is a lethal pinball table.
//  Joystick drag → locks the feed while playing (with the free skip button).
//

import SwiftUI

enum TankMazeGame {
    static let definition = GameDefinition(
        id: "tank-maze",
        title: "Tank Maze",
        emoji: "🍌",
        genre: .reflex,
        levelCount: 7,
        locksFeed: true,
        manual: GameManual(
            bullets: [
                "Drive with the joystick; the turret points where you steer.",
                "Tap FIRE to launch a shell that ricochets off walls and stays live for seconds.",
                "Destroy every enemy tank to win.",
                "Any bouncing shell — even your own — is lethal.",
            ],
            bulletsVI: [
                "Lái bằng cần điều khiển; nòng pháo hướng theo nơi bạn lái.",
                "Chạm BẮN để phóng đạn nảy khỏi tường và còn sống vài giây.",
                "Phá hủy mọi xe tăng địch để thắng.",
                "Mọi viên đạn đang nảy — kể cả của bạn — đều chết người.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(TankMazeView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct TankMazeView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    // Spacious open arena — floating cover blocks, never 1-cell tunnels (reused from Assassin).
    private let cols = 13
    private let rows = 17

    // MARK: Difficulty
    private var enemyCount: Int   { [1, 2, 2, 3, 3, 4, 4][min(level, 7) - 1] }
    private var enemySpeed: Double { [1.2, 1.4, 1.5, 1.7, 1.9, 2.1, 2.3][min(level, 7) - 1] }
    private var enemyFire: Double  { [2.2, 2.0, 1.7, 1.5, 1.3, 1.1, 0.95][min(level, 7) - 1] }
    private var coverBlocks: Int   { 4 + level }
    private var baseTime: Double   { Double(30 + enemyCount * 12) }

    private let playerSpeed = 3.4
    private let playerShootCD = 0.5
    private let maxPlayerShots = 4
    private let shellSpeed = 5.0
    private let shellLife = 6.0
    private let shellArm = 0.12       // muzzle-clearance before a shell can hit anything

    private struct P: Hashable { let r: Int; let c: Int }
    private struct Tank: Identifiable {
        let id = UUID()
        var pos: CGPoint          // continuous cell coords (x=col, y=row)
        var facing: Double
        var fireCD: Double
        var roam: P               // current wander target
        var repick: Double        // seconds until it picks a new target
        var tint = 0              // presentation: which enemy colour it wears
    }
    private struct Shell: Identifiable {
        let id = UUID()
        var pos: CGPoint
        var vel: CGVector
        var life: Double
        var arm: Double
        let fromPlayer: Bool
    }
    private struct Burst: Identifiable { let id = UUID(); let pos: CGPoint; let color: Color; let t0 = Date() }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var walls: [[Bool]] = []
    @State private var enemies: [Tank] = []
    @State private var shells: [Shell] = []
    @State private var player = CGPoint(x: 1.5, y: 1.5)
    @State private var playerFacing = 0.0
    @State private var stick = CGVector.zero
    @State private var shootCD = 0.0
    @State private var timeLeft = 0.0
    @State private var bursts: [Burst] = []
    @State private var shakeTick = 0
    @State private var built = false
    @State private var demoFire = false     // FIRE button flashed in the demo
    // Presentation only: scorch marks left by kills, destroyed enemy colours, and the player's wreck.
    @State private var scorches: [CGPoint] = []
    @State private var killed: [Int] = []
    @State private var playerHit = false

    var body: some View {
        VStack(spacing: isDemo ? 6 : 10) {
            hud
            GeometryReader { geo in
                let lay = arenaLayout(geo.size)
                ZStack {
                    TankArena(walls: walls, cols: cols, rows: rows, cell: lay.cell, origin: lay.origin).equatable()
                    TimelineView(.animation(paused: bursts.isEmpty)) { tl in
                        Canvas { ctx, _ in drawEntities(ctx, lay, now: tl.date) }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipShape(RoundedRectangle(cornerRadius: isDemo ? 8 : 12))
                .screenShake(shakeTick, amount: 6)
            }
            controls
        }
        .padding(.horizontal, isDemo ? 8 : 12)
        .padding(.top, isDemo ? 8 : 14)
        .padding(.bottom, isDemo ? 8 : 12)
        .background(TankArt.card)
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { isDemo ? await runDemo() : await run() }
    }

    /// Tank Trouble-style scoreboard: one icon per enemy tank, greyed once it's destroyed.
    private var hud: some View {
        let icons = (enemies.map { ($0.tint, true) } + killed.map { ($0, false) }).sorted { $0.0 < $1.0 }
        return VStack(spacing: isDemo ? 0 : 8) {
            HStack(spacing: isDemo ? 8 : 12) {
                ForEach(icons, id: \.0) { tint, alive in
                    Canvas { ctx, s in
                        TankArt.tank(ctx, at: CGPoint(x: s.width * 0.44, y: s.height / 2), facing: 0,
                                     cell: s.height * 1.02, color: alive ? TankArt.enemy(tint) : Color(white: 0.72))
                    }
                    .frame(width: isDemo ? 28 : 36, height: isDemo ? 20 : 26)
                    .opacity(alive ? 1 : 0.55)
                }
            }
            .animation(.easeOut(duration: 0.2), value: killed.count)
            if !isDemo { timeBar.frame(height: 6).padding(.horizontal, 40) }
        }
    }

    // MARK: - Demo (live manual clip)

    /// A staged clean shot: the player faces a lone enemy down a clear lane and fires;
    /// the real ricochet-shell physics (`stepShells`) carries the shot in for the kill.
    private func runDemo() async {
        while !Task.isCancelled {
            demoSetup()
            try? await Task.sleep(for: .seconds(0.7))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.1)) { demoFire = true }
            shoot()                                    // fire straight down the lane
            Task { try? await Task.sleep(for: .seconds(0.18)); withAnimation(.easeIn(duration: 0.1)) { demoFire = false } }
            var frames = 0
            while phase == .play && !enemies.isEmpty && frames < 260 && !Task.isCancelled {
                _ = stepShells(dt: 0.016)              // advance only the shell (no enemy AI / timer)
                try? await Task.sleep(for: .seconds(0.016))
                frames += 1
            }
            try? await Task.sleep(for: .seconds(1.2))  // hold on ARENA CLEAR
        }
    }

    private func demoSetup() {
        // Borders + a couple of cover blocks kept off the firing lane (row 8).
        var w = Array(repeating: Array(repeating: false, count: cols), count: rows)
        for r in 0..<rows { w[r][0] = true; w[r][cols - 1] = true }
        for c in 0..<cols { w[0][c] = true; w[rows - 1][c] = true }
        for (r, c) in [(4, 4), (4, 5), (12, 6), (12, 7), (5, 9)] { w[r][c] = true }
        walls = w

        player = CGPoint(x: 3.5, y: 8.5)
        playerFacing = 0                               // pointing right, down the lane
        enemies = [Tank(pos: CGPoint(x: 9.5, y: 8.5), facing: .pi,
                        fireCD: 9999, roam: P(r: 8, c: 9), repick: 9999)]
        shells = []; bursts = []; stick = .zero; shootCD = 0
        scorches = []; killed = []; playerHit = false
        timeLeft = baseTime
        phase = .play
        built = true
    }

    // MARK: - Rendering

    private struct ArenaLayout {
        let cell: CGFloat
        let origin: CGPoint      // screen position of cell (0, 0)
    }

    /// Fits the arena into the play area. Only the inner face of a border cell can ever be touched,
    /// so the outer part of the border is trimmed away (Tank Trouble's thin frame). The squat demo
    /// card shows a band of rows around the duel.
    private func arenaLayout(_ s: CGSize) -> ArenaLayout {
        let trim = TankArena.trim
        let spanX = CGFloat(cols) - 2 * trim
        let spanY = isDemo ? 7 : CGFloat(rows) - 2 * trim
        let top = isDemo ? 5 : trim
        let cell = max(1, min(s.width / spanX, s.height / spanY))
        return ArenaLayout(cell: cell,
                           origin: CGPoint(x: (s.width - cell * spanX) / 2 - trim * cell,
                                           y: (s.height - cell * spanY) / 2 - top * cell))
    }

    /// Everything that moves: scorch marks, tanks, bullets and explosions, in one Canvas.
    private func drawEntities(_ ctx: GraphicsContext, _ lay: ArenaLayout, now: Date) {
        let c = lay.cell
        func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: lay.origin.x + p.x * c, y: lay.origin.y + p.y * c) }
        for s in scorches { TankArt.scorch(ctx, at: pt(s), cell: c) }
        for e in enemies { TankArt.tank(ctx, at: pt(e.pos), facing: e.facing, cell: c, color: TankArt.enemy(e.tint)) }
        if !playerHit { TankArt.tank(ctx, at: pt(player), facing: playerFacing, cell: c, color: TankArt.you) }
        for s in shells { TankArt.bullet(ctx, at: pt(s.pos), cell: c) }
        for b in bursts { TankArt.explosion(ctx, at: pt(b.pos), cell: c, t: now.timeIntervalSince(b.t0)) }
    }

    private var controls: some View {
        HStack {
            TankJoystick(vector: $stick, size: isDemo ? 74 : 120)
            Spacer()
            Button { shoot() } label: {
                Text(L("FIRE", "BẮN"))
                    .font(.system(size: isDemo ? 17 : 20, weight: .black, design: .rounded))
                    .foregroundStyle(demoFire ? .black : .white)
                    .frame(width: isDemo ? 78 : 100, height: isDemo ? 50 : 70)
                    .background(demoFire ? BananaTheme.banana : TankArt.wall, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .stroke(demoFire ? .white : .black.opacity(0.35), lineWidth: demoFire ? 3 : 1.5))
                    .shadow(color: .black.opacity(0.25), radius: 0, x: 0, y: demoFire ? 1 : 4)
                    .scaleEffect(demoFire ? 0.9 : 1)
                    .animation(.easeOut(duration: 0.1), value: demoFire)
            }
        }
        .padding(.horizontal, isDemo ? 14 : 20)
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac = baseTime > 0 ? timeLeft / baseTime : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color(white: 0.8))
                Capsule().fill(frac < 0.3 ? .red : BananaTheme.banana)
                    .frame(width: geo.size.width * max(0, frac))
                Capsule().stroke(.black.opacity(0.15), lineWidth: 1)
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
        if let first = bursts.first, Date().timeIntervalSince(first.t0) > 1.0 { bursts.removeFirst() }   // finished explosions

        // Player drive (axis-separated collision); turret eases toward the stick.
        let vx = Double(stick.dx) * playerSpeed * dt
        let vy = Double(stick.dy) * playerSpeed * dt
        if canStand(player.x + vx, player.y) { player.x += vx }
        if canStand(player.x, player.y + vy) { player.y += vy }
        if hypot(stick.dx, stick.dy) > 0.08 {
            let target = atan2(Double(stick.dy), Double(stick.dx))
            playerFacing += angleDiff(target, playerFacing) * min(1.0, dt * 14.0)
        }
        shootCD = max(0, shootCD - dt)

        // Enemies roam + shoot on a clear line.
        for i in enemies.indices {
            roamStep(&enemies[i], dt: dt)
            enemies[i].fireCD -= dt
            if enemies[i].fireCD <= 0, losClear(enemies[i].pos, player) {
                let a = atan2(player.y - enemies[i].pos.y, player.x - enemies[i].pos.x)
                enemies[i].facing = a
                enemies[i].fireCD = enemyFire
                fire(from: enemies[i].pos, angle: a, fromPlayer: false)
            }
        }

        if !stepShells(dt: dt) { return }

        timeLeft -= dt
        if timeLeft <= 0 { timeLeft = 0; fail() }
    }

    /// Advances shells (with wall ricochet) and resolves hits. Returns false if the game ended.
    private func stepShells(dt: Double) -> Bool {
        var survivors: [Shell] = []
        for var s in shells {
            s.arm = max(0, s.arm - dt)
            s.life -= dt
            if s.life <= 0 { continue }

            // Axis-separated bounce: reflect the component that would enter a wall.
            let nx = s.pos.x + Double(s.vel.dx) * dt
            if isWall(Int(floor(s.pos.y)), Int(floor(nx))) { s.vel.dx = -s.vel.dx } else { s.pos.x = nx }
            let ny = s.pos.y + Double(s.vel.dy) * dt
            if isWall(Int(floor(ny)), Int(floor(s.pos.x))) { s.vel.dy = -s.vel.dy } else { s.pos.y = ny }

            if s.arm <= 0 {
                // Player hit?
                if hypot(player.x - s.pos.x, player.y - s.pos.y) < 0.5 {
                    bursts.append(Burst(pos: player, color: BananaTheme.banana))
                    scorches.append(player)
                    playerHit = true
                    shakeTick += 1
                    fail(); return false
                }
                // Enemy hit (any shell is lethal to any tank — watch your ricochets)?
                if let hit = enemies.firstIndex(where: { hypot($0.pos.x - s.pos.x, $0.pos.y - s.pos.y) < 0.5 }) {
                    bursts.append(Burst(pos: enemies[hit].pos, color: Color(red: 1, green: 0.35, blue: 0.3)))
                    scorches.append(enemies[hit].pos)
                    killed.append(enemies[hit].tint)
                    enemies.remove(at: hit)
                    shakeTick += 1
                    Haptics.tap(); SoundManager.shared.tap()
                    continue   // shell consumed
                }
            }
            survivors.append(s)
        }
        shells = survivors
        if enemies.isEmpty { win(); return false }
        return true
    }

    private func shoot() {
        guard phase == .play, shootCD <= 0 else { return }
        guard shells.filter(\.fromPlayer).count < maxPlayerShots else { return }
        shootCD = playerShootCD
        fire(from: player, angle: playerFacing, fromPlayer: true)
        SoundManager.shared.tap(); Haptics.tap()
    }

    private func fire(from: CGPoint, angle: Double, fromPlayer: Bool) {
        let muzzle = CGPoint(x: from.x + cos(angle) * 0.55, y: from.y + sin(angle) * 0.55)
        shells.append(Shell(pos: muzzle,
                            vel: CGVector(dx: cos(angle) * shellSpeed, dy: sin(angle) * shellSpeed),
                            life: shellLife, arm: shellArm, fromPlayer: fromPlayer))
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

    // MARK: - Enemy roam

    private func roamStep(_ e: inout Tank, dt: Double) {
        e.repick -= dt
        let target = center(e.roam)
        let dx = target.x - e.pos.x, dy = target.y - e.pos.y
        let d = hypot(dx, dy)
        if d < 0.35 || e.repick <= 0 {
            e.roam = randomOpenCell()
            e.repick = Double.random(in: 1.6...3.2)
        }
        guard d > 0.0001 else { return }
        let sp = enemySpeed * dt
        let mx = dx / d * sp, my = dy / d * sp
        var moved = false
        if canStand(e.pos.x + mx, e.pos.y) { e.pos.x += mx; moved = true }
        if canStand(e.pos.x, e.pos.y + my) { e.pos.y += my; moved = true }
        if !moved { e.repick = 0 }   // wedged — pick a new target next frame
        // Body faces travel direction unless it just aimed to fire (fireCD freshly set).
        e.facing += angleDiff(atan2(dy, dx), e.facing) * min(1.0, dt * 10.0)
    }

    private func center(_ p: P) -> CGPoint { CGPoint(x: Double(p.c) + 0.5, y: Double(p.r) + 0.5) }

    private func randomOpenCell() -> P {
        for _ in 0..<40 {
            let r = Int.random(in: 1..<(rows - 1)), c = Int.random(in: 1..<(cols - 1))
            if !isWall(r, c) { return P(r: r, c: c) }
        }
        return P(r: 1, c: 1)
    }

    // MARK: - Geometry helpers (shared shape with Assassin)

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

    private func canStand(_ x: Double, _ y: Double) -> Bool {
        let rad = 0.30
        for cx in [x - rad, x + rad] {
            for cy in [y - rad, y + rad] {
                if isWall(Int(floor(cy)), Int(floor(cx))) { return false }
            }
        }
        return true
    }

    // MARK: - Setup (open arena; spread player + enemies)

    private func setup() {
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

        // Enemies spread out.
        var starts: [P] = []
        for cand in open.shuffled() {
            if starts.allSatisfy({ manhattan($0, cand) >= 4 }) {
                starts.append(cand)
                if starts.count == enemyCount { break }
            }
        }
        while starts.count < enemyCount, let any = open.randomElement() { starts.append(any) }
        enemies = starts.map { s in
            Tank(pos: center(s), facing: Double.random(in: 0..<(2 * .pi)),
                 fireCD: Double.random(in: 0.6...enemyFire), roam: randomOpenCell(),
                 repick: Double.random(in: 1.2...2.6))
        }

        // Player starts farthest from every enemy.
        let startCell = open.max { minDist($0, starts) < minDist($1, starts) } ?? P(r: 1, c: 1)
        player = center(startCell)
        playerFacing = 0
        stick = .zero; shells = []; bursts = []; shootCD = 0
        for i in enemies.indices { enemies[i].tint = i }
        scorches = []; killed = []; playerHit = false
        timeLeft = baseTime
        phase = .play
    }

    private func manhattan(_ a: P, _ b: P) -> Int { abs(a.r - b.r) + abs(a.c - b.c) }
    private func minDist(_ p: P, _ set: [P]) -> Int { set.map { manhattan($0, p) }.min() ?? .max }

}

// MARK: - Virtual joystick (relative analog stick; snaps back on release)

private struct TankJoystick: View {
    @Binding var vector: CGVector
    let size: CGFloat
    @State private var knob: CGSize = .zero

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(white: 0.74), Color(white: 0.84)], center: .center,
                                         startRadius: 0, endRadius: size / 2))
                .overlay(Circle().stroke(Color(white: 0.6), lineWidth: 2))
            Circle().fill(RadialGradient(colors: [BananaTheme.banana.lit(0.35), BananaTheme.banana, BananaTheme.banana.shade(0.2)],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.26))
                .frame(width: size * 0.42, height: size * 0.42)
                .overlay(Circle().stroke(BananaTheme.banana.shade(0.55), lineWidth: 2))
                .shadow(color: .black.opacity(0.25), radius: 0, x: 0, y: 3)
                .offset(knob)
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

// MARK: - Tank Trouble art

/// Flat Tank Trouble tanks (you in banana yellow, rivals red / green / blue / orange), tiny black
/// bullets, a light tiled floor with charcoal walls, fireballs and scorch marks.
private enum TankArt {
    static let card = Color(red: 0.9, green: 0.9, blue: 0.89)
    static let wall = Color(red: 0.27, green: 0.28, blue: 0.3)
    static let you = Color(red: 0.98, green: 0.79, blue: 0.16)
    static func enemy(_ i: Int) -> Color {
        [Color(red: 0.86, green: 0.13, blue: 0.1), Color(red: 0.33, green: 0.64, blue: 0.25),
         Color(red: 0.17, green: 0.32, blue: 0.93), Color(red: 0.95, green: 0.5, blue: 0.1)][((i % 4) + 4) % 4]
    }

    private static func disc(_ p: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }

    /// A top-down tank pointing along `facing`: treads, a hull, a round turret and the barrel.
    static func tank(_ ctx: GraphicsContext, at p: CGPoint, facing: Double, cell c: CGFloat, color: Color) {
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        g.rotate(by: .radians(facing))
        let L = c * 0.94, W = c * 0.74
        let outline = color.shade(0.6)
        var s = g
        s.opacity = 0.2
        s.fill(Path(roundedRect: CGRect(x: -L / 2 + c * 0.05, y: -W / 2 + c * 0.08, width: L, height: W), cornerRadius: c * 0.12),
               with: .color(.black))
        // Treads.
        for top in [true, false] {
            let tr = CGRect(x: -L / 2, y: top ? -W / 2 : W / 2 - W * 0.26, width: L, height: W * 0.26)
            g.fill(Path(roundedRect: tr, cornerRadius: c * 0.06), with: .color(color.shade(0.5)))
            var marks = Path()
            var x = -L / 2 + c * 0.09
            while x < L / 2 - c * 0.05 {
                marks.move(to: CGPoint(x: x, y: tr.minY + 1)); marks.addLine(to: CGPoint(x: x, y: tr.maxY - 1))
                x += c * 0.13
            }
            g.stroke(marks, with: .color(.black.opacity(0.3)), lineWidth: max(0.5, c * 0.025))
        }
        // Hull.
        let hull = CGRect(x: -L / 2 + c * 0.05, y: -W / 2 + W * 0.17, width: L - c * 0.1, height: W * 0.66)
        g.fill(Path(roundedRect: hull, cornerRadius: c * 0.07),
               with: .linearGradient(Gradient(colors: [color.lit(0.18), color, color.shade(0.12)]),
                                     startPoint: CGPoint(x: 0, y: hull.minY), endPoint: CGPoint(x: 0, y: hull.maxY)))
        g.stroke(Path(roundedRect: hull, cornerRadius: c * 0.07), with: .color(outline), lineWidth: max(1, c * 0.035))
        // Barrel, then the turret on top of its root.
        let barrel = CGRect(x: 0, y: -c * 0.07, width: c * 0.64, height: c * 0.14)
        g.fill(Path(roundedRect: barrel, cornerRadius: c * 0.03), with: .color(color.shade(0.28)))
        g.stroke(Path(roundedRect: barrel, cornerRadius: c * 0.03), with: .color(outline), lineWidth: max(1, c * 0.03))
        let tr = c * 0.23
        let tc = CGPoint(x: -c * 0.03, y: 0)
        g.fill(disc(tc, tr), with: .radialGradient(Gradient(colors: [color.lit(0.25), color.shade(0.12), color.shade(0.3)]),
                                                   center: CGPoint(x: tc.x - tr * 0.3, y: tc.y - tr * 0.35),
                                                   startRadius: 0, endRadius: tr * 1.3))
        g.stroke(disc(tc, tr), with: .color(outline), lineWidth: max(1, c * 0.035))
    }

    /// A small black ball — every bullet is the same, and every bullet kills.
    static func bullet(_ ctx: GraphicsContext, at p: CGPoint, cell c: CGFloat) {
        let r = max(2, c * 0.12)
        ctx.fill(disc(CGPoint(x: p.x + r * 0.25, y: p.y + r * 0.35), r), with: .color(.black.opacity(0.18)))
        ctx.fill(disc(p, r), with: .radialGradient(Gradient(colors: [Color(white: 0.45), Color(white: 0.08)]),
                                                   center: CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.35),
                                                   startRadius: 0, endRadius: r * 1.3))
    }

    static func scorch(_ ctx: GraphicsContext, at p: CGPoint, cell c: CGFloat) {
        for (k, f) in [(0.0, 0.62), (1.3, 0.42), (2.6, 0.38), (4.1, 0.46), (5.2, 0.34)].enumerated() {
            let off = k == 0 ? 0 : c * 0.26
            let q = CGPoint(x: p.x + CGFloat(cos(f.0)) * off, y: p.y + CGFloat(sin(f.0)) * off)
            ctx.fill(disc(q, c * CGFloat(f.1)), with: .color(.black.opacity(0.1)))
        }
    }

    /// Fireball, smoke puffs and flying chips over ~0.9 s.
    static func explosion(_ ctx: GraphicsContext, at p: CGPoint, cell c: CGFloat, t: Double) {
        guard t >= 0, t < 0.9 else { return }
        for k in 0..<7 {
            let a = Double(k) * 0.9 + 0.3
            let d = c * CGFloat(0.2 + t * 1.0)
            let q = CGPoint(x: p.x + CGFloat(cos(a)) * d, y: p.y + CGFloat(sin(a)) * d - CGFloat(t) * c * 0.35)
            ctx.fill(disc(q, c * CGFloat(0.2 + t * 0.42)), with: .color(Color(white: 0.4).opacity(max(0, 0.6 - t * 0.66))))
        }
        if t < 0.42 {
            let k = t / 0.42
            let r = c * CGFloat(0.4 + k * 0.65)
            ctx.fill(disc(p, r), with: .radialGradient(Gradient(colors: [.white, Color(red: 1, green: 0.88, blue: 0.35),
                                                                        Color(red: 1, green: 0.45, blue: 0.1),
                                                                        Color(red: 0.85, green: 0.15, blue: 0.05).opacity(0)]),
                                                     center: p, startRadius: 0, endRadius: r))
        }
        for k in 0..<8 {
            let a = Double(k) * 0.785 + 0.2
            let d = c * CGFloat(0.3 + t * 2.1)
            let q = CGPoint(x: p.x + CGFloat(cos(a)) * d, y: p.y + CGFloat(sin(a)) * d + CGFloat(t * t) * c * 0.8)
            let s = c * 0.08 * CGFloat(max(0, 1 - t / 0.9))
            ctx.fill(Path(CGRect(x: q.x - s, y: q.y - s, width: s * 2, height: s * 2)), with: .color(Color(white: 0.22)))
        }
    }
}

/// The static maze: a light tiled floor with charcoal walls. Equatable, so the 60 fps loop never
/// redraws it — only a new level (or a new size) does.
private struct TankArena: View, Equatable {
    let walls: [[Bool]]
    let cols: Int, rows: Int
    let cell: CGFloat
    let origin: CGPoint

    /// Share of each border cell that is trimmed away (never reachable, so never drawn).
    static let trim: CGFloat = 0.7

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(TankArt.card))
            guard walls.count == rows else { return }
            func rect(_ r: Int, _ c: Int) -> CGRect {
                var rc = CGRect(x: origin.x + CGFloat(c) * cell, y: origin.y + CGFloat(r) * cell, width: cell, height: cell)
                let keep = cell * (1 - Self.trim)
                if r == 0 { rc = CGRect(x: rc.minX, y: rc.maxY - keep, width: rc.width, height: keep) }
                if r == rows - 1 { rc = CGRect(x: rc.minX, y: rc.minY, width: rc.width, height: keep) }
                if c == 0 { rc = CGRect(x: rc.maxX - keep, y: rc.minY, width: keep, height: rc.height) }
                if c == cols - 1 { rc = CGRect(x: rc.minX, y: rc.minY, width: keep, height: rc.height) }
                return rc
            }
            // Floor tiles in a faint checker.
            for r in 0..<rows {
                for c in 0..<cols where !walls[r][c] {
                    ctx.fill(Path(rect(r, c).insetBy(dx: -0.3, dy: -0.3)),
                             with: .color((r + c) % 2 == 0 ? Color(white: 0.97) : Color(white: 0.935)))
                }
            }
            // Walls cast a soft shadow down-right, then the charcoal blocks with a lit top edge.
            for r in 0..<rows {
                for c in 0..<cols where walls[r][c] {
                    ctx.fill(Path(rect(r, c).offsetBy(dx: cell * 0.1, dy: cell * 0.14)), with: .color(.black.opacity(0.1)))
                }
            }
            for r in 0..<rows {
                for c in 0..<cols where walls[r][c] {
                    let rc = rect(r, c).insetBy(dx: -0.3, dy: -0.3)
                    ctx.fill(Path(rc), with: .color(TankArt.wall))
                    if r == 0 || !walls[r - 1][c] {
                        ctx.fill(Path(CGRect(x: rc.minX, y: rc.minY, width: rc.width, height: max(1.5, cell * 0.09))),
                                 with: .color(Color(white: 0.45)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
