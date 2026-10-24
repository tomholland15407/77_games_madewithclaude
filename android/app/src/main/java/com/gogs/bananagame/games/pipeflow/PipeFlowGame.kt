package com.gogs.bananagame.games.pipeflow

import androidx.compose.foundation.Canvas
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

/**
 * Brain — Pipe Flow (iOS PipeFlowGame.swift, id "pipe-flow"): tap pipe tiles to rotate them 90° and
 * link the source (left) to the drain (right) before the clock empties. Boards are carved around a
 * guaranteed route, then scrambled so they never start connected. Drawn after Pipe Mania.
 */
object PipeFlowGame {
    val definition = GameDefinition(
        id = "pipe-flow",
        title = "Pipe Flow",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Tap a pipe tile to rotate it.",
                "Link an unbroken line of pipe from the source on the left to the drain on the right.",
                "The connected flow glows yellow.",
                "Complete the line before the clock empties or you drop back to level 1.",
            ),
            bulletsVI = listOf(
                "Chạm một ô ống để xoay nó.",
                "Nối một đường ống liền mạch từ nguồn bên trái đến chỗ thoát bên phải.",
                "Dòng chảy được nối sẽ phát sáng màu vàng.",
                "Hoàn thành đường ống trước khi hết giờ, nếu không bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        prefetch = { level -> BoardCache.prefetch(key(level)) { PipeGen.generate(gridN(level), minPathLen(level)) } },
        content = { level, onWin, onFail -> PipeFlowView(level, onWin, onFail) }
    )

    fun key(level: Int) = BoardCache.key("pipe-flow", level)
    fun gridN(level: Int) = listOf(4, 4, 5, 5, 6, 6, 6)[min(level, 7) - 1]
    fun timeLimit(level: Int) = listOf(30.0, 26.0, 24.0, 20.0, 16.0, 13.0, 11.0)[min(level, 7) - 1]
    fun minPathLen(level: Int) = listOf(8, 10, 13, 16, 20, 24, 28)[min(level, 7) - 1]
}

// Connection bits.
private const val N = 1
private const val E = 2
private const val S = 4
private const val W = 8

data class PCell(val r: Int, val c: Int)
class PipeBoard(val masks: List<IntArray>, val source: PCell, val drain: PCell)

object PipeGen {
    fun rotateCW(m: Int) = ((m shl 1) or (m shr 3)) and 15

    fun flows(masks: List<IntArray>, source: PCell, n: Int): Set<PCell> {
        val reached = hashSetOf(source); val stack = ArrayDeque(listOf(source))
        while (stack.isNotEmpty()) {
            val cur = stack.removeLast()
            val m = masks[cur.r][cur.c]
            for ((bit, dr, dc, opp) in listOf(intArrayOf(N, -1, 0, S), intArrayOf(S, 1, 0, N), intArrayOf(E, 0, 1, W), intArrayOf(W, 0, -1, E))) {
                if (m and bit == 0) continue
                val nx = PCell(cur.r + dr, cur.c + dc)
                if (nx.r !in 0 until n || nx.c !in 0 until n || nx in reached) continue
                if (masks[nx.r][nx.c] and opp != 0) { reached.add(nx); stack.addLast(nx) }
            }
        }
        return reached
    }

    /** Randomized DFS carving a self-avoiding path from source to drain. */
    private fun carvePath(from: PCell, to: PCell, n: Int): List<PCell>? {
        val visited = hashSetOf(from); val path = mutableListOf(from)
        fun dfs(cur: PCell): Boolean {
            if (cur == to) return true
            for ((dr, dc) in listOf(-1 to 0, 1 to 0, 0 to -1, 0 to 1).shuffled()) {
                val nx = PCell(cur.r + dr, cur.c + dc)
                if (nx.r !in 0 until n || nx.c !in 0 until n || nx in visited) continue
                visited.add(nx); path.add(nx)
                if (dfs(nx)) return true
                path.removeAt(path.size - 1); visited.remove(nx)
            }
            return false
        }
        return if (dfs(from)) path else null
    }

