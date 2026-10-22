//
//  CratePushGame.swift
//  A Banana Game
//
//  Brain — a Sokoban. Nudge the banana with the d-pad and SHOVE every crate onto a green
//  target mark. You can only push (never pull), so a crate wedged into a corner is lost — plan
//  before you shove. Park every crate before the clock runs out or you fail back to level 1.
//
//  Boards are generated fresh and then solved with a PUSH-based BFS (player movement between
//  pushes is free reachability, so states collapse and even deep boards verify in-budget): a
//  candidate is only dealt if it's solvable AND needs enough pushes to be a real puzzle. If a
//  push wedges a crate into a corner it can never leave, we detect the dead board and fail fast
//  instead of stalling the clock. 7 levels: bigger rooms, more crates, more interior walls and a
//  higher minimum push count, so every level bites and level 7 is brutal. Stone cools with depth.
//
//  Drawn as classic Sokoban: a warehouse of orange brick walls and wooden floorboards, green ✕
//  targets painted on the floor, X-braced wooden crates that light up green-edged once parked, and
//  the banana warehouse keeper in a blue cap, which faces where it walks. The board is an Equatable view
//  (the clock doesn't redraw it); the d-pad keeps its button frames, restyled as chunky steel keys.
//

import SwiftUI

enum CratePushGame {
    static let definition = GameDefinition(
        id: "crate-push",
        title: "Crate Push",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Nudge the banana with the d-pad and shove every crate onto a green target mark.",
                "You can only push, never pull — a crate wedged into a corner is lost.",
                "Plan before you shove.",
                "Park every crate before the clock runs out, or wedge one hopelessly, and you're back to level 1.",
            ],
            bulletsVI: [
                "Đẩy quả chuối bằng d-pad và đưa mọi thùng lên dấu mục tiêu màu xanh.",
                "Bạn chỉ đẩy được, không kéo — một thùng kẹt vào góc là hỏng.",
                "Hãy tính trước khi đẩy.",
                "Đặt hết mọi thùng trước khi hết giờ, hoặc kẹt một thùng vô vọng, sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(CratePushView(level: level, onWin: onWin, onFail: onFail))
        },
        prefetch: { level in CratePushView(level: level, onWin: {}, onFail: {}).prefetchBoard() }
    )
}

private nonisolated struct P: Hashable, Sendable { let r: Int; let c: Int }
private nonisolated struct Puzzle: Sendable {
    let rows: Int; let cols: Int
    let walls: Set<P>; let targets: Set<P>; let crates: Set<P>; let player: P
}

