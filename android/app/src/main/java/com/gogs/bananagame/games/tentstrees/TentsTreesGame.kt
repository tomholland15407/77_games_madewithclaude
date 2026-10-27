package com.gogs.bananagame.games.tentstrees

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
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
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/**
 * Brain — Tents & Trees (iOS TentsTreesGame.swift, id "tents-trees"): pitch one tent orthogonally
 * beside every tree; tents never touch (even diagonally) and match the row/column totals. Tap cycles
 * empty → tent → grass → empty. Boards are built solved-first, so a solution always exists.
 */
object TentsTreesGame {
    val definition = GameDefinition(
        id = "tents-trees",
        title = "Tents & Trees",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Tap a cell to cycle empty → tent → grass → empty.",
                "Give every tree exactly one tent orthogonally beside it (one tent per tree).",
                "Two tents may never touch, even diagonally.",
                "Match the tent totals on each row and column; solve the grid before time runs out.",
            ),
            bulletsVI = listOf(
                "Chạm một ô để luân chuyển trống → lều → cỏ → trống.",
                "Mỗi cây phải có đúng một lều kề bên (một lều cho mỗi cây).",
                "Hai lều không bao giờ được chạm nhau, kể cả theo đường chéo.",
                "Khớp tổng số lều ở mỗi hàng và cột; giải lưới trước khi hết giờ.",
            ),
            liveDemo = true
        ),
        prefetch = { level -> BoardCache.prefetch(key(level)) { TentsGen.generate(n(level), tentTarget(level)) } },
        content = { level, onWin, onFail -> TentsTreesView(level, onWin, onFail) }
    )

    fun key(level: Int) = BoardCache.key("tents-trees", level)
    fun n(level: Int) = listOf(5, 6, 6, 7, 7, 8, 8)[min(level, 7) - 1]
    fun tentTarget(level: Int) = listOf(4, 6, 7, 9, 10, 12, 13)[min(level, 7) - 1]
    fun timeLimit(level: Int) = listOf(70.0, 75.0, 80.0, 85.0, 85.0, 80.0, 75.0)[min(level, 7) - 1]
}

class TentsBoard(val n: Int, val trees: List<Int>, val rowCounts: List<Int>, val colCounts: List<Int>)

object TentsGen {
    fun orthNeighbors(cell: Int, n: Int): List<Int> {
        val r = cell / n; val c = cell % n
        val out = ArrayList<Int>(4)
        if (r > 0) out.add((r - 1) * n + c)
        if (r < n - 1) out.add((r + 1) * n + c)
        if (c > 0) out.add(r * n + c - 1)
        if (c < n - 1) out.add(r * n + c + 1)
        return out
    }

    fun eightNeighbors(cell: Int, n: Int): List<Int> {
        val r = cell / n; val c = cell % n
        val out = ArrayList<Int>(8)
        for (dr in -1..1) for (dc in -1..1) {
            if (dr == 0 && dc == 0) continue
            val nr = r + dr; val nc = c + dc
            if (nr in 0 until n && nc in 0 until n) out.add(nr * n + nc)
        }
        return out
    }

    fun generate(n: Int, tentTarget: Int): TentsBoard {
        repeat(400) {
            // 1) scatter non-touching tents
            val tents = mutableListOf<Int>(); val blocked = HashSet<Int>()
            for (cell in (0 until n * n).shuffled()) {
                if (tents.size == tentTarget) break
                if (cell in blocked) continue
                tents.add(cell); blocked.add(cell); blocked.addAll(eightNeighbors(cell, n))
            }
            if (tents.size != tentTarget) return@repeat
            // 2) give each tent its own adjacent tree
            val tentSet = tents.toSet(); val trees = HashSet<Int>(); var ok = true
            for (tent in tents.shuffled()) {
                val options = orthNeighbors(tent, n).filter { it !in tentSet && it !in trees }
                if (options.isEmpty()) { ok = false; break }
                trees.add(options.pick())
            }
            if (!ok || trees.size != tentTarget) return@repeat
            // 3) read off the row/column totals
            val rows = IntArray(n); val cols = IntArray(n)
            for (t in tents) { rows[t / n]++; cols[t % n]++ }
            return TentsBoard(n, trees.toList(), rows.toList(), cols.toList())
        }
        // Fallback: trees down the first column, tents to their right.
        val trees = mutableListOf<Int>(); val rows = IntArray(n); val cols = IntArray(n)
        for (r in 0 until min(tentTarget, n)) { trees.add(r * n); rows[r]++; cols[min(1, n - 1)]++ }
        return TentsBoard(n, trees, rows.toList(), cols.toList())
    }
}

