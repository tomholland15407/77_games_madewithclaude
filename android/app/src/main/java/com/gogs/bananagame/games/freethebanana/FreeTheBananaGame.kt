package com.gogs.bananagame.games.freethebanana

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutLinearInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Brain — Free the Banana (was "Klotski"; iOS KlotskiGame.swift): the wooden Huarong Dao set.
 * Drag blocks into the two gaps to work the 2×2 banana block out through the exit notch.
 */
object FreeTheBananaGame {
    val definition = GameDefinition(
        id = "klotski",
        title = "Free the Banana",
        genre = Genre.BRAIN,
        locksFeed = true,
        manual = GameManual(
            bullets = listOf(
                "Drag blocks into the two empty cells — blocks slide only, never rotate.",
                "Work the big 2×2 banana block down to the exit slot at the bottom centre.",
                "Only the clock can beat you, so plan quickly.",
            ),
            bulletsVI = listOf(
                "Kéo các khối vào hai ô trống — khối chỉ trượt, không xoay.",
                "Đưa khối chuối lớn 2×2 xuống ô thoát ở giữa dưới cùng.",
                "Chỉ có đồng hồ mới thắng được bạn, nên hãy tính nhanh.",
            ),
            liveDemo = true
        ),
        prefetch = { level -> BoardCache.prefetch(key(level)) { KlotskiGen.generateStart(fraction(level), level >= 7) } },
        content = { level, onWin, onFail -> FreeTheBananaView(level, onWin, onFail) }
    )

    fun key(level: Int) = BoardCache.key("klotski", level)
    fun fraction(level: Int) = listOf(0.13, 0.25, 0.37, 0.49, 0.62, 0.74, 1.0)[min(level, 7) - 1]
    fun timeLimit(level: Int) = listOf(120.0, 150.0, 180.0, 210.0, 270.0, 330.0, 420.0)[min(level, 7) - 1]

    /** Warms the one-time distance map off-main shortly after launch (iOS `KlotskiGame.prewarm`). */
    @OptIn(kotlinx.coroutines.DelicateCoroutinesApi::class)
    fun prewarm() {
        GlobalScope.launch(Dispatchers.Default) { delay(1500); KlotskiGen.distanceMap }
    }
}

object KlotskiGen {
    const val COLS = 4
    const val ROWS = 5
    val goalCells = intArrayOf(13, 14, 17, 18)

    /** 0 = big (B), 1…4 = vertical, 5 = horizontal, 6…9 = singles. */
    fun pieceClass(id: Int): Char = when (id) { 0 -> 'B'; 1, 2, 3, 4 -> 'V'; 5 -> 'H'; else -> 'S' }

    /** Canonical key: same-shape blocks are interchangeable (3 bits per cell). */
    fun key(occ: IntArray): Long {
        var k = 0L
        for (v in occ) {
            val c = when { v == -1 -> 0L; v == 0 -> 1L; v <= 4 -> 2L; v == 5 -> 3L; else -> 4L }
            k = (k shl 3) or c
        }
        return k
    }

    fun isGoal(occ: IntArray) = goalCells.all { occ[it] == 0 }

    /** Grouped moves: sliding one piece in a straight line by any distance is ONE move. */
    fun neighborsGrouped(occ: IntArray): List<IntArray> {
        val out = ArrayList<IntArray>()
        val ids = occ.filter { it >= 0 }.toSet()
        for (pid in ids) {
            val cells = (0 until ROWS * COLS).filter { occ[it] == pid }
            for ((dr, dc) in listOf(-1 to 0, 1 to 0, 0 to -1, 0 to 1)) {
                var cur = cells
                val work = occ.copyOf()
                while (true) {
                    val shifted = ArrayList<Int>()
                    var ok = true
                    for (cell in cur) {
                        val r = cell / COLS + dr; val c = cell % COLS + dc
                        if (r < 0 || r >= ROWS || c < 0 || c >= COLS) { ok = false; break }
                        shifted.add(r * COLS + c)
                    }
                    if (!ok) break
                    val curSet = cur.toHashSet()
                    if (shifted.any { work[it] != -1 && it !in curSet }) break
                    for (cell in cur) work[cell] = -1
                    for (ni in shifted) work[ni] = pid
                    out.add(work.copyOf())
                    cur = shifted
                }
            }
        }
        return out
    }

