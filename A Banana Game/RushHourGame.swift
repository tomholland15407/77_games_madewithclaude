//
//  RushHourGame.swift
//  A Banana Game
//
//  Brain — a Rush Hour sliding-jam puzzle. The board is packed with cars that only slide along
//  their length. DRAG a car to shuffle the jam and open a lane so the banana car can slide out
//  the exit on the right. Every board is generated and BFS-verified solvable (and never already
//  solved). Solve it before the clock runs out. It's a drag game, so the feed locks while you
//  play (a skip button lets you leave). 7 levels: denser jams needing more moves, on a shorter
//  clock — near-impossible by L6–7.
//
//  Drawn as ThinkFun's Rush Hour: a charcoal plastic tray with a raised rim, recessed squares and
//  the exit gap (with chevrons) in the right rim of the exit row; top-down plastic cars and trucks
//  in the game's bright colours (windshields, roofs, cargo beds, headlights) and the yellow banana
//  car with a banana decal. The cars stay views, so drags and slides are unchanged; the "FREE THE"
//  header is gone. The tray is an Equatable view.
//

import SwiftUI

enum RushHourGame {
    static let definition = GameDefinition(
        id: "rush-hour",
        title: "Banana Getaway",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        locksFeed: true,
        manual: GameManual(
            bullets: [
                "Cars only slide along their length.",
                "Drag the blockers to clear the exit row.",
                "Then slide the yellow banana car off the right edge.",
                "Solve the jam before the clock runs out or you drop back to level 1.",
            ],
            bulletsVI: [
                "Xe chỉ trượt dọc theo chiều dài của nó.",
                "Kéo các xe cản để dọn trống hàng lối ra.",
                "Rồi trượt xe chuối vàng ra khỏi mép phải.",
                "Giải kẹt xe trước khi hết giờ, nếu không bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(RushHourView(level: level, onWin: onWin, onFail: onFail))
        },
        prefetch: { level in RushHourView(level: level, onWin: {}, onFail: {}).prefetchBoard() }
    )
}

struct RushHourView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    private let size = 6
    private let exitRow = 2

    // Difficulty shifted up (the old level 6 is roughly the new level 1) and pushed past the old
    // top end for the new L6–7. Move-count is the real difficulty lever; generation keeps the
    // hardest board it finds so a high minMoves never drops back to a trivial fallback.
    private var blockerCount: Int  { [6, 7, 8, 8, 9, 9, 9][min(level, 7) - 1] }
    private var minMoves: Int      { [8, 11, 14, 17, 20, 24, 28][min(level, 7) - 1] }
    private var timeLimit: Double  { [60, 54, 48, 42, 36, 30, 26][min(level, 7) - 1] }

    struct Car: Equatable { var r: Int; var c: Int; let len: Int; let horiz: Bool }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var cars: [Car] = []
    @State private var timeLeft = 0.0
    @State private var ready = false

    // Drag tracking.
    @State private var dragId: Int? = nil
    @State private var originR = 0
    @State private var originC = 0
    @State private var demoFinger: Int? = nil   // car index the demo is "dragging"

    var body: some View {
        Group {
            if ready {
                gameBody
            } else {
                BrainstormingView(skyTop: Color(white: 0.12), skyBottom: Color(white: 0.05))
            }
        }
        .task { isDemo ? await runDemo() : await run() }
    }

    // MARK: - Demo (live manual clip)

    /// A fixed, obviously-solvable jam: the banana car sits in the exit row behind one
    /// vertical blocker. Slide the blocker up, then slide the banana off the right edge.
    private func demoBoard() -> [Car] {
        [
            Car(r: exitRow, c: 1, len: 2, horiz: true),   // 0: banana car
            Car(r: 1, c: 3, len: 2, horiz: false),        // 1: the blocker to lift
            Car(r: 4, c: 0, len: 2, horiz: true),         // 2: dressing
            Car(r: 0, c: 0, len: 2, horiz: false),        // 3: dressing
        ]
    }

