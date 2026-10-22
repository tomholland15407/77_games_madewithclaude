//
//  Slide2048Game.swift
//  A Banana Game
//
//  Game #10 — brain (swipe). A pint-sized 2048: swipe to slide every tile, and
//  tiles with the same number merge. Reach the target tile to win the level.
//  If the board fills with no moves left, you fail back to level 1. 7 levels:
//  the target tile climbs (16 → 512) and from level 5 the board shrinks to 3×3,
//  where the high targets become nearly unreachable.
//
//  Locks the feed's vertical paging while playing (see `locksFeed`) so its
//  up/down swipes drive the tiles instead of the feed.
//

import SwiftUI

enum Slide2048Game {
    static let definition = GameDefinition(
        id: "slide-2048",
        title: "Slide",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        locksFeed: true,
        manual: GameManual(
            bullets: [
                "Swipe to slide every tile; matching numbers merge into double.",
                "Reach the target tile to win the level.",
                "A full board with no moves — or the clock running out — drops you to level 1.",
            ],
            bulletsVI: [
                "Vuốt để trượt mọi ô; hai số giống nhau gộp thành gấp đôi.",
                "Đạt tới ô mục tiêu để qua cấp.",
                "Bàn đầy không còn nước đi — hoặc hết giờ — sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(Slide2048View(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct Slide2048View: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    /// Board is 4×4 for the first levels, shrinking to 3×3 where it gets brutal.
    private var side: Int { level <= 4 ? 4 : 3 }
    /// The tile you must reach to win. Climbs fast: 16 → 512.
    private var target: Int { [0, 16, 32, 64, 128, 128, 256, 512][min(level, 7)] }
    /// Seconds to reach the target — an open-ended puzzle still needs a hard
    /// fail so you can't play forever. Generous early (~23s), tight late (~8s).
    private var timeLimit: Double { max(8, 26 - Double(level) * 2.5) }

    @State private var grid: [[Int]] = []
    @State private var timeLeft = 0.0
    @State private var done = false
    // Presentation only: the tiles as moving pieces (they slide, pop on merge, zoom in when born),
    // re-synced to `grid` after every move.
    @State private var tiles: [SlideTile] = []
    @State private var nextTileID = 0
    @State private var moveToken = 0
    @State private var demoFinger: CGPoint? = nil      // demo swipe finger, in board-unit offsets
    @State private var demoFingerDown = false

    private var bestTile: Int { grid.flatMap { $0 }.max() ?? 0 }

    var body: some View {
        VStack(spacing: isDemo ? 8 : 14) {
            header
            if !isDemo {
                timeBar
                    .frame(height: 8)
                    .padding(.horizontal, 30)
            }
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                board(side)
                    .frame(width: side, height: side)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
        .padding(.horizontal, isDemo ? 12 : 18)
        .padding(.vertical, isDemo ? 10 : 18)
        .background(SlideArt.page)
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in handleSwipe(value.translation) }
        )
        .onAppear { if !isDemo { setup() } }
        // The countdown — run out of time and you fail back to level 1.
        .task {
            if isDemo { await runDemo(); return }
            timeLeft = timeLimit
            let start = Date()
            while !Task.isCancelled && !done {
                try? await Task.sleep(for: .seconds(0.05))
                timeLeft = max(0, timeLimit - Date().timeIntervalSince(start))
                if timeLeft <= 0 && !done {
                    done = true
                    Haptics.warning()
                    SoundManager.shared.error()
                    onFail()
                }
            }
        }
    }

    /// 2048's header: the goal as big title numerals, and a taupe BEST box.
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: -4) {
                Text(L("GOAL", "MỤC TIÊU"))
                    .font(.system(size: isDemo ? 11 : 13, weight: .heavy))
                    .tracking(1.5)
                    .foregroundStyle(SlideArt.ink.opacity(0.75))
                Text("\(target)")
                    .font(.system(size: isDemo ? 38 : 56, weight: .heavy))
                    .foregroundStyle(SlideArt.ink)
            }
            Spacer()
            VStack(spacing: 0) {
                Text(L("BEST", "CAO NHẤT"))
                    .font(.system(size: isDemo ? 10 : 12, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(Color(red: 0.93, green: 0.89, blue: 0.85))
                Text("\(bestTile)")
                    .font(.system(size: isDemo ? 20 : 26, weight: .heavy))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            .frame(minWidth: isDemo ? 64 : 84)
            .padding(.vertical, isDemo ? 4 : 7)
            .padding(.horizontal, 10)
            .background(SlideArt.board, in: RoundedRectangle(cornerRadius: 5))
        }
    }

    // MARK: - Demo (live manual clip)

    /// A fixed board solved with LEFT → UP → UP, merging up to a 16 tile (the L1 target).
    /// Drives the real `apply(_:)` merge logic; a finger swipes across the board for each move.
    private func runDemo() async {
        let swipes: [(Direction, CGPoint)] = [(.left, CGPoint(x: -1, y: 0)), (.up, CGPoint(x: 0, y: -1)),
                                              (.up, CGPoint(x: 0, y: -1))]
        while !Task.isCancelled {
            done = false
            grid = [[2, 2, 0, 0], [2, 2, 0, 0], [8, 0, 0, 0], [0, 0, 0, 0]]
            rebuildTiles()
            timeLeft = timeLimit
            demoFinger = nil
            try? await Task.sleep(for: .seconds(0.8))
            for (dir, v) in swipes {
                guard !Task.isCancelled else { return }
                demoFinger = CGPoint(x: -v.x * 0.28, y: -v.y * 0.28)
                demoFingerDown = true
                try? await Task.sleep(for: .seconds(0.2))
                withAnimation(.easeOut(duration: 0.28)) { demoFinger = CGPoint(x: v.x * 0.28, y: v.y * 0.28) }
                try? await Task.sleep(for: .seconds(0.2))
                let before = grid
                apply(dir)
                animateMove(from: before, dir: dir)
                try? await Task.sleep(for: .seconds(0.15))
                demoFingerDown = false
                demoFinger = nil
                try? await Task.sleep(for: .seconds(0.55))
            }
            try? await Task.sleep(for: .seconds(1.1))   // hold on the 16 tile
        }
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let fraction = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(SlideArt.slot)
                Capsule()
                    .fill(fraction < 0.3 ? Color(red: 0.9, green: 0.25, blue: 0.2) : SlideArt.color(16))
                    .frame(width: geo.size.width * fraction)
            }
        }
    }