    val classic = intArrayOf(1, 0, 0, 2, 1, 0, 0, 2, 3, 5, 5, 4, 3, 6, 7, 4, 8, -1, -1, 9)

    class DistanceMap(val byDistance: Map<Int, List<IntArray>>, val maxDist: Int)

    val distanceMap: DistanceMap by lazy { build() }

    private fun build(): DistanceMap {
        val indexOf = HashMap<Long, Int>()
        val states = ArrayList<IntArray>()
        indexOf[key(classic)] = 0; states.add(classic)
        var head = 0
        while (head < states.size) {
            val st = states[head++]
            for (nx in neighborsGrouped(st)) {
                val k = key(nx)
                if (k !in indexOf) { indexOf[k] = states.size; states.add(nx) }
            }
        }
        val dist = IntArray(states.size) { -1 }
        val queue = ArrayDeque<Int>()
        states.forEachIndexed { i, s -> if (isGoal(s)) { dist[i] = 0; queue.add(i) } }
        while (queue.isNotEmpty()) {
            val i = queue.removeFirst()
            for (nx in neighborsGrouped(states[i])) {
                val j = indexOf[key(nx)] ?: continue
                if (dist[j] == -1) { dist[j] = dist[i] + 1; queue.add(j) }
            }
        }
        val by = HashMap<Int, MutableList<IntArray>>()
        var maxD = 0
        dist.forEachIndexed { i, d -> if (d > 0) { by.getOrPut(d) { ArrayList() }.add(states[i]); maxD = max(maxD, d) } }
        return DistanceMap(by, maxD)
    }

    fun generateStart(fraction: Double, boss: Boolean): IntArray {
        if (boss) return classic.copyOf()
        val map = distanceMap
        val want = max(2, Math.round(map.maxDist * fraction).toInt())
        for (delta in 0..map.maxDist) for (d in listOf(want - delta, want + delta)) {
            if (d < 1 || d > map.maxDist) continue
            map.byDistance[d]?.takeIf { it.isNotEmpty() }?.let { return it.pick().copyOf() }
        }
        return classic.copyOf()
    }
}

private val DEMO_BOARD = intArrayOf(1, 3, 2, 4, 1, 3, 2, 4, -1, 0, 0, 8, -1, 0, 0, 9, 6, 7, 5, 5)
private val DEMO_MOVES = listOf(
    intArrayOf(0, 0, -1, 1), intArrayOf(8, 0, -1, 1), intArrayOf(9, -1, 0, 1), intArrayOf(5, -1, 0, 1), intArrayOf(7, 0, 1, 2), intArrayOf(6, 0, 1, 2),
    intArrayOf(0, 1, 0, 1), intArrayOf(8, 0, -1, 2), intArrayOf(9, 0, -1, 2), intArrayOf(5, -1, 0, 1), intArrayOf(6, -1, 0, 1), intArrayOf(6, 0, 1, 1),
    intArrayOf(0, 0, 1, 1),
)

private class KLayout(w: Double, h: Double, demo: Boolean) {
    val cell: Double; val ox: Double; val oy: Double; val rim: Double; val exitSlide: Double
    init {
        val rimF = 0.3
        val room = if (demo) 0.3 else 0.95
        val byW = w / (4 + rimF * 2 + 0.3)
        val byH = h / (5 + rimF * 2 + room + 0.15)
        cell = max(10.0, floor(min(byW, byH)))
        rim = cell * rimF
        ox = (w - cell * 4) / 2
        oy = (h - cell * (5 + rimF * 2 + room)) / 2 + rim
        exitSlide = if (demo) 0.6 else 1.2
    }
}

