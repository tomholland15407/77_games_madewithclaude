//
//  DecoyGame.swift
//  A Banana Game
//
//  Brain / stealth — a Metal Gear "knock on the wall" distraction. You must cross a guarded room
//  to the exit, but the guards sweep bright vision cones — walk into one and you're caught. Tap
//  anywhere to LOB a noise decoy: the nearest guard breaks off its patrol to investigate the
//  sound, opening a lane. It looks around, then heads back — so time your throws and slip through
//  the gap. Decoys are limited and a per-level clock is ticking.
//
//  7 levels: more guards, wider and longer cones, faster patrols, fewer decoys, less time.
//
//  Drawn as Metal Gear Solid's Soliton radar: a phosphor grid on dark green glass, walls with bright
//  green edges, guards as red blips with their vision cones (pale cyan on patrol, amber with MGS's
//  "?" while they check a noise, same geometry as `spots`), sound rings where a decoy lands, the exit
//  as a pulsing objective marker, the banana as a yellow blip, and the "!" over whoever spots you.
//  The map is an Equatable view; everything that moves is one Canvas.
//

import SwiftUI

enum DecoyGame {
    static let definition = GameDefinition(
        id: "decoy",
        title: "Decoy",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        locksFeed: false,
        manual: GameManual(
            bullets: [
                "Steer with the d-pad to reach the exit.",
                "Guards sweep vision cones — get caught in one and you're back to level 1.",
                "Tap anywhere to throw a noise decoy: the nearest guard leaves its route to investigate.",
                "It looks around, then returns; decoys are limited, so beat the clock.",
            ],
            bulletsVI: [
                "Điều khiển bằng d-pad để đến lối ra.",
                "Lính gác quét tầm nhìn — bị bắt trong một tầm nhìn là bạn về cấp 1.",
                "Chạm bất kỳ đâu để ném mồi nhử tiếng động: lính gần nhất rời tuyến đi kiểm tra.",
                "Nó nhìn quanh rồi quay lại; mồi nhử có hạn, nên hãy chạy đua với đồng hồ.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(DecoyView(level: level, onWin: onWin, onFail: onFail))
        },
        prefetch: { level in DecoyView(level: level, onWin: {}, onFail: {}).prefetchBoard() }
    )
}

struct DecoyView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void
    @Environment(\.isDemo) private var isDemo

    private let cols = 13
    private let rows = 17

    // MARK: Difficulty
    private var guardCount: Int      { [3, 4, 5, 6, 7, 8, 10][min(level, 7) - 1] }
    private var patrolSpeed: Double  { [1.3, 1.5, 1.7, 1.9, 2.1, 2.4, 2.7][min(level, 7) - 1] }
    private var visionRange: Double  { [3.4, 3.8, 4.2, 4.6, 5.0, 5.4, 5.8][min(level, 7) - 1] }
    private var visionHalfDeg: Double { [24, 28, 32, 36, 40, 44, 48][min(level, 7) - 1] }
    private var decoyBudget: Int     { [5, 4, 4, 3, 2, 2, 1][min(level, 7) - 1] }
    private var investigateHold: Double { [2.6, 2.4, 2.2, 2.0, 1.8, 1.6, 1.4][min(level, 7) - 1] }
    private var coverBlocks: Int     { 4 + level }
    private var timeLimit: Double    { Double(34 - level) }

    private let playerSpeed: Double = 3.7
    private var visionHalf: Double { visionHalfDeg * .pi / 180.0 }

