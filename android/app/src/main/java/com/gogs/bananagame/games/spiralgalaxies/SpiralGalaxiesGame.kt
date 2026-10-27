package com.gogs.bananagame.games.spiralgalaxies

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/** Brain — Spiral Galaxies (iOS SpiralGalaxiesGame.swift): carve the grid into 180°-symmetric galaxies. */
object SpiralGalaxiesGame {
    val definition = GameDefinition(
        id = "spiral-galaxies",
        title = "Spiral Galaxies",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Split the grid into galaxies — each holds exactly one star.",
                "Every galaxy must look identical when rotated 180° around its star.",
                "Tap a cell to cycle it through the stars it could join; fill the grid before time runs out.",
            ),
            bulletsVI = listOf(
                "Chia lưới thành các thiên hà — mỗi thiên hà chứa đúng một ngôi sao.",
                "Mỗi thiên hà phải giống hệt khi xoay 180° quanh ngôi sao của nó.",
                "Chạm một ô để luân chuyển qua các sao nó có thể thuộc về; lấp đầy lưới trước khi hết giờ.",
            ),
            liveDemo = true
        ),
        prefetch = { level -> BoardCache.prefetch(key(level)) { SGGen.generate(n(level), maxPairs(level)) } },
        content = { level, onWin, onFail -> SpiralGalaxiesView(level, onWin, onFail) }
    )

    fun key(level: Int) = BoardCache.key("spiral-galaxies", level)
    fun n(level: Int) = listOf(5, 6, 6, 7, 7, 8, 8)[min(level, 7) - 1]
    fun maxPairs(level: Int) = listOf(2, 2, 3, 3, 4, 4, 5)[min(level, 7) - 1]
    fun timeLimit(level: Int) = listOf(65.0, 70.0, 75.0, 80.0, 85.0, 85.0, 80.0)[min(level, 7) - 1]
}

/** A tiny seeded SplitMix64 RNG so the manual demo grows the same board every time. */
private class SplitMix(var state: Long) : Random() {
    override fun nextBits(bitCount: Int): Int = (nextLong() ushr (64 - bitCount)).toInt()
    override fun nextLong(): Long {
        state += -0x61c8864680b583ebL
        var z = state
        z = (z xor (z ushr 30)) * -0x40a7b892e31b1a47L
        z = (z xor (z ushr 27)) * -0x6b2fb644ecceee15L
        return z xor (z ushr 31)
    }
}

object SGGen {
    fun mirror(cell: Int, center: Int, n: Int): Int? {
        val r = cell / n; val c = cell % n
        val mr = 2 * (center / n) - r; val mc = 2 * (center % n) - c
        if (mr < 0 || mr >= n || mc < 0 || mc >= n) return null
        return mr * n + mc
    }

    fun orthNeighbors(cell: Int, n: Int): List<Int> {
        val r = cell / n; val c = cell % n
        val out = ArrayList<Int>(4)
        if (r > 0) out.add((r - 1) * n + c)
        if (r < n - 1) out.add((r + 1) * n + c)
        if (c > 0) out.add(r * n + c - 1)
        if (c < n - 1) out.add(r * n + c + 1)
        return out
    }

    /** Grows a symmetric tiling (region per cell) and its star cells. */
    fun tiling(n: Int, maxPairs: Int, rng: Random): Pair<IntArray, List<Int>> {
        val region = IntArray(n * n) { -1 }
        val dots = ArrayList<Int>()
        var rid = 0
        for (seed in (0 until n * n).shuffled(rng)) {
            if (region[seed] != -1) continue
            val center = seed
            region[seed] = rid
            val members = arrayListOf(seed)
            val target = rng.nextInt(2, maxPairs + 2)
            var guard = 0
            while (members.size < target * 2 + 1 && guard < 300) {
                guard++
                val pairs = ArrayList<Pair<Int, Int>>()
                val memberSet = members.toHashSet()
                for (m in members) for (nb in orthNeighbors(m, n)) {
                    if (region[nb] != -1) continue
                    val v = mirror(nb, center, n) ?: continue
                    if (v != nb && region[v] == -1 && v !in memberSet) pairs.add(nb to v)
                }
                if (pairs.isEmpty()) break
                val (u, v) = pairs[rng.nextInt(pairs.size)]
                region[u] = rid; region[v] = rid
                members.add(u); members.add(v)
            }
            dots.add(center)
            rid++
        }
        return region to dots
    }

    fun generate(n: Int, maxPairs: Int): List<Int> {
        var best: List<Int> = (0 until n * n).toList()
        var bestSingletons = Int.MAX_VALUE
        repeat(200) {
            val (region, dots) = tiling(n, maxPairs, Random)
            val sizes = IntArray(dots.size)
            for (v in region) sizes[v]++
            val singletons = sizes.count { it == 1 }
            if (singletons < bestSingletons) { bestSingletons = singletons; best = dots }
            if (singletons <= max(1, n / 3) && dots.size <= (n * n) / 2) return dots
        }
        return best
    }

