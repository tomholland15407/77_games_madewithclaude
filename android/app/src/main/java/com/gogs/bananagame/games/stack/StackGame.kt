package com.gogs.bananagame.games.stack

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
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Reflex — Stack (iOS StackGame.swift): tap to drop the sliding slab; overhang is sliced away.
 * Stack the quota before the clock; missing the tower entirely fails.
 */
object StackGame {
    val definition = GameDefinition(
        id = "stack",
        title = "Stack",
        genre = Genre.REFLEX,
        manual = GameManual(
            bullets = listOf(
                "A slab slides back and forth atop the tower.",
                "Tap to drop it — any overhang past the slab below is sliced off, so the tower narrows.",
                "Stack the level's quota of slabs to win.",
                "Miss the tower entirely, or run out of time, and you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Một tấm trượt qua lại trên đỉnh tháp.",
                "Chạm để thả nó — phần thừa ra ngoài tấm bên dưới bị cắt bỏ, nên tháp hẹp dần.",
                "Xếp đủ số tấm của cấp để thắng.",
                "Trượt hụt cả tháp, hoặc hết giờ, sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> StackView(level, onWin, onFail) }
    )
}

private const val ACTIVE_Y = 0.30
private const val SLAB_H = 0.045
private val demoMiss = listOf(0.0, 0.03, 0.0, -0.02, 0.018, 0.0, -0.012, 0.0)

private class Slab(val cx: Double, val hw: Double)
/** A sliced-off overhang (or the whole missed slab) falling away. */
private class Chip(val level: Int, val x0: Double, val x1: Double, val side: Int, val born: Double)
/** The white square ring of a perfect drop. */
private class Ring(val level: Int, val cx: Double, val hw: Double, val born: Double)

private class StackWorld(level: Int) {
    private val li = min(level, 7) - 1
    val slabSpeed = listOf(0.50, 0.62, 0.75, 0.90, 1.05, 1.25, 1.45)[li]
    val startHalf = listOf(0.24, 0.22, 0.20, 0.18, 0.16, 0.15, 0.14)[li]
    val target = listOf(8, 10, 12, 14, 16, 18, 20)[li]
    val timeLimit = listOf(30.0, 28.0, 26.0, 24.0, 22.0, 20.0, 18.0)[li]
    val baseHue = listOf(0.50, 0.55, 0.35, 0.08, 0.85, 0.62, 0.13)[li]

    val slabs = mutableListOf<Slab>()
    val chips = mutableListOf<Chip>()
    val rings = mutableListOf<Ring>()
    var movingCx = 0.24; var movingHw = 0.24; var dir = 1.0
    var added = 0
    var timeLeft = timeLimit
    var done = false
    var missed = false
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    fun setup() {
        slabs.clear(); slabs.add(Slab(0.5, startHalf))
        chips.clear(); rings.clear()
        movingHw = startHalf; movingCx = movingHw; dir = 1.0
        added = 0; done = false; missed = false; timeLeft = timeLimit
    }

    fun step(dt: Double) {
        if (done) return
        movingCx += dir * slabSpeed * dt
        if (movingCx > 1 - movingHw) { movingCx = 1 - movingHw; dir = -1.0 }
        if (movingCx < movingHw) { movingCx = movingHw; dir = 1.0 }
    }

    fun drop() {
        if (done) return
        val below = slabs.last()
        val perfect = abs(movingCx - below.cx) < 0.012
        val cx: Double; val hw: Double
        if (perfect) { cx = below.cx; hw = movingHw } else {
            val l = max(below.cx - below.hw, movingCx - movingHw)
            val r = min(below.cx + below.hw, movingCx + movingHw)
            if (r - l <= 0.001) {
                // A miss: the whole slab falls away.
                missed = true
                chips.add(Chip(slabs.size, movingCx - movingHw, movingCx + movingHw, if (movingCx >= below.cx) 1 else -1, nowSec()))
                fail(); return
            }
            cx = (l + r) / 2; hw = (r - l) / 2
        }
        slabs.add(Slab(cx, hw))
        Haptics.tap(); SoundManager.tap()
        val now = nowSec()
        if (perfect) rings.add(Ring(slabs.size - 1, cx, hw, now))
        else if (hw < below.hw - 0.0001) {
            val right = cx > below.cx
            val x0 = if (right) below.cx + below.hw else cx + hw - 2 * below.hw
            val x1 = if (right) cx - hw + 2 * below.hw else below.cx - below.hw
            chips.add(Chip(slabs.size - 1, x0, x1, if (right) 1 else -1, now))
        }
        chips.removeAll { now - it.born > 1.3 }; rings.removeAll { now - it.born > 1.3 }
        movingHw = hw; movingCx = movingHw; dir = 1.0
        added++
        if (added >= target) win()
    }

    fun win() { if (done) return; done = true; onWin() }
    fun fail() { if (done) return; done = true; SoundManager.error(); onFail() }
}

@Composable
private fun StackView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { StackWorld(level).also { it.setup() } }
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
            world.setup()
            delay(500)
            while (isActive && !world.done) {
                world.step(dt)
                val below = world.slabs.last()
                if (world.dir > 0 && world.movingCx >= below.cx + demoMiss[world.added % demoMiss.size]) {
                    world.drop(); demoTapT = nowSec()
                    delay(180)
                }
                demoTick++
                delay(16)
            }
            delay(1300)
        }
    }

    Canvas(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .then(if (isDemo) Modifier else Modifier.tapAt { world.drop() })
    ) {
        tick; demoTick
        val w = size.width.toDouble(); val h = size.height.toDouble()
        sky((world.baseHue + world.added * 0.018 + 0.5) % 1.0)
        drawTower(world, w, h, nowSec())
        scoreboard(tm, world, h, isDemo)
        if (isDemo) tapRipple(w * 0.5, h * 0.72, nowSec() - demoTapT)
    }
}

