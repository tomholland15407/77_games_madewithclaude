//
//  MasyuGame.swift
//  A Banana Game
//
//  Brain — Masyu (the Nikoli "pearl" loop puzzle). Draw ONE closed loop that threads every
//  pearl. Tap the gap between two cells to add or remove a segment; the loop never crosses or
//  branches. The two pearl types have opposite rules:
//    • White pearl — the loop runs STRAIGHT through it, but must TURN in the cell just before
//      and/or just after it.
//    • Black pearl — the loop TURNS on it, and must run straight for at least one cell on both
//      sides of the turn.
//  Solve the whole board before the clock runs out or you drop back to level 1.
//
//  Every board is solvable by construction: a random single loop is grown on the grid, then the
//  pearls are read straight off that loop (white on valid straight cells, black on valid turns),
//  so the loop the generator built is always a legal solution. The board never starts drawn, so
//  it can't begin solved. Generation runs off-main behind the shared brainstorming banana. Seven
//  levels grow the grid (5×5 → 8×8) and the pearl count while the clock tightens.
//

import SwiftUI

enum MasyuGame {
    static let definition = GameDefinition(
        id: "masyu",
        title: "Pearl Chain",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Tap between two cells to draw one closed loop through every pearl — it never crosses or branches.",
                "White pearls: the loop runs straight through but turns just before or after.",
                "Black pearls: the loop turns on them but runs straight one cell on both sides.",
                "Finish the loop before the clock runs out.",
            ],
            bulletsVI: [
                "Chạm giữa hai ô để vẽ một vòng khép kín qua mọi hạt ngọc — không cắt nhau, không rẽ nhánh.",
                "Ngọc trắng: vòng đi thẳng qua nhưng phải rẽ ngay trước hoặc sau nó.",
                "Ngọc đen: vòng phải rẽ tại nó nhưng đi thẳng một ô ở cả hai bên.",
                "Hoàn thành vòng trước khi hết giờ.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(MasyuView(level: level, onWin: onWin, onFail: onFail))
        },
        prefetch: { level in MasyuView(level: level, onWin: {}, onFail: {}).prefetchBoard() }
    )
}

// MARK: - Model

private struct MCell: Hashable, Sendable { let r: Int; let c: Int }

/// An undirected segment between two orthogonally-adjacent cells (normalized so it hashes stably).
private struct MEdge: Hashable, Sendable {
    let a: MCell; let b: MCell
    init(_ x: MCell, _ y: MCell) {
        if (x.r, x.c) <= (y.r, y.c) { a = x; b = y } else { a = y; b = x }
    }
    var horizontal: Bool { a.r == b.r }
}

private struct MasyuPuzzle: Sendable {
    let n: Int
    let whites: [MCell]
    let blacks: [MCell]
}

// MARK: - Generation & rules (pure / off-main)

private enum MasyuGen {
    static func inBounds(_ cell: MCell, _ n: Int) -> Bool {
        cell.r >= 0 && cell.r < n && cell.c >= 0 && cell.c < n
    }

    static func adjacency(_ links: Set<MEdge>) -> [MCell: [MCell]] {
        var adj: [MCell: [MCell]] = [:]
        for e in links {
            adj[e.a, default: []].append(e.b)
            adj[e.b, default: []].append(e.a)
        }
        return adj
    }

    /// A cell's two loop-neighbours are collinear with it (loop passes straight through).
    static func isStraight(_ cell: MCell, _ nbrs: [MCell]) -> Bool {
        guard nbrs.count == 2 else { return false }
        return (nbrs[0].r == cell.r && nbrs[1].r == cell.r)
            || (nbrs[0].c == cell.c && nbrs[1].c == cell.c)
    }

    static func turnAt(_ cell: MCell, _ adj: [MCell: [MCell]]) -> Bool {
        guard let nbrs = adj[cell], nbrs.count == 2 else { return false }
        return !isStraight(cell, nbrs)
    }

