package com.gogs.bananagame.games.mirrormaze

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
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.Icon
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
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/**
 * Brain — Mirror Maze (iOS MirrorMazeGame.swift, id "mirror-maze"): wall emitters fire deadly beams
 * that reflect off mirrors. Tap a mirror to turn it 15°, carve a lane, and d-pad the banana to the
 * exit; touch a beam and it's back to level 1. Boards are generated with a beam-free route that the
 * start configuration blocks. Drawn after Deflektor's optics lab.
 */
object MirrorMazeGame {
    val definition = GameDefinition(
        id = "mirror-maze",
        title = "Mirror Maze",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Deadly laser beams fire from the walls and reflect off the mirrors.",
                "Tap a mirror to rotate it 15° and bend the beams away from your path.",
                "You start hemmed in, so re-aim the beams to open a lane.",
                "Steer with the d-pad to the exit; touch a beam and you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Những tia laser chết người bắn ra từ tường và phản chiếu qua các gương.",
                "Chạm một gương để xoay nó 15° và bẻ các tia ra khỏi lối đi của bạn.",
                "Bạn bắt đầu bị vây kín, nên phải chỉnh lại các tia để mở một lối.",
                "Điều khiển bằng d-pad để đến lối ra; chạm một tia là bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        prefetch = { level -> BoardCache.prefetch(key(level)) { gen(level) } },
        content = { level, onWin, onFail -> MirrorMazeView(level, onWin, onFail) }
    )

    fun key(level: Int) = BoardCache.key("mirror-maze", level)
    fun gen(level: Int): MMBoard {
        val i = min(level, 7) - 1
        return MMGen.generate(listOf(3, 4, 5, 6, 7, 8, 9)[i], listOf(3, 4, 5, 6, 7, 8, 9)[i], listOf(0, 1, 1, 2, 2, 3, 3)[i])
    }
}

private const val COLS = 11
private const val ROWS = 15
private const val STEPS = 12                 // 12 orientations, 15° apart
private const val PLAYER_SPEED = 3.4

/** Cells are indices r * COLS + c. */
class MMSource(val cell: Int, val dx: Int, val dy: Int)
class MMBoard(val walls: BooleanArray, val sources: List<MMSource>, val mirrors: List<Int>, val orient: Map<Int, Int>, val start: Int, val exit: Int)

object MMGen {
    private fun wallAt(walls: BooleanArray, r: Int, c: Int) = r !in 0 until ROWS || c !in 0 until COLS || walls[r * COLS + c]
    private fun manhattan(a: Int, b: Int) = abs(a / COLS - b / COLS) + abs(a % COLS - b % COLS)

    /**
     * Ray-trace every source, reflecting off tilted mirrors, until it hits a wall (or a travel cap
     * breaks a loop). Returns the deadly cells and, when [polys] is given, the drawable polylines.
     */
    fun trace(config: Map<Int, Int>, walls: BooleanArray, sources: List<MMSource>, stepLen: Double, cap: Double,
              polys: MutableList<List<P>>? = null): BooleanArray {
        val cells = BooleanArray(ROWS * COLS)
        for (s in sources) {
            // Launch from the first interior cell (the emitter sits on the border wall).
            val inC = s.cell % COLS + s.dx; val inR = s.cell / COLS + s.dy
            var px = inC + 0.5; var py = inR + 0.5
            var dx = s.dx.toDouble(); var dy = s.dy.toDouble()
            val poly = if (polys != null) mutableListOf(P(s.cell % COLS + 0.5, s.cell / COLS + 0.5), P(px, py)) else null
            cells[inR * COLS + inC] = true
            var lastMirror = -1
            var travel = 0.0
            while (travel < cap) {
                val nx = px + dx * stepLen; val ny = py + dy * stepLen
                if (wallAt(walls, floor(ny).toInt(), floor(nx).toInt())) { poly?.add(P(nx, ny)); break }
                px = nx; py = ny
                travel += stepLen
                val mc = floor(py).toInt() * COLS + floor(px).toInt()
                cells[mc] = true
                if (lastMirror >= 0 && hypot(px - (lastMirror % COLS + 0.5), py - (lastMirror / COLS + 0.5)) > 0.55) lastMirror = -1
                val idx = config[mc]
                if (idx != null && mc != lastMirror) {
                    val cx = mc % COLS + 0.5; val cy = mc / COLS + 0.5
                    if (hypot(px - cx, py - cy) < 0.3) {
                        poly?.add(P(cx, cy))
                        val phi = idx * 15.0 * PI / 180.0
                        val ux = cos(phi); val uy = sin(phi)
                        val dot = dx * ux + dy * uy
                        val ndx = 2 * dot * ux - dx; val ndy = 2 * dot * uy - dy
                        dx = ndx; dy = ndy
                        lastMirror = mc
                        px = cx + dx * 0.32; py = cy + dy * 0.32
                        travel += 0.32
                    }
                }
            }
            if (poly != null) { poly.add(P(px, py)); polys!!.add(poly) }
        }
        return cells
    }

