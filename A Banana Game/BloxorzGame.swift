//
//  BloxorzGame.swift
//  A Banana Game
//
//  Brain — Bloxorz. A 1×2 block rolls across a tiled board; tip it end-over-end with the d-pad and
//  land it standing upright, filling exactly the goal square. Roll any part of the block off a tile
//  (off the board or over a hole) and it falls — back to level 1. A clock keeps the pressure on.
//
//  Boards are a rectangle with random holes punched out, then verified with a BFS over block states
//  (standing / lying flat / lying on edge) so every level has a real, non-trivial rolling solution
//  and is never pre-solved. Generation runs off-main behind the brainstorming banana. Levels grow
//  the board, punch more holes, and demand longer solutions until it's brutal.
//

import SwiftUI

private nonisolated struct BCell: Hashable, Sendable { let r: Int; let c: Int }

private nonisolated struct BloxPuzzle: Sendable {
    let w: Int; let h: Int
    let tiles: Set<BCell>
    let start: BCell
    let goal: BCell
}

enum BloxorzGame {
    static let definition = GameDefinition(
        id: "bloxorz",
        title: "Topple Block",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Use the d-pad to roll the 1×2 block end over end across the tiles.",
                "Upright it covers one square; tipped over it covers two.",
                "Land it standing exactly on the goal square to win.",
                "Roll off the board or over a hole and you drop to level 1.",
            ],
            bulletsVI: [
                "Dùng d-pad để lăn khối 1×2 lộn đầu qua các ô.",
                "Đứng thẳng nó chiếm một ô; ngã ra nó chiếm hai ô.",
                "Cho nó đứng đúng trên ô mục tiêu để thắng.",
                "Lăn khỏi bàn hoặc qua một lỗ sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(BloxorzView(level: level, onWin: onWin, onFail: onFail))
        },
        prefetch: { level in BloxorzView(level: level, onWin: {}, onFail: {}).prefetchBoard() }
    )
}

