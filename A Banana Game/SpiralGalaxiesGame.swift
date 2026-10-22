//
//  SpiralGalaxiesGame.swift
//  A Banana Game
//
//  Brain — Spiral Galaxies (Nikoli's Tentai Show). Carve the whole grid into "galaxies": every
//  galaxy must contain exactly one star and be 180°-rotationally symmetric about it (spin the
//  region half a turn around its star and it lands on itself). Tap a cell to claim it for a star —
//  each tap cycles the cell through only the stars it could legally belong to (the ones whose mirror
//  of that cell stays on the board), then back to unclaimed. Fill every cell into a valid galaxy
//  before the clock runs out or you drop to level 1.
//
//  Boards are built solved-first: symmetric regions are grown in mirror-image pairs around random
//  star cells until the grid is tiled, so a legal partition always exists (and single-cell galaxies
//  are capped so the board is never trivial). The player starts with everything unclaimed, so it
//  can't begin solved; the win check re-proves each galaxy is connected, centered on its star, and
//  symmetric. Generation runs off-main behind the shared brainstorming banana. Seven levels grow the
//  grid (5×5 → 8×8) and the galaxy sizes while the clock tightens.
//

import SwiftUI

enum SpiralGalaxiesGame {
    static let definition = GameDefinition(
        id: "spiral-galaxies",
        title: "Spiral Galaxies",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Split the grid into galaxies — each holds exactly one star.",
                "Every galaxy must look identical when rotated 180° around its star.",
                "Tap a cell to cycle it through the stars it could join; fill the grid before time runs out.",
            ],
            bulletsVI: [
                "Chia lưới thành các thiên hà — mỗi thiên hà chứa đúng một ngôi sao.",
                "Mỗi thiên hà phải giống hệt khi xoay 180° quanh ngôi sao của nó.",
                "Chạm một ô để luân chuyển qua các sao nó có thể thuộc về; lấp đầy lưới trước khi hết giờ.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(SpiralGalaxiesView(level: level, onWin: onWin, onFail: onFail))
        },
        prefetch: { level in SpiralGalaxiesView(level: level, onWin: {}, onFail: {}).prefetchBoard() }
    )
}

/// A tiny seeded SplitMix64 RNG so the manual demo grows the same board every time.
private struct DemoRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private enum SGGen {
    static func mirror(_ cell: Int, _ center: Int, _ n: Int) -> Int? {
        let r = cell / n, c = cell % n
        let dr = center / n, dc = center % n
        let mr = 2 * dr - r, mc = 2 * dc - c
        if mr < 0 || mr >= n || mc < 0 || mc >= n { return nil }
        return mr * n + mc
    }

    static func orthNeighbors(_ cell: Int, _ n: Int) -> [Int] {
        let r = cell / n, c = cell % n
        var out: [Int] = []
        if r > 0 { out.append((r - 1) * n + c) }
        if r < n - 1 { out.append((r + 1) * n + c) }
        if c > 0 { out.append(r * n + c - 1) }
        if c < n - 1 { out.append(r * n + c + 1) }
        return out
    }

    /// Build a symmetric tiling and return the star cells (region centers). Regions are grown in
    /// mirror-image pairs with a floor of two pairs (≥5 cells) so the board doesn't collapse into a
    /// field of single-cell stars. The least-degenerate attempt is kept as a safety net.
    static func generate(n: Int, maxPairs: Int) -> [Int] {
        var best: [Int] = Array(0..<n * n)
        var bestSingletons = Int.max
        for _ in 0..<200 {
            var region = [Int](repeating: -1, count: n * n)
            var dots: [Int] = []
            var rid = 0
            for seed in Array(0..<n * n).shuffled() where region[seed] == -1 {
                let center = seed
                region[seed] = rid
                var members = [seed]
                let target = Int.random(in: 2...(maxPairs + 1))    // ≥2 mirror pairs when room allows
                var guardCount = 0
                while members.count < target * 2 + 1 && guardCount < 300 {
                    guardCount += 1
                    var pairs: [(Int, Int)] = []
                    let memberSet = Set(members)
                    for m in members {
                        for nb in orthNeighbors(m, n) where region[nb] == -1 {
                            if let v = mirror(nb, center, n), v != nb, region[v] == -1, !memberSet.contains(v) {
                                pairs.append((nb, v))
                            }
                        }
                    }
                    guard let (u, v) = pairs.randomElement() else { break }
                    region[u] = rid; region[v] = rid
                    members.append(u); members.append(v)
                }
                dots.append(center)
                rid += 1
            }
            var sizes = [Int](repeating: 0, count: dots.count)
            for v in region { sizes[v] += 1 }
            let singletons = sizes.filter { $0 == 1 }.count
            if singletons < bestSingletons { bestSingletons = singletons; best = dots }
            // Accept a board with few singletons that still leaves plenty of blank cells to claim.
            if singletons <= max(1, n / 3) && dots.count <= (n * n) / 2 { return dots }
        }
        return best
    }
}

