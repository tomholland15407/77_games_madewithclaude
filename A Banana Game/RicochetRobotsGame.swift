//
//  RicochetRobotsGame.swift
//  A Banana Game
//
//  Brain — Ricochet Robots. Robots have no brakes: once nudged they slide in a straight line
//  until a wall or another robot stops them. Tap a robot to select it, then use the d-pad to send
//  it sliding. Steer the BANANA robot onto the ringed target cell, using the other robots as
//  movable blockers. Reset (↺) snaps everyone back so you can try another line for free — the only
//  way to lose is the clock.
//
//  Every board is generated then BFS-verified: the solver finds the true minimum number of slides
//  for the banana robot to reach the target and only deals boards whose optimum sits in the
//  level's window (so L1 is a short two-mover and L6–7 demand long, blocker-heavy plans). There's no
//  move limit — the puzzle is hard enough — so a wrong turn just means resetting and rethinking
//  before time runs out. Generation runs off-main behind the shared brainstorming banana.
//
//  Drawn as Alex Randolph's board game: ivory bevelled squares on a dark frame, black walls with
//  rounded ends, the target as the game's ringed planet in yellow, and glossy robot pieces (the
//  yellow banana robot with a stem for an antenna; blue, red, green and silver blockers) on blue
//  felt. The move counter and reset key are icons; the clock wears the sand-timer icon. The board
//  is an Equatable view; the robots stay views so their slides still animate.
//

import SwiftUI

enum RicochetRobotsGame {
    static let definition = GameDefinition(
        id: "ricochet-robots",
        title: "Slide Bots",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Robots slide until they hit a wall or another robot.",
                "Tap a robot to select it, then use the d-pad to send it sliding.",
                "Get the banana robot onto the ringed target cell, using the others as blockers.",
                "Tap reset (↺) to snap everyone back; run out of time and you're back to level 1.",
            ],
            bulletsVI: [
                "Robot trượt cho đến khi gặp tường hoặc robot khác.",
                "Chạm một robot để chọn, rồi dùng d-pad để cho nó trượt.",
                "Đưa robot chuối vào ô mục tiêu có vòng, dùng các robot khác làm vật chặn.",
                "Chạm đặt lại (↺) để đưa mọi người về chỗ cũ; hết giờ sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(RicochetRobotsView(level: level, onWin: onWin, onFail: onFail))
        },
        prefetch: { level in RicochetRobotsView(level: level, onWin: {}, onFail: {}).prefetchBoard() }
    )
}

// MARK: - Model / solver (pure, off-main)

private struct RRBoard: Sendable {
    let n: Int
    let walls: Set<Int>       // encoded (cell*4 + dir); both sides stored
    let robots: [Int]         // index 0 = banana (target) robot, rest are blockers
    let targetCell: Int
}

private enum RRGen {
    // 0 = up, 1 = right, 2 = down, 3 = left
    static let dirVecs: [(Int, Int)] = [(-1, 0), (0, 1), (1, 0), (0, -1)]

    static func addWall(_ walls: inout Set<Int>, _ r: Int, _ c: Int, _ dir: Int, _ n: Int) {
        walls.insert((r * n + c) * 4 + dir)
        let (dr, dc) = dirVecs[dir]
        let nr = r + dr, nc = c + dc
        if nr >= 0, nr < n, nc >= 0, nc < n {
            walls.insert((nr * n + nc) * 4 + (dir + 2) % 4)
        }
    }

    static func slide(from: Int, dir: Int, blockers: Set<Int>, walls: Set<Int>, n: Int) -> Int {
        var pos = from
        let (dr, dc) = dirVecs[dir]
        while true {
            if walls.contains(pos * 4 + dir) { break }
            let r = pos / n, c = pos % n
            let nr = r + dr, nc = c + dc
            if nr < 0 || nr >= n || nc < 0 || nc >= n { break }
            let np = nr * n + nc
            if blockers.contains(np) { break }
            pos = np
        }
        return pos
    }

