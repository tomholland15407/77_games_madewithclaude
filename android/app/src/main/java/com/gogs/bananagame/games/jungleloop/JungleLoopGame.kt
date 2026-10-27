package com.gogs.bananagame.games.jungleloop

import androidx.compose.foundation.Canvas
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
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

/**
 * Brain — Jungle Loop (iOS SlitherlinkGame.swift, id "slitherlink"): draw one closed loop so every
 * numbered cell has exactly that many sides on it. Boards are the boundary of a random hole-free blob.
 */
object JungleLoopGame {
    val definition = GameDefinition(
        id = "slitherlink",
        title = "Jungle Loop",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Tap an edge between two dots to draw a segment; tap again for ✕, once more to clear.",
                "Build ONE closed loop with no branches or crossings.",
                "Each numbered cell must have exactly that many of its four sides on the loop.",
                "Finish the loop and satisfy every clue before time runs out.",
            ),
            bulletsVI = listOf(
                "Chạm cạnh giữa hai chấm để vẽ một đoạn; chạm lần nữa thành ✕, thêm lần nữa để xóa.",
                "Tạo MỘT vòng khép kín, không rẽ nhánh, không cắt nhau.",
                "Mỗi ô có số phải có đúng bấy nhiêu cạnh (trong bốn cạnh) nằm trên vòng.",
                "Hoàn thành vòng và thỏa mọi gợi ý trước khi hết giờ.",
            ),
            liveDemo = true
        ),
        prefetch = { level -> BoardCache.prefetch(key(level)) { SLGen.makePuzzle(gridN(level), keepFrac(level)) } },
        content = { level, onWin, onFail -> JungleLoopView(level, onWin, onFail) }
    )

    fun key(level: Int) = BoardCache.key("slitherlink", level)
    fun gridN(level: Int) = intArrayOf(3, 4, 4, 5, 5, 6, 6)[min(level, 7) - 1]
    fun keepFrac(level: Int) = doubleArrayOf(1.0, 0.85, 0.70, 0.60, 0.50, 0.45, 0.38)[min(level, 7) - 1]
    fun timeLimit(level: Int) = doubleArrayOf(70.0, 100.0, 130.0, 160.0, 190.0, 220.0, 250.0)[min(level, 7) - 1]
}

data class SLCell(val r: Int, val c: Int)
class SlitherPuzzle(val n: Int, val clues: List<List<Int?>>)

/** An edge: horizontal (dot(r,c)→dot(r,c+1)) or vertical (dot(r,c)→dot(r+1,c)). */
private data class SLEdge(val horizontal: Boolean, val r: Int, val c: Int)

/** Generation: grow a simply-connected blob; its boundary is exactly one loop (iOS makePuzzle). */
object SLGen {
    private val dirs = listOf(-1 to 0, 1 to 0, 0 to -1, 0 to 1)

    fun makePuzzle(n: Int, keepFrac: Double): SlitherPuzzle {
        repeat(300) {
            val blob = growBlob(n)
            if (blob.isEmpty() || blob.size >= n * n || !simplyConnected(blob, n)) return@repeat
            val full = fullClues(blob, n)
            val boundaryCells = full.sumOf { row -> row.count { it > 0 } }
            if (boundaryCells < max(4, n)) return@repeat
            val cells = (0 until n).flatMap { r -> (0 until n).map { c -> SLCell(r, c) } }.shuffled()
            val keepK = max(3, (n * n * keepFrac).roundAway())
            val kept = cells.take(keepK).toSet()
            var positives = 0
            val clues = List(n) { r -> List(n) { c ->
                if (SLCell(r, c) in kept) { if (full[r][c] > 0) positives++; full[r][c] } else null
            } }
            if (positives < 3) return@repeat
            return SlitherPuzzle(n, clues)
        }
        return fallback(n)
    }

    private fun growBlob(n: Int): Set<SLCell> {
        val target = rndInt(max(2, n)..max(3, (n * n * 0.6).toInt()))
        val s = mutableSetOf(SLCell(Random.nextInt(n), Random.nextInt(n)))
        while (s.size < target) {
            val cand = mutableListOf<SLCell>()
            for (cell in s) for ((dr, dc) in dirs) {
                val nb = SLCell(cell.r + dr, cell.c + dc)
                if (nb.r in 0 until n && nb.c in 0 until n && nb !in s) cand += nb
            }
            if (cand.isEmpty()) break
            s += cand.pick()
        }
        return s
    }

