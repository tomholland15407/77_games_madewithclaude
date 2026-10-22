//
//  NurikabeGame.swift
//  A Banana Game
//
//  Brain — Nurikabe ("islands in the stream"). Flood the grid with sea while leaving the numbered
//  islands dry. Tap a cell to cycle land → sea → land-with-a-dot (a pencil mark) → land. Four rules
//  must all hold at once:
//    • Every numbered cell is an island of exactly that many land cells (one number per island).
//    • Islands never touch orthogonally (diagonal is fine).
//    • All the sea is a single connected body.
//    • The sea contains no solid 2×2 block.
//  Solve it before the clock runs out or it's back to level 1.
//
//  Boards are built solved-first: isolated islands are grown at arm's length from each other, then
//  any 2×2 sea pools are broken up by dropping in single-cell islands, and the layout is verified
//  (sea connected, no pools). A guaranteed-valid comb pattern is the fallback. Clues are the island
//  sizes; the win check re-proves all four rules, so only a truly correct sea wins. Generation runs
//  off-main behind the shared brainstorming banana. Seven levels grow the grid and the islands.
//

import SwiftUI

enum NurikabeGame {
    static let definition = GameDefinition(
        id: "nurikabe",
        title: "Lagoon Islands",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Tap a cell to cycle land → sea → dotted land → land.",
                "Each numbered cell is an island of exactly that many land cells; islands never touch.",
                "All sea joins into one body — and no 2×2 block of sea is allowed.",
                "Solve the whole grid before the clock runs out.",
            ],
            bulletsVI: [
                "Chạm một ô để luân chuyển đất → biển → đất chấm → đất.",
                "Mỗi ô có số là một đảo gồm đúng bấy nhiêu ô đất; các đảo không chạm nhau.",
                "Toàn bộ biển nối thành một khối — và không được có khối biển 2×2.",
                "Giải toàn bộ lưới trước khi hết giờ.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(NurikabeView(level: level, onWin: onWin, onFail: onFail))
        },
        prefetch: { level in NurikabeView(level: level, onWin: {}, onFail: {}).prefetchBoard() }
    )
}

private struct NKPuzzle: Sendable {
    let n: Int
    let clues: [Int: Int]     // cell index -> island size
}

private enum NKGen {
    static func orth(_ cell: Int, _ n: Int) -> [Int] {
        let r = cell / n, c = cell % n
        var out: [Int] = []
        if r > 0 { out.append((r - 1) * n + c) }
        if r < n - 1 { out.append((r + 1) * n + c) }
        if c > 0 { out.append(r * n + c - 1) }
        if c < n - 1 { out.append(r * n + c + 1) }
        return out
    }

    static func hasIslandNeighbor(_ cell: Int, _ id: [Int], _ n: Int) -> Bool {
        orth(cell, n).contains { id[$0] != 0 }
    }
    static func hasOtherIslandNeighbor(_ cell: Int, _ thisId: Int, _ id: [Int], _ n: Int) -> Bool {
        orth(cell, n).contains { id[$0] != 0 && id[$0] != thisId }
    }

    static func has2x2Water(_ id: [Int], _ n: Int) -> Bool {
        for r in 0..<n - 1 {
            for c in 0..<n - 1 {
                let a = r * n + c
                if id[a] == 0 && id[a + 1] == 0 && id[a + n] == 0 && id[a + n + 1] == 0 { return true }
            }
        }
        return false
    }

    static func waterConnected(_ water: [Int], _ n: Int) -> Bool {
        guard let start = water.first else { return false }
        let set = Set(water)
        var seen: Set<Int> = [start]
        var stack = [start]
        while let cur = stack.popLast() {
            for nb in orth(cur, n) where set.contains(nb) && !seen.contains(nb) {
                seen.insert(nb); stack.append(nb)
            }
        }
        return seen.count == set.count
    }

