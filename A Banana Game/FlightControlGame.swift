//
//  FlightControlGame.swift
//  GOGs
//
//  Brain — Flight Control (Firemint's air-traffic classic). Aircraft drift in from the edges; touch
//  one and draw its route. Lead red jets to the red runway, yellow planes to the yellow runway and
//  blue helicopters to the helipad — a route that reaches the matching landing zone locks on and the
//  aircraft lands by itself. Land the level's quota; any mid-air collision ends it (the clock is a
//  backstop). Aircraft without a route fly straight and turn back at the screen edge.
//
//  Look: a mown-grass airfield with trees, painted runways (threshold stripes, dashed centre line,
//  coloured approach chevrons), a helipad, cartoon top-down aircraft with ground shadows (spinning
//  props and rotors), dotted routes, blinking edge warnings before arrivals, red proximity rings and
//  explosions. The static airfield is its own equatable view, so each frame only redraws traffic.
//
//  Ramp: more aircraft per level, arriving faster and flying faster, with all three types from L2.
//  Route drawing uses drags, so the feed locks while playing.
//

import SwiftUI

enum FlightControlGame {
    static let definition = GameDefinition(
        id: "flight-control",
        title: "Landing Lines",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        locksFeed: true,
        manual: GameManual(
            bullets: [
                "Touch an aircraft and draw a route for it to follow.",
                "Red jets land on the red runway, yellow planes on the yellow one, helicopters on the helipad.",
                "Land the number of aircraft shown to win.",
                "Any two aircraft touching mid-air, or the clock running out, sends you back to level 1.",
            ],
            bulletsVI: [
                "Chạm vào một máy bay và vẽ đường bay cho nó.",
                "Máy bay phản lực đỏ hạ cánh ở đường băng đỏ, máy bay vàng ở đường băng vàng, trực thăng ở bãi đáp.",
                "Hạ cánh đủ số máy bay yêu cầu để thắng.",
                "Hai máy bay va nhau trên không, hoặc hết giờ, bạn sẽ về lại cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(FlightControlView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

// MARK: - Model

/// World units: 1 unit = the play area's shorter side, so speeds/sizes feel the same on any screen.
private struct FCZone {
    let kind: Int             // 0 red jets, 1 yellow planes, 2 helicopters
    let center: CGPoint       // units
    let heading: Double       // landing direction (runways)
    let length: CGFloat
    let width: CGFloat
    var dir: CGPoint { CGPoint(x: cos(heading), y: sin(heading)) }
    var entrance: CGPoint { kind == 2 ? center : CGPoint(x: center.x - dir.x * length / 2, y: center.y - dir.y * length / 2) }
    var end: CGPoint { CGPoint(x: center.x + dir.x * length / 2, y: center.y + dir.y * length / 2) }
    var zoneRadius: CGFloat { kind == 2 ? 0.07 : 0.075 }
}

private struct FCPlane: Identifiable {
    let id: Int
    let kind: Int
    var p: CGPoint
    var heading: Double
    var speed: CGFloat
    var path: [CGPoint] = []
    var locked = false          // route ends in its landing zone
    var touchdown: Double? = nil
    var spin = Double.random(in: 0..<6)

    var size: CGFloat { [0.12, 0.105, 0.11][kind] }
}

private struct FCWarning { let kind: Int; let point: CGPoint; let heading: Double; let at: Double }

private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

// MARK: - View

struct FlightControlView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void
    @Environment(\.isDemo) private var isDemo

    private var quota: Int { [5, 7, 9, 11, 13, 15, 18][min(level, 7) - 1] }
    private var spawnEvery: Double { [5.0, 4.2, 3.6, 3.1, 2.7, 2.3, 2.0][min(level, 7) - 1] }
    private var speedK: CGFloat { [1.0, 1.05, 1.1, 1.18, 1.26, 1.34, 1.42][min(level, 7) - 1] }
    private var kinds: [Int] { level == 1 ? [0, 1] : [0, 1, 2] }
    private var timeLimit: Double { Double(quota) * spawnEvery + 45 }

    private static let colors: [Color] = [Color(red: 0.9, green: 0.2, blue: 0.18),
                                          Color(red: 0.98, green: 0.8, blue: 0.16),
                                          Color(red: 0.2, green: 0.5, blue: 0.95)]

    private enum Phase { case play, won, crashed, done }

    @State private var phase: Phase = .play
    @State private var size: CGSize = .zero
    @State private var planes: [FCPlane] = []
    @State private var warnings: [FCWarning] = []
    @State private var landed = 0
    @State private var clock = 0.0
    @State private var nextSpawn = 1.2
    @State private var nextID = 0
    @State private var drawingID: Int? = nil
    @State private var crash: (p: CGPoint, t0: Double)? = nil
    @State private var shake = 0
    @State private var timeLeft = 0.0
    @State private var demoFinger: CGPoint? = nil       // units

    // MARK: Geometry

    private var unit: CGFloat { max(1, min(size.width, size.height)) }
    private var world: CGSize { CGSize(width: size.width / unit, height: size.height / unit) }

    private var zones: [FCZone] {
        let w = world
        return [
            FCZone(kind: 0, center: CGPoint(x: 0.45 * w.width, y: 0.62 * w.height), heading: 20 * .pi / 180, length: 0.42, width: 0.078),
            FCZone(kind: 1, center: CGPoint(x: 0.66 * w.width, y: 0.3 * w.height), heading: -35 * .pi / 180, length: 0.3, width: 0.06),
            FCZone(kind: 2, center: CGPoint(x: 0.78 * w.width, y: 0.78 * w.height), heading: 0, length: 0, width: 0.065),
        ]
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                FCAirfield(size: geo.size, zones: zones, unit: unit).equatable()
                Canvas { ctx, _ in drawTraffic(ctx) }
                hud
            }
            .contentShape(Rectangle())
            .gesture(routeGesture, including: isDemo ? .none : .all)
            .screenShake(shake, amount: 8)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
    }

    private var hud: some View {
        VStack(spacing: 6) {
            if !isDemo {
                GeometryReader { g in
                    let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(.black.opacity(0.22))
                        Capsule().fill(frac < 0.3 ? .red : BananaTheme.banana).frame(width: g.size.width * frac)
                    }
                }
                .frame(height: 6)
                .padding(.horizontal, 40)
            }
            HStack(spacing: 6) {
                Image(systemName: "airplane.arrival")
                Text("\(min(landed, quota)) / \(quota)")
                    .contentTransition(.numericText())
                Spacer()
            }
            .font(.system(size: isDemo ? 15 : 20, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 0, x: 0, y: 2)
            .padding(.horizontal, isDemo ? 12 : 18)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, isDemo ? 8 : 12)
        .allowsHitTesting(false)
    }

    // MARK: Traffic drawing

    private func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * unit, y: p.y * unit) }

