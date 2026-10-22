//
//  SpotDifferenceGame.swift
//  A Banana Game
//
//  Spot the Difference. Two stacked procedural scenes (top / bottom) built from
//  simple nature icons. They're identical except one detail differs — a changed
//  color, size, symbol, position, or a missing item. Tap the differing spot in
//  either scene before the clock runs out. A wrong tap or the timeout fails you.
//  Tap only → no feed lock.
//
//  Drawn like the spot-the-difference apps: two white-bordered pictures (sky, hills and meadow)
//  with every item as an ink-outlined cartoon sticker, a red circle on the difference when you
//  find it (a red ✕ where you miss), and a pencil that wears down as the clock runs.
//

import SwiftUI

enum SpotDifferenceGame {
    static let definition = GameDefinition(
        id: "spot-difference", title: "Spot the Difference", emoji: "🍌",
        genre: .brain, levelCount: 7,
        manual: GameManual(
            bullets: [
                "Two stacked scenes are identical except for one detail.",
                "The difference may be a changed color, size, symbol, position, or a missing item.",
                "Tap the differing spot in either scene before the clock runs out.",
                "A wrong tap or a timeout sends you back to level 1.",
            ],
            bulletsVI: [
                "Hai cảnh xếp chồng giống hệt nhau, chỉ khác đúng một chi tiết.",
                "Điểm khác có thể là màu, kích thước, biểu tượng, vị trí, hoặc một vật bị thiếu.",
                "Chạm vào điểm khác biệt ở một trong hai cảnh trước khi hết giờ.",
                "Chạm sai hoặc hết giờ sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(SpotDifferenceView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

private struct SceneItem: Identifiable {
    let id = UUID()
    var symbol: String
    var pos: CGPoint          // fractional within a scene rect (0...1)
    var size: CGFloat         // fractional of the scene width
    var color: Color
    var hidden: Bool = false
}

struct SpotDifferenceView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    private let symbols = ["tree.fill", "cloud.fill", "sun.max.fill", "leaf.fill",
                           "bird.fill", "mountain.2.fill", "ant.fill", "tortoise.fill",
                           "fish.fill", "pawprint.fill"]
    private let palette: [Color] = [.green, .mint, .teal, .yellow, .orange, .white, .cyan]

    // MARK: Difficulty
    private var itemCount: Int { 6 + level * 2 }                   // L1 8 → L7 20 items
    private var timeLimit: Double { max(6.0, 15.0 - Double(level) * 1.3) }
    /// Tap tolerance around the difference, as a fraction of the scene width.
    private var tolFrac: CGFloat { max(0.06, 0.15 - CGFloat(level) * 0.012) }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var base: [SceneItem] = []       // scene A (top)
    @State private var changed: SceneItem = SceneItem(symbol: "leaf.fill", pos: .zero, size: 0.1, color: .green)
    @State private var diffIndex = 0                // which item differs
    @State private var timeLeft = 0.0
    // Demo-mode overlay: a crosshair that lands on the difference, then rings flash.
    @State private var demoCrosshair = false
    @State private var demoRing = false
    @State private var circled = false            // presentation: you found it — ring it in both pictures
    @State private var missAt: CGPoint? = nil     // presentation: a red ✕ where a wrong tap landed

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // Two scene rects stacked with a gap; kept clear of the camera strip.
            let top = CGRect(x: size.width * 0.06, y: size.height * 0.14,
                             width: size.width * 0.88, height: size.height * 0.36)
            let bottom = CGRect(x: size.width * 0.06, y: size.height * 0.54,
                                width: size.width * 0.88, height: size.height * 0.36)

            ZStack(alignment: .topLeading) {
                PuzzlePage().equatable()

                HStack(spacing: 12) {
                    PencilTimer(frac: timeLimit > 0 ? timeLeft / timeLimit : 0)
                        .frame(height: 16)
                    FoundBadge(found: circled || (isDemo && demoRing))
                        .frame(width: 24, height: 24)
                }
                .padding(.horizontal, 30)
                .frame(width: size.width)
                .position(x: size.width / 2, y: size.height * 0.06)

                SpotPicture(items: base.map { StickerItem($0) }, size: top.size).equatable()
                    .frame(width: top.width, height: top.height)
                    .position(x: top.midX, y: top.midY)
                SpotPicture(items: sceneB.map { StickerItem($0) }, size: bottom.size).equatable()
                    .frame(width: bottom.width, height: bottom.height)
                    .position(x: bottom.midX, y: bottom.midY)

                if circled, diffIndex < base.count {
                    markerRings(top: top, bottom: bottom)
                }
                if let m = missAt {
                    MarkerCross()
                        .frame(width: top.width * 0.12, height: top.width * 0.12)
                        .position(m)
                }

                if isDemo {
                    demoOverlay(top: top, bottom: bottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { loc in
                guard !isDemo else { return }
                handleTap(loc, top: top, bottom: bottom)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
    }

    /// Red marker circles round the difference in both pictures.
    private func markerRings(top: CGRect, bottom: CGRect) -> some View {
        let a = CGPoint(x: top.minX + base[diffIndex].pos.x * top.width,
                        y: top.minY + base[diffIndex].pos.y * top.height)
        let b = CGPoint(x: bottom.minX + changed.pos.x * bottom.width,
                        y: bottom.minY + changed.pos.y * bottom.height)
        let ring = top.width * (tolFrac + 0.03) * 2
        return ForEach(Array([a, b].enumerated()), id: \.offset) { _, p in
            MarkerRing()
                .frame(width: ring, height: ring * 0.9)
                .position(p)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
        }
    }

    /// The demo's finger (on the top picture's differing item) plus the marker circles that ring
    /// the difference in both pictures at the "win" beat.
    @ViewBuilder
    private func demoOverlay(top: CGRect, bottom: CGRect) -> some View {
        // `base` is empty until runDemo() builds the scene in `.task`; skip until then.
        if diffIndex < base.count {
        let a = CGPoint(x: top.minX + base[diffIndex].pos.x * top.width,
                        y: top.minY + base[diffIndex].pos.y * top.height)
        if demoRing {
            markerRings(top: top, bottom: bottom)
        }
        if demoCrosshair {
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 3)
                .position(x: a.x + top.width * 0.06, y: a.y + top.height * 0.12)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
        }
        }
    }

    /// Scene B = the base items, but the differing item is replaced by its changed version.
    private var sceneB: [SceneItem] {
        var s = base
        if diffIndex < s.count { s[diffIndex] = changed }
        return s
    }

    // MARK: - Flow

    private func run() async {
        buildScene()
        phase = .play
        timeLeft = timeLimit
        let start = Date()
        while !Task.isCancelled && phase == .play {
            try? await Task.sleep(for: .seconds(0.05))
            timeLeft = max(0, timeLimit - Date().timeIntervalSince(start))
            if timeLeft <= 0 { fail(); break }
        }
    }

    // MARK: - Demo (live manual clip)

    /// Deterministic Level-1 replay: show the two scenes, glide a tap onto the one
    /// difference, flash the matching rings, hold, then reset and loop. Never calls
    /// onWin/onFail (it's just for the manual). Roughly a 3s loop.
    private func runDemo() async {
        demoScene()
        phase = .play
        timeLeft = timeLimit            // keep the time bar full
        while !Task.isCancelled {
            demoCrosshair = false
            demoRing = false
            try? await Task.sleep(for: .seconds(0.7))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.35)) { demoCrosshair = true }
            try? await Task.sleep(for: .seconds(0.85))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.3)) { demoRing = true }
            try? await Task.sleep(for: .seconds(1.3))       // hold on the "win"
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                demoCrosshair = false
                demoRing = false
            }
            try? await Task.sleep(for: .seconds(0.35))
        }
    }

