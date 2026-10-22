//
//  StackGame.swift
//  A Banana Game
//
//  Reflex — the Stack (Ketchapp) homage. A slab slides back and forth atop the tower;
//  TAP to drop it. Any part hanging past the slab below is sliced off and the tower
//  narrows — so precision compounds. Stack the level's quota of slabs to win; miss the
//  tower entirely (zero overlap) or run out of time and you fail back to level 1.
//  7 levels: faster slide, a narrower start, a taller goal, and a new colour zone.
//
//  Drawn as Ketchapp's Stack: isometric slabs with a lit top and two shaded sides, the hue drifting
//  layer by layer and darkening down the tower, a two-tone pastel sky that shifts as you build, a
//  little floating dust, and the big thin score. The slide axis is the logic's x axis projected onto
//  one iso diagonal, so what overlaps on screen is exactly what `drop()` keeps. Sliced overhangs
//  fall away, a perfect drop flashes the white square ring, and a miss drops the whole slab.
//

import SwiftUI

enum StackGame {
    static let definition = GameDefinition(
        id: "stack",
        title: "Stack",
        emoji: "🍌",
        genre: .reflex,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "A slab slides back and forth atop the tower.",
                "Tap to drop it — any overhang past the slab below is sliced off, so the tower narrows.",
                "Stack the level's quota of slabs to win.",
                "Miss the tower entirely, or run out of time, and you're back to level 1.",
            ],
            bulletsVI: [
                "Một tấm trượt qua lại trên đỉnh tháp.",
                "Chạm để thả nó — phần thừa ra ngoài tấm bên dưới bị cắt bỏ, nên tháp hẹp dần.",
                "Xếp đủ số tấm của cấp để thắng.",
                "Trượt hụt cả tháp, hoặc hết giờ, sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(StackView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct StackView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    // MARK: Difficulty
    private var slabSpeed: CGFloat { [0.50, 0.62, 0.75, 0.90, 1.05, 1.25, 1.45][min(level, 7) - 1] }
    private var startHalf: CGFloat { [0.24, 0.22, 0.20, 0.18, 0.16, 0.15, 0.14][min(level, 7) - 1] }
    private var target: Int { [8, 10, 12, 14, 16, 18, 20][min(level, 7) - 1] }
    private var timeLimit: Double { [30, 28, 26, 24, 22, 20, 18][min(level, 7) - 1] }
    private var levelBaseHue: Double { [0.50, 0.55, 0.35, 0.08, 0.85, 0.62, 0.13][min(level, 7) - 1] }

    private let activeY: CGFloat = 0.30
    private let slabH: CGFloat = 0.045

    // MARK: State
    private struct Slab: Identifiable { let id = UUID(); var cx: CGFloat; var hw: CGFloat }
    private struct Burst: Identifiable { let id = UUID(); let x: CGFloat; let color: Color; let count: Int; let spread: CGFloat }

    @State private var slabs: [Slab] = []
    @State private var bursts: [Burst] = []
    @State private var movingCx: CGFloat = 0.24
    @State private var movingHw: CGFloat = 0.24
    @State private var dir: CGFloat = 1
    @State private var added = 0
    @State private var timeLeft = 0.0
    @State private var done = false
    @State private var loopTask: Task<Void, Never>?
    @State private var demoTapID = 0      // demo: bumps per drop → a fresh DemoTapRipple
    // Presentation only: falling offcuts, perfect-drop rings, and a counter that schedules pruning.
    @State private var chips: [STChip] = []
    @State private var rings: [STRing] = []
    @State private var fxSerial = 0

    private func slabColor(_ index: Int) -> Color {
        Color(hue: (levelBaseHue + Double(index) * 0.02).truncatingRemainder(dividingBy: 1.0),
              saturation: 0.65, brightness: 0.95)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack(alignment: .top) {
                STSky(hue: STArt.skyHue(levelBaseHue, added)).equatable()

                // The tower, the sliding slab and the offcuts. The timeline only runs while an offcut
                // falls or a ring fades, so a miss still drops its slab after the loop has stopped.
                TimelineView(.animation(paused: chips.isEmpty && rings.isEmpty)) { tl in
                    Canvas { ctx, size in
                        drawTower(ctx, size: size, now: tl.date.timeIntervalSinceReferenceDate)
                    }
                }

                scoreboard(h: h)

                // Demo: a ripple for each tap-anywhere drop.
                if isDemo && demoTapID > 0 {
                    DemoTapRipple().id(demoTapID).position(x: w * 0.5, y: h * 0.72)
                }
            }
            .frame(width: w, height: h)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { drop() }
        }
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
        // `drop()` adds a white 16-spark burst for a perfect drop and a smaller one otherwise; read it
        // here to show the ring or the sliced overhang, then clear it (nothing else draws bursts).
        .onChange(of: bursts.count) { old, new in
            guard new > old, slabs.count >= 2, let burst = bursts.last else { return }
            let placed = slabs[slabs.count - 1], below = slabs[slabs.count - 2]
            let now = Date().timeIntervalSinceReferenceDate
            if burst.count == 16 {
                rings.append(STRing(level: slabs.count - 1, cx: placed.cx, hw: placed.hw, born: now))
            } else if placed.hw < below.hw - 0.0001 {
                let right = placed.cx > below.cx
                let x0 = right ? below.cx + below.hw : placed.cx + placed.hw - 2 * below.hw
                let x1 = right ? placed.cx - placed.hw + 2 * below.hw : below.cx - below.hw
                chips.append(STChip(level: slabs.count - 1, x0: x0, x1: x1, side: right ? 1 : -1, born: now))
            }
            bursts.removeAll()
            fxSerial += 1
        }
        // A miss (not the clock) ends the run with the slab still hanging: let it fall.
        .onChange(of: done) { _, isDone in
            guard isDone, added < target, timeLeft > 0, let below = slabs.last else { return }
            chips.append(STChip(level: slabs.count, x0: movingCx - movingHw, x1: movingCx + movingHw,
                                side: movingCx >= below.cx ? 1 : -1, born: Date().timeIntervalSinceReferenceDate))
            fxSerial += 1
        }
        .task(id: fxSerial) {
            try? await Task.sleep(for: .seconds(1.4))
            let cut = Date().timeIntervalSinceReferenceDate - 1.3
            chips.removeAll { $0.born < cut }
            rings.removeAll { $0.born < cut }
        }
    }

