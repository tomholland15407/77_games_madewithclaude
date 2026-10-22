//
//  GeometryDashGame.swift
//  A Banana Game
//
//  Reflex — a rhythm auto-runner. A banana cube races right at a fixed pace; the world
//  scrolls at you. TAP to jump the spikes on the beat. Coloured PORTALS flip you into
//  a "flight" section where you HOLD to thrust up and thread the moving gaps, then a
//  portal flips you back to the cube. Precise timing is everything — one touch on a
//  spike, a gap wall, or (in flight) the ceiling/floor fails you back to level 1.
//  Reach the end of the track to win. 7 levels: faster track, tighter spike clusters,
//  narrower flight gaps, more flight sections; the world shifts neon-cool as you climb.
//
//  Drawn as Geometry Dash: a saturated per-level colour with big faint background squares, ground
//  tiles under a glowing line, black spikes and block pillars with white outlines, pink and green
//  portals, and a banana-yellow cube with GD's face that spins while it's airborne and snaps to
//  the nearest quarter turn when it lands (flight zones swap it for the GD ship with a streak).
//  The ground is drawn where the cube really runs (floorY + hs); spikes are centred on their
//  collision span and reach the lethal height; the thorns in flight zones end at the ship's lethal
//  floor line. GD's progress bar sits in the ceiling, and a crash bursts the cube.
//

import SwiftUI

enum GeometryDashGame {
    static let definition = GameDefinition(
        id: "geometry-dash",
        title: "Square Sprint",
        emoji: "🍌",
        genre: .reflex,
        levelCount: 7,
        // Hold-to-fly needs a full-screen press gesture, which would otherwise swallow the
        // feed's vertical swipe. Lock the pager while playing and show the skip button instead.
        locksFeed: true,
        manual: GameManual(
            bullets: [
                "The cube auto-runs to the right. Tap to jump the spikes on the beat.",
                "Coloured portals flip you into flight sections — hold to thrust up and thread the gaps.",
                "A portal flips you back to the cube; reach the end of the track to win.",
                "One touch on a spike, a gap wall, or a ceiling/floor in flight sends you to level 1.",
            ],
            bulletsVI: [
                "Khối lập phương tự chạy sang phải. Chạm để nhảy qua gai theo nhịp.",
                "Cổng màu chuyển bạn sang đoạn bay — giữ để đẩy lên và luồn qua các khe di động.",
                "Một cổng đưa bạn về lại khối lập phương; đến cuối đường đua để thắng.",
                "Chạm gai, tường khe, hay trần/sàn khi bay sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(GeometryDashView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct GeometryDashView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    // MARK: Difficulty
    private var scrollSpeed: CGFloat { [0.55, 0.62, 0.70, 0.78, 0.87, 0.97, 1.08][min(level, 7) - 1] }
    private var beatGap: CGFloat     { [0.62, 0.56, 0.50, 0.45, 0.41, 0.37, 0.34][min(level, 7) - 1] }
    private var maxCluster: Int      { 1 }   // always single spikes — clusters were too harsh
    private var shipSegments: Int    { [0, 1, 1, 2, 2, 3, 3][min(level, 7) - 1] }
    private var shipGapHalf: CGFloat { [0.26, 0.24, 0.22, 0.20, 0.18, 0.16, 0.14][min(level, 7) - 1] }
    private var shipBarGap: CGFloat  { [0.75, 0.70, 0.64, 0.58, 0.52, 0.47, 0.42][min(level, 7) - 1] }

    private let camX: CGFloat = 0.26
    private let viewSpan: CGFloat = 1.5
    private let floorY: CGFloat = 0.80
    private let ceilY: CGFloat = 0.12
    private let hs: CGFloat = 0.042           // cube half-size (screen fraction)
    private let hsWorld: CGFloat = 0.028      // cube half-size in worldX for overlap
    private let gravity: CGFloat = 7.0
    private let jumpV: CGFloat = 1.85
    private let shipThrust: CGFloat = 4.6
    private let shipGrav: CGFloat = 3.4
    private let shipMaxV: CGFloat = 1.0

    // MARK: Layout
    private enum ObKind { case spike, bar, portalToShip, portalToCube }
    private struct Ob: Identifiable {
        let id = UUID()
        let kind: ObKind
        let x: CGFloat           // worldX of the obstacle
        var w: CGFloat = 0       // width for spike clusters
        var gapCenter: CGFloat = 0   // for bars (flight gap center, screen fraction)
    }
    private struct ShipZone { let start: CGFloat; let end: CGFloat }

    @State private var obstacles: [Ob] = []
    @State private var shipZones: [ShipZone] = []
    @State private var trackEnd: CGFloat = 6
    @State private var distance: CGFloat = 0
    @State private var y: CGFloat = 0.80
    @State private var vy: CGFloat = 0
    @State private var grounded = true
    @State private var holding = false
    @State private var shakeTick = 0
    @State private var done = false
    @State private var loopTask: Task<Void, Never>?
    @State private var demoTapID = 0      // demo: bumps per jump → a fresh DemoTapRipple

    private var inShip: Bool { shipZones.contains { distance >= $0.start && distance < $0.end } }

    // Presentation only: the cube's settled quarter-turn, where it left the ground, where it crashed.
    @State private var spin: Double = 0
    @State private var takeoff: CGFloat = 0
    @State private var deathAt: CGPoint? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let pal = GDArt.palette(level)

            ZStack {
                // Background, ground, obstacles, portals and the icon: one Canvas.
                Canvas { ctx, size in drawTrack(ctx, size: size, palette: pal) }

                GDProgress(fraction: Double(min(distance, trackEnd) / trackEnd), scale: isDemo ? 0.72 : 1)
                    .position(x: w / 2, y: ceilY * h * 0.5)
                    .allowsHitTesting(false)

                Color.clear.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { _ in press() }
                        .onEnded { _ in holding = false })

                if let d = deathAt {
                    GDDeath(size: hs * 2 * h).position(x: d.x * w, y: d.y * h).allowsHitTesting(false)
                }

                // Demo: a ripple for each tap-to-jump.
                if isDemo && demoTapID > 0 {
                    DemoTapRipple().id(demoTapID).position(x: w * 0.7, y: h * 0.5)
                }
            }
            .frame(width: w, height: h)
            .clipped()
            .screenShake(shakeTick, amount: 7)
        }
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
        // The cube turns half a revolution per jump and settles on the nearest quarter turn.
        .onChange(of: grounded) { _, onGround in
            if onGround { spin = ((spin + airSpin) / 90).rounded() * 90 } else { takeoff = distance }
        }
        .onChange(of: done) { _, isDone in
            deathAt = isDone && distance < trackEnd ? CGPoint(x: camX, y: y) : nil
        }
    }

