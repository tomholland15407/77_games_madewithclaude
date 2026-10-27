package com.gogs.bananagame.games.lineconnect

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
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
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** Brain — Line Connect (iOS LineConnectGame.swift): memorize the mines, then trace a path past them. */
object LineConnectGame {
    val definition = GameDefinition(
        id = "line-connect",
        title = "Line Connect",
        genre = Genre.BRAIN,
        locksFeed = true,
        manual = GameManual(
            bullets = listOf(
                "Mines flash in the field, then vanish — memorize them.",
                "Drag a freeform line from the 🍌 on the left to the flag on the right.",
                "Touch a hidden mine, or run out of time, and you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Mìn nhấp nháy trên cánh đồng rồi biến mất — hãy ghi nhớ chúng.",
                "Kéo một đường tự do từ 🍌 bên trái đến lá cờ bên phải.",
                "Chạm phải một quả mìn ẩn, hoặc hết giờ, sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> LineConnectView(level, onWin, onFail) }
    )
}

private enum class LPhase { PEEK, PLAY, DONE }
private const val START_X = 0.06
private const val GOAL_X = 0.94
private const val EP_R = 0.07

@Composable
private fun LineConnectView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val obstacleCount = 1 + level
    val obR = 0.05 + level * 0.006
    val peekTime = max(0.6, 2.8 - level * 0.32)
    val timeLimit = max(3.0, 8.0 - level * 0.6)
    var phase by remember { mutableStateOf(LPhase.PEEK) }
    var obstacles by remember { mutableStateOf(listOf<P>()) }
    var startY by remember { mutableDoubleStateOf(0.5) }
    var goalY by remember { mutableDoubleStateOf(0.5) }
    var path by remember { mutableStateOf(listOf<P>()) }   // fractional points
    var armed by remember { mutableStateOf(false) }
    var reveal by remember { mutableStateOf(true) }
    var timeLeft by remember { mutableDoubleStateOf(timeLimit) }
    var boom by remember { mutableStateOf<Pair<P, Double>?>(null) }
    var area by remember { mutableStateOf(P.zero) }
    val handP = rememberHand()

    fun win() { if (phase != LPhase.PLAY) return; phase = LPhase.DONE; Haptics.tap(); SoundManager.tap(); onWin() }
    fun fail() { if (phase != LPhase.PLAY) return; phase = LPhase.DONE; reveal = true; SoundManager.error(); onFail() }

    fun makeObstacles(): List<P> {
        val result = ArrayList<P>()
        val start = P(START_X, startY); val goal = P(GOAL_X, goalY)
        val minGap = obR * 2 + 0.04
        val clear = obR + EP_R + 0.06
        var attempts = 0
        while (result.size < obstacleCount && attempts < 500) {
            attempts++
            val cand = P(rnd(0.2, 0.8), rnd(0.12, 0.88))
            if (cand.dist(start) < clear + 0.06 || cand.dist(goal) < clear + 0.06) continue
            if (result.any { it.dist(cand) < minGap }) continue
            result.add(cand)
        }
        val step = obR * 1.5
        for (yEdge in listOf(0.06, 0.94)) {
            var x = 0.04
            while (x <= 0.96) {
                val cand = P(x, yEdge); x += step
                if (cand.dist(start) < clear || cand.dist(goal) < clear) continue
                result.add(cand)
            }
        }
        return result
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            val route = listOf(P(0.06, 0.5), P(0.14, 0.36), P(0.28, 0.22), P(0.50, 0.18), P(0.72, 0.22), P(0.86, 0.36), P(0.94, 0.5))
            while (isActive) {
                startY = 0.5; goalY = 0.5
                obstacles = listOf(P(0.40, 0.50), P(0.50, 0.50), P(0.60, 0.50), P(0.50, 0.38), P(0.50, 0.62))
                path = emptyList(); reveal = true; boom = null; phase = LPhase.PEEK
                delay((peekTime * 1000).toLong())
                reveal = false; phase = LPhase.PLAY; timeLeft = timeLimit
                delay(400)
                for (pt in route) { path = path + pt; delay(160) }
                win()
                delay(1300)
            }
        } else {
            phase = LPhase.PEEK; reveal = true; boom = null; armed = false; path = emptyList()
            startY = rnd(0.25, 0.75); goalY = rnd(0.25, 0.75)
            obstacles = makeObstacles()
            delay((peekTime * 1000).toLong())
            if (phase != LPhase.PEEK) return@LaunchedEffect
            reveal = false; phase = LPhase.PLAY
            timeLeft = timeLimit
            val start = nowSec()
            while (isActive && phase == LPhase.PLAY) {
                delay(50)
                timeLeft = max(0.0, timeLimit - (nowSec() - start))
                if (timeLeft <= 0) { fail(); break }
            }
        }
    }

