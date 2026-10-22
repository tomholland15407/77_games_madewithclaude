//
//  FloodItGame.swift
//  A Banana Game
//
//  Brain — Flood-It. The top-left cell owns a flood of its own colour; every cell of that colour
//  connected to it is "yours". Tap a colour from the palette to repaint your whole flood that
//  colour, swallowing any neighbouring cells that already match. Turn the ENTIRE board one colour
//  before you run out of moves (or time) — otherwise it's back to level 1.
//
//  The board is random, but the move budget isn't guessed: a greedy max-capture solver is run many
//  times with randomized tie-breaks, and the budget is the best (fewest) moves it ever found, minus
//  a slack that shrinks each level. Because that solution is a real playthrough, the budget is
//  always beatable — but by L7 you must match an optimized greedy line exactly. Seven levels grow
//  the grid (5×5 → 8×8) and the palette (4 → 6 colours) while the slack disappears.
//

import SwiftUI

enum FloodItGame {
    static let definition = GameDefinition(
        id: "flood-it",
        title: "Color Tide",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Your flood starts at the top-left cell.",
                "Tap a colour to repaint your whole flood, absorbing touching cells that match.",
                "Fill the entire board with one colour before your moves (or the clock) run out.",
            ],
            bulletsVI: [
                "Vùng loang của bạn bắt đầu ở ô trên cùng bên trái.",
                "Chạm một màu để tô lại toàn bộ vùng loang, hút các ô liền kề cùng màu.",
                "Lấp cả bàn bằng một màu duy nhất trước khi hết lượt (hoặc hết giờ).",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(FloodItView(level: level, onWin: onWin, onFail: onFail))
        },
        prefetch: { level in FloodItView(level: level, onWin: {}, onFail: {}).prefetchBoard() }
    )
}

private enum FloodCore {
    /// Indices of the flood region connected to the top-left cell (same colour).
    static func region0(_ g: [Int], _ n: Int) -> [Int] {
        let target = g[0]
        var seen = [Bool](repeating: false, count: g.count)
        seen[0] = true
        var stack = [0]
        var out: [Int] = []
        while let cur = stack.popLast() {
            out.append(cur)
            let r = cur / n, c = cur % n
            let nbrs = [(r - 1, c), (r + 1, c), (r, c - 1), (r, c + 1)]
            for (nr, nc) in nbrs where nr >= 0 && nr < n && nc >= 0 && nc < n {
                let ni = nr * n + nc
                if !seen[ni] && g[ni] == target { seen[ni] = true; stack.append(ni) }
            }
        }
        return out
    }

    static func isMono(_ g: [Int]) -> Bool {
        let first = g[0]
        return g.allSatisfy { $0 == first }
    }

    /// One greedy playthrough: each move repaints the flood the colour that captures the most cells.
    /// Colour order is shuffled so ties break randomly, letting repeated runs find shorter lines.
    static func greedyMoves(_ start: [Int], n: Int, colors: Int) -> Int {
        var g = start
        var moves = 0
        var guardCount = 0
        while !isMono(g) {
            guardCount += 1
            if guardCount > n * n * colors + 50 { break }
            let region = region0(g, n)
            let cur = g[0]
            var bestX = cur, bestGain = -1
            for x in Array(0..<colors).shuffled() where x != cur {
                var gg = g
                for i in region { gg[i] = x }
                let sz = region0(gg, n).count
                if sz > bestGain { bestGain = sz; bestX = x }
            }
            for i in region { g[i] = bestX }
            moves += 1
        }
        return moves
    }

    static func makeBoard(n: Int, colors: Int) -> [Int] {
        var g = (0..<n * n).map { _ in Int.random(in: 0..<colors) }
        // never start monochrome
        var tries = 0
        while isMono(g) && tries < 8 {
            g = (0..<n * n).map { _ in Int.random(in: 0..<colors) }
            tries += 1
        }
        return g
    }
}

