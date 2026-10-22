//
//  TentsTreesGame.swift
//  A Banana Game
//
//  Brain — Tents & Trees. Pitch one tent next to every tree. Tap a cell to cycle empty → tent →
//  grass (an X you can pencil in) → empty. Three rules must all hold at once:
//    • Each tree has exactly one tent orthogonally beside it, one tent per tree (a perfect pairing).
//    • No two tents touch — not even diagonally.
//    • The tents in each row and column match the numbers along the edges.
//  Solve the whole grid before the clock runs out or you drop back to level 1.
//
//  Every board is built solved-first: non-touching tents are scattered, each is given an adjacent
//  tree, and the row/column totals are read off that layout — so a legal solution always exists and
//  the board never starts with tents on it. The win check re-proves a full tree↔tent matching, so
//  only a genuinely correct field wins. Generation runs off-main behind the shared brainstorming
//  banana. Seven levels grow the grid (5×5 → 8×8) and the tent count while the clock tightens.
//
//  Drawn like Frozax's Tents and Trees: a warm peach card, dark undecided plots, bright lime grass
//  marks, low-poly trees and little red tents standing on grass, and the clue numbers in slim
//  strips (dark while short, green when met, red when over). The grid is an Equatable view so the
//  clock doesn't redraw it; every cell keeps a square button, sized so the grid fits the card (the
//  old one ran a few points past the screen edge at 6–8 columns).
//

import SwiftUI

enum TentsTreesGame {
    static let definition = GameDefinition(
        id: "tents-trees",
        title: "Tents & Trees",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Tap a cell to cycle empty → tent → grass → empty.",
                "Give every tree exactly one tent orthogonally beside it (one tent per tree).",
                "Two tents may never touch, even diagonally.",
                "Match the tent totals on each row and column; solve the grid before time runs out.",
            ],
            bulletsVI: [
                "Chạm một ô để luân chuyển trống → lều → cỏ → trống.",
                "Mỗi cây phải có đúng một lều kề bên (một lều cho mỗi cây).",
                "Hai lều không bao giờ được chạm nhau, kể cả theo đường chéo.",
                "Khớp tổng số lều ở mỗi hàng và cột; giải lưới trước khi hết giờ.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(TentsTreesView(level: level, onWin: onWin, onFail: onFail))
        },
        prefetch: { level in TentsTreesView(level: level, onWin: {}, onFail: {}).prefetchBoard() }
    )
}

private struct TentsBoard: Sendable {
    let n: Int
    let trees: [Int]
    let rowCounts: [Int]
    let colCounts: [Int]
}

private enum TentsGen {
    static func orthNeighbors(_ cell: Int, _ n: Int) -> [Int] {
        let r = cell / n, c = cell % n
        var out: [Int] = []
        if r > 0 { out.append((r - 1) * n + c) }
        if r < n - 1 { out.append((r + 1) * n + c) }
        if c > 0 { out.append(r * n + c - 1) }
        if c < n - 1 { out.append(r * n + c + 1) }
        return out
    }

    static func eightNeighbors(_ cell: Int, _ n: Int) -> [Int] {
        let r = cell / n, c = cell % n
        var out: [Int] = []
        for dr in -1...1 {
            for dc in -1...1 where !(dr == 0 && dc == 0) {
                let nr = r + dr, nc = c + dc
                if nr >= 0, nr < n, nc >= 0, nc < n { out.append(nr * n + nc) }
            }
        }
        return out
    }

    static func generate(n: Int, tentTarget: Int) -> TentsBoard {
        for _ in 0..<400 {
            // 1) scatter non-touching tents
            var tents: [Int] = []
            var blocked = Set<Int>()
            for cell in Array(0..<n * n).shuffled() {
                if tents.count == tentTarget { break }
                if blocked.contains(cell) { continue }
                tents.append(cell)
                blocked.insert(cell)
                for nb in eightNeighbors(cell, n) { blocked.insert(nb) }
            }
            guard tents.count == tentTarget else { continue }

            // 2) give each tent its own adjacent tree (distinct cell, not on a tent)
            let tentSet = Set(tents)
            var trees = Set<Int>()
            var ok = true
            for tent in tents.shuffled() {
                let options = orthNeighbors(tent, n).filter { !tentSet.contains($0) && !trees.contains($0) }
                guard let tree = options.randomElement() else { ok = false; break }
                trees.insert(tree)
            }
            guard ok, trees.count == tentTarget else { continue }

            // 3) read off the row/column totals
            var rowCounts = [Int](repeating: 0, count: n)
            var colCounts = [Int](repeating: 0, count: n)
            for t in tents { rowCounts[t / n] += 1; colCounts[t % n] += 1 }

            return TentsBoard(n: n, trees: Array(trees), rowCounts: rowCounts, colCounts: colCounts)
        }
        // Fallback: trees down the diagonal, tents to their right.
        var trees: [Int] = []
        var rowCounts = [Int](repeating: 0, count: n)
        var colCounts = [Int](repeating: 0, count: n)
        for r in 0..<min(tentTarget, n) {
            trees.append(r * n + 0)
            rowCounts[r] += 1; colCounts[min(1, n - 1)] += 1
        }
        return TentsBoard(n: n, trees: trees, rowCounts: rowCounts, colCounts: colCounts)
    }
}

