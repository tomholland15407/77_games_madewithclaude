//
//  GoldMinerGame.swift
//  A Banana Game
//
//  Reflex — a Gold Miner / Đào Vàng claw grab. A claw swings fast on a rope above a dirt field of
//  gold, gems, rocks and mystery sacks. Tap to fire the claw straight along its current angle; it
//  grabs whatever it strikes and reels it up — big nuggets and rocks reel slowly, small gold and
//  gems snap right back. Bank enough money to hit the level's GOAL before the clock runs out; fall
//  short and you're back to level 1.
//
//  7 levels: a higher goal, less time, a faster swing, and more worthless rocks cluttering the gold.
//

import SwiftUI

enum GoldMinerGame {
    static let definition = GameDefinition(
        id: "gold-miner",
        title: "Nugget Hook",
        emoji: "🍌",
        genre: .reflex,
        levelCount: 7,
        locksFeed: false,
        manual: GameManual(
            bullets: [
                "The claw swings on its rope; tap anywhere to fire it along its current angle.",
                "It grabs the first thing it hits and reels it up — rocks and big nuggets reel slowly.",
                "Hit the money GOAL before the clock runs out; rocks deduct money, so avoid them.",
            ],
            bulletsVI: [
                "Móc câu đung đưa trên dây; chạm bất kỳ đâu để phóng theo góc hiện tại.",
                "Nó tóm vật đầu tiên chạm phải và kéo lên — đá và cục vàng lớn kéo chậm.",
                "Đạt MỤC TIÊU tiền trước khi hết giờ; đá trừ tiền, nên hãy tránh.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(GoldMinerView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct GoldMinerView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    // MARK: Difficulty
    private var goalFrac: Double    { [0.35, 0.45, 0.55, 0.62, 0.70, 0.78, 0.85][min(level, 7) - 1] }
    private var timeLimit: Double   { [40, 38, 35, 32, 29, 26, 24][min(level, 7) - 1] }
    private var swingSpeed: Double  { [3.0, 3.5, 4.0, 4.5, 5.0, 5.6, 6.3][min(level, 7) - 1] }
    private var goldCount: Int      { [8, 8, 8, 9, 9, 10, 10][min(level, 7) - 1] }
    private var rockCount: Int      { [1, 2, 3, 4, 5, 7, 9][min(level, 7) - 1] }
    private var diamondCount: Int   { [1, 1, 1, 2, 2, 2, 3][min(level, 7) - 1] }
    private var mysteryCount: Int   { [1, 1, 1, 1, 2, 2, 2][min(level, 7) - 1] }
    // Grabbing a rock stings hard and scales with the level (100 at level 1).
    private var rockPenalty: Int    { 100 + (min(level, 7) - 1) * 50 }

    private let maxAngle: Double = 1.35        // ~77° each side — near-horizontal sweep
    private let restLen: CGFloat = 0.05        // rope length at rest (fraction of height)
    private let maxLen: CGFloat = 0.78
    private let extendSpeed: CGFloat = 1.25    // fraction of height / sec
    private let reelEmpty: CGFloat = 1.9

    fileprivate enum Kind { case gold, rock, diamond, mystery }
    private struct Obj: Identifiable {
        let id = UUID()
        var pos: CGPoint          // fractions of (w, h)
        let rFrac: CGFloat        // radius as fraction of min(w, h)
        let value: Int
        let reelFactor: CGFloat   // reel speed multiplier (heavy = small)
        let kind: Kind
        let seed: Double
    }

    private enum HookState { case swing, extend, reel }
    private enum Phase { case play, done }

    @State private var phase: Phase = .play
    @State private var hook: HookState = .swing
    @State private var field: CGSize = .zero
    @State private var objects: [Obj] = []
    @State private var money = 0
    @State private var goal = 0
    @State private var timeLeft = 0.0
    @State private var swingPhase: Double = 0
    @State private var angle: Double = 0        // current claw angle from straight-down
    @State private var ropeLen: CGFloat = 0.05
    @State private var grabbed: Obj? = nil
    @State private var bursts: [BurstMark] = []
    @State private var shakeTick = 0
    @State private var cloudT: CGFloat = 0
    @State private var built = false
    @State private var rippleID = 0     // bump to fire a one-shot "tap" ring in the demo

    private struct BurstMark: Identifiable { let id = UUID(); let pos: CGPoint; let color: Color }
    // Presentation only: the "+$" amounts floating up from the winch after each deposit.
    private struct Gain: Identifiable { let id = UUID(); let value: Int; let t0: Date }
    @State private var gains: [Gain] = []

    var body: some View {
        scene
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task { isDemo ? await runDemo() : await run() }
    }
    // MARK: - Demo (live manual clip)

    /// A staged grab: one fat nugget sits straight below the winch. When the swing
    /// crosses vertical the demo fires; the real extend/grab/reel banks it past the
    /// (lowered) goal for the win.
    private func runDemo() async {
        while field == .zero { try? await Task.sleep(for: .seconds(0.02)) }
        while !Task.isCancelled {
            demoSetup()
            var last = Date()
            var fired = false
            while phase == .play && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.016))
                let now = Date()
                let dt = CGFloat(min(0.05, now.timeIntervalSince(last))); last = now
                if !fired, hook == .swing, abs(angle) < 0.05 {
                    rippleID += 1          // fire the "tap" ripple
                    fire()                 // loose straight down onto the nugget
                    fired = true
                }
                step(dt: dt)               // real physics: extend → grab → reel → deposit → win
            }
            try? await Task.sleep(for: .seconds(1.3))   // hold on the banked gold
        }
    }

