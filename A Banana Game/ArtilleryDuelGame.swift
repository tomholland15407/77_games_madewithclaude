//
//  ArtilleryDuelGame.swift
//  A Banana Game
//
//  Reflex / aiming — a Scorched-Earth style artillery duel. You and an AI gun sit on opposite
//  hills across rolling terrain, with wind pushing every shell. Set your ANGLE and POWER, then
//  tap FIRE to lob a banana shell over the hills. Land a direct hit to win — but the AI fires
//  back between your shots and gets sharper each level, so miss and it may bracket you first.
//  Run out of shells or time and you drop back to level 1. 7 levels: sharper AI, stronger wind,
//  taller terrain, fewer shells — near-impossible by L6–7.
//
//  Drawn after Scorched Earth (and the 1983 Artillery Duel): a banded gradient sky that turns from
//  day to sunset, dusk, a starry night and a red storm; layered dirt under a grassy rim; domed tanks
//  on treads (yours banana yellow, its barrel at your angle; the enemy's parked at 50°); a spinning
//  banana shell with a short comet tail (not a lasting trace); the same blasts and mushroom clouds,
//  in one Canvas. The HUD is shell pips and a wind flag; the sliders and FIRE use icons, not words.
//

import SwiftUI

enum ArtilleryDuelGame {
    static let definition = GameDefinition(
        id: "artillery-duel",
        title: "Artillery Duel",
        emoji: "🍌",
        genre: .reflex,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Set your angle and power with the sliders, and mind the wind arrow.",
                "Tap FIRE to lob a shell at the enemy gun across the terrain — a direct hit wins.",
                "The AI fires back between your shots and gets more accurate each level.",
                "Run out of shells or time and it's back to level 1.",
            ],
            bulletsVI: [
                "Đặt góc và lực bằng các thanh trượt, và để ý mũi tên gió.",
                "Chạm BẮN để nã một quả đạn vào khẩu pháo địch bên kia địa hình — trúng thẳng là thắng.",
                "AI bắn trả giữa các lượt của bạn và ngày càng chính xác hơn qua mỗi cấp.",
                "Hết đạn hoặc hết giờ sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(ArtilleryDuelView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct ArtilleryDuelView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void
    @Environment(\.isDemo) private var isDemo

    private var aiErrorDeg: Double { [16, 13, 10, 8, 6, 4, 2][min(level, 7) - 1] }
    private var windMax: Double    { [0.0, 0.06, 0.12, 0.16, 0.22, 0.28, 0.34][min(level, 7) - 1] }
    private var terrainAmp: Double { [0.10, 0.12, 0.14, 0.17, 0.20, 0.23, 0.26][min(level, 7) - 1] }
    private var shells: Int        { [8, 7, 6, 6, 5, 5, 4][min(level, 7) - 1] }
    private var timeLimit: Double  { [45, 42, 40, 38, 35, 32, 30][min(level, 7) - 1] }

    private let samples = 120
    private let gravity: Double = 0.55
    private let launchK: Double = 1.25          // power → speed scale

    private enum Phase { case aiming, playerFly, enemyFly, finishing, done }
    private struct Explosion: Identifiable { let id = UUID(); let pos: CGPoint; var age: Double = 0; let dur: Double; let mushroom: Bool }
    @State private var phase: Phase = .aiming
    @State private var angle: Double = 45
    @State private var power: Double = 0.6
    @State private var wind: Double = 0
    @State private var terrain: [Double] = []   // ground y (fraction) per sample
    @State private var playerPos = CGPoint(x: 0.12, y: 0.5)
    @State private var enemyPos = CGPoint(x: 0.88, y: 0.5)
    @State private var shell: CGPoint? = nil
    @State private var shellVel = CGVector(dx: 0, dy: 0)
    @State private var shotsLeft = 0
    @State private var timeLeft = 0.0
    @State private var status = ""
    @State private var explosions: [Explosion] = []
    @State private var pendingWin: Bool? = nil
    @State private var finishAt: Date? = nil
    @State private var shakeTick = 0
    @State private var loopTask: Task<Void, Never>?
    @State private var built = false
    @State private var demoFire = false          // demo: FIRE being pressed
    @State private var demoPower = false         // demo: power slider being dragged
    @State private var tail: [CGPoint] = []      // presentation: the shell's last few positions

    var body: some View {
        VStack(spacing: 8) {
            // Shells left (pips) and the wind (a flag, its direction and strength).
            HStack(spacing: 16) {
                ADShellPips(total: shells, left: shotsLeft)
                    .frame(width: CGFloat(shells) * (isDemo ? 8 : 10), height: isDemo ? 14 : 17)
                windLabel
            }
            .font(.system(size: isDemo ? 13 : 16, weight: .black, design: .rounded))
            .frame(height: isDemo ? 16 : 19)
            .padding(.top, isDemo ? 6 : 0)
            if !isDemo { timeBar.frame(height: 5).padding(.horizontal, 56) }

            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    // Sky and terrain never change during a duel: drawn once.
                    ADScenery(size: geo.size, terrain: terrain, level: level).equatable()

                    // Tanks, the shell and its tail, blasts and mushroom clouds: one Canvas.
                    Canvas { ctx, _ in
                        let md = min(w, h)
                        ADArt.tank(ctx, at: CGPoint(x: playerPos.x * w, y: playerPos.y * h), size: md, color: ADArt.banana,
                                   barrelDeg: angle, aimRight: true)
                        ADArt.tank(ctx, at: CGPoint(x: enemyPos.x * w, y: enemyPos.y * h), size: md, color: Color(red: 0.9, green: 0.3, blue: 0.3),
                                   barrelDeg: 50, aimRight: false)
                        if let s = shell {
                            let p = CGPoint(x: s.x * w, y: s.y * h)
                            ADArt.shell(ctx, at: p, velocity: CGVector(dx: shellVel.dx * w, dy: shellVel.dy * h), size: md * 0.05, trail: tail.map { CGPoint(x: $0.x * w, y: $0.y * h) })
                        }
                        for e in explosions {
                            drawExplosion(ctx, e, w: w, h: h)
                        }
                    }
                    .allowsHitTesting(false)

                    if !status.isEmpty {
                        Text(status)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(.black.opacity(0.5), in: Capsule())
                            .position(x: w * 0.5, y: h * 0.16)
                    }
                }
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .screenShake(shakeTick, amount: 7)
            }
            .padding(.horizontal, isDemo ? 8 : 0)

            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.07, green: 0.07, blue: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
        // A short comet tail behind the shell in flight (not a lasting trace of the shot).
        .onChange(of: shell) { _, s in
            if let s { tail.append(s); if tail.count > 8 { tail.removeFirst(tail.count - 8) } } else { tail = [] }
        }
    }

