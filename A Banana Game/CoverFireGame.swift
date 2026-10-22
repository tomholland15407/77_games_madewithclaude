//
//  CoverFireGame.swift
//  A Banana Game
//
//  Brain / stealth — Sokoban meets a sniper's nest. One or more snipers lock onto you the moment
//  they have a clear line of sight: a bright beam snaps to you and starts charging. Stay exposed
//  and the shot lands — back to level 1. Break the line of sight before it fires by ducking behind
//  a wall or by PUSHING a crate into the gap (walk into a crate to shove it one tile). Reach the
//  exit alive. A per-level clock keeps you honest.
//
//  7 levels: more snipers, faster charges, fewer crates, more open ground, and less time.
//

import SwiftUI

enum CoverFireGame {
    static let definition = GameDefinition(
        id: "cover-fire",
        title: "Compound Dash",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        locksFeed: false,
        manual: GameManual(
            bullets: [
                "Reach the exit without getting shot. Move with the d-pad.",
                "Snipers fire a charging beam the instant they see you.",
                "Break their line of sight before it completes — hide behind a wall or shove a crate into the gap.",
            ],
            bulletsVI: [
                "Đến lối ra mà không bị bắn. Di chuyển bằng d-pad.",
                "Lính bắn tỉa nạp một tia sáng ngay khi nhìn thấy bạn.",
                "Cắt tầm nhìn của chúng trước khi nạp xong — nấp sau tường hoặc đẩy một thùng vào khe hở.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(CoverFireView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct CoverFireView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    private let cols = 11
    private let rows = 15

    // MARK: Difficulty
    private var sniperCount: Int  { [1, 1, 1, 2, 2, 3, 3][min(level, 7) - 1] }
    private var chargeTime: Double { [2.4, 2.1, 1.8, 1.6, 1.4, 1.2, 1.0][min(level, 7) - 1] }
    private var crateCount: Int   { [8, 7, 6, 6, 5, 4, 3][min(level, 7) - 1] }
    private var wallBlocks: Int   { [3, 3, 2, 2, 2, 1, 1][min(level, 7) - 1] }
    private var timeLimit: Double { Double(40 - level * 2) }

    private let moveInterval: Double = 0.13

    private struct P: Hashable { let r: Int; let c: Int }
    private struct Sniper: Identifiable { let id = UUID(); let cell: P; var charge: Double = 0 }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var walls: [[Bool]] = []
    @State private var crates: Set<P> = []
    @State private var snipers: [Sniper] = []
    @State private var playerCell = P(r: 1, c: 1)
    @State private var exitCell = P(r: 1, c: 1)
    @State private var moveDir: (Int, Int) = (0, 0)
    @State private var stepCD: Double = 0
    @State private var timeLeft = 0.0
    @State private var built = false
    @State private var demoDir: (dc: Int, dr: Int)? = nil   // d-pad arrow flashed in the demo

    var body: some View {
        VStack(spacing: isDemo ? 6 : 10) {
            sniperGauges
            if !isDemo { timeBar.frame(height: 5).padding(.horizontal, 50) }
            board
            dpad
        }
        .padding(.top, isDemo ? 8 : 12)
        .padding(.bottom, isDemo ? 8 : 10)
        .padding(.horizontal, isDemo ? 6 : 10)
        .background(Color(red: 0.16, green: 0.17, blue: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { isDemo ? await runDemo() : await run() }
    }

    /// One scope gauge per sniper: it fills red while that sniper has you in its sights.
    private var sniperGauges: some View {
        HStack(spacing: isDemo ? 8 : 12) {
            ForEach(snipers) { s in
                let t = min(1, s.charge / chargeTime)
                Canvas { ctx, size in CoverArt.scopeGauge(ctx, size: size, charge: t, locked: hasLOS(from: s.cell, to: playerCell)) }
                    .frame(width: isDemo ? 20 : 26, height: isDemo ? 20 : 26)
            }
        }
    }
    // MARK: - Demo (live manual clip)

    /// A fixed room: walk the bottom lane to the exit. A sniper up top sees you only
    /// through a one-tile gap in a wall, so its beam flashes and thickens as you cross
    /// that column, then breaks as you step behind the wall. Never charges to a shot.
    private func runDemo() async {
        while !Task.isCancelled {
            demoSetup()
            await demoWait(0.7)
            for _ in 0..<6 {                 // walk right toward the exit
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.1)) { demoDir = (1, 0) }
                tryStep(dc: 1, dr: 0)
                await demoWait(0.3)
                withAnimation(.easeIn(duration: 0.1)) { demoDir = nil }
                await demoWait(0.2)
            }
            if playerCell == exitCell { win() }   // onWin is a no-op; marks it reached
            await demoWait(1.2)
        }
    }

    /// Sleeps while charging any sniper that currently sees the player — capped well
    /// below `chargeTime` so the beam thickens for show but never actually fires.
    private func demoWait(_ dur: Double) async {
        let steps = max(1, Int(dur / 0.016))
        for _ in 0..<steps {
            guard !Task.isCancelled else { return }
            for i in snipers.indices {
                if hasLOS(from: snipers[i].cell, to: playerCell) {
                    snipers[i].charge = min(chargeTime * 0.7, snipers[i].charge + 0.016)
                } else {
                    snipers[i].charge = max(0, snipers[i].charge - 0.016 * 3)
                }
            }
            try? await Task.sleep(for: .seconds(0.016))
        }
    }

    private func demoSetup() {
        var w = Array(repeating: Array(repeating: false, count: cols), count: rows)
        for r in 0..<rows { w[r][0] = true; w[r][cols - 1] = true }
        for c in 0..<cols { w[0][c] = true; w[rows - 1][c] = true }
        // A wall band across row 9 with a single gap at column 6 — the sniper's peephole.
        for c in 1...9 where c != 6 { w[9][c] = true }
        walls = w

        playerCell = P(r: 11, c: 2)
        exitCell = P(r: 11, c: 8)
        snipers = [Sniper(cell: P(r: 2, c: 6))]
        crates = [P(r: 5, c: 3), P(r: 6, c: 8)]   // dressing, off the lane and sightline
        moveDir = (0, 0); stepCD = 0
        timeLeft = timeLimit
        phase = .play
        built = true
    }

    private var board: some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width
            let h: CGFloat = geo.size.height
            // The squat demo card shows rows 1–12, where the sniper, the gap and the lane are.
            let firstRow = isDemo ? 1 : 0
            let shownRows = isDemo ? 12 : rows
            let cell: CGFloat = min(w / CGFloat(cols), h / CGFloat(shownRows))
            let ox: CGFloat = (w - cell * CGFloat(cols)) / 2
            let oy: CGFloat = (h - cell * CGFloat(shownRows)) / 2 - CGFloat(firstRow) * cell

            ZStack {
                CoverGround(cols: cols, rows: rows, cell: cell, origin: CGPoint(x: ox, y: oy)).equatable()
                Canvas { ctx, _ in drawCompound(ctx, cell: cell, ox: ox, oy: oy) }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: isDemo ? 8 : 12))
        }
    }

