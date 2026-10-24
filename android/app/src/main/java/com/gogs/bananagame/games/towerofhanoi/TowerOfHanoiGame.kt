package com.gogs.bananagame.games.towerofhanoi

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
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
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/**
 * Brain — Tower of Hanoi (iOS TowerOfHanoiGame.swift): move the stack onto the brass goal peg, one
 * disk at a time, never larger on smaller, within a move budget that shrinks to the perfect 2ⁿ−1.
 */
object TowerOfHanoiGame {
    val definition = GameDefinition(
        id = "tower-of-hanoi",
        title = "Tower of Hanoi",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Tap a peg to pick up its top disk, then tap another peg to place it.",
                "You can never put a larger disk on a smaller one.",
                "Move the entire stack onto the highlighted goal peg.",
                "Overspend your moves or the clock and you drop to level 1.",
            ),
            bulletsVI = listOf(
                "Chạm một cọc để nhấc đĩa trên cùng, rồi chạm cọc khác để đặt xuống.",
                "Không bao giờ được đặt đĩa lớn lên đĩa nhỏ.",
                "Chuyển toàn bộ chồng đĩa sang cọc mục tiêu được tô sáng.",
                "Dùng quá số nước đi hoặc hết giờ sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> TowerOfHanoiView(level, onWin, onFail) }
    )
}

/** Ellipse height / width for the 3/4 view. */
private const val TILT = 0.26

private val demoMoves = listOf(0 to 2, 0 to 1, 2 to 1, 0 to 2, 1 to 0, 1 to 2, 0 to 2)

@Composable
private fun TowerOfHanoiView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val li = min(level, 7) - 1
    val diskCount = listOf(3, 3, 4, 4, 5, 6, 7)[li]
    val slack = listOf(6, 3, 5, 2, 3, 2, 0)[li]
    val timeLimit = listOf(40.0, 45.0, 60.0, 70.0, 100.0, 140.0, 190.0)[li]
    val budget = (1 shl diskCount) - 1 + slack
    var playing by remember { mutableStateOf(true) }
    var pegs by remember { mutableStateOf(listOf(listOf<Int>(), listOf(), listOf())) }
    var goalPeg by remember { mutableIntStateOf(2) }
    var selected by remember { mutableStateOf<Int?>(null) }
    var movesUsed by remember { mutableIntStateOf(0) }
    var timeLeft by remember { mutableDoubleStateOf(timeLimit) }
    val lift by animateFloatAsState(if (selected != null) 1f else 0f, tween(120), label = "lift")

    fun win() { if (!playing) return; playing = false; onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }

    fun tapPeg(i: Int) {
        if (!playing) return
        val s = selected
        if (s != null) {
            if (s == i) { selected = null; return }
            val moving = pegs[s].lastOrNull() ?: run { selected = null; return }
            val top = pegs[i].lastOrNull()
            if (top != null && top < moving) { SoundManager.error(); Haptics.warning(); selected = null; return }
            pegs = pegs.mapIndexed { k, p -> when (k) { s -> p.dropLast(1); i -> p + moving; else -> p } }
            selected = null
            movesUsed++
            SoundManager.tap(); Haptics.tap()
            if (pegs[goalPeg].size == diskCount) { win(); return }
            if (movesUsed >= budget) fail()
        } else {
            if (pegs[i].isEmpty()) return
            selected = i
            SoundManager.tap()
        }
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (isActive) {
                pegs = listOf(listOf(3, 2, 1), listOf(), listOf()); goalPeg = 2; selected = null
                movesUsed = 0; playing = true; timeLeft = timeLimit
                delay(600)
                for ((from, to) in demoMoves) { tapPeg(from); delay(350); tapPeg(to); delay(500) }
                delay(1100)
            }
        } else {
            val startPeg = Random.nextInt(3)
            var goal = Random.nextInt(3)
            while (goal == startPeg) goal = Random.nextInt(3)
            pegs = List(3) { if (it == startPeg) (diskCount downTo 1).toList() else emptyList() }
            goalPeg = goal; selected = null; movesUsed = 0; playing = true; timeLeft = timeLimit
            val s = nowSec()
            while (isActive && playing) {
                delay(50)
                timeLeft = max(0.0, timeLimit - (nowSec() - s))
                if (timeLeft <= 0) { fail(); break }
            }
        }
    }

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp)
            .clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp)).drawBehind { oakTable() },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(if (isDemo) 4.dp else 10.dp)
    ) {
        Row(Modifier.padding(top = if (isDemo) 8.dp else 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Canvas(Modifier.size(if (isDemo) 22.dp else 28.dp, if (isDemo) 34.dp else 44.dp)) { hourglass(if (timeLimit > 0) timeLeft / timeLimit else 0.0) }
            Box(Modifier.drawBehind { woodPlaque() }.padding(horizontal = 16.dp, vertical = if (isDemo) 5.dp else 8.dp)) {
                Text(L("MOVES  $movesUsed / $budget", "NƯỚC  $movesUsed / $budget"), style = ts(if (isDemo) 17.0 else 20.0, FontWeight.Black,
                    if (budget - movesUsed <= 2) rgb(0.75, 0.1, 0.08) else rgb(0.32, 0.17, 0.07)))
            }
        }
        Canvas(Modifier.fillMaxWidth().weight(1f).then(if (isDemo) Modifier else Modifier.tapIn { p, w, _ -> tapPeg(clampI((p.x / (w / 3)).toInt(), 0, 2)) })) {
            val w = size.width.toDouble(); val h = size.height.toDouble()
            val u = density.toDouble()
            val colW = w / 3
            val n = max(pegs.flatten().maxOrNull() ?: 0, 1)
            val diskH = min(30 * u, h * 0.7 / n)
            val baseY = h * 0.86
            val maxDiskW = colW * 0.86; val minDiskW = maxDiskW * 0.32
            val pegW = max(6 * u, colW * 0.07)
            hanoiStand(w, h, baseY, colW, maxDiskW, pegW, goalPeg)
            for (peg in 0 until 3) {
                val cx = colW * (peg + 0.5)
                val stack = pegs[peg]
                stack.forEachIndexed { idx, sz ->
                    val lifted = selected == peg && idx == stack.size - 1
                    val dw = minDiskW + (maxDiskW - minDiskW) * (sz - 1) / max(n - 1, 1)
                    val restY = baseY - (idx + 0.5) * diskH - 2 * u
                    val y = if (lifted) lerp(restY, baseY - (n + 0.8) * diskH, lift.toDouble()) else restY
                    disk(cx, y, ringColor(sz, n), dw, diskH, pegW, peg == goalPeg, lifted)
                }
            }
        }
    }
}

