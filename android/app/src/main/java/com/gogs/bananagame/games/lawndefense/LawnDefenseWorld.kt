package com.gogs.bananagame.games.lawndefense

import com.gogs.bananagame.core.roundAway
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

// The battle rules of Lawn Defense (iOS LawnDefenseGame.swift `LDScene` … `LDWorld`), ported 1:1.
// Value types became mutable classes; every rule, number and RNG call order is the same.

enum class LDScene { BACKYARD, DESERT, PIRATE, FRONTIER, GLACIER, FUTURE, ROOFTOP }

/** The seed packets, in bar order: sun, shooters, then walls, traps and bombs. */
enum class LDPlantKind {
    SUNFLOWER, PEASHOOTER, POPPER, FROST, LOBBER, WALLNUT, PEEL, FLYTRAP, CHERRY, CHILI;
    val cost get() = intArrayOf(50, 100, 200, 175, 300, 50, 25, 150, 150, 125)[ordinal]
    /** Seconds before the packet can be planted again. */
    val recharge get() = doubleArrayOf(3.0, 4.5, 6.0, 6.0, 8.0, 16.0, 14.0, 10.0, 26.0, 24.0)[ordinal]
    /** Bites a zombie needs to eat it (a zombie bites once a second). */
    val bites get() = doubleArrayOf(3.0, 3.0, 3.0, 3.0, 3.0, 26.0, 3.0, 3.0, 99.0, 99.0)[ordinal]
    val shoots get() = this == PEASHOOTER || this == POPPER || this == FROST
    /** Lit bombs: nothing can squash one before it goes off. */
    val isBomb get() = this == CHERRY || this == CHILI
}

enum class LDZombieKind {
    NORMAL, CONE, BUCKET, FLAG, IMP, RUNNER, JUMPER, SHIELD;
    val hp get() = doubleArrayOf(6.0, 6.0, 6.0, 6.0, 3.0, 6.0, 7.0, 6.0)[ordinal]
    val armor get() = doubleArrayOf(0.0, 8.0, 18.0, 0.0, 0.0, 12.0, 0.0, 0.0)[ordinal]
    val shield get() = doubleArrayOf(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 14.0)[ordinal]
    val pace get() = doubleArrayOf(1.0, 1.0, 1.0, 1.15, 1.5, 1.9, 1.7, 0.95)[ordinal]
}

enum class LDBossMove(val windup: Double) {
    SUMMON(0.9), AMBUSH(1.4), GRAVES(1.1), BOMBARD(1.5), CHARGE(1.6), FREEZE(1.4), ROLL(1.1), LASER(1.6), STOMP(1.4)
}

enum class LDBossKind {
    GROUNDSKEEPER, PHARAOH, CAPTAIN, OUTLAW, MAMMOTH, MECH, MEGABOT;
    /** Lanes it covers: the groundskeeper walks one, the locomotive fills two, the rest three. */
    val span get() = intArrayOf(1, 3, 3, 2, 3, 3, 3)[ordinal]
    val moves: List<LDBossMove> get() = when (this) {
        GROUNDSKEEPER -> emptyList()
        PHARAOH -> listOf(LDBossMove.GRAVES, LDBossMove.AMBUSH, LDBossMove.SUMMON)
        CAPTAIN -> listOf(LDBossMove.BOMBARD, LDBossMove.AMBUSH, LDBossMove.SUMMON)
        OUTLAW -> listOf(LDBossMove.CHARGE, LDBossMove.BOMBARD, LDBossMove.SUMMON)
        MAMMOTH -> listOf(LDBossMove.FREEZE, LDBossMove.ROLL, LDBossMove.SUMMON)
        MECH -> listOf(LDBossMove.LASER, LDBossMove.BOMBARD, LDBossMove.SUMMON)
        MEGABOT -> listOf(LDBossMove.ROLL, LDBossMove.STOMP, LDBossMove.AMBUSH, LDBossMove.SUMMON)
    }
}

enum class LDShot { PEA, POPCORN, FROST, MELON }
enum class LDRollerKind { SNOWBALL, FIREBALL, ICEBALL }

sealed class LDTarget {
    data class Zombie(val id: Int) : LDTarget()
    data object Boss : LDTarget()
    data class Roller(val id: Int) : LDTarget()
}

data class LDTile(val row: Int, val col: Int)

