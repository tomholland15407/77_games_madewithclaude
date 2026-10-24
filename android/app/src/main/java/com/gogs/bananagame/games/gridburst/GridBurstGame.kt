package com.gogs.bananagame.games.gridburst

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.random.Random

/**
 * Brain — Grid Burst (iOS BlockBlastGame.swift, id "block-blast"): drag the three dealt pieces onto
 * an 8×8 board; full rows / columns blast. Clear the line quota; if no tray piece fits anywhere (or
 * time runs out) it's over. Drawn like the real game; locks the feed while playing.
 */
object GridBurstGame {
    val definition = GameDefinition(
        id = "block-blast",
        title = "Grid Burst",
        genre = Genre.BRAIN,
        locksFeed = true,
        manual = GameManual(
            bullets = listOf(
                "Drag the pieces from the tray onto the board.",
                "Fill a whole row or column to blast it; clearing several at once is worth more.",
                "Clear the line target to win.",
                "If none of your pieces fits anywhere, or time runs out, you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Kéo các khối từ khay lên bàn.",
                "Lấp đầy cả một hàng hoặc một cột để phá nó; phá nhiều hàng cùng lúc càng tốt.",
                "Phá đủ số hàng mục tiêu để thắng.",
                "Nếu không khối nào còn vừa chỗ, hoặc hết giờ, bạn về lại cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> GridBurstView(level, onWin, onFail) }
    )
}

private const val N = 8

private data class BCell(val r: Int, val c: Int)
private class Piece(val id: Int, val cells: List<BCell>, val color: Int) {
    val rows = cells.maxOf { it.r } + 1
    val cols = cells.maxOf { it.c } + 1
}

private object Shapes {
    fun grid(vararg rows: String) = rows.flatMapIndexed { r, line -> line.mapIndexedNotNull { c, ch -> if (ch == '#') BCell(r, c) else null } }

    /** Every orientation of a shape (rotations + mirror), de-duplicated. */
    fun orientations(base: List<BCell>): List<List<BCell>> {
        fun normalize(cs: List<BCell>): List<BCell> {
            val mr = cs.minOf { it.r }; val mc = cs.minOf { it.c }
            return cs.map { BCell(it.r - mr, it.c - mc) }.sortedWith(compareBy({ it.r }, { it.c }))
        }
        val seen = mutableListOf<List<BCell>>()
        var cur = base
        for (flip in 0 until 2) {
            if (flip == 1) cur = base.map { BCell(it.r, -it.c) }
            repeat(4) {
                cur = cur.map { BCell(it.c, -it.r) }
                val n = normalize(cur)
                if (n !in seen) seen.add(n)
            }
        }
        return seen
    }

    // Tiered shape pools (each entry is one orientation, so rotations share the tier's weight).
    val easy = listOf(grid("#"), grid("##"), grid("#", "#"), grid("##", "##"), grid("###"), grid("#", "#", "#")) + orientations(grid("#.", "##"))
    val medium = listOf(grid("####"), grid("#", "#", "#", "#"), grid("###", "###"), grid("##", "##", "##")) +
        orientations(grid("###", ".#.")) + orientations(grid("#..", "###")) + orientations(grid(".##", "##."))
    val hard = listOf(grid("#####"), grid("#", "#", "#", "#", "#"), grid("###", "###", "###"), grid("#.", ".#"), grid(".#", "#."),
        grid("#..", ".#.", "..#"), grid("..#", ".#.", "#..")) + orientations(grid("#..", "#..", "###"))
}

// Block Blast palette.
private val COLORS = listOf(rgb(0.93, 0.27, 0.27), rgb(0.98, 0.58, 0.16), rgb(0.99, 0.80, 0.18), rgb(0.38, 0.78, 0.23),
    rgb(0.20, 0.76, 0.93), rgb(0.24, 0.47, 0.93), rgb(0.62, 0.36, 0.91))
private val BG_TOP = rgb(0.27, 0.40, 0.84)
private val BG_BOTTOM = rgb(0.15, 0.23, 0.58)
private val BOARD = rgb(0.09, 0.12, 0.29)
private val EMPTY = rgb(0.13, 0.17, 0.38)

private enum class BPhase { PLAY, WON, STUCK, DONE }
private class ClearFX(val cell: Int, val color: Int, val t0: Double)
private class Praise(val text: String, val combo: Int, val t0: Double)
private class Returning(val piece: Piece, val slot: Int, val from: P, val t0: Double)

private class Layout(w: Double, h: Double, demo: Boolean, u: Double) {
    val pad = (if (demo) 10 else 16) * u
    val statusH = (if (demo) 36 else 74) * u
    val trayH = min(w * 0.4, h * 0.26)
    val side = max(40 * u, min(w - pad * 2, h - statusH - trayH - pad * 2))
    val cell = side / 8
    val top = max(pad * 0.5, (h - (statusH + side + trayH)) / 2)
    val bx = (w - side) / 2
    val by = top + statusH
    val slotW = w / 3
    val slotY = by + side + pad * 0.4
    fun slotCenter(i: Int) = P(i * slotW + slotW / 2, slotY + trayH / 2)
    fun inSlot(i: Int, p: P) = p.x >= i * slotW && p.x < (i + 1) * slotW && p.y >= slotY && p.y < slotY + trayH
    val trayCell = cell * 0.6
}

private class BurstWorld(val level: Int) {
    private val li = min(level, 7) - 1
    val target = listOf(4, 6, 8, 10, 12, 14, 16)[li]
    val prefill = listOf(0, 6, 10, 14, 18, 22, 26)[li]
    val timeLimit = listOf(90.0, 90.0, 90.0, 95.0, 95.0, 90.0, 85.0)[li]
    /** Deal weights for the easy / medium / hard shape pools. */
    private val mix = listOf(Triple(0.7, 0.3, 0.0), Triple(0.55, 0.4, 0.05), Triple(0.45, 0.45, 0.1), Triple(0.35, 0.45, 0.2),
        Triple(0.3, 0.45, 0.25), Triple(0.25, 0.4, 0.35), Triple(0.2, 0.4, 0.4))[li]

    var phase = BPhase.PLAY
    val cells = IntArray(N * N) { -1 }                 // colour index per cell, -1 = empty
    val tray = arrayOfNulls<Piece>(3)
    var lines = 0
    var combo = 0
    var heldSlot = -1
    var finger = P.zero
    var returning: Returning? = null
    val clears = mutableListOf<ClearFX>()
    val placedAt = HashMap<Int, Double>()
    var praise: Praise? = null
    var stuckAt: Double? = null
    var timeLeft = timeLimit
    private var nextId = 0

    fun fits(p: Piece, r: Int, c: Int): Boolean {
        if (r < 0 || c < 0 || r + p.rows > N || c + p.cols > N) return false
        return p.cells.all { cells[(r + it.r) * N + c + it.c] < 0 }
    }
    fun canFitAnywhere(p: Piece): Boolean {
        for (r in 0..(N - p.rows)) for (c in 0..(N - p.cols)) if (fits(p, r, c)) return true
        return false
    }

    /** Cells of every row/column that would be complete if `extra` cells were filled too. */
    fun completedLines(extra: Set<Int>): Set<Int> {
        val out = HashSet<Int>()
        fun filled(i: Int) = cells[i] >= 0 || i in extra
        for (r in 0 until N) if ((0 until N).all { filled(r * N + it) }) out.addAll((0 until N).map { r * N + it })
        for (c in 0 until N) if ((0 until N).all { filled(it * N + c) }) out.addAll((0 until N).map { it * N + c })
        return out
    }

    fun liftedCenter(p: Piece, f: P, cell: Double) = P(f.x, f.y - p.rows * cell / 2 - cell * 1.1)

    fun snap(p: Piece, f: P, lay: Layout): BCell? {
        val c0 = liftedCenter(p, f, lay.cell)
        val x0 = c0.x - p.cols * lay.cell / 2 - lay.bx; val y0 = c0.y - p.rows * lay.cell / 2 - lay.by
        val c = (x0 / lay.cell).roundToInt(); val r = (y0 / lay.cell).roundToInt()
        return if (fits(p, r, c)) BCell(r, c) else null
    }

    fun place(p: Piece, slot: Int, spot: BCell) {
        val now = nowSec()
        for (c in p.cells) { val i = (spot.r + c.r) * N + spot.c + c.c; cells[i] = p.color; placedAt[i] = now }
        tray[slot] = null
        SoundManager.tap(); Haptics.tap()
        val full = completedLines(emptySet())
        val rowsDone = (0 until N).count { r -> (0 until N).all { cells[r * N + it] >= 0 } }
        val colsDone = (0 until N).count { c -> (0 until N).all { cells[it * N + c] >= 0 } }
        val cleared = rowsDone + colsDone
        if (cleared > 0) {
            for (i in full) { if (cells[i] >= 0) clears.add(ClearFX(i, cells[i], now)); cells[i] = -1; placedAt.remove(i) }
            lines += cleared
            combo++
            val words = listOf(L("Good!", "Tốt!"), L("Great!", "Tuyệt!"), L("Excellent!", "Xuất sắc!"), L("Unbelievable!", "Không thể tin!"))
            if (cleared >= 2 || combo >= 2) praise = Praise(words[min(max(cleared, combo) - 1, words.size - 1)], combo, now)
            Haptics.success()
        } else combo = 0
        if (lines >= target) { phase = BPhase.WON; return }
        if (tray.all { it == null }) deal()
        if (tray.filterNotNull().none { canFitAnywhere(it) }) { phase = BPhase.STUCK; stuckAt = nowSec() }
    }

    private fun randomShape(): List<BCell> {
        val roll = Random.nextDouble()
        val pool = if (roll < mix.first) Shapes.easy else if (roll < mix.first + mix.second) Shapes.medium else Shapes.hard
        return pool.pick()
    }

    /** Deals three pieces, re-rolling until at least one fits (level 1: all three). */
    fun deal() {
        var best = listOf<Piece>()
        for (attempt in 0 until 40) {
            val hand = List(3) { Piece(++nextId, randomShape(), Random.nextInt(COLORS.size)) }
            val fitting = hand.count { canFitAnywhere(it) }
            best = hand
            if (fitting == 3 || (level > 1 && fitting >= 1) || attempt == 39) break
        }
        for (i in 0 until 3) tray[i] = best[i]
    }

    /** Scatter junk in clumps without leaving any row or column complete. */
    fun prefillBoard(count: Int) {
        cells.fill(-1)
        var placed = 0; var guardCount = 0
        while (placed < count && guardCount < 2000) {
            guardCount++
            var i = Random.nextInt(N * N)
            if (placed > 0 && Random.nextBoolean()) {
                // grow an existing clump
                val base = cells.indices.filter { cells[it] >= 0 }.pick()
                val opts = listOf(base - 1, base + 1, base - N, base + N).filter { it in 0 until N * N && (it / N == base / N || it % N == base % N) }
                i = opts.randomOrNull() ?: i
            }
            if (cells[i] >= 0) continue
            cells[i] = Random.nextInt(COLORS.size)
            if (completedLines(emptySet()).isNotEmpty()) { cells[i] = -1; continue }
            placed++
        }
    }

    fun setup() {
        prefillBoard(prefill)
        lines = 0; combo = 0
        deal()
        phase = BPhase.PLAY; timeLeft = timeLimit
    }

    /** A fixed level-1 board one step from three blasts (1, then 2, then 2 lines). */
    fun demoSetup() {
        cells.fill(-1)
        var k = 0
        for ((r, cols) in demoFill) for (c in cols) { cells[r * N + c] = listOf(5, 0, 3, 1, 6, 4, 2)[k % 7]; k++ }
        tray[0] = Piece(1, Shapes.grid("###"), 4); tray[1] = Piece(2, Shapes.grid("##", "##"), 2); tray[2] = Piece(3, Shapes.grid(".#", "##"), 6)
        lines = 0; combo = 0; praise = null; clears.clear(); placedAt.clear(); stuckAt = null
        heldSlot = -1; returning = null
        phase = BPhase.PLAY
    }

    fun pruneFX() {
        val now = nowSec()
        clears.removeAll { now - it.t0 > 0.6 }
        placedAt.entries.removeAll { now - it.value >= 0.2 }
        if (praise != null && now - praise!!.t0 > 1.05) praise = null
        if (returning != null && now - returning!!.t0 > 0.24) returning = null
    }

    fun drop(lay: Layout) {
        val p = tray.getOrNull(heldSlot)
        if (p == null) { heldSlot = -1; return }
        val spot = snap(p, finger, lay)
        val slot = heldSlot
        heldSlot = -1
        if (spot != null) place(p, slot, spot)
        else returning = Returning(p, slot, liftedCenter(p, finger, lay.cell), nowSec())
    }
}

private val demoFill = listOf(0 to listOf(0, 1, 6), 1 to listOf(0, 1, 2, 3, 5, 6, 7), 2 to listOf(0, 1, 2, 5, 6, 7), 3 to listOf(7),
    4 to listOf(0, 1, 7), 5 to listOf(0, 1, 2, 3, 4, 5), 6 to listOf(0, 1, 2, 3, 4, 5), 7 to listOf(0, 1, 5, 6, 7))
private val demoMoves = listOf(Triple(0, 7, 2), Triple(1, 5, 6), Triple(2, 1, 3))

@Composable
private fun GridBurstView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { BurstWorld(level).also { if (isDemo) it.demoSetup() else it.setup() } }
    val tm = rememberTextMeasurer()
    val handP = rememberHand()
    val area = remember { doubleArrayOf(0.0, 0.0) }
    val demo = remember { object { var finger: P? = null; var pressed = false } }
    val dens = androidx.compose.ui.platform.LocalDensity.current.density.toDouble()
    val tick by rememberFrameLoop()

    fun fail() {
        if (world.phase != BPhase.PLAY && world.phase != BPhase.STUCK) return
        world.phase = BPhase.DONE; SoundManager.error(); onFail()
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (isActive) {
                world.demoSetup(); demo.finger = null; demo.pressed = false
                delay(600)
                for ((slot, r, c) in demoMoves) {
                    val p = world.tray[slot] ?: break
                    if (area[0] <= 0) break
                    val lay = Layout(area[0], area[1], true, dens)
                    val start = lay.slotCenter(slot)
                    // Finger point whose lifted piece lands exactly on (r, c).
                    val tx = lay.bx + (c + p.cols / 2.0) * lay.cell; val ty = lay.by + (r + p.rows / 2.0) * lay.cell
                    val end = P(tx, ty + p.rows * lay.cell / 2 + lay.cell * 1.1)
                    demo.finger = start
                    delay(250)
                    demo.pressed = true
                    world.heldSlot = slot; world.finger = start
                    for (s in 1..28) {
                        val t = s / 28.0
                        val e = if (t < 0.5) 2 * t * t else 1 - (-2 * t + 2).pow(2) / 2
                        val f = P(start.x + (end.x - start.x) * e, start.y + (end.y - start.y) * e)
                        world.finger = f; demo.finger = f
                        delay(20)
                    }
                    delay(250)
                    world.drop(lay)
                    demo.pressed = false
                    delay(750)
                }
                demo.finger = null
                delay(1300)
            }
        } else {
            val start = nowSec()
            while (isActive) {
                delay(50)
                world.pruneFX()
                when (world.phase) {
                    BPhase.PLAY -> {
                        world.timeLeft = max(0.0, world.timeLimit - (nowSec() - start))
                        if (world.timeLeft <= 0) { fail(); return@LaunchedEffect }
                    }
                    BPhase.WON -> { delay(550); world.phase = BPhase.DONE; onWin(); return@LaunchedEffect }
                    BPhase.STUCK -> { delay(900); fail(); return@LaunchedEffect }
                    BPhase.DONE -> return@LaunchedEffect
                }
            }
        }
    }
    if (isDemo) LaunchedEffect(Unit) { while (isActive) { delay(50); world.pruneFX() } }

