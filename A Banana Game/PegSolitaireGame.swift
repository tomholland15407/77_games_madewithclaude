//
//  PegSolitaireGame.swift
//  A Banana Game
//
//  Brain — Peg Solitaire. Jump one peg straight over an adjacent peg into the empty hole beyond;
//  the jumped peg is removed. Keep jumping until a single peg remains to win. Tap a peg to select it,
//  then tap a highlighted hole to leap. Strand yourself with no jumps left (more than one peg), or
//  run out of time, and you're back to level 1.
//
//  Boards are built backwards from a lone survivor by "un-jumping" — the exact inverse of a jump on
//  the live board — so every layout is guaranteed reducible to one peg and is never pre-solved.
//  Levels grow the board and the peg count, so the number of forced-perfect jumps climbs steeply.
//

import SwiftUI

private nonisolated struct PCell: Hashable, Sendable { let r: Int; let c: Int }

private nonisolated struct PegPuzzle: Sendable {
    let w: Int; let h: Int; let pegs: Set<PCell>
}

enum PegSolitaireGame {
    static let definition = GameDefinition(
        id: "peg-solitaire",
        title: "Peg Solitaire",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Tap a peg, then tap a highlighted hole two spaces away in a straight line.",
                "The peg leaps the one between them and removes it.",
                "Clear the board down to a single peg to win — before time runs out.",
            ],
            bulletsVI: [
                "Chạm vào một quân cờ, rồi chạm vào ô trống được tô sáng cách hai ô theo đường thẳng.",
                "Quân cờ nhảy qua quân ở giữa và loại nó khỏi bàn.",
                "Giảm bàn cờ xuống chỉ còn một quân để thắng — trước khi hết giờ.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(PegSolitaireView(level: level, onWin: onWin, onFail: onFail))
        },
        prefetch: { level in PegSolitaireView(level: level, onWin: {}, onFail: {}).prefetchBoard() }
    )
}

