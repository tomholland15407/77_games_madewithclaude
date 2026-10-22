//
//  TowerOfHanoiGame.swift
//  A Banana Game
//
//  Brain — Tower of Hanoi. Move the whole stack of disks onto the goal peg, one disk at a time,
//  never setting a larger disk on a smaller one. Tap a peg to lift its top disk, tap another peg to
//  drop it. The catch is a move budget: it starts generous but shrinks each level until level 7
//  allows only the mathematically perfect number of moves (2ⁿ−1). Overspend your moves or run out of
//  time and you're back to level 1.
//
//  The start and goal pegs are randomized each play, and the disk count climbs from 3 to 7, so the
//  optimal solution explodes from 7 moves to 127 — a flawless-only finale.
//
//  Drawn as the wooden toy: a plywood base and dowel pegs with painted rainbow rings in a 3/4
//  view (the rims of the rings below show around each one), a brass goal peg with a pennant, a
//  wooden move plaque and an hourglass clock.
//

import SwiftUI

enum TowerOfHanoiGame {
    static let definition = GameDefinition(
        id: "tower-of-hanoi",
        title: "Tower of Hanoi",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Tap a peg to pick up its top disk, then tap another peg to place it.",
                "You can never put a larger disk on a smaller one.",
                "Move the entire stack onto the highlighted goal peg.",
                "Overspend your moves or the clock and you drop to level 1.",
            ],
            bulletsVI: [
                "Chạm một cọc để nhấc đĩa trên cùng, rồi chạm cọc khác để đặt xuống.",
                "Không bao giờ được đặt đĩa lớn lên đĩa nhỏ.",
                "Chuyển toàn bộ chồng đĩa sang cọc mục tiêu được tô sáng.",
                "Dùng quá số nước đi hoặc hết giờ sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(TowerOfHanoiView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct TowerOfHanoiView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    private var diskCount: Int { [3, 3, 4, 4, 5, 6, 7][min(level, 7) - 1] }
    private var slack: Int { [6, 3, 5, 2, 3, 2, 0][min(level, 7) - 1] }
    private var timeLimit: Double { [40, 45, 60, 70, 100, 140, 190][min(level, 7) - 1] }

    private var optimal: Int { (1 << diskCount) - 1 }
    private var budget: Int { optimal + slack }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var pegs: [[Int]] = [[], [], []]   // each bottom→top, values = disk sizes
    @State private var goalPeg = 2
    @State private var selected: Int? = nil
    @State private var movesUsed = 0
    @State private var timeLeft = 0.0
    @State private var loopTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: isDemo ? 4 : 10) {
            HStack(spacing: 12) {
                Hourglass(frac: timeLimit > 0 ? timeLeft / timeLimit : 0)
                    .frame(width: isDemo ? 22 : 28, height: isDemo ? 34 : 44)
                Text(L("MOVES  \(movesUsed) / \(budget)", "NƯỚC  \(movesUsed) / \(budget)"))
                    .font(.system(size: isDemo ? 17 : 20, weight: .black, design: .rounded))
                    .foregroundStyle(budget - movesUsed <= 2 ? Color(red: 0.75, green: 0.1, blue: 0.08)
                                                            : Color(red: 0.32, green: 0.17, blue: 0.07))
                    .contentTransition(.numericText())
                    .padding(.horizontal, 16).padding(.vertical, isDemo ? 5 : 8)
                    .background(WoodPlaque())
            }
            .padding(.top, isDemo ? 8 : 12)
            boardView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OakTable().equatable())
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : start() }
        .onDisappear { loopTask?.cancel() }
    }

    // MARK: - Demo (live manual clip)

    /// The 7-move optimal 3-disk solution from peg 0 → peg 2, as (from, to) pairs.
    /// Each move is two real `tapPeg` calls (select, then place) so the lift/drop
    /// animates exactly like real play.
    private func runDemo() async {
        let moves = [(0, 2), (0, 1), (2, 1), (0, 2), (1, 0), (1, 2), (0, 2)]
        while !Task.isCancelled {
            demoSetup()
            try? await Task.sleep(for: .seconds(0.6))
            for (from, to) in moves {
                guard !Task.isCancelled else { return }
                tapPeg(from)
                try? await Task.sleep(for: .seconds(0.35))
                guard !Task.isCancelled else { return }
                tapPeg(to)
                try? await Task.sleep(for: .seconds(0.5))
            }
            // Last move filled the goal peg → win() ran (onWin is a no-op). Hold, loop.
            try? await Task.sleep(for: .seconds(1.1))
        }
    }

    private func demoSetup() {
        pegs = [[3, 2, 1], [], []]   // 3 disks on peg 0, biggest at the bottom
        goalPeg = 2
        selected = nil
        movesUsed = 0
        phase = .play
        timeLeft = timeLimit
    }

    private var boardView: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let colW = w / 3
            let n = max(pegs.joined().max() ?? 0, 1)   // the rings actually on the board, not the level's count
            let diskH = min(30, (h * 0.7) / CGFloat(n))
            let baseY = h * 0.86
            let maxDiskW = colW * 0.86
            let minDiskW = maxDiskW * 0.32
            let pegW = max(6, colW * 0.07)
            ZStack {
                HanoiStand(w: w, h: h, baseY: baseY, colW: colW, maxDiskW: maxDiskW, pegW: pegW, goal: goalPeg)
                    .equatable()

                // Disks.
                ForEach(0..<3, id: \.self) { peg in
                    disksForPeg(peg: peg, colW: colW, diskH: diskH, baseY: baseY,
                                maxDiskW: maxDiskW, minDiskW: minDiskW, n: n, pegW: pegW)
                }

                // Tap columns.
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { i in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onTapGesture { tapPeg(i) }
                    }
                }
            }
            .frame(width: w, height: h)
        }
    }

    private func disksForPeg(peg: Int, colW: CGFloat, diskH: CGFloat, baseY: CGFloat,
                             maxDiskW: CGFloat, minDiskW: CGFloat, n: Int, pegW: CGFloat) -> some View {
        let cx = colW * (CGFloat(peg) + 0.5)
        let stack = pegs[peg]
        let liftTop = selected == peg
        return ForEach(Array(stack.enumerated()), id: \.offset) { idx, size in
            let isTop = idx == stack.count - 1
            let lifted = liftTop && isTop
            let dw = minDiskW + (maxDiskW - minDiskW) * CGFloat(size - 1) / CGFloat(max(n - 1, 1))
            let restY = baseY - (CGFloat(idx) + 0.5) * diskH - 2
            let y = lifted ? baseY - (CGFloat(n) + 0.8) * diskH : restY
            HanoiDisk(color: HanoiArt.ringColor(size, n: n), width: dw, thick: diskH, pegW: pegW,
                      brass: peg == goalPeg, lifted: lifted)
                .equatable()
                .frame(width: dw + 16, height: diskH + dw * HanoiArt.tilt + 16)
                .position(x: cx, y: y)
                .animation(.easeOut(duration: 0.12), value: selected)
        }
    }

    // MARK: - Flow
    private func start() {
        let n = diskCount
        let startPeg = Int.random(in: 0..<3)
        var goal = Int.random(in: 0..<3)
        while goal == startPeg { goal = Int.random(in: 0..<3) }
        var newPegs: [[Int]] = [[], [], []]
        newPegs[startPeg] = Array((1...n).reversed())   // bottom = n (biggest) … top = 1
        pegs = newPegs
        goalPeg = goal
        selected = nil
        movesUsed = 0
        phase = .play
        timeLeft = timeLimit
        loopTask?.cancel()
        loopTask = Task {
            let s = Date()
            while !Task.isCancelled && phase == .play {
                try? await Task.sleep(for: .seconds(0.05))
                timeLeft = max(0, timeLimit - Date().timeIntervalSince(s))
                if timeLeft <= 0 { fail(); break }
            }
        }
    }

    private func tapPeg(_ i: Int) {
        guard phase == .play else { return }
        if let s = selected {
            if s == i { selected = nil; return }
            guard let moving = pegs[s].last else { selected = nil; return }
            if let topDest = pegs[i].last, topDest < moving {
                SoundManager.shared.error(); Haptics.warning(); selected = nil; return
            }
            pegs[s].removeLast(); pegs[i].append(moving)
            selected = nil
            movesUsed += 1
            SoundManager.shared.tap(); Haptics.tap()
            if pegs[goalPeg].count == diskCount { win(); return }
            if movesUsed >= budget { fail() }
        } else {
            guard !pegs[i].isEmpty else { return }
            selected = i
            SoundManager.shared.tap()
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

// MARK: - The wooden toy

private enum HanoiArt {
    /// Ellipse height / width for the 3/4 view.
    static let tilt: CGFloat = 0.26

    /// Rainbow rings: the biggest red at the bottom, climbing to violet at the top.
    static func ringColor(_ size: Int, n: Int) -> Color {
        let rainbow: [Color] = [Color(red: 0.86, green: 0.16, blue: 0.16), Color(red: 0.96, green: 0.5, blue: 0.1),
                                Color(red: 0.98, green: 0.82, blue: 0.14), Color(red: 0.2, green: 0.68, blue: 0.3),
                                Color(red: 0.16, green: 0.5, blue: 0.86), Color(red: 0.3, green: 0.26, blue: 0.7),
                                Color(red: 0.6, green: 0.3, blue: 0.72)]
        let t = Double(n - size) / Double(max(n - 1, 1))
        return rainbow[max(0, min(6, Int((t * 6).rounded())))]
    }

    static func hash(_ n: Double) -> CGFloat {
        let v: Double = sin(n * 12.9898) * 43758.5453
        return CGFloat(v - floor(v))
    }

    /// Gentle wavy grain across a rect (clip first).
    static func grain(_ ctx: GraphicsContext, in r: CGRect, seed: Int, spacing: CGFloat, color: Color) {
        var y = r.minY
        var k = 0
        while y < r.maxY {
            let s = Double(seed * 17 + k)
            var p = Path()
            let amp: CGFloat = spacing * (0.2 + hash(s) * 0.4)
            let ph: CGFloat = hash(s + 2) * 6.28
            for j in 0...16 {
                let x = r.minX + r.width * CGFloat(j) / 16
                let pt = CGPoint(x: x, y: y + amp * sin(x / max(1, r.width) * 7 + ph))
                if j == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            ctx.stroke(p, with: .color(color.opacity(0.25 + Double(hash(s + 5)) * 0.35)), lineWidth: 0.8)
            y += spacing * (0.7 + hash(s + 7) * 0.6)
            k += 1
        }
    }

    /// A dowel: shaded cylinder with a rounded top.
    static func dowel(_ ctx: GraphicsContext, x: CGFloat, top: CGFloat, bottom: CGFloat, w: CGFloat, brass: Bool) {
        let light = brass ? Color(red: 1, green: 0.88, blue: 0.5) : Color(red: 0.96, green: 0.86, blue: 0.66)
        let dark = brass ? Color(red: 0.62, green: 0.42, blue: 0.1) : Color(red: 0.72, green: 0.56, blue: 0.36)
        let body = Path(roundedRect: CGRect(x: x - w / 2, y: top, width: w, height: bottom - top), cornerRadius: w / 2)
        ctx.fill(body, with: .linearGradient(Gradient(colors: [dark, light, light, dark]),
                                             startPoint: CGPoint(x: x - w / 2, y: 0), endPoint: CGPoint(x: x + w / 2, y: 0)))
        ctx.stroke(body, with: .color(dark.shade(0.3).opacity(0.7)), lineWidth: 0.8)
    }
}

/// Plywood base and the three dowels (the goal peg in brass with a pennant) — static.
private struct HanoiStand: View, Equatable {
    let w: CGFloat, h: CGFloat, baseY: CGFloat, colW: CGFloat, maxDiskW: CGFloat, pegW: CGFloat, goal: Int

    var body: some View {
        Canvas { ctx, _ in
            let plane = baseY - 2                                   // where the bottom rings sit
            let depth = maxDiskW * HanoiArt.tilt * 1.6
            let top = CGRect(x: w * 0.03, y: plane - depth / 2, width: w * 0.94, height: depth)
            let front = CGRect(x: top.minX, y: top.maxY, width: top.width, height: max(10, h * 0.035))
            // Shadow on the table.
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 8))
                l.fill(Path(roundedRect: CGRect(x: top.minX + 6, y: top.minY + 10, width: top.width, height: top.height + front.height),
                            cornerRadius: 6), with: .color(.black.opacity(0.45)))
            }
            // Front edge: plywood layers.
            ctx.fill(Path(roundedRect: front, cornerRadius: 3), with: .color(Color(red: 0.72, green: 0.52, blue: 0.3)))
            var plies = Path()
            for k in 1...3 {
                let y = front.minY + front.height * CGFloat(k) / 4
                plies.move(to: CGPoint(x: front.minX + 2, y: y)); plies.addLine(to: CGPoint(x: front.maxX - 2, y: y))
            }
            ctx.stroke(plies, with: .color(Color(red: 0.45, green: 0.28, blue: 0.12).opacity(0.7)), lineWidth: 1)
            // Top face with grain.
            let topPath = Path(roundedRect: top, cornerRadius: 4)
            ctx.fill(topPath, with: .linearGradient(Gradient(colors: [Color(red: 0.93, green: 0.8, blue: 0.6), Color(red: 0.85, green: 0.69, blue: 0.47)]),
                                                    startPoint: CGPoint(x: 0, y: top.minY), endPoint: CGPoint(x: 0, y: top.maxY)))
            var g = ctx
            g.clip(to: topPath)
            HanoiArt.grain(g, in: top, seed: 3, spacing: 5, color: Color(red: 0.6, green: 0.42, blue: 0.22))
            ctx.stroke(topPath, with: .color(Color(red: 0.5, green: 0.33, blue: 0.16).opacity(0.6)), lineWidth: 1)
            // The goal peg glows where it meets the base.
            let gx = colW * (CGFloat(goal) + 0.5)
            ctx.fill(Path(ellipseIn: CGRect(x: gx - maxDiskW * 0.55, y: plane - maxDiskW * 0.55 * HanoiArt.tilt,
                                            width: maxDiskW * 1.1, height: maxDiskW * 1.1 * HanoiArt.tilt)),
                     with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.85, blue: 0.3).opacity(0.55), .clear]),
                                           center: CGPoint(x: gx, y: plane), startRadius: 0, endRadius: maxDiskW * 0.55))
            // Dowels.
            let pegTop = baseY - h * 0.62
            for i in 0..<3 {
                let cx = colW * (CGFloat(i) + 0.5)
                ctx.fill(Path(ellipseIn: CGRect(x: cx - pegW, y: plane - pegW * 0.4, width: pegW * 2, height: pegW * 0.8)),
                         with: .color(.black.opacity(0.25)))
                HanoiArt.dowel(ctx, x: cx, top: pegTop, bottom: plane, w: pegW, brass: i == goal)
            }
            // A pennant on the goal peg.
            var pole = Path()
            pole.move(to: CGPoint(x: gx, y: pegTop + 2)); pole.addLine(to: CGPoint(x: gx, y: pegTop - pegW * 2.6))
            ctx.stroke(pole, with: .color(Color(red: 0.55, green: 0.38, blue: 0.1)), lineWidth: 1.5)
            var flag = Path()
            flag.move(to: CGPoint(x: gx, y: pegTop - pegW * 2.6))
            flag.addLine(to: CGPoint(x: gx + pegW * 2.8, y: pegTop - pegW * 1.95))
            flag.addLine(to: CGPoint(x: gx, y: pegTop - pegW * 1.3))
            flag.closeSubpath()
            ctx.fill(flag, with: .color(Color(red: 0.9, green: 0.2, blue: 0.16)))
            ctx.fill(Path(ellipseIn: CGRect(x: gx - pegW * 0.45, y: pegTop - pegW * 3.0, width: pegW * 0.9, height: pegW * 0.9)),
                     with: .color(Color(red: 1, green: 0.85, blue: 0.4)))
        }
        .allowsHitTesting(false)
    }
}

