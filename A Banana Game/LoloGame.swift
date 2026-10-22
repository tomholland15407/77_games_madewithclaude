//
//  LoloGame.swift
//  A Banana Game
//
//  Brain — an Adventures-of-Lolo room. Steer the banana with the d-pad, collect every heart, then
//  reach the door. Stone statues (Medusas) petrify anything in their line of sight — the red tiles
//  are deadly. You can shove blocks (push only, Sokoban-style) to break a statue's gaze and carve a
//  safe path. Step into a gaze, or let the clock run out, and you're back to level 1.
//
//  Rooms are seeded at random and then hill-climbed: pieces move one at a time while a search over
//  (player, block layout, hearts left) keeps proving a fully safe solution, and the climb keeps the
//  room that needs the most separate push runs and has every block doing a job. So every board is
//  solvable without ever standing in a gaze, can't be done without pushing, and wrong pushes can
//  strand you. Generation runs off-main behind the brainstorming banana. Levels add statues, blocks,
//  hearts, room size and required push runs until it's brutal.
//

import SwiftUI

private nonisolated struct LCell: Hashable, Sendable { let r: Int; let c: Int }

private nonisolated struct LoloPuzzle: Sendable {
    let rows: Int; let cols: Int
    let walls: Set<LCell>; let medusas: Set<LCell>
    let blocks: Set<LCell>; let hearts: Set<LCell>
    let player: LCell; let exit: LCell
}

/// A level's room recipe: interior size, statues, blocks, hearts and boulders, then the climb's targets
/// (push runs a solution needs, blocks that must move) and its step budget.
private typealias LoloParams = (iw: Int, ih: Int, med: Int, blk: Int, hrt: Int, walls: Int, runs: Int, must: Int, steps: Int)

enum LoloGame {
    static let definition = GameDefinition(
        id: "lolo",
        title: "Statue Maze",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Move the banana with the d-pad; collect every heart, then reach the door.",
                "Statues petrify their straight line of sight — red tiles are instant death.",
                "Push blocks (never pull) to break a statue's gaze and open a safe route.",
                "A gaze or the clock running out sends you back to level 1.",
            ],
            bulletsVI: [
                "Di chuyển quả chuối bằng d-pad; nhặt hết trái tim rồi đến cửa.",
                "Tượng đá hóa đá theo đường nhìn thẳng — ô đỏ là chết ngay.",
                "Đẩy khối (chỉ đẩy, không kéo) để chặn tầm nhìn của tượng và mở lối an toàn.",
                "Bị tầm nhìn quét trúng hoặc hết giờ sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(LoloView(level: level, onWin: onWin, onFail: onFail))
        },
        prefetch: { level in LoloView(level: level, onWin: {}, onFail: {}).prefetchBoard() }
    )
}

