//
//  ColorBumpGame.swift
//  A Banana Game
//
//  Reflex — a Color Bump 3D homage. The banana ball auto-rolls forward down a lane.
//  Coloured barriers slide toward you, each split into colour bands; you may only roll
//  through the band that matches the ball's CURRENT colour — steer onto a wrong colour
//  and you fail back to level 1. TAP the LEFT or RIGHT half of the screen to steer.
//  Colour GATES (full-width lines) repaint the ball, so every barrier must be re-read.
//  Reach the target distance to win. 7 levels: faster roll, denser barriers with more
//  (narrower) bands, and more frequent colour switches; the lane deepens in hue.
//
//  Drawn as Color Bump 3D: a pale track with coloured rails running into a gentle perspective over a
//  vivid backdrop, each barrier a row of 3D cubes in its band colours, the glossy ball with a white
//  trail, and paint gates as glowing arches with a swap sign (no "SWITCH" text). The perspective is
//  tuned so a row reaches the top edge at the same distance as the old flat view (dz ≈ 0.82) and
//  meets the ball exactly when `step()` judges it; the cubes of the band the ball rolled through
//  scatter. A progress bar replaces the "%" text, and a wrong colour bursts the ball.
//

import SwiftUI

enum ColorBumpGame {
    static let definition = GameDefinition(
        id: "color-bump",
        title: "Rainbow Roll",
        emoji: "🍌",
        genre: .reflex,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "The ball auto-rolls down the lane. Tap the left or right half to steer.",
                "Barriers split into color bands — only roll through the band matching your ball.",
                "Color gates repaint the ball, so re-read every barrier.",
                "Reach the target distance to win; a wrong color sends you back to level 1.",
            ],
            bulletsVI: [
                "Quả bóng tự lăn xuống làn. Chạm nửa trái hoặc phải để lái.",
                "Rào chắn chia thành các dải màu — chỉ lăn qua dải khớp màu bóng của bạn.",
                "Cổng đổi màu tô lại màu bóng, nên hãy đọc kỹ mỗi rào chắn.",
                "Đạt quãng đường mục tiêu để thắng; sai màu sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(ColorBumpView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct ColorBumpView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void
    @Environment(\.isDemo) private var isDemo

    private static let palette: [Color] = [
        Color(red: 0.95, green: 0.30, blue: 0.36),   // red
        Color(red: 0.30, green: 0.62, blue: 1.00),   // blue
        Color(red: 1.00, green: 0.82, blue: 0.25),   // banana
        Color(red: 0.40, green: 0.82, blue: 0.48)    // green
    ]

    // MARK: Difficulty
    private var rollSpeed: CGFloat  { [0.60, 0.70, 0.80, 0.92, 1.05, 1.20, 1.38][min(level, 7) - 1] }
    private var spacing: CGFloat    { [0.95, 0.85, 0.76, 0.68, 0.60, 0.54, 0.48][min(level, 7) - 1] }
    private var bands: Int          { [2, 2, 3, 3, 4, 4, 5][min(level, 7) - 1] }
    private var gateEvery: Int      { [5, 4, 4, 3, 3, 2, 2][min(level, 7) - 1] }
    private var targetDist: CGFloat { [4.5, 5.5, 6.5, 7.5, 8.5, 10, 12][min(level, 7) - 1] }
    private var colorsUsed: [Color] { Array(Self.palette.prefix(min(4, 2 + level / 2))) }

    private let laneLo: CGFloat = 0.14
    private let laneHi: CGFloat = 0.86
    private let ballScreenY: CGFloat = 0.74
    private let ballR: CGFloat = 0.05
    private let zScale: CGFloat = 0.9
    private let steerStep: CGFloat = 0.17

    // MARK: Model
    private struct Band { let lo: CGFloat; let hi: CGFloat; let color: Int }
    private enum RowKind { case barrier([Band]); case gate(Int) }
    private struct Row: Identifiable { let id = UUID(); let z: CGFloat; let kind: RowKind }

    @State private var rows: [Row] = []
    @State private var nextRow = 0
    @State private var distance: CGFloat = 0
    @State private var ballX: CGFloat = 0.5
    @State private var targetX: CGFloat = 0.5
    @State private var ballColorIndex = 0
    @State private var shakeTick = 0
    @State private var done = false
    @State private var loopTask: Task<Void, Never>?
    @State private var demoSide: CGFloat = 0     // demo: half being tapped (-1 left / 1 right / 0 none)
    @State private var demoTapID = 0             // demo: bumps per steer → a fresh DemoTapRipple

    // Presentation only: which band of each passed barrier the ball rolled through (its cubes
    // scatter), and where the ball burst.
    @State private var scattered: [UUID: Int] = [:]
    @State private var burst = false

    var body: some View {
        VStack(spacing: 4) {
            CBProgress(fraction: Double(min(distance, targetDist) / targetDist), color: swatch(ballColorIndex), scale: isDemo ? 0.7 : 1)
                .frame(height: isDemo ? 19 : 31)
                .padding(.top, isDemo ? 6 : 0)

            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height

                ZStack {
                    // Track, rows of cubes, gates, trail and ball: one Canvas (the card's backdrop shows around it).
                    Canvas { ctx, size in drawCourse(ctx, size: size) }

                    if burst {
                        CBBurst(color: swatch(ballColorIndex), size: ballR * 2 * h)
                            .position(x: ballX * w, y: ballScreenY * h)
                            .allowsHitTesting(false)
                    }

                    Color.clear.contentShape(Rectangle())
                        .onTapGesture(coordinateSpace: .local) { loc in
                            steer(loc.x < w / 2 ? -1 : 1)
                        }

                    // Demo: the tapped half tints, with a thumb and a ripple on it (ink: the track is white).
                    if isDemo && demoSide != 0 {
                        Rectangle().fill(Color(red: 0.2, green: 0.1, blue: 0.3).opacity(0.1))
                            .frame(width: w / 2, height: h)
                            .position(x: demoSide < 0 ? w * 0.25 : w * 0.75, y: h / 2)
                            .allowsHitTesting(false)
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color(red: 0.16, green: 0.1, blue: 0.24))
                            .shadow(color: .white.opacity(0.8), radius: 2)
                            .position(x: (demoSide < 0 ? w * 0.25 : w * 0.75) + 10, y: h * 0.9 + 14)
                            .allowsHitTesting(false)
                    }
                    if isDemo && demoTapID > 0 {
                        DemoTapRipple().id(demoTapID)
                            .position(x: demoSide < 0 ? w * 0.25 : w * 0.75, y: h * 0.9)
                    }
                }
                .frame(width: w, height: h)
                .clipped()
                .screenShake(shakeTick, amount: 7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CBBackdrop(level: level).equatable())
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
        // Each row `step()` has just judged: remember the band the ball went through (its cubes scatter).
        .onChange(of: nextRow) { old, new in
            guard new > old else { if new == 0 { scattered = [:] }; return }
            for i in old..<min(new, rows.count) {
                if case .barrier(let segs) = rows[i].kind {
                    scattered[rows[i].id] = segs.firstIndex(where: { ballX >= $0.lo && ballX < $0.hi }) ?? (segs.count - 1)
                }
            }
        }
        .onChange(of: done) { _, isDone in burst = isDone && distance < targetDist }
    }

    /// Perspective: 1 at the ball, shrinking with distance ahead; tuned so dz ≈ 0.82 is the top edge
    /// (where the old flat view showed rows appearing).
    private func depthScale(_ dz: CGFloat) -> CGFloat { 1.2 / (1.2 + max(-0.6, dz)) }
    private func rowY(_ dz: CGFloat, _ h: CGFloat) -> CGFloat {
        let horizon = -1.083 * h
        return horizon + (ballScreenY * h - horizon) * depthScale(dz)
    }
    private func laneX(_ frac: CGFloat, _ dz: CGFloat, _ w: CGFloat) -> CGFloat {
        w / 2 + (frac * w - w / 2) * depthScale(dz)
    }

    private func drawCourse(_ ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        CBArt.track(ctx, size: size, lo: laneLo, hi: laneHi, distance: distance, x: { laneX($0, $1, w) }, y: { rowY($0, h) })

        // Far rows first so nearer ones overlap them.
        for row in rows.reversed() {
            let dz = row.z - distance
            guard dz > -0.35 && dz < 0.9 else { continue }
            switch row.kind {
            case .gate(let c):
                CBArt.gate(ctx, color: swatch(c), lo: laneLo, hi: laneHi, dz: dz, x: { laneX($0, $1, w) }, y: { rowY($0, h) }, h: h)
            case .barrier(let segs):
                let through = scattered[row.id]
                for (bi, b) in segs.enumerated() {
                    CBArt.cubes(ctx, color: swatch(b.color), lo: b.lo, hi: b.hi, dz: dz, scatter: through == bi ? max(0, -dz) : 0,
                                ballX: ballX, x: { laneX($0, $1, w) }, y: { rowY($0, h) }, h: h)
                }
            }
        }

        if !burst {
            CBArt.ball(ctx, at: CGPoint(x: ballX * w, y: ballScreenY * h), radius: ballR * h, color: swatch(ballColorIndex),
                       roll: Double(distance), size: size)
        }
    }

    /// Render-time color lookup. Indexes the full 4-colour `palette` (clamped) rather than the
    /// level-truncated `colorsUsed`. During a fail→reset transition SwiftUI can briefly render a
    /// row whose colour index was built for a higher level (more colours) against a `colorsUsed`
    /// that has already shrunk to the new level's size — indexing `colorsUsed` there crashed with
    /// "Index out of range". Every index is a valid `palette` index by construction, so this is safe.
    private func swatch(_ i: Int) -> Color {
        Self.palette[max(0, min(i, Self.palette.count - 1))]
    }

    // MARK: Input
    private func steer(_ d: CGFloat) {
        guard !done else { return }
        targetX = min(laneHi - ballR, max(laneLo + ballR, targetX + d * steerStep))
        SoundManager.shared.tap(); Haptics.tap()
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
        distance = 0; ballX = 0.5; targetX = 0.5; done = false; nextRow = 0; shakeTick = 0
        ballColorIndex = 0
        var built: [Row] = []
        var z: CGFloat = 1.3
        var current = Int.random(in: 0..<colorsUsed.count)
        ballColorIndex = current
        let count = 5 + level * 2
        for i in 0..<count {
            if i > 0 && i % gateEvery == 0 {
                // Colour gate — repaint to a new colour.
                let newC = (0..<colorsUsed.count).filter { $0 != current }.randomElement() ?? current
                current = newC
                built.append(Row(z: z, kind: .gate(newC)))
                // Give a full barrier's worth of room after a recolour so the player
                // can actually re-steer to the new matching band (a 0.7 gap was
                // unreactable at speed and read as the switch "failing" you).
                z += spacing * 1.5
            }
            built.append(Row(z: z, kind: .barrier(makeBarrier(matching: current))))
            z += spacing
        }
        rows = built
    }

    /// Full-width barrier of `bands` colour segments; guarantees one matches `matching`.
    private func makeBarrier(matching: Int) -> [Band] {
        let n = bands
        var colors = (0..<n).map { _ in Int.random(in: 0..<colorsUsed.count) }
        if !colors.contains(matching) { colors[Int.random(in: 0..<n)] = matching }
        let width = (laneHi - laneLo) / CGFloat(n)
        return (0..<n).map { i in
            Band(lo: laneLo + CGFloat(i) * width, hi: laneLo + CGFloat(i + 1) * width, color: colors[i])
        }
    }

    private func step(dt: CGFloat) {
        guard !done else { return }
        distance += rollSpeed * dt
        ballX += (targetX - ballX) * min(1, 18 * dt)

        // Evaluate each row exactly as the ball reaches it.
        while nextRow < rows.count && distance >= rows[nextRow].z {
            let row = rows[nextRow]
            nextRow += 1
            switch row.kind {
            case .gate(let c):
                ballColorIndex = c
                SoundManager.shared.tap(); Haptics.tap()
            case .barrier(let segs):
                if let b = segs.first(where: { ballX >= $0.lo && ballX < $0.hi }) ?? segs.last {
                    if b.color != ballColorIndex { shakeTick += 1; fail(); return }
                }
            }
        }

        if distance >= targetDist { win(); return }
    }

    // MARK: - Demo (live manual clip)
    // Level 1 (two colours, two-band barriers every 0.95, no SWITCH gate before the 4.5 finish) on a
    // fixed layout whose matching band alternates sides, stepped at a fixed 1/60s through the real
    // `steer`/`step`. Joins the run just before the first barrier; the autopilot taps a half (twice
    // to cross the centre line) when the next barrier is 0.55 out, so the ball is settled in its
    // band well before contact. Reaching 4.5 is the real win().
    private static let demoLayout: [[Int]] = [[1, 0], [0, 1], [1, 0], [0, 1], [1, 0]]  // left, right

    private func demoSetup() {
        distance = 0.45; ballX = 0.5; targetX = 0.5; done = false; nextRow = 0; shakeTick = 0
        ballColorIndex = 0
        var built: [Row] = []
        var z: CGFloat = 1.3
        let width = (laneHi - laneLo) / 2
        for pair in Self.demoLayout {
            let bands = pair.enumerated().map { i, c in
                Band(lo: laneLo + CGFloat(i) * width, hi: laneLo + CGFloat(i + 1) * width, color: c)
            }
            built.append(Row(z: z, kind: .barrier(bands)))
            z += spacing
        }
        rows = built
    }

    private func runDemo() async {
        let dt: CGFloat = 1.0 / 60.0
        while !Task.isCancelled {
            demoSetup()
            demoSide = 0
            var steeredFor = -1
            var pending: [(frame: Int, side: CGFloat)] = []
            var releaseAt = 0
            var frame = 0
            while !Task.isCancelled && !done && frame < 900 {
                frame += 1
                // Plan the taps for the next barrier once it's 0.55 out.
                if nextRow < rows.count, steeredFor < nextRow, rows[nextRow].z - distance < 0.55,
                   case .barrier(let segs) = rows[nextRow].kind,
                   let band = segs.first(where: { $0.color == ballColorIndex }) {
                    steeredFor = nextRow
                    let goal = (band.lo + band.hi) / 2
                    let side: CGFloat = goal < targetX ? -1 : 1
                    let taps = Int((abs(goal - targetX) / steerStep).rounded())
                    for k in 0..<taps { pending.append((frame + k * 11, side)) }
                }
                if let p = pending.first, p.frame <= frame {
                    pending.removeFirst()
                    demoSide = p.side
                    steer(p.side)
                    demoTapID += 1
                    releaseAt = frame + 16
                }
                if demoSide != 0 && frame >= releaseAt { demoSide = 0 }
                step(dt: dt)
                try? await Task.sleep(for: .seconds(0.016))
            }
            // 100% → the real win() ran (onWin is a no-op). Hold, then loop.
            demoSide = 0
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    private func win() {
        guard !done else { return }
        done = true; loopTask?.cancel(); onWin()
    }
    private func fail() {
        guard !done else { return }
        done = true; loopTask?.cancel(); SoundManager.shared.error(); onFail()
    }
}

// MARK: - Color Bump 3D art

private enum CBArt {
    typealias XMap = (CGFloat, CGFloat) -> CGFloat   // (lane fraction, dz) → screen x
    typealias YMap = (CGFloat) -> CGFloat            // dz → screen y

    private static func quad(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Path {
        var p = Path()
        p.move(to: a); p.addLine(to: b); p.addLine(to: c); p.addLine(to: d)
        p.closeSubpath()
        return p
    }

    /// The pale track in perspective, its rails, and stripes that stream toward the ball.
    static func track(_ ctx: GraphicsContext, size: CGSize, lo: CGFloat, hi: CGFloat, distance: CGFloat, x: XMap, y: YMap) {
        let near: CGFloat = -0.6, far: CGFloat = 0.9
        let lane = quad(CGPoint(x: x(lo, far), y: y(far)), CGPoint(x: x(hi, far), y: y(far)),
                        CGPoint(x: x(hi, near), y: y(near)), CGPoint(x: x(lo, near), y: y(near)))
        ctx.fill(lane, with: .linearGradient(Gradient(colors: [Color(red: 0.84, green: 0.86, blue: 0.9), Color(red: 0.97, green: 0.97, blue: 0.99)]),
                                             startPoint: CGPoint(x: 0, y: y(far)), endPoint: CGPoint(x: 0, y: y(0))))
        var stripes = Path()
        let gap: CGFloat = 0.3
        var z = (distance / gap).rounded(.up) * gap - distance
        while z < far {
            if z > near {
                stripes.addPath(quad(CGPoint(x: x(lo, z), y: y(z)), CGPoint(x: x(hi, z), y: y(z)),
                                     CGPoint(x: x(hi, z - 0.02), y: y(z - 0.02)), CGPoint(x: x(lo, z - 0.02), y: y(z - 0.02))))
            }
            z += gap
        }
        ctx.fill(stripes, with: .color(.black.opacity(0.05)))
        for (a, b) in [(lo - 0.03, lo), (hi, hi + 0.03)] {
            let rail = quad(CGPoint(x: x(a, far), y: y(far)), CGPoint(x: x(b, far), y: y(far)),
                            CGPoint(x: x(b, near), y: y(near)), CGPoint(x: x(a, near), y: y(near)))
            ctx.fill(rail, with: .color(.white))
            ctx.stroke(rail, with: .color(.black.opacity(0.18)), lineWidth: 1)
        }
    }

    /// One band of a barrier as a row of cubes. `scatter` (world units since the ball passed) sends
    /// the cubes of the band it rolled through tumbling aside.
    static func cubes(_ ctx: GraphicsContext, color: Color, lo: CGFloat, hi: CGFloat, dz: CGFloat, scatter: CGFloat,
                      ballX: CGFloat, x: XMap, y: YMap, h: CGFloat) {
        let n = max(1, Int(((hi - lo) / 0.085).rounded()))
        let cw = (hi - lo) / CGFloat(n)
        let depth: CGFloat = 0.05, height = h * 0.045
        let fade = scatter > 0 ? max(0, 1 - Double(scatter) / 0.45) : 1
        guard fade > 0 else { return }
        var g = ctx
        g.opacity = fade
        for i in 0..<n {
            var x0 = lo + CGFloat(i) * cw + 0.006, x1 = lo + CGFloat(i + 1) * cw - 0.006
            var z0 = dz
            var lift: CGFloat = 0
            if scatter > 0 {
                let mid = (x0 + x1) / 2
                let push = (mid < ballX ? -1 : 1) * scatter * (0.9 + CGFloat(i % 3) * 0.3)
                x0 += push; x1 += push
                z0 = dz + scatter * 0.6
                lift = CGFloat(sin(Double(min(3.14, scatter * 7)))) * height * 1.4
            }
            let z1 = z0 + depth
            let kf = y(z0), kb = y(z1)
            let sF = (x(x1, z0) - x(x0, z0)) / max(0.0001, (x1 - x0)) , sB = (x(x1, z1) - x(x0, z1)) / max(0.0001, (x1 - x0))
            let hF = height * sF / max(1, (x(1, 0) - x(0, 0))), hB = height * sB / max(1, (x(1, 0) - x(0, 0)))
            let fl = CGPoint(x: x(x0, z0), y: kf - lift), fr = CGPoint(x: x(x1, z0), y: kf - lift)
            let bl = CGPoint(x: x(x0, z1), y: kb - lift), br = CGPoint(x: x(x1, z1), y: kb - lift)
            let ftl = CGPoint(x: fl.x, y: fl.y - hF), ftr = CGPoint(x: fr.x, y: fr.y - hF)
            let btl = CGPoint(x: bl.x, y: bl.y - hB), btr = CGPoint(x: br.x, y: br.y - hB)
            // The inner side (facing the centre line) shows in perspective.
            if (x0 + x1) / 2 < 0.5 {
                g.fill(quad(ftr, btr, br, fr), with: .color(color.shade(0.32)))
            } else {
                g.fill(quad(ftl, btl, bl, fl), with: .color(color.shade(0.32)))
            }
            g.fill(quad(btl, btr, ftr, ftl), with: .color(color.lit(0.32)))
            g.fill(quad(ftl, ftr, fr, fl), with: .linearGradient(Gradient(colors: [color, color.shade(0.18)]),
                                                                 startPoint: CGPoint(x: 0, y: ftl.y), endPoint: CGPoint(x: 0, y: fl.y)))
        }
    }

    /// A paint gate: a glowing strip across the track, two posts and a bar with a swap sign.
    static func gate(_ ctx: GraphicsContext, color: Color, lo: CGFloat, hi: CGFloat, dz: CGFloat, x: XMap, y: YMap, h: CGFloat) {
        let strip = quad(CGPoint(x: x(lo, dz + 0.02), y: y(dz + 0.02)), CGPoint(x: x(hi, dz + 0.02), y: y(dz + 0.02)),
                         CGPoint(x: x(hi, dz - 0.02), y: y(dz - 0.02)), CGPoint(x: x(lo, dz - 0.02), y: y(dz - 0.02)))
        ctx.fill(strip, with: .color(color.opacity(0.9)))
        let k = (x(1, dz) - x(0, dz)) / max(1, x(1, 0) - x(0, 0))
        let postH = h * 0.14 * k, postW = max(3, 8 * k)
        let yb = y(dz)
        for fx in [lo, hi] {
            let px = x(fx, dz)
            ctx.fill(Path(roundedRect: CGRect(x: px - postW / 2, y: yb - postH, width: postW, height: postH), cornerRadius: postW / 2),
                     with: .color(color))
        }
        let bar = CGRect(x: x(lo, dz) - postW / 2, y: yb - postH - postW, width: x(hi, dz) - x(lo, dz) + postW, height: postW * 1.4)
        ctx.fill(Path(roundedRect: bar, cornerRadius: postW * 0.7), with: .color(color))
        ctx.fill(Path(roundedRect: bar.insetBy(dx: postW * 0.6, dy: bar.height * 0.3).offsetBy(dx: 0, dy: -bar.height * 0.12),
                      cornerRadius: postW * 0.3), with: .color(.white.opacity(0.45)))
        var sign = ctx.resolve(Image(systemName: "arrow.triangle.2.circlepath"))
        sign.shading = .color(.white)
        let s = max(10, 26 * k)
        let mid = CGPoint(x: (x(lo, dz) + x(hi, dz)) / 2, y: yb - postH * 0.55)
        ctx.fill(Path(ellipseIn: CGRect(x: mid.x - s * 0.8, y: mid.y - s * 0.8, width: s * 1.6, height: s * 1.6)), with: .color(color))
        ctx.draw(sign, in: CGRect(x: mid.x - s / 2, y: mid.y - s / 2, width: s, height: s))
    }

    /// The glossy ball with its shadow and white trail.
    static func ball(_ ctx: GraphicsContext, at c: CGPoint, radius r: CGFloat, color: Color, roll: Double, size: CGSize) {
        var trail = Path()
        trail.move(to: CGPoint(x: c.x - r * 0.55, y: c.y + r * 0.4))
        trail.addLine(to: CGPoint(x: c.x + r * 0.55, y: c.y + r * 0.4))
        trail.addLine(to: CGPoint(x: c.x + r * 0.15, y: size.height))
        trail.addLine(to: CGPoint(x: c.x - r * 0.15, y: size.height))
        trail.closeSubpath()
        ctx.fill(trail, with: .linearGradient(Gradient(colors: [.white.opacity(0.9), .white.opacity(0)]),
                                              startPoint: c, endPoint: CGPoint(x: c.x, y: size.height)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.9, y: c.y + r * 0.62, width: r * 1.8, height: r * 0.55)), with: .color(.black.opacity(0.22)))
        let body = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.fill(body, with: .radialGradient(Gradient(colors: [color.lit(0.55), color, color.shade(0.35)]),
                                             center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4), startRadius: 0, endRadius: r * 1.5))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.55, y: c.y - r * 0.62, width: r * 0.42, height: r * 0.3)), with: .color(.white.opacity(0.85)))
    }
}

