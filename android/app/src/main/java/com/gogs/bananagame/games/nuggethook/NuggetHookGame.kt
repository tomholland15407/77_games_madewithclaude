package com.gogs.bananagame.games.nuggethook

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** Reflex — Nugget Hook (was "Gold Miner"; iOS GoldMinerGame.swift): the Flash claw-grab classic. */
object NuggetHookGame {
    val definition = GameDefinition(
        id = "gold-miner",
        title = "Nugget Hook",
        genre = Genre.REFLEX,
        manual = GameManual(
            bullets = listOf(
                "The claw swings on its rope; tap anywhere to fire it along its current angle.",
                "It grabs the first thing it hits and reels it up — rocks and big nuggets reel slowly.",
                "Hit the money GOAL before the clock runs out; rocks deduct money, so avoid them.",
            ),
            bulletsVI = listOf(
                "Móc câu đung đưa trên dây; chạm bất kỳ đâu để phóng theo góc hiện tại.",
                "Nó tóm vật đầu tiên chạm phải và kéo lên — đá và cục vàng lớn kéo chậm.",
                "Đạt MỤC TIÊU tiền trước khi hết giờ; đá trừ tiền, nên hãy tránh.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> NuggetHookView(level, onWin, onFail) }
    )
}

private enum class Kind { GOLD, ROCK, DIAMOND, MYSTERY }
private enum class Hook { SWING, EXTEND, REEL }

private var objIds = 0
private class Obj(val x: Double, val y: Double, val rFrac: Double, val value: Int, val reelFactor: Double, val kind: Kind, val seed: Double) {
    val id = ++objIds
}
private class Gain(val value: Int, val t0: Double)
private class BurstMark(val x: Double, val y: Double, val color: Color, val t0: Double = nowSec())

private const val MAX_ANGLE = 1.35
private const val REST_LEN = 0.05
private const val MAX_LEN = 0.78
private const val EXTEND_SPEED = 1.25
private const val REEL_EMPTY = 1.9

private class MinerWorld(val level: Int) {
    val goalFrac = listOf(0.35, 0.45, 0.55, 0.62, 0.70, 0.78, 0.85)[min(level, 7) - 1]
    val timeLimit = listOf(40.0, 38.0, 35.0, 32.0, 29.0, 26.0, 24.0)[min(level, 7) - 1]
    val swingSpeed = listOf(3.0, 3.5, 4.0, 4.5, 5.0, 5.6, 6.3)[min(level, 7) - 1]
    val goldCount = listOf(8, 8, 8, 9, 9, 10, 10)[min(level, 7) - 1]
    val rockCount = listOf(1, 2, 3, 4, 5, 7, 9)[min(level, 7) - 1]
    val diamondCount = listOf(1, 1, 1, 2, 2, 2, 3)[min(level, 7) - 1]
    val mysteryCount = listOf(1, 1, 1, 1, 2, 2, 2)[min(level, 7) - 1]
    val rockPenalty = 100 + (min(level, 7) - 1) * 50

    var playing = true
    var hook = Hook.SWING
    var w = 0.0; var h = 0.0
    var objects = mutableListOf<Obj>()
    var money = 0
    var goal = 0
    var timeLeft = timeLimit
    var swingPhase = 0.0
    var angle = 0.0
    var ropeLen = REST_LEN
    var grabbed: Obj? = null
    var bursts = mutableListOf<BurstMark>()
    var gains = mutableListOf<Gain>()
    var shakeT0 = -10.0
    var rippleT0 = -10.0
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    fun pivotX() = w * 0.5
    fun pivotY() = h * 0.205
    fun tip() = P(pivotX() + sin(angle) * ropeLen * h, pivotY() + cos(angle) * ropeLen * h)

    fun setup() {
        val objs = ArrayList<Obj>()
        fun place(rFrac: Double, value: Int, factor: Double, kind: Kind, force: Boolean = false): Boolean {
            repeat(40) {
                val x = rnd(0.08, 0.92); val y = rnd(0.34, 0.93)
                if (objs.all { o -> hypot(o.x - x, o.y - y) > (o.rFrac + rFrac) * 1.6 }) {
                    objs.add(Obj(x, y, rFrac, value, factor, kind, rnd(0.0, 6.28))); return true
                }
            }
            if (force) { objs.add(Obj(rnd(0.08, 0.92), rnd(0.34, 0.93), rFrac, value, factor, kind, rnd(0.0, 6.28))); return true }
            return false
        }
        repeat(goldCount) {
            when (rndInt(0..2)) {
                0 -> place(0.034, 60, 1.0, Kind.GOLD)
                1 -> place(0.050, 140, 0.72, Kind.GOLD)
                else -> place(0.074, 320, 0.46, Kind.GOLD)
            }
        }
        repeat(diamondCount) { place(0.028, 560, 1.15, Kind.DIAMOND) }
        repeat(mysteryCount) { place(0.040, rndInt(80..420), 0.8, Kind.MYSTERY) }
        repeat(rockCount) {
            if (rndBool()) place(0.056, -rockPenalty, 0.42, Kind.ROCK) else place(0.078, -(rockPenalty * 3 / 2), 0.30, Kind.ROCK)
        }
        if (objs.none { it.kind == Kind.ROCK }) place(0.056, -rockPenalty, 0.42, Kind.ROCK, force = true)
        objects = objs
        val potential = objs.filter { it.kind != Kind.ROCK }.sumOf { it.value }
        goal = max(100, ((potential * goalFrac).toInt() / 10) * 10)
        money = 0; timeLeft = timeLimit; swingPhase = 0.0; angle = 0.0; ropeLen = REST_LEN
        hook = Hook.SWING; grabbed = null; playing = true
    }

    fun demoSetup() {
        objects = mutableListOf(
            Obj(0.5, 0.62, 0.074, 320, 0.46, Kind.GOLD, 1.0),
            Obj(0.24, 0.50, 0.050, 140, 0.72, Kind.GOLD, 2.4),
            Obj(0.78, 0.70, 0.050, 140, 0.72, Kind.GOLD, 3.1),
            Obj(0.62, 0.86, 0.028, 560, 1.15, Kind.DIAMOND, 4.7),
        )
        goal = 300; money = 0; timeLeft = timeLimit; swingPhase = 0.0; angle = 0.0; ropeLen = REST_LEN
        hook = Hook.SWING; grabbed = null; bursts.clear(); gains.clear(); playing = true
    }

    fun step(dt: Double) {
        if (!playing || w <= 0) return
        when (hook) {
            Hook.SWING -> { swingPhase += dt * swingSpeed; angle = MAX_ANGLE * sin(swingPhase); ropeLen = REST_LEN }
            Hook.EXTEND -> {
                ropeLen += EXTEND_SPEED * dt
                val t = tip()
                val hookR = min(w, h) * 0.02
                val hit = objects.firstOrNull { hypot(it.x * w - t.x, it.y * h - t.y) < it.rFrac * min(w, h) + hookR }
                if (hit != null) {
                    grabbed = hit
                    Haptics.tap(); SoundManager.tap()
                    hook = Hook.REEL
                } else if (ropeLen >= MAX_LEN || t.x < w * 0.02 || t.x > w * 0.98 || t.y > h * 0.97) hook = Hook.REEL
            }
            Hook.REEL -> {
                val g = grabbed
                val speed = if (g == null) REEL_EMPTY else REEL_EMPTY * 0.55 * g.reelFactor
                ropeLen -= speed * dt
                if (ropeLen <= REST_LEN) {
                    ropeLen = REST_LEN
                    if (g != null) { deposit(g); grabbed = null }
                    hook = Hook.SWING
                }
            }
        }
        timeLeft -= dt
        if (timeLeft <= 0) { timeLeft = 0.0; if (money >= goal) win() else fail() }
    }

    fun fire() {
        if (!playing || hook != Hook.SWING) return
        hook = Hook.EXTEND
        SoundManager.tap(); Haptics.tap()
    }

    fun deposit(g: Obj) {
        objects.removeAll { it.id == g.id }
        money = max(0, money + g.value)
        val color = if (g.kind == Kind.ROCK) rgb(0.9, 0.4, 0.4) else if (g.kind == Kind.DIAMOND) rgb(0.6, 0.9, 1.0) else BananaTheme.banana
        bursts.add(BurstMark(w * 0.5, h * 0.14, color))
        gains.add(Gain(g.value, nowSec()))
        if (gains.size > 4) gains.removeAt(0)
        if (g.kind == Kind.ROCK) { shakeT0 = nowSec(); SoundManager.error(); Haptics.warning() }
        else { if (g.value >= 250) shakeT0 = nowSec(); SoundManager.tap(); Haptics.success() }
        if (money >= goal) win()
    }

    fun win() { if (!playing) return; playing = false; Haptics.success(); SoundManager.tap(); onWin() }
    fun fail() { if (!playing) return; playing = false; Haptics.warning(); SoundManager.error(); onFail() }
}

private val CRANK_A = StickPose(P(0.44, 0.17), 0.1, P(0.46, 0.29), P(0.44, 0.6), P(0.35, 0.43), P(0.36, 0.57), P(0.62, 0.37), P(0.8, 0.33),
    P(0.39, 0.79), P(0.35, 0.98), P(0.53, 0.79), P(0.58, 0.98))
private val CRANK_B = StickPose(P(0.45, 0.18), 0.1, P(0.46, 0.3), P(0.44, 0.6), P(0.35, 0.43), P(0.36, 0.57), P(0.63, 0.46), P(0.8, 0.47),
    P(0.39, 0.79), P(0.35, 0.98), P(0.53, 0.79), P(0.58, 0.98))

@Composable
private fun NuggetHookView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { MinerWorld(level) }
    world.onWin = onWin; world.onFail = onFail
    var built by remember { mutableStateOf(false) }
    var demoFired by remember { mutableStateOf(false) }
    val tm = rememberTextMeasurer()

    val tick by rememberFrameLoop(running = true) { dt ->
        if (world.w <= 0) return@rememberFrameLoop
        if (!built && !isDemo) { world.setup(); built = true }
        if (isDemo) {
            if (!demoFired && world.hook == Hook.SWING && abs(world.angle) < 0.05) {
                world.rippleT0 = nowSec(); world.fire(); demoFired = true
            }
        }
        world.step(dt)
    }
    LaunchedEffect(Unit) {
        if (!isDemo) return@LaunchedEffect
        while (world.w <= 0) delay(20)
        while (isActive) {
            world.demoSetup(); demoFired = false; built = true
            while (world.playing && isActive) delay(16)
            delay(1300)
        }
    }

    BoxWithConstraints(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .graphicsLayer {
                val t = nowSec() - world.shakeT0
                if (t in 0.0..0.35) {
                    val k = sin(t / 0.35 * PI * 3)
                    translationX = (6 * density * k).toFloat(); translationY = (3.6 * density * k).toFloat()
                }
            }
            .tapAt { if (!isDemo) world.fire() }
    ) {
        world.w = constraints.maxWidth.toDouble(); world.h = constraints.maxHeight.toDouble()
        Canvas(Modifier.fillMaxSize()) {
            tick
            val w = size.width.toDouble(); val h = size.height.toDouble()
            backdrop(w, h)
            val fh = h * 0.15
            val cranking = world.hook == Hook.REEL && (world.ropeLen * 40).toInt() % 2 == 0
            val pose = if (cranking) CRANK_A else CRANK_B
            val fx = world.pivotX() - fh * 0.52 - fh * 0.45; val fy = h * 0.24 - fh
            stickFigure(pose, fx, fy, fh * 0.9, fh, rgb(0.28, 0.2, 0.16), lineFrac = 0.07)
            hatAndBeard(fx, fy, fh * 0.9, fh, pose)
            drawField(world, tm)
            val now = nowSec()
            world.bursts.removeAll { now - it.t0 > 0.6 }
            for (b in world.bursts) particleBurst(b.x, b.y, now - b.t0, b.color, 14, 46.0)
            if (isDemo) tapRipple(w * 0.5, h * 0.78, now - world.rippleT0)
            hud(world, tm, isDemo)
        }
    }
}

private fun DrawScope.hud(world: MinerWorld, tm: TextMeasurer, isDemo: Boolean) {
    val u = density.toDouble()
    val sz = (if (isDemo) 13.0 else 17.0) * u
    val label = rgb(0.36, 0.16, 0.02)
    val shadow = rgb(0.3, 0.12, 0.0)
    fun line(x: Double, y: Double, l: String, v: String, color: Color, rightAlign: Boolean = false) {
        val lw = textWidth(tm, "$l:", sz, FontWeight.Black)
        val vw = textWidth(tm, v, sz, FontWeight.Black)
        val x0 = if (rightAlign) x - lw - 5 * u - vw else x
        text(tm, "$l:", x0, y, sz, label, FontWeight.Black, anchorX = 0.0, anchorY = 0.0)
        text(tm, v, x0 + lw + 5 * u + 1.5 * u, y + 1.5 * u, sz, shadow, FontWeight.Black, anchorX = 0.0, anchorY = 0.0)
        text(tm, v, x0 + lw + 5 * u, y, sz, color, FontWeight.Black, anchorX = 0.0, anchorY = 0.0)
    }
    val px = (if (isDemo) 10.0 else 14.0) * u
    val top = (if (isDemo) 6.0 else 10.0) * u
    val lh = sz * 1.25 + (if (isDemo) 0.0 else 2 * u)
    line(px, top, L("Money", "Tiền"), "$${world.money}", if (world.money >= world.goal) rgb(0.55, 1.0, 0.55) else Color.White)
    line(px, top + lh, L("Goal", "Mục tiêu"), "$${world.goal}", rgb(1.0, 0.93, 0.4))
    if (!isDemo) line(size.width - px, top, L("Time", "Giờ"), "${ceil(world.timeLeft).toInt()}",
        if (world.timeLeft < world.timeLimit * 0.3) rgb(1.0, 0.35, 0.3) else Color.White, rightAlign = true)
}

private fun DrawScope.drawField(world: MinerWorld, tm: TextMeasurer) {
    val w = world.w; val h = world.h
    val m = min(w, h)
    val px = world.pivotX(); val py = world.pivotY()
    for (o in world.objects) if (world.grabbed?.id != o.id) MinerArt.treasure(this, tm, o.kind, o.x * w, o.y * h, o.rFrac * m, o.seed)
    val t = world.tip()
    line(px, py, t.x, t.y, rgb(0.2, 0.14, 0.08), max(2.0, m * 0.006), StrokeCap.Butt)
    world.grabbed?.let { g ->
        val r = g.rFrac * m
        MinerArt.treasure(this, tm, g.kind, t.x + sin(world.angle) * r, t.y + cos(world.angle) * r, r, g.seed)
    }
    MinerArt.claw(this, t.x, t.y, world.angle, m * 0.03, world.grabbed == null)
    MinerArt.winch(this, px, py, m * 0.06, world.ropeLen * 40)
    val now = nowSec()
    for (gain in world.gains) {
        val tt = now - gain.t0
        if (tt >= 1.1) continue
        val a = if (tt > 0.8) max(0.0, (1.1 - tt) / 0.3) else 1.0
        val gx = px + m * 0.16; val gy = py - m * 0.04 - tt * m * 0.08
        val s = if (gain.value >= 0) "+$${gain.value}" else "-$${-gain.value}"
        text(tm, s, gx + 1.5, gy + 1.5, m * 0.05, rgb(0.3, 0.12, 0.0).op(a), FontWeight.Black)
        text(tm, s, gx, gy, m * 0.05, (if (gain.value >= 0) rgb(0.55, 1.0, 0.5) else rgb(1.0, 0.4, 0.35)).op(a), FontWeight.Black)
    }
}

private fun DrawScope.hatAndBeard(x: Double, y: Double, w: Double, h: Double, pose: StickPose) {
    val hcx = x + w / 2 + (pose.head.x - 0.5) * h; val hcy = y + pose.head.y * h
    val r = pose.headR * h
    val ink = rgb(0.22, 0.14, 0.05)
    val beard = Path(); beard.m(hcx - r * 0.35, hcy + r * 0.1)
    beard.q(hcx + r * 0.2, hcy + r * 1.9, hcx + r * 1.05, hcy + r * 0.2)
    beard.q(hcx + r * 0.4, hcy + r * 0.45, hcx - r * 0.35, hcy + r * 0.1); beard.close()
    drawPath(beard, Color.White)
    strokePath(beard, rgb(0.6, 0.6, 0.62), max(0.8, r * 0.1))
    oval(hcx + r * 0.62, hcy - r * 0.2, r * 0.62, r * 0.5, rgb(1.0, 0.72, 0.58))
    ellipseStroke(hcx + r * 0.93, hcy + r * 0.05, r * 0.31, r * 0.25, ink, max(0.8, r * 0.08))
    val hat = Path(); hat.m(hcx - r * 1.05, hcy - r * 0.25); hat.q(hcx, hcy - r * 2.1, hcx + r * 1.05, hcy - r * 0.25); hat.close()
    drawPath(hat, vgrad(listOf(rgb(1.0, 0.9, 0.35), rgb(0.95, 0.72, 0.05)), hcy - r * 1.4, hcy - r * 0.2))
    strokePath(hat, ink, max(0.8, r * 0.1))
    rrect(hcx - r * 1.3, hcy - r * 0.38, r * 2.75, r * 0.3, r * 0.12, rgb(0.95, 0.75, 0.08))
    rrectStroke(hcx - r * 1.3, hcy - r * 0.38, r * 2.75, r * 0.3, r * 0.12, ink, max(0.8, r * 0.1))
    oval(hcx + r * 0.2, hcy - r * 1.05, r * 0.5, r * 0.45, rgb(1.0, 1.0, 0.8))
}

private fun DrawScope.backdrop(w: Double, h: Double) {
    val groundY = h * 0.24
    rect(0.0, groundY, w, h - groundY, vgrad(listOf(rgb(0.97, 0.8, 0.47), rgb(0.86, 0.6, 0.3), rgb(0.66, 0.42, 0.19)), groundY, h))
    listOf(0.36, 0.52, 0.68, 0.84).forEachIndexed { i, f ->
        val y0 = h * f
        val band = Path(); band.m(0.0, y0)
        var x = 0.0
        while (x <= w + 1) { band.l(x, y0 + sin(x / w * 7 + i * 1.9) * h * 0.012); x += w / 40 }
        x = w
        while (x >= -1) { band.l(x, y0 + h * 0.055 + sin(x / w * 6 + i * 2.7) * h * 0.014); x -= w / 40 }
        band.close()
        drawPath(band, rgb(0.62, 0.38, 0.15, 0.18))
    }
    val u = density.toDouble()
    for (k in 0 until 60) {
        val fx = abs((sin(k * 12.9898) * 43758.5453) % 1.0)
        val fy = abs((sin(k * 78.233) * 12345.678) % 1.0)
        val r = (1.2 + k % 3) * u
        oval(fx * w, groundY + 6 * u + fy * (h - groundY - 10 * u), r * 2, r * 1.4, rgb(0.45, 0.28, 0.12, 0.35))
    }
    rect(0.0, 0.0, w, groundY, vgrad(listOf(rgb(1.0, 0.74, 0.2), rgb(0.98, 0.6, 0.1)), 0.0, groundY))
    val R = groundY * 0.8
    val dome = Path(); dome.m(w / 2 - R, groundY); dome.arc(w / 2, groundY, R, PI, 0.0); dome.close()
    drawPath(dome, vgrad(listOf(rgb(0.2, 0.3, 0.62), rgb(0.1, 0.16, 0.44)), groundY - R, groundY))
    strokePath(dome, rgb(0.06, 0.08, 0.25), 2 * u)
    rect(0.0, groundY - 1.5 * u, w, 4 * u, rgb(0.45, 0.26, 0.08))
}

private object MinerArt {
    fun c(r: Double, g: Double, b: Double) = rgb(r, g, b)