struct PegSolitaireView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    private var params: (w: Int, h: Int, pegs: Int) {
        [ (4, 4, 5), (5, 4, 7), (5, 5, 9), (5, 5, 12), (6, 5, 14), (6, 6, 17), (6, 6, 20) ][min(level, 7) - 1]
    }
    private var timeLimit: Double { [40, 50, 60, 70, 80, 90, 100][min(level, 7) - 1] }

    // Marble solitaire on a games table: green felt, a teak board with a carved groove round the
    // edge (captured marbles collect there), drilled holes and glossy glass marbles.
    private static let feltTop = Color(red: 0.12, green: 0.36, blue: 0.27)
    private static let feltBottom = Color(red: 0.04, green: 0.16, blue: 0.12)

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var ready = false
    @State private var w = 0
    @State private var h = 0
    @State private var pegs: Set<PCell> = []
    @State private var selected: PCell? = nil
    @State private var timeLeft = 0.0
    @State private var loopTask: Task<Void, Never>?
    // Presentation only: each marble's glass colour travels with it, captured marbles fill the groove.
    @State private var tint: [PCell: Int] = [:]
    @State private var captured: [Int] = []
    @State private var hop: PegHop? = nil
    @State private var demoCell: PCell? = nil

    var body: some View {
        Group {
            if ready { gameBody } else { BrainstormingView(skyTop: Self.feltTop, skyBottom: Self.feltBottom) }
        }
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
    }

    // MARK: - Demo (live manual clip)

    /// A compact 3×3 board (a 2×2 peg block) solved in three jumps down to one peg.
    /// Drives the real `tapHole` select→jump flow with a finger on each tapped hole.
    private func runDemo() async {
        let jumps: [(PCell, PCell)] = [
            (PCell(r: 0, c: 1), PCell(r: 2, c: 1)),   // jump down the left column
            (PCell(r: 0, c: 2), PCell(r: 2, c: 2)),   // jump down the right column
            (PCell(r: 2, c: 2), PCell(r: 2, c: 0)),   // final leap left → one peg remains
        ]
        while !Task.isCancelled {
            demoSetup()
            try? await Task.sleep(for: .seconds(0.7))
            for (from, to) in jumps {
                guard !Task.isCancelled else { return }
                demoCell = from
                try? await Task.sleep(for: .seconds(0.28))
                tapHole(from)                                 // select the peg
                try? await Task.sleep(for: .seconds(0.45))
                guard !Task.isCancelled else { return }
                demoCell = to
                try? await Task.sleep(for: .seconds(0.3))
                tapHole(to)                                   // leap into the hole
                try? await Task.sleep(for: .seconds(0.6))
            }
            demoCell = nil
            try? await Task.sleep(for: .seconds(1.2))         // hold on the single peg
        }
    }

    private func demoSetup() {
        w = 3; h = 3
        pegs = [PCell(r: 0, c: 1), PCell(r: 1, c: 1), PCell(r: 0, c: 2), PCell(r: 1, c: 2)]
        selected = nil
        demoCell = nil
        assignTints(shuffled: false)
        ready = true
        phase = .play
        timeLeft = timeLimit
    }

    private var gameBody: some View {
        ZStack {
            RadialGradient(colors: [Self.feltTop, Self.feltBottom], center: UnitPoint(x: 0.5, y: 0.42),
                           startRadius: 10, endRadius: 560)
            VStack(spacing: isDemo ? 4 : 10) {
                statusRow
                if !isDemo { timeBar.frame(height: 6).padding(.horizontal, 48) }
                boardView
            }
            .padding(.top, isDemo ? 8 : 14)
            .padding(.bottom, isDemo ? 4 : 10)
            .padding(.horizontal, isDemo ? 4 : 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Canvas { ctx, s in
                PegArt.marble(ctx, at: CGPoint(x: s.width / 2, y: s.height / 2), r: s.width * 0.42, tint: 3, shadow: false)
            }
            .frame(width: isDemo ? 18 : 22, height: isDemo ? 18 : 22)
            Text(L("\(pegs.count) PEG\(pegs.count == 1 ? "" : "S") LEFT", "CÒN \(pegs.count) QUÂN"))
                .font(.system(size: isDemo ? 17 : 20, weight: .black, design: .rounded))
                .foregroundStyle(pegs.count == 1 ? BananaTheme.banana : .white)
                .contentTransition(.numericText())
        }
        .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 2)
    }

    private var boardView: some View {
        GeometryReader { geo in
            let lay = PegArt.layout(geo.size, w: w, h: h)
            ZStack {
                PegBoardWood(size: geo.size, w: w, h: h).equatable()
                TimelineView(.animation(paused: hop == nil)) { tl in
                    Canvas { ctx, _ in drawPieces(ctx, lay, now: tl.date) }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { loc in
                guard !isDemo, let cell = lay.cell(at: loc) else { return }
                tapHole(cell)
            }
        }
    }

    /// Marbles, legal-jump glows, the hop in flight, captured marbles in the groove, demo finger.
    private func drawPieces(_ ctx: GraphicsContext, _ lay: PegLayout, now: Date) {
        guard lay.cell > 0 else { return }
        let r = lay.cell * 0.36
        let hk = hop.map { min(1, now.timeIntervalSince($0.t0) / 0.26) } ?? 1
        let ck = hop.map { min(1, now.timeIntervalSince($0.t0) / 0.42) } ?? 1

        // Captured marbles resting in the groove (the newest one flies in from the board).
        for (i, k) in captured.enumerated() where !(hop?.slot == i && ck < 1) {
            PegArt.marble(ctx, at: lay.groovePoint(i), r: lay.cell * 0.14, tint: k)
        }

        // Legal landing holes for the selected marble glow gold.
        if let s = selected {
            for (dr, dc) in [(2, 0), (-2, 0), (0, 2), (0, -2)] {
                let to = PCell(r: s.r + dr, c: s.c + dc)
                guard to.r >= 0, to.r < h, to.c >= 0, to.c < w, jumpMid(from: s, to: to) != nil else { continue }
                let c = lay.center(to)
                let rr = lay.cell * 0.3
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)),
                         with: .radialGradient(Gradient(colors: [BananaTheme.banana.opacity(0.55), BananaTheme.banana.opacity(0)]),
                                               center: c, startRadius: 0, endRadius: rr))
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)),
                           with: .color(BananaTheme.banana), lineWidth: max(2, lay.cell * 0.05))
            }
        }

        // Resting marbles (the selected one lifts off its hole; the hopping one is drawn in flight).
        for p in pegs.sorted(by: { ($0.r, $0.c) < ($1.r, $1.c) }) {
            if let hp = hop, hk < 1, p == hp.to { continue }
            let c = lay.center(p)
            if p == selected {
                let rr = lay.cell * 0.43
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)),
                           with: .color(.white.opacity(0.9)), lineWidth: max(2, lay.cell * 0.045))
                PegArt.marble(ctx, at: CGPoint(x: c.x, y: c.y - lay.cell * 0.07), r: r * 1.1, tint: tint[p] ?? 0, lift: 1)
            } else {
                PegArt.marble(ctx, at: c, r: r, tint: tint[p] ?? 0)
            }
        }

        if let hp = hop {
            // The jumped marble drops out of its hole and rolls into its groove slot.
            if ck < 1 {
                let a = lay.center(hp.mid), b = lay.groovePoint(hp.slot)
                let e = 1 - pow(1 - ck, 3)
                let p = CGPoint(x: a.x + (b.x - a.x) * e, y: a.y + (b.y - a.y) * e)
                PegArt.marble(ctx, at: p, r: r + (lay.cell * 0.14 - r) * e, tint: hp.midTint)
            }
            // The jumping marble arcs over it.
            if hk < 1 {
                let a = lay.center(hp.from), b = lay.center(hp.to)
                let e = hk < 0.5 ? 2 * hk * hk : 1 - pow(-2 * hk + 2, 2) / 2
                let lift = CGFloat(sin(hk * .pi))
                let p = CGPoint(x: a.x + (b.x - a.x) * e, y: a.y + (b.y - a.y) * e - lift * lay.cell * 0.45)
                PegArt.marble(ctx, at: p, r: r * (1 + 0.12 * lift), tint: hp.tint, lift: lift)
            }
        }

        // Demo finger on the hole being tapped.
        if isDemo, let d = demoCell {
            let c = lay.center(d)
            var hand = ctx.resolve(Image(systemName: "hand.point.up.left.fill"))
            hand.shading = .color(.white)
            var g = ctx
            g.addFilter(.shadow(color: .black.opacity(0.6), radius: 3))
            let hw = lay.cell * 0.55
            g.draw(hand, in: CGRect(x: c.x + lay.cell * 0.02, y: c.y + lay.cell * 0.1, width: hw, height: hw))
        }
    }

    /// Gives every marble a glass colour; the colours then travel with the marbles.
    private func assignTints(shuffled: Bool) {
        let order = pegs.sorted { ($0.r, $0.c) < ($1.r, $1.c) }
        var kinds = (0..<order.count).map { $0 % PegArt.marbleCount }
        if shuffled { kinds.shuffle() }
        tint = Dictionary(uniqueKeysWithValues: zip(order, kinds))
        captured = []
        hop = nil
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.3))
                Capsule().fill(frac < 0.3 ? .red : BananaTheme.banana)
                    .frame(width: geo.size.width * frac)
            }
        }
    }

    // MARK: - Input
    /// The peg jumped over if `from` can legally leap to `to`, else nil.
    private func jumpMid(from: PCell, to: PCell) -> PCell? {
        guard pegs.contains(from), !pegs.contains(to) else { return nil }
        let dr = to.r - from.r, dc = to.c - from.c
        let ok = (abs(dr) == 2 && dc == 0) || (abs(dc) == 2 && dr == 0)
        guard ok else { return nil }
        let mid = PCell(r: from.r + dr / 2, c: from.c + dc / 2)
        return pegs.contains(mid) ? mid : nil
    }

    private func tapHole(_ cell: PCell) {
        guard phase == .play else { return }
        if let s = selected {
            if s == cell { selected = nil; return }
            if let mid = jumpMid(from: s, to: cell) {
                pegs.remove(s); pegs.remove(mid); pegs.insert(cell)
                selected = nil
                recordHop(from: s, over: mid, to: cell)
                SoundManager.shared.tap(); Haptics.tap()
                if pegs.count == 1 { win(); return }
                if isDead() { deadFail() }
                return
            }
            if pegs.contains(cell) { selected = cell; SoundManager.shared.tap(); return }
            selected = nil
        } else if pegs.contains(cell) {
            selected = cell; SoundManager.shared.tap()
        }
    }

    /// Presentation only: the jumping marble keeps its colour, the jumped one heads for the groove.
    private func recordHop(from: PCell, over mid: PCell, to: PCell) {
        let t = tint[from] ?? 0, mt = tint[mid] ?? 0
        tint[from] = nil; tint[mid] = nil; tint[to] = t
        captured.append(mt)
        let stamp = Date()
        hop = PegHop(from: from, to: to, mid: mid, tint: t, midTint: mt, slot: captured.count - 1, t0: stamp)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            if hop?.t0 == stamp { hop = nil }
        }
    }

    private func isDead() -> Bool {
        for p in pegs {
            for (dr, dc) in [(2, 0), (-2, 0), (0, 2), (0, -2)] {
                let to = PCell(r: p.r + dr, c: p.c + dc)
                if to.r >= 0, to.r < h, to.c >= 0, to.c < w, jumpMid(from: p, to: to) != nil { return false }
            }
        }
        return true
    }

    private func deadFail() {
        guard phase == .play else { return }
        phase = .done; loopTask?.cancel()
        SoundManager.shared.error(); Haptics.warning()
        Task { try? await Task.sleep(for: .seconds(0.4)); onFail() }
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
        let p = params
        BoardCache.prefetch(boardKey) { Self.makePuzzle(p) }
    }
    private var boardKey: String { BoardCache.key("peg-solitaire", level: level) }

    private func run() async {
        let p = params
        let t0 = Date()
        let puzzle = await BoardCache.take(boardKey) { Self.makePuzzle(p) }
        guard !Task.isCancelled else { return }
        await BoardCache.holdBrainstorm(since: t0, minimum: 0.6)
        guard !Task.isCancelled else { return }
        w = puzzle.w; h = puzzle.h; pegs = puzzle.pegs
        selected = nil
        assignTints(shuffled: true)
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

    // MARK: - Generation (backward un-jumping / off-main)
    private nonisolated static func makePuzzle(_ p: (w: Int, h: Int, pegs: Int)) -> PegPuzzle {
        var best = PegPuzzle(w: p.w, h: p.h, pegs: [])
        for _ in 0..<40 {
            let cand = build(p)
            if cand.pegs.count >= p.pegs { return cand }
            if cand.pegs.count > best.pegs.count { best = cand }
        }
        return best.pegs.count >= 3 ? best : fallback(p)
    }

    private nonisolated static func build(_ p: (w: Int, h: Int, pegs: Int)) -> PegPuzzle {
        func inb(_ c: PCell) -> Bool { c.r >= 0 && c.r < p.h && c.c >= 0 && c.c < p.w }
        var pegs: Set<PCell> = [PCell(r: Int.random(in: 0..<p.h), c: Int.random(in: 0..<p.w))]
        var guardN = 0
        let dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        while pegs.count < p.pegs && guardN < p.pegs * 60 {
            guardN += 1
            var did = false
            for c in pegs.shuffled() {
                for (dr, dc) in dirs.shuffled() {
                    // Un-jump: peg at C moves to A = C + 2d, restoring B = C + d.
                    let a = PCell(r: c.r + dr * 2, c: c.c + dc * 2)
                    let b = PCell(r: c.r + dr, c: c.c + dc)
                    if inb(a), inb(b), !pegs.contains(a), !pegs.contains(b) {
                        pegs.remove(c); pegs.insert(a); pegs.insert(b)
                        did = true
                        break
                    }
                }
                if did { break }
            }
            if !did { break }
        }
        return PegPuzzle(w: p.w, h: p.h, pegs: pegs)
    }

    private nonisolated static func fallback(_ p: (w: Int, h: Int, pegs: Int)) -> PegPuzzle {
        // Three in a row: A B empty → guaranteed one jump to a single peg.
        PegPuzzle(w: max(p.w, 3), h: max(p.h, 1),
                  pegs: [PCell(r: 0, c: 0), PCell(r: 0, c: 1)])
    }
}