    /** First board whose route is ≥ minPathLen tiles, else the longest seen; always solvable, never pre-connected. */
    fun generate(n: Int, minPathLen: Int): PipeBoard {
        var best: PipeBoard? = null; var bestLen = -1
        repeat(200) {
            val source = PCell(Random.nextInt(n), 0); val drain = PCell(Random.nextInt(n), n - 1)
            val path = carvePath(source, drain, n) ?: return@repeat
            val m = List(n) { IntArray(n) }
            for (i in 0 until path.size - 1) {
                val a = path[i]; val b = path[i + 1]
                if (b.r == a.r - 1) { m[a.r][a.c] = m[a.r][a.c] or N; m[b.r][b.c] = m[b.r][b.c] or S }
                if (b.r == a.r + 1) { m[a.r][a.c] = m[a.r][a.c] or S; m[b.r][b.c] = m[b.r][b.c] or N }
                if (b.c == a.c + 1) { m[a.r][a.c] = m[a.r][a.c] or E; m[b.r][b.c] = m[b.r][b.c] or W }
                if (b.c == a.c - 1) { m[a.r][a.c] = m[a.r][a.c] or W; m[b.r][b.c] = m[b.r][b.c] or E }
            }
            // Decoy pipes on empty cells so the board looks full.
            val decoys = listOf(N or S, E or W, N or E, S or W, N or W, S or E)
            for (r in 0 until n) for (c in 0 until n) if (m[r][c] == 0) m[r][c] = decoys.pick()
            // Scramble every tile so it doesn't start solved.
            for (r in 0 until n) for (c in 0 until n) repeat(rndInt(0..3)) { m[r][c] = rotateCW(m[r][c]) }
            var guardCount = 0
            while (drain in flows(m, source, n) && guardCount < 20) {
                guardCount++
                val pc = path.pick(); m[pc.r][pc.c] = rotateCW(m[pc.r][pc.c])
            }
            if (drain in flows(m, source, n)) return@repeat
            val board = PipeBoard(m, source, drain)
            if (path.size >= minPathLen) return board
            if (path.size > bestLen) { bestLen = path.size; best = board }
        }
        best?.let { return it }
        // Deterministic last resort: a straight row-0 line, broken at the source.
        val m = List(n) { IntArray(n) { E or W } }
        m[0][0] = N
        return PipeBoard(m, PCell(0, 0), PCell(0, n - 1))
    }
}

// Demo: a fixed 4×4 board whose route snakes 10 tiles; the route's tiles are turned in flow order
// (13 taps) so the yellow flow creeps along, and only the last tap connects.
private val demoMasks = listOf(intArrayOf(6, 3, 3, 5), intArrayOf(12, 10, 10, 6), intArrayOf(1, 12, 10, 2), intArrayOf(9, 9, 6, 12))
private val demoTaps = listOf(2 to 0, 2 to 1, 1 to 1, 0 to 1, 0 to 2, 0 to 2, 1 to 2, 2 to 2, 3 to 2, 3 to 2, 3 to 2, 3 to 3, 2 to 3)

private class PGeo(w: Double, h: Double, n: Int) {
    val cell = min(w, h) / (n + 1)
    val boardW = cell * n
    val ox = (w - boardW) / 2
    val oy = (h - boardW) / 2
}

