//
//  CatBurglarGame.swift
//  A Banana Game
//
//  Brain / stealth — a Monaco-style heist. Steer the burglar with the d-pad through a guarded
//  vault and scoop up every gold stash, then slip out the exit. Guards sweep bright vision cones;
//  step into one (out of the shadows) and the ALARM trips — every guard turns hostile and a swarm
//  of reinforcements pours in through the red door, all firing ruthlessly. Dark SHADOW tiles hide
//  you from the cones, so read the sweeps and dash between shadows. The exit only unlocks once the
//  last coin is grabbed. Take a bullet or run out the clock and it's back to level 1.
//
//  7 levels: far more loot, more guards, wider and longer cones, faster patrols, and — once the
//  alarm is up — a bigger, faster-firing swarm.
//
//  Drawn as a mansion at night with a literal cat burglar: basket-weave parquet under moonlight,
//  soft indigo pools for the shadow tiles, plum walls with gold molding, furniture on every block of
//  cover (palms, armchairs, sofas, bookshelves, a grand piano, a billiard table…), stacks of gold
//  coins for the stashes, guard dogs in navy vests and peaked caps sweeping flashlight cones (red
//  once the alarm trips), the guards' red door with a siren lamp, a locked door that opens into a
//  green-lit way out, and a banana-yellow tabby in a black domino mask with a swag sack.
//

import SwiftUI

enum CatBurglarGame {
    static let definition = GameDefinition(
        id: "cat-burglar",
        title: "Cat Burglar",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        locksFeed: false,
        manual: GameManual(
            bullets: [
                "Steer with the d-pad. Grab every gold stash, then reach the exit.",
                "The exit unlocks once all the loot is gone.",
                "Guards sweep vision cones — get seen in the open and the alarm trips a firing swarm.",
                "Dark shadow tiles hide you; a bullet or a timeout sends you to level 1.",
            ],
            bulletsVI: [
                "Điều khiển bằng d-pad. Lấy hết mọi túi vàng, rồi đến lối ra.",
                "Lối ra mở khi đã lấy hết chiến lợi phẩm.",
                "Lính gác quét tầm nhìn — bị thấy ngoài trống là báo động và một bầy nổ súng.",
                "Ô bóng tối giúp bạn ẩn mình; trúng đạn hoặc hết giờ sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(CatBurglarView(level: level, onWin: onWin, onFail: onFail))
        },
        prefetch: { level in CatBurglarView(level: level, onWin: {}, onFail: {}).prefetchBoard() }
    )
}

struct CatBurglarView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    private let cols = 13
    private let rows = 17

    // MARK: Difficulty (all derived from `level`)
    private var guardCount: Int      { [1, 1, 2, 3, 3, 4, 4][min(level, 7) - 1] }
    private var lootCount: Int       { [10, 12, 14, 16, 18, 20, 24][min(level, 7) - 1] }
    private var patrolSpeed: Double  { [1.3, 1.5, 1.7, 1.9, 2.1, 2.4, 2.7][min(level, 7) - 1] }
    private var chaseSpeed: Double   { patrolSpeed + 1.1 }
    private var visionRange: Double  { [3.2, 3.6, 4.0, 4.4, 4.8, 5.2, 5.6][min(level, 7) - 1] }
    private var visionHalfDeg: Double { [22, 26, 30, 34, 38, 42, 46][min(level, 7) - 1] }
    private var shadowFraction: Double { [0.30, 0.26, 0.22, 0.18, 0.14, 0.11, 0.08][min(level, 7) - 1] }
    private var coverBlocks: Int     { 4 + level }
    private var reinforcements: Int  { [4, 5, 6, 7, 8, 9, 10][min(level, 7) - 1] }
    private var guardFireInterval: Double { [1.2, 1.1, 1.0, 0.9, 0.8, 0.7, 0.6][min(level, 7) - 1] }
    private var baseTime: Double     { Double(28 + lootCount * 3) }
    private var alarmBoost: Double   { Double(10 + reinforcements * 3) }

    private let playerSpeed: Double = 3.7
    private let guardProjSpeed: Double = 6.0
    private let fireRange: Double = 8.0
    private var visionHalf: Double { visionHalfDeg * .pi / 180.0 }

    private struct P: Hashable { let r: Int; let c: Int }
    private struct Guard: Identifiable {
        let id = UUID()
        var pos: CGPoint
        var path: [P]
        var idx: Int
        var dir: Int
        var facing: Double
        var alerted: Bool = false
        var fireCD: Double = 0
    }
    private struct Coin: Identifiable { let id = UUID(); let cell: P }
    private struct Shot: Identifiable { let id = UUID(); var pos: CGPoint; var vel: CGVector; var life: Double }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var walls: [[Bool]] = []
    @State private var shadows: Set<P> = []
    @State private var guards: [Guard] = []
    @State private var coins: [Coin] = []
    @State private var shots: [Shot] = []
    @State private var player = CGPoint(x: 1.5, y: 1.5)
    @State private var exitCell = P(r: 1, c: 1)
    @State private var doorCell = P(r: 1, c: 1)
    @State private var moveDir = CGVector.zero
    @State private var alarmRaised = false
    @State private var timeLeft = 0.0
    @State private var maxTime = 0.0
    @State private var built = false
    @State private var ready = false
    @State private var catFacing = 0.0          // presentation only: which way the cat is turned

    private var lootLeft: Int { coins.count }
    private var exitOpen: Bool { coins.isEmpty }

