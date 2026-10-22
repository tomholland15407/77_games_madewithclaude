//
//  DigDugGame.swift
//  A Banana Game
//
//  Reflex — dig, pump, and drop rocks. Tunnel through the strata with the d-pad (moving into
//  dirt carves it). Tap PUMP to fire a harpoon down a clear tunnel; keep pumping a monster
//  before it deflates and it bursts. Dig out the dirt UNDER a boulder and it drops — crushing
//  any monster (or you!) beneath it. Grey bedrock blocks can't be dug through. Clear every
//  monster to win; get caught or crushed, or let the clock run out, and you fall back to level
//  1. 7 levels: more monsters, faster and ghostier hunters, more rocks and bedrock, and a
//  tighter clock. Strata cool with depth.
//
//  Drawn as Namco's 1982 Dig Dug: a blue sky strip with one flower per level on the surface, four
//  stippled dirt layers (a new set of earths each level), round black tunnels, orange boulders that
//  rock while they teeter, grey faceted bedrock, the red goggled Pooka (the phaser, with a steady
//  halo so it's never lost in the dirt) and the green Fygar, a banana digger in Dig Dug's white
//  helmet, and the pump's hose with its harpoon tip. The ground is an Equatable view redrawn only
//  when a cell is dug; everything that moves is one Canvas.
//

import SwiftUI

enum DigDugGame {
    static let definition = GameDefinition(
        id: "dig-dug",
        title: "Tunnel Pump",
        emoji: "🍌",
        genre: .reflex,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Move with the d-pad to carve tunnels through the dirt.",
                "Tap PUMP to harpoon a monster down a clear tunnel and inflate it — keep pumping until it bursts.",
                "Dig out the dirt under a boulder to drop it and crush monsters beneath; grey bedrock can't be dug.",
                "Clear every monster before the clock runs out; caught, crushed, or timed out sends you to level 1.",
            ],
            bulletsVI: [
                "Di chuyển bằng d-pad để đào đường hầm xuyên qua đất.",
                "Chạm BƠM để phóng lao vào quái trong đường hầm thông và bơm phồng nó — bơm liên tục đến khi nó nổ.",
                "Đào đất dưới một tảng đá để thả nó đè quái bên dưới; đá xám không đào được.",
                "Dọn hết quái trước khi hết giờ; bị bắt, bị đè, hoặc hết giờ sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(DigDugView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct DigDugView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void
    @Environment(\.isDemo) private var isDemo

    private let cols = 9
    private let rowsN = 13

    private var enemyN: Int         { [2, 2, 3, 3, 4, 4, 5][min(level, 7) - 1] }
    private var enemyStep: Double   { [0.62, 0.56, 0.50, 0.44, 0.39, 0.34, 0.30][min(level, 7) - 1] }
    // The red monster's signature is ghosting THROUGH the dirt toward the player, so it should do
    // it often — this is the per-move chance it starts a dirt shortcut when it's in a tunnel (once
    // inside dirt it always keeps phasing). Kept high so the ability reads clearly every level.
    private var ghostChance: Double { [0.40, 0.50, 0.60, 0.68, 0.76, 0.84, 0.92][min(level, 7) - 1] }
    private var pumps: Int          { level >= 5 ? 4 : 3 }
    private var rockN: Int          { [1, 2, 2, 3, 3, 4, 4][min(level, 7) - 1] }
    private var bedrockN: Int       { [0, 1, 2, 2, 3, 3, 4][min(level, 7) - 1] }
    private var timeLimit: Double   { [46, 46, 44, 42, 40, 38, 36][min(level, 7) - 1] }
    // How long a freshly-unsupported rock teeters before it drops — your window to bolt out.
    private var wobbleTime: Double  { max(0.30, 0.70 - Double(level) * 0.05) }

    private struct P: Hashable { let r: Int; let c: Int }
    private struct Enemy: Identifiable { let id = UUID(); var cell: P; var inflate: Double; var deflateDelay: Double; var kind: Int }
    private struct Burst: Identifiable { let id = UUID(); let cell: P; let color: Color }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var dug: Set<P> = []
    @State private var rocks: Set<P> = []
    @State private var rockWobble: [P: Double] = [:]   // unsupported rocks teetering before they drop
    @State private var rockFalling: Set<P> = []        // rocks past the wobble, now dropping
    @State private var bedrock: Set<P> = []
    @State private var player = P(r: 1, c: 4)
    @State private var facing = P(r: 0, c: 1)
    @State private var enemies: [Enemy] = []
    @State private var bursts: [Burst] = []
    @State private var moveDir: P? = nil
    @State private var harpoon: (from: P, dir: P, len: Int)? = nil
    @State private var harpoonTimer = 0.0
    @State private var moveAcc = 0.0
    @State private var enemyAcc = 0.0
    @State private var rockAcc = 0.0
    @State private var timeLeft = 0.0
    @State private var started = false
    @State private var shakeTick = 0
    @State private var loopTask: Task<Void, Never>?
    @State private var demoPump = 0                    // demo: frames left on the PUMP press flash
    @State private var enemyLeft: [UUID: Bool] = [:]   // presentation: which way each monster last stepped

    private func isOpen(_ p: P) -> Bool { dug.contains(p) && !rocks.contains(p) && !bedrock.contains(p) }
    private func isDirt(_ p: P) -> Bool { !dug.contains(p) && !rocks.contains(p) && !bedrock.contains(p) }

    var body: some View {
        ZStack {
            VStack(spacing: isDemo ? 4 : 6) {
                // Monsters left: a Pooka and its count.
                HStack(spacing: 7) {
                    DDPookaIcon().frame(width: isDemo ? 17 : 22, height: isDemo ? 17 : 22)
                    Text("\(enemies.count)")
                        .font(.system(size: isDemo ? 15 : 20, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                .padding(.top, isDemo ? 6 : 0)
                if !isDemo { timeBar.frame(height: 5).padding(.horizontal, 60) }

                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height
                    let cell = min(w / CGFloat(cols), h / CGFloat(rowsN))
                    let ox = (w - cell * CGFloat(cols)) / 2
                    let oy = (h - cell * CGFloat(rowsN)) / 2
                    let cx: (Int) -> CGFloat = { c in ox + (CGFloat(c) + 0.5) * cell }
                    let cy: (Int) -> CGFloat = { r in oy + (CGFloat(r) + 0.5) * cell }

                    ZStack {
                        Color.black
                        // Sky, strata, tunnels and bedrock: redrawn only when a cell is dug.
                        DDGround(size: geo.size, rows: rowsN, cols: cols, dug: Set(dug.map { $0.r * cols + $0.c }),
                                 bedrock: Set(bedrock.map { $0.r * cols + $0.c }), level: level)
                            .equatable()
                        // Boulders, the pump's hose, the monsters and the digger: one Canvas.
                        Canvas { ctx, _ in drawActors(ctx, cell: cell, ox: ox, oy: oy) }

                        ForEach(bursts) { b in
                            ParticleBurstView(color: b.color, count: 12, spread: 44) {
                                bursts.removeAll { $0.id == b.id }
                            }
                            .position(x: cx(b.cell.c), y: cy(b.cell.r))
                        }
                    }
                    .frame(width: w, height: h)
                    .clipped()
                    .screenShake(shakeTick, amount: 4)
                }

                controls
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(white: 0.03))
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
        // Each monster faces the way it last stepped.
        .onChange(of: enemies.map { DDStep(id: $0.id, c: $0.cell.c) }) { old, new in
            for n in new {
                if let o = old.first(where: { $0.id == n.id }), o.c != n.c { enemyLeft[n.id] = n.c < o.c }
            }
        }
    }

    private func drawActors(_ ctx: GraphicsContext, cell: CGFloat, ox: CGFloat, oy: CGFloat) {
        let ctr = { (p: P) in CGPoint(x: ox + (CGFloat(p.c) + 0.5) * cell, y: oy + (CGFloat(p.r) + 0.5) * cell) }
        for rk in rocks {
            // Same teeter as before: a fast rock back and forth while it's unsupported.
            let tilt: Double = rockWobble[rk].map { sin($0 * 42) * 8 } ?? 0
            DDArt.rock(ctx, at: ctr(rk), size: cell * 0.94, tiltDeg: tilt, seed: rk.r * 9 + rk.c)
        }
        if let hp = harpoon {
            let tip = P(r: hp.from.r + hp.dir.r * hp.len, c: hp.from.c + hp.dir.c * hp.len)
            DDArt.harpoon(ctx, from: ctr(hp.from), to: ctr(tip), cell: cell)
        }
        for e in enemies {
            let size = cell * (0.86 + CGFloat(e.inflate) * 0.18)
            let left = enemyLeft[e.id] ?? (e.cell.c > player.c)
            let puff = min(1, e.inflate / Double(max(1, pumps)))
            if e.kind == 0 {
                DDArt.pooka(ctx, at: ctr(e.cell), size: size, puff: puff, left: left)
            } else {
                DDArt.fygar(ctx, at: ctr(e.cell), size: size, puff: puff, left: left)
            }
        }
        DDArt.digger(ctx, at: ctr(player), size: cell * 0.9, dr: facing.r, dc: facing.c)
    }

    private var controls: some View {
        HStack(spacing: 18) {
            VStack(spacing: isDemo ? 4 : 6) {
                dirBtn("chevron.up", P(r: -1, c: 0))
                HStack(spacing: isDemo ? 4 : 6) {
                    dirBtn("chevron.left", P(r: 0, c: -1))
                    dirBtn("chevron.down", P(r: 1, c: 0))
                    dirBtn("chevron.right", P(r: 0, c: 1))
                }
            }
            Button { fire() } label: {
                DDPumpIcon()
                    .frame(width: isDemo ? 30 : 36, height: isDemo ? 30 : 36)
                    .frame(width: isDemo ? 66 : 76, height: isDemo ? 42 : 54)
                    .background(DDKey(pump: true, lit: demoPump > 0))
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                    .scaleEffect(demoPump > 0 ? 0.9 : 1)
            }
            .buttonStyle(DDPressStyle())
        }
        .padding(.bottom, isDemo ? 6 : 8)
    }

    private func dirBtn(_ icon: String, _ d: P) -> some View {
        // In the demo the held arrow lights up (the script drives moveDir directly).
        let lit = isDemo && moveDir == d
        return Image(systemName: icon)
            .font(.system(size: isDemo ? 17 : 20, weight: .heavy)).foregroundStyle(lit ? Color(red: 0.2, green: 0.08, blue: 0.02) : .white)
            .frame(width: isDemo ? 46 : 56, height: isDemo ? 32 : 46)
            .background(DDKey(pump: false, lit: lit))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(lit ? 0.9 : 1)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if phase == .play && started { moveDir = d; facing = d } }
                .onEnded { _ in if moveDir == d { moveDir = nil } })
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(frac < 0.3 ? Color(red: 1, green: 0.3, blue: 0.25) : Color(red: 1, green: 0.74, blue: 0.24))
                    .frame(width: geo.size.width * frac)
            }
        }
    }

