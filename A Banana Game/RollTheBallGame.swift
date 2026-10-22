//
//  RollTheBallGame.swift
//  A Banana Game
//
//  Brain — Roll the Ball. Slide the pipe tiles around the single empty space to build one unbroken
//  track from the ball to the goal; the moment the pipe connects end to end, the ball rolls and you
//  win. Tap any tile next to the gap to slide it in (no dragging — it stays out of the feed's way).
//  The ball and goal tiles are fixed, and some levels add fixed blockers that jam up the sliding.
//  Run out of time and you're back to level 1.
//
//  Boards start from a fully connected solution, then scramble by making random legal slides — so
//  every puzzle is guaranteed solvable and is checked to be broken (never pre-solved) before it's
//  dealt. Generation runs off-main behind the brainstorming banana. Levels grow the grid and add
//  blockers so the sliding gets tighter and the route longer.
//

import SwiftUI

private nonisolated struct RCell: Hashable, Sendable { let r: Int; let c: Int }

private enum RKind: Sendable { case pipe, source, goal, blocker }

private nonisolated struct RTile: Sendable, Equatable {
    var openings: Int   // bitmask N=1,E=2,S=4,W=8
    var fixed: Bool
    var kind: RKind
}

private nonisolated struct RollPuzzle: Sendable {
    let n: Int
    let board: [[RTile?]]
    let source: RCell
    let goal: RCell
}

enum RollTheBallGame {
    static let definition = GameDefinition(
        id: "roll-the-ball",
        title: "Groove Slider",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Tap a pipe tile next to the empty space to slide it into the gap.",
                "Rearrange the tiles into one unbroken track from the ball to the goal.",
                "Connect them and the ball rolls home; the ball and goal tiles can't move.",
                "Run out of time and you're back to level 1.",
            ],
            bulletsVI: [
                "Chạm một ô ống cạnh ô trống để trượt nó vào khe.",
                "Sắp lại các ô thành một đường ống liền mạch từ quả bóng đến đích.",
                "Nối được thì bóng lăn về; ô bóng và ô đích không di chuyển được.",
                "Hết giờ sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(RollTheBallView(level: level, onWin: onWin, onFail: onFail))
        },
        prefetch: { level in RollTheBallView(level: level, onWin: {}, onFail: {}).prefetchBoard() }
    )
}

