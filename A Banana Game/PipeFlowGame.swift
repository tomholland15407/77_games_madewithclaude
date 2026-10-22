//
//  PipeFlowGame.swift
//  A Banana Game
//
//  Brain — a Pipe Mania style plumbing puzzle. TAP a pipe tile to rotate it 90°. Connect an
//  unbroken run of pipe from the SOURCE (left) to the DRAIN (right) so the banana flow reaches
//  the end before the clock runs out. Filled pipe glows yellow so you can see how far the flow
//  gets. Boards are generated with a guaranteed solution, then scrambled so they never start
//  connected. 7 levels: bigger grids, longer routes, and a tighter clock.
//
//  Drawn after Pipe Mania: bevelled stone tiles with corner screws in an iron frame on a basement
//  brick wall, thick steel pipes with flanges at the tile edges, and the connected run filled with
//  glowing banana juice. A green tank with a valve feeds the source row from outside the board and
//  a drain grate takes the drain row; the source and drain tiles wear coloured frames instead of
//  the old IN/OUT words, and the "CONNECT THE PIPE" line is gone. Stone → steel → sewer by level.
//

import SwiftUI

enum PipeFlowGame {
    static let definition = GameDefinition(
        id: "pipe-flow",
        title: "Pipe Flow",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Tap a pipe tile to rotate it.",
                "Link an unbroken line of pipe from the source on the left to the drain on the right.",
                "The connected flow glows yellow.",
                "Complete the line before the clock empties or you drop back to level 1.",
            ],
            bulletsVI: [
                "Chạm một ô ống để xoay nó.",
                "Nối một đường ống liền mạch từ nguồn bên trái đến chỗ thoát bên phải.",
                "Dòng chảy được nối sẽ phát sáng màu vàng.",
                "Hoàn thành đường ống trước khi hết giờ, nếu không bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(PipeFlowView(level: level, onWin: onWin, onFail: onFail))
        },
        prefetch: { level in PipeFlowView(level: level, onWin: {}, onFail: {}).prefetchBoard() }
    )
}

