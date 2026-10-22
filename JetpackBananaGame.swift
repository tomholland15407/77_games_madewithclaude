//
//  JetpackBananaGame.swift
//  A Banana Game
//
//  Reflex — a jetpack flight through an industrial corridor. HOLD ANYWHERE to thrust up,
//  release to fall under gravity. Instead of static electric gaps (too Flappy-like), the
//  hazards are small flying monsters that drift in from the right and bob up and down on
//  their own sine paths — so the game is about DODGING moving creatures, not threading
//  fixed slots. Touch a monster, the ceiling, or the floor and you fail back to level 1.
//  Fly the level's target distance to win. 7 levels: more/faster monsters with wider bob,
//  faster scroll, and the facility descends from a clean lab to a red-alert reactor.
//
//  Drawn as Jetpack Joyride's secret lab: riveted blue-steel wall panels with the yellow stripe,
//  hazard-striped doorways, a steel ceiling beam and a grated walkway, all scrolling 1:1 with the
//  monsters (one pre-drawn strip, slid by an offset). Red-alert beacons sweep the corridor at 4–5,
//  and at 6–7 the upper panels become windows onto space. The banana wears Barry's machine-gun
//  jetpack — held, it sprays tracers that spark on the floor — and the monsters are escaped lab
//  mutants: bat-winged blobs that glare at the banana. The distance is a chunky outlined counter.
//

import SwiftUI