    private func drawTraffic(_ ctx: GraphicsContext) {
        guard size.width > 0 else { return }
        let u = unit

        // Routes: dots in the aircraft colour; a locked route (it will land) is drawn brighter.
        for pl in planes where !pl.path.isEmpty && pl.touchdown == nil {
            var route = Path()
            route.move(to: pt(pl.p))
            for q in pl.path { route.addLine(to: pt(q)) }
            let c = Self.colors[pl.kind]
            ctx.stroke(route, with: .color(.black.opacity(0.18)),
                       style: StrokeStyle(lineWidth: u * 0.014, lineCap: .round, lineJoin: .round, dash: [0.1, u * 0.03]))
            ctx.stroke(route, with: .color(pl.locked ? c.lit(0.15) : c.lit(0.55).opacity(0.95)),
                       style: StrokeStyle(lineWidth: u * (pl.locked ? 0.012 : 0.01), lineCap: .round, lineJoin: .round,
                                          dash: [0.1, u * 0.03]))
        }

        // Arrival warnings: a blinking chevron at the edge in the incoming aircraft's colour.
        for w in warnings where Int(clock * 5) % 2 == 0 {
            var g = ctx
            g.translateBy(x: w.point.x * u, y: w.point.y * u)
            g.rotate(by: .radians(w.heading))
            var tri = Path()
            tri.move(to: CGPoint(x: u * 0.035, y: 0))
            tri.addLine(to: CGPoint(x: -u * 0.02, y: -u * 0.03))
            tri.addLine(to: CGPoint(x: -u * 0.02, y: u * 0.03))
            tri.closeSubpath()
            g.fill(tri, with: .color(Self.colors[w.kind]))
            g.stroke(tri, with: .color(.white), lineWidth: 2)
        }

        // Proximity rings.
        let airborne = planes.filter { $0.touchdown == nil }
        var near = Set<Int>()
        for a in airborne {
            for b in airborne where b.id > a.id {
                if dist(a.p, b.p) < (a.size + b.size) * 0.5 * 2.3 { near.insert(a.id); near.insert(b.id) }
            }
        }

        // Aircraft: shadow first, then body; landing aircraft shrink onto the ground.
        for pl in planes.sorted(by: { ($0.touchdown != nil ? 0 : 1) < ($1.touchdown != nil ? 0 : 1) }) {
            let land = pl.touchdown.map { min(1, (clock - $0) / (pl.kind == 2 ? 0.9 : 1.3)) } ?? 0
            let scale = 1 - 0.32 * land
            let alt = 1 - land
            FCArt.draw(pl.kind, in: ctx, at: pt(pl.p), heading: pl.heading, length: pl.size * u * scale,
                       altitude: alt, spin: pl.spin, alpha: land > 0.85 ? (1 - land) / 0.15 : 1)
            if near.contains(pl.id) {
                let pulse = 0.85 + 0.15 * sin(clock * 14)
                let r = pl.size * u * 0.85 * pulse
                ctx.stroke(Path(ellipseIn: CGRect(x: pl.p.x * u - r, y: pl.p.y * u - r, width: r * 2, height: r * 2)),
                           with: .color(Color(red: 1, green: 0.15, blue: 0.1).opacity(0.9)), lineWidth: 2.5)
            }
        }

        // Crash.
        if let c = crash {
            let t = clock - c.t0
            let p = pt(c.p)
            for k in 0..<3 {
                let rr = u * CGFloat(0.04 + t * (0.25 - Double(k) * 0.05))
                let color: Color = [Color(red: 1, green: 0.85, blue: 0.3), Color(red: 1, green: 0.5, blue: 0.1),
                                    Color(red: 0.85, green: 0.2, blue: 0.1)][k]
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2)),
                         with: .color(color.opacity(max(0, 0.9 - t * 0.9))))
            }
            for k in 0..<7 {
                let a = Double(k) * 0.9
                let d = u * CGFloat(0.05 + t * 0.2)
                let rr = u * CGFloat(0.025 + t * 0.03)
                let q = CGPoint(x: p.x + CGFloat(cos(a)) * d, y: p.y + CGFloat(sin(a)) * d)
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - rr, y: q.y - rr, width: rr * 2, height: rr * 2)),
                         with: .color(Color(white: 0.25).opacity(max(0, 0.6 - t * 0.5))))
            }
        }

        // Demo finger.
        if let f = demoFinger {
            var hand = ctx.resolve(Image(systemName: "hand.point.up.left.fill"))
            hand.shading = .color(.white)
            var h = ctx
            h.addFilter(.shadow(color: .black.opacity(0.55), radius: 3))
            let w = u * 0.11
            h.draw(hand, in: CGRect(x: f.x * u - w * 0.28, y: f.y * u - w * 0.08, width: w, height: w))
        }
    }

    // MARK: Routes

    private var routeGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let p = CGPoint(x: v.location.x / unit, y: v.location.y / unit)
                if drawingID == nil {
                    let s = CGPoint(x: v.startLocation.x / unit, y: v.startLocation.y / unit)
                    beginRoute(at: s)
                }
                extendRoute(to: p)
            }
            .onEnded { _ in drawingID = nil }
    }

    private func beginRoute(at p: CGPoint) {
        guard phase == .play else { return }
        let grab = planes.filter { $0.touchdown == nil }
            .min { dist($0.p, p) < dist($1.p, p) }
        guard let pl = grab, dist(pl.p, p) < 0.11, let i = planes.firstIndex(where: { $0.id == pl.id }) else { return }
        drawingID = pl.id
        planes[i].path = []
        planes[i].locked = false
        Haptics.tap()
    }

    private func extendRoute(to p: CGPoint) {
        guard phase == .play, let id = drawingID, let i = planes.firstIndex(where: { $0.id == id }),
              !planes[i].locked else { return }
        let last = planes[i].path.last ?? planes[i].p
        guard dist(last, p) > 0.012 else { return }
        planes[i].path.append(CGPoint(x: min(max(p.x, 0.01), world.width - 0.01), y: min(max(p.y, 0.01), world.height - 0.01)))
        // Reaching the matching landing zone locks the route onto the runway / pad.
        let z = zones[planes[i].kind]
        if dist(p, z.entrance) < z.zoneRadius {
            let dx = p.x - last.x, dy = p.y - last.y
            let aligned = z.kind == 2 || (dx * z.dir.x + dy * z.dir.y) > 0
            if aligned {
                planes[i].path.append(z.entrance)
                if z.kind != 2 { planes[i].path.append(z.end) }
                planes[i].locked = true
                // drawingID stays set until the finger lifts: clearing it here made the rest of this drag
                // re-grab the aircraft and replace the drawn route with a straight line.
                SoundManager.shared.tap(); Haptics.tap()
            }
        }
    }

    // MARK: Simulation

    private func step(_ dt: Double) {
        clock += dt
        let w = world

        // Spawns (with a warning chevron first).
        if phase == .play {
            if clock >= nextSpawn {
                nextSpawn = clock + spawnEvery * Double.random(in: 0.8...1.2)
                if let s = spawnSpot() { warnings.append(FCWarning(kind: kinds.randomElement()!, point: s.edge, heading: s.heading, at: clock)) }
            }
            for wn in warnings where clock - wn.at >= 1.3 {
                let back = CGPoint(x: wn.point.x - cos(wn.heading) * 0.06, y: wn.point.y - sin(wn.heading) * 0.06)
                planes.append(FCPlane(id: nextID, kind: wn.kind, p: back, heading: wn.heading,
                                      speed: [0.075, 0.06, 0.045][wn.kind] * speedK))
                nextID += 1
            }
            warnings.removeAll { clock - $0.at >= 1.3 }
        }

        var remove = Set<Int>()
        for i in planes.indices {
            planes[i].spin += dt * (planes[i].kind == 2 ? 22 : 30)
            if let td = planes[i].touchdown {
                // Rolling out / settling on the pad.
                let t = clock - td
                if planes[i].kind != 2 {
                    advance(i, by: planes[i].speed * CGFloat(max(0.25, 1 - t * 0.6)) * CGFloat(dt))
                    if planes[i].path.isEmpty || t > 1.3 { remove.insert(planes[i].id) }
                } else if t > 0.9 {
                    remove.insert(planes[i].id)
                }
                continue
            }
            if !planes[i].path.isEmpty {
                advance(i, by: planes[i].speed * CGFloat(dt))
                let z = zones[planes[i].kind]
                if planes[i].locked {
                    let atGate = z.kind == 2 ? dist(planes[i].p, z.center) < 0.012
                                             : (planes[i].path.count <= 1 && dist(planes[i].p, z.entrance) < 0.03)
                    if atGate || (z.kind != 2 && planes[i].path.count == 1) {
                        planes[i].touchdown = clock
                        landed += 1
                        SoundManager.shared.tap(); Haptics.success()
                        if landed >= quota && phase == .play { phase = .won }
                    }
                }
            } else {
                // Straight on; turn back toward the field near an edge.
                var h = planes[i].heading
                let p = planes[i].p
                let m: CGFloat = 0.05
                let out = (p.x < m && cos(h) < 0) || (p.x > w.width - m && cos(h) > 0)
                    || (p.y < m && sin(h) < 0) || (p.y > w.height - m && sin(h) > 0)
                if out {
                    let toCenter = atan2(w.height / 2 - p.y, w.width / 2 - p.x)
                    var d = toCenter - h
                    while d > .pi { d -= 2 * .pi }
                    while d < -.pi { d += 2 * .pi }
                    h += max(-1, min(1, d)) * 1.8 * dt
                    planes[i].heading = h
                }
                planes[i].p.x += cos(h) * planes[i].speed * CGFloat(dt)
                planes[i].p.y += sin(h) * planes[i].speed * CGFloat(dt)
            }
        }
        planes.removeAll { remove.contains($0.id) }

        // Collisions between airborne aircraft.
        if phase == .play {
            let air = planes.filter { $0.touchdown == nil }
            outer: for a in air {
                for b in air where b.id > a.id && dist(a.p, b.p) < (a.size + b.size) * 0.5 * 0.82 {
                    crash = (CGPoint(x: (a.p.x + b.p.x) / 2, y: (a.p.y + b.p.y) / 2), clock)
                    planes.removeAll { $0.id == a.id || $0.id == b.id }
                    phase = .crashed
                    shake += 1
                    break outer
                }
            }
        }
    }

    private func advance(_ i: Int, by d: CGFloat) {
        var left = d
        while left > 0, let next = planes[i].path.first {
            let dx = next.x - planes[i].p.x, dy = next.y - planes[i].p.y
            let len = hypot(dx, dy)
            if len > 0.0001 {
                // Turn smoothly toward the route instead of snapping.
                let target = atan2(dy, dx)
                var diff = target - planes[i].heading
                while diff > .pi { diff -= 2 * .pi }
                while diff < -.pi { diff += 2 * .pi }
                planes[i].heading += diff * 0.35
            }
            if len <= left {
                planes[i].p = next
                planes[i].path.removeFirst()
                left -= len
            } else {
                planes[i].p.x += dx / len * left
                planes[i].p.y += dy / len * left
                left = 0
            }
        }
        if left > 0 {
            planes[i].p.x += cos(planes[i].heading) * left
            planes[i].p.y += sin(planes[i].heading) * left
        }
    }

    /// An edge point (just inside the frame) plus an inward heading, away from current traffic.
    private func spawnSpot() -> (edge: CGPoint, heading: Double)? {
        let w = world
        for _ in 0..<12 {
            let side = Int.random(in: 0..<4)
            let f = CGFloat.random(in: 0.18...0.82)
            let edge: CGPoint = [CGPoint(x: 0.03, y: f * w.height), CGPoint(x: w.width - 0.03, y: f * w.height),
                                 CGPoint(x: f * w.width, y: 0.12), CGPoint(x: f * w.width, y: w.height - 0.03)][side]
            let aim = CGPoint(x: CGFloat.random(in: 0.3...0.7) * w.width, y: CGFloat.random(in: 0.3...0.7) * w.height)
            if planes.contains(where: { dist($0.p, edge) < 0.28 }) { continue }
            return (edge, atan2(aim.y - edge.y, aim.x - edge.x))
        }
        return nil
    }

    // MARK: Flow

    private func run() async {
        while size.width == 0 && !Task.isCancelled { try? await Task.sleep(for: .seconds(0.02)) }
        phase = .play
        timeLeft = timeLimit
        let start = Date()
        var last = Date()
        var acc = 0.0
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1.0 / 60))
            let now = Date()
            acc += min(0.1, now.timeIntervalSince(last))
            last = now
            while acc >= 1.0 / 60 { acc -= 1.0 / 60; step(1.0 / 60) }
            switch phase {
            case .play:
                timeLeft = max(0, timeLimit - now.timeIntervalSince(start))
                if timeLeft <= 0 { fail(); return }
            case .won:
                try? await Task.sleep(for: .seconds(0.9))
                guard !Task.isCancelled else { return }
                phase = .done
                onWin()
                return
            case .crashed:
                SoundManager.shared.error()
                Haptics.warning()
                let t0 = Date()
                while Date().timeIntervalSince(t0) < 1.0 && !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1.0 / 60))
                    step(1.0 / 60)
                }
                guard !Task.isCancelled else { return }
                phase = .done
                onFail()
                return
            case .done:
                return
            }
        }
    }

    private func fail() {
        guard phase == .play else { return }
        phase = .done
        SoundManager.shared.error()
        onFail()
    }

    // MARK: - Demo (live manual clip)
    // Level 1's closing stretch (3 of 5 landed). A red jet cruises in from the left and the finger
    // curls a route into the red runway's approach; then it draws the helicopter across to the pad
    // while a yellow plane crosses the top, well clear. Both land through the real step/route code —
    // 5/5. (Demo aircraft fly a little faster so the clip stays short.)
    private func runDemo() async {
        while size.width == 0 && !Task.isCancelled { try? await Task.sleep(for: .seconds(0.02)) }
        while !Task.isCancelled {
            let w = world
            planes = [
                FCPlane(id: 1, kind: 0, p: CGPoint(x: 0.07, y: 0.3 * w.height), heading: 0.35, speed: 0.1),
                FCPlane(id: 2, kind: 2, p: CGPoint(x: 0.97 * w.width, y: 0.5 * w.height), heading: 2.8, speed: 0.075),
                FCPlane(id: 3, kind: 1, p: CGPoint(x: 0.42 * w.width, y: 0.13 * w.height), heading: 0.08, speed: 0.07),
            ]
            warnings = []
            landed = 3
            clock = 0
            nextSpawn = 999
            crash = nil
            phase = .play
            drawingID = nil
            demoFinger = nil
            await demoFrames(30)

            // Route 1: jet → red runway approach (a curve that arrives along the runway heading).
            await demoDraw(planeID: 1, zone: zones[0], bend: 0.12)
            await demoFrames(20)
            // Route 2: helicopter → pad.
            await demoDraw(planeID: 2, zone: zones[2], bend: -0.08)
            demoFinger = nil
            // Let both land.
            for _ in 0..<600 where !Task.isCancelled && landed < 5 {
                await demoFrames(1)
            }
            await demoFrames(80)
        }
    }

    /// The finger presses the aircraft and traces a quadratic curve that meets `zone` head-on.
    private func demoDraw(planeID: Int, zone: FCZone, bend: CGFloat) async {
        guard let pl = planes.first(where: { $0.id == planeID }) else { return }
        demoFinger = pl.p
        await demoFrames(10)
        beginRoute(at: pl.p)
        let a = planes.first(where: { $0.id == planeID })?.p ?? pl.p
        let target = zone.kind == 2 ? zone.center : CGPoint(x: zone.entrance.x + zone.dir.x * 0.01, y: zone.entrance.y + zone.dir.y * 0.01)
        let ctrl = zone.kind == 2
            ? CGPoint(x: (a.x + target.x) / 2 - bend, y: (a.y + target.y) / 2)
            : CGPoint(x: zone.entrance.x - zone.dir.x * bend * 1.6, y: zone.entrance.y - zone.dir.y * bend * 1.6)
        let steps = 48
        for s in 1...steps {
            guard !Task.isCancelled else { return }
            let t = CGFloat(s) / CGFloat(steps)
            let q = CGPoint(x: (1 - t) * (1 - t) * a.x + 2 * (1 - t) * t * ctrl.x + t * t * target.x,
                            y: (1 - t) * (1 - t) * a.y + 2 * (1 - t) * t * ctrl.y + t * t * target.y)
            demoFinger = q
            extendRoute(to: q)
            await demoFrames(1)
        }
        drawingID = nil
    }

    private func demoFrames(_ n: Int) async {
        for _ in 0..<n {
            guard !Task.isCancelled else { return }
            step(1.0 / 60)
            try? await Task.sleep(for: .seconds(1.0 / 60))
        }
    }
}