    /// The big thin score with the slab goal beside it, and (while playing) a hairline clock.
    private func scoreboard(h: CGFloat) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(added)")
                    .font(.system(size: isDemo ? h * 0.075 : max(34, h * 0.085), weight: .thin))
                    .monospacedDigit()
                Text("/\(target)")
                    .font(.system(size: max(15, h * 0.03), weight: .light))
                    .opacity(0.7)
            }
            .foregroundStyle(.white)
            if !isDemo {
                timeBar.frame(width: 120, height: 3)
            }
        }
        .padding(.top, isDemo ? 2 : h * 0.045)
        .allowsHitTesting(false)
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let fraction = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(fraction < 0.3 ? Color(red: 1, green: 0.3, blue: 0.3) : .white.opacity(0.9))
                    .frame(width: geo.size.width * fraction)
            }
        }
    }

    /// Iso layout: the logic's x runs down-right, depth (a fixed ±startHalf) runs down-left, and each
    /// level is one slab thickness. The sliding slab's top face is centred at `activeY` when x = 0.5.
    private func drawTower(_ ctx: GraphicsContext, size: CGSize, now: Double) {
        let w = size.width, h = size.height
        let d = startHalf
        let iso = STIso(scale: 0.94 * min(w, h * 0.68) / (0.866 * (1 + 2 * d)), thick: slabH * h * 0.9, midX: w / 2,
                        topY: activeY * h, top: slabs.count, depth: d)
        let base = levelBaseHue
        let n = slabs.count

        // Offcuts that fell off the far (up-left) side go behind the tower.
        for c in chips where c.side < 0 { drawChip(ctx, c, iso: iso, h: h, now: now, hue: base) }

        let first = max(0, n - Int(h / max(1, iso.thick)) - 2)
        for i in first..<n {
            let s = slabs[i]
            let depthShade = min(0.5, Double(n - i) * 0.028)
            STArt.slab(ctx, iso: iso, x0: s.cx - s.hw, x1: s.cx + s.hw, level: i,
                       hue: STArt.hue(base, i), shade: depthShade, down: i == 0 ? h * 2 : 0)
        }
        for r in rings { STArt.ring(ctx, r, iso: iso, now: now) }
        for c in chips where c.side > 0 { drawChip(ctx, c, iso: iso, h: h, now: now, hue: base) }

        if !(done && added < target && timeLeft > 0) {
            STArt.slab(ctx, iso: iso, x0: movingCx - movingHw, x1: movingCx + movingHw, level: n,
                       hue: STArt.hue(base, n), shade: 0, down: 0)
        }
    }

    private func drawChip(_ ctx: GraphicsContext, _ c: STChip, iso: STIso, h: CGFloat, now: Double, hue base: Double) {
        let age = max(0, now - c.born)
        guard age < 1.3 else { return }
        var g = ctx
        g.translateBy(x: CGFloat(c.side) * CGFloat(age) * iso.scale * 0.12 * 0.866,
                      y: 0.5 * h * 2.4 * CGFloat(age * age) + CGFloat(c.side) * CGFloat(age) * iso.scale * 0.12 * 0.5)
        g.opacity = max(0, min(1, (1.3 - age) / 0.5))
        STArt.slab(g, iso: iso, x0: c.x0, x1: c.x1, level: c.level, hue: STArt.hue(base, c.level), shade: 0, down: 0)
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
    // Level 1 (8 slabs), stepped at a fixed 1/60s through the real `step`. Each slab is tapped
    // (the real `drop`) as it slides over the tower, with a scripted human error per drop — some
    // perfect (white burst, no loss), some a hair off so the overhang is really sliced away.
    private static let demoMiss: [CGFloat] = [0, 0.03, 0, -0.02, 0.018, 0, -0.012, 0]

    private func runDemo() async {
        let dt: CGFloat = 1.0 / 60.0
        while !Task.isCancelled {
            setup()
            try? await Task.sleep(for: .seconds(0.5))
            while !Task.isCancelled && !done {
                step(dt: dt)
                if let below = slabs.last, dir > 0,
                   movingCx >= below.cx + Self.demoMiss[added % Self.demoMiss.count] {
                    drop(); demoTapID += 1
                    try? await Task.sleep(for: .seconds(0.18))   // a beat between taps
                }
                try? await Task.sleep(for: .seconds(0.016))
            }
            // Quota stacked → the real win() ran (onWin is a no-op). Hold, then loop.
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    private func setup() {
        slabs = [Slab(cx: 0.5, hw: startHalf)]
        movingHw = startHalf
        movingCx = movingHw
        dir = 1
        added = 0
        done = false
        timeLeft = timeLimit
    }

    private func step(dt: CGFloat) {
        guard !done else { return }
        movingCx += dir * slabSpeed * dt
        if movingCx > 1 - movingHw { movingCx = 1 - movingHw; dir = -1 }
        if movingCx < movingHw { movingCx = movingHw; dir = 1 }
    }

    private func drop() {
        guard !done, let below = slabs.last else { return }
        let perfect = abs(movingCx - below.cx) < 0.012
        let cx: CGFloat
        let hw: CGFloat
        if perfect {
            cx = below.cx; hw = movingHw
        } else {
            let newLeft = max(below.cx - below.hw, movingCx - movingHw)
            let newRight = min(below.cx + below.hw, movingCx + movingHw)
            let overlap = newRight - newLeft
            if overlap <= 0.001 { fail(); return }
            cx = (newLeft + newRight) / 2
            hw = overlap / 2
        }

        slabs.append(Slab(cx: cx, hw: hw))
        Haptics.tap(); SoundManager.shared.tap()
        bursts.append(Burst(x: cx, color: perfect ? .white : slabColor(slabs.count - 1),
                            count: perfect ? 16 : 10, spread: perfect ? 70 : 40))

        movingHw = hw
        movingCx = movingHw
        dir = 1
        added += 1
        if added >= target { win() }
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

// MARK: - Stack art

/// A sliced-off overhang (or the whole missed slab) falling away from the tower.
private struct STChip {
    let level: Int
    let x0: CGFloat, x1: CGFloat
    let side: Int
    let born: Double
}

/// The white square ring of a perfect drop.
private struct STRing {
    let level: Int
    let cx: CGFloat, hw: CGFloat
    let born: Double
}

/// The isometric camera: logic x runs down-right, depth z runs down-left, elevation is in levels
/// (the sliding slab at level `top` has its top face at `top + 1`, centred on `topY` when x = 0.5).
private struct STIso {
    let scale: CGFloat
    let thick: CGFloat
    let midX: CGFloat
    let topY: CGFloat
    let top: Int
    let depth: CGFloat

    func p(_ x: CGFloat, _ z: CGFloat, _ e: CGFloat) -> CGPoint {
        CGPoint(x: midX + (x - 0.5 - z) * scale * 0.866,
                y: topY + (x - 0.5 + z) * scale * 0.5 - (e - CGFloat(top + 1)) * thick)
    }
}

private enum STArt {
    static func hue(_ base: Double, _ level: Int) -> Double {
        (base + Double(level) * 0.018).truncatingRemainder(dividingBy: 1)
    }

    /// The sky sits roughly opposite the tower's current colour, like the real game's.
    static func skyHue(_ base: Double, _ added: Int) -> Double {
        (base + Double(added) * 0.018 + 0.5).truncatingRemainder(dividingBy: 1)
    }

    private static func quad(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Path {
        var p = Path()
        p.move(to: a); p.addLine(to: b); p.addLine(to: c); p.addLine(to: d)
        p.closeSubpath()
        return p
    }

    /// One slab: a lit top and the two sides that face the camera. `down` extends the sides below
    /// the slab (the base is a pedestal that runs off the bottom of the screen).
    static func slab(_ ctx: GraphicsContext, iso: STIso, x0: CGFloat, x1: CGFloat, level: Int,
                     hue: Double, shade: Double, down: CGFloat) {
        guard x1 - x0 > 0.0005 else { return }
        let d = iso.depth
        let et = CGFloat(level + 1), eb = CGFloat(level) - down / max(1, iso.thick)
        let top = Color(hue: hue, saturation: 0.42, brightness: 0.98).shade(shade)
        let left = Color(hue: hue, saturation: 0.5, brightness: 0.84).shade(shade)
        let right = Color(hue: hue, saturation: 0.56, brightness: 0.7).shade(shade)
        ctx.fill(quad(iso.p(x0, d, et), iso.p(x1, d, et), iso.p(x1, d, eb), iso.p(x0, d, eb)), with: .color(left))
        ctx.fill(quad(iso.p(x1, -d, et), iso.p(x1, d, et), iso.p(x1, d, eb), iso.p(x1, -d, eb)), with: .color(right))
        ctx.fill(quad(iso.p(x0, -d, et), iso.p(x1, -d, et), iso.p(x1, d, et), iso.p(x0, d, et)), with: .color(top))
    }

    static func ring(_ ctx: GraphicsContext, _ r: STRing, iso: STIso, now: Double) {
        let age = now - r.born
        guard age >= 0, age < 0.6 else { return }
        let alpha = 1 - age / 0.6
        for (k, lw) in [(1.08 + age * 0.7, 3.0), (1.2 + age * 1.0, 1.5)] as [(Double, CGFloat)] {
            let hw = r.hw * CGFloat(k), d = iso.depth * CGFloat(k)
            let e = CGFloat(r.level + 1)
            let ring = quad(iso.p(r.cx - hw, -d, e), iso.p(r.cx + hw, -d, e), iso.p(r.cx + hw, d, e), iso.p(r.cx - hw, d, e))
            ctx.stroke(ring, with: .color(.white.opacity(alpha)), lineWidth: lw)
        }
    }

    static func hash(_ n: Double) -> CGFloat {
        let v = sin(n * 12.9898) * 43758.5453
        return CGFloat(v - floor(v))
    }
}

/// The two-tone sky and its floating dust. Redrawn only when the hue moves (once per slab).
private struct STSky: View, Equatable {
    let hue: Double

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hue: hue, saturation: 0.5, brightness: 0.74),
                                    Color(hue: (hue + 0.93).truncatingRemainder(dividingBy: 1), saturation: 0.3, brightness: 0.97)],
                           startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                for i in 0..<16 {
                    let k = Double(i)
                    let s = 2 + STArt.hash(k + 4) * 2.5
                    let p = CGPoint(x: STArt.hash(k) * size.width, y: STArt.hash(k + 9) * size.height * 0.85)
                    ctx.fill(Path(CGRect(x: p.x, y: p.y, width: s, height: s)), with: .color(.white.opacity(0.45 + Double(STArt.hash(k + 2)) * 0.45)))
                }
            }
        }
    }
}