    private func demoSetup() {
        objects = [
            Obj(pos: CGPoint(x: 0.5, y: 0.62), rFrac: 0.074, value: 320, reelFactor: 0.46, kind: .gold, seed: 1.0),
            Obj(pos: CGPoint(x: 0.24, y: 0.50), rFrac: 0.050, value: 140, reelFactor: 0.72, kind: .gold, seed: 2.4),
            Obj(pos: CGPoint(x: 0.78, y: 0.70), rFrac: 0.050, value: 140, reelFactor: 0.72, kind: .gold, seed: 3.1),
            Obj(pos: CGPoint(x: 0.62, y: 0.86), rFrac: 0.028, value: 560, reelFactor: 1.15, kind: .diamond, seed: 4.7),
        ]
        goal = 300                          // the fat nugget alone clears it
        money = 0
        timeLeft = timeLimit
        swingPhase = 0
        angle = 0
        ropeLen = restLen
        hook = .swing
        grabbed = nil
        bursts = []
        gains = []
        phase = .play
        built = true
    }

    /// Gold Miner's HUD, painted on the orange surface: Money / Goal on the left, Time on the right.
    private func hud(w: CGFloat, h: CGFloat) -> some View {
        let size: CGFloat = isDemo ? 13 : 17
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: isDemo ? 0 : 2) {
                hudLine(L("Money", "Tiền"), "$\(money)", size: size,
                        color: money >= goal ? Color(red: 0.55, green: 1, blue: 0.55) : .white)
                hudLine(L("Goal", "Mục tiêu"), "$\(goal)", size: size, color: Color(red: 1, green: 0.93, blue: 0.4))
            }
            Spacer()
            if !isDemo {
                hudLine(L("Time", "Giờ"), "\(Int(ceil(timeLeft)))", size: size,
                        color: timeLeft < timeLimit * 0.3 ? Color(red: 1, green: 0.35, blue: 0.3) : .white)
            }
        }
        .padding(.horizontal, isDemo ? 10 : 14)
        .padding(.top, isDemo ? 6 : 10)
        .frame(width: w, height: h, alignment: .top)
        .allowsHitTesting(false)
    }

    private func hudLine(_ label: String, _ value: String, size: CGFloat, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(label + ":")
                .foregroundStyle(Color(red: 0.36, green: 0.16, blue: 0.02))
            Text(value)
                .foregroundStyle(color)
                .shadow(color: Color(red: 0.3, green: 0.12, blue: 0.0), radius: 0, x: 1.5, y: 1.5)
                .contentTransition(.numericText())
        }
        .font(.system(size: size, weight: .black, design: .rounded))
    }

    private var scene: some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width
            let h: CGFloat = geo.size.height
            let pivot = CGPoint(x: w * 0.5, y: h * 0.205)

            ZStack(alignment: .topLeading) {
                MinerBackdrop(size: geo.size).equatable()
                miner(w: w, h: h, pivot: pivot)
                Canvas { ctx, _ in drawField(ctx, w: w, h: h, pivot: pivot) }
                ForEach(bursts) { b in
                    ParticleBurstView(color: b.color, count: 14, spread: 46) {
                        bursts.removeAll { $0.id == b.id }
                    }
                    .position(b.pos)
                }
                // Demo-only "tap" ripple that shows the fire gesture (there's no button here).
                if isDemo, rippleID > 0 {
                    DemoTapRipple()
                        .id(rippleID)
                        .position(x: w * 0.5, y: h * 0.78)
                }
                hud(w: w, h: h)
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
            .screenShake(shakeTick, amount: 6)
            .contentShape(Rectangle())
            .onTapGesture { fire() }
            .onAppear { if field == .zero { field = geo.size } }
        }
        .padding(.horizontal, isDemo ? 0 : 8)
    }

    // MARK: - Scene pieces

    /// Everything that moves: treasure in the dirt, the winch reel, rope, claw (+ its catch) and the
    /// "+$" gains floating up from the winch — one Canvas.
    private func drawField(_ ctx: GraphicsContext, w: CGFloat, h: CGFloat, pivot: CGPoint) {
        let m = min(w, h)
        for obj in objects where grabbed?.id != obj.id {
            MinerArt.treasure(ctx, obj.kind, at: CGPoint(x: obj.pos.x * w, y: obj.pos.y * h), r: obj.rFrac * m, seed: obj.seed)
        }
        let tip = hookTip(pivot: pivot, w: w, h: h)
        // Rope from the reel down to the claw.
        var rope = Path()
        rope.move(to: pivot)
        rope.addLine(to: tip)
        ctx.stroke(rope, with: .color(Color(red: 0.2, green: 0.14, blue: 0.08)), lineWidth: max(2, m * 0.006))
        if let g = grabbed {
            let r = g.rFrac * m
            MinerArt.treasure(ctx, g.kind, at: CGPoint(x: tip.x + CGFloat(sin(angle)) * r, y: tip.y + CGFloat(cos(angle)) * r),
                              r: r, seed: g.seed)
        }
        MinerArt.claw(ctx, at: tip, angle: angle, size: m * 0.03, open: grabbed == nil)
        MinerArt.winch(ctx, at: pivot, size: m * 0.06, turn: Double(ropeLen) * 40)
        // Money earned rises from the winch.
        let now = Date()
        for gain in gains {
            let t = now.timeIntervalSince(gain.t0)
            guard t < 1.1 else { continue }
            let text = Text(gain.value >= 0 ? "+$\(gain.value)" : "-$\(-gain.value)")
                .font(.system(size: m * 0.05, weight: .black, design: .rounded))
            var g = ctx
            g.opacity = t > 0.8 ? max(0, (1.1 - t) / 0.3) : 1
            let p = CGPoint(x: pivot.x + m * 0.16, y: pivot.y - m * 0.04 - CGFloat(t) * m * 0.08)
            g.draw(g.resolve(text.foregroundStyle(Color(red: 0.3, green: 0.12, blue: 0.0))), at: CGPoint(x: p.x + 1.5, y: p.y + 1.5))
            g.draw(g.resolve(text.foregroundStyle(gain.value >= 0 ? Color(red: 0.55, green: 1, blue: 0.5) : Color(red: 1, green: 0.4, blue: 0.35))), at: p)
        }
    }

    /// The old prospector (a stick figure in a hard hat, white beard) cranking the winch.
    private func miner(w: CGFloat, h: CGFloat, pivot: CGPoint) -> some View {
        let fh = h * 0.15
        let cranking = hook == .reel && Int(ropeLen * 40) % 2 == 0
        let pose = cranking ? MinerArt.crankA : MinerArt.crankB
        return ZStack {
            StickFigure(pose: pose, color: Color(red: 0.28, green: 0.2, blue: 0.16), lineFrac: 0.07)
            Canvas { ctx, s in MinerArt.hatAndBeard(ctx, size: s, pose: pose) }
        }
        .frame(width: fh * 0.9, height: fh)
        .position(x: pivot.x - fh * 0.52, y: h * 0.24 - fh * 0.5)
    }
    // MARK: - Geometry

    private func hookTip(pivot: CGPoint, w: CGFloat, h: CGFloat) -> CGPoint {
        CGPoint(x: pivot.x + CGFloat(sin(angle)) * ropeLen * h,
                y: pivot.y + CGFloat(cos(angle)) * ropeLen * h)
    }

    // MARK: - Flow

    private func run() async {
        while field == .zero { try? await Task.sleep(for: .seconds(0.02)) }
        if !built { setup(); built = true }
        var last = Date()
        while !Task.isCancelled && phase == .play {
            try? await Task.sleep(for: .seconds(0.016))
            let now = Date()
            let dt = CGFloat(min(0.05, now.timeIntervalSince(last))); last = now
            step(dt: dt)
        }
    }

    private func step(dt: CGFloat) {
        guard phase == .play else { return }
        let w: CGFloat = field.width, h: CGFloat = field.height
        cloudT += dt * 0.02

        switch hook {
        case .swing:
            swingPhase += Double(dt) * swingSpeed
            angle = maxAngle * sin(swingPhase)
            ropeLen = restLen
        case .extend:
            ropeLen += extendSpeed * dt
            let pivot = CGPoint(x: w * 0.5, y: h * 0.205)
            let tip = hookTip(pivot: pivot, w: w, h: h)
            // Grab the first object the claw reaches.
            let hookR: CGFloat = min(w, h) * 0.02
            if let hit = objects.firstIndex(where: {
                let c = CGPoint(x: $0.pos.x * w, y: $0.pos.y * h)
                return hypot(c.x - tip.x, c.y - tip.y) < $0.rFrac * min(w, h) + hookR
            }) {
                grabbed = objects[hit]
                Haptics.tap(); SoundManager.shared.tap()
                hook = .reel
            } else if ropeLen >= maxLen || tip.x < w * 0.02 || tip.x > w * 0.98 || tip.y > h * 0.97 {
                hook = .reel
            }
        case .reel:
            let speed: CGFloat = grabbed == nil ? reelEmpty : reelEmpty * 0.55 * (grabbed?.reelFactor ?? 1)
            ropeLen -= speed * dt
            if ropeLen <= restLen {
                ropeLen = restLen
                if let g = grabbed {
                    deposit(g, w: w, h: h)
                    grabbed = nil
                }
                hook = .swing
            }
        }

        timeLeft -= Double(dt)
        if timeLeft <= 0 { timeLeft = 0; if money >= goal { win() } else { fail() } }
    }

    private func fire() {
        guard phase == .play, hook == .swing else { return }
        hook = .extend
        SoundManager.shared.tap(); Haptics.tap()
    }

    private func deposit(_ g: Obj, w: CGFloat, h: CGFloat) {
        objects.removeAll { $0.id == g.id }
        // Money never drops below zero; rocks are a penalty.
        withAnimation(.spring(duration: 0.3)) { money = max(0, money + g.value) }
        let color = g.kind == .rock ? Color(red: 0.9, green: 0.4, blue: 0.4)
                  : g.kind == .diamond ? Color(red: 0.6, green: 0.9, blue: 1.0) : BananaTheme.banana
        bursts.append(BurstMark(pos: CGPoint(x: w * 0.5, y: h * 0.14), color: color))
        gains.append(Gain(value: g.value, t0: Date()))
        if gains.count > 4 { gains.removeFirst() }
        if g.kind == .rock {
            shakeTick += 1
            SoundManager.shared.error(); Haptics.warning()
        } else {
            if g.value >= 250 { shakeTick += 1 }
            SoundManager.shared.tap(); Haptics.success()
        }
        if money >= goal { win() }
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

    // MARK: - Setup

    private func setup() {
        var objs: [Obj] = []
        // Returns whether the object actually found a free spot (spacing can crowd it out).
        @discardableResult
        func place(_ rFrac: CGFloat, value: Int, factor: CGFloat, kind: Kind, force: Bool = false) -> Bool {
            for _ in 0..<40 {
                let x = CGFloat.random(in: 0.08...0.92)
                let y = CGFloat.random(in: 0.34...0.93)
                let cand = CGPoint(x: x, y: y)
                let ok = objs.allSatisfy { o in
                    let dx = (o.pos.x - x), dy = (o.pos.y - y)
                    return hypot(dx, dy) > (o.rFrac + rFrac) * 1.6
                }
                if ok {
                    objs.append(Obj(pos: cand, rFrac: rFrac, value: value, reelFactor: factor,
                                    kind: kind, seed: Double.random(in: 0...6.28)))
                    return true
                }
            }
            // Last resort: drop it at a random spot regardless of spacing so it never silently vanishes.
            if force {
                objs.append(Obj(pos: CGPoint(x: .random(in: 0.08...0.92), y: .random(in: 0.34...0.93)),
                                rFrac: rFrac, value: value, reelFactor: factor,
                                kind: kind, seed: Double.random(in: 0...6.28)))
                return true
            }
            return false
        }

        for _ in 0..<goldCount {
            switch Int.random(in: 0..<3) {
            case 0: place(0.034, value: 60, factor: 1.0, kind: .gold)
            case 1: place(0.050, value: 140, factor: 0.72, kind: .gold)
            default: place(0.074, value: 320, factor: 0.46, kind: .gold)
            }
        }
        for _ in 0..<diamondCount { place(0.028, value: 560, factor: 1.15, kind: .diamond) }
        for _ in 0..<mysteryCount { place(0.040, value: Int.random(in: 80...420), factor: 0.8, kind: .mystery) }
        for _ in 0..<rockCount {
            // Rocks are a penalty: grabbing one deducts money (and reels back slowly). The bigger
            // rock hits harder; both scale with the level (starting at 100 on level 1).
            if Bool.random() { place(0.056, value: -rockPenalty, factor: 0.42, kind: .rock) }
            else { place(0.078, value: -(rockPenalty * 3 / 2), factor: 0.30, kind: .rock) }
        }
        // Guarantee every level has at least one rock, even if the field crowded them all out.
        if !objs.contains(where: { $0.kind == .rock }) {
            place(0.056, value: -rockPenalty, factor: 0.42, kind: .rock, force: true)
        }
        objects = objs

        let potential = objs.filter { $0.kind != .rock }.reduce(0) { $0 + $1.value }
        goal = max(100, (Int(Double(potential) * goalFrac) / 10) * 10)

        money = 0
        timeLeft = timeLimit
        swingPhase = 0
        angle = 0
        ropeLen = restLen
        hook = .swing
        grabbed = nil
        phase = .play
    }
}

