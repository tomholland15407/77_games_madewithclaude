//
//  RicochetShotGame.swift
//  A Banana Game
//
//  Brain — a billiards-style bank shot. You have a fixed cannon and a handful of bullets. Tap the
//  arena to aim; a dotted preview traces where the shot will ricochet off the walls. Tap FIRE to
//  launch — the bullet banks around the room, popping every red target it grazes. Clear all
//  targets before you run out of bullets (or time) and you win; otherwise it's back to level 1.
//
//  7 levels: more targets, more interior walls to bank around, and shorter shots (5 bounces down to
//  2). Every board is verified so the bullets clear it, but only just: at most one to spare, none at
//  levels 6–7.
//
//  Drawn as a red-rock canyon plinking range: a sandy floor with wind ripples, sandstone walls that
//  cast shadows, tin cans for targets (a popped can is knocked flying), and a six-shooter with a
//  banana grip whose cylinder shows the rounds left. The sight line is the same `simulate` polyline,
//  dotted; the bullet leaves a tracer and sparks off the rock at every bounce. Midday at level 1,
//  moonlight by level 7. The arena is an Equatable view, so the 60 Hz loop only redraws the action.
//

import SwiftUI

enum RicochetShotGame {
    static let definition = GameDefinition(
        id: "ricochet-shot",
        title: "Canyon Plink",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        locksFeed: false,
        manual: GameManual(
            bullets: [
                "You have FEWER bullets than targets, so each shot must pop several.",
                "Tap the arena to aim; the dotted line previews how the bullet banks off the walls.",
                "Line it up to sweep through as many targets as possible, then tap FIRE.",
                "Clear them all before your bullets or the clock run out.",
            ],
            bulletsVI: [
                "Bạn có ÍT đạn hơn số mục tiêu, nên mỗi phát phải hạ nhiều mục tiêu.",
                "Chạm vào sân để nhắm; đường chấm cho xem viên đạn nảy khỏi tường ra sao.",
                "Canh sao cho quét qua càng nhiều mục tiêu càng tốt, rồi chạm BẮN.",
                "Dọn sạch tất cả trước khi hết đạn hoặc hết giờ.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(RicochetShotView(level: level, onWin: onWin, onFail: onFail))
        },
        prefetch: { level in RicochetShotView(level: level, onWin: {}, onFail: {}).prefetchBoard() }
    )
}

struct RicochetShotView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void
    @Environment(\.isDemo) private var isDemo

    private let cols = 11
    private let rows = 15

    // MARK: Difficulty
    private var targetCount: Int { [7, 9, 11, 13, 15, 17, 20][min(level, 7) - 1] }
    private var maxBounces: Int   { [5, 5, 4, 4, 3, 3, 2][min(level, 7) - 1] }
    private var interiorWalls: Int { [0, 1, 2, 3, 4, 5, 6][min(level, 7) - 1] }
    private var timeLimit: Double { Double(30 + targetCount * 5) }
    /// Far fewer bullets than dots — every board is verified so bank shots can still clear it.
    private var bulletBudget: Int { [3, 3, 4, 4, 5, 5, 6][min(level, 7) - 1] }
    /// …and needs nearly all of them: the verified cover may leave at most this many to spare.
    private var spareShots: Int { [1, 1, 1, 1, 1, 0, 0][min(level, 7) - 1] }

    private let bulletSpeed: Double = 13.0

    private struct P: Hashable { let r: Int; let c: Int }
    private struct Target: Identifiable { let id = UUID(); let cell: P }

    private enum Phase { case aim, firing, done }
    @State private var phase: Phase = .aim
    @State private var walls: [[Bool]] = []
    @State private var targets: [Target] = []
    @State private var shooter = CGPoint(x: 5.5, y: 13.5)
    @State private var aimAngle: Double = -(.pi / 2)
    @State private var bullet = CGPoint.zero
    @State private var bulletVel = CGVector.zero
    @State private var bulletTravel: Double = 0
    @State private var bouncesLeft = 0
    @State private var ammo = 0
    @State private var timeLeft = 0.0
    @State private var built = false
    @State private var ready = false
    @State private var demoFinger: CGPoint? = nil  // demo: aim tap point (grid units)
    @State private var demoTapID = 0               // demo: bumps per aim tap → a fresh DemoTapRipple
    @State private var demoFirePress = false       // demo: FIRE being pressed

    // Presentation only: the bullet's recent path, ricochet sparks and cans knocked flying.
    @State private var trail: [CGPoint] = []
    @State private var sparks: [RSFx] = []
    @State private var knocked: [RSFx] = []
    @State private var fxSerial = 0