    // MARK: Input
    private func fire() {
        guard phase == .play, started else { return }
        let range = 3
        var len = 0
        var hitIndex: Int? = nil
        var pierced = false                            // the pump can punch through ONE thin dirt wall
        for step in 1...range {
            let cell = P(r: player.r + facing.r * step, c: player.c + facing.c * step)
            if !inBounds(cell) { break }
            if rocks.contains(cell) || bedrock.contains(cell) { break }   // solid — always stops the harpoon
            if isDirt(cell) {
                if pierced { break }                   // a second wall of dirt is too thick to pump through
                pierced = true
                len = step
                continue                               // pass through this thin wall into the next tunnel
            }
            len = step                                 // an open tunnel cell
            if let idx = enemies.firstIndex(where: { $0.cell == cell }) { hitIndex = idx; break }
        }
        harpoon = (player, facing, max(1, len)); harpoonTimer = 0.16
        SoundManager.shared.tap(); Haptics.tap()
        if let idx = hitIndex {
            enemies[idx].inflate = min(Double(pumps), enemies[idx].inflate + 1)
            enemies[idx].deflateDelay = 0.9
            if enemies[idx].inflate >= Double(pumps) { popEnemy(idx) }
        }
    }

    private func popEnemy(_ idx: Int) {
        bursts.append(Burst(cell: enemies[idx].cell, color: monsterColor(enemies[idx].kind)))
        enemies.remove(at: idx)
        shakeTick += 1
        if enemies.isEmpty { win() }
    }

    // MARK: - Flow
    private func run() async {
        setup()
        begin()
    }

    private func begin() {
        guard !started else { return }
        started = true
        var last = Date(); let start = Date()
        loopTask = Task {
            while !Task.isCancelled && phase == .play {
                try? await Task.sleep(for: .seconds(0.033))
                let now = Date()
                let dt = min(0.08, now.timeIntervalSince(last)); last = now
                timeLeft = max(0, timeLimit - now.timeIntervalSince(start))
                if timeLeft <= 0 { fail(); break }
                tick(dt: dt)
            }
        }
    }

