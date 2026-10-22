//
//  QuickDrawGame.swift
//  A Banana Game
//
//  Quick Draw — a pixel-art cowboy duel at high noon. Two gunslingers face off across a
//  dusty street. Three bananas light up one at a time; the instant the THIRD banana
//  appears, tap anywhere to shoot the rival before he shoots you. Tap before the third
//  banana = you drew too soon. Purely reflex. Tap-only.
//  7 levels: the rival's draw gets quicker — near-impossible by L6–7. The street shifts
//  from bright noon toward a blood-red night as you climb.
//
//  Drawn as a Western main street: false-front saloon, store, bank (its clock creeps from noon
//  toward midnight with the level) and sheriff's office, mesas and the sun or moon in the gap,
//  three banana lanterns on a rope as the GO signal, stick-figure gunslingers in hats (the
//  rival masked like an outlaw), a tumbleweed rolling through during the count.
//

import SwiftUI

enum QuickDrawGame {
    static let definition = GameDefinition(
        id: "quick-draw", title: "Quick Draw", emoji: "🍌",
        genre: .reflex, levelCount: 7,
        manual: GameManual(
            bullets: [
                "A high-noon duel. Three bananas light up one at a time.",
                "The instant the THIRD one appears, tap anywhere to shoot before your rival.",
                "Tapping before the third banana means you drew too soon and lose.",
            ],
            bulletsVI: [
                "Một cuộc đấu súng giữa trưa. Ba quả chuối sáng lên lần lượt.",
                "Ngay khi quả THỨ BA xuất hiện, chạm bất kỳ đâu để bắn trước đối thủ.",
                "Chạm trước quả chuối thứ ba nghĩa là bạn rút súng quá sớm và thua.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(QuickDrawView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct QuickDrawView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    // The rival's reaction window shrinks fast: L1 is generous, L6–7 near-impossible.
    private var rivalReaction: Double {
        max(0.16, 0.66 - Double(level) * 0.07) + Double.random(in: -0.03...0.05)
    }

    private enum Phase { case counting, draw, done }
    @State private var phase: Phase = .counting
    @State private var bananasShown = 0     // 0…3; the 3rd is the GO signal
    @State private var outcome: String? = nil   // brief on-screen result

    // Who fired the winning/losing shot — drives the muzzle flash, recoil, and topple.
    private enum Gunman { case you, rival }
    @State private var shooter: Gunman? = nil
    @State private var shakeTick = 0
    @State private var demoTapID = 0   // bumps per demo tap → a fresh DemoTapRipple
    @State private var tumbleStart = Date()   // presentation: when this duel's tumbleweed set off

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let lay = QuickDrawLayout(w: w, h: h, demo: isDemo)
            let youX = w * 0.24, rivalX = w * 0.76

            ZStack {
                WesternStreet(level: level, demo: isDemo).equatable()

                // Tumbleweed bowling across the street while the count runs.
                Tumbleweed(start: tumbleStart, rolling: phase == .counting, lay: lay)

                // The three banana lanterns on the rope — the GO signal.
                ForEach(0..<3, id: \.self) { i in
                    BananaLantern(lit: i < bananasShown, size: lay.lantern)
                        .position(lay.lanternPoint(i))
                }
                .animation(.spring(duration: 0.22), value: bananasShown)

                // The two gunslingers.
                gunslinger(you: true, fired: shooter == .you, hit: shooter == .rival, h: lay.cowboyH)
                    .frame(width: lay.cowboyW, height: lay.cowboyH)
                    .position(x: youX, y: lay.cowboyY)
                gunslinger(you: false, fired: shooter == .rival, hit: shooter == .you, h: lay.cowboyH)
                    .frame(width: lay.cowboyW, height: lay.cowboyH)
                    .position(x: rivalX, y: lay.cowboyY)

                // Muzzle flash + smoke at the firing cowboy's gun. The firing pose's gun tip sits at
                // unit (~0.89, ~0.35) of the figure, which spans `cowboyH` around (x, cowboyY).
                if let s = shooter {
                    let reach = 0.39 * lay.cowboyH
                    let fx = s == .you ? youX + reach : rivalX - reach
                    let fy = lay.cowboyY - 0.15 * lay.cowboyH
                    MuzzleFlash(size: lay.cowboyH * 0.3, facingRight: s == .you)
                        .position(x: fx, y: fy)
                    ParticleBurstView(color: Color(red: 1, green: 0.8, blue: 0.3), count: 10, spread: 40)
                        .position(x: fx, y: fy)
                }

                // Demo: a tap ripple where the (tap-anywhere) shot lands.
                if isDemo && demoTapID > 0 {
                    DemoTapRipple()
                        .id(demoTapID)
                        .position(x: w * 0.5, y: h * 0.66)
                }

                // DRAW! and the verdict, poster-style.
                if !promptText.isEmpty {
                    posterText(promptText)
                        .position(x: w * 0.5, y: lay.bannerY)
                        .transition(.scale(scale: 1.6).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.25), value: promptText)
            .frame(width: w, height: h)
            .contentShape(Rectangle())
            .onTapGesture { shoot() }
            .screenShake(shakeTick, amount: 7)
        }
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: phase) { _, now in if now == .counting { tumbleStart = Date() } }
        .task { isDemo ? await runDemo() : await run() }
    }

    /// A stick-figure gunslinger in his hat (and, for the rival, an outlaw's bandana over the face).
    private func gunslinger(you: Bool, fired: Bool, hit: Bool, h: CGFloat) -> some View {
        // Authored facing right; mirror for the rival.
        let flip: CGFloat = you ? 1 : -1
        let color = you ? BananaTheme.banana : Color(red: 0.88, green: 0.26, blue: 0.28)
        // A hit gunslinger topples away from the shooter (his hat flying off); recoil kicks the shooter back.
        return ZStack {
            StickFigure(pose: fired ? .firing : .standing, color: color, gun: true)
            CowboyGear(outlaw: !you)
            CowboyHat(outlaw: !you)
                .offset(x: hit ? -h * 0.3 : 0, y: hit ? -h * 0.32 : 0)
                .rotationEffect(.degrees(hit ? -150 : 0), anchor: UnitPoint(x: 0.5, y: 0.08))
                .opacity(hit ? 0 : 1)
                .animation(.easeOut(duration: 0.55), value: hit)
        }
        .scaleEffect(x: flip, y: 1)
        .rotationEffect(.degrees(hit ? Double(flip) * 82 : 0), anchor: .bottom)
        .offset(x: fired ? -flip * 6 : 0)
        .opacity(hit ? 0.7 : 1)
        .animation(.spring(duration: 0.35), value: hit)
        .animation(.easeOut(duration: 0.12), value: fired)
    }

    private func posterText(_ s: String) -> some View {
        let win = s == L("GOT HIM", "HẠ GỤC"), go = phase == .draw
        let ink: Color = go ? Color(red: 1, green: 0.93, blue: 0.75) : (win ? Color(red: 1, green: 0.85, blue: 0.3) : Color(red: 1, green: 0.36, blue: 0.3))
        return Text(s)
            .font(.system(size: isDemo ? (go ? 34 : 26) : (go ? 52 : 38), weight: .black, design: .serif))
            .tracking(isDemo ? 2 : 3)
            .foregroundStyle(ink)
            .shadow(color: Color(red: 0.25, green: 0.1, blue: 0.03), radius: 0, x: 3, y: 3)
            .shadow(color: .black.opacity(0.5), radius: 6)
            .lineLimit(1).minimumScaleFactor(0.5)
            .padding(.horizontal, 20)
    }

    private var promptText: String {
        if let outcome { return outcome }
        switch phase {
        case .counting: return ""
        case .draw:     return L("DRAW!", "BẮN!")
        case .done:     return ""
        }
    }

    // MARK: - Demo (live manual clip)
    // Fixed rhythm, then a sharp draw ~0.2s after the third banana — well inside the L1
    // rival's ~0.6s window — through the real `shoot()`, so the rival genuinely topples.
    private func runDemo() async {
        let rhythm = [0.75, 0.55, 0.85]
        while !Task.isCancelled {
            phase = .counting
            bananasShown = 0
            outcome = nil
            shooter = nil
            try? await Task.sleep(for: .seconds(0.4))
            for i in 1...3 {
                try? await Task.sleep(for: .seconds(rhythm[i - 1]))
                guard !Task.isCancelled else { return }
                bananasShown = i
                SoundManager.shared.tap(); Haptics.tap()
            }
            phase = .draw
            try? await Task.sleep(for: .seconds(0.2))
            guard !Task.isCancelled else { return }
            demoTapID += 1
            shoot()   // → GOT HIM + the real win() (onWin is a no-op)
            try? await Task.sleep(for: .seconds(1.5))
        }
    }

    // MARK: - Flow

    private func run() async {
        phase = .counting
        bananasShown = 0
        outcome = nil
        shooter = nil
        // Bananas appear one at a time. Each duel picks a random *rhythm* so the pace is
        // inconsistent — sometimes a fast burst then a long wait, sometimes slow-then-quick,
        // etc. — and the GO signal can never be pre-timed.
        let rhythms: [[ClosedRange<Double>]] = [
            [0.60...0.90, 0.60...0.90, 0.60...0.90],   // steady
            [0.90...1.40, 0.55...0.80, 0.25...0.45],   // accelerate: slow → fast
            [0.25...0.45, 0.55...0.80, 0.90...1.40],   // decelerate: fast → slow
            [0.30...0.50, 0.30...0.50, 1.00...1.55],   // burst, then a long hang
            [1.00...1.55, 0.30...0.50, 0.30...0.50],   // long hang, then a burst
            [0.50...0.80, 1.05...1.55, 0.35...0.60]    // syncopated
        ]
        let rhythm = rhythms.randomElement()!
        for i in 1...3 {
            try? await Task.sleep(for: .seconds(Double.random(in: rhythm[i - 1])))
            if Task.isCancelled { return }
            if phase != .counting { return }   // tapped too soon (handled in shoot)
            bananasShown = i
            SoundManager.shared.tap(); Haptics.tap()
        }
        // Third banana is up → the duel is live.
        phase = .draw
        try? await Task.sleep(for: .seconds(rivalReaction))
        if Task.isCancelled { return }
        if phase == .draw {
            outcome = L("TOO SLOW", "QUÁ CHẬM")
            shooter = .rival   // rival drew first
            shakeTick += 1
            fail()
        }
    }

    private func shoot() {
        switch phase {
        case .counting:
            outcome = L("TOO SOON", "QUÁ SỚM")
            fail()
        case .draw:
            outcome = L("GOT HIM", "HẠ GỤC")
            shooter = .you
            shakeTick += 1
            win()
        case .done:
            break
        }
    }

    private func win() {
        guard phase != .done else { return }
        phase = .done
        Haptics.tap(); SoundManager.shared.tap()
        onWin()
    }

    private func fail() {
        guard phase != .done else { return }
        phase = .done
        SoundManager.shared.error()
        onFail()
    }
}

// MARK: - The Western street

/// Where everything sits for this card size (shared by the static street and the live pieces).
private struct QuickDrawLayout {
    let w: CGFloat, h: CGFloat, demo: Bool

