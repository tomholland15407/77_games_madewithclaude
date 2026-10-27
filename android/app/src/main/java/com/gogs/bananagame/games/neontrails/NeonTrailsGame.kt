package com.gogs.bananagame.games.neontrails

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.TurnLeft
import androidx.compose.material.icons.filled.TurnRight
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/**
 * Reflex — Neon Trails (iOS LightCyclesGame.swift, id "light-cycles"): a light-cycle duel. Your cycle
 * drives itself, laying a wall of light; LEFT / RIGHT turn 90°. Box every rival into a wall without
 * hitting one yourself before the clock runs out. Drawn as TRON's grid.
 */
object NeonTrailsGame {
    val definition = GameDefinition(
        id = "light-cycles",
        title = "Neon Trails",
        genre = Genre.REFLEX,
        manual = GameManual(
            bullets = listOf(
                "Your cycle drives forward on its own, leaving a wall of light.",
                "Tap LEFT or RIGHT to turn 90°.",
                "Trap every enemy cycle so it smashes into a wall, and never hit a wall yourself.",
                "Crash, or let the clock run out, and it's back to level 1.",
            ),
            bulletsVI = listOf(
                "Xe của bạn tự chạy về phía trước, để lại một bức tường ánh sáng.",
                "Chạm TRÁI hoặc PHẢI để rẽ 90°.",
                "Dồn mọi xe địch đâm vào tường, và đừng bao giờ tự đâm vào tường.",
                "Đâm xe, hoặc hết giờ, sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> NeonTrailsView(level, onWin, onFail) }
    )
}

private const val COLS = 17
private const val ROWS = 23

private data class Cell(val r: Int, val c: Int)
private class Cycle(var pos: Cell, var dir: Cell, val color: Color, val isPlayer: Boolean) {
    var alive = true
    var pendingTurn = 0
    val history = mutableListOf(pos)
}
private class Derez(val cell: Cell, val color: Color, val at: Double)

private fun rotated(d: Cell, turn: Int) = when (turn) { -1 -> Cell(-d.c, d.r); 1 -> Cell(d.c, -d.r); else -> d }

private class TrailWorld(val level: Int) {
    private val li = min(level, 7) - 1
    val tick = listOf(0.17, 0.15, 0.13, 0.11, 0.10, 0.085, 0.07)[li]
    val aiCount = listOf(1, 1, 2, 2, 2, 3, 3)[li]
    val aggression = listOf(0.15, 0.25, 0.35, 0.45, 0.55, 0.65, 0.75)[li]
    val lookahead = listOf(6, 6, 5, 5, 4, 4, 3)[li]
    val timeLimit = listOf(30.0, 28.0, 26.0, 24.0, 22.0, 20.0, 18.0)[li]

    var playing = true
    val occupied = HashSet<Cell>()
    var cycles = listOf<Cycle>()
    val derez = mutableListOf<Derez>()
    var timeLeft = timeLimit
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    fun setup() {
        // The grid edge itself is the wall; no border cells are seeded.
        occupied.clear(); derez.clear()
        val palette = listOf(rgb(0.95, 0.28, 0.30), rgb(0.3, 0.6, 1.0), rgb(0.5, 0.9, 0.4))
        val cs = mutableListOf(Cycle(Cell(ROWS - 4, COLS / 2), Cell(-1, 0), BananaTheme.banana, true))
        for (k in 0 until aiCount) {
            val c = min(COLS - 3, max(3, COLS / 2 + (k - aiCount / 2) * 4))
            cs.add(Cycle(Cell(3, c), Cell(1, 0), palette[k % palette.size], false))
        }
        cycles = cs
        for (cy in cs) occupied.add(cy.pos)
        timeLeft = timeLimit; playing = true
    }

    /** The scripted demo: the player lays a wall up column 8; the rival drives right into it. */
    fun demoSetup(playerStart: Cell, rivalStart: Cell) {
        occupied.clear(); derez.clear()
        occupied.add(playerStart); occupied.add(rivalStart)
        cycles = listOf(Cycle(playerStart, Cell(-1, 0), BananaTheme.banana, true), Cycle(rivalStart, Cell(0, 1), rgb(0.95, 0.28, 0.30), false))
        timeLeft = timeLimit; playing = true
    }

    fun kill(cy: Cycle) { if (!cy.alive) return; cy.alive = false; derez.add(Derez(cy.pos, cy.color, nowSec())) }

    fun turn(d: Int) {
        if (!playing) return
        cycles.firstOrNull { it.isPlayer && it.alive }?.let { it.pendingTurn = d; SoundManager.tap(); Haptics.tap() }
    }

    private fun free(c: Cell) = c.r in 0 until ROWS && c.c in 0 until COLS && c !in occupied
    private fun freeRun(from: Cell, dir: Cell, maxSteps: Int): Int {
        var n = 0; var cur = from
        while (n < maxSteps) { cur = Cell(cur.r + dir.r, cur.c + dir.c); if (!free(cur)) break; n++ }
        return n
    }

    private fun aiDecide(cy: Cycle): Int {
        val scored = listOf(0, -1, 1).map { t -> val d = rotated(cy.dir, t); Triple(t, freeRun(cy.pos, d, lookahead), d) }
        val safe = scored.filter { it.second >= 1 }
        if (safe.isEmpty()) return 0                           // doomed — go straight
        // Aggression: sometimes steer toward the player, but only among safe moves.
        val player = cycles.firstOrNull { it.isPlayer && it.alive }
        if (Random.nextDouble() < aggression && player != null) {
            return safe.minBy { val n = Cell(cy.pos.r + it.third.r, cy.pos.c + it.third.c); abs(n.r - player.pos.r) + abs(n.c - player.pos.c) }.first
        }
        // Otherwise maximize open space, preferring straight on ties.
        val top = safe.maxOf { it.second }
        val tied = safe.filter { it.second == top }
        return (tied.firstOrNull { it.first == 0 } ?: tied.pick()).first
    }

    fun stepAll() {
        for (cy in cycles) if (!cy.isPlayer && cy.alive) cy.pendingTurn = aiDecide(cy)
        // Move every live cycle (player first for deterministic priority).
        for (cy in cycles.sortedBy { if (it.isPlayer) 0 else 1 }) {
            if (!cy.alive) continue
            cy.dir = rotated(cy.dir, cy.pendingTurn); cy.pendingTurn = 0
            val next = Cell(cy.pos.r + cy.dir.r, cy.pos.c + cy.dir.c)
            if (next in occupied || next.r !in 0 until ROWS || next.c !in 0 until COLS) {
                kill(cy)
                if (cy.isPlayer) { fail(); return }
                SoundManager.error(); Haptics.warning()
                continue
            }
            cy.pos = next; occupied.add(next); cy.history.add(next)
        }
        if (cycles.filter { !it.isPlayer }.all { !it.alive }) win()
    }

    fun win() { if (!playing) return; playing = false; Haptics.success(); SoundManager.tap(); onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }
}

@Composable
private fun NeonTrailsView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { TrailWorld(level).also { it.setup() } }
    world.onWin = onWin; world.onFail = onFail
    val frame by rememberFrameLoop()

    LaunchedEffect(Unit) {
        if (isDemo) {
            val wallCol = 8; val crashRow = 16
            val playerCells = (0..16).map { Cell(ROWS - 4 - it, wallCol) }   // (19,8) → (3,8)
            val rivalStart = Cell(crashRow, 0); val rivalDir = Cell(0, 1)
            while (isActive) {
                world.demoSetup(playerCells[0], rivalStart)
                delay(500)
                val player = world.cycles[0]; val rival = world.cycles[1]
                for (t in 1 until playerCells.size) {
                    // Player advances first, so its wall cell exists before the rival tests it.
                    val p = playerCells[t]
                    player.pos = p; world.occupied.add(p); player.history.add(p)
                    if (rival.alive) {
                        val n = Cell(rival.pos.r + rivalDir.r, rival.pos.c + rivalDir.c)
                        if (n in world.occupied || n.c >= COLS) world.kill(rival)
                        else { rival.pos = n; world.occupied.add(n); rival.history.add(n) }
                    }
                    delay(140)
                }
                world.kill(rival)
                delay(1100)
            }
        } else {
            val start = nowSec()
            while (isActive && world.playing) {
                delay((world.tick * 1000).toLong())
                world.timeLeft = max(0.0, world.timeLimit - (nowSec() - start))
                if (world.timeLeft <= 0) { world.fail(); break }
                world.stepAll()
            }
        }
    }

    val neon = neon(level)
    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp)).background(Color.Black),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        frame
        // Rivals: one bike icon per enemy cycle, dimmed once it's derezzed.
        Row(Modifier.height(20.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            for (cy in world.cycles) if (!cy.isPlayer) Canvas(Modifier.size(30.dp, 16.dp)) {
                bike(size.width / 2.0, size.height / 2.0, 1.0, 0.0, cy.color, size.width / 1.6, if (cy.alive) 1.0 else 0.25)
            }
        }
        if (!isDemo) {
            val f = world.timeLeft / world.timeLimit
            TimeBar(f, Modifier.fillMaxWidth().padding(horizontal = 48.dp).height(6.dp), fill = if (f < 0.3) rgb(1.0, 0.3, 0.26) else neon, track = neon.op(0.15))
        }
        Canvas(
            Modifier.fillMaxWidth().weight(1f).padding(horizontal = 8.dp)
                .drawWithCache { onDrawBehind { grid(level) } }
        ) {
            frame
            val w = size.width.toDouble(); val h = size.height.toDouble()
            val cell = min(w / COLS, h / ROWS)
            val ox = (w - cell * COLS) / 2; val oy = (h - cell * ROWS) / 2
            fun ctr(p: Cell) = P(ox + (p.c + 0.5) * cell, oy + (p.r + 0.5) * cell)
            for (cy in world.cycles) trail(cy.history.map { ctr(it) }, cy.color, cell)
            for (cy in world.cycles) if (cy.alive) { val p = ctr(cy.pos); bike(p.x, p.y, cy.dir.c.toDouble(), cy.dir.r.toDouble(), cy.color, cell, 1.0) }
            val now = nowSec()
            for (d in world.derez) { val p = ctr(d.cell); derezArt(p.x, p.y, d.color, cell, now - d.at) }
        }
        // Steering.
        Row(Modifier.padding(bottom = 10.dp), horizontalArrangement = Arrangement.spacedBy(40.dp)) {
            TurnKey(Icons.Filled.TurnLeft, neon, isDemo) { world.turn(-1) }
            TurnKey(Icons.Filled.TurnRight, neon, isDemo) { world.turn(1) }
        }
    }
}