struct LoloView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    // interior (w,h), medusas, blocks, hearts, interior walls, push runs needed, blocks that must move,
    // climb steps
    private var params: LoloParams {
        [ (6, 4, 2, 1, 2, 1, 2, 1, 300),
          (6, 5, 2, 2, 2, 1, 3, 2, 300),
          (7, 5, 3, 2, 3, 2, 4, 2, 300),
          (7, 6, 3, 2, 3, 2, 5, 2, 300),
          (7, 6, 3, 3, 3, 3, 6, 3, 300),
          (8, 6, 4, 3, 3, 3, 7, 3, 350),
          (8, 7, 4, 3, 4, 4, 8, 3, 400) ][min(level, 7) - 1]
    }
    private var timeLimit: Double { [40, 50, 60, 70, 80, 85, 90][min(level, 7) - 1] }

    private var skyTop: Color { Color(red: 0.36, green: 0.2, blue: 0.11) }
    private var skyBottom: Color { Color(red: 0.14, green: 0.08, blue: 0.04) }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var ready = false
    @State private var rows = 0
    @State private var cols = 0
    @State private var walls: Set<LCell> = []
    @State private var medusas: Set<LCell> = []
    @State private var blocks: Set<LCell> = []
    @State private var hearts: Set<LCell> = []
    @State private var player = LCell(r: 0, c: 0)
    @State private var exit = LCell(r: 0, c: 0)
    @State private var timeLeft = 0.0
    @State private var shakeTick = 0
    @State private var loopTask: Task<Void, Never>?
    @State private var demoDir: (dc: Int, dr: Int)? = nil   // d-pad arrow flashed in the demo
    // Presentation only: which way the banana faces, how many hearts the room started with, and
    // whether the gaze has turned the banana to stone.
    @State private var facingLeft = false
    @State private var heartTotal = 0
    @State private var stoned = false

    private var deadlyNow: Set<LCell> {
        Self.deadly(rows: rows, cols: cols, walls: walls, medusas: medusas, exit: exit, blocks: blocks)
    }

    var body: some View {
        Group {
            if ready { gameBody } else { BrainstormingView(skyTop: skyTop, skyBottom: skyBottom) }
        }
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
    }

    // MARK: - Demo (live manual clip)

    /// A safe hand-built room: walk right to grab the heart, then onto the door. A
    /// Medusa in the corner paints its (avoided) red gaze so the danger is on show.
    /// Drives the real `move`; the gaze rays never cross the player's row.
    private func runDemo() async {
        while !Task.isCancelled {
            demoSetup()
            try? await Task.sleep(for: .seconds(0.7))
            for _ in 0..<4 {                       // right, right (heart), right, right (door)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.1)) { demoDir = (1, 0) }
                move(dc: 1, dr: 0)
                try? await Task.sleep(for: .seconds(0.3))
                withAnimation(.easeIn(duration: 0.1)) { demoDir = nil }
                try? await Task.sleep(for: .seconds(0.25))
            }
            try? await Task.sleep(for: .seconds(1.1))   // hold on reaching the door
        }
    }

    private func demoSetup() {
        let r = 5, c = 7                          // interior 5×3 + border
        rows = r; cols = c
        var wl = Set<LCell>()
        for rr in 0..<r { wl.insert(LCell(r: rr, c: 0)); wl.insert(LCell(r: rr, c: c - 1)) }
        for cc in 0..<c { wl.insert(LCell(r: 0, c: cc)); wl.insert(LCell(r: r - 1, c: cc)) }
        walls = wl
        medusas = [LCell(r: 3, c: 5)]             // gaze rays stop at walls/exit — never hit row 1
        blocks = []
        hearts = [LCell(r: 1, c: 3)]
        heartTotal = 1
        facingLeft = false
        stoned = false
        player = LCell(r: 1, c: 1)
        exit = LCell(r: 1, c: 5)
        ready = true
        phase = .play
        timeLeft = timeLimit
    }

    private var gameBody: some View {
        VStack(spacing: isDemo ? 6 : 10) {
            statusRow
            if !isDemo { timeBar.frame(height: 5).padding(.horizontal, 60) }
            boardView
            dpad
        }
        .padding(.top, isDemo ? 8 : 12)
        .padding(.bottom, isDemo ? 8 : 12)
        .background(Color(red: 0.05, green: 0.04, blue: 0.04))
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Heart Framers still to collect; once they're all in, the door opens.
    private var statusRow: some View {
        Group {
            if hearts.isEmpty {
                Text(L("REACH THE DOOR", "ĐẾN CỬA"))
                    .font(.system(size: isDemo ? 16 : 18, weight: .black, design: .rounded))
                    .foregroundStyle(BananaTheme.banana)
            } else {
                HStack(spacing: isDemo ? 5 : 7) {
                    ForEach(0..<max(heartTotal, hearts.count), id: \.self) { i in
                        Canvas { ctx, s in LoloArt.heartFramer(ctx, CGRect(origin: .zero, size: s)) }
                            .frame(width: isDemo ? 18 : 24, height: isDemo ? 18 : 24)
                            .opacity(i < hearts.count ? 1 : 0.25)
                    }
                }
            }
        }
        .frame(height: isDemo ? 20 : 26)
    }

    private var boardView: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let cell = cols > 0 ? min(w / CGFloat(cols), h / CGFloat(rows)) : 0
            let ox = (w - cell * CGFloat(cols)) / 2
            let oy = (h - cell * CGFloat(rows)) / 2
            ZStack(alignment: .topLeading) {
                LoloRoom(rows: rows, cols: cols, walls: walls, cell: cell, origin: CGPoint(x: ox, y: oy)).equatable()
                Canvas { ctx, _ in drawPieces(ctx, cell: cell, ox: ox, oy: oy) }
                if cell > 0 {
                    Canvas { ctx, s in
                        LoloArt.hero(ctx, CGRect(origin: .zero, size: s), facingLeft: facingLeft, stone: stoned)
                    }
                    .frame(width: cell, height: cell)
                    .position(x: ox + (CGFloat(player.c) + 0.5) * cell, y: oy + (CGFloat(player.r) + 0.5) * cell)
                    .animation(.easeOut(duration: 0.11), value: player)
                }
            }
            .frame(width: w, height: h)
            .clipped()
            .screenShake(shakeTick, amount: 4)
        }
    }

    /// Gaze beams, the door, Heart Framers, Emerald Framers and the Medusas.
    private func drawPieces(_ ctx: GraphicsContext, cell: CGFloat, ox: CGFloat, oy: CGFloat) {
        guard cell > 0 else { return }
        func rect(_ c: LCell) -> CGRect {
            CGRect(x: ox + CGFloat(c.c) * cell, y: oy + CGFloat(c.r) * cell, width: cell, height: cell)
        }
        func mid(_ c: LCell) -> CGPoint { CGPoint(x: rect(c).midX, y: rect(c).midY) }

        // The petrifying gaze: every deadly tile glows red, with a beam down each line of sight.
        for c in deadlyNow {
            ctx.fill(Path(rect(c)), with: .color(LoloArt.gaze.opacity(0.3)))
        }
        for m in medusas {
            for (dr, dc) in [(0, 1), (0, -1), (1, 0), (-1, 0)] {
                var last: LCell? = nil
                var r = m.r + dr, c = m.c + dc
                while r >= 0 && r < rows && c >= 0 && c < cols {
                    let cc = LCell(r: r, c: c)
                    if walls.contains(cc) || medusas.contains(cc) || blocks.contains(cc) || cc == exit { break }
                    last = cc
                    r += dr; c += dc
                }
                guard let end = last else { continue }
                var beam = Path()
                let a = mid(m), b = mid(end)
                beam.move(to: CGPoint(x: a.x + CGFloat(dc) * cell * 0.35, y: a.y + CGFloat(dr) * cell * 0.35))
                beam.addLine(to: CGPoint(x: b.x + CGFloat(dc) * cell * 0.5, y: b.y + CGFloat(dr) * cell * 0.5))
                ctx.stroke(beam, with: .color(LoloArt.gaze.opacity(0.35)), style: StrokeStyle(lineWidth: cell * 0.3, lineCap: .round))
                ctx.stroke(beam, with: .color(Color(red: 1, green: 0.55, blue: 0.5).opacity(0.9)),
                           style: StrokeStyle(lineWidth: max(1.5, cell * 0.06), lineCap: .round))
            }
        }

        LoloArt.door(ctx, rect(exit), open: hearts.isEmpty)
        for h in hearts { LoloArt.heartFramer(ctx, rect(h).insetBy(dx: cell * 0.1, dy: cell * 0.1)) }
        for b in blocks { LoloArt.emeraldFramer(ctx, rect(b)) }
        for m in medusas { LoloArt.medusa(ctx, rect(m)) }
    }

    /// An NES-style cross d-pad; the pressed arm lights up.
    private var dpad: some View {
        let a: CGFloat = isDemo ? 32 : 46
        return ZStack {
            NESCross().fill(Color(white: 0.42)).frame(width: a * 3 + 4, height: a * 3 + 4)
            NESCross()
                .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.1)], startPoint: .top, endPoint: .bottom))
                .frame(width: a * 3, height: a * 3)
            Circle().fill(Color(white: 0.07)).frame(width: a * 0.55, height: a * 0.55)
            arm(0, -1, a).offset(y: -a)
            arm(-1, 0, a).offset(x: -a)
            arm(1, 0, a).offset(x: a)
            arm(0, 1, a).offset(y: a)
        }
        .frame(width: a * 3 + 4, height: a * 3 + 4)
        .shadow(color: .black.opacity(0.5), radius: 0, x: 0, y: 3)
    }

    private func arm(_ dc: Int, _ dr: Int, _ a: CGFloat) -> some View {
        let lit = demoDir?.dc == dc && demoDir?.dr == dr
        let angle: Double = dr < 0 ? 0 : dr > 0 ? 180 : dc < 0 ? 270 : 90
        return Button { move(dc: dc, dr: dr) } label: {
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: a * 0.36, weight: .black))
                .rotationEffect(.degrees(angle))
                .frame(width: a, height: a)
                .contentShape(Rectangle())
        }
        .buttonStyle(DPadArmStyle(lit: lit, radius: a * 0.16))
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

    // MARK: - Input
    private func move(dc: Int, dr: Int) {
        guard phase == .play else { return }
        if dc != 0 { facingLeft = dc < 0 }
        let dest = LCell(r: player.r + dr, c: player.c + dc)
        if dest.r < 0 || dest.r >= rows || dest.c < 0 || dest.c >= cols { return }
        if walls.contains(dest) || medusas.contains(dest) { return }
        if blocks.contains(dest) {
            let beyond = LCell(r: dest.r + dr, c: dest.c + dc)
            if beyond.r < 0 || beyond.r >= rows || beyond.c < 0 || beyond.c >= cols { return }
            if walls.contains(beyond) || medusas.contains(beyond) || blocks.contains(beyond)
                || hearts.contains(beyond) || beyond == exit { return }
            blocks.remove(dest); blocks.insert(beyond)
            player = dest
        } else {
            player = dest
            if hearts.contains(dest) { hearts.remove(dest); Haptics.tap() }
        }
        SoundManager.shared.tap()
        if deadlyNow.contains(player) { petrified(); return }
        if hearts.isEmpty && player == exit { win() }
    }

    private func petrified() {
        guard phase == .play else { return }
        phase = .done; loopTask?.cancel()
        stoned = true
        SoundManager.shared.error(); Haptics.warning(); shakeTick += 1
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
    private var boardKey: String { BoardCache.key("lolo", level: level) }

    private func run() async {
        let p = params
        let t0 = Date()
        let puzzle = await BoardCache.take(boardKey) { Self.makePuzzle(p) }
        guard !Task.isCancelled else { return }
        await BoardCache.holdBrainstorm(since: t0, minimum: 0.7)
        guard !Task.isCancelled else { return }
        rows = puzzle.rows; cols = puzzle.cols
        walls = puzzle.walls; medusas = puzzle.medusas
        blocks = puzzle.blocks; hearts = puzzle.hearts
        player = puzzle.player; exit = puzzle.exit
        heartTotal = puzzle.hearts.count; stoned = false
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

    // MARK: - Gaze (pure)
    private nonisolated static func deadly(rows: Int, cols: Int, walls: Set<LCell>, medusas: Set<LCell>,
                                           exit: LCell, blocks: Set<LCell>) -> Set<LCell> {
        var out = Set<LCell>()
        for m in medusas {
            for (dr, dc) in [(0, 1), (0, -1), (1, 0), (-1, 0)] {
                var r = m.r + dr, c = m.c + dc
                while r >= 0 && r < rows && c >= 0 && c < cols {
                    let cell = LCell(r: r, c: c)
                    if walls.contains(cell) || medusas.contains(cell) || blocks.contains(cell) || cell == exit { break }
                    out.insert(cell)
                    r += dr; c += dc
                }
            }
        }
        return out
    }

    // MARK: - Generation + hill climb (pure / off-main)
    /// Seeds a random room that can't be solved without pushing, then hill-climbs it: move one piece to
    /// another tile and keep the change while the room stays safely solvable and gets no easier. Stops at
    /// the level's targets, after `steps` tries, or at the deadline (a slow phone settles for the hardest
    /// room it has found so far).
    private nonisolated static func makePuzzle(_ p: LoloParams) -> LoloPuzzle {
        var seed: (room: LoloPuzzle, rating: (runs: Int, must: Int, score: Int))?
        for _ in 0..<4000 {
            guard let cand = generate(p), let r = rate(cand, p), r.runs > 0 else { continue }   // blocks must matter
            seed = (cand, r); break
        }
        guard let seed else { return fallback() }
        var room = seed.room, cur = seed.rating
        var best = room, top = cur
        let deadline = Date().addingTimeInterval(2)
        for _ in 0..<p.steps {
            if (top.runs >= p.runs && top.must >= p.must) || Date() > deadline { break }
            let cand = mutate(room)
            guard let r = rate(cand, p, atLeast: cur.score) else { continue }
            if r.score >= cur.score { room = cand; cur = r }       // sideways moves let it cross plateaus
            if r.score > top.score { best = cand; top = r }
        }
        return best
    }

    /// How hard a room is: the fewest push runs a safe solution needs, how many blocks must move (pinning
    /// any one of them in place makes the room unsolvable), and the climb's score. Nil if there's no safe
    /// solution. The pinning test is skipped when the room couldn't reach `need` anyway.
    private nonisolated static func rate(_ p: LoloPuzzle, _ t: LoloParams, atLeast need: Int = 0)
        -> (runs: Int, must: Int, score: Int)? {
        guard let runs = pushRuns(p) else { return nil }
        let score = { (must: Int) in 3 * min(runs, t.runs + 2) + 4 * must }
        var must = 0
        if runs > 0 && score(p.blocks.count) >= need {
            for b in p.blocks {
                var blocks = p.blocks; blocks.remove(b)
                var walls = p.walls; walls.insert(b)
                let pinned = LoloPuzzle(rows: p.rows, cols: p.cols, walls: walls, medusas: p.medusas,
                                        blocks: blocks, hearts: p.hearts, player: p.player, exit: p.exit)
                if pushRuns(pinned) == nil { must += 1 }
            }
        }
        return (runs, must, score(must))
    }

    private nonisolated static func generate(_ p: LoloParams) -> LoloPuzzle? {
        let rows = p.ih + 2, cols = p.iw + 2
        var walls = Set<LCell>()
        for r in 0..<rows { walls.insert(LCell(r: r, c: 0)); walls.insert(LCell(r: r, c: cols - 1)) }
        for c in 0..<cols { walls.insert(LCell(r: 0, c: c)); walls.insert(LCell(r: rows - 1, c: c)) }
        var floor: [LCell] = []
        for r in 1...p.ih { for c in 1...p.iw { floor.append(LCell(r: r, c: c)) } }
        floor.shuffle()
        var idx = 0
        func take(_ n: Int) -> [LCell]? {
            guard idx + n <= floor.count else { return nil }
            defer { idx += n }
            return Array(floor[idx..<idx + n])
        }
        guard let iw = take(p.walls) else { return nil }
        walls.formUnion(iw)
        guard let meds = take(p.med) else { return nil }
        guard let blks = take(p.blk) else { return nil }
        guard let hrts = take(p.hrt) else { return nil }
        guard let ex = take(1)?.first else { return nil }
        // The banana starts on a tile no gaze reaches.
        let gaze = deadly(rows: rows, cols: cols, walls: walls, medusas: Set(meds), exit: ex, blocks: Set(blks))
        guard let pl = floor[idx...].first(where: { !gaze.contains($0) }) else { return nil }
        return LoloPuzzle(rows: rows, cols: cols, walls: walls, medusas: Set(meds),
                          blocks: Set(blks), hearts: Set(hrts), player: pl, exit: ex)
    }

    /// The same room with one piece (a boulder, statue, block, heart, the banana or the door) moved to a
    /// random free tile.
    private nonisolated static func mutate(_ p: LoloPuzzle) -> LoloPuzzle {
        var walls = p.walls, meds = p.medusas, blks = p.blocks, hrts = p.hearts, pl = p.player, ex = p.exit
        var free: [LCell] = []
        for r in 1..<(p.rows - 1) {
            for c in 1..<(p.cols - 1) {
                let x = LCell(r: r, c: c)
                if !walls.contains(x) && !meds.contains(x) && !blks.contains(x) && !hrts.contains(x) && x != pl && x != ex {
                    free.append(x)
                }
            }
        }
        guard let to = free.randomElement() else { return p }
        let rocks = walls.filter { $0.r > 0 && $0.c > 0 && $0.r < p.rows - 1 && $0.c < p.cols - 1 }
        // One piece, picked uniformly: 0 boulder, 1 statue, 2 block, 3 heart, 4 banana, 5 door.
        let kinds = Array(repeating: 0, count: rocks.count) + Array(repeating: 1, count: meds.count)
            + Array(repeating: 2, count: blks.count) + Array(repeating: 3, count: hrts.count) + [4, 5]
        switch kinds.randomElement()! {
        case 0: walls.remove(rocks.randomElement()!); walls.insert(to)
        case 1: meds.remove(meds.randomElement()!); meds.insert(to)
        case 2: blks.remove(blks.randomElement()!); blks.insert(to)
        case 3: hrts.remove(hrts.randomElement()!); hrts.insert(to)
        case 4: pl = to
        default: ex = to
        }
        return LoloPuzzle(rows: p.rows, cols: p.cols, walls: walls, medusas: meds,
                          blocks: blks, hearts: hrts, player: pl, exit: ex)
    }

    // The verifier runs on bitmask states — cells are bits of a UInt128 (boards are ≤ 9×10) — and
    // memoizes the medusa-gaze map per block layout instead of re-tracing it for every step.
    private nonisolated struct LSolverGrid {
        let rows: Int, cols: Int
        let walls: UInt128, medusas: UInt128, hearts: UInt128, blocks: UInt128
        let player: Int, exit: Int
        let medusaList: [Int]
        init(_ p: LoloPuzzle) {
            rows = p.rows; cols = p.cols
            let C = p.cols
            func mask(_ s: Set<LCell>) -> UInt128 { s.reduce(0) { $0 | (1 << UInt128($1.r * C + $1.c)) } }
            walls = mask(p.walls); medusas = mask(p.medusas); hearts = mask(p.hearts); blocks = mask(p.blocks)
            player = p.player.r * C + p.player.c; exit = p.exit.r * C + p.exit.c
            medusaList = p.medusas.map { $0.r * C + $0.c }.sorted()
        }
        @inline(__always) func bit(_ i: Int) -> UInt128 { 1 << UInt128(i) }
        /// Cells swept by a medusa gaze for the given block layout (same rays as `deadly`).
        func deadly(blocks bs: UInt128) -> UInt128 {
            var out: UInt128 = 0
            let stop = walls | medusas | bs | bit(exit)
            for m in medusaList {
                let mr = m / cols, mc = m % cols
                for (dr, dc) in [(0, 1), (0, -1), (1, 0), (-1, 0)] {
                    var r = mr + dr, c = mc + dc
                    while r >= 0 && r < rows && c >= 0 && c < cols {
                        let b = bit(r * cols + c)
                        if stop & b != 0 { break }
                        out |= b
                        r += dr; c += dc
                    }
                }
            }
            return out
        }
    }

    /// The fewest push runs over all safe solutions, or nil if there is none. A run is one block shoved
    /// one or more tiles in a straight line. Walking is free, so a search state is a block layout plus the
    /// whole patch of floor the banana can walk over without crossing a gaze (grabbing every heart on it).
    /// Breadth-first over runs: the first layer with the door in the patch and every heart in hand is the
    /// answer. Same moves and gaze as `move`.
    private nonisolated static func pushRuns(_ p: LoloPuzzle) -> Int? {
        let g = LSolverGrid(p)
        var gazeCache: [UInt128: UInt128] = [:]
        func gaze(_ bs: UInt128) -> UInt128 {
            if let d = gazeCache[bs] { return d }
            let d = g.deadly(blocks: bs); gazeCache[bs] = d; return d
        }
        // Player must not start in a gaze.
        if gaze(g.blocks) & g.bit(g.player) != 0 { return nil }
        let open = ((1 << UInt128(g.rows * g.cols)) - 1) & ~(g.walls | g.medusas)
        let heartCells = p.hearts.map { $0.r * g.cols + $0.c }
        // Tiles of the hearts still to collect, by heart mask (heart i = bit i).
        let heartTiles: [UInt128] = (0..<(1 << heartCells.count)).map { m in
            heartCells.indices.reduce(0) { m & (1 << $1) != 0 ? $0 | g.bit(heartCells[$1]) : $0 }
        }
        struct Key: Hashable {
            let bs: UInt128; let x: Int                  // x = the patch's first tile | hearts left << 8
            func hash(into h: inout Hasher) {            // one word instead of three: the search is mostly hashing
                h.combine(UInt64(truncatingIfNeeded: bs) &* 0x9E37_79B9_7F4A_7C15 ^ UInt64(truncatingIfNeeded: bs >> 64)
                          ^ UInt64(x) &* 0xC2B2_AE3D_27D4_EB4F)
            }
        }
        struct Node { let key: Key; let patch: UInt128 }
        let w = UInt128(g.cols)
        /// The banana at tile `t`: flood the floor it can walk over and drop the hearts lying on it.
        func node(_ t: Int, _ bs: UInt128, _ hs: Int) -> Node {
            let free = open & ~bs & ~gaze(bs)
            var patch = g.bit(t)
            while true {
                let grown = (patch | patch << 1 | patch >> 1 | patch << w | patch >> w) & free
                if grown == patch { break }
                patch = grown
            }
            var left = hs
            for i in heartCells.indices where patch & g.bit(heartCells[i]) != 0 { left &= ~(1 << i) }
            return Node(key: Key(bs: bs, x: patch.trailingZeroBitCount | left << 8), patch: patch)
        }
        let start = node(g.player, g.blocks, heartTiles.count - 1)
        var seen: Set<Key> = [start.key]
        var layer = [start], nextLayer: [Node] = []
        var runs = 0, expanded = 0
        while !layer.isEmpty {
            for s in layer {
                expanded += 1
                if expanded > 50_000 { return nil }
                let hs = s.key.x >> 8
                if hs == 0 && s.patch & g.bit(g.exit) != 0 { return runs }
                let stop = g.walls | g.medusas | heartTiles[hs] | g.bit(g.exit)
                for step in [1, -1, g.cols, -g.cols] {
                    // Patch tiles with a block right next to them in this direction.
                    var from = s.patch & (step > 0 ? s.key.bs >> UInt128(step) : s.key.bs << UInt128(-step))
                    while from != 0 {
                        var pl = from.trailingZeroBitCount
                        from &= from - 1
                        var bs = s.key.bs
                        while true {                         // the run: one more tile each pass
                            let blk = pl + step, dest = blk + step
                            if (stop | bs) & g.bit(dest) != 0 { break }
                            bs = (bs & ~g.bit(blk)) | g.bit(dest)
                            pl = blk
                            if gaze(bs) & g.bit(pl) != 0 { break }   // never step into a gaze
                            let n = node(pl, bs, hs)
                            if seen.insert(n.key).inserted { nextLayer.append(n) }
                        }
                    }
                }
            }
            layer = nextLayer; nextLayer = []; runs += 1
        }
        return nil
    }

    private nonisolated static func fallback() -> LoloPuzzle {
        // A safe corridor: player → heart → exit, no statue in any line of sight. Always winnable.
        let rows = 3, cols = 6
        var walls = Set<LCell>()
        for r in 0..<rows { walls.insert(LCell(r: r, c: 0)); walls.insert(LCell(r: r, c: cols - 1)) }
        for c in 0..<cols { walls.insert(LCell(r: 0, c: c)); walls.insert(LCell(r: rows - 1, c: c)) }
        return LoloPuzzle(rows: rows, cols: cols, walls: walls,
                          medusas: [], blocks: [],
                          hearts: [LCell(r: 1, c: 2)], player: LCell(r: 1, c: 1), exit: LCell(r: 1, c: 4))
    }
}

// MARK: - Adventures of Lolo art

/// The NES room: sandstone blocks round the edge, a brown brick floor, tan boulders, Heart Framers,
/// green Emerald Framers, stone Medusa heads and a stone door. The hero is the banana, drawn with
/// Lolo's big eyes and red feet.
private enum LoloArt {
    static let sand = Color(red: 0.9, green: 0.73, blue: 0.49)
    static let sandLight = Color(red: 0.99, green: 0.88, blue: 0.67)
    static let sandDark = Color(red: 0.64, green: 0.45, blue: 0.26)
    static let mortar = Color(red: 0.25, green: 0.13, blue: 0.06)
    static let brick = Color(red: 0.5, green: 0.27, blue: 0.14)
    static let gaze = Color(red: 1.0, green: 0.16, blue: 0.12)

    private static func disc(_ p: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }

    /// Two courses of running-bond bricks per cell; offsets follow the global row so rooms tile.
    static func floor(_ ctx: GraphicsContext, _ r: CGRect, row: Int) {
        ctx.fill(Path(r), with: .color(mortar))
        var g = ctx
        g.clip(to: Path(r))
        let h = r.height / 2, bw = r.width / 2
        for k in 0..<2 {
            let y = r.minY + CGFloat(k) * h
            let shift = (row * 2 + k) % 2 == 0 ? 0 : bw / 2
            for i in -1...2 {
                let b = CGRect(x: r.minX + CGFloat(i) * bw + shift, y: y, width: bw, height: h).insetBy(dx: 0.7, dy: 0.7)
                g.fill(Path(roundedRect: b, cornerRadius: 1.2),
                       with: .linearGradient(Gradient(colors: [brick.lit(0.12), brick, brick.shade(0.15)]),
                                             startPoint: CGPoint(x: b.midX, y: b.minY), endPoint: CGPoint(x: b.midX, y: b.maxY)))
                g.fill(Path(CGRect(x: b.minX + 1, y: b.minY, width: b.width - 2, height: max(0.8, h * 0.1))),
                       with: .color(brick.lit(0.3).opacity(0.6)))
            }
        }
    }

    /// A bevelled sandstone block for the room's outer wall.
    static func block(_ ctx: GraphicsContext, _ r: CGRect) {
        let b = r.insetBy(dx: 0.6, dy: 0.6)
        let e = b.width * 0.16
        ctx.fill(Path(roundedRect: b, cornerRadius: b.width * 0.12), with: .color(sand))
        var top = Path()
        top.move(to: CGPoint(x: b.minX, y: b.maxY)); top.addLine(to: CGPoint(x: b.minX, y: b.minY))
        top.addLine(to: CGPoint(x: b.maxX, y: b.minY)); top.addLine(to: CGPoint(x: b.maxX - e, y: b.minY + e))
        top.addLine(to: CGPoint(x: b.minX + e, y: b.minY + e)); top.addLine(to: CGPoint(x: b.minX + e, y: b.maxY - e))
        top.closeSubpath()
        var g = ctx
        g.clip(to: Path(roundedRect: b, cornerRadius: b.width * 0.12))
        g.fill(top, with: .color(sandLight))
        var bottom = Path()
        bottom.move(to: CGPoint(x: b.maxX, y: b.minY)); bottom.addLine(to: CGPoint(x: b.maxX, y: b.maxY))
        bottom.addLine(to: CGPoint(x: b.minX, y: b.maxY)); bottom.addLine(to: CGPoint(x: b.minX + e, y: b.maxY - e))
        bottom.addLine(to: CGPoint(x: b.maxX - e, y: b.maxY - e)); bottom.addLine(to: CGPoint(x: b.maxX - e, y: b.minY + e))
        bottom.closeSubpath()
        g.fill(bottom, with: .color(sandDark))
        // A couple of pits for the worn stone look.
        g.fill(disc(CGPoint(x: b.minX + b.width * 0.62, y: b.minY + b.height * 0.42), b.width * 0.05), with: .color(sandDark.opacity(0.7)))
        g.fill(disc(CGPoint(x: b.minX + b.width * 0.36, y: b.minY + b.height * 0.64), b.width * 0.035), with: .color(sandDark.opacity(0.6)))
        ctx.stroke(Path(roundedRect: b, cornerRadius: b.width * 0.12), with: .color(mortar), lineWidth: max(1, r.width * 0.035))
    }

    /// A lumpy tan boulder (interior walls block Medusa's gaze, like Lolo's rocks).
    static func rock(_ ctx: GraphicsContext, _ r: CGRect) {
        let s = r.width
        ctx.fill(Path(ellipseIn: CGRect(x: r.minX + s * 0.1, y: r.minY + s * 0.62, width: s * 0.84, height: s * 0.3)),
                 with: .color(.black.opacity(0.3)))
        for (x, y, rr) in [(0.33, 0.4, 0.25), (0.66, 0.42, 0.24), (0.5, 0.63, 0.3)] as [(CGFloat, CGFloat, CGFloat)] {
            let c = CGPoint(x: r.minX + s * x, y: r.minY + s * y)
            let p = disc(c, s * rr)
            ctx.fill(p, with: .radialGradient(Gradient(colors: [sandLight, sand, sandDark]),
                                              center: CGPoint(x: c.x - s * rr * 0.35, y: c.y - s * rr * 0.4),
                                              startRadius: 0, endRadius: s * rr * 1.25))
            ctx.stroke(p, with: .color(mortar), lineWidth: max(1, s * 0.035))
        }
    }

    static func heartPath(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: r.midX, y: r.minY + h * 0.26))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.3),
                   control1: CGPoint(x: r.midX - w * 0.1, y: r.minY - h * 0.08), control2: CGPoint(x: r.minX, y: r.minY - h * 0.02))
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY),
                   control1: CGPoint(x: r.minX, y: r.minY + h * 0.62), control2: CGPoint(x: r.midX - w * 0.22, y: r.minY + h * 0.8))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + h * 0.3),
                   control1: CGPoint(x: r.midX + w * 0.22, y: r.minY + h * 0.8), control2: CGPoint(x: r.maxX, y: r.minY + h * 0.62))
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY + h * 0.26),
                   control1: CGPoint(x: r.maxX, y: r.minY - h * 0.02), control2: CGPoint(x: r.midX + w * 0.1, y: r.minY - h * 0.08))
        p.closeSubpath()
        return p
    }

    /// A Heart Framer: a pink heart set in a white frame.
    static func heartFramer(_ ctx: GraphicsContext, _ r: CGRect) {
        let s = r.width
        let frame = r.insetBy(dx: s * 0.04, dy: s * 0.04)
        ctx.fill(Path(roundedRect: frame.offsetBy(dx: 0, dy: s * 0.05), cornerRadius: s * 0.16), with: .color(.black.opacity(0.3)))
        ctx.fill(Path(roundedRect: frame, cornerRadius: s * 0.16),
                 with: .linearGradient(Gradient(colors: [.white, Color(red: 0.93, green: 0.86, blue: 0.9)]),
                                       startPoint: CGPoint(x: frame.midX, y: frame.minY), endPoint: CGPoint(x: frame.midX, y: frame.maxY)))
        ctx.stroke(Path(roundedRect: frame, cornerRadius: s * 0.16), with: .color(Color(red: 0.55, green: 0.3, blue: 0.4)), lineWidth: max(1, s * 0.05))
        let inner = frame.insetBy(dx: s * 0.12, dy: s * 0.12)
        ctx.fill(Path(roundedRect: inner, cornerRadius: s * 0.1), with: .color(Color(red: 1.0, green: 0.84, blue: 0.9)))
        let heart = heartPath(in: inner.insetBy(dx: s * 0.05, dy: s * 0.07))
        ctx.fill(heart, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.42, blue: 0.56), Color(red: 0.86, green: 0.1, blue: 0.3)]),
                                              startPoint: CGPoint(x: inner.midX, y: inner.minY), endPoint: CGPoint(x: inner.midX, y: inner.maxY)))
        ctx.stroke(heart, with: .color(Color(red: 0.5, green: 0.05, blue: 0.15)), lineWidth: max(0.8, s * 0.035))
        ctx.fill(disc(CGPoint(x: inner.minX + inner.width * 0.32, y: inner.minY + inner.height * 0.34), s * 0.05), with: .color(.white.opacity(0.85)))
    }

    /// An Emerald Framer: the green gem block you push.
    static func emeraldFramer(_ ctx: GraphicsContext, _ r: CGRect) {
        let s = r.width
        let b = r.insetBy(dx: s * 0.07, dy: s * 0.07)
        let k = b.width * 0.26
        func oct(_ q: CGRect, _ cut: CGFloat) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: q.minX + cut, y: q.minY)); p.addLine(to: CGPoint(x: q.maxX - cut, y: q.minY))
            p.addLine(to: CGPoint(x: q.maxX, y: q.minY + cut)); p.addLine(to: CGPoint(x: q.maxX, y: q.maxY - cut))
            p.addLine(to: CGPoint(x: q.maxX - cut, y: q.maxY)); p.addLine(to: CGPoint(x: q.minX + cut, y: q.maxY))
            p.addLine(to: CGPoint(x: q.minX, y: q.maxY - cut)); p.addLine(to: CGPoint(x: q.minX, y: q.minY + cut))
            p.closeSubpath()
            return p
        }
        ctx.fill(oct(b.offsetBy(dx: 0, dy: s * 0.06), k), with: .color(.black.opacity(0.35)))
        ctx.fill(oct(b, k), with: .linearGradient(Gradient(colors: [Color(red: 0.55, green: 0.95, blue: 0.55), Color(red: 0.1, green: 0.5, blue: 0.22)]),
                                                  startPoint: CGPoint(x: b.minX, y: b.minY), endPoint: CGPoint(x: b.maxX, y: b.maxY)))
        let face = b.insetBy(dx: b.width * 0.2, dy: b.width * 0.2)
        ctx.fill(oct(face, k * 0.5), with: .linearGradient(Gradient(colors: [Color(red: 0.3, green: 0.8, blue: 0.4), Color(red: 0.16, green: 0.6, blue: 0.3)]),
                                                           startPoint: CGPoint(x: face.minX, y: face.minY), endPoint: CGPoint(x: face.maxX, y: face.maxY)))
        ctx.stroke(oct(face, k * 0.5), with: .color(Color(red: 0.04, green: 0.3, blue: 0.12).opacity(0.7)), lineWidth: max(0.8, s * 0.025))
        ctx.stroke(oct(b, k), with: .color(Color(red: 0.03, green: 0.25, blue: 0.1)), lineWidth: max(1, s * 0.04))
        ctx.fill(disc(CGPoint(x: face.minX + face.width * 0.3, y: face.minY + face.height * 0.3), s * 0.06), with: .color(.white.opacity(0.75)))
    }

    /// A stone Medusa head: snake hair, a grey-green face and glowing red eyes.
    static func medusa(_ ctx: GraphicsContext, _ r: CGRect) {
        let s = r.width
        let c = CGPoint(x: r.midX, y: r.midY + s * 0.06)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.36, y: c.y + s * 0.18, width: s * 0.72, height: s * 0.2)), with: .color(.black.opacity(0.35)))
        let snake = Color(red: 0.24, green: 0.56, blue: 0.3)
        for (i, a) in [-165.0, -130.0, -90.0, -50.0, -15.0].enumerated() {
            let rad = a * .pi / 180
            let base = CGPoint(x: c.x + CGFloat(cos(rad)) * s * 0.24, y: c.y - s * 0.02 + CGFloat(sin(rad)) * s * 0.24)
            let tip = CGPoint(x: c.x + CGFloat(cos(rad)) * s * 0.44, y: c.y - s * 0.02 + CGFloat(sin(rad)) * s * 0.44)
            let wob = (i % 2 == 0 ? 1.0 : -1.0) * s * 0.08
            var p = Path()
            p.move(to: base)
            p.addQuadCurve(to: tip, control: CGPoint(x: (base.x + tip.x) / 2 + CGFloat(-sin(rad)) * wob,
                                                     y: (base.y + tip.y) / 2 + CGFloat(cos(rad)) * wob))
            ctx.stroke(p, with: .color(Color(red: 0.06, green: 0.2, blue: 0.08)), style: StrokeStyle(lineWidth: s * 0.11, lineCap: .round))
            ctx.stroke(p, with: .color(snake), style: StrokeStyle(lineWidth: s * 0.065, lineCap: .round))
            ctx.fill(disc(tip, s * 0.06), with: .color(snake.lit(0.15)))
            ctx.stroke(disc(tip, s * 0.06), with: .color(Color(red: 0.06, green: 0.2, blue: 0.08)), lineWidth: max(0.8, s * 0.02))
        }
        let face = Path(ellipseIn: CGRect(x: c.x - s * 0.29, y: c.y - s * 0.3, width: s * 0.58, height: s * 0.56))
        ctx.fill(face, with: .radialGradient(Gradient(colors: [Color(red: 0.74, green: 0.8, blue: 0.7), Color(red: 0.5, green: 0.58, blue: 0.5),
                                                               Color(red: 0.32, green: 0.38, blue: 0.32)]),
                                             center: CGPoint(x: c.x - s * 0.08, y: c.y - s * 0.12), startRadius: 0, endRadius: s * 0.4))
        ctx.stroke(face, with: .color(Color(red: 0.14, green: 0.18, blue: 0.14)), lineWidth: max(1, s * 0.04))
        for sx: CGFloat in [-1, 1] {
            let e = CGPoint(x: c.x + sx * s * 0.11, y: c.y - s * 0.05)
            ctx.fill(disc(e, s * 0.1), with: .radialGradient(Gradient(colors: [gaze.opacity(0.7), gaze.opacity(0)]),
                                                             center: e, startRadius: 0, endRadius: s * 0.1))
            ctx.fill(Path(ellipseIn: CGRect(x: e.x - s * 0.06, y: e.y - s * 0.04, width: s * 0.12, height: s * 0.08)),
                     with: .color(Color(red: 1, green: 0.95, blue: 0.6)))
            ctx.fill(disc(e, s * 0.028), with: .color(Color(red: 0.9, green: 0.05, blue: 0.05)))
            var brow = Path()
            brow.move(to: CGPoint(x: e.x - sx * s * 0.08, y: e.y - s * 0.09))
            brow.addLine(to: CGPoint(x: e.x + sx * s * 0.06, y: e.y - s * 0.05))
            ctx.stroke(brow, with: .color(Color(red: 0.14, green: 0.18, blue: 0.14)), style: StrokeStyle(lineWidth: max(1, s * 0.04), lineCap: .round))
        }
        var mouth = Path()
        mouth.move(to: CGPoint(x: c.x - s * 0.08, y: c.y + s * 0.14))
        mouth.addQuadCurve(to: CGPoint(x: c.x + s * 0.08, y: c.y + s * 0.14), control: CGPoint(x: c.x, y: c.y + s * 0.08))
        ctx.stroke(mouth, with: .color(Color(red: 0.14, green: 0.18, blue: 0.14)), style: StrokeStyle(lineWidth: max(1, s * 0.035), lineCap: .round))
    }

    /// The exit: a stone archway, barred shut until every heart is collected, then open and glowing.
    static func door(_ ctx: GraphicsContext, _ r: CGRect, open: Bool) {
        let s = r.width
        let arch = CGRect(x: r.minX + s * 0.1, y: r.minY + s * 0.06, width: s * 0.8, height: s * 0.9)
        func archPath(_ q: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: q.minX, y: q.maxY))
            p.addLine(to: CGPoint(x: q.minX, y: q.minY + q.width / 2))
            p.addArc(center: CGPoint(x: q.midX, y: q.minY + q.width / 2), radius: q.width / 2,
                     startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            p.addLine(to: CGPoint(x: q.maxX, y: q.maxY))
            p.closeSubpath()
            return p
        }
        ctx.fill(archPath(arch), with: .linearGradient(Gradient(colors: [sandLight, sandDark]),
                                                       startPoint: CGPoint(x: arch.minX, y: arch.minY), endPoint: CGPoint(x: arch.maxX, y: arch.maxY)))
        ctx.stroke(archPath(arch), with: .color(mortar), lineWidth: max(1, s * 0.035))
        let hole = arch.insetBy(dx: s * 0.1, dy: 0).offsetBy(dx: 0, dy: s * 0.05)
        let inside = CGRect(x: hole.minX, y: hole.minY, width: hole.width, height: hole.height - s * 0.05)
        if open {
            ctx.fill(archPath(inside), with: .color(Color(red: 0.06, green: 0.03, blue: 0.02)))
            ctx.fill(archPath(inside), with: .radialGradient(Gradient(colors: [BananaTheme.banana.opacity(0.95), BananaTheme.banana.opacity(0)]),
                                                             center: CGPoint(x: inside.midX, y: inside.maxY - s * 0.1),
                                                             startRadius: 0, endRadius: s * 0.5))
        } else {
            ctx.fill(archPath(inside), with: .linearGradient(Gradient(colors: [Color(red: 0.55, green: 0.33, blue: 0.16), Color(red: 0.36, green: 0.2, blue: 0.09)]),
                                                             startPoint: CGPoint(x: inside.minX, y: inside.minY), endPoint: CGPoint(x: inside.maxX, y: inside.maxY)))
            var planks = Path()
            for k in 1...2 {
                let x = inside.minX + inside.width * CGFloat(k) / 3
                planks.move(to: CGPoint(x: x, y: inside.minY + s * 0.04)); planks.addLine(to: CGPoint(x: x, y: inside.maxY))
            }
            ctx.stroke(planks, with: .color(.black.opacity(0.35)), lineWidth: max(0.8, s * 0.025))
            for fy: CGFloat in [0.42, 0.78] {
                ctx.fill(Path(CGRect(x: inside.minX, y: inside.minY + inside.height * fy - s * 0.03, width: inside.width, height: s * 0.06)),
                         with: .color(Color(white: 0.3)))
            }
            ctx.fill(disc(CGPoint(x: inside.midX, y: inside.minY + inside.height * 0.6), s * 0.045), with: .color(BananaTheme.banana))
        }
    }

    /// The banana hero in Lolo's style: big round eyes and little red feet. Faces right unless flipped.
    static func hero(_ ctx: GraphicsContext, _ r: CGRect, facingLeft: Bool, stone: Bool) {
        let s = r.width
        var g = ctx
        g.translateBy(x: r.midX, y: r.midY)
        if facingLeft { g.scaleBy(x: -1, y: 1) }
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        let peel = stone ? Color(white: 0.62) : Color(red: 1.0, green: 0.86, blue: 0.2)
        let peelDark = stone ? Color(white: 0.4) : Color(red: 0.86, green: 0.62, blue: 0.08)
        let ink = Color(red: 0.25, green: 0.15, blue: 0.04)
        let feet = stone ? Color(white: 0.5) : Color(red: 0.88, green: 0.18, blue: 0.14)

        g.fill(Path(ellipseIn: CGRect(x: -s * 0.3, y: s * 0.3, width: s * 0.6, height: s * 0.14)), with: .color(.black.opacity(0.35)))
        for fx: CGFloat in [-0.17, 0.09] {
            let f = CGRect(x: fx * s, y: s * 0.27, width: s * 0.2, height: s * 0.12)
            g.fill(Path(ellipseIn: f), with: .color(feet))
            g.stroke(Path(ellipseIn: f), with: .color(ink), lineWidth: max(1, s * 0.03))
        }
        // The curved body: a crescent leaning back, bulging towards the facing side.
        var body = Path()
        body.move(to: P(-0.06, -0.42))
        body.addQuadCurve(to: P(-0.08, 0.3), control: P(-0.42, -0.02))
        body.addQuadCurve(to: P(-0.06, -0.42), control: P(0.46, 0.04))
        body.closeSubpath()
        g.fill(body, with: .linearGradient(Gradient(colors: [peel.lit(0.35), peel, peelDark]),
                                           startPoint: P(-0.3, -0.3), endPoint: P(0.3, 0.3)))
        var ridge = Path()
        ridge.move(to: P(-0.05, -0.36))
        ridge.addQuadCurve(to: P(-0.06, 0.24), control: P(0.2, 0.0))
        g.stroke(ridge, with: .color(peelDark.opacity(0.55)), lineWidth: max(1, s * 0.03))
        g.stroke(body, with: .color(ink), lineWidth: max(1, s * 0.04))
        // Stem and tip.
        g.fill(Path(roundedRect: CGRect(x: -s * 0.1, y: -s * 0.5, width: s * 0.09, height: s * 0.12), cornerRadius: s * 0.02),
               with: .color(stone ? Color(white: 0.35) : Color(red: 0.42, green: 0.28, blue: 0.1)))
        g.fill(disc(P(-0.075, 0.29), s * 0.035), with: .color(ink))
        // Lolo's eyes: two big white ovals, pupils looking ahead.
        for (ex, ey) in [(-0.1, -0.1), (0.07, -0.08)] as [(CGFloat, CGFloat)] {
            let e = CGRect(x: ex * s - s * 0.085, y: ey * s - s * 0.12, width: s * 0.17, height: s * 0.22)
            g.fill(Path(ellipseIn: e), with: .color(.white))
            g.stroke(Path(ellipseIn: e), with: .color(ink), lineWidth: max(1, s * 0.03))
            g.fill(Path(ellipseIn: CGRect(x: e.midX - s * 0.005, y: e.midY - s * 0.06, width: s * 0.07, height: s * 0.1)),
                   with: .color(stone ? Color(white: 0.3) : .black))
        }
    }
}