    var baseY: CGFloat { h * (demo ? 0.6 : 0.62) }          // boardwalk / foot of the buildings
    var feetY: CGFloat { h * 0.9 }
    var cowboyH: CGFloat { h * (demo ? 0.44 : 0.37) }
    var cowboyW: CGFloat { w * 0.3 }
    var cowboyY: CGFloat { feetY - cowboyH * 0.47 }
    var saloonTop: CGFloat { baseY - baseY * 0.56 }
    var lantern: CGFloat { min(w * 0.11, h * (demo ? 0.15 : 0.085)) }
    /// DRAW! / the verdict sit in the open sky above the rope, never over the GO lanterns.
    var bannerY: CGFloat { h * (demo ? 0.17 : 0.19) }
    // The rope runs from the saloon's corner to the bank's, sagging over the gap.
    var ropeA: CGPoint { CGPoint(x: w * 0.32, y: saloonTop + h * 0.035) }
    var ropeB: CGPoint { CGPoint(x: w * 0.68, y: saloonTop + h * 0.035) }
    var sag: CGFloat { h * (demo ? 0.05 : 0.04) }

    func ropePoint(_ t: CGFloat) -> CGPoint {
        let c = CGPoint(x: (ropeA.x + ropeB.x) / 2, y: ropeA.y + sag * 2)
        let u: CGFloat = 1 - t
        let x: CGFloat = u * u * ropeA.x + 2 * u * t * c.x + t * t * ropeB.x
        let y: CGFloat = u * u * ropeA.y + 2 * u * t * c.y + t * t * ropeB.y
        return CGPoint(x: x, y: y)
    }
    func lanternPoint(_ i: Int) -> CGPoint {
        let p = ropePoint([0.18, 0.5, 0.82][max(0, min(2, i))])
        return CGPoint(x: p.x, y: p.y + lantern * 0.72)
    }
}

private enum QuickDrawArt {
    // Noon street darkening to a red-night showdown (one entry per level).
    static let skyTops: [Color] = [Color(red: 0.45, green: 0.70, blue: 0.95), Color(red: 0.62, green: 0.74, blue: 0.90),
                                   Color(red: 0.95, green: 0.70, blue: 0.42), Color(red: 0.90, green: 0.50, blue: 0.30),
                                   Color(red: 0.40, green: 0.26, blue: 0.42), Color(red: 0.16, green: 0.12, blue: 0.28),
                                   Color(red: 0.28, green: 0.05, blue: 0.08)]
    static let skyBottoms: [Color] = [Color(red: 0.85, green: 0.72, blue: 0.48), Color(red: 0.88, green: 0.72, blue: 0.46),
                                      Color(red: 0.86, green: 0.56, blue: 0.30), Color(red: 0.98, green: 0.62, blue: 0.3),
                                      Color(red: 0.62, green: 0.34, blue: 0.36), Color(red: 0.14, green: 0.12, blue: 0.22),
                                      Color(red: 0.36, green: 0.06, blue: 0.06)]
    static let sands: [Color] = [Color(red: 0.86, green: 0.70, blue: 0.44), Color(red: 0.83, green: 0.66, blue: 0.40),
                                 Color(red: 0.76, green: 0.55, blue: 0.32), Color(red: 0.62, green: 0.42, blue: 0.27),
                                 Color(red: 0.36, green: 0.28, blue: 0.27), Color(red: 0.2, green: 0.17, blue: 0.2),
                                 Color(red: 0.26, green: 0.11, blue: 0.1)]
    /// How far the town has sunk into shadow, and whether its lamps are lit.
    static let dusk: [Double] = [0, 0.04, 0.14, 0.36, 0.55, 0.68, 0.7]
    /// The bank clock creeps from high noon toward midnight.
    static let hours: [Double] = [12, 2, 4, 6, 8, 10, 12]