    /// Barriers and sandbags, the helipad, crates, the sniper nests and their laser sights, the player.
    private func drawCompound(_ ctx: GraphicsContext, cell: CGFloat, ox: CGFloat, oy: CGFloat) {
        guard walls.count == rows else { return }
        func rect(_ r: Int, _ c: Int) -> CGRect {
            CGRect(x: ox + CGFloat(c) * cell, y: oy + CGFloat(r) * cell, width: cell, height: cell)
        }
        func mid(_ p: P) -> CGPoint { CGPoint(x: ox + (CGFloat(p.c) + 0.5) * cell, y: oy + (CGFloat(p.r) + 0.5) * cell) }
        for r in 0..<rows {
            for c in 0..<cols where walls[r][c] {
                let border = r == 0 || c == 0 || r == rows - 1 || c == cols - 1
                if border { CoverArt.barrier(ctx, in: rect(r, c)) } else { CoverArt.sandbags(ctx, in: rect(r, c), row: r) }
            }
        }
        CoverArt.helipad(ctx, in: rect(exitCell.r, exitCell.c))
        for cr in crates { CoverArt.crate(ctx, in: rect(cr.r, cr.c)) }
        // Laser sights: a thin red beam that thickens and pulses as the sniper's shot charges.
        let now = Date().timeIntervalSinceReferenceDate
        for s in snipers where hasLOS(from: s.cell, to: playerCell) {
            let t = min(1, s.charge / chargeTime)
            let pulse = 0.75 + 0.25 * sin(now * (8 + 22 * t))
            var beam = Path()
            beam.move(to: mid(s.cell))
            beam.addLine(to: mid(playerCell))
            ctx.stroke(beam, with: .color(Color(red: 1, green: 0.1, blue: 0.08).opacity(0.25 * pulse)),
                       style: StrokeStyle(lineWidth: cell * (0.12 + 0.2 * t), lineCap: .round))
            ctx.stroke(beam, with: .color(Color(red: 1, green: 0.25 + 0.5 * (1 - t), blue: 0.2).opacity(pulse)),
                       style: StrokeStyle(lineWidth: max(1, cell * (0.03 + 0.07 * t)), lineCap: .round))
        }
        for s in snipers {
            let aim = hasLOS(from: s.cell, to: playerCell) ? mid(playerCell) : CGPoint(x: mid(s.cell).x, y: mid(s.cell).y + cell)
            CoverArt.sniperNest(ctx, at: mid(s.cell), aim: aim, cell: cell)
        }
        let seen = snipers.contains { hasLOS(from: $0.cell, to: playerCell) }
        CoverArt.soldier(ctx, at: mid(playerCell), cell: cell, targeted: seen)
    }
    private var dpad: some View {
        Group {
            if isDemo {
                HStack(spacing: 6) {
                    dpadButton(-1, 0, "chevron.left")
                    dpadButton(0, -1, "chevron.up")
                    dpadButton(0, 1, "chevron.down")
                    dpadButton(1, 0, "chevron.right")
                }
            } else {
                VStack(spacing: 6) {
                    dpadButton(0, -1, "chevron.up")
                    HStack(spacing: 6) {
                        dpadButton(-1, 0, "chevron.left")
                        dpadButton(1, 0, "chevron.right")
                    }
                    dpadButton(0, 1, "chevron.down")
                }
            }
        }
        .padding(.bottom, isDemo ? 0 : 6)
    }

