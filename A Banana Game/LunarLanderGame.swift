//
//  LunarLanderGame.swift
//  A Banana Game
//
//  Reflex — set the lander down gently. Gravity is always pulling you into the rocks; hold the
//  thruster to fight it and ◄ ► to rotate. Touch down on the flat lit pad while nearly upright
//  and moving slowly to win. Come in too fast, too tilted, off the pad, or run the fuel dry in
//  mid-air and you crash back to level 1 (a clock is the final safety net). 7 levels: stronger
//  gravity, a narrower pad, less fuel and stricter touchdown limits — level 7 wants a feather.
//  The surface shifts moon-grey → rust → obsidian as you descend the difficulty.
//
//  Drawn after Atari's 1979 vector Lunar Lander: black space, the ground as a glowing ridge line over
//  dark rock, and a lit landing pad whose lights blink (steady green once you're down). The lander is
//  the Apollo module — gold-foil descent stage, silver cabin — sized so its footpads touch exactly
//  where `step()` detects contact. A crash flings its pieces; a landing kicks up dust. Speed and fuel
//  are gauges (the speed tick is the safe limit). Earth hangs over the Moon, Mars's moons over the
//  rust levels, a ringed giant over the obsidian plains.
//

import SwiftUI

enum LunarLanderGame {
    static let definition = GameDefinition(
        id: "lunar-lander",
        title: "Moon Touchdown",
        emoji: "🍌",
        genre: .reflex,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Gravity constantly pulls the lander down.",
                "Hold the thruster to fight it and the rotate buttons to turn.",
                "Touch down on the flat lit pad while nearly upright and moving slowly to win.",
                "Too fast, too tilted, off the pad, or out of fuel — and you crash back to level 1.",
            ],
            bulletsVI: [
                "Trọng lực liên tục kéo tàu đáp xuống.",
                "Giữ nút đẩy để chống lại nó và các nút xoay để quay.",
                "Đáp xuống bệ phẳng sáng khi gần như thẳng đứng và di chuyển chậm để thắng.",
                "Quá nhanh, quá nghiêng, lệch bệ, hoặc hết nhiên liệu — bạn rơi về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(LunarLanderView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct LunarLanderView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void
    @Environment(\.isDemo) private var isDemo

    // MARK: Difficulty
    private var gravity: CGFloat   { [0.17, 0.21, 0.25, 0.30, 0.35, 0.41, 0.47][min(level, 7) - 1] }
    private var padW: CGFloat      { [0.24, 0.20, 0.17, 0.14, 0.11, 0.09, 0.07][min(level, 7) - 1] }
    private var fuelMax: Double    { [11, 10, 9, 8, 7.5, 7, 6.5][min(level, 7) - 1] }
    private var safeSpeed: CGFloat { [0.32, 0.29, 0.26, 0.22, 0.19, 0.16, 0.13][min(level, 7) - 1] }
    private var maxTilt: Double    { [0.55, 0.48, 0.42, 0.36, 0.30, 0.24, 0.19][min(level, 7) - 1] }
    private var timeLimit: Double  { [36, 34, 32, 30, 28, 26, 24][min(level, 7) - 1] }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var pos = CGPoint(x: 0.5, y: 0.12)
    @State private var vel = CGVector.zero
    @State private var angle: Double = 0
    @State private var rotDir = 0
    @State private var thrusting = false
    @State private var fuel = 0.0
    @State private var terrain: [CGPoint] = []
    @State private var padCenter: CGFloat = 0.5
    @State private var timeLeft = 0.0
    @State private var shakeTick = 0
    @State private var bursts: [CGPoint] = []
    @State private var loopTask: Task<Void, Never>?

    // Presentation only: when the lander crashed / touched down, and whether their effects still play.
    @State private var crashAt: Date? = nil
    @State private var landedAt: Date? = nil
    @State private var fxLive = false

    private let shipR: CGFloat = 0.028

    private var speed: CGFloat { hypot(vel.dx, vel.dy) }
    private var padY: CGFloat {
        terrain.first { abs($0.x - padCenter) < 0.001 }?.y ?? 0.82
    }

    var body: some View {
        VStack(spacing: 4) {
            // Speed against the safe touchdown limit (the tick), and the fuel left.
            HStack(spacing: isDemo ? 14 : 22) {
                LLGauge(icon: "gauge.with.dots.needle.67percent", fraction: Double(min(1, speed / max(0.01, safeSpeed * 2))), mark: 0.5,
                        color: speed < safeSpeed ? LLArt.safe : LLArt.danger, small: isDemo)
                LLGauge(icon: "fuelpump.fill", fraction: fuel / max(0.01, fuelMax), mark: nil,
                        color: fuel / max(0.01, fuelMax) < 0.25 ? LLArt.danger : LLArt.amber, small: isDemo)
            }
            .padding(.top, isDemo ? 6 : 0)
            if !isDemo { timeBar.frame(height: 5).padding(.horizontal, 60) }

            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height

                ZStack {
                    // The ground and the pad never move: drawn once per site.
                    LLTerrain(size: geo.size, terrain: terrain, padCenter: padCenter, padW: padW, padY: padY, level: level).equatable()

                    // Lander, flame, pad lights, dust and debris: one Canvas.
                    TimelineView(.animation(paused: phase == .play || !fxLive)) { tl in
                        Canvas { ctx, _ in
                            let now = max(tl.date, Date())
                            LLArt.padLights(ctx, center: CGPoint(x: padCenter * w, y: padY * h), width: padW * w, now: now, landed: landedAt != nil)
                            if let t = landedAt {
                                LLArt.dust(ctx, at: CGPoint(x: pos.x * w, y: (pos.y + shipR) * h), unit: shipR * h, age: now.timeIntervalSince(t))
                            }
                            if let t = crashAt, let p = bursts.last {
                                LLArt.debris(ctx, at: CGPoint(x: p.x * w, y: p.y * h), unit: shipR * h, age: now.timeIntervalSince(t))
                            } else {
                                LLArt.lander(ctx, at: CGPoint(x: pos.x * w, y: pos.y * h), unit: shipR * h, angle: angle,
                                             flame: thrusting && fuel > 0, now: now)
                            }
                        }
                    }
                }
                .frame(width: w, height: h)
                .clipped()
                .screenShake(shakeTick, amount: 7)
            }

            HStack(spacing: 10) {
                holdButton("arrow.counterclockwise", active: rotDir == -1) { rotDir = -1 } release: { if rotDir == -1 { rotDir = 0 } }
                holdButton("flame.fill", wide: true, active: thrusting) { thrusting = true } release: { thrusting = false }
                holdButton("arrow.clockwise", active: rotDir == 1) { rotDir = 1 } release: { if rotDir == 1 { rotDir = 0 } }
            }
            .padding(.bottom, isDemo ? 6 : 8)
            .frame(maxWidth: .infinity)
            .background(alignment: .top) {
                // The regolith runs on under the console keys.
                LLArt.palette(level).fill1.padding(.top, -4).padding(.bottom, -40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LLSpace(level: level).equatable())
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
        // A crash leaves a burst point; a touchdown on the pad (not the clock) lights the pad green.
        .onChange(of: bursts.count) { old, new in
            if new > old { crashAt = Date(); fxLive = true } else if new == 0 { crashAt = nil }
        }
        .onChange(of: phase) { _, ph in
            landedAt = ph == .done && bursts.isEmpty && timeLeft > 0 ? Date() : nil
            if landedAt != nil { fxLive = true }
        }
        .task(id: fxLive) {
            guard fxLive else { return }
            try? await Task.sleep(for: .seconds(1.6))
            if !Task.isCancelled { fxLive = false }
        }
    }

    private func holdButton(_ icon: String, wide: Bool = false, active: Bool = false,
                            press: @escaping () -> Void, release: @escaping () -> Void) -> some View {
        // In the demo the held control lights up (the autopilot drives rotDir/thrusting directly).
        let lit = isDemo && active
        return Image(systemName: icon)
            .font(.system(size: isDemo ? 19 : 22, weight: .bold))
            .foregroundStyle(wide ? Color(red: 0.25, green: 0.1, blue: 0.02) : Color(white: lit ? 1 : 0.88))
            .frame(width: wide ? (isDemo ? 96 : 110) : (isDemo ? 64 : 74), height: isDemo ? 38 : 54)
            .background(LLKey(wide: wide, lit: lit))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .scaleEffect(lit ? 0.92 : 1)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if phase == .play { press() } }
                .onEnded { _ in release() })
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14))
                Capsule().fill(frac < 0.3 ? LLArt.danger : Color(white: 0.9))
                    .frame(width: geo.size.width * frac)
            }
        }
    }

    // MARK: - Flow
    private func run() async {
        setup()
        var last = Date(); let start = Date()
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

    private func setup() {
        pos = CGPoint(x: CGFloat.random(in: 0.3...0.7), y: 0.12)
        vel = CGVector(dx: CGFloat.random(in: -0.06...0.06), dy: 0.02)
        angle = 0; rotDir = 0; thrusting = false; fuel = fuelMax
        bursts = []
        // Build jagged terrain with one flat pad.
        padCenter = CGFloat.random(in: 0.2...0.8)
        var pts: [CGPoint] = []
        let n = 24
        let padLo = padCenter - padW / 2, padHi = padCenter + padW / 2
        let padHeight = CGFloat.random(in: 0.74...0.84)
        for i in 0...n {
            let x = CGFloat(i) / CGFloat(n)
            if x >= padLo - 0.001 && x <= padHi + 0.001 {
                pts.append(CGPoint(x: x, y: padHeight))
            } else {
                let hilly = padHeight - CGFloat.random(in: -0.06...0.12)
                pts.append(CGPoint(x: x, y: min(0.94, max(0.6, hilly))))
            }
        }
        // Guarantee exact pad edge samples so padY is well-defined.
        pts.append(CGPoint(x: padCenter, y: padHeight))
        pts.sort { $0.x < $1.x }
        terrain = pts
        timeLeft = timeLimit; phase = .play
    }

    // MARK: - Demo (live manual clip)
    // Level 1 on a fixed site: the lander starts high on the left drifting right, the lit pad is
    // off to the right (0.68) among fixed hills. Stepped at a fixed 1/60s through the real `step`;
    // an autopilot holds the real controls: it tilts toward a horizontal-speed target (capped at
    // 0.2) and burns whenever the descent beats an altitude-scaled limit, flaring upright near the
    // pad, with every button held ≥8 frames so presses read clearly. Tuned offline on a port of
    // `step`: lands in ~4.0s at 0.18 (limit 0.32), 0.06 rad tilt, 0.02 off-centre, never nearer
    // than 0.1 to a hill — and still lands in 398/400 perturbed starts.
    private static let demoHills: [CGFloat] = [0.02, 0.08, 0.11, 0.05, 0.09, 0.12, 0.04, 0.07, 0.10,
                                               0.03, 0.06, 0.09, 0.02, 0.05, 0.11, 0.07, 0.10, 0.04,
                                               0.08, 0.12, 0.06, 0.03, 0.09, 0.05, 0.10]

    private func demoSetup() {
        pos = CGPoint(x: 0.28, y: 0.12)
        vel = CGVector(dx: 0.03, dy: 0.02)
        angle = 0; rotDir = 0; thrusting = false; fuel = fuelMax
        bursts = []
        padCenter = 0.68
        let padHeight: CGFloat = 0.80
        let n = 24
        let padLo = padCenter - padW / 2, padHi = padCenter + padW / 2
        var pts: [CGPoint] = []
        for i in 0...n {
            let x = CGFloat(i) / CGFloat(n)
            if x >= padLo - 0.001 && x <= padHi + 0.001 {
                pts.append(CGPoint(x: x, y: padHeight))
            } else {
                pts.append(CGPoint(x: x, y: min(0.94, max(0.6, padHeight - Self.demoHills[i]))))
            }
        }
        pts.append(CGPoint(x: padCenter, y: padHeight))
        pts.sort { $0.x < $1.x }
        terrain = pts
        timeLeft = timeLimit; phase = .play
    }

    private func runDemo() async {
        let dt: CGFloat = 1.0 / 60.0
        func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { max(lo, min(hi, v)) }
        while !Task.isCancelled {
            demoSetup()
            try? await Task.sleep(for: .seconds(0.4))
            var frame = 0, lastRot = -9, lastThr = -9
            while !Task.isCancelled && phase == .play && frame < 900 {
                frame += 1
                let alt = padY - (pos.y + shipR)
                let dx = padCenter - pos.x
                let vxDes = clamp(1.0 * dx, -0.2, 0.2)
                var angDes = clamp(5 * (vxDes - vel.dx), -0.45, 0.45)
                if alt < 0.1 { angDes = abs(dx) < 0.06 ? clamp(5 * (0 - vel.dx), -0.12, 0.12) : angDes * 0.5 }
                let e = Double(angDes) - angle
                let wantRot = e > 0.03 ? 1 : (e < -0.03 ? -1 : 0)
                if wantRot != rotDir && frame - lastRot >= 8 { rotDir = wantRot; lastRot = frame }
                let vyDes = clamp(0.8 * alt + 0.15, 0.04, 0.25)
                let wantThr = vel.dy > vyDes || (abs(angle) > 0.12 && vel.dy > vyDes - 0.05)
                if wantThr != thrusting && frame - lastThr >= 8 { thrusting = wantThr; lastThr = frame }
                step(dt: dt)
                try? await Task.sleep(for: .seconds(0.016))
            }
            // Touched down on the pad → the real win() ran (onWin is a no-op). Hold, then loop.
            rotDir = 0; thrusting = false
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    private func groundY(at x: CGFloat) -> CGFloat {
        guard terrain.count > 1 else { return 0.82 }
        for i in 0..<(terrain.count - 1) {
            let a = terrain[i], b = terrain[i + 1]
            if x >= a.x && x <= b.x {
                let t = b.x - a.x > 0.0001 ? (x - a.x) / (b.x - a.x) : 0
                return a.y + (b.y - a.y) * t
            }
        }
        return terrain.last?.y ?? 0.82
    }

    private func step(dt: CGFloat) {
        guard phase == .play else { return }
        angle += Double(rotDir) * 1.9 * Double(dt)
        angle = max(-1.4, min(1.4, angle))

        if thrusting && fuel > 0 {
            fuel -= Double(dt)
            let up = CGVector(dx: sin(angle), dy: -cos(angle))
            let power = gravity * 2.7
            vel.dx += up.dx * power * dt
            vel.dy += up.dy * power * dt
        }
        vel.dy += gravity * dt
        pos.x += vel.dx * dt
        pos.y += vel.dy * dt

        // Side walls bounce softly.
        if pos.x < 0.03 { pos.x = 0.03; vel.dx = abs(vel.dx) * 0.4 }
        if pos.x > 0.97 { pos.x = 0.97; vel.dx = -abs(vel.dx) * 0.4 }

        // Ground contact.
        let gy = groundY(at: pos.x)
        if pos.y + shipR >= gy {
            pos.y = gy - shipR
            let onPad = abs(pos.x - padCenter) < padW / 2
            let gentle = speed < safeSpeed
            let upright = abs(angle) < maxTilt
            if onPad && gentle && upright {
                win()
            } else {
                bursts.append(pos)
                crash()
            }
        }
    }

    private func win() {
        guard phase != .done else { return }
        phase = .done; loopTask?.cancel(); Haptics.tap(); onWin()
    }
    private func crash() {
        guard phase != .done else { return }
        phase = .done; loopTask?.cancel(); shakeTick += 1; SoundManager.shared.error(); onFail()
    }
    private func fail() { crash() }

}

// MARK: - Vector lander art (after Atari's 1979 Lunar Lander)

private struct LLPalette {
    let line: Color
    let fill0: Color, fill1: Color
    let sky0: Color, sky1: Color
}

private enum LLArt {
    static let safe = Color(red: 0.36, green: 0.95, blue: 0.52)
    static let danger = Color(red: 1, green: 0.33, blue: 0.28)
    static let amber = Color(red: 1, green: 0.75, blue: 0.32)

    static func hash(_ n: Double) -> Double {
        let x = sin(n) * 43758.5453
        return x - floor(x)
    }

    /// Moon grey (1–2) → Martian rust (3–5) → obsidian (6–7).
    static func palette(_ level: Int) -> LLPalette {
        let c = { (r: Double, g: Double, b: Double) in Color(red: r, green: g, blue: b) }
        switch min(max(level, 1), 7) {
        case 1: return LLPalette(line: c(0.93, 0.94, 0.98), fill0: c(0.21, 0.21, 0.25), fill1: c(0.09, 0.09, 0.11), sky0: c(0, 0, 0.02), sky1: c(0.03, 0.03, 0.07))
        case 2: return LLPalette(line: c(0.90, 0.91, 0.96), fill0: c(0.23, 0.21, 0.25), fill1: c(0.10, 0.09, 0.11), sky0: c(0, 0, 0.02), sky1: c(0.04, 0.03, 0.08))
        case 3: return LLPalette(line: c(1.0, 0.72, 0.52), fill0: c(0.36, 0.18, 0.12), fill1: c(0.15, 0.07, 0.05), sky0: c(0.02, 0.01, 0.02), sky1: c(0.14, 0.05, 0.04))
        case 4: return LLPalette(line: c(1.0, 0.64, 0.44), fill0: c(0.38, 0.15, 0.10), fill1: c(0.16, 0.06, 0.04), sky0: c(0.02, 0.01, 0.02), sky1: c(0.18, 0.06, 0.04))
        case 5: return LLPalette(line: c(1.0, 0.56, 0.40), fill0: c(0.33, 0.12, 0.10), fill1: c(0.13, 0.05, 0.04), sky0: c(0.02, 0.01, 0.02), sky1: c(0.16, 0.05, 0.06))
        case 6: return LLPalette(line: c(0.78, 0.66, 1.0), fill0: c(0.14, 0.10, 0.21), fill1: c(0.05, 0.03, 0.08), sky0: c(0.01, 0.0, 0.03), sky1: c(0.06, 0.03, 0.12))
        default: return LLPalette(line: c(0.70, 0.58, 1.0), fill0: c(0.10, 0.07, 0.16), fill1: c(0.03, 0.02, 0.06), sky0: c(0.0, 0.0, 0.02), sky1: c(0.04, 0.02, 0.09))
        }
    }

    /// The Apollo-style lander in a unit where 1 = `shipR` of the field height, so its footpads
    /// touch down exactly where `step()` detects contact. Gold-foil descent stage, silver cabin.
    static func lander(_ ctx: GraphicsContext, at p: CGPoint, unit u: CGFloat, angle: Double, flame: Bool, now: Date) {
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        g.rotate(by: .radians(angle))
        g.scaleBy(x: u, y: u)
        let lw = 1.3 / u
        let ink = Color(red: 0.04, green: 0.04, blue: 0.07)
        func poly(_ pts: [(CGFloat, CGFloat)]) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
            for q in pts.dropFirst() { path.addLine(to: CGPoint(x: q.0, y: q.1)) }
            path.closeSubpath()
            return path
        }
        if flame {
            let k = Int(now.timeIntervalSinceReferenceDate * 24)
            let f = CGFloat(0.5 + 0.5 * sin(Double(k) * 2.3))
            let len: CGFloat = 0.9 + 0.55 * f
            let outer = poly([(-0.24, 0.6), (0.24, 0.6), (0, 0.6 + len)])
            g.fill(outer, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.7), Color(red: 1, green: 0.55, blue: 0.15), Color(red: 1, green: 0.3, blue: 0.1).opacity(0)]),
                                                startPoint: CGPoint(x: 0, y: 0.6), endPoint: CGPoint(x: 0, y: 0.6 + len)))
            g.fill(poly([(-0.1, 0.6), (0.1, 0.6), (0, 0.6 + len * 0.55)]), with: .color(.white.opacity(0.9)))
        }
        // Legs and footpads (the pads' soles sit on y = 1).
        var legs = Path()
        for s in [-1.0, 1.0] as [CGFloat] {
            legs.move(to: CGPoint(x: s * 0.5, y: 0.18)); legs.addLine(to: CGPoint(x: s * 0.98, y: 0.9))
            legs.move(to: CGPoint(x: s * 0.52, y: 0.4)); legs.addLine(to: CGPoint(x: s * 0.86, y: 0.72))
        }
        g.stroke(legs, with: .color(ink), style: StrokeStyle(lineWidth: 0.16, lineCap: .round))
        g.stroke(legs, with: .color(Color(white: 0.78)), style: StrokeStyle(lineWidth: 0.09, lineCap: .round))
        for s in [-1.0, 1.0] as [CGFloat] {
            let pad = Path(ellipseIn: CGRect(x: s * 1.0 - 0.19, y: 0.87, width: 0.38, height: 0.13))
            g.fill(pad, with: .color(Color(white: 0.82)))
            g.stroke(pad, with: .color(ink), lineWidth: lw)
        }
        // Engine bell and the gold-foil descent stage.
        let bell = poly([(-0.14, 0.4), (0.14, 0.4), (0.23, 0.61), (-0.23, 0.61)])
        g.fill(bell, with: .color(Color(white: 0.3)))
        g.stroke(bell, with: .color(ink), lineWidth: lw)
        let stage = poly([(-0.55, -0.02), (0.55, -0.02), (0.63, 0.1), (0.63, 0.34), (0.55, 0.43), (-0.55, 0.43), (-0.63, 0.34), (-0.63, 0.1)])
        g.fill(stage, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.88, blue: 0.46), Color(red: 0.86, green: 0.62, blue: 0.16), Color(red: 0.62, green: 0.42, blue: 0.1)]),
                                            startPoint: CGPoint(x: -0.4, y: -0.02), endPoint: CGPoint(x: 0.4, y: 0.43)))
        var foil = Path()
        for (x0, y0, x1, y1) in [(-0.4, 0.06, -0.2, 0.3), (-0.05, 0.02, 0.1, 0.24), (0.25, 0.12, 0.46, 0.36), (-0.52, 0.28, -0.36, 0.4)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            foil.move(to: CGPoint(x: x0, y: y0)); foil.addLine(to: CGPoint(x: x1, y: y1))
        }
        g.stroke(foil, with: .color(Color(red: 0.55, green: 0.36, blue: 0.08).opacity(0.7)), lineWidth: 0.04)
        g.stroke(stage, with: .color(ink), lineWidth: lw)
        // The ascent stage: silver cabin, triangular window, antenna dish, thruster quads.
        let cabin = poly([(-0.46, -0.02), (-0.53, -0.36), (-0.34, -0.63), (0.1, -0.7), (0.41, -0.58), (0.51, -0.3), (0.46, -0.02)])
        g.fill(cabin, with: .linearGradient(Gradient(colors: [Color(white: 0.95), Color(white: 0.72)]),
                                            startPoint: CGPoint(x: -0.4, y: -0.6), endPoint: CGPoint(x: 0.4, y: 0)))
        g.fill(Path(CGRect(x: 0.1, y: -0.38, width: 0.26, height: 0.22)), with: .color(Color(white: 0.58)))
        let window = poly([(-0.3, -0.44), (-0.06, -0.52), (-0.14, -0.24)])
        g.fill(window, with: .color(Color(red: 0.1, green: 0.13, blue: 0.2)))
        g.fill(poly([(-0.24, -0.44), (-0.13, -0.48), (-0.17, -0.4)]), with: .color(.white.opacity(0.55)))
        g.stroke(cabin, with: .color(ink), lineWidth: lw)
        var mast = Path()
        mast.move(to: CGPoint(x: 0.3, y: -0.6)); mast.addLine(to: CGPoint(x: 0.42, y: -0.86))
        var quads = Path()
        for (x, y) in [(-0.56, -0.3), (0.54, -0.28)] as [(CGFloat, CGFloat)] {
            quads.move(to: CGPoint(x: x - 0.1, y: y)); quads.addLine(to: CGPoint(x: x + 0.1, y: y))
            quads.move(to: CGPoint(x: x, y: y - 0.1)); quads.addLine(to: CGPoint(x: x, y: y + 0.1))
        }
        g.stroke(mast, with: .color(Color(white: 0.8)), lineWidth: 0.06)
        g.stroke(quads, with: .color(Color(white: 0.85)), lineWidth: 0.06)
        let dish = Path(ellipseIn: CGRect(x: 0.33, y: -0.97, width: 0.2, height: 0.14))
        g.fill(dish, with: .color(Color(white: 0.9)))
        g.stroke(dish, with: .color(ink), lineWidth: lw * 0.8)
    }

    /// Landing lights at the pad's ends: blinking red / white, steady green once landed.
    static func padLights(_ ctx: GraphicsContext, center c: CGPoint, width: CGFloat, now: Date, landed: Bool) {
        let t = now.timeIntervalSinceReferenceDate
        let on = Int(t * 2.4) % 2 == 0
        for (i, x) in [c.x - width / 2, c.x + width / 2].enumerated() {
            let lit = landed || (on == (i == 0))
            let col: Color = landed ? LLArt.safe : (lit ? Color(red: 1, green: 0.3, blue: 0.25) : Color(white: 0.35))
            let p = CGPoint(x: x, y: c.y - 3)
            if lit {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)),
                         with: .radialGradient(Gradient(colors: [col.opacity(0.7), col.opacity(0)]), center: p, startRadius: 0, endRadius: 7))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(col))
        }
    }

    /// Two puffs of regolith kicked out from under the footpads.
    static func dust(_ ctx: GraphicsContext, at feet: CGPoint, unit u: CGFloat, age: Double) {
        guard age < 1.1 else { return }
        let a = CGFloat(age)
        let fade = max(0, 0.5 * (1 - age / 1.1))
        for s in [-1.0, 1.0] as [CGFloat] {
            let cx = feet.x + s * (1 + a * 1.8) * u
            let wdt = (0.6 + a * 1.8) * u, hgt = (0.25 + a * 0.5) * u
            ctx.fill(Path(ellipseIn: CGRect(x: cx - wdt / 2, y: feet.y - hgt, width: wdt, height: hgt)), with: .color(Color(white: 0.8).opacity(fade)))
        }
    }

    /// The crash: a flash, then the lander's pieces (gold and silver strokes) flung out and falling.
    static func debris(_ ctx: GraphicsContext, at p: CGPoint, unit u: CGFloat, age: Double) {
        let a = CGFloat(age)
        if age < 0.45 {
            let r = (0.6 + a * 5) * u
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                     with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.75).opacity(0.9 * (1 - age / 0.45)), Color(red: 1, green: 0.5, blue: 0.1).opacity(0)]),
                                           center: p, startRadius: 0, endRadius: r))
        }
        guard age < 1.4 else { return }
        let fade = max(0, 1 - age / 1.4)
        for i in 0..<14 {
            let dir = Double(i) / 14 * 2 * .pi + hash(Double(i) * 3.1) * 0.5 - .pi / 2
            let v = CGFloat(2.4 + 2.6 * hash(Double(i) * 7.7))
            let q = CGPoint(x: p.x + CGFloat(cos(dir)) * v * a * u, y: p.y + CGFloat(sin(dir)) * v * a * u + 2.2 * a * a * u)
            let spin = Double(i) * 0.8 + age * (4 + Double(i % 3) * 3)
            let len = u * CGFloat(0.25 + 0.3 * hash(Double(i) * 1.3))
            var seg = Path()
            seg.move(to: CGPoint(x: q.x - CGFloat(cos(spin)) * len, y: q.y - CGFloat(sin(spin)) * len))
            seg.addLine(to: CGPoint(x: q.x + CGFloat(cos(spin)) * len, y: q.y + CGFloat(sin(spin)) * len))
            let col = i % 3 == 0 ? Color(white: 0.9) : Color(red: 1, green: 0.78, blue: 0.3)
            ctx.stroke(seg, with: .color(col.opacity(fade)), style: StrokeStyle(lineWidth: max(1.2, u * 0.1), lineCap: .round))
        }
    }
}

