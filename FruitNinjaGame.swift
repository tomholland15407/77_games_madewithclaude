//
//  FruitNinjaGame.swift
//  A Banana Game
//
//  Reflex (swipe) — a Fruit Ninja homage. Fruit is tossed up in arcs; SWIPE across it
//  to slice, and never slice a bomb. Slice the level's quota of fruit to win; slice a
//  bomb, or let three fruit fall past unsliced, and you fail back to level 1. A glowing
//  blade trail follows your finger and juice sprays on every cut. 7 levels: more fruit
//  per toss, faster arcs, and more bombs — from a lit dojo to a volcanic red glow.
//
//  Swiping fights the feed's vertical pager, so this game sets `locksFeed: true` (the
//  page locks paging while playing and shows a skip button).
//
//  Drawn as Fruit Ninja Classic: a wooden dojo board with knife scars and a faint ink wave that
//  darkens into a volcanic glow, FruitArt fruit (watermelon, orange, apple, lemon, strawberry,
//  pineapple — each `fruitColors` entry is one kind) that split into halves showing their flesh,
//  juice that sprays and stains the board, a tapered white blade swoosh, dark bombs with a red
//  brush mark and a sparking fuse (a sliced one whites out the board), and the HUD: a watermelon
//  and the slice count, and three ✕ that turn red as fruit falls.
//

import SwiftUI

