//
//  RockNRocketGame.swift
//  A Banana Game
//
//  Reflex — a top-down combat racer in the Rock n' Roll Racing tradition. Three cars
//  tear around a closed, curvy circuit for THREE LAPS. Hold GAS and steer ◄ ► through the
//  corners; the track edges keep you on the tarmac. Each car packs a handful of ROCKETS:
//  land one on a rival and they spin out for a second. Finish the three laps in FRONT to
//  win; come last or run out the clock and you drop back to level 1.
//
//  7 levels ramp the circuit tightness, the AI's pace and how few rockets you carry (while
//  the rivals carry more), through a desert → forest → night → volcano mood ramp. All
//  controls are fixed on-screen buttons, so it stays tap-safe (no feed lock).
//
//  Drawn as a top-down combat racer on Rock n' Roll Racing-style worlds: desert with cacti,
//  grassland, forest, an ice planet, a night city under street lamps, then volcanic and lava plains
//  (scenery kept off the tarmac). Red-and-white kerbs, textured asphalt exactly as wide as the
//  physics allows, white edge lines, a chequered start/finish, vector race cars (the banana-yellow
//  player's car has a black stripe) and missiles with flames. The HUD is a flag + lap count, a
//  place medal and missile pips; the keys carry arrows, a missile and a pedal instead of words.
//  The circuit is an Equatable view drawn once; cars and rockets share one Canvas.
//

import SwiftUI