    private func runDemo() async {
        while !Task.isCancelled {
            cars = demoBoard()
            ready = true
            phase = .play
            timeLeft = timeLimit
            try? await Task.sleep(for: .seconds(0.7))
            guard !Task.isCancelled, cars.count > 1 else { return }
            demoFinger = 1                                               // grab the blocker
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.easeInOut(duration: 0.5)) { cars[1].r = 0 }   // blocker up, clears the row
            try? await Task.sleep(for: .seconds(0.7))
            guard !Task.isCancelled else { return }
            demoFinger = 0                                               // grab the banana car
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.easeInOut(duration: 0.65)) { cars[0].c = 4 }  // banana slides out the exit
            try? await Task.sleep(for: .seconds(0.6))
            demoFinger = nil
            try? await Task.sleep(for: .seconds(1.2))                    // hold on the freed car
        }
    }

    private var gameBody: some View {
        VStack(spacing: 14) {
            if !isDemo { timeBar.frame(height: 6).padding(.horizontal, 48).padding(.top, 6) }

            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let cell = min(w, h) / (CGFloat(size) + 1.2)
                let boardW = cell * CGFloat(size)
                let ox = (w - boardW) / 2, oy = (h - boardW) / 2

                ZStack {
                    // The plastic tray, its squares and the exit gap: drawn once.
                    RHTray(size: geo.size, n: size, exitRow: exitRow).equatable()

                    // Cars (views, so the drag and the slides still animate).
                    ForEach(Array(cars.enumerated()), id: \.offset) { i, car in
                        let isBanana = (i == 0)
                        let cw = (car.horiz ? CGFloat(car.len) : 1) * cell - 6
                        let ch = (car.horiz ? 1 : CGFloat(car.len)) * cell - 6
                        RHCar(color: isBanana ? RHArt.banana : RHArt.color(i), len: car.len, horiz: car.horiz, banana: isBanana)
                            .frame(width: cw, height: ch)
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                            .position(x: ox + (CGFloat(car.c) + (car.horiz ? CGFloat(car.len) : 1) / 2) * cell,
                                      y: oy + (CGFloat(car.r) + (car.horiz ? 1 : CGFloat(car.len)) / 2) * cell)
                            .gesture(dragGesture(i, cell: cell))
                    }

                    // Demo-only finger that rides the car being "dragged".
                    if let fi = demoFinger, fi < cars.count {
                        let car = cars[fi]
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.system(size: cell * 0.6))
                            .foregroundStyle(.white)
                            .shadow(radius: 3)
                            .position(x: ox + (CGFloat(car.c) + (car.horiz ? CGFloat(car.len) : 1) / 2) * cell + cell * 0.22,
                                      y: oy + (CGFloat(car.r) + (car.horiz ? 1 : CGFloat(car.len)) / 2) * cell + cell * 0.22)
                            .allowsHitTesting(false)
                    }
                }
            }
            .padding(.horizontal, isDemo ? 8 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RHArt.table)
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
    }

    private func dragGesture(_ i: Int, cell: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { v in
                guard phase == .play, i < cars.count else { return }
                if dragId != i { dragId = i; originR = cars[i].r; originC = cars[i].c }
                let (neg, pos) = slideRange(i, r: originR, c: originC)
                if cars[i].horiz {
                    let off = Int((v.translation.width / cell).rounded())
                    cars[i].c = originC + min(pos, max(-neg, off))
                } else {
                    let off = Int((v.translation.height / cell).rounded())
                    cars[i].r = originR + min(pos, max(-neg, off))
                }
            }
            .onEnded { _ in
                guard dragId == i, i < cars.count else { return }
                if cars[i].r != originR || cars[i].c != originC {
                    SoundManager.shared.tap(); Haptics.tap()
                }
                dragId = nil
                if goal(cars) { win() }
            }
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

    // MARK: - Flow
    /// Hands this level's board build to `BoardCache` so it can run during the countdown.
    func prefetchBoard() {
        let (sz, ex, bc, mm) = (size, exitRow, blockerCount, minMoves)
        BoardCache.prefetch(boardKey) { Self.generateBoard(size: sz, exitRow: ex, blockerCount: bc, minMoves: mm) }
    }
    private var boardKey: String { BoardCache.key("rush-hour", level: level) }

    private func run() async {
        // Generate + BFS-verify off the main actor so the countdown never hitches; the banana
        // "brainstorms" while it works. Then commit and start the clock.
        let (sz, ex, bc, mm) = (size, exitRow, blockerCount, minMoves)
        let t0 = Date()
        let board = await BoardCache.take(boardKey) { Self.generateBoard(size: sz, exitRow: ex, blockerCount: bc, minMoves: mm) }
        guard !Task.isCancelled else { return }
        await BoardCache.holdBrainstorm(since: t0, minimum: 0.7)
        guard !Task.isCancelled else { return }
        cars = board
        ready = true
        phase = .play
        timeLeft = timeLimit
        let start = Date()
        while !Task.isCancelled && phase == .play {
            try? await Task.sleep(for: .seconds(0.05))
            timeLeft = max(0, timeLimit - Date().timeIntervalSince(start))
            if timeLeft <= 0 { fail() }
        }
    }

    // MARK: - Geometry helpers (gameplay wrappers over the pure static solver logic)
    private func occupancy(_ cs: [Car], excluding: Int? = nil) -> [[Int]] {
        Self.occupancy(cs, size: size, excluding: excluding)
    }

    /// How far car `i` (at origin r,c) can slide in the negative and positive axis directions.
    private func slideRange(_ i: Int, r: Int, c: Int) -> (Int, Int) {
        let g = occupancy(cars, excluding: i)
        let car = cars[i]
        var neg = 0, pos = 0
        if car.horiz {
            var cc = c + car.len
            while cc < size && g[r][cc] == -1 { pos += 1; cc += 1 }
            var cl = c - 1
            while cl >= 0 && g[r][cl] == -1 { neg += 1; cl -= 1 }
        } else {
            var rr = r + car.len
            while rr < size && g[rr][c] == -1 { pos += 1; rr += 1 }
            var rl = r - 1
            while rl >= 0 && g[rl][c] == -1 { neg += 1; rl -= 1 }
        }
        return (neg, pos)
    }

    private func goal(_ cs: [Car]) -> Bool { Self.goal(cs, size: size) }

    // MARK: - Generation (pure / off-main; BFS-verified solvable, not already solved)

    private nonisolated static func occupancy(_ cs: [Car], size: Int, excluding: Int? = nil) -> [[Int]] {
        var g = Array(repeating: Array(repeating: -1, count: size), count: size)
        for (i, car) in cs.enumerated() where i != excluding {
            for k in 0..<car.len {
                let rr = car.r + (car.horiz ? 0 : k)
                let cc = car.c + (car.horiz ? k : 0)
                if rr >= 0, rr < size, cc >= 0, cc < size { g[rr][cc] = i }
            }
        }
        return g
    }

    private nonisolated static func goal(_ cs: [Car], size: Int) -> Bool {
        let b = cs[0]
        return b.horiz && b.c + b.len - 1 == size - 1
    }

    /// Try many random jams; return the first that needs at least `minMoves` moves, else the
    /// hardest solvable board we saw (so a high minMoves never falls back to a trivial board).
    private nonisolated static func generateBoard(size: Int, exitRow: Int, blockerCount: Int, minMoves: Int) -> [Car] {
        var best: [Car]? = nil
        var bestMoves = -1
        for _ in 0..<300 {
            var cs: [Car] = [Car(r: exitRow, c: Int.random(in: 0...2), len: 2, horiz: true)]
            var attempts = 0
            while cs.count < blockerCount + 1 && attempts < 200 {
                attempts += 1
                let horiz = Bool.random()
                let len = Int.random(in: 0...2) == 0 ? 3 : 2
                let r = horiz ? Int.random(in: 0..<size) : Int.random(in: 0...(size - len))
                let c = horiz ? Int.random(in: 0...(size - len)) : Int.random(in: 0..<size)
                let cand = Car(r: r, c: c, len: len, horiz: horiz)
                if fits(cand, in: cs, size: size) { cs.append(cand) }
            }
            guard let moves = shortestSolution(cs, size: size) else { continue }
            if moves >= minMoves { return cs }
            if moves > bestMoves { bestMoves = moves; best = cs }
        }
        // Fallback: a guaranteed simple board (one vertical blocker on the exit row).
        return best ?? [Car(r: exitRow, c: 0, len: 2, horiz: true),
                        Car(r: exitRow, c: 3, len: 2, horiz: false)]
    }

    private nonisolated static func fits(_ car: Car, in cs: [Car], size: Int) -> Bool {
        var cells = Set<Int>()
        for other in cs {
            for k in 0..<other.len {
                let rr = other.r + (other.horiz ? 0 : k)
                let cc = other.c + (other.horiz ? k : 0)
                cells.insert(rr * size + cc)
            }
        }
        for k in 0..<car.len {
            let rr = car.r + (car.horiz ? 0 : k)
            let cc = car.c + (car.horiz ? k : 0)
            if cells.contains(rr * size + cc) { return false }
        }
        return true
    }

    /// Shortest number of slide-moves to free the banana car; nil if unsolvable (or the search
    /// cap is hit). The same breadth-first search as before — same expansion order, same cap —
    /// but on packed integer states (3 bits per car) with bitmask occupancy instead of String keys
    /// and `[[Int]]` grids, which makes generation ~20× faster without changing which boards
    /// pass the `minMoves` bar.
    private nonisolated static func shortestSolution(_ start: [Car], size: Int) -> Int? {
        if goal(start, size: size) { return 0 }
        let n = start.count
        precondition(n <= 21 && size <= 8, "packed state needs ≤ 21 cars on a ≤ 8×8 board")
        // Per-car constants: the cell bitmask for every legal position of its sliding coordinate.
        var lens = [Int](repeating: 0, count: n)
        var masks = [[UInt64]](repeating: [], count: n)
        var startKey: UInt64 = 0
        for (i, car) in start.enumerated() {
            lens[i] = car.len
            let maxV = size - car.len
            var list = [UInt64](repeating: 0, count: maxV + 1)
            for v in 0...maxV {
                var m: UInt64 = 0
                for k in 0..<car.len {
                    let rr = car.horiz ? car.r : v + k
                    let cc = car.horiz ? v + k : car.c
                    if rr >= 0, rr < size, cc >= 0, cc < size { m |= 1 << UInt64(rr * size + cc) }
                }
                list[v] = m
            }
            masks[i] = list
            let v = car.horiz ? car.c : car.r
            startKey |= UInt64(v) << UInt64(3 * i)
        }
        // The banana car (index 0) wins when its right end touches the right edge.
        let goalV = start[0].horiz ? size - start[0].len : -1
        @inline(__always) func coord(_ s: UInt64, _ i: Int) -> Int { Int((s >> UInt64(3 * i)) & 7) }
        @inline(__always) func leadCell(_ car: Car, _ v: Int, _ dir: Int) -> Int {
            let lead = dir > 0 ? v + car.len - 1 : v
            return car.horiz ? car.r * size + lead : lead * size + car.c
        }

        var visited: Set<UInt64> = [startKey]
        var frontier: [UInt64] = [startKey]
        var depth = 0
        let cap = 60000
        while !frontier.isEmpty && visited.count < cap {
            depth += 1
            var next: [UInt64] = []
            for state in frontier {
                var occ: UInt64 = 0
                for i in 0..<n { occ |= masks[i][coord(state, i)] }
                for i in 0..<n {
                    let car = start[i]
                    let v = coord(state, i)
                    let g = occ & ~masks[i][v]          // everything except this car
                    let clear = ~(UInt64(7) << UInt64(3 * i))
                    for dir in [-1, 1] {
                        var off = dir
                        while true {
                            let nv = v + off
                            if nv < 0 || nv + lens[i] - 1 >= size { break }
                            if g & (1 << UInt64(leadCell(car, nv, dir))) != 0 { break }
                            let ns = (state & clear) | (UInt64(nv) << UInt64(3 * i))
                            if !visited.contains(ns) {
                                visited.insert(ns)
                                if i == 0 && nv == goalV { return depth }
                                next.append(ns)
                            }
                            off += dir
                        }
                    }
                }
            }
            frontier = next
        }
        return nil
    }

    private func win() {
        guard phase != .done else { return }
        phase = .done
        Haptics.success(); SoundManager.shared.tap()
        onWin()
    }
    private func fail() {
        guard phase != .done else { return }
        phase = .done
        SoundManager.shared.error()
        onFail()
    }
}

