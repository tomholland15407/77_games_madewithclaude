//
//  LightCyclesGame.swift
//  A Banana Game
//
//  Reflex + spatial strategy — a Tron light-cycle duel. Your cycle races forward on its own,
//  laying a solid wall of light behind it; steer with the LEFT / RIGHT buttons (they turn you
//  90° relative to travel). Box the enemy cycle in so it crashes into a wall — but never cross
//  a wall yourself (yours, theirs, or the border) or you crash. Wipe out every rival before the
//  clock runs out. 7 levels: faster cycles, more rivals, and craftier AI — near-impossible by
//  L6–7.
//
//  Drawn as TRON's light-cycle grid: a black arena with a glowing grid and neon border (blue, then
//  violet, then Clu's orange-red), light walls as glowing ribbons through the occupied cells, sleek
//  light cycles at their heads, and a derezz burst when one crashes. Rivals show as bike icons that
//  dim when derezzed (no "rivals" word). The grid is an Equatable view; the rest is one Canvas.
//

import SwiftUI

enum LightCyclesGame {
    static let definition = GameDefinition(
        id: "light-cycles",
        title: "Neon Trails",
        emoji: "🍌",
        genre: .reflex,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Your cycle drives forward on its own, leaving a wall of light.",
                "Tap LEFT or RIGHT to turn 90°.",
                "Trap every enemy cycle so it smashes into a wall, and never hit a wall yourself.",
                "Crash, or let the clock run out, and it's back to level 1.",
            ],
            bulletsVI: [
                "Xe của bạn tự chạy về phía trước, để lại một bức tường ánh sáng.",
                "Chạm TRÁI hoặc PHẢI để rẽ 90°.",
                "Dồn mọi xe địch đâm vào tường, và đừng bao giờ tự đâm vào tường.",
                "Đâm xe, hoặc hết giờ, sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(LightCyclesView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct LightCyclesView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    private let cols = 17
    private let rows = 23

    private var tick: Double      { [0.17, 0.15, 0.13, 0.11, 0.10, 0.085, 0.07][min(level, 7) - 1] }
    private var aiCount: Int      { [1, 1, 2, 2, 2, 3, 3][min(level, 7) - 1] }
    private var aggression: Double { [0.15, 0.25, 0.35, 0.45, 0.55, 0.65, 0.75][min(level, 7) - 1] }
    private var lookahead: Int    { [6, 6, 5, 5, 4, 4, 3][min(level, 7) - 1] }
    private var timeLimit: Double { [30, 28, 26, 24, 22, 20, 18][min(level, 7) - 1] }

    private struct Cell: Hashable { var r: Int; var c: Int }
    private struct Cycle {
        var pos: Cell
        var dir: Cell            // heading as (dr, dc)
        var alive = true
        var pendingTurn = 0      // -1 left, +1 right, 0 straight (player)
        let color: Color
        let isPlayer: Bool
    }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var occupied: Set<Cell> = []
    @State private var cycles: [Cycle] = []
    @State private var timeLeft = 0.0
    @State private var loopTask: Task<Void, Never>?
    @State private var built = false
    @State private var derez: [LCDerez] = []   // presentation: cycles derezzing where they crashed

    var body: some View {
        VStack(spacing: 12) {
            // Rivals: one bike icon per enemy cycle, dimmed once it's derezzed.
            HStack(spacing: 8) {
                ForEach(Array(cycles.enumerated()).filter { !$0.element.isPlayer }, id: \.offset) { _, cyc in
                    LCBikeIcon(color: cyc.color, alive: cyc.alive)
                        .frame(width: 30, height: 16)
                }
            }
            .frame(height: 20)
            if !isDemo { timeBar.frame(height: 6).padding(.horizontal, 48) }

            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let cell = min(w / CGFloat(cols), h / CGFloat(rows))
                let boardW = cell * CGFloat(cols), boardH = cell * CGFloat(rows)
                let ox = (w - boardW) / 2, oy = (h - boardH) / 2

                ZStack {
                    // The grid never changes: drawn once.
                    LCGrid(size: geo.size, rows: rows, cols: cols, level: level).equatable()

                    // Light walls, the cycles and any derez bursts: one Canvas.
                    TimelineView(.animation(paused: derez.isEmpty)) { tl in
                        Canvas { ctx, _ in
                            let now = max(tl.date, Date())
                            let ctr = { (p: Cell) in CGPoint(x: ox + (CGFloat(p.c) + 0.5) * cell, y: oy + (CGFloat(p.r) + 0.5) * cell) }
                            for (idx, cyc) in cycles.enumerated() {
                                LCArt.trail((history[idx] ?? []).map(ctr), color: cyc.color, cell: cell, ctx)
                            }
                            for cyc in cycles where cyc.alive {
                                LCArt.bike(ctx, at: ctr(cyc.pos), dir: CGVector(dx: cyc.dir.c, dy: cyc.dir.r), color: cyc.color, cell: cell)
                            }
                            for d in derez {
                                LCArt.derez(ctx, at: ctr(Cell(r: d.r, c: d.c)), color: d.color, cell: cell, age: now.timeIntervalSince(d.at))
                            }
                        }
                    }
                    .frame(width: w, height: h)
                }
            }
            .padding(.horizontal, 8)
            .layoutPriority(1)

            // Steering.
            HStack(spacing: 40) {
                turnButton("arrow.turn.up.left", -1)
                turnButton("arrow.turn.up.right", 1)
            }
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
        // A cycle that stops being alive derezzes where it was.
        .onChange(of: cycles.map(\.alive)) { old, new in
            guard old.count == new.count else { return }
            for i in new.indices where old[i] && !new[i] {
                derez.append(LCDerez(r: cycles[i].pos.r, c: cycles[i].pos.c, color: cycles[i].color, at: Date()))
            }
        }
        .onChange(of: cycles.count) { _, _ in derez = [] }
        .task(id: derez.count) {
            guard !derez.isEmpty else { return }
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            let now = Date()
            derez.removeAll { now.timeIntervalSince($0.at) > 1.0 }
        }
    }

    // MARK: - Demo (live manual clip)

    /// A scripted duel (the real AI is stochastic): the player lays a vertical wall of
    /// light while the rival drives straight into it and crashes — the win. Drives the
    /// real `history`/`cycles` render state one cell per tick.
    private func runDemo() async {
        // Player: straight up column 8, laying its yellow wall. Rival: drives right along
        // row 16 and slams into that wall (col 8), which the player has long since filled.
        let wallCol = 8
        let crashRow = 16
        let playerCells = (0...16).map { Cell(r: rows - 4 - $0, c: wallCol) }  // (19,8) → (3,8)
        let rivalStart = Cell(r: crashRow, c: 0)
        let rivalDir = Cell(r: 0, c: 1)   // heading right, toward the wall

        while !Task.isCancelled {
            demoSetup(playerStart: playerCells[0], rivalStart: rivalStart)
            try? await Task.sleep(for: .seconds(0.5))
            var rivalPos = rivalStart
            var rivalAlive = true
            var t = 1
            while t < playerCells.count && !Task.isCancelled {
                // Player advances first, so its wall cell exists before the rival tests it.
                let p = playerCells[t]
                cycles[0].pos = p
                occupied.insert(p)
                history[0, default: []].append(p)

                if rivalAlive {
                    let n = Cell(r: rivalPos.r + rivalDir.r, c: rivalPos.c + rivalDir.c)
                    if occupied.contains(n) || n.c >= cols {
                        rivalAlive = false                       // slammed into the yellow wall
                        if cycles.count > 1 { cycles[1].alive = false }
                    } else {
                        rivalPos = n
                        cycles[1].pos = n
                        occupied.insert(n)
                        history[1, default: []].append(n)
                    }
                }
                t += 1
                try? await Task.sleep(for: .seconds(0.14))
            }
            if cycles.count > 1 { cycles[1].alive = false }
            try? await Task.sleep(for: .seconds(1.1))     // hold on "0 rivals"
        }
    }

    private func demoSetup(playerStart: Cell, rivalStart: Cell) {
        occupied = [playerStart, rivalStart]
        cycles = [
            Cycle(pos: playerStart, dir: Cell(r: -1, c: 0), color: BananaTheme.banana, isPlayer: true),
            Cycle(pos: rivalStart, dir: Cell(r: 0, c: 1),
                  color: Color(red: 0.95, green: 0.28, blue: 0.30), isPlayer: false),
        ]
        history = [0: [playerStart], 1: [rivalStart]]
        phase = .play
        timeLeft = timeLimit
    }

    private func turnButton(_ icon: String, _ d: Int) -> some View {
        Button { turn(d) } label: {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(LCArt.neon(level))
                .frame(width: 96, height: 64)
                .background(LCKey(color: LCArt.neon(level)))
        }
        .disabled(phase == .done)
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(LCArt.neon(level).opacity(0.15))
                Capsule().fill(frac < 0.3 ? Color(red: 1, green: 0.3, blue: 0.26) : LCArt.neon(level))
                    .frame(width: geo.size.width * frac)
            }
        }
    }

    // MARK: - Input
    private func turn(_ d: Int) {
        guard phase == .play else { return }
        if let i = cycles.firstIndex(where: { $0.isPlayer && $0.alive }) {
            cycles[i].pendingTurn = d
            SoundManager.shared.tap(); Haptics.tap()
        }
    }

    // MARK: - Flow
    private func run() async {
        if !built { setup(); built = true }
        timeLeft = timeLimit
        let start = Date()
        loopTask = Task {
            while !Task.isCancelled && phase == .play {
                try? await Task.sleep(for: .seconds(tick))
                timeLeft = max(0, timeLimit - Date().timeIntervalSince(start))
                if timeLeft <= 0 { fail(); break }
                stepAll()
            }
        }
    }

    private func setup() {
        // No border cells are seeded as walls — the grid edge itself is the wall (handled by the
        // bounds check in stepAll). Seeding a ring of occupied cells used to eat the outermost
        // row/column, which read as an invisible one-cell border.
        occupied = []

        let palette = [Color(red: 0.95, green: 0.28, blue: 0.30),
                       Color(red: 0.3, green: 0.6, blue: 1.0),
                       Color(red: 0.5, green: 0.9, blue: 0.4)]
        var cs: [Cycle] = []
        // Player: bottom-center heading up.
        let player = Cycle(pos: Cell(r: rows - 4, c: cols / 2), dir: Cell(r: -1, c: 0),
                           color: BananaTheme.banana, isPlayer: true)
        cs.append(player)
        occupied.insert(player.pos)
        // Rivals along the top, heading down.
        for k in 0..<aiCount {
            let c = cols / 2 + (k - aiCount / 2) * 4
            let cc = min(cols - 3, max(3, c))
            let ai = Cycle(pos: Cell(r: 3, c: cc), dir: Cell(r: 1, c: 0),
                           color: palette[k % palette.count], isPlayer: false)
            cs.append(ai)
            occupied.insert(ai.pos)
        }
        cycles = cs
        // Seed each cycle's light-wall history (keyed by cycle index) with its start cell.
        var h: [Int: [Cell]] = [:]
        for (idx, cyc) in cs.enumerated() { h[idx] = [cyc.pos] }
        history = h
        phase = .play
    }

    // Full per-cycle history for rendering the light walls (keyed by cycle index).
    @State private var history: [Int: [Cell]] = [:]

    private func stepAll() {
        // Decide AI turns.
        for i in cycles.indices where !cycles[i].isPlayer && cycles[i].alive {
            cycles[i].pendingTurn = aiDecide(cycles[i])
        }
        // Move every live cycle (player first for deterministic priority).
        let order = cycles.indices.sorted { (cycles[$0].isPlayer ? 0 : 1) < (cycles[$1].isPlayer ? 0 : 1) }
        for i in order where cycles[i].alive {
            var cyc = cycles[i]
            cyc.dir = rotated(cyc.dir, by: cyc.pendingTurn)
            cyc.pendingTurn = 0
            let next = Cell(r: cyc.pos.r + cyc.dir.r, c: cyc.pos.c + cyc.dir.c)
            if occupied.contains(next) || next.r < 0 || next.r >= rows || next.c < 0 || next.c >= cols {
                cyc.alive = false
                cycles[i] = cyc
                if cyc.isPlayer { fail(); return }
                SoundManager.shared.error(); Haptics.warning()
                continue
            }
            cyc.pos = next
            occupied.insert(next)
            history[i, default: []].append(next)
            cycles[i] = cyc
        }
        if cycles.filter({ !$0.isPlayer }).allSatisfy({ !$0.alive }) { win() }
    }

    private func rotated(_ dir: Cell, by turn: Int) -> Cell {
        switch turn {
        case -1: return Cell(r: -dir.c, c: dir.r)   // left
        case 1:  return Cell(r: dir.c, c: -dir.r)   // right
        default: return dir
        }
    }

    private func free(_ cell: Cell) -> Bool {
        cell.r >= 0 && cell.r < rows && cell.c >= 0 && cell.c < cols && !occupied.contains(cell)
    }

    private func freeRun(from: Cell, dir: Cell, maxSteps: Int) -> Int {
        var n = 0
        var cur = from
        while n < maxSteps {
            cur = Cell(r: cur.r + dir.r, c: cur.c + dir.c)
            if !free(cur) { break }
            n += 1
        }
        return n
    }

    private func aiDecide(_ cyc: Cycle) -> Int {
        let options: [Int] = [0, -1, 1]
        // Rank by survival room ahead.
        var scored: [(turn: Int, run: Int, dir: Cell)] = options.map {
            let d = rotated(cyc.dir, by: $0)
            return ($0, freeRun(from: cyc.pos, dir: d, maxSteps: lookahead), d)
        }
        let safe = scored.filter { $0.run >= 1 }
        if safe.isEmpty { return 0 }   // doomed — go straight

        // Aggression: sometimes steer toward the player, but only among safe moves.
        if Double.random(in: 0...1) < aggression,
           let player = cycles.first(where: { $0.isPlayer && $0.alive }) {
            let best = safe.min { a, b in
                let na = Cell(r: cyc.pos.r + a.dir.r, c: cyc.pos.c + a.dir.c)
                let nb = Cell(r: cyc.pos.r + b.dir.r, c: cyc.pos.c + b.dir.c)
                return dist(na, player.pos) < dist(nb, player.pos)
            }
            if let best { return best.turn }
        }
        // Otherwise maximize open space, preferring straight on ties.
        scored = safe.sorted { $0.run > $1.run }
        let top = scored.first!.run
        let tied = scored.filter { $0.run == top }
        return (tied.first { $0.turn == 0 } ?? tied.randomElement()!).turn
    }

    private func dist(_ a: Cell, _ b: Cell) -> Int { abs(a.r - b.r) + abs(a.c - b.c) }

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