    static func hash(_ n: Double) -> CGFloat {
        let v: Double = sin(n * 12.9898) * 43758.5453
        return CGFloat(v - floor(v))
    }

    static func street(_ ctx: GraphicsContext, _ s: CGSize, level: Int, demo: Bool) {
        let L = max(1, min(level, 7)) - 1
        let lay = QuickDrawLayout(w: s.width, h: s.height, demo: demo)
        let w = s.width, h = s.height, base = lay.baseY
        let night = L >= 4
        let tint: Color = L == 6 ? Color(red: 0.14, green: 0.02, blue: 0.03) : Color(red: 0.07, green: 0.06, blue: 0.12)
        let d = dusk[L]
        func tone(_ c: Color) -> Color { c.mix(with: tint, by: d) }

        // Sky, stars, sun or moon, mesas.
        ctx.fill(Path(CGRect(origin: .zero, size: s)),
                 with: .linearGradient(Gradient(colors: [skyTops[L], skyBottoms[L]]), startPoint: .zero, endPoint: CGPoint(x: 0, y: base)))
        if night {
            var stars = Path()
            for k in 0..<50 {
                let x: CGFloat = hash(Double(k) * 1.7) * w
                let y: CGFloat = hash(Double(k) * 3.1 + 0.5) * base * 0.8
                let r: CGFloat = 0.5 + hash(Double(k) * 5.3) * 1.1
                stars.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
            ctx.fill(stars, with: .color(.white.opacity(0.75)))
        }
        sunOrMoon(ctx, L, w: w, h: h, base: base)
        mesas(ctx, color: tone(skyBottoms[L].mix(with: Color(red: 0.55, green: 0.3, blue: 0.2), by: 0.45)).shade(0.12), w: w, base: base, h: h)

        // The street.
        let ground = CGRect(x: 0, y: base, width: w, height: h - base)
        ctx.fill(Path(ground), with: .linearGradient(Gradient(colors: [sands[L].shade(0.1), sands[L].lit(0.06)]),
                                                     startPoint: CGPoint(x: 0, y: base), endPoint: CGPoint(x: 0, y: h)))
        for (k, y) in [lay.feetY - h * 0.1, lay.feetY + h * 0.035].enumerated() {
            var rut = Path()
            rut.move(to: CGPoint(x: 0, y: y))
            rut.addCurve(to: CGPoint(x: w, y: y + h * 0.01), control1: CGPoint(x: w * 0.3, y: y - h * 0.012), control2: CGPoint(x: w * 0.7, y: y + h * 0.018))
            ctx.stroke(rut, with: .color(sands[L].shade(0.18).opacity(0.55)), lineWidth: h * (k == 0 ? 0.008 : 0.012))
        }
        var pebbles = Path()
        for k in 0..<36 {
            let x: CGFloat = hash(Double(k) * 2.3 + 9) * w
            let y: CGFloat = base + h * 0.03 + hash(Double(k) * 4.7 + 1) * (h - base - h * 0.03)
            let r: CGFloat = 0.8 + hash(Double(k) * 6.1) * 1.6
            pebbles.addEllipse(in: CGRect(x: x - r * 1.4, y: y - r, width: r * 2.8, height: r * 2))
        }
        ctx.fill(pebbles, with: .color(sands[L].shade(0.3).opacity(0.6)))

        // The town, either side of the gap.
        let wood1 = tone(Color(red: 0.72, green: 0.45, blue: 0.24)), wood2 = tone(Color(red: 0.6, green: 0.36, blue: 0.2))
        let wood3 = tone(Color(red: 0.8, green: 0.58, blue: 0.34)), brick = tone(Color(red: 0.62, green: 0.28, blue: 0.2))
        let trim = tone(Color(red: 0.92, green: 0.82, blue: 0.62)), deep = tone(Color(red: 0.25, green: 0.14, blue: 0.08))
        let glass: Color = night ? Color(red: 1, green: 0.78, blue: 0.4) : tone(skyTops[L].mix(with: .black, by: 0.45))
        let store = CGRect(x: -w * 0.04, y: base - base * 0.38, width: w * 0.13, height: base * 0.38)
        let saloon = CGRect(x: w * 0.08, y: lay.saloonTop, width: w * 0.24, height: base - lay.saloonTop)
        let bank = CGRect(x: w * 0.68, y: lay.saloonTop, width: w * 0.24, height: base - lay.saloonTop)
        let jail = CGRect(x: w * 0.91, y: base - base * 0.4, width: w * 0.13, height: base * 0.4)
        facade(ctx, store, wood: wood3, trim: trim, deep: deep)
        window(ctx, CGRect(x: store.minX + store.width * 0.4, y: store.minY + store.height * 0.42, width: store.width * 0.44, height: store.height * 0.28), glass: glass, lit: night, frame: trim)
        facade(ctx, jail, wood: wood2, trim: trim, deep: deep)
        window(ctx, CGRect(x: jail.minX + jail.width * 0.18, y: jail.minY + jail.height * 0.42, width: jail.width * 0.42, height: jail.height * 0.28), glass: glass, lit: night, frame: trim, bars: true)
        sign(ctx, CGRect(x: jail.minX + jail.width * 0.12, y: jail.minY + jail.height * 0.14, width: jail.width * 0.7, height: jail.height * 0.16), board: deep) { c, r in
            star(c, center: CGPoint(x: r.midX, y: r.midY), r: r.height * 0.36, color: Color(red: 0.95, green: 0.78, blue: 0.3))
        }
        saloonFront(ctx, saloon, wood: wood1, trim: trim, deep: deep, glass: glass, lit: night)
        bankFront(ctx, bank, brick: brick, trim: trim, deep: deep, glass: glass, lit: night, hour: hours[L])

        // Boardwalks, hitching rail, barrels, trough.
        for r in [CGRect(x: -w * 0.04, y: base - h * 0.012, width: w * 0.37, height: h * 0.028),
                  CGRect(x: w * 0.67, y: base - h * 0.012, width: w * 0.37, height: h * 0.028)] {
            ctx.fill(Path(r), with: .color(tone(Color(red: 0.62, green: 0.42, blue: 0.24))))
            ctx.fill(Path(CGRect(x: r.minX, y: r.maxY - r.height * 0.35, width: r.width, height: r.height * 0.35)), with: .color(deep.opacity(0.8)))
            var seams = Path()
            var x = r.minX
            while x < r.maxX { seams.move(to: CGPoint(x: x, y: r.minY)); seams.addLine(to: CGPoint(x: x, y: r.maxY - r.height * 0.35)); x += h * 0.025 }
            ctx.stroke(seams, with: .color(deep.opacity(0.35)), lineWidth: 0.8)
        }
        hitchingRail(ctx, x0: w * 0.1, x1: w * 0.3, y: base + h * 0.05, h: h, color: tone(Color(red: 0.5, green: 0.32, blue: 0.17)))
        barrel(ctx, CGRect(x: w * 0.33, y: base - h * 0.055, width: h * 0.04, height: h * 0.055), wood: tone(Color(red: 0.6, green: 0.38, blue: 0.2)), hoop: deep)
        barrel(ctx, CGRect(x: w * 0.33 + h * 0.035, y: base - h * 0.045, width: h * 0.036, height: h * 0.045), wood: tone(Color(red: 0.55, green: 0.34, blue: 0.18)), hoop: deep)
        trough(ctx, CGRect(x: w * 0.7, y: base + h * 0.022, width: w * 0.16, height: h * 0.03), wood: tone(Color(red: 0.52, green: 0.33, blue: 0.18)), water: tone(Color(red: 0.35, green: 0.55, blue: 0.7)))

        // The rope and the strings the lanterns hang from.
        var rope = Path()
        rope.move(to: lay.ropeA)
        rope.addQuadCurve(to: lay.ropeB, control: CGPoint(x: (lay.ropeA.x + lay.ropeB.x) / 2, y: lay.ropeA.y + lay.sag * 2))
        ctx.stroke(rope, with: .color(tone(Color(red: 0.3, green: 0.2, blue: 0.12))), lineWidth: max(1.2, h * 0.004))
        for i in 0..<3 {
            let top = lay.ropePoint([0.18, 0.5, 0.82][i])
            var string = Path()
            string.move(to: top); string.addLine(to: CGPoint(x: top.x, y: lay.lanternPoint(i).y - lay.lantern * 0.36))
            ctx.stroke(string, with: .color(tone(Color(red: 0.3, green: 0.2, blue: 0.12))), lineWidth: 1)
        }

        // Saguaros in the foreground corners.
        let cactus = tone(Color(red: 0.24, green: 0.48, blue: 0.26))
        saguaro(ctx, base: CGPoint(x: w * 0.035, y: lay.feetY + h * 0.06), height: h * 0.24, color: cactus, flip: false)
        saguaro(ctx, base: CGPoint(x: w * 0.965, y: lay.feetY + h * 0.07), height: h * 0.2, color: cactus, flip: true)
    }

    static func sunOrMoon(_ ctx: GraphicsContext, _ L: Int, w: CGFloat, h: CGFloat, base: CGFloat) {
        let cx = w * 0.5
        switch L {
        case 0, 1, 2:
            let y: CGFloat = [h * 0.08, h * 0.11, h * 0.17][L]
            let r: CGFloat = w * 0.06
            let core: Color = L == 2 ? Color(red: 1, green: 0.88, blue: 0.55) : Color(red: 1, green: 0.97, blue: 0.82)
            ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 4, y: y - r * 4, width: r * 8, height: r * 8)),
                     with: .radialGradient(Gradient(colors: [core.opacity(0.55), core.opacity(0)]), center: CGPoint(x: cx, y: y), startRadius: r, endRadius: r * 4))
            ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: y - r, width: r * 2, height: r * 2)), with: .color(core))
        case 3:
            let y = base - h * 0.03, r = w * 0.11
            ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 3.4, y: y - r * 3.4, width: r * 6.8, height: r * 6.8)),
                     with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.6, blue: 0.25).opacity(0.6), .clear]), center: CGPoint(x: cx, y: y), startRadius: r, endRadius: r * 3.4))
            ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: y - r, width: r * 2, height: r * 2)),
                     with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.8, blue: 0.4), Color(red: 0.98, green: 0.38, blue: 0.16)]),
                                           startPoint: CGPoint(x: cx, y: y - r), endPoint: CGPoint(x: cx, y: y + r)))
        case 4:
            ctx.fill(Path(CGRect(x: 0, y: base - h * 0.12, width: w, height: h * 0.12)),
                     with: .linearGradient(Gradient(colors: [.clear, Color(red: 1, green: 0.5, blue: 0.3).opacity(0.35)]),
                                           startPoint: CGPoint(x: 0, y: base - h * 0.12), endPoint: CGPoint(x: 0, y: base)))
            moon(ctx, center: CGPoint(x: cx + w * 0.05, y: h * 0.1), r: w * 0.035, color: Color(white: 0.95), crescent: true)
        case 5:
            moon(ctx, center: CGPoint(x: cx, y: h * 0.1), r: w * 0.055, color: Color(red: 0.95, green: 0.95, blue: 0.88), crescent: false)
        default:
            moon(ctx, center: CGPoint(x: cx, y: h * 0.13), r: w * 0.085, color: Color(red: 0.86, green: 0.18, blue: 0.12), crescent: false)
        }
    }

    static func moon(_ ctx: GraphicsContext, center c: CGPoint, r: CGFloat, color: Color, crescent: Bool) {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 3, y: c.y - r * 3, width: r * 6, height: r * 6)),
                 with: .radialGradient(Gradient(colors: [color.opacity(0.35), color.opacity(0)]), center: c, startRadius: r, endRadius: r * 3))
        var disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        if crescent {
            disc.addPath(Path(ellipseIn: CGRect(x: c.x - r * 0.55, y: c.y - r * 1.15, width: r * 2, height: r * 2)))
            ctx.fill(disc, with: .color(color), style: FillStyle(eoFill: true))
            return
        }
        ctx.fill(disc, with: .color(color))
        for (dx, dy, rr) in [(-0.3, -0.2, 0.22), (0.25, 0.25, 0.16), (0.2, -0.35, 0.1)] as [(CGFloat, CGFloat, CGFloat)] {
            ctx.fill(Path(ellipseIn: CGRect(x: c.x + dx * r - rr * r, y: c.y + dy * r - rr * r, width: rr * r * 2, height: rr * r * 2)),
                     with: .color(color.shade(0.14)))
        }
    }

    /// Flat-topped buttes along the horizon.
    static func mesas(_ ctx: GraphicsContext, color: Color, w: CGFloat, base: CGFloat, h: CGFloat) {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: base))
        let tops: [(CGFloat, CGFloat, CGFloat)] = [(0.0, 0.06, 0.1), (0.2, 0.1, 0.18), (0.38, 0.13, 0.14), (0.55, 0.08, 0.22), (0.78, 0.12, 0.12)]
        for (x0, height, width) in tops {
            let x = x0 * w, top = base - height * h, ww = width * w
            p.addLine(to: CGPoint(x: x, y: base))
            p.addLine(to: CGPoint(x: x + ww * 0.12, y: top))
            p.addLine(to: CGPoint(x: x + ww * 0.88, y: top))
            p.addLine(to: CGPoint(x: x + ww, y: base))
        }
        p.addLine(to: CGPoint(x: w, y: base))
        p.closeSubpath()
        ctx.fill(p, with: .color(color))
    }

    /// A false-front wooden building: vertical planks, a cornice, and a door.
    static func facade(_ ctx: GraphicsContext, _ r: CGRect, wood: Color, trim: Color, deep: Color) {
        ctx.fill(Path(r), with: .linearGradient(Gradient(colors: [wood.lit(0.06), wood.shade(0.1)]),
                                                startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.minX, y: r.maxY)))
        var planks = Path()
        var x = r.minX + r.width / 7
        while x < r.maxX { planks.move(to: CGPoint(x: x, y: r.minY)); planks.addLine(to: CGPoint(x: x, y: r.maxY)); x += r.width / 7 }
        ctx.stroke(planks, with: .color(deep.opacity(0.35)), lineWidth: 0.8)
        ctx.fill(Path(CGRect(x: r.minX - 2, y: r.minY, width: r.width + 4, height: max(3, r.height * 0.05))), with: .color(trim))
        ctx.fill(Path(CGRect(x: r.minX - 2, y: r.minY + max(3, r.height * 0.05), width: r.width + 4, height: 1.5)), with: .color(deep.opacity(0.6)))
        let door = CGRect(x: r.midX - r.width * 0.14, y: r.maxY - r.height * 0.32, width: r.width * 0.28, height: r.height * 0.32)
        ctx.fill(Path(door), with: .color(deep))
        ctx.stroke(Path(door), with: .color(trim.opacity(0.7)), lineWidth: 1)
    }

    static func window(_ ctx: GraphicsContext, _ r: CGRect, glass: Color, lit: Bool, frame: Color, bars: Bool = false) {
        if lit {
            ctx.fill(Path(ellipseIn: r.insetBy(dx: -r.width * 0.5, dy: -r.height * 0.5)),
                     with: .radialGradient(Gradient(colors: [glass.opacity(0.35), glass.opacity(0)]),
                                           center: CGPoint(x: r.midX, y: r.midY), startRadius: 0, endRadius: max(r.width, r.height)))
        }
        ctx.fill(Path(r), with: .color(glass))
        var mullion = Path()
        mullion.move(to: CGPoint(x: r.midX, y: r.minY)); mullion.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        mullion.move(to: CGPoint(x: r.minX, y: r.midY)); mullion.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        if bars {
            for k in 1..<4 { let x = r.minX + r.width * CGFloat(k) / 4; mullion.move(to: CGPoint(x: x, y: r.minY)); mullion.addLine(to: CGPoint(x: x, y: r.maxY)) }
        }
        ctx.stroke(mullion, with: .color(frame.shade(0.3)), lineWidth: 1)
        ctx.stroke(Path(r), with: .color(frame), lineWidth: 1.5)
    }

    /// A plank sign with a painted picture on it.
    static func sign(_ ctx: GraphicsContext, _ r: CGRect, board: Color, paint: (GraphicsContext, CGRect) -> Void) {
        ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(board))
        ctx.stroke(Path(roundedRect: r, cornerRadius: 2), with: .color(Color(red: 0.9, green: 0.8, blue: 0.6).opacity(0.6)), lineWidth: 1)
        paint(ctx, r)
    }

    static func star(_ ctx: GraphicsContext, center c: CGPoint, r: CGFloat, color: Color) {
        var p = Path()
        for k in 0..<10 {
            let a: CGFloat = -.pi / 2 + CGFloat(k) * .pi / 5
            let rr: CGFloat = k % 2 == 0 ? r : r * 0.45
            let pt = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
            if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        ctx.fill(p, with: .color(color))
    }

    /// The saloon: tall false front, sign with a painted mug, balcony with railing, batwing doors.
    static func saloonFront(_ ctx: GraphicsContext, _ r: CGRect, wood: Color, trim: Color, deep: Color, glass: Color, lit: Bool) {
        facade(ctx, r, wood: wood, trim: trim, deep: deep)
        // Stepped parapet.
        let step = CGRect(x: r.midX - r.width * 0.2, y: r.minY - r.height * 0.06, width: r.width * 0.4, height: r.height * 0.06 + 2)
        ctx.fill(Path(step), with: .color(wood))
        ctx.fill(Path(CGRect(x: step.minX - 2, y: step.minY, width: step.width + 4, height: max(2.5, r.height * 0.03))), with: .color(trim))
        sign(ctx, CGRect(x: r.minX + r.width * 0.1, y: r.minY + r.height * 0.09, width: r.width * 0.8, height: r.height * 0.13), board: deep) { c, s in
            // A foaming mug.
            let m = CGRect(x: s.midX - s.height * 0.3, y: s.minY + s.height * 0.25, width: s.height * 0.5, height: s.height * 0.6)
            c.fill(Path(roundedRect: m, cornerRadius: 2), with: .color(Color(red: 0.98, green: 0.75, blue: 0.25)))
            c.fill(Path(ellipseIn: CGRect(x: m.minX - 1, y: m.minY - s.height * 0.14, width: m.width + 2, height: s.height * 0.26)), with: .color(.white))
            c.stroke(Path(ellipseIn: CGRect(x: m.maxX - 1, y: m.minY + m.height * 0.2, width: m.width * 0.5, height: m.height * 0.5)),
                     with: .color(Color(red: 0.98, green: 0.75, blue: 0.25)), lineWidth: 1.5)
        }
        // Upper windows, then the balcony.
        let balY = r.minY + r.height * 0.52
        for k in 0..<2 {
            let wr = CGRect(x: r.minX + r.width * (0.16 + CGFloat(k) * 0.44), y: r.minY + r.height * 0.28, width: r.width * 0.24, height: r.height * 0.18)
            window(ctx, wr, glass: glass, lit: lit, frame: trim)
        }
        ctx.fill(Path(CGRect(x: r.minX - r.width * 0.04, y: balY, width: r.width * 1.08, height: max(3, r.height * 0.03))), with: .color(deep))
        var rail = Path()
        rail.move(to: CGPoint(x: r.minX - r.width * 0.04, y: balY - r.height * 0.07)); rail.addLine(to: CGPoint(x: r.maxX + r.width * 0.04, y: balY - r.height * 0.07))
        var x = r.minX
        while x <= r.maxX + 1 { rail.move(to: CGPoint(x: x, y: balY - r.height * 0.07)); rail.addLine(to: CGPoint(x: x, y: balY)); x += r.width / 10 }
        ctx.stroke(rail, with: .color(trim.opacity(0.85)), lineWidth: 1.2)
        // Posts down to the boardwalk.
        for px in [r.minX + r.width * 0.02, r.maxX - r.width * 0.02] {
            ctx.fill(Path(CGRect(x: px - 1.5, y: balY, width: 3, height: r.maxY - balY)), with: .color(deep))
        }
        // Batwing doors over the lamplit doorway.
        let door = CGRect(x: r.midX - r.width * 0.14, y: r.maxY - r.height * 0.32, width: r.width * 0.28, height: r.height * 0.32)
        ctx.fill(Path(door), with: .color(lit ? Color(red: 1, green: 0.72, blue: 0.35) : deep))
        for k in 0..<2 {
            let bw = CGRect(x: door.minX + CGFloat(k) * door.width * 0.5 + 1, y: door.minY + door.height * 0.28, width: door.width * 0.5 - 2, height: door.height * 0.42)
            ctx.fill(Path(roundedRect: bw, cornerRadius: 1.5), with: .color(wood.lit(0.12)))
            var louvre = Path()
            var y = bw.minY + bw.height * 0.2
            while y < bw.maxY { louvre.move(to: CGPoint(x: bw.minX + 1, y: y)); louvre.addLine(to: CGPoint(x: bw.maxX - 1, y: y)); y += bw.height * 0.2 }
            ctx.stroke(louvre, with: .color(deep.opacity(0.6)), lineWidth: 0.8)
        }
        for k in 0..<2 {
            let wr = CGRect(x: k == 0 ? r.minX + r.width * 0.06 : r.maxX - r.width * 0.26, y: r.maxY - r.height * 0.28, width: r.width * 0.2, height: r.height * 0.16)
            window(ctx, wr, glass: glass, lit: lit, frame: trim)
        }
    }

    /// The bank: brick front, pediment with the town clock, pilasters, a "$" shingle.
    static func bankFront(_ ctx: GraphicsContext, _ r: CGRect, brick: Color, trim: Color, deep: Color, glass: Color, lit: Bool, hour: Double) {
        ctx.fill(Path(r), with: .color(brick))
        var mortar = Path()
        let course = max(3, r.height * 0.035)
        var y = r.minY + course
        var row = 0
        while y < r.maxY {
            mortar.move(to: CGPoint(x: r.minX, y: y)); mortar.addLine(to: CGPoint(x: r.maxX, y: y))
            var x = r.minX + (row % 2 == 0 ? 0 : course)
            while x < r.maxX { mortar.move(to: CGPoint(x: x, y: y - course)); mortar.addLine(to: CGPoint(x: x, y: y)); x += course * 2 }
            y += course; row += 1
        }
        ctx.stroke(mortar, with: .color(trim.opacity(0.22)), lineWidth: 0.6)
        // Pediment with the clock.
        var ped = Path()
        ped.move(to: CGPoint(x: r.minX - 3, y: r.minY)); ped.addLine(to: CGPoint(x: r.midX, y: r.minY - r.height * 0.13)); ped.addLine(to: CGPoint(x: r.maxX + 3, y: r.minY)); ped.closeSubpath()
        ctx.fill(ped, with: .color(trim))
        ctx.fill(Path(CGRect(x: r.minX - 3, y: r.minY, width: r.width + 6, height: max(3, r.height * 0.04))), with: .color(trim.shade(0.08)))
        let cc = CGPoint(x: r.midX, y: r.minY + r.height * 0.1)
        let cr = r.width * 0.13
        ctx.fill(Path(ellipseIn: CGRect(x: cc.x - cr - 2, y: cc.y - cr - 2, width: cr * 2 + 4, height: cr * 2 + 4)), with: .color(deep))
        ctx.fill(Path(ellipseIn: CGRect(x: cc.x - cr, y: cc.y - cr, width: cr * 2, height: cr * 2)),
                 with: .color(lit ? Color(red: 1, green: 0.93, blue: 0.7) : Color(red: 0.98, green: 0.95, blue: 0.86)))
        var ticks = Path()
        for k in 0..<12 {
            let a: CGFloat = CGFloat(k) / 12 * 2 * .pi
            ticks.move(to: CGPoint(x: cc.x + sin(a) * cr * 0.78, y: cc.y - cos(a) * cr * 0.78))
            ticks.addLine(to: CGPoint(x: cc.x + sin(a) * cr * 0.92, y: cc.y - cos(a) * cr * 0.92))
        }
        ctx.stroke(ticks, with: .color(deep), lineWidth: 1)
        let ha: CGFloat = CGFloat(hour.truncatingRemainder(dividingBy: 12)) / 12 * 2 * .pi
        var hands = Path()
        hands.move(to: cc); hands.addLine(to: CGPoint(x: cc.x + sin(ha) * cr * 0.5, y: cc.y - cos(ha) * cr * 0.5))
        hands.move(to: cc); hands.addLine(to: CGPoint(x: cc.x, y: cc.y - cr * 0.78))
        ctx.stroke(hands, with: .color(deep), style: StrokeStyle(lineWidth: max(1.2, cr * 0.13), lineCap: .round))
        // Pilasters, windows, door, shingle.
        for px in [r.minX + r.width * 0.06, r.maxX - r.width * 0.14] {
            ctx.fill(Path(CGRect(x: px, y: r.minY + r.height * 0.22, width: r.width * 0.08, height: r.height * 0.78)), with: .color(trim.shade(0.05)))
        }
        for k in 0..<2 {
            let wr = CGRect(x: r.minX + r.width * (0.22 + CGFloat(k) * 0.34), y: r.minY + r.height * 0.3, width: r.width * 0.22, height: r.height * 0.24)
            window(ctx, wr, glass: glass, lit: lit, frame: trim, bars: true)
        }
        let door = CGRect(x: r.midX - r.width * 0.12, y: r.maxY - r.height * 0.3, width: r.width * 0.24, height: r.height * 0.3)
        ctx.fill(Path(roundedRect: door, cornerRadius: 1), with: .color(deep))
        ctx.stroke(Path(door), with: .color(trim), lineWidth: 1.2)
        let shingle = CGRect(x: r.midX - r.width * 0.16, y: r.minY + r.height * 0.6, width: r.width * 0.32, height: r.height * 0.1)
        sign(ctx, shingle, board: deep) { c, s in
            c.draw(Text("$").font(.system(size: s.height * 0.8, weight: .black, design: .serif))
                    .foregroundColor(Color(red: 0.95, green: 0.78, blue: 0.3)), at: CGPoint(x: s.midX, y: s.midY))
        }
    }

    static func hitchingRail(_ ctx: GraphicsContext, x0: CGFloat, x1: CGFloat, y: CGFloat, h: CGFloat, color: Color) {
        var p = Path()
        p.move(to: CGPoint(x: x0, y: y - h * 0.045)); p.addLine(to: CGPoint(x: x1, y: y - h * 0.045))
        for x in [x0 + 2, x1 - 2] { p.move(to: CGPoint(x: x, y: y - h * 0.05)); p.addLine(to: CGPoint(x: x, y: y)) }
        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: max(2, h * 0.007), lineCap: .round))
    }

    static func barrel(_ ctx: GraphicsContext, _ r: CGRect, wood: Color, hoop: Color) {
        ctx.fill(Path(roundedRect: r, cornerRadius: r.width * 0.3), with: .color(wood))
        var hoops = Path()
        for f in [0.22, 0.78] as [CGFloat] { hoops.move(to: CGPoint(x: r.minX, y: r.minY + r.height * f)); hoops.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * f)) }
        ctx.stroke(hoops, with: .color(hoop), lineWidth: 1.5)
    }

    static func trough(_ ctx: GraphicsContext, _ r: CGRect, wood: Color, water: Color) {
        ctx.fill(Path(r), with: .color(wood))
        ctx.fill(Path(CGRect(x: r.minX + 2, y: r.minY + 1.5, width: r.width - 4, height: r.height * 0.28)), with: .color(water))
        ctx.stroke(Path(r), with: .color(wood.shade(0.4)), lineWidth: 1)
    }

    static func saguaro(_ ctx: GraphicsContext, base b: CGPoint, height: CGFloat, color: Color, flip: Bool) {
        let s: CGFloat = flip ? -1 : 1
        let lw = height * 0.16
        var trunk = Path()
        trunk.move(to: b); trunk.addLine(to: CGPoint(x: b.x, y: b.y - height))
        var arms = Path()
        arms.move(to: CGPoint(x: b.x, y: b.y - height * 0.45))
        arms.addQuadCurve(to: CGPoint(x: b.x + s * height * 0.26, y: b.y - height * 0.72), control: CGPoint(x: b.x + s * height * 0.26, y: b.y - height * 0.45))
        arms.move(to: CGPoint(x: b.x, y: b.y - height * 0.6))
        arms.addQuadCurve(to: CGPoint(x: b.x - s * height * 0.2, y: b.y - height * 0.85), control: CGPoint(x: b.x - s * height * 0.2, y: b.y - height * 0.6))
        let outline = color.shade(0.45)
        ctx.stroke(trunk, with: .color(outline), style: StrokeStyle(lineWidth: lw + 3, lineCap: .round))
        ctx.stroke(arms, with: .color(outline), style: StrokeStyle(lineWidth: lw * 0.72 + 3, lineCap: .round))
        ctx.stroke(trunk, with: .color(color), style: StrokeStyle(lineWidth: lw, lineCap: .round))
        ctx.stroke(arms, with: .color(color), style: StrokeStyle(lineWidth: lw * 0.72, lineCap: .round))
        var ribs = Path()
        ribs.move(to: CGPoint(x: b.x - lw * 0.18, y: b.y)); ribs.addLine(to: CGPoint(x: b.x - lw * 0.18, y: b.y - height * 0.95))
        ribs.move(to: CGPoint(x: b.x + lw * 0.18, y: b.y)); ribs.addLine(to: CGPoint(x: b.x + lw * 0.18, y: b.y - height * 0.95))
        ctx.stroke(ribs, with: .color(color.shade(0.25)), lineWidth: 1)
    }
}

