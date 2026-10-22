//
//  LawnDefenseArt.swift
//  A Banana Game
//
//  Lawn Defense's art: the seven worlds (sky, lawn, edges and seed bar), the ten plants and their seed
//  packets, the zombies in each world's clothes, the shots and effects, and the scene composition (one
//  Canvas). Cartoon vector drawing; the bosses are in LawnDefenseBosses.swift. The corn popper, frost
//  berry, melon lobber, banana peel, flytrap, hot chili, the world outfits and the bosses are original
//  designs; the sunflower, peashooter, walnut, cherry bomb and the coat-and-tie zombie keep the 2009 look.
//

import SwiftUI

// MARK: - Worlds

/// A world's colours.
struct LDLook {
    let skyTop: Color
    let skyBottom: Color
    let tileLight: Color
    let tileDark: Color
    let tileMark: Color         // grass blades, plank seams, cracks…
    let yardTop: Color
    let yardBottom: Color
    let bar: [Color]            // seed bar, top to bottom
    let barEdge: Color
    let sprite: Color?          // a colour wash over plants and zombies (dusk, night, neon)

    static func of(_ s: LDScene) -> LDLook {
        switch s {
        case .backyard:
            return LDLook(skyTop: Color(red: 0.42, green: 0.7, blue: 0.95), skyBottom: Color(red: 0.78, green: 0.9, blue: 0.98),
                          tileLight: Color(red: 0.43, green: 0.74, blue: 0.17), tileDark: Color(red: 0.35, green: 0.64, blue: 0.12),
                          tileMark: Color(red: 0.25, green: 0.5, blue: 0.08),
                          yardTop: Color(red: 0.24, green: 0.52, blue: 0.12), yardBottom: Color(red: 0.14, green: 0.36, blue: 0.08),
                          bar: [Color(red: 0.62, green: 0.4, blue: 0.2), Color(red: 0.45, green: 0.27, blue: 0.12)],
                          barEdge: Color(red: 0.24, green: 0.13, blue: 0.05), sprite: nil)
        case .desert:
            return LDLook(skyTop: Color(red: 0.55, green: 0.78, blue: 0.95), skyBottom: Color(red: 0.98, green: 0.88, blue: 0.66),
                          tileLight: Color(red: 0.93, green: 0.8, blue: 0.55), tileDark: Color(red: 0.86, green: 0.71, blue: 0.45),
                          tileMark: Color(red: 0.66, green: 0.5, blue: 0.28),
                          yardTop: Color(red: 0.9, green: 0.74, blue: 0.47), yardBottom: Color(red: 0.78, green: 0.6, blue: 0.35),
                          bar: [Color(red: 0.86, green: 0.7, blue: 0.45), Color(red: 0.7, green: 0.53, blue: 0.3)],
                          barEdge: Color(red: 0.42, green: 0.28, blue: 0.12), sprite: nil)
        case .pirate:
            return LDLook(skyTop: Color(red: 0.36, green: 0.68, blue: 0.95), skyBottom: Color(red: 0.75, green: 0.9, blue: 1.0),
                          tileLight: Color(red: 0.72, green: 0.5, blue: 0.3), tileDark: Color(red: 0.62, green: 0.41, blue: 0.23),
                          tileMark: Color(red: 0.36, green: 0.22, blue: 0.1),
                          yardTop: Color(red: 0.12, green: 0.42, blue: 0.62), yardBottom: Color(red: 0.06, green: 0.24, blue: 0.42),
                          bar: [Color(red: 0.42, green: 0.25, blue: 0.13), Color(red: 0.3, green: 0.17, blue: 0.08)],
                          barEdge: Color(red: 0.78, green: 0.6, blue: 0.25), sprite: nil)
        case .frontier:
            return LDLook(skyTop: Color(red: 0.55, green: 0.4, blue: 0.62), skyBottom: Color(red: 1.0, green: 0.66, blue: 0.38),
                          tileLight: Color(red: 0.78, green: 0.66, blue: 0.38), tileDark: Color(red: 0.7, green: 0.57, blue: 0.3),
                          tileMark: Color(red: 0.5, green: 0.38, blue: 0.18),
                          yardTop: Color(red: 0.72, green: 0.5, blue: 0.3), yardBottom: Color(red: 0.55, green: 0.34, blue: 0.2),
                          bar: [Color(red: 0.72, green: 0.56, blue: 0.4), Color(red: 0.55, green: 0.4, blue: 0.27)],
                          barEdge: Color(red: 0.32, green: 0.2, blue: 0.1), sprite: Color(red: 1.0, green: 0.88, blue: 0.8))
        case .glacier:
            return LDLook(skyTop: Color(red: 0.1, green: 0.18, blue: 0.36), skyBottom: Color(red: 0.36, green: 0.55, blue: 0.75),
                          tileLight: Color(red: 0.9, green: 0.96, blue: 1.0), tileDark: Color(red: 0.78, green: 0.88, blue: 0.97),
                          tileMark: Color(red: 0.55, green: 0.72, blue: 0.9),
                          yardTop: Color(red: 0.86, green: 0.93, blue: 0.99), yardBottom: Color(red: 0.6, green: 0.75, blue: 0.9),
                          bar: [Color(red: 0.6, green: 0.78, blue: 0.92), Color(red: 0.4, green: 0.58, blue: 0.78)],
                          barEdge: Color(red: 0.16, green: 0.3, blue: 0.5), sprite: Color(red: 0.9, green: 0.95, blue: 1.0))
        case .future:
            return LDLook(skyTop: Color(red: 0.07, green: 0.03, blue: 0.2), skyBottom: Color(red: 0.32, green: 0.12, blue: 0.45),
                          tileLight: Color(red: 0.3, green: 0.34, blue: 0.46), tileDark: Color(red: 0.23, green: 0.26, blue: 0.37),
                          tileMark: Color(red: 0.2, green: 0.95, blue: 0.95),
                          yardTop: Color(red: 0.14, green: 0.1, blue: 0.26), yardBottom: Color(red: 0.06, green: 0.04, blue: 0.14),
                          bar: [Color(red: 0.5, green: 0.54, blue: 0.62), Color(red: 0.3, green: 0.33, blue: 0.42)],
                          barEdge: Color(red: 0.2, green: 0.95, blue: 0.95), sprite: Color(red: 0.88, green: 0.9, blue: 1.0))
        case .rooftop:
            return LDLook(skyTop: Color(red: 0.04, green: 0.05, blue: 0.16), skyBottom: Color(red: 0.16, green: 0.18, blue: 0.38),
                          tileLight: Color(red: 0.4, green: 0.36, blue: 0.58), tileDark: Color(red: 0.33, green: 0.29, blue: 0.5),
                          tileMark: Color(red: 0.2, green: 0.17, blue: 0.32),
                          yardTop: Color(red: 0.22, green: 0.18, blue: 0.32), yardBottom: Color(red: 0.1, green: 0.08, blue: 0.18),
                          bar: [Color(red: 0.42, green: 0.28, blue: 0.2), Color(red: 0.28, green: 0.17, blue: 0.12)],
                          barEdge: Color(red: 0.14, green: 0.08, blue: 0.05), sprite: Color(red: 0.78, green: 0.8, blue: 1.0))
        }
    }
}

/// The sky behind the seed bar and the meter.
struct LDBackdrop: View, Equatable {
    let scene: LDScene

    var body: some View {
        Canvas { ctx, s in
            let look = LDLook.of(scene)
            ctx.fill(Path(CGRect(origin: .zero, size: s)), with: .linearGradient(Gradient(colors: [look.skyTop, look.skyBottom]),
                                                                                 startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height)))
            switch scene {
            case .backyard:
                LDLawnArt.clouds(ctx, s, alpha: 0.6)
                LDLawnArt.hedge(ctx, s, Color(red: 0.16, green: 0.42, blue: 0.14))
            case .desert:
                ctx.fill(LDLawnArt.disc(CGPoint(x: s.width * 0.82, y: s.height * 0.06), 26), with: .color(Color(red: 1, green: 0.97, blue: 0.8).opacity(0.9)))
                var dunes = Path()
                dunes.move(to: CGPoint(x: 0, y: s.height))
                dunes.addLine(to: CGPoint(x: 0, y: s.height - 40))
                dunes.addQuadCurve(to: CGPoint(x: s.width * 0.45, y: s.height - 30), control: CGPoint(x: s.width * 0.2, y: s.height - 62))
                dunes.addQuadCurve(to: CGPoint(x: s.width, y: s.height - 44), control: CGPoint(x: s.width * 0.75, y: s.height - 6))
                dunes.addLine(to: CGPoint(x: s.width, y: s.height))
                ctx.fill(dunes, with: .color(Color(red: 0.86, green: 0.68, blue: 0.42)))
            case .pirate:
                LDLawnArt.clouds(ctx, s, alpha: 0.7)
                var sea = Path(CGRect(x: 0, y: s.height - 44, width: s.width, height: 44))
                sea.addRect(CGRect(x: 0, y: s.height - 44, width: s.width, height: 44))
                ctx.fill(sea, with: .linearGradient(Gradient(colors: [Color(red: 0.12, green: 0.45, blue: 0.68), Color(red: 0.05, green: 0.25, blue: 0.45)]),
                                                    startPoint: CGPoint(x: 0, y: s.height - 44), endPoint: CGPoint(x: 0, y: s.height)))
                LDLawnArt.waves(ctx, y: s.height - 40, width: s.width, color: .white.opacity(0.5))
            case .frontier:
                ctx.fill(LDLawnArt.disc(CGPoint(x: s.width * 0.2, y: s.height * 0.07), 22), with: .color(Color(red: 1, green: 0.85, blue: 0.5).opacity(0.85)))
                var scrub = Path(CGRect(x: 0, y: s.height - 30, width: s.width, height: 30))
                var x: CGFloat = 12
                while x < s.width { scrub.addEllipse(in: CGRect(x: x, y: s.height - 40, width: 22, height: 16)); x += 58 }
                ctx.fill(scrub, with: .color(Color(red: 0.5, green: 0.32, blue: 0.2)))
            case .glacier:
                LDLawnArt.icicles(ctx, width: s.width, top: 0, length: 26, color: Color(red: 0.75, green: 0.9, blue: 1).opacity(0.85))
                LDLawnArt.aurora(ctx, s)
                var snow = Path()
                var x: CGFloat = -10
                while x < s.width + 10 { snow.addEllipse(in: CGRect(x: x, y: s.height - 40, width: 60, height: 40)); x += 44 }
                snow.addRect(CGRect(x: 0, y: s.height - 22, width: s.width, height: 22))
                ctx.fill(snow, with: .color(Color(red: 0.92, green: 0.97, blue: 1)))
            case .future:
                LDLawnArt.stars(ctx, s, count: 30, alpha: 0.6)
                LDLawnArt.skyline(ctx, s, base: s.height, height: 46, color: Color(red: 0.12, green: 0.06, blue: 0.24), lights: Color(red: 0.3, green: 1, blue: 1))
            case .rooftop:
                LDLawnArt.stars(ctx, s, count: 46, alpha: 0.8)
                // A crescent moon.
                let m = CGPoint(x: s.width * 0.14, y: s.height * 0.06)
                var moon = Path(ellipseIn: CGRect(x: m.x - 18, y: m.y - 18, width: 36, height: 36))
                moon = moon.subtracting(Path(ellipseIn: CGRect(x: m.x - 9, y: m.y - 22, width: 36, height: 36)))
                ctx.fill(moon, with: .color(Color(red: 1, green: 0.97, blue: 0.85)))
                LDLawnArt.skyline(ctx, s, base: s.height, height: 34, color: Color(red: 0.08, green: 0.06, blue: 0.16), lights: Color(red: 1, green: 0.85, blue: 0.4))
            }
        }
        .allowsHitTesting(false)
    }
}

/// The lawn between the house (left) and the street (right), dressed for each world: tiles, the edge
/// along the top, the strip where the mowers wait, the way in on the right and the ground below.
struct LDLawn: View, Equatable {
    let size: CGSize
    let scene: LDScene
    let rowsInPlay: [Int]
    let shown: [Int]

    var body: some View {
        Canvas { ctx, s in
            let look = LDLook.of(scene)
            let lay = LDLayout(size: s, rows: shown)
            let cw = lay.cellW, ch = lay.cellH
            let top = lay.point(x: 0, y: Double(shown.first ?? 0)).y
            let bottom = top + ch * CGFloat(shown.count)
            let left = lay.origin.x - cw * 0.62, right = lay.origin.x + cw * 7.78
            let streetX = lay.origin.x + cw * 7
            let yard = CGRect(x: 0, y: bottom, width: s.width, height: max(0, s.height - bottom))
            // The ground below the lawn.
            ctx.fill(Path(yard), with: .linearGradient(Gradient(colors: [look.yardTop, look.yardBottom]),
                                                      startPoint: CGPoint(x: 0, y: yard.minY), endPoint: CGPoint(x: 0, y: yard.maxY)))
            LDLawnArt.yardDressing(ctx, scene: scene, yard: yard, left: left, right: right, cw: cw)
            // The edge along the top.
            LDLawnArt.topEdge(ctx, scene: scene, left: left, right: right, top: top, cw: cw)
            // The way in on the right.
            LDLawnArt.street(ctx, scene: scene, x: streetX, right: right, top: top - 2, bottom: max(bottom, s.height), cw: cw)
            // The strip on the house side where the mowers wait.
            LDLawnArt.patio(ctx, scene: scene, rect: CGRect(x: left, y: top, width: cw * 0.62, height: bottom - top), ch: ch)
            // The tiles.
            for r in shown {
                for c in 0..<LDWorld.cols {
                    let o = lay.point(x: Double(c), y: Double(r))
                    let tile = CGRect(x: o.x, y: o.y, width: cw + 0.5, height: ch + 0.5)
                    LDLawnArt.tile(ctx, scene: scene, look: look, rect: tile, row: r, col: c, inPlay: rowsInPlay.contains(r))
                }
            }
            // A soft shadow under the top edge.
            ctx.fill(Path(CGRect(x: lay.origin.x, y: top, width: cw * 7, height: 6)), with: .linearGradient(Gradient(colors: [.black.opacity(0.22), .clear]),
                                                                                                         startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: top + 6)))
        }
        .allowsHitTesting(false)
    }
}

/// The seed bar's background: planks, sandstone, ship's timber, ice or brushed metal.
struct LDSeedBar: View, Equatable {
    let scene: LDScene

