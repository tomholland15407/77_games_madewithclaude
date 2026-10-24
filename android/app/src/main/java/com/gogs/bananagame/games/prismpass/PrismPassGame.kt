package com.gogs.bananagame.games.prismpass

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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Reflex — Prism Pass (iOS ColorSwitchGame.swift, id "color-switch"): tap to hop the ball up through
 * rotating rings, only through the arc of its own colour. Wrong colour or a fall → level 1.
 */
object PrismPassGame {
    val definition = GameDefinition(
        id = "color-switch",
        title = "Prism Pass",
        genre = Genre.REFLEX,
        manual = GameManual(
            bullets = listOf(
                "Tap to hop the ball up through a tower of rotating multi-colored rings.",
                "Only pass through the arc segment matching your ball's current color.",
                "Switch dots between rings recolor the ball, so re-read every gap.",
                "Brush a wrong color, or fall off the bottom, and you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Chạm để nảy bóng lên qua một tháp các vòng nhiều màu đang xoay.",
                "Chỉ được đi qua đoạn cung khớp với màu hiện tại của bóng.",
                "Chấm đổi màu giữa các vòng sẽ tô lại màu bóng, nên hãy đọc kỹ mỗi khe.",
                "Chạm sai màu, hoặc rơi khỏi đáy, sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> PrismPassView(level, onWin, onFail) }
    )
}

/** Color Switch's four, then orange and green for the 5- and 6-arc levels. */
private val allColors = listOf(rgb(0.20, 0.89, 0.95), rgb(0.96, 0.87, 0.05), rgb(0.50, 0.16, 0.86), rgb(0.98, 0.02, 0.52),
    rgb(1.00, 0.50, 0.08), rgb(0.24, 0.82, 0.36))
private fun swatch(i: Int) = allColors[clampI(i, 0, allColors.size - 1)]

private const val BALL_X = 0.5
private const val BALL_R = 0.028
private const val RING_THICK = 0.02
private const val ANCHOR = 0.34
private const val GRAVITY = 1.5
private const val BOUNCE_V = 0.34
private const val FALL_LIMIT = 0.80

private val demoTaps = setOf(10, 18, 26, 34, 42, 50, 58, 66, 74, 82, 90, 98, 108, 118, 128, 151, 160, 183,
    202, 210, 218, 226, 234, 242, 250, 258, 266, 274, 282, 290, 298, 306, 314, 322,
    330, 338, 346, 354, 362, 370, 378, 386, 406, 436, 445, 457, 469, 477, 485)

private class Ring(val worldY: Double, val speed: Double, val dir: Double) { var passed = false }
private class Dot(val worldY: Double) { var used = false }

private class PrismWorld(level: Int, val isDemo: Boolean) {
    private val li = min(level, 7) - 1
    val arcCount = listOf(4, 4, 4, 5, 5, 6, 6)[li]
    val toClear = listOf(3, 4, 5, 6, 7, 8, 9)[li]
    val ringRadius = listOf(0.17, 0.16, 0.15, 0.14, 0.13, 0.12, 0.11)[li]
    val rotSpeed = listOf(0.9, 1.1, 1.3, 1.6, 1.9, 2.3, 2.7)[li]
    val timeLimit = (18 + toClear * 6).toDouble()
    val ringSpacing = 2 * (ringRadius + 0.22)

    var rings = listOf<Ring>()
    var dots = listOf<Dot>()
    var ballY = 0.0; var cam = 0.0; var vy = 0.0
    var colorIndex = 0
    var t = 0.0
    var passed = 0
    var timeLeft = timeLimit
    var done = false
    var deathY: Double? = null
    var deathT0 = 0.0
    val demoRecolors = mutableListOf<Int>()
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    fun colorAt(phi: Double, r: Ring): Int {
        val seg = 2 * PI / arcCount
        var a = (phi - t * r.speed * r.dir) % (2 * PI)
        if (a < 0) a += 2 * PI
        return (a / seg).toInt() % arcCount
    }

    private fun build(speed: (Int) -> Double, dir: (Int) -> Double) {
        val r = mutableListOf<Ring>(); val d = mutableListOf<Dot>()
        var y = 0.5
        for (i in 0..toClear) {
            r.add(Ring(y, speed(i), dir(i)))
            if (i < toClear) d.add(Dot(y + ringSpacing / 2))
            y += ringSpacing
        }
        rings = r; dots = d
    }

    fun setup() {
        ballY = 0.0; cam = 0.0; vy = BOUNCE_V; t = 0.0; passed = 0; done = false; deathY = null
        timeLeft = timeLimit
        colorIndex = rndInt(0 until arcCount)
        build({ rotSpeed * rnd(0.85, 1.2) }, { if (rndBool()) 1.0 else -1.0 })
    }

    fun demoSetup() {
        cam = 0.80; ballY = 0.80; vy = BOUNCE_V; passed = 1; done = false; deathY = null
        t = 4.0; timeLeft = timeLimit; colorIndex = 1
        demoRecolors.clear(); demoRecolors.add(3)
        val dirs = listOf(1.0, 1.0, -1.0, 1.0)
        build({ 1.08 }, { dirs[it % dirs.size] })
        rings[0].passed = true; dots[0].used = true
    }

    fun hop() { if (done) return; vy = BOUNCE_V; SoundManager.tap(); Haptics.tap() }

    fun step(dt: Double) {
        if (done) return
        t += dt
        vy -= GRAVITY * dt; ballY += vy * dt
        if (ballY > cam) cam = ballY
        if (cam - ballY > FALL_LIMIT) { fail(); return }
        for (d in dots) {
            if (d.used || abs(d.worldY - ballY) >= BALL_R + 0.02) continue
            d.used = true
            colorIndex = if (isDemo && demoRecolors.isNotEmpty()) demoRecolors.removeAt(0)
            else (0 until arcCount).filter { it != colorIndex }.randomOrNull() ?: colorIndex
            SoundManager.tap(); Haptics.tap()
        }
        for (r in rings) {
            val d = abs(ballY - r.worldY)
            if (abs(d - ringRadius) < BALL_R + RING_THICK) {
                val phi = if (ballY < r.worldY) PI / 2 else -PI / 2
                if (colorAt(phi, r) != colorIndex) { fail(); return }
            }
            if (!r.passed && ballY > r.worldY + ringRadius) {
                r.passed = true; passed++
                SoundManager.tap(); Haptics.tap()
                if (passed >= toClear) { win(); return }
            }
        }
    }

    fun win() { if (done) return; done = true; onWin() }
    fun fail() {
        if (done) return
        done = true
        if (passed < toClear) { deathY = ANCHOR + (cam - ballY); deathT0 = nowSec() }
        SoundManager.error(); onFail()
    }
}

@Composable
private fun PrismPassView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { PrismWorld(level, isDemo).also { it.setup() } }
    world.onWin = onWin; world.onFail = onFail
    var demoTapT by remember { mutableDoubleStateOf(-10.0) }
    var demoTick by remember { mutableIntStateOf(0) }
    val start = remember { nowSec() }
    val tm = rememberTextMeasurer()
    val tick by rememberFrameLoop { dt ->
        if (isDemo || world.done) return@rememberFrameLoop
        world.timeLeft = max(0.0, world.timeLimit - (nowSec() - start))
        if (world.timeLeft <= 0) { world.fail(); return@rememberFrameLoop }
        world.step(dt)
    }

    LaunchedEffect(Unit) {
        if (!isDemo) return@LaunchedEffect
        val dt = 1.0 / 60.0
        while (isActive) {
            world.demoSetup()
            delay(400)
            var frame = 0
            while (isActive && !world.done && frame < 900) {
                frame++
                if (frame in demoTaps) { world.hop(); demoTapT = nowSec() }
                world.step(dt)
                demoTick++
                delay(16)
            }
            delay(1300)
        }
    }

    Canvas(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .then(if (isDemo) Modifier else Modifier.tapAt { world.hop() })
    ) {
        tick; demoTick
        val w = size.width.toDouble(); val h = size.height.toDouble(); val u = density.toDouble()
        drawRect(androidx.compose.ui.graphics.Brush.radialGradient(0f to rgb(0.18, 0.18, 0.19),
            (40 * u / (520 * u)).toFloat() to rgb(0.18, 0.18, 0.19), 1f to rgb(0.14, 0.14, 0.15), center = off(w / 2, h / 2), radius = (520 * u).f))
        tower(world)
        val sc = if (isDemo) 0.62 else 1.0
        score(tm, world.passed, world.toClear, if (isDemo) null else world.timeLeft / world.timeLimit, sc, (if (isDemo) 12 else 18) * u, (if (isDemo) 6 else 12) * u)
        world.deathY?.let { burst(BALL_X * w, it * h, BALL_R * 2 * h, nowSec() - world.deathT0) }
        if (isDemo) tapRipple(w * 0.74, h * 0.80, nowSec() - demoTapT)
    }
}

private fun DrawScope.tower(world: PrismWorld) {
    val w = size.width.toDouble(); val h = size.height.toDouble(); val u = density.toDouble()
    fun sy(y: Double) = (ANCHOR + (world.cam - y)) * h
    val seg = 2 * PI / world.arcCount
    for (r in world.rings) {
        val cx = BALL_X * w; val cy = sy(r.worldY)
        if (cy <= -world.ringRadius * h - 40 * u || cy >= h + world.ringRadius * h + 40 * u) continue
        val rot = world.t * r.speed * r.dir
        for (i in 0 until world.arcCount) {
            val arc = Path(); arc.arc(cx, cy, world.ringRadius * h, rot + i * seg, rot + (i + 1) * seg, moveFirst = true)
            strokePath(arc, swatch(i), RING_THICK * 2 * h, StrokeCap.Butt)
        }
    }
    for (d in world.dots) if (!d.used) switcher(BALL_X * w, sy(d.worldY), BALL_R * h * 0.95, world.arcCount)
    if (world.deathY == null) circle(BALL_X * w, sy(world.ballY), BALL_R * h, swatch(world.colorIndex))
}

/** The colour switcher: a small disc cut into one wedge per colour. */
private fun DrawScope.switcher(cx: Double, cy: Double, r: Double, n: Int) {
    for (i in 0 until n) {
        val wedge = Path(); wedge.m(cx, cy)
        wedge.arc(cx, cy, r, -PI / 2 + i.toDouble() / n * 2 * PI, -PI / 2 + (i + 1).toDouble() / n * 2 * PI)
        wedge.close()
        fillPath(wedge, swatch(i))
    }
}

/** The thin white score (rings cleared / quota) with a hairline clock under it while playing. */
private fun DrawScope.score(tm: TextMeasurer, passed: Int, total: Int, fraction: Double?, scale: Double, x: Double, top: Double) {
    val u = density.toDouble()
    val big = 44 * scale * u; val small = 18 * scale * u
    val baseY = top + big * 0.85
    val bs = "$passed"
    text(tm, bs, x, baseY, big, Color.White, FontWeight.Light, anchorX = 0.0, anchorY = 0.85)
    text(tm, "/$total", x + textWidth(tm, bs, big, FontWeight.Light) + 3 * scale * u, baseY, small, Color.White.op(0.55), FontWeight.Normal, anchorX = 0.0, anchorY = 0.85)
    if (fraction != null) {
        val f = clamp(fraction, 0.0, 1.0)
        val by = baseY + big * 0.2 + 5 * scale * u
        rrect(x, by, 90 * u, 3 * u, 1.5 * u, Color.White.op(0.18))
        if (f > 0) rrect(x, by, 90 * u * f, 3 * u, 1.5 * u, if (f < 0.3) rgb(0.98, 0.02, 0.52) else Color.White.op(0.85))
    }
}

/** The ball bursting into little coloured balls (0.8 s ease-out). */
private fun DrawScope.burst(x: Double, y: Double, size: Double, t: Double) {
    if (t < 0 || t > 0.8) return
    val k = t / 0.8; val e = 1 - (1 - k) * (1 - k)
    for (i in 0 until 22) {
        val a = i / 22.0 * 2 * PI + (i % 3) * 0.2
        val d = size * (1.6 + 0.9 * (i % 4))
        val dot = size * (0.28 + 0.08 * (i % 3))
        circle(x + cos(a) * d * e, y + (sin(a) * d + size * 0.8) * e, dot / 2, allColors[i % 4].op(1 - e))
    }
}