struct SpiralGalaxiesView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    private var n: Int { [5, 6, 6, 7, 7, 8, 8][min(level, 7) - 1] }
    private var maxPairs: Int { [2, 2, 3, 3, 4, 4, 5][min(level, 7) - 1] }
    private var timeLimit: Double { [65, 70, 75, 80, 85, 85, 80][min(level, 7) - 1] }

    private let skyTop = Color(red: 0.07, green: 0.06, blue: 0.16)
    private let skyBottom = Color(red: 0.02, green: 0.02, blue: 0.07)

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var boardN = 0
    @State private var dots: [Int] = []
    @State private var cellRegion: [Int] = []              // -1 = unclaimed, else dot index
    @State private var candidatesPerCell: [[Int]] = []     // dot indices legal for each cell
    @State private var timeLeft = 0.0
    @State private var ready = false
    @State private var loopTask: Task<Void, Never>?
    @State private var demoSolution: [Int] = []            // the solved region per cell (demo)
    @State private var demoCell: Int? = nil                 // demo finger

    private var unclaimed: Int { cellRegion.filter { $0 == -1 }.count }

    var body: some View {
        Group {
            if ready { gameBody } else { BrainstormingView(skyTop: skyTop, skyBottom: skyBottom) }
        }
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
    }

    // MARK: - Demo (live manual clip)

    /// A real, varied 5×5 galaxy tiling (not trivial stripes) grown deterministically in
    /// mirror-pairs — so each region is genuinely 180°-symmetric about its star, connected
    /// and star-owned. Fills the board one galaxy at a time; the real `isSolved()` accepts it.
    private func runDemo() async {
        while !Task.isCancelled {
            demoSetup()
            try? await Task.sleep(for: .seconds(0.6))
            // Reveal galaxy by galaxy: star first (its own cell), then its symmetric pairs.
            for rid in dots.indices {
                let center = dots[rid]
                let members = (0..<boardN * boardN)
                    .filter { demoSolution[$0] == rid }
                    .sorted { a, b in
                        (a == center ? 0 : 1, a) < (b == center ? 0 : 1, b)
                    }
                for i in members {
                    guard !Task.isCancelled else { return }
                    demoCell = i
                    withAnimation(.easeOut(duration: 0.14)) { cellRegion[i] = rid }
                    try? await Task.sleep(for: .seconds(0.11))
                }
                try? await Task.sleep(for: .seconds(0.12))
            }
            demoCell = nil
            if isSolved() { win() }              // onWin is a no-op; the board is genuinely solved
            try? await Task.sleep(for: .seconds(1.5))
        }
    }

    private func demoSetup() {
        let n = 5
        let built = Self.demoTiling(n: n)
        boardN = n
        dots = built.dots
        demoSolution = built.region
        cellRegion = [Int](repeating: -1, count: n * n)
        var cands = [[Int]](repeating: [], count: n * n)
        for i in 0..<n * n {
            var list: [(Int, Int)] = []
            for (di, center) in dots.enumerated() where SGGen.mirror(i, center, n) != nil {
                let dr = i / n - center / n, dc = i % n - center % n
                list.append((di, dr * dr + dc * dc))
            }
            cands[i] = list.sorted { $0.1 < $1.1 }.map { $0.0 }
        }
        candidatesPerCell = cands
        ready = true
        phase = .play
        timeLeft = timeLimit
    }

    /// Deterministically grow a legal galaxy tiling (region id per cell + star cells),
    /// mirroring `SGGen.generate` but seeded and recording the full partition so the demo
    /// has a known solution. Favours a few multi-cell galaxies for a non-trivial board.
    private static func demoTiling(n: Int) -> (region: [Int], dots: [Int]) {
        var rng = DemoRNG(seed: 0xB16B_00B5_1234_5678)
        var region = [Int](repeating: -1, count: n * n)
        var dots: [Int] = []
        var rid = 0
        for seed in Array(0..<n * n).shuffled(using: &rng) where region[seed] == -1 {
            let center = seed
            region[seed] = rid
            var members = [seed]
            let target = Int.random(in: 2...4, using: &rng)     // ≥2 mirror pairs when there's room
            var guardCount = 0
            while members.count < target * 2 + 1 && guardCount < 300 {
                guardCount += 1
                var pairs: [(Int, Int)] = []
                let memberSet = Set(members)
                for m in members {
                    for nb in SGGen.orthNeighbors(m, n) where region[nb] == -1 {
                        if let v = SGGen.mirror(nb, center, n), v != nb, region[v] == -1, !memberSet.contains(v) {
                            pairs.append((nb, v))
                        }
                    }
                }
                guard let pick = pairs.randomElement(using: &rng) else { break }
                region[pick.0] = rid; region[pick.1] = rid
                members.append(pick.0); members.append(pick.1)
            }
            dots.append(center)
            rid += 1
        }
        return (region, dots)
    }

    private var gameBody: some View {
        VStack(spacing: isDemo ? 6 : 12) {
            Text(L("\(unclaimed) cells to claim", "còn \(unclaimed) ô cần chia"))
                .font(.system(size: isDemo ? 17 : 20, weight: .black, design: .rounded))
                .foregroundStyle(unclaimed == 0 ? Color(red: 1, green: 0.85, blue: 0.4) : .white)
                .contentTransition(.numericText())
            if !isDemo { timeBar.frame(height: 6).padding(.horizontal, 50) }

            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height) * 0.98
                let cell = boardN > 0 ? side / CGFloat(boardN) : 0
                let ox = (geo.size.width - cell * CGFloat(boardN)) / 2
                let oy = (geo.size.height - cell * CGFloat(boardN)) / 2
                ZStack {
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
        .background(SpaceBackdrop().equatable())
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Deep space: claimed cells glow as a nebula around their star; a finished galaxy gets spiral arms.
    private func boardCanvas(cell: CGFloat, ox: CGFloat, oy: CGFloat) -> some View {
        Canvas { ctx, _ in
            let n = boardN
            guard n > 0, cellRegion.count == n * n else { return }
            func rect(_ i: Int) -> CGRect {
                CGRect(x: ox + CGFloat(i % n) * cell, y: oy + CGFloat(i / n) * cell, width: cell, height: cell)
            }
            func center(_ i: Int) -> CGPoint { CGPoint(x: rect(i).midX, y: rect(i).midY) }
            let panel = CGRect(x: ox, y: oy, width: cell * CGFloat(n), height: cell * CGFloat(n))
            ctx.fill(Path(roundedRect: panel.insetBy(dx: -4, dy: -4), cornerRadius: 12), with: .color(.black.opacity(0.35)))
            // The empty grid: faint cell frames in the dark.
            for i in 0..<n * n {
                ctx.stroke(Path(roundedRect: rect(i).insetBy(dx: 1.5, dy: 1.5), cornerRadius: cell * 0.14),
                           with: .color(.white.opacity(0.08)), lineWidth: 1)
            }
            // Nebula glow: each claimed cell brightens toward its own star.
            for i in 0..<n * n where cellRegion[i] >= 0 {
                let rid = cellRegion[i]
                let col = SpaceArt.nebula(rid)
                let star = center(dots[rid])
                let d = hypot(center(i).x - star.x, center(i).y - star.y) / cell
                let strength = max(0.28, 0.62 - 0.1 * Double(d))
                let rc = rect(i).insetBy(dx: 1.5, dy: 1.5)
                ctx.fill(Path(roundedRect: rc, cornerRadius: cell * 0.14),
                         with: .radialGradient(Gradient(colors: [col.lit(0.25).opacity(strength), col.opacity(strength * 0.7)]),
                                               center: CGPoint(x: rc.midX, y: rc.midY), startRadius: 0, endRadius: cell * 0.7))
            }
            // Finished galaxies: spiral arms inside the region, then a crisp white rim.
            let correct = correctGalaxyCells()
            var doneRegions = Set<Int>()
            for i in correct { doneRegions.insert(cellRegion[i]) }
            for rid in doneRegions {
                var clip = Path()
                for i in 0..<n * n where cellRegion[i] == rid { clip.addRect(rect(i).insetBy(dx: 1, dy: 1)) }
                var g = ctx
                g.clip(to: clip)
                SpaceArt.spiral(g, at: center(dots[rid]), cell: cell, color: SpaceArt.nebula(rid), seed: rid)
            }
            if !correct.isEmpty {
                var outline = Path()
                for i in correct {
                    let r = i / n, c = i % n
                    let x0 = ox + CGFloat(c) * cell, y0 = oy + CGFloat(r) * cell
                    let region = cellRegion[i]
                    if r == 0 || cellRegion[(r - 1) * n + c] != region {
                        outline.move(to: CGPoint(x: x0, y: y0)); outline.addLine(to: CGPoint(x: x0 + cell, y: y0))
                    }
                    if r == n - 1 || cellRegion[(r + 1) * n + c] != region {
                        outline.move(to: CGPoint(x: x0, y: y0 + cell)); outline.addLine(to: CGPoint(x: x0 + cell, y: y0 + cell))
                    }
                    if c == 0 || cellRegion[r * n + c - 1] != region {
                        outline.move(to: CGPoint(x: x0, y: y0)); outline.addLine(to: CGPoint(x: x0, y: y0 + cell))
                    }
                    if c == n - 1 || cellRegion[r * n + c + 1] != region {
                        outline.move(to: CGPoint(x: x0 + cell, y: y0)); outline.addLine(to: CGPoint(x: x0 + cell, y: y0 + cell))
                    }
                }
                ctx.stroke(outline, with: .color(.white), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            // Stars: a hot core with a four-point glint; gold once their galaxy is complete.
            for (rid, d) in dots.enumerated() {
                SpaceArt.star(ctx, at: center(d), cell: cell, done: doneRegions.contains(rid))
            }
            // Demo finger on the cell being claimed.
            if isDemo, let i = demoCell, i < n * n {
                var hand = ctx.resolve(Image(systemName: "hand.point.up.left.fill"))
                hand.shading = .color(.white)
                var h = ctx
                h.addFilter(.shadow(color: .black.opacity(0.6), radius: 3))
                let hw = cell * 0.62
                h.draw(hand, in: CGRect(x: center(i).x, y: center(i).y + cell * 0.05, width: hw, height: hw))
            }
        }
    }
    private var timeBar: some View {
        GeometryReader { geo in
            let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(frac < 0.3 ? .red : BananaTheme.banana).frame(width: geo.size.width * frac)
            }
        }
    }

    // MARK: Input
    private func handleTap(_ loc: CGPoint, cell: CGFloat, ox: CGFloat, oy: CGFloat) {
        guard phase == .play, cell > 0 else { return }
        let c = Int((loc.x - ox) / cell)
        let r = Int((loc.y - oy) / cell)
        guard r >= 0, r < boardN, c >= 0, c < boardN else { return }
        let i = r * boardN + c
        let cands = candidatesPerCell[i]
        let cur = cellRegion[i]
        let next: Int
        if cur == -1 {
            next = cands.first ?? -1
        } else if let pos = cands.firstIndex(of: cur), pos + 1 < cands.count {
            next = cands[pos + 1]
        } else {
            next = -1
        }
        cellRegion[i] = next
        SoundManager.shared.tap(); Haptics.tap()
        if unclaimed == 0, isSolved() { win() }
    }

    // MARK: Win check
    private func isSolved() -> Bool {
        if cellRegion.contains(-1) { return false }
        // each star owns its own cell
        for (idx, center) in dots.enumerated() where cellRegion[center] != idx { return false }
        var byDot: [Int: [Int]] = [:]
        for i in 0..<boardN * boardN { byDot[cellRegion[i], default: []].append(i) }
        for (dotIdx, cells) in byDot {
            let center = dots[dotIdx]
            let set = Set(cells)
            guard set.contains(center) else { return false }
            for x in cells {
                guard let m = SGGen.mirror(x, center, boardN), set.contains(m) else { return false }
            }
            if !isConnected(cells) { return false }
        }
        return true
    }

    private func isConnected(_ cells: [Int]) -> Bool {
        guard let start = cells.first else { return true }
        let set = Set(cells)
        var seen: Set<Int> = [start]
        var stack = [start]
        while let cur = stack.popLast() {
            for nb in SGGen.orthNeighbors(cur, boardN) where set.contains(nb) && !seen.contains(nb) {
                seen.insert(nb); stack.append(nb)
            }
        }
        return seen.count == set.count
    }

    /// Cells that belong to a galaxy that is already valid on its own (contains its star, is
    /// symmetric about it, and connected) — used to draw the live white outline.
    private func correctGalaxyCells() -> Set<Int> {
        guard !cellRegion.isEmpty else { return [] }
        var byDot: [Int: [Int]] = [:]
        for i in 0..<boardN * boardN where cellRegion[i] >= 0 { byDot[cellRegion[i], default: []].append(i) }
        var out = Set<Int>()
        for (dotIdx, cells) in byDot {
            let center = dots[dotIdx]
            let set = Set(cells)
            guard set.contains(center) else { continue }
            var symmetric = true
            for x in cells where !(SGGen.mirror(x, center, boardN).map { set.contains($0) } ?? false) {
                symmetric = false; break
            }
            if symmetric && isConnected(cells) { out.formUnion(cells) }
        }
        return out
    }

    // MARK: Flow
    /// Hands this level's board build to `BoardCache` so it can run during the countdown.
    func prefetchBoard() {
        let size = n, mp = maxPairs
        BoardCache.prefetch(boardKey) { SGGen.generate(n: size, maxPairs: mp) }
    }
    private var boardKey: String { BoardCache.key("spiral-galaxies", level: level) }

    private func run() async {
        let size = n, mp = maxPairs
        let t0 = Date()
        let starCells = await BoardCache.take(boardKey) { SGGen.generate(n: size, maxPairs: mp) }
        guard !Task.isCancelled else { return }
        await BoardCache.holdBrainstorm(since: t0, minimum: 0.7)
        guard !Task.isCancelled else { return }

        boardN = size
        dots = starCells
        cellRegion = [Int](repeating: -1, count: size * size)
        // legal owning stars for each cell (mirror must stay on the board), nearest first
        var cands = [[Int]](repeating: [], count: size * size)
        for i in 0..<size * size {
            var list: [(Int, Int)] = []       // (dotIndex, squaredDistance)
            for (di, center) in starCells.enumerated() where SGGen.mirror(i, center, size) != nil {
                let dr = i / size - center / size, dc = i % size - center % size
                list.append((di, dr * dr + dc * dc))
            }
            cands[i] = list.sorted { $0.1 < $1.1 }.map { $0.0 }
        }
        candidatesPerCell = cands

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

// MARK: - Space art

/// Nebula colours, stars and spiral arms for the galaxies.
private enum SpaceArt {
    static let hues: [Color] = [
        Color(red: 1.0, green: 0.78, blue: 0.35),   // gold
        Color(red: 0.35, green: 0.78, blue: 1.0),   // cyan
        Color(red: 1.0, green: 0.42, blue: 0.62),   // magenta
        Color(red: 0.66, green: 0.52, blue: 1.0),   // violet
        Color(red: 0.42, green: 0.92, blue: 0.62),  // green
        Color(red: 1.0, green: 0.58, blue: 0.3),    // orange
    ]
    static func nebula(_ i: Int) -> Color { hues[((i % hues.count) + hues.count) % hues.count] }

    /// A star: soft halo, a four-point glint and a hot core (gold when its galaxy is complete).
    static func star(_ ctx: GraphicsContext, at p: CGPoint, cell: CGFloat, done: Bool) {
        let core = done ? Color(red: 1, green: 0.86, blue: 0.35) : .white
        let r = cell * 0.16
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 3, y: p.y - r * 3, width: r * 6, height: r * 6)),
                 with: .radialGradient(Gradient(colors: [core.opacity(0.55), core.opacity(0)]), center: p, startRadius: 0, endRadius: r * 3))
        var glint = Path()
        for (dx, dy) in [(1.0, 0.0), (0.0, 1.0)] as [(CGFloat, CGFloat)] {
            glint.move(to: CGPoint(x: p.x - dx * r * 2.6, y: p.y - dy * r * 2.6))
            glint.addQuadCurve(to: CGPoint(x: p.x + dx * r * 2.6, y: p.y + dy * r * 2.6), control: p)
        }
        ctx.stroke(glint, with: .color(core.opacity(0.9)), lineWidth: max(1, cell * 0.035))
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(core))
        ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(.black.opacity(0.35)), lineWidth: 1)
    }

    /// Two logarithmic spiral arms swirling out of the star (the caller clips them to the galaxy).
    static func spiral(_ ctx: GraphicsContext, at p: CGPoint, cell: CGFloat, color: Color, seed: Int) {
        let turn = Double(seed) * 1.3
        for arm in 0..<2 {
            var path = Path()
            var dots: [CGPoint] = []
            for k in 0...60 {
                let th = Double(k) / 60 * 3.4 * .pi
                let r = cell * 0.18 * CGFloat(exp(0.2 * th))
                let a = th + Double(arm) * .pi + turn
                let q = CGPoint(x: p.x + CGFloat(cos(a)) * r, y: p.y + CGFloat(sin(a)) * r)
                if k == 0 { path.move(to: q) } else { path.addLine(to: q) }
                if k % 9 == 4 { dots.append(q) }
            }
            ctx.stroke(path, with: .color(color.lit(0.3).opacity(0.35)), style: StrokeStyle(lineWidth: cell * 0.32, lineCap: .round))
            ctx.stroke(path, with: .color(color.lit(0.6).opacity(0.85)), style: StrokeStyle(lineWidth: max(1.5, cell * 0.08), lineCap: .round))
            for d in dots {
                ctx.fill(Path(ellipseIn: CGRect(x: d.x - 1.5, y: d.y - 1.5, width: 3, height: 3)), with: .color(.white.opacity(0.9)))
            }
        }
    }
}