    private var windLabel: some View {
        HStack(spacing: 4) {
            ADWindFlag(strength: abs(wind), windMax: max(0.01, windMax), toRight: wind >= 0)
                .frame(width: 22, height: 16)
            Image(systemName: wind >= 0 ? "arrow.right" : "arrow.left")
                .foregroundStyle(abs(wind) > 0.18 ? .red : .white)
            Text(String(format: "%.0f", abs(wind) * 100)).foregroundStyle(.white)
        }
    }

    private func drawExplosion(_ ctx: GraphicsContext, _ e: Explosion, w: CGFloat, h: CGFloat) {
        let p = min(1, e.age / e.dur)
        let md = min(w, h)
        let base = CGPoint(x: e.pos.x * w, y: e.pos.y * h)
        let fade = 1 - max(0, (p - 0.55) / 0.45)
        let hot = Color(red: 1, green: 0.55, blue: 0.15)
        if e.mushroom {
            let ease = 1 - pow(1 - p, 2)
            let riseH = 0.24 * h * CGFloat(ease)
            let capW = CGFloat(0.05 + 0.15 * ease) * md
            let stemW = 0.055 * md
            let col = hot.mix(with: Color(white: 0.55), by: min(1, p * 1.3))
            let flashR = md * 0.12 * CGFloat(0.5 + p)
            ctx.fill(Path(ellipseIn: CGRect(x: base.x - flashR, y: base.y - flashR, width: flashR * 2, height: flashR * 2)),
                     with: .color(Color(red: 1, green: 0.92, blue: 0.45).opacity((1 - p) * 0.9)))
            ctx.fill(Path(ellipseIn: CGRect(x: base.x - capW * 1.2, y: base.y - riseH - capW * 0.9, width: capW * 2.4, height: capW * 1.8)),
                     with: .radialGradient(Gradient(colors: [hot.opacity(0.45 * fade), hot.opacity(0)]), center: CGPoint(x: base.x, y: base.y - riseH),
                                           startRadius: 0, endRadius: capW * 1.2))
            ctx.fill(Path(roundedRect: CGRect(x: base.x - stemW / 2, y: base.y - riseH, width: stemW, height: max(1, riseH)), cornerRadius: stemW / 2),
                     with: .color(col.opacity(0.85 * fade)))
            for i in 0..<3 {
                let dx = CGFloat([-1.0, 0, 1][i]) * capW * 0.30
                let cw = capW * (i == 1 ? 1.0 : 0.72)
                ctx.fill(Path(ellipseIn: CGRect(x: base.x + dx - cw / 2, y: base.y - riseH - capW * 0.32, width: cw, height: capW * 0.64)),
                         with: .color(col.opacity(0.9 * fade)))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: base.x - capW * 0.25, y: base.y - riseH - capW * 0.25, width: capW * 0.5, height: capW * 0.5)),
                     with: .color(Color(red: 1, green: 0.82, blue: 0.32).opacity((1 - p) * fade)))
        } else {
            let r = CGFloat(0.02 + 0.12 * p) * md
            ctx.stroke(Path(ellipseIn: CGRect(x: base.x - r, y: base.y - r, width: r * 2, height: r * 2)), with: .color(hot.opacity(fade)), lineWidth: 3)
            ctx.fill(Path(ellipseIn: CGRect(x: base.x - r / 2, y: base.y - r / 2, width: r, height: r)),
                     with: .color(Color(red: 1, green: 0.82, blue: 0.35).opacity((1 - p) * 0.9)))
            var dirt = Path()
            for k in 0..<6 {
                let a = Double.pi * (1.1 + Double(k) * 0.16)
                let d = r * 1.2
                let q = CGPoint(x: base.x + CGFloat(cos(a)) * d, y: base.y + CGFloat(sin(a)) * d)
                dirt.addEllipse(in: CGRect(x: q.x - 2, y: q.y - 2, width: 4, height: 4))
            }
            ctx.fill(dirt, with: .color(Color(red: 0.4, green: 0.28, blue: 0.16).opacity(fade)))
        }
    }

    private var controls: some View {
        VStack(spacing: isDemo ? 2 : 6) {
            HStack {
                HStack(spacing: 6) {
                    ADAngleIcon(deg: angle).frame(width: isDemo ? 16 : 20, height: isDemo ? 16 : 20)
                    Text("\(Int(angle))°").font(.system(size: isDemo ? 12 : 14, weight: .bold, design: .rounded)).monospacedDigit()
                }
                .foregroundStyle(.white).frame(width: isDemo ? 92 : 110, alignment: .leading)
                Slider(value: $angle, in: 10...85).tint(ADArt.banana)
                    .disabled(phase != .aiming)
            }
            HStack {
                HStack(spacing: 6) {
                    ADPowerIcon(level: power).frame(width: isDemo ? 16 : 20, height: isDemo ? 16 : 20)
                    Text("\(Int(power * 100))").font(.system(size: isDemo ? 12 : 14, weight: .bold, design: .rounded)).monospacedDigit()
                }
                .foregroundStyle(demoPower ? ADArt.banana : .white).frame(width: isDemo ? 92 : 110, alignment: .leading)
                Slider(value: $power, in: 0.2...1.0).tint(ADArt.banana)
                    .disabled(phase != .aiming)
                    .overlay {
                        // Demo: a finger riding the power thumb while it's dragged.
                        if demoPower {
                            GeometryReader { g in
                                Image(systemName: "hand.point.up.left.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.6), radius: 3)
                                    .position(x: 14 + (g.size.width - 28) * CGFloat((power - 0.2) / 0.8) + 8,
                                              y: g.size.height / 2 + 14)
                            }
                            .allowsHitTesting(false)
                        }
                    }
            }
            Button { fire() } label: {
                Image(systemName: "scope")
                    .font(.system(size: isDemo ? 16 : 19, weight: .heavy))
                    .foregroundStyle(phase == .aiming || demoFire ? Color(red: 0.25, green: 0.1, blue: 0) : Color(white: 0.6))
                    .frame(height: isDemo ? 19 : 22)   // the old FIRE text's height, so the field keeps its size
                    .frame(maxWidth: .infinity).padding(.vertical, isDemo ? 7 : 12)
                    .background(ADFireKey(ready: phase == .aiming || demoFire, lit: demoFire))
                    .scaleEffect(demoFire ? 0.94 : 1)
            }
            .buttonStyle(ADPressStyle())
            .disabled(phase != .aiming && !isDemo)
        }
        .padding(.horizontal, 20).padding(.bottom, isDemo ? 4 : 8)
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(frac < 0.3 ? Color(red: 1, green: 0.3, blue: 0.25) : ADArt.banana)
                    .frame(width: geo.size.width * frac)
            }
        }
    }

    // MARK: - Flow
    private func run() async {
        if !built { setup(); built = true }
        var last = Date(); let start = Date()
        loopTask = Task {
            while !Task.isCancelled && phase != .done {
                try? await Task.sleep(for: .seconds(0.016))
                let now = Date()
                let dt = min(0.05, now.timeIntervalSince(last)); last = now
                timeLeft = max(0, timeLimit - now.timeIntervalSince(start))
                if timeLeft <= 0, phase == .aiming || phase == .playerFly || phase == .enemyFly {
                    fail(); break
                }
                // Advance explosion animations.
                for i in explosions.indices { explosions[i].age += dt }
                explosions.removeAll { $0.age >= $0.dur }
                if phase == .playerFly || phase == .enemyFly { stepShell(dt: dt) }
                // Hold on the mushroom cloud, then resolve the round.
                if phase == .finishing, let fa = finishAt, now >= fa {
                    if pendingWin == true { win() } else { fail() }
                    break
                }
            }
        }
    }

    private func setup() {
        // Terrain: a couple of humps; guns sit on the surface at fixed x.
        let phase1 = Double.random(in: 0...(2 * .pi))
        let phase2 = Double.random(in: 0...(2 * .pi))
        var t: [Double] = []
        for i in 0..<samples {
            let x = Double(i) / Double(samples - 1)
            // Base ground around 0.72; humps rise (smaller y). Edges kept higher for the gun hills.
            let hump = sin(x * .pi * 2 + phase1) * terrainAmp + sin(x * .pi * 4 + phase2) * terrainAmp * 0.4
            let edge = -0.06 * cos(x * .pi * 2)   // slightly raise both ends
            t.append(min(0.9, max(0.28, 0.72 - hump - edge)))
        }
        terrain = t
        playerPos = CGPoint(x: 0.12, y: groundY(0.12) - 0.01)
        enemyPos = CGPoint(x: 0.88, y: groundY(0.88) - 0.01)
        wind = Double.random(in: -windMax...windMax)
        shotsLeft = shells
        shell = nil; status = ""
        angle = 45; power = 0.6
        phase = .aiming
    }

    // MARK: - Demo (live manual clip)
    // Level 1 (no wind, gentle hills) on fixed terrain, stepped at a fixed 1/60s through the real
    // `fire`/`stepShell`/`enemyTurn`. The default 45° / power 60 shell sails clean over the far
    // gun; the AI lobs back and misses (its random error pinned to +12°, inside L1's ±16°); the
    // power slider eases down to 57 and the second shell drops onto the red gun — mushroom cloud,
    // the real win(). Checked offline: power 55–59 all hit at 45°, so 57 is the middle.
    private func demoSetup() {
        let phase1 = 2.499, phase2 = 2.303
        var t: [Double] = []
        for i in 0..<samples {
            let x = Double(i) / Double(samples - 1)
            let hump = sin(x * .pi * 2 + phase1) * terrainAmp + sin(x * .pi * 4 + phase2) * terrainAmp * 0.4
            let edge = -0.06 * cos(x * .pi * 2)
            t.append(min(0.9, max(0.28, 0.72 - hump - edge)))
        }
        terrain = t
        playerPos = CGPoint(x: 0.12, y: groundY(0.12) - 0.01)
        enemyPos = CGPoint(x: 0.88, y: groundY(0.88) - 0.01)
        wind = 0
        shotsLeft = shells
        shell = nil; status = ""; explosions = []; pendingWin = nil
        angle = 45; power = 0.6
        demoFire = false; demoPower = false
        phase = .aiming
    }

    /// Step shells + explosion ages at a fixed 1/60s until the volley settles (back to aiming, or
    /// a hit is finishing).
    private func demoFly() async {
        let dt = 1.0 / 60.0
        var frames = 0
        while !Task.isCancelled && (phase == .playerFly || phase == .enemyFly) && frames < 900 {
            frames += 1
            for i in explosions.indices { explosions[i].age += dt }
            explosions.removeAll { $0.age >= $0.dur }
            stepShell(dt: dt)
            try? await Task.sleep(for: .seconds(0.016))
        }
    }

    private func demoPress() async {
        demoFire = true
        fire()
        try? await Task.sleep(for: .seconds(0.15))
        demoFire = false
    }

    private func runDemo() async {
        while !Task.isCancelled {
            demoSetup()
            built = true
            try? await Task.sleep(for: .seconds(0.8))
            await demoPress()                                  // 45° / 60 → overshoots
            await demoFly()                                    // …and the AI's reply misses
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .seconds(0.4))
            demoPower = true                                   // ease the power slider down to 57
            for k in 1...24 {
                power = 0.6 + (0.576 - 0.6) * Double(k) / 24
                try? await Task.sleep(for: .seconds(0.025))
            }
            try? await Task.sleep(for: .seconds(0.25))
            demoPower = false
            await demoPress()
            await demoFly()                                    // direct hit → finishing
            // Let the mushroom cloud bloom (as the real loop does), then the real win().
            let dt = 1.0 / 60.0
            for _ in 0..<60 {
                for i in explosions.indices { explosions[i].age += dt }
                explosions.removeAll { $0.age >= $0.dur }
                try? await Task.sleep(for: .seconds(0.016))
            }
            if phase == .finishing { if pendingWin == true { win() } else { fail() } }
            try? await Task.sleep(for: .seconds(1.0))
        }
    }

    private func groundY(_ xFrac: Double) -> Double {
        guard terrain.count == samples else { return 0.72 }
        let clamped = max(0, min(0.999, xFrac))
        let f = clamped * Double(samples - 1)
        let i = Int(floor(f))
        let frac = f - Double(i)
        let a = terrain[i]
        let b = i + 1 < samples ? terrain[i + 1] : a
        return a + (b - a) * frac
    }

    private func fire() {
        guard phase == .aiming else { return }
        shotsLeft -= 1
        launch(from: playerPos, angleDeg: angle, pwr: power, toRight: true)
        phase = .playerFly
        SoundManager.shared.tap(); Haptics.tap()
    }

    private func launch(from: CGPoint, angleDeg: Double, pwr: Double, toRight: Bool) {
        let a = angleDeg * .pi / 180
        let speed = pwr * launchK
        shell = CGPoint(x: from.x + (toRight ? 0.02 : -0.02), y: from.y - 0.02)
        shellVel = CGVector(dx: (toRight ? 1 : -1) * cos(a) * speed, dy: -sin(a) * speed)
    }

    private func stepShell(dt: Double) {
        guard var s = shell else { return }
        shellVel.dx += wind * dt
        shellVel.dy += gravity * dt
        s.x += shellVel.dx * dt
        s.y += shellVel.dy * dt
        shell = s

        // Off the sides / bottom → miss.
        if s.x < -0.05 || s.x > 1.05 || s.y > 1.05 {
            resolveMiss(at: s); return
        }
        // Target hits → mushroom cloud, then resolve.
        if phase == .playerFly, dist(s, enemyPos) < 0.045 { beginFinish(win: true, at: enemyPos); return }
        if phase == .enemyFly, dist(s, playerPos) < 0.045 { beginFinish(win: false, at: playerPos); return }
        // Ground impact.
        if s.y >= groundY(s.x) {
            resolveMiss(at: CGPoint(x: s.x, y: groundY(s.x))); return
        }
    }

    private func beginFinish(win didWin: Bool, at p: CGPoint) {
        shell = nil
        explosions.append(Explosion(pos: p, dur: 1.1, mushroom: true))
        shakeTick += 1
        pendingWin = didWin
        phase = .finishing
        finishAt = Date().addingTimeInterval(1.0)
        if didWin { Haptics.success(); SoundManager.shared.tap() }
        else { Haptics.warning(); SoundManager.shared.error() }
    }

    private func resolveMiss(at p: CGPoint) {
        shell = nil
        explosions.append(Explosion(pos: p, dur: 0.5, mushroom: false))
        shakeTick += 1
        if phase == .playerFly {
            // Enemy returns fire (unless the duel is over on shells).
            enemyTurn()
        } else {
            // Enemy missed → back to the player.
            if shotsLeft <= 0 { fail(); return }
            phase = .aiming
        }
    }

    private func enemyTurn() {
        // Aim: search angle/power whose shot lands nearest the player, then add level-based error.
        var best = (ang: 50.0, pwr: 0.6, miss: Double.greatestFiniteMagnitude)
        for angTry in stride(from: 25.0, through: 80.0, by: 5.0) {
            for pwrTry in stride(from: 0.3, through: 1.0, by: 0.05) {
                let landX = simulateLandingX(from: enemyPos, angleDeg: angTry, pwr: pwrTry, toRight: false)
                let miss = abs(landX - playerPos.x)
                if miss < best.miss { best = (angTry, pwrTry, miss) }
            }
        }
        // Demo: a fixed +12° error (inside L1's ±16°) — a clear miss mid-field.
        let jitter = isDemo ? 12 : Double.random(in: -aiErrorDeg...aiErrorDeg)
        phase = .enemyFly
        launch(from: enemyPos, angleDeg: best.ang + jitter, pwr: best.pwr, toRight: false)
        status = ""
    }

    /// Simulate a shot and return where it lands (x fraction) — for the AI's aim search.
    private func simulateLandingX(from: CGPoint, angleDeg: Double, pwr: Double, toRight: Bool) -> Double {
        let a = angleDeg * .pi / 180
        let speed = pwr * launchK
        var pos = CGPoint(x: from.x + (toRight ? 0.02 : -0.02), y: from.y - 0.02)
        var vel = CGVector(dx: (toRight ? 1 : -1) * cos(a) * speed, dy: -sin(a) * speed)
        var steps = 0
        while steps < 1200 {
            steps += 1
            vel.dx += wind * 0.016
            vel.dy += gravity * 0.016
            pos.x += vel.dx * 0.016
            pos.y += vel.dy * 0.016
            if pos.x < -0.05 || pos.x > 1.05 || pos.y > 1.05 { return pos.x }
            if pos.y >= groundY(pos.x) { return pos.x }
        }
        return pos.x
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }

    private func win() {
        guard phase != .done else { return }
        phase = .done; loopTask?.cancel()
        Haptics.success(); SoundManager.shared.tap()
        onWin()
    }
    private func fail() {
        guard phase != .done else { return }
        phase = .done; loopTask?.cancel()
        SoundManager.shared.error()
        onFail()
    }
}