    /// Minimum number of slides for robot 0 to reach `targetCell`. Non-target robots are treated
    /// as interchangeable blockers to keep the state space small. Returns nil if unsolved in-budget.
    static func optimalMoves(start: [Int], targetCell: Int, walls: Set<Int>, n: Int, cap: Int) -> Int? {
        let t0 = start[0]
        let b0 = Array(start.dropFirst()).sorted()
        if t0 == targetCell { return 0 }
        func key(_ t: Int, _ b: [Int]) -> String { "\(t)|" + b.map(String.init).joined(separator: ",") }
        var seen: Set<String> = [key(t0, b0)]
        var queue: [(Int, [Int], Int)] = [(t0, b0, 0)]
        var head = 0, expanded = 0
        while head < queue.count {
            let (t, b, d) = queue[head]; head += 1
            expanded += 1
            if expanded > cap { return nil }
            let bset = Set(b)
            // move the target robot
            for dir in 0..<4 {
                let nt = slide(from: t, dir: dir, blockers: bset, walls: walls, n: n)
                if nt != t {
                    if nt == targetCell { return d + 1 }
                    let k = key(nt, b)
                    if !seen.contains(k) { seen.insert(k); queue.append((nt, b, d + 1)) }
                }
            }
            // move a blocker
            for i in 0..<b.count {
                var others = bset; others.remove(b[i]); others.insert(t)
                for dir in 0..<4 {
                    let np = slide(from: b[i], dir: dir, blockers: others, walls: walls, n: n)
                    if np != b[i] {
                        var nb = b; nb[i] = np; nb.sort()
                        let k = key(t, nb)
                        if !seen.contains(k) { seen.insert(k); queue.append((t, nb, d + 1)) }
                    }
                }
            }
        }
        return nil
    }

    static func generate(n: Int, robotCount: Int, wallCount: Int,
                         minOpt: Int, maxOpt: Int) -> RRBoard {
        var fallback: RRBoard?
        for _ in 0..<500 {
            var walls = Set<Int>()
            for _ in 0..<wallCount {
                addWall(&walls, Int.random(in: 0..<n), Int.random(in: 0..<n), Int.random(in: 0..<4), n)
            }
            let targetCell = Int.random(in: 0..<n * n)
            // ensure a robot can stop ON the target: give it at least one adjacent wall
            addWall(&walls, targetCell / n, targetCell % n, Int.random(in: 0..<4), n)

            var cells = Array(0..<n * n).shuffled()
            cells.removeAll { $0 == targetCell }
            guard cells.count >= robotCount else { continue }
            let start = Array(cells.prefix(robotCount))

            guard let opt = optimalMoves(start: start, targetCell: targetCell,
                                         walls: walls, n: n, cap: 120_000) else { continue }
            let board = RRBoard(n: n, walls: walls, robots: start, targetCell: targetCell)
            if opt >= minOpt && opt <= maxOpt { return board }
            if opt >= 1 && opt <= maxOpt { fallback = board }
        }
        return fallback ?? RRBoard(n: n, walls: [], robots: Array(0..<robotCount),
                                   targetCell: n * n - 1)
    }
}

// MARK: - View