struct RollTheBallView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    private var gridN: Int { [3, 3, 4, 4, 5, 5, 5][min(level, 7) - 1] }
    private var blockerCount: Int { [0, 0, 0, 1, 1, 2, 3][min(level, 7) - 1] }
    private var timeLimit: Double { [45, 55, 70, 85, 100, 110, 120][min(level, 7) - 1] }

    private var skyTop: Color { Color(red: 0.42, green: 0.26, blue: 0.14) }
    private var skyBottom: Color { Color(red: 0.2, green: 0.11, blue: 0.05) }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var ready = false
    @State private var n = 0
    @State private var board: [[RTile?]] = []
    @State private var source = RCell(r: 0, c: 0)
    @State private var goal = RCell(r: 0, c: 0)
    @State private var gap = RCell(r: 0, c: 0)
    @State private var timeLeft = 0.0
    @State private var loopTask: Task<Void, Never>?
    @State private var flowPath: [RCell] = []   // source→goal cells, lit up on win
    @State private var flowIndex = 0.0          // how far the light has traveled
    @State private var demoTap: RCell? = nil    // tile the demo is "tapping" (highlighted + finger)
    @State private var moves = 0                // presentation only: slides made (the original's Move count)

    private static let dirs: [(bit: Int, dr: Int, dc: Int)] = [(1, -1, 0), (2, 0, 1), (4, 1, 0), (8, 0, -1)]
    private static func opposite(_ bit: Int) -> Int {
        switch bit { case 1: return 4; case 4: return 1; case 2: return 8; default: return 2 }
    }

    private var connected: Set<RCell> {
        Self.connectedFromSource(board: board, n: n, source: source)
    }

    var body: some View {
        Group {
            if ready { gameBody } else { BrainstormingView(skyTop: skyTop, skyBottom: skyBottom) }
        }
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
    }

    private var gameBody: some View {
        VStack(spacing: isDemo ? 6 : 10) {
            // A wooden plaque with the move count (the original's Move counter).
            HStack(spacing: 8) {
                Text(L("MOVES", "BƯỚC"))
                    .font(.system(size: isDemo ? 12 : 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 1, green: 0.88, blue: 0.62).opacity(0.8))
                Text("\(moves)")
                    .font(.system(size: isDemo ? 18 : 24, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 1, green: 0.93, blue: 0.75))
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 18)
            .padding(.vertical, isDemo ? 3 : 6)
            .background(RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [RollArt.woodDark.lit(0.12), RollArt.woodDark],
                                                                                startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.black.opacity(0.45), lineWidth: 1.5))
            if !isDemo { timeBar.frame(height: 5).padding(.horizontal, 60) }
            boardView
        }
        .padding(.top, isDemo ? 8 : 12)
        .padding(.bottom, isDemo ? 8 : 12)
        .background(RollBackdrop().equatable())
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var boardView: some View {
        GeometryReader { geo in
            let gw = geo.size.width, gh = geo.size.height
            let cell = n > 0 ? min(gw * 0.92 / CGFloat(n), gh * 0.92 / CGFloat(n)) : 0
            let ox = (gw - cell * CGFloat(n)) / 2
            let oy = (gh - cell * CGFloat(n)) / 2
            let conn = connected
            ZStack {
                tileCanvas(cell: cell, ox: ox, oy: oy, conn: conn)
                tapLayer(cell: cell, ox: ox, oy: oy)
            }
            .frame(width: gw, height: gh)
        }
    }

    private func tileCanvas(cell: CGFloat, ox: CGFloat, oy: CGFloat, conn: Set<RCell>) -> some View {
        Canvas { ctx, _ in
            guard n > 0, board.count == n else { return }
            RollArt.frame(ctx, CGRect(x: ox, y: oy, width: cell * CGFloat(n), height: cell * CGFloat(n)), cell: cell)
            for r in 0..<n { for c in 0..<n {
                let rect = CGRect(x: ox + CGFloat(c) * cell, y: oy + CGFloat(r) * cell, width: cell, height: cell)
                guard let tile = board[r][c] else { continue }
                let here = RCell(r: r, c: c)
                // The ball waits on the source tile until the track connects and it rolls away.
                let ballHome = tile.kind == .source && flowPath.count < 2
                RollArt.tile(ctx, rect, tile: tile, lit: conn.contains(here), ball: ballHome, seed: r * 7 + c * 13)
            }}
            // The rolling ball.
            if flowPath.count > 1 {
                func ctr(_ p: RCell) -> CGPoint {
                    CGPoint(x: ox + (CGFloat(p.c) + 0.5) * cell, y: oy + (CGFloat(p.r) + 0.5) * cell)
                }
                let upto = min(Int(flowIndex.rounded(.down)), flowPath.count - 1)
                let i0 = min(upto, flowPath.count - 1)
                let i1 = min(i0 + 1, flowPath.count - 1)
                let frac = flowIndex - Double(i0)
                let a = ctr(flowPath[i0]), b = ctr(flowPath[i1])
                RollArt.ball(ctx, at: CGPoint(x: a.x + (b.x - a.x) * frac, y: a.y + (b.y - a.y) * frac), r: cell * 0.2)
            }
        }
    }

    private func tapLayer(cell: CGFloat, ox: CGFloat, oy: CGFloat) -> some View {
        ForEach(0..<max(n, 0), id: \.self) { r in
            ForEach(0..<max(n, 0), id: \.self) { c in
                let cc = RCell(r: r, c: c)
                let slidable = isAdjacentToGap(cc) && (board[r][c]?.fixed == false)
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .frame(width: cell, height: cell)
                    .overlay(
                        slidable ? RoundedRectangle(cornerRadius: cell * 0.1).stroke(.white.opacity(0.55), lineWidth: 2)
                            .padding(cell * 0.05) : nil
                    )
                    .overlay { if demoTap == cc { demoPress(cell: cell) } }
                    .position(x: ox + (CGFloat(c) + 0.5) * cell, y: oy + (CGFloat(r) + 0.5) * cell)
                    .onTapGesture { slide(cc) }
            }
        }
    }

    /// Demo-only "press" on a tile: a white ring, a shrink, and a pointing finger.
    private func demoPress(cell: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cell * 0.1).fill(.white.opacity(0.18))
            RoundedRectangle(cornerRadius: cell * 0.1).stroke(.white, lineWidth: 3)
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: cell * 0.36))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 3)
                .offset(x: cell * 0.22, y: cell * 0.26)
        }
        .padding(cell * 0.05)
        .scaleEffect(0.9)
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.35))
                Capsule().fill(frac < 0.3 ? .red : BananaTheme.banana)
                    .frame(width: geo.size.width * frac)
            }
        }
    }
    // MARK: - Input
    private func isAdjacentToGap(_ c: RCell) -> Bool {
        (abs(c.r - gap.r) == 1 && c.c == gap.c) || (abs(c.c - gap.c) == 1 && c.r == gap.r)
    }

    private func slide(_ c: RCell) {
        guard phase == .play, isAdjacentToGap(c) else { return }
        guard let tile = board[c.r][c.c], !tile.fixed else { return }
        board[gap.r][gap.c] = tile
        board[c.r][c.c] = nil
        gap = c
        moves += 1
        SoundManager.shared.tap(); Haptics.tap()
        if connected.contains(goal) { rollBall() }
    }

    /// The pipe is connected — send the ball (a traveling light) from source to goal, then win.
    private func rollBall() {
        guard phase == .play else { return }
        let path = Self.orderedPath(board: board, n: n, source: source, goal: goal)
        guard path.count > 1 else { win(); return }
        phase = .done; loopTask?.cancel()
        flowPath = path
        flowIndex = 0
        SoundManager.shared.tap()
        Task {
            let total = 0.75
            let start = Date()
            while true {
                let e = Date().timeIntervalSince(start)
                if e >= total { break }
                flowIndex = (e / total) * Double(path.count - 1)
                try? await Task.sleep(for: .seconds(0.016))
            }
            flowIndex = Double(path.count - 1)
            Haptics.success()
            try? await Task.sleep(for: .seconds(0.12))
            onWin()
        }
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
        let g = gridN, b = blockerCount, lvl = level
        BoardCache.prefetch(boardKey) { Self.makePuzzle(n: g, blockers: b, level: lvl) }
    }
    private var boardKey: String { BoardCache.key("roll-the-ball", level: level) }

    private func run() async {
        let g = gridN, b = blockerCount, lvl = level
        let t0 = Date()
        let puzzle = await BoardCache.take(boardKey) { Self.makePuzzle(n: g, blockers: b, level: lvl) }
        guard !Task.isCancelled else { return }
        await BoardCache.holdBrainstorm(since: t0, minimum: 0.7)
        guard !Task.isCancelled else { return }
        n = puzzle.n; board = puzzle.board; source = puzzle.source; goal = puzzle.goal
        for r in 0..<n { for c in 0..<n where puzzle.board[r][c] == nil { gap = RCell(r: r, c: c) } }
        moves = 0
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

    // MARK: - Demo (live manual clip)
    // A fixed 3×3 Level-1 board: solved track src(0,0)↓ → (1,0) → (1,1) → (1,2) → goal(2,2),
    // scrambled by five legal slides. The demo replays the five inverse slides through the
    // real `slide()`, so the pipe only connects on the last tap and the real ball rolls home.
    private static let demoScramble = [RCell(r: 1, c: 1), RCell(r: 1, c: 2), RCell(r: 0, c: 2),
                                       RCell(r: 0, c: 1), RCell(r: 1, c: 1)]
    private static let demoSolution = [RCell(r: 0, c: 1), RCell(r: 0, c: 2), RCell(r: 1, c: 2),
                                       RCell(r: 1, c: 1), RCell(r: 2, c: 1)]

    private func demoSetup() {
        func pipe(_ m: Int) -> RTile { RTile(openings: m, fixed: false, kind: .pipe) }
        var b: [[RTile?]] = [
            [RTile(openings: 4, fixed: true, kind: .source), pipe(5), pipe(6)],
            [pipe(3), pipe(10), pipe(12)],
            [pipe(9), nil, RTile(openings: 1, fixed: true, kind: .goal)],
        ]
        var g = RCell(r: 2, c: 1)
        for t in Self.demoScramble {           // apply the scramble (tile t slides into the gap)
            b[g.r][g.c] = b[t.r][t.c]; b[t.r][t.c] = nil; g = t
        }
        n = 3; board = b; gap = g
        source = RCell(r: 0, c: 0); goal = RCell(r: 2, c: 2)
        flowPath = []; flowIndex = 0; demoTap = nil; moves = 0
        timeLeft = timeLimit
        phase = .play
        ready = true
    }

    private func runDemo() async {
        while !Task.isCancelled {
            demoSetup()
            try? await Task.sleep(for: .seconds(0.7))
            for cell in Self.demoSolution {
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.12)) { demoTap = cell }
                try? await Task.sleep(for: .seconds(0.35))
                guard !Task.isCancelled else { return }
                slide(cell)
                try? await Task.sleep(for: .seconds(0.2))
                withAnimation(.easeOut(duration: 0.12)) { demoTap = nil }
                try? await Task.sleep(for: .seconds(0.3))
            }
            // The last slide connected the pipe → the real ball roll ran (onWin is a no-op).
            try? await Task.sleep(for: .seconds(0.9 + 1.3))
        }
    }

    // MARK: - Connectivity (pure)
    private nonisolated static func connectedFromSource(board: [[RTile?]], n: Int, source: RCell) -> Set<RCell> {
        guard n > 0, source.r < board.count, board[source.r][source.c] != nil else { return [] }
        var seen: Set<RCell> = [source]
        var stack = [source]
        while let cur = stack.popLast() {
            guard let t = board[cur.r][cur.c] else { continue }
            for d in dirs where t.openings & d.bit != 0 {
                let nr = cur.r + d.dr, nc = cur.c + d.dc
                guard nr >= 0, nr < n, nc >= 0, nc < n else { continue }
                let nb = RCell(r: nr, c: nc)
                guard let nt = board[nr][nc], nt.openings & opposite(d.bit) != 0 else { continue }
                if !seen.contains(nb) { seen.insert(nb); stack.append(nb) }
            }
        }
        return seen
    }

    /// Ordered source→goal cells through connected, mutually-open pipes (for the light animation).
    private nonisolated static func orderedPath(board: [[RTile?]], n: Int, source: RCell, goal: RCell) -> [RCell] {
        guard n > 0, board[source.r][source.c] != nil else { return [] }
        var parent: [RCell: RCell] = [:]
        var seen: Set<RCell> = [source]
        var queue = [source]; var head = 0
        while head < queue.count {
            let cur = queue[head]; head += 1
            if cur == goal { break }
            guard let t = board[cur.r][cur.c] else { continue }
            for d in dirs where t.openings & d.bit != 0 {
                let nr = cur.r + d.dr, nc = cur.c + d.dc
                guard nr >= 0, nr < n, nc >= 0, nc < n else { continue }
                let nb = RCell(r: nr, c: nc)
                guard let nt = board[nr][nc], nt.openings & opposite(d.bit) != 0, !seen.contains(nb) else { continue }
                seen.insert(nb); parent[nb] = cur; queue.append(nb)
            }
        }
        guard seen.contains(goal) else { return [] }
        var path = [goal]; var cur = goal
        while cur != source { guard let p = parent[cur] else { return [] }; path.append(p); cur = p }
        return path.reversed()
    }

    // MARK: - Generation (solve-then-scramble / off-main)
    private nonisolated static func makePuzzle(n: Int, blockers: Int, level: Int) -> RollPuzzle {
        for _ in 0..<80 {
            if let solved = buildSolved(n: n, blockers: blockers) {
                let scrambled = scramble(solved, moves: n * n * 4 + level * 10)
                // Ensure not already solved.
                if !connectedFromSource(board: scrambled.board, n: n, source: scrambled.source).contains(scrambled.goal) {
                    return scrambled
                }
            }
        }
        return buildSolved(n: n, blockers: 0) ?? trivial(n: n)
    }

    private nonisolated static func dirBit(from a: RCell, to b: RCell) -> Int {
        if b.r == a.r - 1 { return 1 }
        if b.r == a.r + 1 { return 4 }
        if b.c == a.c + 1 { return 2 }
        return 8
    }

    private nonisolated static func buildSolved(n: Int, blockers: Int) -> RollPuzzle? {
        var all: [RCell] = []
        for r in 0..<n { for c in 0..<n { all.append(RCell(r: r, c: c)) } }
        let source = all.randomElement()!
        var goal = all.randomElement()!
        var g = 0
        while goal == source && g < 50 { goal = all.randomElement()!; g += 1 }
        guard goal != source, let path = findPath(source: source, goal: goal, n: n) else { return nil }
        // Need room for a gap and the blockers among non-path cells.
        let free = n * n - path.count
        guard free >= blockers + 1 else { return nil }

        var board = [[RTile?]](repeating: [RTile?](repeating: nil, count: n), count: n)
        for (i, cell) in path.enumerated() {
            var openings = 0
            if i > 0 { openings |= dirBit(from: cell, to: path[i - 1]) }
            if i < path.count - 1 { openings |= dirBit(from: cell, to: path[i + 1]) }
            let kind: RKind = i == 0 ? .source : (i == path.count - 1 ? .goal : .pipe)
            board[cell.r][cell.c] = RTile(openings: openings, fixed: kind != .pipe, kind: kind)
        }
        // Fill non-path cells: blockers (fixed), decoy pipes (movable), and exactly one gap.
        var nonPath = all.filter { cell in board[cell.r][cell.c] == nil }.shuffled()
        for _ in 0..<blockers {
            let b = nonPath.removeLast()
            board[b.r][b.c] = RTile(openings: 0, fixed: true, kind: .blocker)
        }
        let gapCell = nonPath.removeLast()   // stays nil = the gap
        _ = gapCell
        let decoyMasks = [5, 10, 3, 6, 12, 9]   // straights + corners
        for cell in nonPath {
            board[cell.r][cell.c] = RTile(openings: decoyMasks.randomElement()!, fixed: false, kind: .pipe)
        }
        return RollPuzzle(n: n, board: board, source: source, goal: goal)
    }

    /// Randomized DFS simple path from source to goal.
    private nonisolated static func findPath(source: RCell, goal: RCell, n: Int) -> [RCell]? {
        var best: [RCell]? = nil
        func dfs(_ cur: RCell, _ visited: inout Set<RCell>, _ path: inout [RCell]) -> Bool {
            if cur == goal { best = path; return true }
            for d in dirs.shuffled() {
                let nr = cur.r + d.dr, nc = cur.c + d.dc
                guard nr >= 0, nr < n, nc >= 0, nc < n else { continue }
                let nb = RCell(r: nr, c: nc)
                if visited.contains(nb) { continue }
                visited.insert(nb); path.append(nb)
                if dfs(nb, &visited, &path) { return true }
                path.removeLast(); visited.remove(nb)
            }
            return false
        }
        var visited: Set<RCell> = [source]
        var path = [source]
        _ = dfs(source, &visited, &path)
        return best
    }

    private nonisolated static func scramble(_ puzzle: RollPuzzle, moves: Int) -> RollPuzzle {
        var board = puzzle.board
        let n = puzzle.n
        var gap = RCell(r: 0, c: 0)
        for r in 0..<n { for c in 0..<n where board[r][c] == nil { gap = RCell(r: r, c: c) } }
        var lastMoved: RCell? = nil
        for _ in 0..<moves {
            var candidates: [RCell] = []
            for d in dirs {
                let nr = gap.r + d.dr, nc = gap.c + d.dc
                guard nr >= 0, nr < n, nc >= 0, nc < n else { continue }
                let cell = RCell(r: nr, c: nc)
                if let t = board[nr][nc], !t.fixed, cell != lastMoved { candidates.append(cell) }
            }
            if candidates.isEmpty {
                for d in dirs {
                    let nr = gap.r + d.dr, nc = gap.c + d.dc
                    guard nr >= 0, nr < n, nc >= 0, nc < n else { continue }
                    if let t = board[nr][nc], !t.fixed { candidates.append(RCell(r: nr, c: nc)) }
                }
            }
            guard let pick = candidates.randomElement() else { break }
            board[gap.r][gap.c] = board[pick.r][pick.c]
            board[pick.r][pick.c] = nil
            lastMoved = gap
            gap = pick
        }
        return RollPuzzle(n: n, board: board, source: puzzle.source, goal: puzzle.goal)
    }

    private nonisolated static func trivial(n: Int) -> RollPuzzle {
        var board = [[RTile?]](repeating: [RTile?](repeating: nil, count: max(n, 3)), count: max(n, 3))
        board[0][0] = RTile(openings: 2, fixed: true, kind: .source)
        board[0][1] = RTile(openings: 10, fixed: false, kind: .pipe)
        board[0][2] = RTile(openings: 8, fixed: true, kind: .goal)
        return RollPuzzle(n: max(n, 3), board: board, source: RCell(r: 0, c: 0), goal: RCell(r: 0, c: 2))
    }
}

