//
//  FruitArt.swift
//  GOGs
//
//  Shared vector fruit illustrations in the Suika style: glossy bodies lit from the upper-left, a
//  darker rim, stems/leaves, and an optional kawaii face. Every fruit is drawn in a unit circle
//  (body radius ≈ 1, stems/crowns may poke above it), so one call scales to any radius.
//  Fruit Merge draws them as its (rotating) physics bodies with faces; Tile Trio uses them as tile
//  icons. No emoji — everything here is paths and gradients.
//

import SwiftUI

enum FruitKind: Int, CaseIterable, Sendable {
    // The Suika evolution order (index = merge tier).
    case cherry, strawberry, grape, dekopon, persimmon, apple, pear, peach, pineapple, melon, watermelon
    // Extra tile-only kinds.
    case banana, lemon
}

enum FruitArt {
    /// Signature body color (bursts, accents).
    static func color(_ k: FruitKind) -> Color {
        switch k {
        case .cherry:     return Color(red: 0.86, green: 0.10, blue: 0.20)
        case .strawberry: return Color(red: 0.95, green: 0.25, blue: 0.34)
        case .grape:      return Color(red: 0.55, green: 0.30, blue: 0.80)
        case .dekopon:    return Color(red: 1.00, green: 0.63, blue: 0.14)
        case .persimmon:  return Color(red: 0.97, green: 0.43, blue: 0.11)
        case .apple:      return Color(red: 0.90, green: 0.12, blue: 0.16)
        case .pear:       return Color(red: 0.95, green: 0.87, blue: 0.45)
        case .peach:      return Color(red: 1.00, green: 0.69, blue: 0.73)
        case .pineapple:  return Color(red: 0.97, green: 0.75, blue: 0.20)
        case .melon:      return Color(red: 0.67, green: 0.86, blue: 0.44)
        case .watermelon: return Color(red: 0.18, green: 0.62, blue: 0.26)
        case .banana:     return Color(red: 1.00, green: 0.85, blue: 0.24)
        case .lemon:      return Color(red: 1.00, green: 0.90, blue: 0.32)
        }
    }

    /// Draws `kind` centred at `center` with body radius `radius`, rotated by `angle`.
    static func draw(_ kind: FruitKind, in context: GraphicsContext, at center: CGPoint,
                     radius: CGFloat, angle: Angle = .zero, face: Bool = false) {
        guard radius > 0.5 else { return }
        var c = context
        c.translateBy(x: center.x, y: center.y)
        c.rotate(by: angle)
        c.scaleBy(x: radius, y: radius)
        switch kind {
        case .cherry:     cherry(c)
        case .strawberry: strawberry(c)
        case .grape:      grape(c)
        case .dekopon:    dekopon(c)
        case .persimmon:  persimmon(c)
        case .apple:      apple(c)
        case .pear:       pear(c)
        case .peach:      peach(c)
        case .pineapple:  pineapple(c)
        case .melon:      melon(c)
        case .watermelon: watermelon(c)
        case .banana:     banana(c)
        case .lemon:      lemon(c)
        }
        if face {
            switch kind {
            case .strawberry: drawFace(c, y: -0.1, s: 0.9)
            case .grape:      drawFace(c, y: 0.0, s: 0.72)
            case .pineapple:  drawFace(c, y: 0.18, s: 0.9)
            case .persimmon:  drawFace(c, y: 0.14, s: 1)
            default:          drawFace(c, y: 0.1, s: 1)
            }
        }
    }

    // MARK: - Primitives