    Canvas(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .onSizeChanged { area[0] = it.width.toDouble(); area[1] = it.height.toDouble() }
            .then(if (isDemo) Modifier else Modifier.touchDrag(
                onStart = { p ->
                    if (world.phase == BPhase.PLAY && world.returning == null) {
                        val lay = Layout(area[0], area[1], false, dens)
                        val slot = (0 until 3).firstOrNull { lay.inSlot(it, p) && world.tray[it] != null }
                        if (slot != null) { world.heldSlot = slot; world.finger = p; Haptics.tap() }
                    }
                },
                onMove = { _, now -> if (world.heldSlot >= 0) world.finger = now },
                onEnd = { _, _ -> if (world.heldSlot >= 0) world.drop(Layout(area[0], area[1], false, dens)) }
            ))
    ) {
        tick
        val lay = Layout(size.width.toDouble(), size.height.toDouble(), isDemo, density.toDouble())
        rect(0.0, 0.0, size.width.toDouble(), size.height.toDouble(), vgrad(listOf(BG_TOP, BG_BOTTOM), 0.0, size.height.toDouble()))
        scene(world, lay, tm)
        statusBar(world, lay, tm, isDemo)
        demo.finger?.let { f ->
            val w = lay.cell * (if (demo.pressed) 0.95 else 1.05)
            hand(handP, f.x - w * 0.28, f.y - w * 0.08, w)
        }
    }
}