    /// Degrees turned since takeoff: 180° over one full jump at this level's scroll speed.
    private var airSpin: Double {
        let jumpSpan = Double(scrollSpeed * 2 * jumpV / gravity)
        return Double(distance - takeoff) * 180 / max(0.01, jumpSpan)
    }

    private func drawTrack(_ ctx: GraphicsContext, size: CGSize, palette pal: GDPalette) {
        let w = size.width, h = size.height
        let sx: (CGFloat) -> CGFloat = { wx in (camX + (wx - distance) / viewSpan) * w }
        let cube = hs * 2 * h
        let groundTop = (floorY + hs) * h         // where the resting cube's bottom is
        let scroll = distance / viewSpan * w

        GDArt.backdrop(ctx, size: size, palette: pal, scroll: scroll)
        GDArt.ground(ctx, size: size, top: groundTop, palette: pal, scroll: scroll)
        // Flight zones: thorns whose tips are the ship's lethal floor line (y + hs >= floorY).
        for z in shipZones {
            GDArt.thorns(ctx, from: sx(z.start), to: sx(z.end), tips: floorY * h, base: groundTop, width: w)
        }
        GDArt.ceiling(ctx, size: size, edge: ceilY * h, palette: pal)

        for ob in obstacles {
            let x = sx(ob.x)
            guard x > -90 && x < w + 90 else { continue }
            switch ob.kind {
            case .spike:
                // Centred on the span `step()` tests; the tip is the lethal height (+ a hair).
                GDArt.spike(ctx, midX: sx(ob.x + ob.w / 2), base: groundTop, apex: (floorY - 0.10) * h, halfWidth: cube * 0.48)
            case .bar:
                let half = 0.03 / viewSpan * w
                GDArt.pillar(ctx, midX: x, halfWidth: half, top: ceilY * h, bottom: (ob.gapCenter - shipGapHalf) * h)
                GDArt.pillar(ctx, midX: x, halfWidth: half, top: (ob.gapCenter + shipGapHalf) * h, bottom: groundTop)
            case .portalToShip, .portalToCube:
                GDArt.portal(ctx, midX: x, top: ceilY * h, bottom: floorY * h, ship: ob.kind == .portalToShip)
            }
        }
        let fx = sx(trackEnd)
        if fx > -40 && fx < w + 40 { GDArt.finish(ctx, x: fx, top: ceilY * h, bottom: groundTop) }

        guard deathAt == nil else { return }
        let p = CGPoint(x: camX * w, y: y * h)
        if inShip {
            GDArt.ship(ctx, at: p, size: cube, tilt: .degrees(Double(max(-40, min(40, vy * 40)))))
        } else {
            if grounded { GDArt.dust(ctx, behind: p, size: cube, ground: groundTop, scroll: distance) }
            GDArt.cube(ctx, at: p, size: cube, angle: .degrees(grounded ? spin : spin + airSpin))
        }
    }

