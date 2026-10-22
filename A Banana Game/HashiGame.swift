//
//  HashiGame.swift
//  A Banana Game
//
//  Brain — Hashiwokakero ("bridges"). Numbered islands float on a grid; the number is how many
//  bridges must touch that island. Tap one island, then a second island in the same row or column,
//  to lay a bridge between them; tap the pair again to double it, once more to clear it. Bridges run
//  straight, never cross, and at most two link any pair. Satisfy every island's number and join them
//  all into one network before the clock runs out.
//
//  Boards are built by growing a connected web of islands (each new island bridged to the existing
//  web, then extra cross-links added) so the clue numbers are exactly one real solution's degrees —
//  always solvable, never pre-solved. The generator runs off-main behind the brainstorming banana.
//  Levels add islands and grid size: level 1 is a gentle four-island warm-up, levels 6–7 are dense.
//
//  Drawn as an archipelago: a deep sea with swell lines, round sandy islands in a ring of surf whose
//  clue sits on a painted disc (white, green when met, red when over), and wooden plank bridges with
//  rope rails (a double bridge is two decks side by side). The board is an Equatable view so the
//  clock doesn't redraw it, and each island keeps its old circular tap area.
//

import SwiftUI

private nonisolated struct HIsland: Sendable { let r: Int; let c: Int; var need: Int }
private nonisolated struct HashiPuzzle: Sendable { let gridN: Int; let islands: [HIsland] }

private struct HPair: Hashable { let a: Int; let b: Int
    init(_ x: Int, _ y: Int) { a = min(x, y); b = max(x, y) }
}

enum HashiGame {
    static let definition = GameDefinition(
        id: "hashi-bridges",
        title: "Bridges",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Each island's number is how many bridges must connect to it.",
                "Tap two islands in the same row or column to build; tap again to double, a third time to clear.",
                "Bridges are straight, never cross, and max two per pair.",
                "Match every number and join all islands into one network before time runs out.",
            ],
            bulletsVI: [
                "Con số trên mỗi đảo là số cầu phải nối vào nó.",
                "Chạm hai đảo cùng hàng hoặc cột để nối; chạm lại thành cầu đôi, lần ba để xóa.",
                "Cầu đi thẳng, không cắt nhau, tối đa hai cầu mỗi cặp.",
                "Khớp mọi con số và nối tất cả các đảo thành một mạng trước khi hết giờ.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(HashiView(level: level, onWin: onWin, onFail: onFail))
        },
        prefetch: { level in HashiView(level: level, onWin: {}, onFail: {}).prefetchBoard() }
    )
}

