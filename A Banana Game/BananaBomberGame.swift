//
//  BananaBomberGame.swift
//  A Banana Game
//
//  Strategy + action — a Bomberman-style grid brawl. Move with the d-pad through a maze of
//  hard pillars and destructible crates. Tap BOMB to drop a banana bomb; after a short fuse it
//  blasts in a + cross, smashing crates and any enemy caught in it — but it kills YOU too, so
//  drop it and run. Clear every enemy to win. Get caught in a blast, touched by an enemy, or
//  time out, and you fall back to level 1. 7 levels: more enemies, denser mazes, shorter fuses,
//  and hungrier hunters — near-impossible by L6–7.
//
//  Drawn as Hudson's Bomberman: a checkered floor (grass, then desert, ice and volcanic rock),
//  bevelled stone pillars from the logic's own `hard` cells, brick soft blocks, black bombs with
//  sparking fuses, Bomberman's flame cross with a white-hot core, Ballom balloons for the enemies,
//  and the banana in Bomberman's white helmet with the pink antenna. The HUD is a Ballom and a
//  count; the BOMB key shows a bomb. The arena is an Equatable view; the rest is one Canvas.
//

import SwiftUI

enum BananaBomberGame {
    static let definition = GameDefinition(
        id: "banana-bomber",
        title: "Banana Bomber",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Move with the d-pad. Tap BOMB to drop a banana bomb.",
                "After a short fuse it explodes in a + cross that destroys crates and enemies — and you too.",
                "So run clear of the blast, then clear every enemy to win.",
                "Caught in a blast, touched by an enemy, or timed out, and it's back to level 1.",
            ],
            bulletsVI: [
                "Di chuyển bằng d-pad. Chạm BOM để thả một quả bom chuối.",
                "Sau ngòi nổ ngắn nó nổ thành hình dấu +, phá thùng và địch — và cả bạn nữa.",
                "Vậy nên hãy chạy khỏi vụ nổ, rồi dọn hết địch để thắng.",
                "Dính vụ nổ, bị địch chạm, hoặc hết giờ, sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(BananaBomberView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct BananaBomberView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void
    @Environment(\.isDemo) private var isDemo

    private let cols = 11
    private let rows = 13
    private let bombRange = 2

    private var crateCount: Int    { [16, 22, 28, 32, 36, 40, 44][min(level, 7) - 1] }
    private var enemyN: Int        { [2, 2, 3, 3, 4, 4, 5][min(level, 7) - 1] }
    private var fuse: Double       { [2.2, 2.0, 1.9, 1.8, 1.7, 1.6, 1.5][min(level, 7) - 1] }
    private var enemyStep: Double  { [0.55, 0.50, 0.45, 0.40, 0.35, 0.30, 0.26][min(level, 7) - 1] }
    private var chaseProb: Double  { [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6][min(level, 7) - 1] }
    private var timeLimit: Double  { [50, 48, 46, 44, 42, 40, 38][min(level, 7) - 1] }

    private struct Cell: Hashable { var r: Int; var c: Int }
    private struct Enemy: Identifiable { let id = UUID(); var cell: Cell; var dir: Cell }
    private struct Bomb: Identifiable { let id = UUID(); let cell: Cell; var fuse: Double }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var crates: Set<Cell> = []
    @State private var enemies: [Enemy] = []
    @State private var bombs: [Bomb] = []
    @State private var blast: Set<Cell> = []
    @State private var blastTimer = 0.0
    @State private var player = Cell(r: 1, c: 1)
    @State private var moveDir: Cell? = nil
    @State private var moveAcc = 0.0
    @State private var enemyAcc = 0.0
    @State private var timeLeft = 0.0
    @State private var loopTask: Task<Void, Never>?
    @State private var built = false
    @State private var demoBomb = 0                // demo: frames left on the BOMB press flash

    private func hard(_ r: Int, _ c: Int) -> Bool {
        r == 0 || c == 0 || r == rows - 1 || c == cols - 1 || (r % 2 == 0 && c % 2 == 0)
    }
    private func walkable(_ cell: Cell) -> Bool {
        cell.r >= 0 && cell.r < rows && cell.c >= 0 && cell.c < cols
            && !hard(cell.r, cell.c) && !crates.contains(cell) && !bombs.contains { $0.cell == cell }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Enemies left: a Ballom and its count.
            HStack(spacing: 7) {
                BBBallomIcon().frame(width: isDemo ? 17 : 22, height: isDemo ? 17 : 22)
                Text("\(enemies.count)")
                    .font(.system(size: isDemo ? 15 : 20, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            .padding(.top, isDemo ? 6 : 0)
            if !isDemo { timeBar.frame(height: 5).padding(.horizontal, 56) }

            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let cell = min(w / CGFloat(cols), h / CGFloat(rows))
                let boardW = cell * CGFloat(cols), boardH = cell * CGFloat(rows)
                let ox = (w - boardW) / 2, oy = (h - boardH) / 2

                ZStack {
                    // Floor, stone pillars and brick blocks: redrawn only when a block is blasted.
                    BBArena(size: geo.size, rows: rows, cols: cols,
                            hard: Set((0..<rows).flatMap { r in (0..<cols).filter { hard(r, $0) }.map { r * cols + $0 } }),
                            crates: Set(crates.map { $0.r * cols + $0.c }), level: level)
                        .equatable()

                    // Bombs, flames, the Balloms and the bomber: one Canvas.
                    Canvas { ctx, _ in
                        let ctr = { (p: Cell) in CGPoint(x: ox + (CGFloat(p.c) + 0.5) * cell, y: oy + (CGFloat(p.r) + 0.5) * cell) }
                        for b in bombs {
                            BBArt.bomb(ctx, at: ctr(b.cell), cell: cell, pulse: 1 + 0.12 * CGFloat(sin(b.fuse * 12)), spark: Int(b.fuse * 16) % 2 == 0)
                        }
                        BBArt.flames(ctx, cells: blast.map { ($0.r, $0.c) }, center: { ctr(Cell(r: $0, c: $1)) }, cell: cell)
                        for e in enemies {
                            BBArt.ballom(ctx, at: ctr(e.cell), size: cell * 0.8, lookRight: e.dir.c >= 0)
                        }
                        BBArt.bomber(ctx, at: ctr(player), size: cell * 0.86)
                    }
                    // Fill the whole play area: the Canvas already offsets its drawing by (ox, oy),
                    // so giving it a boardW×boardH frame + .position would double that offset and
                    // slide the grid/crates/blast off the sprites (invisible-block bug).
                    .frame(width: w, height: h)
                }
            }
            .padding(.horizontal, 6)

            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BBArt.backdrop(level))
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
    }

    private var controls: some View {
        HStack(spacing: 20) {
            VStack(spacing: isDemo ? 4 : 6) {
                dirBtn("chevron.up", Cell(r: -1, c: 0))
                HStack(spacing: isDemo ? 4 : 6) {
                    dirBtn("chevron.left", Cell(r: 0, c: -1))
                    dirBtn("chevron.down", Cell(r: 1, c: 0))
                    dirBtn("chevron.right", Cell(r: 0, c: 1))
                }
            }
            Button { dropBomb() } label: {
                BBBombIcon()
                    .frame(width: isDemo ? 30 : 36, height: isDemo ? 30 : 36)
                    .frame(width: isDemo ? 66 : 78, height: isDemo ? 42 : 56)
                    .background(BBKey(bomb: true, lit: demoBomb > 0))
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                    .scaleEffect(demoBomb > 0 ? 0.9 : 1)
            }
            .buttonStyle(BBPressStyle())
            .disabled(phase == .done && !isDemo)
        }
        .padding(.bottom, isDemo ? 6 : 8)
    }

    private func dirBtn(_ icon: String, _ d: Cell) -> some View {
        // In the demo the held arrow lights up (the script drives moveDir directly).
        let lit = isDemo && moveDir == d
        return Image(systemName: icon)
            .font(.system(size: isDemo ? 17 : 20, weight: .heavy)).foregroundStyle(lit ? Color(red: 0.2, green: 0.12, blue: 0) : .white)
            .frame(width: isDemo ? 46 : 56, height: isDemo ? 32 : 46)
            .background(BBKey(bomb: false, lit: lit))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(lit ? 0.9 : 1)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if phase == .play { moveDir = d } }
                .onEnded { _ in if moveDir == d { moveDir = nil } })
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.3))
                Capsule().fill(frac < 0.3 ? Color(red: 1, green: 0.32, blue: 0.24) : Color(red: 1, green: 0.8, blue: 0.3))
                    .frame(width: geo.size.width * frac)
            }
        }
    }

    // MARK: - Flow
    private func run() async {
        if !built { setup(); built = true }
        var last = Date(); let start = Date()
        loopTask = Task {
            while !Task.isCancelled && phase == .play {
                try? await Task.sleep(for: .seconds(0.033))
                let now = Date()
                let dt = min(0.08, now.timeIntervalSince(last)); last = now
                timeLeft = max(0, timeLimit - now.timeIntervalSince(start))
                if timeLeft <= 0 { fail(); break }
                tick(dt: dt)
            }
        }
    }

    private func setup() {
        player = Cell(r: 1, c: 1)
        let safe: Set<Cell> = [Cell(r: 1, c: 1), Cell(r: 1, c: 2), Cell(r: 2, c: 1)]
        var floor: [Cell] = []
        for r in 1..<(rows - 1) { for c in 1..<(cols - 1) where !hard(r, c) {
            floor.append(Cell(r: r, c: c))
        }}
        // Crates.
        var cr: Set<Cell> = []
        for cell in floor.shuffled() {
            if cr.count >= crateCount { break }
            if safe.contains(cell) { continue }
            cr.insert(cell)
        }
        crates = cr
        // Enemies — open floor far from the player.
        var es: [Enemy] = []
        let open = floor.filter { !cr.contains($0) && abs($0.r - 1) + abs($0.c - 1) >= 6 }.shuffled()
        for cell in open {
            if es.count >= enemyN { break }
            es.append(Enemy(cell: cell, dir: [Cell(r: 0, c: 1), Cell(r: 1, c: 0)].randomElement()!))
        }
        enemies = es
        bombs = []; blast = []; blastTimer = 0
        moveDir = nil; moveAcc = 0; enemyAcc = 0
        timeLeft = timeLimit; phase = .play
    }

    private func tick(dt: Double) {
        guard phase == .play else { return }

        // Blast lifetime.
        if blastTimer > 0 {
            blastTimer -= dt
            if blastTimer <= 0 { blast = [] }
        }

        // Bomb fuses.
        for i in bombs.indices { bombs[i].fuse -= dt }
        let exploding = bombs.filter { $0.fuse <= 0 }
        if !exploding.isEmpty {
            bombs.removeAll { $0.fuse <= 0 }
            for b in exploding { detonate(b.cell) }
        }

        // Player movement (hold to repeat).
        moveAcc += dt
        if let mv = moveDir, moveAcc >= 0.13 {
            moveAcc = 0
            let dest = Cell(r: player.r + mv.r, c: player.c + mv.c)
            if walkable(dest) { player = dest; SoundManager.shared.tap() }
        }
        if checkPlayerDead() { return }

        // Enemy movement.
        enemyAcc += dt
        if enemyAcc >= enemyStep {
            enemyAcc = 0
            for i in enemies.indices { moveEnemy(&enemies[i]) }
            _ = checkPlayerDead()
        }
    }

    private func dropBomb() {
        guard phase == .play else { return }
        guard !bombs.contains(where: { $0.cell == player }) else { return }
        bombs.append(Bomb(cell: player, fuse: fuse))
        SoundManager.shared.tap(); Haptics.tap()
    }

    private func detonate(_ center: Cell) {
        var cells: Set<Cell> = [center]
        let dirs = [Cell(r: -1, c: 0), Cell(r: 1, c: 0), Cell(r: 0, c: -1), Cell(r: 0, c: 1)]
        for d in dirs {
            for step in 1...bombRange {
                let cell = Cell(r: center.r + d.r * step, c: center.c + d.c * step)
                if hard(cell.r, cell.c) { break }
                cells.insert(cell)
                if crates.contains(cell) { crates.remove(cell); break }   // crate absorbs the blast
            }
        }
        blast = cells
        blastTimer = 0.35
        Haptics.warning(); SoundManager.shared.error()
        // Kill enemies caught in the blast.
        let before = enemies.count
        enemies.removeAll { cells.contains($0.cell) }
        if enemies.count < before { SoundManager.shared.tap() }
        // Chain any other bombs the blast reaches.
        let chained = bombs.filter { cells.contains($0.cell) }
        bombs.removeAll { cells.contains($0.cell) }
        for b in chained { detonate(b.cell) }
        if checkPlayerDead() { return }
        if enemies.isEmpty { win() }
    }

    private func moveEnemy(_ e: inout Enemy) {
        let dirs = [Cell(r: -1, c: 0), Cell(r: 1, c: 0), Cell(r: 0, c: -1), Cell(r: 0, c: 1)]
        // Chase: sometimes step toward the player if a move gets closer.
        if !isDemo && Double.random(in: 0...1) < chaseProb {
            let options = dirs.map { Cell(r: e.cell.r + $0.r, c: e.cell.c + $0.c) }
                .filter { walkable($0) }
            if let best = options.min(by: { manhattan($0, player) < manhattan($1, player) }) {
                e.dir = Cell(r: best.r - e.cell.r, c: best.c - e.cell.c)
                e.cell = best
                return
            }
        }
        // Wander: keep going straight if possible, else pick a random open turn. (Demo: always the
        // "straight on / turn back when blocked" roll, so the clip is fixed.)
        let ahead = Cell(r: e.cell.r + e.dir.r, c: e.cell.c + e.dir.c)
        if walkable(ahead) && (isDemo || Double.random(in: 0...1) > 0.2) { e.cell = ahead; return }
        let turns = dirs.map { Cell(r: e.cell.r + $0.r, c: e.cell.c + $0.c) }.filter { walkable($0) }
        let back = Cell(r: e.cell.r - e.dir.r, c: e.cell.c - e.dir.c)
        if let pick = isDemo ? ([back] + turns).first(where: { walkable($0) }) : turns.randomElement() {
            e.dir = Cell(r: pick.r - e.cell.r, c: pick.c - e.cell.c)
            e.cell = pick
        }
    }

    // MARK: - Demo (live manual clip)
    // A fixed level-1 arena (16 crates, two wanderers) played through the real `dropBomb`/`tick` at
    // the loop's fixed 1/30s. One enemy walks the top corridor straight at you: step right, BOMB,
    // duck back round the corner and down — it bumps the bomb, turns back into the blast. Then run
    // the left column and the middle row, BOMB beside the right-hand shaft and back off; the second
    // enemy is patrolling that shaft and walks into the fire. Both blasts also crack a crate.
    // Checked offline on a port of `tick`: both kills, no enemy ever within 3 cells, win at 4.3s;
    // the second drop works anywhere in frames 63–71 (67 = middle).
    private enum DemoInput { case hold(Cell), release, bomb }
    private static let demoScript: [(frame: Int, input: DemoInput)] = [
        (10, .hold(Cell(r: 0, c: 1))), (16, .release), (17, .bomb),
        (18, .hold(Cell(r: 0, c: -1))), (23, .release), (24, .hold(Cell(r: 1, c: 0))), (40, .release),
        (41, .hold(Cell(r: 0, c: 1))), (64, .release), (67, .bomb),
        (68, .hold(Cell(r: 0, c: -1))), (80, .release)
    ]
    private static let demoCrates: [(Int, Int)] = [
        (1, 9), (3, 3), (3, 7), (3, 9), (11, 9), (7, 1), (7, 3), (9, 2),
        (8, 3), (9, 5), (7, 5), (10, 5), (11, 3), (11, 6), (9, 7), (8, 1)
    ]

    private func runDemo() async {
        let dt = 1.0 / 30.0
        while !Task.isCancelled {
            player = Cell(r: 1, c: 1)
            crates = Set(Self.demoCrates.map { Cell(r: $0.0, c: $0.1) })
            enemies = [Enemy(cell: Cell(r: 1, c: 7), dir: Cell(r: 0, c: -1)),
                       Enemy(cell: Cell(r: 8, c: 9), dir: Cell(r: 1, c: 0))]
            bombs = []; blast = []; blastTimer = 0
            moveDir = nil; moveAcc = 0; enemyAcc = 0; demoBomb = 0
            timeLeft = timeLimit; phase = .play; built = true
            try? await Task.sleep(for: .seconds(0.5))
            var frame = 0, next = 0
            while !Task.isCancelled && phase == .play && frame < 600 {
                frame += 1
                while next < Self.demoScript.count && Self.demoScript[next].frame <= frame {
                    switch Self.demoScript[next].input {
                    case .hold(let d): moveDir = d
                    case .release: moveDir = nil
                    case .bomb: dropBomb(); demoBomb = 5
                    }
                    next += 1
                }
                if demoBomb > 0 { demoBomb -= 1 }
                tick(dt: dt)
                try? await Task.sleep(for: .seconds(0.033))
            }
            // Arena clear → the real win() ran (onWin is a no-op). Hold, then loop.
            moveDir = nil; demoBomb = 0
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    @discardableResult
    private func checkPlayerDead() -> Bool {
        if blast.contains(player) { fail(); return true }
        if enemies.contains(where: { $0.cell == player }) { fail(); return true }
        return false
    }

    private func manhattan(_ a: Cell, _ b: Cell) -> Int { abs(a.r - b.r) + abs(a.c - b.c) }

    private func win() {
        guard phase != .done else { return }
        phase = .done; loopTask?.cancel()
        Haptics.success(); SoundManager.shared.tap()
        onWin()
    }
    private func fail() {
        guard phase != .done else { return }
        phase = .done; loopTask?.cancel()
        SoundManager.shared.error()
        onFail()
    }
}

// MARK: - Bomberman art (after Hudson's Bomberman)

private enum BBArt {
    static func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    /// Floor pair per world: grass (1–2), desert (3–4), ice (5), volcanic rock (6–7).
    static func floor(_ level: Int) -> (Color, Color) {
        switch min(max(level, 1), 7) {
        case 1, 2: return (c(0.38, 0.66, 0.3), c(0.34, 0.6, 0.27))
        case 3, 4: return (c(0.88, 0.76, 0.5), c(0.83, 0.7, 0.45))
        case 5: return (c(0.78, 0.9, 0.96), c(0.7, 0.84, 0.93))
        default: return (c(0.3, 0.22, 0.22), c(0.26, 0.19, 0.19))
        }
    }

    static func backdrop(_ level: Int) -> Color {
        floor(level).0.mix(with: .black, by: 0.72)
    }

    /// A lit bomb: black ball, highlight, a fuse with a spark.
    static func bomb(_ ctx: GraphicsContext, at p: CGPoint, cell: CGFloat, pulse: CGFloat, spark: Bool) {
        let r = cell * 0.33 * pulse
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.9, y: p.y + r * 0.6, width: r * 1.8, height: r * 0.5)), with: .color(.black.opacity(0.3)))
        let ball = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r * 0.9, width: r * 2, height: r * 2))
        ctx.fill(ball, with: .radialGradient(Gradient(colors: [Color(white: 0.4), Color(white: 0.08)]), center: CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.4), startRadius: 0, endRadius: r * 1.3))
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.55, y: p.y - r * 0.6, width: r * 0.36, height: r * 0.26)), with: .color(.white.opacity(0.7)))
        ctx.fill(Path(roundedRect: CGRect(x: p.x + r * 0.2, y: p.y - r * 1.15, width: r * 0.4, height: r * 0.3), cornerRadius: r * 0.08), with: .color(Color(white: 0.3)))
        var fuse = Path()
        fuse.move(to: CGPoint(x: p.x + r * 0.4, y: p.y - r * 1.1))
        fuse.addQuadCurve(to: CGPoint(x: p.x + r * 0.9, y: p.y - r * 1.5), control: CGPoint(x: p.x + r * 0.5, y: p.y - r * 1.55))
        ctx.stroke(fuse, with: .color(c(0.85, 0.75, 0.55)), style: StrokeStyle(lineWidth: max(1, cell * 0.04), lineCap: .round))
        let tip = CGPoint(x: p.x + r * 0.9, y: p.y - r * 1.5)
        let sr = cell * (spark ? 0.14 : 0.09)
        ctx.fill(Path(ellipseIn: CGRect(x: tip.x - sr, y: tip.y - sr, width: sr * 2, height: sr * 2)),
                 with: .radialGradient(Gradient(colors: [.white, c(1, 0.8, 0.2), c(1, 0.4, 0.1).opacity(0)]), center: tip, startRadius: 0, endRadius: sr))
    }

    /// The blast as Bomberman's flame cross: orange arms bridging neighbouring blast cells, a
    /// white-hot core down the middle, a burst in each cell.
    static func flames(_ ctx: GraphicsContext, cells: [(Int, Int)], center: (Int, Int) -> CGPoint, cell: CGFloat) {
        guard !cells.isEmpty else { return }
        let set = Set(cells.map { $0.0 * 1000 + $0.1 })
        var outer = Path(), inner = Path()
        for (r, cc) in cells {
            let p = center(r, cc)
            outer.addEllipse(in: CGRect(x: p.x - cell * 0.42, y: p.y - cell * 0.42, width: cell * 0.84, height: cell * 0.84))
            inner.addEllipse(in: CGRect(x: p.x - cell * 0.24, y: p.y - cell * 0.24, width: cell * 0.48, height: cell * 0.48))
            for (dr, dc) in [(0, 1), (1, 0)] where set.contains((r + dr) * 1000 + cc + dc) {
                let q = center(r + dr, cc + dc)
                var arm = Path()
                arm.move(to: p); arm.addLine(to: q)
                outer.addPath(arm.strokedPath(StrokeStyle(lineWidth: cell * 0.7, lineCap: .round)))
                inner.addPath(arm.strokedPath(StrokeStyle(lineWidth: cell * 0.34, lineCap: .round)))
            }
        }
        ctx.fill(outer, with: .color(c(1, 0.45, 0.1)))
        ctx.fill(inner, with: .color(c(1, 0.9, 0.4)))
        var core = Path()
        for (r, cc) in cells {
            let p = center(r, cc)
            core.addEllipse(in: CGRect(x: p.x - cell * 0.12, y: p.y - cell * 0.12, width: cell * 0.24, height: cell * 0.24))
        }
        ctx.fill(core, with: .color(.white))
    }

    /// Ballom: an orange-pink balloon creature with big eyes.
    static func ballom(_ ctx: GraphicsContext, at p: CGPoint, size s: CGFloat, lookRight: Bool) {
        let r = s * 0.46
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.8, y: p.y + r * 0.7, width: r * 1.6, height: r * 0.4)), with: .color(.black.opacity(0.25)))
        let body = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 1.9))
        ctx.fill(body, with: .radialGradient(Gradient(colors: [c(1, 0.78, 0.62), c(0.98, 0.52, 0.34), c(0.8, 0.3, 0.2)]),
                                             center: CGPoint(x: p.x - r * 0.3, y: p.y - r * 0.4), startRadius: 0, endRadius: r * 1.3))
        ctx.stroke(body, with: .color(c(0.4, 0.12, 0.06)), lineWidth: max(1, s * 0.04))
        let look: CGFloat = lookRight ? 1 : -1
        for dx in [-0.34, 0.24] as [CGFloat] {
            let e = CGPoint(x: p.x + dx * r + look * r * 0.05, y: p.y - r * 0.18)
            ctx.fill(Path(ellipseIn: CGRect(x: e.x - r * 0.2, y: e.y - r * 0.26, width: r * 0.4, height: r * 0.52)), with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: e.x - r * 0.08 + look * r * 0.07, y: e.y - r * 0.12, width: r * 0.16, height: r * 0.24)), with: .color(.black))
        }
        var mouth = Path()
        mouth.move(to: CGPoint(x: p.x - r * 0.3, y: p.y + r * 0.35))
        mouth.addQuadCurve(to: CGPoint(x: p.x + r * 0.3, y: p.y + r * 0.35), control: CGPoint(x: p.x, y: p.y + r * 0.62))
        ctx.stroke(mouth, with: .color(c(0.4, 0.1, 0.06)), style: StrokeStyle(lineWidth: max(1, s * 0.05), lineCap: .round))
    }

    /// The bomber: a banana in Bomberman's white helmet with the pink antenna ball.
    static func bomber(_ ctx: GraphicsContext, at p: CGPoint, size s: CGFloat) {
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        g.scaleBy(x: s, y: s)
        let ink = c(0.14, 0.1, 0.04)
        g.fill(Path(ellipseIn: CGRect(x: -0.32, y: 0.36, width: 0.64, height: 0.14)), with: .color(.black.opacity(0.28)))
        var body = Path()
        body.move(to: CGPoint(x: -0.02, y: -0.36))
        body.addCurve(to: CGPoint(x: 0.1, y: 0.44), control1: CGPoint(x: -0.44, y: -0.18), control2: CGPoint(x: -0.4, y: 0.36))
        body.addCurve(to: CGPoint(x: -0.02, y: -0.36), control1: CGPoint(x: 0.14, y: 0.2), control2: CGPoint(x: 0.22, y: -0.16))
        body.closeSubpath()
        g.fill(body, with: .linearGradient(Gradient(colors: [c(1, 0.94, 0.45), c(0.95, 0.72, 0.14)]), startPoint: CGPoint(x: 0.1, y: 0), endPoint: CGPoint(x: -0.35, y: 0)))
        g.stroke(body, with: .color(ink), lineWidth: 0.04)
        let helmet = Path(ellipseIn: CGRect(x: -0.32, y: -0.52, width: 0.6, height: 0.5))
        g.fill(helmet, with: .radialGradient(Gradient(colors: [.white, Color(white: 0.8)]), center: CGPoint(x: -0.1, y: -0.4), startRadius: 0, endRadius: 0.4))
        g.stroke(helmet, with: .color(ink), lineWidth: 0.035)
        let face = Path(roundedRect: CGRect(x: -0.2, y: -0.34, width: 0.36, height: 0.22), cornerRadius: 0.1)
        g.fill(face, with: .color(c(1, 0.86, 0.72)))
        for x in [-0.1, 0.05] as [CGFloat] {
            g.fill(Path(roundedRect: CGRect(x: x - 0.025, y: -0.3, width: 0.05, height: 0.12), cornerRadius: 0.025), with: .color(ink))
        }
        var antenna = Path()
        antenna.move(to: CGPoint(x: -0.02, y: -0.52)); antenna.addLine(to: CGPoint(x: -0.02, y: -0.66))
        g.stroke(antenna, with: .color(ink), lineWidth: 0.04)
        g.fill(Path(ellipseIn: CGRect(x: -0.1, y: -0.8, width: 0.16, height: 0.16)), with: .color(c(1, 0.4, 0.6)))
    }
}

