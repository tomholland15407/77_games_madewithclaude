//
//  KnifeHitGame.swift
//  A Banana Game
//
//  Reflex — a Knife Hit homage. A wooden log spins in the centre; TAP to throw the
//  waiting knife straight up so it sticks into the rim. Land it in an empty spot and it
//  sticks; hit an already-stuck knife or an iron plate bolted to the log and it clanks
//  off — fail back to level 1. Stick the level's quota of knives to win. 7 levels: the
//  log spins faster (and reverses direction from level 4), starts with more knives and
//  blocks already in it, and the quota grows — so the rim gets lethally crowded. A
//  generous clock is the safety-net fail.
//
//  Drawn as Ketchapp's Knife Hit: a dark teal backdrop with soft light shafts, a wooden log seen end
//  on (growth rings, bark rim, a crack and a knot that show the spin), silver knives with orange
//  handles whose tips sink into the wood, iron plates bolted over the rim for the blocks (drawn at
//  their true angular width), and Knife Hit's column of knife icons for the knives left. A clank
//  sends the knife spinning away; the last knife splits the log apart.
//

import SwiftUI

enum KnifeHitGame {
    static let definition = GameDefinition(
        id: "knife-hit",
        title: "Log Darts",
        emoji: "🍌",
        genre: .reflex,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "A log spins in the center. Tap to throw the waiting knife into the rim.",
                "Land it in an empty spot and it sticks.",
                "Hit an already-stuck knife or an iron plate and it clanks off — back to level 1.",
                "Stick the level's quota of knives to win.",
            ],
            bulletsVI: [
                "Một khúc gỗ xoay ở giữa. Chạm để phóng con dao đang chờ vào vành.",
                "Cắm vào chỗ trống thì nó dính lại.",
                "Trúng con dao đã cắm hoặc tấm sắt thì nó bật ra — về cấp 1.",
                "Cắm đủ số dao của cấp để thắng.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(KnifeHitView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct KnifeHitView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void
    @Environment(\.isDemo) private var isDemo

    // MARK: Difficulty
    private var quota: Int        { [4, 5, 6, 8, 10, 12, 14][min(level, 7) - 1] }
    private var preKnives: Int    { [1, 2, 2, 3, 4, 5, 6][min(level, 7) - 1] }
    private var blocks: Int       { [0, 0, 1, 1, 2, 2, 3][min(level, 7) - 1] }
    private var rotSpeed: CGFloat { [1.2, 1.5, 1.8, 2.1, 2.5, 3.0, 3.6][min(level, 7) - 1] }
    private var canReverse: Bool  { level >= 4 }
    private var timeLimit: Double { [13, 14, 15, 16, 17, 18, 20][min(level, 7) - 1] }

    private let knifeWidth: CGFloat = 0.17     // angular half-width of a stuck knife (rad)
    private let blockWidth: CGFloat = 0.30

    // MARK: State
    private struct Block: Identifiable { let id = UUID(); let rel: CGFloat }
    @State private var theta: CGFloat = 0
    @State private var dir: CGFloat = 1
    @State private var reversalTimer: CGFloat = 2
    @State private var stuck: [CGFloat] = []       // relative angles of stuck knives
    @State private var blockList: [Block] = []
    @State private var count = 0
    @State private var throwing = false
    @State private var throwProgress: CGFloat = 0
    @State private var shakeTick = 0
    @State private var timeLeft: Double = 0
    @State private var done = false
    @State private var loopTask: Task<Void, Never>?
    @State private var demoTapID = 0      // demo: bumps per throw → a fresh DemoTapRipple

    // Presentation only: when the log split (win) or the knife clanked away (fail).
    @State private var splitAt: Date? = nil
    @State private var clankAt: Date? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let cx = w * 0.5, cy = h * 0.40
            let R = min(w, h) * 0.20
            let kw = R * 0.34, kh = R * 0.80

            ZStack {
                KHBackdrop(level: level).equatable()

                // Stuck knives, iron plates and the log (on top, so the blade tips sink into it).
                TimelineView(.animation(paused: splitAt == nil)) { tl in
                    Canvas { ctx, size in
                        let age = splitAt.map { max(0, tl.date.timeIntervalSince($0)) }
                        KHArt.log(ctx, center: CGPoint(x: cx, y: cy), radius: R, theta: theta, knives: stuck,
                                  blocks: blockList.map(\.rel), knife: CGSize(width: kw, height: kh), split: age)
                    }
                }

                // The waiting / thrown knife (a view, so the 0.07 s throw still animates).
                KHKnife(size: CGSize(width: kw, height: kh))
                    .frame(width: kw * 1.4, height: kh)
                    .position(x: cx, y: cy + (h * 0.42) - throwProgress * (h * 0.42 - R - kh * 0.4))
                    .opacity((isDemo && done) || clankAt != nil ? 0 : 1)   // demo win hold: no spare knife

                // A clanked knife tumbles away.
                if clankAt != nil {
                    KHClank(size: CGSize(width: kw, height: kh))
                        .frame(width: kw * 1.4, height: kh)
                        .position(x: cx, y: cy + R + kh * 0.5)
                        .allowsHitTesting(false)
                }

                KHHud(left: quota - count, total: quota, fraction: isDemo ? nil : (timeLimit > 0 ? timeLeft / timeLimit : 0))
                    .padding(.leading, isDemo ? 12 : 18)
                    .padding(.vertical, isDemo ? 8 : 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false)

                Color.clear.contentShape(Rectangle())
                    .onTapGesture { throwKnife() }

                if isDemo && demoTapID > 0 {
                    DemoTapRipple().id(demoTapID).position(x: w * 0.74, y: h * 0.84)
                }
            }
            .frame(width: w, height: h)
            .clipped()
            .screenShake(shakeTick, amount: 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
        // The last knife splits the log; a clank (not the clock) sends the knife spinning away.
        .onChange(of: done) { _, isDone in
            splitAt = isDone && count >= quota ? Date() : nil
            clankAt = isDone && count < quota && timeLeft > 0 ? Date() : nil
        }
    }

    // MARK: Input
    private func throwKnife() {
        guard !done, !throwing else { return }
        throwing = true
        Task {
            withAnimation(.easeOut(duration: 0.07)) { throwProgress = 1 }
            try? await Task.sleep(for: .seconds(0.075))
            resolve()
            throwProgress = 0
            throwing = false
        }
    }

    private func resolve() {
        guard !done else { return }
        // The knife arrives at the bottom of the log: screen angle π/2.
        let contact = norm(.pi / 2 - theta)
        for r in stuck where angDiff(r, contact) < knifeWidth * 2 { clank(); return }
        for b in blockList where angDiff(b.rel, contact) < blockWidth + knifeWidth { clank(); return }
        stuck.append(contact)
        count += 1
        SoundManager.shared.tap(); Haptics.tap()
        if count >= quota { win() }
    }

    private func clank() {
        shakeTick += 1
        fail()
    }

    // MARK: - Flow
    private func run() async {
        setup()
        var last = Date()
        let start = Date()
        loopTask = Task {
            while !Task.isCancelled && !done {
                try? await Task.sleep(for: .seconds(0.016))
                let now = Date()
                let dt = CGFloat(min(0.05, now.timeIntervalSince(last)))
                last = now
                timeLeft = max(0, timeLimit - now.timeIntervalSince(start))
                if timeLeft <= 0 { fail(); break }
                if canReverse {
                    reversalTimer -= dt
                    if reversalTimer <= 0 { dir = -dir; reversalTimer = CGFloat.random(in: 1.2...2.6) }
                }
                theta += rotSpeed * dir * dt
            }
        }
    }

    private func setup() {
        theta = 0; dir = 1; reversalTimer = CGFloat.random(in: 1.2...2.6)
        count = 0; throwing = false; throwProgress = 0; timeLeft = timeLimit; done = false
        // Scatter pre-stuck knives and blocks without overlapping.
        var used: [CGFloat] = []
        var blks: [Block] = []
        func freeAngle(_ pad: CGFloat) -> CGFloat? {
            for _ in 0..<40 {
                let a = CGFloat.random(in: 0..<(2 * .pi))
                if used.allSatisfy({ angDiff($0, a) > pad }) { used.append(a); return a }
            }
            return nil
        }
        var pre: [CGFloat] = []
        for _ in 0..<preKnives { if let a = freeAngle(knifeWidth * 3) { pre.append(a) } }
        for _ in 0..<blocks { if let a = freeAngle(blockWidth * 2) { blks.append(Block(rel: a)) } }
        stuck = pre
        blockList = blks
    }

    // MARK: - Demo (live manual clip)
    // Level 1 (quota 4, one knife already in the log, no blocks, steady 1.2 rad/s spin) on a fixed
    // setup, stepped at a fixed 1/60s. Throws through the real `throwKnife` every 0.7s, so the four
    // knives land 0.84 rad apart and ≥1.8 rad from the pre-stuck one (a clank needs < 0.34). The
    // 4th sticks → the real win().
    private static let demoThrowFrames: Set<Int> = [48, 90, 132, 174]

    private func runDemo() async {
        let dt: CGFloat = 1.0 / 60.0
        while !Task.isCancelled {
            theta = 0; dir = 1; count = 0; throwing = false; throwProgress = 0
            timeLeft = timeLimit; done = false
            stuck = [2.4]; blockList = []
            var frame = 0
            while !Task.isCancelled && !done && frame < 600 {
                frame += 1
                if Self.demoThrowFrames.contains(frame) { throwKnife(); demoTapID += 1 }
                theta += rotSpeed * dir * dt
                try? await Task.sleep(for: .seconds(0.016))
            }
            // 4/4 → the real win() ran (onWin is a no-op). Hold on the loaded log, then loop.
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    private func norm(_ a: CGFloat) -> CGFloat {
        var x = a.truncatingRemainder(dividingBy: 2 * .pi)
        if x < 0 { x += 2 * .pi }
        return x
    }
    private func angDiff(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        var d = abs(norm(a) - norm(b))
        if d > .pi { d = 2 * .pi - d }
        return d
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

// MARK: - Knife Hit art

private enum KHArt {
    static let ink = Color(red: 0.12, green: 0.08, blue: 0.06)

    /// A knife pointing up (tip at −y), centred in a `kw × kh` box: silver blade, dark guard,
    /// orange handle with two rivet bands.
    static func knife(_ g: GraphicsContext, kw: CGFloat, kh: CGFloat, tint: Color? = nil) {
        var blade = Path()
        blade.move(to: CGPoint(x: 0, y: -kh / 2))
        blade.addQuadCurve(to: CGPoint(x: kw * 0.3, y: -kh * 0.04), control: CGPoint(x: kw * 0.3, y: -kh * 0.34))
        blade.addLine(to: CGPoint(x: kw * 0.3, y: kh * 0.05))
        blade.addLine(to: CGPoint(x: -kw * 0.3, y: kh * 0.05))
        blade.addLine(to: CGPoint(x: -kw * 0.3, y: -kh * 0.28))
        blade.closeSubpath()
        let guardBar = Path(roundedRect: CGRect(x: -kw * 0.44, y: kh * 0.04, width: kw * 0.88, height: kh * 0.07), cornerRadius: kw * 0.06)
        let handle = Path(roundedRect: CGRect(x: -kw * 0.27, y: kh * 0.1, width: kw * 0.54, height: kh * 0.4), cornerRadius: kw * 0.16)
        if let t = tint {
            for part in [blade, guardBar, handle] { g.fill(part, with: .color(t)) }
            return
        }
        g.fill(blade, with: .linearGradient(Gradient(colors: [Color(white: 0.97), Color(white: 0.78), Color(white: 0.6)]),
                                            startPoint: CGPoint(x: -kw * 0.3, y: 0), endPoint: CGPoint(x: kw * 0.3, y: 0)))
        var spine = Path()
        spine.move(to: CGPoint(x: -kw * 0.05, y: -kh * 0.4)); spine.addLine(to: CGPoint(x: -kw * 0.05, y: kh * 0.03))
        g.stroke(spine, with: .color(.white.opacity(0.8)), lineWidth: max(0.6, kw * 0.06))
        g.stroke(blade, with: .color(Color(white: 0.35)), lineWidth: max(0.6, kw * 0.05))
        g.fill(guardBar, with: .color(Color(white: 0.28)))
        g.fill(handle, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.62, blue: 0.26), Color(red: 0.86, green: 0.36, blue: 0.1)]),
                                             startPoint: CGPoint(x: -kw * 0.27, y: 0), endPoint: CGPoint(x: kw * 0.27, y: 0)))
        for y in [0.22, 0.38] as [CGFloat] {
            g.fill(Path(CGRect(x: -kw * 0.27, y: kh * y, width: kw * 0.54, height: kh * 0.04)), with: .color(Color(red: 0.45, green: 0.16, blue: 0.06)))
        }
        g.stroke(handle, with: .color(Color(red: 0.4, green: 0.14, blue: 0.05)), lineWidth: max(0.6, kw * 0.05))
    }

    /// The log seen end-on: bark rim, pale face, growth rings, a crack and a knot (they show the spin).
    static func face(_ g: GraphicsContext, radius R: CGFloat, theta: CGFloat) {
        let disc = { (r: CGFloat) in Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)) }
        g.fill(disc(R), with: .color(Color(red: 0.55, green: 0.3, blue: 0.13)))
        g.fill(disc(R * 0.9), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.85, blue: 0.5), Color(red: 0.95, green: 0.68, blue: 0.32)]),
                                                     center: .zero, startRadius: 0, endRadius: R * 0.9))
        var rings = Path()
        for k in 1...5 { rings.addPath(disc(R * (0.14 + 0.15 * CGFloat(k)))) }
        g.stroke(rings, with: .color(Color(red: 0.86, green: 0.55, blue: 0.24).opacity(0.75)), lineWidth: max(1, R * 0.03))
        var rot = g
        rot.rotate(by: .radians(Double(theta)))
        var crack = Path()
        crack.move(to: CGPoint(x: R * 0.3, y: 0))
        crack.addLine(to: CGPoint(x: R * 0.5, y: R * 0.05))
        crack.addLine(to: CGPoint(x: R * 0.64, y: -R * 0.03))
        crack.addLine(to: CGPoint(x: R * 0.88, y: R * 0.04))
        rot.stroke(crack, with: .color(Color(red: 0.5, green: 0.27, blue: 0.1)), style: StrokeStyle(lineWidth: max(1.2, R * 0.035), lineCap: .round, lineJoin: .round))
        rot.fill(Path(ellipseIn: CGRect(x: -R * 0.52, y: -R * 0.36, width: R * 0.18, height: R * 0.12)), with: .color(Color(red: 0.72, green: 0.42, blue: 0.16)))
        g.stroke(disc(R * 0.9), with: .color(Color(red: 0.72, green: 0.42, blue: 0.16)), lineWidth: max(1, R * 0.04))
        g.stroke(disc(R), with: .color(ink.opacity(0.6)), lineWidth: max(1, R * 0.025))
    }

    /// An iron plate over the rim spanning the block's true angular half-width (0.30 rad).
    static func plate(_ g: GraphicsContext, radius R: CGFloat, angle a: CGFloat) {
        let half: Double = 0.30
        var p = Path()
        p.addArc(center: .zero, radius: R * 1.1, startAngle: .radians(Double(a) - half), endAngle: .radians(Double(a) + half), clockwise: false)
        p.addArc(center: .zero, radius: R * 0.84, startAngle: .radians(Double(a) + half), endAngle: .radians(Double(a) - half), clockwise: true)
        p.closeSubpath()
        g.fill(p, with: .radialGradient(Gradient(colors: [Color(white: 0.5), Color(white: 0.78), Color(white: 0.42)]),
                                        center: .zero, startRadius: R * 0.84, endRadius: R * 1.1))
        g.stroke(p, with: .color(Color(white: 0.2)), lineWidth: max(1, R * 0.03))
        var rivets = Path()
        for d in [-0.18, 0.18] {
            let q = CGPoint(x: CGFloat(cos(Double(a) + d)) * R * 0.97, y: CGFloat(sin(Double(a) + d)) * R * 0.97)
            rivets.addEllipse(in: CGRect(x: q.x - R * 0.035, y: q.y - R * 0.035, width: R * 0.07, height: R * 0.07))
        }
        g.fill(rivets, with: .color(Color(white: 0.25)))
    }

    /// Stuck knives, the log over them, and the plates; `split` (seconds) breaks it all apart.
    static func log(_ ctx: GraphicsContext, center c: CGPoint, radius R: CGFloat, theta: CGFloat,
                    knives: [CGFloat], blocks: [CGFloat], knife: CGSize, split: Double?) {
        let kw = knife.width, kh = knife.height
        let t = CGFloat(split ?? 0)
        let fade = split == nil ? 1.0 : max(0, 1 - (split ?? 0) / 1.25)
        guard fade > 0 else { return }
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.opacity = fade
        for rel in knives {
            let a = rel + theta
            var k = g
            let out = R + kh * 0.30 + t * R * 1.6
            k.translateBy(x: CGFloat(cos(Double(a))) * out, y: CGFloat(sin(Double(a))) * out + t * t * R * 3)
            k.rotate(by: .radians(Double(a) - .pi / 2 + Double(t) * 6))
            Self.knife(k, kw: kw, kh: kh)
        }
        if split == nil {
            face(g, radius: R, theta: theta)
        } else {
            // Three wedges fly off along their bisectors and drop.
            for k in 0..<3 {
                let mid = Double(theta) + Double(k) * 2 * .pi / 3 + .pi / 3
                var w = g
                w.translateBy(x: CGFloat(cos(mid)) * t * R * 1.2, y: CGFloat(sin(mid)) * t * R * 1.2 + t * t * R * 2.6)
                w.rotate(by: .radians(Double(t) * (k == 1 ? -1.6 : 1.6)))
                var wedge = Path()
                wedge.move(to: .zero)
                wedge.addArc(center: .zero, radius: R * 1.02, startAngle: .radians(mid - .pi / 3), endAngle: .radians(mid + .pi / 3), clockwise: false)
                wedge.closeSubpath()
                w.clip(to: wedge)
                face(w, radius: R, theta: theta)
            }
        }
        for a in blocks {
            var p = g
            p.translateBy(x: 0, y: t * t * R * 2.6)
            plate(p, radius: R, angle: a + theta)
        }
    }
}

