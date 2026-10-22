//
//  ColorTrapGame.swift
//  A Banana Game
//
//  Game #6 — brain (Stroop test). A color WORD is painted in a different INK
//  color. The prompt tells you to match either the ink or the word's meaning —
//  and from level 5 it flips between the two so you can't autopilot. Tap the
//  wrong swatch, or let the timer expire, and you fail back to level 1.
//  7 levels: more swatches, a shrinking clock, and nastier word/ink flips.
//

import SwiftUI

enum ColorTrapGame {
    static let definition = GameDefinition(
        id: "color-trap",
        title: "Color Trap",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "A color word is painted in a different ink.",
                "The prompt says whether to match the ink or the word — tap that swatch.",
                "A wrong tap or a timeout fails you back to level 1.",
            ],
            bulletsVI: [
                "Một từ chỉ màu được viết bằng mực khác màu.",
                "Yêu cầu cho biết chọn theo màu mực hay theo nghĩa của từ — chạm ô màu đó.",
                "Chạm sai hoặc hết giờ sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(ColorTrapView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

/// One color the game knows about: its name (shown as the WORD) and its ink.
private struct ColorOption: Identifiable {
    let name: String
    let color: Color
    var id: String { name }
}

private enum TrapMode {
    case ink   // tap the swatch matching the INK the word is painted in
    case word  // tap the swatch matching what the WORD says
}

struct ColorTrapView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    /// The full palette. Higher levels draw more of these into play.
    private static let palette: [ColorOption] = [
        ColorOption(name: "RED",    color: Color(red: 0.95, green: 0.26, blue: 0.21)),
        ColorOption(name: "GREEN",  color: Color(red: 0.30, green: 0.80, blue: 0.36)),
        ColorOption(name: "BLUE",   color: Color(red: 0.26, green: 0.53, blue: 0.96)),
        ColorOption(name: "YELLOW", color: BananaTheme.banana),
        ColorOption(name: "ORANGE", color: Color(red: 1.0,  green: 0.55, blue: 0.10)),
        ColorOption(name: "PURPLE", color: Color(red: 0.67, green: 0.38, blue: 0.95)),
    ]

    /// The colour word as shown on screen (the `name` stays the English key used for matching).
    private static func displayName(_ name: String) -> String {
        switch name {
        case "RED": return L("RED", "ĐỎ")
        case "GREEN": return L("GREEN", "XANH LÁ")
        case "BLUE": return L("BLUE", "XANH DƯƠNG")
        case "YELLOW": return L("YELLOW", "VÀNG")
        case "ORANGE": return L("ORANGE", "CAM")
        case "PURPLE": return L("PURPLE", "TÍM")
        default: return name
        }
    }

    /// Correct answers needed to win. L1=3 … L7=9.
    private var target: Int { 2 + level }
    /// How many swatches are on screen. L1=3 … L7=6.
    private var swatchCount: Int { min(Self.palette.count, 2 + level) }
    /// Seconds per round — generous early, brutal late.
    private var timePerRound: Double { max(1.1, 4.2 - Double(level) * 0.42) }
    /// From level 5, rounds randomly ask for the WORD instead of the ink.
    private var canFlip: Bool { level >= 5 }

    @State private var swatches: [ColorOption] = []
    @State private var wordText = ""
    @State private var inkColor = Color.white
    @State private var mode: TrapMode = .ink
    @State private var correctName = ""
    @State private var score = 0
    @State private var timeLeft = 0.0
    @State private var done = false
    @State private var timerTask: Task<Void, Never>?
    @State private var demoTask: Task<Void, Never>?
    @State private var demoFlash: String? = nil   // name of the auto-picked swatch

    var body: some View {
        VStack(spacing: 0) {
            // The studio wall: score, clock and the easel with the painted word.
            VStack(spacing: isDemo ? 4 : 12) {
                if !isDemo {
                    Text("\(score) / \(target)")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 2)
                    timeBar
                        .frame(height: 8)
                        .padding(.horizontal, 44)
                }
                easel
            }
            .padding(.top, isDemo ? 8 : 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(StudioWall().equatable())
            // The wooden floor with the open paint cans.
            swatchGrid
                .padding(.horizontal, isDemo ? 26 : 28)
                .padding(.top, isDemo ? 12 : 22)
                .padding(.bottom, isDemo ? 12 : 26)
                .frame(maxWidth: .infinity)
                .background(StudioFloor().equatable())
        }
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if isDemo { demoTask = Task { await runDemo() } } else { newRound() }
        }
        .onDisappear { timerTask?.cancel(); demoTask?.cancel() }
    }