/** Rainbow rings: the biggest red at the bottom, climbing to violet at the top. */
private fun ringColor(size: Int, n: Int): Color {
    val rainbow = listOf(rgb(0.86, 0.16, 0.16), rgb(0.96, 0.5, 0.1), rgb(0.98, 0.82, 0.14), rgb(0.2, 0.68, 0.3),
        rgb(0.16, 0.5, 0.86), rgb(0.3, 0.26, 0.7), rgb(0.6, 0.3, 0.72))
    val t = (n - size).toDouble() / max(n - 1, 1)
    return rainbow[clampI((t * 6).roundAway(), 0, 6)]
}

private fun hash(n: Double): Double { val v = sin(n * 12.9898) * 43758.5453; return v - kotlin.math.floor(v) }

/** Gentle wavy grain across a rect (clip first). */
private fun DrawScope.grain(x0: Double, y0: Double, w: Double, h: Double, seed: Int, spacing: Double, color: Color) {
    val u = density.toDouble()
    var y = y0; var k = 0
    while (y < y0 + h) {
        val s = (seed * 17 + k).toDouble()
        val p = Path()
        val amp = spacing * (0.2 + hash(s) * 0.4)
        val ph = hash(s + 2) * 6.28
        for (j in 0..16) {
            val x = x0 + w * j / 16
            val py = y + amp * sin((x - x0) / max(1.0, w) * 7 + ph)
            if (j == 0) p.m(x, py) else p.l(x, py)
        }
        strokePath(p, color.op(0.25 + hash(s + 5) * 0.35), 0.8 * u, StrokeCap.Butt)
        y += spacing * (0.7 + hash(s + 7) * 0.6)
        k++
    }
}

/** A dowel: shaded cylinder with a rounded top. */
private fun DrawScope.dowel(x: Double, top: Double, bottom: Double, w: Double, brass: Boolean) {
    val light = if (brass) rgb(1.0, 0.88, 0.5) else rgb(0.96, 0.86, 0.66)
    val dark = if (brass) rgb(0.62, 0.42, 0.1) else rgb(0.72, 0.56, 0.36)
    rrect(x - w / 2, top, w, bottom - top, w / 2, hgrad(listOf(dark, light, light, dark), x - w / 2, x + w / 2))
    rrectStroke(x - w / 2, top, w, bottom - top, w / 2, dark.shade(0.3).op(0.7), 0.8 * density)
}

