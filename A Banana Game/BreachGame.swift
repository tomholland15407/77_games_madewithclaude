//
//  BreachGame.swift
//  A Banana Game
//
//  Brain / strategy — a Rainbow Six / Battle City breach. You must reach the vault through a field
//  of destructible brick, but you carry only a handful of breach charges. Face a brick and tap
//  BREACH to blow a hole (one charge). Pick the shortest route — guards converge on you and will
//  pour through the very holes you open, so every wasted charge and every extra second is danger.
//  Every board is generated and verified reachable within your charge budget.
//
//  7 levels: thicker brick, fewer charges, more and faster guards, and less time.
//

import SwiftUI

enum BreachGame {
    static let definition = GameDefinition(
        id: "breach",
        title: "Breach",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        locksFeed: false,
        manual: GameManual(
            bullets: [
                "Reach the vault. Move with the d-pad.",
                "Face a brick wall and tap BREACH to blast a hole — each blast costs one charge.",
                "Charges are limited, so pick the shortest route.",
                "Guards chase you through your holes; beat them and the clock to the vault.",
            ],
            bulletsVI: [
                "Đến két sắt. Di chuyển bằng d-pad.",
                "Đối mặt tường gạch và chạm PHÁ để nổ một lỗ — mỗi lần nổ tốn một lượt.",
                "Số lần phá có hạn, nên hãy chọn đường ngắn nhất.",
                "Lính gác đuổi theo qua các lỗ của bạn; hãy vượt chúng và đồng hồ để tới két.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(BreachView(level: level, onWin: onWin, onFail: onFail))
        },
        prefetch: { level in BreachView(level: level, onWin: {}, onFail: {}).prefetchBoard() }
    )
}

struct BreachView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    private let cols = 11
    private let rows = 15

    // MARK: Difficulty
    private var brickDensity: Double { [0.35, 0.42, 0.48, 0.55, 0.62, 0.70, 0.78][min(level, 7) - 1] }
    private var breachBudget: Int    { [7, 7, 6, 5, 5, 4, 4][min(level, 7) - 1] }
    private var guardCount: Int      { [1, 1, 2, 2, 3, 3, 4][min(level, 7) - 1] }
    private var guardSpeed: Double   { [1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.2][min(level, 7) - 1] }
    private var timeLimit: Double    { Double(46 - level * 3) }

    private let moveInterval: Double = 0.13

    private struct P: Hashable { let r: Int; let c: Int }
    private enum Tile { case floor, solid, brick }
    private struct Enemy: Identifiable { let id = UUID(); var pos: CGPoint }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var grid: [[Tile]] = []
    @State private var guards: [Enemy] = []
    @State private var playerCell = P(r: 1, c: 1)
    @State private var targetCell = P(r: 1, c: 1)
    @State private var facing: (Int, Int) = (0, -1)
    @State private var moveDir: (Int, Int) = (0, 0)
    @State private var stepCD: Double = 0
    @State private var charges = 0
    @State private var timeLeft = 0.0
    @State private var built = false
    @State private var ready = false
    @State private var demoDir: (dc: Int, dr: Int)? = nil   // d-pad arrow flashed in the demo
    @State private var demoBreachPress = false              // BREACH button flashed in the demo
    // Presentation only: blown-out brick leaves rubble; each blast plays a short explosion.
    private struct Blast { let cell: P; let t0: Date }
    @State private var rubble: Set<P> = []
    @State private var blasts: [Blast] = []

    var body: some View {
        Group {
            if ready { gameBody }
            else { BrainstormingView(skyTop: Color(white: 0.11), skyBottom: Color(white: 0.04)) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { isDemo ? await runDemo() : await run() }
    }

    // MARK: - Demo (live manual clip)

    /// A fixed brick corridor: face up, breach the single brick, then walk to the vault
    /// while a guard creeps up the corridor behind (it never catches in the short loop).
    private func runDemo() async {
        while !Task.isCancelled {
            demoSetup()
            await demoWait(0.7)
            withAnimation(.easeOut(duration: 0.1)) { facing = (0, -1); demoDir = (0, -1) }   // aim up at the brick
            await demoWait(0.5)
            withAnimation(.easeOut(duration: 0.1)) { demoBreachPress = true }
            breach()                         // blow the brick ahead
            await demoWait(0.35)
            withAnimation(.easeIn(duration: 0.1)) { demoBreachPress = false }
            await demoWait(0.3)
            for _ in 0..<3 {                 // step up the cleared corridor to the vault
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.1)) { demoDir = (0, -1) }
                tryStep(dc: 0, dr: -1)
                await demoWait(0.28)
                withAnimation(.easeIn(duration: 0.1)) { demoDir = nil }
                await demoWait(0.22)
            }
            if playerCell == targetCell { win() }   // onWin is a no-op; marks it reached
            await demoWait(1.2)              // hold on the vault
        }
    }

