package com.gogs.bananagame.games.berrybalance

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
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
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** Brain — Berry Balance (was "Binairo"; iOS BinairoGame.swift): blueberries vs banana slices on a waffle. */
object BerryBalanceGame {
    val definition = GameDefinition(
        id = "binairo",
        title = "Berry Balance",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Tap a cell to cycle blank → blue → banana → blank; clue cells are locked.",
                "No three of the same colour may sit in a line.",
                "Each row and column needs equal numbers of both colours.",
                "No two rows (or two columns) may be identical; finish before time runs out.",
            ),
            bulletsVI = listOf(
                "Chạm một ô để luân chuyển trống → xanh → chuối → trống; ô gợi ý bị khóa.",
                "Không được có ba ô cùng màu liền nhau trên một hàng.",
                "Mỗi hàng và cột cần số lượng bằng nhau của cả hai màu.",
                "Không hai hàng (hoặc hai cột) nào được giống hệt nhau; hoàn thành trước khi hết giờ.",
            ),
            liveDemo = true
        ),
        prefetch = { level -> BoardCache.prefetch(key(level)) { BinGen.generate(n(level), clueFrac(level)) } },
        content = { level, onWin, onFail -> BerryBalanceView(level, onWin, onFail) }
    )

    fun key(level: Int) = BoardCache.key("binairo", level)
    fun n(level: Int) = listOf(6, 6, 8, 8, 8, 10, 10)[min(level, 7) - 1]
    fun clueFrac(level: Int) = listOf(0.55, 0.48, 0.48, 0.42, 0.38, 0.40, 0.34)[min(level, 7) - 1]
    fun timeLimit(level: Int) = listOf(70.0, 75.0, 85.0, 90.0, 95.0, 105.0, 110.0)[min(level, 7) - 1]
}

class BinairoPuzzle(val n: Int, val value: IntArray, val clues: Set<Int>)

object BinGen {
    fun rowEqual(g: IntArray, a: Int, b: Int, n: Int): Boolean { for (c in 0 until n) if (g[a * n + c] != g[b * n + c]) return false; return true }
    fun colEqual(g: IntArray, a: Int, b: Int, n: Int): Boolean { for (r in 0 until n) if (g[r * n + a] != g[r * n + b]) return false; return true }

    fun canPlace(g: IntArray, r: Int, c: Int, v: Int, n: Int): Boolean {
        if (c >= 2 && g[r * n + c - 1] == v && g[r * n + c - 2] == v) return false
        if (r >= 2 && g[(r - 1) * n + c] == v && g[(r - 2) * n + c] == v) return false
        var rowV = 0; for (cc in 0 until n) if (g[r * n + cc] == v) rowV++
        if (rowV + 1 > n / 2) return false
        var colV = 0; for (rr in 0 until n) if (g[rr * n + c] == v) colV++
        if (colV + 1 > n / 2) return false
        return true
    }

    fun fill(g: IntArray, pos: Int, n: Int): Boolean {
        if (pos == n * n) return true
        val r = pos / n; val c = pos % n
        for (v in listOf(0, 1).shuffled()) {
            if (!canPlace(g, r, c, v, n)) continue
            g[pos] = v
            var ok = true
            if (c == n - 1) for (rr in 0 until r) if (rowEqual(g, rr, r, n)) { ok = false; break }
            if (ok && r == n - 1) for (cc in 0 until c) if (colEqual(g, cc, c, n)) { ok = false; break }
            if (ok && fill(g, pos + 1, n)) return true
            g[pos] = -1
        }
        return false
    }

    fun generate(n: Int, clueFrac: Double): BinairoPuzzle {
        repeat(12) {
            val g = IntArray(n * n) { -1 }
            if (fill(g, 0, n)) {
                val count = max(1, (n * n * clueFrac).toInt())
                val clues = (0 until n * n).shuffled().take(count).toSet()
                return BinairoPuzzle(n, IntArray(n * n) { if (it in clues) g[it] else -1 }, clues)
            }
        }
        val g = IntArray(n * n) { ((it % n) / 2 + it / n) % 2 }
        val clues = (0 until n * n).shuffled().take(n * n / 2).toSet()
        return BinairoPuzzle(n, IntArray(n * n) { if (it in clues) g[it] else -1 }, clues)
    }