// Demo: a fixed 5×5 board with a unique solution, solved by deduction through the real tap (grass
// marks included); the 4th tent is the real win (see the iOS comment for the reasoning).
private val demoTrees = setOf(8, 11, 19, 22)
private val demoRows = listOf(0, 1, 1, 0, 2)
private val demoCols = listOf(1, 1, 1, 0, 1)
private val demoMoves = listOf(23 to 2, 24 to 1, 21 to 1, 9 to 2, 7 to 1, 12 to 2, 10 to 1)

/** Grid geometry (iOS TTGrid): square cells, 3 pt gaps, clue strips 0.6 of a cell, centred. */
private class TTLayout(w: Double, h: Double, val n: Int, u: Double) {
    val gap = 3 * u
    val cell = if (n > 0) floor(min((w - gap * n - 12 * u) / (n + 0.6), (h - gap * n) / (n + 0.6))) else 0.0
    val strip = cell * 0.6
    val ox = (w - (strip + n * (cell + gap))) / 2
    val oy = (h - (strip + n * (cell + gap))) / 2
    fun cx(c: Int) = ox + strip + gap + c * (cell + gap)
    fun cy(r: Int) = oy + strip + gap + r * (cell + gap)
    fun hit(p: P): Int? {
        if (n == 0) return null
        for (r in 0 until n) for (c in 0 until n)
            if (p.x >= cx(c) && p.x < cx(c) + cell && p.y >= cy(r) && p.y < cy(r) + cell) return r * n + c
        return null
    }
}