    /// Black-pearl legality: from the (turning) cell, the loop continues straight for one more
    /// cell along BOTH of its arms.
    static func blackValid(_ cell: MCell, _ nbrs: [MCell], _ adj: [MCell: [MCell]]) -> Bool {
        for nb in nbrs {
            let dr = nb.r - cell.r, dc = nb.c - cell.c
            let beyond = MCell(r: nb.r + dr, c: nb.c + dc)
            guard let nn = adj[nb], nn.contains(beyond) else { return false }
        }
        return true
    }

    /// Whether one pearl's local rule holds for the current links (works on partial loops too, so
    /// it doubles as live feedback).
    static func pearlSatisfied(_ p: MCell, isWhite: Bool, _ adj: [MCell: [MCell]]) -> Bool {
        guard let nbrs = adj[p], nbrs.count == 2 else { return false }
        if isWhite {
            return isStraight(p, nbrs) && nbrs.contains { turnAt($0, adj) }
        } else {
            return !isStraight(p, nbrs) && blackValid(p, nbrs, adj)
        }
    }

    /// The full Masyu win test — a single closed loop of degree-2 cells that threads every pearl and
    /// honours every pearl's rule. Shared by generation (to prove each board is winnable) and the view.
    static func satisfiesAll(links: Set<MEdge>, whites: [MCell], blacks: [MCell]) -> Bool {
        if links.isEmpty { return false }
        let adj = adjacency(links)
        for (_, nbrs) in adj where nbrs.count != 2 { return false }
        let loopCells = Array(adj.keys)
        for p in whites where adj[p] == nil { return false }
        for p in blacks where adj[p] == nil { return false }
        guard let start = loopCells.first, let first = adj[start]?.first else { return false }
        var prev = start, cur = first, visited = 1
        while cur != start {
            visited += 1
            guard let nbrs = adj[cur], nbrs.count == 2 else { return false }
            let next = nbrs[0] == prev ? nbrs[1] : nbrs[0]
            prev = cur; cur = next
            if visited > loopCells.count { break }
        }
        if visited != loopCells.count { return false }
        for p in whites where !pearlSatisfied(p, isWhite: true, adj) { return false }
        for p in blacks where !pearlSatisfied(p, isWhite: false, adj) { return false }
        return true
    }

    /// Grow a random single loop from a central 2×2 by repeatedly "bumping" a loop edge outward
    /// over two free cells (edge → three edges around the new pair). This always keeps exactly one
    /// loop and only ever adds cells.
    static func growLoop(n: Int) -> Set<MEdge> {
        var links = Set<MEdge>()
        var inLoop = Set<MCell>()
        let sr = max(0, n / 2 - 1), sc = max(0, n / 2 - 1)
        let c00 = MCell(r: sr, c: sc), c01 = MCell(r: sr, c: sc + 1)
        let c10 = MCell(r: sr + 1, c: sc), c11 = MCell(r: sr + 1, c: sc + 1)
        links.insert(MEdge(c00, c01)); links.insert(MEdge(c01, c11))
        links.insert(MEdge(c11, c10)); links.insert(MEdge(c10, c00))
        inLoop.formUnion([c00, c01, c10, c11])

        let attempts = n * n * 6
        for _ in 0..<attempts {
            guard let e = links.randomElement() else { break }
            let a = e.a, b = e.b
            let deltas: [(Int, Int)] = e.horizontal ? [(-1, 0), (1, 0)] : [(0, -1), (0, 1)]
            for (dr, dc) in deltas.shuffled() {
                let a2 = MCell(r: a.r + dr, c: a.c + dc)
                let b2 = MCell(r: b.r + dr, c: b.c + dc)
                if inBounds(a2, n) && inBounds(b2, n) && !inLoop.contains(a2) && !inLoop.contains(b2) {
                    links.remove(e)
                    links.insert(MEdge(a, a2)); links.insert(MEdge(a2, b2)); links.insert(MEdge(b2, b))
                    inLoop.insert(a2); inLoop.insert(b2)
                    break
                }
            }
        }
        return links
    }

