//
//  QbertGame.swift
//  A Banana Game
//
//  Brain — hop the pyramid. Use the four diagonal buttons to bounce from cube to cube; each
//  landing flips a cube's top toward the target colour. Light up every cube to win. Hop off
//  the edge into the void, get landed on by the bouncing hunter, or let the clock expire and
//  you fall back to level 1. 7 levels: taller pyramids, cubes that need two hops to set, a
//  faster hunter and a tighter clock — level 7 is a frantic scramble. The cube palette shifts
//  each level.
//
//  Drawn as Gottlieb's 1982 Q*bert: a black void, tri-coloured cubes (top, and a light and a dark
//  side, a new scheme each level), an orange Q*bert with his tube snout who arcs from cube to cube
//  and faces his hop, a purple coiled Coily who hops too, the "change to" sample (the target colour
//  between two arrows), and his @!#?@! balloon when a round is lost — a hop into the void shows him
//  jumping off and falling. The cubes keep the old IsoCube geometry, drawn in one Canvas.
//

import SwiftUI

enum QbertGame {
    static let definition = GameDefinition(
        id: "qbert",
        title: "Pyramid Hop",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Use the four diagonal buttons to hop from cube to cube.",
                "Each landing flips a cube's top toward the target color.",
                "Light up every cube to win.",
                "Hop into the void, get caught by the bouncing hunter, or time out, and you're back to level 1.",
            ],
            bulletsVI: [
                "Dùng bốn nút chéo để nhảy từ khối này sang khối khác.",
                "Mỗi lần đáp sẽ đổi mặt trên của khối tiến về màu mục tiêu.",
                "Thắp sáng mọi khối để thắng.",
                "Nhảy ra khoảng không, bị kẻ săn nảy bắt, hoặc hết giờ, sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(QbertView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct QbertView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void
    @Environment(\.isDemo) private var isDemo

    private var rowsN: Int         { [4, 4, 5, 5, 6, 6, 7][min(level, 7) - 1] }
    private var hopsNeeded: Int    { level >= 4 ? 2 : 1 }
    // The hunter is present from level 1 so L1/L2 aren't identical — but it's slow early
    // and waits out a grace period, so the first levels stay learnable before it speeds up.
    private var hasEnemy: Bool     { true }
    private var enemyStep: Double  { [1.5, 1.2, 0.95, 0.78, 0.64, 0.54, 0.46][min(level, 7) - 1] }
    /// Seconds before the hunter starts moving — a longer breather on the gentle early levels.
    private var enemyGrace: Double { [2.0, 1.5, 1.0, 0.6, 0.4, 0.3, 0.2][min(level, 7) - 1] }

    private var cubes: Int { rowsN * (rowsN + 1) / 2 }
    private var timeLimit: Double {
        let f = [2.4, 2.2, 1.9, 1.6, 1.35, 1.15, 0.98][min(level, 7) - 1]
        return Double(cubes * hopsNeeded) * f
    }

    // Cube top colours: state 0 = base, up to hopsNeeded = lit target (the level's palette).
    private func topColor(_ s: Int) -> Color {
        let pal = QBArt.palette(level)
        if s <= 0 { return pal.base }
        if s >= hopsNeeded { return pal.target }
        return pal.mid
    }

    private struct P: Hashable { let r: Int; let c: Int }
    private enum Phase { case play, done }

    @State private var phase: Phase = .play
    @State private var state: [P: Int] = [:]
    @State private var player = P(r: 0, c: 0)
    @State private var enemy: P? = nil
    @State private var enemyAcc = 0.0
    @State private var timeLeft = 0.0
    @State private var shakeTick = 0
    @State private var loopTask: Task<Void, Never>?
    @State private var demoKey: String? = nil       // demo: diagonal button being pressed

    // Presentation only: hop arcs (Q*bert and the hunter), which way Q*bert faces, the last
    // direction pressed (to show a hop into the void), and when the round was lost.
    @State private var hopFrom: P? = nil
    @State private var hopAt: Date? = nil
    @State private var coilyFrom: P? = nil
    @State private var coilyAt: Date? = nil
    @State private var faceUp = false
    @State private var faceLeft = true
    @State private var lastTry = P(r: 1, c: 0)
    @State private var lostAt: Date? = nil
    @State private var fxLive = false
    @State private var fxSerial = 0

    private var coloredCount: Int { state.values.filter { $0 >= hopsNeeded }.count }

    var body: some View {
        let pal = QBArt.palette(level)
        VStack(spacing: isDemo ? 4 : 6) {
            // Q*bert's "change to" sample — the target colour between two arrows — and the count.
            HStack(spacing: 10) {
                QBChangeTo(top: topColor(hopsNeeded), left: pal.left, right: pal.right)
                    .frame(width: isDemo ? 50 : 64, height: isDemo ? 20 : 26)
                Text("\(coloredCount)/\(cubes)")
                    .font(.system(size: isDemo ? 15 : 20, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            .padding(.top, isDemo ? 6 : 0)
            if !isDemo { timeBar.frame(height: 5).padding(.horizontal, 60) }

            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                // The squat demo card is short for its width: size the pyramid to the height too and
                // drop the apex so Q*bert standing on the top cube stays in frame.
                let cubeW = isDemo ? min(w * 0.68 / CGFloat(rowsN), h / (0.8 * CGFloat(rowsN - 1) + 1.55))
                                   : w * 0.68 / CGFloat(rowsN)
                let topY = isDemo ? cubeW * 0.82 : h * 0.14
                let px: (P) -> CGFloat = { p in w * 0.5 + (CGFloat(p.c) - CGFloat(p.r) / 2) * cubeW }
                let py: (P) -> CGFloat = { p in topY + CGFloat(p.r) * cubeW * 0.80 }

                TimelineView(.animation(paused: !fxLive)) { tl in
                    Canvas { ctx, _ in
                        let now = max(tl.date, Date())
                        // Cubes, back to front, exactly where the old IsoCube views sat.
                        for r in 0..<rowsN {
                            for c in 0...r {
                                let cell = P(r: r, c: c)
                                QBArt.cube(ctx, center: CGPoint(x: px(cell), y: py(cell)), w: cubeW, top: topColor(state[cell] ?? 0),
                                           left: pal.left, right: pal.right)
                            }
                        }
                        let stand = { (p: P) in CGPoint(x: px(p), y: py(p) - cubeW * 0.36) }
                        if let e = enemy {
                            let at = QBArt.hopPoint(from: coilyFrom.map(stand), to: stand(e), since: coilyAt, now: now, lift: cubeW * 0.45)
                            QBArt.coily(ctx, at: at, size: cubeW * 0.74, left: px(e) > px(player))
                        }
                        drawQbert(ctx, cubeW: cubeW, stand: stand, now: now, field: CGSize(width: w, height: h))
                    }
                }
                .frame(width: w, height: h)
                .clipped()
                .screenShake(shakeTick, amount: 5)
            }

            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
        // Hops arc from cube to cube (a jump of more than one row is a reset: it just snaps).
        .onChange(of: player) { old, new in
            let dr = new.r - old.r, dc = new.c - old.c
            guard abs(dr) == 1 else { hopAt = nil; return }
            hopFrom = old; hopAt = Date()
            faceUp = dr < 0
            faceLeft = (dr < 0 && dc < 0) || (dr > 0 && dc == 0)
            fxLive = true; fxSerial += 1
        }
        .onChange(of: enemy) { old, new in
            if let o = old, let n = new, abs(o.r - n.r) == 1 { coilyFrom = o; coilyAt = Date(); fxLive = true; fxSerial += 1 } else { coilyAt = nil }
        }
        .onChange(of: phase) { _, ph in
            lostAt = ph == .done && coloredCount < cubes ? Date() : nil
            if lostAt != nil { fxLive = true; fxSerial += 1 }
        }
        .task(id: fxSerial) {
            try? await Task.sleep(for: .seconds(1.4))
            if !Task.isCancelled { fxLive = false }
        }
    }

    /// Q*bert: hopping, or — once the round is lost — cursing (and falling, if he hopped off the edge).
    private func drawQbert(_ ctx: GraphicsContext, cubeW: CGFloat, stand: (P) -> CGPoint, now: Date, field: CGSize) {
        var at = QBArt.hopPoint(from: hopFrom.map(stand), to: stand(player), since: hopAt, now: now, lift: cubeW * 0.5)
        var scale: CGFloat = 1
        var up = faceUp, left = faceLeft
        if let lost = lostAt {
            let t = now.timeIntervalSince(lost)
            let off = P(r: player.r + lastTry.r, c: player.c + lastTry.c)
            var balloon = CGPoint(x: at.x, y: at.y - cubeW * 0.42)
            if enemy != player && timeLeft > 0 && !onPyramid(off) {
                // He jumped into the void: arc out, then drop away and shrink; the curse stays at the edge.
                up = lastTry.r < 0
                left = (lastTry.r < 0 && lastTry.c < 0) || (lastTry.r > 0 && lastTry.c == 0)
                at = QBArt.arc(from: stand(player), to: stand(off), progress: min(1, t / 0.2), lift: cubeW * 0.5)
                let drop = max(0, t - 0.2)
                at.y += CGFloat(drop * drop) * cubeW * 6
                scale = max(0.35, 1 - CGFloat(drop) * 0.7)
                let edge = stand(off)
                balloon = CGPoint(x: edge.x, y: edge.y - cubeW * 0.42)
            }
            QBArt.qbert(ctx, at: at, size: cubeW * 0.74 * scale, up: up, left: left)
            QBArt.grawlix(ctx, above: balloon, size: cubeW, bounds: field)
            return
        }
        QBArt.qbert(ctx, at: at, size: cubeW * 0.74, up: up, left: left)
    }

    private var controls: some View {
        HStack(spacing: isDemo ? 18 : 26) {
            VStack(spacing: isDemo ? 5 : 8) {
                diagBtn("arrow.up.left", -1, -1)
                diagBtn("arrow.down.left", 1, 0)
            }
            VStack(spacing: isDemo ? 5 : 8) {
                diagBtn("arrow.up.right", -1, 0)
                diagBtn("arrow.down.right", 1, 1)
            }
        }
        .padding(.bottom, isDemo ? 6 : 10)
    }

    private func diagBtn(_ icon: String, _ dr: Int, _ dc: Int) -> some View {
        let pressed = isDemo && demoKey == icon
        return Button {
            lastTry = P(r: dr, c: dc)   // presentation: which way he went if this hop leaves the pyramid
            hop(dr: dr, dc: dc)
        } label: {
            Image(systemName: icon)
                .font(.system(size: isDemo ? 19 : 24, weight: .heavy)).foregroundStyle(Color(red: 0.3, green: 0.1, blue: 0.0))
                .frame(width: isDemo ? 60 : 74, height: isDemo ? 36 : 58)
                .background(QBKey(lit: pressed))
                .contentShape(RoundedRectangle(cornerRadius: 16))
                .scaleEffect(pressed ? 0.9 : 1)
        }
        .buttonStyle(QBPressStyle())
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(frac < 0.3 ? Color(red: 1, green: 0.3, blue: 0.25) : QBArt.orange)
                    .frame(width: geo.size.width * frac)
            }
        }
    }

    // MARK: Input
    private func hop(dr: Int, dc: Int) {
        guard phase == .play else { return }
        let dest = P(r: player.r + dr, c: player.c + dc)
        guard onPyramid(dest) else { shakeTick += 1; SoundManager.shared.error(); fail(); return }
        player = dest
        let s = min(hopsNeeded, (state[dest] ?? 0) + 1)
        state[dest] = s
        SoundManager.shared.tap(); Haptics.tap()
        if let e = enemy, e == dest { fail(); return }
        if coloredCount >= cubes { win() }
    }

    private func onPyramid(_ p: P) -> Bool { p.r >= 0 && p.r < rowsN && p.c >= 0 && p.c <= p.r }

    // MARK: - Flow
    private func run() async {
        setup()
        var last = Date(); let start = Date()
        loopTask = Task {
            while !Task.isCancelled && phase == .play {
                try? await Task.sleep(for: .seconds(0.033))
                let now = Date()
                let dt = min(0.08, now.timeIntervalSince(last)); last = now
                timeLeft = max(0, timeLimit - now.timeIntervalSince(start))
                if timeLeft <= 0 { fail(); break }
                if hasEnemy { stepEnemy(dt: dt) }
            }
        }
    }

    private func setup() {
        var st: [P: Int] = [:]
        for r in 0..<rowsN { for c in 0...r { st[P(r: r, c: c)] = 0 } }
        player = P(r: 0, c: 0)
        st[player] = min(hopsNeeded, 1)
        state = st
        enemy = hasEnemy ? P(r: rowsN - 1, c: Bool.random() ? 0 : rowsN - 1) : nil
        // Negative accumulator = the grace delay counts up to 0 before the first hop.
        enemyAcc = -enemyGrace
        timeLeft = timeLimit; phase = .play
    }

    // MARK: - Demo (live manual clip)
    // Level 1 (4-row pyramid, one hop per cube, the hunter from the bottom-left corner after its
    // 2s grace, then a hop every 1.5s) through the real `hop`/`stepEnemy` at the loop's fixed 1/30s.
    // The route came from an offline DP over hop slots (13 frames apart) that scores near-misses and
    // back-and-forth hops: it lights the far side while the hunter sits on its corner, waits for it
    // to climb off, dodges its lunge at (3,1) and finishes on the corner it left. Wins at 6.0s and
    // still wins with every hop shifted −3…+3 frames.
    private static let demoHops: [(icon: String, dr: Int, dc: Int)] = {
        let key: [String: (String, Int, Int)] = [
            "UL": ("arrow.up.left", -1, -1), "UR": ("arrow.up.right", -1, 0),
            "DL": ("arrow.down.left", 1, 0), "DR": ("arrow.down.right", 1, 1)
        ]
        return ["DL", "DR", "DL", "UR", "UR", "DR", "DR", "UL", "DL", "UL", "UL", "DL", "DL"]
            .map { key[$0]! }.map { (icon: $0.0, dr: $0.1, dc: $0.2) }
    }()

    private func runDemo() async {
        let dt = 1.0 / 30.0
        while !Task.isCancelled {
            setup()
            enemy = P(r: rowsN - 1, c: 0)               // fixed: hunter starts bottom-left
            demoKey = nil
            try? await Task.sleep(for: .seconds(0.4))
            var frame = 0, next = 0
            while !Task.isCancelled && phase == .play && frame < 600 {
                frame += 1
                if next < Self.demoHops.count && frame == 24 + 13 * next {
                    let h = Self.demoHops[next]
                    demoKey = h.icon
                    hop(dr: h.dr, dc: h.dc)
                    next += 1
                }
                if demoKey != nil && next > 0 && frame == 24 + 13 * (next - 1) + 6 { demoKey = nil }
                if phase == .play { stepEnemy(dt: dt) }
                try? await Task.sleep(for: .seconds(0.033))
            }
            // Every cube lit → the real win() ran (onWin is a no-op). Hold, then loop.
            demoKey = nil
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    private func stepEnemy(dt: Double) {
        guard var e = enemy else { return }
        enemyAcc += dt
        guard enemyAcc >= enemyStep else { return }
        enemyAcc = 0
        // Greedy hop toward the player, staying on the pyramid.
        let moves = [P(r: e.r - 1, c: e.c - 1), P(r: e.r - 1, c: e.c),
                     P(r: e.r + 1, c: e.c), P(r: e.r + 1, c: e.c + 1)]
        let valid = moves.filter { onPyramid($0) }
        if let best = valid.min(by: { dist($0, player) < dist($1, player) }) {
            e = best; enemy = e
            if e == player { fail(); return }
        }
    }

    private func dist(_ a: P, _ b: P) -> Int { abs(a.r - b.r) + abs(a.c - b.c) }

    private func win() {
        guard phase != .done else { return }
        phase = .done; loopTask?.cancel(); onWin()
    }
    private func fail() {
        guard phase != .done else { return }
        phase = .done; loopTask?.cancel(); shakeTick += 1; SoundManager.shared.error(); onFail()
    }

}

// MARK: - Q*bert art (after Gottlieb's 1982 arcade game)

private struct QBPalette {
    let base: Color, mid: Color, target: Color
    let left: Color, right: Color
}

private enum QBArt {
    static let orange = Color(red: 1, green: 0.52, blue: 0.1)

    /// Tri-coloured cubes like the arcade's: a new top / side scheme each level (blue → yellow first).
    static func palette(_ level: Int) -> QBPalette {
        let c = { (r: Double, g: Double, b: Double) in Color(red: r, green: g, blue: b) }
        switch min(max(level, 1), 7) {
        case 1: return QBPalette(base: c(0.33, 0.42, 0.96), mid: c(0.33, 0.42, 0.96), target: c(1, 0.9, 0.18), left: c(0.82, 0.7, 0.47), right: c(0.34, 0.33, 0.42))
        case 2: return QBPalette(base: c(0.2, 0.62, 0.55), mid: c(0.2, 0.62, 0.55), target: c(1, 0.62, 0.78), left: c(0.62, 0.66, 0.74), right: c(0.26, 0.28, 0.36))
        case 3: return QBPalette(base: c(0.56, 0.3, 0.78), mid: c(0.56, 0.3, 0.78), target: c(0.42, 0.92, 0.42), left: c(0.9, 0.8, 0.56), right: c(0.3, 0.22, 0.36))
        case 4: return QBPalette(base: c(0.36, 0.4, 0.46), mid: c(0.3, 0.64, 0.98), target: c(1, 0.88, 0.2), left: c(0.82, 0.54, 0.32), right: c(0.42, 0.24, 0.18))
        case 5: return QBPalette(base: c(0.66, 0.2, 0.26), mid: c(0.98, 0.56, 0.24), target: c(1, 0.96, 0.66), left: c(0.56, 0.62, 0.72), right: c(0.24, 0.27, 0.36))
        case 6: return QBPalette(base: c(0.22, 0.48, 0.3), mid: c(0.92, 0.86, 0.3), target: c(0.98, 0.42, 0.62), left: c(0.72, 0.72, 0.78), right: c(0.3, 0.3, 0.36))
        default: return QBPalette(base: c(0.38, 0.23, 0.52), mid: c(0.3, 0.82, 0.88), target: c(1, 0.9, 0.2), left: c(0.86, 0.6, 0.4), right: c(0.4, 0.2, 0.2))
        }
    }

    /// One cube with the old IsoCube's exact geometry: a `w × 1.2w` box centred on `center`, its top
    /// diamond `w/2` tall.
    static func cube(_ ctx: GraphicsContext, center: CGPoint, w: CGFloat, top: Color, left: Color, right: Color) {
        let x0 = center.x - w / 2, y0 = center.y - w * 0.6
        let topH = w * 0.5, sideH = w * 0.7
        func quad(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Path {
            var p = Path()
            p.move(to: a); p.addLine(to: b); p.addLine(to: c); p.addLine(to: d); p.closeSubpath()
            return p
        }
        let lFace = quad(CGPoint(x: x0, y: y0 + topH * 0.5), CGPoint(x: x0 + w / 2, y: y0 + topH),
                         CGPoint(x: x0 + w / 2, y: y0 + topH + sideH), CGPoint(x: x0, y: y0 + topH * 0.5 + sideH))
        let rFace = quad(CGPoint(x: x0 + w, y: y0 + topH * 0.5), CGPoint(x: x0 + w / 2, y: y0 + topH),
                         CGPoint(x: x0 + w / 2, y: y0 + topH + sideH), CGPoint(x: x0 + w, y: y0 + topH * 0.5 + sideH))
        let tFace = quad(CGPoint(x: x0 + w / 2, y: y0), CGPoint(x: x0 + w, y: y0 + topH / 2),
                         CGPoint(x: x0 + w / 2, y: y0 + topH), CGPoint(x: x0, y: y0 + topH / 2))
        ctx.fill(lFace, with: .color(left))
        ctx.fill(rFace, with: .color(right))
        ctx.fill(tFace, with: .color(top))
        // A thin inner bevel on the top keeps neighbouring tops apart.
        let inset = quad(CGPoint(x: x0 + w / 2, y: y0 + topH * 0.12), CGPoint(x: x0 + w * 0.88, y: y0 + topH / 2),
                         CGPoint(x: x0 + w / 2, y: y0 + topH * 0.88), CGPoint(x: x0 + w * 0.12, y: y0 + topH / 2))
        ctx.stroke(inset, with: .color(.white.opacity(0.18)), lineWidth: max(1, w * 0.02))
        var edges = tFace
        edges.addPath(lFace); edges.addPath(rFace)
        ctx.stroke(edges, with: .color(.black.opacity(0.6)), lineWidth: max(1, w * 0.02))
    }

    /// A point on a hop's arc (`progress` 0…1).
    static func arc(from a: CGPoint, to b: CGPoint, progress t: Double, lift: CGFloat) -> CGPoint {
        let k = CGFloat(max(0, min(1, t)))
        return CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k - lift * 4 * k * (1 - k))
    }

    /// Where a hopper is drawn: on its hop arc for 0.18 s after `since`, else on its cube.
    static func hopPoint(from a: CGPoint?, to b: CGPoint, since: Date?, now: Date, lift: CGFloat) -> CGPoint {
        guard let a, let since else { return b }
        let t = now.timeIntervalSince(since) / 0.18
        return t >= 1 ? b : arc(from: a, to: b, progress: t, lift: lift)
    }

    /// Q*bert: an orange ball with big eyes, a tube snout and black shoes, facing his hop.
    static func qbert(_ ctx: GraphicsContext, at p: CGPoint, size s: CGFloat, up: Bool, left: Bool) {
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        if left { g.scaleBy(x: -1, y: 1) }
        g.scaleBy(x: s, y: s)
        let ink = Color(red: 0.18, green: 0.06, blue: 0.0)
        let body = orange
        g.fill(Path(ellipseIn: CGRect(x: -0.3, y: 0.38, width: 0.6, height: 0.12)), with: .color(.black.opacity(0.3)))
        var legs = Path()
        legs.move(to: CGPoint(x: -0.1, y: 0.2)); legs.addLine(to: CGPoint(x: -0.12, y: 0.38))
        legs.move(to: CGPoint(x: 0.1, y: 0.2)); legs.addLine(to: CGPoint(x: 0.1, y: 0.38))
        g.stroke(legs, with: .color(body.mix(with: .black, by: 0.2)), style: StrokeStyle(lineWidth: 0.08, lineCap: .round))
        for x in [-0.12, 0.1] as [CGFloat] {
            g.fill(Path(ellipseIn: CGRect(x: x - 0.08, y: 0.34, width: 0.26, height: 0.12)), with: .color(Color(white: 0.08)))
        }
        let ball = Path(ellipseIn: CGRect(x: -0.32, y: -0.32, width: 0.64, height: 0.6))
        g.fill(ball, with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.78, blue: 0.45), body, body.mix(with: .black, by: 0.3)]),
                                           center: CGPoint(x: -0.1, y: -0.16), startRadius: 0, endRadius: 0.42))
        g.stroke(ball, with: .color(ink), lineWidth: 0.035)
        // The tube snout: forward and down (or up when he hops away from you).
        let tip = up ? CGPoint(x: 0.44, y: -0.2) : CGPoint(x: 0.44, y: 0.14)
        let root = CGPoint(x: 0.14, y: up ? -0.06 : 0.04)
        var tube = Path()
        tube.move(to: root); tube.addLine(to: tip)
        g.stroke(tube, with: .color(ink), style: StrokeStyle(lineWidth: 0.2, lineCap: .round))
        g.stroke(tube, with: .color(body.mix(with: .white, by: 0.08)), style: StrokeStyle(lineWidth: 0.14, lineCap: .round))
        g.fill(Path(ellipseIn: CGRect(x: tip.x - 0.05, y: tip.y - 0.07, width: 0.1, height: 0.14)), with: .color(ink))
        // Big eyes.
        for (x, r) in [(-0.02, 0.1), (0.17, 0.09)] as [(CGFloat, CGFloat)] {
            let eye = Path(ellipseIn: CGRect(x: x - r, y: -0.22 - r, width: r * 2, height: r * 2.2))
            g.fill(eye, with: .color(.white))
            g.stroke(eye, with: .color(ink), lineWidth: 0.025)
            g.fill(Path(ellipseIn: CGRect(x: x - r * 0.1, y: (up ? -0.3 : -0.2) - r * 0.4, width: r * 0.8, height: r * 0.9)), with: .color(.black))
        }
    }

