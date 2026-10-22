//
//  MirrorMazeGame.swift
//  A Banana Game
//
//  Brain — a Deflektor-style optics room crossed with stealth. A dense web of deadly laser beams
//  fires from the walls and reflects off tiltable mirrors. Tap a mirror to rotate it 15° and bend
//  the beams out of your lane, then steer your banana with the d-pad to the exit. Touch any beam
//  and it's back to level 1. Every board is generated so a clear route exists — but you start
//  boxed in, so you MUST re-aim mirrors to carve the path.
//
//  7 levels: many more emitters and mirrors, tighter rooms, and less time.
//
//  Drawn after Deflektor's optics lab: steel floor tiles, riveted wall blocks, laser cannons whose
//  lenses face into the room, mirrors as pivot discs carrying a silver bar at the exact angle the
//  beam uses, lasers as a red glow with a white-hot core along the traced polylines, a green
//  teleport pad for the exit and a vector banana. The lab turns violet at 4–5 and alarm-red at
//  6–7. The "REACH THE EXIT" line is gone. The room is an Equatable view; the rest is one Canvas.
//

import SwiftUI

enum MirrorMazeGame {
    static let definition = GameDefinition(
        id: "mirror-maze",
        title: "Mirror Maze",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        locksFeed: false,
        manual: GameManual(
            bullets: [
                "Deadly laser beams fire from the walls and reflect off the mirrors.",
                "Tap a mirror to rotate it 15° and bend the beams away from your path.",
                "You start hemmed in, so re-aim the beams to open a lane.",
                "Steer with the d-pad to the exit; touch a beam and you're back to level 1.",
            ],
            bulletsVI: [
                "Những tia laser chết người bắn ra từ tường và phản chiếu qua các gương.",
                "Chạm một gương để xoay nó 15° và bẻ các tia ra khỏi lối đi của bạn.",
                "Bạn bắt đầu bị vây kín, nên phải chỉnh lại các tia để mở một lối.",
                "Điều khiển bằng d-pad để đến lối ra; chạm một tia là bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(MirrorMazeView(level: level, onWin: onWin, onFail: onFail))
        },
        prefetch: { level in MirrorMazeView(level: level, onWin: {}, onFail: {}).prefetchBoard() }
    )
}

struct MirrorMazeView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void
    @Environment(\.isDemo) private var isDemo

    private let cols = 11
    private let rows = 15
    private let steps = 12                 // 12 orientations, 15° apart

    // MARK: Difficulty
    private var mirrorCount: Int { [3, 4, 5, 6, 7, 8, 9][min(level, 7) - 1] }
    private var sourceCount: Int { [3, 4, 5, 6, 7, 8, 9][min(level, 7) - 1] }
    private var coverBlocks: Int { [0, 1, 1, 2, 2, 3, 3][min(level, 7) - 1] }
    private var timeLimit: Double { [42, 40, 38, 36, 34, 32, 30][min(level, 7) - 1] }

    private let playerSpeed: Double = 3.4

    private struct P: Hashable { let r: Int; let c: Int }
    private struct Source { let cell: P; let dir: CGVector }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var walls: [[Bool]] = []
    @State private var sources: [Source] = []
    @State private var mirrors: [P] = []
    @State private var orient: [P: Int] = [:]       // 15°-step index 0..11
    @State private var beamCells: Set<P> = []
    @State private var beamPolys: [[CGPoint]] = []
    @State private var player = CGPoint(x: 1.5, y: 1.5)
    @State private var startCell = P(r: 1, c: 1)
    @State private var exitCell = P(r: 1, c: 1)
    @State private var moveDir = CGVector.zero
    @State private var timeLeft = 0.0
    @State private var built = false
    @State private var ready = false
    @State private var demoFinger: P? = nil        // demo: mirror being tapped
    @State private var demoTapID = 0               // demo: bumps per tap → a fresh DemoTapRipple

