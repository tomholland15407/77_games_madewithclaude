package com.gogs.bananagame.games.critterduel

import kotlin.math.max
import kotlin.math.min

/** The battle rules of Critter Duel (iOS CritterDuelGame.swift `CDType` … `CDBattle`), ported 1:1. */
enum class CDType {
    NORMAL, GRASS, FIRE, WATER, ELECTRIC;

    /** Damage multiplier when a move of this type hits a critter of type [defender]. */
    fun against(defender: CDType): Double = when {
        (this == GRASS && defender == WATER) || (this == WATER && defender == FIRE) ||
            (this == FIRE && defender == GRASS) || (this == ELECTRIC && defender == WATER) -> 2.0
        (this == GRASS && (defender == GRASS || defender == FIRE)) || (this == FIRE && (defender == FIRE || defender == WATER)) ||
            (this == WATER && (defender == WATER || defender == GRASS)) || (this == ELECTRIC && (defender == ELECTRIC || defender == GRASS)) -> 0.5
        else -> 1.0
    }
}

class CDMove(val en: String, val vi: String, val type: CDType, val power: Int, val accuracy: Double, val heals: Boolean, val pp: Int)

object CDMoves {
    const val TACKLE = 0; const val LEAF_CUT = 1; const val BUBBLE = 2; const val EMBER = 3; const val SNACK = 4
    const val ZAP = 5; const val FLARE = 6; const val BOLT = 7; const val TORRENT = 8; const val SEED_STORM = 9
    val all = listOf(
        CDMove("Tackle", "Húc", CDType.NORMAL, 40, 1.0, false, 99),
        CDMove("Leaf Cut", "Cắt Lá", CDType.GRASS, 55, 1.0, false, 99),
        CDMove("Bubble", "Bong Bóng", CDType.WATER, 50, 1.0, false, 99),
        CDMove("Ember", "Than Hồng", CDType.FIRE, 50, 1.0, false, 99),
        CDMove("Snack", "Ăn Vặt", CDType.NORMAL, 0, 1.0, true, 2),
        CDMove("Zap", "Chích Điện", CDType.ELECTRIC, 50, 1.0, false, 99),
        CDMove("Flare", "Bùng Lửa", CDType.FIRE, 80, 0.8, false, 99),
        CDMove("Bolt", "Sét Đánh", CDType.ELECTRIC, 80, 0.8, false, 99),
        CDMove("Torrent", "Thác Nước", CDType.WATER, 80, 0.8, false, 99),
        CDMove("Seed Storm", "Bão Hạt", CDType.GRASS, 80, 0.8, false, 99),
    )
}

class CDSpecies(val name: String, val type: CDType, val hp: Int, val atk: Int, val def: Int, val spd: Int, val moves: List<Int>)

object CDDex {
    const val BANANO = 0; const val COCONUTTY = 1; const val CHILIPEP = 2; const val LEMONZAP = 3
    const val MELONOX = 4; const val BLUBBERY = 5; const val PEPPEROAR = 6
    val all = listOf(
        CDSpecies("Banano", CDType.GRASS, 60, 56, 52, 62, listOf(CDMoves.LEAF_CUT, CDMoves.BUBBLE, CDMoves.EMBER, CDMoves.SNACK)),
        CDSpecies("Coconutty", CDType.WATER, 55, 46, 62, 35, listOf(CDMoves.TACKLE, CDMoves.BUBBLE, CDMoves.TORRENT)),
        CDSpecies("Chilipep", CDType.FIRE, 45, 62, 42, 68, listOf(CDMoves.TACKLE, CDMoves.EMBER, CDMoves.FLARE)),
        CDSpecies("Lemonzap", CDType.ELECTRIC, 46, 58, 46, 78, listOf(CDMoves.TACKLE, CDMoves.ZAP, CDMoves.BOLT)),
        CDSpecies("Melonox", CDType.GRASS, 70, 52, 64, 30, listOf(CDMoves.TACKLE, CDMoves.LEAF_CUT, CDMoves.SEED_STORM)),
        CDSpecies("Blubbery", CDType.WATER, 50, 55, 50, 55, listOf(CDMoves.TACKLE, CDMoves.BUBBLE, CDMoves.TORRENT)),
        CDSpecies("Pepperoar", CDType.FIRE, 70, 58, 50, 50, listOf(CDMoves.TACKLE, CDMoves.EMBER, CDMoves.FLARE)),
    )
}