@Composable
private fun TentsTreesView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val timeLimit = TentsTreesGame.timeLimit(level)
    var playing by remember { mutableStateOf(true) }
    var ready by remember { mutableStateOf(false) }
    var boardN by remember { mutableIntStateOf(0) }
    var trees by remember { mutableStateOf(setOf<Int>()) }
    var tents by remember { mutableStateOf(setOf<Int>()) }
    var grass by remember { mutableStateOf(setOf<Int>()) }
    var rowCounts by remember { mutableStateOf(listOf<Int>()) }
    var colCounts by remember { mutableStateOf(listOf<Int>()) }
    var timeLeft by remember { mutableDoubleStateOf(timeLimit) }
    var demoCell by remember { mutableStateOf<Int?>(null) }
    val tm = rememberTextMeasurer()
    val handP = rememberHand()
    val dens = LocalDensity.current.density.toDouble()

    fun win() { if (!playing) return; playing = false; onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }

    fun hasPerfectMatching(): Boolean {
        val tentList = tents.toList(); val treeList = trees.toList()
        val treeIndex = treeList.withIndex().associate { (i, t) -> t to i }
        val adj = tentList.map { t -> TentsGen.orthNeighbors(t, boardN).mapNotNull { treeIndex[it] } }
        val matchTree = IntArray(treeList.size) { -1 }
        fun augment(u: Int, visited: BooleanArray): Boolean {
            for (v in adj[u]) if (!visited[v]) {
                visited[v] = true
                if (matchTree[v] == -1 || augment(matchTree[v], visited)) { matchTree[v] = u; return true }
            }
            return false
        }
        var matched = 0
        for (u in tentList.indices) if (augment(u, BooleanArray(treeList.size))) matched++
        return matched == tentList.size
    }

    fun isSolved(): Boolean {
        val n = boardN
        if (tents.size != trees.size) return false
        for (r in 0 until n) if (tents.count { it / n == r } != rowCounts[r]) return false
        for (c in 0 until n) if (tents.count { it % n == c } != colCounts[c]) return false
        for (t in tents) if (TentsGen.eightNeighbors(t, n).any { it in tents }) return false
        return hasPerfectMatching()
    }

    fun tap(idx: Int) {
        if (!playing || idx in trees) return
        when (idx) {
            in tents -> { tents = tents - idx; grass = grass + idx }
            in grass -> grass = grass - idx
            else -> tents = tents + idx
        }
        SoundManager.tap(); Haptics.tap()
        if (isSolved()) win()
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (isActive) {
                boardN = 5; trees = demoTrees; tents = emptySet(); grass = emptySet()
                rowCounts = demoRows; colCounts = demoCols; demoCell = null
                timeLeft = timeLimit; playing = true; ready = true
                delay(800)
                for ((cell, taps) in demoMoves) {
                    demoCell = cell
                    delay(250)
                    for (k in 0 until taps) { if (k > 0) delay(220); tap(cell) }
                    delay(350)
                }
                demoCell = null
                delay(1300)
            }
        } else {
            val t0 = System.currentTimeMillis()
            val b = BoardCache.take(TentsTreesGame.key(level)) { TentsGen.generate(TentsTreesGame.n(level), TentsTreesGame.tentTarget(level)) }
            BoardCache.holdBrainstorm(t0, 0.7)
            boardN = b.n; trees = b.trees.toSet(); tents = emptySet(); grass = emptySet()
            rowCounts = b.rowCounts; colCounts = b.colCounts
            ready = true; playing = true; timeLeft = timeLimit
            val start = nowSec()
            while (isActive && playing) {
                delay(50)
                timeLeft = max(0.0, timeLimit - (nowSec() - start))
                if (timeLeft <= 0) { fail(); break }
            }
        }
    }

    if (!ready) { BrainstormingView(rgb(0.09, 0.15, 0.13), rgb(0.03, 0.06, 0.05)); return }

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .drawBehind { rect(0.0, 0.0, size.width.toDouble(), size.height.toDouble(), vgrad(listOf(rgb(0.99, 0.91, 0.83), rgb(0.96, 0.84, 0.74)), 0.0, size.height.toDouble())) }
            .padding(vertical = if (isDemo) 6.dp else 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(if (isDemo) 4.dp else 12.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Canvas(Modifier.size(if (isDemo) 18.dp else 24.dp, if (isDemo) 15.dp else 20.dp)) { tent(0.0, 0.0, size.width.toDouble(), size.height.toDouble()) }
            Text("${tents.size}/${trees.size}", style = ts(if (isDemo) 15.0 else 20.0, FontWeight.Black, TTInk).copy(fontFeatureSettings = "tnum"))
        }
        if (!isDemo) {
            val f = if (timeLimit > 0) timeLeft / timeLimit else 0.0
            TimeBar(f, Modifier.fillMaxWidth().padding(horizontal = 50.dp).height(6.dp),
                fill = if (f < 0.3) rgb(0.86, 0.25, 0.2) else rgb(0.4, 0.62, 0.24), track = TTInk.op(0.14))
        }
        Canvas(Modifier.fillMaxWidth().weight(1f).then(if (isDemo) Modifier else Modifier.tapIn(boardN) { p, w, h ->
            TTLayout(w, h, boardN, dens).hit(p)?.let { tap(it) }
        })) {
            val u = density.toDouble()
            val n = boardN
            val g = TTLayout(size.width.toDouble(), size.height.toDouble(), n, u)
            val cell = g.cell
            if (n == 0 || cell <= 0) return@Canvas
            for (c in 0 until n) {
                val cur = tents.count { it % n == c }; val target = colCounts.getOrElse(c) { 0 }
                text(tm, "$target", g.cx(c) + cell / 2, g.oy + g.strip / 2, cell * 0.44, clueColor(cur, target), FontWeight.ExtraBold)
            }
            for (r in 0 until n) {
                val cur = tents.count { it / n == r }; val target = rowCounts.getOrElse(r) { 0 }
                text(tm, "$target", g.ox + g.strip / 2, g.cy(r) + cell / 2, cell * 0.44, clueColor(cur, target), FontWeight.ExtraBold)
            }
            for (r in 0 until n) for (c in 0 until n) {
                val idx = r * n + c
                val kind = if (idx in trees) 1 else if (idx in tents) 2 else if (idx in grass) 3 else 0
                plot(g.cx(c), g.cy(r), cell, kind, (r + c) % 2 == 0)
            }
            demoCell?.let { d ->
                val x = g.cx(d % n); val y = g.cy(d / n)
                rrectStroke(x, y, cell, cell, cell * 0.12, TTInk, 2.5 * u)
                hand(handP, x + cell * 0.57, y + cell * 0.63, cell * 0.46)
            }
        }
    }
}