/** Plywood base and the three dowels (the goal peg in brass with a pennant). */
private fun DrawScope.hanoiStand(w: Double, h: Double, baseY: Double, colW: Double, maxDiskW: Double, pegW: Double, goal: Int) {
    val u = density.toDouble()
    val plane = baseY - 2 * u
    val depth = maxDiskW * TILT * 1.6
    val tx = w * 0.03; val ty = plane - depth / 2; val tw = w * 0.94
    val fy = ty + depth; val fh = max(10 * u, h * 0.035)
    blurRRect(tx + 6 * u, ty + 10 * u, tw, depth + fh, 6 * u, Color.Black.op(0.45), 8 * u)
    rrect(tx, fy, tw, fh, 3 * u, rgb(0.72, 0.52, 0.3))
    val plies = Path()
    for (k in 1..3) { val y = fy + fh * k / 4; plies.m(tx + 2 * u, y); plies.l(tx + tw - 2 * u, y) }
    strokePath(plies, rgb(0.45, 0.28, 0.12, 0.7), u, StrokeCap.Butt)
    rrect(tx, ty, tw, depth, 4 * u, vgrad(listOf(rgb(0.93, 0.8, 0.6), rgb(0.85, 0.69, 0.47)), ty, ty + depth))
    val topPath = Path().apply { addRoundRect(androidx.compose.ui.geometry.RoundRect(tx.f, ty.f, (tx + tw).f, (ty + depth).f, (4 * u).f, (4 * u).f)) }
    clipPath(topPath) { grain(tx, ty, tw, depth, 3, 5 * u, rgb(0.6, 0.42, 0.22)) }
    rrectStroke(tx, ty, tw, depth, 4 * u, rgb(0.5, 0.33, 0.16, 0.6), u)
    val gx = colW * (goal + 0.5)
    ellipse(gx, plane, maxDiskW * 0.55, maxDiskW * 0.55 * TILT, radial(listOf(rgb(1.0, 0.85, 0.3, 0.55), Color.Transparent), gx, plane, maxDiskW * 0.55))
    val pegTop = baseY - h * 0.62
    for (i in 0 until 3) {
        val cx = colW * (i + 0.5)
        ellipse(cx, plane, pegW, pegW * 0.4, Color.Black.op(0.25))
        dowel(cx, pegTop, plane, pegW, i == goal)
    }
    line(gx, pegTop + 2 * u, gx, pegTop - pegW * 2.6, rgb(0.55, 0.38, 0.1), 1.5 * u, StrokeCap.Butt)
    fillPath(polyPath(gx, pegTop - pegW * 2.6, gx + pegW * 2.8, pegTop - pegW * 1.95, gx, pegTop - pegW * 1.3), rgb(0.9, 0.2, 0.16))
    circle(gx, pegTop - pegW * 2.55, pegW * 0.45, rgb(1.0, 0.85, 0.4))
}

/** One painted ring in the 3/4 view: top face (hole + peg rising out) over the rounded side band. */
private fun DrawScope.disk(cx: Double, cy: Double, color: Color, width: Double, thick: Double, pegW: Double, brass: Boolean, lifted: Boolean) {
    val u = density.toDouble()
    val rx = width / 2; val ry = width * TILT / 2
    val topY = cy - thick / 2; val botY = cy + thick / 2
    val band = Path()
    band.m(cx - rx, topY); band.l(cx - rx, botY)
    band.arcTo(androidx.compose.ui.geometry.Rect((cx - rx).f, (botY - ry).f, (cx + rx).f, (botY + ry).f), 180f, -180f, false)
    band.l(cx + rx, topY); band.close()
    drawPath(band, hgrad(listOf(color.shade(0.35), color.lit(0.1), color.shade(0.05), color.shade(0.4)), cx - rx, cx + rx))
    strokePath(band, color.shade(0.55).op(0.7), 0.8 * u)
    ellipse(cx, topY, rx, ry, radial(listOf(color.lit(0.32), color.lit(0.05)), cx - rx * 0.3, topY - ry * 0.4, rx))
    ellipseStroke(cx, topY, rx, ry, color.shade(0.4).op(0.6), 0.8 * u)
    val hr = pegW / 2 + 1.5 * u
    ellipse(cx, topY, hr, hr * TILT * 1.6, color.shade(0.7))
    // The peg rising out of the hole (drawn to just above the ring; the stand draws the rest).
    dowel(cx, topY - thick * 0.6, topY, pegW, brass)
    if (lifted) ellipseStroke(cx, topY, rx, ry, Color.White.op(0.9), 2 * u)
}