// MARK: - Gold Miner art

/// The classic Flash Gold Miner: an orange surface with the prospector's dark-blue dome, sandy
/// strata full of lumpy gold, grey rocks, diamonds and "?" sacks, a metal claw on a wooden winch.
private enum MinerArt {
    static func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    /// Cranking poses for the prospector (StickFigure unit box, facing the winch on the right).
    static let crankA = StickPose(
        head: CGPoint(x: 0.44, y: 0.17), headR: 0.1,
        neck: CGPoint(x: 0.46, y: 0.29), hip: CGPoint(x: 0.44, y: 0.6),
        lElbow: CGPoint(x: 0.35, y: 0.43), lHand: CGPoint(x: 0.36, y: 0.57),
        rElbow: CGPoint(x: 0.62, y: 0.37), rHand: CGPoint(x: 0.8, y: 0.33),
        lKnee: CGPoint(x: 0.39, y: 0.79), lFoot: CGPoint(x: 0.35, y: 0.98),
        rKnee: CGPoint(x: 0.53, y: 0.79), rFoot: CGPoint(x: 0.58, y: 0.98))
    static let crankB = StickPose(
        head: CGPoint(x: 0.45, y: 0.18), headR: 0.1,
        neck: CGPoint(x: 0.46, y: 0.3), hip: CGPoint(x: 0.44, y: 0.6),
        lElbow: CGPoint(x: 0.35, y: 0.43), lHand: CGPoint(x: 0.36, y: 0.57),
        rElbow: CGPoint(x: 0.63, y: 0.46), rHand: CGPoint(x: 0.8, y: 0.47),
        lKnee: CGPoint(x: 0.39, y: 0.79), lFoot: CGPoint(x: 0.35, y: 0.98),
        rKnee: CGPoint(x: 0.53, y: 0.79), rFoot: CGPoint(x: 0.58, y: 0.98))