    fun lineCorrect(v: IntArray, n: Int, idx: (Int) -> Int): Boolean {
        var count0 = 0
        for (k in 0 until n) {
            val x = v[idx(k)]
            if (x == -1) return false
            if (x == 0) count0++
            if (k >= 2 && x == v[idx(k - 1)] && x == v[idx(k - 2)]) return false
        }
        return count0 == n / 2
    }

    fun isSolved(v: IntArray, n: Int): Boolean {
        if (v.contains(-1)) return false
        for (r in 0 until n) if (!lineCorrect(v, n) { r * n + it }) return false
        for (c in 0 until n) if (!lineCorrect(v, n) { it * n + c }) return false
        for (a in 0 until n) for (b in a + 1 until n) if (rowEqual(v, a, b, n) || colEqual(v, a, b, n)) return false
        return true
    }
}

private val DEMO_SOLUTION = intArrayOf(1, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0)
private val DEMO_CLUES = setOf(1, 2, 3, 4, 6, 7, 9, 11, 13, 16, 17, 18, 21, 22, 23, 24, 25, 28, 31)
private val DEMO_ORDER = listOf(0, 5, 10, 8, 15, 12, 14, 19, 20, 27, 26, 29, 30, 32, 33, 34, 35)

@Composable
private fun BerryBalanceView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val timeLimit = BerryBalanceGame.timeLimit(level)
    var playing by remember { mutableStateOf(true) }
    var ready by remember { mutableStateOf(false) }
    var boardN by remember { mutableIntStateOf(0) }
    var value by remember { mutableStateOf(IntArray(0)) }
    var clues by remember { mutableStateOf(setOf<Int>()) }
    var timeLeft by remember { mutableDoubleStateOf(timeLimit) }
    var demoTap by remember { mutableStateOf<Int?>(null) }
    val handP = rememberHand()
    val blanks = value.count { it == -1 }

    fun win() { if (!playing) return; playing = false; onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }
    fun tapCell(i: Int) {
        if (!playing || i >= value.size || i in clues) return
        value = value.copyOf().also { it[i] = if (it[i] == -1) 0 else if (it[i] == 0) 1 else -1 }
        SoundManager.tap(); Haptics.tap()
        if (value.none { it == -1 } && BinGen.isSolved(value, boardN)) win()
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (isActive) {
                boardN = 6; clues = DEMO_CLUES
                value = IntArray(36) { if (it in DEMO_CLUES) DEMO_SOLUTION[it] else -1 }
                demoTap = null; timeLeft = timeLimit; playing = true; ready = true
                delay(600)
                for (i in DEMO_ORDER) {
                    demoTap = i
                    repeat(DEMO_SOLUTION[i] + 1) { delay(140); tapCell(i) }
                    delay(140)
                }
                demoTap = null
                delay(1300)
            }
        } else {
            val size = BerryBalanceGame.n(level); val frac = BerryBalanceGame.clueFrac(level)
            val t0 = System.currentTimeMillis()
            val pz = BoardCache.take(BerryBalanceGame.key(level)) { BinGen.generate(size, frac) }
            BoardCache.holdBrainstorm(t0, 0.7)
            boardN = pz.n; value = pz.value; clues = pz.clues
            ready = true; playing = true; timeLeft = timeLimit
            val start = nowSec()
            while (isActive && playing) {
                delay(50)
                timeLeft = max(0.0, timeLimit - (nowSec() - start))
                if (timeLeft <= 0) { fail(); break }
            }
        }
    }

    if (!ready) { BrainstormingView(rgb(0.62, 0.18, 0.16), rgb(0.36, 0.08, 0.08)); return }

    Box(Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))) {
        Canvas(Modifier.fillMaxSize()) { gingham() }
        Column(
            Modifier.fillMaxSize().padding(vertical = if (isDemo) 8.dp else 14.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(if (isDemo) 6.dp else 12.dp)
        ) {
            Text(L("$blanks blank", "còn $blanks ô trống"), style = ts(if (isDemo) 15.0 else 20.0, FontWeight.Black, rgb(0.36, 0.16, 0.06)),
                modifier = Modifier.background(Color.White.op(0.85), RoundedCornerShape(50)).padding(horizontal = 14.dp, vertical = if (isDemo) 3.dp else 5.dp))
            if (!isDemo) TimeBar(timeLeft / timeLimit, Modifier.fillMaxWidth().padding(horizontal = 50.dp).height(6.dp),
                fill = if (timeLeft / timeLimit < 0.3) rgb(0.8, 0.1, 0.1) else rgb(0.95, 0.62, 0.1), track = Color.White.op(0.6))
            Canvas(Modifier.fillMaxWidth().weight(1f).padding(horizontal = 8.dp).tapIn(boardN) { p, w, h ->
                if (isDemo || boardN == 0) return@tapIn
                val cell = min(w, h) * 0.94 / boardN
                val ox = (w - cell * boardN) / 2; val oy = (h - cell * boardN) / 2
                val c = floor((p.x - ox) / cell).toInt(); val r = floor((p.y - oy) / cell).toInt()
                if (r in 0 until boardN && c in 0 until boardN) tapCell(r * boardN + c)
            }) {
                val n = boardN
                if (n == 0 || value.size != n * n) return@Canvas
                val w = size.width.toDouble(); val h = size.height.toDouble()
                val cell = min(w, h) * 0.94 / n
                val ox = (w - cell * n) / 2; val oy = (h - cell * n) / 2
                WaffleArt.waffle(this, ox, oy, cell, n)
                for (i in 0 until n * n) {
                    val cx = ox + (i % n + 0.5) * cell; val cy = oy + (i / n + 0.5) * cell
                    if (i in clues) WaffleArt.cream(this, cx, cy, cell * 0.4)
                    when (value[i]) { 0 -> WaffleArt.blueberry(this, cx, cy, cell * 0.3); 1 -> WaffleArt.bananaSlice(this, cx, cy, cell * 0.31) }
                }
                val u = density.toDouble()
                for (r in 0 until n) if (BinGen.lineCorrect(value, n) { r * n + it }) WaffleArt.honey(this, ox + 2 * u, oy + r * cell + 2 * u, cell * n - 4 * u, cell - 4 * u, cell)
                for (c in 0 until n) if (BinGen.lineCorrect(value, n) { it * n + c }) WaffleArt.honey(this, ox + c * cell + 2 * u, oy + 2 * u, cell - 4 * u, cell * n - 4 * u, cell)
                demoTap?.let { i ->
                    val cx = ox + (i % n + 0.5) * cell; val cy = oy + (i / n + 0.5) * cell
                    val s = (cell - 2 * u) * 0.9
                    rrectStroke(cx - s / 2, cy - s / 2, s, s, cell * 0.2 * 0.9, Color.White, 3 * u)
                    val hs = cell * 0.65
                    hand(handP, cx + cell * 0.3 - hs * 0.35, cy + cell * 0.36 - hs * 0.25, hs)
                }
            }
        }
    }
}