    private func dpadButton(_ dc: Int, _ dr: Int, _ icon: String) -> some View {
        let pressed = demoDir?.dc == dc && demoDir?.dr == dr
        return Image(systemName: icon)
            .font(.system(size: isDemo ? 16 : 22, weight: .black))
            .foregroundStyle(pressed ? .black : Color(red: 0.92, green: 0.9, blue: 0.8))
            .frame(width: isDemo ? 52 : 74, height: isDemo ? 34 : 52)
            .background(pressed ? BananaTheme.banana : Color(red: 0.3, green: 0.34, blue: 0.2),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.black.opacity(0.35), lineWidth: 1.5))
            .scaleEffect(pressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.1), value: pressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard phase == .play else { return }
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

    private func run() async {
        if !built { setup(); built = true }
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

        // Grid-step movement with auto-repeat while held.
        stepCD -= dt
        if moveDir != (0, 0) && stepCD <= 0 {
            tryStep(dc: moveDir.0, dr: moveDir.1)
            stepCD = moveInterval
        }

        // Snipers charge while they see you.
        for i in snipers.indices {
            if hasLOS(from: snipers[i].cell, to: playerCell) {
                snipers[i].charge += dt
                if snipers[i].charge >= chargeTime { fail(); return }
            } else {
                snipers[i].charge = max(0, snipers[i].charge - dt * 3)
            }
        }

        if playerCell == exitCell { win(); return }

        timeLeft -= dt
        if timeLeft <= 0 { timeLeft = 0; fail() }
    }