/// The waiting knife.
private struct KHKnife: View {
    let size: CGSize
    var body: some View {
        Canvas { ctx, s in
            var g = ctx
            g.translateBy(x: s.width / 2, y: s.height / 2)
            KHArt.knife(g, kw: size.width, kh: size.height)
        }
    }
}

/// A knife that hit metal or another knife: it tumbles away and fades (once).
private struct KHClank: View {
    let size: CGSize
    @State private var go = false
    var body: some View {
        KHKnife(size: size)
            .rotationEffect(.degrees(go ? 560 : 0))
            .offset(x: go ? size.height * 1.6 : 0, y: go ? size.height * 2.4 : 0)
            .opacity(go ? 0 : 1)
            .onAppear { withAnimation(.easeIn(duration: 0.75)) { go = true } }
    }
}

/// Knife Hit's column of knives: white ones are still to throw, dim ones are in the log. A slim clock
/// sits above it while playing.
private struct KHHud: View {
    let left: Int
    let total: Int
    let fraction: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let f = fraction {
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.16))
                    Capsule().fill(f < 0.3 ? Color(red: 1, green: 0.35, blue: 0.3) : .white.opacity(0.85))
                        .frame(width: 90 * max(0, min(1, f)))
                }
                .frame(width: 90, height: 3)
            }
            Spacer(minLength: 0)
            Canvas { ctx, size in
                let n = max(1, total)
                let step = min(24, size.height / CGFloat(n))
                for i in 0..<n {
                    var g = ctx
                    g.translateBy(x: size.width / 2, y: size.height - (CGFloat(i) + 0.5) * step)
                    KHArt.knife(g, kw: step * 0.46, kh: step * 0.92, tint: i < left ? .white : .white.opacity(0.2))
                }
            }
            .frame(width: 20, height: min(24 * CGFloat(max(1, total)), 300))
        }
    }
}

