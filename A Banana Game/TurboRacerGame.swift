//
//  TurboRacerGame.swift
//  A Banana Game
//
//  Reflex — a Pole Position / OutRun style pseudo-3D racer. The road is drawn
//  scanline-by-scanline, curving toward a vanishing point with checkerboard grass
//  and rushing rumble stripes for speed. Hold ◄ ► to steer your car at the bottom;
//  hug the tarmac through the curves and slalom past slower traffic. Reach the
//  finish line to win. Slam into a car or slide off the road, or run out of time,
//  and you fall back to level 1.
//
//  7 levels: higher top speed, denser traffic, and sharper curves through a
//  day → dusk → night → neon ramp — level 7 is a white-knuckle blur.
//
//  Steering is fixed on-screen buttons, so this stays tap-safe (no feed lock).
//

import SwiftUI

enum TurboRacerGame {
    static let definition = GameDefinition(
        id: "turbo-racer",
        title: "Turbo Racer",
        emoji: "🍌",
        genre: .reflex,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Hold ◄ ► to steer down a curving pseudo-3D road.",
                "Hug the tarmac through bends and slalom past slower traffic.",
                "Reach the finish to win; a crash, sliding off, or the clock ends the run.",
            ],
            bulletsVI: [
                "Giữ ◄ ► để lái trên con đường 3D uốn lượn.",
                "Bám mặt đường qua các khúc cua và luồn lách qua xe chậm.",
                "Về đích để thắng; va chạm, trượt khỏi đường, hoặc hết giờ là thua.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(TurboRacerView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct TurboRacerView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    // MARK: Difficulty
    // Speed is cranked WAY up so the road and traffic scream past — the whole game
    // should feel like a blur. `finish` scales with speed so each course still runs a
    // sane ~44–50s (timeLimit = finish/speed + 10).
    private var speed: Double     { [4.6, 5.6, 6.8, 8.0, 9.4, 10.8, 12.4][min(level, 7) - 1] }
    private var finish: Double    { [156, 196, 245, 296, 357, 421, 496][min(level, 7) - 1] }
    private var curveAmp: Double  { [0.35, 0.45, 0.6, 0.75, 0.9, 1.05, 1.2][min(level, 7) - 1] }
    private var curveFreq: Double { [0.10, 0.11, 0.12, 0.13, 0.14, 0.15, 0.16][min(level, 7) - 1] }
    private var spawnGap: Double  { [7.0, 6.0, 5.0, 4.2, 3.6, 3.0, 2.6][min(level, 7) - 1] }
    private var timeLimit: Double { finish / speed + 10 }

    private let hy: CGFloat = 0.32          // horizon (fraction of the play area)
    private let maxHalf: CGFloat = 0.42     // road half-width at the bottom
    private let viewRange: Double = 18      // how far ahead traffic is visible (distance units)
    private let playerY: CGFloat = 0.90     // player car's fixed screen depth
    private let steerRate: Double = 2.4     // responsive enough to survive the higher speed
    private let driftRate: Double = 1.05

    private struct Car: Identifiable {
        let id = UUID()
        let worldZ: Double
        let roadX: Double       // -1…1 across the road
        let color: Color
        var passed = false
        let kind = Int.random(in: 0..<4)   // presentation: beetle, sedan, van or sports car
    }
    private struct Burst: Identifiable { let id = UUID(); let x: CGFloat; let y: CGFloat }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var distance: Double = 0
    @State private var curve: Double = 0
    @State private var playerX: Double = 0
    @State private var steer: Double = 0
    @State private var cars: [Car] = []
    @State private var lastSpawn: Double = 0
    @State private var bursts: [Burst] = []
    @State private var timeLeft = 0.0
    @State private var shakeTick = 0
    @State private var loopTask: Task<Void, Never>?
    @State private var built = false
    @State private var demoSteer: Double = 0     // which steer button the demo is "holding"

    private let trafficColors: [Color] = [
        Color(red: 0.90, green: 0.30, blue: 0.32), Color(red: 0.35, green: 0.55, blue: 0.95),
        Color(red: 0.45, green: 0.80, blue: 0.45), Color(red: 0.85, green: 0.55, blue: 0.95)
    ]

    /// The level's OutRun stage: coast, countryside, desert, sunset, mountains, night city, neon.
    private var stage: OutRunStage { OutRunArt.stage(level) }

    var body: some View {
        VStack(spacing: isDemo ? 8 : 12) {
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let st = stage
                ZStack(alignment: .topLeading) {
                    // Sky + horizon scenery, drifting against the bends (parallax). The strip is wider
                    // than the card, so it rides in an overlay that can't widen the layout.
                    Color.clear
                        .frame(width: w, height: hy * h + 1)
                        .overlay(alignment: .leading) {
                            OutRunSky(level: level, width: w, height: hy * h).equatable()
                                .frame(width: w * 1.4, height: hy * h + 1)
                                .offset(x: -w * 0.2 - CGFloat(curve) * w * 0.14)
                        }
                    Canvas { ctx, size in drawWorld(ctx, size, st) }
                        .frame(width: w, height: h)
                    ForEach(bursts) { b in
                        ParticleBurstView(color: .orange, count: 16, spread: 60) {
                            bursts.removeAll { $0.id == b.id }
                        }
                        .position(x: b.x * w, y: b.y * h)
                    }
                    hud
                        .frame(width: w, height: h)
                }
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 18))
                .screenShake(shakeTick, amount: 6)
            }
            .padding(.horizontal, isDemo ? 0 : 8)

            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
    }

    /// OutRun's HUD: TIME counting down (top-left), course progress (top-right), km/h (bottom-left).
    private var hud: some View {
        let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
        let pct = Int(min(distance, finish) / finish * 100)
        return VStack(alignment: .leading) {
            HStack(alignment: .top) {
                if !isDemo {
                    VStack(alignment: .leading, spacing: -4) {
                        hudText(L("TIME", "GIỜ"), size: 13, color: Color(red: 1, green: 0.5, blue: 0.2))
                        hudText("\(Int(ceil(timeLeft)))", size: 34,
                                color: frac < 0.3 ? Color(red: 1, green: 0.25, blue: 0.2) : Color(red: 1, green: 0.9, blue: 0.2))
                    }
                }
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: isDemo ? 14 : 18, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 0, x: 1.5, y: 1.5)
                    hudText("\(pct)%", size: isDemo ? 18 : 24, color: .white)
                }
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                hudText("\(Int(speed * 30 + 60))", size: isDemo ? 16 : 22, color: .white)
                hudText("km/h", size: isDemo ? 10 : 12, color: Color(red: 1, green: 0.5, blue: 0.2))
            }
        }
        .padding(.horizontal, isDemo ? 10 : 12)
        .padding(.vertical, isDemo ? 8 : 10)
        .allowsHitTesting(false)
    }

    private func hudText(_ s: String, size: CGFloat, color: Color) -> some View {
        Text(s)
            .font(.system(size: size, weight: .black, design: .rounded).italic())
            .foregroundStyle(color)
            .shadow(color: .black, radius: 0, x: 1.5, y: 1.5)
            .shadow(color: .black.opacity(0.8), radius: 0, x: -1, y: -1)
            .monospacedDigit()
    }
    // MARK: - Demo (live manual clip)

    /// Drive the scrolling road and the progress % from 0 → 100 in a few seconds, with
    /// the car gently weaving and traffic streaming past (no collisions / fail in demo).
    private func runDemo() async {
        while !Task.isCancelled {
            setup()
            let rate = finish / 3.2         // reach the finish in ~3s
            var spawnT = 0.6
            var nextSide = 0.6
            while distance < finish && !Task.isCancelled {
                let dt = 0.016
                spawnT += dt
                distance = min(finish, distance + rate * dt)
                curve = curveAmp * sin(distance * curveFreq)

                // Traffic streams in from alternating sides.
                if spawnT >= 0.8 {
                    spawnT = 0
                    cars.append(Car(worldZ: distance + viewRange, roadX: nextSide,
                                    color: trafficColors.randomElement()!))
                    nextSide = -nextSide
                }
                // Auto-dodge: ease toward the side opposite the nearest car ahead, so the
                // banana car threads the gap instead of ploughing through traffic.
                var nearestX: Double? = nil
                var nearestRel = Double.greatestFiniteMagnitude
                for car in cars {
                    let rel = car.worldZ - distance
                    if rel > 0.2, rel < 7, rel < nearestRel { nearestRel = rel; nearestX = car.roadX }
                }
                let targetX = nearestX.map { $0 > 0 ? -0.55 : 0.55 } ?? 0.0
                playerX += (targetX - playerX) * 0.12
                demoSteer = abs(targetX - playerX) > 0.06 ? (targetX > playerX ? 1 : -1) : 0

                cars.removeAll { $0.worldZ - distance < -2 }
                try? await Task.sleep(for: .seconds(dt))
            }
            demoSteer = 0
            try? await Task.sleep(for: .seconds(1.2))   // hold on 100%
        }
    }

    /// Road, roadside scenery and traffic (far → near), then the player's car — one Canvas.
    /// Traffic and the car use exactly the projection the collision code in `step` uses.
    private func drawWorld(_ ctx: GraphicsContext, _ size: CGSize, _ st: OutRunStage) {
        let W = size.width, H = size.height
        OutRunArt.road(ctx, size: size, hy: hy, maxHalf: maxHalf, curve: curve, distance: distance, stage: st)

        func project(_ rel: Double, _ roadX: Double) -> (p: CGPoint, scale: CGFloat) {
            let t = 1 - rel / viewRange
            let half = Double(maxHalf) * (0.08 + 0.92 * t)
            let center = 0.5 + curve * 0.35 * (1 - t)
            return (CGPoint(x: CGFloat(center + roadX * half) * W, y: (hy + CGFloat(t) * (1 - hy)) * H), CGFloat(0.10 + 0.90 * t))
        }

        enum Sprite { case prop(Int, Double), car(Car) }
        var sprites: [(rel: Double, s: Sprite)] = []
        let gap = 2.4
        let k0 = Int(ceil((distance + 0.25) / gap)), k1 = Int(floor((distance + viewRange - 0.1) / gap))
        if k0 <= k1 {
            for k in k0...k1 where st.prop != 6 || k % 2 == 0 {   // neon palms are spaced out
                sprites.append((Double(k) * gap - distance, .prop(k, -1)))
                sprites.append((Double(k) * gap - distance + gap / 2, .prop(k, 1)))
            }
        }
        for car in cars {
            let rel = car.worldZ - distance
            if rel > 0.2 && rel < viewRange { sprites.append((rel, .car(car))) }
        }
        for (rel, s) in sprites.sorted(by: { $0.rel > $1.rel }) where rel > 0.2 && rel < viewRange {
            switch s {
            case let .prop(k, side):
                let jitter = Double((k * 7919 + (side > 0 ? 31 : 0)) % 100) / 100
                let (p, sc) = project(rel, side * (1.42 + 0.35 * jitter))
                OutRunArt.prop(ctx, kind: st.prop, ground: p, scale: sc, H: H, side: CGFloat(side), variant: k)
            case let .car(car):
                let (p, sc) = project(rel, car.roadX)
                let cw = 0.17 * W * sc
                OutRunArt.traffic(ctx, kind: car.kind, center: p, width: cw, color: car.color, night: level >= 6)
            }
        }

        let lean = steer != 0 ? steer : demoSteer
        OutRunArt.playerCar(ctx, center: CGPoint(x: (0.5 + CGFloat(playerX) * maxHalf) * W, y: playerY * H),
                            width: 0.19 * W, lean: CGFloat(lean), night: level >= 6)
    }

    private var controls: some View {
        HStack(spacing: isDemo ? 28 : 40) {
            holdButton("chevron.left", dir: -1)
            holdButton("chevron.right", dir: 1)
        }
        .padding(.bottom, isDemo ? 4 : 8)
    }

    private func holdButton(_ icon: String, dir: Double) -> some View {
        let pressed = isDemo && demoSteer == dir
        return Image(systemName: icon)
            .font(.system(size: isDemo ? 24 : 30, weight: .black)).foregroundStyle(.black)
            .frame(width: isDemo ? 84 : 100, height: isDemo ? 50 : 66)
            .background(pressed ? BananaTheme.banana.lit(0.3) : BananaTheme.banana,
                        in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(pressed ? 0.95 : 0.4), lineWidth: pressed ? 3 : 2))
            .scaleEffect(pressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if phase == .play { steer = dir } }
                .onEnded { _ in if steer == dir { steer = 0 } })
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
                let dt = min(0.05, now.timeIntervalSince(last))
                last = now
                timeLeft = max(0, timeLimit - now.timeIntervalSince(start))
                if timeLeft <= 0 { fail(); break }
                step(dt: dt)
            }
        }
    }

    private func setup() {
        distance = 0; curve = 0; playerX = 0; steer = 0
        cars = []; bursts = []; lastSpawn = 0
        timeLeft = timeLimit
        phase = .play
    }

    private func step(dt: Double) {
        guard phase == .play else { return }
        distance += speed * dt
        curve = curveAmp * sin(distance * curveFreq)

        playerX += steer * steerRate * dt
        playerX -= curve * driftRate * dt

        // Off the tarmac → spin out.
        if abs(playerX) > 1.15 { crash(atX: 0.5 + playerX * Double(maxHalf), atY: 0.9); return }

        // Spawn upcoming traffic.
        if distance - lastSpawn >= spawnGap {
            lastSpawn = distance
            cars.append(Car(worldZ: distance + viewRange,
                            roadX: Double.random(in: -0.7...0.7),
                            color: trafficColors.randomElement()!))
        }

        // Resolve passes / collisions — judged at the player's ACTUAL drawn depth using
        // the same projection the renderer uses, so what you see is what you hit. (The old
        // code tested overlap at rel<=0, i.e. the screen bottom BELOW the player sprite,
        // which made crashes feel random.)
        let tP = Double((playerY - hy) / (1 - hy))
        let relPlayer = viewRange * (1 - tP)
        let halfP = Double(maxHalf) * (0.08 + 0.92 * tP)
        let centerP = 0.5 + curve * 0.35 * (1 - tP)
        let carWP = 0.17 * (0.10 + 0.90 * tP)            // traffic sprite width (screen frac)
        let playerScreenX = 0.5 + playerX * Double(maxHalf)
        let hitThresh = (carWP + 0.19) * 0.5 * 0.82      // sum of half-widths, 18% forgiveness
        for i in cars.indices {
            let rel = cars[i].worldZ - distance
            if rel <= relPlayer && !cars[i].passed {
                cars[i].passed = true
                let carScreenX = centerP + cars[i].roadX * halfP
                if abs(carScreenX - playerScreenX) < hitThresh {
                    crash(atX: carScreenX, atY: Double(playerY)); return
                }
            }
        }
        cars.removeAll { $0.worldZ - distance < -2 }

        if distance >= finish { win() }
    }

    private func crash(atX: Double, atY: Double) {
        bursts.append(Burst(x: CGFloat(atX), y: CGFloat(atY)))
        shakeTick += 1
        fail()
    }

    private func win() {
        guard phase == .play else { return }
        phase = .done
        loopTask?.cancel()
        Haptics.success(); SoundManager.shared.tap()
        onWin()
    }

    private func fail() {
        guard phase == .play else { return }
        phase = .done
        loopTask?.cancel()
        SoundManager.shared.error(); Haptics.warning()
        onFail()
    }

}