// MARK: - TRON art

/// A cycle that just crashed: where, its colour, and when (it derezzes, then fades).
private struct LCDerez {
    let r: Int
    let c: Int
    let color: Color
    let at: Date
}

private enum LCArt {
    /// The arena's neon: TRON blue, then violet, then Clu's orange-red at 6–7.
    static func neon(_ level: Int) -> Color {
        level >= 6 ? Color(red: 1, green: 0.45, blue: 0.22) : level >= 4 ? Color(red: 0.72, green: 0.45, blue: 1) : Color(red: 0.25, green: 0.85, blue: 1)
    }

    /// A light wall: a glowing ribbon through the cells the cycle has driven.
    static func trail(_ pts: [CGPoint], color: Color, cell: CGFloat, _ ctx: GraphicsContext) {
        guard let first = pts.first else { return }
        if pts.count == 1 {
            ctx.fill(Path(roundedRect: CGRect(x: first.x - cell * 0.21, y: first.y - cell * 0.21, width: cell * 0.42, height: cell * 0.42), cornerRadius: cell * 0.08), with: .color(color))
            return
        }
        var line = Path()
        line.move(to: first)
        for p in pts.dropFirst() { line.addLine(to: p) }
        ctx.stroke(line, with: .color(color.opacity(0.22)), style: StrokeStyle(lineWidth: cell * 0.95, lineCap: .square, lineJoin: .miter))
        ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: cell * 0.44, lineCap: .square, lineJoin: .miter))
        ctx.stroke(line, with: .color(.white.opacity(0.75)), style: StrokeStyle(lineWidth: max(1, cell * 0.12), lineCap: .square, lineJoin: .miter))
    }

    /// A light cycle along its heading: dark body, glowing edge stripe and wheel rims.
    static func bike(_ ctx: GraphicsContext, at p: CGPoint, dir: CGVector, color: Color, cell: CGFloat) {
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        g.rotate(by: .radians(atan2(Double(dir.dy), Double(dir.dx))))
        let L = cell * 1.3, W = cell * 0.62
        g.fill(Path(ellipseIn: CGRect(x: -L * 0.7, y: -W, width: L * 1.4, height: W * 2)),
               with: .radialGradient(Gradient(colors: [color.opacity(0.45), color.opacity(0)]), center: .zero, startRadius: 0, endRadius: L * 0.7))
        let body = Path(roundedRect: CGRect(x: -L * 0.5, y: -W * 0.42, width: L, height: W * 0.84), cornerRadius: W * 0.42)
        g.fill(body, with: .color(Color(white: 0.06)))
        g.stroke(body, with: .color(color), lineWidth: max(1.2, cell * 0.1))
        for x in [-L * 0.3, L * 0.3] {
            let wheel = Path(ellipseIn: CGRect(x: x - W * 0.3, y: -W * 0.3, width: W * 0.6, height: W * 0.6))
            g.fill(wheel, with: .color(Color(white: 0.02)))
            g.stroke(wheel, with: .color(color), lineWidth: max(1, cell * 0.08))
        }
        g.fill(Path(roundedRect: CGRect(x: -L * 0.08, y: -W * 0.16, width: L * 0.3, height: W * 0.32), cornerRadius: W * 0.16), with: .color(color.opacity(0.85)))
        g.fill(Path(roundedRect: CGRect(x: L * 0.32, y: -W * 0.08, width: L * 0.16, height: W * 0.16), cornerRadius: W * 0.08), with: .color(.white))
    }

    /// Derezz: a flash and a scatter of fading light cubes.
    static func derez(_ ctx: GraphicsContext, at p: CGPoint, color: Color, cell: CGFloat, age: Double) {
        guard age < 1.0 else { return }
        let a = CGFloat(age)
        if age < 0.3 {
            let r = cell * (0.5 + a * 4)
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color.opacity(1 - age / 0.3)), lineWidth: 2)
        }
        var cubes = Path()
        for i in 0..<14 {
            let dir = Double(i) / 14 * 2 * .pi + Double(i % 3) * 0.3
            let d = cell * (0.4 + a * CGFloat(2.2 + Double(i % 4) * 0.5))
            let q = CGPoint(x: p.x + CGFloat(cos(dir)) * d, y: p.y + CGFloat(sin(dir)) * d)
            let s = cell * (0.28 - a * 0.18)
            cubes.addRect(CGRect(x: q.x - s / 2, y: q.y - s / 2, width: s, height: s))
        }
        ctx.fill(cubes, with: .color(color.opacity(max(0, 1 - age))))
    }
}