// MARK: - Airfield (static background)

private struct FCAirfield: View, Equatable {
    let size: CGSize
    let zones: [FCZone]
    let unit: CGFloat

    static func == (a: FCAirfield, b: FCAirfield) -> Bool { a.size == b.size && a.unit == b.unit }

    var body: some View {
        Canvas { ctx, s in
            let u = unit
            // Grass with mowing stripes.
            ctx.fill(Path(CGRect(origin: .zero, size: s)), with: .color(Color(red: 0.42, green: 0.68, blue: 0.27)))
            let band = u * 0.11
            var x: CGFloat = -s.height
            var k = 0
            while x < s.width + s.height {
                var stripe = Path()
                stripe.move(to: CGPoint(x: x, y: 0))
                stripe.addLine(to: CGPoint(x: x + band, y: 0))
                stripe.addLine(to: CGPoint(x: x + band + s.height * 0.35, y: s.height))
                stripe.addLine(to: CGPoint(x: x + s.height * 0.35, y: s.height))
                stripe.closeSubpath()
                if k % 2 == 0 { ctx.fill(stripe, with: .color(Color(red: 0.47, green: 0.73, blue: 0.3))) }
                x += band
                k += 1
            }
            // Soft darker patches.
            for (i, f) in [(0.15, 0.2), (0.8, 0.12), (0.55, 0.48), (0.2, 0.88), (0.9, 0.6), (0.45, 0.95)].enumerated() {
                let c = CGPoint(x: f.0 * s.width, y: f.1 * s.height)
                let r = u * CGFloat(0.12 + Double(i % 3) * 0.04)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 0.7, width: r * 2, height: r * 1.4)),
                         with: .color(Color(red: 0.3, green: 0.55, blue: 0.2).opacity(0.18)))
            }

            for z in zones {
                if z.kind == 2 { helipad(ctx, z, u) } else { runway(ctx, z, u) }
            }

            // Trees along the margins.
            for (i, f) in [(0.05, 0.5), (0.93, 0.9), (0.08, 0.72), (0.95, 0.42), (0.5, 0.18), (0.18, 0.12), (0.62, 0.9)].enumerated() {
                tree(ctx, CGPoint(x: f.0 * s.width, y: f.1 * s.height), u * CGFloat(0.045 + Double(i % 3) * 0.012))
            }
        }
    }

    private func runway(_ ctx: GraphicsContext, _ z: FCZone, _ u: CGFloat) {
        var g = ctx
        g.translateBy(x: z.center.x * u, y: z.center.y * u)
        g.rotate(by: .radians(z.heading))
        let L = z.length * u, W = z.width * u
        let color = z.kind == 0 ? Color(red: 0.9, green: 0.2, blue: 0.18) : Color(red: 0.98, green: 0.8, blue: 0.16)
        // Shoulder + asphalt.
        g.fill(Path(roundedRect: CGRect(x: -L / 2 - W * 0.15, y: -W * 0.65, width: L + W * 0.3, height: W * 1.3), cornerRadius: W * 0.2),
               with: .color(Color(red: 0.75, green: 0.72, blue: 0.62)))
        g.fill(Path(CGRect(x: -L / 2, y: -W / 2, width: L, height: W)), with: .color(Color(red: 0.36, green: 0.37, blue: 0.4)))
        // Edge lines and dashed centre line.
        var edges = Path()
        edges.move(to: CGPoint(x: -L / 2, y: -W * 0.42)); edges.addLine(to: CGPoint(x: L / 2, y: -W * 0.42))
        edges.move(to: CGPoint(x: -L / 2, y: W * 0.42)); edges.addLine(to: CGPoint(x: L / 2, y: W * 0.42))
        g.stroke(edges, with: .color(.white.opacity(0.85)), lineWidth: max(1, W * 0.05))
        var centre = Path()
        centre.move(to: CGPoint(x: -L / 2 + W * 1.2, y: 0)); centre.addLine(to: CGPoint(x: L / 2 - W * 0.4, y: 0))
        g.stroke(centre, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: max(1, W * 0.06), dash: [W * 0.45, W * 0.35]))
        // Threshold "piano keys" at the landing end.
        for k in 0..<5 {
            let yy = -W * 0.34 + CGFloat(k) * W * 0.17
            g.fill(Path(CGRect(x: -L / 2 + W * 0.15, y: yy - W * 0.05, width: W * 0.6, height: W * 0.1)), with: .color(.white))
        }
        // Coloured approach chevrons pointing down the runway, before the threshold.
        for k in 0..<3 {
            let cx = -L / 2 - W * (0.55 + CGFloat(k) * 0.55)
            var ch = Path()
            ch.move(to: CGPoint(x: cx - W * 0.2, y: -W * 0.45))
            ch.addLine(to: CGPoint(x: cx + W * 0.2, y: 0))
            ch.addLine(to: CGPoint(x: cx - W * 0.2, y: W * 0.45))
            g.stroke(ch, with: .color(color.opacity(1 - Double(k) * 0.25)),
                     style: StrokeStyle(lineWidth: W * 0.16, lineCap: .round, lineJoin: .round))
        }
        // The landing zone disc at the entrance.
        let r = z.zoneRadius * u
        g.fill(Path(ellipseIn: CGRect(x: -L / 2 - r, y: -r, width: r * 2, height: r * 2)), with: .color(color.opacity(0.28)))
        g.stroke(Path(ellipseIn: CGRect(x: -L / 2 - r, y: -r, width: r * 2, height: r * 2)), with: .color(color.opacity(0.9)),
                 style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
    }

    private func helipad(_ ctx: GraphicsContext, _ z: FCZone, _ u: CGFloat) {
        let c = CGPoint(x: z.center.x * u, y: z.center.y * u)
        let r = z.width * u
        let blue = Color(red: 0.2, green: 0.5, blue: 0.95)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 1.25, y: c.y - r * 1.25, width: r * 2.5, height: r * 2.5)),
                 with: .color(Color(red: 0.75, green: 0.72, blue: 0.62)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(blue))
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * 0.82, y: c.y - r * 0.82, width: r * 1.64, height: r * 1.64)),
                   with: .color(.white), lineWidth: max(1.5, r * 0.08))
        let h = ctx.resolve(Text("H").font(.system(size: r * 1.05, weight: .black, design: .rounded)).foregroundStyle(.white))
        ctx.draw(h, at: c)
    }

    private func tree(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r + r * 0.35, y: c.y - r + r * 0.45, width: r * 2, height: r * 2)),
                 with: .color(.black.opacity(0.2)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                 with: .color(Color(red: 0.16, green: 0.45, blue: 0.18)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.75, y: c.y - r * 0.8, width: r * 1.2, height: r * 1.2)),
                 with: .color(Color(red: 0.28, green: 0.6, blue: 0.26)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.5, y: c.y - r * 0.6, width: r * 0.55, height: r * 0.55)),
                 with: .color(Color(red: 0.42, green: 0.72, blue: 0.34)))
    }
}