enum FruitNinjaGame {
    static let definition = GameDefinition(
        id: "fruit-ninja",
        title: "Juice Blade",
        emoji: "🍌",
        genre: .reflex,
        levelCount: 7,
        locksFeed: true,
        manual: GameManual(
            bullets: [
                "Fruit is tossed up in arcs — swipe across it to slice.",
                "Never slice a bomb.",
                "Slice the level's quota of fruit to win.",
                "Slice a bomb, or let three fruit fall past unsliced, and you're back to level 1.",
            ],
            bulletsVI: [
                "Trái cây được tung lên theo vòng cung — vuốt ngang qua để chém.",
                "Đừng bao giờ chém trúng bom.",
                "Chém đủ số trái cây của cấp để thắng.",
                "Chém trúng bom, hoặc để ba quả rơi qua chưa chém, sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(FruitNinjaView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

// Each colour is one fruit kind (FNArt.kinds, same order); the colour itself is only a key.
private let fruitColors: [Color] = [
    Color(red: 0.30, green: 0.75, blue: 0.35),
    Color(red: 1.00, green: 0.60, blue: 0.15),
    Color(red: 0.90, green: 0.25, blue: 0.30),
    Color(red: 0.60, green: 0.85, blue: 0.25),
    Color(red: 0.75, green: 0.45, blue: 1.00),
    Color(red: 0.30, green: 0.80, blue: 0.85)
]

struct FruitNinjaView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    // MARK: Difficulty
    private var target: Int { [5, 7, 9, 11, 13, 16, 20][min(level, 7) - 1] }
    private var spawnInterval: Double { [1.5, 1.35, 1.2, 1.05, 0.9, 0.78, 0.68][min(level, 7) - 1] }
    private var groupLo: Int { [1, 1, 1, 2, 2, 2, 3][min(level, 7) - 1] }
    private var groupHi: Int { [2, 2, 3, 3, 4, 4, 5][min(level, 7) - 1] }
    private var bombChance: Double { [0.0, 0.14, 0.22, 0.30, 0.38, 0.47, 0.56][min(level, 7) - 1] }
    private var launchSpeed: CGFloat { [1.35, 1.42, 1.5, 1.58, 1.66, 1.74, 1.82][min(level, 7) - 1] }

    private let gravity: CGFloat = 1.5
    private let sliceRadius: CGFloat = 0.09
    private let maxMisses = 3

    // MARK: State
    private struct Fruit: Identifiable {
        let id = UUID()
        var pos: CGPoint
        var vel: CGVector
        let isBomb: Bool
        let color: Color
        var rot: CGFloat
        let spin: CGFloat
    }
    private struct Burst: Identifiable { let id = UUID(); let pos: CGPoint; let color: Color }

    @State private var fruits: [Fruit] = []
    @State private var bursts: [Burst] = []
    @State private var trail: [CGPoint] = []
    @State private var sliced = 0
    @State private var misses = 0
    @State private var spawnAccum = 0.0
    @State private var done = false
    @State private var loopTask: Task<Void, Never>?
    @State private var demoToss = 0                 // demo: index into the fixed toss script
    @State private var demoTrail: [CGPoint] = []    // demo: blade trail in field fractions

    // Presentation only: fruit halves, juice stains, the bomb flash, and a counter that schedules pruning.
    @State private var halves: [FNHalf] = []
    @State private var splats: [FNSplat] = []
    @State private var boom: FNBoom? = nil
    @State private var fxSerial = 0

    var body: some View {
        VStack(spacing: 4) {
            if !isDemo {
                FNHud(sliced: sliced, target: target, misses: misses, maxMisses: maxMisses, scale: 1)
                    .frame(height: 51)
            }

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                ZStack {
                    // Stains, fruit, halves, juice, the blade and the bomb flash: one Canvas. The timeline
                    // only runs while halves fly or stains fade (the fruit move by themselves).
                    TimelineView(.animation(paused: halves.isEmpty && splats.isEmpty && boom == nil)) { tl in
                        Canvas { ctx, size in
                            // Reading the timeline's date is what redraws the Canvas on each tick; the
                            // wall clock keeps the fuse sparks live while the timeline is paused.
                            drawScene(ctx, size: size, now: max(tl.date.timeIntervalSinceReferenceDate, Date().timeIntervalSinceReferenceDate))
                        } symbols: {
                            ForEach(FNArt.kinds.indices, id: \.self) { k in
                                FNFruitSymbol(kind: FNArt.kinds[k], radius: FNArt.radius(k) * w).tag(k)
                            }
                            FNBombSymbol(radius: FNArt.bombRadius * w).tag(99)
                        }
                    }

                    // Demo: the finger at the tip of the scripted swipe.
                    if isDemo && demoTrail.count > 1, let tip = demoTrail.last {
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 3)
                            .position(x: tip.x * w + 10, y: tip.y * h + 14)
                    }
                    if isDemo {
                        FNHud(sliced: sliced, target: target, misses: misses, maxMisses: maxMisses, scale: 0.62)
                            .frame(height: 34)
                            .padding(.horizontal, 6)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: w, height: h)
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            guard !done else { return }
                            trail.append(v.location)
                            if trail.count > 14 { trail.removeFirst() }
                            sliceAt(fx: v.location.x / w, fy: v.location.y / h)
                        }
                        .onEnded { _ in trail = [] }
                )
                // `sliceAt` adds a burst per sliced fruit: split it into halves and splash the board.
                .onChange(of: bursts.count) { old, new in
                    guard new > old else { return }
                    for b in bursts.suffix(new - old) { spawnSlice(b, size: geo.size) }
                    bursts.removeAll()
                }
                // Ending with fruit left and misses to spare means a bomb was cut: white-out from it.
                .onChange(of: done) { _, isDone in
                    guard isDone, sliced < target, misses < maxMisses else { return }
                    let tip = isDemo ? demoTrail.last
                        : trail.last.map { CGPoint(x: $0.x / max(1, geo.size.width), y: $0.y / max(1, geo.size.height)) }
                    let t = tip ?? CGPoint(x: 0.5, y: 0.5)
                    let at = fruits.filter(\.isBomb)
                        .min(by: { hypot($0.pos.x - t.x, $0.pos.y - t.y) < hypot($1.pos.x - t.x, $1.pos.y - t.y) })?.pos ?? t
                    boom = FNBoom(pos: at, born: Date().timeIntervalSinceReferenceDate)
                    fxSerial += 1
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FNDojo(level: level).equatable())
        .overlay(VignetteOverlay(strength: 0.35))
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
        .task(id: fxSerial) {
            try? await Task.sleep(for: .seconds(2.6))
            let cut = Date().timeIntervalSinceReferenceDate - 2.5
            halves.removeAll { $0.born < cut }
            splats.removeAll { $0.born < cut }
            if let b = boom, b.born < cut { boom = nil }
        }
    }

    /// Two halves flying apart across the blade's line, a juice stain and a spray of drops.
    private func spawnSlice(_ b: Burst, size: CGSize) {
        let k = fruitColors.firstIndex(of: b.color) ?? 0
        let pts: [CGPoint] = isDemo ? demoTrail.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) } : trail
        var ang = 0.3
        if pts.count >= 2 {
            let a = pts[pts.count - 2], c = pts[pts.count - 1]
            if hypot(c.x - a.x, c.y - a.y) > 0.5 { ang = atan2(Double(c.y - a.y), Double(c.x - a.x)) }
        }
        let now = Date().timeIntervalSinceReferenceDate
        for side in [-1.0, 1.0] {
            // Push each half away from the cut line (its normal), with a little hop.
            let nx = -sin(ang) * side, ny = cos(ang) * side
            halves.append(FNHalf(kind: k, p0: b.pos, v0: CGVector(dx: nx * 0.22, dy: ny * 0.22 - 0.12),
                                 cut: ang, side: side, spin: side * 2.4, born: now))
        }
        splats.append(FNSplat(kind: k, pos: b.pos, seed: Double(splats.count % 97) + now.truncatingRemainder(dividingBy: 13), born: now))
        fxSerial += 1
    }

