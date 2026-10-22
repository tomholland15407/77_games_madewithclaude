//
//  SniperGame.swift
//  A Banana Game
//
//  Reflex — a scoped marksman game. You look through a sniper SCOPE at a wide vista: DRAG to
//  pan the scope across the scene, tap FIRE to shoot whatever sits under the crosshair. A shot
//  is a pure hitscan at the reticle, so aiming is exact — line it up and the target drops.
//
//  The opening is calm: enemies can't draw on you until a beat AFTER your first shot. Once armed,
//  a red enemy occasionally stops, turns, and RAISES its weapon — a red beam paints toward your
//  scope and thickens as it charges; if it completes you lose a drop of blood (you can take a few
//  hits, shown as a blood count). Miss a shot and the nearest enemy is startled into aiming, so
//  wild shots cost you. Your magazine is limited — run dry with targets left and it's over. Down
//  every target to win; bleed out, run out of ammo, or let the clock expire and you fall back to
//  level 1.
//
//  7 levels: more targets, faster patrols, quicker & more frequent aim-ups, a jumpier scope-sway
//  and a leaner magazine — through a day → dusk → night mood ramp. Drag to aim → locks the feed
//  while playing (with the free skip button).
//
//  Drawn as a mobile sniper game: the crafted scope (dark mask, rim with range ticks, mil-dot
//  reticle, recoil kick, muzzle bloom, glass glint) over a parallax vista — snow-capped ridges, a
//  pine treeline, an outpost with huts, a flag and a watchtower, sandbags and grass — from day to
//  dusk to a starry night. The red soldiers are vector stick figures (helmet, vest, rifle) that walk
//  their beat, shoulder the rifle toward your scope when they draw on you, and topple when hit. The
//  counters are icons: cartridges, blood drops, a helmeted head.
//

import SwiftUI

enum SniperGame {
    static let definition = GameDefinition(
        id: "sniper",
        title: "Sniper",
        emoji: "🍌",
        genre: .reflex,
        levelCount: 7,
        locksFeed: true,       // drag to pan the scope — lock the pager while playing
        manual: GameManual(
            bullets: [
                "Drag to pan your scope across the vista; tap FIRE to hitscan whatever is under the crosshair.",
                "Red soldiers patrol; one periodically stops and paints a growing red beam at you.",
                "Drop it before the beam completes or you take a hit (you can survive a few).",
                "Missing startles the nearest enemy into aiming, and your magazine is limited.",
            ],
            bulletsVI: [
                "Kéo để lia ống ngắm khắp cảnh; chạm BẮN để bắn trúng ngay thứ dưới tâm ngắm.",
                "Lính đỏ tuần tra; một tên thỉnh thoảng dừng lại và vẽ một tia đỏ lớn dần nhắm vào bạn.",
                "Hạ nó trước khi tia hoàn tất, nếu không bạn trúng đạn (bạn chịu được vài phát).",
                "Bắn trượt làm kẻ gần nhất giật mình giương súng, và băng đạn của bạn có hạn.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(SniperView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct SniperView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    // MARK: - Difficulty (from level)
    private var targetCount: Int    { [2, 3, 3, 4, 5, 6, 7][min(level, 7) - 1] }
    private var walkSpeed: Double   { [0.05, 0.06, 0.07, 0.08, 0.09, 0.10, 0.11][min(level, 7) - 1] } // world/sec
    /// Average seconds a target patrols before it decides to raise its weapon.
    private var aimEvery: Double    { [6.5, 5.6, 4.8, 4.0, 3.3, 2.7, 2.2][min(level, 7) - 1] }
    /// How long the raised-weapon telegraph lasts before it fires (your window to drop it).
    private var aimTime: Double     { [3.0, 2.6, 2.3, 2.0, 1.7, 1.4, 1.1][min(level, 7) - 1] }
    private var swayAmp: Double     { [0.004, 0.006, 0.008, 0.011, 0.014, 0.018, 0.022][min(level, 7) - 1] }
    private var ammo0: Int          { targetCount + [5, 5, 4, 4, 3, 2, 2][min(level, 7) - 1] }
    private var timeLimit: Double   { Double(16 + targetCount * 7) }
    /// Hits you can take before you're down — your "blood". Fewer at higher levels.
    private var maxHP: Int          { [4, 4, 3, 3, 3, 2, 2][min(level, 7) - 1] }
    /// Enemies can't draw on you until this long AFTER your first shot — the opening is calm.
    private var armDelay0: Double   { [2.4, 2.2, 2.0, 1.8, 1.6, 1.4, 1.2][min(level, 7) - 1] }

    // MARK: - World geometry (world units; the scene is `sceneW` wide, 1.0 tall)
    private let sceneW = 2.4
    private let viewH = 0.62            // world-units of scene height visible through the scope
    private let groundV = 0.60          // horizon / where targets stand
    private let targetH = 0.085         // world height of a soldier

    // MARK: - Model
    private struct Target: Identifiable {
        let id = UUID()
        var x: Double
        let y: Double            // feet line
        var dir: Double          // +1 / -1
        let minX: Double, maxX: Double
        var speed: Double
        var aimCD: Double        // countdown to raising the weapon
        var aiming = false
        var aimT = 0.0           // remaining telegraph while aiming
        var pause = 0.0
    }
    private struct Burst: Identifiable { let id = UUID(); let wx: Double; let wy: Double; let color: Color; let big: Bool }
    private struct Ridge { let x: Double; let top: Double }
    private struct Building { let x: Double; let w: Double; let h: Double; let shade: Double }
    private struct Prop { let x: Double; let kind: Int }   // ground cover / tufts

    private enum Phase { case play, done }
    @State private var phase: Phase = .play

    @State private var aim = CGPoint(x: 0.4, y: 0.52)
    @State private var targets: [Target] = []
    @State private var bursts: [Burst] = []
    @State private var ammo = 0
    @State private var hp = 0
    @State private var hasFired = false
    @State private var armDelay = 0.0
    @State private var hurt = 0.0             // red hit-flash, decays
    @State private var timeLeft = 0.0
    @State private var recoil = 0.0
    @State private var muzzle = 0.0
    @State private var animT = 0.0
    @State private var shakeTick = 0
    @State private var built = false

    // Scene scenery (generated once so it never flickers).
    @State private var ridges: [Ridge] = []
    @State private var midline: [Ridge] = []
    @State private var buildings: [Building] = []
    @State private var props: [Prop] = []

    @State private var area: CGSize = .zero
    @State private var lastDrag: CGSize = .zero
    @State private var demoFire = false     // FIRE button flashed in the demo
    @State private var downed: [SNDown] = []  // presentation: soldiers just shot, toppling

    private var danger: Bool { targets.contains { $0.aiming } }
    /// Enemies only start drawing on you a beat after your first shot.
    private var armed: Bool { hasFired && armDelay <= 0 }

    // MARK: - Body
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let s = h / viewH                       // pixels per world unit
            ZStack {
                sceneLayer(w: w, h: h, s: s)
                    .offset(y: -CGFloat(recoil) * h * 0.02)
                    .offset(x: CGFloat(recoil) * CGFloat.random(in: -3...3))
                    .clipShape(Circle())

                scopeOverlay(w: w, h: h, s: s).allowsHitTesting(false)
                muzzleBloom(w: w, h: h).allowsHitTesting(false)
                if hurt > 0 {
                    Color(red: 0.8, green: 0.05, blue: 0.05).opacity(hurt * 0.38).allowsHitTesting(false)
                }

                // Panning happens on a dedicated clear surface UNDER the HUD/FIRE button, so it
                // never fights the FIRE tap or the page's bottom-centre skip chevron.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                guard phase == .play else { return }
                                let dx = v.translation.width - lastDrag.width
                                let dy = v.translation.height - lastDrag.height
                                lastDrag = v.translation
                                pan(dx: dx, dy: dy, s: s)
                            }
                            .onEnded { _ in lastDrag = .zero }
                    )

                hud(w: w, h: h).allowsHitTesting(false)
                controls
            }
            .frame(width: w, height: h)
            .clipped()
            .screenShake(shakeTick, amount: 5)
            .onAppear { area = geo.size }
            .onChange(of: geo.size) { _, n in area = n }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { isDemo ? await runDemo() : await run() }
        // A soldier that drops out of the list was shot: it topples where it stood.
        .onChange(of: targets.map { SNSeen(id: $0.id, x: $0.x, y: $0.y, dir: $0.dir) }) { old, new in
            let now = Date()
            for o in old where !new.contains(where: { $0.id == o.id }) {
                downed.append(SNDown(id: o.id, wx: o.x, wy: o.y, facing: o.dir, at: now))
            }
        }
        .task(id: downed.count) {
            guard !downed.isEmpty else { return }
            try? await Task.sleep(for: .seconds(1.3))
            guard !Task.isCancelled else { return }
            let now = Date()
            downed.removeAll { now.timeIntervalSince($0.at) > 1.2 }
        }
    }