    fun candidates(n: Int, dots: List<Int>): List<List<Int>> = List(n * n) { i ->
        dots.withIndex().filter { mirror(i, it.value, n) != null }
            .map { (di, center) -> val dr = i / n - center / n; val dc = i % n - center % n; di to dr * dr + dc * dc }
            .sortedBy { it.second }.map { it.first }
    }

    fun isConnected(cells: List<Int>, n: Int): Boolean {
        if (cells.isEmpty()) return true
        val set = cells.toHashSet()
        val seen = hashSetOf(cells[0]); val stack = arrayListOf(cells[0])
        while (stack.isNotEmpty()) {
            val cur = stack.removeAt(stack.size - 1)
            for (nb in orthNeighbors(cur, n)) if (nb in set && seen.add(nb)) stack.add(nb)
        }
        return seen.size == set.size
    }

    fun isSolved(region: IntArray, dots: List<Int>, n: Int): Boolean {
        if (region.contains(-1)) return false
        dots.forEachIndexed { idx, center -> if (region[center] != idx) return false }
        val byDot = HashMap<Int, MutableList<Int>>()
        for (i in 0 until n * n) byDot.getOrPut(region[i]) { ArrayList() }.add(i)
        for ((dotIdx, cells) in byDot) {
            val center = dots[dotIdx]
            val set = cells.toHashSet()
            if (center !in set) return false
            for (x in cells) { val m = mirror(x, center, n) ?: return false; if (m !in set) return false }
            if (!isConnected(cells, n)) return false
        }
        return true
    }

    fun correctCells(region: IntArray, dots: List<Int>, n: Int): Set<Int> {
        val byDot = HashMap<Int, MutableList<Int>>()
        for (i in 0 until n * n) if (region[i] >= 0) byDot.getOrPut(region[i]) { ArrayList() }.add(i)
        val out = HashSet<Int>()
        for ((dotIdx, cells) in byDot) {
            val center = dots[dotIdx]
            val set = cells.toHashSet()
            if (center !in set) continue
            val symmetric = cells.all { x -> mirror(x, center, n)?.let { it in set } ?: false }
            if (symmetric && isConnected(cells, n)) out.addAll(cells)
        }
        return out
    }
}

private val SKY_TOP = rgb(0.07, 0.06, 0.16)
private val SKY_BOTTOM = rgb(0.02, 0.02, 0.07)