    static func repairPools(_ id: inout [Int], _ nextId: inout Int, _ n: Int) -> Bool {
        var guardCount = 0
        while true {
            guardCount += 1
            if guardCount > n * n * 4 { return false }
            var pool: Int?
            outer: for r in 0..<n - 1 {
                for c in 0..<n - 1 {
                    let a = r * n + c
                    if id[a] == 0 && id[a + 1] == 0 && id[a + n] == 0 && id[a + n + 1] == 0 {
                        pool = a; break outer
                    }
                }
            }
            guard let tl = pool else { return true }
            let cells = [tl, tl + 1, tl + n, tl + n + 1]
            var converted = false
            for cand in cells.shuffled() where !hasIslandNeighbor(cand, id, n) {
                id[cand] = nextId; nextId += 1
                converted = true; break
            }
            if !converted { return false }
        }
    }

    static func generate(n: Int, islandCount: Int, maxSize: Int) -> NKPuzzle {
        for _ in 0..<2500 {
            var id = [Int](repeating: 0, count: n * n)
            var nextId = 1
            var ok = true
            for _ in 0..<islandCount {
                let seeds = (0..<n * n).filter { id[$0] == 0 && !hasIslandNeighbor($0, id, n) }
                guard let seed = seeds.randomElement() else { ok = false; break }
                let thisId = nextId; nextId += 1
                id[seed] = thisId
                var members = [seed]
                let size = Int.random(in: 1...maxSize)
                var guardCount = 0
                while members.count < size && guardCount < 200 {
                    guardCount += 1
                    var cands: [Int] = []
                    for m in members {
                        for nb in orth(m, n) where id[nb] == 0 && !hasOtherIslandNeighbor(nb, thisId, id, n) {
                            cands.append(nb)
                        }
                    }
                    guard let add = cands.randomElement() else { break }
                    id[add] = thisId; members.append(add)
                }
            }
            guard ok else { continue }
            guard repairPools(&id, &nextId, n) else { continue }

            let water = (0..<n * n).filter { id[$0] == 0 }
            guard !water.isEmpty, waterConnected(water, n), !has2x2Water(id, n) else { continue }

            var cellsById: [Int: [Int]] = [:]
            for i in 0..<n * n where id[i] != 0 { cellsById[id[i], default: []].append(i) }
            guard !cellsById.isEmpty else { continue }
            var clues: [Int: Int] = [:]
            for (_, cells) in cellsById {
                clues[cells.randomElement()!] = cells.count
            }
            return NKPuzzle(n: n, clues: clues)
        }
        return fallback(n: n)
    }

    /// A single-cell island at every (odd, odd) cell: each is isolated, every 2×2 contains exactly
    /// one, and the remaining sea stays connected. Always a valid Nurikabe.
    static func fallback(n: Int) -> NKPuzzle {
        var clues: [Int: Int] = [:]
        var r = 1
        while r < n { var c = 1; while c < n { clues[r * n + c] = 1; c += 2 }; r += 2 }
        return NKPuzzle(n: n, clues: clues)
    }
}

