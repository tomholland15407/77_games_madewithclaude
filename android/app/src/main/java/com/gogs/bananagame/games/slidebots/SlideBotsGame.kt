package com.gogs.bananagame.games.slidebots

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.HourglassBottom
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.Start
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/**
 * Brain — Slide Bots (iOS RicochetRobotsGame.swift, id "ricochet-robots"): robots slide until a wall
 * or robot stops them. Select a robot, d-pad it, and land the banana robot on the ringed target using
 * the others as blockers. Reset is free; only the clock fails. Boards are BFS-verified per level.
 */
object SlideBotsGame {
    val definition = GameDefinition(
        id = "ricochet-robots",
        title = "Slide Bots",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Robots slide until they hit a wall or another robot.",
                "Tap a robot to select it, then use the d-pad to send it sliding.",
                "Get the banana robot onto the ringed target cell, using the others as blockers.",
                "Tap reset (↺) to snap everyone back; run out of time and you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Robot trượt cho đến khi gặp tường hoặc robot khác.",
                "Chạm một robot để chọn, rồi dùng d-pad để cho nó trượt.",
                "Đưa robot chuối vào ô mục tiêu có vòng, dùng các robot khác làm vật chặn.",
                "Chạm đặt lại (↺) để đưa mọi người về chỗ cũ; hết giờ sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        prefetch = { level -> BoardCache.prefetch(key(level)) { gen(level) } },
        content = { level, onWin, onFail -> SlideBotsView(level, onWin, onFail) }
    )

    fun key(level: Int) = BoardCache.key("ricochet-robots", level)
    private fun li(level: Int) = min(level, 7) - 1
    fun gen(level: Int): RRBoard {
        val i = li(level)
        return RRGen.generate(listOf(6, 6, 7, 7, 8, 8, 8)[i], listOf(2, 3, 3, 4, 4, 4, 5)[i], listOf(4, 5, 6, 8, 9, 11, 13)[i],
            listOf(2, 3, 4, 4, 5, 5, 6)[i], listOf(5, 6, 7, 8, 9, 10, 11)[i])
    }
    fun timeLimit(level: Int) = listOf(55.0, 60.0, 65.0, 70.0, 75.0, 80.0, 80.0)[li(level)]
}

class RRBoard(val n: Int, val walls: Set<Int>, val robots: List<Int>, val targetCell: Int)

object RRGen {
    // 0 = up, 1 = right, 2 = down, 3 = left
    private val dirVecs = listOf(-1 to 0, 0 to 1, 1 to 0, 0 to -1)

    /** Walls are encoded (cell*4 + dir), stored on both sides. */
    fun addWall(walls: MutableSet<Int>, r: Int, c: Int, dir: Int, n: Int) {
        walls.add((r * n + c) * 4 + dir)
        val (dr, dc) = dirVecs[dir]
        val nr = r + dr; val nc = c + dc
        if (nr in 0 until n && nc in 0 until n) walls.add((nr * n + nc) * 4 + (dir + 2) % 4)
    }

    fun slide(from: Int, dir: Int, blockers: Set<Int>, walls: Set<Int>, n: Int): Int {
        var pos = from
        val (dr, dc) = dirVecs[dir]
        while (true) {
            if (pos * 4 + dir in walls) break
            val nr = pos / n + dr; val nc = pos % n + dc
            if (nr !in 0 until n || nc !in 0 until n) break
            val np = nr * n + nc
            if (np in blockers) break
            pos = np
        }
        return pos
    }

    /** Packs the target robot and the sorted blockers (each < 64) into one Long key. */
    private fun key(t: Int, b: List<Int>): Long { var k = t.toLong(); for (x in b) k = (k shl 6) or x.toLong(); return k }