    var body: some View {
        Group {
            if ready { gameBody }
            else { BrainstormingView(skyTop: Color(white: 0.11), skyBottom: Color(white: 0.04)) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { isDemo ? await runDemo() : await run() }
    }

    private var gameBody: some View {
        VStack(spacing: isDemo ? 5 : 8) {
            header
            if !isDemo { timeBar.frame(height: 5).padding(.horizontal, 50) }
            // 4 pt (not 12) inside the 8 pt card inset keeps the arena exactly its old size.
            board.padding(.horizontal, isDemo ? 12 : 4)
            fireButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RSBackdrop(level: level, horizon: isDemo ? 26 : 40).equatable())
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        // Presentation read off the logic's own state: a spark at every bounce, a short trail
        // behind the bullet, and each popped can knocked flying.
        .onChange(of: bouncesLeft) { old, new in
            guard new < old else { return }
            sparks.append(RSFx(p: bullet, at: Date(), seed: (new + 16) % 7)); fxSerial += 1
        }
        .onChange(of: bullet) { _, p in
            guard phase == .firing else { return }
            trail.append(p)
            if trail.count > 12 { trail.removeFirst(trail.count - 12) }
        }
        .onChange(of: phase) { _, ph in if ph != .firing { trail = [] } }
        .onChange(of: targets.map(\.cell)) { old, new in
            let now = Date()
            for c in old where !new.contains(c) {
                knocked.append(RSFx(p: CGPoint(x: Double(c.c) + 0.5, y: Double(c.r) + 0.5), at: now, seed: c.r * 11 + c.c))
            }
            fxSerial += 1
        }
        .task(id: fxSerial) {
            try? await Task.sleep(for: .seconds(0.9))
            guard !Task.isCancelled else { return }
            let now = Date()
            sparks.removeAll { now.timeIntervalSince($0.at) > 0.8 }
            knocked.removeAll { now.timeIntervalSince($0.at) > 0.8 }
        }
    }

    /// Cans left (a can and its count) and the cartridges left in the belt.
    private var header: some View {
        HStack {
            HStack(spacing: 7) {
                RSCanIcon().frame(width: isDemo ? 13 : 16, height: isDemo ? 17 : 21)
                Text("\(targets.count)")
                    .font(.system(size: isDemo ? 16 : 20, weight: .black, design: .rounded))
                    .foregroundStyle(RSArt.cream)
                    .monospacedDigit()
            }
            Spacer()
            RSBelt(total: bulletBudget, loaded: ammo)
                .frame(width: CGFloat(bulletBudget) * (isDemo ? 9 : 11), height: isDemo ? 17 : 21)
        }
        .padding(.horizontal, 22)
        .padding(.top, isDemo ? 6 : 0)
    }

    private var board: some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width
            let h: CGFloat = geo.size.height
            let cell: CGFloat = min(w / CGFloat(cols), h / CGFloat(rows))
            let ox: CGFloat = (w - cell * CGFloat(cols)) / 2
            let oy: CGFloat = (h - cell * CGFloat(rows)) / 2
            let px: (Double) -> CGFloat = { x in ox + CGFloat(x) * cell }
            let py: (Double) -> CGFloat = { y in oy + CGFloat(y) * cell }

            ZStack {
                // The canyon floor and rock walls never change during a level: drawn once.
                RSArena(size: geo.size, rows: rows, cols: cols, walls: walls, level: level).equatable()

                // Aim dots, cans, the bullet, sparks and the six-shooter: one Canvas.
                TimelineView(.animation(paused: sparks.isEmpty && knocked.isEmpty)) { tl in
                    Canvas { ctx, _ in
                        drawAction(ctx, cell: cell, ox: ox, oy: oy, now: max(tl.date, Date()))
                    }
                }
                .allowsHitTesting(false)

                // Demo: the aiming tap — a ripple under a finger at the tapped point.
                if let f = demoFinger {
                    DemoTapRipple().id(demoTapID)
                        .position(x: px(Double(f.x)), y: py(Double(f.y)))
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: cell * 1.3))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 3)
                        .position(x: px(Double(f.x)) + cell * 0.55, y: py(Double(f.y)) + cell * 0.75)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { loc in
                guard phase == .aim else { return }
                let tx = Double((loc.x - ox) / cell)
                let ty = Double((loc.y - oy) / cell)
                let a = atan2(ty - shooter.y, tx - shooter.x)
                aimAngle = a
                SoundManager.shared.tap()
            }
        }
    }

    private func drawAction(_ ctx: GraphicsContext, cell: CGFloat, ox: CGFloat, oy: CGFloat, now: Date) {
        let pt = { (p: CGPoint) in CGPoint(x: ox + p.x * cell, y: oy + p.y * cell) }
        let pal = RSArt.palette(level)

        // The same polyline as before (`simulate`), dotted like a chalked sight line.
        if phase == .aim {
            let pts = simulate(from: shooter, angle: aimAngle, bounces: maxBounces)
            if let first = pts.first {
                var line = Path()
                line.move(to: pt(first))
                for q in pts.dropFirst() { line.addLine(to: pt(q)) }
                ctx.stroke(line, with: .color(pal.sight), style: StrokeStyle(lineWidth: max(2.5, cell * 0.11), lineCap: .round, dash: [0.1, cell * 0.36]))
            }
        }

        for t in targets {
            RSArt.can(ctx, at: pt(CGPoint(x: Double(t.cell.c) + 0.5, y: Double(t.cell.r) + 0.5)), cell: cell,
                      label: RSArt.label(t.cell.r * 7 + t.cell.c * 3))
        }
        for k in knocked {
            let age = now.timeIntervalSince(k.at)
            guard age < 0.8 else { continue }
            let a = CGFloat(age)
            let side: CGFloat = k.seed % 2 == 0 ? 1 : -1
            var g = ctx
            g.opacity = max(0, 1 - Double(age) / 0.8)
            let c = pt(k.p)
            g.translateBy(x: c.x + side * a * cell * 2.2, y: c.y - a * cell * 3.2 + a * a * cell * 6)
            g.rotate(by: .radians(Double(side) * age * 9))
            RSArt.can(g, at: .zero, cell: cell, label: RSArt.label((k.seed / 11) * 7 + (k.seed % 11) * 3))
        }

        if phase == .firing {
            if trail.count > 1 {
                for i in 1..<trail.count {
                    var seg = Path()
                    seg.move(to: pt(trail[i - 1])); seg.addLine(to: pt(trail[i]))
                    let f = Double(i) / Double(trail.count)
                    ctx.stroke(seg, with: .color(pal.tracer.opacity(0.75 * f)), style: StrokeStyle(lineWidth: cell * 0.13 * CGFloat(f), lineCap: .round))
                }
            }
            let b = pt(bullet)
            ctx.fill(Path(ellipseIn: CGRect(x: b.x - cell * 0.42, y: b.y - cell * 0.42, width: cell * 0.84, height: cell * 0.84)),
                     with: .radialGradient(Gradient(colors: [pal.tracer.opacity(0.7), pal.tracer.opacity(0)]), center: b, startRadius: 0, endRadius: cell * 0.42))
            ctx.fill(Path(ellipseIn: CGRect(x: b.x - cell * 0.1, y: b.y - cell * 0.1, width: cell * 0.2, height: cell * 0.2)),
                     with: .color(Color(red: 1, green: 0.96, blue: 0.82)))
        }

        for s in sparks {
            let age = now.timeIntervalSince(s.at)
            guard age < 0.35 else { continue }
            RSArt.spark(ctx, at: pt(s.p), cell: cell, age: age, seed: s.seed)
        }

        RSArt.revolver(ctx, at: pt(shooter), cell: cell, angle: aimAngle, loaded: ammo)
    }

    private var fireButton: some View {
        Button { fire() } label: {
            RSFireFace(ready: phase == .aim || demoFirePress, lit: demoFirePress)
                .frame(width: isDemo ? 130 : 160, height: isDemo ? 40 : 56)
        }
        .buttonStyle(RSPressStyle(lit: demoFirePress))
        .disabled(phase != .aim && !isDemo)
        .padding(.bottom, isDemo ? 6 : 8)
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac: Double = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.32))
                Capsule().fill(frac < 0.3 ? Color(red: 0.96, green: 0.34, blue: 0.22) : RSArt.cream)
                    .frame(width: geo.size.width * max(0, frac))
            }
        }
    }

    // MARK: - Flow

    /// Hands this level's board build to `BoardCache` so it can run during the countdown.
    func prefetchBoard() {
        let sh = CGPoint(x: Double(cols) / 2.0, y: Double(rows) - 1.5)
        let (c, r, iw, tc, bb, sp, mb, bs) = (cols, rows, interiorWalls, targetCount, bulletBudget, spareShots, maxBounces, bulletSpeed)
        BoardCache.prefetch(boardKey) { Self.generate(cols: c, rows: r, interiorWalls: iw, targetCount: tc, bulletBudget: bb, spareShots: sp, maxBounces: mb, bulletSpeed: bs, shooter: sh) }
    }
    private var boardKey: String { BoardCache.key("ricochet-shot", level: level) }

    private func run() async {
        if !built {
            // Generate + set-cover-verify off the main actor so the countdown/scroll never hitch.
            let sh = CGPoint(x: Double(cols) / 2.0, y: Double(rows) - 1.5)
            let (c, r, iw, tc, bb, sp, mb, bs) = (cols, rows, interiorWalls, targetCount, bulletBudget, spareShots, maxBounces, bulletSpeed)
            let t0 = Date()
            let board = await BoardCache.take(boardKey) { Self.generate(cols: c, rows: r, interiorWalls: iw, targetCount: tc, bulletBudget: bb, spareShots: sp, maxBounces: mb, bulletSpeed: bs, shooter: sh) }
            guard !Task.isCancelled else { return }
            await BoardCache.holdBrainstorm(since: t0, minimum: 0.6)
            guard !Task.isCancelled else { return }
            walls = board.walls
            targets = board.targets.map { Target(cell: $0) }
            shooter = sh
            aimAngle = -(.pi / 2)
            ammo = bulletBudget
            timeLeft = timeLimit
            built = true
            ready = true
            phase = .aim
        }
        var last = Date()
        while !Task.isCancelled && phase != .done {
            try? await Task.sleep(for: .seconds(0.016))
            let now = Date()
            let dt = min(0.05, now.timeIntervalSince(last)); last = now
            timeLeft -= dt
            if timeLeft <= 0 { timeLeft = 0; fail(); break }
            if phase == .firing { stepBullet(dt: dt) }
        }
    }

    // MARK: - Demo (live manual clip)
    // A fixed level-1 room (open 11×15, 7 targets, 3 bullets, 5 bounces) whose targets are
    // scattered in the generator's zone (rows 1–10). Two bank shots clear it, found offline with the
    // real `fire`/`stepBullet` at 60 fps: the first pops four (3.3s), the second the last three, the
    // last one the real win() (1.5s), and every pairing within ±0.005 / ±0.008 rad still wins. The
    // demo taps a rough aim first (its preview passes one can), taps again onto the true line and
    // FIREs, then taps the second line and FIREs.
    private static let demoTargets = [P(r: 1, c: 6), P(r: 2, c: 8), P(r: 3, c: 1), P(r: 4, c: 3),
                                      P(r: 6, c: 4), P(r: 8, c: 9), P(r: 10, c: 4)]
    private static let demoAims: [Double] = [-2.8681, -2.8181, -1.9866]   // rough, then the two true lines

    private func runDemo() async {
        let dt = 1.0 / 60.0
        while !Task.isCancelled {
            var w = Array(repeating: Array(repeating: false, count: cols), count: rows)
            for r in 0..<rows { w[r][0] = true; w[r][cols - 1] = true }
            for c in 0..<cols { w[0][c] = true; w[rows - 1][c] = true }
            walls = w
            targets = Self.demoTargets.map { Target(cell: $0) }
            shooter = CGPoint(x: Double(cols) / 2.0, y: Double(rows) - 1.5)
            aimAngle = -(.pi / 2)
            ammo = bulletBudget
            timeLeft = timeLimit
            demoFinger = nil; demoFirePress = false
            built = true; ready = true; phase = .aim
            try? await Task.sleep(for: .seconds(0.8))
            for (k, a) in Self.demoAims.enumerated() {
                guard !Task.isCancelled else { return }
                // Tap a point 4 cells out along the aim line (the real handler aims at the tap).
                demoFinger = CGPoint(x: shooter.x + cos(a) * 4, y: shooter.y + sin(a) * 4)
                demoTapID += 1
                aimAngle = a
                SoundManager.shared.tap()
                try? await Task.sleep(for: .seconds(1.0))
                guard k > 0 else { continue }       // the rough first aim is only looked at
                demoFinger = nil
                demoFirePress = true
                fire()
                try? await Task.sleep(for: .seconds(0.15))
                demoFirePress = false
                while !Task.isCancelled && phase == .firing {
                    stepBullet(dt: dt)
                    try? await Task.sleep(for: .seconds(0.016))
                }
            }
            // Every target popped → the real win() ran (onWin is a no-op). Hold, then loop.
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    private func fire() {
        guard phase == .aim, ammo > 0 else { return }
        ammo -= 1
        bullet = shooter
        bulletVel = CGVector(dx: cos(aimAngle) * bulletSpeed, dy: sin(aimAngle) * bulletSpeed)
        bulletTravel = 0
        bouncesLeft = maxBounces
        phase = .firing
        SoundManager.shared.tap(); Haptics.tap()
    }

    private func stepBullet(dt: Double) {
        // Sub-step for clean reflections at high speed.
        let sub = 6
        let sdt = dt / Double(sub)
        for _ in 0..<sub {
            guard phase == .firing else { return }
            let nx = bullet.x + bulletVel.dx * sdt
            let ny = bullet.y + bulletVel.dy * sdt
            var bounced = false
            if isWall(Int(floor(bullet.y)), Int(floor(nx))) {
                bulletVel.dx = -bulletVel.dx; bounced = true
            }
            if isWall(Int(floor(ny)), Int(floor(bullet.x))) {
                bulletVel.dy = -bulletVel.dy; bounced = true
            }
            if bounced {
                bouncesLeft -= 1
                SoundManager.shared.tap()
                if bouncesLeft < 0 { endShot(); return }
                continue
            }
            bullet.x = nx; bullet.y = ny
            bulletTravel += bulletSpeed * sdt

            // Hit targets.
            if let hit = targets.firstIndex(where: {
                hypot(bullet.x - (Double($0.cell.c) + 0.5), bullet.y - (Double($0.cell.r) + 0.5)) < 0.48
            }) {
                targets.remove(at: hit)
                Haptics.tap(); SoundManager.shared.tap()
                if targets.isEmpty { win(); return }
            }
            if bulletTravel > 90 { endShot(); return }
        }
    }

    private func endShot() {
        guard phase == .firing else { return }
        if targets.isEmpty { win(); return }
        if ammo <= 0 { fail(); return }
        phase = .aim
    }

    private func win() {
        guard phase != .done else { return }
        phase = .done
        Haptics.success(); SoundManager.shared.tap()
        onWin()
    }

    private func fail() {
        guard phase != .done else { return }
        phase = .done
        Haptics.warning(); SoundManager.shared.error()
        onFail()
    }

    // MARK: - Ricochet simulation (shared by preview + verification)

    /// Returns the polyline a shot would trace, reflecting off walls up to `bounces` times.
    private func simulate(from origin: CGPoint, angle: Double, bounces: Int) -> [CGPoint] {
        var pts = [origin]
        var pos = origin
        var vel = CGVector(dx: cos(angle) * bulletSpeed, dy: sin(angle) * bulletSpeed)
        var left = bounces
        let sdt = 0.004
        var travel: Double = 0
        while left >= 0 && travel < 90 {
            let nx = pos.x + vel.dx * sdt
            let ny = pos.y + vel.dy * sdt
            var bounced = false
            if isWall(Int(floor(pos.y)), Int(floor(nx))) { vel.dx = -vel.dx; bounced = true }
            if isWall(Int(floor(ny)), Int(floor(pos.x))) { vel.dy = -vel.dy; bounced = true }
            if bounced {
                pts.append(pos); left -= 1; continue
            }
            pos.x = nx; pos.y = ny
            travel += bulletSpeed * sdt
        }
        pts.append(pos)
        return pts
    }

    private func isWall(_ r: Int, _ c: Int) -> Bool {
        guard r >= 0, r < rows, c >= 0, c < cols, walls.count == rows else { return true }
        return walls[r][c]
    }

    // MARK: - Generation (pure/static → runs off the main actor via run())

    private struct RBoard { var walls: [[Bool]]; var targets: [P] }

    /// A room, then cans dealt until a greedy cover over 360 aims clears them within `bulletBudget`
    /// shots with at most `spareShots` to spare — so the budget is always enough, but only just.
    private static func generate(cols: Int, rows: Int, interiorWalls: Int, targetCount: Int,
                                 bulletBudget: Int, spareShots: Int, maxBounces: Int, bulletSpeed: Double,
                                 shooter: CGPoint) -> RBoard {
        var hardest: (board: RBoard, shots: Int)?     // the most demanding in-budget board, if none hits the band
        var last = RBoard(walls: [], targets: [])
        for _ in 0..<30 {
            var w = Array(repeating: Array(repeating: false, count: cols), count: rows)
            for r in 0..<rows { w[r][0] = true; w[r][cols - 1] = true }
            for c in 0..<cols { w[0][c] = true; w[rows - 1][c] = true }

            // Interior wall blocks (kept off the bottom rows where the cannon sits).
            var placed = 0, tries = 0
            while placed < interiorWalls && tries < 200 {
                tries += 1
                let bw = Int.random(in: 1...2), bh = Int.random(in: 1...3)
                let c0 = Int.random(in: 2...(cols - 2 - bw))
                let r0 = Int.random(in: 2...(rows - 5 - bh))
                var ok = true
                for r in (r0 - 1)...(r0 + bh) where ok {
                    for c in (c0 - 1)...(c0 + bw) where w[r][c] { ok = false }
                }
                guard ok else { continue }
                for r in r0..<(r0 + bh) { for c in c0..<(c0 + bw) { w[r][c] = true } }
                placed += 1
            }

            // A shot's path depends only on the walls: trace the 360 aims once, as the cells each one pops.
            // A can only counts if the shot also pops it 0.3° either side, so a hand-tapped aim works too.
            let aims = (0..<360).map { i in
                let cells = [-0.3, 0, 0.3].map { d in
                    shotCells(angle: (Double(i) + d) / 360 * 2 * .pi, walls: w, rows: rows, cols: cols,
                              shooter: shooter, bulletSpeed: bulletSpeed, maxBounces: maxBounces)
                }
                return cells[0].indices.map { cells[0][$0] && cells[1][$0] && cells[2][$0] }
            }
            for _ in 0..<40 {
                let chosen = placeTargets(in: w, rows: rows, cols: cols, targetCount: targetCount)
                let need = greedyShots(chosen, aims: aims, cols: cols)
                last = RBoard(walls: w, targets: chosen)
                if need <= bulletBudget && need >= bulletBudget - spareShots { return last }
                if need <= bulletBudget && need > (hardest?.shots ?? 0) { hardest = (last, need) }
            }
        }
        return hardest?.board ?? last
    }

    /// Targets on open cells in the upper 2/3, lightly spaced so shots can bank through clusters.
    private static func placeTargets(in w: [[Bool]], rows: Int, cols: Int, targetCount: Int) -> [P] {
        var cells: [P] = []
        for r in 1..<(rows - 4) { for c in 1..<(cols - 1) where !w[r][c] { cells.append(P(r: r, c: c)) } }
        var chosen: [P] = []
        for cand in cells.shuffled() where !chosen.contains(cand) {
            chosen.append(cand)
            if chosen.count == targetCount { break }
        }
        while chosen.count < targetCount, let any = cells.randomElement() {
            if !chosen.contains(any) { chosen.append(any) }
        }
        return chosen
    }

    /// Which cells a shot at `angle` pops a can in: `stepBullet`'s own path at 60 fps (6 sub-steps a
    /// frame, so the bounces land where the bullet's do) and its 0.48 reach around each cell centre.
    private static func shotCells(angle: Double, walls: [[Bool]], rows: Int, cols: Int, shooter: CGPoint,
                                  bulletSpeed: Double, maxBounces: Int) -> [Bool] {
        func wall(_ r: Int, _ c: Int) -> Bool {
            guard r >= 0, r < rows, c >= 0, c < cols, walls.count == rows else { return true }
            return walls[r][c]
        }
        var hit = Array(repeating: false, count: rows * cols)
        // Every cell whose centre lies within the 0.48 reach of one straight run of the path.
        func sweep(_ a: CGPoint, _ b: CGPoint) {
            let dx = b.x - a.x, dy = b.y - a.y, len2 = dx * dx + dy * dy
            for r in max(0, Int(floor(min(a.y, b.y) - 0.48)))...min(rows - 1, Int(floor(max(a.y, b.y) + 0.48))) {
                for c in max(0, Int(floor(min(a.x, b.x) - 0.48)))...min(cols - 1, Int(floor(max(a.x, b.x) + 0.48))) {
                    let px = Double(c) + 0.5 - a.x, py = Double(r) + 0.5 - a.y
                    let t = len2 > 0 ? max(0, min(1, (px * dx + py * dy) / len2)) : 0
                    let ex = px - dx * t, ey = py - dy * t
                    if ex * ex + ey * ey < 0.48 * 0.48 { hit[r * cols + c] = true }
                }
            }
        }
        var pos = shooter, runStart = shooter
        var vel = CGVector(dx: cos(angle) * bulletSpeed, dy: sin(angle) * bulletSpeed)
        var left = maxBounces
        let sdt = 1.0 / 360
        var travel: Double = 0
        while left >= 0 && travel < 90 {
            let nx = pos.x + vel.dx * sdt, ny = pos.y + vel.dy * sdt
            var bounced = false
            if wall(Int(floor(pos.y)), Int(floor(nx))) { vel.dx = -vel.dx; bounced = true }
            if wall(Int(floor(ny)), Int(floor(pos.x))) { vel.dy = -vel.dy; bounced = true }
            if bounced { sweep(runStart, pos); runStart = pos; left -= 1; continue }
            pos.x = nx; pos.y = ny
            travel += bulletSpeed * sdt
        }
        sweep(runStart, pos)
        return hit
    }

    /// Shots a greedy set cover over the traced aims needs to pop every can (Int.max if one can't be hit).
    private static func greedyShots(_ targets: [P], aims: [[Bool]], cols: Int) -> Int {
        let masks = aims.map { hit in
            targets.indices.reduce(0) { hit[targets[$1].r * cols + targets[$1].c] ? $0 | 1 << $1 : $0 }
        }
        var left = (1 << targets.count) - 1, shots = 0
        while left != 0 {
            let best = masks.max { ($0 & left).nonzeroBitCount < ($1 & left).nonzeroBitCount } ?? 0
            if best & left == 0 { return .max }
            left &= ~best
            shots += 1
        }
        return shots
    }
}

// MARK: - Canyon plinking range art

/// A spark / knocked can: where (grid units), when, and a small seed for its look.
private struct RSFx {
    let p: CGPoint
    let at: Date
    let seed: Int
}

private struct RSPalette {
    let sand0: Color, sand1: Color, speck: Color
    let rock: Color, rockDark: Color, rockLit: Color
    let back0: Color, back1: Color
    let sight: Color, tracer: Color
    let shadow: Double
    let sky0: Color, sky1: Color, mesa: Color
}

private enum RSArt {
    static let cream = Color(red: 1, green: 0.93, blue: 0.78)

    static func hash(_ n: Double) -> Double {
        let x = sin(n) * 43758.5453
        return x - floor(x)
    }

    /// Midday → golden hour → sunset → dusk → moonlit canyon, one step per level.
    static func palette(_ level: Int) -> RSPalette {
        let c = { (r: Double, g: Double, b: Double) in Color(red: r, green: g, blue: b) }
        let ink = c(0.34, 0.18, 0.09).opacity(0.72)
        let chalk = Color.white.opacity(0.78)
        switch min(max(level, 1), 7) {
        case 1: return RSPalette(sand0: c(0.95, 0.83, 0.62), sand1: c(0.90, 0.75, 0.52), speck: c(0.72, 0.55, 0.36),
                                 rock: c(0.80, 0.42, 0.25), rockDark: c(0.56, 0.26, 0.14), rockLit: c(0.96, 0.66, 0.46),
                                 back0: c(0.62, 0.30, 0.18), back1: c(0.38, 0.17, 0.10), sight: ink, tracer: c(1, 0.94, 0.72), shadow: 0.2, sky0: c(0.42, 0.70, 0.95), sky1: c(0.80, 0.90, 0.96), mesa: c(0.78, 0.50, 0.38))
        case 2: return RSPalette(sand0: c(0.95, 0.80, 0.57), sand1: c(0.89, 0.71, 0.47), speck: c(0.70, 0.52, 0.32),
                                 rock: c(0.82, 0.44, 0.24), rockDark: c(0.58, 0.27, 0.13), rockLit: c(0.98, 0.67, 0.42),
                                 back0: c(0.66, 0.32, 0.18), back1: c(0.40, 0.18, 0.10), sight: ink, tracer: c(1, 0.94, 0.72), shadow: 0.22, sky0: c(0.40, 0.64, 0.92), sky1: c(0.88, 0.86, 0.78), mesa: c(0.78, 0.47, 0.33))
        case 3: return RSPalette(sand0: c(0.97, 0.76, 0.50), sand1: c(0.90, 0.64, 0.40), speck: c(0.70, 0.46, 0.28),
                                 rock: c(0.84, 0.40, 0.22), rockDark: c(0.58, 0.23, 0.11), rockLit: c(1.0, 0.66, 0.40),
                                 back0: c(0.70, 0.30, 0.16), back1: c(0.42, 0.15, 0.09), sight: ink, tracer: c(1, 0.92, 0.66), shadow: 0.25, sky0: c(0.48, 0.58, 0.86), sky1: c(1.0, 0.80, 0.55), mesa: c(0.74, 0.40, 0.27))
        case 4: return RSPalette(sand0: c(0.93, 0.66, 0.52), sand1: c(0.84, 0.54, 0.44), speck: c(0.62, 0.36, 0.30),
                                 rock: c(0.74, 0.31, 0.26), rockDark: c(0.50, 0.19, 0.18), rockLit: c(0.96, 0.56, 0.46),
                                 back0: c(0.54, 0.21, 0.22), back1: c(0.28, 0.11, 0.17), sight: ink, tracer: c(1, 0.9, 0.7), shadow: 0.26, sky0: c(0.40, 0.34, 0.62), sky1: c(0.98, 0.58, 0.42), mesa: c(0.50, 0.24, 0.27))
        case 5: return RSPalette(sand0: c(0.66, 0.52, 0.56), sand1: c(0.55, 0.42, 0.50), speck: c(0.42, 0.30, 0.38),
                                 rock: c(0.52, 0.28, 0.32), rockDark: c(0.34, 0.17, 0.23), rockLit: c(0.72, 0.46, 0.48),
                                 back0: c(0.30, 0.15, 0.25), back1: c(0.15, 0.07, 0.15), sight: chalk, tracer: c(1, 0.9, 0.74), shadow: 0.28, sky0: c(0.20, 0.17, 0.40), sky1: c(0.62, 0.36, 0.48), mesa: c(0.30, 0.16, 0.25))
        case 6: return RSPalette(sand0: c(0.40, 0.42, 0.56), sand1: c(0.32, 0.34, 0.48), speck: c(0.24, 0.26, 0.38),
                                 rock: c(0.32, 0.27, 0.40), rockDark: c(0.19, 0.16, 0.27), rockLit: c(0.52, 0.48, 0.64),
                                 back0: c(0.13, 0.12, 0.24), back1: c(0.06, 0.06, 0.13), sight: chalk, tracer: c(0.9, 0.95, 1), shadow: 0.3, sky0: c(0.05, 0.07, 0.20), sky1: c(0.16, 0.18, 0.36), mesa: c(0.12, 0.11, 0.21))
        default: return RSPalette(sand0: c(0.31, 0.33, 0.47), sand1: c(0.23, 0.25, 0.38), speck: c(0.17, 0.19, 0.30),
                                  rock: c(0.24, 0.20, 0.31), rockDark: c(0.13, 0.11, 0.20), rockLit: c(0.42, 0.40, 0.56),
                                  back0: c(0.08, 0.08, 0.16), back1: c(0.03, 0.03, 0.08), sight: chalk, tracer: c(0.9, 0.95, 1), shadow: 0.32, sky0: c(0.02, 0.03, 0.10), sky1: c(0.08, 0.09, 0.22), mesa: c(0.07, 0.06, 0.14))
        }
    }

    /// Label colours for the cans (red, blue, green, yellow).
    static func label(_ i: Int) -> Color {
        let all = [Color(red: 0.86, green: 0.18, blue: 0.15), Color(red: 0.18, green: 0.40, blue: 0.84),
                   Color(red: 0.22, green: 0.62, blue: 0.30), Color(red: 0.96, green: 0.76, blue: 0.16)]
        return all[abs(i) % all.count]
    }

    /// The floor, its shadows, and the sandstone walls (strata, sunlit tops, cracks).
    static func arena(_ ctx: GraphicsContext, rows: Int, cols: Int, walls: [[Bool]], cell: CGFloat, ox: CGFloat, oy: CGFloat, level: Int) {
        let pal = palette(level)
        func wall(_ r: Int, _ c: Int) -> Bool { r < 0 || r >= rows || c < 0 || c >= cols || walls[r][c] }
        let field = CGRect(x: ox, y: oy, width: cell * CGFloat(cols), height: cell * CGFloat(rows))

        // Sand, wind ripples, specks and pebbles.
        ctx.fill(Path(field), with: .linearGradient(Gradient(colors: [pal.sand1, pal.sand0, pal.sand1]),
                                                    startPoint: CGPoint(x: field.minX, y: field.minY), endPoint: CGPoint(x: field.maxX, y: field.maxY)))
        var ripples = Path()
        for k in 0..<10 {
            let y0 = field.minY + field.height * (CGFloat(k) + 0.5) / 10
            var x = field.minX
            ripples.move(to: CGPoint(x: x, y: y0))
            var i = 0
            while x < field.maxX {
                let nx = x + cell * 1.7
                let bend: CGFloat = cell * 0.16 * ((i + k) % 2 == 0 ? 1 : -1)
                ripples.addQuadCurve(to: CGPoint(x: nx, y: y0), control: CGPoint(x: x + cell * 0.85, y: y0 - bend))
                x = nx; i += 1
            }
        }
        ctx.stroke(ripples, with: .color(pal.speck.opacity(0.18)), lineWidth: max(1, cell * 0.045))
        var specks = Path(), pebbles = Path()
        for i in 0..<240 {
            let x = field.minX + CGFloat(hash(Double(i) * 12.9898)) * field.width
            let y = field.minY + CGFloat(hash(Double(i) * 78.233)) * field.height
            if i % 12 == 0 {
                let d = cell * (0.1 + 0.08 * CGFloat(hash(Double(i) * 3.3)))
                pebbles.addEllipse(in: CGRect(x: x, y: y, width: d, height: d * 0.72))
            } else {
                let d = cell * (0.035 + 0.04 * CGFloat(hash(Double(i) * 3.7)))
                specks.addEllipse(in: CGRect(x: x, y: y, width: d, height: d * 0.8))
            }
        }
        ctx.fill(specks, with: .color(pal.speck.opacity(0.5)))
        ctx.fill(pebbles, with: .color(pal.rockDark.opacity(0.55)))

        // Shadows the rocks cast on the sand (light from the upper left).
        var shade = Path()
        for r in 0..<rows {
            for c in 0..<cols where !walls[r][c] {
                let x0 = ox + CGFloat(c) * cell, y0 = oy + CGFloat(r) * cell
                if wall(r - 1, c) { shade.addRect(CGRect(x: x0, y: y0, width: cell, height: cell * 0.26)) }
                if wall(r, c - 1) { shade.addRect(CGRect(x: x0, y: y0, width: cell * 0.2, height: cell)) }
            }
        }
        ctx.fill(shade, with: .color(.black.opacity(pal.shadow)))

        // Sandstone mesas: a speckled top face, plus a cliff face with strata drawn INSIDE the wall cell
        // wherever the cell below is open, so the foot of the cliff is exactly the collision edge.
        let faceK: CGFloat = 0.3
        var tops = Path(), faces = Path(), rimLit = Path(), rimDark = Path(), strata = Path()
        var rockSpecks = Path(), rockSpecksLit = Path(), cracks = Path(), edges = Path()
        for r in 0..<rows {
            for c in 0..<cols where walls[r][c] {
                let x0 = ox + CGFloat(c) * cell, y0 = oy + CGFloat(r) * cell
                let hasFace = !wall(r + 1, c)
                let topH = hasFace ? cell * (1 - faceK) : cell
                tops.addRect(CGRect(x: x0, y: y0, width: cell + 0.5, height: topH + 0.5))
                if hasFace {
                    let fy = y0 + topH
                    faces.addRect(CGRect(x: x0, y: fy, width: cell + 0.5, height: cell * faceK))
                    rimLit.addRect(CGRect(x: x0, y: fy - cell * 0.035, width: cell + 0.5, height: cell * 0.05))
                    for k in 1...2 {
                        let sy = fy + cell * faceK * CGFloat(k) / 3 + cell * 0.02 * CGFloat(hash(Double(c * 7 + k)) - 0.5)
                        strata.move(to: CGPoint(x: x0, y: sy)); strata.addLine(to: CGPoint(x: x0 + cell + 0.5, y: sy))
                    }
                    edges.move(to: CGPoint(x: x0, y: y0 + cell)); edges.addLine(to: CGPoint(x: x0 + cell, y: y0 + cell))
                }
                if !wall(r - 1, c) {
                    rimLit.addRect(CGRect(x: x0, y: y0, width: cell + 0.5, height: cell * 0.06))
                    edges.move(to: CGPoint(x: x0, y: y0)); edges.addLine(to: CGPoint(x: x0 + cell, y: y0))
                }
                if !wall(r, c - 1) {
                    rimLit.addRect(CGRect(x: x0, y: y0, width: cell * 0.06, height: topH))
                    edges.move(to: CGPoint(x: x0, y: y0)); edges.addLine(to: CGPoint(x: x0, y: y0 + cell))
                }
                if !wall(r, c + 1) {
                    rimDark.addRect(CGRect(x: x0 + cell * 0.92, y: y0, width: cell * 0.08, height: cell))
                    edges.move(to: CGPoint(x: x0 + cell, y: y0)); edges.addLine(to: CGPoint(x: x0 + cell, y: y0 + cell))
                }
                for i in 0..<7 {
                    let hx = CGFloat(hash(Double(r * 131 + c * 17 + i) * 1.37))
                    let hy = CGFloat(hash(Double(r * 71 + c * 29 + i) * 2.11))
                    let d = cell * (0.05 + 0.07 * CGFloat(hash(Double(i + r * 3 + c) * 4.4)))
                    let rect = CGRect(x: x0 + hx * (cell - d), y: y0 + hy * max(1, topH - d), width: d, height: d * 0.8)
                    if i % 3 == 0 { rockSpecksLit.addEllipse(in: rect) } else { rockSpecks.addEllipse(in: rect) }
                }
                if hash(Double(r * 37 + c * 11) + 0.5) < 0.35 {
                    let sx = x0 + cell * CGFloat(0.2 + 0.45 * hash(Double(r * 5 + c) + 2.1)), sy = y0 + topH * 0.22
                    cracks.move(to: CGPoint(x: sx, y: sy))
                    cracks.addQuadCurve(to: CGPoint(x: sx + cell * 0.2, y: sy + topH * 0.45), control: CGPoint(x: sx + cell * 0.22, y: sy + topH * 0.08))
                }
            }
        }
        ctx.fill(tops, with: .color(pal.rock))
        ctx.fill(rockSpecks, with: .color(pal.rockDark.opacity(0.32)))
        ctx.fill(rockSpecksLit, with: .color(pal.rockLit.opacity(0.42)))
        ctx.stroke(cracks, with: .color(pal.rockDark.opacity(0.7)), style: StrokeStyle(lineWidth: max(0.8, cell * 0.035), lineCap: .round))
        ctx.fill(faces, with: .color(pal.rockDark))
        ctx.stroke(strata, with: .color(pal.rockDark.shade(0.35)), lineWidth: max(1, cell * 0.04))
        ctx.fill(rimLit, with: .color(pal.rockLit.opacity(0.85)))
        ctx.fill(rimDark, with: .color(pal.rockDark.opacity(0.5)))
        ctx.stroke(edges, with: .color(pal.rockDark.shade(0.35)), lineWidth: max(1, cell * 0.04))
    }

    /// A tin can standing on the sand, seen from the front and a little above. The can is centred on
    /// its target cell and fits well inside the 0.48-cell hit radius.
    static func can(_ ctx: GraphicsContext, at c: CGPoint, cell: CGFloat, label: Color) {
        let W = cell * 0.52, H = cell * 0.48, E = cell * 0.18
        let base = c.y + cell * 0.24, top = base - H
        let l = c.x - W / 2, r = c.x + W / 2
        ctx.fill(Path(ellipseIn: CGRect(x: l, y: base - E * 0.3, width: W * 1.3, height: E * 0.95)), with: .color(.black.opacity(0.22)))
        var body = Path()
        body.move(to: CGPoint(x: l, y: top))
        body.addLine(to: CGPoint(x: l, y: base))
        body.addQuadCurve(to: CGPoint(x: r, y: base), control: CGPoint(x: c.x, y: base + E))
        body.addLine(to: CGPoint(x: r, y: top))
        body.closeSubpath()
        let metal = Gradient(stops: [.init(color: Color(white: 0.48), location: 0), .init(color: Color(white: 0.88), location: 0.3),
                                     .init(color: Color(white: 0.98), location: 0.42), .init(color: Color(white: 0.66), location: 0.8),
                                     .init(color: Color(white: 0.44), location: 1)])
        ctx.fill(body, with: .linearGradient(metal, startPoint: CGPoint(x: l, y: 0), endPoint: CGPoint(x: r, y: 0)))
        let lt = top + H * 0.2, lb = base - H * 0.14
        var band = Path()
        band.move(to: CGPoint(x: l, y: lt))
        band.addQuadCurve(to: CGPoint(x: r, y: lt), control: CGPoint(x: c.x, y: lt + E))
        band.addLine(to: CGPoint(x: r, y: lb))
        band.addQuadCurve(to: CGPoint(x: l, y: lb), control: CGPoint(x: c.x, y: lb + E))
        band.closeSubpath()
        ctx.fill(band, with: .linearGradient(Gradient(colors: [label.shade(0.4), label, label.lit(0.3), label.shade(0.45)]),
                                             startPoint: CGPoint(x: l, y: 0), endPoint: CGPoint(x: r, y: 0)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - W * 0.15, y: (lt + lb) / 2 - H * 0.05, width: W * 0.3, height: H * 0.2)), with: .color(.white.opacity(0.85)))
        let lid = CGRect(x: l, y: top - E / 2, width: W, height: E)
        ctx.fill(Path(ellipseIn: lid), with: .color(Color(white: 0.9)))
        ctx.fill(Path(ellipseIn: lid.insetBy(dx: W * 0.09, dy: E * 0.17)), with: .color(Color(white: 0.68)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - W * 0.12, y: top - E * 0.22, width: W * 0.24, height: E * 0.36)), with: .color(Color(white: 0.86)))
        var outline = body
        outline.addEllipse(in: lid)
        ctx.stroke(outline, with: .color(.black.opacity(0.5)), lineWidth: max(0.7, cell * 0.028))
    }

    /// A ricochet: a flash and a star of sparks flying off the rock.
    static func spark(_ ctx: GraphicsContext, at p: CGPoint, cell: CGFloat, age: Double, seed: Int) {
        let t = CGFloat(age / 0.35)
        let fade = max(0, 1 - Double(t))
        let fr = cell * 0.32 * (1 + t)
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - fr, y: p.y - fr, width: fr * 2, height: fr * 2)),
                 with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.7).opacity(0.9 * fade), Color(red: 1, green: 0.8, blue: 0.4).opacity(0)]),
                                       center: p, startRadius: 0, endRadius: fr))
        var rays = Path()
        for k in 0..<7 {
            let a = Double(k) * 0.9 + Double(seed) * 0.7
            let r0 = cell * (0.08 + 0.5 * t), r1 = cell * (0.22 + 0.8 * t)
            rays.move(to: CGPoint(x: p.x + CGFloat(cos(a)) * r0, y: p.y + CGFloat(sin(a)) * r0))
            rays.addLine(to: CGPoint(x: p.x + CGFloat(cos(a)) * r1, y: p.y + CGFloat(sin(a)) * r1))
        }
        ctx.stroke(rays, with: .color(Color(red: 1, green: 0.86, blue: 0.42).opacity(fade)), style: StrokeStyle(lineWidth: max(1, cell * 0.05), lineCap: .round))
    }

    /// The six-shooter seen from above, barrel along the aim, with a banana grip. The cylinder's six
    /// chambers show the rounds left.
    static func revolver(_ ctx: GraphicsContext, at p: CGPoint, cell: CGFloat, angle: Double, loaded: Int) {
        func parts(_ g: GraphicsContext, shadow: Bool) {
            let steel = Color(red: 0.40, green: 0.42, blue: 0.47)
            let dark = Color(red: 0.15, green: 0.16, blue: 0.19)
            let ink = Color.black.opacity(0.7)
            var grip = Path()
            grip.move(to: CGPoint(x: -0.26, y: -0.13))
            grip.addQuadCurve(to: CGPoint(x: -0.9, y: -0.04), control: CGPoint(x: -0.6, y: -0.26))
            grip.addQuadCurve(to: CGPoint(x: -0.88, y: 0.1), control: CGPoint(x: -0.97, y: 0.04))
            grip.addQuadCurve(to: CGPoint(x: -0.26, y: 0.13), control: CGPoint(x: -0.56, y: 0.2))
            grip.closeSubpath()
            let frame = Path(roundedRect: CGRect(x: -0.38, y: -0.15, width: 0.64, height: 0.3), cornerRadius: 0.08)
            let barrel = Path(roundedRect: CGRect(x: 0.16, y: -0.085, width: 0.88, height: 0.17), cornerRadius: 0.05)
            let drum = Path(ellipseIn: CGRect(x: -0.27, y: -0.25, width: 0.5, height: 0.5))
            if shadow {
                for part in [grip, frame, barrel, drum] { g.fill(part, with: .color(.black.opacity(0.28))) }
                return
            }
            g.fill(grip, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.9, blue: 0.4), Color(red: 0.93, green: 0.72, blue: 0.16)]),
                                               startPoint: CGPoint(x: 0, y: -0.2), endPoint: CGPoint(x: 0, y: 0.2)))
            g.fill(Path(ellipseIn: CGRect(x: -0.95, y: -0.05, width: 0.12, height: 0.14)), with: .color(Color(red: 0.42, green: 0.28, blue: 0.1)))
            g.stroke(grip, with: .color(ink), lineWidth: 0.035)
            g.fill(frame, with: .color(dark))
            g.fill(barrel, with: .linearGradient(Gradient(colors: [steel.lit(0.35), steel, steel.shade(0.35)]),
                                                 startPoint: CGPoint(x: 0, y: -0.085), endPoint: CGPoint(x: 0, y: 0.085)))
            g.fill(Path(CGRect(x: 1.0, y: -0.095, width: 0.07, height: 0.19)), with: .color(dark))
            g.fill(Path(CGRect(x: 0.9, y: -0.03, width: 0.08, height: 0.06)), with: .color(dark.opacity(0.8)))
            g.stroke(barrel, with: .color(ink), lineWidth: 0.03)
            g.fill(Path(roundedRect: CGRect(x: -0.46, y: -0.045, width: 0.12, height: 0.09), cornerRadius: 0.03), with: .color(dark))
            g.fill(drum, with: .radialGradient(Gradient(colors: [steel.lit(0.4), steel, steel.shade(0.4)]),
                                               center: CGPoint(x: -0.1, y: -0.1), startRadius: 0, endRadius: 0.32))
            g.stroke(drum, with: .color(ink), lineWidth: 0.03)
            for k in 0..<6 {
                let a = Double(k) / 6 * 2 * .pi - .pi / 2
                let q = CGPoint(x: -0.02 + CGFloat(cos(a)) * 0.155, y: CGFloat(sin(a)) * 0.155)
                let hole = Path(ellipseIn: CGRect(x: q.x - 0.058, y: q.y - 0.058, width: 0.116, height: 0.116))
                if k < loaded {
                    g.fill(hole, with: .color(Color(red: 0.93, green: 0.75, blue: 0.33)))
                    g.fill(Path(ellipseIn: CGRect(x: q.x - 0.022, y: q.y - 0.022, width: 0.044, height: 0.044)), with: .color(Color(red: 0.62, green: 0.44, blue: 0.18)))
                } else {
                    g.fill(hole, with: .color(Color(white: 0.08)))
                }
            }
            g.fill(Path(ellipseIn: CGRect(x: -0.06, y: -0.04, width: 0.08, height: 0.08)), with: .color(steel.lit(0.5)))
        }
        var sh = ctx
        sh.translateBy(x: p.x + cell * 0.07, y: p.y + cell * 0.11)
        sh.rotate(by: .radians(angle))
        sh.scaleBy(x: cell * 1.15, y: cell * 1.15)
        parts(sh, shadow: true)
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        g.rotate(by: .radians(angle))
        g.scaleBy(x: cell * 1.15, y: cell * 1.15)
        parts(g, shadow: false)
    }
}

