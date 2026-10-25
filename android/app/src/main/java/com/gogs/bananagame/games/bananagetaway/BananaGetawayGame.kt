package com.gogs.bananagame.games.bananagetaway

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.random.Random

/**
 * Brain — Banana Getaway (iOS RushHourGame.swift, id "rush-hour"): a sliding-jam puzzle. Cars only
 * slide along their length; drag the jam apart so the yellow banana car can slide out of the exit on
 * the right. Every board is BFS-verified solvable with a per-level minimum move count. Drag game, so
 * the feed locks while playing. Drawn as ThinkFun's Rush Hour: a charcoal tray with an exit gap and
 * top-down plastic cars and trucks.
 */
object BananaGetawayGame {
    val definition = GameDefinition(
        id = "rush-hour",
        title = "Banana Getaway",
        genre = Genre.BRAIN,
        locksFeed = true,
        manual = GameManual(
            bullets = listOf(
                "Cars only slide along their length.",
                "Drag the blockers to clear the exit row.",
                "Then slide the yellow banana car off the right edge.",
                "Solve the jam before the clock runs out or you drop back to level 1.",
            ),
            bulletsVI = listOf(
                "Xe chỉ trượt dọc theo chiều dài của nó.",
                "Kéo các xe cản để dọn trống hàng lối ra.",
                "Rồi trượt xe chuối vàng ra khỏi mép phải.",
                "Giải kẹt xe trước khi hết giờ, nếu không bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        prefetch = { level -> BoardCache.prefetch(key(level)) { RHGen.generate(RHGen.Params(level)) } },
        content = { level, onWin, onFail -> BananaGetawayView(level, onWin, onFail) }
    )

    fun key(level: Int) = BoardCache.key("rush-hour", level)
}

/** A car or truck: row, column of its top-left cell, its length and its axis. */
data class RHCar(val r: Int, val c: Int, val len: Int, val horiz: Boolean)

object RHGen {
    const val SIZE = 6
    const val EXIT_ROW = 2

    /** Difficulty shifted up (the old level 6 is the new level 1); the move count is the real lever. */
    class Params(level: Int) {
        private val li = min(max(level, 1), 7) - 1
        val blockerCount = listOf(6, 7, 8, 8, 9, 9, 9)[li]
        val minMoves = listOf(8, 11, 14, 17, 20, 24, 28)[li]
        val timeLimit = listOf(60.0, 54.0, 48.0, 42.0, 36.0, 30.0, 26.0)[li]
    }

    fun occupancy(cs: List<RHCar>, excluding: Int? = null): Array<IntArray> {
        val g = Array(SIZE) { IntArray(SIZE) { -1 } }
        for ((i, car) in cs.withIndex()) {
            if (i == excluding) continue
            for (k in 0 until car.len) {
                val rr = car.r + (if (car.horiz) 0 else k); val cc = car.c + (if (car.horiz) k else 0)
                if (rr in 0 until SIZE && cc in 0 until SIZE) g[rr][cc] = i
            }
        }
        return g
    }

    /** The banana car (index 0) is out when its right end touches the right edge. */
    fun goal(cs: List<RHCar>): Boolean { val b = cs[0]; return b.horiz && b.c + b.len - 1 == SIZE - 1 }

    /**
     * Try many random jams; return the first that needs at least `minMoves` moves, else the hardest
     * solvable board seen (so a high bar never falls back to a trivial board).
     */
    fun generate(p: Params): List<RHCar> {
        var best: List<RHCar>? = null
        var bestMoves = -1
        repeat(300) {
            val cs = mutableListOf(RHCar(EXIT_ROW, rndInt(0..2), 2, true))
            var attempts = 0
            while (cs.size < p.blockerCount + 1 && attempts < 200) {
                attempts++
                val horiz = Random.nextBoolean()
                val len = if (rndInt(0..2) == 0) 3 else 2
                val r = if (horiz) rndInt(0 until SIZE) else rndInt(0..(SIZE - len))
                val c = if (horiz) rndInt(0..(SIZE - len)) else rndInt(0 until SIZE)
                val cand = RHCar(r, c, len, horiz)
                if (fits(cand, cs)) cs.add(cand)
            }
            val moves = shortestSolution(cs) ?: return@repeat
            if (moves >= p.minMoves) return cs
            if (moves > bestMoves) { bestMoves = moves; best = cs }
        }
        // Fallback: a guaranteed simple board (one vertical blocker on the exit row).
        return best ?: listOf(RHCar(EXIT_ROW, 0, 2, true), RHCar(EXIT_ROW, 3, 2, false))
    }

    private fun fits(car: RHCar, cs: List<RHCar>): Boolean {
        val cells = HashSet<Int>()
        for (o in cs) for (k in 0 until o.len) cells.add((o.r + (if (o.horiz) 0 else k)) * SIZE + o.c + (if (o.horiz) k else 0))
        for (k in 0 until car.len) if ((car.r + (if (car.horiz) 0 else k)) * SIZE + car.c + (if (car.horiz) k else 0) in cells) return false
        return true
    }

    /**
     * Shortest number of slide-moves to free the banana car; null if unsolvable (or the 60 000-state cap
     * is hit). Breadth-first on packed states (3 bits per car) with bitmask occupancy, in the iOS order.
     */
    fun shortestSolution(start: List<RHCar>): Int? {
        if (goal(start)) return 0
        val n = start.size
        val masks = Array(n) { LongArray(0) }
        var startKey = 0L
        for ((i, car) in start.withIndex()) {
            masks[i] = LongArray(SIZE - car.len + 1) { v ->
                var m = 0L
                for (k in 0 until car.len) {
                    val rr = if (car.horiz) car.r else v + k; val cc = if (car.horiz) v + k else car.c
                    if (rr in 0 until SIZE && cc in 0 until SIZE) m = m or (1L shl (rr * SIZE + cc))
                }
                m
            }
            startKey = startKey or ((if (car.horiz) car.c else car.r).toLong() shl (3 * i))
        }
        val goalV = if (start[0].horiz) SIZE - start[0].len else -1
        fun coord(s: Long, i: Int) = ((s ushr (3 * i)) and 7L).toInt()
        fun leadCell(car: RHCar, v: Int, dir: Int): Int {
            val lead = if (dir > 0) v + car.len - 1 else v
            return if (car.horiz) car.r * SIZE + lead else lead * SIZE + car.c
        }
        val visited = HashSet<Long>().apply { add(startKey) }
        var frontier = arrayListOf(startKey)
        var depth = 0
        while (frontier.isNotEmpty() && visited.size < 60000) {
            depth++
            val next = ArrayList<Long>()
            for (state in frontier) {
                var occ = 0L
                for (i in 0 until n) occ = occ or masks[i][coord(state, i)]
                for (i in 0 until n) {
                    val car = start[i]
                    val v = coord(state, i)
                    val g = occ and masks[i][v].inv()          // everything except this car
                    val clear = (7L shl (3 * i)).inv()
                    for (dir in intArrayOf(-1, 1)) {
                        var off = dir
                        while (true) {
                            val nv = v + off
                            if (nv < 0 || nv + car.len - 1 >= SIZE) break
                            if ((g and (1L shl leadCell(car, nv, dir))) != 0L) break
                            val ns = (state and clear) or (nv.toLong() shl (3 * i))
                            if (visited.add(ns)) {
                                if (i == 0 && nv == goalV) return depth
                                next.add(ns)
                            }
                            off += dir
                        }
                    }
                }
            }
            frontier = next
        }
        return null
    }

    /** The manual clip: the banana car in the exit row behind one vertical blocker, and some dressing. */
    fun demoBoard() = listOf(
        RHCar(EXIT_ROW, 1, 2, true),      // 0: banana car
        RHCar(1, 3, 2, false),            // 1: the blocker to lift
        RHCar(4, 0, 2, true),             // 2: dressing
        RHCar(0, 0, 2, false),            // 3: dressing
    )
}

/** A car's on-screen slide (the demo's eased moves): from where, when, and for how long. */
private class Slide(val fromR: Double, val fromC: Double, val t0: Double, val dur: Double)

private class Jam(val p: RHGen.Params) {
    var cars = mutableListOf<RHCar>()
    val slides = mutableMapOf<Int, Slide>()
    var playing = true
    var timeLeft by mutableDoubleStateOf(p.timeLimit)
    var dragId: Int? = null
    var originR = 0; var originC = 0
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    /** How far car `i` (at origin r, c) can slide in the negative and positive directions. */
    fun slideRange(i: Int, r: Int, c: Int): Pair<Int, Int> {
        val g = RHGen.occupancy(cars, i)
        val car = cars[i]
        var neg = 0; var pos = 0
        if (car.horiz) {
            var cc = c + car.len; while (cc < RHGen.SIZE && g[r][cc] == -1) { pos++; cc++ }
            var cl = c - 1; while (cl >= 0 && g[r][cl] == -1) { neg++; cl-- }
        } else {
            var rr = r + car.len; while (rr < RHGen.SIZE && g[rr][c] == -1) { pos++; rr++ }
            var rl = r - 1; while (rl >= 0 && g[rl][c] == -1) { neg++; rl-- }
        }
        return neg to pos
    }

    /** A drag on car `i` by (dx, dy) cells from where it started: it snaps cell by cell within its free range. */
    fun drag(i: Int, dx: Double, dy: Double) {
        if (!playing || i >= cars.size) return
        if (dragId != i) { dragId = i; originR = cars[i].r; originC = cars[i].c }
        val (neg, pos) = slideRange(i, originR, originC)
        val car = cars[i]
        cars[i] = if (car.horiz) car.copy(c = originC + min(pos, max(-neg, dx.roundToInt())))
                  else car.copy(r = originR + min(pos, max(-neg, dy.roundToInt())))
    }

    fun endDrag(i: Int) {
        if (dragId != i || i >= cars.size) return
        if (cars[i].r != originR || cars[i].c != originC) { SoundManager.tap(); Haptics.tap() }
        dragId = null
        if (RHGen.goal(cars)) win()
    }

    /** Where car `i` is drawn: its cell, or part-way along a demo slide. */
    fun shown(i: Int, now: Double): Pair<Double, Double> {
        val car = cars[i]
        val s = slides[i] ?: return car.r.toDouble() to car.c.toDouble()
        val k = clamp((now - s.t0) / s.dur, 0.0, 1.0)
        val e = 0.5 - 0.5 * cos(PI * k)
        return (s.fromR + (car.r - s.fromR) * e) to (s.fromC + (car.c - s.fromC) * e)
    }

    fun slideTo(i: Int, r: Int, c: Int, dur: Double) {
        val (sr, sc) = shown(i, nowSec())
        slides[i] = Slide(sr, sc, nowSec(), dur)
        cars[i] = cars[i].copy(r = r, c = c)
    }

    fun win() {
        if (!playing) return
        playing = false
        Haptics.success(); SoundManager.tap()
        onWin()
    }

    fun fail() {
        if (!playing) return
        playing = false
        SoundManager.error()
        onFail()
    }
}

/** The board's cell size and offset inside an area of w × h points. */
private class RHGrid(w: Double, h: Double) {
    val cell = min(w, h) / (RHGen.SIZE + 1.2)
    val ox = (w - cell * RHGen.SIZE) / 2
    val oy = (h - cell * RHGen.SIZE) / 2
}

@Composable
private fun BananaGetawayView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val jam = remember { Jam(RHGen.Params(level)) }
    jam.onWin = onWin; jam.onFail = onFail
    var ready by remember { mutableStateOf(false) }
    var demoFinger by remember { mutableStateOf<Int?>(null) }
    val tick by rememberFrameLoop(running = ready)
    val handP = rememberHand()

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (isActive) {
                jam.cars = RHGen.demoBoard().toMutableList(); jam.slides.clear()
                jam.playing = true; ready = true
                delay(700)
                demoFinger = 1                                  // grab the blocker
                delay(300)
                jam.slideTo(1, 0, 3, 0.5)                       // blocker up, clears the row
                delay(700)
                demoFinger = 0                                  // grab the banana car
                delay(300)
                jam.slideTo(0, RHGen.EXIT_ROW, 4, 0.65)         // banana slides out the exit
                delay(600)
                demoFinger = null
                delay(1200)                                     // hold on the freed car
            }
        } else {
            val t0 = System.currentTimeMillis()
            val b = BoardCache.take(BananaGetawayGame.key(level)) { RHGen.generate(jam.p) }
            BoardCache.holdBrainstorm(t0, 0.7)
            jam.cars = b.toMutableList(); ready = true
            val start = nowSec()
            while (isActive && jam.playing) {
                delay(50)
                jam.timeLeft = max(0.0, jam.p.timeLimit - (nowSec() - start))
                if (jam.timeLeft <= 0) jam.fail()
            }
        }
    }

    if (!ready) { BrainstormingView(gray(0.12), gray(0.05)); return }

    val u = LocalDensity.current.density.toDouble()
    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp)
            .clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .background(Brush.verticalGradient(listOf(rgb(0.2, 0.23, 0.28), rgb(0.1, 0.11, 0.14)))),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        if (!isDemo) {
            Canvas(Modifier.fillMaxWidth().padding(horizontal = 48.dp).padding(top = 6.dp).height(6.dp)) {
                val f = clamp(jam.timeLeft / jam.p.timeLimit, 0.0, 1.0)
                val w = size.width.toDouble(); val h = size.height.toDouble()
                rrect(0.0, 0.0, w, h, h / 2, Color.White.op(0.15))
                if (f > 0) rrect(0.0, 0.0, w * f, h, min(h, w * f) / 2, if (f < 0.3) Color.Red else BananaTheme.banana)
            }
        }
        var dragging by remember { mutableStateOf<Int?>(null) }
        var area by remember { mutableStateOf(IntSize.Zero) }
        Canvas(
            Modifier.weight(1f).fillMaxWidth().padding(horizontal = if (isDemo) 8.dp else 0.dp)
                .onSizeChanged { area = it }
                .artBehind { w, h -> tray(RHGrid(w, h)) }
                .then(if (isDemo) Modifier else Modifier.touchDrag(
                    onStart = { p ->
                        val g = RHGrid(area.width / u, area.height / u)
                        dragging = jam.cars.indices.firstOrNull { i -> carRect(jam.cars[i], g).contains(p.x / u, p.y / u) }
                    },
                    onMove = { start, p ->
                        val i = dragging ?: return@touchDrag
                        val g = RHGrid(area.width / u, area.height / u)
                        jam.drag(i, (p.x - start.x) / u / g.cell, (p.y - start.y) / u / g.cell)
                    },
                    onEnd = { _, _ -> dragging?.let { jam.endDrag(it) }; dragging = null }))
        ) {
            tick
            val now = nowSec()
            inPoints { w, h ->
                val g = RHGrid(w, h)
                for ((i, car) in jam.cars.withIndex()) {
                    val (r, c) = jam.shown(i, now)
                    val cw = (if (car.horiz) car.len.toDouble() else 1.0) * g.cell - 6
                    val ch = (if (car.horiz) 1.0 else car.len.toDouble()) * g.cell - 6
                    val cx = g.ox + (c + (if (car.horiz) car.len.toDouble() else 1.0) / 2) * g.cell
                    val cy = g.oy + (r + (if (car.horiz) 1.0 else car.len.toDouble()) / 2) * g.cell
                    vehicle(cx, cy, cw, ch, if (i == 0) BANANA else blockerColor(i), car.len, car.horiz, i == 0)
                }
            }
            demoFinger?.let { fi ->
                if (fi >= jam.cars.size) return@let
                val g = RHGrid(size.width / u, size.height / u)
                val car = jam.cars[fi]
                val (r, c) = jam.shown(fi, now)
                val x = (g.ox + (c + (if (car.horiz) car.len.toDouble() else 1.0) / 2) * g.cell + g.cell * 0.22) * u
                val y = (g.oy + (r + (if (car.horiz) 1.0 else car.len.toDouble()) / 2) * g.cell + g.cell * 0.22) * u
                val s = g.cell * 0.6 * u
                hand(handP, x - s / 2, y - s / 2, s)
            }
        }
    }
}

