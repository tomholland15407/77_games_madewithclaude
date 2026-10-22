//
//  ParkingGame.swift
//  A Banana Game
//
//  Parking Challenge. A top-down lot: steer your car into the marked spot without
//  hitting a wall or a parked car. The car auto-creeps forward; you turn with a
//  rotary steering wheel (drag it round) and flip a REVERSE handle to back up.
//  Come to rest fully inside the spot to win; a collision or the countdown fails you.
//  Drag control → locksFeed (the page adds a skip button).
//
//  Drawn like the top-down parking games: an asphalt lot with painted bays and hazard-striped
//  curbs, the target bay glowing with a "P", parked cars in assorted colours, your banana-yellow
//  coupé with brake/reverse lights, and a dashboard with a leather wheel, a D/R gear lever and a
//  brake pedal.
//

import SwiftUI

enum ParkingGame {
    static let definition = GameDefinition(
        id: "parking", title: "Park King", emoji: "🍌",
        genre: .reflex, levelCount: 7, locksFeed: true,
        manual: GameManual(
            bullets: [
                "Your car creeps forward on its own. Turn the wheel to aim.",
                "Flip REVERSE to back up, and tap BRAKE to stop and line up a turn.",
                "Come to rest with the whole car inside the marked spot to win.",
                "Hit a wall or a parked car, or run out of time, and you're back to level 1.",
            ],
            bulletsVI: [
                "Xe của bạn tự bò về phía trước. Xoay vô lăng để nhắm hướng.",
                "Bật LÙI để đi lùi, và chạm PHANH để dừng và canh một cú rẽ.",
                "Dừng lại với cả xe nằm trọn trong ô đã đánh dấu để thắng.",
                "Đâm vào tường hay xe đang đỗ, hoặc hết giờ, sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(ParkingView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct ParkingView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    // Car dimensions as fractions of the play width (length along heading, width across).
    private let carL: CGFloat = 0.20
    private let carW: CGFloat = 0.10
    // The drivable field sits above the control strip.
    private let fieldTop: CGFloat = 0.06
    private let fieldBottom: CGFloat = 0.74

    // MARK: Difficulty
    private let creep: CGFloat = 0.052          // forward speed, fraction/s
    private let reverseCreep: CGFloat = 0.044
    private let turnRate: CGFloat = 2.4          // rad/s at full lock (snappy enough to maneuver)
    private var obstacleCount: Int { level - 1 } // L1 none flanking … L7 crowded
    // Later levels are crowded and demand a lot of shuffling, so the clock GROWS again
    // for L5–7 rather than shrinking — the difficulty is the tight slot, not the timer.
    private var timeLimit: Double { [44, 41, 39, 37, 44, 48, 52][min(level, 7) - 1] }
    /// Spot roominess around the car. Kept tight — the box is only a little bigger
    /// than the car so the challenge is fitting inside without touching the lines.
    /// `spotPadW` is the sliver across the car's width; `spotPadL` runs nose-to-tail.
    /// Slack around the car inside the box. Levels 1–4 are pinned to the level-5
    /// tightness (so even early parks demand precision); 5–7 keep shrinking.
    private var padLevel: Int { max(level, 5) }
    private var spotPadW: CGFloat { max(0.010, 0.036 - CGFloat(padLevel) * 0.0040) }
    private var spotPadL: CGFloat { max(0.014, 0.050 - CGFloat(padLevel) * 0.0060) }
    /// Gap between the spot and the parked cars flanking it — also tighter each level.
    private var neighborGap: CGFloat { max(0.012, 0.032 - CGFloat(level) * 0.0028) }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var pos = CGPoint(x: 0.5, y: 0.58)
    @State private var heading: CGFloat = -.pi / 2   // pointing "up" the screen
    @State private var steer: CGFloat = 0            // -1 … 1
    @State private var reverse = false
    @State private var braking = false
    @State private var spot = CGRect(x: 0.4, y: 0.12, width: 0.2, height: 0.24)
    @State private var obstacles: [CGRect] = []
    @State private var timeLeft = 0.0
    @State private var loopTask: Task<Void, Never>?
    @State private var lastWheelAngle: Double?
    /// Play-area width ÷ height. The car is drawn scaled by width on BOTH axes (so
    /// rotation keeps its shape), so all collision/layout math converts a y offset
    /// from width-units to height-fraction by multiplying by this. Set once we know
    /// the real size — without it the car's collision box is far longer than the
    /// car you see, which caused phantom "you hit a wall" fails.
    @State private var aspect: CGFloat = 0.5
    @State private var didBegin = false
    /// The manual demo's own loop — NOT `loopTask`, which the real win() cancels.
    @State private var demoTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                ParkingLot(spot: spot, obstacles: obstacles, fieldTop: fieldTop, fieldBottom: fieldBottom).equatable()

                if !isDemo {
                    timeBar.frame(height: 10).padding(.horizontal, 48)
                        .frame(maxWidth: .infinity)
                        .position(x: size.width / 2, y: size.height * (fieldTop * 0.5))
                }

                // Your car.
                carBody(size: size)

                // Controls.
                steeringWheel(size: size)
                reverseHandle(size: size)
                brakeHandle(size: size)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { begin(size: size) }
        }
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .onDisappear { loopTask?.cancel(); demoTask?.cancel() }
    }

    private func carBody(size: CGSize) -> some View {
        CoupeArt(braking: braking, reversing: reverse)
            .equatable()
            .frame(width: carL * size.width, height: carW * size.width)
            .rotationEffect(.radians(Double(heading)))
            .position(x: pos.x * size.width, y: pos.y * size.height)
    }

    private func steeringWheel(size: CGSize) -> some View {
        let r = size.width * (isDemo ? 0.095 : 0.13)
        return ZStack {
            WheelArt()
            // Demo: a finger gripping the rim at the top, turning with the wheel.
            if isDemo {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: r * 0.7))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 3)
                    .offset(x: r * 0.18, y: -r * 0.72)
            }
        }
        .frame(width: r * 2, height: r * 2)
        // Turn the wheel visibly further than your finger travels, so the lock reads clearly.
        .rotationEffect(.radians(Double(steer) * 2.6))
        .position(x: size.width * (isDemo ? 0.2 : 0.22), y: size.height * (isDemo ? 0.87 : 0.87))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    guard phase == .play else { return }
                    let a = atan2(Double(v.location.y - r), Double(v.location.x - r))
                    if let last = lastWheelAngle {
                        // Smaller divisor ⇒ a little rotation moves the steering a lot
                        // (a ~50° drag reaches full lock), so it feels responsive.
                        steer = min(1, max(-1, steer + CGFloat(angleDelta(a, last)) / 0.9))
                    }
                    lastWheelAngle = a
                }
                .onEnded { _ in lastWheelAngle = nil }
        )
    }

    /// The D / R gear lever (a real toggle of `reverse`).
    private func reverseHandle(size: CGSize) -> some View {
        Button {
            guard phase == .play else { return }
            reverse.toggle()
            SoundManager.shared.tap(); Haptics.tap()
        } label: {
            VStack(spacing: 3) {
                GearLever(reverse: reverse)
                    .frame(width: isDemo ? 44 : 56, height: isDemo ? 40 : 56)
                Text(reverse ? L("REVERSE", "LÙI") : L("DRIVE", "TIẾN"))
                    .font(.system(size: isDemo ? 10 : 12, weight: .black))
                    .foregroundStyle(reverse ? Color(red: 1, green: 0.85, blue: 0.4) : .white.opacity(0.85))
            }
            .frame(width: isDemo ? 70 : 96, height: isDemo ? 58 : 84)
        }
        .buttonStyle(DashPressStyle())
        .position(x: size.width * (isDemo ? 0.84 : 0.84), y: size.height * (isDemo ? 0.87 : 0.88))
    }

    /// Toggle the brake: tap once to bring the car to a complete stop (it stays put
    /// so you can line up a turn), tap again to resume creeping. Because the car can
    /// sit still indefinitely, driving forward too long never fails you.
    private func brakeHandle(size: CGSize) -> some View {
        Button {
            guard phase == .play else { return }
            braking.toggle()
            SoundManager.shared.tap(); Haptics.tap()
        } label: {
            VStack(spacing: 3) {
                BrakePedal(pressed: braking)
                    .frame(width: isDemo ? 40 : 50, height: isDemo ? 40 : 56)
                Text(braking ? L("STOPPED", "ĐÃ DỪNG") : L("BRAKE", "PHANH"))
                    .font(.system(size: isDemo ? 10 : 12, weight: .black))
                    .foregroundStyle(braking ? Color(red: 1, green: 0.4, blue: 0.35) : .white.opacity(0.85))
            }
            .frame(width: isDemo ? 70 : 96, height: isDemo ? 58 : 84)
        }
        .buttonStyle(DashPressStyle())
        // Pedal and gear share the dashboard row, clear of the lot.
        .position(x: size.width * (isDemo ? 0.62 : 0.6), y: size.height * (isDemo ? 0.87 : 0.88))
    }

    /// The level clock as a parking-meter strip.
    private var timeBar: some View {
        GeometryReader { geo in
            let fraction = timeLimit > 0 ? timeLeft / timeLimit : 0
            HStack(spacing: 6) {
                Text("P")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.12, green: 0.4, blue: 0.85)))
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.45))
                    Capsule().fill(fraction < 0.3 ? Color(red: 0.95, green: 0.3, blue: 0.25) : Color(red: 0.35, green: 0.85, blue: 0.45))
                        .frame(width: max(0, (geo.size.width - 22) * fraction))
                }
                .frame(height: 8)
            }
        }
    }

    // MARK: - Flow

    private func begin(size: CGSize) {
        guard !didBegin, size.width > 0, size.height > 0 else { return }
        didBegin = true
        aspect = size.width / size.height
        if isDemo { demoTask = Task { await runDemo() }; return }

        phase = .play
        pos = CGPoint(x: 0.5, y: 0.63)
        heading = -.pi / 2
        steer = 0
        reverse = false
        braking = false
        buildLot()
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

    private func buildLot(spotX: CGFloat? = nil) {
        // The car parks nose-in (pointing up). Everything here is in field-fraction
        // space (x = fraction of width, y = fraction of height). The car's DRAWN
        // length along y is `carL * aspect` (it's scaled by width, not height), so the
        // box must use that — otherwise the box looks/behaves twice as long as the car.
        let carYExtent = carL * aspect
        let sw = carW + spotPadW * 2          // narrow: across the car
        let sh = carYExtent + spotPadL * 2    // tall: nose-to-tail
        let sx = spotX ?? CGFloat.random(in: 0.24...0.76)
        let cy = fieldTop + sh / 2 + 0.04     // keep the whole box (and a parked car) inside the field
        let spotRect = CGRect(x: sx - sw / 2, y: cy - sh / 2, width: sw, height: sh)
        spot = spotRect

        var obs: [CGRect] = []
        // Parked neighbours hugging the spot (what makes it a real slot).
        if obstacleCount >= 1 {
            obs.append(CGRect(x: spotRect.minX - sw - neighborGap, y: spotRect.minY, width: sw, height: sh))
        }
        if obstacleCount >= 2 {
            obs.append(CGRect(x: spotRect.maxX + neighborGap, y: spotRect.minY, width: sw, height: sh))
        }
        // The car's starting footprint (nose-up), padded, so nothing spawns on or hugging it.
        let startRect = CGRect(x: 0.5 - carW / 2, y: 0.63 - carYExtent / 2, width: carW, height: carYExtent)
            .insetBy(dx: -0.05, dy: -0.05)

        // Extra scattered cars in the mid-field, clear of the spot, each other, and the start.
        var tries = 0
        while obs.count < obstacleCount && tries < 400 {
            tries += 1
            let r = CGRect(x: CGFloat.random(in: 0.16...0.68),
                           y: CGFloat.random(in: 0.30...0.46),
                           width: sw, height: sh)
            if r.insetBy(dx: -0.04, dy: -0.04).intersects(spotRect) { continue }
            // Keep a clear lane between scattered cars so they never crowd together.
            if obs.contains(where: { $0.insetBy(dx: -0.06, dy: -0.05).intersects(r) }) { continue }
            // Keep the car's whole starting footprint clear.
            if r.intersects(startRect) { continue }
            obs.append(r)
        }
        obstacles = obs
    }

    // MARK: - Demo (live manual clip)
    // Level 1: an open lot, a tight L1 box up and to the right. The real `step` runs at a fixed
    // 1/60s; your hands are a smooth feedback steer (aim the nose at the box's lane, then
    // straighten, wheel rate-limited like a real hand) and the car noses in square — all four
    // corners inside → the real win(). The car starts a touch higher than in play so its tail
    // clears the field edge in the squat card. Verified offline across card widths (~7s).
    private static let demoSpotX: CGFloat = 0.62

    private func runDemo() async {
        let dt: CGFloat = 1.0 / 60.0
        while !Task.isCancelled {
            phase = .play
            pos = CGPoint(x: 0.5, y: 0.58)
            heading = -.pi / 2
            steer = 0; reverse = false; braking = false
            buildLot(spotX: Self.demoSpotX)
            timeLeft = timeLimit
            try? await Task.sleep(for: .seconds(0.6))
            var t = 0.0
            while !Task.isCancelled && phase == .play && t < 14 {
                t += Double(dt)
                let desired = -.pi / 2 + max(-0.6, min(0.6, 16 * (spot.midX - pos.x)))
                let want = max(-1, min(1, (desired - heading) * 5))
                steer += max(-3 * dt, min(3 * dt, want - steer))
                step(dt: dt)
                try? await Task.sleep(for: .seconds(0.016))
            }
            // Parked square in the box → the real win() ran (onWin is a no-op). Hold, then loop.
            withAnimation(.easeOut(duration: 0.3)) { steer = 0 }
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    private func step(dt: CGFloat) {
        let v = braking ? 0 : (reverse ? -reverseCreep : creep)
        // Turning only happens while actually moving (reversing flips the wheel).
        if v != 0 { heading += steer * turnRate * dt * (v > 0 ? 1 : -1) }

        var p = pos
        p.x += cos(heading) * v * dt
        p.y += sin(heading) * v * dt

        // Soft outer walls: the field edge just blocks the car (no fail), so creeping
        // forward too long can't lose the game — only parked cars or the clock do.
        let tentative = carCorners(at: p)
        let hitsWall = tentative.contains { $0.x < 0.01 || $0.x > 0.99 || $0.y < fieldTop || $0.y > fieldBottom }
        if !hitsWall { pos = p }

        let corners = carCorners(at: pos)
        // Parked cars are hard collisions, but shrink them a hair so a light graze
        // of the paint doesn't instantly fail you — only a real overlap does.
        let touchTol: CGFloat = 0.012
        for ob in obstacles {
            let hitBox = ob.insetBy(dx: touchTol, dy: touchTol)
            if corners.contains(where: { hitBox.contains($0) }) { fail(); return }
            for oc in rectCorners(hitBox) where pointInPolygon(oc, corners) { fail(); return }
        }

        // Win only when the ENTIRE car is inside the bounded spot — all four rotated
        // corners must sit within the spot rect itself (no inflation). This inherently
        // enforces alignment: a tilted car pokes a corner over a line and won't register.
        if corners.allSatisfy({ spot.contains($0) }) {
            win()
        }
    }

    /// The car's four corners in field-fraction space for a given center.
    /// Offsets are computed in width-units (the car is drawn scaled by width on both
    /// axes), then the y component is converted to height-fraction via `aspect` so
    /// this polygon lines up exactly with the car you see on screen.
    private func carCorners(at p: CGPoint) -> [CGPoint] {
        let fx = cos(heading), fy = sin(heading)     // forward
        let sx = -fy, sy = fx                         // side
        let hl = carL / 2, hw = carW / 2
        return [(hl, hw), (hl, -hw), (-hl, -hw), (-hl, hw)].map { (a, b) in
            CGPoint(x: p.x + fx * a + sx * b,
                    y: p.y + (fy * a + sy * b) * aspect)
        }
    }

    private func rectCorners(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
         CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
    }

    private func pointInPolygon(_ pt: CGPoint, _ poly: [CGPoint]) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > pt.y) != (b.y > pt.y),
               pt.x < (b.x - a.x) * (pt.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// Smallest signed difference between two angles.
    private func angleDelta(_ a: Double, _ b: Double) -> Double {
        var d = a - b
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
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

// MARK: - Parking-lot art

private enum ParkArt {
    static let paint = Color(red: 0.96, green: 0.96, blue: 0.92)
    static let carColours: [Color] = [Color(red: 0.85, green: 0.2, blue: 0.2), Color(red: 0.2, green: 0.45, blue: 0.85),
                                      Color(red: 0.92, green: 0.92, blue: 0.94), Color(red: 0.18, green: 0.2, blue: 0.24),
                                      Color(red: 0.25, green: 0.65, blue: 0.4), Color(red: 0.62, green: 0.64, blue: 0.68),
                                      Color(red: 0.95, green: 0.55, blue: 0.15)]

    static func hash(_ n: Double) -> CGFloat {
        let v: Double = sin(n * 12.9898) * 43758.5453
        return CGFloat(v - floor(v))
    }

    /// A top-down car filling `r`, nose toward `nose` (unit vector: (0,-1) is up, (1,0) is right).
    static func car(_ ctx: GraphicsContext, in r: CGRect, color: Color, noseUp: Bool,
                    brake: Bool = false, reverse: Bool = false, stripes: Bool = false) {
        var c = ctx
        // Work in a frame where the car points right: length along x.
        let len = noseUp ? r.height : r.width, wid = noseUp ? r.width : r.height
        c.translateBy(x: r.midX, y: r.midY)
        if noseUp { c.rotate(by: .degrees(-90)) }
        let body = CGRect(x: -len / 2, y: -wid / 2, width: len, height: wid)
        let shape = Path(roundedRect: body, cornerSize: CGSize(width: len * 0.16, height: wid * 0.32))
        c.fill(shape.offsetBy(dx: wid * 0.06, dy: wid * 0.1), with: .color(.black.opacity(0.35)))
        c.fill(shape, with: .linearGradient(Gradient(colors: [color.lit(0.25), color, color.shade(0.25)]),
                                            startPoint: CGPoint(x: 0, y: -wid / 2), endPoint: CGPoint(x: 0, y: wid / 2)))
        c.stroke(shape, with: .color(color.shade(0.55)), lineWidth: 1)
        if stripes {
            // Twin racing stripes over the bonnet, roof and boot.
            for s in [-1.0, 1.0] as [CGFloat] {
                let stripe = CGRect(x: -len * 0.47, y: s * wid * 0.07 - wid * 0.045, width: len * 0.94, height: wid * 0.09)
                var clip = c
                clip.clip(to: shape)
                clip.fill(Path(stripe), with: .color(Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.85)))
            }
        }
        // Windscreen, roof, rear window.
        let glass = Color(red: 0.16, green: 0.2, blue: 0.28)
        c.fill(Path(roundedRect: CGRect(x: len * 0.08, y: -wid * 0.36, width: len * 0.17, height: wid * 0.72), cornerRadius: wid * 0.1), with: .color(glass))
        c.fill(Path(roundedRect: CGRect(x: -len * 0.24, y: -wid * 0.34, width: len * 0.12, height: wid * 0.68), cornerRadius: wid * 0.08), with: .color(glass))
        c.fill(Path(roundedRect: CGRect(x: -len * 0.12, y: -wid * 0.36, width: len * 0.2, height: wid * 0.72), cornerRadius: wid * 0.1), with: .color(color.lit(0.1)))
        // Side mirrors.
        for s in [-1.0, 1.0] as [CGFloat] {
            c.fill(Path(ellipseIn: CGRect(x: len * 0.14, y: s * wid * 0.5 - wid * 0.07, width: len * 0.07, height: wid * 0.14)), with: .color(color.shade(0.2)))
        }
        // Headlights and taillights.
        for s in [-1.0, 1.0] as [CGFloat] {
            c.fill(Path(roundedRect: CGRect(x: len * 0.43, y: s * wid * 0.3 - wid * 0.08, width: len * 0.06, height: wid * 0.16), cornerRadius: 1.5),
                   with: .color(Color(red: 1, green: 0.97, blue: 0.8)))
            let tail = CGRect(x: -len * 0.49, y: s * wid * 0.3 - wid * 0.08, width: len * 0.05, height: wid * 0.16)
            c.fill(Path(roundedRect: tail, cornerRadius: 1.5), with: .color(brake ? Color(red: 1, green: 0.15, blue: 0.1) : Color(red: 0.6, green: 0.08, blue: 0.08)))
            if brake {
                c.fill(Path(ellipseIn: tail.insetBy(dx: -len * 0.06, dy: -wid * 0.1)),
                       with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.2, blue: 0.1).opacity(0.6), .clear]),
                                             center: CGPoint(x: tail.midX, y: tail.midY), startRadius: 0, endRadius: len * 0.1))
            }
            if reverse {
                c.fill(Path(roundedRect: CGRect(x: -len * 0.49, y: s * wid * 0.12 - wid * 0.05, width: len * 0.04, height: wid * 0.1), cornerRadius: 1),
                       with: .color(.white))
            }
        }
    }
}