    /// Coily: a purple snake on its coiled spring body, big eyes on whoever it's after.
    static func coily(_ ctx: GraphicsContext, at p: CGPoint, size s: CGFloat, left: Bool) {
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        if left { g.scaleBy(x: -1, y: 1) }
        g.scaleBy(x: s, y: s)
        let purple = Color(red: 0.62, green: 0.3, blue: 0.86)
        let ink = Color(red: 0.12, green: 0.02, blue: 0.2)
        g.fill(Path(ellipseIn: CGRect(x: -0.3, y: 0.38, width: 0.6, height: 0.12)), with: .color(.black.opacity(0.3)))
        for (y, w) in [(0.3, 0.5), (0.16, 0.44), (0.03, 0.38)] as [(CGFloat, CGFloat)] {
            let coil = Path(ellipseIn: CGRect(x: -w / 2, y: y - 0.08, width: w, height: 0.18))
            g.fill(coil, with: .linearGradient(Gradient(colors: [purple.mix(with: .white, by: 0.25), purple.mix(with: .black, by: 0.25)]),
                                               startPoint: CGPoint(x: 0, y: y - 0.08), endPoint: CGPoint(x: 0, y: y + 0.1)))
            g.stroke(coil, with: .color(ink), lineWidth: 0.03)
        }
        let head = Path(ellipseIn: CGRect(x: -0.22, y: -0.46, width: 0.5, height: 0.42))
        g.fill(head, with: .radialGradient(Gradient(colors: [purple.mix(with: .white, by: 0.3), purple, purple.mix(with: .black, by: 0.3)]),
                                           center: CGPoint(x: -0.04, y: -0.36), startRadius: 0, endRadius: 0.34))
        g.stroke(head, with: .color(ink), lineWidth: 0.03)
        for x in [-0.05, 0.14] as [CGFloat] {
            g.fill(Path(ellipseIn: CGRect(x: x - 0.08, y: -0.4, width: 0.16, height: 0.18)), with: .color(.white))
            g.fill(Path(ellipseIn: CGRect(x: x - 0.01, y: -0.34, width: 0.08, height: 0.09)), with: .color(.black))
        }
        var brows = Path()
        brows.move(to: CGPoint(x: -0.14, y: -0.44)); brows.addLine(to: CGPoint(x: 0.02, y: -0.4))
        brows.move(to: CGPoint(x: 0.07, y: -0.4)); brows.addLine(to: CGPoint(x: 0.23, y: -0.45))
        g.stroke(brows, with: .color(ink), style: StrokeStyle(lineWidth: 0.04, lineCap: .round))
        var tongue = Path()
        tongue.move(to: CGPoint(x: 0.24, y: -0.16)); tongue.addLine(to: CGPoint(x: 0.4, y: -0.12))
        tongue.move(to: CGPoint(x: 0.4, y: -0.12)); tongue.addLine(to: CGPoint(x: 0.46, y: -0.16))
        tongue.move(to: CGPoint(x: 0.4, y: -0.12)); tongue.addLine(to: CGPoint(x: 0.46, y: -0.08))
        g.stroke(tongue, with: .color(Color(red: 0.95, green: 0.15, blue: 0.2)), style: StrokeStyle(lineWidth: 0.035, lineCap: .round))
    }