struct NurikabeView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    private var n: Int { [5, 6, 6, 7, 7, 8, 8][min(level, 7) - 1] }
    private var islandCount: Int { [2, 3, 3, 4, 4, 5, 5][min(level, 7) - 1] }
    private var maxSize: Int { [3, 3, 4, 4, 5, 5, 6][min(level, 7) - 1] }
    private var timeLimit: Double { [80, 85, 90, 95, 95, 90, 85][min(level, 7) - 1] }

    private let skyTop = Color(red: 0.05, green: 0.42, blue: 0.62)
    private let skyBottom = Color(red: 0.02, green: 0.2, blue: 0.38)

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var boardN = 0
    @State private var clues: [Int: Int] = [:]
    @State private var mark: [Int] = []       // 0 = land, 1 = sea, 2 = dotted land
    @State private var timeLeft = 0.0
    @State private var ready = false
    @State private var loopTask: Task<Void, Never>?
    @State private var demoTap: Int? = nil      // cell the demo is "tapping" (ring + finger)

    private var seaNeeded: Int { boardN * boardN - clues.values.reduce(0, +) }
    private var seaCount: Int { mark.filter { $0 == 1 }.count }

    var body: some View {
        Group {
            if ready { gameBody } else { BrainstormingView(skyTop: skyTop, skyBottom: skyBottom) }
        }
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
    }

    private var gameBody: some View {
        VStack(spacing: isDemo ? 6 : 12) {
            Text(L("\(seaCount)/\(seaNeeded) sea", "biển \(seaCount)/\(seaNeeded)"))
                .font(.system(size: isDemo ? 15 : 20, weight: .black, design: .rounded))
                .foregroundStyle(seaCount == seaNeeded ? Color(red: 1, green: 0.9, blue: 0.5) : .white)
                .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 2)
                .contentTransition(.numericText())
            if !isDemo { timeBar.frame(height: 6).padding(.horizontal, 50) }

            GeometryReader { geo in
                let cell = boardN > 0 ? min(geo.size.width, geo.size.height) * 0.95 / CGFloat(boardN) : 0
                let ox = (geo.size.width - cell * CGFloat(boardN)) / 2
                let oy = (geo.size.height - cell * CGFloat(boardN)) / 2
                Canvas { ctx, _ in drawIslands(ctx, cell: cell, ox: ox, oy: oy) }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture { loc in
                        guard cell > 0 else { return }
                        let c = Int(floor((loc.x - ox) / cell)), r = Int(floor((loc.y - oy) / cell))
                        guard r >= 0, r < boardN, c >= 0, c < boardN else { return }
                        tap(r * boardN + c)
                    }
            }
            .padding(.horizontal, isDemo ? 4 : 8)
        }
        .padding(.vertical, isDemo ? 8 : 14)
        .background(OceanBackdrop().equatable())
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A lagoon: turquoise sea everywhere the player floods, sandy islands with rounded coasts and a
    /// shallows ring elsewhere, palm-tree clue islands, seashells for dotted land.
    private func drawIslands(_ ctx: GraphicsContext, cell: CGFloat, ox: CGFloat, oy: CGFloat) {
        let n = boardN
        guard n > 0, mark.count == n * n else { return }
        let board = CGRect(x: ox, y: oy, width: cell * CGFloat(n), height: cell * CGFloat(n))
        func rect(_ i: Int) -> CGRect { CGRect(x: ox + CGFloat(i % n) * cell, y: oy + CGFloat(i / n) * cell, width: cell, height: cell) }
        func land(_ r: Int, _ c: Int) -> Bool {
            guard r >= 0, r < n, c >= 0, c < n else { return true }     // the frame squares islands off
            return mark[r * n + c] != 1
        }
        IslandArt.sea(ctx, board, cell: cell)
        // Each land cell rounds any corner whose two neighbours are both sea (a coastline).
        func shape(_ i: Int, grow: CGFloat) -> Path {
            let r = i / n, c = i % n
            let rc = rect(i).insetBy(dx: -grow, dy: -grow)
            let k = cell * 0.42
            let tl = !land(r - 1, c) && !land(r, c - 1), tr = !land(r - 1, c) && !land(r, c + 1)
            let bl = !land(r + 1, c) && !land(r, c - 1), br = !land(r + 1, c) && !land(r, c + 1)
            return Path(roundedRect: rc, cornerRadii: RectangleCornerRadii(topLeading: tl ? k : 0, bottomLeading: bl ? k : 0,
                                                                          bottomTrailing: br ? k : 0, topTrailing: tr ? k : 0))
        }
        var shallows = Path(), sand = Path()
        for i in 0..<n * n where mark[i] != 1 {
            shallows.addPath(shape(i, grow: cell * 0.09))
            sand.addPath(shape(i, grow: 0.3))
        }
        ctx.fill(shallows, with: .color(Color(red: 0.55, green: 0.92, blue: 0.9).opacity(0.75)))
        ctx.fill(sand, with: .linearGradient(Gradient(colors: [Color(red: 0.98, green: 0.9, blue: 0.68), Color(red: 0.92, green: 0.8, blue: 0.55)]),
                                             startPoint: CGPoint(x: board.minX, y: board.minY), endPoint: CGPoint(x: board.maxX, y: board.maxY)))
        // Faint cell lines so islands can be counted.
        var grid = Path()
        for k in 1..<n {
            let x = ox + CGFloat(k) * cell, y = oy + CGFloat(k) * cell
            grid.move(to: CGPoint(x: x, y: board.minY)); grid.addLine(to: CGPoint(x: x, y: board.maxY))
            grid.move(to: CGPoint(x: board.minX, y: y)); grid.addLine(to: CGPoint(x: board.maxX, y: y))
        }
        var sandOnly = ctx
        sandOnly.clip(to: sand)
        sandOnly.stroke(grid, with: .color(Color(red: 0.7, green: 0.56, blue: 0.34).opacity(0.45)), lineWidth: 1)
        for i in 0..<n * n {
            let rc = rect(i)
            if let v = clues[i] {
                IslandArt.clue(ctx, rc, number: v)
            } else if mark[i] == 2 {
                IslandArt.shell(ctx, at: CGPoint(x: rc.midX, y: rc.midY), size: cell * 0.36)
            }
        }
        ctx.stroke(Path(roundedRect: board.insetBy(dx: -2, dy: -2), cornerRadius: 10), with: .color(.white.opacity(0.35)), lineWidth: 2)
        // Demo press: a ring and a finger on the cell being tapped.
        if let d = demoTap, d < n * n {
            let rc = rect(d).insetBy(dx: 2, dy: 2)
            ctx.stroke(Path(roundedRect: rc, cornerRadius: cell * 0.14), with: .color(.white), lineWidth: 3)
            var hand = ctx.resolve(Image(systemName: "hand.point.up.left.fill"))
            hand.shading = .color(.white)
            var h = ctx
            h.addFilter(.shadow(color: .black.opacity(0.6), radius: 3))
            let hw = cell * 0.55
            h.draw(hand, in: CGRect(x: rc.midX, y: rc.midY + cell * 0.05, width: hw, height: hw))
        }
    }
    private var timeBar: some View {
        GeometryReader { geo in
            let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.25))
                Capsule().fill(frac < 0.3 ? .red : BananaTheme.banana).frame(width: geo.size.width * frac)
            }
        }
    }

    // MARK: Input
    private func tap(_ idx: Int) {
        guard phase == .play, clues[idx] == nil, idx < mark.count else { return }
        mark[idx] = (mark[idx] + 1) % 3
        SoundManager.shared.tap(); Haptics.tap()
        if seaCount == seaNeeded, isSolved() { win() }
    }

    // MARK: Win check
    private func isSolved() -> Bool {
        let total = boardN * boardN
        let sea = (0..<total).filter { mark[$0] == 1 }
        let land = (0..<total).filter { mark[$0] != 1 }
        if sea.isEmpty { return false }
        // sea: single body, no 2×2
        var seaGrid = [Int](repeating: 1, count: total)     // 1 = land here (so 0 marks sea for helpers)
        for s in sea { seaGrid[s] = 0 }
        if NKGen.has2x2Water(seaGrid, boardN) { return false }
        if !NKGen.waterConnected(sea, boardN) { return false }
        // islands: connected land components, one clue each, size == clue
        let landSet = Set(land)
        var seen = Set<Int>()
        for cell in land where !seen.contains(cell) {
            var comp: [Int] = []
            var stack = [cell]; seen.insert(cell)
            while let cur = stack.popLast() {
                comp.append(cur)
                for nb in NKGen.orth(cur, boardN) where landSet.contains(nb) && !seen.contains(nb) {
                    seen.insert(nb); stack.append(nb)
                }
            }
            let clueCells = comp.filter { clues[$0] != nil }
            if clueCells.count != 1 { return false }
            if comp.count != clues[clueCells[0]]! { return false }
        }
        return true
    }

    // MARK: Demo (live manual clip)
    // A Level-1-sized 5×5 board with a unique solution (verified by exhaustive island search):
    //   # 3 # # #
    //   # . # 3 #
    //   # . # . #
    //   # # # . #
    //   # 1 # # #
    // The demo solves it through the real `tap`: seal the 1, dot the first 3's body and sea its
    // shore, dot the second 3, then flood the rest. The last sea tap triggers the real win check.
    private static let demoClues: [Int: Int] = [1: 3, 8: 3, 21: 1]
    /// (cell, taps): 1 tap = sea, 2 taps = dotted land.
    private static let demoMoves: [(Int, Int)] = [
        (16, 1), (20, 1), (22, 1),
        (6, 2), (11, 2),
        (0, 1), (2, 1), (5, 1), (7, 1), (10, 1), (12, 1), (15, 1), (17, 1),
        (13, 2), (18, 2),
        (3, 1), (4, 1), (9, 1), (14, 1), (19, 1), (23, 1), (24, 1),
    ]

    private func demoSetup() {
        boardN = 5
        clues = Self.demoClues
        mark = [Int](repeating: 0, count: 25)
        demoTap = nil
        timeLeft = timeLimit
        phase = .play
        ready = true
    }

    private func runDemo() async {
        while !Task.isCancelled {
            demoSetup()
            try? await Task.sleep(for: .seconds(0.6))
            for (idx, taps) in Self.demoMoves {
                guard !Task.isCancelled else { return }
                demoTap = idx
                for _ in 0..<taps {
                    try? await Task.sleep(for: .seconds(0.13))
                    guard !Task.isCancelled else { return }
                    tap(idx)
                }
                try? await Task.sleep(for: .seconds(0.12))
            }
            demoTap = nil
            // The last sea tap made a legal board → the real win() ran (onWin is a no-op).
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    // MARK: Flow
    /// Hands this level's board build to `BoardCache` so it can run during the countdown.
    func prefetchBoard() {
        let size = n, ic = islandCount, ms = maxSize
        BoardCache.prefetch(boardKey) { NKGen.generate(n: size, islandCount: ic, maxSize: ms) }
    }
    private var boardKey: String { BoardCache.key("nurikabe", level: level) }

    private func run() async {
        let size = n, ic = islandCount, ms = maxSize
        let t0 = Date()
        let puzzle = await BoardCache.take(boardKey) { NKGen.generate(n: size, islandCount: ic, maxSize: ms) }
        guard !Task.isCancelled else { return }
        await BoardCache.holdBrainstorm(since: t0, minimum: 0.7)
        guard !Task.isCancelled else { return }

        boardN = puzzle.n
        clues = puzzle.clues
        mark = [Int](repeating: 0, count: puzzle.n * puzzle.n)
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

    private func win() {
        guard phase != .done else { return }
        phase = .done; loopTask?.cancel(); onWin()
    }
    private func fail() {
        guard phase != .done else { return }
        phase = .done; loopTask?.cancel(); SoundManager.shared.error(); onFail()
    }
}

// MARK: - Island art

private enum IslandArt {
    static func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    /// Turquoise lagoon water with soft wave marks.
    static func sea(_ ctx: GraphicsContext, _ b: CGRect, cell: CGFloat) {
        ctx.fill(Path(roundedRect: b, cornerRadius: 8),
                 with: .linearGradient(Gradient(colors: [c(0.12, 0.72, 0.8), c(0.05, 0.5, 0.7)]),
                                       startPoint: CGPoint(x: b.minX, y: b.minY), endPoint: CGPoint(x: b.maxX, y: b.maxY)))
        var g = ctx
        g.clip(to: Path(roundedRect: b, cornerRadius: 8))
        var y = b.minY + cell * 0.3
        var row = 0
        while y < b.maxY {
            var x = b.minX + CGFloat(row % 2) * cell * 0.5
            while x < b.maxX {
                var wave = Path()
                wave.move(to: CGPoint(x: x, y: y))
                wave.addQuadCurve(to: CGPoint(x: x + cell * 0.22, y: y), control: CGPoint(x: x + cell * 0.11, y: y - cell * 0.08))
                g.stroke(wave, with: .color(.white.opacity(0.28)), lineWidth: max(1, cell * 0.03))
                x += cell
            }
            y += cell * 0.5
            row += 1
        }
    }

    /// A clue island cell: a little palm tree and the island's size.
    static func clue(_ ctx: GraphicsContext, _ r: CGRect, number: Int) {
        let s = r.width
        let base = CGPoint(x: r.minX + s * 0.26, y: r.minY + s * 0.72)
        let top = CGPoint(x: r.minX + s * 0.34, y: r.minY + s * 0.24)
        var trunk = Path()
        trunk.move(to: base)
        trunk.addQuadCurve(to: top, control: CGPoint(x: r.minX + s * 0.2, y: r.minY + s * 0.45))
        ctx.stroke(trunk, with: .color(c(0.55, 0.36, 0.18)), style: StrokeStyle(lineWidth: s * 0.06, lineCap: .round))
        for a in [-150.0, -110.0, -70.0, -30.0, 10.0] {
            let rad = a * .pi / 180
            let tip = CGPoint(x: top.x + CGFloat(cos(rad)) * s * 0.24, y: top.y + CGFloat(sin(rad)) * s * 0.16 + s * 0.06)
            var frond = Path()
            frond.move(to: top)
            frond.addQuadCurve(to: tip, control: CGPoint(x: (top.x + tip.x) / 2, y: min(top.y, tip.y) - s * 0.06))
            ctx.stroke(frond, with: .color(c(0.18, 0.6, 0.24)), style: StrokeStyle(lineWidth: s * 0.07, lineCap: .round))
        }
        let text = Text("\(number)").font(.system(size: s * 0.5, weight: .black, design: .rounded))
        let p = CGPoint(x: r.midX + s * 0.1, y: r.midY + s * 0.04)
        let outline = ctx.resolve(text.foregroundStyle(.white))
        for k in 0..<8 {
            let a = Double(k) * .pi / 4
            ctx.draw(outline, at: CGPoint(x: p.x + CGFloat(cos(a)) * s * 0.035, y: p.y + CGFloat(sin(a)) * s * 0.035))
        }
        ctx.draw(ctx.resolve(text.foregroundStyle(c(0.42, 0.24, 0.1))), at: p)
    }

    /// A pink scallop shell — the "definitely land" pencil mark.
    static func shell(_ ctx: GraphicsContext, at p: CGPoint, size s: CGFloat) {
        var fan = Path()
        fan.move(to: CGPoint(x: p.x, y: p.y + s * 0.45))
        fan.addLine(to: CGPoint(x: p.x - s * 0.5, y: p.y - s * 0.05))
        fan.addQuadCurve(to: CGPoint(x: p.x + s * 0.5, y: p.y - s * 0.05), control: CGPoint(x: p.x, y: p.y - s * 0.75))
        fan.closeSubpath()
        ctx.fill(fan, with: .linearGradient(Gradient(colors: [c(1, 0.8, 0.78), c(0.95, 0.55, 0.55)]),
                                            startPoint: CGPoint(x: p.x, y: p.y - s * 0.4), endPoint: CGPoint(x: p.x, y: p.y + s * 0.45)))
        var ribs = Path()
        for k in -2...2 {
            ribs.move(to: CGPoint(x: p.x, y: p.y + s * 0.42))
            ribs.addLine(to: CGPoint(x: p.x + CGFloat(k) * s * 0.18, y: p.y - s * 0.3 + abs(CGFloat(k)) * s * 0.08))
        }
        ctx.stroke(ribs, with: .color(c(0.8, 0.4, 0.4)), lineWidth: max(0.8, s * 0.05))
        ctx.stroke(fan, with: .color(c(0.7, 0.32, 0.32)), lineWidth: max(0.8, s * 0.05))
    }
}

/// Deep ocean around the lagoon, with sun sparkles (static).
private struct OceanBackdrop: View, Equatable {
    var body: some View {
        Canvas { ctx, s in
            ctx.fill(Path(CGRect(origin: .zero, size: s)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.06, green: 0.46, blue: 0.66), Color(red: 0.02, green: 0.2, blue: 0.4)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height)))
            for k in 0..<40 {
                let fx = CGFloat((sin(Double(k) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)).magnitude
                let fy = CGFloat((sin(Double(k) * 78.233) * 24634.6345).truncatingRemainder(dividingBy: 1)).magnitude
                var wave = Path()
                let p = CGPoint(x: fx * s.width, y: fy * s.height)
                wave.move(to: p)
                wave.addQuadCurve(to: CGPoint(x: p.x + 16, y: p.y), control: CGPoint(x: p.x + 8, y: p.y - 5))
                ctx.stroke(wave, with: .color(.white.opacity(0.18)), lineWidth: 1.5)
            }
        }
        .allowsHitTesting(false)
    }
}