@Composable
private fun SpiralGalaxiesView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val timeLimit = SpiralGalaxiesGame.timeLimit(level)
    var playing by remember { mutableStateOf(true) }
    var ready by remember { mutableStateOf(false) }
    var boardN by remember { mutableIntStateOf(0) }
    var dots by remember { mutableStateOf(listOf<Int>()) }
    var region by remember { mutableStateOf(IntArray(0)) }
    var cands by remember { mutableStateOf(listOf<List<Int>>()) }
    var timeLeft by remember { mutableDoubleStateOf(timeLimit) }
    var demoCell by remember { mutableStateOf<Int?>(null) }
    val handP = rememberHand()
    val unclaimed = region.count { it == -1 }

    fun win() { if (!playing) return; playing = false; onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }

    fun tap(i: Int) {
        if (!playing) return
        val cs = cands[i]
        val cur = region[i]
        val next = if (cur == -1) cs.firstOrNull() ?: -1 else {
            val pos = cs.indexOf(cur)
            if (pos >= 0 && pos + 1 < cs.size) cs[pos + 1] else -1
        }
        region = region.copyOf().also { it[i] = next }
        SoundManager.tap(); Haptics.tap()
        if (region.none { it == -1 } && SGGen.isSolved(region, dots, boardN)) win()
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (isActive) {
                val n = 5
                val (sol, ds) = SGGen.tiling(n, 3, SplitMix(0x0B16B00B51234567L))
                boardN = n; dots = ds; region = IntArray(n * n) { -1 }; cands = SGGen.candidates(n, ds)
                ready = true; playing = true; timeLeft = timeLimit
                delay(600)
                for (rid in ds.indices) {
                    val center = ds[rid]
                    val members = (0 until n * n).filter { sol[it] == rid }.sortedWith(compareBy({ if (it == center) 0 else 1 }, { it }))
                    for (i in members) {
                        demoCell = i
                        region = region.copyOf().also { it[i] = rid }
                        delay(110)
                    }
                    delay(120)
                }
                demoCell = null
                if (SGGen.isSolved(region, dots, n)) win()
                delay(1500)
            }
        } else {
            val size = SpiralGalaxiesGame.n(level); val mp = SpiralGalaxiesGame.maxPairs(level)
            val t0 = System.currentTimeMillis()
            val starCells = BoardCache.take(SpiralGalaxiesGame.key(level)) { SGGen.generate(size, mp) }
            BoardCache.holdBrainstorm(t0, 0.7)
            boardN = size; dots = starCells; region = IntArray(size * size) { -1 }
            cands = SGGen.candidates(size, starCells)
            ready = true; playing = true; timeLeft = timeLimit
            val start = nowSec()
            while (isActive && playing) {
                delay(50)
                timeLeft = max(0.0, timeLimit - (nowSec() - start))
                if (timeLeft <= 0) { fail(); break }
            }
        }
    }

    if (!ready) { BrainstormingView(SKY_TOP, SKY_BOTTOM); return }

    Box(Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))) {
        Canvas(Modifier.fillMaxSize()) { spaceBackdrop() }
        Column(
            Modifier.fillMaxSize().padding(vertical = if (isDemo) 8.dp else 14.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(if (isDemo) 6.dp else 12.dp)
        ) {
            Text(L("$unclaimed cells to claim", "còn $unclaimed ô cần chia"),
                style = ts(if (isDemo) 17.0 else 20.0, FontWeight.Black, if (unclaimed == 0) rgb(1.0, 0.85, 0.4) else Color.White))
            if (!isDemo) TimeBar(timeLeft / timeLimit, Modifier.fillMaxWidth().padding(horizontal = 50.dp).height(6.dp))
            Canvas(
                Modifier.fillMaxWidth().weight(1f).padding(horizontal = if (isDemo) 4.dp else 8.dp)
                    .tapIn(boardN) { p, w, h ->
                        if (isDemo || boardN == 0) return@tapIn
                        // geometry mirrors the draw below
                        val cell = min(w, h) * 0.98 / boardN
                        val ox = (w - cell * boardN) / 2; val oy = (h - cell * boardN) / 2
                        val c = ((p.x - ox) / cell).toInt(); val r = ((p.y - oy) / cell).toInt()
                        if (p.x >= ox && p.y >= oy && r in 0 until boardN && c in 0 until boardN) tap(r * boardN + c)
                    }
            ) {
                val n = boardN
                if (n == 0 || region.size != n * n) return@Canvas
                val w = size.width.toDouble(); val h = size.height.toDouble()
                val cell = min(w, h) * 0.98 / n
                val ox = (w - cell * n) / 2; val oy = (h - cell * n) / 2
                drawBoard(n, cell, ox, oy, region, dots)
                demoCell?.let { i ->
                    if (isDemo) hand(handP, ox + (i % n + 0.5) * cell, oy + (i / n + 0.5) * cell + cell * 0.05, cell * 0.62)
                }
            }
        }
    }
}

private fun DrawScope.drawBoard(n: Int, cell: Double, ox: Double, oy: Double, region: IntArray, dots: List<Int>) {
    val u = density.toDouble()
    fun rx(i: Int) = ox + (i % n) * cell
    fun ry(i: Int) = oy + (i / n) * cell
    rrect(ox - 4 * u, oy - 4 * u, cell * n + 8 * u, cell * n + 8 * u, 12 * u, Color.Black.op(0.35))
    val ins = 1.5 * u
    for (i in 0 until n * n) rrectStroke(rx(i) + ins, ry(i) + ins, cell - 2 * ins, cell - 2 * ins, cell * 0.14, Color.White.op(0.08), u)
    for (i in 0 until n * n) {
        val rid = region[i]
        if (rid < 0) continue
        val col = SpaceArt.nebula(rid)
        val sx = rx(dots[rid]) + cell / 2; val sy = ry(dots[rid]) + cell / 2
        val d = hypot(rx(i) + cell / 2 - sx, ry(i) + cell / 2 - sy) / cell
        val strength = max(0.28, 0.62 - 0.1 * d)
        val cx = rx(i) + cell / 2; val cy = ry(i) + cell / 2
        rrect(rx(i) + ins, ry(i) + ins, cell - 2 * ins, cell - 2 * ins, cell * 0.14,
            radial(listOf(col.lit(0.25).op(strength), col.op(strength * 0.7)), cx, cy, cell * 0.7))
    }
    val correct = SGGen.correctCells(region, dots, n)
    val doneRegions = correct.map { region[it] }.toSet()
    for (rid in doneRegions) {
        val clip = Path()
        for (i in 0 until n * n) if (region[i] == rid) clip.addRect(Rect((rx(i) + 1).f, (ry(i) + 1).f, (rx(i) + cell - 1).f, (ry(i) + cell - 1).f))
        clipPath(clip) { SpaceArt.spiral(this, rx(dots[rid]) + cell / 2, ry(dots[rid]) + cell / 2, cell, SpaceArt.nebula(rid), rid) }
    }
    if (correct.isNotEmpty()) {
        val outline = Path()
        for (i in correct) {
            val r = i / n; val c = i % n
            val x0 = ox + c * cell; val y0 = oy + r * cell
            val rg = region[i]
            if (r == 0 || region[(r - 1) * n + c] != rg) { outline.m(x0, y0); outline.l(x0 + cell, y0) }
            if (r == n - 1 || region[(r + 1) * n + c] != rg) { outline.m(x0, y0 + cell); outline.l(x0 + cell, y0 + cell) }
            if (c == 0 || region[r * n + c - 1] != rg) { outline.m(x0, y0); outline.l(x0, y0 + cell) }
            if (c == n - 1 || region[r * n + c + 1] != rg) { outline.m(x0 + cell, y0); outline.l(x0 + cell, y0 + cell) }
        }
        strokePath(outline, Color.White, 2.5 * u)
    }
    dots.forEachIndexed { rid, d -> SpaceArt.star(this, rx(d) + cell / 2, ry(d) + cell / 2, cell, rid in doneRegions) }
}

