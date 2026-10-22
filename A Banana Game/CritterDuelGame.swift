//
//  CritterDuelGame.swift
//  A Banana Game
//
//  Brain — a turn-based critter battle in the style of the classic handheld monster RPGs. Your
//  partner, Banano (a grass-type banana), faces a line of rival critters one at a time. Each turn you
//  pick one of four moves: three attacks of different types and a banana Snack that heals. Types
//  matter: grass beats water, water beats fire, fire beats grass, and electric beats water. The right
//  type hits twice as hard, the wrong one half as hard. Knock out every rival to win; faint, or run
//  out the clock, and you're back to level 1.
//
//  7 levels: one weak rival at level 1, then two, then three, ending with a bell-pepper boss; rivals
//  gain levels and stronger moves, and their trainer goes from picking moves at random to always
//  picking the one that hurts you most. Banano's health carries over between rivals and the two
//  Snacks are all the healing you get. Tuned with a bot that always picks the best move and snacks
//  when the next hit could knock Banano out: it wins every level-1 and -2 battle, about 94/80/68% of
//  levels 3–5, 24% of level 6 and 3% of level 7 (a player mashing random moves wins half of level 3
//  and none of 6–7). There's no same-type bonus, so a fire rival can't knock Banano out in one hit
//  from full health.
//
//  Drawn like the handheld games' battle screen: a sky-and-meadow field, grass platforms, the rival
//  facing you and Banano seen from behind, cream HP boxes with green/yellow/red bars and the type
//  shown as an icon, a teal message box, and the four type-coloured move buttons. The critters are
//  original fruit creatures (coconut, chili, lemon, watermelon, blueberry, bell pepper).
//
//  The rules are `CDBattle`, a plain value: one call resolves a whole turn and returns the events,
//  which the view then plays back. The demo and the balance bot use the same code.
//

import SwiftUI