/** SplitMix64, bit-identical to the iOS `LDRandom`. */
class LDRandom(var state: ULong) {
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

/** One level's recipe. */
class LDParams(
    var scene: LDScene, var rows: List<Int>, var count: Int, var mix: List<Pair<LDZombieKind, Double>>,
    var firstSpawn: Double, var gap: Double, var finalWave: Int, var speed: Double, var skyEvery: Double,
    var startSun: Int, var mowers: Boolean, var packets: List<LDPlantKind>, var boss: LDBossKind?,
    var bossHP: Double, var bossEvery: Double, var bossPower: Int,
) {
    companion object {
        fun level(level: Int): LDParams {
            val i = min(max(level, 1), 7) - 1
            fun m(vararg p: Pair<LDZombieKind, Double>) = p.toList()
            val mixes = listOf(
                m(LDZombieKind.BUCKET to 0.16, LDZombieKind.CONE to 0.34),
                m(LDZombieKind.BUCKET to 0.2, LDZombieKind.SHIELD to 0.12, LDZombieKind.CONE to 0.32),
                m(LDZombieKind.BUCKET to 0.18, LDZombieKind.JUMPER to 0.11, LDZombieKind.SHIELD to 0.07, LDZombieKind.CONE to 0.31),
                m(LDZombieKind.BUCKET to 0.18, LDZombieKind.RUNNER to 0.12, LDZombieKind.JUMPER to 0.08, LDZombieKind.CONE to 0.29),
                m(LDZombieKind.BUCKET to 0.19, LDZombieKind.SHIELD to 0.09, LDZombieKind.JUMPER to 0.08, LDZombieKind.RUNNER to 0.07, LDZombieKind.CONE to 0.29),
                m(LDZombieKind.BUCKET to 0.2, LDZombieKind.RUNNER to 0.09, LDZombieKind.SHIELD to 0.09, LDZombieKind.JUMPER to 0.07, LDZombieKind.CONE to 0.28),
                m(LDZombieKind.BUCKET to 0.2, LDZombieKind.RUNNER to 0.1, LDZombieKind.SHIELD to 0.08, LDZombieKind.JUMPER to 0.08, LDZombieKind.CONE to 0.28),
            )
            return LDParams(
                scene = LDScene.entries[i],
                rows = listOf(0, 1, 2, 3, 4),
                count = intArrayOf(18, 21, 22, 20, 21, 23, 23)[i],
                mix = mixes[i],
                firstSpawn = doubleArrayOf(12.0, 12.0, 11.5, 11.5, 11.5, 11.0, 11.0)[i],
                gap = doubleArrayOf(4.6, 4.4, 4.4, 4.5, 4.3, 4.4, 4.3)[i],
                finalWave = intArrayOf(6, 6, 6, 7, 7, 7, 10)[i],
                speed = doubleArrayOf(0.38, 0.39, 0.39, 0.4, 0.4, 0.41, 0.41)[i],
                skyEvery = doubleArrayOf(5.5, 5.8, 5.8, 6.0, 5.8, 6.2, 7.0)[i],
                startSun = intArrayOf(125, 100, 100, 100, 100, 100, 100)[i],
                mowers = true,
                packets = LDPlantKind.entries.toList(),
                boss = LDBossKind.entries[i],
                bossHP = doubleArrayOf(60.0, 125.0, 115.0, 90.0, 130.0, 100.0, 150.0)[i],
                bossEvery = doubleArrayOf(9.0, 8.0, 8.5, 7.5, 7.0, 6.5, 6.5)[i],
                bossPower = 2,
            )
        }
    }
}

class LDPlant(val id: Int, val kind: LDPlantKind, val row: Int, val col: Int, var hp: Double, var timer: Double, val planted: Double) {
    var fired = -9.0
    var bitten = -9.0
    var frozen = 0.0
    var chewing = 0.0
    var gulp = -9.0
}

class LDZombie(val id: Int, val kind: LDZombieKind, val row: Int, var x: Double, var hp: Double, var armor: Double,
               var shield: Double, var speedK: Double, val born: Double) {
    var eating = false
    var hit = -9.0
    var died: Double? = null
    var burnt = false
    var eaten = false
    var slowUntil = -9.0
    var stunUntil = -9.0
    var hopped = -9.0
}

class LDPea(val id: Int, val row: Int, var x: Double, val shot: LDShot)
class LDLob(val id: Int, val row: Int, val x0: Double, var x1: Double, val t0: Double, val target: LDTarget)
class LDSun(val id: Int, var x: Double, var y: Double, val landY: Double, var life: Double, val born: Double)
class LDGrave(val id: Int, val row: Int, val col: Int, var hp: Double, val born: Double)
class LDRoller(val id: Int, val kind: LDRollerKind, val row: Int, var x: Double, var hp: Double, val born: Double)
class LDDrop(val id: Int, val kind: LDZombieKind, val row: Int, val x: Double, val fromX: Double, val t0: Double, val lands: Double)

enum class LDBossMode { ARRIVING, STANDING, WALKING, SHIFTING, CHARGING, RETREATING }

class LDBoss(val kind: LDBossKind, val maxHP: Double, var hp: Double, var row: Int, var y: Double, var x: Double) {
    var mode = LDBossMode.ARRIVING
    var clock = 2.5
    var move: LDBossMove? = null
    var windup = 0.0
    var targets: List<LDTile> = emptyList()
    var last: LDBossMove? = null
    var moves = 0
    var stunUntil = -9.0
    var hit = -9.0
    var died: Double? = null
    var threw = false
    var smashed = -9.0
    var arrivedAt = 0.0
    var lastAt = -9.0
    var lastTargets: List<LDTile> = emptyList()
    val rows: IntRange get() = row..(row + kind.span - 1)

    companion object { const val HOME = 5.6 }
}

/** A lane's mower: ready, running at x, or gone. */
class LDMower(var state: Int, var x: Double = 0.0) {
    companion object { const val READY = 0; const val RUNNING = 1; const val GONE = 2 }
}

class LDSplat(val row: Int, val x: Double, val t: Double, val shot: LDShot)
class LDBoom(val row: Int, val col: Int, val t: Double)
class LDBlaze(val row: Int, val t: Double)
class LDCrash(val row: Int, val col: Int, val t: Double)
class LDSpawn(val t: Double, val row: Int, val kind: LDZombieKind)

/** The whole battle: the view, the demo and the unit tests step the same code. */
class LDWorld(val params: LDParams, seed: ULong) {
    companion object {
        const val COLS = 7
        const val BITE_RATE = 1.0
        const val PEA_SPEED = 5.0
        const val SHOOT_EVERY = 1.4
        const val LOB_EVERY = 2.8
        const val LOB_TIME = 0.9
        const val SUNFLOWER_EVERY = 7.5
        const val SUN_VALUE = 25
        const val PEEL_ARM = 6.0
        const val ROLL_SPEED = 1.15
        const val CHARGE_STOP = 2.0

        /** Who drops in on an ambush tile (fixed by the tile, so the view can show them coming). */
        fun ambusher(tile: LDTile): LDZombieKind =
            listOf(LDZombieKind.IMP, LDZombieKind.NORMAL, LDZombieKind.IMP, LDZombieKind.CONE)[(tile.row + tile.col) % 4]
    }

