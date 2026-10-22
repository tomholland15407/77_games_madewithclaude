//
//  CheerUpMonkeyGame.swift
//  A Banana Game
//
//  Brain — a point-and-tap puzzle stage in the style of the Monkey GO Happy series. A sad monkey sits
//  at the bottom of the scene; the banana that would cheer it up is shut in a chest whose lock has a
//  row of coloured symbol wheels. Mini monkeys hide around the scene, peeking out from behind rocks
//  and bushes or shut inside barrels, pots and crates (tap to open them). Each one holds up a placard
//  in one wheel's colour showing that wheel's symbol, then hops into the basket with it: the sign is
//  shown only that once, so the player has to remember it. From level 2 one wheel shows dice pips
//  instead: count the gems of that wheel's colour (some are shut in containers, and gems in other
//  colours are decoys). Set every wheel and the chest springs open; tap the banana to hand it over and
//  the monkey jumps for joy. Run out of time and you're back to level 1.
//
//  7 levels: four wheels of four symbols and four mini monkeys (two in plain sight, two shut in
//  containers) at level 1, up to eight wheels of six symbols, seven mini monkeys, ten containers to
//  search and decoy gems at level 7 (more than five wheels sit on two rows). Clocks run 34, 36, 34,
//  32, 30, 24 and 21 seconds. Tapping costs nothing but time, so the clock (and a forgotten sign) is
//  the only way to lose. Every stage is dealt at random, and it is always solvable: each wheel's clue
//  is somewhere in the scene. The clocks come from a player model run on real deals (time to look,
//  spot, open, count and click; forgetting isn't modelled): a casual player clears level 1 and about
//  half of level 2, a steady one clears up to level 4 most of the time, and level 7 takes expert
//  speed, which wins it about a quarter of the time.
//
//  Drawn like the Monkey GO Happy stages: a painted, outlined cartoon scene (a cottage at dusk, a
//  jungle temple, a ship's deck, a reef, then the same places by night, at sunset and in a storm),
//  the big-headed orange monkey with the peach face and huge purple eyes at the bottom, tiny mini
//  monkeys, a wicker basket that fills with the ones you find, and a wooden lock panel of
//  brass-framed wheels.
//
//  The rules are `CMStage`, a plain value; the view only animates what it reports. The demo plays a
//  fixed level-1 stage through the same calls.
//

import SwiftUI

enum CheerUpMonkeyGame {
    static let definition = GameDefinition(
        id: "cheer-up-monkey",
        title: "Cheer Up Monkey",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Find the mini monkeys: tap them where they peek out, and tap barrels, pots and crates to look inside.",
                "Each mini monkey shows a symbol in one wheel's colour only once, so remember it; dice wheels mean counting the gems of that colour.",
                "Set every wheel to open the chest, then tap the banana to cheer the monkey up.",
                "If time runs out, you're back to level 1.",
            ],
            bulletsVI: [
                "Tìm các chú khỉ con: chạm vào chỗ chúng ló ra, và chạm thùng, hũ, hộp gỗ để xem bên trong.",
                "Mỗi chú khỉ con chỉ giơ ký hiệu cùng màu với một bánh xoay một lần, hãy nhớ kỹ; bánh có chấm xúc xắc là đếm số ngọc màu đó.",
                "Xoay đúng mọi bánh để mở rương, rồi chạm vào quả chuối để làm chú khỉ vui lên.",
                "Nếu hết giờ, bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(CheerUpMonkeyView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

// MARK: - Rules

/// Wheel and clue colours: each wheel has its own, and its clue (a placard or gems) is in that colour.
/// Clear crystal is never a wheel's colour; it's only ever a decoy gem.
enum CMHue: Int, CaseIterable {
    case red, blue, green, purple, orange, yellow, pink, teal, crystal
    static let wheelHues: [CMHue] = [.red, .blue, .green, .purple, .orange, .yellow, .pink, .teal]
}

/// Scene props. Barrels, pots and crates open; the rest are cover to peek out from.
enum CMPropKind: Int {
    case barrel, pot, crate, rock, bush, stump, sack, coral
    var opens: Bool { rawValue <= 2 }
}

/// What a container holds.
enum CMLoot: Equatable {
    case nothing
    case mini(Int)              // that mini monkey
    case gems(CMHue, Int)       // that many clue gems
    case junk(Int)              // something useless (a sock, a fish bone, an old boot)
}

struct CMProp {
    let kind: CMPropKind
    let x: Double, y: Double    // where it stands, in scene fractions
    let scale: Double
    var loot: CMLoot = .nothing
    var open = false
}

struct CMMini {
    let hue: CMHue
    let glyph: Int              // the symbol on its placard
    let host: Int               // the prop it peeks out from behind, or sits inside
    let side: Int               // peeking: −1 left, 1 right, 0 over the top
    let inside: Bool
    var found = false
}

struct CMGem {
    let hue: CMHue
    let x: Double, y: Double    // scene fractions (a gem inside a container sits by it once opened)
    let host: Int?              // the container it's shut in, if any
}

struct CMWheel {
    let hue: CMHue
    let count: Bool             // pips (count the gems) instead of symbols
    let target: Int             // the face that opens the lock (count wheels: pips − 1)
    var shown: Int
}

struct CMRandom {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(max(1, n))) }
    mutating func shuffle<T>(_ a: inout [T]) {
        guard a.count > 1 else { return }
        for i in stride(from: a.count - 1, to: 0, by: -1) { a.swapAt(i, int(i + 1)) }
    }
}

struct CMParams {
    let wheels: Int             // code length
    let symbols: Int            // faces per wheel
    let counts: Int             // wheels whose clue is a gem count (the rest come from mini monkeys)
    let peeking: Int            // mini monkeys in plain sight (the rest hide in containers)
    let containers: Int         // barrels, pots and crates to search
    let hiddenGems: Int         // clue gems shut in containers
    let decoyGems: Int          // gems in colours no wheel uses
    let time: Double

    static func level(_ level: Int) -> CMParams {
        let i = min(max(level, 1), 7) - 1
        return CMParams(wheels: [4, 5, 6, 6, 7, 7, 8][i],
                        symbols: [4, 4, 5, 5, 6, 6, 6][i],
                        counts: [0, 1, 1, 1, 1, 1, 1][i],
                        peeking: [2, 2, 2, 2, 2, 2, 2][i],
                        containers: [4, 5, 6, 7, 8, 9, 10][i],
                        hiddenGems: [0, 0, 1, 1, 2, 2, 2][i],
                        decoyGems: [0, 1, 1, 2, 2, 3, 3][i],
                        time: [34, 36, 34, 32, 30, 24, 21][i])
    }
}

/// One stage: the props, who hides where, the gems, and the lock.
struct CMStage {
    var props: [CMProp]
    var minis: [CMMini]
    var gems: [CMGem]
    var wheels: [CMWheel]
    let symbols: Int
    var bananaGiven = false

    var unlocked: Bool { wheels.allSatisfy { $0.shown == $0.target } }
    var found: Int { minis.filter(\.found).count }

    /// Spots a prop can stand on: feet in scene fractions and a size, back to front. The middle
    /// bottom is the monkey's, the bottom corners hold the basket and the chest.
    static let slots: [(x: Double, y: Double, s: Double)] = [
        (0.15, 0.36, 0.7), (0.5, 0.35, 0.7), (0.85, 0.36, 0.7),
        (0.13, 0.5, 0.8), (0.34, 0.5, 0.8), (0.66, 0.5, 0.8), (0.87, 0.5, 0.8),
        (0.5, 0.47, 0.75),
        (0.12, 0.64, 0.9), (0.31, 0.65, 0.9), (0.5, 0.6, 0.8), (0.69, 0.65, 0.9), (0.88, 0.64, 0.9),
        (0.17, 0.79, 1.0), (0.83, 0.79, 1.0),
    ]

    /// Scenery kinds for a theme (0 cottage, 1 temple, 2 deck, 3 reef): cover to peek out from.
    static func cover(_ theme: Int) -> [CMPropKind] {
        switch theme {
        case 1: return [.rock, .bush]
        case 2: return [.sack, .rock]
        case 3: return [.coral, .rock]
        default: return [.bush, .rock, .stump]
        }
    }

    /// Deals a stage. Every clue must fit on the ground, so a deal that runs out of room for a
    /// counting wheel's gems is thrown away and dealt again.
    static func make(_ p: CMParams, theme: Int, seed: UInt64) -> CMStage {
        var s = seed
        while true {
            if let stage = attempt(p, theme: theme, seed: s) { return stage }
            s = s &+ 0x9E37_79B9_7F4A_7C15
        }
    }

    static func attempt(_ p: CMParams, theme: Int, seed: UInt64) -> CMStage? {
        var rng = CMRandom(state: seed)
        // The lock: k colours, `counts` of them read from gems.
        var hues = CMHue.wheelHues
        rng.shuffle(&hues)
        let k = p.wheels
        var isCount = Array(repeating: false, count: k)
        var order = Array(0..<k)
        rng.shuffle(&order)
        for i in order.prefix(p.counts) { isCount[i] = true }
        var wheels: [CMWheel] = []
        for i in 0..<k {
            let target = isCount[i] ? rng.int(min(p.symbols, 5)) : rng.int(p.symbols)
            wheels.append(CMWheel(hue: hues[i], count: isCount[i], target: target, shown: rng.int(p.symbols)))
        }
        if wheels.allSatisfy({ $0.shown == $0.target }) { wheels[0].shown = (wheels[0].shown + 1) % p.symbols }

        // Props: containers and cover on shuffled spots, with a little jitter.
        let miniWheels = (0..<k).filter { !isCount[$0] }
        let peeking = min(p.peeking, miniWheels.count)
        let coverCount = peeking + 1
        var spots = Array(0..<slots.count)
        rng.shuffle(&spots)
        let kinds = cover(theme)
        var props: [CMProp] = []
        for (n, s) in spots.prefix(p.containers + coverCount).enumerated() {
            let slot = slots[s]
            let kind: CMPropKind = n < p.containers ? [.barrel, .pot, .crate][rng.int(3)] : kinds[rng.int(kinds.count)]
            props.append(CMProp(kind: kind, x: slot.x + (rng.unit() - 0.5) * 0.04, y: slot.y + (rng.unit() - 0.5) * 0.02, scale: slot.s))
        }
        var containers = Array(0..<p.containers)
        rng.shuffle(&containers)
        let covers = Array(p.containers..<props.count)

        // Mini monkeys: one per symbol wheel, some peeking from behind cover, the rest shut inside.
        var minis: [CMMini] = []
        var nextContainer = 0
        for (n, w) in miniWheels.enumerated() {
            let glyph = wheels[w].target
            if n < peeking {
                // Peek over the top or out to a side, but never toward the scene's edge (cut off) and,
                // in the front row beside the big monkey, only over the top.
                let host = props[covers[n]]
                let sides: [Int] = host.y > 0.7 ? [0] : host.x < 0.25 ? [0, 1] : host.x > 0.75 ? [0, -1] : [0, -1, 1]
                minis.append(CMMini(hue: wheels[w].hue, glyph: glyph, host: covers[n], side: sides[rng.int(sides.count)], inside: false))
            } else {
                let c = containers[nextContainer]; nextContainer += 1
                props[c].loot = .mini(minis.count)
                minis.append(CMMini(hue: wheels[w].hue, glyph: glyph, host: c, side: 0, inside: true))
            }
        }

        // Gems: each count wheel's colour, as many as its answer; some shut in containers. Decoys in
        // colours no wheel uses lie about too.
        var gems: [CMGem] = []
        var hiddenLeft = p.hiddenGems
        var spotsFree = freeGemSpots(props: props, rng: &rng)
        for w in 0..<k where isCount[w] {
            var n = wheels[w].target + 1
            while n > 0 && hiddenLeft > 0 && nextContainer < containers.count && rng.unit() < 0.7 {
                let c = containers[nextContainer]; nextContainer += 1
                let inside = min(n, 1 + rng.int(2))
                props[c].loot = .gems(wheels[w].hue, inside)
                for g in 0..<inside {
                    gems.append(CMGem(hue: wheels[w].hue, x: props[c].x + (Double(g) - Double(inside - 1) / 2) * 0.05, y: props[c].y - 0.005, host: c))
                }
                n -= inside; hiddenLeft -= 1
            }
            for _ in 0..<n {
                guard let s = spotsFree.popLast() else { return nil }
                gems.append(CMGem(hue: wheels[w].hue, x: s.0, y: s.1, host: nil))
            }
        }
        let decoyHues = CMHue.allCases.filter { h in !wheels.contains { $0.hue == h } }
        for _ in 0..<p.decoyGems where !spotsFree.isEmpty && !decoyHues.isEmpty {
            let s = spotsFree.removeLast()
            gems.append(CMGem(hue: decoyHues[rng.int(decoyHues.count)], x: s.0, y: s.1, host: nil))
        }
        // The other containers hold junk.
        for c in containers[nextContainer...] { props[c].loot = .junk(rng.int(3)) }
        return CMStage(props: props, minis: minis, gems: gems, wheels: wheels, symbols: p.symbols)
    }

    /// Open ground for loose gems: a jittered grid over the scene's floor, away from props, the
    /// monkey, the basket and the chest; shuffled.
    static func freeGemSpots(props: [CMProp], rng: inout CMRandom) -> [(Double, Double)] {
        var out: [(Double, Double)] = []
        for gy in stride(from: 0.4, through: 0.87, by: 0.067) {
            for gx in stride(from: 0.07, through: 0.94, by: 0.072) {
                let x = gx + (rng.unit() - 0.5) * 0.02, y = gy + (rng.unit() - 0.5) * 0.015
                if abs(x - 0.5) < 0.2 && y > 0.6 { continue }                 // the monkey
                if y > 0.8 && (x < 0.3 || x > 0.7) { continue }               // basket and chest
                if props.contains(where: { abs($0.x - x) < 0.1 * $0.scale + 0.03 && y < $0.y + 0.02 && y > $0.y - 0.13 * $0.scale }) { continue }
                out.append((x, y))
            }
        }
        rng.shuffle(&out)
        return out
    }

    /// Tap a closed container: it opens. A mini monkey inside is found at once.
    mutating func open(_ i: Int) {
        guard props.indices.contains(i), props[i].kind.opens, !props[i].open else { return }
        props[i].open = true
        if case .mini(let m) = props[i].loot { minis[m].found = true }
    }

    /// Tap a mini monkey peeking out.
    mutating func collect(_ m: Int) {
        guard minis.indices.contains(m), !minis[m].inside else { return }
        minis[m].found = true
    }

    /// Tap a wheel: the next face.
    mutating func turn(_ w: Int) {
        guard wheels.indices.contains(w), !unlocked else { return }
        wheels[w].shown = (wheels[w].shown + 1) % symbols
    }

    /// Tap the banana once the chest is open.
    mutating func giveBanana() {
        guard unlocked else { return }
        bananaGiven = true
    }
}

// MARK: - Layout

/// Where things sit in a scene of a given size. The drawing and the hit tests both use these.
enum CMLayout {
    /// The prop size unit.
    static func unit(_ s: CGSize) -> CGFloat { min(s.width, s.height * 0.62) / 5 }

    /// Height and width of a prop, as multiples of its scaled unit.
    static func shape(_ k: CMPropKind) -> (h: CGFloat, w: CGFloat) {
        switch k {
        case .barrel: return (1.0, 0.78)
        case .pot: return (0.95, 0.82)
        case .crate: return (0.82, 0.96)
        case .rock: return (0.72, 1.4)
        case .bush: return (0.9, 1.45)
        case .stump: return (0.62, 1.05)
        case .sack: return (0.86, 0.9)
        case .coral: return (1.05, 1.1)
        }
    }

