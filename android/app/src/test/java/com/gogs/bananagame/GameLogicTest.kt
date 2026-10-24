package com.gogs.bananagame

import com.gogs.bananagame.core.Bits128
import com.gogs.bananagame.games.breach.BreachGen
import com.gogs.bananagame.games.bridges.BridgesGame
import com.gogs.bananagame.games.bridges.HashiGen
import com.gogs.bananagame.games.cratepush.CrateGen
import com.gogs.bananagame.games.cratepush.CratePushGame
import com.gogs.bananagame.games.mirrormaze.MMGen
import com.gogs.bananagame.games.mirrormaze.MMSource
import com.gogs.bananagame.games.mirrormaze.MirrorMazeGame
import com.gogs.bananagame.games.slidebots.RRGen
import com.gogs.bananagame.games.slidebots.SlideBotsGame
import com.gogs.bananagame.games.tentstrees.TentsGen
import com.gogs.bananagame.games.tentstrees.TentsTreesGame
import com.gogs.bananagame.games.critterduel.CDBattle
import com.gogs.bananagame.games.critterduel.CDEvent
import com.gogs.bananagame.games.critterduel.CDType
import com.gogs.bananagame.games.critterduel.CritterDuelGame
import com.gogs.bananagame.games.jungleloop.SLGen
import com.gogs.bananagame.games.lawndefense.LDParams
import com.gogs.bananagame.games.lawndefense.LDPlantKind
import com.gogs.bananagame.games.lawndefense.LDWorld
import com.gogs.bananagame.games.lawndefense.LDZombieKind
import com.gogs.bananagame.games.pearlchain.MasyuGen
import com.gogs.bananagame.games.pegsolitaire.PCell
import com.gogs.bananagame.games.pegsolitaire.PegSolitaireGame
import com.gogs.bananagame.games.slide2048.Slide2048Game
import com.gogs.bananagame.games.spiralgalaxies.SGGen
import com.gogs.bananagame.games.statuemaze.StatueMazeGame
import com.gogs.bananagame.games.statuemaze.StatueSolver
import com.gogs.bananagame.ui.SemanticVersion
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

/** Pure game-logic checks: generators produce solvable boards, rule helpers behave like iOS. */
class GameLogicTest {

    @Test fun semanticVersionCompare() {
        assertTrue(SemanticVersion.isNewer("1.10", "1.9"))
        assertFalse(SemanticVersion.isNewer("1.0", "1.0.0"))
        assertTrue(SemanticVersion.isNewer("2.1b3", "2.0"))
    }

    @Test fun bits128Shifts() {
        val b = Bits128.bit(63)
        assertTrue((b shl 1).has(64))
        assertTrue(((b shl 1) shr 1).has(63))
        assertEquals(90, Bits128.ones(90).popCount())
        assertEquals(70, Bits128.bit(70).trailingZeros())
    }

    @Test fun slideCollapseMergesOncePerPair() {
        assertEquals(listOf(4, 4, 0, 0), Slide2048Game.collapse(listOf(2, 2, 2, 2)))
        assertEquals(listOf(4, 2, 0, 0), Slide2048Game.collapse(listOf(2, 2, 2, 0)))
        assertEquals(listOf(8, 0, 0), Slide2048Game.collapse(listOf(0, 4, 4)))
        val moved = Slide2048Game.apply(listOf(listOf(2, 0), listOf(2, 0)), Slide2048Game.Dir.UP)
        assertEquals(listOf(listOf(4, 0), listOf(0, 0)), moved)
    }

    @Test fun pegBoardsReduceToOnePeg() {
        // Every generated board must be reducible to a single peg (it is built by un-jumping).
        repeat(5) {
            val p = PegSolitaireGame.makePuzzle(PegSolitaireGame.params(2))
            assertTrue(solvable(p.pegs, p.w, p.h, HashSet()))
        }
    }

    private fun solvable(pegs: Set<PCell>, w: Int, h: Int, seen: HashSet<Set<PCell>>): Boolean {
        if (pegs.size == 1) return true
        if (!seen.add(pegs)) return false
        for (p in pegs) for ((dr, dc) in listOf(2 to 0, -2 to 0, 0 to 2, 0 to -2)) {
            val to = PCell(p.r + dr, p.c + dc)
            if (to.r !in 0 until h || to.c !in 0 until w) continue
            val mid = PegSolitaireGame.jumpMid(pegs, p, to) ?: continue
            if (solvable(pegs - p - mid + to, w, h, seen)) return true
        }
        return false
    }