enum RockNRocketGame {
    static let definition = GameDefinition(
        id: "rock-n-rocket",
        title: "Rock 'n' Rocket",
        emoji: "🍌",
        genre: .reflex,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "A top-down combat race: three laps around a closed circuit against two AI cars.",
                "Hold GAS and steer with ◄ ► through the corners.",
                "Tap FIRE to launch a rocket; land one on a rival and they spin out briefly.",
                "Finish the three laps in front to win; come last or time out and you're back to level 1.",
            ],
            bulletsVI: [
                "Đua chiến đấu nhìn từ trên: ba vòng quanh đường đua kín đấu với hai xe AI.",
                "Giữ GA và lái bằng ◄ ► qua các khúc cua.",
                "Chạm BẮN để phóng tên lửa; trúng một đối thủ khiến chúng xoay lộn một lúc.",
                "Về đích ba vòng ở phía trước để thắng; về chót hoặc hết giờ sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(RockNRocketView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct RockNRocketView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void
    @Environment(\.isDemo) private var isDemo

    // MARK: - Difficulty
    private let laps = 3
    private var aiFactor: Double     { [0.72, 0.79, 0.86, 0.93, 0.99, 1.04, 1.09][min(level, 7) - 1] }
    private var halfWidth: Double    { [0.062, 0.058, 0.054, 0.050, 0.046, 0.042, 0.038][min(level, 7) - 1] }
    private var playerRockets: Int   { [3, 3, 3, 2, 2, 1, 1][min(level, 7) - 1] }
    private var aiRockets: Int       { [1, 2, 3, 3, 4, 5, 6][min(level, 7) - 1] }
    private var aiFireEvery: Double  { [4.5, 4.0, 3.4, 2.9, 2.4, 2.0, 1.6][min(level, 7) - 1] }
    private var trackShape: Int      { min(level, 7) - 1 }
    /// Generous clock — the circuit is long and winding, so 3 laps take a while.
    private var timeLimit: Double    { 80 }

    // Feel constants
    private let maxSpeed = 0.30       // frac/sec
    private let accelRate = 0.55
    private let coastDrag = 0.22
    private let turnRate = 2.7        // rad/sec at speed
    private let rocketSpeed = 0.62
    private let carRadius = 0.017     // half-size in min-dimension fractions (used for car-car bumps)
    private let N = 128               // centerline resolution (higher = smoother, longer, curvier)

    // MARK: - Model
    private struct Car: Identifiable {
        let id: Int
        var pos: CGPoint
        var heading: Double
        var speed: Double = 0
        var lap = 0
        var idx = 0
        var lastIdx = 0
        var reachedHalf = false
        var spin: Double = 0          // spin-out timer (no control while > 0)
        var rockets: Int
        var fireCD: Double = 0
        var bump: CGVector = .zero    // transient shove velocity from a car-car collision (decays)
        let color: Color
        var isPlayer: Bool
    }
    private struct Rocket: Identifiable {
        let id = UUID()
        var pos: CGPoint
        var heading: Double
        var vel: CGVector
        var owner: Int
        var life: Double
        var trailCD: Double = 0
    }
    private struct Burst: Identifiable { let id = UUID(); let pos: CGPoint; let color: Color; let big: Bool }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var center: [CGPoint] = []
    @State private var cars: [Car] = []
    @State private var rockets: [Rocket] = []
    @State private var bursts: [Burst] = []

    @State private var steer = 0.0
    @State private var gas = false
    @State private var area: CGSize = .zero
    @State private var timeLeft = 0.0
    @State private var animT = 0.0
    @State private var shakeTick = 0
    @State private var built = false
    @State private var demoFire = 0            // demo: frames left on the FIRE press flash

    private var player: Car? { cars.first { $0.isPlayer } }

    // MARK: - Body
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                // The circuit and its scenery never change during a race: drawn once.
                RKTrack(size: geo.size, center: center, halfWidth: halfWidth, level: level).equatable()

                // Rockets and cars: one Canvas.
                Canvas { ctx, _ in drawRace(ctx, w: w, h: h) }
                    .allowsHitTesting(false)

                ForEach(bursts) { b in
                    ParticleBurstView(color: b.color, count: b.big ? 18 : 9,
                                      spread: b.big ? 80 : 40, gravity: 10) {
                        bursts.removeAll { $0.id == b.id }
                    }
                    .position(x: b.pos.x * w, y: b.pos.y * h)
                }

                hud(w: w, h: h)
                controls
            }
            .frame(width: w, height: h)
            .clipped()
            .screenShake(shakeTick, amount: 6)
            .onAppear { area = geo.size }
            .onChange(of: geo.size) { _, newValue in area = newValue }
        }
        // Rounded like the other cards but full width: the physics clamps and bumps in points, so the
        // play area keeps its old size.
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { isDemo ? await runDemo() : await run() }
    }

    private func drawRace(_ ctx: GraphicsContext, w: CGFloat, h: CGFloat) {
        let flick = Int(animT * 22) % 2 == 0
        for r in rockets {
            RKArt.rocket(ctx, at: CGPoint(x: r.pos.x * w, y: r.pos.y * h), heading: r.heading, length: h * 0.042, flick: flick)
        }
        for c in cars {
            let blink = c.spin > 0 && Int(c.spin * 16) % 2 == 0
            RKArt.car(ctx, at: CGPoint(x: c.pos.x * w, y: c.pos.y * h), heading: c.heading, length: h * 0.036,
                      color: c.color, player: c.isPlayer, dim: blink, spinning: c.spin > 0)
        }
    }

    // MARK: - HUD
    private func hud(w: CGFloat, h: CGFloat) -> some View {
        VStack(spacing: 4) {
            HStack {
                // Lap: a chequered flag and the count.
                HStack(spacing: 5) {
                    RKFlagIcon().frame(width: isDemo ? 14 : 17, height: isDemo ? 14 : 17)
                    Text("\(min(laps, (player?.lap ?? 0) + 1))/\(laps)")
                        .font(.system(size: isDemo ? 13 : 16, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                Spacer()
                // Place: 1, 2 or 3 on a gold, silver or bronze medal.
                RKMedal(place: place).frame(width: isDemo ? 22 : 28, height: isDemo ? 22 : 28)
                Spacer()
                // Rockets left.
                HStack(spacing: 3) {
                    ForEach(0..<max(1, playerRockets), id: \.self) { i in
                        RKRocketIcon(lit: i < (player?.rockets ?? 0))
                            .frame(width: isDemo ? 7 : 8, height: isDemo ? 14 : 17)
                    }
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 4)
            .background(.black.opacity(0.35), in: Capsule())
            .padding(.horizontal, 8).padding(.top, 4)

            if !isDemo {
                GeometryReader { g in
                    let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(.black.opacity(0.35))
                        Capsule().fill(frac < 0.25 ? Color(red: 1, green: 0.3, blue: 0.25) : .white)
                            .frame(width: g.size.width * max(0, frac))
                    }
                }
                .frame(height: 4).padding(.horizontal, 50)
            }
            Spacer()
        }
    }

    /// 1st / 2nd / 3rd, counted the same way the old "1st" text was.
    private var place: Int {
        guard let p = player else { return 1 }
        let ahead = cars.filter { !$0.isPlayer &&
            ($0.lap > p.lap || ($0.lap == p.lap && $0.idx > p.idx)) }.count
        return min(3, ahead + 1)
    }

    // MARK: - Controls
    private func holdButton(_ key: RKKey.Face, color: Color, active: Bool = false,
                            onPress: @escaping (Bool) -> Void) -> some View {
        // In the demo the held control lights up (the autopilot drives steer/gas directly).
        let lit = isDemo && active
        return RKKey(face: key, color: color, lit: lit)
            .frame(width: isDemo ? 50 : 62, height: isDemo ? 40 : 54)
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .scaleEffect(lit ? 0.9 : 1)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in onPress(true) }
                .onEnded { _ in onPress(false) })
    }

    private var controls: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                HStack(spacing: isDemo ? 8 : 10) {
                    holdButton(.left, color: Color(white: 0.24), active: steer < 0) { d in if phase == .play { steer = d ? -1 : (steer < 0 ? 0 : steer) } }
                    holdButton(.right, color: Color(white: 0.24), active: steer > 0) { d in if phase == .play { steer = d ? 1 : (steer > 0 ? 0 : steer) } }
                }
                Spacer()
                HStack(spacing: isDemo ? 8 : 10) {
                    RKKey(face: .fire, color: Color(red: 0.9, green: 0.24, blue: 0.24), lit: demoFire > 0)
                        .frame(width: isDemo ? 50 : 62, height: isDemo ? 40 : 54)
                        .scaleEffect(demoFire > 0 ? 0.9 : 1)
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                        .onTapGesture { firePlayerRocket() }
                    holdButton(.gas, color: Color(red: 0.2, green: 0.62, blue: 0.3), active: gas) { d in if phase == .play { gas = d } }
                }
            }
            .padding(.horizontal, isDemo ? 12 : 20).padding(.bottom, isDemo ? 6 : 10)
        }
    }

    // MARK: - Flow
    private func run() async {
        if !built { setup(); built = true }
        var last = Date()
        while !Task.isCancelled && phase == .play {
            try? await Task.sleep(for: .seconds(0.016))
            let now = Date()
            let dt = min(0.05, now.timeIntervalSince(last)); last = now
            step(dt: dt)
        }
    }

    private func setup() {
        // Generate a closed, LONG, curvy centreline — a low harmonic sets the big shape and a
        // higher one adds extra bends, so each lap winds through many corners (per-level shape).
        // Bigger amplitudes + extra harmonics than before → a much longer, twistier lap. The
        // radius stays positive (sum of amplitudes < 1), so the star-shaped loop never self-crosses.
        let phases: [(k1: Double, k2: Double, a1: Double, a2: Double, k3: Double, a3: Double, p: Double)] = [
            (3, 4, 0.20, 0.17, 6, 0.10, 0.0), (4, 3, 0.24, 0.19, 7, 0.11, 0.6),
            (4, 5, 0.25, 0.21, 7, 0.12, 1.1), (5, 4, 0.27, 0.22, 8, 0.13, 0.3),
            (5, 6, 0.28, 0.24, 9, 0.13, 1.8), (6, 5, 0.30, 0.25, 9, 0.14, 0.9),
            (6, 7, 0.31, 0.27, 10, 0.15, 2.2)
        ]
        let s = phases[min(trackShape, phases.count - 1)]
        // Slightly tighter base radii than before so the bigger curve amplitudes still keep the
        // whole loop comfortably on-screen.
        let cx = 0.5, cy = 0.50, rx = 0.33, ry = 0.28
        var pts: [CGPoint] = []
        for i in 0..<N {
            let t = Double(i) / Double(N) * 2 * .pi
            let radx = rx * (1 + s.a1 * sin(s.k1 * t + s.p) + s.a3 * sin(s.k3 * t + s.p))
            let rady = ry * (1 + s.a2 * sin(s.k2 * t + s.p * 0.5) + s.a3 * sin(s.k3 * t + 1.7))
            pts.append(CGPoint(x: cx + radx * cos(t), y: cy + rady * sin(t)))
        }
        center = pts

        // Grid-start the three cars just behind the line, STAGGERED two nodes apart (and on
        // alternating sides) so the smaller, now-collidable cars never spawn overlapping.
        let startI = N - 4
        let colors: [Color] = [BananaTheme.banana,
                               Color(red: 0.9, green: 0.25, blue: 0.28),
                               Color(red: 0.30, green: 0.55, blue: 0.95)]
        var newCars: [Car] = []
        for k in 0..<3 {
            let si = ((startI - k * 2) % N + N) % N
            let pa = pts[si], pb = pts[(si + 1) % N]
            let dir = CGVector(dx: pb.x - pa.x, dy: pb.y - pa.y)
            let dl = max(0.0001, hypot(dir.dx, dir.dy))
            let heading = atan2(dir.dy, dir.dx)
            let nrm = CGVector(dx: -dir.dy / dl, dy: dir.dx / dl)
            let lat = (k % 2 == 0 ? 1.0 : -1.0) * halfWidth * 0.45
            let pos = CGPoint(x: pa.x + nrm.dx * lat, y: pa.y + nrm.dy * lat)
            newCars.append(Car(id: k, pos: pos, heading: heading, lap: 0, idx: si, lastIdx: si,
                               rockets: k == 0 ? playerRockets : aiRockets,
                               fireCD: aiFireEvery, color: colors[k], isPlayer: k == 0))
        }
        cars = newCars
        rockets = []; bursts = []
        steer = 0; gas = false
        timeLeft = timeLimit; animT = 0; phase = .play
    }

    // MARK: - Demo (live manual clip)
    // The closing stretch of level 1: the final lap (LAP 3/3), the banana car on the lower-left
    // bend with the red rival 14 nodes up the road and blue trailing — then the top-right run to
    // the flag, clear of the control bar. Stepped at a fixed 1/60s through the real `step`; the
    // autopilot holds GAS, steers ◄ ► toward a point 7 nodes up the centreline (each press held
    // ≥5 frames so it reads), and fires once red is within 0.15 and dead ahead (≤0.1 rad). The
    // rocket spins red out, the banana car sails past and takes the flag first. The AIs are
    // "reloading" (no rockets in the clip), so nothing random can happen. Checked offline on a
    // port of the physics at 16 card sizes (300–390 × 300–360pt): fire ≈1.3s, red hit, win ≈4.6s.
    private func demoCar(_ k: Int, idx: Int, lat: Double, speed: Double) -> Car {
        let colors: [Color] = [BananaTheme.banana,
                               Color(red: 0.9, green: 0.25, blue: 0.28),
                               Color(red: 0.30, green: 0.55, blue: 0.95)]
        let si = ((idx % N) + N) % N
        let pa = center[si], pb = center[(si + 1) % N]
        let dir = CGVector(dx: pb.x - pa.x, dy: pb.y - pa.y)
        let dl = max(0.0001, hypot(dir.dx, dir.dy))
        let nrm = CGVector(dx: -dir.dy / dl, dy: dir.dx / dl)
        var car = Car(id: k, pos: CGPoint(x: pa.x + nrm.dx * lat, y: pa.y + nrm.dy * lat),
                      heading: atan2(dir.dy, dir.dx), speed: speed, lap: laps - 1, idx: si, lastIdx: si,
                      rockets: k == 0 ? playerRockets : 0, fireCD: 99, color: colors[k], isPlayer: k == 0)
        car.reachedHalf = true
        return car
    }

    private func runDemo() async {
        let dt = 1.0 / 60.0
        while !Task.isCancelled {
            setup()                                         // builds the real L1 circuit
            cars = [demoCar(0, idx: 44, lat: 0, speed: 0.22),
                    demoCar(1, idx: 58, lat: -halfWidth * 0.35, speed: maxSpeed * aiFactor),
                    demoCar(2, idx: 36, lat: halfWidth * 0.45, speed: maxSpeed * aiFactor)]
            gas = true; steer = 0; demoFire = 0
            try? await Task.sleep(for: .seconds(0.5))       // (also lets `area` settle)
            var frame = 0, lastSteer = -99, fired = false
            while !Task.isCancelled && phase == .play && frame < 900 {
                frame += 1
                if let p = cars.first(where: { $0.isPlayer }) {
                    let tgt = center[(p.idx + 7) % N]
                    let d = angleDiff(atan2(tgt.y - p.pos.y, tgt.x - p.pos.x), p.heading)
                    let want: Double = d > 0.10 ? 1 : (d < -0.10 ? -1 : 0)
                    if want != steer && frame - lastSteer >= 5 { steer = want; lastSteer = frame }
                    if !fired, let red = cars.first(where: { $0.id == 1 }), red.spin <= 0 {
                        let dx = red.pos.x - p.pos.x, dy = red.pos.y - p.pos.y
                        if hypot(dx, dy) < 0.15 && abs(angleDiff(atan2(dy, dx), p.heading)) < 0.10 {
                            firePlayerRocket(); fired = true; demoFire = 8
                        }
                    }
                }
                if demoFire > 0 { demoFire -= 1 }
                step(dt: dt)
                try? await Task.sleep(for: .seconds(0.016))
            }
            // Flag taken in 1st → the real win() ran (onWin is a no-op). Hold, then loop.
            steer = 0; gas = false; demoFire = 0
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    private func step(dt: Double) {
        guard phase == .play, center.count == N else { return }
        animT += dt

        for i in cars.indices {
            updateCar(&cars[i], dt: dt)
        }
        resolveCarCollisions()
        updateRockets(dt: dt)

        // AI rocket fire.
        for i in cars.indices where !cars[i].isPlayer {
            cars[i].fireCD -= dt
            if cars[i].fireCD <= 0 && cars[i].rockets > 0 && cars[i].spin <= 0 {
                cars[i].fireCD = aiFireEvery * Double.random(in: 0.8...1.3)
                if let target = aiTarget(for: cars[i]) {
                    fireRocket(from: i, aimingAt: target)
                }
            }
        }

        timeLeft -= dt
        if timeLeft <= 0 { timeLeft = 0; fail() }
    }

    private func updateCar(_ c: inout Car, dt: Double) {
        if c.spin > 0 {
            c.spin -= dt
            c.heading += 11 * dt
            c.speed = max(0, c.speed - 0.9 * dt)
            advance(&c, dt: dt)
            return
        }

        let steerInput: Double = c.isPlayer ? steer : aiSteer(for: c)
        // Turn scales a little with speed so a stopped car doesn't pivot in place.
        let turnScale = min(1.0, 0.25 + c.speed / (maxSpeed * 0.6))
        c.heading += steerInput * turnRate * dt * turnScale

        let vmax = c.isPlayer ? maxSpeed : maxSpeed * aiFactor
        let accelerating = c.isPlayer ? gas : true
        if accelerating { c.speed += accelRate * dt } else { c.speed -= coastDrag * dt }
        c.speed = min(vmax, max(0, c.speed))

        advance(&c, dt: dt)
    }

    private func advance(_ c: inout Car, dt: Double) {
        // Motion = drive along the heading + any transient shove from a car-car bump (which decays).
        var np = CGPoint(x: c.pos.x + (cos(c.heading) * c.speed + Double(c.bump.dx)) * dt,
                         y: c.pos.y + (sin(c.heading) * c.speed + Double(c.bump.dy)) * dt)
        let decay = CGFloat(min(1, 7 * dt))
        c.bump.dx -= c.bump.dx * decay
        c.bump.dy -= c.bump.dy * decay
        // Keep the WHOLE car inside the tarmac: clamp its offset from the centreline to the
        // track band (measured in points via the play-area aspect, matching the drawn width),
        // and only scrub a little speed so it can never get stuck against an edge — it always
        // keeps running. This replaces the old wall-bounce that could kill the car's speed.
        if area.width > 1, area.height > 1, center.count == N {
            let c0 = center[nearestIndex(np)]
            let minDim = min(area.width, area.height)
            let dxp = (np.x - c0.x) * area.width
            let dyp = (np.y - c0.y) * area.height
            let distp = hypot(dxp, dyp)
            let maxp = CGFloat(halfWidth) * minDim * 0.82
            if distp > maxp && distp > 0.0001 {
                let k = maxp / distp
                np.x = c0.x + (np.x - c0.x) * k
                np.y = c0.y + (np.y - c0.y) * k
                c.speed = max(c.speed * 0.9, maxSpeed * 0.35)
            }
        }
        c.pos = np

        // Lap tracking via centreline index crossings.
        let idx = nearestIndex(c.pos)
        if idx > N / 2 { c.reachedHalf = true }
        if c.reachedHalf && c.lastIdx > (N * 3 / 4) && idx < (N / 4) {
            c.lap += 1
            c.reachedHalf = false
            if c.isPlayer { Haptics.tap(); SoundManager.shared.tap() }
            if c.lap >= laps { finishRace(winnerIsPlayer: c.isPlayer) }
        }
        c.lastIdx = idx
        c.idx = idx
    }

    /// Keep cars from overlapping and let them physically shove one another. Works in point
    /// space (via `area`) so the round bodies separate correctly on a non-square screen, then
    /// converts the push back into 0…1 fractions and adds an outward impulse to each car's
    /// `bump` velocity — a side-swipe knocks rivals off their racing line.
    private func resolveCarCollisions() {
        guard area.width > 1, area.height > 1, cars.count > 1 else { return }
        let minPx = CGFloat(carRadius) * 2 * min(area.width, area.height)
        for i in 0..<cars.count {
            for j in (i + 1)..<cars.count {
                let dxp = (cars[j].pos.x - cars[i].pos.x) * area.width
                let dyp = (cars[j].pos.y - cars[i].pos.y) * area.height
                let distp = hypot(dxp, dyp)
                guard distp < minPx, distp > 0.0001 else { continue }
                // Feedback only on the first frame of contact so it doesn't machine-gun while
                // two cars grind alongside each other.
                let freshHit = hypot(cars[i].bump.dx, cars[i].bump.dy) < 0.02
                    && hypot(cars[j].bump.dx, cars[j].bump.dy) < 0.02

                let nxp = dxp / distp, nyp = dyp / distp
                let overlap = minPx - distp
                // Separate the pair (half each), converting the push back into screen fractions.
                let sx = nxp * overlap * 0.5, sy = nyp * overlap * 0.5
                cars[i].pos.x -= sx / area.width;  cars[i].pos.y -= sy / area.height
                cars[j].pos.x += sx / area.width;  cars[j].pos.y += sy / area.height
                // Outward shove, scaled by how fast they were closing, along the fractional normal.
                let nfx = cars[j].pos.x - cars[i].pos.x
                let nfy = cars[j].pos.y - cars[i].pos.y
                let nl = max(0.0001, hypot(nfx, nfy))
                let ux = CGFloat(nfx / nl), uy = CGFloat(nfy / nl)
                let kick = CGFloat(0.10 + 0.35 * (cars[i].speed + cars[j].speed))
                cars[i].bump.dx -= ux * kick; cars[i].bump.dy -= uy * kick
                cars[j].bump.dx += ux * kick; cars[j].bump.dy += uy * kick
                cars[i].speed *= 0.9; cars[j].speed *= 0.9
                if freshHit {
                    shakeTick += 1
                    if cars[i].isPlayer || cars[j].isPlayer { Haptics.tap(); SoundManager.shared.tap() }
                }
            }
        }
    }

    private func updateRockets(dt: Double) {
        var survivors: [Rocket] = []
        for var r in rockets {
            r.pos.x += Double(r.vel.dx) * dt
            r.pos.y += Double(r.vel.dy) * dt
            r.life -= dt
            r.trailCD -= dt
            if r.trailCD <= 0 {
                r.trailCD = 0.06
                bursts.append(Burst(pos: r.pos, color: Color(white: 0.7), big: false))
            }
            if r.life <= 0 || r.pos.x < 0 || r.pos.x > 1 || r.pos.y < 0 || r.pos.y > 1 { continue }
            // Hit any car that isn't the owner.
            if let hi = cars.firstIndex(where: { $0.id != r.owner && $0.spin <= 0 &&
                hypot($0.pos.x - r.pos.x, $0.pos.y - r.pos.y) < 0.024 }) {
                cars[hi].spin = 1.0
                cars[hi].speed *= 0.3
                bursts.append(Burst(pos: r.pos, color: Color(red: 1, green: 0.5, blue: 0.2), big: true))
                shakeTick += 1
                Haptics.warning(); SoundManager.shared.error()
                continue
            }
            survivors.append(r)
        }
        rockets = survivors
    }

    private func firePlayerRocket() {
        guard phase == .play, let pi = cars.firstIndex(where: { $0.isPlayer }),
              cars[pi].rockets > 0, cars[pi].spin <= 0 else { return }
        cars[pi].rockets -= 1
        spawnRocket(from: pi, heading: cars[pi].heading)
        SoundManager.shared.tap(); Haptics.tap()
    }

    private func fireRocket(from i: Int, aimingAt target: Car) {
        cars[i].rockets -= 1
        let aim = atan2(target.pos.y - cars[i].pos.y, target.pos.x - cars[i].pos.x)
        spawnRocket(from: i, heading: aim)
    }

    private func spawnRocket(from i: Int, heading: Double) {
        let c = cars[i]
        // Spawn the rocket CLEAR of the firer's own body: the collision radius is 0.024 and the
        // car half-size ~0.017, so launch from well past both (0.05) along the firing direction.
        // Combined with the owner-ignore in `updateRockets`, a rocket can never detonate on — or
        // spin out — the car that fired it.
        let muzzle = 0.05
        let nose = CGPoint(x: c.pos.x + cos(heading) * muzzle, y: c.pos.y + sin(heading) * muzzle)
        rockets.append(Rocket(pos: nose, heading: heading,
                              vel: CGVector(dx: cos(heading) * rocketSpeed, dy: sin(heading) * rocketSpeed),
                              owner: c.id, life: 1.6))
    }

    /// An AI picks the nearest rival within a forward-ish cone to lob a rocket at.
    private func aiTarget(for c: Car) -> Car? {
        var best: Car?
        var bestD = 0.4
        for o in cars where o.id != c.id {
            let d = hypot(o.pos.x - c.pos.x, o.pos.y - c.pos.y)
            if d < bestD { bestD = d; best = o }
        }
        return best
    }

    private func finishRace(winnerIsPlayer: Bool) {
        if winnerIsPlayer { win() } else { fail() }
    }

    private func win() {
        guard phase == .play else { return }
        phase = .done
        Haptics.success(); SoundManager.shared.tap()
        onWin()
    }

    private func fail() {
        guard phase == .play else { return }
        phase = .done
        Haptics.warning(); SoundManager.shared.error()
        onFail()
    }

    // MARK: - AI steering + geometry
    private func aiSteer(for c: Car) -> Double {
        // Aim a few nodes ahead along the racing line (scaled to the node density).
        let look = (c.idx + max(4, N / 18)) % N
        let target = center[look]
        let desired = atan2(target.y - c.pos.y, target.x - c.pos.x)
        let d = angleDiff(desired, c.heading)
        return max(-1, min(1, d * 2.5))
    }

    private func angleDiff(_ a: Double, _ b: Double) -> Double {
        var d = a - b
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }

    private func nearestIndex(_ p: CGPoint) -> Int {
        var best = 0
        var bestD = Double.greatestFiniteMagnitude
        for i in 0..<N {
            let dx = center[i].x - p.x, dy = center[i].y - p.y
            let d = dx * dx + dy * dy
            if d < bestD { bestD = d; best = i }
        }
        return best
    }

}

// MARK: - Combat-racer art (after Rock n' Roll Racing's planets, seen from above)

private enum RKArt {
    static func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    static func hash(_ n: Double) -> Double {
        let x = sin(n) * 43758.5453
        return x - floor(x)
    }

    /// Ground colours per world: desert, grassland, forest, ice planet, night city, volcanic, inferno.
    static func ground(_ level: Int) -> (Color, Color) {
        switch min(max(level, 1), 7) {
        case 1: return (c(0.88, 0.76, 0.52), c(0.76, 0.62, 0.40))
        case 2: return (c(0.44, 0.68, 0.32), c(0.32, 0.54, 0.24))
        case 3: return (c(0.26, 0.5, 0.28), c(0.15, 0.35, 0.19))
        case 4: return (c(0.88, 0.92, 0.97), c(0.7, 0.78, 0.9))
        case 5: return (c(0.12, 0.14, 0.26), c(0.06, 0.07, 0.16))
        case 6: return (c(0.27, 0.13, 0.12), c(0.14, 0.06, 0.07))
        default: return (c(0.33, 0.1, 0.06), c(0.16, 0.04, 0.03))
        }
    }

    /// One piece of scenery for the world (drawn off the track only).
    static func prop(_ ctx: GraphicsContext, at p: CGPoint, size s: CGFloat, level: Int, seed: Double) {
        let shadow = Path(ellipseIn: CGRect(x: p.x - s * 0.4, y: p.y + s * 0.2, width: s * 0.9, height: s * 0.3))
        switch min(max(level, 1), 7) {
        case 1:
            if seed < 0.55 {
                // Saguaro seen from above-front.
                ctx.fill(shadow, with: .color(.black.opacity(0.18)))
                var cactus = Path()
                cactus.addRoundedRect(in: CGRect(x: p.x - s * 0.1, y: p.y - s * 0.45, width: s * 0.2, height: s * 0.75), cornerSize: CGSize(width: s * 0.1, height: s * 0.1))
                cactus.addRoundedRect(in: CGRect(x: p.x - s * 0.36, y: p.y - s * 0.2, width: s * 0.14, height: s * 0.3), cornerSize: CGSize(width: s * 0.07, height: s * 0.07))
                cactus.addRoundedRect(in: CGRect(x: p.x + s * 0.22, y: p.y - s * 0.3, width: s * 0.14, height: s * 0.3), cornerSize: CGSize(width: s * 0.07, height: s * 0.07))
                cactus.addRect(CGRect(x: p.x - s * 0.3, y: p.y - s * 0.02, width: s * 0.25, height: s * 0.1))
                cactus.addRect(CGRect(x: p.x + s * 0.05, y: p.y - s * 0.08, width: s * 0.25, height: s * 0.1))
                ctx.fill(cactus, with: .color(c(0.3, 0.55, 0.26)))
            } else {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.32, y: p.y - s * 0.18, width: s * 0.64, height: s * 0.42)), with: .color(c(0.62, 0.48, 0.32)))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.22, y: p.y - s * 0.16, width: s * 0.3, height: s * 0.18)), with: .color(c(0.78, 0.66, 0.5)))
            }
        case 2, 3:
            ctx.fill(shadow, with: .color(.black.opacity(0.2)))
            let r = s * (level == 3 ? 0.42 : 0.3)
            let crown = level == 3 ? c(0.13, 0.36, 0.17) : c(0.28, 0.56, 0.22)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(crown))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.6, y: p.y - r * 0.7, width: r * 0.9, height: r * 0.8)), with: .color(crown.mix(with: .white, by: 0.18)))
            if level == 2 && seed > 0.7 {
                for k in 0..<3 {
                    let q = CGPoint(x: p.x + CGFloat(k - 1) * s * 0.3, y: p.y + s * 0.45)
                    ctx.fill(Path(ellipseIn: CGRect(x: q.x - s * 0.05, y: q.y - s * 0.05, width: s * 0.1, height: s * 0.1)), with: .color(k == 1 ? c(1, 0.85, 0.3) : .white))
                }
            }
        case 4:
            // Snowy pine: a white-capped star seen from above.
            ctx.fill(shadow, with: .color(c(0.3, 0.4, 0.6).opacity(0.25)))
            var star = Path()
            for k in 0..<10 {
                let a = Double(k) / 10 * 2 * .pi
                let rr = s * (k % 2 == 0 ? 0.42 : 0.2)
                let q = CGPoint(x: p.x + CGFloat(cos(a)) * rr, y: p.y + CGFloat(sin(a)) * rr)
                if k == 0 { star.move(to: q) } else { star.addLine(to: q) }
            }
            star.closeSubpath()
            ctx.fill(star, with: .color(c(0.2, 0.42, 0.36)))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.14, y: p.y - s * 0.14, width: s * 0.28, height: s * 0.28)), with: .color(.white))
        case 5:
            // Street lamp pooling light on the ground.
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.7, y: p.y - s * 0.7, width: s * 1.4, height: s * 1.4)),
                     with: .radialGradient(Gradient(colors: [c(1, 0.85, 0.5).opacity(0.35), c(1, 0.85, 0.5).opacity(0)]), center: p, startRadius: 0, endRadius: s * 0.7))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.08, y: p.y - s * 0.08, width: s * 0.16, height: s * 0.16)), with: .color(c(1, 0.92, 0.7)))
        default:
            if seed < 0.5 {
                // A lava pool with a bright core.
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.42, y: p.y - s * 0.26, width: s * 0.84, height: s * 0.52)),
                         with: .radialGradient(Gradient(colors: [c(1, 0.85, 0.3), c(1, 0.4, 0.1), c(0.5, 0.1, 0.04)]), center: p, startRadius: 0, endRadius: s * 0.44))
            } else {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.3, y: p.y - s * 0.2, width: s * 0.6, height: s * 0.4)), with: .color(c(0.1, 0.06, 0.06)))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.18, y: p.y - s * 0.16, width: s * 0.26, height: s * 0.14)), with: .color(c(0.28, 0.16, 0.14)))
            }
        }
    }

    /// A top-down race car along its heading: wheels, a tapered body with a racing stripe, the
    /// cockpit, a rear wing. The player's car is banana yellow.
    static func car(_ ctx: GraphicsContext, at p: CGPoint, heading: Double, length L: CGFloat, color: Color, player: Bool, dim: Bool, spinning: Bool) {
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        g.rotate(by: .radians(heading))
        g.opacity = dim ? 0.55 : 1
        let W = L * 0.62
        g.fill(Path(roundedRect: CGRect(x: -L * 0.46, y: -W * 0.46, width: L * 0.96, height: W * 0.96), cornerRadius: W * 0.3)
                .applying(CGAffineTransform(translationX: 1.5, y: 2)), with: .color(.black.opacity(0.35)))
        for (x, y) in [(-0.3, -0.52), (-0.3, 0.52), (0.28, -0.5), (0.28, 0.5)] as [(CGFloat, CGFloat)] {
            g.fill(Path(roundedRect: CGRect(x: x * L - L * 0.1, y: y * W - W * 0.13, width: L * 0.2, height: W * 0.26), cornerRadius: W * 0.06),
                   with: .color(Color(white: 0.1)))
        }
        var body = Path()
        body.move(to: CGPoint(x: -L * 0.46, y: -W * 0.42))
        body.addLine(to: CGPoint(x: L * 0.2, y: -W * 0.42))
        body.addQuadCurve(to: CGPoint(x: L * 0.5, y: 0), control: CGPoint(x: L * 0.5, y: -W * 0.34))
        body.addQuadCurve(to: CGPoint(x: L * 0.2, y: W * 0.42), control: CGPoint(x: L * 0.5, y: W * 0.34))
        body.addLine(to: CGPoint(x: -L * 0.46, y: W * 0.42))
        body.closeSubpath()
        g.fill(body, with: .linearGradient(Gradient(colors: [color.mix(with: .white, by: 0.3), color, color.mix(with: .black, by: 0.3)]),
                                           startPoint: CGPoint(x: 0, y: -W * 0.42), endPoint: CGPoint(x: 0, y: W * 0.42)))
        g.fill(Path(CGRect(x: -L * 0.46, y: -W * 0.08, width: L * 0.9, height: W * 0.16)),
               with: .color(player ? Color(white: 0.1).opacity(0.85) : .white.opacity(0.75)))
        g.fill(Path(roundedRect: CGRect(x: -L * 0.02, y: -W * 0.24, width: L * 0.22, height: W * 0.48), cornerRadius: W * 0.14),
               with: .color(Color(red: 0.12, green: 0.18, blue: 0.26)))
        g.fill(Path(roundedRect: CGRect(x: L * 0.04, y: -W * 0.16, width: L * 0.08, height: W * 0.14), cornerRadius: W * 0.05),
               with: .color(.white.opacity(0.5)))
        g.fill(Path(roundedRect: CGRect(x: -L * 0.52, y: -W * 0.52, width: L * 0.1, height: W * 1.04), cornerRadius: W * 0.04),
               with: .color(color.mix(with: .black, by: 0.45)))
        g.stroke(body, with: .color(.black.opacity(0.6)), lineWidth: max(0.8, L * 0.04))
        if spinning {
            g.opacity = 0.6
            for k in 0..<3 {
                let q = CGPoint(x: -L * (0.6 + CGFloat(k) * 0.18), y: CGFloat(k % 2 == 0 ? -1 : 1) * W * 0.3)
                g.fill(Path(ellipseIn: CGRect(x: q.x - W * 0.3, y: q.y - W * 0.3, width: W * 0.6, height: W * 0.6)), with: .color(Color(white: 0.85)))
            }
        }
    }

    /// A missile along its heading: white body, red nose, fins, a flickering flame.
    static func rocket(_ ctx: GraphicsContext, at p: CGPoint, heading: Double, length L: CGFloat, flick: Bool) {
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        g.rotate(by: .radians(heading))
        let W = L * 0.34
        let flame = flick ? L * 0.55 : L * 0.38
        var fire = Path()
        fire.move(to: CGPoint(x: -L * 0.42, y: -W * 0.35)); fire.addLine(to: CGPoint(x: -L * 0.42 - flame, y: 0)); fire.addLine(to: CGPoint(x: -L * 0.42, y: W * 0.35)); fire.closeSubpath()
        g.fill(fire, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.6), Color(red: 1, green: 0.5, blue: 0.1).opacity(0)]),
                                           startPoint: CGPoint(x: -L * 0.42, y: 0), endPoint: CGPoint(x: -L * 0.42 - flame, y: 0)))
        var fins = Path()
        fins.move(to: CGPoint(x: -L * 0.3, y: 0)); fins.addLine(to: CGPoint(x: -L * 0.46, y: -W * 0.85)); fins.addLine(to: CGPoint(x: -L * 0.46, y: W * 0.85)); fins.closeSubpath()
        g.fill(fins, with: .color(Color(red: 0.75, green: 0.18, blue: 0.16)))
        let body = Path(roundedRect: CGRect(x: -L * 0.42, y: -W / 2, width: L * 0.72, height: W), cornerRadius: W * 0.3)
        g.fill(body, with: .linearGradient(Gradient(colors: [Color(white: 0.98), Color(white: 0.7)]), startPoint: CGPoint(x: 0, y: -W / 2), endPoint: CGPoint(x: 0, y: W / 2)))
        var nose = Path()
        nose.move(to: CGPoint(x: L * 0.3, y: -W / 2)); nose.addQuadCurve(to: CGPoint(x: L * 0.5, y: 0), control: CGPoint(x: L * 0.46, y: -W * 0.45))
        nose.addQuadCurve(to: CGPoint(x: L * 0.3, y: W / 2), control: CGPoint(x: L * 0.46, y: W * 0.45)); nose.closeSubpath()
        g.fill(nose, with: .color(Color(red: 0.9, green: 0.2, blue: 0.18)))
        g.stroke(body, with: .color(.black.opacity(0.5)), lineWidth: max(0.6, L * 0.03))
    }
}

