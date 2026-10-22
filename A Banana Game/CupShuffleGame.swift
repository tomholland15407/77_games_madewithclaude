//
//  CupShuffleGame.swift
//  A Banana Game
//
//  Game — memory. The classic street game: a banana hides under one of several
//  upside-down cups. The cups reveal the banana briefly, drop, then shuffle fast.
//  Tap the cup you think still hides the banana.
//  7 levels: more cups (3 → 9), more/faster swaps, and a shorter peek each level.
//  Fail = wrong cup (the correct one is revealed) or letting the pick clock run out.
//

import SwiftUI

enum CupShuffleGame {
    static let definition = GameDefinition(
        id: "cup-shuffle",
        title: "Cup Shuffle",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "A banana hides under one cup, shown to you before the shuffle.",
                "Watch the cups shuffle, then tap the one you think still hides it.",
                "A wrong pick or a timeout sends you back to level 1.",
            ],
            bulletsVI: [
                "Quả chuối giấu dưới một cái cốc, được cho xem trước khi xáo.",
                "Theo dõi các cốc xáo trộn, rồi chạm vào cốc bạn nghĩ vẫn giấu nó.",
                "Chọn sai hoặc hết giờ sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(CupShuffleView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

/// One cup. Identity is stable so the grid animates cups *sliding* to new slots
/// when we shuffle the array, which is what sells the effect.
private struct Cup: Identifiable {
    let id = UUID()
    var hasBanana: Bool
    var lifted = false      // raised to reveal what's underneath
    var picked = false      // the cup the player tapped
}

struct CupShuffleView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    /// L1 = 3 cups … L7 = 9 cups.
    private var cupCount: Int { min(9, level + 2) }
    /// How long the banana is shown before the shuffle. Shrinks with level.
    private var peekTime: Double { max(0.6, 1.6 - Double(level) * 0.14) }
    /// Number of swaps in the shuffle — climbs fast.
    private var swapCount: Int { 3 + level * 3 }
    /// Seconds between swaps — faster each level.
    private var swapInterval: Double { max(0.12, 0.42 - Double(level) * 0.035) }
    /// Time the player has to pick once the shuffle ends.
    private var pickTime: Double { 5.0 }

    private enum Phase { case peek, shuffle, pick, done }

    @State private var cups: [Cup] = []
    @State private var phase: Phase = .peek
    @State private var pickLeft = 0.0
    @State private var demoFinger: UUID? = nil     // the cup the demo's finger is on

    var body: some View {
        VStack(spacing: isDemo ? 8 : 18) {
            Text(prompt)
                .font(.system(size: isDemo ? 16 : 19, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.4), radius: 0, x: 0, y: 2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .frame(minHeight: isDemo ? 20 : 26)

            // Pick clock — only visible (and ticking) during the pick phase.
            timeBar
                .frame(height: 6)
                .padding(.horizontal, 48)
                .opacity(phase == .pick && !isDemo ? 1 : 0)

            // Cups sit in centred rows (6 cups = 3 + 3, 9 = 5 + 4). Each cup is placed by its index,
            // so when the shuffle swaps two array slots the cups slide between spots.
            GeometryReader { geo in
                let lay = cupLayout(geo.size)
                ZStack(alignment: .topLeading) {
                    ForEach(Array(cups.enumerated()), id: \.element.id) { i, cup in
                        cupTile(cup)
                            .frame(width: lay.w, height: lay.h)
                            .position(lay.center(i))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .padding(.vertical, isDemo ? 10 : 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CupFelt().equatable())
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
    }
    // MARK: - Demo (live manual clip)

    /// Peek → shuffle (real animation) → auto-pick the banana cup for the win, then loop.
    private func runDemo() async {
        while !Task.isCancelled {
            var built = (0..<cupCount).map { _ in Cup(hasBanana: false) }
            built[0].hasBanana = true
            cups = built

            phase = .peek
            for i in cups.indices { cups[i].lifted = true }
            try? await Task.sleep(for: .seconds(peekTime))
            for i in cups.indices { cups[i].lifted = false }
            try? await Task.sleep(for: .seconds(0.4))

            phase = .shuffle
            for _ in 0..<min(swapCount, 6) {
                guard !Task.isCancelled else { return }
                let a = Int.random(in: 0..<cups.count)
                var b = Int.random(in: 0..<cups.count)
                if b == a { b = (b + 1) % cups.count }
                withAnimation(.easeInOut(duration: swapInterval * 0.9)) { cups.swapAt(a, b) }
                try? await Task.sleep(for: .seconds(swapInterval))
            }

            phase = .pick
            pickLeft = pickTime
            try? await Task.sleep(for: .seconds(0.7))
            guard !Task.isCancelled else { return }
            if let bIdx = cups.firstIndex(where: { $0.hasBanana }) {
                demoFinger = cups[bIdx].id             // the finger lands on the right cup
                try? await Task.sleep(for: .seconds(0.3))
                pick(cups[bIdx])                      // reveals the banana → win (onWin is a no-op)
            }
            try? await Task.sleep(for: .seconds(1.4))  // hold on the revealed banana
            demoFinger = nil
        }
    }

    private var prompt: String {
        switch phase {
        case .peek:    return L("Watch the banana…", "Nhìn quả chuối…")
        case .shuffle: return L("Keep your eyes on it!", "Đừng rời mắt khỏi nó!")
        case .pick:    return L("Which cup hides the banana?", "Cốc nào giấu quả chuối?")
        case .done:    return ""
        }
    }

    private struct CupLayout {
        let w: CGFloat, h: CGFloat
        let cols: Int, count: Int
        let origin: CGPoint, stepX: CGFloat, stepY: CGFloat
        func center(_ i: Int) -> CGPoint {
            let row = i / cols
            let inRow = min(cols, count - row * cols)
            let rowW = CGFloat(inRow - 1) * stepX
            return CGPoint(x: origin.x - rowW / 2 + CGFloat(i % cols) * stepX, y: origin.y + CGFloat(row) * stepY)
        }
    }

    private func cupLayout(_ s: CGSize) -> CupLayout {
        let n = max(1, cups.count)
        let cols = n <= 5 ? n : Int((Double(n) / 2).rounded(.up))
        let rows = (n + cols - 1) / cols
        let gapX = s.width * 0.04
        let w = min((s.width - gapX * CGFloat(cols + 1)) / CGFloat(cols), s.height / CGFloat(rows) * 0.62, 118)
        let h = w / 0.82
        let stepX = w + gapX, stepY = h * 1.25
        let blockH = CGFloat(rows - 1) * stepY
        return CupLayout(w: w, h: h, cols: cols, count: n,
                         origin: CGPoint(x: s.width / 2, y: s.height / 2 - blockH / 2 + h * 0.08),
                         stepX: stepX, stepY: stepY)
    }

    /// A red party cup, upside down on the felt. The banana (or nothing) lies underneath and shows
    /// when the cup lifts.
    private func cupTile(_ cup: Cup) -> some View {
        Button { pick(cup) } label: {
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                ZStack {
                    // What's under the cup: a soft shadow on the felt, and the banana if it's here.
                    Canvas { ctx, s in
                        CupArt.underCup(ctx, size: s, banana: cup.hasBanana && cup.lifted, lifted: cup.lifted)
                    }
                    Canvas { ctx, s in CupArt.cup(ctx, size: s) }
                        .offset(y: cup.lifted ? -h * 0.58 : 0)
                        .rotationEffect(.degrees(cup.lifted ? -5 : 0), anchor: .bottom)
                    if isDemo && demoFinger == cup.id {
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.system(size: w * 0.42))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.55), radius: 3)
                            .position(x: w * 0.62, y: h * 0.62)
                    }
                }
                .frame(width: w, height: h)
            }
            .animation(.spring(duration: 0.35), value: cup.lifted)
        }
        .buttonStyle(CupButtonStyle())
        .disabled(phase != .pick)
    }
    private var timeBar: some View {
        GeometryReader { geo in
            let fraction = pickTime > 0 ? pickLeft / pickTime : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.3))
                Capsule()
                    .fill(fraction < 0.3 ? .red : BananaTheme.banana)
                    .frame(width: geo.size.width * fraction)
            }
        }
    }

    // MARK: - Flow

    private func run() async {
        // Build the cups with the banana under a random one.
        var built = (0..<cupCount).map { _ in Cup(hasBanana: false) }
        built[Int.random(in: 0..<built.count)].hasBanana = true
        cups = built

        // Peek: lift every cup so the player sees where the banana is.
        phase = .peek
        for i in cups.indices { cups[i].lifted = true }
        try? await Task.sleep(for: .seconds(peekTime))
        for i in cups.indices { cups[i].lifted = false }
        try? await Task.sleep(for: .seconds(0.35))

        // Shuffle: swap random pairs; the grid animates cups sliding between slots.
        phase = .shuffle
        for _ in 0..<swapCount {
            if Task.isCancelled { return }
            let a = Int.random(in: 0..<cups.count)
            var b = Int.random(in: 0..<cups.count)
            if b == a { b = (b + 1) % cups.count }
            withAnimation(.easeInOut(duration: swapInterval * 0.9)) {
                cups.swapAt(a, b)
            }
            SoundManager.shared.tap()
            try? await Task.sleep(for: .seconds(swapInterval))
        }

        // Pick: start the clock; running out is a fail.
        phase = .pick
        pickLeft = pickTime
        let start = Date()
        while !Task.isCancelled && phase == .pick {
            try? await Task.sleep(for: .seconds(0.05))
            pickLeft = max(0, pickTime - Date().timeIntervalSince(start))
            if pickLeft <= 0 && phase == .pick {
                revealAndFail(pickedIndex: nil)
            }
        }
    }

    private func pick(_ cup: Cup) {
        guard phase == .pick, let index = cups.firstIndex(where: { $0.id == cup.id }) else { return }
        cups[index].picked = true
        cups[index].lifted = true
        if cups[index].hasBanana {
            phase = .done
            Haptics.tap()
            SoundManager.shared.tap()
            onWin()
        } else {
            revealAndFail(pickedIndex: index)
        }
    }

    /// Lifts the true banana cup so the player sees where it was, then fails.
    private func revealAndFail(pickedIndex: Int?) {
        guard phase == .pick else { return }
        phase = .done
        if let i = cups.firstIndex(where: { $0.hasBanana }) { cups[i].lifted = true }
        onFail()
    }
}


