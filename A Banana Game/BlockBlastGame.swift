//
//  BlockBlastGame.swift
//  GOGs
//
//  Brain — Block Blast. Drag the three dealt pieces onto an 8×8 board; filling a whole row or
//  column blasts it away. Clear the level's line quota before you run out of room — if none of the
//  pieces left in the tray fits anywhere, it's over (the clock is a backstop).
//
//  Look & feel follow the real game: a navy board of recessed cells on a blue backdrop, glossy
//  bevelled blocks, the dragged piece lifted above the finger at full size, a ghost where it will
//  land, lines that are about to clear re-coloured in the piece's colour, burst clears and
//  "Great!"-style praise on multi-line clears. Unplaceable tray pieces dim.
//
//  Ramp: bigger quotas, more junk pre-placed on the board and a deal mix that shifts from small
//  pieces to 3×3s, 5-longs, big Ls and diagonals. It's a drag game, so the feed locks while playing.
//

import SwiftUI

enum BlockBlastGame {
    static let definition = GameDefinition(
        id: "block-blast",
        title: "Grid Burst",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        locksFeed: true,
        manual: GameManual(
            bullets: [
                "Drag the pieces from the tray onto the board.",
                "Fill a whole row or column to blast it; clearing several at once is worth more.",
                "Clear the line target to win.",
                "If none of your pieces fits anywhere, or time runs out, you're back to level 1.",
            ],
            bulletsVI: [
                "Kéo các khối từ khay lên bàn.",
                "Lấp đầy cả một hàng hoặc một cột để phá nó; phá nhiều hàng cùng lúc càng tốt.",
                "Phá đủ số hàng mục tiêu để thắng.",
                "Nếu không khối nào còn vừa chỗ, hoặc hết giờ, bạn về lại cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(BlockBlastView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

// MARK: - Pieces

private struct BBCell: Hashable { let r: Int; let c: Int }

private struct BBPiece: Equatable, Identifiable {
    let id: Int
    let cells: [BBCell]
    let color: Int
    var rows: Int { (cells.map(\.r).max() ?? 0) + 1 }
    var cols: Int { (cells.map(\.c).max() ?? 0) + 1 }
}

private enum BBShapes {
    static func grid(_ rows: [String]) -> [BBCell] {
        var out: [BBCell] = []
        for (r, line) in rows.enumerated() {
            for (c, ch) in line.enumerated() where ch == "#" { out.append(BBCell(r: r, c: c)) }
        }
        return out
    }

    /// Every orientation of a shape (rotations + mirror), de-duplicated.
    static func orientations(_ base: [BBCell]) -> [[BBCell]] {
        func normalize(_ cs: [BBCell]) -> [BBCell] {
            let mr = cs.map(\.r).min() ?? 0, mc = cs.map(\.c).min() ?? 0
            return cs.map { BBCell(r: $0.r - mr, c: $0.c - mc) }.sorted { ($0.r, $0.c) < ($1.r, $1.c) }
        }
        var seen: [[BBCell]] = []
        var cur = base
        for flip in 0..<2 {
            if flip == 1 { cur = base.map { BBCell(r: $0.r, c: -$0.c) } }
            for _ in 0..<4 {
                cur = cur.map { BBCell(r: $0.c, c: -$0.r) }
                let n = normalize(cur)
                if !seen.contains(n) { seen.append(n) }
            }
        }
        return seen
    }

    // Tiered shape pools (each entry is one orientation, so rotations share the tier's weight).
    static let easy: [[BBCell]] = [grid(["#"]), grid(["##"]), grid(["#", "#"]), grid(["##", "##"]),
                                   grid(["###"]), grid(["#", "#", "#"])] + orientations(grid(["#.", "##"]))
    static let medium: [[BBCell]] = [grid(["####"]), grid(["#", "#", "#", "#"]), grid(["###", "###"]),
                                     grid(["##", "##", "##"])]
        + orientations(grid(["###", ".#."])) + orientations(grid(["#..", "###"]))
        + orientations(grid([".##", "##."]))
    static let hard: [[BBCell]] = [grid(["#####"]), grid(["#", "#", "#", "#", "#"]), grid(["###", "###", "###"]),
                                   grid(["#.", ".#"]), grid([".#", "#."]),
                                   grid(["#..", ".#.", "..#"]), grid(["..#", ".#.", "#.."])]
        + orientations(grid(["#..", "#..", "###"]))
}

// MARK: - View

struct BlockBlastView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void
    @Environment(\.isDemo) private var isDemo

    private let n = 8
    private var target: Int { [4, 6, 8, 10, 12, 14, 16][min(level, 7) - 1] }
    private var prefill: Int { [0, 6, 10, 14, 18, 22, 26][min(level, 7) - 1] }
    private var timeLimit: Double { [90, 90, 90, 95, 95, 90, 85][min(level, 7) - 1] }
    /// Deal weights for the easy / medium / hard shape pools.
    private var mix: (Double, Double, Double) {
        [(0.7, 0.3, 0.0), (0.55, 0.4, 0.05), (0.45, 0.45, 0.1), (0.35, 0.45, 0.2),
         (0.3, 0.45, 0.25), (0.25, 0.4, 0.35), (0.2, 0.4, 0.4)][min(level, 7) - 1]
    }

    // Block Blast palette.
    private static let colors: [Color] = [
        Color(red: 0.93, green: 0.27, blue: 0.27), Color(red: 0.98, green: 0.58, blue: 0.16),
        Color(red: 0.99, green: 0.80, blue: 0.18), Color(red: 0.38, green: 0.78, blue: 0.23),
        Color(red: 0.20, green: 0.76, blue: 0.93), Color(red: 0.24, green: 0.47, blue: 0.93),
        Color(red: 0.62, green: 0.36, blue: 0.91),
    ]
    private static let bgTop = Color(red: 0.27, green: 0.40, blue: 0.84)
    private static let bgBottom = Color(red: 0.15, green: 0.23, blue: 0.58)
    private static let boardColor = Color(red: 0.09, green: 0.12, blue: 0.29)
    private static let emptyCell = Color(red: 0.13, green: 0.17, blue: 0.38)

    private enum Phase { case play, won, stuck, done }

    private struct Held { var slot: Int; var finger: CGPoint }
    private struct ClearFX { let cell: Int; let color: Int; let t0: Date }
    private struct Praise { let text: String; let combo: Int; let t0: Date }

    private struct Layout {
        let board: CGRect
        let cell: CGFloat
        let slots: [CGRect]
        let trayCell: CGFloat
        let status: CGRect
    }

    @State private var phase: Phase = .play
    @State private var cells: [Int?] = []            // colour index per cell, nil = empty
    @State private var tray: [BBPiece?] = [nil, nil, nil]
    @State private var lines = 0
    @State private var combo = 0
    @State private var held: Held? = nil
    @State private var returning: (piece: BBPiece, slot: Int, from: CGPoint, t0: Date)? = nil
    @State private var clears: [ClearFX] = []
    @State private var placedAt: [Int: Date] = [:]
    @State private var praise: Praise? = nil
    @State private var stuckAt: Date? = nil
    @State private var size: CGSize = .zero
    @State private var timeLeft = 0.0
    @State private var nextID = 0
    @State private var demoFinger: CGPoint? = nil
    @State private var demoPressed = false

    private var animating: Bool {
        !clears.isEmpty || praise != nil || !placedAt.isEmpty || stuckAt != nil || returning != nil
    }

    var body: some View {
        GeometryReader { geo in
            let lay = Self.layout(geo.size, demo: isDemo)
            TimelineView(.animation(paused: !animating)) { tl in
                ZStack {
                    LinearGradient(colors: [Self.bgTop, Self.bgBottom], startPoint: .top, endPoint: .bottom)
                    Canvas { ctx, _ in draw(ctx, lay: lay, now: tl.date) }
                    statusBar(lay)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(lay), including: isDemo ? .none : .all)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
    }

    private func statusBar(_ lay: Layout) -> some View {
        VStack(spacing: isDemo ? 4 : 8) {
            if !isDemo {
                GeometryReader { g in
                    let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule().fill(frac < 0.3 ? .red : BananaTheme.banana)
                            .frame(width: g.size.width * frac)
                    }
                }
                .frame(height: 6)
                .padding(.horizontal, 40)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(min(lines, target))")
                    .font(.system(size: isDemo ? 26 : 40, weight: .black, design: .rounded))
                    .contentTransition(.numericText())
                Text("/ \(target)")
                    .font(.system(size: isDemo ? 15 : 20, weight: .heavy, design: .rounded))
                    .opacity(0.7)
                Text(L("LINES", "HÀNG"))
                    .font(.system(size: isDemo ? 12 : 15, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                    .opacity(0.7)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 0, x: 0, y: 2)
        }
        .frame(width: lay.status.width, height: lay.status.height)
        .position(x: lay.status.midX, y: lay.status.midY)
    }

    // MARK: Layout

    private static func layout(_ s: CGSize, demo: Bool) -> Layout {
        let pad: CGFloat = demo ? 10 : 16
        let statusH: CGFloat = demo ? 36 : 74
        let trayH = min(s.width * 0.4, s.height * 0.26)
        let side = max(40, min(s.width - pad * 2, s.height - statusH - trayH - pad * 2))
        let cell = side / 8
        let usedH = statusH + side + trayH
        let top = max(pad * 0.5, (s.height - usedH) / 2)
        let board = CGRect(x: (s.width - side) / 2, y: top + statusH, width: side, height: side)
        let slotW = s.width / 3
        let slots = (0..<3).map { CGRect(x: CGFloat($0) * slotW, y: board.maxY + pad * 0.4, width: slotW, height: trayH) }
        let trayCell = cell * 0.6
        return Layout(board: board, cell: cell, slots: slots, trayCell: trayCell,
                      status: CGRect(x: 0, y: top, width: s.width, height: statusH))
    }

    // MARK: Drawing

    private func draw(_ ctx: GraphicsContext, lay: Layout, now: Date) {
        let b = lay.board, cell = lay.cell
        guard cells.count == n * n else { return }

        // Board: navy slab with recessed cells.
        let slab = b.insetBy(dx: -cell * 0.14, dy: -cell * 0.14)
        ctx.fill(Path(roundedRect: slab, cornerRadius: cell * 0.28), with: .color(Self.boardColor))
        ctx.stroke(Path(roundedRect: slab, cornerRadius: cell * 0.28), with: .color(.black.opacity(0.35)), lineWidth: 2)
        func rect(_ i: Int) -> CGRect {
            CGRect(x: b.minX + CGFloat(i % n) * cell, y: b.minY + CGFloat(i / n) * cell, width: cell, height: cell)
        }
        for i in 0..<n * n {
            let rc = rect(i).insetBy(dx: cell * 0.045, dy: cell * 0.045)
            ctx.fill(Path(roundedRect: rc, cornerRadius: cell * 0.12), with: .color(Self.emptyCell))
            ctx.stroke(Path(roundedRect: rc.insetBy(dx: 0.5, dy: 0.5), cornerRadius: cell * 0.12),
                       with: .color(.black.opacity(0.22)), lineWidth: 1)
        }

        // Where would the held piece land, and which lines would that finish?
        let heldPiece = held.flatMap { tray[$0.slot] }
        var ghost: [Int] = []
        var ghostLines = Set<Int>()
        if let h = held, let p = heldPiece, let spot = snap(p, finger: h.finger, lay: lay) {
            ghost = p.cells.map { (spot.r + $0.r) * n + spot.c + $0.c }
            ghostLines = completedLines(adding: Set(ghost))
        }

        let gray = stuckAt.map { min(1, now.timeIntervalSince($0) / 0.5) } ?? 0
        for i in 0..<n * n {
            guard let col = cells[i] else { continue }
            var color = Self.colors[col]
            if ghostLines.contains(i), let p = heldPiece { color = Self.colors[p.color] }
            if gray > 0 { color = color.mix(with: Color(white: 0.45), by: gray * 0.85) }
            var rc = rect(i).insetBy(dx: cell * 0.03, dy: cell * 0.03)
            if let t = placedAt[i] {
                let k = min(1, now.timeIntervalSince(t) / 0.16)
                let s = 1 + 0.14 * (1 - k)
                rc = rc.insetBy(dx: -rc.width * (s - 1) / 2, dy: -rc.height * (s - 1) / 2)
            }
            Self.drawBlock(ctx, rc, color)
        }
        if let p = heldPiece {
            for i in ghost {
                let color = Self.colors[p.color]
                let rc = rect(i).insetBy(dx: cell * 0.03, dy: cell * 0.03)
                if ghostLines.contains(i) {
                    Self.drawBlock(ctx, rc, color)
                } else {
                    var g = ctx
                    g.opacity = 0.42
                    Self.drawBlock(g, rc, color)
                }
            }
        }

        // Line blasts: blocks flash white and shrink away while chips fly out.
        for fx in clears {
            let t = now.timeIntervalSince(fx.t0)
            guard t < 0.55 else { continue }
            let rc = rect(fx.cell)
            let k = min(1, t / 0.32)
            let color = Self.colors[fx.color].mix(with: .white, by: max(0, 0.7 - k))
            let s = (1 - k) * 0.94
            if s > 0.02 {
                let r2 = CGRect(x: rc.midX - rc.width * s / 2, y: rc.midY - rc.height * s / 2,
                                width: rc.width * s, height: rc.height * s)
                Self.drawBlock(ctx, r2, color)
            }
            for j in 0..<4 {
                let a = Double(fx.cell * 7 + j) * 1.7
                let d = cell * CGFloat(0.4 + t * 2.2)
                let px = rc.midX + CGFloat(cos(a)) * d
                let py = rc.midY + CGFloat(sin(a)) * d + CGFloat(t * t) * cell * 6
                let sz = cell * 0.2 * CGFloat(max(0, 1 - t / 0.55))
                ctx.fill(Path(CGRect(x: px - sz / 2, y: py - sz / 2, width: sz, height: sz)),
                         with: .color(Self.colors[fx.color].lit(0.3)))
            }
        }

        // Tray.
        for (slot, piece) in tray.enumerated() {
            guard let piece, held?.slot != slot, returning?.slot != slot else { continue }
            let fits = canFitAnywhere(piece)
            var g = ctx
            if !fits { g.opacity = 0.35 }
            drawPiece(g, piece, center: CGPoint(x: lay.slots[slot].midX, y: lay.slots[slot].midY),
                      cell: trayCell(piece, slot: slot, lay: lay))
        }

        // A piece flying back to its slot after an illegal drop.
        if let r = returning {
            let k = min(1, now.timeIntervalSince(r.t0) / 0.22)
            let e = 1 - pow(1 - k, 3)
            let to = CGPoint(x: lay.slots[r.slot].midX, y: lay.slots[r.slot].midY)
            let c = CGPoint(x: r.from.x + (to.x - r.from.x) * e, y: r.from.y + (to.y - r.from.y) * e)
            drawPiece(ctx, r.piece, center: c, cell: cell + (trayCell(r.piece, slot: r.slot, lay: lay) - cell) * e)
        }

        // The held piece: full size, lifted above the finger, with a soft drop shadow.
        if let h = held, let p = heldPiece {
            let c = liftedCenter(p, finger: h.finger, cell: cell)
            var s = ctx
            s.addFilter(.shadow(color: .black.opacity(0.35), radius: cell * 0.2, x: 0, y: cell * 0.25))
            drawPiece(s, p, center: c, cell: cell)
        }

        // Praise banner.
        if let pr = praise {
            let t = now.timeIntervalSince(pr.t0)
            if t < 1.0 {
                let pop = t < 0.18 ? 0.6 + 0.55 * (t / 0.18) : max(1.0, 1.15 - (t - 0.18) * 0.8)
                let alpha = t > 0.75 ? max(0, 1 - (t - 0.75) / 0.25) : 1
                let center = CGPoint(x: b.midX, y: b.midY - cell * 0.4 - CGFloat(t) * cell * 0.5)
                drawBanner(ctx, pr.text, at: center, size: cell * 0.95 * CGFloat(pop), alpha: alpha)
                if pr.combo >= 2 {
                    drawBanner(ctx, L("COMBO \(pr.combo)", "COMBO \(pr.combo)"),
                               at: CGPoint(x: center.x, y: center.y + cell * 0.95), size: cell * 0.5, alpha: alpha)
                }
            }
        }

        // Demo finger.
        if let f = demoFinger {
            var hand = ctx.resolve(Image(systemName: "hand.point.up.left.fill"))
            hand.shading = .color(.white)
            var h = ctx
            h.addFilter(.shadow(color: .black.opacity(0.55), radius: 3))
            let w = cell * (demoPressed ? 0.95 : 1.05)
            h.draw(hand, in: CGRect(x: f.x - w * 0.28, y: f.y - w * 0.08, width: w, height: w))
        }
    }

    /// Tray pieces sit at ~60% of a board cell; only long pieces shrink to fit their slot.
    private func trayCell(_ p: BBPiece, slot: Int, lay: Layout) -> CGFloat {
        let s = lay.slots[slot]
        return min(lay.trayCell, s.width * 0.86 / CGFloat(p.cols), s.height * 0.86 / CGFloat(p.rows))
    }

    private func drawBanner(_ ctx: GraphicsContext, _ text: String, at p: CGPoint, size: CGFloat, alpha: Double) {
        var g = ctx
        g.opacity = alpha
        let font = Font.system(size: size, weight: .black, design: .rounded)
        let outline = g.resolve(Text(text).font(font).foregroundStyle(Color(red: 0.35, green: 0.12, blue: 0.02)))
        for k in 0..<8 {
            let a = Double(k) * .pi / 4
            g.draw(outline, at: CGPoint(x: p.x + CGFloat(cos(a)) * size * 0.07, y: p.y + CGFloat(sin(a)) * size * 0.07 + size * 0.04))
        }
        var fill = g.resolve(Text(text).font(font))
        fill.shading = .linearGradient(Gradient(colors: [Color(red: 1, green: 0.97, blue: 0.55), Color(red: 1, green: 0.62, blue: 0.1)]),
                                       startPoint: CGPoint(x: p.x, y: p.y - size * 0.5), endPoint: CGPoint(x: p.x, y: p.y + size * 0.5))
        g.draw(fill, at: p)
    }

    private func drawPiece(_ ctx: GraphicsContext, _ p: BBPiece, center: CGPoint, cell: CGFloat) {
        let ox = center.x - CGFloat(p.cols) * cell / 2, oy = center.y - CGFloat(p.rows) * cell / 2
        for c in p.cells {
            let rc = CGRect(x: ox + CGFloat(c.c) * cell, y: oy + CGFloat(c.r) * cell, width: cell, height: cell)
            Self.drawBlock(ctx, rc.insetBy(dx: cell * 0.03, dy: cell * 0.03), Self.colors[p.color])
        }
    }

    /// A glossy bevelled block: lit top/left edges, shaded right/bottom, a gradient face and a glint.
    private static func drawBlock(_ ctx: GraphicsContext, _ r: CGRect, _ base: Color) {
        let radius = r.width * 0.12
        let body = Path(roundedRect: r, cornerRadius: radius)
        var c = ctx
        c.clip(to: body)
        c.fill(body, with: .color(base))
        let b = r.width * 0.15
        func quad(_ pts: [CGPoint]) -> Path { var p = Path(); p.addLines(pts); p.closeSubpath(); return p }
        let tl = CGPoint(x: r.minX, y: r.minY), tr = CGPoint(x: r.maxX, y: r.minY)
        let bl = CGPoint(x: r.minX, y: r.maxY), br = CGPoint(x: r.maxX, y: r.maxY)
        let itl = CGPoint(x: r.minX + b, y: r.minY + b), itr = CGPoint(x: r.maxX - b, y: r.minY + b)
        let ibl = CGPoint(x: r.minX + b, y: r.maxY - b), ibr = CGPoint(x: r.maxX - b, y: r.maxY - b)
        c.fill(quad([tl, tr, itr, itl]), with: .color(base.lit(0.45)))
        c.fill(quad([tl, itl, ibl, bl]), with: .color(base.lit(0.2)))
        c.fill(quad([tr, br, ibr, itr]), with: .color(base.shade(0.2)))
        c.fill(quad([bl, ibl, ibr, br]), with: .color(base.shade(0.4)))
        let face = CGRect(x: r.minX + b, y: r.minY + b, width: r.width - 2 * b, height: r.height - 2 * b)
        c.fill(Path(face), with: .linearGradient(Gradient(colors: [base.lit(0.14), base.shade(0.04)]),
                                                 startPoint: CGPoint(x: face.midX, y: face.minY),
                                                 endPoint: CGPoint(x: face.midX, y: face.maxY)))
        c.fill(Path(roundedRect: CGRect(x: face.minX + face.width * 0.08, y: face.minY + face.height * 0.08,
                                        width: face.width * 0.26, height: face.height * 0.14),
                    cornerRadius: face.height * 0.07),
               with: .color(.white.opacity(0.5)))
    }

    // MARK: Rules

    private func fits(_ p: BBPiece, r: Int, c: Int) -> Bool {
        guard r >= 0, c >= 0, r + p.rows <= n, c + p.cols <= n else { return false }
        return p.cells.allSatisfy { cells[(r + $0.r) * n + c + $0.c] == nil }
    }

    private func canFitAnywhere(_ p: BBPiece) -> Bool {
        guard cells.count == n * n else { return false }
        for r in 0...(n - p.rows) {
            for c in 0...(n - p.cols) where fits(p, r: r, c: c) { return true }
        }
        return false
    }

    /// Cells of every row/column that would be complete if `extra` cells were filled too.
    private func completedLines(adding extra: Set<Int>) -> Set<Int> {
        var out = Set<Int>()
        func filled(_ i: Int) -> Bool { cells[i] != nil || extra.contains(i) }
        for r in 0..<n where (0..<n).allSatisfy({ filled(r * n + $0) }) { out.formUnion((0..<n).map { r * n + $0 }) }
        for c in 0..<n where (0..<n).allSatisfy({ filled($0 * n + c) }) { out.formUnion((0..<n).map { $0 * n + c }) }
        return out
    }

    private func liftedCenter(_ p: BBPiece, finger: CGPoint, cell: CGFloat) -> CGPoint {
        CGPoint(x: finger.x, y: finger.y - CGFloat(p.rows) * cell / 2 - cell * 1.1)
    }

    private func snap(_ p: BBPiece, finger: CGPoint, lay: Layout) -> BBCell? {
        let center = liftedCenter(p, finger: finger, cell: lay.cell)
        let x0 = center.x - CGFloat(p.cols) * lay.cell / 2 - lay.board.minX
        let y0 = center.y - CGFloat(p.rows) * lay.cell / 2 - lay.board.minY
        let c = Int((x0 / lay.cell).rounded()), r = Int((y0 / lay.cell).rounded())
        return fits(p, r: r, c: c) ? BBCell(r: r, c: c) : nil
    }

    private func dragGesture(_ lay: Layout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard phase == .play, returning == nil else { return }
                if held == nil {
                    guard let slot = lay.slots.firstIndex(where: { $0.contains(v.startLocation) }),
                          tray[slot] != nil else { return }
                    held = Held(slot: slot, finger: v.location)
                    Haptics.tap()
                } else {
                    held?.finger = v.location
                }
            }
            .onEnded { _ in drop(lay) }
    }

    private func drop(_ lay: Layout) {
        guard let h = held, let p = tray[h.slot] else { held = nil; return }
        if let spot = snap(p, finger: h.finger, lay: lay) {
            held = nil
            place(p, slot: h.slot, at: spot)
        } else {
            returning = (p, h.slot, liftedCenter(p, finger: h.finger, cell: lay.cell), Date())
            held = nil
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.24))
                returning = nil
            }
        }
    }

    private func place(_ p: BBPiece, slot: Int, at spot: BBCell) {
        let now = Date()
        for c in p.cells {
            let i = (spot.r + c.r) * n + spot.c + c.c
            cells[i] = p.color
            placedAt[i] = now
        }
        tray[slot] = nil
        SoundManager.shared.tap(); Haptics.tap()

        let full = completedLines(adding: [])
        let rowsDone = (0..<n).filter { r in (0..<n).allSatisfy { cells[r * n + $0] != nil } }.count
        let colsDone = (0..<n).filter { c in (0..<n).allSatisfy { cells[$0 * n + c] != nil } }.count
        let cleared = rowsDone + colsDone
        if cleared > 0 {
            for i in full {
                if let col = cells[i] { clears.append(ClearFX(cell: i, color: col, t0: now)) }
                cells[i] = nil
                placedAt[i] = nil
            }
            lines += cleared
            combo += 1
            let words = [L("Good!", "Tốt!"), L("Great!", "Tuyệt!"), L("Excellent!", "Xuất sắc!"),
                         L("Unbelievable!", "Không thể tin!")]
            if cleared >= 2 || combo >= 2 {
                praise = Praise(text: words[min(max(cleared, combo) - 1, words.count - 1)], combo: combo, t0: now)
            }
            Haptics.success()
        } else {
            combo = 0
        }

        if lines >= target {
            phase = .won
            return
        }
        if tray.allSatisfy({ $0 == nil }) { deal() }
        if !tray.compactMap({ $0 }).contains(where: canFitAnywhere) {
            phase = .stuck
            stuckAt = Date()
        }
    }

    // MARK: Dealing

    private func randomShape() -> [BBCell] {
        let (e, m, _) = mix
        let roll = Double.random(in: 0..<1)
        let pool = roll < e ? BBShapes.easy : (roll < e + m ? BBShapes.medium : BBShapes.hard)
        return pool.randomElement()!
    }

    private func makePiece(_ shape: [BBCell]) -> BBPiece {
        nextID += 1
        return BBPiece(id: nextID, cells: shape, color: Int.random(in: 0..<Self.colors.count))
    }

    /// Deals three pieces, re-rolling until at least one of them fits (level 1: all three).
    private func deal() {
        var best: [BBPiece] = []
        for attempt in 0..<40 {
            let hand = (0..<3).map { _ in makePiece(randomShape()) }
            let fitting = hand.filter(canFitAnywhere).count
            best = hand
            if fitting == 3 || (level > 1 && fitting >= 1) || attempt == 39 { break }
        }
        tray = best
    }

    /// Scatter junk in clumps without leaving any row or column complete.
    private func prefillBoard(_ count: Int) {
        cells = Array(repeating: nil, count: n * n)
        var placed = 0, guardCount = 0
        while placed < count && guardCount < 2000 {
            guardCount += 1
            var i = Int.random(in: 0..<(n * n))
            if placed > 0 && Bool.random() {
                // grow an existing clump
                let filled = cells.indices.filter { cells[$0] != nil }
                let base = filled.randomElement()!
                let opts = [base - 1, base + 1, base - n, base + n].filter {
                    $0 >= 0 && $0 < n * n && ($0 / n == base / n || $0 % n == base % n)
                }
                i = opts.randomElement() ?? i
            }
            guard cells[i] == nil else { continue }
            cells[i] = Int.random(in: 0..<Self.colors.count)
            if !completedLines(adding: []).isEmpty { cells[i] = nil; continue }
            placed += 1
        }
    }

    // MARK: Flow

    private func run() async {
        prefillBoard(prefill)
        lines = 0; combo = 0
        deal()
        phase = .play
        timeLeft = timeLimit
        let start = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(0.05))
            pruneFX()
            switch phase {
            case .play:
                timeLeft = max(0, timeLimit - Date().timeIntervalSince(start))
                if timeLeft <= 0 { fail(); return }
            case .won:
                try? await Task.sleep(for: .seconds(0.55))
                guard !Task.isCancelled else { return }
                phase = .done
                onWin()
                return
            case .stuck:
                try? await Task.sleep(for: .seconds(0.9))
                guard !Task.isCancelled else { return }
                fail()
                return
            case .done:
                return
            }
        }
    }