/// The static street for this level (redrawn only when the level or card changes).
private struct WesternStreet: View, Equatable {
    let level: Int
    let demo: Bool

    var body: some View {
        Canvas { ctx, s in QuickDrawArt.street(ctx, s, level: level, demo: demo) }
            .allowsHitTesting(false)
    }
}

/// One of the three GO lanterns: a banana that lights up with a warm halo.
private struct BananaLantern: View {
    let lit: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.9, blue: 0.4).opacity(0.85), Color(red: 1, green: 0.8, blue: 0.2).opacity(0)],
                                     center: .center, startRadius: 0, endRadius: size))
                .frame(width: size * 2, height: size * 2)
                .opacity(lit ? 1 : 0)
                .scaleEffect(lit ? 1 : 0.5)
            FruitIcon(kind: .banana, scale: 0.42)
                .frame(width: size, height: size)
                .saturation(lit ? 1 : 0.15)
                .brightness(lit ? 0.04 : -0.38)
                .opacity(lit ? 1 : 0.85)
        }
        .scaleEffect(lit ? 1.12 : 0.9)
        .allowsHitTesting(false)
    }
}

/// Tumbleweed rolling across the street while the count runs (animates only then).
private struct Tumbleweed: View {
    let start: Date
    let rolling: Bool
    let lay: QuickDrawLayout