    private func setup() {
        var d: Set<P> = []
        for c in 0..<cols { d.insert(P(r: 0, c: c)); d.insert(P(r: 1, c: c)) }
        for r in 0..<6 { d.insert(P(r: r, c: 4)) }
        player = P(r: 1, c: 4); facing = P(r: 0, c: 1)
        var used: Set<P> = Array(d).reduce(into: Set<P>()) { $0.insert($1) }
        used.insert(player)

        // Bedrock (indestructible) in the lower dirt.
        var bed: Set<P> = []
        var tries = 0
        while bed.count < bedrockN && tries < 80 {
            tries += 1
            let cell = P(r: Int.random(in: 4..<rowsN), c: Int.random(in: 0..<cols))
            if used.contains(cell) { continue }
            bed.insert(cell); used.insert(cell)
        }
        // Rocks — sit in dirt with dirt below them so they start supported.
        var rk: Set<P> = []
        tries = 0
        while rk.count < rockN && tries < 120 {
            tries += 1
            // Keep boulders in the upper-middle strata so there's real room to fall and
            // crush something below — spawning them near the floor made them pointless.
            let cell = P(r: Int.random(in: 3..<8), c: Int.random(in: 0..<cols))
            let below = P(r: cell.r + 1, c: cell.c)
            if used.contains(cell) || used.contains(below) || d.contains(below) { continue }
            rk.insert(cell); used.insert(cell)
        }
        // Monsters each get their own carved-out ROOM — GUARANTEED at least 3 open cells
        // (its own cell plus ≥2 carved neighbours) so every monster always has room to run.
        let adjDirs = [P(r:-1,c:0), P(r:1,c:0), P(r:0,c:-1), P(r:0,c:1)]
        func carvableNeighbours(of cell: P) -> [P] {
            adjDirs.map { P(r: cell.r + $0.r, c: cell.c + $0.c) }.filter { n in
                inBounds(n) && n.r >= 3 && !bed.contains(n) && !rk.contains(n)
                    && !rk.contains(P(r: n.r - 1, c: n.c))   // don't dig out from under a rock
                    && !used.contains(n)                      // keep each monster's room its own
            }
        }
        var es: [Enemy] = []
        for i in 0..<enemyN {
            var chosen: P? = nil
            var room: [P] = []
            var t = 0
            while chosen == nil && t < 160 {
                t += 1
                let cell = P(r: Int.random(in: 5..<rowsN), c: Int.random(in: 0..<cols))
                if used.contains(cell) || manhattan(cell, player) < 5 { continue }
                if rk.contains(P(r: cell.r - 1, c: cell.c)) { continue }    // rock right above → skip
                let carvable = carvableNeighbours(of: cell)
                guard carvable.count >= 2 else { continue }                 // need a real ≥3-cell room
                chosen = cell
                room = Array(carvable.shuffled().prefix(min(3, carvable.count)))
            }
            // Fallback: any free cell so the game stays valid even if the grid is very tight.
            if chosen == nil {
                outer: for r in (5..<rowsN).shuffled() {
                    for c in (0..<cols).shuffled() {
                        let cell = P(r: r, c: c)
                        if !used.contains(cell) && manhattan(cell, player) >= 3 { chosen = cell; break outer }
                    }
                }
            }
            guard let cell = chosen else { continue }
            used.insert(cell); d.insert(cell)
            for n in room { d.insert(n); used.insert(n) }
            es.append(Enemy(cell: cell, inflate: 0, deflateDelay: 0, kind: i % 2))
        }
        dug = d; rocks = rk; rockWobble = [:]; rockFalling = []; bedrock = bed; enemies = es; bursts = []
        moveDir = nil; harpoon = nil; harpoonTimer = 0
        moveAcc = 0; enemyAcc = 0; rockAcc = 0
        started = false
        timeLeft = timeLimit; phase = .play
    }

    private func tick(dt: Double) {
        guard phase == .play else { return }
        if harpoonTimer > 0 { harpoonTimer -= dt; if harpoonTimer <= 0 { harpoon = nil } }

        // Deflate inflated monsters that aren't being actively pumped.
        for i in enemies.indices where enemies[i].inflate > 0 {
            enemies[i].deflateDelay -= dt
            if enemies[i].deflateDelay <= 0 {
                enemies[i].inflate = max(0, enemies[i].inflate - 1.4 * dt)
            }
        }

        // Player movement (hold to repeat).
        moveAcc += dt
        if let mv = moveDir, moveAcc >= 0.13 {
            moveAcc = 0
            let dest = P(r: player.r + mv.r, c: player.c + mv.c)
            if inBounds(dest) && !rocks.contains(dest) && !bedrock.contains(dest) {
                player = dest
                dug.insert(dest)
                SoundManager.shared.tap()
            }
        }
        if checkCaught() { return }

        // Rocks: an unsupported boulder teeters (wobbles) for a beat before it commits to falling,
        // giving the player a window to dash clear from under it.
        for rock in Array(rocks) where !rockFalling.contains(rock) {
            let below = P(r: rock.r + 1, c: rock.c)
            let unsupported = inBounds(below) && dug.contains(below)
                && !rocks.contains(below) && !bedrock.contains(below)
            if unsupported {
                if rockWobble[rock] == nil {
                    rockWobble[rock] = wobbleTime
                    SoundManager.shared.tap()               // the tell-tale wobble cue
                } else {
                    rockWobble[rock]! -= dt
                    if rockWobble[rock]! <= 0 { rockWobble[rock] = nil; rockFalling.insert(rock) }
                }
            } else {
                rockWobble[rock] = nil                       // re-supported (a rock landed below) — settle
            }
        }
        rockAcc += dt
        if rockAcc >= 0.11 { rockAcc = 0; fallRocks() }
        if phase == .done { return }

        // Enemy movement.
        enemyAcc += dt
        if enemyAcc >= enemyStep {
            enemyAcc = 0
            for i in enemies.indices { moveEnemy(&enemies[i]) }
            _ = checkCaught()
        }
    }