/// The lot: asphalt, hazard-striped curbs, painted bays, the glowing target bay, parked cars, and
/// the dashboard below the field. Static for the round.
private struct ParkingLot: View, Equatable {
    let spot: CGRect
    let obstacles: [CGRect]
    let fieldTop: CGFloat
    let fieldBottom: CGFloat

    var body: some View {
        Canvas { ctx, s in
            let w = s.width, h = s.height
            func rect(_ r: CGRect) -> CGRect { CGRect(x: r.minX * w, y: r.minY * h, width: r.width * w, height: r.height * h) }
            // Sidewalk around everything.
            ctx.fill(Path(CGRect(origin: .zero, size: s)), with: .color(Color(red: 0.62, green: 0.62, blue: 0.6)))
            // Asphalt field.
            let field = CGRect(x: w * 0.01, y: fieldTop * h, width: w * 0.98, height: (fieldBottom - fieldTop) * h)
            ctx.fill(Path(field), with: .linearGradient(Gradient(colors: [Color(red: 0.25, green: 0.26, blue: 0.29), Color(red: 0.2, green: 0.21, blue: 0.24)]),
                                                        startPoint: CGPoint(x: 0, y: field.minY), endPoint: CGPoint(x: 0, y: field.maxY)))
            var grit = Path()
            for k in 0..<260 {
                let x = field.minX + ParkArt.hash(Double(k) * 1.37) * field.width, y = field.minY + ParkArt.hash(Double(k) * 2.71 + 3) * field.height
                grit.addEllipse(in: CGRect(x: x, y: y, width: 1.4, height: 1.4))
            }
            ctx.fill(grit, with: .color(.white.opacity(0.07)))
            for k in 0..<4 {
                let x = field.minX + ParkArt.hash(Double(k) * 5.3) * field.width, y = field.minY + field.height * (0.35 + ParkArt.hash(Double(k) * 7.9) * 0.55)
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 24 + ParkArt.hash(Double(k)) * 20, height: 12 + ParkArt.hash(Double(k) + 1) * 8)),
                         with: .color(.black.opacity(0.22)))
            }
            // Curb with hazard stripes around the field.
            let curb: CGFloat = 5
            var stripes = ctx
            let ring = Path(field.insetBy(dx: -curb, dy: -curb)).subtracting(Path(field))
            stripes.clip(to: ring)
            stripes.fill(ring, with: .color(Color(red: 0.95, green: 0.78, blue: 0.1)))
            var diag = Path()
            var x: CGFloat = -h
            while x < w + h { diag.move(to: CGPoint(x: x, y: 0)); diag.addLine(to: CGPoint(x: x + h, y: h)); x += 14 }
            stripes.stroke(diag, with: .color(Color(red: 0.12, green: 0.12, blue: 0.12)), lineWidth: 6)
            // Painted bays across the top row, keyed to the target bay.
            let sp = rect(spot)
            let pitch = obstacles.first.map { abs(rect($0).minX - sp.minX) } ?? sp.width * 1.35
            let gap = max(4, pitch - sp.width)
            var bays = Path()
            var bx = sp.minX - gap / 2
            while bx > field.minX { bays.move(to: CGPoint(x: bx, y: sp.minY - 4)); bays.addLine(to: CGPoint(x: bx, y: sp.maxY + 4)); bx -= pitch }
            bx = sp.maxX + gap / 2
            while bx < field.maxX { bays.move(to: CGPoint(x: bx, y: sp.minY - 4)); bays.addLine(to: CGPoint(x: bx, y: sp.maxY + 4)); bx += pitch }
            bays.move(to: CGPoint(x: field.minX, y: sp.minY - 4)); bays.addLine(to: CGPoint(x: field.maxX, y: sp.minY - 4))
            ctx.stroke(bays, with: .color(ParkArt.paint.opacity(0.75)), lineWidth: 2.5)
            // The target bay: glowing, framed exactly on the win box, with a painted P.
            ctx.fill(Path(sp), with: .color(Color(red: 0.3, green: 0.9, blue: 0.45).opacity(0.18)))
            ctx.draw(Text("P").font(.system(size: sp.width * 0.62, weight: .black)).foregroundColor(ParkArt.paint.opacity(0.35)),
                     at: CGPoint(x: sp.midX, y: sp.midY))
            ctx.stroke(Path(roundedRect: sp, cornerRadius: 3), with: .color(Color(red: 1, green: 0.85, blue: 0.2)), lineWidth: 3)
            // Parked cars.
            for (i, ob) in obstacles.enumerated() {
                let r = rect(ob).insetBy(dx: rect(ob).width * 0.08, dy: rect(ob).height * 0.05)
                ParkArt.car(ctx, in: r, color: ParkArt.carColours[i % ParkArt.carColours.count], noseUp: true)
            }
            // Dashboard across the bottom.
            let dashTop = fieldBottom * h + curb + 4
            let dash = CGRect(x: 0, y: dashTop, width: w, height: h - dashTop)
            ctx.fill(Path(roundedRect: dash, cornerSize: CGSize(width: 18, height: 18)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.2, green: 0.2, blue: 0.23), Color(red: 0.08, green: 0.08, blue: 0.1)]),
                                           startPoint: CGPoint(x: 0, y: dashTop), endPoint: CGPoint(x: 0, y: h)))
            var stitch = Path()
            stitch.move(to: CGPoint(x: 12, y: dashTop + 7)); stitch.addLine(to: CGPoint(x: w - 12, y: dashTop + 7))
            ctx.stroke(stitch, with: .color(Color(red: 0.7, green: 0.55, blue: 0.3).opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .allowsHitTesting(false)
    }
}