/// The ground as a glowing vector ridge line over dark rock, with the flat pad lit up. Drawn once
/// per site; the pad is drawn exactly over the span that counts (`padCenter ± padW / 2`).
private struct LLTerrain: View, Equatable {
    let size: CGSize
    let terrain: [CGPoint]
    let padCenter: CGFloat
    let padW: CGFloat
    let padY: CGFloat
    let level: Int

    var body: some View {
        Canvas { ctx, _ in
            guard let first = terrain.first else { return }
            let w = size.width, h = size.height
            let pal = LLArt.palette(level)
            var ridge = Path()
            ridge.move(to: CGPoint(x: first.x * w, y: first.y * h))
            for pt in terrain { ridge.addLine(to: CGPoint(x: pt.x * w, y: pt.y * h)) }
            var ground = ridge
            ground.addLine(to: CGPoint(x: w, y: h))
            ground.addLine(to: CGPoint(x: first.x * w, y: h))
            ground.closeSubpath()
            let top = (terrain.map(\.y).min() ?? 0.6) * h
            ctx.fill(ground, with: .linearGradient(Gradient(colors: [pal.fill0, pal.fill1]), startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: h)))
            // Faint scan lines in the rock: the vector-display feel.
            var scan = ctx
            scan.clip(to: ground)
            var lines = Path()
            var y = top
            while y < h {
                lines.move(to: CGPoint(x: 0, y: y)); lines.addLine(to: CGPoint(x: w, y: y))
                y += 5
            }
            scan.stroke(lines, with: .color(pal.line.opacity(0.05)), lineWidth: 1)
            // Glowing ridge line.
            ctx.stroke(ridge, with: .color(pal.line.opacity(0.14)), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            ctx.stroke(ridge, with: .color(pal.line.opacity(0.3)), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            ctx.stroke(ridge, with: .color(pal.line), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            // The pad.
            let px0 = (padCenter - padW / 2) * w, px1 = (padCenter + padW / 2) * w, py = padY * h
            var pad = Path()
            pad.move(to: CGPoint(x: px0, y: py)); pad.addLine(to: CGPoint(x: px1, y: py))
            let padCol = Color(red: 1, green: 0.92, blue: 0.55)
            ctx.stroke(pad, with: .color(padCol.opacity(0.25)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
            ctx.stroke(pad, with: .color(padCol), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            var posts = Path()
            for x in [px0 + 2, px1 - 2] {
                posts.move(to: CGPoint(x: x, y: py)); posts.addLine(to: CGPoint(x: x, y: py + 7))
            }
            ctx.stroke(posts, with: .color(padCol.opacity(0.8)), lineWidth: 1.5)
        }
    }
}

/// Deep space over the whole card: stars, and the sky of each world — Earth over the Moon, Mars's
/// two little moons, a ringed giant over the obsidian plains.
private struct LLSpace: View, Equatable {
    let level: Int

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let pal = LLArt.palette(level)
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [pal.sky0, pal.sky1]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            var stars = Path(), bright = Path()
            for i in 0..<80 {
                let x = CGFloat(LLArt.hash(Double(i) * 12.99)) * w
                let y = CGFloat(LLArt.hash(Double(i) * 78.23)) * h * 0.75
                let d: CGFloat = 0.8 + CGFloat(LLArt.hash(Double(i) * 3.3)) * 1.4
                if i % 9 == 0 { bright.addEllipse(in: CGRect(x: x, y: y, width: d + 0.8, height: d + 0.8)) }
                else { stars.addEllipse(in: CGRect(x: x, y: y, width: d, height: d)) }
            }
            ctx.fill(stars, with: .color(.white.opacity(0.55)))
            ctx.fill(bright, with: .color(.white.opacity(0.95)))
            let m = min(w, h)
            switch min(max(level, 1), 7) {
            case 1, 2:
                // Earth, half lit.
                let r = m * 0.075, c = CGPoint(x: w * 0.8, y: h * 0.2)
                let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 1.25, y: c.y - r * 1.25, width: r * 2.5, height: r * 2.5)),
                         with: .radialGradient(Gradient(colors: [Color(red: 0.4, green: 0.7, blue: 1).opacity(0.3), .clear]), center: c, startRadius: r * 0.9, endRadius: r * 1.25))
                ctx.fill(disc, with: .color(Color(red: 0.18, green: 0.42, blue: 0.82)))
                var earth = ctx
                earth.clip(to: disc)
                var land = Path()
                land.addEllipse(in: CGRect(x: c.x - r * 0.6, y: c.y - r * 0.55, width: r * 0.7, height: r * 0.5))
                land.addEllipse(in: CGRect(x: c.x + r * 0.05, y: c.y + r * 0.05, width: r * 0.5, height: r * 0.7))
                earth.fill(land, with: .color(Color(red: 0.32, green: 0.55, blue: 0.3)))
                var clouds = Path()
                clouds.addEllipse(in: CGRect(x: c.x - r * 0.9, y: c.y - r * 0.15, width: r * 1.1, height: r * 0.22))
                clouds.addEllipse(in: CGRect(x: c.x - r * 0.2, y: c.y - r * 0.8, width: r * 0.9, height: r * 0.2))
                earth.fill(clouds, with: .color(.white.opacity(0.8)))
                earth.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.35, y: c.y - r * 1.1, width: r * 2.2, height: r * 2.3)), with: .color(.black.opacity(0.62)))
            case 3, 4, 5:
                // Phobos and Deimos, and a dusty glow over the horizon.
                ctx.fill(Path(CGRect(x: 0, y: h * 0.45, width: w, height: h * 0.55)),
                         with: .linearGradient(Gradient(colors: [.clear, Color(red: 0.6, green: 0.25, blue: 0.12).opacity(0.22)]), startPoint: CGPoint(x: 0, y: h * 0.45), endPoint: CGPoint(x: 0, y: h * 0.8)))
                let r = m * 0.032, c = CGPoint(x: w * 0.78, y: h * 0.17)
                let phobos = Path(ellipseIn: CGRect(x: c.x - r * 1.2, y: c.y - r * 0.85, width: r * 2.4, height: r * 1.7))
                ctx.fill(phobos, with: .color(Color(red: 0.62, green: 0.54, blue: 0.48)))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.3, y: c.y - r * 0.9, width: r * 1.6, height: r * 1.8)), with: .color(.black.opacity(0.45)))
                ctx.fill(Path(ellipseIn: CGRect(x: w * 0.26, y: h * 0.1, width: m * 0.022, height: m * 0.02)), with: .color(Color(red: 0.75, green: 0.68, blue: 0.6)))
            default:
                // A ringed giant and a violet haze.
                let r = m * 0.11, c = CGPoint(x: w * 0.2, y: h * 0.15)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 2.2, y: c.y - r * 1.6, width: r * 4.4, height: r * 3.2)),
                         with: .radialGradient(Gradient(colors: [Color(red: 0.5, green: 0.3, blue: 0.9).opacity(0.18), .clear]), center: c, startRadius: r, endRadius: r * 2.2))
                var back = Path()
                back.addEllipse(in: CGRect(x: c.x - r * 1.9, y: c.y - r * 0.38, width: r * 3.8, height: r * 0.76))
                ctx.stroke(back, with: .color(Color(red: 0.8, green: 0.7, blue: 1).opacity(0.5)), lineWidth: 2)
                let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                ctx.fill(disc, with: .linearGradient(Gradient(colors: [Color(red: 0.62, green: 0.46, blue: 0.9), Color(red: 0.34, green: 0.2, blue: 0.56)]),
                                                     startPoint: CGPoint(x: c.x, y: c.y - r), endPoint: CGPoint(x: c.x, y: c.y + r)))
                var bands = ctx
                bands.clip(to: disc)
                for k in 0..<4 {
                    bands.fill(Path(CGRect(x: c.x - r, y: c.y - r * 0.7 + CGFloat(k) * r * 0.42, width: r * 2, height: r * 0.12)), with: .color(.white.opacity(0.12)))
                }
                bands.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.2, y: c.y - r * 1.2, width: r * 2.2, height: r * 2.4)), with: .color(.black.opacity(0.4)))
                var front = Path()
                front.addArc(center: .zero, radius: 1, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
                ctx.stroke(front.applying(CGAffineTransform(scaleX: r * 1.9, y: r * 0.38).concatenating(CGAffineTransform(translationX: c.x, y: c.y))),
                           with: .color(Color(red: 0.86, green: 0.78, blue: 1).opacity(0.8)), lineWidth: 2.5)
            }
        }
    }
}