    private static func disc(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    private static func oval(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2))
    }

    /// Glossy body: light from the upper-left falling off to a slightly darker far side, plus a rim.
    private static func body(_ c: GraphicsContext, _ p: Path, _ base: Color,
                             far: Color? = nil, rim: Double = 0.42, rimWidth: CGFloat = 0.075) {
        c.fill(p, with: .radialGradient(Gradient(colors: [base.lit(0.5), base, far ?? base.shade(0.25)]),
                                        center: CGPoint(x: -0.38, y: -0.42), startRadius: 0.02, endRadius: 1.6))
        c.stroke(p, with: .color(base.shade(rim)), lineWidth: rimWidth)
    }

    /// The specular glint: a tilted white ellipse on the lit side.
    private static func gloss(_ c: GraphicsContext, x: CGFloat = -0.42, y: CGFloat = -0.42,
                              rx: CGFloat = 0.22, ry: CGFloat = 0.12, opacity: Double = 0.75) {
        var g = c
        g.translateBy(x: x, y: y)
        g.rotate(by: .degrees(-38))
        g.fill(oval(0, 0, rx, ry), with: .color(.white.opacity(opacity)))
        g.fill(oval(rx * 1.35, ry * 0.4, rx * 0.22, ry * 0.45), with: .color(.white.opacity(opacity * 0.8)))
    }

    private static let leafGreen = Color(red: 0.30, green: 0.70, blue: 0.24)
    private static let stemBrown = Color(red: 0.43, green: 0.28, blue: 0.14)

    /// A pointed leaf from `a` to `b`, `w` wide at the middle, with a midrib.
    private static func leaf(_ c: GraphicsContext, _ a: CGPoint, _ b: CGPoint, w: CGFloat,
                             color: Color = leafGreen) {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(0.0001, hypot(dx, dy))
        let nx = -dy / len * w, ny = dx / len * w
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        var p = Path()
        p.move(to: a)
        p.addQuadCurve(to: b, control: CGPoint(x: mid.x + nx, y: mid.y + ny))
        p.addQuadCurve(to: a, control: CGPoint(x: mid.x - nx, y: mid.y - ny))
        c.fill(p, with: .linearGradient(Gradient(colors: [color.lit(0.3), color.shade(0.12)]),
                                        startPoint: CGPoint(x: mid.x + nx, y: mid.y + ny),
                                        endPoint: CGPoint(x: mid.x - nx, y: mid.y - ny)))
        c.stroke(p, with: .color(color.shade(0.5)), lineWidth: 0.05)
        var rib = Path()
        rib.move(to: a)
        rib.addLine(to: CGPoint(x: a.x + dx * 0.78, y: a.y + dy * 0.78))
        c.stroke(rib, with: .color(color.shade(0.4).opacity(0.8)), lineWidth: 0.035)
    }

    private static func stem(_ c: GraphicsContext, _ a: CGPoint, _ ctrl: CGPoint, _ b: CGPoint,
                             w: CGFloat = 0.1, color: Color = stemBrown) {
        var p = Path()
        p.move(to: a)
        p.addQuadCurve(to: b, control: ctrl)
        c.stroke(p, with: .color(color.shade(0.35)), style: StrokeStyle(lineWidth: w + 0.05, lineCap: .round))
        c.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: w, lineCap: .round))
    }

    /// Fixed pseudo-random points inside a disc (so speckles never shimmer between frames).
    private static func scatter(seed: UInt64, count: Int, radius: CGFloat, cy: CGFloat = 0) -> [CGPoint] {
        var s = seed
        func next() -> CGFloat {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((s >> 33) % 10_000) / 10_000
        }
        var out: [CGPoint] = []
        while out.count < count {
            let p = CGPoint(x: (next() * 2 - 1) * radius, y: (next() * 2 - 1) * radius)
            if hypot(p.x, p.y) < radius { out.append(CGPoint(x: p.x, y: p.y + cy)) }
        }
        return out
    }

    private static let dekoponDimples = scatter(seed: 11, count: 16, radius: 0.72, cy: 0.1)
    private static let pearSpecks = scatter(seed: 7, count: 18, radius: 0.74, cy: 0.06)
    private static let lemonDimples = scatter(seed: 23, count: 12, radius: 0.55)

    // MARK: - Face

    private static func drawFace(_ c: GraphicsContext, y: CGFloat, s: CGFloat) {
        let ink = Color(red: 0.14, green: 0.08, blue: 0.08)
        c.fill(oval(-0.3 * s, y, 0.075 * s, 0.1 * s), with: .color(ink))
        c.fill(oval(0.3 * s, y, 0.075 * s, 0.1 * s), with: .color(ink))
        c.fill(disc(-0.325 * s, y - 0.035 * s, 0.03 * s), with: .color(.white))
        c.fill(disc(0.275 * s, y - 0.035 * s, 0.03 * s), with: .color(.white))
        var m = Path()
        m.move(to: CGPoint(x: -0.1 * s, y: y + 0.16 * s))
        m.addQuadCurve(to: CGPoint(x: 0.1 * s, y: y + 0.16 * s), control: CGPoint(x: 0, y: y + 0.28 * s))
        c.stroke(m, with: .color(ink), style: StrokeStyle(lineWidth: 0.05 * s, lineCap: .round))
        let blush = Color(red: 1, green: 0.42, blue: 0.5).opacity(0.5)
        c.fill(oval(-0.52 * s, y + 0.15 * s, 0.13 * s, 0.075 * s), with: .color(blush))
        c.fill(oval(0.52 * s, y + 0.15 * s, 0.13 * s, 0.075 * s), with: .color(blush))
    }

    // MARK: - Fruits

    private static func cherry(_ c: GraphicsContext) {
        let red = color(.cherry)
        body(c, disc(0, 0.1, 0.88), red)
        c.fill(oval(0.02, -0.72, 0.13, 0.06), with: .color(red.shade(0.45)))     // stem dimple
        stem(c, CGPoint(x: 0.02, y: -0.72), CGPoint(x: 0.04, y: -1.08), CGPoint(x: 0.36, y: -1.22),
             w: 0.09, color: Color(red: 0.42, green: 0.52, blue: 0.18))
        leaf(c, CGPoint(x: 0.34, y: -1.2), CGPoint(x: 0.9, y: -1.02), w: 0.2)
        gloss(c, x: -0.38, y: -0.25)
    }

    private static func strawberry(_ c: GraphicsContext) {
        let red = color(.strawberry)
        var p = Path()
        p.move(to: CGPoint(x: -0.86, y: -0.4))
        p.addCurve(to: CGPoint(x: 0, y: 0.98), control1: CGPoint(x: -0.94, y: 0.32), control2: CGPoint(x: -0.4, y: 0.9))
        p.addCurve(to: CGPoint(x: 0.86, y: -0.4), control1: CGPoint(x: 0.4, y: 0.9), control2: CGPoint(x: 0.94, y: 0.32))
        p.addCurve(to: CGPoint(x: -0.86, y: -0.4), control1: CGPoint(x: 0.7, y: -0.98), control2: CGPoint(x: -0.7, y: -0.98))
        body(c, p, red)
        let seedRows: [(CGFloat, [CGFloat])] = [(-0.3, [-0.55, -0.2, 0.2, 0.55]), (0.02, [-0.62, -0.28, 0.08, 0.44]),
                                               (0.32, [-0.4, -0.05, 0.3]), (0.6, [-0.17, 0.17])]
        let seed = Color(red: 1.0, green: 0.92, blue: 0.62)
        for (y, xs) in seedRows {
            for x in xs {
                c.fill(oval(x, y, 0.045, 0.07), with: .color(red.shade(0.45)))
                c.fill(oval(x, y - 0.012, 0.035, 0.055), with: .color(seed))
            }
        }
        // Calyx: a green star of leaves across the top.
        let top = CGPoint(x: 0, y: -0.7)
        for deg in [200.0, 235.0, 270.0, 305.0, 340.0] {
            let a = deg * .pi / 180
            leaf(c, top, CGPoint(x: top.x + cos(a) * 0.62, y: top.y + sin(a) * 0.42), w: 0.13)
        }
        stem(c, CGPoint(x: 0, y: -0.78), CGPoint(x: 0.02, y: -0.98), CGPoint(x: 0.1, y: -1.1),
             w: 0.09, color: leafGreen.shade(0.1))
        gloss(c, x: -0.45, y: -0.32, rx: 0.18, ry: 0.1)
    }

    private static func grape(_ c: GraphicsContext) {
        let purple = color(.grape)
        stem(c, CGPoint(x: 0, y: -0.7), CGPoint(x: 0.02, y: -1.0), CGPoint(x: 0.14, y: -1.14), w: 0.1)
        leaf(c, CGPoint(x: 0.1, y: -1.02), CGPoint(x: 0.66, y: -1.12), w: 0.2)
        // A round bunch: six grapes around one, lower ones in front.
        var spots: [CGPoint] = (0..<6).map { i in
            let a = Double(i) * .pi / 3 - .pi / 2
            return CGPoint(x: cos(a) * 0.56, y: sin(a) * 0.56)
        }
        spots.sort { $0.y < $1.y }
        for (i, p) in spots.enumerated() {
            if i == 3 {   // the centre grape sits between the upper and lower rings
                grapeBerry(c, CGPoint.zero, purple)
            }
            grapeBerry(c, p, purple)
        }
    }

    private static func grapeBerry(_ c: GraphicsContext, _ p: CGPoint, _ purple: Color) {
        var g = c
        g.translateBy(x: p.x, y: p.y)
        body(g, disc(0, 0, 0.42), purple, rimWidth: 0.06)
        g.fill(oval(-0.14, -0.15, 0.1, 0.06), with: .color(.white.opacity(0.7)))
    }

    private static func dekopon(_ c: GraphicsContext) {
        let orange = color(.dekopon)
        body(c, disc(0, -0.74, 0.3), orange)                    // the "deko" bump
        body(c, disc(0, 0.12, 0.88), orange)
        for p in dekoponDimples {
            c.fill(disc(p.x, p.y, 0.028), with: .color(orange.shade(0.28).opacity(0.7)))
        }
        leaf(c, CGPoint(x: 0.04, y: -0.98), CGPoint(x: 0.6, y: -1.16), w: 0.2)
        c.fill(disc(0.02, -1.0, 0.07), with: .color(stemBrown))
        gloss(c, x: -0.4, y: -0.22)
    }

    private static func persimmon(_ c: GraphicsContext) {
        let orange = color(.persimmon)
        body(c, oval(0, 0.1, 0.96, 0.86), orange, far: Color(red: 0.82, green: 0.26, blue: 0.08))
        let base = CGPoint(x: 0, y: -0.7)
        for tip in [CGPoint(x: -0.6, y: -0.6), CGPoint(x: 0.6, y: -0.6), CGPoint(x: -0.28, y: -0.98), CGPoint(x: 0.28, y: -0.98)] {
            leaf(c, base, tip, w: 0.2, color: Color(red: 0.36, green: 0.58, blue: 0.2))
        }
        c.fill(disc(0, -0.76, 0.1), with: .color(stemBrown))
        gloss(c, x: -0.45, y: -0.2)
    }

    private static func apple(_ c: GraphicsContext) {
        let red = color(.apple)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -0.62))
        p.addCurve(to: CGPoint(x: -0.96, y: -0.08), control1: CGPoint(x: -0.36, y: -0.98), control2: CGPoint(x: -0.96, y: -0.78))
        p.addCurve(to: CGPoint(x: 0, y: 0.96), control1: CGPoint(x: -0.96, y: 0.62), control2: CGPoint(x: -0.45, y: 0.98))
        p.addCurve(to: CGPoint(x: 0.96, y: -0.08), control1: CGPoint(x: 0.45, y: 0.98), control2: CGPoint(x: 0.96, y: 0.62))
        p.addCurve(to: CGPoint(x: 0, y: -0.62), control1: CGPoint(x: 0.96, y: -0.78), control2: CGPoint(x: 0.36, y: -0.98))
        body(c, p, red, far: Color(red: 0.62, green: 0.05, blue: 0.1))
        stem(c, CGPoint(x: 0, y: -0.6), CGPoint(x: 0.0, y: -0.9), CGPoint(x: 0.12, y: -1.06), w: 0.1)
        leaf(c, CGPoint(x: 0.1, y: -0.9), CGPoint(x: 0.66, y: -1.06), w: 0.22)
        gloss(c, x: -0.46, y: -0.34)
    }

    private static func pear(_ c: GraphicsContext) {
        let yellow = color(.pear)
        body(c, disc(0, 0.06, 0.93), yellow, far: Color(red: 0.8, green: 0.72, blue: 0.3))
        for p in pearSpecks {
            c.fill(disc(p.x, p.y, 0.025), with: .color(Color(red: 0.62, green: 0.5, blue: 0.22).opacity(0.6)))
        }
        c.fill(oval(0, -0.82, 0.14, 0.06), with: .color(yellow.shade(0.4)))
        stem(c, CGPoint(x: 0, y: -0.82), CGPoint(x: 0.0, y: -1.02), CGPoint(x: 0.1, y: -1.12), w: 0.1)
        gloss(c, x: -0.42, y: -0.38)
    }

    private static func peach(_ c: GraphicsContext) {
        let pink = color(.peach)
        body(c, disc(0, 0.06, 0.93), pink, far: Color(red: 1.0, green: 0.56, blue: 0.42), rim: 0.38)
        var crease = Path()
        crease.move(to: CGPoint(x: 0.08, y: -0.84))
        crease.addQuadCurve(to: CGPoint(x: -0.18, y: 0.5), control: CGPoint(x: -0.36, y: -0.22))
        c.stroke(crease, with: .color(Color(red: 0.9, green: 0.42, blue: 0.48).opacity(0.75)),
                 style: StrokeStyle(lineWidth: 0.07, lineCap: .round))
        leaf(c, CGPoint(x: 0.06, y: -0.86), CGPoint(x: 0.64, y: -1.08), w: 0.22)
        leaf(c, CGPoint(x: 0.02, y: -0.86), CGPoint(x: -0.36, y: -1.12), w: 0.16)
        gloss(c, x: -0.46, y: -0.32, opacity: 0.6)
    }

    private static func pineapple(_ c: GraphicsContext) {
        let gold = color(.pineapple)
        let base = CGPoint(x: 0, y: -0.62)
        let crown = Color(red: 0.26, green: 0.62, blue: 0.26)
        for tip in [CGPoint(x: -0.62, y: -1.02), CGPoint(x: 0.62, y: -1.02), CGPoint(x: -0.3, y: -1.28),
                    CGPoint(x: 0.3, y: -1.28), CGPoint(x: 0, y: -1.4)] {
            leaf(c, base, tip, w: 0.15, color: crown)
        }
        let shape = oval(0, 0.16, 0.84, 0.86)
        body(c, shape, gold, far: Color(red: 0.85, green: 0.52, blue: 0.1))
        var clip = c
        clip.clip(to: shape)
        var hatch = Path()
        for i in -6...6 {
            let o = CGFloat(i) * 0.3
            hatch.move(to: CGPoint(x: o - 1.2, y: -1.2)); hatch.addLine(to: CGPoint(x: o + 1.2, y: 1.2))
            hatch.move(to: CGPoint(x: o + 1.2, y: -1.2)); hatch.addLine(to: CGPoint(x: o - 1.2, y: 1.2))
        }
        clip.stroke(hatch, with: .color(Color(red: 0.72, green: 0.45, blue: 0.08).opacity(0.75)), lineWidth: 0.045)
        for i in -4...4 {
            for j in -4...4 where (i + j) % 2 == 0 {
                let x = CGFloat(i) * 0.212, y = CGFloat(j) * 0.212 + 0.16
                clip.fill(disc(x, y, 0.03), with: .color(Color(red: 0.6, green: 0.36, blue: 0.06).opacity(0.7)))
            }
        }
        c.stroke(shape, with: .color(gold.shade(0.45)), lineWidth: 0.075)
        gloss(c, x: -0.42, y: -0.26, opacity: 0.55)
    }

    private static func melon(_ c: GraphicsContext) {
        let green = color(.melon)
        let shape = disc(0, 0.04, 0.95)
        body(c, shape, green, far: Color(red: 0.45, green: 0.66, blue: 0.3))
        var clip = c
        clip.clip(to: shape)
        var net = Path()
        let jit: [CGFloat] = [0.06, -0.05, 0.08, -0.07, 0.04, -0.06, 0.07]
        for i in 0..<7 {
            let y = -0.84 + CGFloat(i) * 0.3
            net.move(to: CGPoint(x: -1.1, y: y))
            net.addCurve(to: CGPoint(x: 1.1, y: y + jit[i] * 0.5),
                         control1: CGPoint(x: -0.4, y: y + jit[i] * 2.2), control2: CGPoint(x: 0.4, y: y - jit[(i + 2) % 7] * 2.2))
            let x = -0.9 + CGFloat(i) * 0.3
            net.move(to: CGPoint(x: x, y: -1.1))
            net.addCurve(to: CGPoint(x: x * 0.7 + jit[i], y: 1.1),
                         control1: CGPoint(x: x * 1.18 + jit[(i + 3) % 7] * 2, y: -0.35), control2: CGPoint(x: x * 1.12 - jit[i] * 2, y: 0.4))
        }
        clip.stroke(net, with: .color(Color(red: 0.93, green: 0.97, blue: 0.84).opacity(0.8)), lineWidth: 0.05)
        c.stroke(shape, with: .color(green.shade(0.45)), lineWidth: 0.075)
        stem(c, CGPoint(x: 0, y: -0.86), CGPoint(x: 0, y: -1.0), CGPoint(x: 0, y: -1.12), w: 0.11,
             color: Color(red: 0.5, green: 0.55, blue: 0.24))
        stem(c, CGPoint(x: -0.16, y: -1.12), CGPoint(x: 0, y: -1.15), CGPoint(x: 0.16, y: -1.12), w: 0.09,
             color: Color(red: 0.5, green: 0.55, blue: 0.24))
        gloss(c, x: -0.44, y: -0.36, opacity: 0.6)
    }

    private static func watermelon(_ c: GraphicsContext) {
        let green = color(.watermelon)
        let shape = disc(0, 0, 0.97)
        body(c, shape, green.lit(0.1), far: Color(red: 0.08, green: 0.38, blue: 0.14))
        var clip = c
        clip.clip(to: shape)
        let dark = Color(red: 0.07, green: 0.33, blue: 0.12)
        for (i, s) in ([-0.86, -0.52, -0.18, 0.18, 0.52, 0.86] as [CGFloat]).enumerated() {
            var stripe = Path()
            var first = true
            var y: CGFloat = -1.0
            while y <= 1.0001 {
                let zig: CGFloat = (Int((y + 1) * 10) % 2 == 0 ? 1 : -1) * 0.055 * (i % 2 == 0 ? 1 : -1)
                let pt = CGPoint(x: s * sqrt(max(0, 1 - y * y)) + zig, y: y)
                if first { stripe.move(to: pt); first = false } else { stripe.addLine(to: pt) }
                y += 0.1
            }
            clip.stroke(stripe, with: .color(dark), style: StrokeStyle(lineWidth: 0.13, lineJoin: .round))
        }
        c.stroke(shape, with: .color(dark.shade(0.3)), lineWidth: 0.075)
        c.fill(disc(0, -0.95, 0.08), with: .color(stemBrown))
        gloss(c, x: -0.44, y: -0.44, opacity: 0.55)
    }

    private static func banana(_ c: GraphicsContext) {
        let yellow = color(.banana)
        // A chunky crescent: a deep outer belly and a shallow inner curve.
        var p = Path()
        p.move(to: CGPoint(x: -0.95, y: -0.36))
        p.addCurve(to: CGPoint(x: 0.86, y: -0.62), control1: CGPoint(x: -0.8, y: 0.95), control2: CGPoint(x: 0.66, y: 0.98))
        p.addLine(to: CGPoint(x: 0.7, y: -0.44))
        p.addCurve(to: CGPoint(x: -0.8, y: -0.2), control1: CGPoint(x: 0.42, y: 0.22), control2: CGPoint(x: -0.52, y: 0.24))
        p.closeSubpath()
        body(c, p, yellow, far: Color(red: 0.92, green: 0.64, blue: 0.08), rim: 0.5)
        var ridge = Path()
        ridge.move(to: CGPoint(x: -0.8, y: -0.1))
        ridge.addCurve(to: CGPoint(x: 0.72, y: -0.4), control1: CGPoint(x: -0.6, y: 0.62), control2: CGPoint(x: 0.5, y: 0.66))
        c.stroke(ridge, with: .color(.white.opacity(0.4)), style: StrokeStyle(lineWidth: 0.07, lineCap: .round))
        stem(c, CGPoint(x: 0.8, y: -0.54), CGPoint(x: 0.9, y: -0.66), CGPoint(x: 0.92, y: -0.8), w: 0.15,
             color: Color(red: 0.52, green: 0.44, blue: 0.16))
        c.fill(disc(-0.9, -0.3, 0.075), with: .color(Color(red: 0.32, green: 0.2, blue: 0.08)))
    }

    private static func lemon(_ c: GraphicsContext) {
        let yellow = color(.lemon)
        var g = c
        g.rotate(by: .degrees(-24))
        // One silhouette with softly pointed ends (no separate nub blobs).
        var shape = Path()
        shape.move(to: CGPoint(x: -1.0, y: 0))
        shape.addCurve(to: CGPoint(x: 0, y: -0.66), control1: CGPoint(x: -0.9, y: -0.34), control2: CGPoint(x: -0.52, y: -0.66))
        shape.addCurve(to: CGPoint(x: 1.0, y: 0), control1: CGPoint(x: 0.52, y: -0.66), control2: CGPoint(x: 0.9, y: -0.34))
        shape.addCurve(to: CGPoint(x: 0, y: 0.66), control1: CGPoint(x: 0.9, y: 0.34), control2: CGPoint(x: 0.52, y: 0.66))
        shape.addCurve(to: CGPoint(x: -1.0, y: 0), control1: CGPoint(x: -0.52, y: 0.66), control2: CGPoint(x: -0.9, y: 0.34))
        shape.closeSubpath()
        body(g, shape, yellow, far: Color(red: 0.88, green: 0.72, blue: 0.1), rim: 0.45)
        for p in lemonDimples {
            g.fill(disc(p.x * 1.3, p.y, 0.025), with: .color(yellow.shade(0.3).opacity(0.6)))
        }
        leaf(g, CGPoint(x: 0.66, y: -0.26), CGPoint(x: 0.96, y: -0.8), w: 0.18)
        gloss(g, x: -0.36, y: -0.28, rx: 0.24, ry: 0.1)
    }
}

/// A single fruit as a SwiftUI view (used for small UI icons: goals, next-fruit bubbles, tray tiles).
struct FruitIcon: View {
    let kind: FruitKind
    var face = false
    /// Body radius as a fraction of the smaller side (stems/crowns need headroom above it).
    var scale: CGFloat = 0.36

    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) * scale
            FruitArt.draw(kind, in: ctx, at: CGPoint(x: size.width / 2, y: size.height / 2 + r * 0.12),
                          radius: r, face: face)
        }
    }
}