struct CratePushView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void
    @Environment(\.isDemo) private var isDemo

    private var timeLimit: Double { [50, 55, 65, 75, 85, 85, 95][min(level, 7) - 1] }

    // Interior (w,h), crate count, interior walls, and the minimum number of crate PUSHES a
    // board's optimal solution must need to be considered "hard enough" to deal.
    private var params: (iw: Int, ih: Int, crates: Int, walls: Int, minPushes: Int) {
        [ (4, 3, 1, 1, 4),
          (4, 4, 2, 1, 7),
          (5, 4, 2, 2, 10),
          (5, 5, 3, 2, 13),
          (6, 5, 3, 3, 16),
          (6, 5, 4, 4, 20),
          (6, 6, 4, 5, 24) ][min(level, 7) - 1]
    }

    // MARK: Mood ramp
    private var skyTop: Color {
        [Color(red:0.16,green:0.15,blue:0.20), Color(red:0.15,green:0.14,blue:0.20),
         Color(red:0.14,green:0.13,blue:0.20), Color(red:0.13,green:0.12,blue:0.19),
         Color(red:0.12,green:0.10,blue:0.18), Color(red:0.10,green:0.08,blue:0.16),
         Color(red:0.08,green:0.06,blue:0.14)][min(level,7)-1]
    }
    private var skyBottom: Color {
        [Color(red:0.10,green:0.09,blue:0.14), Color(red:0.09,green:0.08,blue:0.13),
         Color(red:0.09,green:0.07,blue:0.13), Color(red:0.08,green:0.06,blue:0.12),
         Color(red:0.07,green:0.05,blue:0.11), Color(red:0.06,green:0.04,blue:0.10),
         Color(red:0.05,green:0.03,blue:0.09)][min(level,7)-1]
    }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var rows = 0
    @State private var colsN = 0
    @State private var walls: Set<P> = []
    @State private var targets: Set<P> = []
    @State private var crates: Set<P> = []
    @State private var player = P(r: 0, c: 0)
    @State private var facing = 1
    @State private var timeLeft = 0.0
    @State private var shakeTick = 0
    @State private var loopTask: Task<Void, Never>?
    @State private var ready = false
    @State private var demoKey: String? = nil     // demo: d-pad arrow being pressed

    var body: some View {
        Group {
            if ready {
                gameBody
            } else {
                BrainstormingView(skyTop: skyTop, skyBottom: skyBottom)
            }
        }
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
    }

    private var gameBody: some View {
        VStack(spacing: isDemo ? 4 : 8) {
            HStack(spacing: 8) {
                CPArt.crateIcon.frame(width: isDemo ? 16 : 20, height: isDemo ? 16 : 20)
                Text("\(crates.subtracting(targets).count)")
                    .font(.system(size: isDemo ? 15 : 20, weight: .black, design: .rounded))
                    .foregroundStyle(BananaTheme.banana)
                    .monospacedDigit()
            }
            .padding(.top, isDemo ? 6 : 0)
            if !isDemo { timeBar.frame(height: 5).padding(.horizontal, 60) }

            GeometryReader { geo in
                CPBoard(size: geo.size, rows: rows, cols: colsN, walls: walls, targets: targets, crates: crates,
                        player: player, facing: facing)
                    .equatable()
                    .screenShake(shakeTick, amount: 4)
            }

            dpad
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CPArt.backdrop)
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
    }

    private var dpad: some View {
        VStack(spacing: isDemo ? 4 : 8) {
            arrow("chevron.up", 0, -1)
            HStack(spacing: isDemo ? 4 : 8) {
                arrow("chevron.left", -1, 0)
                arrow("chevron.down", 0, 1)
                arrow("chevron.right", 1, 0)
            }
        }
        .padding(.bottom, isDemo ? 6 : 8)
    }

    private func arrow(_ icon: String, _ dc: Int, _ dr: Int) -> some View {
        let pressed = isDemo && demoKey == icon
        return Button { move(dc: dc, dr: dr) } label: {
            Image(systemName: icon)
                .font(.system(size: isDemo ? 18 : 22, weight: .heavy))
                .foregroundStyle(pressed ? .black : .white)
                .frame(width: isDemo ? 50 : 66, height: isDemo ? 34 : 52)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(pressed ? AnyShapeStyle(BananaTheme.banana)
                              : AnyShapeStyle(LinearGradient(colors: [Color(white: 0.42), Color(white: 0.24)], startPoint: .top, endPoint: .bottom)))
                )
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.black.opacity(0.55), lineWidth: 2))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(pressed ? 0.9 : 0.22), lineWidth: 1).padding(2))
                .scaleEffect(pressed ? 0.9 : 1)
        }
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(frac < 0.3 ? Color(red: 0.95, green: 0.3, blue: 0.25) : BananaTheme.banana)
                    .frame(width: geo.size.width * frac)
            }
        }
    }

    // MARK: Input
    private func move(dc: Int, dr: Int) {
        guard phase == .play else { return }
        if dc > 0 { facing = 1 } else if dc < 0 { facing = -1 }
        let dest = P(r: player.r + dr, c: player.c + dc)
        if walls.contains(dest) { return }
        if crates.contains(dest) {
            let beyond = P(r: dest.r + dr, c: dest.c + dc)
            if walls.contains(beyond) || crates.contains(beyond) { return }
            crates.remove(dest); crates.insert(beyond)
            player = dest
            SoundManager.shared.tap(); Haptics.tap()
            if targets.contains(beyond) { shakeTick += 1 }
            if crates == targets { win() }
            else if isDeadlocked() { deadlock() }
        } else {
            player = dest
            SoundManager.shared.tap()
        }
    }

    // MARK: - Flow
    /// Hands this level's board build to `BoardCache` so it can run during the countdown.
    func prefetchBoard() {
        let p = params
        BoardCache.prefetch(boardKey) { Self.makePuzzle(p) }
    }
    private var boardKey: String { BoardCache.key("crate-push", level: level) }

    private func run() async {
        // Build (generate + verify) off the main actor so the countdown never hitches, then
        // commit and start the clock. While it builds we show the "brainstorming" banana.
        let p = params
        let t0 = Date()
        let puzzle = await BoardCache.take(boardKey) { Self.makePuzzle(p) }
        guard !Task.isCancelled else { return }
        await BoardCache.holdBrainstorm(since: t0, minimum: 0.7)
        guard !Task.isCancelled else { return }
        commit(puzzle)
        ready = true
        timeLeft = timeLimit
        phase = .play
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
    // A fixed level-1 room (4×3 floor, one pillar, one crate) that needs the level's minimum of 4
    // pushes — checked offline: push-optimal = 4, move-optimal = 12. The pillar above the crate
    // rules out the direct "push it down" line, and pushing it straight left strands the banana
    // (it can never get behind it again), so the solution loops round: shove right, down, then left
    // twice onto the pad. Played through the real `move` with each d-pad arrow lighting up.
    //   # # # # # #
    //   # . # . . #
    //   # @ C . . #
    //   # T . . . #
    //   # # # # # #
    private static let demoMoves: [(icon: String, dc: Int, dr: Int)] = {
        let key: [Character: (String, Int, Int)] = [
            "U": ("chevron.up", 0, -1), "D": ("chevron.down", 0, 1),
            "L": ("chevron.left", -1, 0), "R": ("chevron.right", 1, 0)
        ]
        return "RDRRUULDRDLL".map { key[$0]! }.map { (icon: $0.0, dc: $0.1, dr: $0.2) }
    }()

    private static var demoPuzzle: Puzzle {
        let rows = 5, cols = 6
        var walls: Set<P> = [P(r: 1, c: 2)]
        for r in 0..<rows { walls.insert(P(r: r, c: 0)); walls.insert(P(r: r, c: cols - 1)) }
        for c in 0..<cols { walls.insert(P(r: 0, c: c)); walls.insert(P(r: rows - 1, c: c)) }
        return Puzzle(rows: rows, cols: cols, walls: walls,
                      targets: [P(r: 3, c: 1)], crates: [P(r: 2, c: 2)], player: P(r: 2, c: 1))
    }

    private func runDemo() async {
        while !Task.isCancelled {
            commit(Self.demoPuzzle)
            facing = 1; demoKey = nil
            timeLeft = timeLimit
            phase = .play
            ready = true
            try? await Task.sleep(for: .seconds(0.8))
            for m in Self.demoMoves {
                guard !Task.isCancelled else { return }
                demoKey = m.icon
                move(dc: m.dc, dr: m.dr)
                try? await Task.sleep(for: .seconds(0.16))
                demoKey = nil
                try? await Task.sleep(for: .seconds(0.16))
            }
            // Crate parked → the real win() ran (onWin is a no-op). Hold, then loop.
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    private func commit(_ p: Puzzle) {
        rows = p.rows; colsN = p.cols
        walls = p.walls; targets = p.targets; crates = p.crates; player = p.player
    }

    /// True once a crate that isn't on a target is jammed into a corner (a wall on two
    /// perpendicular sides). Push-only means such a crate can never move again → dead board.
    private func isDeadlocked() -> Bool {
        for cr in crates where !targets.contains(cr) {
            let up = walls.contains(P(r: cr.r - 1, c: cr.c))
            let down = walls.contains(P(r: cr.r + 1, c: cr.c))
            let left = walls.contains(P(r: cr.r, c: cr.c - 1))
            let right = walls.contains(P(r: cr.r, c: cr.c + 1))
            if (up || down) && (left || right) { return true }
        }
        return false
    }

    /// Fail fast on a wedged crate: freeze input, thump, then drop back to level 1.
    private func deadlock() {
        guard phase == .play else { return }
        phase = .done
        loopTask?.cancel()
        SoundManager.shared.error(); Haptics.warning()
        shakeTick += 1
        Task { try? await Task.sleep(for: .seconds(0.4)); onFail() }
    }

    // MARK: - Generation (pure / off-main)

    /// Try many random rooms; deal the first that needs at least `minPushes` pushes, else the
    /// hardest solvable one we saw, else a tiny hand-built board. Every path is guaranteed solvable.
    private nonisolated static func makePuzzle(_ p: (iw: Int, ih: Int, crates: Int, walls: Int, minPushes: Int)) -> Puzzle {
        var best: Puzzle?
        var bestPushes = -1
        for _ in 0..<160 {
            guard let cand = generate(p) else { continue }
            if let pushes = solvePushes(cand) {
                if pushes >= p.minPushes { return cand }
                if pushes > bestPushes { bestPushes = pushes; best = cand }
            }
        }
        return best ?? fallback()
    }

    /// Random enclosed room with interior walls, crates, targets and a player.
    private nonisolated static func generate(_ p: (iw: Int, ih: Int, crates: Int, walls: Int, minPushes: Int)) -> Puzzle? {
        let rows = p.ih + 2, cols = p.iw + 2
        var floor: [P] = []
        for r in 1...p.ih { for c in 1...p.iw { floor.append(P(r: r, c: c)) } }
        floor.shuffle()
        var idx = 0
        func take(_ n: Int) -> [P]? {
            guard idx + n <= floor.count else { return nil }
            defer { idx += n }
            return Array(floor[idx..<idx+n])
        }
        // Border walls.
        var walls: Set<P> = []
        for r in 0..<rows { walls.insert(P(r: r, c: 0)); walls.insert(P(r: r, c: cols - 1)) }
        for c in 0..<cols { walls.insert(P(r: 0, c: c)); walls.insert(P(r: rows - 1, c: c)) }
        guard let interiorWalls = take(p.walls) else { return nil }
        walls.formUnion(interiorWalls)
        guard let crateCells = take(p.crates) else { return nil }
        guard let targetCells = take(p.crates) else { return nil }
        guard let playerCells = take(1), let player = playerCells.first else { return nil }
        let crates = Set(crateCells), targets = Set(targetCells)
        // Reject a board that's already (partly) solved into a freebie.
        if crates == targets { return nil }
        return Puzzle(rows: rows, cols: cols, walls: walls, targets: targets, crates: crates, player: player)
    }

    private nonisolated static let dirs = [(0, -1), (0, 1), (-1, 0), (1, 0)]

    /// Push-based BFS: a state is (crate layout + which region the player is in). Player walking
    /// between pushes is free, so the space is tiny next to move-BFS and deep boards verify well
    /// within the cap. Returns the optimal number of pushes, or nil if unsolved in-budget.
    /// Cells are bits of a UInt64 (boards are at most 8×8) so flood fills, keys and pushes are a
    /// handful of integer ops instead of Set<P> churn — same search, ~30× faster.
    private nonisolated static func solvePushes(_ p: Puzzle) -> Int? {
        if p.crates == p.targets { return 0 }
        let R = p.rows, C = p.cols
        guard R * C <= 64 else { return nil }
        @inline(__always) func bit(_ r: Int, _ c: Int) -> UInt64 { 1 << UInt64(r * C + c) }
        func mask(_ s: Set<P>) -> UInt64 { s.reduce(0) { $0 | bit($1.r, $1.c) } }
        let walls = mask(p.walls), targets = mask(p.targets)
        let full: UInt64 = R * C == 64 ? .max : (1 << UInt64(R * C)) - 1
        var notLeft: UInt64 = 0, notRight: UInt64 = 0
        for r in 0..<R { for c in 0..<C { if c > 0 { notLeft |= bit(r, c) }; if c < C - 1 { notRight |= bit(r, c) } } }

        /// Cells the player can walk to from `start` without crossing walls or crates.
        func region(from start: UInt64, crates: UInt64) -> UInt64 {
            let free = full & ~(walls | crates)
            var reg = start
            while true {
                let grown = reg
                    | ((reg & notRight) << 1) | ((reg & notLeft) >> 1)
                    | ((reg << UInt64(C)) & full) | (reg >> UInt64(C))
                let next = (grown & free) | start
                if next == reg { return reg }
                reg = next
            }
        }
        struct Key: Hashable { let crates: UInt64; let rep: Int }

        let startRegion = region(from: bit(p.player.r, p.player.c), crates: mask(p.crates))
        var seen: Set<Key> = [Key(crates: mask(p.crates), rep: startRegion.trailingZeroBitCount)]
        var queue: [(UInt64, UInt64, Int)] = [(mask(p.crates), startRegion, 0)]   // crates, region, pushes
        var head = 0, expanded = 0
        while head < queue.count {
            let (cs, reg, d) = queue[head]; head += 1
            expanded += 1
            if expanded > 150_000 { return nil }
            var boxes = cs
            while boxes != 0 {
                let idx = boxes.trailingZeroBitCount
                boxes &= boxes - 1
                let br = idx / C, bc = idx % C
                for (dr, dc) in dirs {
                    let fr = br - dr, fc = bc - dc   // where the player must stand
                    let tr = br + dr, tc = bc + dc   // where the crate would land
                    guard fr >= 0, fr < R, fc >= 0, fc < C, tr >= 0, tr < R, tc >= 0, tc < C else { continue }
                    let from = bit(fr, fc), to = bit(tr, tc)
                    if (walls | cs) & from != 0 || reg & from == 0 { continue }
                    if (walls | cs) & to != 0 { continue }
                    let ncs = (cs & ~bit(br, bc)) | to
                    if ncs == targets { return d + 1 }
                    let nreg = region(from: bit(br, bc), crates: ncs)
                    let k = Key(crates: ncs, rep: nreg.trailingZeroBitCount)
                    if seen.contains(k) { continue }
                    seen.insert(k)
                    queue.append((ncs, nreg, d + 1))
                }
            }
        }
        return nil
    }

    private nonisolated static func fallback() -> Puzzle {
        // Enclosed 5×3 with one crate one push from a target — always solvable.
        let rows = 3, cols = 5
        var walls: Set<P> = []
        for r in 0..<rows { walls.insert(P(r: r, c: 0)); walls.insert(P(r: r, c: cols - 1)) }
        for c in 0..<cols { walls.insert(P(r: 0, c: c)); walls.insert(P(r: rows - 1, c: c)) }
        return Puzzle(rows: rows, cols: cols, walls: walls,
                      targets: [P(r: 1, c: 1)], crates: [P(r: 1, c: 2)], player: P(r: 1, c: 3))
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

// MARK: - Brainstorming (shown while a solver builds a board off-main; reused by other puzzle games)
struct BrainstormingView: View {
    let skyTop: Color
    let skyBottom: Color

    @State private var bananaPos: CGPoint = .zero
    @State private var rotation = 0.0
    @State private var placed = false
    @State private var dots = ""

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                LinearGradient(colors: [skyTop, skyBottom], startPoint: .top, endPoint: .bottom)

                VStack(spacing: 12) {
                    Text(L("I am brainstorming\(dots)", "Đang động não\(dots)"))
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(BananaTheme.banana)
                    Text(L("Even Elon Musk has to think!", "Ngay cả Elon Musk cũng phải suy nghĩ!"))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

                Text("🍌")
                    .font(.system(size: 54))
                    .rotationEffect(.degrees(rotation))
                    .shadow(color: BananaTheme.banana.opacity(0.5), radius: 12)
                    .position(bananaPos)
                    .opacity(placed ? 1 : 0)
            }
            .task { await animate(w: w, h: h) }
        }
    }

    /// The banana darts to random spots — sometimes ducking clean off-screen — at irregular
    /// intervals so it feels unpredictable, while an ellipsis ticks on the headline.
    private func animate(w: CGFloat, h: CGFloat) async {
        bananaPos = CGPoint(x: w * 0.5, y: h * 0.66)
        placed = true

        let dotsTask = Task { @MainActor in
            let seq = ["", ".", "..", "..."]
            var i = 0
            while !Task.isCancelled {
                dots = seq[i % seq.count]; i += 1
                try? await Task.sleep(for: .seconds(0.35))
            }
        }
        defer { dotsTask.cancel() }

        while !Task.isCancelled {
            let duckOut = Double.random(in: 0...1) < 0.4
            let target: CGPoint
            if duckOut {
                switch Int.random(in: 0..<4) {
                case 0:  target = CGPoint(x: -90, y: .random(in: 0...h))
                case 1:  target = CGPoint(x: w + 90, y: .random(in: 0...h))
                case 2:  target = CGPoint(x: .random(in: 0...w), y: -90)
                default: target = CGPoint(x: .random(in: 0...w), y: h + 90)
                }
            } else {
                target = CGPoint(x: .random(in: w * 0.15...w * 0.85),
                                 y: .random(in: h * 0.18...h * 0.82))
            }
            let dur = Double.random(in: 0.22...0.7)
            withAnimation(.easeInOut(duration: dur)) {
                bananaPos = target
                rotation += Double.random(in: -200...200)
            }
            try? await Task.sleep(for: .seconds(dur + Double.random(in: 0.1...0.8)))
        }
    }
}

// MARK: - Warehouse art (classic Sokoban)

/// The room, drawn once per move: brick walls laid in continuous courses, floorboards, painted ✕
/// targets, crates and the keeper. Equatable, so the 20 Hz clock doesn't redraw it.
private struct CPBoard: View, Equatable {
    let size: CGSize
    let rows: Int
    let cols: Int
    let walls: Set<P>
    let targets: Set<P>
    let crates: Set<P>
    let player: P
    let facing: Int

    var body: some View {
        Canvas { ctx, _ in
            let w = size.width, h = size.height
            let cell = cols > 0 && rows > 0 ? min(w / CGFloat(cols), h / CGFloat(rows)) : 0
            guard cell > 0 else { return }
            let ox = (w - cell * CGFloat(cols)) / 2
            let oy = (h - cell * CGFloat(rows)) / 2
            let rect = { (r: Int, c: Int) in CGRect(x: ox + CGFloat(c) * cell, y: oy + CGFloat(r) * cell, width: cell, height: cell) }
            for r in 0..<rows {
                for c in 0..<cols {
                    let p = P(r: r, c: c)
                    if walls.contains(p) {
                        CPArt.bricks(ctx, rect(r, c), cell: cell, originX: ox, originY: oy)
                    } else {
                        CPArt.floor(ctx, rect(r, c), cell: cell, originY: oy, wallAbove: walls.contains(P(r: r - 1, c: c)))
                    }
                }
            }
            for t in targets { CPArt.target(ctx, rect(t.r, t.c)) }
            for cr in crates { CPArt.crate(ctx, rect(cr.r, cr.c), parked: targets.contains(cr)) }
            CPArt.keeper(ctx, rect(player.r, player.c), facing: facing)
        }
    }
}

private enum CPArt {
    static let backdrop = LinearGradient(colors: [Color(red: 0.17, green: 0.15, blue: 0.15), Color(red: 0.09, green: 0.08, blue: 0.08)],
                                         startPoint: .top, endPoint: .bottom)
    static var crateIcon: some View {
        Canvas { ctx, size in crate(ctx, CGRect(origin: .zero, size: size), parked: false) }
    }

    /// Orange bricks in running bond, aligned to the whole room so neighbouring walls join up.
    static func bricks(_ ctx: GraphicsContext, _ r: CGRect, cell: CGFloat, originX: CGFloat, originY: CGFloat) {
        ctx.fill(Path(r), with: .color(Color(red: 0.8, green: 0.38, blue: 0.2)))
        var g = ctx
        g.clip(to: Path(r))
        let course = cell / 3, brick = cell / 2
        var mortar = Path(), light = Path()
        var y = originY + ((r.minY - originY) / course).rounded(.down) * course
        while y < r.maxY {
            let k = Int(((y - originY) / course).rounded())
            mortar.move(to: CGPoint(x: r.minX, y: y)); mortar.addLine(to: CGPoint(x: r.maxX, y: y))
            light.move(to: CGPoint(x: r.minX, y: y + 1.5)); light.addLine(to: CGPoint(x: r.maxX, y: y + 1.5))
            var x = originX + (k % 2 == 0 ? 0 : brick / 2) - brick
            while x < r.maxX {
                if x > r.minX - 1 { mortar.move(to: CGPoint(x: x, y: y)); mortar.addLine(to: CGPoint(x: x, y: y + course)) }
                x += brick
            }
            y += course
        }
        g.stroke(light, with: .color(Color(red: 0.96, green: 0.6, blue: 0.4).opacity(0.6)), lineWidth: 1)
        g.stroke(mortar, with: .color(Color(red: 0.42, green: 0.2, blue: 0.12)), lineWidth: max(1, cell * 0.035))
    }

    /// Floorboards; a strip of shade under any wall above.
    static func floor(_ ctx: GraphicsContext, _ r: CGRect, cell: CGFloat, originY: CGFloat, wallAbove: Bool) {
        ctx.fill(Path(r), with: .color(Color(red: 0.56, green: 0.39, blue: 0.23)))
        let board = cell / 4
        var seams = Path()
        for i in 0..<4 {
            let y = r.minY + CGFloat(i) * board
            seams.move(to: CGPoint(x: r.minX, y: y)); seams.addLine(to: CGPoint(x: r.maxX, y: y))
            let jx = r.minX + cell * (i % 2 == 0 ? 0.3 : 0.75)
            seams.move(to: CGPoint(x: jx, y: y)); seams.addLine(to: CGPoint(x: jx, y: y + board))
        }
        ctx.stroke(seams, with: .color(Color(red: 0.36, green: 0.24, blue: 0.13)), lineWidth: max(0.8, cell * 0.02))
        if wallAbove {
            ctx.fill(Path(CGRect(x: r.minX, y: r.minY, width: r.width, height: cell * 0.22)),
                     with: .linearGradient(Gradient(colors: [.black.opacity(0.35), .clear]), startPoint: CGPoint(x: 0, y: r.minY),
                                           endPoint: CGPoint(x: 0, y: r.minY + cell * 0.22)))
        }
    }

    /// A painted green ✕ on the boards.
    static func target(_ ctx: GraphicsContext, _ r: CGRect) {
        let s = r.width * 0.22
        var x = Path()
        x.move(to: CGPoint(x: r.midX - s, y: r.midY - s)); x.addLine(to: CGPoint(x: r.midX + s, y: r.midY + s))
        x.move(to: CGPoint(x: r.midX + s, y: r.midY - s)); x.addLine(to: CGPoint(x: r.midX - s, y: r.midY + s))
        ctx.stroke(x, with: .color(Color(red: 0.1, green: 0.24, blue: 0.08).opacity(0.6)), style: StrokeStyle(lineWidth: r.width * 0.16, lineCap: .round))
        ctx.stroke(x, with: .color(Color(red: 0.36, green: 0.86, blue: 0.3)), style: StrokeStyle(lineWidth: r.width * 0.1, lineCap: .round))
    }

    /// An X-braced wooden crate; a parked one gets a green-lit frame.
    static func crate(_ ctx: GraphicsContext, _ cellRect: CGRect, parked: Bool) {
        let r = cellRect.insetBy(dx: cellRect.width * 0.06, dy: cellRect.height * 0.06)
        let s = r.width
        let frameCol = parked ? Color(red: 0.34, green: 0.72, blue: 0.3) : Color(red: 0.6, green: 0.4, blue: 0.2)
        if parked {
            ctx.fill(Path(roundedRect: r.insetBy(dx: -s * 0.08, dy: -s * 0.08), cornerRadius: s * 0.14),
                     with: .radialGradient(Gradient(colors: [Color(red: 0.4, green: 1, blue: 0.4).opacity(0.5), .clear]),
                                           center: CGPoint(x: r.midX, y: r.midY), startRadius: s * 0.4, endRadius: s * 0.62))
        }
        let outer = Path(roundedRect: r, cornerRadius: s * 0.07)
        ctx.fill(outer, with: .color(frameCol))
        let inner = r.insetBy(dx: s * 0.14, dy: s * 0.14)
        ctx.fill(Path(inner), with: .linearGradient(Gradient(colors: [Color(red: 0.92, green: 0.72, blue: 0.44), Color(red: 0.8, green: 0.58, blue: 0.32)]),
                                                    startPoint: CGPoint(x: inner.minX, y: inner.minY), endPoint: CGPoint(x: inner.maxX, y: inner.maxY)))
        var clip = ctx
        clip.clip(to: Path(inner))
        var brace = Path()
        brace.move(to: CGPoint(x: inner.minX, y: inner.minY)); brace.addLine(to: CGPoint(x: inner.maxX, y: inner.maxY))
        brace.move(to: CGPoint(x: inner.maxX, y: inner.minY)); brace.addLine(to: CGPoint(x: inner.minX, y: inner.maxY))
        clip.stroke(brace, with: .color(frameCol), lineWidth: s * 0.13)
        var nails = Path()
        for (x, y) in [(r.minX, r.minY), (r.maxX, r.minY), (r.minX, r.maxY), (r.maxX, r.maxY)] {
            let q = CGPoint(x: x + (x < r.midX ? s * 0.07 : -s * 0.07), y: y + (y < r.midY ? s * 0.07 : -s * 0.07))
            nails.addEllipse(in: CGRect(x: q.x - s * 0.025, y: q.y - s * 0.025, width: s * 0.05, height: s * 0.05))
        }
        ctx.fill(nails, with: .color(Color(red: 0.25, green: 0.18, blue: 0.12)))
        ctx.stroke(outer, with: .color(Color(red: 0.24, green: 0.14, blue: 0.07)), lineWidth: max(1, s * 0.04))
    }

    /// The warehouse keeper: an upright banana in a blue cap, facing where it last walked.
    static func keeper(_ ctx: GraphicsContext, _ cellRect: CGRect, facing: Int) {
        let s = cellRect.width * 0.98
        var g = ctx
        g.translateBy(x: cellRect.midX, y: cellRect.midY)
        g.scaleBy(x: CGFloat(facing < 0 ? -1 : 1) * s, y: s)
        let ink = Color(red: 0.12, green: 0.09, blue: 0.05)
        g.fill(Path(ellipseIn: CGRect(x: -0.3, y: 0.38, width: 0.6, height: 0.12)), with: .color(.black.opacity(0.25)))
        var body = Path()
        body.move(to: CGPoint(x: -0.02, y: -0.4))
        body.addCurve(to: CGPoint(x: 0.08, y: 0.44), control1: CGPoint(x: -0.46, y: -0.2), control2: CGPoint(x: -0.4, y: 0.36))
        body.addCurve(to: CGPoint(x: -0.02, y: -0.4), control1: CGPoint(x: 0.12, y: 0.2), control2: CGPoint(x: 0.2, y: -0.18))
        body.closeSubpath()
        g.fill(body, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.92, blue: 0.4), Color(red: 0.95, green: 0.72, blue: 0.14)]),
                                           startPoint: CGPoint(x: 0.1, y: 0), endPoint: CGPoint(x: -0.35, y: 0)))
        g.stroke(body, with: .color(ink), lineWidth: 0.04)
        // Blue cap with its brim to the front.
        var cap = Path()
        cap.move(to: CGPoint(x: -0.2, y: -0.3))
        cap.addQuadCurve(to: CGPoint(x: 0.14, y: -0.32), control: CGPoint(x: -0.04, y: -0.56))
        cap.closeSubpath()
        g.fill(cap, with: .color(Color(red: 0.2, green: 0.42, blue: 0.86)))
        g.fill(Path(roundedRect: CGRect(x: 0.06, y: -0.34, width: 0.24, height: 0.06), cornerRadius: 0.03), with: .color(Color(red: 0.14, green: 0.3, blue: 0.66)))
        g.stroke(cap, with: .color(ink), lineWidth: 0.035)
        let eye = Path(ellipseIn: CGRect(x: -0.07, y: -0.2, width: 0.15, height: 0.16))
        g.fill(eye, with: .color(.white))
        g.stroke(eye, with: .color(ink), lineWidth: 0.025)
        g.fill(Path(ellipseIn: CGRect(x: 0.01, y: -0.15, width: 0.06, height: 0.08)), with: .color(ink))
        var smile = Path()
        smile.move(to: CGPoint(x: -0.06, y: 0.02)); smile.addQuadCurve(to: CGPoint(x: 0.07, y: 0.0), control: CGPoint(x: 0.02, y: 0.09))
        g.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: 0.03, lineCap: .round))
    }
}