    val tick by rememberFrameLoop(running = reveal || boom != null)

    fun geom(): DoubleArray {
        val side = min(area.x, area.y) * 0.86
        return doubleArrayOf((area.x - side) / 2, (area.y - side) / 2, side)
    }

    fun handleDrag(p: P, isStart: Boolean) {
        if (phase != LPhase.PLAY) return
        val g = geom()
        val ox = g[0]; val oy = g[1]; val side = g[2]
        fun act(f: P) = P(ox + f.x * side, oy + f.y * side)
        val epR = EP_R * side
        val startPt = act(P(START_X, startY)); val goalPt = act(P(GOAL_X, goalY))
        val f = P((p.x - ox) / side, (p.y - oy) / side)
        if (!armed) {
            if (p.dist(startPt) <= epR * 1.4) { armed = true; path = listOf(P(START_X, startY), f) }
            return
        }
        if (p.x < ox || p.x > ox + side || p.y < oy || p.y > oy + side) { armed = false; path = emptyList(); return }
        path = path + f
        for (ob in obstacles) if (p.dist(act(ob)) <= obR * side) { boom = ob to nowSec(); fail(); return }
        if (p.dist(goalPt) <= epR) win()
    }

    Box(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .background(rgb(0.12, 0.2, 0.1))
            .onSizeChanged { area = P(it.width.toDouble(), it.height.toDouble()) }
            .then(if (isDemo) Modifier else Modifier.touchDrag(
                onStart = { p -> handleDrag(p, true) },
                onMove = { _, p -> handleDrag(p, false) },
                onEnd = { _, _ -> if (phase == LPhase.PLAY) { armed = false; path = emptyList() } }
            ).let { it }),
    ) {
        Canvas(Modifier.fillMaxSize()) {
            tick
            val (ox, oy, side) = geom().let { Triple(it[0], it[1], it[2]) }
            if (side <= 0) return@Canvas
            fun act(f: P) = P(ox + f.x * side, oy + f.y * side)
            minefield(ox, oy, side)
            trail(path.map { act(it) }, max(8 * density.toDouble(), side * 0.045))
            val gp = act(P(GOAL_X, goalY)); val sp = act(P(START_X, startY))
            val epR = EP_R * side
            finish(gp.x, gp.y, epR)
            banana(sp.x, sp.y, epR * 1.9)
            if (reveal) {
                val blink = floor(nowSec() * 4).toLong() % 2 == 0L
                for (ob in obstacles) { val a = act(ob); mine(a.x, a.y, obR * side, blink) }
            }
            boom?.let { (at, t0) -> val a = act(at); explosion(a.x, a.y, obR * side * 2.2, nowSec() - t0) }
            if (isDemo && phase == LPhase.PLAY) path.lastOrNull()?.let { f ->
                val a = act(f); val hw = epR * 1.5
                hand(handP, a.x - hw * 0.28, a.y - hw * 0.06, hw)
            }
        }
        if (!isDemo) TimeBar(timeLeft / timeLimit, Modifier.fillMaxWidth().padding(horizontal = 48.dp).padding(top = 10.dp).height(6.dp))
        if (phase == LPhase.PEEK) {
            val g = geom()
            val dens = androidx.compose.ui.platform.LocalDensity.current.density
            val cy = if (isDemo) g[1] + g[2] - 14 * dens else g[1] + g[2] + (area.y - g[1] - g[2]) / 2
            Box(Modifier.fillMaxWidth().offset(y = (cy / dens).dp - 16.dp), contentAlignment = Alignment.TopCenter) {
                Text(L("MEMORIZE", "GHI NHỚ"), style = ts(if (isDemo) 14.0 else 17.0, FontWeight.Black, rgb(0.2, 0.12, 0.02), spacing = 2.0),
                    modifier = Modifier.background(rgb(1.0, 0.84, 0.2), RoundedCornerShape(50))
                        .border(2.dp, rgb(0.25, 0.15, 0.02), RoundedCornerShape(50)).padding(horizontal = 16.dp, vertical = 7.dp))
            }
        }
    }
}

