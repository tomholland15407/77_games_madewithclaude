//
//  GunMayhemGame.swift
//  A Banana Game
//
//  Reflex — a Gun Mayhem–style platform brawler. You and rival gunners fight on
//  floating platforms; there are no health bars — every bullet you land builds an
//  opponent's KNOCKBACK, and once they're rattled enough a hit blasts them clean off
//  the stage. Move with ◄ ►, JUMP (double-jump to recover), and SHOOT. Knock every
//  rival off to win. Fall off yourself three times, or let the clock run out with
//  rivals still standing, and you fail back to level 1.
//
//  7 levels: more rivals with more lives, faster and more accurate fire, and stages
//  that lose their safety platforms so a single big hit sends you flying with nothing
//  to grab — levels 6–7 are a knife-edge.
//
//  Controls are fixed on-screen buttons (finger stays put), so this stays tap-safe
//  and does NOT lock the feed.
//

import SwiftUI

enum GunMayhemGame {
    static let definition = GameDefinition(
        id: "gun-mayhem",
        title: "Ledge Brawl",
        emoji: "🍌",
        genre: .reflex,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "A platform brawl with no health bars — every hit builds a rival's knockback.",
                "Move with ◄ ►, JUMP (tap again to double-jump), and SHOOT.",
                "Knock every rival off the stage to win.",
                "Fall off three times, or time out with rivals standing, and you're back to level 1.",
            ],
            bulletsVI: [
                "Ẩu đả trên bệ, không có thanh máu — mỗi phát trúng làm đối thủ bị hất mạnh hơn.",
                "Di chuyển bằng ◄ ►, NHẢY (chạm lần nữa để nhảy đúp), và BẮN.",
                "Hất mọi đối thủ khỏi sân để thắng.",
                "Rơi ba lần, hoặc hết giờ khi đối thủ còn đứng, sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(GunMayhemView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct GunMayhemView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    // MARK: Difficulty (from level)
    private var enemyCount: Int    { [1, 1, 2, 2, 3, 3, 3][min(level, 7) - 1] }
    private var enemyLives: Int    { [1, 2, 2, 2, 2, 3, 3][min(level, 7) - 1] }
    private var enemyFire: Double  { [1.5, 1.3, 1.15, 1.0, 0.9, 0.8, 0.7][min(level, 7) - 1] }
    private var timeLimit: Double  { Double(35 + enemyCount * 13) }

    // MARK: Physics constants (fractions of the play area)
    private let g: CGFloat = 2.2
    private let maxFall: CGFloat = 1.6
    private let moveSpeed: CGFloat = 0.45
    private let groundAccel: CGFloat = 4.0
    private let airAccel: CGFloat = 1.5
    private let jumpV: CGFloat = -1.0
    private let fw: CGFloat = 0.032       // fighter half-width
    private let fh: CGFloat = 0.050       // fighter half-height
    private let bulletSpeed: CGFloat = 1.4
    private let bulletLife: Double = 0.85
    private let playerFire: Double = 0.30
    private let hitDamage: Double = 0.14
    private let knockBase: CGFloat = 0.35
    private let knockGrow: CGFloat = 1.1
    private let upKickBase: CGFloat = 0.35
    private let upKickGrow: CGFloat = 0.5
    // Rivals hold a firing distance from you: closer than keepNear they back off, past keepFar they close in.
    private let keepNear: CGFloat = 0.14
    private let keepFar: CGFloat = 0.32

    // MARK: Model
    private struct Plat: Identifiable { let id = UUID(); let x: CGFloat; let y: CGFloat; let w: CGFloat }
    private struct Fighter: Identifiable {
        let id: Int
        var pos: CGPoint
        var vel: CGVector = .zero
        var facing: CGFloat = 1
        var onGround = false
        var jumpsLeft = 2
        var lives: Int
        var damage: Double = 0
        var shootCD: Double = 0
        var invuln: Double = 0
        let isPlayer: Bool
        let shirt: Color
        let hat: Color
        // AI intents
        var moveDir: CGFloat = 0
        var jumpReq = false
        var shootReq = false
        var aiTimer: Double = 0
        var paceTimer: Double = 0      // until a rival turns back on its stroll
    }
    /// `lastX` is where this frame's sweep starts (the gun hand on the first frame), so hits can't be skipped.
    private struct Bullet: Identifiable { let id = UUID(); var pos: CGPoint; var lastX: CGFloat; var vel: CGVector; let fromPlayer: Bool; var life: Double }
    private struct Burst: Identifiable { let id = UUID(); let pos: CGPoint; let color: Color }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var plats: [Plat] = []
    @State private var fighters: [Fighter] = []
    @State private var bullets: [Bullet] = []
    @State private var bursts: [Burst] = []
    @State private var timeLeft = 0.0
    @State private var shakeTick = 0
    @State private var loopTask: Task<Void, Never>?
    @State private var built = false

    // Player input
    @State private var playerMoveDir: CGFloat = 0
    @State private var playerJumpReq = false
    @State private var playerShootReq = false

    // Demo-only: which on-screen control is visibly "pressed" right now.
    @State private var demoMove: CGFloat = 0
    @State private var demoJump = false
    @State private var demoFire = false

    private var enemiesLeft: Int { fighters.filter { !$0.isPlayer }.count }
    private var playerLives: Int { fighters.first?.lives ?? 0 }

    private var skyTop: Color {
        [Color(red:0.14,green:0.20,blue:0.34), Color(red:0.20,green:0.18,blue:0.34),
         Color(red:0.24,green:0.16,blue:0.30), Color(red:0.22,green:0.13,blue:0.24),
         Color(red:0.18,green:0.10,blue:0.20), Color(red:0.14,green:0.07,blue:0.14),
         Color(red:0.10,green:0.04,blue:0.10)][min(level,7)-1]
    }
    private var skyBottom: Color {
        [Color(red:0.28,green:0.40,blue:0.55), Color(red:0.34,green:0.32,blue:0.50),
         Color(red:0.40,green:0.28,blue:0.44), Color(red:0.36,green:0.22,blue:0.34),
         Color(red:0.30,green:0.16,blue:0.28), Color(red:0.22,green:0.10,blue:0.20),
         Color(red:0.16,green:0.06,blue:0.14)][min(level,7)-1]
    }

    var body: some View {
        VStack(spacing: isDemo ? 6 : 8) {
            if !isDemo { hud }

            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    MayhemStage(level: level, plats: plats.map { GMPlat(x: $0.x, y: $0.y, w: $0.w) }).equatable()

                    // Everything that moves, in one pass: tracers, fighters, muzzle flashes, name tags.
                    Canvas { ctx, size in drawAction(ctx, size) }

                    ForEach(bursts) { b in
                        ParticleBurstView(color: b.color, count: 12, spread: 46) {
                            bursts.removeAll { $0.id == b.id }
                        }
                        .position(x: b.pos.x * w, y: b.pos.y * h)
                    }
                }
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: isDemo ? 10 : 14))
                .overlay(RoundedRectangle(cornerRadius: isDemo ? 10 : 14).stroke(Color.black, lineWidth: 2))
                .screenShake(shakeTick, amount: 6)
            }
            .padding(.horizontal, isDemo ? 6 : 10)

            controls
        }
        .padding(.vertical, isDemo ? 6 : 10)
        .background(GunmetalPanel().equatable())
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
    }

    /// Fighter chips with lives (you on the left, the rivals still standing on the right) around the
    /// match clock (hidden in the manual demo to fit the card).
    private var hud: some View {
        HStack(spacing: 8) {
            fighterChip(color: BananaTheme.banana, hat: 0, hatColor: fighters.first?.hat ?? .black,
                        label: L("YOU", "BẠN"), lives: playerLives)
            Spacer(minLength: 4)
            Text(clockText)
                .font(.system(size: 20, weight: .black, design: .monospaced))
                .foregroundStyle(timeLeft < 10 ? Color(red: 1, green: 0.35, blue: 0.3) : Color(white: 0.12))
                .padding(.horizontal, 14).padding(.vertical, 5)
                .background(SteelPlate(pressed: false))
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                ForEach(fighters.filter { !$0.isPlayer }) { f in
                    fighterChip(color: f.shirt, hat: f.id, hatColor: f.hat, label: nil, lives: f.lives)
                }
            }
        }
        .padding(.horizontal, 14)
    }

    private var clockText: String {
        let t = max(0, Int(timeLeft.rounded(.up)))
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    private func fighterChip(color: Color, hat: Int, hatColor: Color, label: String?, lives: Int) -> some View {
        HStack(spacing: 4) {
            Canvas { ctx, s in
                MayhemArt.headIcon(ctx, center: CGPoint(x: s.width / 2, y: s.height * 0.58), r: s.height * 0.3,
                                   color: color, hat: hat, hatColor: hatColor)
            }
            .frame(width: 24, height: 26)
            if let label {
                Text(label).font(.system(size: 12, weight: .black)).foregroundStyle(.white)
            }
            Text("×\(max(0, lives))").font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(Color(white: 0.8))
        }
    }

    // MARK: - Rendering

    private func drawAction(_ ctx: GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        // Tracer rounds.
        for b in bullets {
            let p = CGPoint(x: b.pos.x * w, y: b.pos.y * h)
            let dir: CGFloat = b.vel.dx >= 0 ? 1 : -1
            let len: CGFloat = max(12, w * 0.07)
            let tail = CGPoint(x: p.x - dir * len, y: p.y)
            let col = b.fromPlayer ? Color(red: 1, green: 0.93, blue: 0.45) : Color(red: 1, green: 0.5, blue: 0.28)
            var streak = Path()
            streak.move(to: tail); streak.addLine(to: p)
            ctx.stroke(streak, with: .linearGradient(Gradient(colors: [col.opacity(0), col]), startPoint: tail, endPoint: p),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)), with: .color(.white))
        }
        // Fighters.
        let figureH: CGFloat = fh * 2.3 * h
        let tagSize: CGFloat = max(8, figureH * 0.24)
        var botNumber = 0
        var tags: [CGRect] = []
        var labels: [(GraphicsContext.ResolvedText, GraphicsContext.ResolvedText, CGPoint)] = []
        for f in fighters {
            if !f.isPlayer { botNumber += 1 }
            let blink = f.invuln > 0 && Int(f.invuln * 12) % 2 == 0
            let feet = CGPoint(x: f.pos.x * w, y: (f.pos.y + fh) * h)
            let reload = f.isPlayer ? playerFire : enemyFire
            let justFired = f.shootCD > reload - 0.08
            let pose: StickPose
            if !f.onGround { pose = .jumping }
            else if justFired { pose = MayhemArt.aim }
            else if abs(f.vel.dx) > 0.08 { pose = Int(f.pos.x * 90) % 2 == 0 ? .runA : .runB }
            else { pose = .standing }
            MayhemArt.fighter(ctx, pose: pose, feet: feet, height: figureH, facing: f.facing, color: f.shirt,
                              hat: f.id, hatColor: f.hat, alpha: blink ? 0.35 : 1, flash: justFired)
            // Name tag over the head, like the arena's "Bot 1".
            let tag = f.isPlayer ? L("YOU", "BẠN") : L("BOT \(botNumber)", "MÁY \(botNumber)")
            let text = Text(tag).font(.system(size: tagSize, weight: .heavy))
            let label = ctx.resolve(text.foregroundColor(f.isPlayer ? BananaTheme.banana : .white))
            let shadow = ctx.resolve(text.foregroundColor(.black.opacity(0.7)))
            let size = label.measure(in: CGSize(width: 300, height: 100))
            var at = CGPoint(x: feet.x, y: feet.y - figureH * 1.14)
            // Fighters bunched together stack their tags instead of printing over each other.
            var box = CGRect(x: at.x - size.width / 2, y: at.y - size.height / 2, width: size.width, height: size.height)
            while tags.contains(where: { $0.intersects(box) }) {
                at.y -= size.height + 1
                box = box.offsetBy(dx: 0, dy: -(size.height + 1))
            }
            tags.append(box)
            labels.append((shadow, label, at))
        }
        // Tags go on last, so no fighter is ever drawn over a name.
        for (shadow, label, at) in labels {
            ctx.draw(shadow, at: CGPoint(x: at.x + 1, y: at.y + 1))
            ctx.draw(label, at: at)
        }
    }

    // MARK: - Controls (riveted steel, like the logo)

    private var controls: some View {
        HStack {
            HStack(spacing: isDemo ? 8 : 12) {
                holdButton("chevron.left", dir: -1)
                holdButton("chevron.right", dir: 1)
            }
            Spacer()
            HStack(spacing: isDemo ? 8 : 12) {
                Button { playerJumpReq = true; Haptics.tap() } label: { controlIcon("arrow.up") }
                    .buttonStyle(SteelButtonStyle(lit: demoJump, width: btnW, height: btnH))
                Button { playerShootReq = true } label: { controlIcon("scope") }
                    .buttonStyle(SteelButtonStyle(lit: demoFire, width: btnW, height: btnH, red: true))
            }
        }
        .padding(.horizontal, isDemo ? 14 : 22)
        .padding(.bottom, isDemo ? 0 : 4)
    }

    private var btnW: CGFloat { isDemo ? 54 : 72 }
    private var btnH: CGFloat { isDemo ? 42 : 58 }

    private func controlIcon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: isDemo ? 19 : 25, weight: .black))
    }

    /// Press-and-hold move button (idiom B) — finger stays on it, so no feed-swipe conflict.
    private func holdButton(_ icon: String, dir: CGFloat) -> some View {
        let pressed = playerMoveDir == dir || (isDemo && demoMove == dir)
        return controlIcon(icon)
            .foregroundStyle(Color(white: pressed ? 0.05 : 0.14))
            .shadow(color: .white.opacity(0.5), radius: 0, x: 0, y: 1)
            .frame(width: btnW, height: btnH)
            .background(SteelPlate(pressed: pressed))
            .scaleEffect(pressed ? 0.94 : 1)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if phase == .play { playerMoveDir = dir } }
                .onEnded { _ in if playerMoveDir == dir { playerMoveDir = 0 } })
    }

    // MARK: - Flow

    private func run() async {
        if !built { setup(); built = true }
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
    // Level 1: one rival, one life. The real sim runs at a fixed 1/60s with a coin-flip-free
    // rival, so every loop is identical. The rival starts as if it had just fired (its real L1
    // reload is on cooldown). Scripted you: ◄ turns to face it and FIRE lands at once, then a
    // steady FIRE rhythm from the ground walks it back until a hit blasts it off the stage (5
    // hits, ~1.9s, verified headless against this exact code). A rival bullet closing in while
    // you're grounded triggers a dodge-JUMP; once it's launched you hop in celebration.
    private func runDemo() async {
        let dt: CGFloat = 1.0 / 60.0
        while !Task.isCancelled {
            setup()
            for i in fighters.indices where !fighters[i].isPlayer { fighters[i].shootCD = enemyFire }
            demoMove = 0; demoJump = false; demoFire = false
            try? await Task.sleep(for: .seconds(0.5))
            var t = 0.0, nextFire = 0.0, jumpFlash = 0.0, fireFlash = 0.0
            while !Task.isCancelled && phase == .play && t < 8 {
                t += Double(dt)
                demoInput(t: t, nextFire: &nextFire, jumpFlash: &jumpFlash, fireFlash: &fireFlash)
                step(dt: dt)
                jumpFlash -= Double(dt); fireFlash -= Double(dt)
                try? await Task.sleep(for: .seconds(0.016))
            }
            // The rival fell off → the real win() ran (onWin is a no-op). Hold on it while you
            // land your hop and the last bullets fly out, then loop.
            playerMoveDir = 0
            for _ in 0..<78 {
                guard !Task.isCancelled else { return }
                if !fighters.isEmpty { physics(&fighters[0], dt: dt) }
                stepBullets(dt: dt)
                jumpFlash -= Double(dt); fireFlash -= Double(dt)
                demoMove = 0; demoJump = jumpFlash > 0; demoFire = fireFlash > 0
                try? await Task.sleep(for: .seconds(0.016))
            }
        }
    }

    /// The scripted player for one demo frame at sim time `t`; also lights up the pressed control.
    private func demoInput(t: Double, nextFire: inout Double, jumpFlash: inout Double, fireFlash: inout Double) {
        guard let me = fighters.first else { return }
        let frame = Int((t * 60).rounded())
        // A short ◄ press turns you to face the rival (it spawns on your left).
        playerMoveDir = frame <= 8 ? -1 : 0
        // Dodge any rival bullet about to reach you; hop once the rival is launched off-stage.
        let incoming = bullets.contains { b in
            !b.fromPlayer && abs(b.pos.y - me.pos.y) < fh + 0.02
                && (b.pos.x - me.pos.x) * b.vel.dx < 0 && abs(b.pos.x - me.pos.x) < 0.2
        }
        // (The celebration hop waits until every rival round has cleared you, so it can't hop into one.)
        let inbound = bullets.contains { !$0.fromPlayer && ($0.pos.x - me.pos.x) * ($0.vel.dx > 0 ? 1 : -1) < fw * 2 }
        let launched = !inbound && fighters.dropFirst().contains { $0.pos.x < 0 || $0.pos.x > 1 }
        if me.onGround && (incoming || launched) {
            playerJumpReq = true; jumpFlash = 0.18
        }
        // FIRE on a steady rhythm while grounded (airborne shots would sail over the rival).
        if me.onGround && t >= nextFire {
            playerShootReq = true; fireFlash = 0.12
            nextFire = t + 0.33
        }
        demoMove = playerMoveDir
        demoJump = jumpFlash > 0
        demoFire = fireFlash > 0
    }

    private func setup() {
        plats = buildPlats()
        let mainTop = plats[0].y
        var fs: [Fighter] = []
        fs.append(Fighter(id: 0, pos: CGPoint(x: 0.5, y: mainTop - fh), lives: 3,
                          isPlayer: true, shirt: BananaTheme.banana, hat: Color(red: 0.16, green: 0.16, blue: 0.28)))
        let shirts: [Color] = [Color(red: 0.90, green: 0.30, blue: 0.32),
                               Color(red: 0.35, green: 0.55, blue: 0.95),
                               Color(red: 0.45, green: 0.80, blue: 0.45)]
        // Two rivals flank you on the rooftop; a third starts up on the highest platform, not on top of you.
        let high = plats.dropFirst().min { $0.y < $1.y } ?? plats[0]
        let spots: [CGPoint] = [CGPoint(x: 0.22, y: mainTop - fh), CGPoint(x: 0.78, y: mainTop - fh),
                                CGPoint(x: high.x + high.w / 2, y: high.y - fh)]
        for k in 0..<enemyCount {
            fs.append(Fighter(id: k + 1, pos: spots[k % spots.count], lives: enemyLives,
                              isPlayer: false, shirt: shirts[k % shirts.count],
                              hat: shirts[k % shirts.count].shade(0.45),
                              aiTimer: isDemo ? 0.8 : Double.random(in: 0.3...1.0)))
        }
        fighters = fs
        bullets = []; bursts = []
        playerMoveDir = 0; playerJumpReq = false; playerShootReq = false
        timeLeft = timeLimit
        phase = .play
    }

    private func buildPlats() -> [Plat] {
        let mainY: CGFloat = 0.80
        var ps = [Plat(x: 0.14, y: mainY, w: 0.72)]
        switch level {
        case 1, 2, 3:
            ps.append(Plat(x: 0.04, y: 0.58, w: 0.24))
            ps.append(Plat(x: 0.72, y: 0.58, w: 0.24))
            ps.append(Plat(x: 0.39, y: 0.40, w: 0.22))
        case 4, 5:
            ps.append(Plat(x: 0.06, y: 0.56, w: 0.22))
            ps.append(Plat(x: 0.72, y: 0.56, w: 0.22))
        default:
            ps.append(Plat(x: 0.40, y: 0.44, w: 0.20))
        }
        return ps
    }

    private func step(dt: CGFloat) {
        guard phase == .play else { return }

        // Feed player input into fighter 0.
        if !fighters.isEmpty {
            fighters[0].moveDir = playerMoveDir
            if playerJumpReq { fighters[0].jumpReq = true; playerJumpReq = false }
            if playerShootReq { fighters[0].shootReq = true; playerShootReq = false }
        }

        // AI decides intents for rivals.
        for i in fighters.indices where !fighters[i].isPlayer { aiThink(&fighters[i], dt: dt) }

        // Physics for everyone.
        for i in fighters.indices { physics(&fighters[i], dt: dt) }
        separate()

        // Resolve shooting.
        for i in fighters.indices {
            guard fighters[i].shootReq else { continue }
            fighters[i].shootReq = false
            guard fighters[i].shootCD <= 0 else { continue }
            fighters[i].shootCD = fighters[i].isPlayer ? playerFire : enemyFire
            let dir = fighters[i].facing
            let bx = fighters[i].pos.x + dir * fw * 1.3
            let by = fighters[i].pos.y - fh * 0.15
            bullets.append(Bullet(pos: CGPoint(x: bx, y: by), lastX: fighters[i].pos.x + dir * fw,
                                  vel: CGVector(dx: dir * bulletSpeed, dy: 0),
                                  fromPlayer: fighters[i].isPlayer, life: bulletLife))
            SoundManager.shared.tap()
        }

        stepBullets(dt: dt)
        handleDeaths()
    }

    private func physics(_ f: inout Fighter, dt: CGFloat) {
        f.shootCD = max(0, f.shootCD - Double(dt))
        f.invuln = max(0, f.invuln - Double(dt))

        if f.jumpReq {
            f.jumpReq = false
            if f.jumpsLeft > 0 {
                f.vel.dy = jumpV
                f.jumpsLeft -= 1
                f.onGround = false
                if f.isPlayer { SoundManager.shared.tap() }
            }
        }

        // Horizontal control eases toward the desired speed; a big knockback overrides it and
        // only bleeds off slowly in the air (Smash-like recovery).
        let accel = f.onGround ? groundAccel : airAccel
        let desired = f.moveDir * moveSpeed
        let dv = desired - f.vel.dx
        let maxDV = accel * dt
        f.vel.dx += max(-maxDV, min(maxDV, dv))

        f.vel.dy = min(maxFall, f.vel.dy + g * dt)

        f.pos.x += f.vel.dx * dt
        f.pos.y += f.vel.dy * dt
        if f.moveDir != 0 { f.facing = f.moveDir > 0 ? 1 : -1 }

        // One-way platform landing (only while falling).
        f.onGround = false
        if f.vel.dy >= 0 {
            let feet = f.pos.y + fh
            for p in plats where f.pos.x >= p.x - fw * 0.4 && f.pos.x <= p.x + p.w + fw * 0.4 {
                if feet >= p.y && feet <= p.y + 0.06 + f.vel.dy * dt {
                    f.pos.y = p.y - fh
                    f.vel.dy = 0
                    f.onGround = true
                    f.jumpsLeft = 2
                    break
                }
            }
        }
    }

    /// Bodies are solid on the ground, so you and a rival can never share a spot. Whoever walked in is
    /// held back (nobody gets shoved off a ledge); a fighter landing on another slides off to the side.
    /// In the air you still pass over each other.
    private func separate() {
        for i in fighters.indices.dropFirst() {
            let me = fighters[0], r = fighters[i]
            guard me.onGround && r.onGround && abs(r.pos.y - me.pos.y) < fh else { continue }
            let gap = r.pos.x - me.pos.x
            let overlap = 2 * fw - abs(gap)
            guard overlap > 0 else { continue }
            let side: CGFloat = gap != 0 ? (gap > 0 ? 1 : -1) : (me.pos.x < 0.5 ? 1 : -1)   // the rival's side of you
            let youIn = max(0, me.vel.dx * side), rivalIn = max(0, -r.vel.dx * side)
            let yourShare = youIn + rivalIn > 0 ? youIn / (youIn + rivalIn) : 0.5
            fighters[0].pos.x -= side * overlap * yourShare
            fighters[i].pos.x += side * overlap * (1 - yourShare)
            if youIn > 0 { fighters[0].vel.dx = 0 }
            if rivalIn > 0 { fighters[i].vel.dx = 0 }
        }
    }

    private func aiThink(_ e: inout Fighter, dt: CGFloat) {
        guard let player = fighters.first else { return }
        e.aiTimer -= Double(dt)
        e.paceTimer -= Double(dt)
        let dx = player.pos.x - e.pos.x
        let dy = player.pos.y - e.pos.y
        let toward: CGFloat = dx >= 0 ? 1 : -1
        let level = abs(dy) < 0.07

        // Never stands still: it keeps striding and turns back every so often.
        var dir = e.moveDir
        if dir == 0 || e.paceTimer <= 0 {
            dir = dir == 0 ? toward : -dir
            e.paceTimer = isDemo ? 0.7 : Double.random(in: 0.4...0.9)
        }
        if level {
            // Hold a firing distance: back off when crowding you, close in from afar.
            if abs(dx) < keepNear { dir = -toward } else if abs(dx) > keepFar { dir = toward }
            // Turn to fire the moment the gun is ready, and keep facing you through the shot.
            if e.shootCD <= 0 || e.shootCD > enemyFire - 0.25 { dir = toward }
        } else if abs(dx) > 0.12 {
            dir = toward      // head over to your side of the stage
        }
        // Don't walk off an edge unless we deliberately leap.
        if e.onGround && !groundAhead(e.pos.x + dir * 0.06, e.pos.y) {
            if dir == toward && abs(dx) > 0.12 && (!isDemo && Bool.random()) { e.jumpReq = true }  // leap the gap toward the player
            else { dir = -dir }
        }
        e.moveDir = dir

        // Recover if knocked out past the stage edges.
        if !e.onGround && e.jumpsLeft > 0 && (e.pos.x < 0.10 || e.pos.x > 0.90) {
            e.jumpReq = true
            e.moveDir = e.pos.x < 0.5 ? 1 : -1
        }

        // Shoot when roughly level with the player and facing them (facing follows the stride).
        if level && e.moveDir == toward && e.shootCD <= 0 { e.shootReq = true }

        // Occasional hop to close vertical distance / dodge.
        if e.onGround && e.aiTimer <= 0 {
            // Demo: same AI, minus the coin flips, so every loop replays identically.
            e.aiTimer = isDemo ? 1.0 : Double.random(in: 0.6...1.4)
            if dy < -0.06 || (!isDemo && Bool.random()) { e.jumpReq = true }
        }
    }

    /// Is there a platform to stand on near this x at roughly the fighter's feet level?
    private func groundAhead(_ x: CGFloat, _ y: CGFloat) -> Bool {
        let feet = y + fh
        for p in plats where x >= p.x && x <= p.x + p.w {
            let drop = p.y - feet
            if drop >= -0.03 && drop < 0.25 { return true }
        }
        return false
    }

    private func stepBullets(dt: CGFloat) {
        var survivors: [Bullet] = []
        let reach = fw + 0.012
        for var b in bullets {
            let x0 = b.lastX
            b.pos.x += b.vel.dx * dt
            b.pos.y += b.vel.dy * dt
            b.lastX = b.pos.x
            b.life -= Double(dt)
            if b.life <= 0 || b.pos.x < -0.1 || b.pos.x > 1.1 || b.pos.y < -0.1 || b.pos.y > 1.2 { continue }
            var hit = false
            for i in fighters.indices {
                if fighters[i].isPlayer == b.fromPlayer { continue }   // no self / friendly fire
                if fighters[i].invuln > 0 { continue }
                // Swept along this frame's path, so a target pressed right up against the gun is hit point-blank.
                let x = fighters[i].pos.x
                if min(x0, b.pos.x) < x + reach && max(x0, b.pos.x) > x - reach && abs(b.pos.y - fighters[i].pos.y) < fh + 0.012 {
                    applyHit(i, bullet: b)
                    hit = true
                    break
                }
            }
            if !hit { survivors.append(b) }
        }
        bullets = survivors
    }

    private func applyHit(_ i: Int, bullet b: Bullet) {
        let dir: CGFloat = b.vel.dx >= 0 ? 1 : -1
        fighters[i].damage += hitDamage
        let impulse = knockBase + CGFloat(fighters[i].damage) * knockGrow
        fighters[i].vel.dx += dir * impulse
        fighters[i].vel.dy -= upKickBase + CGFloat(fighters[i].damage) * upKickGrow
        fighters[i].onGround = false
        bursts.append(Burst(pos: fighters[i].pos, color: fighters[i].shirt))
        shakeTick += 1
        if fighters[i].isPlayer { Haptics.warning(); SoundManager.shared.error() }
        else { Haptics.tap(); SoundManager.shared.tap() }
    }

    private func handleDeaths() {
        var updated: [Fighter] = []
        for var f in fighters {
            if f.pos.x < -0.12 || f.pos.x > 1.12 || f.pos.y > 1.18 || f.pos.y < -0.4 {
                f.lives -= 1
                bursts.append(Burst(pos: CGPoint(x: min(1.1, max(-0.1, f.pos.x)),
                                                 y: min(1.1, max(0, f.pos.y))), color: f.shirt))
                shakeTick += 1
                SoundManager.shared.error()
                if f.lives > 0 {
                    f.pos = CGPoint(x: 0.5, y: 0.06)
                    f.vel = .zero
                    f.damage = 0
                    f.invuln = 1.4
                    f.onGround = false
                    f.jumpsLeft = 2
                }
            }
            updated.append(f)
        }
        // Keep the player even at 0 lives (we fail on that); drop defeated rivals.
        fighters = updated.filter { $0.isPlayer || $0.lives > 0 }
        guard !fighters.isEmpty else { return }
        if fighters[0].lives <= 0 { fail(); return }
        if enemiesLeft == 0 { win() }
    }

    private func win() {
        guard phase == .play else { return }
        phase = .done
        loopTask?.cancel()
        onWin()
    }

    private func fail() {
        guard phase == .play else { return }
        phase = .done
        loopTask?.cancel()
        SoundManager.shared.error()
        onFail()
    }
}