struct RicochetRobotsView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void
    @Environment(\.isDemo) private var isDemo

    private var n: Int { [6, 6, 7, 7, 8, 8, 8][min(level, 7) - 1] }
    private var robotCount: Int { [2, 3, 3, 4, 4, 4, 5][min(level, 7) - 1] }
    private var wallCount: Int { [4, 5, 6, 8, 9, 11, 13][min(level, 7) - 1] }
    private var minOpt: Int { [2, 3, 4, 4, 5, 5, 6][min(level, 7) - 1] }
    private var maxOpt: Int { [5, 6, 7, 8, 9, 10, 11][min(level, 7) - 1] }
    private var timeLimit: Double { [55, 60, 65, 70, 75, 80, 80][min(level, 7) - 1] }

    private let skyTop = Color(red: 0.10, green: 0.13, blue: 0.20)
    private let skyBottom = Color(red: 0.04, green: 0.05, blue: 0.10)
    private let blockerColors: [Color] = [
        Color(red: 0.22, green: 0.46, blue: 0.92),
        Color(red: 0.9, green: 0.24, blue: 0.22),
        Color(red: 0.22, green: 0.68, blue: 0.32),
        Color(red: 0.72, green: 0.74, blue: 0.8),
    ]

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var boardN = 0
    @State private var walls: Set<Int> = []
    @State private var robots: [Int] = []
    @State private var startRobots: [Int] = []
    @State private var targetCell = 0
    @State private var moves = 0
    @State private var selected = 0
    @State private var timeLeft = 0.0
    @State private var ready = false
    @State private var shakeTick = 0
    @State private var loopTask: Task<Void, Never>?
    @State private var demoKey: String? = nil       // demo: control being pressed (arrow icon / "reset")
    @State private var demoFinger: Int? = nil       // demo: robot being tapped

    var body: some View {
        Group {
            if ready { gameBody } else { BrainstormingView(skyTop: skyTop, skyBottom: skyBottom) }
        }
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
    }

    private var gameBody: some View {
        VStack(spacing: isDemo ? 6 : 10) {
            header
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height) * 0.98
                let cell = boardN > 0 ? side / CGFloat(boardN) : 0
                let ox = (geo.size.width - cell * CGFloat(boardN)) / 2
                let oy = (geo.size.height - cell * CGFloat(boardN)) / 2
                ZStack {
                    // The board, its walls and the target never change during a puzzle: drawn once.
                    RRBoardArt(size: geo.size, n: boardN, walls: walls, target: targetCell).equatable()
                    ForEach(robots.indices, id: \.self) { i in
                        robotView(i, cell: cell)
                            .position(x: ox + (CGFloat(robots[i] % boardN) + 0.5) * cell,
                                      y: oy + (CGFloat(robots[i] / boardN) + 0.5) * cell)
                    }
                    if let f = demoFinger, f < robots.count, boardN > 0 {
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.system(size: cell * 0.5))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 3)
                            .position(x: ox + (CGFloat(robots[f] % boardN) + 0.8) * cell,
                                      y: oy + (CGFloat(robots[f] / boardN) + 0.88) * cell)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .screenShake(shakeTick, amount: 5)
            }
            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 8)
        .background(RRTable().equatable())
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
    }

    /// Slides so far (an arrow to the wall and the count), the reset key, and the sand timer.
    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.to.line")
                        .font(.system(size: isDemo ? 13 : 16, weight: .bold))
                        .foregroundStyle(RRArt.cream.opacity(0.75))
                    Text("\(moves)")
                        .font(.system(size: isDemo ? 16 : 20, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                Spacer()
                Button { resetPositions() } label: {
                    let pressed = isDemo && demoKey == "reset"
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: isDemo ? 15 : 19, weight: .heavy))
                        .foregroundStyle(pressed ? RRArt.ink : .white)
                        .frame(width: isDemo ? 64 : 88, height: isDemo ? 30 : 40)
                        .background(RRKey(lit: pressed, radius: 12))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                        .scaleEffect(pressed ? 0.9 : 1)
                }
                .buttonStyle(RRPressStyle())
            }
            .padding(.horizontal, 24)
            if !isDemo {
                HStack(spacing: 8) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(RRArt.cream.opacity(0.75))
                    timeBar.frame(height: 6)
                }
                .padding(.horizontal, 40)
            }
        }
        .padding(.top, 4)
    }

    private var controls: some View {
        VStack(spacing: isDemo ? 4 : 8) {
            arrow("chevron.up", 0)
            HStack(spacing: isDemo ? 4 : 8) {
                arrow("chevron.left", 3)
                arrow("chevron.down", 2)
                arrow("chevron.right", 1)
            }
        }
        .padding(.bottom, isDemo ? 2 : 6)
    }

    private func arrow(_ icon: String, _ dir: Int) -> some View {
        let pressed = isDemo && demoKey == icon
        return Button { move(dir) } label: {
            Image(systemName: icon)
                .font(.system(size: isDemo ? 18 : 22, weight: .heavy))
                .foregroundStyle(pressed ? RRArt.ink : .white)
                .frame(width: isDemo ? 50 : 66, height: isDemo ? 32 : 50)
                .background(RRKey(lit: pressed, radius: 14))
                .contentShape(RoundedRectangle(cornerRadius: 14))
                .scaleEffect(pressed ? 0.9 : 1)
        }
        .buttonStyle(RRPressStyle())
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(frac < 0.3 ? Color(red: 1, green: 0.32, blue: 0.28) : RRArt.sand).frame(width: geo.size.width * frac)
            }
        }
    }

    private func robotView(_ i: Int, cell: CGFloat) -> some View {
        let isTarget = i == 0
        let col = isTarget ? RRArt.banana : blockerColors[(i - 1) % blockerColors.count]
        let isSel = selected == i
        return RRRobot(color: col, selected: isSel, banana: isTarget)
            .frame(width: cell * 0.78, height: cell * 0.78)
            .scaleEffect(isSel ? 1.06 : 1)
            .contentShape(Rectangle())
            .onTapGesture { select(i) }
    }

    // MARK: Input
    private func select(_ i: Int) {
        guard phase == .play else { return }
        selected = i
        SoundManager.shared.tap(); Haptics.tap()
    }

    private func move(_ dir: Int) {
        guard phase == .play, selected < robots.count else { return }
        var others = Set(robots); others.remove(robots[selected])
        let np = RRGen.slide(from: robots[selected], dir: dir, blockers: others, walls: walls, n: boardN)
        guard np != robots[selected] else { return }
        withAnimation(.easeOut(duration: 0.16)) { robots[selected] = np }
        moves += 1
        SoundManager.shared.tap(); Haptics.tap()
        if robots[0] == targetCell { win() }
    }

    private func resetPositions() {
        guard phase == .play else { return }
        withAnimation(.easeInOut(duration: 0.2)) { robots = startRobots }
        moves = 0
        selected = 0
        SoundManager.shared.tap(); Haptics.tap()
    }

    // MARK: - Demo (live manual clip)
    // A fixed level-1 board (6×6, two robots, four walls + the target's own wall) whose optimum is
    // 3 slides — and the banana robot can NEVER reach the ringed cell on its own (checked offline by
    // BFS), so the blocker is the whole puzzle. The clip tells the three rules in order: the banana
    // slides ▼ ▶ and sails straight over the target (no brakes), ↺ snaps everyone back, then the
    // blue robot slides ▶ to the far wall as a backstop and the same ▼ ▶ now stops dead on the ring.
    //   . . B . . .        B banana (0,2)   b blue (3,0)   T target (3,4)
    //   . . . . . .        walls: under (2,0), under (3,2), under the target, right of (3,5)
    //   . . . . . .               and right of (5,2)
    //   b . . . T .
    private static let demoWalls: [(r: Int, c: Int, dir: Int)] =
        [(2, 0, 2), (3, 2, 2), (3, 4, 2), (3, 5, 1), (5, 2, 1)]
    private enum DemoStep { case tap(Int), slide(Int), reset }
    private static let demoSteps: [DemoStep] =
        [.tap(0), .slide(2), .slide(1), .reset, .tap(1), .slide(1), .tap(0), .slide(2), .slide(1)]
    private static let arrowIcons = ["chevron.up", "chevron.right", "chevron.down", "chevron.left"]

    private func runDemo() async {
        while !Task.isCancelled {
            var w = Set<Int>()
            for wall in Self.demoWalls { RRGen.addWall(&w, wall.r, wall.c, wall.dir, 6) }
            boardN = 6
            walls = w
            robots = [0 * 6 + 2, 3 * 6 + 0]
            startRobots = robots
            targetCell = 3 * 6 + 4
            moves = 0; selected = 0
            demoKey = nil; demoFinger = nil
            timeLeft = timeLimit
            phase = .play
            ready = true
            try? await Task.sleep(for: .seconds(0.8))
            for step in Self.demoSteps {
                guard !Task.isCancelled else { return }
                switch step {
                case .tap(let i):
                    demoFinger = i
                    try? await Task.sleep(for: .seconds(0.3))
                    select(i)
                    try? await Task.sleep(for: .seconds(0.25))
                    demoFinger = nil
                case .slide(let dir):
                    demoKey = Self.arrowIcons[dir]
                    move(dir)
                    try? await Task.sleep(for: .seconds(0.2))
                    demoKey = nil
                    try? await Task.sleep(for: .seconds(0.3))
                case .reset:
                    try? await Task.sleep(for: .seconds(0.4))   // let the overshoot sink in
                    demoKey = "reset"
                    resetPositions()
                    try? await Task.sleep(for: .seconds(0.2))
                    demoKey = nil
                    try? await Task.sleep(for: .seconds(0.4))
                }
            }
            // Banana on the ring → the real win() ran (onWin is a no-op). Hold, then loop.
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    // MARK: Flow
    /// Hands this level's board build to `BoardCache` so it can run during the countdown.
    func prefetchBoard() {
        let params = (n, robotCount, wallCount, minOpt, maxOpt)
        BoardCache.prefetch(boardKey) { RRGen.generate(n: params.0, robotCount: params.1, wallCount: params.2, minOpt: params.3, maxOpt: params.4) }
    }
    private var boardKey: String { BoardCache.key("ricochet-robots", level: level) }

    private func run() async {
        let params = (n, robotCount, wallCount, minOpt, maxOpt)
        let t0 = Date()
        let board = await BoardCache.take(boardKey) { RRGen.generate(n: params.0, robotCount: params.1, wallCount: params.2, minOpt: params.3, maxOpt: params.4) }
        guard !Task.isCancelled else { return }
        await BoardCache.holdBrainstorm(since: t0, minimum: 0.7)
        guard !Task.isCancelled else { return }

        boardN = board.n
        walls = board.walls
        robots = board.robots
        startRobots = board.robots
        targetCell = board.targetCell
        moves = 0
        selected = 0
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

// MARK: - Board-game art (after Alex Randolph's Ricochet Robots)

private enum RRArt {
    static let banana = Color(red: 1, green: 0.84, blue: 0.2)
    static let cream = Color(red: 0.96, green: 0.94, blue: 0.86)
    static let sand = Color(red: 0.96, green: 0.8, blue: 0.46)
    static let ink = Color(red: 0.14, green: 0.1, blue: 0.02)

    /// The yellow ringed-planet target chip (the board game's planet symbol, in the banana's colour).
    static func planet(_ ctx: GraphicsContext, at c: CGPoint, cell: CGFloat) {
        let r = cell * 0.2
        var back = Path()
        back.addArc(center: .zero, radius: 1, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        var front = Path()
        front.addArc(center: .zero, radius: 1, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        let ringT = CGAffineTransform(scaleX: r * 1.9, y: r * 0.62).concatenating(CGAffineTransform(rotationAngle: -0.35)).concatenating(CGAffineTransform(translationX: c.x, y: c.y))
        let ringCol = Color(red: 0.86, green: 0.55, blue: 0.08)
        ctx.stroke(back.applying(ringT), with: .color(ringCol), lineWidth: max(1.5, cell * 0.05))
        let ball = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.fill(ball, with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.55), banana, Color(red: 0.9, green: 0.62, blue: 0.1)]),
                                             center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4), startRadius: 0, endRadius: r * 1.4))
        ctx.stroke(ball, with: .color(ringCol.mix(with: .black, by: 0.3)), lineWidth: max(1, cell * 0.025))
        ctx.stroke(front.applying(ringT), with: .color(ringCol), lineWidth: max(1.5, cell * 0.05))
    }
}