    var body: some View {
        TimelineView(.animation(paused: !rolling)) { tl in
            Canvas { ctx, _ in
                let r: CGFloat = lay.h * 0.035
                let t: CGFloat = CGFloat(tl.date.timeIntervalSince(start))
                let x: CGFloat = lay.w + r * 2 - t * lay.w / 3.6
                guard x > -r * 2 else { return }
                let hop: CGFloat = abs(sin(t * 5)) * r * 0.5
                let c = CGPoint(x: x, y: lay.feetY - lay.h * 0.07 - r - hop)
                var g = ctx
                g.translateBy(x: c.x, y: c.y)
                g.rotate(by: .radians(Double(-x / r)))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: lay.feetY - lay.h * 0.07 - r * 0.25, width: r * 2, height: r * 0.5)),
                         with: .color(.black.opacity(0.15)))
                var scribble = Path()
                for k in 0..<8 {
                    let a: CGFloat = CGFloat(k) * 0.8
                    scribble.addEllipse(in: CGRect(x: -r * 0.95, y: -r * 0.45, width: r * 1.9, height: r * 0.9)
                        .applying(CGAffineTransform(rotationAngle: a)))
                }
                g.stroke(scribble, with: .color(Color(red: 0.55, green: 0.4, blue: 0.22)), lineWidth: max(1, r * 0.07))
                g.stroke(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)), with: .color(Color(red: 0.45, green: 0.32, blue: 0.17)), lineWidth: max(1, r * 0.05))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Hat for a gunslinger, drawn in the StickFigure's own frame (head at unit (0.5, 0.15), r 0.1).