    var body: some View {
        Canvas { ctx, s in
            let look = LDLook.of(scene)
            ctx.fill(Path(CGRect(origin: .zero, size: s)), with: .linearGradient(Gradient(colors: look.bar), startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height)))
            switch scene {
            case .desert:
                // Sandstone blocks.
                var joints = Path()
                for i in 1..<3 { joints.move(to: CGPoint(x: 0, y: s.height * CGFloat(i) / 3)); joints.addLine(to: CGPoint(x: s.width, y: s.height * CGFloat(i) / 3)) }
                for i in 0..<8 {
                    let row = i % 3
                    let x = s.width * (CGFloat(i) / 8 + (row == 1 ? 0.06 : 0))
                    joints.move(to: CGPoint(x: x, y: s.height * CGFloat(row) / 3)); joints.addLine(to: CGPoint(x: x, y: s.height * CGFloat(row + 1) / 3))
                }
                ctx.stroke(joints, with: .color(Color(red: 0.55, green: 0.4, blue: 0.2).opacity(0.45)), lineWidth: 1)
            case .future:
                var seams = Path()
                for i in 1..<4 { seams.move(to: CGPoint(x: s.width * CGFloat(i) / 4, y: 0)); seams.addLine(to: CGPoint(x: s.width * CGFloat(i) / 4, y: s.height)) }
                ctx.stroke(seams, with: .color(.black.opacity(0.25)), lineWidth: 1)
                var rivets = Path()
                for i in 0...4 { for y in [5.0, Double(s.height) - 5] { rivets.addEllipse(in: CGRect(x: s.width * CGFloat(i) / 4 - 2, y: y - 2, width: 4, height: 4)) } }
                ctx.fill(rivets, with: .color(.white.opacity(0.35)))
            case .glacier:
                var frost = Path()
                for i in 0..<9 {
                    let x = s.width * CGFloat(LDLawnArt.hash(Double(i) * 3.7)), y = s.height * CGFloat(LDLawnArt.hash(Double(i) * 5.3))
                    frost.move(to: CGPoint(x: x - 4, y: y)); frost.addLine(to: CGPoint(x: x + 4, y: y))
                    frost.move(to: CGPoint(x: x, y: y - 4)); frost.addLine(to: CGPoint(x: x, y: y + 4))
                }
                ctx.stroke(frost, with: .color(.white.opacity(0.5)), lineWidth: 1)
                LDLawnArt.icicles(ctx, width: s.width, top: s.height - 1, length: -6, color: .white.opacity(0.4))
            default:
                // Wood grain (with brass bolts on the ship).
                var grain = Path()
                for i in 0..<6 {
                    let y = s.height * CGFloat(i + 1) / 7
                    grain.move(to: CGPoint(x: 0, y: y))
                    grain.addCurve(to: CGPoint(x: s.width, y: y + 3), control1: CGPoint(x: s.width * 0.3, y: y - 4), control2: CGPoint(x: s.width * 0.7, y: y + 5))
                }
                ctx.stroke(grain, with: .color(Color(red: 0.2, green: 0.1, blue: 0.04).opacity(0.3)), lineWidth: 1)
                if scene == .pirate {
                    var bolts = Path()
                    for i in 0...6 { for y in [6.0, Double(s.height) - 6] { bolts.addEllipse(in: CGRect(x: s.width * CGFloat(i) / 6 - 2.5, y: y - 2.5, width: 5, height: 5)) } }
                    ctx.fill(bolts, with: .color(Color(red: 0.85, green: 0.68, blue: 0.3)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// A seed packet: the plant on a pale card with its price; greyed while it recharges or can't be afforded.
struct LDPacketFace: View {
    let kind: LDPlantKind
    let cost: Int
    let ready: Bool
    let charge: Double
    let picked: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.95, blue: 0.8), Color(red: 0.88, green: 0.82, blue: 0.62)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: 0.62, green: 0.82, blue: 0.5))
                .padding(.horizontal, 4).padding(.top, 4).padding(.bottom, 16)
            Canvas { ctx, s in
                let b = CGPoint(x: s.width / 2, y: s.height * 0.95)
                LDLawnArt.plantIcon(ctx, kind: kind, base: b, s: min(s.width, s.height) * 0.95)
            }
            .padding(.horizontal, 4).padding(.top, 4).padding(.bottom, 16)
            VStack {
                Spacer()
                Text(verbatim: String(cost))
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.2, green: 0.12, blue: 0.04))
                    .padding(.bottom, 1)
            }
            if !ready {
                GeometryReader { g in
                    VStack(spacing: 0) {
                        Color.black.opacity(0.5).frame(height: g.size.height * CGFloat(min(1, max(0, charge))))
                        Color.black.opacity(0.28)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            RoundedRectangle(cornerRadius: 6)
                .stroke(picked ? BananaTheme.banana : Color(red: 0.2, green: 0.36, blue: 0.1), lineWidth: picked ? 3 : 2)
        }
        .scaleEffect(picked ? 1.06 : 1)
        .offset(y: picked ? -2 : 0)
    }
}

struct LDPacketStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

// MARK: - Art

enum LDLawnArt {
    static let ink = Color(red: 0.12, green: 0.1, blue: 0.06)
    static let leaf = Color(red: 0.36, green: 0.72, blue: 0.16)
    static let leafDark = Color(red: 0.16, green: 0.42, blue: 0.08)

    static func hash(_ n: Double) -> Double {
        let v = sin(n * 12.9898) * 43758.5453
        return v - floor(v)
    }

    static func disc(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    static func oval(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2))
    }

    static func barEdge(_ s: LDScene) -> Color { LDLook.of(s).barEdge }

    // MARK: Backdrop pieces

    static func clouds(_ ctx: GraphicsContext, _ s: CGSize, alpha: Double) {
        var clouds = Path()
        for i in 0..<4 {
            let x = CGFloat(hash(Double(i) * 5.7)) * s.width, y = 20 + CGFloat(hash(Double(i) * 2.9)) * s.height * 0.25
            for k in 0..<3 { clouds.addEllipse(in: CGRect(x: x + CGFloat(k) * 18 - 18, y: y - CGFloat(k == 1 ? 10 : 4), width: 34, height: 22)) }
        }
        ctx.fill(clouds, with: .color(.white.opacity(alpha)))
    }

    static func hedge(_ ctx: GraphicsContext, _ s: CGSize, _ color: Color) {
        var hedge = Path()
        var x: CGFloat = -10
        while x < s.width + 10 { hedge.addEllipse(in: CGRect(x: x, y: s.height - 46, width: 46, height: 40)); x += 30 }
        hedge.addRect(CGRect(x: 0, y: s.height - 26, width: s.width, height: 26))
        ctx.fill(hedge, with: .color(color))
    }

    static func stars(_ ctx: GraphicsContext, _ s: CGSize, count: Int, alpha: Double) {
        var stars = Path()
        for i in 0..<count {
            let x = CGFloat(hash(Double(i) * 3.3)) * s.width, y = CGFloat(hash(Double(i) * 7.1)) * s.height * 0.5
            let r: CGFloat = i % 5 == 0 ? 2.2 : 1.5
            stars.addEllipse(in: CGRect(x: x, y: y, width: r, height: r))
        }
        ctx.fill(stars, with: .color(.white.opacity(alpha)))
    }

    static func waves(_ ctx: GraphicsContext, y: CGFloat, width: CGFloat, color: Color) {
        var w = Path()
        var x: CGFloat = 4
        while x < width {
            w.move(to: CGPoint(x: x, y: y)); w.addQuadCurve(to: CGPoint(x: x + 14, y: y), control: CGPoint(x: x + 7, y: y - 5))
            x += 26
        }
        ctx.stroke(w, with: .color(color), lineWidth: 1.5)
    }

    static func icicles(_ ctx: GraphicsContext, width: CGFloat, top: CGFloat, length: CGFloat, color: Color) {
        var ice = Path()
        var x: CGFloat = 0
        var i = 0.0
        while x < width {
            let w: CGFloat = 8 + CGFloat(hash(i)) * 8
            let l = length * (0.5 + CGFloat(hash(i + 0.5)))
            ice.move(to: CGPoint(x: x, y: top)); ice.addLine(to: CGPoint(x: x + w / 2, y: top + l)); ice.addLine(to: CGPoint(x: x + w, y: top))
            ice.closeSubpath()
            x += w + 2; i += 1
        }
        ctx.fill(ice, with: .color(color))
    }

    static func aurora(_ ctx: GraphicsContext, _ s: CGSize) {
        for (k, col) in [Color(red: 0.3, green: 1, blue: 0.7), Color(red: 0.5, green: 0.7, blue: 1)].enumerated() {
            var band = Path()
            let y = s.height * (0.08 + CGFloat(k) * 0.06)
            band.move(to: CGPoint(x: -10, y: y))
            band.addCurve(to: CGPoint(x: s.width + 10, y: y + 10), control1: CGPoint(x: s.width * 0.3, y: y - 26), control2: CGPoint(x: s.width * 0.6, y: y + 34))
            ctx.stroke(band, with: .color(col.opacity(0.3)), style: StrokeStyle(lineWidth: 12, lineCap: .round))
        }
    }

    static func skyline(_ ctx: GraphicsContext, _ s: CGSize, base: CGFloat, height: CGFloat, color: Color, lights: Color) {
        var towers = Path()
        var windows = Path()
        var x: CGFloat = -4
        var i = 0.0
        while x < s.width {
            let w: CGFloat = 14 + CGFloat(hash(i * 1.7)) * 16
            let h = height * (0.45 + CGFloat(hash(i * 2.3)) * 0.55)
            towers.addRect(CGRect(x: x, y: base - h, width: w, height: h))
            var wy = base - h + 5
            while wy < base - 4 {
                if hash(i * 9.1 + Double(wy)) > 0.55 { windows.addRect(CGRect(x: x + 3, y: wy, width: 2.5, height: 2.5)) }
                if hash(i * 4.3 + Double(wy)) > 0.6 { windows.addRect(CGRect(x: x + w - 6, y: wy, width: 2.5, height: 2.5)) }
                wy += 6
            }
            x += w + 2; i += 1
        }
        ctx.fill(towers, with: .color(color))
        ctx.fill(windows, with: .color(lights.opacity(0.8)))
    }

    // MARK: Lawn pieces

    static func tile(_ ctx: GraphicsContext, scene: LDScene, look: LDLook, rect o: CGRect, row r: Int, col c: Int, inPlay: Bool) {
        let light = (r + c) % 2 == 0
        guard inPlay else {
            ctx.fill(Path(o), with: .color(look.tileDark.mix(with: .black, by: 0.35)))
            return
        }
        ctx.fill(Path(o), with: .color(light ? look.tileLight : look.tileDark))
        let seed = Double(r * 31 + c * 7)
        switch scene {
        case .backyard:
            var blades = Path()
            for b in 0..<5 {
                let bx = o.minX + o.width * CGFloat(hash(seed + Double(b))), by = o.minY + o.height * CGFloat(hash(Double(r * 13 + c * 17 + b) + 0.5))
                blades.move(to: CGPoint(x: bx, y: by)); blades.addLine(to: CGPoint(x: bx - 1.5, y: by - 5))
                blades.move(to: CGPoint(x: bx, y: by)); blades.addLine(to: CGPoint(x: bx + 1.5, y: by - 5))
            }
            ctx.stroke(blades, with: .color(look.tileMark.opacity(0.55)), lineWidth: 1)
        case .rooftop:
            // Staggered rows of slates, each with a shadowed lower edge.
            var edges = Path()
            var joints = Path()
            let rowsN = 3
            for k in 0..<rowsN {
                let y0 = o.minY + o.height * CGFloat(k) / CGFloat(rowsN)
                let y1 = o.minY + o.height * CGFloat(k + 1) / CGFloat(rowsN)
                edges.addRect(CGRect(x: o.minX, y: y1 - 2.5, width: o.width, height: 2.5))
                let w = o.width / 3
                var x = o.minX + (k % 2 == 0 ? w * 0.5 : w)
                while x < o.maxX - 2 { joints.move(to: CGPoint(x: x, y: y0)); joints.addLine(to: CGPoint(x: x, y: y1)); x += w }
            }
            ctx.fill(edges, with: .color(look.tileMark.opacity(0.55)))
            ctx.stroke(joints, with: .color(look.tileMark.opacity(0.7)), lineWidth: 1)
        case .pirate:
            // Deck planks running bow to stern (across the lanes), with butt joints and nail heads.
            var seams = Path()
            var nails = Path()
            let n = 4
            for k in 1..<n {
                let x = o.minX + o.width * CGFloat(k) / CGFloat(n)
                seams.move(to: CGPoint(x: x, y: o.minY)); seams.addLine(to: CGPoint(x: x, y: o.maxY))
            }
            for k in 0..<n {
                let x0 = o.minX + o.width * CGFloat(k) / CGFloat(n)
                let jy = o.minY + o.height * CGFloat(0.2 + 0.6 * hash(seed + Double(k) * 1.3))
                seams.move(to: CGPoint(x: x0, y: jy)); seams.addLine(to: CGPoint(x: x0 + o.width / CGFloat(n), y: jy))
                let nx = x0 + o.width / CGFloat(n) / 2
                nails.addEllipse(in: CGRect(x: nx - 1, y: jy - 4, width: 2, height: 2))
                nails.addEllipse(in: CGRect(x: nx - 1, y: jy + 2, width: 2, height: 2))
            }
            ctx.stroke(seams, with: .color(look.tileMark.opacity(0.55)), lineWidth: 1)
            ctx.fill(nails, with: .color(look.tileMark.opacity(0.8)))
        case .desert:
            var cracks = Path()
            let x = o.minX + o.width * CGFloat(hash(seed + 0.3)), y = o.minY + o.height * CGFloat(hash(seed + 0.7))
            cracks.move(to: CGPoint(x: x, y: y)); cracks.addLine(to: CGPoint(x: x + 6, y: y + 4)); cracks.addLine(to: CGPoint(x: x + 9, y: y + 2))
            ctx.stroke(cracks, with: .color(look.tileMark.opacity(0.5)), lineWidth: 1)
            var pebbles = Path()
            for b in 0..<3 {
                let px = o.minX + o.width * CGFloat(hash(seed + Double(b) * 1.9)), py = o.minY + o.height * CGFloat(hash(seed + Double(b) * 2.3 + 0.4))
                pebbles.addEllipse(in: CGRect(x: px, y: py, width: 3.5, height: 2.5))
            }
            ctx.fill(pebbles, with: .color(look.tileMark.opacity(0.45)))
        case .frontier:
            var tufts = Path()
            for b in 0..<3 {
                let bx = o.minX + o.width * CGFloat(hash(seed + Double(b))), by = o.minY + o.height * CGFloat(hash(Double(r * 13 + c * 17 + b) + 0.5))
                tufts.move(to: CGPoint(x: bx, y: by)); tufts.addLine(to: CGPoint(x: bx - 2, y: by - 5))
                tufts.move(to: CGPoint(x: bx, y: by)); tufts.addLine(to: CGPoint(x: bx + 2, y: by - 4))
                tufts.move(to: CGPoint(x: bx, y: by)); tufts.addLine(to: CGPoint(x: bx, y: by - 6))
            }
            ctx.stroke(tufts, with: .color(look.tileMark.opacity(0.55)), lineWidth: 1)
        case .glacier:
            var sparkle = Path()
            for b in 0..<2 {
                let x = o.minX + o.width * CGFloat(hash(seed + Double(b) * 3.1)), y = o.minY + o.height * CGFloat(hash(seed + Double(b) * 1.7 + 0.2))
                sparkle.move(to: CGPoint(x: x - 3, y: y)); sparkle.addLine(to: CGPoint(x: x + 3, y: y))
                sparkle.move(to: CGPoint(x: x, y: y - 3)); sparkle.addLine(to: CGPoint(x: x, y: y + 3))
            }
            ctx.stroke(sparkle, with: .color(.white), lineWidth: 1)
            var crack = Path()
            let x = o.minX + o.width * CGFloat(hash(seed + 0.9)), y = o.minY + o.height * CGFloat(hash(seed + 0.1))
            crack.move(to: CGPoint(x: x, y: y)); crack.addLine(to: CGPoint(x: x + 8, y: y + 6)); crack.addLine(to: CGPoint(x: x + 5, y: y + 12))
            ctx.stroke(crack, with: .color(look.tileMark.opacity(0.6)), lineWidth: 1)
        case .future:
            // Panel seams that glow, and corner bolts.
            let inset = o.insetBy(dx: 2.5, dy: 2.5)
            ctx.stroke(Path(roundedRect: inset, cornerRadius: 3), with: .color(look.tileMark.opacity(light ? 0.35 : 0.22)), lineWidth: 1)
            var bolts = Path()
            for p in [CGPoint(x: inset.minX + 4, y: inset.minY + 4), CGPoint(x: inset.maxX - 4, y: inset.minY + 4),
                      CGPoint(x: inset.minX + 4, y: inset.maxY - 4), CGPoint(x: inset.maxX - 4, y: inset.maxY - 4)] {
                bolts.addEllipse(in: CGRect(x: p.x - 1.2, y: p.y - 1.2, width: 2.4, height: 2.4))
            }
            ctx.fill(bolts, with: .color(.white.opacity(0.3)))
        }
    }

    static func topEdge(_ ctx: GraphicsContext, scene: LDScene, left: CGFloat, right: CGFloat, top: CGFloat, cw: CGFloat) {
        switch scene {
        case .backyard, .rooftop:
            if scene == .rooftop {
                // The roof ridge and a chimney.
                let ridge = CGRect(x: left, y: top - cw * 0.3, width: right - left, height: cw * 0.3)
                ctx.fill(Path(ridge), with: .color(Color(red: 0.22, green: 0.18, blue: 0.34)))
                ctx.fill(Path(CGRect(x: left, y: top - cw * 0.33, width: right - left, height: cw * 0.06)), with: .color(Color(red: 0.4, green: 0.35, blue: 0.55)))
                let chim = CGRect(x: left + (right - left) * 0.62, y: top - cw * 0.85, width: cw * 0.55, height: cw * 0.6)
                ctx.fill(Path(chim), with: .color(Color(red: 0.45, green: 0.22, blue: 0.18)))
                var bricks = Path()
                for k in 1..<4 { bricks.move(to: CGPoint(x: chim.minX, y: chim.minY + chim.height * CGFloat(k) / 4)); bricks.addLine(to: CGPoint(x: chim.maxX, y: chim.minY + chim.height * CGFloat(k) / 4)) }
                ctx.stroke(bricks, with: .color(.black.opacity(0.3)), lineWidth: 1)
                ctx.fill(Path(CGRect(x: chim.minX - 3, y: chim.minY - 4, width: chim.width + 6, height: 5)), with: .color(Color(red: 0.3, green: 0.16, blue: 0.14)))
                return
            }
            // Picket fence.
            let fenceTop = top - cw * 0.55
            var pickets = Path()
            var px = left
            while px < right {
                var p = Path()
                p.move(to: CGPoint(x: px, y: top)); p.addLine(to: CGPoint(x: px, y: fenceTop + 6)); p.addLine(to: CGPoint(x: px + cw * 0.12, y: fenceTop))
                p.addLine(to: CGPoint(x: px + cw * 0.24, y: fenceTop + 6)); p.addLine(to: CGPoint(x: px + cw * 0.24, y: top)); p.closeSubpath()
                pickets.addPath(p)
                px += cw * 0.34
            }
            ctx.fill(pickets, with: .color(Color(red: 0.97, green: 0.95, blue: 0.9)))
            ctx.stroke(pickets, with: .color(Color(red: 0.6, green: 0.55, blue: 0.48)), lineWidth: 1)
            ctx.fill(Path(CGRect(x: left, y: fenceTop + cw * 0.22, width: right - left, height: cw * 0.08)), with: .color(Color(red: 0.88, green: 0.85, blue: 0.78)))
        case .desert:
            // A low sandstone wall with a carved band.
            let wall = CGRect(x: left, y: top - cw * 0.5, width: right - left, height: cw * 0.5)
            ctx.fill(Path(wall), with: .color(Color(red: 0.88, green: 0.72, blue: 0.48)))
            var joints = Path()
            joints.move(to: CGPoint(x: left, y: wall.midY)); joints.addLine(to: CGPoint(x: right, y: wall.midY))
            var x = left
            var k = 0
            while x < right { joints.move(to: CGPoint(x: x, y: k % 2 == 0 ? wall.minY : wall.midY)); joints.addLine(to: CGPoint(x: x, y: k % 2 == 0 ? wall.midY : wall.maxY)); x += cw * 0.7; k += 1 }
            ctx.stroke(joints, with: .color(Color(red: 0.6, green: 0.44, blue: 0.24)), lineWidth: 1)
            var glyphs = Path()
            x = left + cw * 0.3
            var g = 0
            while x < right - cw * 0.2 {
                let y = wall.minY + wall.height * 0.25
                switch g % 3 {
                case 0: glyphs.addEllipse(in: CGRect(x: x - 3, y: y - 2, width: 6, height: 4))
                case 1: glyphs.move(to: CGPoint(x: x - 3, y: y + 2)); glyphs.addLine(to: CGPoint(x: x, y: y - 3)); glyphs.addLine(to: CGPoint(x: x + 3, y: y + 2))
                default: glyphs.move(to: CGPoint(x: x - 3, y: y)); glyphs.addQuadCurve(to: CGPoint(x: x + 3, y: y), control: CGPoint(x: x, y: y - 5))
                }
                x += cw * 0.36; g += 1
            }
            ctx.stroke(glyphs, with: .color(Color(red: 0.5, green: 0.34, blue: 0.16)), lineWidth: 1.2)
            ctx.fill(Path(CGRect(x: left, y: wall.minY - 2, width: right - left, height: 3)), with: .color(Color(red: 0.95, green: 0.82, blue: 0.58)))
        case .pirate:
            // The ship's rail: balusters under a heavy top rail, a coil of rope.
            let railY = top - cw * 0.5
            var posts = Path()
            var x = left + 2
            while x < right { posts.addRoundedRect(in: CGRect(x: x, y: railY + 4, width: cw * 0.12, height: top - railY - 4), cornerSize: CGSize(width: 3, height: 3)); x += cw * 0.3 }
            ctx.fill(posts, with: .color(Color(red: 0.5, green: 0.3, blue: 0.15)))
            ctx.stroke(posts, with: .color(Color(red: 0.25, green: 0.13, blue: 0.05)), lineWidth: 1)
            let rail = CGRect(x: left, y: railY, width: right - left, height: cw * 0.13)
            ctx.fill(Path(roundedRect: rail, cornerRadius: 3), with: .color(Color(red: 0.42, green: 0.24, blue: 0.11)))
            ctx.stroke(Path(roundedRect: rail, cornerRadius: 3), with: .color(Color(red: 0.2, green: 0.1, blue: 0.04)), lineWidth: 1)
            var rope = Path()
            rope.move(to: CGPoint(x: left, y: railY + cw * 0.2))
            var rx = left
            while rx < right { rope.addQuadCurve(to: CGPoint(x: rx + cw * 0.9, y: railY + cw * 0.2), control: CGPoint(x: rx + cw * 0.45, y: railY + cw * 0.38)); rx += cw * 0.9 }
            ctx.stroke(rope, with: .color(Color(red: 0.85, green: 0.72, blue: 0.45)), lineWidth: 2)
        case .frontier:
            // A ranch fence: posts and two rails.
            let fenceTop = top - cw * 0.5
            var rails = Path()
            for y in [fenceTop + cw * 0.08, fenceTop + cw * 0.28] { rails.addRect(CGRect(x: left, y: y, width: right - left, height: cw * 0.08)) }
            var posts = Path()
            var x = left + 3
            while x < right { posts.addRect(CGRect(x: x, y: fenceTop, width: cw * 0.1, height: top - fenceTop)); x += cw * 1.1 }
            ctx.fill(rails, with: .color(Color(red: 0.6, green: 0.42, blue: 0.25)))
            ctx.fill(posts, with: .color(Color(red: 0.48, green: 0.32, blue: 0.18)))
            ctx.stroke(rails, with: .color(Color(red: 0.3, green: 0.18, blue: 0.08)), lineWidth: 0.8)
            ctx.stroke(posts, with: .color(Color(red: 0.3, green: 0.18, blue: 0.08)), lineWidth: 0.8)
        case .glacier:
            // Ice blocks.
            let wall = CGRect(x: left, y: top - cw * 0.5, width: right - left, height: cw * 0.5)
            ctx.fill(Path(wall), with: .linearGradient(Gradient(colors: [Color(red: 0.8, green: 0.93, blue: 1), Color(red: 0.6, green: 0.8, blue: 0.95)]),
                                                      startPoint: CGPoint(x: 0, y: wall.minY), endPoint: CGPoint(x: 0, y: wall.maxY)))
            var joints = Path()
            var x = left
            while x < right { joints.move(to: CGPoint(x: x, y: wall.minY)); joints.addLine(to: CGPoint(x: x, y: wall.maxY)); x += cw * 0.8 }
            joints.move(to: CGPoint(x: left, y: wall.midY)); joints.addLine(to: CGPoint(x: right, y: wall.midY))
            ctx.stroke(joints, with: .color(.white.opacity(0.8)), lineWidth: 1)
            icicles(ctx, width: right - left, top: wall.maxY, length: 7, color: Color(red: 0.85, green: 0.95, blue: 1))
        case .future:
            // A force-field rail between glowing posts.
            let y = top - cw * 0.4
            ctx.stroke(Path { p in p.move(to: CGPoint(x: left, y: y)); p.addLine(to: CGPoint(x: right, y: y)) },
                       with: .color(Color(red: 0.2, green: 0.95, blue: 0.95).opacity(0.85)), lineWidth: 2)
            ctx.stroke(Path { p in p.move(to: CGPoint(x: left, y: y + cw * 0.18)); p.addLine(to: CGPoint(x: right, y: y + cw * 0.18)) },
                       with: .color(Color(red: 1, green: 0.3, blue: 0.85).opacity(0.6)), lineWidth: 1.5)
            var posts = Path()
            var x = left + 2
            while x < right { posts.addRoundedRect(in: CGRect(x: x, y: y - cw * 0.08, width: cw * 0.1, height: top - y + cw * 0.08), cornerSize: CGSize(width: 2, height: 2)); x += cw * 1.2 }
            ctx.fill(posts, with: .color(Color(red: 0.5, green: 0.55, blue: 0.65)))
        }
    }

    static func street(_ ctx: GraphicsContext, scene: LDScene, x: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat, cw: CGFloat) {
        let w = max(0, right - x)
        switch scene {
        case .backyard, .rooftop:
            if scene == .rooftop {
                ctx.fill(Path(CGRect(x: x, y: top, width: w, height: bottom - top)), with: .color(Color(red: 0.16, green: 0.14, blue: 0.26)))
                ctx.fill(Path(CGRect(x: x, y: top, width: cw * 0.12, height: bottom - top)), with: .color(Color(red: 0.45, green: 0.4, blue: 0.6)))
                return
            }
            ctx.fill(Path(CGRect(x: x, y: top, width: cw * 0.3, height: bottom - top)), with: .color(Color(white: 0.8)))
            ctx.fill(Path(CGRect(x: x + cw * 0.3, y: top, width: max(0, w - cw * 0.3), height: bottom - top)), with: .color(Color(white: 0.35)))
        case .desert:
            ctx.fill(Path(CGRect(x: x, y: top, width: w, height: bottom - top)), with: .color(Color(red: 0.8, green: 0.64, blue: 0.4)))
            ctx.fill(Path(CGRect(x: x, y: top, width: cw * 0.1, height: bottom - top)), with: .color(Color(red: 0.66, green: 0.5, blue: 0.28)))
        case .pirate:
            // The deck ends; beyond it the sea.
            ctx.fill(Path(CGRect(x: x, y: top, width: w, height: bottom - top)), with: .linearGradient(Gradient(colors: [Color(red: 0.12, green: 0.45, blue: 0.68), Color(red: 0.06, green: 0.3, blue: 0.5)]),
                                                                                                      startPoint: CGPoint(x: x, y: 0), endPoint: CGPoint(x: x + w, y: 0)))
            var y = top + 10
            var foam = Path()
            while y < bottom { foam.move(to: CGPoint(x: x + 4, y: y)); foam.addQuadCurve(to: CGPoint(x: x + w - 2, y: y), control: CGPoint(x: x + w / 2, y: y - 4)); y += 22 }
            ctx.stroke(foam, with: .color(.white.opacity(0.45)), lineWidth: 1.2)
            ctx.fill(Path(CGRect(x: x, y: top, width: cw * 0.12, height: bottom - top)), with: .color(Color(red: 0.3, green: 0.17, blue: 0.08)))
        case .frontier:
            // Railroad tracks.
            ctx.fill(Path(CGRect(x: x, y: top, width: w, height: bottom - top)), with: .color(Color(red: 0.62, green: 0.48, blue: 0.32)))
            var ties = Path()
            var y = top + 4
            while y < bottom { ties.addRect(CGRect(x: x + 1, y: y, width: w - 2, height: 5)); y += 14 }
            ctx.fill(ties, with: .color(Color(red: 0.4, green: 0.26, blue: 0.14)))
            for rx in [x + w * 0.28, x + w * 0.72] { ctx.fill(Path(CGRect(x: rx - 1.5, y: top, width: 3, height: bottom - top)), with: .color(Color(white: 0.55))) }
        case .glacier:
            ctx.fill(Path(CGRect(x: x, y: top, width: w, height: bottom - top)), with: .color(Color(red: 0.7, green: 0.84, blue: 0.95)))
            ctx.fill(Path(CGRect(x: x, y: top, width: cw * 0.1, height: bottom - top)), with: .color(.white))
        case .future:
            ctx.fill(Path(CGRect(x: x, y: top, width: w, height: bottom - top)), with: .color(Color(red: 0.1, green: 0.08, blue: 0.2)))
            var dashes = Path()
            var y = top + 6
            while y < bottom { dashes.addRect(CGRect(x: x + w / 2 - 1.5, y: y, width: 3, height: 9)); y += 18 }
            ctx.fill(dashes, with: .color(Color(red: 1, green: 0.3, blue: 0.85).opacity(0.8)))
            ctx.fill(Path(CGRect(x: x, y: top, width: 2, height: bottom - top)), with: .color(Color(red: 0.2, green: 0.95, blue: 0.95)))
        }
    }

    static func patio(_ ctx: GraphicsContext, scene: LDScene, rect patio: CGRect, ch: CGFloat) {
        let (fill, line): (Color, Color)
        switch scene {
        case .backyard: (fill, line) = (Color(red: 0.78, green: 0.72, blue: 0.6), Color(red: 0.6, green: 0.54, blue: 0.44))
        case .desert: (fill, line) = (Color(red: 0.82, green: 0.66, blue: 0.42), Color(red: 0.6, green: 0.45, blue: 0.25))
        case .pirate: (fill, line) = (Color(red: 0.45, green: 0.27, blue: 0.13), Color(red: 0.25, green: 0.13, blue: 0.05))
        case .frontier: (fill, line) = (Color(red: 0.62, green: 0.45, blue: 0.28), Color(red: 0.4, green: 0.27, blue: 0.14))
        case .glacier: (fill, line) = (Color(red: 0.78, green: 0.9, blue: 1), Color(red: 0.55, green: 0.72, blue: 0.9))
        case .future: (fill, line) = (Color(red: 0.36, green: 0.4, blue: 0.52), Color(red: 0.2, green: 0.95, blue: 0.95))
        case .rooftop: (fill, line) = (Color(red: 0.3, green: 0.26, blue: 0.4), Color(red: 0.18, green: 0.15, blue: 0.26))
        }
        ctx.fill(Path(patio), with: .color(fill))
        var flags = Path()
        var y = patio.minY
        var k = 0
        while y < patio.maxY {
            flags.addRect(CGRect(x: patio.minX + (k % 2 == 0 ? 0 : patio.width * 0.4), y: y, width: patio.width * 0.6, height: ch * 0.33))
            y += ch * 0.33; k += 1
        }
        var stones = ctx
        stones.clip(to: Path(patio))
        stones.stroke(flags, with: .color(line.opacity(scene == .future ? 0.5 : 1)), lineWidth: 1)
    }

    static func yardDressing(_ ctx: GraphicsContext, scene: LDScene, yard: CGRect, left: CGFloat, right: CGFloat, cw: CGFloat) {
        guard yard.height > cw * 0.6 else { return }
        switch scene {
        case .backyard:
            var bushes = Path()
            var bx = left - cw * 0.3
            while bx < right { bushes.addEllipse(in: CGRect(x: bx, y: yard.minY + cw * 0.15, width: cw * 0.9, height: cw * 0.55)); bx += cw * 0.62 }
            ctx.fill(bushes, with: .color(Color(red: 0.18, green: 0.45, blue: 0.12)))
            var blooms = Path()
            for i in 0..<14 {
                let fx = left + (right - left) * CGFloat(hash(Double(i) * 4.3)), fy = yard.minY + cw * (0.2 + 0.4 * CGFloat(hash(Double(i) * 9.1)))
                blooms.addEllipse(in: CGRect(x: fx, y: fy, width: 5, height: 5))
            }
            ctx.fill(blooms, with: .color(Color(red: 1, green: 0.85, blue: 0.3)))
        case .desert:
            // Two little pyramids and a palm.
            for (i, px) in [left + cw * 1.2, left + cw * 2.6].enumerated() {
                let h = cw * (i == 0 ? 0.9 : 0.6)
                var pyr = Path()
                pyr.move(to: CGPoint(x: px - h, y: yard.minY + cw * 1.05)); pyr.addLine(to: CGPoint(x: px, y: yard.minY + cw * 1.05 - h)); pyr.addLine(to: CGPoint(x: px + h, y: yard.minY + cw * 1.05))
                pyr.closeSubpath()
                ctx.fill(pyr, with: .color(Color(red: 0.8, green: 0.6, blue: 0.34)))
                var shade = Path()
                shade.move(to: CGPoint(x: px, y: yard.minY + cw * 1.05 - h)); shade.addLine(to: CGPoint(x: px + h, y: yard.minY + cw * 1.05)); shade.addLine(to: CGPoint(x: px + h * 0.3, y: yard.minY + cw * 1.05))
                shade.closeSubpath()
                ctx.fill(shade, with: .color(Color(red: 0.62, green: 0.44, blue: 0.24)))
            }
            palm(ctx, base: CGPoint(x: right - cw * 1.4, y: yard.minY + cw * 1.2), h: cw * 1.0)
        case .pirate:
            waves(ctx, y: yard.minY + cw * 0.35, width: right + cw, color: .white.opacity(0.5))
            waves(ctx, y: yard.minY + cw * 0.85, width: right + cw, color: .white.opacity(0.35))
            // The ship's hull edge right under the deck.
            ctx.fill(Path(CGRect(x: 0, y: yard.minY, width: right, height: cw * 0.16)), with: .color(Color(red: 0.32, green: 0.18, blue: 0.08)))
            ctx.fill(Path(CGRect(x: 0, y: yard.minY + cw * 0.16, width: right, height: cw * 0.05)), with: .color(Color(red: 0.8, green: 0.62, blue: 0.25)))
        case .frontier:
            cactus(ctx, base: CGPoint(x: left + cw * 1.3, y: yard.minY + cw * 1.1), h: cw * 0.9)
            cactus(ctx, base: CGPoint(x: right - cw * 1.6, y: yard.minY + cw * 0.95), h: cw * 0.65)
            var rocks = Path()
            for i in 0..<5 {
                let rx = left + (right - left) * CGFloat(hash(Double(i) * 6.1)), ry = yard.minY + cw * (0.4 + 0.5 * CGFloat(hash(Double(i) * 2.2)))
                rocks.addEllipse(in: CGRect(x: rx, y: ry, width: 10, height: 6))
            }
            ctx.fill(rocks, with: .color(Color(red: 0.45, green: 0.3, blue: 0.2)))
        case .glacier:
            var drifts = Path()
            var x = left - cw * 0.4
            while x < right { drifts.addEllipse(in: CGRect(x: x, y: yard.minY + cw * 0.1, width: cw * 1.1, height: cw * 0.5)); x += cw * 0.8 }
            ctx.fill(drifts, with: .color(.white.opacity(0.8)))
        case .future:
            var grid = Path()
            var x = left
            while x < right { grid.move(to: CGPoint(x: x, y: yard.minY)); grid.addLine(to: CGPoint(x: x - cw * 0.4, y: yard.maxY)); x += cw * 0.8 }
            var y = yard.minY + cw * 0.3
            while y < yard.maxY { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: yard.maxX, y: y)); y += cw * 0.45 }
            ctx.stroke(grid, with: .color(Color(red: 1, green: 0.3, blue: 0.85).opacity(0.35)), lineWidth: 1)
        case .rooftop:
            // The eaves of the houses below.
            var eaves = Path()
            var x = left - cw * 0.5
            var i = 0.0
            while x < right {
                let w = cw * (1.2 + CGFloat(hash(i)) * 0.8)
                eaves.move(to: CGPoint(x: x, y: yard.minY + cw * 1.1)); eaves.addLine(to: CGPoint(x: x + w / 2, y: yard.minY + cw * 0.5)); eaves.addLine(to: CGPoint(x: x + w, y: yard.minY + cw * 1.1))
                eaves.closeSubpath()
                x += w * 0.8; i += 1
            }
            ctx.fill(eaves, with: .color(Color(red: 0.14, green: 0.11, blue: 0.24)))
        }
    }

    static func palm(_ ctx: GraphicsContext, base: CGPoint, h: CGFloat) {
        var trunk = Path()
        trunk.move(to: base); trunk.addQuadCurve(to: CGPoint(x: base.x + h * 0.15, y: base.y - h), control: CGPoint(x: base.x - h * 0.1, y: base.y - h * 0.5))
        ctx.stroke(trunk, with: .color(Color(red: 0.5, green: 0.34, blue: 0.18)), style: StrokeStyle(lineWidth: h * 0.09, lineCap: .round))
        let top = CGPoint(x: base.x + h * 0.15, y: base.y - h)
        var fronds = Path()
        for a in [-2.6, -2.0, -1.2, -0.6, 0.1] as [Double] {
            let tip = CGPoint(x: top.x + CGFloat(cos(a)) * h * 0.5, y: top.y + CGFloat(sin(a)) * h * 0.3 + h * 0.12)
            fronds.move(to: top); fronds.addQuadCurve(to: tip, control: CGPoint(x: (top.x + tip.x) / 2, y: top.y - h * 0.15))
        }
        ctx.stroke(fronds, with: .color(Color(red: 0.2, green: 0.5, blue: 0.18)), style: StrokeStyle(lineWidth: h * 0.08, lineCap: .round))
    }

    static func cactus(_ ctx: GraphicsContext, base: CGPoint, h: CGFloat) {
        let green = Color(red: 0.3, green: 0.55, blue: 0.25)
        var c = Path()
        c.addRoundedRect(in: CGRect(x: base.x - h * 0.1, y: base.y - h, width: h * 0.2, height: h), cornerSize: CGSize(width: h * 0.1, height: h * 0.1))
        c.addRoundedRect(in: CGRect(x: base.x - h * 0.34, y: base.y - h * 0.65, width: h * 0.12, height: h * 0.36), cornerSize: CGSize(width: h * 0.06, height: h * 0.06))
        c.addRect(CGRect(x: base.x - h * 0.3, y: base.y - h * 0.35, width: h * 0.25, height: h * 0.09))
        c.addRoundedRect(in: CGRect(x: base.x + h * 0.22, y: base.y - h * 0.8, width: h * 0.12, height: h * 0.4), cornerSize: CGSize(width: h * 0.06, height: h * 0.06))
        c.addRect(CGRect(x: base.x + h * 0.05, y: base.y - h * 0.47, width: h * 0.25, height: h * 0.09))
        ctx.fill(c, with: .color(green))
    }

    // MARK: Plants (anchored at the bottom centre of their tile, sized by the tile width)

    /// A plant as drawn in its seed packet.
    static func plantIcon(_ ctx: GraphicsContext, kind: LDPlantKind, base b: CGPoint, s: CGFloat) {
        switch kind {
        case .sunflower: sunflower(ctx, base: b, s: s, t: 0, seed: 0, wince: false)
        case .peashooter: peashooter(ctx, base: b, s: s, t: 0, seed: 0, recoil: 9)
        case .popper: popper(ctx, base: b, s: s, t: 0, seed: 0, recoil: 9)
        case .frost: frostBerry(ctx, base: b, s: s, t: 0, seed: 0, recoil: 9)
        case .lobber: lobber(ctx, base: b, s: s, t: 0, seed: 0, fired: 9)
        case .wallnut: wallnut(ctx, base: b, s: s, health: 1, wince: false)
        case .peel: peel(ctx, base: CGPoint(x: b.x, y: b.y - s * 0.06), s: s * 1.25, arm: 1, t: 0)
        case .flytrap: flytrap(ctx, base: b, s: s, t: 0, seed: 0, chewing: 0, gulp: -9)
        case .cherry: cherry(ctx, base: b, s: s, fuse: 0, t: 0)
        case .chili: chili(ctx, base: b, s: s, fuse: 0, t: 0)
        }
    }

    static func sunflower(_ ctx: GraphicsContext, base b: CGPoint, s: CGFloat, t: Double, seed: Double, wince: Bool) {
        let bob = CGFloat(sin(t * 2.4 + seed)) * s * 0.025
        let head = CGPoint(x: b.x + bob * 0.6, y: b.y - s * 0.7 + bob)
        var stem = Path()
        stem.move(to: b); stem.addQuadCurve(to: CGPoint(x: head.x, y: head.y + s * 0.2), control: CGPoint(x: b.x + s * 0.08, y: b.y - s * 0.3))
        ctx.stroke(stem, with: .color(leafDark), style: StrokeStyle(lineWidth: s * 0.11, lineCap: .round))
        ctx.stroke(stem, with: .color(leaf), style: StrokeStyle(lineWidth: s * 0.06, lineCap: .round))
        for side in [-1.0, 1.0] as [CGFloat] {
            var l = Path()
            let root = CGPoint(x: b.x, y: b.y - s * 0.12)
            l.move(to: root)
            l.addQuadCurve(to: CGPoint(x: root.x + side * s * 0.36, y: root.y - s * 0.1), control: CGPoint(x: root.x + side * s * 0.16, y: root.y - s * 0.24))
            l.addQuadCurve(to: root, control: CGPoint(x: root.x + side * s * 0.22, y: root.y + s * 0.06))
            ctx.fill(l, with: .color(leaf))
            ctx.stroke(l, with: .color(leafDark), lineWidth: 1.2)
        }
        var petals = Path()
        let pr = s * 0.38
        for k in 0..<13 {
            let a = Double(k) / 13 * 2 * .pi + sin(t * 1.3 + seed) * 0.05
            let c = CGPoint(x: head.x + CGFloat(cos(a)) * pr * 0.62, y: head.y + CGFloat(sin(a)) * pr * 0.62)
            var p = Path(ellipseIn: CGRect(x: -pr * 0.36, y: -pr * 0.17, width: pr * 0.72, height: pr * 0.34))
            p = p.applying(CGAffineTransform(rotationAngle: CGFloat(a)).concatenating(CGAffineTransform(translationX: c.x, y: c.y)))
            petals.addPath(p)
        }
        ctx.fill(petals, with: .color(Color(red: 1, green: 0.82, blue: 0.1)))
        ctx.stroke(petals, with: .color(Color(red: 0.85, green: 0.5, blue: 0.05)), lineWidth: 1)
        let fr = s * 0.21
        ctx.fill(disc(head, fr), with: .radialGradient(Gradient(colors: [Color(red: 0.72, green: 0.42, blue: 0.14), Color(red: 0.5, green: 0.27, blue: 0.08)]),
                                                     center: CGPoint(x: head.x - fr * 0.3, y: head.y - fr * 0.3), startRadius: 0, endRadius: fr * 1.3))
        ctx.stroke(disc(head, fr), with: .color(Color(red: 0.35, green: 0.18, blue: 0.05)), lineWidth: 1.2)
        for dx in [-0.38, 0.38] as [CGFloat] {
            let e = CGPoint(x: head.x + dx * fr, y: head.y - fr * 0.18)
            if wince {
                var shut = Path(); shut.move(to: CGPoint(x: e.x - fr * 0.14, y: e.y)); shut.addLine(to: CGPoint(x: e.x + fr * 0.14, y: e.y))
                ctx.stroke(shut, with: .color(ink), lineWidth: 1.5)
            } else {
                ctx.fill(oval(e, fr * 0.13, fr * 0.2), with: .color(ink))
                ctx.fill(disc(CGPoint(x: e.x - fr * 0.04, y: e.y - fr * 0.07), fr * 0.05), with: .color(.white))
            }
        }
        var smile = Path()
        smile.addArc(center: CGPoint(x: head.x, y: head.y + fr * 0.08), radius: fr * 0.42, startAngle: .degrees(25), endAngle: .degrees(155), clockwise: false)
        ctx.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
    }

    static func peashooter(_ ctx: GraphicsContext, base b: CGPoint, s: CGFloat, t: Double, seed: Double, recoil: Double) {
        let sway = CGFloat(sin(t * 2 + seed)) * s * 0.015
        let kick = CGFloat(max(0, 1 - recoil / 0.18))          // 1 right after a shot
        let head = CGPoint(x: b.x - s * 0.04 + sway - kick * s * 0.04, y: b.y - s * 0.6)
        let hr = s * 0.24
        var stem = Path()
        stem.move(to: b); stem.addQuadCurve(to: CGPoint(x: head.x, y: head.y + hr * 0.7), control: CGPoint(x: b.x - s * 0.06, y: b.y - s * 0.28))
        ctx.stroke(stem, with: .color(leafDark), style: StrokeStyle(lineWidth: s * 0.11, lineCap: .round))
        ctx.stroke(stem, with: .color(leaf), style: StrokeStyle(lineWidth: s * 0.06, lineCap: .round))
        for side in [-1.0, 1.0] as [CGFloat] {
            var l = Path()
            l.move(to: b)
            l.addQuadCurve(to: CGPoint(x: b.x + side * s * 0.4, y: b.y - s * 0.03), control: CGPoint(x: b.x + side * s * 0.2, y: b.y - s * 0.2))
            l.addQuadCurve(to: b, control: CGPoint(x: b.x + side * s * 0.26, y: b.y + s * 0.06))
            ctx.fill(l, with: .color(leaf))
            ctx.stroke(l, with: .color(leafDark), lineWidth: 1.2)
        }
        let bodyG = Gradient(colors: [Color(red: 0.7, green: 0.95, blue: 0.35), Color(red: 0.36, green: 0.74, blue: 0.14)])
        var tuft = Path()
        tuft.move(to: CGPoint(x: head.x - hr * 0.8, y: head.y - hr * 0.3))
        tuft.addQuadCurve(to: CGPoint(x: head.x - hr * 1.55, y: head.y - hr * 0.9), control: CGPoint(x: head.x - hr * 1.4, y: head.y - hr * 0.2))
        tuft.addQuadCurve(to: CGPoint(x: head.x - hr * 0.6, y: head.y - hr * 0.75), control: CGPoint(x: head.x - hr * 1.0, y: head.y - hr * 1.0))
        ctx.fill(tuft, with: .color(leaf)); ctx.stroke(tuft, with: .color(leafDark), lineWidth: 1.2)
        let snoutL = hr * (1.05 - kick * 0.2)
        let snout = CGRect(x: head.x + hr * 0.3, y: head.y - hr * 0.42, width: snoutL, height: hr * 0.84)
        ctx.fill(Path(roundedRect: snout, cornerRadius: hr * 0.3), with: .linearGradient(bodyG, startPoint: CGPoint(x: 0, y: snout.minY), endPoint: CGPoint(x: 0, y: snout.maxY)))
        ctx.stroke(Path(roundedRect: snout, cornerRadius: hr * 0.3), with: .color(leafDark), lineWidth: 1.4)
        let mouth = CGPoint(x: snout.maxX, y: snout.midY)
        ctx.fill(oval(mouth, hr * 0.2, hr * 0.48), with: .color(Color(red: 0.48, green: 0.82, blue: 0.2)))
        ctx.stroke(oval(mouth, hr * 0.2, hr * 0.48), with: .color(leafDark), lineWidth: 1.4)
        ctx.fill(oval(mouth, hr * 0.09, hr * 0.27), with: .color(Color(red: 0.08, green: 0.2, blue: 0.04)))
        ctx.fill(disc(head, hr), with: .radialGradient(bodyG, center: CGPoint(x: head.x - hr * 0.3, y: head.y - hr * 0.4), startRadius: 0, endRadius: hr * 1.5))
        ctx.stroke(disc(head, hr), with: .color(leafDark), lineWidth: 1.4)
        let eye = CGPoint(x: head.x + hr * 0.25, y: head.y - hr * 0.22)
        ctx.fill(oval(eye, hr * 0.24, hr * 0.3), with: .color(.white))
        ctx.fill(disc(CGPoint(x: eye.x + hr * 0.08, y: eye.y + hr * 0.02), hr * 0.15), with: .color(ink))
        ctx.fill(disc(CGPoint(x: eye.x + hr * 0.12, y: eye.y - hr * 0.05), hr * 0.05), with: .color(.white))
    }

    /// Two little round eyes looking right.
    static func eyes(_ ctx: GraphicsContext, at c: CGPoint, r: CGFloat, gap: CGFloat, blink: Bool = false) {
        for dx in [-gap / 2, gap / 2] {
            let e = CGPoint(x: c.x + dx, y: c.y)
            if blink {
                var shut = Path(); shut.move(to: CGPoint(x: e.x - r, y: e.y)); shut.addLine(to: CGPoint(x: e.x + r, y: e.y))
                ctx.stroke(shut, with: .color(ink), lineWidth: max(1.2, r * 0.4))
                continue
            }
            ctx.fill(oval(e, r, r * 1.2), with: .color(.white))
            ctx.stroke(oval(e, r, r * 1.2), with: .color(ink), lineWidth: 1)
            ctx.fill(disc(CGPoint(x: e.x + r * 0.35, y: e.y + r * 0.1), r * 0.55), with: .color(ink))
            ctx.fill(disc(CGPoint(x: e.x + r * 0.45, y: e.y - r * 0.2), r * 0.2), with: .color(.white))
        }
    }

    /// The corn popper: an ear of corn in its husk with a popcorn tuft; fires two popcorn puffs a shot.
    static func popper(_ ctx: GraphicsContext, base b: CGPoint, s: CGFloat, t: Double, seed: Double, recoil: Double) {
        let sway = CGFloat(sin(t * 2.2 + seed)) * s * 0.015
        let kick = CGFloat(max(0, 1 - recoil / 0.22))
        let c = CGPoint(x: b.x + sway - kick * s * 0.03, y: b.y - s * 0.5)
        let rx = s * 0.17 * (1 + 0.08 * kick), ry = s * 0.3 * (1 - 0.06 * kick)
        // Outer husk leaves.
        for side in [-1.0, 1.0] as [CGFloat] {
            var l = Path()
            l.move(to: CGPoint(x: b.x, y: b.y))
            l.addQuadCurve(to: CGPoint(x: b.x + side * s * 0.36, y: b.y - s * 0.44), control: CGPoint(x: b.x + side * s * 0.34, y: b.y - s * 0.08))
            l.addQuadCurve(to: CGPoint(x: b.x + side * s * 0.05, y: b.y - s * 0.12), control: CGPoint(x: b.x + side * s * 0.16, y: b.y - s * 0.28))
            l.closeSubpath()
            ctx.fill(l, with: .color(Color(red: 0.55, green: 0.78, blue: 0.3)))
            ctx.stroke(l, with: .color(leafDark), lineWidth: 1.2)
        }
        // The cob and its kernels.
        let cob = oval(c, rx, ry)
        ctx.fill(cob, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.88, blue: 0.3), Color(red: 0.96, green: 0.64, blue: 0.08)]),
                                           startPoint: CGPoint(x: c.x - rx, y: c.y), endPoint: CGPoint(x: c.x + rx, y: c.y)))
        var kernels = Path()
        for row in 0..<8 {
            let y = c.y - ry * 0.85 + CGFloat(row) * ry * 0.24
            for col in 0..<4 {
                let x = c.x - rx * 0.75 + CGFloat(col) * rx * 0.5 + (row % 2 == 0 ? 0 : rx * 0.25)
                kernels.addEllipse(in: CGRect(x: x - rx * 0.17, y: y - ry * 0.08, width: rx * 0.34, height: ry * 0.16))
            }
        }
        var k = ctx
        k.clip(to: cob)
        k.stroke(kernels, with: .color(Color(red: 0.82, green: 0.5, blue: 0.05).opacity(0.7)), lineWidth: 0.8)
        ctx.stroke(cob, with: .color(Color(red: 0.6, green: 0.35, blue: 0.05)), lineWidth: 1.4)
        // Popcorn tuft on top.
        for (i, p) in [CGPoint(x: c.x - rx * 0.5, y: c.y - ry * 1.02), CGPoint(x: c.x + rx * 0.15, y: c.y - ry * 1.14), CGPoint(x: c.x + rx * 0.7, y: c.y - ry * 0.95)].enumerated() {
            popcorn(ctx, at: p, r: s * 0.06, spin: Double(i))
        }
        // Inner husk wrapping the lower cob.
        for side in [-1.0, 1.0] as [CGFloat] {
            var l = Path()
            l.move(to: CGPoint(x: b.x + side * s * 0.02, y: b.y - s * 0.05))
            l.addQuadCurve(to: CGPoint(x: c.x + side * rx * 0.95, y: c.y - ry * 0.05), control: CGPoint(x: b.x + side * s * 0.26, y: b.y - s * 0.2))
            l.addQuadCurve(to: CGPoint(x: b.x, y: b.y - s * 0.1), control: CGPoint(x: c.x + side * rx * 0.3, y: c.y + ry * 0.5))
            l.closeSubpath()
            ctx.fill(l, with: .color(leaf))
            ctx.stroke(l, with: .color(leafDark), lineWidth: 1.2)
        }
        eyes(ctx, at: CGPoint(x: c.x - rx * 0.05, y: c.y - ry * 0.3), r: rx * 0.26, gap: rx * 0.75)
        let mouth = CGPoint(x: c.x + rx * 0.62, y: c.y + ry * 0.05)
        ctx.fill(oval(mouth, rx * (0.2 + 0.12 * kick), ry * (0.1 + 0.05 * kick)), with: .color(Color(red: 0.4, green: 0.18, blue: 0.02)))
        if kick > 0.3 { popcorn(ctx, at: CGPoint(x: mouth.x + rx * 0.5, y: mouth.y), r: s * 0.05 * kick, spin: t) }
    }

    /// A popcorn puff: shot and tuft.
    static func popcorn(_ ctx: GraphicsContext, at c: CGPoint, r: CGFloat, spin: Double) {
        var puff = Path()
        for k in 0..<4 {
            let a = Double(k) / 4 * 2 * .pi + spin
            puff.addEllipse(in: CGRect(x: c.x + CGFloat(cos(a)) * r * 0.55 - r * 0.6, y: c.y + CGFloat(sin(a)) * r * 0.55 - r * 0.6, width: r * 1.2, height: r * 1.2))
        }
        ctx.fill(puff, with: .color(Color(red: 1, green: 0.98, blue: 0.9)))
        ctx.stroke(puff, with: .color(Color(red: 0.75, green: 0.62, blue: 0.4)), lineWidth: 0.8)
        ctx.fill(disc(c, r * 0.28), with: .color(Color(red: 1, green: 0.78, blue: 0.2)))
    }

    /// The frost berry: a big frosted blueberry whose star-shaped crown is its muzzle.
    static func frostBerry(_ ctx: GraphicsContext, base b: CGPoint, s: CGFloat, t: Double, seed: Double, recoil: Double) {
        let sway = CGFloat(sin(t * 1.8 + seed)) * s * 0.015
        let kick = CGFloat(max(0, 1 - recoil / 0.18))
        let head = CGPoint(x: b.x + sway - kick * s * 0.04, y: b.y - s * 0.52)
        let r = s * 0.27
        var stem = Path()
        stem.move(to: b); stem.addQuadCurve(to: CGPoint(x: head.x - r * 0.2, y: head.y + r * 0.8), control: CGPoint(x: b.x - s * 0.05, y: b.y - s * 0.15))
        ctx.stroke(stem, with: .color(Color(red: 0.18, green: 0.36, blue: 0.3)), style: StrokeStyle(lineWidth: s * 0.1, lineCap: .round))
        ctx.stroke(stem, with: .color(Color(red: 0.36, green: 0.62, blue: 0.5)), style: StrokeStyle(lineWidth: s * 0.05, lineCap: .round))
        for side in [-1.0, 1.0] as [CGFloat] {
            var l = Path()
            l.move(to: b)
            l.addQuadCurve(to: CGPoint(x: b.x + side * s * 0.36, y: b.y - s * 0.1), control: CGPoint(x: b.x + side * s * 0.16, y: b.y - s * 0.22))
            l.addQuadCurve(to: b, control: CGPoint(x: b.x + side * s * 0.24, y: b.y + s * 0.05))
            ctx.fill(l, with: .color(Color(red: 0.4, green: 0.68, blue: 0.56)))
            ctx.stroke(l, with: .color(Color(red: 0.16, green: 0.34, blue: 0.28)), lineWidth: 1.2)
        }
        // The berry, with its powdery bloom.
        ctx.fill(disc(head, r), with: .radialGradient(Gradient(colors: [Color(red: 0.5, green: 0.58, blue: 0.98), Color(red: 0.24, green: 0.26, blue: 0.66), Color(red: 0.14, green: 0.14, blue: 0.42)]),
                                                    center: CGPoint(x: head.x - r * 0.35, y: head.y - r * 0.35), startRadius: 0, endRadius: r * 1.4))
        ctx.fill(disc(CGPoint(x: head.x - r * 0.3, y: head.y - r * 0.38), r * 0.42), with: .radialGradient(Gradient(colors: [.white.opacity(0.45), .white.opacity(0)]),
                                                                                                         center: CGPoint(x: head.x - r * 0.3, y: head.y - r * 0.38), startRadius: 0, endRadius: r * 0.42))
        ctx.stroke(disc(head, r), with: .color(Color(red: 0.1, green: 0.08, blue: 0.3)), lineWidth: 1.4)
        // Frost along the top.
        var rime = Path()
        rime.addArc(center: head, radius: r * 0.92, startAngle: .degrees(200), endAngle: .degrees(320), clockwise: false)
        ctx.stroke(rime, with: .color(Color(red: 0.85, green: 0.95, blue: 1).opacity(0.85)), style: StrokeStyle(lineWidth: r * 0.14, lineCap: .round, dash: [r * 0.18, r * 0.12]))
        // The crown, facing the street.
        let crown = CGPoint(x: head.x + r * 0.86, y: head.y + r * 0.05)
        var star = Path()
        for i in 0..<10 {
            let a = Double(i) / 10 * 2 * .pi
            let rr = i % 2 == 0 ? r * 0.36 : r * 0.16
            let p = CGPoint(x: crown.x + CGFloat(cos(a)) * rr * 0.6, y: crown.y + CGFloat(sin(a)) * rr)
            if i == 0 { star.move(to: p) } else { star.addLine(to: p) }
        }
        star.closeSubpath()
        ctx.fill(star, with: .color(Color(red: 0.2, green: 0.2, blue: 0.5)))
        ctx.stroke(star, with: .color(Color(red: 0.08, green: 0.06, blue: 0.25)), lineWidth: 1)
        ctx.fill(oval(crown, r * 0.08, r * 0.12), with: .color(Color(red: 0.05, green: 0.04, blue: 0.18)))
        eyes(ctx, at: CGPoint(x: head.x - r * 0.05, y: head.y - r * 0.12), r: r * 0.2, gap: r * 0.6)
        // Snowflake sparkles.
        for i in 0..<3 {
            let a = t * 0.9 + Double(i) * 2.1 + seed
            let p = CGPoint(x: head.x + CGFloat(cos(a)) * r * 1.35, y: head.y + CGFloat(sin(a)) * r * 1.1)
            snowflake(ctx, at: p, r: s * 0.045)
        }
        if kick > 0.2 {
            ctx.fill(disc(CGPoint(x: crown.x + r * 0.35, y: crown.y), r * 0.3 * kick), with: .color(Color(red: 0.85, green: 0.95, blue: 1).opacity(0.7)))
        }
    }

    static func snowflake(_ ctx: GraphicsContext, at c: CGPoint, r: CGFloat) {
        var f = Path()
        for k in 0..<3 {
            let a = Double(k) / 3 * .pi
            f.move(to: CGPoint(x: c.x - CGFloat(cos(a)) * r, y: c.y - CGFloat(sin(a)) * r))
            f.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y + CGFloat(sin(a)) * r))
        }
        ctx.stroke(f, with: .color(.white), lineWidth: 1.1)
    }

    /// The melon lobber: a striped melon with a coiled vine arm that flings melon balls overhead.
    static func lobber(_ ctx: GraphicsContext, base b: CGPoint, s: CGFloat, t: Double, seed: Double, fired: Double) {
        let since = fired
        // The arm: leaning back while loaded, flung forward on a throw, then easing back.
        let swing: Double
        if since < 0.14 { swing = -0.55 + (since / 0.14) * 1.55 } else if since < 0.8 { swing = 1.0 - (since - 0.14) / 0.66 * 1.55 } else { swing = -0.55 + sin(t * 1.6 + seed) * 0.05 }
        // Leaves on the ground.
        for (i, side) in ([-1.0, 1.0, -0.3] as [CGFloat]).enumerated() {
            var l = Path()
            l.move(to: b)
            l.addQuadCurve(to: CGPoint(x: b.x + side * s * 0.42, y: b.y - s * (i == 2 ? 0.16 : 0.04)), control: CGPoint(x: b.x + side * s * 0.2, y: b.y - s * 0.2))
            l.addQuadCurve(to: b, control: CGPoint(x: b.x + side * s * 0.28, y: b.y + s * 0.06))
            ctx.fill(l, with: .color(leaf))
            ctx.stroke(l, with: .color(leafDark), lineWidth: 1.1)
        }
        // The melon body with stripes and a face.
        let body = CGPoint(x: b.x, y: b.y - s * 0.22)
        let rx = s * 0.28, ry = s * 0.21
        let melon = oval(body, rx, ry)
        ctx.fill(melon, with: .radialGradient(Gradient(colors: [Color(red: 0.5, green: 0.8, blue: 0.3), Color(red: 0.2, green: 0.5, blue: 0.12)]),
                                             center: CGPoint(x: body.x - rx * 0.3, y: body.y - ry * 0.4), startRadius: 0, endRadius: rx * 1.3))
        var stripes = Path()
        for k in -2...2 {
            let x = body.x + CGFloat(k) * rx * 0.38
            stripes.move(to: CGPoint(x: x, y: body.y - ry * 0.95))
            stripes.addCurve(to: CGPoint(x: x, y: body.y + ry * 0.95), control1: CGPoint(x: x + rx * 0.12, y: body.y - ry * 0.3), control2: CGPoint(x: x - rx * 0.12, y: body.y + ry * 0.3))
        }
        var sc = ctx
        sc.clip(to: melon)
        sc.stroke(stripes, with: .color(Color(red: 0.12, green: 0.34, blue: 0.08)), lineWidth: rx * 0.14)
        ctx.stroke(melon, with: .color(Color(red: 0.08, green: 0.24, blue: 0.05)), lineWidth: 1.4)
        eyes(ctx, at: CGPoint(x: body.x + rx * 0.2, y: body.y - ry * 0.15), r: rx * 0.15, gap: rx * 0.45)
        var smile = Path()
        smile.addArc(center: CGPoint(x: body.x + rx * 0.25, y: body.y + ry * 0.2), radius: rx * 0.18, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
        ctx.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        // The coiled vine arm and its leaf cup.
        let pivot = CGPoint(x: body.x - rx * 0.55, y: body.y - ry * 0.75)
        let len = s * 0.46
        let tip = CGPoint(x: pivot.x + CGFloat(sin(swing)) * len, y: pivot.y - CGFloat(cos(swing)) * len)
        var vine = Path()
        vine.move(to: pivot)
        let n = 10
        for i in 1...n {
            let f = CGFloat(i) / CGFloat(n)
            let x = pivot.x + (tip.x - pivot.x) * f, y = pivot.y + (tip.y - pivot.y) * f
            let wob = CGFloat(sin(Double(i) * 1.9)) * s * 0.025 * (1 - f)
            vine.addLine(to: CGPoint(x: x + wob * CGFloat(cos(swing)), y: y + wob * CGFloat(sin(swing))))
        }
        ctx.stroke(vine, with: .color(leafDark), style: StrokeStyle(lineWidth: s * 0.1, lineCap: .round, lineJoin: .round))
        ctx.stroke(vine, with: .color(leaf), style: StrokeStyle(lineWidth: s * 0.055, lineCap: .round, lineJoin: .round))
        var coil = Path()
        coil.addArc(center: pivot, radius: s * 0.05, startAngle: .degrees(0), endAngle: .degrees(300), clockwise: false)
        ctx.stroke(coil, with: .color(leafDark), lineWidth: 1.6)
        var cup = Path()
        cup.addArc(center: tip, radius: s * 0.14, startAngle: .radians(swing + .pi * 0.1), endAngle: .radians(swing + .pi * 0.9), clockwise: false)
        cup.closeSubpath()
        ctx.fill(cup, with: .color(leaf))
        ctx.stroke(cup, with: .color(leafDark), lineWidth: 1.2)
        if since > 0.75 || since >= 8 {
            melonBall(ctx, at: CGPoint(x: tip.x - CGFloat(sin(swing)) * s * 0.03, y: tip.y - s * 0.08), r: s * 0.11)
        }
    }

    static func melonBall(_ ctx: GraphicsContext, at c: CGPoint, r: CGFloat) {
        let ball = disc(c, r)
        ctx.fill(ball, with: .radialGradient(Gradient(colors: [Color(red: 0.55, green: 0.85, blue: 0.35), Color(red: 0.2, green: 0.5, blue: 0.12)]),
                                            center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.3), startRadius: 0, endRadius: r * 1.3))
        var stripes = Path()
        for k in -1...1 {
            stripes.move(to: CGPoint(x: c.x + CGFloat(k) * r * 0.5, y: c.y - r))
            stripes.addQuadCurve(to: CGPoint(x: c.x + CGFloat(k) * r * 0.5, y: c.y + r), control: CGPoint(x: c.x + CGFloat(k) * r * 0.5 + r * 0.25, y: c.y))
        }
        var sc = ctx
        sc.clip(to: ball)
        sc.stroke(stripes, with: .color(Color(red: 0.12, green: 0.34, blue: 0.08)), lineWidth: r * 0.22)
        ctx.stroke(ball, with: .color(Color(red: 0.08, green: 0.24, blue: 0.05)), lineWidth: 1)
    }

    static func wallnut(_ ctx: GraphicsContext, base b: CGPoint, s: CGFloat, health: Double, wince: Bool) {
        let w = s * 0.62, h = s * 0.8
        let body = CGRect(x: b.x - w / 2, y: b.y - h, width: w, height: h)
        let shell = Path(ellipseIn: body)
        ctx.fill(shell, with: .radialGradient(Gradient(colors: [Color(red: 0.9, green: 0.68, blue: 0.4), Color(red: 0.66, green: 0.42, blue: 0.18), Color(red: 0.45, green: 0.26, blue: 0.1)]),
                                             center: CGPoint(x: body.midX - w * 0.12, y: body.midY - h * 0.15), startRadius: 0, endRadius: h * 0.7))
        ctx.stroke(shell, with: .color(Color(red: 0.3, green: 0.16, blue: 0.05)), lineWidth: 1.6)
        var ridge = Path()
        ridge.move(to: CGPoint(x: body.midX + w * 0.28, y: body.minY + h * 0.2)); ridge.addQuadCurve(to: CGPoint(x: body.midX + w * 0.3, y: body.maxY - h * 0.2), control: CGPoint(x: body.midX + w * 0.44, y: body.midY))
        ctx.stroke(ridge, with: .color(Color(red: 0.42, green: 0.24, blue: 0.08).opacity(0.6)), lineWidth: 1.2)
        if health < 0.67 {
            var crack = Path()
            crack.move(to: CGPoint(x: body.midX - w * 0.1, y: body.minY + h * 0.05))
            crack.addLine(to: CGPoint(x: body.midX + w * 0.02, y: body.minY + h * 0.2))
            crack.addLine(to: CGPoint(x: body.midX - w * 0.08, y: body.minY + h * 0.32))
            crack.addLine(to: CGPoint(x: body.midX + w * 0.05, y: body.minY + h * 0.42))
            if health < 0.34 {
                crack.move(to: CGPoint(x: body.minX + w * 0.08, y: body.midY + h * 0.1))
                crack.addLine(to: CGPoint(x: body.minX + w * 0.25, y: body.midY + h * 0.18))
                crack.addLine(to: CGPoint(x: body.minX + w * 0.2, y: body.midY + h * 0.3))
            }
            ctx.stroke(crack, with: .color(Color(red: 0.25, green: 0.12, blue: 0.04)), lineWidth: 1.6)
        }
        for dx in [-0.18, 0.12] as [CGFloat] {
            let e = CGPoint(x: body.midX + dx * w - w * 0.05, y: body.minY + h * 0.4)
            ctx.fill(oval(e, w * 0.13, h * 0.12), with: .color(.white))
            ctx.stroke(oval(e, w * 0.13, h * 0.12), with: .color(ink), lineWidth: 1)
            let look = wince ? CGFloat(0) : -w * 0.04
            ctx.fill(disc(CGPoint(x: e.x + look, y: e.y + h * 0.01), w * 0.06), with: .color(ink))
            if health < 0.34 || wince {
                var brow = Path()
                brow.move(to: CGPoint(x: e.x - w * 0.12, y: e.y - h * 0.13 + (dx < 0 ? h * 0.03 : 0)))
                brow.addLine(to: CGPoint(x: e.x + w * 0.12, y: e.y - h * 0.13 + (dx < 0 ? 0 : h * 0.03)))
                ctx.stroke(brow, with: .color(ink), lineWidth: 1.4)
            }
        }
    }

    /// A banana peel. Freshly planted it's a banana standing up and slowly unpeeling; armed, it's the empty
    /// peel, flaps drooping to the ground, glinting.
    static func peel(_ ctx: GraphicsContext, base b: CGPoint, s: CGFloat, arm: Double, t: Double) {
        let yellow = Color(red: 1, green: 0.87, blue: 0.25), deep = Color(red: 0.9, green: 0.64, blue: 0.1), brown = Color(red: 0.42, green: 0.25, blue: 0.07)
        let open = CGFloat(min(1, max(0, arm)))
        let armed = arm >= 1
        // Where the flaps join: high on a standing banana, low on an empty peel.
        let root = CGPoint(x: b.x, y: b.y - s * (armed ? 0.24 : 0.5 - 0.1 * open))
        ctx.fill(oval(CGPoint(x: b.x, y: b.y), s * (0.28 + 0.14 * open), s * 0.05), with: .color(.black.opacity(0.18)))
        if !armed {
            // The fruit inside, showing more as the peel opens.
            var fruit = Path()
            fruit.addRoundedRect(in: CGRect(x: root.x - s * 0.09, y: root.y - s * 0.3 * (1 - open * 0.6), width: s * 0.18, height: s * 0.32 * (1 - open * 0.6) + (b.y - root.y)), cornerSize: CGSize(width: s * 0.09, height: s * 0.09))
            ctx.fill(fruit, with: .color(Color(red: 0.99, green: 0.95, blue: 0.75)))
            ctx.stroke(fruit, with: .color(Color(red: 0.8, green: 0.7, blue: 0.4)), lineWidth: 1)
        }
        // The cup at the bottom of the peel and its stalk.
        let cup = Path(ellipseIn: CGRect(x: root.x - s * 0.13, y: root.y - s * 0.02, width: s * 0.26, height: b.y - root.y + s * 0.02))
        ctx.fill(cup, with: .linearGradient(Gradient(colors: [yellow, deep]), startPoint: CGPoint(x: root.x - s * 0.13, y: 0), endPoint: CGPoint(x: root.x + s * 0.13, y: 0)))
        ctx.stroke(cup, with: .color(brown), lineWidth: 1.2)
        ctx.fill(Path(roundedRect: CGRect(x: b.x - s * 0.03, y: b.y - s * 0.035, width: s * 0.06, height: s * 0.05), cornerRadius: 2), with: .color(brown))
        // Four flaps: straight up while closed, drooping out to the ground once open.
        for (i, side) in ([-1.0, -0.45, 0.45, 1.0] as [CGFloat]).enumerated() {
            let len = s * (abs(side) > 0.5 ? 0.42 : 0.36)
            let up = -CGFloat.pi / 2 + side * 0.12
            let down = side < 0 ? CGFloat.pi * (0.62 + 0.08 * abs(side)) : CGFloat.pi * (0.38 - 0.08 * abs(side))
            let a = up + (down - up) * open
            let from = CGPoint(x: root.x + side * s * 0.07, y: root.y + s * 0.02)
            let tip = CGPoint(x: from.x + cos(a) * len, y: min(b.y, from.y + sin(a) * len))
            let bend = CGPoint(x: (from.x + tip.x) / 2 + cos(a - .pi / 2) * len * 0.25 * side, y: (from.y + tip.y) / 2 - len * 0.18 * open)
            var flap = Path()
            flap.move(to: CGPoint(x: from.x - s * 0.05, y: from.y))
            flap.addQuadCurve(to: tip, control: CGPoint(x: bend.x - s * 0.04, y: bend.y))
            flap.addQuadCurve(to: CGPoint(x: from.x + s * 0.05, y: from.y), control: CGPoint(x: bend.x + s * 0.05, y: bend.y + s * 0.05))
            flap.closeSubpath()
            ctx.fill(flap, with: .linearGradient(Gradient(colors: [i % 2 == 0 ? yellow : yellow.mix(with: deep, by: 0.3), deep]), startPoint: from, endPoint: tip))
            ctx.stroke(flap, with: .color(brown), lineWidth: 1.1)
            ctx.fill(disc(tip, s * 0.028), with: .color(brown))
        }
        if armed {
            // A slippery glint.
            let glow = 0.5 + 0.5 * sin(t * 4)
            var glint = Path()
            let g = CGPoint(x: b.x + s * 0.2, y: b.y - s * 0.22)
            glint.move(to: CGPoint(x: g.x - s * 0.06, y: g.y)); glint.addLine(to: CGPoint(x: g.x + s * 0.06, y: g.y))
            glint.move(to: CGPoint(x: g.x, y: g.y - s * 0.06)); glint.addLine(to: CGPoint(x: g.x, y: g.y + s * 0.06))
            ctx.stroke(glint, with: .color(.white.opacity(0.4 + 0.6 * glow)), lineWidth: 1.4)
        }
    }

    /// A zombie a flytrap has just snapped up: where it stood, how tall it's drawn and which world dresses it.
    struct Prey {
        let zombie: LDWorld.Zombie
        let feet: CGPoint
        let h: CGFloat
        let scene: LDScene
    }

    /// 0 before `a`, 1 after `b`, easing in and out between.
    private static func ramp(_ x: Double, _ a: Double, _ b: Double) -> Double {
        let k = min(1, max(0, (x - a) / (b - a)))
        return k * k * (3 - 2 * k)
    }

    private static func mix(_ p: CGPoint, _ q: CGPoint, _ k: Double) -> CGPoint {
        CGPoint(x: p.x + (q.x - p.x) * CGFloat(k), y: p.y + (q.y - p.y) * CGFloat(k))
    }

    /// The flytrap: hinged jaws ringed with bristles. It strikes down over a zombie's head, hauls it back with
    /// its legs kicking out of the jaws, gulps it down in three swallows and chews for a while. A boss only
    /// gets a lunge and a snap.
    static func flytrap(_ ctx: GraphicsContext, base b: CGPoint, s: CGFloat, t: Double, seed: Double, chewing: Double, gulp: Double, prey: Prey? = nil) {
        let since = t - gulp
        let chew = 0.04 + 0.03 * abs(sin(t * 7))
        var open: Double
        if chewing > 0 { open = chew } else if since < 0.3 { open = 0.05 } else { open = 0.5 + 0.06 * sin(t * 2.5 + seed) }
        var bulge: CGFloat = chewing > 0 ? 1.12 : 1
        let rest = CGPoint(x: b.x - s * 0.14, y: b.y - s * 0.5)
        var len = s * 0.5
        var jaw: CGFloat = 1        // the jaws stretch wide to take a zombie
        var hinge = rest
        var aim = 0.0               // the jaws' heading, clockwise from the street
        // The meal while it goes down: its feet, tilt and size, and the line at the lips it vanishes behind.
        var meal: (feet: CGPoint, tilt: Double, scale: CGFloat, lips: CGPoint?)? = nil
        if chewing > 0 && since >= 0, let prey {
            let a = since
            // Strike (to 0.12 s) up and over, jaws stretched wide; snap (to 0.2 s) over its head and shoulders;
            // haul it back (to 0.6 s); three gulps (to 1.35 s), the jaws swelling with each; settle (to 1.6 s)
            // into chewing.
            let biteAim = 1.1, biteJaw: CGFloat = 1.5
            let chest = CGPoint(x: prey.feet.x - prey.h * 0.03, y: prey.feet.y - prey.h * 0.72)
            let biteHinge = CGPoint(x: chest.x - len * biteJaw * CGFloat(cos(biteAim)), y: chest.y - len * biteJaw * CGFloat(sin(biteAim)))
            let held = CGPoint(x: rest.x + s * 0.04, y: rest.y - s * 0.06)
            let strike = ramp(a, 0, 0.12), snap = ramp(a, 0.12, 0.19), grab = ramp(a, 0.13, 0.24)
            let haul = ramp(a, 0.2, 0.6), settle = ramp(a, 1.35, 1.6)
            let gp = min(3, max(0, (a - 0.6) / 0.25)), done = floor(gp)
            let swallowed = (done + ramp(gp - done, 0, 0.5)) / 3
            let jerk = gp < 3 && gp > 0 ? sin(min(1, (gp - done) / 0.5) * .pi) : 0
            hinge = mix(mix(mix(rest, biteHinge, strike), held, haul), rest, settle)
            hinge.y -= CGFloat(jerk) * s * 0.05
            aim = biteAim * strike
            aim += (0.22 - aim) * haul
            aim += (0 - aim) * settle
            aim -= jerk * 0.12
            open = 0.5 + 0.5 * strike
            open += (0.4 - open) * snap
            open += jerk * 0.08
            open += (chew - open) * settle
            bulge = 1 + 0.12 * CGFloat(grab) + 0.2 * CGFloat(swallowed)
            bulge += (1.12 - bulge) * CGFloat(settle)
            jaw = 1 + (biteJaw - 1) * CGFloat(strike) - 0.2 * CGFloat(haul) - 0.3 * CGFloat(swallowed)
            len *= jaw
            if a < 1.6 {
                let along = 0.72 - 0.17 * haul                       // lips-to-toe length still outside, in heights
                let reach = CGFloat(along * (1 - swallowed) - 0.2 * swallowed) * prey.h
                let scale = 1 - 0.34 * CGFloat(haul)
                let tilt = aim - .pi / 2 + 0.1 * sin(t * 17) * (1 - swallowed) * grab
                let dir = CGPoint(x: CGFloat(cos(aim)), y: CGFloat(sin(aim)))
                let lips = CGPoint(x: hinge.x + dir.x * len, y: hinge.y + dir.y * len)
                let up = CGPoint(x: CGFloat(sin(tilt)), y: -CGFloat(cos(tilt)))
                let hung = CGPoint(x: lips.x - up.x * reach * scale, y: lips.y - up.y * reach * scale)
                meal = (mix(prey.feet, hung, grab), tilt * grab, 1 + (scale - 1) * CGFloat(grab),
                        a >= 0.15 ? CGPoint(x: hinge.x + dir.x * len * 0.78, y: hinge.y + dir.y * len * 0.78) : nil)
            }
        } else if chewing > 0 && since >= 0 && since < 0.45 {
            // A boss: lunge, snap, pull back.
            let strike = ramp(since, 0, 0.1), snap = ramp(since, 0.1, 0.16), back = ramp(since, 0.2, 0.45)
            hinge = mix(mix(rest, CGPoint(x: rest.x + s * 0.55, y: rest.y - s * 0.05), strike), rest, back)
            aim = 0.12 * strike * (1 - back)
            open = 0.5 + 0.5 * strike
            open += (chew - open) * snap
            jaw = 1 + 0.3 * CGFloat(strike * (1 - back))
            len *= jaw
        }
        // Stalk and two long leaves.
        var stem = Path()
        stem.move(to: b)
        stem.addQuadCurve(to: hinge, control: CGPoint(x: b.x + s * 0.08 + (hinge.x - rest.x) * 0.15, y: b.y - s * 0.25 + (hinge.y - rest.y) * 0.3))
        ctx.stroke(stem, with: .color(leafDark), style: StrokeStyle(lineWidth: s * 0.1, lineCap: .round))
        ctx.stroke(stem, with: .color(leaf), style: StrokeStyle(lineWidth: s * 0.05, lineCap: .round))
        for side in [-1.0, 1.0] as [CGFloat] {
            var l = Path()
            l.move(to: b)
            l.addQuadCurve(to: CGPoint(x: b.x + side * s * 0.42, y: b.y - s * 0.16), control: CGPoint(x: b.x + side * s * 0.2, y: b.y - s * 0.28))
            l.addQuadCurve(to: b, control: CGPoint(x: b.x + side * s * 0.3, y: b.y + s * 0.02))
            ctx.fill(l, with: .color(leaf))
            ctx.stroke(l, with: .color(leafDark), lineWidth: 1.1)
        }
        // The meal, under the jaws: a dark gullet behind it, and only what still sticks out past the lips.
        if let m = meal, let prey {
            var g = ctx
            if let lips = m.lips {
                var gullet = Path()
                gullet.move(to: hinge)
                for side in [-1.0, 1.0] {
                    gullet.addLine(to: CGPoint(x: hinge.x + CGFloat(cos(aim + side * open)) * len, y: hinge.y + CGFloat(sin(aim + side * open)) * len))
                }
                gullet.closeSubpath()
                ctx.fill(gullet, with: .color(Color(red: 0.36, green: 0.05, blue: 0.1)))
                let d = CGPoint(x: CGFloat(cos(aim)), y: CGFloat(sin(aim))), far = prey.h * 3
                var outside = Path()
                outside.move(to: CGPoint(x: lips.x - d.y * far, y: lips.y + d.x * far))
                outside.addLine(to: CGPoint(x: lips.x + d.y * far, y: lips.y - d.x * far))
                outside.addLine(to: CGPoint(x: lips.x + d.y * far + d.x * far, y: lips.y - d.x * far + d.y * far))
                outside.addLine(to: CGPoint(x: lips.x - d.y * far + d.x * far, y: lips.y + d.x * far + d.y * far))
                outside.closeSubpath()
                g.clip(to: outside)
            }
            g.translateBy(x: m.feet.x, y: m.feet.y)
            g.rotate(by: .radians(m.tilt))
            g.scaleBy(x: m.scale, y: m.scale)
            // Its legs keep kicking.
            var kicking = prey.zombie
            kicking.died = nil
            kicking.eating = false
            kicking.speedK = 4.5
            figure(g, feet: .zero, h: prey.h, z: kicking, t: t, scene: prey.scene, look: Outfit.of(prey.scene), stunned: false)
        }
        // Two lobes hinged at the back, opening toward the street.
        let depth = s * 0.17 * bulge * jaw
        for side in [-1.0, 1.0] {
            let a = aim + side * open
            let dir = CGPoint(x: CGFloat(cos(a)), y: CGFloat(sin(a)))
            let norm = CGPoint(x: -dir.y * CGFloat(side), y: dir.x * CGFloat(side))
            let tip = CGPoint(x: hinge.x + dir.x * len, y: hinge.y + dir.y * len)
            let mid = CGPoint(x: hinge.x + dir.x * len * 0.5 - norm.x * depth, y: hinge.y + dir.y * len * 0.5 - norm.y * depth)
            var lobe = Path()
            lobe.move(to: hinge)
            lobe.addQuadCurve(to: tip, control: CGPoint(x: mid.x - norm.x * depth * 0.6, y: mid.y - norm.y * depth * 0.6))
            lobe.addQuadCurve(to: hinge, control: CGPoint(x: hinge.x + dir.x * len * 0.55, y: hinge.y + dir.y * len * 0.55))
            ctx.fill(lobe, with: .color(Color(red: 0.4, green: 0.72, blue: 0.22)))
            ctx.stroke(lobe, with: .color(leafDark), lineWidth: 1.3)
            // The red inside.
            var inner = Path()
            inner.move(to: CGPoint(x: hinge.x + dir.x * len * 0.12, y: hinge.y + dir.y * len * 0.12))
            inner.addQuadCurve(to: CGPoint(x: hinge.x + dir.x * len * 0.92, y: hinge.y + dir.y * len * 0.92),
                               control: CGPoint(x: hinge.x + dir.x * len * 0.52 - norm.x * depth * 0.55, y: hinge.y + dir.y * len * 0.52 - norm.y * depth * 0.55))
            inner.addQuadCurve(to: CGPoint(x: hinge.x + dir.x * len * 0.12, y: hinge.y + dir.y * len * 0.12),
                               control: CGPoint(x: hinge.x + dir.x * len * 0.52, y: hinge.y + dir.y * len * 0.52))
            ctx.fill(inner, with: .color(Color(red: 0.88, green: 0.22, blue: 0.28)))
            // Bristles along the rim.
            var bristles = Path()
            for i in 1...6 {
                let f = CGFloat(i) / 7
                let base = CGPoint(x: hinge.x + dir.x * len * f - norm.x * depth * 0.9 * (1 - abs(f - 0.5) * 1.4),
                                   y: hinge.y + dir.y * len * f - norm.y * depth * 0.9 * (1 - abs(f - 0.5) * 1.4))
                bristles.move(to: base)
                bristles.addLine(to: CGPoint(x: base.x - norm.x * s * 0.08 * jaw + dir.x * s * 0.03, y: base.y - norm.y * s * 0.08 * jaw + dir.y * s * 0.03))
            }
            ctx.stroke(bristles, with: .color(Color(red: 0.86, green: 0.95, blue: 0.7)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        }
        // Little eyes on top (wide open while it strikes and swallows).
        let eye = CGPoint(x: len * 0.3, y: -s * 0.12 - CGFloat(open) * s * 0.18)
        let top = CGPoint(x: hinge.x + eye.x * CGFloat(cos(aim)) - eye.y * CGFloat(sin(aim)), y: hinge.y + eye.x * CGFloat(sin(aim)) + eye.y * CGFloat(cos(aim)))
        let busy = since >= 0 && since < 1.6
        eyes(ctx, at: top, r: s * 0.045, gap: s * 0.12, blink: chewing > 0 && !busy && Int(t * 2) % 3 == 0)
    }

    static func cherry(_ ctx: GraphicsContext, base b: CGPoint, s: CGFloat, fuse: Double, t: Double) {
        let swell = 1 + CGFloat(max(0, fuse)) * 0.28
        let jitter = CGFloat(sin(t * 60)) * s * 0.02 * CGFloat(fuse)
        let joint = CGPoint(x: b.x + jitter, y: b.y - s * 0.78)
        let berries = [CGPoint(x: b.x - s * 0.17 + jitter, y: b.y - s * 0.22), CGPoint(x: b.x + s * 0.15 + jitter, y: b.y - s * 0.3)]
        var stems = Path()
        for c in berries { stems.move(to: c); stems.addQuadCurve(to: joint, control: CGPoint(x: (c.x + joint.x) / 2, y: joint.y + s * 0.1)) }
        ctx.stroke(stems, with: .color(leafDark), style: StrokeStyle(lineWidth: s * 0.05, lineCap: .round))
        var lf = Path()
        lf.move(to: joint); lf.addQuadCurve(to: CGPoint(x: joint.x + s * 0.24, y: joint.y - s * 0.04), control: CGPoint(x: joint.x + s * 0.1, y: joint.y - s * 0.14))
        lf.addQuadCurve(to: joint, control: CGPoint(x: joint.x + s * 0.14, y: joint.y + s * 0.06))
        ctx.fill(lf, with: .color(leaf)); ctx.stroke(lf, with: .color(leafDark), lineWidth: 1)
        let red = Color(red: 0.86 + 0.1 * fuse, green: 0.1, blue: 0.1)
        for c in berries {
            let r = s * 0.2 * swell
            ctx.fill(disc(c, r), with: .radialGradient(Gradient(colors: [red.lit(0.35), red, red.shade(0.35)]),
                                                     center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4), startRadius: 0, endRadius: r * 1.3))
            ctx.stroke(disc(c, r), with: .color(Color(red: 0.35, green: 0.02, blue: 0.02)), lineWidth: 1.4)
            for dx in [-0.32, 0.32] as [CGFloat] {
                let e = CGPoint(x: c.x + dx * r, y: c.y - r * 0.05)
                ctx.fill(disc(e, r * 0.12), with: .color(ink))
                var brow = Path()
                brow.move(to: CGPoint(x: e.x - r * 0.2 * (dx < 0 ? 1 : -1), y: e.y - r * 0.32))
                brow.addLine(to: CGPoint(x: e.x + r * 0.16 * (dx < 0 ? 1 : -1), y: e.y - r * 0.16))
                ctx.stroke(brow, with: .color(ink), lineWidth: 1.5)
            }
            var m = Path()
            m.addArc(center: CGPoint(x: c.x, y: c.y + r * 0.45), radius: r * 0.2, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
            ctx.stroke(m, with: .color(ink), lineWidth: 1.3)
        }
    }

    /// The hot chili: a curled red pepper that gets angrier (and hotter) until it bursts into a lane of fire.
    static func chili(_ ctx: GraphicsContext, base b: CGPoint, s: CGFloat, fuse: Double, t: Double) {
        let f = CGFloat(max(0, min(1, fuse)))
        let jitter = CGFloat(sin(t * 70)) * s * 0.025 * f
        let swell = 1 + f * 0.18
        let red = Color(red: 0.9, green: 0.12 + 0.25 * Double(f), blue: 0.08)
        let top = CGPoint(x: b.x + jitter, y: b.y - s * 0.78)
        var pepper = Path()
        pepper.move(to: CGPoint(x: top.x - s * 0.13 * swell, y: top.y + s * 0.06))
        pepper.addCurve(to: CGPoint(x: b.x + s * 0.12 + jitter, y: b.y - s * 0.02),
                        control1: CGPoint(x: top.x - s * 0.24 * swell, y: top.y + s * 0.4), control2: CGPoint(x: b.x - s * 0.2 + jitter, y: b.y - s * 0.05))
        pepper.addCurve(to: CGPoint(x: top.x + s * 0.13 * swell, y: top.y + s * 0.06),
                        control1: CGPoint(x: b.x + s * 0.02 + jitter, y: b.y - s * 0.22), control2: CGPoint(x: top.x + s * 0.2 * swell, y: top.y + s * 0.34))
        pepper.closeSubpath()
        if f > 0.3 {
            ctx.fill(disc(CGPoint(x: b.x, y: b.y - s * 0.4), s * 0.42 * f), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.6, blue: 0.1).opacity(0.6), .clear]),
                                                                                               center: CGPoint(x: b.x, y: b.y - s * 0.4), startRadius: 0, endRadius: s * 0.42 * f))
        }
        ctx.fill(pepper, with: .linearGradient(Gradient(colors: [red.lit(0.25), red, red.shade(0.35)]), startPoint: CGPoint(x: top.x - s * 0.15, y: top.y), endPoint: CGPoint(x: top.x + s * 0.15, y: top.y)))
        ctx.stroke(pepper, with: .color(Color(red: 0.35, green: 0.02, blue: 0.02)), lineWidth: 1.4)
        // Stem cap and curl.
        var cap = Path()
        cap.addEllipse(in: CGRect(x: top.x - s * 0.15 * swell, y: top.y - s * 0.03, width: s * 0.3 * swell, height: s * 0.1))
        ctx.fill(cap, with: .color(leaf)); ctx.stroke(cap, with: .color(leafDark), lineWidth: 1.1)
        var curl = Path()
        curl.move(to: CGPoint(x: top.x, y: top.y))
        curl.addQuadCurve(to: CGPoint(x: top.x + s * 0.12, y: top.y - s * 0.12), control: CGPoint(x: top.x - s * 0.04, y: top.y - s * 0.14))
        ctx.stroke(curl, with: .color(leafDark), style: StrokeStyle(lineWidth: s * 0.04, lineCap: .round))
        // An angry face.
        let face = CGPoint(x: top.x - s * 0.01, y: top.y + s * 0.28)
        for dx in [-1.0, 1.0] as [CGFloat] {
            let e = CGPoint(x: face.x + dx * s * 0.055, y: face.y)
            ctx.fill(disc(e, s * 0.028), with: .color(ink))
            var brow = Path()
            brow.move(to: CGPoint(x: e.x - dx * s * 0.05, y: e.y - s * 0.06)); brow.addLine(to: CGPoint(x: e.x + dx * s * 0.03, y: e.y - s * 0.025))
            ctx.stroke(brow, with: .color(ink), lineWidth: 1.5)
        }
        var mouth = Path()
        mouth.move(to: CGPoint(x: face.x - s * 0.06, y: face.y + s * 0.09)); mouth.addLine(to: CGPoint(x: face.x + s * 0.06, y: face.y + s * 0.08))
        ctx.stroke(mouth, with: .color(ink), lineWidth: 1.6)
    }

    /// A cherry bomb's blast across its 3×3 tiles.
    static func boom(_ ctx: GraphicsContext, at c: CGPoint, cell: CGFloat, age: Double) {
        let k = CGFloat(min(1, age / 0.35))
        let fade = max(0, 1 - age / 0.9)
        let r = cell * (0.6 + 1.3 * k)
        var g = ctx
        g.opacity = fade
        g.fill(disc(c, r * 1.1), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.6), Color(red: 1, green: 0.55, blue: 0.1), Color(red: 0.6, green: 0.15, blue: 0.05).opacity(0)]),
                                                     center: c, startRadius: 0, endRadius: r * 1.1))
        var star = Path()
        for i in 0..<20 {
            let a = Double(i) / 20 * 2 * .pi
            let rr = i % 2 == 0 ? r : r * 0.55
            let p = CGPoint(x: c.x + CGFloat(cos(a)) * rr, y: c.y + CGFloat(sin(a)) * rr * 0.8)
            if i == 0 { star.move(to: p) } else { star.addLine(to: p) }
        }
        star.closeSubpath()
        g.fill(star, with: .color(Color(red: 1, green: 0.78, blue: 0.2).opacity(0.85)))
        g.fill(disc(c, r * 0.35), with: .color(.white.opacity(0.9)))
    }

    /// A hot chili's fire running the whole lane.
    static func blaze(_ ctx: GraphicsContext, lay: LDLayout, row: Int, age: Double) {
        let fade = max(0, 1 - max(0, age - 0.45) / 0.45)
        let grow = CGFloat(min(1, age / 0.18))
        var g = ctx
        g.opacity = fade
        let cw = lay.cellW, ch = lay.cellH
        let baseY = lay.point(x: 0, y: Double(row) + 0.92).y
        var x = -0.6
        var i = 0.0
        while x < Double(LDWorld.cols) + 0.6 {
            let p = lay.point(x: x, y: Double(row))
            let h = ch * (0.55 + 0.35 * CGFloat(hash(i + 1.3))) * grow * CGFloat(0.8 + 0.2 * sin(age * 30 + i))
            let w = cw * 0.42
            var flame = Path()
            flame.move(to: CGPoint(x: p.x - w / 2, y: baseY))
            flame.addQuadCurve(to: CGPoint(x: p.x + CGFloat(sin(age * 20 + i)) * w * 0.2, y: baseY - h), control: CGPoint(x: p.x - w * 0.6, y: baseY - h * 0.5))
            flame.addQuadCurve(to: CGPoint(x: p.x + w / 2, y: baseY), control: CGPoint(x: p.x + w * 0.6, y: baseY - h * 0.5))
            flame.closeSubpath()
            g.fill(flame, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.5), Color(red: 1, green: 0.5, blue: 0.08), Color(red: 0.85, green: 0.12, blue: 0.05)]),
                                                startPoint: CGPoint(x: p.x, y: baseY), endPoint: CGPoint(x: p.x, y: baseY - h)))
            x += 0.32; i += 1
        }
    }

    /// Dust and splinters where a plant got squashed.
    static func crash(_ ctx: GraphicsContext, at c: CGPoint, cell: CGFloat, age: Double) {
        let k = CGFloat(min(1, age / 0.25))
        var g = ctx
        g.opacity = max(0, 1 - age / 0.7)
        g.fill(oval(CGPoint(x: c.x, y: c.y), cell * (0.3 + 0.5 * k), cell * (0.12 + 0.18 * k)), with: .color(Color(red: 0.55, green: 0.45, blue: 0.35).opacity(0.7)))
        var bits = Path()
        for i in 0..<7 {
            let a = Double(i) / 7 * .pi + 0.2
            let d = cell * 0.55 * k
            let p = CGPoint(x: c.x + CGFloat(cos(a)) * d * (i % 2 == 0 ? 1 : -1), y: c.y - CGFloat(sin(a)) * d * 0.8 + cell * 0.6 * CGFloat(age * age))
            bits.addRect(CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 3))
        }
        g.fill(bits, with: .color(Color(red: 0.3, green: 0.5, blue: 0.15)))
    }

    /// The ice a frozen plant is locked in.
    static func iceBlock(_ ctx: GraphicsContext, base b: CGPoint, s: CGFloat, left: Double) {
        let r = CGRect(x: b.x - s * 0.42, y: b.y - s * 0.95, width: s * 0.84, height: s * 0.95)
        var g = ctx
        g.opacity = left < 1 ? 0.5 + 0.5 * left : 1
        g.fill(Path(roundedRect: r, cornerRadius: s * 0.08), with: .linearGradient(Gradient(colors: [Color(red: 0.85, green: 0.95, blue: 1).opacity(0.75), Color(red: 0.55, green: 0.78, blue: 0.95).opacity(0.6)]),
                                                                                startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.maxX, y: r.maxY)))
        g.stroke(Path(roundedRect: r, cornerRadius: s * 0.08), with: .color(.white.opacity(0.9)), lineWidth: 1.5)
        var shine = Path()
        shine.move(to: CGPoint(x: r.minX + s * 0.12, y: r.minY + s * 0.15)); shine.addLine(to: CGPoint(x: r.minX + s * 0.12, y: r.minY + s * 0.45))
        shine.move(to: CGPoint(x: r.minX + s * 0.22, y: r.minY + s * 0.12)); shine.addLine(to: CGPoint(x: r.minX + s * 0.22, y: r.minY + s * 0.25))
        g.stroke(shine, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        if left < 2.5 {
            var crack = Path()
            crack.move(to: CGPoint(x: r.midX, y: r.minY)); crack.addLine(to: CGPoint(x: r.midX + s * 0.08, y: r.minY + s * 0.25)); crack.addLine(to: CGPoint(x: r.midX - s * 0.05, y: r.minY + s * 0.42))
            g.stroke(crack, with: .color(.white), lineWidth: 1.2)
        }
    }

    /// A sandstone grave marker the pharaoh raises: it rises out of the sand and crumbles as it's shot.
    static func grave(_ ctx: GraphicsContext, base b: CGPoint, s: CGFloat, health: Double, age: Double) {
        let rise = CGFloat(min(1, age / 0.45))
        let w = s * 0.56, h = s * 0.78 * rise
        guard h > 1 else { return }
        let r = CGRect(x: b.x - w / 2, y: b.y - h, width: w, height: h)
        var stone = Path()
        stone.move(to: CGPoint(x: r.minX, y: r.maxY))
        stone.addLine(to: CGPoint(x: r.minX, y: r.minY + w * 0.5))
        stone.addArc(center: CGPoint(x: r.midX, y: r.minY + w * 0.5), radius: w / 2, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        stone.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        stone.closeSubpath()
        ctx.fill(stone, with: .linearGradient(Gradient(colors: [Color(red: 0.92, green: 0.78, blue: 0.52), Color(red: 0.72, green: 0.55, blue: 0.3)]),
                                             startPoint: CGPoint(x: r.minX, y: 0), endPoint: CGPoint(x: r.maxX, y: 0)))
        ctx.stroke(stone, with: .color(Color(red: 0.4, green: 0.26, blue: 0.1)), lineWidth: 1.4)
        // Carved glyphs: an eye and a wave.
        var carve = Path()
        let e = CGPoint(x: r.midX, y: r.minY + w * 0.55)
        carve.move(to: CGPoint(x: e.x - w * 0.22, y: e.y)); carve.addQuadCurve(to: CGPoint(x: e.x + w * 0.22, y: e.y), control: CGPoint(x: e.x, y: e.y - w * 0.2))
        carve.addQuadCurve(to: CGPoint(x: e.x - w * 0.22, y: e.y), control: CGPoint(x: e.x, y: e.y + w * 0.2))
        carve.move(to: CGPoint(x: e.x - w * 0.25, y: e.y + w * 0.42))
        for i in 0..<4 { carve.addQuadCurve(to: CGPoint(x: e.x - w * 0.25 + CGFloat(i + 1) * w * 0.125, y: e.y + w * 0.42), control: CGPoint(x: e.x - w * 0.25 + (CGFloat(i) + 0.5) * w * 0.125, y: e.y + w * 0.34)) }
        ctx.stroke(carve, with: .color(Color(red: 0.45, green: 0.3, blue: 0.12)), lineWidth: 1.3)
        ctx.fill(disc(e, w * 0.05), with: .color(Color(red: 0.45, green: 0.3, blue: 0.12)))
        if health < 0.6 {
            var crack = Path()
            crack.move(to: CGPoint(x: r.minX + w * 0.2, y: r.minY + w * 0.2)); crack.addLine(to: CGPoint(x: r.minX + w * 0.4, y: r.minY + w * 0.45)); crack.addLine(to: CGPoint(x: r.minX + w * 0.3, y: r.minY + w * 0.7))
            if health < 0.3 { crack.move(to: CGPoint(x: r.maxX - w * 0.1, y: r.midY)); crack.addLine(to: CGPoint(x: r.maxX - w * 0.35, y: r.midY + w * 0.25)) }
            ctx.stroke(crack, with: .color(Color(red: 0.3, green: 0.18, blue: 0.06)), lineWidth: 1.4)
        }
        // A heap of sand at the foot.
        ctx.fill(oval(CGPoint(x: b.x, y: b.y), w * 0.7, s * 0.06), with: .color(Color(red: 0.86, green: 0.7, blue: 0.45)))
    }

    /// Snowballs, fireballs and iceballs (they roll, so their markings turn).
    static func roller(_ ctx: GraphicsContext, at c: CGPoint, r: CGFloat, kind: LDRollerKind, spin: Double, t: Double) {
        switch kind {
        case .snowball:
            ctx.fill(disc(c, r), with: .radialGradient(Gradient(colors: [.white, Color(red: 0.82, green: 0.9, blue: 0.98), Color(red: 0.6, green: 0.72, blue: 0.88)]),
                                                     center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.35), startRadius: 0, endRadius: r * 1.4))
            var lumps = Path()
            for k in 0..<5 {
                let a = spin + Double(k) * 1.26
                lumps.addEllipse(in: CGRect(x: c.x + CGFloat(cos(a)) * r * 0.6 - r * 0.12, y: c.y + CGFloat(sin(a)) * r * 0.6 - r * 0.08, width: r * 0.24, height: r * 0.16))
            }
            ctx.fill(lumps, with: .color(Color(red: 0.62, green: 0.72, blue: 0.86)))
            ctx.stroke(disc(c, r), with: .color(Color(red: 0.22, green: 0.32, blue: 0.5)), lineWidth: 2)
        case .fireball, .iceball:
            let hot = kind == .fireball
            let core = hot ? Color(red: 1, green: 0.9, blue: 0.5) : Color(red: 0.85, green: 0.97, blue: 1)
            let mid = hot ? Color(red: 1, green: 0.45, blue: 0.08) : Color(red: 0.35, green: 0.7, blue: 1)
            let rim = hot ? Color(red: 0.7, green: 0.1, blue: 0.05) : Color(red: 0.15, green: 0.35, blue: 0.75)
            // A trail streaming behind (to the right).
            for k in 1...4 {
                let p = CGPoint(x: c.x + r * CGFloat(k) * 0.55, y: c.y + CGFloat(sin(t * 12 + Double(k))) * r * 0.12)
                ctx.fill(disc(p, r * (0.85 - CGFloat(k) * 0.16)), with: .color(mid.opacity(0.45 - Double(k) * 0.09)))
            }
            ctx.fill(disc(c, r), with: .radialGradient(Gradient(colors: [core, mid, rim]), center: CGPoint(x: c.x - r * 0.25, y: c.y - r * 0.25), startRadius: 0, endRadius: r * 1.3))
            var marks = Path()
            for k in 0..<3 {
                let a = spin + Double(k) * 2.09
                if hot {
                    marks.addEllipse(in: CGRect(x: c.x + CGFloat(cos(a)) * r * 0.5 - r * 0.12, y: c.y + CGFloat(sin(a)) * r * 0.5 - r * 0.12, width: r * 0.24, height: r * 0.24))
                } else {
                    marks.move(to: c); marks.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * r * 0.85, y: c.y + CGFloat(sin(a)) * r * 0.85))
                }
            }
            if hot { ctx.fill(marks, with: .color(Color(red: 0.75, green: 0.2, blue: 0.05).opacity(0.7))) } else { ctx.stroke(marks, with: .color(.white.opacity(0.8)), lineWidth: 1.5) }
            ctx.stroke(disc(c, r), with: .color(rim), lineWidth: 1.4)
        }
    }

    // MARK: Zombies

    /// What a world's zombies wear.
    struct Outfit {
        let coat: Color
        let pants: Color
        let shirt: Color?
        let tie: Color?
        let skin: Color
        let hat: Hat
        let pattern: Pattern
        enum Hat { case hair, wraps, bandana, cowboy, furHat, antenna }
        enum Pattern { case none, wraps, stripes, poncho, fur, suit }

        static func of(_ s: LDScene) -> Outfit {
            let skin = Color(red: 0.58, green: 0.66, blue: 0.5)
            switch s {
            case .backyard, .rooftop:
                return Outfit(coat: Color(red: 0.42, green: 0.3, blue: 0.2), pants: Color(red: 0.28, green: 0.22, blue: 0.18), shirt: Color(white: 0.92),
                              tie: Color(red: 0.82, green: 0.08, blue: 0.08), skin: skin, hat: .hair, pattern: .none)
            case .desert:
                return Outfit(coat: Color(red: 0.88, green: 0.82, blue: 0.66), pants: Color(red: 0.8, green: 0.73, blue: 0.56), shirt: nil, tie: nil,
                              skin: skin, hat: .wraps, pattern: .wraps)
            case .pirate:
                return Outfit(coat: Color(white: 0.95), pants: Color(red: 0.2, green: 0.22, blue: 0.36), shirt: nil, tie: nil,
                              skin: skin, hat: .bandana, pattern: .stripes)
            case .frontier:
                return Outfit(coat: Color(red: 0.78, green: 0.44, blue: 0.18), pants: Color(red: 0.3, green: 0.36, blue: 0.52), shirt: Color(red: 0.92, green: 0.88, blue: 0.8), tie: nil,
                              skin: skin, hat: .cowboy, pattern: .poncho)
            case .glacier:
                return Outfit(coat: Color(red: 0.48, green: 0.34, blue: 0.24), pants: Color(red: 0.36, green: 0.36, blue: 0.4), shirt: nil, tie: nil,
                              skin: Color(red: 0.6, green: 0.7, blue: 0.62), hat: .furHat, pattern: .fur)
            case .future:
                return Outfit(coat: Color(red: 0.78, green: 0.8, blue: 0.88), pants: Color(red: 0.6, green: 0.62, blue: 0.72), shirt: nil, tie: nil,
                              skin: Color(red: 0.62, green: 0.72, blue: 0.62), hat: .antenna, pattern: .suit)
            }
        }
    }

    /// A cartoon zombie shambling left, feet at `f`, `h` tall, dressed for its world. Headgear and shields
    /// show what's left of them.
    static func zombie(_ ctx: GraphicsContext, feet f0: CGPoint, h h0: CGFloat, z: LDWorld.Zombie, t: Double, scene: LDScene, cell: CGFloat) {
        var g = ctx
        var f = f0
        var h = h0
        if z.kind == .imp { h *= 0.66 }
        let look = Outfit.of(scene)
        // A jumper's vault: it sails up and over from a tile back.
        if z.hopped >= 0 && t - z.hopped < 0.45 {
            let p = CGFloat((t - z.hopped) / 0.45)
            f.x += (1 - p) * cell
            f.y -= sin(p * .pi) * h * 0.55
        }
        // Ambushers in the desert rise up out of the sand (the pirates' swing and the brain-bot's drop are
        // drawn by the boss's windup, ending where they land).
        if t - z.born < 0.5 && z.x < Double(LDWorld.cols) - 0.2 && z.hopped < 0 {
            let p = CGFloat((t - z.born) / 0.5)
            switch scene {
            case .desert:
                g.clip(to: Path(CGRect(x: f.x - h, y: f.y - h * 2, width: h * 2, height: h * 2)))
                f.y += h * (1 - p) * 0.9
            default:
                break
            }
        }
        if let died = z.died {
            let age = t - died
            if z.eaten { return }
            g.opacity = max(0, 1 - max(0, age - 0.9) / 0.6)
            if z.burnt {
                charred(g, feet: f, h: h, age: age)
                return
            }
            g.translateBy(x: f.x, y: f.y)
            g.rotate(by: .radians(min(1, age / 0.55) * .pi / 2.1))      // topples back, away from the house
            g.translateBy(x: -f.x, y: -f.y)
        }
        // Flat on its back after a banana peel, seeing stars.
        let stunned = z.died == nil && t < z.stunUntil
        if stunned {
            let into = 2.5 - (z.stunUntil - t)
            let fall = min(1, into / 0.25) * min(1, (z.stunUntil - t) / 0.3)
            g.translateBy(x: f.x, y: f.y)
            g.rotate(by: .radians(fall * .pi / 2.05))
            g.translateBy(x: -f.x, y: -f.y)
        }
        // Tints and flashes go on a layer, so each is applied once rather than per stroke.
        let chilled = t < z.slowUntil && z.died == nil, flashing = t - z.hit < 0.08
        if t < z.slowUntil && z.died == nil { g.addFilter(.colorMultiply(Color(red: 0.72, green: 0.86, blue: 1))) }
        if t - z.hit < 0.08 { g.addFilter(.brightness(0.25)) }
        if chilled || flashing {
            g.drawLayer { layer in figure(layer, feet: f, h: h, z: z, t: t, scene: scene, look: look, stunned: stunned) }
        } else {
            figure(g, feet: f, h: h, z: z, t: t, scene: scene, look: look, stunned: stunned)
        }
        if stunned {
            // Stars circling its head, drawn upright on `ctx`. They must come after the layer above has closed:
            // drawing into `ctx` from inside `g.drawLayer` is a RenderBox precondition failure (a crash).
            let into = 2.5 - (z.stunUntil - t)
            let head = CGPoint(x: f.x + h * 0.75, y: f.y - h * 0.12)
            if into > 0.2 {
                for k in 0..<3 {
                    let a = t * 5 + Double(k) * 2.1
                    starShape(ctx, at: CGPoint(x: head.x + CGFloat(cos(a)) * h * 0.14, y: head.y - h * 0.12 + CGFloat(sin(a)) * h * 0.04), r: h * 0.035)
                }
            }
        }
    }

    /// The zombie itself, once it's been placed, tilted and tinted.
    private static func figure(_ g: GraphicsContext, feet f0: CGPoint, h: CGFloat, z: LDWorld.Zombie, t: Double, scene: LDScene, look: Outfit, stunned: Bool) {
        var f = f0
        let pace = z.kind == .runner ? 5.5 : (z.kind == .imp ? 5.0 : 3.4)
        let phase = t * pace * z.speedK + Double(z.id)
        let walking = !z.eating && z.died == nil && !stunned
        let step = walking ? CGFloat(sin(phase)) : 0
        let chomp = z.eating ? CGFloat(abs(sin(t * 9 + Double(z.id)))) : 0
        let lw = max(1.2, h * 0.018)
        let springy = z.kind == .jumper && z.hopped < 0
        if springy && walking { f.y -= abs(CGFloat(sin(phase))) * h * 0.06 }
        let lean: CGFloat = z.kind == .runner ? -h * 0.1 : (z.eating ? -h * 0.05 : -h * 0.02)
        let hip = CGPoint(x: f.x + h * 0.02, y: f.y - h * (springy ? 0.48 : 0.42))
        // Legs (back then front), shoes.
        for (i, s) in [step, -step].enumerated() {
            let knee = CGPoint(x: hip.x + s * h * 0.06 - h * 0.01, y: hip.y + h * 0.21)
            let foot = CGPoint(x: hip.x + s * h * (z.kind == .runner ? 0.18 : 0.12) - h * 0.03 + CGFloat(i) * h * 0.04, y: hip.y + h * 0.4)
            var leg = Path(); leg.move(to: hip); leg.addLine(to: knee); leg.addLine(to: foot)
            g.stroke(leg, with: .color(ink), style: StrokeStyle(lineWidth: h * 0.085 + lw, lineCap: .round, lineJoin: .round))
            g.stroke(leg, with: .color(i == 0 ? look.pants.shade(0.2) : look.pants), style: StrokeStyle(lineWidth: h * 0.085, lineCap: .round, lineJoin: .round))
            g.fill(oval(CGPoint(x: foot.x - h * 0.03, y: foot.y), h * 0.07, h * 0.035), with: .color(ink))
            if z.kind == .jumper {
                // Spring boots (one sprung loose after the vault).
                var coil = Path()
                let bottom = CGPoint(x: foot.x - h * 0.03, y: foot.y + h * 0.07)
                let loose = z.hopped >= 0 && i == 1
                coil.move(to: CGPoint(x: foot.x - h * 0.03, y: foot.y + h * 0.02))
                for k in 1...4 {
                    let y = foot.y + h * 0.02 + CGFloat(k) * h * 0.0125 * (loose ? 1.8 : 1)
                    coil.addLine(to: CGPoint(x: bottom.x + (k % 2 == 0 ? -1 : 1) * h * 0.035 + (loose ? h * 0.03 * CGFloat(k) : 0), y: y))
                }
                g.stroke(coil, with: .color(Color(white: 0.55)), lineWidth: max(1, h * 0.012))
            }
        }
        // Torso.
        let shoulder = CGPoint(x: hip.x + lean, y: f.y - h * (springy ? 0.84 : 0.78))
        var torso = Path()
        torso.move(to: CGPoint(x: hip.x - h * 0.16, y: hip.y + h * 0.04))
        torso.addLine(to: CGPoint(x: shoulder.x - h * 0.19, y: shoulder.y))
        torso.addLine(to: CGPoint(x: shoulder.x + h * 0.19, y: shoulder.y))
        torso.addLine(to: CGPoint(x: hip.x + h * 0.17, y: hip.y + h * 0.04))
        torso.closeSubpath()
        // Back arm (with the flag, if any).
        let backShoulder = CGPoint(x: shoulder.x + h * 0.08, y: shoulder.y + h * 0.05)
        let reach = CGFloat(sin(phase * 0.5)) * h * 0.02
        let pump = z.kind == .runner && walking ? CGFloat(sin(phase)) * h * 0.1 : 0
        let backHand = CGPoint(x: shoulder.x - h * 0.28 + pump, y: shoulder.y + h * 0.12 + reach)
        arm(g, from: backShoulder, to: backHand, h: h, coat: look.coat.shade(0.18), skin: look.skin, lw: lw)
        if z.kind == .flag { flag(g, hand: backHand, h: h, t: t, lw: lw) }
        g.fill(torso, with: .color(look.coat))
        var deco = g
        deco.clip(to: torso)
        switch look.pattern {
        case .wraps:
            var wraps = Path()
            for k in 0..<7 {
                let y = shoulder.y + h * 0.05 + CGFloat(k) * h * 0.055
                wraps.move(to: CGPoint(x: hip.x - h * 0.25, y: y + h * 0.02)); wraps.addLine(to: CGPoint(x: hip.x + h * 0.25, y: y - h * 0.015))
            }
            deco.stroke(wraps, with: .color(Color(red: 0.62, green: 0.55, blue: 0.4)), lineWidth: max(0.8, h * 0.008))
        case .stripes:
            var stripes = Path()
            for k in 0..<5 { stripes.addRect(CGRect(x: hip.x - h * 0.3, y: shoulder.y + h * 0.04 + CGFloat(k) * h * 0.075, width: h * 0.6, height: h * 0.035)) }
            deco.fill(stripes, with: .color(Color(red: 0.82, green: 0.12, blue: 0.12)))
            deco.fill(Path(CGRect(x: hip.x - h * 0.3, y: hip.y - h * 0.02, width: h * 0.6, height: h * 0.05)), with: .color(Color(red: 0.65, green: 0.1, blue: 0.3)))
        case .poncho:
            var zig = Path()
            let y = shoulder.y + h * 0.2
            zig.move(to: CGPoint(x: hip.x - h * 0.3, y: y))
            var x = hip.x - h * 0.3
            var up = true
            while x < hip.x + h * 0.3 { x += h * 0.05; zig.addLine(to: CGPoint(x: x, y: y + (up ? -h * 0.03 : h * 0.03))); up.toggle() }
            deco.stroke(zig, with: .color(Color(red: 0.95, green: 0.85, blue: 0.4)), lineWidth: max(1, h * 0.016))
            deco.stroke(zig.offsetBy(dx: 0, dy: h * 0.12), with: .color(Color(red: 0.2, green: 0.5, blue: 0.5)), lineWidth: max(1, h * 0.016))
        case .fur:
            deco.fill(Path(CGRect(x: hip.x - h * 0.3, y: hip.y - h * 0.04, width: h * 0.6, height: h * 0.1)), with: .color(Color(red: 0.92, green: 0.9, blue: 0.84)))
            deco.fill(Path(CGRect(x: hip.x - h * 0.06, y: shoulder.y, width: h * 0.04, height: h * 0.4)), with: .color(Color(red: 0.3, green: 0.2, blue: 0.14)))
        case .suit:
            deco.fill(Path(CGRect(x: shoulder.x - h * 0.03, y: shoulder.y, width: h * 0.06, height: h * 0.4)), with: .color(Color(red: 0.2, green: 0.9, blue: 0.9)))
            deco.fill(Path(CGRect(x: hip.x - h * 0.3, y: hip.y - h * 0.02, width: h * 0.6, height: h * 0.04)), with: .color(Color(red: 0.3, green: 0.32, blue: 0.4)))
        case .none:
            break
        }
        g.stroke(torso, with: .color(ink), lineWidth: lw)
        if let shirt = look.shirt {
            var s = Path()
            s.move(to: CGPoint(x: shoulder.x - h * 0.08, y: shoulder.y)); s.addLine(to: CGPoint(x: shoulder.x + h * 0.08, y: shoulder.y))
            s.addLine(to: CGPoint(x: shoulder.x + h * 0.01, y: shoulder.y + h * 0.2)); s.closeSubpath()
            g.fill(s, with: .color(shirt))
        }
        if let tieColor = look.tie, z.kind != .imp {
            var tie = Path()
            tie.move(to: CGPoint(x: shoulder.x - h * 0.02, y: shoulder.y + h * 0.02)); tie.addLine(to: CGPoint(x: shoulder.x + h * 0.03, y: shoulder.y + h * 0.02))
            tie.addLine(to: CGPoint(x: shoulder.x + h * 0.04, y: shoulder.y + h * 0.24)); tie.addLine(to: CGPoint(x: shoulder.x, y: shoulder.y + h * 0.28))
            tie.addLine(to: CGPoint(x: shoulder.x - h * 0.03, y: shoulder.y + h * 0.23)); tie.closeSubpath()
            g.fill(tie, with: .color(tieColor))
        }
        if look.pattern == .fur {
            g.fill(oval(CGPoint(x: shoulder.x, y: shoulder.y + h * 0.01), h * 0.2, h * 0.04), with: .color(Color(red: 0.92, green: 0.9, blue: 0.84)))
        }
        // Front arm, reaching for brains — gone once the zombie is badly hurt. A shield bearer holds its shield up.
        let frontShoulder = CGPoint(x: shoulder.x - h * 0.12, y: shoulder.y + h * 0.05)
        if z.kind == .shield && z.shield > 0 {
            let hand = CGPoint(x: shoulder.x - h * 0.3, y: shoulder.y + h * 0.16)
            arm(g, from: frontShoulder, to: hand, h: h, coat: look.coat, skin: look.skin, lw: lw)
        } else if z.hp > z.kind.hp / 2 {
            let hand = CGPoint(x: shoulder.x - h * 0.38 - pump, y: shoulder.y + h * 0.08 - reach - chomp * h * 0.03)
            arm(g, from: frontShoulder, to: hand, h: h, coat: look.coat, skin: look.skin, lw: lw)
        } else {
            var stump = Path(); stump.move(to: frontShoulder); stump.addLine(to: CGPoint(x: frontShoulder.x - h * 0.06, y: frontShoulder.y + h * 0.06))
            g.stroke(stump, with: .color(ink), style: StrokeStyle(lineWidth: h * 0.07 + lw, lineCap: .round))
            g.stroke(stump, with: .color(look.coat), style: StrokeStyle(lineWidth: h * 0.07, lineCap: .round))
        }
        // Head.
        let hc = CGPoint(x: shoulder.x - h * 0.05, y: shoulder.y - h * 0.13)
        let headScale: CGFloat = z.kind == .imp ? 1.3 : 1
        zombieHead(g, at: hc, h: h * headScale, skin: look.skin, chomp: chomp, lw: lw, wraps: look.hat == .wraps)
        // Headgear, dented as it wears; without any, the world's hat.
        let worn = z.kind.armor > 0 ? z.armor / z.kind.armor : 0
        if z.kind == .cone && z.armor > 0 {
            cone(g, head: hc, h: h, worn: worn, lw: lw)
        } else if z.kind == .bucket && z.armor > 0 {
            bucket(g, head: hc, h: h, worn: worn, lw: lw, scene: scene)
        } else if z.kind == .runner && z.armor > 0 {
            helmet(g, head: hc, h: h, worn: worn, lw: lw, scene: scene)
        } else {
            hat(g, look.hat, head: hc, h: h * headScale, lw: lw, t: t, id: z.id)
        }
        if z.kind == .shield && z.shield > 0 {
            shield(g, hand: CGPoint(x: shoulder.x - h * 0.33, y: shoulder.y + h * 0.16), h: h, health: z.shield / z.kind.shield, scene: scene, lw: lw)
        }
    }

    static func starShape(_ ctx: GraphicsContext, at c: CGPoint, r: CGFloat) {
        var s = Path()
        for i in 0..<10 {
            let a = Double(i) / 10 * 2 * .pi - .pi / 2
            let rr = i % 2 == 0 ? r : r * 0.45
            let p = CGPoint(x: c.x + CGFloat(cos(a)) * rr, y: c.y + CGFloat(sin(a)) * rr)
            if i == 0 { s.move(to: p) } else { s.addLine(to: p) }
        }
        s.closeSubpath()
        ctx.fill(s, with: .color(Color(red: 1, green: 0.9, blue: 0.2)))
        ctx.stroke(s, with: .color(ink), lineWidth: 0.8)
    }

    private static func flag(_ g: GraphicsContext, hand: CGPoint, h: CGFloat, t: Double, lw: CGFloat) {
        var pole = Path(); pole.move(to: CGPoint(x: hand.x, y: hand.y + h * 0.1)); pole.addLine(to: CGPoint(x: hand.x + h * 0.02, y: hand.y - h * 0.62))
        g.stroke(pole, with: .color(Color(red: 0.45, green: 0.3, blue: 0.15)), style: StrokeStyle(lineWidth: h * 0.025, lineCap: .round))
        let top = CGPoint(x: hand.x + h * 0.02, y: hand.y - h * 0.62)
        let wave = CGFloat(sin(t * 6)) * h * 0.02
        var cloth = Path()
        cloth.move(to: top); cloth.addLine(to: CGPoint(x: top.x + h * 0.32, y: top.y + h * 0.03 + wave))
        cloth.addLine(to: CGPoint(x: top.x + h * 0.27, y: top.y + h * 0.12 + wave)); cloth.addLine(to: CGPoint(x: top.x + h * 0.31, y: top.y + h * 0.21 + wave))
        cloth.addLine(to: CGPoint(x: top.x, y: top.y + h * 0.2))
        cloth.closeSubpath()
        g.fill(cloth, with: .color(Color(red: 0.82, green: 0.12, blue: 0.1)))
        g.stroke(cloth, with: .color(ink), lineWidth: lw * 0.8)
        // A grabbing green hand on it.
        let c = CGPoint(x: top.x + h * 0.14, y: top.y + h * 0.11 + wave * 0.5)
        var palm = Path(ellipseIn: CGRect(x: c.x - h * 0.035, y: c.y - h * 0.01, width: h * 0.07, height: h * 0.06))
        for k in 0..<4 { palm.addRoundedRect(in: CGRect(x: c.x - h * 0.035 + CGFloat(k) * h * 0.019, y: c.y - h * 0.055, width: h * 0.013, height: h * 0.05), cornerSize: CGSize(width: 2, height: 2)) }
        g.fill(palm, with: .color(Color(red: 0.62, green: 0.75, blue: 0.5)))
    }

    private static func cone(_ g: GraphicsContext, head hc: CGPoint, h: CGFloat, worn: Double, lw: CGFloat) {
        var cone = Path()
        cone.move(to: CGPoint(x: hc.x - h * 0.15, y: hc.y - h * 0.07))
        cone.addLine(to: CGPoint(x: hc.x + h * 0.02 + (worn < 0.5 ? h * 0.05 : 0), y: hc.y - h * 0.42))
        cone.addLine(to: CGPoint(x: hc.x + h * 0.17, y: hc.y - h * 0.06))
        cone.closeSubpath()
        g.fill(cone, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.62, blue: 0.2), Color(red: 0.9, green: 0.4, blue: 0.05)]),
                                          startPoint: CGPoint(x: hc.x - h * 0.15, y: 0), endPoint: CGPoint(x: hc.x + h * 0.17, y: 0)))
        var stripes = Path()
        for y in [0.17, 0.27] as [CGFloat] {
            stripes.move(to: CGPoint(x: hc.x - h * (0.12 - y * 0.25), y: hc.y - h * y))
            stripes.addLine(to: CGPoint(x: hc.x + h * (0.14 - y * 0.3), y: hc.y - h * y))
        }
        g.stroke(stripes, with: .color(.white.opacity(0.85)), lineWidth: h * 0.03)
        g.stroke(cone, with: .color(ink), lineWidth: lw)
        g.fill(oval(CGPoint(x: hc.x + h * 0.01, y: hc.y - h * 0.06), h * 0.2, h * 0.035), with: .color(Color(red: 0.85, green: 0.35, blue: 0.05)))
    }

    private static func bucket(_ g: GraphicsContext, head hc: CGPoint, h: CGFloat, worn: Double, lw: CGFloat, scene: LDScene) {
        let top = hc.y - h * 0.3
        var pail = Path()
        pail.move(to: CGPoint(x: hc.x - h * 0.17, y: hc.y - h * 0.02))
        pail.addLine(to: CGPoint(x: hc.x - h * 0.13, y: top))
        pail.addLine(to: CGPoint(x: hc.x + h * 0.13, y: top))
        pail.addLine(to: CGPoint(x: hc.x + h * 0.17, y: hc.y - h * 0.02))
        pail.closeSubpath()
        // The future's buckets are chrome domes with a light; everyone else wears a tin pail.
        let colors = scene == .future ? [Color(red: 0.6, green: 0.95, blue: 1), Color(red: 0.3, green: 0.5, blue: 0.7), Color(red: 0.5, green: 0.85, blue: 0.95)]
                                      : [Color(white: 0.82), Color(white: 0.55), Color(white: 0.72)]
        g.fill(pail, with: .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: hc.x - h * 0.17, y: 0), endPoint: CGPoint(x: hc.x + h * 0.17, y: 0)))
        g.stroke(pail, with: .color(ink), lineWidth: lw)
        g.fill(oval(CGPoint(x: hc.x, y: top), h * 0.13, h * 0.025), with: .color(Color(white: 0.45)))
        if worn < 0.5 {
            var dent = Path(); dent.move(to: CGPoint(x: hc.x - h * 0.06, y: top + h * 0.06)); dent.addLine(to: CGPoint(x: hc.x - h * 0.01, y: top + h * 0.12))
            dent.addLine(to: CGPoint(x: hc.x + h * 0.05, y: top + h * 0.08))
            g.stroke(dent, with: .color(Color(white: 0.3)), lineWidth: lw)
        }
    }

    /// A runner's sports helmet with a face guard.
    private static func helmet(_ g: GraphicsContext, head hc: CGPoint, h: CGFloat, worn: Double, lw: CGFloat, scene: LDScene) {
        let shell = Color(red: 0.2, green: 0.3, blue: 0.75)
        var dome = Path()
        dome.addArc(center: CGPoint(x: hc.x + h * 0.01, y: hc.y - h * 0.02), radius: h * 0.18, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        dome.addLine(to: CGPoint(x: hc.x + h * 0.19, y: hc.y + h * 0.05))
        dome.addLine(to: CGPoint(x: hc.x + h * 0.08, y: hc.y + h * 0.06))
        dome.addLine(to: CGPoint(x: hc.x - h * 0.17, y: hc.y - h * 0.02))
        dome.closeSubpath()
        g.fill(dome, with: .linearGradient(Gradient(colors: [shell.lit(0.3), shell, shell.shade(0.3)]), startPoint: CGPoint(x: hc.x, y: hc.y - h * 0.2), endPoint: CGPoint(x: hc.x, y: hc.y + h * 0.05)))
        g.stroke(dome, with: .color(ink), lineWidth: lw)
        var stripe = Path()
        stripe.move(to: CGPoint(x: hc.x - h * 0.12, y: hc.y - h * 0.14)); stripe.addQuadCurve(to: CGPoint(x: hc.x + h * 0.16, y: hc.y - h * 0.08), control: CGPoint(x: hc.x + h * 0.04, y: hc.y - h * 0.22))
        g.stroke(stripe, with: .color(.white), lineWidth: h * 0.025)
        var guardBars = Path()
        guardBars.move(to: CGPoint(x: hc.x - h * 0.16, y: hc.y + h * 0.0)); guardBars.addLine(to: CGPoint(x: hc.x - h * 0.2, y: hc.y + h * 0.1))
        guardBars.move(to: CGPoint(x: hc.x - h * 0.2, y: hc.y + h * 0.05)); guardBars.addLine(to: CGPoint(x: hc.x - h * 0.04, y: hc.y + h * 0.07))
        g.stroke(guardBars, with: .color(Color(white: 0.85)), lineWidth: max(1, h * 0.014))
        if worn < 0.5 {
            var crack = Path(); crack.move(to: CGPoint(x: hc.x - h * 0.02, y: hc.y - h * 0.18)); crack.addLine(to: CGPoint(x: hc.x + h * 0.03, y: hc.y - h * 0.1)); crack.addLine(to: CGPoint(x: hc.x, y: hc.y - h * 0.05))
            g.stroke(crack, with: .color(ink), lineWidth: lw * 0.8)
        }
    }

    /// The world's shield: a bin lid, a sarcophagus lid, a barrel end, a saloon door, an ice slab or an energy shield.
    private static func shield(_ g: GraphicsContext, hand: CGPoint, h: CGFloat, health: Double, scene: LDScene, lw: CGFloat) {
        let w = h * 0.2, ht = h * 0.48
        let r = CGRect(x: hand.x - w * 0.75, y: hand.y - ht * 0.55, width: w, height: ht)
        var shape: Path
        let fill: GraphicsContext.Shading
        let edge: Color
        switch scene {
        case .desert:
            shape = Path(roundedRect: r, cornerRadius: w * 0.45)
            fill = .linearGradient(Gradient(colors: [Color(red: 0.95, green: 0.78, blue: 0.3), Color(red: 0.75, green: 0.55, blue: 0.15)]), startPoint: CGPoint(x: r.minX, y: 0), endPoint: CGPoint(x: r.maxX, y: 0))
            edge = Color(red: 0.4, green: 0.25, blue: 0.05)
        case .pirate:
            shape = Path(ellipseIn: CGRect(x: r.minX - w * 0.1, y: r.midY - w * 0.9, width: w * 1.2, height: w * 1.8))
            fill = .color(Color(red: 0.6, green: 0.38, blue: 0.18))
            edge = Color(red: 0.25, green: 0.14, blue: 0.05)
        case .frontier:
            shape = Path(roundedRect: r, cornerRadius: 2)
            fill = .color(Color(red: 0.62, green: 0.42, blue: 0.22))
            edge = Color(red: 0.3, green: 0.18, blue: 0.06)
        case .glacier:
            shape = Path(roundedRect: r, cornerRadius: w * 0.15)
            fill = .linearGradient(Gradient(colors: [Color(red: 0.85, green: 0.95, blue: 1).opacity(0.9), Color(red: 0.55, green: 0.78, blue: 0.95).opacity(0.85)]), startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.maxX, y: r.maxY))
            edge = .white
        case .future:
            shape = Path(roundedRect: r, cornerRadius: w * 0.3)
            fill = .color(Color(red: 0.3, green: 0.95, blue: 1).opacity(0.45))
            edge = Color(red: 0.4, green: 1, blue: 1)
        case .backyard, .rooftop:
            shape = Path(ellipseIn: CGRect(x: r.minX - w * 0.1, y: r.midY - w * 0.95, width: w * 1.2, height: w * 1.9))
            fill = .linearGradient(Gradient(colors: [Color(white: 0.85), Color(white: 0.55)]), startPoint: CGPoint(x: r.minX, y: 0), endPoint: CGPoint(x: r.maxX, y: 0))
            edge = ink
        }
        g.fill(shape, with: fill)
        var detail = Path()
        switch scene {
        case .desert:
            detail.addEllipse(in: CGRect(x: r.midX - w * 0.25, y: r.minY + ht * 0.18, width: w * 0.5, height: w * 0.5))
            detail.move(to: CGPoint(x: r.minX + w * 0.15, y: r.midY + ht * 0.1)); detail.addLine(to: CGPoint(x: r.maxX - w * 0.15, y: r.midY + ht * 0.1))
            detail.move(to: CGPoint(x: r.minX + w * 0.15, y: r.midY + ht * 0.25)); detail.addLine(to: CGPoint(x: r.maxX - w * 0.15, y: r.midY + ht * 0.25))
        case .pirate:
            detail.move(to: CGPoint(x: r.minX - w * 0.05, y: r.midY - w * 0.4)); detail.addLine(to: CGPoint(x: r.maxX + w * 0.05, y: r.midY - w * 0.4))
            detail.move(to: CGPoint(x: r.minX - w * 0.05, y: r.midY + w * 0.4)); detail.addLine(to: CGPoint(x: r.maxX + w * 0.05, y: r.midY + w * 0.4))
        case .frontier:
            for k in 1..<4 { detail.move(to: CGPoint(x: r.minX + 2, y: r.minY + ht * CGFloat(k) / 4)); detail.addLine(to: CGPoint(x: r.maxX - 2, y: r.minY + ht * CGFloat(k) / 4)) }
        case .backyard, .rooftop:
            detail.addEllipse(in: CGRect(x: r.midX - w * 0.2, y: r.midY - w * 0.12, width: w * 0.4, height: w * 0.24))
        default:
            break
        }
        g.stroke(detail, with: .color(edge.opacity(0.7)), lineWidth: max(1, lw * 0.8))
        if health < 0.67 {
            var crack = Path()
            crack.move(to: CGPoint(x: r.midX, y: r.minY + ht * 0.1)); crack.addLine(to: CGPoint(x: r.midX - w * 0.2, y: r.minY + ht * 0.35)); crack.addLine(to: CGPoint(x: r.midX + w * 0.1, y: r.midY))
            if health < 0.34 { crack.move(to: CGPoint(x: r.minX + w * 0.1, y: r.maxY - ht * 0.2)); crack.addLine(to: CGPoint(x: r.midX, y: r.maxY - ht * 0.35)) }
            g.stroke(crack, with: .color(scene == .glacier || scene == .future ? .white : ink), lineWidth: max(1, lw))
        }
        g.stroke(shape, with: .color(edge), lineWidth: lw)
    }

    private static func hat(_ g: GraphicsContext, _ hat: Outfit.Hat, head c: CGPoint, h: CGFloat, lw: CGFloat, t: Double, id: Int) {
        let rx = h * 0.15, ry = h * 0.165
        switch hat {
        case .hair:
            var hair = Path()
            for k in 0..<3 {
                let x = c.x - rx * 0.2 + CGFloat(k) * rx * 0.25
                hair.move(to: CGPoint(x: x, y: c.y - ry * 0.95))
                hair.addQuadCurve(to: CGPoint(x: x + rx * 0.2, y: c.y - ry * 1.3), control: CGPoint(x: x - rx * 0.15, y: c.y - ry * 1.25))
            }
            g.stroke(hair, with: .color(ink), lineWidth: lw * 0.8)
        case .wraps:
            break       // drawn with the head
        case .bandana:
            var band = Path()
            band.addArc(center: c, radius: rx * 1.02, startAngle: .degrees(190), endAngle: .degrees(350), clockwise: false)
            band.closeSubpath()
            g.fill(band, with: .color(Color(red: 0.82, green: 0.12, blue: 0.12)))
            g.stroke(band, with: .color(ink), lineWidth: lw * 0.8)
            var knot = Path()
            knot.move(to: CGPoint(x: c.x + rx * 0.95, y: c.y - ry * 0.3))
            knot.addLine(to: CGPoint(x: c.x + rx * 1.5, y: c.y - ry * 0.1 + CGFloat(sin(t * 5 + Double(id))) * ry * 0.1))
            knot.addLine(to: CGPoint(x: c.x + rx * 1.45, y: c.y + ry * 0.2))
            knot.closeSubpath()
            g.fill(knot, with: .color(Color(red: 0.7, green: 0.08, blue: 0.08)))
            var dots = Path()
            for k in 0..<3 { dots.addEllipse(in: CGRect(x: c.x - rx * 0.6 + CGFloat(k) * rx * 0.45, y: c.y - ry * 0.75, width: rx * 0.14, height: rx * 0.14)) }
            g.fill(dots, with: .color(.white))
        case .cowboy:
            let brimY = c.y - ry * 0.7
            g.fill(oval(CGPoint(x: c.x, y: brimY), rx * 1.75, ry * 0.22), with: .color(Color(red: 0.5, green: 0.32, blue: 0.16)))
            g.stroke(oval(CGPoint(x: c.x, y: brimY), rx * 1.75, ry * 0.22), with: .color(ink), lineWidth: lw * 0.8)
            var crown = Path()
            crown.move(to: CGPoint(x: c.x - rx * 0.85, y: brimY))
            crown.addLine(to: CGPoint(x: c.x - rx * 0.7, y: brimY - ry * 0.85))
            crown.addQuadCurve(to: CGPoint(x: c.x + rx * 0.7, y: brimY - ry * 0.85), control: CGPoint(x: c.x, y: brimY - ry * 0.6))
            crown.addLine(to: CGPoint(x: c.x + rx * 0.85, y: brimY))
            crown.closeSubpath()
            g.fill(crown, with: .color(Color(red: 0.58, green: 0.38, blue: 0.2)))
            g.stroke(crown, with: .color(ink), lineWidth: lw * 0.8)
            g.fill(Path(CGRect(x: c.x - rx * 0.82, y: brimY - ry * 0.25, width: rx * 1.64, height: ry * 0.18)), with: .color(Color(red: 0.25, green: 0.15, blue: 0.08)))
        case .furHat:
            g.fill(oval(CGPoint(x: c.x, y: c.y - ry * 0.75), rx * 1.12, ry * 0.55), with: .color(Color(red: 0.55, green: 0.38, blue: 0.24)))
            g.fill(oval(CGPoint(x: c.x, y: c.y - ry * 0.5), rx * 1.18, ry * 0.25), with: .color(Color(red: 0.92, green: 0.9, blue: 0.84)))
            for side in [-1.0, 1.0] as [CGFloat] {
                g.fill(oval(CGPoint(x: c.x + side * rx * 0.95, y: c.y - ry * 0.05), rx * 0.25, ry * 0.42), with: .color(Color(red: 0.55, green: 0.38, blue: 0.24)))
            }
        case .antenna:
            g.fill(Path(CGRect(x: c.x - rx * 1.02, y: c.y - ry * 0.55, width: rx * 2.04, height: ry * 0.22)), with: .color(Color(red: 0.35, green: 0.38, blue: 0.48)))
            var stalk = Path()
            stalk.move(to: CGPoint(x: c.x + rx * 0.3, y: c.y - ry * 0.55)); stalk.addLine(to: CGPoint(x: c.x + rx * 0.45, y: c.y - ry * 1.5))
            g.stroke(stalk, with: .color(Color(white: 0.4)), lineWidth: max(1, lw * 0.8))
            let blink = 0.5 + 0.5 * sin(t * 6 + Double(id))
            g.fill(disc(CGPoint(x: c.x + rx * 0.45, y: c.y - ry * 1.55), rx * 0.2), with: .color(Color(red: 1, green: 0.25 + 0.3 * blink, blue: 0.4)))
        }
    }

    private static func arm(_ g: GraphicsContext, from a: CGPoint, to hand: CGPoint, h: CGFloat, coat: Color, skin: Color, lw: CGFloat) {
        let elbow = CGPoint(x: (a.x + hand.x) / 2, y: (a.y + hand.y) / 2 + h * 0.03)
        var sleeve = Path(); sleeve.move(to: a); sleeve.addLine(to: elbow); sleeve.addLine(to: hand)
        g.stroke(sleeve, with: .color(ink), style: StrokeStyle(lineWidth: h * 0.075 + lw, lineCap: .round, lineJoin: .round))
        g.stroke(sleeve, with: .color(coat), style: StrokeStyle(lineWidth: h * 0.075, lineCap: .round, lineJoin: .round))
        g.fill(oval(hand, h * 0.045, h * 0.038), with: .color(ink))
        g.fill(oval(hand, h * 0.036, h * 0.03), with: .color(skin))
    }

    private static func zombieHead(_ g: GraphicsContext, at c: CGPoint, h: CGFloat, skin: Color, chomp: CGFloat, lw: CGFloat, wraps: Bool) {
        let rx = h * 0.15, ry = h * 0.165
        let head = oval(c, rx, ry)
        g.fill(head, with: .radialGradient(Gradient(colors: [skin.lit(0.15), skin, skin.shade(0.2)]),
                                          center: CGPoint(x: c.x - rx * 0.3, y: c.y - ry * 0.4), startRadius: 0, endRadius: ry * 1.4))
        if wraps {
            // A mummy's bandages, leaving one eye and the mouth.
            var band = g
            band.clip(to: head)
            band.fill(head, with: .color(Color(red: 0.9, green: 0.85, blue: 0.7)))
            var lines = Path()
            for k in 0..<6 {
                let y = c.y - ry + CGFloat(k) * ry * 0.38
                lines.move(to: CGPoint(x: c.x - rx * 1.2, y: y + ry * 0.12)); lines.addLine(to: CGPoint(x: c.x + rx * 1.2, y: y - ry * 0.08))
            }
            band.stroke(lines, with: .color(Color(red: 0.62, green: 0.55, blue: 0.4)), lineWidth: max(0.8, lw * 0.7))
        }
        g.stroke(head, with: .color(ink), lineWidth: lw)
        // Eyes: one big and staring, one droopy (a mummy's droopy one is wrapped over).
        let big = CGPoint(x: c.x - rx * 0.42, y: c.y - ry * 0.2)
        g.fill(disc(big, rx * 0.34), with: .color(.white)); g.stroke(disc(big, rx * 0.34), with: .color(ink), lineWidth: lw * 0.8)
        g.fill(disc(CGPoint(x: big.x - rx * 0.08, y: big.y + rx * 0.04), rx * 0.09), with: .color(ink))
        if !wraps {
            let small = CGPoint(x: c.x + rx * 0.22, y: c.y - ry * 0.16)
            g.fill(oval(small, rx * 0.24, rx * 0.2), with: .color(.white)); g.stroke(oval(small, rx * 0.24, rx * 0.2), with: .color(ink), lineWidth: lw * 0.8)
            g.fill(disc(CGPoint(x: small.x - rx * 0.05, y: small.y + rx * 0.05), rx * 0.07), with: .color(ink))
            var lid = Path(); lid.move(to: CGPoint(x: small.x - rx * 0.26, y: small.y - rx * 0.06)); lid.addLine(to: CGPoint(x: small.x + rx * 0.26, y: small.y - rx * 0.1))
            g.stroke(lid, with: .color(ink), lineWidth: lw)
        }
        // Gaping mouth with a couple of teeth; it chomps while eating.
        let mouthTop = c.y + ry * 0.38
        let open = ry * (0.2 + 0.25 * chomp)
        var mouth = Path()
        mouth.addRoundedRect(in: CGRect(x: c.x - rx * 0.62, y: mouthTop, width: rx * 0.7, height: open), cornerSize: CGSize(width: rx * 0.15, height: rx * 0.15))
        g.fill(mouth, with: .color(Color(red: 0.2, green: 0.08, blue: 0.08)))
        g.fill(Path(CGRect(x: c.x - rx * 0.5, y: mouthTop, width: rx * 0.14, height: open * 0.4)), with: .color(Color(white: 0.95)))
        g.fill(Path(CGRect(x: c.x - rx * 0.24, y: mouthTop, width: rx * 0.12, height: open * 0.35)), with: .color(Color(white: 0.95)))
        g.stroke(mouth, with: .color(ink), lineWidth: lw * 0.8)
    }

    /// A zombie caught in a blast: a charred silhouette that crumbles to ash.
    private static func charred(_ g: GraphicsContext, feet f: CGPoint, h: CGFloat, age: Double) {
        let crumble = CGFloat(min(1, max(0, (age - 0.4) / 0.6)))
        let ash = Color(white: 0.12)
        let top = f.y - h * 0.95 * (1 - crumble * 0.85)
        var body = Path()
        body.addRoundedRect(in: CGRect(x: f.x - h * 0.16, y: top, width: h * 0.34, height: f.y - top), cornerSize: CGSize(width: h * 0.08, height: h * 0.08))
        g.fill(body, with: .color(ash))
        if crumble < 0.5 {
            g.fill(disc(CGPoint(x: f.x - h * 0.06, y: top + h * 0.12), h * 0.035), with: .color(.white.opacity(0.9)))
            g.fill(disc(CGPoint(x: f.x + h * 0.04, y: top + h * 0.12), h * 0.028), with: .color(.white.opacity(0.9)))
        }
        g.fill(oval(CGPoint(x: f.x, y: f.y), h * 0.25 * (0.5 + crumble), h * 0.05), with: .color(ash.opacity(0.7)))
    }

    // MARK: Small things

    static func pea(_ ctx: GraphicsContext, at c: CGPoint, r: CGFloat, shot: LDShot, t: Double) {
        switch shot {
        case .pea:
            ctx.fill(disc(c, r), with: .radialGradient(Gradient(colors: [Color(red: 0.75, green: 1, blue: 0.45), Color(red: 0.36, green: 0.78, blue: 0.12)]),
                                                     center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.35), startRadius: 0, endRadius: r * 1.3))
            ctx.stroke(disc(c, r), with: .color(leafDark), lineWidth: 1.2)
        case .popcorn:
            popcorn(ctx, at: c, r: r * 1.05, spin: t * 8)
        case .frost:
            ctx.fill(disc(c, r * 1.5), with: .radialGradient(Gradient(colors: [Color(red: 0.8, green: 0.95, blue: 1).opacity(0.6), .clear]), center: c, startRadius: r * 0.5, endRadius: r * 1.5))
            ctx.fill(disc(c, r), with: .radialGradient(Gradient(colors: [Color(red: 0.75, green: 0.85, blue: 1), Color(red: 0.3, green: 0.36, blue: 0.85)]),
                                                     center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.35), startRadius: 0, endRadius: r * 1.3))
            snowflake(ctx, at: c, r: r * 0.6)
        case .melon:
            melonBall(ctx, at: c, r: r * 1.2)
        }
    }

    static func splat(_ ctx: GraphicsContext, at c: CGPoint, r: CGFloat, age: Double, shot: LDShot) {
        if shot == .melon { melonSplash(ctx, at: c, r: r * 1.6, age: age); return }
        var g = ctx
        g.opacity = max(0, 1 - age / 0.35)
        let k = CGFloat(0.6 + age * 2.5)
        let color: Color
        switch shot {
        case .pea: color = Color(red: 0.5, green: 0.85, blue: 0.2)
        case .popcorn: color = Color(red: 1, green: 0.95, blue: 0.8)
        case .frost: color = Color(red: 0.75, green: 0.9, blue: 1)
        case .melon: color = Color(red: 0.95, green: 0.3, blue: 0.35)
        }
        for i in 0..<6 {
            let a = Double(i) / 6 * 2 * .pi + 0.4
            g.fill(disc(CGPoint(x: c.x + CGFloat(cos(a)) * r * k, y: c.y + CGFloat(sin(a)) * r * k * 0.8), r * 0.35), with: .color(color))
        }
        g.fill(disc(c, r * 0.6), with: .color(color.lit(0.2)))
    }

    /// A melon landing: red pulp and seeds.
    static func melonSplash(_ ctx: GraphicsContext, at c: CGPoint, r: CGFloat, age: Double) {
        var g = ctx
        g.opacity = max(0, 1 - age / 0.35)
        let k = CGFloat(0.6 + age * 3)
        for i in 0..<8 {
            let a = Double(i) / 8 * 2 * .pi
            g.fill(disc(CGPoint(x: c.x + CGFloat(cos(a)) * r * k, y: c.y + CGFloat(sin(a)) * r * k * 0.7), r * 0.32), with: .color(Color(red: 0.95, green: 0.3, blue: 0.35)))
        }
        g.fill(disc(c, r * 0.7), with: .color(Color(red: 0.98, green: 0.45, blue: 0.45)))
        var seeds = Path()
        for i in 0..<4 { seeds.addEllipse(in: CGRect(x: c.x + CGFloat(i - 2) * r * 0.3, y: c.y - r * 0.1 + CGFloat(i % 2) * r * 0.2, width: r * 0.14, height: r * 0.2)) }
        g.fill(seeds, with: .color(ink))
    }

    static func sun(_ ctx: GraphicsContext, at c: CGPoint, r: CGFloat, t: Double, fade: Double = 1) {
        var g = ctx
        g.opacity = fade
        g.fill(disc(c, r * 1.7), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.4).opacity(0.55), Color(red: 1, green: 0.85, blue: 0.2).opacity(0)]),
                                                     center: c, startRadius: r * 0.5, endRadius: r * 1.7))
        var rays = Path()
        for i in 0..<12 {
            let a = Double(i) / 12 * 2 * .pi + t * 0.7
            let p1 = CGPoint(x: c.x + CGFloat(cos(a - 0.12)) * r * 0.85, y: c.y + CGFloat(sin(a - 0.12)) * r * 0.85)
            let p2 = CGPoint(x: c.x + CGFloat(cos(a)) * r * 1.35, y: c.y + CGFloat(sin(a)) * r * 1.35)
            let p3 = CGPoint(x: c.x + CGFloat(cos(a + 0.12)) * r * 0.85, y: c.y + CGFloat(sin(a + 0.12)) * r * 0.85)
            rays.move(to: p1); rays.addLine(to: p2); rays.addLine(to: p3); rays.closeSubpath()
        }
        g.fill(rays, with: .color(Color(red: 1, green: 0.85, blue: 0.15)))
        g.fill(disc(c, r), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 1, blue: 0.75), Color(red: 1, green: 0.85, blue: 0.15), Color(red: 1, green: 0.62, blue: 0.05)]),
                                               center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.3), startRadius: 0, endRadius: r * 1.3))
    }

    static func mower(_ ctx: GraphicsContext, at c: CGPoint, s: CGFloat) {
        var handle = Path()
        handle.move(to: CGPoint(x: c.x - s * 0.2, y: c.y - s * 0.05)); handle.addLine(to: CGPoint(x: c.x - s * 0.5, y: c.y - s * 0.42))
        handle.addLine(to: CGPoint(x: c.x - s * 0.42, y: c.y - s * 0.48))
        ctx.stroke(handle, with: .color(ink), style: StrokeStyle(lineWidth: s * 0.06, lineCap: .round, lineJoin: .round))
        let body = CGRect(x: c.x - s * 0.28, y: c.y - s * 0.16, width: s * 0.56, height: s * 0.24)
        ctx.fill(Path(roundedRect: body, cornerRadius: s * 0.08), with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.32, blue: 0.25), Color(red: 0.7, green: 0.06, blue: 0.05)]),
                                                                                    startPoint: CGPoint(x: 0, y: body.minY), endPoint: CGPoint(x: 0, y: body.maxY)))
        ctx.stroke(Path(roundedRect: body, cornerRadius: s * 0.08), with: .color(ink), lineWidth: 1.2)
        ctx.fill(Path(roundedRect: CGRect(x: c.x - s * 0.1, y: body.minY - s * 0.12, width: s * 0.22, height: s * 0.14), cornerRadius: s * 0.03), with: .color(Color(white: 0.55)))
        ctx.stroke(Path(roundedRect: CGRect(x: c.x - s * 0.1, y: body.minY - s * 0.12, width: s * 0.22, height: s * 0.14), cornerRadius: s * 0.03), with: .color(ink), lineWidth: 1)
        for dx in [-0.18, 0.2] as [CGFloat] {
            let w = CGPoint(x: c.x + dx * s, y: body.maxY)
            ctx.fill(disc(w, s * 0.1), with: .color(ink))
            ctx.fill(disc(w, s * 0.04), with: .color(Color(white: 0.6)))
        }
    }

    // MARK: The live scene

    static func scene(_ ctx: GraphicsContext, world w: LDWorld, lay: LDLayout, selected: LDPlantKind?) {
        let cw = lay.cellW, ch = lay.cellH
        // Free tiles light up while a seed is in hand.
        if selected != nil {
            var hint = Path()
            for r in w.params.rows where lay.rows.contains(r) {
                for c in 0..<LDWorld.cols where w.plant(at: r, c) == nil && w.grave(at: r, c) == nil && !w.bossCovers(r, c) {
                    let p = lay.point(x: Double(c), y: Double(r))
                    hint.addRoundedRect(in: CGRect(x: p.x + 3, y: p.y + 3, width: cw - 6, height: ch - 6), cornerSize: CGSize(width: 6, height: 6))
                }
            }
            ctx.fill(hint, with: .color(.white.opacity(0.13)))
        }
        // What the boss is winding up to, marked on the lawn.
        if let b = w.boss { LDBossArt.underlay(ctx, boss: b, world: w, lay: lay) }
        // Everything standing on the lawn, washed in the world's light (dusk, night, neon) as one layer.
        if let tint = LDLook.of(w.params.scene).sprite {
            var tinted = ctx
            tinted.addFilter(.colorMultiply(tint))
            tinted.drawLayer { layer in sprites(layer, world: w, lay: lay) }
        } else {
            sprites(ctx, world: w, lay: lay)
        }
        // Shots, blasts and splashes on top.
        for p in w.peas where lay.rows.contains(p.row) { pea(ctx, at: lay.point(x: p.x, y: Double(p.row) + 0.36), r: cw * 0.11, shot: p.shot, t: w.t) }
        for s in w.splats where lay.rows.contains(s.row) { splat(ctx, at: lay.point(x: s.x, y: Double(s.row) + 0.36), r: cw * 0.12, age: w.t - s.t, shot: s.shot) }
        for b in w.booms where lay.rows.contains(b.row) {
            boom(ctx, at: lay.point(x: Double(b.col) + 0.5, y: Double(b.row) + 0.5), cell: cw, age: w.t - b.t)
        }
        for f in w.blazes where lay.rows.contains(f.row) { blaze(ctx, lay: lay, row: f.row, age: w.t - f.t) }
        for c in w.crashes where lay.rows.contains(c.row) { crash(ctx, at: lay.point(x: Double(c.col) + 0.5, y: Double(c.row) + 0.85), cell: cw, age: w.t - c.t) }
        // Melons in flight.
        for l in w.lobs {
            let p = CGFloat(min(1, (w.t - l.t0) / LDWorld.lobTime))
            let a = lay.point(x: l.x0, y: Double(l.row) + 0.3), b = lay.point(x: l.x1, y: Double(l.row) + 0.4)
            let c = CGPoint(x: a.x + (b.x - a.x) * p, y: a.y + (b.y - a.y) * p - sin(p * .pi) * ch * 1.1)
            melonBall(ctx, at: c, r: cw * 0.13)
        }
        if let b = w.boss { LDBossArt.overlay(ctx, boss: b, world: w, lay: lay) }
        // Suns float above everything; they blink before they fade.
        for s in w.suns {
            let fade = s.life < 1.5 ? (Int(s.life * 8) % 2 == 0 ? 0.45 : 1) : 1
            sun(ctx, at: lay.point(x: s.x, y: s.y), r: cw * 0.3, t: w.t + Double(s.id), fade: fade)
        }
    }

    /// Mowers, graves, plants, rolling balls, zombies and the boss, lane by lane from the back.
    private static func sprites(_ ctx: GraphicsContext, world w: LDWorld, lay: LDLayout) {
        let cw = lay.cellW, ch = lay.cellH
        let scene = w.params.scene
        let ps = min(cw * 1.05, ch * 0.74)
        let zh = min(ch * 1.22, cw * 1.9)
        let bossBottom: Int? = w.boss.map { b in b.kind.span > 1 ? Int(ceil(b.y - 0.001)) + b.kind.span - 1 : -1 }
        for r in lay.rows {
            // The lane's mower.
            switch w.mowers[r] {
            case .ready: mower(ctx, at: lay.point(x: -0.36, y: Double(r) + 0.66), s: cw * 0.9)
            case .running(let x): mower(ctx, at: lay.point(x: x, y: Double(r) + 0.66), s: cw * 0.9)
            case .gone: break
            }
            for gv in w.graves where gv.row == r {
                grave(ctx, base: lay.point(x: Double(gv.col) + 0.5, y: Double(r) + 0.9), s: ps, health: gv.hp / 8, age: w.t - gv.born)
            }
            // Plants.
            for p in w.plants where p.row == r {
                let b = lay.point(x: Double(p.col) + 0.5, y: Double(r) + 0.9)
                let seed = Double(p.id) * 1.7
                let wince = w.t - p.bitten < 0.25
                let t = p.frozen > 0 ? p.planted : w.t
                switch p.kind {
                case .sunflower: sunflower(ctx, base: b, s: ps, t: t, seed: seed, wince: wince)
                case .peashooter: peashooter(ctx, base: b, s: ps, t: t, seed: seed, recoil: w.t - p.fired)
                case .popper: popper(ctx, base: b, s: ps, t: t, seed: seed, recoil: w.t - p.fired)
                case .frost: frostBerry(ctx, base: b, s: ps, t: t, seed: seed, recoil: w.t - p.fired)
                case .lobber: lobber(ctx, base: b, s: ps, t: t, seed: seed, fired: w.t - p.fired)
                case .wallnut: wallnut(ctx, base: b, s: ps, health: p.hp / LDPlantKind.wallnut.bites, wince: wince)
                case .peel: peel(ctx, base: b, s: ps, arm: p.timer <= 0 ? 1 : 1 - p.timer / LDWorld.peelArm, t: w.t)
                case .flytrap:
                    // The zombie it just snapped up is drawn in its jaws until it's gone down.
                    let prey = w.zombies.first { $0.eaten && $0.row == r && $0.died == p.gulp }.map { z in
                        Prey(zombie: z, feet: lay.point(x: z.x + 0.3, y: Double(r) + 0.92), h: z.kind == .imp ? zh * 0.66 : zh, scene: scene)
                    }
                    flytrap(ctx, base: b, s: ps, t: t, seed: seed, chewing: p.chewing, gulp: p.gulp, prey: prey)
                case .cherry: cherry(ctx, base: b, s: ps, fuse: 1 - max(0, p.timer) / 1.1, t: w.t)
                case .chili: chili(ctx, base: b, s: ps, fuse: 1 - max(0, p.timer) / 0.8, t: w.t)
                }
                if p.frozen > 0 { iceBlock(ctx, base: b, s: ps, left: p.frozen) }
            }
            // Rolling balls.
            for rl in w.rollers where rl.row == r {
                let rr = cw * 0.42
                let c = lay.point(x: rl.x + 0.42, y: Double(r) + 0.9)
                ctx.fill(oval(CGPoint(x: c.x, y: c.y), rr * 0.95, rr * 0.25), with: .color(.black.opacity(0.25)))
                roller(ctx, at: CGPoint(x: c.x, y: c.y - rr), r: rr, kind: rl.kind, spin: -rl.x * 2.4, t: w.t)
            }
            // Zombies (and a walking boss), back to front.
            var walkers: [(x: Double, draw: () -> Void)] = []
            for z in w.zombies where z.row == r {
                walkers.append((z.x, { zombie(ctx, feet: lay.point(x: z.x + 0.3, y: Double(r) + 0.92), h: zh, z: z, t: w.t, scene: scene, cell: cw) }))
            }
            if let b = w.boss, b.kind.span == 1, Int(b.y.rounded()) == r {
                walkers.append((b.x, { LDBossArt.draw(ctx, boss: b, world: w, lay: lay) }))
            }
            for item in walkers.sorted(by: { $0.x > $1.x }) { item.draw() }
            // A standing boss in front of its lanes.
            if let b = w.boss, b.kind.span > 1, bossBottom == r { LDBossArt.draw(ctx, boss: b, world: w, lay: lay) }
        }
        if let b = w.boss, b.kind.span > 1, let bottom = bossBottom, !lay.rows.contains(bottom) { LDBossArt.draw(ctx, boss: b, world: w, lay: lay) }
        // The imp being flung, tumbling through the air.
        for d in w.drops {
            let p = CGFloat(min(1, (w.t - d.t0) / (d.lands - d.t0)))
            let a = lay.point(x: d.fromX, y: Double(d.row) + 0.2), b = lay.point(x: d.x + 0.3, y: Double(d.row) + 0.92)
            let c = CGPoint(x: a.x + (b.x - a.x) * p, y: a.y + (b.y - a.y) * p - sin(p * .pi) * ch * 1.6)
            var g = ctx
            g.translateBy(x: c.x, y: c.y)
            g.rotate(by: .radians(Double(p) * 4 * .pi))
            g.translateBy(x: -c.x, y: -c.y)
            let fake = LDWorld.Zombie(id: d.id, kind: .imp, row: d.row, x: d.x, hp: 3, armor: 0, shield: 0, speedK: 1, born: -9)
            zombie(g, feet: CGPoint(x: c.x, y: c.y + zh * 0.33), h: zh, z: fake, t: w.t, scene: scene, cell: cw)
        }
    }

    /// The flag meter: a zombie head creeps along as the horde arrives; the flag marks the final rush and
    /// the boss waits at the end.
    static func flagMeter(_ ctx: GraphicsContext, size s: CGSize, progress: Double, rushAt: Double, boss: LDBossKind?) {
        let bar = CGRect(x: s.height * 0.6, y: s.height * 0.22, width: s.width - s.height * 1.1, height: s.height * 0.56)
        ctx.fill(Path(roundedRect: bar, cornerRadius: bar.height / 2), with: .color(Color(red: 0.16, green: 0.1, blue: 0.05)))
        let fill = CGRect(x: bar.maxX - bar.width * CGFloat(progress), y: bar.minY, width: bar.width * CGFloat(progress), height: bar.height)
        ctx.fill(Path(roundedRect: fill, cornerRadius: bar.height / 2), with: .linearGradient(Gradient(colors: [Color(red: 0.55, green: 0.9, blue: 0.2), Color(red: 0.25, green: 0.6, blue: 0.08)]),
                                                                                         startPoint: CGPoint(x: 0, y: fill.minY), endPoint: CGPoint(x: 0, y: fill.maxY)))
        ctx.stroke(Path(roundedRect: bar, cornerRadius: bar.height / 2), with: .color(Color(red: 0.55, green: 0.38, blue: 0.18)), lineWidth: 1.5)
        // The rush flag.
        let fx = bar.maxX - bar.width * CGFloat(rushAt)
        var pole = Path(); pole.move(to: CGPoint(x: fx, y: bar.maxY)); pole.addLine(to: CGPoint(x: fx, y: 0))
        ctx.stroke(pole, with: .color(Color(white: 0.85)), lineWidth: 1.2)
        var flag = Path()
        flag.move(to: CGPoint(x: fx, y: 0)); flag.addLine(to: CGPoint(x: fx + s.height * 0.6, y: s.height * 0.12)); flag.addLine(to: CGPoint(x: fx, y: s.height * 0.32)); flag.closeSubpath()
        ctx.fill(flag, with: .color(Color(red: 0.86, green: 0.14, blue: 0.1)))
        // The boss waiting at the end.
        if let k = boss { LDBossArt.icon(ctx, kind: k, at: CGPoint(x: bar.minX - s.height * 0.05, y: s.height / 2), r: s.height * 0.48) }
        // The zombie head.
        let hx = bar.maxX - bar.width * CGFloat(progress)
        let hr = s.height * 0.48
        let hc = CGPoint(x: hx, y: s.height / 2)
        ctx.fill(disc(hc, hr), with: .color(Color(red: 0.58, green: 0.66, blue: 0.5)))
        ctx.stroke(disc(hc, hr), with: .color(ink), lineWidth: 1.2)
        ctx.fill(disc(CGPoint(x: hc.x - hr * 0.35, y: hc.y - hr * 0.15), hr * 0.3), with: .color(.white))
        ctx.fill(disc(CGPoint(x: hc.x - hr * 0.38, y: hc.y - hr * 0.12), hr * 0.1), with: .color(ink))
        ctx.fill(Path(CGRect(x: hc.x - hr * 0.5, y: hc.y + hr * 0.35, width: hr * 0.6, height: hr * 0.18)), with: .color(ink))
    }

    /// The boss's health bar: red draining to the left, its face at the end.
    static func bossMeter(_ ctx: GraphicsContext, size s: CGSize, boss b: LDWorld.Boss, t: Double) {
        let bar = CGRect(x: s.height * 0.7, y: s.height * 0.18, width: s.width - s.height * 0.9, height: s.height * 0.64)
        ctx.fill(Path(roundedRect: bar, cornerRadius: bar.height / 2), with: .color(Color(red: 0.16, green: 0.05, blue: 0.05)))
        let k = CGFloat(max(0, b.hp / b.maxHP))
        let fill = CGRect(x: bar.minX, y: bar.minY, width: bar.width * k, height: bar.height)
        let flash = t - b.hit < 0.08
        ctx.fill(Path(roundedRect: fill, cornerRadius: bar.height / 2), with: .linearGradient(Gradient(colors: flash ? [.white, Color(red: 1, green: 0.7, blue: 0.6)] : [Color(red: 1, green: 0.42, blue: 0.3), Color(red: 0.75, green: 0.08, blue: 0.08)]),
                                                                                         startPoint: CGPoint(x: 0, y: fill.minY), endPoint: CGPoint(x: 0, y: fill.maxY)))
        ctx.stroke(Path(roundedRect: bar, cornerRadius: bar.height / 2), with: .color(Color(red: 0.95, green: 0.8, blue: 0.4)), lineWidth: 1.5)
        LDBossArt.icon(ctx, kind: b.kind, at: CGPoint(x: bar.minX - s.height * 0.05, y: s.height / 2), r: s.height * 0.48)
    }
}