    private func tryStep(dc: Int, dr: Int) {
        let target = P(r: playerCell.r + dr, c: playerCell.c + dc)
        if isWall(target.r, target.c) { return }
        if crates.contains(target) {
            let beyond = P(r: target.r + dr, c: target.c + dc)
            if isWall(beyond.r, beyond.c) || crates.contains(beyond) { return }
            crates.remove(target); crates.insert(beyond)
            playerCell = target
            SoundManager.shared.tap(); Haptics.tap()
            return
        }
        playerCell = target
        SoundManager.shared.tap()
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

    // MARK: - Line of sight (blocked by walls or crates)

    private func hasLOS(from a: P, to b: P) -> Bool {
        let dr = b.r - a.r, dc = b.c - a.c
        let steps = max(abs(dr), abs(dc))
        guard steps > 0 else { return true }
        for i in 1..<steps {
            let t = Double(i) / Double(steps)
            let r = Int((Double(a.r) + Double(dr) * t).rounded())
            let c = Int((Double(a.c) + Double(dc) * t).rounded())
            let cell = P(r: r, c: c)
            if isWall(r, c) || crates.contains(cell) { return false }
        }
        return true
    }

    private func isWall(_ r: Int, _ c: Int) -> Bool {
        guard r >= 0, r < rows, c >= 0, c < cols, walls.count == rows else { return true }
        return walls[r][c]
    }

    private func manhattan(_ a: P, _ b: P) -> Int { abs(a.r - b.r) + abs(a.c - b.c) }

    // MARK: - Setup

    private func setup() {
        var w = Array(repeating: Array(repeating: false, count: cols), count: rows)
        for r in 0..<rows { w[r][0] = true; w[r][cols - 1] = true }
        for c in 0..<cols { w[0][c] = true; w[rows - 1][c] = true }
        var placed = 0, tries = 0
        while placed < wallBlocks && tries < 120 {
            tries += 1
            let bw = Int.random(in: 1...2), bh = Int.random(in: 1...2)
            let c0 = Int.random(in: 2...(cols - 2 - bw))
            let r0 = Int.random(in: 3...(rows - 4 - bh))
            var ok = true
            for r in (r0 - 1)...(r0 + bh) where ok {
                for c in (c0 - 1)...(c0 + bw) where w[r][c] { ok = false }
            }
            guard ok else { continue }
            for r in r0..<(r0 + bh) { for c in c0..<(c0 + bw) { w[r][c] = true } }
            placed += 1
        }
        walls = w

        playerCell = P(r: 1, c: 1)
        exitCell = P(r: rows - 2, c: cols - 2)

        var open: [P] = []
        for r in 2..<(rows - 2) { for c in 1..<(cols - 1) where !w[r][c] { open.append(P(r: r, c: c)) } }

        // Snipers along the sides, spaced, never adjacent to the player start.
        var ss: [Sniper] = []
        for cand in open.shuffled()
        where manhattan(cand, playerCell) >= 4 && cand != exitCell && (cand.c <= 2 || cand.c >= cols - 3) {
            if ss.allSatisfy({ manhattan($0.cell, cand) >= 4 }) {
                ss.append(Sniper(cell: cand))
                if ss.count == sniperCount { break }
            }
        }
        while ss.count < sniperCount, let any = open.randomElement() {
            if !ss.contains(where: { $0.cell == any }) && manhattan(any, playerCell) >= 3 {
                ss.append(Sniper(cell: any))
            }
        }
        snipers = ss

        // Crates on open cells, off the sniper tiles / start / exit, spaced out.
        let sniperCells = Set(ss.map { $0.cell })
        var cs: Set<P> = []
        // First, guarantee cover right next to the spawn so a player who starts exposed can dash
        // behind something before the first shot lands. (Same total crate count — placement only.)
        let nearGuarantee = min(2, crateCount)
        for cand in open.shuffled()
        where manhattan(cand, playerCell) >= 1 && manhattan(cand, playerCell) <= 3
            && cand != exitCell && !sniperCells.contains(cand) {
            if cs.count >= nearGuarantee { break }
            cs.insert(cand)
        }
        // Then fill the rest anywhere, spaced out.
        for cand in open.shuffled()
        where cand != playerCell && cand != exitCell && !sniperCells.contains(cand) && !cs.contains(cand) {
            if cs.count >= crateCount { break }
            if cs.allSatisfy({ manhattan($0, cand) >= 2 }) { cs.insert(cand) }
        }
        crates = cs

        moveDir = (0, 0); stepCD = 0
        timeLeft = timeLimit
        phase = .play
    }

}

// MARK: - Compound art

/// A desert compound under sniper watch: concrete barriers, sandbag walls, olive ammo crates, sniper
/// nests with red laser sights, a helmeted banana and an extraction helipad.
private enum CoverArt {
    static func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
    static let bag = c(0.74, 0.66, 0.46)

    private static func disc(_ p: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }

    /// A concrete jersey barrier block (the compound perimeter).
    static func barrier(_ ctx: GraphicsContext, in r: CGRect) {
        let q = r.insetBy(dx: -0.3, dy: -0.3)
        ctx.fill(Path(q), with: .linearGradient(Gradient(colors: [c(0.66, 0.65, 0.62), c(0.5, 0.49, 0.46)]),
                                                startPoint: CGPoint(x: q.minX, y: q.minY), endPoint: CGPoint(x: q.maxX, y: q.maxY)))
        ctx.stroke(Path(r.insetBy(dx: r.width * 0.12, dy: r.width * 0.12)), with: .color(.white.opacity(0.14)), lineWidth: 1)
        ctx.fill(Path(ellipseIn: CGRect(x: r.minX + r.width * 0.3, y: r.minY + r.height * 0.4, width: r.width * 0.12, height: r.width * 0.08)),
                 with: .color(.black.opacity(0.15)))
    }

    /// Two staggered courses of sandbags filling a cell.
    static func sandbags(_ ctx: GraphicsContext, in r: CGRect, row: Int) {
        ctx.fill(Path(r.offsetBy(dx: r.width * 0.08, dy: r.width * 0.1)), with: .color(.black.opacity(0.18)))
        let h = r.height / 2, bw = r.width / 2
        var g = ctx
        g.clip(to: Path(r.insetBy(dx: -r.width * 0.06, dy: -r.width * 0.02)))
        for k in 0..<2 {
            let shift = (row * 2 + k) % 2 == 0 ? 0 : bw / 2
            for i in -1...2 {
                let b = CGRect(x: r.minX + CGFloat(i) * bw + shift, y: r.minY + CGFloat(k) * h, width: bw, height: h).insetBy(dx: 0.5, dy: 0.8)
                let bagPath = Path(roundedRect: b, cornerRadius: h * 0.45)
                g.fill(bagPath, with: .linearGradient(Gradient(colors: [bag.lit(0.18), bag, bag.shade(0.25)]),
                                                     startPoint: CGPoint(x: b.midX, y: b.minY), endPoint: CGPoint(x: b.midX, y: b.maxY)))
                g.stroke(bagPath, with: .color(bag.shade(0.5)), lineWidth: max(0.6, h * 0.06))
                var seam = Path()
                seam.move(to: CGPoint(x: b.midX, y: b.minY + h * 0.2))
                seam.addLine(to: CGPoint(x: b.midX, y: b.maxY - h * 0.2))
                g.stroke(seam, with: .color(bag.shade(0.4).opacity(0.6)), lineWidth: max(0.5, h * 0.04))
            }
        }
    }

    /// An olive ammo crate from above.
    static func crate(_ ctx: GraphicsContext, in r: CGRect) {
        let b = r.insetBy(dx: r.width * 0.08, dy: r.width * 0.08)
        let olive = c(0.36, 0.42, 0.22)
        ctx.fill(Path(roundedRect: b.offsetBy(dx: r.width * 0.06, dy: r.width * 0.08), cornerRadius: 3), with: .color(.black.opacity(0.28)))
        ctx.fill(Path(roundedRect: b, cornerRadius: 3), with: .linearGradient(Gradient(colors: [olive.lit(0.15), olive.shade(0.12)]),
                                                                             startPoint: CGPoint(x: b.minX, y: b.minY), endPoint: CGPoint(x: b.maxX, y: b.maxY)))
        var slats = Path()
        for k in 1...2 {
            let y = b.minY + b.height * CGFloat(k) / 3
            slats.move(to: CGPoint(x: b.minX, y: y)); slats.addLine(to: CGPoint(x: b.maxX, y: y))
        }
        ctx.stroke(slats, with: .color(olive.shade(0.45)), lineWidth: max(0.8, r.width * 0.03))
        ctx.stroke(Path(roundedRect: b, cornerRadius: 3), with: .color(olive.shade(0.6)), lineWidth: max(1, r.width * 0.05))
        ctx.fill(Path(CGRect(x: b.midX - b.width * 0.22, y: b.midY - b.height * 0.07, width: b.width * 0.44, height: b.height * 0.14)),
                 with: .color(c(0.9, 0.86, 0.6).opacity(0.85)))
        for (fx, fy) in [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)] as [(CGFloat, CGFloat)] {
            ctx.fill(Path(CGRect(x: b.minX + b.width * fx - b.width * 0.09, y: b.minY + b.height * fy - b.width * 0.09,
                                 width: b.width * 0.18, height: b.width * 0.18)), with: .color(c(0.55, 0.56, 0.52)))
        }
    }