    /// Sleeps while nudging the guards toward the player (life without a fail check).
    private func demoWait(_ dur: Double) async {
        let steps = max(1, Int(dur / 0.016))
        for _ in 0..<steps {
            guard !Task.isCancelled else { return }
            let pp = CGPoint(x: Double(playerCell.c) + 0.5, y: Double(playerCell.r) + 0.5)
            for i in guards.indices { chase(&guards[i], toward: pp, dt: 0.016) }
            try? await Task.sleep(for: .seconds(0.016))
        }
    }

    private func demoSetup() {
        var g = Array(repeating: Array(repeating: Tile.brick, count: cols), count: rows)
        for r in 0..<rows { g[r][0] = .solid; g[r][cols - 1] = .solid }
        for c in 0..<cols { g[0][c] = .solid; g[rows - 1][c] = .solid }
        // A clear vertical corridor up column 5, blocked by one brick to breach at (4,5).
        for r in 1..<(rows - 1) { g[r][5] = .floor }
        g[4][5] = .brick
        grid = g
        playerCell = P(r: 5, c: 5)
        targetCell = P(r: 1, c: 5)
        guards = [Enemy(pos: CGPoint(x: 5.5, y: 12.5))]   // trailing up the corridor
        rubble = []; blasts = []
        facing = (0, -1)
        moveDir = (0, 0); stepCD = 0
        charges = breachBudget
        timeLeft = timeLimit
        built = true
        ready = true
        phase = .play
    }