    /** Minimum slides for robot 0 to reach the target; blockers are interchangeable. Null if over budget. */
    fun optimalMoves(start: List<Int>, targetCell: Int, walls: Set<Int>, n: Int, cap: Int): Int? {
        val t0 = start[0]; val b0 = start.drop(1).sorted()
        if (t0 == targetCell) return 0
        val seen = HashSet<Long>(); seen.add(key(t0, b0))
        val qt = ArrayList<Int>(); val qb = ArrayList<List<Int>>(); val qd = ArrayList<Int>()
        qt.add(t0); qb.add(b0); qd.add(0)
        var head = 0; var expanded = 0
        while (head < qt.size) {
            val t = qt[head]; val b = qb[head]; val d = qd[head]; head++
            if (++expanded > cap) return null
            val bset = b.toHashSet()
            for (dir in 0 until 4) {
                val nt = slide(t, dir, bset, walls, n)
                if (nt != t) {
                    if (nt == targetCell) return d + 1
                    if (seen.add(key(nt, b))) { qt.add(nt); qb.add(b); qd.add(d + 1) }
                }
            }
            for (i in b.indices) {
                val others = HashSet(bset); others.remove(b[i]); others.add(t)
                for (dir in 0 until 4) {
                    val np = slide(b[i], dir, others, walls, n)
                    if (np != b[i]) {
                        val nb = b.toMutableList(); nb[i] = np; nb.sort()
                        if (seen.add(key(t, nb))) { qt.add(t); qb.add(nb); qd.add(d + 1) }
                    }
                }
            }
        }
        return null
    }

    fun generate(n: Int, robotCount: Int, wallCount: Int, minOpt: Int, maxOpt: Int): RRBoard {
        var fallback: RRBoard? = null
        repeat(500) {
            val walls = HashSet<Int>()
            repeat(wallCount) { addWall(walls, Random.nextInt(n), Random.nextInt(n), Random.nextInt(4), n) }
            val targetCell = Random.nextInt(n * n)
            // Ensure a robot can stop ON the target: give it at least one adjacent wall.
            addWall(walls, targetCell / n, targetCell % n, Random.nextInt(4), n)
            val cells = (0 until n * n).shuffled().filter { it != targetCell }
            if (cells.size < robotCount) return@repeat
            val start = cells.take(robotCount)
            val opt = optimalMoves(start, targetCell, walls, n, 120_000) ?: return@repeat
            val board = RRBoard(n, walls, start, targetCell)
            if (opt in minOpt..maxOpt) return board
            if (opt in 1..maxOpt) fallback = board
        }
        return fallback ?: RRBoard(n, emptySet(), (0 until robotCount).toList(), n * n - 1)
    }
}

private val blockerColors = listOf(rgb(0.22, 0.46, 0.92), rgb(0.9, 0.24, 0.22), rgb(0.22, 0.68, 0.32), rgb(0.72, 0.74, 0.8))

// Demo: a 6×6 board whose optimum is 3 slides, and the banana robot can never reach the ring alone:
// it slides ▼ ▶ over the target, ↺ resets, blue slides ▶ as a backstop, then ▼ ▶ stops on the ring.
private val demoWalls = listOf(Triple(2, 0, 2), Triple(3, 2, 2), Triple(3, 4, 2), Triple(3, 5, 1), Triple(5, 2, 1))
private sealed class DemoStep { class Tap(val i: Int) : DemoStep(); class Slide(val dir: Int) : DemoStep(); object Reset : DemoStep() }
private val demoSteps = listOf(DemoStep.Tap(0), DemoStep.Slide(2), DemoStep.Slide(1), DemoStep.Reset, DemoStep.Tap(1), DemoStep.Slide(1),
    DemoStep.Tap(0), DemoStep.Slide(2), DemoStep.Slide(1))

/** Board geometry (iOS RRBoardArt): a square 98% of the shorter side, centred. */
private class RRGeo(w: Double, h: Double, n: Int) {
    val side = min(w, h) * 0.98
    val cell = if (n > 0) side / n else 0.0
    val ox = (w - side) / 2
    val oy = (h - side) / 2
}

