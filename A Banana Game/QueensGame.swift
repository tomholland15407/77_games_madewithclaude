//
//  QueensGame.swift
//  GOGs
//
//  Brain — Queens (the LinkedIn daily puzzle). Place exactly one crown in every row, every column
//  and every colour region, and no two crowns may touch — not even diagonally. Tap a cell to cycle
//  empty → X (a note) → crown → empty. Clashing crowns light their row/column/region with red
//  stripes (auto-check); placing a crown that clashes costs one of three strikes.
//
//  Every board is generated solution-first: a legal crown layout is drawn, colour regions are
//  grown outward from the crowns, then cells are shuffled between regions until a backtracking
//  solver proves the solution UNIQUE. Early levels are additionally graded by a small logic
//  solver so they fall to pure deduction (no guessing). Boards are built during the countdown via
//  `BoardCache`. Seven levels grow the grid 5×5 → 10×10 on a tightening clock.
//

import SwiftUI

enum QueensGame {
    static let definition = GameDefinition(
        id: "queens",
        title: "Queens",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Place one crown in every row, every column and every color region.",
                "Crowns can never touch each other, not even diagonally.",
                "Tap a cell once for an X note, twice for a crown, a third time to clear it.",
                "Three clashing crowns, or the clock running out, sends you back to level 1.",
            ],
            bulletsVI: [
                "Đặt một vương miện ở mỗi hàng, mỗi cột và mỗi vùng màu.",
                "Các vương miện không bao giờ được chạm nhau, kể cả theo đường chéo.",
                "Chạm một ô một lần để ghi chú X, hai lần để đặt vương miện, lần ba để xóa.",
                "Đặt sai ba vương miện, hoặc hết giờ, bạn sẽ về lại cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(QueensView(level: level, onWin: onWin, onFail: onFail))
        },
        prefetch: { level in QueensView(level: level, onWin: {}, onFail: {}).prefetchBoard() }
    )
}

// MARK: - Generator

private nonisolated struct QueensBoard: Sendable {
    let n: Int
    let regions: [Int]      // region id (0..<n) per cell, row-major
    let solution: [Int]     // crown column for each row
}