enum CritterDuelGame {
    static let definition = GameDefinition(
        id: "critter-duel",
        title: "Critter Duel",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Tap a move to attack; the rival answers every turn, and the faster critter goes first.",
                "Grass beats water, water beats fire, fire beats grass, electric beats water: the right type does double damage.",
                "The banana Snack heals Banano, but only twice. Knock out every rival to win.",
                "If Banano faints or time runs out, you're back to level 1.",
            ],
            bulletsVI: [
                "Chạm một chiêu để tấn công; đối thủ đánh trả mỗi lượt, con nào nhanh hơn ra đòn trước.",
                "Cỏ thắng nước, nước thắng lửa, lửa thắng cỏ, điện thắng nước: đúng hệ gây sát thương gấp đôi.",
                "Món Ăn Vặt chuối hồi máu cho Banano, nhưng chỉ hai lần. Hạ hết đối thủ để thắng.",
                "Nếu Banano gục hoặc hết giờ, bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(CritterDuelView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

// MARK: - Rules

enum CDType: Int {
    case normal, grass, fire, water, electric

    /// Damage multiplier when a move of this type hits a critter of type `defender`.
    func against(_ defender: CDType) -> Double {
        switch (self, defender) {
        case (.grass, .water), (.water, .fire), (.fire, .grass), (.electric, .water): return 2
        case (.grass, .grass), (.grass, .fire), (.fire, .fire), (.fire, .water), (.water, .water), (.water, .grass),
             (.electric, .electric), (.electric, .grass): return 0.5
        default: return 1
        }
    }
}

struct CDMove {
    let en: String
    let vi: String
    let type: CDType
    let power: Int
    let accuracy: Double
    let heals: Bool
    let pp: Int
}

enum CDMoves {
    static let tackle = 0, leafCut = 1, bubble = 2, ember = 3, snack = 4, zap = 5, flare = 6, bolt = 7, torrent = 8, seedStorm = 9
    static let all: [CDMove] = [
        CDMove(en: "Tackle", vi: "Húc", type: .normal, power: 40, accuracy: 1, heals: false, pp: 99),
        CDMove(en: "Leaf Cut", vi: "Cắt Lá", type: .grass, power: 55, accuracy: 1, heals: false, pp: 99),
        CDMove(en: "Bubble", vi: "Bong Bóng", type: .water, power: 50, accuracy: 1, heals: false, pp: 99),
        CDMove(en: "Ember", vi: "Than Hồng", type: .fire, power: 50, accuracy: 1, heals: false, pp: 99),
        CDMove(en: "Snack", vi: "Ăn Vặt", type: .normal, power: 0, accuracy: 1, heals: true, pp: 2),
        CDMove(en: "Zap", vi: "Chích Điện", type: .electric, power: 50, accuracy: 1, heals: false, pp: 99),
        CDMove(en: "Flare", vi: "Bùng Lửa", type: .fire, power: 80, accuracy: 0.8, heals: false, pp: 99),
        CDMove(en: "Bolt", vi: "Sét Đánh", type: .electric, power: 80, accuracy: 0.8, heals: false, pp: 99),
        CDMove(en: "Torrent", vi: "Thác Nước", type: .water, power: 80, accuracy: 0.8, heals: false, pp: 99),
        CDMove(en: "Seed Storm", vi: "Bão Hạt", type: .grass, power: 80, accuracy: 0.8, heals: false, pp: 99),
    ]
}

struct CDSpecies {
    let name: String
    let type: CDType
    let hp: Int, atk: Int, def: Int, spd: Int
    let moves: [Int]              // weakest first; low-level rivals only know the first two
}

enum CDDex {
    static let banano = 0, coconutty = 1, chilipep = 2, lemonzap = 3, melonox = 4, blubbery = 5, pepperoar = 6
    static let all: [CDSpecies] = [
        CDSpecies(name: "Banano", type: .grass, hp: 60, atk: 56, def: 52, spd: 62,
                  moves: [CDMoves.leafCut, CDMoves.bubble, CDMoves.ember, CDMoves.snack]),
        CDSpecies(name: "Coconutty", type: .water, hp: 55, atk: 46, def: 62, spd: 35, moves: [CDMoves.tackle, CDMoves.bubble, CDMoves.torrent]),
        CDSpecies(name: "Chilipep", type: .fire, hp: 45, atk: 62, def: 42, spd: 68, moves: [CDMoves.tackle, CDMoves.ember, CDMoves.flare]),
        CDSpecies(name: "Lemonzap", type: .electric, hp: 46, atk: 58, def: 46, spd: 78, moves: [CDMoves.tackle, CDMoves.zap, CDMoves.bolt]),
        CDSpecies(name: "Melonox", type: .grass, hp: 70, atk: 52, def: 64, spd: 30, moves: [CDMoves.tackle, CDMoves.leafCut, CDMoves.seedStorm]),
        CDSpecies(name: "Blubbery", type: .water, hp: 50, atk: 55, def: 50, spd: 55, moves: [CDMoves.tackle, CDMoves.bubble, CDMoves.torrent]),
        CDSpecies(name: "Pepperoar", type: .fire, hp: 70, atk: 58, def: 50, spd: 50, moves: [CDMoves.tackle, CDMoves.ember, CDMoves.flare]),
    ]
}

struct CDRandom {
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

struct CDCritter {
    let species: Int
    let level: Int
    let maxHP: Int
    var hp: Int
    let atk: Int, def: Int, spd: Int
    let moves: [Int]
    var pp: [Int]

    init(species: Int, level: Int, knownMoves: Int = 4) {
        let s = CDDex.all[species]
        self.species = species
        self.level = level
        maxHP = 2 * s.hp * level / 100 + level + 10
        hp = maxHP
        atk = 2 * s.atk * level / 100 + 5
        def = 2 * s.def * level / 100 + 5
        spd = 2 * s.spd * level / 100 + 5
        moves = Array(s.moves.prefix(knownMoves))
        pp = moves.map { CDMoves.all[$0].pp }
    }

    var name: String { CDDex.all[species].name }
    var type: CDType { CDDex.all[species].type }
}

/// What happened in a turn, in order, for the view to play back.
enum CDEvent {
    case use(foe: Bool, move: Int)
    case hit(foe: Bool, amount: Int, mult: Double, crit: Bool)   // `foe`: the one taking the hit
    case miss(foe: Bool)
    case heal(foe: Bool, amount: Int)
    case faint(foe: Bool)
    case send(index: Int)
}

/// One level's battle. `turn(_:)` resolves a whole turn: both critters act, fastest first (a Snack
/// always goes first), and a knocked-out rival is replaced by the next one.
struct CDBattle {
    var you: CDCritter
    var foes: [CDCritter]
    var current = 0
    let smart: Double             // chance the rival's trainer picks the move that hurts you most
    var rng: CDRandom

    var foe: CDCritter? { current < foes.count ? foes[current] : nil }
    var won: Bool { current >= foes.count }
    var lost: Bool { you.hp <= 0 }

    /// Seconds on the clock for each level.
    static func timeLimit(_ level: Int) -> Double { [60, 60, 75, 80, 90, 105, 110][min(max(level, 1), 7) - 1] }

    static func level(_ level: Int, seed: UInt64) -> CDBattle {
        var rng = CDRandom(state: seed)
        let i = min(max(level, 1), 7) - 1
        let yourLevel = [10, 10, 11, 12, 13, 14, 15][i]
        let pools: [[Int]] = [
            [CDDex.coconutty, CDDex.blubbery],
            [CDDex.chilipep, CDDex.melonox, CDDex.lemonzap],
            [CDDex.coconutty, CDDex.chilipep, CDDex.lemonzap, CDDex.melonox, CDDex.blubbery],
            [CDDex.coconutty, CDDex.chilipep, CDDex.lemonzap, CDDex.melonox, CDDex.blubbery],
            [CDDex.coconutty, CDDex.chilipep, CDDex.lemonzap, CDDex.melonox, CDDex.blubbery],
            [CDDex.chilipep, CDDex.lemonzap, CDDex.melonox, CDDex.blubbery, CDDex.coconutty],
            [CDDex.chilipep, CDDex.lemonzap, CDDex.melonox, CDDex.blubbery, CDDex.coconutty],
        ]
        let count = [1, 1, 2, 2, 2, 3, 3][i]
        let foeLevels = [[8], [9], [9, 10], [11, 12], [13, 14], [14, 15, 15], [15, 16, 17]][i]
        let known = [2, 2, 2, 3, 3, 3, 3][i]
        var pool = pools[i]
        var foes: [CDCritter] = []
        for k in 0..<count {
            // The level-7 finale is always the bell-pepper boss.
            let species: Int
            if i == 6 && k == count - 1 { species = CDDex.pepperoar } else { species = pool.remove(at: rng.int(pool.count)) }
            foes.append(CDCritter(species: species, level: foeLevels[k], knownMoves: known))
        }
        return CDBattle(you: CDCritter(species: CDDex.banano, level: yourLevel), foes: foes,
                        smart: [0, 0.25, 0.5, 0.7, 0.85, 1, 1][i], rng: rng)
    }

    /// Expected damage of `move` from `a` onto `d` (no crits or misses) — the trainer's yardstick.
    static func expected(_ move: Int, from a: CDCritter, to d: CDCritter) -> Double {
        let m = CDMoves.all[move]
        guard !m.heals else { return 0 }
        return base(m, a, d) * m.type.against(d.type) * 0.925 * m.accuracy
    }

    private static func base(_ m: CDMove, _ a: CDCritter, _ d: CDCritter) -> Double {
        (Double(2 * a.level / 5 + 2) * Double(m.power) * Double(a.atk) / Double(d.def)) / 50 + 2
    }

    private mutating func strike(_ move: Int, attackerIsFoe: Bool) -> [CDEvent] {
        var out: [CDEvent] = [.use(foe: attackerIsFoe, move: move)]
        let m = CDMoves.all[move]
        if attackerIsFoe {
            if let i = foes[current].moves.firstIndex(of: move) { foes[current].pp[i] -= 1 }
        } else if let i = you.moves.firstIndex(of: move) {
            you.pp[i] -= 1
        }
        let a = attackerIsFoe ? foes[current] : you
        if m.heals {
            let amount = min(a.maxHP - a.hp, a.maxHP / 2)
            if attackerIsFoe { foes[current].hp += amount } else { you.hp += amount }
            out.append(.heal(foe: attackerIsFoe, amount: amount))
            return out
        }
        if rng.unit() > m.accuracy { out.append(.miss(foe: !attackerIsFoe)); return out }
        let d = attackerIsFoe ? you : foes[current]
        let crit = rng.unit() < 0.0625
        let mult = m.type.against(d.type)
        let raw = Self.base(m, a, d) * mult * (crit ? 1.5 : 1) * (0.85 + 0.15 * rng.unit())
        let amount = min(d.hp, max(1, Int(raw)))
        if attackerIsFoe { you.hp -= amount } else { foes[current].hp -= amount }
        out.append(.hit(foe: !attackerIsFoe, amount: amount, mult: mult, crit: crit))
        if (attackerIsFoe ? you.hp : foes[current].hp) <= 0 { out.append(.faint(foe: !attackerIsFoe)) }
        return out
    }

    /// The rival trainer's pick: usually the move that hurts most (by level), else any move.
    mutating func foeChoice() -> Int {
        guard let f = foe else { return CDMoves.tackle }
        let usable = f.moves.indices.filter { f.pp[$0] > 0 }.map { f.moves[$0] }
        if rng.unit() < smart, let best = usable.max(by: { Self.expected($0, from: f, to: you) < Self.expected($1, from: f, to: you) }) {
            return best
        }
        return usable.isEmpty ? CDMoves.tackle : usable[rng.int(usable.count)]
    }

    /// Resolve a full turn with your move (an index into Banano's moves).
    mutating func turn(_ choice: Int) -> [CDEvent] {
        guard !won, !lost, you.moves.indices.contains(choice), you.pp[choice] > 0 else { return [] }
        let yours = you.moves[choice]
        let theirs = foeChoice()
        let youFirst: Bool
        if CDMoves.all[yours].heals { youFirst = true }
        else if you.spd != foes[current].spd { youFirst = you.spd > foes[current].spd }
        else { youFirst = rng.unit() < 0.5 }
        var events: [CDEvent] = []
        for foeTurn in (youFirst ? [false, true] : [true, false]) {
            guard !lost, foe != nil, foes[current].hp > 0 else { break }
            events += strike(foeTurn ? theirs : yours, attackerIsFoe: foeTurn)
        }
        if foe != nil && foes[current].hp <= 0 {
            current += 1
            if current < foes.count { events.append(.send(index: current)) }
        }
        return events
    }
}

// MARK: - View

struct CritterDuelView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var battle = CDBattle.level(1, seed: 1)
    @State private var built = false
    @State private var busy = false
    @State private var timeLeft = 0.0
    @State private var shake = 0
    // What's on screen, which trails the rules while a turn plays back.
    @State private var shownYouHP = 0.0
    @State private var shownFoeHP = 0.0
    @State private var shownFoe = 0
    @State private var message = ""
    @State private var fx = CDFx()
    // Demo-only: the finger on a move button.
    @State private var demoPress: Int?
    @State private var demoTap = 0

    private var timeLimit: Double { CDBattle.timeLimit(level) }
    private var foeOnScreen: CDCritter? { shownFoe < battle.foes.count ? battle.foes[shownFoe] : battle.foes.last }

    var body: some View {
        VStack(spacing: 0) {
            field
            VStack(spacing: isDemo ? 5 : 8) {
                messageBox
                if !isDemo {
                    timeBar.frame(height: 5).padding(.horizontal, 30)
                }
                moveGrid
            }
            .padding(.horizontal, isDemo ? 8 : 12)
            .padding(.top, isDemo ? 6 : 10)
            .padding(.bottom, isDemo ? 8 : 12)
            .background(CDPanel().equatable())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .screenShake(shake, amount: 5)
        .task { isDemo ? await runDemo() : await run() }
    }

    // MARK: Field

    private var field: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                CDField(level: level).equatable()
                TimelineView(.animation) { tl in
                    Canvas { ctx, s in
                        CDArt.scene(ctx, size: s, you: battle.you, foe: foeOnScreen, fx: fx, now: tl.date)
                    }
                }
                .allowsHitTesting(false)
                if let foe = foeOnScreen {
                    CDHPBox(name: foe.name, level: foe.level, type: foe.type, hp: shownFoeHP, maxHP: Double(foe.maxHP), numbers: false, compact: isDemo,
                            party: (0..<battle.foes.count).map { i in i < shownFoe || (i == shownFoe && battle.foes[i].hp <= 0 && fx.foeFainted) })
                        .frame(width: w * 0.56)
                        .position(x: w * 0.31, y: h * (isDemo ? 0.13 : 0.12))
                        .opacity(fx.foeBoxVisible ? 1 : 0)
                }
                CDHPBox(name: battle.you.name, level: battle.you.level, type: battle.you.type, hp: shownYouHP, maxHP: Double(battle.you.maxHP), numbers: true, compact: isDemo)
                    .frame(width: w * 0.56)
                    .position(x: w * 0.7, y: h * (isDemo ? 0.66 : 0.68))
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var messageBox: some View {
        Text(message)
            .font(.system(size: isDemo ? 13 : 16, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.55), radius: 0, x: 1, y: 1)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .frame(height: isDemo ? 38 : 54)
            .background(
                RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [Color(red: 0.24, green: 0.5, blue: 0.58), Color(red: 0.15, green: 0.36, blue: 0.44)],
                                                                       startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 0.88, green: 0.4, blue: 0.22), lineWidth: 3))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.5), lineWidth: 1).padding(4))
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(frac < 0.25 ? Color(red: 1, green: 0.32, blue: 0.25) : Color(white: 0.85))
                    .frame(width: geo.size.width * max(0, frac))
            }
        }
    }

    private var moveGrid: some View {
        let moves = battle.you.moves
        return Grid(horizontalSpacing: isDemo ? 6 : 8, verticalSpacing: isDemo ? 6 : 8) {
            GridRow { moveButton(0, moves); moveButton(1, moves) }
            GridRow { moveButton(2, moves); moveButton(3, moves) }
        }
    }

    @ViewBuilder
    private func moveButton(_ i: Int, _ moves: [Int]) -> some View {
        if i < moves.count {
            let m = CDMoves.all[moves[i]]
            let left = battle.you.pp[i]
            let usable = left > 0 && phase == .play
            Button { choose(i) } label: {
                CDMoveFace(move: m, left: m.heals ? left : nil, foeType: foeOnScreen?.type, compact: isDemo)
                    .frame(height: isDemo ? 40 : 58)
                    .overlay {
                        if isDemo && demoPress == i {
                            ZStack {
                                DemoTapRipple().id(demoTap)
                                Image(systemName: "hand.point.up.left.fill")
                                    .font(.system(size: 26))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.6), radius: 3)
                                    .offset(x: 14, y: 16)
                            }
                        }
                    }
            }
            .buttonStyle(CDMoveStyle(lit: isDemo && demoPress == i, dim: !usable || (busy && !isDemo)))
            .disabled(!usable || busy)
        } else {
            Color.clear.frame(height: isDemo ? 40 : 58)
        }
    }

    // MARK: Flow

    private func run() async {
        if !built {
            battle = CDBattle.level(level, seed: UInt64.random(in: 1...UInt64.max))
            shownYouHP = Double(battle.you.hp)
            shownFoeHP = Double(battle.foes[0].hp)
            shownFoe = 0
            fx.enter(Date())
            message = L("\(battle.foes[0].name) appears!", "\(battle.foes[0].name) xuất hiện!")
            timeLeft = timeLimit
            built = true
            Task { try? await Task.sleep(for: .seconds(1.1)); if !busy && phase == .play { message = prompt } }
        }
        let start = Date().addingTimeInterval(-(timeLimit - timeLeft))
        while !Task.isCancelled && phase == .play {
            try? await Task.sleep(for: .seconds(0.05))
            timeLeft = max(0, timeLimit - Date().timeIntervalSince(start))
            if timeLeft <= 0 { fail(); break }
        }
    }

    private var prompt: String { L("What will \(battle.you.name) do?", "\(battle.you.name) sẽ làm gì?") }

    private func choose(_ i: Int) {
        guard phase == .play, !busy else { return }
        let events = battle.turn(i)
        guard !events.isEmpty else { return }
        busy = true
        SoundManager.shared.tap(); Haptics.tap()
        Task { await playBack(events) }
    }

    /// Show a resolved turn one beat at a time, then hand control back (or end the level).
    private func playBack(_ events: [CDEvent]) async {
        for e in events {
            guard phase == .play || isDemo else { return }
            switch e {
            case .use(let foe, let move):
                let m = CDMoves.all[move]
                let who = foe ? (foeOnScreen?.name ?? "") : battle.you.name
                message = m.heals ? L("\(who) eats a banana!", "\(who) ăn chuối!") : L("\(who) used \(m.en)!", "\(who) dùng \(m.vi)!")
                fx.use(fromFoe: foe, type: m.type, heals: m.heals, at: Date())
                await pause(0.75)
            case .hit(let foe, let amount, let mult, let crit):
                fx.hit(onFoe: foe, mult: mult, crit: crit, at: Date())
                withAnimation(.linear(duration: 0.45)) {
                    if foe { shownFoeHP = max(0, shownFoeHP - Double(amount)) } else { shownYouHP = max(0, shownYouHP - Double(amount)) }
                }
                if mult > 1 || crit { shake += 1 }
                if foe { SoundManager.shared.tap() } else { SoundManager.shared.error(); Haptics.warning() }
                await pause(0.6)
            case .miss(let foe):
                fx.miss(onFoe: foe, at: Date())
                await pause(0.55)
            case .heal(let foe, let amount):
                withAnimation(.linear(duration: 0.45)) {
                    if foe { shownFoeHP += Double(amount) } else { shownYouHP += Double(amount) }
                }
                await pause(0.55)
            case .faint(let foe):
                fx.faint(foe: foe, at: Date())
                message = L("\(foe ? (foeOnScreen?.name ?? "") : battle.you.name) fainted!", "\(foe ? (foeOnScreen?.name ?? "") : battle.you.name) gục ngã!")
                await pause(0.9)
            case .send(let index):
                shownFoe = index
                shownFoeHP = Double(battle.foes[index].hp)
                fx.enter(Date())
                message = L("\(battle.foes[index].name) appears!", "\(battle.foes[index].name) xuất hiện!")
                await pause(1.1)
            }
        }
        if battle.won { win(); return }
        if battle.lost { fail(); return }
        message = prompt
        busy = false
    }

    private func pause(_ s: Double) async {
        try? await Task.sleep(for: .seconds(s))
    }

    // MARK: Demo (live manual clip)
    // Level 1 on a fixed seed: Banano against Coconutty, a water critter. The finger taps Leaf Cut
    // (grass beats water) twice; the rival answers once in between, and the second hit knocks it
    // out, which is the real win state. Every beat is the real turn's events played back.
    private static let demoSeed: UInt64 = 0xD0E1

    private func runDemo() async {
        while !Task.isCancelled {
            battle = CDBattle.level(1, seed: Self.demoSeed)
            shownYouHP = Double(battle.you.hp)
            shownFoeHP = Double(battle.foes[0].hp)
            shownFoe = 0
            fx = CDFx()
            fx.enter(Date())
            phase = .play
            busy = false
            message = L("\(battle.foes[0].name) appears!", "\(battle.foes[0].name) xuất hiện!")
            await pause(1.2)
            message = prompt
            while !Task.isCancelled && !battle.won && !battle.lost {
                await pause(0.7)
                demoPress = 0; demoTap += 1
                await pause(0.35)
                demoPress = nil
                let events = battle.turn(0)
                busy = true
                await playBack(events)
            }
            await pause(1.4)
        }
    }

    private func win() {
        guard phase == .play else { return }
        if isDemo { busy = false; return }
        phase = .done
        Haptics.tap(); SoundManager.shared.tap()
        onWin()
    }

    private func fail() {
        guard phase == .play else { return }
        if isDemo { busy = false; return }
        phase = .done
        SoundManager.shared.error(); Haptics.warning()
        onFail()
    }
}