    // MARK: - Demo (live manual clip)

    /// Pan onto each stationary target and fire the real hitscan `fire()` (exact under
    /// the reticle → always connects). A single frame loop keeps the scope alive (sway,
    /// recoil/muzzle decay) so there are no leaked child tasks.
    private func runDemo() async {
        while !Task.isCancelled {
            demoSetup()
            let gy = groundV - Double(targetH) / 2
            await demoWait(0.6)
            if let t = targets.first { await demoPan(to: t.x, y: gy, dur: 0.85) }
            await demoWait(0.22); await demoShoot(); await demoWait(0.7)
            if let t = targets.first { await demoPan(to: t.x, y: gy, dur: 0.85) }
            await demoWait(0.22); await demoShoot(); await demoWait(1.3)   // last shot wins; hold on the cleared vista
        }
    }

    private func demoSetup() {
        if !built { setup(); built = true }   // scenery + defaults once (no per-loop reshuffle)
        phase = .play
        ammo = ammo0
        hp = maxHP
        hasFired = false; armDelay = 0; hurt = 0; recoil = 0; muzzle = 0
        bursts = []
        // Two stationary targets at fixed, in-view spots.
        targets = [
            Target(x: 0.80, y: groundV, dir: -1, minX: 0.80, maxX: 0.80, speed: 0, aimCD: .infinity),
            Target(x: 1.62, y: groundV, dir: 1, minX: 1.62, maxX: 1.62, speed: 0, aimCD: .infinity),
        ]
        aim = CGPoint(x: 0.44, y: 0.52)
    }

    /// Advance the ambient clock one frame (sway animation + recoil/muzzle/hurt decay).
    private func demoTick(_ dt: Double) {
        animT += dt
        if recoil > 0 { recoil = max(0, recoil - dt * 6) }
        if muzzle > 0 { muzzle = max(0, muzzle - dt) }
        if hurt > 0 { hurt = max(0, hurt - dt * 2.2) }
    }

    private func demoWait(_ dur: Double) async {
        let steps = max(1, Int(dur / 0.016))
        for _ in 0..<steps {
            guard !Task.isCancelled else { return }
            demoTick(0.016)
            try? await Task.sleep(for: .seconds(0.016))
        }
    }

    /// Flash the FIRE button, take the shot, then keep the clock ticking briefly.
    private func demoShoot() async {
        withAnimation(.easeOut(duration: 0.1)) { demoFire = true }
        fire()
        await demoWait(0.18)
        withAnimation(.easeIn(duration: 0.1)) { demoFire = false }
    }

    private func demoPan(to gx: Double, y gy: Double, dur: Double) async {
        let sx = Double(aim.x), sy = Double(aim.y)
        let steps = max(1, Int(dur / 0.016))
        for k in 1...steps {
            guard !Task.isCancelled else { return }
            let f = 0.5 - 0.5 * cos(.pi * Double(k) / Double(steps))   // easeInOut
            aim.x = CGFloat(sx + (gx - sx) * f)
            aim.y = CGFloat(sy + (gy - sy) * f)
            demoTick(0.016)
            try? await Task.sleep(for: .seconds(0.016))
        }
    }

    // MARK: - Scene
    private var sky: (Color, Color) {
        switch min(level, 7) {
        case 1: return (Color(red: 0.50, green: 0.70, blue: 0.92), Color(red: 0.82, green: 0.88, blue: 0.80))
        case 2: return (Color(red: 0.42, green: 0.60, blue: 0.86), Color(red: 0.86, green: 0.82, blue: 0.62))
        case 3: return (Color(red: 0.58, green: 0.44, blue: 0.52), Color(red: 0.95, green: 0.66, blue: 0.40))
        case 4: return (Color(red: 0.40, green: 0.30, blue: 0.48), Color(red: 0.78, green: 0.44, blue: 0.42))
        case 5: return (Color(red: 0.16, green: 0.16, blue: 0.30), Color(red: 0.36, green: 0.28, blue: 0.40))
        case 6: return (Color(red: 0.10, green: 0.10, blue: 0.22), Color(red: 0.24, green: 0.18, blue: 0.30))
        default: return (Color(red: 0.06, green: 0.07, blue: 0.16), Color(red: 0.16, green: 0.12, blue: 0.22))
        }
    }
    private var groundColor: Color { sky.1.shade(0.55) }

    private func sceneLayer(w: CGFloat, h: CGFloat, s: CGFloat) -> some View {
        ZStack {
            // Sky, ridges, treeline, outpost, ground, cover, the soldiers and their aim beams: one
            // Canvas. The timeline only runs to finish a toppling soldier after the loop has stopped.
            TimelineView(.animation(paused: downed.isEmpty || phase == .play)) { tl in
                Canvas { ctx, size in
                    let now = max(tl.date, Date())
                    drawVista(ctx, size: size, s: s)
                    drawSoldiers(ctx, w: w, h: h, s: s, now: now)
                }
            }

            // Bursts (world-anchored).
            ForEach(bursts) { b in
                let p = worldToScreen(b.wx, b.wy, w: w, h: h, s: s)
                ParticleBurstView(color: b.color, count: b.big ? 20 : 10,
                                  spread: b.big ? 70 : 34, gravity: 18) {
                    bursts.removeAll { $0.id == b.id }
                }
                .position(p)
            }
        }
    }