    /** Fast cell-only trace (coarser step) used by the generator. */
    private fun beamCells(config: Map<Int, Int>, walls: BooleanArray, sources: List<MMSource>) = trace(config, walls, sources, 0.12, 45.0)

    fun pathExists(start: Int, exit: Int, beam: BooleanArray, walls: BooleanArray): Boolean {
        val seen = BooleanArray(ROWS * COLS); seen[start] = true
        val q = IntArray(ROWS * COLS); var head = 0; var tail = 0; q[tail++] = start
        while (head < tail) {
            val cur = q[head++]
            if (cur == exit) return true
            val r = cur / COLS; val c = cur % COLS
            for ((nr, nc) in listOf(r - 1 to c, r + 1 to c, r to c - 1, r to c + 1)) {
                if (wallAt(walls, nr, nc)) continue
                val n = nr * COLS + nc
                if (seen[n] || beam[n]) continue
                seen[n] = true; q[tail++] = n
            }
        }
        return false
    }

    private fun border(): BooleanArray {
        val w = BooleanArray(ROWS * COLS)
        for (r in 0 until ROWS) { w[r * COLS] = true; w[r * COLS + COLS - 1] = true }
        for (c in 0 until COLS) { w[c] = true; w[(ROWS - 1) * COLS + c] = true }
        return w
    }

    /**
     * Try layouts with a directed orientation search; if a whole density can't be solved, shed one
     * emitter (then mirror) and retry — never collapsing to an easy board.
     */
    fun generate(sourceCount: Int, mirrorCount: Int, coverBlocks: Int): MMBoard {
        var sc = sourceCount; var mc = mirrorCount
        while (true) {
            repeat(40) { tryBuild(sc, mc, coverBlocks, false)?.let { return it } }
            repeat(40) { tryBuild(sc, mc, coverBlocks, true)?.let { return it } }
            if (sc > 2) sc-- else if (mc > 2) mc-- else return shieldedFallback(sc, mc)
        }
    }

    /** A wall-enclosed L-corridor stays beam-free however the mirrors turn (only if all else fails). */
    private fun shieldedFallback(sourceCount: Int, mirrorCount: Int): MMBoard {
        val w = border()
        for (c in 1..(COLS - 3)) w[2 * COLS + c] = true
        for (r in 3..(ROWS - 2)) w[r * COLS + COLS - 3] = true
        val srcs = ArrayList<MMSource>(); var col = 1
        repeat(sourceCount) {
            if (col <= COLS - 4) { srcs.add(MMSource((ROWS - 1) * COLS + col, 0, -1)); col++ }
            else srcs.add(MMSource(rndInt(3..(ROWS - 2)) * COLS, 1, 0))
        }
        val open = ArrayList<Int>()
        for (r in 3..(ROWS - 2)) for (c in 1..(COLS - 4)) if (!w[r * COLS + c]) open.add(r * COLS + c)
        val ms = open.shuffled().take(mirrorCount)
        return MMBoard(w, srcs, ms, ms.associateWith { Random.nextInt(STEPS) }, COLS + 1, (ROWS - 2) * COLS + COLS - 2)
    }