/// The board: ivory squares with a bevel, black walls with rounded ends, a dark frame, and the target
/// square tinted with its planet. Equatable, so it's drawn once per puzzle.
private struct RRBoardArt: View, Equatable {
    let size: CGSize
    let n: Int
    let walls: Set<Int>
    let target: Int

    var body: some View {
        Canvas { ctx, _ in
            guard n > 0 else { return }
            let side = min(size.width, size.height) * 0.98
            let cell = side / CGFloat(n)
            let ox = (size.width - side) / 2, oy = (size.height - side) / 2
            let board = CGRect(x: ox, y: oy, width: side, height: side)
            ctx.fill(Path(roundedRect: board.insetBy(dx: -5, dy: -5), cornerRadius: 7), with: .color(Color(red: 0.12, green: 0.12, blue: 0.16)))
            ctx.fill(Path(board), with: .color(Color(red: 0.62, green: 0.61, blue: 0.58)))
            var squares = Path(), bevels = Path()
            for r in 0..<n {
                for c in 0..<n {
                    let rect = CGRect(x: ox + CGFloat(c) * cell + 0.6, y: oy + CGFloat(r) * cell + 0.6, width: cell - 1.2, height: cell - 1.2)
                    squares.addRect(rect)
                    bevels.addRect(rect.insetBy(dx: cell * 0.12, dy: cell * 0.12))
                }
            }
            ctx.fill(squares, with: .color(Color(red: 0.89, green: 0.88, blue: 0.84)))
            ctx.stroke(bevels, with: .color(Color(red: 0.76, green: 0.75, blue: 0.71)), lineWidth: max(1, cell * 0.025))
            // Target square.
            let tr = target / n, tc = target % n
            let tRect = CGRect(x: ox + CGFloat(tc) * cell + 0.6, y: oy + CGFloat(tr) * cell + 0.6, width: cell - 1.2, height: cell - 1.2)
            ctx.fill(Path(tRect), with: .color(Color(red: 1, green: 0.95, blue: 0.72)))
            ctx.stroke(Path(tRect.insetBy(dx: cell * 0.06, dy: cell * 0.06)), with: .color(RRArt.banana), lineWidth: max(1.5, cell * 0.045))
            RRArt.planet(ctx, at: CGPoint(x: tRect.midX, y: tRect.midY), cell: cell)
            // Walls.
            var segs = Path()
            let ext = cell * 0.05
            for encoded in walls {
                let dir = encoded % 4, idx = encoded / 4
                let r = idx / n, c = idx % n
                let x0 = ox + CGFloat(c) * cell, y0 = oy + CGFloat(r) * cell
                switch dir {
                case 0: segs.move(to: CGPoint(x: x0 - ext, y: y0)); segs.addLine(to: CGPoint(x: x0 + cell + ext, y: y0))
                case 1: segs.move(to: CGPoint(x: x0 + cell, y: y0 - ext)); segs.addLine(to: CGPoint(x: x0 + cell, y: y0 + cell + ext))
                case 2: segs.move(to: CGPoint(x: x0 - ext, y: y0 + cell)); segs.addLine(to: CGPoint(x: x0 + cell + ext, y: y0 + cell))
                default: segs.move(to: CGPoint(x: x0, y: y0 - ext)); segs.addLine(to: CGPoint(x: x0, y: y0 + cell + ext))
                }
            }
            ctx.stroke(segs, with: .color(Color(red: 0.1, green: 0.09, blue: 0.12)), style: StrokeStyle(lineWidth: cell * 0.11, lineCap: .round))
            ctx.stroke(segs, with: .color(.white.opacity(0.12)), style: StrokeStyle(lineWidth: cell * 0.03, lineCap: .round))
            ctx.stroke(Path(board), with: .color(Color(red: 0.1, green: 0.09, blue: 0.12)), lineWidth: cell * 0.09)
        }
    }
}