    /// An easel holding a white canvas: the colour word is painted on it in dripping ink, and the
    /// INK / WORD instruction is scrawled on a strip of masking tape across the top.
    private var easel: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let cw = max(40, min(w - (isDemo ? 44 : 52), (h - 34) * 1.75))
            let ch = cw / 1.75
            let rect = CGRect(x: (w - cw) / 2, y: max(16, (h - ch) / 2 - 4), width: cw, height: ch)
            ZStack {
                Canvas { ctx, size in ColorTrapArt.easel(ctx, canvas: rect, size: size) }
                Canvas { ctx, size in
                    ColorTrapArt.paintedWord(ctx, Self.displayName(wordText), ink: inkColor, in: CGRect(origin: .zero, size: size))
                }
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                tape
                    .frame(maxWidth: rect.width * 0.92)
                    .position(x: rect.midX, y: rect.minY + 2)
            }
        }
    }

    private var tape: some View {
        HStack(spacing: 7) {
            Image(systemName: mode == .ink ? "drop.fill" : "textformat")
                .font(.system(size: isDemo ? 13 : 16, weight: .black))
            Text(mode == .ink ? L("MATCH THE INK", "CHỌN THEO MÀU MỰC") : L("MATCH THE WORD", "CHỌN THEO NGHĨA TỪ"))
                .font(.system(size: isDemo ? 13 : 17, weight: .heavy, design: .rounded))
                .tracking(1)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(Color(red: 0.2, green: 0.18, blue: 0.16))
        .padding(.horizontal, isDemo ? 14 : 18)
        .padding(.vertical, isDemo ? 5 : 7)
        .background(TapeStrip().fill(Color(red: 0.94, green: 0.88, blue: 0.7).opacity(0.97)))
        .shadow(color: .black.opacity(0.25), radius: 1.5, x: 0, y: 1.5)
        .rotationEffect(.degrees(-2.5))
    }

    private var swatchGrid: some View {
        let d: CGFloat = isDemo ? 58 : 84
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16),
                                        count: min(3, swatchCount)),
                         spacing: isDemo ? 10 : 18) {
            ForEach(swatches) { option in
                let picked = demoFlash == option.name
                Button { choose(option) } label: {
                    Canvas { ctx, size in ColorTrapArt.paintCan(ctx, size: size, paint: option.color) }
                        .frame(width: d, height: d)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white, lineWidth: picked ? 4 : 0).padding(-4))
                        .scaleEffect(picked ? 1.08 : 1)
                        .overlay {
                            if picked && isDemo {
                                Image(systemName: "hand.point.up.left.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.55), radius: 3)
                                    .offset(x: 16, y: 18)
                            }
                        }
                }
                .buttonStyle(CanPressStyle())
                .disabled(done)
            }
        }
    }

    // MARK: - Demo (live manual clip)

    /// Auto-pick the correct swatch each round up to the win, ringing the chosen one.
    /// Keeps the simple INK mode (no word/ink flip) so the demo reads clearly.
    private func runDemo() async {
        while !Task.isCancelled {
            done = false
            score = 0
            for _ in 0..<target {
                guard !Task.isCancelled else { return }
                let subset = Array(Self.palette.shuffled().prefix(swatchCount))
                swatches = subset.shuffled()
                let wordOption = subset.randomElement()!
                let inkOption = subset.filter { $0.name != wordOption.name }.randomElement() ?? wordOption
                mode = .ink
                wordText = wordOption.name
                inkColor = inkOption.color
                correctName = inkOption.name
                timeLeft = timePerRound
                demoFlash = nil
                try? await Task.sleep(for: .seconds(0.9))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.15)) { demoFlash = correctName }
                try? await Task.sleep(for: .seconds(0.5))
                score += 1
                try? await Task.sleep(for: .seconds(0.2))
            }
            try? await Task.sleep(for: .seconds(0.9))   // hold on the cleared score
        }
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let fraction = timePerRound > 0 ? timeLeft / timePerRound : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule()
                    .fill(fraction < 0.3 ? .red : BananaTheme.banana)
                    .frame(width: geo.size.width * fraction)
            }
        }
    }

    // MARK: - Flow

    private func newRound() {
        guard !done else { return }

        // Pick this round's swatches (a shuffled subset of the palette).
        let subset = Array(Self.palette.shuffled().prefix(swatchCount))
        swatches = subset.shuffled()

        // The word we show and the ink it's painted in are two *different*
        // swatches — that mismatch is the whole trap.
        let wordOption = subset.randomElement()!
        let inkOption = subset.filter { $0.name != wordOption.name }.randomElement() ?? wordOption

        mode = (canFlip && Bool.random()) ? .word : .ink
        wordText = wordOption.name
        inkColor = inkOption.color
        correctName = (mode == .ink) ? inkOption.name : wordOption.name

        startTimer()
    }

    private func startTimer() {
        timerTask?.cancel()
        timeLeft = timePerRound
        let start = Date()
        timerTask = Task {
            while !Task.isCancelled && !done {
                try? await Task.sleep(for: .seconds(0.05))
                timeLeft = max(0, timePerRound - Date().timeIntervalSince(start))
                if timeLeft <= 0 && !done {
                    done = true
                    SoundManager.shared.error()
                    onFail()
                }
            }
        }
    }

    private func choose(_ option: ColorOption) {
        guard !done else { return }
        if option.name == correctName {
            Haptics.tap()
            SoundManager.shared.tap()
            score += 1
            if score >= target {
                done = true
                timerTask?.cancel()
                onWin()
            } else {
                newRound()
            }
        } else {
            done = true
            timerTask?.cancel()
            Haptics.warning()
            SoundManager.shared.error()
            onFail()
        }
    }
}

