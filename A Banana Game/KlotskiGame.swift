//
//  KlotskiGame.swift
//  A Banana Game
//
//  Brain — Klotski (Huarong Pass). A 4×5 tray is jammed with sliding blocks and just two empty
//  cells. Drag a block into the gaps — blocks only slide, never lift or rotate — and work the big
//  2×2 BANANA block down to the exit slot at the bottom centre. It's feed-locked while you play
//  (drag to slide) with a skip button to bail. No wrong move can lose it, so the clock is the fail:
//  run out of time and you're back to level 1.
//
//  Each board (L1–L6) is a fresh random packing: the big block drops at a random 2×2 spot (never on
//  the exit) and the classic piece set fills the rest by exact-cover backtracking. A BFS over the
//  reduced state space (same-shape blocks are interchangeable) verifies it's solvable and needs at
//  least the level's minimum number of slides — so easy placements are rejected and difficulty climbs
//  gently. L7 is the real thing: the classic Huarong Dao (81-move) escape as the final boss. Clocks
//  are deliberately generous. Generation runs off-main behind the shared brainstorming banana.
//

import SwiftUI

enum KlotskiGame {
    static let definition = GameDefinition(
        id: "klotski",
        title: "Free the Banana",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        locksFeed: true,
        manual: GameManual(
            bullets: [
                "Drag blocks into the two empty cells — blocks slide only, never rotate.",
                "Work the big 2×2 banana block down to the exit slot at the bottom centre.",
                "Only the clock can beat you, so plan quickly.",
            ],
            bulletsVI: [
                "Kéo các khối vào hai ô trống — khối chỉ trượt, không xoay.",
                "Đưa khối chuối lớn 2×2 xuống ô thoát ở giữa dưới cùng.",
                "Chỉ có đồng hồ mới thắng được bạn, nên hãy tính nhanh.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(KlotskiView(level: level, onWin: onWin, onFail: onFail))
        },
        prefetch: { level in KlotskiView(level: level, onWin: {}, onFail: {}).prefetchBoard() }
    )

    /// Warm the one-time (~1–2s) grouped-move distance map off-main at launch, so the first time the
    /// feed scrolls to Klotski it never hitches building it. Safe to call more than once — the map is
    /// a thread-safe lazy `static let`, so this just forces its first access early.
    static func prewarm() {
        // Wait out the launch + splash entrance so this ~1–2s compute never competes with the
        // first frames' animation (most visible on the Simulator's limited cores). Klotski lives
        // deep in the feed, so a short delay before warming its map is harmless.
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(1.5))
            _ = KlotskiGen.distanceMap
        }
    }
}

private enum KlotskiGen {
    static let cols = 4
    static let rows = 5
    static let goalCells = [13, 14, 17, 18]     // 2×2 exit: rows 3-4, cols 1-2 (bottom-centre)
    static let goalTopLeft = 13                 // top-left of the exit 2×2

    // Ids are grouped by shape so this static class map holds:
    // 0 = big (B), 1…4 = vertical dominoes (V), 5 = horizontal domino (H), 6…9 = singles (S).
    static func pieceClass(_ id: Int) -> Character {
        switch id {
        case 0: return "B"
        case 1, 2, 3, 4: return "V"
        case 5: return "H"
        default: return "S"
        }
    }

    static func canonicalKey(_ occ: [Int]) -> String {
        String(occ.map { $0 == -1 ? "." : pieceClass($0) })
    }

    static func isGoal(_ occ: [Int]) -> Bool {
        goalCells.allSatisfy { occ[$0] == 0 }
    }

    /// Grouped moves — the classic Klotski convention where sliding a piece in a straight line by
    /// any number of cells counts as ONE move (this is the metric under which the classic solves in
    /// 81). Every intermediate landing along a slide is emitted as its own neighbour.
    static func neighborsGrouped(_ occ: [Int]) -> [[Int]] {
        var out: [[Int]] = []
        let ids = Set(occ.filter { $0 >= 0 })
        for pid in ids {
            let cells = (0..<rows * cols).filter { occ[$0] == pid }
            for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                var cur = cells
                var work = occ
                while true {
                    var shifted: [Int] = []
                    var ok = true
                    for cell in cur {
                        let r = cell / cols + dr, c = cell % cols + dc
                        if r < 0 || r >= rows || c < 0 || c >= cols { ok = false; break }
                        shifted.append(r * cols + c)
                    }
                    guard ok else { break }
                    let curSet = Set(cur)
                    var valid = true
                    for ni in shifted where work[ni] != -1 && !curSet.contains(ni) { valid = false; break }
                    guard valid else { break }
                    for cell in cur { work[cell] = -1 }
                    for ni in shifted { work[ni] = pid }
                    out.append(work)          // this landing = one grouped move
                    cur = shifted
                }
            }
        }
        return out
    }

    /// The classic Huarong Dao start (the famous 81-move escape) — big block top-centre.
    static let classicFallback: [Int] = [
        1, 0, 0, 2,
        1, 0, 0, 2,
        3, 5, 5, 4,
        3, 6, 7, 4,
        8, -1, -1, 9,
    ]

    /// Exact grouped-move distance from every reachable state to the nearest exit, bucketed by
    /// distance. Built once (thread-safe lazy `static let`) since it depends only on the fixed piece
    /// set and exit — so difficulty can be dialled in precisely and starts vary within a distance.
    struct DistanceMap {
        let byDistance: [Int: [[Int]]]
        let maxDist: Int
    }

    static let distanceMap: DistanceMap = buildDistanceMap()

    private static func buildDistanceMap() -> DistanceMap {
        // 1. Enumerate the whole reachable component from the classic layout.
        var indexOf: [String: Int] = [:]
        var states: [[Int]] = []
        indexOf[canonicalKey(classicFallback)] = 0
        states.append(classicFallback)
        var head = 0
        while head < states.count {
            let st = states[head]; head += 1
            for nx in neighborsGrouped(st) {
                let k = canonicalKey(nx)
                if indexOf[k] == nil { indexOf[k] = states.count; states.append(nx) }
            }
        }
        // 2. Multi-source BFS from every goal state (big block on the exit) → distance to solve.
        var dist = [Int](repeating: -1, count: states.count)
        var queue: [Int] = []
        for (i, st) in states.enumerated() where isGoal(st) { dist[i] = 0; queue.append(i) }
        var qh = 0
        while qh < queue.count {
            let i = queue[qh]; qh += 1
            for nx in neighborsGrouped(states[i]) {
                if let j = indexOf[canonicalKey(nx)], dist[j] == -1 {
                    dist[j] = dist[i] + 1; queue.append(j)
                }
            }
        }
        // 3. Bucket the states by their solve distance.
        var byDistance: [Int: [[Int]]] = [:]
        var maxDist = 0
        for (i, d) in dist.enumerated() where d > 0 {
            byDistance[d, default: []].append(states[i])
            maxDist = max(maxDist, d)
        }
        return DistanceMap(byDistance: byDistance, maxDist: maxDist)
    }

    /// A random start whose optimal solution is (as close as possible to) `fraction` of the deepest
    /// possible board — so the ramp scales to the real diameter whatever metric shakes out to, and
    /// the boss (fraction ~1) is the classic. Expressed as a fraction so it can't clamp-flatten.
    static func generateStart(fraction: Double, boss: Bool) -> [Int] {
        if boss { return classicFallback }
        let map = distanceMap
        let want = max(2, Int((Double(map.maxDist) * fraction).rounded()))
        for delta in 0...map.maxDist {
            for d in [want - delta, want + delta] where d >= 1 && d <= map.maxDist {
                if let bucket = map.byDistance[d], let pick = bucket.randomElement() { return pick }
            }
        }
        return classicFallback
    }
}