    /** True if no pocket of non-blob cells is enclosed by the blob. */
    fun simplyConnected(s: Set<SLCell>, n: Int): Boolean {
        val nonCount = n * n - s.size
        if (nonCount == 0) return true
        val seen = mutableSetOf<SLCell>()
        val stack = ArrayDeque<SLCell>()
        for (r in 0 until n) for (c in 0 until n) {
            if (!(r == 0 || c == 0 || r == n - 1 || c == n - 1)) continue
            val cell = SLCell(r, c)
            if (cell !in s && seen.add(cell)) stack.addLast(cell)
        }
        while (stack.isNotEmpty()) {
            val cur = stack.removeLast()
            for ((dr, dc) in dirs) {
                val nb = SLCell(cur.r + dr, cur.c + dc)
                if (nb.r in 0 until n && nb.c in 0 until n && nb !in s && seen.add(nb)) stack.addLast(nb)
            }
        }
        return seen.size == nonCount
    }

    fun fullClues(s: Set<SLCell>, n: Int): List<List<Int>> {
        fun inS(r: Int, c: Int) = r in 0 until n && c in 0 until n && SLCell(r, c) in s
        return List(n) { r -> List(n) { c -> dirs.count { (dr, dc) -> inS(r, c) != inS(r + dr, c + dc) } } }
    }

    private fun fallback(n: Int): SlitherPuzzle {
        val g = max(n, 3)
        val full = fullClues(setOf(SLCell(g / 2, g / 2)), g)
        return SlitherPuzzle(g, full.map { row -> row.map { it } })
    }

    /** One closed loop through every touched dot that satisfies all clues (iOS checkWin). */
    fun isSolved(n: Int, clues: List<List<Int?>>, h: Array<IntArray>, v: Array<IntArray>): Boolean {
        for (r in 0 until n) for (c in 0 until n) {
            val clue = clues[r][c] ?: continue
            val cnt = (if (h[r][c] == 1) 1 else 0) + (if (h[r + 1][c] == 1) 1 else 0) + (if (v[r][c] == 1) 1 else 0) + (if (v[r][c + 1] == 1) 1 else 0)
            if (cnt != clue) return false
        }
        val adj = links(n, h, v)
        if (adj.isEmpty()) return false
        if (adj.values.any { it.size != 2 }) return false
        val start = adj.keys.first()
        val seen = mutableSetOf(start)
        val stack = ArrayDeque(listOf(start))
        while (stack.isNotEmpty()) {
            val cur = stack.removeLast()
            for (nb in adj[cur] ?: emptyList()) if (seen.add(nb)) stack.addLast(nb)
        }
        return seen.size == adj.size
    }

    fun links(n: Int, h: Array<IntArray>, v: Array<IntArray>): Map<SLCell, List<SLCell>> {
        val adj = LinkedHashMap<SLCell, MutableList<SLCell>>()
        fun link(a: SLCell, b: SLCell) { adj.getOrPut(a) { mutableListOf() }.add(b); adj.getOrPut(b) { mutableListOf() }.add(a) }
        for (r in 0..n) for (c in 0 until n) if (h[r][c] == 1) link(SLCell(r, c), SLCell(r, c + 1))
        for (r in 0 until n) for (c in 0..n) if (v[r][c] == 1) link(SLCell(r, c), SLCell(r + 1, c))
        return adj
    }
}

private val demoCrosses = listOf(SLEdge(false, 0, 2), SLEdge(true, 1, 2))
private val demoLoop = listOf(
    SLEdge(true, 0, 0), SLEdge(false, 0, 1), SLEdge(true, 1, 1), SLEdge(false, 1, 2), SLEdge(true, 2, 2), SLEdge(false, 2, 3),
    SLEdge(true, 3, 2), SLEdge(true, 3, 1), SLEdge(false, 2, 1), SLEdge(true, 2, 0), SLEdge(false, 1, 0), SLEdge(false, 0, 0),
)