// MARK: - Presentation state

/// Animation clocks for the field: who's lunging, who's hit, what the move looks like, who fainted.
struct CDFx {
    var lungeFoe = false
    var lungeAt = Date.distantPast
    var effectType: CDType = .normal
    var effectHeals = false
    var effectFromFoe = false
    var effectAt = Date.distantPast
    var hitFoe = false
    var hitAt = Date.distantPast
    var badge: (text: String, color: Color)?
    var badgeOnFoe = false
    var badgeAt = Date.distantPast
    var faintFoe = false
    var faintAt = Date.distantPast
    var enterAt = Date.distantPast
    var foeFainted = false
    var foeBoxVisible = true

    mutating func use(fromFoe: Bool, type: CDType, heals: Bool, at: Date) {
        lungeFoe = fromFoe; lungeAt = heals ? .distantPast : at
        effectType = type; effectHeals = heals; effectFromFoe = fromFoe; effectAt = at
    }
    mutating func hit(onFoe: Bool, mult: Double, crit: Bool, at: Date) {
        hitFoe = onFoe; hitAt = at
        if mult > 1 { badge = ("×2", Color(red: 0.95, green: 0.38, blue: 0.15)) }
        else if mult < 1 { badge = ("×½", Color(red: 0.42, green: 0.48, blue: 0.62)) }
        else if crit { badge = ("!", Color(red: 0.95, green: 0.75, blue: 0.15)) }
        else { badge = nil }
        if crit, mult != 1, let b = badge { badge = (b.text + "!", b.color) }
        badgeOnFoe = onFoe; badgeAt = at
    }
    mutating func miss(onFoe: Bool, at: Date) {
        badge = (L("MISS", "TRƯỢT"), Color(white: 0.45)); badgeOnFoe = onFoe; badgeAt = at
    }
    mutating func faint(foe: Bool, at: Date) {
        faintFoe = foe; faintAt = at
        if foe { foeFainted = true }
    }
    mutating func enter(_ at: Date) {
        enterAt = at; foeFainted = false; faintFoe = false; faintAt = .distantPast
    }
}

// MARK: - Art

private enum CDArt {
    static let ink = Color(red: 0.1, green: 0.08, blue: 0.1)

    static func color(_ t: CDType) -> Color {
        switch t {
        case .grass: return Color(red: 0.35, green: 0.72, blue: 0.28)
        case .fire: return Color(red: 0.93, green: 0.42, blue: 0.16)
        case .water: return Color(red: 0.25, green: 0.52, blue: 0.9)
        case .electric: return Color(red: 0.96, green: 0.76, blue: 0.1)
        case .normal: return Color(red: 0.62, green: 0.6, blue: 0.48)
        }
    }

    static func icon(_ t: CDType) -> String {
        switch t {
        case .grass: return "leaf.fill"
        case .fire: return "flame.fill"
        case .water: return "drop.fill"
        case .electric: return "bolt.fill"
        case .normal: return "circle.fill"
        }
    }