    var t = 0.0
    var sun = params.startSun
    val plants = mutableListOf<LDPlant>()
    val zombies = mutableListOf<LDZombie>()
    val peas = mutableListOf<LDPea>()
    val lobs = mutableListOf<LDLob>()
    val suns = mutableListOf<LDSun>()
    val graves = mutableListOf<LDGrave>()
    val rollers = mutableListOf<LDRoller>()
    val drops = mutableListOf<LDDrop>()
    var boss: LDBoss? = null
    val mowers = List(5) { LDMower(if (params.mowers && it in params.rows) LDMower.READY else LDMower.GONE) }
    val recharge = DoubleArray(LDPlantKind.entries.size)
    var schedule = mutableListOf<LDSpawn>()
    var spawned = 0
    var skyTimer = 3.0
    val splats = mutableListOf<LDSplat>()
    val booms = mutableListOf<LDBoom>()
    val blazes = mutableListOf<LDBlaze>()
    val crashes = mutableListOf<LDCrash>()
    var won = false
    var lost = false
    var nextID = 1
    val rng = LDRandom(seed)

    init {
        // The horde: an even trickle, then a final rush led by a flag zombie (the boss follows it).
        val n = params.count
        val rush = max(1, min(params.finalWave, n))
        val kinds = mutableListOf<LDZombieKind>()
        val quota = params.mix.map { (k, share) -> k to (n * share).roundAway() }.toMutableList()
        repeat(n) {
            val q = quota.indexOfFirst { it.second > 0 }
            if (q >= 0) { kinds += quota[q].first; quota[q] = quota[q].first to quota[q].second - 1 } else kinds += LDZombieKind.NORMAL
        }
        var k = n - 1
        while (k > 0) { val j = rng.int(k + 1); val tmp = kinds[k]; kinds[k] = kinds[j]; kinds[j] = tmp; k-- }
        // Keep the opening gentle: the first two are plain zombies.
        for (a in 0 until min(2, n)) {
            if (kinds[a] == LDZombieKind.NORMAL) continue
            val j = kinds.indices.lastOrNull { kinds[it] == LDZombieKind.NORMAL }
            if (j != null && j > a) { val tmp = kinds[a]; kinds[a] = kinds[j]; kinds[j] = tmp }
        }
        var time = params.firstSpawn
        for (i in 0 until n) {
            val inRush = i >= n - rush
            val kind = if (i == n - rush) LDZombieKind.FLAG else kinds[i]
            schedule += LDSpawn(time, params.rows[rng.int(params.rows.size)], kind)
            if (i == n - rush - 1) time += params.gap + 3
            else if (inRush) time += 0.45 + rng.unit() * 0.4
            else time += params.gap * (0.85 + rng.unit() * 0.3) * (1 - 0.25 * i / max(1, n).toDouble())
        }
    }

    private fun newID(): Int { nextID += 1; return nextID }

    /** Fraction of the horde that has arrived (the flag meter). */
    val progress: Double get() = if (schedule.isEmpty()) 1.0 else spawned.toDouble() / schedule.size

    fun plantAt(row: Int, col: Int): LDPlant? = plants.firstOrNull { it.row == row && it.col == col }
    fun graveAt(row: Int, col: Int): LDGrave? = graves.firstOrNull { it.row == row && it.col == col }

    fun canPlant(kind: LDPlantKind) = kind in params.packets && sun >= kind.cost && recharge[kind.ordinal] <= 0

    /** The tiles a standing boss's bulk covers (nothing can be planted there). */
    fun bossCovers(row: Int, col: Int): Boolean {
        val b = boss ?: return false
        if (b.died != null || b.kind.span <= 1 || !(b.mode == LDBossMode.STANDING || b.mode == LDBossMode.SHIFTING)) return false
        return row in b.rows && col + 0.5 >= LDBoss.HOME
    }

    /** Plant a seed; false when it's unaffordable, recharging, or the tile isn't free lawn. */
    fun plant(kind: LDPlantKind, row: Int, col: Int): Boolean {
        if (won || lost || !canPlant(kind) || row !in params.rows || col !in 0 until COLS ||
            plantAt(row, col) != null || graveAt(row, col) != null || bossCovers(row, col)) return false
        sun -= kind.cost
        recharge[kind.ordinal] = kind.recharge
        val timer = when (kind) {
            LDPlantKind.SUNFLOWER -> 4.5
            LDPlantKind.PEASHOOTER, LDPlantKind.POPPER, LDPlantKind.FROST -> 0.4
            LDPlantKind.LOBBER -> 0.6
            LDPlantKind.WALLNUT, LDPlantKind.FLYTRAP -> 0.0
            LDPlantKind.PEEL -> PEEL_ARM
            LDPlantKind.CHERRY -> 1.1
            LDPlantKind.CHILI -> 0.8
        }
        plants += LDPlant(newID(), kind, row, col, kind.bites, timer, t)
        return true
    }