/// The circuit, drawn once per race: the world's ground and scenery (kept off the tarmac), red and
/// white kerbs, textured asphalt the width the physics allows, white edge lines, a dashed centre
/// line, and the chequered start/finish across index 0.
private struct RKTrack: View, Equatable {
    let size: CGSize
    let center: [CGPoint]
    let halfWidth: Double
    let level: Int

    var body: some View {
        Canvas { ctx, _ in
            let W = size.width, H = size.height
            let (g0, g1) = RKArt.ground(level)
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [g0, g1]), startPoint: .zero, endPoint: CGPoint(x: 0, y: H)))
            if level >= 5 {
                var stars = Path()
                for i in 0..<50 {
                    let d: CGFloat = 1 + CGFloat(RKArt.hash(Double(i) * 1.7)) * 1.4
                    stars.addEllipse(in: CGRect(x: CGFloat(RKArt.hash(Double(i) * 12.9)) * W, y: CGFloat(RKArt.hash(Double(i) * 78.2)) * H, width: d, height: d))
                }
                ctx.fill(stars, with: .color((level == 5 ? Color.white : Color(red: 1, green: 0.6, blue: 0.4)).opacity(0.55)))
            }
            // Ground speckle.
            var speck = Path()
            for i in 0..<160 {
                let d: CGFloat = 1.5 + CGFloat(RKArt.hash(Double(i) * 3.3)) * 2.5
                speck.addEllipse(in: CGRect(x: CGFloat(RKArt.hash(Double(i) * 5.1)) * W, y: CGFloat(RKArt.hash(Double(i) * 9.7)) * H, width: d, height: d * 0.7))
            }
            ctx.fill(speck, with: .color(g1.mix(with: .black, by: 0.25).opacity(0.5)))
            guard center.count > 2 else { return }
            let minDim = min(W, H)
            let hw = CGFloat(halfWidth) * minDim
            func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * W, y: p.y * H) }
            // Scenery away from the track.
            let clear = hw + minDim * 0.05
            for i in 0..<80 {
                let q = CGPoint(x: CGFloat(RKArt.hash(Double(i) * 17.3)) * W, y: CGFloat(RKArt.hash(Double(i) * 31.7)) * H)
                let near = center.contains { hypot($0.x * W - q.x, $0.y * H - q.y) < clear }
                if near { continue }
                RKArt.prop(ctx, at: q, size: minDim * 0.055, level: level, seed: RKArt.hash(Double(i) * 2.9))
            }
            var path = Path()
            path.move(to: pt(center[0]))
            for p in center.dropFirst() { path.addLine(to: pt(p)) }
            path.closeSubpath()
            let lw = hw * 2
            // Kerbs: red with white blocks, just outside the tarmac.
            ctx.stroke(path, with: .color(Color(red: 0.86, green: 0.16, blue: 0.14)), style: StrokeStyle(lineWidth: lw + 9, lineCap: .round, lineJoin: .round))
            ctx.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: lw + 9, lineCap: .butt, lineJoin: .round, dash: [7, 7]))
            // Tarmac with a faint grain.
            let tarmac = level >= 5 ? Color(white: 0.2) : Color(white: 0.3)
            ctx.stroke(path, with: .color(tarmac), style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
            ctx.stroke(path, with: .color(.white.opacity(0.05)), style: StrokeStyle(lineWidth: lw * 0.6, lineCap: .round, lineJoin: .round, dash: [2, 9]))
            ctx.stroke(path, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: lw - 2, lineCap: .round, lineJoin: .round))
            ctx.stroke(path, with: .color(tarmac), style: StrokeStyle(lineWidth: lw - 5, lineCap: .round, lineJoin: .round))
            ctx.stroke(path, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 2, lineCap: .butt, dash: [10, 12]))
            // Start / finish: a chequered band across the track at index 0.
            let a = center[0], b = center[1]
            let dir = CGVector(dx: b.x - a.x, dy: b.y - a.y)
            let dl = max(0.0001, hypot(dir.dx, dir.dy))
            let nrm = CGVector(dx: -dir.dy / dl, dy: dir.dx / dl)
            let along = CGVector(dx: dir.dx / dl, dy: dir.dy / dl)
            let squares = 8
            for row in 0..<2 {
                for s in 0..<squares {
                    let t0 = CGFloat(s) / CGFloat(squares) * 2 - 1
                    let t1 = CGFloat(s + 1) / CGFloat(squares) * 2 - 1
                    let off = CGFloat(row) * 4.5
                    let c0 = CGPoint(x: a.x * W + nrm.dx * hw * t0 + along.dx * off, y: a.y * H + nrm.dy * hw * t0 + along.dy * off)
                    let c1 = CGPoint(x: a.x * W + nrm.dx * hw * t1 + along.dx * off, y: a.y * H + nrm.dy * hw * t1 + along.dy * off)
                    var sq = Path()
                    sq.move(to: c0); sq.addLine(to: c1)
                    sq.addLine(to: CGPoint(x: c1.x + along.dx * 4.5, y: c1.y + along.dy * 4.5))
                    sq.addLine(to: CGPoint(x: c0.x + along.dx * 4.5, y: c0.y + along.dy * 4.5))
                    sq.closeSubpath()
                    ctx.fill(sq, with: .color((s + row) % 2 == 0 ? .white : .black))
                }
            }
        }
    }
}