// MARK: - Roll the Ball art

/// BitMango's look: light wooden tiles with a carved groove track (curved on corners), steel-framed
/// fixed tiles with corner screws, riveted steel blockers, a silver ball and a goal hole.
private enum RollArt {
    static let wood = Color(red: 0.86, green: 0.66, blue: 0.42)
    static let woodDark = Color(red: 0.36, green: 0.21, blue: 0.1)
    static let groove = Color(red: 0.4, green: 0.23, blue: 0.1)
    static let lit = Color(red: 1.0, green: 0.8, blue: 0.3)

    private static func disc(_ p: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }

    /// The dark wooden frame the tiles slide in.
    static func frame(_ ctx: GraphicsContext, _ r: CGRect, cell: CGFloat) {
        let outer = r.insetBy(dx: -cell * 0.14, dy: -cell * 0.14)
        ctx.fill(Path(roundedRect: outer.offsetBy(dx: 0, dy: cell * 0.06), cornerRadius: cell * 0.2), with: .color(.black.opacity(0.45)))
        ctx.fill(Path(roundedRect: outer, cornerRadius: cell * 0.2),
                 with: .linearGradient(Gradient(colors: [woodDark.lit(0.2), woodDark, woodDark.shade(0.3)]),
                                       startPoint: CGPoint(x: outer.minX, y: outer.minY), endPoint: CGPoint(x: outer.maxX, y: outer.maxY)))
        ctx.fill(Path(roundedRect: r, cornerRadius: cell * 0.08), with: .color(Color(red: 0.2, green: 0.11, blue: 0.05)))
        ctx.stroke(Path(roundedRect: r, cornerRadius: cell * 0.08), with: .color(.black.opacity(0.5)), lineWidth: 2)
    }

