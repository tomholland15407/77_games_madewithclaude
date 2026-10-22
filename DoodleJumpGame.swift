//
//  DoodleJumpGame.swift
//  A Banana Game
//
//  Reflex — a Doodle Jump homage. A banana critter auto-bounces ever upward; hold the
//  LEFT or RIGHT half of the screen to steer it onto the platforms (edges wrap). Climb
//  to the level's target height to win; miss the platforms and fall off the bottom and
//  you fail back to level 1. 7 levels: platforms get sparser, smaller, and start moving
//  or crumbling, and the climb gets much longer — through grass, clouds, and space.
//
//  Drawn as the classic Doodle Jump: cream graph paper that scrolls with the climb (blue dusk paper
//  at 4–5, the navy space theme at 6–7), sketchy pill platforms — green, blue when they move, brown
//  and cracked when they crumble (they snap in two and fall once used) — coiled springs, and a
//  banana Doodler (snout, dot eye, striped shorts, four legs) that faces where it's steered and
//  wraps across the edges. A torn-paper strip carries the height and a pencil clock, and a red
//  scribble with a flag marks the target height, like the game's score lines.
//

import SwiftUI

enum DoodleJumpGame {
    static let definition = GameDefinition(
        id: "doodle-jump",
        title: "Sketch Hop",
        emoji: "🍌",
        genre: .reflex,
        levelCount: 7,
        // Hold-to-steer drags on the screen halves would fight the vertical pager,
        // so lock the feed while playing — this also gives the bottom skip button,
        // the only way to leave since the drag halves swallow vertical swipes.
        locksFeed: true,
        manual: GameManual(
            bullets: [
                "The critter auto-bounces upward.",
                "Hold the left or right half of the screen to steer onto platforms (edges wrap around).",
                "Climb to the level's target height to win.",
                "Miss the platforms and fall off the bottom and you're back to level 1.",
            ],
            bulletsVI: [
                "Con vật tự bật lên liên tục.",
                "Giữ nửa trái hoặc phải màn hình để lái lên các bệ (mép màn hình nối vòng).",
                "Leo tới độ cao mục tiêu của cấp để thắng.",
                "Hụt bệ và rơi khỏi đáy sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(DoodleJumpView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct DoodleJumpView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    // MARK: Difficulty
    private var targetHeight: CGFloat { [5, 7, 9, 12, 15, 19, 24][min(level, 7) - 1] }
    private var gapLo: CGFloat { [0.18, 0.20, 0.22, 0.24, 0.26, 0.28, 0.30][min(level, 7) - 1] }
    private var platHalf: CGFloat { [0.14, 0.13, 0.12, 0.11, 0.10, 0.09, 0.08][min(level, 7) - 1] }
    private var movingChance: Double { [0.0, 0.0, 0.15, 0.25, 0.35, 0.45, 0.55][min(level, 7) - 1] }
    private var crumbleChance: Double { [0.0, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35][min(level, 7) - 1] }
    private var springChance: Double { [0.12, 0.10, 0.10, 0.08, 0.08, 0.06, 0.05][min(level, 7) - 1] }
    /// Generous safety-net clock so you can't bounce in place forever without climbing.
    private var timeLimit: Double { max(60, Double(targetHeight) * 10) }

    private let g: CGFloat = 1.5
    private let jumpV: CGFloat = 1.1
    private let springV: CGFloat = 1.95
    private let moveSpeed: CGFloat = 0.95
    private let charHalf: CGFloat = 0.05

    // MARK: State
    private enum Kind { case normal, moving, crumble, spring }
    private struct Platform: Identifiable {
        let id = UUID()
        var x: CGFloat
        let baseX: CGFloat
        let y: CGFloat
        let kind: Kind
        let amp: CGFloat
        let spd: CGFloat
        let phase: CGFloat
        var alive = true
    }

    @State private var platforms: [Platform] = []
    @State private var charX: CGFloat = 0.5
    @State private var charY: CGFloat = 0.2
    @State private var vy: CGFloat = 0
    @State private var moveDir: CGFloat = 0
    @State private var cameraY: CGFloat = -0.45
    @State private var charMaxY: CGFloat = 0
    @State private var highestY: CGFloat = 0
    @State private var t = 0.0
    @State private var timeLeft = 0.0
    @State private var done = false
    @State private var loopTask: Task<Void, Never>?

    /// World-Y (up-positive) → screen-Y (top-origin), given the current camera.
    private func screenY(_ worldY: CGFloat, cameraY: CGFloat, h: CGFloat) -> CGFloat {
        (1 - (worldY - cameraY)) * h
    }

    @State private var facingLeft = false              // presentation: the Doodler faces where it's steered
    @State private var brokeAt: [UUID: Double] = [:]   // presentation: `t` when each crumbled platform broke

    var body: some View {
        VStack(spacing: 4) {
            if !isDemo {
                DJTopBar(percent: Int(min(charMaxY, targetHeight) / targetHeight * 100),
                         fraction: timeLimit > 0 ? timeLeft / timeLimit : 0, theme: DJArt.theme(level))
                    .frame(height: 41)
            }

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                ZStack {
                    // Paper, platforms and the Doodler: one Canvas.
                    Canvas { ctx, size in drawWorld(ctx, size: size) }

                    // Steering halves (hold to move; no vertical swipe → feed-safe).
                    HStack(spacing: 0) {
                        Color.clear.contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0)
                                .onChanged { _ in if !done { moveDir = -1 } }
                                .onEnded { _ in if moveDir == -1 { moveDir = 0 } })
                        Color.clear.contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0)
                                .onChanged { _ in if !done { moveDir = 1 } }
                                .onEnded { _ in if moveDir == 1 { moveDir = 0 } })
                    }

                    // Demo: the held screen half tints, with a finger on it (ink on paper, white in space).
                    if isDemo && moveDir != 0 {
                        let space = DJArt.theme(level).space
                        let tint: Color = space ? .white.opacity(0.14) : Color(red: 0.2, green: 0.3, blue: 0.55).opacity(0.1)
                        HStack(spacing: 0) {
                            moveDir < 0 ? tint : .clear
                            moveDir > 0 ? tint : .clear
                        }
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(space ? .white : DJArt.theme(level).ink)
                            .shadow(color: (space ? Color.black : .white).opacity(0.7), radius: 2)
                            .position(x: w * (moveDir < 0 ? 0.22 : 0.78), y: h * 0.84)
                    }
                }
                .frame(width: w, height: h)
                .clipped()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DJArt.theme(level).paper)
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
        .onChange(of: moveDir) { _, d in if d != 0 { facingLeft = d < 0 } }
        // A crumbling platform snaps in two when it's used: remember when, to animate the halves.
        .onChange(of: platforms.filter { !$0.alive }.map(\.id)) { _, dead in
            for id in dead where brokeAt[id] == nil { brokeAt[id] = t }
            brokeAt = brokeAt.filter { dead.contains($0.key) }
        }
    }

    /// The paper scrolls with the camera; platforms sit where `step()` tests them, and the Doodler's
    /// feet stand on a platform's top surface exactly when `charY == p.y`.
    private func drawWorld(_ ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        let th = DJArt.theme(level)
        DJArt.paper(ctx, size: size, theme: th, scroll: cameraY * h)

        let goalY = screenY(targetHeight, cameraY: cameraY, h: h)
        if goalY > -40 && goalY < h + 40 { DJArt.goal(ctx, y: goalY, width: w) }

        let tk = max(11, w * 0.042)
        for p in platforms {
            let c = CGPoint(x: p.x * w, y: screenY(p.y, cameraY: cameraY, h: h))
            guard c.y > -40 && c.y < h + 80 else { continue }
            let kind: Int = p.kind == .normal ? 0 : p.kind == .moving ? 1 : p.kind == .crumble ? 2 : 3
            if p.alive {
                // The spring stretches while the Doodler is still rocketing up off it.
                let sprung = kind == 3 && vy > jumpV + 0.1 && charY > p.y && charY - p.y < 0.45
                    && abs(charX - p.x) < platHalf + charHalf
                DJArt.platform(ctx, center: c, halfWidth: platHalf * w, thick: tk, kind: kind, theme: th, sprung: sprung)
            } else if let t0 = brokeAt[p.id] {
                DJArt.broken(ctx, center: c, halfWidth: platHalf * w, thick: tk, age: t - t0, h: h, theme: th)
            }
        }

        let feet = CGPoint(x: charX * w, y: screenY(charY, cameraY: cameraY, h: h) - tk / 2)
        let body = w * 0.14
        let stretch = max(-0.08, min(0.12, vy * 0.07))
        for dx in [-w, 0, w] where abs(feet.x + dx - w / 2) < w / 2 + body {
            DJArt.doodler(ctx, feet: CGPoint(x: feet.x + dx, y: feet.y), height: body, left: facingLeft, stretch: stretch, theme: th)
        }
    }

    // MARK: - Flow
    private func run() async {
        setup()
        let start = Date()
        var last = start
        loopTask = Task {
            while !Task.isCancelled && !done {
                try? await Task.sleep(for: .seconds(0.016))
                let now = Date()
                let dt = CGFloat(min(0.05, now.timeIntervalSince(last)))
                last = now
                timeLeft = max(0, timeLimit - now.timeIntervalSince(start))
                if timeLeft <= 0 { fail(); break }
                step(dt: dt)
            }
        }
    }

    private func setup() {
        charX = 0.5; charY = 0.2; vy = 0; moveDir = 0
        cameraY = -0.45; charMaxY = 0; t = 0; done = false
        timeLeft = timeLimit
        // A solid launch platform under the critter, then fill upward.
        platforms = [Platform(x: 0.5, baseX: 0.5, y: 0.0, kind: .normal, amp: 0, spd: 0, phase: 0)]
        highestY = 0
        fillPlatforms()
    }

    private func fillPlatforms() {
        if isDemo { return }   // the demo climbs its fixed layout
        while highestY < cameraY + 1.6 {
            let gap = CGFloat.random(in: gapLo...(gapLo + 0.06))
            let y = highestY + gap
            let kind = pickKind()
            let amp: CGFloat = kind == .moving ? CGFloat.random(in: 0.12...0.22) : 0
            let hw = platHalf
            let baseX = CGFloat.random(in: (hw + amp)...(1 - hw - amp))
            platforms.append(Platform(x: baseX, baseX: baseX, y: y, kind: kind,
                                      amp: amp, spd: CGFloat.random(in: 1.0...1.8),
                                      phase: CGFloat.random(in: 0...(2 * .pi))))
            highestY = y
        }
    }

    // MARK: - Demo (live manual clip)
    // Level 1 (climb to 5) on a fixed layout — a launch pad and a staircase of normal pads with
    // four spring pads (L1 rolls springs 12% of the time). The real `step` runs at a fixed 1/60s;
    // the finger holds the left/right half to steer onto each next spring while falling, so the
    // critter rockets up spring to spring and crosses the target height (~7s) → the real win().
    private static let demoPads: [(x: CGFloat, y: CGFloat, spring: Bool)] = [
        (0.5, 0.0, false), (0.62, 0.30, true), (0.3, 0.75, false), (0.78, 1.05, false), (0.38, 1.40, true),
        (0.72, 2.0, false), (0.2, 2.35, false), (0.58, 2.55, true), (0.86, 3.1, false), (0.3, 3.45, false),
        (0.42, 3.85, true), (0.75, 4.4, false), (0.2, 4.75, false), (0.6, 5.1, false),
    ]
    private static let demoRoute = [1, 4, 7, 10]   // the spring pads, in climbing order

    private func runDemo() async {
        let dt: CGFloat = 1.0 / 60.0
        while !Task.isCancelled {
            setup()
            platforms = Self.demoPads.map {
                Platform(x: $0.x, baseX: $0.x, y: $0.y, kind: $0.spring ? .spring : .normal, amp: 0, spd: 0, phase: 0)
            }
            highestY = Self.demoPads.last!.y
            let route = Self.demoRoute.map { Self.demoPads[$0] }
            var leg = 0
            try? await Task.sleep(for: .seconds(0.5))
            while !Task.isCancelled && !done {
                // Steer toward the next spring; advance once we've bounced off it.
                if leg < route.count, charY >= route[leg].y - 0.001, vy > springV - 0.05 { leg += 1 }
                if leg < route.count, abs(route[leg].x - charX) > 0.03 {
                    moveDir = route[leg].x > charX ? 1 : -1
                } else {
                    moveDir = 0
                }
                step(dt: dt)
                try? await Task.sleep(for: .seconds(0.016))
            }
            moveDir = 0
            // Target height reached → the real win() ran (onWin is a no-op). Hold, then loop.
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    private func pickKind() -> Kind {
        let r = Double.random(in: 0..<1)
        if r < springChance { return .spring }
        if r < springChance + movingChance { return .moving }
        if r < springChance + movingChance + crumbleChance { return .crumble }
        return .normal
    }

    private func step(dt: CGFloat) {
        guard !done else { return }
        t += Double(dt)

        // Horizontal steer (wraps).
        charX += moveDir * moveSpeed * dt
        if charX < 0 { charX += 1 }
        if charX > 1 { charX -= 1 }

        // Vertical bounce.
        vy -= g * dt
        charY += vy * dt
        charMaxY = max(charMaxY, charY)

        // Moving platforms.
        for i in platforms.indices where platforms[i].kind == .moving {
            let hw = platHalf
            let x = platforms[i].baseX + platforms[i].amp * sin(t * Double(platforms[i].spd) + Double(platforms[i].phase))
            platforms[i].x = min(1 - hw, max(hw, x))
        }

        // Landings (only while falling).
        if vy < 0 {
            for i in platforms.indices where platforms[i].alive {
                let p = platforms[i]
                if charY <= p.y + 0.012 && charY >= p.y - 0.05 && abs(charX - p.x) < platHalf + charHalf {
                    charY = p.y
                    vy = p.kind == .spring ? springV : jumpV
                    Haptics.tap(); SoundManager.shared.tap()
                    if p.kind == .crumble { platforms[i].alive = false }
                    break
                }
            }
        }

        // Camera only rises; feed new platforms; cull old.
        cameraY = max(cameraY, charY - 0.45)
        fillPlatforms()
        platforms.removeAll { $0.y < cameraY - 0.3 }

        if charMaxY >= targetHeight { win(); return }
        if charY < cameraY - 0.06 { fail(); return }   // fell off the bottom
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

// MARK: - Doodle Jump art

private struct DJTheme {
    let paper: Color
    let grid: Color
    let platforms: [Color]     // normal, moving, crumbling, spring
    let ink: Color
    let space: Bool
    let strip: Color
    let stripInk: Color
}

private enum DJArt {
    static func theme(_ level: Int) -> DJTheme {
        switch min(max(level, 1), 7) {
        case 1...3:
            return DJTheme(paper: Color(red: 0.973, green: 0.941, blue: 0.898), grid: Color(red: 0.9, green: 0.66, blue: 0.48).opacity(0.38),
                           platforms: [Color(red: 0.46, green: 0.76, blue: 0.2), Color(red: 0.44, green: 0.74, blue: 0.96),
                                       Color(red: 0.62, green: 0.43, blue: 0.23), Color(red: 0.46, green: 0.76, blue: 0.2)],
                           ink: Color(red: 0.1, green: 0.08, blue: 0.07), space: false,
                           strip: Color(red: 0.7, green: 0.79, blue: 0.86).opacity(0.92), stripInk: Color(red: 0.1, green: 0.08, blue: 0.07))
        case 4, 5:
            return DJTheme(paper: Color(red: 0.87, green: 0.9, blue: 0.95), grid: Color(red: 0.44, green: 0.56, blue: 0.8).opacity(0.3),
                           platforms: [Color(red: 0.4, green: 0.72, blue: 0.3), Color(red: 0.4, green: 0.66, blue: 0.98),
                                       Color(red: 0.58, green: 0.42, blue: 0.26), Color(red: 0.4, green: 0.72, blue: 0.3)],
                           ink: Color(red: 0.08, green: 0.09, blue: 0.14), space: false,
                           strip: Color(red: 0.55, green: 0.64, blue: 0.8).opacity(0.92), stripInk: Color(red: 0.08, green: 0.09, blue: 0.14))
        default:
            return DJTheme(paper: Color(red: 0.07, green: 0.09, blue: 0.21), grid: Color(red: 0.35, green: 0.48, blue: 0.86).opacity(0.22),
                           platforms: [Color(red: 0.3, green: 0.74, blue: 0.62), Color(red: 0.46, green: 0.66, blue: 1.0),
                                       Color(red: 0.6, green: 0.44, blue: 0.3), Color(red: 0.3, green: 0.74, blue: 0.62)],
                           ink: Color(red: 0.01, green: 0.02, blue: 0.06), space: true,
                           strip: Color(red: 0.2, green: 0.25, blue: 0.44).opacity(0.95), stripInk: .white)
        }
    }

    static func hash(_ n: Double) -> Double {
        let v = sin(n * 12.9898) * 43758.5453
        return v - floor(v)
    }

    /// Graph paper that moves with the world (stars too, in space, at half speed).
    static func paper(_ ctx: GraphicsContext, size: CGSize, theme th: DJTheme, scroll: CGFloat) {
        let w = size.width, h = size.height
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(th.paper))
        if th.space {
            var stars = Path()
            for i in 0..<34 {
                let k = Double(i)
                let y = (CGFloat(hash(k + 1)) * h + scroll * 0.5).truncatingRemainder(dividingBy: h)
                let r = CGFloat(0.7 + hash(k + 2) * 1.4)
                stars.addEllipse(in: CGRect(x: CGFloat(hash(k)) * w - r, y: y - r, width: r * 2, height: r * 2))
            }
            ctx.fill(stars, with: .color(.white.opacity(0.75)))
        }
        let cell = max(14, w * 0.045)
        var grid = Path()
        var x: CGFloat = cell * 0.5
        while x < w { grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: h)); x += cell }
        var y = scroll.truncatingRemainder(dividingBy: cell)
        while y < h { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: w, y: y)); y += cell }
        ctx.stroke(grid, with: .color(th.grid), lineWidth: 0.8)
    }

    /// Like the game's friends' score lines: a red scribble along the right edge with a pennant.
    static func goal(_ ctx: GraphicsContext, y: CGFloat, width w: CGFloat) {
        let red = Color(red: 0.86, green: 0.12, blue: 0.1)
        var line = Path()
        line.move(to: CGPoint(x: w * 0.6, y: y))
        var x = w * 0.6
        var i = 0
        while x < w {
            x += 9
            i += 1
            line.addLine(to: CGPoint(x: x, y: y + (i % 2 == 0 ? -1.2 : 1.2)))
        }
        ctx.stroke(line, with: .color(red), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        let pole = CGPoint(x: w * 0.66, y: y)
        var stick = Path()
        stick.move(to: pole); stick.addLine(to: CGPoint(x: pole.x, y: pole.y - 26))
        ctx.stroke(stick, with: .color(Color(red: 0.1, green: 0.08, blue: 0.07)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        var flag = Path()
        flag.move(to: CGPoint(x: pole.x, y: pole.y - 26))
        flag.addLine(to: CGPoint(x: pole.x + 17, y: pole.y - 20))
        flag.addLine(to: CGPoint(x: pole.x, y: pole.y - 14))
        flag.closeSubpath()
        ctx.fill(flag, with: .color(red))
        ctx.stroke(flag, with: .color(Color(red: 0.1, green: 0.08, blue: 0.07)), lineWidth: 1.4)
    }

    /// A sketchy pill: kind 0 normal, 1 moving, 2 crumbling (cracked), 3 with a spring.
    static func platform(_ ctx: GraphicsContext, center c: CGPoint, halfWidth hw: CGFloat, thick t: CGFloat,
                         kind: Int, theme th: DJTheme, sprung: Bool) {
        let rect = CGRect(x: c.x - hw, y: c.y - t / 2, width: hw * 2, height: t)
        let pill = Path(roundedRect: rect, cornerRadius: t / 2)
        let col = th.platforms[max(0, min(3, kind))]
        ctx.fill(pill, with: .linearGradient(Gradient(colors: [col.mix(with: .white, by: 0.22), col, col.mix(with: .black, by: 0.22)]),
                                             startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
        if kind == 2 {
            var grain = Path()
            grain.move(to: CGPoint(x: rect.minX + t * 0.6, y: c.y + 1)); grain.addLine(to: CGPoint(x: rect.maxX - t * 0.6, y: c.y + 1))
            ctx.stroke(grain, with: .color(.black.opacity(0.2)), lineWidth: 1)
            var crack = Path()
            crack.move(to: CGPoint(x: c.x - 1, y: rect.minY))
            crack.addLine(to: CGPoint(x: c.x + 2.5, y: c.y - t * 0.1))
            crack.addLine(to: CGPoint(x: c.x - 2, y: c.y + t * 0.2))
            crack.addLine(to: CGPoint(x: c.x + 1, y: rect.maxY))
            ctx.stroke(crack, with: .color(th.ink), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        } else {
            var scribble = Path()
            for i in 0..<3 {
                let x0 = rect.minX + t * 0.55 + CGFloat(i) * t * 0.5
                scribble.move(to: CGPoint(x: x0, y: rect.minY + t * 0.72))
                scribble.addLine(to: CGPoint(x: x0 + t * 0.34, y: rect.minY + t * 0.26))
            }
            ctx.stroke(scribble, with: .color(.white.opacity(0.75)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
        ctx.stroke(pill, with: .color(th.ink), lineWidth: 1.8)

        if kind == 3 {
            let sx = c.x + hw * 0.35
            let base = rect.minY
            let height = sprung ? t * 2.4 : t * 0.9
            var coil = Path()
            coil.move(to: CGPoint(x: sx, y: base))
            let turns = sprung ? 6 : 4
            for i in 1...turns {
                let yy = base - height * CGFloat(i) / CGFloat(turns)
                coil.addLine(to: CGPoint(x: sx + (i % 2 == 0 ? -t * 0.42 : t * 0.42), y: yy))
            }
            ctx.stroke(coil, with: .color(th.ink), style: StrokeStyle(lineWidth: 2.6, lineJoin: .round))
            ctx.stroke(coil, with: .color(Color(white: 0.78)), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            let plate = Path(roundedRect: CGRect(x: sx - t * 0.7, y: base - height - t * 0.32, width: t * 1.4, height: t * 0.32), cornerRadius: 1.5)
            ctx.fill(plate, with: .color(Color(white: 0.82)))
            ctx.stroke(plate, with: .color(th.ink), lineWidth: 1.4)
        }
    }

    /// A used crumbling platform: the two halves tip outward and drop.
    static func broken(_ ctx: GraphicsContext, center c: CGPoint, halfWidth hw: CGFloat, thick t: CGFloat, age: Double,
                       h: CGFloat, theme th: DJTheme) {
        guard age >= 0, age < 0.9 else { return }
        let a = CGFloat(age)
        let fall = 0.5 * 2.4 * h * a * a
        for side in [-1.0, 1.0] as [CGFloat] {
            var g = ctx
            g.opacity = Double(max(0, 1 - a / 0.9))
            g.translateBy(x: c.x + side * a * 22, y: c.y + fall)
            g.rotate(by: .degrees(Double(side * a * 70)))
            let rect = CGRect(x: side < 0 ? -hw : 0, y: -t / 2, width: hw, height: t)
            let half = Path(roundedRect: rect, cornerRadius: t / 2)
            g.fill(half, with: .color(th.platforms[2]))
            g.stroke(half, with: .color(th.ink), lineWidth: 1.8)
        }
    }

    /// The banana Doodler, authored facing right with its feet at the origin: striped shorts, four
    /// legs, a trumpet snout, a dot eye and the banana's stem on its head.
    static func doodler(_ ctx: GraphicsContext, feet: CGPoint, height hh: CGFloat, left: Bool, stretch: CGFloat, theme th: DJTheme) {
        var g = ctx
        g.translateBy(x: feet.x, y: feet.y)
        g.scaleBy(x: (left ? -1 : 1) * (1 - stretch * 0.5) * hh, y: (1 + stretch) * hh)
        let ink = Color(red: 0.08, green: 0.07, blue: 0.06)
        let lw: CGFloat = 0.04

        var legs = Path()
        for x in [-0.2, -0.07, 0.07, 0.2] as [CGFloat] {
            legs.move(to: CGPoint(x: x, y: -0.2)); legs.addLine(to: CGPoint(x: x, y: -0.015))
            legs.addLine(to: CGPoint(x: x + 0.07, y: -0.015))
        }
        g.stroke(legs, with: .color(ink), style: StrokeStyle(lineWidth: 0.045, lineCap: .round, lineJoin: .round))

        var body = Path()
        body.move(to: CGPoint(x: -0.3, y: -0.2))
        body.addLine(to: CGPoint(x: -0.31, y: -0.74))
        body.addCurve(to: CGPoint(x: 0.29, y: -0.76), control1: CGPoint(x: -0.3, y: -1.08), control2: CGPoint(x: 0.3, y: -1.08))
        body.addLine(to: CGPoint(x: 0.3, y: -0.2))
        body.closeSubpath()
        g.fill(body, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.92, blue: 0.38), Color(red: 0.96, green: 0.78, blue: 0.16)]),
                                           startPoint: CGPoint(x: -0.3, y: -0.9), endPoint: CGPoint(x: 0.3, y: -0.3)))
        var ridge = Path()
        ridge.move(to: CGPoint(x: -0.2, y: -0.86)); ridge.addQuadCurve(to: CGPoint(x: -0.2, y: -0.46), control: CGPoint(x: -0.25, y: -0.66))
        g.stroke(ridge, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 0.04, lineCap: .round))

        // Striped shorts over the lower body.
        let shorts = Path(roundedRect: CGRect(x: -0.31, y: -0.42, width: 0.62, height: 0.23), cornerRadius: 0.04)
        g.fill(shorts, with: .color(Color(red: 0.46, green: 0.66, blue: 0.2)))
        var stripes = g
        stripes.clip(to: shorts)
        for y in [-0.39, -0.31, -0.23] as [CGFloat] {
            stripes.fill(Path(CGRect(x: -0.4, y: y, width: 0.8, height: 0.045)), with: .color(Color(red: 0.16, green: 0.36, blue: 0.12)))
        }
        g.stroke(shorts, with: .color(ink), lineWidth: lw)
        g.stroke(body, with: .color(ink), lineWidth: lw)

        // The snout: a tube ending in a flared opening, facing forward.
        var snout = Path()
        snout.move(to: CGPoint(x: 0.24, y: -0.8))
        snout.addLine(to: CGPoint(x: 0.5, y: -0.8))
        snout.addLine(to: CGPoint(x: 0.58, y: -0.86))
        snout.addLine(to: CGPoint(x: 0.58, y: -0.6))
        snout.addLine(to: CGPoint(x: 0.5, y: -0.66))
        snout.addLine(to: CGPoint(x: 0.24, y: -0.66))
        snout.closeSubpath()
        g.fill(snout, with: .color(Color(red: 0.98, green: 0.86, blue: 0.28)))
        g.stroke(snout, with: .color(ink), style: StrokeStyle(lineWidth: lw, lineJoin: .round))
        g.fill(Path(ellipseIn: CGRect(x: 0.545, y: -0.84, width: 0.06, height: 0.22)), with: .color(ink.opacity(0.85)))

        g.fill(Path(ellipseIn: CGRect(x: 0.08, y: -0.87, width: 0.085, height: 0.085)), with: .color(ink))
        g.fill(Path(ellipseIn: CGRect(x: 0.1, y: -0.86, width: 0.025, height: 0.025)), with: .color(.white))

        var stem = Path()
        stem.move(to: CGPoint(x: -0.02, y: -0.98))
        stem.addQuadCurve(to: CGPoint(x: -0.12, y: -1.13), control: CGPoint(x: -0.02, y: -1.1))
        g.stroke(stem, with: .color(ink), style: StrokeStyle(lineWidth: 0.1, lineCap: .round))
        g.stroke(stem, with: .color(Color(red: 0.55, green: 0.42, blue: 0.16)), style: StrokeStyle(lineWidth: 0.055, lineCap: .round))
    }
}

/// Doodle Jump's torn-paper strip: the height in handwriting, and the clock as a pencil-hatched bar.
private struct DJTopBar: View {
    let percent: Int
    let fraction: Double
    let theme: DJTheme

    var body: some View {
        ZStack(alignment: .top) {
            Canvas { ctx, size in
                var strip = Path()
                strip.move(to: .zero)
                strip.addLine(to: CGPoint(x: size.width, y: 0))
                var x = size.width
                var i = 0
                while x > 0 {
                    x -= 7
                    i += 1
                    strip.addLine(to: CGPoint(x: max(0, x), y: size.height - (i % 2 == 0 ? 2 : 6) - CGFloat(DJArt.hash(Double(i)) * 3)))
                }
                strip.closeSubpath()
                ctx.fill(strip, with: .color(theme.strip))
            }
            HStack {
                Text("\(percent)%")
                    .font(.custom("Noteworthy-Bold", size: 25))
                    .foregroundStyle(theme.stripInk)
                    .monospacedDigit()
                Spacer()
                Canvas { ctx, size in
                    let box = CGRect(x: 1, y: 1, width: size.width - 2, height: size.height - 2)
                    let fill = CGRect(x: box.minX, y: box.minY, width: box.width * CGFloat(max(0, min(1, fraction))), height: box.height)
                    var hatch = Path()
                    var x = fill.minX - box.height
                    while x < fill.maxX {
                        hatch.move(to: CGPoint(x: x, y: box.maxY)); hatch.addLine(to: CGPoint(x: x + box.height, y: box.minY))
                        x += 4
                    }
                    var clipped = ctx
                    clipped.clip(to: Path(fill))
                    clipped.stroke(hatch, with: .color(fraction < 0.3 ? Color(red: 0.86, green: 0.12, blue: 0.1) : theme.stripInk), lineWidth: 1.6)
                    ctx.stroke(Path(roundedRect: box, cornerRadius: 3), with: .color(theme.stripInk), lineWidth: 1.8)
                }
                .frame(width: 104, height: 14)
            }
            .padding(.horizontal, 16)
            .padding(.top, 3)
        }
    }
}