    private fun tryBuild(sourceCount: Int, mirrorCount: Int, coverBlocks: Int, relax: Boolean): MMBoard? {
        val w = border()
        var placed = 0; var tries = 0
        while (placed < coverBlocks && tries < 120) {
            tries++
            val c0 = rndInt(2..(COLS - 3)); val r0 = rndInt(3..(ROWS - 4))
            if (w[r0 * COLS + c0]) continue
            w[r0 * COLS + c0] = true; placed++
        }
        val start = COLS + 1
        val exit = (ROWS - 2) * COLS + COLS - 2
        if (w[start] || w[exit]) return null
        // Emitters on the border, pointing inward at open cells.
        val srcs = ArrayList<MMSource>(); var st = 0
        while (srcs.size < sourceCount && st < 400) {
            st++
            val s = when (Random.nextInt(4)) {
                0 -> MMSource(rndInt(2..(COLS - 3)), 0, 1)
                1 -> MMSource((ROWS - 1) * COLS + rndInt(2..(COLS - 3)), 0, -1)
                2 -> MMSource(rndInt(3..(ROWS - 4)) * COLS, 1, 0)
                else -> MMSource(rndInt(3..(ROWS - 4)) * COLS + COLS - 1, -1, 0)
            }
            if (w[s.cell + s.dy * COLS + s.dx]) continue
            if (srcs.any { manhattan(it.cell, s.cell) < (if (relax) 1 else 2) }) continue
            srcs.add(s)
        }
        if (srcs.size < sourceCount) return null
        // Mirrors on interior open cells (not start/exit), spaced.
        val ms = ArrayList<Int>()
        val openCells = ArrayList<Int>()
        for (r in 2 until ROWS - 2) for (c in 2 until COLS - 2) if (!w[r * COLS + c]) openCells.add(r * COLS + c)
        for (cand in openCells.shuffled()) {
            if (cand == start || cand == exit) continue
            if (ms.all { manhattan(it, cand) >= (if (relax) 1 else 2) }) { ms.add(cand); if (ms.size == mirrorCount) break }
        }
        if (ms.size < mirrorCount) return null
        // A SOLVED config must exist: minimize danger on start/exit and keep a route open.
        val solved = greedyConfig(ms, w, srcs) { cells ->
            var s = cells.count { it }
            if (cells[exit]) s += 5000
            if (cells[start]) s += 5000
            if (!pathExists(start, exit, cells, w)) s += 5000
            s
        }
        val solvedCells = beamCells(solved, w, srcs)
        if (solvedCells[exit] || solvedCells[start] || !pathExists(start, exit, solvedCells, w)) return null
        // The START config should be HARD: safe on spawn, the direct path closed, busy with beams.
        val blocked = greedyConfig(ms, w, srcs) { cells ->
            var s = 0
            if (cells[start]) s += 5000
            if (pathExists(start, exit, cells, w)) s += 800
            s - cells.count { it }
        }
        val bc = beamCells(blocked, w, srcs)
        val startConfig = if (!bc[start] && !pathExists(start, exit, bc, w)) blocked else solved
        return MMBoard(w, srcs, ms, startConfig, start, exit)
    }

    /** Seed random orientations, then repeatedly re-pick each mirror's step to minimize `cost`. */
    private fun greedyConfig(mirrors: List<Int>, walls: BooleanArray, sources: List<MMSource>, cost: (BooleanArray) -> Int): Map<Int, Int> {
        val cfg = HashMap<Int, Int>()
        for (m in mirrors) cfg[m] = Random.nextInt(STEPS)
        repeat(3) {
            for (m in mirrors) {
                var bestO = cfg[m] ?: 0; var bestC = Int.MAX_VALUE
                for (o in 0 until STEPS) {
                    cfg[m] = o
                    val c = cost(beamCells(cfg, walls, sources))
                    if (c < bestC) { bestC = c; bestO = o }
                }
                cfg[m] = bestO
            }
        }
        return cfg
    }
}