    private func drawScene(_ ctx: GraphicsContext, size: CGSize, now: Double) {
        let w = size.width, h = size.height
        for s in splats { FNArt.stain(ctx, s, size: size, now: now) }

        for f in fruits {
            let c = CGPoint(x: f.pos.x * w, y: f.pos.y * h)
            if f.isBomb {
                FNArt.bombHalo(ctx, at: c, radius: FNArt.bombRadius * w, now: now)
                var g = ctx
                g.translateBy(x: c.x, y: c.y)
                g.rotate(by: .radians(Double(f.rot) * 0.4))
                if let sym = g.resolveSymbol(id: 99) { g.draw(sym, at: .zero) }
                FNArt.fuseSpark(g, radius: FNArt.bombRadius * w, now: now)
            } else {
                let k = fruitColors.firstIndex(of: f.color) ?? 0
                var g = ctx
                g.translateBy(x: c.x, y: c.y)
                g.rotate(by: .radians(Double(f.rot)))
                if let sym = g.resolveSymbol(id: k) { g.draw(sym, at: .zero) }
            }
        }

        for half in halves {
            let age = now - half.born
            guard age >= 0, age < 2.5 else { continue }
            let t = CGFloat(age)
            let p = CGPoint(x: (half.p0.x + half.v0.dx * t) * w, y: (half.p0.y + half.v0.dy * t + 0.5 * gravity * t * t) * h)
            guard p.y < h + 80 else { continue }
            FNArt.half(ctx, half, at: p, radius: FNArt.radius(half.kind) * w, age: age)
        }
        for s in splats { FNArt.spray(ctx, s, size: size, now: now) }

        let blade = isDemo ? demoTrail.map { CGPoint(x: $0.x * w, y: $0.y * h) } : trail
        FNArt.blade(ctx, blade, width: max(9, w * 0.028))

        if let b = boom { FNArt.boom(ctx, b, size: size, now: now) }
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
        fruits = []; bursts = []; trail = []
        sliced = 0; misses = 0; spawnAccum = 0; done = false
    }

    private func step(dt: CGFloat) {
        guard !done else { return }
        for i in fruits.indices {
            fruits[i].vel.dy += gravity * dt
            fruits[i].pos.x += fruits[i].vel.dx * dt
            fruits[i].pos.y += fruits[i].vel.dy * dt
            fruits[i].rot += fruits[i].spin * dt
        }

        let fell = fruits.filter { $0.pos.y > 1.12 && !$0.isBomb }.count
        if fell > 0 { misses += fell }
        fruits.removeAll { $0.pos.y > 1.12 }
        if misses >= maxMisses { fail(); return }

        spawnAccum += Double(dt)
        if spawnAccum >= spawnInterval {
            spawnAccum -= spawnInterval
            toss()
        }
    }

    // MARK: - Demo (live manual clip)
    // Level 1 (5 fruit, no bombs) on a fixed toss script, stepped at a fixed 1/60s through the
    // real `step`. The finger swipes each fruit near the top of its arc — a quick diagonal stroke
    // whose points go through the real `sliceAt` and draw the blade trail. The 5th slice → win().
    private static let demoTosses: [[(x: CGFloat, dx: CGFloat, up: CGFloat)]] = [
        [(0.38, 0.10, 1.35)],
        [(0.28, 0.12, 1.30), (0.70, -0.10, 1.40)],
        [(0.62, -0.08, 1.33), (0.34, 0.14, 1.38)],
    ]

    private func runDemo() async {
        let dt: CGFloat = 1.0 / 60.0
        while !Task.isCancelled {
            setup()
            demoToss = 0; demoTrail = []
            spawnAccum = spawnInterval - 0.4          // first toss comes quickly in the clip
            try? await Task.sleep(for: .seconds(0.3))
            var swipe: (from: CGPoint, to: CGPoint, k: Int)? = nil
            var linger = 0
            while !Task.isCancelled && !done {
                step(dt: dt)
                if let sw = swipe {
                    // Advance the stroke; every point is a real slice test.
                    let f = CGFloat(sw.k) / 7
                    let p = CGPoint(x: sw.from.x + (sw.to.x - sw.from.x) * f, y: sw.from.y + (sw.to.y - sw.from.y) * f)
                    demoTrail.append(p)
                    sliceAt(fx: p.x, fy: p.y)
                    swipe = sw.k >= 7 ? nil : (sw.from, sw.to, sw.k + 1)
                    if swipe == nil { linger = 8 }
                } else if linger > 0 {
                    linger -= 1
                    if linger == 0 { demoTrail = [] }
                } else if let f = fruits.filter({ !$0.isBomb && $0.vel.dy > -0.35 && $0.pos.y < 0.85 })
                            .min(by: { $0.vel.dy < $1.vel.dy }) {
                    // Swipe up-and-across through where it'll be mid-stroke.
                    let c = CGPoint(x: f.pos.x + f.vel.dx * 0.06, y: f.pos.y + f.vel.dy * 0.06)
                    swipe = (CGPoint(x: c.x - 0.14, y: c.y + 0.07), CGPoint(x: c.x + 0.14, y: c.y - 0.07), 0)
                    demoTrail = []
                }
                try? await Task.sleep(for: .seconds(0.016))
            }
            // Quota sliced → the real win() ran (onWin is a no-op). Hold, then loop.
            try? await Task.sleep(for: .seconds(0.25))
            demoTrail = []
            try? await Task.sleep(for: .seconds(1.1))
        }
    }