/// A chequered flag (the lap counter).
private struct RKFlagIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            var pole = Path()
            pole.move(to: CGPoint(x: w * 0.14, y: h * 0.05)); pole.addLine(to: CGPoint(x: w * 0.14, y: h * 0.98))
            ctx.stroke(pole, with: .color(.white), lineWidth: max(1.5, w * 0.1))
            let flag = CGRect(x: w * 0.2, y: h * 0.08, width: w * 0.76, height: h * 0.5)
            ctx.fill(Path(flag), with: .color(.white))
            for r in 0..<3 {
                for c in 0..<4 where (r + c) % 2 == 0 {
                    ctx.fill(Path(CGRect(x: flag.minX + CGFloat(c) * flag.width / 4, y: flag.minY + CGFloat(r) * flag.height / 3,
                                         width: flag.width / 4, height: flag.height / 3)), with: .color(.black))
                }
            }
        }
    }
}

/// The player's place on a gold, silver or bronze medal.
private struct RKMedal: View {
    let place: Int

    var body: some View {
        let metal: [Color] = place == 1 ? [Color(red: 1, green: 0.88, blue: 0.4), Color(red: 0.86, green: 0.62, blue: 0.12)]
            : place == 2 ? [Color(white: 0.92), Color(white: 0.62)]
            : [Color(red: 0.92, green: 0.62, blue: 0.4), Color(red: 0.66, green: 0.38, blue: 0.2)]
        ZStack {
            Circle().fill(LinearGradient(colors: metal, startPoint: .top, endPoint: .bottom))
            Circle().strokeBorder(.black.opacity(0.4), lineWidth: 1.5)
            Text("\(place)")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .minimumScaleFactor(0.5)
                .foregroundStyle(Color(red: 0.25, green: 0.16, blue: 0.04))
                .padding(3)
        }
    }
}