/// Your banana-yellow coupé (pointing right, as `heading` 0 does); brake and reverse lights.
private struct CoupeArt: View, Equatable {
    let braking: Bool
    let reversing: Bool

    var body: some View {
        Canvas { ctx, s in
            ParkArt.car(ctx, in: CGRect(origin: .zero, size: s), color: Color(red: 1, green: 0.84, blue: 0.2), noseUp: false,
                        brake: braking, reverse: reversing, stripes: true)
        }
        .allowsHitTesting(false)
    }
}

/// A leather steering wheel with three silver spokes and a banana on the hub.
private struct WheelArt: View {
    var body: some View {
        Canvas { ctx, s in
            let c = CGPoint(x: s.width / 2, y: s.height / 2), r = min(s.width, s.height) / 2
            let rim = r * 0.18
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2).offsetBy(dx: 0, dy: 3)), with: .color(.black.opacity(0.35)))
            var spokes = Path()
            for a in [-90.0, 30.0, 150.0] {
                let rad = a * .pi / 180
                spokes.move(to: c)
                spokes.addLine(to: CGPoint(x: c.x + CGFloat(cos(rad)) * (r - rim * 0.5), y: c.y + CGFloat(sin(rad)) * (r - rim * 0.5)))
            }
            ctx.stroke(spokes, with: .color(Color(white: 0.2)), style: StrokeStyle(lineWidth: r * 0.22, lineCap: .round))
            ctx.stroke(spokes, with: .color(Color(white: 0.72)), style: StrokeStyle(lineWidth: r * 0.14, lineCap: .round))
            let ringPath = Path(ellipseIn: CGRect(x: c.x - r + rim / 2, y: c.y - r + rim / 2, width: (r - rim / 2) * 2, height: (r - rim / 2) * 2))
            ctx.stroke(ringPath, with: .color(Color(red: 0.12, green: 0.1, blue: 0.1)), lineWidth: rim)
            ctx.stroke(ringPath, with: .color(Color(red: 0.24, green: 0.2, blue: 0.19)), style: StrokeStyle(lineWidth: rim * 0.3, dash: [2, 3]))
            // Top marker so the lock reads, then the hub.
            ctx.fill(Path(roundedRect: CGRect(x: c.x - rim * 0.35, y: c.y - r, width: rim * 0.7, height: rim), cornerRadius: 2), with: .color(Color(red: 1, green: 0.82, blue: 0.2)))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.3, y: c.y - r * 0.3, width: r * 0.6, height: r * 0.6)), with: .color(Color(white: 0.16)))
            FruitArt.draw(.banana, in: ctx, at: CGPoint(x: c.x, y: c.y + r * 0.02), radius: r * 0.17)
        }
    }
}