    static func propRect(_ p: CMProp, _ s: CGSize) -> CGRect {
        let u = unit(s) * CGFloat(p.scale)
        let k = shape(p.kind)
        // Kept whole inside the scene, whatever its shape.
        let half = u * k.w / 2
        let fx = min(max(CGFloat(p.x) * s.width, half + 4), s.width - half - 4), fy = CGFloat(p.y) * s.height
        return CGRect(x: fx - half, y: fy - u * k.h, width: u * k.w, height: u * k.h)
    }

    static func miniR(_ s: CGSize, scale: Double = 1) -> CGFloat { unit(s) * 0.2 * CGFloat(scale) }

    /// A peeking mini monkey's head centre: just out from its cover's side, or over its top.
    static func peekHead(_ m: CMMini, _ stage: CMStage, _ s: CGSize) -> CGPoint {
        let host = stage.props[m.host]
        let r = propRect(host, s)
        let mr = miniR(s, scale: host.scale)
        switch m.side {
        case -1: return CGPoint(x: r.minX + mr * 0.15, y: r.minY + r.height * 0.42)
        case 1: return CGPoint(x: r.maxX - mr * 0.15, y: r.minY + r.height * 0.42)
        default: return CGPoint(x: r.midX + r.width * 0.12, y: r.minY + mr * 0.25)
        }
    }

    /// The big monkey: head radius and where its feet are.
    static func monkeyR(_ s: CGSize) -> CGFloat { min(s.width * 0.135, s.height * 0.115) }
    static func monkeyFeet(_ s: CGSize) -> CGPoint { CGPoint(x: s.width / 2, y: s.height - 4) }

    static func chestRect(_ s: CGSize) -> CGRect {
        let r = monkeyR(s)
        return CGRect(x: s.width * 0.83 - r * 0.95, y: s.height - 6 - r * 1.25, width: r * 1.9, height: r * 1.25)
    }

    static func basketRect(_ s: CGSize) -> CGRect {
        let r = monkeyR(s)
        return CGRect(x: s.width * 0.17 - r * 1.0, y: s.height - 6 - r * 1.05, width: r * 2.0, height: r * 1.05)
    }

    /// The banana once the chest springs open: up over the chest.
    static func bananaPoint(_ s: CGSize) -> CGPoint {
        let c = chestRect(s)
        return CGPoint(x: c.midX, y: c.minY - monkeyR(s) * 0.55)
    }
}

// MARK: - View

struct CheerUpMonkeyView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var stage = CMStage(props: [], minis: [], gems: [], wheels: [], symbols: 3)
    @State private var built = false
    @State private var timeLeft = 0.0
    @State private var sceneSize: CGSize = .zero
    @State private var fx = CMFx()
    // Demo-only: the finger, on a scene point or on a wheel.
    @State private var demoPoint: CGPoint?
    @State private var demoWheel: Int?
    @State private var demoTap = 0

    private var params: CMParams { CMParams.level(level) }
    private var li: Int { min(max(level, 1), 7) - 1 }
    /// Cottage, temple, deck, reef, then the cottage by night, the temple at sunset, the deck in a storm.
    private var theme: Int { [0, 1, 2, 3, 0, 1, 2][li] }
    private var night: Bool { level >= 5 }

    var body: some View {
        VStack(spacing: 0) {
            if !isDemo {
                timeBar.frame(height: 6).padding(.horizontal, 36).padding(.top, 10).padding(.bottom, 8)
            }
            scene
                .clipShape(RoundedRectangle(cornerRadius: isDemo ? 8 : 12))
                .overlay(RoundedRectangle(cornerRadius: isDemo ? 8 : 12).stroke(.black.opacity(0.8), lineWidth: 2))
                .padding(.horizontal, isDemo ? 6 : 8)
                .padding(.top, isDemo ? 6 : 0)
            lockPanel
                .padding(.horizontal, isDemo ? 6 : 8)
                .padding(.top, isDemo ? 6 : 8)
                .padding(.bottom, isDemo ? 6 : 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CMFrame().equatable())
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
    }

    // MARK: Scene

    private var scene: some View {
        GeometryReader { geo in
            let s = geo.size
            ZStack(alignment: .topLeading) {
                CMBackdrop(theme: theme, night: night).equatable()
                TimelineView(.animation) { tl in
                    Canvas { ctx, size in
                        CMArt.scene(ctx, size: size, stage: stage, fx: fx, now: tl.date, theme: theme, night: night)
                    }
                }
                .allowsHitTesting(false)
                if isDemo, let p = demoPoint {
                    ZStack {
                        DemoTapRipple().id(demoTap)
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.7), radius: 3)
                            .offset(x: 12, y: 15)
                    }
                    .position(p)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: s.width, height: s.height)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { p in
                guard !isDemo else { return }
                tap(at: p, in: s)
            }
            .onAppear { sceneSize = s }
            .onChange(of: s) { _, new in sceneSize = new }
        }
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac = params.time > 0 ? timeLeft / params.time : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.45))
                Capsule().fill(frac < 0.25 ? Color(red: 1, green: 0.3, blue: 0.2) : Color(red: 1, green: 0.82, blue: 0.1))
                    .frame(width: geo.size.width * max(0, frac))
            }
            .overlay(Capsule().stroke(.black.opacity(0.6), lineWidth: 1))
        }
    }

    /// The lock: one brass-framed wheel per colour on a wooden plank. Past five wheels they go on two
    /// rows, every wheel as wide as one in the longer row and the shorter row centred.
    private var lockPanel: some View {
        let n = stage.wheels.count
        let gap: CGFloat = isDemo ? 6 : 8
        let twoRows = n > 5
        let rows = twoRows ? [Array(0..<(n + 1) / 2), Array((n + 1) / 2..<n)] : [Array(0..<n)]
        // The plank is as wide as the scene above it; its padding is 10 a side.
        let perRow = CGFloat((n + 1) / 2)
        let width: CGFloat? = twoRows ? max(24, (sceneSize.width - 20 - (perRow - 1) * gap) / perRow) : nil
        return VStack(spacing: gap) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: gap) {
                    ForEach(rows[r], id: \.self) { i in
                        wheel(i, width: width, height: twoRows ? 56 : (isDemo ? 46 : 70))
                    }
                }
            }
        }
        .padding(isDemo ? 6 : 10)
        .frame(maxWidth: .infinity)
        .background(CMPlank().equatable())
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 8 : 12))
        .overlay(RoundedRectangle(cornerRadius: isDemo ? 8 : 12).stroke(.black.opacity(0.75), lineWidth: 2))
    }

    private func wheel(_ i: Int, width: CGFloat?, height: CGFloat) -> some View {
        let w = stage.wheels[i]
        return Button { turn(i) } label: {
            CMWheelFace(hue: w.hue, count: w.count, face: w.shown, open: stage.unlocked, compact: isDemo)
                .frame(width: width, height: height)
                .overlay {
                    if isDemo && demoWheel == i {
                        ZStack {
                            DemoTapRipple().id(demoTap)
                            Image(systemName: "hand.point.up.left.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.7), radius: 3)
                                .offset(x: 11, y: 14)
                        }
                    }
                }
        }
        .buttonStyle(CMWheelStyle(lit: isDemo && demoWheel == i))
        .disabled(phase != .play || stage.unlocked)
    }

    // MARK: Input

    /// A tap on the scene: the banana once the chest is open, a peeking mini monkey, or a closed
    /// container (front ones first, as they're drawn on top).
    private func tap(at p: CGPoint, in s: CGSize) {
        guard phase == .play, !stage.bananaGiven else { return }
        if stage.unlocked {
            let b = CMLayout.bananaPoint(s)
            if hypot(p.x - b.x, p.y - b.y) < max(30, CMLayout.monkeyR(s) * 0.8) { giveBanana() }
            return
        }
        for (i, m) in stage.minis.enumerated() where !m.found && !m.inside {
            let h = CMLayout.peekHead(m, stage, s)
            if hypot(p.x - h.x, p.y - h.y) < max(20, CMLayout.miniR(s, scale: stage.props[m.host].scale) * 1.6) {
                collect(i)
                return
            }
        }
        let order = stage.props.indices.sorted { stage.props[$0].y > stage.props[$1].y }
        for i in order where stage.props[i].kind.opens && !stage.props[i].open {
            if CMLayout.propRect(stage.props[i], s).insetBy(dx: -6, dy: -6).contains(p) {
                open(i)
                return
            }
        }
    }

    private func collect(_ m: Int) {
        stage.collect(m)
        fx.foundAt[m] = Date()
        SoundManager.shared.tap(); Haptics.tap()
    }

    private func open(_ i: Int) {
        stage.open(i)
        fx.openedAt[i] = Date()
        if case .mini(let m) = stage.props[i].loot { fx.foundAt[m] = Date() }
        SoundManager.shared.tap(); Haptics.tap()
    }

    private func turn(_ w: Int) {
        guard phase == .play, !stage.unlocked else { return }
        stage.turn(w)
        SoundManager.shared.tap(); Haptics.tap()
        if stage.unlocked {
            fx.unlockedAt = Date()
            Haptics.success()
        }
    }

    private func giveBanana() {
        stage.giveBanana()
        fx.givenAt = Date()
        SoundManager.shared.tap()
        Task {
            try? await Task.sleep(for: .seconds(1.1))   // let the monkey jump for joy first
            win()
        }
    }

    // MARK: Flow

    private func run() async {
        if !built {
            stage = CMStage.make(params, theme: theme, seed: UInt64.random(in: 1...UInt64.max))
            timeLeft = params.time
            built = true
        }
        let start = Date().addingTimeInterval(-(params.time - timeLeft))
        while !Task.isCancelled && phase == .play {
            try? await Task.sleep(for: .seconds(0.05))
            if stage.bananaGiven { continue }        // the clock stops once the monkey has its banana
            timeLeft = max(0, params.time - Date().timeIntervalSince(start))
            if timeLeft <= 0 { fail(); break }
        }
    }

    // MARK: Demo (live manual clip)
    // A small fixed stage: two mini monkeys peek out, a red one from behind a rock and a blue one
    // over a bush, with a barrel and a pot that hold only junk. The finger taps the red mini monkey
    // and, once it has hopped into the basket with its sign, turns the red wheel to the triangle; then
    // the blue one, and the blue wheel to the square. The chest springs open and it hands the banana
    // over. Every step is the real stage call.
    private static func demoStage() -> CMStage {
        // Sized up for the small card.
        let props = [
            CMProp(kind: .barrel, x: 0.3, y: 0.52, scale: 1.25, loot: .junk(0)),
            CMProp(kind: .pot, x: 0.7, y: 0.52, scale: 1.25, loot: .junk(1)),
            CMProp(kind: .rock, x: 0.15, y: 0.74, scale: 1.4),
            CMProp(kind: .bush, x: 0.85, y: 0.72, scale: 1.4),
        ]
        let minis = [
            CMMini(hue: .red, glyph: 1, host: 2, side: 1, inside: false),
            CMMini(hue: .blue, glyph: 2, host: 3, side: 0, inside: false),
        ]
        let wheels = [
            CMWheel(hue: .red, count: false, target: 1, shown: 0),
            CMWheel(hue: .blue, count: false, target: 2, shown: 0),
        ]
        return CMStage(props: props, minis: minis, gems: [], wheels: wheels, symbols: 3)
    }

    private func runDemo() async {
        while sceneSize == .zero { try? await Task.sleep(for: .seconds(0.02)) }
        while !Task.isCancelled {
            stage = Self.demoStage()
            fx = CMFx()
            phase = .play
            demoPoint = nil; demoWheel = nil
            try? await Task.sleep(for: .seconds(0.7))
            // Spot each mini monkey, then set its wheel from memory: red one turn (circle → triangle),
            // blue two (→ square).
            for (m, turns) in [(0, 1), (1, 2)] {
                guard !Task.isCancelled else { return }
                demoPoint = CMLayout.peekHead(stage.minis[m], stage, sceneSize)
                try? await Task.sleep(for: .seconds(0.35))
                demoTap += 1
                collect(m)
                try? await Task.sleep(for: .seconds(1.25))
                demoPoint = nil
                for _ in 0..<turns {
                    guard !Task.isCancelled else { return }
                    demoWheel = m
                    try? await Task.sleep(for: .seconds(0.3))
                    demoTap += 1
                    turn(m)
                    try? await Task.sleep(for: .seconds(0.3))
                }
                demoWheel = nil
            }
            try? await Task.sleep(for: .seconds(0.8))
            // Hand over the banana.
            demoPoint = CMLayout.bananaPoint(sceneSize)
            try? await Task.sleep(for: .seconds(0.4))
            demoTap += 1
            stage.giveBanana()
            fx.givenAt = Date()
            try? await Task.sleep(for: .seconds(0.4))
            demoPoint = nil
            try? await Task.sleep(for: .seconds(1.6))
        }
    }

    private func win() {
        guard phase == .play, !isDemo else { return }
        phase = .done
        Haptics.tap(); SoundManager.shared.tap()
        onWin()
    }

    private func fail() {
        guard phase == .play, !isDemo else { return }
        phase = .done
        fx.failedAt = Date()
        SoundManager.shared.error(); Haptics.warning()
        onFail()
    }
}

// MARK: - Presentation state

/// Animation clocks: containers opening, mini monkeys found, the chest, the banana, the end.
struct CMFx {
    var openedAt: [Int: Date] = [:]
    var foundAt: [Int: Date] = [:]
    var unlockedAt: Date?
    var givenAt: Date?
    var failedAt: Date?
}

// MARK: - Art

enum CMArt {
    static let ink = Color(red: 0.16, green: 0.08, blue: 0.03)
    static let fur = Color(red: 0.98, green: 0.56, blue: 0.1)
    static let furDark = Color(red: 0.8, green: 0.38, blue: 0.04)
    static let peach = Color(red: 1.0, green: 0.84, blue: 0.64)
    static let iris = Color(red: 0.5, green: 0.32, blue: 0.88)
    static let yellow = Color(red: 1.0, green: 0.84, blue: 0.08)

    static func color(_ h: CMHue) -> Color {
        switch h {
        case .red: return Color(red: 0.92, green: 0.16, blue: 0.16)
        case .blue: return Color(red: 0.16, green: 0.42, blue: 0.95)
        case .green: return Color(red: 0.15, green: 0.7, blue: 0.24)
        case .purple: return Color(red: 0.62, green: 0.26, blue: 0.86)
        case .orange: return Color(red: 1.0, green: 0.5, blue: 0.06)
        case .yellow: return Color(red: 0.98, green: 0.8, blue: 0.0)
        case .pink: return Color(red: 0.98, green: 0.38, blue: 0.72)
        case .teal: return Color(red: 0.0, green: 0.74, blue: 0.74)
        case .crystal: return Color(red: 0.84, green: 0.95, blue: 1.0)
        }
    }