struct KlotskiView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    // Gentle climb up to the L7 "final boss" (the classic Huarong Dao). Values are minimum
    // single-cell slides in the optimal solution; L7 ignores this and uses the classic board.
    // Fraction of the puzzle's deepest board to target — tuned to land on roughly 10/20/…/60 moves
    // when the classic depth is ~81, giving a clean per-level climb. L7 ignores this (classic board).
    private var targetFraction: Double { [0.13, 0.25, 0.37, 0.49, 0.62, 0.74, 1.0][min(level, 7) - 1] }
    // Very generous clocks — Klotski is genuinely hard, so time should rarely be the enemy.
    private var timeLimit: Double { [120, 150, 180, 210, 270, 330, 420][min(level, 7) - 1] }

    private let cols = KlotskiGen.cols
    private let rows = KlotskiGen.rows
    private let skyTop = Color(red: 0.14, green: 0.11, blue: 0.09)
    private let skyBottom = Color(red: 0.06, green: 0.04, blue: 0.03)

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var occ: [Int] = []
    @State private var timeLeft = 0.0
    @State private var ready = false
    @State private var loopTask: Task<Void, Never>?

    // drag tracking
    @State private var dragPiece: Int?
    @State private var dragAxis = 0        // 0 none, 1 horizontal, 2 vertical
    @State private var dragApplied = 0
    @State private var demoPiece: Int? = nil   // block the demo's finger is dragging
    @State private var exiting = false         // presentation: the banana block sliding out on the win

    var body: some View {
        Group {
            if ready { gameBody } else { BrainstormingView(skyTop: skyTop, skyBottom: skyBottom) }
        }
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
    }

    private var gameBody: some View {
        VStack(spacing: 4) {
            if !isDemo {
                IncenseTimer(frac: timeLimit > 0 ? timeLeft / timeLimit : 0)
                    .frame(height: 34)
                    .padding(.horizontal, 30)
                    .padding(.top, 6)
            }

            GeometryReader { geo in
                let lay = KlotskiLayout(size: geo.size, demo: isDemo)
                ZStack {
                    KlotskiTray(cell: lay.cell, ox: lay.ox, oy: lay.oy, rim: lay.rim).equatable()
                    ForEach(pieceIds, id: \.self) { pid in
                        pieceView(pid, lay)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in handleDrag(v, cell: lay.cell, ox: lay.ox, oy: lay.oy) }
                        .onEnded { _ in dragPiece = nil; dragAxis = 0; dragApplied = 0 }
                )
            }
        }
        .padding(.vertical, isDemo ? 4 : 8)
        .background(TeaTable().equatable())
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pieceIds: [Int] { Set(occ.filter { $0 >= 0 }).sorted() }

    /// One wooden block: its art is drawn once (Equatable) and only its position animates as it slides.
    private func pieceView(_ pid: Int, _ lay: KlotskiLayout) -> some View {
        let b = box(pid)
        let inset = lay.cell * 0.035
        let w: CGFloat = CGFloat(b.w) * lay.cell - inset * 2
        let h: CGFloat = CGFloat(b.h) * lay.cell - inset * 2
        let pad: CGFloat = lay.cell * 0.14
        let px: CGFloat = lay.ox + (CGFloat(b.minC) + CGFloat(b.w) / 2) * lay.cell
        let py: CGFloat = lay.oy + (CGFloat(b.minR) + CGFloat(b.h) / 2) * lay.cell
        return KlotskiBlock(kind: KlotskiGen.pieceClass(pid), seed: pid, w: w, h: h, cell: lay.cell, pad: pad)
            .equatable()
            .frame(width: w + pad * 2, height: h + pad * 2)
            .overlay { if demoPiece == pid { demoGrab(cell: lay.cell, w: w, h: h) } }
            .position(x: px, y: py)
            // On the win the banana block keeps going, out through the notch in the tray.
            .offset(y: pid == 0 && exiting ? lay.cell * lay.exitSlide : 0)
            .animation(.easeOut(duration: 0.1), value: occ)
    }

    /// Demo-only: a white grab ring + finger riding the block being dragged.
    private func demoGrab(cell: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cell * 0.09).stroke(.white, lineWidth: 3)
                .frame(width: w, height: h)
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: cell * 0.5))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 3)
                .offset(x: cell * 0.12, y: cell * 0.16)
        }
        .allowsHitTesting(false)
    }

    private func box(_ pid: Int) -> (minR: Int, minC: Int, w: Int, h: Int) {
        var minR = rows, minC = cols, maxR = -1, maxC = -1
        for i in 0..<rows * cols where occ[i] == pid {
            let r = i / cols, c = i % cols
            minR = min(minR, r); maxR = max(maxR, r); minC = min(minC, c); maxC = max(maxC, c)
        }
        return (minR, minC, maxC - minC + 1, maxR - minR + 1)
    }

    // MARK: Input
    private func pieceAt(_ loc: CGPoint, cell: CGFloat, ox: CGFloat, oy: CGFloat) -> Int? {
        let c = Int((loc.x - ox) / cell), r = Int((loc.y - oy) / cell)
        guard r >= 0, r < rows, c >= 0, c < cols else { return nil }
        let v = occ[r * cols + c]
        return v >= 0 ? v : nil
    }

    private func handleDrag(_ v: DragGesture.Value, cell: CGFloat, ox: CGFloat, oy: CGFloat) {
        guard phase == .play, cell > 0 else { return }
        if dragPiece == nil {
            dragPiece = pieceAt(v.startLocation, cell: cell, ox: ox, oy: oy)
            dragAxis = 0; dragApplied = 0
        }
        guard let p = dragPiece else { return }
        let tx = v.translation.width, ty = v.translation.height
        if dragAxis == 0 {
            if max(abs(tx), abs(ty)) > cell * 0.25 { dragAxis = abs(tx) >= abs(ty) ? 1 : 2 } else { return }
        }
        let t = dragAxis == 1 ? tx : ty
        // Step once the finger passes the halfway point of a cell, so blocks follow the drag readily.
        let want = Int((t / cell).rounded())
        while dragApplied < want {
            let moved = dragAxis == 1 ? slide(p, 0, 1) : slide(p, 1, 0)
            if moved { dragApplied += 1 } else { break }
        }
        while dragApplied > want {
            let moved = dragAxis == 1 ? slide(p, 0, -1) : slide(p, -1, 0)
            if moved { dragApplied -= 1 } else { break }
        }
    }

    @discardableResult
    private func slide(_ pid: Int, _ dr: Int, _ dc: Int) -> Bool {
        guard phase == .play else { return false }
        let cells = (0..<rows * cols).filter { occ[$0] == pid }
        var shifted: [Int] = []
        for cell in cells {
            let r = cell / cols + dr, c = cell % cols + dc
            if r < 0 || r >= rows || c < 0 || c >= cols { return false }
            shifted.append(r * cols + c)
        }
        for ni in shifted where occ[ni] != -1 && occ[ni] != pid { return false }
        var nocc = occ
        for cell in cells { nocc[cell] = -1 }
        for ni in shifted { nocc[ni] = pid }
        withAnimation(.easeOut(duration: 0.1)) { occ = nocc }
        SoundManager.shared.tap(); Haptics.tap()
        if KlotskiGen.isGoal(occ) { withAnimation(.easeIn(duration: 0.5).delay(0.12)) { exiting = true } }   // presentation only
        if KlotskiGen.isGoal(occ) { win() }
        return true
    }

    // MARK: Demo (live manual clip)
    // A real Level-1 board: exactly 13 grouped moves from solved (Level 1 targets 13% of the
    // 101-move diameter), picked from a BFS of the full state space for the most banana-block
    // travel. The demo drags each block along its optimal slide through the real `slide()`.
    //   V V V V         ids: 0 = banana 2×2, 1–4 = vertical, 5 = horizontal, 6–9 = singles
    //   V V V V
    //   . B B S
    //   . B B S
    //   S S H H
    private static let demoBoard: [Int] = [
        1, 3, 2, 4,
        1, 3, 2, 4,
        -1, 0, 0, 8,
        -1, 0, 0, 9,
        6, 7, 5, 5,
    ]
    /// Optimal solution as (piece, dRow, dCol, cells).
    private static let demoMoves: [(Int, Int, Int, Int)] = [
        (0, 0, -1, 1), (8, 0, -1, 1), (9, -1, 0, 1), (5, -1, 0, 1), (7, 0, 1, 2), (6, 0, 1, 2),
        (0, 1, 0, 1), (8, 0, -1, 2), (9, 0, -1, 2), (5, -1, 0, 1), (6, -1, 0, 1), (6, 0, 1, 1),
        (0, 0, 1, 1),
    ]

    private func runDemo() async {
        while !Task.isCancelled {
            occ = Self.demoBoard
            demoPiece = nil
            exiting = false
            timeLeft = timeLimit
            phase = .play
            ready = true
            try? await Task.sleep(for: .seconds(0.6))
            for (pid, dr, dc, cells) in Self.demoMoves {
                guard !Task.isCancelled else { return }
                demoPiece = pid
                try? await Task.sleep(for: .seconds(0.18))
                for _ in 0..<cells {
                    guard !Task.isCancelled else { return }
                    slide(pid, dr, dc)
                    try? await Task.sleep(for: .seconds(0.16))
                }
                try? await Task.sleep(for: .seconds(0.08))
            }
            demoPiece = nil
            // The last slide parked the banana on the exit → the real win() ran (onWin is a no-op).
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    // MARK: Flow
    /// Hands this level's board build to `BoardCache` so it can run during the countdown.
    func prefetchBoard() {
        let fraction = targetFraction, boss = level >= 7
        BoardCache.prefetch(boardKey) { KlotskiGen.generateStart(fraction: fraction, boss: boss) }
    }
    private var boardKey: String { BoardCache.key("klotski", level: level) }

    private func run() async {
        let fraction = targetFraction, boss = level >= 7
        let t0 = Date()
        let board = await BoardCache.take(boardKey) { KlotskiGen.generateStart(fraction: fraction, boss: boss) }
        guard !Task.isCancelled else { return }
        // Level 1 is where the shared distance map is built for the first time (and where the feed
        // scroll can hitch), so if the brainstorming page did show, hold it a beat longer to mask it.
        await BoardCache.holdBrainstorm(since: t0, minimum: level == 1 ? 1.5 : 0.7)
        guard !Task.isCancelled else { return }

        occ = board
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

// MARK: - The wooden Huarong Dao set

/// Tray geometry: the board (4×5 cells), the rim around it, and room below the notch for the exit slide.
private struct KlotskiLayout {
    let cell: CGFloat, ox: CGFloat, oy: CGFloat, rim: CGFloat, exitSlide: CGFloat

    init(size: CGSize, demo: Bool) {
        let rimF: CGFloat = 0.3
        let room: CGFloat = demo ? 0.3 : 0.95          // cells of table below the tray
        let byW: CGFloat = size.width / (4 + rimF * 2 + 0.3)
        let byH: CGFloat = size.height / (5 + rimF * 2 + room + 0.15)
        cell = max(10, floor(min(byW, byH)))
        rim = cell * rimF
        ox = (size.width - cell * 4) / 2
        let total: CGFloat = cell * (5 + rimF * 2 + room)
        oy = (size.height - total) / 2 + rim
        exitSlide = demo ? 0.6 : 1.2
    }
}

private enum KlotskiArt {
    static let burnt = Color(red: 0.42, green: 0.23, blue: 0.10)          // laser-etched line
    static let tassel = Color(red: 0.78, green: 0.14, blue: 0.12)
    static let gold = Color(red: 0.93, green: 0.76, blue: 0.36)
    static let goldDark = Color(red: 0.6, green: 0.43, blue: 0.14)

    /// A repeatable 0…1 pseudo-random value.
    static func hash(_ n: Double) -> CGFloat {
        let v: Double = sin(n * 12.9898) * 43758.5453
        return CGFloat(v - floor(v))
    }

    /// Wavy grain lines running along the long axis, clipped by the caller.
    static func grain(_ ctx: GraphicsContext, in r: CGRect, vertical: Bool, seed: Int, spacing: CGFloat,
                      color: Color, width: CGFloat) {
        let across: CGFloat = vertical ? r.width : r.height
        let along: CGFloat = vertical ? r.height : r.width
        let count = max(3, Int(across / spacing))
        for k in 0..<count {
            let s: Double = Double(seed) * 7.31 + Double(k) * 1.73
            let base: CGFloat = (CGFloat(k) + 0.2 + hash(s) * 0.6) / CGFloat(count) * across
            let amp: CGFloat = spacing * (0.15 + hash(s + 3.1) * 0.35)
            let freq: CGFloat = (1.2 + hash(s + 5.7) * 2.2) / along * .pi
            let phase: CGFloat = hash(s + 9.3) * 6.28
            var p = Path()
            let steps = 14
            for j in 0...steps {
                let t: CGFloat = CGFloat(j) / CGFloat(steps) * along
                let off: CGFloat = base + amp * sin(t * freq + phase)
                let pt = vertical ? CGPoint(x: r.minX + off, y: r.minY + t) : CGPoint(x: r.minX + t, y: r.minY + off)
                if j == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            let op: Double = 0.35 + Double(hash(s + 11.9)) * 0.5
            ctx.stroke(p, with: .color(color.opacity(op)), lineWidth: width * (0.6 + hash(s + 2.2) * 0.9))
        }
    }

    /// Light-top-left / dark-bottom-right edge on a rounded block.
    static func bevel(_ ctx: GraphicsContext, _ r: CGRect, rad: CGFloat, lw: CGFloat, light: Color, dark: Color) {
        var lit = Path()
        lit.move(to: CGPoint(x: r.minX + lw / 2, y: r.maxY - rad))
        lit.addLine(to: CGPoint(x: r.minX + lw / 2, y: r.minY + rad))
        lit.addQuadCurve(to: CGPoint(x: r.minX + rad, y: r.minY + lw / 2), control: CGPoint(x: r.minX + lw / 2, y: r.minY + lw / 2))
        lit.addLine(to: CGPoint(x: r.maxX - rad, y: r.minY + lw / 2))
        ctx.stroke(lit, with: .color(light), style: StrokeStyle(lineWidth: lw, lineCap: .round))
        var shade = Path()
        shade.move(to: CGPoint(x: r.maxX - lw / 2, y: r.minY + rad))
        shade.addLine(to: CGPoint(x: r.maxX - lw / 2, y: r.maxY - rad))
        shade.addQuadCurve(to: CGPoint(x: r.maxX - rad, y: r.maxY - lw / 2), control: CGPoint(x: r.maxX - lw / 2, y: r.maxY - lw / 2))
        shade.addLine(to: CGPoint(x: r.minX + rad, y: r.maxY - lw / 2))
        ctx.stroke(shade, with: .color(dark), style: StrokeStyle(lineWidth: lw, lineCap: .round))
    }

    /// A natural beech block with grain and a bevelled edge.
    static func beech(_ ctx: GraphicsContext, _ r: CGRect, rad: CGFloat, cell: CGFloat, seed: Int) {
        let body = Path(roundedRect: r, cornerRadius: rad)
        let tint: CGFloat = hash(Double(seed) * 3.3) * 0.05
        let light = Color(red: 0.95 - tint, green: 0.84 - tint, blue: 0.66 - tint)
        let deep = Color(red: 0.84 - tint, green: 0.66 - tint, blue: 0.45 - tint)
        ctx.fill(body, with: .linearGradient(Gradient(colors: [light, deep]),
                                             startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.maxX, y: r.maxY)))
        var g = ctx
        g.clip(to: body)
        grain(g, in: r, vertical: r.height >= r.width, seed: seed, spacing: cell * 0.075,
              color: Color(red: 0.66, green: 0.44, blue: 0.24), width: max(0.6, cell * 0.012))
        bevel(ctx, r.insetBy(dx: 0.5, dy: 0.5), rad: rad, lw: max(1.5, cell * 0.035),
              light: .white.opacity(0.55), dark: Color(red: 0.5, green: 0.31, blue: 0.14).opacity(0.55))
        ctx.stroke(body, with: .color(Color(red: 0.36, green: 0.22, blue: 0.1).opacity(0.7)), lineWidth: 1)
    }

    /// The etched border every Huarong Dao block carries.
    static func etchedFrame(_ ctx: GraphicsContext, _ r: CGRect, cell: CGFloat) -> CGRect {
        let f = r.insetBy(dx: cell * 0.11, dy: cell * 0.11)
        ctx.stroke(Path(roundedRect: f, cornerRadius: cell * 0.04), with: .color(burnt.opacity(0.75)), lineWidth: max(1, cell * 0.018))
        return f
    }

    /// Tall block: a general's spear with a red tassel.
    static func spear(_ ctx: GraphicsContext, _ f: CGRect, cell: CGFloat) {
        let lw: CGFloat = max(1.2, cell * 0.024)
        let cx: CGFloat = f.midX
        let tipY: CGFloat = f.minY + f.height * 0.07
        let baseY: CGFloat = f.minY + f.height * 0.27
        let midY: CGFloat = (tipY + baseY) / 2
        let hw: CGFloat = f.width * 0.13
        var blade = Path()
        blade.move(to: CGPoint(x: cx, y: tipY))
        blade.addQuadCurve(to: CGPoint(x: cx, y: baseY), control: CGPoint(x: cx + hw * 2, y: midY))
        blade.addQuadCurve(to: CGPoint(x: cx, y: tipY), control: CGPoint(x: cx - hw * 2, y: midY))
        blade.closeSubpath()
        ctx.fill(blade, with: .color(burnt.opacity(0.16)))
        ctx.stroke(blade, with: .color(burnt), lineWidth: lw)
        var rib = Path()
        rib.move(to: CGPoint(x: cx, y: tipY + f.height * 0.025)); rib.addLine(to: CGPoint(x: cx, y: baseY))
        ctx.stroke(rib, with: .color(burnt.opacity(0.7)), lineWidth: lw * 0.6)
        // Guard, then the tassel hanging from it.
        let guardY: CGFloat = baseY + f.height * 0.015
        var guardBar = Path()
        guardBar.move(to: CGPoint(x: cx - f.width * 0.16, y: guardY)); guardBar.addLine(to: CGPoint(x: cx + f.width * 0.16, y: guardY))
        ctx.stroke(guardBar, with: .color(burnt), style: StrokeStyle(lineWidth: lw * 1.3, lineCap: .round))
        var tuft = Path()
        for k in -3...3 {
            let dx: CGFloat = CGFloat(k) * f.width * 0.045
            tuft.move(to: CGPoint(x: cx + dx * 0.4, y: guardY + lw))
            tuft.addQuadCurve(to: CGPoint(x: cx + dx * 1.3, y: guardY + f.height * 0.13),
                              control: CGPoint(x: cx + dx * 0.9, y: guardY + f.height * 0.05))
        }
        ctx.stroke(tuft, with: .color(tassel), style: StrokeStyle(lineWidth: lw * 0.9, lineCap: .round))
        // Shaft down to a small butt spike.
        let by: CGFloat = f.maxY - f.height * 0.075
        var shaft = Path()
        shaft.move(to: CGPoint(x: cx, y: guardY + lw)); shaft.addLine(to: CGPoint(x: cx, y: by))
        ctx.stroke(shaft, with: .color(burnt), style: StrokeStyle(lineWidth: lw * 1.2, lineCap: .round))
        // A round pommel at the butt (no point, so it never reads as a direction arrow).
        let pr: CGFloat = f.width * 0.065
        let pommel = Path(ellipseIn: CGRect(x: cx - pr, y: by - pr * 0.4, width: pr * 2, height: pr * 2))
        ctx.fill(pommel, with: .color(burnt.opacity(0.2)))
        ctx.stroke(pommel, with: .color(burnt), lineWidth: lw * 0.9)
    }

    /// Wide block: Guan Yu's crescent-blade glaive lying flat.
    static func glaive(_ ctx: GraphicsContext, _ f: CGRect, cell: CGFloat) {
        let lw: CGFloat = max(1.2, cell * 0.024)
        let cy: CGFloat = f.midY + f.height * 0.06
        let x0: CGFloat = f.minX + f.width * 0.66
        var shaft = Path()
        shaft.move(to: CGPoint(x: f.minX + f.width * 0.07, y: cy)); shaft.addLine(to: CGPoint(x: x0, y: cy))
        ctx.stroke(shaft, with: .color(burnt), style: StrokeStyle(lineWidth: lw * 1.2, lineCap: .round))
        // Back of the blade runs along the shaft line with a small spur; the cutting edge sweeps
        // down and round, rising to the point at the far end.
        let tip = CGPoint(x: f.maxX - f.width * 0.03, y: f.minY + f.height * 0.1)
        var blade = Path()
        blade.move(to: CGPoint(x: x0, y: cy - f.height * 0.1))
        blade.addLine(to: CGPoint(x: x0 + f.width * 0.09, y: cy - f.height * 0.12))
        blade.addLine(to: CGPoint(x: x0 + f.width * 0.11, y: cy - f.height * 0.3))      // spur
        blade.addLine(to: CGPoint(x: x0 + f.width * 0.14, y: cy - f.height * 0.14))
        blade.addQuadCurve(to: tip, control: CGPoint(x: f.maxX - f.width * 0.1, y: cy - f.height * 0.16))
        blade.addQuadCurve(to: CGPoint(x: x0 + f.width * 0.02, y: cy + f.height * 0.2),
                           control: CGPoint(x: f.maxX - f.width * 0.02, y: cy + f.height * 0.34))
        blade.closeSubpath()
        ctx.fill(blade, with: .color(burnt.opacity(0.16)))
        ctx.stroke(blade, with: .color(burnt), style: StrokeStyle(lineWidth: lw, lineJoin: .round))
        // A dragon-eye ring where the blade meets the shaft.
        let er: CGFloat = f.height * 0.07
        ctx.stroke(Path(ellipseIn: CGRect(x: x0 + f.width * 0.05 - er, y: cy + f.height * 0.02 - er, width: er * 2, height: er * 2)),
                   with: .color(burnt), lineWidth: lw * 0.8)
        var tuft = Path()
        for k in 0...5 {
            let dx: CGFloat = CGFloat(k - 2) * f.width * 0.018
            tuft.move(to: CGPoint(x: x0 - f.width * 0.02, y: cy + lw))
            tuft.addQuadCurve(to: CGPoint(x: x0 - f.width * 0.05 + dx * 1.6, y: cy + f.height * 0.36),
                              control: CGPoint(x: x0 - f.width * 0.01 + dx, y: cy + f.height * 0.16))
        }
        ctx.stroke(tuft, with: .color(tassel), style: StrokeStyle(lineWidth: lw * 0.9, lineCap: .round))
        var ferrule = Path()
        ferrule.move(to: CGPoint(x: f.minX + f.width * 0.07, y: cy - f.height * 0.07))
        ferrule.addLine(to: CGPoint(x: f.minX + f.width * 0.07, y: cy + f.height * 0.07))
        ctx.stroke(ferrule, with: .color(burnt), style: StrokeStyle(lineWidth: lw * 1.4, lineCap: .round))
    }

    /// Single block: a soldier's round shield.
    static func shield(_ ctx: GraphicsContext, _ f: CGRect, cell: CGFloat) {
        let lw: CGFloat = max(1.2, cell * 0.024)
        let c = CGPoint(x: f.midX, y: f.midY)
        let R: CGFloat = min(f.width, f.height) * 0.36
        let outer = Path(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2))
        ctx.fill(outer, with: .color(burnt.opacity(0.12)))
        ctx.stroke(outer, with: .color(burnt), lineWidth: lw)
        let r2: CGFloat = R * 0.6
        let inner = Path(ellipseIn: CGRect(x: c.x - r2, y: c.y - r2, width: r2 * 2, height: r2 * 2))
        ctx.fill(inner, with: .color(tassel.opacity(0.55)))
        ctx.stroke(inner, with: .color(burnt), lineWidth: lw * 0.8)
        let r3: CGFloat = R * 0.2
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r3, y: c.y - r3, width: r3 * 2, height: r3 * 2)), with: .color(burnt))
        for k in 0..<4 {
            let a: CGFloat = .pi / 4 + CGFloat(k) * .pi / 2
            let p = CGPoint(x: c.x + cos(a) * R * 0.8, y: c.y + sin(a) * R * 0.8)
            let rr: CGFloat = max(1, R * 0.07)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2)), with: .color(burnt))
        }
    }

    /// The 2×2 hero block: vermilion lacquer, gold frame and corner frets, a banana in the middle.
    static func lacquer(_ ctx: GraphicsContext, _ r: CGRect, rad: CGFloat, cell: CGFloat) {
        let body = Path(roundedRect: r, cornerRadius: rad)
        ctx.fill(body, with: .linearGradient(Gradient(colors: [Color(red: 0.84, green: 0.25, blue: 0.18),
                                                               Color(red: 0.56, green: 0.1, blue: 0.08)]),
                                             startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.maxX, y: r.maxY)))
        var sheen = ctx
        sheen.clip(to: body)
        sheen.fill(Path(ellipseIn: CGRect(x: r.minX - r.width * 0.3, y: r.minY - r.height * 0.45, width: r.width * 1.1, height: r.height * 0.9)),
                   with: .radialGradient(Gradient(colors: [.white.opacity(0.22), .white.opacity(0)]),
                                         center: CGPoint(x: r.minX + r.width * 0.25, y: r.minY + r.height * 0.05),
                                         startRadius: 0, endRadius: r.width * 0.6))
        let lw: CGFloat = max(1.2, cell * 0.022)
        let f1 = r.insetBy(dx: cell * 0.1, dy: cell * 0.1)
        let f2 = r.insetBy(dx: cell * 0.16, dy: cell * 0.16)
        ctx.stroke(Path(roundedRect: f1, cornerRadius: cell * 0.05), with: .color(gold), lineWidth: lw * 1.3)
        ctx.stroke(Path(roundedRect: f2, cornerRadius: cell * 0.03), with: .color(gold.opacity(0.8)), lineWidth: lw * 0.7)
        // Key-fret brackets in each corner.
        let k: CGFloat = cell * 0.22
        for (sx, sy) in [(CGFloat(1), CGFloat(1)), (-1, 1), (1, -1), (-1, -1)] {
            let o = CGPoint(x: sx > 0 ? f2.minX + cell * 0.06 : f2.maxX - cell * 0.06, y: sy > 0 ? f2.minY + cell * 0.06 : f2.maxY - cell * 0.06)
            var fret = Path()
            fret.move(to: CGPoint(x: o.x, y: o.y + sy * k))
            fret.addLine(to: o)
            fret.addLine(to: CGPoint(x: o.x + sx * k, y: o.y))
            fret.move(to: CGPoint(x: o.x + sx * k * 0.45, y: o.y + sy * k * 0.45))
            fret.addLine(to: CGPoint(x: o.x + sx * k * 0.45, y: o.y + sy * k * 0.2))
            ctx.stroke(fret, with: .color(gold), style: StrokeStyle(lineWidth: lw, lineCap: .square))
        }
        // The banana, with a soft shadow so it sits on the lacquer.
        let br: CGFloat = min(r.width, r.height) * 0.3
        var shadow = ctx
        shadow.addFilter(.shadow(color: .black.opacity(0.45), radius: cell * 0.05, x: 0, y: cell * 0.03))
        FruitArt.draw(.banana, in: shadow, at: CGPoint(x: r.midX + br * 0.04, y: r.midY + br * 0.18), radius: br, angle: .degrees(-12))
        bevel(ctx, r.insetBy(dx: 0.5, dy: 0.5), rad: rad, lw: max(1.5, cell * 0.035),
              light: Color(red: 1, green: 0.62, blue: 0.52).opacity(0.7), dark: Color(red: 0.3, green: 0.03, blue: 0.02).opacity(0.7))
        ctx.stroke(body, with: .color(Color(red: 0.25, green: 0.03, blue: 0.02).opacity(0.8)), lineWidth: 1)
    }
}