    static func disc(_ c: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }
    static func oval(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2)) }

    static func eye(_ g: GraphicsContext, _ c: CGPoint, _ r: CGFloat, look: CGPoint = .zero, angry: Bool = false, left: Bool = true) {
        g.fill(oval(c, r * 0.8, r), with: .color(.white))
        g.stroke(oval(c, r * 0.8, r), with: .color(ink), lineWidth: max(1, r * 0.18))
        g.fill(oval(CGPoint(x: c.x + look.x * r * 0.3, y: c.y + r * 0.1 + look.y * r * 0.3), r * 0.48, r * 0.6), with: .color(ink))
        g.fill(disc(CGPoint(x: c.x - r * 0.15 + look.x * r * 0.3, y: c.y - r * 0.18), r * 0.2), with: .color(.white))
        if angry {
            var brow = Path()
            brow.move(to: CGPoint(x: c.x - r * 0.9, y: c.y - r * (left ? 1.25 : 0.85)))
            brow.addLine(to: CGPoint(x: c.x + r * 0.9, y: c.y - r * (left ? 0.85 : 1.25)))
            g.stroke(brow, with: .color(ink), style: StrokeStyle(lineWidth: max(1.5, r * 0.32), lineCap: .round))
        }
    }

    static func flame(_ g: GraphicsContext, base b: CGPoint, h: CGFloat, w: CGFloat, t: Double) {
        let k = CGFloat(1 + 0.12 * sin(t * 13))
        var f = Path()
        f.move(to: CGPoint(x: b.x - w / 2, y: b.y))
        f.addQuadCurve(to: CGPoint(x: b.x + w * 0.05, y: b.y - h * k), control: CGPoint(x: b.x - w * 0.6, y: b.y - h * 0.6 * k))
        f.addQuadCurve(to: CGPoint(x: b.x + w / 2, y: b.y), control: CGPoint(x: b.x + w * 0.65, y: b.y - h * 0.45 * k))
        f.closeSubpath()
        g.fill(f, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.92, blue: 0.4), Color(red: 1, green: 0.5, blue: 0.1)]),
                                       startPoint: CGPoint(x: b.x, y: b.y), endPoint: CGPoint(x: b.x, y: b.y - h)))
        g.stroke(f, with: .color(Color(red: 0.75, green: 0.25, blue: 0.05)), lineWidth: 1)
    }

    // MARK: Critters (feet at `b`, about `s` tall)

    static func critter(_ g: GraphicsContext, _ species: Int, feet b: CGPoint, s: CGFloat, back: Bool, t: Double) {
        switch species {
        case CDDex.banano: banano(g, b, s, back: back, t: t)
        case CDDex.coconutty: coconutty(g, b, s, t: t)
        case CDDex.chilipep: chilipep(g, b, s, t: t)
        case CDDex.lemonzap: lemonzap(g, b, s, t: t)
        case CDDex.melonox: melonox(g, b, s, t: t)
        case CDDex.blubbery: blubbery(g, b, s, t: t)
        default: pepperoar(g, b, s, t: t)
        }
    }

    /// Banano from behind: an upright banana with a leaf tuft by the stem, little arms and feet.
    static func banano(_ g: GraphicsContext, _ b: CGPoint, _ s: CGFloat, back: Bool, t: Double) {
        let lw = max(1.4, s * 0.022)
        for dx in [-0.16, 0.12] as [CGFloat] {
            g.fill(oval(CGPoint(x: b.x + dx * s, y: b.y - s * 0.03), s * 0.1, s * 0.05), with: .color(Color(red: 0.5, green: 0.32, blue: 0.1)))
        }
        var body = Path()
        body.move(to: CGPoint(x: b.x + s * 0.02, y: b.y - s * 0.05))
        body.addCurve(to: CGPoint(x: b.x + s * 0.12, y: b.y - s * 0.92), control1: CGPoint(x: b.x - s * 0.5, y: b.y - s * 0.2), control2: CGPoint(x: b.x - s * 0.36, y: b.y - s * 0.86))
        body.addCurve(to: CGPoint(x: b.x + s * 0.02, y: b.y - s * 0.05), control1: CGPoint(x: b.x + s * 0.3, y: b.y - s * 0.7), control2: CGPoint(x: b.x + s * 0.34, y: b.y - s * 0.16))
        body.closeSubpath()
        // Arms.
        for (dx, dy) in [(-0.3, -0.48), (0.26, -0.44)] as [(CGFloat, CGFloat)] {
            let c = CGPoint(x: b.x + dx * s, y: b.y + dy * s)
            g.fill(oval(c, s * 0.07, s * 0.1), with: .color(Color(red: 1, green: 0.85, blue: 0.25)))
            g.stroke(oval(c, s * 0.07, s * 0.1), with: .color(Color(red: 0.55, green: 0.38, blue: 0.05)), lineWidth: lw)
        }
        g.fill(body, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.5), Color(red: 1, green: 0.83, blue: 0.18), Color(red: 0.88, green: 0.64, blue: 0.08)]),
                                           startPoint: CGPoint(x: b.x - s * 0.3, y: b.y - s * 0.5), endPoint: CGPoint(x: b.x + s * 0.3, y: b.y - s * 0.4)))
        // Ridges and a few speckles down its back.
        var ridge = Path()
        ridge.move(to: CGPoint(x: b.x + s * 0.06, y: b.y - s * 0.1))
        ridge.addCurve(to: CGPoint(x: b.x + s * 0.1, y: b.y - s * 0.86), control1: CGPoint(x: b.x - s * 0.26, y: b.y - s * 0.3), control2: CGPoint(x: b.x - s * 0.14, y: b.y - s * 0.78))
        g.stroke(ridge, with: .color(Color(red: 0.82, green: 0.6, blue: 0.1).opacity(0.7)), lineWidth: lw)
        for (dx, dy) in [(-0.16, -0.36), (-0.08, -0.62), (-0.2, -0.5), (0.04, -0.28)] as [(CGFloat, CGFloat)] {
            g.fill(oval(CGPoint(x: b.x + dx * s, y: b.y + dy * s), s * 0.018, s * 0.012), with: .color(Color(red: 0.45, green: 0.3, blue: 0.08)))
        }
        g.stroke(body, with: .color(Color(red: 0.5, green: 0.34, blue: 0.04)), lineWidth: lw)
        // The stem and its leaf tuft.
        let stem = CGRect(x: b.x + s * 0.07, y: b.y - s * 1.0, width: s * 0.09, height: s * 0.12)
        g.fill(Path(roundedRect: stem, cornerRadius: s * 0.02), with: .color(Color(red: 0.42, green: 0.28, blue: 0.08)))
        let sway = CGFloat(sin(t * 2.2)) * s * 0.02
        for side in [-1.0, 1.0] as [CGFloat] {
            var leaf = Path()
            let root = CGPoint(x: stem.midX, y: stem.minY + s * 0.02)
            leaf.move(to: root)
            leaf.addQuadCurve(to: CGPoint(x: root.x + side * s * 0.2 + sway, y: root.y - s * 0.12), control: CGPoint(x: root.x + side * s * 0.05, y: root.y - s * 0.18))
            leaf.addQuadCurve(to: root, control: CGPoint(x: root.x + side * s * 0.18, y: root.y - s * 0.02))
            g.fill(leaf, with: .color(Color(red: 0.36, green: 0.74, blue: 0.24)))
            g.stroke(leaf, with: .color(Color(red: 0.15, green: 0.4, blue: 0.08)), lineWidth: 1)
        }
    }

    static func coconutty(_ g: GraphicsContext, _ b: CGPoint, _ s: CGFloat, t: Double) {
        let lw = max(1.3, s * 0.022)
        let c = CGPoint(x: b.x, y: b.y - s * 0.4)
        let r = s * 0.36
        for dx in [-0.17, 0.17] as [CGFloat] { g.fill(oval(CGPoint(x: b.x + dx * s, y: b.y - s * 0.03), s * 0.09, s * 0.045), with: .color(Color(red: 0.35, green: 0.2, blue: 0.1))) }
        // Fins.
        for side in [-1.0, 1.0] as [CGFloat] {
            var fin = Path()
            fin.move(to: CGPoint(x: c.x + side * r * 0.85, y: c.y - r * 0.1))
            fin.addQuadCurve(to: CGPoint(x: c.x + side * r * 1.45, y: c.y + r * 0.25), control: CGPoint(x: c.x + side * r * 1.35, y: c.y - r * 0.35))
            fin.addQuadCurve(to: CGPoint(x: c.x + side * r * 0.85, y: c.y + r * 0.3), control: CGPoint(x: c.x + side * r * 1.1, y: c.y + r * 0.4))
            g.fill(fin, with: .color(Color(red: 0.4, green: 0.7, blue: 0.98)))
            g.stroke(fin, with: .color(Color(red: 0.1, green: 0.3, blue: 0.6)), lineWidth: lw)
        }
        g.fill(disc(c, r), with: .radialGradient(Gradient(colors: [Color(red: 0.66, green: 0.44, blue: 0.24), Color(red: 0.44, green: 0.27, blue: 0.12), Color(red: 0.3, green: 0.17, blue: 0.07)]),
                                               center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.3), startRadius: 0, endRadius: r * 1.4))
        var fibres = Path()
        for k in 0..<14 {
            let a = Double(k) / 14 * 2 * .pi
            let p = CGPoint(x: c.x + CGFloat(cos(a)) * r * 0.82, y: c.y + CGFloat(sin(a)) * r * 0.82)
            fibres.move(to: p); fibres.addLine(to: CGPoint(x: p.x + r * 0.08, y: p.y + r * 0.1))
        }
        g.stroke(fibres, with: .color(Color(red: 0.25, green: 0.14, blue: 0.05).opacity(0.6)), lineWidth: 1)
        g.stroke(disc(c, r), with: .color(Color(red: 0.2, green: 0.1, blue: 0.04)), lineWidth: lw)
        // The open top: white flesh round a pool of water, with a drop jumping out.
        let top = CGPoint(x: c.x, y: c.y - r * 0.78)
        g.fill(oval(top, r * 0.58, r * 0.2), with: .color(Color(white: 0.96)))
        g.fill(oval(CGPoint(x: top.x, y: top.y + r * 0.02), r * 0.46, r * 0.13), with: .color(Color(red: 0.35, green: 0.65, blue: 0.98)))
        g.stroke(oval(top, r * 0.58, r * 0.2), with: .color(Color(red: 0.2, green: 0.1, blue: 0.04)), lineWidth: lw)
        let hop = CGFloat(abs(sin(t * 2.6))) * r * 0.5
        g.fill(oval(CGPoint(x: top.x + r * 0.15, y: top.y - r * 0.15 - hop), r * 0.07, r * 0.1), with: .color(Color(red: 0.45, green: 0.75, blue: 1)))
        eye(g, CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.05), r * 0.22)
        eye(g, CGPoint(x: c.x + r * 0.35, y: c.y - r * 0.05), r * 0.22)
        var smile = Path()
        smile.addArc(center: CGPoint(x: c.x, y: c.y + r * 0.25), radius: r * 0.22, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
        g.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: lw, lineCap: .round))
    }

    static func chilipep(_ g: GraphicsContext, _ b: CGPoint, _ s: CGFloat, t: Double) {
        let lw = max(1.3, s * 0.022)
        var body = Path()
        body.move(to: CGPoint(x: b.x - s * 0.24, y: b.y - s * 0.8))
        body.addCurve(to: CGPoint(x: b.x + s * 0.2, y: b.y - s * 0.02), control1: CGPoint(x: b.x - s * 0.36, y: b.y - s * 0.4), control2: CGPoint(x: b.x - s * 0.1, y: b.y - s * 0.04))
        body.addQuadCurve(to: CGPoint(x: b.x + s * 0.06, y: b.y - s * 0.16), control: CGPoint(x: b.x + s * 0.2, y: b.y - s * 0.14))
        body.addCurve(to: CGPoint(x: b.x + s * 0.24, y: b.y - s * 0.8), control1: CGPoint(x: b.x + s * 0.26, y: b.y - s * 0.3), control2: CGPoint(x: b.x + s * 0.34, y: b.y - s * 0.62))
        body.closeSubpath()
        // Flames rising off its head.
        for (dx, hh) in [(-0.13, 0.28), (0.0, 0.38), (0.13, 0.26)] as [(CGFloat, CGFloat)] {
            flame(g, base: CGPoint(x: b.x + dx * s, y: b.y - s * 0.86), h: s * hh, w: s * 0.16, t: t + Double(dx) * 9)
        }
        g.fill(body, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.32, blue: 0.22), Color(red: 0.8, green: 0.06, blue: 0.06)]),
                                           startPoint: CGPoint(x: b.x - s * 0.2, y: b.y - s * 0.7), endPoint: CGPoint(x: b.x + s * 0.2, y: b.y - s * 0.2)))
        g.fill(oval(CGPoint(x: b.x - s * 0.12, y: b.y - s * 0.6), s * 0.04, s * 0.12), with: .color(.white.opacity(0.45)))
        g.stroke(body, with: .color(Color(red: 0.35, green: 0.02, blue: 0.02)), lineWidth: lw)
        // Green cap.
        var cap = Path()
        cap.move(to: CGPoint(x: b.x - s * 0.26, y: b.y - s * 0.78))
        for k in 0..<5 {
            let x = b.x - s * 0.26 + s * 0.13 * CGFloat(k)
            cap.addQuadCurve(to: CGPoint(x: x + s * 0.13, y: b.y - s * 0.78), control: CGPoint(x: x + s * 0.065, y: b.y - s * 0.68))
        }
        cap.addQuadCurve(to: CGPoint(x: b.x - s * 0.26, y: b.y - s * 0.78), control: CGPoint(x: b.x, y: b.y - s * 0.94))
        g.fill(cap, with: .color(Color(red: 0.3, green: 0.66, blue: 0.2)))
        g.stroke(cap, with: .color(Color(red: 0.1, green: 0.32, blue: 0.06)), lineWidth: lw)
        let ec = CGPoint(x: b.x, y: b.y - s * 0.56)
        eye(g, CGPoint(x: ec.x - s * 0.09, y: ec.y), s * 0.06, look: CGPoint(x: -0.3, y: 0), angry: true, left: true)
        eye(g, CGPoint(x: ec.x + s * 0.09, y: ec.y), s * 0.06, look: CGPoint(x: -0.3, y: 0), angry: true, left: false)
        var grin = Path()
        grin.move(to: CGPoint(x: ec.x - s * 0.1, y: ec.y + s * 0.12))
        grin.addQuadCurve(to: CGPoint(x: ec.x + s * 0.1, y: ec.y + s * 0.11), control: CGPoint(x: ec.x, y: ec.y + s * 0.2))
        g.stroke(grin, with: .color(ink), style: StrokeStyle(lineWidth: lw, lineCap: .round))
        var fang = Path()
        fang.move(to: CGPoint(x: ec.x + s * 0.03, y: ec.y + s * 0.145)); fang.addLine(to: CGPoint(x: ec.x + s * 0.055, y: ec.y + s * 0.19)); fang.addLine(to: CGPoint(x: ec.x + s * 0.075, y: ec.y + s * 0.14))
        g.fill(fang, with: .color(.white))
    }

    static func lemonzap(_ g: GraphicsContext, _ b: CGPoint, _ s: CGFloat, t: Double) {
        let lw = max(1.3, s * 0.022)
        let c = CGPoint(x: b.x, y: b.y - s * 0.36)
        for dx in [-0.14, 0.14] as [CGFloat] { g.fill(oval(CGPoint(x: b.x + dx * s, y: b.y - s * 0.03), s * 0.08, s * 0.045), with: .color(Color(red: 0.75, green: 0.55, blue: 0.05))) }
        // Bolt antennae.
        for side in [-1.0, 1.0] as [CGFloat] {
            let root = CGPoint(x: c.x + side * s * 0.12, y: c.y - s * 0.24)
            var bolt = Path()
            bolt.move(to: root)
            bolt.addLine(to: CGPoint(x: root.x + side * s * 0.1, y: root.y - s * 0.14))
            bolt.addLine(to: CGPoint(x: root.x + side * s * 0.03, y: root.y - s * 0.15))
            bolt.addLine(to: CGPoint(x: root.x + side * s * 0.16, y: root.y - s * 0.34))
            bolt.addLine(to: CGPoint(x: root.x + side * s * 0.12, y: root.y - s * 0.2))
            bolt.addLine(to: CGPoint(x: root.x + side * s * 0.18, y: root.y - s * 0.19))
            bolt.addLine(to: CGPoint(x: root.x + side * s * 0.04, y: root.y + s * 0.02))
            bolt.closeSubpath()
            g.fill(bolt, with: .color(Color(red: 1, green: 0.9, blue: 0.2)))
            g.stroke(bolt, with: .color(Color(red: 0.55, green: 0.38, blue: 0)), lineWidth: lw)
        }
        // The lemon, pointed at both ends.
        var lemon = Path()
        lemon.move(to: CGPoint(x: c.x - s * 0.42, y: c.y))
        lemon.addCurve(to: CGPoint(x: c.x + s * 0.42, y: c.y), control1: CGPoint(x: c.x - s * 0.3, y: c.y - s * 0.38), control2: CGPoint(x: c.x + s * 0.3, y: c.y - s * 0.38))
        lemon.addCurve(to: CGPoint(x: c.x - s * 0.42, y: c.y), control1: CGPoint(x: c.x + s * 0.3, y: c.y + s * 0.36), control2: CGPoint(x: c.x - s * 0.3, y: c.y + s * 0.36))
        lemon.closeSubpath()
        g.fill(lemon, with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.98, blue: 0.6), Color(red: 1, green: 0.88, blue: 0.15), Color(red: 0.85, green: 0.68, blue: 0.05)]),
                                            center: CGPoint(x: c.x - s * 0.1, y: c.y - s * 0.12), startRadius: 0, endRadius: s * 0.45))
        var dimples = Path()
        for k in 0..<9 {
            let p = CGPoint(x: c.x + s * CGFloat(hash(Double(k)) - 0.5) * 0.5, y: c.y + s * CGFloat(hash(Double(k) + 3) - 0.5) * 0.36)
            dimples.addEllipse(in: CGRect(x: p.x, y: p.y, width: 2, height: 2))
        }
        g.fill(dimples, with: .color(Color(red: 0.8, green: 0.62, blue: 0.05).opacity(0.6)))
        g.stroke(lemon, with: .color(Color(red: 0.5, green: 0.36, blue: 0)), lineWidth: lw)
        eye(g, CGPoint(x: c.x - s * 0.11, y: c.y - s * 0.03), s * 0.065, look: CGPoint(x: -0.3, y: 0), angry: true, left: true)
        eye(g, CGPoint(x: c.x + s * 0.11, y: c.y - s * 0.03), s * 0.065, look: CGPoint(x: -0.3, y: 0), angry: true, left: false)
        var smirk = Path()
        smirk.move(to: CGPoint(x: c.x - s * 0.06, y: c.y + s * 0.1)); smirk.addQuadCurve(to: CGPoint(x: c.x + s * 0.08, y: c.y + s * 0.08), control: CGPoint(x: c.x + s * 0.02, y: c.y + s * 0.15))
        g.stroke(smirk, with: .color(ink), style: StrokeStyle(lineWidth: lw, lineCap: .round))
        // Crackling sparks.
        var sparks = Path()
        for k in 0..<3 {
            let a = t * 3 + Double(k) * 2.1
            let p = CGPoint(x: c.x + CGFloat(cos(a)) * s * 0.5, y: c.y + CGFloat(sin(a)) * s * 0.3)
            sparks.move(to: p); sparks.addLine(to: CGPoint(x: p.x + 4, y: p.y - 5)); sparks.addLine(to: CGPoint(x: p.x + 1, y: p.y - 6)); sparks.addLine(to: CGPoint(x: p.x + 5, y: p.y - 11))
        }
        g.stroke(sparks, with: .color(Color(red: 1, green: 0.95, blue: 0.5).opacity(0.5 + 0.5 * abs(sin(t * 9)))), lineWidth: 1.6)
    }

    static func melonox(_ g: GraphicsContext, _ b: CGPoint, _ s: CGFloat, t: Double) {
        let lw = max(1.3, s * 0.022)
        let c = CGPoint(x: b.x, y: b.y - s * 0.3)
        for dx in [-0.32, -0.12, 0.12, 0.32] as [CGFloat] {
            g.fill(Path(roundedRect: CGRect(x: b.x + dx * s - s * 0.06, y: b.y - s * 0.16, width: s * 0.12, height: s * 0.16), cornerRadius: s * 0.05),
                   with: .color(Color(red: 0.25, green: 0.55, blue: 0.2)))
        }
        // Face: a slice of red flesh with seed freckles.
        var face = Path()
        face.addArc(center: CGPoint(x: c.x, y: c.y - s * 0.02), radius: s * 0.34, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        face.closeSubpath()
        g.fill(face, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.4, blue: 0.42), Color(red: 0.88, green: 0.18, blue: 0.24)]),
                                           startPoint: CGPoint(x: 0, y: c.y), endPoint: CGPoint(x: 0, y: c.y + s * 0.3)))
        g.stroke(face, with: .color(Color(red: 0.4, green: 0.05, blue: 0.08)), lineWidth: lw)
        var seeds = Path()
        for (dx, dy) in [(-0.22, 0.12), (-0.1, 0.2), (0.12, 0.2), (0.22, 0.1), (0.0, 0.26)] as [(CGFloat, CGFloat)] {
            seeds.addEllipse(in: CGRect(x: c.x + dx * s - 2, y: c.y + dy * s - 3, width: 4, height: 6))
        }
        g.fill(seeds, with: .color(ink))
        // Striped shell dome.
        var shell = Path()
        shell.addArc(center: CGPoint(x: c.x, y: c.y), radius: s * 0.4, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        shell.closeSubpath()
        g.fill(shell, with: .color(Color(red: 0.42, green: 0.74, blue: 0.3)))
        var stripes = g
        stripes.clip(to: shell)
        for k in -2...2 {
            var st = Path()
            let x = c.x + CGFloat(k) * s * 0.16
            st.move(to: CGPoint(x: x, y: c.y)); st.addQuadCurve(to: CGPoint(x: x * 0.5 + c.x * 0.5, y: c.y - s * 0.42), control: CGPoint(x: x + CGFloat(k) * s * 0.05, y: c.y - s * 0.25))
            stripes.stroke(st, with: .color(Color(red: 0.12, green: 0.4, blue: 0.1)), lineWidth: s * 0.06)
        }
        g.stroke(shell, with: .color(Color(red: 0.08, green: 0.3, blue: 0.06)), lineWidth: lw)
        // Sleepy eyes.
        for dx in [-0.12, 0.12] as [CGFloat] {
            var lid = Path()
            lid.addArc(center: CGPoint(x: c.x + dx * s, y: c.y + s * 0.05), radius: s * 0.05, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            g.stroke(lid, with: .color(ink), style: StrokeStyle(lineWidth: lw * 1.2, lineCap: .round))
        }
        let snore = CGFloat(sin(t * 1.5)) * s * 0.01
        g.fill(oval(CGPoint(x: c.x, y: c.y + s * 0.14 + snore), s * 0.04, s * 0.03), with: .color(Color(red: 0.4, green: 0.05, blue: 0.08)))
    }

    static func blubbery(_ g: GraphicsContext, _ b: CGPoint, _ s: CGFloat, t: Double) {
        let lw = max(1.3, s * 0.022)
        let c = CGPoint(x: b.x, y: b.y - s * 0.38)
        let r = s * 0.34
        for dx in [-0.14, 0.14] as [CGFloat] { g.fill(oval(CGPoint(x: b.x + dx * s, y: b.y - s * 0.03), s * 0.08, s * 0.04), with: .color(Color(red: 0.2, green: 0.2, blue: 0.5))) }
        g.fill(disc(c, r), with: .radialGradient(Gradient(colors: [Color(red: 0.45, green: 0.5, blue: 0.95), Color(red: 0.22, green: 0.24, blue: 0.7), Color(red: 0.12, green: 0.12, blue: 0.4)]),
                                               center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4), startRadius: 0, endRadius: r * 1.4))
        g.fill(oval(CGPoint(x: c.x - r * 0.4, y: c.y - r * 0.45), r * 0.25, r * 0.12), with: .color(.white.opacity(0.35)))
        g.stroke(disc(c, r), with: .color(Color(red: 0.06, green: 0.06, blue: 0.25)), lineWidth: lw)
        // The star-shaped crown on top.
        var crown = Path()
        let cc = CGPoint(x: c.x, y: c.y - r * 0.92)
        for k in 0..<10 {
            let a = Double(k) / 10 * 2 * .pi - .pi / 2
            let rr = k % 2 == 0 ? r * 0.3 : r * 0.13
            let p = CGPoint(x: cc.x + CGFloat(cos(a)) * rr, y: cc.y + CGFloat(sin(a)) * rr * 0.6)
            if k == 0 { crown.move(to: p) } else { crown.addLine(to: p) }
        }
        crown.closeSubpath()
        g.fill(crown, with: .color(Color(red: 0.16, green: 0.14, blue: 0.4)))
        g.stroke(crown, with: .color(Color(red: 0.06, green: 0.06, blue: 0.2)), lineWidth: 1)
        eye(g, CGPoint(x: c.x - r * 0.35, y: c.y), r * 0.24, look: CGPoint(x: -0.3, y: 0))
        eye(g, CGPoint(x: c.x + r * 0.32, y: c.y), r * 0.24, look: CGPoint(x: -0.3, y: 0))
        for dx in [-0.6, 0.58] as [CGFloat] {
            g.fill(oval(CGPoint(x: c.x + dx * r, y: c.y + r * 0.35), r * 0.13, r * 0.07), with: .color(Color(red: 1, green: 0.55, blue: 0.75).opacity(0.7)))
        }
        var m = Path()
        m.addArc(center: CGPoint(x: c.x, y: c.y + r * 0.3), radius: r * 0.15, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
        g.stroke(m, with: .color(.white), style: StrokeStyle(lineWidth: lw, lineCap: .round))
        // Two drops orbiting it.
        for k in 0..<2 {
            let a = t * 1.6 + Double(k) * .pi
            let p = CGPoint(x: c.x + CGFloat(cos(a)) * r * 1.35, y: c.y + CGFloat(sin(a)) * r * 0.5)
            var drop = Path()
            drop.move(to: CGPoint(x: p.x, y: p.y - r * 0.16))
            drop.addQuadCurve(to: CGPoint(x: p.x, y: p.y + r * 0.08), control: CGPoint(x: p.x + r * 0.14, y: p.y))
            drop.addQuadCurve(to: CGPoint(x: p.x, y: p.y - r * 0.16), control: CGPoint(x: p.x - r * 0.14, y: p.y))
            g.fill(drop, with: .color(Color(red: 0.5, green: 0.78, blue: 1).opacity(0.85)))
        }
    }

    /// The level-7 boss: a big bell-pepper dragon with leaf wings and stem horns.
    static func pepperoar(_ g: GraphicsContext, _ b: CGPoint, _ s0: CGFloat, t: Double) {
        let s = s0 * 1.15
        let lw = max(1.4, s * 0.02)
        let c = CGPoint(x: b.x, y: b.y - s * 0.4)
        let flap = CGFloat(sin(t * 4)) * s * 0.04
        for side in [-1.0, 1.0] as [CGFloat] {
            var wing = Path()
            wing.move(to: CGPoint(x: c.x + side * s * 0.25, y: c.y - s * 0.1))
            wing.addQuadCurve(to: CGPoint(x: c.x + side * s * 0.62, y: c.y - s * 0.38 - flap), control: CGPoint(x: c.x + side * s * 0.36, y: c.y - s * 0.45))
            wing.addQuadCurve(to: CGPoint(x: c.x + side * s * 0.28, y: c.y + s * 0.08), control: CGPoint(x: c.x + side * s * 0.62, y: c.y - s * 0.02))
            g.fill(wing, with: .color(Color(red: 0.3, green: 0.62, blue: 0.2)))
            g.stroke(wing, with: .color(Color(red: 0.1, green: 0.3, blue: 0.06)), lineWidth: lw)
        }
        for dx in [-0.16, 0.16] as [CGFloat] { g.fill(oval(CGPoint(x: b.x + dx * s, y: b.y - s * 0.03), s * 0.1, s * 0.045), with: .color(Color(red: 0.55, green: 0.12, blue: 0.05))) }
        // The lobed pepper body.
        var body = Path()
        body.move(to: CGPoint(x: c.x - s * 0.3, y: c.y - s * 0.32))
        body.addQuadCurve(to: CGPoint(x: c.x + s * 0.3, y: c.y - s * 0.32), control: CGPoint(x: c.x, y: c.y - s * 0.46))
        body.addCurve(to: CGPoint(x: c.x + s * 0.18, y: c.y + s * 0.36), control1: CGPoint(x: c.x + s * 0.46, y: c.y - s * 0.1), control2: CGPoint(x: c.x + s * 0.4, y: c.y + s * 0.32))
        body.addQuadCurve(to: CGPoint(x: c.x - s * 0.02, y: c.y + s * 0.36), control: CGPoint(x: c.x + s * 0.08, y: c.y + s * 0.44))
        body.addQuadCurve(to: CGPoint(x: c.x - s * 0.2, y: c.y + s * 0.36), control: CGPoint(x: c.x - s * 0.12, y: c.y + s * 0.44))
        body.addCurve(to: CGPoint(x: c.x - s * 0.3, y: c.y - s * 0.32), control1: CGPoint(x: c.x - s * 0.42, y: c.y + s * 0.32), control2: CGPoint(x: c.x - s * 0.46, y: c.y - s * 0.1))
        body.closeSubpath()
        g.fill(body, with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.6, blue: 0.25), Color(red: 0.95, green: 0.3, blue: 0.08), Color(red: 0.65, green: 0.12, blue: 0.04)]),
                                           center: CGPoint(x: c.x - s * 0.12, y: c.y - s * 0.15), startRadius: 0, endRadius: s * 0.55))
        var creases = Path()
        creases.move(to: CGPoint(x: c.x - s * 0.08, y: c.y - s * 0.3)); creases.addQuadCurve(to: CGPoint(x: c.x - s * 0.06, y: c.y + s * 0.36), control: CGPoint(x: c.x - s * 0.16, y: c.y))
        creases.move(to: CGPoint(x: c.x + s * 0.1, y: c.y - s * 0.3)); creases.addQuadCurve(to: CGPoint(x: c.x + s * 0.12, y: c.y + s * 0.36), control: CGPoint(x: c.x + s * 0.2, y: c.y))
        g.stroke(creases, with: .color(Color(red: 0.6, green: 0.12, blue: 0.04).opacity(0.6)), lineWidth: lw)
        g.stroke(body, with: .color(Color(red: 0.35, green: 0.05, blue: 0.02)), lineWidth: lw)
        // Stem horns.
        for side in [-1.0, 1.0] as [CGFloat] {
            var horn = Path()
            horn.move(to: CGPoint(x: c.x + side * s * 0.05, y: c.y - s * 0.4))
            horn.addQuadCurve(to: CGPoint(x: c.x + side * s * 0.2, y: c.y - s * 0.62), control: CGPoint(x: c.x + side * s * 0.02, y: c.y - s * 0.56))
            g.stroke(horn, with: .color(Color(red: 0.1, green: 0.3, blue: 0.06)), style: StrokeStyle(lineWidth: s * 0.055 + lw, lineCap: .round))
            g.stroke(horn, with: .color(Color(red: 0.32, green: 0.6, blue: 0.18)), style: StrokeStyle(lineWidth: s * 0.055, lineCap: .round))
        }
        eye(g, CGPoint(x: c.x - s * 0.11, y: c.y - s * 0.1), s * 0.065, look: CGPoint(x: -0.3, y: 0.2), angry: true, left: true)
        eye(g, CGPoint(x: c.x + s * 0.11, y: c.y - s * 0.1), s * 0.065, look: CGPoint(x: -0.3, y: 0.2), angry: true, left: false)
        var jaw = Path()
        jaw.move(to: CGPoint(x: c.x - s * 0.12, y: c.y + s * 0.06))
        jaw.addQuadCurve(to: CGPoint(x: c.x + s * 0.12, y: c.y + s * 0.06), control: CGPoint(x: c.x, y: c.y + s * 0.18))
        jaw.closeSubpath()
        g.fill(jaw, with: .color(Color(red: 0.3, green: 0.04, blue: 0.02)))
        for dx in [-0.07, 0.07] as [CGFloat] {
            var tooth = Path(); tooth.move(to: CGPoint(x: c.x + dx * s - s * 0.02, y: c.y + s * 0.06)); tooth.addLine(to: CGPoint(x: c.x + dx * s, y: c.y + s * 0.1)); tooth.addLine(to: CGPoint(x: c.x + dx * s + s * 0.02, y: c.y + s * 0.06))
            g.fill(tooth, with: .color(.white))
        }
        flame(g, base: CGPoint(x: c.x - s * 0.15, y: c.y + s * 0.1), h: s * 0.14, w: s * 0.08, t: t)
    }

    static func hash(_ n: Double) -> Double { let v = sin(n * 12.9898) * 43758.5453; return v - floor(v) }

    // MARK: Move effects

    static func effect(_ g: GraphicsContext, type: CDType, heals: Bool, from a: CGPoint, to b: CGPoint, k: CGFloat, s: CGFloat) {
        if heals {
            // Banana snack: a banana floats up, sparkles all round.
            var g2 = g
            g2.opacity = Double(max(0, 1 - k))
            let p = CGPoint(x: a.x, y: a.y - s * 0.3 - k * s * 0.5)
            banana(g2, at: p, w: s * 0.36)
            for i in 0..<6 {
                let ang = Double(i) / 6 * 2 * .pi + Double(k) * 2
                let q = CGPoint(x: a.x + CGFloat(cos(ang)) * s * 0.4 * (0.5 + k), y: a.y - s * 0.4 + CGFloat(sin(ang)) * s * 0.3)
                var plus = Path()
                plus.move(to: CGPoint(x: q.x - 4, y: q.y)); plus.addLine(to: CGPoint(x: q.x + 4, y: q.y))
                plus.move(to: CGPoint(x: q.x, y: q.y - 4)); plus.addLine(to: CGPoint(x: q.x, y: q.y + 4))
                g2.stroke(plus, with: .color(Color(red: 0.4, green: 0.95, blue: 0.4)), lineWidth: 2.5)
            }
            return
        }
        let travel = min(1, k / 0.75)
        func along(_ f: CGFloat, wobble: CGFloat = 0) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f - sin(f * .pi) * s * 0.25 + wobble)
        }
        switch type {
        case .grass:
            for i in 0..<4 {
                let f = travel - CGFloat(i) * 0.12
                guard f > 0, f < 1 else { continue }
                let p = along(f, wobble: CGFloat(sin(Double(f) * 12 + Double(i))) * s * 0.05)
                var leaf = Path(ellipseIn: CGRect(x: -s * 0.07, y: -s * 0.03, width: s * 0.14, height: s * 0.06))
                leaf = leaf.applying(CGAffineTransform(rotationAngle: CGFloat(Double(f) * 14 + Double(i))).concatenating(CGAffineTransform(translationX: p.x, y: p.y)))
                g.fill(leaf, with: .color(Color(red: 0.4, green: 0.82, blue: 0.25)))
                g.stroke(leaf, with: .color(Color(red: 0.12, green: 0.4, blue: 0.08)), lineWidth: 1)
            }
        case .water:
            for i in 0..<5 {
                let f = travel - CGFloat(i) * 0.08
                guard f > 0, f < 1 else { continue }
                let p = along(f, wobble: CGFloat(sin(Double(f) * 18 + Double(i) * 2)) * s * 0.06)
                let r = s * (0.05 + 0.015 * CGFloat(i % 3))
                g.fill(disc(p, r), with: .color(Color(red: 0.55, green: 0.8, blue: 1).opacity(0.75)))
                g.stroke(disc(p, r), with: .color(Color(red: 0.2, green: 0.45, blue: 0.9)), lineWidth: 1.2)
                g.fill(disc(CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.35), r * 0.25), with: .color(.white))
            }
        case .fire:
            for i in 0..<3 {
                let f = travel - CGFloat(i) * 0.15
                guard f > 0, f < 1 else { continue }
                let p = along(f)
                let r = s * 0.085
                g.fill(disc(p, r * 1.6), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.6, blue: 0.1).opacity(0.6), .clear]), center: p, startRadius: 0, endRadius: r * 1.6))
                g.fill(disc(p, r), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.6), Color(red: 1, green: 0.5, blue: 0.1)]), center: p, startRadius: 0, endRadius: r))
            }
        case .electric:
            if k > 0.25 && k < 0.85 {
                var bolt = Path()
                bolt.move(to: CGPoint(x: b.x + s * 0.05, y: b.y - s * 1.6))
                var y = b.y - s * 1.6
                var x = b.x + s * 0.05
                var flip: CGFloat = 1
                while y < b.y - s * 0.4 {
                    y += s * 0.16; x += flip * s * 0.1; flip = -flip
                    bolt.addLine(to: CGPoint(x: x, y: y))
                }
                g.stroke(bolt, with: .color(Color(red: 1, green: 0.95, blue: 0.4)), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                g.stroke(bolt, with: .color(.white), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        case .normal:
            if k > 0.25 && k < 0.7 {
                var star = Path()
                let c = CGPoint(x: b.x, y: b.y - s * 0.4)
                for i in 0..<12 {
                    let ang = Double(i) / 12 * 2 * .pi
                    let rr = i % 2 == 0 ? s * 0.3 : s * 0.12
                    let p = CGPoint(x: c.x + CGFloat(cos(ang)) * rr, y: c.y + CGFloat(sin(ang)) * rr)
                    if i == 0 { star.move(to: p) } else { star.addLine(to: p) }
                }
                star.closeSubpath()
                g.fill(star, with: .color(.white.opacity(0.9)))
                g.stroke(star, with: .color(Color(red: 1, green: 0.8, blue: 0.2)), lineWidth: 2)
            }
        }
    }

    static func banana(_ g: GraphicsContext, at c: CGPoint, w: CGFloat) {
        let h = w * 0.45
        var ban = Path()
        ban.move(to: CGPoint(x: c.x - w * 0.5, y: c.y - h * 0.4))
        ban.addQuadCurve(to: CGPoint(x: c.x + w * 0.5, y: c.y - h * 0.5), control: CGPoint(x: c.x - w * 0.02, y: c.y + h * 1.05))
        ban.addQuadCurve(to: CGPoint(x: c.x - w * 0.5, y: c.y - h * 0.4), control: CGPoint(x: c.x, y: c.y + h * 0.02))
        ban.closeSubpath()
        g.fill(ban, with: .color(Color(red: 1, green: 0.86, blue: 0.2)))
        g.stroke(ban, with: .color(Color(red: 0.5, green: 0.34, blue: 0.04)), lineWidth: 1.4)
        g.fill(Path(CGRect(x: c.x + w * 0.45, y: c.y - h * 0.6, width: w * 0.08, height: h * 0.18)), with: .color(Color(red: 0.42, green: 0.28, blue: 0.08)))
    }

    // MARK: The live field

    static func scene(_ ctx: GraphicsContext, size: CGSize, you: CDCritter, foe: CDCritter?, fx: CDFx, now: Date) {
        let w = size.width, h = size.height
        let t = now.timeIntervalSinceReferenceDate
        let foeS = min(w * 0.36, h * 0.4), youS = min(w * 0.5, h * 0.58)
        var foeFeet = CGPoint(x: w * 0.71, y: h * 0.44)
        var youFeet = CGPoint(x: w * 0.25, y: h * 1.02)
        // Lunges, the foe's entrance, and fainting.
        let lunge = now.timeIntervalSince(fx.lungeAt)
        if lunge < 0.3 {
            let k = CGFloat(sin(.pi * lunge / 0.3)) * w * 0.07
            if fx.lungeFoe { foeFeet.x -= k; foeFeet.y += k * 0.5 } else { youFeet.x += k; youFeet.y -= k * 0.5 }
        }
        let enter = now.timeIntervalSince(fx.enterAt)
        if enter < 0.5 { foeFeet.x += CGFloat(1 - enter / 0.5) * w * 0.6 }
        let faint = now.timeIntervalSince(fx.faintAt)
        var foeAlpha = 1.0, youAlpha = 1.0
        if faint >= 0 && faint < 10 {
            let k = min(1, faint / 0.5)
            if fx.faintFoe { foeFeet.y += CGFloat(k) * foeS * 0.5; foeAlpha = 1 - k } else { youFeet.y += CGFloat(k) * youS * 0.5; youAlpha = 1 - k }
        }
        // Hit blink.
        let hit = now.timeIntervalSince(fx.hitAt)
        if hit < 0.45 && Int(hit * 14) % 2 == 0 { if fx.hitFoe { foeAlpha *= 0.25 } else { youAlpha *= 0.25 } }
        let bob = CGFloat(sin(t * 2.4)) * h * 0.006
        if let foe {
            var g = ctx
            g.opacity = foeAlpha
            critter(g, foe.species, feet: CGPoint(x: foeFeet.x, y: foeFeet.y + bob), s: foeS, back: false, t: t)
        }
        var g = ctx
        g.opacity = youAlpha
        critter(g, you.species, feet: CGPoint(x: youFeet.x, y: youFeet.y - bob), s: youS, back: true, t: t)
        // The move flying across.
        let e = now.timeIntervalSince(fx.effectAt)
        if e < 0.8 {
            let from = fx.effectFromFoe ? CGPoint(x: foeFeet.x, y: foeFeet.y - foeS * 0.45) : CGPoint(x: youFeet.x + youS * 0.1, y: youFeet.y - youS * 0.6)
            let to = fx.effectFromFoe ? CGPoint(x: youFeet.x, y: youFeet.y - youS * 0.3) : CGPoint(x: foeFeet.x, y: foeFeet.y)
            effect(ctx, type: fx.effectType, heals: fx.effectHeals, from: fx.effectHeals ? (fx.effectFromFoe ? CGPoint(x: foeFeet.x, y: foeFeet.y) : CGPoint(x: youFeet.x, y: youFeet.y - youS * 0.5)) : from,
                   to: to, k: CGFloat(e / 0.8), s: fx.effectFromFoe ? foeS : youS * 0.8)
        }
        // ×2 / ×½ / MISS badge over the one that was hit.
        let bAge = now.timeIntervalSince(fx.badgeAt)
        if let badge = fx.badge, bAge < 1.1 {
            let anchor = fx.badgeOnFoe ? CGPoint(x: foeFeet.x + foeS * 0.35, y: foeFeet.y - foeS * 0.95) : CGPoint(x: youFeet.x + youS * 0.38, y: youFeet.y - youS * 0.9)
            let rise = CGFloat(min(1, bAge / 0.25)) * 10
            let text = ctx.resolve(Text(badge.text).font(.system(size: 20, weight: .black, design: .rounded)).foregroundColor(.white))
            let sz = text.measure(in: CGSize(width: 200, height: 60))
            var rect = CGRect(x: anchor.x - sz.width / 2 - 9, y: anchor.y - rise - sz.height / 2 - 3, width: sz.width + 18, height: sz.height + 6)
            rect.origin.x = max(4, min(w - rect.width - 4, rect.origin.x))
            rect.origin.y = max(4, min(h - rect.height - 4, rect.origin.y))
            var g2 = ctx
            g2.opacity = bAge > 0.8 ? max(0, 1 - (bAge - 0.8) / 0.3) : 1
            g2.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .color(badge.color))
            g2.stroke(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .color(.white), lineWidth: 2)
            g2.draw(text, at: CGPoint(x: rect.midX, y: rect.midY))
        }
    }
}