/** A car's hit area: its drawn frame (3 pt inside its cells). */
private class Box2(val x: Double, val y: Double, val w: Double, val h: Double) {
    fun contains(px: Double, py: Double) = px >= x && px <= x + w && py >= y && py <= y + h
}

private fun carRect(car: RHCar, g: RHGrid): Box2 {
    val cw = (if (car.horiz) car.len else 1) * g.cell - 6
    val ch = (if (car.horiz) 1 else car.len) * g.cell - 6
    return Box2(g.ox + car.c * g.cell + 3, g.oy + car.r * g.cell + 3, cw, ch)
}

// Art (ThinkFun's Rush Hour), drawn in points.

private val BANANA = rgb(1.0, 0.84, 0.16)

/** The game's bright plastic colours for the blockers. */
private fun blockerColor(i: Int) = listOf(
    rgb(0.42, 0.8, 0.24), rgb(1.0, 0.52, 0.14), rgb(0.2, 0.7, 0.92),
    rgb(0.94, 0.36, 0.62), rgb(0.58, 0.38, 0.86), rgb(0.16, 0.42, 0.86),
    rgb(0.12, 0.56, 0.4), rgb(0.86, 0.2, 0.22), rgb(0.2, 0.78, 0.72),
    rgb(0.76, 0.62, 0.4),
)[i % 10]