/// One painted wooden ring in the 3/4 view: its top face (with the hole, and the peg rising out of
/// it) over the rounded side band. Drawn once; only its position moves.
private struct HanoiDisk: View, Equatable {
    let color: Color
    let width: CGFloat
    let thick: CGFloat
    let pegW: CGFloat
    let brass: Bool
    let lifted: Bool

    var body: some View {
        Canvas { ctx, s in
            let cx = s.width / 2, cy = s.height / 2
            let rx = width / 2, ry = width * HanoiArt.tilt / 2
            let topY = cy - thick / 2, botY = cy + thick / 2
            // Side band: the front half of the bottom ellipse joined to the top ellipse's sides.
            var band = Path()
            band.move(to: CGPoint(x: cx - rx, y: topY))
            band.addLine(to: CGPoint(x: cx - rx, y: botY))
            band.addArc(center: CGPoint(x: cx, y: botY), radius: 1, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true,
                        transform: CGAffineTransform(translationX: cx, y: botY).scaledBy(x: rx, y: ry).translatedBy(x: -cx, y: -botY))
            band.addLine(to: CGPoint(x: cx + rx, y: topY))
            band.closeSubpath()
            ctx.fill(band, with: .linearGradient(Gradient(colors: [color.shade(0.35), color.lit(0.1), color.shade(0.05), color.shade(0.4)]),
                                                 startPoint: CGPoint(x: cx - rx, y: 0), endPoint: CGPoint(x: cx + rx, y: 0)))
            ctx.stroke(band, with: .color(color.shade(0.55).opacity(0.7)), lineWidth: 0.8)
            // Top face with a soft sheen.
            let topFace = Path(ellipseIn: CGRect(x: cx - rx, y: topY - ry, width: rx * 2, height: ry * 2))
            ctx.fill(topFace, with: .radialGradient(Gradient(colors: [color.lit(0.32), color.lit(0.05)]),
                                                    center: CGPoint(x: cx - rx * 0.3, y: topY - ry * 0.4), startRadius: 0, endRadius: rx))
            ctx.stroke(topFace, with: .color(color.shade(0.4).opacity(0.6)), lineWidth: 0.8)
            // The hole, with the peg coming up out of it.
            let hr = pegW / 2 + 1.5
            ctx.fill(Path(ellipseIn: CGRect(x: cx - hr, y: topY - hr * HanoiArt.tilt * 1.6, width: hr * 2, height: hr * HanoiArt.tilt * 3.2)),
                     with: .color(color.shade(0.7)))
            HanoiArt.dowel(ctx, x: cx, top: 0, bottom: topY, w: pegW, brass: brass)
            if lifted {
                ctx.stroke(topFace, with: .color(.white.opacity(0.9)), lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Oak tabletop behind the toy (static).
private struct OakTable: View, Equatable {
    var body: some View {
        Canvas { ctx, s in
            let r = CGRect(origin: .zero, size: s)
            ctx.fill(Path(r), with: .linearGradient(Gradient(colors: [Color(red: 0.42, green: 0.27, blue: 0.15), Color(red: 0.3, green: 0.18, blue: 0.1)]),
                                                    startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height)))
            HanoiArt.grain(ctx, in: r, seed: 9, spacing: 9, color: Color(red: 0.18, green: 0.1, blue: 0.05))
            ctx.fill(Path(r), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.9, blue: 0.7).opacity(0.14), .clear]),
                                                    center: CGPoint(x: s.width / 2, y: s.height * 0.45), startRadius: 0, endRadius: max(s.width, s.height) * 0.7))
        }
        .allowsHitTesting(false)
    }
}