@Composable
private fun SlideBotsView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val timeLimit = SlideBotsGame.timeLimit(level)
    var playing by remember { mutableStateOf(true) }
    var ready by remember { mutableStateOf(false) }
    var boardN by remember { mutableIntStateOf(0) }
    var walls by remember { mutableStateOf(setOf<Int>()) }
    var robots by remember { mutableStateOf(listOf<Int>()) }
    var startRobots by remember { mutableStateOf(listOf<Int>()) }
    var targetCell by remember { mutableIntStateOf(0) }
    var moves by remember { mutableIntStateOf(0) }
    var selected by remember { mutableIntStateOf(0) }
    var timeLeft by remember { mutableDoubleStateOf(timeLimit) }
    var demoKey by remember { mutableStateOf<String?>(null) }
    var demoFinger by remember { mutableStateOf<Int?>(null) }
    // Presentation: where each robot slid from, and when (slides ease out over 0.16 s; reset 0.2 s).
    val anim = remember { object { var from = listOf<Int>(); var t0 = -10.0; var dur = 0.16 } }
    val handP = rememberHand()
    val dens = LocalDensity.current.density.toDouble()
    val tick by rememberFrameLoop()

    fun win() { if (!playing) return; playing = false; onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }
    fun setRobots(to: List<Int>, dur: Double) { anim.from = robots; anim.t0 = nowSec(); anim.dur = dur; robots = to }

    fun select(i: Int) { if (!playing) return; selected = i; SoundManager.tap(); Haptics.tap() }
    fun move(dir: Int) {
        if (!playing || selected >= robots.size) return
        val others = robots.toHashSet(); others.remove(robots[selected])
        val np = RRGen.slide(robots[selected], dir, others, walls, boardN)
        if (np == robots[selected]) return
        setRobots(robots.toMutableList().also { it[selected] = np }, 0.16)
        moves++
        SoundManager.tap(); Haptics.tap()
        if (robots[0] == targetCell) win()
    }
    fun resetPositions() {
        if (!playing) return
        setRobots(startRobots, 0.2)
        moves = 0; selected = 0
        SoundManager.tap(); Haptics.tap()
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            val arrows = listOf("up", "right", "down", "left")
            while (isActive) {
                val w = HashSet<Int>(); for ((r, c, d) in demoWalls) RRGen.addWall(w, r, c, d, 6)
                boardN = 6; walls = w
                robots = listOf(2, 18); startRobots = robots; anim.from = robots
                targetCell = 3 * 6 + 4
                moves = 0; selected = 0; demoKey = null; demoFinger = null
                timeLeft = timeLimit; playing = true; ready = true
                delay(800)
                for (step in demoSteps) {
                    when (step) {
                        is DemoStep.Tap -> { demoFinger = step.i; delay(300); select(step.i); delay(250); demoFinger = null }
                        is DemoStep.Slide -> { demoKey = arrows[step.dir]; move(step.dir); delay(200); demoKey = null; delay(300) }
                        DemoStep.Reset -> { delay(400); demoKey = "reset"; resetPositions(); delay(200); demoKey = null; delay(400) }
                    }
                }
                delay(1300)
            }
        } else {
            val t0 = System.currentTimeMillis()
            val b = BoardCache.take(SlideBotsGame.key(level)) { SlideBotsGame.gen(level) }
            BoardCache.holdBrainstorm(t0, 0.7)
            boardN = b.n; walls = b.walls; robots = b.robots; startRobots = b.robots; anim.from = b.robots
            targetCell = b.targetCell; moves = 0; selected = 0
            ready = true; playing = true; timeLeft = timeLimit
            val start = nowSec()
            while (isActive && playing) {
                delay(50)
                timeLeft = max(0.0, timeLimit - (nowSec() - start))
                if (timeLeft <= 0) { fail(); break }
            }
        }
    }

    if (!ready) { BrainstormingView(rgb(0.10, 0.13, 0.20), rgb(0.04, 0.05, 0.10)); return }

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .drawBehind { table() }.padding(vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(if (isDemo) 6.dp else 10.dp)
    ) {
        // Slides so far, the reset key, and the sand timer.
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp), verticalAlignment = Alignment.CenterVertically) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(Icons.Filled.Start, null, tint = RRCream.op(0.75), modifier = Modifier.size(if (isDemo) 15.dp else 19.dp))
                    Text("$moves", style = ts(if (isDemo) 16.0 else 20.0, FontWeight.Black, Color.White).copy(fontFeatureSettings = "tnum"))
                }
                Spacer(Modifier.weight(1f))
                RRKeyButton(Icons.Filled.Replay, if (isDemo) 64.dp else 88.dp, if (isDemo) 30.dp else 40.dp, 12.0, isDemo && demoKey == "reset", isDemo,
                    if (isDemo) 17.dp else 21.dp) { resetPositions() }
            }
            if (!isDemo) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 40.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Filled.HourglassBottom, null, tint = RRCream.op(0.75), modifier = Modifier.size(15.dp))
                    val f = timeLeft / timeLimit
                    TimeBar(f, Modifier.weight(1f).height(6.dp), fill = if (f < 0.3) rgb(1.0, 0.32, 0.28) else RRSand)
                }
            }
        }
        Canvas(Modifier.fillMaxWidth().weight(1f).then(if (isDemo) Modifier else Modifier.tapIn(boardN) { p, w, h ->
            val g = RRGeo(w, h, boardN)
            val half = g.cell * 0.39
            robots.indices.firstOrNull { i ->
                val cx = g.ox + (robots[i] % boardN + 0.5) * g.cell; val cy = g.oy + (robots[i] / boardN + 0.5) * g.cell
                p.x >= cx - half && p.x <= cx + half && p.y >= cy - half && p.y <= cy + half
            }?.let { select(it) }
        })) {
            tick
            val n = boardN
            if (n == 0) return@Canvas
            val g = RRGeo(size.width.toDouble(), size.height.toDouble(), n)
            board(g, n, walls, targetCell)
            val k = clamp((nowSec() - anim.t0) / anim.dur, 0.0, 1.0)
            val e = 1 - (1 - k) * (1 - k)
            fun pos(i: Int): P {
                val to = robots[i]; val from = anim.from.getOrElse(i) { to }
                val fx = (from % n + 0.5); val fy = (from / n + 0.5); val tx = (to % n + 0.5); val ty = (to / n + 0.5)
                return P(g.ox + (fx + (tx - fx) * e) * g.cell, g.oy + (fy + (ty - fy) * e) * g.cell)
            }
            for (i in robots.indices) {
                val p = pos(i)
                val col = if (i == 0) RRBanana else blockerColors[(i - 1) % blockerColors.size]
                robot(p.x, p.y, g.cell * 0.78 * (if (selected == i) 1.06 else 1.0), col, selected == i, i == 0)
            }
            demoFinger?.let { f ->
                if (f < robots.size) {
                    val s = g.cell * 0.5
                    val p = pos(f)
                    hand(handP, p.x + g.cell * 0.3 - s / 2, p.y + g.cell * 0.38 - s / 2, s)
                }
            }
        }
        Column(Modifier.padding(bottom = if (isDemo) 2.dp else 6.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(if (isDemo) 4.dp else 8.dp)) {
            val kw = if (isDemo) 50.dp else 66.dp; val kh = if (isDemo) 32.dp else 50.dp; val ic = if (isDemo) 22.dp else 28.dp
            RRKeyButton(Icons.Filled.KeyboardArrowUp, kw, kh, 14.0, isDemo && demoKey == "up", isDemo, ic) { move(0) }
            Row(horizontalArrangement = Arrangement.spacedBy(if (isDemo) 4.dp else 8.dp)) {
                RRKeyButton(Icons.Filled.KeyboardArrowLeft, kw, kh, 14.0, isDemo && demoKey == "left", isDemo, ic) { move(3) }
                RRKeyButton(Icons.Filled.KeyboardArrowDown, kw, kh, 14.0, isDemo && demoKey == "down", isDemo, ic) { move(2) }
                RRKeyButton(Icons.Filled.KeyboardArrowRight, kw, kh, 14.0, isDemo && demoKey == "right", isDemo, ic) { move(1) }
            }
        }
    }
}