private object SpaceArt {
    val hues = listOf(rgb(1.0, 0.78, 0.35), rgb(0.35, 0.78, 1.0), rgb(1.0, 0.42, 0.62), rgb(0.66, 0.52, 1.0), rgb(0.42, 0.92, 0.62), rgb(1.0, 0.58, 0.3))
    fun nebula(i: Int) = hues[((i % hues.size) + hues.size) % hues.size]

    fun star(d: DrawScope, px: Double, py: Double, cell: Double, done: Boolean) = with(d) {
        val core = if (done) rgb(1.0, 0.86, 0.35) else Color.White
        val r = cell * 0.16
        circle(px, py, r * 3, radial(listOf(core.op(0.55), core.op(0.0)), px, py, r * 3))
        val glint = Path()
        for ((dx, dy) in listOf(1.0 to 0.0, 0.0 to 1.0)) {
            glint.m(px - dx * r * 2.6, py - dy * r * 2.6); glint.q(px, py, px + dx * r * 2.6, py + dy * r * 2.6)
        }
        strokePath(glint, core.op(0.9), max(1.0, cell * 0.035))
        circle(px, py, r, core)
        circleStroke(px, py, r, Color.Black.op(0.35), 1.0)
    }

    fun spiral(d: DrawScope, px: Double, py: Double, cell: Double, color: Color, seed: Int) = with(d) {
        val turn = seed * 1.3
        for (arm in 0 until 2) {
            val path = Path()
            val pts = ArrayList<P>()
            for (k in 0..60) {
                val th = k / 60.0 * 3.4 * PI
                val r = cell * 0.18 * exp(0.2 * th)
                val a = th + arm * PI + turn
                val qx = px + cos(a) * r; val qy = py + sin(a) * r
                if (k == 0) path.m(qx, qy) else path.l(qx, qy)
                if (k % 9 == 4) pts.add(P(qx, qy))
            }
            strokePath(path, color.lit(0.3).op(0.35), cell * 0.32)
            strokePath(path, color.lit(0.6).op(0.85), max(1.5, cell * 0.08))
            for (q in pts) circle(q.x, q.y, 1.5 * density, Color.White.op(0.9))
        }
    }
}

private fun DrawScope.spaceBackdrop() {
    val W = size.width.toDouble(); val H = size.height.toDouble()
    drawRect(lin(listOf(rgb(0.08, 0.06, 0.2), rgb(0.02, 0.02, 0.07)), 0.0, 0.0, W * 0.3, H))
    for ((p, col) in listOf(Triple(0.2, 0.25, 0.5) to rgb(0.6, 0.2, 0.8), Triple(0.85, 0.7, 0.55) to rgb(0.1, 0.4, 0.9), Triple(0.5, 0.9, 0.4) to rgb(0.9, 0.3, 0.5))) {
        val cx = W * p.first; val cy = H * p.second; val r = max(W, H) * p.third
        circle(cx, cy, r, radial(listOf(col.op(0.18), Color.Transparent), cx, cy, r))
    }
    val u = density.toDouble()
    for (k in 0 until 120) {
        val fx = abs((sin(k * 12.9898) * 43758.5453) % 1.0)
        val fy = abs((sin(k * 78.233) * 24634.6345) % 1.0)
        val r = (0.5 + (k % 4) * 0.35) * u
        oval(fx * W, fy * H, r * 2, r * 2, Color.White.op(0.25 + 0.15 * (k % 3)))
    }
}
