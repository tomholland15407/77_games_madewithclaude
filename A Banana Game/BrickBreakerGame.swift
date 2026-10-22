//
//  BrickBreakerGame.swift
//  A Banana Game
//
//  Reflex (drag) — Breakout / Arkanoid, juiced up. Drag the paddle left/right to
//  keep the ball(s) alive and smash every brick before the clock runs out. Broken
//  bricks sometimes drop a POWER-UP that falls toward the paddle — catch it for a
//  temporary edge: double/triple ball, a fire-ball that tears straight through
//  bricks, an ice-ball that swells huge, a wider paddle, slow-motion, or a laser
//  paddle that auto-fires bolts. Lose every ball and you fail back to level 1.
//
//  7 levels: the ball starts fast and only gets faster, the wall packs in far more
//  bricks of mixed sizes, and the paddle shrinks — by 6–7 it's a blur.
//
//  Dragging the paddle would fight the feed's vertical pager, so this game sets
//  `locksFeed: true` (the page locks paging while playing and shows a skip button).
//
//  Drawn like BlackBerry's Brick Breaker: brushed grey floor plates inside a yellow-and-black
//  hazard frame (drawn outside the physics walls), embossed bricks stamped with a zig-zag motif,
//  the blue hover paddle with its chrome hump (a red cannon while the laser lasts), a dark steel
//  ball that turns into a fireball or a big ice ball, glossy pill capsules, and a gunmetal HUD
//  with yellow block lettering.
//

import SwiftUI