// MARK: - Gun Mayhem art

/// A platform as the static stage needs it (the model's `Plat` carries a UUID).
private struct GMPlat: Equatable { let x: CGFloat; let y: CGFloat; let w: CGFloat }

private enum MayhemArt {
    static let ink = Color(red: 0.05, green: 0.05, blue: 0.09)
    /// Firing, with the pistol held at chest height — level with where the rounds actually leave.
    static let aim = StickPose(
        head: CGPoint(x: 0.50, y: 0.15), headR: 0.10,
        neck: CGPoint(x: 0.50, y: 0.27), hip: CGPoint(x: 0.50, y: 0.60),
        lElbow: CGPoint(x: 0.42, y: 0.40), lHand: CGPoint(x: 0.37, y: 0.47),
        rElbow: CGPoint(x: 0.62, y: 0.39), rHand: CGPoint(x: 0.76, y: 0.41),
        lKnee: CGPoint(x: 0.44, y: 0.78), lFoot: CGPoint(x: 0.38, y: 0.97),
        rKnee: CGPoint(x: 0.58, y: 0.78), rFoot: CGPoint(x: 0.64, y: 0.97))
    static let skyTops: [Color] = [Color(red: 0.14, green: 0.20, blue: 0.34), Color(red: 0.20, green: 0.18, blue: 0.34),
                                   Color(red: 0.24, green: 0.16, blue: 0.30), Color(red: 0.22, green: 0.13, blue: 0.24),
                                   Color(red: 0.18, green: 0.10, blue: 0.20), Color(red: 0.14, green: 0.07, blue: 0.14),
                                   Color(red: 0.10, green: 0.04, blue: 0.10)]
    static let skyBottoms: [Color] = [Color(red: 0.28, green: 0.40, blue: 0.55), Color(red: 0.34, green: 0.32, blue: 0.50),
                                      Color(red: 0.40, green: 0.28, blue: 0.44), Color(red: 0.36, green: 0.22, blue: 0.34),
                                      Color(red: 0.30, green: 0.16, blue: 0.28), Color(red: 0.22, green: 0.10, blue: 0.20),
                                      Color(red: 0.16, green: 0.06, blue: 0.14)]