    static func rectangleLoop(n: Int) -> Set<MEdge> {
        var links = Set<MEdge>()
        for c in 0..<(n - 1) {
            links.insert(MEdge(MCell(r: 0, c: c), MCell(r: 0, c: c + 1)))
            links.insert(MEdge(MCell(r: n - 1, c: c), MCell(r: n - 1, c: c + 1)))
        }
        for r in 0..<(n - 1) {
            links.insert(MEdge(MCell(r: r, c: 0), MCell(r: r + 1, c: 0)))
            links.insert(MEdge(MCell(r: r, c: n - 1), MCell(r: r + 1, c: n - 1)))
        }
        return links
    }

    static func pickPearls(adj: [MCell: [MCell]], target: Int) -> (whites: [MCell], blacks: [MCell]) {
        var whiteCand: [MCell] = []
        var blackCand: [MCell] = []
        for (cell, nbrs) in adj where nbrs.count == 2 {
            if isStraight(cell, nbrs) {
                if nbrs.contains(where: { turnAt($0, adj) }) { whiteCand.append(cell) }
            } else if blackValid(cell, nbrs, adj) {
                blackCand.append(cell)
            }
        }
        whiteCand.shuffle(); blackCand.shuffle()
        var whites: [MCell] = []; var blacks: [MCell] = []
        var wi = 0, bi = 0
        // Interleave, slightly favouring the more-constraining black pearls.
        while whites.count + blacks.count < target {
            let canB = bi < blackCand.count, canW = wi < whiteCand.count
            if !canB && !canW { break }
            let pickBlack = canB && (!canW || blacks.count <= whites.count)
            if pickBlack { blacks.append(blackCand[bi]); bi += 1 }
            else { whites.append(whiteCand[wi]); wi += 1 }
        }
        return (whites, blacks)
    }

    static func generate(n: Int, pearlTarget: Int) -> MasyuPuzzle {
        for _ in 0..<60 {
            let links = growLoop(n: n)
            let adj = adjacency(links)
            guard adj.keys.count >= 10 else { continue }
            let (whites, blacks) = pickPearls(adj: adj, target: pearlTarget)
            guard !blacks.isEmpty, !whites.isEmpty,
                  whites.count + blacks.count >= min(pearlTarget, 4) else { continue }
            // Prove the loop we built is a legal solution to the board we're about to hand over.
            if satisfiesAll(links: links, whites: whites, blacks: blacks) {
                return MasyuPuzzle(n: n, whites: whites, blacks: blacks)
            }
        }
        let links = rectangleLoop(n: n)
        let (w, b) = pickPearls(adj: adjacency(links), target: pearlTarget)
        return MasyuPuzzle(n: n, whites: w, blacks: b)
    }
}

// MARK: - View