struct HashiView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void
    @Environment(\.isDemo) private var isDemo

    private var targetIslands: Int { [4, 6, 8, 10, 12, 14, 16][min(level, 7) - 1] }
    private var gridSize: Int { [5, 6, 7, 7, 8, 8, 9][min(level, 7) - 1] }
    private var timeLimit: Double { [55, 75, 95, 115, 130, 140, 150][min(level, 7) - 1] }

    private var skyTop: Color {
        [Color(red: 0.06, green: 0.13, blue: 0.22), Color(red: 0.06, green: 0.12, blue: 0.21),
         Color(red: 0.05, green: 0.11, blue: 0.20), Color(red: 0.05, green: 0.10, blue: 0.19),
         Color(red: 0.04, green: 0.09, blue: 0.18), Color(red: 0.04, green: 0.08, blue: 0.16),
         Color(red: 0.03, green: 0.07, blue: 0.15)][min(level, 7) - 1]
    }
    private var skyBottom: Color {
        [Color(red: 0.03, green: 0.07, blue: 0.13), Color(red: 0.03, green: 0.06, blue: 0.12),
         Color(red: 0.02, green: 0.06, blue: 0.12), Color(red: 0.02, green: 0.05, blue: 0.11),
         Color(red: 0.02, green: 0.05, blue: 0.10), Color(red: 0.01, green: 0.04, blue: 0.09),
         Color(red: 0.01, green: 0.03, blue: 0.08)][min(level, 7) - 1]
    }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var ready = false
    @State private var gridN = 0
    @State private var islands: [HIsland] = []
    @State private var allowed: Set<HPair> = []
    @State private var interior: [HPair: Set<Int>] = [:]
    @State private var bridges: [HPair: Int] = [:]
    @State private var selected: Int? = nil
    @State private var timeLeft = 0.0
    @State private var loopTask: Task<Void, Never>?
    @State private var demoFinger: Int? = nil     // demo: island being tapped (finger)

    private var solvedCount: Int {
        islands.indices.filter { degree($0) == islands[$0].need }.count
    }

    var body: some View {
        Group {
            if ready { gameBody } else { BrainstormingView(skyTop: skyTop, skyBottom: skyBottom) }
        }
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
    }

    private var gameBody: some View {
        VStack(spacing: isDemo ? 4 : 10) {
            HStack(spacing: 8) {
                HashiIslandIcon().frame(width: isDemo ? 16 : 20, height: isDemo ? 16 : 20)
                Text("\(solvedCount) / \(islands.count)")
                    .font(.system(size: isDemo ? 14 : 18, weight: .black, design: .rounded))
                    .foregroundStyle(solvedCount == islands.count ? BananaTheme.banana : .white)
                    .monospacedDigit()
            }
            .padding(.top, isDemo ? 6 : 0)
            if !isDemo { timeBar.frame(height: 5).padding(.horizontal, 60) }
            boardView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HashiSea().equatable())
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
    }

    private var boardView: some View {
        GeometryReader { geo in
            HashiBoard(size: geo.size, gridN: gridN, islands: islands.map { HashiBoard.Isle(r: $0.r, c: $0.c, need: $0.need) },
                       degrees: islands.indices.map { degree($0) },
                       bridges: bridges.filter { $0.value > 0 }.map { HashiBoard.Span(a: $0.key.a, b: $0.key.b, count: $0.value) }
                           .sorted { ($0.a, $0.b) < ($1.a, $1.b) },
                       selected: selected, finger: demoFinger, onTap: { tapIsland($0) })
                .equatable()
        }
        .padding(.horizontal, isDemo ? 0 : -8)
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(frac < 0.3 ? Color(red: 1, green: 0.35, blue: 0.3) : Color(red: 1, green: 0.9, blue: 0.62))
                    .frame(width: geo.size.width * frac)
            }
        }
    }

    // MARK: - Flow
    /// Hands this level's board build to `BoardCache` so it can run during the countdown.
    func prefetchBoard() {
        let g = gridSize, t = targetIslands
        BoardCache.prefetch(boardKey) { Self.makePuzzle(gridN: g, target: t) }
    }
    private var boardKey: String { BoardCache.key("hashi-bridges", level: level) }

    private func run() async {
        let g = gridSize, t = targetIslands
        let t0 = Date()
        let puzzle = await BoardCache.take(boardKey) { Self.makePuzzle(gridN: g, target: t) }
        guard !Task.isCancelled else { return }
        await BoardCache.holdBrainstorm(since: t0, minimum: 0.7)
        guard !Task.isCancelled else { return }
        commit(puzzle)
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
    // A fixed level-1 board (four islands on a 5×5 grid, like the generator's warm-up) with a
    // unique solution, checked offline by enumerating every 0/1/2 assignment of the 4 corridors:
    //   3 · · · 2        the 4 in the corner has only two neighbours → double to both;
    //   · · · · ·        that leaves the 3s needing one each, closed by single bridges
    //   · · · · ·        through the 2. Played in that order through the real `tapIsland`,
    //   · · · · ·        so the last single bridge is the real win().
    //   4 · · · 3
    private static let demoPuzzle = HashiPuzzle(gridN: 5, islands: [
        HIsland(r: 0, c: 0, need: 3), HIsland(r: 0, c: 4, need: 2),
        HIsland(r: 4, c: 0, need: 4), HIsland(r: 4, c: 4, need: 3)
    ])
    private static let demoTaps = [2, 0, 2, 0, 2, 3, 2, 3, 0, 1, 1, 3]

    private func runDemo() async {
        while !Task.isCancelled {
            commit(Self.demoPuzzle)
            demoFinger = nil
            timeLeft = timeLimit
            phase = .play
            ready = true
            try? await Task.sleep(for: .seconds(0.7))
            for i in Self.demoTaps {
                guard !Task.isCancelled else { return }
                demoFinger = i
                try? await Task.sleep(for: .seconds(0.22))
                guard !Task.isCancelled else { return }
                tapIsland(i)
                try? await Task.sleep(for: .seconds(0.3))
            }
            demoFinger = nil
            // Every island green and joined → the real win() ran (onWin is a no-op). Hold, then loop.
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    private func commit(_ p: HashiPuzzle) {
        gridN = p.gridN
        islands = p.islands
        bridges = [:]
        selected = nil
        // Geometric neighbours: same row/col, no island strictly between.
        var allow = Set<HPair>()
        var inter: [HPair: Set<Int>] = [:]
        let n = islands.count
        for i in 0..<n {
            for j in (i + 1)..<n {
                let A = islands[i], B = islands[j]
                if A.r == B.r {
                    let c1 = min(A.c, B.c), c2 = max(A.c, B.c)
                    if !islands.contains(where: { $0.r == A.r && $0.c > c1 && $0.c < c2 }) {
                        let pair = HPair(i, j)
                        allow.insert(pair)
                        inter[pair] = Set((c1 + 1..<c2).map { A.r * p.gridN + $0 })
                    }
                } else if A.c == B.c {
                    let r1 = min(A.r, B.r), r2 = max(A.r, B.r)
                    if !islands.contains(where: { $0.c == A.c && $0.r > r1 && $0.r < r2 }) {
                        let pair = HPair(i, j)
                        allow.insert(pair)
                        inter[pair] = Set((r1 + 1..<r2).map { $0 * p.gridN + A.c })
                    }
                }
            }
        }
        allowed = allow
        interior = inter
    }

    // MARK: - Input
    private func tapIsland(_ i: Int) {
        guard phase == .play else { return }
        guard let s = selected else { selected = i; SoundManager.shared.tap(); return }
        if s == i { selected = nil; return }
        selected = nil
        let pair = HPair(s, i)
        guard allowed.contains(pair) else { SoundManager.shared.error(); Haptics.warning(); return }
        toggle(pair)
    }

    private func toggle(_ pair: HPair) {
        let cur = bridges[pair] ?? 0
        if cur == 0 {
            if crosses(pair) { SoundManager.shared.error(); Haptics.warning(); return }
            bridges[pair] = 1
        } else if cur == 1 {
            bridges[pair] = 2
        } else {
            bridges[pair] = nil
        }
        SoundManager.shared.tap(); Haptics.tap()
        checkWin()
    }

    /// True if building `pair` would share a grid cell with an existing bridge.
    private func crosses(_ pair: HPair) -> Bool {
        guard let mine = interior[pair] else { return false }
        for (other, cnt) in bridges where cnt > 0 && other != pair {
            if let cells = interior[other], !cells.isDisjoint(with: mine) { return true }
        }
        return false
    }

    private func degree(_ i: Int) -> Int {
        var d = 0
        for (pair, cnt) in bridges where cnt > 0 && (pair.a == i || pair.b == i) { d += cnt }
        return d
    }

    private func checkWin() {
        for i in islands.indices where degree(i) != islands[i].need { return }
        guard isConnected() else { return }
        win()
    }

    private func isConnected() -> Bool {
        guard !islands.isEmpty else { return false }
        var adj = Array(repeating: [Int](), count: islands.count)
        for (pair, cnt) in bridges where cnt > 0 { adj[pair.a].append(pair.b); adj[pair.b].append(pair.a) }
        var seen = Set<Int>([0]); var stack = [0]
        while let cur = stack.popLast() {
            for nb in adj[cur] where !seen.contains(nb) { seen.insert(nb); stack.append(nb) }
        }
        return seen.count == islands.count
    }

    private func win() {
        guard phase != .done else { return }
        phase = .done; loopTask?.cancel(); onWin()
    }

    private func fail() {
        guard phase != .done else { return }
        phase = .done; loopTask?.cancel(); SoundManager.shared.error(); onFail()
    }

    // MARK: - Generation (pure / off-main)
    private nonisolated static func makePuzzle(gridN: Int, target: Int) -> HashiPuzzle {
        var best: HashiPuzzle?
        for _ in 0..<50 {
            let p = tryGenerate(gridN: gridN, target: target)
            if p.islands.count >= max(3, target - 2) { return p }
            if best == nil || p.islands.count > best!.islands.count { best = p }
        }
        return best ?? fallback()
    }

    private nonisolated static func tryGenerate(gridN: Int, target: Int) -> HashiPuzzle {
        var positions: [(r: Int, c: Int)] = []
        var need: [Int] = []
        var islandAt = Set<Int>()
        var bridgeCell = Set<Int>()
        func key(_ r: Int, _ c: Int) -> Int { r * gridN + c }

        let r0 = Int.random(in: 0..<gridN), c0 = Int.random(in: 0..<gridN)
        positions.append((r0, c0)); need.append(0); islandAt.insert(key(r0, c0))

        let dirs = [(0, 1), (0, -1), (1, 0), (-1, 0)]
        var tries = 0
        while positions.count < target && tries < target * 80 {
            tries += 1
            let ai = Int.random(in: 0..<positions.count)
            let (ar, ac) = positions[ai]
            let dir = dirs.randomElement()!
            let dist = Int.random(in: 2...4)
            let nr = ar + dir.0 * dist, nc = ac + dir.1 * dist
            guard nr >= 0, nr < gridN, nc >= 0, nc < gridN else { continue }
            guard !islandAt.contains(key(nr, nc)) else { continue }
            var interiorCells: [Int] = []
            var ok = true
            for step in 1..<dist {
                let ir = ar + dir.0 * step, ic = ac + dir.1 * step
                let ik = key(ir, ic)
                if islandAt.contains(ik) || bridgeCell.contains(ik) { ok = false; break }
                interiorCells.append(ik)
            }
            guard ok else { continue }
            let cnt = Int.random(in: 1...2)
            positions.append((nr, nc)); need.append(0); islandAt.insert(key(nr, nc))
            for ik in interiorCells { bridgeCell.insert(ik) }
            need[ai] += cnt; need[positions.count - 1] += cnt
        }

        // Extra cross-links between aligned islands (each corridor used once, 1–2 bridges).
        let n = positions.count
        for _ in 0..<(target * 6) {
            let i = Int.random(in: 0..<n), j = Int.random(in: 0..<n)
            guard i != j else { continue }
            let A = positions[i], B = positions[j]
            var interiorCells: [Int] = []
            var ok = true
            if A.r == B.r {
                let c1 = min(A.c, B.c), c2 = max(A.c, B.c)
                guard c2 - c1 >= 2 else { continue }
                for c in (c1 + 1)..<c2 {
                    let ik = key(A.r, c)
                    if islandAt.contains(ik) || bridgeCell.contains(ik) { ok = false; break }
                    interiorCells.append(ik)
                }
            } else if A.c == B.c {
                let r1 = min(A.r, B.r), r2 = max(A.r, B.r)
                guard r2 - r1 >= 2 else { continue }
                for r in (r1 + 1)..<r2 {
                    let ik = key(r, A.c)
                    if islandAt.contains(ik) || bridgeCell.contains(ik) { ok = false; break }
                    interiorCells.append(ik)
                }
            } else { continue }
            guard ok, !interiorCells.isEmpty else { continue }
            let cnt = Int.random(in: 1...2)
            guard need[i] + cnt <= 8, need[j] + cnt <= 8 else { continue }
            for ik in interiorCells { bridgeCell.insert(ik) }
            need[i] += cnt; need[j] += cnt
        }

        let islands = positions.enumerated().map { HIsland(r: $0.element.r, c: $0.element.c, need: need[$0.offset]) }
        return HashiPuzzle(gridN: gridN, islands: islands)
    }

    private nonisolated static func fallback() -> HashiPuzzle {
        // A 3×3 square of 4 islands, each needing 2 bridges (a ring). Always solvable.
        [HIsland(r: 0, c: 0, need: 2), HIsland(r: 0, c: 2, need: 2),
         HIsland(r: 2, c: 0, need: 2), HIsland(r: 2, c: 2, need: 2)]
            .withGrid(3)
    }
}

private extension Array where Element == HIsland {
    func withGrid(_ n: Int) -> HashiPuzzle { HashiPuzzle(gridN: n, islands: self) }
}

// MARK: - Archipelago art

/// The board: plank bridges under sandy islands. Equatable (the tap closure is left out), so the
/// 20 Hz clock doesn't redraw it. Each island keeps the old circular tap area (0.72 of a cell).
private struct HashiBoard: View, Equatable {
    struct Isle: Equatable { let r: Int; let c: Int; let need: Int }
    struct Span: Equatable { let a: Int; let b: Int; let count: Int }

    let size: CGSize
    let gridN: Int
    let islands: [Isle]
    let degrees: [Int]
    let bridges: [Span]
    let selected: Int?
    let finger: Int?
    let onTap: (Int) -> Void

    static func == (l: HashiBoard, r: HashiBoard) -> Bool {
        l.size == r.size && l.gridN == r.gridN && l.islands == r.islands && l.degrees == r.degrees
            && l.bridges == r.bridges && l.selected == r.selected && l.finger == r.finger
    }

    var body: some View {
        let side = min(size.width, size.height) - 16
        let cell = gridN > 0 ? side / CGFloat(gridN) : 0
        let ox = (size.width - cell * CGFloat(gridN)) / 2
        let oy = (size.height - cell * CGFloat(gridN)) / 2
        let pos: (Int) -> CGPoint = { i in
            CGPoint(x: ox + (CGFloat(islands[i].c) + 0.5) * cell, y: oy + (CGFloat(islands[i].r) + 0.5) * cell)
        }
        ZStack {
            Canvas { ctx, _ in
                for span in bridges where span.a < islands.count && span.b < islands.count {
                    HashiArt.bridge(ctx, from: pos(span.a), to: pos(span.b), count: span.count, cell: cell)
                }
                for i in islands.indices {
                    let d = i < degrees.count ? degrees[i] : 0
                    HashiArt.island(ctx, at: pos(i), cell: cell, need: islands[i].need, degree: d, selected: selected == i)
                }
            }
            ForEach(islands.indices, id: \.self) { i in
                Color.clear
                    .frame(width: cell * 0.72, height: cell * 0.72)
                    .contentShape(Circle())
                    .onTapGesture { onTap(i) }
                    .position(pos(i))
            }
            if let f = finger, f < islands.count {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: cell * 0.5))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 3)
                    .position(x: pos(f).x + cell * 0.3, y: pos(f).y + cell * 0.38)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

private enum HashiArt {
    static let wood = Color(red: 0.62, green: 0.42, blue: 0.22)
    static let rope = Color(red: 0.9, green: 0.8, blue: 0.56)

    /// A plank bridge (or two side by side) from island to island; the islands cover its ends.
    static func bridge(_ ctx: GraphicsContext, from p1: CGPoint, to p2: CGPoint, count: Int, cell: CGFloat) {
        let horizontal = abs(p1.y - p2.y) < 0.5
        let off = cell * 0.11
        let offsets: [CGFloat] = count >= 2 ? [-off, off] : [0]
        let deck = count >= 2 ? cell * 0.1 : cell * 0.16
        let len = horizontal ? abs(p2.x - p1.x) : abs(p2.y - p1.y)
        let start = horizontal ? min(p1.x, p2.x) : min(p1.y, p2.y)
        for o in offsets {
            var g = ctx
            if horizontal {
                g.translateBy(x: start, y: p1.y + o)
            } else {
                g.translateBy(x: p1.x + o, y: start)
                g.rotate(by: .degrees(90))
            }
            // Shadow on the water, then the planks, then the rope rails.
            g.fill(Path(CGRect(x: 0, y: -deck / 2 + deck * 0.35, width: len, height: deck)), with: .color(.black.opacity(0.2)))
            var planks = Path()
            var x: CGFloat = 0
            var k = 0
            while x < len {
                planks.addRect(CGRect(x: x, y: -deck / 2, width: min(cell * 0.07, len - x), height: deck))
                x += cell * 0.09
                k += 1
            }
            g.fill(planks, with: .linearGradient(Gradient(colors: [wood.mix(with: .white, by: 0.2), wood, wood.mix(with: .black, by: 0.25)]),
                                                  startPoint: CGPoint(x: 0, y: -deck / 2), endPoint: CGPoint(x: 0, y: deck / 2)))
            var rails = Path()
            rails.move(to: CGPoint(x: 0, y: -deck / 2)); rails.addLine(to: CGPoint(x: len, y: -deck / 2))
            rails.move(to: CGPoint(x: 0, y: deck / 2)); rails.addLine(to: CGPoint(x: len, y: deck / 2))
            g.stroke(rails, with: .color(rope), lineWidth: max(1, cell * 0.022))
        }
    }

    /// A smooth irregular blob around `c` (a coastline), fixed per island by `seed`.
    static func blob(_ c: CGPoint, r: CGFloat, seed: Double) -> Path {
        let n = 12
        let pts: [CGPoint] = (0..<n).map { i in
            let a = Double(i) / Double(n) * 2 * .pi
            let k = 1 + 0.07 * sin(seed + Double(i) * 2.3) + 0.04 * cos(seed * 1.7 + Double(i) * 1.1)
            return CGPoint(x: c.x + CGFloat(cos(a) * k) * r, y: c.y + CGFloat(sin(a) * k) * r)
        }
        var p = Path()
        let mid = { (a: CGPoint, b: CGPoint) in CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        p.move(to: mid(pts[n - 1], pts[0]))
        for i in 0..<n { p.addQuadCurve(to: mid(pts[i], pts[(i + 1) % n]), control: pts[i]) }
        p.closeSubpath()
        return p
    }

    /// An island: turquoise shallows, a sandy coast, a grass cap with a palm, and its clue on a
    /// painted disc — white, green when satisfied, red when over. The selected island glows yellow.
    static func island(_ ctx: GraphicsContext, at p: CGPoint, cell: CGFloat, need: Int, degree: Int, selected: Bool) {
        func disc(_ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)) }
        let seed = Double(p.x * 0.37 + p.y * 0.11)
        if selected {
            ctx.fill(disc(cell * 0.52), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.85, blue: 0.3).opacity(0.6), .clear]),
                                                             center: p, startRadius: cell * 0.36, endRadius: cell * 0.52))
        }
        ctx.fill(blob(p, r: cell * 0.46, seed: seed + 3), with: .color(Color(red: 0.36, green: 0.82, blue: 0.82).opacity(0.33)))
        let sand = blob(p, r: cell * 0.37, seed: seed)
        ctx.fill(sand, with: .radialGradient(Gradient(colors: [Color(red: 0.99, green: 0.91, blue: 0.7), Color(red: 0.88, green: 0.74, blue: 0.48)]),
                                             center: CGPoint(x: p.x - cell * 0.1, y: p.y - cell * 0.12), startRadius: 0, endRadius: cell * 0.42))
        ctx.stroke(sand, with: .color(.white.opacity(0.5)), lineWidth: max(1, cell * 0.02))
        let grass = blob(CGPoint(x: p.x, y: p.y - cell * 0.015), r: cell * 0.315, seed: seed + 7)
        ctx.fill(grass, with: .linearGradient(Gradient(colors: [Color(red: 0.42, green: 0.8, blue: 0.36), Color(red: 0.22, green: 0.56, blue: 0.26)]),
                                              startPoint: CGPoint(x: p.x, y: p.y - cell * 0.3), endPoint: CGPoint(x: p.x, y: p.y + cell * 0.3)))
        // A little palm leaning out of the top-left of the island.
        var trunk = Path()
        trunk.move(to: CGPoint(x: p.x - cell * 0.12, y: p.y - cell * 0.12))
        trunk.addQuadCurve(to: CGPoint(x: p.x - cell * 0.3, y: p.y - cell * 0.36), control: CGPoint(x: p.x - cell * 0.26, y: p.y - cell * 0.16))
        ctx.stroke(trunk, with: .color(Color(red: 0.5, green: 0.34, blue: 0.18)), style: StrokeStyle(lineWidth: max(1.2, cell * 0.05), lineCap: .round))
        var fronds = Path()
        let top = CGPoint(x: p.x - cell * 0.3, y: p.y - cell * 0.36)
        for (dx, dy) in [(-0.16, 0.06), (0.14, 0.04), (-0.08, -0.12), (0.1, -0.1), (-0.02, 0.12)] as [(CGFloat, CGFloat)] {
            fronds.move(to: top)
            fronds.addQuadCurve(to: CGPoint(x: top.x + cell * dx, y: top.y + cell * dy),
                                control: CGPoint(x: top.x + cell * dx * 0.5, y: top.y + cell * (dy - 0.06)))
        }
        ctx.stroke(fronds, with: .color(Color(red: 0.2, green: 0.62, blue: 0.24)), style: StrokeStyle(lineWidth: max(1.2, cell * 0.04), lineCap: .round))
        let face: Color = degree == need ? Color(red: 0.3, green: 0.74, blue: 0.4) : degree > need ? Color(red: 0.92, green: 0.3, blue: 0.28) : .white
        ctx.fill(disc(cell * 0.23), with: .color(face))
        ctx.stroke(disc(cell * 0.23), with: .color(Color(red: 0.16, green: 0.24, blue: 0.14).opacity(0.75)), lineWidth: max(1, cell * 0.02))
        if selected {
            ctx.stroke(disc(cell * 0.44), with: .color(Color(red: 1, green: 0.85, blue: 0.3)), lineWidth: 3)
        }
        let ink: Color = face == .white ? Color(red: 0.08, green: 0.2, blue: 0.3) : .white
        let num = ctx.resolve(Text("\(need)").font(.system(size: cell * 0.29, weight: .black, design: .rounded)).foregroundColor(ink))
        ctx.draw(num, at: p)
    }
}