/** SplitMix64, bit-identical to the iOS `CDRandom`, so seeded battles (the demo) replay the same. */
class CDRandom(var state: ULong) {
    fun next(): ULong {
        state += 0x9E3779B97F4A7C15uL
        var z = state
        z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9uL
        z = (z xor (z shr 27)) * 0x94D049BB133111EBuL
        return z xor (z shr 31)
    }
    fun unit(): Double = (next() shr 11).toDouble() / (1uL shl 53).toDouble()
    fun int(n: Int): Int = (next() % max(1, n).toULong()).toInt()
}

class CDCritter(val species: Int, val level: Int, knownMoves: Int = 4) {
    private val s = CDDex.all[species]
    val maxHP = 2 * s.hp * level / 100 + level + 10
    var hp = maxHP
    val atk = 2 * s.atk * level / 100 + 5
    val def = 2 * s.def * level / 100 + 5
    val spd = 2 * s.spd * level / 100 + 5
    val moves: List<Int> = s.moves.take(knownMoves)
    val pp: IntArray = IntArray(moves.size) { CDMoves.all[moves[it]].pp }
    val name get() = s.name
    val type get() = s.type
}

/** What happened in a turn, in order, for the view to play back. `foe` on hit/miss = the one taking it. */
sealed class CDEvent {
    data class Use(val foe: Boolean, val move: Int) : CDEvent()
    data class Hit(val foe: Boolean, val amount: Int, val mult: Double, val crit: Boolean) : CDEvent()
    data class Miss(val foe: Boolean) : CDEvent()
    data class Heal(val foe: Boolean, val amount: Int) : CDEvent()
    data class Faint(val foe: Boolean) : CDEvent()
    data class Send(val index: Int) : CDEvent()
}

/** One level's battle; [turn] resolves a whole turn (fastest first, a Snack always first). */
class CDBattle(val you: CDCritter, val foes: List<CDCritter>, val smart: Double, val rng: CDRandom) {
    var current = 0
    val foe: CDCritter? get() = if (current < foes.size) foes[current] else null
    val won get() = current >= foes.size
    val lost get() = you.hp <= 0

    companion object {
        fun timeLimit(level: Int): Double = doubleArrayOf(60.0, 60.0, 75.0, 80.0, 90.0, 105.0, 110.0)[min(max(level, 1), 7) - 1]

        fun level(level: Int, seed: ULong): CDBattle {
            val rng = CDRandom(seed)
            val i = min(max(level, 1), 7) - 1
            val yourLevel = intArrayOf(10, 10, 11, 12, 13, 14, 15)[i]
            val all5 = listOf(CDDex.COCONUTTY, CDDex.CHILIPEP, CDDex.LEMONZAP, CDDex.MELONOX, CDDex.BLUBBERY)
            val late5 = listOf(CDDex.CHILIPEP, CDDex.LEMONZAP, CDDex.MELONOX, CDDex.BLUBBERY, CDDex.COCONUTTY)
            val pools = listOf(listOf(CDDex.COCONUTTY, CDDex.BLUBBERY), listOf(CDDex.CHILIPEP, CDDex.MELONOX, CDDex.LEMONZAP),
                all5, all5, all5, late5, late5)
            val count = intArrayOf(1, 1, 2, 2, 2, 3, 3)[i]
            val foeLevels = listOf(listOf(8), listOf(9), listOf(9, 10), listOf(11, 12), listOf(13, 14), listOf(14, 15, 15), listOf(15, 16, 17))[i]
            val known = intArrayOf(2, 2, 2, 3, 3, 3, 3)[i]
            val pool = pools[i].toMutableList()
            val foes = mutableListOf<CDCritter>()
            for (k in 0 until count) {
                // The level-7 finale is always the bell-pepper boss.
                val species = if (i == 6 && k == count - 1) CDDex.PEPPEROAR else pool.removeAt(rng.int(pool.size))
                foes += CDCritter(species, foeLevels[k], known)
            }
            return CDBattle(CDCritter(CDDex.BANANO, yourLevel), foes, doubleArrayOf(0.0, 0.25, 0.5, 0.7, 0.85, 1.0, 1.0)[i], rng)
        }

        /** Expected damage of `move` from a onto d (no crits or misses) — the trainer's yardstick. */
        fun expected(move: Int, a: CDCritter, d: CDCritter): Double {
            val m = CDMoves.all[move]
            if (m.heals) return 0.0
            return base(m, a, d) * m.type.against(d.type) * 0.925 * m.accuracy
        }

        private fun base(m: CDMove, a: CDCritter, d: CDCritter): Double =
            ((2 * a.level / 5 + 2).toDouble() * m.power * a.atk / d.def) / 50 + 2
    }

