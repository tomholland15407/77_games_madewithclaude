//
//  MemoryGame.swift
//  A Banana Game
//
//  Game #4 — memory. Watch a sequence of pads light up, then repeat it. One
//  wrong pad fails you back to level 1. 7 levels: the sequence grows from 3 to
//  9 and flashes faster, so 6–7 are near-impossible to hold in your head.
//

import SwiftUI

enum MemoryGame {
    static let definition = GameDefinition(
        id: "banana-memory",
        title: "Banana Memory",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Watch the four pads flash a sequence.",
                "Tap them back in the exact same order.",
                "One wrong pad sends you back to level 1.",
            ],
            bulletsVI: [
                "Xem bốn nút nhấp nháy theo một chuỗi.",
                "Chạm lại chúng theo đúng thứ tự.",
                "Một nút sai sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(MemoryView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct MemoryView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    private var length: Int { 2 + level }                        // L1=3 ... L7=9
    private var flashOn: Double { max(0.28, 0.62 - Double(level) * 0.05) }

    @State private var sequence: [Int] = []
    @State private var inputIndex = 0
    @State private var activePad: Int? = nil
    @State private var isPlayingBack = true
    @State private var done = false
    @State private var playbackTask: Task<Void, Never>?
    @State private var demoTask: Task<Void, Never>?
    @State private var pressedPad: Int? = nil     // presentation: a tapped pad lights up briefly
    @State private var demoFinger: Int? = nil

    // A dark spotlight so the black Simon body reads against the feed.
    private static let backTop = Color(red: 0.2, green: 0.21, blue: 0.27)
    private static let backBottom = Color(red: 0.04, green: 0.04, blue: 0.07)

    var body: some View {
        ZStack {
            RadialGradient(colors: [Self.backTop, Self.backBottom], center: UnitPoint(x: 0.5, y: 0.55),
                           startRadius: 10, endRadius: 520)
            VStack(spacing: isDemo ? 4 : 16) {
                Text(isDemo ? (isPlayingBack ? L("MEMORY", "GHI NHỚ") : L("REPEAT", "LẶP LẠI"))
                            : (isPlayingBack ? L("Watch…", "Xem…") : L("Your turn", "Đến lượt bạn")))
                    .font(.system(size: isDemo ? 19 : 24, weight: .black, design: .rounded))
                    .foregroundStyle(isPlayingBack ? .white.opacity(0.55) : BananaTheme.banana)
                GeometryReader { geo in
                    let d = min(geo.size.width, geo.size.height)
                    Canvas { ctx, size in
                        SimonArt.draw(ctx, size: size, lit: activePad ?? pressedPad, watching: isPlayingBack,
                                      count: min(inputIndex, sequence.count), total: sequence.count,
                                      finger: isDemo ? demoFinger : nil)
                    }
                    .frame(width: d, height: d)
                    .contentShape(Circle())
                    .onTapGesture { loc in handleTap(loc, side: d) }
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
            .padding(.vertical, isDemo ? 8 : 20)
            .padding(.horizontal, isDemo ? 8 : 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if isDemo {
                demoTask = Task { await runDemo() }
            } else {
                startRound()
            }
        }
        .onDisappear { playbackTask?.cancel(); demoTask?.cancel() }
    }

    // MARK: - Demo (live manual clip)

    /// Flash a fixed sequence, then press the same pads back in order (a perfect round) with a
    /// finger, hold, and loop. Runs the real `playback()` for the "watch" phase.
    private func runDemo() async {
        let demoSeq = [0, 3, 2]
        while !Task.isCancelled {
            done = false
            inputIndex = 0
            isPlayingBack = true
            sequence = demoSeq
            await playback()                 // "Watch…" → sets isPlayingBack = false
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .seconds(0.4))
            for pad in demoSeq {             // "Your turn" — replay the answer
                guard !Task.isCancelled else { return }
                demoFinger = pad
                try? await Task.sleep(for: .seconds(0.16))
                activePad = pad
                inputIndex += 1
                try? await Task.sleep(for: .seconds(0.28))
                activePad = nil
                try? await Task.sleep(for: .seconds(0.16))
            }
            demoFinger = nil
            try? await Task.sleep(for: .seconds(1.0))
        }
    }

    /// Taps land on whichever coloured quadrant is under the finger; it lights like the real toy.
    private func handleTap(_ loc: CGPoint, side: CGFloat) {
        guard !isDemo, let q = SimonArt.quadrant(at: loc, side: side) else { return }
        if !isPlayingBack && !done {
            pressedPad = q
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.2))
                if pressedPad == q { pressedPad = nil }
            }
        }
        tapPad(q)
    }

    // MARK: - Flow

    private func startRound() {
        done = false
        inputIndex = 0
        isPlayingBack = true
        sequence = (0..<length).map { _ in Int.random(in: 0..<4) }
        playbackTask?.cancel()
        playbackTask = Task { await playback() }
    }