    private func toss() {
        if isDemo {
            let group = Self.demoTosses[demoToss % Self.demoTosses.count]
            demoToss += 1
            for (i, t) in group.enumerated() {
                fruits.append(Fruit(pos: CGPoint(x: t.x, y: 1.1), vel: CGVector(dx: t.dx, dy: -t.up),
                                    isBomb: false, color: fruitColors[(demoToss * 2 + i) % fruitColors.count],
                                    rot: 0, spin: i == 0 ? 2.2 : -1.8))
            }
            return
        }
        let count = Int.random(in: groupLo...groupHi)
        for k in 0..<count {
            let isBomb = k == 0 ? false : (Double.random(in: 0..<1) < bombChance)
            let x = CGFloat.random(in: 0.2...0.8)
            let dx = CGFloat.random(in: -0.22...0.22)
            let up = launchSpeed * CGFloat.random(in: 0.9...1.05)
            fruits.append(Fruit(pos: CGPoint(x: x, y: 1.1),
                                vel: CGVector(dx: dx, dy: -up),
                                isBomb: isBomb,
                                color: fruitColors.randomElement() ?? .green,
                                rot: 0,
                                spin: CGFloat.random(in: -3...3)))
        }
    }

    private func sliceAt(fx: CGFloat, fy: CGFloat) {
        guard let i = fruits.firstIndex(where: {
            !$0.isBomb && hypot(fx - $0.pos.x, fy - $0.pos.y) < sliceRadius
        }) ?? fruits.firstIndex(where: {
            $0.isBomb && hypot(fx - $0.pos.x, fy - $0.pos.y) < sliceRadius
        }) else { return }

        let f = fruits[i]
        if f.isBomb { fail(); return }
        fruits.remove(at: i)
        sliced += 1
        Haptics.tap(); SoundManager.shared.tap()
        bursts.append(Burst(pos: f.pos, color: f.color))
        if sliced >= target { win() }
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

// MARK: - Fruit Ninja art

/// One half of a sliced fruit, flying on its own arc (field fractions, seconds).
private struct FNHalf {
    let kind: Int
    let p0: CGPoint
    let v0: CGVector
    let cut: Double          // the blade's angle across the fruit
    let side: Double         // which side of the cut this half is
    let spin: Double
    let born: Double
}

/// A juice splash: drops fly out, and a stain stays on the board a moment.
private struct FNSplat {
    let kind: Int
    let pos: CGPoint
    let seed: Double
    let born: Double
}

/// A sliced bomb whiting out the board.
private struct FNBoom {
    let pos: CGPoint
    let born: Double
}

private enum FNArt {
    /// The fruit for each `fruitColors` entry, in the same order.
    static let kinds: [FruitKind] = [.watermelon, .dekopon, .apple, .lemon, .strawberry, .pineapple]
    static let bombRadius: CGFloat = 0.066
    /// Body radius as a fraction of the field width (all inside the 0.09 slice radius).
    static func radius(_ k: Int) -> CGFloat { [0.085, 0.07, 0.07, 0.066, 0.062, 0.066][max(0, k) % 6] }

    static func juice(_ k: Int) -> Color {
        [Color(red: 0.9, green: 0.1, blue: 0.16), Color(red: 1, green: 0.55, blue: 0.08), Color(red: 0.98, green: 0.9, blue: 0.62),
         Color(red: 1, green: 0.88, blue: 0.24), Color(red: 0.94, green: 0.12, blue: 0.24), Color(red: 1, green: 0.8, blue: 0.2)][max(0, k) % 6]
    }

    static func hash(_ n: Double) -> Double {
        let v = sin(n * 12.9898) * 43758.5453
        return v - floor(v)
    }

    // MARK: Juice

    static func stain(_ ctx: GraphicsContext, _ s: FNSplat, size: CGSize, now: Double) {
        let age = now - s.born
        guard age >= 0, age < 2.5 else { return }
        let a = age < 0.08 ? age / 0.08 : max(0, min(1, 1 - (age - 0.7) / 1.8))
        let c = CGPoint(x: s.pos.x * size.width, y: s.pos.y * size.height)
        let r = size.width * 0.07
        var p = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 0.8, width: r * 2, height: r * 1.6))
        for i in 0..<8 {
            let k = s.seed * 7 + Double(i)
            let ang = hash(k) * 2 * .pi, dist = r * CGFloat(0.8 + hash(k + 1) * 0.9), rr = r * CGFloat(0.1 + hash(k + 2) * 0.22)
            let q = CGPoint(x: c.x + CGFloat(cos(ang)) * dist, y: c.y + CGFloat(sin(ang)) * dist)
            p.addEllipse(in: CGRect(x: q.x - rr, y: q.y - rr, width: rr * 2, height: rr * 2))
        }
        ctx.fill(p, with: .color(juice(s.kind).opacity(0.5 * a)))
    }

    static func spray(_ ctx: GraphicsContext, _ s: FNSplat, size: CGSize, now: Double) {
        let age = now - s.born
        guard age >= 0, age < 0.7 else { return }
        let c = CGPoint(x: s.pos.x * size.width, y: s.pos.y * size.height)
        let t = CGFloat(age)
        var p = Path()
        for i in 0..<14 {
            let k = s.seed * 11 + Double(i)
            let ang = hash(k) * 2 * .pi, sp = size.width * CGFloat(0.35 + hash(k + 3) * 0.55)
            let q = CGPoint(x: c.x + CGFloat(cos(ang)) * sp * t, y: c.y + CGFloat(sin(ang)) * sp * t + 0.5 * 1.5 * size.height * t * t)
            let rr = CGFloat(1.6 + hash(k + 5) * 2.6)
            p.addEllipse(in: CGRect(x: q.x - rr, y: q.y - rr, width: rr * 2, height: rr * 2))
        }
        ctx.fill(p, with: .color(juice(s.kind).opacity(max(0, 1 - age / 0.7))))
    }