private fun c(r: Double, g: Double, b: Double) = rgb(r, g, b)

private fun DrawScope.mine(px: Double, py: Double, r: Double, lit: Boolean) {
    circle(px + r * 0.12, py + r * 0.18, r, Color.Black.op(0.3))
    circle(px, py, r, radial(listOf(c(0.5, 0.52, 0.34), c(0.3, 0.32, 0.2), c(0.2, 0.21, 0.13)), px - r * 0.3, py - r * 0.35, r * 1.3))
    circleStroke(px, py, r, c(0.1, 0.11, 0.06), max(1.0, r * 0.1))
    for (k in 0 until 8) {
        val a = k / 8.0 * 2 * PI
        line(px + cos(a) * r * 0.45, py + sin(a) * r * 0.45, px + cos(a) * r * 0.82, py + sin(a) * r * 0.82, c(0.15, 0.16, 0.1).op(0.7), max(0.8, r * 0.07), StrokeCap.Butt)
    }
    circle(px, py, r * 0.36, radial(listOf(c(0.62, 0.64, 0.6), c(0.3, 0.31, 0.28)), px - r * 0.1, py - r * 0.1, r * 0.4))
    val lx = px + r * 0.5; val ly = py - r * 0.5
    if (lit) circle(lx, ly, r * 0.5, radial(listOf(c(1.0, 0.2, 0.15).op(0.8), c(1.0, 0.2, 0.15).op(0.0)), lx, ly, r * 0.5))
    circle(lx, ly, r * 0.16, if (lit) c(1.0, 0.3, 0.25) else c(0.5, 0.08, 0.06))
}

private fun DrawScope.trail(pts: List<P>, w: Double) {
    if (pts.size < 2) return
    val p = polyPath(pts, close = false)
    drawPath(p, c(0.36, 0.26, 0.14).op(0.75), style = Stroke((w * 1.25).f, cap = StrokeCap.Round, join = StrokeJoin.Round))
    drawPath(p, c(0.82, 0.68, 0.44), style = Stroke(w.f, cap = StrokeCap.Round, join = StrokeJoin.Round))
    drawPath(p, c(0.66, 0.52, 0.32), style = Stroke((w * 0.3).f, cap = StrokeCap.Round, join = StrokeJoin.Round,
        pathEffect = PathEffect.dashPathEffect(floatArrayOf((w * 0.5).f, (w * 0.7).f))))
}

private fun DrawScope.finish(px: Double, py: Double, r: Double) {
    circle(px, py, r, Color.White.op(0.18))
    drawCircle(Color.White.op(0.9), r.f, off(px, py), style = Stroke(max(2.0, r * 0.12).f,
        pathEffect = PathEffect.dashPathEffect(floatArrayOf((r * 0.35).f, (r * 0.2).f))))
    val bx = px - r * 0.1; val by = py + r * 0.35
    val tx = bx; val ty = by - r * 1.9
    oval(bx - r * 0.3, by - r * 0.08, r * 0.6, r * 0.18, Color.Black.op(0.3))
    line(bx, by, tx, ty, c(0.3, 0.3, 0.32), max(1.5, r * 0.12))
    val fw = r * 1.2; val fh = r * 0.8
    for (i in 0 until 4) for (j in 0 until 3) {
        val x0 = tx + fw * i / 4; val x1 = tx + fw * (i + 1) / 4
        val w0 = sin(i * 0.9) * fh * 0.08; val w1 = sin((i + 1) * 0.9) * fh * 0.08
        val y0 = ty + fh * j / 3; val y1 = ty + fh * (j + 1) / 3
        drawPath(polyPath(x0, y0 + w0, x1, y0 + w1, x1, y1 + w1, x0, y1 + w0), if ((i + j) % 2 == 0) Color.White else c(0.1, 0.1, 0.12))
    }
    circle(tx, ty, max(1.5, r * 0.1), c(0.95, 0.8, 0.25))
}