/// One block, drawn once; `pad` leaves room around it for its contact shadow.
private struct KlotskiBlock: View, Equatable {
    let kind: Character
    let seed: Int
    let w: CGFloat
    let h: CGFloat
    let cell: CGFloat
    let pad: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            let r = CGRect(x: pad, y: pad, width: w, height: h)
            let rad: CGFloat = cell * 0.09
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: cell * 0.045))
                l.fill(Path(roundedRect: r.offsetBy(dx: cell * 0.025, dy: cell * 0.05), cornerRadius: rad),
                       with: .color(.black.opacity(0.5)))
            }
            if kind == "B" {
                KlotskiArt.lacquer(ctx, r, rad: rad, cell: cell)
            } else {
                KlotskiArt.beech(ctx, r, rad: rad, cell: cell, seed: seed)
                let f = KlotskiArt.etchedFrame(ctx, r, cell: cell)
                switch kind {
                case "V": KlotskiArt.spear(ctx, f, cell: cell)
                case "H": KlotskiArt.glaive(ctx, f, cell: cell)
                default:  KlotskiArt.shield(ctx, f, cell: cell)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The tray: a raised beech rim with a notch cut in the bottom under the exit, and a walnut floor.
private struct KlotskiTray: View, Equatable {
    let cell: CGFloat
    let ox: CGFloat
    let oy: CGFloat
    let rim: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            let board = CGRect(x: ox, y: oy, width: cell * 4, height: cell * 5)
            let outer = board.insetBy(dx: -rim, dy: -rim)
            let notch = CGRect(x: board.minX + cell, y: board.maxY - 1, width: cell * 2, height: rim + 2)
            // The tray's shadow on the table.
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: rim * 0.45))
                l.fill(Path(roundedRect: outer.offsetBy(dx: rim * 0.1, dy: rim * 0.3), cornerRadius: rim * 0.9),
                       with: .color(.black.opacity(0.6)))
            }
            // Walnut floor with its own faint grain; it runs on out through the notch (the exit lane).
            let lane = CGRect(x: notch.minX, y: board.maxY - 1, width: notch.width, height: rim + 1)
            var floorShape = Path(board)
            floorShape.addRect(lane)
            ctx.fill(floorShape, with: .linearGradient(Gradient(colors: [Color(red: 0.47, green: 0.3, blue: 0.18),
                                                                        Color(red: 0.36, green: 0.22, blue: 0.12)]),
                                                         startPoint: CGPoint(x: board.minX, y: board.minY),
                                                         endPoint: CGPoint(x: board.maxX, y: board.maxY)))
            var floor = ctx
            floor.clip(to: floorShape)
            KlotskiArt.grain(floor, in: board.union(lane), vertical: true, seed: 42, spacing: cell * 0.11,
                             color: Color(red: 0.25, green: 0.14, blue: 0.07), width: max(0.6, cell * 0.014))
            // The exit: a carved outline of the 2×2 slot above the notch.
            let slot = CGRect(x: board.minX + cell, y: board.minY + cell * 3, width: cell * 2, height: cell * 2)
                .insetBy(dx: cell * 0.09, dy: cell * 0.09)
            let slotPath = Path(roundedRect: slot, cornerRadius: cell * 0.08)
            floor.stroke(slotPath.offsetBy(dx: 0, dy: 1.2), with: .color(.white.opacity(0.12)), lineWidth: max(1.5, cell * 0.03))
            floor.stroke(slotPath, with: .color(.black.opacity(0.35)), lineWidth: max(1.5, cell * 0.03))
            // The rim casts a soft shadow onto the floor along its top and left edges.
            let s: CGFloat = cell * 0.16
            floor.fill(Path(CGRect(x: board.minX, y: board.minY, width: board.width, height: s)),
                       with: .linearGradient(Gradient(colors: [.black.opacity(0.45), .clear]),
                                             startPoint: CGPoint(x: 0, y: board.minY), endPoint: CGPoint(x: 0, y: board.minY + s)))
            floor.fill(Path(CGRect(x: board.minX, y: board.minY, width: s, height: board.height)),
                       with: .linearGradient(Gradient(colors: [.black.opacity(0.4), .clear]),
                                             startPoint: CGPoint(x: board.minX, y: 0), endPoint: CGPoint(x: board.minX + s, y: 0)))
            // The rim: outer rounded frame minus the board-plus-notch opening.
            var hole = Path()
            hole.move(to: CGPoint(x: board.minX, y: board.minY))
            hole.addLine(to: CGPoint(x: board.maxX, y: board.minY))
            hole.addLine(to: CGPoint(x: board.maxX, y: board.maxY))
            hole.addLine(to: CGPoint(x: notch.maxX, y: board.maxY))
            hole.addLine(to: CGPoint(x: notch.maxX, y: outer.maxY + 2))
            hole.addLine(to: CGPoint(x: notch.minX, y: outer.maxY + 2))
            hole.addLine(to: CGPoint(x: notch.minX, y: board.maxY))
            hole.addLine(to: CGPoint(x: board.minX, y: board.maxY))
            hole.closeSubpath()
            var rimPath = Path(roundedRect: outer, cornerRadius: rim * 0.8)
            rimPath.addPath(hole)
            let rimFill = FillStyle(eoFill: true)
            ctx.fill(rimPath, with: .linearGradient(Gradient(colors: [Color(red: 0.9, green: 0.68, blue: 0.42),
                                                                    Color(red: 0.7, green: 0.47, blue: 0.25)]),
                                                     startPoint: CGPoint(x: outer.minX, y: outer.minY),
                                                     endPoint: CGPoint(x: outer.maxX, y: outer.maxY)), style: rimFill)
            // Grain runs along each rail: across the top and bottom, down the sides (mitred corners).
            let railGrain = Color(red: 0.55, green: 0.33, blue: 0.15)
            var tb = ctx
            var tbClip = Path()
            tbClip.move(to: CGPoint(x: outer.minX, y: outer.minY)); tbClip.addLine(to: CGPoint(x: outer.maxX, y: outer.minY))
            tbClip.addLine(to: CGPoint(x: board.maxX, y: board.minY)); tbClip.addLine(to: CGPoint(x: board.minX, y: board.minY)); tbClip.closeSubpath()
            tbClip.move(to: CGPoint(x: outer.minX, y: outer.maxY)); tbClip.addLine(to: CGPoint(x: outer.maxX, y: outer.maxY))
            tbClip.addLine(to: CGPoint(x: board.maxX, y: board.maxY)); tbClip.addLine(to: CGPoint(x: board.minX, y: board.maxY)); tbClip.closeSubpath()
            tb.clip(to: tbClip)
            tb.clip(to: rimPath, style: rimFill)
            KlotskiArt.grain(tb, in: outer, vertical: false, seed: 7, spacing: rim * 0.22, color: railGrain, width: max(0.6, cell * 0.012))
            var lr = ctx
            var lrClip = Path()
            lrClip.move(to: CGPoint(x: outer.minX, y: outer.minY)); lrClip.addLine(to: CGPoint(x: board.minX, y: board.minY))
            lrClip.addLine(to: CGPoint(x: board.minX, y: board.maxY)); lrClip.addLine(to: CGPoint(x: outer.minX, y: outer.maxY)); lrClip.closeSubpath()
            lrClip.move(to: CGPoint(x: outer.maxX, y: outer.minY)); lrClip.addLine(to: CGPoint(x: board.maxX, y: board.minY))
            lrClip.addLine(to: CGPoint(x: board.maxX, y: board.maxY)); lrClip.addLine(to: CGPoint(x: outer.maxX, y: outer.maxY)); lrClip.closeSubpath()
            lr.clip(to: lrClip)
            lr.clip(to: rimPath, style: rimFill)
            KlotskiArt.grain(lr, in: outer, vertical: true, seed: 13, spacing: rim * 0.22, color: railGrain, width: max(0.6, cell * 0.012))
            // Mitre joints.
            var mitres = Path()
            for (o, b) in [(CGPoint(x: outer.minX, y: outer.minY), CGPoint(x: board.minX, y: board.minY)),
                           (CGPoint(x: outer.maxX, y: outer.minY), CGPoint(x: board.maxX, y: board.minY)),
                           (CGPoint(x: outer.minX, y: outer.maxY), CGPoint(x: board.minX, y: board.maxY)),
                           (CGPoint(x: outer.maxX, y: outer.maxY), CGPoint(x: board.maxX, y: board.maxY))] {
                let k: CGFloat = rim * 0.25
                let dx: CGFloat = b.x > o.x ? k : -k, dy: CGFloat = b.y > o.y ? k : -k
                mitres.move(to: CGPoint(x: o.x + dx, y: o.y + dy)); mitres.addLine(to: b)
            }
            ctx.stroke(mitres, with: .color(Color(red: 0.45, green: 0.26, blue: 0.1).opacity(0.6)), lineWidth: 1)
            // Edges: light along the outer top-left, dark on the inner lip and the notch's end grain.
            ctx.stroke(Path(roundedRect: outer.insetBy(dx: 1, dy: 1), cornerRadius: rim * 0.75),
                       with: .color(.white.opacity(0.35)), lineWidth: 1.5)
            ctx.stroke(hole, with: .color(Color(red: 0.3, green: 0.16, blue: 0.06).opacity(0.85)), lineWidth: 1.5)
            // The floor board's cut end at the mouth of the lane.
            ctx.fill(Path(CGRect(x: lane.minX, y: lane.maxY - 1.5, width: lane.width, height: 1.5)),
                     with: .color(Color(red: 0.2, green: 0.11, blue: 0.05)))
            for x in [notch.minX, notch.maxX] {
                let w: CGFloat = rim * 0.14
                let face = CGRect(x: x == notch.minX ? x - w : x, y: board.maxY, width: w, height: rim)
                ctx.fill(Path(face), with: .color(Color(red: 0.55, green: 0.33, blue: 0.16).opacity(0.8)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Dark walnut tabletop under the puzzle (static).
private struct TeaTable: View, Equatable {
    var body: some View {
        Canvas { ctx, s in
            let r = CGRect(origin: .zero, size: s)
            ctx.fill(Path(r), with: .linearGradient(Gradient(colors: [Color(red: 0.24, green: 0.15, blue: 0.09),
                                                                    Color(red: 0.13, green: 0.08, blue: 0.05)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height)))
            let plank: CGFloat = 64
            var y: CGFloat = 0
            var k = 0
            while y < s.height {
                let band = CGRect(x: 0, y: y, width: s.width, height: plank)
                var g = ctx
                g.clip(to: Path(band))
                KlotskiArt.grain(g, in: band, vertical: false, seed: 100 + k, spacing: 7,
                                 color: Color(red: 0.07, green: 0.04, blue: 0.02), width: 0.8)
                ctx.fill(Path(CGRect(x: 0, y: y + plank - 1.5, width: s.width, height: 1.5)), with: .color(.black.opacity(0.45)))
                y += plank; k += 1
            }
        }
        .allowsHitTesting(false)
    }
}

/// The level clock: an incense stick burning down toward its holder, a thread of smoke at the ember.
private struct IncenseTimer: View {
    let frac: Double

    var body: some View {
        Canvas { ctx, s in
            let h: CGFloat = s.height
            let y: CGFloat = h * 0.74
            let x0: CGFloat = h * 0.7
            let maxLen: CGFloat = s.width - x0 - h * 0.2
            let f: CGFloat = CGFloat(max(0, min(1, frac)))
            let tip: CGFloat = x0 + maxLen * f
            let low = frac < 0.3
            // A faint line of fallen ash where the stick has already burnt.
            var ash = Path()
            ash.move(to: CGPoint(x: tip + 3, y: y + h * 0.1)); ash.addLine(to: CGPoint(x: x0 + maxLen, y: y + h * 0.1))
            ctx.stroke(ash, with: .color(Color(white: 0.6).opacity(0.3)), style: StrokeStyle(lineWidth: 1.5, dash: [2, 5]))
            // The stick.
            var stick = Path()
            stick.move(to: CGPoint(x: x0 - h * 0.25, y: y)); stick.addLine(to: CGPoint(x: tip, y: y))
            ctx.stroke(stick, with: .color(Color(red: 0.55, green: 0.24, blue: 0.14)), style: StrokeStyle(lineWidth: h * 0.16, lineCap: .butt))
            ctx.stroke(stick, with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: h * 0.03, lineCap: .butt))
            // Ember and glow.
            let glowR: CGFloat = h * (low ? 0.5 : 0.36)
            let emberCol = low ? Color(red: 1, green: 0.25, blue: 0.08) : Color(red: 1, green: 0.55, blue: 0.16)
            ctx.fill(Path(ellipseIn: CGRect(x: tip - glowR, y: y - glowR, width: glowR * 2, height: glowR * 2)),
                     with: .radialGradient(Gradient(colors: [emberCol.opacity(0.75), emberCol.opacity(0)]),
                                           center: CGPoint(x: tip, y: y), startRadius: 0, endRadius: glowR))
            ctx.fill(Path(ellipseIn: CGRect(x: tip - h * 0.08, y: y - h * 0.08, width: h * 0.16, height: h * 0.16)),
                     with: .color(Color(red: 1, green: 0.85, blue: 0.5)))
            // Smoke curling up from the ember.
            var smoke = Path()
            smoke.move(to: CGPoint(x: tip, y: y - h * 0.1))
            smoke.addCurve(to: CGPoint(x: tip + h * 0.1, y: h * 0.02),
                           control1: CGPoint(x: tip - h * 0.3, y: y - h * 0.35), control2: CGPoint(x: tip + h * 0.35, y: h * 0.3))
            ctx.stroke(smoke, with: .linearGradient(Gradient(colors: [.white.opacity(0.45), .white.opacity(0)]),
                                                    startPoint: CGPoint(x: tip, y: y), endPoint: CGPoint(x: tip, y: 0)),
                       style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            // A little bronze holder at the left end.
            let base = CGRect(x: 0, y: y - h * 0.08, width: x0 * 0.95, height: h * 0.3)
            ctx.fill(Path(roundedRect: base, cornerRadius: h * 0.12),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.86, green: 0.64, blue: 0.3), Color(red: 0.5, green: 0.32, blue: 0.1)]),
                                           startPoint: CGPoint(x: 0, y: base.minY), endPoint: CGPoint(x: 0, y: base.maxY)))
            ctx.fill(Path(ellipseIn: CGRect(x: x0 * 0.5, y: y - h * 0.16, width: h * 0.26, height: h * 0.26)),
                     with: .color(Color(red: 0.62, green: 0.4, blue: 0.14)))
        }
        .allowsHitTesting(false)
    }
}