/// Color Bump's progress bar: filled in the ball's colour between a start dot and a goal ring.
private struct CBProgress: View {
    let fraction: Double
    let color: Color
    let scale: CGFloat

    var body: some View {
        let barW: CGFloat = 190 * scale
        HStack(spacing: 6 * scale) {
            Circle().fill(color).overlay(Circle().stroke(.white, lineWidth: 2 * scale)).frame(width: 16 * scale, height: 16 * scale)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3))
                Capsule().fill(color).frame(width: barW * max(0, min(1, fraction)))
                Capsule().stroke(.white, lineWidth: 2 * scale)
            }
            .frame(width: barW, height: 10 * scale)
            Circle().stroke(.white, lineWidth: 2 * scale).frame(width: 16 * scale, height: 16 * scale)
        }
    }
}

/// A vivid backdrop per level, like the game's changing worlds (space by level 7).
private struct CBBackdrop: View, Equatable {
    let level: Int

    var body: some View {
        let pairs: [[Color]] = [
            [Color(red: 0.98, green: 0.36, blue: 0.62), Color(red: 0.66, green: 0.16, blue: 0.62)],
            [Color(red: 0.2, green: 0.78, blue: 0.9), Color(red: 0.12, green: 0.42, blue: 0.82)],
            [Color(red: 1.0, green: 0.56, blue: 0.24), Color(red: 0.9, green: 0.26, blue: 0.22)],
            [Color(red: 0.62, green: 0.42, blue: 0.98), Color(red: 0.34, green: 0.18, blue: 0.7)],
            [Color(red: 0.2, green: 0.82, blue: 0.62), Color(red: 0.08, green: 0.46, blue: 0.5)],
            [Color(red: 0.92, green: 0.22, blue: 0.3), Color(red: 0.46, green: 0.06, blue: 0.2)],
            [Color(red: 0.12, green: 0.1, blue: 0.3), Color(red: 0.02, green: 0.02, blue: 0.08)],
        ]
        ZStack {
            LinearGradient(colors: pairs[min(max(level, 1), 7) - 1], startPoint: .top, endPoint: .bottom)
            if level >= 7 { Starfield(count: 50).opacity(0.8) }
        }
    }
}

/// The ball bursting into shards (once).
private struct CBBurst: View {
    let color: Color
    let size: CGFloat
    @State private var go = false

    var body: some View {
        ZStack {
            ForEach(0..<16, id: \.self) { i in
                let a: Double = Double(i) / 16 * 2 * .pi
                let d: CGFloat = size * (1.3 + 0.5 * CGFloat(i % 3))
                let s: CGFloat = size * (0.22 + 0.06 * CGFloat(i % 3))
                let dx: CGFloat = go ? CGFloat(cos(a)) * d : 0
                let dy: CGFloat = go ? CGFloat(sin(a)) * d : 0
                RoundedRectangle(cornerRadius: s * 0.2)
                    .fill(color)
                    .frame(width: s, height: s)
                    .rotationEffect(.degrees(go ? Double(i * 40) : 0))
                    .offset(x: dx, y: dy)
                    .opacity(go ? 0 : 1)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.6)) { go = true } }
    }
}