/// A small wooden plaque behind the move counter.
private struct WoodPlaque: View {
    var body: some View {
        Canvas { ctx, s in
            let r = CGRect(origin: .zero, size: s).insetBy(dx: 1, dy: 1)
            let p = Path(roundedRect: r, cornerRadius: 8)
            ctx.fill(p, with: .linearGradient(Gradient(colors: [Color(red: 0.96, green: 0.84, blue: 0.62), Color(red: 0.86, green: 0.68, blue: 0.44)]),
                                              startPoint: CGPoint(x: 0, y: r.minY), endPoint: CGPoint(x: 0, y: r.maxY)))
            var g = ctx
            g.clip(to: p)
            HanoiArt.grain(g, in: r, seed: 21, spacing: 4, color: Color(red: 0.6, green: 0.4, blue: 0.2))
            ctx.stroke(p, with: .color(Color(red: 0.45, green: 0.28, blue: 0.12)), lineWidth: 2)
            for x in [r.minX + 7, r.maxX - 7] {
                ctx.fill(Path(ellipseIn: CGRect(x: x - 2, y: r.midY - 2, width: 4, height: 4)), with: .color(Color(red: 0.4, green: 0.36, blue: 0.3)))
            }
        }
    }
}

/// The level clock: sand runs from the top bulb to the bottom one (it glows red near the end).
private struct Hourglass: View {
    let frac: Double