private class MirrorWorld(val level: Int) {
    val timeLimit = listOf(42.0, 40.0, 38.0, 36.0, 34.0, 32.0, 30.0)[min(level, 7) - 1]
    var playing = true
    var walls = BooleanArray(ROWS * COLS)
    var mapVersion by mutableIntStateOf(0)
    var sources = listOf<MMSource>()
    var mirrors = listOf<Int>()
    val orient = HashMap<Int, Int>()
    var beam = BooleanArray(ROWS * COLS)
    var polys = listOf<List<P>>()
    var px = 1.5; var py = 1.5
    var exit = (ROWS - 2) * COLS + COLS - 2
    // Snapshot state, so the keys re-light when the demo script (or a finger) changes them.
    var mdx by mutableDoubleStateOf(0.0)
    var mdy by mutableDoubleStateOf(0.0)
    var timeLeft = timeLimit
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    fun commit(b: MMBoard) {
        walls = b.walls; mapVersion++
        sources = b.sources; mirrors = b.mirrors
        orient.clear(); orient.putAll(b.orient)
        exit = b.exit
        px = b.start % COLS + 0.5; py = b.start / COLS + 0.5
        mdx = 0.0; mdy = 0.0; timeLeft = timeLimit; playing = true
        updateBeam()
    }

    fun updateBeam() {
        val ps = mutableListOf<List<P>>()
        beam = MMGen.trace(orient, walls, sources, 0.07, 60.0, ps)
        polys = ps
    }

    /** Tap a mirror: turn it one 15° step and re-trace every beam. */
    fun rotateMirror(cell: Int) {
        if (!playing) return
        val o = orient[cell] ?: return
        orient[cell] = (o + 1) % STEPS
        updateBeam()
        SoundManager.tap(); Haptics.tap()
    }

    private fun isWall(r: Int, c: Int) = r !in 0 until ROWS || c !in 0 until COLS || walls[r * COLS + c]
    private fun canStand(x: Double, y: Double): Boolean {
        val rad = 0.26
        for (cx in listOf(x - rad, x + rad)) for (cy in listOf(y - rad, y + rad)) if (isWall(floor(cy).toInt(), floor(cx).toInt())) return false
        return true
    }

    fun step(dt: Double) {
        if (!playing) return
        val vx = mdx * PLAYER_SPEED * dt; val vy = mdy * PLAYER_SPEED * dt
        if (canStand(px + vx, py)) px += vx
        if (canStand(px, py + vy)) py += vy
        if (beam[floor(py).toInt() * COLS + floor(px).toInt()]) { fail(); return }
        if (hypot(px - (exit % COLS + 0.5), py - (exit / COLS + 0.5)) < 0.5) { win(); return }
        timeLeft -= dt
        if (timeLeft <= 0) { timeLeft = 0.0; fail() }
    }

    fun win() { if (!playing) return; playing = false; Haptics.success(); SoundManager.tap(); onWin() }
    fun fail() { if (!playing) return; playing = false; Haptics.warning(); SoundManager.error(); onFail() }
}

// Demo: an open 11×15 room with three wall emitters and three mirrors, boxed in at the start. One tap
// on the middle mirror and two on the bottom-left one swing the beams clear, then ▼ and ► to the exit.
private fun demoBoard(): MMBoard {
    val w = BooleanArray(ROWS * COLS)
    for (r in 0 until ROWS) { w[r * COLS] = true; w[r * COLS + COLS - 1] = true }
    for (c in 0 until COLS) { w[c] = true; w[(ROWS - 1) * COLS + c] = true }
    val srcs = listOf(MMSource(9 * COLS + 10, -1, 0), MMSource(11 * COLS + 10, -1, 0), MMSource(7, 0, 1))
    val orient = mapOf(9 * COLS + 7 to 1, 2 * COLS + 6 to 1, 11 * COLS + 2 to 2)
    return MMBoard(w, srcs, listOf(9 * COLS + 7, 2 * COLS + 6, 11 * COLS + 2), orient, COLS + 1, (ROWS - 2) * COLS + COLS - 2)
}
private val demoTaps = listOf(9 * COLS + 7, 11 * COLS + 2, 11 * COLS + 2)