    /** Pick up a sun; false if it's gone. */
    fun collect(id: Int): Boolean {
        val i = suns.indexOfFirst { it.id == id }
        if (i < 0) return false
        suns.removeAt(i)
        sun += SUN_VALUE
        return true
    }

    // Targets

    private fun targetable(z: LDZombie) = z.died == null && t >= z.born

    private fun bossIn(row: Int): Boolean {
        val b = boss ?: return false
        if (b.died != null || !(b.mode != LDBossMode.ARRIVING || b.x < COLS - 0.3)) return false
        return row in b.rows
    }

    private fun targetAhead(row: Int, col: Int): Boolean {
        val c = col + 0.2; val edge = COLS - 0.15
        if (zombies.any { it.row == row && targetable(it) && it.x > c && it.x < edge }) return true
        if (rollers.any { it.row == row && it.x > c && it.x < edge }) return true
        val b = boss
        if (b != null && bossIn(row) && b.x > c && b.x < edge) return true
        return false
    }

    private fun lobTarget(row: Int, col: Int): Pair<LDTarget, Double>? {
        val c = col + 0.2; val edge = COLS - 0.15
        var best: Pair<LDTarget, Double>? = null
        for (z in zombies) if (z.row == row && targetable(z) && z.x > c && z.x < edge && z.x < (best?.second ?: 99.0)) best = LDTarget.Zombie(z.id) to z.x
        for (r in rollers) if (r.row == row && r.x > c && r.x < edge && r.x < (best?.second ?: 99.0)) best = LDTarget.Roller(r.id) to r.x
        val b = boss
        if (b != null && bossIn(row) && b.x > c && b.x < edge && b.x < (best?.second ?: 99.0)) best = LDTarget.Boss to b.x
        return best
    }

    // Damage

    private fun kill(z: LDZombie, burnt: Boolean = false, eaten: Boolean = false) {
        if (z.died != null) return
        z.died = t; z.burnt = burnt; z.eaten = eaten
    }

    /** Damage that goes round the shield (lobs, peels, splash): headgear first, then the zombie. */
    private fun wound(z: LDZombie, d: Double) {
        z.hit = t
        val soak = min(z.armor, d)
        z.armor -= soak
        z.hp -= d - soak
        if (z.hp <= 0) kill(z)
    }

    private fun hurtBoss(d: Double, interrupt: Boolean = false, stun: Double = 0.0) {
        val b = boss ?: return
        if (b.died != null) return
        b.hp -= d
        b.hit = t
        if (stun > 0) b.stunUntil = max(b.stunUntil, t + stun)
        if (interrupt && b.move != null && b.mode == LDBossMode.STANDING) {
            b.move = null; b.targets = emptyList(); b.clock = params.bossEvery * 0.6
        }
        if (b.hp <= 0) { b.hp = 0.0; b.died = t; b.move = null; b.targets = emptyList() }
    }

    // Step

    fun step(dt: Double) {
        if (won || lost) return
        t += dt
        for (k in recharge.indices) recharge[k] = max(0.0, recharge[k] - dt)

        while (spawned < schedule.size && schedule[spawned].t <= t) {
            val s = schedule[spawned]
            spawned += 1
            addZombie(s.kind, s.row, COLS + 0.4)
        }
        val bk = params.boss
        if (boss == null && bk != null && spawned == schedule.size) {
            val flag = schedule.lastOrNull { it.kind == LDZombieKind.FLAG }?.t
            if (flag != null && (t - flag > 18 || (t - flag > 4 && zombies.count { it.died == null } <= 2))) arrive(bk)
        }

        skyTimer -= dt
        if (skyTimer <= 0) {
            skyTimer = params.skyEvery
            val row = params.rows[rng.int(params.rows.size)]
            suns += LDSun(newID(), 0.6 + rng.unit() * (COLS - 1.2), params.rows[0] - 0.9, row + 0.55, 8.0, t)
        }
        for (s in suns) { if (s.y < s.landY) s.y = min(s.landY, s.y + 1.1 * dt) else s.life -= dt }
        suns.removeAll { it.life <= 0 }

        plantsAct(dt)
        flyPeas(dt)
        flyLobs()
        zombiesAct(dt)
        bossAct(dt)
        rollersAct(dt)

        for (d in drops) if (t >= d.lands) addZombie(d.kind, d.row, d.x)
        drops.removeAll { t >= it.lands }

        for (r in mowers.indices) {
            val m = mowers[r]
            if (m.state != LDMower.RUNNING) continue
            m.x += 5 * dt
            for (z in zombies) if (z.row == r && z.died == null && z.x < m.x + 0.35) kill(z)
            if (m.x > COLS + 1) m.state = LDMower.GONE
        }

        zombies.removeAll { z -> z.died?.let { t - it > 1.6 } ?: false }
        graves.removeAll { it.hp <= 0 }
        rollers.removeAll { it.hp <= 0 || it.x < -0.4 }
        splats.removeAll { t - it.t > 0.35 }
        booms.removeAll { t - it.t > 0.9 }
        blazes.removeAll { t - it.t > 0.9 }
        crashes.removeAll { t - it.t > 0.7 }
        if (lost) return
        val bossDone = params.boss == null || (boss?.died?.let { t - it > 2 } ?: false)
        if (bossDone && spawned == schedule.size && drops.isEmpty() && zombies.all { it.died != null }) won = true
    }