    /// A fixed, readable 8-item scene with one clear color difference (item 5).
    private func demoScene() {
        let cols = 4, rows = 2
        let syms = ["tree.fill", "cloud.fill", "sun.max.fill", "leaf.fill",
                    "bird.fill", "mountain.2.fill", "fish.fill", "pawprint.fill"]
        let cols8: [Color] = [.green, .white, .yellow, .mint, .cyan, .teal, .orange, .green]
        var items: [SceneItem] = []
        for i in 0..<8 {
            let c = i % cols, r = i / cols
            let p = CGPoint(x: (CGFloat(c) + 0.5) / CGFloat(cols),
                            y: (CGFloat(r) + 0.5) / CGFloat(rows))
            items.append(SceneItem(symbol: syms[i], pos: p, size: 0.11, color: cols8[i]))
        }
        base = items
        diffIndex = 5                       // the mountain: teal on top, orange below
        var ch = items[5]
        ch.color = .orange
        changed = ch
    }

    private func buildScene() {
        // Place items on a jittered grid so a big count stays spread out (and hard
        // to scan) without collapsing into one overlapping clump.
        let cols = max(3, Int((Double(itemCount) * 1.5).squareRoot().rounded(.up)))
        let rows = Int((Double(itemCount) / Double(cols)).rounded(.up))
        var cells = (0..<rows).flatMap { r in (0..<cols).map { (c: $0, r: r) } }
        cells.shuffle()

        var items: [SceneItem] = []
        for i in 0..<itemCount {
            let cell = cells[i]
            let cx = (CGFloat(cell.c) + 0.5) / CGFloat(cols)
            let cy = (CGFloat(cell.r) + 0.5) / CGFloat(rows)
            let jx = CGFloat.random(in: -0.35...0.35) / CGFloat(cols)
            let jy = CGFloat.random(in: -0.35...0.35) / CGFloat(rows)
            let p = CGPoint(x: min(0.93, max(0.07, cx + jx)),
                            y: min(0.9, max(0.12, cy + jy)))
            let sz = CGFloat.random(in: 0.07...0.12)
            items.append(SceneItem(symbol: symbols.randomElement()!, pos: p, size: sz,
                                   color: palette.randomElement()!))
        }
        base = items
        diffIndex = Int.random(in: 0..<items.count)
        changed = mutate(items[diffIndex])
    }