    // MARK: Input
    private func press() {
        guard !done else { return }
        if inShip { holding = true }
        else if grounded {
            vy = -jumpV; grounded = false
            SoundManager.shared.tap(); Haptics.tap()
        }
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

    // MARK: - Demo (live manual clip)
    // The real Level-1 track (single spikes on a fixed beat — L1 has no randomness), played from
    // its closing stretch (the last five spikes + the finish line) so the clip stays short. The
    // real `step` runs at a fixed 1/60s; the finger taps (the real `press`) when the next spike
    // is 0.12 ahead — the middle of the safe jump window (0.09–0.16, checked offline) → win().
    private func runDemo() async {
        let dt: CGFloat = 1.0 / 60.0
        while !Task.isCancelled {
            setup()
            distance = trackEnd - 4.4
            try? await Task.sleep(for: .seconds(0.4))
            while !Task.isCancelled && !done {
                if grounded, let next = obstacles.filter({ $0.kind == .spike && $0.x - distance > -0.2 }).map(\.x).min(),
                   next - distance >= 0, next - distance <= 0.12 {
                    press(); demoTapID += 1
                }
                step(dt: dt)
                try? await Task.sleep(for: .seconds(0.016))
            }
            // Finish line crossed → the real win() ran (onWin is a no-op). Hold, then loop.
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    private func setup() {
        distance = 0; y = floorY; vy = 0; grounded = true; holding = false; done = false
        var obs: [Ob] = []
        var zones: [ShipZone] = []
        var x: CGFloat = 1.4                    // lead-in before first hazard
        var shipLeft = shipSegments
        // Alternate cube runs and (later) flight zones down the track.
        for seg in 0..<(3 + level) {
            let makeShip = shipLeft > 0 && seg % 2 == 1
            if makeShip {
                shipLeft -= 1
                let portalX = x
                obs.append(Ob(kind: .portalToShip, x: portalX))
                x += 0.75                                  // generous lead-in to climb into the lane
                var gc: CGFloat = (ceilY + floorY) / 2     // first gap is dead-centre
                let barCount = 2 + level / 3               // short, legible sections
                for _ in 0..<barCount {
                    obs.append(Ob(kind: .bar, x: x, gapCenter: gc))
                    // Each next gap is only a reachable step from the last → a readable path.
                    let lo = ceilY + shipGapHalf + 0.03
                    let hi = floorY - shipGapHalf - 0.03
                    gc = min(hi, max(lo, gc + CGFloat.random(in: -0.10...0.10)))
                    x += shipBarGap
                }
                let portalCubeX = x
                zones.append(ShipZone(start: portalX, end: portalCubeX))
                obs.append(Ob(kind: .portalToCube, x: portalCubeX))
                x += 0.6
            } else {
                let spikeRuns = 3 + level
                for _ in 0..<spikeRuns {
                    let cluster = Int.random(in: 1...maxCluster)
                    obs.append(Ob(kind: .spike, x: x, w: CGFloat(cluster) * 0.05))
                    x += beatGap
                }
            }
        }
        trackEnd = x + 1.0
        obstacles = obs
        shipZones = zones
    }

    private func step(dt: CGFloat) {
        guard !done else { return }
        distance += scrollSpeed * dt

        if inShip {
            vy += (holding ? -shipThrust : shipGrav) * dt
            vy = max(-shipMaxV, min(shipMaxV, vy))
            y += vy * dt
            grounded = false
            if y <= ceilY + hs || y >= floorY - hs { crash(); return }
        } else {
            vy += gravity * dt
            y += vy * dt
            if y >= floorY {                 // land on the ground
                y = floorY; vy = 0; grounded = true
            } else { grounded = false }
        }

        // Collisions with the obstacles near the player.
        for ob in obstacles where abs(ob.x - distance) < 0.5 {
            switch ob.kind {
            case .spike:
                let lo = ob.x - hsWorld, hi = ob.x + ob.w + hsWorld
                if distance > lo && distance < hi {
                    // Cleared only if the cube's bottom is above the spike tips.
                    if y + hs > floorY - 0.10 + 0.01 { crash(); return }
                }
            case .bar:
                if abs(ob.x - distance) < 0.02 + hsWorld {
                    if y - hs < ob.gapCenter - shipGapHalf || y + hs > ob.gapCenter + shipGapHalf { crash(); return }
                }
            default: break
            }
        }

        if distance >= trackEnd { win(); return }
    }

    private func win() {
        guard !done else { return }
        done = true; loopTask?.cancel(); onWin()
    }
    private func crash() { fail() }
    private func fail() {
        guard !done else { return }
        done = true; loopTask?.cancel()
        shakeTick += 1; SoundManager.shared.error(); onFail()
    }
}

// MARK: - Geometry Dash art

private struct GDPalette {
    let top: Color, bottom: Color, ground: Color
}

private enum GDArt {
    static let primary = Color(red: 1.0, green: 0.86, blue: 0.16)     // banana-yellow icon
    static let secondary = Color(red: 0.25, green: 0.95, blue: 1.0)   // GD's default cyan
    static let ink = Color(red: 0.02, green: 0.02, blue: 0.04)

    /// Stereo-Madness blue, then magenta, green, violet, orange, crimson and a dark finale.
    static func palette(_ level: Int) -> GDPalette {
        switch min(max(level, 1), 7) {
        case 1: return GDPalette(top: Color(red: 0.16, green: 0.42, blue: 1.0), bottom: Color(red: 0.05, green: 0.22, blue: 0.78), ground: Color(red: 0.03, green: 0.15, blue: 0.6))
        case 2: return GDPalette(top: Color(red: 0.86, green: 0.24, blue: 0.82), bottom: Color(red: 0.52, green: 0.08, blue: 0.56), ground: Color(red: 0.38, green: 0.04, blue: 0.44))
        case 3: return GDPalette(top: Color(red: 0.16, green: 0.72, blue: 0.38), bottom: Color(red: 0.05, green: 0.42, blue: 0.2), ground: Color(red: 0.03, green: 0.3, blue: 0.14))
        case 4: return GDPalette(top: Color(red: 0.52, green: 0.28, blue: 0.96), bottom: Color(red: 0.27, green: 0.1, blue: 0.62), ground: Color(red: 0.19, green: 0.06, blue: 0.48))
        case 5: return GDPalette(top: Color(red: 1.0, green: 0.46, blue: 0.14), bottom: Color(red: 0.72, green: 0.2, blue: 0.05), ground: Color(red: 0.5, green: 0.11, blue: 0.03))
        case 6: return GDPalette(top: Color(red: 0.86, green: 0.12, blue: 0.28), bottom: Color(red: 0.46, green: 0.03, blue: 0.13), ground: Color(red: 0.32, green: 0.02, blue: 0.08))
        default: return GDPalette(top: Color(red: 0.18, green: 0.15, blue: 0.36), bottom: Color(red: 0.07, green: 0.05, blue: 0.16), ground: Color(red: 0.04, green: 0.03, blue: 0.1))
        }
    }

    static func hash(_ n: Double) -> CGFloat {
        let v = sin(n * 12.9898) * 43758.5453
        return CGFloat(v - floor(v))
    }

    /// Sky gradient with big faint squares drifting at a fifth of the track speed.
    static func backdrop(_ ctx: GraphicsContext, size: CGSize, palette p: GDPalette, scroll: CGFloat) {
        let w = size.width, h = size.height
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [p.top, p.bottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        let tile = h * 0.22
        let off = (scroll * 0.2).truncatingRemainder(dividingBy: tile * 4)
        var light = Path(), dark = Path()
        var col = 0.0
        var x = -off - tile
        while x < w + tile {
            for row in 0..<5 {
                let k = col * 7 + Double(row) + floor(Double((scroll * 0.2) / (tile * 4))) * 29
                let r = hash(k)
                let rect = CGRect(x: x, y: CGFloat(row) * tile - tile * 0.3, width: tile * (r > 0.5 ? 2 : 1) - 3, height: tile - 3)
                if r < 0.3 { light.addRect(rect) } else if r > 0.75 { dark.addRect(rect) }
            }
            x += tile
            col += 1
        }
        ctx.fill(light, with: .color(.white.opacity(0.06)))
        ctx.fill(dark, with: .color(.black.opacity(0.08)))
    }

    /// Ground tiles scrolling with the track, under GD's glowing line.
    static func ground(_ ctx: GraphicsContext, size: CGSize, top: CGFloat, palette p: GDPalette, scroll: CGFloat) {
        let w = size.width, h = size.height
        ctx.fill(Path(CGRect(x: 0, y: top, width: w, height: h - top)),
                 with: .linearGradient(Gradient(colors: [p.ground, p.ground.mix(with: .black, by: 0.45)]),
                                       startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: h)))
        let tile = max(24, h * 0.1)
        var grid = Path()
        var x = -(scroll.truncatingRemainder(dividingBy: tile))
        while x < w { grid.move(to: CGPoint(x: x, y: top)); grid.addLine(to: CGPoint(x: x, y: h)); x += tile }
        var y = top + tile
        while y < h { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: w, y: y)); y += tile }
        ctx.stroke(grid, with: .color(.white.opacity(0.1)), lineWidth: 1.5)
        glowLine(ctx, y: top, width: w)
    }

    /// The ceiling band (its lower edge is the ship's lethal ceiling).
    static func ceiling(_ ctx: GraphicsContext, size: CGSize, edge: CGFloat, palette p: GDPalette) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: edge)),
                 with: .linearGradient(Gradient(colors: [p.ground.mix(with: .black, by: 0.45), p.ground]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: edge)))
        glowLine(ctx, y: edge, width: size.width)
    }

    /// GD's floor line: brightest in the middle, fading out toward both edges.
    static func glowLine(_ ctx: GraphicsContext, y: CGFloat, width w: CGFloat) {
        let fade = Gradient(stops: [.init(color: .white.opacity(0), location: 0), .init(color: .white, location: 0.5), .init(color: .white.opacity(0), location: 1)])
        ctx.fill(Path(CGRect(x: 0, y: y - 3, width: w, height: 6)),
                 with: .linearGradient(Gradient(stops: [.init(color: .white.opacity(0), location: 0), .init(color: .white.opacity(0.22), location: 0.5), .init(color: .white.opacity(0), location: 1)]),
                                       startPoint: .zero, endPoint: CGPoint(x: w, y: 0)))
        ctx.fill(Path(CGRect(x: 0, y: y - 1, width: w, height: 2)), with: .linearGradient(fade, startPoint: .zero, endPoint: CGPoint(x: w, y: 0)))
    }

    /// A black spike with a white glowing rim and a faint coloured core.
    static func spike(_ ctx: GraphicsContext, midX x: CGFloat, base: CGFloat, apex: CGFloat, halfWidth hw: CGFloat) {
        var tri = Path()
        tri.move(to: CGPoint(x: x, y: apex))
        tri.addLine(to: CGPoint(x: x + hw, y: base))
        tri.addLine(to: CGPoint(x: x - hw, y: base))
        tri.closeSubpath()
        ctx.stroke(tri, with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth: 6, lineJoin: .round))
        ctx.fill(tri, with: .linearGradient(Gradient(colors: [ink, ink, Color(white: 0.16)]),
                                            startPoint: CGPoint(x: x, y: apex), endPoint: CGPoint(x: x, y: base)))
        ctx.stroke(tri, with: .color(.white), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
    }

    /// Small ground thorns filling a flight zone; their tips are the lethal floor line.
    static func thorns(_ ctx: GraphicsContext, from x0: CGFloat, to x1: CGFloat, tips: CGFloat, base: CGFloat, width w: CGFloat) {
        let a = max(-20, x0), b = min(w + 20, x1)
        guard b > a else { return }
        let step = max(10, (base - tips) * 0.7)
        var path = Path()
        var x = x0 + step / 2
        while x < b {
            if x > a - step {
                path.move(to: CGPoint(x: x - step / 2, y: base))
                path.addLine(to: CGPoint(x: x, y: tips))
                path.addLine(to: CGPoint(x: x + step / 2, y: base))
                path.closeSubpath()
            }
            x += step
        }
        ctx.fill(path, with: .color(ink))
        ctx.stroke(path, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
    }

    /// A pillar of GD blocks: black, white-rimmed, with block seams.
    static func pillar(_ ctx: GraphicsContext, midX x: CGFloat, halfWidth hw: CGFloat, top: CGFloat, bottom: CGFloat) {
        guard bottom - top > 1 else { return }
        let r = CGRect(x: x - hw, y: top, width: hw * 2, height: bottom - top)
        ctx.fill(Path(r), with: .linearGradient(Gradient(colors: [Color(white: 0.02), Color(white: 0.12)]),
                                                startPoint: CGPoint(x: r.minX, y: 0), endPoint: CGPoint(x: r.maxX, y: 0)))
        var seams = Path()
        var y = top + hw * 2
        while y < bottom - 2 { seams.move(to: CGPoint(x: r.minX, y: y)); seams.addLine(to: CGPoint(x: r.maxX, y: y)); y += hw * 2 }
        ctx.stroke(seams, with: .color(.white.opacity(0.28)), lineWidth: 1)
        ctx.stroke(Path(r), with: .color(.white.opacity(0.25)), lineWidth: 5)
        ctx.stroke(Path(r), with: .color(.white), lineWidth: 1.8)
    }

    /// A GD portal: a tall oval ring, pink into the ship, green back to the cube.
    static func portal(_ ctx: GraphicsContext, midX x: CGFloat, top: CGFloat, bottom: CGFloat, ship: Bool) {
        let c1 = ship ? Color(red: 1, green: 0.45, blue: 0.85) : Color(red: 0.5, green: 1, blue: 0.45)
        let c2 = ship ? Color(red: 0.72, green: 0.1, blue: 0.82) : Color(red: 0.1, green: 0.66, blue: 0.2)
        let h = bottom - top
        let ring = CGRect(x: x - h * 0.09, y: top + h * 0.04, width: h * 0.18, height: h * 0.92)
        ctx.stroke(Path(ellipseIn: ring), with: .color(c1.opacity(0.3)), lineWidth: 14)
        ctx.fill(Path(ellipseIn: ring.insetBy(dx: 4, dy: 8)), with: .color(c2.opacity(0.25)))
        ctx.stroke(Path(ellipseIn: ring), with: .linearGradient(Gradient(colors: [c1, c2, c1]),
                                                                startPoint: CGPoint(x: 0, y: ring.minY), endPoint: CGPoint(x: 0, y: ring.maxY)), lineWidth: 6)
        ctx.stroke(Path(ellipseIn: ring.insetBy(dx: 5, dy: 10)), with: .color(.white.opacity(0.7)), lineWidth: 1.5)
        var dots = Path()
        for i in 0..<6 {
            let a = Double(i) / 6 * 2 * .pi
            let p = CGPoint(x: ring.midX + CGFloat(cos(a)) * ring.width * 0.72, y: ring.midY + CGFloat(sin(a)) * ring.height * 0.52)
            dots.addEllipse(in: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5))
        }
        ctx.fill(dots, with: .color(c1))
    }

    static func finish(_ ctx: GraphicsContext, x: CGFloat, top: CGFloat, bottom: CGFloat) {
        let sq: CGFloat = 8
        var black = Path(), white = Path()
        var y = top
        var row = 0
        while y < bottom {
            for col in 0..<2 {
                let r = CGRect(x: x - sq + CGFloat(col) * sq, y: y, width: sq, height: min(sq, bottom - y))
                if (row + col) % 2 == 0 { white.addRect(r) } else { black.addRect(r) }
            }
            y += sq
            row += 1
        }
        ctx.fill(Path(CGRect(x: x - sq - 4, y: top, width: sq * 2 + 8, height: bottom - top)), with: .color(.white.opacity(0.25)))
        ctx.fill(white, with: .color(.white))
        ctx.fill(black, with: .color(ink))
    }

    /// GD's default icon in banana yellow: a black-rimmed square, a cyan inset with square eyes and
    /// a mouth bar.
    static func cube(_ ctx: GraphicsContext, at c: CGPoint, size s: CGFloat, angle: Angle) {
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: angle)
        icon(g, size: s)
    }

    private static func icon(_ g: GraphicsContext, size s: CGFloat) {
        let outer = Path(roundedRect: CGRect(x: -s / 2, y: -s / 2, width: s, height: s), cornerRadius: s * 0.06)
        g.fill(outer, with: .linearGradient(Gradient(colors: [primary.mix(with: .white, by: 0.25), primary]),
                                            startPoint: CGPoint(x: 0, y: -s / 2), endPoint: CGPoint(x: 0, y: s / 2)))
        g.stroke(outer, with: .color(ink), lineWidth: s * 0.08)
        let inner = Path(CGRect(x: -s * 0.27, y: -s * 0.27, width: s * 0.54, height: s * 0.54))
        g.fill(inner, with: .color(secondary))
        g.stroke(inner, with: .color(ink), lineWidth: s * 0.06)
        g.fill(Path(CGRect(x: -s * 0.19, y: -s * 0.18, width: s * 0.12, height: s * 0.12)), with: .color(ink))
        g.fill(Path(CGRect(x: s * 0.07, y: -s * 0.18, width: s * 0.12, height: s * 0.12)), with: .color(ink))
        g.fill(Path(CGRect(x: -s * 0.19, y: s * 0.07, width: s * 0.38, height: s * 0.09)), with: .color(ink))
    }

    /// The GD ship: a hull with a tail fin, the mini icon riding on top, and a fading streak.
    static func ship(_ ctx: GraphicsContext, at c: CGPoint, size s: CGFloat, tilt: Angle) {
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: tilt)
        var streak = Path()
        streak.move(to: CGPoint(x: -s * 0.85, y: s * 0.18)); streak.addLine(to: CGPoint(x: -s * 2.6, y: s * 0.18))
        g.stroke(streak, with: .linearGradient(Gradient(colors: [secondary.opacity(0.8), secondary.opacity(0)]),
                                               startPoint: CGPoint(x: -s * 0.85, y: 0), endPoint: CGPoint(x: -s * 2.6, y: 0)),
                 style: StrokeStyle(lineWidth: s * 0.22, lineCap: .round))
        var mini = g
        mini.translateBy(x: -s * 0.08, y: -s * 0.2)
        icon(mini, size: s * 0.52)
        var hull = Path()
        hull.move(to: CGPoint(x: -s * 0.86, y: -s * 0.02))
        hull.addLine(to: CGPoint(x: s * 0.38, y: -s * 0.02))
        hull.addQuadCurve(to: CGPoint(x: s * 0.92, y: s * 0.2), control: CGPoint(x: s * 0.82, y: -s * 0.02))
        hull.addQuadCurve(to: CGPoint(x: s * 0.3, y: s * 0.44), control: CGPoint(x: s * 0.8, y: s * 0.44))
        hull.addLine(to: CGPoint(x: -s * 0.8, y: s * 0.44))
        hull.closeSubpath()
        g.fill(hull, with: .color(primary))
        g.stroke(hull, with: .color(ink), style: StrokeStyle(lineWidth: s * 0.07, lineJoin: .round))
        g.fill(Path(CGRect(x: -s * 0.66, y: s * 0.14, width: s * 1.18, height: s * 0.11)), with: .color(secondary))
        var fin = Path()
        fin.move(to: CGPoint(x: -s * 0.86, y: -s * 0.02))
        fin.addLine(to: CGPoint(x: -s * 0.96, y: -s * 0.36))
        fin.addLine(to: CGPoint(x: -s * 0.6, y: -s * 0.02))
        fin.closeSubpath()
        g.fill(fin, with: .color(secondary))
        g.stroke(fin, with: .color(ink), style: StrokeStyle(lineWidth: s * 0.06, lineJoin: .round))
    }

    /// Square dust kicked up behind the running cube.
    static func dust(_ ctx: GraphicsContext, behind c: CGPoint, size s: CGFloat, ground: CGFloat, scroll: CGFloat) {
        var p = Path()
        for i in 0..<5 {
            let f = (Double(scroll) * 6 + Double(i) * 0.2).truncatingRemainder(dividingBy: 1)
            let x = c.x - s * 0.5 - CGFloat(f) * s * 1.1
            let y = ground - 2 - CGFloat(f) * s * 0.35 - hash(Double(i) + 3) * 3
            let q = s * 0.1 * CGFloat(1 - f * 0.6)
            p.addRect(CGRect(x: x, y: y - q, width: q, height: q))
        }
        ctx.fill(p, with: .color(primary.opacity(0.75)))
    }
}