private struct CowboyHat: View {
    let outlaw: Bool

    var body: some View {
        Canvas { ctx, s in
            let h = s.height, cx = s.width / 2
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: cx + x * h, y: y * h) }
            let felt = outlaw ? Color(red: 0.14, green: 0.12, blue: 0.13) : Color(red: 0.86, green: 0.74, blue: 0.54)
            let band = outlaw ? Color(red: 0.75, green: 0.75, blue: 0.8) : Color(red: 0.4, green: 0.24, blue: 0.12)
            let edge = Color(red: 0.05, green: 0.05, blue: 0.09)
            var crown = Path()
            crown.move(to: p(-0.085, 0.1))
            crown.addLine(to: p(-0.078, 0.028))
            crown.addQuadCurve(to: p(0, 0.042), control: p(-0.04, 0.0))
            crown.addQuadCurve(to: p(0.078, 0.028), control: p(0.04, 0.0))
            crown.addLine(to: p(0.085, 0.1))
            crown.closeSubpath()
            var brim = Path()
            brim.move(to: p(-0.2, 0.078))
            brim.addQuadCurve(to: p(0.2, 0.078), control: p(0, 0.14))
            brim.addQuadCurve(to: p(-0.2, 0.078), control: p(0, 0.1))
            brim.closeSubpath()
            for shape in [crown, brim] {
                ctx.stroke(shape, with: .color(edge), style: StrokeStyle(lineWidth: h * 0.022, lineJoin: .round))
            }
            ctx.fill(crown, with: .color(felt))
            ctx.fill(brim, with: .color(felt.shade(0.08)))
            ctx.fill(Path(CGRect(x: cx - 0.084 * h, y: 0.078 * h, width: 0.168 * h, height: 0.016 * h)), with: .color(band))
        }
        .allowsHitTesting(false)
    }
}

