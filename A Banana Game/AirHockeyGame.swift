//
//  AirHockeyGame.swift
//  A Banana Game
//
//  Air Hockey. A vertical table: drag your paddle in the bottom half, the puck
//  bounces off walls and paddles, and the AI defends + attacks up top. First to
//  N goals wins; the AI reaching N (or the clock running out) fails you. Drag
//  game → locksFeed.
//

import SwiftUI

enum AirHockeyGame {
    static let definition = GameDefinition(
        id: "air-hockey", title: "Air Hockey", emoji: "🍌",
        genre: .reflex, levelCount: 7, locksFeed: true,
        manual: GameManual(
            bullets: [
                "Drag your paddle in the bottom half of the table to strike the puck.",
                "Flick it to launch the puck into the AI's goal up top.",
                "First to the target number of goals wins.",
                "If the AI gets there first, or the clock runs out, you're back to level 1.",
            ],
            bulletsVI: [
                "Kéo vợt của bạn ở nửa dưới bàn để đánh quả bóng.",
                "Búng nó để phóng bóng vào khung thành AI phía trên.",
                "Ai đạt đủ số bàn thắng mục tiêu trước sẽ thắng.",
                "Nếu AI đạt trước, hoặc hết giờ, bạn sẽ về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(AirHockeyView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct AirHockeyView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    // Table geometry (fractions).
    private let puckRFrac: CGFloat = 0.035
    // Your own goal (bottom) stays narrow so the AI has a hard time scoring…
    private let mouthL: CGFloat = 0.3
    private let mouthR: CGFloat = 0.7
    // The AI's goal line (top) is the same width as yours.
    private let aiMouthL: CGFloat = 0.3
    private let aiMouthR: CGFloat = 0.7
    /// Goals needed rises with the level: L1 first-to-1 … L7 first-to-7.
    private var goalsToWin: Int { level }

    // MARK: Difficulty
    private var playerPaddleRFrac: CGFloat { max(0.06, 0.105 - CGFloat(level) * 0.005) }
    private let aiPaddleRFrac: CGFloat = 0.075
    private var baseSpeed: CGFloat { 0.48 + CGFloat(level) * 0.06 }
    // Raised so the extra force from your paddle actually launches the puck fast
    // toward the AI goal instead of being clamped away.
    private var maxSpeed: CGFloat { 1.35 + CGFloat(level) * 0.14 }
    private var aiSpeed: CGFloat { 0.26 + CGFloat(level) * 0.05 }
    // Longer clock on higher levels, since they need more goals to win.
    // Generous per-goal budget so it never feels like a race against the clock.
    private var timeLimit: Double { 18.0 + Double(level) * 9.0 }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var puck = CGPoint(x: 0.5, y: 0.5)
    @State private var vel = CGVector(dx: 0, dy: 0.5)
    @State private var playerPaddle = CGPoint(x: 0.5, y: 0.82)
    @State private var lastPlayer = CGPoint(x: 0.5, y: 0.82)
    @State private var playerVel = CGVector(dx: 0, dy: 0)
    @State private var aiPaddle = CGPoint(x: 0.5, y: 0.12)
    @State private var playerScore = 0
    @State private var aiScore = 0
    @State private var timeLeft = 0.0
    @State private var loopTask: Task<Void, Never>?
    @State private var serveCooldown = 0.0
    // Brief per-paddle cooldowns so a paddle can't re-hit the puck every frame
    // (which used to pin the puck in a corner).
    @State private var playerHitCD = 0.0
    @State private var aiHitCD = 0.0

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let pR = playerPaddleRFrac * size.width
            ZStack {
                HockeyTable(size: size, mouthL: aiMouthL, mouthR: aiMouthR, bottomL: mouthL, bottomR: mouthR).equatable()
                Canvas { ctx, s in drawPlay(ctx, s) }
                // Demo: a finger riding your mallet shows the drag.
                if isDemo {
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 3)
                        .position(x: playerPaddle.x * size.width + pR * 0.7,
                                  y: playerPaddle.y * size.height + pR * 0.9)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard phase == .play else { return }
                        let fx = min(1 - playerPaddleRFrac, max(playerPaddleRFrac, value.location.x / size.width))
                        // Player paddle is confined to the bottom half.
                        let fy = min(1 - playerPaddleRFrac, max(0.52, value.location.y / size.height))
                        playerPaddle = CGPoint(x: fx, y: fy)
                    }
            )
        }
        // The rail sits outside the playing surface, so the puck's walls stay exactly where they were.
        .padding(isDemo ? 7 : 9)
        .background(HockeyRail())
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 14 : 26))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
    }

    /// Scores, the clock, mallets and the puck (with a speed streak), in one Canvas.
    private func drawPlay(_ ctx: GraphicsContext, _ s: CGSize) {
        let w = s.width, h = s.height
        guard w > 1, h > 1 else { return }
        // Big faint score digits in each half, arcade-style.
        HockeyArt.score(ctx, aiScore, label: L("AI", "MÁY"), at: CGPoint(x: w * 0.8, y: h * 0.3), size: w * 0.2)
        HockeyArt.score(ctx, playerScore, label: L("YOU", "BẠN"), at: CGPoint(x: w * 0.8, y: h * 0.7), size: w * 0.2)
        if !isDemo {
            HockeyArt.clock(ctx, seconds: Int(ceil(timeLeft)), at: CGPoint(x: w * 0.12, y: h * 0.5), low: timeLeft < timeLimit * 0.3)
        }
        let puckP = CGPoint(x: puck.x * w, y: puck.y * h)
        let puckR = puckRFrac * w
        HockeyArt.puck(ctx, at: puckP, r: puckR, vel: CGVector(dx: vel.dx * w, dy: vel.dy * h))
        HockeyArt.mallet(ctx, at: CGPoint(x: aiPaddle.x * w, y: aiPaddle.y * h), r: aiPaddleRFrac * w,
                         color: Color(red: 0.9, green: 0.16, blue: 0.16))
        HockeyArt.mallet(ctx, at: CGPoint(x: playerPaddle.x * w, y: playerPaddle.y * h), r: playerPaddleRFrac * w,
                         color: BananaTheme.banana)
    }
    // MARK: - Flow

    private func run() async {
        phase = .play
        playerScore = 0; aiScore = 0
        serve(toward: Bool.random() ? 1 : -1)
        timeLeft = timeLimit
        let start = Date()
        var last = start
        loopTask = Task {
            while !Task.isCancelled && phase == .play {
                try? await Task.sleep(for: .seconds(0.016))
                let now = Date()
                let dt = CGFloat(min(0.05, now.timeIntervalSince(last)))
                last = now
                timeLeft = max(0, timeLimit - now.timeIntervalSince(start))
                step(dt: dt)
                if timeLeft <= 0 { fail() }
            }
        }
    }

    // MARK: - Demo (live manual clip)
    // Level 1 is first-to-1. The demo serves at a fixed angle and drives YOUR paddle on a fixed
    // script (glide to a guard spot, then a sharp upward flick at t = 1.0s) through the real
    // `step`, stepped at a fixed 1/60s so every loop is bit-identical. Tuned offline against a
    // port of `step`: the serve glances off the paddle into the right wall, the rebound meets
    // the flick, and the puck is driven up-left past the (real, unassisted) AI into its goal.
    private static let demoAngle: CGFloat = 0.35
    private static let demoStart = CGPoint(x: 0.5, y: 0.82)
    private static let demoGuard = CGPoint(x: 0.53, y: 0.88)
    private static let demoFlick = CGVector(dx: 0.05, dy: -0.3)
    private static let demoStrikeAt = 1.0
    private static let demoFlickDur = 0.24

    /// Scripted paddle position at demo time `t` (eased glide → hold → ease-out flick).
    private func demoPaddle(at t: Double) -> CGPoint {
        let s = Self.demoStart, w = Self.demoGuard
        if t < Self.demoStrikeAt - 0.35 {
            var f = min(1, t / max(0.01, Self.demoStrikeAt - 0.35)); f = f * f * (3 - 2 * f)
            return CGPoint(x: s.x + (w.x - s.x) * f, y: s.y + (w.y - s.y) * f)
        }
        if t < Self.demoStrikeAt { return w }
        var f = min(1, (t - Self.demoStrikeAt) / Self.demoFlickDur)
        f = 1 - (1 - f) * (1 - f)
        let x = w.x + Self.demoFlick.dx * f, y = w.y + Self.demoFlick.dy * f
        return CGPoint(x: min(1 - playerPaddleRFrac, max(playerPaddleRFrac, x)),
                       y: min(1 - playerPaddleRFrac, max(0.52, y)))
    }

    private func runDemo() async {
        let dt: CGFloat = 1.0 / 60.0
        while !Task.isCancelled {
            phase = .play
            playerScore = 0; aiScore = 0
            playerPaddle = Self.demoStart; lastPlayer = Self.demoStart; playerVel = .zero
            aiPaddle = CGPoint(x: 0.5, y: 0.12)
            playerHitCD = 0; aiHitCD = 0
            puck = CGPoint(x: 0.5, y: 0.5)
            vel = CGVector(dx: baseSpeed * sin(Self.demoAngle), dy: baseSpeed * abs(cos(Self.demoAngle)))
            serveCooldown = 0.5
            timeLeft = timeLimit
            try? await Task.sleep(for: .seconds(0.5))
            var t = 0.0
            // Real physics; the goal calls the real win() (onWin is a no-op) and ends the rally.
            while !Task.isCancelled && phase == .play && t < 4.0 {
                t += Double(dt)
                playerPaddle = demoPaddle(at: t)
                step(dt: dt)
                try? await Task.sleep(for: .seconds(0.016))
            }
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    /// Serve the puck from center. `dir` = +1 toward the player (down), -1 toward AI.
    private func serve(toward dir: CGFloat) {
        puck = CGPoint(x: 0.5, y: 0.5)
        let angle = CGFloat.random(in: -0.5...0.5)
        vel = CGVector(dx: baseSpeed * sin(angle), dy: baseSpeed * dir * abs(cos(angle)))
        serveCooldown = 0.5
    }

    private func step(dt: CGFloat) {
        if serveCooldown > 0 { serveCooldown -= Double(dt) }
        if playerHitCD > 0 { playerHitCD -= Double(dt) }
        if aiHitCD > 0 { aiHitCD -= Double(dt) }

        // Player paddle velocity (for imparting momentum to the puck).
        playerVel = CGVector(dx: (playerPaddle.x - lastPlayer.x) / dt,
                             dy: (playerPaddle.y - lastPlayer.y) / dt)
        lastPlayer = playerPaddle

        // AI: mostly guard its goal; only nudge forward when the puck comes up
        // slowly. Kept to a central x band so it can't pin the puck in a corner.
        let advancing = puck.y < 0.32 && vel.dy < 0
        let aiTargetY: CGFloat = advancing ? min(0.34, puck.y) : 0.13
        let aiTargetX = min(0.75, max(0.25, puck.x))
        let aiStep = aiSpeed * dt
        aiPaddle.x += max(-aiStep, min(aiStep, aiTargetX - aiPaddle.x))
        aiPaddle.y += max(-aiStep, min(aiStep, aiTargetY - aiPaddle.y))

        // Integrate puck.
        var p = puck
        p.x += vel.dx * dt
        p.y += vel.dy * dt

        // Side walls.
        if p.x < puckRFrac { p.x = puckRFrac; vel.dx = abs(vel.dx) }
        if p.x > 1 - puckRFrac { p.x = 1 - puckRFrac; vel.dx = -abs(vel.dx) }

        // Top (AI goal) — you score the instant the puck *touches* the wide yellow
        // line (no need to fully cross it), so you have a big, easy target.
        if p.y < puckRFrac {
            if p.x > aiMouthL && p.x < aiMouthR {
                puck = p; scored(player: true); return
            } else {
                p.y = puckRFrac; vel.dy = abs(vel.dy)
            }
        }
        // Bottom (your goal) — the AI must fully cross the narrow mouth to score.
        if p.y > 1 - puckRFrac {
            if p.x > mouthL && p.x < mouthR {
                if p.y > 1 { puck = p; scored(player: false); return }
            } else {
                p.y = 1 - puckRFrac; vel.dy = -abs(vel.dy)
            }
        }

        puck = p
        collide(with: playerPaddle, radius: playerPaddleRFrac, paddleVel: playerVel, isAI: false)
        collide(with: aiPaddle, radius: aiPaddleRFrac, paddleVel: .zero, isAI: true)
        clampSpeed()
    }

    private func collide(with paddle: CGPoint, radius: CGFloat, paddleVel: CGVector, isAI: Bool) {
        if isAI ? (aiHitCD > 0) : (playerHitCD > 0) { return }
        let minD = puckRFrac + radius
        let dx = puck.x - paddle.x
        let dy = puck.y - paddle.y
        let dist = hypot(dx, dy)
        guard dist < minD && dist > 0.0001 else { return }
        let nx = dx / dist, ny = dy / dist
        // Push the puck clear of the paddle.
        puck = CGPoint(x: paddle.x + nx * minD, y: paddle.y + ny * minD)
        // Reflect velocity along the collision normal (only if approaching).
        let dot = vel.dx * nx + vel.dy * ny
        if dot < 0 {
            vel.dx -= 2 * dot * nx
            vel.dy -= 2 * dot * ny
        }
        // Impart a share of the paddle's motion — your swing transfers much more
        // force than the AI's, so a quick flick really launches the puck.
        let velShare: CGFloat = isAI ? 0.5 : 1.1
        vel.dx += paddleVel.dx * velShare
        vel.dy += paddleVel.dy * velShare
        // Your paddle is bouncy: the puck gains speed on contact instead of
        // bleeding it, so you can clear it away easily (the AI stays neutral).
        let bounce: CGFloat = isAI ? 1.0 : 1.7
        vel.dx *= bounce
        vel.dy *= bounce
        // Guarantee the puck moves away from the paddle (prevents corner pinning),
        // with a much stronger kick off the player's paddle.
        let push = baseSpeed * (isAI ? 0.2 : 0.95)
        vel.dx += nx * push
        vel.dy += ny * push
        if isAI { aiHitCD = 0.15 } else { playerHitCD = 0.15 }
    }

    private func clampSpeed() {
        var speed = hypot(vel.dx, vel.dy)
        if speed < baseSpeed * 0.7 && speed > 0.0001 {
            let s = baseSpeed * 0.7 / speed
            vel.dx *= s; vel.dy *= s; speed = baseSpeed * 0.7
        }
        if speed > maxSpeed {
            let s = maxSpeed / speed
            vel.dx *= s; vel.dy *= s
        }
    }

    private func scored(player: Bool) {
        if player { playerScore += 1; Haptics.tap(); SoundManager.shared.tap() }
        else { aiScore += 1; SoundManager.shared.error() }

        if playerScore >= goalsToWin { win(); return }
        if aiScore >= goalsToWin { fail(); return }
        // Serve toward whoever was just scored on.
        serve(toward: player ? -1 : 1)
    }

    private func win() {
        guard phase != .done else { return }
        phase = .done
        loopTask?.cancel()
        Haptics.tap(); SoundManager.shared.tap()
        onWin()
    }

    private func fail() {
        guard phase != .done else { return }
        phase = .done
        loopTask?.cancel()
        SoundManager.shared.error()
        onFail()
    }
}

// MARK: - Arcade table art

private enum HockeyArt {
    private static func disc(_ p: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }

    /// A mallet ("striker"): a coloured base, a raised handle knob and a soft shadow.
    static func mallet(_ ctx: GraphicsContext, at p: CGPoint, r: CGFloat, color: Color) {
        ctx.fill(disc(CGPoint(x: p.x + r * 0.12, y: p.y + r * 0.2), r), with: .color(.black.opacity(0.28)))
        ctx.fill(disc(p, r), with: .radialGradient(Gradient(colors: [color.lit(0.35), color, color.shade(0.35)]),
                                                  center: CGPoint(x: p.x - r * 0.3, y: p.y - r * 0.35), startRadius: 0, endRadius: r * 1.3))
        ctx.stroke(disc(p, r), with: .color(color.shade(0.55)), lineWidth: max(1, r * 0.06))
        ctx.stroke(disc(p, r * 0.78), with: .color(color.shade(0.25).opacity(0.8)), lineWidth: max(1, r * 0.05))
        ctx.fill(disc(CGPoint(x: p.x + r * 0.05, y: p.y + r * 0.08), r * 0.5), with: .color(.black.opacity(0.25)))
        ctx.fill(disc(p, r * 0.46), with: .radialGradient(Gradient(colors: [color.lit(0.55), color.lit(0.1), color.shade(0.3)]),
                                                         center: CGPoint(x: p.x - r * 0.15, y: p.y - r * 0.2), startRadius: 0, endRadius: r * 0.55))
        ctx.fill(disc(CGPoint(x: p.x - r * 0.16, y: p.y - r * 0.18), r * 0.14), with: .color(.white.opacity(0.75)))
    }

    /// The puck: a black disc with a white ring, streaking when it moves fast.
    static func puck(_ ctx: GraphicsContext, at p: CGPoint, r: CGFloat, vel: CGVector) {
        let speed = hypot(vel.dx, vel.dy)
        if speed > 1 {
            let tail = CGPoint(x: p.x - vel.dx * 0.07, y: p.y - vel.dy * 0.07)
            var streak = Path()
            streak.move(to: p); streak.addLine(to: tail)
            ctx.stroke(streak, with: .linearGradient(Gradient(colors: [Color(white: 0.2).opacity(0.35), .clear]),
                                                     startPoint: p, endPoint: tail),
                       style: StrokeStyle(lineWidth: r * 1.6, lineCap: .round))
        }
        ctx.fill(disc(CGPoint(x: p.x + r * 0.12, y: p.y + r * 0.2), r), with: .color(.black.opacity(0.25)))
        ctx.fill(disc(p, r), with: .radialGradient(Gradient(colors: [Color(white: 0.3), Color(white: 0.08)]),
                                                  center: CGPoint(x: p.x - r * 0.3, y: p.y - r * 0.3), startRadius: 0, endRadius: r * 1.2))
        ctx.stroke(disc(p, r * 0.68), with: .color(.white.opacity(0.7)), lineWidth: max(1, r * 0.12))
    }

    /// A big faint score digit with its label, printed on the table.
    static func score(_ ctx: GraphicsContext, _ value: Int, label: String, at p: CGPoint, size: CGFloat) {
        let ink = Color(red: 0.12, green: 0.25, blue: 0.55).opacity(0.28)
        ctx.draw(ctx.resolve(Text("\(value)").font(.system(size: size, weight: .black, design: .rounded)).foregroundStyle(ink)), at: p)
        ctx.draw(ctx.resolve(Text(label).font(.system(size: size * 0.2, weight: .heavy, design: .rounded)).foregroundStyle(ink)),
                 at: CGPoint(x: p.x, y: p.y + size * 0.62))
    }

    /// A small red-LED countdown on the centre line.
    static func clock(_ ctx: GraphicsContext, seconds: Int, at p: CGPoint, low: Bool) {
        let box = CGRect(x: p.x - 24, y: p.y - 14, width: 48, height: 28)
        ctx.fill(Path(roundedRect: box, cornerRadius: 6), with: .color(Color(red: 0.08, green: 0.1, blue: 0.16)))
        ctx.stroke(Path(roundedRect: box, cornerRadius: 6), with: .color(Color(red: 0.3, green: 0.35, blue: 0.45)), lineWidth: 1.5)
        let led = low ? Color(red: 1, green: 0.25, blue: 0.2) : Color(red: 1, green: 0.62, blue: 0.2)
        let t = Text(String(format: "%02d", max(0, seconds))).font(.system(size: 18, weight: .bold, design: .monospaced))
        var g = ctx
        g.addFilter(.blur(radius: 2.5))
        g.draw(g.resolve(t.foregroundStyle(led)), at: p)
        ctx.draw(ctx.resolve(t.foregroundStyle(led.lit(0.3))), at: p)
    }
}

/// The navy aluminium rail round the table.
private struct HockeyRail: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.2, green: 0.26, blue: 0.4), Color(red: 0.08, green: 0.11, blue: 0.2)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// The static playing surface: icy white with a grid of air holes, red centre line and circle, blue
/// lines, goal creases and the dark goal slots.
private struct HockeyTable: View, Equatable {
    let size: CGSize
    let mouthL: CGFloat, mouthR: CGFloat
    let bottomL: CGFloat, bottomR: CGFloat