/// Deep space behind the board: an indigo sky, faint nebula haze and a fixed starfield (static).
private struct SpaceBackdrop: View, Equatable {
    var body: some View {
        Canvas { ctx, s in
            ctx.fill(Path(CGRect(origin: .zero, size: s)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.08, green: 0.06, blue: 0.2), Color(red: 0.02, green: 0.02, blue: 0.07)]),
                                           startPoint: .zero, endPoint: CGPoint(x: s.width * 0.3, y: s.height)))
            for (fx, fy, fr, col) in [(0.2, 0.25, 0.5, Color(red: 0.6, green: 0.2, blue: 0.8)), (0.85, 0.7, 0.55, Color(red: 0.1, green: 0.4, blue: 0.9)),
                                      (0.5, 0.9, 0.4, Color(red: 0.9, green: 0.3, blue: 0.5))] as [(CGFloat, CGFloat, CGFloat, Color)] {
                let c = CGPoint(x: s.width * fx, y: s.height * fy)
                let r = max(s.width, s.height) * fr
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .radialGradient(Gradient(colors: [col.opacity(0.18), .clear]), center: c, startRadius: 0, endRadius: r))
            }
            for k in 0..<120 {
                let fx = CGFloat((sin(Double(k) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)).magnitude
                let fy = CGFloat((sin(Double(k) * 78.233) * 24634.6345).truncatingRemainder(dividingBy: 1)).magnitude
                let r = 0.5 + CGFloat(k % 4) * 0.35
                ctx.fill(Path(ellipseIn: CGRect(x: fx * s.width, y: fy * s.height, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(0.25 + 0.15 * Double(k % 3))))
            }
        }
        .allowsHitTesting(false)
    }
}