@Composable
private fun JungleLoopView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    var ready by remember { mutableStateOf(false) }
    var playing by remember { mutableStateOf(true) }
    var n by remember { mutableIntStateOf(0) }
    var clues by remember { mutableStateOf<List<List<Int?>>>(emptyList()) }
    var h by remember { mutableStateOf(arrayOf<IntArray>()) }
    var v by remember { mutableStateOf(arrayOf<IntArray>()) }
    var ver by remember { mutableIntStateOf(0) }
    var timeLeft by remember { mutableDoubleStateOf(JungleLoopGame.timeLimit(level)) }
    var demoEdge by remember { mutableStateOf<SLEdge?>(null) }
    val timeLimit = JungleLoopGame.timeLimit(level)
    val tm = rememberTextMeasurer()
    val handP = rememberHand()
    val dens = androidx.compose.ui.platform.LocalDensity.current.density.toDouble()

    fun win() { if (!playing) return; playing = false; onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }
    fun tap(e: SLEdge) {
        if (!playing) return
        if (e.horizontal) h[e.r][e.c] = (h[e.r][e.c] + 1) % 3 else v[e.r][e.c] = (v[e.r][e.c] + 1) % 3
        ver++
        SoundManager.tap(); Haptics.tap()
        if (SLGen.isSolved(n, clues, h, v)) win()
    }
    fun setBoard(pz: SlitherPuzzle) {
        n = pz.n; clues = pz.clues
        h = Array(n + 1) { IntArray(n) }; v = Array(n) { IntArray(n + 1) }
        ver++
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (isActive) {
                setBoard(SlitherPuzzle(3, listOf(listOf(3, 2, 0), listOf(2, 2, 2), listOf(2, 2, 3))))
                demoEdge = null; timeLeft = timeLimit; playing = true; ready = true
                delay(700)
                for ((edge, taps) in demoCrosses.map { it to 2 } + demoLoop.map { it to 1 }) {
                    if (!isActive) return@LaunchedEffect
                    demoEdge = edge
                    repeat(taps) { delay(150); tap(edge) }
                    delay(130)
                }
                demoEdge = null
                delay(1300)
            }
        } else {
            val t0 = System.currentTimeMillis()
            val pz = BoardCache.take(JungleLoopGame.key(level)) { SLGen.makePuzzle(JungleLoopGame.gridN(level), JungleLoopGame.keepFrac(level)) }
            BoardCache.holdBrainstorm(t0, 0.6)
            setBoard(pz)
            ready = true; playing = true; timeLeft = timeLimit
            val start = nowSec()
            while (isActive && playing) {
                delay(50)
                timeLeft = max(0.0, timeLimit - (nowSec() - start))
                if (timeLeft <= 0) { fail(); break }
            }
        }
    }

    if (!ready) { BrainstormingView(rgb(0.12, 0.3, 0.16), rgb(0.04, 0.14, 0.07)); return }

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp)
            .clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .drawBehind { jungleFloor() }
    ) {
        if (!isDemo) {
            Canvas(Modifier.fillMaxWidth().padding(horizontal = 36.dp).padding(top = 10.dp).height(22.dp)) { bamboo(timeLeft / timeLimit) }
        }
        val pad = if (isDemo) 18.0 else 30.0
        Canvas(
            Modifier.fillMaxWidth().weight(1f).padding(top = if (isDemo) 0.dp else 8.dp)
                .then(if (isDemo) Modifier else Modifier.tapIn(n) { p, w, hh ->
                    val padPx = pad * dens
                    val cell = if (n > 0) min((w - 2 * padPx) / n, (hh - 2 * padPx) / n) else 0.0
                    val ox = (w - cell * n) / 2; val oy = (hh - cell * n) / 2
                    edgeAt(p, n, cell, ox, oy)?.let { tap(it) }
                })
        ) {
            ver
            val u = density.toDouble()
            val padPx = pad * u
            val w = size.width.toDouble(); val hh = size.height.toDouble()
            if (n <= 0 || h.size != n + 1 || v.size != n) return@Canvas
            val cell = min((w - 2 * padPx) / n, (hh - 2 * padPx) / n)
            val ox = (w - cell * n) / 2; val oy = (hh - cell * n) / 2
            drawBoard(tm, n, clues, h, v, cell, ox, oy, min(cell * 0.38, padPx - 6 * u))
            val e = demoEdge
            if (e != null) {
                val mx = if (e.horizontal) ox + (e.c + 0.5) * cell else ox + e.c * cell
                val my = if (e.horizontal) oy + e.r * cell else oy + (e.r + 0.5) * cell
                val len = cell * 0.9 + 8 * u; val thick = max(3 * u, cell * 0.09) + 14 * u
                val rw = if (e.horizontal) len else thick; val rh = if (e.horizontal) thick else len
                rrectStroke(mx - rw / 2, my - rh / 2, rw, rh, min(rw, rh) / 2, Color.White, 2.5 * u)
                val hw = cell * 0.36
                hand(handP, mx + cell * 0.02, my + cell * 0.04, hw)
            }
        }
    }
}