/// The sea: deep teal with long swell lines and a few whitecaps.
private struct HashiSea: View, Equatable {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.05, green: 0.4, blue: 0.54), Color(red: 0.02, green: 0.2, blue: 0.34)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            var swell = Path()
            var y: CGFloat = 20
            var row = 0
            while y < h {
                let shift = CGFloat(row % 2) * 30
                var x: CGFloat = -40 + shift
                while x < w {
                    swell.move(to: CGPoint(x: x, y: y))
                    swell.addQuadCurve(to: CGPoint(x: x + 44, y: y), control: CGPoint(x: x + 22, y: y - 6))
                    x += 70
                }
                y += 34
                row += 1
            }
            ctx.stroke(swell, with: .color(.white.opacity(0.07)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}

/// The counter's little island: sand, a palm and its fronds.
private struct HashiIslandIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.05, y: h * 0.62, width: w * 0.9, height: h * 0.34)), with: .color(Color(red: 0.95, green: 0.85, blue: 0.6)))
            var trunk = Path()
            trunk.move(to: CGPoint(x: w * 0.5, y: h * 0.72)); trunk.addQuadCurve(to: CGPoint(x: w * 0.56, y: h * 0.28), control: CGPoint(x: w * 0.42, y: h * 0.5))
            ctx.stroke(trunk, with: .color(Color(red: 0.55, green: 0.38, blue: 0.2)), style: StrokeStyle(lineWidth: max(1.5, w * 0.1), lineCap: .round))
            var fronds = Path()
            for (dx, dy) in [(-0.4, 0.1), (0.4, 0.12), (-0.25, -0.18), (0.3, -0.16)] as [(CGFloat, CGFloat)] {
                fronds.move(to: CGPoint(x: w * 0.56, y: h * 0.28))
                fronds.addQuadCurve(to: CGPoint(x: w * (0.56 + dx), y: h * (0.28 + dy + 0.12)), control: CGPoint(x: w * (0.56 + dx * 0.5), y: h * (0.28 + dy - 0.1)))
            }
            ctx.stroke(fronds, with: .color(Color(red: 0.3, green: 0.78, blue: 0.38)), style: StrokeStyle(lineWidth: max(1.5, w * 0.1), lineCap: .round))
        }
    }
}