private fun rr(x: Double, y: Double, w: Double, h: Double, r: Double) =
    Path().apply { addRoundRect(RoundRect(x.f, y.f, (x + w).f, (y + h).f, CornerRadius(r.f, r.f))) }

/** The charcoal plastic tray: a raised rim, 6×6 recessed squares and the exit gap (with chevrons). */
private fun DrawScope.tray(g: RHGrid) {
    val cell = g.cell; val n = RHGen.SIZE
    val bw = cell * n
    val bx = g.ox; val by = g.oy
    val rx = bx - cell * 0.22; val ry = by - cell * 0.22; val rw = bw + cell * 0.44
    rrect(rx, ry + 4, rw, rw, cell * 0.3, Color.Black.op(0.4))
    rrect(rx, ry, rw, rw, cell * 0.3, vgrad(listOf(gray(0.32), gray(0.16)), ry, ry + rw))
    rrectStroke(rx + 1.5, ry + 1.5, rw - 3, rw - 3, cell * 0.28, Color.White.op(0.15), 1.5)
    rrect(bx, by, bw, bw, cell * 0.08, gray(0.12))
    val squares = Path()
    for (r in 0 until n) for (c in 0 until n) {
        squares.addRoundRect(RoundRect((bx + c * cell + cell * 0.05).f, (by + r * cell + cell * 0.05).f,
            (bx + c * cell + cell * 0.95).f, (by + r * cell + cell * 0.95).f, CornerRadius((cell * 0.08).f)))
    }
    drawPath(squares, gray(0.2))
    drawPath(squares, Color.Black.op(0.35), style = Stroke(1f))
    // Exit gap in the right rim, marked with chevrons.
    val gy = by + RHGen.EXIT_ROW * cell
    rect(bx + bw - 1, gy + cell * 0.06, rx + rw - (bx + bw) + 2, cell * 0.88, gray(0.12))
    val chevrons = Path()
    for (k in 0 until 2) {
        val x = rx + rw + cell * (0.12 + k * 0.2)
        chevrons.m(x, gy + cell * 0.3); chevrons.l(x + cell * 0.14, gy + cell * 0.5); chevrons.l(x, gy + cell * 0.7)
    }
    drawPath(chevrons, BANANA, style = Stroke(max(2.0, cell * 0.07).f, cap = StrokeCap.Round, join = StrokeJoin.Round))
}