// MARK: - OutRun art

/// One stage of the drive (one per level), OutRun style.
private struct OutRunStage {
    let skyTop: Color, skyBottom: Color
    let groundA: Color, groundB: Color
    let roadA: Color, roadB: Color
    let rumbleA: Color, rumbleB: Color
    let lane: Color
    let prop: Int       // 0 palm, 1 round tree, 2 saguaro, 3 palm silhouette, 4 pine, 5 street lamp, 6 neon palm
    let scenery: Int    // 0 sea + island, 1 hills, 2 mesas, 3 sunset sea, 4 snowy peaks, 5 city, 6 synthwave sun
}

private enum OutRunArt {
    static func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    static func stage(_ level: Int) -> OutRunStage {
        switch min(max(level, 1), 7) {
        case 1:  // Coconut beach
            return OutRunStage(skyTop: c(0.1, 0.44, 0.95), skyBottom: c(0.6, 0.83, 1.0),
                               groundA: c(0.94, 0.86, 0.64), groundB: c(0.89, 0.8, 0.57),
                               roadA: c(0.5, 0.5, 0.53), roadB: c(0.46, 0.46, 0.49),
                               rumbleA: .white, rumbleB: c(0.88, 0.12, 0.12), lane: .white, prop: 0, scenery: 0)
        case 2:  // Countryside
            return OutRunStage(skyTop: c(0.22, 0.52, 0.95), skyBottom: c(0.74, 0.9, 1.0),
                               groundA: c(0.42, 0.72, 0.3), groundB: c(0.36, 0.65, 0.26),
                               roadA: c(0.48, 0.48, 0.5), roadB: c(0.44, 0.44, 0.46),
                               rumbleA: .white, rumbleB: c(0.88, 0.12, 0.12), lane: .white, prop: 1, scenery: 1)
        case 3:  // Desert
            return OutRunStage(skyTop: c(0.96, 0.6, 0.28), skyBottom: c(1.0, 0.87, 0.62),
                               groundA: c(0.9, 0.64, 0.38), groundB: c(0.84, 0.58, 0.34),
                               roadA: c(0.52, 0.46, 0.42), roadB: c(0.48, 0.42, 0.39),
                               rumbleA: .white, rumbleB: c(0.85, 0.2, 0.1), lane: c(1, 0.95, 0.85), prop: 2, scenery: 2)
        case 4:  // Sunset coast
            return OutRunStage(skyTop: c(0.3, 0.17, 0.48), skyBottom: c(1.0, 0.52, 0.3),
                               groundA: c(0.5, 0.34, 0.3), groundB: c(0.45, 0.3, 0.27),
                               roadA: c(0.34, 0.3, 0.36), roadB: c(0.31, 0.27, 0.33),
                               rumbleA: c(1, 0.85, 0.6), rumbleB: c(0.95, 0.35, 0.2), lane: c(1, 0.9, 0.75), prop: 3, scenery: 3)
        case 5:  // Alpine dusk
            return OutRunStage(skyTop: c(0.16, 0.15, 0.4), skyBottom: c(0.72, 0.42, 0.55),
                               groundA: c(0.2, 0.36, 0.3), groundB: c(0.17, 0.31, 0.26),
                               roadA: c(0.3, 0.3, 0.35), roadB: c(0.27, 0.27, 0.32),
                               rumbleA: .white, rumbleB: c(0.85, 0.15, 0.2), lane: .white, prop: 4, scenery: 4)
        case 6:  // Night city
            return OutRunStage(skyTop: c(0.02, 0.03, 0.1), skyBottom: c(0.13, 0.11, 0.3),
                               groundA: c(0.1, 0.11, 0.16), groundB: c(0.08, 0.09, 0.13),
                               roadA: c(0.21, 0.21, 0.25), roadB: c(0.18, 0.18, 0.22),
                               rumbleA: c(0.85, 0.85, 0.9), rumbleB: c(0.8, 0.15, 0.2), lane: c(1, 0.85, 0.3), prop: 5, scenery: 5)
        default: // Neon
            return OutRunStage(skyTop: c(0.04, 0.0, 0.1), skyBottom: c(0.4, 0.03, 0.34),
                               groundA: c(0.12, 0.02, 0.2), groundB: c(0.08, 0.01, 0.14),
                               roadA: c(0.14, 0.08, 0.2), roadB: c(0.11, 0.06, 0.16),
                               rumbleA: c(0.3, 1, 0.95), rumbleB: c(1, 0.2, 0.75), lane: c(0.4, 1, 0.95), prop: 6, scenery: 6)
        }
    }