    private fun addZombie(kind: LDZombieKind, row: Int, x: Double) {
        val k = if (kind == LDZombieKind.FLAG) 1.0 else 0.9 + 0.2 * rng.unit()
        zombies += LDZombie(newID(), kind, row, x, kind.hp, kind.armor, kind.shield, kind.pace * k, t)
    }

    // Plants

    private fun plantsAct(dt: Double) {
        val blasts = mutableListOf<LDTile>()
        val fires = mutableListOf<Int>()
        for (p in plants) {
            if (p.frozen > 0) { p.frozen = max(0.0, p.frozen - dt); continue }
            p.timer -= dt
            when (p.kind) {
                LDPlantKind.SUNFLOWER -> if (p.timer <= 0) {
                    p.timer = SUNFLOWER_EVERY
                    suns += LDSun(newID(), p.col + 0.75, p.row + 0.15, p.row + 0.55, 8.0, t)
                }
                LDPlantKind.PEASHOOTER, LDPlantKind.POPPER, LDPlantKind.FROST -> if (p.timer <= 0 && targetAhead(p.row, p.col)) {
                    p.timer = SHOOT_EVERY
                    p.fired = t
                    val x = p.col + 0.8
                    when (p.kind) {
                        LDPlantKind.POPPER -> { peas += LDPea(newID(), p.row, x, LDShot.POPCORN); peas += LDPea(newID(), p.row, x - 0.4, LDShot.POPCORN) }
                        LDPlantKind.FROST -> peas += LDPea(newID(), p.row, x, LDShot.FROST)
                        else -> peas += LDPea(newID(), p.row, x, LDShot.PEA)
                    }
                }
                LDPlantKind.LOBBER -> if (p.timer <= 0) {
                    val tg = lobTarget(p.row, p.col)
                    if (tg != null) {
                        p.timer = LOB_EVERY
                        p.fired = t
                        lobs += LDLob(newID(), p.row, p.col + 0.5, tg.second, t, tg.first)
                    }
                }
                LDPlantKind.FLYTRAP -> {
                    if (p.chewing > 0) { p.chewing = max(0.0, p.chewing - dt) } else {
                        val reach = p.col + 1.35
                        val z = zombies.filter { it.row == p.row && targetable(it) && it.x > p.col + 0.1 && it.x < reach }.minByOrNull { it.x }
                        val b = boss
                        if (z != null) {
                            kill(z, eaten = true)
                            p.chewing = 12.0
                            p.gulp = t
                        } else if (b != null && bossIn(p.row) && b.x > p.col + 0.1 && b.x < reach) {
                            hurtBoss(6.0)
                            p.chewing = 5.0
                            p.gulp = t
                        }
                    }
                }
                LDPlantKind.CHERRY -> if (p.timer <= 0) { blasts += LDTile(p.row, p.col); p.hp = 0.0 }
                LDPlantKind.CHILI -> if (p.timer <= 0) { fires += p.row; p.hp = 0.0 }
                LDPlantKind.WALLNUT, LDPlantKind.PEEL -> {}
            }
        }
        for (b in blasts) {
            booms += LDBoom(b.row, b.col, t)
            val lo = b.col - 0.9; val hi = b.col + 1.9
            for (z in zombies) if (abs(z.row - b.row) <= 1 && z.x > lo && z.x < hi && t >= z.born) kill(z, burnt = true)
            for (g in graves) if (abs(g.row - b.row) <= 1 && abs(g.col - b.col) <= 1) g.hp = 0.0
            for (r in rollers) if (abs(r.row - b.row) <= 1 && r.x > lo - 0.5 && r.x < hi) r.hp = 0.0
            val bs = boss
            if (bs != null && bs.died == null && ((b.row - 1) in bs.rows || b.row in bs.rows || (b.row + 1) in bs.rows) && bs.x < hi) {
                hurtBoss(20.0, interrupt = true, stun = 1.5)
            }
        }
        for (row in fires) {
            blazes += LDBlaze(row, t)
            for (z in zombies) if (z.row == row && t >= z.born) kill(z, burnt = true)
            for (g in graves) if (g.row == row) g.hp = 0.0
            for (r in rollers) if (r.row == row) r.hp = 0.0
            for (p in plants) if (p.row == row) p.frozen = 0.0
            if (bossIn(row)) hurtBoss(20.0, interrupt = true, stun = 1.5)
        }
    }

    // Shots