struct TentsTreesView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void
    @Environment(\.isDemo) private var isDemo

    private var n: Int { [5, 6, 6, 7, 7, 8, 8][min(level, 7) - 1] }
    private var tentTarget: Int { [4, 6, 7, 9, 10, 12, 13][min(level, 7) - 1] }
    private var timeLimit: Double { [70, 75, 80, 85, 85, 80, 75][min(level, 7) - 1] }

    private let skyTop = Color(red: 0.09, green: 0.15, blue: 0.13)
    private let skyBottom = Color(red: 0.03, green: 0.06, blue: 0.05)

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var boardN = 0
    @State private var trees: Set<Int> = []
    @State private var tents: Set<Int> = []
    @State private var grass: Set<Int> = []
    @State private var rowCounts: [Int] = []
    @State private var colCounts: [Int] = []
    @State private var timeLeft = 0.0
    @State private var ready = false
    @State private var loopTask: Task<Void, Never>?
    @State private var demoCell: Int? = nil       // demo: cell being tapped (finger + ring)

    var body: some View {
        Group {
            if ready { gameBody } else { BrainstormingView(skyTop: skyTop, skyBottom: skyBottom) }
        }
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
    }

    private var gameBody: some View {
        VStack(spacing: isDemo ? 4 : 12) {
            HStack(spacing: 8) {
                TTArt.tentIcon.frame(width: isDemo ? 18 : 24, height: isDemo ? 15 : 20)
                Text("\(tents.count)/\(trees.count)")
                    .font(.system(size: isDemo ? 15 : 20, weight: .black, design: .rounded))
                    .foregroundStyle(TTArt.ink)
                    .contentTransition(.numericText())
            }
            if !isDemo { timeBar.frame(height: 6).padding(.horizontal, 50) }

            GeometryReader { geo in
                TTGrid(size: geo.size, n: boardN, trees: trees, tents: tents, grass: grass,
                       rowCounts: rowCounts, colCounts: colCounts, demoCell: isDemo ? demoCell : nil,
                       enabled: phase != .done || isDemo, onTap: { tap($0) })
                    .equatable()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, isDemo ? 6 : 10)
        .background(TTArt.backdrop)
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(TTArt.ink.opacity(0.14))
                Capsule().fill(frac < 0.3 ? Color(red: 0.86, green: 0.25, blue: 0.2) : Color(red: 0.4, green: 0.62, blue: 0.24))
                    .frame(width: geo.size.width * frac)
            }
        }
    }

    private func rowTentCount(_ r: Int) -> Int { tents.filter { $0 / boardN == r }.count }
    private func colTentCount(_ c: Int) -> Int { tents.filter { $0 % boardN == c }.count }

    // MARK: Input
    private func tap(_ idx: Int) {
        guard phase == .play, !trees.contains(idx) else { return }
        if tents.contains(idx) {
            tents.remove(idx); grass.insert(idx)
        } else if grass.contains(idx) {
            grass.remove(idx)
        } else {
            tents.insert(idx)
        }
        SoundManager.shared.tap(); Haptics.tap()
        if isSolved() { win() }
    }

    // MARK: Win check
    private func isSolved() -> Bool {
        let n = boardN
        if tents.count != trees.count { return false }
        for r in 0..<n where rowTentCount(r) != rowCounts[r] { return false }
        for c in 0..<n where colTentCount(c) != colCounts[c] { return false }
        // no two tents touch (8-directional)
        for t in tents {
            for nb in TentsGen.eightNeighbors(t, n) where tents.contains(nb) { return false }
        }
        // perfect tree↔tent matching over orthogonal adjacency
        return hasPerfectMatching()
    }

    private func hasPerfectMatching() -> Bool {
        let tentList = Array(tents)
        let treeList = Array(trees)
        var treeIndex: [Int: Int] = [:]
        for (i, t) in treeList.enumerated() { treeIndex[t] = i }
        let adj: [[Int]] = tentList.map { tent in
            TentsGen.orthNeighbors(tent, boardN).compactMap { treeIndex[$0] }
        }
        var matchTree = [Int](repeating: -1, count: treeList.count)
        func augment(_ u: Int, _ visited: inout [Bool]) -> Bool {
            for v in adj[u] where !visited[v] {
                visited[v] = true
                if matchTree[v] == -1 || augment(matchTree[v], &visited) {
                    matchTree[v] = u
                    return true
                }
            }
            return false
        }
        var matched = 0
        for u in tentList.indices {
            var visited = [Bool](repeating: false, count: treeList.count)
            if augment(u, &visited) { matched += 1 }
        }
        return matched == tentList.count
    }

    // MARK: Flow
    /// Hands this level's board build to `BoardCache` so it can run during the countdown.
    func prefetchBoard() {
        let size = n, target = tentTarget
        BoardCache.prefetch(boardKey) { TentsGen.generate(n: size, tentTarget: target) }
    }
    private var boardKey: String { BoardCache.key("tents-trees", level: level) }

    private func run() async {
        let size = n, target = tentTarget
        let t0 = Date()
        let board = await BoardCache.take(boardKey) { TentsGen.generate(n: size, tentTarget: target) }
        guard !Task.isCancelled else { return }
        await BoardCache.holdBrainstorm(since: t0, minimum: 0.7)
        guard !Task.isCancelled else { return }

        boardN = board.n
        trees = Set(board.trees)
        tents = []
        grass = []
        rowCounts = board.rowCounts
        colCounts = board.colCounts
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
    // A fixed level-1 board (5×5, four trees) with a unique solution — checked offline by trying
    // every legal tent placement — solved by deduction through the real `tap`, grass marks included:
    //   · · · · ·  0     row 4 needs 2 but column 3 is empty and 20/21 touch → 24 + one of 20/21;
    //   · · · T ·  1     tree 22 can only take 21 (17 is in the empty row 3) → tents 24, 21;
    //   · T · · ·  1     column 4 is now full → grass 9 → tree 8 takes 7; column 2 full →
    //   · · · · T  0     grass 12 → tree 11 takes 10. The 4th tent is the real win().
    //   · · T · ·  2
    //   1 1 1 0 1
    private static let demoTrees: Set<Int> = [8, 11, 19, 22]
    private static let demoRows = [0, 1, 1, 0, 2]
    private static let demoCols = [1, 1, 1, 0, 1]
    // (cell, taps): 1 tap = tent, 2 taps = grass (empty → tent → grass).
    private static let demoMoves: [(cell: Int, taps: Int)] = [
        (23, 2), (24, 1), (21, 1), (9, 2), (7, 1), (12, 2), (10, 1)
    ]

    private func runDemo() async {
        while !Task.isCancelled {
            boardN = 5
            trees = Self.demoTrees
            tents = []
            grass = []
            rowCounts = Self.demoRows
            colCounts = Self.demoCols
            demoCell = nil
            timeLeft = timeLimit
            phase = .play
            ready = true
            try? await Task.sleep(for: .seconds(0.8))
            for move in Self.demoMoves {
                guard !Task.isCancelled else { return }
                demoCell = move.cell
                try? await Task.sleep(for: .seconds(0.25))
                for k in 0..<move.taps {
                    guard !Task.isCancelled else { return }
                    if k > 0 { try? await Task.sleep(for: .seconds(0.22)) }
                    tap(move.cell)
                }
                try? await Task.sleep(for: .seconds(0.35))
            }
            demoCell = nil
            // All four tents legal → the real win() ran (onWin is a no-op). Hold, then loop.
            try? await Task.sleep(for: .seconds(1.3))
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

// MARK: - Campsite art (after Frozax's Tents and Trees)

private enum TTArt {
    static let ink = Color(red: 0.3, green: 0.27, blue: 0.25)
    static let met = Color(red: 0.36, green: 0.6, blue: 0.24)
    static let over = Color(red: 0.86, green: 0.25, blue: 0.2)
    static let backdrop = LinearGradient(colors: [Color(red: 0.99, green: 0.91, blue: 0.83), Color(red: 0.96, green: 0.84, blue: 0.74)],
                                         startPoint: .top, endPoint: .bottom)
    static var tentIcon: some View {
        Canvas { ctx, size in tent(ctx, in: CGRect(origin: .zero, size: size)) }
    }

    private static func quad(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Path {
        var p = Path()
        p.move(to: a); p.addLine(to: b); p.addLine(to: c); p.addLine(to: d)
        p.closeSubpath()
        return p
    }

    /// A little red tent (a prism seen from the front-left) filling `r`.
    static func tent(_ ctx: GraphicsContext, in r: CGRect) {
        let p = { (x: CGFloat, y: CGFloat) in CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        ctx.fill(Path(ellipseIn: CGRect(x: r.minX + r.width * 0.1, y: r.minY + r.height * 0.82, width: r.width * 0.84, height: r.height * 0.14)),
                 with: .color(.black.opacity(0.18)))
        ctx.fill(quad(p(0.42, 0.1), p(0.64, 0.04), p(0.94, 0.8), p(0.72, 0.88)), with: .color(Color(red: 0.66, green: 0.2, blue: 0.12)))
        var front = Path()
        front.move(to: p(0.42, 0.1)); front.addLine(to: p(0.72, 0.88)); front.addLine(to: p(0.08, 0.88)); front.closeSubpath()
        ctx.fill(front, with: .color(Color(red: 0.9, green: 0.34, blue: 0.2)))
        var door = Path()
        door.move(to: p(0.42, 0.42)); door.addLine(to: p(0.54, 0.88)); door.addLine(to: p(0.3, 0.88)); door.closeSubpath()
        ctx.fill(door, with: .color(Color(red: 0.42, green: 0.12, blue: 0.07)))
    }

    /// A low-poly tree: three stacked green blocks on a short trunk.
    static func tree(_ ctx: GraphicsContext, in r: CGRect) {
        let s = r.width
        let ox = r.minX, oy = r.minY
        ctx.fill(Path(ellipseIn: CGRect(x: ox + s * 0.22, y: oy + s * 0.8, width: s * 0.56, height: s * 0.12)), with: .color(.black.opacity(0.18)))
        ctx.fill(Path(CGRect(x: ox + s * 0.44, y: oy + s * 0.66, width: s * 0.12, height: s * 0.2)), with: .color(Color(red: 0.5, green: 0.32, blue: 0.16)))
        let tiers: [(w: CGFloat, top: CGFloat, bottom: CGFloat)] = [(0.6, 0.5, 0.72), (0.44, 0.32, 0.52), (0.28, 0.14, 0.34)]
        for t in tiers {
            let l = ox + s * (0.5 - t.w / 2), rr = ox + s * (0.5 + t.w / 2)
            let top = oy + s * t.top, bottom = oy + s * t.bottom
            let dx = s * 0.07, dy = s * 0.06
            ctx.fill(quad(CGPoint(x: rr, y: top), CGPoint(x: rr + dx, y: top - dy), CGPoint(x: rr + dx, y: bottom - dy), CGPoint(x: rr, y: bottom)),
                     with: .color(Color(red: 0.18, green: 0.44, blue: 0.2)))
            ctx.fill(quad(CGPoint(x: l, y: top), CGPoint(x: l + dx, y: top - dy), CGPoint(x: rr + dx, y: top - dy), CGPoint(x: rr, y: top)),
                     with: .color(Color(red: 0.5, green: 0.8, blue: 0.38)))
            ctx.fill(Path(CGRect(x: l, y: top, width: rr - l, height: bottom - top)), with: .color(Color(red: 0.3, green: 0.62, blue: 0.28)))
        }
    }

    /// One plot: 0 undecided (dark), 1 tree, 2 tent, 3 grass mark (lime with tufts).
    static func cell(_ ctx: GraphicsContext, size: CGSize, kind: Int, alt: Bool) {
        let r = CGRect(origin: .zero, size: size)
        let tile = Path(roundedRect: r, cornerRadius: size.width * 0.12)
        switch kind {
        case 0:
            ctx.fill(tile, with: .color(alt ? Color(red: 0.26, green: 0.28, blue: 0.29) : Color(red: 0.23, green: 0.25, blue: 0.26)))
            ctx.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.12), cornerRadius: size.width * 0.12),
                     with: .color(.white.opacity(0.05)))
        case 3:
            ctx.fill(tile, with: .color(Color(red: 0.74, green: 0.87, blue: 0.4)))
            var blades = Path()
            for (x, y) in [(0.28, 0.4), (0.66, 0.34), (0.46, 0.72)] as [(CGFloat, CGFloat)] {
                let base = CGPoint(x: size.width * x, y: size.height * y)
                for dx in [-0.07, 0.0, 0.07] as [CGFloat] {
                    blades.move(to: base)
                    blades.addLine(to: CGPoint(x: base.x + size.width * dx, y: base.y - size.height * 0.12))
                }
            }
            ctx.stroke(blades, with: .color(Color(red: 0.46, green: 0.68, blue: 0.22)), style: StrokeStyle(lineWidth: max(1, size.width * 0.035), lineCap: .round))
        default:
            ctx.fill(tile, with: .color(Color(red: 0.6, green: 0.8, blue: 0.34)))
            if kind == 1 { tree(ctx, in: r.insetBy(dx: size.width * 0.02, dy: size.height * 0.02)) }
            else { tent(ctx, in: r.insetBy(dx: size.width * 0.12, dy: size.height * 0.14)) }
        }
    }
}

/// The campsite grid. Equatable (the tap closure is left out) so the clock doesn't redraw it. Cells
/// are square buttons; the clue strips are 0.6 of a cell so the whole grid fits the card.
private struct TTGrid: View, Equatable {
    let size: CGSize
    let n: Int
    let trees: Set<Int>
    let tents: Set<Int>
    let grass: Set<Int>
    let rowCounts: [Int]
    let colCounts: [Int]
    let demoCell: Int?
    let enabled: Bool
    let onTap: (Int) -> Void

    static func == (l: TTGrid, r: TTGrid) -> Bool {
        l.size == r.size && l.n == r.n && l.trees == r.trees && l.tents == r.tents && l.grass == r.grass
            && l.rowCounts == r.rowCounts && l.colCounts == r.colCounts && l.demoCell == r.demoCell && l.enabled == r.enabled
    }

    var body: some View {
        let gap: CGFloat = 3
        let cell = n > 0 ? floor(min((size.width - gap * CGFloat(n) - 12) / (CGFloat(n) + 0.6),
                                     (size.height - gap * CGFloat(n)) / (CGFloat(n) + 0.6))) : 0
        let strip = cell * 0.6
        VStack(spacing: gap) {
            HStack(spacing: gap) {
                Color.clear.frame(width: strip, height: strip)
                ForEach(0..<n, id: \.self) { c in
                    label(current: tents.filter { $0 % n == c }.count, target: c < colCounts.count ? colCounts[c] : 0, cell: cell)
                        .frame(width: cell, height: strip)
                }
            }
            ForEach(0..<n, id: \.self) { r in
                HStack(spacing: gap) {
                    label(current: tents.filter { $0 / n == r }.count, target: r < rowCounts.count ? rowCounts[r] : 0, cell: cell)
                        .frame(width: strip, height: cell)
                    ForEach(0..<n, id: \.self) { c in
                        cellButton(r * n + c, alt: (r + c) % 2 == 0, cell: cell)
                            .zIndex(demoCell == r * n + c ? 1 : 0)
                    }
                }
                .zIndex(demoCell.map { $0 / max(n, 1) == r } == true ? 1 : 0)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func label(current: Int, target: Int, cell: CGFloat) -> some View {
        Text("\(target)")
            .font(.system(size: cell * 0.44, weight: .heavy, design: .rounded))
            .foregroundStyle(current == target ? TTArt.met : (current > target ? TTArt.over : TTArt.ink))
    }

    private func cellButton(_ idx: Int, alt: Bool, cell: CGFloat) -> some View {
        let kind = trees.contains(idx) ? 1 : tents.contains(idx) ? 2 : grass.contains(idx) ? 3 : 0
        return Button { onTap(idx) } label: {
            Canvas { ctx, size in TTArt.cell(ctx, size: size, kind: kind, alt: alt) }
                .frame(width: cell, height: cell)
                .overlay {
                    // Demo: the tapped cell rings up under a finger.
                    if demoCell == idx {
                        RoundedRectangle(cornerRadius: cell * 0.12).stroke(TTArt.ink, lineWidth: 2.5)
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.system(size: cell * 0.46))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 3)
                            .offset(x: cell * 0.3, y: cell * 0.36)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
