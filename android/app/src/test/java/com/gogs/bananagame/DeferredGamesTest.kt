package com.gogs.bananagame

import com.gogs.bananagame.games.catburglar.CBGen
import com.gogs.bananagame.games.catburglar.CBParams
import com.gogs.bananagame.games.catburglar.CatWorld
import com.gogs.bananagame.games.cheerupmonkey.CMLoot
import com.gogs.bananagame.games.cheerupmonkey.CMParams
import com.gogs.bananagame.games.cheerupmonkey.CMRandom
import com.gogs.bananagame.games.cheerupmonkey.CMStage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Headless checks of the final batch's rules, generators and scripted manual demos. */
class DeferredGamesTest {

    @Test
    fun catBurglarDemoLootsEverythingUnseenAndEscapes() {
        val w = CatWorld(1)
        w.commit(CBGen.demoBoard())
        var leg = 0; var frames = 0
        while (w.playing && frames < 60 * 60) { leg = w.demoDrive(leg); w.step(1.0 / 60); frames++ }
        assertTrue("the demo should end in the real win()", w.won)
        assertFalse("the route must stay out of the guard's sight", w.alarmRaised)
        assertEquals(0, w.coins.size)
    }

    @Test
    fun catBurglarBoardsAreWellFormed() {
        for (level in 1..7) {
            val p = CBParams(level)
            val b = CBGen.generate(level)
            assertEquals(p.lootCount, b.coins.size)
            assertEquals(p.guardCount, b.paths.size)
            assertFalse(b.walls[b.start.r][b.start.c])
            assertFalse(b.walls[b.exit.r][b.exit.c])
            assertTrue(b.coins.none { it == b.start || it == b.exit || it == b.door })
            assertTrue(b.start in b.shadows)
            assertFalse(b.exit in b.shadows)
        }
    }

    @Test
    fun cheerUpMonkeyRandomIsSplitMix64() {
        // The published SplitMix64 test vector: seed 0 → 0xE220A8397B1DCDAF first.
        assertEquals(0xE220A8397B1DCDAFuL, CMRandom(0uL).next())
    }

    @Test
    fun cheerUpMonkeyDealsAreWellFormedAndSolvable() {
        for (level in 1..7) {
            val p = CMParams.level(level)
            val theme = listOf(0, 1, 2, 3, 0, 1, 2)[level - 1]
            for (n in 1..500) {
                val st = CMStage.make(p, theme, n.toULong() * 0x9E3779B97F4A7C15uL)
                assertEquals(p.wheels, st.wheels.size)
                assertEquals(p.containers, st.props.count { it.kind.opens })
                assertFalse("a fresh lock is never already open", st.unlocked)
                // Each symbol wheel's sign is on exactly one mini monkey in its colour; each count wheel's
                // colour has exactly as many gems as its answer.
                for (w in st.wheels) {
                    val minis = st.minis.filter { it.hue == w.hue }
                    if (w.count) {
                        assertTrue(minis.isEmpty())
                        assertEquals(w.target + 1, st.gems.count { it.hue == w.hue })
                        assertTrue(w.target < 5)
                    } else {
                        assertEquals(1, minis.size)
                        assertEquals(w.target, minis[0].glyph)
                    }
                }
                val wheelHues = st.wheels.map { it.hue }.toSet()
                assertTrue(st.gems.count { it.hue !in wheelHues } <= p.decoyGems)
                // Hidden minis sit in containers that hold them; the others peek out from cover.
                for ((i, m) in st.minis.withIndex()) {
                    if (m.inside) assertEquals(CMLoot.Mini(i), st.props[m.host].loot)
                    else assertFalse(st.props[m.host].kind.opens)
                }
                assertEquals(minOf(p.peeking, st.minis.size), st.minis.count { !it.inside })
                // Gems shut in a container match what the container holds.
                for ((i, prop) in st.props.withIndex()) {
                    val inside = st.gems.filter { it.host == i }
                    val loot = prop.loot
                    if (loot is CMLoot.Gems) { assertEquals(loot.n, inside.size); assertTrue(inside.all { it.hue == loot.hue }) }
                    else assertTrue(inside.isEmpty())
                }
                assertTrue(st.gems.all { it.x in 0.0..1.0 && it.y in 0.0..1.0 })
                // Solve it: search every container, collect every peeking mini monkey, set the wheels.
                for (i in st.props.indices) st.open(i)
                for (m in st.minis.indices) st.collect(m)
                assertEquals(st.minis.size, st.found)
                for ((i, w) in st.wheels.withIndex()) while (w.shown != w.target) st.turn(i)
                assertTrue(st.unlocked)
                st.giveBanana()
                assertTrue(st.bananaGiven)
            }
        }
    }

    @Test
    fun cheerUpMonkeyDemoScriptOpensTheChest() {
        val st = CMStage.demo()
        st.giveBanana()
        assertFalse("the banana stays shut in the chest until the lock opens", st.bananaGiven)
        // The clip: red mini monkey, red wheel one turn; blue mini monkey, blue wheel two turns.
        st.collect(0); st.turn(0)
        assertFalse(st.unlocked)
        st.collect(1); st.turn(1); st.turn(1)
        assertTrue(st.unlocked)
        assertEquals(2, st.found)
        st.giveBanana()
        assertTrue(st.bananaGiven)
    }
}