    var body: some View {
        Group {
            if ready { gameBody }
            else { BrainstormingView(skyTop: Color(white: 0.11), skyBottom: Color(white: 0.04)) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { isDemo ? await runDemo() : await run() }
    }

    private var gameBody: some View {
        VStack(spacing: isDemo ? 4 : 8) {
            if !isDemo { timeBar.frame(height: 5).padding(.horizontal, 50).padding(.top, 4) }
            // 4 pt (not 12) inside the 8 pt card inset keeps the room exactly its old width.
            board.padding(.horizontal, isDemo ? 12 : 4)
                .padding(.top, isDemo ? 8 : 0)
            dpad
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MMArt.backdrop(level))
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
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
                // Floor tiles, steel walls and the exit pad never change during a level: drawn once.
                MMRoom(size: geo.size, rows: rows, cols: cols, walls: walls, exit: exitCell.r * cols + exitCell.c, level: level)
                    .equatable()

                // Lasers, mirror discs, the wall cannons and the banana: one Canvas.
                Canvas { ctx, _ in
                    let pt = { (x: Double, y: Double) in CGPoint(x: px(x), y: py(y)) }
                    MMArt.beams(ctx, polys: beamPolys.map { poly in poly.map { pt(Double($0.x), Double($0.y)) } }, cell: cell)
                    for m in mirrors {
                        MMArt.mirror(ctx, at: pt(Double(m.c) + 0.5, Double(m.r) + 0.5), cell: cell, degrees: Double(orient[m] ?? 0) * 15.0)
                    }
                    for s in sources {
                        MMArt.emitter(ctx, at: pt(Double(s.cell.c) + 0.5, Double(s.cell.r) + 0.5), cell: cell, dir: s.dir)
                    }
                    MMArt.banana(ctx, at: pt(player.x, player.y), cell: cell)
                }
                .allowsHitTesting(false)

                // Demo: the mirror tap — a ripple under a finger.
                if let m = demoFinger {
                    DemoTapRipple().id(demoTapID)
                        .position(x: px(Double(m.c) + 0.5), y: py(Double(m.r) + 0.5))
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: cell * 1.3))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 3)
                        .position(x: px(Double(m.c) + 1.05), y: py(Double(m.r) + 1.25))
                        .allowsHitTesting(false)
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { loc in
                guard phase == .play else { return }
                let c = Int(floor(Double((loc.x - ox) / cell)))
                let r = Int(floor(Double((loc.y - oy) / cell)))
                rotateMirror(P(r: r, c: c))
            }
        }
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
            .foregroundStyle(lit ? Color(red: 0.2, green: 0.12, blue: 0) : .white)
            .frame(width: isDemo ? 56 : 74, height: isDemo ? 30 : 52)
            .background(MMKey(lit: lit, radius: isDemo ? 9 : 14))
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
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(frac < 0.3 ? Color(red: 1, green: 0.3, blue: 0.28) : Color(red: 0.55, green: 0.9, blue: 1))
                    .frame(width: geo.size.width * max(0, frac))
            }
        }
    }

    // MARK: - Flow

    /// Hands this level's board build to `BoardCache` so it can run during the countdown.
    func prefetchBoard() {
        let (c, r, st, sc, mc, cb) = (cols, rows, steps, sourceCount, mirrorCount, coverBlocks)
        BoardCache.prefetch(boardKey) { Self.generate(cols: c, rows: r, steps: st, sourceCount: sc, mirrorCount: mc, coverBlocks: cb) }
    }
    private var boardKey: String { BoardCache.key("mirror-maze", level: level) }

    private func run() async {
        if !built {
            // Generate + verify off the main actor so the countdown never hitches. Kick off the
            // solver, THEN hold on a fixed floor: this suspension yields the main actor so the
            // "brainstorming" page (only shown when the board is genuinely still building) never flickers.
            let (c, r, st, sc, mc, cb) = (cols, rows, steps, sourceCount, mirrorCount, coverBlocks)
            let t0 = Date()
            let result = await BoardCache.take(boardKey) { Self.generate(cols: c, rows: r, steps: st, sourceCount: sc, mirrorCount: mc, coverBlocks: cb) }
            await BoardCache.holdBrainstorm(since: t0, minimum: 1.0)
            guard !Task.isCancelled else { return }
            walls = result.walls; sources = result.sources; mirrors = result.mirrors
            orient = result.orient; startCell = result.start; exitCell = result.exit
            updateBeam()
            player = CGPoint(x: Double(startCell.c) + 0.5, y: Double(startCell.r) + 0.5)
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

    /// Tap a mirror: turn it one 15° step and re-trace every beam.
    private func rotateMirror(_ cell: P) {
        guard orient[cell] != nil else { return }
        orient[cell] = ((orient[cell] ?? 0) + 1) % steps
        updateBeam()
        SoundManager.shared.tap(); Haptics.tap()
    }

    // MARK: - Demo (live manual clip)
    // A fixed level-1 room (open 11×15, three wall emitters, three mirrors) found offline with an
    // exact port of `trace`. It starts boxed in: beams rake the left column (rows 5–10) and every
    // route to the exit is cut. One tap on the middle mirror and two on the bottom-left one swing
    // them clear (the start cell stays beam-free after every tap), then ▼ down the left column and
    // ► along the bottom row to the exit — a lane no beam touches.
    //   # # # # # # # E # # #      E emitters: top (0,7) ▼, right (9,10) ◄ and (11,10) ◄
    //   # S . . . . . * . . #      M mirrors (2,6) 15°, (9,7) 15°→30°, (11,2) 30°→60°
    //   # . . . . . M * . . #
    private static let demoSources: [(r: Int, c: Int, dx: Double, dy: Double)] =
        [(9, 10, -1, 0), (11, 10, -1, 0), (0, 7, 0, 1)]
    private static let demoMirrors: [(r: Int, c: Int, o: Int)] = [(9, 7, 1), (2, 6, 1), (11, 2, 2)]
    private static let demoTaps = [P(r: 9, c: 7), P(r: 11, c: 2), P(r: 11, c: 2)]

    private func runDemo() async {
        let dt = 1.0 / 60.0
        while !Task.isCancelled {
            var w = Array(repeating: Array(repeating: false, count: cols), count: rows)
            for r in 0..<rows { w[r][0] = true; w[r][cols - 1] = true }
            for c in 0..<cols { w[0][c] = true; w[rows - 1][c] = true }
            walls = w
            sources = Self.demoSources.map { Source(cell: P(r: $0.r, c: $0.c), dir: CGVector(dx: $0.dx, dy: $0.dy)) }
            mirrors = Self.demoMirrors.map { P(r: $0.r, c: $0.c) }
            orient = Dictionary(uniqueKeysWithValues: Self.demoMirrors.map { (P(r: $0.r, c: $0.c), $0.o) })
            startCell = P(r: 1, c: 1); exitCell = P(r: rows - 2, c: cols - 2)
            updateBeam()
            player = CGPoint(x: 1.5, y: 1.5)
            moveDir = .zero; demoFinger = nil
            timeLeft = timeLimit
            built = true; ready = true; phase = .play
            try? await Task.sleep(for: .seconds(1.0))            // show the boxed-in start
            for m in Self.demoTaps {
                guard !Task.isCancelled else { return }
                demoFinger = m
                try? await Task.sleep(for: .seconds(0.3))
                demoTapID += 1
                rotateMirror(m)
                try? await Task.sleep(for: .seconds(0.45))
            }
            demoFinger = nil
            try? await Task.sleep(for: .seconds(0.3))
            var frame = 0
            while !Task.isCancelled && phase == .play && frame < 900 {
                frame += 1
                if player.y < Double(exitCell.r) + 0.5 {
                    moveDir = CGVector(dx: 0, dy: 1)                   // ▼ down the cleared column
                } else {
                    player.y = Double(exitCell.r) + 0.5
                    moveDir = CGVector(dx: 1, dy: 0)                   // ► along the bottom row
                }
                step(dt: dt)
                try? await Task.sleep(for: .seconds(0.016))
            }
            // Reached the exit → the real win() ran (onWin is a no-op). Hold, then loop.
            moveDir = .zero
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    private func step(dt: Double) {
        guard phase == .play else { return }
        let vx = moveDir.dx * playerSpeed * dt
        let vy = moveDir.dy * playerSpeed * dt
        if canStand(player.x + vx, player.y) { player.x += vx }
        if canStand(player.x, player.y + vy) { player.y += vy }

        let pc = P(r: Int(floor(player.y)), c: Int(floor(player.x)))
        if beamCells.contains(pc) { fail(); return }

        let d = hypot(player.x - (Double(exitCell.c) + 0.5), player.y - (Double(exitCell.r) + 0.5))
        if d < 0.5 { win(); return }

        timeLeft -= dt
        if timeLeft <= 0 { timeLeft = 0; fail() }
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

    // MARK: - Continuous beam optics

    private func updateBeam() {
        let (cells, polys) = Self.trace(config: orient, walls: walls, sources: sources,
                                        rows: rows, cols: cols, steps: steps)
        beamCells = cells
        beamPolys = polys
    }

    /// Fast cell-only beam trace (coarser step, no polylines) used by the off-main generator so it
    /// can afford many layout attempts and never fall back to a trivial (easy) board.
    private static func beamCells(config: [P: Int], walls: [[Bool]], sources: [Source],
                                  rows: Int, cols: Int, steps: Int) -> Set<P> {
        func wall(_ r: Int, _ c: Int) -> Bool {
            guard r >= 0, r < rows, c >= 0, c < cols, walls.count == rows else { return true }
            return walls[r][c]
        }
        var cells: Set<P> = []
        let stepLen: Double = 0.12
        for s in sources {
            let inC = s.cell.c + Int(s.dir.dx), inR = s.cell.r + Int(s.dir.dy)
            var pos = CGPoint(x: Double(inC) + 0.5, y: Double(inR) + 0.5)
            var dir = s.dir
            cells.insert(P(r: inR, c: inC))
            var lastMirror: P? = nil
            var travel: Double = 0
            while travel < 45 {
                let np = CGPoint(x: pos.x + dir.dx * stepLen, y: pos.y + dir.dy * stepLen)
                if wall(Int(floor(np.y)), Int(floor(np.x))) { break }
                pos = np
                travel += stepLen
                cells.insert(P(r: Int(floor(pos.y)), c: Int(floor(pos.x))))
                if let lm = lastMirror,
                   hypot(pos.x - (Double(lm.c) + 0.5), pos.y - (Double(lm.r) + 0.5)) > 0.55 { lastMirror = nil }
                let mcell = P(r: Int(floor(pos.y)), c: Int(floor(pos.x)))
                if let idx = config[mcell], mcell != lastMirror {
                    let cen = CGPoint(x: Double(mcell.c) + 0.5, y: Double(mcell.r) + 0.5)
                    if hypot(pos.x - cen.x, pos.y - cen.y) < 0.3 {
                        let phi = Double(idx) * 15.0 * .pi / 180.0
                        let u = CGVector(dx: cos(phi), dy: sin(phi))
                        let dot = dir.dx * u.dx + dir.dy * u.dy
                        dir = CGVector(dx: 2 * dot * u.dx - dir.dx, dy: 2 * dot * u.dy - dir.dy)
                        lastMirror = mcell
                        pos = CGPoint(x: cen.x + dir.dx * 0.32, y: cen.y + dir.dy * 0.32)
                        travel += 0.32
                    }
                }
            }
        }
        return cells
    }

    /// Ray-trace every source, reflecting off tilted mirrors, until it hits a wall (or a travel
    /// cap breaks a loop). Returns the deadly cells + drawable polylines. Pure/static so the
    /// generator can call it off the main actor.
    private static func trace(config: [P: Int], walls: [[Bool]], sources: [Source],
                              rows: Int, cols: Int, steps: Int) -> (Set<P>, [[CGPoint]]) {
        func wall(_ r: Int, _ c: Int) -> Bool {
            guard r >= 0, r < rows, c >= 0, c < cols, walls.count == rows else { return true }
            return walls[r][c]
        }
        var cells: Set<P> = []
        var polys: [[CGPoint]] = []
        let stepLen: Double = 0.07
        for s in sources {
            // The emitter cell sits on the border wall, so launch the ray from the first interior
            // cell (drawing the line back to the emitter). Starting on the wall cell would trip the
            // wall check immediately and the beam would never appear.
            let inC = s.cell.c + Int(s.dir.dx), inR = s.cell.r + Int(s.dir.dy)
            let emitter = CGPoint(x: Double(s.cell.c) + 0.5, y: Double(s.cell.r) + 0.5)
            var pos = CGPoint(x: Double(inC) + 0.5, y: Double(inR) + 0.5)
            var dir = s.dir
            var poly: [CGPoint] = [emitter, pos]
            cells.insert(P(r: inR, c: inC))
            var lastMirror: P? = nil
            var travel: Double = 0
            while travel < 60 {
                let np = CGPoint(x: pos.x + dir.dx * stepLen, y: pos.y + dir.dy * stepLen)
                if wall(Int(floor(np.y)), Int(floor(np.x))) { poly.append(np); break }
                pos = np
                travel += stepLen
                cells.insert(P(r: Int(floor(pos.y)), c: Int(floor(pos.x))))
                if let lm = lastMirror,
                   hypot(pos.x - (Double(lm.c) + 0.5), pos.y - (Double(lm.r) + 0.5)) > 0.55 { lastMirror = nil }
                let mcell = P(r: Int(floor(pos.y)), c: Int(floor(pos.x)))
                if let stepIdx = config[mcell], mcell != lastMirror {
                    let cen = CGPoint(x: Double(mcell.c) + 0.5, y: Double(mcell.r) + 0.5)
                    if hypot(pos.x - cen.x, pos.y - cen.y) < 0.3 {
                        poly.append(cen)
                        let phi = Double(stepIdx) * 15.0 * .pi / 180.0
                        let u = CGVector(dx: cos(phi), dy: sin(phi))
                        let dot = dir.dx * u.dx + dir.dy * u.dy
                        dir = CGVector(dx: 2 * dot * u.dx - dir.dx, dy: 2 * dot * u.dy - dir.dy)
                        lastMirror = mcell
                        pos = CGPoint(x: cen.x + dir.dx * 0.32, y: cen.y + dir.dy * 0.32)
                        travel += 0.32
                    }
                }
            }
            poly.append(pos)
            polys.append(poly)
        }
        return (cells, polys)
    }

    private func isWall(_ r: Int, _ c: Int) -> Bool {
        guard r >= 0, r < rows, c >= 0, c < cols, walls.count == rows else { return true }
        return walls[r][c]
    }

    private func canStand(_ x: Double, _ y: Double) -> Bool {
        let rad = 0.26
        for cx in [x - rad, x + rad] {
            for cy in [y - rad, y + rad] {
                if isWall(Int(floor(cy)), Int(floor(cx))) { return false }
            }
        }
        return true
    }

    // MARK: - Generation (pure/static → runs off the main actor via run())

    private struct Board {
        var walls: [[Bool]]
        var sources: [Source]
        var mirrors: [P]
        var orient: [P: Int]
        var start: P
        var exit: P
    }

    private static func manhattan(_ a: P, _ b: P) -> Int { abs(a.r - b.r) + abs(a.c - b.c) }

    private static func generate(cols: Int, rows: Int, steps: Int,
                                 sourceCount: Int, mirrorCount: Int, coverBlocks: Int) -> Board {
        // tryBuild now solves each layout with a DIRECTED (greedy) orientation search instead of
        // random sampling, so it lands a hard, solvable, blocked-start board on virtually the first
        // attempt. There is no time cap — if a particular layout can't be solved we just try more
        // layouts, and only if a whole density can't be solved do we shed ONE emitter and retry
        // (staying as hard as possible). The board is NEVER allowed to collapse to an easy one.
        var sc = sourceCount, mc = mirrorCount
        while true {
            for _ in 0..<40 {
                if let b = tryBuild(cols: cols, rows: rows, steps: steps, sourceCount: sc,
                                    mirrorCount: mc, coverBlocks: coverBlocks, relax: false) { return b }
            }
            for _ in 0..<40 {
                if let b = tryBuild(cols: cols, rows: rows, steps: steps, sourceCount: sc,
                                    mirrorCount: mc, coverBlocks: coverBlocks, relax: true) { return b }
            }
            if sc > 2 { sc -= 1 }
            else if mc > 2 { mc -= 1 }
            else { return shieldedFallback(cols: cols, rows: rows, steps: steps,
                                           sourceCount: sc, mirrorCount: mc) }  // mathematically unreachable
        }
    }

    /// A full-count, guaranteed-solvable board used only if every randomized attempt somehow
    /// failed. A wall-enclosed L-corridor (top row across, then the far column down) stays
    /// beam-free no matter how the mirrors are turned, so a route always exists — yet it still
    /// fields the full set of emitters and mirrors, so it never reads as the trivial easy board.
    private static func shieldedFallback(cols: Int, rows: Int, steps: Int,
                                         sourceCount: Int, mirrorCount: Int) -> Board {
        var w = Array(repeating: Array(repeating: false, count: cols), count: rows)
        for r in 0..<rows { w[r][0] = true; w[r][cols - 1] = true }
        for c in 0..<cols { w[0][c] = true; w[rows - 1][c] = true }

        let start = P(r: 1, c: 1)
        let exit = P(r: rows - 2, c: cols - 2)

        // Seal the L-corridor off from the beam field: a wall strip under the top row, and a wall
        // strip left of the exit column. Beams (even reflected ones) can't reach the corridor.
        for c in 1...(cols - 3) { w[2][c] = true }
        for r in 3...(rows - 2) { w[r][cols - 3] = true }

        // Emitters fire into the sealed field only (bottom wall up; overflow on the left wall).
        var srcs: [Source] = []
        var col = 1
        for _ in 0..<sourceCount {
            if col <= cols - 4 {
                srcs.append(Source(cell: P(r: rows - 1, c: col), dir: CGVector(dx: 0, dy: -1)))
                col += 1
            } else {
                let r = Int.random(in: 3...(rows - 2))
                srcs.append(Source(cell: P(r: r, c: 0), dir: CGVector(dx: 1, dy: 0)))
            }
        }

        // Mirrors scattered through the field (never on the corridor).
        var ms: [P] = []
        var open: [P] = []
        for r in 3...(rows - 2) { for c in 1...(cols - 4) where !w[r][c] { open.append(P(r: r, c: c)) } }
        for cand in open.shuffled() {
            if ms.count == mirrorCount { break }
            ms.append(cand)
        }
        var orient: [P: Int] = [:]
        for m in ms { orient[m] = Int.random(in: 0..<steps) }

        return Board(walls: w, sources: srcs, mirrors: ms, orient: orient, start: start, exit: exit)
    }

    private static func tryBuild(cols: Int, rows: Int, steps: Int, sourceCount: Int,
                                 mirrorCount: Int, coverBlocks: Int, relax: Bool) -> Board? {
        var w = Array(repeating: Array(repeating: false, count: cols), count: rows)
        for r in 0..<rows { w[r][0] = true; w[r][cols - 1] = true }
        for c in 0..<cols { w[0][c] = true; w[rows - 1][c] = true }
        var placed = 0, tries = 0
        while placed < coverBlocks && tries < 120 {
            tries += 1
            let c0 = Int.random(in: 2...(cols - 3))
            let r0 = Int.random(in: 3...(rows - 4))
            if w[r0][c0] { continue }
            w[r0][c0] = true; placed += 1
        }

        let start = P(r: 1, c: 1)
        let exit = P(r: rows - 2, c: cols - 2)
        if w[start.r][start.c] || w[exit.r][exit.c] { return nil }

        // Emitters on the border, pointing inward at open cells.
        var srcs: [Source] = []
        var st = 0
        while srcs.count < sourceCount && st < 400 {
            st += 1
            let side = Int.random(in: 0..<4)
            let cell: P; let dir: CGVector
            switch side {
            case 0: cell = P(r: 0, c: Int.random(in: 2...(cols - 3))); dir = CGVector(dx: 0, dy: 1)
            case 1: cell = P(r: rows - 1, c: Int.random(in: 2...(cols - 3))); dir = CGVector(dx: 0, dy: -1)
            case 2: cell = P(r: Int.random(in: 3...(rows - 4)), c: 0); dir = CGVector(dx: 1, dy: 0)
            default: cell = P(r: Int.random(in: 3...(rows - 4)), c: cols - 1); dir = CGVector(dx: -1, dy: 0)
            }
            let inside = P(r: cell.r + Int(dir.dy), c: cell.c + Int(dir.dx))
            if w[inside.r][inside.c] { continue }
            if srcs.contains(where: { manhattan($0.cell, cell) < (relax ? 1 : 2) }) { continue }
            srcs.append(Source(cell: cell, dir: dir))
        }
        if srcs.count < sourceCount { return nil }

        // Mirrors on interior open cells (not start/exit), spaced.
        var ms: [P] = []
        var openCells: [P] = []
        for r in 2..<(rows - 2) { for c in 2..<(cols - 2) where !w[r][c] { openCells.append(P(r: r, c: c)) } }
        for cand in openCells.shuffled() where cand != start && cand != exit {
            if ms.allSatisfy({ manhattan($0, cand) >= (relax ? 1 : 2) }) {
                ms.append(cand)
                if ms.count == mirrorCount { break }
            }
        }
        if ms.count < mirrorCount { return nil }

        // A SOLVED config must exist for the board to be solvable. Find one with a directed greedy
        // search that minimizes danger on the exit and keeps a route open — far more reliable than
        // random sampling (which is what used to fail and drop us into the easy fallback).
        let solved = greedyConfig(mirrors: ms, walls: w, sources: srcs, rows: rows, cols: cols, steps: steps) { cells in
            var s = cells.count
            if cells.contains(exit) { s += 5000 }
            if cells.contains(start) { s += 5000 }
            if !pathExists(start: start, exit: exit, avoiding: cells, walls: w, rows: rows, cols: cols) { s += 5000 }
            return s
        }
        let solvedCells = beamCells(config: solved, walls: w, sources: srcs, rows: rows, cols: cols, steps: steps)
        guard !solvedCells.contains(exit), !solvedCells.contains(start),
              pathExists(start: start, exit: exit, avoiding: solvedCells, walls: w, rows: rows, cols: cols)
        else { return nil }   // this layout is oversaturated — caller tries another

        // The START config should be HARD: player-safe on spawn, but the direct path is closed so
        // the player MUST re-aim mirrors. Greedy-maximize beam coverage while keeping the start safe
        // and the path blocked. If (rarely) no blocked-start exists, fall back to the solved config.
        let blocked = greedyConfig(mirrors: ms, walls: w, sources: srcs, rows: rows, cols: cols, steps: steps) { cells in
            var s = 0
            if cells.contains(start) { s += 5000 }   // never trap the player on spawn
            if pathExists(start: start, exit: exit, avoiding: cells, walls: w, rows: rows, cols: cols) { s += 800 }
            s -= cells.count                          // prefer a busier, more menacing board
            return s
        }
        let blockedCells = beamCells(config: blocked, walls: w, sources: srcs, rows: rows, cols: cols, steps: steps)
        let startConfig = (!blockedCells.contains(start)
                           && !pathExists(start: start, exit: exit, avoiding: blockedCells, walls: w, rows: rows, cols: cols))
                          ? blocked : solved
        return Board(walls: w, sources: srcs, mirrors: ms, orient: startConfig, start: start, exit: exit)
    }

    /// Directed (greedy) orientation search: seeds random orientations, then repeatedly re-picks
    /// each mirror's 15° step to minimize `cost(beamCells)`. Converges to a good config in a couple
    /// of passes — reliable where blind random sampling would miss and force an easy fallback.
    private static func greedyConfig(mirrors: [P], walls: [[Bool]], sources: [Source],
                                     rows: Int, cols: Int, steps: Int,
                                     cost: (Set<P>) -> Int) -> [P: Int] {
        var cfg: [P: Int] = [:]
        for m in mirrors { cfg[m] = Int.random(in: 0..<steps) }
        for _ in 0..<3 {
            for m in mirrors {
                var bestO = cfg[m] ?? 0, bestC = Int.max
                for o in 0..<steps {
                    cfg[m] = o
                    let c = cost(beamCells(config: cfg, walls: walls, sources: sources,
                                           rows: rows, cols: cols, steps: steps))
                    if c < bestC { bestC = c; bestO = o }
                }
                cfg[m] = bestO
            }
        }
        return cfg
    }

    private static func pathExists(start: P, exit: P, avoiding beam: Set<P>,
                                   walls: [[Bool]], rows: Int, cols: Int) -> Bool {
        func wall(_ r: Int, _ c: Int) -> Bool {
            guard r >= 0, r < rows, c >= 0, c < cols, walls.count == rows else { return true }
            return walls[r][c]
        }
        var seen: Set<P> = [start]
        var q = [start]; var head = 0
        while head < q.count {
            let cur = q[head]; head += 1
            if cur == exit { return true }
            let ns = [P(r: cur.r - 1, c: cur.c), P(r: cur.r + 1, c: cur.c),
                      P(r: cur.r, c: cur.c - 1), P(r: cur.r, c: cur.c + 1)]
            for n in ns where !seen.contains(n) && !wall(n.r, n.c) && !beam.contains(n) {
                seen.insert(n); q.append(n)
            }
        }
        return false
    }

}

// MARK: - Optics-lab art (after Deflektor)

private enum MMArt {
    static func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    /// Lab tint per level: cool blue, then violet, then an alarm-red room at 6–7.
    static func tint(_ level: Int) -> Color {
        level >= 6 ? c(0.36, 0.14, 0.16) : level >= 4 ? c(0.26, 0.18, 0.4) : c(0.14, 0.24, 0.38)
    }

    static func backdrop(_ level: Int) -> LinearGradient {
        LinearGradient(colors: [tint(level).mix(with: .black, by: 0.55), tint(level).mix(with: .black, by: 0.82)], startPoint: .top, endPoint: .bottom)
    }

    /// The deadly beams: a red glow and a white-hot core along the traced polylines.
    static func beams(_ ctx: GraphicsContext, polys: [[CGPoint]], cell: CGFloat) {
        var all = Path()
        for poly in polys {
            guard let first = poly.first else { continue }
            all.move(to: first)
            for q in poly.dropFirst() { all.addLine(to: q) }
        }
        let red = c(1, 0.22, 0.24)
        ctx.stroke(all, with: .color(red.opacity(0.22)), style: StrokeStyle(lineWidth: cell * 0.5, lineCap: .round, lineJoin: .round))
        ctx.stroke(all, with: .color(red), style: StrokeStyle(lineWidth: cell * 0.16, lineCap: .round, lineJoin: .round))
        ctx.stroke(all, with: .color(c(1, 0.85, 0.85)), style: StrokeStyle(lineWidth: max(1, cell * 0.05), lineCap: .round, lineJoin: .round))
    }

    /// A mirror on its pivot disc, the silver bar at the mirror's angle (the one the beam uses).
    static func mirror(_ ctx: GraphicsContext, at p: CGPoint, cell: CGFloat, degrees: Double) {
        let r = cell * 0.44
        let disc = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        ctx.fill(disc, with: .radialGradient(Gradient(colors: [c(0.36, 0.4, 0.48), c(0.16, 0.18, 0.24)]), center: CGPoint(x: p.x - r * 0.3, y: p.y - r * 0.3), startRadius: 0, endRadius: r * 1.2))
        ctx.stroke(disc, with: .color(c(0.55, 0.85, 1).opacity(0.7)), lineWidth: max(1, cell * 0.04))
        var ticks = Path()
        for k in 0..<12 {
            let a = Double(k) / 12 * 2 * .pi
            ticks.move(to: CGPoint(x: p.x + CGFloat(cos(a)) * r * 0.82, y: p.y + CGFloat(sin(a)) * r * 0.82))
            ticks.addLine(to: CGPoint(x: p.x + CGFloat(cos(a)) * r * 0.95, y: p.y + CGFloat(sin(a)) * r * 0.95))
        }
        ctx.stroke(ticks, with: .color(.white.opacity(0.25)), lineWidth: 1)
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        g.rotate(by: .degrees(degrees))
        let bar = CGRect(x: -cell * 0.43, y: -cell * 0.08, width: cell * 0.86, height: cell * 0.16)
        g.fill(Path(roundedRect: bar, cornerRadius: cell * 0.04), with: .linearGradient(Gradient(colors: [.white, c(0.72, 0.86, 0.95), c(0.5, 0.6, 0.7)]),
                                                                                        startPoint: CGPoint(x: 0, y: bar.minY), endPoint: CGPoint(x: 0, y: bar.maxY)))
        g.stroke(Path(roundedRect: bar, cornerRadius: cell * 0.04), with: .color(c(0.1, 0.12, 0.16)), lineWidth: max(1, cell * 0.03))
        g.fill(Path(ellipseIn: CGRect(x: -cell * 0.06, y: -cell * 0.06, width: cell * 0.12, height: cell * 0.12)), with: .color(c(0.2, 0.22, 0.28)))
    }

    /// A laser cannon in the wall, its barrel and red lens pointing into the room.
    static func emitter(_ ctx: GraphicsContext, at p: CGPoint, cell: CGFloat, dir: CGVector) {
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        g.rotate(by: .radians(atan2(Double(dir.dy), Double(dir.dx))))
        let housing = CGRect(x: -cell * 0.4, y: -cell * 0.36, width: cell * 0.6, height: cell * 0.72)
        g.fill(Path(roundedRect: housing, cornerRadius: cell * 0.1), with: .linearGradient(Gradient(colors: [c(0.5, 0.52, 0.58), c(0.24, 0.25, 0.3)]),
                                                                                           startPoint: CGPoint(x: 0, y: housing.minY), endPoint: CGPoint(x: 0, y: housing.maxY)))
        g.stroke(Path(roundedRect: housing, cornerRadius: cell * 0.1), with: .color(.black.opacity(0.6)), lineWidth: 1)
        let barrel = CGRect(x: cell * 0.12, y: -cell * 0.16, width: cell * 0.36, height: cell * 0.32)
        g.fill(Path(roundedRect: barrel, cornerRadius: cell * 0.06), with: .color(c(0.18, 0.18, 0.22)))
        let lens = CGPoint(x: cell * 0.46, y: 0)
        g.fill(Path(ellipseIn: CGRect(x: lens.x - cell * 0.3, y: -cell * 0.3, width: cell * 0.6, height: cell * 0.6)),
               with: .radialGradient(Gradient(colors: [c(1, 0.3, 0.3).opacity(0.7), c(1, 0.2, 0.2).opacity(0)]), center: lens, startRadius: 0, endRadius: cell * 0.3))
        g.fill(Path(ellipseIn: CGRect(x: lens.x - cell * 0.1, y: -cell * 0.1, width: cell * 0.2, height: cell * 0.2)), with: .color(c(1, 0.5, 0.5)))
    }

    /// The banana, seen from above, a touch smaller than its cell.
    static func banana(_ ctx: GraphicsContext, at p: CGPoint, cell: CGFloat) {
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - cell * 0.62, y: p.y - cell * 0.62, width: cell * 1.24, height: cell * 1.24)),
                 with: .radialGradient(Gradient(colors: [c(1, 0.9, 0.3).opacity(0.45), c(1, 0.9, 0.3).opacity(0)]), center: p, startRadius: 0, endRadius: cell * 0.62))
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        g.fill(Path(ellipseIn: CGRect(x: -cell * 0.34, y: cell * 0.08, width: cell * 0.68, height: cell * 0.22)), with: .color(.black.opacity(0.35)))
        g.rotate(by: .degrees(-25))
        g.scaleBy(x: cell * 0.8, y: cell * 0.8)
        var body = Path()
        body.move(to: CGPoint(x: -0.44, y: -0.1))
        body.addQuadCurve(to: CGPoint(x: 0.44, y: -0.12), control: CGPoint(x: 0, y: 0.66))
        body.addQuadCurve(to: CGPoint(x: -0.44, y: -0.1), control: CGPoint(x: 0, y: 0.12))
        body.closeSubpath()
        g.fill(body, with: .linearGradient(Gradient(colors: [c(1, 0.96, 0.55), c(0.98, 0.76, 0.14)]), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: 0.32)))
        g.stroke(body, with: .color(c(0.22, 0.15, 0.02)), lineWidth: 0.06)
        g.fill(Path(roundedRect: CGRect(x: 0.4, y: -0.22, width: 0.12, height: 0.12), cornerRadius: 0.03), with: .color(c(0.42, 0.27, 0.08)))
        g.fill(Path(ellipseIn: CGRect(x: -0.06, y: 0.06, width: 0.12, height: 0.12)), with: .color(.white))
        g.fill(Path(ellipseIn: CGRect(x: -0.02, y: 0.09, width: 0.06, height: 0.07)), with: .color(c(0.1, 0.08, 0.04)))
    }
}