/** A dark glass turn key with a neon edge. */
@Composable
private fun TurnKey(icon: ImageVector, color: Color, isDemo: Boolean, onPress: () -> Unit) {
    Box(Modifier.size(96.dp, 64.dp).then(if (isDemo) Modifier else Modifier.pressDown(onDown = onPress)), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val u = density.toDouble(); val w = size.width.toDouble(); val h = size.height.toDouble(); val r = 16 * u
            rrect(0.0, 0.0, w, h, r, vgrad(listOf(gray(0.14), gray(0.04)), 0.0, h))
            rrectStroke(3 * u, 3 * u, w - 6 * u, h - 6 * u, r - 3 * u, color.op(0.3), 6 * u)
            rrectStroke(u, u, w - 2 * u, h - 2 * u, r - u, color, 2 * u)
        }
        Icon(icon, null, tint = color, modifier = Modifier.size(36.dp))
    }
}

// TRON art (iOS LCArt).

/** The arena's neon: TRON blue, then violet, then Clu's orange-red at 6–7. */
private fun neon(level: Int) = if (level >= 6) rgb(1.0, 0.45, 0.22) else if (level >= 4) rgb(0.72, 0.45, 1.0) else rgb(0.25, 0.85, 1.0)

/** A light wall: a glowing ribbon through the cells the cycle has driven. */
private fun DrawScope.trail(pts: List<P>, color: Color, cell: Double) {
    if (pts.isEmpty()) return
    if (pts.size == 1) { rrect(pts[0].x - cell * 0.21, pts[0].y - cell * 0.21, cell * 0.42, cell * 0.42, cell * 0.08, color); return }
    val line = Path(); line.m(pts[0].x, pts[0].y)
    for (p in pts.drop(1)) line.l(p.x, p.y)
    strokePath(line, color.op(0.22), cell * 0.95, StrokeCap.Square, StrokeJoin.Miter)
    strokePath(line, color, cell * 0.44, StrokeCap.Square, StrokeJoin.Miter)
    strokePath(line, Color.White.op(0.75), max(density.toDouble(), cell * 0.12), StrokeCap.Square, StrokeJoin.Miter)
}

