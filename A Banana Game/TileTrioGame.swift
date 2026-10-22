//
//  TileTrioGame.swift
//  GOGs
//
//  Brain — Tile Trio, the "Tile Master" triple-match genre. Fruit tiles are stacked in layered,
//  symmetric pyramids; a tile is only free when nothing above overlaps it (covered tiles dim).
//  Tap free tiles to send them to the 7-slot tray, where matching tiles line up together and any
//  three alike merge and pop. Clear the whole board to win; if the tray ever fills with seven tiles
//  and no trio, or the clock runs out, it's back to level 1.
//
//  Every board is winnable: the layout is built first, a random legal uncovering order is drawn,
//  and fruit kinds are assigned along that order so its tray never holds more than a level's
//  "load" — the player just has to find a good order. Later levels stack deeper, add near-lookalike
//  fruit (cherry / strawberry / apple, pear / lemon / pineapple…) and interleave the trios more.
//

import SwiftUI

enum TileTrioGame {
    static let definition = GameDefinition(
        id: "tile-trio",
        title: "Tile Trio",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Tap a free tile to move it into the tray; dimmed tiles are covered and can't be picked.",
                "Three matching tiles in the tray pop and free up space.",
                "Clear every tile from the board to win.",
                "If the tray fills with seven tiles, or time runs out, you're back to level 1.",
            ],
            bulletsVI: [
                "Chạm một ô trống để đưa vào khay; ô bị tối đang bị che và không chọn được.",
                "Ba ô giống nhau trong khay sẽ nổ và giải phóng chỗ.",
                "Dọn sạch mọi ô trên bàn để thắng.",
                "Nếu khay đầy bảy ô, hoặc hết giờ, bạn về lại cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(TileTrioView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

// MARK: - Model & generator

private struct TTTile: Identifiable, Equatable, Sendable {
    let id: Int
    let x: Int, y: Int, z: Int      // half-tile grid position and layer
    let kind: FruitKind
}

private nonisolated enum TTGen {
    struct Params: Sendable {
        /// Base footprint in whole tiles, then one letter per upper layer:
        /// "o" = shifted half a tile right+down (one tile smaller each way), "s" = an exact pile on
        /// the layer below (only a sliver of the lower tile shows).
        let cols: Int, rows: Int, schedule: String
        let count: Int, kinds: Int, maxLoad: Int, pNew: Double
    }

    /// Kind order: clearly different fruit first, lookalikes join on later levels.
    static let kindOrder: [FruitKind] = [.cherry, .grape, .pear, .melon, .dekopon, .peach, .watermelon,
                                         .banana, .strawberry, .lemon, .apple, .pineapple, .persimmon]

    static func overlaps(_ a: (Int, Int), _ b: (Int, Int)) -> Bool { abs(a.0 - b.0) < 2 && abs(a.1 - b.1) < 2 }

    /// A symmetric layered pyramid following the level's schedule, trimmed symmetrically from the
    /// top layer if it overshoots `count`.
    static func layout(_ p: Params) -> [(x: Int, y: Int, z: Int)] {
        var pos: [(x: Int, y: Int, z: Int)] = []
        var layer: [(x: Int, y: Int)] = []
        for y in 0..<p.rows { for x in 0..<p.cols { layer.append((x * 2, y * 2)) } }
        pos += layer.map { ($0.x, $0.y, 0) }
        for (i, mode) in p.schedule.enumerated() {
            if mode == "o" {
                // Every 2×2 block of the layer below gets a tile on its centre.
                let set = Set(layer.map { $0.x * 1000 + $0.y })
                layer = layer.filter { set.contains(($0.x + 2) * 1000 + $0.y) && set.contains($0.x * 1000 + $0.y + 2)
                                       && set.contains(($0.x + 2) * 1000 + $0.y + 2) }
                    .map { ($0.x + 1, $0.y + 1) }
            }
            pos += layer.map { ($0.x, $0.y, i + 1) }
        }
        // Trim the top layer symmetrically: mirror pairs, or the centre column for an odd excess.
        let topZ = p.schedule.count
        let minX = pos.map(\.x).min() ?? 0, maxX = pos.map(\.x).max() ?? 0
        let mirror = minX + maxX
        var guardCount = 0
        while pos.count > p.count && guardCount < 200 {
            guardCount += 1
            let diff = pos.count - p.count
            let top = pos.indices.filter { pos[$0].z == topZ }.shuffled()
            if diff % 2 == 1, let i = top.first(where: { pos[$0].x * 2 == mirror }) {
                pos.remove(at: i); continue
            }
            if let i = top.first(where: { pos[$0].x * 2 != mirror }),
               let j = pos.firstIndex(where: { $0.z == topZ && $0.x == mirror - pos[i].x && $0.y == pos[i].y }) {
                pos.remove(at: max(i, j)); pos.remove(at: min(i, j)); continue
            }
            if let i = top.first { pos.remove(at: i) } else { break }
        }
        return pos
    }

    /// Assigns kinds along a random legal uncovering order so that order never loads the tray past
    /// `maxLoad` tiles — a guaranteed solution.
    static func generate(_ p: Params) -> [TTTile] {
        for _ in 0..<60 {
            let pos = layout(p)
            guard pos.count % 3 == 0, pos.count >= 3 else { continue }
            // Random uncovering order.
            var remaining = Array(pos.indices)
            var order: [Int] = []
            while !remaining.isEmpty {
                let frees = remaining.filter { i in
                    !remaining.contains { j in pos[j].z > pos[i].z && overlaps((pos[j].x, pos[j].y), (pos[i].x, pos[i].y)) }
                }
                guard let pick = frees.randomElement() else { break }
                order.append(pick)
                remaining.removeAll { $0 == pick }
            }
            guard order.count == pos.count else { continue }
            let kinds = Array(kindOrder.prefix(p.kinds))
            if let assignment = assign(order: order, kinds: kinds, maxLoad: p.maxLoad, pNew: p.pNew) {
                return pos.indices.map { i in
                    TTTile(id: i, x: pos[i].x, y: pos[i].y, z: pos[i].z, kind: assignment[i]!)
                }
            }
        }
        return []
    }

    static func assign(order: [Int], kinds: [FruitKind], maxLoad: Int, pNew: Double) -> [Int: FruitKind]? {
        let n = order.count, triples = n / 3
        var queue = (0..<triples).map { kinds[$0 % kinds.count] }.shuffled()
        var open: [(kind: FruitKind, count: Int)] = []
        var result: [Int: FruitKind] = [:]
        for (i, tile) in order.enumerated() {
            let left = n - i
            let need = open.reduce(0) { $0 + 3 - $1.count }
            let load = open.reduce(0) { $0 + $1.count }
            // Opening must never strand the plan at the cap with no pair left to finish.
            let canOpen = !queue.isEmpty && need + 3 <= left
                && (load + 1 < maxLoad || (load + 1 == maxLoad && open.contains { $0.count == 2 }))
            // Continuing an open trio: completing it clears it, otherwise it adds one tile.
            let continuable = open.indices.filter { open[$0].count == 2 || load + 1 <= maxLoad }
            let wantNew = canOpen && (open.isEmpty || Double.random(in: 0..<1) < pNew || continuable.isEmpty)
            if wantNew && need < left {
                // Prefer a kind that isn't already waiting in the tray.
                let k = queue.firstIndex { q in !open.contains { $0.kind == q } } ?? 0
                let kind = queue.remove(at: k)
                result[tile] = kind
                open.append((kind, 1))
            } else {
                guard let j = continuable.randomElement() else { return nil }
                result[tile] = open[j].kind
                open[j].count += 1
                if open[j].count == 3 { open.remove(at: j) }
            }
        }
        return open.isEmpty && queue.isEmpty ? result : nil
    }
}

// MARK: - View

struct TileTrioView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void
    @Environment(\.isDemo) private var isDemo

    private var params: TTGen.Params {
        [TTGen.Params(cols: 4, rows: 3, schedule: "o", count: 18, kinds: 6, maxLoad: 3, pNew: 0.25),
         TTGen.Params(cols: 4, rows: 4, schedule: "oo", count: 27, kinds: 7, maxLoad: 4, pNew: 0.35),
         TTGen.Params(cols: 5, rows: 4, schedule: "oo", count: 36, kinds: 8, maxLoad: 4, pNew: 0.45),
         TTGen.Params(cols: 4, rows: 4, schedule: "osos", count: 42, kinds: 9, maxLoad: 5, pNew: 0.5),
         TTGen.Params(cols: 5, rows: 4, schedule: "oso", count: 48, kinds: 10, maxLoad: 5, pNew: 0.55),
         TTGen.Params(cols: 5, rows: 4, schedule: "osos", count: 54, kinds: 12, maxLoad: 6, pNew: 0.65),
         TTGen.Params(cols: 5, rows: 5, schedule: "ooso", count: 63, kinds: 13, maxLoad: 6, pNew: 0.75)][min(level, 7) - 1]
    }
    private var timeLimit: Double { [60, 70, 80, 85, 90, 90, 90][min(level, 7) - 1] }
    private let slots = 7

    private static let bgTop = Color(red: 0.40, green: 0.76, blue: 0.74)
    private static let bgBottom = Color(red: 0.16, green: 0.49, blue: 0.55)

    private enum Phase { case play, won, stuck, done }

    @State private var phase: Phase = .play
    @State private var board: [TTTile] = []
    @State private var tray: [TTTile] = []
    @State private var matching: Set<Int> = []
    @State private var converge: [Int: Int] = [:]     // tile id → tile id it merges into
    private struct Burst: Identifiable { let id: Int; let slot: Int; let color: Color }
    @State private var bursts: [Burst] = []
    @State private var extent = (minX: 0, maxX: 2, minY: 0, maxY: 2, layers: 1)
    @State private var total = 0
    @State private var timeLeft = 0.0
    @State private var burstID = 0
    @State private var demoTap: Int? = nil           // tile id under the demo finger
    @State private var demoRipple = 0

    var body: some View {
        GeometryReader { geo in
            let lay = layout(geo.size)
            ZStack {
                LinearGradient(colors: [Self.bgTop, Self.bgBottom], startPoint: .top, endPoint: .bottom)
                statusBar
                    .frame(width: geo.size.width)
                    .position(x: geo.size.width / 2, y: lay.statusY)
                trayView(lay)
                let blocked = blockedIDs()
                ForEach(board + tray) { t in
                    let slot = tray.firstIndex { $0.id == t.id }
                    tileView(t, blocked: slot == nil && blocked.contains(t.id), size: slot == nil ? lay.tile : lay.slot * 0.9)
                        .position(tilePoint(t, slot: slot, lay))
                        .zIndex(tileZ(t, slot: slot))
                        .onTapGesture { if !isDemo { tap(t.id) } }
                        .transition(.scale(scale: 1.35).combined(with: .opacity))
                }
                ForEach(bursts) { b in
                    ParticleBurstView(color: b.color, count: 16, spread: lay.slot * 1.3, gravity: 6)
                        .position(trayPoint(b.slot, lay))
                        .zIndex(20_000)
                        .allowsHitTesting(false)
                }
                if isDemo, let id = demoTap, let t = board.first(where: { $0.id == id }) {
                    demoFinger(at: boardPoint(t, lay), size: lay.tile)
                        .zIndex(30_000)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
    }

    private var statusBar: some View {
        VStack(spacing: isDemo ? 2 : 8) {
            if !isDemo {
                GeometryReader { g in
                    let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(.black.opacity(0.18))
                        Capsule().fill(frac < 0.3 ? .red : BananaTheme.banana).frame(width: g.size.width * frac)
                    }
                }
                .frame(height: 6)
                .padding(.horizontal, 40)
            }
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(Color(red: 1, green: 0.97, blue: 0.9))
                    .frame(width: isDemo ? 11 : 14, height: isDemo ? 11 : 14)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(red: 0.29, green: 0.6, blue: 0.44), lineWidth: 2))
                Text("\(board.count + tray.count - matching.count)")
                    .contentTransition(.numericText())
            }
            .font(.system(size: isDemo ? 15 : 20, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 0, x: 0, y: 1.5)
        }
    }

    // MARK: Layout

    private struct Lay {
        let origin: CGPoint      // top-left of the board grid
        let tile: CGFloat
        let tray: CGRect
        let slot: CGFloat
        let statusY: CGFloat
        let lift: CGSize         // per-layer offset
    }

    private func layout(_ s: CGSize) -> Lay {
        let pad: CGFloat = isDemo ? 8 : 14
        let statusH: CGFloat = isDemo ? 24 : 56
        let slot = min((s.width - pad * 2 - 16) / CGFloat(slots), isDemo ? 40 : 54)
        let trayH = slot + 16
        let tray = CGRect(x: (s.width - (slot * CGFloat(slots) + 16)) / 2, y: s.height - pad - trayH,
                          width: slot * CGFloat(slots) + 16, height: trayH)
        let spanX = CGFloat(extent.maxX - extent.minX + 2) / 2
        let spanY = CGFloat(extent.maxY - extent.minY + 2) / 2
        let availW = s.width - pad * 2
        let availH = tray.minY - statusH - pad * 1.5
        let liftK = CGSize(width: -0.03, height: -0.05)
        let depth = CGFloat(max(0, extent.layers - 1)) * 0.05 + 0.1   // layer lift + tile thickness
        let tile = max(10, min(availW / spanX, availH / (spanY + depth), isDemo ? 58 : 88))
        let bw = tile * spanX, bh = tile * (spanY + depth)
        let origin = CGPoint(x: (s.width - bw) / 2 - CGFloat(extent.minX) * tile / 2,
                             y: statusH + pad * 0.5 + (availH - bh) / 2 + CGFloat(max(0, extent.layers - 1)) * tile * 0.05
                                - CGFloat(extent.minY) * tile / 2)
        return Lay(origin: origin, tile: tile, tray: tray, slot: slot, statusY: statusH / 2 + (isDemo ? 4 : 6),
                   lift: CGSize(width: liftK.width * tile, height: liftK.height * tile))
    }

    private func boardPoint(_ t: TTTile, _ l: Lay) -> CGPoint {
        CGPoint(x: l.origin.x + CGFloat(t.x + 1) * l.tile / 2 + CGFloat(t.z) * l.lift.width,
                y: l.origin.y + CGFloat(t.y + 1) * l.tile / 2 + CGFloat(t.z) * l.lift.height)
    }

    private func tilePoint(_ t: TTTile, slot: Int?, _ l: Lay) -> CGPoint {
        guard var i = slot else { return boardPoint(t, l) }
        // A popping trio slides together onto its middle tile first.
        if let into = converge[t.id], let j = tray.firstIndex(where: { $0.id == into }) { i = j }
        return trayPoint(i, l)
    }

    private func tileZ(_ t: TTTile, slot: Int?) -> Double {
        if let slot { return 10_000 + Double(slot) }
        return Double(t.z * 1000 + t.y * 10 + t.x)
    }

    private func trayPoint(_ i: Int, _ l: Lay) -> CGPoint {
        CGPoint(x: l.tray.minX + 8 + (CGFloat(min(i, slots - 1)) + 0.5) * l.slot, y: l.tray.midY - 2)
    }

    // MARK: Pieces

    private func tileView(_ t: TTTile, blocked: Bool, size: CGFloat) -> some View {
        let r = size * 0.17
        return ZStack {
            // Thickness: the green mahjong-style base peeking out below the face.
            RoundedRectangle(cornerRadius: r)
                .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.7, blue: 0.5), Color(red: 0.2, green: 0.5, blue: 0.36)],
                                     startPoint: .top, endPoint: .bottom))
                .offset(y: size * 0.1)
            RoundedRectangle(cornerRadius: r)
                .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.99, blue: 0.95), Color(red: 0.95, green: 0.91, blue: 0.8)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: r).stroke(Color(red: 0.82, green: 0.74, blue: 0.58), lineWidth: max(1, size * 0.025)))
            FruitIcon(kind: t.kind, scale: 0.33)
                .frame(width: size * 0.92, height: size * 0.92)
        }
        .frame(width: size, height: size)
        .compositingGroup()
        .saturation(blocked ? 0.55 : 1)
        .brightness(blocked ? -0.32 : 0)
        .shadow(color: .black.opacity(0.28), radius: size * 0.05, x: 0, y: size * 0.12)
        .animation(.easeOut(duration: 0.18), value: blocked)
    }

    private func trayView(_ l: Lay) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.36, blue: 0.2), Color(red: 0.38, green: 0.23, blue: 0.12)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 0.26, green: 0.15, blue: 0.07), lineWidth: 3))
                .shadow(color: .black.opacity(0.3), radius: 6, y: 4)
            HStack(spacing: 0) {
                ForEach(0..<slots, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color(red: 0.3, green: 0.18, blue: 0.09).opacity(0.75))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.black.opacity(0.25), lineWidth: 1))
                        .padding(3)
                        .frame(width: l.slot, height: l.slot)
                }
            }
        }
        .frame(width: l.tray.width, height: l.tray.height)
        .position(x: l.tray.midX, y: l.tray.midY)
    }

    private func demoFinger(at p: CGPoint, size: CGFloat) -> some View {
        ZStack {
            DemoTapRipple().id(demoRipple)
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: size * 0.5))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 3)
                .offset(x: size * 0.2, y: size * 0.3)
        }
        .position(p)
        .allowsHitTesting(false)
    }

    // MARK: Rules

    private func blockedIDs() -> Set<Int> {
        var out = Set<Int>()
        for a in board {
            if board.contains(where: { $0.z > a.z && TTGen.overlaps(($0.x, $0.y), (a.x, a.y)) }) { out.insert(a.id) }
        }
        return out
    }

    private func tap(_ id: Int) {
        guard phase == .play, let idx = board.firstIndex(where: { $0.id == id }) else { return }
        let t = board[idx]
        guard !blockedIDs().contains(id) else { return }
        SoundManager.shared.tap(); Haptics.tap()

        // Land next to its twins (the tray keeps matching tiles together).
        let insertAt = tray.lastIndex { $0.kind == t.kind && !matching.contains($0.id) }.map { $0 + 1 } ?? tray.count
        withAnimation(.easeOut(duration: 0.2)) {
            board.remove(at: idx)
            tray.insert(t, at: insertAt)
        }
        let twins = tray.filter { $0.kind == t.kind && !matching.contains($0.id) }
        if twins.count >= 3 {
            let trio = Array(twins.prefix(3))
            let ids = Set(trio.map(\.id))
            matching.formUnion(ids)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.2))
                withAnimation(.easeIn(duration: 0.12)) {
                    for x in trio { converge[x.id] = trio[1].id }
                }
                try? await Task.sleep(for: .seconds(0.13))
                let slot = tray.firstIndex { $0.id == trio[1].id } ?? 0
                burstID += 1
                let myBurst = burstID
                bursts.append(Burst(id: myBurst, slot: slot, color: FruitArt.color(t.kind)))
                withAnimation(.easeOut(duration: 0.22)) {
                    tray.removeAll { ids.contains($0.id) }
                }
                matching.subtract(ids)
                for x in trio { converge[x.id] = nil }
                SoundManager.shared.tap()
                Haptics.success()
                try? await Task.sleep(for: .seconds(0.6))
                bursts.removeAll { $0.id == myBurst }
            }
        } else if tray.count - matching.count >= slots {
            phase = .stuck
            Haptics.warning()
        }
    }

    // MARK: Flow

    private func load(_ tiles: [TTTile]) {
        board = tiles
        tray = []
        matching = []
        converge = [:]
        total = tiles.count
        extent = (tiles.map(\.x).min() ?? 0, tiles.map(\.x).max() ?? 2, tiles.map(\.y).min() ?? 0,
                  tiles.map(\.y).max() ?? 2, (tiles.map(\.z).max() ?? 0) + 1)
    }

    private func run() async {
        let p = params
        let tiles = await Task.detached(priority: .userInitiated) { TTGen.generate(p) }.value
        guard !Task.isCancelled else { return }
        load(tiles)
        phase = .play
        timeLeft = timeLimit
        let start = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(0.05))
            switch phase {
            case .play:
                timeLeft = max(0, timeLimit - Date().timeIntervalSince(start))
                if board.isEmpty && tray.isEmpty && total > 0 {
                    phase = .won
                } else if timeLeft <= 0 {
                    fail(); return
                }
            case .won:
                try? await Task.sleep(for: .seconds(0.3))
                guard !Task.isCancelled else { return }
                phase = .done
                onWin()
                return
            case .stuck:
                try? await Task.sleep(for: .seconds(0.8))
                guard !Task.isCancelled else { return }
                fail()
                return
            case .done:
                return
            }
        }
    }

    private func fail() {
        guard phase == .play || phase == .stuck else { return }
        phase = .done
        SoundManager.shared.error()
        onFail()
    }

    // MARK: - Demo (live manual clip)
    // A fixed 12-tile, two-layer pyramid (3×3 base, three tiles on top). The script taps through the
    // real `tap`: cherry, grape, then a second cherry that slots in NEXT to the first, a third cherry
    // freed underneath (trio pops), the two grapes (pop), then the melons and oranges — board clear.
    private static let demoTiles: [TTTile] = [
        TTTile(id: 0, x: 1, y: 1, z: 1, kind: .cherry), TTTile(id: 1, x: 3, y: 1, z: 1, kind: .grape),
        TTTile(id: 2, x: 2, y: 3, z: 1, kind: .grape),
        TTTile(id: 3, x: 0, y: 0, z: 0, kind: .melon), TTTile(id: 4, x: 2, y: 0, z: 0, kind: .melon),
        TTTile(id: 5, x: 4, y: 0, z: 0, kind: .dekopon), TTTile(id: 6, x: 0, y: 2, z: 0, kind: .cherry),
        TTTile(id: 7, x: 2, y: 2, z: 0, kind: .grape), TTTile(id: 8, x: 4, y: 2, z: 0, kind: .dekopon),
        TTTile(id: 9, x: 0, y: 4, z: 0, kind: .cherry), TTTile(id: 10, x: 2, y: 4, z: 0, kind: .dekopon),
        TTTile(id: 11, x: 4, y: 4, z: 0, kind: .melon),
    ]
    private static let demoOrder = [0, 1, 9, 6, 2, 7, 3, 4, 11, 5, 8, 10]

    private func runDemo() async {
        while !Task.isCancelled {
            load(Self.demoTiles)
            demoTap = nil
            phase = .play
            try? await Task.sleep(for: .seconds(0.7))
            for id in Self.demoOrder {
                guard !Task.isCancelled else { return }
                demoTap = id
                demoRipple += 1
                try? await Task.sleep(for: .seconds(0.22))
                tap(id)
                demoTap = nil
                try? await Task.sleep(for: .seconds(0.3))
            }
            try? await Task.sleep(for: .seconds(1.5))
        }
    }
}
