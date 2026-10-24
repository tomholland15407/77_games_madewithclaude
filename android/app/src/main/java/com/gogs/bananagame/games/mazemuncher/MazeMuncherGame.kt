package com.gogs.bananagame.games.mazemuncher

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.material.icons.automirrored.filled.ArrowLeft
import androidx.compose.material.icons.automirrored.filled.ArrowRight
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.ArrowDropUp
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Reflex — Maze Muncher (iOS MazeMuncherGame.swift): steer the muncher with the d-pad, eat every
 * pellet before the clock, and don't let the red ghost catch you.
 */
object MazeMuncherGame {
    val definition = GameDefinition(
        id = "maze-muncher",
        title = "Maze Muncher",
        genre = Genre.REFLEX,
        manual = GameManual(
            bullets = listOf(
                "Steer the muncher with the d-pad and gobble every pellet in the maze.",
                "A ghost hunts you the whole time.",
                "Clear the board before the clock runs out.",
                "Get caught by the ghost, or run out of time, and you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Điều khiển kẻ ăn bằng d-pad và đớp hết mọi viên trong mê cung.",
                "Một con ma săn bạn suốt cả màn.",
                "Dọn sạch bàn trước khi hết giờ.",
                "Bị ma bắt, hoặc hết giờ, sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> MazeMuncherView(level, onWin, onFail) }
    )
}

private val MAZE = listOf(
    "#############",
    "#...........#",
    "#.#.#.#.#.#.#",
    "#...........#",
    "#.#.#.#.#.#.#",
    "#.....G.....#",
    "#.#.#.#.#.#.#",
    "#...........#",
    "#.#.#.#.#.#.#",
    "#...........#",
    "#.....P.....#",
    "#############",
)
private val COLS = MAZE[0].length
private val ROWS = MAZE.size
private const val MUNCHER_STEP = 0.16

private data class Cell(val c: Int, val r: Int)
private data class Dir(val dc: Int, val dr: Int) { companion object { val NONE = Dir(0, 0) } }

private val demoPellets = (5 downTo 1).map { Cell(it, 10) } + (9 downTo 7).map { Cell(1, it) } + (2..11).map { Cell(it, 7) }
private val demoTurns = listOf<Pair<Cell?, Dir>>(null to Dir(-1, 0), Cell(1, 10) to Dir(0, -1), Cell(1, 7) to Dir(1, 0))

private class MuncherWorld(level: Int, val isDemo: Boolean) {
    val ghostStep = listOf(0.30, 0.26, 0.22, 0.19, 0.16, 0.14, 0.115)[min(level, 7) - 1]
    val timeLimit = listOf(58.0, 55.0, 52.0, 49.0, 46.0, 43.0, 40.0)[min(level, 7) - 1]
    val walls = HashSet<Cell>()
    val pellets = HashSet<Cell>()
    var totalPellets = 0
    var muncher = Cell(1, 1); var muncherFrom = Cell(1, 1); var muncherT0 = 0.0
    var ghost = Cell(1, 1); var ghostFrom = Cell(1, 1); var ghostT0 = 0.0
    var dir = Dir.NONE
    var pending: Dir? = null
    var ghostDir = Dir.NONE
    var facing = 0.0
    var chomp = false; var chompT0 = 0.0
    var timeLeft = timeLimit
    var done = false
    var munchAcc = 0.0; var ghostAcc = 0.0
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    fun setup() {
        walls.clear(); pellets.clear()
        MAZE.forEachIndexed { r, line ->
            line.forEachIndexed { c, ch ->
                when (ch) {
                    '#' -> walls.add(Cell(c, r))
                    '.' -> pellets.add(Cell(c, r))
                    'P' -> muncher = Cell(c, r)
                    'G' -> ghost = Cell(c, r)
                }
            }
        }
        muncherFrom = muncher; ghostFrom = ghost
        totalPellets = pellets.size
        dir = Dir.NONE; pending = null; ghostDir = Dir.NONE
        facing = 0.0; chomp = false; timeLeft = timeLimit
        munchAcc = 0.0; ghostAcc = 0.0; done = false
    }

    fun isWall(c: Int, r: Int) = c < 0 || c >= COLS || r < 0 || r >= ROWS || Cell(c, r) in walls

    fun tick(dt: Double) {
        munchAcc += dt
        if (munchAcc >= MUNCHER_STEP) { munchAcc -= MUNCHER_STEP; stepMuncher() }
        if (done) return
        ghostAcc += dt
        if (ghostAcc >= ghostStep) { ghostAcc -= ghostStep; stepGhost() }
    }

    private fun stepMuncher() {
        val p = pending
        if (p != null && !isWall(muncher.c + p.dc, muncher.r + p.dr)) { dir = p; pending = null }
        if (dir == Dir.NONE || isWall(muncher.c + dir.dc, muncher.r + dir.dr)) return
        muncherFrom = muncher; muncherT0 = nowSec()
        muncher = Cell(muncher.c + dir.dc, muncher.r + dir.dr)
        facing = when { dir.dc > 0 -> 0.0; dir.dc < 0 -> 180.0; dir.dr > 0 -> 90.0; dir.dr < 0 -> -90.0; else -> facing }
        chomp = !chomp; chompT0 = nowSec()
        if (pellets.remove(muncher)) {
            SoundManager.tap(); Haptics.tap()
            if (pellets.isEmpty()) { win(); return }
        }
        if (muncher == ghost) fail()
    }

    private fun stepGhost() {
        // Greedy chase, no about-face unless it's the only way out (fixed tie-break in the demo).
        val base = listOf(Dir(0, -1), Dir(0, 1), Dir(-1, 0), Dir(1, 0))
        val options = if (isDemo) base else base.shuffled()
        var best: Dir? = null; var bestDist = Int.MAX_VALUE
        for (d in options) {
            if (isWall(ghost.c + d.dc, ghost.r + d.dr)) continue
            if (d.dc == -ghostDir.dc && d.dr == -ghostDir.dr && ghostDir != Dir.NONE) continue
            val dist = abs(ghost.c + d.dc - muncher.c) + abs(ghost.r + d.dr - muncher.r)
            if (dist < bestDist) { bestDist = dist; best = d }
        }
        if (best == null) best = options.firstOrNull { !isWall(ghost.c + it.dc, ghost.r + it.dr) }
        val move = best ?: return
        ghostDir = move
        ghostFrom = ghost; ghostT0 = nowSec()
        ghost = Cell(ghost.c + move.dc, ghost.r + move.dr)
        if (ghost == muncher) fail()
    }

    fun win() { if (done) return; done = true; onWin() }
    fun fail() { if (done) return; done = true; SoundManager.error(); onFail() }
}

@Composable
private fun MazeMuncherView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { MuncherWorld(level, isDemo).also { it.setup() } }
    world.onWin = onWin; world.onFail = onFail
    var demoPress by remember { mutableStateOf<Dir?>(null) }
    val start = remember { nowSec() }
    val frame by rememberFrameLoop { dt ->
        if (isDemo || world.done) return@rememberFrameLoop
        world.timeLeft = max(0.0, world.timeLimit - (nowSec() - start))
        if (world.timeLeft <= 0) { world.fail(); return@rememberFrameLoop }
        world.tick(dt)
    }

    LaunchedEffect(Unit) {
        if (!isDemo) return@LaunchedEffect
        val dt = 1.0 / 60.0
        while (isActive) {
            world.setup()
            world.pellets.clear(); world.pellets.addAll(demoPellets)
            demoPress = null
            delay(600)
            var turn = 0; var flash = 0.0
            while (isActive && !world.done) {
                if (turn < demoTurns.size) {
                    val (at, d) = demoTurns[turn]
                    if (at == null || at == world.muncher) { world.pending = d; Haptics.tap(); demoPress = d; flash = 0.22; turn++ }
                }
                world.tick(dt)
                flash -= dt
                if (flash <= 0) demoPress = null
                delay(16)
            }
            demoPress = null
            delay(1300)
        }
    }

    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(if (isDemo) 4.dp else 8.dp)) {
        frame
        val eaten = world.totalPellets - world.pellets.size
        Canvas(Modifier.fillMaxWidth().height(if (isDemo) 14.dp else 21.dp).padding(top = if (isDemo) 6.dp else 0.dp)) {
            pacDigits("$eaten/${world.totalPellets}", (if (isDemo) 2.0 else 3.0) * density)
        }
        if (!isDemo) {
            val f = world.timeLeft / world.timeLimit
            TimeBar(f, Modifier.fillMaxWidth().padding(horizontal = 48.dp).height(6.dp), fill = if (f < 0.3) pacRed else pacYellow, track = pacWall.op(0.35))
        }
        Canvas(Modifier.fillMaxWidth().weight(1f)) {
            frame
            val cell = min(size.width / COLS.toDouble(), size.height / ROWS.toDouble())
            val ox = (size.width - cell * COLS) / 2; val oy = (size.height - cell * ROWS) / 2
            fun px(c: Double) = ox + (c + 0.5) * cell
            fun py(r: Double) = oy + (r + 0.5) * cell
            pacMaze(world.walls, cell, ox, oy)
            val d = cell * 0.22
            for (k in world.pellets) rrect(px(k.c.toDouble()) - d / 2, py(k.r.toDouble()) - d / 2, d, d, d * 0.2, pacPellet)
            val now = nowSec()
            val mt = clamp((now - world.muncherT0) / MUNCHER_STEP, 0.0, 1.0)
            val mx = lerp(world.muncherFrom.c.toDouble(), world.muncher.c.toDouble(), mt)
            val my = lerp(world.muncherFrom.r.toDouble(), world.muncher.r.toDouble(), mt)
            val ct = clamp((now - world.chompT0) / MUNCHER_STEP, 0.0, 1.0)
            val open = if (world.chomp) lerp(1.0, 0.08, ct) else lerp(0.08, 1.0, ct)
            muncherArt(px(mx), py(my), cell * 0.56, open, world.facing)
            val gt = clamp((now - world.ghostT0) / world.ghostStep, 0.0, 1.0)
            val gx = lerp(world.ghostFrom.c.toDouble(), world.ghost.c.toDouble(), gt)
            val gy = lerp(world.ghostFrom.r.toDouble(), world.ghost.r.toDouble(), gt)
            val s = cell * 1.12
            ghostArt(px(gx) - s / 2, py(gy) - s / 2, s, world.ghostDir, (world.ghost.c + world.ghost.r) % 2)
        }
        Box(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 6.dp)) {
            Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(if (isDemo) 5.dp else 10.dp)) {
                PacKey(Icons.Filled.ArrowDropUp, Dir(0, -1), isDemo, demoPress, world)
                Row(horizontalArrangement = Arrangement.spacedBy(if (isDemo) 6.dp else 10.dp)) {
                    PacKey(Icons.AutoMirrored.Filled.ArrowLeft, Dir(-1, 0), isDemo, demoPress, world)
                    PacKey(Icons.Filled.ArrowDropDown, Dir(0, 1), isDemo, demoPress, world)
                    PacKey(Icons.AutoMirrored.Filled.ArrowRight, Dir(1, 0), isDemo, demoPress, world)
                }
            }
            if (!isDemo) Canvas(Modifier.align(Alignment.TopEnd).padding(top = 15.dp).size(128.dp, 24.dp)) { fruitRow(level) }
        }
    }
}

