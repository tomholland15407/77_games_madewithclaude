package com.gogs.bananagame

import com.gogs.bananagame.core.Bits128
import com.gogs.bananagame.games.breach.BreachGen
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
}
