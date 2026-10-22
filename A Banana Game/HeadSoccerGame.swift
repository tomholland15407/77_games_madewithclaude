//
//  HeadSoccerGame.swift
//  A Banana Game
//
//  Head Soccer. Two big-headed banana players on a small pitch. Hold LEFT / RIGHT
//  to run, tap JUMP to leap and power-kick — your head auto-heads any ball it
//  touches. Score in the AI's goal (right); it defends and attacks your goal (left).
//  First to `level` goals wins; the AI reaching it first, or the clock, fails you.
//  Buttons only → no feed lock.
//
//  Drawn like Head Soccer: a floodlit stadium (stands and crowd, ad boards), a striped pitch with
//  netted goals, big cartoon heads with one boot each (a banana for you, a tomato for the AI), a
//  spinning black-and-white ball, the match scoreboard up top, arrow keys left and JUMP right.
//

import SwiftUI

enum HeadSoccerGame {
    static let definition = GameDefinition(
        id: "head-soccer", title: "Header Duel", emoji: "🍌",
        genre: .reflex, levelCount: 7,
        manual: GameManual(
            bullets: [
                "Hold LEFT / RIGHT to run and tap JUMP to leap.",
                "Your big head auto-heads any ball it touches.",
                "Score in the AI's goal on the right while defending yours on the left.",
                "Reach the target goals first to win; if the AI does, or time runs out, you're back to level 1.",
            ],
            bulletsVI: [
                "Giữ TRÁI / PHẢI để chạy và chạm NHẢY để bật lên.",
                "Cái đầu to của bạn tự đánh đầu mọi quả bóng nó chạm phải.",
                "Ghi bàn vào khung thành AI bên phải trong khi bảo vệ khung của bạn bên trái.",
                "Đạt đủ bàn thắng trước để thắng; nếu AI đạt trước, hoặc hết giờ, bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(HeadSoccerView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct HeadSoccerView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    // Pitch geometry (fractions).
    private let ground: CGFloat = 0.80
    private let ceiling: CGFloat = 0.14
    private let headR: CGFloat = 0.09
    private let ballR: CGFloat = 0.042
    private let goalTop: CGFloat = 0.60      // goal mouth spans goalTop…ground at each edge
    private let goalW: CGFloat = 0.05        // horizontal depth of each goal mouth

    // MARK: Difficulty
    private var goalsToWin: Int { level }
    private var aiSpeed: CGFloat { 0.24 + CGFloat(level) * 0.05 }
    private var aiJumpChance: Double { 0.01 + Double(level) * 0.006 }
    private var ballSpeedCap: CGFloat { 1.0 + CGFloat(level) * 0.12 }
    private var timeLimit: Double {
        // Base clock grows with level (higher levels need more goals). From level 3
        // up we add an extra cushion so the longer goal targets stay achievable.
        let base = 10.0 + Double(level) * 4.0
        let cushion = level >= 3 ? Double(level - 2) * 6.0 : 0
        return base + cushion
    }

    private let gravity: CGFloat = 2.4
    private let moveSpeed: CGFloat = 0.5
    private let jumpV: CGFloat = 1.15

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var ball = CGPoint(x: 0.5, y: 0.4)
    @State private var ballVel = CGVector(dx: 0.3, dy: 0)
    @State private var player = CGPoint(x: 0.25, y: 0.80)
    @State private var playerVY: CGFloat = 0
    @State private var ai = CGPoint(x: 0.75, y: 0.80)
    @State private var aiVY: CGFloat = 0
    @State private var moveDir: CGFloat = 0
    @State private var playerScore = 0
    @State private var aiScore = 0
    @State private var timeLeft = 0.0
    @State private var loopTask: Task<Void, Never>?
    @State private var serveCD = 0.0
    @State private var demoJump = false     // demo: JUMP visibly pressed

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                Stadium(ground: ground, goalTop: goalTop, goalW: goalW).equatable()

                scoreboard
                    .frame(width: size.width)
                    .position(x: size.width / 2, y: size.height * 0.065)

                // Heads, boots and the ball, drawn together every frame.
                Canvas { ctx, s in
                    SoccerArt.player(ctx, head: CGPoint(x: player.x * s.width, y: player.y * s.height), r: headR * s.width,
                                     banana: true, facing: 1)
                    SoccerArt.player(ctx, head: CGPoint(x: ai.x * s.width, y: ai.y * s.height), r: headR * s.width,
                                     banana: false, facing: -1)
                    SoccerArt.ball(ctx, at: CGPoint(x: ball.x * s.width, y: ball.y * s.height), r: ballR * s.width,
                                   spin: Double(ball.x * s.width / max(1, ballR * s.width)))
                    SoccerArt.goalFront(ctx, s, goalTop: goalTop, ground: ground, goalW: goalW)
                }
                .allowsHitTesting(false)

                controls
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
    }

    /// The match scoreboard: both heads and the score, the clock, and the target.
    private var scoreboard: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Canvas { ctx, s in SoccerArt.face(ctx, c: CGPoint(x: s.width / 2, y: s.height / 2), r: s.width * 0.42, banana: true, facing: 1) }
                    .frame(width: 22, height: 22)
                Text(L("YOU", "BẠN")).font(.system(size: 11, weight: .black)).foregroundStyle(BananaTheme.banana)
                Text("\(playerScore) : \(aiScore)")
                    .font(.system(size: isDemo ? 18 : 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(red: 0.1, green: 0.12, blue: 0.2)))
                Text(L("AI", "MÁY")).font(.system(size: 11, weight: .black)).foregroundStyle(Color(red: 1, green: 0.5, blue: 0.45))
                Canvas { ctx, s in SoccerArt.face(ctx, c: CGPoint(x: s.width / 2, y: s.height / 2), r: s.width * 0.42, banana: false, facing: -1) }
                    .frame(width: 22, height: 22)
            }
            HStack(spacing: 8) {
                if !isDemo {
                    Text(clockText)
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundStyle(timeLeft < 5 ? Color(red: 1, green: 0.4, blue: 0.35) : Color(red: 1, green: 0.85, blue: 0.3))
                }
                Text(L("first to \(goalsToWin)", "về \(goalsToWin) trước"))
                    .font(.system(size: 10, weight: .heavy)).foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [Color(red: 0.2, green: 0.26, blue: 0.42), Color(red: 0.1, green: 0.13, blue: 0.24)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 0.95, green: 0.78, blue: 0.3), lineWidth: 2))
        )
    }

    private var clockText: String {
        let t = max(0, Int(timeLeft.rounded(.up)))
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    private var controls: some View {
        VStack {
            Spacer()
            HStack(spacing: isDemo ? 8 : 12) {
                holdButton("arrowtriangle.left.fill", dir: -1)
                holdButton("arrowtriangle.right.fill", dir: 1)
                Spacer()
                Button(action: jump) {
                    Text(L("JUMP", "NHẢY"))
                        .font(.system(size: isDemo ? 15 : 19, weight: .black, design: .rounded))
                        .frame(width: isDemo ? 92 : 118, height: isDemo ? 34 : 56)
                }
                .buttonStyle(FramedKeyStyle(lit: demoJump))
            }
            .padding(.horizontal, isDemo ? 10 : 16)
            // In the squat demo card the row sits flush at the bottom, clear of the heads
            // (which straddle the ground line).
            .padding(.bottom, isDemo ? 4 : 18)
        }
        // Fill the page so the Spacer pushes the row to the bottom and the ZStack's
        // .topLeading alignment doesn't pin the buttons to the left edge.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A press-and-hold move button: sets the run direction while the finger is down.
    private func holdButton(_ icon: String, dir: CGFloat) -> some View {
        let pressed = moveDir == dir
        return Image(systemName: icon)
            .font(.system(size: isDemo ? 17 : 22, weight: .black))
            .foregroundStyle(pressed ? Color(red: 1, green: 0.85, blue: 0.3) : .white)
            .frame(width: isDemo ? 58 : 76, height: isDemo ? 34 : 56)
            .background(FramedKeyFace(pressed: pressed))
            .scaleEffect(pressed ? 0.92 : 1)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if phase == .play { moveDir = dir } }
                    .onEnded { _ in if moveDir == dir { moveDir = 0 } }
            )
    }

    // MARK: - Flow

    private func run() async {
        phase = .play
        playerScore = 0; aiScore = 0
        resetPositions(serveToward: Bool.random() ? 1 : -1)
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
                if timeLeft <= 0 { fail(); break }
                step(dt: dt)
            }
        }
    }

    // MARK: - Demo (live manual clip)
    // Level 1 is first-to-1. The real sim runs at a fixed 1/60s with the AI's random jumps
    // off, so each loop is identical. Serve comes to you; you tap JUMP at 0.35s and hold ►
    // from 0.4–0.9s, meeting the dropping ball with a rising header that lobs it just over the
    // AI's head into its goal (~1.0s; found by search over a port of `step`, and robust to
    // ±2-frame timing shifts). The goal calls the real win() (onWin is a no-op).
    private func runDemo() async {
        let dt: CGFloat = 1.0 / 60.0
        while !Task.isCancelled {
            phase = .play
            playerScore = 0; aiScore = 0
            moveDir = 0; demoJump = false
            resetPositions(serveToward: -1)
            timeLeft = timeLimit
            try? await Task.sleep(for: .seconds(0.6))
            var t = 0.0, jumped = false, jumpFlash = 0.0
            while !Task.isCancelled && phase == .play && t < 6 {
                t += Double(dt)
                moveDir = (t >= 0.4 && t < 0.9) ? 1 : 0
                if !jumped && t >= 0.35 { jump(); jumped = true; jumpFlash = 0.2 }
                demoJump = jumpFlash > 0
                jumpFlash -= Double(dt)
                step(dt: dt)
                try? await Task.sleep(for: .seconds(0.016))
            }
            moveDir = 0; demoJump = false
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    private func resetPositions(serveToward dir: CGFloat) {
        player = CGPoint(x: 0.25, y: ground); playerVY = 0
        ai = CGPoint(x: 0.75, y: ground); aiVY = 0
        ball = CGPoint(x: 0.5, y: 0.35)
        ballVel = CGVector(dx: 0.25 * dir, dy: 0)
        serveCD = 0.4
    }

    private func step(dt: CGFloat) {
        if serveCD > 0 { serveCD -= Double(dt) }

        // Player horizontal (own half, but may cross a bit toward midfield).
        player.x = min(0.55, max(0.05, player.x + moveDir * moveSpeed * dt))
        applyGravity(to: &player, vy: &playerVY, dt: dt)

        // AI chases the ball; jumps sometimes when the ball is high & near.
        let aiTargetX = min(0.95, max(0.45, ball.x))
        let aiStep = aiSpeed * dt
        ai.x += max(-aiStep, min(aiStep, aiTargetX - ai.x))
        // (The demo drops the AI's coin-flip jumps so every loop replays identically.)
        if !isDemo, ai.y >= ground - 0.001, ball.y < 0.5, abs(ball.x - ai.x) < 0.18,
           Double.random(in: 0...1) < aiJumpChance { aiVY = -jumpV }
        applyGravity(to: &ai, vy: &aiVY, dt: dt)

        // Ball physics.
        ballVel.dy += gravity * dt
        var b = ball
        b.x += ballVel.dx * dt
        b.y += ballVel.dy * dt

        // Ceiling.
        if b.y < ceiling + ballR { b.y = ceiling + ballR; ballVel.dy = abs(ballVel.dy) * 0.8 }
        // Ground.
        if b.y > ground - ballR { b.y = ground - ballR; ballVel.dy = -abs(ballVel.dy) * 0.6; ballVel.dx *= 0.98 }
        // Side walls — but the goal mouths let the ball through to score.
        let inMouth = b.y > goalTop && b.y < ground
        if b.x < ballR {
            if inMouth { ball = b; scored(player: false); return }
            b.x = ballR; ballVel.dx = abs(ballVel.dx) * 0.8
        }
        if b.x > 1 - ballR {
            if inMouth { ball = b; scored(player: true); return }
            b.x = 1 - ballR; ballVel.dx = -abs(ballVel.dx) * 0.8
        }
        ball = b

        headBounce(head: player, vy: playerVY)
        headBounce(head: ai, vy: aiVY)
        clampBall()
    }

    private func applyGravity(to p: inout CGPoint, vy: inout CGFloat, dt: CGFloat) {
        vy += gravity * dt
        p.y += vy * dt
        if p.y >= ground { p.y = ground; vy = 0 }
    }

    /// Circle-circle bounce of the ball off a head, adding the head's motion.
    private func headBounce(head: CGPoint, vy: CGFloat) {
        let minD = ballR + headR
        let dx = ball.x - head.x
        let dy = ball.y - head.y
        let dist = hypot(dx, dy)
        guard dist < minD && dist > 0.0001 else { return }
        let nx = dx / dist, ny = dy / dist
        ball = CGPoint(x: head.x + nx * minD, y: head.y + ny * minD)
        let dot = ballVel.dx * nx + ballVel.dy * ny
        if dot < 0 {
            ballVel.dx -= 2 * dot * nx
            ballVel.dy -= 2 * dot * ny
        }
        // Kick outward, plus extra lift if the head is jumping (moving up).
        let kick: CGFloat = 0.5
        ballVel.dx += nx * kick
        ballVel.dy += ny * kick + min(0, vy) * 0.6
        SoundManager.shared.tap()
    }

    private func clampBall() {
        let speed = hypot(ballVel.dx, ballVel.dy)
        if speed > ballSpeedCap {
            let s = ballSpeedCap / speed
            ballVel.dx *= s; ballVel.dy *= s
        }
    }

    private func jump() {
        guard phase == .play, player.y >= ground - 0.001 else { return }
        playerVY = -jumpV
        SoundManager.shared.tap(); Haptics.tap()
    }

    private func scored(player who: Bool) {
        if who { playerScore += 1; Haptics.tap(); SoundManager.shared.tap() }
        else { aiScore += 1; SoundManager.shared.error() }
        if playerScore >= goalsToWin { win(); return }
        if aiScore >= goalsToWin { fail(); return }
        resetPositions(serveToward: who ? -1 : 1)
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

// MARK: - Head Soccer art

private enum SoccerArt {
    static let ink = Color(red: 0.1, green: 0.07, blue: 0.08)

    static func hash(_ n: Double) -> CGFloat {
        let v: Double = sin(n * 12.9898) * 43758.5453
        return CGFloat(v - floor(v))
    }

    /// A big head (banana or tomato) with one boot under it.
    static func player(_ ctx: GraphicsContext, head c: CGPoint, r: CGFloat, banana: Bool, facing: CGFloat) {
        // Boot on the grass in front of the ball's line.
        let bootY = c.y + r * 0.95
        var boot = Path()
        boot.move(to: CGPoint(x: c.x - facing * r * 0.35, y: bootY - r * 0.28))
        boot.addLine(to: CGPoint(x: c.x + facing * r * 0.05, y: bootY - r * 0.28))
        boot.addQuadCurve(to: CGPoint(x: c.x + facing * r * 0.55, y: bootY + r * 0.02), control: CGPoint(x: c.x + facing * r * 0.5, y: bootY - r * 0.26))
        boot.addLine(to: CGPoint(x: c.x + facing * r * 0.55, y: bootY + r * 0.12))
        boot.addLine(to: CGPoint(x: c.x - facing * r * 0.38, y: bootY + r * 0.12))
        boot.closeSubpath()
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.6, y: bootY + r * 0.06, width: r * 1.2, height: r * 0.2)), with: .color(.black.opacity(0.25)))
        ctx.fill(boot, with: .color(Color(red: 0.12, green: 0.12, blue: 0.16)))
        var stripes = Path()
        for k in 0..<3 {
            let x = c.x - facing * r * (0.18 - CGFloat(k) * 0.12)
            stripes.move(to: CGPoint(x: x, y: bootY - r * 0.24)); stripes.addLine(to: CGPoint(x: x + facing * r * 0.06, y: bootY + r * 0.02))
        }
        ctx.stroke(stripes, with: .color(.white), lineWidth: max(1, r * 0.06))
        ctx.fill(Path(CGRect(x: c.x - r * 0.38, y: bootY + r * 0.1, width: r * 0.93, height: r * 0.05).offsetBy(dx: facing < 0 ? -r * 0.17 : 0, dy: 0)),
                 with: .color(Color(white: 0.85)))
        face(ctx, c: c, r: r, banana: banana, facing: facing)
    }

    /// The head itself: a round banana (with its stem) or a tomato (with its leaves), and a face
    /// that looks the way it's playing.
    static func face(_ ctx: GraphicsContext, c: CGPoint, r: CGFloat, banana: Bool, facing: CGFloat) {
        let base = banana ? Color(red: 1, green: 0.84, blue: 0.24) : Color(red: 0.9, green: 0.2, blue: 0.16)
        let head = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.fill(head, with: .color(ink))
        let inner = Path(ellipseIn: CGRect(x: c.x - r + 1.5, y: c.y - r + 1.5, width: r * 2 - 3, height: r * 2 - 3))
        ctx.fill(inner, with: .radialGradient(Gradient(colors: [base.lit(0.35), base, base.shade(0.25)]),
                                              center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4), startRadius: 0, endRadius: r * 1.4))
        // Topping.
        if banana {
            var stem = Path()
            stem.move(to: CGPoint(x: c.x - facing * r * 0.05, y: c.y - r * 0.9))
            stem.addQuadCurve(to: CGPoint(x: c.x - facing * r * 0.3, y: c.y - r * 1.35), control: CGPoint(x: c.x, y: c.y - r * 1.25))
            ctx.stroke(stem, with: .color(ink), style: StrokeStyle(lineWidth: max(3, r * 0.26), lineCap: .round))
            ctx.stroke(stem, with: .color(Color(red: 0.5, green: 0.42, blue: 0.16)), style: StrokeStyle(lineWidth: max(2, r * 0.16), lineCap: .round))
            // A sweatband.
            ctx.fill(Path(CGRect(x: c.x - r * 0.95, y: c.y - r * 0.55, width: r * 1.9, height: r * 0.2)).applying(.identity), with: .color(Color(red: 0.16, green: 0.5, blue: 0.9)))
        } else {
            for k in 0..<5 {
                let a = -Double.pi / 2 + (Double(k) - 2) * 0.5
                var leaf = Path()
                let tip = CGPoint(x: c.x + CGFloat(cos(a)) * r * 0.55, y: c.y - r * 0.82 + CGFloat(sin(a) + 1) * r * 0.12)
                leaf.move(to: CGPoint(x: c.x, y: c.y - r * 0.9))
                leaf.addQuadCurve(to: tip, control: CGPoint(x: (c.x + tip.x) / 2, y: c.y - r * 1.12))
                ctx.stroke(leaf, with: .color(Color(red: 0.2, green: 0.55, blue: 0.2)), style: StrokeStyle(lineWidth: max(2, r * 0.14), lineCap: .round))
            }
        }
        // Eyes looking toward the opponent's goal, brows set for battle.
        for dx in [-0.34, 0.26] as [CGFloat] {
            let e = CGPoint(x: c.x + facing * dx * r, y: c.y - r * 0.12)
            ctx.fill(Path(ellipseIn: CGRect(x: e.x - r * 0.18, y: e.y - r * 0.22, width: r * 0.36, height: r * 0.44)), with: .color(.white))
            ctx.stroke(Path(ellipseIn: CGRect(x: e.x - r * 0.18, y: e.y - r * 0.22, width: r * 0.36, height: r * 0.44)), with: .color(ink), lineWidth: max(1, r * 0.04))
            ctx.fill(Path(ellipseIn: CGRect(x: e.x + facing * r * 0.02 - r * 0.07, y: e.y - r * 0.09, width: r * 0.14, height: r * 0.2)), with: .color(ink))
        }
        var brows = Path()
        brows.move(to: CGPoint(x: c.x - facing * r * 0.52, y: c.y - r * 0.44)); brows.addLine(to: CGPoint(x: c.x - facing * r * 0.14, y: c.y - r * 0.36))
        brows.move(to: CGPoint(x: c.x + facing * r * 0.1, y: c.y - r * 0.36)); brows.addLine(to: CGPoint(x: c.x + facing * r * 0.44, y: c.y - r * 0.44))
        ctx.stroke(brows, with: .color(ink), style: StrokeStyle(lineWidth: max(1.5, r * 0.1), lineCap: .round))
        var mouth = Path()
        mouth.move(to: CGPoint(x: c.x - r * 0.12 + facing * r * 0.05, y: c.y + r * 0.42))
        mouth.addQuadCurve(to: CGPoint(x: c.x + r * 0.22 + facing * r * 0.05, y: c.y + r * 0.38), control: CGPoint(x: c.x + facing * r * 0.08, y: c.y + r * 0.58))
        ctx.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: max(1.5, r * 0.08), lineCap: .round))
    }

    /// The classic black-and-white ball, rolling.
    static func ball(_ ctx: GraphicsContext, at c: CGPoint, r: CGFloat, spin: Double) {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(ink))
        let inner = Path(ellipseIn: CGRect(x: c.x - r + 1, y: c.y - r + 1, width: r * 2 - 2, height: r * 2 - 2))
        ctx.fill(inner, with: .radialGradient(Gradient(colors: [.white, Color(white: 0.8)]),
                                              center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.35), startRadius: 0, endRadius: r * 1.3))
        var patches = ctx
        patches.clip(to: inner)
        func pentagon(_ p: CGPoint, _ s: CGFloat, _ rot: Double) -> Path {
            var path = Path()
            for k in 0..<5 {
                let a = rot + Double(k) / 5 * 2 * .pi
                let pt = CGPoint(x: p.x + CGFloat(cos(a)) * s, y: p.y + CGFloat(sin(a)) * s)
                if k == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            path.closeSubpath()
            return path
        }
        patches.fill(pentagon(c, r * 0.32, spin), with: .color(ink))
        for k in 0..<5 {
            let a = spin + Double(k) / 5 * 2 * .pi + .pi / 5
            let p = CGPoint(x: c.x + CGFloat(cos(a)) * r * 0.86, y: c.y + CGFloat(sin(a)) * r * 0.86)
            patches.fill(pentagon(p, r * 0.3, a), with: .color(ink))
        }
    }

    /// The goal frame in front of the play: posts and crossbar over the net.
    static func goalFront(_ ctx: GraphicsContext, _ s: CGSize, goalTop: CGFloat, ground: CGFloat, goalW: CGFloat) {
        let top = goalTop * s.height, bottom = ground * s.height, depth = goalW * s.width
        for left in [true, false] {
            let postX = left ? depth : s.width - depth
            var frame = Path()
            frame.move(to: CGPoint(x: left ? 0 : s.width, y: top)); frame.addLine(to: CGPoint(x: postX, y: top))
            frame.addLine(to: CGPoint(x: postX, y: bottom))
            ctx.stroke(frame, with: .color(ink.opacity(0.5)), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            ctx.stroke(frame, with: .color(.white), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
    }
}

/// Floodlit stadium, ad boards, the striped pitch and the nets behind the goal frames (static).
private struct Stadium: View, Equatable {
    let ground: CGFloat
    let goalTop: CGFloat
    let goalW: CGFloat

    var body: some View {
        Canvas { ctx, s in
            let w = s.width, h = s.height
            let boards = h * 0.55
            ctx.fill(Path(CGRect(origin: .zero, size: s)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.24, green: 0.52, blue: 0.9), Color(red: 0.6, green: 0.82, blue: 1)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: boards)))
            // Stands: tiers of crowd under a roof.
            let standTop = h * 0.2
            var stand = Path()
            stand.move(to: CGPoint(x: 0, y: standTop + h * 0.04))
            stand.addQuadCurve(to: CGPoint(x: w, y: standTop + h * 0.04), control: CGPoint(x: w / 2, y: standTop - h * 0.03))
            stand.addLine(to: CGPoint(x: w, y: boards)); stand.addLine(to: CGPoint(x: 0, y: boards)); stand.closeSubpath()
            ctx.fill(stand, with: .color(Color(red: 0.2, green: 0.22, blue: 0.3)))
            var crowd = ctx
            crowd.clip(to: stand)
            let palette: [Color] = [.red, .white, .yellow, .blue, .orange, Color(red: 0.4, green: 0.8, blue: 0.4), .pink]
            var y = standTop
            var row = 0
            while y < boards {
                var x: CGFloat = row % 2 == 0 ? 3 : 7
                var k = 0
                while x < w {
                    let col = palette[Int(SoccerArt.hash(Double(row * 97 + k)) * CGFloat(palette.count)) % palette.count]
                    crowd.fill(Path(ellipseIn: CGRect(x: x, y: y + SoccerArt.hash(Double(k + row)) * 2, width: 4.5, height: 5)), with: .color(col.opacity(0.85)))
                    x += 8; k += 1
                }
                y += 7; row += 1
                if row % 5 == 0 {
                    crowd.fill(Path(CGRect(x: 0, y: y, width: w, height: 2.5)), with: .color(Color(red: 0.55, green: 0.58, blue: 0.64)))
                    y += 3
                }
            }
            // Roof and floodlights.
            var roof = Path()
            roof.move(to: CGPoint(x: 0, y: standTop + h * 0.02))
            roof.addQuadCurve(to: CGPoint(x: w, y: standTop + h * 0.02), control: CGPoint(x: w / 2, y: standTop - h * 0.05))
            ctx.stroke(roof, with: .color(Color(red: 0.85, green: 0.87, blue: 0.9)), lineWidth: 5)
            for fx in [w * 0.12, w * 0.88] {
                ctx.fill(Path(CGRect(x: fx - 1.5, y: standTop - h * 0.06, width: 3, height: h * 0.07)), with: .color(Color(white: 0.75)))
                let lamp = CGRect(x: fx - 14, y: standTop - h * 0.09, width: 28, height: 12)
                ctx.fill(Path(roundedRect: lamp, cornerRadius: 3), with: .color(Color(white: 0.3)))
                var bulbs = Path()
                for k in 0..<4 { bulbs.addEllipse(in: CGRect(x: lamp.minX + 2 + CGFloat(k) * 6.5, y: lamp.minY + 3, width: 5, height: 5)) }
                ctx.fill(bulbs, with: .color(Color(red: 1, green: 0.98, blue: 0.8)))
            }
            // Ad boards along the back of the pitch.
            let boardH = h * 0.04
            let colours: [Color] = [Color(red: 0.95, green: 0.8, blue: 0.2), Color(red: 0.2, green: 0.5, blue: 0.9), Color(red: 0.9, green: 0.25, blue: 0.2), Color(red: 0.15, green: 0.6, blue: 0.35)]
            var bx: CGFloat = 0
            var k = 0
            while bx < w {
                let bw = w * 0.24
                let r = CGRect(x: bx, y: boards, width: bw, height: boardH)
                ctx.fill(Path(r), with: .color(colours[k % colours.count]))
                ctx.fill(Path(roundedRect: r.insetBy(dx: bw * 0.3, dy: boardH * 0.28), cornerRadius: 3), with: .color(.white.opacity(0.85)))
                bx += bw; k += 1
            }
            // Pitch with mowing stripes.
            let pitchTop = boards + boardH
            let pitch = CGRect(x: 0, y: pitchTop, width: w, height: h - pitchTop)
            ctx.fill(Path(pitch), with: .color(Color(red: 0.28, green: 0.62, blue: 0.24)))
            var stripe = pitchTop
            var i = 0
            while stripe < h {
                let band = h * 0.035 * (1 + CGFloat(i) * 0.25)
                if i % 2 == 0 { ctx.fill(Path(CGRect(x: 0, y: stripe, width: w, height: band)), with: .color(Color(red: 0.34, green: 0.7, blue: 0.3))) }
                stripe += band; i += 1
            }
            // The touchline the ball rolls on, and the halfway line.
            let gy = ground * h
            ctx.fill(Path(CGRect(x: 0, y: gy - 1, width: w, height: 2.5)), with: .color(.white.opacity(0.85)))
            ctx.fill(Path(CGRect(x: w / 2 - 1.2, y: pitchTop, width: 2.4, height: gy - pitchTop)), with: .color(.white.opacity(0.55)))
            ctx.stroke(Path(ellipseIn: CGRect(x: w / 2 - w * 0.12, y: gy - h * 0.035, width: w * 0.24, height: h * 0.07)), with: .color(.white.opacity(0.55)), lineWidth: 2)
            // Nets behind the goal mouths.
            let top = goalTop * h, depth = goalW * w
            for left in [true, false] {
                let r = CGRect(x: left ? 0 : w - depth, y: top, width: depth, height: gy - top)
                ctx.fill(Path(r), with: .color(.white.opacity(0.18)))
                var net = Path()
                var nx = r.minX
                while nx <= r.maxX { net.move(to: CGPoint(x: nx, y: r.minY)); net.addLine(to: CGPoint(x: nx, y: r.maxY)); nx += 5 }
                var ny = r.minY
                while ny <= r.maxY { net.move(to: CGPoint(x: r.minX, y: ny)); net.addLine(to: CGPoint(x: r.maxX, y: ny)); ny += 5 }
                ctx.stroke(net, with: .color(.white.opacity(0.6)), lineWidth: 0.8)
            }
        }
        .allowsHitTesting(false)
    }
}

/// The framed keys from the Head Soccer HUD.
private struct FramedKeyFace: View {
    var pressed: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(LinearGradient(colors: pressed ? [Color(red: 0.2, green: 0.2, blue: 0.3), Color(red: 0.32, green: 0.3, blue: 0.42)]
                                                 : [Color(red: 0.36, green: 0.34, blue: 0.48).opacity(0.92), Color(red: 0.16, green: 0.15, blue: 0.24).opacity(0.92)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.95, green: 0.76, blue: 0.3), lineWidth: pressed ? 3 : 2))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.25), lineWidth: 1).padding(3))
    }
}

private struct FramedKeyStyle: ButtonStyle {
    var lit: Bool
    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed || lit
        return configuration.label
            .foregroundStyle(down ? Color(red: 1, green: 0.85, blue: 0.3) : .white)
            .background(FramedKeyFace(pressed: down))
            .scaleEffect(down ? 0.92 : 1)
    }
}