// MARK: - Studio art

/// The paint studio: an easel with a primed canvas, the colour word painted in dripping ink (with a
/// dark outline so yellow stays legible on white), and open paint cans seen from above.
private enum ColorTrapArt {
    static let wood = Color(red: 0.62, green: 0.41, blue: 0.22)
    static let woodDark = Color(red: 0.4, green: 0.25, blue: 0.13)

    private static func disc(_ p: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }

    /// Easel legs, the ledge and the canvas board (everything but the paint).
    static func easel(_ ctx: GraphicsContext, canvas r: CGRect, size: CGSize) {
        let legW = max(6, r.width * 0.045)
        let apex = CGPoint(x: r.midX, y: r.minY - r.height * 0.16)
        func leg(_ bottomX: CGFloat, _ width: CGFloat, _ color: Color) {
            var p = Path()
            p.move(to: CGPoint(x: apex.x - width * 0.35, y: apex.y))
            p.addLine(to: CGPoint(x: apex.x + width * 0.35, y: apex.y))
            p.addLine(to: CGPoint(x: bottomX + width / 2, y: size.height + 4))
            p.addLine(to: CGPoint(x: bottomX - width / 2, y: size.height + 4))
            p.closeSubpath()
            ctx.fill(p, with: .linearGradient(Gradient(colors: [color.lit(0.12), color, color.shade(0.2)]),
                                              startPoint: CGPoint(x: bottomX - width, y: 0), endPoint: CGPoint(x: bottomX + width, y: 0)))
        }
        leg(r.midX, legW * 0.85, woodDark)
        leg(r.minX + r.width * 0.1, legW, wood)
        leg(r.maxX - r.width * 0.1, legW, wood)

        // Canvas: soft drop shadow, primed white with a faint weave.
        var sh = ctx
        sh.addFilter(.blur(radius: 7))
        sh.fill(Path(r.offsetBy(dx: 4, dy: 7)), with: .color(.black.opacity(0.5)))
        ctx.fill(Path(r), with: .linearGradient(Gradient(colors: [Color(white: 0.995), Color(red: 0.95, green: 0.94, blue: 0.91)]),
                                                startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
        var weave = Path()
        var y = r.minY + 3
        while y < r.maxY { weave.move(to: CGPoint(x: r.minX, y: y)); weave.addLine(to: CGPoint(x: r.maxX, y: y)); y += 3 }
        var x = r.minX + 3
        while x < r.maxX { weave.move(to: CGPoint(x: x, y: r.minY)); weave.addLine(to: CGPoint(x: x, y: r.maxY)); x += 3 }
        ctx.stroke(weave, with: .color(.black.opacity(0.025)), lineWidth: 0.6)
        ctx.stroke(Path(r), with: .color(Color(white: 0.78)), lineWidth: 1)

        // The ledge the canvas rests on.
        let ledge = CGRect(x: r.minX - r.width * 0.07, y: r.maxY - 3, width: r.width * 1.14, height: max(9, r.height * 0.075))
        ctx.fill(Path(roundedRect: ledge.offsetBy(dx: 0, dy: 3), cornerRadius: 3), with: .color(.black.opacity(0.3)))
        ctx.fill(Path(roundedRect: ledge, cornerRadius: 3),
                 with: .linearGradient(Gradient(colors: [wood.lit(0.2), wood, woodDark]),
                                       startPoint: CGPoint(x: ledge.midX, y: ledge.minY), endPoint: CGPoint(x: ledge.midX, y: ledge.maxY)))
    }

    /// A stable pseudo-random stream per word, so the drips don't move between frames.
    private struct Stream {
        var h: UInt64
        init(_ s: String) {
            h = 1469598103934665603
            for u in s.unicodeScalars { h = (h ^ UInt64(u.value)) &* 1099511628211 }
        }
        mutating func next() -> CGFloat {
            h = h &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((h >> 33) % 10_000) / 10_000
        }
    }

    /// The word, fitted to `r`, painted in `ink` with drips running off the letters.
    static func paintedWord(_ ctx: GraphicsContext, _ word: String, ink: Color, in r: CGRect) {
        guard !word.isEmpty, r.width > 20 else { return }
        let base: CGFloat = 100
        let probe = ctx.resolve(Text(word).font(.system(size: base, weight: .black, design: .rounded)))
        let m = probe.measure(in: CGSize(width: 10_000, height: 10_000))
        let fs = min(base * r.width * 0.84 / max(m.width, 1), r.height * 0.46)
        let font = Font.system(size: fs, weight: .black, design: .rounded)
        let center = CGPoint(x: r.midX, y: r.midY - fs * 0.12)
        let textW = m.width * fs / base
        let outline = Color(red: 0.12, green: 0.11, blue: 0.13)
        let o = max(1.2, fs * 0.045)

        // Drips hang from about half the letters — only from a solid left stem (B, D, E, N…) or a
        // round bottom (O, G, C…), measured per letter, so a drip can never turn V into Y.
        let letters = Array(word)
        let baseFont = Font.system(size: base, weight: .black, design: .rounded)
        var edges: [CGFloat] = [0]
        for i in 1...letters.count {
            edges.append(ctx.resolve(Text(String(letters[0..<i])).font(baseFont)).measure(in: CGSize(width: 10_000, height: 10_000)).width)
        }
        let stems: Set<Character> = ["B", "D", "Đ", "E", "H", "K", "L", "M", "N", "P", "R", "U", "Ư", "F"]
        let rounds: Set<Character> = ["O", "Ô", "Ơ", "Ỏ", "G", "C", "Q", "S", "Ó", "Ò"]
        let left = center.x - textW / 2
        var rnd = Stream(word)
        var drips: [Path] = []
        for (i, ch) in letters.enumerated() {
            let roll = rnd.next()
            guard stems.contains(ch) || rounds.contains(ch), roll < 0.6 else { continue }
            let a = left + edges[i] * fs / base, b = left + edges[i + 1] * fs / base
            let x = stems.contains(ch) ? a + (b - a) * 0.27 : (a + b) / 2
            let w = fs * (0.09 + 0.05 * rnd.next())
            let y0 = center.y + fs * 0.27
            let len = min(fs * (0.2 + 0.46 * rnd.next()), r.maxY - y0 - w * 1.4)
            guard len > w else { continue }
            var p = Path(roundedRect: CGRect(x: x - w / 2, y: y0, width: w, height: len), cornerRadius: w / 2)
            p.addPath(disc(CGPoint(x: x, y: y0 + len), w * 0.62))
            drips.append(p)
        }

        // Dark outline behind letters and drips.
        let dark = ctx.resolve(Text(word).font(font).foregroundStyle(outline))
        for k in 0..<8 {
            let a = Double(k) * .pi / 4
            ctx.draw(dark, at: CGPoint(x: center.x + CGFloat(cos(a)) * o, y: center.y + CGFloat(sin(a)) * o))
        }
        // Drips only show below the letters (never inside a counter like E's).
        var below = ctx
        below.clip(to: Path(CGRect(x: r.minX, y: center.y + fs * 0.3, width: r.width, height: r.height)))
        for d in drips { below.stroke(d, with: .color(outline), lineWidth: o * 2) }
        // Wet paint: a top-lit gradient, then a soft sheen across the upper half of the letters.
        let paint = GraphicsContext.Shading.linearGradient(Gradient(colors: [ink.lit(0.2), ink, ink.shade(0.14)]),
                                                           startPoint: CGPoint(x: center.x, y: center.y - fs * 0.45),
                                                           endPoint: CGPoint(x: center.x, y: center.y + fs * 0.6))
        for d in drips { below.fill(d, with: paint) }
        var fill = ctx.resolve(Text(word).font(font))
        fill.shading = paint
        ctx.draw(fill, at: center)
        var sheen = ctx
        sheen.clip(to: Path(CGRect(x: r.minX, y: center.y - fs * 0.4, width: r.width, height: fs * 0.2)))
        var gloss = ctx.resolve(Text(word).font(font))
        gloss.shading = .color(.white.opacity(0.28))
        sheen.draw(gloss, at: center)
    }

    /// A paint can seen from slightly above: a silver tin with a label in the paint colour, an open
    /// top brimming with glossy paint, and a drip running down the front.
    static func paintCan(_ ctx: GraphicsContext, size: CGSize, paint: Color) {
        let d = min(size.width, size.height)
        let cx = size.width / 2, oy = (size.height - d) / 2
        let rx = d * 0.39, ry = d * 0.13
        let topY = oy + d * 0.2, botY = oy + d * 0.84
        func ell(_ cy: CGFloat, _ ex: CGFloat, _ ey: CGFloat) -> CGRect { CGRect(x: cx - ex, y: cy - ey, width: ex * 2, height: ey * 2) }
        /// The front half of an ellipse at `y`, left to right (or right to left).
        func front(_ p: inout Path, _ y: CGFloat, reverse: Bool = false) {
            for k in 0...18 {
                let a = Double.pi * Double(reverse ? 18 - k : k) / 18
                p.addLine(to: CGPoint(x: cx - rx * CGFloat(cos(a)), y: y + ry * CGFloat(sin(a))))
            }
        }
        let metal = Gradient(stops: [.init(color: Color(white: 0.42), location: 0), .init(color: Color(white: 0.93), location: 0.28),
                                     .init(color: Color(white: 0.74), location: 0.62), .init(color: Color(white: 0.4), location: 1)])
        let across = (CGPoint(x: cx - rx, y: 0), CGPoint(x: cx + rx, y: 0))

        var sh = ctx
        sh.addFilter(.blur(radius: d * 0.035))
        sh.fill(Path(ellipseIn: ell(botY + ry * 0.45, rx * 1.08, ry * 0.95)), with: .color(.black.opacity(0.55)))

        // Tin body.
        var body = Path()
        body.move(to: CGPoint(x: cx - rx, y: topY))
        front(&body, botY)
        body.addLine(to: CGPoint(x: cx + rx, y: topY))
        body.closeSubpath()
        ctx.fill(body, with: .linearGradient(metal, startPoint: across.0, endPoint: across.1))
        // Label in the paint colour, wrapping round the tin, with a white pinstripe.
        let l0 = topY + ry * 1.35, l1 = botY - d * 0.03
        var label = Path()
        label.move(to: CGPoint(x: cx - rx, y: l0))
        front(&label, l0)
        front(&label, l1, reverse: true)
        label.closeSubpath()
        ctx.fill(label, with: .linearGradient(Gradient(stops: [.init(color: paint.shade(0.4), location: 0),
                                                               .init(color: paint.lit(0.18), location: 0.3),
                                                               .init(color: paint, location: 0.62),
                                                               .init(color: paint.shade(0.4), location: 1)]),
                                              startPoint: across.0, endPoint: across.1))
        var stripe = Path()
        stripe.move(to: CGPoint(x: cx - rx, y: l0 + (l1 - l0) * 0.2))
        front(&stripe, l0 + (l1 - l0) * 0.2)
        ctx.stroke(stripe, with: .color(.white.opacity(0.85)), lineWidth: max(1, d * 0.02))
        ctx.stroke(body, with: .color(Color(white: 0.3)), lineWidth: 1)

        // Open top: the rim, then a pool of glossy paint.
        ctx.fill(Path(ellipseIn: ell(topY, rx, ry)), with: .linearGradient(metal, startPoint: across.0, endPoint: across.1))
        ctx.stroke(Path(ellipseIn: ell(topY, rx, ry)), with: .color(Color(white: 0.32)), lineWidth: 1)
        let pool = ell(topY + ry * 0.05, rx * 0.86, ry * 0.76)
        ctx.fill(Path(ellipseIn: pool), with: .linearGradient(Gradient(colors: [paint.lit(0.28), paint, paint.shade(0.18)]),
                                                              startPoint: CGPoint(x: pool.minX, y: pool.minY),
                                                              endPoint: CGPoint(x: pool.maxX, y: pool.maxY)))
        ctx.fill(Path(ellipseIn: CGRect(x: pool.minX + pool.width * 0.16, y: pool.minY + pool.height * 0.18,
                                        width: pool.width * 0.3, height: pool.height * 0.3)), with: .color(.white.opacity(0.6)))

        // Drips over the front rim.
        for (fx, len) in [(0.3, 0.3), (-0.42, 0.16)] {
            let x = cx + rx * CGFloat(fx)
            let yTop = topY + ry * CGFloat(sqrt(max(0, 1 - fx * fx))) - d * 0.01
            let w = d * 0.075
            var drip = Path(roundedRect: CGRect(x: x - w / 2, y: yTop, width: w, height: d * CGFloat(len)), cornerRadius: w / 2)
            drip.addPath(Path(ellipseIn: CGRect(x: x - w * 0.62, y: yTop + d * CGFloat(len) - w * 0.62, width: w * 1.24, height: w * 1.24)))
            ctx.stroke(drip, with: .color(paint.shade(0.5)), lineWidth: 1.2)
            ctx.fill(drip, with: .linearGradient(Gradient(colors: [paint.lit(0.22), paint.shade(0.05)]),
                                                 startPoint: CGPoint(x: x - w, y: 0), endPoint: CGPoint(x: x + w, y: 0)))
        }
    }
}

/// A strip of masking tape with torn, zig-zag ends.
private struct TapeStrip: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let z: CGFloat = 4
        let n = max(2, Int(r.height / 5))
        p.move(to: CGPoint(x: r.minX + z, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - z, y: r.minY))
        for i in 0..<n {
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * (CGFloat(i) + 0.5) / CGFloat(n)))
            p.addLine(to: CGPoint(x: r.maxX - z, y: r.minY + r.height * CGFloat(i + 1) / CGFloat(n)))
        }
        p.addLine(to: CGPoint(x: r.minX + z, y: r.maxY))
        for i in 0..<n {
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY - r.height * (CGFloat(i) + 0.5) / CGFloat(n)))
            p.addLine(to: CGPoint(x: r.minX + z, y: r.maxY - r.height * CGFloat(i + 1) / CGFloat(n)))
        }
        p.closeSubpath()
        return p
    }
}