    var body: some View {
        Group {
            if ready { gameBody }
            else { BrainstormingView(skyTop: Color(red: 0.1, green: 0.09, blue: 0.17), skyBottom: Color(red: 0.03, green: 0.03, blue: 0.07)) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { isDemo ? await runDemo() : await run() }
        // The cat turns to face where it's heading (presentation only).
        .onChange(of: moveDir) { _, d in if d != .zero { catFacing = atan2(d.dy, d.dx) } }
    }

    private var gameBody: some View {
        Group {
            if isDemo {
                // The squat manual card: the mansion on the left, a compact d-pad beside it.
                HStack(spacing: 10) {
                    board
                    dpad
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    header
                    timeBar.frame(height: 5).padding(.horizontal, 50)
                    board.padding(.horizontal, 12)
                    dpad
                }
                .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CBArt.night)
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
    }

    private var header: some View {
        HStack(spacing: 10) {
            CBCoinIcon().frame(width: 24, height: 22)
            Text(exitOpen ? L("REACH THE EXIT", "ĐẾN LỐI RA") : L("\(lootLeft) stash\(lootLeft == 1 ? "" : "es") left", "còn \(lootLeft) túi vàng"))
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(exitOpen ? CBArt.exitGreen : CBArt.gold)
            if alarmRaised {
                Text(L("ALARM", "BÁO ĐỘNG"))
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(red: 0.9, green: 0.15, blue: 0.17), in: Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 22)
    }

    private var board: some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width
            let h: CGFloat = geo.size.height
            let cell: CGFloat = min(w / CGFloat(cols), h / CGFloat(rows))
            let ox: CGFloat = (w - cell * CGFloat(cols)) / 2
            let oy: CGFloat = (h - cell * CGFloat(rows)) / 2

            ZStack {
                CBMansion(walls: walls, shadows: Set(shadows.map { $0.r * cols + $0.c }),
                          exitR: exitCell.r, exitC: exitCell.c, doorR: doorCell.r, doorC: doorCell.c,
                          exitOpen: exitOpen, alarm: alarmRaised, cell: cell, ox: ox, oy: oy)
                    .equatable()
                // Loot, flashlight cones, bullets, guard dogs and the cat, in one pass.
                Canvas { ctx, _ in drawAction(ctx, cell: cell, ox: ox, oy: oy) }
                    .allowsHitTesting(false)
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func drawAction(_ ctx: GraphicsContext, cell: CGFloat, ox: CGFloat, oy: CGFloat) {
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + CGFloat(x) * cell, y: oy + CGFloat(y) * cell) }
        for coin in coins {
            CBArt.coins(ctx, at: pt(Double(coin.cell.c) + 0.5, Double(coin.cell.r) + 0.5), cell: cell)
        }
        // Flashlight cones: exactly the geometry the guards see with (not clipped by furniture).
        for g in guards {
            let origin = pt(g.pos.x, g.pos.y)
            let R: CGFloat = CGFloat(visionRange) * cell
            var cone = Path()
            cone.move(to: origin)
            cone.addArc(center: origin, radius: R, startAngle: .radians(g.facing - visionHalf),
                        endAngle: .radians(g.facing + visionHalf), clockwise: false)
            cone.closeSubpath()
            let col = g.alerted ? Color(red: 1, green: 0.25, blue: 0.22) : Color(red: 1, green: 0.93, blue: 0.62)
            ctx.fill(cone, with: .radialGradient(Gradient(colors: [col.opacity(0.55), col.opacity(0.14)]),
                                                 center: origin, startRadius: cell * 0.3, endRadius: R))
            ctx.stroke(cone, with: .color(col.opacity(0.85)), lineWidth: 1.5)
        }
        for s in shots {
            let p = pt(s.pos.x, s.pos.y)
            let speed = max(0.001, hypot(s.vel.dx, s.vel.dy))
            let tail = CGPoint(x: p.x - s.vel.dx / speed * cell * 0.55, y: p.y - s.vel.dy / speed * cell * 0.55)
            var streak = Path()
            streak.move(to: tail)
            streak.addLine(to: p)
            ctx.stroke(streak, with: .linearGradient(Gradient(colors: [Color.red.opacity(0), Color(red: 1, green: 0.35, blue: 0.3)]), startPoint: tail, endPoint: p),
                       style: StrokeStyle(lineWidth: cell * 0.16, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - cell * 0.09, y: p.y - cell * 0.09, width: cell * 0.18, height: cell * 0.18)), with: .color(.white))
        }
        for g in guards {
            CBArt.guardDog(ctx, at: pt(g.pos.x, g.pos.y), facing: g.facing, cell: cell, alerted: g.alerted)
        }
        // The cat dims while it hides on a shadow tile.
        let here = P(r: Int(floor(player.y)), c: Int(floor(player.x)))
        CBArt.cat(ctx, at: pt(player.x, player.y), facing: catFacing, cell: cell, hidden: shadows.contains(here))
    }

    private var dpad: some View {
        VStack(spacing: isDemo ? 4 : 6) {
            dpadButton(0, -1, "chevron.up")
            HStack(spacing: isDemo ? 4 : 6) {
                dpadButton(-1, 0, "chevron.left")
                dpadButton(1, 0, "chevron.right")
            }
            dpadButton(0, 1, "chevron.down")
        }
        .padding(.bottom, isDemo ? 0 : 6)
    }

    private func dpadButton(_ dx: Double, _ dy: Double, _ icon: String) -> some View {
        let pressed = moveDir.dx == dx && moveDir.dy == dy   // the held arrow lights up (the demo's too)
        return Image(systemName: icon)
            .font(.system(size: isDemo ? 16 : 22, weight: .black))
            .foregroundStyle(pressed ? .black : CBArt.gold)
            .frame(width: isDemo ? 44 : 74, height: isDemo ? 36 : 52)
            .background(pressed ? CBArt.gold : Color(red: 0.14, green: 0.11, blue: 0.19), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(pressed ? Color.white : CBArt.gold.opacity(0.6), lineWidth: pressed ? 3 : 1.5))
            .scaleEffect(pressed ? 0.9 : 1)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if phase == .play { moveDir = CGVector(dx: dx, dy: dy) } }
                    .onEnded { _ in if moveDir.dx == dx && moveDir.dy == dy { moveDir = .zero } }
            )
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac: Double = maxTime > 0 ? timeLeft / maxTime : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(frac < 0.3 ? .red : CBArt.gold)
                    .frame(width: geo.size.width * max(0, frac))
            }
        }
    }

    // MARK: - Flow

    /// Hands this level's board build to `BoardCache` so it can run during the countdown.
    func prefetchBoard() {
        let (c, r, cb, gc, lc, sf) = (cols, rows, coverBlocks, guardCount, lootCount, shadowFraction)
        BoardCache.prefetch(boardKey) { Self.generate(cols: c, rows: r, coverBlocks: cb, guardCount: gc, lootCount: lc, shadowFraction: sf) }
    }
    private var boardKey: String { BoardCache.key("cat-burglar", level: level) }

    private func run() async {
        if !built {
            let (c, r, cb, gc, lc, sf) = (cols, rows, coverBlocks, guardCount, lootCount, shadowFraction)
            let t0 = Date()
            let board = await BoardCache.take(boardKey) { Self.generate(cols: c, rows: r, coverBlocks: cb, guardCount: gc, lootCount: lc, shadowFraction: sf) }
            guard !Task.isCancelled else { return }
            await BoardCache.holdBrainstorm(since: t0, minimum: 0.6)
            guard !Task.isCancelled else { return }
            walls = board.walls
            guards = board.guards
            coins = board.coins
            shadows = board.shadows
            exitCell = board.exit
            doorCell = board.door
            player = CGPoint(x: Double(board.start.c) + 0.5, y: Double(board.start.r) + 0.5)
            shots = []
            alarmRaised = false
            moveDir = .zero
            timeLeft = baseTime; maxTime = baseTime
            built = true
            ready = true
            phase = .play
        }
        var last = Date()
        while !Task.isCancelled && phase == .play {
            try? await Task.sleep(for: .seconds(0.016))
            let now = Date()
            let dt = min(0.05, now.timeIntervalSince(last)); last = now
            step(dt: dt)
        }
    }

    // MARK: - Demo (live manual clip)
    // A fixed Level-1 vault (1 guard, 10 stashes). The loot lies along one sweep: right, down
    // column 5, across row 13, down to the exit. The guard patrols column 8 (rows 4–12), cone
    // pointing along its beat; its only reach onto the route is where row 13 crosses below it,
    // and that stretch is SHADOW — so you slip past in the dark. The d-pad is held for each leg
    // through the real `step` at a fixed 1/60s: loot, exit unlocks, walk out → real win().
    private static let demoLegs: [(dx: Double, dy: Double, to: P)] = [
        (1, 0, P(r: 1, c: 5)), (0, 1, P(r: 13, c: 5)), (1, 0, P(r: 13, c: 11)), (0, 1, P(r: 15, c: 11)),
    ]

    private func demoSetup() {
        var w = Array(repeating: Array(repeating: false, count: cols), count: rows)
        for r in 0..<rows { w[r][0] = true; w[r][cols - 1] = true }
        for c in 0..<cols { w[0][c] = true; w[rows - 1][c] = true }
        for (r, c) in [(3, 2), (3, 3), (4, 2), (4, 3), (7, 10), (8, 10), (7, 11), (10, 2), (11, 2), (15, 7)] {
            w[r][c] = true
        }
        walls = w
        guards = [Guard(pos: center(P(r: 4, c: 8)), path: (4...12).map { P(r: $0, c: 8) }, idx: 0, dir: 1,
                        facing: .pi / 2)]
        coins = [P(r: 1, c: 3), P(r: 1, c: 5), P(r: 4, c: 5), P(r: 7, c: 5), P(r: 10, c: 5),
                 P(r: 13, c: 5), P(r: 13, c: 7), P(r: 13, c: 9), P(r: 13, c: 11), P(r: 14, c: 11)].map { Coin(cell: $0) }
        shadows = [P(r: 1, c: 1), P(r: 13, c: 7), P(r: 13, c: 8), P(r: 13, c: 9), P(r: 6, c: 3), P(r: 5, c: 10),
                   P(r: 9, c: 7), P(r: 2, c: 9), P(r: 12, c: 3), P(r: 11, c: 10), P(r: 15, c: 4), P(r: 8, c: 6)]
        exitCell = P(r: 15, c: 11)
        doorCell = P(r: 15, c: 1)
        player = center(P(r: 1, c: 1))
        shots = []
        alarmRaised = false
        moveDir = .zero
        timeLeft = baseTime; maxTime = baseTime
        built = true
        ready = true
        phase = .play
    }

    private func runDemo() async {
        let dt = 1.0 / 60.0
        while !Task.isCancelled {
            demoSetup()
            try? await Task.sleep(for: .seconds(0.6))
            var leg = 0
            while !Task.isCancelled && phase == .play {
                if leg < Self.demoLegs.count {
                    let l = Self.demoLegs[leg]
                    let goal = center(l.to)
                    // Release this arrow on reaching the leg's corner, then press the next one.
                    if abs(player.x - goal.x) < 0.07 && abs(player.y - goal.y) < 0.07 {
                        leg += 1
                        moveDir = .zero
                    } else {
                        moveDir = CGVector(dx: l.dx, dy: l.dy)
                    }
                }
                step(dt: dt)
                try? await Task.sleep(for: .seconds(0.016))
            }
            moveDir = .zero
            // Loot cleared and out the exit → the real win() ran (onWin is a no-op). Hold, loop.
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    private func step(dt: Double) {
        guard phase == .play else { return }

        // Player movement (axis-separated wall collision).
        let vx = moveDir.dx * playerSpeed * dt
        let vy = moveDir.dy * playerSpeed * dt
        if canStand(player.x + vx, player.y) { player.x += vx }
        if canStand(player.x, player.y + vy) { player.y += vy }

        // Guards patrol, or (once the alarm is up) chase and shoot.
        for i in guards.indices {
            if guards[i].alerted { chase(&guards[i], dt: dt) }
            else { patrol(&guards[i], dt: dt) }
            if guards[i].alerted {
                guards[i].fireCD -= dt
                let d = hypot(player.x - guards[i].pos.x, player.y - guards[i].pos.y)
                if guards[i].fireCD <= 0, d <= fireRange, losClear(guards[i].pos, player) {
                    let a = atan2(player.y - guards[i].pos.y, player.x - guards[i].pos.x)
                    guards[i].facing = a
                    guards[i].fireCD = guardFireInterval
                    shots.append(Shot(pos: guards[i].pos,
                                      vel: CGVector(dx: cos(a) * guardProjSpeed, dy: sin(a) * guardProjSpeed),
                                      life: 2.4))
                }
            }
        }

        // Collect loot.
        let pc = P(r: Int(floor(player.y)), c: Int(floor(player.x)))
        if let hit = coins.firstIndex(where: { $0.cell == pc }) {
            coins.remove(at: hit)
            Haptics.tap(); SoundManager.shared.tap()
        }

        // Detection — trips the alarm the first time (unless hiding in shadow).
        if !alarmRaised, !shadows.contains(pc) {
            for g in guards where spots(g, target: player) { raiseAlarm(); break }
        }

        // Bullets.
        if !stepShots(dt: dt) { return }

        // Reach exit once loot cleared.
        if exitOpen {
            let d = hypot(player.x - (Double(exitCell.c) + 0.5), player.y - (Double(exitCell.r) + 0.5))
            if d < 0.5 { win(); return }
        }

        timeLeft -= dt
        if timeLeft <= 0 { timeLeft = 0; fail() }
    }

    private func stepShots(dt: Double) -> Bool {
        var survivors: [Shot] = []
        for var s in shots {
            s.pos.x += s.vel.dx * dt
            s.pos.y += s.vel.dy * dt
            s.life -= dt
            if s.life <= 0 { continue }
            if isWall(Int(floor(s.pos.y)), Int(floor(s.pos.x))) { continue }
            if hypot(player.x - s.pos.x, player.y - s.pos.y) < 0.42 { fail(); return false }
            survivors.append(s)
        }
        shots = survivors
        return true
    }

    private func raiseAlarm() {
        guard !alarmRaised else { return }
        alarmRaised = true
        for i in guards.indices {
            guards[i].alerted = true
            guards[i].fireCD = Double.random(in: 0.2...guardFireInterval)
        }
        let d = center(doorCell)
        for k in 0..<reinforcements {
            guards.append(Guard(pos: d, path: [doorCell], idx: 0, dir: 1,
                                facing: atan2(player.y - d.y, player.x - d.x),
                                alerted: true, fireCD: Double(k) * 0.3 + 0.4))
        }
        timeLeft += alarmBoost; maxTime += alarmBoost
        SoundManager.shared.error(); Haptics.warning()
    }

    private func patrol(_ g: inout Guard, dt: Double) {
        guard g.path.count >= 2 else { return }
        let wp = center(g.path[g.idx])
        let dx = wp.x - g.pos.x, dy = wp.y - g.pos.y
        let d = hypot(dx, dy)
        let sd = patrolSpeed * dt
        if d <= sd || d < 0.0001 {
            g.pos = wp
            var ni = g.idx + g.dir
            if ni < 0 || ni >= g.path.count { g.dir = -g.dir; ni = g.idx + g.dir }
            ni = max(0, min(g.path.count - 1, ni))
            let nwp = center(g.path[ni])
            g.facing = atan2(nwp.y - g.pos.y, nwp.x - g.pos.x)
            g.idx = ni
        } else {
            g.pos.x += dx / d * sd
            g.pos.y += dy / d * sd
            g.facing = atan2(dy, dx)
        }
    }

    private func chase(_ g: inout Guard, dt: Double) {
        let dx = player.x - g.pos.x, dy = player.y - g.pos.y
        let d = hypot(dx, dy)
        if d > 0.0001 { g.facing = atan2(dy, dx) }
        guard d > 0.4 else { return }
        let sp = chaseSpeed * dt
        let nx = dx / d * sp, ny = dy / d * sp
        if canStand(g.pos.x + nx, g.pos.y) { g.pos.x += nx }
        if canStand(g.pos.x, g.pos.y + ny) { g.pos.y += ny }
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

    // MARK: - Detection helpers

    private func spots(_ g: Guard, target: CGPoint) -> Bool {
        let dx = target.x - g.pos.x, dy = target.y - g.pos.y
        let dist = hypot(dx, dy)
        guard dist <= visionRange, dist > 0.0001 else { return false }
        let off = abs(angleDiff(atan2(dy, dx), g.facing))
        guard off <= visionHalf else { return false }
        return losClear(g.pos, target)
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

    private func canStand(_ x: Double, _ y: Double) -> Bool {
        let rad = 0.28
        for cx in [x - rad, x + rad] {
            for cy in [y - rad, y + rad] {
                if isWall(Int(floor(cy)), Int(floor(cx))) { return false }
            }
        }
        return true
    }

    private func center(_ p: P) -> CGPoint { CGPoint(x: Double(p.c) + 0.5, y: Double(p.r) + 0.5) }
    private func manhattan(_ a: P, _ b: P) -> Int { abs(a.r - b.r) + abs(a.c - b.c) }
    private func minDist(_ p: P, _ set: [P]) -> Int { set.map { manhattan($0, p) }.min() ?? .max }

    // MARK: - Generation (pure/static → runs off the main actor via run())

    private struct CBoard {
        var walls: [[Bool]]
        var guards: [Guard]
        var coins: [Coin]
        var shadows: Set<P>
        var start: P
        var exit: P
        var door: P
    }

    private static func center(_ p: P) -> CGPoint { CGPoint(x: Double(p.c) + 0.5, y: Double(p.r) + 0.5) }
    private static func manhattan(_ a: P, _ b: P) -> Int { abs(a.r - b.r) + abs(a.c - b.c) }

    private static func generate(cols: Int, rows: Int, coverBlocks: Int, guardCount: Int,
                                 lootCount: Int, shadowFraction: Double) -> CBoard {
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

        let startCell = open.min { manhattan($0, P(r: 1, c: 1)) < manhattan($1, P(r: 1, c: 1)) } ?? P(r: 1, c: 1)
        let corner = P(r: rows - 2, c: cols - 2)
        let exitCell = open.filter { $0 != startCell }.min { manhattan($0, corner) < manhattan($1, corner) } ?? corner
        let doorCorner = P(r: rows - 2, c: 1)
        let doorCell = open.filter { $0 != startCell && $0 != exitCell }
            .min { manhattan($0, doorCorner) < manhattan($1, doorCorner) } ?? P(r: rows - 2, c: 1)

        var starts: [P] = []
        for cand in open.shuffled() where manhattan(cand, startCell) >= 5 && cand != exitCell {
            if starts.allSatisfy({ manhattan($0, cand) >= 4 }) {
                starts.append(cand)
                if starts.count == guardCount { break }
            }
        }
        while starts.count < guardCount, let any = open.randomElement() { starts.append(any) }

        var gs: [Guard] = []
        for s in starts {
            var path = [s, neighbours(s).first ?? s]
            for goal in open.shuffled() where goal != s {
                let p = bfsPath(s, goal)
                if p.count >= 5 { path = p; break }
            }
            let f = path.count >= 2
                ? atan2(center(path[1]).y - center(path[0]).y, center(path[1]).x - center(path[0]).x)
                : 0
            gs.append(Guard(pos: center(s), path: path, idx: 0, dir: 1, facing: f))
        }

        // Loot: lots of distinct open cells, off the start / exit / door / guard tiles.
        let blocked = Set(starts + [startCell, exitCell, doorCell])
        var lootCells: [P] = []
        for cand in open.shuffled() where !blocked.contains(cand) {
            lootCells.append(cand)
            if lootCells.count == lootCount { break }
        }
        let coins = lootCells.map { Coin(cell: $0) }

        // Shadow tiles.
        let shadowTarget = Int(Double(open.count) * shadowFraction)
        var sh: Set<P> = []
        for cand in open.shuffled() where cand != exitCell { sh.insert(cand); if sh.count >= shadowTarget { break } }
        sh.insert(startCell)

        return CBoard(walls: w, guards: gs, coins: coins, shadows: sh,
                      start: startCell, exit: exitCell, door: doorCell)
    }
}

// MARK: - Night mansion art

private enum CBArt {
    static let night = Color(red: 0.07, green: 0.06, blue: 0.11)
    static let gold = Color(red: 1.0, green: 0.8, blue: 0.24)
    static let exitGreen = Color(red: 0.45, green: 0.95, blue: 0.5)
    static let ink = Color(red: 0.07, green: 0.05, blue: 0.08)
    static let catYellow = Color(red: 1.0, green: 0.83, blue: 0.22)

    static func hash(_ n: Double) -> CGFloat {
        let v: Double = sin(n * 12.9898) * 43758.5453
        return CGFloat(v - floor(v))
    }

    static func disc(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    static func oval(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2))
    }

    /// A stack of three gold coins with a glint.
    static func coins(_ ctx: GraphicsContext, at p: CGPoint, cell: CGFloat) {
        let rx = cell * 0.24, ry = cell * 0.1
        ctx.fill(oval(CGPoint(x: p.x + cell * 0.03, y: p.y + cell * 0.2), rx * 1.1, ry * 1.1), with: .color(.black.opacity(0.4)))
        for (k, dy) in [0.16, 0.05, -0.06].enumerated() {
            let c = CGPoint(x: p.x + CGFloat(k % 2 == 0 ? 0 : 0.03) * cell, y: p.y + CGFloat(dy) * cell)
            ctx.fill(oval(CGPoint(x: c.x, y: c.y + ry * 0.45), rx, ry), with: .color(Color(red: 0.7, green: 0.46, blue: 0.08)))
            ctx.fill(oval(c, rx, ry), with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.6), gold]),
                                                          startPoint: CGPoint(x: c.x, y: c.y - ry), endPoint: CGPoint(x: c.x, y: c.y + ry)))
            ctx.stroke(oval(c, rx * 0.62, ry * 0.62), with: .color(Color(red: 0.8, green: 0.55, blue: 0.1)), lineWidth: 0.7)
        }
        var star = Path()
        let s = CGPoint(x: p.x + cell * 0.2, y: p.y - cell * 0.16)
        for i in 0..<8 {
            let a = Double(i) * .pi / 4
            let r = i % 2 == 0 ? cell * 0.12 : cell * 0.03
            let q = CGPoint(x: s.x + CGFloat(cos(a)) * r, y: s.y + CGFloat(sin(a)) * r)
            if i == 0 { star.move(to: q) } else { star.addLine(to: q) }
        }
        star.closeSubpath()
        ctx.fill(star, with: .color(.white.opacity(0.9)))
    }

    /// A guard dog from above in a navy harness and peaked cap, nose pointing where it faces.
    static func guardDog(_ ctx: GraphicsContext, at p: CGPoint, facing: Double, cell: CGFloat, alerted: Bool) {
        let s = cell * 1.45
        let fur = Color(red: 0.8, green: 0.6, blue: 0.38)
        let ear = Color(red: 0.5, green: 0.32, blue: 0.17)
        let navy = Color(red: 0.14, green: 0.2, blue: 0.45)
        ctx.fill(oval(CGPoint(x: p.x + s * 0.04, y: p.y + s * 0.1), s * 0.38, s * 0.24), with: .color(.black.opacity(0.35)))
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        g.rotate(by: .radians(facing))
        let lw = max(1, s * 0.04)
        var tail = Path()
        tail.move(to: CGPoint(x: -s * 0.28, y: 0))
        tail.addLine(to: CGPoint(x: -s * 0.42, y: -s * 0.05))
        g.stroke(tail, with: .color(ink), style: StrokeStyle(lineWidth: s * 0.08 + lw, lineCap: .round))
        g.stroke(tail, with: .color(fur), style: StrokeStyle(lineWidth: s * 0.08, lineCap: .round))
        let body = oval(CGPoint(x: -s * 0.08, y: 0), s * 0.24, s * 0.18)
        g.fill(body, with: .color(fur))
        g.stroke(body, with: .color(ink), lineWidth: lw)
        // Harness band with the guard's badge.
        var band = g
        band.clip(to: body)
        band.fill(Path(CGRect(x: -s * 0.06, y: -s * 0.2, width: s * 0.09, height: s * 0.4)), with: .color(navy))
        g.fill(disc(CGPoint(x: -s * 0.015, y: 0), s * 0.035), with: .color(gold))
        // Floppy ears either side of the head, then the head, snout and nose.
        for side: CGFloat in [-1, 1] {
            let e = oval(CGPoint(x: s * 0.18, y: side * s * 0.17), s * 0.1, s * 0.065)
            g.fill(e, with: .color(ear))
            g.stroke(e, with: .color(ink), lineWidth: lw * 0.8)
        }
        let head = disc(CGPoint(x: s * 0.22, y: 0), s * 0.17)
        g.fill(head, with: .color(fur.lit(0.12)))
        g.stroke(head, with: .color(ink), lineWidth: lw)
        let snout = oval(CGPoint(x: s * 0.38, y: 0), s * 0.085, s * 0.075)
        g.fill(snout, with: .color(fur.lit(0.4)))
        g.stroke(snout, with: .color(ink), lineWidth: lw * 0.8)
        g.fill(disc(CGPoint(x: s * 0.45, y: 0), s * 0.035), with: .color(ink))
        for side: CGFloat in [-1, 1] {
            g.fill(disc(CGPoint(x: s * 0.3, y: side * s * 0.075), s * 0.025), with: .color(ink))
        }
        // The peaked cap: navy crown, gold badge, black visor toward the nose.
        var visor = Path()
        visor.addArc(center: CGPoint(x: s * 0.17, y: 0), radius: s * 0.1, startAngle: .degrees(-65), endAngle: .degrees(65), clockwise: false)
        g.stroke(visor, with: .color(ink), style: StrokeStyle(lineWidth: s * 0.05, lineCap: .round))
        g.fill(disc(CGPoint(x: s * 0.15, y: 0), s * 0.09), with: .color(navy))
        g.stroke(disc(CGPoint(x: s * 0.15, y: 0), s * 0.09), with: .color(ink), lineWidth: lw * 0.7)
        g.fill(disc(CGPoint(x: s * 0.2, y: 0), s * 0.025), with: .color(gold))
        if alerted {
            let b = CGRect(x: p.x - cell * 0.18, y: p.y - cell * 1.1, width: cell * 0.36, height: cell * 0.42)
            ctx.fill(Path(roundedRect: b.insetBy(dx: -1.5, dy: -1.5), cornerRadius: cell * 0.1), with: .color(ink))
            ctx.fill(Path(roundedRect: b, cornerRadius: cell * 0.08), with: .color(Color(red: 1, green: 0.85, blue: 0.2)))
            ctx.draw(Text("!").font(.system(size: cell * 0.36, weight: .black)).foregroundColor(ink), at: CGPoint(x: b.midX, y: b.midY))
        }
    }

    /// The cat burglar from above: a banana-yellow tabby in a black domino mask with a swag sack
    /// on its back, turned to where it's heading. It dims while hiding in a shadow.
    static func cat(_ ctx: GraphicsContext, at p: CGPoint, facing: Double, cell: CGFloat, hidden: Bool) {
        let s = cell * 1.45
        var g = ctx
        if hidden { g.opacity = 0.62 }
        g.fill(oval(CGPoint(x: p.x + s * 0.04, y: p.y + s * 0.09), s * 0.34, s * 0.22), with: .color(.black.opacity(0.35)))
        g.translateBy(x: p.x, y: p.y)
        g.rotate(by: .radians(facing))
        let lw = max(1, s * 0.04)
        let stripe = Color(red: 0.86, green: 0.5, blue: 0.08)
        var tail = Path()
        tail.move(to: CGPoint(x: -s * 0.2, y: 0))
        tail.addCurve(to: CGPoint(x: -s * 0.36, y: s * 0.2), control1: CGPoint(x: -s * 0.42, y: -s * 0.06), control2: CGPoint(x: -s * 0.46, y: s * 0.12))
        g.stroke(tail, with: .color(ink), style: StrokeStyle(lineWidth: s * 0.085 + lw, lineCap: .round))
        g.stroke(tail, with: .color(catYellow), style: StrokeStyle(lineWidth: s * 0.085, lineCap: .round))
        g.fill(disc(CGPoint(x: -s * 0.36, y: s * 0.2), s * 0.045), with: .color(stripe))
        let body = oval(CGPoint(x: -s * 0.06, y: 0), s * 0.21, s * 0.15)
        g.fill(body, with: .color(catYellow))
        var stripes = Path()
        for x in [-0.17, -0.09] as [CGFloat] {
            stripes.move(to: CGPoint(x: s * x, y: -s * 0.15))
            stripes.addQuadCurve(to: CGPoint(x: s * x, y: s * 0.15), control: CGPoint(x: s * (x - 0.04), y: 0))
        }
        var clipped = g
        clipped.clip(to: body)
        clipped.stroke(stripes, with: .color(stripe), lineWidth: s * 0.03)
        g.stroke(body, with: .color(ink), lineWidth: lw)
        // The swag sack slung over its back.
        let sack = disc(CGPoint(x: -s * 0.03, y: -s * 0.02), s * 0.1)
        g.fill(sack, with: .radialGradient(Gradient(colors: [Color(red: 0.85, green: 0.8, blue: 0.7), Color(red: 0.55, green: 0.5, blue: 0.42)]),
                                           center: CGPoint(x: -s * 0.06, y: -s * 0.05), startRadius: 0, endRadius: s * 0.13))
        g.stroke(sack, with: .color(ink), lineWidth: lw * 0.9)
        // Big head: pointed ears, black mask with white eyes, pink nose, whiskers.
        for side: CGFloat in [-1, 1] {
            var ear = Path()
            ear.move(to: CGPoint(x: s * 0.1, y: side * s * 0.07))
            ear.addLine(to: CGPoint(x: s * 0.1, y: side * s * 0.24))
            ear.addLine(to: CGPoint(x: s * 0.26, y: side * s * 0.14))
            ear.closeSubpath()
            g.fill(ear, with: .color(catYellow))
            g.stroke(ear, with: .color(ink), style: StrokeStyle(lineWidth: lw * 0.9, lineJoin: .round))
        }
        let head = disc(CGPoint(x: s * 0.22, y: 0), s * 0.17)
        g.fill(head, with: .color(catYellow))
        var masked = g
        masked.clip(to: head)
        masked.fill(Path(CGRect(x: s * 0.23, y: -s * 0.2, width: s * 0.08, height: s * 0.4)), with: .color(ink))
        g.stroke(head, with: .color(ink), lineWidth: lw)
        for side: CGFloat in [-1, 1] {
            g.fill(oval(CGPoint(x: s * 0.27, y: side * s * 0.07), s * 0.025, s * 0.035), with: .color(.white))
        }
        g.fill(disc(CGPoint(x: s * 0.37, y: 0), s * 0.028), with: .color(Color(red: 1, green: 0.55, blue: 0.6)))
        var whiskers = Path()
        for side: CGFloat in [-1, 1] {
            whiskers.move(to: CGPoint(x: s * 0.35, y: side * s * 0.05)); whiskers.addLine(to: CGPoint(x: s * 0.44, y: side * s * 0.13))
        }
        g.stroke(whiskers, with: .color(ink.opacity(0.7)), lineWidth: max(0.6, lw * 0.5))
    }
}