    /// A comic curse balloon (a generic grawlix, not the arcade original's exact one).
    static func grawlix(_ ctx: GraphicsContext, above anchor: CGPoint, size: CGFloat, bounds: CGSize) {
        let text = ctx.resolve(Text("#%&!").font(.system(size: max(9, size * 0.3), weight: .black, design: .rounded)).foregroundColor(.black))
        let ts = text.measure(in: CGSize(width: 400, height: 100))
        // Keep the whole balloon inside the field (the apex sits close to the top edge).
        let p = CGPoint(x: min(max(anchor.x, ts.width / 2 + 12), bounds.width - ts.width / 2 - 12), y: max(anchor.y, ts.height + 16))
        let box = CGRect(x: p.x - ts.width / 2 - 8, y: p.y - ts.height - 12, width: ts.width + 16, height: ts.height + 8)
        var balloon = Path(roundedRect: box, cornerRadius: box.height / 2)
        balloon.move(to: CGPoint(x: p.x - 4, y: box.maxY - 1))
        balloon.addLine(to: CGPoint(x: p.x + 2, y: box.maxY + 7))
        balloon.addLine(to: CGPoint(x: p.x + 6, y: box.maxY - 1))
        ctx.fill(balloon, with: .color(.white))
        ctx.stroke(Path(roundedRect: box, cornerRadius: box.height / 2), with: .color(.black), lineWidth: 1.5)
        ctx.draw(text, at: CGPoint(x: box.midX, y: box.midY))
    }
}