    /// Produce the altered copy of an item. Magnitude of the change shrinks with
    /// the level so the difference gets subtler as you climb.
    private func mutate(_ item: SceneItem) -> SceneItem {
        var c = item
        let strong = level <= 3
        switch Int.random(in: 0..<5) {
        case 0: // color
            c.color = palette.filter { $0 != item.color }.randomElement() ?? .red
        case 1: // size
            let f: CGFloat = strong ? (Bool.random() ? 1.6 : 0.6) : (Bool.random() ? 1.22 : 0.82)
            c.size = max(0.05, item.size * f)
        case 2: // symbol swap
            c.symbol = symbols.filter { $0 != item.symbol }.randomElement() ?? "leaf.fill"
        case 3: // hide it entirely (missing in one scene)
            c.hidden = true
        default: // position nudge
            let d: CGFloat = strong ? 0.14 : 0.07
            c.pos = CGPoint(x: min(0.92, max(0.08, item.pos.x + CGFloat.random(in: -d...d))),
                            y: min(0.9, max(0.12, item.pos.y + CGFloat.random(in: -d...d))))
        }
        return c
    }

    private func handleTap(_ loc: CGPoint, top: CGRect, bottom: CGRect) {
        guard phase == .play else { return }
        let tol = tolFrac * top.width
        // The differing spot lives at the base item's position in the top scene and
        // the changed item's position in the bottom scene (they only differ for a
        // position-type change). Tapping near either counts.
        let a = CGPoint(x: top.minX + base[diffIndex].pos.x * top.width,
                        y: top.minY + base[diffIndex].pos.y * top.height)
        let b = CGPoint(x: bottom.minX + changed.pos.x * bottom.width,
                        y: bottom.minY + changed.pos.y * bottom.height)
        if hypot(loc.x - a.x, loc.y - a.y) < tol || hypot(loc.x - b.x, loc.y - b.y) < tol {
            withAnimation(.spring(duration: 0.3)) { circled = true }   // presentation: ring the difference
            win()
        } else {
            missAt = loc                                                   // presentation: ✕ the miss
            fail()
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

// MARK: - Picture-book art

/// What a picture needs to draw one item (Equatable, so the pictures only redraw when they change).
private struct StickerItem: Equatable {
    let symbol: String
    let pos: CGPoint
    let size: CGFloat
    let color: Color
    let hidden: Bool

    init(_ item: SceneItem) {
        symbol = item.symbol; pos = item.pos; size = item.size; color = item.color; hidden = item.hidden
    }
}

/// One framed picture: a painted sky-and-meadow with every item as an outlined sticker.
private struct SpotPicture: View, Equatable {
    let items: [StickerItem]
    let size: CGSize

    var body: some View {
        Canvas { ctx, s in
            let r = CGRect(origin: .zero, size: s)
            let frame = Path(roundedRect: r, cornerRadius: 14)
            var inside = ctx
            inside.clip(to: frame)
            SpotArt.scenery(inside, r)
            let ink = Color(red: 0.16, green: 0.13, blue: 0.2)
            for item in items where !item.hidden {
                var img = ctx.resolve(Image(systemName: item.symbol))
                let natural = img.size
                guard natural.width > 0 else { continue }
                let w = r.width * item.size
                let h = w * natural.height / natural.width
                let box = CGRect(x: item.pos.x * r.width - w / 2, y: item.pos.y * r.height - h / 2, width: w, height: h)
                // Soft sticker shadow, an ink outline, then the colour.
                img.shading = .color(.black.opacity(0.22))
                inside.draw(img, in: box.offsetBy(dx: 1.5, dy: 2.5))
                img.shading = .color(ink)
                let o: CGFloat = max(1.2, w * 0.045)
                for (dx, dy) in [(-o, 0), (o, 0), (0, -o), (0, o), (-o * 0.7, -o * 0.7), (o * 0.7, -o * 0.7), (-o * 0.7, o * 0.7), (o * 0.7, o * 0.7)] {
                    inside.draw(img, in: box.offsetBy(dx: dx, dy: dy))
                }
                img.shading = .color(item.color)
                inside.draw(img, in: box)
            }
            // White photo border with a soft drop shadow outside the picture.
            ctx.stroke(frame, with: .color(.white), lineWidth: 6)
            ctx.stroke(Path(roundedRect: r.insetBy(dx: -3, dy: -3), cornerRadius: 16), with: .color(.black.opacity(0.12)), lineWidth: 1)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(.white).padding(-3).shadow(color: .black.opacity(0.25), radius: 6, y: 3))
        .allowsHitTesting(false)
    }
}

private enum SpotArt {
    static func hash(_ n: Double) -> CGFloat {
        let v: Double = sin(n * 12.9898) * 43758.5453
        return CGFloat(v - floor(v))
    }

    /// Light sky, two rows of soft hills and a meadow — the same painting in both pictures.
    static func scenery(_ ctx: GraphicsContext, _ r: CGRect) {
        ctx.fill(Path(r), with: .linearGradient(Gradient(colors: [Color(red: 0.62, green: 0.84, blue: 0.98), Color(red: 0.88, green: 0.95, blue: 1)]),
                                                startPoint: CGPoint(x: 0, y: r.minY), endPoint: CGPoint(x: 0, y: r.minY + r.height * 0.55)))
        func hills(_ y: CGFloat, _ amp: CGFloat, _ phase: CGFloat, _ color: Color) {
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            for k in 0...24 {
                let x = r.minX + r.width * CGFloat(k) / 24
                p.addLine(to: CGPoint(x: x, y: r.minY + r.height * y - amp * r.height * sin(CGFloat(k) / 24 * .pi * 2.2 + phase)))
            }
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.closeSubpath()
            ctx.fill(p, with: .color(color))
        }
        hills(0.5, 0.06, 0.4, Color(red: 0.62, green: 0.82, blue: 0.62))
        hills(0.62, 0.05, 2.1, Color(red: 0.55, green: 0.78, blue: 0.45))
        ctx.fill(Path(CGRect(x: r.minX, y: r.minY + r.height * 0.7, width: r.width, height: r.height * 0.3)),
                 with: .linearGradient(Gradient(colors: [Color(red: 0.55, green: 0.78, blue: 0.42), Color(red: 0.47, green: 0.7, blue: 0.36)]),
                                       startPoint: CGPoint(x: 0, y: r.minY + r.height * 0.7), endPoint: CGPoint(x: 0, y: r.maxY)))
        var grass = Path()
        for k in 0..<60 {
            let x = r.minX + hash(Double(k) * 1.9) * r.width
            let y = r.minY + r.height * (0.66 + hash(Double(k) * 3.7) * 0.32)
            grass.move(to: CGPoint(x: x, y: y)); grass.addLine(to: CGPoint(x: x - 1.5, y: y - 4))
            grass.move(to: CGPoint(x: x + 2, y: y)); grass.addLine(to: CGPoint(x: x + 3, y: y - 5))
        }
        ctx.stroke(grass, with: .color(Color(red: 0.33, green: 0.55, blue: 0.25).opacity(0.5)), lineWidth: 1)
    }
}

/// The page behind the pictures: warm paper with a polka-dot print (static).
private struct PuzzlePage: View, Equatable {
    var body: some View {
        Canvas { ctx, s in
            ctx.fill(Path(CGRect(origin: .zero, size: s)),
                     with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.84, blue: 0.5), Color(red: 1, green: 0.7, blue: 0.42)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height)))
            var dots = Path()
            var y: CGFloat = 8
            var row = 0
            while y < s.height {
                var x: CGFloat = row % 2 == 0 ? 8 : 22
                while x < s.width { dots.addEllipse(in: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)); x += 28 }
                y += 24; row += 1
            }
            ctx.fill(dots, with: .color(.white.opacity(0.28)))
        }
        .allowsHitTesting(false)
    }
}