struct PipeFlowView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void
    @Environment(\.isDemo) private var isDemo

    // Difficulty shifted up: the first three levels used to be near-trivial. Bigger grids, longer
    // required routes, and a tighter clock. `minPathLen` forces a real snaking solution.
    private var gridN: Int        { [4, 4, 5, 5, 6, 6, 6][min(level, 7) - 1] }
    private var timeLimit: Double { [30, 26, 24, 20, 16, 13, 11][min(level, 7) - 1] }
    private var minPathLen: Int   { [8, 10, 13, 16, 20, 24, 28][min(level, 7) - 1] }

    // Connection bits.
    private static let N = 1, E = 2, S = 4, W = 8

    private struct Cell: Hashable { let r: Int; let c: Int }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var masks: [[Int]] = []
    @State private var source = Cell(r: 0, c: 0)
    @State private var drain = Cell(r: 0, c: 0)
    @State private var timeLeft = 0.0
    @State private var solved = false
    @State private var ready = false
    @State private var demoFinger: Cell? = nil      // demo: tile being tapped
    @State private var demoTapID = 0                // demo: bumps per tap → a fresh DemoTapRipple

    private var filled: Set<Cell> { flow() }

    var body: some View {
        Group {
            if ready {
                gameBody
            } else {
                BrainstormingView(skyTop: Color(white: 0.11), skyBottom: Color(white: 0.04))
            }
        }
        .task { isDemo ? await runDemo() : await run() }
    }

    private var gameBody: some View {
        VStack(spacing: isDemo ? 4 : 14) {
            if !isDemo { timeBar.frame(height: 6).padding(.horizontal, 48).padding(.top, 6) }

            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let n = max(1, gridN)
                let cell = min(w, h) / CGFloat(n + 1)
                let boardW = cell * CGFloat(n)
                let ox = (w - boardW) / 2
                let oy = (h - boardW) / 2
                let filledSet = filled

                ZStack {
                    // Tiles, pipes and flow, the tank feeding the source row and the drain on the far side.
                    Canvas { ctx, _ in
                        guard masks.count == n else { return }
                        let board = CGRect(x: ox, y: oy, width: boardW, height: boardW)
                        PFArt.frame(ctx, board: board, cell: cell)
                        for r in 0..<n {
                            for c in 0..<n {
                                PFArt.tile(ctx, rect: CGRect(x: ox + CGFloat(c) * cell, y: oy + CGFloat(r) * cell, width: cell, height: cell), level: level)
                            }
                        }
                        let srcY = oy + (CGFloat(source.r) + 0.5) * cell, drY = oy + (CGFloat(drain.r) + 0.5) * cell
                        PFArt.tank(ctx, at: CGPoint(x: ox, y: srcY), cell: cell)
                        PFArt.drain(ctx, at: CGPoint(x: ox + boardW, y: drY), cell: cell, flowing: solved)
                        PFArt.mark(ctx, rect: CGRect(x: ox + CGFloat(source.c) * cell, y: oy + CGFloat(source.r) * cell, width: cell, height: cell),
                                   cell: cell, color: PFArt.green)
                        PFArt.mark(ctx, rect: CGRect(x: ox + CGFloat(drain.c) * cell, y: oy + CGFloat(drain.r) * cell, width: cell, height: cell),
                                   cell: cell, color: solved ? PFArt.juice : Color(red: 0.95, green: 0.35, blue: 0.3))
                        for r in 0..<n {
                            for c in 0..<n {
                                let center = CGPoint(x: ox + (CGFloat(c) + 0.5) * cell, y: oy + (CGFloat(r) + 0.5) * cell)
                                PFArt.pipe(ctx, mask: masks[r][c], center: center, cell: cell, full: filledSet.contains(Cell(r: r, c: c)),
                                           n: Self.N, e: Self.E, s: Self.S, w: Self.W)
                            }
                        }
                    }

                    // Demo: the tapped tile — a ripple under a finger.
                    if let f = demoFinger {
                        let cx = ox + (CGFloat(f.c) + 0.5) * cell, cy = oy + (CGFloat(f.r) + 0.5) * cell
                        DemoTapRipple().id(demoTapID).position(x: cx, y: cy)
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.system(size: cell * 0.42))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 3)
                            .position(x: cx + cell * 0.28, y: cy + cell * 0.34)
                            .allowsHitTesting(false)
                    }

                    // Tap layer.
                    ForEach(0..<n, id: \.self) { r in
                        ForEach(0..<n, id: \.self) { c in
                            Color.clear
                                .contentShape(Rectangle())
                                .frame(width: cell, height: cell)
                                .position(x: ox + (CGFloat(c) + 0.5) * cell, y: oy + (CGFloat(r) + 0.5) * cell)
                                .onTapGesture { rotate(r, c) }
                        }
                    }
                }
            }
            .padding(.horizontal, isDemo ? 10 : 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PFBrickWall(level: level).equatable())
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.35))
                Capsule().fill(frac < 0.3 ? Color(red: 1, green: 0.32, blue: 0.26) : PFArt.juice)
                    .frame(width: geo.size.width * frac)
            }
        }
    }

    // MARK: - Flow
    /// Hands this level's board build to `BoardCache` so it can run during the countdown.
    func prefetchBoard() {
        let (n, minLen) = (gridN, minPathLen)
        BoardCache.prefetch(boardKey) { Self.generate(n: n, minPathLen: minLen) }
    }
    private var boardKey: String { BoardCache.key("pipe-flow", level: level) }

    private func run() async {
        // Generate off the main actor (longer required routes mean more tries), showing the
        // "brainstorming" banana while it works, then commit and start the clock.
        let (n, minLen) = (gridN, minPathLen)
        let t0 = Date()
        let board = await BoardCache.take(boardKey) { Self.generate(n: n, minPathLen: minLen) }
        guard !Task.isCancelled else { return }
        await BoardCache.holdBrainstorm(since: t0, minimum: 0.7)
        guard !Task.isCancelled else { return }
        masks = board.masks; source = board.source; drain = board.drain
        solved = false
        ready = true
        phase = .play
        timeLeft = timeLimit
        let start = Date()
        while !Task.isCancelled && phase == .play {
            try? await Task.sleep(for: .seconds(0.05))
            timeLeft = max(0, timeLimit - Date().timeIntervalSince(start))
            if timeLeft <= 0 { fail() }
        }
    }

    // MARK: - Demo (live manual clip)
    // A fixed level-1 board (4×4) whose route snakes 10 tiles — past L1's 8-tile minimum — from IN
    // (row 2, left) up, over, down and back to OUT (row 2, right), with every tile scrambled and
    // decoy pipes in the gaps. The demo turns the route's tiles in flow order through the real
    // `rotate` (13 taps, each tile only as far as it needs), so the yellow flow visibly creeps
    // along; checked offline that it can't connect early — the last tap is the real win().
    //   route: (2,0) (2,1) (1,1) (0,1) (0,2) (1,2) (2,2) (3,2) (3,3) (2,3)
    private static let demoMasks: [[Int]] = [[6, 3, 3, 5], [12, 10, 10, 6], [1, 12, 10, 2], [9, 9, 6, 12]]
    private static let demoTaps: [(Int, Int)] = [(2, 0), (2, 1), (1, 1), (0, 1), (0, 2), (0, 2), (1, 2),
                                                 (2, 2), (3, 2), (3, 2), (3, 2), (3, 3), (2, 3)]

    private func runDemo() async {
        while !Task.isCancelled {
            masks = Self.demoMasks
            source = Cell(r: 2, c: 0); drain = Cell(r: 2, c: 3)
            solved = false; demoFinger = nil
            timeLeft = timeLimit
            phase = .play
            ready = true
            try? await Task.sleep(for: .seconds(0.8))
            for (r, c) in Self.demoTaps {
                guard !Task.isCancelled else { return }
                let cell = Cell(r: r, c: c)
                if demoFinger != cell {
                    demoFinger = cell
                    try? await Task.sleep(for: .seconds(0.18))
                }
                demoTapID += 1
                rotate(r, c)
                try? await Task.sleep(for: .seconds(0.26))
            }
            demoFinger = nil
            // OUT is flowing → the real win() ran (onWin is a no-op). Hold, then loop.
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    private func rotate(_ r: Int, _ c: Int) {
        guard phase == .play, r < masks.count, c < masks[r].count else { return }
        masks[r][c] = Self.rotateCW(masks[r][c])
        SoundManager.shared.tap(); Haptics.tap()
        if flow().contains(drain) { solved = true; win() }
    }

    private nonisolated static func rotateCW(_ m: Int) -> Int { ((m << 1) | (m >> 3)) & 15 }

    // MARK: - Generation (pure / off-main)

    /// Try many random boards; return the first whose solution path is at least `minPathLen`
    /// tiles, else the longest-path board we saw (so a high minPathLen never yields a short one).
    /// Every returned board is guaranteed solvable and NOT already connected.
    private nonisolated static func generate(n: Int, minPathLen: Int) -> (masks: [[Int]], source: Cell, drain: Cell) {
        var best: (masks: [[Int]], source: Cell, drain: Cell)? = nil
        var bestLen = -1
        for _ in 0..<200 {
            let source = Cell(r: Int.random(in: 0..<n), c: 0)
            let drain = Cell(r: Int.random(in: 0..<n), c: n - 1)
            guard let path = carvePath(from: source, to: drain, n: n) else { continue }

            var m = Array(repeating: Array(repeating: 0, count: n), count: n)
            // Lay the solution connections along the path.
            for i in 0..<(path.count - 1) {
                let a = path[i], b = path[i + 1]
                if b.r == a.r - 1 { m[a.r][a.c] |= N; m[b.r][b.c] |= S }
                if b.r == a.r + 1 { m[a.r][a.c] |= S; m[b.r][b.c] |= N }
                if b.c == a.c + 1 { m[a.r][a.c] |= E; m[b.r][b.c] |= W }
                if b.c == a.c - 1 { m[a.r][a.c] |= W; m[b.r][b.c] |= E }
            }
            // Decoy pipes on empty cells so the board looks full.
            let decoys = [N | S, E | W, N | E, S | W, N | W, S | E]
            for r in 0..<n { for c in 0..<n where m[r][c] == 0 {
                m[r][c] = decoys.randomElement()!
            }}
            // Scramble every tile so it doesn't start solved.
            for r in 0..<n { for c in 0..<n {
                for _ in 0..<Int.random(in: 0...3) { m[r][c] = rotateCW(m[r][c]) }
            }}
            // Guarantee it's not already connected.
            var guardCount = 0
            while flows(masks: m, source: source, n: n).contains(drain) && guardCount < 20 {
                guardCount += 1
                let pc = path[Int.random(in: 0..<path.count)]
                m[pc.r][pc.c] = rotateCW(m[pc.r][pc.c])
            }
            if flows(masks: m, source: source, n: n).contains(drain) { continue }   // still solved
            let board = (masks: m, source: source, drain: drain)
            if path.count >= minPathLen { return board }
            if path.count > bestLen { bestLen = path.count; best = board }
        }
        if let best { return best }
        // Deterministic last resort: a straight row-0 line, broken at the source so it starts unsolved.
        var m = Array(repeating: Array(repeating: E | W, count: n), count: n)
        m[0][0] = N
        return (masks: m, source: Cell(r: 0, c: 0), drain: Cell(r: 0, c: n - 1))
    }

    /// Randomized DFS carving a self-avoiding path from source to drain.
    private nonisolated static func carvePath(from: Cell, to: Cell, n: Int) -> [Cell]? {
        var visited: Set<Cell> = [from]
        var path: [Cell] = [from]
        func dfs(_ cur: Cell) -> Bool {
            if cur == to { return true }
            let dirs = [(-1, 0), (1, 0), (0, -1), (0, 1)].shuffled()
            for (dr, dc) in dirs {
                let nx = Cell(r: cur.r + dr, c: cur.c + dc)
                guard nx.r >= 0, nx.r < n, nx.c >= 0, nx.c < n, !visited.contains(nx) else { continue }
                visited.insert(nx); path.append(nx)
                if dfs(nx) { return true }
                path.removeLast(); visited.remove(nx)
            }
            return false
        }
        return dfs(from) ? path : nil
    }

    // MARK: - Connectivity (flow from source)
    private func flow() -> Set<Cell> {
        guard masks.count == gridN else { return [] }
        return Self.flows(masks: masks, source: source, n: gridN)
    }

    private nonisolated static func flows(masks: [[Int]], source: Cell, n: Int) -> Set<Cell> {
        var reached: Set<Cell> = [source]
        var stack = [source]
        while let cur = stack.popLast() {
            let m = masks[cur.r][cur.c]
            let checks: [(Int, Int, Int, Int)] = [
                (N, -1, 0, S), (S, 1, 0, N),
                (E, 0, 1, W),  (W, 0, -1, E)
            ]
            for (bit, dr, dc, opp) in checks where m & bit != 0 {
                let nx = Cell(r: cur.r + dr, c: cur.c + dc)
                guard nx.r >= 0, nx.r < n, nx.c >= 0, nx.c < n, !reached.contains(nx) else { continue }
                if masks[nx.r][nx.c] & opp != 0 { reached.insert(nx); stack.append(nx) }
            }
        }
        return reached
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
        SoundManager.shared.error()
        onFail()
    }
}

// MARK: - Plumbing art (after Pipe Mania)

private enum PFArt {
    static let juice = Color(red: 1, green: 0.84, blue: 0.2)
    static let green = Color(red: 0.3, green: 0.82, blue: 0.4)
    static let steel = Color(red: 0.66, green: 0.7, blue: 0.76)

    /// Stone tiles (1–3), blue steel plates (4–5), a dark sewer (6–7).
    static func tileColor(_ level: Int) -> Color {
        level >= 6 ? Color(red: 0.3, green: 0.3, blue: 0.26) : level >= 4 ? Color(red: 0.38, green: 0.46, blue: 0.56) : Color(red: 0.72, green: 0.64, blue: 0.5)
    }

    /// The board's dark iron frame.
    static func frame(_ ctx: GraphicsContext, board: CGRect, cell: CGFloat) {
        let outer = board.insetBy(dx: -cell * 0.14, dy: -cell * 0.14)
        ctx.fill(Path(roundedRect: outer, cornerRadius: cell * 0.12), with: .color(Color(white: 0.12)))
        ctx.stroke(Path(roundedRect: outer.insetBy(dx: 2, dy: 2), cornerRadius: cell * 0.1), with: .color(.white.opacity(0.12)), lineWidth: 1.5)
    }

    /// A bevelled tile with a screw in each corner.
    static func tile(_ ctx: GraphicsContext, rect r: CGRect, level: Int) {
        let base = tileColor(level)
        let t = r.insetBy(dx: r.width * 0.025, dy: r.width * 0.025)
        ctx.fill(Path(t), with: .color(base))
        let b = r.width * 0.07
        var lit = Path()
        lit.move(to: CGPoint(x: t.minX, y: t.maxY)); lit.addLine(to: CGPoint(x: t.minX, y: t.minY)); lit.addLine(to: CGPoint(x: t.maxX, y: t.minY))
        lit.addLine(to: CGPoint(x: t.maxX - b, y: t.minY + b)); lit.addLine(to: CGPoint(x: t.minX + b, y: t.minY + b)); lit.addLine(to: CGPoint(x: t.minX + b, y: t.maxY - b)); lit.closeSubpath()
        ctx.fill(lit, with: .color(.white.opacity(0.2)))
        var dark = Path()
        dark.move(to: CGPoint(x: t.maxX, y: t.minY)); dark.addLine(to: CGPoint(x: t.maxX, y: t.maxY)); dark.addLine(to: CGPoint(x: t.minX, y: t.maxY))
        dark.addLine(to: CGPoint(x: t.minX + b, y: t.maxY - b)); dark.addLine(to: CGPoint(x: t.maxX - b, y: t.maxY - b)); dark.addLine(to: CGPoint(x: t.maxX - b, y: t.minY + b)); dark.closeSubpath()
        ctx.fill(dark, with: .color(.black.opacity(0.25)))
        var screws = Path()
        for (dx, dy) in [(0.15, 0.15), (0.85, 0.15), (0.15, 0.85), (0.85, 0.85)] as [(CGFloat, CGFloat)] {
            screws.addEllipse(in: CGRect(x: t.minX + t.width * dx - r.width * 0.035, y: t.minY + t.height * dy - r.width * 0.035, width: r.width * 0.07, height: r.width * 0.07))
        }
        ctx.fill(screws, with: .color(.black.opacity(0.3)))
    }

    /// A thin coloured frame around the source (green) or drain tile.
    static func mark(_ ctx: GraphicsContext, rect: CGRect, cell: CGFloat, color: Color) {
        ctx.stroke(Path(roundedRect: rect.insetBy(dx: cell * 0.06, dy: cell * 0.06), cornerRadius: cell * 0.08), with: .color(color), lineWidth: max(2, cell * 0.06))
    }

    /// One tile's pipe: steel arms out to the tile edges with a flange at each, a round joint in the
    /// middle, and — when the flow has reached it — glowing banana juice inside.
    static func pipe(_ ctx: GraphicsContext, mask m: Int, center: CGPoint, cell: CGFloat, full: Bool, n: Int, e: Int, s: Int, w: Int) {
        var arms = Path()
        var flanges = Path()
        let reach = cell * 0.5
        for (bit, dx, dy) in [(n, 0.0, -1.0), (s, 0.0, 1.0), (e, 1.0, 0.0), (w, -1.0, 0.0)] as [(Int, CGFloat, CGFloat)] where m & bit != 0 {
            arms.move(to: center); arms.addLine(to: CGPoint(x: center.x + dx * reach, y: center.y + dy * reach))
            let fx = center.x + dx * cell * 0.42, fy = center.y + dy * cell * 0.42
            let hw = cell * 0.2, ht = cell * 0.05
            flanges.addRect(dx == 0 ? CGRect(x: fx - hw, y: fy - ht, width: hw * 2, height: ht * 2) : CGRect(x: fx - ht, y: fy - hw, width: ht * 2, height: hw * 2))
        }
        let joint = Path(ellipseIn: CGRect(x: center.x - cell * 0.19, y: center.y - cell * 0.19, width: cell * 0.38, height: cell * 0.38))
        let ink = Color(white: 0.12)
        ctx.stroke(arms, with: .color(ink), style: StrokeStyle(lineWidth: cell * 0.34, lineCap: .butt))
        ctx.fill(joint.applying(CGAffineTransform(translationX: 0, y: 0)), with: .color(ink))
        ctx.fill(flanges, with: .color(ink))
        ctx.stroke(arms, with: .color(steel), style: StrokeStyle(lineWidth: cell * 0.26, lineCap: .butt))
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - cell * 0.16, y: center.y - cell * 0.16, width: cell * 0.32, height: cell * 0.32)), with: .color(steel))
        ctx.fill(flanges.applying(CGAffineTransform.identity), with: .color(steel.mix(with: .black, by: 0.2)))
        ctx.stroke(arms, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: cell * 0.06, lineCap: .butt))
        if full {
            ctx.stroke(arms, with: .color(juice.opacity(0.45)), style: StrokeStyle(lineWidth: cell * 0.22, lineCap: .round))
            ctx.stroke(arms, with: .color(juice), style: StrokeStyle(lineWidth: cell * 0.14, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - cell * 0.11, y: center.y - cell * 0.11, width: cell * 0.22, height: cell * 0.22)), with: .color(juice))
            ctx.stroke(arms, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: cell * 0.04, lineCap: .round))
        }
    }

    /// The supply tank outside the board, piped in at the source row.
    static func tank(_ ctx: GraphicsContext, at p: CGPoint, cell: CGFloat) {
        var feed = Path()
        feed.move(to: CGPoint(x: p.x - cell * 0.3, y: p.y)); feed.addLine(to: CGPoint(x: p.x + 1, y: p.y))
        ctx.stroke(feed, with: .color(Color(white: 0.12)), lineWidth: cell * 0.34)
        ctx.stroke(feed, with: .color(juice), lineWidth: cell * 0.2)
        let body = CGRect(x: p.x - cell * 0.46, y: p.y - cell * 0.3, width: cell * 0.26, height: cell * 0.6)
        ctx.fill(Path(roundedRect: body, cornerRadius: cell * 0.12), with: .linearGradient(Gradient(colors: [green.mix(with: .white, by: 0.3), green, green.mix(with: .black, by: 0.35)]),
                                                                                           startPoint: CGPoint(x: body.minX, y: 0), endPoint: CGPoint(x: body.maxX, y: 0)))
        ctx.stroke(Path(roundedRect: body, cornerRadius: cell * 0.12), with: .color(Color(white: 0.1)), lineWidth: max(1, cell * 0.035))
        let wheel = CGPoint(x: body.midX, y: body.minY - cell * 0.02)
        ctx.stroke(Path(ellipseIn: CGRect(x: wheel.x - cell * 0.12, y: wheel.y - cell * 0.12, width: cell * 0.24, height: cell * 0.24)), with: .color(Color(red: 0.85, green: 0.2, blue: 0.18)), lineWidth: max(1.5, cell * 0.05))
    }

    /// The drain outside the board at the drain row; juice pours in once connected.
    static func drain(_ ctx: GraphicsContext, at p: CGPoint, cell: CGFloat, flowing: Bool) {
        var out = Path()
        out.move(to: CGPoint(x: p.x - 1, y: p.y)); out.addLine(to: CGPoint(x: p.x + cell * 0.36, y: p.y))
        ctx.stroke(out, with: .color(Color(white: 0.12)), lineWidth: cell * 0.34)
        ctx.stroke(out, with: .color(flowing ? juice : Color(white: 0.3)), lineWidth: cell * 0.2)
        let grate = CGRect(x: p.x + cell * 0.3, y: p.y - cell * 0.26, width: cell * 0.16, height: cell * 0.52)
        ctx.fill(Path(roundedRect: grate, cornerRadius: cell * 0.04), with: .color(Color(white: 0.2)))
        var bars = Path()
        for k in 1...3 {
            let y = grate.minY + grate.height * CGFloat(k) / 4
            bars.move(to: CGPoint(x: grate.minX + 2, y: y)); bars.addLine(to: CGPoint(x: grate.maxX - 2, y: y))
        }
        ctx.stroke(bars, with: .color(flowing ? juice : Color(white: 0.45)), lineWidth: 1.5)
    }
}

/// A basement brick wall behind the board.
private struct PFBrickWall: View, Equatable {
    let level: Int

    var body: some View {
        Canvas { ctx, size in
            let base = level >= 6 ? Color(red: 0.2, green: 0.18, blue: 0.16) : level >= 4 ? Color(red: 0.2, green: 0.22, blue: 0.28) : Color(red: 0.36, green: 0.2, blue: 0.14)
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
            var mortar = Path()
            let bh: CGFloat = 16, bw: CGFloat = 36
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                mortar.move(to: CGPoint(x: 0, y: y)); mortar.addLine(to: CGPoint(x: size.width, y: y))
                var x: CGFloat = row % 2 == 0 ? 0 : bw / 2
                while x < size.width {
                    mortar.move(to: CGPoint(x: x, y: y)); mortar.addLine(to: CGPoint(x: x, y: y + bh))
                    x += bw
                }
                y += bh; row += 1
            }
            ctx.stroke(mortar, with: .color(.black.opacity(0.3)), lineWidth: 2)
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.55)]), center: CGPoint(x: size.width / 2, y: size.height / 2),
                                           startRadius: min(size.width, size.height) * 0.3, endRadius: max(size.width, size.height) * 0.7))
        }
    }
}