    // MARK: Halves

    /// A half fruit at the origin: the fruit clipped to one side of the cut, with its flesh showing.
    static func drawHalf(_ ctx: GraphicsContext, kind k: Int, radius r: CGFloat, side: Double) {
        let clip = Path(CGRect(x: -r * 2, y: side > 0 ? -0.5 : -r * 2 + 0.5, width: r * 4, height: r * 2))
        var g = ctx
        g.clip(to: clip)
        FruitArt.draw(kinds[max(0, k) % 6], in: g, at: .zero, radius: r)
        let face = Path(ellipseIn: CGRect(x: -r * 0.9, y: -r * 0.38, width: r * 1.8, height: r * 0.76))
        let flesh = juice(k)
        switch max(0, k) % 6 {
        case 0:   // watermelon: pale rind band, red flesh, black seeds
            g.fill(face, with: .color(Color(red: 0.88, green: 0.97, blue: 0.72)))
            g.fill(Path(ellipseIn: CGRect(x: -r * 0.8, y: -r * 0.3, width: r * 1.6, height: r * 0.6)),
                   with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.36, blue: 0.36), Color(red: 0.86, green: 0.08, blue: 0.14)]),
                                         startPoint: CGPoint(x: 0, y: -r * 0.3), endPoint: CGPoint(x: 0, y: r * 0.3)))
            for i in 0..<6 {
                let x = -r * 0.55 + r * 0.22 * CGFloat(i), y = CGFloat(side) * r * (0.1 + 0.06 * CGFloat(i % 2))
                g.fill(Path(ellipseIn: CGRect(x: x - r * 0.04, y: y - r * 0.06, width: r * 0.08, height: r * 0.12)), with: .color(Color(red: 0.1, green: 0.06, blue: 0.05)))
            }
        case 2:   // apple: cream flesh, two pips
            g.fill(face, with: .color(Color(red: 1, green: 0.95, blue: 0.8)))
            g.stroke(face, with: .color(Color(red: 0.85, green: 0.1, blue: 0.14)), lineWidth: max(1, r * 0.08))
            for x in [-0.12, 0.12] as [CGFloat] {
                g.fill(Path(ellipseIn: CGRect(x: r * x - r * 0.05, y: CGFloat(side) * r * 0.12 - r * 0.07, width: r * 0.1, height: r * 0.14)),
                       with: .color(Color(red: 0.4, green: 0.22, blue: 0.08)))
            }
        case 4:   // strawberry: red with a pale heart
            g.fill(face, with: .color(flesh))
            g.fill(Path(ellipseIn: CGRect(x: -r * 0.45, y: -r * 0.18, width: r * 0.9, height: r * 0.36)), with: .color(Color(red: 1, green: 0.78, blue: 0.8)))
        case 5:   // pineapple: gold flesh, pale core
            g.fill(face, with: .color(Color(red: 1, green: 0.86, blue: 0.34)))
            g.fill(Path(ellipseIn: CGRect(x: -r * 0.22, y: -r * 0.12, width: r * 0.44, height: r * 0.24)), with: .color(Color(red: 1, green: 0.96, blue: 0.72)))
        default:  // orange / lemon: pith ring and segments
            g.fill(face, with: .color(Color(red: 1, green: 0.96, blue: 0.84)))
            let inner = Path(ellipseIn: CGRect(x: -r * 0.8, y: -r * 0.3, width: r * 1.6, height: r * 0.6))
            g.fill(inner, with: .color(flesh))
            var seg = Path()
            for i in 0..<6 {
                let a = Double(i) / 6 * .pi * 2
                seg.move(to: .zero)
                seg.addLine(to: CGPoint(x: CGFloat(cos(a)) * r * 0.8, y: CGFloat(sin(a)) * r * 0.3))
            }
            g.stroke(seg, with: .color(.white.opacity(0.6)), lineWidth: max(0.8, r * 0.04))
        }
        g.stroke(face, with: .color(.black.opacity(0.18)), lineWidth: 1)
    }

    static func half(_ ctx: GraphicsContext, _ hf: FNHalf, at p: CGPoint, radius r: CGFloat, age: Double) {
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        g.rotate(by: .radians(hf.cut + hf.spin * age))
        g.opacity = age > 1.8 ? max(0, (2.5 - age) / 0.7) : 1
        drawHalf(g, kind: hf.kind, radius: r, side: hf.side)
    }

    // MARK: Blade

    /// The swoosh: pointed at both ends, widest near the finger, with a pale blue sheen.
    static func blade(_ ctx: GraphicsContext, _ pts: [CGPoint], width: CGFloat) {
        let n = pts.count
        guard n >= 2 else { return }
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in 0..<n {
            let a = pts[max(0, i - 1)], b = pts[min(n - 1, i + 1)]
            let len = max(0.001, hypot(b.x - a.x, b.y - a.y))
            let dx = (b.x - a.x) / len, dy = (b.y - a.y) / len
            let f = Double(i) / Double(n - 1)
            let hw = width * 0.5 * CGFloat(sin(.pi * pow(f, 0.62)))
            left.append(CGPoint(x: pts[i].x - dy * hw, y: pts[i].y + dx * hw))
            right.append(CGPoint(x: pts[i].x + dy * hw, y: pts[i].y - dx * hw))
        }
        var poly = Path()
        poly.addLines(left + right.reversed())
        poly.closeSubpath()
        ctx.stroke(poly, with: .color(Color(red: 0.7, green: 0.88, blue: 1).opacity(0.35)), style: StrokeStyle(lineWidth: width * 0.8, lineJoin: .round))
        ctx.fill(poly, with: .color(.white))
    }

    // MARK: Bombs

    static func bombHalo(_ ctx: GraphicsContext, at c: CGPoint, radius r: CGFloat, now: Double) {
        let pulse = CGFloat(1.35 + 0.1 * sin(now * 9))
        let rr = r * pulse
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)),
                 with: .radialGradient(Gradient(colors: [Color.red.opacity(0.55), Color.red.opacity(0)]),
                                       center: c, startRadius: r * 0.8, endRadius: rr))
    }

    /// The flickering spark at the fuse tip, in the bomb's own (rotated) frame.
    static func fuseSpark(_ g: GraphicsContext, radius r: CGFloat, now: Double) {
        let tip = CGPoint(x: r * 0.92, y: -r * 1.22)
        let flick = Int(now * 20)
        g.fill(Path(ellipseIn: CGRect(x: tip.x - r * 0.3, y: tip.y - r * 0.3, width: r * 0.6, height: r * 0.6)),
               with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.8, blue: 0.3).opacity(0.8), .clear]),
                                     center: tip, startRadius: 0, endRadius: r * 0.3))
        var rays = Path()
        for i in 0..<7 {
            let a = Double(i) / 7 * 2 * .pi + Double(flick) * 0.7
            let len = r * CGFloat(0.16 + hash(Double(flick * 7 + i)) * 0.26)
            rays.move(to: tip)
            rays.addLine(to: CGPoint(x: tip.x + CGFloat(cos(a)) * len, y: tip.y + CGFloat(sin(a)) * len))
        }
        g.stroke(rays, with: .color(Color(red: 1, green: 0.92, blue: 0.5)), style: StrokeStyle(lineWidth: max(1, r * 0.05), lineCap: .round))
        g.fill(Path(ellipseIn: CGRect(x: tip.x - r * 0.07, y: tip.y - r * 0.07, width: r * 0.14, height: r * 0.14)), with: .color(.white))
    }

    static func boom(_ ctx: GraphicsContext, _ b: FNBoom, size: CGSize, now: Double) {
        let age = now - b.born
        guard age >= 0, age < 1.4 else { return }
        let w = size.width, h = size.height
        let c = CGPoint(x: b.pos.x * w, y: b.pos.y * h)
        let fade = max(0, 1 - age / 1.4)
        var rays = Path()
        let far = max(w, h) * 1.5
        for i in 0..<12 {
            let a = Double(i) / 12 * 2 * .pi + age * 0.5
            rays.move(to: c)
            rays.addLine(to: CGPoint(x: c.x + CGFloat(cos(a - 0.08)) * far, y: c.y + CGFloat(sin(a - 0.08)) * far))
            rays.addLine(to: CGPoint(x: c.x + CGFloat(cos(a + 0.08)) * far, y: c.y + CGFloat(sin(a + 0.08)) * far))
            rays.closeSubpath()
        }
        ctx.fill(rays, with: .color(.white.opacity(0.6 * fade)))
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(max(0, 0.8 - age * 1.1))))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - w * 0.3, y: c.y - w * 0.3, width: w * 0.6, height: w * 0.6)),
                 with: .radialGradient(Gradient(colors: [.white.opacity(fade), .white.opacity(0)]), center: c, startRadius: 0, endRadius: w * 0.3))
    }
}