// Drawing (after Block Blast).

private fun DrawScope.statusBar(world: BurstWorld, lay: Layout, tm: TextMeasurer, isDemo: Boolean) {
    val u = density.toDouble(); val w = size.width.toDouble()
    var y = lay.top
    if (!isDemo) {
        val f = if (world.timeLimit > 0) world.timeLeft / world.timeLimit else 0.0
        val bw = w - 80 * u
        rrect(40 * u, y + 4 * u, bw, 6 * u, 3 * u, Color.White.op(0.18))
        rrect(40 * u, y + 4 * u, bw * clamp(f, 0.0, 1.0), 6 * u, 3 * u, if (f < 0.3) Color.Red else BananaTheme.banana)
        y += 14 * u
    }
    val big = (if (isDemo) 26 else 40) * u; val mid = (if (isDemo) 15 else 20) * u; val small = (if (isDemo) 12 else 15) * u
    val s1 = "${min(world.lines, world.target)}"; val s2 = "/ ${world.target}"; val s3 = L("LINES", "HÀNG")
    val w1 = textWidth(tm, s1, big, FontWeight.Black); val w2 = textWidth(tm, s2, mid, FontWeight.ExtraBold); val w3 = textWidth(tm, s3, small, FontWeight.ExtraBold) + small * 0.6
    val gap = 6 * u
    var x = (w - (w1 + w2 + w3 + gap * 2)) / 2
    val base = y + (lay.statusH - (y - lay.top)) * 0.5 + big * 0.35
    for ((s, sz, a, wd) in listOf(Quad(s1, big, 1.0, w1), Quad(s2, mid, 0.7, w2), Quad(s3, small, 0.7, w3))) {
        val wt = if (sz == big) FontWeight.Black else FontWeight.ExtraBold
        val sp = if (s == s3) small * 0.1 else 0.0
        text(tm, s, x, base + 2 * u, sz, Color.Black.op(0.25), wt, anchorX = 0.0, anchorY = 0.8, spacing = sp)
        text(tm, s, x, base, sz, Color.White.op(a), wt, anchorX = 0.0, anchorY = 0.8, spacing = sp)
        x += wd + gap
    }
}

