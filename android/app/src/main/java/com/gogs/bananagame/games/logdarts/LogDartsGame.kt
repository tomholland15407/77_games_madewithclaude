package com.gogs.bananagame.games.logdarts

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Reflex — Log Darts (iOS KnifeHitGame.swift, id "knife-hit"): tap to throw knives into the spinning
 * log; hitting a stuck knife or an iron plate clanks off. Stick the quota.
 */
object LogDartsGame {
    val definition = GameDefinition(
        id = "knife-hit",
        title = "Log Darts",
        genre = Genre.REFLEX,
        manual = GameManual(
            bullets = listOf(
                "A log spins in the center. Tap to throw the waiting knife into the rim.",
                "Land it in an empty spot and it sticks.",
                "Hit an already-stuck knife or an iron plate and it clanks off — back to level 1.",
                "Stick the level's quota of knives to win.",
            ),
            bulletsVI = listOf(
                "Một khúc gỗ xoay ở giữa. Chạm để phóng con dao đang chờ vào vành.",
                "Cắm vào chỗ trống thì nó dính lại.",
                "Trúng con dao đã cắm hoặc tấm sắt thì nó bật ra — về cấp 1.",
                "Cắm đủ số dao của cấp để thắng.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> LogDartsView(level, onWin, onFail) }
    )
}

private const val KNIFE_W = 0.17
private const val BLOCK_W = 0.30
private val demoThrowFrames = setOf(48, 90, 132, 174)

private fun norm(a: Double): Double { var x = a % (2 * PI); if (x < 0) x += 2 * PI; return x }
private fun angDiff(a: Double, b: Double): Double { var d = abs(norm(a) - norm(b)); if (d > PI) d = 2 * PI - d; return d }

private class LogWorld(val level: Int) {
    private val li = min(level, 7) - 1
    val quota = listOf(4, 5, 6, 8, 10, 12, 14)[li]
    val preKnives = listOf(1, 2, 2, 3, 4, 5, 6)[li]
    val blocks = listOf(0, 0, 1, 1, 2, 2, 3)[li]
    val rotSpeed = listOf(1.2, 1.5, 1.8, 2.1, 2.5, 3.0, 3.6)[li]
    val canReverse = level >= 4
    val timeLimit = listOf(13.0, 14.0, 15.0, 16.0, 17.0, 18.0, 20.0)[li]

    var theta = 0.0; var dir = 1.0; var reversal = 2.0
    var stuck = mutableListOf<Double>()
    var blockList = listOf<Double>()
    var count = 0
    var throwing = false
    var throwT0 = -10.0
    var timeLeft = timeLimit
    var done = false
    var splitAt = -1.0
    var clankAt = -1.0
    var shakeT0 = -10.0
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    fun setup() {
        theta = 0.0; dir = 1.0; reversal = rnd(1.2, 2.6)
        count = 0; throwing = false; timeLeft = timeLimit; done = false; splitAt = -1.0; clankAt = -1.0
        val used = mutableListOf<Double>()
        fun free(pad: Double): Double? {
            repeat(40) { val a = rnd(0.0, 2 * PI); if (used.all { angDiff(it, a) > pad }) { used.add(a); return a } }
            return null
        }
        stuck = (0 until preKnives).mapNotNull { free(KNIFE_W * 3) }.toMutableList()
        blockList = (0 until blocks).mapNotNull { free(BLOCK_W * 2) }
    }

    fun spin(dt: Double) {
        if (canReverse) { reversal -= dt; if (reversal <= 0) { dir = -dir; reversal = rnd(1.2, 2.6) } }
        theta += rotSpeed * dir * dt
    }

    /** The knife arrives at the bottom of the log: screen angle π/2. */
    fun resolve() {
        if (done) return
        val contact = norm(PI / 2 - theta)
        if (stuck.any { angDiff(it, contact) < KNIFE_W * 2 } || blockList.any { angDiff(it, contact) < BLOCK_W + KNIFE_W }) {
            shakeT0 = nowSec(); fail(); return
        }
        stuck.add(contact); count++
        SoundManager.tap(); Haptics.tap()
        if (count >= quota) win()
    }

    fun win() { if (done) return; done = true; splitAt = nowSec(); onWin() }
    fun fail() {
        if (done) return
        done = true
        if (timeLeft > 0) clankAt = nowSec()
        SoundManager.error(); onFail()
    }
}

@Composable
private fun LogDartsView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { LogWorld(level).also { it.setup() } }
    world.onWin = onWin; world.onFail = onFail
    var demoTapT by remember { mutableDoubleStateOf(-10.0) }
    var demoTick by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    val start = remember { nowSec() }
    val tick by rememberFrameLoop { dt ->
        if (isDemo || world.done) return@rememberFrameLoop
        world.timeLeft = max(0.0, world.timeLimit - (nowSec() - start))
        if (world.timeLeft <= 0) { world.fail(); return@rememberFrameLoop }
        world.spin(dt)
    }

    fun throwKnife() {
        if (world.done || world.throwing) return
        world.throwing = true; world.throwT0 = nowSec()
        scope.launch { delay(75); world.resolve(); world.throwing = false }
    }

    LaunchedEffect(Unit) {
        if (!isDemo) return@LaunchedEffect
        val dt = 1.0 / 60.0
        while (isActive) {
            world.theta = 0.0; world.dir = 1.0; world.count = 0; world.throwing = false
            world.timeLeft = world.timeLimit; world.done = false; world.splitAt = -1.0; world.clankAt = -1.0
            world.stuck = mutableListOf(2.4); world.blockList = emptyList()
            var frame = 0
            while (isActive && !world.done && frame < 600) {
                frame++
                if (frame in demoThrowFrames) { throwKnife(); demoTapT = nowSec() }
                world.theta += world.rotSpeed * world.dir * dt
                demoTick++
                delay(16)
            }
            delay(1300)
        }
    }

    Canvas(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .graphicsLayer {
                val t = nowSec() - world.shakeT0
                if (t in 0.0..0.35) translationX = (6 * density * sin(t / 0.35 * PI * 3) * (1 - t / 0.35)).toFloat()
            }
            .then(if (isDemo) Modifier else Modifier.tapAt { throwKnife() })
    ) {
        tick; demoTick
        val w = size.width.toDouble(); val h = size.height.toDouble(); val u = density.toDouble()
        backdrop(level)
        val cx = w * 0.5; val cy = h * 0.40
        val r = min(w, h) * 0.20
        val kw = r * 0.34; val kh = r * 0.80
        val now = nowSec()
        val split = if (world.splitAt >= 0) now - world.splitAt else null
        logArt(cx, cy, r, world.theta, world.stuck, world.blockList, kw, kh, split)
        // The waiting / thrown knife (0.07 s ease-out throw).
        val hidden = (isDemo && world.done) || world.clankAt >= 0
        if (!hidden) {
            val k = if (world.throwing) clamp((now - world.throwT0) / 0.07, 0.0, 1.0) else 0.0
            val p = 1 - (1 - k) * (1 - k)
            translate(cx.f, (cy + h * 0.42 - p * (h * 0.42 - r - kh * 0.4)).f) { knife(kw, kh) }
        }
        if (world.clankAt >= 0) {
            val t = now - world.clankAt
            if (t < 0.75) {
                val e = (t / 0.75) * (t / 0.75)
                withAlpha(1 - e) {
                    translate((cx + kh * 1.6 * e).f, (cy + r + kh * 0.5 + kh * 2.4 * e).f) {
                        rotateRad((deg(560.0) * e).f, Offset.Zero) { knife(kw, kh) }
                    }
                }
            }
        }
        hud(world.quota - world.count, world.quota, if (isDemo) null else world.timeLeft / world.timeLimit, (if (isDemo) 12 else 18) * u, (if (isDemo) 8 else 14) * u)
        if (isDemo) tapRipple(w * 0.74, h * 0.84, now - demoTapT)
    }
}

// Knife Hit art (iOS KHArt and friends).

private val ink = rgb(0.12, 0.08, 0.06)

/** A knife pointing up (tip at −y), centred at the origin in a kw × kh box. */
private fun DrawScope.knife(kw: Double, kh: Double, tint: Color? = null) {
    val blade = Path()
    blade.m(0.0, -kh / 2); blade.q(kw * 0.3, -kh * 0.34, kw * 0.3, -kh * 0.04)
    blade.l(kw * 0.3, kh * 0.05); blade.l(-kw * 0.3, kh * 0.05); blade.l(-kw * 0.3, -kh * 0.28); blade.close()
    if (tint != null) {
        fillPath(blade, tint)
        rrect(-kw * 0.44, kh * 0.04, kw * 0.88, kh * 0.07, kw * 0.06, tint)
        rrect(-kw * 0.27, kh * 0.1, kw * 0.54, kh * 0.4, kw * 0.16, tint)
        return
    }
    val lw = max(0.6 * density, kw * 0.05)
    drawPath(blade, hgrad(listOf(gray(0.97), gray(0.78), gray(0.6)), -kw * 0.3, kw * 0.3))
    line(-kw * 0.05, -kh * 0.4, -kw * 0.05, kh * 0.03, Color.White.op(0.8), max(0.6 * density, kw * 0.06))
    strokePath(blade, gray(0.35), lw)
    rrect(-kw * 0.44, kh * 0.04, kw * 0.88, kh * 0.07, kw * 0.06, gray(0.28))
    rrect(-kw * 0.27, kh * 0.1, kw * 0.54, kh * 0.4, kw * 0.16, hgrad(listOf(rgb(1.0, 0.62, 0.26), rgb(0.86, 0.36, 0.1)), -kw * 0.27, kw * 0.27))
    for (y in listOf(0.22, 0.38)) rect(-kw * 0.27, kh * y, kw * 0.54, kh * 0.04, rgb(0.45, 0.16, 0.06))
    rrectStroke(-kw * 0.27, kh * 0.1, kw * 0.54, kh * 0.4, kw * 0.16, rgb(0.4, 0.14, 0.05), lw)
}

/** The log end-on, centred at the origin: bark rim, growth rings, a crack and a knot that show the spin. */
private fun DrawScope.face(r: Double, theta: Double) {
    circle(0.0, 0.0, r, rgb(0.55, 0.3, 0.13))
    circle(0.0, 0.0, r * 0.9, radial(listOf(rgb(1.0, 0.85, 0.5), rgb(0.95, 0.68, 0.32)), 0.0, 0.0, r * 0.9))
    for (k in 1..5) circleStroke(0.0, 0.0, r * (0.14 + 0.15 * k), rgb(0.86, 0.55, 0.24, 0.75), max(density.toDouble(), r * 0.03))
    rotateRad(theta.f, Offset.Zero) {
        val crack = Path(); crack.m(r * 0.3, 0.0); crack.l(r * 0.5, r * 0.05); crack.l(r * 0.64, -r * 0.03); crack.l(r * 0.88, r * 0.04)
        strokePath(crack, rgb(0.5, 0.27, 0.1), max(1.2 * density, r * 0.035))
        oval(-r * 0.52, -r * 0.36, r * 0.18, r * 0.12, rgb(0.72, 0.42, 0.16))
    }
    circleStroke(0.0, 0.0, r * 0.9, rgb(0.72, 0.42, 0.16), max(density.toDouble(), r * 0.04))
    circleStroke(0.0, 0.0, r, ink.op(0.6), max(density.toDouble(), r * 0.025))
}

/** An iron plate over the rim spanning the block's true angular half-width. */
private fun DrawScope.plate(r: Double, a: Double) {
    val half = 0.30
    val p = Path()
    p.arc(0.0, 0.0, r * 1.1, a - half, a + half, moveFirst = true)
    p.arc(0.0, 0.0, r * 0.84, a + half, a - half, clockwise = true)
    p.close()
    drawPath(p, androidx.compose.ui.graphics.Brush.radialGradient(0f to gray(0.5), (0.84 / 1.1).toFloat() to gray(0.5),
        (0.97 / 1.1).toFloat() to gray(0.78), 1f to gray(0.42), center = Offset.Zero, radius = (r * 1.1).f))
    strokePath(p, gray(0.2), max(density.toDouble(), r * 0.03))
    for (d in listOf(-0.18, 0.18)) circle(cos(a + d) * r * 0.97, sin(a + d) * r * 0.97, r * 0.035, gray(0.25))
}

/** Stuck knives, the log over them, and the plates; `split` (seconds) breaks it apart. */
private fun DrawScope.logArt(cx: Double, cy: Double, r: Double, theta: Double, knives: List<Double>, blocks: List<Double>, kw: Double, kh: Double, split: Double?) {
    val t = split ?: 0.0
    val fade = if (split == null) 1.0 else max(0.0, 1 - split / 1.25)
    if (fade <= 0) return
    translate(cx.f, cy.f) {
        withAlpha(fade) {
            for (rel in knives) {
                val a = rel + theta
                val out = r + kh * 0.30 + t * r * 1.6
                translate((cos(a) * out).f, (sin(a) * out + t * t * r * 3).f) { rotateRad((a - PI / 2 + t * 6).f, Offset.Zero) { knife(kw, kh) } }
            }
            if (split == null) face(r, theta)
            else for (k in 0 until 3) {
                val mid = theta + k * 2 * PI / 3 + PI / 3
                translate((cos(mid) * t * r * 1.2).f, (sin(mid) * t * r * 1.2 + t * t * r * 2.6).f) {
                    rotateRad((t * (if (k == 1) -1.6 else 1.6)).f, Offset.Zero) {
                        val wedge = Path(); wedge.m(0.0, 0.0); wedge.arc(0.0, 0.0, r * 1.02, mid - PI / 3, mid + PI / 3); wedge.close()
                        clipPath(wedge) { face(r, theta) }
                    }
                }
            }
            for (a in blocks) translate(0f, (t * t * r * 2.6).f) { plate(r, a + theta) }
        }
    }
}

/** The column of knives (white = still to throw) with a slim clock above it while playing. */
private fun DrawScope.hud(left: Int, total: Int, fraction: Double?, x: Double, top: Double) {
    val u = density.toDouble()
    val h = size.height.toDouble()
    if (fraction != null) {
        val f = clamp(fraction, 0.0, 1.0)
        rrect(x, top, 90 * u, 3 * u, 1.5 * u, Color.White.op(0.16))
        if (f > 0) rrect(x, top, 90 * u * f, 3 * u, 1.5 * u, if (f < 0.3) rgb(1.0, 0.35, 0.3) else Color.White.op(0.85))
    }
    val n = max(1, total)
    val colH = min(24 * u * n, 300 * u)
    val step = min(24 * u, colH / n)
    val bottom = h - top
    for (i in 0 until n) translate((x + 10 * u).f, (bottom - (i + 0.5) * step).f) { knife(step * 0.46, step * 0.92, if (i < left) Color.White else Color.White.op(0.2)) }
}

/** Dark teal backdrop with soft light shafts (navy mid-game, a crimson boss glow at 6–7). */
private fun DrawScope.backdrop(level: Int) {
    val w = size.width.toDouble(); val h = size.height.toDouble()
    val cols = when {
        level >= 6 -> listOf(rgb(0.28, 0.07, 0.1), rgb(0.1, 0.02, 0.05))
        level >= 4 -> listOf(rgb(0.08, 0.15, 0.3), rgb(0.03, 0.06, 0.15))
        else -> listOf(rgb(0.07, 0.24, 0.29), rgb(0.03, 0.11, 0.15))
    }
    rect(0.0, 0.0, w, h, vgrad(cols, 0.0, h))
    for ((x, width) in listOf(0.18 to 0.09, 0.46 to 0.14, 0.8 to 0.07))
        drawPath(polyPath(w * x, 0.0, w * (x + width), 0.0, w * (x + width - 0.22), h, w * (x - 0.22), h),
            vgrad(listOf(Color.White.op(0.07), Color.White.op(0.0)), 0.0, h * 0.85))
}