/// A FruitArt fruit rendered once and stamped by the scene Canvas.
private struct FNFruitSymbol: View {
    let kind: FruitKind
    let radius: CGFloat

    var body: some View {
        Canvas { ctx, size in
            FruitArt.draw(kind, in: ctx, at: CGPoint(x: size.width / 2, y: size.height / 2), radius: radius)
        }
        .frame(width: max(1, radius * 3.2), height: max(1, radius * 3.2))
    }
}

/// The bomb: a dark glossy ball with a red brush mark, an iron cap and a fuse (the spark is animated
/// by the scene).
private struct FNBombSymbol: View {
    let radius: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let r = radius
            var g = ctx
            g.translateBy(x: size.width / 2, y: size.height / 2)
            var fuse = Path()
            fuse.move(to: CGPoint(x: r * 0.62, y: -r * 0.84))
            fuse.addQuadCurve(to: CGPoint(x: r * 0.92, y: -r * 1.22), control: CGPoint(x: r * 0.95, y: -r * 0.9))
            g.stroke(fuse, with: .color(Color(red: 0.28, green: 0.2, blue: 0.12)), style: StrokeStyle(lineWidth: r * 0.14, lineCap: .round))
            g.stroke(fuse, with: .color(Color(red: 0.78, green: 0.62, blue: 0.38)), style: StrokeStyle(lineWidth: r * 0.07, lineCap: .round))
            var cap = g
            cap.translateBy(x: r * 0.5, y: -r * 0.72)
            cap.rotate(by: .degrees(38))
            cap.fill(Path(roundedRect: CGRect(x: -r * 0.2, y: -r * 0.13, width: r * 0.4, height: r * 0.26), cornerRadius: r * 0.05),
                     with: .linearGradient(Gradient(colors: [Color(white: 0.55), Color(white: 0.22)]),
                                           startPoint: CGPoint(x: 0, y: -r * 0.13), endPoint: CGPoint(x: 0, y: r * 0.13)))
            let ball = Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
            g.fill(ball, with: .radialGradient(Gradient(colors: [Color(red: 0.36, green: 0.38, blue: 0.48), Color(red: 0.1, green: 0.1, blue: 0.15), Color(red: 0.02, green: 0.02, blue: 0.04)]),
                                               center: CGPoint(x: -r * 0.35, y: -r * 0.4), startRadius: 0, endRadius: r * 1.5))
            // The red brush mark: two tapered strokes crossing.
            for (a, b) in [(CGPoint(x: -r * 0.52, y: -r * 0.3), CGPoint(x: r * 0.5, y: r * 0.42)),
                           (CGPoint(x: r * 0.36, y: -r * 0.5), CGPoint(x: -r * 0.3, y: r * 0.5))] {
                let dx = b.x - a.x, dy = b.y - a.y, len = hypot(dx, dy)
                let nx = -dy / len * r * 0.13, ny = dx / len * r * 0.13
                var stroke = Path()
                stroke.move(to: a)
                stroke.addQuadCurve(to: b, control: CGPoint(x: (a.x + b.x) / 2 + nx, y: (a.y + b.y) / 2 + ny))
                stroke.addQuadCurve(to: a, control: CGPoint(x: (a.x + b.x) / 2 - nx, y: (a.y + b.y) / 2 - ny))
                g.fill(stroke, with: .color(Color(red: 0.88, green: 0.08, blue: 0.1)))
            }
            g.stroke(ball, with: .color(.black), lineWidth: r * 0.07)
            g.fill(Path(ellipseIn: CGRect(x: -r * 0.62, y: -r * 0.68, width: r * 0.42, height: r * 0.24)), with: .color(.white.opacity(0.35)))
        }
        .frame(width: max(1, radius * 3.2), height: max(1, radius * 3.2))
    }
}