    /// The vista, same layers and parallax as before (sky 0.2, ridge 0.35, treeline + outpost 0.6,
    /// ground 1): snow-capped ridges, a pine treeline, huts and a watchtower, sandbags and grass.
    private func drawVista(_ ctx: GraphicsContext, size: CGSize, s: CGFloat) {
        let W = size.width, H = size.height
        func P(_ wx: Double, _ wy: Double, _ par: Double) -> CGPoint {
            CGPoint(x: W / 2 + CGFloat((wx - Double(aim.x)) * par) * s,
                    y: H / 2 + CGFloat((wy - Double(aim.y)) * par) * s)
        }
        let night = level >= 5
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [sky.0, sky.1]), startPoint: .zero, endPoint: CGPoint(x: 0, y: H)))
        if night {
            var stars = Path()
            for i in 0..<70 {
                let q = P(SNArt.hash(Double(i) * 3.1) * sceneW, 0.02 + SNArt.hash(Double(i) * 7.7) * 0.42, 0.15)
                let d: CGFloat = 1 + CGFloat(SNArt.hash(Double(i) * 1.9)) * 1.6
                stars.addEllipse(in: CGRect(x: q.x, y: q.y, width: d, height: d))
            }
            ctx.fill(stars, with: .color(.white.opacity(0.8)))
        }
        // Sun / moon disc with a soft glow.
        let disc = P(sceneW * 0.5, 0.24, 0.2)
        let dr = min(W, H) * 0.06
        let discCol = level >= 5 ? Color(white: 0.96) : Color(red: 1, green: 0.95, blue: 0.8)
        ctx.fill(Path(ellipseIn: CGRect(x: disc.x - dr * 2.4, y: disc.y - dr * 2.4, width: dr * 4.8, height: dr * 4.8)),
                 with: .radialGradient(Gradient(colors: [discCol.opacity(0.35), discCol.opacity(0)]), center: disc, startRadius: dr, endRadius: dr * 2.4))
        ctx.fill(Path(ellipseIn: CGRect(x: disc.x - dr, y: disc.y - dr, width: dr * 2, height: dr * 2)), with: .color(discCol.opacity(0.9)))
        if !night {
            var clouds = Path()
            for i in 0..<7 {
                let c = P(SNArt.hash(Double(i) * 5.3) * sceneW, 0.1 + SNArt.hash(Double(i) * 2.3) * 0.16, 0.25)
                let cw = CGFloat(0.06 + 0.05 * SNArt.hash(Double(i) * 9.1)) * s * 0.25
                for k in 0..<3 {
                    let off = CGFloat(k - 1) * cw * 0.55
                    clouds.addEllipse(in: CGRect(x: c.x + off - cw * 0.5, y: c.y - cw * (k == 1 ? 0.42 : 0.28), width: cw, height: cw * (k == 1 ? 0.7 : 0.5)))
                }
            }
            ctx.fill(clouds, with: .color(.white.opacity(level >= 3 ? 0.35 : 0.55)))
        }

        // Far ridge (par 0.35) with snowcaps on the high peaks.
        if !ridges.isEmpty {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: H))
            p.addLine(to: P(ridges[0].x, ridges[0].top, 0.35))
            for r in ridges { p.addLine(to: P(r.x, r.top, 0.35)) }
            let last = P(groundV, groundV, 0.35)
            p.addLine(to: CGPoint(x: W, y: last.y))
            p.addLine(to: CGPoint(x: W, y: H)); p.closeSubpath()
            let top = P(0, groundV - 0.2, 0.35).y, bottom = P(0, groundV, 0.35).y
            ctx.fill(p, with: .linearGradient(Gradient(colors: [sky.1.shade(0.22), sky.1.shade(0.42)]),
                                              startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom)))
            var snow = Path()
            for (i, r) in ridges.enumerated() where r.top < groundV - 0.165 && i > 0 && i < ridges.count - 1 {
                let peak = P(r.x, r.top, 0.35)
                let l = P(ridges[i - 1].x, ridges[i - 1].top, 0.35), rr = P(ridges[i + 1].x, ridges[i + 1].top, 0.35)
                snow.move(to: peak)
                snow.addLine(to: CGPoint(x: peak.x + (l.x - peak.x) * 0.3, y: peak.y + (l.y - peak.y) * 0.3))
                snow.addLine(to: CGPoint(x: peak.x + (rr.x - peak.x) * 0.3, y: peak.y + (rr.y - peak.y) * 0.3))
                snow.closeSubpath()
            }
            ctx.fill(snow, with: .color(Color.white.opacity(night ? 0.35 : 0.75)))
        }
        // Mid treeline (par 0.6): the old band, crowned with pines.
        if !midline.isEmpty {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: H))
            for r in midline { p.addLine(to: P(r.x, r.top + 0.03, 0.6)) }
            p.addLine(to: CGPoint(x: W, y: H)); p.closeSubpath()
            let treeCol = sky.1.shade(0.52)
            ctx.fill(p, with: .color(treeCol))
            var pines = Path()
            for r in midline {
                let tip = P(r.x, r.top, 0.6), foot = P(r.x, r.top + 0.05, 0.6)
                let hw = CGFloat(0.018) * s * 0.6
                pines.move(to: tip); pines.addLine(to: CGPoint(x: tip.x + hw, y: foot.y)); pines.addLine(to: CGPoint(x: tip.x - hw, y: foot.y)); pines.closeSubpath()
            }
            ctx.fill(pines, with: .color(treeCol))
        }
        // Outpost (par 0.6): huts with a roof line and a door, every third one a watchtower.
        for (i, b) in buildings.enumerated() {
            let base = P(b.x, groundV, 0.6)
            let bw = CGFloat(b.w) * s * 0.6
            let bh = CGFloat(b.h) * s * 0.6
            let wall = groundColor.shade(b.shade).lit(0.08)
            let lit = Color(red: 1, green: 0.85, blue: 0.4).opacity(0.7)
            if i % 3 == 0 {
                let legTop = base.y - bh * 0.72, hutH = bh * 0.28
                var legs = Path()
                for sx in [-1.0, 1.0] as [CGFloat] {
                    legs.move(to: CGPoint(x: base.x + sx * bw * 0.34, y: base.y)); legs.addLine(to: CGPoint(x: base.x + sx * bw * 0.24, y: legTop))
                }
                legs.move(to: CGPoint(x: base.x - bw * 0.32, y: base.y)); legs.addLine(to: CGPoint(x: base.x + bw * 0.26, y: legTop + bh * 0.2))
                legs.move(to: CGPoint(x: base.x + bw * 0.32, y: base.y)); legs.addLine(to: CGPoint(x: base.x - bw * 0.26, y: legTop + bh * 0.2))
                ctx.stroke(legs, with: .color(wall.shade(0.2)), lineWidth: max(1.5, bw * 0.06))
                let hut = CGRect(x: base.x - bw * 0.36, y: legTop - hutH, width: bw * 0.72, height: hutH)
                ctx.fill(Path(hut), with: .color(wall))
                ctx.fill(Path(CGRect(x: hut.minX + hut.width * 0.15, y: hut.minY + hutH * 0.3, width: hut.width * 0.7, height: hutH * 0.3)),
                         with: .color(night ? lit : Color.black.opacity(0.45)))
                var roof = Path()
                roof.move(to: CGPoint(x: hut.minX - bw * 0.08, y: hut.minY)); roof.addLine(to: CGPoint(x: hut.midX, y: hut.minY - hutH * 0.5)); roof.addLine(to: CGPoint(x: hut.maxX + bw * 0.08, y: hut.minY)); roof.closeSubpath()
                ctx.fill(roof, with: .color(wall.shade(0.3)))
            } else {
                let rect = CGRect(x: base.x - bw / 2, y: base.y - bh, width: bw, height: bh)
                ctx.fill(Path(rect), with: .color(wall))
                ctx.fill(Path(CGRect(x: rect.minX - bw * 0.05, y: rect.minY - bh * 0.06, width: bw * 1.1, height: bh * 0.08)), with: .color(wall.shade(0.3)))
                ctx.fill(Path(CGRect(x: rect.midX - bw * 0.1, y: rect.maxY - bh * 0.34, width: bw * 0.2, height: bh * 0.34)), with: .color(Color.black.opacity(0.5)))
                var wy = rect.minY + bh * 0.18
                while wy < rect.maxY - bh * 0.45 {
                    for wx in [rect.minX + bw * 0.16, rect.maxX - bw * 0.34] {
                        ctx.fill(Path(CGRect(x: wx, y: wy, width: bw * 0.18, height: bh * 0.12)), with: .color(night ? lit : Color.black.opacity(0.4)))
                    }
                    wy += bh * 0.28
                }
                if i == 1 {
                    var pole = Path()
                    pole.move(to: CGPoint(x: rect.maxX - bw * 0.1, y: rect.minY)); pole.addLine(to: CGPoint(x: rect.maxX - bw * 0.1, y: rect.minY - bh * 0.7))
                    ctx.stroke(pole, with: .color(wall.shade(0.4)), lineWidth: max(1, bw * 0.04))
                    ctx.fill(Path(CGRect(x: rect.maxX - bw * 0.1, y: rect.minY - bh * 0.7, width: bw * 0.3, height: bh * 0.18)), with: .color(Color(red: 0.78, green: 0.16, blue: 0.16)))
                }
            }
        }
        // Ground (par 1) with a lit rim and grass strokes.
        let horizon = P(0, groundV, 1).y
        ctx.fill(Path(CGRect(x: 0, y: horizon, width: W, height: H - horizon)),
                 with: .linearGradient(Gradient(colors: [groundColor.lit(0.06), groundColor.shade(0.3)]), startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: H)))
        ctx.fill(Path(CGRect(x: 0, y: horizon, width: W, height: 2)), with: .color(groundColor.lit(0.25)))
        var grass = Path()
        for i in 0..<90 {
            let g = P(SNArt.hash(Double(i) * 4.1) * sceneW, groundV + 0.01 + SNArt.hash(Double(i) * 6.7) * 0.12, 1)
            let gh = CGFloat(0.008 + 0.006 * SNArt.hash(Double(i))) * s
            grass.move(to: g); grass.addLine(to: CGPoint(x: g.x - gh * 0.3, y: g.y - gh))
            grass.move(to: g); grass.addLine(to: CGPoint(x: g.x + gh * 0.3, y: g.y - gh))
        }
        ctx.stroke(grass, with: .color(groundColor.lit(0.18)), lineWidth: 1.2)
        // Cover (par 1): sandbag walls where the crates were, and grass tufts.
        let bag = Color(red: 0.72, green: 0.64, blue: 0.46).mix(with: sky.1, by: night ? 0.55 : 0.15)
        for pr in props {
            let g = P(pr.x, groundV, 1)
            if pr.kind == 0 {
                let cw = CGFloat(0.05) * s, ch = CGFloat(0.045) * s
                var bags = Path()
                for (bx, by, bwf) in [(-0.5, 0.5, 0.5), (0.0, 0.5, 0.5), (-0.28, 0.0, 0.56)] as [(CGFloat, CGFloat, CGFloat)] {
                    bags.addRoundedRect(in: CGRect(x: g.x + bx * cw, y: g.y - ch + by * ch, width: cw * bwf, height: ch * 0.5),
                                        cornerSize: CGSize(width: ch * 0.2, height: ch * 0.2))
                }
                ctx.fill(bags, with: .color(bag))
                ctx.stroke(bags, with: .color(.black.opacity(0.4)), lineWidth: 1.2)
            } else {
                let tw = CGFloat(0.02) * s
                var tuft = Path()
                for dx in [-0.35, 0.0, 0.35] as [CGFloat] {
                    tuft.move(to: CGPoint(x: g.x, y: g.y)); tuft.addLine(to: CGPoint(x: g.x + dx * tw, y: g.y - tw * (dx == 0 ? 1.1 : 0.8)))
                }
                ctx.stroke(tuft, with: .color(groundColor.lit(0.2)), style: StrokeStyle(lineWidth: max(1.5, tw * 0.18), lineCap: .round))
            }
        }
    }

    /// The red soldiers as stick figures (walking, standing, or raising a rifle with its aim beam),
    /// and the ones just shot toppling over.
    private func drawSoldiers(_ ctx: GraphicsContext, w: CGFloat, h: CGFloat, s: CGFloat, now: Date) {
        let H = CGFloat(targetH) * s
        for d in downed {
            let age = now.timeIntervalSince(d.at)
            guard age < 1.2 else { continue }
            var g = ctx
            g.opacity = age < 0.6 ? 1 : max(0, 1 - (age - 0.6) / 0.6)
            let facing: CGFloat = d.facing < 0 ? -1 : 1
            let tilt = -Double(facing) * min(1, age / 0.35) * .pi / 2
            SNArt.soldier(g, feet: worldToScreen(d.wx, d.wy, w: w, h: h, s: s), height: H, pose: SNArt.hitPose, facing: facing, aiming: false, tilt: tilt)
        }
        for t in targets {
            let feet = worldToScreen(t.x, t.y, w: w, h: h, s: s)
            let center = CGPoint(x: feet.x, y: feet.y - H / 2)
            if t.aiming {
                // Aim beam: a red line from the scope centre to the soldier, thickening as it charges.
                let prog = CGFloat(max(0, 1 - t.aimT / max(0.001, aimTime)))
                var beam = Path()
                beam.move(to: CGPoint(x: w / 2, y: h / 2)); beam.addLine(to: center)
                let red = Color(red: 1, green: 0.25, blue: 0.2)
                ctx.stroke(beam, with: .color(red.opacity(0.14 + 0.2 * Double(prog))), style: StrokeStyle(lineWidth: (1 + 3 * prog) * 4, lineCap: .round))
                ctx.stroke(beam, with: .color(red.opacity(0.35 + 0.55 * Double(prog))), style: StrokeStyle(lineWidth: 1 + 3 * prog, lineCap: .round))
            }
            let (pose, facing) = figure(t)
            SNArt.soldier(ctx, feet: feet, height: H, pose: pose, facing: facing, aiming: t.aiming)
        }
    }

    /// The pose and facing a soldier is drawn with right now — shared by the art and the shot's hit test.
    private func figure(_ t: Target) -> (pose: StickPose, facing: CGFloat) {
        let walking = t.speed > 0 && t.pause <= 0
        let f2 = Int((animT + t.x * 5) * 6) % 2 == 1
        let pose = t.aiming ? SNArt.aimPose : (walking ? (f2 ? SNArt.walkB : SNArt.walkA) : SNArt.standPose)
        // A soldier drawing on you turns his rifle toward the scope.
        let facing: CGFloat = t.aiming ? (t.x < Double(aim.x) ? 1 : -1) : (t.dir < 0 ? -1 : 1)
        return (pose, facing)
    }

    private func worldToScreen(_ wx: Double, _ wy: Double, w: CGFloat, h: CGFloat, s: CGFloat) -> CGPoint {
        CGPoint(x: w / 2 + CGFloat(wx - Double(aim.x)) * s,
                y: h / 2 + CGFloat(wy - Double(aim.y)) * s)
    }

    // MARK: - Scope overlay
    private func scopeOverlay(w: CGFloat, h: CGFloat, s: CGFloat) -> some View {
        let r = min(w, h) * 0.46
        let c = CGPoint(x: w / 2, y: h / 2)
        // Reticle sits at centre + the current sway (WYSIWYG — a shot lands exactly here).
        let sway = swayOffset()
        let rc = CGPoint(x: c.x + CGFloat(sway.x) * s, y: c.y + CGFloat(sway.y) * s)
        return ZStack {
            // Dark mask everywhere except the lens.
            Canvas { ctx, size in
                var mask = Path(CGRect(origin: .zero, size: size))
                mask.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                ctx.fill(mask, with: .color(.black.opacity(0.94)), style: FillStyle(eoFill: true))
                // Inner lens vignette.
                let vg = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                ctx.fill(vg, with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.55)]),
                                                   center: c, startRadius: r * 0.55, endRadius: r))
                // Glass glint (top-left arc sheen).
                var glint = Path()
                glint.addArc(center: c, radius: r * 0.86, startAngle: .degrees(200), endAngle: .degrees(250), clockwise: false)
                ctx.stroke(glint, with: .color(.white.opacity(0.18)), lineWidth: r * 0.06)
                // Range ticks inside the rim, and a faint coated-lens tint at the edge.
                var ticks = Path()
                for k in 0..<36 {
                    let a = Double(k) / 36 * 2 * .pi
                    let len: CGFloat = k % 3 == 0 ? r * 0.06 : r * 0.03
                    ticks.move(to: CGPoint(x: c.x + CGFloat(cos(a)) * (r - 3), y: c.y + CGFloat(sin(a)) * (r - 3)))
                    ticks.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * (r - 3 - len), y: c.y + CGFloat(sin(a)) * (r - 3 - len)))
                }
                ctx.stroke(ticks, with: .color(.white.opacity(0.3)), lineWidth: 1)
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r + 5, y: c.y - r + 5, width: r * 2 - 10, height: r * 2 - 10)),
                           with: .color(Color(red: 0.4, green: 0.8, blue: 1).opacity(0.16)), lineWidth: 3)
            }

            // Lens rim.
            Circle().stroke(Color.black, lineWidth: 6).frame(width: r * 2, height: r * 2).position(c)
            Circle().stroke(Color.white.opacity(0.22), lineWidth: 2).frame(width: r * 2, height: r * 2).position(c)
            // Danger ring when someone's drawing on you.
            if danger {
                Circle().stroke(Color(red: 1, green: 0.25, blue: 0.2).opacity(0.5 + 0.3 * sin(animT * 10)),
                                lineWidth: 4)
                    .frame(width: r * 2 - 8, height: r * 2 - 8).position(c)
            }

            // Mil-dot crosshair.
            Canvas { ctx, size in
                let col = Color.black.opacity(0.85)
                let gap = r * 0.09
                // Horizontal + vertical hairs with a centre gap.
                var hair = Path()
                hair.move(to: CGPoint(x: rc.x - r, y: rc.y)); hair.addLine(to: CGPoint(x: rc.x - gap, y: rc.y))
                hair.move(to: CGPoint(x: rc.x + gap, y: rc.y)); hair.addLine(to: CGPoint(x: rc.x + r, y: rc.y))
                hair.move(to: CGPoint(x: rc.x, y: rc.y - r)); hair.addLine(to: CGPoint(x: rc.x, y: rc.y - gap))
                hair.move(to: CGPoint(x: rc.x, y: rc.y + gap)); hair.addLine(to: CGPoint(x: rc.x, y: rc.y + r))
                ctx.stroke(hair, with: .color(col), lineWidth: 1.4)
                // Mil dots.
                for i in 1...4 {
                    let d = gap + CGFloat(i) * r * 0.18
                    for pt in [CGPoint(x: rc.x - d, y: rc.y), CGPoint(x: rc.x + d, y: rc.y),
                               CGPoint(x: rc.x, y: rc.y - d), CGPoint(x: rc.x, y: rc.y + d)] {
                        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 1.6, y: pt.y - 1.6, width: 3.2, height: 3.2)),
                                 with: .color(col))
                    }
                }
                // Centre dot (red).
                ctx.fill(Path(ellipseIn: CGRect(x: rc.x - 2, y: rc.y - 2, width: 4, height: 4)),
                         with: .color(Color(red: 1, green: 0.3, blue: 0.25)))
            }
        }
    }

    private func swayOffset() -> CGPoint {
        CGPoint(x: cos(animT * 1.3) * swayAmp + sin(animT * 2.3) * swayAmp * 0.5,
                y: sin(animT * 1.7) * swayAmp)
    }

    private func muzzleBloom(w: CGFloat, h: CGFloat) -> some View {
        Group {
            if muzzle > 0 {
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 1, green: 0.9, blue: 0.5).opacity(0.9), .clear],
                                         center: .center, startRadius: 0, endRadius: min(w, h) * 0.5))
                    .frame(width: min(w, h), height: min(w, h))
                    .position(x: w / 2, y: h / 2)
                    .opacity(muzzle / 0.09)
            }
        }
    }

    // MARK: - HUD
    private func hud(w: CGFloat, h: CGFloat) -> some View {
        VStack {
            HStack(alignment: .center) {
                // Rounds left in the magazine.
                SNAmmo(total: max(1, ammo0), loaded: ammo)
                    .frame(width: CGFloat(max(1, ammo0)) * 7, height: 18)
                Spacer()
                // Blood / health.
                HStack(spacing: 3) {
                    ForEach(0..<max(1, maxHP), id: \.self) { i in
                        Image(systemName: i < hp ? "drop.fill" : "drop")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(i < hp ? Color(red: 0.92, green: 0.16, blue: 0.16) : .white.opacity(0.25))
                    }
                }
                Spacer()
                // Soldiers left: a helmeted head and the count.
                HStack(spacing: 5) {
                    SNHeadIcon().frame(width: 16, height: 16)
                    Text("\(targets.count)")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 18).padding(.top, 4)

            GeometryReader { g in
                let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule().fill(frac < 0.25 ? Color(red: 1, green: 0.3, blue: 0.25) : Color(white: 0.85))
                        .frame(width: g.size.width * max(0, frac))
                }
            }
            .frame(height: 4).padding(.horizontal, 50).padding(.top, 2)
            Spacer()
        }
    }

    // MARK: - Controls
    private var controls: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                // Bottom-RIGHT so it clears the page's bottom-centre skip chevron (locksFeed).
                SNFireKey(lit: demoFire)
                    .frame(width: 96, height: 56)
                    .scaleEffect(demoFire ? 0.9 : 1)
                    .animation(.easeOut(duration: 0.1), value: demoFire)
                    .contentShape(Rectangle())
                    .onTapGesture { fire() }
            }
            .padding(.trailing, 20)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Flow
    private func run() async {
        if !built { setup(); built = true }
        var last = Date()
        while !Task.isCancelled && phase == .play {
            try? await Task.sleep(for: .seconds(0.016))
            let now = Date()
            let dt = min(0.05, now.timeIntervalSince(last)); last = now
            step(dt: dt)
        }
    }

    private func setup() {
        phase = .play
        ammo = ammo0
        hp = maxHP
        hasFired = false; armDelay = 0; hurt = 0
        timeLeft = timeLimit
        recoil = 0; muzzle = 0; animT = 0
        aim = CGPoint(x: 0.4, y: 0.52)
        bursts = []

        // Scenery.
        ridges = stride(from: -0.3, through: sceneW + 0.3, by: 0.12).map {
            Ridge(x: $0, top: groundV - Double.random(in: 0.10...0.20))
        }
        midline = stride(from: -0.3, through: sceneW + 0.3, by: 0.08).map {
            Ridge(x: $0, top: groundV - Double.random(in: 0.03...0.10))
        }
        buildings = (0..<7).map { _ in
            Building(x: Double.random(in: 0.1...(sceneW - 0.1)), w: Double.random(in: 0.08...0.16),
                     h: Double.random(in: 0.10...0.22), shade: Double.random(in: 0.1...0.35))
        }
        props = (0..<26).map { _ in
            Prop(x: Double.random(in: 0.05...(sceneW - 0.05)), kind: Int.random(in: 0...2) == 0 ? 0 : 1)
        }

        // Targets, spread across the scene with per-target patrol lanes.
        var built: [Target] = []
        let slot = (sceneW - 0.4) / Double(targetCount)
        for i in 0..<targetCount {
            let base = 0.2 + slot * (Double(i) + 0.5)
            let span = min(slot * 0.4, 0.22)
            built.append(Target(x: base, y: groundV + Double.random(in: -0.005...0.005),
                                dir: Bool.random() ? 1 : -1,
                                minX: base - span, maxX: base + span,
                                speed: walkSpeed * Double.random(in: 0.85...1.15),
                                aimCD: Double.random(in: aimEvery * 0.4...aimEvery)))
        }
        targets = built
    }

    private func pan(dx: CGFloat, dy: CGFloat, s: CGFloat) {
        // Grab-the-world: drag moves the vista under a fixed reticle.
        let viewWx = viewH * Double(area.width / max(1, area.height))
        let minX = viewWx / 2 + 0.02, maxX = sceneW - viewWx / 2 - 0.02
        aim.x = CGFloat(min(max(minX, Double(aim.x) - Double(dx) / Double(s)), maxX))
        aim.y = CGFloat(min(max(0.45, Double(aim.y) - Double(dy) / Double(s)), 0.62))
    }

    private func step(dt: Double) {
        guard phase == .play else { return }
        animT += dt
        if recoil > 0 { recoil = max(0, recoil - dt * 6) }
        if muzzle > 0 { muzzle = max(0, muzzle - dt) }
        if hurt > 0 { hurt = max(0, hurt - dt * 2.2) }
        if hasFired && armDelay > 0 { armDelay = max(0, armDelay - dt) }

        for i in targets.indices {
            if targets[i].aiming {
                targets[i].aimT -= dt
                if targets[i].aimT <= 0 {           // the shot connects — you take a hit
                    targets[i].aiming = false
                    targets[i].aimCD = Double.random(in: aimEvery * 0.6...aimEvery)
                    takeHit()
                    if phase == .done { return }
                    continue
                }
                continue
            }
            // Patrol.
            if targets[i].pause > 0 {
                targets[i].pause -= dt
            } else {
                targets[i].x += targets[i].dir * targets[i].speed * dt
                if targets[i].x <= targets[i].minX { targets[i].x = targets[i].minX; targets[i].dir = 1 }
                if targets[i].x >= targets[i].maxX { targets[i].x = targets[i].maxX; targets[i].dir = -1 }
                if Double.random(in: 0...1) < dt * 0.4 { targets[i].pause = Double.random(in: 0.3...1.0) }
            }
            // Enemies only draw on you once armed (a beat after your first shot).
            if armed {
                targets[i].aimCD -= dt
                if targets[i].aimCD <= 0 { raiseWeapon(&targets[i]) }
            }
        }

        timeLeft -= dt
        if timeLeft <= 0 { timeLeft = 0; fail() }
    }

    private func takeHit() {
        hp -= 1
        hurt = 1
        shakeTick += 1
        Haptics.warning(); SoundManager.shared.error()
        if hp <= 0 { fail() }
    }

    private func raiseWeapon(_ t: inout Target) {
        t.aiming = true
        t.aimT = aimTime
        t.dir = -1   // turn to face the scope
        SoundManager.shared.error()
        Haptics.warning()
    }

    private func fire() {
        guard phase == .play, ammo > 0 else { return }
        ammo -= 1
        if !hasFired { hasFired = true; armDelay = armDelay0 }   // start the calm-then-armed clock
        recoil = 1; muzzle = 0.09; shakeTick += 1
        SoundManager.shared.tap(); Haptics.tap()

        // The world point under the reticle's red dot, as drawn: the sway moves the reticle, and a
        // follow-up shot during the kick sees the scene still lifted by the recoil.
        let sway = swayOffset()
        let sx = Double(aim.x) + Double(sway.x)
        let sy = Double(aim.y) + Double(sway.y) + recoil * 0.02 * viewH
        // It's a hit only if that dot touches the soldier's drawn body (limbs, vest, helmeted head).
        let dot = 2.0 / (Double(max(1, area.height)) / viewH)      // the dot's 2 pt radius, in world units

        if let idx = targets.firstIndex(where: { t in
            let (pose, facing) = figure(t)
            let local = CGPoint(x: 0.5 + CGFloat((sx - t.x) / targetH) * facing, y: 0.97 + CGFloat((sy - t.y) / targetH))
            return SNArt.touches(local, pose: pose, slack: CGFloat(dot / targetH))
        }) {
            let t = targets[idx]
            bursts.append(Burst(wx: t.x, wy: t.y - targetH / 2, color: Color(red: 0.95, green: 0.3, blue: 0.25), big: true))
            bursts.append(Burst(wx: t.x, wy: t.y - targetH / 2, color: BananaTheme.banana, big: false))
            targets.remove(at: idx)
            if targets.isEmpty { win(); return }
        } else {
            // Miss: puff of dust; once armed, the nearest target is startled into aiming.
            bursts.append(Burst(wx: sx, wy: sy, color: Color(white: 0.85), big: false))
            if armed, let ni = nearestTarget(to: sx, sy: sy), !targets[ni].aiming,
               abs(sx - targets[ni].x) < 0.22 {
                raiseWeapon(&targets[ni])
            }
        }

        if ammo <= 0 && !targets.isEmpty { fail() }   // out of ammo with work left → over
    }

    private func nearestTarget(to sx: Double, sy: Double) -> Int? {
        var best: Int?; var bestD = Double.greatestFiniteMagnitude
        for (i, t) in targets.enumerated() {
            let d = abs(sx - t.x)
            if d < bestD { bestD = d; best = i }
        }
        return best
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

}