private class MGeo(w: Double, h: Double) {
    val cell = min(w / COLS, h / ROWS)
    val ox = (w - cell * COLS) / 2
    val oy = (h - cell * ROWS) / 2
}

@Composable
private fun MirrorMazeView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { MirrorWorld(level) }
    world.onWin = onWin; world.onFail = onFail
    var ready by remember { mutableStateOf(false) }
    var demoTick by remember { mutableIntStateOf(0) }
    var demoFinger by remember { mutableStateOf<Int?>(null) }
    var demoTapAt by remember { mutableStateOf(-10.0) }
    val handP = rememberHand()
    val tick by rememberFrameLoop(running = ready) { dt -> if (!isDemo) world.step(dt) }

    LaunchedEffect(Unit) {
        if (isDemo) {
            val dt = 1.0 / 60.0
            while (isActive) {
                world.commit(demoBoard()); demoFinger = null; ready = true
                delay(1000)                                             // show the boxed-in start
                for (m in demoTaps) { demoFinger = m; delay(300); demoTapAt = nowSec(); world.rotateMirror(m); delay(450) }
                demoFinger = null
                delay(300)
                var frame = 0
                val exitY = world.exit / COLS + 0.5
                while (isActive && world.playing && frame < 900) {
                    frame++
                    if (world.py < exitY) { world.mdx = 0.0; world.mdy = 1.0 }         // ▼ down the cleared column
                    else { world.py = exitY; world.mdx = 1.0; world.mdy = 0.0 }       // ► along the bottom row
                    world.step(dt)
                    demoTick++
                    delay(16)
                }
                world.mdx = 0.0; world.mdy = 0.0
                delay(1300)
            }
        } else {
            val t0 = System.currentTimeMillis()
            val b = BoardCache.take(MirrorMazeGame.key(level)) { MirrorMazeGame.gen(level) }
            BoardCache.holdBrainstorm(t0, 1.0)
            world.commit(b); ready = true
        }
    }

    if (!ready) { BrainstormingView(gray(0.11), gray(0.04)); return }

    val tint = tint(level)
    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .background(Brush.verticalGradient(listOf(tint.mix(Color.Black, 0.55), tint.mix(Color.Black, 0.82)))),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(if (isDemo) 4.dp else 8.dp)
    ) {
        tick; demoTick
        if (!isDemo) {
            val f = world.timeLeft / world.timeLimit
            TimeBar(f, Modifier.fillMaxWidth().padding(horizontal = 50.dp).padding(top = 4.dp).height(5.dp),
                fill = if (f < 0.3) rgb(1.0, 0.3, 0.28) else rgb(0.55, 0.9, 1.0))
        }
        Canvas(
            Modifier.fillMaxWidth().weight(1f).padding(horizontal = if (isDemo) 12.dp else 4.dp).padding(top = if (isDemo) 8.dp else 0.dp)
                .clip(RoundedCornerShape(16.dp))
                .drawWithCache {
                    // Floor tiles, steel walls and the exit pad never change during a level: rendered once.
                    world.mapVersion
                    val bmp = ImageBitmap(size.width.toInt().coerceAtLeast(1), size.height.toInt().coerceAtLeast(1))
                    CanvasDrawScope().draw(this, layoutDirection, androidx.compose.ui.graphics.Canvas(bmp), size) { room(world.walls, world.exit, level) }
                    onDrawBehind { drawImage(bmp) }
                }
                .then(if (isDemo) Modifier else Modifier.tapIn { p, w, h ->
                    val g = MGeo(w, h)
                    val c = floor((p.x - g.ox) / g.cell).toInt(); val r = floor((p.y - g.oy) / g.cell).toInt()
                    if (r in 0 until ROWS && c in 0 until COLS) world.rotateMirror(r * COLS + c)
                })
        ) {
            tick; demoTick
            val g = MGeo(size.width.toDouble(), size.height.toDouble())
            fun x(v: Double) = g.ox + v * g.cell
            fun y(v: Double) = g.oy + v * g.cell
            beams(world.polys.map { poly -> poly.map { P(x(it.x), y(it.y)) } }, g.cell)
            for (m in world.mirrors) mirror(x(m % COLS + 0.5), y(m / COLS + 0.5), g.cell, (world.orient[m] ?: 0) * 15.0)
            for (s in world.sources) emitter(x(s.cell % COLS + 0.5), y(s.cell / COLS + 0.5), g.cell, s.dx, s.dy)
            banana(x(world.px), y(world.py), g.cell)
            demoFinger?.let { m ->
                val cx = x(m % COLS + 0.5); val cy = y(m / COLS + 0.5)
                tapRipple(cx, cy, nowSec() - demoTapAt)
                val s = g.cell * 1.3
                hand(handP, x(m % COLS + 1.05) - s / 2, y(m / COLS + 1.25) - s / 2, s)
            }
        }
        val kw = if (isDemo) 56.dp else 74.dp; val kh = if (isDemo) 30.dp else 52.dp
        @Composable fun key(dx: Double, dy: Double, icon: ImageVector) = MMKey(world, dx, dy, icon, isDemo, kw, kh)
        if (isDemo) {
            // The squat demo card can't spare a 3-row cross: same four buttons, one row.
            Row(Modifier.padding(bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                key(-1.0, 0.0, Icons.Filled.KeyboardArrowLeft); key(0.0, -1.0, Icons.Filled.KeyboardArrowUp)
                key(0.0, 1.0, Icons.Filled.KeyboardArrowDown); key(1.0, 0.0, Icons.Filled.KeyboardArrowRight)
            }
        } else {
            Column(Modifier.padding(bottom = 6.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                key(0.0, -1.0, Icons.Filled.KeyboardArrowUp)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { key(-1.0, 0.0, Icons.Filled.KeyboardArrowLeft); key(1.0, 0.0, Icons.Filled.KeyboardArrowRight) }
                key(0.0, 1.0, Icons.Filled.KeyboardArrowDown)
            }
        }
    }
}

/** Steel d-pad keys (banana yellow while held). */
@Composable
private fun MMKey(world: MirrorWorld, dx: Double, dy: Double, icon: ImageVector, isDemo: Boolean, w: Dp, h: Dp) {
    val lit = isDemo && world.mdx == dx && world.mdy == dy      // as on iOS, only the demo's presses light up
    val radius = if (isDemo) 9.0 else 14.0
    Box(
        Modifier.scale(if (lit) 0.92f else 1f).size(w, h)
            .then(if (isDemo) Modifier else Modifier.pressDown(
                onDown = { if (world.playing) { world.mdx = dx; world.mdy = dy } },
                onUp = { if (world.mdx == dx && world.mdy == dy) { world.mdx = 0.0; world.mdy = 0.0 } })),
        contentAlignment = Alignment.Center
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val u = density.toDouble(); val bw = size.width.toDouble(); val bh = size.height.toDouble(); val r = radius * u
            rrect(0.0, 0.0, bw, bh, r, vgrad(if (lit) listOf(rgb(1.0, 0.9, 0.45), rgb(0.95, 0.72, 0.16)) else listOf(gray(0.36), gray(0.18)), 0.0, bh))
            rrectStroke(u, u, bw - 2 * u, bh - 2 * u, r - u, Color.Black.op(0.55), 2 * u)
            rrectStroke(3.5 * u, 3.5 * u, bw - 7 * u, bh - 7 * u, r - 3.5 * u, Color.White.op(if (lit) 0.9 else 0.2), u)
        }
        Icon(icon, null, tint = if (lit) rgb(0.2, 0.12, 0.0) else Color.White, modifier = Modifier.size(if (isDemo) 20.dp else 28.dp))
    }
}