@Composable
private fun PipeFlowView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val n = PipeFlowGame.gridN(level)
    val timeLimit = PipeFlowGame.timeLimit(level)
    var playing by remember { mutableStateOf(true) }
    var ready by remember { mutableStateOf(false) }
    var masks by remember { mutableStateOf(listOf<IntArray>()) }
    var source by remember { mutableStateOf(PCell(0, 0)) }
    var drain by remember { mutableStateOf(PCell(0, 0)) }
    var solved by remember { mutableStateOf(false) }
    var timeLeft by remember { mutableDoubleStateOf(timeLimit) }
    var demoFinger by remember { mutableStateOf<PCell?>(null) }
    var demoTapAt by remember { mutableDoubleStateOf(-10.0) }
    val handP = rememberHand()
    val tick by rememberFrameLoop(running = demoFinger != null)

    fun win() { if (!playing) return; playing = false; Haptics.success(); SoundManager.tap(); onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }
    fun rotate(r: Int, c: Int) {
        if (!playing || r !in masks.indices || c !in 0 until n) return
        masks = masks.mapIndexed { i, row -> if (i == r) row.copyOf().also { it[c] = PipeGen.rotateCW(it[c]) } else row }
        SoundManager.tap(); Haptics.tap()
        if (drain in PipeGen.flows(masks, source, n)) { solved = true; win() }
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (isActive) {
                masks = demoMasks.map { it.copyOf() }
                source = PCell(2, 0); drain = PCell(2, 3)
                solved = false; demoFinger = null; timeLeft = timeLimit; playing = true; ready = true
                delay(800)
                for ((r, c) in demoTaps) {
                    val cell = PCell(r, c)
                    if (demoFinger != cell) { demoFinger = cell; delay(180) }
                    demoTapAt = nowSec()
                    rotate(r, c)
                    delay(260)
                }
                demoFinger = null
                delay(1300)
            }
        } else {
            val t0 = System.currentTimeMillis()
            val b = BoardCache.take(PipeFlowGame.key(level)) { PipeGen.generate(n, PipeFlowGame.minPathLen(level)) }
            BoardCache.holdBrainstorm(t0, 0.7)
            masks = b.masks; source = b.source; drain = b.drain
            solved = false; ready = true; playing = true; timeLeft = timeLimit
            val start = nowSec()
            while (isActive && playing) {
                delay(50)
                timeLeft = max(0.0, timeLimit - (nowSec() - start))
                if (timeLeft <= 0) { fail(); break }
            }
        }
    }

    if (!ready) { BrainstormingView(gray(0.11), gray(0.04)); return }

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .drawWithCache { onDrawBehind { brickWall(level) } },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(if (isDemo) 4.dp else 14.dp)
    ) {
        if (!isDemo) {
            val f = if (timeLimit > 0) timeLeft / timeLimit else 0.0
            TimeBar(f, Modifier.fillMaxWidth().padding(horizontal = 48.dp).padding(top = 6.dp).height(6.dp),
                fill = if (f < 0.3) rgb(1.0, 0.32, 0.26) else PFJuice, track = Color.Black.op(0.35))
        }
        Canvas(Modifier.fillMaxWidth().weight(1f).padding(horizontal = if (isDemo) 10.dp else 2.dp)
            .then(if (isDemo) Modifier else Modifier.tapIn(masks) { p, w, h ->
                val g = PGeo(w, h, n)
                val c = floor((p.x - g.ox) / g.cell).toInt(); val r = floor((p.y - g.oy) / g.cell).toInt()
                if (r in 0 until n && c in 0 until n) rotate(r, c)
            })) {
            tick
            if (masks.size != n) return@Canvas
            val g = PGeo(size.width.toDouble(), size.height.toDouble(), n)
            val cell = g.cell
            val filled = PipeGen.flows(masks, source, n)
            frame(g.ox, g.oy, g.boardW, cell)
            for (r in 0 until n) for (c in 0 until n) tile(g.ox + c * cell, g.oy + r * cell, cell, level)
            tank(g.ox, g.oy + (source.r + 0.5) * cell, cell)
            drainArt(g.ox + g.boardW, g.oy + (drain.r + 0.5) * cell, cell, solved)
            mark(g.ox + source.c * cell, g.oy + source.r * cell, cell, PFGreen)
            mark(g.ox + drain.c * cell, g.oy + drain.r * cell, cell, if (solved) PFJuice else rgb(0.95, 0.35, 0.3))
            for (r in 0 until n) for (c in 0 until n) pipe(masks[r][c], g.ox + (c + 0.5) * cell, g.oy + (r + 0.5) * cell, cell, PCell(r, c) in filled)
            demoFinger?.let { f ->
                val cx = g.ox + (f.c + 0.5) * cell; val cy = g.oy + (f.r + 0.5) * cell
                tapRipple(cx, cy, nowSec() - demoTapAt)
                val s = cell * 0.42
                hand(handP, cx + cell * 0.28 - s / 2, cy + cell * 0.34 - s / 2, s)
            }
        }
    }
}

