//
//  LawnDefenseBosses.swift
//  A Banana Game
//
//  Lawn Defense's seven bosses, all original designs: the groundskeeper (a hulking zombie in overalls with
//  a garden shovel and an imp in his bib pocket), the pharaoh (a towering mummy king with a golden crook),
//  the captain (a zombie pirate on the bow of his ship, with a cannon), the outlaw's locomotive, the woolly
//  mammoth and its caveman rider, the mech (a chrome walker with a laser arm and a missile pod) and the
//  brain-bot (a brain in a glass dome on three legs, with a fire-and-ice cannon and a claw). Plus what they
//  telegraph on the lawn, what they throw, and the little faces on the health bar.
//

import SwiftUI

enum LDBossArt {
    static let ink = LDLawnArt.ink

    private static func disc(_ c: CGPoint, _ r: CGFloat) -> Path { LDLawnArt.disc(c, r) }
    private static func oval(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> Path { LDLawnArt.oval(c, rx, ry) }

    /// Where a boss stands on screen.
    struct Frame {
        let front: CGFloat      // x of its front edge
        let ground: CGFloat     // y of the bottom of its lowest lane
        let top: CGFloat        // y of the top of its top lane
        let cw: CGFloat
        let ch: CGFloat
        var lanes: CGFloat { ground - top }
    }

    static func frame(_ b: LDWorld.Boss, _ lay: LDLayout) -> Frame {
        let span = Double(b.kind.span)
        return Frame(front: lay.point(x: b.x, y: 0).x, ground: lay.point(x: 0, y: b.y + span - 0.06).y,
                     top: lay.point(x: 0, y: b.y).y, cw: lay.cellW, ch: lay.cellH)
    }

    /// How far into its windup the boss is (0…1), or nil.
    static func windup(_ b: LDWorld.Boss) -> (LDBossMove, Double)? {
        guard let m = b.move else { return nil }
        return (m, max(0, min(1, 1 - b.windup / m.windup)))
    }

    // MARK: Drawing a boss

    static func draw(_ ctx: GraphicsContext, boss b: LDWorld.Boss, world w: LDWorld, lay: LDLayout) {
        var g = ctx
        let t = w.t
        if let d = b.died {
            let age = t - d
            guard age < 2.8 else { return }
            if age < 0.9 {
                g.translateBy(x: CGFloat(sin(age * 70)) * lay.cellW * 0.06, y: 0)
            } else {
                let k = min(1, (age - 0.9) / 1.1)
                let pivot = b.kind.span == 1 ? lay.point(x: b.x + 0.5, y: b.y + 0.92) : lay.point(x: b.x + 2.2, y: b.y + Double(b.kind.span))
                g.translateBy(x: pivot.x, y: pivot.y)
                g.rotate(by: .radians(k * 0.55))
                g.translateBy(x: -pivot.x, y: -pivot.y)
                g.opacity = max(0, 1 - max(0, age - 1.7) / 1.1)
            }
        }
        let stunned = b.died == nil && t < b.stunUntil
        if stunned { g.translateBy(x: CGFloat(sin(t * 18)) * lay.cellW * 0.03, y: 0) }
        // A hit brightens the whole boss a touch (on a layer, so the filter runs once). It's under fire most
        // of the fight, so the flash stays subtle.
        if t - b.hit < 0.06 && b.died == nil {
            g.addFilter(.brightness(0.1))
            g.drawLayer { layer in figure(layer, b, lay, t) }
        } else {
            figure(g, b, lay, t)
        }
        if let d = b.died { smoke(ctx, boss: b, lay: lay, age: t - d) }
        if stunned {
            let head = b.kind.span == 1 ? lay.point(x: b.x + 0.45, y: b.y - 0.6) : lay.point(x: b.x + 0.9, y: b.y - 0.35)
            for k in 0..<4 {
                let a = t * 4 + Double(k) * 1.57
                LDLawnArt.starShape(ctx, at: CGPoint(x: head.x + CGFloat(cos(a)) * lay.cellW * 0.45, y: head.y + CGFloat(sin(a)) * lay.cellW * 0.12), r: lay.cellW * 0.1)
            }
        }
    }

    private static func figure(_ g: GraphicsContext, _ b: LDWorld.Boss, _ lay: LDLayout, _ t: Double) {
        switch b.kind {
        case .groundskeeper: groundskeeper(g, b, lay, t)
        case .pharaoh: pharaoh(g, b, frame(b, lay), t)
        case .captain: captain(g, b, frame(b, lay), t)
        case .outlaw: locomotive(g, b, frame(b, lay), t)
        case .mammoth: mammoth(g, b, frame(b, lay), t)
        case .mech: mech(g, b, frame(b, lay), t)
        case .megabot: brainBot(g, b, frame(b, lay), t)
        }
    }

    /// Smoke and sparks while a beaten boss shakes apart.
    private static func smoke(_ ctx: GraphicsContext, boss b: LDWorld.Boss, lay: LDLayout, age: Double) {
        let c = b.kind.span == 1 ? lay.point(x: b.x + 0.5, y: b.y - 0.1) : lay.point(x: b.x + 1.1, y: b.y + Double(b.kind.span) * 0.4)
        var g = ctx
        g.opacity = max(0, 1 - age / 2.6)
        for i in 0..<9 {
            let a = Double(i) * 0.7
            let rise = CGFloat(age) * lay.cellW * (0.6 + 0.2 * CGFloat(i % 3))
            let p = CGPoint(x: c.x + CGFloat(cos(a * 3)) * lay.cellW * 0.9 * CGFloat(LDLawnArt.hash(Double(i))), y: c.y - rise - CGFloat(i) * lay.cellW * 0.1)
            g.fill(disc(p, lay.cellW * (0.25 + 0.2 * CGFloat(age))), with: .color(Color(white: 0.25 + 0.1 * Double(i % 3)).opacity(0.55)))
        }
        if age < 0.9 {
            for i in 0..<5 {
                let p = CGPoint(x: c.x + CGFloat(LDLawnArt.hash(Double(i) + age) - 0.5) * lay.cellW * 2, y: c.y + CGFloat(LDLawnArt.hash(Double(i) * 2 + age) - 0.5) * lay.cellW * 2)
                LDLawnArt.starShape(ctx, at: p, r: lay.cellW * 0.07)
            }
        }
    }

    // MARK: The groundskeeper (backyard)

    private static func groundskeeper(_ g: GraphicsContext, _ b: LDWorld.Boss, _ lay: LDLayout, _ t: Double) {
        let f = lay.point(x: b.x + 0.45, y: b.y + 0.92)
        let H = min(lay.cellH * 1.22, lay.cellW * 1.9) * 1.55
        let walking = b.mode == .walking && b.windup <= 0 && b.died == nil && t >= b.stunUntil
        let phase = t * 2.2
        let step = walking ? CGFloat(sin(phase)) : 0
        let lw = max(1.4, H * 0.012)
        let skin = Color(red: 0.55, green: 0.64, blue: 0.47)
        let denim = Color(red: 0.24, green: 0.38, blue: 0.62)
        let shirt = Color(red: 0.88, green: 0.86, blue: 0.74)
        let hip = CGPoint(x: f.x + H * 0.02, y: f.y - H * 0.4 - abs(step) * H * 0.015)
        // Legs and boots.
        for (i, s) in [step, -step].enumerated() {
            let foot = CGPoint(x: hip.x + s * H * 0.09 - H * 0.02 + CGFloat(i) * H * 0.07, y: f.y - H * 0.03)
            var leg = Path(); leg.move(to: hip); leg.addLine(to: CGPoint(x: (hip.x + foot.x) / 2 + H * 0.01, y: (hip.y + foot.y) / 2)); leg.addLine(to: foot)
            g.stroke(leg, with: .color(ink), style: StrokeStyle(lineWidth: H * 0.13 + lw, lineCap: .round, lineJoin: .round))
            g.stroke(leg, with: .color(i == 0 ? denim.shade(0.25) : denim), style: StrokeStyle(lineWidth: H * 0.13, lineCap: .round, lineJoin: .round))
            g.fill(Path(roundedRect: CGRect(x: foot.x - H * 0.1, y: foot.y - H * 0.02, width: H * 0.15, height: H * 0.06), cornerRadius: H * 0.02), with: .color(Color(red: 0.3, green: 0.18, blue: 0.08)))
        }
        // The great belly: undershirt, overall bib and straps.
        let shoulder = CGPoint(x: hip.x - H * 0.03, y: f.y - H * 0.8)
        var body = Path()
        body.move(to: CGPoint(x: hip.x - H * 0.2, y: hip.y + H * 0.04))
        body.addCurve(to: CGPoint(x: shoulder.x - H * 0.2, y: shoulder.y), control1: CGPoint(x: hip.x - H * 0.34, y: hip.y - H * 0.12), control2: CGPoint(x: shoulder.x - H * 0.3, y: shoulder.y + H * 0.1))
        body.addLine(to: CGPoint(x: shoulder.x + H * 0.2, y: shoulder.y))
        body.addCurve(to: CGPoint(x: hip.x + H * 0.2, y: hip.y + H * 0.04), control1: CGPoint(x: shoulder.x + H * 0.28, y: shoulder.y + H * 0.14), control2: CGPoint(x: hip.x + H * 0.26, y: hip.y - H * 0.1))
        body.closeSubpath()
        // Back arm.
        let backHand = CGPoint(x: shoulder.x + H * 0.18, y: shoulder.y + H * 0.34 + step * H * 0.02)
        limb(g, from: CGPoint(x: shoulder.x + H * 0.14, y: shoulder.y + H * 0.04), to: backHand, w: H * 0.1, cover: shirt.shade(0.2), skin: skin, lw: lw)
        g.fill(body, with: .color(shirt))
        var stains = Path()
        stains.addEllipse(in: CGRect(x: shoulder.x - H * 0.1, y: shoulder.y + H * 0.08, width: H * 0.06, height: H * 0.04))
        stains.addEllipse(in: CGRect(x: shoulder.x + H * 0.06, y: shoulder.y + H * 0.15, width: H * 0.05, height: H * 0.035))
        g.fill(stains, with: .color(Color(red: 0.6, green: 0.55, blue: 0.35).opacity(0.6)))
        var bib = Path()
        bib.move(to: CGPoint(x: hip.x - H * 0.22, y: hip.y - H * 0.08))
        bib.addLine(to: CGPoint(x: shoulder.x - H * 0.12, y: shoulder.y + H * 0.17))
        bib.addLine(to: CGPoint(x: shoulder.x + H * 0.12, y: shoulder.y + H * 0.17))
        bib.addLine(to: CGPoint(x: hip.x + H * 0.22, y: hip.y - H * 0.08))
        bib.addLine(to: CGPoint(x: hip.x + H * 0.2, y: hip.y + H * 0.04))
        bib.addLine(to: CGPoint(x: hip.x - H * 0.2, y: hip.y + H * 0.04))
        bib.closeSubpath()
        var clipped = g
        clipped.clip(to: body)
        clipped.fill(bib, with: .color(denim))
        var straps = Path()
        straps.move(to: CGPoint(x: shoulder.x - H * 0.1, y: shoulder.y + H * 0.17)); straps.addLine(to: CGPoint(x: shoulder.x - H * 0.13, y: shoulder.y - H * 0.01))
        straps.move(to: CGPoint(x: shoulder.x + H * 0.1, y: shoulder.y + H * 0.17)); straps.addLine(to: CGPoint(x: shoulder.x + H * 0.13, y: shoulder.y - H * 0.01))
        clipped.stroke(straps, with: .color(denim), lineWidth: H * 0.04)
        clipped.fill(disc(CGPoint(x: shoulder.x - H * 0.1, y: shoulder.y + H * 0.17), H * 0.018), with: .color(Color(red: 0.95, green: 0.8, blue: 0.3)))
        clipped.fill(disc(CGPoint(x: shoulder.x + H * 0.1, y: shoulder.y + H * 0.17), H * 0.018), with: .color(Color(red: 0.95, green: 0.8, blue: 0.3)))
        // The bib pocket, with the imp peeking out until it's flung.
        let pocket = CGRect(x: shoulder.x - H * 0.08, y: shoulder.y + H * 0.24, width: H * 0.16, height: H * 0.1)
        if !b.threw {
            let ic = CGPoint(x: pocket.midX - H * 0.01, y: pocket.minY - H * 0.035)
            g.fill(oval(ic, H * 0.045, H * 0.042), with: .color(skin))
            g.stroke(oval(ic, H * 0.045, H * 0.042), with: .color(ink), lineWidth: lw * 0.7)
            g.fill(disc(CGPoint(x: ic.x - H * 0.015, y: ic.y - H * 0.005), H * 0.012), with: .color(.white))
            g.fill(disc(CGPoint(x: ic.x - H * 0.017, y: ic.y - H * 0.004), H * 0.005), with: .color(ink))
            g.fill(Path(CGRect(x: ic.x - H * 0.05, y: ic.y - H * 0.045, width: H * 0.08, height: H * 0.02)), with: .color(Color(red: 0.8, green: 0.15, blue: 0.1)))
        }
        clipped.fill(Path(roundedRect: pocket, cornerRadius: H * 0.01), with: .color(denim.shade(0.15)))
        clipped.stroke(Path(roundedRect: pocket, cornerRadius: H * 0.01), with: .color(ink.opacity(0.6)), lineWidth: lw * 0.7)
        g.stroke(body, with: .color(ink), lineWidth: lw)
        // Head: small for the body, big underbite, straw hat.
        let hc = CGPoint(x: shoulder.x - H * 0.05, y: shoulder.y - H * 0.08)
        let hr = H * 0.1
        g.fill(oval(hc, hr, hr * 1.05), with: .radialGradient(Gradient(colors: [skin.lit(0.15), skin, skin.shade(0.2)]), center: CGPoint(x: hc.x - hr * 0.3, y: hc.y - hr * 0.3), startRadius: 0, endRadius: hr * 1.4))
        g.stroke(oval(hc, hr, hr * 1.05), with: .color(ink), lineWidth: lw)
        let eye = CGPoint(x: hc.x - hr * 0.42, y: hc.y - hr * 0.15)
        g.fill(disc(eye, hr * 0.28), with: .color(.white)); g.stroke(disc(eye, hr * 0.28), with: .color(ink), lineWidth: lw * 0.7)
        g.fill(disc(CGPoint(x: eye.x - hr * 0.07, y: eye.y + hr * 0.03), hr * 0.1), with: .color(ink))
        var brow = Path(); brow.move(to: CGPoint(x: eye.x - hr * 0.35, y: eye.y - hr * 0.42)); brow.addLine(to: CGPoint(x: eye.x + hr * 0.4, y: eye.y - hr * 0.22))
        g.stroke(brow, with: .color(ink), lineWidth: lw * 1.2)
        var jaw = Path()
        jaw.addRoundedRect(in: CGRect(x: hc.x - hr * 0.95, y: hc.y + hr * 0.35, width: hr * 1.1, height: hr * 0.5), cornerSize: CGSize(width: hr * 0.2, height: hr * 0.2))
        g.fill(jaw, with: .color(skin.shade(0.1))); g.stroke(jaw, with: .color(ink), lineWidth: lw * 0.8)
        var teeth = Path()
        for k in 0..<3 { teeth.move(to: CGPoint(x: hc.x - hr * 0.85 + CGFloat(k) * hr * 0.35, y: hc.y + hr * 0.4)); teeth.addLine(to: CGPoint(x: hc.x - hr * 0.78 + CGFloat(k) * hr * 0.35, y: hc.y + hr * 0.18)); teeth.addLine(to: CGPoint(x: hc.x - hr * 0.7 + CGFloat(k) * hr * 0.35, y: hc.y + hr * 0.4)) }
        g.fill(teeth, with: .color(Color(white: 0.95)))
        let brimY = hc.y - hr * 0.65
        g.fill(oval(CGPoint(x: hc.x, y: brimY), hr * 2.1, hr * 0.32), with: .color(Color(red: 0.92, green: 0.8, blue: 0.45)))
        g.stroke(oval(CGPoint(x: hc.x, y: brimY), hr * 2.1, hr * 0.32), with: .color(Color(red: 0.55, green: 0.42, blue: 0.15)), lineWidth: lw * 0.8)
        var crown = Path()
        crown.addRoundedRect(in: CGRect(x: hc.x - hr * 0.85, y: brimY - hr * 0.75, width: hr * 1.7, height: hr * 0.8), cornerSize: CGSize(width: hr * 0.35, height: hr * 0.35))
        g.fill(crown, with: .color(Color(red: 0.95, green: 0.84, blue: 0.5)))
        g.stroke(crown, with: .color(Color(red: 0.55, green: 0.42, blue: 0.15)), lineWidth: lw * 0.8)
        g.fill(Path(CGRect(x: hc.x - hr * 0.85, y: brimY - hr * 0.22, width: hr * 1.7, height: hr * 0.16)), with: .color(Color(red: 0.75, green: 0.2, blue: 0.15)))
        var fray = Path()
        for k in 0..<6 { let x = hc.x - hr * 2 + CGFloat(k) * hr * 0.75; fray.move(to: CGPoint(x: x, y: brimY + hr * 0.2)); fray.addLine(to: CGPoint(x: x - hr * 0.1, y: brimY + hr * 0.42)) }
        g.stroke(fray, with: .color(Color(red: 0.7, green: 0.55, blue: 0.25)), lineWidth: lw * 0.6)
        // The shovel: carried low, raised overhead while it winds up, slammed down on the smash.
        let rest = -0.35, raised = 1.9, slam = -0.8
        var angle = rest
        if b.windup > 0 { angle = rest + (raised - rest) * min(1, (0.8 - b.windup) / 0.6) }
        if t - b.smashed < 0.25 { angle = slam }
        let grip = CGPoint(x: shoulder.x - H * 0.14, y: shoulder.y + H * 0.06)
        let hand = CGPoint(x: grip.x - H * 0.16 * CGFloat(cos(angle)), y: grip.y + H * 0.16 * CGFloat(sin(-angle)) + H * 0.1)
        let dir = CGPoint(x: -CGFloat(cos(angle)), y: -CGFloat(sin(angle)))
        let end = CGPoint(x: hand.x + dir.x * H * 0.55, y: hand.y + dir.y * H * 0.55)
        var handle = Path(); handle.move(to: CGPoint(x: hand.x - dir.x * H * 0.15, y: hand.y - dir.y * H * 0.15)); handle.addLine(to: end)
        g.stroke(handle, with: .color(ink), style: StrokeStyle(lineWidth: H * 0.035 + lw, lineCap: .round))
        g.stroke(handle, with: .color(Color(red: 0.65, green: 0.45, blue: 0.22)), style: StrokeStyle(lineWidth: H * 0.035, lineCap: .round))
        let n = CGPoint(x: -dir.y, y: dir.x)
        var blade = Path()
        blade.move(to: CGPoint(x: end.x + n.x * H * 0.07, y: end.y + n.y * H * 0.07))
        blade.addLine(to: CGPoint(x: end.x + dir.x * H * 0.2 + n.x * H * 0.06, y: end.y + dir.y * H * 0.2 + n.y * H * 0.06))
        blade.addQuadCurve(to: CGPoint(x: end.x + dir.x * H * 0.2 - n.x * H * 0.06, y: end.y + dir.y * H * 0.2 - n.y * H * 0.06), control: CGPoint(x: end.x + dir.x * H * 0.3, y: end.y + dir.y * H * 0.3))
        blade.addLine(to: CGPoint(x: end.x - n.x * H * 0.07, y: end.y - n.y * H * 0.07))
        blade.closeSubpath()
        g.fill(blade, with: .linearGradient(Gradient(colors: [Color(white: 0.8), Color(white: 0.5)]), startPoint: end, endPoint: CGPoint(x: end.x + dir.x * H * 0.25, y: end.y + dir.y * H * 0.25)))
        g.stroke(blade, with: .color(ink), lineWidth: lw)
        limb(g, from: CGPoint(x: shoulder.x - H * 0.14, y: shoulder.y + H * 0.04), to: hand, w: H * 0.1, cover: shirt, skin: skin, lw: lw)
    }

    /// A thick arm (sleeve then a big hand).
    private static func limb(_ g: GraphicsContext, from a: CGPoint, to hand: CGPoint, w: CGFloat, cover: Color, skin: Color, lw: CGFloat) {
        let elbow = CGPoint(x: (a.x + hand.x) / 2, y: (a.y + hand.y) / 2 + w * 0.3)
        var arm = Path(); arm.move(to: a); arm.addLine(to: elbow); arm.addLine(to: hand)
        g.stroke(arm, with: .color(ink), style: StrokeStyle(lineWidth: w + lw, lineCap: .round, lineJoin: .round))
        g.stroke(arm, with: .color(skin), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        var sleeve = Path(); sleeve.move(to: a); sleeve.addLine(to: CGPoint(x: a.x + (elbow.x - a.x) * 0.5, y: a.y + (elbow.y - a.y) * 0.5))
        g.stroke(sleeve, with: .color(cover), style: StrokeStyle(lineWidth: w * 1.05, lineCap: .round))
        g.fill(disc(hand, w * 0.62), with: .color(ink))
        g.fill(disc(hand, w * 0.52), with: .color(skin))
    }

    // MARK: The pharaoh (desert)

    private static func pharaoh(_ g: GraphicsContext, _ b: LDWorld.Boss, _ f: Frame, _ t: Double) {
        let cw = f.cw, L = f.lanes
        let wu = windup(b)
        let bob = CGFloat(sin(t * 1.6)) * f.ch * 0.03
        let cx = f.front + cw * 1.05
        let wrap = Color(red: 0.9, green: 0.84, blue: 0.68), wrapLine = Color(red: 0.6, green: 0.52, blue: 0.38)
        let gold = Color(red: 0.98, green: 0.78, blue: 0.22), blue = Color(red: 0.12, green: 0.28, blue: 0.72)
        let lw = max(1.5, cw * 0.035)
        let waist = f.ground - L * 0.42 + bob
        let shoulders = f.ground - L * 0.82 + bob
        // Robe and legs, wrapped.
        var robe = Path()
        robe.move(to: CGPoint(x: cx - cw * 0.82, y: f.ground))
        robe.addLine(to: CGPoint(x: cx - cw * 0.72, y: waist))
        robe.addLine(to: CGPoint(x: cx + cw * 0.72, y: waist))
        robe.addLine(to: CGPoint(x: cx + cw * 0.82, y: f.ground))
        robe.closeSubpath()
        g.fill(robe, with: .color(wrap.shade(0.08)))
        var bands = Path()
        var y = waist + L * 0.05
        while y < f.ground { bands.move(to: CGPoint(x: cx - cw * 0.62, y: y)); bands.addLine(to: CGPoint(x: cx + cw * 0.62, y: y - L * 0.03)); y += L * 0.06 }
        var rc = g
        rc.clip(to: robe)
        rc.stroke(bands, with: .color(wrapLine), lineWidth: 1)
        rc.fill(Path(CGRect(x: cx - cw * 0.12, y: waist, width: cw * 0.24, height: f.ground - waist)), with: .linearGradient(Gradient(colors: [gold, blue, gold, blue, gold]),
                                                                                                                         startPoint: CGPoint(x: 0, y: waist), endPoint: CGPoint(x: 0, y: f.ground)))
        g.stroke(robe, with: .color(ink), lineWidth: lw)
        // Torso.
        var torso = Path()
        torso.move(to: CGPoint(x: cx - cw * 0.72, y: waist))
        torso.addLine(to: CGPoint(x: cx - cw * 1.0, y: shoulders))
        torso.addLine(to: CGPoint(x: cx + cw * 1.0, y: shoulders))
        torso.addLine(to: CGPoint(x: cx + cw * 0.72, y: waist))
        torso.closeSubpath()
        g.fill(torso, with: .color(wrap))
        var tc = g
        tc.clip(to: torso)
        var tb = Path()
        y = shoulders
        while y < waist { tb.move(to: CGPoint(x: cx - cw, y: y + L * 0.02)); tb.addLine(to: CGPoint(x: cx + cw, y: y - L * 0.02)); y += L * 0.055 }
        tc.stroke(tb, with: .color(wrapLine), lineWidth: 1)
        g.stroke(torso, with: .color(ink), lineWidth: lw)
        g.fill(Path(CGRect(x: cx - cw * 0.76, y: waist - L * 0.03, width: cw * 1.52, height: L * 0.05)), with: .color(gold))
        // The broad collar.
        var collar = Path()
        collar.addArc(center: CGPoint(x: cx, y: shoulders), radius: cw * 0.78, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        collar.closeSubpath()
        g.fill(collar, with: .color(gold))
        for (k, col) in [blue, Color(red: 0.8, green: 0.15, blue: 0.15), blue].enumerated() {
            var ring = Path()
            ring.addArc(center: CGPoint(x: cx, y: shoulders), radius: cw * (0.3 + CGFloat(k) * 0.17), startAngle: .degrees(5), endAngle: .degrees(175), clockwise: false)
            g.stroke(ring, with: .color(col), lineWidth: cw * 0.07)
        }
        g.stroke(collar, with: .color(ink), lineWidth: lw)
        // Arms: the crook arm rises for graves; both arms rise to call a sandstorm.
        var raise = 0.0
        if let (m, p) = wu { raise = m == .graves ? (p < 0.85 ? p / 0.85 : 1 - (p - 0.85) / 0.15 * 1.2) : (m == .ambush ? min(1, p * 1.5) : 0.3 * p) }
        let fShoulder = CGPoint(x: cx - cw * 0.84, y: shoulders + L * 0.05)
        let fHand = CGPoint(x: fShoulder.x - cw * 0.35, y: fShoulder.y + L * 0.2 - CGFloat(raise) * L * 0.45)
        let bShoulder = CGPoint(x: cx + cw * 0.84, y: shoulders + L * 0.05)
        let bRaise = wu?.0 == .ambush ? raise : 0
        let bHand = CGPoint(x: bShoulder.x + cw * 0.3, y: bShoulder.y + L * 0.22 - CGFloat(bRaise) * L * 0.5)
        limb(g, from: bShoulder, to: bHand, w: cw * 0.36, cover: wrap, skin: wrap, lw: lw)
        // The golden crook.
        var staff = Path()
        staff.move(to: CGPoint(x: fHand.x, y: fHand.y + L * 0.32)); staff.addLine(to: CGPoint(x: fHand.x, y: fHand.y - L * 0.32))
        staff.addArc(center: CGPoint(x: fHand.x - cw * 0.14, y: fHand.y - L * 0.32), radius: cw * 0.14, startAngle: .degrees(0), endAngle: .degrees(200), clockwise: true)
        g.stroke(staff, with: .color(ink), style: StrokeStyle(lineWidth: cw * 0.1 + lw, lineCap: .round))
        g.stroke(staff, with: .linearGradient(Gradient(colors: [gold, blue, gold, blue, gold, blue]), startPoint: CGPoint(x: 0, y: fHand.y - L * 0.4), endPoint: CGPoint(x: 0, y: fHand.y + L * 0.32)),
                 style: StrokeStyle(lineWidth: cw * 0.1, lineCap: .round))
        limb(g, from: fShoulder, to: fHand, w: cw * 0.36, cover: wrap, skin: wrap, lw: lw)
        // Head: wrapped face under a striped headdress, eyes aglow.
        let hc = CGPoint(x: cx - cw * 0.05, y: shoulders - L * 0.15)
        let hr = cw * 0.44
        var nemes = Path()
        nemes.move(to: CGPoint(x: hc.x - hr * 1.0, y: hc.y - hr * 0.7))
        nemes.addQuadCurve(to: CGPoint(x: hc.x + hr * 1.0, y: hc.y - hr * 0.7), control: CGPoint(x: hc.x, y: hc.y - hr * 1.6))
        nemes.addLine(to: CGPoint(x: hc.x + hr * 1.45, y: shoulders + L * 0.1))
        nemes.addLine(to: CGPoint(x: hc.x + hr * 0.75, y: shoulders + L * 0.12))
        nemes.addLine(to: CGPoint(x: hc.x + hr * 0.7, y: hc.y + hr * 0.4))
        nemes.addLine(to: CGPoint(x: hc.x - hr * 0.7, y: hc.y + hr * 0.4))
        nemes.addLine(to: CGPoint(x: hc.x - hr * 0.75, y: shoulders + L * 0.12))
        nemes.addLine(to: CGPoint(x: hc.x - hr * 1.45, y: shoulders + L * 0.1))
        nemes.closeSubpath()
        g.fill(nemes, with: .color(gold))
        var nc = g
        nc.clip(to: nemes)
        var stripes = Path()
        y = hc.y - hr * 1.6
        while y < shoulders + L * 0.12 { stripes.addRect(CGRect(x: hc.x - hr * 1.6, y: y, width: hr * 3.2, height: hr * 0.13)); y += hr * 0.27 }
        nc.fill(stripes, with: .color(blue))
        g.stroke(nemes, with: .color(ink), lineWidth: lw)
        let face = oval(hc, hr * 0.62, hr * 0.72)
        g.fill(face, with: .color(wrap))
        var fc = g
        fc.clip(to: face)
        var fb = Path()
        y = hc.y - hr
        while y < hc.y + hr { fb.move(to: CGPoint(x: hc.x - hr, y: y + hr * 0.1)); fb.addLine(to: CGPoint(x: hc.x + hr, y: y - hr * 0.08)); y += hr * 0.24 }
        fc.stroke(fb, with: .color(wrapLine), lineWidth: 1)
        g.stroke(face, with: .color(ink), lineWidth: lw)
        let glow = 0.6 + 0.4 * sin(t * 3) + (wu != nil ? 0.4 : 0)
        for dx in [-0.26, 0.22] as [CGFloat] {
            let e = CGPoint(x: hc.x + dx * hr, y: hc.y - hr * 0.12)
            g.fill(disc(e, hr * 0.3), with: .radialGradient(Gradient(colors: [Color(red: 0.6, green: 1, blue: 0.4).opacity(min(1, glow)), .clear]), center: e, startRadius: 0, endRadius: hr * 0.3))
            g.fill(oval(e, hr * 0.12, hr * 0.08), with: .color(Color(red: 0.75, green: 1, blue: 0.5)))
        }
        // Golden beard and the brow band with a cobra-like crest (a plain gold disc here).
        g.fill(Path(roundedRect: CGRect(x: hc.x - hr * 0.13, y: hc.y + hr * 0.62, width: hr * 0.26, height: hr * 0.55), cornerRadius: hr * 0.08), with: .color(gold))
        g.stroke(Path(roundedRect: CGRect(x: hc.x - hr * 0.13, y: hc.y + hr * 0.62, width: hr * 0.26, height: hr * 0.55), cornerRadius: hr * 0.08), with: .color(ink), lineWidth: lw * 0.8)
        g.fill(Path(CGRect(x: hc.x - hr * 0.72, y: hc.y - hr * 0.62, width: hr * 1.44, height: hr * 0.14)), with: .color(gold))
        g.fill(disc(CGPoint(x: hc.x, y: hc.y - hr * 0.72), hr * 0.15), with: .color(Color(red: 0.2, green: 0.75, blue: 0.6)))
        g.stroke(disc(CGPoint(x: hc.x, y: hc.y - hr * 0.72), hr * 0.15), with: .color(ink), lineWidth: lw * 0.7)
        // Sand whirling about him while he calls up a storm.
        if let (m, p) = wu, m == .ambush || m == .graves {
            var sand = g
            sand.opacity = p
            for k in 0..<10 {
                let a = t * 5 + Double(k) * 0.63
                let r = cw * (0.9 + 0.3 * CGFloat(k % 3))
                sand.fill(disc(CGPoint(x: cx + CGFloat(cos(a)) * r, y: waist + CGFloat(sin(a)) * r * 0.5), cw * 0.05), with: .color(Color(red: 0.92, green: 0.78, blue: 0.5)))
            }
        }
    }

    // MARK: The captain (pirate ship)

    private static func captain(_ g: GraphicsContext, _ b: LDWorld.Boss, _ f: Frame, _ t: Double) {
        let cw = f.cw, L = f.lanes
        let wu = windup(b)
        let rock = CGFloat(sin(t * 1.4)) * f.ch * 0.03
        let deckY = f.ground - L * 0.5 + rock
        let wood = Color(red: 0.42, green: 0.24, blue: 0.12), dark = Color(red: 0.25, green: 0.13, blue: 0.05)
        let gold = Color(red: 0.9, green: 0.72, blue: 0.28)
        let lw = max(1.5, cw * 0.035)
        let x0 = f.front
        // Mast and a sail behind everything.
        let mastX = x0 + cw * 1.9
        g.fill(Path(CGRect(x: mastX - cw * 0.07, y: f.top - f.ch * 0.9, width: cw * 0.14, height: deckY - f.top + f.ch * 0.9)), with: .color(Color(red: 0.5, green: 0.32, blue: 0.16)))
        var sail = Path()
        sail.move(to: CGPoint(x: mastX - cw * 0.05, y: f.top - f.ch * 0.75))
        sail.addQuadCurve(to: CGPoint(x: mastX - cw * 0.05, y: deckY - L * 0.2), control: CGPoint(x: mastX - cw * 1.0, y: (f.top + deckY) / 2))
        sail.closeSubpath()
        g.fill(sail, with: .color(Color(red: 0.95, green: 0.9, blue: 0.78)))
        g.stroke(sail, with: .color(Color(red: 0.6, green: 0.52, blue: 0.4)), lineWidth: 1.2)
        var patch = Path(); patch.addRect(CGRect(x: mastX - cw * 0.45, y: (f.top + deckY) / 2 - cw * 0.1, width: cw * 0.18, height: cw * 0.15))
        g.fill(patch, with: .color(Color(red: 0.8, green: 0.7, blue: 0.5)))
        // A pennant: a zombie hand on red.
        var flag = Path()
        let ft = CGPoint(x: mastX, y: f.top - f.ch * 0.9)
        flag.move(to: ft); flag.addLine(to: CGPoint(x: ft.x - cw * 0.55, y: ft.y + cw * 0.12 + CGFloat(sin(t * 5)) * cw * 0.05)); flag.addLine(to: CGPoint(x: ft.x, y: ft.y + cw * 0.3)); flag.closeSubpath()
        g.fill(flag, with: .color(Color(red: 0.75, green: 0.1, blue: 0.1)))
        // The hull's bow.
        var hull = Path()
        hull.move(to: CGPoint(x: x0 + cw * 0.15, y: deckY))
        hull.addQuadCurve(to: CGPoint(x: x0 - cw * 0.35, y: deckY - L * 0.12), control: CGPoint(x: x0 - cw * 0.1, y: deckY - L * 0.02))
        hull.addQuadCurve(to: CGPoint(x: x0 + cw * 0.55, y: f.ground + rock), control: CGPoint(x: x0 - cw * 0.2, y: f.ground - L * 0.1))
        hull.addLine(to: CGPoint(x: x0 + cw * 3.4, y: f.ground + rock))
        hull.addLine(to: CGPoint(x: x0 + cw * 3.4, y: deckY))
        hull.closeSubpath()
        g.fill(hull, with: .linearGradient(Gradient(colors: [wood.lit(0.1), wood, dark]), startPoint: CGPoint(x: 0, y: deckY), endPoint: CGPoint(x: 0, y: f.ground)))
        var hc = g
        hc.clip(to: hull)
        var planks = Path()
        var y = deckY + L * 0.08
        while y < f.ground { planks.move(to: CGPoint(x: x0 - cw, y: y)); planks.addLine(to: CGPoint(x: x0 + cw * 4, y: y)); y += L * 0.075 }
        hc.stroke(planks, with: .color(dark.opacity(0.6)), lineWidth: 1)
        hc.fill(Path(CGRect(x: x0 - cw, y: deckY + L * 0.25, width: cw * 5, height: L * 0.035)), with: .color(gold))
        g.stroke(hull, with: .color(ink), lineWidth: lw)
        // The bow cannon in its port, recoiling on a shot.
        var kick: CGFloat = 0
        if let (m, p) = wu, m == .bombard { kick = p > 0.45 ? CGFloat(min(1, (p - 0.45) / 0.1)) * CGFloat(max(0, 1 - (p - 0.55) / 0.45)) : 0 }
        let port = CGRect(x: x0 + cw * 0.35, y: deckY + L * 0.09, width: cw * 0.42, height: L * 0.12)
        g.fill(Path(roundedRect: port, cornerRadius: 3), with: .color(Color(white: 0.08)))
        let barrel = CGRect(x: port.minX - cw * 0.55 + kick * cw * 0.2, y: port.midY - L * 0.035, width: cw * 0.7, height: L * 0.07)
        g.fill(Path(roundedRect: barrel, cornerRadius: L * 0.03), with: .linearGradient(Gradient(colors: [Color(white: 0.45), Color(white: 0.15)]), startPoint: CGPoint(x: 0, y: barrel.minY), endPoint: CGPoint(x: 0, y: barrel.maxY)))
        g.fill(Path(roundedRect: CGRect(x: barrel.minX - cw * 0.06, y: barrel.minY - L * 0.012, width: cw * 0.12, height: barrel.height + L * 0.024), cornerRadius: 2), with: .color(Color(white: 0.2)))
        if kick > 0.2 {
            var puff = g
            puff.opacity = Double(kick)
            for k in 0..<4 { puff.fill(disc(CGPoint(x: barrel.minX - cw * (0.15 + CGFloat(k) * 0.12), y: barrel.midY - CGFloat(k % 2) * cw * 0.08), cw * (0.14 + CGFloat(k) * 0.03)), with: .color(Color(white: 0.85))) }
        }
        // The rail along the deck.
        g.fill(Path(CGRect(x: x0 + cw * 0.1, y: deckY - L * 0.06, width: cw * 3.3, height: L * 0.03)), with: .color(dark))
        var posts = Path()
        var x = x0 + cw * 0.2
        while x < x0 + cw * 3.4 { posts.addRect(CGRect(x: x, y: deckY - L * 0.06, width: cw * 0.06, height: L * 0.06)); x += cw * 0.3 }
        g.fill(posts, with: .color(wood.lit(0.15)))
        // The captain on deck.
        let cx = x0 + cw * 1.05
        let coat = Color(red: 0.7, green: 0.1, blue: 0.12)
        let skin = Color(red: 0.58, green: 0.66, blue: 0.5)
        let shoulder = CGPoint(x: cx, y: deckY - L * 0.32)
        var body = Path()
        body.move(to: CGPoint(x: cx - cw * 0.42, y: deckY - L * 0.04))
        body.addLine(to: CGPoint(x: shoulder.x - cw * 0.36, y: shoulder.y))
        body.addLine(to: CGPoint(x: shoulder.x + cw * 0.36, y: shoulder.y))
        body.addLine(to: CGPoint(x: cx + cw * 0.42, y: deckY - L * 0.04))
        body.closeSubpath()
        g.fill(body, with: .color(coat))
        g.fill(Path(CGRect(x: cx - cw * 0.07, y: shoulder.y, width: cw * 0.14, height: deckY - shoulder.y - L * 0.04)), with: .color(Color(white: 0.92)))
        var buttons = Path()
        for k in 0..<3 { buttons.addEllipse(in: CGRect(x: cx - cw * 0.16, y: shoulder.y + L * 0.04 + CGFloat(k) * L * 0.06, width: cw * 0.05, height: cw * 0.05)) }
        g.fill(buttons, with: .color(gold))
        g.stroke(body, with: .color(ink), lineWidth: lw)
        // Hook arm: pointing ahead while giving orders.
        var point = 0.0
        if let (m, p) = wu, m == .ambush || m == .summon { point = min(1, p * 2) }
        let hookHand = CGPoint(x: shoulder.x - cw * 0.55 - CGFloat(point) * cw * 0.25, y: shoulder.y + L * 0.12 - CGFloat(point) * L * 0.16)
        limb(g, from: CGPoint(x: shoulder.x - cw * 0.3, y: shoulder.y + L * 0.03), to: hookHand, w: cw * 0.16, cover: coat, skin: coat, lw: lw)
        var hook = Path()
        hook.addArc(center: CGPoint(x: hookHand.x - cw * 0.06, y: hookHand.y - cw * 0.06), radius: cw * 0.09, startAngle: .degrees(60), endAngle: .degrees(330), clockwise: false)
        g.stroke(hook, with: .color(Color(white: 0.8)), style: StrokeStyle(lineWidth: cw * 0.04, lineCap: .round))
        // Head: beard, eye patch, tricorn.
        let head = CGPoint(x: cx - cw * 0.05, y: shoulder.y - L * 0.09)
        let hr = cw * 0.28
        g.fill(oval(head, hr, hr * 1.05), with: .color(skin))
        g.stroke(oval(head, hr, hr * 1.05), with: .color(ink), lineWidth: lw)
        var beard = Path()
        beard.move(to: CGPoint(x: head.x - hr * 0.95, y: head.y + hr * 0.1))
        beard.addQuadCurve(to: CGPoint(x: head.x + hr * 0.6, y: head.y + hr * 0.2), control: CGPoint(x: head.x - hr * 0.3, y: head.y + hr * 1.6))
        beard.addQuadCurve(to: CGPoint(x: head.x - hr * 0.95, y: head.y + hr * 0.1), control: CGPoint(x: head.x - hr * 0.2, y: head.y + hr * 0.6))
        g.fill(beard, with: .color(Color(red: 0.2, green: 0.12, blue: 0.08)))
        let eye = CGPoint(x: head.x - hr * 0.45, y: head.y - hr * 0.2)
        g.fill(disc(eye, hr * 0.26), with: .color(.white)); g.stroke(disc(eye, hr * 0.26), with: .color(ink), lineWidth: 1)
        g.fill(disc(CGPoint(x: eye.x - hr * 0.08, y: eye.y), hr * 0.1), with: .color(ink))
        g.fill(oval(CGPoint(x: head.x + hr * 0.2, y: head.y - hr * 0.2), hr * 0.22, hr * 0.2), with: .color(ink))
        var strap = Path(); strap.move(to: CGPoint(x: head.x - hr * 0.9, y: head.y - hr * 0.6)); strap.addLine(to: CGPoint(x: head.x + hr * 0.95, y: head.y + hr * 0.05))
        g.stroke(strap, with: .color(ink), lineWidth: 1.4)
        var tricorn = Path()
        let brim = head.y - hr * 0.62
        tricorn.move(to: CGPoint(x: head.x - hr * 1.5, y: brim + hr * 0.05))
        tricorn.addQuadCurve(to: CGPoint(x: head.x + hr * 1.4, y: brim), control: CGPoint(x: head.x, y: brim - hr * 1.6))
        tricorn.addQuadCurve(to: CGPoint(x: head.x - hr * 1.5, y: brim + hr * 0.05), control: CGPoint(x: head.x, y: brim - hr * 0.35))
        g.fill(tricorn, with: .color(Color(white: 0.1)))
        g.stroke(tricorn, with: .color(gold), lineWidth: 1.6)
        // A gold anchor on the hat.
        var anchor = Path()
        let a = CGPoint(x: head.x, y: brim - hr * 0.55)
        anchor.move(to: CGPoint(x: a.x, y: a.y - hr * 0.18)); anchor.addLine(to: CGPoint(x: a.x, y: a.y + hr * 0.16))
        anchor.move(to: CGPoint(x: a.x - hr * 0.12, y: a.y + hr * 0.06)); anchor.addQuadCurve(to: CGPoint(x: a.x + hr * 0.12, y: a.y + hr * 0.06), control: CGPoint(x: a.x, y: a.y + hr * 0.28))
        anchor.move(to: CGPoint(x: a.x - hr * 0.08, y: a.y - hr * 0.08)); anchor.addLine(to: CGPoint(x: a.x + hr * 0.08, y: a.y - hr * 0.08))
        g.stroke(anchor, with: .color(gold), lineWidth: 1.4)
    }

    // MARK: The outlaw's locomotive (frontier)

    private static func locomotive(_ g: GraphicsContext, _ b: LDWorld.Boss, _ f: Frame, _ t: Double) {
        let cw = f.cw, L = f.lanes
        let wu = windup(b)
        let charging = b.mode == .charging, backing = b.mode == .retreating
        let rumble = (wu?.0 == .charge ? CGFloat(sin(t * 50)) * cw * 0.03 * CGFloat(wu!.1) : 0) + (charging ? CGFloat(sin(t * 40)) * cw * 0.02 : 0)
        let x0 = f.front + rumble
        let lw = max(1.5, cw * 0.035)
        let black = Color(white: 0.12), brass = Color(red: 0.86, green: 0.68, blue: 0.28), red = Color(red: 0.72, green: 0.12, blue: 0.1)
        let axle = f.ground - L * 0.12
        // Smoke from the stack, streaming back (thick and fast while charging).
        let stack = CGPoint(x: x0 + cw * 0.85, y: f.ground - L * 0.95)
        var smokeCtx = g
        smokeCtx.opacity = charging ? 0.9 : 0.65
        for k in 0..<6 {
            let age = (t * (charging ? 2.4 : 0.9) + Double(k) / 6).truncatingRemainder(dividingBy: 1)
            let p = CGPoint(x: stack.x + CGFloat(age) * cw * (charging ? 2.6 : 1.2), y: stack.y - CGFloat(age) * L * 0.35)
            smokeCtx.fill(disc(p, cw * (0.14 + CGFloat(age) * 0.3)), with: .color(Color(white: 0.75 - age * 0.3)))
        }
        // Cab at the back.
        let cab = CGRect(x: x0 + cw * 2.05, y: f.ground - L * 1.02, width: cw * 1.1, height: L * 0.82)
        g.fill(Path(cab), with: .color(red))
        g.fill(Path(CGRect(x: cab.minX - cw * 0.08, y: cab.minY - L * 0.06, width: cab.width + cw * 0.16, height: L * 0.07)), with: .color(black))
        let window = CGRect(x: cab.minX + cw * 0.15, y: cab.minY + L * 0.1, width: cw * 0.55, height: L * 0.24)
        g.fill(Path(window), with: .color(Color(red: 0.2, green: 0.15, blue: 0.12)))
        g.stroke(Path(cab), with: .color(ink), lineWidth: lw)
        // The engineer at the window (hat, bandana; an arm up with dynamite when throwing).
        let head = CGPoint(x: window.midX - cw * 0.05, y: window.midY)
        let hr = cw * 0.17
        g.fill(oval(head, hr, hr), with: .color(Color(red: 0.58, green: 0.66, blue: 0.5)))
        g.stroke(oval(head, hr, hr), with: .color(ink), lineWidth: 1.2)
        g.fill(Path(CGRect(x: head.x - hr, y: head.y + hr * 0.15, width: hr * 2, height: hr * 0.6)), with: .color(Color(red: 0.75, green: 0.15, blue: 0.12)))
        g.fill(disc(CGPoint(x: head.x - hr * 0.4, y: head.y - hr * 0.2), hr * 0.25), with: .color(.white))
        g.fill(disc(CGPoint(x: head.x - hr * 0.45, y: head.y - hr * 0.18), hr * 0.1), with: .color(ink))
        g.fill(oval(CGPoint(x: head.x, y: head.y - hr * 0.75), hr * 1.6, hr * 0.25), with: .color(Color(red: 0.45, green: 0.28, blue: 0.14)))
        g.fill(Path(roundedRect: CGRect(x: head.x - hr * 0.75, y: head.y - hr * 1.5, width: hr * 1.5, height: hr * 0.8), cornerRadius: hr * 0.3), with: .color(Color(red: 0.52, green: 0.33, blue: 0.17)))
        if let (m, p) = wu, m == .bombard {
            let hand = CGPoint(x: head.x - hr * 1.2, y: head.y - hr * (0.5 + 1.8 * CGFloat(min(1, p * 1.4))))
            var arm = Path(); arm.move(to: CGPoint(x: head.x - hr * 0.6, y: head.y + hr * 0.6)); arm.addLine(to: hand)
            g.stroke(arm, with: .color(Color(red: 0.58, green: 0.66, blue: 0.5)), style: StrokeStyle(lineWidth: hr * 0.4, lineCap: .round))
            if p < 0.55 { dynamite(g, at: CGPoint(x: hand.x, y: hand.y - hr * 0.3), s: cw * 0.35, angle: -0.4, t: t) }
        }
        // Boiler with brass bands.
        let boiler = CGRect(x: x0 + cw * 0.38, y: f.ground - L * 0.82, width: cw * 1.8, height: L * 0.46)
        g.fill(Path(roundedRect: boiler, cornerRadius: L * 0.2), with: .linearGradient(Gradient(colors: [Color(white: 0.35), black, Color(white: 0.05)]), startPoint: CGPoint(x: 0, y: boiler.minY), endPoint: CGPoint(x: 0, y: boiler.maxY)))
        for k in 0..<3 {
            let bx = boiler.minX + boiler.width * (0.25 + CGFloat(k) * 0.25)
            g.fill(Path(CGRect(x: bx - cw * 0.04, y: boiler.minY, width: cw * 0.08, height: boiler.height)), with: .color(brass))
        }
        g.stroke(Path(roundedRect: boiler, cornerRadius: L * 0.2), with: .color(ink), lineWidth: lw)
        // Steam dome and the stack.
        g.fill(oval(CGPoint(x: boiler.minX + boiler.width * 0.62, y: boiler.minY), cw * 0.2, L * 0.07), with: .color(brass))
        var funnel = Path()
        funnel.move(to: CGPoint(x: stack.x - cw * 0.12, y: boiler.minY + L * 0.02))
        funnel.addLine(to: CGPoint(x: stack.x - cw * 0.12, y: stack.y + L * 0.12))
        funnel.addLine(to: CGPoint(x: stack.x - cw * 0.26, y: stack.y))
        funnel.addLine(to: CGPoint(x: stack.x + cw * 0.26, y: stack.y))
        funnel.addLine(to: CGPoint(x: stack.x + cw * 0.12, y: stack.y + L * 0.12))
        funnel.addLine(to: CGPoint(x: stack.x + cw * 0.12, y: boiler.minY + L * 0.02))
        funnel.closeSubpath()
        g.fill(funnel, with: .color(black))
        g.stroke(funnel, with: .color(ink), lineWidth: lw)
        g.fill(Path(CGRect(x: stack.x - cw * 0.27, y: stack.y - L * 0.02, width: cw * 0.54, height: L * 0.03)), with: .color(brass))
        // The smokebox face and its lamp.
        let face = CGPoint(x: boiler.minX + cw * 0.05, y: boiler.midY)
        g.fill(oval(face, cw * 0.14, L * 0.22), with: .color(Color(white: 0.2)))
        g.stroke(oval(face, cw * 0.14, L * 0.22), with: .color(brass), lineWidth: 2)
        let lamp = CGPoint(x: face.x - cw * 0.05, y: boiler.minY - L * 0.05)
        let lit = wu?.0 == .charge || charging
        g.fill(disc(lamp, cw * (lit ? 0.4 : 0.22)), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.6).opacity(lit ? 0.9 : 0.5), .clear]), center: lamp, startRadius: 0, endRadius: cw * (lit ? 0.4 : 0.22)))
        g.fill(Path(roundedRect: CGRect(x: lamp.x - cw * 0.1, y: lamp.y - cw * 0.09, width: cw * 0.2, height: cw * 0.18), cornerRadius: 3), with: .color(brass))
        g.fill(disc(lamp, cw * 0.06), with: .color(Color(red: 1, green: 0.95, blue: 0.6)))
        // The cowcatcher.
        var catcher = Path()
        catcher.move(to: CGPoint(x: x0 - cw * 0.05, y: f.ground))
        catcher.addLine(to: CGPoint(x: x0 + cw * 0.45, y: f.ground - L * 0.34))
        catcher.addLine(to: CGPoint(x: x0 + cw * 0.5, y: f.ground))
        catcher.closeSubpath()
        g.fill(catcher, with: .color(red))
        var bars = Path()
        for k in 1..<5 {
            let p = CGFloat(k) / 5
            bars.move(to: CGPoint(x: x0 - cw * 0.05 + p * cw * 0.5, y: f.ground - p * L * 0.34)); bars.addLine(to: CGPoint(x: x0 - cw * 0.05 + p * cw * 0.55, y: f.ground))
        }
        g.stroke(bars, with: .color(ink.opacity(0.7)), lineWidth: 1.2)
        g.stroke(catcher, with: .color(ink), lineWidth: lw)
        // Wheels: they turn as it moves.
        let spin = Double(b.x) * -2.2 + (charging || backing ? t * (charging ? -14 : 8) : 0)
        let big = L * 0.17
        for (wx, r) in [(x0 + cw * 0.75, L * 0.1), (x0 + cw * 1.45, big), (x0 + cw * 2.2, big), (x0 + cw * 2.85, L * 0.12)] {
            let c = CGPoint(x: wx, y: f.ground - r)
            g.fill(disc(c, r), with: .color(red))
            g.stroke(disc(c, r), with: .color(ink), lineWidth: lw)
            var spokes = Path()
            for k in 0..<6 {
                let a = spin + Double(k) * .pi / 3
                spokes.move(to: c); spokes.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * r * 0.85, y: c.y + CGFloat(sin(a)) * r * 0.85))
            }
            g.stroke(spokes, with: .color(Color(red: 0.4, green: 0.05, blue: 0.05)), lineWidth: 1.4)
            g.fill(disc(c, r * 0.25), with: .color(brass))
        }
        let rodA = CGPoint(x: x0 + cw * 1.45 + CGFloat(cos(spin)) * big * 0.6, y: f.ground - big + CGFloat(sin(spin)) * big * 0.6)
        let rodB = CGPoint(x: x0 + cw * 2.2 + CGFloat(cos(spin)) * big * 0.6, y: f.ground - big + CGFloat(sin(spin)) * big * 0.6)
        var rod = Path(); rod.move(to: rodA); rod.addLine(to: rodB)
        g.stroke(rod, with: .color(Color(white: 0.75)), style: StrokeStyle(lineWidth: cw * 0.07, lineCap: .round))
        _ = axle
        // Motion lines while it charges.
        if charging {
            var lines = Path()
            for k in 0..<4 {
                let y = f.ground - L * (0.15 + CGFloat(k) * 0.22)
                lines.move(to: CGPoint(x: x0 + cw * 3.4, y: y)); lines.addLine(to: CGPoint(x: x0 + cw * (4.4 + CGFloat(k % 2) * 0.4), y: y))
            }
            g.stroke(lines, with: .color(.white.opacity(0.6)), lineWidth: 2)
        }
    }

    static func dynamite(_ g: GraphicsContext, at c: CGPoint, s: CGFloat, angle: Double, t: Double) {
        var d = g
        d.translateBy(x: c.x, y: c.y)
        d.rotate(by: .radians(angle))
        let stick = CGRect(x: -s * 0.12, y: -s * 0.4, width: s * 0.24, height: s * 0.8)
        d.fill(Path(roundedRect: stick, cornerRadius: s * 0.05), with: .color(Color(red: 0.85, green: 0.15, blue: 0.12)))
        d.stroke(Path(roundedRect: stick, cornerRadius: s * 0.05), with: .color(ink), lineWidth: 1)
        d.fill(Path(CGRect(x: stick.minX, y: -s * 0.1, width: stick.width, height: s * 0.08)), with: .color(Color(red: 0.95, green: 0.85, blue: 0.6)))
        var fuse = Path(); fuse.move(to: CGPoint(x: 0, y: -s * 0.4)); fuse.addQuadCurve(to: CGPoint(x: s * 0.12, y: -s * 0.6), control: CGPoint(x: -s * 0.08, y: -s * 0.55))
        d.stroke(fuse, with: .color(Color(white: 0.3)), lineWidth: 1.2)
        let spark = CGPoint(x: s * 0.12, y: -s * 0.6)
        d.fill(disc(spark, s * (0.08 + 0.04 * CGFloat(abs(sin(t * 30))))), with: .color(Color(red: 1, green: 0.85, blue: 0.3)))
    }

    // MARK: The woolly mammoth (glacier)

    private static func mammoth(_ g: GraphicsContext, _ b: LDWorld.Boss, _ f: Frame, _ t: Double) {
        let cw = f.cw, L = f.lanes
        let wu = windup(b)
        let breathe = CGFloat(sin(t * 1.5)) * L * 0.01
        let x0 = f.front
        let lw = max(1.5, cw * 0.035)
        let fur = Color(red: 0.5, green: 0.32, blue: 0.2), furDark = Color(red: 0.32, green: 0.19, blue: 0.1)
        let body = CGPoint(x: x0 + cw * 1.45, y: f.ground - L * 0.5 + breathe)
        let brx = cw * 1.3, bry = L * 0.36
        // Legs (back pair darker).
        for (i, lx) in [x0 + cw * 2.3, x0 + cw * 0.9, x0 + cw * 2.0, x0 + cw * 0.65].enumerated() {
            let r = CGRect(x: lx - cw * 0.22, y: body.y, width: cw * 0.44, height: f.ground - body.y)
            g.fill(Path(roundedRect: r, cornerRadius: cw * 0.15), with: .color(i < 2 ? furDark : fur))
            g.stroke(Path(roundedRect: r, cornerRadius: cw * 0.15), with: .color(ink), lineWidth: lw)
            var nails = Path()
            for k in 0..<3 { nails.addEllipse(in: CGRect(x: r.minX + cw * 0.04 + CGFloat(k) * cw * 0.13, y: f.ground - cw * 0.09, width: cw * 0.1, height: cw * 0.07)) }
            g.fill(nails, with: .color(Color(red: 0.92, green: 0.88, blue: 0.78)))
        }
        // The shaggy body.
        var shag = Path()
        for i in 0...40 {
            let a = Double(i) / 40 * 2 * .pi
            let wob: CGFloat = i % 2 == 0 ? 1.0 : 0.92
            let p = CGPoint(x: body.x + CGFloat(cos(a)) * brx * wob, y: body.y + CGFloat(sin(a)) * bry * wob)
            if i == 0 { shag.move(to: p) } else { shag.addLine(to: p) }
        }
        shag.closeSubpath()
        g.fill(shag, with: .radialGradient(Gradient(colors: [fur.lit(0.2), fur, furDark]), center: CGPoint(x: body.x - brx * 0.3, y: body.y - bry * 0.4), startRadius: 0, endRadius: brx * 1.3))
        g.stroke(shag, with: .color(ink), lineWidth: lw)
        var hair = Path()
        for k in 0..<14 {
            let hx = body.x - brx * 0.8 + CGFloat(k) * brx * 0.12
            let hy = body.y - bry * 0.2 + CGFloat(LDLawnArt.hash(Double(k))) * bry * 0.8
            hair.move(to: CGPoint(x: hx, y: hy)); hair.addLine(to: CGPoint(x: hx - cw * 0.04, y: hy + L * 0.06))
        }
        g.stroke(hair, with: .color(furDark), lineWidth: 1.2)
        var frost = Path()
        for k in 0..<10 { frost.addEllipse(in: CGRect(x: body.x - brx * 0.7 + CGFloat(LDLawnArt.hash(Double(k) * 3.1)) * brx * 1.4, y: body.y - bry * 0.9 + CGFloat(LDLawnArt.hash(Double(k) * 1.3)) * bry * 0.6, width: 3, height: 3)) }
        g.fill(frost, with: .color(.white.opacity(0.85)))
        // The rider: a caveman zombie with a bone club.
        let seat = CGPoint(x: body.x + brx * 0.1, y: body.y - bry * 0.95)
        let rh = L * 0.28
        var tunic = Path()
        tunic.move(to: CGPoint(x: seat.x - rh * 0.3, y: seat.y + rh * 0.05)); tunic.addLine(to: CGPoint(x: seat.x - rh * 0.22, y: seat.y - rh * 0.55))
        tunic.addLine(to: CGPoint(x: seat.x + rh * 0.22, y: seat.y - rh * 0.55)); tunic.addLine(to: CGPoint(x: seat.x + rh * 0.3, y: seat.y + rh * 0.05)); tunic.closeSubpath()
        g.fill(tunic, with: .color(Color(red: 0.75, green: 0.55, blue: 0.3)))
        var spots = Path()
        for k in 0..<3 { spots.addEllipse(in: CGRect(x: seat.x - rh * 0.15 + CGFloat(k) * rh * 0.12, y: seat.y - rh * 0.4 + CGFloat(k % 2) * rh * 0.15, width: rh * 0.08, height: rh * 0.06)) }
        g.fill(spots, with: .color(Color(red: 0.4, green: 0.25, blue: 0.12)))
        g.stroke(tunic, with: .color(ink), lineWidth: 1.2)
        let rhead = CGPoint(x: seat.x - rh * 0.05, y: seat.y - rh * 0.74)
        g.fill(oval(rhead, rh * 0.22, rh * 0.23), with: .color(Color(red: 0.6, green: 0.7, blue: 0.62)))
        g.stroke(oval(rhead, rh * 0.22, rh * 0.23), with: .color(ink), lineWidth: 1.2)
        var mop = Path()
        mop.move(to: CGPoint(x: rhead.x - rh * 0.26, y: rhead.y - rh * 0.02))
        mop.addQuadCurve(to: CGPoint(x: rhead.x + rh * 0.26, y: rhead.y - rh * 0.05), control: CGPoint(x: rhead.x, y: rhead.y - rh * 0.5))
        mop.addQuadCurve(to: CGPoint(x: rhead.x - rh * 0.26, y: rhead.y - rh * 0.02), control: CGPoint(x: rhead.x, y: rhead.y - rh * 0.14))
        g.fill(mop, with: .color(Color(red: 0.25, green: 0.15, blue: 0.08)))
        let reye = CGPoint(x: rhead.x - rh * 0.09, y: rhead.y + rh * 0.02)
        g.fill(disc(reye, rh * 0.07), with: .color(.white))
        g.stroke(disc(reye, rh * 0.07), with: .color(ink), lineWidth: 0.8)
        g.fill(disc(CGPoint(x: reye.x - rh * 0.02, y: reye.y), rh * 0.03), with: .color(ink))
        g.fill(Path(roundedRect: CGRect(x: rhead.x - rh * 0.14, y: rhead.y + rh * 0.1, width: rh * 0.16, height: rh * 0.06), cornerRadius: 1), with: .color(Color(red: 0.2, green: 0.08, blue: 0.08)))
        let swing = wu != nil ? CGFloat(sin(t * 10)) * 0.3 : 0
        let clubHand = CGPoint(x: seat.x - rh * 0.4, y: seat.y - rh * 0.6)
        var club = Path(); club.move(to: clubHand); club.addLine(to: CGPoint(x: clubHand.x - rh * 0.25 + swing * rh, y: clubHand.y - rh * 0.6))
        g.stroke(club, with: .color(Color(red: 0.95, green: 0.92, blue: 0.82)), style: StrokeStyle(lineWidth: rh * 0.1, lineCap: .round))
        g.fill(disc(CGPoint(x: clubHand.x - rh * 0.25 + swing * rh, y: clubHand.y - rh * 0.62), rh * 0.09), with: .color(Color(red: 0.95, green: 0.92, blue: 0.82)))
        // The head, ear, eye.
        let head = CGPoint(x: x0 + cw * 0.42, y: f.ground - L * 0.7 + breathe)
        let hr = L * 0.22
        g.fill(oval(head, hr * 1.05, hr), with: .radialGradient(Gradient(colors: [fur.lit(0.2), fur]), center: CGPoint(x: head.x - hr * 0.3, y: head.y - hr * 0.3), startRadius: 0, endRadius: hr * 1.3))
        g.stroke(oval(head, hr * 1.05, hr), with: .color(ink), lineWidth: lw)
        g.fill(oval(CGPoint(x: head.x + hr * 0.7, y: head.y - hr * 0.05), hr * 0.3, hr * 0.42), with: .color(furDark))
        let eye = CGPoint(x: head.x - hr * 0.35, y: head.y - hr * 0.2)
        g.fill(disc(eye, hr * 0.12), with: .color(.white))
        g.fill(disc(CGPoint(x: eye.x - hr * 0.03, y: eye.y), hr * 0.06), with: .color(ink))
        var brow = Path(); brow.move(to: CGPoint(x: eye.x - hr * 0.2, y: eye.y - hr * 0.2)); brow.addLine(to: CGPoint(x: eye.x + hr * 0.22, y: eye.y - hr * 0.08))
        g.stroke(brow, with: .color(ink), lineWidth: 1.8)
        // The trunk: hanging, raised to blow frost, curled to push a snowball.
        var trunkTip: CGPoint
        var trunk = Path()
        let root = CGPoint(x: head.x - hr * 0.75, y: head.y + hr * 0.15)
        trunk.move(to: root)
        if let (m, p) = wu, m == .freeze {
            let k = CGFloat(min(1, p * 1.6))
            trunkTip = CGPoint(x: root.x - hr * (0.6 + 0.7 * k), y: root.y + hr * (0.9 - 1.3 * k))
            trunk.addQuadCurve(to: trunkTip, control: CGPoint(x: root.x - hr * 0.7, y: root.y + hr * 0.6))
        } else if let (m, _) = wu, m == .roll {
            trunkTip = CGPoint(x: root.x - hr * 0.5, y: f.ground - L * 0.1)
            trunk.addQuadCurve(to: trunkTip, control: CGPoint(x: root.x - hr * 0.9, y: root.y + hr * 0.4))
        } else {
            trunkTip = CGPoint(x: root.x - hr * 0.2 + CGFloat(sin(t * 1.2)) * hr * 0.1, y: f.ground - L * 0.12)
            trunk.addQuadCurve(to: trunkTip, control: CGPoint(x: root.x - hr * 0.55, y: root.y + hr * 0.7))
        }
        g.stroke(trunk, with: .color(ink), style: StrokeStyle(lineWidth: hr * 0.4 + lw, lineCap: .round))
        g.stroke(trunk, with: .color(fur), style: StrokeStyle(lineWidth: hr * 0.4, lineCap: .round))
        // Tusks curving forward and up.
        for k in 0..<2 {
            var tusk = Path()
            let tr = CGPoint(x: head.x - hr * (0.45 - CGFloat(k) * 0.15), y: head.y + hr * 0.45)
            tusk.move(to: tr)
            tusk.addQuadCurve(to: CGPoint(x: tr.x - hr * (1.5 - CGFloat(k) * 0.2), y: tr.y - hr * 0.35), control: CGPoint(x: tr.x - hr * 0.9, y: tr.y + hr * 0.75))
            g.stroke(tusk, with: .color(ink), style: StrokeStyle(lineWidth: hr * 0.2 + lw, lineCap: .round))
            g.stroke(tusk, with: .color(Color(red: 0.97, green: 0.94, blue: 0.84)), style: StrokeStyle(lineWidth: hr * 0.2, lineCap: .round))
        }
        // Frost gathering at the trunk while it winds up a freeze.
        if let (m, p) = wu, m == .freeze {
            var mist = g
            mist.opacity = p
            for k in 0..<6 {
                let a = t * 6 + Double(k)
                mist.fill(disc(CGPoint(x: trunkTip.x + CGFloat(cos(a)) * hr * 0.3, y: trunkTip.y + CGFloat(sin(a)) * hr * 0.3), hr * 0.15), with: .color(Color(red: 0.85, green: 0.95, blue: 1).opacity(0.8)))
            }
        }
        if let (m, p) = wu, m == .roll {
            LDLawnArt.roller(g, at: CGPoint(x: trunkTip.x - cw * 0.35 * CGFloat(p), y: f.ground - cw * 0.4 * CGFloat(p)), r: cw * 0.42 * CGFloat(p), kind: .snowball, spin: 0, t: t)
        }
    }

    // MARK: The mech (future)

    private static func mech(_ g: GraphicsContext, _ b: LDWorld.Boss, _ f: Frame, _ t: Double) {
        let cw = f.cw, L = f.lanes
        let wu = windup(b)
        let bob = CGFloat(sin(t * 2.2)) * L * 0.012
        let x0 = f.front
        let cx = x0 + cw * 1.25
        let lw = max(1.5, cw * 0.035)
        let chrome = [Color(white: 0.85), Color(white: 0.55), Color(white: 0.7)]
        let neon = Color(red: 0.2, green: 0.95, blue: 0.95), pink = Color(red: 1, green: 0.3, blue: 0.85)
        let hip = f.ground - L * 0.42 + bob
        let shoulders = f.ground - L * 0.9 + bob
        // Legs with pistons and big feet.
        for (i, lx) in [cx + cw * 0.45, cx - cw * 0.4].enumerated() {
            let knee = CGPoint(x: lx - cw * 0.15, y: f.ground - L * 0.2)
            var leg = Path(); leg.move(to: CGPoint(x: lx, y: hip)); leg.addLine(to: knee); leg.addLine(to: CGPoint(x: lx, y: f.ground - L * 0.04))
            g.stroke(leg, with: .color(ink), style: StrokeStyle(lineWidth: cw * 0.3 + lw, lineCap: .round, lineJoin: .round))
            g.stroke(leg, with: .color(i == 0 ? Color(white: 0.45) : Color(white: 0.6)), style: StrokeStyle(lineWidth: cw * 0.3, lineCap: .round, lineJoin: .round))
            var piston = Path(); piston.move(to: CGPoint(x: lx + cw * 0.12, y: hip + L * 0.04)); piston.addLine(to: CGPoint(x: knee.x + cw * 0.15, y: knee.y))
            g.stroke(piston, with: .color(Color(white: 0.85)), lineWidth: cw * 0.06)
            let foot = CGRect(x: lx - cw * 0.4, y: f.ground - L * 0.06, width: cw * 0.7, height: L * 0.06)
            g.fill(Path(roundedRect: foot, cornerRadius: 4), with: .color(Color(white: 0.3)))
            g.stroke(Path(roundedRect: foot, cornerRadius: 4), with: .color(ink), lineWidth: lw)
            g.fill(Path(CGRect(x: knee.x - cw * 0.1, y: knee.y - cw * 0.03, width: cw * 0.2, height: cw * 0.06)), with: .color(neon))
        }
        // Missile pod on the back shoulder.
        var open = 0.0
        if let (m, p) = wu, m == .bombard { open = min(1, p * 2) }
        let pod = CGRect(x: cx + cw * 0.15, y: shoulders - L * 0.22, width: cw * 0.75, height: L * 0.2)
        g.fill(Path(roundedRect: pod, cornerRadius: 4), with: .color(Color(white: 0.35)))
        for k in 0..<4 {
            let mx = pod.minX + pod.width * (0.15 + CGFloat(k) * 0.22)
            g.fill(disc(CGPoint(x: mx, y: pod.minY + pod.height * 0.45), pod.height * 0.17), with: .color(Color(white: 0.1)))
            if open > 0.2 && b.move != nil { g.fill(disc(CGPoint(x: mx, y: pod.minY + pod.height * 0.45 - CGFloat(open) * pod.height * 0.2), pod.height * 0.13), with: .color(Color(red: 0.95, green: 0.2, blue: 0.15))) }
        }
        g.stroke(Path(roundedRect: pod, cornerRadius: 4), with: .color(ink), lineWidth: lw)
        // Torso: a chrome hull with neon trim, a vent grille and a glowing core, armoured shoulders.
        var torso = Path()
        torso.move(to: CGPoint(x: cx - cw * 0.62, y: hip))
        torso.addLine(to: CGPoint(x: cx - cw * 0.92, y: shoulders + L * 0.08))
        torso.addLine(to: CGPoint(x: cx - cw * 0.7, y: shoulders))
        torso.addLine(to: CGPoint(x: cx + cw * 0.7, y: shoulders))
        torso.addLine(to: CGPoint(x: cx + cw * 0.92, y: shoulders + L * 0.08))
        torso.addLine(to: CGPoint(x: cx + cw * 0.62, y: hip))
        torso.closeSubpath()
        g.fill(torso, with: .linearGradient(Gradient(colors: [Color(white: 0.9), Color(white: 0.62), Color(white: 0.45)]), startPoint: CGPoint(x: cx - cw * 0.6, y: shoulders), endPoint: CGPoint(x: cx + cw * 0.8, y: hip)))
        var trim = Path()
        trim.move(to: CGPoint(x: cx - cw * 0.55, y: hip - L * 0.03)); trim.addLine(to: CGPoint(x: cx - cw * 0.8, y: shoulders + L * 0.09))
        trim.move(to: CGPoint(x: cx + cw * 0.55, y: hip - L * 0.03)); trim.addLine(to: CGPoint(x: cx + cw * 0.8, y: shoulders + L * 0.09))
        g.stroke(trim, with: .color(neon.opacity(0.9)), lineWidth: 2)
        var grille = Path()
        for k in 0..<4 {
            let y = hip - L * 0.05 - CGFloat(k) * L * 0.035
            grille.move(to: CGPoint(x: cx - cw * 0.35, y: y)); grille.addLine(to: CGPoint(x: cx + cw * 0.35, y: y))
        }
        g.stroke(grille, with: .color(Color(white: 0.25)), lineWidth: 2)
        var seams = Path()
        seams.move(to: CGPoint(x: cx - cw * 0.75, y: shoulders + L * 0.14)); seams.addLine(to: CGPoint(x: cx + cw * 0.75, y: shoulders + L * 0.14))
        g.stroke(seams, with: .color(pink.opacity(0.85)), lineWidth: 1.5)
        let core = CGPoint(x: cx - cw * 0.05, y: shoulders + L * 0.27)
        let pulse = 0.6 + 0.4 * sin(t * 4)
        g.fill(disc(core, cw * 0.24), with: .radialGradient(Gradient(colors: [.white, neon.opacity(pulse), neon.opacity(0)]), center: core, startRadius: 0, endRadius: cw * 0.24))
        g.stroke(disc(core, cw * 0.13), with: .color(Color(white: 0.3)), lineWidth: 2)
        g.stroke(torso, with: .color(ink), lineWidth: lw)
        for side in [-1.0, 1.0] as [CGFloat] {
            let plate = CGRect(x: cx + side * cw * 0.95 - cw * 0.3, y: shoulders - L * 0.03, width: cw * 0.6, height: L * 0.15)
            g.fill(Path(roundedRect: plate, cornerRadius: cw * 0.12), with: .linearGradient(Gradient(colors: [Color(white: 0.85), Color(white: 0.5)]), startPoint: CGPoint(x: 0, y: plate.minY), endPoint: CGPoint(x: 0, y: plate.maxY)))
            g.stroke(Path(roundedRect: plate, cornerRadius: cw * 0.12), with: .color(ink), lineWidth: lw)
            g.fill(Path(CGRect(x: plate.minX + cw * 0.08, y: plate.midY - 1.5, width: plate.width - cw * 0.16, height: 3)), with: .color(pink))
        }
        // Cockpit dome with the pilot.
        let dome = CGPoint(x: cx, y: shoulders - L * 0.02)
        let dr = cw * 0.48
        var glass = Path()
        glass.addArc(center: dome, radius: dr, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        glass.closeSubpath()
        let pilot = CGPoint(x: dome.x - dr * 0.05, y: dome.y - dr * 0.4)
        g.fill(oval(pilot, dr * 0.32, dr * 0.34), with: .color(Color(red: 0.62, green: 0.72, blue: 0.62)))
        g.stroke(oval(pilot, dr * 0.32, dr * 0.34), with: .color(ink), lineWidth: 1.2)
        g.fill(disc(CGPoint(x: pilot.x - dr * 0.12, y: pilot.y - dr * 0.05), dr * 0.1), with: .color(.white))
        g.fill(disc(CGPoint(x: pilot.x - dr * 0.14, y: pilot.y - dr * 0.04), dr * 0.04), with: .color(ink))
        g.fill(Path(CGRect(x: pilot.x - dr * 0.32, y: pilot.y - dr * 0.22, width: dr * 0.64, height: dr * 0.08)), with: .color(Color(white: 0.35)))
        g.fill(glass, with: .color(neon.opacity(0.18)))
        g.stroke(glass, with: .color(Color(white: 0.9)), lineWidth: lw)
        var shine = Path(); shine.addArc(center: dome, radius: dr * 0.78, startAngle: .degrees(200), endAngle: .degrees(240), clockwise: false)
        g.stroke(shine, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        // The laser arm, glowing as it charges.
        var heat = 0.0
        if let (m, p) = wu, m == .laser { heat = p }
        let shoulder = CGPoint(x: cx - cw * 0.75, y: shoulders + L * 0.12)
        let muzzle = CGPoint(x: x0 - cw * 0.25, y: shoulder.y + L * 0.1)
        var arm = Path(); arm.move(to: shoulder); arm.addLine(to: CGPoint(x: muzzle.x + cw * 0.3, y: muzzle.y))
        g.stroke(arm, with: .color(ink), style: StrokeStyle(lineWidth: cw * 0.26 + lw, lineCap: .round))
        g.stroke(arm, with: .linearGradient(Gradient(colors: chrome), startPoint: CGPoint(x: 0, y: muzzle.y - cw * 0.13), endPoint: CGPoint(x: 0, y: muzzle.y + cw * 0.13)), style: StrokeStyle(lineWidth: cw * 0.26, lineCap: .round))
        let barrel = CGRect(x: muzzle.x, y: muzzle.y - cw * 0.08, width: cw * 0.4, height: cw * 0.16)
        g.fill(Path(roundedRect: barrel, cornerRadius: 3), with: .color(Color(white: 0.25)))
        g.stroke(Path(roundedRect: barrel, cornerRadius: 3), with: .color(ink), lineWidth: lw)
        let tip = CGPoint(x: barrel.minX, y: barrel.midY)
        g.fill(disc(tip, cw * (0.1 + 0.25 * CGFloat(heat))), with: .radialGradient(Gradient(colors: [.white, Color(red: 1, green: 0.2, blue: 0.2).opacity(0.3 + 0.7 * heat), .clear]),
                                                                                   center: tip, startRadius: 0, endRadius: cw * (0.1 + 0.25 * CGFloat(heat))))
    }

    // MARK: The brain-bot (rooftop)

    private static func brainBot(_ g: GraphicsContext, _ b: LDWorld.Boss, _ f: Frame, _ t: Double) {
        let cw = f.cw, L = f.lanes
        let wu = windup(b)
        let bob = CGFloat(sin(t * 1.9)) * L * 0.015
        let x0 = f.front
        let cx = x0 + cw * 1.3
        let lw = max(1.5, cw * 0.035)
        let metal = Color(red: 0.42, green: 0.38, blue: 0.55), metalDark = Color(red: 0.24, green: 0.2, blue: 0.34)
        let bodyC = CGPoint(x: cx, y: f.ground - L * 0.58 + bob)
        // Three legs; the front one lifts for a stomp.
        var lift: CGFloat = 0
        if let (m, p) = wu, m == .stomp { lift = p < 0.8 ? CGFloat(p / 0.8) : CGFloat(max(0, 1 - (p - 0.8) / 0.2)) }
        for (i, footX) in [x0 + cw * 0.15, cx + cw * 0.2, cx + cw * 1.2].enumerated() {
            let hipP = CGPoint(x: cx + CGFloat(i - 1) * cw * 0.55, y: bodyC.y + L * 0.06)
            let foot = CGPoint(x: footX - (i == 0 ? lift * cw * 0.3 : 0), y: f.ground - (i == 0 ? lift * L * 0.35 : 0))
            let knee = CGPoint(x: (hipP.x + foot.x) / 2 + (i == 0 ? -cw * 0.25 : cw * 0.2), y: min(hipP.y, foot.y) - L * 0.12)
            var leg = Path(); leg.move(to: hipP); leg.addLine(to: knee); leg.addLine(to: foot)
            g.stroke(leg, with: .color(ink), style: StrokeStyle(lineWidth: cw * 0.16 + lw, lineCap: .round, lineJoin: .round))
            g.stroke(leg, with: .color(i == 1 ? metalDark : metal), style: StrokeStyle(lineWidth: cw * 0.16, lineCap: .round, lineJoin: .round))
            g.fill(disc(knee, cw * 0.1), with: .color(Color(red: 1, green: 0.85, blue: 0.3)))
            g.fill(Path(roundedRect: CGRect(x: foot.x - cw * 0.22, y: foot.y - cw * 0.08, width: cw * 0.44, height: cw * 0.12), cornerRadius: 3), with: .color(metalDark))
        }
        // The claw arm at the back (holding a zombie while it winds up a drop).
        let clawBase = CGPoint(x: cx + cw * 0.8, y: bodyC.y - L * 0.08)
        let clawTip = CGPoint(x: clawBase.x + cw * 0.2, y: bodyC.y - L * 0.5)
        var clawArm = Path(); clawArm.move(to: clawBase); clawArm.addLine(to: CGPoint(x: clawBase.x + cw * 0.45, y: clawBase.y - L * 0.25)); clawArm.addLine(to: clawTip)
        g.stroke(clawArm, with: .color(ink), style: StrokeStyle(lineWidth: cw * 0.12 + lw, lineCap: .round, lineJoin: .round))
        g.stroke(clawArm, with: .color(metal), style: StrokeStyle(lineWidth: cw * 0.12, lineCap: .round, lineJoin: .round))
        var claw = Path()
        claw.move(to: CGPoint(x: clawTip.x - cw * 0.15, y: clawTip.y - cw * 0.2)); claw.addQuadCurve(to: CGPoint(x: clawTip.x + cw * 0.15, y: clawTip.y - cw * 0.2), control: CGPoint(x: clawTip.x, y: clawTip.y + cw * 0.1))
        g.stroke(claw, with: .color(Color(white: 0.8)), lineWidth: cw * 0.06)
        // Chassis with blinking lights.
        let chassis = oval(bodyC, cw * 1.15, L * 0.17)
        g.fill(chassis, with: .linearGradient(Gradient(colors: [metal.lit(0.2), metal, metalDark]), startPoint: CGPoint(x: 0, y: bodyC.y - L * 0.17), endPoint: CGPoint(x: 0, y: bodyC.y + L * 0.17)))
        g.stroke(chassis, with: .color(ink), lineWidth: lw)
        for k in 0..<5 {
            let on = (Int(t * 4) + k) % 3 == 0
            let p = CGPoint(x: bodyC.x - cw * 0.8 + CGFloat(k) * cw * 0.4, y: bodyC.y + L * 0.05)
            g.fill(disc(p, cw * 0.06), with: .color(on ? Color(red: 1, green: 0.3, blue: 0.3) : Color(red: 0.4, green: 0.1, blue: 0.1)))
        }
        // Glass dome with the brain.
        let dome = CGPoint(x: bodyC.x, y: bodyC.y - L * 0.1)
        let drx = cw * 0.95, dry = L * 0.36
        var glass = Path()
        glass.addArc(center: .zero, radius: 1, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        glass.closeSubpath()
        glass = glass.applying(CGAffineTransform(scaleX: drx, y: dry).concatenating(CGAffineTransform(translationX: dome.x, y: dome.y)))
        let brainC = CGPoint(x: dome.x, y: dome.y - dry * 0.45)
        var brain = Path()
        for i in 0...24 {
            let a = Double(i) / 24 * 2 * .pi
            let wob = 1 + 0.08 * CGFloat(sin(a * 7))
            let p = CGPoint(x: brainC.x + CGFloat(cos(a)) * drx * 0.72 * wob, y: brainC.y + CGFloat(sin(a)) * dry * 0.48 * wob)
            if i == 0 { brain.move(to: p) } else { brain.addLine(to: p) }
        }
        brain.closeSubpath()
        g.fill(brain, with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.78, blue: 0.82), Color(red: 0.92, green: 0.5, blue: 0.6)]), center: CGPoint(x: brainC.x - drx * 0.2, y: brainC.y - dry * 0.2), startRadius: 0, endRadius: drx))
        var folds = Path()
        folds.move(to: CGPoint(x: brainC.x, y: brainC.y - dry * 0.45)); folds.addLine(to: CGPoint(x: brainC.x, y: brainC.y + dry * 0.3))
        for k in 0..<4 {
            let y = brainC.y - dry * 0.3 + CGFloat(k) * dry * 0.18
            folds.move(to: CGPoint(x: brainC.x - drx * 0.55, y: y)); folds.addQuadCurve(to: CGPoint(x: brainC.x - drx * 0.1, y: y), control: CGPoint(x: brainC.x - drx * 0.32, y: y - dry * 0.12))
            folds.move(to: CGPoint(x: brainC.x + drx * 0.1, y: y + dry * 0.05)); folds.addQuadCurve(to: CGPoint(x: brainC.x + drx * 0.55, y: y + dry * 0.05), control: CGPoint(x: brainC.x + drx * 0.32, y: y + dry * 0.18))
        }
        g.stroke(folds, with: .color(Color(red: 0.75, green: 0.3, blue: 0.42)), lineWidth: 1.4)
        g.stroke(brain, with: .color(Color(red: 0.55, green: 0.2, blue: 0.3)), lineWidth: 1.4)
        // Two angry eyes on the brain.
        for dx in [-0.32, 0.05] as [CGFloat] {
            let e = CGPoint(x: brainC.x + dx * drx, y: brainC.y + dry * 0.05)
            g.fill(oval(e, drx * 0.13, dry * 0.11), with: .color(.white))
            g.stroke(oval(e, drx * 0.13, dry * 0.11), with: .color(ink), lineWidth: 1.2)
            g.fill(disc(CGPoint(x: e.x - drx * 0.04, y: e.y + dry * 0.01), drx * 0.055), with: .color(ink))
            var brow = Path(); brow.move(to: CGPoint(x: e.x - drx * 0.14, y: e.y - dry * 0.16)); brow.addLine(to: CGPoint(x: e.x + drx * 0.12, y: e.y - dry * 0.08))
            g.stroke(brow, with: .color(ink), lineWidth: 2)
        }
        g.fill(glass, with: .color(Color(red: 0.7, green: 0.9, blue: 1).opacity(0.22)))
        g.stroke(glass, with: .color(Color(white: 0.92)), lineWidth: lw)
        var shine = Path(); shine.addArc(center: CGPoint(x: dome.x - drx * 0.35, y: dome.y - dry * 0.6), radius: drx * 0.25, startAngle: .degrees(200), endAngle: .degrees(270), clockwise: false)
        g.stroke(shine, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        // The cannon arm: glowing orange for a fireball, blue for an iceball.
        var glowColor: Color? = nil
        var heat = 0.0
        if let (m, p) = wu, m == .roll {
            heat = p
            glowColor = b.moves % 2 == 0 ? Color(red: 1, green: 0.45, blue: 0.1) : Color(red: 0.35, green: 0.75, blue: 1)
        }
        let shoulder = CGPoint(x: cx - cw * 0.8, y: bodyC.y)
        let muzzle = CGPoint(x: x0 - cw * 0.2, y: bodyC.y + L * 0.12)
        var arm = Path(); arm.move(to: shoulder); arm.addLine(to: muzzle)
        g.stroke(arm, with: .color(ink), style: StrokeStyle(lineWidth: cw * 0.24 + lw, lineCap: .round))
        g.stroke(arm, with: .color(metal), style: StrokeStyle(lineWidth: cw * 0.24, lineCap: .round))
        g.fill(disc(muzzle, cw * 0.17), with: .color(metalDark))
        g.stroke(disc(muzzle, cw * 0.17), with: .color(ink), lineWidth: lw)
        if let gc = glowColor {
            g.fill(disc(muzzle, cw * (0.15 + 0.3 * CGFloat(heat))), with: .radialGradient(Gradient(colors: [.white, gc, gc.opacity(0)]), center: muzzle, startRadius: 0, endRadius: cw * (0.15 + 0.3 * CGFloat(heat))))
        }
    }

    // MARK: Telegraphs and shots

    /// Marked on the lawn under everything: target tiles, lanes about to freeze, aim lines, stomp shadows.
    static func underlay(_ ctx: GraphicsContext, boss b: LDWorld.Boss, world w: LDWorld, lay: LDLayout) {
        guard b.died == nil else { return }
        let cw = lay.cellW, ch = lay.cellH
        let t = w.t
        if let (m, p) = windup(b) {
            switch m {
            case .bombard:
                for tile in b.targets {
                    let c = lay.point(x: Double(tile.col) + 0.5, y: Double(tile.row) + 0.6)
                    let r = cw * (0.42 - 0.12 * CGFloat(p)) * CGFloat(1 + 0.08 * sin(t * 12))
                    var ring = Path()
                    ring.addEllipse(in: CGRect(x: c.x - r, y: c.y - r * 0.7, width: r * 2, height: r * 1.4))
                    ring.move(to: CGPoint(x: c.x - r * 1.25, y: c.y)); ring.addLine(to: CGPoint(x: c.x - r * 0.55, y: c.y))
                    ring.move(to: CGPoint(x: c.x + r * 0.55, y: c.y)); ring.addLine(to: CGPoint(x: c.x + r * 1.25, y: c.y))
                    ring.move(to: CGPoint(x: c.x, y: c.y - r)); ring.addLine(to: CGPoint(x: c.x, y: c.y - r * 0.4))
                    ring.move(to: CGPoint(x: c.x, y: c.y + r * 0.4)); ring.addLine(to: CGPoint(x: c.x, y: c.y + r))
                    ctx.stroke(ring, with: .color(Color(red: 1, green: 0.15, blue: 0.1).opacity(0.5 + 0.5 * p)), lineWidth: 2.2)
                    ctx.fill(LDLawnArt.oval(CGPoint(x: c.x, y: c.y + ch * 0.25), cw * 0.35 * CGFloat(p), cw * 0.1 * CGFloat(p)), with: .color(.black.opacity(0.25)))
                }
            case .graves, .ambush:
                for tile in b.targets {
                    let c = lay.point(x: Double(tile.col) + 0.5, y: Double(tile.row) + 0.8)
                    if w.params.scene == .desert {
                        // A little whirlwind of darker sand.
                        var swirl = ctx
                        swirl.opacity = 0.35 + 0.65 * p
                        swirl.fill(LDLawnArt.oval(c, cw * 0.42, ch * 0.1), with: .color(Color(red: 0.55, green: 0.38, blue: 0.18).opacity(0.45)))
                        for k in 0..<9 {
                            let a = t * 9 + Double(k) * 0.8
                            let r = cw * (0.12 + 0.045 * CGFloat(k)) * CGFloat(0.5 + 0.5 * p)
                            let q = CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y - CGFloat(k) * ch * 0.06 + CGFloat(sin(a)) * r * 0.3)
                            swirl.fill(LDLawnArt.disc(q, cw * 0.065), with: .color(Color(red: 0.62, green: 0.44, blue: 0.2)))
                        }
                    } else {
                        ctx.fill(LDLawnArt.oval(c, cw * 0.4 * CGFloat(p), cw * 0.12 * CGFloat(p)), with: .color(.black.opacity(0.3)))
                    }
                }
            case .freeze, .roll:
                if let row = b.targets.first?.row {
                    let a = lay.point(x: -0.6, y: Double(row)), z = lay.point(x: b.x, y: Double(row) + 1)
                    let lane = CGRect(x: a.x, y: a.y, width: z.x - a.x, height: z.y - a.y)
                    let col = m == .freeze ? Color(red: 0.6, green: 0.85, blue: 1) : (b.kind == .megabot && b.moves % 2 == 0 ? Color(red: 1, green: 0.5, blue: 0.2) : Color(red: 0.6, green: 0.85, blue: 1))
                    ctx.fill(Path(lane), with: .color(col.opacity(0.12 + 0.25 * p)))
                    var arrows = Path()
                    var x = Double(b.x) - 0.7
                    while x > -0.2 {
                        let c = lay.point(x: x, y: Double(row) + 0.5)
                        arrows.move(to: CGPoint(x: c.x + cw * 0.12, y: c.y - ch * 0.12)); arrows.addLine(to: CGPoint(x: c.x - cw * 0.08, y: c.y)); arrows.addLine(to: CGPoint(x: c.x + cw * 0.12, y: c.y + ch * 0.12))
                        x -= 1
                    }
                    ctx.stroke(arrows, with: .color(.white.opacity(0.35 + 0.4 * p)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            case .laser:
                for tile in b.targets {
                    let a = lay.point(x: -0.6, y: Double(tile.row) + 0.45), z = lay.point(x: b.x - 0.3, y: Double(tile.row) + 0.45)
                    var aim = Path(); aim.move(to: a); aim.addLine(to: z)
                    ctx.stroke(aim, with: .color(Color(red: 1, green: 0.15, blue: 0.15).opacity(0.35 + 0.5 * p)), style: StrokeStyle(lineWidth: 1.5 + 2 * CGFloat(p), dash: [6, 5], dashPhase: CGFloat(t * 40)))
                }
            case .stomp:
                for tile in b.targets {
                    let c = lay.point(x: Double(tile.col) + 0.5, y: Double(tile.row) + 0.75)
                    ctx.fill(LDLawnArt.oval(c, cw * 0.48 * CGFloat(0.4 + 0.6 * p), ch * 0.2 * CGFloat(0.4 + 0.6 * p)), with: .color(.black.opacity(0.18 + 0.25 * p)))
                }
            case .charge:
                for r in b.rows {
                    var chevrons = Path()
                    var x = Double(b.x) - 0.5
                    while x > LDWorld.chargeStop {
                        let c = lay.point(x: x, y: Double(r) + 0.5)
                        chevrons.move(to: CGPoint(x: c.x + cw * 0.15, y: c.y - ch * 0.15)); chevrons.addLine(to: CGPoint(x: c.x - cw * 0.1, y: c.y)); chevrons.addLine(to: CGPoint(x: c.x + cw * 0.15, y: c.y + ch * 0.15))
                        x -= 0.7
                    }
                    ctx.stroke(chevrons, with: .color(Color(red: 1, green: 0.25, blue: 0.1).opacity(0.3 + 0.6 * p * (0.6 + 0.4 * sin(t * 14)))), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
            case .summon:
                break
            }
        }
        // The lane that just froze glitters; a stomp leaves a crack.
        if b.last == .freeze && t - b.lastAt < 0.8, let row = b.lastTargets.first?.row {
            let a = lay.point(x: -0.6, y: Double(row)), z = lay.point(x: b.x, y: Double(row) + 1)
            ctx.fill(Path(CGRect(x: a.x, y: a.y, width: z.x - a.x, height: z.y - a.y)), with: .color(Color(red: 0.85, green: 0.95, blue: 1).opacity(0.5 * (1 - (t - b.lastAt) / 0.8))))
        }
    }

    /// Drawn over everything: shots in flight, beams and breath at the moment they land.
    static func overlay(_ ctx: GraphicsContext, boss b: LDWorld.Boss, world w: LDWorld, lay: LDLayout) {
        guard b.died == nil else { return }
        let cw = lay.cellW, ch = lay.cellH
        let t = w.t
        if let (m, p) = windup(b) {
            switch m {
            case .bombard:
                // Shells fly the last stretch of the windup.
                let start = 0.45
                guard p > start else { break }
                let k = CGFloat((p - start) / (1 - start))
                let from: CGPoint
                switch b.kind {
                case .captain: from = lay.point(x: b.x - 0.45, y: b.y + 2.3)
                case .outlaw: from = lay.point(x: b.x + 2.1, y: b.y - 0.1)
                default: from = lay.point(x: b.x + 1.6, y: b.y - 0.3)
                }
                for (i, tile) in b.targets.enumerated() {
                    let to = lay.point(x: Double(tile.col) + 0.5, y: Double(tile.row) + 0.6)
                    let kk = max(0, min(1, k * 1.15 - CGFloat(i) * 0.05))
                    let c = CGPoint(x: from.x + (to.x - from.x) * kk, y: from.y + (to.y - from.y) * kk - sin(kk * .pi) * ch * 1.8)
                    switch b.kind {
                    case .captain:
                        ctx.fill(LDLawnArt.disc(c, cw * 0.15), with: .radialGradient(Gradient(colors: [Color(white: 0.5), Color(white: 0.08)]), center: CGPoint(x: c.x - cw * 0.05, y: c.y - cw * 0.05), startRadius: 0, endRadius: cw * 0.2))
                    case .outlaw:
                        dynamite(ctx, at: c, s: cw * 0.35, angle: Double(kk) * 9, t: t)
                    default:
                        missile(ctx, at: c, toward: to, s: cw * 0.4, t: t)
                    }
                }
            case .ambush where b.kind == .captain:
                // Pirates swing in on ropes from the rigging, landing on their tiles.
                let zh = min(ch * 1.22, cw * 1.9)
                let top = Double(lay.rows.first ?? 0)
                for tile in b.targets {
                    let anchor = lay.point(x: Double(tile.col) + 0.35, y: top - 1.3)
                    let start = lay.point(x: Double(tile.col) + 2.4, y: Double(tile.row) - 0.9)
                    let end = lay.point(x: Double(tile.col) + 0.9, y: Double(tile.row) + 0.92)
                    let a0 = atan2(Double(start.y - anchor.y), Double(start.x - anchor.x)), a1 = atan2(Double(end.y - anchor.y), Double(end.x - anchor.x))
                    let r0 = hypot(start.x - anchor.x, start.y - anchor.y), r1 = hypot(end.x - anchor.x, end.y - anchor.y)
                    let k = CGFloat(p)
                    let a = a0 + (a1 - a0) * Double(k)
                    let r = r0 + (r1 - r0) * k
                    let feet = CGPoint(x: anchor.x + CGFloat(cos(a)) * r, y: anchor.y + CGFloat(sin(a)) * r)
                    let hand = CGPoint(x: feet.x - zh * 0.25, y: feet.y - zh * 0.7)
                    var rope = Path(); rope.move(to: anchor); rope.addLine(to: hand)
                    ctx.stroke(rope, with: .color(Color(red: 0.85, green: 0.72, blue: 0.45)), lineWidth: 2)
                    let fake = LDWorld.Zombie(id: tile.row * 10 + tile.col, kind: LDWorld.ambusher(tile), row: tile.row, x: 0, hp: 6, armor: 8, shield: 0, speedK: 1, born: -9)
                    LDLawnArt.zombie(ctx, feet: feet, h: zh, z: fake, t: t, scene: w.params.scene, cell: cw)
                }
            case .ambush where b.kind == .megabot:
                for tile in b.targets {
                    let c = lay.point(x: Double(tile.col) + 0.9, y: Double(tile.row) + 0.92)
                    let fall = CGFloat(p * p)
                    // Its shadow grows where it will land.
                    ctx.fill(LDLawnArt.oval(c, cw * 0.35 * fall, cw * 0.1 * fall), with: .color(.black.opacity(0.3)))
                    let zh = min(ch * 1.22, cw * 1.9)
                    let top = lay.point(x: 0, y: Double(lay.rows.first ?? 0) - 1.5).y
                    let fake = LDWorld.Zombie(id: tile.row * 10 + tile.col, kind: LDWorld.ambusher(tile), row: tile.row, x: 0, hp: 6, armor: 8, shield: 0, speedK: 1, born: -9)
                    LDLawnArt.zombie(ctx, feet: CGPoint(x: c.x, y: top + (c.y - top) * fall), h: zh, z: fake, t: t, scene: w.params.scene, cell: cw)
                }
            case .freeze:
                break
            default:
                break
            }
        }
        // Moments after a move lands.
        let since = t - b.lastAt
        switch b.last {
        case .laser where since < 0.35:
            for tile in b.lastTargets {
                let a = lay.point(x: -0.6, y: Double(tile.row) + 0.45), z = lay.point(x: b.x - 0.3, y: Double(tile.row) + 0.45)
                var beam = Path(); beam.move(to: a); beam.addLine(to: z)
                let k = 1 - since / 0.35
                ctx.stroke(beam, with: .color(Color(red: 1, green: 0.2, blue: 0.2).opacity(0.6 * k)), lineWidth: ch * 0.3)
                ctx.stroke(beam, with: .color(.white.opacity(k)), lineWidth: ch * 0.08)
            }
        case .freeze where since < 0.6:
            if let row = b.lastTargets.first?.row {
                var mist = ctx
                mist.opacity = 1 - since / 0.6
                var x = Double(b.x) - 0.2
                var i = 0.0
                while x > -0.6 {
                    let c = lay.point(x: x, y: Double(row) + 0.5)
                    mist.fill(LDLawnArt.disc(CGPoint(x: c.x, y: c.y + CGFloat(sin(i * 2 + t * 8)) * ch * 0.12), cw * (0.3 + 0.1 * CGFloat(LDLawnArt.hash(i)))), with: .color(Color(red: 0.85, green: 0.95, blue: 1).opacity(0.75)))
                    x -= 0.45; i += 1
                }
            }
        case .stomp where since < 0.5:
            for tile in b.lastTargets {
                let c = lay.point(x: Double(tile.col) + 0.5, y: Double(tile.row) + 0.8)
                let k = CGFloat(since / 0.5)
                var ring = Path(); ring.addEllipse(in: CGRect(x: c.x - cw * (0.3 + 0.5 * k), y: c.y - ch * (0.1 + 0.15 * k), width: cw * (0.6 + k), height: ch * (0.2 + 0.3 * k)))
                ctx.stroke(ring, with: .color(.white.opacity(Double(1 - k) * 0.8)), lineWidth: 2)
            }
        default:
            break
        }
    }

    static func missile(_ ctx: GraphicsContext, at c: CGPoint, toward to: CGPoint, s: CGFloat, t: Double) {
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .radians(atan2(Double(to.y - c.y), Double(to.x - c.x))))
        g.fill(LDLawnArt.oval(CGPoint(x: -s * 0.55, y: 0), s * 0.3 * CGFloat(0.8 + 0.2 * sin(t * 40)), s * 0.1), with: .color(Color(red: 1, green: 0.7, blue: 0.2)))
        g.fill(Path(roundedRect: CGRect(x: -s * 0.35, y: -s * 0.08, width: s * 0.6, height: s * 0.16), cornerRadius: s * 0.08), with: .color(Color(white: 0.92)))
        var nose = Path(); nose.move(to: CGPoint(x: s * 0.25, y: -s * 0.08)); nose.addLine(to: CGPoint(x: s * 0.42, y: 0)); nose.addLine(to: CGPoint(x: s * 0.25, y: s * 0.08)); nose.closeSubpath()
        g.fill(nose, with: .color(Color(red: 0.9, green: 0.15, blue: 0.15)))
        var fins = Path(); fins.move(to: CGPoint(x: -s * 0.35, y: -s * 0.08)); fins.addLine(to: CGPoint(x: -s * 0.45, y: -s * 0.18)); fins.addLine(to: CGPoint(x: -s * 0.25, y: -s * 0.08))
        fins.move(to: CGPoint(x: -s * 0.35, y: s * 0.08)); fins.addLine(to: CGPoint(x: -s * 0.45, y: s * 0.18)); fins.addLine(to: CGPoint(x: -s * 0.25, y: s * 0.08))
        g.fill(fins, with: .color(Color(red: 0.9, green: 0.15, blue: 0.15)))
    }

    // MARK: Health-bar faces

    static func icon(_ ctx: GraphicsContext, kind: LDBossKind, at c: CGPoint, r: CGFloat) {
        ctx.fill(disc(c, r), with: .color(Color(red: 0.15, green: 0.08, blue: 0.05)))
        ctx.stroke(disc(c, r), with: .color(Color(red: 0.95, green: 0.8, blue: 0.4)), lineWidth: 1.4)
        var g = ctx
        g.clip(to: disc(c, r * 0.92))
        let skin = Color(red: 0.58, green: 0.66, blue: 0.5)
        switch kind {
        case .groundskeeper:
            g.fill(oval(CGPoint(x: c.x, y: c.y + r * 0.2), r * 0.6, r * 0.62), with: .color(skin))
            g.fill(oval(CGPoint(x: c.x, y: c.y - r * 0.25), r * 1.1, r * 0.22), with: .color(Color(red: 0.92, green: 0.8, blue: 0.45)))
            g.fill(Path(roundedRect: CGRect(x: c.x - r * 0.5, y: c.y - r * 0.75, width: r, height: r * 0.5), cornerRadius: r * 0.2), with: .color(Color(red: 0.95, green: 0.84, blue: 0.5)))
            g.fill(disc(CGPoint(x: c.x - r * 0.2, y: c.y + r * 0.12), r * 0.13), with: .color(.white))
        case .pharaoh:
            g.fill(Path(CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .linearGradient(Gradient(colors: [Color(red: 0.98, green: 0.78, blue: 0.22), Color(red: 0.12, green: 0.28, blue: 0.72), Color(red: 0.98, green: 0.78, blue: 0.22), Color(red: 0.12, green: 0.28, blue: 0.72)]),
                                                                                                      startPoint: CGPoint(x: 0, y: c.y - r), endPoint: CGPoint(x: 0, y: c.y + r)))
            g.fill(oval(CGPoint(x: c.x, y: c.y + r * 0.1), r * 0.5, r * 0.6), with: .color(Color(red: 0.9, green: 0.84, blue: 0.68)))
            g.fill(disc(CGPoint(x: c.x - r * 0.18, y: c.y), r * 0.1), with: .color(Color(red: 0.6, green: 1, blue: 0.4)))
            g.fill(disc(CGPoint(x: c.x + r * 0.18, y: c.y), r * 0.1), with: .color(Color(red: 0.6, green: 1, blue: 0.4)))
        case .captain:
            g.fill(oval(CGPoint(x: c.x, y: c.y + r * 0.25), r * 0.6, r * 0.6), with: .color(skin))
            var hat = Path()
            hat.move(to: CGPoint(x: c.x - r, y: c.y - r * 0.05)); hat.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y - r * 0.05), control: CGPoint(x: c.x, y: c.y - r * 1.3))
            g.fill(hat, with: .color(Color(white: 0.08)))
            g.fill(oval(CGPoint(x: c.x + r * 0.15, y: c.y + r * 0.15), r * 0.18, r * 0.16), with: .color(Color(white: 0.05)))
        case .outlaw:
            g.fill(Path(CGRect(x: c.x - r, y: c.y - r * 0.1, width: r * 2, height: r)), with: .color(Color(white: 0.15)))
            g.fill(Path(CGRect(x: c.x - r * 0.25, y: c.y - r * 0.85, width: r * 0.5, height: r * 0.8)), with: .color(Color(white: 0.2)))
            g.fill(disc(CGPoint(x: c.x - r * 0.5, y: c.y + r * 0.1), r * 0.22), with: .color(Color(red: 1, green: 0.9, blue: 0.5)))
            g.fill(Path(CGRect(x: c.x - r, y: c.y + r * 0.55, width: r * 2, height: r * 0.2)), with: .color(Color(red: 0.72, green: 0.12, blue: 0.1)))
        case .mammoth:
            g.fill(oval(CGPoint(x: c.x + r * 0.1, y: c.y), r * 0.8, r * 0.7), with: .color(Color(red: 0.5, green: 0.32, blue: 0.2)))
            var tusk = Path(); tusk.move(to: CGPoint(x: c.x - r * 0.2, y: c.y + r * 0.3)); tusk.addQuadCurve(to: CGPoint(x: c.x - r * 0.9, y: c.y - r * 0.1), control: CGPoint(x: c.x - r * 0.8, y: c.y + r * 0.7))
            g.stroke(tusk, with: .color(Color(red: 0.97, green: 0.94, blue: 0.84)), style: StrokeStyle(lineWidth: r * 0.18, lineCap: .round))
            g.fill(disc(CGPoint(x: c.x - r * 0.15, y: c.y - r * 0.15), r * 0.1), with: .color(.white))
        case .mech:
            g.fill(Path(roundedRect: CGRect(x: c.x - r * 0.7, y: c.y - r * 0.5, width: r * 1.4, height: r), cornerRadius: r * 0.2), with: .color(Color(white: 0.7)))
            g.fill(Path(CGRect(x: c.x - r * 0.55, y: c.y - r * 0.12, width: r * 1.1, height: r * 0.24)), with: .color(Color(red: 0.2, green: 0.95, blue: 0.95)))
            g.fill(disc(CGPoint(x: c.x - r * 0.2, y: c.y), r * 0.1), with: .color(Color(red: 1, green: 0.2, blue: 0.2)))
        case .megabot:
            g.fill(oval(CGPoint(x: c.x, y: c.y + r * 0.05), r * 0.75, r * 0.55), with: .color(Color(red: 0.95, green: 0.6, blue: 0.7)))
            var folds = Path(); folds.move(to: CGPoint(x: c.x, y: c.y - r * 0.4)); folds.addLine(to: CGPoint(x: c.x, y: c.y + r * 0.5))
            g.stroke(folds, with: .color(Color(red: 0.7, green: 0.3, blue: 0.4)), lineWidth: 1.2)
            g.fill(disc(CGPoint(x: c.x - r * 0.3, y: c.y), r * 0.13), with: .color(.white))
            g.fill(disc(CGPoint(x: c.x + r * 0.1, y: c.y), r * 0.13), with: .color(.white))
        }
    }
}