    private func fallRocks() {
        var rk = rocks
        var falling = rockFalling
        // Only rocks that finished wobbling actually drop; process bottom-up.
        for rock in rocks.sorted(by: { $0.r > $1.r }) where falling.contains(rock) {
            guard rk.contains(rock) else { continue }
            let below = P(r: rock.r + 1, c: rock.c)
            // A falling boulder smashes ANY monster in the cell beneath it — including a red
            // one phasing through dirt. (Previously the rock only crushed monsters in an open
            // tunnel, so it could rest on/pass a ghosting monster without hurting it.)
            if inBounds(below), let ei = enemies.firstIndex(where: { $0.cell == below }) {
                bursts.append(Burst(cell: below, color: monsterColor(enemies[ei].kind)))
                enemies.remove(at: ei)
                shakeTick += 1
            }
            guard inBounds(below), dug.contains(below), !rk.contains(below), !bedrock.contains(below) else {
                falling.remove(rock)                          // hit solid ground — it comes to rest
                continue
            }
            rk.remove(rock); rk.insert(below)
            falling.remove(rock); falling.insert(below)
            dug.insert(rock)                                  // vacated cell becomes tunnel
            shakeTick += 1
            SoundManager.shared.tap()
            if below == player { rocks = rk; rockFalling = falling; fail(); return }
        }
        rocks = rk
        rockFalling = falling
        if enemies.isEmpty && phase == .play { win() }
    }

    private func moveEnemy(_ e: inout Enemy) {
        if e.inflate > 0 { return }
        let dirs = [P(r:-1,c:0), P(r:1,c:0), P(r:0,c:-1), P(r:0,c:1)]
        let cur = manhattan(e.cell, player)
        // Every candidate step not blocked by a rock / bedrock / wall. Dirt cells are included
        // here — only the red phaser is ever allowed to actually enter one.
        let nbrs = dirs.map { P(r: e.cell.r + $0.r, c: e.cell.c + $0.c) }
            .filter { inBounds($0) && !rocks.contains($0) && !bedrock.contains($0) }

        // Pick the cell that gets closest to the player, but PREFER one no other monster occupies
        // so two monsters never stack into a single blob (which reads as one of them vanishing).
        // Falls back to any candidate, so a monster can never freeze for lack of a free cell.
        func choose(_ cells: [P]) -> P? {
            let free = cells.filter { c in !enemies.contains { $0.id != e.id && $0.cell == c } }
            return (free.isEmpty ? cells : free).min { manhattan($0, player) < manhattan($1, player) }
        }

        // Best OPEN (tunnel) neighbour that gets closer to the player.
        let openBetter = choose(nbrs.filter { isOpen($0) && manhattan($0, player) < cur })

        if e.kind == 0 {
            // RED phaser (Dig Dug's Pooka): it frequently ghosts straight through solid dirt toward
            // you — its signature move. It also must NEVER freeze: once inside dirt it always keeps
            // tunnelling toward the player, and while in a tunnel it starts a dirt shortcut with the
            // (high) `ghostChance`. Every phase step is guaranteed to move as long as some neighbour
            // reduces the distance, so it can't get stuck mid-dirt.
            let inDirt = isDirt(e.cell)
            // Demo: it always takes the phase roll (a legal roll sequence) so the clip is fixed.
            if inDirt || isDemo || Double.random(in: 0...1) < ghostChance {
                if let g = choose(nbrs.filter { manhattan($0, player) < cur }) { e.cell = g; return }
            }
            // Not phasing this step: prefer an improving tunnel, else move through any tunnel.
            if let best = openBetter { e.cell = best; return }
            if let d = choose(nbrs.filter { isOpen($0) }) { e.cell = d; return }
            // Boxed in with no open neighbour: step to the closest cell so it can't sit frozen.
            if let g = choose(nbrs) { e.cell = g }
            return
        }

        // GREEN monster: tunnel-bound — it only ever moves through open cells.
        if let best = openBetter { e.cell = best; return }
        if let d = choose(nbrs.filter { isOpen($0) }) { e.cell = d }
    }

    // MARK: - Demo (live manual clip)
    // A fixed level-1 dig (two monsters, one boulder, no bedrock) that shows both ways to win,
    // played through the real `fire`/`tick` at a fixed 1/30s (the real loop's step):
    //   • the red phaser ghosts up through the dirt toward you — step down, face it, PUMP ×3;
    //   • the green one is penned in a shaft under the boulder — dig in under the rock and dash
    //     back up the main shaft; the rock teeters, drops, and crushes it (the real win()).
    // Scripted and checked offline on a port of `tick`: win at 3.6s with no loose monster ever
    // closer than 2 cells, and it still wins with the second half shifted −2…+3 frames.
    private enum DemoInput { case hold(P), release, pump }
    private static let demoScript: [(frame: Int, input: DemoInput)] = [
        (6, .hold(P(r: 1, c: 0))), (9, .release),                     // step down, face the shaft
        (58, .pump), (64, .pump), (70, .pump),                        // red monster: pop
        (72, .hold(P(r: 1, c: 0))), (79, .release),                   // down to row 4
        (80, .hold(P(r: 0, c: 1))), (87, .release),                   // dig in under the boulder
        (91, .hold(P(r: 0, c: -1))), (98, .release),                  // dash back to the shaft…
        (99, .hold(P(r: -1, c: 0))), (105, .release)                  // …and up, clear of the drop
    ]

    private func demoSetup() {
        var d: Set<P> = []
        for c in 0..<cols { d.insert(P(r: 0, c: c)); d.insert(P(r: 1, c: c)) }
        for r in 0..<6 { d.insert(P(r: r, c: 4)) }
        // Monster rooms: red (8,4) with (8,3),(9,4); green (6,6) in a shaft (5,6)…(7,6).
        for cell in [P(r: 8, c: 4), P(r: 8, c: 3), P(r: 9, c: 4),
                     P(r: 5, c: 6), P(r: 6, c: 6), P(r: 7, c: 6)] { d.insert(cell) }
        dug = d
        rocks = [P(r: 3, c: 6)]; rockWobble = [:]; rockFalling = []; bedrock = []
        enemies = [Enemy(cell: P(r: 8, c: 4), inflate: 0, deflateDelay: 0, kind: 0),
                   Enemy(cell: P(r: 6, c: 6), inflate: 0, deflateDelay: 0, kind: 1)]
        bursts = []
        player = P(r: 1, c: 4); facing = P(r: 0, c: 1)
        moveDir = nil; harpoon = nil; harpoonTimer = 0
        moveAcc = 0; enemyAcc = 0; rockAcc = 0; demoPump = 0
        started = true                                   // fire() needs a started round
        timeLeft = timeLimit; phase = .play
    }