// Optics-lab art (after Deflektor; iOS MMArt).

/** Lab tint per level: cool blue, then violet, then an alarm-red room at 6–7. */
private fun tint(level: Int) = if (level >= 6) rgb(0.36, 0.14, 0.16) else if (level >= 4) rgb(0.26, 0.18, 0.4) else rgb(0.14, 0.24, 0.38)

/** The deadly beams: a red glow and a white-hot core along the traced polylines. */
private fun DrawScope.beams(polys: List<List<P>>, cell: Double) {
    val all = Path()
    for (poly in polys) { if (poly.isEmpty()) continue; all.m(poly[0].x, poly[0].y); for (q in poly.drop(1)) all.l(q.x, q.y) }
    val red = rgb(1.0, 0.22, 0.24)
    strokePath(all, red.op(0.22), cell * 0.5)
    strokePath(all, red, cell * 0.16)
    strokePath(all, rgb(1.0, 0.85, 0.85), max(density.toDouble(), cell * 0.05))
}

/** A mirror on its pivot disc, the silver bar at the mirror's angle. */
private fun DrawScope.mirror(px: Double, py: Double, cell: Double, degrees: Double) {
    val r = cell * 0.44
    circle(px, py, r, radial(listOf(rgb(0.36, 0.4, 0.48), rgb(0.16, 0.18, 0.24)), px - r * 0.3, py - r * 0.3, r * 1.2))
    circleStroke(px, py, r, rgb(0.55, 0.85, 1.0, 0.7), max(density.toDouble(), cell * 0.04))
    val ticks = Path()
    for (k in 0 until 12) {
        val a = k / 12.0 * 2 * PI
        ticks.m(px + cos(a) * r * 0.82, py + sin(a) * r * 0.82); ticks.l(px + cos(a) * r * 0.95, py + sin(a) * r * 0.95)
    }
    strokePath(ticks, Color.White.op(0.25), density.toDouble(), StrokeCap.Butt)
    translate(px.f, py.f) { rotate(degrees.f, Offset.Zero) {
        rrect(-cell * 0.43, -cell * 0.08, cell * 0.86, cell * 0.16, cell * 0.04, vgrad(listOf(Color.White, rgb(0.72, 0.86, 0.95), rgb(0.5, 0.6, 0.7)), -cell * 0.08, cell * 0.08))
        rrectStroke(-cell * 0.43, -cell * 0.08, cell * 0.86, cell * 0.16, cell * 0.04, rgb(0.1, 0.12, 0.16), max(density.toDouble(), cell * 0.03))
        circle(0.0, 0.0, cell * 0.06, rgb(0.2, 0.22, 0.28))
    } }
}