/// The arena: black, a glowing grid (brighter every fourth line) and a neon border. Drawn once.
private struct LCGrid: View, Equatable {
    let size: CGSize
    let rows: Int
    let cols: Int
    let level: Int

    var body: some View {
        Canvas { ctx, _ in
            let cell = min(size.width / CGFloat(cols), size.height / CGFloat(rows))
            let bw = cell * CGFloat(cols), bh = cell * CGFloat(rows)
            let ox = (size.width - bw) / 2, oy = (size.height - bh) / 2
            let neon = LCArt.neon(level)
            let board = CGRect(x: ox, y: oy, width: bw, height: bh)
            ctx.fill(Path(board), with: .radialGradient(Gradient(colors: [neon.opacity(0.08), .clear]), center: CGPoint(x: board.midX, y: board.midY),
                                                        startRadius: 0, endRadius: max(bw, bh) * 0.7))
            var minor = Path(), major = Path()
            for c in 0...cols {
                var l = Path()
                l.move(to: CGPoint(x: ox + CGFloat(c) * cell, y: oy)); l.addLine(to: CGPoint(x: ox + CGFloat(c) * cell, y: oy + bh))
                if c % 4 == 0 { major.addPath(l) } else { minor.addPath(l) }
            }
            for r in 0...rows {
                var l = Path()
                l.move(to: CGPoint(x: ox, y: oy + CGFloat(r) * cell)); l.addLine(to: CGPoint(x: ox + bw, y: oy + CGFloat(r) * cell))
                if r % 4 == 0 { major.addPath(l) } else { minor.addPath(l) }
            }
            ctx.stroke(minor, with: .color(neon.opacity(0.14)), lineWidth: 1)
            ctx.stroke(major, with: .color(neon.opacity(0.32)), lineWidth: 1)
            let border = Path(roundedRect: board, cornerRadius: 6)
            ctx.stroke(border, with: .color(neon.opacity(0.25)), lineWidth: 8)
            ctx.stroke(border, with: .color(neon), lineWidth: 2.5)
        }
    }
}

/// A rival in the HUD: a small bike, dimmed once it has derezzed.
private struct LCBikeIcon: View {
    let color: Color
    let alive: Bool

    var body: some View {
        Canvas { ctx, size in
            var g = ctx
            g.opacity = alive ? 1 : 0.25
            LCArt.bike(g, at: CGPoint(x: size.width / 2, y: size.height / 2), dir: CGVector(dx: 1, dy: 0), color: color, cell: size.width / 1.6)
        }
    }
}

/// A dark glass turn key with a neon edge.
private struct LCKey: View {
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(LinearGradient(colors: [Color(white: 0.14), Color(white: 0.04)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 16).strokeBorder(color.opacity(0.3), lineWidth: 6)
            RoundedRectangle(cornerRadius: 16).strokeBorder(color, lineWidth: 2)
        }
    }
}