    private fun strike(move: Int, attackerIsFoe: Boolean): List<CDEvent> {
        val out = mutableListOf<CDEvent>(CDEvent.Use(attackerIsFoe, move))
        val m = CDMoves.all[move]
        val a = if (attackerIsFoe) foes[current] else you
        a.moves.indexOf(move).let { if (it >= 0) a.pp[it] -= 1 }
        if (m.heals) {
            val amount = min(a.maxHP - a.hp, a.maxHP / 2)
            a.hp += amount
            out += CDEvent.Heal(attackerIsFoe, amount)
            return out
        }
        if (rng.unit() > m.accuracy) { out += CDEvent.Miss(!attackerIsFoe); return out }
        val d = if (attackerIsFoe) you else foes[current]
        val crit = rng.unit() < 0.0625
        val mult = m.type.against(d.type)
        val raw = base(m, a, d) * mult * (if (crit) 1.5 else 1.0) * (0.85 + 0.15 * rng.unit())
        val amount = min(d.hp, max(1, raw.toInt()))
        d.hp -= amount
        out += CDEvent.Hit(!attackerIsFoe, amount, mult, crit)
        if (d.hp <= 0) out += CDEvent.Faint(!attackerIsFoe)
        return out
    }

    /** The rival trainer's pick: usually the move that hurts most (by level), else any move. */
    fun foeChoice(): Int {
        val f = foe ?: return CDMoves.TACKLE
        val usable = f.moves.indices.filter { f.pp[it] > 0 }.map { f.moves[it] }
        if (rng.unit() < smart) {
            val best = usable.maxByOrNull { expected(it, f, you) }
            if (best != null) return best
        }
        return if (usable.isEmpty()) CDMoves.TACKLE else usable[rng.int(usable.size)]
    }

    /** Resolve a full turn with your move (an index into Banano's moves). */
    fun turn(choice: Int): List<CDEvent> {
        if (won || lost || choice !in you.moves.indices || you.pp[choice] <= 0) return emptyList()
        val yours = you.moves[choice]
        val theirs = foeChoice()
        val youFirst = when {
            CDMoves.all[yours].heals -> true
            you.spd != foes[current].spd -> you.spd > foes[current].spd
            else -> rng.unit() < 0.5
        }
        val events = mutableListOf<CDEvent>()
        for (foeTurn in if (youFirst) listOf(false, true) else listOf(true, false)) {
            if (lost || foe == null || foes[current].hp <= 0) break
            events += strike(if (foeTurn) theirs else yours, foeTurn)
        }
        if (foe != null && foes[current].hp <= 0) {
            current += 1
            if (current < foes.size) events += CDEvent.Send(current)
        }
        return events
    }
}