/** Hit areas: 0.9 cell along an edge × 0.5 cell across it; vertical edges first (they sat on top). */
private fun edgeAt(p: P, n: Int, cell: Double, ox: Double, oy: Double): SLEdge? {
    if (n <= 0 || cell <= 0) return null
    val fx = (p.x - ox) / cell; val fy = (p.y - oy) / cell
    val vc = fx.roundAway(); val vr = floor(fy).toInt()
    if (vc in 0..n && vr in 0 until n && abs(fx - vc) <= 0.25 && abs(fy - (vr + 0.5)) <= 0.45) return SLEdge(false, vr, vc)
    val hr = fy.roundAway(); val hc = floor(fx).toInt()
    if (hr in 0..n && hc in 0 until n && abs(fy - hr) <= 0.25 && abs(fx - (hc + 0.5)) <= 0.45) return SLEdge(true, hr, hc)
    return null
}

// Jungle snake art (iOS SnakeArt).

private val skin = rgb(0.36, 0.68, 0.22)
private val skinDark = rgb(0.12, 0.34, 0.1)
private val pattern = rgb(0.93, 0.84, 0.3)

private fun hash(n: Double): Double { val v = kotlin.math.sin(n * 12.9898) * 43758.5453; return v - floor(v) }

private fun DrawScope.drawBoard(tm: TextMeasurer, n: Int, clues: List<List<Int?>>, h: Array<IntArray>, v: Array<IntArray>,
                                cell: Double, ox: Double, oy: Double, rim: Double) {
    val u = density.toDouble()
    fun dot(r: Int, c: Int) = P(ox + c * cell, oy + r * cell)
    clearing(ox - rim, oy - rim, cell * n + 2 * rim, cell * n + 2 * rim, cell)
    val guide = Path()
    for (r in 0..n) { val a = dot(r, 0); val b = dot(r, n); guide.m(a.x, a.y); guide.l(b.x, b.y) }
    for (c in 0..n) { val a = dot(0, c); val b = dot(n, c); guide.m(a.x, a.y); guide.l(b.x, b.y) }
    drawPath(guide, rgb(0.45, 0.33, 0.18, 0.22), style = Stroke(u.f, pathEffect = PathEffect.dashPathEffect(floatArrayOf((3 * u).f, (4 * u).f))))
    for (r in 0 until n) for (c in 0 until n) {
        val clue = clues[r][c] ?: continue
        val cnt = (if (h[r][c] == 1) 1 else 0) + (if (h[r + 1][c] == 1) 1 else 0) + (if (v[r][c] == 1) 1 else 0) + (if (v[r][c + 1] == 1) 1 else 0)
        val state = if (cnt == clue) 1 else if (cnt > clue) 2 else 0
        clueStone(tm, ox + (c + 0.5) * cell, oy + (r + 0.5) * cell, cell, clue, state)
    }
    for (r in 0..n) for (c in 0..n) { val d = dot(r, c); pebble(d.x, d.y, max(2.5 * u, cell * 0.06), r * 31 + c) }
    for (r in 0..n) for (c in 0 until n) if (h[r][c] == 2) twigs(ox + (c + 0.5) * cell, oy + r * cell, cell)
    for (r in 0 until n) for (c in 0..n) if (v[r][c] == 2) twigs(ox + c * cell, oy + (r + 0.5) * cell, cell)
    snakes(SLGen.links(n, h, v), cell) { dot(it.r, it.c) }
}