// MARK: - Static pieces and controls

/// The battle backdrop: sky, a far tree line, the meadow, and the two grass platforms.
private struct CDField: View, Equatable {
    let level: Int

    var body: some View {
        Canvas { ctx, s in
            let w = s.width, h = s.height
            let dusk = level >= 6
            let skyTop = dusk ? Color(red: 0.98, green: 0.62, blue: 0.42) : Color(red: 0.55, green: 0.8, blue: 0.98)
            let skyBottom = dusk ? Color(red: 1, green: 0.85, blue: 0.62) : Color(red: 0.88, green: 0.96, blue: 1)
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h * 0.5)), with: .linearGradient(Gradient(colors: [skyTop, skyBottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h * 0.5)))
            var clouds = Path()
            for (fx, fy, r) in [(0.18, 0.1, 22.0), (0.58, 0.06, 18.0), (0.86, 0.16, 15.0)] as [(CGFloat, CGFloat, CGFloat)] {
                for k in 0..<3 { clouds.addEllipse(in: CGRect(x: w * fx + CGFloat(k - 1) * r * 0.9 - r, y: h * fy - (k == 1 ? r * 0.4 : 0), width: r * 2, height: r * 1.3)) }
            }
            ctx.fill(clouds, with: .color(.white.opacity(0.85)))
            // Far tree line.
            var trees = Path()
            trees.move(to: CGPoint(x: 0, y: h * 0.5))
            var x: CGFloat = 0
            var k = 0
            while x <= w + 20 {
                let top = h * (0.4 + 0.05 * CGFloat(CDArt.hash(Double(k))))
                trees.addQuadCurve(to: CGPoint(x: x + 22, y: h * 0.47), control: CGPoint(x: x + 11, y: top - h * 0.03))
                x += 22; k += 1
            }
            trees.addLine(to: CGPoint(x: w, y: h * 0.52)); trees.addLine(to: CGPoint(x: 0, y: h * 0.52)); trees.closeSubpath()
            ctx.fill(trees, with: .color(dusk ? Color(red: 0.32, green: 0.42, blue: 0.3) : Color(red: 0.3, green: 0.58, blue: 0.32)))
            // Meadow.
            ctx.fill(Path(CGRect(x: 0, y: h * 0.5, width: w, height: h * 0.5)), with: .linearGradient(Gradient(colors: [Color(red: 0.58, green: 0.82, blue: 0.42), Color(red: 0.44, green: 0.72, blue: 0.3)]),
                                                                                                     startPoint: CGPoint(x: 0, y: h * 0.5), endPoint: CGPoint(x: 0, y: h)))
            var tufts = Path()
            for i in 0..<26 {
                let px = w * CGFloat(CDArt.hash(Double(i) * 3.7)), py = h * (0.55 + 0.45 * CGFloat(CDArt.hash(Double(i) * 1.9)))
                tufts.move(to: CGPoint(x: px, y: py)); tufts.addLine(to: CGPoint(x: px - 2, y: py - 6))
                tufts.move(to: CGPoint(x: px, y: py)); tufts.addLine(to: CGPoint(x: px + 2, y: py - 6))
            }
            ctx.stroke(tufts, with: .color(Color(red: 0.28, green: 0.55, blue: 0.2).opacity(0.6)), lineWidth: 1.2)
            // Platforms: a raised oval of grass with a darker rim.
            for (c, rx, ry) in [(CGPoint(x: w * 0.71, y: h * 0.445), w * 0.26, h * 0.06), (CGPoint(x: w * 0.25, y: h * 1.0), w * 0.36, h * 0.09)] {
                ctx.fill(CDArt.oval(CGPoint(x: c.x, y: c.y + ry * 0.35), rx, ry), with: .color(Color(red: 0.3, green: 0.52, blue: 0.2)))
                ctx.fill(CDArt.oval(c, rx, ry), with: .linearGradient(Gradient(colors: [Color(red: 0.62, green: 0.86, blue: 0.42), Color(red: 0.46, green: 0.72, blue: 0.3)]),
                                                                    startPoint: CGPoint(x: 0, y: c.y - ry), endPoint: CGPoint(x: 0, y: c.y + ry)))
                ctx.stroke(CDArt.oval(c, rx, ry), with: .color(Color(red: 0.25, green: 0.45, blue: 0.16)), lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
    }
}

/// An HP box like the handheld games': cream panel, name and level, the type, and the HP bar.
private struct CDHPBox: View {
    let name: String
    let level: Int
    let type: CDType
    let hp: Double
    let maxHP: Double
    let numbers: Bool
    let compact: Bool
    /// The rival's line-up, one marker per critter (`true` = already knocked out).
    var party: [Bool] = []