// MARK: - Marble solitaire art

private struct PegHop {
    let from: PCell, to: PCell, mid: PCell
    let tint: Int, midTint: Int
    let slot: Int              // groove slot the jumped marble rolls into
    let t0: Date
}

private struct PegLayout {
    let origin: CGPoint        // top-left of the hole grid
    let cell: CGFloat
    let w: Int, h: Int

    var grid: CGRect { CGRect(x: origin.x, y: origin.y, width: cell * CGFloat(w), height: cell * CGFloat(h)) }
    var board: CGRect { grid.insetBy(dx: -cell * 0.72, dy: -cell * 0.72) }
    /// Centre line of the carved groove that runs round the board.
    var groove: CGRect { grid.insetBy(dx: -cell * 0.34, dy: -cell * 0.34) }
    var grooveRadius: CGFloat { min(cell * 0.45, min(groove.width, groove.height) / 2) }

    func center(_ p: PCell) -> CGPoint {
        CGPoint(x: origin.x + (CGFloat(p.c) + 0.5) * cell, y: origin.y + (CGFloat(p.r) + 0.5) * cell)
    }

    func cell(at p: CGPoint) -> PCell? {
        guard cell > 0 else { return nil }
        let c = Int(floor((p.x - origin.x) / cell)), r = Int(floor((p.y - origin.y) / cell))
        return (r >= 0 && r < h && c >= 0 && c < w) ? PCell(r: r, c: c) : nil
    }