/// The arena: a checkered floor, bevelled stone pillars/walls (the logic's own `hard` cells) and
/// brick soft blocks. Redrawn only when a block is blasted.
private struct BBArena: View, Equatable {
    let size: CGSize
    let rows: Int
    let cols: Int
    let hard: Set<Int>
    let crates: Set<Int>
    let level: Int

    var body: some View {
        Canvas { ctx, _ in
            let cell = min(size.width / CGFloat(cols), size.height / CGFloat(rows))
            let ox = (size.width - cell * CGFloat(cols)) / 2
            let oy = (size.height - cell * CGFloat(rows)) / 2
            let (f0, f1) = BBArt.floor(level)
            var light = Path(), dark = Path(), stone = Path(), stoneLit = Path(), stoneDark = Path()
            var bricks = Path(), mortar = Path(), brickShade = Path()
            for r in 0..<rows {
                for c in 0..<cols {
                    let rect = CGRect(x: ox + CGFloat(c) * cell, y: oy + CGFloat(r) * cell, width: cell + 0.5, height: cell + 0.5)
                    let idx = r * cols + c
                    if hard.contains(idx) {
                        stone.addRect(rect)
                        stoneLit.addRect(CGRect(x: rect.minX, y: rect.minY, width: cell, height: cell * 0.14))
                        stoneLit.addRect(CGRect(x: rect.minX, y: rect.minY, width: cell * 0.12, height: cell))
                        stoneDark.addRect(CGRect(x: rect.minX, y: rect.maxY - cell * 0.16, width: cell, height: cell * 0.16))
                        stoneDark.addRect(CGRect(x: rect.maxX - cell * 0.14, y: rect.minY, width: cell * 0.14, height: cell))
                    } else {
                        if (r + c) % 2 == 0 { light.addRect(rect) } else { dark.addRect(rect) }
                        if crates.contains(idx) {
                            let b = rect.insetBy(dx: cell * 0.03, dy: cell * 0.03)
                            bricks.addRect(b)
                            brickShade.addRect(CGRect(x: b.minX, y: b.maxY - cell * 0.1, width: b.width, height: cell * 0.1))
                            for k in 1...3 {
                                let y = b.minY + b.height * CGFloat(k) / 4
                                mortar.move(to: CGPoint(x: b.minX, y: y)); mortar.addLine(to: CGPoint(x: b.maxX, y: y))
                            }
                            for k in 0..<4 {
                                let y0 = b.minY + b.height * CGFloat(k) / 4
                                let off: CGFloat = k % 2 == 0 ? 0.5 : 0.25
                                for fx in (k % 2 == 0 ? [off] : [off, off + 0.5]) {
                                    mortar.move(to: CGPoint(x: b.minX + b.width * fx, y: y0)); mortar.addLine(to: CGPoint(x: b.minX + b.width * fx, y: y0 + b.height / 4))
                                }
                            }
                        }
                    }
                }
            }
            ctx.fill(light, with: .color(f0))
            ctx.fill(dark, with: .color(f1))
            let stoneCol = level >= 6 ? Color(white: 0.3) : Color(white: 0.62)
            ctx.fill(stone, with: .color(stoneCol))
            ctx.fill(stoneLit, with: .color(.white.opacity(0.3)))
            ctx.fill(stoneDark, with: .color(.black.opacity(0.3)))
            let brick = level == 5 ? Color(red: 0.62, green: 0.78, blue: 0.9) : Color(red: 0.78, green: 0.44, blue: 0.24)
            ctx.fill(bricks, with: .color(brick))
            ctx.fill(brickShade, with: .color(.black.opacity(0.2)))
            ctx.stroke(mortar, with: .color(brick.mix(with: .black, by: 0.45)), lineWidth: max(1, cell * 0.035))
            ctx.stroke(bricks, with: .color(.black.opacity(0.45)), lineWidth: 1)
        }
    }
}