    fun blob(cx: Double, cy: Double, r: Double, seed: Double, lumpy: Double = 0.13): Path {
        val p = Path()
        val n = 16
        for (i in 0..n) {
            val a = i.toDouble() / n * 2 * PI
            val rr = r * (1 + lumpy * sin(a * 3 + seed) + 0.06 * cos(a * 5 + seed * 1.7))
            val x = cx + cos(a) * rr; val y = cy + sin(a) * rr
            if (i == 0) p.m(x, y) else p.l(x, y)
        }
        p.close()
        return p
    }

    fun treasure(d: DrawScope, tm: TextMeasurer, kind: Kind, px: Double, py: Double, r: Double, seed: Double) = with(d) {
        when (kind) {
            Kind.GOLD -> {
                val b = blob(px, py, r, seed)
                drawPath(b, radial(listOf(c(1.0, 0.97, 0.62), c(1.0, 0.82, 0.16), c(0.82, 0.56, 0.04)), px - r * 0.35, py - r * 0.4, r * 1.5))
                for (k in 0 until 3) {
                    val a = seed + k * 2.1
                    ellipse(px + cos(a) * r * 0.45, py + sin(a) * r * 0.4, r * 0.12, r * 0.09, c(0.85, 0.6, 0.05).op(0.55))
                }
                strokePath(b, c(0.55, 0.34, 0.0), max(1.0, r * 0.07))
                oval(px - r * 0.55, py - r * 0.62, r * 0.5, r * 0.3, Color.White.op(0.75))
                oval(px + r * 0.2, py - r * 0.35, r * 0.16, r * 0.12, Color.White.op(0.6))
            }
            Kind.ROCK -> {
                val b = blob(px, py, r, seed, 0.09)
                drawPath(b, radial(listOf(c(0.78, 0.78, 0.8), c(0.56, 0.57, 0.6), c(0.38, 0.39, 0.43)), px - r * 0.3, py - r * 0.4, r * 1.4))
                val crack = Path()
                crack.m(px - r * 0.1, py - r * 0.55); crack.l(px + r * 0.05, py - r * 0.1); crack.l(px - r * 0.15, py + r * 0.25)
                crack.m(px + r * 0.05, py - r * 0.1); crack.l(px + r * 0.45, py + r * 0.05)
                strokePath(crack, c(0.28, 0.28, 0.32), max(1.0, r * 0.06))
                strokePath(b, c(0.24, 0.25, 0.28), max(1.0, r * 0.07))
                oval(px - r * 0.5, py - r * 0.55, r * 0.35, r * 0.2, Color.White.op(0.35))
            }
            Kind.DIAMOND -> {
                val gem = polyPath(px - r * 0.62, py - r * 0.5, px + r * 0.62, py - r * 0.5, px + r, py - r * 0.1, px, py + r, px - r, py - r * 0.1)
                circle(px, py, r * 1.6, radial(listOf(c(0.7, 0.95, 1.0).op(0.55), Color.Transparent), px, py, r * 1.6))
                drawPath(gem, lin(listOf(c(0.85, 1.0, 1.0), c(0.35, 0.8, 1.0), c(0.12, 0.45, 0.85)), px - r, py - r, px + r, py + r))
                val f = Path()
                f.m(px - r, py - r * 0.1); f.l(px + r, py - r * 0.1)
                f.m(px - r * 0.3, py - r * 0.5); f.l(px - r * 0.45, py - r * 0.1); f.l(px, py + r)
                f.m(px + r * 0.3, py - r * 0.5); f.l(px + r * 0.45, py - r * 0.1); f.l(px, py + r)
                strokePath(f, Color.White.op(0.7), max(0.6, r * 0.06))
                strokePath(gem, c(0.1, 0.3, 0.6), max(1.0, r * 0.08))
            }
            Kind.MYSTERY -> {
                val sack = Path(); sack.m(px - r * 0.35, py - r * 0.55)
                sack.q(px - r * 1.05, py - r * 0.2, px - r * 0.95, py + r * 0.55)
                sack.q(px, py + r * 1.2, px + r * 0.95, py + r * 0.55)
                sack.q(px + r * 1.05, py - r * 0.2, px + r * 0.35, py - r * 0.55); sack.close()
                drawPath(sack, lin(listOf(c(0.72, 0.5, 0.26), c(0.5, 0.32, 0.14)), px - r, py - r, px + r, py + r))
                strokePath(sack, c(0.3, 0.18, 0.07), max(1.0, r * 0.07))
                val neck = polyPath(px - r * 0.35, py - r * 0.55, px - r * 0.5, py - r * 0.95, px + r * 0.5, py - r * 0.95, px + r * 0.35, py - r * 0.55, close = false)
                drawPath(neck, c(0.62, 0.42, 0.2))
                strokePath(neck, c(0.3, 0.18, 0.07), max(1.0, r * 0.06))
                rrect(px - r * 0.45, py - r * 0.62, r * 0.9, r * 0.16, r * 0.06, c(0.9, 0.78, 0.45))
                text(tm, "?", px, py + r * 0.22, r * 1.05, c(0.3, 0.15, 0.04), FontWeight.Black)
            }
        }
    }