    var body: some View {
        Canvas { ctx, s in
            let w = s.width, h = s.height
            let f = CGFloat(max(0, min(1, frac)))
            let cap: CGFloat = h * 0.1
            let glassTop = cap, glassBot = h - cap, mid = h / 2
            let sand = frac < 0.3 ? Color(red: 0.95, green: 0.4, blue: 0.2) : Color(red: 0.95, green: 0.8, blue: 0.45)
            func bulb(top: Bool) -> Path {
                var p = Path()
                let y0 = top ? glassTop : glassBot
                p.move(to: CGPoint(x: w * 0.12, y: y0))
                p.addQuadCurve(to: CGPoint(x: w * 0.47, y: mid), control: CGPoint(x: w * 0.1, y: (y0 + mid) / 2 + (top ? 4 : -4)))
                p.addLine(to: CGPoint(x: w * 0.53, y: mid))
                p.addQuadCurve(to: CGPoint(x: w * 0.88, y: y0), control: CGPoint(x: w * 0.9, y: (y0 + mid) / 2 + (top ? 4 : -4)))
                p.closeSubpath()
                return p
            }
            let upper = bulb(top: true), lower = bulb(top: false)
            ctx.fill(upper, with: .color(.white.opacity(0.18)))
            ctx.fill(lower, with: .color(.white.opacity(0.18)))
            // Sand left on top (a band down by the neck), and the pile below.
            var topSand = ctx
            topSand.clip(to: upper)
            let level = mid - (mid - glassTop) * f * 0.92
            topSand.fill(Path(CGRect(x: 0, y: level, width: w, height: mid - level)), with: .color(sand))
            var botSand = ctx
            botSand.clip(to: lower)
            let pile = (glassBot - mid) * (1 - f) * 0.9
            var mound = Path()
            mound.move(to: CGPoint(x: 0, y: glassBot))
            mound.addLine(to: CGPoint(x: 0, y: glassBot - pile * 0.6))
            mound.addQuadCurve(to: CGPoint(x: w, y: glassBot - pile * 0.6), control: CGPoint(x: w / 2, y: glassBot - pile * 1.5))
            mound.addLine(to: CGPoint(x: w, y: glassBot))
            mound.closeSubpath()
            botSand.fill(mound, with: .color(sand))
            if f > 0 && f < 1 {
                var stream = Path()
                stream.move(to: CGPoint(x: w / 2, y: mid)); stream.addLine(to: CGPoint(x: w / 2, y: glassBot - pile * 0.9))
                ctx.stroke(stream, with: .color(sand), lineWidth: 1.2)
            }
            ctx.stroke(upper, with: .color(.white.opacity(0.7)), lineWidth: 1.2)
            ctx.stroke(lower, with: .color(.white.opacity(0.7)), lineWidth: 1.2)
            // Wooden caps and posts.
            for y in [0, h - cap] {
                ctx.fill(Path(roundedRect: CGRect(x: 0, y: y, width: w, height: cap), cornerRadius: 2), with: .color(Color(red: 0.55, green: 0.34, blue: 0.16)))
            }
            for x in [w * 0.04, w * 0.96 - 2] {
                ctx.fill(Path(CGRect(x: x, y: cap, width: 2, height: h - cap * 2)), with: .color(Color(red: 0.45, green: 0.28, blue: 0.12)))
            }
        }
    }
}