/// Bandana (the rival wears his over his face, outlaw-style), belt and holster.
private struct CowboyGear: View {
    let outlaw: Bool

    var body: some View {
        Canvas { ctx, s in
            let h = s.height, cx = s.width / 2
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: cx + x * h, y: y * h) }
            let edge = Color(red: 0.05, green: 0.05, blue: 0.09)
            var cloth = Path()
            if outlaw {
                cloth.move(to: p(-0.1, 0.155)); cloth.addLine(to: p(0.1, 0.155))
                cloth.addQuadCurve(to: p(0.02, 0.3), control: p(0.1, 0.24))
                cloth.addLine(to: p(-0.09, 0.22)); cloth.closeSubpath()
            } else {
                cloth.move(to: p(-0.06, 0.24)); cloth.addLine(to: p(0.06, 0.24)); cloth.addLine(to: p(0.015, 0.31)); cloth.closeSubpath()
            }
            let tone = outlaw ? Color(red: 0.2, green: 0.17, blue: 0.2) : Color(red: 0.82, green: 0.14, blue: 0.16)
            ctx.stroke(cloth, with: .color(edge), style: StrokeStyle(lineWidth: h * 0.018, lineJoin: .round))
            ctx.fill(cloth, with: .color(tone))
            if outlaw {
                for (x, y) in [(-0.04, 0.19), (0.04, 0.2), (0.0, 0.24), (0.05, 0.25)] as [(CGFloat, CGFloat)] {
                    ctx.fill(Path(ellipseIn: CGRect(x: cx + x * h - 0.008 * h, y: y * h - 0.008 * h, width: 0.016 * h, height: 0.016 * h)),
                             with: .color(.white.opacity(0.75)))
                }
            }
            var belt = Path()
            belt.move(to: p(-0.05, 0.585)); belt.addLine(to: p(0.05, 0.585))
            ctx.stroke(belt, with: .color(edge), style: StrokeStyle(lineWidth: h * 0.04, lineCap: .round))
            ctx.stroke(belt, with: .color(Color(red: 0.42, green: 0.25, blue: 0.12)), style: StrokeStyle(lineWidth: h * 0.026, lineCap: .round))
            ctx.fill(Path(CGRect(x: cx - 0.012 * h, y: 0.575 * h, width: 0.024 * h, height: 0.02 * h)), with: .color(Color(red: 0.95, green: 0.78, blue: 0.3)))
            let holster = Path(roundedRect: CGRect(x: cx + 0.035 * h, y: 0.59 * h, width: 0.035 * h, height: 0.085 * h), cornerRadius: 0.01 * h)
            ctx.fill(holster, with: .color(Color(red: 0.42, green: 0.25, blue: 0.12)))
            ctx.stroke(holster, with: .color(edge), lineWidth: h * 0.01)
        }
        .allowsHitTesting(false)
    }
}