/** Keys: slate, banana yellow while pressed. */
@Composable
private fun RRKeyButton(icon: ImageVector, w: Dp, h: Dp, radius: Double, demoLit: Boolean, isDemo: Boolean, iconSize: Dp, onPress: () -> Unit) {
    var held by remember { mutableStateOf(false) }
    val lit = demoLit || held
    Box(
        Modifier.scale(if (lit) 0.9f else 1f).size(w, h)
            .then(if (isDemo) Modifier else Modifier.pressDown(onDown = { held = true; onPress() }, onUp = { held = false })),
        contentAlignment = Alignment.Center
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val u = density.toDouble(); val bw = size.width.toDouble(); val bh = size.height.toDouble(); val r = radius * u
            val cols = if (lit) listOf(rgb(1.0, 0.9, 0.45), rgb(0.95, 0.72, 0.16)) else listOf(rgb(0.32, 0.36, 0.48), rgb(0.18, 0.21, 0.3))
            rrect(0.0, 0.0, bw, bh, r, vgrad(cols, 0.0, bh))
            rrectStroke(u, u, bw - 2 * u, bh - 2 * u, r - u, Color.Black.op(0.5), 2 * u)
            rrectStroke(3.6 * u, 3.6 * u, bw - 7.2 * u, bh - 7.2 * u, r - 3.6 * u, Color.White.op(if (lit) 0.9 else 0.16), 1.2 * u)
        }
        Icon(icon, null, tint = if (lit) RRInk else Color.White, modifier = Modifier.size(iconSize))
    }
}

