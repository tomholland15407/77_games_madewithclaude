//
//  LawnDefenseGame.swift
//  A Banana Game
//
//  Reflex — a lawn siege in the Plants vs. Zombies mould, across seven worlds. Zombies shamble in from
//  the right, one lane at a time. Tap a seed packet, then a lawn tile, to plant. Sunflowers make sun;
//  pea shooters, corn poppers (two shots at a time) and frost berries (they slow) fire down their lane;
//  melon lobbers arc over shields and graves and splash; walnuts block, banana peels trip, flytraps
//  swallow; cherry bombs blow up the 3×3 tiles around them and hot chilis burn a whole lane. Planting
//  costs sun, so tap the suns that drop from the sky (and the ones your sunflowers make). Each lane has
//  one lawn mower that saves it once; a zombie that gets past a used mower reaches the house and you're
//  back to level 1. After the final rush comes the world's boss: knock its health bar down to win.
//
//  One world per level, each with its boss: the backyard (a giant groundskeeper who walks a lane
//  smashing plants and flings his imp), the desert (a mummy pharaoh who raises graves and calls mummies
//  up out of the sand), a pirate ship (a captain who fires cannonballs and sends pirates swinging in),
//  the frontier (an outlaw's locomotive that charges down two lanes), a glacier (a woolly mammoth that
//  freezes a lane and rolls snowballs), the far future (a mech with a lane laser and missiles) and a
//  rooftop at night (a brain-bot that rolls fire- and iceballs, stomps and drops zombies; less sun falls
//  at night). New zombies join along the way: shield bearers, jumpers on springs that vault the first
//  plant, and fast helmeted runners. A standing boss blocks the last column of the lanes it covers.
//
//  Difficulty: level 1 plays like the old level 5 (the old game was too easy). Tuned with a bot that
//  collects sun like a person and looks ahead by stepping a copy of this world: it wins about 93% of
//  level 1, then 69 / 57 / 35 / 24 / 7 / 1% (on the old levels it won 97% of 5, 68% of 6, 55% of 7).
//
//  The whole battle is `LDWorld`, a plain value stepped by `step(_:)`; the game, its demo and the
//  offline balance bot all drive that same code. The art is in LawnDefenseArt.swift (worlds, plants,
//  zombies) and LawnDefenseBosses.swift (the seven bosses and their attacks). The six new plants, the
//  bosses and the world outfits are original designs; the sunflower, peashooter, walnut, cherry bomb and
//  the coat-and-tie zombie keep the 2009 look the game launched with.
//

import SwiftUI