enum BrickBreakerGame {
    static let definition = GameDefinition(
        id: "brick-breaker",
        title: "Brick Breaker",
        emoji: "🍌",
        genre: .reflex,
        levelCount: 7,
        locksFeed: true,
        manual: GameManual(
            bullets: [
                "Drag the paddle left and right to keep the ball alive.",
                "Smash every brick before the clock runs out.",
                "Broken bricks may drop a power-up: extra balls, fire/ice, wider paddle, slow-mo, or a laser.",
                "Lose every ball and you're back to level 1.",
            ],
            bulletsVI: [
                "Kéo thanh đỡ trái phải để giữ bóng không rơi.",
                "Đập vỡ mọi viên gạch trước khi hết giờ.",
                "Gạch vỡ có thể rơi vật tăng lực: thêm bóng, lửa/băng, thanh rộng, chậm giờ, hoặc laser.",
                "Mất hết bóng sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(BrickBreakerView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct BrickBreakerView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    // MARK: Difficulty
    private var brickRows: Int { [4, 5, 6, 6, 7, 7, 8][min(level, 7) - 1] }
    /// Ball speed as a fraction of the play area per second — fast from L1, faster fast.
    private var ballSpeed: CGFloat { [0.90, 1.05, 1.22, 1.40, 1.60, 1.82, 2.05][min(level, 7) - 1] }
    /// Half-width of the paddle (fraction of width) — shrinks with level.
    private var paddleHalf: CGFloat { max(0.05, 0.15 - CGFloat(level) * 0.010) }
    private var timeLimit: Double { [55, 55, 58, 60, 62, 64, 66][min(level, 7) - 1] }
    /// Chance a broken brick drops a power-up (a touch more generous early on).
    private var dropChance: Double { level <= 2 ? 0.26 : 0.20 }

    private let baseBallR: CGFloat = 0.018
    private let paddleY: CGFloat = 0.93

    /// Brick paints, as on the BlackBerry game's light metal floor (colour is only decoration).
    private let brickColors: [Color] = [
        Color(red: 0.84, green: 0.20, blue: 0.18),
        Color(red: 0.95, green: 0.52, blue: 0.13),
        Color(red: 0.97, green: 0.79, blue: 0.16),
        Color(red: 0.32, green: 0.70, blue: 0.26),
        Color(red: 0.13, green: 0.64, blue: 0.72),
        Color(red: 0.24, green: 0.42, blue: 0.88),
        Color(red: 0.60, green: 0.32, blue: 0.80),
    ]

    // MARK: Power-ups
    private enum Power: CaseIterable {
        case doubleBall, tripleBall, fire, ice, wide, slow, laser

        var color: Color {
            switch self {
            case .doubleBall: return Color(red: 0.55, green: 0.90, blue: 0.45)
            case .tripleBall: return Color(red: 0.35, green: 0.85, blue: 0.85)
            case .fire:       return Color(red: 1.00, green: 0.50, blue: 0.20)
            case .ice:        return Color(red: 0.55, green: 0.82, blue: 1.00)
            case .wide:       return BananaTheme.banana
            case .slow:       return Color(red: 0.72, green: 0.60, blue: 1.00)
            case .laser:      return Color(red: 1.00, green: 0.40, blue: 0.55)
            }
        }
        var icon: String {
            switch self {
            case .doubleBall: return "2.circle.fill"
            case .tripleBall: return "3.circle.fill"
            case .fire:       return "flame.fill"
            case .ice:        return "snowflake"
            case .wide:       return "arrow.left.and.right"
            case .slow:       return "tortoise.fill"
            case .laser:      return "bolt.fill"
            }
        }
    }

    // MARK: State
    private struct Brick: Identifiable {
        let id = UUID()
        let cx: CGFloat; let cy: CGFloat      // center (fractions)
        let hw: CGFloat; let hh: CGFloat      // half extents (fractions)
        let color: Color
        var alive = true
    }
    private struct Ball: Identifiable {
        let id = UUID()
        var pos: CGPoint
        var vel: CGVector
    }
    private struct Drop: Identifiable {
        let id = UUID()
        var pos: CGPoint
        let kind: Power
    }
    private struct Bolt: Identifiable {
        let id = UUID()
        var pos: CGPoint
    }
    private struct Burst: Identifiable {
        let id = UUID()
        let x: CGFloat; let y: CGFloat
        let color: Color
    }

    @State private var bricks: [Brick] = []
    @State private var balls: [Ball] = []
    @State private var drops: [Drop] = []
    @State private var bolts: [Bolt] = []
    @State private var bursts: [Burst] = []
    @State private var paddleX: CGFloat = 0.5
    @State private var timeLeft = 0.0
    @State private var done = false
    @State private var loopTask: Task<Void, Never>?
    @State private var shakeTrigger = 0

    // Timed effect expiries (nil = inactive).
    @State private var fireUntil: Date?
    @State private var iceUntil: Date?
    @State private var wideUntil: Date?
    @State private var slowUntil: Date?
    @State private var laserUntil: Date?
    @State private var lastBoltFire = Date.distantPast

    private var fireActive: Bool { (fireUntil ?? .distantPast) > Date() }
    private var iceActive: Bool  { (iceUntil  ?? .distantPast) > Date() }
    private var wideActive: Bool { (wideUntil ?? .distantPast) > Date() }
    private var slowActive: Bool { (slowUntil ?? .distantPast) > Date() }
    private var laserActive: Bool { (laserUntil ?? .distantPast) > Date() }

    private var curPaddleHalf: CGFloat { wideActive ? min(0.30, paddleHalf * 1.9) : paddleHalf }
    private var ballR: CGFloat { iceActive ? baseBallR * 1.9 : baseBallR }
    private var effectiveSpeed: CGFloat { ballSpeed * (slowActive ? 0.5 : 1.0) }

    private var remaining: Int { bricks.filter(\.alive).count }

    var body: some View {
        VStack(spacing: 0) {
            if !isDemo { hud }

            GeometryReader { geo in
                // The hazard frame sits OUTSIDE the physics field, so the ball still bounces at the
                // field's normalized walls; drags anywhere on the card move the paddle as before.
                let t = BBArt.frameWidth(geo.size)
                let w = max(1, geo.size.width - t * 2)
                let h = max(1, geo.size.height - t)
                ZStack(alignment: .topLeading) {
                    BBFrame(size: geo.size, t: t).equatable()

                    ZStack(alignment: .topLeading) {
                        BBFloor(size: CGSize(width: w, height: h)).equatable()
                        BBBricks(bricks: bricks.filter(\.alive).map { BBBrickSnap(cx: $0.cx, cy: $0.cy, hw: $0.hw, hh: $0.hh, color: $0.color) },
                                 size: CGSize(width: w, height: h))
                            .equatable()

                        // Everything that moves: bolts, capsules, balls and the paddle.
                        Canvas { ctx, size in drawAction(ctx, w: size.width, h: size.height) }
                            .allowsHitTesting(false)

                        // Demo: a finger dragging the paddle.
                        if isDemo {
                            Image(systemName: "hand.point.up.left.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.6), radius: 3)
                                .position(x: paddleX * w + 10, y: paddleY * h + 16)
                        }

                        // Particle bursts on brick breaks.
                        ForEach(bursts) { b in
                            ParticleBurstView(color: b.color, count: 9, spread: 34, gravity: 30) {
                                bursts.removeAll { $0.id == b.id }
                            }
                            .position(x: b.x * w, y: b.y * h)
                        }
                    }
                    .frame(width: w, height: h)
                    .clipped()
                    .offset(x: t, y: t)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .screenShake(shakeTrigger, amount: 7)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard !done else { return }
                            paddleX = min(1 - curPaddleHalf, max(curPaddleHalf, (value.location.x - t) / w))
                        }
                )
            }
        }
        .background(BBArt.gunmetal)
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
    }

    /// Bricks left in the BlackBerry HUD's yellow block letters, over the clock gauge.
    private var hud: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                BBBrickIcon().frame(width: 30, height: 15)
                Text(L("\(remaining) left", "còn \(remaining)"))
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(BBArt.hudYellow)
                    .shadow(color: .black, radius: 0, x: 1.5, y: 2)
            }
            timeBar.frame(height: 8).padding(.horizontal, 40)
        }
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    // MARK: - Drawing

    private func drawAction(_ ctx: GraphicsContext, w: CGFloat, h: CGFloat) {
        // Laser bolts.
        for bolt in bolts {
            let r = CGRect(x: bolt.pos.x * w - 2.5, y: bolt.pos.y * h - 10, width: 5, height: 20)
            ctx.fill(Path(roundedRect: r.insetBy(dx: -3, dy: -3), cornerRadius: 5), with: .color(BBArt.laser.opacity(0.35)))
            ctx.fill(Path(roundedRect: r, cornerRadius: 2.5), with: .color(BBArt.laser))
            ctx.fill(Path(roundedRect: r.insetBy(dx: 1.4, dy: 3), cornerRadius: 1), with: .color(.white.opacity(0.9)))
        }
        // Falling power-up capsules.
        for d in drops {
            BBArt.capsule(ctx, center: CGPoint(x: d.pos.x * w, y: d.pos.y * h), color: d.kind.color, icon: d.kind.icon)
        }
        // Balls: a dark steel ball, a fireball while FIRE lasts, a big frosty ball while ICE lasts.
        for b in balls {
            BBArt.ball(ctx, center: CGPoint(x: b.pos.x * w, y: b.pos.y * h), radius: ballR * w,
                       dir: CGVector(dx: b.vel.dx * w, dy: b.vel.dy * h), fire: fireActive, ice: iceActive)
        }
        // The paddle.
        BBArt.paddle(ctx, center: CGPoint(x: paddleX * w, y: paddleY * h), width: curPaddleHalf * 2 * w, laser: laserActive)
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let fraction = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.45))
                Capsule().stroke(.white.opacity(0.12), lineWidth: 1)
                Capsule().fill(LinearGradient(colors: fraction < 0.3 ? [Color(red: 1, green: 0.45, blue: 0.35), Color(red: 0.8, green: 0.12, blue: 0.1)]
                                                                     : [BBArt.hudYellow.lit(0.3), BBArt.hudYellow.shade(0.15)],
                                              startPoint: .top, endPoint: .bottom))
                    .frame(width: geo.size.width * fraction)
            }
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

    // MARK: - Demo (live manual clip)
    // A fixed Level-1 endgame: six bricks left and a FIRE power-up already falling from one just
    // broken (random drops are off in the demo). The real `step` runs at a fixed 1/60s; your
    // finger drags the paddle: it catches the drop when it can still get back to the ball, then
    // meets each return, aiming the bounce (the paddle's off-centre deflection) at the nearest
    // brick. The fire-ball plows through the wall and the last brick falls → the real win().
    // Tuned offline against a port of `advanceBall`; robust to launch/drop/finger-speed tweaks.
    private static let demoWall: [(cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat)] = [
        (0.2, 0.156, 0.16, 0.052), (0.62, 0.156, 0.16, 0.052),
        (0.36, 0.204, 0.14, 0.040), (0.78, 0.204, 0.14, 0.040),
        (0.5, 0.25, 0.16, 0.052), (0.24, 0.294, 0.13, 0.040),
    ]

    private func demoSetup() {
        bricks = Self.demoWall.enumerated().map { i, b in
            Brick(cx: b.cx, cy: b.cy, hw: b.w / 2 - 0.006, hh: b.h / 2 - 0.006,
                  color: brickColors[(i * 2) % brickColors.count])
        }
        paddleX = 0.5
        let a = CGFloat.pi * 0.62
        balls = [Ball(pos: CGPoint(x: 0.5, y: paddleY - 0.06),
                      vel: CGVector(dx: cos(a) * ballSpeed, dy: -sin(a) * ballSpeed))]
        drops = [Drop(pos: CGPoint(x: 0.5, y: 0.55), kind: .fire)]
        bolts = []; bursts = []
        fireUntil = nil; iceUntil = nil; wideUntil = nil; slowUntil = nil; laserUntil = nil
        timeLeft = timeLimit
        done = false
    }

    /// Where the lead ball will cross the paddle line (straight line + wall bounces) and when.
    private func demoIntercept(_ b: Ball, dt: CGFloat) -> (x: CGFloat, t: CGFloat) {
        var x = b.pos.x, y = b.pos.y, vx = b.vel.dx, vy = b.vel.dy, t: CGFloat = 0
        for _ in 0..<2000 {
            x += vx * dt; y += vy * dt; t += dt
            if x < ballR { x = ballR; vx = abs(vx) }
            if x > 1 - ballR { x = 1 - ballR; vx = -abs(vx) }
            if y < ballR { y = ballR; vy = abs(vy) }
            if vy > 0 && y >= paddleY - 0.02 { return (x, t) }
        }
        return (x, t)
    }

    /// The finger: catch the drop if there's time to get back, else line up the return so the
    /// deflection sends the ball at the nearest remaining brick.
    private func demoPaddleTarget(dt: CGFloat, fingerSpeed: CGFloat) -> CGFloat {
        guard let ball = balls.first else { return paddleX }
        let (xh, th) = demoIntercept(ball, dt: dt)
        if let d = drops.first {
            let tDrop = (paddleY - 0.03 - d.pos.y) / 0.55
            if tDrop < th - 0.1 && abs(d.pos.x - xh) <= fingerSpeed * (th - tDrop) * 0.8 { return d.pos.x }
        }
        guard let b = bricks.filter(\.alive).min(by: { abs($0.cx - xh) < abs($1.cx - xh) }) else { return xh }
        let ratio = (b.cx - xh) / ((paddleY - 0.02) - b.cy)
        let off = max(-0.85, min(0.85, ratio / sqrt(1 + ratio * ratio) / 0.75))
        return xh - off * curPaddleHalf
    }

    private func runDemo() async {
        let dt: CGFloat = 1.0 / 60.0, fingerSpeed: CGFloat = 1.6
        while !Task.isCancelled {
            demoSetup()
            try? await Task.sleep(for: .seconds(0.6))
            var t: CGFloat = 0
            while !Task.isCancelled && !done && t < 15 {
                t += dt
                let target = demoPaddleTarget(dt: dt, fingerSpeed: fingerSpeed)
                let stepMax = fingerSpeed * dt
                paddleX = min(1 - curPaddleHalf, max(curPaddleHalf, paddleX + max(-stepMax, min(stepMax, target - paddleX))))
                step(dt: dt)
                try? await Task.sleep(for: .seconds(0.016))
            }
            // Wall cleared → the real win() ran (onWin is a no-op). Hold, then loop.
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    private func setup() {
        bricks = buildBricks()
        paddleX = 0.5
        balls = [makeBall()]
        drops = []; bolts = []; bursts = []
        fireUntil = nil; iceUntil = nil; wideUntil = nil; slowUntil = nil; laserUntil = nil
        timeLeft = timeLimit
    }

    /// A ball launched upward from the paddle at a randomized angle.
    private func makeBall() -> Ball {
        let angle = CGFloat.random(in: (.pi * 0.60)...(.pi * 0.90))   // up-left..up-right
        return Ball(pos: CGPoint(x: paddleX, y: paddleY - 0.06),
                    vel: CGVector(dx: cos(angle) * effectiveSpeed, dy: -sin(angle) * effectiveSpeed))
    }

    /// Mixed-size wall: each row is split into a random number of bricks of varied
    /// widths, and row heights alternate, so it never reads as a uniform grid.
    private func buildBricks() -> [Brick] {
        var built: [Brick] = []
        let top: CGFloat = 0.13
        let x0: CGFloat = 0.06
        let usable: CGFloat = 0.88
        let gap: CGFloat = 0.006
        var y = top
        for r in 0..<brickRows {
            let rowH: CGFloat = r % 2 == 0 ? 0.052 : 0.040   // alternate tall/short rows
            // Split this row into segments whose widths sum to `usable`.
            let segCount = Int.random(in: max(3, 4)...7)
            var weights = (0..<segCount).map { _ in CGFloat.random(in: 0.7...1.6) }
            let sum = weights.reduce(0, +)
            weights = weights.map { $0 / sum }
            var x = x0
            for (i, wgt) in weights.enumerated() {
                let segW = usable * wgt
                let cx = x + segW / 2
                let cy = y + rowH / 2
                built.append(Brick(cx: cx, cy: cy,
                                   hw: segW / 2 - gap, hh: rowH / 2 - gap,
                                   color: brickColors[(r + i) % brickColors.count]))
                x += segW
            }
            y += rowH + 0.004
        }
        return built
    }

    private func step(dt: CGFloat) {
        guard !done else { return }

        // Advance every ball; collect indices that fell off the bottom.
        var lost: [Int] = []
        for i in balls.indices {
            advanceBall(&balls[i], dt: dt)
            if balls[i].pos.y > 1 + ballR { lost.append(i) }
        }
        for i in lost.reversed() { balls.remove(at: i) }
        if !lost.isEmpty { shakeTrigger += 1 }
        if balls.isEmpty { fail(); return }

        stepDrops(dt: dt)
        stepBolts(dt: dt)

        if remaining == 0 { win() }
    }

    private func advanceBall(_ ball: inout Ball, dt: CGFloat) {
        // Keep magnitude at the current effective speed (handles slow-mo in/out).
        renormalize(&ball.vel)
        ball.pos.x += ball.vel.dx * dt
        ball.pos.y += ball.vel.dy * dt

        // Walls.
        if ball.pos.x < ballR { ball.pos.x = ballR; ball.vel.dx = abs(ball.vel.dx) }
        if ball.pos.x > 1 - ballR { ball.pos.x = 1 - ballR; ball.vel.dx = -abs(ball.vel.dx) }
        if ball.pos.y < ballR { ball.pos.y = ballR; ball.vel.dy = abs(ball.vel.dy) }

        // Paddle.
        if ball.vel.dy > 0 && ball.pos.y >= paddleY - 0.02 && ball.pos.y <= paddleY + 0.02 {
            if abs(ball.pos.x - paddleX) <= curPaddleHalf + ballR {
                ball.vel.dy = -abs(ball.vel.dy)
                let offset = (ball.pos.x - paddleX) / curPaddleHalf     // -1...1
                ball.vel.dx = offset * effectiveSpeed * 0.75
                renormalize(&ball.vel)
                ball.pos.y = paddleY - 0.02
                Haptics.tap(); SoundManager.shared.tap()
            }
        }

        // Bricks — resolve at most one hit per frame (unless fire tears through).
        for i in bricks.indices where bricks[i].alive {
            let b = bricks[i]
            let overlapX = b.hw + ballR - abs(ball.pos.x - b.cx)
            let overlapY = b.hh + ballR - abs(ball.pos.y - b.cy)
            if overlapX > 0 && overlapY > 0 {
                if !fireActive {
                    // Push out along the shallower axis and reflect that component.
                    if overlapX < overlapY {
                        ball.vel.dx = ball.pos.x < b.cx ? -abs(ball.vel.dx) : abs(ball.vel.dx)
                    } else {
                        ball.vel.dy = ball.pos.y < b.cy ? -abs(ball.vel.dy) : abs(ball.vel.dy)
                    }
                }
                breakBrick(i)
                if !fireActive { break }   // fire keeps plowing through this frame
            }
        }
    }

    private func breakBrick(_ i: Int) {
        guard bricks[i].alive else { return }
        let b = bricks[i]
        bricks[i].alive = false
        bursts.append(Burst(x: b.cx, y: b.cy, color: b.color))
        Haptics.tap(); SoundManager.shared.tap()
        if !isDemo, Double.random(in: 0...1) < dropChance {   // the demo seeds its one drop
            drops.append(Drop(pos: CGPoint(x: b.cx, y: b.cy), kind: Power.allCases.randomElement()!))
        }
    }

    private func stepDrops(dt: CGFloat) {
        for i in drops.indices { drops[i].pos.y += 0.55 * dt }
        // Catch (near paddle) or discard (off bottom).
        var caught: [Int] = []
        for (i, d) in drops.enumerated() {
            if d.pos.y >= paddleY - 0.03 && d.pos.y <= paddleY + 0.03
                && abs(d.pos.x - paddleX) <= curPaddleHalf + 0.03 {
                apply(d.kind)
                caught.append(i)
            } else if d.pos.y > 1.05 {
                caught.append(i)
            }
        }
        for i in caught.reversed() { drops.remove(at: i) }
    }

    private func stepBolts(dt: CGFloat) {
        // Auto-fire while the laser is active.
        if laserActive && Date().timeIntervalSince(lastBoltFire) > 0.42 {
            lastBoltFire = Date()
            bolts.append(Bolt(pos: CGPoint(x: paddleX, y: paddleY - 0.03)))
            SoundManager.shared.tap()
        }
        for i in bolts.indices { bolts[i].pos.y -= 1.25 * dt }
        var spent: [Int] = []
        for (i, bolt) in bolts.enumerated() {
            if bolt.pos.y < -0.02 { spent.append(i); continue }
            if let hit = bricks.firstIndex(where: { $0.alive
                && abs(bolt.pos.x - $0.cx) <= $0.hw
                && abs(bolt.pos.y - $0.cy) <= $0.hh + 0.01 }) {
                breakBrick(hit)
                spent.append(i)
            }
        }
        for i in spent.reversed() { bolts.remove(at: i) }
    }

    private func apply(_ kind: Power) {
        Haptics.success(); SoundManager.shared.tap()
        shakeTrigger += 1
        let now = Date()
        switch kind {
        case .doubleBall:
            if balls.count < 6, let seed = balls.first { balls.append(spawnFrom(seed)) }
        case .tripleBall:
            if let seed = balls.first {
                for _ in 0..<2 where balls.count < 6 { balls.append(spawnFrom(seed)) }
            }
        case .fire:  fireUntil  = now.addingTimeInterval(6)
        case .ice:   iceUntil   = now.addingTimeInterval(6)
        case .wide:  wideUntil  = now.addingTimeInterval(8)
        case .slow:  slowUntil  = now.addingTimeInterval(5)
        case .laser: laserUntil = now.addingTimeInterval(6)
        }
    }

    /// A fresh ball spawned from an existing one at a mirrored/jittered angle.
    private func spawnFrom(_ seed: Ball) -> Ball {
        let angle = CGFloat.random(in: (.pi * 0.60)...(.pi * 0.90))
        let dir: CGFloat = Bool.random() ? 1 : -1
        return Ball(pos: seed.pos,
                    vel: CGVector(dx: cos(angle) * effectiveSpeed * dir, dy: -sin(angle) * effectiveSpeed))
    }

    /// Keep a velocity at the current effective speed while preserving its direction.
    private func renormalize(_ vel: inout CGVector) {
        let mag = sqrt(vel.dx * vel.dx + vel.dy * vel.dy)
        guard mag > 0.0001 else { return }
        vel.dx = vel.dx / mag * effectiveSpeed
        vel.dy = vel.dy / mag * effectiveSpeed
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

// MARK: - BlackBerry Brick Breaker art

private struct BBBrickSnap: Equatable {
    let cx: CGFloat, cy: CGFloat, hw: CGFloat, hh: CGFloat
    let color: Color
}

private enum BBArt {
    static let gunmetal = Color(red: 0.15, green: 0.16, blue: 0.19)
    static let hudYellow = Color(red: 0.99, green: 0.8, blue: 0.2)
    static let hazard = Color(red: 0.99, green: 0.82, blue: 0.12)
    static let laser = Color(red: 1.0, green: 0.2, blue: 0.25)
    static let paddleBlue = Color(red: 0.2, green: 0.38, blue: 0.92)
    static let ink = Color(red: 0.07, green: 0.08, blue: 0.1)

    static func frameWidth(_ s: CGSize) -> CGFloat { max(8, min(s.width, s.height) * 0.034) }

    static func hash(_ n: Double) -> CGFloat {
        let v: Double = sin(n * 12.9898) * 43758.5453
        return CGFloat(v - floor(v))
    }

    /// An embossed brick: bevelled edges, a glossy face and the dark zig-zag motif the
    /// BlackBerry bricks are stamped with.
    static func brick(_ ctx: GraphicsContext, _ r: CGRect, _ base: Color) {
        let rad = min(3, r.height * 0.18)
        ctx.fill(Path(roundedRect: r.offsetBy(dx: 1.2, dy: 1.8), cornerRadius: rad), with: .color(.black.opacity(0.28)))
        let body = Path(roundedRect: r, cornerRadius: rad)
        ctx.fill(body, with: .linearGradient(Gradient(colors: [base.lit(0.28), base, base.shade(0.22)]),
                                             startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
        // The stamped motif: a zig-zag band between two rails.
        let face = r.insetBy(dx: min(r.width * 0.12, r.height * 0.3), dy: r.height * 0.27)
        if face.width > 4 && face.height > 2 {
            var zig = Path()
            let step = max(3, face.height * 0.95)
            var x = face.minX
            var up = true
            zig.move(to: CGPoint(x: x, y: face.maxY))
            while x < face.maxX {
                x = min(face.maxX, x + step)
                zig.addLine(to: CGPoint(x: x, y: up ? face.minY : face.maxY))
                up.toggle()
            }
            let lw = max(1, r.height * 0.12)
            ctx.stroke(zig.offsetBy(dx: 0, dy: 0.8), with: .color(base.lit(0.35).opacity(0.7)), style: StrokeStyle(lineWidth: lw * 0.6, lineJoin: .round))
            ctx.stroke(zig, with: .color(base.shade(0.45)), style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
        }
        // Bevel: a lit top lip and a dark bottom lip.
        ctx.fill(Path(roundedRect: CGRect(x: r.minX + 1.5, y: r.minY + 1, width: r.width - 3, height: max(1, r.height * 0.12)), cornerRadius: 1),
                 with: .color(.white.opacity(0.45)))
        ctx.fill(Path(CGRect(x: r.minX + 1.5, y: r.maxY - max(1, r.height * 0.1) - 0.6, width: r.width - 3, height: max(1, r.height * 0.1))),
                 with: .color(.black.opacity(0.22)))
        ctx.stroke(body, with: .color(ink.opacity(0.6)), lineWidth: 1)
    }

    /// A glossy pill capsule carrying the power-up's icon.
    static func capsule(_ ctx: GraphicsContext, center c: CGPoint, color: Color, icon: String) {
        let r = CGRect(x: c.x - 18, y: c.y - 11, width: 36, height: 22)
        let pill = Path(roundedRect: r, cornerRadius: r.height / 2)
        ctx.fill(pill.offsetBy(dx: 1.5, dy: 2.5), with: .color(.black.opacity(0.3)))
        ctx.fill(pill, with: .linearGradient(Gradient(colors: [color.lit(0.45), color, color.shade(0.35)]),
                                             startPoint: CGPoint(x: c.x, y: r.minY), endPoint: CGPoint(x: c.x, y: r.maxY)))
        ctx.fill(Path(roundedRect: CGRect(x: r.minX + 6, y: r.minY + 2.5, width: r.width - 12, height: 5), cornerRadius: 2.5),
                 with: .color(.white.opacity(0.55)))
        ctx.stroke(pill, with: .color(ink.opacity(0.7)), lineWidth: 1.3)
        var img = ctx.resolve(Image(systemName: icon))
        img.shading = .color(.black.opacity(0.85))
        let s = img.size
        let k = min(13 / max(1, s.width), 13 / max(1, s.height))
        ctx.draw(img, in: CGRect(x: c.x - s.width * k / 2, y: c.y - s.height * k / 2 + 1, width: s.width * k, height: s.height * k))
    }

    /// The ball: dark steel, or a fireball with a flame trail, or a big frosted ice ball.
    static func ball(_ ctx: GraphicsContext, center c: CGPoint, radius rad: CGFloat, dir: CGVector, fire: Bool, ice: Bool) {
        let len = max(0.0001, hypot(dir.dx, dir.dy))
        let ux = dir.dx / len, uy = dir.dy / len
        if fire {
            for k in (1...5).reversed() {
                let d = CGFloat(k) * rad * 0.85
                let rr = rad * (1.05 - CGFloat(k) * 0.14)
                let p = CGPoint(x: c.x - ux * d, y: c.y - uy * d)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2)),
                         with: .color(Color(red: 1, green: 0.35 + 0.1 * Double(k), blue: 0.05).opacity(0.85 - 0.14 * Double(k))))
            }
        }
        let rect = CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2)
        let colors: [Color] = fire ? [.white, Color(red: 1, green: 0.9, blue: 0.4), Color(red: 1, green: 0.5, blue: 0.1), Color(red: 0.8, green: 0.15, blue: 0.05)]
            : ice ? [.white, Color(red: 0.78, green: 0.93, blue: 1), Color(red: 0.4, green: 0.7, blue: 0.97), Color(red: 0.2, green: 0.45, blue: 0.8)]
            : [.white, Color(red: 0.62, green: 0.65, blue: 0.7), Color(red: 0.25, green: 0.27, blue: 0.3), Color(red: 0.08, green: 0.09, blue: 0.1)]
        ctx.fill(Path(ellipseIn: rect.offsetBy(dx: rad * 0.2, dy: rad * 0.3)), with: .color(.black.opacity(0.25)))
        ctx.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: colors),
                                                              center: CGPoint(x: c.x - rad * 0.35, y: c.y - rad * 0.4),
                                                              startRadius: 0, endRadius: rad * 1.5))
        if ice {
            for k in 0..<5 {
                let a = Double(k) * 1.26
                let p = CGPoint(x: c.x + CGFloat(cos(a)) * rad * 0.55, y: c.y + CGFloat(sin(a)) * rad * 0.55)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2)), with: .color(.white.opacity(0.85)))
            }
        }
        ctx.stroke(Path(ellipseIn: rect), with: .color(ink.opacity(fire ? 0.2 : 0.5)), lineWidth: 1)
    }

    /// The blue hover paddle with a chrome hump — carrying a red cannon while the laser lasts.
    static func paddle(_ ctx: GraphicsContext, center c: CGPoint, width w: CGFloat, laser: Bool) {
        let body = CGRect(x: c.x - w / 2, y: c.y - 7, width: w, height: 14)
        let path = Path(roundedRect: body, cornerRadius: 7)
        ctx.fill(path.offsetBy(dx: 0, dy: 3), with: .color(.black.opacity(0.28)))
        ctx.fill(path, with: .linearGradient(Gradient(colors: [paddleBlue.lit(0.35), paddleBlue, paddleBlue.shade(0.4)]),
                                             startPoint: CGPoint(x: c.x, y: body.minY), endPoint: CGPoint(x: c.x, y: body.maxY)))
        // Darker end pods.
        for x in [body.minX, body.maxX - min(12, w * 0.18)] {
            ctx.fill(Path(roundedRect: CGRect(x: x, y: body.minY, width: min(12, w * 0.18), height: body.height), cornerRadius: 7),
                     with: .color(paddleBlue.shade(0.35)))
        }
        ctx.fill(Path(roundedRect: CGRect(x: body.minX + 5, y: body.minY + 2, width: w - 10, height: 2.5), cornerRadius: 1.2),
                 with: .color(.white.opacity(0.45)))
        ctx.stroke(path, with: .color(Color(red: 0.04, green: 0.08, blue: 0.3)), lineWidth: 1.3)
        // Chrome hump in the middle.
        let hw = min(w * 0.42, 44)
        let hump = CGRect(x: c.x - hw / 2, y: body.minY - 5, width: hw, height: 10)
        if laser {
            let barrel = CGRect(x: c.x - 3, y: hump.minY - 8, width: 6, height: 10)
            ctx.fill(Path(roundedRect: barrel, cornerRadius: 2), with: .color(laserColorDark))
            ctx.fill(Path(roundedRect: CGRect(x: barrel.minX, y: barrel.minY, width: 6, height: 3), cornerRadius: 1.5), with: .color(.white.opacity(0.9)))
            ctx.stroke(Path(roundedRect: barrel, cornerRadius: 2), with: .color(ink), lineWidth: 1)
        }
        ctx.fill(Path(roundedRect: hump, cornerRadius: 5),
                 with: .linearGradient(Gradient(colors: [.white, Color(red: 0.72, green: 0.74, blue: 0.78), Color(red: 0.42, green: 0.44, blue: 0.48)]),
                                       startPoint: CGPoint(x: c.x, y: hump.minY), endPoint: CGPoint(x: c.x, y: hump.maxY)))
        ctx.stroke(Path(roundedRect: hump, cornerRadius: 5), with: .color(ink.opacity(0.7)), lineWidth: 1)
        if laser {
            // The cannon's red eye on the hump.
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: hump.minY + 2, width: 6, height: 6)), with: .color(Self.laser))
        }
    }

    static let laserColorDark = Color(red: 0.7, green: 0.08, blue: 0.12)
}