@Composable
private fun FreeTheBananaView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val timeLimit = FreeTheBananaGame.timeLimit(level)
    var playing by remember { mutableStateOf(true) }
    var ready by remember { mutableStateOf(false) }
    var occ by remember { mutableStateOf(IntArray(0)) }
    var timeLeft by remember { mutableDoubleStateOf(timeLimit) }
    var demoPiece by remember { mutableStateOf<Int?>(null) }
    var exiting by remember { mutableStateOf(false) }
    var dragPiece by remember { mutableStateOf<Int?>(null) }
    var dragAxis by remember { mutableIntStateOf(0) }
    var dragApplied by remember { mutableIntStateOf(0) }
    var layout by remember { mutableStateOf<KLayout?>(null) }
    val handP = rememberHand()

    fun win() { if (!playing) return; playing = false; onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }

    fun slide(pid: Int, dr: Int, dc: Int): Boolean {
        if (!playing) return false
        val cells = (0 until 20).filter { occ[it] == pid }
        val shifted = ArrayList<Int>()
        for (cell in cells) {
            val r = cell / 4 + dr; val c = cell % 4 + dc
            if (r < 0 || r >= 5 || c < 0 || c >= 4) return false
            shifted.add(r * 4 + c)
        }
        if (shifted.any { occ[it] != -1 && occ[it] != pid }) return false
        val n = occ.copyOf()
        for (cell in cells) n[cell] = -1
        for (ni in shifted) n[ni] = pid
        occ = n
        SoundManager.tap(); Haptics.tap()
        if (KlotskiGen.isGoal(occ)) { exiting = true; win() }
        return true
    }

    fun box(pid: Int): IntArray {
        var minR = 5; var minC = 4; var maxR = -1; var maxC = -1
        for (i in 0 until 20) if (occ[i] == pid) {
            val r = i / 4; val c = i % 4
            minR = min(minR, r); maxR = max(maxR, r); minC = min(minC, c); maxC = max(maxC, c)
        }
        return intArrayOf(minR, minC, maxC - minC + 1, maxR - minR + 1)
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (isActive) {
                occ = DEMO_BOARD.copyOf(); demoPiece = null; exiting = false
                timeLeft = timeLimit; playing = true; ready = true
                delay(600)
                for (m in DEMO_MOVES) {
                    demoPiece = m[0]; delay(180)
                    repeat(m[3]) { slide(m[0], m[1], m[2]); delay(160) }
                    delay(80)
                }
                demoPiece = null
                delay(1300)
            }
        } else {
            val t0 = System.currentTimeMillis()
            val board = BoardCache.take(FreeTheBananaGame.key(level)) { KlotskiGen.generateStart(FreeTheBananaGame.fraction(level), level >= 7) }
            BoardCache.holdBrainstorm(t0, if (level == 1) 1.5 else 0.7)
            occ = board; ready = true; playing = true; timeLeft = timeLimit
            val start = nowSec()
            while (isActive && playing) {
                delay(50)
                timeLeft = max(0.0, timeLimit - (nowSec() - start))
                if (timeLeft <= 0) { fail(); break }
            }
        }
    }

    if (!ready) { BrainstormingView(rgb(0.14, 0.11, 0.09), rgb(0.06, 0.04, 0.03)); return }

    Box(Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))) {
        Canvas(Modifier.fillMaxSize()) { teaTable() }
        Column(Modifier.fillMaxSize().padding(vertical = if (isDemo) 4.dp else 8.dp)) {
            if (!isDemo) Canvas(Modifier.fillMaxWidth().height(34.dp).padding(horizontal = 30.dp).padding(top = 6.dp)) { incense(timeLeft / timeLimit) }
            BoxWithConstraints(
                Modifier.fillMaxWidth().weight(1f).padding(top = 4.dp)
                    .then(if (isDemo) Modifier else Modifier.touchDrag(
                        onStart = { p ->
                            val lay = layout ?: return@touchDrag
                            val c = floor((p.x - lay.ox) / lay.cell).toInt(); val r = floor((p.y - lay.oy) / lay.cell).toInt()
                            dragPiece = if (r in 0 until 5 && c in 0 until 4 && occ[r * 4 + c] >= 0) occ[r * 4 + c] else null
                            dragAxis = 0; dragApplied = 0
                        },
                        onMove = { s, p ->
                            val lay = layout ?: return@touchDrag
                            val pid = dragPiece ?: return@touchDrag
                            if (!playing) return@touchDrag
                            val tx = p.x - s.x; val ty = p.y - s.y
                            if (dragAxis == 0) { if (max(abs(tx), abs(ty)) > lay.cell * 0.25) dragAxis = if (abs(tx) >= abs(ty)) 1 else 2 else return@touchDrag }
                            val t = if (dragAxis == 1) tx else ty
                            val want = (t / lay.cell).roundAway()
                            while (dragApplied < want) { if (if (dragAxis == 1) slide(pid, 0, 1) else slide(pid, 1, 0)) dragApplied++ else break }
                            while (dragApplied > want) { if (if (dragAxis == 1) slide(pid, 0, -1) else slide(pid, -1, 0)) dragApplied-- else break }
                        },
                        onEnd = { _, _ -> dragPiece = null; dragAxis = 0; dragApplied = 0 }
                    ))
            ) {
                val dens = androidx.compose.ui.platform.LocalDensity.current.density
                val lay = remember(constraints.maxWidth, constraints.maxHeight) { KLayout(constraints.maxWidth.toDouble(), constraints.maxHeight.toDouble(), isDemo) }
                layout = lay
                Canvas(Modifier.fillMaxSize()) { tray(lay.cell, lay.ox, lay.oy, lay.rim) }
                val ids = occ.filter { it >= 0 }.toSortedSet()
                for (pid in ids) key(pid) {
                    val b = box(pid)
                    val inset = lay.cell * 0.035
                    val w = b[2] * lay.cell - inset * 2; val h = b[3] * lay.cell - inset * 2
                    val pad = lay.cell * 0.14
                    val px = lay.ox + (b[1] + b[2] / 2.0) * lay.cell; val py = lay.oy + (b[0] + b[3] / 2.0) * lay.cell
                    val ax by animateFloatAsState((px - w / 2 - pad).toFloat(), tween(100, easing = LinearOutSlowInEasing), label = "x")
                    val ay by animateFloatAsState((py - h / 2 - pad).toFloat(), tween(100, easing = LinearOutSlowInEasing), label = "y")
                    val exit by animateFloatAsState(if (pid == 0 && exiting) (lay.cell * lay.exitSlide).toFloat() else 0f,
                        tween(500, delayMillis = 120, easing = FastOutLinearInEasing), label = "e")
                    Canvas(Modifier.offset { IntOffset(ax.roundToInt(), (ay + exit).roundToInt()) }.size(((w + pad * 2) / dens).dp, ((h + pad * 2) / dens).dp)) {
                        block(KlotskiGen.pieceClass(pid), pid, pad, pad, w, h, lay.cell)
                        if (demoPiece == pid) {
                            rrectStroke(pad, pad, w, h, lay.cell * 0.09, Color.White, 3.0 * density)
                            val hs = lay.cell * 0.65
                            hand(handP, pad + w / 2 + lay.cell * 0.12 - hs * 0.35, pad + h / 2 + lay.cell * 0.16 - hs * 0.25, hs)
                        }
                    }
                }
            }
        }
    }
}