    /// The extraction point: a helipad with a beacon.
    static func helipad(_ ctx: GraphicsContext, in r: CGRect) {
        let p = CGPoint(x: r.midX, y: r.midY), R = r.width * 0.62
        ctx.fill(disc(p, R * 1.25), with: .radialGradient(Gradient(colors: [c(0.4, 1, 0.5).opacity(0.4), .clear]), center: p, startRadius: 0, endRadius: R * 1.25))
        ctx.fill(disc(p, R), with: .color(c(0.24, 0.26, 0.24)))
        ctx.stroke(disc(p, R * 0.84), with: .color(c(0.98, 0.84, 0.2)), lineWidth: max(1, R * 0.1))
        ctx.draw(ctx.resolve(Text("H").font(.system(size: R * 1.05, weight: .black, design: .rounded)).foregroundStyle(.white)), at: p)
    }

    /// A sniper in a ring of sandbags, rifle trained on `aim`.
    static func sniperNest(_ ctx: GraphicsContext, at p: CGPoint, aim: CGPoint, cell s: CGFloat) {
        for k in 0..<8 {
            let a = Double(k) / 8 * 2 * .pi
            let q = CGPoint(x: p.x + CGFloat(cos(a)) * s * 0.42, y: p.y + CGFloat(sin(a)) * s * 0.42)
            ctx.fill(Path(ellipseIn: CGRect(x: q.x - s * 0.16, y: q.y - s * 0.11, width: s * 0.32, height: s * 0.22)), with: .color(bag.shade(0.1)))
            ctx.stroke(Path(ellipseIn: CGRect(x: q.x - s * 0.16, y: q.y - s * 0.11, width: s * 0.32, height: s * 0.22)), with: .color(bag.shade(0.5)), lineWidth: 0.8)
        }
        let a = atan2(Double(aim.y - p.y), Double(aim.x - p.x))
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        g.rotate(by: .radians(a))
        g.fill(Path(roundedRect: CGRect(x: 0, y: -s * 0.04, width: s * 0.62, height: s * 0.08), cornerRadius: s * 0.02), with: .color(c(0.12, 0.12, 0.12)))
        g.fill(Path(ellipseIn: CGRect(x: -s * 0.2, y: -s * 0.24, width: s * 0.34, height: s * 0.48)), with: .color(c(0.3, 0.34, 0.22)))
        g.fill(disc(CGPoint(x: -s * 0.02, y: 0), s * 0.17), with: .radialGradient(Gradient(colors: [c(0.45, 0.5, 0.32), c(0.22, 0.26, 0.15)]),
                                                                                  center: CGPoint(x: -s * 0.06, y: -s * 0.05), startRadius: 0, endRadius: s * 0.2))
        g.fill(disc(CGPoint(x: s * 0.2, y: 0), s * 0.04), with: .color(c(1, 0.2, 0.15)))
    }