    static func disc(_ c: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }
    static func oval(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2)) }
    static func hash(_ n: Double) -> Double { let v = sin(n * 12.9898) * 43758.5453; return v - floor(v) }

    // MARK: Symbols

    /// Wheel and placard symbols: circle, triangle, square, star, heart, diamond.
    static func glyph(_ i: Int, in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY), s = min(r.width, r.height) / 2
        var p = Path()
        switch i % 6 {
        case 0:
            p.addEllipse(in: CGRect(x: c.x - s * 0.82, y: c.y - s * 0.82, width: s * 1.64, height: s * 1.64))
        case 1:
            p.move(to: CGPoint(x: c.x, y: c.y - s * 0.92))
            p.addLine(to: CGPoint(x: c.x + s * 0.92, y: c.y + s * 0.74))
            p.addLine(to: CGPoint(x: c.x - s * 0.92, y: c.y + s * 0.74))
            p.closeSubpath()
        case 2:
            p.addRoundedRect(in: CGRect(x: c.x - s * 0.74, y: c.y - s * 0.74, width: s * 1.48, height: s * 1.48), cornerSize: CGSize(width: s * 0.12, height: s * 0.12))
        case 3:
            for k in 0..<10 {
                let a = Double(k) * .pi / 5 - .pi / 2
                let rr = k % 2 == 0 ? s * 0.98 : s * 0.42
                let q = CGPoint(x: c.x + CGFloat(cos(a)) * rr, y: c.y + 0.06 * s + CGFloat(sin(a)) * rr)
                if k == 0 { p.move(to: q) } else { p.addLine(to: q) }
            }
            p.closeSubpath()
        case 4:
            p.move(to: CGPoint(x: c.x, y: c.y + s * 0.86))
            p.addCurve(to: CGPoint(x: c.x - s * 0.9, y: c.y - s * 0.28), control1: CGPoint(x: c.x - s * 0.5, y: c.y + s * 0.48), control2: CGPoint(x: c.x - s * 0.92, y: c.y + s * 0.1))
            p.addArc(center: CGPoint(x: c.x - s * 0.45, y: c.y - s * 0.32), radius: s * 0.45, startAngle: .degrees(175), endAngle: .degrees(355), clockwise: false)
            p.addArc(center: CGPoint(x: c.x + s * 0.45, y: c.y - s * 0.32), radius: s * 0.45, startAngle: .degrees(185), endAngle: .degrees(5), clockwise: false)
            p.addCurve(to: CGPoint(x: c.x, y: c.y + s * 0.86), control1: CGPoint(x: c.x + s * 0.92, y: c.y + s * 0.1), control2: CGPoint(x: c.x + s * 0.5, y: c.y + s * 0.48))
            p.closeSubpath()
        default:
            p.move(to: CGPoint(x: c.x, y: c.y - s * 0.96))
            p.addLine(to: CGPoint(x: c.x + s * 0.7, y: c.y))
            p.addLine(to: CGPoint(x: c.x, y: c.y + s * 0.96))
            p.addLine(to: CGPoint(x: c.x - s * 0.7, y: c.y))
            p.closeSubpath()
        }
        return p
    }

    /// Dice pips for 1…6 in a square.
    static func pips(_ n: Int, in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY), s = min(r.width, r.height) / 2
        let d = s * 0.56, pr = s * 0.2
        let layout: [[(CGFloat, CGFloat)]] = [
            [(0, 0)], [(-1, -1), (1, 1)], [(-1, -1), (0, 0), (1, 1)], [(-1, -1), (1, -1), (-1, 1), (1, 1)],
            [(-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)], [(-1, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (1, 1)],
        ]
        var p = Path()
        for (x, y) in layout[max(0, min(5, n - 1))] {
            p.addEllipse(in: CGRect(x: c.x + x * d - pr, y: c.y + y * d - pr, width: pr * 2, height: pr * 2))
        }
        return p
    }

    /// A placard: a cream card with a coloured rim and the symbol painted in that colour.
    static func placard(_ g: GraphicsContext, glyph: Int, hue: CMHue, center c: CGPoint, size s: CGFloat) {
        let r = CGRect(x: c.x - s / 2, y: c.y - s / 2, width: s, height: s)
        g.fill(Path(roundedRect: r.offsetBy(dx: s * 0.05, dy: s * 0.07), cornerRadius: s * 0.16), with: .color(.black.opacity(0.3)))
        g.fill(Path(roundedRect: r, cornerRadius: s * 0.16), with: .color(Color(red: 1, green: 0.97, blue: 0.86)))
        g.stroke(Path(roundedRect: r.insetBy(dx: s * 0.06, dy: s * 0.06), cornerRadius: s * 0.12), with: .color(color(hue)), lineWidth: max(1.5, s * 0.1))
        let gp = CMArt.glyph(glyph, in: r.insetBy(dx: s * 0.24, dy: s * 0.24))
        g.fill(gp, with: .color(color(hue)))
        g.stroke(gp, with: .color(ink.opacity(0.8)), lineWidth: max(0.8, s * 0.035))
        g.stroke(Path(roundedRect: r, cornerRadius: s * 0.16), with: .color(ink), lineWidth: max(1, s * 0.05))
    }

    /// A cut gem (wider than tall) with a bright crown facet and a glint.
    static func gem(_ g: GraphicsContext, hue: CMHue, center c: CGPoint, size s: CGFloat) {
        let base = color(hue)
        let top = c.y - s * 0.32, mid = c.y - s * 0.05, bot = c.y + s * 0.42
        var body = Path()
        body.move(to: CGPoint(x: c.x - s * 0.3, y: top))
        body.addLine(to: CGPoint(x: c.x + s * 0.3, y: top))
        body.addLine(to: CGPoint(x: c.x + s * 0.5, y: mid))
        body.addLine(to: CGPoint(x: c.x, y: bot))
        body.addLine(to: CGPoint(x: c.x - s * 0.5, y: mid))
        body.closeSubpath()
        g.fill(oval(CGPoint(x: c.x, y: bot - s * 0.02), s * 0.36, s * 0.08), with: .color(.black.opacity(0.25)))
        g.fill(body, with: .linearGradient(Gradient(colors: [base.lit(0.35), base, base.shade(0.35)]),
                                           startPoint: CGPoint(x: c.x, y: top), endPoint: CGPoint(x: c.x, y: bot)))
        var crown = Path()
        crown.move(to: CGPoint(x: c.x - s * 0.3, y: top))
        crown.addLine(to: CGPoint(x: c.x + s * 0.3, y: top))
        crown.addLine(to: CGPoint(x: c.x + s * 0.5, y: mid))
        crown.addLine(to: CGPoint(x: c.x - s * 0.5, y: mid))
        crown.closeSubpath()
        g.fill(crown, with: .color(base.lit(0.45)))
        var facets = Path()
        facets.move(to: CGPoint(x: c.x - s * 0.15, y: mid)); facets.addLine(to: CGPoint(x: c.x, y: bot))
        facets.move(to: CGPoint(x: c.x + s * 0.15, y: mid)); facets.addLine(to: CGPoint(x: c.x, y: bot))
        g.stroke(facets, with: .color(base.shade(0.45).opacity(0.7)), lineWidth: 0.8)
        g.stroke(body, with: .color(ink), lineWidth: max(1, s * 0.07))
        g.fill(disc(CGPoint(x: c.x - s * 0.14, y: top + s * 0.1), s * 0.07), with: .color(.white.opacity(0.95)))
    }

    // MARK: Props

    /// A prop standing with its base centre at the bottom middle of `r`.
    static func prop(_ g: GraphicsContext, _ p: CMProp, rect r: CGRect, theme: Int, night: Bool, openAge: Double) {
        let lw = max(1.2, r.height * 0.035)
        g.fill(oval(CGPoint(x: r.midX, y: r.maxY - lw), r.width * 0.5, r.height * 0.08), with: .color(.black.opacity(0.28)))
        switch p.kind {
        case .barrel: barrel(g, r, lw: lw, open: p.open, age: openAge)
        case .pot: pot(g, r, lw: lw, open: p.open, age: openAge)
        case .crate: crate(g, r, lw: lw, open: p.open, age: openAge)
        case .rock: rock(g, r, lw: lw, theme: theme)
        case .bush: bush(g, r, lw: lw, theme: theme, night: night)
        case .stump: stump(g, r, lw: lw)
        case .sack: sack(g, r, lw: lw)
        case .coral: coral(g, r, lw: lw)
        }
    }

    /// How far a lid has come off, 0…1, with a little overshoot.
    static func lift(_ age: Double) -> CGFloat {
        guard age < 0.35 else { return 1 }
        let k = age / 0.35
        return CGFloat(1 - pow(1 - k, 3) + 0.15 * sin(k * .pi))
    }

    static func barrel(_ g: GraphicsContext, _ r: CGRect, lw: CGFloat, open: Bool, age: Double) {
        let wood = Gradient(colors: [Color(red: 0.55, green: 0.33, blue: 0.15), Color(red: 0.78, green: 0.52, blue: 0.27), Color(red: 0.5, green: 0.3, blue: 0.13)])
        let topY = r.minY + r.height * 0.1
        var body = Path()
        body.move(to: CGPoint(x: r.minX + r.width * 0.1, y: topY))
        body.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.1, y: r.maxY - r.height * 0.06), control: CGPoint(x: r.minX - r.width * 0.08, y: r.midY))
        body.addLine(to: CGPoint(x: r.maxX - r.width * 0.1, y: r.maxY - r.height * 0.06))
        body.addQuadCurve(to: CGPoint(x: r.maxX - r.width * 0.1, y: topY), control: CGPoint(x: r.maxX + r.width * 0.08, y: r.midY))
        body.closeSubpath()
        g.fill(body, with: .linearGradient(wood, startPoint: CGPoint(x: r.minX, y: 0), endPoint: CGPoint(x: r.maxX, y: 0)))
        var staves = Path()
        for k in 1...3 {
            let x = r.minX + r.width * CGFloat(k) / 4
            staves.move(to: CGPoint(x: x, y: topY)); staves.addQuadCurve(to: CGPoint(x: x, y: r.maxY - r.height * 0.06), control: CGPoint(x: x + (x - r.midX) * 0.25, y: r.midY))
        }
        g.stroke(staves, with: .color(ink.opacity(0.35)), lineWidth: 1)
        for f in [0.28, 0.72] as [CGFloat] {
            let y = r.minY + r.height * f
            var hoop = Path()
            hoop.move(to: CGPoint(x: r.minX + r.width * 0.02, y: y)); hoop.addQuadCurve(to: CGPoint(x: r.maxX - r.width * 0.02, y: y), control: CGPoint(x: r.midX, y: y + r.height * 0.05))
            g.stroke(hoop, with: .color(Color(white: 0.25)), lineWidth: r.height * 0.07)
            g.stroke(hoop, with: .color(Color(white: 0.5)), lineWidth: r.height * 0.02)
        }
        g.stroke(body, with: .color(ink), lineWidth: lw)
        let top = CGPoint(x: r.midX, y: topY)
        if open {
            g.fill(oval(top, r.width * 0.4, r.height * 0.07), with: .color(Color(red: 0.12, green: 0.06, blue: 0.02)))
            g.stroke(oval(top, r.width * 0.4, r.height * 0.07), with: .color(ink), lineWidth: lw)
            // The lid, tipped off and leaning on the side.
            let k = lift(age)
            var lid = g
            lid.translateBy(x: top.x + r.width * 0.5 * k, y: top.y - r.height * 0.25 * k)
            lid.rotate(by: .degrees(Double(70 * k)))
            lid.fill(oval(.zero, r.width * 0.4, r.height * 0.08), with: .color(Color(red: 0.72, green: 0.48, blue: 0.24)))
            lid.stroke(oval(.zero, r.width * 0.4, r.height * 0.08), with: .color(ink), lineWidth: lw)
        } else {
            g.fill(oval(top, r.width * 0.4, r.height * 0.07), with: .color(Color(red: 0.72, green: 0.48, blue: 0.24)))
            var rings = Path()
            rings.addEllipse(in: CGRect(x: top.x - r.width * 0.26, y: top.y - r.height * 0.04, width: r.width * 0.52, height: r.height * 0.08))
            g.stroke(rings, with: .color(ink.opacity(0.35)), lineWidth: 1)
            g.stroke(oval(top, r.width * 0.4, r.height * 0.07), with: .color(ink), lineWidth: lw)
        }
    }

    static func pot(_ g: GraphicsContext, _ r: CGRect, lw: CGFloat, open: Bool, age: Double) {
        let clay = Gradient(colors: [Color(red: 0.7, green: 0.3, blue: 0.14), Color(red: 0.9, green: 0.5, blue: 0.26), Color(red: 0.62, green: 0.25, blue: 0.1)])
        let neckY = r.minY + r.height * 0.2
        var body = Path()
        body.move(to: CGPoint(x: r.midX - r.width * 0.2, y: neckY))
        body.addCurve(to: CGPoint(x: r.midX - r.width * 0.2, y: r.maxY - r.height * 0.02), control1: CGPoint(x: r.minX - r.width * 0.1, y: r.minY + r.height * 0.4), control2: CGPoint(x: r.minX, y: r.maxY - r.height * 0.05))
        body.addLine(to: CGPoint(x: r.midX + r.width * 0.2, y: r.maxY - r.height * 0.02))
        body.addCurve(to: CGPoint(x: r.midX + r.width * 0.2, y: neckY), control1: CGPoint(x: r.maxX, y: r.maxY - r.height * 0.05), control2: CGPoint(x: r.maxX + r.width * 0.1, y: r.minY + r.height * 0.4))
        body.closeSubpath()
        g.fill(body, with: .linearGradient(clay, startPoint: CGPoint(x: r.minX, y: 0), endPoint: CGPoint(x: r.maxX, y: 0)))
        // A painted band of zigzags.
        var band = Path()
        let by = r.minY + r.height * 0.55
        let n = 6
        for k in 0...n {
            let x = r.minX + r.width * (0.12 + 0.76 * CGFloat(k) / CGFloat(n))
            let y = by + (k % 2 == 0 ? -r.height * 0.04 : r.height * 0.04)
            if k == 0 { band.move(to: CGPoint(x: x, y: y)) } else { band.addLine(to: CGPoint(x: x, y: y)) }
        }
        g.stroke(band, with: .color(Color(red: 0.98, green: 0.88, blue: 0.62).opacity(0.85)), lineWidth: max(1, r.height * 0.03))
        g.stroke(body, with: .color(ink), lineWidth: lw)
        let rim = CGRect(x: r.midX - r.width * 0.27, y: neckY - r.height * 0.07, width: r.width * 0.54, height: r.height * 0.1)
        g.fill(Path(roundedRect: rim, cornerRadius: rim.height * 0.4), with: .color(Color(red: 0.8, green: 0.4, blue: 0.2)))
        g.stroke(Path(roundedRect: rim, cornerRadius: rim.height * 0.4), with: .color(ink), lineWidth: lw)
        if open {
            g.fill(oval(CGPoint(x: rim.midX, y: rim.minY + 1), rim.width * 0.4, rim.height * 0.35), with: .color(Color(red: 0.15, green: 0.05, blue: 0.02)))
            let k = lift(age)
            var lid = g
            lid.translateBy(x: rim.midX - r.width * 0.55 * k, y: rim.minY - r.height * 0.06 - r.height * 0.2 * sin(.pi * Double(min(1, k))))
            lid.rotate(by: .degrees(Double(-55 * k)))
            potLid(lid, w: rim.width, lw: lw)
        } else {
            var lid = g
            lid.translateBy(x: rim.midX, y: rim.minY)
            potLid(lid, w: rim.width, lw: lw)
        }
    }

    static func potLid(_ g: GraphicsContext, w: CGFloat, lw: CGFloat) {
        var dome = Path()
        dome.move(to: CGPoint(x: -w * 0.48, y: 0))
        dome.addQuadCurve(to: CGPoint(x: w * 0.48, y: 0), control: CGPoint(x: 0, y: -w * 0.42))
        dome.closeSubpath()
        g.fill(dome, with: .color(Color(red: 0.84, green: 0.45, blue: 0.22)))
        g.stroke(dome, with: .color(ink), lineWidth: lw)
        g.fill(disc(CGPoint(x: 0, y: -w * 0.24), w * 0.09), with: .color(Color(red: 0.6, green: 0.26, blue: 0.1)))
        g.stroke(disc(CGPoint(x: 0, y: -w * 0.24), w * 0.09), with: .color(ink), lineWidth: lw * 0.8)
    }

    static func crate(_ g: GraphicsContext, _ r: CGRect, lw: CGFloat, open: Bool, age: Double) {
        let front = CGRect(x: r.minX, y: r.minY + r.height * 0.18, width: r.width, height: r.height * 0.82)
        let topH = r.height * 0.18
        let plank = Color(red: 0.86, green: 0.64, blue: 0.36), dark = Color(red: 0.6, green: 0.4, blue: 0.18)
        g.fill(Path(front), with: .linearGradient(Gradient(colors: [plank, dark]), startPoint: CGPoint(x: 0, y: front.minY), endPoint: CGPoint(x: 0, y: front.maxY)))
        var boards = Path()
        for k in 1...2 {
            let y = front.minY + front.height * CGFloat(k) / 3
            boards.move(to: CGPoint(x: front.minX, y: y)); boards.addLine(to: CGPoint(x: front.maxX, y: y))
        }
        g.stroke(boards, with: .color(ink.opacity(0.4)), lineWidth: 1)
        var brace = Path()
        brace.move(to: CGPoint(x: front.minX + lw, y: front.minY + lw)); brace.addLine(to: CGPoint(x: front.maxX - lw, y: front.maxY - lw))
        brace.move(to: CGPoint(x: front.maxX - lw, y: front.minY + lw)); brace.addLine(to: CGPoint(x: front.minX + lw, y: front.maxY - lw))
        g.stroke(brace, with: .color(dark.shade(0.15)), lineWidth: r.width * 0.09)
        g.stroke(brace, with: .color(plank.lit(0.1)), lineWidth: r.width * 0.05)
        g.stroke(Path(front), with: .color(ink), lineWidth: lw)
        // The top face in a little perspective.
        var topFace = Path()
        topFace.move(to: CGPoint(x: front.minX, y: front.minY))
        topFace.addLine(to: CGPoint(x: front.minX + r.width * 0.12, y: front.minY - topH))
        topFace.addLine(to: CGPoint(x: front.maxX - r.width * 0.12, y: front.minY - topH))
        topFace.addLine(to: CGPoint(x: front.maxX, y: front.minY))
        topFace.closeSubpath()
        if open {
            g.fill(topFace, with: .color(Color(red: 0.16, green: 0.08, blue: 0.03)))
            g.stroke(topFace, with: .color(ink), lineWidth: lw)
            // The lid swung up and back on its hinge.
            let k = lift(age)
            var lid = Path()
            let hingeY = front.minY - topH
            lid.move(to: CGPoint(x: front.minX + r.width * 0.12, y: hingeY))
            lid.addLine(to: CGPoint(x: front.maxX - r.width * 0.12, y: hingeY))
            lid.addLine(to: CGPoint(x: front.maxX - r.width * 0.04, y: hingeY - r.height * 0.42 * k))
            lid.addLine(to: CGPoint(x: front.minX + r.width * 0.04, y: hingeY - r.height * 0.42 * k))
            lid.closeSubpath()
            g.fill(lid, with: .color(plank.shade(0.1)))
            g.stroke(lid, with: .color(ink), lineWidth: lw)
        } else {
            g.fill(topFace, with: .color(plank.lit(0.15)))
            var seams = Path()
            seams.move(to: CGPoint(x: r.midX, y: front.minY)); seams.addLine(to: CGPoint(x: r.midX, y: front.minY - topH))
            g.stroke(seams, with: .color(ink.opacity(0.4)), lineWidth: 1)
            g.stroke(topFace, with: .color(ink), lineWidth: lw)
        }
    }

    static func rock(_ g: GraphicsContext, _ r: CGRect, lw: CGFloat, theme: Int) {
        let base = theme == 1 ? Color(red: 0.82, green: 0.68, blue: 0.42) : (theme == 3 ? Color(red: 0.5, green: 0.45, blue: 0.62) : Color(red: 0.62, green: 0.62, blue: 0.64))
        var body = Path()
        body.move(to: CGPoint(x: r.minX, y: r.maxY))
        body.addCurve(to: CGPoint(x: r.midX - r.width * 0.05, y: r.minY), control1: CGPoint(x: r.minX - r.width * 0.02, y: r.minY + r.height * 0.4), control2: CGPoint(x: r.minX + r.width * 0.15, y: r.minY))
        body.addCurve(to: CGPoint(x: r.maxX, y: r.maxY), control1: CGPoint(x: r.maxX - r.width * 0.1, y: r.minY - r.height * 0.05), control2: CGPoint(x: r.maxX + r.width * 0.04, y: r.minY + r.height * 0.5))
        body.closeSubpath()
        g.fill(body, with: .linearGradient(Gradient(colors: [base.lit(0.2), base, base.shade(0.35)]), startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.maxX, y: r.maxY)))
        var cracks = Path()
        cracks.move(to: CGPoint(x: r.midX + r.width * 0.1, y: r.minY + r.height * 0.2))
        cracks.addLine(to: CGPoint(x: r.midX + r.width * 0.02, y: r.minY + r.height * 0.45))
        cracks.addLine(to: CGPoint(x: r.midX + r.width * 0.12, y: r.minY + r.height * 0.6))
        g.stroke(cracks, with: .color(ink.opacity(0.4)), lineWidth: 1.2)
        g.fill(oval(CGPoint(x: r.midX - r.width * 0.18, y: r.minY + r.height * 0.28), r.width * 0.12, r.height * 0.08), with: .color(.white.opacity(0.25)))
        g.stroke(body, with: .color(ink), lineWidth: lw)
    }

    static func bush(_ g: GraphicsContext, _ r: CGRect, lw: CGFloat, theme: Int, night: Bool) {
        let leaf = night ? Color(red: 0.16, green: 0.42, blue: 0.24) : (theme == 1 ? Color(red: 0.3, green: 0.62, blue: 0.16) : Color(red: 0.25, green: 0.6, blue: 0.22))
        let blobs: [(CGFloat, CGFloat, CGFloat)] = [(0.22, 0.62, 0.26), (0.5, 0.42, 0.32), (0.78, 0.6, 0.26), (0.36, 0.72, 0.28), (0.64, 0.74, 0.28)]
        var shape = Path()
        for (bx, by, br) in blobs { shape.addEllipse(in: CGRect(x: r.minX + r.width * (bx - br * 0.7), y: r.minY + r.height * (by - br), width: r.width * br * 1.4, height: r.height * br * 2)) }
        g.fill(shape, with: .linearGradient(Gradient(colors: [leaf.lit(0.18), leaf, leaf.shade(0.3)]), startPoint: CGPoint(x: 0, y: r.minY), endPoint: CGPoint(x: 0, y: r.maxY)))
        var gloss = Path()
        for (bx, by, br) in blobs.prefix(3) { gloss.addEllipse(in: CGRect(x: r.minX + r.width * (bx - br * 0.3), y: r.minY + r.height * (by - br * 0.7), width: r.width * br * 0.5, height: r.height * br * 0.4)) }
        g.fill(gloss, with: .color(.white.opacity(0.18)))
        g.stroke(shape, with: .color(ink), lineWidth: lw)
    }

    static func stump(_ g: GraphicsContext, _ r: CGRect, lw: CGFloat) {
        let top = CGRect(x: r.minX + r.width * 0.08, y: r.minY, width: r.width * 0.84, height: r.height * 0.3)
        var bark = Path()
        bark.move(to: CGPoint(x: top.minX, y: top.midY))
        bark.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        bark.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        bark.addLine(to: CGPoint(x: top.maxX, y: top.midY))
        bark.closeSubpath()
        g.fill(bark, with: .linearGradient(Gradient(colors: [Color(red: 0.42, green: 0.26, blue: 0.13), Color(red: 0.58, green: 0.38, blue: 0.2), Color(red: 0.36, green: 0.22, blue: 0.1)]),
                                           startPoint: CGPoint(x: r.minX, y: 0), endPoint: CGPoint(x: r.maxX, y: 0)))
        var grain = Path()
        for k in 1...3 { let x = r.minX + r.width * CGFloat(k) / 4; grain.move(to: CGPoint(x: x, y: top.midY + 2)); grain.addLine(to: CGPoint(x: x + (x - r.midX) * 0.1, y: r.maxY - 2)) }
        g.stroke(grain, with: .color(ink.opacity(0.35)), lineWidth: 1)
        g.stroke(bark, with: .color(ink), lineWidth: lw)
        g.fill(Path(ellipseIn: top), with: .color(Color(red: 0.86, green: 0.68, blue: 0.42)))
        for k in 1...2 { g.stroke(Path(ellipseIn: top.insetBy(dx: top.width * 0.13 * CGFloat(k), dy: top.height * 0.13 * CGFloat(k))), with: .color(Color(red: 0.62, green: 0.44, blue: 0.24)), lineWidth: 1) }
        g.stroke(Path(ellipseIn: top), with: .color(ink), lineWidth: lw)
    }

    static func sack(_ g: GraphicsContext, _ r: CGRect, lw: CGFloat) {
        let neck = CGPoint(x: r.midX, y: r.minY + r.height * 0.18)
        var body = Path()
        body.move(to: CGPoint(x: neck.x - r.width * 0.14, y: neck.y))
        body.addCurve(to: CGPoint(x: r.midX, y: r.maxY), control1: CGPoint(x: r.minX - r.width * 0.1, y: r.minY + r.height * 0.5), control2: CGPoint(x: r.minX, y: r.maxY))
        body.addCurve(to: CGPoint(x: neck.x + r.width * 0.14, y: neck.y), control1: CGPoint(x: r.maxX, y: r.maxY), control2: CGPoint(x: r.maxX + r.width * 0.1, y: r.minY + r.height * 0.5))
        body.closeSubpath()
        let burlap = Color(red: 0.8, green: 0.66, blue: 0.42)
        g.fill(body, with: .linearGradient(Gradient(colors: [burlap.lit(0.1), burlap, burlap.shade(0.3)]), startPoint: CGPoint(x: r.minX, y: 0), endPoint: CGPoint(x: r.maxX, y: 0)))
        var weave = Path()
        for k in 1...4 { let y = r.minY + r.height * (0.3 + 0.15 * CGFloat(k)); weave.move(to: CGPoint(x: r.minX + r.width * 0.15, y: y)); weave.addQuadCurve(to: CGPoint(x: r.maxX - r.width * 0.15, y: y), control: CGPoint(x: r.midX, y: y + 3)) }
        g.stroke(weave, with: .color(ink.opacity(0.2)), lineWidth: 1)
        g.stroke(body, with: .color(ink), lineWidth: lw)
        var tuft = Path()
        tuft.move(to: CGPoint(x: neck.x - r.width * 0.14, y: neck.y))
        tuft.addLine(to: CGPoint(x: neck.x - r.width * 0.22, y: r.minY))
        tuft.addLine(to: CGPoint(x: neck.x, y: r.minY + r.height * 0.06))
        tuft.addLine(to: CGPoint(x: neck.x + r.width * 0.22, y: r.minY))
        tuft.addLine(to: CGPoint(x: neck.x + r.width * 0.14, y: neck.y))
        tuft.closeSubpath()
        g.fill(tuft, with: .color(burlap.shade(0.1)))
        g.stroke(tuft, with: .color(ink), lineWidth: lw)
        g.stroke(Path(CGRect(x: neck.x - r.width * 0.16, y: neck.y - 1.5, width: r.width * 0.32, height: 3)), with: .color(Color(red: 0.45, green: 0.25, blue: 0.1)), lineWidth: 2.5)
    }

    static func coral(_ g: GraphicsContext, _ r: CGRect, lw: CGFloat) {
        let pink = Color(red: 1.0, green: 0.45, blue: 0.55)
        var arms = Path()
        let base = CGPoint(x: r.midX, y: r.maxY)
        let tips: [(CGFloat, CGFloat)] = [(-0.42, 0.25), (-0.18, 0.02), (0.08, 0.1), (0.3, 0.0), (0.46, 0.3)]
        for (tx, ty) in tips {
            arms.move(to: base)
            arms.addQuadCurve(to: CGPoint(x: r.midX + r.width * tx, y: r.minY + r.height * ty), control: CGPoint(x: r.midX + r.width * tx * 0.3, y: r.minY + r.height * 0.6))
        }
        g.stroke(arms, with: .color(ink), style: StrokeStyle(lineWidth: r.width * 0.16 + lw * 2, lineCap: .round))
        g.stroke(arms, with: .color(pink), style: StrokeStyle(lineWidth: r.width * 0.16, lineCap: .round))
        var dots = Path()
        for (tx, ty) in tips { dots.addEllipse(in: CGRect(x: r.midX + r.width * tx - 2, y: r.minY + r.height * ty - 2, width: 4, height: 4)) }
        g.fill(dots, with: .color(.white.opacity(0.6)))
    }

    /// Junk found in a container: an old sock, a fish bone, a boot.
    static func junk(_ g: GraphicsContext, _ k: Int, at c: CGPoint, size s: CGFloat) {
        let lw = max(1, s * 0.06)
        switch k % 3 {
        case 0:
            var sock = Path()
            sock.move(to: CGPoint(x: c.x - s * 0.15, y: c.y - s * 0.5))
            sock.addLine(to: CGPoint(x: c.x + s * 0.12, y: c.y - s * 0.5))
            sock.addLine(to: CGPoint(x: c.x + s * 0.12, y: c.y + s * 0.1))
            sock.addQuadCurve(to: CGPoint(x: c.x + s * 0.45, y: c.y + s * 0.25), control: CGPoint(x: c.x + s * 0.45, y: c.y + s * 0.05))
            sock.addQuadCurve(to: CGPoint(x: c.x - s * 0.15, y: c.y + s * 0.35), control: CGPoint(x: c.x + s * 0.2, y: c.y + s * 0.5))
            sock.closeSubpath()
            g.fill(sock, with: .color(Color(white: 0.92)))
            g.fill(Path(CGRect(x: c.x - s * 0.15, y: c.y - s * 0.38, width: s * 0.27, height: s * 0.08)), with: .color(Color(red: 0.9, green: 0.2, blue: 0.2)))
            g.stroke(sock, with: .color(ink), lineWidth: lw)
        case 1:
            var bone = Path()
            bone.move(to: CGPoint(x: c.x - s * 0.45, y: c.y)); bone.addLine(to: CGPoint(x: c.x + s * 0.3, y: c.y))
            for k in 0..<4 {
                let x = c.x - s * 0.3 + CGFloat(k) * s * 0.15
                bone.move(to: CGPoint(x: x, y: c.y - s * 0.18)); bone.addLine(to: CGPoint(x: x + s * 0.04, y: c.y + s * 0.18))
            }
            g.stroke(bone, with: .color(Color(white: 0.95)), lineWidth: lw * 1.6)
            var head = Path()
            head.move(to: CGPoint(x: c.x + s * 0.28, y: c.y - s * 0.2)); head.addLine(to: CGPoint(x: c.x + s * 0.5, y: c.y)); head.addLine(to: CGPoint(x: c.x + s * 0.28, y: c.y + s * 0.2)); head.closeSubpath()
            g.fill(head, with: .color(Color(white: 0.95)))
            g.stroke(head, with: .color(ink), lineWidth: lw)
            var tail = Path()
            tail.move(to: CGPoint(x: c.x - s * 0.45, y: c.y)); tail.addLine(to: CGPoint(x: c.x - s * 0.6, y: c.y - s * 0.15)); tail.addLine(to: CGPoint(x: c.x - s * 0.6, y: c.y + s * 0.15)); tail.closeSubpath()
            g.fill(tail, with: .color(Color(white: 0.95)))
            g.stroke(tail, with: .color(ink), lineWidth: lw)
        default:
            var boot = Path()
            boot.move(to: CGPoint(x: c.x - s * 0.2, y: c.y - s * 0.45))
            boot.addLine(to: CGPoint(x: c.x + s * 0.1, y: c.y - s * 0.45))
            boot.addLine(to: CGPoint(x: c.x + s * 0.1, y: c.y + s * 0.05))
            boot.addQuadCurve(to: CGPoint(x: c.x + s * 0.5, y: c.y + s * 0.3), control: CGPoint(x: c.x + s * 0.48, y: c.y + s * 0.08))
            boot.addLine(to: CGPoint(x: c.x - s * 0.2, y: c.y + s * 0.3))
            boot.closeSubpath()
            g.fill(boot, with: .color(Color(red: 0.42, green: 0.26, blue: 0.14)))
            g.stroke(boot, with: .color(ink), lineWidth: lw)
            var hole = Path()
            hole.addEllipse(in: CGRect(x: c.x + s * 0.18, y: c.y + s * 0.12, width: s * 0.1, height: s * 0.08))
            g.fill(hole, with: .color(peach))
        }
    }

    // MARK: Monkeys

    /// A monkey head in the Monkey GO Happy style: orange fur, round ears, a peach face over big
    /// purple eyes. `mood`: 0 sad, 1 happy, 2 sobbing. Used for the big monkey and the mini ones.
    static func monkeyHead(_ g: GraphicsContext, at c: CGPoint, r: CGFloat, mood: Int, t: Double, look: CGFloat = 0) {
        let lw = max(1, r * 0.07)
        // Ears.
        for side in [-1.0, 1.0] as [CGFloat] {
            let e = CGPoint(x: c.x + side * r * 0.98, y: c.y + r * 0.05)
            g.fill(disc(e, r * 0.36), with: .color(fur))
            g.stroke(disc(e, r * 0.36), with: .color(ink), lineWidth: lw)
            g.fill(disc(CGPoint(x: e.x - side * r * 0.04, y: e.y + r * 0.02), r * 0.21), with: .color(peach))
        }
        // Head and tuft.
        var tuft = Path()
        for k in 0..<3 {
            let bx = c.x + CGFloat(k - 1) * r * 0.16
            tuft.move(to: CGPoint(x: bx - r * 0.1, y: c.y - r * 0.9))
            tuft.addQuadCurve(to: CGPoint(x: bx + CGFloat(k - 1) * r * 0.14 + r * 0.05, y: c.y - r * 1.3), control: CGPoint(x: bx - r * 0.1, y: c.y - r * 1.15))
            tuft.addQuadCurve(to: CGPoint(x: bx + r * 0.1, y: c.y - r * 0.9), control: CGPoint(x: bx + r * 0.08, y: c.y - r * 1.1))
        }
        g.fill(tuft, with: .color(furDark))
        g.stroke(tuft, with: .color(ink), lineWidth: lw * 0.8)
        g.fill(disc(c, r), with: .radialGradient(Gradient(colors: [fur.lit(0.2), fur, furDark]), center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.35), startRadius: 0, endRadius: r * 1.3))
        g.stroke(disc(c, r), with: .color(ink), lineWidth: lw)
        // The peach face: two lobes round the eyes and a muzzle.
        var face = Path()
        face.addEllipse(in: CGRect(x: c.x - r * 0.8, y: c.y - r * 0.5, width: r * 0.86, height: r * 0.86))
        face.addEllipse(in: CGRect(x: c.x - r * 0.06, y: c.y - r * 0.5, width: r * 0.86, height: r * 0.86))
        face.addEllipse(in: CGRect(x: c.x - r * 0.55, y: c.y + r * 0.08, width: r * 1.1, height: r * 0.76))
        g.fill(face, with: .color(peach))
        // Eyes.
        for side in [-1.0, 1.0] as [CGFloat] {
            let e = CGPoint(x: c.x + side * r * 0.36, y: c.y - r * 0.08)
            if mood == 1 {
                // Squeezed shut with joy.
                var happy = Path()
                happy.move(to: CGPoint(x: e.x - r * 0.22, y: e.y + r * 0.04))
                happy.addQuadCurve(to: CGPoint(x: e.x + r * 0.22, y: e.y + r * 0.04), control: CGPoint(x: e.x, y: e.y - r * 0.26))
                g.stroke(happy, with: .color(ink), style: StrokeStyle(lineWidth: lw * 1.6, lineCap: .round))
                continue
            }
            g.fill(oval(e, r * 0.27, r * 0.33), with: .color(.white))
            let ic = CGPoint(x: e.x + look * r * 0.08, y: e.y + r * 0.06)
            g.fill(oval(ic, r * 0.2, r * 0.24), with: .color(iris))
            g.fill(oval(CGPoint(x: ic.x, y: ic.y + r * 0.02), r * 0.11, r * 0.14), with: .color(Color(red: 0.12, green: 0.04, blue: 0.2)))
            g.fill(disc(CGPoint(x: ic.x - r * 0.08, y: ic.y - r * 0.09), r * 0.065), with: .color(.white))
            g.fill(disc(CGPoint(x: ic.x + r * 0.07, y: ic.y + r * 0.08), r * 0.035), with: .color(.white))
            // Sad lids droop toward the outside, with brows tilted up in the middle.
            var lid = Path()
            lid.move(to: CGPoint(x: e.x - r * 0.32, y: e.y - r * 0.36))
            lid.addLine(to: CGPoint(x: e.x + r * 0.32, y: e.y - r * 0.36))
            lid.addLine(to: CGPoint(x: e.x + side * r * 0.3, y: e.y - r * 0.06))
            lid.addLine(to: CGPoint(x: e.x - side * r * 0.3, y: e.y - r * 0.26))
            lid.closeSubpath()
            var clip = g
            clip.clip(to: oval(e, r * 0.27, r * 0.33))
            clip.fill(lid, with: .color(peach.shade(0.08)))
            g.stroke(oval(e, r * 0.27, r * 0.33), with: .color(ink), lineWidth: lw * 0.8)
            var lidLine = Path()
            lidLine.move(to: CGPoint(x: e.x - side * r * 0.28, y: e.y - r * 0.25)); lidLine.addLine(to: CGPoint(x: e.x + side * r * 0.28, y: e.y - r * 0.07))
            var lidClip = g
            lidClip.clip(to: oval(e, r * 0.3, r * 0.36))
            lidClip.stroke(lidLine, with: .color(ink), lineWidth: lw)
            var brow = Path()
            brow.move(to: CGPoint(x: e.x - side * r * 0.24, y: e.y - r * 0.5))
            brow.addLine(to: CGPoint(x: e.x + side * r * 0.2, y: e.y - r * 0.38))
            g.stroke(brow, with: .color(furDark.shade(0.3)), style: StrokeStyle(lineWidth: lw * 1.3, lineCap: .round))
        }
        // Nose.
        for side in [-1.0, 1.0] as [CGFloat] {
            g.fill(oval(CGPoint(x: c.x + side * r * 0.07, y: c.y + r * 0.3), r * 0.035, r * 0.045), with: .color(ink.opacity(0.8)))
        }
        // Mouth.
        if mood == 1 {
            var grin = Path()
            grin.move(to: CGPoint(x: c.x - r * 0.36, y: c.y + r * 0.42))
            grin.addQuadCurve(to: CGPoint(x: c.x + r * 0.36, y: c.y + r * 0.42), control: CGPoint(x: c.x, y: c.y + r * 0.46))
            grin.addQuadCurve(to: CGPoint(x: c.x - r * 0.36, y: c.y + r * 0.42), control: CGPoint(x: c.x, y: c.y + r * 1.0))
            grin.closeSubpath()
            g.fill(grin, with: .color(Color(red: 0.55, green: 0.08, blue: 0.1)))
            var clip = g
            clip.clip(to: grin)
            clip.fill(oval(CGPoint(x: c.x, y: c.y + r * 0.8), r * 0.22, r * 0.13), with: .color(Color(red: 1, green: 0.45, blue: 0.5)))
            clip.fill(Path(CGRect(x: c.x - r * 0.3, y: c.y + r * 0.42, width: r * 0.6, height: r * 0.08)), with: .color(.white))
            g.stroke(grin, with: .color(ink), lineWidth: lw)
        } else {
            var frown = Path()
            frown.move(to: CGPoint(x: c.x - r * 0.18, y: c.y + r * 0.6))
            frown.addQuadCurve(to: CGPoint(x: c.x + r * 0.18, y: c.y + r * 0.6), control: CGPoint(x: c.x, y: c.y + r * (mood == 2 ? 0.38 : 0.47)))
            g.stroke(frown, with: .color(ink), style: StrokeStyle(lineWidth: lw * 1.2, lineCap: .round))
            // Tears: one at a time when sad, streams when sobbing.
            let drops = mood == 2 ? 3 : 1
            for k in 0..<drops {
                let phase = (t * (mood == 2 ? 1.6 : 0.6) + Double(k) / Double(drops)).truncatingRemainder(dividingBy: 1)
                for side in (mood == 2 ? [-1.0, 1.0] : [1.0]) as [CGFloat] {
                    let p = CGPoint(x: c.x + side * r * 0.5, y: c.y + r * 0.2 + CGFloat(phase) * r * 0.9)
                    var drop = Path()
                    drop.move(to: CGPoint(x: p.x, y: p.y - r * 0.12))
                    drop.addQuadCurve(to: CGPoint(x: p.x, y: p.y + r * 0.06), control: CGPoint(x: p.x + r * 0.1, y: p.y))
                    drop.addQuadCurve(to: CGPoint(x: p.x, y: p.y - r * 0.12), control: CGPoint(x: p.x - r * 0.1, y: p.y))
                    var dg = g
                    dg.opacity = 1 - phase * 0.6
                    dg.fill(drop, with: .color(Color(red: 0.55, green: 0.8, blue: 1)))
                    dg.stroke(drop, with: .color(Color(red: 0.2, green: 0.4, blue: 0.8)), lineWidth: max(0.6, lw * 0.5))
                }
            }
        }
    }

    /// The big monkey, sitting with its feet at `f`. `jump` lifts it (the happy hop).
    static func bigMonkey(_ g: GraphicsContext, feet f0: CGPoint, r: CGFloat, mood: Int, t: Double, jump: CGFloat) {
        let lw = max(1.4, r * 0.06)
        let f = CGPoint(x: f0.x, y: f0.y - jump)
        g.fill(oval(CGPoint(x: f0.x, y: f0.y - r * 0.04), r * 0.95 * (1 - jump / (r * 4)), r * 0.16), with: .color(.black.opacity(0.28)))
        let headC = CGPoint(x: f.x, y: f.y - r * 2.05 + (mood == 0 ? CGFloat(sin(t * 1.8)) * r * 0.02 : 0))
        // Arms: hanging when sad, thrown up when happy.
        for side in [-1.0, 1.0] as [CGFloat] {
            var arm = Path()
            let shoulder = CGPoint(x: f.x + side * r * 0.5, y: f.y - r * 1.05)
            let hand: CGPoint
            if mood == 1 {
                hand = CGPoint(x: f.x + side * r * 1.25, y: f.y - r * 2.4 + CGFloat(sin(t * 14)) * r * 0.06)
                arm.move(to: shoulder); arm.addQuadCurve(to: hand, control: CGPoint(x: f.x + side * r * 1.2, y: f.y - r * 1.2))
            } else {
                hand = CGPoint(x: f.x + side * r * 0.95, y: f.y - r * 0.12)
                arm.move(to: shoulder); arm.addQuadCurve(to: hand, control: CGPoint(x: f.x + side * r * 1.05, y: f.y - r * 0.8))
            }
            g.stroke(arm, with: .color(ink), style: StrokeStyle(lineWidth: r * 0.24 + lw * 2, lineCap: .round))
            g.stroke(arm, with: .color(fur), style: StrokeStyle(lineWidth: r * 0.24, lineCap: .round))
            g.fill(disc(hand, r * 0.17), with: .color(peach))
            g.stroke(disc(hand, r * 0.17), with: .color(ink), lineWidth: lw)
        }
        // Body and belly.
        var body = Path()
        body.move(to: CGPoint(x: f.x - r * 0.45, y: f.y - r * 1.3))
        body.addCurve(to: CGPoint(x: f.x, y: f.y - r * 0.08), control1: CGPoint(x: f.x - r * 0.95, y: f.y - r * 0.9), control2: CGPoint(x: f.x - r * 0.8, y: f.y - r * 0.08))
        body.addCurve(to: CGPoint(x: f.x + r * 0.45, y: f.y - r * 1.3), control1: CGPoint(x: f.x + r * 0.8, y: f.y - r * 0.08), control2: CGPoint(x: f.x + r * 0.95, y: f.y - r * 0.9))
        body.closeSubpath()
        g.fill(body, with: .linearGradient(Gradient(colors: [fur, furDark]), startPoint: CGPoint(x: f.x - r * 0.6, y: f.y - r * 1.2), endPoint: CGPoint(x: f.x + r * 0.6, y: f.y)))
        g.stroke(body, with: .color(ink), lineWidth: lw)
        g.fill(oval(CGPoint(x: f.x, y: f.y - r * 0.55), r * 0.42, r * 0.4), with: .color(peach))
        // Legs folded in front, feet up.
        for side in [-1.0, 1.0] as [CGFloat] {
            let k = CGPoint(x: f.x + side * r * 0.42, y: f.y - r * 0.2)
            g.fill(oval(k, r * 0.34, r * 0.22), with: .color(fur))
            g.stroke(oval(k, r * 0.34, r * 0.22), with: .color(ink), lineWidth: lw)
            g.fill(oval(CGPoint(x: k.x + side * r * 0.14, y: k.y + r * 0.03), r * 0.16, r * 0.13), with: .color(peach))
        }
        monkeyHead(g, at: headC, r: r, mood: mood, t: t)
    }

    /// A mini monkey: a tiny copy with a little body. `placard` (glyph, hue) is held up over its head.
    static func miniMonkey(_ g: GraphicsContext, head c: CGPoint, r: CGFloat, t: Double, placard: (Int, CMHue)?, wave: Bool) {
        let lw = max(0.8, r * 0.09)
        var body = Path()
        body.addEllipse(in: CGRect(x: c.x - r * 0.62, y: c.y + r * 0.7, width: r * 1.24, height: r * 1.3))
        g.fill(body, with: .color(fur))
        g.stroke(body, with: .color(ink), lineWidth: lw)
        g.fill(oval(CGPoint(x: c.x, y: c.y + r * 1.4), r * 0.32, r * 0.36), with: .color(peach))
        if let (glyph, hue) = placard {
            for side in [-1.0, 1.0] as [CGFloat] {
                var arm = Path()
                arm.move(to: CGPoint(x: c.x + side * r * 0.5, y: c.y + r * 0.95))
                arm.addLine(to: CGPoint(x: c.x + side * r * 0.75, y: c.y - r * 1.0))
                g.stroke(arm, with: .color(ink), style: StrokeStyle(lineWidth: r * 0.3 + lw * 2, lineCap: .round))
                g.stroke(arm, with: .color(fur), style: StrokeStyle(lineWidth: r * 0.3, lineCap: .round))
            }
            monkeyHead(g, at: c, r: r, mood: 1, t: t)
            CMArt.placard(g, glyph: glyph, hue: hue, center: CGPoint(x: c.x, y: c.y - r * 1.9), size: r * 2.1)
        } else {
            if wave {
                var arm = Path()
                arm.move(to: CGPoint(x: c.x + r * 0.5, y: c.y + r * 0.95))
                arm.addLine(to: CGPoint(x: c.x + r * 1.05, y: c.y + r * 0.1 + CGFloat(sin(t * 8)) * r * 0.25))
                g.stroke(arm, with: .color(ink), style: StrokeStyle(lineWidth: r * 0.3 + lw * 2, lineCap: .round))
                g.stroke(arm, with: .color(fur), style: StrokeStyle(lineWidth: r * 0.3, lineCap: .round))
            }
            monkeyHead(g, at: c, r: r, mood: 0, t: t, look: CGFloat(sin(t * 0.9)))
        }
    }

    /// The wicker basket the mini monkeys hop into.
    static func basket(_ g: GraphicsContext, _ r: CGRect, heads: Int, t: Double) {
        let lw = max(1.2, r.height * 0.04)
        let rimY = r.minY + r.height * 0.2
        let mr = r.height * 0.22
        for k in 0..<heads {
            let x = r.minX + r.width * (0.24 + 0.26 * CGFloat(k % 3)), y = rimY - mr * 0.25 - CGFloat(k / 3) * mr * 0.5
            monkeyHead(g, at: CGPoint(x: x, y: y), r: mr, mood: 1, t: t + Double(k))
        }
        var body = Path()
        body.move(to: CGPoint(x: r.minX, y: rimY))
        body.addLine(to: CGPoint(x: r.maxX, y: rimY))
        body.addLine(to: CGPoint(x: r.maxX - r.width * 0.1, y: r.maxY))
        body.addLine(to: CGPoint(x: r.minX + r.width * 0.1, y: r.maxY))
        body.closeSubpath()
        let straw = Color(red: 0.86, green: 0.62, blue: 0.3)
        g.fill(body, with: .linearGradient(Gradient(colors: [straw, straw.shade(0.35)]), startPoint: CGPoint(x: 0, y: rimY), endPoint: CGPoint(x: 0, y: r.maxY)))
        var clip = g
        clip.clip(to: body)
        var weave = Path()
        var x = r.minX - r.height
        while x < r.maxX + r.height {
            weave.move(to: CGPoint(x: x, y: rimY)); weave.addLine(to: CGPoint(x: x + r.height, y: r.maxY))
            weave.move(to: CGPoint(x: x + r.height, y: rimY)); weave.addLine(to: CGPoint(x: x, y: r.maxY))
            x += r.height * 0.24
        }
        clip.stroke(weave, with: .color(straw.shade(0.45).opacity(0.6)), lineWidth: 1)
        g.stroke(body, with: .color(ink), lineWidth: lw)
        let rim = CGRect(x: r.minX - r.width * 0.03, y: rimY - r.height * 0.07, width: r.width * 1.06, height: r.height * 0.14)
        g.fill(Path(roundedRect: rim, cornerRadius: rim.height / 2), with: .color(straw.lit(0.1)))
        g.stroke(Path(roundedRect: rim, cornerRadius: rim.height / 2), with: .color(ink), lineWidth: lw)
    }

    /// The chest: closed with a big brass padlock, or open with light pouring out.
    static func chest(_ g: GraphicsContext, _ r: CGRect, openAge: Double?, t: Double) {
        let lw = max(1.4, r.height * 0.04)
        let wood = Color(red: 0.62, green: 0.34, blue: 0.14), band = Color(red: 0.95, green: 0.72, blue: 0.2)
        let lidH = r.height * 0.36
        let body = CGRect(x: r.minX, y: r.minY + lidH, width: r.width, height: r.height - lidH)
        g.fill(oval(CGPoint(x: r.midX, y: r.maxY - 1), r.width * 0.55, r.height * 0.08), with: .color(.black.opacity(0.3)))
        let k = openAge.map { CGFloat(min(1, $0 / 0.3)) } ?? 0
        if let age = openAge {
            // Light from inside.
            let glow = CGPoint(x: r.midX, y: body.minY)
            g.fill(disc(glow, r.width * (0.7 + 0.05 * CGFloat(sin(t * 5)))), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.6).opacity(0.8 * Double(k)), .clear]),
                                                                                           center: glow, startRadius: 0, endRadius: r.width * 0.75))
            // The lid, thrown back.
            var lid = Path()
            lid.move(to: CGPoint(x: body.minX, y: body.minY))
            lid.addLine(to: CGPoint(x: body.maxX, y: body.minY))
            lid.addLine(to: CGPoint(x: body.maxX - r.width * 0.06, y: body.minY - lidH * 1.4 * k))
            lid.addQuadCurve(to: CGPoint(x: body.minX + r.width * 0.06, y: body.minY - lidH * 1.4 * k), control: CGPoint(x: r.midX, y: body.minY - lidH * 1.9 * k))
            lid.closeSubpath()
            g.fill(lid, with: .color(Color(red: 0.42, green: 0.08, blue: 0.1)))
            g.stroke(lid, with: .color(ink), lineWidth: lw)
            g.fill(Path(CGRect(x: body.minX + lw, y: body.minY - lw, width: body.width - lw * 2, height: lw * 2.5)), with: .color(Color(red: 0.12, green: 0.05, blue: 0.02)))
            _ = age
        }
        g.fill(Path(roundedRect: body, cornerRadius: r.width * 0.04), with: .linearGradient(Gradient(colors: [wood.lit(0.12), wood.shade(0.25)]), startPoint: CGPoint(x: 0, y: body.minY), endPoint: CGPoint(x: 0, y: body.maxY)))
        for fx in [0.08, 0.92] as [CGFloat] {
            g.fill(Path(CGRect(x: r.minX + r.width * fx - r.width * 0.05, y: body.minY, width: r.width * 0.1, height: body.height)), with: .color(band))
        }
        g.stroke(Path(roundedRect: body, cornerRadius: r.width * 0.04), with: .color(ink), lineWidth: lw)
        if openAge == nil {
            var lid = Path()
            lid.move(to: CGPoint(x: r.minX, y: body.minY))
            lid.addLine(to: CGPoint(x: r.minX, y: r.minY + lidH * 0.45))
            lid.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + lidH * 0.45), control: CGPoint(x: r.midX, y: r.minY - lidH * 0.35))
            lid.addLine(to: CGPoint(x: r.maxX, y: body.minY))
            lid.closeSubpath()
            g.fill(lid, with: .linearGradient(Gradient(colors: [wood.lit(0.2), wood]), startPoint: CGPoint(x: 0, y: r.minY), endPoint: CGPoint(x: 0, y: body.minY)))
            var straps = g
            straps.clip(to: lid)
            for fx in [0.08, 0.92] as [CGFloat] {
                straps.fill(Path(CGRect(x: r.minX + r.width * fx - r.width * 0.05, y: r.minY - lidH, width: r.width * 0.1, height: lidH * 2)), with: .color(band))
            }
            g.stroke(lid, with: .color(ink), lineWidth: lw)
            // Padlock.
            let lc = CGPoint(x: r.midX, y: body.minY + body.height * 0.12)
            let ls = r.width * 0.26
            var shackle = Path()
            shackle.addArc(center: CGPoint(x: lc.x, y: lc.y), radius: ls * 0.32, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            g.stroke(shackle, with: .color(ink), lineWidth: ls * 0.2 + lw)
            g.stroke(shackle, with: .color(Color(white: 0.75)), lineWidth: ls * 0.2)
            let lock = CGRect(x: lc.x - ls * 0.5, y: lc.y, width: ls, height: ls * 0.8)
            g.fill(Path(roundedRect: lock, cornerRadius: ls * 0.15), with: .linearGradient(Gradient(colors: [band.lit(0.3), band.shade(0.2)]), startPoint: CGPoint(x: 0, y: lock.minY), endPoint: CGPoint(x: 0, y: lock.maxY)))
            g.stroke(Path(roundedRect: lock, cornerRadius: ls * 0.15), with: .color(ink), lineWidth: lw)
            g.fill(disc(CGPoint(x: lock.midX, y: lock.midY - ls * 0.05), ls * 0.1), with: .color(ink))
            g.fill(Path(CGRect(x: lock.midX - ls * 0.04, y: lock.midY - ls * 0.02, width: ls * 0.08, height: ls * 0.22)), with: .color(ink))
        }
    }

    /// A banana: crescent, stalk and tip, about `w` long.
    static func banana(_ g: GraphicsContext, at c: CGPoint, w: CGFloat, angle: Double = -0.3) {
        var gg = g
        gg.translateBy(x: c.x, y: c.y)
        gg.rotate(by: .radians(angle))
        let h = w * 0.42
        var ban = Path()
        ban.move(to: CGPoint(x: -w * 0.5, y: -h * 0.35))
        ban.addQuadCurve(to: CGPoint(x: w * 0.5, y: -h * 0.45), control: CGPoint(x: 0, y: h * 1.15))
        ban.addQuadCurve(to: CGPoint(x: -w * 0.5, y: -h * 0.35), control: CGPoint(x: 0, y: h * 0.1))
        ban.closeSubpath()
        gg.fill(ban, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.96, blue: 0.5), yellow, Color(red: 0.9, green: 0.66, blue: 0.08)]),
                                           startPoint: CGPoint(x: 0, y: -h * 0.3), endPoint: CGPoint(x: 0, y: h * 0.6)))
        gg.stroke(ban, with: .color(ink), lineWidth: max(1.2, w * 0.04))
        gg.fill(Path(roundedRect: CGRect(x: w * 0.44, y: -h * 0.62, width: w * 0.12, height: h * 0.26), cornerRadius: w * 0.02), with: .color(Color(red: 0.42, green: 0.28, blue: 0.08)))
        gg.fill(disc(CGPoint(x: -w * 0.5, y: -h * 0.35), w * 0.035), with: .color(Color(red: 0.3, green: 0.2, blue: 0.05)))
    }

    // MARK: The live scene

    static func scene(_ ctx: GraphicsContext, size s: CGSize, stage: CMStage, fx: CMFx, now: Date, theme: Int, night: Bool) {
        let t = now.timeIntervalSinceReferenceDate
        guard !stage.wheels.isEmpty else { return }
        let u = CMLayout.unit(s)
        // Props back to front, each with any mini monkey peeking out from behind it first.
        let order = stage.props.indices.sorted { stage.props[$0].y < stage.props[$1].y }
        for i in order {
            let p = stage.props[i]
            let rect = CMLayout.propRect(p, s)
            for (m, mini) in stage.minis.enumerated() where mini.host == i && !mini.inside && !mini.found {
                let h = CMLayout.peekHead(mini, stage, s)
                miniMonkey(ctx, head: h, r: CMLayout.miniR(s, scale: p.scale), t: t + Double(m), placard: nil, wave: mini.side != 0)
            }
            let age = fx.openedAt[i].map { now.timeIntervalSince($0) } ?? 99
            prop(ctx, p, rect: rect, theme: theme, night: night, openAge: age)
            if p.open {
                let lootAt = CGPoint(x: rect.midX, y: rect.minY - u * 0.12 * CGFloat(p.scale))
                switch p.loot {
                case .junk(let k): junk(ctx, k, at: lootAt, size: u * 0.42 * CGFloat(p.scale))
                default: break
                }
            }
        }
        // Gems: loose ones, and the ones in containers once those are open.
        for gm in stage.gems {
            var c = CGPoint(x: CGFloat(gm.x) * s.width, y: CGFloat(gm.y) * s.height)
            if let host = gm.host {
                guard stage.props[host].open else { continue }
                let r = CMLayout.propRect(stage.props[host], s)
                let age = fx.openedAt[host].map { now.timeIntervalSince($0) } ?? 99
                c = CGPoint(x: c.x, y: r.minY - u * 0.14 - u * 0.25 * CGFloat(max(0, 1 - age / 0.3)))
            }
            gem(ctx, hue: gm.hue, center: c, size: u * 0.3)
        }
        // The basket with the mini monkeys already in it.
        let landed = stage.minis.indices.filter { m in stage.minis[m].found && (fx.foundAt[m].map { now.timeIntervalSince($0) > 1.5 } ?? true) }.count
        basket(ctx, CMLayout.basketRect(s), heads: landed, t: t)
        // The chest, and the banana once it's open.
        let chestAge = fx.unlockedAt.map { now.timeIntervalSince($0) }
        chest(ctx, CMLayout.chestRect(s), openAge: stage.unlocked ? (chestAge ?? 99) : nil, t: t)
        let mr = CMLayout.monkeyR(s)
        let feet = CMLayout.monkeyFeet(s)
        if stage.unlocked {
            let rise = CGFloat(min(1, (chestAge ?? 99) / 0.45))
            let b0 = CMLayout.bananaPoint(s)
            let c = CMLayout.chestRect(s)
            if let given = fx.givenAt {
                let k = CGFloat(min(1, now.timeIntervalSince(given) / 0.4))
                if k < 1 {
                    let mouth = CGPoint(x: feet.x, y: feet.y - mr * 1.7)
                    let p = CGPoint(x: b0.x + (mouth.x - b0.x) * k, y: b0.y + (mouth.y - b0.y) * k - sin(.pi * k) * mr * 0.8)
                    banana(ctx, at: p, w: mr * 1.1 * (1 - k * 0.4), angle: -0.3 - Double(k) * 3)
                }
            } else {
                let p = CGPoint(x: b0.x, y: c.minY + (b0.y - c.minY) * rise + CGFloat(sin(t * 3)) * mr * 0.06)
                ctx.fill(disc(p, mr * 0.75), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.5).opacity(0.55), .clear]), center: p, startRadius: 0, endRadius: mr * 0.75))
                banana(ctx, at: p, w: mr * 1.1)
            }
        }
        // The big monkey: sad, jumping for joy once fed, sobbing if time ran out.
        let happyAge = fx.givenAt.map { now.timeIntervalSince($0) - 0.4 } ?? -1
        let mood = happyAge >= 0 ? 1 : (fx.failedAt != nil ? 2 : 0)
        let jump = mood == 1 ? CGFloat(abs(sin(happyAge * 7))) * mr * 0.55 : 0
        bigMonkey(ctx, feet: feet, r: mr, mood: mood, t: t, jump: jump)
        if mood == 1 {
            for k in 0..<6 {
                let a = Double(k) / 6 * 2 * .pi + happyAge * 2
                let d = mr * (1.6 + 0.4 * CGFloat(min(1, happyAge * 2)))
                let p = CGPoint(x: feet.x + CGFloat(cos(a)) * d, y: feet.y - mr * 2 - jump + CGFloat(sin(a)) * d * 0.7)
                var star = ctx
                star.opacity = max(0, 1 - happyAge / 1.4)
                star.fill(glyph(3, in: CGRect(x: p.x - mr * 0.16, y: p.y - mr * 0.16, width: mr * 0.32, height: mr * 0.32)), with: .color(yellow))
            }
        }
        // Mini monkeys just found: pop up holding the placard, then hop into the basket. The placard is
        // only shown this once, so the player has to remember it.
        let basketTop = CMLayout.basketRect(s)
        for (m, mini) in stage.minis.enumerated() where mini.found {
            guard let at = fx.foundAt[m] else { continue }
            let age = now.timeIntervalSince(at)
            guard age < 1.5 else { continue }
            let host = stage.props[mini.host]
            let hr = CMLayout.miniR(s, scale: host.scale)
            let start: CGPoint
            if mini.inside {
                let r = CMLayout.propRect(host, s)
                start = CGPoint(x: r.midX, y: r.minY - hr * 1.2)
            } else {
                start = CMLayout.peekHead(mini, stage, s)
            }
            let pop = CGFloat(min(1, age / 0.25))
            let shown = CGPoint(x: start.x, y: start.y - hr * 1.0 * pop)
            if age < 1.05 {
                miniMonkey(ctx, head: shown, r: hr * (1 + 0.3 * pop), t: t, placard: (mini.glyph, mini.hue), wave: false)
            } else {
                let k = CGFloat((age - 1.05) / 0.45)
                let end = CGPoint(x: basketTop.midX, y: basketTop.minY)
                let p = CGPoint(x: shown.x + (end.x - shown.x) * k, y: shown.y + (end.y - shown.y) * k - sin(.pi * k) * s.height * 0.12)
                miniMonkey(ctx, head: p, r: hr * 1.3 * (1 - 0.3 * k), t: t, placard: nil, wave: false)
            }
        }
    }
}