private val BURNT = rgb(0.42, 0.23, 0.10)
private val TASSEL = rgb(0.78, 0.14, 0.12)
private val GOLD = rgb(0.93, 0.76, 0.36)

private fun kh(n: Double): Double { val v = sin(n * 12.9898) * 43758.5453; return v - floor(v) }

private fun DrawScope.grain(x: Double, y: Double, w: Double, h: Double, vertical: Boolean, seed: Int, spacing: Double, color: Color, width: Double) {
    val across = if (vertical) w else h
    val along = if (vertical) h else w
    val count = max(3, (across / spacing).toInt())
    for (k in 0 until count) {
        val s = seed * 7.31 + k * 1.73
        val base = (k + 0.2 + kh(s) * 0.6) / count * across
        val amp = spacing * (0.15 + kh(s + 3.1) * 0.35)
        val freq = (1.2 + kh(s + 5.7) * 2.2) / along * PI
        val phase = kh(s + 9.3) * 6.28
        val p = Path()
        for (j in 0..14) {
            val t = j / 14.0 * along
            val o = base + amp * sin(t * freq + phase)
            val px = if (vertical) x + o else x + t; val py = if (vertical) y + t else y + o
            if (j == 0) p.m(px, py) else p.l(px, py)
        }
        strokePath(p, color.op(0.35 + kh(s + 11.9) * 0.5), width * (0.6 + kh(s + 2.2) * 0.9))
    }
}