    private var gameBody: some View {
        VStack(spacing: isDemo ? 6 : 10) {
            header
            if !isDemo { timeBar.frame(height: 5).padding(.horizontal, 50) }
            board
            controls
        }
        .padding(.top, isDemo ? 8 : 12)
        .padding(.bottom, isDemo ? 8 : 10)
        .padding(.horizontal, isDemo ? 6 : 10)
        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// C4 charges left, as a row of little plastic-explosive bricks (spent ones greyed).
    private var header: some View {
        HStack(spacing: isDemo ? 4 : 6) {
            ForEach(0..<breachBudget, id: \.self) { i in
                Canvas { ctx, s in HeistArt.c4(ctx, in: CGRect(origin: .zero, size: s), live: i < charges) }
                    .frame(width: isDemo ? 22 : 28, height: isDemo ? 15 : 19)
            }
        }
        .animation(.easeOut(duration: 0.2), value: charges)
    }

    private var board: some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width
            let h: CGFloat = geo.size.height
            // The squat demo card shows the top 11 rows (vault, breach and walk-up); the guard creeps in.
            let shownRows = isDemo ? 11 : rows
            let cell: CGFloat = min(w / CGFloat(cols), h / CGFloat(shownRows))
            let ox: CGFloat = (w - cell * CGFloat(cols)) / 2
            let oy: CGFloat = (h - cell * CGFloat(shownRows)) / 2

            ZStack {
                HeistFloor(cols: cols, rows: rows, cell: cell, origin: CGPoint(x: ox, y: oy)).equatable()
                TimelineView(.animation(paused: blasts.isEmpty)) { tl in
                    Canvas { ctx, _ in drawHeist(ctx, cell: cell, ox: ox, oy: oy, now: tl.date) }
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: isDemo ? 8 : 12))
        }
    }

    /// Walls, rubble, the vault door, guards with flashlights, the masked banana and C4 blasts.
    private func drawHeist(_ ctx: GraphicsContext, cell: CGFloat, ox: CGFloat, oy: CGFloat, now: Date) {
        guard grid.count == rows else { return }
        func rect(_ r: Int, _ c: Int) -> CGRect {
            CGRect(x: ox + CGFloat(c) * cell, y: oy + CGFloat(r) * cell, width: cell, height: cell)
        }
        for p in rubble { HeistArt.rubble(ctx, in: rect(p.r, p.c), seed: p.r * 31 + p.c) }
        for r in 0..<rows {
            for c in 0..<cols {
                switch grid[r][c] {
                case .floor: break
                case .solid: HeistArt.steel(ctx, in: rect(r, c))
                case .brick: HeistArt.brick(ctx, in: rect(r, c), row: r)
                }
            }
        }
        let vc = CGPoint(x: rect(targetCell.r, targetCell.c).midX, y: rect(targetCell.r, targetCell.c).midY)
        HeistArt.vault(ctx, at: vc, cell: cell)
        let pp = CGPoint(x: ox + (CGFloat(playerCell.c) + 0.5) * cell, y: oy + (CGFloat(playerCell.r) + 0.5) * cell)
        for g in guards {
            let gp = CGPoint(x: ox + CGFloat(g.pos.x) * cell, y: oy + CGFloat(g.pos.y) * cell)
            HeistArt.guardman(ctx, at: gp, toward: pp, cell: cell)
        }
        HeistArt.burglar(ctx, at: pp, facing: facing, cell: cell)
        for b in blasts {
            HeistArt.blast(ctx, in: rect(b.cell.r, b.cell.c), t: now.timeIntervalSince(b.t0))
        }
    }

    private var controls: some View {
        HStack(alignment: .center) {
            if isDemo {
                HStack(spacing: 5) {
                    dpadButton(-1, 0, "chevron.left")
                    dpadButton(0, -1, "chevron.up")
                    dpadButton(0, 1, "chevron.down")
                    dpadButton(1, 0, "chevron.right")
                }
            } else {
                dpad
            }
            Spacer()
            Button { breach() } label: {
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(AngularGradient(colors: Array(repeating: [Color(red: 0.98, green: 0.8, blue: 0.1), Color(white: 0.1)], count: 6).flatMap { $0 },
                                                  center: .center))
                        Circle()
                            .fill(RadialGradient(colors: charges > 0 ? [Color(red: 1, green: 0.45, blue: 0.4), Color(red: 0.8, green: 0.06, blue: 0.06)]
                                                                     : [Color(white: 0.55), Color(white: 0.3)],
                                                 center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: isDemo ? 16 : 28))
                            .padding(isDemo ? 5 : 8)
                            .shadow(color: .black.opacity(0.4), radius: 0, x: 0, y: demoBreachPress ? 1 : 3)
                            .scaleEffect(demoBreachPress ? 0.88 : 1)
                        Circle().stroke(.white, lineWidth: demoBreachPress ? 3 : 0)
                    }
                    .frame(width: isDemo ? 40 : 70, height: isDemo ? 40 : 70)
                    if !isDemo {
                        Text(L("BREACH", "PHÁ"))
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(charges > 0 ? .white : .white.opacity(0.4))
                    }
                }
                .animation(.easeOut(duration: 0.1), value: demoBreachPress)
            }
            .buttonStyle(.plain)
            .disabled(charges == 0)
        }
        .padding(.horizontal, isDemo ? 16 : 24)
    }

    private var dpad: some View {
        VStack(spacing: 5) {
            dpadButton(0, -1, "chevron.up")
            HStack(spacing: 5) {
                dpadButton(-1, 0, "chevron.left")
                dpadButton(1, 0, "chevron.right")
            }
            dpadButton(0, 1, "chevron.down")
        }
    }

    private func dpadButton(_ dc: Int, _ dr: Int, _ icon: String) -> some View {
        let pressed = demoDir?.dc == dc && demoDir?.dr == dr
        return Image(systemName: icon)
            .font(.system(size: isDemo ? 15 : 20, weight: .black))
            .foregroundStyle(pressed ? .black : .white)
            .frame(width: isDemo ? 44 : 62, height: isDemo ? 34 : 44)
            .background(pressed ? BananaTheme.banana : Color(white: 0.24), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(pressed ? 0 : 0.12), lineWidth: 1))
            .scaleEffect(pressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.1), value: pressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard phase == .play else { return }
                        facing = (dc, dr)
                        if moveDir != (dc, dr) { moveDir = (dc, dr); stepCD = 0 }
                    }
                    .onEnded { _ in if moveDir == (dc, dr) { moveDir = (0, 0) } }
            )
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac: Double = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(frac < 0.3 ? .red : BananaTheme.banana)
                    .frame(width: geo.size.width * max(0, frac))
            }
        }
    }
    // MARK: - Flow

    /// Hands this level's board build to `BoardCache` so it can run during the countdown.
    func prefetchBoard() {
        let (c, r, bd, bb, gc, lv) = (cols, rows, brickDensity, breachBudget, guardCount, level)
        BoardCache.prefetch(boardKey) { Self.generate(cols: c, rows: r, brickDensity: bd, breachBudget: bb, guardCount: gc, level: lv) }
    }
    private var boardKey: String { BoardCache.key("breach", level: level) }

    private func run() async {
        if !built {
            // Claim the board prefetched during the countdown (or build it now, off-main). If the
            // "brainstorming" page did show, it stays up a minimum beat so it never flickers.
            let (c, r, bd, bb, gc, lv) = (cols, rows, brickDensity, breachBudget, guardCount, level)
            let t0 = Date()
            let board = await BoardCache.take(boardKey) { Self.generate(cols: c, rows: r, brickDensity: bd, breachBudget: bb, guardCount: gc, level: lv) }
            await BoardCache.holdBrainstorm(since: t0, minimum: 1.0)
            guard !Task.isCancelled else { return }
            grid = board.grid
            playerCell = board.player
            targetCell = board.target
            guards = board.guards
            rubble = []; blasts = []
            charges = breachBudget
            facing = (0, -1)
            moveDir = (0, 0); stepCD = 0
            timeLeft = timeLimit
            built = true
            ready = true
            phase = .play
        }
        var last = Date()
        while !Task.isCancelled && phase == .play {
            try? await Task.sleep(for: .seconds(0.016))
            let now = Date()
            let dt = min(0.05, now.timeIntervalSince(last)); last = now
            step(dt: dt)
        }
    }

    private func step(dt: Double) {
        guard phase == .play else { return }

        stepCD -= dt
        if moveDir != (0, 0) && stepCD <= 0 {
            tryStep(dc: moveDir.0, dr: moveDir.1)
            stepCD = moveInterval
        }

        // Guards converge.
        let pp = CGPoint(x: Double(playerCell.c) + 0.5, y: Double(playerCell.r) + 0.5)
        for i in guards.indices { chase(&guards[i], toward: pp, dt: dt) }
        for g in guards where hypot(g.pos.x - pp.x, g.pos.y - pp.y) < 0.6 { fail(); return }

        if playerCell == targetCell { win(); return }

        timeLeft -= dt
        if timeLeft <= 0 { timeLeft = 0; fail() }
    }

    private func tryStep(dc: Int, dr: Int) {
        let target = P(r: playerCell.r + dr, c: playerCell.c + dc)
        guard inBounds(target), tileAt(target) == .floor else { return }
        playerCell = target
        SoundManager.shared.tap()
    }

    private func breach() {
        guard phase == .play, charges > 0 else { return }
        let ahead = P(r: playerCell.r + facing.1, c: playerCell.c + facing.0)
        guard inBounds(ahead), tileAt(ahead) == .brick else { SoundManager.shared.error(); return }
        grid[ahead.r][ahead.c] = .floor
        rubble.insert(ahead)
        let blast = Blast(cell: ahead, t0: Date())
        blasts.append(blast)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.7))
            blasts.removeAll { $0.t0 == blast.t0 }
        }
        charges -= 1
        SoundManager.shared.tap(); Haptics.warning()
    }

    private func chase(_ e: inout Enemy, toward p: CGPoint, dt: Double) {
        let dx = p.x - e.pos.x, dy = p.y - e.pos.y
        let d = hypot(dx, dy)
        guard d > 0.05 else { return }
        let sp = guardSpeed * dt
        let nx = dx / d * sp, ny = dy / d * sp
        // Axis-separated; prefer the larger axis first so they thread holes.
        if abs(dx) >= abs(dy) {
            if canGuardStand(e.pos.x + nx, e.pos.y) { e.pos.x += nx }
            else if canGuardStand(e.pos.x, e.pos.y + ny) { e.pos.y += ny }
        } else {
            if canGuardStand(e.pos.x, e.pos.y + ny) { e.pos.y += ny }
            else if canGuardStand(e.pos.x + nx, e.pos.y) { e.pos.x += nx }
        }
    }

    private func win() {
        guard phase == .play else { return }
        phase = .done
        Haptics.success(); SoundManager.shared.tap()
        onWin()
    }

    private func fail() {
        guard phase == .play else { return }
        phase = .done
        Haptics.warning(); SoundManager.shared.error()
        onFail()
    }

    // MARK: - Grid helpers

    private func inBounds(_ p: P) -> Bool { p.r >= 0 && p.r < rows && p.c >= 0 && p.c < cols }
    private func tileAt(_ p: P) -> Tile { grid.count == rows ? grid[p.r][p.c] : .solid }

    /// Guards are blocked by solid walls and unbroken brick, but flow through opened floor.
    private func canGuardStand(_ x: Double, _ y: Double) -> Bool {
        let rad = 0.3
        for cx in [x - rad, x + rad] {
            for cy in [y - rad, y + rad] {
                let r = Int(floor(cy)), c = Int(floor(cx))
                guard r >= 0, r < rows, c >= 0, c < cols, grid.count == rows else { return false }
                if grid[r][c] != .floor { return false }
            }
        }
        return true
    }

    private func manhattan(_ a: P, _ b: P) -> Int { abs(a.r - b.r) + abs(a.c - b.c) }
    private static func manhattan(_ a: P, _ b: P) -> Int { abs(a.r - b.r) + abs(a.c - b.c) }

    // MARK: - Generation (pure/static → runs off the main actor via run())

    private struct BBoard { var grid: [[Tile]]; var player: P; var target: P; var guards: [Enemy] }

    private static func generate(cols: Int, rows: Int, brickDensity: Double, breachBudget: Int,
                                 guardCount: Int, level: Int) -> BBoard {
        for _ in 0..<200 {
            if let b = tryBuild(cols: cols, rows: rows, brickDensity: brickDensity,
                                breachBudget: breachBudget, guardCount: guardCount, level: level) {
                return b
            }
        }
        // Fallback: a single brick wall to punch through.
        var g = Array(repeating: Array(repeating: Tile.floor, count: cols), count: rows)
        for r in 0..<rows { g[r][0] = .solid; g[r][cols - 1] = .solid }
        for c in 0..<cols { g[0][c] = .solid; g[rows - 1][c] = .solid }
        for c in 1..<(cols - 1) { g[rows / 2][c] = .brick }
        return BBoard(grid: g, player: P(r: rows - 2, c: cols / 2), target: P(r: 1, c: cols / 2),
                      guards: [Enemy(pos: CGPoint(x: Double(cols) / 2, y: 2.5))])
    }

    private static func tryBuild(cols: Int, rows: Int, brickDensity: Double, breachBudget: Int,
                                 guardCount: Int, level: Int) -> BBoard? {
        var g = Array(repeating: Array(repeating: Tile.floor, count: cols), count: rows)
        for r in 0..<rows { g[r][0] = .solid; g[r][cols - 1] = .solid }
        for c in 0..<cols { g[0][c] = .solid; g[rows - 1][c] = .solid }

        let start = P(r: rows - 2, c: cols / 2)
        let target = P(r: 1, c: cols / 2)

        // Fill the interior (except a small pocket around start/target) with brick at density.
        for r in 2..<(rows - 2) {
            for c in 1..<(cols - 1) {
                let p = P(r: r, c: c)
                if manhattan(p, start) <= 1 || manhattan(p, target) <= 1 { continue }
                if Double.random(in: 0...1) < brickDensity { g[r][c] = .brick }
            }
        }
        // A few indestructible pillars for flavor (never on start/target).
        for _ in 0..<level {
            let r = Int.random(in: 3...(rows - 4)), c = Int.random(in: 2...(cols - 3))
            let p = P(r: r, c: c)
            if manhattan(p, start) > 2 && manhattan(p, target) > 2 { g[r][c] = .solid }
        }
        g[start.r][start.c] = .floor
        g[target.r][target.c] = .floor

        // 0-1 BFS: cost = bricks broken. Verify reachable and tight against the budget.
        guard let cost = minBreaches(from: start, to: target, in: g, rows: rows, cols: cols),
              cost >= 2, cost <= breachBudget else { return nil }

        let gs = placeGuards(avoid: start, target: target, in: g, rows: rows, cols: cols, guardCount: guardCount)
        return BBoard(grid: g, player: start, target: target, guards: gs)
    }

    private static func minBreaches(from s: P, to t: P, in g: [[Tile]], rows: Int, cols: Int) -> Int? {
        func inB(_ p: P) -> Bool { p.r >= 0 && p.r < rows && p.c >= 0 && p.c < cols }
        var best = Array(repeating: Array(repeating: Int.max, count: cols), count: rows)
        best[s.r][s.c] = 0
        var dq: [(P, Int)] = [(s, 0)]
        while !dq.isEmpty {
            let (cur, cost) = dq.removeFirst()
            if cost > best[cur.r][cur.c] { continue }
            if cur == t { return cost }
            let ns = [P(r: cur.r - 1, c: cur.c), P(r: cur.r + 1, c: cur.c),
                      P(r: cur.r, c: cur.c - 1), P(r: cur.r, c: cur.c + 1)]
            for n in ns where inB(n) {
                let tile = g[n.r][n.c]
                if tile == .solid { continue }
                let nc = cost + (tile == .brick ? 1 : 0)
                if nc < best[n.r][n.c] {
                    best[n.r][n.c] = nc
                    if tile == .brick { dq.append((n, nc)) } else { dq.insert((n, nc), at: 0) }
                }
            }
        }
        return best[t.r][t.c] == Int.max ? nil : best[t.r][t.c]
    }

    private static func placeGuards(avoid start: P, target: P, in g: [[Tile]],
                                    rows: Int, cols: Int, guardCount: Int) -> [Enemy] {
        var open: [P] = []
        for r in 1..<(rows - 1) {
            for c in 1..<(cols - 1) where g[r][c] == .floor {
                let p = P(r: r, c: c)
                if manhattan(p, start) >= 4 { open.append(p) }
            }
        }
        open.sort { manhattan($0, target) < manhattan($1, target) }
        var gs: [Enemy] = []
        for p in open {
            if gs.allSatisfy({ hypot($0.pos.x - (Double(p.c) + 0.5), $0.pos.y - (Double(p.r) + 0.5)) >= 2 }) {
                gs.append(Enemy(pos: CGPoint(x: Double(p.c) + 0.5, y: Double(p.r) + 0.5)))
                if gs.count == guardCount { break }
            }
        }
        while gs.count < guardCount {
            gs.append(Enemy(pos: CGPoint(x: Double(target.c) + 0.5, y: Double(target.r) + 1.5)))
        }
        return gs
    }

}