// Campsite art (after Frozax's Tents and Trees; iOS TTArt).

private val TTInk = rgb(0.3, 0.27, 0.25)
private val TTMet = rgb(0.36, 0.6, 0.24)
private val TTOver = rgb(0.86, 0.25, 0.2)
private fun clueColor(cur: Int, target: Int) = if (cur == target) TTMet else if (cur > target) TTOver else TTInk

private fun quad(ax: Double, ay: Double, bx: Double, by: Double, cx: Double, cy: Double, dx: Double, dy: Double) =
    polyPath(ax, ay, bx, by, cx, cy, dx, dy)

/** A little red tent (a prism seen from the front-left) filling the rect. */
private fun DrawScope.tent(x: Double, y: Double, w: Double, h: Double) {
    fun px(fx: Double) = x + fx * w
    fun py(fy: Double) = y + fy * h
    oval(x + w * 0.1, y + h * 0.82, w * 0.84, h * 0.14, Color.Black.op(0.18))
    fillPath(quad(px(0.42), py(0.1), px(0.64), py(0.04), px(0.94), py(0.8), px(0.72), py(0.88)), rgb(0.66, 0.2, 0.12))
    fillPath(polyPath(px(0.42), py(0.1), px(0.72), py(0.88), px(0.08), py(0.88)), rgb(0.9, 0.34, 0.2))
    fillPath(polyPath(px(0.42), py(0.42), px(0.54), py(0.88), px(0.3), py(0.88)), rgb(0.42, 0.12, 0.07))
}

/** A low-poly tree: three stacked green blocks on a short trunk. */
private fun DrawScope.tree(ox: Double, oy: Double, s: Double) {
    oval(ox + s * 0.22, oy + s * 0.8, s * 0.56, s * 0.12, Color.Black.op(0.18))
    rect(ox + s * 0.44, oy + s * 0.66, s * 0.12, s * 0.2, rgb(0.5, 0.32, 0.16))
    for ((tw, tt, tb) in listOf(Triple(0.6, 0.5, 0.72), Triple(0.44, 0.32, 0.52), Triple(0.28, 0.14, 0.34))) {
        val l = ox + s * (0.5 - tw / 2); val rr = ox + s * (0.5 + tw / 2)
        val top = oy + s * tt; val bottom = oy + s * tb
        val dx = s * 0.07; val dy = s * 0.06
        fillPath(quad(rr, top, rr + dx, top - dy, rr + dx, bottom - dy, rr, bottom), rgb(0.18, 0.44, 0.2))
        fillPath(quad(l, top, l + dx, top - dy, rr + dx, top - dy, rr, top), rgb(0.5, 0.8, 0.38))
        rect(l, top, rr - l, bottom - top, rgb(0.3, 0.62, 0.28))
    }
}

/** One plot: 0 undecided (dark), 1 tree, 2 tent, 3 grass mark (lime with tufts). */
private fun DrawScope.plot(x: Double, y: Double, s: Double, kind: Int, alt: Boolean) {
    val rad = s * 0.12
    when (kind) {
        0 -> {
            rrect(x, y, s, s, rad, if (alt) rgb(0.26, 0.28, 0.29) else rgb(0.23, 0.25, 0.26))
            rrect(x, y, s, s * 0.12, rad, Color.White.op(0.05))
        }
        3 -> {
            rrect(x, y, s, s, rad, rgb(0.74, 0.87, 0.4))
            val blades = Path()
            for ((fx, fy) in listOf(0.28 to 0.4, 0.66 to 0.34, 0.46 to 0.72)) {
                val bx = x + s * fx; val by = y + s * fy
                for (dx in listOf(-0.07, 0.0, 0.07)) { blades.m(bx, by); blades.l(bx + s * dx, by - s * 0.12) }
            }
            strokePath(blades, rgb(0.46, 0.68, 0.22), max(density.toDouble(), s * 0.035))
        }
        else -> {
            rrect(x, y, s, s, rad, rgb(0.6, 0.8, 0.34))
            if (kind == 1) tree(x + s * 0.02, y + s * 0.02, s * 0.96)
            else tent(x + s * 0.12, y + s * 0.14, s * 0.76, s * 0.72)
        }
    }
}