/** A light cycle along its heading: dark body, glowing edge stripe and wheel rims. */
private fun DrawScope.bike(px: Double, py: Double, dx: Double, dy: Double, color: Color, cell: Double, alpha: Double) {
    val u = density.toDouble()
    translate(px.f, py.f) { rotateRad(atan2(dy, dx).f, Offset.Zero) {
        val L = cell * 1.3; val W = cell * 0.62
        drawOval(radial(listOf(color.op(0.45 * alpha), color.op(0.0)), 0.0, 0.0, L * 0.7), Offset((-L * 0.7).f, (-W).f), androidx.compose.ui.geometry.Size((L * 1.4).f, (W * 2).f))
        rrect(-L * 0.5, -W * 0.42, L, W * 0.84, W * 0.42, gray(0.06).op(alpha))
        rrectStroke(-L * 0.5, -W * 0.42, L, W * 0.84, W * 0.42, color.op(alpha), max(1.2 * u, cell * 0.1))
        for (x in listOf(-L * 0.3, L * 0.3)) {
            circle(x, 0.0, W * 0.3, gray(0.02).op(alpha))
            circleStroke(x, 0.0, W * 0.3, color.op(alpha), max(u, cell * 0.08))
        }
        rrect(-L * 0.08, -W * 0.16, L * 0.3, W * 0.32, W * 0.16, color.op(0.85 * alpha))
        rrect(L * 0.32, -W * 0.08, L * 0.16, W * 0.16, W * 0.08, Color.White.op(alpha))
    } }
}