/** A black arcade key rimmed in maze blue; lights up yellow while pressed (or demo-pressed). */
@Composable
private fun PacKey(icon: ImageVector, d: Dir, isDemo: Boolean, demoPress: Dir?, world: MuncherWorld) {
    var held by remember { mutableStateOf(false) }
    val on = held || demoPress == d
    Box(
        Modifier.scale(if (on) 0.9f else 1f).size(if (isDemo) 54.dp else 74.dp, if (isDemo) 34.dp else 54.dp)
            .background(if (on) pacYellow else Color.Black, RoundedCornerShape(12.dp))
            .border(if (on) 3.dp else 2.2.dp, if (on) Color.White else pacWall, RoundedCornerShape(12.dp))
            .then(if (isDemo) Modifier else Modifier.pressDown(onDown = {
                held = true
                if (!world.done) { world.pending = d; Haptics.tap() }
            }, onUp = { held = false })),
        contentAlignment = Alignment.Center
    ) {
        if (!on) Box(Modifier.fillMaxSize().padding(4.dp).border(1.2.dp, pacWall.op(0.7), RoundedCornerShape(8.dp)))
        Icon(icon, null, tint = if (on) Color.Black else pacYellow, modifier = Modifier.size(if (isDemo) 26.dp else 34.dp))
    }
}