    private func runDemo() async {
        let dt = 1.0 / 30.0
        while !Task.isCancelled {
            demoSetup()
            try? await Task.sleep(for: .seconds(0.5))
            var frame = 0, next = 0
            while !Task.isCancelled && phase == .play && frame < 600 {
                frame += 1
                while next < Self.demoScript.count && Self.demoScript[next].frame <= frame {
                    switch Self.demoScript[next].input {
                    case .hold(let d): moveDir = d; facing = d
                    case .release: moveDir = nil
                    case .pump: fire(); demoPump = 4
                    }
                    next += 1
                }
                if demoPump > 0 { demoPump -= 1 }
                tick(dt: dt)
                try? await Task.sleep(for: .seconds(0.033))
            }
            // Both monsters gone → the real win() ran (onWin is a no-op). Hold, then loop.
            moveDir = nil; demoPump = 0
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    @discardableResult
    private func checkCaught() -> Bool {
        if enemies.contains(where: { $0.cell == player && $0.inflate == 0 }) { fail(); return true }
        return false
    }

    private func inBounds(_ p: P) -> Bool { p.r >= 0 && p.r < rowsN && p.c >= 0 && p.c < cols }
    private func manhattan(_ a: P, _ b: P) -> Int { abs(a.r - b.r) + abs(a.c - b.c) }

    private func win() {
        guard phase != .done else { return }
        phase = .done; loopTask?.cancel(); onWin()
    }
    private func fail() {
        guard phase != .done else { return }
        phase = .done; loopTask?.cancel(); shakeTick += 1; SoundManager.shared.error(); onFail()
    }

    // MARK: Look
    private func monsterColor(_ k: Int) -> Color {
        k == 0 ? Color(red: 0.93, green: 0.2, blue: 0.16) : Color(red: 0.3, green: 0.74, blue: 0.3)
    }
}

// MARK: - Dig Dug art (after Namco's 1982 arcade game)

/// A monster's id and column, to tell which way it just stepped.
private struct DDStep: Equatable {
    let id: UUID
    let c: Int
}

private enum DDArt {
    static func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    static func hash(_ n: Double) -> Double {
        let x = sin(n) * 43758.5453
        return x - floor(x)
    }

    /// The four dirt layers, top to bottom. Dig Dug's own yellow → maroon at level 1, a new set of
    /// earths each level after (never grey, so the bedrock always stands out).
    static func layers(_ level: Int) -> [Color] {
        switch min(max(level, 1), 7) {
        case 1: return [c(1.0, 0.74, 0.24), c(0.95, 0.52, 0.16), c(0.76, 0.27, 0.12), c(0.52, 0.13, 0.12)]
        case 2: return [c(0.98, 0.82, 0.44), c(0.88, 0.62, 0.32), c(0.68, 0.40, 0.22), c(0.46, 0.24, 0.15)]
        case 3: return [c(0.74, 0.88, 0.34), c(0.48, 0.72, 0.26), c(0.32, 0.52, 0.22), c(0.19, 0.33, 0.17)]
        case 4: return [c(0.96, 0.64, 0.56), c(0.84, 0.42, 0.44), c(0.62, 0.25, 0.35), c(0.40, 0.15, 0.25)]
        case 5: return [c(0.54, 0.78, 0.96), c(0.34, 0.54, 0.86), c(0.25, 0.35, 0.68), c(0.15, 0.19, 0.44)]
        case 6: return [c(0.80, 0.62, 0.96), c(0.60, 0.42, 0.84), c(0.42, 0.27, 0.62), c(0.25, 0.15, 0.40)]
        default: return [c(0.50, 0.86, 0.80), c(0.30, 0.66, 0.66), c(0.20, 0.46, 0.50), c(0.12, 0.28, 0.34)]
        }
    }

    static func layerIndex(_ r: Int) -> Int { max(0, min(3, (r - 2) / 3)) }

    /// Sky (rows 0–1, where the digger can walk the surface), strata with Dig Dug's stipple, round
    /// black tunnels, grey bedrock, and one flower per level on the surface.
    static func ground(_ ctx: GraphicsContext, rows: Int, cols: Int, dug: Set<Int>, bedrock: Set<Int>, level: Int,
                       cell: CGFloat, ox: CGFloat, oy: CGFloat) {
        let W = cell * CGFloat(cols)
        let sky = CGRect(x: ox, y: oy, width: W, height: cell * 2)
        ctx.fill(Path(sky), with: .linearGradient(Gradient(colors: [c(0.13, 0.28, 0.88), c(0.36, 0.58, 1.0)]),
                                                  startPoint: CGPoint(x: 0, y: sky.minY), endPoint: CGPoint(x: 0, y: sky.maxY)))
        let pal = layers(level)
        for r in 2..<rows {
            ctx.fill(Path(CGRect(x: ox, y: oy + CGFloat(r) * cell, width: W, height: cell + 0.5)), with: .color(pal[layerIndex(r)]))
        }
        var dark = [Path(), Path(), Path(), Path()], light = [Path(), Path(), Path(), Path()]
        for r in 2..<rows {
            for col in 0..<cols where !dug.contains(r * cols + col) && !bedrock.contains(r * cols + col) {
                let li = layerIndex(r)
                let x0 = ox + CGFloat(col) * cell, y0 = oy + CGFloat(r) * cell
                for k in 0..<7 {
                    let hx = CGFloat(hash(Double(r * 97 + col * 13 + k) * 1.3)), hy = CGFloat(hash(Double(r * 31 + col * 57 + k) * 2.7))
                    let d = cell * (0.06 + 0.05 * CGFloat(hash(Double(k + r + col) * 5.1)))
                    let rect = CGRect(x: x0 + hx * (cell - d), y: y0 + hy * (cell - d), width: d * 1.3, height: d)
                    if k < 5 { dark[li].addEllipse(in: rect) } else { light[li].addEllipse(in: rect) }
                }
            }
        }
        for li in 0..<4 {
            ctx.fill(dark[li], with: .color(pal[li].mix(with: .black, by: 0.32).opacity(0.85)))
            ctx.fill(light[li], with: .color(pal[li].mix(with: .white, by: 0.3).opacity(0.7)))
        }
        var seams = Path()
        for r in [5, 8, 11] where r < rows {
            seams.move(to: CGPoint(x: ox, y: oy + CGFloat(r) * cell)); seams.addLine(to: CGPoint(x: ox + W, y: oy + CGFloat(r) * cell))
        }
        ctx.stroke(seams, with: .color(.black.opacity(0.18)), lineWidth: max(1, cell * 0.04))
        ctx.fill(Path(CGRect(x: ox, y: sky.maxY - 0.5, width: W, height: max(1.5, cell * 0.06))), with: .color(pal[0].mix(with: .white, by: 0.35)))

        // Tunnels: round-ended, bridged to dug neighbours; the top row opens into the sky.
        var rooms = Path(), bridges = Path()
        let ins = cell * 0.05
        for idx in dug {
            let r = idx / cols, col = idx % cols
            guard r >= 2 else { continue }
            let x0 = ox + CGFloat(col) * cell, y0 = oy + CGFloat(r) * cell
            rooms.addRoundedRect(in: CGRect(x: x0 + ins, y: y0 + ins, width: cell - 2 * ins, height: cell - 2 * ins),
                                 cornerSize: CGSize(width: cell * 0.34, height: cell * 0.34))
            if col + 1 < cols && dug.contains(idx + 1) { bridges.addRect(CGRect(x: x0 + cell * 0.5, y: y0 + ins, width: cell, height: cell - 2 * ins)) }
            if r + 1 < rows && dug.contains(idx + cols) { bridges.addRect(CGRect(x: x0 + ins, y: y0 + cell * 0.5, width: cell - 2 * ins, height: cell)) }
            if r == 2 { bridges.addRect(CGRect(x: x0 + ins, y: y0 - 1, width: cell - 2 * ins, height: cell * 0.5 + 1)) }
        }
        let tunnel = c(0.02, 0.02, 0.03)
        ctx.fill(rooms, with: .color(tunnel))
        ctx.fill(bridges, with: .color(tunnel))

        // Bedrock: faceted grey stone.
        for idx in bedrock {
            let r = idx / cols, col = idx % cols
            let rect = CGRect(x: ox + CGFloat(col) * cell + cell * 0.03, y: oy + CGFloat(r) * cell + cell * 0.03, width: cell * 0.94, height: cell * 0.94)
            let stone = Path(roundedRect: rect, cornerRadius: cell * 0.14)
            ctx.fill(stone, with: .linearGradient(Gradient(colors: [Color(white: 0.66), Color(white: 0.36)]),
                                                  startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
            var facets = Path()
            facets.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.4))
            facets.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.18))
            facets.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.15, y: rect.midY))
            facets.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.18))
            facets.addLine(to: CGPoint(x: rect.midX - rect.width * 0.05, y: rect.maxY - rect.height * 0.2))
            ctx.stroke(facets, with: .color(.white.opacity(0.3)), lineWidth: max(1, cell * 0.04))
            ctx.stroke(stone, with: .color(Color(white: 0.14)), lineWidth: max(1, cell * 0.05))
        }

        // One flower per level on the surface, counting the rounds like the arcade does.
        let surface = sky.maxY
        for i in 0..<min(max(level, 1), 7) {
            flower(ctx, at: CGPoint(x: ox + W - cell * 0.32 - CGFloat(i) * cell * 0.4, y: surface), cell: cell)
        }
    }

    static func flower(_ ctx: GraphicsContext, at p: CGPoint, cell: CGFloat) {
        let s = cell * 0.4
        var stem = Path()
        stem.move(to: p); stem.addLine(to: CGPoint(x: p.x, y: p.y - s))
        ctx.stroke(stem, with: .color(c(0.18, 0.6, 0.2)), lineWidth: max(1, cell * 0.05))
        ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y - s * 0.55, width: s * 0.3, height: s * 0.16)), with: .color(c(0.18, 0.6, 0.2)))
        let head = CGPoint(x: p.x, y: p.y - s)
        var petals = Path()
        for k in 0..<5 {
            let a = Double(k) / 5 * 2 * .pi - .pi / 2
            let q = CGPoint(x: head.x + CGFloat(cos(a)) * s * 0.22, y: head.y + CGFloat(sin(a)) * s * 0.22)
            petals.addEllipse(in: CGRect(x: q.x - s * 0.17, y: q.y - s * 0.17, width: s * 0.34, height: s * 0.34))
        }
        ctx.fill(petals, with: .color(.white))
        ctx.fill(Path(ellipseIn: CGRect(x: head.x - s * 0.14, y: head.y - s * 0.14, width: s * 0.28, height: s * 0.28)), with: .color(c(1, 0.62, 0.12)))
    }

    /// A lumpy orange boulder (tilted while it teeters).
    static func rock(_ ctx: GraphicsContext, at p: CGPoint, size s: CGFloat, tiltDeg: Double, seed: Int) {
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        g.rotate(by: .degrees(tiltDeg))
        let n = 10
        var pts: [CGPoint] = []
        for i in 0..<n {
            let a = Double(i) / Double(n) * 2 * .pi
            let k = 0.4 + 0.07 * hash(Double(seed * 13 + i) * 1.7)
            pts.append(CGPoint(x: CGFloat(cos(a) * k) * s, y: CGFloat(sin(a) * k * 0.9) * s + s * 0.03))
        }
        var blob = Path()
        let mid = { (a: CGPoint, b: CGPoint) in CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        blob.move(to: mid(pts[n - 1], pts[0]))
        for i in 0..<n { blob.addQuadCurve(to: mid(pts[i], pts[(i + 1) % n]), control: pts[i]) }
        blob.closeSubpath()
        g.fill(blob, with: .radialGradient(Gradient(colors: [c(0.98, 0.74, 0.46), c(0.82, 0.5, 0.24), c(0.55, 0.3, 0.14)]),
                                           center: CGPoint(x: -s * 0.14, y: -s * 0.16), startRadius: 0, endRadius: s * 0.55))
        var marks = Path()
        for (x, y, d) in [(-0.14, 0.12, 0.08), (0.16, -0.02, 0.06), (0.04, 0.2, 0.05)] as [(CGFloat, CGFloat, CGFloat)] {
            marks.addEllipse(in: CGRect(x: x * s, y: y * s, width: d * s, height: d * s * 0.8))
        }
        g.fill(marks, with: .color(c(0.45, 0.24, 0.1).opacity(0.7)))
        var crack = Path()
        crack.move(to: CGPoint(x: s * 0.08, y: -s * 0.3)); crack.addLine(to: CGPoint(x: s * 0.16, y: -s * 0.14)); crack.addLine(to: CGPoint(x: s * 0.1, y: -s * 0.04))
        g.stroke(crack, with: .color(c(0.4, 0.2, 0.08)), style: StrokeStyle(lineWidth: max(0.8, s * 0.04), lineCap: .round, lineJoin: .round))
        g.stroke(blob, with: .color(c(0.24, 0.11, 0.04)), lineWidth: max(1, s * 0.05))
    }

    /// The pump's hose with its harpoon tip.
    static func harpoon(_ ctx: GraphicsContext, from a: CGPoint, to b: CGPoint, cell: CGFloat) {
        var hose = Path()
        hose.move(to: a); hose.addLine(to: b)
        ctx.stroke(hose, with: .color(.black.opacity(0.55)), style: StrokeStyle(lineWidth: cell * 0.12, lineCap: .round))
        ctx.stroke(hose, with: .color(Color(white: 0.96)), style: StrokeStyle(lineWidth: cell * 0.06, lineCap: .round))
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(0.001, hypot(dx, dy))
        let ux = dx / len, uy = dy / len
        var head = Path()
        head.move(to: CGPoint(x: b.x + ux * cell * 0.2, y: b.y + uy * cell * 0.2))
        head.addLine(to: CGPoint(x: b.x - uy * cell * 0.13, y: b.y + ux * cell * 0.13))
        head.addLine(to: CGPoint(x: b.x + uy * cell * 0.13, y: b.y - ux * cell * 0.13))
        head.closeSubpath()
        ctx.fill(head, with: .color(Color(white: 0.85)))
        ctx.stroke(head, with: .color(.black.opacity(0.7)), lineWidth: max(0.8, cell * 0.03))
    }

    /// Pooka: a red ball in yellow goggles. `puff` (0…1) is how far it's pumped up — it swells (via the
    /// size) and pales. A steady red halo keeps it plain to see while it phases through dirt.
    static func pooka(_ ctx: GraphicsContext, at p: CGPoint, size s: CGFloat, puff: Double, left: Bool, halo: Bool = true) {
        if halo {
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.68, y: p.y - s * 0.68, width: s * 1.36, height: s * 1.36)),
                     with: .radialGradient(Gradient(colors: [c(1, 0.3, 0.25).opacity(0.5), c(1, 0.3, 0.25).opacity(0)]), center: p, startRadius: s * 0.3, endRadius: s * 0.68))
        }
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        if left { g.scaleBy(x: -1, y: 1) }
        let body = c(0.93, 0.2, 0.16).mix(with: .white, by: puff * 0.45)
        let ink = c(0.2, 0.03, 0.03)
        for sx in [-0.18, 0.16] as [CGFloat] {
            g.fill(Path(ellipseIn: CGRect(x: sx * s - s * 0.11, y: s * 0.3, width: s * 0.24, height: s * 0.14)), with: .color(body.mix(with: .black, by: 0.35)))
        }
        let r = s * 0.42
        let disc = Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
        g.fill(disc, with: .radialGradient(Gradient(colors: [body.mix(with: .white, by: 0.3), body, body.mix(with: .black, by: 0.3)]),
                                           center: CGPoint(x: -s * 0.14, y: -s * 0.18), startRadius: 0, endRadius: r * 1.3))
        g.stroke(disc, with: .color(ink), lineWidth: max(1, s * 0.045))
        let band = Path(roundedRect: CGRect(x: -s * 0.3, y: -s * 0.24, width: s * 0.7, height: s * 0.28), cornerRadius: s * 0.14)
        g.fill(band, with: .color(c(1, 0.84, 0.18)))
        g.stroke(band, with: .color(ink), lineWidth: max(0.8, s * 0.035))
        for lx in [-0.06, 0.22] as [CGFloat] {
            let lens = Path(ellipseIn: CGRect(x: lx * s - s * 0.11, y: -s * 0.21, width: s * 0.22, height: s * 0.22))
            g.fill(lens, with: .color(.white))
            g.fill(Path(ellipseIn: CGRect(x: lx * s - s * 0.01, y: -s * 0.14, width: s * 0.09, height: s * 0.1)), with: .color(ink))
        }
    }

    /// Fygar: a little green dragon with a white wing, facing where it walks.
    static func fygar(_ ctx: GraphicsContext, at p: CGPoint, size s: CGFloat, puff: Double, left: Bool) {
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        if left { g.scaleBy(x: -1, y: 1) }
        g.scaleBy(x: s, y: s)
        let body = c(0.3, 0.74, 0.3).mix(with: .white, by: puff * 0.45)
        let dark = body.mix(with: .black, by: 0.35)
        let ink = c(0.03, 0.15, 0.04)
        let lw: CGFloat = 0.045
        var tail = Path()
        tail.move(to: CGPoint(x: -0.26, y: 0.02)); tail.addLine(to: CGPoint(x: -0.5, y: 0.22)); tail.addLine(to: CGPoint(x: -0.22, y: 0.2)); tail.closeSubpath()
        g.fill(tail, with: .color(dark))
        g.stroke(tail, with: .color(ink), lineWidth: lw)
        for lx in [-0.18, 0.1] as [CGFloat] {
            g.fill(Path(roundedRect: CGRect(x: lx, y: 0.24, width: 0.13, height: 0.16), cornerRadius: 0.04), with: .color(dark))
        }
        let torso = Path(ellipseIn: CGRect(x: -0.36, y: -0.24, width: 0.64, height: 0.56))
        g.fill(torso, with: .linearGradient(Gradient(colors: [body.mix(with: .white, by: 0.2), body, dark]), startPoint: CGPoint(x: 0, y: -0.24), endPoint: CGPoint(x: 0, y: 0.32)))
        g.stroke(torso, with: .color(ink), lineWidth: lw)
        let head = Path(roundedRect: CGRect(x: 0.02, y: -0.34, width: 0.48, height: 0.34), cornerRadius: 0.14)
        g.fill(head, with: .color(body))
        g.stroke(head, with: .color(ink), lineWidth: lw)
        var wing = Path()
        wing.move(to: CGPoint(x: -0.16, y: -0.18)); wing.addLine(to: CGPoint(x: -0.4, y: -0.46)); wing.addLine(to: CGPoint(x: -0.04, y: -0.3)); wing.closeSubpath()
        g.fill(wing, with: .color(c(0.94, 0.96, 0.9)))
        g.stroke(wing, with: .color(ink), lineWidth: lw * 0.8)
        g.fill(Path(ellipseIn: CGRect(x: 0.12, y: -0.3, width: 0.17, height: 0.17)), with: .color(.white))
        g.fill(Path(ellipseIn: CGRect(x: 0.19, y: -0.25, width: 0.08, height: 0.09)), with: .color(ink))
        g.fill(Path(ellipseIn: CGRect(x: 0.42, y: -0.26, width: 0.05, height: 0.05)), with: .color(ink))
        var mouth = Path()
        mouth.move(to: CGPoint(x: 0.3, y: -0.08)); mouth.addLine(to: CGPoint(x: 0.48, y: -0.08))
        g.stroke(mouth, with: .color(ink), lineWidth: lw)
    }

    /// The digger: a banana in Dig Dug's white helmet with a blue visor, pump nozzle forward. It turns
    /// to face its heading (on its side when digging up or down, as in the arcade).
    static func digger(_ ctx: GraphicsContext, at p: CGPoint, size s: CGFloat, dr: Int, dc: Int) {
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        if dr < 0 { g.rotate(by: .degrees(-90)) } else if dr > 0 { g.rotate(by: .degrees(90)) } else if dc < 0 { g.scaleBy(x: -1, y: 1) }
        g.scaleBy(x: s, y: s)
        let ink = c(0.12, 0.09, 0.04)
        let nozzle = Path(roundedRect: CGRect(x: 0.14, y: 0.02, width: 0.32, height: 0.11), cornerRadius: 0.04)
        g.fill(nozzle, with: .color(Color(white: 0.8)))
        g.stroke(nozzle, with: .color(ink), lineWidth: 0.035)
        var body = Path()
        body.move(to: CGPoint(x: -0.02, y: -0.4))
        body.addCurve(to: CGPoint(x: 0.08, y: 0.44), control1: CGPoint(x: -0.46, y: -0.2), control2: CGPoint(x: -0.4, y: 0.36))
        body.addCurve(to: CGPoint(x: -0.02, y: -0.4), control1: CGPoint(x: 0.12, y: 0.2), control2: CGPoint(x: 0.2, y: -0.18))
        body.closeSubpath()
        g.fill(body, with: .linearGradient(Gradient(colors: [c(1, 0.93, 0.42), c(0.95, 0.72, 0.14)]), startPoint: CGPoint(x: 0.1, y: 0), endPoint: CGPoint(x: -0.35, y: 0)))
        g.stroke(body, with: .color(ink), lineWidth: 0.04)
        var helmet = Path()
        helmet.move(to: CGPoint(x: -0.26, y: -0.24))
        helmet.addQuadCurve(to: CGPoint(x: 0.22, y: -0.27), control: CGPoint(x: -0.04, y: -0.64))
        helmet.closeSubpath()
        g.fill(helmet, with: .color(Color(white: 0.97)))
        g.fill(Path(roundedRect: CGRect(x: -0.27, y: -0.31, width: 0.52, height: 0.08), cornerRadius: 0.04), with: .color(c(0.2, 0.42, 0.95)))
        g.stroke(helmet, with: .color(ink), lineWidth: 0.035)
        let eye = Path(ellipseIn: CGRect(x: -0.03, y: -0.2, width: 0.16, height: 0.17))
        g.fill(eye, with: .color(.white))
        g.stroke(eye, with: .color(ink), lineWidth: 0.025)
        g.fill(Path(ellipseIn: CGRect(x: 0.05, y: -0.15, width: 0.06, height: 0.08)), with: .color(ink))
    }
}