    private fun flyPeas(dt: Double) {
        val spent = HashSet<Int>()
        for (p in peas) {
            p.x += PEA_SPEED * dt
            var bestX = 99.0
            var hitZ: LDZombie? = null; var hitG: LDGrave? = null; var hitR: LDRoller? = null; var hitBoss = false
            fun clear() { hitZ = null; hitG = null; hitR = null; hitBoss = false }
            for (z in zombies) if (z.row == p.row && targetable(z) && p.x >= z.x + 0.05 && p.x <= z.x + 0.65 && z.x < bestX) { bestX = z.x; clear(); hitZ = z }
            for (g in graves) if (g.row == p.row && g.hp > 0) {
                val gx = g.col + 0.25
                if (p.x >= gx && p.x <= gx + 0.6 && gx < bestX) { bestX = gx; clear(); hitG = g }
            }
            for (r in rollers) if (r.row == p.row && r.hp > 0 && p.x >= r.x - 0.1 && p.x <= r.x + 0.7 && r.x < bestX) { bestX = r.x; clear(); hitR = r }
            val b = boss
            if (b != null && bossIn(p.row) && p.x >= b.x + 0.05 && p.x <= b.x + 0.95 && b.x < bestX) { bestX = b.x; clear(); hitBoss = true }
            if (hitZ == null && hitG == null && hitR == null && !hitBoss) continue
            spent += p.id
            splats += LDSplat(p.row, p.x, t, p.shot)
            val z = hitZ; val g = hitG; val r = hitR
            when {
                z != null -> {
                    z.hit = t
                    if (z.shield > 0) { z.shield -= 1 } else {
                        if (p.shot == LDShot.FROST) z.slowUntil = t + 4
                        if (z.armor > 0) z.armor -= 1 else z.hp -= 1
                        if (z.hp <= 0) kill(z)
                    }
                }
                g != null -> g.hp -= 1
                r != null -> r.hp -= if (r.kind == LDRollerKind.FIREBALL && p.shot == LDShot.FROST) 3.0 else 1.0
                else -> hurtBoss(1.0)
            }
        }
        peas.removeAll { it.id in spent || it.x > COLS + 0.6 }
    }

    private fun flyLobs() {
        for (l in lobs) {
            when (val tg = l.target) {
                is LDTarget.Zombie -> zombies.firstOrNull { it.id == tg.id && it.died == null }?.let { l.x1 = it.x + 0.2 }
                is LDTarget.Roller -> rollers.firstOrNull { it.id == tg.id }?.let { l.x1 = it.x + 0.2 }
                LDTarget.Boss -> boss?.let { if (it.died == null) l.x1 = it.x + 0.3 }
            }
        }
        for (l in lobs) {
            if (t - l.t0 < LOB_TIME) continue
            splats += LDSplat(l.row, l.x1, t, LDShot.MELON)
            when (val tg = l.target) {
                is LDTarget.Zombie -> zombies.firstOrNull { it.id == tg.id && it.died == null }?.let { wound(it, 3.0) }
                is LDTarget.Roller -> rollers.firstOrNull { it.id == tg.id }?.let { it.hp -= 3 }
                LDTarget.Boss -> if (boss != null && boss?.died == null && bossIn(l.row)) hurtBoss(3.0)
            }
            for (z in zombies) {
                if (abs(z.row - l.row) > 1 || !targetable(z) || abs(z.x + 0.2 - l.x1) > 1.0) continue
                if (l.target is LDTarget.Zombie && z.id == (l.target as LDTarget.Zombie).id) continue
                wound(z, 1.0)
            }
        }
        lobs.removeAll { t - it.t0 >= LOB_TIME }
    }

    // Zombies

    private fun zombiesAct(dt: Double) {
        for (z in zombies) {
            if (z.died != null || t < z.born) continue
            if (t < z.stunUntil) { z.eating = false; continue }
            val chill = if (t < z.slowUntil) 0.5 else 1.0
            val col = floor(z.x - 0.05).toInt()
            val p = plants.firstOrNull { it.row == z.row && it.col == col && it.hp > 0 }
            if (p != null && z.x <= col + 0.95) {
                if (p.kind == LDPlantKind.PEEL && p.timer <= 0) {
                    // Armed: it slips, slides back and lies there seeing stars.
                    p.hp = 0.0
                    z.stunUntil = t + 2.5
                    z.x += 0.6
                    z.eating = false
                    wound(z, 4.0)
                    continue
                }
                if (z.kind == LDZombieKind.JUMPER && z.hopped < 0 && !p.kind.isBomb) {
                    z.x = col - 0.3
                    z.hopped = t
                    z.speedK /= LDZombieKind.JUMPER.pace
                    continue
                }
                z.eating = true
                p.hp -= BITE_RATE * chill * dt
                p.bitten = t
            } else {
                z.eating = false
                z.x -= params.speed * z.speedK * chill * dt
            }
            if (z.x < -0.05) reachHouse(z.row)
        }
        plants.removeAll { it.hp <= 0 }
    }

    private fun reachHouse(row: Int) {
        val m = mowers[row]
        when (m.state) {
            LDMower.READY -> { m.state = LDMower.RUNNING; m.x = -0.5 }
            LDMower.RUNNING -> {}
            else -> lost = true
        }
    }

    // Boss

    private fun arrive(kind: LDBossKind) {
        val row = if (kind.span == 1) params.rows[rng.int(params.rows.size)] else min(5 - kind.span, 1 + rng.int(max(1, 4 - kind.span)))
        boss = LDBoss(kind, params.bossHP, params.bossHP, row, row.toDouble(), COLS + 0.9).also { it.arrivedAt = t }
    }

    private fun crush(row: Int, col: Int) {
        val p = plants.firstOrNull { it.row == row && it.col == col && !it.kind.isBomb } ?: return
        if (p.kind == LDPlantKind.WALLNUT && p.hp > 18) { p.hp -= 18; p.bitten = t } else p.hp = 0.0
    }

    private fun settle() {
        val b = boss ?: return
        for (r in b.rows) crush(r, COLS - 1)
        plants.removeAll { it.hp <= 0 }
    }