/**
 * A plastic car (length 2) or truck (length 3) seen from above, centred at (cx, cy) in a cw × ch frame,
 * nose right (horizontal) or up (vertical); the banana car carries a banana decal.
 */
private fun DrawScope.vehicle(cx: Double, cy: Double, cw: Double, ch: Double, color: Color, len: Int, horiz: Boolean, banana: Boolean) {
    val L = if (horiz) cw else ch; val W = if (horiz) ch else cw
    translate(cx.f, cy.f) {
        rotate(if (horiz) 0f else -90f, Offset.Zero) {
            translate((-L / 2).f, (-W / 2).f) {
                rrect(0.0, 3.0, L, W, W * 0.26, Color.Black.op(0.35))
                rrect(0.0, 0.0, L, W, W * 0.26, vgrad(listOf(color.mix(Color.White, 0.3), color, color.mix(Color.Black, 0.3)), 0.0, W))
                rrectStroke(0.75, 0.75, L - 1.5, W - 1.5, W * 0.25, Color.Black.op(0.45), 1.5)
                val glass = rgb(0.12, 0.18, 0.26)
                if (len >= 3) {
                    // Truck: cab at the nose, a ribbed cargo bed behind.
                    rrect(L - W * 1.05, W * 0.1, W * 0.95, W * 0.8, W * 0.18, color.mix(Color.White, 0.15))
                    rrect(L - W * 0.42, W * 0.16, W * 0.24, W * 0.68, W * 0.08, glass)
                    val bx = W * 0.12; val by = W * 0.12; val bw = L - W * 1.3; val bh = W * 0.76
                    rrect(bx, by, bw, bh, W * 0.1, color.mix(Color.Black, 0.2))
                    val ribs = Path()
                    var x = bx + W * 0.2
                    while (x < bx + bw - W * 0.05) { ribs.m(x, by + 2); ribs.l(x, by + bh - 2); x += W * 0.28 }
                    drawPath(ribs, Color.Black.op(0.3), style = Stroke(1.5f))
                } else {
                    // Car: windshield, roof, rear window.
                    rrect(L * 0.56, W * 0.16, L * 0.16, W * 0.68, W * 0.1, glass)
                    rrect(L * 0.28, W * 0.14, L * 0.28, W * 0.72, W * 0.14, color.mix(Color.White, 0.18))
                    rrect(L * 0.16, W * 0.2, L * 0.1, W * 0.6, W * 0.08, glass)
                    rrect(L * 0.6, W * 0.22, L * 0.06, W * 0.2, 2.0, Color.White.op(0.5))
                }
                // Headlights at the nose, tail lights at the back.
                for (y in listOf(W * 0.14, W * 0.72)) {
                    rrect(L - W * 0.1, y, W * 0.07, W * 0.14, 2.0, rgb(1.0, 0.96, 0.75))
                    rrect(W * 0.03, y, W * 0.06, W * 0.14, 2.0, rgb(0.9, 0.15, 0.1))
                }
                if (banana) {
                    // A banana decal on the roof.
                    translate((L * 0.42).f, (W * 0.5).f) {
                        rotate(-20f, Offset.Zero) {
                            scale((W * 0.55).f, (W * 0.55).f, Offset.Zero) {
                                val b = Path().apply { m(-0.44, -0.1); q(0.0, 0.66, 0.44, -0.12); q(0.0, 0.12, -0.44, -0.1); close() }
                                drawPath(b, rgb(1.0, 0.95, 0.5))
                                drawPath(b, rgb(0.45, 0.3, 0.05), style = Stroke(0.07f))
                                drawPath(rr(0.4, -0.22, 0.12, 0.12, 0.03), rgb(0.42, 0.27, 0.08))
                            }
                        }
                    }
                }
            }
        }
    }
}