struct BloxorzView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    // board (w,h), holes, min solution moves
    private var params: (w: Int, h: Int, holes: Int, minMoves: Int) {
        [ (4, 4, 0, 6), (5, 5, 1, 9), (5, 6, 3, 12), (6, 6, 4, 16),
          (6, 7, 6, 20), (7, 7, 8, 26), (7, 8, 10, 32) ][min(level, 7) - 1]
    }
    private var timeLimit: Double { [40, 50, 60, 70, 75, 80, 85][min(level, 7) - 1] }

    private var skyTop: Color { Color(red: 0.7, green: 0.16, blue: 0.04) }
    private var skyBottom: Color { Color(red: 0.3, green: 0.04, blue: 0.01) }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var ready = false
    @State private var w = 0
    @State private var h = 0
    @State private var tiles: Set<BCell> = []
    @State private var goal = BCell(r: 0, c: 0)
    @State private var block: [BCell] = []      // 1 cell = standing, 2 = lying
    @State private var timeLeft = 0.0
    @State private var shakeTick = 0
    @State private var loopTask: Task<Void, Never>?
    @State private var demoDir: (dc: Int, dr: Int)? = nil   // d-pad arrow flashed in the demo
    // Presentation only: a move counter, the roll in progress (the block tips over its edge),
    // and the drop into the void on a fall / into the hole on a win.
    private struct RollAnim { let from: [BCell]; let dc: Int; let dr: Int; let t0: Date }
    @State private var moves = 0
    @State private var rollAnim: RollAnim? = nil
    @State private var fallStart: Date? = nil
    @State private var sinkStart: Date? = nil

    var body: some View {
        Group {
            if ready { gameBody } else { BrainstormingView(skyTop: skyTop, skyBottom: skyBottom) }
        }
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
    }

    // MARK: - Demo (live manual clip)

    /// A full 4×4 board: roll right, right (flat then stand), then down, down to land
    /// standing exactly on the goal. Drives the real `move`/roll physics.
    private func runDemo() async {
        let moves = [(0, 1), (0, 1), (1, 0), (1, 0)]   // (dr, dc): right, right, down, down
        while !Task.isCancelled {
            demoSetup()
            try? await Task.sleep(for: .seconds(0.7))
            for (dr, dc) in moves {
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.1)) { demoDir = (dc: dc, dr: dr) }
                move(dr: dr, dc: dc)
                try? await Task.sleep(for: .seconds(0.4))
                withAnimation(.easeIn(duration: 0.1)) { demoDir = nil }
                try? await Task.sleep(for: .seconds(0.2))
            }
            try? await Task.sleep(for: .seconds(1.3))   // hold on the standing block
        }
    }

    private func demoSetup() {
        w = 4; h = 4
        var t = Set<BCell>()
        for r in 0..<4 { for c in 0..<4 { t.insert(BCell(r: r, c: c)) } }
        tiles = t
        goal = BCell(r: 3, c: 3)
        block = [BCell(r: 0, c: 0)]
        moves = 0; rollAnim = nil; fallStart = nil; sinkStart = nil
        ready = true
        phase = .play
        timeLeft = timeLimit
    }

    private var gameBody: some View {
        VStack(spacing: isDemo ? 4 : 8) {
            HStack(spacing: 8) {
                Text(L("MOVES", "BƯỚC"))
                    .font(.system(size: isDemo ? 12 : 15, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Color(red: 1, green: 0.62, blue: 0.3))
                Text(String(format: "%03d", moves))
                    .font(.system(size: isDemo ? 18 : 24, weight: .black, design: .monospaced))
                    .foregroundStyle(Color(red: 1, green: 0.88, blue: 0.6))
                    .contentTransition(.numericText())
            }
            .shadow(color: Color(red: 1, green: 0.45, blue: 0.1).opacity(0.9), radius: 6)
            if !isDemo { timeBar.frame(height: 5).padding(.horizontal, 60) }
            boardView
            dpad
        }
        .padding(.top, isDemo ? 8 : 12)
        .padding(.bottom, isDemo ? 8 : 12)
        .background(BloxorzSky().equatable())
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var boardView: some View {
        GeometryReader { geo in
            let proj = BloxProj.fit(w: w, h: h, in: geo.size)
            TimelineView(.animation(paused: !animating)) { tl in
                Canvas { ctx, _ in drawBoard(ctx, proj, now: tl.date) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .screenShake(shakeTick, amount: 5)
        }
    }

    private var animating: Bool { rollAnim != nil || fallStart != nil || sinkStart != nil }

    /// Stone slabs (far rows first, right to left), the goal hole, then the rusty block — rolled
    /// about its edge mid-move, dropping into the void on a fall, sinking into the hole on a win.
    private func drawBoard(_ ctx: GraphicsContext, _ proj: BloxProj, now: Date) {
        guard w > 0, h > 0 else { return }
        for t in tiles.sorted(by: { $0.r != $1.r ? $0.r < $1.r : $0.c > $1.c }) {
            BloxArt.slab(ctx, proj, c: t.c, r: t.r, hole: t == goal)
        }
        // The block's current box, or the box it's rolling out of.
        var box = BloxArt.box(for: block)
        var angle = 0.0
        var pivotDir = (dc: 0, dr: 0)
        if let a = rollAnim {
            let k = min(1, now.timeIntervalSince(a.t0) / 0.16)
            if k < 1 {
                box = BloxArt.box(for: a.from)
                angle = (1 - pow(1 - k, 2)) * .pi / 2
                pivotDir = (a.dc, a.dr)
            }
        }
        var dz = 0.0, alpha = 1.0
        if let f = fallStart {
            let t = max(0, now.timeIntervalSince(f))
            dz = -6 * t * t; alpha = max(0, 1 - t / 0.35)
        }
        if let s = sinkStart {
            let t = max(0, min(1, now.timeIntervalSince(s) / 0.55))
            dz = -2.2 * t * t; alpha = 1 - t * 0.9
        }
        BloxArt.block(ctx, proj, box: box, rollAngle: angle, dir: pivotDir, dz: dz, alpha: alpha)
    }

    /// Keyboard arrow keys (Bloxorz is played on the arrows): an inverted T, or one row in the demo.
    private var dpad: some View {
        Group {
            if isDemo {
                HStack(spacing: 6) {
                    arrow("arrowtriangle.left.fill", -1, 0)
                    arrow("arrowtriangle.up.fill", 0, -1)
                    arrow("arrowtriangle.down.fill", 0, 1)
                    arrow("arrowtriangle.right.fill", 1, 0)
                }
            } else {
                VStack(spacing: 6) {
                    arrow("arrowtriangle.up.fill", 0, -1)
                    HStack(spacing: 6) {
                        arrow("arrowtriangle.left.fill", -1, 0)
                        arrow("arrowtriangle.down.fill", 0, 1)
                        arrow("arrowtriangle.right.fill", 1, 0)
                    }
                }
            }
        }
        .padding(.bottom, isDemo ? 0 : 4)
    }

    private func arrow(_ icon: String, _ dc: Int, _ dr: Int) -> some View {
        let lit = demoDir?.dc == dc && demoDir?.dr == dr
        return Button { move(dr: dr, dc: dc) } label: {
            Image(systemName: icon)
                .font(.system(size: isDemo ? 14 : 18, weight: .bold))
                .frame(width: isDemo ? 50 : 64, height: isDemo ? 34 : 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(ArrowKeyStyle(lit: lit))
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.35))
                Capsule().fill(frac < 0.3 ? Color(red: 1, green: 0.25, blue: 0.15) : Color(red: 1, green: 0.7, blue: 0.3))
                    .frame(width: geo.size.width * frac)
            }
        }
    }
    // MARK: - Input
    private func move(dr: Int, dc: Int) {
        guard phase == .play else { return }
        let next = Self.roll(block, dr: dr, dc: dc)
        let before = block
        if next.allSatisfy({ tiles.contains($0) }) {
            block = next.sorted { $0.r != $1.r ? $0.r < $1.r : $0.c < $1.c }
            recordRoll(from: before, dr: dr, dc: dc)
            SoundManager.shared.tap(); Haptics.tap()
            if block.count == 1 && block[0] == goal { sinkStart = Date().addingTimeInterval(0.16); win() }
        } else {
            block = next.sorted { $0.r != $1.r ? $0.r < $1.r : $0.c < $1.c }
            recordRoll(from: before, dr: dr, dc: dc)
            fell()
        }
    }

    /// Presentation only: count the move and animate the block tipping from `from` to `block`.
    private func recordRoll(from: [BCell], dr: Int, dc: Int) {
        moves += 1
        let anim = RollAnim(from: from, dc: dc, dr: dr, t0: Date())
        rollAnim = anim
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.2))
            if rollAnim?.t0 == anim.t0 { rollAnim = nil }
        }
    }

    private func fell() {
        guard phase == .play else { return }
        phase = .done; loopTask?.cancel()
        fallStart = Date().addingTimeInterval(0.16)
        SoundManager.shared.error(); Haptics.warning(); shakeTick += 1
        Task { try? await Task.sleep(for: .seconds(0.35)); onFail() }
    }

    private func win() {
        guard phase != .done else { return }
        phase = .done; loopTask?.cancel(); onWin()
    }

    private func fail() {
        guard phase != .done else { return }
        phase = .done; loopTask?.cancel(); SoundManager.shared.error(); onFail()
    }

    // MARK: - Flow
    /// Hands this level's board build to `BoardCache` so it can run during the countdown.
    func prefetchBoard() {
        let p = params
        BoardCache.prefetch(boardKey) { Self.makePuzzle(p) }
    }
    private var boardKey: String { BoardCache.key("bloxorz", level: level) }

    private func run() async {
        let p = params
        let t0 = Date()
        let puzzle = await BoardCache.take(boardKey) { Self.makePuzzle(p) }
        guard !Task.isCancelled else { return }
        await BoardCache.holdBrainstorm(since: t0, minimum: 0.7)
        guard !Task.isCancelled else { return }
        w = puzzle.w; h = puzzle.h; tiles = puzzle.tiles; goal = puzzle.goal
        block = [puzzle.start]
        moves = 0; rollAnim = nil; fallStart = nil; sinkStart = nil
        ready = true
        phase = .play
        timeLeft = timeLimit
        let start = Date()
        loopTask = Task {
            while !Task.isCancelled && phase == .play {
                try? await Task.sleep(for: .seconds(0.05))
                timeLeft = max(0, timeLimit - Date().timeIntervalSince(start))
                if timeLeft <= 0 { fail(); break }
            }
        }
    }

    // MARK: - Rolling (pure)
    /// Returns the cells the block would occupy after rolling one step in (dr,dc).
    private nonisolated static func roll(_ block: [BCell], dr: Int, dc: Int) -> [BCell] {
        let sorted = block.sorted { $0.r != $1.r ? $0.r < $1.r : $0.c < $1.c }
        if sorted.count == 1 {
            let s = sorted[0]
            if dc == 1 { return [BCell(r: s.r, c: s.c + 1), BCell(r: s.r, c: s.c + 2)] }
            if dc == -1 { return [BCell(r: s.r, c: s.c - 2), BCell(r: s.r, c: s.c - 1)] }
            if dr == 1 { return [BCell(r: s.r + 1, c: s.c), BCell(r: s.r + 2, c: s.c)] }
            return [BCell(r: s.r - 2, c: s.c), BCell(r: s.r - 1, c: s.c)]
        }
        let a = sorted[0], b = sorted[1]
        let horizontal = a.r == b.r
        if horizontal {
            let r = a.r, c = a.c   // a is left (c), b is c+1
            if dc == 1 { return [BCell(r: r, c: c + 2)] }
            if dc == -1 { return [BCell(r: r, c: c - 1)] }
            if dr == 1 { return [BCell(r: r + 1, c: c), BCell(r: r + 1, c: c + 1)] }
            return [BCell(r: r - 1, c: c), BCell(r: r - 1, c: c + 1)]
        } else {
            let r = a.r, c = a.c   // a is top (r), b is r+1
            if dr == 1 { return [BCell(r: r + 2, c: c)] }
            if dr == -1 { return [BCell(r: r - 1, c: c)] }
            if dc == 1 { return [BCell(r: r, c: c + 1), BCell(r: r + 1, c: c + 1)] }
            return [BCell(r: r, c: c - 1), BCell(r: r + 1, c: c - 1)]
        }
    }

    // MARK: - Generation + BFS verify (pure / off-main)
    private nonisolated static func makePuzzle(_ p: (w: Int, h: Int, holes: Int, minMoves: Int)) -> BloxPuzzle {
        var best: BloxPuzzle?
        var bestMoves = -1
        for _ in 0..<300 {
            guard let cand = generate(p) else { continue }
            if let moves = solve(cand) {
                if moves >= p.minMoves { return cand }
                if moves > bestMoves { bestMoves = moves; best = cand }
            }
        }
        return best ?? fallback(p)
    }

    private nonisolated static func generate(_ p: (w: Int, h: Int, holes: Int, minMoves: Int)) -> BloxPuzzle? {
        var all: [BCell] = []
        for r in 0..<p.h { for c in 0..<p.w { all.append(BCell(r: r, c: c)) } }
        let start = all.randomElement()!
        var goal = all.randomElement()!
        var guardN = 0
        while goal == start && guardN < 50 { goal = all.randomElement()!; guardN += 1 }
        if goal == start { return nil }
        var tiles = Set(all)
        var removable = all.filter { $0 != start && $0 != goal }.shuffled()
        for _ in 0..<min(p.holes, removable.count) { tiles.remove(removable.removeLast()) }
        return BloxPuzzle(w: p.w, h: p.h, tiles: tiles, start: start, goal: goal)
    }

    private nonisolated static func solve(_ p: BloxPuzzle) -> Int? {
        func key(_ cells: [BCell]) -> String {
            cells.sorted { $0.r != $1.r ? $0.r < $1.r : $0.c < $1.c }
                .map { "\($0.r),\($0.c)" }.joined(separator: ";")
        }
        let startState = [p.start]
        var seen: Set<String> = [key(startState)]
        var queue: [([BCell], Int)] = [(startState, 0)]
        var head = 0, expanded = 0
        while head < queue.count {
            let (cells, d) = queue[head]; head += 1
            expanded += 1
            if expanded > 150_000 { return nil }
            if cells.count == 1 && cells[0] == p.goal { return d }
            for (dr, dc) in [(0, 1), (0, -1), (1, 0), (-1, 0)] {
                let next = roll(cells, dr: dr, dc: dc)
                if !next.allSatisfy({ p.tiles.contains($0) }) { continue }
                let k = key(next)
                if seen.contains(k) { continue }
                seen.insert(k)
                queue.append((next, d + 1))
            }
        }
        return nil
    }

    private nonisolated static func fallback(_ p: (w: Int, h: Int, holes: Int, minMoves: Int)) -> BloxPuzzle {
        var all: [BCell] = []
        for r in 0..<4 { for c in 0..<4 { all.append(BCell(r: r, c: c)) } }
        return BloxPuzzle(w: 4, h: 4, tiles: Set(all), start: BCell(r: 0, c: 0), goal: BCell(r: 3, c: 3))
    }
}