// MARK: - Artillery art (after Scorched Earth)

private enum ADArt {
    static let banana = Color(red: 1, green: 0.84, blue: 0.2)

    static func hash(_ n: Double) -> Double {
        let x = sin(n) * 43758.5453
        return x - floor(x)
    }

    /// Sky top/bottom per level: day, afternoon, sunset, dusk, purple night, night, a red storm.
    static func sky(_ level: Int) -> (Color, Color) {
        let c = { (r: Double, g: Double, b: Double) in Color(red: r, green: g, blue: b) }
        switch min(max(level, 1), 7) {
        case 1: return (c(0.34, 0.58, 0.92), c(0.74, 0.87, 0.98))
        case 2: return (c(0.38, 0.54, 0.88), c(0.96, 0.85, 0.7))
        case 3: return (c(0.36, 0.3, 0.6), c(1, 0.62, 0.36))
        case 4: return (c(0.24, 0.2, 0.46), c(0.86, 0.46, 0.46))
        case 5: return (c(0.12, 0.1, 0.3), c(0.42, 0.24, 0.44))
        case 6: return (c(0.04, 0.05, 0.16), c(0.18, 0.14, 0.3))
        default: return (c(0.16, 0.03, 0.05), c(0.5, 0.14, 0.1))
        }
    }