// MARK: - Aircraft art

private enum FCArt {
    /// Draws an aircraft pointing along `heading`. `altitude` 1…0 fades the ground shadow's offset.
    static func draw(_ kind: Int, in ctx: GraphicsContext, at c: CGPoint, heading: Double, length L: CGFloat,
                     altitude: Double, spin: Double, alpha: Double) {
        var g = ctx
        g.opacity = alpha
        // Ground shadow, offset down-right by altitude.
        var s = g
        s.translateBy(x: c.x + L * 0.22 * CGFloat(altitude), y: c.y + L * 0.3 * CGFloat(altitude))
        s.rotate(by: .radians(heading))
        s.opacity = alpha * 0.25
        silhouette(kind, s, L, color: .black, spin: spin)
        var b = g
        b.translateBy(x: c.x, y: c.y)
        b.rotate(by: .radians(heading))
        switch kind {
        case 0: jet(b, L)
        case 1: prop(b, L, spin: spin)
        default: heli(b, L, spin: spin)
        }
    }

    private static func silhouette(_ kind: Int, _ g: GraphicsContext, _ L: CGFloat, color: Color, spin: Double) {
        switch kind {
        case 0: g.fill(jetBody(L), with: .color(color)); g.fill(jetWings(L), with: .color(color))
        case 1: g.fill(propBody(L), with: .color(color)); g.fill(propWings(L), with: .color(color))
        default:
            g.fill(Path(ellipseIn: CGRect(x: -L * 0.12, y: -L * 0.14, width: L * 0.44, height: L * 0.28)), with: .color(color))
            g.fill(Path(ellipseIn: CGRect(x: -L * 0.55, y: -L * 0.55, width: L * 1.1, height: L * 1.1)), with: .color(color.opacity(0.25)))
        }
    }