// MARK: - Bloxorz art

/// Bloxorz's oblique camera: columns run right (slightly up), rows come toward you (down-right),
/// height goes straight up. Fitted so the whole board plus a standing block fills the area.
private struct BloxProj {
    let s: CGFloat
    let origin: CGPoint
    static let U = CGVector(dx: 1, dy: -0.1)
    static let V = CGVector(dx: 0.3, dy: 0.7)
    static let Z: CGFloat = 0.9

    func pt(_ c: Double, _ r: Double, _ z: Double) -> CGPoint {
        CGPoint(x: origin.x + s * (CGFloat(c) * Self.U.dx + CGFloat(r) * Self.V.dx),
                y: origin.y + s * (CGFloat(c) * Self.U.dy + CGFloat(r) * Self.V.dy - CGFloat(z) * Self.Z))
    }

    static func fit(w: Int, h: Int, in size: CGSize) -> BloxProj {
        guard w > 0, h > 0, size.width > 1, size.height > 1 else { return BloxProj(s: 1, origin: .zero) }
        var minX = CGFloat.infinity, maxX = -CGFloat.infinity, minY = CGFloat.infinity, maxY = -CGFloat.infinity
        for c in [0, w] {
            for r in [0, h] {
                for z in [-0.18, 2.0] {
                    let x = CGFloat(c) * U.dx + CGFloat(r) * V.dx
                    let y = CGFloat(c) * U.dy + CGFloat(r) * V.dy - CGFloat(z) * Z
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        let s = min(size.width * 0.94 / (maxX - minX), size.height * 0.94 / (maxY - minY), 72)
        return BloxProj(s: s, origin: CGPoint(x: (size.width - (maxX - minX) * s) / 2 - minX * s,
                                               y: (size.height - (maxY - minY) * s) / 2 - minY * s))
    }
}

private enum BloxArt {
    static func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    private static func poly(_ pts: [CGPoint]) -> Path {
        var p = Path()
        p.addLines(pts)
        p.closeSubpath()
        return p
    }

    /// A grey stone floor slab (top, left side, front side), or the goal: a square pit.
    static func slab(_ ctx: GraphicsContext, _ pj: BloxProj, c col: Int, r row: Int, hole: Bool) {
        let g = 0.035, t = 0.16
        let c0 = Double(col) + g, c1 = Double(col + 1) - g, r0 = Double(row) + g, r1 = Double(row + 1) - g
        let front = poly([pj.pt(c0, r1, 0), pj.pt(c1, r1, 0), pj.pt(c1, r1, -t), pj.pt(c0, r1, -t)])
        let left = poly([pj.pt(c0, r0, 0), pj.pt(c0, r1, 0), pj.pt(c0, r1, -t), pj.pt(c0, r0, -t)])
        let topPts = [pj.pt(c0, r0, 0), pj.pt(c1, r0, 0), pj.pt(c1, r1, 0), pj.pt(c0, r1, 0)]
        let top = poly(topPts)
        ctx.fill(front, with: .color(c(0.34, 0.35, 0.37)))
        ctx.fill(left, with: .color(c(0.5, 0.51, 0.53)))
        if hole {
            // The pit: dark floor, with its back wall and right wall catching the light.
            ctx.fill(top, with: .color(c(0.08, 0.06, 0.05)))
            var g2 = ctx
            g2.clip(to: top)
            let d = 0.7
            g2.fill(poly([pj.pt(c0, r0, 0), pj.pt(c1, r0, 0), pj.pt(c1, r0, -d), pj.pt(c0, r0, -d)]),
                    with: .linearGradient(Gradient(colors: [c(0.42, 0.4, 0.38), c(0.12, 0.1, 0.09)]),
                                          startPoint: pj.pt(c0, r0, 0), endPoint: pj.pt(c0, r0, -d)))
            g2.fill(poly([pj.pt(c1, r0, 0), pj.pt(c1, r1, 0), pj.pt(c1, r1, -d), pj.pt(c1, r0, -d)]),
                    with: .linearGradient(Gradient(colors: [c(0.3, 0.28, 0.26), c(0.08, 0.07, 0.06)]),
                                          startPoint: pj.pt(c1, r0, 0), endPoint: pj.pt(c1, r0, -d)))
            ctx.stroke(top, with: .color(c(0.62, 0.62, 0.64)), lineWidth: max(1, pj.s * 0.03))
        } else {
            ctx.fill(top, with: .linearGradient(Gradient(colors: [c(0.86, 0.87, 0.88), c(0.74, 0.75, 0.77)]),
                                                startPoint: topPts[0], endPoint: topPts[2]))
            // Speckled stone.
            for k in 0..<5 {
                let h = Double((col * 73 + row * 31 + k * 17) % 97) / 97
                let h2 = Double((col * 29 + row * 61 + k * 43) % 89) / 89
                let p = pj.pt(c0 + (c1 - c0) * (0.12 + 0.76 * h), r0 + (r1 - r0) * (0.12 + 0.76 * h2), 0)
                let rr = pj.s * 0.035
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr * 0.6, width: rr * 2, height: rr * 1.2)),
                         with: .color(c(0.55, 0.56, 0.58).opacity(0.5)))
            }
            // Bevel: lit back edge, shaded front edge.
            var back = Path()
            back.move(to: topPts[3]); back.addLine(to: topPts[0]); back.addLine(to: topPts[1])
            ctx.stroke(back, with: .color(.white.opacity(0.55)), lineWidth: max(1, pj.s * 0.025))
            ctx.stroke(top, with: .color(c(0.45, 0.46, 0.48).opacity(0.7)), lineWidth: max(0.6, pj.s * 0.012))
        }
    }