    /// The i-th resting spot in the groove, clockwise from the top-left.
    func groovePoint(_ i: Int) -> CGPoint {
        let g = groove, rr = grooveRadius
        let top = g.width - 2 * rr, side = g.height - 2 * rr, arc = CGFloat.pi * rr / 2
        let perimeter = 2 * top + 2 * side + 4 * arc
        guard perimeter > 0 else { return CGPoint(x: g.midX, y: g.midY) }
        var s = (cell * 0.2 + CGFloat(i) * cell * 0.31).truncatingRemainder(dividingBy: perimeter)
        func arcPoint(_ cx: CGFloat, _ cy: CGFloat, _ a0: Double) -> CGPoint {
            let a = a0 + Double(s / max(rr, 0.001))
            return CGPoint(x: cx + rr * CGFloat(cos(a)), y: cy + rr * CGFloat(sin(a)))
        }
        if s < top { return CGPoint(x: g.minX + rr + s, y: g.minY) }; s -= top
        if s < arc { return arcPoint(g.maxX - rr, g.minY + rr, -.pi / 2) }; s -= arc
        if s < side { return CGPoint(x: g.maxX, y: g.minY + rr + s) }; s -= side
        if s < arc { return arcPoint(g.maxX - rr, g.maxY - rr, 0) }; s -= arc
        if s < top { return CGPoint(x: g.maxX - rr - s, y: g.maxY) }; s -= top
        if s < arc { return arcPoint(g.minX + rr, g.maxY - rr, .pi / 2) }; s -= arc
        if s < side { return CGPoint(x: g.minX, y: g.maxY - rr - s) }; s -= side
        return arcPoint(g.minX + rr, g.minY + rr, .pi)
    }
}