// MARK: - Rush Hour board-game art

private enum RHArt {
    static let banana = Color(red: 1, green: 0.84, blue: 0.16)
    static let table = LinearGradient(colors: [Color(red: 0.2, green: 0.23, blue: 0.28), Color(red: 0.1, green: 0.11, blue: 0.14)], startPoint: .top, endPoint: .bottom)

    /// The game's bright plastic colours for the blockers.
    static func color(_ i: Int) -> Color {
        let all: [Color] = [
            Color(red: 0.42, green: 0.8, blue: 0.24), Color(red: 1, green: 0.52, blue: 0.14), Color(red: 0.2, green: 0.7, blue: 0.92),
            Color(red: 0.94, green: 0.36, blue: 0.62), Color(red: 0.58, green: 0.38, blue: 0.86), Color(red: 0.16, green: 0.42, blue: 0.86),
            Color(red: 0.12, green: 0.56, blue: 0.4), Color(red: 0.86, green: 0.2, blue: 0.22), Color(red: 0.2, green: 0.78, blue: 0.72),
            Color(red: 0.76, green: 0.62, blue: 0.4),
        ]
        return all[i % all.count]
    }
}

/// The charcoal plastic tray: a raised rim, 6×6 recessed squares and the exit gap (with chevrons)
/// in the right-hand rim of the exit row.
private struct RHTray: View, Equatable {
    let size: CGSize
    let n: Int
    let exitRow: Int