private object WaffleArt {
    fun c(r: Double, g: Double, b: Double) = rgb(r, g, b)
    val batter = c(0.9, 0.64, 0.3)

    fun waffle(d: DrawScope, bx: Double, by: Double, cell: Double, n: Int) = with(d) {
        val e = cell * 0.22
        val sx = bx - e; val sy = by - e; val ss = cell * n + 2 * e
        rrect(sx + cell * 0.06, sy + cell * 0.14, ss, ss, cell * 0.5, Color.Black.op(0.35))
        rrect(sx, sy, ss, ss, cell * 0.5, lin(listOf(batter.lit(0.12), batter, c(0.7, 0.42, 0.16)), sx, sy, sx + ss, sy + ss))
        rrectStroke(sx, sy, ss, ss, cell * 0.5, c(0.55, 0.3, 0.1), max(1.0, cell * 0.05))
        for (r in 0 until n) for (col in 0 until n) {
            val px = bx + col * cell + cell * 0.12; val py = by + r * cell + cell * 0.12; val pw = cell * 0.76
            val path = Path().apply { addRoundRect(RoundRect(px.f, py.f, (px + pw).f, (py + pw).f, CornerRadius((cell * 0.1).f))) }
            drawPath(path, lin(listOf(c(0.62, 0.36, 0.13), c(0.8, 0.53, 0.24)), px, py, px + pw, py + pw))
            clipPath(path) { translate((cell * 0.04).f, (cell * 0.05).f) { drawPath(path, Color.Black.op(0.28), style = Stroke((cell * 0.1).f)) } }
            drawPath(path, lin(listOf(c(0.5, 0.27, 0.08), c(1.0, 0.82, 0.52)), px, py, px + pw, py + pw), style = Stroke(max(1.0, cell * 0.035).f))
        }
    }