/// The HUD: a sliced watermelon with the count in Fruit Ninja's gold, and the three misses as ✕s
/// that turn red from the smallest up.
private struct FNHud: View {
    let sliced: Int
    let target: Int
    let misses: Int
    let maxMisses: Int
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 8 * scale) {
            Canvas { ctx, size in
                var g = ctx
                g.translateBy(x: size.width / 2, y: size.height * 0.56)
                g.rotate(by: .degrees(-24))
                FNArt.drawHalf(g, kind: 0, radius: size.width * 0.42, side: 1)
            }
            .frame(width: 40 * scale, height: 40 * scale)
            FNScoreText(text: "\(sliced)/\(target)", size: 30 * scale)
            Spacer(minLength: 0)
            Canvas { ctx, size in
                var x = size.width
                for i in (0..<maxMisses).reversed() {
                    let s = size.height * [0.58, 0.78, 1.0][min(2, i)]
                    x -= s * 0.5
                    FNHud.cross(ctx, at: CGPoint(x: x, y: size.height / 2), size: s, used: i < misses)
                    x -= s * 0.5 + 3
                }
            }
            .frame(width: 88 * scale, height: 30 * scale)
        }
        .padding(.horizontal, 14 * scale)
    }

    static func cross(_ ctx: GraphicsContext, at c: CGPoint, size s: CGFloat, used: Bool) {
        var x = Path()
        x.move(to: CGPoint(x: c.x - s * 0.34, y: c.y - s * 0.34)); x.addLine(to: CGPoint(x: c.x + s * 0.34, y: c.y + s * 0.34))
        x.move(to: CGPoint(x: c.x + s * 0.34, y: c.y - s * 0.34)); x.addLine(to: CGPoint(x: c.x - s * 0.34, y: c.y + s * 0.34))
        let fill = used ? Color(red: 0.95, green: 0.18, blue: 0.12) : Color(red: 0.2, green: 0.4, blue: 0.95)
        ctx.stroke(x, with: .color(Color(red: 0.08, green: 0.06, blue: 0.14)), style: StrokeStyle(lineWidth: s * 0.36, lineCap: .round))
        ctx.stroke(x, with: .color(fill), style: StrokeStyle(lineWidth: s * 0.22, lineCap: .round))
        ctx.stroke(x, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: s * 0.06, lineCap: .round))
    }
}

/// Fruit Ninja's chunky gold numbers with a dark outline.
private struct FNScoreText: View {
    let text: String
    let size: CGFloat

    var body: some View {
        let font = Font.system(size: size, weight: .black, design: .rounded)
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let a = Double(i) * .pi / 4
                Text(text).font(font).foregroundStyle(Color(red: 0.3, green: 0.13, blue: 0.04))
                    .offset(x: CGFloat(cos(a)) * size * 0.07, y: CGFloat(sin(a)) * size * 0.07)
            }
            Text(text).font(font)
                .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.94, blue: 0.42), Color(red: 1, green: 0.6, blue: 0.1)],
                                                startPoint: .top, endPoint: .bottom))
        }
        .fixedSize()
    }
}