// MARK: - Sniper art

/// A soldier just shot: where it stood, which way it faced, and when (it topples, then fades).
private struct SNDown {
    let id: UUID
    let wx: Double
    let wy: Double
    let facing: Double
    let at: Date
}

/// What the view tracks of each soldier, to notice the one that was just shot.
private struct SNSeen: Equatable {
    let id: UUID
    let x: Double
    let y: Double
    let dir: Double
}

private enum SNArt {
    static func hash(_ n: Double) -> Double {
        let x = sin(n) * 43758.5453
        return x - floor(x)
    }

    private static func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    // Poses in StickFigure's unit box (facing right, feet at y ≈ 0.97).
    static let standPose = StickPose(
        head: pt(0.5, 0.15), headR: 0.1, neck: pt(0.5, 0.27), hip: pt(0.5, 0.6),
        lElbow: pt(0.43, 0.41), lHand: pt(0.44, 0.53), rElbow: pt(0.58, 0.4), rHand: pt(0.6, 0.5),
        lKnee: pt(0.46, 0.78), lFoot: pt(0.44, 0.97), rKnee: pt(0.55, 0.78), rFoot: pt(0.57, 0.97))
    static let walkA = StickPose(
        head: pt(0.52, 0.15), headR: 0.1, neck: pt(0.51, 0.27), hip: pt(0.49, 0.6),
        lElbow: pt(0.57, 0.41), lHand: pt(0.62, 0.5), rElbow: pt(0.44, 0.41), rHand: pt(0.4, 0.5),
        lKnee: pt(0.56, 0.78), lFoot: pt(0.62, 0.97), rKnee: pt(0.45, 0.79), rFoot: pt(0.38, 0.96))
    static let walkB = StickPose(
        head: pt(0.52, 0.15), headR: 0.1, neck: pt(0.51, 0.27), hip: pt(0.49, 0.6),
        lElbow: pt(0.44, 0.41), lHand: pt(0.4, 0.5), rElbow: pt(0.57, 0.41), rHand: pt(0.62, 0.5),
        lKnee: pt(0.45, 0.79), lFoot: pt(0.38, 0.96), rKnee: pt(0.56, 0.78), rFoot: pt(0.62, 0.97))
    /// Rifle up at the shoulder, feet braced.
    static let aimPose = StickPose(
        head: pt(0.5, 0.15), headR: 0.1, neck: pt(0.5, 0.27), hip: pt(0.49, 0.6),
        lElbow: pt(0.6, 0.36), lHand: pt(0.72, 0.31), rElbow: pt(0.56, 0.37), rHand: pt(0.62, 0.3),
        lKnee: pt(0.43, 0.78), lFoot: pt(0.37, 0.97), rKnee: pt(0.57, 0.78), rFoot: pt(0.63, 0.97))
    /// Thrown back by the shot.
    static let hitPose = StickPose(
        head: pt(0.46, 0.15), headR: 0.1, neck: pt(0.47, 0.27), hip: pt(0.5, 0.6),
        lElbow: pt(0.38, 0.2), lHand: pt(0.32, 0.1), rElbow: pt(0.58, 0.2), rHand: pt(0.64, 0.1),
        lKnee: pt(0.45, 0.78), lFoot: pt(0.42, 0.97), rKnee: pt(0.57, 0.77), rFoot: pt(0.62, 0.95))