private fun DrawScope.bevel(x: Double, y: Double, w: Double, h: Double, rad: Double, lw: Double, light: Color, dark: Color) {
    val lit = Path(); lit.m(x + lw / 2, y + h - rad); lit.l(x + lw / 2, y + rad); lit.q(x + lw / 2, y + lw / 2, x + rad, y + lw / 2); lit.l(x + w - rad, y + lw / 2)
    strokePath(lit, light, lw)
    val sh = Path(); sh.m(x + w - lw / 2, y + rad); sh.l(x + w - lw / 2, y + h - rad); sh.q(x + w - lw / 2, y + h - lw / 2, x + w - rad, y + h - lw / 2); sh.l(x + rad, y + h - lw / 2)
    strokePath(sh, dark, lw)
}

private fun rr(x: Double, y: Double, w: Double, h: Double, r: Double) = Path().apply { addRoundRect(RoundRect(x.f, y.f, (x + w).f, (y + h).f, CornerRadius(r.f))) }

private fun DrawScope.block(kind: Char, seed: Int, x: Double, y: Double, w: Double, h: Double, cell: Double) {
    val rad = cell * 0.09
    blurRRect(x + cell * 0.025, y + cell * 0.05, w, h, rad, Color.Black.op(0.5), cell * 0.045)
    if (kind == 'B') { lacquer(x, y, w, h, rad, cell); return }
    val body = rr(x, y, w, h, rad)
    val tint = kh(seed * 3.3) * 0.05
    drawPath(body, lin(listOf(rgb(0.95 - tint, 0.84 - tint, 0.66 - tint), rgb(0.84 - tint, 0.66 - tint, 0.45 - tint)), x, y, x + w, y + h))
    clipPath(body) { grain(x, y, w, h, h >= w, seed, cell * 0.075, rgb(0.66, 0.44, 0.24), max(0.6, cell * 0.012)) }
    bevel(x + 0.5, y + 0.5, w - 1, h - 1, rad, max(1.5, cell * 0.035), Color.White.op(0.55), rgb(0.5, 0.31, 0.14, 0.55))
    strokePath(body, rgb(0.36, 0.22, 0.1, 0.7), 1.0)
    val fx = x + cell * 0.11; val fy = y + cell * 0.11; val fw = w - cell * 0.22; val fh = h - cell * 0.22
    rrectStroke(fx, fy, fw, fh, cell * 0.04, BURNT.op(0.75), max(1.0, cell * 0.018))
    when (kind) { 'V' -> spear(fx, fy, fw, fh, cell); 'H' -> glaive(fx, fy, fw, fh, cell); else -> shield(fx, fy, fw, fh, cell) }
}

private fun DrawScope.spear(fx: Double, fy: Double, fw: Double, fh: Double, cell: Double) {
    val lw = max(1.2, cell * 0.024)
    val cx = fx + fw / 2
    val tipY = fy + fh * 0.07; val baseY = fy + fh * 0.27; val midY = (tipY + baseY) / 2
    val hw = fw * 0.13
    val blade = Path(); blade.m(cx, tipY); blade.q(cx + hw * 2, midY, cx, baseY); blade.q(cx - hw * 2, midY, cx, tipY); blade.close()
    drawPath(blade, BURNT.op(0.16)); strokePath(blade, BURNT, lw)
    line(cx, tipY + fh * 0.025, cx, baseY, BURNT.op(0.7), lw * 0.6, StrokeCap.Butt)
    val gy = baseY + fh * 0.015
    line(cx - fw * 0.16, gy, cx + fw * 0.16, gy, BURNT, lw * 1.3)
    val tuft = Path()
    for (k in -3..3) {
        val dx = k * fw * 0.045
        tuft.m(cx + dx * 0.4, gy + lw); tuft.q(cx + dx * 0.9, gy + fh * 0.05, cx + dx * 1.3, gy + fh * 0.13)
    }
    strokePath(tuft, TASSEL, lw * 0.9)
    val by = fy + fh - fh * 0.075
    line(cx, gy + lw, cx, by, BURNT, lw * 1.2)
    val pr = fw * 0.065
    oval(cx - pr, by - pr * 0.4, pr * 2, pr * 2, BURNT.op(0.2))
    ellipseStroke(cx, by - pr * 0.4 + pr, pr, pr, BURNT, lw * 0.9)
}