// MARK: - Heist art

/// A bank heist: a marble lobby, riveted steel walls, red brick to blow with C4, a round steel vault
/// door, security guards with flashlights, and a banana burglar in a bandit mask.
private enum HeistArt {
    static func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
    static let brickRed = c(0.72, 0.28, 0.17)

    private static func disc(_ p: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }

    static func steel(_ ctx: GraphicsContext, in r: CGRect) {
        let q = r.insetBy(dx: -0.3, dy: -0.3)
        ctx.fill(Path(q), with: .linearGradient(Gradient(colors: [c(0.42, 0.45, 0.5), c(0.26, 0.28, 0.32)]),
                                                startPoint: CGPoint(x: q.minX, y: q.minY), endPoint: CGPoint(x: q.maxX, y: q.maxY)))
        ctx.stroke(Path(r.insetBy(dx: r.width * 0.06, dy: r.width * 0.06)), with: .color(.white.opacity(0.1)), lineWidth: 1)
        let rv = r.width * 0.07
        for (fx, fy) in [(0.2, 0.2), (0.8, 0.2), (0.2, 0.8), (0.8, 0.8)] as [(CGFloat, CGFloat)] {
            let p = CGPoint(x: r.minX + r.width * fx, y: r.minY + r.height * fy)
            ctx.fill(disc(p, rv), with: .color(c(0.62, 0.64, 0.68)))
            ctx.fill(disc(CGPoint(x: p.x + rv * 0.3, y: p.y + rv * 0.3), rv * 0.6), with: .color(c(0.2, 0.21, 0.24)))
        }
    }