private data class Quad(val s: String, val size: Double, val alpha: Double, val w: Double)

private fun DrawScope.scene(world: BurstWorld, lay: Layout, tm: TextMeasurer) {
    val u = density.toDouble(); val cell = lay.cell; val now = nowSec()
    // Board: navy slab with recessed cells.
    val i0 = cell * 0.14
    rrect(lay.bx - i0, lay.by - i0, lay.side + 2 * i0, lay.side + 2 * i0, cell * 0.28, BOARD)
    rrectStroke(lay.bx - i0, lay.by - i0, lay.side + 2 * i0, lay.side + 2 * i0, cell * 0.28, Color.Black.op(0.35), 2 * u)
    fun rx(i: Int) = lay.bx + (i % N) * cell
    fun ry(i: Int) = lay.by + (i / N) * cell
    for (i in 0 until N * N) {
        val ins = cell * 0.045
        rrect(rx(i) + ins, ry(i) + ins, cell - 2 * ins, cell - 2 * ins, cell * 0.12, EMPTY)
        rrectStroke(rx(i) + ins + 0.5, ry(i) + ins + 0.5, cell - 2 * ins - 1, cell - 2 * ins - 1, cell * 0.12, Color.Black.op(0.22), u)
    }
    // Where would the held piece land, and which lines would that finish?
    val held = world.tray.getOrNull(world.heldSlot)
    var ghost = listOf<Int>(); var ghostLines = setOf<Int>()
    if (held != null) world.snap(held, world.finger, lay)?.let { spot ->
        ghost = held.cells.map { (spot.r + it.r) * N + spot.c + it.c }
        ghostLines = world.completedLines(ghost.toSet())
    }
    val grayK = world.stuckAt?.let { min(1.0, (now - it) / 0.5) } ?: 0.0
    for (i in 0 until N * N) {
        val col = world.cells[i]
        if (col < 0) continue
        var color = COLORS[col]
        if (i in ghostLines && held != null) color = COLORS[held.color]
        if (grayK > 0) color = color.mix(gray(0.45), grayK * 0.85)
        var ins = cell * 0.03
        world.placedAt[i]?.let { t -> val k = min(1.0, (now - t) / 0.16); ins -= (cell - 2 * ins) * 0.14 * (1 - k) / 2 }
        block(rx(i) + ins, ry(i) + ins, cell - 2 * ins, color)
    }
    if (held != null) for (i in ghost) {
        val ins = cell * 0.03
        if (i in ghostLines) block(rx(i) + ins, ry(i) + ins, cell - 2 * ins, COLORS[held.color])
        else block(rx(i) + ins, ry(i) + ins, cell - 2 * ins, COLORS[held.color], 0.42)
    }
    // Line blasts: blocks flash white and shrink away while chips fly out.
    for (fx in world.clears) {
        val t = now - fx.t0
        if (t >= 0.55) continue
        val cx = rx(fx.cell) + cell / 2; val cy = ry(fx.cell) + cell / 2
        val k = min(1.0, t / 0.32)
        val color = COLORS[fx.color].mix(Color.White, max(0.0, 0.7 - k))
        val s = (1 - k) * 0.94
        if (s > 0.02) block(cx - cell * s / 2, cy - cell * s / 2, cell * s, color)
        for (j in 0 until 4) {
            val a = (fx.cell * 7 + j) * 1.7
            val d = cell * (0.4 + t * 2.2)
            val sz = cell * 0.2 * max(0.0, 1 - t / 0.55)
            rect(cx + cos(a) * d - sz / 2, cy + sin(a) * d + t * t * cell * 6 - sz / 2, sz, sz, COLORS[fx.color].lit(0.3))
        }
    }
    // Tray.
    for (slot in 0 until 3) {
        val p = world.tray[slot] ?: continue
        if (world.heldSlot == slot || world.returning?.slot == slot) continue
        piece(p, lay.slotCenter(slot), trayCell(p, slot, lay), if (world.canFitAnywhere(p)) 1.0 else 0.35)
    }
    // A piece flying back to its slot after an illegal drop.
    world.returning?.let { r ->
        val k = min(1.0, (now - r.t0) / 0.22); val e = 1 - (1 - k).pow(3)
        val to = lay.slotCenter(r.slot)
        piece(r.piece, P(r.from.x + (to.x - r.from.x) * e, r.from.y + (to.y - r.from.y) * e), cell + (trayCell(r.piece, r.slot, lay) - cell) * e, 1.0)
    }
    // The held piece: full size, lifted above the finger, with a soft drop shadow.
    if (held != null) {
        val c = world.liftedCenter(held, world.finger, cell)
        val ox = c.x - held.cols * cell / 2; val oy = c.y - held.rows * cell / 2
        for (b in held.cells) blurRRect(ox + b.c * cell + cell * 0.03, oy + b.r * cell + cell * 0.28, cell * 0.94, cell * 0.94, cell * 0.11, Color.Black.op(0.35), cell * 0.2)
        piece(held, c, cell, 1.0)
    }
    // Praise banner.
    world.praise?.let { pr ->
        val t = now - pr.t0
        if (t < 1.0) {
            val pop = if (t < 0.18) 0.6 + 0.55 * (t / 0.18) else max(1.0, 1.15 - (t - 0.18) * 0.8)
            val alpha = if (t > 0.75) max(0.0, 1 - (t - 0.75) / 0.25) else 1.0
            val cx = lay.bx + lay.side / 2; val cy = lay.by + lay.side / 2 - cell * 0.4 - t * cell * 0.5
            banner(tm, pr.text, cx, cy, cell * 0.95 * pop, alpha)
            if (pr.combo >= 2) banner(tm, L("COMBO ${pr.combo}", "COMBO ${pr.combo}"), cx, cy + cell * 0.95, cell * 0.5, alpha)
        }
    }
}