// Board-game art (after Alex Randolph's Ricochet Robots; iOS RRArt).

private val RRBanana = rgb(1.0, 0.84, 0.2)
private val RRCream = rgb(0.96, 0.94, 0.86)
private val RRSand = rgb(0.96, 0.8, 0.46)
private val RRInk = rgb(0.14, 0.1, 0.02)

/** The yellow ringed-planet target chip. */
private fun DrawScope.planet(cx: Double, cy: Double, cell: Double) {
    val r = cell * 0.2
    val ringCol = rgb(0.86, 0.55, 0.08)
    val lw = max(1.5 * density, cell * 0.05)
    fun ring(a0: Double, a1: Double): Path {
        val p = Path(); val rot = -0.35
        for (s in 0..24) {
            val a = a0 + (a1 - a0) * s / 24
            val ex = cos(a) * r * 1.9; val ey = sin(a) * r * 0.62
            val x = cx + ex * cos(rot) - ey * sin(rot); val y = cy + ex * sin(rot) + ey * cos(rot)
            if (s == 0) p.m(x, y) else p.l(x, y)
        }
        return p
    }
    strokePath(ring(PI, 2 * PI), ringCol, lw)
    circle(cx, cy, r, radial(listOf(rgb(1.0, 0.95, 0.55), RRBanana, rgb(0.9, 0.62, 0.1)), cx - r * 0.35, cy - r * 0.4, r * 1.4))
    circleStroke(cx, cy, r, ringCol.mix(Color.Black, 0.3), max(density.toDouble(), cell * 0.025))
    strokePath(ring(0.0, PI), ringCol, lw)
}

/** Ivory bevelled squares, black walls with rounded ends, a dark frame, and the target square. */
private fun DrawScope.board(g: RRGeo, n: Int, walls: Set<Int>, target: Int) {
    val u = density.toDouble(); val cell = g.cell; val ox = g.ox; val oy = g.oy; val side = g.side
    rrect(ox - 5 * u, oy - 5 * u, side + 10 * u, side + 10 * u, 7 * u, rgb(0.12, 0.12, 0.16))
    rect(ox, oy, side, side, rgb(0.62, 0.61, 0.58))
    val squares = Path(); val bevels = Path()
    val gap = 0.6 * u
    for (r in 0 until n) for (c in 0 until n) {
        val x = ox + c * cell + gap; val y = oy + r * cell + gap; val s = cell - 2 * gap
        squares.addRect(androidx.compose.ui.geometry.Rect(x.f, y.f, (x + s).f, (y + s).f))
        bevels.addRect(androidx.compose.ui.geometry.Rect((x + cell * 0.12).f, (y + cell * 0.12).f, (x + s - cell * 0.12).f, (y + s - cell * 0.12).f))
    }
    fillPath(squares, rgb(0.89, 0.88, 0.84))
    drawPath(bevels, rgb(0.76, 0.75, 0.71), style = Stroke(max(u, cell * 0.025).f))
    // Target square.
    val tx = ox + (target % n) * cell + gap; val ty = oy + (target / n) * cell + gap; val ts = cell - 2 * gap
    rect(tx, ty, ts, ts, rgb(1.0, 0.95, 0.72))
    rectStroke(tx + cell * 0.06, ty + cell * 0.06, ts - cell * 0.12, ts - cell * 0.12, RRBanana, max(1.5 * u, cell * 0.045))
    planet(tx + ts / 2, ty + ts / 2, cell)
    // Walls.
    val segs = Path(); val ext = cell * 0.05
    for (enc in walls) {
        val dir = enc % 4; val idx = enc / 4
        val x0 = ox + (idx % n) * cell; val y0 = oy + (idx / n) * cell
        when (dir) {
            0 -> { segs.m(x0 - ext, y0); segs.l(x0 + cell + ext, y0) }
            1 -> { segs.m(x0 + cell, y0 - ext); segs.l(x0 + cell, y0 + cell + ext) }
            2 -> { segs.m(x0 - ext, y0 + cell); segs.l(x0 + cell + ext, y0 + cell) }
            else -> { segs.m(x0, y0 - ext); segs.l(x0, y0 + cell + ext) }
        }
    }
    val wallCol = rgb(0.1, 0.09, 0.12)
    strokePath(segs, wallCol, cell * 0.11)
    strokePath(segs, Color.White.op(0.12), cell * 0.03)
    rectStroke(ox, oy, side, side, wallCol, cell * 0.09)
}