    /// Three courses of running-bond brick in a cell (offsets follow the global row so walls tile).
    static func brick(_ ctx: GraphicsContext, in r: CGRect, row: Int) {
        ctx.fill(Path(r.insetBy(dx: -0.3, dy: -0.3)), with: .color(c(0.5, 0.42, 0.36)))
        var g = ctx
        g.clip(to: Path(r))
        let ch = r.height / 3, bw = r.width / 2
        for k in 0..<3 {
            let y = r.minY + CGFloat(k) * ch
            let shift = (row * 3 + k) % 2 == 0 ? 0 : bw / 2
            for i in -1...2 {
                let b = CGRect(x: r.minX + CGFloat(i) * bw + shift, y: y, width: bw, height: ch).insetBy(dx: 0.8, dy: 0.8)
                let tone = Double((row * 7 + k * 3 + i * 5 + 50) % 5) * 0.03
                let base = brickRed.shade(tone)
                g.fill(Path(roundedRect: b, cornerRadius: 1), with: .color(base))
                g.fill(Path(CGRect(x: b.minX, y: b.minY, width: b.width, height: max(0.8, ch * 0.16))), with: .color(base.lit(0.25)))
                g.fill(Path(CGRect(x: b.minX, y: b.maxY - max(0.8, ch * 0.16), width: b.width, height: max(0.8, ch * 0.16))), with: .color(base.shade(0.25)))
            }
        }
    }