// Plumbing art (after Pipe Mania; iOS PFArt).

private val PFJuice = rgb(1.0, 0.84, 0.2)
private val PFGreen = rgb(0.3, 0.82, 0.4)
private val PFSteel = rgb(0.66, 0.7, 0.76)

/** Stone tiles (1–3), blue steel plates (4–5), a dark sewer (6–7). */
private fun tileColor(level: Int) = if (level >= 6) rgb(0.3, 0.3, 0.26) else if (level >= 4) rgb(0.38, 0.46, 0.56) else rgb(0.72, 0.64, 0.5)

/** The board's dark iron frame. */
private fun DrawScope.frame(ox: Double, oy: Double, bw: Double, cell: Double) {
    val u = density.toDouble(); val i = cell * 0.14
    rrect(ox - i, oy - i, bw + 2 * i, bw + 2 * i, cell * 0.12, gray(0.12))
    rrectStroke(ox - i + 2 * u, oy - i + 2 * u, bw + 2 * i - 4 * u, bw + 2 * i - 4 * u, cell * 0.1, Color.White.op(0.12), 1.5 * u)
}

/** A bevelled tile with a screw in each corner. */
private fun DrawScope.tile(x: Double, y: Double, w: Double, level: Int) {
    val i = w * 0.025
    val tx = x + i; val ty = y + i; val ts = w - 2 * i
    rect(tx, ty, ts, ts, tileColor(level))
    val b = w * 0.07
    fillPath(polyPath(tx, ty + ts, tx, ty, tx + ts, ty, tx + ts - b, ty + b, tx + b, ty + b, tx + b, ty + ts - b), Color.White.op(0.2))
    fillPath(polyPath(tx + ts, ty, tx + ts, ty + ts, tx, ty + ts, tx + b, ty + ts - b, tx + ts - b, ty + ts - b, tx + ts - b, ty + b), Color.Black.op(0.25))
    for ((dx, dy) in listOf(0.15 to 0.15, 0.85 to 0.15, 0.15 to 0.85, 0.85 to 0.85)) circle(tx + ts * dx, ty + ts * dy, w * 0.035, Color.Black.op(0.3))
}

/** A thin coloured frame around the source (green) or drain tile. */
private fun DrawScope.mark(x: Double, y: Double, cell: Double, color: Color) =
    rrectStroke(x + cell * 0.06, y + cell * 0.06, cell * 0.88, cell * 0.88, cell * 0.08, color, max(2 * density.toDouble(), cell * 0.06))

/** One tile's pipe: steel arms with flanges, a round joint, and glowing juice once the flow arrives. */
private fun DrawScope.pipe(m: Int, cx: Double, cy: Double, cell: Double, full: Boolean) {
    val arms = Path(); val flanges = Path()
    val reach = cell * 0.5
    for ((bit, dx, dy) in listOf(Triple(N, 0.0, -1.0), Triple(S, 0.0, 1.0), Triple(E, 1.0, 0.0), Triple(W, -1.0, 0.0))) {
        if (m and bit == 0) continue
        arms.m(cx, cy); arms.l(cx + dx * reach, cy + dy * reach)
        val fx = cx + dx * cell * 0.42; val fy = cy + dy * cell * 0.42
        val hw = cell * 0.2; val ht = cell * 0.05
        flanges.addRect(if (dx == 0.0) Rect((fx - hw).f, (fy - ht).f, (fx + hw).f, (fy + ht).f) else Rect((fx - ht).f, (fy - hw).f, (fx + ht).f, (fy + hw).f))
    }
    val ink = gray(0.12)
    strokePath(arms, ink, cell * 0.34, StrokeCap.Butt)
    circle(cx, cy, cell * 0.19, ink)
    fillPath(flanges, ink)
    strokePath(arms, PFSteel, cell * 0.26, StrokeCap.Butt)
    circle(cx, cy, cell * 0.16, PFSteel)
    fillPath(flanges, PFSteel.mix(Color.Black, 0.2))
    strokePath(arms, Color.White.op(0.35), cell * 0.06, StrokeCap.Butt)
    if (full) {
        strokePath(arms, PFJuice.op(0.45), cell * 0.22)
        strokePath(arms, PFJuice, cell * 0.14)
        circle(cx, cy, cell * 0.11, PFJuice)
        strokePath(arms, Color.White.op(0.7), cell * 0.04)
    }
}