/// The clock as a pencil: sharpened away from the tip end as time runs out.
private struct PencilTimer: View {
    let frac: Double

    var body: some View {
        Canvas { ctx, s in
            let h = s.height, midY = h / 2
            let eraser = h * 1.1, ferrule = h * 0.7, tipLen = h * 1.3
            let bodyMax = s.width - eraser - ferrule - tipLen
            let bodyLen = max(0, bodyMax * CGFloat(max(0, min(1, frac))))
            let low = frac < 0.3
            ctx.fill(Path(roundedRect: CGRect(x: 0, y: 1, width: eraser + 3, height: h - 2), cornerRadius: h * 0.35),
                     with: .color(Color(red: 0.96, green: 0.56, blue: 0.62)))
            ctx.fill(Path(CGRect(x: eraser, y: 0, width: ferrule, height: h)),
                     with: .linearGradient(Gradient(colors: [Color(white: 0.92), Color(white: 0.62)]), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h)))
            var bands = Path()
            for k in 1...2 { let x = eraser + ferrule * CGFloat(k) / 3; bands.move(to: CGPoint(x: x, y: 0)); bands.addLine(to: CGPoint(x: x, y: h)) }
            ctx.stroke(bands, with: .color(Color(white: 0.45)), lineWidth: 1)
            let bx = eraser + ferrule
            let paint = low ? Color(red: 0.95, green: 0.3, blue: 0.25) : Color(red: 1, green: 0.8, blue: 0.2)
            ctx.fill(Path(CGRect(x: bx, y: 0, width: bodyLen, height: h)),
                     with: .linearGradient(Gradient(colors: [paint.lit(0.25), paint, paint.shade(0.2)]), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h)))
            var facet = Path()
            facet.move(to: CGPoint(x: bx, y: midY)); facet.addLine(to: CGPoint(x: bx + bodyLen, y: midY))
            ctx.stroke(facet, with: .color(paint.shade(0.25).opacity(0.6)), lineWidth: 1)
            let tx = bx + bodyLen
            var wood = Path()
            wood.move(to: CGPoint(x: tx, y: 0)); wood.addLine(to: CGPoint(x: tx + tipLen, y: midY)); wood.addLine(to: CGPoint(x: tx, y: h)); wood.closeSubpath()
            ctx.fill(wood, with: .color(Color(red: 0.93, green: 0.78, blue: 0.56)))
            var lead = Path()
            lead.move(to: CGPoint(x: tx + tipLen * 0.62, y: midY - h * 0.19)); lead.addLine(to: CGPoint(x: tx + tipLen, y: midY)); lead.addLine(to: CGPoint(x: tx + tipLen * 0.62, y: midY + h * 0.19)); lead.closeSubpath()
            ctx.fill(lead, with: .color(Color(white: 0.2)))
        }
        .allowsHitTesting(false)
    }
}