// Arcade art (iOS PacArt and friends).

private val pacWall = rgb(0.13, 0.13, 1.0)
private val pacPellet = rgb(1.0, 0.72, 0.68)
private val pacYellow = rgb(1.0, 1.0, 0.0)
private val pacRed = rgb(1.0, 0.0, 0.0)
private val pacWhite = rgb(0.87, 0.87, 1.0)

private val glyphs = mapOf(
    '0' to listOf("..XXX..", ".XX.XX.", "XX...XX", "XX...XX", "XX...XX", ".XX.XX.", "..XXX.."),
    '1' to listOf("...XX..", "..XXX..", "...XX..", "...XX..", "...XX..", "...XX..", ".XXXXXX"),
    '2' to listOf(".XXXXX.", "XX...XX", ".....XX", "...XXX.", ".XXX...", "XX.....", "XXXXXXX"),
    '3' to listOf("XXXXXXX", "....XX.", "...XX..", "..XXXX.", ".....XX", "XX...XX", ".XXXXX."),
    '4' to listOf("...XXX.", "..XXXX.", ".XX.XX.", "XX..XX.", "XXXXXXX", "....XX.", "....XX."),
    '5' to listOf("XXXXXX.", "XX.....", "XXXXXX.", ".....XX", ".....XX", "XX...XX", ".XXXXX."),
    '6' to listOf("..XXXX.", ".XX....", "XX.....", "XXXXXX.", "XX...XX", "XX...XX", ".XXXXX."),
    '7' to listOf("XXXXXXX", "XX...XX", "....XX.", "...XX..", "..XX...", "..XX...", "..XX..."),
    '8' to listOf(".XXXX..", "XX...X.", "XXX..X.", ".XXXX..", "X..XXXX", "X....XX", ".XXXXX."),
    '9' to listOf(".XXXXX.", "XX...XX", "XX...XX", ".XXXXXX", ".....XX", "....XX.", ".XXXX.."),
    '/' to listOf(".....XX", "....XX.", "...XX..", "..XX...", ".XX....", "XX.....", "X......"),
)