/// The muzzle flash: a hot star-burst pointing along the shot, with a puff of smoke.
private struct MuzzleFlash: View {
    let size: CGFloat
    let facingRight: Bool
    @State private var go = false

    var body: some View {
        Canvas { ctx, s in
            let c = CGPoint(x: s.width / 2, y: s.height / 2)
            let dir: CGFloat = facingRight ? 1 : -1
            var burst = Path()
            for k in 0..<12 {
                let a: CGFloat = CGFloat(k) / 12 * 2 * .pi
                let long: CGFloat = abs(cos(a)) > 0.9 && cos(a) * dir > 0 ? 1.0 : 0.62
                let rr: CGFloat = (k % 2 == 0 ? long : 0.28) * s.width * 0.5
                let pt = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr * 0.8)
                if k == 0 { burst.move(to: pt) } else { burst.addLine(to: pt) }
            }
            burst.closeSubpath()
            ctx.fill(burst, with: .radialGradient(Gradient(colors: [.white, Color(red: 1, green: 0.88, blue: 0.35), Color(red: 1, green: 0.45, blue: 0.1)]),
                                                  center: c, startRadius: 0, endRadius: s.width * 0.5))
        }
        .frame(width: size, height: size)
        .scaleEffect(go ? 1.15 : 0.4)
        .opacity(go ? 0 : 1)
        .overlay {
            Circle().fill(Color(white: 0.85).opacity(0.55))
                .frame(width: size * 0.5, height: size * 0.5)
                .offset(x: (facingRight ? 1 : -1) * (go ? size * 0.55 : size * 0.1), y: go ? -size * 0.35 : 0)
                .scaleEffect(go ? 1.6 : 0.6)
                .opacity(go ? 0 : 0.8)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { go = true } }
        .allowsHitTesting(false)
    }
}