enum LawnDefenseGame {
    static let definition = GameDefinition(
        id: "lawn-defense",
        title: "Lawn Defense",
        emoji: "🍌",
        genre: .reflex,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Tap a seed packet, then a lawn tile to plant it. Tap the falling suns to pay for plants.",
                "Sunflowers make sun. Shooters fire down their lane: frost slows, corn fires twice, melons lob over shields. Walnuts block, peels trip, flytraps gulp, cherries and chilis blast.",
                "Every world ends with a boss: knock its health bar down while it wrecks your lawn.",
                "Each lane's lawn mower saves it once. A zombie that reaches the house sends you back to level 1.",
            ],
            bulletsVI: [
                "Chạm một gói hạt, rồi chạm ô cỏ để trồng. Chạm những mặt trời rơi xuống để có tiền trồng cây.",
                "Hướng dương tạo mặt trời. Cây bắn bắn dọc hàng: việt quất băng làm chậm, bắp bắn hai phát, dưa hấu ném qua khiên. Óc chó chặn đường, vỏ chuối làm trượt ngã, cây bắt ruồi nuốt chửng, anh đào và ớt nổ tung.",
                "Mỗi thế giới kết thúc bằng một trùm: hạ hết thanh máu của nó khi nó phá bãi cỏ của bạn.",
                "Máy cắt cỏ ở mỗi hàng cứu bạn một lần. Zombie nào vào tới nhà sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(LawnDefenseView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

// MARK: - Simulation

/// The seven worlds, one per level.
enum LDScene: Int, CaseIterable {
    case backyard, desert, pirate, frontier, glacier, future, rooftop
}

/// The seed packets, in bar order: sun, shooters, then walls, traps and bombs.
enum LDPlantKind: Int, CaseIterable {
    case sunflower, peashooter, popper, frost, lobber, wallnut, peel, flytrap, cherry, chili
    var cost: Int { [50, 100, 200, 175, 300, 50, 25, 150, 150, 125][rawValue] }
    /// Seconds before the packet can be planted again.
    var recharge: Double { [3, 4.5, 6, 6, 8, 16, 14, 10, 26, 24][rawValue] }
    /// Bites a zombie needs to eat it (a zombie bites once a second).
    var bites: Double { [3, 3, 3, 3, 3, 26, 3, 3, 99, 99][rawValue] }
    /// The straight shooters.
    var shoots: Bool { self == .peashooter || self == .popper || self == .frost }
    /// Lit bombs: nothing can squash one before it goes off.
    var isBomb: Bool { self == .cherry || self == .chili }
}

enum LDZombieKind: Int {
    case normal, cone, bucket, flag, imp, runner, jumper, shield
    /// Peas the zombie itself takes.
    var hp: Double { [6, 6, 6, 6, 3, 6, 7, 6][rawValue] }
    /// Peas the headgear soaks up before the zombie itself takes damage.
    var armor: Double { [0, 8, 18, 0, 0, 12, 0, 0][rawValue] }
    /// Straight shots the shield in front soaks up (lobs and blasts reach the zombie).
    var shield: Double { [0, 0, 0, 0, 0, 0, 0, 14][rawValue] }
    /// Walking pace against a plain zombie's.
    var pace: Double { [1, 1, 1, 1.15, 1.5, 1.9, 1.7, 0.95][rawValue] }
}

/// The boss at the end of each world.
enum LDBossKind: Int {
    case groundskeeper, pharaoh, captain, outlaw, mammoth, mech, megabot
    /// Lanes it covers: the groundskeeper walks one, the locomotive fills two, the rest three.
    var span: Int { [1, 3, 3, 2, 3, 3, 3][rawValue] }
    /// What it does between summons.
    var moves: [LDBossMove] {
        switch self {
        case .groundskeeper: return []
        case .pharaoh: return [.graves, .ambush, .summon]
        case .captain: return [.bombard, .ambush, .summon]
        case .outlaw: return [.charge, .bombard, .summon]
        case .mammoth: return [.freeze, .roll, .summon]
        case .mech: return [.laser, .bombard, .summon]
        case .megabot: return [.roll, .stomp, .ambush, .summon]
        }
    }
}

enum LDBossMove {
    case summon, ambush, graves, bombard, charge, freeze, roll, laser, stomp
    /// Seconds of warning before it lands.
    var windup: Double {
        switch self {
        case .summon: return 0.9
        case .ambush: return 1.4
        case .graves: return 1.1
        case .bombard: return 1.5
        case .charge: return 1.6
        case .freeze: return 1.4
        case .roll: return 1.1
        case .laser: return 1.6
        case .stomp: return 1.4
        }
    }
}

enum LDShot { case pea, popcorn, frost, melon }
enum LDRollerKind { case snowball, fireball, iceball }
enum LDTarget: Equatable { case zombie(Int), boss, roller(Int) }

struct LDTile: Hashable { let row: Int; let col: Int }

/// A small seeded generator, so the demo and the bot replay exactly.
struct LDRandom {
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
}

/// One level's recipe.
struct LDParams {
    var scene: LDScene
    var rows: [Int]                 // lanes in play (0…4, top to bottom)
    var count: Int                  // zombies in the horde
    var mix: [(LDZombieKind, Double)] // share of each special kind (the rest are plain)
    var firstSpawn: Double          // seconds before the first zombie
    var gap: Double                 // seconds between zombies before the final wave
    var finalWave: Int              // zombies in the last rush (led by a flag zombie; the boss follows it)
    var speed: Double               // tiles per second
    var skyEvery: Double            // seconds between suns from the sky
    var startSun: Int
    var mowers: Bool                // one lawn mower per lane
    var packets: [LDPlantKind]
    var boss: LDBossKind?
    var bossHP: Double
    var bossEvery: Double           // seconds between its moves
    var bossPower: Int              // zombies per summon, graves or shells per move

    static func level(_ level: Int) -> LDParams {
        let i = min(max(level, 1), 7) - 1
        // A gentle ramp (Oct 17 2026): the balance bot wins about 91 / 88 / 83 / 79 / 73 / 59 / 33% of L1–7 (the
        // Oct 9 table: 91 / 75 / 60 / 37 / 23 / 6 / 2%), so L5 plays like the old L2, L6 like the old L3, L7 like the old L4.
        let mixes: [[(LDZombieKind, Double)]] = [
            [(.bucket, 0.16), (.cone, 0.34)],
            [(.bucket, 0.2), (.shield, 0.12), (.cone, 0.32)],
            [(.bucket, 0.18), (.jumper, 0.11), (.shield, 0.07), (.cone, 0.31)],
            [(.bucket, 0.18), (.runner, 0.12), (.jumper, 0.08), (.cone, 0.29)],
            [(.bucket, 0.19), (.shield, 0.09), (.jumper, 0.08), (.runner, 0.07), (.cone, 0.29)],
            [(.bucket, 0.2), (.runner, 0.09), (.shield, 0.09), (.jumper, 0.07), (.cone, 0.28)],
            [(.bucket, 0.2), (.runner, 0.1), (.shield, 0.08), (.jumper, 0.08), (.cone, 0.28)],
        ]
        return LDParams(
            scene: LDScene(rawValue: i)!,
            rows: [0, 1, 2, 3, 4],
            count: [18, 21, 22, 20, 21, 23, 23][i],
            mix: mixes[i],
            firstSpawn: [12, 12, 11.5, 11.5, 11.5, 11, 11][i],
            gap: [4.6, 4.4, 4.4, 4.5, 4.3, 4.4, 4.3][i],
            finalWave: [6, 6, 6, 7, 7, 7, 10][i],
            speed: [0.38, 0.39, 0.39, 0.4, 0.4, 0.41, 0.41][i],
            skyEvery: [5.5, 5.8, 5.8, 6, 5.8, 6.2, 7][i],
            startSun: [125, 100, 100, 100, 100, 100, 100][i],
            mowers: true,
            packets: LDPlantKind.allCases,
            boss: LDBossKind(rawValue: i),
            bossHP: [60, 125, 115, 90, 130, 100, 150][i],
            bossEvery: [9, 8, 8.5, 7.5, 7, 6.5, 6.5][i],
            bossPower: [2, 2, 2, 2, 2, 2, 2][i]
        )
    }
}

/// The whole battle as a value: the view, the demo and the balance bot step the same code.
struct LDWorld {
    struct Plant: Identifiable {
        let id: Int
        let kind: LDPlantKind
        let row: Int
        let col: Int
        var hp: Double
        var timer: Double
        var planted: Double
        var fired = -9.0           // time of the last shot (for the recoil)
        var bitten = -9.0          // time of the last bite (for the wince)
        var frozen = 0.0           // seconds it stays iced over
        var chewing = 0.0          // a flytrap's seconds left chewing
        var gulp = -9.0            // a flytrap's last snap
    }
    struct Zombie: Identifiable {
        let id: Int
        let kind: LDZombieKind
        let row: Int
        var x: Double              // front edge, in tiles from the house (0) to the street (cols)
        var hp: Double
        var armor: Double
        var shield: Double
        var speedK: Double
        var born: Double           // when it stepped onto the lawn
        var eating = false
        var hit = -9.0             // time of the last pea (for the flash)
        var died: Double? = nil    // time it fell (it lingers to topple)
        var burnt = false          // blown up rather than shot
        var eaten = false          // swallowed by a flytrap
        var slowUntil = -9.0       // chilled by a frost berry
        var stunUntil = -9.0       // flat on its back after a banana peel
        var hopped = -9.0          // when a jumper vaulted (it only does it once)
    }
    struct Pea: Identifiable {
        let id: Int
        let row: Int
        var x: Double
        let shot: LDShot
    }
    struct Lob: Identifiable {
        let id: Int
        let row: Int
        let x0: Double
        var x1: Double
        let t0: Double
        let target: LDTarget
    }
    struct Sun: Identifiable {
        let id: Int
        var x: Double              // tiles
        var y: Double              // rows
        let landY: Double
        var life: Double           // seconds left once it has landed
        let born: Double
    }
    struct Grave: Identifiable {
        let id: Int
        let row: Int
        let col: Int
        var hp: Double
        let born: Double
    }
    struct Roller: Identifiable {
        let id: Int
        let kind: LDRollerKind
        let row: Int
        var x: Double              // front edge
        var hp: Double
        let born: Double
    }
    struct Drop: Identifiable {
        let id: Int
        let kind: LDZombieKind
        let row: Int
        let x: Double
        let fromX: Double
        let t0: Double
        let lands: Double
    }
    struct Boss {
        enum Mode: Equatable { case arriving, standing, walking, shifting, charging, retreating }
        let kind: LDBossKind
        let maxHP: Double
        var hp: Double
        var row: Int               // the top lane it covers
        var y: Double              // that lane as drawn (it glides between lanes)
        var x: Double              // front edge
        var mode: Mode = .arriving
        var clock = 2.5            // seconds until its next move
        var move: LDBossMove? = nil
        var windup = 0.0           // seconds left before the move lands
        var targets: [LDTile] = [] // what the move aims at
        var last: LDBossMove? = nil
        var moves = 0
        var stunUntil = -9.0
        var hit = -9.0
        var died: Double? = nil
        var threw = false          // the groundskeeper's imp
        var smashed = -9.0         // the groundskeeper's last swing
        var arrivedAt = 0.0
        var lastAt = -9.0          // when its last move landed (for the view)
        var lastTargets: [LDTile] = []

        var rows: ClosedRange<Int> { row...(row + kind.span - 1) }
        static let home = 5.6      // where a standing boss's front edge stops
    }
    enum Mower { case ready, running(Double), gone }
    struct Splat { let row: Int; let x: Double; let t: Double; let shot: LDShot }
    struct Boom { let row: Int; let col: Int; let t: Double }
    struct Blaze { let row: Int; let t: Double }
    struct Crash { let row: Int; let col: Int; let t: Double }   // a shell, a stomp or a laser landing

    static let cols = 7
    static let biteRate = 1.0          // bites per second
    static let peaSpeed = 5.0          // tiles per second
    static let shootEvery = 1.4
    static let lobEvery = 2.8
    static let lobTime = 0.9
    static let sunflowerEvery = 7.5
    static let sunValue = 25
    static let peelArm = 6.0
    static let rollSpeed = 1.15
    static let chargeStop = 2.0           // how far down the lawn the locomotive charges

    let params: LDParams
    var t = 0.0
    var sun: Int
    var plants: [Plant] = []
    var zombies: [Zombie] = []
    var peas: [Pea] = []
    var lobs: [Lob] = []
    var suns: [Sun] = []
    var graves: [Grave] = []
    var rollers: [Roller] = []
    var drops: [Drop] = []
    var boss: Boss? = nil
    var mowers: [Mower]
    var recharge: [Double] = Array(repeating: 0, count: LDPlantKind.allCases.count)
    var schedule: [(t: Double, row: Int, kind: LDZombieKind)] = []
    var spawned = 0
    var skyTimer: Double
    var splats: [Splat] = []
    var booms: [Boom] = []
    var blazes: [Blaze] = []
    var crashes: [Crash] = []
    var won = false
    var lost = false
    var nextID = 1
    var rng: LDRandom

    init(params: LDParams, seed: UInt64) {
        self.params = params
        sun = params.startSun
        rng = LDRandom(state: seed)
        mowers = (0..<5).map { params.mowers && params.rows.contains($0) ? .ready : .gone }
        skyTimer = 3
        // The horde: an even trickle, then a final rush led by a flag zombie (the boss follows it).
        let n = params.count, rush = max(1, min(params.finalWave, n))
        var kinds: [LDZombieKind] = []
        var quota: [(LDZombieKind, Int)] = params.mix.map { ($0.0, Int((Double(n) * $0.1).rounded())) }
        for _ in 0..<n {
            if let q = quota.firstIndex(where: { $0.1 > 0 }) { kinds.append(quota[q].0); quota[q].1 -= 1 } else { kinds.append(.normal) }
        }
        for k in stride(from: n - 1, to: 0, by: -1) { kinds.swapAt(k, rng.int(k + 1)) }
        // Keep the opening gentle: the first two are plain zombies.
        for k in 0..<min(2, n) where kinds[k] != .normal {
            if let j = kinds.indices.last(where: { kinds[$0] == .normal }), j > k { kinds.swapAt(k, j) }
        }
        var time = params.firstSpawn
        for k in 0..<n {
            let inRush = k >= n - rush
            let kind: LDZombieKind = k == n - rush ? .flag : kinds[k]
            schedule.append((t: time, row: params.rows[rng.int(params.rows.count)], kind: kind))
            if k == n - rush - 1 { time += params.gap + 3 }                // a breath before the rush
            else if inRush { time += 0.45 + rng.unit() * 0.4 }
            else { time += params.gap * (0.85 + rng.unit() * 0.3) * (1 - 0.25 * Double(k) / Double(max(1, n))) }
        }
    }

    private mutating func newID() -> Int { nextID += 1; return nextID }

    /// Fraction of the horde that has arrived (the flag meter).
    var progress: Double { schedule.isEmpty ? 1 : Double(spawned) / Double(schedule.count) }

    func plant(at row: Int, _ col: Int) -> Plant? { plants.first { $0.row == row && $0.col == col } }
    func grave(at row: Int, _ col: Int) -> Grave? { graves.first { $0.row == row && $0.col == col } }

    func canPlant(_ kind: LDPlantKind) -> Bool {
        params.packets.contains(kind) && sun >= kind.cost && recharge[kind.rawValue] <= 0
    }

    /// The tiles a standing boss's bulk covers (nothing can be planted there).
    func bossCovers(_ row: Int, _ col: Int) -> Bool {
        guard let b = boss, b.died == nil, b.kind.span > 1, b.mode == .standing || b.mode == .shifting else { return false }
        return b.rows.contains(row) && Double(col) + 0.5 >= LDWorld.Boss.home
    }

    /// Plant a seed; false when it's unaffordable, recharging, or the tile isn't free lawn.
    @discardableResult
    mutating func plant(_ kind: LDPlantKind, row: Int, col: Int) -> Bool {
        guard !won, !lost, canPlant(kind), params.rows.contains(row), (0..<Self.cols).contains(col),
              plant(at: row, col) == nil, grave(at: row, col) == nil, !bossCovers(row, col) else { return false }
        sun -= kind.cost
        recharge[kind.rawValue] = kind.recharge
        let timer: Double
        switch kind {
        case .sunflower: timer = 4.5
        case .peashooter, .popper, .frost: timer = 0.4
        case .lobber: timer = 0.6
        case .wallnut, .flytrap: timer = 0
        case .peel: timer = Self.peelArm
        case .cherry: timer = 1.1        // fuse
        case .chili: timer = 0.8         // fuse
        }
        plants.append(Plant(id: newID(), kind: kind, row: row, col: col, hp: kind.bites, timer: timer, planted: t))
        return true
    }

    /// Pick up a sun; false if it's gone.
    @discardableResult
    mutating func collect(_ id: Int) -> Bool {
        guard let i = suns.firstIndex(where: { $0.id == id }) else { return false }
        suns.remove(at: i)
        sun += Self.sunValue
        return true
    }

    // MARK: Targets

    /// A zombie that can be hit: alive and on the ground.
    private func targetable(_ z: Zombie) -> Bool { z.died == nil && t >= z.born }

    private func bossIn(_ row: Int) -> Bool {
        guard let b = boss, b.died == nil, b.mode != .arriving || b.x < Double(Self.cols) - 0.3 else { return false }
        return b.rows.contains(row)
    }

    /// Anything a shooter in this tile would fire at (zombies, rolling balls, the boss).
    private func targetAhead(row: Int, col: Int) -> Bool {
        let c = Double(col) + 0.2, edge = Double(Self.cols) - 0.15
        if zombies.contains(where: { $0.row == row && targetable($0) && $0.x > c && $0.x < edge }) { return true }
        if rollers.contains(where: { $0.row == row && $0.x > c && $0.x < edge }) { return true }
        if let b = boss, bossIn(row), b.x > c, b.x < edge { return true }
        return false
    }

    /// The first thing ahead a lobbed melon would come down on (it flies over graves and shields).
    private func lobTarget(row: Int, col: Int) -> (LDTarget, Double)? {
        let c = Double(col) + 0.2, edge = Double(Self.cols) - 0.15
        var best: (LDTarget, Double)? = nil
        for z in zombies where z.row == row && targetable(z) && z.x > c && z.x < edge && z.x < (best?.1 ?? 99) { best = (.zombie(z.id), z.x) }
        for r in rollers where r.row == row && r.x > c && r.x < edge && r.x < (best?.1 ?? 99) { best = (.roller(r.id), r.x) }
        if let b = boss, bossIn(row), b.x > c, b.x < edge, b.x < (best?.1 ?? 99) { best = (.boss, b.x) }
        return best
    }

    // MARK: Damage

    private mutating func kill(_ i: Int, burnt: Bool = false, eaten: Bool = false) {
        guard zombies[i].died == nil else { return }
        zombies[i].died = t
        zombies[i].burnt = burnt
        zombies[i].eaten = eaten
    }

    /// Damage that goes round the shield (lobs, peels, splash): headgear first, then the zombie.
    private mutating func wound(_ i: Int, _ d: Double) {
        zombies[i].hit = t
        let soak = min(zombies[i].armor, d)
        zombies[i].armor -= soak
        zombies[i].hp -= d - soak
        if zombies[i].hp <= 0 { kill(i) }
    }

    private mutating func hurtBoss(_ d: Double, interrupt: Bool = false, stun: Double = 0) {
        guard boss?.died == nil, boss != nil else { return }
        boss!.hp -= d
        boss!.hit = t
        if stun > 0 { boss!.stunUntil = max(boss!.stunUntil, t + stun) }
        if interrupt && boss!.move != nil && boss!.mode == .standing {
            boss!.move = nil
            boss!.targets = []
            boss!.clock = params.bossEvery * 0.6
        }
        if boss!.hp <= 0 {
            boss!.hp = 0
            boss!.died = t
            boss!.move = nil
            boss!.targets = []
        }
    }

    // MARK: Step

    mutating func step(_ dt: Double) {
        guard !won, !lost else { return }
        t += dt
        for k in recharge.indices { recharge[k] = max(0, recharge[k] - dt) }

        // Zombies arrive on schedule, from the street; the boss comes in with the flag.
        while spawned < schedule.count && schedule[spawned].t <= t {
            let s = schedule[spawned]
            spawned += 1
            addZombie(s.kind, row: s.row, x: Double(Self.cols) + 0.4)
        }
        // The boss walks on once the final rush is nearly beaten (or soon after it, regardless).
        if boss == nil, let k = params.boss, spawned == schedule.count, let flag = schedule.last(where: { $0.kind == .flag })?.t,
           t - flag > 18 || (t - flag > 4 && zombies.filter({ $0.died == nil }).count <= 2) {
            arrive(k)
        }

        // Sun drifts down from the sky, lands, and fades away if nobody picks it up.
        skyTimer -= dt
        if skyTimer <= 0 {
            skyTimer = params.skyEvery
            let row = params.rows[rng.int(params.rows.count)]
            suns.append(Sun(id: newID(), x: 0.6 + rng.unit() * (Double(Self.cols) - 1.2), y: Double(params.rows[0]) - 0.9,
                            landY: Double(row) + 0.55, life: 8, born: t))
        }
        for i in suns.indices {
            if suns[i].y < suns[i].landY { suns[i].y = min(suns[i].landY, suns[i].y + 1.1 * dt) } else { suns[i].life -= dt }
        }
        suns.removeAll { $0.life <= 0 }

        plantsAct(dt)
        flyPeas(dt)
        flyLobs()
        zombiesAct(dt)
        bossAct(dt)
        rollersAct(dt)

        // Ambushers land.
        for d in drops where t >= d.lands { addZombie(d.kind, row: d.row, x: d.x) }
        drops.removeAll { t >= $0.lands }

        // A running mower clears its whole lane, then rolls off into the street.
        for r in mowers.indices {
            guard case .running(var x) = mowers[r] else { continue }
            x += 5 * dt
            for j in zombies.indices where zombies[j].row == r && zombies[j].died == nil && zombies[j].x < x + 0.35 { kill(j) }
            mowers[r] = x > Double(Self.cols) + 1 ? .gone : .running(x)
        }

        zombies.removeAll { $0.died.map { t - $0 > 1.6 } ?? false }
        graves.removeAll { $0.hp <= 0 }
        rollers.removeAll { $0.hp <= 0 || $0.x < -0.4 }
        splats.removeAll { t - $0.t > 0.35 }
        booms.removeAll { t - $0.t > 0.9 }
        blazes.removeAll { t - $0.t > 0.9 }
        crashes.removeAll { t - $0.t > 0.7 }
        if lost { return }
        // A beaten boss gets a moment to topple before the level is won.
        let bossDone = params.boss == nil || (boss?.died.map { t - $0 > 2 } ?? false)
        if bossDone && spawned == schedule.count && drops.isEmpty && zombies.allSatisfy({ $0.died != nil }) { won = true }
    }

    private mutating func addZombie(_ kind: LDZombieKind, row: Int, x: Double) {
        let k = kind == .flag ? 1 : 0.9 + 0.2 * rng.unit()
        zombies.append(Zombie(id: newID(), kind: kind, row: row, x: x, hp: kind.hp, armor: kind.armor, shield: kind.shield,
                              speedK: kind.pace * k, born: t))
    }

    // MARK: Plants

    private mutating func plantsAct(_ dt: Double) {
        var blasts: [(row: Int, col: Int)] = []
        var fires: [Int] = []
        for i in plants.indices {
            if plants[i].frozen > 0 { plants[i].frozen = max(0, plants[i].frozen - dt); continue }
            plants[i].timer -= dt
            let p = plants[i]
            switch p.kind {
            case .sunflower:
                if p.timer <= 0 {
                    plants[i].timer = Self.sunflowerEvery
                    suns.append(Sun(id: newID(), x: Double(p.col) + 0.75, y: Double(p.row) + 0.15,
                                    landY: Double(p.row) + 0.55, life: 8, born: t))
                }
            case .peashooter, .popper, .frost:
                if p.timer <= 0 && targetAhead(row: p.row, col: p.col) {
                    plants[i].timer = Self.shootEvery
                    plants[i].fired = t
                    let x = Double(p.col) + 0.8
                    switch p.kind {
                    case .popper:
                        peas.append(Pea(id: newID(), row: p.row, x: x, shot: .popcorn))
                        peas.append(Pea(id: newID(), row: p.row, x: x - 0.4, shot: .popcorn))
                    case .frost: peas.append(Pea(id: newID(), row: p.row, x: x, shot: .frost))
                    default: peas.append(Pea(id: newID(), row: p.row, x: x, shot: .pea))
                    }
                }
            case .lobber:
                if p.timer <= 0, let (target, x) = lobTarget(row: p.row, col: p.col) {
                    plants[i].timer = Self.lobEvery
                    plants[i].fired = t
                    lobs.append(Lob(id: newID(), row: p.row, x0: Double(p.col) + 0.5, x1: x, t0: t, target: target))
                }
            case .flytrap:
                if p.chewing > 0 { plants[i].chewing = max(0, p.chewing - dt); break }
                let reach = Double(p.col) + 1.35
                if let j = zombies.indices.filter({ zombies[$0].row == p.row && targetable(zombies[$0])
                    && zombies[$0].x > Double(p.col) + 0.1 && zombies[$0].x < reach }).min(by: { zombies[$0].x < zombies[$1].x }) {
                    kill(j, eaten: true)
                    plants[i].chewing = 12
                    plants[i].gulp = t
                } else if let b = boss, bossIn(p.row), b.x > Double(p.col) + 0.1, b.x < reach {
                    hurtBoss(6)
                    plants[i].chewing = 5
                    plants[i].gulp = t
                }
            case .cherry:
                if p.timer <= 0 { blasts.append((p.row, p.col)); plants[i].hp = 0 }
            case .chili:
                if p.timer <= 0 { fires.append(p.row); plants[i].hp = 0 }
            case .wallnut, .peel:
                break
            }
        }
        // A cherry bomb flattens the 3×3 tiles around it.
        for b in blasts {
            booms.append(Boom(row: b.row, col: b.col, t: t))
            let lo = Double(b.col) - 0.9, hi = Double(b.col) + 1.9
            for j in zombies.indices where abs(zombies[j].row - b.row) <= 1 && zombies[j].x > lo && zombies[j].x < hi && t >= zombies[j].born {
                kill(j, burnt: true)
            }
            for g in graves.indices where abs(graves[g].row - b.row) <= 1 && abs(graves[g].col - b.col) <= 1 { graves[g].hp = 0 }
            for r in rollers.indices where abs(rollers[r].row - b.row) <= 1 && rollers[r].x > lo - 0.5 && rollers[r].x < hi { rollers[r].hp = 0 }
            if let bs = boss, bs.died == nil, bs.rows.contains(b.row - 1) || bs.rows.contains(b.row) || bs.rows.contains(b.row + 1), bs.x < hi {
                hurtBoss(20, interrupt: true, stun: 1.5)
            }
        }
        // A hot chili burns down its whole lane, thawing anything frozen in it.
        for row in fires {
            blazes.append(Blaze(row: row, t: t))
            for j in zombies.indices where zombies[j].row == row && t >= zombies[j].born { kill(j, burnt: true) }
            for g in graves.indices where graves[g].row == row { graves[g].hp = 0 }
            for r in rollers.indices where rollers[r].row == row { rollers[r].hp = 0 }
            for p in plants.indices where plants[p].row == row { plants[p].frozen = 0 }
            if bossIn(row) {
                hurtBoss(20, interrupt: true, stun: 1.5)
            }
        }
    }

    // MARK: Shots

    /// Peas fly right; the nearest thing in the lane takes the hit (a shield, then headgear, first).
    private mutating func flyPeas(_ dt: Double) {
        var spent = Set<Int>()
        for i in peas.indices {
            peas[i].x += Self.peaSpeed * dt
            let p = peas[i]
            enum Hit { case zombie(Int), grave(Int), roller(Int), boss }
            var best: (x: Double, hit: Hit)? = nil
            for j in zombies.indices where zombies[j].row == p.row && targetable(zombies[j])
                && p.x >= zombies[j].x + 0.05 && p.x <= zombies[j].x + 0.65 && zombies[j].x < (best?.x ?? 99) {
                best = (zombies[j].x, .zombie(j))
            }
            for g in graves.indices where graves[g].row == p.row && graves[g].hp > 0 {
                let gx = Double(graves[g].col) + 0.25
                if p.x >= gx && p.x <= gx + 0.6 && gx < (best?.x ?? 99) { best = (gx, .grave(g)) }
            }
            for r in rollers.indices where rollers[r].row == p.row && rollers[r].hp > 0
                && p.x >= rollers[r].x - 0.1 && p.x <= rollers[r].x + 0.7 && rollers[r].x < (best?.x ?? 99) {
                best = (rollers[r].x, .roller(r))
            }
            if let b = boss, bossIn(p.row), p.x >= b.x + 0.05, p.x <= b.x + 0.95, b.x < (best?.x ?? 99) { best = (b.x, .boss) }
            guard let hit = best?.hit else { continue }
            spent.insert(p.id)
            splats.append(Splat(row: p.row, x: p.x, t: t, shot: p.shot))
            switch hit {
            case .zombie(let j):
                zombies[j].hit = t
                if zombies[j].shield > 0 { zombies[j].shield -= 1; break }
                if p.shot == .frost { zombies[j].slowUntil = t + 4 }
                if zombies[j].armor > 0 { zombies[j].armor -= 1 } else { zombies[j].hp -= 1 }
                if zombies[j].hp <= 0 { kill(j) }
            case .grave(let g):
                graves[g].hp -= 1
            case .roller(let r):
                rollers[r].hp -= rollers[r].kind == .fireball && p.shot == .frost ? 3 : 1
            case .boss:
                hurtBoss(1)
            }
        }
        peas.removeAll { spent.contains($0.id) || $0.x > Double(Self.cols) + 0.6 }
    }

    /// Lobbed melons track their target and land on it, splashing everything close by.
    private mutating func flyLobs() {
        for i in lobs.indices {
            switch lobs[i].target {
            case .zombie(let id): if let z = zombies.first(where: { $0.id == id && $0.died == nil }) { lobs[i].x1 = z.x + 0.2 }
            case .roller(let id): if let r = rollers.first(where: { $0.id == id }) { lobs[i].x1 = r.x + 0.2 }
            case .boss: if let b = boss, b.died == nil { lobs[i].x1 = b.x + 0.3 }
            }
        }
        for l in lobs where t - l.t0 >= Self.lobTime {
            splats.append(Splat(row: l.row, x: l.x1, t: t, shot: .melon))
            var direct = false
            switch l.target {
            case .zombie(let id):
                if let j = zombies.firstIndex(where: { $0.id == id && $0.died == nil }) { wound(j, 3); direct = true }
            case .roller(let id):
                if let r = rollers.firstIndex(where: { $0.id == id }) { rollers[r].hp -= 3; direct = true }
            case .boss:
                if boss?.died == nil, bossIn(l.row) { hurtBoss(3); direct = true }
            }
            for j in zombies.indices where abs(zombies[j].row - l.row) <= 1 && targetable(zombies[j]) && abs(zombies[j].x + 0.2 - l.x1) <= 1.0 {
                if case .zombie(let id) = l.target, zombies[j].id == id { continue }
                wound(j, 1)
            }
            _ = direct
        }
        lobs.removeAll { t - $0.t0 >= Self.lobTime }
    }

    // MARK: Zombies

    /// Zombies eat the plant in front of them, or shamble on toward the house.
    private mutating func zombiesAct(_ dt: Double) {
        for j in zombies.indices where zombies[j].died == nil && t >= zombies[j].born {
            let z = zombies[j]
            if t < z.stunUntil { zombies[j].eating = false; continue }
            let chill = t < z.slowUntil ? 0.5 : 1
            let col = Int(floor(z.x - 0.05))
            if let pi = plants.firstIndex(where: { $0.row == z.row && $0.col == col && $0.hp > 0 }), z.x <= Double(col) + 0.95 {
                let p = plants[pi]
                if p.kind == .peel && p.timer <= 0 {
                    // Armed: it slips, slides back and lies there seeing stars.
                    plants[pi].hp = 0
                    zombies[j].stunUntil = t + 2.5
                    zombies[j].x += 0.6
                    zombies[j].eating = false
                    wound(j, 4)
                    continue
                }
                if z.kind == .jumper && z.hopped < 0 && !p.kind.isBomb {
                    // A jumper vaults the first plant it meets, then walks like anyone else.
                    zombies[j].x = Double(col) - 0.3
                    zombies[j].hopped = t
                    zombies[j].speedK /= LDZombieKind.jumper.pace
                    continue
                }
                zombies[j].eating = true
                plants[pi].hp -= Self.biteRate * chill * dt
                plants[pi].bitten = t
            } else {
                zombies[j].eating = false
                zombies[j].x -= params.speed * z.speedK * chill * dt
            }
            if zombies[j].x < -0.05 { reachHouse(z.row) }
        }
        plants.removeAll { $0.hp <= 0 }
    }

    private mutating func reachHouse(_ row: Int) {
        switch mowers[row] {
        case .ready: mowers[row] = .running(-0.5)
        case .running: break
        case .gone: lost = true
        }
    }

    // MARK: Boss

    private mutating func arrive(_ kind: LDBossKind) {
        let row = kind.span == 1 ? params.rows[rng.int(params.rows.count)] : min(5 - kind.span, 1 + rng.int(max(1, 4 - kind.span)))
        boss = Boss(kind: kind, maxHP: params.bossHP, hp: params.bossHP, row: row, y: Double(row), x: Double(Self.cols) + 0.9)
        boss!.arrivedAt = t
    }

    /// Squash what's planted on a tile (a wall-nut takes a big bite instead; a lit bomb can't be squashed).
    private mutating func crush(_ row: Int, _ col: Int) {
        guard let i = plants.firstIndex(where: { $0.row == row && $0.col == col && !$0.kind.isBomb }) else { return }
        if plants[i].kind == .wallnut && plants[i].hp > 18 { plants[i].hp -= 18; plants[i].bitten = t } else { plants[i].hp = 0 }
    }

    /// A standing boss flattens whatever was planted where it plants its feet.
    private mutating func settle() {
        guard let b = boss else { return }
        for r in b.rows { crush(r, Self.cols - 1) }
        plants.removeAll { $0.hp <= 0 }
    }

    private mutating func bossAct(_ dt: Double) {
        guard let b = boss, b.died == nil else { return }
        if t < b.stunUntil && b.mode != .arriving { return }
        switch b.mode {
        case .arriving:
            if b.kind.span == 1 {
                boss!.x -= 0.5 * dt
                if boss!.x <= Double(Self.cols) - 0.2 { boss!.mode = .walking; boss!.clock = params.bossEvery }
            } else {
                boss!.x = max(Boss.home, b.x - 0.9 * dt)
                if boss!.x <= Boss.home { boss!.mode = .standing; boss!.clock = 2; settle() }
            }
        case .walking:
            walk(dt)
        case .shifting:
            let goal = Double(b.row)
            boss!.y += (goal > b.y ? 1 : -1) * min(abs(goal - b.y), dt / 1.2)
            if abs(boss!.y - goal) < 0.0001 {
                boss!.y = goal
                boss!.mode = b.kind.span == 1 ? .walking : .standing
                if b.kind.span > 1 { settle() }
            }
        case .charging:
            charge(dt)
        case .retreating:
            boss!.x = min(Boss.home, b.x + 1.5 * dt)
            if boss!.x >= Boss.home { boss!.mode = .standing; boss!.clock = params.bossEvery * 0.7; settle() }
        case .standing:
            if let m = b.move {
                boss!.windup -= dt
                guard boss!.windup <= 0 else { return }
                perform(m)
                guard boss?.died == nil else { return }
                boss!.move = nil
                boss!.lastAt = t
                boss!.lastTargets = boss!.targets
                boss!.targets = []
                boss!.last = m
                boss!.moves += 1
                boss!.clock = params.bossEvery
                // Every second move it lumbers over to other lanes.
                if boss!.moves % 2 == 0 && boss!.mode == .standing {
                    let options = (0...(5 - b.kind.span)).filter { $0 != b.row }
                    boss!.row = options[rng.int(options.count)]
                    boss!.mode = .shifting
                }
            } else {
                boss!.clock -= dt
                guard boss!.clock <= 0 else { return }
                let pool = b.kind.moves.filter { $0 != b.last || b.kind.moves.count == 1 }
                let m = pool[rng.int(pool.count)]
                let targets = aim(m)
                boss!.move = m
                boss!.windup = m.windup
                boss!.targets = targets
            }
        }
    }

    /// The groundskeeper: walks its lane, smashing every plant in its way, and steps into a quieter lane now and then.
    private mutating func walk(_ dt: Double) {
        let b = boss!
        // Hurt badly while still far up the lawn, it flings its imp ahead (never right onto the patio).
        if !b.threw && b.hp < b.maxHP / 2 && b.x >= 3.6 {
            boss!.threw = true
            drops.append(Drop(id: newID(), kind: .imp, row: b.row, x: b.x - 2.6, fromX: b.x + 0.4, t0: t, lands: t + 1.1))
        }
        boss!.clock -= dt
        let col = Int(floor(b.x - 0.05))
        if let pi = plants.firstIndex(where: { $0.row == b.row && $0.col == col && $0.hp > 0 && !$0.kind.isBomb }), b.x <= Double(col) + 0.95 {
            if plants[pi].kind == .peel && plants[pi].timer <= 0 {
                // Even a giant goes down on a banana peel.
                plants[pi].hp = 0
                plants.removeAll { $0.hp <= 0 }
                boss!.x += 0.5
                hurtBoss(8, stun: 3)
                return
            }
            // Wind up, then smash.
            if boss!.windup <= 0 { boss!.windup = 0.8 }
            boss!.windup -= dt
            if boss!.windup <= 0 {
                boss!.smashed = t
                crashes.append(Crash(row: b.row, col: col, t: t))
                plants[pi].hp = 0
                plants.removeAll { $0.hp <= 0 }
            }
            return
        }
        boss!.windup = 0
        if boss!.clock <= 0 {
            // Now and then it lumbers into a neighbouring lane.
            boss!.clock = params.bossEvery
            let options = [b.row - 1, b.row + 1].filter { params.rows.contains($0) }
            if !options.isEmpty && rng.unit() < 0.6 {
                boss!.row = options[rng.int(options.count)]
                boss!.mode = .shifting
                return
            }
        }
        boss!.x -= params.speed * 0.55 * dt
        if boss!.x < -0.05 {
            if case .ready = mowers[b.row] {
                // The mower can't stop it, but it hurts and knocks it back up the lawn.
                mowers[b.row] = .running(-0.5)
                boss!.x = 2.5
                hurtBoss(b.maxHP * 0.25, stun: 2)
            } else {
                lost = true
            }
        }
    }

    /// The locomotive's charge down its lanes to mid-lawn, crushing plants and zombies alike. A banana peel
    /// derails it; a sound wall-nut takes the blow and stops it.
    private mutating func charge(_ dt: Double) {
        boss!.x -= 3 * dt
        let b = boss!
        let col = Int(floor(b.x))
        for r in b.rows {
            if col >= 0, let pi = plants.firstIndex(where: { $0.row == r && $0.col == col && !$0.kind.isBomb }) {
                let p = plants[pi]
                if p.kind == .peel && p.timer <= 0 {
                    plants[pi].hp = 0
                    plants.removeAll { $0.hp <= 0 }
                    boss!.mode = .retreating
                    hurtBoss(8, stun: 3)
                    return
                }
                crashes.append(Crash(row: r, col: col, t: t))
                if p.kind == .wallnut && p.hp > 18 {
                    crush(r, col)
                    boss!.x = Double(col) + 1
                    boss!.mode = .retreating
                    boss!.stunUntil = t + 1
                    return
                }
                crush(r, col)
            }
            for j in zombies.indices where zombies[j].row == r && zombies[j].died == nil && zombies[j].x > b.x - 0.2 && zombies[j].x < b.x + 1.2 { kill(j) }
        }
        plants.removeAll { $0.hp <= 0 }
        if b.x <= Self.chargeStop { boss!.mode = .retreating }
    }

    /// Who drops in on an ambush tile (fixed by the tile, so the view can show them coming).
    static func ambusher(_ tile: LDTile) -> LDZombieKind { [.imp, .normal, .imp, .cone][(tile.row + tile.col) % 4] }

    /// Picks what a move aims at when its windup starts (the view telegraphs it).
    private mutating func aim(_ m: LDBossMove) -> [LDTile] {
        let b = boss!
        let n = params.bossPower
        switch m {
        case .summon, .charge:
            return []
        case .laser:
            return b.rows.map { LDTile(row: $0, col: -1) }
        case .ambush:
            return (0..<n).map { _ in LDTile(row: params.rows[rng.int(params.rows.count)], col: 3 + rng.int(2)) }
        case .graves:
            var free: [LDTile] = []
            for r in params.rows { for c in 1...5 where plant(at: r, c) == nil && grave(at: r, c) == nil && !bossCovers(r, c) { free.append(LDTile(row: r, col: c)) } }
            var picks: [LDTile] = []
            for _ in 0..<n where !free.isEmpty { picks.append(free.remove(at: rng.int(free.count))) }
            return picks
        case .bombard:
            // Shooters and sunflowers draw fire first.
            var pool: [LDTile] = []
            for p in plants where !p.kind.isBomb {
                let w = p.kind.shoots || p.kind == .lobber ? 3 : (p.kind == .sunflower ? 2 : 1)
                for _ in 0..<w { pool.append(LDTile(row: p.row, col: p.col)) }
            }
            var picks: [LDTile] = []
            for _ in 0..<(n + 1) where !pool.isEmpty {
                let pick = pool[rng.int(pool.count)]
                picks.append(pick)
                pool.removeAll { $0 == pick }
            }
            return picks
        case .freeze, .roll:
            // Its own lane with the most plants.
            let lanes = Array(b.rows)
            let row = lanes.max { a, c in plants.filter { $0.row == a }.count < plants.filter { $0.row == c }.count } ?? b.row
            return [LDTile(row: row, col: -1)]
        case .stomp:
            return b.rows.flatMap { r in [LDTile(row: r, col: 3), LDTile(row: r, col: 4)] }
        }
    }

    private mutating func perform(_ m: LDBossMove) {
        guard let b = boss else { return }
        switch m {
        case .summon:
            let pool = params.mix.map { $0.0 }
            for _ in 0..<params.bossPower {
                let plain = pool.isEmpty || rng.unit() < 0.4
                let kind = plain ? LDZombieKind.normal : pool[rng.int(pool.count)]
                addZombie(kind, row: params.rows[rng.int(params.rows.count)], x: Double(Self.cols) + 0.4)
            }
        case .ambush:
            for tile in b.targets { addZombie(Self.ambusher(tile), row: tile.row, x: Double(tile.col) + 0.6) }
        case .graves:
            for tile in b.targets where plant(at: tile.row, tile.col) == nil && grave(at: tile.row, tile.col) == nil {
                graves.append(Grave(id: newID(), row: tile.row, col: tile.col, hp: 8, born: t))
            }
        case .bombard, .stomp:
            for tile in b.targets {
                crashes.append(Crash(row: tile.row, col: tile.col, t: t))
                crush(tile.row, tile.col)
            }
            plants.removeAll { $0.hp <= 0 }
        case .charge:
            boss!.mode = .charging
        case .freeze:
            if let row = b.targets.first?.row {
                for i in plants.indices where plants[i].row == row && !plants[i].kind.isBomb { plants[i].frozen = 7 }
            }
        case .roll:
            if let row = b.targets.first?.row {
                let kind: LDRollerKind = b.kind == .mammoth ? .snowball : (b.moves % 2 == 0 ? .fireball : .iceball)
                rollers.append(Roller(id: newID(), kind: kind, row: row, x: b.x - 0.3, hp: kind == .snowball ? 14 : 10, born: t))
            }
        case .laser:
            for r in b.rows {
                if let p = plants.filter({ $0.row == r && !$0.kind.isBomb }).max(by: { $0.col < $1.col }) {
                    crashes.append(Crash(row: r, col: p.col, t: t))
                    crush(r, p.col)
                }
            }
            plants.removeAll { $0.hp <= 0 }
        }
    }

    // MARK: Rolling balls

    /// Snowballs, fireballs and iceballs roll down a lane flattening plants; a sound wall-nut shatters them,
    /// and one that reaches the end wrecks the lane's mower.
    private mutating func rollersAct(_ dt: Double) {
        for i in rollers.indices where rollers[i].hp > 0 {
            rollers[i].x -= Self.rollSpeed * dt
            let r = rollers[i]
            let col = Int(floor(r.x - 0.05))
            if col >= 0, let pi = plants.firstIndex(where: { $0.row == r.row && $0.col == col && !$0.kind.isBomb }), r.x <= Double(col) + 0.9 {
                crashes.append(Crash(row: r.row, col: col, t: t))
                if plants[pi].kind == .wallnut && plants[pi].hp > 18 {
                    crush(r.row, col)
                    rollers[i].hp = 0
                    continue
                }
                plants[pi].hp = 0
            }
            if r.x < -0.2 {
                if case .ready = mowers[r.row] { mowers[r.row] = .gone }
                rollers[i].hp = 0
            }
        }
        plants.removeAll { $0.hp <= 0 }
    }
}

// MARK: - View

struct LawnDefenseView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var world: LDWorld
    @State private var selected: LDPlantKind?
    @State private var built = false
    @State private var shake = 0
    // Demo-only: the finger.
    @State private var demoFinger: CGPoint?          // in lawn coordinates (tiles, rows)
    @State private var demoTap = 0
    @State private var demoPacket: LDPlantKind?

    init(level: Int, onWin: @escaping () -> Void, onFail: @escaping () -> Void) {
        self.level = level
        self.onWin = onWin
        self.onFail = onFail
        // The level's own world from the first frame (run() reseeds it).
        _world = State(initialValue: LDWorld(params: LDParams.level(level), seed: 1))
    }

    private var scene: LDScene { world.params.scene }

    var body: some View {
        VStack(spacing: isDemo ? 4 : 8) {
            seedBar
            lawn
            meter
                .frame(height: isDemo ? 14 : 22)
                .padding(.horizontal, isDemo ? 40 : 56)
                .padding(.bottom, isDemo ? 6 : 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LDBackdrop(scene: scene).equatable())
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .screenShake(shake, amount: 5)
        .task { isDemo ? await runDemo() : await run() }
    }

    // MARK: Layout

    /// The lawn's tile grid inside the play area: the mower strip on the left, the street on the right.
    private func layout(_ s: CGSize) -> LDLayout {
        let shown = isDemo ? world.params.rows : Array(0..<5)
        return LDLayout(size: s, rows: shown)
    }

    // MARK: HUD

    /// The seed bar: the sun counter, then the packets (in two rows when there are many).
    private var seedBar: some View {
        let packets = world.params.packets
        let perRow = packets.count > 6 ? (packets.count + 1) / 2 : max(1, packets.count)
        let lines = stride(from: 0, to: packets.count, by: perRow).map { Array(packets[$0..<min(packets.count, $0 + perRow)]) }
        return HStack(spacing: isDemo ? 5 : 8) {
            VStack(spacing: 0) {
                Canvas { ctx, s in LDLawnArt.sun(ctx, at: CGPoint(x: s.width / 2, y: s.height / 2), r: min(s.width, s.height) * 0.36, t: world.t) }
                    .frame(width: isDemo ? 28 : 40, height: isDemo ? 26 : 38)
                Text(verbatim: String(world.sun))
                    .font(.system(size: isDemo ? 13 : 17, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Color(red: 0.25, green: 0.15, blue: 0.05))
                    .padding(.horizontal, 6)
                    .background(Capsule().fill(Color(red: 0.96, green: 0.9, blue: 0.72)))
            }
            .frame(width: isDemo ? 46 : 58)
            VStack(alignment: .leading, spacing: isDemo ? 4 : 5) {
                ForEach(lines.indices, id: \.self) { i in
                    HStack(spacing: isDemo ? 4 : 6) {
                        ForEach(lines[i], id: \.rawValue) { kind in packet(kind) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, isDemo ? 6 : 8)
        .padding(.vertical, isDemo ? 4 : 6)
        .background(LDSeedBar(scene: scene).equatable())
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(LDLawnArt.barEdge(scene), lineWidth: 2))
        .padding(.horizontal, isDemo ? 8 : 10)
        .padding(.top, isDemo ? 6 : 10)
    }

    private func packet(_ kind: LDPlantKind) -> some View {
        let ready = world.canPlant(kind)
        let charge = world.recharge[kind.rawValue] / kind.recharge
        let picked = selected == kind || (isDemo && demoPacket == kind)
        return Button {
            guard phase == .play else { return }
            if selected == kind { selected = nil } else if world.canPlant(kind) {
                selected = kind
                SoundManager.shared.tap()
            } else {
                SoundManager.shared.error()
            }
        } label: {
            LDPacketFace(kind: kind, cost: kind.cost, ready: ready, charge: charge, picked: picked)
                .frame(width: isDemo ? 38 : 50, height: isDemo ? 48 : 60)
        }
        .buttonStyle(LDPacketStyle())
    }

    /// The flag meter while the horde arrives; the boss's health bar once it's here.
    private var meter: some View {
        Canvas { ctx, s in
            if let b = world.boss {
                LDLawnArt.bossMeter(ctx, size: s, boss: b, t: world.t)
            } else {
                LDLawnArt.flagMeter(ctx, size: s, progress: world.progress, rushAt: rushFraction, boss: world.params.boss)
            }
        }
    }

    private var rushFraction: Double {
        let n = world.schedule.count
        return n == 0 ? 1 : Double(n - min(world.params.finalWave, n)) / Double(n)
    }

    // MARK: Lawn

    private var lawn: some View {
        GeometryReader { geo in
            let lay = layout(geo.size)
            ZStack {
                LDLawn(size: geo.size, scene: scene, rowsInPlay: world.params.rows, shown: lay.rows).equatable()
                Canvas { ctx, _ in
                    LDLawnArt.scene(ctx, world: world, lay: lay, selected: selected ?? (isDemo ? demoPacket : nil))
                }
                .allowsHitTesting(false)
                if isDemo, let f = demoFinger {
                    let p = lay.point(x: f.x, y: f.y)
                    DemoTapRipple().id(demoTap).position(p)
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: lay.cellW * 0.7))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 3)
                        .position(x: p.x + lay.cellW * 0.3, y: p.y + lay.cellW * 0.42)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { loc in tapLawn(loc, lay) }
        }
        .padding(.horizontal, isDemo ? 4 : 6)
    }

    private func tapLawn(_ loc: CGPoint, _ lay: LDLayout) {
        guard phase == .play, !isDemo else { return }
        // Suns sit on top: a tap near one picks it up.
        if let s = world.suns.min(by: { hypot(lay.point(x: $0.x, y: $0.y).x - loc.x, lay.point(x: $0.x, y: $0.y).y - loc.y)
                                       < hypot(lay.point(x: $1.x, y: $1.y).x - loc.x, lay.point(x: $1.x, y: $1.y).y - loc.y) }),
           hypot(lay.point(x: s.x, y: s.y).x - loc.x, lay.point(x: s.x, y: s.y).y - loc.y) < lay.cellW * 0.62 {
            if world.collect(s.id) { SoundManager.shared.tap(); Haptics.tap() }
            return
        }
        guard let kind = selected else { return }
        let (x, y) = lay.tile(loc)
        let row = Int(floor(y)), col = Int(floor(x))
        if world.plant(kind, row: row, col: col) {
            selected = nil
            SoundManager.shared.tap(); Haptics.tap()
        } else {
            SoundManager.shared.error()
        }
    }

    // MARK: Flow

    private func run() async {
        if !built {
            world = LDWorld(params: LDParams.level(level), seed: UInt64.random(in: 1...UInt64.max))
            built = true
        }
        var last = Date()
        while !Task.isCancelled && phase == .play {
            try? await Task.sleep(for: .seconds(0.016))
            let now = Date()
            let dt = min(0.05, now.timeIntervalSince(last)); last = now
            advance(dt)
        }
    }

    /// What the feedback watches between two ticks.
    private struct Pulse {
        let mowers: Int
        let boom: Double
        let blaze: Double
        let crash: Double
        let boss: Bool
        let bossDown: Bool

        init(_ w: LDWorld) {
            mowers = w.mowers.filter { if case .ready = $0 { return true } else { return false } }.count
            boom = w.booms.last?.t ?? -1
            blaze = w.blazes.last?.t ?? -1
            crash = w.crashes.last?.t ?? -1
            boss = w.boss != nil
            bossDown = w.boss?.died != nil
        }
    }

    /// One tick of the real world plus the sounds, the shakes and the outcome.
    private func advance(_ dt: Double) {
        let before = Pulse(world)
        world.step(dt)
        let after = Pulse(world)
        if after.mowers < before.mowers { shake += 1; SoundManager.shared.error(); Haptics.warning() }
        if after.boom > before.boom || after.blaze > before.blaze { shake += 1; Haptics.warning() }
        if after.crash > before.crash { shake += 1; Haptics.tap() }
        if after.boss && !before.boss { shake += 1; Haptics.warning() }
        if after.bossDown && !before.bossDown { shake += 1; Haptics.success() }
        if world.lost { fail() } else if world.won { win() }
    }

    // MARK: Demo (live manual clip)
    // The backyard on a fixed seed with three lanes and a short horde, stepped at 1/60 s through the real
    // world. The lawn is already under way (a sunflower in every lane, shooters in the outer lanes); the
    // finger presses the corn popper packet and plants the middle lane, picking up every sun as it lands.
    // Then a small groundskeeper walks up the middle lane and the finger drops a cherry bomb in front of
    // him: his health bar empties, he topples, and that is the real win.
    private static let demoHorde: [(t: Double, row: Int, kind: LDZombieKind)] = [(0.7, 2, .normal), (1.3, 1, .normal), (1.9, 3, .flag)]

    private func demoSetup() {
        var p = LDParams.level(1)
        p.rows = [1, 2, 3]
        p.packets = [.sunflower, .peashooter, .popper, .peel, .cherry]
        var w = LDWorld(params: p, seed: 7)
        w.schedule = Self.demoHorde
        w.sun = 225
        w.skyTimer = 1.2
        var id = 100
        for r in p.rows {
            w.plants.append(LDWorld.Plant(id: id, kind: .sunflower, row: r, col: 0, hp: LDPlantKind.sunflower.bites,
                                          timer: 1.6 + Double(r) * 0.7, planted: -5))
            id += 1
            if r != 2 {
                for (c, k) in [(1, LDPlantKind.popper), (2, .peashooter)] {
                    w.plants.append(LDWorld.Plant(id: id, kind: k, row: r, col: c, hp: k.bites, timer: 0.4, planted: -5))
                    id += 1
                }
            }
        }
        world = w
        selected = nil
        demoFinger = nil
        demoPacket = nil
    }

    private func runDemo() async {
        let dt = 1.0 / 60.0
        while !Task.isCancelled {
            demoSetup()
            phase = .play
            var plan: [(kind: LDPlantKind, row: Int, col: Int)] = [(.popper, 2, 1)]
            var pressT = -1.0
            var frames = 0
            var bombed = false
            while !Task.isCancelled && !world.won && !world.lost && frames < 60 * 30 {
                // The boss walks on early, up the middle lane.
                if world.boss == nil && world.t >= 2.2 {
                    world.boss = LDWorld.Boss(kind: .groundskeeper, maxHP: 16, hp: 16, row: 2, y: 2, x: Double(LDWorld.cols) + 0.9)
                    world.boss?.arrivedAt = world.t
                }
                if let s = world.suns.first(where: { $0.y >= $0.landY && world.t - $0.born > 0.9 }) {
                    // Pick up any sun that has landed.
                    demoFinger = CGPoint(x: s.x, y: s.y); demoTap += 1
                    world.collect(s.id)
                } else if !bombed, let b = world.boss, b.mode == .walking, b.x < 6.4, world.canPlant(.cherry) {
                    // Press the cherry bomb, then drop it right in front of him.
                    if demoPacket != .cherry { demoPacket = .cherry; pressT = world.t }
                    else if world.t - pressT > 0.45 {
                        let col = max(0, min(LDWorld.cols - 1, Int(floor(b.x - 0.6))))
                        demoFinger = CGPoint(x: Double(col) + 0.5, y: Double(b.row) + 0.55); demoTap += 1
                        world.plant(.cherry, row: b.row, col: col)
                        demoPacket = nil
                        bombed = true
                    }
                } else if let step = plan.first {
                    // Plant: press the packet once it's ready and affordable, then tap the tile.
                    if demoPacket == nil && world.t > 0.3 && world.canPlant(step.kind) {
                        demoPacket = step.kind; pressT = world.t
                    } else if demoPacket == step.kind && world.t - pressT > 0.5 {
                        demoFinger = CGPoint(x: Double(step.col) + 0.5, y: Double(step.row) + 0.55); demoTap += 1
                        world.plant(step.kind, row: step.row, col: step.col)
                        demoPacket = nil
                        plan.removeFirst()
                    }
                }
                world.step(dt)
                frames += 1
                try? await Task.sleep(for: .seconds(0.016))
            }
            // The horde and its boss are down (the real win state). Hold, then loop.
            demoFinger = nil
            for _ in 0..<80 {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(0.016))
            }
        }
    }

    private func win() {
        guard phase == .play else { return }
        phase = .done
        selected = nil
        SoundManager.shared.tap(); Haptics.tap()
        onWin()
    }

    private func fail() {
        guard phase == .play else { return }
        phase = .done
        selected = nil
        SoundManager.shared.error(); Haptics.warning()
        onFail()
    }
}

// MARK: - Layout

/// Maps lawn coordinates (x in tiles from the house, y in rows) to points, and back.
struct LDLayout {
    let rows: [Int]               // the rows on screen (all five, or the demo's three)
    let cellW: CGFloat
    let cellH: CGFloat
    let origin: CGPoint           // top-left of tile (0, rows.first)
    let size: CGSize

    init(size: CGSize, rows: [Int]) {
        self.size = size
        self.rows = rows
        // House strip 0.62 tile, seven tiles, street 0.78 tile. Tiles are taller than wide and stretch
        // (up to 1.62×) to fill a tall screen; whatever height is left goes mostly to the yard below.
        let byWidth = size.width / 8.4
        let byHeight = size.height / (CGFloat(rows.count) * 1.36 + 0.7)
        cellW = min(byWidth, byHeight)
        cellH = min(cellW * 1.62, max(cellW * 1.36, (size.height - cellW * 0.7) / CGFloat(rows.count)))
        let lawnW = cellW * 8.4, lawnH = cellH * CGFloat(rows.count)
        let spare = max(0, size.height - lawnH - cellW * 0.6)
        origin = CGPoint(x: (size.width - lawnW) / 2 + cellW * 0.62, y: cellW * 0.6 + spare * 0.3)
    }

    func point(x: Double, y: Double) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(x) * cellW, y: origin.y + (CGFloat(y) - CGFloat(rows.first ?? 0)) * cellH)
    }

    func tile(_ p: CGPoint) -> (x: Double, y: Double) {
        (Double((p.x - origin.x) / cellW), Double((p.y - origin.y) / cellH) + Double(rows.first ?? 0))
    }
}