    private struct P: Hashable { let r: Int; let c: Int }
    private enum GState { case patrol, investigate }
    private struct Guard: Identifiable {
        let id = UUID()
        var pos: CGPoint
        var path: [P]
        var idx: Int
        var dir: Int
        var facing: Double
        var state: GState = .patrol
        var lure: CGPoint = .zero
        var hold: Double = 0
    }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var walls: [[Bool]] = []
    @State private var guards: [Guard] = []
    @State private var player = CGPoint(x: 1.5, y: 1.5)
    @State private var exitCell = P(r: 1, c: 1)
    @State private var moveDir = CGVector.zero
    @State private var decoys = 0
    @State private var timeLeft = 0.0
    @State private var built = false
    @State private var pulse: CGFloat = 0
    @State private var t: Double = 0
    @State private var ready = false
    @State private var demoTap: CGPoint? = nil     // demo: decoy tap point (grid units)
    @State private var demoTapID = 0               // demo: bumps per throw → a fresh DemoTapRipple
    @State private var caught = false              // presentation: spotted (a guard gets MGS's "!")

    var body: some View {
        Group {
            if ready { gameBody }
            else { BrainstormingView(skyTop: Color(white: 0.10), skyBottom: Color(white: 0.03)) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { isDemo ? await runDemo() : await run() }
    }

    private var gameBody: some View {
        VStack(spacing: isDemo ? 4 : 8) {
            header
            if !isDemo { timeBar.frame(height: 5).padding(.horizontal, 50) }
            // 4 pt (not 12) inside the 8 pt card inset keeps the radar exactly its old size.
            board.padding(.horizontal, isDemo ? 12 : 4)
            dpad
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DCArt.bezel)
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        // Spotted (not the clock, not the exit): the guard that saw you gets Metal Gear's "!".
        .onChange(of: phase) { _, ph in
            let atExit = hypot(player.x - (Double(exitCell.c) + 0.5), player.y - (Double(exitCell.r) + 0.5)) < 0.5
            caught = ph == .done && timeLeft > 0 && !atExit
        }
    }

    /// Decoys left: a noise icon and the count.
    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: isDemo ? 14 : 18, weight: .bold))
            Text("\(decoys)")
                .font(.system(size: isDemo ? 16 : 20, weight: .black, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(decoys == 0 ? DCArt.alert : DCArt.caution)
        .frame(maxWidth: .infinity, alignment: .trailing)
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
                // The radar map (grid and walls) never changes during a level: drawn once.
                DCRadarMap(size: geo.size, rows: rows, cols: cols, walls: walls).equatable()

                // Exit, cones, noise rings, guard and player blips: one Canvas.
                entitiesCanvas(cell: cell, ox: ox, oy: oy)

                // Demo: the decoy tap — a ripple under a finger where the noise lands.
                if let tp = demoTap {
                    DemoTapRipple().id(demoTapID)
                        .position(x: px(Double(tp.x)), y: py(Double(tp.y)))
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: cell * 1.3))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 3)
                        .position(x: px(Double(tp.x)) + cell * 0.55, y: py(Double(tp.y)) + cell * 0.75)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { loc in
                guard phase == .play, decoys > 0 else { return }
                let tx = Double((loc.x - ox) / cell)
                let ty = Double((loc.y - oy) / cell)
                throwDecoy(to: CGPoint(x: tx, y: ty))
            }
        }
    }

    /// Everything dynamic in a single Canvas (glows are translucent discs, not shadows): the exit
    /// objective, vision cones (same geometry as `spots`), noise rings, guards and the banana blip.
    private func entitiesCanvas(cell: CGFloat, ox: CGFloat, oy: CGFloat) -> some View {
        Canvas { ctx, _ in
            let px: (Double) -> CGFloat = { ox + CGFloat($0) * cell }
            let py: (Double) -> CGFloat = { oy + CGFloat($0) * cell }

            DCArt.exit(ctx, at: CGPoint(x: px(Double(exitCell.c) + 0.5), y: py(Double(exitCell.r) + 0.5)), cell: cell, pulse: pulse)

            let R: CGFloat = CGFloat(visionRange) * cell
            for g in guards {
                let origin = CGPoint(x: px(g.pos.x), y: py(g.pos.y))
                let col = g.state == .investigate ? DCArt.caution : DCArt.sight
                var cone = Path()
                cone.move(to: origin)
                cone.addArc(center: origin, radius: R,
                            startAngle: .radians(g.facing - visionHalf),
                            endAngle: .radians(g.facing + visionHalf), clockwise: false)
                cone.closeSubpath()
                ctx.fill(cone, with: .radialGradient(Gradient(colors: [col.opacity(0.34), col.opacity(0.12)]), center: origin, startRadius: 0, endRadius: R))
                ctx.stroke(cone, with: .color(col.opacity(0.85)), lineWidth: 1.5)
            }

            for g in guards where g.state == .investigate {
                DCArt.noise(ctx, at: CGPoint(x: px(g.lure.x), y: py(g.lure.y)), cell: cell, pulse: pulse)
            }

            for g in guards {
                let c = CGPoint(x: px(g.pos.x), y: py(g.pos.y))
                DCArt.guardBlip(ctx, at: c, cell: cell, facing: g.facing)
                if g.state == .investigate { DCArt.mark("?", ctx, above: c, cell: cell, color: DCArt.caution) }
            }
            if caught {
                for g in guards where spots(g, target: player) {
                    DCArt.mark("!", ctx, above: CGPoint(x: px(g.pos.x), y: py(g.pos.y)), cell: cell, color: DCArt.alert)
                }
            }

            DCArt.player(ctx, at: CGPoint(x: px(player.x), y: py(player.y)), cell: cell)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var dpad: some View {
        if isDemo {
            // The squat demo card can't spare a 3-row cross: same four buttons, one row.
            HStack(spacing: 6) {
                dpadButton(-1, 0, "chevron.left")
                dpadButton(0, -1, "chevron.up")
                dpadButton(0, 1, "chevron.down")
                dpadButton(1, 0, "chevron.right")
            }
            .padding(.bottom, 6)
        } else {
            VStack(spacing: 6) {
                dpadButton(0, -1, "chevron.up")
                HStack(spacing: 6) {
                    dpadButton(-1, 0, "chevron.left")
                    dpadButton(1, 0, "chevron.right")
                }
                dpadButton(0, 1, "chevron.down")
            }
            .padding(.bottom, 6)
        }
    }

    private func dpadButton(_ dx: Double, _ dy: Double, _ icon: String) -> some View {
        // In the demo the held arrow lights up (the script drives moveDir directly).
        let lit = isDemo && moveDir.dx == dx && moveDir.dy == dy
        return Image(systemName: icon)
            .font(.system(size: isDemo ? 16 : 22, weight: .black))
            .foregroundStyle(lit ? Color(red: 0.02, green: 0.12, blue: 0.05) : DCArt.phosphor)
            .frame(width: isDemo ? 56 : 74, height: isDemo ? 30 : 52)
            .background(DCKey(lit: lit, radius: isDemo ? 9 : 14))
            .contentShape(RoundedRectangle(cornerRadius: isDemo ? 9 : 14))
            .scaleEffect(lit ? 0.92 : 1)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if phase == .play { moveDir = CGVector(dx: dx, dy: dy) } }
                    .onEnded { _ in if moveDir.dx == dx && moveDir.dy == dy { moveDir = .zero } }
            )
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac: Double = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(DCArt.phosphor.opacity(0.15))
                Capsule().fill(frac < 0.3 ? DCArt.alert : DCArt.phosphor)
                    .frame(width: geo.size.width * max(0, frac))
            }
        }
    }

    // MARK: - Flow

    /// Hands this level's board build to `BoardCache` so it can run during the countdown.
    func prefetchBoard() {
        let (c, r, cb, gc) = (cols, rows, coverBlocks, guardCount)
        BoardCache.prefetch(boardKey) { Self.generate(cols: c, rows: r, coverBlocks: cb, guardCount: gc) }
    }
    private var boardKey: String { BoardCache.key("decoy", level: level) }

    private func run() async {
        if !built {
            // Claim the board prefetched during the countdown (or build it now, off-main). If the
            // "brainstorming" page did show, it stays up a minimum beat so it never flickers.
            let (c, r, cb, gc) = (cols, rows, coverBlocks, guardCount)
            let t0 = Date()
            let board = await BoardCache.take(boardKey) { Self.generate(cols: c, rows: r, coverBlocks: cb, guardCount: gc) }
            await BoardCache.holdBrainstorm(since: t0, minimum: 1.0)
            guard !Task.isCancelled else { return }
            walls = board.walls
            guards = board.guards
            exitCell = board.exit
            player = CGPoint(x: Double(board.start.c) + 0.5, y: Double(board.start.r) + 0.5)
            decoys = decoyBudget
            moveDir = .zero
            timeLeft = timeLimit
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
    // A fixed level-1 room (13×17, five cover blocks, three guards, 5 decoys) stepped at a fixed
    // 1/60s through the real `step`/`throwDecoy`. The banana heads right along the top corridor and
    // down the right-hand one to the exit; guard A patrols row 9 straight across that corridor and,
    // left alone, turns to face you just as you pass — caught (checked). So at 4.3s, still on the
    // move, the demo taps a decoy west of A: it breaks off, marches to the noise with its back to
    // you, and you slip by. Verified offline on a port of `step` with every cone widened by 0.8
    // cells / 10°: never seen, exit at 6.85s; any throw from 3.9s to 4.7s works (4.3 = middle).
    // Guards B and C patrol the lower-left, out of play but part of the room.
    private static let demoBlocks: [(r: Int, c: Int, h: Int, w: Int)] =
        [(3, 3, 2, 3), (6, 8, 2, 1), (11, 5, 2, 2), (12, 9, 1, 1), (7, 2, 3, 1)]
    private static let demoPaths: [[P]] = [
        (7...11).reversed().map { P(r: 9, c: $0) },        // A: row 9, east → west
        (1...5).map { P(r: 14, c: $0) },                   // B: row 14
        (11...15).reversed().map { P(r: $0, c: 1) }        // C: column 1, bottom → up
    ]
    private static let demoThrowFrame = 258                // 4.3s
    private static let demoLure = CGPoint(x: 4.5, y: 9.5)

    private func demoSetup() {
        var w = Array(repeating: Array(repeating: false, count: cols), count: rows)
        for r in 0..<rows { w[r][0] = true; w[r][cols - 1] = true }
        for c in 0..<cols { w[0][c] = true; w[rows - 1][c] = true }
        for b in Self.demoBlocks {
            for r in b.r..<(b.r + b.h) { for c in b.c..<(b.c + b.w) { w[r][c] = true } }
        }
        walls = w
        guards = Self.demoPaths.map { path in
            let f = atan2(center(path[1]).y - center(path[0]).y, center(path[1]).x - center(path[0]).x)
            return Guard(pos: center(path[0]), path: path, idx: 0, dir: 1, facing: f)
        }
        exitCell = P(r: rows - 2, c: cols - 2)
        player = CGPoint(x: 1.5, y: 1.5)
        decoys = decoyBudget
        moveDir = .zero
        timeLeft = timeLimit
        t = 0; pulse = 0
        demoTap = nil
        built = true; ready = true; phase = .play
    }

    private func runDemo() async {
        let dt = 1.0 / 60.0
        while !Task.isCancelled {
            demoSetup()
            var frame = 0, down = false
            while !Task.isCancelled && phase == .play && frame < 900 {
                frame += 1
                if frame <= 30 {
                    moveDir = .zero
                } else if !down {
                    moveDir = CGVector(dx: 1, dy: 0)                 // ► along the top corridor…
                    if player.x >= 11.5 { player.x = 11.5; down = true }
                }
                if down { moveDir = CGVector(dx: 0, dy: 1) }         // …then ▼ to the exit
                if frame == Self.demoThrowFrame {
                    demoTap = Self.demoLure; demoTapID += 1
                    throwDecoy(to: Self.demoLure)
                }
                if frame == Self.demoThrowFrame + 45 { demoTap = nil }
                step(dt: dt)
                try? await Task.sleep(for: .seconds(0.016))
            }
            // Reached the exit → the real win() ran (onWin is a no-op). Hold, then loop.
            moveDir = .zero; demoTap = nil
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    private func step(dt: Double) {
        guard phase == .play else { return }

        // Drive the investigate-ring pulse from loop time (no implicit repeatForever animation,
        // which stutters the feed when this page scrolls into view).
        t += dt
        pulse = CGFloat(0.25 + 0.25 * sin(t * 4))

        let vx = moveDir.dx * playerSpeed * dt
        let vy = moveDir.dy * playerSpeed * dt
        if canStand(player.x + vx, player.y) { player.x += vx }
        if canStand(player.x, player.y + vy) { player.y += vy }

        for i in guards.indices {
            switch guards[i].state {
            case .patrol: patrol(&guards[i], dt: dt)
            case .investigate: investigate(&guards[i], dt: dt)
            }
        }

        for g in guards where spots(g, target: player) { fail(); return }

        let d = hypot(player.x - (Double(exitCell.c) + 0.5), player.y - (Double(exitCell.r) + 0.5))
        if d < 0.5 { win(); return }

        timeLeft -= dt
        if timeLeft <= 0 { timeLeft = 0; fail() }
    }

    private func throwDecoy(to raw: CGPoint) {
        // Clamp into the arena and only lure a guard already on patrol.
        let clamped = CGPoint(x: min(Double(cols) - 1.5, max(1.5, raw.x)),
                              y: min(Double(rows) - 1.5, max(1.5, raw.y)))
        guard let idx = guards.enumerated()
            .filter({ $0.element.state == .patrol })
            .min(by: { hypot($0.element.pos.x - clamped.x, $0.element.pos.y - clamped.y)
                     < hypot($1.element.pos.x - clamped.x, $1.element.pos.y - clamped.y) })?.offset
        else { SoundManager.shared.error(); return }
        guards[idx].state = .investigate
        guards[idx].lure = clamped
        guards[idx].hold = 0
        decoys -= 1
        SoundManager.shared.tap(); Haptics.tap()
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

    private func investigate(_ g: inout Guard, dt: Double) {
        let dx = g.lure.x - g.pos.x, dy = g.lure.y - g.pos.y
        let d = hypot(dx, dy)
        let sd = patrolSpeed * 1.15 * dt
        if d > 0.35 {
            let nx = dx / d * sd, ny = dy / d * sd
            if canStand(g.pos.x + nx, g.pos.y) { g.pos.x += nx }
            if canStand(g.pos.x, g.pos.y + ny) { g.pos.y += ny }
            g.facing = atan2(dy, dx)
        } else {
            // Arrived — look around, then resume patrol.
            g.hold += dt
            g.facing += dt * 2.2
            if g.hold >= investigateHold { g.state = .patrol }
        }
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
    private static func center(_ p: P) -> CGPoint { CGPoint(x: Double(p.c) + 0.5, y: Double(p.r) + 0.5) }
    private static func manhattan(_ a: P, _ b: P) -> Int { abs(a.r - b.r) + abs(a.c - b.c) }

    // MARK: - Generation (pure/static → runs off the main actor via run())

    private struct DBoard { var walls: [[Bool]]; var guards: [Guard]; var start: P; var exit: P }

    private static func generate(cols: Int, rows: Int, coverBlocks: Int, guardCount: Int) -> DBoard {
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

        // Guards patrol the middle band, between the player and the exit.
        var starts: [P] = []
        for cand in open.shuffled() where manhattan(cand, startCell) >= 4 && cand != exitCell {
            if starts.allSatisfy({ manhattan($0, cand) >= 3 }) {
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

        return DBoard(walls: w, guards: gs, start: startCell, exit: exitCell)
    }

}

// MARK: - Soliton-radar art (after Metal Gear Solid)

private enum DCArt {
    static let phosphor = Color(red: 0.42, green: 1, blue: 0.56)
    static let sight = Color(red: 0.62, green: 0.95, blue: 1)
    static let caution = Color(red: 1, green: 0.8, blue: 0.28)
    static let alert = Color(red: 1, green: 0.3, blue: 0.28)
    static let bezel = LinearGradient(colors: [Color(red: 0.1, green: 0.12, blue: 0.11), Color(red: 0.03, green: 0.05, blue: 0.04)],
                                      startPoint: .top, endPoint: .bottom)

    /// The exit as a pulsing objective marker.
    static func exit(_ ctx: GraphicsContext, at c: CGPoint, cell: CGFloat, pulse: CGFloat) {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - cell * 0.95, y: c.y - cell * 0.95, width: cell * 1.9, height: cell * 1.9)),
                 with: .radialGradient(Gradient(colors: [phosphor.opacity(0.35), phosphor.opacity(0)]), center: c, startRadius: 0, endRadius: cell * 0.95))
        let box = CGRect(x: c.x - cell * 0.36, y: c.y - cell * 0.36, width: cell * 0.72, height: cell * 0.72)
        ctx.fill(Path(box), with: .color(phosphor.opacity(0.35)))
        ctx.stroke(Path(box), with: .color(phosphor), lineWidth: 2)
        let d = cell * (0.5 + pulse * 0.5), k = cell * 0.2
        var brackets = Path()
        for (sx, sy) in [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)] as [(CGFloat, CGFloat)] {
            let corner = CGPoint(x: c.x + sx * d, y: c.y + sy * d)
            brackets.move(to: CGPoint(x: corner.x - sx * k, y: corner.y)); brackets.addLine(to: corner); brackets.addLine(to: CGPoint(x: corner.x, y: corner.y - sy * k))
        }
        ctx.stroke(brackets, with: .color(phosphor), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    /// Sound rings where a decoy landed.
    static func noise(_ ctx: GraphicsContext, at c: CGPoint, cell: CGFloat, pulse: CGFloat) {
        for (i, base) in [0.35, 0.8, 1.25].enumerated() {
            let r = cell * (CGFloat(base) + pulse * 0.9)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                       with: .color(caution.opacity(0.8 - Double(i) * 0.24)), lineWidth: 2)
        }
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - cell * 0.12, y: c.y - cell * 0.12, width: cell * 0.24, height: cell * 0.24)), with: .color(caution))
    }

    /// A guard: a red blip with a halo and a tick for where it faces.
    static func guardBlip(_ ctx: GraphicsContext, at c: CGPoint, cell: CGFloat, facing: Double) {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - cell * 0.5, y: c.y - cell * 0.5, width: cell, height: cell)),
                 with: .radialGradient(Gradient(colors: [alert.opacity(0.45), alert.opacity(0)]), center: c, startRadius: 0, endRadius: cell * 0.5))
        let r = cell * 0.28
        let dot = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.fill(dot, with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.6, blue: 0.55), alert, Color(red: 0.6, green: 0.08, blue: 0.08)]),
                                            center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.3), startRadius: 0, endRadius: r * 1.3))
        ctx.stroke(dot, with: .color(.black.opacity(0.6)), lineWidth: 1.5)
        var tick = Path()
        tick.move(to: CGPoint(x: c.x + CGFloat(cos(facing)) * r * 0.4, y: c.y + CGFloat(sin(facing)) * r * 0.4))
        tick.addLine(to: CGPoint(x: c.x + CGFloat(cos(facing)) * cell * 0.62, y: c.y + CGFloat(sin(facing)) * cell * 0.62))
        ctx.stroke(tick, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: max(1.5, cell * 0.08), lineCap: .round))
    }

    /// Metal Gear's "?" (heard something) or "!" (spotted you) over a guard.
    static func mark(_ glyph: String, _ ctx: GraphicsContext, above c: CGPoint, cell: CGFloat, color: Color) {
        let font = Font.system(size: max(12, cell * 0.8), weight: .black, design: .rounded)
        let p = CGPoint(x: c.x, y: c.y - cell * 0.78)
        let outline = ctx.resolve(Text(glyph).font(font).foregroundColor(.black))
        for (dx, dy) in [(-1.5, 0.0), (1.5, 0.0), (0.0, -1.5), (0.0, 1.5)] as [(CGFloat, CGFloat)] {
            ctx.draw(outline, at: CGPoint(x: p.x + dx, y: p.y + dy))
        }
        ctx.draw(ctx.resolve(Text(glyph).font(font).foregroundColor(color)), at: p)
    }

    /// The banana on the radar: a tilted yellow banana in a white player ring, with a soft glow so it
    /// pops like the guards' blips do.
    static func player(_ ctx: GraphicsContext, at c: CGPoint, cell: CGFloat) {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - cell * 0.7, y: c.y - cell * 0.7, width: cell * 1.4, height: cell * 1.4)),
                 with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.9, blue: 0.3).opacity(0.4), Color(red: 1, green: 0.9, blue: 0.3).opacity(0)]),
                                       center: c, startRadius: 0, endRadius: cell * 0.7))
        let ring = cell * 0.46
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - ring, y: c.y - ring, width: ring * 2, height: ring * 2)), with: .color(.black.opacity(0.45)))
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - ring, y: c.y - ring, width: ring * 2, height: ring * 2)), with: .color(.white.opacity(0.9)), lineWidth: 1.5)
        var g = ctx
        g.translateBy(x: c.x, y: c.y + cell * 0.05)
        g.rotate(by: .degrees(-28))
        g.scaleBy(x: cell * 0.9, y: cell * 0.9)
        var banana = Path()
        banana.move(to: CGPoint(x: -0.44, y: -0.08))
        banana.addQuadCurve(to: CGPoint(x: 0.44, y: -0.1), control: CGPoint(x: 0, y: 0.62))
        banana.addQuadCurve(to: CGPoint(x: -0.44, y: -0.08), control: CGPoint(x: 0, y: 0.1))
        banana.closeSubpath()
        g.fill(banana, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.96, blue: 0.55), Color(red: 0.98, green: 0.76, blue: 0.14)]),
                                             startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: 0.3)))
        g.stroke(banana, with: .color(Color(red: 0.2, green: 0.14, blue: 0.02)), lineWidth: 0.06)
        g.fill(Path(ellipseIn: CGRect(x: -0.48, y: -0.12, width: 0.08, height: 0.08)), with: .color(Color(red: 0.3, green: 0.2, blue: 0.05)))
        g.fill(Path(roundedRect: CGRect(x: 0.4, y: -0.2, width: 0.12, height: 0.12), cornerRadius: 0.03), with: .color(Color(red: 0.42, green: 0.27, blue: 0.08)))
    }
}