/** Derezz: a flash and a scatter of fading light cubes. */
private fun DrawScope.derezArt(px: Double, py: Double, color: Color, cell: Double, age: Double) {
    if (age >= 1.0 || age < 0) return
    if (age < 0.3) circleStroke(px, py, cell * (0.5 + age * 4), color.op(1 - age / 0.3), 2 * density.toDouble())
    for (i in 0 until 14) {
        val dir = i / 14.0 * 2 * PI + (i % 3) * 0.3
        val d = cell * (0.4 + age * (2.2 + (i % 4) * 0.5))
        val s = cell * (0.28 - age * 0.18)
        rect(px + cos(dir) * d - s / 2, py + sin(dir) * d - s / 2, s, s, color.op(max(0.0, 1 - age)))
    }
}

/** The arena: black, a glowing grid (brighter every fourth line) and a neon border. */
private fun DrawScope.grid(level: Int) {
    val u = density.toDouble(); val w = size.width.toDouble(); val h = size.height.toDouble()
    val cell = min(w / COLS, h / ROWS)
    val bw = cell * COLS; val bh = cell * ROWS
    val ox = (w - bw) / 2; val oy = (h - bh) / 2
    val n = neon(level)
    rect(ox, oy, bw, bh, radial(listOf(n.op(0.08), Color.Transparent), ox + bw / 2, oy + bh / 2, max(bw, bh) * 0.7))
    val minor = Path(); val major = Path()
    for (c in 0..COLS) { val p = if (c % 4 == 0) major else minor; p.m(ox + c * cell, oy); p.l(ox + c * cell, oy + bh) }
    for (r in 0..ROWS) { val p = if (r % 4 == 0) major else minor; p.m(ox, oy + r * cell); p.l(ox + bw, oy + r * cell) }
    strokePath(minor, n.op(0.14), u, StrokeCap.Butt)
    strokePath(major, n.op(0.32), u, StrokeCap.Butt)
    rrectStroke(ox, oy, bw, bh, 6 * u, n.op(0.25), 8 * u)
    rrectStroke(ox, oy, bw, bh, 6 * u, n, 2.5 * u)
}