    static func rubble(_ ctx: GraphicsContext, in r: CGRect, seed: Int) {
        ctx.fill(disc(CGPoint(x: r.midX, y: r.midY), r.width * 0.42), with: .color(c(0.4, 0.38, 0.35).opacity(0.25)))
        for k in 0..<6 {
            let a = Double(seed * 13 + k * 61)
            let q = CGPoint(x: r.midX + CGFloat(cos(a)) * r.width * 0.3, y: r.midY + CGFloat(sin(a * 1.3)) * r.height * 0.3)
            var g = ctx
            g.translateBy(x: q.x, y: q.y)
            g.rotate(by: .radians(a))
            let s = r.width * (0.1 + 0.04 * CGFloat(k % 3))
            g.fill(Path(CGRect(x: -s / 2, y: -s * 0.3, width: s, height: s * 0.6)), with: .color(brickRed.shade(0.1)))
        }
    }

    /// The round steel vault door, bolted into the wall, with its spoked wheel and a golden glow.
    static func vault(_ ctx: GraphicsContext, at p: CGPoint, cell: CGFloat) {
        let R = cell * 0.78
        ctx.fill(disc(p, R * 1.9), with: .radialGradient(Gradient(colors: [c(1, 0.85, 0.35).opacity(0.45), .clear]),
                                                        center: p, startRadius: 0, endRadius: R * 1.9))
        ctx.fill(disc(p, R * 1.1), with: .color(c(0.2, 0.21, 0.24)))
        ctx.fill(disc(p, R), with: .radialGradient(Gradient(colors: [c(0.9, 0.91, 0.93), c(0.62, 0.64, 0.68), c(0.4, 0.42, 0.46)]),
                                                  center: CGPoint(x: p.x - R * 0.3, y: p.y - R * 0.35), startRadius: 0, endRadius: R * 1.3))
        ctx.stroke(disc(p, R), with: .color(c(0.25, 0.26, 0.3)), lineWidth: max(1, R * 0.06))
        for k in 0..<10 {
            let a = Double(k) / 10 * 2 * .pi
            ctx.fill(disc(CGPoint(x: p.x + CGFloat(cos(a)) * R * 0.82, y: p.y + CGFloat(sin(a)) * R * 0.82), R * 0.06),
                     with: .color(c(0.3, 0.31, 0.35)))
        }
        var spokes = Path()
        for k in 0..<6 {
            let a = Double(k) / 6 * 2 * .pi + 0.3
            spokes.move(to: p)
            spokes.addLine(to: CGPoint(x: p.x + CGFloat(cos(a)) * R * 0.55, y: p.y + CGFloat(sin(a)) * R * 0.55))
        }
        ctx.stroke(spokes, with: .color(c(0.78, 0.62, 0.2)), style: StrokeStyle(lineWidth: max(1.5, R * 0.1), lineCap: .round))
        ctx.stroke(disc(p, R * 0.5), with: .color(c(0.85, 0.7, 0.25)), lineWidth: max(1.5, R * 0.08))
        ctx.fill(disc(p, R * 0.14), with: .color(c(0.95, 0.8, 0.3)))
    }