/** A robot piece: glossy body, dome head with a visor and lit eyes, an antenna (a stem for the banana). */
private fun DrawScope.robot(cx: Double, cy: Double, s: Double, color: Color, selected: Boolean, banana: Boolean) {
    val u = density.toDouble()
    if (selected) {
        circle(cx, cy, s * 0.52, Brush.radialGradient(0f to Color.Transparent, (0.3 / 0.52).toFloat() to color.op(0.55), 1f to color.op(0.0),
            center = Offset(cx.f, cy.f), radius = (s * 0.52).f))
        circleStroke(cx, cy, s * 0.47, Color.White, max(1.5 * u, s * 0.06))
    }
    val ink = rgb(0.08, 0.08, 0.1)
    val lw = max(u, s * 0.035)
    oval(cx - s * 0.36, cy + s * 0.22, s * 0.72, s * 0.2, Color.Black.op(0.3))
    rrect(cx - s * 0.3, cy - s * 0.06, s * 0.6, s * 0.38, s * 0.14, hgrad(listOf(color.mix(Color.White, 0.25), color, color.mix(Color.Black, 0.35)), cx - s * 0.3, cx + s * 0.3))
    rrectStroke(cx - s * 0.3, cy - s * 0.06, s * 0.6, s * 0.38, s * 0.14, ink, lw)
    drawOval(radial(listOf(color.mix(Color.White, 0.45), color, color.mix(Color.Black, 0.3)), cx - s * 0.08, cy - s * 0.3, s * 0.36),
        Offset((cx - s * 0.26).f, (cy - s * 0.4).f), androidx.compose.ui.geometry.Size((s * 0.52).f, (s * 0.44).f))
    drawOval(ink, Offset((cx - s * 0.26).f, (cy - s * 0.4).f), androidx.compose.ui.geometry.Size((s * 0.52).f, (s * 0.44).f), style = Stroke(lw.f))
    rrect(cx - s * 0.2, cy - s * 0.24, s * 0.4, s * 0.13, s * 0.065, rgb(0.1, 0.12, 0.16))
    for (dx in listOf(-0.09, 0.09)) oval(cx + dx * s - s * 0.04, cy - s * 0.215, s * 0.08, s * 0.075, rgb(0.6, 0.95, 1.0))
    if (banana) {
        val stem = Path(); stem.m(cx + s * 0.02, cy - s * 0.38); stem.q(cx + s * 0.02, cy - s * 0.48, cx + s * 0.12, cy - s * 0.5)
        strokePath(stem, rgb(0.45, 0.3, 0.1), max(1.5 * u, s * 0.07))
    } else {
        line(cx, cy - s * 0.39, cx, cy - s * 0.48, ink, lw, StrokeCap.Butt)
        circle(cx, cy - s * 0.485, s * 0.045, color.mix(Color.White, 0.3))
    }
    // Wheels peeking out below.
    for (dx in listOf(-0.2, 0.2)) rrect(cx + dx * s - s * 0.08, cy + s * 0.28, s * 0.16, s * 0.08, s * 0.03, gray(0.18))
}

/** The table under the board: dark blue felt. */
private fun DrawScope.table() {
    val u = density.toDouble(); val w = size.width.toDouble(); val h = size.height.toDouble()
    val outer = max(w, h) * 0.75; val inner = 20 * u
    rect(0.0, 0.0, w, h, Brush.radialGradient(0f to rgb(0.13, 0.17, 0.3), (inner / outer).toFloat() to rgb(0.13, 0.17, 0.3), 1f to rgb(0.05, 0.07, 0.14),
        center = Offset((w / 2).f, (h * 0.4).f), radius = outer.f))
    val weave = Path(); var y = 0.0
    while (y < h) { weave.m(0.0, y); weave.l(w, y); y += 3 * u }
    strokePath(weave, Color.White.op(0.025), u, StrokeCap.Butt)
}