/** The sunlit patch of earth the puzzle sits in, with a ring of grass around it. */
private fun DrawScope.clearing(x: Double, y: Double, w: Double, h: Double, cell: Double) {
    val u = density.toDouble()
    blurRRect(x, y + cell * 0.06, w, h, cell * 0.45, Color.Black.op(0.35), cell * 0.12)
    rrect(x, y, w, h, cell * 0.45, radial(listOf(rgb(0.93, 0.84, 0.62), rgb(0.8, 0.67, 0.44)), x + w / 2 - w * 0.15, y + h / 2 - h * 0.2, max(w, h) * 0.75))
    val shape = Path().apply { addRoundRect(androidx.compose.ui.geometry.RoundRect(x.f, y.f, (x + w).f, (y + h).f, (cell * 0.45).f, (cell * 0.45).f)) }
    clipPath(shape) {
        val specks = Path()
        val count = (w * h / (90 * u * u)).toInt()
        for (k in 0 until count) {
            val sx = x + hash(k * 1.3) * w; val sy = y + hash(k * 2.9 + 4) * h
            specks.addOval(androidx.compose.ui.geometry.Rect(sx.f, sy.f, (sx + 1.6 * u).f, (sy + 1.2 * u).f))
        }
        drawPath(specks, rgb(0.5, 0.36, 0.2, 0.3))
    }
    val tufts = Path()
    val perimeter = 2 * (w + h)
    val count = (perimeter / max(10 * u, cell * 0.22)).toInt()
    for (k in 0 until count) {
        val t = k.toDouble() / count * perimeter + hash(k.toDouble()) * 6 * u
        val bx: Double; val by: Double; val ix: Double; val iy: Double
        when {
            t < w -> { bx = x + t; by = y; ix = 0.0; iy = 1.0 }
            t < w + h -> { bx = x + w; by = y + t - w; ix = -1.0; iy = 0.0 }
            t < 2 * w + h -> { bx = x + w - (t - w - h); by = y + h; ix = 0.0; iy = -1.0 }
            else -> { bx = x; by = y + h - (t - 2 * w - h); ix = 1.0; iy = 0.0 }
        }
        val len = cell * (0.08 + hash(k + 0.7) * 0.08)
        for (s in listOf(-1.0, 0.0, 1.0)) { tufts.m(bx, by); tufts.l(bx + ix * len + iy * s * len * 0.5, by + iy * len + ix * s * len * 0.5) }
    }
    drawPath(tufts, rgb(0.3, 0.55, 0.2), style = Stroke((1.4 * u).f, cap = StrokeCap.Round))
}

/** A flat river stone with the clue on it — mossy green when met, red when overshot. */
private fun DrawScope.clueStone(tm: TextMeasurer, cx: Double, cy: Double, cell: Double, number: Int, state: Int) {
    val u = density.toDouble()
    val rx = cell * 0.27; val ry = cell * 0.24
    ellipse(cx + cell * 0.02, cy + cell * 0.035, rx, ry, Color.Black.op(0.22))
    val base = when (state) { 1 -> rgb(0.62, 0.78, 0.5); 2 -> rgb(0.93, 0.62, 0.56); else -> rgb(0.8, 0.8, 0.76) }
    ellipse(cx, cy, rx, ry, radial(listOf(base.lit(0.35), base, base.shade(0.2)), cx - rx * 0.35, cy - ry * 0.45, rx * 1.3))
    ellipseStroke(cx, cy, rx, ry, base.shade(0.45).op(0.7), u)
    val ink = when (state) { 1 -> rgb(0.1, 0.36, 0.12); 2 -> rgb(0.72, 0.1, 0.08); else -> rgb(0.22, 0.2, 0.18) }
    text(tm, "$number", cx, cy + cell * 0.01, cell * 0.34, ink, FontWeight.ExtraBold)
}

private fun DrawScope.pebble(px: Double, py: Double, r: Double, seed: Int) {
    val w = r * (1.9 + hash(seed.toDouble()) * 0.5); val h = r * 1.6
    oval(px - w / 2 + 0.8 * density, py - h / 2 + 1.2 * density, w, h, Color.Black.op(0.25))
    drawOval(radial(listOf(gray(0.88), gray(0.55)), px - w * 0.2, py - h * 0.25, w * 0.7), off(px - w / 2, py - h / 2), sz(w, h))
}

/** Two crossed twigs: the "not here" mark. */
private fun DrawScope.twigs(px: Double, py: Double, cell: Double) {
    val u = density.toDouble()
    val k = cell * 0.11
    val x = Path(); x.m(px - k, py - k * 0.9); x.l(px + k, py + k * 0.9); x.m(px + k, py - k * 0.9); x.l(px - k, py + k * 0.9)
    drawPath(x, rgb(0.3, 0.18, 0.08), style = Stroke(max(2.4 * u, cell * 0.05).f, cap = StrokeCap.Round))
    drawPath(x, rgb(0.62, 0.42, 0.22), style = Stroke(max(1.4 * u, cell * 0.03).f, cap = StrokeCap.Round))
}

