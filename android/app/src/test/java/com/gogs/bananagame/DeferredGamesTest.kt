package com.gogs.bananagame

import com.gogs.bananagame.games.catburglar.CBGen
import com.gogs.bananagame.games.catburglar.CBParams
import com.gogs.bananagame.games.catburglar.CatWorld
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
}