    /// The taupe board with its empty slots, and the tiles sliding over it.
    private func board(_ size: CGFloat) -> some View {
        let n = side
        let gap = size / (CGFloat(n) * 7.2 + 1)
        let cell = (size - gap * CGFloat(n + 1)) / CGFloat(n)
        func center(_ r: Int, _ c: Int) -> CGPoint {
            CGPoint(x: gap + (cell + gap) * CGFloat(c) + cell / 2, y: gap + (cell + gap) * CGFloat(r) + cell / 2)
        }
        return ZStack(alignment: .topLeading) {
            SlideSlots(n: n, size: size).equatable()
            ForEach(tiles) { t in
                SlideTileView(value: t.value, size: cell)
                    .position(center(t.r, t.c))
                    .zIndex(t.merged ? 2 : 1)
                    .transition(.asymmetric(insertion: .scale(scale: t.merged ? 1.22 : 0.1).combined(with: .opacity),
                                            removal: .opacity.animation(.linear(duration: 0.05))))
            }
            if let f = demoFinger {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: cell * 0.55))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 3)
                    .scaleEffect(demoFingerDown ? 0.92 : 1)
                    .position(x: size / 2 + f.x * size, y: size / 2 + f.y * size)
            }
        }
        .frame(width: size, height: size)
    }

    private func valueAt(_ r: Int, _ c: Int) -> Int {
        guard r < grid.count, c < grid[r].count else { return 0 }
        return grid[r][c]
    }

    // MARK: - Tile motion (presentation only)

    private func newTileID() -> Int { nextTileID += 1; return nextTileID }

    /// Snap the visual tiles to the current grid (fresh identities, no motion).
    private func rebuildTiles() {
        var out: [SlideTile] = []
        for r in 0..<grid.count {
            for c in 0..<grid[r].count where grid[r][c] != 0 {
                out.append(SlideTile(id: newTileID(), value: grid[r][c], r: r, c: c))
            }
        }
        moveToken += 1
        tiles = out
    }

    /// Replays a move for the eye: every tile slides the way `collapse` moved it (merging pairs
    /// slide onto the same cell), then merged tiles pop and the newly spawned tile zooms in.
    private func animateMove(from before: [[Int]], dir: Direction) {
        let n = before.count
        guard n > 0 else { return }
        // Make sure we start from the board as it was before this move.
        let visible = tiles.allSatisfy { $0.r < n && $0.c < n && before[$0.r][$0.c] == $0.value }
            && tiles.count == before.flatMap { $0 }.filter { $0 != 0 }.count
        if !visible {
            var out: [SlideTile] = []
            for r in 0..<n { for c in 0..<n where before[r][c] != 0 { out.append(SlideTile(id: newTileID(), value: before[r][c], r: r, c: c)) } }
            tiles = out
        }
        var byCell: [Int: SlideTile] = [:]
        for t in tiles { byCell[t.r * n + t.c] = t }
        var moved: [SlideTile] = []
        var merges: [(r: Int, c: Int, value: Int)] = []
        for line in 0..<n {
            let cells: [(r: Int, c: Int)] = (0..<n).map { k in
                switch dir {
                case .left:  return (line, k)
                case .right: return (line, n - 1 - k)
                case .up:    return (k, line)
                case .down:  return (n - 1 - k, line)
                }
            }
            let run = cells.compactMap { byCell[$0.r * n + $0.c] }
            var i = 0, slot = 0
            while i < run.count {
                let dest = cells[slot]
                if i + 1 < run.count && run[i].value == run[i + 1].value {
                    for k in 0..<2 { var t = run[i + k]; t.r = dest.r; t.c = dest.c; moved.append(t) }
                    merges.append((dest.r, dest.c, run[i].value * 2))
                    i += 2
                } else {
                    var t = run[i]; t.r = dest.r; t.c = dest.c
                    moved.append(t)
                    i += 1
                }
                slot += 1
            }
        }
        moveToken += 1
        let token = moveToken
        withAnimation(.easeInOut(duration: 0.1)) { tiles = moved }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.1))
            guard token == moveToken else { return }
            let mergedCells = Set(merges.map { $0.r * n + $0.c })
            var out = tiles.filter { !mergedCells.contains($0.r * n + $0.c) }
            for m in merges { out.append(SlideTile(id: newTileID(), value: m.value, r: m.r, c: m.c, merged: true)) }
            let covered = Set(out.map { $0.r * n + $0.c })
            for r in 0..<grid.count {
                for c in 0..<grid[r].count where grid[r][c] != 0 && !covered.contains(r * n + c) {
                    out.append(SlideTile(id: newTileID(), value: grid[r][c], r: r, c: c))
                }
            }
            // The board is the truth: if the replay disagrees with it anywhere, snap to it.
            let agrees = out.count == grid.flatMap { $0 }.filter { $0 != 0 }.count
                && out.allSatisfy { $0.r < grid.count && $0.c < grid.count && grid[$0.r][$0.c] == $0.value }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.62)) {
                if agrees { tiles = out } else { rebuildTiles() }
            }
        }
    }

    // MARK: - Flow

    private func setup() {
        grid = Array(repeating: Array(repeating: 0, count: side), count: side)
        spawnTile()
        spawnTile()
        rebuildTiles()
    }

    private func handleSwipe(_ translation: CGSize) {
        guard !done else { return }
        let dir: Direction = abs(translation.width) > abs(translation.height)
            ? (translation.width > 0 ? .right : .left)
            : (translation.height > 0 ? .down : .up)

        let before = grid
        apply(dir)
        guard grid != before else { return }   // an illegal move changes nothing

        Haptics.tap()
        SoundManager.shared.tap()
        spawnTile()
        animateMove(from: before, dir: dir)

        if bestTile >= target {
            done = true
            onWin()
        } else if !hasMoves() {
            done = true
            Haptics.warning()
            SoundManager.shared.error()
            onFail()
        }
    }

    private enum Direction { case up, down, left, right }

    /// Slides and merges the whole board in one direction.
    private func apply(_ dir: Direction) {
        switch dir {
        case .left:
            grid = grid.map { collapse($0) }
        case .right:
            grid = grid.map { collapse($0.reversed()).reversed() }
        case .up:
            transpose()
            grid = grid.map { collapse($0) }
            transpose()
        case .down:
            transpose()
            grid = grid.map { collapse($0.reversed()).reversed() }
            transpose()
        }
    }

    /// Compacts a line toward the start and merges equal neighbors once each.
    private func collapse(_ line: [Int]) -> [Int] {
        var tiles = line.filter { $0 != 0 }
        var merged: [Int] = []
        var i = 0
        while i < tiles.count {
            if i + 1 < tiles.count && tiles[i] == tiles[i + 1] {
                merged.append(tiles[i] * 2)
                i += 2
            } else {
                merged.append(tiles[i])
                i += 1
            }
        }
        while merged.count < line.count { merged.append(0) }
        return merged
    }

    private func transpose() {
        var t = Array(repeating: Array(repeating: 0, count: side), count: side)
        for r in 0..<side {
            for c in 0..<side {
                t[c][r] = grid[r][c]
            }
        }
        grid = t
    }

    private func spawnTile() {
        var empties: [(Int, Int)] = []
        for r in 0..<side {
            for c in 0..<side where grid[r][c] == 0 {
                empties.append((r, c))
            }
        }
        guard let (r, c) = empties.randomElement() else { return }
        grid[r][c] = Int.random(in: 0..<10) == 0 ? 4 : 2   // 10% chance of a 4
    }

    /// A move is possible if any cell is empty or any two neighbors are equal.
    private func hasMoves() -> Bool {
        for r in 0..<side {
            for c in 0..<side {
                if grid[r][c] == 0 { return true }
                if c + 1 < side && grid[r][c] == grid[r][c + 1] { return true }
                if r + 1 < side && grid[r][c] == grid[r + 1][c] { return true }
            }
        }
        return false
    }
}