    var body: some View {
        Canvas { ctx, s in
            let w = s.width, h = s.height
            ctx.fill(Path(CGRect(origin: .zero, size: s)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.93, green: 0.97, blue: 1), Color(red: 0.84, green: 0.91, blue: 0.98)]),
                                           startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
            // Air holes.
            let step = max(12, w / 24)
            var holes = Path()
            var y = step / 2
            while y < h {
                var x = step / 2
                while x < w {
                    holes.addEllipse(in: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8))
                    x += step
                }
                y += step
            }
            ctx.fill(holes, with: .color(Color(red: 0.55, green: 0.65, blue: 0.78).opacity(0.7)))
            let red = Color(red: 0.88, green: 0.18, blue: 0.2), blue = Color(red: 0.2, green: 0.42, blue: 0.85)
            // Centre line and circle.
            ctx.fill(Path(CGRect(x: 0, y: h / 2 - 2, width: w, height: 4)), with: .color(red.opacity(0.85)))
            let cr = w * 0.16
            ctx.stroke(Path(ellipseIn: CGRect(x: w / 2 - cr, y: h / 2 - cr, width: cr * 2, height: cr * 2)), with: .color(red.opacity(0.85)), lineWidth: 3)
            ctx.fill(Path(ellipseIn: CGRect(x: w / 2 - 5, y: h / 2 - 5, width: 10, height: 10)), with: .color(red))
            // Blue lines.
            for fy in [0.3, 0.7] as [CGFloat] {
                ctx.fill(Path(CGRect(x: 0, y: h * fy - 2, width: w, height: 4)), with: .color(blue.opacity(0.75)))
            }
            // Goal creases and slots.
            for (top, l, r) in [(true, mouthL, mouthR), (false, bottomL, bottomR)] {
                let gw = (r - l) * w, gx = l * w
                let cy: CGFloat = top ? 0 : h
                var crease = Path()
                crease.addArc(center: CGPoint(x: gx + gw / 2, y: cy), radius: gw * 0.6,
                              startAngle: .degrees(top ? 0 : 180), endAngle: .degrees(top ? 180 : 360), clockwise: false)
                ctx.stroke(crease, with: .color(blue.opacity(0.75)), lineWidth: 3)
                ctx.fill(Path(roundedRect: CGRect(x: gx, y: top ? -6 : h - 6, width: gw, height: 12), cornerRadius: 5),
                         with: .color(Color(red: 0.05, green: 0.06, blue: 0.1)))
            }
        }
        .allowsHitTesting(false)
    }
}