/** White arcade pixel digits, centred. */
private fun DrawScope.pacDigits(text: String, pixel: Double) {
    val adv = pixel * 8
    val total = text.length * adv - pixel
    val ox = (size.width - total) / 2; val oy = (size.height - pixel * 7) / 2
    val p = Path()
    text.forEachIndexed { i, ch ->
        val rows = glyphs[ch] ?: return@forEachIndexed
        rows.forEachIndexed { y, row ->
            var x = 0
            while (x < row.length) {
                if (row[x] != 'X') { x++; continue }
                var e = x
                while (e + 1 < row.length && row[e + 1] == 'X') e++
                val rx = ox + i * adv + x * pixel; val ry = oy + y * pixel
                p.addRect(androidx.compose.ui.geometry.Rect(rx.f, ry.f, (rx + (e - x + 1) * pixel + 0.3).f, (ry + pixel + 0.3).f))
                x = e + 1
            }
        }
    }
    fillPath(p, pacWhite)
}

/** A blue double line round the border and a thin outlined block on every pillar. */
private fun DrawScope.pacMaze(walls: Set<Cell>, cell: Double, ox: Double, oy: Double) {
    if (walls.isEmpty()) return
    val lw = max(1.4 * density, cell * 0.085)
    val bw = COLS * cell; val bh = ROWS * cell
    rrectStroke(ox + cell * 0.3, oy + cell * 0.3, bw - cell * 0.6, bh - cell * 0.6, cell * 0.55, pacWall, lw)
    rrectStroke(ox + cell * 0.78, oy + cell * 0.78, bw - cell * 1.56, bh - cell * 1.56, cell * 0.3, pacWall, lw)
    for (k in walls) {
        if (k.c <= 0 || k.r <= 0 || k.c >= COLS - 1 || k.r >= ROWS - 1) continue
        rrectStroke(ox + k.c * cell + cell * 0.2, oy + k.r * cell + cell * 0.2, cell * 0.6, cell * 0.6, cell * 0.16, pacWall, lw)
    }
}