    @Test fun masyuBoardsHaveALegalLoop() {
        repeat(10) {
            val links = MasyuGen.growLoop(6)
            val adj = MasyuGen.adjacency(links)
            val (w, b) = MasyuGen.pickPearls(adj, 6)
            assertTrue(MasyuGen.satisfiesAll(links, w, b))
        }
        val rect = MasyuGen.rectangleLoop(5)
        assertTrue(MasyuGen.satisfiesAll(rect, emptyList(), emptyList()))
    }

    @Test fun spiralTilingsAreSymmetric() {
        repeat(10) {
            val (region, dots) = SGGen.tiling(6, 3, Random)
            assertTrue(SGGen.isSolved(region, dots, 6))
        }
    }

    @Test fun breachBoardsFitTheChargeBudget() {
        for (level in 1..7) {
            val b = BreachGen.generate(level)
            val cost = BreachGen.minBreaches(b.player, b.target, b.grid)
            assertNotNull(cost)
            assertTrue(cost!! <= BreachGen.breachBudget(level))
        }
    }

    @Test fun statueRoomsAreSafelySolvable() {
        for (level in listOf(1, 3)) {
            val room = StatueSolver.makePuzzle(StatueMazeGame.params(level))
            assertNotNull(StatueSolver.pushRuns(room))
        }
    }

    @Test
    fun critterDuelTypesAndDemoSeed() {
        assertEquals(2.0, CDType.GRASS.against(CDType.WATER), 0.0)
        assertEquals(0.5, CDType.FIRE.against(CDType.WATER), 0.0)
        assertEquals(1.0, CDType.NORMAL.against(CDType.FIRE), 0.0)
        // The manual demo: two Leaf Cuts (move 0) knock out the level-1 rival on the fixed seed.
        val b = CDBattle.level(1, CritterDuelGame.DEMO_SEED)
        var turns = 0
        while (!b.won && !b.lost && turns < 10) { b.turn(0); turns++ }
        assertTrue(b.won)
        assertEquals(2, turns)
        // Every level builds the right number of rivals; L7 always ends on the boss.
        for (level in 1..7) {
            val bl = CDBattle.level(level, 12345uL + level.toULong())
            assertEquals(intArrayOf(1, 1, 2, 2, 2, 3, 3)[level - 1], bl.foes.size)
        }
        assertEquals("Pepperoar", CDBattle.level(7, 99uL).foes.last().name)
    }

    @Test
    fun lawnDefenseHordeAndUndefendedLawnFalls() {
        for (level in 1..7) {
            val p = LDParams.level(level)
            val w = LDWorld(p, 42uL + level.toULong())
            assertEquals(p.count, w.schedule.size)
            val rush = minOf(p.finalWave, p.count)
            assertEquals(LDZombieKind.FLAG, w.schedule[p.count - rush].kind)
            assertTrue(w.schedule.zipWithNext().all { (a, b) -> a.t <= b.t })
        }
        // Nobody planting: the mowers go, then a zombie reaches the house.
        val w = LDWorld(LDParams.level(1), 9uL)
        var steps = 0
        while (!w.lost && !w.won && steps < 60 * 400) { w.step(1.0 / 60); steps++ }
        assertTrue(w.lost)
        // Planting rules: cost, recharge and one plant per tile.
        val v = LDWorld(LDParams.level(1), 3uL)
        assertTrue(v.plant(LDPlantKind.SUNFLOWER, 2, 0))
        assertFalse(v.plant(LDPlantKind.SUNFLOWER, 2, 1))   // recharging
        assertFalse(v.plant(LDPlantKind.PEASHOOTER, 2, 0))  // tile taken
        assertEquals(125 - 50, v.sun)
    }