private fun DrawScope.glaive(fx: Double, fy: Double, fw: Double, fh: Double, cell: Double) {
    val lw = max(1.2, cell * 0.024)
    val cy = fy + fh / 2 + fh * 0.06
    val x0 = fx + fw * 0.66
    line(fx + fw * 0.07, cy, x0, cy, BURNT, lw * 1.2)
    val tx = fx + fw - fw * 0.03; val ty = fy + fh * 0.1
    val blade = Path()
    blade.m(x0, cy - fh * 0.1); blade.l(x0 + fw * 0.09, cy - fh * 0.12); blade.l(x0 + fw * 0.11, cy - fh * 0.3); blade.l(x0 + fw * 0.14, cy - fh * 0.14)
    blade.q(fx + fw - fw * 0.1, cy - fh * 0.16, tx, ty)
    blade.q(fx + fw - fw * 0.02, cy + fh * 0.34, x0 + fw * 0.02, cy + fh * 0.2); blade.close()
    drawPath(blade, BURNT.op(0.16)); strokePath(blade, BURNT, lw)
    val er = fh * 0.07
    circleStroke(x0 + fw * 0.05, cy + fh * 0.02, er, BURNT, lw * 0.8)
    val tuft = Path()
    for (k in 0..5) {
        val dx = (k - 2) * fw * 0.018
        tuft.m(x0 - fw * 0.02, cy + lw); tuft.q(x0 - fw * 0.01 + dx, cy + fh * 0.16, x0 - fw * 0.05 + dx * 1.6, cy + fh * 0.36)
    }
    strokePath(tuft, TASSEL, lw * 0.9)
    line(fx + fw * 0.07, cy - fh * 0.07, fx + fw * 0.07, cy + fh * 0.07, BURNT, lw * 1.4)
}

private fun DrawScope.shield(fx: Double, fy: Double, fw: Double, fh: Double, cell: Double) {
    val lw = max(1.2, cell * 0.024)
    val cx = fx + fw / 2; val cy = fy + fh / 2
    val R = min(fw, fh) * 0.36
    circle(cx, cy, R, BURNT.op(0.12)); circleStroke(cx, cy, R, BURNT, lw)
    circle(cx, cy, R * 0.6, TASSEL.op(0.55)); circleStroke(cx, cy, R * 0.6, BURNT, lw * 0.8)
    circle(cx, cy, R * 0.2, BURNT)
    for (k in 0 until 4) {
        val a = PI / 4 + k * PI / 2
        circle(cx + cos(a) * R * 0.8, cy + sin(a) * R * 0.8, max(1.0, R * 0.07), BURNT)
    }
}

private fun DrawScope.lacquer(x: Double, y: Double, w: Double, h: Double, rad: Double, cell: Double) {
    val body = rr(x, y, w, h, rad)
    drawPath(body, lin(listOf(rgb(0.84, 0.25, 0.18), rgb(0.56, 0.1, 0.08)), x, y, x + w, y + h))
    clipPath(body) {
        drawOval(radial(listOf(Color.White.op(0.22), Color.White.op(0.0)), x + w * 0.25, y + h * 0.05, w * 0.6), off(x - w * 0.3, y - h * 0.45), sz(w * 1.1, h * 0.9))
    }
    val lw = max(1.2, cell * 0.022)
    rrectStroke(x + cell * 0.1, y + cell * 0.1, w - cell * 0.2, h - cell * 0.2, cell * 0.05, GOLD, lw * 1.3)
    val f2x = x + cell * 0.16; val f2y = y + cell * 0.16; val f2w = w - cell * 0.32; val f2h = h - cell * 0.32
    rrectStroke(f2x, f2y, f2w, f2h, cell * 0.03, GOLD.op(0.8), lw * 0.7)
    val k = cell * 0.22
    for ((sx, sy) in listOf(1.0 to 1.0, -1.0 to 1.0, 1.0 to -1.0, -1.0 to -1.0)) {
        val ox = if (sx > 0) f2x + cell * 0.06 else f2x + f2w - cell * 0.06
        val oy = if (sy > 0) f2y + cell * 0.06 else f2y + f2h - cell * 0.06
        val fret = Path()
        fret.m(ox, oy + sy * k); fret.l(ox, oy); fret.l(ox + sx * k, oy)
        fret.m(ox + sx * k * 0.45, oy + sy * k * 0.45); fret.l(ox + sx * k * 0.45, oy + sy * k * 0.2)
        drawPath(fret, GOLD, style = Stroke(lw.f, cap = StrokeCap.Square))
    }
    val br = min(w, h) * 0.3
    blurOval(x + w / 2 + br * 0.04 - br, y + h / 2 + br * 0.18 + cell * 0.03 - br * 0.6, br * 2, br * 1.3, Color.Black.op(0.45), cell * 0.05)
    FruitArt.draw(this, FruitKind.BANANA, x + w / 2 + br * 0.04, y + h / 2 + br * 0.18, br, -12.0)
    bevel(x + 0.5, y + 0.5, w - 1, h - 1, rad, max(1.5, cell * 0.035), rgb(1.0, 0.62, 0.52, 0.7), rgb(0.3, 0.03, 0.02, 0.7))
    strokePath(body, rgb(0.25, 0.03, 0.02, 0.8), 1.0)
}