/// Everything static between digs: redrawn only when a cell is dug.
private struct DDGround: View, Equatable {
    let size: CGSize
    let rows: Int
    let cols: Int
    let dug: Set<Int>
    let bedrock: Set<Int>
    let level: Int

    var body: some View {
        Canvas { ctx, _ in
            guard rows > 2, cols > 0 else { return }
            let cell = min(size.width / CGFloat(cols), size.height / CGFloat(rows))
            let ox = (size.width - cell * CGFloat(cols)) / 2
            let oy = (size.height - cell * CGFloat(rows)) / 2
            DDArt.ground(ctx, rows: rows, cols: cols, dug: dug, bedrock: bedrock, level: level, cell: cell, ox: ox, oy: oy)
        }
    }
}

/// The counter's Pooka.
private struct DDPookaIcon: View {
    var body: some View {
        Canvas { ctx, size in
            DDArt.pooka(ctx, at: CGPoint(x: size.width / 2, y: size.height / 2), size: min(size.width, size.height) * 1.05, puff: 0, left: false, halo: false)
        }
    }
}

/// The PUMP key's icon: a T-handle air pump with its hose.
private struct DDPumpIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let ink = Color.black.opacity(0.55)
            var hose = Path()
            hose.move(to: CGPoint(x: w * 0.58, y: h * 0.84))
            hose.addQuadCurve(to: CGPoint(x: w * 0.9, y: h * 0.5), control: CGPoint(x: w * 0.95, y: h * 0.9))
            ctx.stroke(hose, with: .color(ink), style: StrokeStyle(lineWidth: w * 0.12, lineCap: .round))
            ctx.stroke(hose, with: .color(.white), style: StrokeStyle(lineWidth: w * 0.07, lineCap: .round))
            let barrel = Path(roundedRect: CGRect(x: w * 0.36, y: h * 0.32, width: w * 0.24, height: h * 0.52), cornerRadius: w * 0.05)
            let handle = Path(roundedRect: CGRect(x: w * 0.18, y: h * 0.08, width: w * 0.6, height: h * 0.1), cornerRadius: w * 0.05)
            let foot = Path(roundedRect: CGRect(x: w * 0.22, y: h * 0.84, width: w * 0.52, height: h * 0.09), cornerRadius: w * 0.04)
            var rod = Path()
            rod.move(to: CGPoint(x: w * 0.48, y: h * 0.16)); rod.addLine(to: CGPoint(x: w * 0.48, y: h * 0.34))
            ctx.stroke(rod, with: .color(ink), lineWidth: w * 0.12)
            ctx.stroke(rod, with: .color(.white), lineWidth: w * 0.07)
            for part in [barrel, handle, foot] {
                ctx.stroke(part, with: .color(ink), lineWidth: w * 0.06)
                ctx.fill(part, with: .color(.white))
            }
        }
    }
}

/// Earth-brown d-pad keys (yellow when pressed) and the red PUMP key.
private struct DDKey: View {
    let pump: Bool
    let lit: Bool

    var body: some View {
        let colors: [Color] = pump
            ? (lit ? [Color(red: 1, green: 0.5, blue: 0.4), Color(red: 0.86, green: 0.22, blue: 0.16)] : [Color(red: 0.92, green: 0.24, blue: 0.18), Color(red: 0.62, green: 0.1, blue: 0.08)])
            : (lit ? [Color(red: 1, green: 0.84, blue: 0.36), Color(red: 0.92, green: 0.62, blue: 0.16)] : [Color(red: 0.4, green: 0.27, blue: 0.18), Color(red: 0.24, green: 0.15, blue: 0.1)])
        return ZStack {
            RoundedRectangle(cornerRadius: pump ? 14 : 12).fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: pump ? 14 : 12).strokeBorder(Color.black.opacity(0.55), lineWidth: 2)
            RoundedRectangle(cornerRadius: pump ? 11 : 9).strokeBorder(.white.opacity(lit ? 0.9 : 0.2), lineWidth: 1.2).padding(3)
        }
    }
}

private struct DDPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.92 : 1)
    }
}