    /// Hard hat with a lamp, a big nose and a white beard on the stick figure's head.
    static func hatAndBeard(_ ctx: GraphicsContext, size s: CGSize, pose: StickPose) {
        let hc = CGPoint(x: s.width / 2 + (pose.head.x - 0.5) * s.height, y: pose.head.y * s.height)
        let r = pose.headR * s.height
        let ink = c(0.22, 0.14, 0.05)
        var beard = Path()
        beard.move(to: CGPoint(x: hc.x - r * 0.35, y: hc.y + r * 0.1))
        beard.addQuadCurve(to: CGPoint(x: hc.x + r * 1.05, y: hc.y + r * 0.2), control: CGPoint(x: hc.x + r * 0.2, y: hc.y + r * 1.9))
        beard.addQuadCurve(to: CGPoint(x: hc.x - r * 0.35, y: hc.y + r * 0.1), control: CGPoint(x: hc.x + r * 0.4, y: hc.y + r * 0.45))
        ctx.fill(beard, with: .color(.white))
        ctx.stroke(beard, with: .color(c(0.6, 0.6, 0.62)), lineWidth: max(0.8, r * 0.1))
        ctx.fill(Path(ellipseIn: CGRect(x: hc.x + r * 0.62, y: hc.y - r * 0.2, width: r * 0.62, height: r * 0.5)), with: .color(c(1, 0.72, 0.58)))
        ctx.stroke(Path(ellipseIn: CGRect(x: hc.x + r * 0.62, y: hc.y - r * 0.2, width: r * 0.62, height: r * 0.5)), with: .color(ink), lineWidth: max(0.8, r * 0.08))
        var hat = Path()
        hat.move(to: CGPoint(x: hc.x - r * 1.05, y: hc.y - r * 0.25))
        hat.addQuadCurve(to: CGPoint(x: hc.x + r * 1.05, y: hc.y - r * 0.25), control: CGPoint(x: hc.x, y: hc.y - r * 2.1))
        hat.closeSubpath()
        ctx.fill(hat, with: .linearGradient(Gradient(colors: [c(1, 0.9, 0.35), c(0.95, 0.72, 0.05)]),
                                            startPoint: CGPoint(x: hc.x, y: hc.y - r * 1.4), endPoint: CGPoint(x: hc.x, y: hc.y - r * 0.2)))
        ctx.stroke(hat, with: .color(ink), lineWidth: max(0.8, r * 0.1))
        let brim = CGRect(x: hc.x - r * 1.3, y: hc.y - r * 0.38, width: r * 2.75, height: r * 0.3)
        ctx.fill(Path(roundedRect: brim, cornerRadius: r * 0.12), with: .color(c(0.95, 0.75, 0.08)))
        ctx.stroke(Path(roundedRect: brim, cornerRadius: r * 0.12), with: .color(ink), lineWidth: max(0.8, r * 0.1))
        ctx.fill(Path(ellipseIn: CGRect(x: hc.x + r * 0.2, y: hc.y - r * 1.05, width: r * 0.5, height: r * 0.45)), with: .color(c(1, 1, 0.8)))
    }