/** The iso camera: logic x runs down-right, depth z down-left, elevation in levels. */
private class Iso(val scale: Double, val thick: Double, val midX: Double, val topY: Double, val top: Int, val depth: Double) {
    fun p(x: Double, z: Double, e: Double) = P(midX + (x - 0.5 - z) * scale * 0.866, topY + (x - 0.5 + z) * scale * 0.5 - (e - (top + 1)) * thick)
}

private fun hueOf(base: Double, level: Int) = (base + level * 0.018) % 1.0

private fun DrawScope.drawTower(world: StackWorld, w: Double, h: Double, now: Double) {
    val d = world.startHalf
    val iso = Iso(0.94 * min(w, h * 0.68) / (0.866 * (1 + 2 * d)), SLAB_H * h * 0.9, w / 2, ACTIVE_Y * h, world.slabs.size, d)
    val n = world.slabs.size
    for (c in world.chips) if (c.side < 0) chip(c, iso, h, now, world.baseHue)
    val first = max(0, n - (h / max(1.0, iso.thick)).toInt() - 2)
    for (i in first until n) {
        val s = world.slabs[i]
        slab(iso, s.cx - s.hw, s.cx + s.hw, i, hueOf(world.baseHue, i), min(0.5, (n - i) * 0.028), if (i == 0) h * 2 else 0.0)
    }
    for (r in world.rings) ring(r, iso, now)
    for (c in world.chips) if (c.side > 0) chip(c, iso, h, now, world.baseHue)
    if (!world.missed) slab(iso, world.movingCx - world.movingHw, world.movingCx + world.movingHw, n, hueOf(world.baseHue, n), 0.0, 0.0)
}

private fun DrawScope.chip(c: Chip, iso: Iso, h: Double, now: Double, base: Double) {
    val age = max(0.0, now - c.born)
    if (age >= 1.3) return
    translate((c.side * age * iso.scale * 0.12 * 0.866).f, (0.5 * h * 2.4 * age * age + c.side * age * iso.scale * 0.12 * 0.5).f) {
        withAlpha(clamp((1.3 - age) / 0.5, 0.0, 1.0)) { slab(iso, c.x0, c.x1, c.level, hueOf(base, c.level), 0.0, 0.0) }
    }
}

private fun quad(a: P, b: P, c: P, d: P) = polyPath(listOf(a, b, c, d))