    /// The block's resting box in board units: (c0, c1, r0, r1, height).
    struct Box { let c0: Double, c1: Double, r0: Double, r1: Double, h: Double }

    static func box(for cells: [BCell]) -> Box {
        guard let first = cells.first else { return Box(c0: 0, c1: 1, r0: 0, r1: 1, h: 2) }
        let minC = cells.map(\.c).min() ?? first.c, maxC = cells.map(\.c).max() ?? first.c
        let minR = cells.map(\.r).min() ?? first.r, maxR = cells.map(\.r).max() ?? first.r
        return Box(c0: Double(minC), c1: Double(maxC + 1), r0: Double(minR), r1: Double(maxR + 1),
                   h: cells.count == 1 ? 2 : 1)
    }

    private struct V3 { var c: Double, r: Double, z: Double }

    /// The rusty-metal block: faces facing the camera are drawn (a convex box needs no sorting),
    /// each with a rust texture mapped onto it and shaded by its tilt. `rollAngle` tips the box
    /// about its leading bottom edge in direction `dir` (0…π/2).
    static func block(_ ctx: GraphicsContext, _ pj: BloxProj, box b: Box, rollAngle: Double,
                      dir: (dc: Int, dr: Int), dz: Double, alpha: Double) {
        guard alpha > 0.01 else { return }
        var corners: [V3] = []
        for zi in 0..<2 { for yi in 0..<2 { for xi in 0..<2 {
            corners.append(V3(c: xi == 0 ? b.c0 : b.c1, r: yi == 0 ? b.r0 : b.r1, z: zi == 0 ? 0 : b.h))
        } } }
        let ca = cos(rollAngle), sa = sin(rollAngle)
        func rot(_ p: V3) -> V3 {
            var q = p
            if dir.dc == 1 { let d = p.c - b.c1; q.c = b.c1 + d * ca + p.z * sa; q.z = -d * sa + p.z * ca }
            if dir.dc == -1 { let d = p.c - b.c0; q.c = b.c0 + d * ca - p.z * sa; q.z = d * sa + p.z * ca }
            if dir.dr == 1 { let d = p.r - b.r1; q.r = b.r1 + d * ca + p.z * sa; q.z = -d * sa + p.z * ca }
            if dir.dr == -1 { let d = p.r - b.r0; q.r = b.r0 + d * ca - p.z * sa; q.z = d * sa + p.z * ca }
            return q
        }
        func rotN(_ n: V3) -> V3 {   // normals rotate about the same axis (no translation)
            var q = n
            if dir.dc == 1 { q.c = n.c * ca + n.z * sa; q.z = -n.c * sa + n.z * ca }
            if dir.dc == -1 { q.c = n.c * ca - n.z * sa; q.z = n.c * sa + n.z * ca }
            if dir.dr == 1 { q.r = n.r * ca + n.z * sa; q.z = -n.r * sa + n.z * ca }
            if dir.dr == -1 { q.r = n.r * ca - n.z * sa; q.z = n.r * sa + n.z * ca }
            return q
        }
        let pts = corners.map { rot($0) }.map { pj.pt($0.c, $0.r, $0.z + dz) }
        // Faces as (corner indices a, b, c, d going round, outward normal). Index = x + 2y + 4z.
        let faces: [([Int], V3)] = [
            ([4, 5, 7, 6], V3(c: 0, r: 0, z: 1)),    // top
            ([2, 3, 7, 6], V3(c: 0, r: 1, z: 0)),    // front (+r)
            ([0, 2, 6, 4], V3(c: -1, r: 0, z: 0)),   // left (-c)
            ([1, 3, 7, 5], V3(c: 1, r: 0, z: 0)),    // right
            ([0, 1, 5, 4], V3(c: 0, r: -1, z: 0)),   // back
            ([0, 1, 3, 2], V3(c: 0, r: 0, z: -1)),   // bottom
        ]
        let view = V3(c: -0.3, r: 1, z: 0.811)            // towards the camera
        let light = V3(c: -0.34, r: 0.42, z: 0.84)
        var g = ctx
        g.opacity = alpha
        for (fi, face) in faces.enumerated() {
            let n = rotN(face.1)
            guard n.c * view.c + n.r * view.r + n.z * view.z > 0.001 else { continue }
            let q = face.0.map { pts[$0] }
            let shape = poly(q)
            var f = g
            f.clip(to: shape)
            // Map the unit square onto the face (the projection is affine, so faces are parallelograms).
            let e1 = CGVector(dx: q[1].x - q[0].x, dy: q[1].y - q[0].y)
            let e2 = CGVector(dx: q[3].x - q[0].x, dy: q[3].y - q[0].y)
            f.concatenate(CGAffineTransform(a: e1.dx, b: e1.dy, c: e2.dx, d: e2.dy, tx: q[0].x, ty: q[0].y))
            rust(f, seed: fi)
            let bright = 0.38 + 0.62 * max(0, n.c * light.c + n.r * light.r + n.z * light.z)
            g.fill(shape, with: .color(.black.opacity(0.78 * (1 - bright))))
            g.stroke(shape, with: .color(c(0.16, 0.08, 0.05)), lineWidth: max(1, pj.s * 0.025))
        }
    }