    private fun bossAct(dt: Double) {
        val b = boss ?: return
        if (b.died != null) return
        if (t < b.stunUntil && b.mode != LDBossMode.ARRIVING) return
        when (b.mode) {
            LDBossMode.ARRIVING -> {
                if (b.kind.span == 1) {
                    b.x -= 0.5 * dt
                    if (b.x <= COLS - 0.2) { b.mode = LDBossMode.WALKING; b.clock = params.bossEvery }
                } else {
                    b.x = max(LDBoss.HOME, b.x - 0.9 * dt)
                    if (b.x <= LDBoss.HOME) { b.mode = LDBossMode.STANDING; b.clock = 2.0; settle() }
                }
            }
            LDBossMode.WALKING -> walk(dt)
            LDBossMode.SHIFTING -> {
                val goal = b.row.toDouble()
                b.y += (if (goal > b.y) 1 else -1) * min(abs(goal - b.y), dt / 1.2)
                if (abs(b.y - goal) < 0.0001) {
                    b.y = goal
                    b.mode = if (b.kind.span == 1) LDBossMode.WALKING else LDBossMode.STANDING
                    if (b.kind.span > 1) settle()
                }
            }
            LDBossMode.CHARGING -> charge(dt)
            LDBossMode.RETREATING -> {
                b.x = min(LDBoss.HOME, b.x + 1.5 * dt)
                if (b.x >= LDBoss.HOME) { b.mode = LDBossMode.STANDING; b.clock = params.bossEvery * 0.7; settle() }
            }
            LDBossMode.STANDING -> {
                val m = b.move
                if (m != null) {
                    b.windup -= dt
                    if (b.windup > 0) return
                    val rowBefore = b.row
                    perform(m)
                    if (b.died != null) return
                    b.move = null
                    b.lastAt = t
                    b.lastTargets = b.targets
                    b.targets = emptyList()
                    b.last = m
                    b.moves += 1
                    b.clock = params.bossEvery
                    if (b.moves % 2 == 0 && b.mode == LDBossMode.STANDING) {
                        val options = (0..(5 - b.kind.span)).filter { it != rowBefore }
                        b.row = options[rng.int(options.size)]
                        b.mode = LDBossMode.SHIFTING
                    }
                } else {
                    b.clock -= dt
                    if (b.clock > 0) return
                    val pool = b.kind.moves.filter { it != b.last || b.kind.moves.size == 1 }
                    val mv = pool[rng.int(pool.size)]
                    val targets = aim(mv)
                    b.move = mv
                    b.windup = mv.windup
                    b.targets = targets
                }
            }
        }
    }

    /** The groundskeeper: walks its lane, smashing every plant in its way, and shifts lanes now and then. */
    private fun walk(dt: Double) {
        val b = boss!!
        if (!b.threw && b.hp < b.maxHP / 2 && b.x >= 3.6) {
            b.threw = true
            drops += LDDrop(newID(), LDZombieKind.IMP, b.row, b.x - 2.6, b.x + 0.4, t, t + 1.1)
        }
        b.clock -= dt
        val col = floor(b.x - 0.05).toInt()
        val p = plants.firstOrNull { it.row == b.row && it.col == col && it.hp > 0 && !it.kind.isBomb }
        if (p != null && b.x <= col + 0.95) {
            if (p.kind == LDPlantKind.PEEL && p.timer <= 0) {
                p.hp = 0.0
                plants.removeAll { it.hp <= 0 }
                b.x += 0.5
                hurtBoss(8.0, stun = 3.0)
                return
            }
            if (b.windup <= 0) b.windup = 0.8
            b.windup -= dt
            if (b.windup <= 0) {
                b.smashed = t
                crashes += LDCrash(b.row, col, t)
                p.hp = 0.0
                plants.removeAll { it.hp <= 0 }
            }
            return
        }
        b.windup = 0.0
        if (b.clock <= 0) {
            b.clock = params.bossEvery
            val options = listOf(b.row - 1, b.row + 1).filter { it in params.rows }
            if (options.isNotEmpty() && rng.unit() < 0.6) {
                b.row = options[rng.int(options.size)]
                b.mode = LDBossMode.SHIFTING
                return
            }
        }
        b.x -= params.speed * 0.55 * dt
        if (b.x < -0.05) {
            val m = mowers[b.row]
            if (m.state == LDMower.READY) {
                m.state = LDMower.RUNNING; m.x = -0.5
                b.x = 2.5
                hurtBoss(b.maxHP * 0.25, stun = 2.0)
            } else lost = true
        }
    }

    /** The locomotive's charge to mid-lawn; a peel derails it, a sound wall-nut stops it. */
    private fun charge(dt: Double) {
        val b = boss!!
        b.x -= 3 * dt
        val col = floor(b.x).toInt()
        for (r in b.rows) {
            if (col >= 0) {
                val p = plants.firstOrNull { it.row == r && it.col == col && !it.kind.isBomb }
                if (p != null) {
                    if (p.kind == LDPlantKind.PEEL && p.timer <= 0) {
                        p.hp = 0.0
                        plants.removeAll { it.hp <= 0 }
                        b.mode = LDBossMode.RETREATING
                        hurtBoss(8.0, stun = 3.0)
                        return
                    }
                    crashes += LDCrash(r, col, t)
                    if (p.kind == LDPlantKind.WALLNUT && p.hp > 18) {
                        crush(r, col)
                        b.x = col + 1.0
                        b.mode = LDBossMode.RETREATING
                        b.stunUntil = t + 1
                        return
                    }
                    crush(r, col)
                }
            }
            for (z in zombies) if (z.row == r && z.died == null && z.x > b.x - 0.2 && z.x < b.x + 1.2) kill(z)
        }
        plants.removeAll { it.hp <= 0 }
        if (b.x <= CHARGE_STOP) b.mode = LDBossMode.RETREATING
    }