/** One slab: a lit top and the two camera-facing sides; `down` extends the sides off-screen (the base). */
private fun DrawScope.slab(iso: Iso, x0: Double, x1: Double, level: Int, hue: Double, shade: Double, down: Double) {
    if (x1 - x0 <= 0.0005) return
    val d = iso.depth
    val et = (level + 1).toDouble(); val eb = level - down / max(1.0, iso.thick)
    fillPath(quad(iso.p(x0, d, et), iso.p(x1, d, et), iso.p(x1, d, eb), iso.p(x0, d, eb)), hsb(hue, 0.5, 0.84).shade(shade))
    fillPath(quad(iso.p(x1, -d, et), iso.p(x1, d, et), iso.p(x1, d, eb), iso.p(x1, -d, eb)), hsb(hue, 0.56, 0.7).shade(shade))
    fillPath(quad(iso.p(x0, -d, et), iso.p(x1, -d, et), iso.p(x1, d, et), iso.p(x0, d, et)), hsb(hue, 0.42, 0.98).shade(shade))
}

private fun DrawScope.ring(r: Ring, iso: Iso, now: Double) {
    val age = now - r.born
    if (age < 0 || age >= 0.6) return
    val alpha = 1 - age / 0.6
    for ((k, lw) in listOf(1.08 + age * 0.7 to 3.0, 1.2 + age * 1.0 to 1.5)) {
        val hw = r.hw * k; val d = iso.depth * k; val e = (r.level + 1).toDouble()
        strokePath(quad(iso.p(r.cx - hw, -d, e), iso.p(r.cx + hw, -d, e), iso.p(r.cx + hw, d, e), iso.p(r.cx - hw, d, e)), Color.White.op(alpha), lw * density)
    }
}

private fun hash(n: Double): Double { val v = sin(n * 12.9898) * 43758.5453; return v - floor(v) }

/** The two-tone sky and its floating dust. */
private fun DrawScope.sky(hue: Double) {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    rect(0.0, 0.0, w, h, vgrad(listOf(hsb(hue, 0.5, 0.74), hsb((hue + 0.93) % 1.0, 0.3, 0.97)), 0.0, h))
    for (i in 0 until 16) {
        val k = i.toDouble(); val s = (2 + hash(k + 4) * 2.5) * u
        rect(hash(k) * w, hash(k + 9) * h * 0.85, s, s, Color.White.op(0.45 + hash(k + 2) * 0.45))
    }
}

/** The big thin score with the slab goal beside it, and (while playing) a hairline clock. */
private fun DrawScope.scoreboard(tm: TextMeasurer, world: StackWorld, h: Double, isDemo: Boolean) {
    val u = density.toDouble()
    val w = size.width.toDouble()
    val big = if (isDemo) h * 0.075 else max(34 * u, h * 0.085)
    val small = max(15 * u, h * 0.03)
    val top = if (isDemo) 2 * u else h * 0.045
    val bigS = "${world.added}"; val smallS = "/${world.target}"
    val bw = textWidth(tm, bigS, big, FontWeight.Thin); val sw = textWidth(tm, smallS, small, FontWeight.Light)
    val x0 = w / 2 - (bw + 4 * u + sw) / 2
    val baseY = top + big * 1.0
    text(tm, bigS, x0, baseY, big, Color.White, FontWeight.Thin, anchorX = 0.0, anchorY = 0.85)
    text(tm, smallS, x0 + bw + 4 * u, baseY, small, Color.White.op(0.7), FontWeight.Light, anchorX = 0.0, anchorY = 0.85)
    if (!isDemo) {
        val f = clamp(world.timeLeft / world.timeLimit, 0.0, 1.0)
        val by = baseY + big * 0.2 + 6 * u; val bx = w / 2 - 60 * u
        rrect(bx, by, 120 * u, 3 * u, 1.5 * u, Color.White.op(0.25))
        if (f > 0) rrect(bx, by, 120 * u * f, 3 * u, 1.5 * u, if (f < 0.3) rgb(1.0, 0.3, 0.3) else Color.White.op(0.9))
    }
}