    private static func jetBody(_ L: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: L * 0.52, y: 0))
        p.addQuadCurve(to: CGPoint(x: L * 0.3, y: -L * 0.075), control: CGPoint(x: L * 0.46, y: -L * 0.07))
        p.addLine(to: CGPoint(x: -L * 0.44, y: -L * 0.06))
        p.addQuadCurve(to: CGPoint(x: -L * 0.44, y: L * 0.06), control: CGPoint(x: -L * 0.52, y: 0))
        p.addLine(to: CGPoint(x: L * 0.3, y: L * 0.075))
        p.addQuadCurve(to: CGPoint(x: L * 0.52, y: 0), control: CGPoint(x: L * 0.46, y: L * 0.07))
        return p
    }

    private static func jetWings(_ L: CGFloat) -> Path {
        var p = Path()
        for s: CGFloat in [-1, 1] {
            p.move(to: CGPoint(x: L * 0.12, y: s * L * 0.06))
            p.addLine(to: CGPoint(x: -L * 0.16, y: s * L * 0.5))
            p.addLine(to: CGPoint(x: -L * 0.27, y: s * L * 0.5))
            p.addLine(to: CGPoint(x: -L * 0.12, y: s * L * 0.06))
            p.closeSubpath()
            p.move(to: CGPoint(x: -L * 0.33, y: s * L * 0.05))
            p.addLine(to: CGPoint(x: -L * 0.46, y: s * L * 0.2))
            p.addLine(to: CGPoint(x: -L * 0.52, y: s * L * 0.2))
            p.addLine(to: CGPoint(x: -L * 0.45, y: s * L * 0.05))
            p.closeSubpath()
        }
        return p
    }

    private static func jet(_ g: GraphicsContext, _ L: CGFloat) {
        let red = Color(red: 0.9, green: 0.2, blue: 0.18)
        let outline = Color(red: 0.35, green: 0.05, blue: 0.05)
        g.fill(jetWings(L), with: .color(red.shade(0.15)))
        g.stroke(jetWings(L), with: .color(outline), lineWidth: max(1, L * 0.025))
        // Engines under the wings.
        for s: CGFloat in [-1, 1] {
            g.fill(Path(roundedRect: CGRect(x: -L * 0.06, y: s * L * 0.24 - L * 0.035, width: L * 0.16, height: L * 0.07), cornerRadius: L * 0.03),
                   with: .color(Color(white: 0.85)))
        }
        g.fill(jetBody(L), with: .linearGradient(Gradient(colors: [red.lit(0.35), red, red.shade(0.2)]),
                                                 startPoint: CGPoint(x: 0, y: -L * 0.08), endPoint: CGPoint(x: 0, y: L * 0.08)))
        g.stroke(jetBody(L), with: .color(outline), lineWidth: max(1, L * 0.025))
        // White stripe + cockpit.
        g.fill(Path(CGRect(x: -L * 0.38, y: -L * 0.018, width: L * 0.7, height: L * 0.036)), with: .color(.white.opacity(0.75)))
        g.fill(Path(ellipseIn: CGRect(x: L * 0.33, y: -L * 0.045, width: L * 0.1, height: L * 0.09)),
               with: .color(Color(red: 0.12, green: 0.2, blue: 0.35)))
    }

    private static func propBody(_ L: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: L * 0.44, y: -L * 0.05))
        p.addQuadCurve(to: CGPoint(x: L * 0.44, y: L * 0.05), control: CGPoint(x: L * 0.52, y: 0))
        p.addLine(to: CGPoint(x: -L * 0.42, y: L * 0.025))
        p.addLine(to: CGPoint(x: -L * 0.42, y: -L * 0.025))
        p.closeSubpath()
        return p
    }

    private static func propWings(_ L: CGFloat) -> Path {
        var p = Path(roundedRect: CGRect(x: -L * 0.02, y: -L * 0.52, width: L * 0.17, height: L * 1.04), cornerRadius: L * 0.05)
        p.addPath(Path(roundedRect: CGRect(x: -L * 0.44, y: -L * 0.18, width: L * 0.1, height: L * 0.36), cornerRadius: L * 0.03))
        return p
    }

    private static func prop(_ g: GraphicsContext, _ L: CGFloat, spin: Double) {
        let yellow = Color(red: 0.98, green: 0.8, blue: 0.16)
        let outline = Color(red: 0.45, green: 0.3, blue: 0.02)
        g.fill(propWings(L), with: .color(yellow.shade(0.08)))
        g.stroke(propWings(L), with: .color(outline), lineWidth: max(1, L * 0.025))
        g.fill(propBody(L), with: .linearGradient(Gradient(colors: [yellow.lit(0.4), yellow, yellow.shade(0.2)]),
                                                  startPoint: CGPoint(x: 0, y: -L * 0.06), endPoint: CGPoint(x: 0, y: L * 0.06)))
        g.stroke(propBody(L), with: .color(outline), lineWidth: max(1, L * 0.025))
        g.fill(Path(ellipseIn: CGRect(x: L * 0.14, y: -L * 0.04, width: L * 0.14, height: L * 0.08)),
               with: .color(Color(red: 0.15, green: 0.25, blue: 0.4)))
        // Spinning propeller: a blur disc plus two blades.
        g.fill(Path(ellipseIn: CGRect(x: L * 0.49, y: -L * 0.2, width: L * 0.05, height: L * 0.4)), with: .color(.white.opacity(0.3)))
        var blades = Path()
        let a = CGFloat(sin(spin)) * L * 0.2
        blades.move(to: CGPoint(x: L * 0.515, y: -a)); blades.addLine(to: CGPoint(x: L * 0.515, y: a))
        g.stroke(blades, with: .color(Color(white: 0.2)), style: StrokeStyle(lineWidth: max(1.5, L * 0.035), lineCap: .round))
    }

    private static func heli(_ g: GraphicsContext, _ L: CGFloat, spin: Double) {
        let blue = Color(red: 0.2, green: 0.5, blue: 0.95)
        let outline = Color(red: 0.05, green: 0.15, blue: 0.4)
        // Skids.
        var skids = Path()
        for s: CGFloat in [-1, 1] {
            skids.move(to: CGPoint(x: -L * 0.12, y: s * L * 0.15)); skids.addLine(to: CGPoint(x: L * 0.3, y: s * L * 0.15))
        }
        g.stroke(skids, with: .color(Color(white: 0.25)), style: StrokeStyle(lineWidth: max(1, L * 0.03), lineCap: .round))
        // Tail boom + tail rotor.
        g.fill(Path(roundedRect: CGRect(x: -L * 0.52, y: -L * 0.03, width: L * 0.45, height: L * 0.06), cornerRadius: L * 0.03),
               with: .color(blue.shade(0.1)))
        var tail = Path()
        let ta = CGFloat(sin(spin * 1.7)) * L * 0.1
        tail.move(to: CGPoint(x: -L * 0.5, y: -ta)); tail.addLine(to: CGPoint(x: -L * 0.5, y: ta))
        g.stroke(tail, with: .color(Color(white: 0.2)), style: StrokeStyle(lineWidth: max(1, L * 0.025), lineCap: .round))
        // Cabin.
        let cabin = Path(ellipseIn: CGRect(x: -L * 0.14, y: -L * 0.15, width: L * 0.46, height: L * 0.3))
        g.fill(cabin, with: .linearGradient(Gradient(colors: [blue.lit(0.35), blue, blue.shade(0.2)]),
                                            startPoint: CGPoint(x: 0, y: -L * 0.15), endPoint: CGPoint(x: 0, y: L * 0.15)))
        g.stroke(cabin, with: .color(outline), lineWidth: max(1, L * 0.025))
        g.fill(Path(ellipseIn: CGRect(x: L * 0.14, y: -L * 0.1, width: L * 0.15, height: L * 0.2)),
               with: .color(Color(red: 0.7, green: 0.88, blue: 1).opacity(0.9)))
        // Main rotor: a blur disc and two long blades.
        g.fill(Path(ellipseIn: CGRect(x: L * 0.08 - L * 0.55, y: -L * 0.55, width: L * 1.1, height: L * 1.1)),
               with: .color(.white.opacity(0.12)))
        var rotor = Path()
        for k in 0..<2 {
            let a = spin + Double(k) * .pi / 2
            let dx = CGFloat(cos(a)) * L * 0.55, dy = CGFloat(sin(a)) * L * 0.55
            rotor.move(to: CGPoint(x: L * 0.08 - dx, y: -dy)); rotor.addLine(to: CGPoint(x: L * 0.08 + dx, y: dy))
        }
        g.stroke(rotor, with: .color(Color(white: 0.18)), style: StrokeStyle(lineWidth: max(1.5, L * 0.035), lineCap: .round))
        g.fill(Path(ellipseIn: CGRect(x: L * 0.08 - L * 0.04, y: -L * 0.04, width: L * 0.08, height: L * 0.08)), with: .color(Color(white: 0.15)))
    }
}