    private func pruneFX() {
        let now = Date()
        clears.removeAll { now.timeIntervalSince($0.t0) > 0.6 }
        placedAt = placedAt.filter { now.timeIntervalSince($0.value) < 0.2 }
        if let p = praise, now.timeIntervalSince(p.t0) > 1.05 { praise = nil }
    }

    private func fail() {
        guard phase == .play || phase == .stuck else { return }
        phase = .done
        SoundManager.shared.error()
        onFail()
    }

    // MARK: - Demo (live manual clip)
    // A fixed level-1 board one step from three blasts: the finger drags a 1×3 into row 7 (1 line),
    // a 2×2 into rows 5–6 ("Great!", 2 lines), then an L into rows 1–2 (2 more) — 5 ≥ 4, the real
    // win. Placements go through the real snap/place code with a finger computed from the layout.
    private static let demoFill: [(Int, [Int])] = [
        (0, [0, 1, 6]), (1, [0, 1, 2, 3, 5, 6, 7]), (2, [0, 1, 2, 5, 6, 7]), (3, [7]),
        (4, [0, 1, 7]), (5, [0, 1, 2, 3, 4, 5]), (6, [0, 1, 2, 3, 4, 5]), (7, [0, 1, 5, 6, 7]),
    ]
    private static let demoMoves: [(slot: Int, r: Int, c: Int)] = [(0, 7, 2), (1, 5, 6), (2, 1, 3)]