private nonisolated enum QueensGen {
    static func neighbors(_ i: Int, _ n: Int) -> [Int] {
        let r = i / n, c = i % n
        var out: [Int] = []
        if r > 0 { out.append(i - n) }
        if r < n - 1 { out.append(i + n) }
        if c > 0 { out.append(i - 1) }
        if c < n - 1 { out.append(i + 1) }
        return out
    }

    /// A random legal crown layout: one per row/column, consecutive rows ≥ 2 columns apart.
    static func randomSolution(_ n: Int) -> [Int] {
        var cols = [Int](repeating: -1, count: n)
        var used = [Bool](repeating: false, count: n)
        func place(_ r: Int) -> Bool {
            if r == n { return true }
            for c in (0..<n).shuffled() where !used[c] {
                if r > 0 && abs(c - cols[r - 1]) < 2 { continue }
                cols[r] = c; used[c] = true
                if place(r + 1) { return true }
                used[c] = false
            }
            return false
        }
        _ = place(0)
        return cols
    }

    /// Grows one region per crown by a weighted random flood fill, so sizes vary (tiny pockets
    /// next to long snakes, like the hand-made puzzles).
    static func grow(_ n: Int, _ solution: [Int]) -> [Int] {
        var reg = [Int](repeating: -1, count: n * n)
        let weights: [Double] = (0..<n).map { _ in [0.35, 1, 1, 1.6, 2.6].randomElement()! }
        var frontier: [[Int]] = Array(repeating: [], count: n)
        for (r, c) in solution.enumerated() {
            let i = r * n + c
            reg[i] = r
            frontier[r] = neighbors(i, n)
        }
        var left = n * n - n
        while left > 0 {
            let live = (0..<n).filter { !frontier[$0].isEmpty }
            guard !live.isEmpty else { break }
            let total = live.reduce(0.0) { $0 + weights[$1] }
            var pick = Double.random(in: 0..<total)
            var k = live[0]
            for x in live { pick -= weights[x]; if pick < 0 { k = x; break } }
            let j = frontier[k].remove(at: Int.random(in: 0..<frontier[k].count))
            if reg[j] != -1 { continue }
            reg[j] = k
            left -= 1
            frontier[k].append(contentsOf: neighbors(j, n).filter { reg[$0] == -1 })
        }
        return reg
    }

    /// Counts solutions (stopping at 2) and returns the first one that differs from `intended`.
    static func solve(_ n: Int, _ reg: [Int], intended: [Int]) -> (count: Int, other: [Int]?) {
        var cols = [Int](repeating: -1, count: n)
        var count = 0
        var other: [Int]? = nil
        func bt(_ r: Int, _ colMask: Int, _ regMask: Int, _ prev: Int) -> Bool {
            if r == n {
                count += 1
                if other == nil && cols != intended { other = cols }
                return count >= 2
            }
            for c in 0..<n {
                if (colMask >> c) & 1 == 1 { continue }
                if prev >= 0 && abs(c - prev) < 2 { continue }
                let g = reg[r * n + c]
                if (regMask >> g) & 1 == 1 { continue }
                cols[r] = c
                if bt(r + 1, colMask | (1 << c), regMask | (1 << g), c) { return true }
            }
            return false
        }
        _ = bt(0, 0, 0, -1)
        return (count, other)
    }

    static func stillConnected(_ n: Int, _ reg: [Int], removing cell: Int) -> Bool {
        let k = reg[cell]
        let cells = (0..<n * n).filter { reg[$0] == k && $0 != cell }
        guard let first = cells.first else { return false }
        let members = Set(cells)
        var seen: Set<Int> = [first]
        var stack = [first]
        while let x = stack.popLast() {
            for y in neighbors(x, n) where members.contains(y) && !seen.contains(y) {
                seen.insert(y); stack.append(y)
            }
        }
        return seen.count == cells.count
    }

    /// Human-style solver used to grade boards: singles (a row/column/region with one open cell)
    /// and confinement (a region squeezed into one row/column clears the rest of that line), plus —
    /// with `lookahead` — "a crown here would leave some line or region with no room".
    static func logicSolvable(_ n: Int, _ reg: [Int], lookahead: Bool) -> Bool {
        let cellCount = n * n
        var units: [[Int]] = []
        for r in 0..<n { units.append((0..<n).map { r * n + $0 }) }
        for c in 0..<n { units.append((0..<n).map { $0 * n + c }) }
        for k in 0..<n { units.append((0..<cellCount).filter { reg[$0] == k }) }
        let unitsOf: [[Int]] = (0..<cellCount).map { [$0 / n, n + $0 % n, 2 * n + reg[$0]] }
        var cand = [Bool](repeating: true, count: cellCount)
        var done = [Bool](repeating: false, count: units.count)
        var placed = 0

        func killSet(_ i: Int) -> Set<Int> {
            var s = Set<Int>()
            for u in unitsOf[i] { s.formUnion(units[u]) }
            let r = i / n, c = i % n
            for dr in -1...1 {
                for dc in -1...1 {
                    let rr = r + dr, cc = c + dc
                    if rr >= 0, rr < n, cc >= 0, cc < n { s.insert(rr * n + cc) }
                }
            }
            return s
        }
        func place(_ i: Int) {
            for j in killSet(i) { cand[j] = false }
            for u in unitsOf[i] { done[u] = true }
            placed += 1
        }

        while placed < n {
            var progress = false
            for u in units.indices where !done[u] {
                var only = -1, count = 0
                for i in units[u] where cand[i] { count += 1; only = i; if count > 1 { break } }
                if count == 0 { return false }
                if count == 1 { place(only); progress = true; break }
            }
            if progress { continue }

            confine: for u in units.indices where !done[u] {
                let cs = units[u].filter { cand[$0] }
                guard let first = cs.first else { return false }
                for v in unitsOf[first] where v / n != u / n && !done[v] {
                    if cs.allSatisfy({ unitsOf[$0].contains(v) }) {
                        let inU = Set(cs)
                        var changed = false
                        for j in units[v] where cand[j] && !inU.contains(j) { cand[j] = false; changed = true }
                        if changed { progress = true; break confine }
                    }
                }
            }
            if progress { continue }

            if lookahead {
                for i in 0..<cellCount where cand[i] {
                    let kill = killSet(i)
                    var dead = false
                    for u in units.indices where !done[u] && !unitsOf[i].contains(u) {
                        if !units[u].contains(where: { cand[$0] && !kill.contains($0) }) { dead = true; break }
                    }
                    if dead { cand[i] = false; progress = true; break }
                }
                if progress { continue }
            }
            return false
        }
        return true
    }

    /// grade 1 = deduction only, 2 = deduction + one-step lookahead, 3 = any unique board.
    static func generate(n: Int, grade: Int) -> QueensBoard {
        var fallback: QueensBoard? = nil
        for _ in 0..<600 {
            let sol = randomSolution(n)
            var reg = grow(n, sol)
            let seeds = Set(sol.enumerated().map { $0.offset * n + $0.element })
            for _ in 0..<80 {
                let (count, other) = solve(n, reg, intended: sol)
                if count == 1 {
                    let board = QueensBoard(n: n, regions: reg, solution: sol)
                    if grade >= 3 || logicSolvable(n, reg, lookahead: grade >= 2) { return board }
                    if fallback == nil { fallback = board }
                    break
                }
                guard let other else { break }
                // Break the rival solution: hand one of its crown cells to a neighbouring region.
                // The intended crowns are region seeds and never move, so the real answer survives.
                var moved = false
                for r in (0..<n).shuffled() where other[r] != sol[r] {
                    let x = r * n + other[r]
                    if seeds.contains(x) { continue }
                    let targets = Set(neighbors(x, n).map { reg[$0] }).subtracting([reg[x]])
                    if let target = targets.randomElement(), stillConnected(n, reg, removing: x) {
                        reg[x] = target
                        moved = true
                        break
                    }
                }
                if !moved { break }
            }
        }
        return fallback ?? QueensBoard(n: 5, regions: QueensView.demoRegions, solution: QueensView.demoSolution)
    }
}