private fun DrawScope.banana(cx: Double, cy: Double, s: Double) {
    oval(cx - s * 0.4, cy + s * 0.12, s * 0.8, s * 0.22, Color.Black.op(0.3))
    val p = Path(); p.m(cx - s * 0.1, cy - s * 0.46)
    p.q(cx - s * 0.52, cy - s * 0.05, cx - s * 0.08, cy + s * 0.3)
    p.q(cx + s * 0.48, cy, cx - s * 0.1, cy - s * 0.46); p.close()
    drawPath(p, hgrad(listOf(c(1.0, 0.95, 0.5), c(1.0, 0.84, 0.2), c(0.86, 0.62, 0.08)), cx - s * 0.3, cx + s * 0.3))
    strokePath(p, c(0.45, 0.3, 0.05), max(1.0, s * 0.04))
    rrect(cx - s * 0.15, cy - s * 0.56, s * 0.1, s * 0.14, s * 0.02, c(0.42, 0.28, 0.1))
}

private fun DrawScope.explosion(px: Double, py: Double, r: Double, t: Double) {
    if (t < 0 || t >= 1.2) return
    for (k in 0 until 6) {
        val a = k * 1.05 + 0.2
        circle(px + cos(a) * r * (0.3 + t), py + sin(a) * r * (0.3 + t) - t * r * 0.6, r * (0.35 + t * 0.6), gray(0.3).op(max(0.0, 0.55 - t * 0.45)))
    }
    if (t < 0.5) {
        val k = t / 0.5; val rr = r * (0.5 + k)
        circle(px, py, rr, radial(listOf(Color.White, c(1.0, 0.85, 0.3), c(1.0, 0.4, 0.1), c(0.8, 0.1, 0.0).op(0.0)), px, py, rr))
    }
    for (k in 0 until 8) {
        val a = k * 0.785
        val d = r * (0.4 + t * 2.4)
        circle(px + cos(a) * d, py + sin(a) * d + t * t * r * 1.5, r * 0.14 * max(0.0, 1 - t / 1.2), c(0.36, 0.24, 0.12))
    }
}

private fun DrawScope.minefield(fx: Double, fy: Double, fs: Double) {
    val W = size.width.toDouble(); val H = size.height.toDouble(); val u = density.toDouble()
    drawRect(radial(listOf(c(0.2, 0.3, 0.14), c(0.08, 0.13, 0.06)), W / 2, H / 2, max(W, H) * 0.7))
    rrect(fx, fy, fs, fs, 6 * u, lin(listOf(c(0.46, 0.68, 0.28), c(0.36, 0.58, 0.22)), fx, fy, fx + fs, fy + fs))
    val field = Path().apply { addRoundRect(RoundRect(fx.f, fy.f, (fx + fs).f, (fy + fs).f, CornerRadius((6 * u).f))) }
    clipPath(field) {
        val band = fs / 8
        for (k in 0 until 8 step 2) rect(fx + k * band, fy, band, fs, Color.White.op(0.06))
        for (k in 0 until 50) {
            val hx = abs((sin(k * 12.9898) * 43758.5453) % 1.0)
            val hy = abs((sin(k * 78.233) * 24634.6345) % 1.0)
            val px = fx + hx * fs; val py = fy + hy * fs
            for (d in listOf(-1.0, 0.0, 1.0)) line(px, py, px + d * 2.5 * u, py - 5 * u, c(0.24, 0.44, 0.14).op(0.8), 1.2 * u, StrokeCap.Butt)
            if (k % 9 == 0) oval(px + 4 * u, py - 3 * u, 4 * u, 4 * u, if (k % 2 == 0) Color.White.op(0.9) else c(1.0, 0.85, 0.3))
        }
    }
    val e = 8 * u
    drawRoundRect(c(0.85, 0.72, 0.45), off(fx - e, fy - e), sz(fs + 2 * e, fs + 2 * e), CornerRadius((8 * u).f),
        style = Stroke((2.5 * u).f, pathEffect = PathEffect.dashPathEffect(floatArrayOf((9 * u).f, (4 * u).f))))
    val posts = 6
    for (i in 0..posts) {
        val t = (fs + 2 * e) * i / posts
        for ((x, y) in listOf(fx - e + t to fy - e, fx - e + t to fy + fs + e, fx - e to fy - e + t, fx + fs + e to fy - e + t)) {
            rrect(x - 3 * u, y - 3 * u, 6 * u, 6 * u, 1.5 * u, c(0.45, 0.3, 0.16))
        }
    }
}