    private func demoSetup() {
        cells = Array(repeating: nil, count: n * n)
        var k = 0
        for (r, cols) in Self.demoFill {
            for c in cols { cells[r * n + c] = [5, 0, 3, 1, 6, 4, 2][k % 7]; k += 1 }
        }
        tray = [BBPiece(id: 1, cells: BBShapes.grid(["###"]), color: 4),
                BBPiece(id: 2, cells: BBShapes.grid(["##", "##"]), color: 2),
                BBPiece(id: 3, cells: BBShapes.grid([".#", "##"]), color: 6)]
        lines = 0; combo = 0; praise = nil; clears = []; placedAt = [:]
        held = nil; demoFinger = nil; demoPressed = false
        phase = .play
    }

    private func runDemo() async {
        while !Task.isCancelled {
            demoSetup()
            try? await Task.sleep(for: .seconds(0.6))
            for move in Self.demoMoves {
                guard !Task.isCancelled, size.width > 0, let p = tray[move.slot] else { return }
                let lay = Self.layout(size, demo: true)
                let start = CGPoint(x: lay.slots[move.slot].midX, y: lay.slots[move.slot].midY)
                // Finger point whose lifted piece lands exactly on (r, c).
                let targetCenter = CGPoint(x: lay.board.minX + (CGFloat(move.c) + CGFloat(p.cols) / 2) * lay.cell,
                                           y: lay.board.minY + (CGFloat(move.r) + CGFloat(p.rows) / 2) * lay.cell)
                let end = CGPoint(x: targetCenter.x, y: targetCenter.y + CGFloat(p.rows) * lay.cell / 2 + lay.cell * 1.1)
                demoFinger = start
                try? await Task.sleep(for: .seconds(0.25))
                demoPressed = true
                held = Held(slot: move.slot, finger: start)
                let steps = 28
                for s in 1...steps {
                    guard !Task.isCancelled else { return }
                    let t = Double(s) / Double(steps)
                    let e = CGFloat(t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2)
                    let f = CGPoint(x: start.x + (end.x - start.x) * e, y: start.y + (end.y - start.y) * e)
                    held?.finger = f
                    demoFinger = f
                    try? await Task.sleep(for: .seconds(1.0 / 50))
                }
                try? await Task.sleep(for: .seconds(0.25))
                drop(lay)
                demoPressed = false
                try? await Task.sleep(for: .seconds(0.75))
            }
            demoFinger = nil
            try? await Task.sleep(for: .seconds(1.3))
        }
    }
}