    private static func blob(_ c: CGPoint, _ r: CGFloat, _ seed: Double, lumpy: Double = 0.13) -> Path {
        var p = Path()
        let n = 16
        for i in 0...n {
            let a = Double(i) / Double(n) * 2 * .pi
            let rr = r * CGFloat(1 + lumpy * sin(a * 3 + seed) + 0.06 * cos(a * 5 + seed * 1.7))
            let pt = CGPoint(x: c.x + CGFloat(cos(a)) * rr, y: c.y + CGFloat(sin(a)) * rr)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    static func treasure(_ ctx: GraphicsContext, _ kind: GoldMinerView.Kind, at p: CGPoint, r: CGFloat, seed: Double) {
        switch kind {
        case .gold:
            let b = blob(p, r, seed)
            ctx.fill(b, with: .radialGradient(Gradient(colors: [c(1, 0.97, 0.62), c(1, 0.82, 0.16), c(0.82, 0.56, 0.04)]),
                                              center: CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.4), startRadius: 0, endRadius: r * 1.5))
            for k in 0..<3 {
                let a = seed + Double(k) * 2.1
                let q = CGPoint(x: p.x + CGFloat(cos(a)) * r * 0.45, y: p.y + CGFloat(sin(a)) * r * 0.4)
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - r * 0.12, y: q.y - r * 0.09, width: r * 0.24, height: r * 0.18)),
                         with: .color(c(0.85, 0.6, 0.05).opacity(0.55)))
            }
            ctx.stroke(b, with: .color(c(0.55, 0.34, 0.0)), lineWidth: max(1, r * 0.07))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.55, y: p.y - r * 0.62, width: r * 0.5, height: r * 0.3)), with: .color(.white.opacity(0.75)))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x + r * 0.2, y: p.y - r * 0.35, width: r * 0.16, height: r * 0.12)), with: .color(.white.opacity(0.6)))
        case .rock:
            let b = blob(p, r, seed, lumpy: 0.09)
            ctx.fill(b, with: .radialGradient(Gradient(colors: [c(0.78, 0.78, 0.8), c(0.56, 0.57, 0.6), c(0.38, 0.39, 0.43)]),
                                              center: CGPoint(x: p.x - r * 0.3, y: p.y - r * 0.4), startRadius: 0, endRadius: r * 1.4))
            var crack = Path()
            crack.move(to: CGPoint(x: p.x - r * 0.1, y: p.y - r * 0.55))
            crack.addLine(to: CGPoint(x: p.x + r * 0.05, y: p.y - r * 0.1))
            crack.addLine(to: CGPoint(x: p.x - r * 0.15, y: p.y + r * 0.25))
            crack.move(to: CGPoint(x: p.x + r * 0.05, y: p.y - r * 0.1))
            crack.addLine(to: CGPoint(x: p.x + r * 0.45, y: p.y + r * 0.05))
            ctx.stroke(crack, with: .color(c(0.28, 0.28, 0.32)), lineWidth: max(1, r * 0.06))
            ctx.stroke(b, with: .color(c(0.24, 0.25, 0.28)), lineWidth: max(1, r * 0.07))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.5, y: p.y - r * 0.55, width: r * 0.35, height: r * 0.2)), with: .color(.white.opacity(0.35)))
        case .diamond:
            var gem = Path()
            gem.move(to: CGPoint(x: p.x - r * 0.62, y: p.y - r * 0.5))
            gem.addLine(to: CGPoint(x: p.x + r * 0.62, y: p.y - r * 0.5))
            gem.addLine(to: CGPoint(x: p.x + r, y: p.y - r * 0.1))
            gem.addLine(to: CGPoint(x: p.x, y: p.y + r))
            gem.addLine(to: CGPoint(x: p.x - r, y: p.y - r * 0.1))
            gem.closeSubpath()
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 1.6, y: p.y - r * 1.6, width: r * 3.2, height: r * 3.2)),
                     with: .radialGradient(Gradient(colors: [c(0.7, 0.95, 1).opacity(0.55), .clear]), center: p, startRadius: 0, endRadius: r * 1.6))
            ctx.fill(gem, with: .linearGradient(Gradient(colors: [c(0.85, 1, 1), c(0.35, 0.8, 1), c(0.12, 0.45, 0.85)]),
                                                startPoint: CGPoint(x: p.x - r, y: p.y - r), endPoint: CGPoint(x: p.x + r, y: p.y + r)))
            var facets = Path()
            facets.move(to: CGPoint(x: p.x - r, y: p.y - r * 0.1)); facets.addLine(to: CGPoint(x: p.x + r, y: p.y - r * 0.1))
            facets.move(to: CGPoint(x: p.x - r * 0.3, y: p.y - r * 0.5)); facets.addLine(to: CGPoint(x: p.x - r * 0.45, y: p.y - r * 0.1))
            facets.addLine(to: CGPoint(x: p.x, y: p.y + r))
            facets.move(to: CGPoint(x: p.x + r * 0.3, y: p.y - r * 0.5)); facets.addLine(to: CGPoint(x: p.x + r * 0.45, y: p.y - r * 0.1))
            facets.addLine(to: CGPoint(x: p.x, y: p.y + r))
            ctx.stroke(facets, with: .color(.white.opacity(0.7)), lineWidth: max(0.6, r * 0.06))
            ctx.stroke(gem, with: .color(c(0.1, 0.3, 0.6)), lineWidth: max(1, r * 0.08))
        case .mystery:
            var sack = Path()
            sack.move(to: CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.55))
            sack.addQuadCurve(to: CGPoint(x: p.x - r * 0.95, y: p.y + r * 0.55), control: CGPoint(x: p.x - r * 1.05, y: p.y - r * 0.2))
            sack.addQuadCurve(to: CGPoint(x: p.x + r * 0.95, y: p.y + r * 0.55), control: CGPoint(x: p.x, y: p.y + r * 1.2))
            sack.addQuadCurve(to: CGPoint(x: p.x + r * 0.35, y: p.y - r * 0.55), control: CGPoint(x: p.x + r * 1.05, y: p.y - r * 0.2))
            sack.closeSubpath()
            ctx.fill(sack, with: .linearGradient(Gradient(colors: [c(0.72, 0.5, 0.26), c(0.5, 0.32, 0.14)]),
                                                 startPoint: CGPoint(x: p.x - r, y: p.y - r), endPoint: CGPoint(x: p.x + r, y: p.y + r)))
            ctx.stroke(sack, with: .color(c(0.3, 0.18, 0.07)), lineWidth: max(1, r * 0.07))
            var neck = Path()
            neck.move(to: CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.55))
            neck.addLine(to: CGPoint(x: p.x - r * 0.5, y: p.y - r * 0.95))
            neck.addLine(to: CGPoint(x: p.x + r * 0.5, y: p.y - r * 0.95))
            neck.addLine(to: CGPoint(x: p.x + r * 0.35, y: p.y - r * 0.55))
            ctx.fill(neck, with: .color(c(0.62, 0.42, 0.2)))
            ctx.stroke(neck, with: .color(c(0.3, 0.18, 0.07)), lineWidth: max(1, r * 0.06))
            ctx.fill(Path(roundedRect: CGRect(x: p.x - r * 0.45, y: p.y - r * 0.62, width: r * 0.9, height: r * 0.16), cornerRadius: r * 0.06),
                     with: .color(c(0.9, 0.78, 0.45)))
            ctx.draw(ctx.resolve(Text("?").font(.system(size: r * 1.05, weight: .black, design: .rounded)).foregroundStyle(c(0.3, 0.15, 0.04))),
                     at: CGPoint(x: p.x, y: p.y + r * 0.22))
        }
    }

    /// The grabber: a hub and two curved metal prongs, pointing along the rope.
    static func claw(_ ctx: GraphicsContext, at tip: CGPoint, angle: Double, size s: CGFloat, open: Bool) {
        var g = ctx
        g.translateBy(x: tip.x, y: tip.y)
        g.rotate(by: .radians(-angle))
        let spread: CGFloat = open ? 1 : 0.45
        var prongs = Path()
        for side: CGFloat in [-1, 1] {
            prongs.move(to: CGPoint(x: 0, y: 0))
            prongs.addQuadCurve(to: CGPoint(x: side * s * 0.35 * spread, y: s * 1.3),
                                control: CGPoint(x: side * s * 1.2 * spread, y: s * 0.55))
        }
        g.stroke(prongs, with: .color(c(0.18, 0.18, 0.2)), style: StrokeStyle(lineWidth: s * 0.42, lineCap: .round))
        g.stroke(prongs, with: .color(c(0.78, 0.8, 0.84)), style: StrokeStyle(lineWidth: s * 0.24, lineCap: .round))
        g.fill(Path(roundedRect: CGRect(x: -s * 0.14, y: -s * 0.6, width: s * 0.28, height: s * 0.6), cornerRadius: s * 0.08), with: .color(c(0.5, 0.52, 0.56)))
        g.fill(Path(ellipseIn: CGRect(x: -s * 0.34, y: -s * 0.34, width: s * 0.68, height: s * 0.68)),
               with: .radialGradient(Gradient(colors: [c(0.9, 0.92, 0.95), c(0.45, 0.47, 0.52)]),
                                     center: CGPoint(x: -s * 0.1, y: -s * 0.1), startRadius: 0, endRadius: s * 0.4))
        g.stroke(Path(ellipseIn: CGRect(x: -s * 0.34, y: -s * 0.34, width: s * 0.68, height: s * 0.68)), with: .color(c(0.18, 0.18, 0.2)), lineWidth: max(1, s * 0.08))
    }

    /// The wooden winch the rope spools from; it turns as the rope pays out and reels in.
    static func winch(_ ctx: GraphicsContext, at p: CGPoint, size s: CGFloat, turn: Double) {
        let wood = c(0.6, 0.38, 0.18), dark = c(0.32, 0.19, 0.08)
        var legs = Path()
        legs.move(to: CGPoint(x: p.x - s * 0.7, y: p.y + s * 0.95)); legs.addLine(to: p)
        legs.move(to: CGPoint(x: p.x + s * 0.7, y: p.y + s * 0.95)); legs.addLine(to: p)
        ctx.stroke(legs, with: .color(dark), style: StrokeStyle(lineWidth: s * 0.2, lineCap: .round))
        ctx.stroke(legs, with: .color(wood), style: StrokeStyle(lineWidth: s * 0.12, lineCap: .round))
        let r = s * 0.55
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(wood))
        var spokes = Path()
        for k in 0..<4 {
            let a = turn + Double(k) * .pi / 2
            spokes.move(to: p)
            spokes.addLine(to: CGPoint(x: p.x + CGFloat(cos(a)) * r * 0.9, y: p.y + CGFloat(sin(a)) * r * 0.9))
        }
        ctx.stroke(spokes, with: .color(dark), lineWidth: max(1, s * 0.08))
        ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(dark), lineWidth: max(1, s * 0.1))
        let hx = p.x + CGFloat(cos(turn)) * r * 0.75, hy = p.y + CGFloat(sin(turn)) * r * 0.75
        ctx.fill(Path(ellipseIn: CGRect(x: hx - s * 0.12, y: hy - s * 0.12, width: s * 0.24, height: s * 0.24)), with: .color(c(0.85, 0.85, 0.88)))
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.12, y: p.y - s * 0.12, width: s * 0.24, height: s * 0.24)), with: .color(dark))
    }
}

