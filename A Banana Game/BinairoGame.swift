//
//  BinairoGame.swift
//  A Banana Game
//
//  Brain — Binairo (a.k.a. Takuzu / 0h h1). Fill every cell with one of two tokens — blue or banana
//  — under three rules at once:
//    • No three of the same token in a row, anywhere across or down.
//    • Every row and every column holds equal numbers of each token.
//    • No two rows are identical, and no two columns are identical.
//  Tap a cell to cycle blank → blue → banana → blank. Some cells are locked clues. Finish the grid
//  before the clock runs out or you drop back to level 1.
//
//  Boards start from a full, rule-legal grid produced by constraint-checked backtracking (triples,
//  balance, and duplicate-line checks are enforced as it fills), then a shrinking fraction of cells
//  is kept as locked clues — so a legal solution always exists and blanks mean it never starts done.
//  The win check re-proves all three rules. Generation runs off-main behind the brainstorming
//  banana. Seven levels grow the grid (6×6 → 10×10) and strip away clues.
//

import SwiftUI

enum BinairoGame {
    static let definition = GameDefinition(
        id: "binairo",
        title: "Berry Balance",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Tap a cell to cycle blank → blue → banana → blank; clue cells are locked.",
                "No three of the same colour may sit in a line.",
                "Each row and column needs equal numbers of both colours.",
                "No two rows (or two columns) may be identical; finish before time runs out.",
            ],
            bulletsVI: [
                "Chạm một ô để luân chuyển trống → xanh → chuối → trống; ô gợi ý bị khóa.",
                "Không được có ba ô cùng màu liền nhau trên một hàng.",
                "Mỗi hàng và cột cần số lượng bằng nhau của cả hai màu.",
                "Không hai hàng (hoặc hai cột) nào được giống hệt nhau; hoàn thành trước khi hết giờ.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(BinairoView(level: level, onWin: onWin, onFail: onFail))
        },
        prefetch: { level in BinairoView(level: level, onWin: {}, onFail: {}).prefetchBoard() }
    )
}

private struct BinairoPuzzle: Sendable {
    let n: Int
    let value: [Int]          // initial board: -1 blank, 0 / 1 clue
    let clues: Set<Int>
}

private enum BinGen {
    static func rowEqual(_ g: [Int], _ a: Int, _ b: Int, _ n: Int) -> Bool {
        for c in 0..<n where g[a * n + c] != g[b * n + c] { return false }
        return true
    }
    static func colEqual(_ g: [Int], _ a: Int, _ b: Int, _ n: Int) -> Bool {
        for r in 0..<n where g[r * n + a] != g[r * n + b] { return false }
        return true
    }

    static func canPlace(_ g: [Int], _ r: Int, _ c: Int, _ v: Int, _ n: Int) -> Bool {
        if c >= 2 && g[r * n + c - 1] == v && g[r * n + c - 2] == v { return false }
        if r >= 2 && g[(r - 1) * n + c] == v && g[(r - 2) * n + c] == v { return false }
        var rowV = 0
        for cc in 0..<n where g[r * n + cc] == v { rowV += 1 }
        if rowV + 1 > n / 2 { return false }
        var colV = 0
        for rr in 0..<n where g[rr * n + c] == v { colV += 1 }
        if colV + 1 > n / 2 { return false }
        return true
    }

    static func fill(_ g: inout [Int], _ pos: Int, _ n: Int) -> Bool {
        if pos == n * n { return true }
        let r = pos / n, c = pos % n
        for v in [0, 1].shuffled() where canPlace(g, r, c, v, n) {
            g[pos] = v
            var ok = true
            if c == n - 1 {
                for rr in 0..<r where rowEqual(g, rr, r, n) { ok = false; break }
            }
            if ok && r == n - 1 {
                for cc in 0..<c where colEqual(g, cc, c, n) { ok = false; break }
            }
            if ok && fill(&g, pos + 1, n) { return true }
            g[pos] = -1
        }
        return false
    }