private enum PegArt {
    /// Glass marble colours: body + the swirl ribbon inside.
    static let glass: [(base: Color, swirl: Color)] = [
        (Color(red: 0.16, green: 0.38, blue: 0.90), Color(red: 0.85, green: 0.95, blue: 1.00)),   // cobalt
        (Color(red: 0.86, green: 0.14, blue: 0.20), Color(red: 1.00, green: 0.90, blue: 0.70)),   // ruby
        (Color(red: 0.10, green: 0.62, blue: 0.36), Color(red: 0.95, green: 1.00, blue: 0.75)),   // emerald
        (Color(red: 0.98, green: 0.64, blue: 0.10), Color(red: 1.00, green: 0.98, blue: 0.85)),   // amber
        (Color(red: 0.58, green: 0.32, blue: 0.90), Color(red: 1.00, green: 0.85, blue: 1.00)),   // violet
        (Color(red: 0.10, green: 0.68, blue: 0.76), Color(red: 1.00, green: 1.00, blue: 1.00)),   // aqua
    ]
    static var marbleCount: Int { glass.count }

    static let teakLight = Color(red: 0.86, green: 0.58, blue: 0.33)
    static let teak = Color(red: 0.71, green: 0.43, blue: 0.21)
    static let teakDark = Color(red: 0.47, green: 0.26, blue: 0.11)