/** The supply tank outside the board, piped in at the source row. */
private fun DrawScope.tank(px: Double, py: Double, cell: Double) {
    line(px - cell * 0.3, py, px + 1, py, gray(0.12), cell * 0.34, StrokeCap.Butt)
    line(px - cell * 0.3, py, px + 1, py, PFJuice, cell * 0.2, StrokeCap.Butt)
    val bx = px - cell * 0.46; val by = py - cell * 0.3; val bw = cell * 0.26; val bh = cell * 0.6
    rrect(bx, by, bw, bh, cell * 0.12, hgrad(listOf(PFGreen.mix(Color.White, 0.3), PFGreen, PFGreen.mix(Color.Black, 0.35)), bx, bx + bw))
    rrectStroke(bx, by, bw, bh, cell * 0.12, gray(0.1), max(density.toDouble(), cell * 0.035))
    circleStroke(bx + bw / 2, by - cell * 0.02, cell * 0.12, rgb(0.85, 0.2, 0.18), max(1.5 * density, cell * 0.05))
}

/** The drain outside the board at the drain row; juice pours in once connected. */
private fun DrawScope.drainArt(px: Double, py: Double, cell: Double, flowing: Boolean) {
    val u = density.toDouble()
    line(px - 1, py, px + cell * 0.36, py, gray(0.12), cell * 0.34, StrokeCap.Butt)
    line(px - 1, py, px + cell * 0.36, py, if (flowing) PFJuice else gray(0.3), cell * 0.2, StrokeCap.Butt)
    val gx = px + cell * 0.3; val gy = py - cell * 0.26; val gw = cell * 0.16; val gh = cell * 0.52
    rrect(gx, gy, gw, gh, cell * 0.04, gray(0.2))
    val bars = Path()
    for (k in 1..3) { val y = gy + gh * k / 4; bars.m(gx + 2 * u, y); bars.l(gx + gw - 2 * u, y) }
    strokePath(bars, if (flowing) PFJuice else gray(0.45), 1.5 * u, StrokeCap.Butt)
}

/** A basement brick wall behind the board, with a vignette. */
private fun DrawScope.brickWall(level: Int) {
    val u = density.toDouble(); val w = size.width.toDouble(); val h = size.height.toDouble()
    rect(0.0, 0.0, w, h, if (level >= 6) rgb(0.2, 0.18, 0.16) else if (level >= 4) rgb(0.2, 0.22, 0.28) else rgb(0.36, 0.2, 0.14))
    val mortar = Path(); val bh = 16 * u; val bw = 36 * u
    var y = 0.0; var row = 0
    while (y < h) {
        mortar.m(0.0, y); mortar.l(w, y)
        var x = if (row % 2 == 0) 0.0 else bw / 2
        while (x < w) { mortar.m(x, y); mortar.l(x, y + bh); x += bw }
        y += bh; row++
    }
    strokePath(mortar, Color.Black.op(0.3), 2 * u, StrokeCap.Butt)
    val outer = max(w, h) * 0.7; val inner = min(w, h) * 0.3
    rect(0.0, 0.0, w, h, Brush.radialGradient(0f to Color.Transparent, (inner / outer).toFloat() to Color.Transparent, 1f to Color.Black.op(0.55),
        center = Offset((w / 2).f, (h / 2).f), radius = outer.f))
}