/// The static backdrop: the orange surface, the prospector's dark-blue dome and the sandy strata.
private struct MinerBackdrop: View, Equatable {
    let size: CGSize

    var body: some View {
        Canvas { ctx, s in
            let w = s.width, h = s.height
            let groundY = h * 0.24
            // Underground: sandy layers darkening with depth.
            ctx.fill(Path(CGRect(x: 0, y: groundY, width: w, height: h - groundY)),
                     with: .linearGradient(Gradient(colors: [MinerArt.c(0.97, 0.8, 0.47), MinerArt.c(0.86, 0.6, 0.3), MinerArt.c(0.66, 0.42, 0.19)]),
                                           startPoint: CGPoint(x: 0, y: groundY), endPoint: CGPoint(x: 0, y: h)))
            for (i, f) in [0.36, 0.52, 0.68, 0.84].enumerated() {
                let y0 = h * CGFloat(f)
                var band = Path()
                band.move(to: CGPoint(x: 0, y: y0))
                var x: CGFloat = 0
                while x <= w + 1 {
                    band.addLine(to: CGPoint(x: x, y: y0 + CGFloat(sin(Double(x / w) * 7 + Double(i) * 1.9)) * h * 0.012))
                    x += w / 40
                }
                x = w
                while x >= -1 {
                    band.addLine(to: CGPoint(x: x, y: y0 + h * 0.055 + CGFloat(sin(Double(x / w) * 6 + Double(i) * 2.7)) * h * 0.014))
                    x -= w / 40
                }
                band.closeSubpath()
                ctx.fill(band, with: .color(MinerArt.c(0.62, 0.38, 0.15).opacity(0.18)))
            }
            // Pebbles.
            for k in 0..<60 {
                let fx = CGFloat((sin(Double(k) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)).magnitude
                let fy = CGFloat((sin(Double(k) * 78.233) * 12345.678).truncatingRemainder(dividingBy: 1)).magnitude
                let r = 1.2 + CGFloat(k % 3)
                ctx.fill(Path(ellipseIn: CGRect(x: fx * w, y: groundY + 6 + fy * (h - groundY - 10), width: r * 2, height: r * 1.4)),
                         with: .color(MinerArt.c(0.45, 0.28, 0.12).opacity(0.35)))
            }
            // The orange surface and the dark-blue dome the prospector works in.
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: groundY)),
                     with: .linearGradient(Gradient(colors: [MinerArt.c(1, 0.74, 0.2), MinerArt.c(0.98, 0.6, 0.1)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: groundY)))
            let R = groundY * 0.8
            var dome = Path()
            dome.move(to: CGPoint(x: w / 2 - R, y: groundY))
            dome.addArc(center: CGPoint(x: w / 2, y: groundY), radius: R, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            dome.closeSubpath()
            ctx.fill(dome, with: .linearGradient(Gradient(colors: [MinerArt.c(0.2, 0.3, 0.62), MinerArt.c(0.1, 0.16, 0.44)]),
                                                 startPoint: CGPoint(x: 0, y: groundY - R), endPoint: CGPoint(x: 0, y: groundY)))
            ctx.stroke(dome, with: .color(MinerArt.c(0.06, 0.08, 0.25)), lineWidth: 2)
            // Ground line.
            ctx.fill(Path(CGRect(x: 0, y: groundY - 1.5, width: w, height: 4)), with: .color(MinerArt.c(0.45, 0.26, 0.08)))
        }
        .allowsHitTesting(false)
    }
}