/// Yellow-and-black hazard stripes round the top and sides of the field (the bottom is open).
private struct BBFrame: View, Equatable {
    let size: CGSize
    let t: CGFloat

    var body: some View {
        Canvas { ctx, s in
            let bands = [CGRect(x: 0, y: 0, width: s.width, height: t),
                         CGRect(x: 0, y: 0, width: t, height: s.height),
                         CGRect(x: s.width - t, y: 0, width: t, height: s.height)]
            var clip = Path()
            for b in bands { clip.addRect(b) }
            var g = ctx
            g.clip(to: clip)
            g.fill(clip, with: .color(BBArt.hazard))
            var stripes = Path()
            var x: CGFloat = -s.height
            while x < s.width + s.height {
                stripes.move(to: CGPoint(x: x, y: s.height))
                stripes.addLine(to: CGPoint(x: x + s.height, y: 0))
                x += t * 1.25
            }
            g.stroke(stripes, with: .color(BBArt.ink), lineWidth: t * 0.55)
            // Shade toward the field, a dark inner lip, and a light outer edge.
            g.fill(clip, with: .linearGradient(Gradient(colors: [.white.opacity(0.18), .clear, .black.opacity(0.18)]),
                                              startPoint: .zero, endPoint: CGPoint(x: t, y: t)))
            var lip = Path()
            lip.move(to: CGPoint(x: t, y: s.height)); lip.addLine(to: CGPoint(x: t, y: t))
            lip.addLine(to: CGPoint(x: s.width - t, y: t)); lip.addLine(to: CGPoint(x: s.width - t, y: s.height))
            ctx.stroke(lip, with: .color(.black.opacity(0.6)), lineWidth: 1.5)
        }
        .allowsHitTesting(false)
    }
}