/// A robot piece seen from above-front: a glossy body, a dome head with a visor and two lit eyes,
/// an antenna (a stem, for the banana robot). The selected one stands in a white ring.
private struct RRRobot: View {
    let color: Color
    let selected: Bool
    let banana: Bool

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let cx = size.width / 2, cy = size.height / 2
            if selected {
                ctx.fill(Path(ellipseIn: CGRect(x: cx - s * 0.52, y: cy - s * 0.52, width: s * 1.04, height: s * 1.04)),
                         with: .radialGradient(Gradient(colors: [color.opacity(0.55), color.opacity(0)]), center: CGPoint(x: cx, y: cy), startRadius: s * 0.3, endRadius: s * 0.52))
                ctx.stroke(Path(ellipseIn: CGRect(x: cx - s * 0.47, y: cy - s * 0.47, width: s * 0.94, height: s * 0.94)), with: .color(.white), lineWidth: max(1.5, s * 0.06))
            }
            let ink = Color(red: 0.08, green: 0.08, blue: 0.1)
            ctx.fill(Path(ellipseIn: CGRect(x: cx - s * 0.36, y: cy + s * 0.22, width: s * 0.72, height: s * 0.2)), with: .color(.black.opacity(0.3)))
            // Body.
            let body = Path(roundedRect: CGRect(x: cx - s * 0.3, y: cy - s * 0.06, width: s * 0.6, height: s * 0.38), cornerRadius: s * 0.14)
            ctx.fill(body, with: .linearGradient(Gradient(colors: [color.mix(with: .white, by: 0.25), color, color.mix(with: .black, by: 0.35)]),
                                                 startPoint: CGPoint(x: cx - s * 0.3, y: 0), endPoint: CGPoint(x: cx + s * 0.3, y: 0)))
            ctx.stroke(body, with: .color(ink), lineWidth: max(1, s * 0.035))
            // Head.
            let head = Path(ellipseIn: CGRect(x: cx - s * 0.26, y: cy - s * 0.4, width: s * 0.52, height: s * 0.44))
            ctx.fill(head, with: .radialGradient(Gradient(colors: [color.mix(with: .white, by: 0.45), color, color.mix(with: .black, by: 0.3)]),
                                                 center: CGPoint(x: cx - s * 0.08, y: cy - s * 0.3), startRadius: 0, endRadius: s * 0.36))
            ctx.stroke(head, with: .color(ink), lineWidth: max(1, s * 0.035))
            let visor = Path(roundedRect: CGRect(x: cx - s * 0.2, y: cy - s * 0.24, width: s * 0.4, height: s * 0.13), cornerRadius: s * 0.065)
            ctx.fill(visor, with: .color(Color(red: 0.1, green: 0.12, blue: 0.16)))
            for dx in [-0.09, 0.09] as [CGFloat] {
                ctx.fill(Path(ellipseIn: CGRect(x: cx + dx * s - s * 0.04, y: cy - s * 0.215, width: s * 0.08, height: s * 0.075)),
                         with: .color(Color(red: 0.6, green: 0.95, blue: 1)))
            }
            if banana {
                var stem = Path()
                stem.move(to: CGPoint(x: cx + s * 0.02, y: cy - s * 0.38))
                stem.addQuadCurve(to: CGPoint(x: cx + s * 0.12, y: cy - s * 0.5), control: CGPoint(x: cx + s * 0.02, y: cy - s * 0.48))
                ctx.stroke(stem, with: .color(Color(red: 0.45, green: 0.3, blue: 0.1)), style: StrokeStyle(lineWidth: max(1.5, s * 0.07), lineCap: .round))
            } else {
                var mast = Path()
                mast.move(to: CGPoint(x: cx, y: cy - s * 0.39)); mast.addLine(to: CGPoint(x: cx, y: cy - s * 0.48))
                ctx.stroke(mast, with: .color(ink), lineWidth: max(1, s * 0.035))
                ctx.fill(Path(ellipseIn: CGRect(x: cx - s * 0.045, y: cy - s * 0.53, width: s * 0.09, height: s * 0.09)), with: .color(color.mix(with: .white, by: 0.3)))
            }
            // Wheels peeking out below.
            for dx in [-0.2, 0.2] as [CGFloat] {
                ctx.fill(Path(roundedRect: CGRect(x: cx + dx * s - s * 0.08, y: cy + s * 0.28, width: s * 0.16, height: s * 0.08), cornerRadius: s * 0.03),
                         with: .color(Color(white: 0.18)))
            }
        }
    }
}