/// The D / R gear lever: the knob sits on D, or pulled back to R.
private struct GearLever: View {
    let reverse: Bool
    var body: some View {
        Canvas { ctx, s in
            let w = s.width, h = s.height
            let slot = CGRect(x: w * 0.44, y: h * 0.14, width: w * 0.12, height: h * 0.72)
            ctx.fill(Path(roundedRect: CGRect(x: w * 0.1, y: 0, width: w * 0.8, height: h), cornerRadius: 8), with: .color(Color(white: 0.12)))
            ctx.fill(Path(roundedRect: slot, cornerRadius: 3), with: .color(.black))
            for (label, y, on) in [("D", h * 0.2, !reverse), ("R", h * 0.8, reverse)] {
                ctx.draw(Text(label).font(.system(size: h * 0.2, weight: .black))
                            .foregroundColor(on ? Color(red: 1, green: 0.85, blue: 0.4) : Color(white: 0.5)),
                         at: CGPoint(x: w * 0.25, y: y))
            }
            let ky = reverse ? h * 0.78 : h * 0.22
            let knob = CGRect(x: w * 0.5 - h * 0.17, y: ky - h * 0.17, width: h * 0.34, height: h * 0.34)
            ctx.fill(Path(ellipseIn: knob.offsetBy(dx: 0, dy: 2)), with: .color(.black.opacity(0.5)))
            ctx.fill(Path(ellipseIn: knob), with: .radialGradient(Gradient(colors: [Color(white: 0.75), Color(white: 0.25)]),
                                                                  center: CGPoint(x: knob.midX - knob.width * 0.2, y: knob.midY - knob.height * 0.25),
                                                                  startRadius: 0, endRadius: knob.width * 0.7))
        }
    }
}

