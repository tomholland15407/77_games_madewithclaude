package com.gogs.bananagame

import com.gogs.bananagame.games.catburglar.CBGen
import com.gogs.bananagame.games.catburglar.CBParams
import com.gogs.bananagame.games.catburglar.CatWorld
import com.gogs.bananagame.games.bananagetaway.RHGen
import com.gogs.bananagame.games.canyonplink.PlinkWorld
import com.gogs.bananagame.games.canyonplink.RSGen
import com.gogs.bananagame.games.canyonplink.RSParams
import com.gogs.bananagame.games.cheerupmonkey.CMLoot
import com.gogs.bananagame.games.rocknrocket.RocketRace
import com.gogs.bananagame.games.sniper.GROUND_V
import com.gogs.bananagame.games.sniper.SniperWorld
import com.gogs.bananagame.games.sniper.TARGET_H
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

    @Test
    fun canyonPlinkDemoClearsTheRoomInTwoShots() {
        val w = PlinkWorld(1)
        w.commit(RSGen.demoBoard())
        for (a in RSGen.demoAims.drop(1)) {
            w.aimAngle = a
            w.fire()
            var frames = 0
            while (w.phase == PlinkWorld.Phase.FIRING && frames < 60 * 20) { w.stepBullet(1.0 / 60); frames++ }
        }
        assertEquals(0, w.targets.size)
        assertEquals(PlinkWorld.Phase.DONE, w.phase)
        assertEquals(1, w.ammo)
    }

    @Test
    fun canyonPlinkBoardsNeedNearlyEveryBullet() {
        for (level in listOf(1, 4, 7)) {
            val p = RSParams(level)
            val b = RSGen.generate(p)
            assertEquals(p.targetCount, b.targets.toSet().size)
            for (t in b.targets) { assertFalse(b.walls[t.r][t.c]); assertTrue(t.r in 1 until 11) }
            val aims = (0 until 360).map { i -> RSGen.shotCells(i / 360.0 * 2 * Math.PI, b.walls, p.maxBounces) }
            assertTrue("level $level must be clearable within ${p.bulletBudget}", RSGen.greedyShots(b.targets, aims) <= p.bulletBudget)
        }
    }

    @Test
    fun sniperDemoDropsBothSoldiers() {
        val w = SniperWorld(1)
        w.setup(); w.demoSetup()
        w.areaW = 377.0; w.areaH = 600.0
        fun wait(dur: Double) = repeat((dur / 0.016).toInt()) { w.tickAmbient(0.016) }
        fun panTo(gx: Double, gy: Double) {
            val sx = w.aimX; val sy = w.aimY; val steps = (0.85 / 0.016).toInt()
            for (k in 1..steps) { val f = 0.5 - 0.5 * Math.cos(Math.PI * k / steps); w.aimX = sx + (gx - sx) * f; w.aimY = sy + (gy - sy) * f; w.tickAmbient(0.016) }
        }
        val gy = GROUND_V - TARGET_H / 2
        wait(0.6); panTo(w.targets.first().x, gy); wait(0.22); w.fire()
        assertEquals(1, w.targets.size)
        wait(0.88); panTo(w.targets.first().x, gy); wait(0.22); w.fire()
        assertEquals(0, w.targets.size)
        assertFalse("the last shot is the real win()", w.playing)
    }

    @Test
    fun rockNRocketDemoTakesTheFlagFirst() {
        for (w in listOf(300.0, 330.0, 360.0, 390.0)) for (h in listOf(300.0, 330.0, 360.0)) {
            val race = RocketRace(1)
            race.areaW = w; race.areaH = h
            race.demoSetup()
            var frame = 0; var fired = false
            val lastSteer = intArrayOf(-99)
            while (race.playing && frame < 900) {
                frame++
                if (race.demoDrive(frame, lastSteer, fired)) fired = true
                race.step(1.0 / 60)
            }
            assertTrue("fires at ${w}x$h", fired)
            assertFalse("finishes at ${w}x$h", race.playing)
            assertEquals("wins at ${w}x$h", RocketRace.LAPS, race.player!!.lap)
        }
    }

    @Test
    fun bananaGetawayBoardsAreSolvableJams() {
        assertEquals(2, RHGen.shortestSolution(RHGen.demoBoard()))
        for (level in listOf(1, 2, 3)) {
            val p = RHGen.Params(level)
            val b = RHGen.generate(p)
            assertEquals(RHGen.EXIT_ROW, b[0].r)
            assertTrue(b[0].horiz)
            assertFalse(RHGen.goal(b))
            val cells = mutableSetOf<Int>()
            for (car in b) for (k in 0 until car.len) {
                val r = car.r + (if (car.horiz) 0 else k); val c = car.c + (if (car.horiz) k else 0)
                assertTrue(r in 0 until RHGen.SIZE && c in 0 until RHGen.SIZE)
                assertTrue("cars overlap", cells.add(r * RHGen.SIZE + c))
            }
            val moves = RHGen.shortestSolution(b)
            assertTrue("level $level is solvable", moves != null && moves > 0)
        }
    }
}