/// A rocket pip for the HUD (lit = still in the rack).
private struct RKRocketIcon: View {
    let lit: Bool

    var body: some View {
        Canvas { ctx, size in
            var g = ctx
            g.translateBy(x: size.width / 2, y: size.height / 2)
            g.rotate(by: .degrees(-90))
            g.opacity = lit ? 1 : 0.28
            RKArt.rocket(g, at: .zero, heading: 0, length: size.height * 0.9, flick: false)
        }
    }
}

/// The driving keys: ◄ ►, the red FIRE key (a missile) and the green GAS key (a pedal).
private struct RKKey: View {
    enum Face { case left, right, fire, gas }
    let face: Face
    let color: Color
    let lit: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: lit ? [Color(red: 1, green: 0.92, blue: 0.5), Color(red: 0.96, green: 0.74, blue: 0.2)]
                                                 : [color.mix(with: .white, by: 0.18), color.mix(with: .black, by: 0.25)],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(lit ? 0.95 : 0.3), lineWidth: lit ? 2.5 : 1.5)
            Canvas { ctx, size in
                let ink: Color = lit ? Color(red: 0.2, green: 0.12, blue: 0) : .white
                let m = min(size.width, size.height)
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                switch face {
                case .left, .right:
                    let s: CGFloat = face == .left ? -1 : 1
                    var tri = Path()
                    tri.move(to: CGPoint(x: c.x + s * m * 0.2, y: c.y))
                    tri.addLine(to: CGPoint(x: c.x - s * m * 0.14, y: c.y - m * 0.2))
                    tri.addLine(to: CGPoint(x: c.x - s * m * 0.14, y: c.y + m * 0.2))
                    tri.closeSubpath()
                    ctx.fill(tri, with: .color(ink))
                case .fire:
                    var g = ctx
                    g.translateBy(x: c.x, y: c.y)
                    g.rotate(by: .degrees(-45))
                    RKArt.rocket(g, at: .zero, heading: 0, length: m * 0.62, flick: true)
                case .gas:
                    // An accelerator pedal in perspective: a ribbed pad leaning back on its arm and hinge.
                    var g = ctx
                    g.translateBy(x: c.x, y: c.y + m * 0.02)
                    var pad = Path()
                    pad.move(to: CGPoint(x: -m * 0.1, y: -m * 0.28))
                    pad.addLine(to: CGPoint(x: m * 0.1, y: -m * 0.28))
                    pad.addLine(to: CGPoint(x: m * 0.17, y: m * 0.08))
                    pad.addLine(to: CGPoint(x: -m * 0.17, y: m * 0.08))
                    pad.closeSubpath()
                    g.fill(pad, with: .color(ink))
                    var ribs = Path()
                    for k in 0..<4 {
                        let y = -m * 0.2 + CGFloat(k) * m * 0.08
                        let hw = m * (0.07 + 0.017 * CGFloat(k))
                        ribs.move(to: CGPoint(x: -hw, y: y)); ribs.addLine(to: CGPoint(x: hw, y: y))
                    }
                    g.stroke(ribs, with: .color(lit ? Color.white.opacity(0.7) : Color.black.opacity(0.45)), lineWidth: max(1.2, m * 0.04))
                    var arm = Path()
                    arm.move(to: CGPoint(x: 0, y: m * 0.08)); arm.addLine(to: CGPoint(x: -m * 0.08, y: m * 0.24))
                    g.stroke(arm, with: .color(ink), style: StrokeStyle(lineWidth: m * 0.07, lineCap: .round))
                    g.fill(Path(ellipseIn: CGRect(x: -m * 0.15, y: m * 0.19, width: m * 0.14, height: m * 0.11)), with: .color(ink))
                }
            }
        }
    }
}