    static func hash(_ n: Double) -> CGFloat {
        let v: Double = sin(n * 12.9898) * 43758.5453
        return CGFloat(v - floor(v))
    }

    /// Night rooftops: sky, moon, two rows of skyline with lit windows, the platforms, fog over the drop.
    static func stage(_ ctx: GraphicsContext, _ s: CGSize, level: Int, plats: [GMPlat]) {
        let L = max(1, min(level, 7)) - 1
        let w = s.width, h = s.height
        ctx.fill(Path(CGRect(origin: .zero, size: s)),
                 with: .linearGradient(Gradient(colors: [skyTops[L], skyBottoms[L]]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        // Moon.
        let mc = CGPoint(x: w * 0.8, y: h * 0.15), mr = min(w, h) * 0.07
        ctx.fill(Path(ellipseIn: CGRect(x: mc.x - mr * 3, y: mc.y - mr * 3, width: mr * 6, height: mr * 6)),
                 with: .radialGradient(Gradient(colors: [Color.white.opacity(0.18), .clear]), center: mc, startRadius: mr, endRadius: mr * 3))
        ctx.fill(Path(ellipseIn: CGRect(x: mc.x - mr, y: mc.y - mr, width: mr * 2, height: mr * 2)), with: .color(Color(red: 0.95, green: 0.93, blue: 0.84)))
        // Two rows of skyline, the far one hazier.
        skyline(ctx, w: w, h: h, top: h * 0.34, count: 11, seed: 3, color: skyBottoms[L].mix(with: Color(red: 0.1, green: 0.1, blue: 0.14), by: 0.45), lit: 0.25)
        skyline(ctx, w: w, h: h, top: h * 0.5, count: 7, seed: 17, color: skyTops[L].mix(with: .black, by: 0.55), lit: 0.45)
        // Platforms: the main one is a rooftop, high ones steel girders, the rest wooden planks.
        let mainW = plats.map(\.w).max() ?? 0
        for p in plats {
            let r = CGRect(x: p.x * w, y: p.y * h, width: p.w * w, height: max(10, h * 0.03))
            if p.w == mainW { rooftop(ctx, r, h: h) }
            else if p.y < 0.5 { girder(ctx, r) }
            else { plank(ctx, r) }
        }
        // Fog over the drop, and a soft vignette.
        ctx.fill(Path(CGRect(x: 0, y: h * 0.84, width: w, height: h * 0.16)),
                 with: .linearGradient(Gradient(colors: [skyBottoms[L].lit(0.1).opacity(0), skyBottoms[L].lit(0.12).opacity(0.75)]),
                                       startPoint: CGPoint(x: 0, y: h * 0.84), endPoint: CGPoint(x: 0, y: h)))
        ctx.fill(Path(CGRect(origin: .zero, size: s)),
                 with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.4)]), center: CGPoint(x: w / 2, y: h / 2),
                                       startRadius: min(w, h) * 0.4, endRadius: max(w, h) * 0.75))
    }

    static func skyline(_ ctx: GraphicsContext, w: CGFloat, h: CGFloat, top: CGFloat, count: Int, seed: Int, color: Color, lit: Double) {
        var x: CGFloat = -w * 0.03
        var k = 0
        var windows = Path()
        while x < w {
            let s = Double(seed * 31 + k)
            let bw: CGFloat = w * (0.08 + hash(s) * 0.1)
            let bh: CGFloat = (h - top) * (0.45 + hash(s + 1.3) * 0.55)
            let r = CGRect(x: x, y: h - bh, width: bw, height: bh)
            ctx.fill(Path(r), with: .color(color))
            if hash(s + 2.7) > 0.6 {
                // A water tower on the roof.
                let tw = bw * 0.35
                ctx.fill(Path(CGRect(x: r.minX + bw * 0.3, y: r.minY - tw * 0.9, width: tw, height: tw * 0.7)), with: .color(color))
                ctx.fill(Path(CGRect(x: r.minX + bw * 0.3 + tw * 0.15, y: r.minY - tw * 0.25, width: tw * 0.7, height: tw * 0.25)), with: .color(color))
            } else if hash(s + 4.1) > 0.5 {
                var mast = Path()
                mast.move(to: CGPoint(x: r.midX, y: r.minY)); mast.addLine(to: CGPoint(x: r.midX, y: r.minY - bh * 0.18))
                ctx.stroke(mast, with: .color(color), lineWidth: 1.5)
            }
            let cw: CGFloat = max(2.5, bw * 0.12), ch: CGFloat = max(3, cw * 1.2)
            var yy = r.minY + ch
            var row = 0
            while yy < h - ch {
                var xx = r.minX + cw * 0.8
                var col = 0
                while xx < r.maxX - cw {
                    if Double(hash(s * 7 + Double(row) * 1.9 + Double(col) * 3.3)) < lit {
                        windows.addRect(CGRect(x: xx, y: yy, width: cw, height: ch))
                    }
                    xx += cw * 2; col += 1
                }
                yy += ch * 2; row += 1
            }
            x += bw + w * 0.005
            k += 1
        }
        ctx.fill(windows, with: .color(Color(red: 1, green: 0.84, blue: 0.45).opacity(0.55)))
    }

    /// The main platform: a concrete rooftop with a ledge, its building dropping away into the fog.
    static func rooftop(_ ctx: GraphicsContext, _ r: CGRect, h: CGFloat) {
        let body = CGRect(x: r.minX + 4, y: r.minY, width: r.width - 8, height: h - r.minY + 2)
        ctx.fill(Path(body), with: .linearGradient(Gradient(colors: [Color(red: 0.24, green: 0.25, blue: 0.3), Color(red: 0.13, green: 0.13, blue: 0.17)]),
                                                   startPoint: CGPoint(x: 0, y: body.minY), endPoint: CGPoint(x: 0, y: body.maxY)))
        var windows = Path()
        let cw: CGFloat = max(5, r.width * 0.045), ch: CGFloat = cw * 1.3
        var yy = r.maxY + ch
        var row = 0
        while yy < h {
            var xx = body.minX + cw
            var col = 0
            while xx < body.maxX - cw {
                if hash(Double(row) * 5.1 + Double(col) * 2.3) > 0.55 { windows.addRect(CGRect(x: xx, y: yy, width: cw, height: ch)) }
                xx += cw * 2.2; col += 1
            }
            yy += ch * 2; row += 1
        }
        ctx.fill(windows, with: .color(Color(red: 1, green: 0.82, blue: 0.42).opacity(0.5)))
        ctx.stroke(Path(body), with: .color(ink), lineWidth: 2)
        let ledge = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height)
        ctx.fill(Path(ledge), with: .linearGradient(Gradient(colors: [Color(red: 0.62, green: 0.64, blue: 0.68), Color(red: 0.42, green: 0.44, blue: 0.49)]),
                                                    startPoint: CGPoint(x: 0, y: ledge.minY), endPoint: CGPoint(x: 0, y: ledge.maxY)))
        ctx.fill(Path(CGRect(x: ledge.minX, y: ledge.minY, width: ledge.width, height: 2)), with: .color(.white.opacity(0.45)))
        ctx.stroke(Path(ledge), with: .color(ink), lineWidth: 2)
    }

    /// A wooden plank with seams and nails.
    static func plank(_ ctx: GraphicsContext, _ r: CGRect) {
        ctx.fill(Path(r), with: .linearGradient(Gradient(colors: [Color(red: 0.78, green: 0.53, blue: 0.3), Color(red: 0.56, green: 0.35, blue: 0.18)]),
                                                startPoint: CGPoint(x: 0, y: r.minY), endPoint: CGPoint(x: 0, y: r.maxY)))
        var seams = Path()
        var x = r.minX + r.width / 3
        while x < r.maxX - 2 { seams.move(to: CGPoint(x: x, y: r.minY)); seams.addLine(to: CGPoint(x: x, y: r.maxY)); x += r.width / 3 }
        ctx.stroke(seams, with: .color(ink.opacity(0.6)), lineWidth: 1)
        var nails = Path()
        for k in 0..<3 {
            for dx in [4.0, r.width / 3 - 4] as [CGFloat] {
                let nx = r.minX + CGFloat(k) * r.width / 3 + dx
                nails.addEllipse(in: CGRect(x: nx - 1, y: r.midY - 1, width: 2, height: 2))
            }
        }
        ctx.fill(nails, with: .color(ink.opacity(0.7)))
        ctx.fill(Path(CGRect(x: r.minX, y: r.minY, width: r.width, height: 1.5)), with: .color(.white.opacity(0.35)))
        ctx.stroke(Path(r), with: .color(ink), lineWidth: 2)
    }

    /// A riveted steel I-beam.
    static func girder(_ ctx: GraphicsContext, _ r: CGRect) {
        let flange = r.height * 0.3
        let steel = Gradient(colors: [Color(red: 0.7, green: 0.73, blue: 0.78), Color(red: 0.42, green: 0.45, blue: 0.5)])
        ctx.fill(Path(CGRect(x: r.minX + r.width * 0.02, y: r.minY + flange, width: r.width * 0.96, height: r.height - flange * 2)),
                 with: .color(Color(red: 0.34, green: 0.36, blue: 0.4)))
        for y in [r.minY, r.maxY - flange] {
            let f = CGRect(x: r.minX, y: y, width: r.width, height: flange)
            ctx.fill(Path(f), with: .linearGradient(steel, startPoint: CGPoint(x: 0, y: f.minY), endPoint: CGPoint(x: 0, y: f.maxY)))
            ctx.stroke(Path(f), with: .color(ink), lineWidth: 1.5)
        }
        var rivets = Path()
        var x = r.minX + 6
        while x < r.maxX - 4 { rivets.addEllipse(in: CGRect(x: x - 1.2, y: r.midY - 1.2, width: 2.4, height: 2.4)); x += 10 }
        ctx.fill(rivets, with: .color(Color(white: 0.75)))
        ctx.stroke(Path(r), with: .color(ink), lineWidth: 2)
    }

    /// A stick-figure gunner in the StickFigure style (outlined round-capped limbs, filled head), with a
    /// chunky vest torso, a hat, a pistol and — right after a shot — a muzzle flash.
    static func fighter(_ ctx: GraphicsContext, pose: StickPose, feet: CGPoint, height H: CGFloat, facing: CGFloat,
                        color: Color, hat: Int, hatColor: Color, alpha: Double, flash: Bool) {
        var c = ctx
        c.opacity = alpha
        func m(_ p: CGPoint) -> CGPoint { CGPoint(x: feet.x + (p.x - 0.5) * H * facing, y: feet.y - (0.97 - p.y) * H) }
        let lw: CGFloat = max(1.8, H * 0.075)
        let ol: CGFloat = max(1.1, H * 0.03)
        var limbs = Path()
        for (a, b, e) in [(pose.neck, pose.lElbow, pose.lHand), (pose.neck, pose.rElbow, pose.rHand),
                          (pose.hip, pose.lKnee, pose.lFoot), (pose.hip, pose.rKnee, pose.rFoot)] {
            limbs.move(to: m(a)); limbs.addLine(to: m(b)); limbs.addLine(to: m(e))
        }
        var torso = Path()
        torso.move(to: m(pose.neck)); torso.addLine(to: m(pose.hip))
        // Pistol along the front forearm.
        let dx = pose.rHand.x - pose.rElbow.x, dy = pose.rHand.y - pose.rElbow.y
        let len = max(0.0001, hypot(dx, dy))
        let tip = CGPoint(x: pose.rHand.x + dx / len * 0.16, y: pose.rHand.y + dy / len * 0.16)
        let grip = CGPoint(x: pose.rHand.x - dy / len * 0.06, y: pose.rHand.y + abs(dx / len) * 0.06 + 0.02)
        var gun = Path()
        gun.move(to: m(pose.rHand)); gun.addLine(to: m(tip))
        gun.move(to: m(pose.rHand)); gun.addLine(to: m(grip))
        let hc = m(pose.head)
        let hr: CGFloat = pose.headR * H
        let round = StrokeStyle(lineWidth: lw + ol * 2, lineCap: .round, lineJoin: .round)
        c.stroke(limbs, with: .color(ink), style: round)
        c.stroke(torso, with: .color(ink), style: StrokeStyle(lineWidth: lw * 2.2 + ol * 2, lineCap: .round))
        c.stroke(gun, with: .color(ink), style: StrokeStyle(lineWidth: lw * 0.9 + ol * 2, lineCap: .round, lineJoin: .round))
        c.fill(Path(ellipseIn: CGRect(x: hc.x - hr - ol, y: hc.y - hr - ol, width: (hr + ol) * 2, height: (hr + ol) * 2)), with: .color(ink))
        c.stroke(limbs, with: .color(color), style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
        c.stroke(torso, with: .color(color.shade(0.12)), style: StrokeStyle(lineWidth: lw * 2.2, lineCap: .round))
        c.stroke(gun, with: .color(Color(white: 0.24)), style: StrokeStyle(lineWidth: lw * 0.9, lineCap: .round, lineJoin: .round))
        c.fill(Path(ellipseIn: CGRect(x: hc.x - hr, y: hc.y - hr, width: hr * 2, height: hr * 2)), with: .color(color))
        headwear(c, center: hc, r: hr, hat: hat, hatColor: hatColor, facing: facing, ol: ol)
        if flash {
            let f = m(tip)
            let fr: CGFloat = H * 0.16
            var star = Path()
            for k in 0..<8 {
                let a: CGFloat = CGFloat(k) / 8 * 2 * .pi
                let rr: CGFloat = k % 2 == 0 ? fr : fr * 0.4
                let pt = CGPoint(x: f.x + cos(a) * rr * (cos(a) * facing > 0.5 ? 1.5 : 1), y: f.y + sin(a) * rr)
                if k == 0 { star.move(to: pt) } else { star.addLine(to: pt) }
            }
            star.closeSubpath()
            ctx.fill(star, with: .radialGradient(Gradient(colors: [.white, Color(red: 1, green: 0.85, blue: 0.3), Color(red: 1, green: 0.5, blue: 0.1)]),
                                                 center: f, startRadius: 0, endRadius: fr * 1.4))
        }
    }

    /// Crown for you; beanie, cap and top hat for the three rivals; shades on the cap and top hat.
    static func headwear(_ c: GraphicsContext, center hc: CGPoint, r hr: CGFloat, hat: Int, hatColor: Color, facing: CGFloat, ol: CGFloat) {
        let edge = StrokeStyle(lineWidth: max(1, ol), lineJoin: .round)
        switch hat {
        case 0:
            var crown = Path()
            let y0 = hc.y - hr * 0.55, y1 = hc.y - hr * 1.45, x0 = hc.x - hr * 0.8, x1 = hc.x + hr * 0.8
            crown.move(to: CGPoint(x: x0, y: y0)); crown.addLine(to: CGPoint(x: x0, y: y1))
            crown.addLine(to: CGPoint(x: hc.x - hr * 0.4, y: y0 - hr * 0.45)); crown.addLine(to: CGPoint(x: hc.x, y: y1 - hr * 0.1))
            crown.addLine(to: CGPoint(x: hc.x + hr * 0.4, y: y0 - hr * 0.45)); crown.addLine(to: CGPoint(x: x1, y: y1))
            crown.addLine(to: CGPoint(x: x1, y: y0)); crown.closeSubpath()
            c.fill(crown, with: .color(Color(red: 1, green: 0.8, blue: 0.2)))
            c.stroke(crown, with: .color(ink), style: edge)
        case 1:
            var beanie = Path()
            beanie.addArc(center: CGPoint(x: hc.x, y: hc.y - hr * 0.1), radius: hr * 1.08, startAngle: .degrees(190), endAngle: .degrees(350), clockwise: false)
            beanie.closeSubpath()
            c.fill(beanie, with: .color(hatColor))
            c.stroke(beanie, with: .color(ink), style: edge)
            let pr = hr * 0.32
            let pom = Path(ellipseIn: CGRect(x: hc.x - pr, y: hc.y - hr * 1.28 - pr, width: pr * 2, height: pr * 2))
            c.fill(pom, with: .color(.white))
            c.stroke(pom, with: .color(ink), style: edge)
        case 2:
            var cap = Path()
            cap.addArc(center: CGPoint(x: hc.x, y: hc.y - hr * 0.15), radius: hr * 1.02, startAngle: .degrees(185), endAngle: .degrees(355), clockwise: false)
            cap.closeSubpath()
            var brim = Path()
            brim.move(to: CGPoint(x: hc.x, y: hc.y - hr * 0.2)); brim.addLine(to: CGPoint(x: hc.x + facing * hr * 1.7, y: hc.y - hr * 0.1))
            c.stroke(brim, with: .color(ink), style: StrokeStyle(lineWidth: hr * 0.45 + ol, lineCap: .round))
            c.stroke(brim, with: .color(hatColor), style: StrokeStyle(lineWidth: hr * 0.45, lineCap: .round))
            c.fill(cap, with: .color(hatColor))
            c.stroke(cap, with: .color(ink), style: edge)
            shades(c, hc: hc, hr: hr, facing: facing)
        default:
            let body = CGRect(x: hc.x - hr * 0.7, y: hc.y - hr * 2.1, width: hr * 1.4, height: hr * 1.5)
            c.fill(Path(body), with: .color(Color(white: 0.1)))
            c.stroke(Path(body), with: .color(ink), style: edge)
            c.fill(Path(CGRect(x: body.minX, y: body.maxY - hr * 0.4, width: body.width, height: hr * 0.25)), with: .color(hatColor.lit(0.2)))
            var brim = Path()
            brim.move(to: CGPoint(x: hc.x - hr * 1.15, y: body.maxY)); brim.addLine(to: CGPoint(x: hc.x + hr * 1.15, y: body.maxY))
            c.stroke(brim, with: .color(ink), style: StrokeStyle(lineWidth: hr * 0.3 + ol, lineCap: .round))
            c.stroke(brim, with: .color(Color(white: 0.12)), style: StrokeStyle(lineWidth: hr * 0.3, lineCap: .round))
            shades(c, hc: hc, hr: hr, facing: facing)
        }
    }

    static func shades(_ c: GraphicsContext, hc: CGPoint, hr: CGFloat, facing: CGFloat) {
        let lens = CGRect(x: facing > 0 ? hc.x - hr * 0.05 : hc.x - hr * 0.95, y: hc.y - hr * 0.25, width: hr, height: hr * 0.42)
        c.fill(Path(roundedRect: lens, cornerRadius: hr * 0.15), with: .color(Color(white: 0.06)))
        c.fill(Path(CGRect(x: lens.minX + hr * 0.15, y: lens.minY + hr * 0.08, width: hr * 0.25, height: hr * 0.08)), with: .color(.white.opacity(0.6)))
    }

    /// A small head with its hat, for the HUD chips.
    static func headIcon(_ ctx: GraphicsContext, center: CGPoint, r: CGFloat, color: Color, hat: Int, hatColor: Color) {
        let ol: CGFloat = 1.5
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - r - ol, y: center.y - r - ol, width: (r + ol) * 2, height: (r + ol) * 2)), with: .color(ink))
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(color))
        headwear(ctx, center: center, r: r, hat: hat, hatColor: hatColor, facing: 1, ol: ol)
    }
}