    fun blueberry(d: DrawScope, px: Double, py: Double, r: Double) = with(d) {
        circle(px + r * 0.1, py + r * 0.16, r, Color.Black.op(0.3))
        circle(px, py, r, radial(listOf(c(0.46, 0.52, 0.8), c(0.2, 0.25, 0.56), c(0.09, 0.1, 0.28)), px - r * 0.35, py - r * 0.4, r * 1.4))
        circle(px - r * 0.3, py - r * 0.2, r * 0.45, Color.White.op(0.12))
        val crown = ArrayList<P>()
        for (k in 0 until 10) {
            val a = k / 10.0 * 2 * PI - PI / 2
            val rr = r * (if (k % 2 == 0) 0.26 else 0.1)
            crown.add(P(px + cos(a) * rr, py - r * 0.18 + sin(a) * rr))
        }
        drawPath(polyPath(crown), c(0.1, 0.1, 0.24))
        circle(px - r * 0.42, py - r * 0.48, r * 0.13, Color.White.op(0.7))
    }

    fun bananaSlice(d: DrawScope, px: Double, py: Double, r: Double) = with(d) {
        circle(px + r * 0.08, py + r * 0.14, r, Color.Black.op(0.25))
        circle(px, py, r, c(0.98, 0.86, 0.45))
        circle(px, py, r * 0.9, radial(listOf(c(1.0, 0.98, 0.86), c(0.99, 0.93, 0.7)), px - r * 0.2, py - r * 0.25, r))
        for (k in 0 until 3) {
            val a = k / 3.0 * 2 * PI - PI / 2
            line(px, py, px + cos(a) * r * 0.36, py + sin(a) * r * 0.36, c(0.9, 0.78, 0.5), r * 0.16)
            circle(px + cos(a) * r * 0.2, py + sin(a) * r * 0.2, r * 0.05, c(0.45, 0.32, 0.18))
        }
        circleStroke(px, py, r, c(0.8, 0.62, 0.25), max(0.8, r * 0.06))
    }

    fun cream(d: DrawScope, px: Double, py: Double, r: Double) = with(d) {
        val puff = Path()
        for (k in 0 until 8) {
            val a = k / 8.0 * 2 * PI
            val qx = px + cos(a) * r * 0.62; val qy = py + sin(a) * r * 0.62
            puff.addOval(androidx.compose.ui.geometry.Rect((qx - r * 0.42).f, (qy - r * 0.42).f, (qx + r * 0.42).f, (qy + r * 0.42).f))
        }
        drawPath(puff, Color.Black.op(0.15))
        drawPath(puff, radial(listOf(Color.White, c(0.96, 0.94, 0.9)), px - r * 0.3, py - r * 0.3, r * 1.2))
        strokePath(puff, c(0.85, 0.8, 0.74), max(0.6, r * 0.04))
    }

    fun honey(d: DrawScope, x: Double, y: Double, w: Double, h: Double, cell: Double) = with(d) {
        rrectStroke(x, y, w, h, cell * 0.3, c(0.85, 0.5, 0.05).op(0.9), max(2.5, cell * 0.1))
        rrectStroke(x, y, w, h, cell * 0.3, c(1.0, 0.82, 0.3), max(1.5, cell * 0.05))
        rrectStroke(x - cell * 0.02, y - cell * 0.02, w, h, cell * 0.3, Color.White.op(0.55), max(0.8, cell * 0.015))
    }
}

private fun DrawScope.gingham() {
    val W = size.width.toDouble(); val H = size.height.toDouble(); val u = density.toDouble()
    drawRect(rgb(0.98, 0.95, 0.9))
    val band = 26 * u
    val red = rgb(0.86, 0.2, 0.2, 0.5)
    var x = 0.0; var k = 0
    while (x < W) { if (k % 2 == 0) rect(x, 0.0, band, H, red); x += band; k++ }
    var y = 0.0; k = 0
    while (y < H) { if (k % 2 == 0) rect(0.0, y, W, band, red); y += band; k++ }
    val r = max(W, H) * 0.75
    drawRect(Brush.radialGradient(0f to Color.Transparent, (W * 0.35 / r).toFloat().coerceIn(0f, 1f) to Color.Transparent, 1f to Color.Black.op(0.28),
        center = off(W / 2, H / 2), radius = r.toFloat()))
}