/// The found-it badge beside the pencil.
private struct FoundBadge: View {
    let found: Bool
    var body: some View {
        ZStack {
            Circle().fill(found ? Color(red: 0.2, green: 0.72, blue: 0.3) : .white.opacity(0.85))
            Circle().stroke(found ? Color(red: 0.1, green: 0.45, blue: 0.16) : Color(red: 0.7, green: 0.5, blue: 0.3), lineWidth: 2)
            if found {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .black)).foregroundStyle(.white)
            }
        }
        .animation(.spring(duration: 0.3), value: found)
    }
}

/// A hand-drawn red marker circle (two slightly different loops).
private struct MarkerRing: View {
    var body: some View {
        Canvas { ctx, s in
            let r = CGRect(origin: .zero, size: s).insetBy(dx: 3, dy: 3)
            var p = Path()
            p.addEllipse(in: r)
            p.addEllipse(in: r.insetBy(dx: 1.5, dy: -1).offsetBy(dx: 1.5, dy: 1))
            ctx.stroke(p, with: .color(Color(red: 0.9, green: 0.1, blue: 0.12)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        .allowsHitTesting(false)
    }
}

/// A red marker ✕ where a wrong tap landed.
private struct MarkerCross: View {
    var body: some View {
        Canvas { ctx, s in
            let r = CGRect(origin: .zero, size: s).insetBy(dx: 3, dy: 3)
            var x = Path()
            x.move(to: CGPoint(x: r.minX, y: r.minY)); x.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            x.move(to: CGPoint(x: r.maxX, y: r.minY)); x.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            ctx.stroke(x, with: .color(.white), style: StrokeStyle(lineWidth: 7, lineCap: .round))
            ctx.stroke(x, with: .color(Color(red: 0.9, green: 0.1, blue: 0.12)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
        .allowsHitTesting(false)
    }
}