/// The static stage for this level.
private struct MayhemStage: View, Equatable {
    let level: Int
    let plats: [GMPlat]

    var body: some View {
        Canvas { ctx, s in MayhemArt.stage(ctx, s, level: level, plats: plats) }
            .allowsHitTesting(false)
    }
}

/// Dark gunmetal behind the HUD and the controls.
private struct GunmetalPanel: View, Equatable {
    var body: some View {
        Canvas { ctx, s in
            ctx.fill(Path(CGRect(origin: .zero, size: s)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.16, green: 0.17, blue: 0.2), Color(red: 0.08, green: 0.085, blue: 0.1)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height)))
            var brushed = Path()
            var y: CGFloat = 0
            while y < s.height { brushed.move(to: CGPoint(x: 0, y: y)); brushed.addLine(to: CGPoint(x: s.width, y: y)); y += 3 }
            ctx.stroke(brushed, with: .color(.white.opacity(0.025)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// A riveted steel plate, like the letters of the Gun Mayhem logo.
private struct SteelPlate: View {
    var pressed: Bool
    var red = false

    var body: some View {
        Canvas { ctx, s in
            let r = CGRect(origin: .zero, size: s).insetBy(dx: 1, dy: 1)
            let shape = Path(roundedRect: r, cornerRadius: 9)
            let top: Color = red ? Color(red: 0.93, green: 0.36, blue: 0.32) : Color(red: 0.84, green: 0.86, blue: 0.89)
            let bottom: Color = red ? Color(red: 0.6, green: 0.14, blue: 0.13) : Color(red: 0.52, green: 0.55, blue: 0.6)
            ctx.fill(shape, with: .linearGradient(Gradient(colors: pressed ? [bottom, top.shade(0.1)] : [top, bottom]),
                                                  startPoint: CGPoint(x: 0, y: r.minY), endPoint: CGPoint(x: 0, y: r.maxY)))
            ctx.stroke(Path(roundedRect: r.insetBy(dx: 2, dy: 2), cornerRadius: 7), with: .color(.white.opacity(pressed ? 0.15 : 0.45)), lineWidth: 1)
            ctx.stroke(shape, with: .color(MayhemArt.ink), lineWidth: 2)
            for (x, y) in [(r.minX + 6, r.minY + 6), (r.maxX - 6, r.minY + 6), (r.minX + 6, r.maxY - 6), (r.maxX - 6, r.maxY - 6)] {
                ctx.fill(Path(ellipseIn: CGRect(x: x - 2.2, y: y - 2.2, width: 4.4, height: 4.4)), with: .color(bottom.shade(0.35)))
                ctx.fill(Path(ellipseIn: CGRect(x: x - 1.2, y: y - 1.6, width: 1.6, height: 1.6)), with: .color(.white.opacity(0.7)))
            }
        }
    }
}

/// JUMP / FIRE: steel plates that sink on a real press and on the demo's `lit` press.
private struct SteelButtonStyle: ButtonStyle {
    var lit: Bool
    var width: CGFloat
    var height: CGFloat
    var red = false

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed || lit
        return configuration.label
            .foregroundStyle(red ? Color.white : Color(white: down ? 0.05 : 0.14))
            .shadow(color: red ? .black.opacity(0.4) : .white.opacity(0.5), radius: 0, x: 0, y: 1)
            .frame(width: width, height: height)
            .background(SteelPlate(pressed: down, red: red))
            .scaleEffect(down ? 0.94 : 1)
    }
}