// MARK: - Static pieces

/// The painted stage behind everything: a cottage at dusk (or night), a jungle temple (or at
/// sunset), a ship's deck (or in a storm), a reef. Static for the level.
private struct CMBackdrop: View, Equatable {
    let theme: Int
    let night: Bool

    var body: some View {
        Canvas { ctx, s in
            switch theme {
            case 1: temple(ctx, s)
            case 2: deck(ctx, s)
            case 3: reef(ctx, s)
            default: cottage(ctx, s)
            }
        }
        .allowsHitTesting(false)
    }

    private var ink: Color { CMArt.ink }

    private func sky(_ ctx: GraphicsContext, _ s: CGSize, _ colors: [Color], horizon: CGFloat) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: s.width, height: horizon + 2)), with: .linearGradient(Gradient(colors: colors), startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))
    }

    private func stars(_ ctx: GraphicsContext, _ s: CGSize, below: CGFloat) {
        var dots = Path()
        for k in 0..<28 {
            let x = s.width * CGFloat(CMArt.hash(Double(k) * 3.1)), y = below * CGFloat(CMArt.hash(Double(k) * 7.3)) * 0.9
            let r: CGFloat = k % 5 == 0 ? 1.6 : 1
            dots.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
        ctx.fill(dots, with: .color(.white.opacity(0.85)))
    }

    private func cottage(_ ctx: GraphicsContext, _ s: CGSize) {
        let w = s.width, h = s.height, hz = h * 0.34
        sky(ctx, s, night ? [Color(red: 0.04, green: 0.05, blue: 0.18), Color(red: 0.12, green: 0.16, blue: 0.4), Color(red: 0.26, green: 0.3, blue: 0.55)]
                          : [Color(red: 0.36, green: 0.28, blue: 0.55), Color(red: 0.95, green: 0.5, blue: 0.32), Color(red: 1, green: 0.86, blue: 0.45)], horizon: hz)
        if night {
            stars(ctx, s, below: hz)
            let m = CGPoint(x: w * 0.8, y: h * 0.09)
            ctx.fill(CMArt.disc(m, h * 0.06), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.98, blue: 0.85).opacity(0.5), .clear]), center: m, startRadius: h * 0.03, endRadius: h * 0.09))
            ctx.fill(CMArt.disc(m, h * 0.035), with: .color(Color(red: 1, green: 0.97, blue: 0.82)))
            ctx.fill(CMArt.disc(CGPoint(x: m.x + h * 0.015, y: m.y - h * 0.008), h * 0.03), with: .color(Color(red: 0.12, green: 0.16, blue: 0.4)))
        } else {
            let sun = CGPoint(x: w * 0.74, y: hz - h * 0.04)
            ctx.fill(CMArt.disc(sun, h * 0.16), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.96, blue: 0.7), Color(red: 1, green: 0.85, blue: 0.4).opacity(0.5), .clear]), center: sun, startRadius: 0, endRadius: h * 0.16))
            var streaks = Path()
            for (fx, fy, fw) in [(0.1, 0.1, 0.3), (0.5, 0.06, 0.25), (0.62, 0.16, 0.35)] as [(CGFloat, CGFloat, CGFloat)] {
                streaks.addRoundedRect(in: CGRect(x: w * fx, y: h * fy, width: w * fw, height: h * 0.018), cornerSize: CGSize(width: h * 0.009, height: h * 0.009))
            }
            ctx.fill(streaks, with: .color(Color(red: 0.55, green: 0.35, blue: 0.6).opacity(0.5)))
        }
        // Pines along the horizon, far then near.
        for layer in 0..<2 {
            var pines = Path()
            var x: CGFloat = -10
            var k = 0
            while x < w + 20 {
                let ph = h * (layer == 0 ? 0.1 : 0.14) * CGFloat(0.7 + 0.5 * CMArt.hash(Double(k) * 1.7 + Double(layer) * 9))
                let pw = ph * 0.5
                let base = hz + (layer == 0 ? 0 : h * 0.01)
                pines.move(to: CGPoint(x: x - pw / 2, y: base))
                pines.addLine(to: CGPoint(x: x, y: base - ph))
                pines.addLine(to: CGPoint(x: x + pw / 2, y: base))
                pines.closeSubpath()
                x += pw * (layer == 0 ? 0.6 : 0.9); k += 1
            }
            let col = night ? (layer == 0 ? Color(red: 0.1, green: 0.16, blue: 0.24) : Color(red: 0.06, green: 0.12, blue: 0.14))
                            : (layer == 0 ? Color(red: 0.35, green: 0.32, blue: 0.4) : Color(red: 0.15, green: 0.3, blue: 0.2))
            ctx.fill(pines, with: .color(col))
        }
        // Ground: grass with a dirt path from the cottage down to the monkey.
        let grass = night ? [Color(red: 0.12, green: 0.26, blue: 0.2), Color(red: 0.06, green: 0.16, blue: 0.12)] : [Color(red: 0.42, green: 0.62, blue: 0.22), Color(red: 0.22, green: 0.42, blue: 0.14)]
        ctx.fill(Path(CGRect(x: 0, y: hz, width: w, height: h - hz)), with: .linearGradient(Gradient(colors: grass), startPoint: CGPoint(x: 0, y: hz), endPoint: CGPoint(x: 0, y: h)))
        var path = Path()
        path.move(to: CGPoint(x: w * 0.36, y: hz + h * 0.02))
        path.addLine(to: CGPoint(x: w * 0.42, y: hz + h * 0.02))
        path.addQuadCurve(to: CGPoint(x: w * 0.7, y: h), control: CGPoint(x: w * 0.42, y: h * 0.7))
        path.addLine(to: CGPoint(x: w * 0.3, y: h))
        path.addQuadCurve(to: CGPoint(x: w * 0.36, y: hz + h * 0.02), control: CGPoint(x: w * 0.36, y: h * 0.7))
        ctx.fill(path, with: .color(night ? Color(red: 0.24, green: 0.22, blue: 0.24) : Color(red: 0.62, green: 0.46, blue: 0.28)))
        tufts(ctx, s, from: hz, color: night ? Color(red: 0.2, green: 0.36, blue: 0.26) : Color(red: 0.3, green: 0.52, blue: 0.16))
        // The cottage: green clapboard, a red shingle roof, a chimney, door and window.
        let cw = w * 0.3, ch = h * 0.12
        let house = CGRect(x: w * 0.24, y: hz + h * 0.015 - ch, width: cw, height: ch)
        ctx.fill(Path(house), with: .color(night ? Color(red: 0.22, green: 0.38, blue: 0.36) : Color(red: 0.4, green: 0.66, blue: 0.5)))
        var boards = Path()
        var by = house.minY + ch * 0.18
        while by < house.maxY { boards.move(to: CGPoint(x: house.minX, y: by)); boards.addLine(to: CGPoint(x: house.maxX, y: by)); by += ch * 0.16 }
        ctx.stroke(boards, with: .color(ink.opacity(0.25)), lineWidth: 1)
        ctx.stroke(Path(house), with: .color(ink), lineWidth: 1.6)
        let chim = CGRect(x: house.maxX - cw * 0.25, y: house.minY - ch * 0.75, width: cw * 0.1, height: ch * 0.5)
        ctx.fill(Path(chim), with: .color(Color(red: 0.55, green: 0.3, blue: 0.24)))
        ctx.stroke(Path(chim), with: .color(ink), lineWidth: 1.4)
        var roof = Path()
        roof.move(to: CGPoint(x: house.minX - cw * 0.1, y: house.minY + 2))
        roof.addLine(to: CGPoint(x: house.midX, y: house.minY - ch * 0.75))
        roof.addLine(to: CGPoint(x: house.maxX + cw * 0.1, y: house.minY + 2))
        roof.closeSubpath()
        ctx.fill(roof, with: .linearGradient(Gradient(colors: [Color(red: 0.82, green: 0.36, blue: 0.2), Color(red: 0.6, green: 0.22, blue: 0.12)]), startPoint: CGPoint(x: 0, y: house.minY - ch * 0.75), endPoint: CGPoint(x: 0, y: house.minY)))
        var shingles = ctx
        shingles.clip(to: roof)
        var rows = Path()
        var ry = house.minY - ch * 0.6
        while ry < house.minY { rows.move(to: CGPoint(x: house.minX - cw * 0.2, y: ry)); rows.addLine(to: CGPoint(x: house.maxX + cw * 0.2, y: ry)); ry += ch * 0.14 }
        shingles.stroke(rows, with: .color(ink.opacity(0.3)), lineWidth: 1)
        ctx.stroke(roof, with: .color(ink), lineWidth: 1.6)
        let door = CGRect(x: house.minX + cw * 0.18, y: house.maxY - ch * 0.62, width: cw * 0.2, height: ch * 0.62)
        ctx.fill(Path(roundedRect: door, cornerRadius: door.width * 0.4), with: .color(Color(red: 0.42, green: 0.24, blue: 0.12)))
        ctx.stroke(Path(roundedRect: door, cornerRadius: door.width * 0.4), with: .color(ink), lineWidth: 1.4)
        let win = CGRect(x: house.minX + cw * 0.55, y: house.minY + ch * 0.25, width: cw * 0.26, height: ch * 0.4)
        ctx.fill(Path(win), with: .color(night ? Color(red: 1, green: 0.85, blue: 0.4) : Color(red: 0.3, green: 0.45, blue: 0.6)))
        var mullion = Path()
        mullion.move(to: CGPoint(x: win.midX, y: win.minY)); mullion.addLine(to: CGPoint(x: win.midX, y: win.maxY))
        mullion.move(to: CGPoint(x: win.minX, y: win.midY)); mullion.addLine(to: CGPoint(x: win.maxX, y: win.midY))
        ctx.stroke(mullion, with: .color(ink), lineWidth: 1.2)
        ctx.stroke(Path(win), with: .color(ink), lineWidth: 1.4)
        // A picket fence along the horizon.
        var pickets = Path()
        var px: CGFloat = 0
        while px < w {
            if px < house.minX - 6 || px > house.maxX + 6 {
                pickets.addRect(CGRect(x: px, y: hz - h * 0.03, width: w * 0.022, height: h * 0.04))
            }
            px += w * 0.04
        }
        pickets.addRect(CGRect(x: 0, y: hz - h * 0.022, width: house.minX - 6, height: h * 0.008))
        pickets.addRect(CGRect(x: house.maxX + 6, y: hz - h * 0.022, width: w - house.maxX - 6, height: h * 0.008))
        ctx.fill(pickets, with: .color(night ? Color(red: 0.55, green: 0.58, blue: 0.68) : Color(red: 0.96, green: 0.88, blue: 0.75)))
        ctx.stroke(pickets, with: .color(ink.opacity(0.7)), lineWidth: 0.8)
    }

    private func temple(_ ctx: GraphicsContext, _ s: CGSize) {
        let w = s.width, h = s.height, hz = h * 0.34
        sky(ctx, s, night ? [Color(red: 0.45, green: 0.1, blue: 0.22), Color(red: 0.95, green: 0.38, blue: 0.18), Color(red: 1, green: 0.72, blue: 0.32)]
                          : [Color(red: 0.92, green: 0.78, blue: 0.22), Color(red: 1, green: 0.92, blue: 0.5), Color(red: 1, green: 0.97, blue: 0.75)], horizon: hz)
        let sun = CGPoint(x: w * 0.5, y: h * 0.12)
        ctx.fill(CMArt.disc(sun, h * 0.2), with: .radialGradient(Gradient(colors: [Color.white.opacity(0.9), Color(red: 1, green: 0.95, blue: 0.6).opacity(0.5), .clear]), center: sun, startRadius: 0, endRadius: h * 0.2))
        // Jungle canopy on both sides.
        var canopy = Path()
        for k in 0..<14 {
            let x = w * CGFloat(k) / 13
            if abs(x - w / 2) < w * 0.24 { continue }
            let r = h * (0.05 + 0.03 * CGFloat(CMArt.hash(Double(k) * 2.3)))
            canopy.addEllipse(in: CGRect(x: x - r, y: hz - r * 1.7, width: r * 2, height: r * 2))
        }
        canopy.addRect(CGRect(x: 0, y: hz - h * 0.05, width: w, height: h * 0.05))
        ctx.fill(canopy, with: .color(night ? Color(red: 0.2, green: 0.16, blue: 0.12) : Color(red: 0.2, green: 0.42, blue: 0.14)))
        // The stepped temple with a carved monkey face over the door.
        let stone = night ? Color(red: 0.72, green: 0.48, blue: 0.3) : Color(red: 0.9, green: 0.74, blue: 0.42)
        let tiers = 4
        for k in 0..<tiers {
            let tw = w * (0.56 - 0.1 * CGFloat(k)), th = h * 0.045
            let r = CGRect(x: w / 2 - tw / 2, y: hz - th * CGFloat(k + 1), width: tw, height: th)
            ctx.fill(Path(r), with: .linearGradient(Gradient(colors: [stone.lit(0.15), stone.shade(0.15)]), startPoint: CGPoint(x: 0, y: r.minY), endPoint: CGPoint(x: 0, y: r.maxY)))
            var blocks = Path()
            var bx = r.minX + th * 1.2
            while bx < r.maxX { blocks.move(to: CGPoint(x: bx, y: r.minY)); blocks.addLine(to: CGPoint(x: bx, y: r.maxY)); bx += th * 1.6 }
            ctx.stroke(blocks, with: .color(ink.opacity(0.3)), lineWidth: 1)
            ctx.stroke(Path(r), with: .color(ink), lineWidth: 1.4)
        }
        let shrine = CGRect(x: w / 2 - w * 0.12, y: hz - h * 0.045 * CGFloat(tiers) - h * 0.1, width: w * 0.24, height: h * 0.1)
        ctx.fill(Path(shrine), with: .color(stone))
        ctx.stroke(Path(shrine), with: .color(ink), lineWidth: 1.6)
        let face = CGPoint(x: shrine.midX, y: shrine.minY + shrine.height * 0.42)
        let fr = shrine.height * 0.3
        for side in [-1.0, 1.0] as [CGFloat] { ctx.fill(CMArt.disc(CGPoint(x: face.x + side * fr, y: face.y), fr * 0.38), with: .color(stone.shade(0.25))) }
        ctx.fill(CMArt.disc(face, fr), with: .color(stone.shade(0.2)))
        ctx.stroke(CMArt.disc(face, fr), with: .color(ink), lineWidth: 1.2)
        for side in [-1.0, 1.0] as [CGFloat] { ctx.fill(CMArt.oval(CGPoint(x: face.x + side * fr * 0.38, y: face.y - fr * 0.1), fr * 0.18, fr * 0.24), with: .color(ink)) }
        let doorR = CGRect(x: shrine.midX - shrine.width * 0.14, y: shrine.maxY - shrine.height * 0.28, width: shrine.width * 0.28, height: shrine.height * 0.28)
        ctx.fill(Path(doorR), with: .color(ink))
        // Vines.
        var vines = Path()
        for (fx, len) in [(0.3, 0.12), (0.62, 0.09), (0.69, 0.14)] as [(CGFloat, CGFloat)] {
            vines.move(to: CGPoint(x: w * fx, y: hz - h * 0.18))
            vines.addCurve(to: CGPoint(x: w * fx + 4, y: hz - h * 0.18 + h * len), control1: CGPoint(x: w * fx + 8, y: hz - h * 0.14), control2: CGPoint(x: w * fx - 8, y: hz - h * 0.1))
        }
        ctx.stroke(vines, with: .color(Color(red: 0.18, green: 0.5, blue: 0.14)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        // Courtyard flagstones in perspective.
        let floor = night ? [Color(red: 0.62, green: 0.42, blue: 0.3), Color(red: 0.42, green: 0.26, blue: 0.18)] : [Color(red: 0.86, green: 0.74, blue: 0.5), Color(red: 0.66, green: 0.52, blue: 0.32)]
        ctx.fill(Path(CGRect(x: 0, y: hz, width: w, height: h - hz)), with: .linearGradient(Gradient(colors: floor), startPoint: CGPoint(x: 0, y: hz), endPoint: CGPoint(x: 0, y: h)))
        var grid = Path()
        var gy = hz, step = h * 0.03
        while gy < h { grid.move(to: CGPoint(x: 0, y: gy)); grid.addLine(to: CGPoint(x: w, y: gy)); gy += step; step *= 1.25 }
        for k in -6...6 {
            grid.move(to: CGPoint(x: w / 2 + CGFloat(k) * w * 0.06, y: hz))
            grid.addLine(to: CGPoint(x: w / 2 + CGFloat(k) * w * 0.3, y: h))
        }
        ctx.stroke(grid, with: .color(ink.opacity(0.22)), lineWidth: 1)
    }

    private func deck(_ ctx: GraphicsContext, _ s: CGSize) {
        let w = s.width, h = s.height, hz = h * 0.34
        sky(ctx, s, night ? [Color(red: 0.14, green: 0.16, blue: 0.2), Color(red: 0.3, green: 0.36, blue: 0.38), Color(red: 0.46, green: 0.52, blue: 0.5)]
                          : [Color(red: 0.32, green: 0.62, blue: 0.95), Color(red: 0.62, green: 0.84, blue: 1), Color(red: 0.86, green: 0.95, blue: 1)], horizon: hz)
        if night {
            var rain = Path()
            for k in 0..<40 {
                let x = w * CGFloat(CMArt.hash(Double(k) * 2.7)), y = hz * CGFloat(CMArt.hash(Double(k) * 5.9))
                rain.move(to: CGPoint(x: x, y: y)); rain.addLine(to: CGPoint(x: x - 6, y: y + 16))
            }
            ctx.stroke(rain, with: .color(.white.opacity(0.35)), lineWidth: 1)
        } else {
            var clouds = Path()
            for (fx, fy, r) in [(0.2, 0.08, 0.05), (0.8, 0.14, 0.04)] as [(CGFloat, CGFloat, CGFloat)] {
                for k in 0..<3 { clouds.addEllipse(in: CGRect(x: w * fx + CGFloat(k - 1) * h * r * 1.1 - h * r, y: h * fy - (k == 1 ? h * r * 0.5 : 0), width: h * r * 2, height: h * r * 1.4)) }
            }
            ctx.fill(clouds, with: .color(.white.opacity(0.9)))
        }
        // The sea.
        ctx.fill(Path(CGRect(x: 0, y: hz - h * 0.07, width: w, height: h * 0.07)), with: .color(night ? Color(red: 0.12, green: 0.24, blue: 0.28) : Color(red: 0.12, green: 0.42, blue: 0.75)))
        var waves = Path()
        for k in 0..<12 { let x = w * CGFloat(k) / 11; waves.move(to: CGPoint(x: x - 8, y: hz - h * 0.04)); waves.addQuadCurve(to: CGPoint(x: x + 8, y: hz - h * 0.04), control: CGPoint(x: x, y: hz - h * 0.05)) }
        ctx.stroke(waves, with: .color(.white.opacity(0.5)), lineWidth: 1.2)
        // Mast, yard, sail and rigging.
        let mastX = w * 0.5
        var shrouds = Path()
        for k in 0..<4 {
            let f = CGFloat(k) / 3
            shrouds.move(to: CGPoint(x: mastX, y: h * 0.04)); shrouds.addLine(to: CGPoint(x: w * (0.08 + 0.1 * f), y: hz))
            shrouds.move(to: CGPoint(x: mastX, y: h * 0.04)); shrouds.addLine(to: CGPoint(x: w * (0.92 - 0.1 * f), y: hz))
        }
        ctx.stroke(shrouds, with: .color(Color(red: 0.3, green: 0.22, blue: 0.14)), lineWidth: 1.4)
        var sail = Path()
        sail.move(to: CGPoint(x: mastX - w * 0.26, y: h * 0.06))
        sail.addLine(to: CGPoint(x: mastX + w * 0.26, y: h * 0.06))
        sail.addQuadCurve(to: CGPoint(x: mastX + w * 0.22, y: h * 0.24), control: CGPoint(x: mastX + w * 0.32, y: h * 0.15))
        sail.addQuadCurve(to: CGPoint(x: mastX - w * 0.22, y: h * 0.24), control: CGPoint(x: mastX, y: h * 0.28))
        sail.addQuadCurve(to: CGPoint(x: mastX - w * 0.26, y: h * 0.06), control: CGPoint(x: mastX - w * 0.32, y: h * 0.15))
        ctx.fill(sail, with: .linearGradient(Gradient(colors: [Color(red: 0.98, green: 0.94, blue: 0.84), Color(red: 0.82, green: 0.74, blue: 0.6)]), startPoint: CGPoint(x: mastX - w * 0.2, y: 0), endPoint: CGPoint(x: mastX + w * 0.25, y: 0)))
        ctx.stroke(sail, with: .color(ink), lineWidth: 1.4)
        ctx.fill(Path(CGRect(x: mastX - w * 0.018, y: 0, width: w * 0.036, height: hz)), with: .linearGradient(Gradient(colors: [Color(red: 0.5, green: 0.32, blue: 0.16), Color(red: 0.7, green: 0.48, blue: 0.26), Color(red: 0.45, green: 0.28, blue: 0.13)]),
                                                                                                            startPoint: CGPoint(x: mastX - w * 0.018, y: 0), endPoint: CGPoint(x: mastX + w * 0.018, y: 0)))
        ctx.stroke(Path(CGRect(x: mastX - w * 0.018, y: 0, width: w * 0.036, height: hz)), with: .color(ink), lineWidth: 1.2)
        ctx.fill(Path(roundedRect: CGRect(x: mastX - w * 0.28, y: h * 0.045, width: w * 0.56, height: h * 0.018), cornerRadius: 3), with: .color(Color(red: 0.5, green: 0.32, blue: 0.16)))
        // Deck planks running toward you, and the rail at the far edge.
        let plank = night ? [Color(red: 0.42, green: 0.3, blue: 0.2), Color(red: 0.26, green: 0.18, blue: 0.12)] : [Color(red: 0.74, green: 0.52, blue: 0.3), Color(red: 0.52, green: 0.34, blue: 0.18)]
        ctx.fill(Path(CGRect(x: 0, y: hz, width: w, height: h - hz)), with: .linearGradient(Gradient(colors: plank), startPoint: CGPoint(x: 0, y: hz), endPoint: CGPoint(x: 0, y: h)))
        var seams = Path()
        for k in -8...8 {
            seams.move(to: CGPoint(x: w / 2 + CGFloat(k) * w * 0.05, y: hz))
            seams.addLine(to: CGPoint(x: w / 2 + CGFloat(k) * w * 0.17, y: h))
        }
        ctx.stroke(seams, with: .color(ink.opacity(0.35)), lineWidth: 1)
        var rail = Path()
        rail.addRect(CGRect(x: 0, y: hz - h * 0.035, width: w, height: h * 0.012))
        var px: CGFloat = w * 0.02
        while px < w { rail.addRect(CGRect(x: px, y: hz - h * 0.035, width: w * 0.014, height: h * 0.035)); px += w * 0.07 }
        ctx.fill(rail, with: .color(Color(red: 0.55, green: 0.36, blue: 0.18)))
        ctx.stroke(rail, with: .color(ink.opacity(0.8)), lineWidth: 0.8)
    }

    private func reef(_ ctx: GraphicsContext, _ s: CGSize) {
        let w = s.width, h = s.height, hz = h * 0.36
        sky(ctx, s, [Color(red: 0.2, green: 0.62, blue: 0.78), Color(red: 0.16, green: 0.3, blue: 0.62), Color(red: 0.3, green: 0.18, blue: 0.5)], horizon: hz)
        var rays = Path()
        for k in 0..<5 {
            let x = w * (0.1 + 0.2 * CGFloat(k))
            rays.move(to: CGPoint(x: x, y: 0)); rays.addLine(to: CGPoint(x: x + w * 0.06, y: 0))
            rays.addLine(to: CGPoint(x: x + w * 0.16, y: hz)); rays.addLine(to: CGPoint(x: x + w * 0.06, y: hz)); rays.closeSubpath()
        }
        ctx.fill(rays, with: .color(.white.opacity(0.07)))
        // Far coral silhouettes.
        var far = Path()
        for k in 0..<9 {
            let x = w * CGFloat(k) / 8, r = h * (0.04 + 0.03 * CGFloat(CMArt.hash(Double(k) * 4.1)))
            far.addEllipse(in: CGRect(x: x - r, y: hz - r * 1.5, width: r * 2, height: r * 2.2))
        }
        ctx.fill(far, with: .color(Color(red: 0.3, green: 0.14, blue: 0.4)))
        // Sea floor.
        ctx.fill(Path(CGRect(x: 0, y: hz, width: w, height: h - hz)), with: .linearGradient(Gradient(colors: [Color(red: 0.62, green: 0.46, blue: 0.66), Color(red: 0.42, green: 0.3, blue: 0.5)]), startPoint: CGPoint(x: 0, y: hz), endPoint: CGPoint(x: 0, y: h)))
        var ripples = Path()
        for k in 0..<10 {
            let y = hz + (h - hz) * CGFloat(k) / 10 + 6, x = w * CGFloat(CMArt.hash(Double(k) * 1.9))
            ripples.move(to: CGPoint(x: x - 20, y: y)); ripples.addQuadCurve(to: CGPoint(x: x + 20, y: y), control: CGPoint(x: x, y: y - 4))
        }
        ctx.stroke(ripples, with: .color(.white.opacity(0.18)), lineWidth: 1.2)
        // Seaweed and bubbles.
        var weed = Path()
        for (fx, len) in [(0.06, 0.2), (0.12, 0.14), (0.94, 0.22), (0.88, 0.12)] as [(CGFloat, CGFloat)] {
            weed.move(to: CGPoint(x: w * fx, y: hz + h * 0.04))
            weed.addCurve(to: CGPoint(x: w * fx + 4, y: hz + h * 0.04 - h * len), control1: CGPoint(x: w * fx + 12, y: hz - h * len * 0.3), control2: CGPoint(x: w * fx - 12, y: hz - h * len * 0.6))
        }
        ctx.stroke(weed, with: .color(Color(red: 0.2, green: 0.6, blue: 0.4)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        var bubbles = Path()
        for k in 0..<12 {
            let x = w * CGFloat(CMArt.hash(Double(k) * 6.1)), y = hz * CGFloat(CMArt.hash(Double(k) * 3.3)), r = 2 + 4 * CGFloat(CMArt.hash(Double(k)))
            bubbles.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
        ctx.stroke(bubbles, with: .color(.white.opacity(0.5)), lineWidth: 1.2)
    }

    private func tufts(_ ctx: GraphicsContext, _ s: CGSize, from y0: CGFloat, color: Color) {
        var t = Path()
        for k in 0..<30 {
            let x = s.width * CGFloat(CMArt.hash(Double(k) * 2.9)), y = y0 + (s.height - y0) * CGFloat(CMArt.hash(Double(k) * 5.7))
            t.move(to: CGPoint(x: x - 3, y: y)); t.addLine(to: CGPoint(x: x - 1, y: y - 6))
            t.move(to: CGPoint(x: x + 1, y: y)); t.addLine(to: CGPoint(x: x + 3, y: y - 7))
        }
        ctx.stroke(t, with: .color(color), lineWidth: 1.4)
    }
}

/// The card behind the scene and the lock: dark stained wood.
private struct CMFrame: View, Equatable {
    var body: some View {
        Canvas { ctx, s in
            ctx.fill(Path(CGRect(origin: .zero, size: s)), with: .linearGradient(Gradient(colors: [Color(red: 0.24, green: 0.14, blue: 0.08), Color(red: 0.13, green: 0.07, blue: 0.04)]),
                                                                                 startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height)))
            var grain = Path()
            for k in 0..<18 {
                let y = s.height * CGFloat(CMArt.hash(Double(k) * 3.3))
                grain.move(to: CGPoint(x: 0, y: y)); grain.addCurve(to: CGPoint(x: s.width, y: y + 6), control1: CGPoint(x: s.width * 0.3, y: y - 5), control2: CGPoint(x: s.width * 0.7, y: y + 9))
            }
            ctx.stroke(grain, with: .color(.black.opacity(0.2)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// The lock panel's wooden plank with nails.
private struct CMPlank: View, Equatable {
    var body: some View {
        Canvas { ctx, s in
            let wood = Color(red: 0.62, green: 0.4, blue: 0.2)
            ctx.fill(Path(CGRect(origin: .zero, size: s)), with: .linearGradient(Gradient(colors: [wood.lit(0.12), wood.shade(0.2)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height)))
            var seams = Path()
            seams.move(to: CGPoint(x: 0, y: s.height / 2)); seams.addLine(to: CGPoint(x: s.width, y: s.height / 2))
            ctx.stroke(seams, with: .color(.black.opacity(0.3)), lineWidth: 1.5)
            var grain = Path()
            for k in 0..<8 {
                let y = s.height * CGFloat(CMArt.hash(Double(k) * 7.7))
                grain.move(to: CGPoint(x: 0, y: y)); grain.addQuadCurve(to: CGPoint(x: s.width, y: y + 3), control: CGPoint(x: s.width / 2, y: y - 4))
            }
            ctx.stroke(grain, with: .color(.black.opacity(0.12)), lineWidth: 1)
            for (x, y) in [(8.0, 8.0), (s.width - 8, 8.0), (8.0, s.height - 8), (s.width - 8, s.height - 8)] as [(CGFloat, CGFloat)] {
                ctx.fill(CMArt.disc(CGPoint(x: x, y: y), 2.6), with: .color(Color(white: 0.3)))
                ctx.fill(CMArt.disc(CGPoint(x: x - 0.6, y: y - 0.6), 1), with: .color(Color(white: 0.8)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// One lock wheel: a brass bezel, a frame in the wheel's colour, and a cream drum showing the
/// current symbol (or dice pips) painted in that colour.
private struct CMWheelFace: View {
    let hue: CMHue
    let count: Bool
    let face: Int
    let open: Bool
    let compact: Bool

    var body: some View {
        Canvas { ctx, s in
            let r = CGRect(origin: .zero, size: s).insetBy(dx: 1, dy: 1)
            let brass = Color(red: 0.92, green: 0.72, blue: 0.3)
            ctx.fill(Path(roundedRect: r.offsetBy(dx: 1.5, dy: 2.5), cornerRadius: r.width * 0.18), with: .color(.black.opacity(0.4)))
            ctx.fill(Path(roundedRect: r, cornerRadius: r.width * 0.18), with: .linearGradient(Gradient(colors: [brass.lit(0.35), brass, brass.shade(0.35)]), startPoint: CGPoint(x: 0, y: r.minY), endPoint: CGPoint(x: 0, y: r.maxY)))
            let frame = r.insetBy(dx: r.width * 0.09, dy: r.height * 0.07)
            ctx.fill(Path(roundedRect: frame, cornerRadius: frame.width * 0.14), with: .color(CMArt.color(hue)))
            let drum = frame.insetBy(dx: frame.width * 0.12, dy: frame.height * 0.08)
            ctx.fill(Path(roundedRect: drum, cornerRadius: drum.width * 0.1),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.72, green: 0.66, blue: 0.56), Color(red: 1, green: 0.98, blue: 0.9), Color(red: 1, green: 0.98, blue: 0.9), Color(red: 0.72, green: 0.66, blue: 0.56)]),
                                           startPoint: CGPoint(x: 0, y: drum.minY), endPoint: CGPoint(x: 0, y: drum.maxY)))
            let side = min(drum.width, drum.height) * 0.72
            let box = CGRect(x: drum.midX - side / 2, y: drum.midY - side / 2, width: side, height: side)
            let mark = count ? CMArt.pips(face + 1, in: box) : CMArt.glyph(face, in: box)
            ctx.fill(mark, with: .color(CMArt.color(hue)))
            ctx.stroke(mark, with: .color(CMArt.ink.opacity(0.85)), lineWidth: compact ? 1 : 1.4)
            ctx.stroke(Path(roundedRect: drum, cornerRadius: drum.width * 0.1), with: .color(CMArt.ink.opacity(0.7)), lineWidth: 1)
            ctx.stroke(Path(roundedRect: r, cornerRadius: r.width * 0.18), with: .color(CMArt.ink), lineWidth: compact ? 1.4 : 2)
            if open {
                ctx.stroke(Path(roundedRect: frame, cornerRadius: frame.width * 0.14), with: .color(Color(red: 0.6, green: 1, blue: 0.5)), lineWidth: compact ? 2 : 3)
            }
        }
    }
}

private struct CMWheelStyle: ButtonStyle {
    var lit: Bool

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed || lit
        return configuration.label
            .scaleEffect(down ? 0.93 : 1)
            .brightness(down ? 0.06 : 0)
    }
}