/// Knife Hit's dark teal backdrop with soft light shafts (navy mid-game, a crimson boss glow at 6–7).
private struct KHBackdrop: View, Equatable {
    let level: Int

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let cols: [Color] = level >= 6 ? [Color(red: 0.28, green: 0.07, blue: 0.1), Color(red: 0.1, green: 0.02, blue: 0.05)]
                : level >= 4 ? [Color(red: 0.08, green: 0.15, blue: 0.3), Color(red: 0.03, green: 0.06, blue: 0.15)]
                : [Color(red: 0.07, green: 0.24, blue: 0.29), Color(red: 0.03, green: 0.11, blue: 0.15)]
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: cols), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            for (x, width) in [(0.18, 0.09), (0.46, 0.14), (0.8, 0.07)] as [(CGFloat, CGFloat)] {
                var shaft = Path()
                shaft.move(to: CGPoint(x: w * x, y: 0))
                shaft.addLine(to: CGPoint(x: w * (x + width), y: 0))
                shaft.addLine(to: CGPoint(x: w * (x + width - 0.22), y: h))
                shaft.addLine(to: CGPoint(x: w * (x - 0.22), y: h))
                shaft.closeSubpath()
                ctx.fill(shaft, with: .linearGradient(Gradient(colors: [.white.opacity(0.07), .white.opacity(0)]),
                                                      startPoint: .zero, endPoint: CGPoint(x: 0, y: h * 0.85)))
            }
        }
    }
}