enum JetpackBananaGame {
    static let definition = GameDefinition(
        id: "jetpack-banana",
        title: "Jetpack Banana",
        emoji: "🍌",
        genre: .reflex,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Hold anywhere to fire the jetpack and rise; release to fall under gravity.",
                "Little flying monsters drift in and bob up and down — dodge them.",
                "Fly the level's target distance to win.",
                "Touch a monster, the ceiling, or the floor and you're back to level 1.",
            ],
            bulletsVI: [
                "Giữ bất kỳ đâu để phụt phản lực bay lên; thả ra để rơi theo trọng lực.",
                "Những con quái bay nhỏ trôi vào và nhấp nhô lên xuống — hãy né chúng.",
                "Bay đủ quãng đường mục tiêu của cấp để thắng.",
                "Chạm quái, trần, hoặc sàn sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(JetpackBananaView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

// The menacing hues — desaturated cool/warm so banana-yellow stays the only warm hero.
private let monsterColors: [Color] = [
    Color(red: 0.86, green: 0.28, blue: 0.34),   // red
    Color(red: 0.55, green: 0.36, blue: 0.85),   // violet
    Color(red: 0.25, green: 0.72, blue: 0.74),   // teal
    Color(red: 0.85, green: 0.45, blue: 0.24),   // ember
    Color(red: 0.80, green: 0.30, blue: 0.62),   // magenta
    Color(red: 0.40, green: 0.66, blue: 0.35)    // toxic green
]

struct JetpackBananaView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    // MARK: Difficulty (index by level 1...7)
    private var scrollSpeed: CGFloat { [0.40, 0.46, 0.53, 0.60, 0.68, 0.77, 0.87][min(level, 7) - 1] }
    private var targetDist: CGFloat  { [4, 5, 6, 7, 8, 9, 10][min(level, 7) - 1] }
    // Horizontal gap between monster spawns — shrinks so the corridor gets crowded.
    private var spacing: CGFloat     { [0.85, 0.74, 0.65, 0.57, 0.50, 0.44, 0.39][min(level, 7) - 1] }
    // Peak vertical bob amplitude (fraction of height) — widens each level.
    private var bobAmp: CGFloat      { [0.08, 0.11, 0.14, 0.17, 0.20, 0.23, 0.26][min(level, 7) - 1] }
    // How fast the monsters oscillate — faster later so the bob is harder to read.
    private var bobSpeedBase: CGFloat { [1.2, 1.4, 1.7, 2.0, 2.3, 2.7, 3.1][min(level, 7) - 1] }
    // Chance a spawn is a *pair* stacked at different heights (extra density late).
    private var pairChance: Double   { [0.0, 0.0, 0.10, 0.20, 0.32, 0.45, 0.60][min(level, 7) - 1] }

    private let bananaX: CGFloat = 0.28
    private let ceiling: CGFloat = 0.03
    private let floor: CGFloat = 0.85
    private let bananaHalfY: CGFloat = 0.045
    private let bananaHalfX: CGFloat = 0.05
    private let monsterHalfY: CGFloat = 0.045
    private let monsterHalfX: CGFloat = 0.042
    private let gravity: CGFloat = 1.8
    private let thrust: CGFloat = 3.4
    private let maxV: CGFloat = 1.1

    // MARK: State
    private struct Monster: Identifiable {
        let id = UUID()
        var x: CGFloat            // horizontal position, 1.15 (off right) → -0.2 (off left)
        let baseY: CGFloat        // center of the vertical oscillation
        let amp: CGFloat          // bob amplitude
        let spd: CGFloat          // bob angular speed
        let phase: CGFloat        // random phase so monsters don't sync
        let color: Color
    }

    @State private var monsters: [Monster] = []
    @State private var bananaY: CGFloat = 0.4
    @State private var vy: CGFloat = 0
    @State private var thrusting = false
    @State private var distance: CGFloat = 0
    @State private var t = 0.0
    @State private var done = false
    @State private var loopTask: Task<Void, Never>?
    @State private var demoSpawn = 0          // demo: index into the fixed monster script

    /// Live vertical position of a monster, clamped inside the corridor.
    private func monsterY(_ m: Monster) -> CGFloat {
        let y = m.baseY + m.amp * CGFloat(sin(t * Double(m.spd) + Double(m.phase)))
        return min(floor - monsterHalfY, max(ceiling + monsterHalfY, y))
    }

    var body: some View {
        VStack(spacing: 4) {
            if !isDemo {
                JBCounter(percent: Int(min(distance, targetDist) / targetDist * 100))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)
                    .frame(height: 31)
            }

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let module = JBArt.module(w)

                ZStack {
                    // The corridor is one pre-drawn strip, two patterns wide, slid 1:1 with the monsters.
                    Color.clear
                        .overlay(alignment: .leading) {
                            JBCorridor(level: level, size: CGSize(width: module * 6, height: h)).equatable()
                                .frame(width: module * 6, height: h)
                                .offset(x: -(distance * w).truncatingRemainder(dividingBy: module * 3))
                        }
                        .clipped()

                    // Alarm beacons, the mutants, the banana and its tracers: one Canvas.
                    Canvas { ctx, size in drawScene(ctx, size: size) }

                    // Hold-to-fly area.
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { _ in if !done { thrusting = true } }
                            .onEnded { _ in thrusting = false })

                    // Demo: the hold-anywhere finger — it presses down (glow + shrink) while thrusting.
                    if isDemo {
                        ZStack {
                            Circle().fill(.white.opacity(thrusting ? 0.28 : 0))
                                .frame(width: 46, height: 46)
                            Image(systemName: "hand.point.up.left.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white.opacity(thrusting ? 1 : 0.6))
                                .shadow(color: .black.opacity(0.6), radius: 3)
                                .offset(x: 8, y: 10)
                        }
                        .scaleEffect(thrusting ? 0.88 : 1)
                        .animation(.easeOut(duration: 0.08), value: thrusting)
                        .position(x: w * 0.76, y: h * 0.6)
                    }
                    VignetteOverlay(strength: 0.3)
                }
                .frame(width: w, height: h)
                .clipped()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.1, blue: 0.15))
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
    }

    /// Everything that moves. Each mutant's body fills its hit box; the banana is drawn about its
    /// own; the ceiling and floor lines in the corridor strip are exactly `ceiling` and `floor`.
    private func drawScene(_ ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        if level == 4 || level == 5 {
            JBArt.alarm(ctx, size: size, scroll: distance * w, module: JBArt.module(w), ceilingY: ceiling * h, t: t)
        }
        for m in monsters {
            JBArt.mutant(ctx, at: CGPoint(x: m.x * w, y: monsterY(m) * h), halfWidth: monsterHalfX * w,
                         halfHeight: monsterHalfY * h, color: m.color, flap: t * 13 + Double(m.phase))
        }
        let hero = CGPoint(x: bananaX * w, y: bananaY * h)
        let bh = h * 0.1
        let tilt = Angle.degrees(Double(max(-18, min(22, vy * 20))))
        let nozzle = JBArt.nozzle(hero: hero, height: bh, tilt: tilt)
        if thrusting { JBArt.gunfire(ctx, nozzle: nozzle, floorY: floor * h, t: t) }
        else { JBArt.idleSmoke(ctx, nozzle: nozzle, t: t) }
        JBArt.banana(ctx, at: hero, height: bh, tilt: tilt)
        if thrusting { JBArt.muzzleFlash(ctx, at: nozzle, size: bh, t: t) }
    }

    // MARK: - Flow
    private func run() async {
        setup()
        var last = Date()
        loopTask = Task {
            while !Task.isCancelled && !done {
                try? await Task.sleep(for: .seconds(0.016))
                let now = Date()
                let dt = CGFloat(min(0.05, now.timeIntervalSince(last)))
                last = now
                step(dt: dt)
            }
        }
    }

    private func setup() {
        monsters = []
        bananaY = 0.4; vy = 0; thrusting = false; distance = 0; t = 0; done = false
        spawn(at: 1.15)      // first monster ahead
    }

    /// Spawn one monster (or a stacked pair on later levels) at horizontal position `x`.
    private func spawn(at x: CGFloat) {
        monsters.append(makeMonster(at: x, band: 0.20...(floor - 0.10)))
        if Double.random(in: 0..<1) < pairChance {
            // A second monster slightly ahead, in the opposite half, for a tighter dodge.
            let lowHalf = Bool.random()
            let band: ClosedRange<CGFloat> = lowHalf ? 0.20...0.45 : (floor - 0.35)...(floor - 0.10)
            monsters.append(makeMonster(at: x + CGFloat.random(in: 0.10...0.20), band: band))
        }
    }

    private func makeMonster(at x: CGFloat, band: ClosedRange<CGFloat>) -> Monster {
        if isDemo {
            let d = Self.demoMonsters[demoSpawn % Self.demoMonsters.count]
            demoSpawn += 1
            return Monster(x: x, baseY: d.base, amp: d.amp, spd: d.spd, phase: d.ph,
                           color: monsterColors[demoSpawn % monsterColors.count])
        }
        return Monster(
            x: x,
            baseY: CGFloat.random(in: band),
            amp: bobAmp * CGFloat.random(in: 0.6...1.0),
            spd: bobSpeedBase * CGFloat.random(in: 0.8...1.2),
            phase: CGFloat.random(in: 0...(2 * .pi)),
            color: monsterColors.randomElement()!
        )
    }

    // MARK: - Demo (live manual clip)
    // Level 1 (distance 4, single monsters) on a fixed monster script, stepped at a fixed 1/60s
    // through the real `step`. The finger holds/releases (the real `thrusting`) to hold a lane:
    // it predicts where the next monster will bob to when it arrives and aims ~0.22 of the field
    // to the far side of it. Clears every monster with room to spare (checked offline) → win().
    private static let demoMonsters: [(base: CGFloat, amp: CGFloat, spd: CGFloat, ph: CGFloat)] = [
        (0.40, 0.07, 1.2, 0.0), (0.62, 0.08, 1.0, 1.5), (0.30, 0.06, 1.4, 3.0),
        (0.55, 0.08, 1.1, 0.7), (0.45, 0.07, 1.3, 2.2), (0.35, 0.08, 0.9, 4.0),
    ]

    private func runDemo() async {
        let dt: CGFloat = 1.0 / 60.0
        while !Task.isCancelled {
            demoSpawn = 0
            setup()
            try? await Task.sleep(for: .seconds(0.4))
            while !Task.isCancelled && !done {
                // Lane choice: the far side of where the next monster will be on arrival.
                var targetY: CGFloat = 0.44
                if let m = monsters.filter({ $0.x + monsterHalfX + bananaHalfX > bananaX }).min(by: { $0.x < $1.x }) {
                    let arrive = max(0, (m.x - bananaX) / scrollSpeed)
                    let y = min(floor - monsterHalfY, max(ceiling + monsterHalfY,
                                m.baseY + m.amp * CGFloat(sin((t + Double(arrive)) * Double(m.spd) + Double(m.phase)))))
                    targetY = y > 0.44 ? max(0.16, y - 0.22) : min(0.72, y + 0.22)
                }
                thrusting = bananaY + vy * 0.18 > targetY
                step(dt: dt)
                try? await Task.sleep(for: .seconds(0.016))
            }
            thrusting = false
            // Target distance flown → the real win() ran (onWin is a no-op). Hold, then loop.
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    private func step(dt: CGFloat) {
        guard !done else { return }
        t += Double(dt)

        // Flight physics.
        vy += (thrusting ? -thrust : gravity) * dt
        vy = max(-maxV, min(maxV, vy))
        bananaY += vy * dt

        // Scroll the world.
        for i in monsters.indices { monsters[i].x -= scrollSpeed * dt }
        distance += scrollSpeed * dt
        if let last = monsters.map(\.x).max(), last < 1.15 - spacing {
            spawn(at: 1.15)
        }
        monsters.removeAll { $0.x < -0.2 }

        // Ceiling / floor fail.
        if bananaY <= ceiling + bananaHalfY { fail(); return }
        if bananaY >= floor - bananaHalfY { fail(); return }

        // Monster collision (axis-aligned overlap on the small sprites).
        for m in monsters where abs(m.x - bananaX) < monsterHalfX + bananaHalfX {
            if abs(monsterY(m) - bananaY) < monsterHalfY + bananaHalfY { fail(); return }
        }

        if distance >= targetDist { win(); return }
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

// MARK: - Jetpack Joyride art

private struct JBPalette {
    let wallHi: Color, wallLo: Color, edge: Color, seam: Color
    let stripe: Color, wainscot: Color, beam: Color, windows: Bool
}

private enum JBArt {
    /// One wall module (two panels); the corridor pattern repeats every three (a door in the third).
    static func module(_ w: CGFloat) -> CGFloat { max(160, w * 0.62) }

    static func palette(_ level: Int) -> JBPalette {
        switch min(max(level, 1), 7) {
        case 1...3:
            return JBPalette(wallHi: Color(red: 0.4, green: 0.5, blue: 0.64), wallLo: Color(red: 0.29, green: 0.37, blue: 0.52),
                             edge: Color(red: 0.62, green: 0.72, blue: 0.84), seam: Color(red: 0.14, green: 0.18, blue: 0.27),
                             stripe: Color(red: 0.98, green: 0.8, blue: 0.2), wainscot: Color(red: 0.21, green: 0.26, blue: 0.36),
                             beam: Color(red: 0.24, green: 0.27, blue: 0.34), windows: false)
        case 4, 5:
            return JBPalette(wallHi: Color(red: 0.46, green: 0.34, blue: 0.4), wallLo: Color(red: 0.33, green: 0.22, blue: 0.28),
                             edge: Color(red: 0.7, green: 0.54, blue: 0.58), seam: Color(red: 0.18, green: 0.1, blue: 0.13),
                             stripe: Color(red: 0.95, green: 0.24, blue: 0.2), wainscot: Color(red: 0.25, green: 0.16, blue: 0.2),
                             beam: Color(red: 0.26, green: 0.2, blue: 0.24), windows: false)
        default:
            return JBPalette(wallHi: Color(red: 0.24, green: 0.29, blue: 0.4), wallLo: Color(red: 0.16, green: 0.2, blue: 0.3),
                             edge: Color(red: 0.42, green: 0.5, blue: 0.64), seam: Color(red: 0.07, green: 0.09, blue: 0.15),
                             stripe: Color(red: 0.25, green: 0.88, blue: 0.84), wainscot: Color(red: 0.12, green: 0.15, blue: 0.23),
                             beam: Color(red: 0.16, green: 0.18, blue: 0.25), windows: true)
        }
    }

    static func hash(_ n: Double) -> Double {
        let v = sin(n * 12.9898) * 43758.5453
        return v - floor(v)
    }

    static func rivets(_ ctx: GraphicsContext, _ r: CGRect, color: Color) {
        var p = Path()
        for q in [CGPoint(x: r.minX + 6, y: r.minY + 6), CGPoint(x: r.maxX - 6, y: r.minY + 6),
                  CGPoint(x: r.minX + 6, y: r.maxY - 6), CGPoint(x: r.maxX - 6, y: r.maxY - 6)] {
            p.addEllipse(in: CGRect(x: q.x - 2.2, y: q.y - 2.2, width: 4.4, height: 4.4))
        }
        ctx.fill(p, with: .color(color))
    }

    // MARK: Moving things

    /// Red-alert beacons on the ceiling beam, scrolling with the wall, each sweeping two red beams.
    static func alarm(_ ctx: GraphicsContext, size: CGSize, scroll: CGFloat, module m: CGFloat, ceilingY: CGFloat, t: Double) {
        let w = size.width, h = size.height
        let gap = m * 1.5
        var x = -scroll.truncatingRemainder(dividingBy: gap) + gap * 0.3
        var k = 0.0
        while x < w + gap {
            let base = CGPoint(x: x, y: ceilingY)
            for beam in 0..<2 {
                let a = t * 4 + k + Double(beam) * .pi
                let dir = CGPoint(x: CGFloat(cos(a)), y: abs(CGFloat(sin(a))) + 0.35)
                let len = h * 0.7
                var wedge = Path()
                wedge.move(to: base)
                wedge.addLine(to: CGPoint(x: base.x + (dir.x - 0.2) * len, y: base.y + dir.y * len))
                wedge.addLine(to: CGPoint(x: base.x + (dir.x + 0.2) * len, y: base.y + dir.y * len))
                wedge.closeSubpath()
                ctx.fill(wedge, with: .linearGradient(Gradient(colors: [Color.red.opacity(0.28), Color.red.opacity(0)]),
                                                      startPoint: base, endPoint: CGPoint(x: base.x + dir.x * len, y: base.y + dir.y * len)))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: x - 7, y: ceilingY - 4, width: 14, height: 11)), with: .color(Color(red: 1, green: 0.2, blue: 0.16)))
            ctx.fill(Path(ellipseIn: CGRect(x: x - 3, y: ceilingY - 1, width: 5, height: 4)), with: .color(.white.opacity(0.8)))
            x += gap
            k += 1.7
        }
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.red.opacity(0.05 + 0.04 * sin(t * 7))))
    }

    /// An escaped lab mutant: a bat-winged blob whose body fills the hit box, glaring toward the banana.
    static func mutant(_ ctx: GraphicsContext, at c: CGPoint, halfWidth hw: CGFloat, halfHeight hh: CGFloat, color: Color, flap: Double) {
        let ink = Color(red: 0.08, green: 0.05, blue: 0.1)
        let lift = CGFloat(sin(flap)) * hh * 0.5
        for side in [-1.0, 1.0] as [CGFloat] {
            var wing = Path()
            let sh = CGPoint(x: c.x + side * hw * 0.55, y: c.y - hh * 0.25)
            let tip = CGPoint(x: c.x + side * hw * 2.0, y: c.y - hh * 0.55 - lift)
            wing.move(to: sh)
            wing.addQuadCurve(to: tip, control: CGPoint(x: c.x + side * hw * 1.3, y: c.y - hh * 0.95 - lift * 0.6))
            let trail = [CGPoint(x: c.x + side * hw * 1.75, y: c.y - hh * 0.08 - lift * 0.7),
                         CGPoint(x: c.x + side * hw * 1.35, y: c.y + hh * 0.02 - lift * 0.45),
                         CGPoint(x: c.x + side * hw * 0.8, y: c.y + hh * 0.18)]
            var from = tip
            for q in trail {
                wing.addQuadCurve(to: q, control: CGPoint(x: (from.x + q.x) / 2 - side * hw * 0.05, y: (from.y + q.y) / 2 - hh * 0.2))
                from = q
            }
            wing.closeSubpath()
            ctx.fill(wing, with: .color(color.shade(0.38)))
            ctx.stroke(wing, with: .color(ink), style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
        }
        // Horns.
        for side in [-1.0, 1.0] as [CGFloat] {
            var horn = Path()
            horn.move(to: CGPoint(x: c.x + side * hw * 0.25, y: c.y - hh * 0.8))
            horn.addLine(to: CGPoint(x: c.x + side * hw * 0.5, y: c.y - hh * 1.12))
            horn.addLine(to: CGPoint(x: c.x + side * hw * 0.62, y: c.y - hh * 0.66))
            horn.closeSubpath()
            ctx.fill(horn, with: .color(color.shade(0.2)))
            ctx.stroke(horn, with: .color(ink), lineWidth: 1.1)
        }
        let body = Path(ellipseIn: CGRect(x: c.x - hw, y: c.y - hh * 0.92, width: hw * 2, height: hh * 1.84))
        ctx.fill(body, with: .radialGradient(Gradient(colors: [color.lit(0.4), color, color.shade(0.35)]),
                                             center: CGPoint(x: c.x - hw * 0.35, y: c.y - hh * 0.45), startRadius: 0, endRadius: hh * 1.6))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - hw * 0.62, y: c.y + hh * 0.08, width: hw * 1.24, height: hh * 0.7)), with: .color(color.lit(0.3).opacity(0.55)))
        ctx.stroke(body, with: .color(ink), lineWidth: 1.6)
        // Eyes glaring left, with angry brows.
        for (ex, er) in [(-0.38, 0.3), (0.16, 0.26)] as [(CGFloat, CGFloat)] {
            let e = CGRect(x: c.x + hw * ex - hw * er, y: c.y - hh * 0.5, width: hw * er * 2, height: hh * 0.42)
            ctx.fill(Path(ellipseIn: e), with: .color(.white))
            ctx.stroke(Path(ellipseIn: e), with: .color(ink), lineWidth: 1)
            ctx.fill(Path(ellipseIn: CGRect(x: e.minX + e.width * 0.08, y: e.midY - e.height * 0.2, width: e.width * 0.5, height: e.height * 0.5)), with: .color(ink))
        }
        var brows = Path()
        brows.move(to: CGPoint(x: c.x - hw * 0.72, y: c.y - hh * 0.62)); brows.addLine(to: CGPoint(x: c.x - hw * 0.12, y: c.y - hh * 0.46))
        brows.move(to: CGPoint(x: c.x + hw * 0.4, y: c.y - hh * 0.6)); brows.addLine(to: CGPoint(x: c.x - hw * 0.02, y: c.y - hh * 0.46))
        ctx.stroke(brows, with: .color(ink), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        // Fanged grin.
        let mouth = Path(roundedRect: CGRect(x: c.x - hw * 0.62, y: c.y + hh * 0.12, width: hw * 1.1, height: hh * 0.3), cornerRadius: hh * 0.12)
        ctx.fill(mouth, with: .color(Color(red: 0.25, green: 0.04, blue: 0.08)))
        var fangs = Path()
        for fx in [-0.46, -0.1, 0.26] as [CGFloat] {
            fangs.move(to: CGPoint(x: c.x + hw * fx, y: c.y + hh * 0.12))
            fangs.addLine(to: CGPoint(x: c.x + hw * (fx + 0.09), y: c.y + hh * 0.27))
            fangs.addLine(to: CGPoint(x: c.x + hw * (fx + 0.18), y: c.y + hh * 0.12))
            fangs.closeSubpath()
        }
        ctx.fill(fangs, with: .color(.white))
    }

    static func nozzle(hero: CGPoint, height bh: CGFloat, tilt: Angle) -> CGPoint {
        let local = CGPoint(x: -bh * 0.34, y: bh * 0.52)
        let a = tilt.radians
        return CGPoint(x: hero.x + local.x * CGFloat(cos(a)) - local.y * CGFloat(sin(a)),
                       y: hero.y + local.x * CGFloat(sin(a)) + local.y * CGFloat(cos(a)))
    }

    /// The machine-gun jetpack's spray: tracers raining down to the walkway, sparking where they hit.
    static func gunfire(_ ctx: GraphicsContext, nozzle n: CGPoint, floorY: CGFloat, t: Double) {
        let drop = max(1, floorY - n.y)
        var streaks = Path(), sparks = Path()
        for i in 0..<9 {
            let k = Double(i)
            let ang = (-4 + hash(k + 1) * 22) * .pi / 180
            let phase = CGFloat((t * 7 + k * 0.111).truncatingRemainder(dividingBy: 1))
            let dx = -CGFloat(sin(ang)), dy = CGFloat(cos(ang))
            let len = drop / dy
            let p = CGPoint(x: n.x + dx * len * phase, y: n.y + dy * len * phase)
            streaks.move(to: p)
            streaks.addLine(to: CGPoint(x: p.x - dx * 13, y: p.y - dy * 13))
            if phase > 0.8 {
                let hit = CGPoint(x: n.x + dx * len, y: floorY)
                for s in 0..<4 {
                    let sa = Double.pi * (1.05 + 0.3 * Double(s)) + hash(k * 3 + Double(s) + floor(t * 20))
                    sparks.move(to: hit)
                    sparks.addLine(to: CGPoint(x: hit.x + CGFloat(cos(sa)) * 7, y: hit.y + CGFloat(sin(sa)) * 7))
                }
            }
        }
        ctx.stroke(streaks, with: .color(Color(red: 1, green: 0.92, blue: 0.55)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        ctx.stroke(sparks, with: .color(Color(red: 1, green: 0.8, blue: 0.3)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
    }

    static func muzzleFlash(_ ctx: GraphicsContext, at n: CGPoint, size s: CGFloat, t: Double) {
        let flick = CGFloat(0.8 + hash(floor(t * 30)) * 0.5)
        var star = Path()
        for i in 0..<10 {
            let a = Double(i) / 10 * 2 * .pi + .pi / 2
            let r = (i % 2 == 0 ? s * 0.26 * flick : s * 0.09)
            let q = CGPoint(x: n.x + CGFloat(cos(a)) * r * 0.8, y: n.y + CGFloat(sin(a)) * r + s * 0.06)
            if i == 0 { star.move(to: q) } else { star.addLine(to: q) }
        }
        star.closeSubpath()
        ctx.fill(star, with: .color(Color(red: 1, green: 0.62, blue: 0.14)))
        ctx.fill(Path(ellipseIn: CGRect(x: n.x - s * 0.07, y: n.y - s * 0.02, width: s * 0.14, height: s * 0.14)), with: .color(Color(red: 1, green: 0.97, blue: 0.75)))
    }

    static func idleSmoke(_ ctx: GraphicsContext, nozzle n: CGPoint, t: Double) {
        let phase = CGFloat((t * 1.6).truncatingRemainder(dividingBy: 1))
        let r = 3 + phase * 7
        ctx.fill(Path(ellipseIn: CGRect(x: n.x - r - phase * 10, y: n.y + phase * 8 - r, width: r * 2, height: r * 2)),
                 with: .color(.white.opacity(0.22 * Double(1 - phase))))
    }

    /// The banana in Barry's machine-gun jetpack, facing right. `height` ≈ the drawn banana.
    static func banana(_ ctx: GraphicsContext, at c: CGPoint, height s: CGFloat, tilt: Angle) {
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: tilt)
        g.scaleBy(x: s, y: s)
        let ink = Color(red: 0.08, green: 0.07, blue: 0.1)

        // The pack: a steel tank with a gun barrel pointing down and a brass ammo belt.
        let tank = Path(roundedRect: CGRect(x: -0.5, y: -0.3, width: 0.3, height: 0.66), cornerRadius: 0.1)
        g.fill(tank, with: .linearGradient(Gradient(colors: [Color(white: 0.78), Color(white: 0.5), Color(white: 0.34)]),
                                           startPoint: CGPoint(x: -0.5, y: 0), endPoint: CGPoint(x: -0.2, y: 0)))
        g.stroke(tank, with: .color(ink), lineWidth: 0.035)
        let barrel = Path(roundedRect: CGRect(x: -0.4, y: 0.32, width: 0.12, height: 0.2), cornerRadius: 0.03)
        g.fill(barrel, with: .color(Color(white: 0.2)))
        g.stroke(barrel, with: .color(ink), lineWidth: 0.03)
        var belt = Path()
        for i in 0..<4 {
            belt.addRoundedRect(in: CGRect(x: -0.19, y: 0.12 + CGFloat(i) * 0.075, width: 0.1, height: 0.05), cornerSize: CGSize(width: 0.02, height: 0.02))
        }
        g.fill(belt, with: .color(Color(red: 0.86, green: 0.66, blue: 0.24)))

        // Banana body, standing, curved like ")" with the stem on top.
        var body = Path()
        body.move(to: CGPoint(x: 0.04, y: -0.5))
        body.addCurve(to: CGPoint(x: 0.14, y: 0.5), control1: CGPoint(x: -0.42, y: -0.26), control2: CGPoint(x: -0.36, y: 0.38))
        body.addCurve(to: CGPoint(x: 0.04, y: -0.5), control1: CGPoint(x: 0.08, y: 0.26), control2: CGPoint(x: 0.14, y: -0.24))
        body.closeSubpath()
        g.fill(body, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.92, blue: 0.4), Color(red: 1, green: 0.8, blue: 0.2), Color(red: 0.9, green: 0.62, blue: 0.1)]),
                                           startPoint: CGPoint(x: 0.1, y: 0), endPoint: CGPoint(x: -0.3, y: 0)))
        var ridge = Path()
        ridge.move(to: CGPoint(x: -0.02, y: -0.36)); ridge.addQuadCurve(to: CGPoint(x: 0.02, y: 0.36), control: CGPoint(x: -0.2, y: 0))
        g.stroke(ridge, with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: 0.04, lineCap: .round))
        g.stroke(body, with: .color(ink), lineWidth: 0.04)
        // Straps.
        var straps = Path()
        straps.move(to: CGPoint(x: -0.24, y: -0.12)); straps.addLine(to: CGPoint(x: 0.07, y: -0.06))
        straps.move(to: CGPoint(x: -0.24, y: 0.16)); straps.addLine(to: CGPoint(x: 0.07, y: 0.2))
        g.stroke(straps, with: .color(Color(red: 0.22, green: 0.2, blue: 0.24)), style: StrokeStyle(lineWidth: 0.06, lineCap: .round))
        // Stem and tip.
        var stem = Path()
        stem.move(to: CGPoint(x: 0.04, y: -0.49)); stem.addQuadCurve(to: CGPoint(x: 0.14, y: -0.64), control: CGPoint(x: 0.04, y: -0.6))
        g.stroke(stem, with: .color(ink), style: StrokeStyle(lineWidth: 0.1, lineCap: .round))
        g.stroke(stem, with: .color(Color(red: 0.55, green: 0.42, blue: 0.16)), style: StrokeStyle(lineWidth: 0.055, lineCap: .round))
        g.fill(Path(ellipseIn: CGRect(x: 0.09, y: 0.46, width: 0.08, height: 0.08)), with: .color(Color(red: 0.3, green: 0.2, blue: 0.1)))
        // Face: one bright eye looking ahead and a grin.
        let eye = Path(ellipseIn: CGRect(x: -0.08, y: -0.33, width: 0.17, height: 0.19))
        g.fill(eye, with: .color(.white))
        g.stroke(eye, with: .color(ink), lineWidth: 0.025)
        g.fill(Path(ellipseIn: CGRect(x: 0.01, y: -0.28, width: 0.07, height: 0.09)), with: .color(ink))
        var smile = Path()
        smile.move(to: CGPoint(x: -0.06, y: -0.07)); smile.addQuadCurve(to: CGPoint(x: 0.07, y: -0.1), control: CGPoint(x: 0.02, y: 0.0))
        g.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: 0.03, lineCap: .round))
    }
}