private fun DrawScope.tray(cell: Double, ox: Double, oy: Double, rim: Double) {
    val bw = cell * 4; val bh = cell * 5
    val outX = ox - rim; val outY = oy - rim; val outW = bw + 2 * rim; val outH = bh + 2 * rim
    val nx = ox + cell; val nw = cell * 2
    blurRRect(outX + rim * 0.1, outY + rim * 0.3, outW, outH, rim * 0.9, Color.Black.op(0.6), rim * 0.45)
    val floorShape = Path().apply {
        addRect(androidx.compose.ui.geometry.Rect(ox.f, oy.f, (ox + bw).f, (oy + bh).f))
        addRect(androidx.compose.ui.geometry.Rect(nx.f, (oy + bh - 1).f, (nx + nw).f, (oy + bh + rim).f))
    }
    drawPath(floorShape, lin(listOf(rgb(0.47, 0.3, 0.18), rgb(0.36, 0.22, 0.12)), ox, oy, ox + bw, oy + bh))
    clipPath(floorShape) {
        grain(ox, oy, bw, bh + rim, true, 42, cell * 0.11, rgb(0.25, 0.14, 0.07), max(0.6, cell * 0.014))
        val sx = ox + cell + cell * 0.09; val sy = oy + cell * 3 + cell * 0.09; val sw = cell * 2 - cell * 0.18
        rrectStroke(sx, sy + 1.2, sw, sw, cell * 0.08, Color.White.op(0.12), max(1.5, cell * 0.03))
        rrectStroke(sx, sy, sw, sw, cell * 0.08, Color.Black.op(0.35), max(1.5, cell * 0.03))
        val s = cell * 0.16
        rect(ox, oy, bw, s, vgrad(listOf(Color.Black.op(0.45), Color.Transparent), oy, oy + s))
        rect(ox, oy, s, bh, hgrad(listOf(Color.Black.op(0.4), Color.Transparent), ox, ox + s))
    }
    val hole = Path()
    hole.m(ox, oy); hole.l(ox + bw, oy); hole.l(ox + bw, oy + bh); hole.l(nx + nw, oy + bh); hole.l(nx + nw, outY + outH + 2)
    hole.l(nx, outY + outH + 2); hole.l(nx, oy + bh); hole.l(ox, oy + bh); hole.close()
    val rimPath = rr(outX, outY, outW, outH, rim * 0.8).apply { addPath(hole); fillType = PathFillType.EvenOdd }
    drawPath(rimPath, lin(listOf(rgb(0.9, 0.68, 0.42), rgb(0.7, 0.47, 0.25)), outX, outY, outX + outW, outY + outH))
    val railGrain = rgb(0.55, 0.33, 0.15)
    clipPath(rimPath) {
        val tb = Path()
        tb.m(outX, outY); tb.l(outX + outW, outY); tb.l(ox + bw, oy); tb.l(ox, oy); tb.close()
        tb.m(outX, outY + outH); tb.l(outX + outW, outY + outH); tb.l(ox + bw, oy + bh); tb.l(ox, oy + bh); tb.close()
        clipPath(tb) { grain(outX, outY, outW, outH, false, 7, rim * 0.22, railGrain, max(0.6, cell * 0.012)) }
        val lr = Path()
        lr.m(outX, outY); lr.l(ox, oy); lr.l(ox, oy + bh); lr.l(outX, outY + outH); lr.close()
        lr.m(outX + outW, outY); lr.l(ox + bw, oy); lr.l(ox + bw, oy + bh); lr.l(outX + outW, outY + outH); lr.close()
        clipPath(lr) { grain(outX, outY, outW, outH, true, 13, rim * 0.22, railGrain, max(0.6, cell * 0.012)) }
    }
    for ((o, b) in listOf(P(outX, outY) to P(ox, oy), P(outX + outW, outY) to P(ox + bw, oy), P(outX, outY + outH) to P(ox, oy + bh), P(outX + outW, outY + outH) to P(ox + bw, oy + bh))) {
        val k = rim * 0.25
        val dx = if (b.x > o.x) k else -k; val dy = if (b.y > o.y) k else -k
        line(o.x + dx, o.y + dy, b.x, b.y, rgb(0.45, 0.26, 0.1, 0.6), 1.0, StrokeCap.Butt)
    }
    rrectStroke(outX + 1, outY + 1, outW - 2, outH - 2, rim * 0.75, Color.White.op(0.35), 1.5)
    strokePath(hole, rgb(0.3, 0.16, 0.06, 0.85), 1.5)
    rect(nx, oy + bh + rim - 1.5, nw, 1.5, rgb(0.2, 0.11, 0.05))
    for (x in listOf(nx, nx + nw)) {
        val ww = rim * 0.14
        rect(if (x == nx) x - ww else x, oy + bh, ww, rim, rgb(0.55, 0.33, 0.16, 0.8))
    }
}