/** A laser cannon in the wall, its barrel and red lens pointing into the room. */
private fun DrawScope.emitter(px: Double, py: Double, cell: Double, dx: Int, dy: Int) {
    translate(px.f, py.f) { rotateRad(atan2(dy.toDouble(), dx.toDouble()).f, Offset.Zero) {
        rrect(-cell * 0.4, -cell * 0.36, cell * 0.6, cell * 0.72, cell * 0.1, vgrad(listOf(rgb(0.5, 0.52, 0.58), rgb(0.24, 0.25, 0.3)), -cell * 0.36, cell * 0.36))
        rrectStroke(-cell * 0.4, -cell * 0.36, cell * 0.6, cell * 0.72, cell * 0.1, Color.Black.op(0.6), density.toDouble())
        rrect(cell * 0.12, -cell * 0.16, cell * 0.36, cell * 0.32, cell * 0.06, rgb(0.18, 0.18, 0.22))
        val lx = cell * 0.46
        circle(lx, 0.0, cell * 0.3, radial(listOf(rgb(1.0, 0.3, 0.3, 0.7), rgb(1.0, 0.2, 0.2, 0.0)), lx, 0.0, cell * 0.3))
        circle(lx, 0.0, cell * 0.1, rgb(1.0, 0.5, 0.5))
    } }
}