/// The lab corridor, pre-drawn once: ceiling beam, riveted wall panels with the stripe, a doorway
/// every third module (or windows onto space), and the grated walkway with hazard stripes.
private struct JBCorridor: View, Equatable {
    let level: Int
    let size: CGSize

    var body: some View {
        Canvas { ctx, size in
            let h = size.height
            let pal = JBArt.palette(level)
            let m = size.width / 6
            let ceilY = 0.03 * h, floorY = 0.85 * h
            let stripeY = h * 0.46, lowY = h * 0.7

            ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: floorY)),
                     with: .linearGradient(Gradient(colors: [pal.wallLo, pal.wallHi, pal.wallLo]),
                                           startPoint: CGPoint(x: 0, y: ceilY), endPoint: CGPoint(x: 0, y: floorY)))
            for k in 0..<6 {
                let x0 = CGFloat(k) * m
                let door = k % 3 == 2
                // Two upper panels (or windows at 6–7) and a darker wainscot.
                for p in 0..<2 {
                    let r = CGRect(x: x0 + CGFloat(p) * m / 2 + 3, y: ceilY + 8, width: m / 2 - 6, height: stripeY - ceilY - 14)
                    if door && p == 1 { continue }
                    if pal.windows {
                        let win = r.insetBy(dx: 6, dy: 8)
                        let wp = Path(roundedRect: win, cornerRadius: 10)
                        ctx.fill(wp, with: .linearGradient(Gradient(colors: [Color(red: 0.02, green: 0.03, blue: 0.1), Color(red: 0.08, green: 0.1, blue: 0.26)]),
                                                           startPoint: CGPoint(x: 0, y: win.minY), endPoint: CGPoint(x: 0, y: win.maxY)))
                        var stars = Path()
                        for i in 0..<9 {
                            let q = Double(k * 20 + p * 9 + i)
                            let sp = CGPoint(x: win.minX + CGFloat(JBArt.hash(q)) * win.width, y: win.minY + CGFloat(JBArt.hash(q + 0.5)) * win.height)
                            let rr = CGFloat(0.6 + JBArt.hash(q + 0.7) * 1.2)
                            stars.addEllipse(in: CGRect(x: sp.x - rr, y: sp.y - rr, width: rr * 2, height: rr * 2))
                        }
                        ctx.fill(stars, with: .color(.white.opacity(0.8)))
                        ctx.stroke(wp, with: .color(pal.edge), lineWidth: 3)
                    } else {
                        ctx.fill(Path(r), with: .linearGradient(Gradient(colors: [pal.wallHi, pal.wallLo]),
                                                                startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.maxX, y: r.maxY)))
                        var bevel = Path()
                        bevel.move(to: CGPoint(x: r.minX, y: r.maxY)); bevel.addLine(to: CGPoint(x: r.minX, y: r.minY)); bevel.addLine(to: CGPoint(x: r.maxX, y: r.minY))
                        ctx.stroke(bevel, with: .color(pal.edge.opacity(0.7)), lineWidth: 1.5)
                        ctx.stroke(Path(r), with: .color(pal.seam.opacity(0.8)), lineWidth: 1)
                        JBArt.rivets(ctx, r, color: pal.seam.opacity(0.9))
                    }
                }
                let low = CGRect(x: x0 + 3, y: lowY, width: m - 6, height: floorY - lowY - 3)
                ctx.fill(Path(low), with: .color(pal.wainscot))
                var vents = Path()
                var vx = low.minX + 12
                while vx < low.maxX - 10 {
                    vents.move(to: CGPoint(x: vx, y: low.minY + 10)); vents.addLine(to: CGPoint(x: vx, y: low.maxY - 10))
                    vx += 9
                }
                ctx.stroke(vents, with: .color(pal.seam.opacity(0.6)), lineWidth: 2)
                ctx.stroke(Path(low), with: .color(pal.seam), lineWidth: 1)

                if door {
                    let d = CGRect(x: x0 + m * 0.52, y: h * 0.3, width: m * 0.4, height: floorY - h * 0.3)
                    ctx.fill(Path(d.insetBy(dx: -5, dy: -5)), with: .color(pal.seam))
                    ctx.fill(Path(d), with: .linearGradient(Gradient(colors: [Color(white: 0.32), Color(white: 0.18)]),
                                                            startPoint: CGPoint(x: d.minX, y: 0), endPoint: CGPoint(x: d.maxX, y: 0)))
                    var seam = Path()
                    seam.move(to: CGPoint(x: d.midX, y: d.minY)); seam.addLine(to: CGPoint(x: d.midX, y: d.maxY))
                    ctx.stroke(seam, with: .color(.black.opacity(0.6)), lineWidth: 2)
                    ctx.fill(Path(roundedRect: CGRect(x: d.midX - d.width * 0.3, y: d.minY + d.height * 0.14, width: d.width * 0.6, height: d.height * 0.16), cornerRadius: 3),
                             with: .color(Color(red: 0.5, green: 0.85, blue: 0.95).opacity(0.5)))
                    // Hazard frame at the threshold and a lamp over the door.
                    var clip = ctx
                    let haz = CGRect(x: d.minX - 5, y: d.maxY - 12, width: d.width + 10, height: 12)
                    clip.clip(to: Path(haz))
                    clip.fill(Path(haz), with: .color(Color(red: 0.98, green: 0.8, blue: 0.2)))
                    var stripes = Path()
                    var sx = haz.minX - 12
                    while sx < haz.maxX {
                        stripes.move(to: CGPoint(x: sx, y: haz.maxY)); stripes.addLine(to: CGPoint(x: sx + 6, y: haz.maxY))
                        stripes.addLine(to: CGPoint(x: sx + 18, y: haz.minY)); stripes.addLine(to: CGPoint(x: sx + 12, y: haz.minY))
                        stripes.closeSubpath()
                        sx += 12
                    }
                    clip.fill(stripes, with: .color(Color(red: 0.1, green: 0.1, blue: 0.1)))
                    ctx.fill(Path(roundedRect: CGRect(x: d.midX - 14, y: d.minY - 16, width: 28, height: 8), cornerRadius: 3),
                             with: .color(level >= 4 && level <= 5 ? Color(red: 1, green: 0.3, blue: 0.25) : Color(red: 0.4, green: 1, blue: 0.55)))
                }
            }
            // The stripe band across the wall (broken by doors).
            ctx.fill(Path(CGRect(x: 0, y: stripeY - 4, width: size.width, height: 9)), with: .color(pal.stripe))
            ctx.fill(Path(CGRect(x: 0, y: stripeY + 5, width: size.width, height: 2)), with: .color(.black.opacity(0.3)))

            // Muted background fittings: a pipe run, wall monitors and warning signs.
            let pipeY = h * 0.6
            ctx.fill(Path(CGRect(x: 0, y: pipeY - 4, width: size.width, height: 8)),
                     with: .linearGradient(Gradient(colors: [pal.edge.opacity(0.55), pal.seam.opacity(0.7)]),
                                           startPoint: CGPoint(x: 0, y: pipeY - 4), endPoint: CGPoint(x: 0, y: pipeY + 4)))
            var flanges = Path()
            var fx = m * 0.25
            while fx < size.width { flanges.addRect(CGRect(x: fx - 3, y: pipeY - 6, width: 6, height: 12)); fx += m / 2 }
            ctx.fill(flanges, with: .color(pal.seam.opacity(0.75)))
            for k in 0..<6 where k % 3 != 2 && !pal.windows {
                let x0 = CGFloat(k) * m
                if k % 3 == 0 {
                    let scr = CGRect(x: x0 + m * 0.12, y: stripeY - h * 0.13, width: m * 0.22, height: h * 0.075)
                    ctx.fill(Path(roundedRect: scr.insetBy(dx: -3, dy: -3), cornerRadius: 4), with: .color(pal.seam))
                    ctx.fill(Path(roundedRect: scr, cornerRadius: 2), with: .color(Color(red: 0.04, green: 0.12, blue: 0.1)))
                    var trace = Path()
                    for i in 0...16 {
                        let px = scr.minX + scr.width * CGFloat(i) / 16
                        let py = scr.midY + CGFloat(sin(Double(i) * 1.1 + Double(k))) * scr.height * 0.28
                        if i == 0 { trace.move(to: CGPoint(x: px, y: py)) } else { trace.addLine(to: CGPoint(x: px, y: py)) }
                    }
                    ctx.stroke(trace, with: .color(Color(red: 0.3, green: 1, blue: 0.55).opacity(0.8)), lineWidth: 1.2)
                } else {
                    // A pressure gauge on the pipe (not a sign: Joyride's "!" means an incoming missile).
                    let c = CGPoint(x: x0 + m * 0.75, y: pipeY - 17)
                    var riser = Path()
                    riser.move(to: CGPoint(x: c.x, y: c.y + 8)); riser.addLine(to: CGPoint(x: c.x, y: pipeY))
                    ctx.stroke(riser, with: .color(pal.seam.opacity(0.8)), lineWidth: 3)
                    let dial = Path(ellipseIn: CGRect(x: c.x - 10, y: c.y - 10, width: 20, height: 20))
                    ctx.fill(dial, with: .color(Color(white: 0.85).opacity(0.85)))
                    ctx.stroke(dial, with: .color(pal.seam), lineWidth: 2.5)
                    var needle = Path()
                    needle.move(to: c); needle.addLine(to: CGPoint(x: c.x + 5, y: c.y - 5))
                    ctx.stroke(needle, with: .color(Color(red: 0.75, green: 0.12, blue: 0.1)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                }
            }

            // Ceiling beam: the lethal line is its lower edge.
            ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: ceilY)), with: .color(pal.beam))
            ctx.fill(Path(CGRect(x: 0, y: ceilY - 2, width: size.width, height: 2)), with: .color(pal.edge.opacity(0.6)))
            ctx.fill(Path(CGRect(x: 0, y: ceilY, width: size.width, height: 10)),
                     with: .linearGradient(Gradient(colors: [.black.opacity(0.35), .clear]), startPoint: CGPoint(x: 0, y: ceilY), endPoint: CGPoint(x: 0, y: ceilY + 10)))

            // Walkway: steel lip, hazard stripes, grating.
            ctx.fill(Path(CGRect(x: 0, y: floorY, width: size.width, height: h - floorY)), with: .color(Color(red: 0.14, green: 0.15, blue: 0.19)))
            ctx.fill(Path(CGRect(x: 0, y: floorY, width: size.width, height: 4)), with: .color(Color(red: 0.72, green: 0.75, blue: 0.8)))
            var haz = Path()
            var hx: CGFloat = -20
            while hx < size.width {
                haz.move(to: CGPoint(x: hx, y: floorY + 13)); haz.addLine(to: CGPoint(x: hx + 10, y: floorY + 13))
                haz.addLine(to: CGPoint(x: hx + 19, y: floorY + 4)); haz.addLine(to: CGPoint(x: hx + 9, y: floorY + 4))
                haz.closeSubpath()
                hx += 20
            }
            ctx.fill(Path(CGRect(x: 0, y: floorY + 4, width: size.width, height: 9)), with: .color(Color(red: 0.98, green: 0.8, blue: 0.2)))
            ctx.fill(haz, with: .color(Color(red: 0.1, green: 0.1, blue: 0.1)))
            var grate = Path()
            var gx: CGFloat = 0
            while gx < size.width { grate.move(to: CGPoint(x: gx, y: floorY + 16)); grate.addLine(to: CGPoint(x: gx, y: h)); gx += 8 }
            var gy = floorY + 16
            while gy < h { grate.move(to: CGPoint(x: 0, y: gy)); grate.addLine(to: CGPoint(x: size.width, y: gy)); gy += 8 }
            ctx.stroke(grate, with: .color(.black.opacity(0.4)), lineWidth: 1.5)
        }
    }
}

/// Jetpack Joyride's chunky white counter with a dark outline.
private struct JBCounter: View {
    let percent: Int

    var body: some View {
        let font = Font.system(size: 28, weight: .black).width(.condensed)
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let a = Double(i) * .pi / 4
                Text("\(percent)%").font(font).foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.16))
                    .offset(x: CGFloat(cos(a)) * 2.2, y: CGFloat(sin(a)) * 2.2)
            }
            Text("\(percent)%").font(font)
                .foregroundStyle(LinearGradient(colors: [.white, Color(red: 0.86, green: 0.9, blue: 0.96)], startPoint: .top, endPoint: .bottom))
        }
        .fixedSize()
    }
}