/** Scaly body along every drawn edge; open chains get a head and a tail; a closed loop bites its own tail. */
private fun DrawScope.snakes(links: Map<SLCell, List<SLCell>>, cell: Double, point: (SLCell) -> P) {
    if (links.isEmpty()) return
    val u = density.toDouble()
    val bw = max(5 * u, cell * 0.17)
    val body = Path()
    val drawn = HashSet<String>()
    for ((a, nbrs) in links) for (b in nbrs) {
        val key = if (a.r < b.r || (a.r == b.r && a.c < b.c)) "${a.r},${a.c}-${b.r},${b.c}" else "${b.r},${b.c}-${a.r},${a.c}"
        if (!drawn.add(key)) continue
        val pa = point(a); val pb = point(b)
        body.m(pa.x, pa.y); body.l(pb.x, pb.y)
    }
    fun st(w: Double, cap: StrokeCap = StrokeCap.Round, effect: PathEffect? = null) = Stroke(w.f, cap = cap, join = StrokeJoin.Round, pathEffect = effect)
    translate((bw * 0.12).f, (bw * 0.22).f) { drawPath(body, Color.Black.op(0.28), style = st(bw + 2 * u)) }
    drawPath(body, skinDark, style = st(bw + 3 * u))
    drawPath(body, skin, style = st(bw))
    drawPath(body, pattern.op(0.85), style = st(bw * 0.42, StrokeCap.Butt, PathEffect.dashPathEffect(floatArrayOf((bw * 0.55).f, (bw * 0.75).f))))
    drawPath(body, Color.White.op(0.18), style = st(bw * 0.18))
    val seen = HashSet<SLCell>()
    val order = compareBy<SLCell>({ it.r }, { it.c })
    for (start in links.keys.sortedWith(order)) {
        if (start in seen) continue
        val comp = mutableListOf<SLCell>()
        val stack = ArrayDeque(listOf(start))
        seen += start
        while (stack.isNotEmpty()) {
            val cur = stack.removeLast()
            comp += cur
            for (nb in links[cur] ?: emptyList()) if (seen.add(nb)) stack.addLast(nb)
        }
        if (comp.any { (links[it]?.size ?: 0) > 2 }) continue
        val ends = comp.filter { links[it]?.size == 1 }.sortedWith(order)
        if (ends.size == 2) {
            val head = ends[0]; val tail = ends[1]
            tailTip(point(tail), point(links[tail]!![0]), bw)
            snakeHead(point(head), point(links[head]!![0]), bw, false)
        } else if (ends.isEmpty()) {
            val top = comp.minWithOrNull(order)
            val prev = top?.let { links[it]?.firstOrNull() }
            if (top != null && prev != null) snakeHead(point(top), point(prev), bw, true)
        }
    }
}

private fun DrawScope.tailTip(p: P, q: P, bw: Double) {
    val dx = p.x - q.x; val dy = p.y - q.y; val len = max(0.001, hypot(dx, dy))
    val ux = dx / len; val uy = dy / len
    val tip = Path()
    tip.m(p.x - uy * bw * 0.5, p.y + ux * bw * 0.5)
    tip.q(p.x + ux * bw * 0.6 - uy * bw * 0.45, p.y + uy * bw * 0.6 + ux * bw * 0.45, p.x + ux * bw * 1.6, p.y + uy * bw * 1.6)
    tip.q(p.x + ux * bw * 0.6 + uy * bw * 0.45, p.y + uy * bw * 0.6 - ux * bw * 0.45, p.x + uy * bw * 0.5, p.y - ux * bw * 0.5)
    tip.close()
    drawPath(tip, skinDark, style = Stroke(3 * density))
    drawPath(tip, skin)
}