/// Brushed grey floor plates with seams and rivets (static).
private struct BBFloor: View, Equatable {
    let size: CGSize

    var body: some View {
        Canvas { ctx, s in
            let full = CGRect(origin: .zero, size: s)
            ctx.fill(Path(full), with: .linearGradient(Gradient(colors: [Color(red: 0.86, green: 0.87, blue: 0.89), Color(red: 0.74, green: 0.76, blue: 0.79)]),
                                                       startPoint: .zero, endPoint: CGPoint(x: s.width * 0.3, y: s.height)))
            // Rows of plates of uneven widths.
            let rowH = max(40, s.height * 0.16)
            var y: CGFloat = -rowH * 0.3
            var row = 0
            while y < s.height {
                var x: CGFloat = -BBArt.hash(Double(row) * 3.1) * s.width * 0.3
                var k = 0
                while x < s.width {
                    let pw = s.width * (0.28 + 0.34 * BBArt.hash(Double(row * 13 + k) * 1.7))
                    let plate = CGRect(x: x + 2, y: y + 2, width: pw - 4, height: rowH - 4)
                    let shade = 0.03 * Double(BBArt.hash(Double(row * 7 + k * 3) + 0.5)) - 0.015
                    ctx.fill(Path(roundedRect: plate, cornerRadius: 3), with: .color(shade > 0 ? .white.opacity(shade * 6) : .black.opacity(-shade * 4)))
                    ctx.stroke(Path(roundedRect: plate.offsetBy(dx: 1, dy: 1), cornerRadius: 3), with: .color(.white.opacity(0.5)), lineWidth: 1)
                    ctx.stroke(Path(roundedRect: plate, cornerRadius: 3), with: .color(Color(red: 0.55, green: 0.57, blue: 0.6)), lineWidth: 1)
                    for (rx, ry) in [(plate.minX + 5, plate.minY + 5), (plate.maxX - 5, plate.minY + 5), (plate.minX + 5, plate.maxY - 5), (plate.maxX - 5, plate.maxY - 5)] {
                        ctx.fill(Path(ellipseIn: CGRect(x: rx - 1.6, y: ry - 1.6, width: 3.2, height: 3.2)), with: .color(Color(red: 0.6, green: 0.62, blue: 0.65)))
                        ctx.fill(Path(ellipseIn: CGRect(x: rx - 1.1, y: ry - 1.3, width: 1.6, height: 1.6)), with: .color(.white.opacity(0.7)))
                    }
                    x += pw; k += 1
                }
                y += rowH; row += 1
            }
            // A soft darkening toward the open bottom.
            ctx.fill(Path(full), with: .linearGradient(Gradient(colors: [.clear, .black.opacity(0.18)]),
                                                       startPoint: CGPoint(x: 0, y: s.height * 0.55), endPoint: CGPoint(x: 0, y: s.height)))
        }
        .allowsHitTesting(false)
    }
}

/// The wall of bricks; redrawn only when a brick breaks.
private struct BBBricks: View, Equatable {
    let bricks: [BBBrickSnap]
    let size: CGSize

    var body: some View {
        Canvas { ctx, s in
            for b in bricks {
                let r = CGRect(x: (b.cx - b.hw) * s.width, y: (b.cy - b.hh) * s.height, width: b.hw * 2 * s.width, height: b.hh * 2 * s.height)
                BBArt.brick(ctx, r, b.color)
            }
        }
        .allowsHitTesting(false)
    }
}

/// A little red brick for the HUD.
private struct BBBrickIcon: View {
    var body: some View {
        Canvas { ctx, s in
            BBArt.brick(ctx, CGRect(origin: .zero, size: s).insetBy(dx: 1, dy: 1), Color(red: 0.84, green: 0.2, blue: 0.18))
        }
    }
}