/// The radar map: phosphor grid on dark green glass, walls as filled blocks with bright green edges,
/// bracket corners and faint scanlines. Drawn once per level.
private struct DCRadarMap: View, Equatable {
    let size: CGSize
    let rows: Int
    let cols: Int
    let walls: [[Bool]]

    var body: some View {
        Canvas { ctx, _ in
            guard walls.count == rows, rows > 0, cols > 0 else { return }
            let cell = min(size.width / CGFloat(cols), size.height / CGFloat(rows))
            let ox = (size.width - cell * CGFloat(cols)) / 2
            let oy = (size.height - cell * CGFloat(rows)) / 2
            let map = CGRect(x: ox, y: oy, width: cell * CGFloat(cols), height: cell * CGFloat(rows))
            ctx.fill(Path(map), with: .radialGradient(Gradient(colors: [Color(red: 0.03, green: 0.17, blue: 0.1), Color(red: 0.01, green: 0.07, blue: 0.04)]),
                                                      center: CGPoint(x: map.midX, y: map.midY), startRadius: 0, endRadius: max(map.width, map.height) * 0.7))
            var grid = Path(), major = Path()
            for c in 0...cols {
                let x = ox + CGFloat(c) * cell
                var line = Path()
                line.move(to: CGPoint(x: x, y: map.minY)); line.addLine(to: CGPoint(x: x, y: map.maxY))
                if c % 4 == 0 { major.addPath(line) } else { grid.addPath(line) }
            }
            for r in 0...rows {
                let y = oy + CGFloat(r) * cell
                var line = Path()
                line.move(to: CGPoint(x: map.minX, y: y)); line.addLine(to: CGPoint(x: map.maxX, y: y))
                if r % 4 == 0 { major.addPath(line) } else { grid.addPath(line) }
            }
            ctx.stroke(grid, with: .color(DCArt.phosphor.opacity(0.07)), lineWidth: 1)
            ctx.stroke(major, with: .color(DCArt.phosphor.opacity(0.14)), lineWidth: 1)
            func wall(_ r: Int, _ c: Int) -> Bool { r < 0 || r >= rows || c < 0 || c >= cols || walls[r][c] }
            var blocks = Path(), edges = Path()
            for r in 0..<rows {
                for c in 0..<cols where walls[r][c] {
                    let x0 = ox + CGFloat(c) * cell, y0 = oy + CGFloat(r) * cell
                    blocks.addRect(CGRect(x: x0, y: y0, width: cell + 0.5, height: cell + 0.5))
                    if !wall(r - 1, c) { edges.move(to: CGPoint(x: x0, y: y0)); edges.addLine(to: CGPoint(x: x0 + cell, y: y0)) }
                    if !wall(r + 1, c) { edges.move(to: CGPoint(x: x0, y: y0 + cell)); edges.addLine(to: CGPoint(x: x0 + cell, y: y0 + cell)) }
                    if !wall(r, c - 1) { edges.move(to: CGPoint(x: x0, y: y0)); edges.addLine(to: CGPoint(x: x0, y: y0 + cell)) }
                    if !wall(r, c + 1) { edges.move(to: CGPoint(x: x0 + cell, y: y0)); edges.addLine(to: CGPoint(x: x0 + cell, y: y0 + cell)) }
                }
            }
            ctx.fill(blocks, with: .color(Color(red: 0.05, green: 0.25, blue: 0.13)))
            var hatch = ctx
            hatch.clip(to: blocks)
            var diag = Path()
            var d: CGFloat = -map.height
            while d < map.width {
                diag.move(to: CGPoint(x: map.minX + d, y: map.maxY)); diag.addLine(to: CGPoint(x: map.minX + d + map.height, y: map.minY))
                d += 7
            }
            hatch.stroke(diag, with: .color(DCArt.phosphor.opacity(0.1)), lineWidth: 1)
            ctx.stroke(edges, with: .color(DCArt.phosphor.opacity(0.35)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            ctx.stroke(edges, with: .color(DCArt.phosphor), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            var scan = Path()
            var y = map.minY
            while y < map.maxY {
                scan.move(to: CGPoint(x: map.minX, y: y)); scan.addLine(to: CGPoint(x: map.maxX, y: y))
                y += 3
            }
            ctx.stroke(scan, with: .color(.black.opacity(0.14)), lineWidth: 1)
            let k = cell * 0.9
            var corners = Path()
            for (x, y, sx, sy) in [(map.minX, map.minY, 1.0, 1.0), (map.maxX, map.minY, -1.0, 1.0), (map.maxX, map.maxY, -1.0, -1.0), (map.minX, map.maxY, 1.0, -1.0)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
                corners.move(to: CGPoint(x: x + sx * 3, y: y + sy * (3 + k))); corners.addLine(to: CGPoint(x: x + sx * 3, y: y + sy * 3)); corners.addLine(to: CGPoint(x: x + sx * (3 + k), y: y + sy * 3))
            }
            ctx.stroke(corners, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}

/// Military d-pad keys; phosphor green while pressed.
private struct DCKey: View {
    let lit: Bool
    let radius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius)
                .fill(LinearGradient(colors: lit ? [DCArt.phosphor, Color(red: 0.2, green: 0.7, blue: 0.35)]
                                                 : [Color(red: 0.17, green: 0.21, blue: 0.18), Color(red: 0.08, green: 0.1, blue: 0.09)],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: radius).strokeBorder(DCArt.phosphor.opacity(lit ? 0.9 : 0.3), lineWidth: 1.5)
        }
    }
}