// MARK: - Shell-game art

/// Glossy red party cups turned upside down on casino felt, with a banana hiding under one.
private enum CupArt {
    static let red = Color(red: 0.86, green: 0.1, blue: 0.12)

    /// Points along the front half of an ellipse (left → right) centred at `cx`, `y`.
    private static func frontArc(_ p: inout Path, cx: CGFloat, y: CGFloat, rx: CGFloat, ry: CGFloat, reverse: Bool = false) {
        for k in 0...16 {
            let t = Double(reverse ? 16 - k : k) / 16
            let a = Double.pi * (1 - t)
            p.addLine(to: CGPoint(x: cx + rx * CGFloat(cos(a)), y: y + ry * CGFloat(sin(a))))
        }
    }

    /// An upside-down party cup: narrow base on top, wide rolled lip on the felt.
    static func cup(_ ctx: GraphicsContext, size s: CGSize) {
        let w = s.width, h = s.height, cx = w / 2
        let topY = h * 0.14, botY = h * 0.9
        let topRX = w * 0.3, botRX = w * 0.45
        let ry = h * 0.045
        var body = Path()
        body.move(to: CGPoint(x: cx - topRX, y: topY))
        body.addLine(to: CGPoint(x: cx - botRX, y: botY))
        frontArc(&body, cx: cx, y: botY, rx: botRX, ry: ry)
        body.addLine(to: CGPoint(x: cx + topRX, y: topY))
        body.closeSubpath()
        let plastic = Gradient(stops: [.init(color: red.shade(0.45), location: 0), .init(color: red.lit(0.25), location: 0.28),
                                       .init(color: red, location: 0.55), .init(color: red.shade(0.5), location: 1)])
        ctx.fill(body, with: .linearGradient(plastic, startPoint: CGPoint(x: cx - botRX, y: 0), endPoint: CGPoint(x: cx + botRX, y: 0)))
        // Ridges round the base (now on top).
        for (k, f) in [0.2, 0.27, 0.34].enumerated() {
            let y = h * CGFloat(f)
            let rx = topRX + (botRX - topRX) * (y - topY) / (botY - topY)
            var ring = Path()
            ring.move(to: CGPoint(x: cx - rx, y: y))
            frontArc(&ring, cx: cx, y: y, rx: rx, ry: ry * 0.8)
            ctx.stroke(ring, with: .color(red.shade(0.45).opacity(k == 1 ? 0.8 : 0.6)), lineWidth: max(1, h * 0.012))
            var shine = Path()
            shine.move(to: CGPoint(x: cx - rx, y: y + h * 0.012))
            frontArc(&shine, cx: cx, y: y + h * 0.012, rx: rx, ry: ry * 0.8)
            ctx.stroke(shine, with: .color(.white.opacity(0.18)), lineWidth: max(0.8, h * 0.008))
        }
        // The rolled lip where the cup meets the felt.
        var lip = Path()
        lip.move(to: CGPoint(x: cx - botRX * 1.03, y: botY - h * 0.03))
        frontArc(&lip, cx: cx, y: botY - h * 0.03, rx: botRX * 1.03, ry: ry)
        frontArc(&lip, cx: cx, y: botY + h * 0.012, rx: botRX * 1.03, ry: ry, reverse: true)
        lip.closeSubpath()
        ctx.fill(lip, with: .linearGradient(Gradient(colors: [red.shade(0.3), red.lit(0.3), red.shade(0.35)]),
                                            startPoint: CGPoint(x: cx - botRX, y: 0), endPoint: CGPoint(x: cx + botRX, y: 0)))
        // The flat base on top.
        let base = CGRect(x: cx - topRX, y: topY - ry, width: topRX * 2, height: ry * 2)
        ctx.fill(Path(ellipseIn: base), with: .linearGradient(Gradient(colors: [red.shade(0.1), red.shade(0.4)]),
                                                              startPoint: CGPoint(x: base.minX, y: base.minY), endPoint: CGPoint(x: base.maxX, y: base.maxY)))
        ctx.stroke(Path(ellipseIn: base), with: .color(red.shade(0.6)), lineWidth: 1)
        // Gloss streak.
        var gloss = Path()
        gloss.move(to: CGPoint(x: cx - topRX * 0.55, y: topY + h * 0.05))
        gloss.addLine(to: CGPoint(x: cx - topRX * 0.3, y: topY + h * 0.05))
        gloss.addLine(to: CGPoint(x: cx - botRX * 0.42, y: botY - h * 0.08))
        gloss.addLine(to: CGPoint(x: cx - botRX * 0.7, y: botY - h * 0.08))
        gloss.closeSubpath()
        ctx.fill(gloss, with: .linearGradient(Gradient(colors: [.white.opacity(0.5), .white.opacity(0.05)]),
                                              startPoint: CGPoint(x: 0, y: topY), endPoint: CGPoint(x: 0, y: botY)))
        ctx.stroke(body, with: .color(red.shade(0.65)), lineWidth: max(1, w * 0.012))
    }