    /// A Scorched Earth tank: treads, a dome, and the barrel at `barrelDeg`.
    static func tank(_ ctx: GraphicsContext, at base: CGPoint, size md: CGFloat, color: Color, barrelDeg: Double, aimRight: Bool) {
        let a = barrelDeg * .pi / 180
        let bl = md * 0.06
        let dome = CGPoint(x: base.x, y: base.y - md * 0.006)
        var barrel = Path()
        barrel.move(to: dome)
        barrel.addLine(to: CGPoint(x: dome.x + CGFloat(cos(a)) * bl * (aimRight ? 1 : -1), y: dome.y - CGFloat(sin(a)) * bl))
        ctx.stroke(barrel, with: .color(.black.opacity(0.6)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        ctx.stroke(barrel, with: .color(color.mix(with: .black, by: 0.2)), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        let r = md * 0.024
        var d = Path()
        d.addArc(center: dome, radius: r, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        d.closeSubpath()
        ctx.fill(d, with: .linearGradient(Gradient(colors: [color.mix(with: .white, by: 0.35), color, color.mix(with: .black, by: 0.3)]),
                                          startPoint: CGPoint(x: dome.x, y: dome.y - r), endPoint: CGPoint(x: dome.x, y: dome.y)))
        ctx.stroke(d, with: .color(.black.opacity(0.6)), lineWidth: 1.2)
        let tread = CGRect(x: base.x - md * 0.036, y: dome.y - 1, width: md * 0.072, height: md * 0.018)
        ctx.fill(Path(roundedRect: tread, cornerRadius: tread.height / 2), with: .color(Color(white: 0.2)))
        var wheels = Path()
        for k in 0..<4 {
            let x = tread.minX + tread.width * (0.16 + CGFloat(k) * 0.225)
            wheels.addEllipse(in: CGRect(x: x - tread.height * 0.3, y: tread.midY - tread.height * 0.3, width: tread.height * 0.6, height: tread.height * 0.6))
        }
        ctx.fill(wheels, with: .color(Color(white: 0.5)))
    }

    /// The banana shell, pointing along its flight, with a short comet tail.
    static func shell(_ ctx: GraphicsContext, at p: CGPoint, velocity v: CGVector, size s: CGFloat, trail: [CGPoint]) {
        if trail.count > 1 {
            for i in 1..<trail.count {
                var seg = Path()
                seg.move(to: trail[i - 1]); seg.addLine(to: trail[i])
                let f = Double(i) / Double(trail.count)
                ctx.stroke(seg, with: .color(Color(red: 1, green: 0.92, blue: 0.6).opacity(0.7 * f)), style: StrokeStyle(lineWidth: s * 0.3 * CGFloat(f), lineCap: .round))
            }
        }
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        g.rotate(by: .radians(atan2(Double(v.dy), Double(v.dx))))
        g.scaleBy(x: s, y: s)
        var b = Path()
        b.move(to: CGPoint(x: -0.5, y: -0.1))
        b.addQuadCurve(to: CGPoint(x: 0.5, y: -0.12), control: CGPoint(x: 0, y: 0.6))
        b.addQuadCurve(to: CGPoint(x: -0.5, y: -0.1), control: CGPoint(x: 0, y: 0.1))
        b.closeSubpath()
        g.fill(b, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.96, blue: 0.55), Color(red: 0.98, green: 0.76, blue: 0.14)]),
                                        startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: 0.3)))
        g.stroke(b, with: .color(Color(red: 0.3, green: 0.2, blue: 0.03)), lineWidth: 0.07)
        g.fill(Path(roundedRect: CGRect(x: 0.44, y: -0.22, width: 0.14, height: 0.14), cornerRadius: 0.03), with: .color(Color(red: 0.42, green: 0.27, blue: 0.08)))
    }
}