    /// Hole grid centred in `s`, leaving room for the rim + groove on every side.
    static func layout(_ s: CGSize, w: Int, h: Int) -> PegLayout {
        guard w > 0, h > 0, s.width > 0, s.height > 0 else { return PegLayout(origin: .zero, cell: 0, w: 0, h: 0) }
        let pad: CGFloat = 1.52
        let cell = min(s.width / (CGFloat(w) + pad), s.height / (CGFloat(h) + pad))
        let gw = cell * CGFloat(w), gh = cell * CGFloat(h)
        return PegLayout(origin: CGPoint(x: (s.width - gw) / 2, y: (s.height - gh) / 2), cell: cell, w: w, h: h)
    }

    /// The teak board: drop shadow, grain, bevel, the carved groove and every drilled hole.
    static func drawBoard(_ ctx: GraphicsContext, _ lay: PegLayout) {
        let c = lay.cell
        guard c > 0 else { return }
        let b = lay.board
        let corner = c * 0.75
        let shape = Path(roundedRect: b, cornerRadius: corner)

        var sh = ctx
        sh.addFilter(.blur(radius: c * 0.2))
        sh.fill(Path(roundedRect: b.offsetBy(dx: 0, dy: c * 0.16), cornerRadius: corner), with: .color(.black.opacity(0.55)))

        ctx.fill(shape, with: .linearGradient(Gradient(colors: [teakLight, teak, teakDark]),
                                              startPoint: CGPoint(x: b.minX, y: b.minY),
                                              endPoint: CGPoint(x: b.maxX, y: b.maxY)))
        // Grain: long wavy strokes along the board.
        var g = ctx
        g.clip(to: shape)
        let lines = max(8, Int(b.height / (c * 0.1)))
        for i in 0..<lines {
            let y0 = b.minY + (CGFloat(i) + 0.5) * b.height / CGFloat(lines)
            let amp = c * (0.03 + 0.05 * CGFloat((i * 37) % 5) / 4)
            let phase = Double(i) * 1.7
            var p = Path()
            p.move(to: CGPoint(x: b.minX - 2, y: y0))
            var x = b.minX
            while x <= b.maxX + c * 0.25 {
                x += c * 0.22
                p.addLine(to: CGPoint(x: x, y: y0 + amp * CGFloat(sin(Double((x - b.minX) / (c * 1.7)) + phase))))
            }
            let dark = (i * 7) % 3 == 0
            g.stroke(p, with: .color(teakDark.opacity(dark ? 0.32 : 0.16)),
                     lineWidth: dark ? max(1, c * 0.024) : max(0.6, c * 0.012))
        }
        // Bevel: lit top-left edge, shaded bottom-right edge.
        ctx.stroke(Path(roundedRect: b.insetBy(dx: c * 0.035, dy: c * 0.035), cornerRadius: corner * 0.95),
                   with: .linearGradient(Gradient(colors: [.white.opacity(0.4), .clear, .black.opacity(0.35)]),
                                         startPoint: CGPoint(x: b.minX, y: b.minY), endPoint: CGPoint(x: b.maxX, y: b.maxY)),
                   lineWidth: c * 0.07)
        ctx.stroke(shape, with: .color(teakDark.shade(0.35)), lineWidth: max(1, c * 0.02))

        // The groove: a dark channel whose far wall catches the light.
        let groove = Path(roundedRect: lay.groove, cornerRadius: lay.grooveRadius)
        ctx.stroke(groove, with: .color(teakDark.shade(0.12)), lineWidth: c * 0.3)
        ctx.stroke(groove, with: .linearGradient(Gradient(colors: [.black.opacity(0.3), .clear, teakLight.opacity(0.3)]),
                                                 startPoint: CGPoint(x: b.minX, y: b.minY),
                                                 endPoint: CGPoint(x: b.maxX, y: b.maxY)),
                   lineWidth: c * 0.22)
        // Its two edges: a dark inner lip and a lit outer lip.
        ctx.stroke(Path(roundedRect: lay.groove.insetBy(dx: c * 0.15, dy: c * 0.15), cornerRadius: max(0, lay.grooveRadius - c * 0.15)),
                   with: .color(teakLight.opacity(0.45)), lineWidth: max(0.8, c * 0.02))
        ctx.stroke(Path(roundedRect: lay.groove.insetBy(dx: -c * 0.15, dy: -c * 0.15), cornerRadius: lay.grooveRadius + c * 0.15),
                   with: .color(teakDark.shade(0.4).opacity(0.6)), lineWidth: max(0.8, c * 0.02))

        for r in 0..<lay.h {
            for col in 0..<lay.w { hole(ctx, lay.center(PCell(r: r, c: col)), c * 0.2) }
        }
    }