/** The muncher: a disc with a wedge mouth facing `facing` degrees; `open` 0…1 is the chomp. */
private fun DrawScope.muncherArt(cx: Double, cy: Double, r: Double, open: Double, facing: Double) {
    val half = 2 + 42 * clamp(open, 0.0, 1.0)
    val p = Path(); p.m(cx, cy)
    p.arc(cx, cy, r, deg(facing + half), deg(facing + 360 - half))
    p.close()
    fillPath(p, pacYellow)
}

/** The red chaser ghost; `frame` flips the skirt each step and the pupils look along its heading. */
private fun DrawScope.ghostArt(x: Double, y: Double, s: Double, d: Dir, frame: Int) {
    fun px(fx: Double) = x + fx * s
    fun py(fy: Double) = y + fy * s
    val body = Path()
    body.m(px(0.06), py(0.9)); body.l(px(0.06), py(0.48))
    body.arc(px(0.5), py(0.48), 0.44 * s, deg(180.0), deg(360.0))
    body.l(px(0.94), py(0.9))
    val feet = if (frame == 0) listOf(0.94, 0.8, 0.66, 0.5, 0.34, 0.2, 0.06) else listOf(0.94, 0.86, 0.72, 0.58, 0.42, 0.28, 0.14, 0.06)
    feet.forEachIndexed { i, fx -> if (i > 0) body.l(px(fx), py(if (i % 2 == 1) 0.76 else 0.94)) }
    body.close()
    fillPath(body, pacRed)
    val lx = d.dc * 0.05; val ly = d.dr * 0.06
    for (ex in listOf(0.33, 0.67)) {
        oval(x + (ex - 0.11 + lx * 0.5) * s, y + (0.3 + ly * 0.5) * s, 0.22 * s, 0.27 * s, pacWhite)
        oval(x + (ex - 0.06 + lx * 1.4) * s, y + (0.39 + ly * 1.4) * s, 0.12 * s, 0.12 * s, pacWall)
    }
}

/** The level indicator: one bonus fruit per level reached, newest on the right. */
private fun DrawScope.fruitRow(level: Int) {
    val kinds = listOf(FruitKind.CHERRY, FruitKind.STRAWBERRY, FruitKind.DEKOPON, FruitKind.DEKOPON, FruitKind.APPLE, FruitKind.APPLE, FruitKind.MELON)
    val n = clampI(level, 1, 7)
    val r = min(size.height * 0.42, size.width / n * 0.47).toDouble()
    val step = r * 2.1
    for (i in 0 until n) FruitArt.draw(this, kinds[i], size.width - r - (n - 1 - i) * step, size.height / 2.0, r)
}