    fun claw(d: DrawScope, tx: Double, ty: Double, angle: Double, s: Double, open: Boolean) = with(d) {
        translate(tx.f, ty.f) {
            rotate((-angle * 180 / PI).f, androidx.compose.ui.geometry.Offset.Zero) {
                val spread = if (open) 1.0 else 0.45
                val prongs = Path()
                for (side in listOf(-1.0, 1.0)) {
                    prongs.m(0.0, 0.0)
                    prongs.q(side * s * 1.2 * spread, s * 0.55, side * s * 0.35 * spread, s * 1.3)
                }
                strokePath(prongs, c(0.18, 0.18, 0.2), s * 0.42)
                strokePath(prongs, c(0.78, 0.8, 0.84), s * 0.24)
                rrect(-s * 0.14, -s * 0.6, s * 0.28, s * 0.6, s * 0.08, c(0.5, 0.52, 0.56))
                circle(0.0, 0.0, s * 0.34, radial(listOf(c(0.9, 0.92, 0.95), c(0.45, 0.47, 0.52)), -s * 0.1, -s * 0.1, s * 0.4))
                circleStroke(0.0, 0.0, s * 0.34, c(0.18, 0.18, 0.2), max(1.0, s * 0.08))
            }
        }
    }

    fun winch(d: DrawScope, px: Double, py: Double, s: Double, turn: Double) = with(d) {
        val wood = c(0.6, 0.38, 0.18); val dark = c(0.32, 0.19, 0.08)
        for (sx in listOf(-1.0, 1.0)) {
            line(px + sx * s * 0.7, py + s * 0.95, px, py, dark, s * 0.2)
            line(px + sx * s * 0.7, py + s * 0.95, px, py, wood, s * 0.12)
        }
        val r = s * 0.55
        circle(px, py, r, wood)
        for (k in 0 until 4) {
            val a = turn + k * PI / 2
            line(px, py, px + cos(a) * r * 0.9, py + sin(a) * r * 0.9, dark, max(1.0, s * 0.08), StrokeCap.Butt)
        }
        circleStroke(px, py, r, dark, max(1.0, s * 0.1))
        circle(px + cos(turn) * r * 0.75, py + sin(turn) * r * 0.75, s * 0.12, c(0.85, 0.85, 0.88))
        circle(px, py, s * 0.12, dark)
    }
}