    var body: some View {
        let frac = maxHP > 0 ? max(0, min(1, hp / maxHP)) : 0
        let bar = frac > 0.5 ? Color(red: 0.3, green: 0.82, blue: 0.35) : (frac > 0.2 ? Color(red: 0.98, green: 0.78, blue: 0.15) : Color(red: 0.95, green: 0.25, blue: 0.2))
        VStack(alignment: .leading, spacing: compact ? 2 : 4) {
            HStack(spacing: 5) {
                Image(systemName: CDArt.icon(type))
                    .font(.system(size: compact ? 9 : 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: compact ? 15 : 19, height: compact ? 15 : 19)
                    .background(Circle().fill(CDArt.color(type)))
                    .overlay(Circle().stroke(.black.opacity(0.4), lineWidth: 1))
                Text(verbatim: name.uppercased())
                    .font(.system(size: compact ? 11 : 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.22, green: 0.22, blue: 0.24))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(verbatim: "Lv\(level)")
                    .font(.system(size: compact ? 10 : 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.22, green: 0.22, blue: 0.24))
            }
            HStack(spacing: 4) {
                Text(verbatim: "HP")
                    .font(.system(size: compact ? 7 : 9, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 1, green: 0.85, blue: 0.3))
                    .padding(.horizontal, 3)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.32, green: 0.26, blue: 0.2)))
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(red: 0.3, green: 0.3, blue: 0.32))
                        Capsule().fill(bar).frame(width: g.size.width * frac)
                    }
                }
                .frame(height: compact ? 5 : 7)
            }
            if numbers {
                Text(verbatim: "\(Int(hp.rounded()))/\(Int(maxHP))")
                    .font(.system(size: compact ? 10 : 13, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(red: 0.22, green: 0.22, blue: 0.24))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else if !party.isEmpty {
                HStack(spacing: compact ? 3 : 4) {
                    Spacer(minLength: 0)
                    ForEach(party.indices, id: \.self) { i in
                        Circle()
                            .fill(party[i] ? Color(white: 0.62) : Color(red: 0.95, green: 0.3, blue: 0.25))
                            .overlay(Circle().fill(.white.opacity(party[i] ? 0 : 0.45)).frame(width: compact ? 2.5 : 3.5).offset(x: -1, y: -1))
                            .overlay(Circle().stroke(Color(red: 0.3, green: 0.32, blue: 0.34), lineWidth: 1.2))
                            .frame(width: compact ? 8 : 10, height: compact ? 8 : 10)
                    }
                }
            }
        }
        .padding(.horizontal, compact ? 7 : 10)
        .padding(.vertical, compact ? 4 : 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [Color(red: 0.99, green: 0.99, blue: 0.92), Color(red: 0.92, green: 0.93, blue: 0.82)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.3), radius: 0, x: 3, y: 3)
        )
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 0.3, green: 0.32, blue: 0.34), lineWidth: 2))
    }
}