    /// The track through one tile: straight channel, quarter-circle bend, or a dead end at the centre.
    private static func track(_ rect: CGRect, openings m: Int) -> Path {
        let cx = rect.midX, cy = rect.midY
        var p = Path()
        let ends: [(Int, CGPoint)] = [(1, CGPoint(x: cx, y: rect.minY)), (2, CGPoint(x: rect.maxX, y: cy)),
                                      (4, CGPoint(x: cx, y: rect.maxY)), (8, CGPoint(x: rect.minX, y: cy))]
        let open = ends.filter { m & $0.0 != 0 }
        if open.count == 2 && (m == 5 || m == 10) {
            p.move(to: open[0].1); p.addLine(to: open[1].1)
        } else if open.count == 2 {
            // Bend around the tile corner shared by the two openings.
            let corner = CGPoint(x: (m & 2 != 0) ? rect.maxX : rect.minX, y: (m & 1 != 0) ? rect.minY : rect.maxY)
            p.move(to: open[0].1)
            p.addQuadCurve(to: open[1].1, control: CGPoint(x: (open[0].1.x + open[1].1.x) - corner.x,
                                                           y: (open[0].1.y + open[1].1.y) - corner.y))
        } else {
            for e in open { p.move(to: e.1); p.addLine(to: CGPoint(x: cx, y: cy)) }
        }
        return p
    }

