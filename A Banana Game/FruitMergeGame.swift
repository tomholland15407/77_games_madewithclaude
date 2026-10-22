//
//  FruitMergeGame.swift
//  GOGs
//
//  Brain (with physics) — Fruit Merge, the Suika / "watermelon game". Drag to aim and let go to
//  drop the next fruit into the box. Two of the same fruit that touch merge into the next one up the
//  chain (cherry → strawberry → grape → dekopon → persimmon → apple → pear → peach → pineapple →
//  melon → watermelon). Make the level's goal fruit to win. If fruit stays piled above the rim, or
//  time runs out, it's back to level 1.
//
//  Physics is a small position-based solver (`FMWorld`, a plain value type): circles with
//  area-weighted mass, Coulomb-style friction so piles hold and fruit roll, 10 fixed substeps per
//  1/60 s frame. Merged fruit grow into their new size over a few frames so a merge "pops" its
//  neighbours outward without exploding. Fruit art is pre-rendered once per kind (FruitArt with
//  faces) and drawn rotated each frame. Later levels start with big fruit and clutter already in
//  the box and ask for higher goals on the clock.
//

import SwiftUI

enum FruitMergeGame {
    static let definition = GameDefinition(
        id: "fruit-merge",
        title: "Fruit Tumble",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        locksFeed: true,
        manual: GameManual(
            bullets: [
                "Drag to aim, then let go to drop the fruit into the box.",
                "Two matching fruits that touch merge into the next fruit up the chain.",
                "Make the goal fruit shown at the top to win.",
                "If fruit stays piled above the rim, or time runs out, you're back to level 1.",
            ],
            bulletsVI: [
                "Kéo để nhắm, rồi thả tay để thả trái cây vào hộp.",
                "Hai trái giống nhau chạm vào nhau sẽ hợp thành trái lớn hơn trong chuỗi.",
                "Tạo ra trái mục tiêu hiện ở phía trên để thắng.",
                "Nếu trái cây chồng quá miệng hộp, hoặc hết giờ, bạn về lại cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(FruitMergeView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

// MARK: - Physics

nonisolated struct FMFruit: Sendable {
    var id: Int
    var tier: Int
    var p: SIMD2<Double>
    var v: SIMD2<Double>
    var r: Double
    var targetR: Double
    var angle: Double = 0
    var age: Double = 0
    var over: Double = 0      // seconds spent above the rim
    var pop: Double = 0       // merge bounce, 1 → 0
}

nonisolated struct FMWorld: Sendable {
    /// Radii as fractions of the box width, in Suika proportions.
    static let radii: [Double] = [0.0375, 0.05, 0.0625, 0.0875, 0.1, 0.1125, 0.13125, 0.15, 0.2, 0.25, 0.3]
    static let boxH = 1.15
    static let gravity = 4.0
    static let dropY = -0.13

    var fruits: [FMFruit] = []
    var nextID = 0
    /// Merge events from the last `step` (new tier + position), for effects and win checks.
    var merges: [(tier: Int, p: SIMD2<Double>)] = []

    mutating func add(tier: Int, x: Double, y: Double = FMWorld.dropY) {
        let r = Self.radii[tier]
        let cx = min(max(x, r), 1 - r)
        fruits.append(FMFruit(id: nextID, tier: tier, p: SIMD2(cx, y), v: .zero, r: r, targetR: r))
        nextID += 1
    }

    /// Longest time any settled fruit has been sitting above the rim.
    var maxOver: Double { fruits.map(\.over).max() ?? 0 }
    /// Is any fruit close to (or above) the rim? Drives the flashing danger line.
    var nearRim: Bool { fruits.contains { $0.age > 0.8 && $0.p.y - $0.r < 0.08 } }

    mutating func step(_ dt: Double) {
        merges = []
        let sub = 10
        let h = dt / Double(sub)
        let muS = 0.55, muK = 0.35
        for _ in 0..<sub {
            let n = fruits.count
            var prev = [SIMD2<Double>](repeating: .zero, count: n)
            for i in 0..<n {
                if fruits[i].r < fruits[i].targetR {
                    fruits[i].r = min(fruits[i].targetR, fruits[i].r + 0.9 * h)   // grow into a merge
                }
                prev[i] = fruits[i].p
                fruits[i].v.y += Self.gravity * h
                fruits[i].p += fruits[i].v * h
            }
            // Fruit–fruit contacts: mass-weighted separation + friction on the relative slide.
            if n > 1 {
                for i in 0..<(n - 1) {
                    for j in (i + 1)..<n {
                        let d = fruits[j].p - fruits[i].p
                        let minD = fruits[i].r + fruits[j].r
                        let dist2 = d.x * d.x + d.y * d.y
                        guard dist2 < minD * minD, dist2 > 1e-14 else { continue }
                        let dist = dist2.squareRoot()
                        let nrm = d / dist
                        let pen = minD - dist
                        let wi = 1 / (fruits[i].r * fruits[i].r), wj = 1 / (fruits[j].r * fruits[j].r)
                        let ki = wi / (wi + wj), kj = wj / (wi + wj)
                        fruits[i].p -= nrm * (pen * ki)
                        fruits[j].p += nrm * (pen * kj)
                        let rel = (fruits[i].p - prev[i]) - (fruits[j].p - prev[j])
                        let tan = rel - nrm * ((rel * nrm).sum())
                        let tl = (tan * tan).sum().squareRoot()
                        if tl > 1e-12 {
                            let corr = tl < muS * pen ? tan : tan * min(muK * pen / tl, 1)
                            fruits[i].p -= corr * ki
                            fruits[j].p += corr * kj
                        }
                    }
                }
            }
            // Walls and floor (with friction along the surface).
            for i in 0..<n {
                let r = fruits[i].r
                if fruits[i].p.x < r {
                    let pen = r - fruits[i].p.x
                    fruits[i].p.x = r
                    let dy = fruits[i].p.y - prev[i].y
                    fruits[i].p.y -= abs(dy) < muS * pen ? dy : dy * min(muK * pen / abs(dy), 1)
                }
                if fruits[i].p.x > 1 - r {
                    let pen = fruits[i].p.x - (1 - r)
                    fruits[i].p.x = 1 - r
                    let dy = fruits[i].p.y - prev[i].y
                    fruits[i].p.y -= abs(dy) < muS * pen ? dy : dy * min(muK * pen / abs(dy), 1)
                }
                if fruits[i].p.y > Self.boxH - r {
                    let pen = fruits[i].p.y - (Self.boxH - r)
                    fruits[i].p.y = Self.boxH - r
                    let dx = fruits[i].p.x - prev[i].x
                    fruits[i].p.x -= abs(dx) < muS * pen ? dx : dx * min(muK * pen / abs(dx), 1)
                }
            }
            for i in 0..<n {
                var v = (fruits[i].p - prev[i]) / h
                let sp = (v * v).sum().squareRoot()
                if sp > 6 { v *= 6 / sp }
                fruits[i].v = v
            }
        }
        // Light air damping, rolling spin, ageing and the over-the-rim timer.
        let damp = 1 - 0.25 * dt
        for i in fruits.indices {
            fruits[i].v *= damp
            fruits[i].angle += fruits[i].v.x / fruits[i].r * dt
            fruits[i].age += dt
            fruits[i].pop = max(0, fruits[i].pop - dt / 0.28)
            if fruits[i].age > 1.0 && fruits[i].p.y - fruits[i].r < 0 && abs(fruits[i].v.y) < 0.6 {
                fruits[i].over += dt
            } else {
                fruits[i].over = 0
            }
        }
        // Merges: touching twins become the next fruit at their mass-weighted midpoint.
        var used = Set<Int>()
        var born: [FMFruit] = []
        let n = fruits.count
        if n > 1 {
            for i in 0..<(n - 1) where !used.contains(i) {
                for j in (i + 1)..<n where !used.contains(j) && fruits[j].tier == fruits[i].tier {
                    let a = fruits[i], b = fruits[j]
                    let d = b.p - a.p
                    let reach = a.r + b.r + 0.004
                    guard (d * d).sum() < reach * reach else { continue }
                    used.insert(i); used.insert(j)
                    if a.tier + 1 < Self.radii.count {
                        let ma = a.r * a.r, mb = b.r * b.r
                        let p = (a.p * ma + b.p * mb) / (ma + mb)
                        var f = FMFruit(id: nextID, tier: a.tier + 1, p: p, v: (a.v + b.v) * 0.25,
                                        r: max(a.r, b.r), targetR: Self.radii[a.tier + 1])
                        f.age = max(a.age, b.age)
                        f.pop = 1
                        f.angle = (a.angle + b.angle) / 2
                        nextID += 1
                        born.append(f)
                        merges.append((a.tier + 1, p))
                    } else {
                        merges.append((a.tier, (a.p + b.p) / 2))   // two watermelons: both vanish
                    }
                    break
                }
            }
        }
        if !used.isEmpty {
            fruits = fruits.indices.filter { !used.contains($0) }.map { fruits[$0] } + born
        }
    }
}

// MARK: - Art cache

/// Each fruit kind rendered once (with its face) so the per-frame Canvas just stamps rotated
/// images instead of re-drawing dozens of gradient paths.
@MainActor
private enum FMArt {
    static let spanK: CGFloat = 1.45        // image half-size in body radii (stems/crowns poke up)
    private static var cache: [Int: Image] = [:]

    static func image(_ tier: Int) -> Image {
        if let img = cache[tier] { return img }
        let r: CGFloat = max(18, CGFloat(FMWorld.radii[tier]) * 380)
        let side = r * spanK * 2
        let view = Canvas { ctx, size in
            FruitArt.draw(FruitKind(rawValue: tier) ?? .cherry, in: ctx,
                          at: CGPoint(x: size.width / 2, y: size.height / 2), radius: r, face: true)
        }
        .frame(width: side, height: side)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let img = renderer.uiImage.map { Image(uiImage: $0) } ?? Image(systemName: "circle.fill")
        cache[tier] = img
        return img
    }

    static func warm() { for t in 0..<FMWorld.radii.count { _ = image(t) } }
}

// MARK: - View

struct FruitMergeView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void
    @Environment(\.isDemo) private var isDemo

    private var goal: Int { [5, 6, 7, 7, 8, 8, 9][min(level, 7) - 1] }
    /// Fruit already in the box when the level starts (settled before play).
    private var seeds: [Int] {
        [[], [], [6, 2, 1],
         [5, 4, 2, 1, 0, 3, 2],
         [7, 5, 3, 2, 1, 0, 4, 1],
         [7, 4, 3, 2, 1, 0, 2, 1, 3, 0, 4, 2, 1, 0],
         [8, 7, 5, 4, 3, 2, 1, 0, 2, 1, 3, 0]][min(level, 7) - 1]
    }
    // Tuned with a headless bot (1.4 s per drop, ±0.04 aim): ~100/100/97/85/45/18/13% wins by level.
    private var timeLimit: Double { [60, 60, 70, 55, 60, 38, 45][min(level, 7) - 1] }
    private let overLimit = 1.6

    private static let bgTop = Color(red: 1.0, green: 0.87, blue: 0.56)
    private static let bgBottom = Color(red: 0.99, green: 0.70, blue: 0.36)
    private static let wood = Color(red: 0.76, green: 0.48, blue: 0.24)

    private enum Phase { case loading, play, won, done }

    @State private var phase: Phase = .loading
    @State private var world = FMWorld()
    @State private var current = 0
    @State private var upcoming = 0
    @State private var aimX = 0.5
    @State private var aiming = false
    @State private var lastDrop = Date.distantPast
    @State private var timeLeft = 0.0
    @State private var clock = 0.0
    @State private var splashes: [(p: SIMD2<Double>, tier: Int, t0: Double)] = []
    @State private var wonTier: Int? = nil
    @State private var demoFinger: SIMD2<Double>? = nil   // in box units
    @State private var demoPressed = false

    var body: some View {
        GeometryReader { geo in
            let lay = layout(geo.size)
            ZStack {
                LinearGradient(colors: [Self.bgTop, Self.bgBottom], startPoint: .top, endPoint: .bottom)
                Canvas { ctx, _ in draw(ctx, lay) }
                if isDemo { demoHud(lay, size: geo.size) } else { hud(lay) }
            }
            .contentShape(Rectangle())
            .gesture(aimGesture(lay), including: isDemo ? .none : .all)
        }
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
    }

    // MARK: Layout

    private struct Lay {
        let box: CGRect          // inner box; x 0…1 maps to its width, y 0…boxH to its height
        let unit: CGFloat        // points per box unit
        let hudY: CGFloat
        let stripY: CGFloat
    }

    private func layout(_ s: CGSize) -> Lay {
        let pad: CGFloat = isDemo ? 8 : 18
        // The squat demo card puts GOAL/NEXT beside the box and skips the strip, so the box is bigger.
        let hudH: CGFloat = isDemo ? 0 : 64
        let stripH: CGFloat = isDemo ? 0 : 38
        let dropSpace: CGFloat = isDemo ? 0.26 : 0.3   // box units above the rim for the hovering fruit
        let wall: CGFloat = 0.03
        let availW = s.width - pad * 2
        let availH = s.height - hudH - stripH - pad * 1.5
        let unit = min(availW / (1 + wall * 2), availH / (CGFloat(FMWorld.boxH) + dropSpace + wall))
        let boxW = unit, boxH = unit * CGFloat(FMWorld.boxH)
        let top = hudH + (availH - boxH - dropSpace * unit - wall * unit) / 2 + dropSpace * unit
        let box = CGRect(x: (s.width - boxW) / 2, y: top, width: boxW, height: boxH)
        return Lay(box: box, unit: unit, hudY: hudH / 2 + (isDemo ? 2 : 4),
                   stripY: box.maxY + wall * unit + stripH / 2 + pad * 0.4)
    }

    private func pt(_ p: SIMD2<Double>, _ l: Lay) -> CGPoint {
        CGPoint(x: l.box.minX + CGFloat(p.x) * l.unit, y: l.box.minY + CGFloat(p.y) * l.unit)
    }

    // MARK: HUD

    private func hud(_ l: Lay) -> some View {
        VStack(spacing: isDemo ? 3 : 8) {
            if !isDemo {
                GeometryReader { g in
                    let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(.black.opacity(0.14))
                        Capsule().fill(frac < 0.3 ? .red : Color(red: 0.55, green: 0.3, blue: 0.1))
                            .frame(width: g.size.width * frac)
                    }
                }
                .frame(height: 6)
                .padding(.horizontal, 40)
            }
            HStack {
                bubble(L("GOAL", "MỤC TIÊU"), tier: goal)
                Spacer()
                bubble(L("NEXT", "TIẾP"), tier: upcoming)
            }
            .padding(.horizontal, isDemo ? 12 : 20)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, isDemo ? 6 : 10)
    }

    private func demoHud(_ l: Lay, size: CGSize) -> some View {
        let leftX = l.box.minX / 2, rightX = l.box.maxX + (size.width - l.box.maxX) / 2
        return ZStack {
            demoTag(L("GOAL", "MỤC TIÊU"), tier: goal).position(x: leftX, y: l.box.minY + 30)
            demoTag(L("NEXT", "TIẾP"), tier: upcoming).position(x: rightX, y: l.box.minY + 30)
        }
    }

    private func demoTag(_ title: String, tier: Int) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.45, green: 0.22, blue: 0.06))
            FMArt.image(tier).resizable().frame(width: 34, height: 34)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0.62, green: 0.36, blue: 0.14).opacity(0.5), lineWidth: 2))
    }

    private func bubble(_ title: String, tier: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: isDemo ? 11 : 14, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.45, green: 0.22, blue: 0.06))
            FMArt.image(tier)
                .resizable()
                .frame(width: isDemo ? 26 : 38, height: isDemo ? 26 : 38)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(Capsule().fill(.white.opacity(0.55)))
        .overlay(Capsule().stroke(Color(red: 0.62, green: 0.36, blue: 0.14).opacity(0.5), lineWidth: 2))
    }

    // MARK: Drawing

    private func draw(_ ctx: GraphicsContext, _ l: Lay) {
        let b = l.box, u = l.unit
        let wall = 0.03 * u

        // The box: a cream tub with a chunky wooden rim, open at the top.
        let outer = CGRect(x: b.minX - wall, y: b.minY - wall * 0.5, width: b.width + wall * 2, height: b.height + wall * 1.5)
        var tub = Path()
        tub.move(to: CGPoint(x: outer.minX, y: outer.minY))
        tub.addLine(to: CGPoint(x: outer.minX, y: outer.maxY - wall * 2))
        tub.addQuadCurve(to: CGPoint(x: outer.minX + wall * 2, y: outer.maxY), control: CGPoint(x: outer.minX, y: outer.maxY))
        tub.addLine(to: CGPoint(x: outer.maxX - wall * 2, y: outer.maxY))
        tub.addQuadCurve(to: CGPoint(x: outer.maxX, y: outer.maxY - wall * 2), control: CGPoint(x: outer.maxX, y: outer.maxY))
        tub.addLine(to: CGPoint(x: outer.maxX, y: outer.minY))
        var shadowed = ctx
        shadowed.addFilter(.shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 5))
        shadowed.fill(Path(roundedRect: b, cornerRadius: wall), with: .linearGradient(
            Gradient(colors: [Color(red: 1, green: 0.97, blue: 0.86).opacity(0.9), Color(red: 1, green: 0.92, blue: 0.74).opacity(0.95)]),
            startPoint: CGPoint(x: b.midX, y: b.minY), endPoint: CGPoint(x: b.midX, y: b.maxY)))
        ctx.stroke(tub, with: .color(Self.wood.shade(0.25)), style: StrokeStyle(lineWidth: wall * 1.35, lineCap: .round, lineJoin: .round))
        ctx.stroke(tub, with: .color(Self.wood), style: StrokeStyle(lineWidth: wall * 0.85, lineCap: .round, lineJoin: .round))

        // Danger line at the rim, flashing when the pile gets close.
        if world.nearRim || world.maxOver > 0 {
            let on = Int(clock * 6) % 2 == 0 || world.maxOver > 0
            var dash = Path()
            dash.move(to: CGPoint(x: b.minX, y: b.minY)); dash.addLine(to: CGPoint(x: b.maxX, y: b.minY))
            ctx.stroke(dash, with: .color(Color(red: 0.9, green: 0.15, blue: 0.1).opacity(on ? 0.9 : 0.35)),
                       style: StrokeStyle(lineWidth: 3, dash: [10, 7]))
        }

        // Aim guide + the hovering fruit.
        if phase == .play {
            let r = FMWorld.radii[current]
            let x = min(max(aimX, r), 1 - r)
            var hitY = FMWorld.boxH
            for f in world.fruits where abs(f.p.x - x) < f.r {
                let dx = f.p.x - x
                hitY = min(hitY, f.p.y - (f.r * f.r - dx * dx).squareRoot())
            }
            var guide = Path()
            guide.move(to: pt(SIMD2(x, FMWorld.dropY + r), l))
            guide.addLine(to: pt(SIMD2(x, hitY), l))
            ctx.stroke(guide, with: .color(.white.opacity(0.85)), lineWidth: 2)
            let canDrop = Date().timeIntervalSince(lastDrop) > 0.45 || isDemo
            var g = ctx
            g.opacity = canDrop ? 1 : 0.55
            stamp(g, tier: current, at: pt(SIMD2(x, FMWorld.dropY), l), r: CGFloat(r) * u, angle: 0, pop: 0)
        }

        for f in world.fruits {
            stamp(ctx, tier: f.tier, at: pt(f.p, l), r: CGFloat(f.r) * u, angle: f.angle, pop: f.pop)
        }

        // Juice splashes on merges.
        for s in splashes {
            let t = clock - s.t0
            guard t >= 0, t < 0.45 else { continue }
            let c = pt(s.p, l)
            let color = FruitArt.color(FruitKind(rawValue: s.tier) ?? .cherry)
            let base = CGFloat(FMWorld.radii[s.tier]) * u
            for k in 0..<10 {
                let a = Double(k) / 10 * 2 * .pi + Double(s.tier)
                let d = base * CGFloat(0.9 + t * 3.2)
                let sz = base * 0.22 * CGFloat(1 - t / 0.45)
                let q = CGPoint(x: c.x + CGFloat(cos(a)) * d, y: c.y + CGFloat(sin(a)) * d + CGFloat(t * t) * u * 1.5)
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - sz, y: q.y - sz, width: sz * 2, height: sz * 2)), with: .color(color))
            }
            let ring = base * CGFloat(1 + t * 2.5)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - ring, y: c.y - ring, width: ring * 2, height: ring * 2)),
                       with: .color(.white.opacity(0.7 * (1 - t / 0.45))), lineWidth: 3)
        }

        // Evolution strip: the whole chain, goal ringed, fruit past the goal dimmed.
        let n = isDemo ? 0 : FMWorld.radii.count
        let cellW = min(b.width * 1.1 / CGFloat(n), 40)
        let x0 = b.midX - cellW * CGFloat(n) / 2
        for t in 0..<n {
            let c = CGPoint(x: x0 + (CGFloat(t) + 0.5) * cellW, y: l.stripY)
            var g = ctx
            if t > goal { g.opacity = 0.3 }
            if t == goal {
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - cellW * 0.52, y: c.y - cellW * 0.52, width: cellW * 1.04, height: cellW * 1.04)),
                         with: .color(.white.opacity(0.7)))
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - cellW * 0.52, y: c.y - cellW * 0.52, width: cellW * 1.04, height: cellW * 1.04)),
                           with: .color(Color(red: 0.62, green: 0.34, blue: 0.1)), lineWidth: 2)
            }
            stamp(g, tier: t, at: c, r: cellW * 0.34, angle: 0, pop: 0)
        }

        // Demo finger.
        if let f = demoFinger {
            var hand = ctx.resolve(Image(systemName: "hand.point.up.left.fill"))
            hand.shading = .color(.white)
            var h = ctx
            h.addFilter(.shadow(color: .black.opacity(0.5), radius: 3))
            let w = u * (demoPressed ? 0.13 : 0.145)
            let p = pt(f, l)
            h.draw(hand, in: CGRect(x: p.x - w * 0.28, y: p.y - w * 0.1, width: w, height: w))
        }
    }

    private func stamp(_ ctx: GraphicsContext, tier: Int, at c: CGPoint, r: CGFloat, angle: Double, pop: Double) {
        let s = r * (1 + 0.16 * CGFloat(sin(pop * .pi))) * FMArt.spanK
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .radians(angle))
        g.draw(FMArt.image(tier), in: CGRect(x: -s, y: -s, width: s * 2, height: s * 2))
    }

    // MARK: Input

    private func aimGesture(_ l: Lay) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard phase == .play else { return }
                aiming = true
                aimX = Double((v.location.x - l.box.minX) / l.unit)
            }
            .onEnded { v in
                guard phase == .play else { return }
                aimX = Double((v.location.x - l.box.minX) / l.unit)
                aiming = false
                drop()
            }
    }

    private func drop() {
        guard phase == .play, Date().timeIntervalSince(lastDrop) > 0.45 || isDemo else { return }
        lastDrop = Date()
        world.add(tier: current, x: aimX)
        current = upcoming
        upcoming = Int.random(in: 0..<5)
        SoundManager.shared.tap(); Haptics.tap()
    }

    // MARK: Flow

    private func handleMerges() {
        for m in world.merges {
            splashes.append((m.p, m.tier, clock))
            SoundManager.shared.tap()
            Haptics.tap()
            if m.tier >= goal && phase == .play {
                wonTier = m.tier
                phase = .won
            }
        }
        splashes.removeAll { clock - $0.t0 > 0.5 }
    }

    /// Drops the level's seed fruit in one by one and lets them settle, off the main actor.
    private nonisolated static func seededWorld(_ seeds: [Int], goal: Int) -> FMWorld {
        for _ in 0..<20 {
            var w = FMWorld()
            var reachedGoal = false
            for tier in seeds {
                w.add(tier: tier, x: Double.random(in: 0.1...0.9), y: 0.1)
                for _ in 0..<24 { w.step(1.0 / 60); if w.merges.contains(where: { $0.tier >= goal }) { reachedGoal = true } }
            }
            for _ in 0..<90 { w.step(1.0 / 60); if w.merges.contains(where: { $0.tier >= goal }) { reachedGoal = true } }
            if !reachedGoal && w.fruits.allSatisfy({ $0.p.y - $0.r > 0.05 }) {
                for i in w.fruits.indices { w.fruits[i].age = 2 }
                return w
            }
        }
        return FMWorld()
    }

    private func run() async {
        FMArt.warm()
        let s = seeds, g = goal
        let seeded = await Task.detached(priority: .userInitiated) { Self.seededWorld(s, goal: g) }.value
        guard !Task.isCancelled else { return }
        world = seeded
        current = Int.random(in: 0..<5)
        upcoming = Int.random(in: 0..<5)
        aimX = 0.5
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
            // Fixed 1/60 s physics steps regardless of frame timing.
            while acc >= 1.0 / 60 {
                acc -= 1.0 / 60
                world.step(1.0 / 60)
                clock += 1.0 / 60
                handleMerges()
            }
            switch phase {
            case .play:
                timeLeft = max(0, timeLimit - now.timeIntervalSince(start))
                if world.maxOver > overLimit || timeLeft <= 0 { fail(); return }
            case .won:
                // Let the goal fruit pop and settle for a beat before reporting the win.
                try? await Task.sleep(for: .seconds(0.7))
                guard !Task.isCancelled else { return }
                phase = .done
                onWin()
                return
            case .loading, .done:
                break
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
    // Level 1 (goal: apple) from a fixed, pre-settled box. The finger drags over and drops a cherry
    // onto the cherry (→ strawberry), then a persimmon onto the persimmon: the new apple pops into
    // being right against the resting apple, and the two merge again into a pear. Stepped at a fixed
    // 1/60 s through the real `FMWorld`, so the chain replays identically every loop.
    private nonisolated static let demoSeeds: [(tier: Int, x: Double)] = [
        (5, 0.14), (4, 0.36), (1, 0.62), (0, 0.84), (2, 0.9), (3, 0.6),
    ]
    private static let demoDrops: [(tier: Int, x: Double)] = [(0, 0.84), (4, 0.36)]

    private nonisolated static func demoWorld() -> FMWorld {
        var w = FMWorld()
        for s in demoSeeds {
            w.add(tier: s.tier, x: s.x, y: 0.1)
            for _ in 0..<30 { w.step(1.0 / 60) }
        }
        for _ in 0..<120 { w.step(1.0 / 60) }
        for i in w.fruits.indices { w.fruits[i].age = 2 }
        return w
    }

    private func runDemo() async {
        FMArt.warm()
        let base = Self.demoWorld()
        while !Task.isCancelled {
            world = base
            clock = 0
            splashes = []
            phase = .play
            current = Self.demoDrops[0].tier
            upcoming = Self.demoDrops[1].tier
            aimX = 0.5
            demoFinger = nil
            try? await Task.sleep(for: .seconds(0.5))
            for (k, d) in Self.demoDrops.enumerated() {
                guard !Task.isCancelled else { return }
                current = d.tier
                upcoming = k + 1 < Self.demoDrops.count ? Self.demoDrops[k + 1].tier : 2
                // Finger slides over the target column, then lets go.
                let fromX = aimX
                demoPressed = true
                for s in 1...24 {
                    let t = Double(s) / 24
                    aimX = fromX + (d.x - fromX) * (t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2)
                    demoFinger = SIMD2(aimX, FMWorld.dropY + 0.12)
                    await demoFrames(1)
                }
                await demoFrames(8)
                world.add(tier: current, x: aimX)
                current = upcoming          // the next fruit moves up to the dropper, as in play
                demoPressed = false
                await demoFrames(k == 0 ? 70 : 110)
            }
            demoFinger = nil
            await demoFrames(60)
        }
    }

    /// Advances the demo `n` fixed physics frames at real time.
    private func demoFrames(_ n: Int) async {
        for _ in 0..<n {
            guard !Task.isCancelled else { return }
            world.step(1.0 / 60)
            clock += 1.0 / 60
            handleMergesDemo()
            try? await Task.sleep(for: .seconds(1.0 / 60))
        }
    }

    private func handleMergesDemo() {
        for m in world.merges { splashes.append((m.p, m.tier, clock)) }
        splashes.removeAll { clock - $0.t0 > 0.5 }
    }
}