/** The banana, seen from above, a touch smaller than its cell. */
private fun DrawScope.banana(px: Double, py: Double, cell: Double) {
    circle(px, py, cell * 0.62, radial(listOf(rgb(1.0, 0.9, 0.3, 0.45), rgb(1.0, 0.9, 0.3, 0.0)), px, py, cell * 0.62))
    translate(px.f, py.f) {
        oval(-cell * 0.34, cell * 0.08, cell * 0.68, cell * 0.22, Color.Black.op(0.35))
        rotate(-25f, Offset.Zero) { scale((cell * 0.8).f, (cell * 0.8).f, Offset.Zero) {
            val b = Path(); b.m(-0.44, -0.1); b.q(0.0, 0.66, 0.44, -0.12); b.q(0.0, 0.12, -0.44, -0.1); b.close()
            drawPath(b, vgrad(listOf(rgb(1.0, 0.96, 0.55), rgb(0.98, 0.76, 0.14)), 0.0, 0.32))
            strokePath(b, rgb(0.22, 0.15, 0.02), 0.06)
            rrect(0.4, -0.22, 0.12, 0.12, 0.03, rgb(0.42, 0.27, 0.08))
            circle(0.0, 0.12, 0.06, Color.White)
            oval(-0.02, 0.09, 0.06, 0.07, rgb(0.1, 0.08, 0.04))
        } }
    }
}

/** The room: steel floor tiles, riveted wall blocks and the green exit pad. */
private fun DrawScope.room(walls: BooleanArray, exit: Int, level: Int) {
    val u = density.toDouble()
    val g = MGeo(size.width.toDouble(), size.height.toDouble())
    val cell = g.cell
    val t = tint(level)
    val floorP = Path(); val seams = Path(); val blocks = Path(); val rivets = Path(); val bevel = Path()
    for (r in 0 until ROWS) for (c in 0 until COLS) {
        val x = g.ox + c * cell; val y = g.oy + r * cell
        if (walls[r * COLS + c]) {
            blocks.addRect(Rect(x.f, y.f, (x + cell + 0.5).f, (y + cell + 0.5).f))
            bevel.addRect(Rect(x.f, y.f, (x + cell).f, (y + cell * 0.1).f))
            for ((dx, dy) in listOf(0.18 to 0.18, 0.82 to 0.18, 0.18 to 0.82, 0.82 to 0.82))
                rivets.addOval(Rect((x + cell * dx - cell * 0.04).f, (y + cell * dy - cell * 0.04).f, (x + cell * dx + cell * 0.04).f, (y + cell * dy + cell * 0.04).f))
        } else {
            floorP.addRect(Rect(x.f, y.f, (x + cell + 0.5).f, (y + cell + 0.5).f))
            seams.addRect(Rect((x + cell * 0.04).f, (y + cell * 0.04).f, (x + cell * 0.96 + 0.5).f, (y + cell * 0.96 + 0.5).f))
        }
    }
    fillPath(floorP, t.mix(Color.Black, 0.72))
    drawPath(seams, t.mix(Color.White, 0.1).op(0.35), style = Stroke(u.f))
    fillPath(blocks, t.mix(gray(0.55), 0.55).mix(Color.Black, 0.35))
    fillPath(bevel, Color.White.op(0.14))
    fillPath(rivets, Color.Black.op(0.4))
    // Exit: a green teleport pad.
    val ex = g.ox + (exit % COLS + 0.5) * cell; val ey = g.oy + (exit / COLS + 0.5) * cell
    circle(ex, ey, cell * 0.9, radial(listOf(rgb(0.4, 1.0, 0.55, 0.4), rgb(0.4, 1.0, 0.55, 0.0)), ex, ey, cell * 0.9))
    for ((k, rr) in listOf(0.42, 0.3, 0.17).withIndex()) {
        if (k == 2) circle(ex, ey, cell * rr, rgb(0.6, 1.0, 0.7)) else circleStroke(ex, ey, cell * rr, rgb(0.4, 1.0, 0.55), max(1.5 * u, cell * 0.06))
    }
}