/// The table under the board: dark blue felt.
private struct RRTable: View, Equatable {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .radialGradient(Gradient(colors: [Color(red: 0.13, green: 0.17, blue: 0.3), Color(red: 0.05, green: 0.07, blue: 0.14)]),
                                           center: CGPoint(x: size.width / 2, y: size.height * 0.4), startRadius: 20, endRadius: max(size.width, size.height) * 0.75))
            var weave = Path()
            var y: CGFloat = 0
            while y < size.height {
                weave.move(to: CGPoint(x: 0, y: y)); weave.addLine(to: CGPoint(x: size.width, y: y))
                y += 3
            }
            ctx.stroke(weave, with: .color(.white.opacity(0.025)), lineWidth: 1)
        }
    }
}

/// Keys: slate, banana yellow while pressed.
private struct RRKey: View {
    let lit: Bool
    let radius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius)
                .fill(LinearGradient(colors: lit ? [Color(red: 1, green: 0.9, blue: 0.45), Color(red: 0.95, green: 0.72, blue: 0.16)]
                                                 : [Color(red: 0.32, green: 0.36, blue: 0.48), Color(red: 0.18, green: 0.21, blue: 0.3)],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: radius).strokeBorder(Color.black.opacity(0.5), lineWidth: 2)
            RoundedRectangle(cornerRadius: radius - 3).strokeBorder(.white.opacity(lit ? 0.9 : 0.16), lineWidth: 1.2).padding(3)
        }
    }
}

private struct RRPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.92 : 1)
    }
}