    // Stroke widths as fractions of the soldier's height, shared by the art and the hit test.
    static let limbW: CGFloat = 0.085
    static let outlineW: CGFloat = 0.04
    static let brimW: CGFloat = 0.03

    /// Does a point in the figure's unit box (facing right, feet at y ≈ 0.97) touch the soldier as
    /// `soldier` draws him — outlined limbs, vest, head and helmet — give or take `slack`? The rifle
    /// doesn't count.
    static func touches(_ p: CGPoint, pose: StickPose, slack: CGFloat) -> Bool {
        func near(_ a: CGPoint, _ b: CGPoint, _ r: CGFloat) -> Bool {
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            let t = len2 > 0 ? max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2)) : 0
            return hypot(p.x - (a.x + dx * t), p.y - (a.y + dy * t)) <= r + slack
        }
        let bones = [(pose.neck, pose.hip), (pose.neck, pose.lElbow), (pose.lElbow, pose.lHand),
                     (pose.neck, pose.rElbow), (pose.rElbow, pose.rHand), (pose.hip, pose.lKnee),
                     (pose.lKnee, pose.lFoot), (pose.hip, pose.rKnee), (pose.rKnee, pose.rFoot)]
        if bones.contains(where: { near($0.0, $0.1, (limbW + outlineW) / 2) }) { return true }
        if near(pt(pose.neck.x, pose.neck.y + 0.05), pt(pose.hip.x, pose.hip.y - 0.07), limbW * 2.1 / 2) { return true }
        let h = pose.head, hr = pose.headR
        if near(h, h, hr + outlineW / 2) { return true }             // the outlined head covers the helmet dome
        return near(pt(h.x - hr * 1.1, h.y + hr * 0.1), pt(h.x + hr * 1.45, h.y + hr * 0.1), brimW / 2)
    }

    /// A red soldier as a vector stick figure: red limbs over a dark contour, a darker vest, a dark
    /// helmet, and a rifle — carried across the chest, or shouldered (with a laser glint) when aiming.
    static func soldier(_ ctx: GraphicsContext, feet: CGPoint, height H: CGFloat, pose: StickPose, facing: CGFloat, aiming: Bool, tilt: Double = 0) {
        var g = ctx
        g.translateBy(x: feet.x, y: feet.y)
        if tilt != 0 { g.rotate(by: .radians(tilt)) }
        func m(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - 0.5) * H * facing, y: (p.y - 0.97) * H) }
        let red = aiming ? Color(red: 0.98, green: 0.34, blue: 0.24) : Color(red: 0.84, green: 0.2, blue: 0.2)
        let outline = Color(red: 0.08, green: 0.04, blue: 0.05)
        let lw = H * limbW
        var limbs = Path()
        limbs.move(to: m(pose.neck)); limbs.addLine(to: m(pose.hip))
        func chain(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) {
            limbs.move(to: m(a)); limbs.addLine(to: m(b)); limbs.addLine(to: m(c))
        }
        chain(pose.neck, pose.lElbow, pose.lHand)
        chain(pose.neck, pose.rElbow, pose.rHand)
        chain(pose.hip, pose.lKnee, pose.lFoot)
        chain(pose.hip, pose.rKnee, pose.rFoot)
        var rifle = Path()
        var muzzle = CGPoint.zero
        if aiming {
            rifle.move(to: m(pt(0.4, 0.31))); rifle.addLine(to: m(pt(0.95, 0.27)))
            muzzle = m(pt(0.95, 0.27))
        } else {
            rifle.move(to: m(pt(0.34, 0.54))); rifle.addLine(to: m(pt(0.68, 0.27)))
        }
        let head = m(pose.head), hr = pose.headR * H
        let ol = H * outlineW
        g.stroke(limbs, with: .color(outline), style: StrokeStyle(lineWidth: lw + ol, lineCap: .round, lineJoin: .round))
        g.stroke(rifle, with: .color(outline), style: StrokeStyle(lineWidth: lw * 0.75 + ol, lineCap: .round))
        g.fill(Path(ellipseIn: CGRect(x: head.x - hr - ol / 2, y: head.y - hr - ol / 2, width: hr * 2 + ol, height: hr * 2 + ol)), with: .color(outline))
        g.stroke(limbs, with: .color(red), style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
        var vest = Path()
        vest.move(to: m(pt(pose.neck.x, pose.neck.y + 0.05))); vest.addLine(to: m(pt(pose.hip.x, pose.hip.y - 0.07)))
        g.stroke(vest, with: .color(red.mix(with: .black, by: 0.32)), style: StrokeStyle(lineWidth: lw * 2.1, lineCap: .round))
        g.fill(Path(ellipseIn: CGRect(x: head.x - hr, y: head.y - hr, width: hr * 2, height: hr * 2)), with: .color(red))
        var helmet = Path()
        helmet.addArc(center: CGPoint(x: head.x, y: head.y + hr * 0.1), radius: hr * 1.12, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        helmet.closeSubpath()
        g.fill(helmet, with: .color(Color(red: 0.26, green: 0.09, blue: 0.1)))
        var brim = Path()
        brim.move(to: CGPoint(x: head.x - hr * 1.1 * facing, y: head.y + hr * 0.1)); brim.addLine(to: CGPoint(x: head.x + hr * 1.45 * facing, y: head.y + hr * 0.1))
        g.stroke(brim, with: .color(Color(red: 0.26, green: 0.09, blue: 0.1)), style: StrokeStyle(lineWidth: max(1, H * brimW), lineCap: .round))
        g.stroke(rifle, with: .color(Color(white: 0.14)), style: StrokeStyle(lineWidth: lw * 0.75, lineCap: .round))
        if aiming {
            g.fill(Path(ellipseIn: CGRect(x: muzzle.x - H * 0.07, y: muzzle.y - H * 0.07, width: H * 0.14, height: H * 0.14)),
                   with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.3, blue: 0.2).opacity(0.9), Color(red: 1, green: 0.3, blue: 0.2).opacity(0)]),
                                         center: muzzle, startRadius: 0, endRadius: H * 0.07))
            g.fill(Path(ellipseIn: CGRect(x: muzzle.x - H * 0.018, y: muzzle.y - H * 0.018, width: H * 0.036, height: H * 0.036)), with: .color(.white))
        }
    }
}