/// The HUD's Ballom.
private struct BBBallomIcon: View {
    var body: some View {
        Canvas { ctx, size in
            BBArt.ballom(ctx, at: CGPoint(x: size.width / 2, y: size.height * 0.46), size: min(size.width, size.height) * 1.02, lookRight: true)
        }
    }
}

/// The BOMB key's icon.
private struct BBBombIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let m = min(size.width, size.height)
            BBArt.bomb(ctx, at: CGPoint(x: size.width / 2 - m * 0.04, y: size.height / 2 + m * 0.1), cell: m * 1.2, pulse: 1, spark: true)
        }
    }
}

/// Keys: dark slate d-pad (banana yellow while pressed) and a yellow BOMB key.
private struct BBKey: View {
    let bomb: Bool
    let lit: Bool

    var body: some View {
        let colors: [Color] = bomb
            ? (lit ? [Color(white: 1), Color(red: 1, green: 0.88, blue: 0.5)] : [Color(red: 1, green: 0.85, blue: 0.35), Color(red: 0.95, green: 0.62, blue: 0.14)])
            : (lit ? [Color(red: 1, green: 0.9, blue: 0.45), Color(red: 0.95, green: 0.72, blue: 0.16)] : [Color(white: 0.34), Color(white: 0.18)])
        return ZStack {
            RoundedRectangle(cornerRadius: bomb ? 14 : 12).fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: bomb ? 14 : 12).strokeBorder(.black.opacity(0.5), lineWidth: 2)
            RoundedRectangle(cornerRadius: bomb ? 11 : 9).strokeBorder(.white.opacity(lit ? 0.9 : 0.25), lineWidth: 1).padding(3)
        }
    }
}

private struct BBPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.92 : 1)
    }
}