    static func tile(_ ctx: GraphicsContext, _ cellRect: CGRect, tile: RTile, lit isLit: Bool, ball: Bool, seed: Int) {
        let s = cellRect.width
        let r = cellRect.insetBy(dx: s * 0.035, dy: s * 0.035)
        let body = Path(roundedRect: r, cornerRadius: s * 0.09)
        if tile.kind == .blocker {
            steel(ctx, r, cornerRadius: s * 0.09)
            var cross = Path()
            cross.move(to: CGPoint(x: r.minX + s * 0.22, y: r.minY + s * 0.22)); cross.addLine(to: CGPoint(x: r.maxX - s * 0.22, y: r.maxY - s * 0.22))
            cross.move(to: CGPoint(x: r.maxX - s * 0.22, y: r.minY + s * 0.22)); cross.addLine(to: CGPoint(x: r.minX + s * 0.22, y: r.maxY - s * 0.22))
            ctx.stroke(cross, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: s * 0.07, lineCap: .round))
            ctx.stroke(cross, with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth: s * 0.025, lineCap: .round))
            return
        }
        // Wooden block: grain, then a bevel.
        ctx.fill(body, with: .linearGradient(Gradient(colors: [wood.lit(0.1), wood, wood.shade(0.12)]),
                                             startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.maxX, y: r.maxY)))
        var g = ctx
        g.clip(to: body)
        for k in 0..<5 {
            let y = r.minY + r.height * (0.1 + 0.2 * CGFloat(k)) + CGFloat((seed * 7 + k * 3) % 5) - 2
            var grain = Path()
            grain.move(to: CGPoint(x: r.minX, y: y))
            grain.addCurve(to: CGPoint(x: r.maxX, y: y + s * 0.04), control1: CGPoint(x: r.minX + r.width * 0.35, y: y - s * 0.05),
                           control2: CGPoint(x: r.minX + r.width * 0.65, y: y + s * 0.08))
            g.stroke(grain, with: .color(wood.shade(0.3).opacity(0.35)), lineWidth: max(0.6, s * 0.012))
        }
        ctx.stroke(Path(roundedRect: r.insetBy(dx: s * 0.02, dy: s * 0.02), cornerRadius: s * 0.08),
                   with: .linearGradient(Gradient(colors: [.white.opacity(0.5), .clear, .black.opacity(0.3)]),
                                         startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.maxX, y: r.maxY)),
                   lineWidth: s * 0.04)
        if tile.fixed { steelFrame(ctx, r, s: s) }
        // The carved groove: dark channel, a shadowed upper edge, and it glows once it joins the track.
        let path = track(r, openings: tile.openings)
        let w = s * 0.34
        var gg = ctx
        gg.clip(to: body)
        gg.stroke(path, with: .color(wood.shade(0.45)), style: StrokeStyle(lineWidth: w * 1.12, lineCap: .round, lineJoin: .round))
        gg.stroke(path, with: .color(isLit ? lit : groove), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        var shadow = gg
        shadow.translateBy(x: 0, y: -w * 0.18)
        shadow.stroke(path, with: .color(.black.opacity(isLit ? 0.15 : 0.35)), style: StrokeStyle(lineWidth: w * 0.45, lineCap: .round, lineJoin: .round))
        if isLit {
            gg.stroke(path, with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: w * 0.18, lineCap: .round, lineJoin: .round))
        }
        if tile.kind == .goal {
            let p = CGPoint(x: r.midX, y: r.midY)
            ctx.fill(disc(p, s * 0.22), with: .linearGradient(Gradient(colors: [Color(white: 0.85), Color(white: 0.45)]),
                                                             startPoint: CGPoint(x: p.x, y: p.y - s * 0.22), endPoint: CGPoint(x: p.x, y: p.y + s * 0.22)))
            ctx.fill(disc(p, s * 0.16), with: .radialGradient(Gradient(colors: [.black, Color(white: 0.12)]),
                                                             center: CGPoint(x: p.x, y: p.y + s * 0.04), startRadius: 0, endRadius: s * 0.16))
        }
        if ball { self.ball(ctx, at: CGPoint(x: r.midX, y: r.midY), r: s * 0.2) }
    }

    private static func steel(_ ctx: GraphicsContext, _ r: CGRect, cornerRadius: CGFloat) {
        ctx.fill(Path(roundedRect: r, cornerRadius: cornerRadius),
                 with: .linearGradient(Gradient(colors: [Color(white: 0.78), Color(white: 0.55), Color(white: 0.68)]),
                                       startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.maxX, y: r.maxY)))
        ctx.stroke(Path(roundedRect: r, cornerRadius: cornerRadius), with: .color(Color(white: 0.3)), lineWidth: 1.5)
        screws(ctx, r, s: r.width)
    }

    /// Fixed tiles can't slide: a steel border bolted down at the corners.
    private static func steelFrame(_ ctx: GraphicsContext, _ r: CGRect, s: CGFloat) {
        ctx.stroke(Path(roundedRect: r.insetBy(dx: s * 0.04, dy: s * 0.04), cornerRadius: s * 0.07),
                   with: .linearGradient(Gradient(colors: [Color(white: 0.85), Color(white: 0.5)]),
                                         startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.maxX, y: r.maxY)),
                   lineWidth: s * 0.08)
        screws(ctx, r, s: s)
    }

    private static func screws(_ ctx: GraphicsContext, _ r: CGRect, s: CGFloat) {
        for (fx, fy) in [(0.13, 0.13), (0.87, 0.13), (0.13, 0.87), (0.87, 0.87)] as [(CGFloat, CGFloat)] {
            let p = CGPoint(x: r.minX + r.width * fx, y: r.minY + r.height * fy)
            let sr = s * 0.055
            ctx.fill(disc(p, sr), with: .radialGradient(Gradient(colors: [Color(white: 0.95), Color(white: 0.5)]),
                                                       center: CGPoint(x: p.x - sr * 0.3, y: p.y - sr * 0.3), startRadius: 0, endRadius: sr * 1.2))
            var slot = Path()
            slot.move(to: CGPoint(x: p.x - sr * 0.6, y: p.y + sr * 0.3)); slot.addLine(to: CGPoint(x: p.x + sr * 0.6, y: p.y - sr * 0.3))
            ctx.stroke(slot, with: .color(Color(white: 0.3)), lineWidth: max(0.8, sr * 0.3))
        }
    }

    /// The polished steel ball.
    static func ball(_ ctx: GraphicsContext, at p: CGPoint, r: CGFloat) {
        ctx.fill(disc(CGPoint(x: p.x + r * 0.15, y: p.y + r * 0.25), r), with: .color(.black.opacity(0.35)))
        ctx.fill(disc(p, r), with: .radialGradient(Gradient(colors: [.white, Color(white: 0.8), Color(white: 0.45), Color(white: 0.25)]),
                                                  center: CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.4), startRadius: 0, endRadius: r * 1.5))
        ctx.stroke(disc(p, r), with: .color(Color(white: 0.2)), lineWidth: max(0.8, r * 0.06))
        ctx.fill(disc(CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.38), r * 0.22), with: .color(.white.opacity(0.9)))
    }
}

/// Warm wood-panelled backdrop (static).
private struct RollBackdrop: View, Equatable {
    var body: some View {
        Canvas { ctx, s in
            ctx.fill(Path(CGRect(origin: .zero, size: s)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.55, green: 0.36, blue: 0.2), Color(red: 0.36, green: 0.21, blue: 0.1)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height)))
            let plank: CGFloat = 46
            var x: CGFloat = 0
            var k = 0
            while x < s.width {
                ctx.fill(Path(CGRect(x: x, y: 0, width: 1.5, height: s.height)), with: .color(.black.opacity(0.22)))
                if k % 2 == 1 { ctx.fill(Path(CGRect(x: x, y: 0, width: plank, height: s.height)), with: .color(.white.opacity(0.03))) }
                x += plank; k += 1
            }
            ctx.fill(Path(CGRect(origin: .zero, size: s)),
                     with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.35)]),
                                           center: CGPoint(x: s.width / 2, y: s.height / 2), startRadius: s.width * 0.3, endRadius: max(s.width, s.height) * 0.8))
        }
        .allowsHitTesting(false)
    }
}