    private static func ellipse(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h))
    }

    /// A tiny deterministic noise for scenery placement.
    static func hash(_ i: Int) -> CGFloat {
        let v = sin(Double(i) * 12.9898 + 78.233) * 43758.5453
        return CGFloat(v - floor(v))
    }

    // MARK: Road

    /// The pseudo-3D road in horizontal bands: ground, red/white curbs, asphalt, edge lines and
    /// dashed lane lines. Same geometry and band phase as the old scanline renderer, but each run of
    /// same-coloured rows is one polygon instead of dozens of rectangles.
    static func road(_ ctx: GraphicsContext, size: CGSize, hy: CGFloat, maxHalf: CGFloat,
                     curve: Double, distance: Double, stage st: OutRunStage) {
        let W = size.width, H = size.height
        let top = hy * H
        struct Row { let y: CGFloat; let c: CGFloat; let h: CGFloat; let even: Bool }
        var rows: [Row] = []
        var y = top
        while y <= H + 2 {
            let t = min(1, max(0, (y - top) / max(1, H - top)))
            let half = maxHalf * (0.08 + 0.92 * t) * W
            let center = CGFloat(0.5 + curve * 0.35 * Double(1 - t)) * W
            let ph = distance * 1.1 + Double(pow(1 - t, 2)) * 26
            rows.append(Row(y: y, c: center, h: half, even: Int(ph) % 2 == 0))
            y += 2
        }
        guard rows.count > 1 else { return }
        var i = 0
        while i < rows.count - 1 {
            var j = i
            while j + 1 < rows.count - 1 && rows[j + 1].even == rows[i].even { j += 1 }
            let seg = Array(rows[i...(j + 1)])
            let even = rows[i].even
            func band(_ l: (Row) -> CGFloat, _ r: (Row) -> CGFloat) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: l(seg[0]), y: seg[0].y))
                for rw in seg.dropFirst() { p.addLine(to: CGPoint(x: l(rw), y: rw.y)) }
                for rw in seg.reversed() { p.addLine(to: CGPoint(x: r(rw), y: rw.y)) }
                p.closeSubpath()
                return p
            }
            ctx.fill(Path(CGRect(x: 0, y: seg[0].y, width: W, height: seg[seg.count - 1].y - seg[0].y + 0.6)),
                     with: .color(even ? st.groundA : st.groundB))
            ctx.fill(band({ $0.c - $0.h * 1.14 }, { $0.c + $0.h * 1.14 }), with: .color(even ? st.rumbleA : st.rumbleB))
            ctx.fill(band({ $0.c - $0.h }, { $0.c + $0.h }), with: .color(even ? st.roadA : st.roadB))
            ctx.fill(band({ $0.c - $0.h * 0.97 }, { $0.c - $0.h * 0.935 }), with: .color(st.lane.opacity(0.85)))
            ctx.fill(band({ $0.c + $0.h * 0.935 }, { $0.c + $0.h * 0.97 }), with: .color(st.lane.opacity(0.85)))
            if even {
                for k: CGFloat in [-1.0 / 3, 1.0 / 3] {
                    ctx.fill(band({ $0.c + $0.h * (k - 0.018) }, { $0.c + $0.h * (k + 0.018) }), with: .color(st.lane))
                }
            }
            i = j + 1
        }
        // Haze where the road meets the sky.
        ctx.fill(Path(CGRect(x: 0, y: top, width: W, height: (H - top) * 0.12)),
                 with: .linearGradient(Gradient(colors: [st.skyBottom.opacity(0.55), st.skyBottom.opacity(0)]),
                                       startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: top + (H - top) * 0.12)))
    }

    // MARK: Roadside

    static func prop(_ ctx: GraphicsContext, kind: Int, ground g: CGPoint, scale s: CGFloat, H: CGFloat,
                     side: CGFloat, variant: Int) {
        switch kind {
        case 0: palm(ctx, g, h: H * 0.5 * s, lean: -side, trunk: c(0.62, 0.44, 0.26), leaf: c(0.16, 0.58, 0.22), style: 0)
        case 1: roundTree(ctx, g, h: H * 0.34 * s, variant: variant)
        case 2: cactus(ctx, g, h: H * 0.3 * s, variant: variant)
        case 3: palm(ctx, g, h: H * 0.5 * s, lean: -side, trunk: c(0.16, 0.08, 0.14), leaf: c(0.14, 0.07, 0.12), style: 1)
        case 4: pine(ctx, g, h: H * 0.42 * s, variant: variant)
        case 5: lamp(ctx, g, h: H * 0.46 * s, side: side)
        default: palm(ctx, g, h: H * 0.5 * s, lean: -side, trunk: c(1, 0.25, 0.75), leaf: c(0.3, 1, 0.95), style: 2)
        }
    }

    /// A leaning coconut palm. style 0 = painted, 1 = sunset silhouette, 2 = neon outline.
    static func palm(_ ctx: GraphicsContext, _ g: CGPoint, h: CGFloat, lean: CGFloat, trunk: Color, leaf: Color, style: Int) {
        guard h > 4 else { return }
        let top = CGPoint(x: g.x + lean * h * 0.3, y: g.y - h)
        let ctrl = CGPoint(x: g.x + lean * h * 0.02, y: g.y - h * 0.6)
        func bez(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            return CGPoint(x: u * u * g.x + 2 * u * t * ctrl.x + t * t * top.x, y: u * u * g.y + 2 * u * t * ctrl.y + t * t * top.y)
        }
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in 0...10 {
            let t = CGFloat(i) / 10
            let p = bez(t), a = bez(max(0, t - 0.05)), b = bez(min(1, t + 0.05))
            let len = max(0.001, hypot(b.x - a.x, b.y - a.y))
            let nx = -(b.y - a.y) / len, ny = (b.x - a.x) / len
            let w = h * (0.048 - 0.022 * t)
            left.append(CGPoint(x: p.x + nx * w, y: p.y + ny * w))
            right.append(CGPoint(x: p.x - nx * w, y: p.y - ny * w))
        }
        var stem = Path()
        stem.addLines(left)
        stem.addLines(right.reversed())
        stem.closeSubpath()
        if style == 2 {
            ctx.stroke(stem, with: .color(trunk.opacity(0.3)), lineWidth: max(2, h * 0.035))
            ctx.stroke(stem, with: .color(trunk), lineWidth: max(1, h * 0.01))
        } else {
            if style == 0 {
                ctx.fill(ellipse(g.x - h * 0.12, g.y - h * 0.02, h * 0.24, h * 0.05), with: .color(.black.opacity(0.18)))
            }
            ctx.fill(stem, with: .color(trunk))
            if style == 0 && h > 60 {          // trunk rings only up close (level of detail)
                for i in 1..<10 {
                    let t = CGFloat(i) / 10
                    let a = left[i], b = right[i]
                    var ring = Path()
                    ring.move(to: a)
                    ring.addQuadCurve(to: b, control: CGPoint(x: (a.x + b.x) / 2 + (bez(t).x - bez(max(0, t - 0.1)).x),
                                                              y: (a.y + b.y) / 2 + h * 0.012))
                    ctx.stroke(ring, with: .color(trunk.shade(0.35)), lineWidth: max(0.5, h * 0.008))
                }
            }
        }
        let angles: [Double] = [-172, -142, -112, -78, -44, -14, 16]
        for (i, a) in angles.enumerated() {
            let rad = a * .pi / 180
            let L = h * (0.36 + 0.05 * CGFloat(i % 2))
            let tip = CGPoint(x: top.x + CGFloat(cos(rad)) * L, y: top.y + CGFloat(sin(rad)) * L * 0.55 + L * 0.35)
            let mid = CGPoint(x: (top.x + tip.x) / 2, y: min(top.y, tip.y) - L * 0.16)
            var frond = Path()
            frond.move(to: top)
            frond.addQuadCurve(to: tip, control: CGPoint(x: mid.x, y: mid.y - L * 0.1))
            frond.addQuadCurve(to: top, control: CGPoint(x: mid.x, y: mid.y + L * 0.12))
            switch style {
            case 2:
                ctx.stroke(frond, with: .color(leaf.opacity(0.3)), lineWidth: max(2, h * 0.03))
                ctx.stroke(frond, with: .color(leaf), lineWidth: max(1, h * 0.008))
            case 1:
                ctx.fill(frond, with: .color(leaf))
            default:
                ctx.fill(frond, with: .color(i % 2 == 0 ? leaf : leaf.lit(0.15)))
                if h > 50 {
                    var rib = Path()
                    rib.move(to: top)
                    rib.addQuadCurve(to: tip, control: mid)
                    ctx.stroke(rib, with: .color(leaf.shade(0.35)), lineWidth: max(0.5, h * 0.006))
                }
            }
        }
        if style == 0 && h > 30 {
            for (dx, dy) in [(-0.035, 0.03), (0.03, 0.035), (0.0, 0.06)] as [(CGFloat, CGFloat)] {
                let r = h * 0.03
                ctx.fill(ellipse(top.x + dx * h - r, top.y + dy * h - r, r * 2, r * 2), with: .color(c(0.45, 0.28, 0.12)))
            }
        }
    }

    static func roundTree(_ ctx: GraphicsContext, _ g: CGPoint, h: CGFloat, variant: Int) {
        guard h > 4 else { return }
        ctx.fill(ellipse(g.x - h * 0.26, g.y - h * 0.04, h * 0.52, h * 0.1), with: .color(.black.opacity(0.2)))
        ctx.fill(Path(CGRect(x: g.x - h * 0.05, y: g.y - h * 0.46, width: h * 0.1, height: h * 0.46)), with: .color(c(0.42, 0.28, 0.15)))
        let tint = variant % 3 == 0 ? 0.06 : 0.0
        let dark = c(0.1 + tint, 0.42, 0.16), mid = c(0.18 + tint, 0.56, 0.22), light = c(0.34 + tint, 0.72, 0.3)
        for (x, y, r, col) in [(-0.15, -0.6, 0.24, dark), (0.15, -0.62, 0.24, dark), (0.0, -0.8, 0.28, mid), (-0.07, -0.86, 0.12, light)]
            as [(CGFloat, CGFloat, CGFloat, Color)] {
            ctx.fill(ellipse(g.x + x * h - r * h, g.y + y * h - r * h, r * h * 2, r * h * 2), with: .color(col))
        }
    }

    static func cactus(_ ctx: GraphicsContext, _ g: CGPoint, h: CGFloat, variant: Int) {
        guard h > 4 else { return }
        let w = h * 0.17
        let green = c(0.3, 0.58, 0.3), dark = c(0.15, 0.36, 0.18)
        ctx.fill(ellipse(g.x - h * 0.22, g.y - h * 0.03, h * 0.44, h * 0.08), with: .color(.black.opacity(0.2)))
        var body = Path(roundedRect: CGRect(x: g.x - w / 2, y: g.y - h, width: w, height: h), cornerRadius: w / 2)
        let lh = variant % 2 == 0 ? 0.5 : 0.58
        body.addPath(Path(roundedRect: CGRect(x: g.x - w * 1.7, y: g.y - h * CGFloat(lh) - w * 0.5, width: w * 1.4, height: w), cornerRadius: w / 2))
        body.addPath(Path(roundedRect: CGRect(x: g.x - w * 1.7, y: g.y - h * CGFloat(lh + 0.28), width: w, height: h * 0.3), cornerRadius: w / 2))
        body.addPath(Path(roundedRect: CGRect(x: g.x + w * 0.3, y: g.y - h * 0.62 - w * 0.5, width: w * 1.4, height: w), cornerRadius: w / 2))
        body.addPath(Path(roundedRect: CGRect(x: g.x + w * 0.7, y: g.y - h * 0.86, width: w, height: h * 0.3), cornerRadius: w / 2))
        ctx.fill(body, with: .linearGradient(Gradient(colors: [green.lit(0.2), green, dark]),
                                             startPoint: CGPoint(x: g.x - w * 1.7, y: 0), endPoint: CGPoint(x: g.x + w * 1.7, y: 0)))
        var ribs = Path()
        for dx: CGFloat in [-0.18, 0.18] {
            ribs.move(to: CGPoint(x: g.x + dx * w, y: g.y - h * 0.95)); ribs.addLine(to: CGPoint(x: g.x + dx * w, y: g.y - h * 0.05))
        }
        ctx.stroke(ribs, with: .color(dark.opacity(0.6)), lineWidth: max(0.5, w * 0.08))
    }

    static func pine(_ ctx: GraphicsContext, _ g: CGPoint, h: CGFloat, variant: Int) {
        guard h > 4 else { return }
        ctx.fill(Path(CGRect(x: g.x - h * 0.035, y: g.y - h * 0.16, width: h * 0.07, height: h * 0.16)), with: .color(c(0.3, 0.2, 0.14)))
        let greens = [c(0.08, 0.26, 0.2), c(0.1, 0.31, 0.24), c(0.13, 0.36, 0.28)]
        for k in 0..<3 {
            let bottom = g.y - h * (0.12 + CGFloat(k) * 0.22)
            let w = h * (0.34 - CGFloat(k) * 0.08)
            var tri = Path()
            tri.move(to: CGPoint(x: g.x - w, y: bottom))
            tri.addLine(to: CGPoint(x: g.x + w, y: bottom))
            tri.addLine(to: CGPoint(x: g.x, y: bottom - h * 0.42))
            tri.closeSubpath()
            ctx.fill(tri, with: .color(greens[k]))
            var snow = Path()
            snow.move(to: CGPoint(x: g.x, y: bottom - h * 0.42))
            snow.addLine(to: CGPoint(x: g.x - w * 0.3, y: bottom - h * 0.3))
            snow.addLine(to: CGPoint(x: g.x + w * 0.3, y: bottom - h * 0.3))
            snow.closeSubpath()
            ctx.fill(snow, with: .color(.white.opacity(0.85)))
        }
    }

    static func lamp(_ ctx: GraphicsContext, _ g: CGPoint, h: CGFloat, side: CGFloat) {
        guard h > 4 else { return }
        let head = CGPoint(x: g.x - side * h * 0.24, y: g.y - h * 1.02)
        ctx.fill(ellipse(head.x - h * 0.3, head.y - h * 0.3, h * 0.6, h * 0.6),
                 with: .radialGradient(Gradient(colors: [c(1, 0.86, 0.5).opacity(0.5), c(1, 0.86, 0.5).opacity(0)]),
                                       center: head, startRadius: 0, endRadius: h * 0.3))
        ctx.fill(Path(CGRect(x: g.x - h * 0.016, y: g.y - h, width: h * 0.032, height: h)), with: .color(c(0.42, 0.44, 0.5)))
        var arm = Path()
        arm.move(to: CGPoint(x: g.x, y: g.y - h * 0.98))
        arm.addQuadCurve(to: head, control: CGPoint(x: g.x - side * h * 0.05, y: g.y - h * 1.08))
        ctx.stroke(arm, with: .color(c(0.42, 0.44, 0.5)), lineWidth: max(1, h * 0.022))
        ctx.fill(Path(roundedRect: CGRect(x: head.x - h * 0.06, y: head.y - h * 0.01, width: h * 0.12, height: h * 0.035), cornerRadius: h * 0.01),
                 with: .color(c(1, 0.95, 0.75)))
    }

    // MARK: Cars

    /// Rear views of the traffic: 0 beetle, 1 sedan, 2 van, 3 sports car. `width` matches the
    /// collision width; taller vehicles grow upwards only.
    static func traffic(_ ctx: GraphicsContext, kind: Int, center p: CGPoint, width w: CGFloat, color: Color, night: Bool) {
        guard w > 2 else { return }
        let h = w * 0.72
        let base = p.y + h * 0.5
        let x = p.x
        let glass = c(0.14, 0.18, 0.26)
        let outline = color.shade(0.55)
        let tail = c(1, 0.16, 0.12)
        ctx.fill(ellipse(x - w * 0.54, base - h * 0.12, w * 1.08, h * 0.24), with: .color(.black.opacity(0.3)))
        for sx: CGFloat in [-1, 1] {
            ctx.fill(Path(roundedRect: CGRect(x: x + sx * w * 0.36 - w * 0.09, y: base - h * 0.32, width: w * 0.18, height: h * 0.32),
                          cornerRadius: w * 0.03), with: .color(c(0.08, 0.08, 0.09)))
        }
        let paint = GraphicsContext.Shading.linearGradient(Gradient(colors: [color.lit(0.3), color, color.shade(0.3)]),
                                                           startPoint: CGPoint(x: x, y: base - h), endPoint: CGPoint(x: x, y: base))
        var lights: [CGRect] = []
        switch kind {
        case 0:
            var body = Path()
            body.move(to: CGPoint(x: x - w * 0.47, y: base - h * 0.14))
            body.addCurve(to: CGPoint(x: x + w * 0.47, y: base - h * 0.14),
                          control1: CGPoint(x: x - w * 0.54, y: base - h * 1.2), control2: CGPoint(x: x + w * 0.54, y: base - h * 1.2))
            body.closeSubpath()
            ctx.fill(body, with: paint)
            ctx.stroke(body, with: .color(outline), lineWidth: max(0.6, w * 0.02))
            ctx.fill(ellipse(x - w * 0.17, base - h * 0.84, w * 0.34, h * 0.2), with: .color(glass))
            for k in 0..<3 {
                ctx.fill(Path(CGRect(x: x - w * 0.1, y: base - h * (0.52 - CGFloat(k) * 0.06), width: w * 0.2, height: max(0.5, h * 0.025))),
                         with: .color(outline.opacity(0.7)))
            }
            lights = [CGRect(x: x - w * 0.4, y: base - h * 0.44, width: w * 0.09, height: h * 0.13),
                      CGRect(x: x + w * 0.31, y: base - h * 0.44, width: w * 0.09, height: h * 0.13)]
            ctx.fill(Path(roundedRect: CGRect(x: x - w * 0.46, y: base - h * 0.22, width: w * 0.92, height: h * 0.07), cornerRadius: h * 0.03),
                     with: .color(c(0.8, 0.82, 0.85)))
        case 1:
            var cabin = Path()
            cabin.move(to: CGPoint(x: x - w * 0.42, y: base - h * 0.6))
            cabin.addLine(to: CGPoint(x: x - w * 0.3, y: base - h * 0.98))
            cabin.addLine(to: CGPoint(x: x + w * 0.3, y: base - h * 0.98))
            cabin.addLine(to: CGPoint(x: x + w * 0.42, y: base - h * 0.6))
            cabin.closeSubpath()
            ctx.fill(cabin, with: .color(color.shade(0.12)))
            ctx.stroke(cabin, with: .color(outline), lineWidth: max(0.6, w * 0.02))
            var win = Path()
            win.move(to: CGPoint(x: x - w * 0.35, y: base - h * 0.64))
            win.addLine(to: CGPoint(x: x - w * 0.26, y: base - h * 0.92))
            win.addLine(to: CGPoint(x: x + w * 0.26, y: base - h * 0.92))
            win.addLine(to: CGPoint(x: x + w * 0.35, y: base - h * 0.64))
            win.closeSubpath()
            ctx.fill(win, with: .color(glass))
            let body = Path(roundedRect: CGRect(x: x - w * 0.49, y: base - h * 0.64, width: w * 0.98, height: h * 0.5), cornerRadius: h * 0.08)
            ctx.fill(body, with: paint)
            ctx.stroke(body, with: .color(outline), lineWidth: max(0.6, w * 0.02))
            lights = [CGRect(x: x - w * 0.46, y: base - h * 0.54, width: w * 0.16, height: h * 0.12),
                      CGRect(x: x + w * 0.3, y: base - h * 0.54, width: w * 0.16, height: h * 0.12)]
            ctx.fill(Path(CGRect(x: x - w * 0.1, y: base - h * 0.38, width: w * 0.2, height: h * 0.1)), with: .color(c(0.95, 0.95, 0.9)))
            ctx.fill(Path(roundedRect: CGRect(x: x - w * 0.48, y: base - h * 0.2, width: w * 0.96, height: h * 0.07), cornerRadius: h * 0.03),
                     with: .color(c(0.18, 0.18, 0.2)))
        case 2:
            let box = Path(roundedRect: CGRect(x: x - w * 0.46, y: base - h * 1.38, width: w * 0.92, height: h * 1.24), cornerRadius: w * 0.07)
            ctx.fill(box, with: .linearGradient(Gradient(colors: [color.lit(0.35), color, color.shade(0.3)]),
                                                startPoint: CGPoint(x: x, y: base - h * 1.4), endPoint: CGPoint(x: x, y: base)))
            ctx.stroke(box, with: .color(outline), lineWidth: max(0.6, w * 0.02))
            for sx: CGFloat in [-1, 1] {
                ctx.fill(Path(roundedRect: CGRect(x: x + (sx < 0 ? -w * 0.38 : w * 0.04), y: base - h * 1.24, width: w * 0.34, height: h * 0.3),
                              cornerRadius: w * 0.03), with: .color(glass))
            }
            var split = Path()
            split.move(to: CGPoint(x: x, y: base - h * 1.3)); split.addLine(to: CGPoint(x: x, y: base - h * 0.24))
            ctx.stroke(split, with: .color(outline), lineWidth: max(0.6, w * 0.02))
            lights = [CGRect(x: x - w * 0.45, y: base - h * 0.66, width: w * 0.07, height: h * 0.32),
                      CGRect(x: x + w * 0.38, y: base - h * 0.66, width: w * 0.07, height: h * 0.32)]
            ctx.fill(Path(roundedRect: CGRect(x: x - w * 0.48, y: base - h * 0.2, width: w * 0.96, height: h * 0.07), cornerRadius: h * 0.03),
                     with: .color(c(0.18, 0.18, 0.2)))
        default:
            ctx.fill(ellipse(x - w * 0.26, base - h * 0.92, w * 0.52, h * 0.52), with: .color(color.shade(0.15)))
            ctx.fill(ellipse(x - w * 0.2, base - h * 0.86, w * 0.4, h * 0.34), with: .color(glass))
            let body = Path(roundedRect: CGRect(x: x - w * 0.5, y: base - h * 0.62, width: w, height: h * 0.48), cornerRadius: h * 0.14)
            ctx.fill(body, with: paint)
            ctx.stroke(body, with: .color(outline), lineWidth: max(0.6, w * 0.02))
            ctx.fill(Path(CGRect(x: x - w * 0.47, y: base - h * 0.78, width: w * 0.94, height: h * 0.07)), with: .color(c(0.1, 0.1, 0.12)))
            for sx: CGFloat in [-1, 1] {
                ctx.fill(Path(CGRect(x: x + sx * w * 0.36 - w * 0.02, y: base - h * 0.74, width: w * 0.04, height: h * 0.14)),
                         with: .color(c(0.1, 0.1, 0.12)))
            }
            lights = [CGRect(x: x - w * 0.44, y: base - h * 0.5, width: w * 0.12, height: h * 0.12),
                      CGRect(x: x - w * 0.29, y: base - h * 0.5, width: w * 0.1, height: h * 0.12),
                      CGRect(x: x + w * 0.19, y: base - h * 0.5, width: w * 0.1, height: h * 0.12),
                      CGRect(x: x + w * 0.32, y: base - h * 0.5, width: w * 0.12, height: h * 0.12)]
        }
        for l in lights {
            if night {
                let cp = CGPoint(x: l.midX, y: l.midY)
                ctx.fill(ellipse(cp.x - w * 0.16, cp.y - w * 0.16, w * 0.32, w * 0.32),
                         with: .radialGradient(Gradient(colors: [tail.opacity(0.6), tail.opacity(0)]), center: cp, startRadius: 0, endRadius: w * 0.16))
            }
            ctx.fill(Path(roundedRect: l, cornerRadius: min(l.width, l.height) * 0.3), with: .color(tail))
        }
    }

    /// The player's red convertible from behind — Testarossa-style slatted rear grille, fat tyres,
    /// the driver and a banana riding shotgun. `lean` tilts it into a turn.
    static func playerCar(_ ctx: GraphicsContext, center p: CGPoint, width w: CGFloat, lean: CGFloat, night: Bool) {
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        g.rotate(by: .degrees(Double(lean) * 2.5))
        let h = w * 0.62
        let base = h * 0.46
        let red = c(0.88, 0.06, 0.08)
        g.fill(ellipse(-w * 0.56, base - h * 0.12, w * 1.12, h * 0.28), with: .color(.black.opacity(0.4)))
        for sx: CGFloat in [-1, 1] {
            g.fill(Path(roundedRect: CGRect(x: sx * w * 0.37 - w * 0.11, y: base - h * 0.44, width: w * 0.22, height: h * 0.44),
                        cornerRadius: w * 0.04), with: .color(c(0.06, 0.06, 0.07)))
        }
        // Windscreen, then the two occupants (heads above the rear deck).
        var screen = Path()
        screen.move(to: CGPoint(x: -w * 0.32, y: -h * 0.3))
        screen.addLine(to: CGPoint(x: -w * 0.25, y: -h * 0.62))
        screen.addLine(to: CGPoint(x: w * 0.25, y: -h * 0.62))
        screen.addLine(to: CGPoint(x: w * 0.32, y: -h * 0.3))
        screen.closeSubpath()
        g.fill(screen, with: .color(c(0.7, 0.86, 0.96).opacity(0.35)))
        g.stroke(screen, with: .color(c(0.15, 0.15, 0.18)), lineWidth: max(1, w * 0.018))
        let shift = -lean * w * 0.02
        let dh = CGPoint(x: -w * 0.14 + shift, y: -h * 0.47)
        g.fill(ellipse(dh.x - w * 0.11, dh.y + w * 0.02, w * 0.22, w * 0.14), with: .color(c(0.15, 0.2, 0.4)))
        g.fill(ellipse(dh.x - w * 0.07, dh.y - w * 0.08, w * 0.14, w * 0.15), with: .color(c(0.32, 0.19, 0.1)))
        // The banana passenger.
        var nana = Path()
        let bx = w * 0.15 + shift, by = -h * 0.44
        nana.move(to: CGPoint(x: bx - w * 0.02, y: by - w * 0.15))
        nana.addQuadCurve(to: CGPoint(x: bx - w * 0.01, y: by + w * 0.08), control: CGPoint(x: bx - w * 0.12, y: by - w * 0.03))
        nana.addQuadCurve(to: CGPoint(x: bx - w * 0.02, y: by - w * 0.15), control: CGPoint(x: bx + w * 0.1, y: by - w * 0.03))
        nana.closeSubpath()
        g.fill(nana, with: .linearGradient(Gradient(colors: [c(1, 0.93, 0.45), c(0.98, 0.78, 0.12)]),
                                           startPoint: CGPoint(x: bx - w * 0.1, y: by), endPoint: CGPoint(x: bx + w * 0.1, y: by)))
        g.stroke(nana, with: .color(c(0.45, 0.3, 0.05)), lineWidth: max(0.8, w * 0.012))
        g.fill(Path(CGRect(x: bx - w * 0.03, y: by - w * 0.19, width: w * 0.025, height: w * 0.05)), with: .color(c(0.4, 0.26, 0.1)))
        // Body.
        var body = Path()
        body.move(to: CGPoint(x: -w * 0.5, y: base - h * 0.12))
        body.addLine(to: CGPoint(x: -w * 0.5, y: -h * 0.14))
        body.addQuadCurve(to: CGPoint(x: -w * 0.36, y: -h * 0.32), control: CGPoint(x: -w * 0.5, y: -h * 0.3))
        body.addLine(to: CGPoint(x: w * 0.36, y: -h * 0.32))
        body.addQuadCurve(to: CGPoint(x: w * 0.5, y: -h * 0.14), control: CGPoint(x: w * 0.5, y: -h * 0.3))
        body.addLine(to: CGPoint(x: w * 0.5, y: base - h * 0.12))
        body.closeSubpath()
        g.fill(body, with: .linearGradient(Gradient(colors: [red.lit(0.35), red, red.shade(0.4)]),
                                           startPoint: CGPoint(x: 0, y: -h * 0.32), endPoint: CGPoint(x: 0, y: base)))
        g.stroke(body, with: .color(red.shade(0.6)), lineWidth: max(1, w * 0.015))
        g.fill(Path(CGRect(x: -w * 0.34, y: -h * 0.3, width: w * 0.68, height: max(1, h * 0.03))), with: .color(.white.opacity(0.35)))
        // The slatted rear grille with the tail lights glowing behind it.
        let grille = CGRect(x: -w * 0.44, y: -h * 0.14, width: w * 0.88, height: h * 0.3)
        g.fill(Path(roundedRect: grille, cornerRadius: h * 0.04), with: .color(c(0.07, 0.05, 0.05)))
        for sx: CGFloat in [-1, 1] {
            let l = CGRect(x: sx < 0 ? grille.minX + w * 0.02 : grille.maxX - w * 0.22, y: grille.minY + h * 0.03, width: w * 0.2, height: grille.height - h * 0.06)
            if night {
                let cp = CGPoint(x: l.midX, y: l.midY)
                g.fill(ellipse(cp.x - w * 0.2, cp.y - w * 0.2, w * 0.4, w * 0.4),
                       with: .radialGradient(Gradient(colors: [c(1, 0.2, 0.15).opacity(0.55), c(1, 0.2, 0.15).opacity(0)]),
                                             center: cp, startRadius: 0, endRadius: w * 0.2))
            }
            g.fill(Path(l), with: .color(c(0.95, 0.12, 0.1)))
        }
        for k in 0..<5 {
            let y = grille.minY + (CGFloat(k) + 0.5) * grille.height / 5
            g.fill(Path(CGRect(x: grille.minX, y: y - h * 0.013, width: grille.width, height: h * 0.026)), with: .color(red.shade(0.15)))
        }
        // Plate, bumper and twin exhausts.
        g.fill(Path(CGRect(x: -w * 0.1, y: grille.maxY + h * 0.03, width: w * 0.2, height: h * 0.11)), with: .color(c(0.97, 0.97, 0.92)))
        g.stroke(Path(CGRect(x: -w * 0.1, y: grille.maxY + h * 0.03, width: w * 0.2, height: h * 0.11)), with: .color(c(0.2, 0.2, 0.2)), lineWidth: 0.8)
        for sx: CGFloat in [-1, 1] {
            g.fill(ellipse(sx * w * 0.27 - w * 0.035, base - h * 0.2, w * 0.07, h * 0.08), with: .color(c(0.25, 0.25, 0.27)))
            g.fill(ellipse(sx * w * 0.27 - w * 0.022, base - h * 0.185, w * 0.044, h * 0.05), with: .color(.black))
        }
    }

    // MARK: Sky

    static func cumulus(_ ctx: GraphicsContext, x: CGFloat, y: CGFloat, size: CGFloat) {
        let puffs: [(CGFloat, CGFloat, CGFloat)] = [(-0.62, 0.14, 0.28), (-0.3, -0.04, 0.38), (0.06, -0.2, 0.46),
                                                   (0.42, -0.02, 0.36), (0.72, 0.14, 0.26), (0.02, 0.14, 0.4)]
        var cloud = Path()
        for p in puffs {
            cloud.addEllipse(in: CGRect(x: x + p.0 * size - p.2 * size, y: y + p.1 * size - p.2 * size, width: p.2 * size * 2, height: p.2 * size * 2))
        }
        ctx.fill(cloud, with: .linearGradient(Gradient(stops: [.init(color: .white, location: 0),
                                                               .init(color: .white, location: 0.5),
                                                               .init(color: c(0.8, 0.86, 0.96), location: 1)]),
                                              startPoint: CGPoint(x: x, y: y - size * 0.6),
                                              endPoint: CGPoint(x: x, y: y + size * 0.55)))
    }

    static func stars(_ ctx: GraphicsContext, _ s: CGSize, count: Int) {
        for i in 0..<count {
            let x = hash(i) * s.width, y = hash(i + 500) * s.height * 0.85
            let r = 0.6 + hash(i + 900) * 1.2
            ctx.fill(ellipse(x - r, y - r, r * 2, r * 2), with: .color(.white.opacity(0.4 + 0.5 * Double(hash(i + 1300)))))
        }
    }

    static func sky(_ ctx: GraphicsContext, size s: CGSize, level: Int) {
        let st = stage(level)
        let W = s.width, H = s.height
        ctx.fill(Path(CGRect(origin: .zero, size: s)),
                 with: .linearGradient(Gradient(colors: [st.skyTop, st.skyBottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: H)))
        switch st.scenery {
        case 0:
            cumulus(ctx, x: W * 0.17, y: H * 0.6, size: H * 0.5)
            cumulus(ctx, x: W * 0.52, y: H * 0.52, size: H * 0.68)
            cumulus(ctx, x: W * 0.86, y: H * 0.64, size: H * 0.48)
            var island = Path()
            island.move(to: CGPoint(x: W * 0.62, y: H * 0.92))
            island.addQuadCurve(to: CGPoint(x: W * 0.8, y: H * 0.92), control: CGPoint(x: W * 0.7, y: H * 0.76))
            island.closeSubpath()
            ctx.fill(island, with: .color(c(0.24, 0.46, 0.4)))
            ctx.fill(Path(CGRect(x: 0, y: H * 0.9, width: W, height: H * 0.1)),
                     with: .linearGradient(Gradient(colors: [c(0.12, 0.5, 0.78), c(0.2, 0.66, 0.82)]),
                                           startPoint: CGPoint(x: 0, y: H * 0.9), endPoint: CGPoint(x: 0, y: H)))
            for k in 0..<14 {
                ctx.fill(Path(CGRect(x: hash(k + 40) * W, y: H * (0.92 + 0.07 * hash(k + 80)), width: W * 0.05, height: 1)),
                         with: .color(.white.opacity(0.55)))
            }
        case 1:
            cumulus(ctx, x: W * 0.25, y: H * 0.45, size: H * 0.42)
            cumulus(ctx, x: W * 0.74, y: H * 0.38, size: H * 0.5)
            for (layer, col) in [(0, c(0.38, 0.62, 0.42)), (1, c(0.26, 0.52, 0.3))] {
                var hills = Path()
                hills.move(to: CGPoint(x: 0, y: H))
                var x: CGFloat = 0
                while x <= W {
                    let yy = H * (layer == 0 ? 0.76 : 0.86) - CGFloat(sin(Double(x / W) * (layer == 0 ? 9 : 14) + Double(layer))) * H * 0.07
                    hills.addLine(to: CGPoint(x: x, y: yy))
                    x += W / 60
                }
                hills.addLine(to: CGPoint(x: W, y: H))
                hills.closeSubpath()
                ctx.fill(hills, with: .color(col))
            }
        case 2:
            let sun = CGPoint(x: W * 0.72, y: H * 0.3)
            ctx.fill(ellipse(sun.x - H * 0.3, sun.y - H * 0.3, H * 0.6, H * 0.6),
                     with: .radialGradient(Gradient(colors: [c(1, 0.97, 0.8), c(1, 0.9, 0.6).opacity(0)]), center: sun, startRadius: 0, endRadius: H * 0.3))
            for (x0, wd, ht) in [(0.02, 0.16, 0.3), (0.22, 0.1, 0.44), (0.36, 0.2, 0.24), (0.6, 0.12, 0.36), (0.8, 0.18, 0.28)] as [(CGFloat, CGFloat, CGFloat)] {
                var mesa = Path()
                mesa.move(to: CGPoint(x: W * x0, y: H))
                mesa.addLine(to: CGPoint(x: W * (x0 + 0.02), y: H * (1 - ht)))
                mesa.addLine(to: CGPoint(x: W * (x0 + wd - 0.02), y: H * (1 - ht)))
                mesa.addLine(to: CGPoint(x: W * (x0 + wd), y: H))
                mesa.closeSubpath()
                ctx.fill(mesa, with: .linearGradient(Gradient(colors: [c(0.78, 0.4, 0.24), c(0.6, 0.28, 0.16)]),
                                                     startPoint: CGPoint(x: 0, y: H * (1 - ht)), endPoint: CGPoint(x: 0, y: H)))
                ctx.fill(Path(CGRect(x: W * (x0 + 0.02), y: H * (1 - ht * 0.6), width: W * (wd - 0.04), height: max(1, H * 0.02))),
                         with: .color(c(0.52, 0.24, 0.14).opacity(0.7)))
            }
        case 3:
            let sun = CGPoint(x: W * 0.5, y: H * 0.88)
            let r = H * 0.42
            ctx.fill(ellipse(sun.x - r * 1.8, sun.y - r * 1.8, r * 3.6, r * 3.6),
                     with: .radialGradient(Gradient(colors: [c(1, 0.7, 0.35).opacity(0.5), .clear]), center: sun, startRadius: 0, endRadius: r * 1.8))
            ctx.fill(ellipse(sun.x - r, sun.y - r, r * 2, r * 2),
                     with: .linearGradient(Gradient(colors: [c(1, 0.92, 0.5), c(1, 0.45, 0.2)]),
                                           startPoint: CGPoint(x: 0, y: sun.y - r), endPoint: CGPoint(x: 0, y: sun.y + r)))
            for k in 0..<4 {
                ctx.fill(Path(CGRect(x: W * (0.05 + 0.25 * CGFloat(k)), y: H * (0.2 + 0.12 * hash(k)), width: W * 0.2, height: H * 0.03)),
                         with: .color(c(0.55, 0.25, 0.5).opacity(0.55)))
            }
            ctx.fill(Path(CGRect(x: 0, y: H * 0.9, width: W, height: H * 0.1)), with: .color(c(0.3, 0.16, 0.34)))
            for k in 0..<6 {
                let ww = W * 0.12 * (1 - CGFloat(k) * 0.12)
                ctx.fill(Path(CGRect(x: sun.x - ww / 2, y: H * (0.915 + CGFloat(k) * 0.014), width: ww, height: 1.5)),
                         with: .color(c(1, 0.7, 0.35).opacity(0.8)))
            }
        case 4:
            ctx.fill(ellipse(W * 0.78, H * 0.16, H * 0.14, H * 0.14), with: .color(c(0.98, 0.95, 0.85)))
            for (layer, col) in [(0, c(0.36, 0.3, 0.56)), (1, c(0.24, 0.2, 0.4))] {
                var ridge = Path()
                ridge.move(to: CGPoint(x: 0, y: H))
                var peaks: [CGPoint] = []
                let n = layer == 0 ? 7 : 10
                for k in 0...n {
                    let x = W * CGFloat(k) / CGFloat(n)
                    let yy = H * (layer == 0 ? 0.42 : 0.66) + H * (layer == 0 ? 0.3 : 0.22) * hash(k * 3 + layer * 50)
                    let pnt = CGPoint(x: x, y: k % 2 == 0 ? yy : min(H * 0.97, yy + H * 0.16))
                    ridge.addLine(to: pnt)
                    if k % 2 == 0 { peaks.append(pnt) }
                }
                ridge.addLine(to: CGPoint(x: W, y: H))
                ridge.closeSubpath()
                ctx.fill(ridge, with: .color(col))
                if layer == 0 {
                    for pk in peaks {
                        var cap = Path()
                        cap.move(to: pk)
                        cap.addLine(to: CGPoint(x: pk.x - W * 0.035, y: pk.y + H * 0.08))
                        cap.addLine(to: CGPoint(x: pk.x + W * 0.035, y: pk.y + H * 0.08))
                        cap.closeSubpath()
                        ctx.fill(cap, with: .color(.white.opacity(0.9)))
                    }
                }
            }
        case 5:
            stars(ctx, s, count: 70)
            ctx.fill(ellipse(W * 0.2, H * 0.12, H * 0.16, H * 0.16), with: .color(c(0.96, 0.94, 0.85)))
            var x: CGFloat = 0
            var k = 0
            while x < W {
                let bw = W * (0.035 + 0.04 * hash(k + 7))
                let bh = H * (0.16 + 0.36 * hash(k + 19))
                let rect = CGRect(x: x, y: H - bh, width: bw, height: bh)
                ctx.fill(Path(rect), with: .color(c(0.05, 0.06, 0.15)))
                var wy = rect.minY + 3
                var row = 0
                while wy < H - 3 {
                    var wx = rect.minX + 2
                    var col = 0
                    while wx < rect.maxX - 3 {
                        if hash(k * 131 + row * 17 + col) > 0.55 {
                            ctx.fill(Path(CGRect(x: wx, y: wy, width: 2, height: 2)), with: .color(c(1, 0.85, 0.4).opacity(0.85)))
                        }
                        wx += 5; col += 1
                    }
                    wy += 6; row += 1
                }
                x += bw + 1
                k += 1
            }
        default:
            stars(ctx, s, count: 50)
            let sun = CGPoint(x: W * 0.5, y: H * 0.9)
            let r = H * 0.5
            var sg = ctx
            sg.clip(to: ellipse(sun.x - r, sun.y - r, r * 2, r * 2))
            sg.fill(Path(CGRect(x: sun.x - r, y: sun.y - r, width: r * 2, height: r * 2)),
                    with: .linearGradient(Gradient(colors: [c(1, 0.92, 0.3), c(1, 0.45, 0.4), c(1, 0.15, 0.6)]),
                                          startPoint: CGPoint(x: 0, y: sun.y - r), endPoint: CGPoint(x: 0, y: sun.y + r * 0.4)))
            for k in 0..<6 {
                let yy = sun.y - r * 0.1 + CGFloat(k) * r * 0.12
                sg.fill(Path(CGRect(x: sun.x - r, y: yy, width: r * 2, height: r * (0.02 + 0.012 * CGFloat(k)))), with: .color(st.skyBottom))
            }
            var ridge = Path()
            ridge.move(to: CGPoint(x: 0, y: H))
            for k in 0...12 {
                let xx = W * CGFloat(k) / 12
                let far = abs(xx - sun.x) / W
                ridge.addLine(to: CGPoint(x: xx, y: H - H * (k % 2 == 0 ? 0.1 : 0.2 + 0.4 * far) * (0.6 + 0.4 * hash(k + 3))))
            }
            ridge.addLine(to: CGPoint(x: W, y: H))
            ridge.closeSubpath()
            ctx.fill(ridge, with: .color(c(0.08, 0.0, 0.16)))
            ctx.stroke(ridge, with: .color(c(1, 0.25, 0.8)), lineWidth: 1.5)
        }
    }
}

/// The sky and horizon scenery for a stage. Equatable: it only redraws for a new level or size;
/// the parallax drift is a cheap offset applied by the parent.
private struct OutRunSky: View, Equatable {
    let level: Int
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Canvas { ctx, s in OutRunArt.sky(ctx, size: s, level: level) }
            .allowsHitTesting(false)
    }
}