/// The sky in Scorched Earth's banded gradient (stars at night) and the terrain: a grassy rim over
/// layered dirt. Drawn once per duel.
private struct ADScenery: View, Equatable {
    let size: CGSize
    let terrain: [Double]
    let level: Int

    var body: some View {
        Canvas { ctx, _ in
            let w = size.width, h = size.height
            let (top, bottom) = ADArt.sky(level)
            let bands = 12
            for k in 0..<bands {
                let t = Double(k) / Double(bands - 1)
                ctx.fill(Path(CGRect(x: 0, y: h * CGFloat(k) / CGFloat(bands), width: w, height: h / CGFloat(bands) + 1)),
                         with: .color(top.mix(with: bottom, by: t)))
            }
            if level >= 5 {
                var stars = Path()
                for i in 0..<50 {
                    let d: CGFloat = 1 + CGFloat(ADArt.hash(Double(i) * 1.7)) * 1.4
                    stars.addEllipse(in: CGRect(x: CGFloat(ADArt.hash(Double(i) * 12.9)) * w, y: CGFloat(ADArt.hash(Double(i) * 78.2)) * h * 0.6, width: d, height: d))
                }
                ctx.fill(stars, with: .color(.white.opacity(0.7)))
            }
            guard terrain.count > 1 else { return }
            var ridge = Path()
            for (i, t) in terrain.enumerated() {
                let p = CGPoint(x: CGFloat(i) / CGFloat(terrain.count - 1) * w, y: CGFloat(t) * h)
                if i == 0 { ridge.move(to: p) } else { ridge.addLine(to: p) }
            }
            var land = ridge
            land.addLine(to: CGPoint(x: w, y: h)); land.addLine(to: CGPoint(x: 0, y: h)); land.closeSubpath()
            let night = level >= 5
            let dirt0 = night ? Color(red: 0.3, green: 0.22, blue: 0.2) : Color(red: 0.62, green: 0.44, blue: 0.26)
            let dirt1 = night ? Color(red: 0.14, green: 0.1, blue: 0.1) : Color(red: 0.36, green: 0.24, blue: 0.14)
            let topY = CGFloat(terrain.min() ?? 0.3) * h
            ctx.fill(land, with: .linearGradient(Gradient(colors: [dirt0, dirt1]), startPoint: CGPoint(x: 0, y: topY), endPoint: CGPoint(x: 0, y: h)))
            var strata = ctx
            strata.clip(to: land)
            var y = topY + 10
            var k = 0
            while y < h {
                var band = Path()
                band.move(to: CGPoint(x: 0, y: y))
                var x: CGFloat = 0
                while x < w {
                    let nx = x + 40
                    band.addQuadCurve(to: CGPoint(x: nx, y: y), control: CGPoint(x: x + 20, y: y + CGFloat(ADArt.hash(Double(k * 11) + Double(x)) - 0.5) * 8))
                    x = nx
                }
                strata.stroke(band, with: .color(.black.opacity(0.12)), lineWidth: 3)
                y += 14; k += 1
            }
            let grass = night ? Color(red: 0.18, green: 0.3, blue: 0.2) : Color(red: 0.36, green: 0.62, blue: 0.26)
            ctx.stroke(ridge, with: .color(grass), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            ctx.stroke(ridge, with: .color(grass.mix(with: .white, by: 0.25)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

/// Shells left as little rounds.
private struct ADShellPips: View {
    let total: Int
    let left: Int

    var body: some View {
        Canvas { ctx, size in
            let n = max(1, total)
            let slot = size.width / CGFloat(n)
            for i in 0..<n {
                let rect = CGRect(x: CGFloat(i) * slot + slot * 0.2, y: size.height * 0.15, width: slot * 0.6, height: size.height * 0.8)
                var round = Path()
                round.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                round.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.width * 0.5))
                round.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + rect.width * 0.5), control: CGPoint(x: rect.midX, y: rect.minY - rect.width * 0.3))
                round.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                round.closeSubpath()
                if i < left {
                    ctx.fill(round, with: .color(ADArt.banana))
                } else {
                    ctx.stroke(round, with: .color(.white.opacity(0.3)), lineWidth: 1)
                }
            }
        }
    }
}

/// A wind flag that streams further in stronger wind.
private struct ADWindFlag: View {
    let strength: Double
    let windMax: Double
    let toRight: Bool

    var body: some View {
        Canvas { ctx, size in
            var g = ctx
            if !toRight { g.translateBy(x: size.width, y: 0); g.scaleBy(x: -1, y: 1) }
            let w = size.width, h = size.height
            var pole = Path()
            pole.move(to: CGPoint(x: w * 0.1, y: h * 0.05)); pole.addLine(to: CGPoint(x: w * 0.1, y: h))
            g.stroke(pole, with: .color(.white), lineWidth: 1.5)
            let f = CGFloat(max(0.15, min(1, strength / windMax)))
            var sock = Path()
            sock.move(to: CGPoint(x: w * 0.1, y: h * 0.1))
            sock.addLine(to: CGPoint(x: w * 0.1 + w * 0.85 * f, y: h * (0.2 + 0.1 * (1 - f))))
            sock.addLine(to: CGPoint(x: w * 0.1 + w * 0.85 * f, y: h * (0.42 - 0.1 * (1 - f))))
            sock.addLine(to: CGPoint(x: w * 0.1, y: h * 0.52))
            sock.closeSubpath()
            g.fill(sock, with: .color(Color(red: 1, green: 0.45, blue: 0.25)))
        }
    }
}

/// The angle icon: a little protractor arc with the barrel line at the current angle.
private struct ADAngleIcon: View {
    let deg: Double

    var body: some View {
        Canvas { ctx, size in
            let o = CGPoint(x: size.width * 0.12, y: size.height * 0.88)
            let r = size.width * 0.78
            var arc = Path()
            arc.addArc(center: o, radius: r * 0.6, startAngle: .degrees(-deg), endAngle: .degrees(0), clockwise: false)
            ctx.stroke(arc, with: .color(.white.opacity(0.6)), lineWidth: 1.5)
            var base = Path()
            base.move(to: o); base.addLine(to: CGPoint(x: o.x + r, y: o.y))
            let a = deg * .pi / 180
            base.move(to: o); base.addLine(to: CGPoint(x: o.x + CGFloat(cos(a)) * r, y: o.y - CGFloat(sin(a)) * r))
            ctx.stroke(base, with: .color(.white), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}

/// The power icon: three rising bars, lit up to the current power.
private struct ADPowerIcon: View {
    let level: Double

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            for k in 0..<3 {
                let bh = h * CGFloat(0.35 + 0.3 * Double(k))
                let rect = CGRect(x: w * (0.08 + 0.32 * CGFloat(k)), y: h - bh, width: w * 0.24, height: bh)
                let on = level >= 0.2 + 0.8 * Double(k) / 3
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(on ? ADArt.banana : .white.opacity(0.3)))
            }
        }
    }
}

/// FIRE: a yellow key (grey while a shell is in the air).
private struct ADFireKey: View {
    let ready: Bool
    let lit: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: ready ? [Color(red: 1, green: 0.9, blue: 0.4), Color(red: 0.95, green: 0.68, blue: 0.14)] : [Color(white: 0.34), Color(white: 0.24)],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(lit ? 0.95 : 0.2), lineWidth: lit ? 2.5 : 1)
        }
    }
}

private struct ADPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}