/// A little stack of coins for the HUD.
private struct CBCoinIcon: View {
    var body: some View {
        Canvas { ctx, s in CBArt.coins(ctx, at: CGPoint(x: s.width / 2, y: s.height * 0.5), cell: min(s.width, s.height) * 1.1) }
    }
}

/// The mansion at night: parquet floor, soft pools of shadow, plum walls with gold molding,
/// furniture on every block of cover, the exit door and the guards' red door. Redrawn only when
/// the layout, the exit lock or the alarm changes.
private struct CBMansion: View, Equatable {
    let walls: [[Bool]]
    let shadows: Set<Int>
    let exitR: Int, exitC: Int
    let doorR: Int, doorC: Int
    let exitOpen: Bool
    let alarm: Bool
    let cell: CGFloat
    let ox: CGFloat
    let oy: CGFloat

    var body: some View {
        Canvas { ctx, s in
            let rows = walls.count
            guard rows > 0 else { return }
            let cols = walls[0].count
            func rect(_ r: Int, _ c: Int) -> CGRect { CGRect(x: ox + CGFloat(c) * cell, y: oy + CGFloat(r) * cell, width: cell, height: cell) }
            func wall(_ r: Int, _ c: Int) -> Bool { r < 0 || c < 0 || r >= rows || c >= cols || walls[r][c] }
            func shade(_ r: Int, _ c: Int) -> Bool { r >= 0 && c >= 0 && r < rows && c < cols && shadows.contains(r * cols + c) }
            let border: (Int, Int) -> Bool = { r, c in r == 0 || c == 0 || r == rows - 1 || c == cols - 1 }

            // Basket-weave parquet: three planks per tile, alternating direction.
            for r in 0..<rows {
                for c in 0..<cols where !walls[r][c] {
                    let rc = rect(r, c)
                    let vertical = (r + c) % 2 == 0
                    for k in 0..<3 {
                        let t = CBArt.hash(Double(r * 31 + c * 7 + k))
                        let wood = Color(red: 0.5 + 0.07 * Double(t), green: 0.35 + 0.05 * Double(t), blue: 0.22 + 0.03 * Double(t))
                        let plank = vertical
                            ? CGRect(x: rc.minX + CGFloat(k) * cell / 3, y: rc.minY, width: cell / 3, height: cell)
                            : CGRect(x: rc.minX, y: rc.minY + CGFloat(k) * cell / 3, width: cell, height: cell / 3)
                        ctx.fill(Path(plank.insetBy(dx: -0.25, dy: -0.25)), with: .color(wood))
                        ctx.stroke(Path(plank), with: .color(Color(red: 0.22, green: 0.14, blue: 0.08).opacity(0.7)), lineWidth: 0.6)
                    }
                }
            }
            // Moonlight falling across the room from the top left.
            let floorRect = CGRect(x: ox, y: oy, width: CGFloat(cols) * cell, height: CGFloat(rows) * cell)
            ctx.fill(Path(floorRect), with: .linearGradient(Gradient(colors: [Color(red: 0.55, green: 0.65, blue: 1).opacity(0.14), .clear, .black.opacity(0.18)]),
                                                            startPoint: CGPoint(x: floorRect.minX, y: floorRect.minY),
                                                            endPoint: CGPoint(x: floorRect.maxX, y: floorRect.maxY)))
            // Pools of shadow: each shadow tile rounds the corners it doesn't share, so touching
            // tiles melt into one dark pool.
            var pools = Path()
            let rad = cell * 0.38
            for r in 0..<rows {
                for c in 0..<cols where shade(r, c) {
                    let tl = !shade(r - 1, c) && !shade(r, c - 1), tr = !shade(r - 1, c) && !shade(r, c + 1)
                    let bl = !shade(r + 1, c) && !shade(r, c - 1), br = !shade(r + 1, c) && !shade(r, c + 1)
                    pools.addPath(Path(roundedRect: rect(r, c).insetBy(dx: -0.4, dy: -0.4),
                                       cornerRadii: RectangleCornerRadii(topLeading: tl ? rad : 0, bottomLeading: bl ? rad : 0,
                                                                         bottomTrailing: br ? rad : 0, topTrailing: tr ? rad : 0)))
                }
            }
            // A soft, feathered pool of dark, with a faint crisp rim so each tile's edge stays exact.
            var soft = ctx
            soft.addFilter(.blur(radius: cell * 0.12))
            soft.fill(pools, with: .color(Color(red: 0.02, green: 0.03, blue: 0.13).opacity(0.7)))
            ctx.fill(pools, with: .color(Color(red: 0.02, green: 0.03, blue: 0.13).opacity(0.35)))
            ctx.stroke(pools, with: .color(Color(red: 0.35, green: 0.42, blue: 0.85).opacity(0.28)), lineWidth: 1)

            // Walls: plum wallpaper tops with a gold molding where they meet the floor.
            let plum = Color(red: 0.27, green: 0.1, blue: 0.15)
            var molding = Path()
            for r in 0..<rows {
                for c in 0..<cols where walls[r][c] && border(r, c) {
                    let rc = rect(r, c)
                    ctx.fill(Path(rc.insetBy(dx: -0.3, dy: -0.3)), with: .color(plum))
                    ctx.fill(CBArt.disc(CGPoint(x: rc.midX, y: rc.midY), cell * 0.07), with: .color(plum.lit(0.12)))
                    if !wall(r + 1, c) { molding.move(to: CGPoint(x: rc.minX, y: rc.maxY - 1)); molding.addLine(to: CGPoint(x: rc.maxX, y: rc.maxY - 1)) }
                    if !wall(r - 1, c) { molding.move(to: CGPoint(x: rc.minX, y: rc.minY + 1)); molding.addLine(to: CGPoint(x: rc.maxX, y: rc.minY + 1)) }
                    if !wall(r, c + 1) { molding.move(to: CGPoint(x: rc.maxX - 1, y: rc.minY)); molding.addLine(to: CGPoint(x: rc.maxX - 1, y: rc.maxY)) }
                    if !wall(r, c - 1) { molding.move(to: CGPoint(x: rc.minX + 1, y: rc.minY)); molding.addLine(to: CGPoint(x: rc.minX + 1, y: rc.maxY)) }
                }
            }
            ctx.stroke(molding, with: .color(CBArt.gold.opacity(0.75)), lineWidth: max(1, cell * 0.07))

            // Furniture on each block of cover (blocks are rectangles; find each one's extent).
            var seen = Set<Int>()
            for r in 0..<rows {
                for c in 0..<cols where walls[r][c] && !border(r, c) && !seen.contains(r * cols + c) {
                    var stack = [(r, c)]
                    var minR = r, maxR = r, minC = c, maxC = c
                    seen.insert(r * cols + c)
                    while let (cr, cc) = stack.popLast() {
                        minR = min(minR, cr); maxR = max(maxR, cr); minC = min(minC, cc); maxC = max(maxC, cc)
                        for (nr, nc) in [(cr - 1, cc), (cr + 1, cc), (cr, cc - 1), (cr, cc + 1)]
                        where nr >= 0 && nr < rows && nc >= 0 && nc < cols && walls[nr][nc] && !border(nr, nc) && !seen.contains(nr * cols + nc) {
                            seen.insert(nr * cols + nc); stack.append((nr, nc))
                        }
                    }
                    let box = rect(minR, minC).union(rect(maxR, maxC))
                    furniture(ctx, box, w: maxC - minC + 1, h: maxR - minR + 1, seed: Double(minR * 17 + minC))
                }
            }

            exitDoor(ctx, rect(exitR, exitC))
            guardDoor(ctx, rect(doorR, doorC))

            // The alarm bathes the room in red.
            if alarm {
                ctx.fill(Path(CGRect(origin: .zero, size: s)), with: .radialGradient(Gradient(colors: [.clear, Color(red: 1, green: 0.1, blue: 0.1).opacity(0.35)]),
                                                                                  center: CGPoint(x: s.width / 2, y: s.height / 2),
                                                                                  startRadius: min(s.width, s.height) * 0.3, endRadius: max(s.width, s.height) * 0.7))
            }
            ctx.fill(Path(CGRect(origin: .zero, size: s)), with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.3)]),
                                                                              center: CGPoint(x: s.width / 2, y: s.height / 2),
                                                                              startRadius: min(s.width, s.height) * 0.4, endRadius: max(s.width, s.height) * 0.75))
        }
        .allowsHitTesting(false)
    }

    /// Picks a piece by the block's footprint: plants, armchairs and vases for single tiles, sofas
    /// and cabinets for pairs, bookshelves for strips, a piano or a round table for 2×2, and a dining
    /// table, a bed or a billiard table for the big ones.
    private func furniture(_ ctx: GraphicsContext, _ box: CGRect, w: Int, h: Int, seed: Double) {
        let r = box.insetBy(dx: cell * 0.07, dy: cell * 0.07)
        let pick = Int(CBArt.hash(seed) * 97)
        ctx.fill(Path(roundedRect: r.offsetBy(dx: cell * 0.08, dy: cell * 0.12), cornerRadius: cell * 0.14), with: .color(.black.opacity(0.4)))
        let ink = CBArt.ink
        let lw = max(1, cell * 0.05)
        let horizontal = w >= h
        if w == 1 && h == 1 {
            let c = CGPoint(x: r.midX, y: r.midY), m = r.width
            switch pick % 3 {
            case 0:     // potted palm
                ctx.fill(CBArt.disc(c, m * 0.3), with: .color(Color(red: 0.72, green: 0.38, blue: 0.2)))
                ctx.stroke(CBArt.disc(c, m * 0.3), with: .color(ink), lineWidth: lw)
                for k in 0..<6 {
                    var leaf = ctx
                    leaf.translateBy(x: c.x, y: c.y)
                    leaf.rotate(by: .radians(Double(k) * .pi / 3 + 0.3))
                    let l = CBArt.oval(CGPoint(x: m * 0.25, y: 0), m * 0.25, m * 0.09)
                    leaf.fill(l, with: .color(Color(red: 0.2, green: 0.55, blue: 0.3)))
                    leaf.stroke(l, with: .color(Color(red: 0.05, green: 0.25, blue: 0.12)), lineWidth: lw * 0.7)
                }
            case 1:     // armchair
                let seat = Path(roundedRect: r.insetBy(dx: m * 0.08, dy: m * 0.08), cornerRadius: m * 0.2)
                ctx.fill(seat, with: .color(Color(red: 0.55, green: 0.12, blue: 0.18)))
                ctx.stroke(seat, with: .color(ink), lineWidth: lw)
                ctx.fill(Path(roundedRect: CGRect(x: r.minX + m * 0.24, y: r.minY + m * 0.3, width: m * 0.52, height: m * 0.52), cornerRadius: m * 0.14),
                         with: .color(Color(red: 0.72, green: 0.2, blue: 0.26)))
            default:    // a vase on a marble pedestal
                let ped = Path(roundedRect: r.insetBy(dx: m * 0.1, dy: m * 0.1), cornerRadius: m * 0.08)
                ctx.fill(ped, with: .color(Color(red: 0.86, green: 0.84, blue: 0.8)))
                ctx.stroke(ped, with: .color(ink), lineWidth: lw)
                ctx.fill(CBArt.disc(c, m * 0.26), with: .color(Color(red: 0.25, green: 0.4, blue: 0.8)))
                ctx.stroke(CBArt.disc(c, m * 0.26), with: .color(ink), lineWidth: lw * 0.8)
                ctx.fill(CBArt.disc(c, m * 0.1), with: .color(Color(red: 0.08, green: 0.12, blue: 0.3)))
            }
        } else if w * h == 2 && pick % 2 == 0 {
            // A velvet sofa: back along one long side, arms at the ends, two cushions.
            let sofa = Path(roundedRect: r, cornerRadius: cell * 0.18)
            ctx.fill(sofa, with: .color(Color(red: 0.36, green: 0.14, blue: 0.3)))
            ctx.stroke(sofa, with: .color(ink), lineWidth: lw)
            let inner = horizontal ? CGRect(x: r.minX + cell * 0.14, y: r.minY + cell * 0.22, width: r.width - cell * 0.28, height: r.height - cell * 0.26)
                                   : CGRect(x: r.minX + cell * 0.22, y: r.minY + cell * 0.14, width: r.width - cell * 0.26, height: r.height - cell * 0.28)
            for k in 0..<2 {
                let cush = horizontal ? CGRect(x: inner.minX + CGFloat(k) * inner.width / 2, y: inner.minY, width: inner.width / 2, height: inner.height)
                                      : CGRect(x: inner.minX, y: inner.minY + CGFloat(k) * inner.height / 2, width: inner.width, height: inner.height / 2)
                ctx.fill(Path(roundedRect: cush.insetBy(dx: 1, dy: 1), cornerRadius: cell * 0.12), with: .color(Color(red: 0.5, green: 0.22, blue: 0.42)))
                ctx.stroke(Path(roundedRect: cush.insetBy(dx: 1, dy: 1), cornerRadius: cell * 0.12), with: .color(ink.opacity(0.6)), lineWidth: lw * 0.6)
            }
        } else if min(w, h) == 1 {
            // Bookshelf / cabinet: a wooden case full of coloured book tops.
            let caseP = Path(roundedRect: r, cornerRadius: cell * 0.08)
            ctx.fill(caseP, with: .color(Color(red: 0.36, green: 0.22, blue: 0.12)))
            let inside = r.insetBy(dx: cell * 0.1, dy: cell * 0.1)
            let bookColors: [Color] = [Color(red: 0.7, green: 0.15, blue: 0.15), Color(red: 0.15, green: 0.35, blue: 0.6), Color(red: 0.2, green: 0.5, blue: 0.3),
                                       Color(red: 0.8, green: 0.6, blue: 0.2), Color(red: 0.45, green: 0.2, blue: 0.5)]
            let n = Int((horizontal ? inside.width : inside.height) / (cell * 0.16))
            for k in 0..<max(1, n) {
                let t = CGFloat(k) / CGFloat(max(1, n))
                let bk = horizontal ? CGRect(x: inside.minX + t * inside.width, y: inside.minY, width: inside.width / CGFloat(max(1, n)) - 0.8, height: inside.height)
                                    : CGRect(x: inside.minX, y: inside.minY + t * inside.height, width: inside.width, height: inside.height / CGFloat(max(1, n)) - 0.8)
                ctx.fill(Path(bk), with: .color(bookColors[Int(CBArt.hash(seed + Double(k)) * 5) % 5]))
            }
            ctx.stroke(caseP, with: .color(ink), lineWidth: lw)
        } else if w == 2 && h == 2 {
            let c = CGPoint(x: r.midX, y: r.midY), m = r.width
            if pick % 2 == 0 {
                // A grand piano: glossy black body with a curved tail, keys along the front.
                var piano = Path()
                piano.move(to: CGPoint(x: r.minX, y: r.minY + m * 0.1))
                piano.addLine(to: CGPoint(x: r.maxX, y: r.minY + m * 0.1))
                piano.addLine(to: CGPoint(x: r.maxX, y: r.minY + m * 0.36))
                piano.addQuadCurve(to: CGPoint(x: r.minX + m * 0.62, y: r.minY + m * 0.64), control: CGPoint(x: r.maxX, y: r.minY + m * 0.6))
                piano.addQuadCurve(to: CGPoint(x: r.minX + m * 0.46, y: r.maxY - m * 0.02), control: CGPoint(x: r.minX + m * 0.5, y: r.minY + m * 0.7))
                piano.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - m * 0.18), control: CGPoint(x: r.minX + m * 0.12, y: r.maxY + m * 0.04))
                piano.closeSubpath()
                ctx.fill(piano, with: .linearGradient(Gradient(colors: [Color(white: 0.22), Color(white: 0.05)]), startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.maxX, y: r.maxY)))
                ctx.stroke(piano, with: .color(.black), lineWidth: lw)
                let keys = CGRect(x: r.minX + m * 0.06, y: r.minY, width: m * 0.88, height: m * 0.13)
                ctx.fill(Path(keys), with: .color(.white))
                var black = Path()
                var x = keys.minX + m * 0.05
                while x < keys.maxX - m * 0.03 { black.addRect(CGRect(x: x, y: keys.minY, width: m * 0.025, height: keys.height * 0.6)); x += m * 0.07 }
                ctx.fill(black, with: .color(.black))
                ctx.stroke(Path(keys), with: .color(.black), lineWidth: 0.8)
                ctx.fill(CBArt.oval(CGPoint(x: c.x + m * 0.08, y: c.y), m * 0.18, m * 0.08), with: .color(.white.opacity(0.12)))
            } else {
                // A round table with four chairs and a candle.
                for k in 0..<4 {
                    let a = Double(k) * .pi / 2 + .pi / 4
                    let q = CGPoint(x: c.x + CGFloat(cos(a)) * m * 0.36, y: c.y + CGFloat(sin(a)) * m * 0.36)
                    ctx.fill(Path(roundedRect: CGRect(x: q.x - m * 0.1, y: q.y - m * 0.1, width: m * 0.2, height: m * 0.2), cornerRadius: m * 0.05),
                             with: .color(Color(red: 0.45, green: 0.28, blue: 0.15)))
                    ctx.stroke(Path(roundedRect: CGRect(x: q.x - m * 0.1, y: q.y - m * 0.1, width: m * 0.2, height: m * 0.2), cornerRadius: m * 0.05), with: .color(ink), lineWidth: lw * 0.7)
                }
                ctx.fill(CBArt.disc(c, m * 0.33), with: .color(Color(red: 0.93, green: 0.9, blue: 0.84)))
                ctx.stroke(CBArt.disc(c, m * 0.33), with: .color(ink), lineWidth: lw)
                ctx.fill(CBArt.disc(c, m * 0.05), with: .color(CBArt.gold))
                ctx.fill(CBArt.disc(c, m * 0.16), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.85, blue: 0.4).opacity(0.5), .clear]),
                                                                        center: c, startRadius: 0, endRadius: m * 0.16))
            }
        } else if w >= 3 && h >= 3 || pick % 3 == 0 {
            // A billiard table: wooden rail, green felt, six pockets and a few balls.
            ctx.fill(Path(roundedRect: r, cornerRadius: cell * 0.14), with: .color(Color(red: 0.4, green: 0.22, blue: 0.1)))
            let felt = r.insetBy(dx: cell * 0.16, dy: cell * 0.16)
            ctx.fill(Path(roundedRect: felt, cornerRadius: cell * 0.06), with: .color(Color(red: 0.1, green: 0.48, blue: 0.3)))
            for p in [CGPoint(x: felt.minX, y: felt.minY), CGPoint(x: felt.maxX, y: felt.minY), CGPoint(x: felt.minX, y: felt.maxY),
                      CGPoint(x: felt.maxX, y: felt.maxY), CGPoint(x: horizontal ? felt.midX : felt.minX, y: horizontal ? felt.minY : felt.midY),
                      CGPoint(x: horizontal ? felt.midX : felt.maxX, y: horizontal ? felt.maxY : felt.midY)] {
                ctx.fill(CBArt.disc(p, cell * 0.09), with: .color(.black))
            }
            let balls: [(CGFloat, CGFloat, Color)] = [(0.3, 0.4, .white), (0.6, 0.55, Color(red: 0.9, green: 0.2, blue: 0.2)), (0.66, 0.35, Color(red: 0.95, green: 0.8, blue: 0.2))]
            for b in balls {
                ctx.fill(CBArt.disc(CGPoint(x: felt.minX + felt.width * b.0, y: felt.minY + felt.height * b.1), cell * 0.07), with: .color(b.2))
            }
            ctx.stroke(Path(roundedRect: r, cornerRadius: cell * 0.14), with: .color(ink), lineWidth: lw)
        } else if pick % 2 == 0 {
            // A dining table under a white cloth, plates and candlesticks down the middle.
            let cloth = Path(roundedRect: r.insetBy(dx: cell * 0.1, dy: cell * 0.1), cornerRadius: cell * 0.1)
            ctx.fill(cloth, with: .color(Color(red: 0.93, green: 0.91, blue: 0.86)))
            ctx.stroke(cloth, with: .color(ink), lineWidth: lw)
            let n = max(w, h)
            for k in 0..<n {
                let t = (CGFloat(k) + 0.5) / CGFloat(n)
                for side: CGFloat in [-1, 1] {
                    let p = horizontal ? CGPoint(x: r.minX + t * r.width, y: r.midY + side * r.height * 0.24)
                                       : CGPoint(x: r.midX + side * r.width * 0.24, y: r.minY + t * r.height)
                    ctx.fill(CBArt.disc(p, cell * 0.12), with: .color(.white))
                    ctx.stroke(CBArt.disc(p, cell * 0.12), with: .color(Color(white: 0.6)), lineWidth: 0.8)
                }
                let q = horizontal ? CGPoint(x: r.minX + t * r.width, y: r.midY) : CGPoint(x: r.midX, y: r.minY + t * r.height)
                ctx.fill(CBArt.disc(q, cell * 0.06), with: .color(CBArt.gold))
            }
        } else {
            // A four-poster bed: headboard, two pillows and a quilt.
            let bed = Path(roundedRect: r, cornerRadius: cell * 0.1)
            ctx.fill(bed, with: .color(Color(red: 0.4, green: 0.24, blue: 0.13)))
            let quilt = horizontal ? CGRect(x: r.minX + r.width * 0.3, y: r.minY + cell * 0.08, width: r.width * 0.66, height: r.height - cell * 0.16)
                                   : CGRect(x: r.minX + cell * 0.08, y: r.minY + r.height * 0.3, width: r.width - cell * 0.16, height: r.height * 0.66)
            ctx.fill(Path(roundedRect: quilt, cornerRadius: cell * 0.08), with: .color(Color(red: 0.25, green: 0.35, blue: 0.62)))
            for k in 0..<2 {
                let pw = horizontal ? CGRect(x: r.minX + cell * 0.12, y: r.minY + CGFloat(k) * r.height / 2 + cell * 0.1, width: r.width * 0.16, height: r.height / 2 - cell * 0.2)
                                    : CGRect(x: r.minX + CGFloat(k) * r.width / 2 + cell * 0.1, y: r.minY + cell * 0.12, width: r.width / 2 - cell * 0.2, height: r.height * 0.16)
                ctx.fill(Path(roundedRect: pw, cornerRadius: cell * 0.08), with: .color(.white))
            }
            ctx.stroke(bed, with: .color(ink), lineWidth: lw)
        }
    }

    /// The way out: a locked door with a padlock, then a glowing green open doorway.
    private func exitDoor(_ ctx: GraphicsContext, _ rc: CGRect) {
        let d = rc.insetBy(dx: cell * 0.12, dy: cell * 0.06)
        var arch = Path()
        arch.move(to: CGPoint(x: d.minX, y: d.maxY))
        arch.addLine(to: CGPoint(x: d.minX, y: d.minY + d.width * 0.5))
        arch.addArc(center: CGPoint(x: d.midX, y: d.minY + d.width * 0.5), radius: d.width * 0.5, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        arch.addLine(to: CGPoint(x: d.maxX, y: d.maxY))
        arch.closeSubpath()
        if exitOpen {
            let c = CGPoint(x: rc.midX, y: rc.midY)
            ctx.fill(CBArt.disc(c, cell * 1.3), with: .radialGradient(Gradient(colors: [CBArt.exitGreen.opacity(0.55), .clear]), center: c, startRadius: 0, endRadius: cell * 1.3))
            ctx.fill(arch, with: .linearGradient(Gradient(colors: [Color(red: 0.85, green: 1, blue: 0.85), CBArt.exitGreen]),
                                                 startPoint: CGPoint(x: d.midX, y: d.minY), endPoint: CGPoint(x: d.midX, y: d.maxY)))
            ctx.stroke(arch, with: .color(Color(red: 0.1, green: 0.4, blue: 0.15)), lineWidth: max(1.2, cell * 0.06))
        } else {
            ctx.fill(arch, with: .color(Color(red: 0.36, green: 0.2, blue: 0.1)))
            ctx.stroke(arch, with: .color(CBArt.ink), lineWidth: max(1, cell * 0.05))
            let lock = CGRect(x: d.midX - cell * 0.13, y: d.midY, width: cell * 0.26, height: cell * 0.22)
            var shackle = Path()
            shackle.addArc(center: CGPoint(x: lock.midX, y: lock.minY), radius: cell * 0.08, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            ctx.stroke(shackle, with: .color(Color(white: 0.75)), lineWidth: max(1, cell * 0.05))
            ctx.fill(Path(roundedRect: lock, cornerRadius: cell * 0.04), with: .color(CBArt.gold))
            ctx.fill(CBArt.disc(CGPoint(x: lock.midX, y: lock.midY), cell * 0.03), with: .color(CBArt.ink))
        }
    }

    /// The guards' red steel door with its siren lamp — blazing once the alarm trips.
    private func guardDoor(_ ctx: GraphicsContext, _ rc: CGRect) {
        let c = CGPoint(x: rc.midX, y: rc.midY)
        if alarm {
            ctx.fill(CBArt.disc(c, cell * 1.7), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.15, blue: 0.1).opacity(0.6), .clear]),
                                                                     center: c, startRadius: 0, endRadius: cell * 1.7))
        }
        let d = rc.insetBy(dx: cell * 0.1, dy: cell * 0.08)
        ctx.fill(Path(roundedRect: d, cornerRadius: cell * 0.06), with: .linearGradient(Gradient(colors: [Color(red: 0.8, green: 0.16, blue: 0.14), Color(red: 0.5, green: 0.06, blue: 0.06)]),
                                                                                       startPoint: CGPoint(x: d.minX, y: d.minY), endPoint: CGPoint(x: d.maxX, y: d.maxY)))
        ctx.stroke(Path(roundedRect: d, cornerRadius: cell * 0.06), with: .color(CBArt.ink), lineWidth: max(1, cell * 0.05))
        for p in [CGPoint(x: d.minX + cell * 0.1, y: d.minY + cell * 0.1), CGPoint(x: d.maxX - cell * 0.1, y: d.minY + cell * 0.1),
                  CGPoint(x: d.minX + cell * 0.1, y: d.maxY - cell * 0.1), CGPoint(x: d.maxX - cell * 0.1, y: d.maxY - cell * 0.1)] {
            ctx.fill(CBArt.disc(p, cell * 0.035), with: .color(Color(white: 0.8)))
        }
        let lamp = CGPoint(x: c.x, y: c.y - cell * 0.04)
        ctx.fill(CBArt.disc(lamp, cell * 0.14), with: .color(alarm ? Color(red: 1, green: 0.3, blue: 0.2) : Color(red: 0.35, green: 0.05, blue: 0.05)))
        ctx.fill(CBArt.disc(CGPoint(x: lamp.x - cell * 0.04, y: lamp.y - cell * 0.04), cell * 0.04), with: .color(.white.opacity(alarm ? 0.9 : 0.35)))
        ctx.stroke(CBArt.disc(lamp, cell * 0.14), with: .color(CBArt.ink), lineWidth: 1)
    }
}