/// The room: steel floor tiles, riveted wall blocks and the green exit pad. Drawn once per level.
private struct MMRoom: View, Equatable {
    let size: CGSize
    let rows: Int
    let cols: Int
    let walls: [[Bool]]
    let exit: Int
    let level: Int

    var body: some View {
        Canvas { ctx, _ in
            guard walls.count == rows, rows > 0, cols > 0 else { return }
            let cell = min(size.width / CGFloat(cols), size.height / CGFloat(rows))
            let ox = (size.width - cell * CGFloat(cols)) / 2
            let oy = (size.height - cell * CGFloat(rows)) / 2
            let tint = MMArt.tint(level)
            var floor = Path(), seams = Path(), blocks = Path(), rivets = Path(), bevel = Path()
            for r in 0..<rows {
                for c in 0..<cols {
                    let rect = CGRect(x: ox + CGFloat(c) * cell, y: oy + CGFloat(r) * cell, width: cell + 0.5, height: cell + 0.5)
                    if walls[r][c] {
                        blocks.addRect(rect)
                        bevel.addRect(CGRect(x: rect.minX, y: rect.minY, width: cell, height: cell * 0.1))
                        for (dx, dy) in [(0.18, 0.18), (0.82, 0.18), (0.18, 0.82), (0.82, 0.82)] as [(CGFloat, CGFloat)] {
                            rivets.addEllipse(in: CGRect(x: rect.minX + cell * dx - cell * 0.04, y: rect.minY + cell * dy - cell * 0.04, width: cell * 0.08, height: cell * 0.08))
                        }
                    } else {
                        floor.addRect(rect)
                        seams.addRect(rect.insetBy(dx: cell * 0.04, dy: cell * 0.04))
                    }
                }
            }
            ctx.fill(floor, with: .color(tint.mix(with: .black, by: 0.72)))
            ctx.stroke(seams, with: .color(tint.mix(with: .white, by: 0.1).opacity(0.35)), lineWidth: 1)
            ctx.fill(blocks, with: .color(tint.mix(with: Color(white: 0.55), by: 0.55).mix(with: .black, by: 0.35)))
            ctx.fill(bevel, with: .color(.white.opacity(0.14)))
            ctx.fill(rivets, with: .color(.black.opacity(0.4)))
            // Exit: a green teleport pad.
            let er = exit / cols, ec = exit % cols
            let e = CGPoint(x: ox + (CGFloat(ec) + 0.5) * cell, y: oy + (CGFloat(er) + 0.5) * cell)
            ctx.fill(Path(ellipseIn: CGRect(x: e.x - cell * 0.9, y: e.y - cell * 0.9, width: cell * 1.8, height: cell * 1.8)),
                     with: .radialGradient(Gradient(colors: [MMArt.c(0.4, 1, 0.55).opacity(0.4), MMArt.c(0.4, 1, 0.55).opacity(0)]), center: e, startRadius: 0, endRadius: cell * 0.9))
            for (k, rr) in [0.42, 0.3, 0.17].enumerated() {
                let ring = Path(ellipseIn: CGRect(x: e.x - cell * CGFloat(rr), y: e.y - cell * CGFloat(rr), width: cell * CGFloat(rr) * 2, height: cell * CGFloat(rr) * 2))
                if k == 2 { ctx.fill(ring, with: .color(MMArt.c(0.6, 1, 0.7))) } else { ctx.stroke(ring, with: .color(MMArt.c(0.4, 1, 0.55)), lineWidth: max(1.5, cell * 0.06)) }
            }
        }
    }
}

/// Steel d-pad keys (banana yellow while pressed).
private struct MMKey: View {
    let lit: Bool
    let radius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius)
                .fill(LinearGradient(colors: lit ? [Color(red: 1, green: 0.9, blue: 0.45), Color(red: 0.95, green: 0.72, blue: 0.16)]
                                                 : [Color(white: 0.36), Color(white: 0.18)],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: radius).strokeBorder(.black.opacity(0.55), lineWidth: 2)
            RoundedRectangle(cornerRadius: radius - 3).strokeBorder(.white.opacity(lit ? 0.9 : 0.2), lineWidth: 1).padding(3)
        }
    }
}