// MARK: - 2048 art

/// One tile as a moving piece (presentation only; `grid` stays the source of truth).
private struct SlideTile: Identifiable, Equatable {
    let id: Int
    var value: Int
    var r: Int
    var c: Int
    var merged = false
}

/// Gabriele Cirulli's 2048 palette.
private enum SlideArt {
    static let page = Color(red: 0.98, green: 0.973, blue: 0.937)      // #FAF8EF
    static let board = Color(red: 0.733, green: 0.678, blue: 0.627)    // #BBADA0
    static let slot = Color(red: 0.804, green: 0.757, blue: 0.706)     // #CDC1B4
    static let ink = Color(red: 0.467, green: 0.431, blue: 0.396)      // #776E65
    static let light = Color(red: 0.976, green: 0.965, blue: 0.949)    // #F9F6F2

    static func color(_ v: Int) -> Color {
        switch v {
        case 2:    return Color(red: 0.933, green: 0.894, blue: 0.855)   // #EEE4DA
        case 4:    return Color(red: 0.929, green: 0.878, blue: 0.784)   // #EDE0C8
        case 8:    return Color(red: 0.949, green: 0.694, blue: 0.475)   // #F2B179
        case 16:   return Color(red: 0.961, green: 0.584, blue: 0.388)   // #F59563
        case 32:   return Color(red: 0.965, green: 0.486, blue: 0.373)   // #F67C5F
        case 64:   return Color(red: 0.965, green: 0.369, blue: 0.231)   // #F65E3B
        case 128:  return Color(red: 0.929, green: 0.812, blue: 0.447)   // #EDCF72
        case 256:  return Color(red: 0.929, green: 0.8, blue: 0.38)      // #EDCC61
        case 512:  return Color(red: 0.929, green: 0.784, blue: 0.314)   // #EDC850
        case 1024: return Color(red: 0.929, green: 0.773, blue: 0.247)   // #EDC53F
        case 2048: return Color(red: 0.929, green: 0.761, blue: 0.18)    // #EDC22E
        default:   return Color(red: 0.235, green: 0.227, blue: 0.196)   // #3C3A32
        }
    }
}