    static func generate(n: Int, clueFrac: Double) -> BinairoPuzzle {
        for _ in 0..<12 {
            var g = [Int](repeating: -1, count: n * n)
            if fill(&g, 0, n) {
                let clueCount = max(1, Int(Double(n * n) * clueFrac))
                let clueCells = Set(Array(0..<n * n).shuffled().prefix(clueCount))
                var value = [Int](repeating: -1, count: n * n)
                for i in clueCells { value[i] = g[i] }
                return BinairoPuzzle(n: n, value: value, clues: clueCells)
            }
        }
        // Fallback: a shifted-stripe grid (valid balance & no triples) with half the cells as clues.
        var g = [Int](repeating: 0, count: n * n)
        for r in 0..<n {
            for c in 0..<n {
                let block = (c / 2 + r) % 2
                g[r * n + c] = block
            }
        }
        let clueCells = Set(Array(0..<n * n).shuffled().prefix(n * n / 2))
        var value = [Int](repeating: -1, count: n * n)
        for i in clueCells { value[i] = g[i] }
        return BinairoPuzzle(n: n, value: value, clues: clueCells)
    }
}

struct BinairoView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    private var n: Int { [6, 6, 8, 8, 8, 10, 10][min(level, 7) - 1] }
    private var clueFrac: Double { [0.55, 0.48, 0.48, 0.42, 0.38, 0.40, 0.34][min(level, 7) - 1] }
    private var timeLimit: Double { [70, 75, 85, 90, 95, 105, 110][min(level, 7) - 1] }

    private let skyTop = Color(red: 0.62, green: 0.18, blue: 0.16)
    private let skyBottom = Color(red: 0.36, green: 0.08, blue: 0.08)

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var boardN = 0
    @State private var value: [Int] = []
    @State private var clues: Set<Int> = []
    @State private var timeLeft = 0.0
    @State private var ready = false
    @State private var loopTask: Task<Void, Never>?
    @State private var demoTap: Int? = nil      // cell the demo is "tapping" (ring + finger)

    private var blanks: Int { value.filter { $0 == -1 }.count }

    var body: some View {
        Group {
            if ready { gameBody } else { BrainstormingView(skyTop: skyTop, skyBottom: skyBottom) }
        }
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
    }

    private var gameBody: some View {
        VStack(spacing: isDemo ? 6 : 12) {
            Text(L("\(blanks) blank", "còn \(blanks) ô trống"))
                .font(.system(size: isDemo ? 15 : 20, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.36, green: 0.16, blue: 0.06))
                .padding(.horizontal, 14).padding(.vertical, isDemo ? 3 : 5)
                .background(Capsule().fill(.white.opacity(0.85)))
                .contentTransition(.numericText())
            if !isDemo { timeBar.frame(height: 6).padding(.horizontal, 50) }

            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height) * 0.94
                let cell = boardN > 0 ? side / CGFloat(boardN) : 0
                let ox = (geo.size.width - cell * CGFloat(boardN)) / 2
                let oy = (geo.size.height - cell * CGFloat(boardN)) / 2
                boardCanvas(cell: cell, ox: ox, oy: oy)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { loc in
                        handleTap(loc, cell: cell, ox: ox, oy: oy)
                    }
                    .overlay(alignment: .topLeading) {
                        if let i = demoTap, i < boardN * boardN {
                            demoPress(cell: cell)
                                .position(x: ox + (CGFloat(i % boardN) + 0.5) * cell,
                                          y: oy + (CGFloat(i / boardN) + 0.5) * cell)
                        }
                    }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, isDemo ? 8 : 14)
        .background(GinghamCloth().equatable())
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Demo-only "press" on a cell: a white ring that shrinks in, plus a pointing finger.
    private func demoPress(cell: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cell * 0.2).stroke(.white, lineWidth: 3)
                .frame(width: cell - 2, height: cell - 2)
                .scaleEffect(0.9)
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: cell * 0.5))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 3)
                .offset(x: cell * 0.3, y: cell * 0.36)
        }
        .frame(width: cell * 1.6, height: cell * 1.6)
        .allowsHitTesting(false)
    }

    /// A Belgian waffle: every pocket holds a blueberry (blue), a banana slice (banana) or nothing.
    /// Clue fruit sits on a dollop of whipped cream; a completed legal line gets a honey glaze.
    private func boardCanvas(cell: CGFloat, ox: CGFloat, oy: CGFloat) -> some View {
        Canvas { ctx, _ in
            guard boardN > 0, value.count == boardN * boardN else { return }
            let board = CGRect(x: ox, y: oy, width: cell * CGFloat(boardN), height: cell * CGFloat(boardN))
            WaffleArt.waffle(ctx, board, n: boardN)
            for i in 0..<boardN * boardN {
                let r = i / boardN, c = i % boardN
                let rect = CGRect(x: ox + CGFloat(c) * cell, y: oy + CGFloat(r) * cell, width: cell, height: cell)
                let center = CGPoint(x: rect.midX, y: rect.midY)
                if clues.contains(i) { WaffleArt.cream(ctx, at: center, r: cell * 0.4) }
                switch value[i] {
                case 0: WaffleArt.blueberry(ctx, at: center, r: cell * 0.3)
                case 1: WaffleArt.bananaSlice(ctx, at: center, r: cell * 0.31)
                default: break
                }
            }
            // Honey glaze over every completed, rule-legal row and column.
            for r in 0..<boardN where rowCorrect(r) {
                WaffleArt.honey(ctx, CGRect(x: ox + 2, y: oy + CGFloat(r) * cell + 2, width: cell * CGFloat(boardN) - 4, height: cell - 4), cell: cell)
            }
            for c in 0..<boardN where colCorrect(c) {
                WaffleArt.honey(ctx, CGRect(x: ox + CGFloat(c) * cell + 2, y: oy + 2, width: cell - 4, height: cell * CGFloat(boardN) - 4), cell: cell)
            }
        }
    }
    private func rowCorrect(_ r: Int) -> Bool {
        let n = boardN
        var count0 = 0
        for c in 0..<n {
            let v = value[r * n + c]
            if v == -1 { return false }
            if v == 0 { count0 += 1 }
            if c >= 2 && v == value[r * n + c - 1] && v == value[r * n + c - 2] { return false }
        }
        return count0 == n / 2
    }

    private func colCorrect(_ c: Int) -> Bool {
        let n = boardN
        var count0 = 0
        for r in 0..<n {
            let v = value[r * n + c]
            if v == -1 { return false }
            if v == 0 { count0 += 1 }
            if r >= 2 && v == value[(r - 1) * n + c] && v == value[(r - 2) * n + c] { return false }
        }
        return count0 == n / 2
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.6))
                Capsule().fill(frac < 0.3 ? Color(red: 0.8, green: 0.1, blue: 0.1) : Color(red: 0.95, green: 0.62, blue: 0.1)).frame(width: geo.size.width * frac)
            }
        }
    }

    // MARK: Input
    private func handleTap(_ loc: CGPoint, cell: CGFloat, ox: CGFloat, oy: CGFloat) {
        guard phase == .play, cell > 0 else { return }
        let c = Int((loc.x - ox) / cell)
        let r = Int((loc.y - oy) / cell)
        guard r >= 0, r < boardN, c >= 0, c < boardN else { return }
        tapCell(r * boardN + c)
    }

    private func tapCell(_ i: Int) {
        guard phase == .play, i < value.count, !clues.contains(i) else { return }
        // blank(-1) -> 0 -> 1 -> blank
        value[i] = value[i] == -1 ? 0 : (value[i] == 0 ? 1 : -1)
        SoundManager.shared.tap(); Haptics.tap()
        if blanks == 0, isSolved() { win() }
    }

    // MARK: Win check
    private func isSolved() -> Bool {
        let n = boardN
        if value.contains(-1) { return false }
        // balance + triples per row
        for r in 0..<n {
            var count0 = 0
            for c in 0..<n {
                if value[r * n + c] == 0 { count0 += 1 }
                if c >= 2 && value[r * n + c] == value[r * n + c - 1] && value[r * n + c] == value[r * n + c - 2] {
                    return false
                }
            }
            if count0 != n / 2 { return false }
        }
        // balance + triples per column
        for c in 0..<n {
            var count0 = 0
            for r in 0..<n {
                if value[r * n + c] == 0 { count0 += 1 }
                if r >= 2 && value[r * n + c] == value[(r - 1) * n + c] && value[r * n + c] == value[(r - 2) * n + c] {
                    return false
                }
            }
            if count0 != n / 2 { return false }
        }
        // distinct rows / columns
        for a in 0..<n {
            for b in (a + 1)..<n {
                if BinGen.rowEqual(value, a, b, n) { return false }
                if BinGen.colEqual(value, a, b, n) { return false }
            }
        }
        return true
    }

    // MARK: Demo (live manual clip)
    // A real Level-1 board: 6×6 with 19 clues (the level's clue fraction) and a unique solution.
    // The demo fills the 17 blanks in a pure-deduction order (each is forced by the triple or
    // balance rule at that moment) through the real `tapCell`, so banana cells take two taps.
    private static let demoSolution = [1, 0, 1, 0, 0, 1,  0, 1, 0, 0, 1, 1,  0, 1, 0, 1, 1, 0,
                                       1, 0, 1, 1, 0, 0,  0, 1, 1, 0, 0, 1,  1, 0, 0, 1, 1, 0]
    private static let demoClues: Set<Int> = [1, 2, 3, 4, 6, 7, 9, 11, 13, 16, 17, 18, 21, 22, 23, 24, 25, 28, 31]
    private static let demoOrder = [0, 5, 10, 8, 15, 12, 14, 19, 20, 27, 26, 29, 30, 32, 33, 34, 35]

    private func demoSetup() {
        boardN = 6
        clues = Self.demoClues
        value = (0..<36).map { Self.demoClues.contains($0) ? Self.demoSolution[$0] : -1 }
        demoTap = nil
        timeLeft = timeLimit
        phase = .play
        ready = true
    }

    private func runDemo() async {
        while !Task.isCancelled {
            demoSetup()
            try? await Task.sleep(for: .seconds(0.6))
            for i in Self.demoOrder {
                guard !Task.isCancelled else { return }
                demoTap = i
                // blank → blue takes one tap; blank → blue → banana takes two.
                for _ in 0...Self.demoSolution[i] {
                    try? await Task.sleep(for: .seconds(0.14))
                    guard !Task.isCancelled else { return }
                    tapCell(i)
                }
                try? await Task.sleep(for: .seconds(0.14))
            }
            demoTap = nil
            // The last tap completed a legal grid → the real win() ran (onWin is a no-op).
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    // MARK: Flow
    /// Hands this level's board build to `BoardCache` so it can run during the countdown.
    func prefetchBoard() {
        let size = n, frac = clueFrac
        BoardCache.prefetch(boardKey) { BinGen.generate(n: size, clueFrac: frac) }
    }
    private var boardKey: String { BoardCache.key("binairo", level: level) }

    private func run() async {
        let size = n, frac = clueFrac
        let t0 = Date()
        let puzzle = await BoardCache.take(boardKey) { BinGen.generate(n: size, clueFrac: frac) }
        guard !Task.isCancelled else { return }
        await BoardCache.holdBrainstorm(since: t0, minimum: 0.7)
        guard !Task.isCancelled else { return }

        boardN = puzzle.n
        value = puzzle.value
        clues = puzzle.clues
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

// MARK: - Waffle art

/// A golden Belgian waffle with blueberries and banana slices in its pockets.
private enum WaffleArt {
    static func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
    static let batter = c(0.9, 0.64, 0.3)

    private static func disc(_ p: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }

    /// The waffle slab: raised ridges between recessed pockets, toasted edges.
    static func waffle(_ ctx: GraphicsContext, _ b: CGRect, n: Int) {
        let cell = b.width / CGFloat(n)
        let slab = b.insetBy(dx: -cell * 0.22, dy: -cell * 0.22)
        ctx.fill(Path(roundedRect: slab.offsetBy(dx: cell * 0.06, dy: cell * 0.14), cornerRadius: cell * 0.5), with: .color(.black.opacity(0.35)))
        ctx.fill(Path(roundedRect: slab, cornerRadius: cell * 0.5),
                 with: .linearGradient(Gradient(colors: [batter.lit(0.12), batter, c(0.7, 0.42, 0.16)]),
                                       startPoint: CGPoint(x: slab.minX, y: slab.minY), endPoint: CGPoint(x: slab.maxX, y: slab.maxY)))
        ctx.stroke(Path(roundedRect: slab, cornerRadius: cell * 0.5), with: .color(c(0.55, 0.3, 0.1)), lineWidth: max(1, cell * 0.05))
        for r in 0..<n {
            for col in 0..<n {
                let rect = CGRect(x: b.minX + CGFloat(col) * cell, y: b.minY + CGFloat(r) * cell, width: cell, height: cell)
                let pocket = rect.insetBy(dx: cell * 0.12, dy: cell * 0.12)
                let path = Path(roundedRect: pocket, cornerRadius: cell * 0.1)
                ctx.fill(path, with: .linearGradient(Gradient(colors: [c(0.62, 0.36, 0.13), c(0.8, 0.53, 0.24)]),
                                                     startPoint: CGPoint(x: pocket.minX, y: pocket.minY), endPoint: CGPoint(x: pocket.maxX, y: pocket.maxY)))
                // Inner shadow along the top-left walls; the lower-right walls catch the light.
                var g = ctx
                g.clip(to: path)
                g.stroke(path.offsetBy(dx: cell * 0.04, dy: cell * 0.05), with: .color(.black.opacity(0.28)), lineWidth: cell * 0.1)
                ctx.stroke(path, with: .linearGradient(Gradient(colors: [c(0.5, 0.27, 0.08), c(1, 0.82, 0.52)]),
                                                       startPoint: CGPoint(x: pocket.minX, y: pocket.minY), endPoint: CGPoint(x: pocket.maxX, y: pocket.maxY)),
                           lineWidth: max(1, cell * 0.035))
            }
        }
    }

    /// A plump blueberry with its bloom and five-point crown.
    static func blueberry(_ ctx: GraphicsContext, at p: CGPoint, r: CGFloat) {
        ctx.fill(disc(CGPoint(x: p.x + r * 0.1, y: p.y + r * 0.16), r), with: .color(.black.opacity(0.3)))
        ctx.fill(disc(p, r), with: .radialGradient(Gradient(colors: [c(0.46, 0.52, 0.8), c(0.2, 0.25, 0.56), c(0.09, 0.1, 0.28)]),
                                                  center: CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.4), startRadius: 0, endRadius: r * 1.4))
        ctx.fill(disc(CGPoint(x: p.x - r * 0.3, y: p.y - r * 0.2), r * 0.45), with: .color(.white.opacity(0.12)))
        var crown = Path()
        for k in 0..<10 {
            let a = Double(k) / 10 * 2 * .pi - .pi / 2
            let rr = r * (k % 2 == 0 ? 0.26 : 0.1)
            let q = CGPoint(x: p.x + CGFloat(cos(a)) * rr, y: p.y - r * 0.18 + CGFloat(sin(a)) * rr)
            if k == 0 { crown.move(to: q) } else { crown.addLine(to: q) }
        }
        crown.closeSubpath()
        ctx.fill(crown, with: .color(c(0.1, 0.1, 0.24)))
        ctx.fill(disc(CGPoint(x: p.x - r * 0.42, y: p.y - r * 0.48), r * 0.13), with: .color(.white.opacity(0.7)))
    }

    /// A banana slice seen from above: pale flesh, a thin rind edge and the seedy three-lobed core.
    static func bananaSlice(_ ctx: GraphicsContext, at p: CGPoint, r: CGFloat) {
        ctx.fill(disc(CGPoint(x: p.x + r * 0.08, y: p.y + r * 0.14), r), with: .color(.black.opacity(0.25)))
        ctx.fill(disc(p, r), with: .color(c(0.98, 0.86, 0.45)))
        ctx.fill(disc(p, r * 0.9), with: .radialGradient(Gradient(colors: [c(1, 0.98, 0.86), c(0.99, 0.93, 0.7)]),
                                                        center: CGPoint(x: p.x - r * 0.2, y: p.y - r * 0.25), startRadius: 0, endRadius: r))
        for k in 0..<3 {
            let a = Double(k) / 3 * 2 * .pi - .pi / 2
            var lobe = Path()
            lobe.move(to: p)
            lobe.addLine(to: CGPoint(x: p.x + CGFloat(cos(a)) * r * 0.36, y: p.y + CGFloat(sin(a)) * r * 0.36))
            ctx.stroke(lobe, with: .color(c(0.9, 0.78, 0.5)), style: StrokeStyle(lineWidth: r * 0.16, lineCap: .round))
            let seed = CGPoint(x: p.x + CGFloat(cos(a)) * r * 0.2, y: p.y + CGFloat(sin(a)) * r * 0.2)
            ctx.fill(disc(seed, r * 0.05), with: .color(c(0.45, 0.32, 0.18)))
        }
        ctx.stroke(disc(p, r), with: .color(c(0.8, 0.62, 0.25)), lineWidth: max(0.8, r * 0.06))
    }

    /// A swirl of whipped cream under a clue fruit (clues are locked in place).
    static func cream(_ ctx: GraphicsContext, at p: CGPoint, r: CGFloat) {
        var puff = Path()
        for k in 0..<8 {
            let a = Double(k) / 8 * 2 * .pi
            let q = CGPoint(x: p.x + CGFloat(cos(a)) * r * 0.62, y: p.y + CGFloat(sin(a)) * r * 0.62)
            puff.addEllipse(in: CGRect(x: q.x - r * 0.42, y: q.y - r * 0.42, width: r * 0.84, height: r * 0.84))
        }
        ctx.fill(puff, with: .color(.black.opacity(0.15)))
        ctx.fill(puff, with: .radialGradient(Gradient(colors: [.white, c(0.96, 0.94, 0.9)]),
                                            center: CGPoint(x: p.x - r * 0.3, y: p.y - r * 0.3), startRadius: 0, endRadius: r * 1.2))
        ctx.stroke(puff, with: .color(c(0.85, 0.8, 0.74)), lineWidth: max(0.6, r * 0.04))
    }

    /// Glossy honey poured along a finished line.
    static func honey(_ ctx: GraphicsContext, _ rect: CGRect, cell: CGFloat) {
        let path = Path(roundedRect: rect, cornerRadius: cell * 0.3)
        ctx.stroke(path, with: .color(c(0.85, 0.5, 0.05).opacity(0.9)), lineWidth: max(2.5, cell * 0.1))
        ctx.stroke(path, with: .color(c(1, 0.82, 0.3)), lineWidth: max(1.5, cell * 0.05))
        ctx.stroke(path.offsetBy(dx: -cell * 0.02, dy: -cell * 0.02), with: .color(.white.opacity(0.55)), lineWidth: max(0.8, cell * 0.015))
    }
}

/// A red gingham tablecloth (static).
private struct GinghamCloth: View, Equatable {
    var body: some View {
        Canvas { ctx, s in
            ctx.fill(Path(CGRect(origin: .zero, size: s)), with: .color(Color(red: 0.98, green: 0.95, blue: 0.9)))
            let band: CGFloat = 26
            var x: CGFloat = 0
            var k = 0
            while x < s.width {
                if k % 2 == 0 { ctx.fill(Path(CGRect(x: x, y: 0, width: band, height: s.height)), with: .color(Color(red: 0.86, green: 0.2, blue: 0.2).opacity(0.5))) }
                x += band; k += 1
            }
            var y: CGFloat = 0
            k = 0
            while y < s.height {
                if k % 2 == 0 { ctx.fill(Path(CGRect(x: 0, y: y, width: s.width, height: band)), with: .color(Color(red: 0.86, green: 0.2, blue: 0.2).opacity(0.5))) }
                y += band; k += 1
            }
            ctx.fill(Path(CGRect(origin: .zero, size: s)),
                     with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.28)]),
                                           center: CGPoint(x: s.width / 2, y: s.height / 2), startRadius: s.width * 0.35, endRadius: max(s.width, s.height) * 0.75))
        }
        .allowsHitTesting(false)
    }
}