/// The brake pedal: grooved rubber, pushed down while you're stopped.
private struct BrakePedal: View {
    let pressed: Bool
    var body: some View {
        Canvas { ctx, s in
            let w = s.width, h = s.height
            let pad = CGRect(x: w * 0.12, y: pressed ? h * 0.2 : h * 0.06, width: w * 0.76, height: h * (pressed ? 0.72 : 0.78))
            ctx.fill(Path(roundedRect: pad.offsetBy(dx: 0, dy: 3), cornerRadius: 6), with: .color(.black.opacity(0.5)))
            ctx.fill(Path(roundedRect: pad, cornerRadius: 6), with: .linearGradient(Gradient(colors: pressed ? [Color(white: 0.2), Color(white: 0.28)] : [Color(white: 0.38), Color(white: 0.2)]),
                                                                                    startPoint: CGPoint(x: 0, y: pad.minY), endPoint: CGPoint(x: 0, y: pad.maxY)))
            var grooves = Path()
            var y = pad.minY + pad.height * 0.18
            while y < pad.maxY - 3 { grooves.move(to: CGPoint(x: pad.minX + 5, y: y)); grooves.addLine(to: CGPoint(x: pad.maxX - 5, y: y)); y += pad.height * 0.16 }
            ctx.stroke(grooves, with: .color(.black.opacity(0.55)), lineWidth: 2)
            if pressed {
                ctx.stroke(Path(roundedRect: pad, cornerRadius: 6), with: .color(Color(red: 1, green: 0.3, blue: 0.25)), lineWidth: 2)
            }
        }
    }
}

/// Dashboard controls take a real press with a small dip and no default dimming.
private struct DashPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