/// The static room: brick floor, sandstone outer wall and boulders. Equatable, so the clock never
/// redraws it — only a new room (or a new size) does.
private struct LoloRoom: View, Equatable {
    let rows: Int, cols: Int
    let walls: Set<LCell>
    let cell: CGFloat
    let origin: CGPoint

    var body: some View {
        Canvas { ctx, _ in
            guard cell > 0 else { return }
            for r in 0..<rows {
                for c in 0..<cols {
                    let rect = CGRect(x: origin.x + CGFloat(c) * cell, y: origin.y + CGFloat(r) * cell, width: cell, height: cell)
                    let here = LCell(r: r, c: c)
                    if !walls.contains(here) {
                        LoloArt.floor(ctx, rect, row: r)
                    } else if r == 0 || c == 0 || r == rows - 1 || c == cols - 1 {
                        LoloArt.block(ctx, rect)
                    } else {
                        LoloArt.floor(ctx, rect, row: r)
                        LoloArt.rock(ctx, rect)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The plus-shaped base of an NES d-pad.
private struct NESCross: Shape {
    func path(in r: CGRect) -> Path {
        let a = r.width / 3
        var p = Path()
        p.addRoundedRect(in: CGRect(x: r.minX + a, y: r.minY, width: a, height: r.height), cornerSize: CGSize(width: a * 0.2, height: a * 0.2))
        p.addRoundedRect(in: CGRect(x: r.minX, y: r.minY + a, width: r.width, height: a), cornerSize: CGSize(width: a * 0.2, height: a * 0.2))
        return p
    }
}

/// A d-pad arm: grey arrow on black, banana-lit while pressed (or when the demo presses it).
private struct DPadArmStyle: ButtonStyle {
    let lit: Bool
    let radius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let on = lit || configuration.isPressed
        configuration.label
            .foregroundStyle(on ? .black : Color(white: 0.55))
            .background(RoundedRectangle(cornerRadius: radius).fill(on ? BananaTheme.banana : .clear))
            .scaleEffect(on ? 0.92 : 1)
            .animation(.easeOut(duration: 0.08), value: on)
    }
}