    /// The felt under a cup: its shadow (or footprint when lifted), and the banana if it's hiding here.
    static func underCup(_ ctx: GraphicsContext, size s: CGSize, banana: Bool, lifted: Bool) {
        let w = s.width, h = s.height
        let foot = CGRect(x: w * 0.03, y: h * 0.86, width: w * 0.94, height: h * 0.11)
        ctx.fill(Path(ellipseIn: foot.offsetBy(dx: w * 0.02, dy: h * 0.012)), with: .color(.black.opacity(lifted ? 0.18 : 0.4)))
        if banana { bananaOnFelt(ctx, center: CGPoint(x: w * 0.5, y: h * 0.82), width: w * 0.7) }
    }

    /// A ripe banana lying on its side.
    static func bananaOnFelt(_ ctx: GraphicsContext, center c: CGPoint, width w: CGFloat) {
        let h = w * 0.4
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - w * 0.45, y: c.y + h * 0.12, width: w * 0.9, height: h * 0.4)), with: .color(.black.opacity(0.3)))
        var p = Path()
        p.move(to: CGPoint(x: c.x - w * 0.5, y: c.y - h * 0.4))
        p.addQuadCurve(to: CGPoint(x: c.x + w * 0.5, y: c.y - h * 0.5), control: CGPoint(x: c.x - w * 0.02, y: c.y + h * 1.05))
        p.addQuadCurve(to: CGPoint(x: c.x - w * 0.5, y: c.y - h * 0.4), control: CGPoint(x: c.x, y: c.y + h * 0.3))
        p.closeSubpath()
        ctx.fill(p, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.5), Color(red: 1, green: 0.84, blue: 0.2),
                                                            Color(red: 0.85, green: 0.62, blue: 0.08)]),
                                          startPoint: CGPoint(x: c.x, y: c.y - h * 0.3), endPoint: CGPoint(x: c.x, y: c.y + h * 0.6)))
        var ridge = Path()
        ridge.move(to: CGPoint(x: c.x - w * 0.42, y: c.y - h * 0.25))
        ridge.addQuadCurve(to: CGPoint(x: c.x + w * 0.42, y: c.y - h * 0.33), control: CGPoint(x: c.x, y: c.y + h * 0.62))
        ctx.stroke(ridge, with: .color(Color(red: 0.85, green: 0.6, blue: 0.1).opacity(0.6)), lineWidth: max(1, w * 0.02))
        ctx.stroke(p, with: .color(Color(red: 0.45, green: 0.3, blue: 0.05)), lineWidth: max(1, w * 0.025))
        ctx.fill(Path(roundedRect: CGRect(x: c.x - w * 0.58, y: c.y - h * 0.5, width: w * 0.12, height: h * 0.2), cornerRadius: w * 0.02),
                 with: .color(Color(red: 0.42, green: 0.28, blue: 0.1)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x + w * 0.46, y: c.y - h * 0.56, width: w * 0.07, height: h * 0.14)),
                 with: .color(Color(red: 0.3, green: 0.2, blue: 0.05)))
    }
}

/// Green casino felt under a warm spotlight (static).
private struct CupFelt: View, Equatable {
    var body: some View {
        Canvas { ctx, s in
            ctx.fill(Path(CGRect(origin: .zero, size: s)),
                     with: .radialGradient(Gradient(colors: [Color(red: 0.13, green: 0.5, blue: 0.3), Color(red: 0.06, green: 0.3, blue: 0.17),
                                                            Color(red: 0.02, green: 0.13, blue: 0.08)]),
                                           center: CGPoint(x: s.width / 2, y: s.height * 0.52), startRadius: 0, endRadius: max(s.width, s.height) * 0.72))
            // Fine felt nap.
            var nap = Path()
            var y: CGFloat = 0
            var k = 0
            while y < s.height {
                var x = CGFloat((k * 37) % 11)
                while x < s.width {
                    nap.addRect(CGRect(x: x, y: y, width: 1, height: 1))
                    x += 11
                }
                y += 5
                k += 1
            }
            ctx.fill(nap, with: .color(.white.opacity(0.05)))
        }
        .allowsHitTesting(false)
    }
}

/// Cups never dim while disabled (a see-through cup would give the banana away); they only dip
/// a little when pressed.
private struct CupButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