/** Tray pieces sit at ~60% of a board cell; only long pieces shrink to fit their slot. */
private fun trayCell(p: Piece, slot: Int, lay: Layout) = min(lay.trayCell, min(lay.slotW * 0.86 / p.cols, lay.trayH * 0.86 / p.rows))

private fun DrawScope.piece(p: Piece, c: P, cell: Double, alpha: Double) {
    val ox = c.x - p.cols * cell / 2; val oy = c.y - p.rows * cell / 2
    for (b in p.cells) block(ox + b.c * cell + cell * 0.03, oy + b.r * cell + cell * 0.03, cell * 0.94, COLORS[p.color], alpha)
}

/** A glossy bevelled block: lit top/left edges, shaded right/bottom, a gradient face and a glint. */
private fun DrawScope.block(x: Double, y: Double, s: Double, base: Color, alpha: Double = 1.0) {
    val body = androidx.compose.ui.graphics.Path().apply {
        addRoundRect(androidx.compose.ui.geometry.RoundRect(x.f, y.f, (x + s).f, (y + s).f, androidx.compose.ui.geometry.CornerRadius((s * 0.12).f)))
    }
    withAlpha(alpha) {
        clipPath(body) {
            rect(x, y, s, s, base)
            val b = s * 0.15
            fillPath(polyPath(x, y, x + s, y, x + s - b, y + b, x + b, y + b), base.lit(0.45))
            fillPath(polyPath(x, y, x + b, y + b, x + b, y + s - b, x, y + s), base.lit(0.2))
            fillPath(polyPath(x + s, y, x + s, y + s, x + s - b, y + s - b, x + s - b, y + b), base.shade(0.2))
            fillPath(polyPath(x, y + s, x + b, y + s - b, x + s - b, y + s - b, x + s, y + s), base.shade(0.4))
            val fx = x + b; val fy = y + b; val fs = s - 2 * b
            rect(fx, fy, fs, fs, vgrad(listOf(base.lit(0.14), base.shade(0.04)), fy, fy + fs))
            rrect(fx + fs * 0.08, fy + fs * 0.08, fs * 0.26, fs * 0.14, fs * 0.07, Color.White.op(0.5))
        }
    }
}

/** "Great!"-style praise: a dark outline ring and a yellow → orange gradient fill. */
private fun DrawScope.banner(tm: TextMeasurer, s: String, cx: Double, cy: Double, size: Double, alpha: Double) {
    withAlpha(alpha) {
        for (k in 0 until 8) {
            val a = k * PI / 4
            text(tm, s, cx + cos(a) * size * 0.07, cy + sin(a) * size * 0.07 + size * 0.04, size, rgb(0.35, 0.12, 0.02), FontWeight.Black)
        }
        val style = TextStyle(fontSize = (size / density / fontScale).sp, fontWeight = FontWeight.Black, fontFamily = Rounded,
            brush = Brush.verticalGradient(listOf(rgb(1.0, 0.97, 0.55), rgb(1.0, 0.62, 0.1))))
        val layout = tm.measure(s, style, softWrap = false, maxLines = 1)
        drawText(layout, topLeft = Offset((cx - layout.size.width / 2.0).f, (cy - layout.size.height / 2.0).f))
    }
}