/// The floor and walls, drawn once per board (the 60 Hz loop never redraws them).
private struct RSArena: View, Equatable {
    let size: CGSize
    let rows: Int
    let cols: Int
    let walls: [[Bool]]
    let level: Int

    var body: some View {
        Canvas { ctx, _ in
            guard walls.count == rows, rows > 0, cols > 0 else { return }
            let cell = min(size.width / CGFloat(cols), size.height / CGFloat(rows))
            let ox = (size.width - cell * CGFloat(cols)) / 2
            let oy = (size.height - cell * CGFloat(rows)) / 2
            RSArt.arena(ctx, rows: rows, cols: cols, walls: walls, cell: cell, ox: ox, oy: oy, level: level)
        }
    }
}

/// Behind the arena: the sky of the hour over distant buttes, then the desert floor.
private struct RSBackdrop: View, Equatable {
    let level: Int
    let horizon: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let pal = RSArt.palette(level)
            let w = size.width, h = size.height
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: horizon + 1)),
                     with: .linearGradient(Gradient(colors: [pal.sky0, pal.sky1]), startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))
            if level >= 6 {
                var stars = Path()
                for i in 0..<34 {
                    let x = CGFloat(RSArt.hash(Double(i) * 9.1)) * w
                    let y = CGFloat(RSArt.hash(Double(i) * 3.3)) * horizon * 0.8
                    let d: CGFloat = 1 + CGFloat(RSArt.hash(Double(i) * 1.9)) * 1.4
                    stars.addEllipse(in: CGRect(x: x, y: y, width: d, height: d))
                }
                ctx.fill(stars, with: .color(.white.opacity(0.75)))
            }
            let disc = CGRect(x: w * 0.5 - 8, y: horizon * 0.22, width: 16, height: 16)
            ctx.fill(Path(ellipseIn: disc), with: .color(level >= 6 ? Color(red: 0.94, green: 0.95, blue: 1) : Color(red: 1, green: 0.96, blue: 0.8).opacity(0.9)))
            var buttes = Path()
            buttes.move(to: CGPoint(x: 0, y: horizon + 1))
            var x: CGFloat = -10
            var i = 0
            while x < w {
                let gap = 14 + 36 * CGFloat(RSArt.hash(Double(i) * 5.3))
                let bw = 34 + 54 * CGFloat(RSArt.hash(Double(i) * 1.7))
                let bh = horizon * (0.22 + 0.3 * CGFloat(RSArt.hash(Double(i) * 2.9)))
                buttes.addLine(to: CGPoint(x: x + gap, y: horizon + 1))
                buttes.addLine(to: CGPoint(x: x + gap + 7, y: horizon - bh))
                buttes.addLine(to: CGPoint(x: x + gap + bw - 7, y: horizon - bh))
                buttes.addLine(to: CGPoint(x: x + gap + bw, y: horizon + 1))
                x += gap + bw
                i += 1
            }
            buttes.addLine(to: CGPoint(x: w, y: horizon + 1))
            buttes.closeSubpath()
            ctx.fill(buttes, with: .color(pal.mesa))
            ctx.fill(Path(CGRect(x: 0, y: horizon, width: w, height: h - horizon)),
                     with: .linearGradient(Gradient(colors: [pal.back0, pal.back1]), startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: h)))
            var pebbles = Path()
            for k in 0..<60 {
                let px = CGFloat(RSArt.hash(Double(k) * 4.7)) * w
                let py = horizon + CGFloat(RSArt.hash(Double(k) * 8.3)) * (h - horizon)
                let d: CGFloat = 2 + 4 * CGFloat(RSArt.hash(Double(k) * 2.2))
                pebbles.addEllipse(in: CGRect(x: px, y: py, width: d, height: d * 0.7))
            }
            ctx.fill(pebbles, with: .color(.black.opacity(0.18)))
        }
    }
}