/** A friendly cartoon head pointing away from `q`, with eyes and a flicking tongue. */
private fun DrawScope.snakeHead(p: P, q: P, bw: Double, biting: Boolean) {
    val angle = atan2(p.y - q.y, p.x - q.x)
    translate(p.x.f, p.y.f) {
        rotateRad(angle.f, Offset.Zero) {
            val hl = bw * 2.1; val hw = bw * 1.55
            val hx = if (biting) -hl * 0.35 else -hl * 0.15; val hy = -hw / 2
            val maxX = hx + hl
            if (!biting) {
                val tg = Path()
                tg.m(maxX - bw * 0.2, 0.0); tg.l(maxX + bw * 0.7, 0.0)
                tg.m(maxX + bw * 0.7, 0.0); tg.l(maxX + bw * 1.0, -bw * 0.25)
                tg.m(maxX + bw * 0.7, 0.0); tg.l(maxX + bw * 1.0, bw * 0.25)
                drawPath(tg, rgb(0.86, 0.16, 0.2), style = Stroke(max(1.2 * density, bw * 0.16).f, cap = StrokeCap.Round))
            }
            oval(hx, hy, hl, hw, skinDark)
            val i = 1.5 * density
            drawOval(vgrad(listOf(skin.lit(0.2), skin), -hw / 2, hw / 2), off(hx + i, hy + i), sz(hl - 2 * i, hw - 2 * i))
            for (s in listOf(-1.0, 1.0)) {
                val ex = hx + hl * 0.62; val ey = s * hw * 0.26
                val er = bw * 0.36
                circle(ex, ey, er, Color.White)
                oval(ex - er * 0.1, ey - er * 0.55, er * 0.75, er * 1.1, Color.Black)
            }
            oval(maxX - bw * 0.35, -bw * 0.18, bw * 0.12, bw * 0.12, skinDark)
            oval(maxX - bw * 0.35, bw * 0.06, bw * 0.12, bw * 0.12, skinDark)
        }
    }
}

/** Deep jungle around the clearing: leaves and dappled light. */
private fun DrawScope.jungleFloor() {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    drawRect(lin(listOf(rgb(0.1, 0.3, 0.15), rgb(0.04, 0.16, 0.08)), 0.0, 0.0, w, h))
    for (k in 0 until 46) {
        val x = hash(k * 1.7) * w; val y = hash(k * 3.3 + 1) * h
        val len = (26 + hash(k * 5.1) * 44) * u
        val a = hash(k * 7.7) * PI * 2
        translate(x.f, y.f) {
            rotateRad(a.f, Offset.Zero) {
                val leaf = Path(); leaf.m(0.0, 0.0); leaf.q(len * 0.5, -len * 0.34, len, 0.0); leaf.q(len * 0.5, len * 0.34, 0.0, 0.0)
                val tone = 0.22 + hash(k * 9.1) * 0.25
                drawPath(leaf, rgb(tone * 0.45, min(1.0, tone * 1.6), tone * 0.55))
                line(0.0, 0.0, len * 0.9, 0.0, Color.Black.op(0.25), u, StrokeCap.Butt)
            }
        }
    }
    for (k in 0 until 12) {
        val x = hash(k * 11.3) * w; val y = hash(k * 13.7) * h
        val r = (20 + hash(k * 2.1) * 40) * u
        drawOval(radial(listOf(rgb(1.0, 0.95, 0.6, 0.12), Color.Transparent), x, y, r), off(x - r, y - r * 0.7), sz(r * 2, r * 1.4))
    }
}

/** The level clock: a bamboo stalk that shortens toward its left end (and dries out near the end). */
private fun DrawScope.bamboo(frac: Double) {
    val u = density.toDouble()
    val f = max(0.0, min(1.0, frac))
    val len = size.width * f
    if (len <= 1) return
    val sh = size.height.toDouble()
    val h = sh * 0.62
    val y = (sh - h) / 2
    val green = if (frac < 0.3) rgb(0.78, 0.62, 0.24) else rgb(0.42, 0.72, 0.3)
    rrect(0.0, y, len, h, h * 0.35, vgrad(listOf(green.lit(0.3), green, green.shade(0.3)), y, y + h))
    var x = 34 * u
    while (x < len - 4 * u) { rrect(x - 1.5 * u, y - u, 3 * u, h + 2 * u, 1.5 * u, green.shade(0.4)); x += 34 * u }
    rrectStroke(0.0, y, len, h, h * 0.35, green.shade(0.5), u)
    val tx = len - 6 * u; val ty = y
    val leaf = Path(); leaf.m(tx, ty); leaf.q(tx + 4 * u, ty - 9 * u, tx + 14 * u, ty - 7 * u); leaf.q(tx + 11 * u, ty + u, tx, ty)
    drawPath(leaf, green.lit(0.1))
}