private fun DrawScope.teaTable() {
    val W = size.width.toDouble(); val H = size.height.toDouble(); val u = density.toDouble()
    rect(0.0, 0.0, W, H, vgrad(listOf(rgb(0.24, 0.15, 0.09), rgb(0.13, 0.08, 0.05)), 0.0, H))
    val plank = 64 * u
    var y = 0.0; var k = 0
    while (y < H) {
        clipRect(0f, y.f, W.f, (y + plank).f) { grain(0.0, y, W, plank, false, 100 + k, 7 * u, rgb(0.07, 0.04, 0.02), 0.8 * u) }
        rect(0.0, y + plank - 1.5 * u, W, 1.5 * u, Color.Black.op(0.45))
        y += plank; k++
    }
}

private fun DrawScope.incense(frac: Double) {
    val W = size.width.toDouble(); val h = size.height.toDouble(); val u = density.toDouble()
    val y = h * 0.74; val x0 = h * 0.7
    val maxLen = W - x0 - h * 0.2
    val f = frac.coerceIn(0.0, 1.0)
    val tip = x0 + maxLen * f
    val low = frac < 0.3
    drawLine(gray(0.6).op(0.3), off(tip + 3 * u, y + h * 0.1), off(x0 + maxLen, y + h * 0.1), (1.5 * u).f,
        pathEffect = PathEffect.dashPathEffect(floatArrayOf((2 * u).f, (5 * u).f)))
    line(x0 - h * 0.25, y, tip, y, rgb(0.55, 0.24, 0.14), h * 0.16, StrokeCap.Butt)
    line(x0 - h * 0.25, y, tip, y, Color.White.op(0.18), h * 0.03, StrokeCap.Butt)
    val gr = h * (if (low) 0.5 else 0.36)
    val ember = if (low) rgb(1.0, 0.25, 0.08) else rgb(1.0, 0.55, 0.16)
    circle(tip, y, gr, radial(listOf(ember.op(0.75), ember.op(0.0)), tip, y, gr))
    circle(tip, y, h * 0.08, rgb(1.0, 0.85, 0.5))
    val smoke = Path(); smoke.m(tip, y - h * 0.1); smoke.c(tip - h * 0.3, y - h * 0.35, tip + h * 0.35, h * 0.3, tip + h * 0.1, h * 0.02)
    drawPath(smoke, vgrad(listOf(Color.White.op(0.45), Color.White.op(0.0)), y, 0.0), style = Stroke((1.6 * u).f, cap = StrokeCap.Round))
    rrect(0.0, y - h * 0.08, x0 * 0.95, h * 0.3, h * 0.12, vgrad(listOf(rgb(0.86, 0.64, 0.3), rgb(0.5, 0.32, 0.1)), y - h * 0.08, y + h * 0.22))
    oval(x0 * 0.5, y - h * 0.16, h * 0.26, h * 0.26, rgb(0.62, 0.4, 0.14))
}
