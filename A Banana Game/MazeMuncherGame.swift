//
//  MazeMuncherGame.swift
//  A Banana Game
//
//  Reflex — a Pac-Man homage. Steer a pixel muncher around a maze with four
//  on-screen buttons, gobbling every pellet while a ghost hunts you down. Clear
//  the board before the timer to win. Get caught by the ghost — or run out of
//  time — and you fail back to level 1. 7 levels: the ghost gets faster and the
//  clock tighter, until by 6–7 it's practically on your tail from the start.
//
//  Drawn like the arcade original: a black screen, thin blue double-line walls and outlined
//  blocks, small peach pellets, a yellow muncher whose wedge mouth chomps toward where he's
//  heading, and the red chaser ghost with a wavy skirt and eyes that look where it's going. The
//  pellet count is in the arcade's white pixel digits, the level shows as the bonus-fruit row, and
//  the d-pad is a black arcade panel with blue-rimmed keys.
//

import SwiftUI

enum MazeMuncherGame {
    static let definition = GameDefinition(
        id: "maze-muncher",
        title: "Maze Muncher",
        emoji: "🍌",
        genre: .reflex,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Steer the muncher with the d-pad and gobble every pellet in the maze.",
                "A ghost hunts you the whole time.",
                "Clear the board before the clock runs out.",
                "Get caught by the ghost, or run out of time, and you're back to level 1.",
            ],
            bulletsVI: [
                "Điều khiển kẻ ăn bằng d-pad và đớp hết mọi viên trong mê cung.",
                "Một con ma săn bạn suốt cả màn.",
                "Dọn sạch bàn trước khi hết giờ.",
                "Bị ma bắt, hoặc hết giờ, sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(MazeMuncherView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct MazeMuncherView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    // MARK: Difficulty
    private let muncherStep = 0.16
    /// Seconds per ghost step — the ghost speeds up (and out-paces you late).
    private var ghostStep: Double { [0.30, 0.26, 0.22, 0.19, 0.16, 0.14, 0.115][min(level, 7) - 1] }
    private var timeLimit: Double { [58, 55, 52, 49, 46, 43, 40][min(level, 7) - 1] }

    // The maze. `#` wall, `.` pellet, `P` muncher start, `G` ghost start.
    // Interior pillars are isolated, so every corridor stays connected.
    private let maze = [
        "#############",
        "#...........#",
        "#.#.#.#.#.#.#",
        "#...........#",
        "#.#.#.#.#.#.#",
        "#.....G.....#",
        "#.#.#.#.#.#.#",
        "#...........#",
        "#.#.#.#.#.#.#",
        "#...........#",
        "#.....P.....#",
        "#############"
    ]
    private var cols: Int { maze[0].count }
    private var rows: Int { maze.count }

    // MARK: State
    private struct Cell: Equatable { var c: Int; var r: Int }

    @State private var walls: Set<Int> = []
    @State private var pellets: Set<Int> = []
    @State private var totalPellets = 0
    @State private var muncher = Cell(c: 1, r: 1)
    @State private var ghost = Cell(c: 1, r: 1)
    @State private var dir = (dc: 0, dr: 0)
    @State private var pendingDir: (dc: Int, dr: Int)? = nil
    @State private var ghostDir = (dc: 0, dr: 0)
    @State private var facing = 0.0            // muncher rotation, degrees
    @State private var chomp = false
    @State private var timeLeft = 0.0
    @State private var done = false
    @State private var loopTask: Task<Void, Never>?
    @State private var demoPress: (dc: Int, dr: Int)? = nil   // demo: d-pad arrow being pressed

    private func key(_ c: Int, _ r: Int) -> Int { c * 100 + r }
    private var eaten: Int { totalPellets - pellets.count }

    var body: some View {
        VStack(spacing: isDemo ? 4 : 8) {
            PacDigits(text: "\(eaten)/\(totalPellets)", pixel: isDemo ? 2 : 3)
                .equatable()
                .frame(height: isDemo ? 14 : 21)
                .padding(.top, isDemo ? 6 : 0)
            if !isDemo { timeBar.frame(height: 6).padding(.horizontal, 48) }

            GeometryReader { geo in
                let cell = min(geo.size.width / CGFloat(cols), geo.size.height / CGFloat(rows))
                let boardW = cell * CGFloat(cols)
                let boardH = cell * CGFloat(rows)
                let ox = (geo.size.width - boardW) / 2
                let oy = (geo.size.height - boardH) / 2
                let px: (Int) -> CGFloat = { ox + (CGFloat($0) + 0.5) * cell }
                let py: (Int) -> CGFloat = { oy + (CGFloat($0) + 0.5) * cell }

                ZStack(alignment: .topLeading) {
                    // Walls (static) and pellets.
                    PacMaze(walls: walls, cols: cols, rows: rows, cell: cell, ox: ox, oy: oy).equatable()
                    Canvas { ctx, _ in
                        let d = cell * 0.22
                        for k in pellets {
                            let rect = CGRect(x: px(k / 100) - d / 2, y: py(k % 100) - d / 2, width: d, height: d)
                            ctx.fill(Path(roundedRect: rect, cornerRadius: d * 0.2), with: .color(PacArt.pellet))
                        }
                    }
                    .allowsHitTesting(false)

                    // The muncher: a yellow wedge whose mouth opens and shuts once per step.
                    PacMouthShape(open: chomp ? 0.08 : 1)
                        .fill(PacArt.yellow)
                        .frame(width: cell * 1.12, height: cell * 1.12)
                        .animation(.linear(duration: muncherStep), value: chomp)
                        .rotationEffect(.degrees(facing))
                        .animation(nil, value: facing)          // turns snap, as in the arcade
                        .position(x: px(muncher.c), y: py(muncher.r))
                        .animation(.linear(duration: muncherStep), value: muncher)

                    // The ghost: red chaser, skirt rippling with each step, eyes on its heading.
                    PacGhost(dc: ghostDir.dc, dr: ghostDir.dr, frame: (ghost.c + ghost.r) % 2)
                        .equatable()
                        .frame(width: cell * 1.12, height: cell * 1.12)
                        .position(x: px(ghost.c), y: py(ghost.r))
                        .animation(.linear(duration: ghostStep), value: ghost)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }

            ZStack(alignment: .topTrailing) {
                dpad
                    .frame(maxWidth: .infinity)
                if !isDemo {
                    // The arcade's level indicator: one bonus fruit per level reached, level with
                    // the ▲ key (the row beside it is free).
                    PacFruitRow(level: level).equatable()
                        .frame(width: 128, height: 24)
                        .padding(.top, 15)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let fraction = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(PacArt.wall.opacity(0.35))
                Capsule().fill(fraction < 0.3 ? PacArt.red : PacArt.yellow)
                    .frame(width: geo.size.width * fraction)
            }
        }
    }

    // MARK: Controls

    private var dpad: some View {
        VStack(spacing: isDemo ? 5 : 10) {
            arrow("arrowtriangle.up.fill", dc: 0, dr: -1, deg: -90)
            HStack(spacing: isDemo ? 6 : 10) {
                arrow("arrowtriangle.left.fill", dc: -1, dr: 0, deg: 180)
                arrow("arrowtriangle.down.fill", dc: 0, dr: 1, deg: 90)
                arrow("arrowtriangle.right.fill", dc: 1, dr: 0, deg: 0)
            }
        }
    }

    private func arrow(_ icon: String, dc: Int, dr: Int, deg: Double) -> some View {
        Button {
            guard !done else { return }
            pendingDir = (dc, dr)
            Haptics.tap()
        } label: {
            Image(systemName: icon)
                .font(.system(size: isDemo ? 15 : 20, weight: .bold))
                .frame(width: isDemo ? 54 : 74, height: isDemo ? 34 : 54)
                .contentShape(Rectangle())
        }
        .buttonStyle(PacKeyStyle(lit: demoPress.map { $0.dc == dc && $0.dr == dr } ?? false))
    }

    // MARK: - Flow

    private func run() async {
        setup()
        let start = Date()
        var last = start
        var munchAccum = 0.0
        var ghostAccum = 0.0
        loopTask = Task {
            while !Task.isCancelled && !done {
                try? await Task.sleep(for: .seconds(0.016))
                let now = Date()
                let dt = now.timeIntervalSince(last)
                last = now
                timeLeft = max(0, timeLimit - now.timeIntervalSince(start))
                if timeLeft <= 0 { fail(); break }

                munchAccum += dt
                if munchAccum >= muncherStep { munchAccum -= muncherStep; stepMuncher() }
                if done { break }
                ghostAccum += dt
                if ghostAccum >= ghostStep { ghostAccum -= ghostStep; stepGhost() }
            }
        }
    }

    // MARK: - Demo (live manual clip)
    // A fixed Level-1 endgame: the real maze with only 18 pellets left in an L-shaped run —
    // along the bottom, up the left edge, across row 7. The muncher starts on P and the ghost on
    // G with the real L1 step timings, stepped at a fixed 1/60s (the ghost's tie-break is fixed
    // in the demo). The d-pad queues ◄, then ▲ at the corner, then ► at row 7; the ghost closes
    // to 2 cells but never catches (checked offline), and the last pellet is a real win().
    private static let demoPellets: [(Int, Int)] =
        (1...5).reversed().map { ($0, 10) } + (7...9).reversed().map { (1, $0) } + (2...11).map { ($0, 7) }
    /// (cell the muncher has just reached → direction to queue next)
    private static let demoTurns: [(at: (Int, Int)?, dir: (dc: Int, dr: Int))] =
        [(nil, (-1, 0)), ((1, 10), (0, -1)), ((1, 7), (1, 0))]

    private func runDemo() async {
        let dt = 1.0 / 60.0
        while !Task.isCancelled {
            setup()
            pellets = Set(Self.demoPellets.map { key($0.0, $0.1) })
            done = false
            demoPress = nil
            try? await Task.sleep(for: .seconds(0.6))
            var munchAccum = 0.0, ghostAccum = 0.0, turn = 0, pressFlash = 0.0
            while !Task.isCancelled && !done {
                // Queue the next leg the moment the muncher reaches its corner (a d-pad press).
                if turn < Self.demoTurns.count {
                    let tr = Self.demoTurns[turn]
                    if tr.at == nil || (tr.at!.0 == muncher.c && tr.at!.1 == muncher.r) {
                        pendingDir = tr.dir; Haptics.tap()
                        demoPress = tr.dir; pressFlash = 0.22
                        turn += 1
                    }
                }
                munchAccum += dt
                if munchAccum >= muncherStep { munchAccum -= muncherStep; stepMuncher() }
                if done { break }
                ghostAccum += dt
                if ghostAccum >= ghostStep { ghostAccum -= ghostStep; stepGhost() }
                pressFlash -= dt
                if pressFlash <= 0 { demoPress = nil }
                try? await Task.sleep(for: .seconds(0.016))
            }
            demoPress = nil
            // The last pellet went down → the real win() ran (onWin is a no-op). Hold, then loop.
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    private func setup() {
        var wallSet: Set<Int> = []
        var pelletSet: Set<Int> = []
        for (r, line) in maze.enumerated() {
            for (c, ch) in line.enumerated() {
                switch ch {
                case "#": wallSet.insert(key(c, r))
                case ".": pelletSet.insert(key(c, r))
                case "P": muncher = Cell(c: c, r: r)
                case "G": ghost = Cell(c: c, r: r)
                default: break
                }
            }
        }
        walls = wallSet
        pellets = pelletSet
        totalPellets = pelletSet.count
        dir = (0, 0); pendingDir = nil; ghostDir = (0, 0)
        facing = 0; chomp = false
        timeLeft = timeLimit
    }

    private func isWall(_ c: Int, _ r: Int) -> Bool {
        if c < 0 || c >= cols || r < 0 || r >= rows { return true }
        return walls.contains(key(c, r))
    }

    private func stepMuncher() {
        // Turn if the queued direction is open; otherwise keep going if we can.
        if let p = pendingDir, !isWall(muncher.c + p.dc, muncher.r + p.dr) {
            dir = p; pendingDir = nil
        }
        guard dir != (0, 0), !isWall(muncher.c + dir.dc, muncher.r + dir.dr) else { return }

        muncher = Cell(c: muncher.c + dir.dc, r: muncher.r + dir.dr)
        facing = angle(dir)
        chomp.toggle()

        if pellets.remove(key(muncher.c, muncher.r)) != nil {
            SoundManager.shared.tap(); Haptics.tap()
            if pellets.isEmpty { win(); return }
        }
        if muncher == ghost { fail() }
    }

    private func stepGhost() {
        // Greedy chase: pick the open neighbor that shrinks the distance most,
        // avoiding an immediate about-face unless it's the only way out.
        var best: (dc: Int, dr: Int)? = nil
        var bestDist = Int.max
        // The demo fixes the tie-break order so its chase replays identically every loop.
        let options = isDemo ? [(0, -1), (0, 1), (-1, 0), (1, 0)] : [(0, -1), (0, 1), (-1, 0), (1, 0)].shuffled()
        for (dc, dr) in options {
            if isWall(ghost.c + dc, ghost.r + dr) { continue }
            if dc == -ghostDir.dc && dr == -ghostDir.dr && ghostDir != (0, 0) { continue }
            let dist = abs(ghost.c + dc - muncher.c) + abs(ghost.r + dr - muncher.r)
            if dist < bestDist { bestDist = dist; best = (dc, dr) }
        }
        // Dead end — allow the reverse.
        if best == nil {
            for (dc, dr) in options where !isWall(ghost.c + dc, ghost.r + dr) {
                best = (dc, dr); break
            }
        }
        guard let move = best else { return }
        ghostDir = move
        ghost = Cell(c: ghost.c + move.dc, r: ghost.r + move.dr)
        if ghost == muncher { fail() }
    }

    private func angle(_ d: (dc: Int, dr: Int)) -> Double {
        if d.dc > 0 { return 0 }
        if d.dc < 0 { return 180 }
        if d.dr > 0 { return 90 }
        if d.dr < 0 { return -90 }
        return facing
    }

    private func win() {
        guard !done else { return }
        done = true
        loopTask?.cancel()
        onWin()
    }

    private func fail() {
        guard !done else { return }
        done = true
        loopTask?.cancel()
        SoundManager.shared.error()
        onFail()
    }
}

// MARK: - Arcade art

private enum PacArt {
    static let wall = Color(red: 0.13, green: 0.13, blue: 1.0)       // #2121FF
    static let pellet = Color(red: 1.0, green: 0.72, blue: 0.68)     // #FFB8AE
    static let yellow = Color(red: 1.0, green: 1.0, blue: 0.0)       // #FFFF00
    static let red = Color(red: 1.0, green: 0.0, blue: 0.0)          // the chaser
    static let eyeWhite = Color(red: 0.87, green: 0.87, blue: 1.0)   // #DEDEFF
    static let white = Color(red: 0.87, green: 0.87, blue: 1.0)

    /// The cabinet's chunky 7×7 score digits (and a slash).
    static let glyphs: [Character: [String]] = [
        "0": ["..XXX..", ".XX.XX.", "XX...XX", "XX...XX", "XX...XX", ".XX.XX.", "..XXX.."],
        "1": ["...XX..", "..XXX..", "...XX..", "...XX..", "...XX..", "...XX..", ".XXXXXX"],
        "2": [".XXXXX.", "XX...XX", ".....XX", "...XXX.", ".XXX...", "XX.....", "XXXXXXX"],
        "3": ["XXXXXXX", "....XX.", "...XX..", "..XXXX.", ".....XX", "XX...XX", ".XXXXX."],
        "4": ["...XXX.", "..XXXX.", ".XX.XX.", "XX..XX.", "XXXXXXX", "....XX.", "....XX."],
        "5": ["XXXXXX.", "XX.....", "XXXXXX.", ".....XX", ".....XX", "XX...XX", ".XXXXX."],
        "6": ["..XXXX.", ".XX....", "XX.....", "XXXXXX.", "XX...XX", "XX...XX", ".XXXXX."],
        "7": ["XXXXXXX", "XX...XX", "....XX.", "...XX..", "..XX...", "..XX...", "..XX..."],
        "8": [".XXXX..", "XX...X.", "XXX..X.", ".XXXX..", "X..XXXX", "X....XX", ".XXXXX."],
        "9": [".XXXXX.", "XX...XX", "XX...XX", ".XXXXXX", ".....XX", "....XX.", ".XXXX.."],
        "/": [".....XX", "....XX.", "...XX..", "..XX...", ".XX....", "XX.....", "X......"],
    ]
}

/// The muncher: a disc with a wedge mouth facing +x. `open` 0…1 animates the chomp.
private struct PacMouthShape: Shape {
    var open: Double
    var animatableData: Double {
        get { open }
        set { open = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let half = 2 + 42 * max(0, min(1, open))
        var p = Path()
        p.move(to: c)
        p.addArc(center: c, radius: r, startAngle: .degrees(half), endAngle: .degrees(360 - half), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// The red chaser ghost. `frame` flips the skirt each step; the pupils look along (dc, dr).
private struct PacGhost: View, Equatable {
    let dc: Int
    let dr: Int
    let frame: Int

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let o = CGPoint(x: (size.width - s) / 2, y: (size.height - s) / 2)
            func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
            var body = Path()
            body.move(to: P(0.06, 0.9))
            body.addLine(to: P(0.06, 0.48))
            body.addArc(center: P(0.5, 0.48), radius: 0.44 * s, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            body.addLine(to: P(0.94, 0.9))
            // Wavy skirt: three feet, shifted half a step every other frame.
            let feet: [CGFloat] = frame == 0 ? [0.94, 0.8, 0.66, 0.5, 0.34, 0.2, 0.06] : [0.94, 0.86, 0.72, 0.58, 0.42, 0.28, 0.14, 0.06]
            for (i, x) in feet.enumerated() where i > 0 {
                body.addLine(to: P(x, i % 2 == 1 ? 0.76 : 0.94))
            }
            body.closeSubpath()
            ctx.fill(body, with: .color(PacArt.red))
            // Eyes: white with blue pupils looking where it's heading.
            let lx = CGFloat(dc) * 0.05, ly = CGFloat(dr) * 0.06
            for ex in [0.33, 0.67] as [CGFloat] {
                ctx.fill(Path(ellipseIn: CGRect(x: o.x + (ex - 0.11 + lx * 0.5) * s, y: o.y + (0.3 + ly * 0.5) * s, width: 0.22 * s, height: 0.27 * s)),
                         with: .color(PacArt.eyeWhite))
                ctx.fill(Path(ellipseIn: CGRect(x: o.x + (ex - 0.06 + lx * 1.4) * s, y: o.y + (0.39 + ly * 1.4) * s, width: 0.12 * s, height: 0.12 * s)),
                         with: .color(PacArt.wall))
            }
        }
        .allowsHitTesting(false)
    }
}

/// White arcade pixel digits, centred in the view.
private struct PacDigits: View, Equatable {
    let text: String
    let pixel: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let chars = Array(text)
            let adv = pixel * 8
            let total = CGFloat(chars.count) * adv - pixel
            let ox = (size.width - total) / 2, oy = (size.height - pixel * 7) / 2
            var p = Path()
            for (i, ch) in chars.enumerated() {
                guard let rows = PacArt.glyphs[ch] else { continue }
                for (y, row) in rows.enumerated() {
                    let cs = Array(row)
                    var x = 0
                    while x < cs.count {
                        guard cs[x] == "X" else { x += 1; continue }
                        var e = x
                        while e + 1 < cs.count && cs[e + 1] == "X" { e += 1 }
                        // Runs overlap a hair so no seams show between pixels.
                        p.addRect(CGRect(x: ox + CGFloat(i) * adv + CGFloat(x) * pixel, y: oy + CGFloat(y) * pixel,
                                         width: CGFloat(e - x + 1) * pixel + 0.3, height: pixel + 0.3))
                        x = e + 1
                    }
                }
            }
            ctx.fill(p, with: .color(PacArt.white))
        }
        .allowsHitTesting(false)
    }
}

/// The maze: a blue double line round the border and a thin outlined block on every pillar,
/// each drawn inside its own wall cells.
private struct PacMaze: View, Equatable {
    let walls: Set<Int>
    let cols: Int
    let rows: Int
    let cell: CGFloat
    let ox: CGFloat
    let oy: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            guard !walls.isEmpty else { return }
            let lw = max(1.4, cell * 0.085)
            let board = CGRect(x: ox, y: oy, width: CGFloat(cols) * cell, height: CGFloat(rows) * cell)
            let outer = board.insetBy(dx: cell * 0.3, dy: cell * 0.3)
            let inner = board.insetBy(dx: cell * 0.78, dy: cell * 0.78)
            ctx.stroke(Path(roundedRect: outer, cornerRadius: cell * 0.55), with: .color(PacArt.wall), lineWidth: lw)
            ctx.stroke(Path(roundedRect: inner, cornerRadius: cell * 0.3), with: .color(PacArt.wall), lineWidth: lw)
            var blocks = Path()
            for k in walls {
                let c = k / 100, r = k % 100
                guard c > 0, r > 0, c < cols - 1, r < rows - 1 else { continue }   // the border is drawn above
                let rc = CGRect(x: ox + CGFloat(c) * cell, y: oy + CGFloat(r) * cell, width: cell, height: cell)
                blocks.addRoundedRect(in: rc.insetBy(dx: cell * 0.2, dy: cell * 0.2), cornerSize: CGSize(width: cell * 0.16, height: cell * 0.16))
            }
            ctx.stroke(blocks, with: .color(PacArt.wall), lineWidth: lw)
        }
        .allowsHitTesting(false)
    }
}

/// The level indicator: the arcade's bonus fruit for every level reached, newest on the right.
private struct PacFruitRow: View, Equatable {
    let level: Int

    var body: some View {
        Canvas { ctx, size in
            let kinds: [FruitKind] = [.cherry, .strawberry, .dekopon, .dekopon, .apple, .apple, .melon]
            let n = max(1, min(7, level))
            // Full-size fruit while they fit side by side; seven shrink a little to stay in the row.
            let r = min(size.height * 0.42, size.width / CGFloat(n) * 0.47)
            let step = r * 2.1
            for i in 0..<n {
                let x = size.width - r - CGFloat(n - 1 - i) * step
                FruitArt.draw(kinds[i], in: ctx, at: CGPoint(x: x, y: size.height / 2), radius: r)
            }
        }
        .allowsHitTesting(false)
    }
}

/// A black arcade key rimmed in maze blue; lights up yellow while pressed (or demo-pressed).
private struct PacKeyStyle: ButtonStyle {
    let lit: Bool

    func makeBody(configuration: Configuration) -> some View {
        let on = lit || configuration.isPressed
        return configuration.label
            .foregroundStyle(on ? Color.black : PacArt.yellow)
            .background(RoundedRectangle(cornerRadius: 12).fill(on ? PacArt.yellow : Color.black))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(PacArt.wall.opacity(on ? 0 : 0.7), lineWidth: 1.2).padding(4))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Color.white : PacArt.wall, lineWidth: on ? 3 : 2.2))
            .scaleEffect(on ? 0.9 : 1)
    }
}