    /// A security guard from above: navy uniform and cap, flashlight beam aimed at the burglar.
    static func guardman(_ ctx: GraphicsContext, at p: CGPoint, toward target: CGPoint, cell: CGFloat) {
        let a = atan2(Double(target.y - p.y), Double(target.x - p.x))
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        g.rotate(by: .radians(a))
        var beam = Path()
        beam.move(to: CGPoint(x: cell * 0.3, y: 0))
        beam.addLine(to: CGPoint(x: cell * 2.3, y: -cell * 0.85))
        beam.addLine(to: CGPoint(x: cell * 2.3, y: cell * 0.85))
        beam.closeSubpath()
        g.fill(beam, with: .linearGradient(Gradient(colors: [c(1, 0.96, 0.7).opacity(0.45), c(1, 0.96, 0.7).opacity(0)]),
                                           startPoint: CGPoint(x: cell * 0.3, y: 0), endPoint: CGPoint(x: cell * 2.3, y: 0)))
        let navy = c(0.14, 0.2, 0.44)
        g.fill(Path(ellipseIn: CGRect(x: -cell * 0.18, y: -cell * 0.34, width: cell * 0.36, height: cell * 0.68)), with: .color(navy))
        g.stroke(Path(ellipseIn: CGRect(x: -cell * 0.18, y: -cell * 0.34, width: cell * 0.36, height: cell * 0.68)), with: .color(.black.opacity(0.5)), lineWidth: 1)
        g.fill(Path(roundedRect: CGRect(x: cell * 0.05, y: cell * 0.12, width: cell * 0.3, height: cell * 0.1), cornerRadius: cell * 0.04), with: .color(navy.shade(0.2)))
        g.fill(Path(roundedRect: CGRect(x: cell * 0.3, y: cell * 0.1, width: cell * 0.12, height: cell * 0.14), cornerRadius: cell * 0.03), with: .color(c(0.7, 0.72, 0.76)))
        g.fill(disc(CGPoint(x: cell * 0.02, y: 0), cell * 0.15), with: .color(navy.shade(0.35)))
        g.fill(Path(ellipseIn: CGRect(x: cell * 0.1, y: -cell * 0.1, width: cell * 0.14, height: cell * 0.2)), with: .color(navy.shade(0.5)))
        g.fill(disc(CGPoint(x: -cell * 0.02, y: -cell * 0.22), cell * 0.045), with: .color(c(0.95, 0.8, 0.3)))
    }

    /// The banana burglar from above: a masked banana with a loot sack, pointing where it faces.
    static func burglar(_ ctx: GraphicsContext, at p: CGPoint, facing: (Int, Int), cell: CGFloat) {
        let a = atan2(Double(facing.1), Double(facing.0))
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        g.rotate(by: .radians(a))
        let s = cell
        g.fill(disc(CGPoint(x: -s * 0.24, y: 0), s * 0.17), with: .color(c(0.55, 0.38, 0.2)))
        g.stroke(disc(CGPoint(x: -s * 0.24, y: 0), s * 0.17), with: .color(c(0.3, 0.2, 0.08)), lineWidth: 1)
        var body = Path()
        body.move(to: CGPoint(x: -s * 0.2, y: -s * 0.3))
        body.addQuadCurve(to: CGPoint(x: s * 0.32, y: s * 0.0), control: CGPoint(x: s * 0.2, y: -s * 0.36))
        body.addQuadCurve(to: CGPoint(x: -s * 0.2, y: s * 0.3), control: CGPoint(x: s * 0.2, y: s * 0.36))
        body.addQuadCurve(to: CGPoint(x: -s * 0.2, y: -s * 0.3), control: CGPoint(x: s * 0.05, y: 0))
        body.closeSubpath()
        g.fill(body, with: .linearGradient(Gradient(colors: [c(1, 0.93, 0.45), c(0.98, 0.78, 0.1)]),
                                           startPoint: CGPoint(x: 0, y: -s * 0.3), endPoint: CGPoint(x: 0, y: s * 0.3)))
        g.stroke(body, with: .color(c(0.45, 0.3, 0.05)), lineWidth: max(1, s * 0.04))
        // Bandit mask across the front, two eye holes looking ahead.
        var g2 = g
        g2.clip(to: body)
        g2.fill(Path(CGRect(x: s * 0.05, y: -s * 0.4, width: s * 0.14, height: s * 0.8)), with: .color(c(0.1, 0.1, 0.12)))
        for side: CGFloat in [-1, 1] {
            g.fill(disc(CGPoint(x: s * 0.13, y: side * s * 0.12), s * 0.05), with: .color(.white))
            g.fill(disc(CGPoint(x: s * 0.15, y: side * s * 0.12), s * 0.025), with: .color(.black))
        }
        var arrow = Path()
        arrow.move(to: CGPoint(x: s * 0.52, y: 0))
        arrow.addLine(to: CGPoint(x: s * 0.4, y: -s * 0.08))
        arrow.addLine(to: CGPoint(x: s * 0.4, y: s * 0.08))
        arrow.closeSubpath()
        g.fill(arrow, with: .color(.white))
    }