/// A 2048 tile: flat colour, heavy numerals (dark on 2/4, light from 8), a golden glow from 128.
private struct SlideTileView: View {
    let value: Int
    let size: CGFloat

    var body: some View {
        let digits = String(value).count
        let fontSize = size * (digits <= 2 ? 0.5 : digits == 3 ? 0.42 : 0.33)
        RoundedRectangle(cornerRadius: size * 0.06)
            .fill(SlideArt.color(value))
            .frame(width: size, height: size)
            .overlay(
                Text("\(value)")
                    .font(.system(size: fontSize, weight: .heavy))
                    .foregroundStyle(value <= 4 ? SlideArt.ink : SlideArt.light)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(size * 0.06)
            )
            .shadow(color: value >= 128 ? Color(red: 0.95, green: 0.8, blue: 0.3).opacity(0.55) : .clear,
                    radius: value >= 128 ? size * 0.12 : 0)
    }
}

/// The taupe board and its empty slots (static).
private struct SlideSlots: View, Equatable {
    let n: Int
    let size: CGFloat

    var body: some View {
        Canvas { ctx, s in
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: s), cornerRadius: s.width * 0.02), with: .color(SlideArt.board))
            let gap = s.width / (CGFloat(n) * 7.2 + 1)
            let cell = (s.width - gap * CGFloat(n + 1)) / CGFloat(n)
            for r in 0..<n {
                for c in 0..<n {
                    let rect = CGRect(x: gap + (cell + gap) * CGFloat(c), y: gap + (cell + gap) * CGFloat(r), width: cell, height: cell)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: cell * 0.06), with: .color(SlideArt.slot))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