struct FloodItView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    private var n: Int { [5, 6, 6, 7, 7, 8, 8][min(level, 7) - 1] }
    private var colorCount: Int { [4, 4, 5, 5, 6, 6, 6][min(level, 7) - 1] }
    private var slack: Int { [3, 3, 2, 2, 1, 1, 0][min(level, 7) - 1] }
    private var timeLimit: Double { [45, 50, 55, 60, 60, 55, 50][min(level, 7) - 1] }

    // Lab Pixies' Flood-It! colours, ordered so the 4- and 5-colour levels get the most distinct ones.
    private let palette: [Color] = [
        Color(red: 0.984, green: 0.894, blue: 0.200),   // yellow  #FBE433
        Color(red: 0.122, green: 0.439, blue: 0.965),   // blue    #1F70F6
        Color(red: 0.957, green: 0.349, blue: 0.490),   // pink    #F4597D
        Color(red: 0.227, green: 0.855, blue: 0.173),   // green   #3ADA2C
        Color(red: 0.573, green: 0.365, blue: 0.749),   // purple  #925DBF
        Color(red: 0.945, green: 0.522, blue: 0.098),   // orange  #F18519
    ]

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var boardN = 0
    @State private var colors = 0
    @State private var grid: [Int] = []
    @State private var budget = 0
    @State private var moves = 0
    @State private var timeLeft = 0.0
    @State private var ready = false
    @State private var loopTask: Task<Void, Never>?
    @State private var demoPress: Int? = nil    // palette colour the demo is pressing

    /// Presentation only: the new colour pouring out from the corner, one flood-ring at a time.
    private struct Ripple { let id = UUID(); let from: [Int]; let ring: [Int: Int]; let step: Double; let t0: Date }
    @State private var ripple: Ripple? = nil
    private static let popTime = 0.14

    var body: some View {
        Group {
            if ready { gameBody } else { Color.black }
        }
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
    }

    /// The Flood-It! app screen: black, "Step n / budget", a seamless board, a row of round colour buttons.
    private var gameBody: some View {
        GeometryReader { geo in
            let gap: CGFloat = isDemo ? 9 : 16
            let headH: CGFloat = isDemo ? 20 : 28
            let barH: CGFloat = isDemo ? 0 : 4
            let btn: CGFloat = isDemo ? 38 : 50
            let rows: CGFloat = isDemo ? 3 : 4
            let side = max(40, min(geo.size.width - (isDemo ? 24 : 36),
                                   geo.size.height - headH - barH - btn - gap * rows - (isDemo ? 12 : 24)))
            VStack(spacing: gap) {
                Text(L("Step \(moves) / \(budget)", "Bước \(moves) / \(budget)"))
                    .font(.system(size: isDemo ? 16 : 22, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .frame(width: side, height: headH, alignment: .leading)
                if !isDemo { timeBar.frame(width: side, height: barH) }
                TimelineView(.animation(paused: ripple == nil)) { tl in
                    Canvas { ctx, size in drawBoard(ctx, side: size.width, now: tl.date) }
                }
                .frame(width: side, height: side)
                colorButtons(size: btn).frame(width: side + (isDemo ? 16 : 20), height: btn)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
    }

    /// Flat, seamless squares. While a move ripples, each cell of your old flood pops to the new colour
    /// in the order the flood reaches it from the top-left corner.
    private func drawBoard(_ ctx: GraphicsContext, side: CGFloat, now: Date) {
        let n = boardN
        guard n > 0, grid.count == n * n else { return }
        let cell = side / CGFloat(n)
        let anim = ripple.flatMap { $0.from.count == n * n ? $0 : nil }
        for i in 0..<n * n {
            // Each square bleeds a hair into its neighbours so no seams show between them.
            let rc = CGRect(x: CGFloat(i % n) * cell, y: CGFloat(i / n) * cell, width: cell, height: cell).insetBy(dx: -0.4, dy: -0.4)
            if let a = anim, let ring = a.ring[i] {
                let t = (now.timeIntervalSince(a.t0) - Double(ring) * a.step) / Self.popTime
                if t < 1 {
                    ctx.fill(Path(rc), with: .color(palette[a.from[i]]))
                    guard t > 0 else { continue }
                    let p = CGFloat(1 - pow(1 - t, 2))
                    let k = cell * 0.5 * (1 - p)
                    // The last sliver snaps to the full square, so no hairline of the old colour lingers.
                    let pop = k < 1 ? Path(rc) : Path(roundedRect: rc.insetBy(dx: k, dy: k), cornerRadius: k * 0.6)
                    ctx.fill(pop, with: .color(palette[grid[i]]))
                    continue
                }
            }
            ctx.fill(Path(rc), with: .color(palette[grid[i]]))
        }
    }

    private func colorButtons(size: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<colors, id: \.self) { x in
                Button { play(x) } label: {
                    Circle()
                        .fill(palette[x])
                        .frame(width: size, height: size)
                        // Demo-only press: a white ring + shrink on the colour being tapped.
                        .overlay { if demoPress == x { Circle().stroke(.white, lineWidth: 3.5) } }
                        .scaleEffect(demoPress == x ? 0.84 : 1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FloodButtonStyle())
                .disabled(phase == .done || grid.first == x)
            }
        }
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(white: 0.16))
                Rectangle().fill(frac < 0.3 ? palette[2] : .white).frame(width: geo.size.width * frac)
            }
        }
    }

    /// Presentation only: remembers the colours before a move and how many flood-steps each cell of
    /// the repainted region is from the corner, so the new colour can pour outwards.
    private func recordRipple(from before: [Int], region: [Int]) {
        let n = boardN
        let inRegion = Set(region)
        var ring: [Int: Int] = [0: 0]
        var queue = [0], head = 0
        while head < queue.count {
            let cur = queue[head]; head += 1
            let r = cur / n, c = cur % n
            for (nr, nc) in [(r - 1, c), (r + 1, c), (r, c - 1), (r, c + 1)] where nr >= 0 && nr < n && nc >= 0 && nc < n {
                let ni = nr * n + nc
                if inRegion.contains(ni) && ring[ni] == nil { ring[ni] = ring[cur]! + 1; queue.append(ni) }
            }
        }
        let deepest = ring.values.max() ?? 0
        let step = min(0.035, 0.4 / Double(max(1, deepest)))
        let r = Ripple(from: before, ring: ring, step: step, t0: Date())
        ripple = r
        Task {
            try? await Task.sleep(for: .seconds(Double(deepest) * step + Self.popTime + 0.05))
            if ripple?.id == r.id { ripple = nil }
        }
    }

    // MARK: Input
    private func play(_ x: Int) {
        guard phase == .play, !grid.isEmpty, grid[0] != x else { return }
        let before = grid                                   // presentation: the colours the ripple starts from
        let region = FloodCore.region0(grid, boardN)
        for i in region { grid[i] = x }
        recordRipple(from: before, region: region)          // presentation only
        moves += 1
        SoundManager.shared.tap(); Haptics.tap()
        if FloodCore.isMono(grid) { win(); return }
        if moves >= budget { fail() }
    }

    // MARK: Demo (live manual clip)
    // A fixed Level-1 board (5×5, 4 colours). Its optimal solve is 7 moves (BFS-verified) and the
    // game's own 24-run greedy also finds 7, so the real budget is 7 + slack 3 = 10. The demo
    // presses the optimal colours through the real `play()`; the 7th floods the board → win.
    private static let demoBoard = [0, 3, 1, 2, 0,
                                    1, 3, 0, 3, 2,
                                    1, 3, 0, 1, 3,
                                    2, 1, 2, 2, 3,
                                    3, 0, 0, 1, 2]
    private static let demoMoves = [3, 1, 0, 1, 3, 2, 0]

    private func runDemo() async {
        while !Task.isCancelled {
            boardN = 5
            colors = 4
            grid = Self.demoBoard
            budget = 7 + slack
            moves = 0
            demoPress = nil
            ripple = nil
            timeLeft = timeLimit
            phase = .play
            ready = true
            try? await Task.sleep(for: .seconds(0.6))
            for x in Self.demoMoves {
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.1)) { demoPress = x }
                try? await Task.sleep(for: .seconds(0.3))
                guard !Task.isCancelled else { return }
                play(x)
                try? await Task.sleep(for: .seconds(0.15))
                withAnimation(.easeOut(duration: 0.1)) { demoPress = nil }
                try? await Task.sleep(for: .seconds(0.3))
            }
            // The last colour flooded the board → the real win() ran (onWin is a no-op).
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    // MARK: Flow
    /// Hands this level's board build to `BoardCache` so it can run during the countdown.
    func prefetchBoard() {
        let size = n, cc = colorCount
        BoardCache.prefetch(boardKey) { Self.build(n: size, colors: cc) }
    }
    private var boardKey: String { BoardCache.key("flood-it", level: level) }

    /// The board plus its greedy-solver move baseline (the level budget = baseline + slack).
    private nonisolated static func build(n size: Int, colors cc: Int) -> ([Int], Int) {
        let g = FloodCore.makeBoard(n: size, colors: cc)
        var best = Int.max
        for _ in 0..<24 { best = min(best, FloodCore.greedyMoves(g, n: size, colors: cc)) }
        return (g, best == Int.max ? size * size : best)
    }

    private func run() async {
        let size = n, cc = colorCount, sl = slack
        let (board, base) = await BoardCache.take(boardKey) { Self.build(n: size, colors: cc) }
        guard !Task.isCancelled else { return }

        boardN = size
        colors = cc
        grid = board
        budget = base + sl
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

    private func win() {
        guard phase != .done else { return }
        phase = .done; loopTask?.cancel(); onWin()
    }
    private func fail() {
        guard phase != .done else { return }
        phase = .done; loopTask?.cancel(); SoundManager.shared.error(); onFail()
    }
}

/// Round colour buttons: a real press shrinks them, and nothing dims when a button is disabled.
private struct FloodButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.88 : 1)
    }
}