    var body: some View {
        Canvas { ctx, _ in
            let w = size.width, h = size.height
            let cell = min(w, h) / (CGFloat(n) + 1.2)
            let boardW = cell * CGFloat(n)
            let ox = (w - boardW) / 2, oy = (h - boardW) / 2
            let board = CGRect(x: ox, y: oy, width: boardW, height: boardW)
            let rim = board.insetBy(dx: -cell * 0.22, dy: -cell * 0.22)
            ctx.fill(Path(roundedRect: rim.offsetBy(dx: 0, dy: 4), cornerRadius: cell * 0.3), with: .color(.black.opacity(0.4)))
            ctx.fill(Path(roundedRect: rim, cornerRadius: cell * 0.3), with: .linearGradient(Gradient(colors: [Color(white: 0.32), Color(white: 0.16)]),
                                                                                              startPoint: CGPoint(x: 0, y: rim.minY), endPoint: CGPoint(x: 0, y: rim.maxY)))
            ctx.stroke(Path(roundedRect: rim.insetBy(dx: 1.5, dy: 1.5), cornerRadius: cell * 0.28), with: .color(.white.opacity(0.15)), lineWidth: 1.5)
            ctx.fill(Path(roundedRect: board, cornerRadius: cell * 0.08), with: .color(Color(white: 0.12)))
            var squares = Path()
            for r in 0..<n {
                for c in 0..<n {
                    squares.addRoundedRect(in: CGRect(x: ox + CGFloat(c) * cell + cell * 0.05, y: oy + CGFloat(r) * cell + cell * 0.05,
                                                      width: cell * 0.9, height: cell * 0.9), cornerSize: CGSize(width: cell * 0.08, height: cell * 0.08))
                }
            }
            ctx.fill(squares, with: .color(Color(white: 0.2)))
            ctx.stroke(squares, with: .color(.black.opacity(0.35)), lineWidth: 1)
            // Exit gap in the right rim, marked with chevrons.
            let gy = oy + CGFloat(exitRow) * cell
            let gap = CGRect(x: board.maxX - 1, y: gy + cell * 0.06, width: rim.maxX - board.maxX + 2, height: cell * 0.88)
            ctx.fill(Path(gap), with: .color(Color(white: 0.12)))
            var chevrons = Path()
            for k in 0..<2 {
                let x = rim.maxX + cell * (0.12 + CGFloat(k) * 0.2)
                chevrons.move(to: CGPoint(x: x, y: gy + cell * 0.3))
                chevrons.addLine(to: CGPoint(x: x + cell * 0.14, y: gy + cell * 0.5))
                chevrons.addLine(to: CGPoint(x: x, y: gy + cell * 0.7))
            }
            ctx.stroke(chevrons, with: .color(RHArt.banana), style: StrokeStyle(lineWidth: max(2, cell * 0.07), lineCap: .round, lineJoin: .round))
        }
    }
}