/// The dojo board: vertical planks with grain, knots and knife scars, a faint ink wave, and from
/// level 5 a volcanic glow rising from below.
private struct FNDojo: View, Equatable {
    let level: Int

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let heat = Double(min(max(level, 1), 7) - 1) / 6
            let base = Color(red: 0.66, green: 0.46, blue: 0.27).mix(with: Color(red: 0.4, green: 0.17, blue: 0.12), by: heat)
            let planks = 6
            let pw = w / CGFloat(planks)
            for i in 0..<planks {
                let k = Double(i)
                let tone = base.mix(with: FNArt.hash(k + 3) > 0.5 ? .white : .black, by: 0.04 + FNArt.hash(k + 7) * 0.08)
                let r = CGRect(x: CGFloat(i) * pw, y: 0, width: pw + 0.5, height: h)
                ctx.fill(Path(r), with: .linearGradient(Gradient(colors: [tone.mix(with: .white, by: 0.06), tone, tone.mix(with: .black, by: 0.12)]),
                                                        startPoint: CGPoint(x: r.minX, y: 0), endPoint: CGPoint(x: r.maxX, y: 0)))
                var grain = Path()
                for j in 0..<6 {
                    let x0 = r.minX + pw * CGFloat(0.12 + 0.15 * Double(j)) + CGFloat(FNArt.hash(k * 13 + Double(j)) * 6)
                    grain.move(to: CGPoint(x: x0, y: 0))
                    var y: CGFloat = 0
                    while y < h {
                        y += 18
                        let wob = CGFloat(sin(Double(y) * 0.03 + k + Double(j))) * 2.5
                        grain.addLine(to: CGPoint(x: x0 + wob, y: y))
                    }
                }
                ctx.stroke(grain, with: .color(.black.opacity(0.08)), lineWidth: 1)
                if FNArt.hash(k + 21) > 0.35 {
                    let kc = CGPoint(x: r.midX + CGFloat(FNArt.hash(k + 5) - 0.5) * pw * 0.4, y: h * CGFloat(0.15 + FNArt.hash(k + 9) * 0.7))
                    for ring in 0..<3 {
                        let rr = CGFloat(4 + ring * 4)
                        ctx.stroke(Path(ellipseIn: CGRect(x: kc.x - rr * 0.6, y: kc.y - rr * 1.3, width: rr * 1.2, height: rr * 2.6)),
                                   with: .color(.black.opacity(0.12)), lineWidth: 1.2)
                    }
                }
                ctx.fill(Path(CGRect(x: r.minX, y: 0, width: 2, height: h)), with: .color(.black.opacity(0.35)))
                ctx.fill(Path(CGRect(x: r.minX + 2, y: 0, width: 1, height: h)), with: .color(.white.opacity(0.1)))
            }
            // A faint ink wave rolling in from the lower left.
            var wave = Path()
            for s in 0..<4 {
                let o = CGFloat(s) * 14
                wave.move(to: CGPoint(x: -20, y: h * 0.92 - o))
                wave.addCurve(to: CGPoint(x: w * 0.52, y: h * 0.56 - o * 0.4),
                              control1: CGPoint(x: w * 0.2, y: h * 0.9 - o), control2: CGPoint(x: w * 0.28, y: h * 0.5 - o))
                wave.addQuadCurve(to: CGPoint(x: w * 0.44, y: h * 0.64 - o * 0.5), control: CGPoint(x: w * 0.62, y: h * 0.62 - o * 0.5))
            }
            ctx.stroke(wave, with: .color(Color(red: 0.12, green: 0.06, blue: 0.03).opacity(0.09)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            // Knife scars.
            var dark = Path(), light = Path()
            for i in 0..<9 {
                let k = Double(i) + 40
                let p = CGPoint(x: CGFloat(FNArt.hash(k)) * w, y: CGFloat(FNArt.hash(k + 1)) * h)
                let a = (FNArt.hash(k + 2) > 0.5 ? 1.0 : -1.0) * (0.35 + FNArt.hash(k + 3) * 0.6)
                let len = CGFloat(30 + FNArt.hash(k + 4) * 70)
                let q = CGPoint(x: p.x + CGFloat(cos(a)) * len, y: p.y + CGFloat(sin(a)) * len)
                dark.move(to: p); dark.addLine(to: q)
                light.move(to: CGPoint(x: p.x + 1, y: p.y + 1.2)); light.addLine(to: CGPoint(x: q.x + 1, y: q.y + 1.2))
            }
            ctx.stroke(dark, with: .color(.black.opacity(0.32)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            ctx.stroke(light, with: .color(.white.opacity(0.14)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            if level >= 5 {
                let glow = CGPoint(x: w / 2, y: h * 1.05)
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.32, blue: 0.08).opacity(0.18 * Double(level - 4)), .clear]),
                                               center: glow, startRadius: 0, endRadius: h * 0.75))
            }
        }
    }
}