/// Paint cans sink a little when pressed.
private struct CanPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// Teal studio wallpaper with a spotlight on the easel (static).
private struct StudioWall: View, Equatable {
    var body: some View {
        Canvas { ctx, s in
            ctx.fill(Path(CGRect(origin: .zero, size: s)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.2, green: 0.34, blue: 0.38), Color(red: 0.11, green: 0.2, blue: 0.24)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height)))
            var x: CGFloat = 0
            var k = 0
            while x < s.width {
                if k % 2 == 0 { ctx.fill(Path(CGRect(x: x, y: 0, width: 16, height: s.height)), with: .color(.white.opacity(0.035))) }
                x += 16
                k += 1
            }
            ctx.fill(Path(CGRect(origin: .zero, size: s)),
                     with: .radialGradient(Gradient(colors: [.white.opacity(0.18), .clear]),
                                           center: CGPoint(x: s.width / 2, y: s.height * 0.55), startRadius: 0, endRadius: s.width * 0.75))
        }
        .allowsHitTesting(false)
    }
}

/// Worn wooden floorboards under the paint cans (static).
private struct StudioFloor: View, Equatable {
    var body: some View {
        Canvas { ctx, s in
            ctx.fill(Path(CGRect(origin: .zero, size: s)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.5, green: 0.33, blue: 0.19), Color(red: 0.37, green: 0.24, blue: 0.13)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height)))
            ctx.fill(Path(CGRect(x: 0, y: 0, width: s.width, height: 8)), with: .color(Color(red: 0.23, green: 0.14, blue: 0.08)))
            ctx.fill(Path(CGRect(x: 0, y: 8, width: s.width, height: 3)), with: .color(.black.opacity(0.28)))
            let plank: CGFloat = 26
            var y: CGFloat = 11
            var row = 0
            while y < s.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: s.width, height: 1.2)), with: .color(.black.opacity(0.3)))
                var x = CGFloat((row * 61) % 113) - 20
                while x < s.width {
                    ctx.fill(Path(CGRect(x: x, y: y, width: 1.2, height: plank)), with: .color(.black.opacity(0.25)))
                    x += 124
                }
                for g in 0..<3 {
                    let gy = y + plank * (0.3 + 0.2 * CGFloat(g))
                    var grain = Path()
                    grain.move(to: CGPoint(x: 0, y: gy))
                    grain.addCurve(to: CGPoint(x: s.width, y: gy + 2), control1: CGPoint(x: s.width * 0.3, y: gy - 2),
                                   control2: CGPoint(x: s.width * 0.7, y: gy + 3))
                    ctx.stroke(grain, with: .color(.black.opacity(0.07)), lineWidth: 1)
                }
                y += plank
                row += 1
            }
            // A few old, pale paint splats.
            for (fx, fy, fr) in [(0.12, 0.7, 7.0), (0.86, 0.35, 5.0), (0.55, 0.9, 6.0), (0.3, 0.2, 4.0)] {
                ctx.fill(Path(ellipseIn: CGRect(x: s.width * fx - fr, y: s.height * fy - fr * 0.6, width: fr * 2, height: fr * 1.2)),
                         with: .color(.white.opacity(0.12)))
            }
        }
        .allowsHitTesting(false)
    }
}