    /// Rusty metal in unit-square space: a rust-brown base mottled with orange corrosion, blue-grey
    /// bare steel and dark pitting.
    private static func rust(_ ctx: GraphicsContext, seed: Int) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: 1, height: 1)),
                 with: .linearGradient(Gradient(colors: [c(0.58, 0.3, 0.2), c(0.44, 0.22, 0.15)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 1, y: 1)))
        func h(_ a: Int, _ m: Int) -> Double {
            let n: Double = Double(a) * 12.9898 + Double(m) * 78.233 + Double(seed) * 37.719
            let v: Double = sin(n) * 43758.5453
            return v - floor(v)
        }
        for k in 0..<22 {
            let x: Double = h(37 + k, k)
            let y: Double = h(53 + k * 3, k + 5)
            let sz: Double = 0.05 + 0.12 * h(11 + k * 5, k + 9)
            let col: Color = k % 3 == 0 ? c(0.46, 0.49, 0.56) : (k % 3 == 1 ? c(0.84, 0.44, 0.16) : c(0.28, 0.13, 0.08))
            ctx.fill(Path(ellipseIn: CGRect(x: x - sz / 2, y: y - sz * 0.4, width: sz, height: sz * 0.8)),
                     with: .color(col.opacity(0.42)))
        }
        for k in 0..<40 {
            let x: Double = h(19 + k * 7, k + 2)
            let y: Double = h(7 + k * 11, k + 4)
            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 0.025, height: 0.02)),
                     with: .color((k % 2 == 0 ? c(0.95, 0.6, 0.28) : c(0.2, 0.1, 0.06)).opacity(0.6)))
        }
    }
}