/// The counter's can.
private struct RSCanIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let cell = size.height / 0.7
            RSArt.can(ctx, at: CGPoint(x: size.width / 2, y: size.height / 2), cell: cell, label: RSArt.label(0))
        }
    }
}

/// Cartridges in a belt: brass ones are left, dark sockets are spent. The last round glows red.
private struct RSBelt: View {
    let total: Int
    let loaded: Int

    var body: some View {
        Canvas { ctx, size in
            let n = max(1, total)
            let slot = size.width / CGFloat(n)
            let w = min(slot * 0.62, size.height * 0.34)
            for i in 0..<n {
                let x = slot * (CGFloat(i) + 0.5)
                let caseRect = CGRect(x: x - w / 2, y: size.height * 0.38, width: w, height: size.height * 0.6)
                var tip = Path()
                tip.move(to: CGPoint(x: x - w / 2, y: size.height * 0.4))
                tip.addQuadCurve(to: CGPoint(x: x + w / 2, y: size.height * 0.4), control: CGPoint(x: x, y: -size.height * 0.08))
                tip.closeSubpath()
                if i < loaded {
                    let warn = loaded <= 1
                    ctx.fill(tip, with: .color(Color(red: 0.78, green: 0.45, blue: 0.24)))
                    ctx.fill(Path(roundedRect: caseRect, cornerRadius: w * 0.2),
                             with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.86, blue: 0.46), Color(red: 0.82, green: 0.6, blue: 0.2)]),
                                                   startPoint: CGPoint(x: caseRect.minX, y: 0), endPoint: CGPoint(x: caseRect.maxX, y: 0)))
                    if warn {
                        var all = Path(roundedRect: caseRect, cornerRadius: w * 0.2)
                        all.addPath(tip)
                        ctx.stroke(all, with: .color(Color(red: 1, green: 0.3, blue: 0.2)), lineWidth: 1.5)
                    }
                } else {
                    var all = Path(roundedRect: caseRect, cornerRadius: w * 0.2)
                    all.addPath(tip)
                    ctx.fill(all, with: .color(.black.opacity(0.3)))
                    ctx.stroke(all, with: .color(.white.opacity(0.25)), lineWidth: 1)
                }
            }
        }
    }
}

/// FIRE: a red button in a brass rim with a crosshair; greyed while a shot is in the air.
private struct RSFireFace: View {
    let ready: Bool
    let lit: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: ready ? [Color(red: 0.88, green: 0.3, blue: 0.2), Color(red: 0.6, green: 0.15, blue: 0.1)]
                                                   : [Color(white: 0.42), Color(white: 0.28)],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 16).strokeBorder(Color(red: 0.96, green: 0.8, blue: 0.42), lineWidth: 3)
            RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(lit ? 0.9 : 0.18), lineWidth: 1.5).padding(5)
            Image(systemName: "scope")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(.white.opacity(ready ? 1 : 0.5))
        }
    }
}

private struct RSPressStyle: ButtonStyle {
    let lit: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed || lit ? 0.92 : 1)
    }
}