/// "Change to": the target colour on a little cube, with an arrow pointing at it from each side.
private struct QBChangeTo: View {
    let top: Color
    let left: Color
    let right: Color

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let cw = h * 0.95
            QBArt.cube(ctx, center: CGPoint(x: w / 2, y: h / 2 + cw * 0.02), w: cw * 0.82, top: top, left: left, right: right)
            for s in [-1.0, 1.0] as [CGFloat] {
                let tipX = w / 2 - s * cw * 0.6
                var arrow = Path()
                arrow.move(to: CGPoint(x: tipX, y: h / 2))
                arrow.addLine(to: CGPoint(x: tipX - s * h * 0.34, y: h / 2 - h * 0.24))
                arrow.addLine(to: CGPoint(x: tipX - s * h * 0.34, y: h / 2 + h * 0.24))
                arrow.closeSubpath()
                ctx.fill(arrow, with: .color(QBArt.orange))
            }
        }
    }
}

/// The diagonal hop keys in Q*bert orange (white when pressed).
private struct QBKey: View {
    let lit: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: lit ? [Color(white: 1), Color(red: 1, green: 0.88, blue: 0.62)]
                                                 : [Color(red: 1, green: 0.66, blue: 0.24), Color(red: 0.9, green: 0.4, blue: 0.08)],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.5), lineWidth: 2)
            RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(lit ? 0.95 : 0.3), lineWidth: 1.2).padding(3)
        }
    }
}

private struct QBPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.92 : 1)
    }
}