struct MasyuView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    private var n: Int { [5, 6, 6, 7, 7, 8, 8][min(level, 7) - 1] }
    private var pearlTarget: Int { [4, 5, 7, 8, 10, 12, 14][min(level, 7) - 1] }
    private var timeLimit: Double { [80, 85, 90, 95, 95, 90, 85][min(level, 7) - 1] }

    private let skyTop = Color(red: 0.2, green: 0.08, blue: 0.14)
    private let skyBottom = Color(red: 0.08, green: 0.03, blue: 0.06)

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var boardN = 0
    @State private var whites: Set<MCell> = []
    @State private var blacks: Set<MCell> = []
    @State private var links: Set<MEdge> = []
    @State private var timeLeft = 0.0
    @State private var ready = false
    @State private var loopTask: Task<Void, Never>?
    @State private var demoEdge: MEdge? = nil     // demo finger

    private var pearlsLeftOnLoop: Int {
        let adj = MasyuGen.adjacency(links)
        return whites.filter { adj[$0] == nil }.count + blacks.filter { adj[$0] == nil }.count
    }

    var body: some View {
        Group {
            if ready { gameBody } else { BrainstormingView(skyTop: skyTop, skyBottom: skyBottom) }
        }
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
    }

    // MARK: - Demo (live manual clip)

    /// Draw the rectangle-border loop edge-by-edge. The pearls are read off that exact
    /// loop (via `pickPearls`), so completing the border satisfies the real win check.
    private func runDemo() async {
        while !Task.isCancelled {
            let size = 5
            let solution = MasyuGen.rectangleLoop(n: size)
            let (w, b) = MasyuGen.pickPearls(adj: MasyuGen.adjacency(solution), target: pearlTarget)
            boardN = size
            whites = Set(w)
            blacks = Set(b)
            links = []
            ready = true
            phase = .play
            timeLeft = timeLimit

            try? await Task.sleep(for: .seconds(0.7))
            for e in perimeterEdges(size) {
                guard !Task.isCancelled else { return }
                demoEdge = e
                withAnimation(.easeOut(duration: 0.1)) { _ = links.insert(e) }
                try? await Task.sleep(for: .seconds(0.18))
                if isSolved() { break }
            }
            demoEdge = nil
            if isSolved() { win() }
            try? await Task.sleep(for: .seconds(1.4))
        }
    }

    /// The border edges traced clockwise (top → right → bottom → left).
    private func perimeterEdges(_ n: Int) -> [MEdge] {
        var e: [MEdge] = []
        for c in 0..<(n - 1) { e.append(MEdge(MCell(r: 0, c: c), MCell(r: 0, c: c + 1))) }
        for r in 0..<(n - 1) { e.append(MEdge(MCell(r: r, c: n - 1), MCell(r: r + 1, c: n - 1))) }
        for c in stride(from: n - 1, to: 0, by: -1) { e.append(MEdge(MCell(r: n - 1, c: c), MCell(r: n - 1, c: c - 1))) }
        for r in stride(from: n - 1, to: 0, by: -1) { e.append(MEdge(MCell(r: r, c: 0), MCell(r: r - 1, c: 0))) }
        return e
    }

    private var gameBody: some View {
        VStack(spacing: isDemo ? 6 : 12) {
            Text(L("\(pearlsLeftOnLoop) pearls to thread", "còn \(pearlsLeftOnLoop) hạt ngọc"))
                .font(.system(size: isDemo ? 17 : 20, weight: .black, design: .rounded))
                .foregroundStyle(pearlsLeftOnLoop == 0 ? Color(red: 1, green: 0.84, blue: 0.4) : .white)
                .contentTransition(.numericText())
            if !isDemo { timeBar.frame(height: 6).padding(.horizontal, 50) }

            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height) * 0.92
                let cell = boardN > 0 ? side / CGFloat(boardN) : 0
                let ox = (geo.size.width - cell * CGFloat(boardN)) / 2
                let oy = (geo.size.height - cell * CGFloat(boardN)) / 2

                ZStack {
                    JewelBox(n: boardN, cell: cell, origin: CGPoint(x: ox, y: oy)).equatable()
                    boardCanvas(cell: cell, ox: ox, oy: oy)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { loc in
                    handleTap(loc, cell: cell, ox: ox, oy: oy)
                }
            }
            .padding(.horizontal, isDemo ? 4 : 8)
        }
        .padding(.vertical, isDemo ? 8 : 14)
        .background(LinearGradient(colors: [Color(red: 0.2, green: 0.08, blue: 0.14), Color(red: 0.08, green: 0.03, blue: 0.06)],
                                   startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The gold chain, then the pearls — a pearl whose rule is met sits in a gold clasp.
    private func boardCanvas(cell: CGFloat, ox: CGFloat, oy: CGFloat) -> some View {
        Canvas { ctx, _ in
            guard boardN > 0 else { return }
            let center: (Int, Int) -> CGPoint = { r, c in
                CGPoint(x: ox + (CGFloat(c) + 0.5) * cell, y: oy + (CGFloat(r) + 0.5) * cell)
            }

            // The drawn loop, as a gold chain.
            var line = Path()
            for e in links {
                line.move(to: center(e.a.r, e.a.c))
                line.addLine(to: center(e.b.r, e.b.c))
            }
            if !links.isEmpty { JewelArt.chain(ctx, line, cell: cell) }

            let adj = MasyuGen.adjacency(links)
            for p in whites {
                JewelArt.pearl(ctx, at: center(p.r, p.c), r: cell * 0.3, black: false,
                               clasped: MasyuGen.pearlSatisfied(p, isWhite: true, adj))
            }
            for p in blacks {
                JewelArt.pearl(ctx, at: center(p.r, p.c), r: cell * 0.3, black: true,
                               clasped: MasyuGen.pearlSatisfied(p, isWhite: false, adj))
            }

            // Demo finger on the gap being tapped.
            if isDemo, let e = demoEdge {
                let a = center(e.a.r, e.a.c), b = center(e.b.r, e.b.c)
                let m = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                var hand = ctx.resolve(Image(systemName: "hand.point.up.left.fill"))
                hand.shading = .color(.white)
                var h = ctx
                h.addFilter(.shadow(color: .black.opacity(0.6), radius: 3))
                let hw = cell * 0.6
                h.draw(hand, in: CGRect(x: m.x - hw * 0.02, y: m.y + hw * 0.02, width: hw, height: hw))
            }
        }
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

    // MARK: Input
    private func handleTap(_ loc: CGPoint, cell: CGFloat, ox: CGFloat, oy: CGFloat) {
        guard phase == .play, cell > 0 else { return }
        var best: MEdge?
        var bestD = cell * 0.5
        for r in 0..<boardN {
            for c in 0..<boardN {
                if c + 1 < boardN {
                    let mx = ox + CGFloat(c + 1) * cell
                    let my = oy + (CGFloat(r) + 0.5) * cell
                    let d = hypot(loc.x - mx, loc.y - my)
                    if d < bestD { bestD = d; best = MEdge(MCell(r: r, c: c), MCell(r: r, c: c + 1)) }
                }
                if r + 1 < boardN {
                    let mx = ox + (CGFloat(c) + 0.5) * cell
                    let my = oy + CGFloat(r + 1) * cell
                    let d = hypot(loc.x - mx, loc.y - my)
                    if d < bestD { bestD = d; best = MEdge(MCell(r: r, c: c), MCell(r: r + 1, c: c)) }
                }
            }
        }
        guard let e = best else { return }
        if links.contains(e) { links.remove(e) } else { links.insert(e) }
        SoundManager.shared.tap(); Haptics.tap()
        if isSolved() { win() }
    }

    // MARK: Win check
    private func isSolved() -> Bool {
        MasyuGen.satisfiesAll(links: links, whites: Array(whites), blacks: Array(blacks))
    }

    // MARK: Flow
    /// Hands this level's board build to `BoardCache` so it can run during the countdown.
    func prefetchBoard() {
        let size = n, target = pearlTarget
        BoardCache.prefetch(boardKey) { MasyuGen.generate(n: size, pearlTarget: target) }
    }
    private var boardKey: String { BoardCache.key("masyu", level: level) }

    private func run() async {
        let size = n, target = pearlTarget
        let t0 = Date()
        let puzzle = await BoardCache.take(boardKey) { MasyuGen.generate(n: size, pearlTarget: target) }
        guard !Task.isCancelled else { return }
        await BoardCache.holdBrainstorm(since: t0, minimum: 0.7)
        guard !Task.isCancelled else { return }

        boardN = puzzle.n
        whites = Set(puzzle.whites)
        blacks = Set(puzzle.blacks)
        links = []
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

// MARK: - Jewellery art

/// A jewellery box: quilted velvet with tufting buttons at every cell, lustrous white pearls and
/// iridescent Tahitian black pearls, threaded by a gold chain.
private enum JewelArt {
    static let gold = Color(red: 0.95, green: 0.76, blue: 0.3)

    static func chain(_ ctx: GraphicsContext, _ path: Path, cell: CGFloat) {
        let w = cell * 0.13
        ctx.stroke(path, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: w * 1.5, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(Color(red: 0.62, green: 0.44, blue: 0.1)), style: StrokeStyle(lineWidth: w * 1.15, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(gold), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        // Link segments and a bright glint along the top.
        ctx.stroke(path, with: .color(Color(red: 0.62, green: 0.44, blue: 0.1).opacity(0.85)),
                   style: StrokeStyle(lineWidth: w * 0.4, lineCap: .butt, lineJoin: .round, dash: [w * 0.9, w * 0.55]))
        ctx.stroke(path, with: .color(Color(red: 1, green: 0.96, blue: 0.75).opacity(0.8)),
                   style: StrokeStyle(lineWidth: max(0.8, w * 0.18), lineCap: .round, lineJoin: .round))
    }

    /// A pearl: white (ivory with a pink blush) or Tahitian black (green-purple sheen). A pearl whose
    /// rule is satisfied sits in a gold clasp ring.
    static func pearl(_ ctx: GraphicsContext, at p: CGPoint, r: CGFloat, black: Bool, clasped: Bool) {
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.9, y: p.y - r * 0.55, width: r * 2, height: r * 1.9)), with: .color(.black.opacity(0.35)))
        if clasped {
            let cr = r * 1.22
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - cr, y: p.y - cr, width: cr * 2, height: cr * 2)),
                       with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.94, blue: 0.65), gold, Color(red: 0.6, green: 0.42, blue: 0.08)]),
                                             startPoint: CGPoint(x: p.x - cr, y: p.y - cr), endPoint: CGPoint(x: p.x + cr, y: p.y + cr)),
                       lineWidth: max(2, r * 0.26))
            for k in 0..<4 {
                let a = Double(k) * .pi / 2 + .pi / 4
                let q = CGPoint(x: p.x + CGFloat(cos(a)) * cr, y: p.y + CGFloat(sin(a)) * cr)
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - r * 0.14, y: q.y - r * 0.14, width: r * 0.28, height: r * 0.28)), with: .color(gold))
            }
        }
        let body = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        if black {
            ctx.fill(body, with: .radialGradient(Gradient(colors: [Color(red: 0.42, green: 0.44, blue: 0.5), Color(red: 0.12, green: 0.13, blue: 0.17),
                                                                   Color(red: 0.03, green: 0.03, blue: 0.05)]),
                                                 center: CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.4), startRadius: 0, endRadius: r * 1.4))
            ctx.fill(body, with: .linearGradient(Gradient(colors: [Color(red: 0.3, green: 0.9, blue: 0.6).opacity(0.22), .clear,
                                                                   Color(red: 0.7, green: 0.3, blue: 0.9).opacity(0.28)]),
                                                 startPoint: CGPoint(x: p.x - r, y: p.y + r), endPoint: CGPoint(x: p.x + r, y: p.y - r)))
        } else {
            ctx.fill(body, with: .radialGradient(Gradient(colors: [.white, Color(red: 0.97, green: 0.94, blue: 0.9), Color(red: 0.8, green: 0.76, blue: 0.78)]),
                                                 center: CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.4), startRadius: 0, endRadius: r * 1.4))
            ctx.fill(body, with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.8, blue: 0.85).opacity(0.35), .clear]),
                                                 center: CGPoint(x: p.x + r * 0.4, y: p.y + r * 0.45), startRadius: 0, endRadius: r * 0.9))
        }
        ctx.stroke(body, with: .color(.black.opacity(black ? 0.6 : 0.25)), lineWidth: max(0.8, r * 0.05))
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.55, y: p.y - r * 0.6, width: r * 0.5, height: r * 0.32)), with: .color(.white.opacity(black ? 0.7 : 0.95)))
        ctx.fill(Path(ellipseIn: CGRect(x: p.x + r * 0.25, y: p.y + r * 0.3, width: r * 0.22, height: r * 0.14)), with: .color(.white.opacity(0.35)))
    }
}