    static func hole(_ ctx: GraphicsContext, _ p: CGPoint, _ r: CGFloat) {
        let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: rect),
                 with: .radialGradient(Gradient(colors: [Color(red: 0.09, green: 0.04, blue: 0.02),
                                                         Color(red: 0.2, green: 0.1, blue: 0.04), teakDark]),
                                       center: CGPoint(x: p.x - r * 0.2, y: p.y - r * 0.25), startRadius: 0, endRadius: r * 1.15))
        // The lower lip catches the light.
        var lip = ctx
        lip.clip(to: Path(CGRect(x: p.x - r * 1.3, y: p.y + r * 0.1, width: r * 2.6, height: r * 1.3)))
        lip.stroke(Path(ellipseIn: rect), with: .color(teakLight.lit(0.25).opacity(0.6)), lineWidth: max(1, r * 0.12))
    }

    /// A glossy glass marble with a swirl, lit from the upper-left. `lift` (0…1) raises it off the board.
    static func marble(_ ctx: GraphicsContext, at c: CGPoint, r: CGFloat, tint k: Int,
                       lift: CGFloat = 0, shadow: Bool = true) {
        let m = glass[((k % glass.count) + glass.count) % glass.count]
        if shadow {
            var s = ctx
            s.opacity = Double(0.42 - 0.17 * lift)
            let off = r * (0.2 + 0.55 * lift)
            s.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.88 + off * 0.45, y: c.y - r * 0.7 + off, width: r * 1.76, height: r * 1.55)),
                   with: .color(.black))
        }
        let body = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.fill(body, with: .radialGradient(Gradient(colors: [m.base.lit(0.5), m.base, m.base.shade(0.5)]),
                                             center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4), startRadius: 0, endRadius: r * 1.55))
        // Swirl ribbon inside the glass.
        var g = ctx
        g.clip(to: body)
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .radians(Double(k) * 1.9 + 0.4))
        var sw = Path()
        sw.move(to: CGPoint(x: -r, y: r * 0.3))
        sw.addCurve(to: CGPoint(x: r, y: -r * 0.25), control1: CGPoint(x: -r * 0.3, y: -r * 0.55),
                    control2: CGPoint(x: r * 0.25, y: r * 0.6))
        g.stroke(sw, with: .color(m.swirl.opacity(0.55)), style: StrokeStyle(lineWidth: r * 0.32, lineCap: .round))
        g.stroke(sw, with: .color(m.swirl.opacity(0.9)), style: StrokeStyle(lineWidth: r * 0.08, lineCap: .round))
        // Light gathering in the far side of the glass.
        ctx.fill(body, with: .radialGradient(Gradient(colors: [m.base.lit(0.6).opacity(0.55), .clear]),
                                             center: CGPoint(x: c.x + r * 0.35, y: c.y + r * 0.45), startRadius: 0, endRadius: r * 0.55))
        ctx.stroke(body, with: .color(m.base.shade(0.65).opacity(0.6)), lineWidth: max(0.7, r * 0.06))
        // Specular glints.
        var hl = ctx
        hl.translateBy(x: c.x - r * 0.38, y: c.y - r * 0.44)
        hl.rotate(by: .degrees(-35))
        hl.fill(Path(ellipseIn: CGRect(x: -r * 0.3, y: -r * 0.17, width: r * 0.6, height: r * 0.34)), with: .color(.white.opacity(0.85)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x + r * 0.3, y: c.y + r * 0.42, width: r * 0.2, height: r * 0.12)),
                 with: .color(.white.opacity(0.4)))
    }
}

/// The static teak board (grain, groove, holes) — equatable, so the timer ticks never redraw it.
private struct PegBoardWood: View, Equatable {
    let size: CGSize
    let w: Int, h: Int

    var body: some View {
        Canvas { ctx, s in PegArt.drawBoard(ctx, PegArt.layout(s, w: w, h: h)) }
            .allowsHitTesting(false)
    }
}