    private func playback() async {
        try? await Task.sleep(for: .seconds(0.6))
        for pad in sequence {
            if done || Task.isCancelled { return }
            withAnimation { activePad = pad }
            SoundManager.shared.padTone(pad)
            try? await Task.sleep(for: .seconds(flashOn))
            withAnimation { activePad = nil }
            try? await Task.sleep(for: .seconds(0.18))
        }
        isPlayingBack = false
    }

    private func tapPad(_ index: Int) {
        guard !isPlayingBack, !done else { return }
        Haptics.tap()
        SoundManager.shared.padTone(index)

        if index == sequence[inputIndex] {
            inputIndex += 1
            if inputIndex >= sequence.count {
                done = true
                onWin()
            }
        } else {
            done = true
            SoundManager.shared.error()
            onFail()
        }
    }
}

// MARK: - Simon art

/// The 1978 Simon: a black round body, four coloured quadrant pads (green, red, yellow, blue) with
/// embossed trapezoids that light up bright, and a brushed-silver hub. Pads: 0 TL, 1 TR, 2 BL, 3 BR.
private enum SimonArt {
    static let pad: [Color] = [Color(red: 0.0, green: 0.55, blue: 0.24), Color(red: 0.74, green: 0.07, blue: 0.1),
                               Color(red: 0.86, green: 0.7, blue: 0.04), Color(red: 0.05, green: 0.32, blue: 0.76)]
    static let glow: [Color] = [Color(red: 0.4, green: 1.0, blue: 0.5), Color(red: 1.0, green: 0.4, blue: 0.34),
                                Color(red: 1.0, green: 0.96, blue: 0.42), Color(red: 0.45, green: 0.78, blue: 1.0)]

    private struct Geo {
        let c: CGPoint
        let R: CGFloat
        var rIn: CGFloat { R * 0.41 }
        var rOut: CGFloat { R * 0.9 }
        var gap: CGFloat { R * 0.04 }        // half the width of the black cross between pads
        var hub: CGFloat { R * 0.34 }
    }

    private static func geo(_ side: CGFloat) -> Geo {
        Geo(c: CGPoint(x: side / 2, y: side / 2), R: side / 2 * 0.94)
    }

    /// The quadrant under a tap (the whole coloured ring counts, generously).
    static func quadrant(at p: CGPoint, side: CGFloat) -> Int? {
        let g = geo(side)
        let dx = p.x - g.c.x, dy = p.y - g.c.y
        let d = hypot(dx, dy)
        guard d > g.rIn * 0.92, d < g.R * 1.02 else { return nil }
        return (dy < 0 ? 0 : 2) + (dx < 0 ? 0 : 1)
    }

    /// One quadrant between radii `r0…r1`, clear of the cross by `h`.
    private static func sector(_ q: Int, _ g: Geo, r0: CGFloat, r1: CGFloat, h: CGFloat) -> Path {
        let sx: CGFloat = q % 2 == 0 ? -1 : 1
        let sy: CGFloat = q < 2 ? -1 : 1
        let o = sqrt(max(0, r1 * r1 - h * h)), i = sqrt(max(0, r0 * r0 - h * h))
        var p = Path()
        func arc(_ r: CGFloat, _ a0: Double, _ a1: Double) {
            for k in 1...28 {
                let a = a0 + (a1 - a0) * Double(k) / 28
                p.addLine(to: CGPoint(x: g.c.x + r * CGFloat(cos(a)), y: g.c.y + r * CGFloat(sin(a))))
            }
        }
        p.move(to: CGPoint(x: g.c.x + sx * i, y: g.c.y + sy * h))
        p.addLine(to: CGPoint(x: g.c.x + sx * o, y: g.c.y + sy * h))
        arc(r1, atan2(Double(sy * h), Double(sx * o)), atan2(Double(sy * o), Double(sx * h)))
        p.addLine(to: CGPoint(x: g.c.x + sx * h, y: g.c.y + sy * i))
        arc(r0, atan2(Double(sy * i), Double(sx * h)), atan2(Double(sy * h), Double(sx * i)))
        p.closeSubpath()
        return p
    }

    static func draw(_ ctx: GraphicsContext, size: CGSize, lit: Int?, watching: Bool,
                     count: Int, total: Int, finger: Int?) {
        let side = min(size.width, size.height)
        guard side > 20 else { return }
        let g = geo(side)
        let R = g.R, c = g.c
        let disc = Path(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2))