// MARK: - View

struct QueensView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void
    @Environment(\.isDemo) private var isDemo

    private var n: Int { [5, 6, 7, 7, 8, 9, 10][min(level, 7) - 1] }
    private var grade: Int { [1, 1, 2, 2, 2, 3, 3][min(level, 7) - 1] }
    private var timeLimit: Double { [60, 70, 80, 65, 85, 95, 100][min(level, 7) - 1] }
    private let maxMistakes = 3

    /// LinkedIn Queens' pastel region palette.
    private static let palette: [Color] = [
        Color(red: 0.733, green: 0.639, blue: 0.886),   // lavender
        Color(red: 1.000, green: 0.788, blue: 0.573),   // apricot
        Color(red: 0.588, green: 0.745, blue: 1.000),   // sky
        Color(red: 0.702, green: 0.875, blue: 0.627),   // sage
        Color(red: 0.875, green: 0.875, blue: 0.875),   // light grey
        Color(red: 1.000, green: 0.482, blue: 0.376),   // coral
        Color(red: 0.902, green: 0.953, blue: 0.533),   // lime
        Color(red: 0.725, green: 0.698, blue: 0.620),   // khaki
        Color(red: 0.875, green: 0.627, blue: 0.749),   // rose
        Color(red: 0.639, green: 0.824, blue: 0.847),   // teal
    ]
    private static let ink = Color(red: 0.10, green: 0.10, blue: 0.11)
    private static let clash = Color(red: 0.86, green: 0.16, blue: 0.14)

    private enum Mark { case empty, x, crown }
    private enum Phase { case play, won, done }

    @State private var phase: Phase = .play
    @State private var boardN = 0
    @State private var regions: [Int] = []
    @State private var colorOf: [Int] = []          // region id → palette index
    @State private var marks: [Mark] = []
    @State private var mistakes = 0
    @State private var timeLeft = 0.0
    @State private var ready = false
    @State private var shake = 0
    @State private var celebrate: Double = -1       // win wave progress 0…1 (−1 = idle)
    @State private var demoCell: Int? = nil

    var body: some View {
        Group {
            if ready {
                gameBody
            } else {
                BrainstormingView(skyTop: Color(white: 0.13), skyBottom: Color(white: 0.05))
            }
        }
        .task { isDemo ? await runDemo() : await run() }
    }

    private var gameBody: some View {
        VStack(spacing: isDemo ? 8 : 14) {
            if !isDemo { timeBar.frame(height: 6).padding(.horizontal, 48) }
            statusRow
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                board(side: side)
                    .frame(width: side, height: side)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
        .padding(.horizontal, isDemo ? 12 : 18)
        .padding(.vertical, isDemo ? 8 : 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusRow: some View {
        let crowns = marks.filter { $0 == .crown }.count
        return HStack(spacing: 8) {
            Image(systemName: "crown.fill")
                .foregroundStyle(BananaTheme.banana)
            Text("\(crowns)/\(boardN)")
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Spacer()
            ForEach(0..<maxMistakes, id: \.self) { i in
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(i < mistakes ? Self.clash : .white.opacity(0.18))
            }
        }
        .font(.system(size: isDemo ? 15 : 19, weight: .black, design: .rounded))
    }

    // MARK: Board

    private func board(side: CGFloat) -> some View {
        Canvas { ctx, size in drawBoard(ctx, size: size) }
            .clipShape(RoundedRectangle(cornerRadius: side * 0.025))
            .overlay(RoundedRectangle(cornerRadius: side * 0.025).stroke(.white.opacity(0.14), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { loc in
                guard !isDemo, boardN > 0 else { return }
                let cell = side / CGFloat(boardN)
                let c = Int(loc.x / cell), r = Int(loc.y / cell)
                guard r >= 0, r < boardN, c >= 0, c < boardN else { return }
                tap(r * boardN + c)
            }
            .screenShake(shake, amount: 7)
    }

    private func drawBoard(_ ctx: GraphicsContext, size: CGSize) {
        let n = boardN
        guard n > 0, regions.count == n * n, marks.count == n * n, colorOf.count == n else { return }
        let cell = size.width / CGFloat(n)
        let info = conflicts()
        func rect(_ i: Int) -> CGRect {
            CGRect(x: CGFloat(i % n) * cell, y: CGFloat(i / n) * cell, width: cell, height: cell)
        }

        // Region fills.
        for i in 0..<n * n {
            ctx.fill(Path(rect(i)), with: .color(Self.palette[colorOf[regions[i]] % Self.palette.count]))
        }
        // Auto-check: red diagonal stripes over every clashing line/region/pair.
        for i in info.striped {
            var s = ctx
            let rc = rect(i)
            s.clip(to: Path(rc))
            var stripes = Path()
            let step = cell / 4.2
            var x = rc.minX - rc.height
            while x < rc.maxX {
                stripes.move(to: CGPoint(x: x, y: rc.maxY))
                stripes.addLine(to: CGPoint(x: x + rc.height, y: rc.minY))
                x += step
            }
            s.stroke(stripes, with: .color(Self.clash.opacity(0.55)), lineWidth: max(1.5, cell * 0.07))
        }
        // Thin lines inside regions, thick ink where regions meet.
        var thin = Path(), thick = Path()
        for r in 0..<n {
            for c in 0..<n {
                let i = r * n + c
                if c < n - 1 {
                    let x = CGFloat(c + 1) * cell
                    var seg = Path()
                    seg.move(to: CGPoint(x: x, y: CGFloat(r) * cell))
                    seg.addLine(to: CGPoint(x: x, y: CGFloat(r + 1) * cell))
                    if regions[i] == regions[i + 1] { thin.addPath(seg) } else { thick.addPath(seg) }
                }
                if r < n - 1 {
                    let y = CGFloat(r + 1) * cell
                    var seg = Path()
                    seg.move(to: CGPoint(x: CGFloat(c) * cell, y: y))
                    seg.addLine(to: CGPoint(x: CGFloat(c + 1) * cell, y: y))
                    if regions[i] == regions[i + n] { thin.addPath(seg) } else { thick.addPath(seg) }
                }
            }
        }
        ctx.stroke(thin, with: .color(Self.ink.opacity(0.28)), lineWidth: max(0.8, cell * 0.018))
        let thickW = max(2.2, cell * 0.075)
        ctx.stroke(thick, with: .color(Self.ink), style: StrokeStyle(lineWidth: thickW, lineCap: .square))
        ctx.stroke(Path(CGRect(origin: .zero, size: size).insetBy(dx: thickW / 2, dy: thickW / 2)),
                   with: .color(Self.ink), lineWidth: thickW)

        // Marks.
        var crown = ctx.resolve(Image(systemName: "crown.fill"))
        for i in 0..<n * n {
            let rc = rect(i)
            switch marks[i] {
            case .empty:
                break
            case .x:
                var p = Path()
                let d = cell * 0.13
                p.move(to: CGPoint(x: rc.midX - d, y: rc.midY - d)); p.addLine(to: CGPoint(x: rc.midX + d, y: rc.midY + d))
                p.move(to: CGPoint(x: rc.midX + d, y: rc.midY - d)); p.addLine(to: CGPoint(x: rc.midX - d, y: rc.midY + d))
                ctx.stroke(p, with: .color(Self.ink.opacity(0.62)),
                           style: StrokeStyle(lineWidth: max(1.2, cell * 0.045), lineCap: .round))
            case .crown:
                // Win wave: crowns pop row by row.
                var scale: CGFloat = 1
                if celebrate >= 0 {
                    let t = celebrate * 1.6 - Double(i / n) * 0.09
                    scale = 1 + 0.32 * CGFloat(sin(min(max(t, 0), 1) * .pi))
                }
                let w = cell * 0.6 * scale
                crown.shading = .color(info.badCrowns.contains(i) ? Self.clash : Self.ink)
                ctx.draw(crown, in: CGRect(x: rc.midX - w / 2, y: rc.midY - w * 0.46, width: w, height: w * 0.86))
            }
        }

        // Demo: a ring + finger on the cell being tapped.
        if isDemo, let d = demoCell, d < n * n {
            let rc = rect(d).insetBy(dx: 2, dy: 2)
            ctx.stroke(Path(roundedRect: rc, cornerRadius: 4), with: .color(.white), lineWidth: 2.5)
            var hand = ctx.resolve(Image(systemName: "hand.point.up.left.fill"))
            hand.shading = .color(.white)
            var h = ctx
            h.addFilter(.shadow(color: .black.opacity(0.6), radius: 3))
            let hw = cell * 0.62
            h.draw(hand, in: CGRect(x: rc.midX + cell * 0.02, y: rc.midY + cell * 0.08, width: hw, height: hw))
        }
    }

    // MARK: Rules

    /// Cells to stripe (every row/column/region holding 2+ crowns, plus touching pairs) and the
    /// crowns involved.
    private func conflicts() -> (striped: Set<Int>, badCrowns: Set<Int>) {
        let n = boardN
        let crowns = marks.indices.filter { marks[$0] == .crown }
        var striped = Set<Int>(), bad = Set<Int>()
        guard crowns.count > 1 else { return (striped, bad) }
        func mark(_ group: [Int], cells: [Int]) {
            if group.count > 1 { bad.formUnion(group); striped.formUnion(cells) }
        }
        for r in 0..<n { mark(crowns.filter { $0 / n == r }, cells: (0..<n).map { r * n + $0 }) }
        for c in 0..<n { mark(crowns.filter { $0 % n == c }, cells: (0..<n).map { $0 * n + c }) }
        for k in 0..<n {
            mark(crowns.filter { regions[$0] == k }, cells: (0..<n * n).filter { regions[$0] == k })
        }
        for a in crowns {
            for b in crowns where b > a && abs(a / n - b / n) <= 1 && abs(a % n - b % n) <= 1 {
                bad.formUnion([a, b]); striped.formUnion([a, b])
            }
        }
        return (striped, bad)
    }

    private func tap(_ i: Int) {
        guard phase == .play, i < marks.count else { return }
        switch marks[i] {
        case .empty: marks[i] = .x
        case .x:     marks[i] = .crown
        case .crown: marks[i] = .empty
        }
        guard marks[i] == .crown else { SoundManager.shared.tap(); Haptics.tap(); return }

        let info = conflicts()
        if info.badCrowns.contains(i) {
            mistakes += 1
            shake += 1
            SoundManager.shared.error()
            Haptics.warning()
            if mistakes >= maxMistakes { fail() }
            return
        }
        SoundManager.shared.tap(); Haptics.tap()
        if marks.filter({ $0 == .crown }).count == boardN && info.badCrowns.isEmpty {
            phase = .won   // the run loop plays the crown wave, then reports the win
        }
    }

    // MARK: Flow

    func prefetchBoard() {
        let size = n, g = grade
        BoardCache.prefetch(boardKey) { QueensGen.generate(n: size, grade: g) }
    }
    private var boardKey: String { BoardCache.key("queens", level: level) }

    private func load(_ board: QueensBoard) {
        boardN = board.n
        regions = board.regions
        colorOf = Array(0..<board.n).shuffled()
        marks = Array(repeating: .empty, count: board.n * board.n)
        mistakes = 0
        celebrate = -1
    }

    private func run() async {
        let size = n, g = grade
        let t0 = Date()
        let board = await BoardCache.take(boardKey) { QueensGen.generate(n: size, grade: g) }
        guard !Task.isCancelled else { return }
        await BoardCache.holdBrainstorm(since: t0, minimum: 0.7)
        guard !Task.isCancelled else { return }

        load(board)
        ready = true
        phase = .play
        timeLeft = timeLimit
        let start = Date()
        // Structured loop (cancelled with the view): drives the clock and the win wave.
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(0.05))
            switch phase {
            case .play:
                timeLeft = max(0, timeLimit - Date().timeIntervalSince(start))
                if timeLeft <= 0 { fail(); return }
            case .won:
                await playWinWave()
                guard !Task.isCancelled else { return }
                phase = .done
                onWin()
                return
            case .done:
                return
            }
        }
    }

    private func playWinWave() async {
        let t0 = Date()
        while !Task.isCancelled {
            let t = Date().timeIntervalSince(t0) / 0.75
            celebrate = min(1, t)
            if t >= 1 { break }
            try? await Task.sleep(for: .seconds(1.0 / 60))
        }
    }

    private func fail() {
        guard phase == .play else { return }
        phase = .done
        SoundManager.shared.error()
        onFail()
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(frac < 0.3 ? .red : BananaTheme.banana)
                    .frame(width: geo.size.width * frac)
            }
        }
    }

    // MARK: - Demo (live manual clip)
    // A fixed 5×5 board with a unique solution, found offline and graded "pure deduction":
    //   2 2 2 0 0     Regions 0 and 1 are 2-cell pockets lying in rows 0 and 1, so no other region
    //   2 4 1 1 3     can use those rows → X the rest of rows 0–1. That leaves region 2 a single
    //   2 4 4 3 3     cell (row 2, col 0), and the other crowns fall in turn: (4,1) → (3,3) →
    //   4 4 3 3 4     (0,4) → (1,2). Each crown is two real taps (X, then crown); the fifth is the
    //   4 4 4 4 4     real win.
    nonisolated static let demoRegions = [2, 2, 2, 0, 0, 2, 4, 1, 1, 3, 2, 4, 4, 3, 3, 4, 4, 3, 3, 4, 4, 4, 4, 4, 4]
    nonisolated static let demoSolution = [4, 2, 0, 3, 1]
    private static let demoColors = [3, 5, 1, 2, 0]      // pocket colours chosen to read clearly
    private static let demoNotes = [0, 1, 2, 5, 6, 9]    // X'd cells (rows 0–1 outside the pockets)
    private static let demoCrowns = [10, 21, 18, 4, 7]

    private func runDemo() async {
        while !Task.isCancelled {
            load(QueensBoard(n: 5, regions: Self.demoRegions, solution: Self.demoSolution))
            colorOf = Self.demoColors
            demoCell = nil
            phase = .play
            ready = true
            try? await Task.sleep(for: .seconds(0.7))
            for cell in Self.demoNotes {
                guard !Task.isCancelled else { return }
                demoCell = cell
                try? await Task.sleep(for: .seconds(0.16))
                tap(cell)
                try? await Task.sleep(for: .seconds(0.2))
            }
            for cell in Self.demoCrowns {
                guard !Task.isCancelled else { return }
                demoCell = cell
                try? await Task.sleep(for: .seconds(0.22))
                tap(cell)
                try? await Task.sleep(for: .seconds(0.2))
                tap(cell)
                try? await Task.sleep(for: .seconds(0.3))
            }
            demoCell = nil
            if phase == .won { await playWinWave() }
            try? await Task.sleep(for: .seconds(1.2))
        }
    }
}