    private fun aim(m: LDBossMove): List<LDTile> {
        val b = boss!!
        val n = params.bossPower
        return when (m) {
            LDBossMove.SUMMON, LDBossMove.CHARGE -> emptyList()
            LDBossMove.LASER -> b.rows.map { LDTile(it, -1) }
            LDBossMove.AMBUSH -> (0 until n).map {
                val r = params.rows[rng.int(params.rows.size)]
                LDTile(r, 3 + rng.int(2))
            }
            LDBossMove.GRAVES -> {
                val free = mutableListOf<LDTile>()
                for (r in params.rows) for (c in 1..5) if (plantAt(r, c) == null && graveAt(r, c) == null && !bossCovers(r, c)) free += LDTile(r, c)
                val picks = mutableListOf<LDTile>()
                repeat(n) { if (free.isNotEmpty()) picks += free.removeAt(rng.int(free.size)) }
                picks
            }
            LDBossMove.BOMBARD -> {
                val pool = mutableListOf<LDTile>()
                for (p in plants) {
                    if (p.kind.isBomb) continue
                    val w = if (p.kind.shoots || p.kind == LDPlantKind.LOBBER) 3 else if (p.kind == LDPlantKind.SUNFLOWER) 2 else 1
                    repeat(w) { pool += LDTile(p.row, p.col) }
                }
                val picks = mutableListOf<LDTile>()
                repeat(n + 1) {
                    if (pool.isNotEmpty()) {
                        val pick = pool[rng.int(pool.size)]
                        picks += pick
                        pool.removeAll { it == pick }
                    }
                }
                picks
            }
            LDBossMove.FREEZE, LDBossMove.ROLL -> {
                val row = b.rows.toList().maxByOrNull { r -> plants.count { it.row == r } } ?: b.row
                listOf(LDTile(row, -1))
            }
            LDBossMove.STOMP -> b.rows.flatMap { r -> listOf(LDTile(r, 3), LDTile(r, 4)) }
        }
    }

    private fun perform(m: LDBossMove) {
        val b = boss ?: return
        when (m) {
            LDBossMove.SUMMON -> {
                val pool = params.mix.map { it.first }
                repeat(params.bossPower) {
                    val plain = pool.isEmpty() || rng.unit() < 0.4
                    val kind = if (plain) LDZombieKind.NORMAL else pool[rng.int(pool.size)]
                    addZombie(kind, params.rows[rng.int(params.rows.size)], COLS + 0.4)
                }
            }
            LDBossMove.AMBUSH -> for (tile in b.targets) addZombie(ambusher(tile), tile.row, tile.col + 0.6)
            LDBossMove.GRAVES -> for (tile in b.targets) {
                if (plantAt(tile.row, tile.col) == null && graveAt(tile.row, tile.col) == null) graves += LDGrave(newID(), tile.row, tile.col, 8.0, t)
            }
            LDBossMove.BOMBARD, LDBossMove.STOMP -> {
                for (tile in b.targets) { crashes += LDCrash(tile.row, tile.col, t); crush(tile.row, tile.col) }
                plants.removeAll { it.hp <= 0 }
            }
            LDBossMove.CHARGE -> b.mode = LDBossMode.CHARGING
            LDBossMove.FREEZE -> b.targets.firstOrNull()?.row?.let { row ->
                for (p in plants) if (p.row == row && !p.kind.isBomb) p.frozen = 7.0
            }
            LDBossMove.ROLL -> b.targets.firstOrNull()?.row?.let { row ->
                val kind = if (b.kind == LDBossKind.MAMMOTH) LDRollerKind.SNOWBALL else if (b.moves % 2 == 0) LDRollerKind.FIREBALL else LDRollerKind.ICEBALL
                rollers += LDRoller(newID(), kind, row, b.x - 0.3, if (kind == LDRollerKind.SNOWBALL) 14.0 else 10.0, t)
            }
            LDBossMove.LASER -> {
                for (r in b.rows) {
                    val p = plants.filter { it.row == r && !it.kind.isBomb }.maxByOrNull { it.col }
                    if (p != null) { crashes += LDCrash(r, p.col, t); crush(r, p.col) }
                }
                plants.removeAll { it.hp <= 0 }
            }
        }
    }

    /** Snowballs, fireballs and iceballs roll down a lane flattening plants; a sound wall-nut shatters them. */
    private fun rollersAct(dt: Double) {
        for (r in rollers) {
            if (r.hp <= 0) continue
            r.x -= ROLL_SPEED * dt
            val col = floor(r.x - 0.05).toInt()
            if (col >= 0) {
                val p = plants.firstOrNull { it.row == r.row && it.col == col && !it.kind.isBomb }
                if (p != null && r.x <= col + 0.9) {
                    crashes += LDCrash(r.row, col, t)
                    if (p.kind == LDPlantKind.WALLNUT && p.hp > 18) {
                        crush(r.row, col)
                        r.hp = 0.0
                        continue
                    }
                    p.hp = 0.0
                }
            }
            if (r.x < -0.2) {
                if (mowers[r.row].state == LDMower.READY) mowers[r.row].state = LDMower.GONE
                r.hp = 0.0
            }
        }
        plants.removeAll { it.hp <= 0 }
    }
}