        // Drop shadow + the black plastic body with a bevelled rim.
        var sh = ctx
        sh.addFilter(.blur(radius: R * 0.06))
        sh.fill(Path(ellipseIn: CGRect(x: c.x - R * 0.97, y: c.y - R * 0.9, width: R * 1.94, height: R * 1.94)),
                with: .color(.black.opacity(0.7)))
        ctx.fill(disc, with: .radialGradient(Gradient(colors: [Color(white: 0.17), Color(white: 0.08), Color(white: 0.03)]),
                                             center: CGPoint(x: c.x - R * 0.3, y: c.y - R * 0.35), startRadius: 0, endRadius: R * 1.4))
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - R * 0.975, y: c.y - R * 0.975, width: R * 1.95, height: R * 1.95)),
                   with: .linearGradient(Gradient(colors: [.white.opacity(0.28), .white.opacity(0.02), .black.opacity(0.4)]),
                                         startPoint: CGPoint(x: c.x, y: c.y - R), endPoint: CGPoint(x: c.x, y: c.y + R)),
                   lineWidth: R * 0.035)

        // A lit pad spills light over the black plastic around it.
        if let q = lit {
            var gl = ctx
            gl.addFilter(.blur(radius: R * 0.09))
            gl.fill(sector(q, g, r0: g.rIn * 0.9, r1: g.rOut * 1.06, h: 0), with: .color(glow[q].opacity(0.75)))
        }

        // Pads: rounded corners come from filling an inset sector and stroking it with a round join.
        let k = R * 0.03
        for q in 0..<4 {
            let on = lit == q
            let path = sector(q, g, r0: g.rIn + k, r1: g.rOut - k, h: g.gap + k)
            let mid = CGPoint(x: c.x + (q % 2 == 0 ? -1 : 1) * R * 0.46, y: c.y + (q < 2 ? -1 : 1) * R * 0.46)
            let shading: GraphicsContext.Shading = on
                ? .radialGradient(Gradient(colors: [.white, glow[q], glow[q].mix(with: pad[q], by: 0.35)]),
                                  center: mid, startRadius: 0, endRadius: R * 0.62)
                : .radialGradient(Gradient(colors: [pad[q].lit(0.22), pad[q], pad[q].shade(0.35)]),
                                  center: CGPoint(x: mid.x - R * 0.12, y: mid.y - R * 0.14), startRadius: 0, endRadius: R * 0.7)
            ctx.fill(path, with: shading)
            ctx.stroke(path, with: shading, style: StrokeStyle(lineWidth: k * 2, lineJoin: .round))
            // Embossed trapezoid in the middle of the pad.
            let emboss = sector(q, g, r0: g.rIn + (g.rOut - g.rIn) * 0.34, r1: g.rOut - (g.rOut - g.rIn) * 0.26,
                                h: g.gap + (g.rOut - g.rIn) * 0.3)
            ctx.stroke(emboss, with: .color((on ? Color.white : pad[q].lit(0.35)).opacity(on ? 0.55 : 0.4)),
                       style: StrokeStyle(lineWidth: max(1, R * 0.012), lineJoin: .round))
            var dark = ctx
            dark.translateBy(x: R * 0.008, y: R * 0.012)
            dark.stroke(emboss, with: .color(.black.opacity(on ? 0.08 : 0.22)),
                        style: StrokeStyle(lineWidth: max(1, R * 0.01), lineJoin: .round))
        }

        // Hub: a black collar round a brushed-silver disc.
        let hr = g.hub
        let hub = Path(ellipseIn: CGRect(x: c.x - hr, y: c.y - hr, width: hr * 2, height: hr * 2))
        ctx.fill(hub, with: .conicGradient(Gradient(colors: [Color(white: 0.9), Color(white: 0.66), Color(white: 0.95),
                                                             Color(white: 0.6), Color(white: 0.9), Color(white: 0.7),
                                                             Color(white: 0.9)]),
                                           center: c, angle: .degrees(-20)))
        for i in stride(from: 0.2, to: 1.0, by: 0.07) {
            let r = hr * CGFloat(i)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                       with: .color(.white.opacity(0.12)), lineWidth: 0.6)
        }
        ctx.stroke(hub, with: .color(Color(white: 0.3)), lineWidth: max(1, R * 0.012))
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - hr * 0.96, y: c.y - hr * 0.96, width: hr * 1.92, height: hr * 1.92)),
                   with: .linearGradient(Gradient(colors: [.white.opacity(0.7), .black.opacity(0.25)]),
                                         startPoint: CGPoint(x: c.x, y: c.y - hr), endPoint: CGPoint(x: c.x, y: c.y + hr)),
                   lineWidth: max(1, R * 0.01))

        // Two little blue slide switches and a status lamp: red while Simon plays, green for your turn.
        for sx: CGFloat in [-1, 1] {
            let slot = CGRect(x: c.x + sx * hr * 0.5 - hr * 0.16, y: c.y - hr * 0.58, width: hr * 0.32, height: hr * 0.13)
            ctx.fill(Path(roundedRect: slot, cornerRadius: hr * 0.05), with: .color(Color(white: 0.22)))
            let knob = CGRect(x: slot.minX + (sx < 0 ? 0 : slot.width * 0.45), y: slot.minY - hr * 0.03,
                              width: slot.width * 0.55, height: slot.height + hr * 0.06)
            ctx.fill(Path(roundedRect: knob, cornerRadius: hr * 0.04),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.35, green: 0.55, blue: 1), Color(red: 0.1, green: 0.28, blue: 0.8)]),
                                           startPoint: CGPoint(x: knob.midX, y: knob.minY), endPoint: CGPoint(x: knob.midX, y: knob.maxY)))
        }
        let lamp = watching ? Color(red: 1, green: 0.22, blue: 0.18) : Color(red: 0.3, green: 1, blue: 0.4)
        let lr = hr * 0.1
        let lc = CGPoint(x: c.x, y: c.y - hr * 0.52)
        ctx.fill(Path(ellipseIn: CGRect(x: lc.x - lr * 2.2, y: lc.y - lr * 2.2, width: lr * 4.4, height: lr * 4.4)),
                 with: .radialGradient(Gradient(colors: [lamp.opacity(0.55), lamp.opacity(0)]), center: lc, startRadius: 0, endRadius: lr * 2.2))
        ctx.fill(Path(ellipseIn: CGRect(x: lc.x - lr, y: lc.y - lr, width: lr * 2, height: lr * 2)),
                 with: .radialGradient(Gradient(colors: [.white, lamp, lamp.shade(0.35)]),
                                       center: CGPoint(x: lc.x - lr * 0.3, y: lc.y - lr * 0.3), startRadius: 0, endRadius: lr * 1.2))

        // Step counter in a red LED window.
        let win = CGRect(x: c.x - hr * 0.56, y: c.y - hr * 0.2, width: hr * 1.12, height: hr * 0.52)
        ctx.fill(Path(roundedRect: win, cornerRadius: hr * 0.08), with: .color(Color(red: 0.1, green: 0.02, blue: 0.02)))
        ctx.stroke(Path(roundedRect: win, cornerRadius: hr * 0.08), with: .color(.black.opacity(0.6)), lineWidth: 1)
        let led = Color(red: 1, green: 0.26, blue: 0.2)
        let digits = Text("\(count)/\(total)").font(.system(size: hr * 0.36, weight: .bold, design: .monospaced))
        var bloom = ctx
        bloom.addFilter(.blur(radius: hr * 0.05))
        bloom.draw(bloom.resolve(digits.foregroundStyle(led)), at: CGPoint(x: win.midX, y: win.midY))
        ctx.draw(ctx.resolve(digits.foregroundStyle(led.lit(0.25))), at: CGPoint(x: win.midX, y: win.midY))

        // Three round buttons along the bottom of the hub.
        for (i, col) in [Color(red: 0.98, green: 0.82, blue: 0.1), Color(red: 0.9, green: 0.12, blue: 0.1),
                         Color(red: 0.98, green: 0.82, blue: 0.1)].enumerated() {
            let bc = CGPoint(x: c.x + CGFloat(i - 1) * hr * 0.42, y: c.y + hr * 0.58)
            let br = hr * 0.1
            ctx.fill(Path(ellipseIn: CGRect(x: bc.x - br * 1.3, y: bc.y - br * 1.3, width: br * 2.6, height: br * 2.6)),
                     with: .color(Color(white: 0.2)))
            ctx.fill(Path(ellipseIn: CGRect(x: bc.x - br, y: bc.y - br, width: br * 2, height: br * 2)),
                     with: .radialGradient(Gradient(colors: [col.lit(0.5), col, col.shade(0.35)]),
                                           center: CGPoint(x: bc.x - br * 0.3, y: bc.y - br * 0.35), startRadius: 0, endRadius: br * 1.3))
        }

        // Soft plastic sheen over the whole toy.
        ctx.fill(disc, with: .radialGradient(Gradient(colors: [.white.opacity(0.1), .clear]),
                                             center: CGPoint(x: c.x - R * 0.45, y: c.y - R * 0.5), startRadius: 0, endRadius: R * 0.9))

        // Demo finger pressing a pad.
        if let q = finger {
            let pc = CGPoint(x: c.x + (q % 2 == 0 ? -1 : 1) * R * 0.46, y: c.y + (q < 2 ? -1 : 1) * R * 0.46)
            var hand = ctx.resolve(Image(systemName: "hand.point.up.left.fill"))
            hand.shading = .color(.white)
            var h = ctx
            h.addFilter(.shadow(color: .black.opacity(0.6), radius: 3))
            let hw = R * 0.3
            h.draw(hand, in: CGRect(x: pc.x - hw * 0.05, y: pc.y + hw * 0.02, width: hw, height: hw))
        }
    }
}