/// Speed or fuel as an icon and a bar; the speed bar's tick is the safe touchdown limit.
private struct LLGauge: View {
    let icon: String
    let fraction: Double
    let mark: Double?
    let color: Color
    let small: Bool

    var body: some View {
        let bw: CGFloat = small ? 58 : 84, bh: CGFloat = small ? 6 : 8
        HStack(spacing: small ? 5 : 7) {
            Image(systemName: icon)
                .font(.system(size: small ? 12 : 16, weight: .bold))
                .foregroundStyle(color)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14))
                Capsule().fill(color).frame(width: bw * CGFloat(max(0, min(1, fraction))))
                if let m = mark {
                    Rectangle().fill(.white).frame(width: 2, height: bh + 6).offset(x: bw * CGFloat(m) - 1)
                }
            }
            .frame(width: bw, height: bh)
        }
    }
}

/// Console keys: gunmetal rotate keys, an amber engine key.
private struct LLKey: View {
    let wide: Bool
    let lit: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: wide ? (lit ? [Color(red: 1, green: 0.95, blue: 0.66), Color(red: 1, green: 0.68, blue: 0.24)]
                                                         : [Color(red: 0.92, green: 0.58, blue: 0.2), Color(red: 0.72, green: 0.36, blue: 0.08)])
                                                  : [Color(white: lit ? 0.46 : 0.3), Color(white: lit ? 0.28 : 0.16)],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 14).strokeBorder(Color.black.opacity(0.6), lineWidth: 2)
            RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(lit ? 0.9 : 0.16), lineWidth: 1.2).padding(3)
        }
    }
}