/// A plastic car (length 2) or truck (length 3) seen from above, nose to the right (horizontal) or
/// up (vertical): glossy body, windshield, roof, headlights; a truck has a cab and a cargo bed. The
/// banana car carries a banana decal.
private struct RHCar: View {
    let color: Color
    let len: Int
    let horiz: Bool
    let banana: Bool

    var body: some View {
        Canvas { ctx, size in
            var g = ctx
            // Draw in a horizontal frame (nose at +x), rotated for vertical pieces.
            let L = horiz ? size.width : size.height, W = horiz ? size.height : size.width
            if !horiz {
                g.translateBy(x: size.width / 2, y: size.height / 2)
                g.rotate(by: .degrees(-90))
                g.translateBy(x: -L / 2, y: -W / 2)
            }
            let body = CGRect(x: 0, y: 0, width: L, height: W)
            g.fill(Path(roundedRect: body.offsetBy(dx: 0, dy: 3), cornerRadius: W * 0.26), with: .color(.black.opacity(0.35)))
            g.fill(Path(roundedRect: body, cornerRadius: W * 0.26), with: .linearGradient(Gradient(colors: [color.mix(with: .white, by: 0.3), color, color.mix(with: .black, by: 0.3)]),
                                                                                          startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: W)))
            g.stroke(Path(roundedRect: body.insetBy(dx: 0.75, dy: 0.75), cornerRadius: W * 0.25), with: .color(.black.opacity(0.45)), lineWidth: 1.5)
            let glass = Color(red: 0.12, green: 0.18, blue: 0.26)
            if len >= 3 {
                // Truck: cab at the nose, a ribbed cargo bed behind.
                let cab = CGRect(x: L - W * 1.05, y: W * 0.1, width: W * 0.95, height: W * 0.8)
                g.fill(Path(roundedRect: cab, cornerRadius: W * 0.18), with: .color(color.mix(with: .white, by: 0.15)))
                g.fill(Path(roundedRect: CGRect(x: L - W * 0.42, y: W * 0.16, width: W * 0.24, height: W * 0.68), cornerRadius: W * 0.08), with: .color(glass))
                let bed = CGRect(x: W * 0.12, y: W * 0.12, width: L - W * 1.3, height: W * 0.76)
                g.fill(Path(roundedRect: bed, cornerRadius: W * 0.1), with: .color(color.mix(with: .black, by: 0.2)))
                var ribs = Path()
                var x = bed.minX + W * 0.2
                while x < bed.maxX - W * 0.05 {
                    ribs.move(to: CGPoint(x: x, y: bed.minY + 2)); ribs.addLine(to: CGPoint(x: x, y: bed.maxY - 2))
                    x += W * 0.28
                }
                g.stroke(ribs, with: .color(.black.opacity(0.3)), lineWidth: 1.5)
            } else {
                // Car: windshield, roof, rear window.
                g.fill(Path(roundedRect: CGRect(x: L * 0.56, y: W * 0.16, width: L * 0.16, height: W * 0.68), cornerRadius: W * 0.1), with: .color(glass))
                g.fill(Path(roundedRect: CGRect(x: L * 0.28, y: W * 0.14, width: L * 0.28, height: W * 0.72), cornerRadius: W * 0.14), with: .color(color.mix(with: .white, by: 0.18)))
                g.fill(Path(roundedRect: CGRect(x: L * 0.16, y: W * 0.2, width: L * 0.1, height: W * 0.6), cornerRadius: W * 0.08), with: .color(glass))
                g.fill(Path(roundedRect: CGRect(x: L * 0.6, y: W * 0.22, width: L * 0.06, height: W * 0.2), cornerRadius: 2), with: .color(.white.opacity(0.5)))
            }
            // Headlights at the nose, tail lights at the back.
            for y in [W * 0.14, W * 0.72] {
                g.fill(Path(roundedRect: CGRect(x: L - W * 0.1, y: y, width: W * 0.07, height: W * 0.14), cornerRadius: 2), with: .color(Color(red: 1, green: 0.96, blue: 0.75)))
                g.fill(Path(roundedRect: CGRect(x: W * 0.03, y: y, width: W * 0.06, height: W * 0.14), cornerRadius: 2), with: .color(Color(red: 0.9, green: 0.15, blue: 0.1)))
            }
            if banana {
                // A banana decal on the roof.
                var d = g
                d.translateBy(x: L * 0.42, y: W * 0.5)
                d.rotate(by: .degrees(-20))
                d.scaleBy(x: W * 0.55, y: W * 0.55)
                var b = Path()
                b.move(to: CGPoint(x: -0.44, y: -0.1))
                b.addQuadCurve(to: CGPoint(x: 0.44, y: -0.12), control: CGPoint(x: 0, y: 0.66))
                b.addQuadCurve(to: CGPoint(x: -0.44, y: -0.1), control: CGPoint(x: 0, y: 0.12))
                b.closeSubpath()
                d.fill(b, with: .color(Color(red: 1, green: 0.95, blue: 0.5)))
                d.stroke(b, with: .color(Color(red: 0.45, green: 0.3, blue: 0.05)), lineWidth: 0.07)
                d.fill(Path(roundedRect: CGRect(x: 0.4, y: -0.22, width: 0.12, height: 0.12), cornerRadius: 0.03), with: .color(Color(red: 0.42, green: 0.27, blue: 0.08)))
            }
        }
    }
}