    /// The banana in a green helmet; a red laser dot sits on it while a sniper has it in view.
    static func soldier(_ ctx: GraphicsContext, at p: CGPoint, cell s: CGFloat, targeted: Bool) {
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.36, y: p.y - s * 0.12, width: s * 0.8, height: s * 0.56)), with: .color(.black.opacity(0.22)))
        var body = Path()
        body.move(to: CGPoint(x: p.x - s * 0.16, y: p.y - s * 0.44))
        body.addQuadCurve(to: CGPoint(x: p.x - s * 0.12, y: p.y + s * 0.44), control: CGPoint(x: p.x + s * 0.62, y: p.y))
        body.addQuadCurve(to: CGPoint(x: p.x - s * 0.16, y: p.y - s * 0.44), control: CGPoint(x: p.x + s * 0.06, y: p.y))
        body.closeSubpath()
        ctx.stroke(body, with: .color(.black.opacity(0.55)), lineWidth: max(2, s * 0.1))
        ctx.fill(body, with: .linearGradient(Gradient(colors: [c(1, 0.95, 0.5), c(0.98, 0.78, 0.12)]),
                                             startPoint: CGPoint(x: p.x - s * 0.1, y: p.y), endPoint: CGPoint(x: p.x + s * 0.34, y: p.y)))
        ctx.stroke(body, with: .color(c(0.45, 0.3, 0.05)), lineWidth: max(1, s * 0.04))
        let helmet = Path(ellipseIn: CGRect(x: p.x - s * 0.2, y: p.y - s * 0.46, width: s * 0.42, height: s * 0.3))
        ctx.fill(helmet, with: .radialGradient(Gradient(colors: [c(0.5, 0.56, 0.32), c(0.25, 0.3, 0.15)]),
                                               center: CGPoint(x: p.x - s * 0.02, y: p.y - s * 0.38), startRadius: 0, endRadius: s * 0.24))
        ctx.stroke(helmet, with: .color(c(0.12, 0.15, 0.06)), lineWidth: max(1, s * 0.035))
        if targeted {
            ctx.fill(disc(CGPoint(x: p.x + s * 0.12, y: p.y + s * 0.08), s * 0.13), with: .color(c(1, 0.1, 0.1).opacity(0.3)))
            ctx.fill(disc(CGPoint(x: p.x + s * 0.12, y: p.y + s * 0.08), s * 0.05), with: .color(c(1, 0.15, 0.1)))
        }
    }

    /// A scope reticle that fills red with the sniper's charge.
    static func scopeGauge(_ ctx: GraphicsContext, size s: CGSize, charge t: Double, locked: Bool) {
        let p = CGPoint(x: s.width / 2, y: s.height / 2), R = min(s.width, s.height) / 2 - 1.5
        ctx.fill(disc(p, R), with: .color(.black.opacity(0.35)))
        if t > 0 {
            var arc = Path()
            arc.move(to: p)
            arc.addArc(center: p, radius: R, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * t), clockwise: false)
            arc.closeSubpath()
            ctx.fill(arc, with: .color(c(1, 0.18, 0.12).opacity(0.85)))
        }
        ctx.stroke(disc(p, R), with: .color(locked ? c(1, 0.3, 0.25) : .white.opacity(0.7)), lineWidth: 2)
        var cross = Path()
        cross.move(to: CGPoint(x: p.x - R, y: p.y)); cross.addLine(to: CGPoint(x: p.x + R, y: p.y))
        cross.move(to: CGPoint(x: p.x, y: p.y - R)); cross.addLine(to: CGPoint(x: p.x, y: p.y + R))
        ctx.stroke(cross, with: .color(.white.opacity(0.75)), lineWidth: 1)
    }
}

/// Sun-baked sand for the whole compound (static).
private struct CoverGround: View, Equatable {
    let cols: Int, rows: Int
    let cell: CGFloat
    let origin: CGPoint

    var body: some View {
        Canvas { ctx, s in
            ctx.fill(Path(CGRect(origin: .zero, size: s)), with: .color(CoverArt.c(0.16, 0.17, 0.12)))
            let field = CGRect(x: origin.x, y: origin.y, width: cell * CGFloat(cols), height: cell * CGFloat(rows))
            ctx.fill(Path(field), with: .linearGradient(Gradient(colors: [CoverArt.c(0.86, 0.76, 0.55), CoverArt.c(0.78, 0.67, 0.46)]),
                                                        startPoint: CGPoint(x: field.minX, y: field.minY), endPoint: CGPoint(x: field.maxX, y: field.maxY)))
            for k in 0..<Int(cols * rows / 2) {
                let fx = CGFloat((sin(Double(k) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)).magnitude
                let fy = CGFloat((sin(Double(k) * 78.233) * 24634.6345).truncatingRemainder(dividingBy: 1)).magnitude
                let r = cell * (k % 5 == 0 ? 0.5 : 0.07)
                let q = CGPoint(x: field.minX + fx * field.width, y: field.minY + fy * field.height)
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r * 0.6, width: r * 2, height: r * 1.2)),
                         with: .color(CoverArt.c(0.6, 0.5, 0.32).opacity(k % 5 == 0 ? 0.12 : 0.35)))
            }
        }
        .allowsHitTesting(false)
    }
}