/// The Bloxorz sky: a red-orange glow with dark cloud blotches (static).
private struct BloxorzSky: View, Equatable {
    var body: some View {
        Canvas { ctx, s in
            ctx.fill(Path(CGRect(origin: .zero, size: s)),
                     with: .linearGradient(Gradient(colors: [BloxArt.c(0.84, 0.24, 0.04), BloxArt.c(0.66, 0.13, 0.03), BloxArt.c(0.36, 0.05, 0.01)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height)))
            var g = ctx
            g.addFilter(.blur(radius: max(s.width, s.height) * 0.04))
            for (fx, fy, fw, fh, a) in [(0.1, 0.62, 0.7, 0.16, 0.5), (0.7, 0.75, 0.8, 0.2, 0.55), (0.3, 0.9, 0.9, 0.2, 0.6),
                                        (0.85, 0.12, 0.5, 0.14, 0.35), (0.05, 0.08, 0.4, 0.12, 0.3), (0.5, 0.45, 0.5, 0.1, 0.25)]
                    as [(CGFloat, CGFloat, CGFloat, CGFloat, Double)] {
                g.fill(Path(ellipseIn: CGRect(x: s.width * (fx - fw / 2), y: s.height * (fy - fh / 2), width: s.width * fw, height: s.height * fh)),
                       with: .color(BloxArt.c(0.16, 0.01, 0.0).opacity(a)))
            }
            ctx.fill(Path(CGRect(origin: .zero, size: s)),
                     with: .radialGradient(Gradient(colors: [BloxArt.c(1, 0.5, 0.15).opacity(0.25), .clear]),
                                           center: CGPoint(x: s.width * 0.5, y: s.height * 0.3), startRadius: 0, endRadius: s.width * 0.8))
        }
        .allowsHitTesting(false)
    }
}

/// A computer arrow key: a dark keycap that glows orange while pressed (or pressed by the demo).
private struct ArrowKeyStyle: ButtonStyle {
    let lit: Bool

    func makeBody(configuration: Configuration) -> some View {
        let on = lit || configuration.isPressed
        configuration.label
            .foregroundStyle(on ? Color(red: 0.25, green: 0.08, blue: 0) : Color(white: 0.85))
            .background {
                RoundedRectangle(cornerRadius: 9)
                    .fill(on ? LinearGradient(colors: [Color(red: 1, green: 0.78, blue: 0.4), Color(red: 1, green: 0.5, blue: 0.15)], startPoint: .top, endPoint: .bottom)
                             : LinearGradient(colors: [Color(white: 0.32), Color(white: 0.16)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(.black.opacity(0.6), lineWidth: 1))
                    .shadow(color: on ? Color(red: 1, green: 0.5, blue: 0.1).opacity(0.8) : .black.opacity(0.5),
                            radius: on ? 6 : 0, x: 0, y: on ? 0 : 3)
            }
            .scaleEffect(on ? 0.93 : 1)
            .animation(.easeOut(duration: 0.08), value: on)
    }
}