    @Test
    fun jungleLoopPuzzlesHaveEnoughClues() {
        for (level in 1..7) {
            val n = intArrayOf(3, 4, 4, 5, 5, 6, 6)[level - 1]
            val pz = SLGen.makePuzzle(n, doubleArrayOf(1.0, 0.85, 0.70, 0.60, 0.50, 0.45, 0.38)[level - 1])
            assertEquals(n, pz.n)
            assertTrue(pz.clues.sumOf { r -> r.count { (it ?: 0) > 0 } } >= 3)
        }
        // The demo board's loop is accepted by the win check.
        val h = Array(4) { IntArray(3) }; val v = Array(3) { IntArray(4) }
        for ((r, c) in listOf(0 to 0, 1 to 1, 2 to 2, 3 to 2, 3 to 1, 2 to 0)) h[r][c] = 1
        for ((r, c) in listOf(0 to 1, 1 to 2, 2 to 3, 2 to 1, 1 to 0, 0 to 0)) v[r][c] = 1
        val clues = listOf(listOf<Int?>(3, 2, 0), listOf<Int?>(2, 2, 2), listOf<Int?>(2, 2, 3))
        assertTrue(SLGen.isSolved(3, clues, h, v))
        h[0][0] = 0
        assertFalse(SLGen.isSolved(3, clues, h, v))
    }

    @Test
    fun hashiAndTentsBoardsAreWellFormed() {
        for (level in 1..7) {
            val target = BridgesGame.targetIslands(level)
            val p = HashiGen.make(BridgesGame.gridSize(level), target)
            assertTrue(p.islands.size >= 3)
            assertTrue(p.islands.all { it.need in 1..8 })
            assertEquals(0, p.islands.sumOf { it.need } % 2)   // every bridge has two ends
            val t = TentsGen.generate(TentsTreesGame.n(level), TentsTreesGame.tentTarget(level))
            assertEquals(t.rowCounts.sum(), t.trees.size)
            assertEquals(t.colCounts.sum(), t.trees.size)
        }
    }

    @Test
    fun crateAndSlideBotBoardsAreSolvable() {
        assertEquals(4, CrateGen.solvePushes(CrateGen.demoPuzzle))
        for (level in 1..4) assertNotNull(CrateGen.solvePushes(CrateGen.makePuzzle(CratePushGame.params(level))))
        // Slide Bots demo: optimum 3, and the banana robot alone can never reach the ring.
        val w = HashSet<Int>()
        for ((r, c, d) in listOf(Triple(2, 0, 2), Triple(3, 2, 2), Triple(3, 4, 2), Triple(3, 5, 1), Triple(5, 2, 1))) RRGen.addWall(w, r, c, d, 6)
        assertEquals(3, RRGen.optimalMoves(listOf(2, 18), 22, w, 6, 100_000))
        assertEquals(null, RRGen.optimalMoves(listOf(2), 22, w, 6, 100_000))
        val b = SlideBotsGame.gen(2)
        val opt = RRGen.optimalMoves(b.robots, b.targetCell, b.walls, b.n, 120_000)
        assertNotNull(opt); assertTrue(opt!! in 1..6)
    }

    @Test
    fun mirrorMazeDemoOpensAfterTheTaps() {
        val cols = 11; val rows = 15
        val walls = BooleanArray(rows * cols)
        for (r in 0 until rows) { walls[r * cols] = true; walls[r * cols + cols - 1] = true }
        for (c in 0 until cols) { walls[c] = true; walls[(rows - 1) * cols + c] = true }
        val srcs = listOf(MMSource(9 * cols + 10, -1, 0), MMSource(11 * cols + 10, -1, 0), MMSource(7, 0, 1))
        val orient = hashMapOf(9 * cols + 7 to 1, 2 * cols + 6 to 1, 11 * cols + 2 to 2)
        val start = cols + 1; val exit = (rows - 2) * cols + cols - 2
        val before = MMGen.trace(orient, walls, srcs, 0.07, 60.0)
        assertFalse(before[start])
        assertFalse(MMGen.pathExists(start, exit, before, walls))
        orient[9 * cols + 7] = 2; orient[11 * cols + 2] = 4
        val after = MMGen.trace(orient, walls, srcs, 0.07, 60.0)
        assertTrue(MMGen.pathExists(start, exit, after, walls))
        // Generated boards start the player safe, next to a solvable room.
        val g = MirrorMazeGame.gen(3)
        assertFalse(MMGen.trace(g.orient, g.walls, g.sources, 0.07, 60.0)[g.start])
    }
}