/** Oak tabletop behind the toy. */
private fun DrawScope.oakTable() {
    val w = size.width.toDouble(); val h = size.height.toDouble()
    rect(0.0, 0.0, w, h, vgrad(listOf(rgb(0.42, 0.27, 0.15), rgb(0.3, 0.18, 0.1)), 0.0, h))
    grain(0.0, 0.0, w, h, 9, 9 * density.toDouble(), rgb(0.18, 0.1, 0.05))
    drawRect(radial(listOf(rgb(1.0, 0.9, 0.7, 0.14), Color.Transparent), w / 2, h * 0.45, max(w, h) * 0.7))
}

/** A small wooden plaque behind the move counter. */
private fun DrawScope.woodPlaque() {
    val u = density.toDouble()
    val x = u; val y = u; val w = size.width - 2 * u; val h = size.height - 2 * u
    rrect(x, y, w, h, 8 * u, vgrad(listOf(rgb(0.96, 0.84, 0.62), rgb(0.86, 0.68, 0.44)), y, y + h))
    val p = Path().apply { addRoundRect(androidx.compose.ui.geometry.RoundRect(x.f, y.f, (x + w).f, (y + h).f, (8 * u).f, (8 * u).f)) }
    clipPath(p) { grain(x, y, w, h, 21, 4 * u, rgb(0.6, 0.4, 0.2)) }
    rrectStroke(x, y, w, h, 8 * u, rgb(0.45, 0.28, 0.12), 2 * u)
    for (sx in listOf(x + 7 * u, x + w - 7 * u)) circle(sx, y + h / 2, 2 * u, rgb(0.4, 0.36, 0.3))
}

/** The level clock: sand runs from the top bulb to the bottom one (red near the end). */
private fun DrawScope.hourglass(frac: Double) {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    val f = clamp(frac, 0.0, 1.0)
    val cap = h * 0.1
    val glassTop = cap; val glassBot = h - cap; val mid = h / 2
    val sand = if (frac < 0.3) rgb(0.95, 0.4, 0.2) else rgb(0.95, 0.8, 0.45)
    fun bulb(top: Boolean): Path {
        val p = Path(); val y0 = if (top) glassTop else glassBot
        val bend = if (top) 4 * u else -4 * u
        p.m(w * 0.12, y0); p.q(w * 0.1, (y0 + mid) / 2 + bend, w * 0.47, mid); p.l(w * 0.53, mid)
        p.q(w * 0.9, (y0 + mid) / 2 + bend, w * 0.88, y0); p.close()
        return p
    }
    val upper = bulb(true); val lower = bulb(false)
    fillPath(upper, Color.White.op(0.18)); fillPath(lower, Color.White.op(0.18))
    clipPath(upper) { val lv = mid - (mid - glassTop) * f * 0.92; rect(0.0, lv, w, mid - lv, sand) }
    val pile = (glassBot - mid) * (1 - f) * 0.9
    clipPath(lower) {
        val mound = Path()
        mound.m(0.0, glassBot); mound.l(0.0, glassBot - pile * 0.6)
        mound.q(w / 2, glassBot - pile * 1.5, w, glassBot - pile * 0.6); mound.l(w, glassBot); mound.close()
        fillPath(mound, sand)
    }
    if (f > 0 && f < 1) line(w / 2, mid, w / 2, glassBot - pile * 0.9, sand, 1.2 * u, StrokeCap.Butt)
    strokePath(upper, Color.White.op(0.7), 1.2 * u); strokePath(lower, Color.White.op(0.7), 1.2 * u)
    for (y in listOf(0.0, h - cap)) rrect(0.0, y, w, cap, 2 * u, rgb(0.55, 0.34, 0.16))
    for (x in listOf(w * 0.04, w * 0.96 - 2 * u)) rect(x, cap, 2 * u, h - cap * 2, rgb(0.45, 0.28, 0.12))
}