/// Rounds left as brass cartridges; spent ones are dark sockets.
private struct SNAmmo: View {
    let total: Int
    let loaded: Int

    var body: some View {
        Canvas { ctx, size in
            let n = max(1, total)
            let slot = size.width / CGFloat(n)
            let w = min(slot * 0.62, size.height * 0.3)
            for i in 0..<n {
                let x = slot * (CGFloat(i) + 0.5)
                let body = CGRect(x: x - w / 2, y: size.height * 0.36, width: w, height: size.height * 0.62)
                var tip = Path()
                tip.move(to: CGPoint(x: x - w / 2, y: size.height * 0.38))
                tip.addQuadCurve(to: CGPoint(x: x + w / 2, y: size.height * 0.38), control: CGPoint(x: x, y: -size.height * 0.1))
                tip.closeSubpath()
                if i < loaded {
                    ctx.fill(tip, with: .color(Color(red: 0.74, green: 0.44, blue: 0.24)))
                    ctx.fill(Path(roundedRect: body, cornerRadius: w * 0.2),
                             with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.88, blue: 0.5), Color(red: 0.8, green: 0.6, blue: 0.2)]),
                                                   startPoint: CGPoint(x: body.minX, y: 0), endPoint: CGPoint(x: body.maxX, y: 0)))
                } else {
                    var all = Path(roundedRect: body, cornerRadius: w * 0.2)
                    all.addPath(tip)
                    ctx.stroke(all, with: .color(.white.opacity(0.25)), lineWidth: 1)
                }
            }
        }
    }
}

/// The counter's soldier: a red head under a dark helmet.
private struct SNHeadIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) * 0.36
            let c = CGPoint(x: size.width / 2, y: size.height * 0.56)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(Color(red: 0.9, green: 0.24, blue: 0.22)))
            var helmet = Path()
            helmet.addArc(center: CGPoint(x: c.x, y: c.y + r * 0.1), radius: r * 1.15, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            helmet.closeSubpath()
            ctx.fill(helmet, with: .color(Color(red: 0.3, green: 0.1, blue: 0.1)))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(.black.opacity(0.6)), lineWidth: 1)
        }
    }
}

/// FIRE: a red trigger key with a crosshair.
private struct SNFireKey: View {
    let lit: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: lit ? [Color(red: 1, green: 0.52, blue: 0.46), Color(red: 0.86, green: 0.22, blue: 0.2)]
                                                 : [Color(red: 0.95, green: 0.3, blue: 0.28), Color(red: 0.66, green: 0.12, blue: 0.12)],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(lit ? 0.95 : 0.5), lineWidth: lit ? 3 : 2)
            Image(systemName: "scope")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(.white)
        }
    }
}