    /// C4 going off: a flash, bricks flying out and a puff of smoke.
    static func blast(_ ctx: GraphicsContext, in r: CGRect, t: Double) {
        guard t >= 0, t < 0.7 else { return }
        let p = CGPoint(x: r.midX, y: r.midY), s = r.width
        for k in 0..<5 {
            let a = Double(k) * 1.26 + 0.4
            let q = CGPoint(x: p.x + CGFloat(cos(a)) * s * CGFloat(0.2 + t * 0.9), y: p.y + CGFloat(sin(a)) * s * CGFloat(0.2 + t * 0.9))
            ctx.fill(disc(q, s * CGFloat(0.22 + t * 0.4)), with: .color(c(0.5, 0.48, 0.45).opacity(max(0, 0.55 - t * 0.8))))
        }
        if t < 0.35 {
            let k = t / 0.35
            ctx.fill(disc(p, s * CGFloat(0.4 + k * 0.7)),
                     with: .radialGradient(Gradient(colors: [.white, c(1, 0.85, 0.3), c(1, 0.4, 0.1), c(0.8, 0.1, 0).opacity(0)]),
                                           center: p, startRadius: 0, endRadius: s * CGFloat(0.4 + k * 0.7)))
        }
        for k in 0..<8 {
            let a = Double(k) * 0.785 + 0.2
            let d = s * CGFloat(0.2 + t * 1.8)
            var g = ctx
            g.translateBy(x: p.x + CGFloat(cos(a)) * d, y: p.y + CGFloat(sin(a)) * d)
            g.rotate(by: .radians(a * 3 + t * 8))
            let bs = s * 0.14 * CGFloat(max(0, 1 - t / 0.7))
            g.fill(Path(CGRect(x: -bs, y: -bs * 0.5, width: bs * 2, height: bs)), with: .color(brickRed))
        }
    }

    /// A block of plastic explosive with its detonator (greyed once spent).
    static func c4(_ ctx: GraphicsContext, in r: CGRect, live: Bool) {
        var g = ctx
        g.opacity = live ? 1 : 0.25
        let block = r.insetBy(dx: r.width * 0.06, dy: r.height * 0.14)
        g.fill(Path(roundedRect: block, cornerRadius: r.height * 0.12), with: .color(c(0.86, 0.82, 0.7)))
        g.stroke(Path(roundedRect: block, cornerRadius: r.height * 0.12), with: .color(c(0.35, 0.32, 0.25)), lineWidth: 1)
        g.fill(Path(roundedRect: CGRect(x: block.midX - block.width * 0.18, y: block.minY + block.height * 0.18,
                                        width: block.width * 0.36, height: block.height * 0.64), cornerRadius: 2),
               with: .color(c(0.12, 0.12, 0.14)))
        g.fill(disc(CGPoint(x: block.midX, y: block.midY), block.height * 0.14), with: .color(live ? c(1, 0.2, 0.15) : c(0.4, 0.4, 0.4)))
        var wire = Path()
        wire.move(to: CGPoint(x: block.minX + block.width * 0.12, y: block.minY))
        wire.addQuadCurve(to: CGPoint(x: block.maxX - block.width * 0.12, y: block.minY), control: CGPoint(x: block.midX, y: r.minY - r.height * 0.1))
        g.stroke(wire, with: .color(c(0.85, 0.15, 0.12)), lineWidth: max(1, r.height * 0.08))
    }
}

/// The marble lobby floor (static): cream and grey tiles with faint veins.
private struct HeistFloor: View, Equatable {
    let cols: Int, rows: Int
    let cell: CGFloat
    let origin: CGPoint

    var body: some View {
        Canvas { ctx, s in
            ctx.fill(Path(CGRect(origin: .zero, size: s)), with: .color(HeistArt.c(0.12, 0.12, 0.14)))
            for r in 0..<rows {
                for c in 0..<cols {
                    let rect = CGRect(x: origin.x + CGFloat(c) * cell, y: origin.y + CGFloat(r) * cell, width: cell, height: cell)
                    let light = (r + c) % 2 == 0
                    ctx.fill(Path(rect), with: .color(light ? HeistArt.c(0.93, 0.91, 0.86) : HeistArt.c(0.8, 0.79, 0.76)))
                    var vein = Path()
                    let k = CGFloat((r * 17 + c * 29) % 10) / 10
                    vein.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * k))
                    vein.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * (1 - k * 0.6)),
                                      control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.3))
                    ctx.stroke(vein, with: .color(.black.opacity(0.07)), lineWidth: 0.8)
                    ctx.stroke(Path(rect), with: .color(.black.opacity(0.08)), lineWidth: 0.6)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