/// The box: a gold-trimmed tray of quilted velvet with a tufting button at every cell (static).
private struct JewelBox: View, Equatable {
    let n: Int
    let cell: CGFloat
    let origin: CGPoint

    var body: some View {
        Canvas { ctx, _ in
            guard n > 0 else { return }
            let side = cell * CGFloat(n)
            let tray = CGRect(x: origin.x, y: origin.y, width: side, height: side)
            let rim = tray.insetBy(dx: -cell * 0.18, dy: -cell * 0.18)
            ctx.fill(Path(roundedRect: rim.offsetBy(dx: 0, dy: cell * 0.08), cornerRadius: cell * 0.3), with: .color(.black.opacity(0.5)))
            ctx.fill(Path(roundedRect: rim, cornerRadius: cell * 0.3),
                     with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.9, blue: 0.55), JewelArt.gold, Color(red: 0.55, green: 0.38, blue: 0.08)]),
                                           startPoint: CGPoint(x: rim.minX, y: rim.minY), endPoint: CGPoint(x: rim.maxX, y: rim.maxY)))
            ctx.fill(Path(roundedRect: tray, cornerRadius: cell * 0.18),
                     with: .radialGradient(Gradient(colors: [Color(red: 0.2, green: 0.24, blue: 0.5), Color(red: 0.09, green: 0.1, blue: 0.26)]),
                                           center: CGPoint(x: tray.midX, y: tray.minY + tray.height * 0.35), startRadius: 0, endRadius: side * 0.8))
            // Diamond quilting: stitched diagonals that meet at the tufting buttons.
            var g = ctx
            g.clip(to: Path(roundedRect: tray, cornerRadius: cell * 0.18))
            var stitches = Path()
            for k in -n...(2 * n) {
                let x0 = tray.minX + (CGFloat(k) + 0.5) * cell
                stitches.move(to: CGPoint(x: x0, y: tray.minY - cell * 0.5)); stitches.addLine(to: CGPoint(x: x0 + side + cell, y: tray.maxY + cell * 0.5))
                stitches.move(to: CGPoint(x: x0, y: tray.minY - cell * 0.5)); stitches.addLine(to: CGPoint(x: x0 - side - cell, y: tray.maxY + cell * 0.5))
            }
            g.stroke(stitches, with: .color(Color(red: 0.05, green: 0.06, blue: 0.16).opacity(0.7)), lineWidth: max(1, cell * 0.035))
            g.stroke(stitches, with: .color(Color(red: 0.45, green: 0.5, blue: 0.8).opacity(0.15)),
                     style: StrokeStyle(lineWidth: max(0.6, cell * 0.015), dash: [cell * 0.08, cell * 0.06]))
            for r in 0..<n {
                for c in 0..<n {
                    let p = CGPoint(x: tray.minX + (CGFloat(c) + 0.5) * cell, y: tray.minY + (CGFloat(r) + 0.5) * cell)
                    let br = cell * 0.07
                    g.fill(Path(ellipseIn: CGRect(x: p.x - br * 1.8, y: p.y - br * 1.8, width: br * 3.6, height: br * 3.6)),
                           with: .radialGradient(Gradient(colors: [Color.black.opacity(0.45), .clear]), center: p, startRadius: 0, endRadius: br * 1.8))
                    g.fill(Path(ellipseIn: CGRect(x: p.x - br, y: p.y - br, width: br * 2, height: br * 2)),
                           with: .radialGradient(Gradient(colors: [Color(red: 0.4, green: 0.45, blue: 0.75), Color(red: 0.12, green: 0.13, blue: 0.32)]),
                                                 center: CGPoint(x: p.x - br * 0.3, y: p.y - br * 0.3), startRadius: 0, endRadius: br * 1.3))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