/// GD's progress bar and percentage, in the ceiling.
private struct GDProgress: View {
    let fraction: Double
    let scale: CGFloat

    var body: some View {
        let f = max(0, min(1, fraction))
        let barW: CGFloat = 170 * scale
        HStack(spacing: 8 * scale) {
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.35))
                Capsule().fill(LinearGradient(colors: [Color(red: 0.6, green: 1, blue: 0.45), Color(red: 0.3, green: 0.9, blue: 0.3)],
                                              startPoint: .top, endPoint: .bottom))
                    .frame(width: max(0, barW * f))
                Capsule().stroke(.white, lineWidth: 2)
            }
            .frame(width: barW, height: 11 * scale)
            ZStack {
                ForEach(0..<8, id: \.self) { i in
                    let a = Double(i) * .pi / 4
                    Text("\(Int(f * 100))%").font(.system(size: 18 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .offset(x: CGFloat(cos(a)) * 1.6, y: CGFloat(sin(a)) * 1.6)
                }
                Text("\(Int(f * 100))%").font(.system(size: 18 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .fixedSize()
            .frame(width: 52 * scale, alignment: .leading)
        }
    }
}

/// The crash: the icon bursts into squares inside an expanding white ring (once).
private struct GDDeath: View {
    let size: CGFloat
    @State private var go = false

    var body: some View {
        ZStack {
            Circle().stroke(.white, lineWidth: 3)
                .frame(width: size, height: size)
                .scaleEffect(go ? 3.4 : 0.3)
                .opacity(go ? 0 : 1)
            ForEach(0..<14, id: \.self) { i in
                let a = Double(i) / 14 * 2 * .pi + Double(i % 3) * 0.25
                let d = size * (1.1 + 0.25 * CGFloat(i % 4))
                Rectangle()
                    .fill(i % 3 == 0 ? GDArt.secondary : GDArt.primary)
                    .frame(width: size * 0.2, height: size * 0.2)
                    .rotationEffect(.degrees(go ? Double(i * 47) : 0))
                    .offset(x: go ? CGFloat(cos(a)) * d : 0, y: go ? CGFloat(sin(a)) * d : 0)
                    .opacity(go ? 0 : 1)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.65)) { go = true } }
    }
}