/// A move button's face: its type colour, type icon and name (the Snack shows the uses left).
private struct CDMoveFace: View {
    let move: CDMove
    let left: Int?
    let foeType: CDType?
    let compact: Bool

    var body: some View {
        let tint = move.heals ? Color(red: 0.93, green: 0.55, blue: 0.68) : CDArt.color(move.type)
        HStack(spacing: compact ? 5 : 8) {
            Group {
                if move.heals {
                    Canvas { ctx, s in CDArt.banana(ctx, at: CGPoint(x: s.width / 2, y: s.height / 2), w: s.width * 0.9) }
                } else {
                    Image(systemName: CDArt.icon(move.type))
                        .font(.system(size: compact ? 12 : 16, weight: .bold))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: compact ? 22 : 30, height: compact ? 22 : 30)
            .background(Circle().fill(.white))
            Text(L(move.en, move.vi))
                .font(.system(size: compact ? 12 : 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 0, x: 1, y: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            if let left {
                Text(verbatim: "×\(left)")
                    .font(.system(size: compact ? 11 : 14, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, compact ? 8 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [tint.lit(0.18), tint.shade(0.12)], startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.85), lineWidth: 2))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.black.opacity(0.35), lineWidth: 1).padding(-1))
    }
}

private struct CDMoveStyle: ButtonStyle {
    var lit: Bool
    var dim: Bool

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed || lit
        return configuration.label
            .scaleEffect(down ? 0.95 : 1)
            .brightness(down ? 0.08 : 0)
            .opacity(dim && !lit ? 0.55 : 1)
    }
}

/// The dark lower screen behind the message box and the moves.
private struct CDPanel: View, Equatable {
    var body: some View {
        Canvas { ctx, s in
            ctx.fill(Path(CGRect(origin: .zero, size: s)), with: .linearGradient(Gradient(colors: [Color(red: 0.2, green: 0.24, blue: 0.3), Color(red: 0.11, green: 0.13, blue: 0.17)]),
                                                                                 startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height)))
            var grid = Path()
            var y: CGFloat = 0
            while y < s.height { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: s.width, y: y)); y += 6 }
            ctx.stroke(grid, with: .color(.white.opacity(0.03)), lineWidth: 1)
            ctx.fill(Path(CGRect(x: 0, y: 0, width: s.width, height: 3)), with: .color(Color(red: 0.88, green: 0.4, blue: 0.22)))
        }
        .allowsHitTesting(false)
    }
}
