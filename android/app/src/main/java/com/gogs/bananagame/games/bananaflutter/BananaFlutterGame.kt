package com.gogs.bananagame.games.bananaflutter

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
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.withTransform
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
 * Reflex — Banana Flutter (iOS FlappyBananaGame.swift, id "flappy-banana"): tap anywhere to flap
 * through the scrolling pipes; clear the level's quota. Pipe, ceiling or ground → level 1.
 */
object BananaFlutterGame {
    val definition = GameDefinition(
        id = "flappy-banana",
        title = "Banana Flutter",
        genre = Genre.REFLEX,
        manual = GameManual(
            bullets = listOf(
                "A winged banana falls under gravity.",
                "Tap anywhere to flap upward and thread the gaps between the scrolling pipes.",
                "Clear the level's quota of pipes to win.",
                "Clip a pipe, the ceiling, or the ground and you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Quả chuối có cánh rơi theo trọng lực.",
                "Chạm bất kỳ đâu để vỗ cánh bay lên và luồn qua khe giữa các ống cuộn tới.",
                "Vượt đủ số ống của cấp để thắng.",
                "Chạm ống, trần, hoặc mặt đất sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> BananaFlutterView(level, onWin, onFail) }
    )
}

private const val BIRD_X = 0.28
private const val GROUND_Y = 0.88
private const val PIPE_W = 0.15
private const val BIRD_HALF_Y = 0.05
private const val GRAVITY = 2.8
private const val FLAP_V = -0.95
private val demoGaps = listOf(0.40, 0.58, 0.32, 0.55, 0.45)

private class Pipe(var x: Double, val gapCenter: Double) { var passed = false }

private class FlutterWorld(level: Int, val isDemo: Boolean) {
    private val li = min(level, 7) - 1
    val pipeSpeed = listOf(0.34, 0.40, 0.46, 0.52, 0.58, 0.65, 0.72)[li]
    val gapHalf = listOf(0.20, 0.175, 0.155, 0.14, 0.125, 0.11, 0.10)[li]
    val pipeSpacing = listOf(0.62, 0.58, 0.54, 0.50, 0.47, 0.44, 0.42)[li]
    val target = listOf(4, 5, 6, 7, 8, 9, 10)[li]
    var birdY = 0.42; var vy = 0.0
    val pipes = mutableListOf<Pipe>()
    var score = 0
    var done = false
    var demoGapIdx = 0
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    fun setup() { birdY = 0.42; vy = 0.0; score = 0; done = false; pipes.clear(); pipes.add(makePipe(1.15)) }

    private fun makePipe(x: Double): Pipe {
        if (isDemo) return Pipe(x, demoGaps[demoGapIdx++ % demoGaps.size])
        val lo = gapHalf + 0.08; val hi = GROUND_Y - gapHalf - 0.06
        return Pipe(x, rnd(lo, max(lo, hi)))
    }

    fun step(dt: Double) {
        if (done) return
        vy += GRAVITY * dt; birdY += vy * dt
        for (p in pipes) p.x -= pipeSpeed * dt
        val last = pipes.maxOfOrNull { it.x }
        if (last != null && last < 1.15 - pipeSpacing) pipes.add(makePipe(1.15))
        pipes.removeAll { it.x < -0.25 }
        if (birdY <= 0.02) { fail(); return }
        if (birdY >= GROUND_Y - BIRD_HALF_Y) { fail(); return }
        for (p in pipes) {
            if (!p.passed && p.x < BIRD_X) {
                p.passed = true; score++
                Haptics.tap(); SoundManager.tap()
                if (score >= target) { win(); return }
            }
            if (abs(p.x - BIRD_X) < PIPE_W / 2 + 0.03 &&
                (birdY - BIRD_HALF_Y < p.gapCenter - gapHalf || birdY + BIRD_HALF_Y > p.gapCenter + gapHalf)) { fail(); return }
        }
    }

    fun flap() { if (done) return; vy = FLAP_V; Haptics.tap(); SoundManager.tap() }
    fun win() { if (done) return; done = true; onWin() }
    fun fail() { if (done) return; done = true; SoundManager.error(); onFail() }
}

@Composable
private fun BananaFlutterView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { FlutterWorld(level, isDemo).also { it.setup() } }
    world.onWin = onWin; world.onFail = onFail
    var demoTapT by remember { mutableDoubleStateOf(-10.0) }
    var demoTick by remember { mutableIntStateOf(0) }
    // Once the run ends the scene freezes (the ground stops scrolling with everything else).
    var frozenAt by remember { mutableDoubleStateOf(-1.0) }
    val tick by rememberFrameLoop { dt -> if (!isDemo) world.step(dt) }

    LaunchedEffect(Unit) {
        if (!isDemo) return@LaunchedEffect
        val dt = 1.0 / 60.0
        while (isActive) {
            world.demoGapIdx = 0; world.setup(); frozenAt = -1.0
            delay(500)
            while (isActive && !world.done) {
                val next = world.pipes.filter { it.x + PIPE_W / 2 + 0.03 > BIRD_X }.minByOrNull { it.x }
                val aim = (next?.gapCenter ?: 0.45) + 0.07
                if (world.birdY > aim && world.vy > 0) { world.flap(); demoTapT = nowSec() }
                world.step(dt)
                demoTick++
                delay(16)
            }
            delay(1300)
        }
    }

    val pal = palette(level)
    Canvas(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .drawWithCache {
                val bg = androidx.compose.ui.graphics.ImageBitmap(size.width.toInt().coerceAtLeast(1), size.height.toInt().coerceAtLeast(1))
                val cv = androidx.compose.ui.graphics.Canvas(bg)
                androidx.compose.ui.graphics.drawscope.CanvasDrawScope().draw(this, layoutDirection, cv, size) { backdrop(pal) }
                onDrawBehind { drawImage(bg) }
            }
            .then(if (isDemo) Modifier else Modifier.tapAt { world.flap() })
    ) {
        tick; demoTick
        val w = size.width.toDouble(); val h = size.height.toDouble()
        if (world.done && frozenAt < 0) frozenAt = nowSec()
        val now = if (frozenAt >= 0) frozenAt else nowSec()
        for (p in world.pipes) {
            val topH = max(0.0, p.gapCenter - world.gapHalf) * h
            val gapBot = (p.gapCenter + world.gapHalf) * h
            val botH = max(0.0, GROUND_Y * h - gapBot)
            pipe(p.x * w, 0.0, topH, PIPE_W * w, true, pal.redPipes)
            pipe(p.x * w, gapBot, gapBot + botH, PIPE_W * w, false, pal.redPipes)
        }
        ground(GROUND_Y * h, now * world.pipeSpeed * w, pal.groundDim)
        if (pal.rain) rain(now)
        val wing = if (world.done) 1 else listOf(0, 1, 2, 1)[(now * 11).toInt() % 4]
        bird(BIRD_X * w, world.birdY * h, h * 0.09, clamp(world.vy * 45, -25.0, 55.0), wing)
        score(world.score, world.target, w / 2, h * 0.06, max(3.0 * density, w * 0.0135))
        if (isDemo) tapRipple(w * 0.72, h * 0.62, nowSec() - demoTapT)
    }
}

// Flappy Bird art (iOS FBArt / FBBackdrop).

private fun fb(r: Int, g: Int, b: Int) = Color(r / 255f, g / 255f, b / 255f)

private class FBPalette(
    val skyTop: Color, val skyBottom: Color, val cloud: Color, val cloudEdge: Color,
    val city: Color, val cityShade: Color, val window: Color, val litWindows: Boolean,
    val bush: Color, val bushEdge: Color, val stars: Boolean, val rain: Boolean, val redPipes: Boolean, val groundDim: Double,
)

private val ink = fb(84, 56, 71)

private fun palette(level: Int): FBPalette = when (clampI(level, 1, 7)) {
    1 -> FBPalette(fb(113, 197, 207), fb(113, 197, 207), fb(234, 252, 219), fb(200, 235, 217), fb(219, 241, 201), fb(196, 230, 184), fb(170, 222, 196), false,
        fb(132, 227, 140), fb(104, 196, 124), false, false, false, 0.0)
    2 -> FBPalette(fb(98, 184, 206), fb(168, 214, 204), fb(250, 245, 216), fb(226, 224, 198), fb(232, 232, 196), fb(214, 214, 178), fb(196, 212, 176), false,
        fb(122, 214, 122), fb(96, 184, 104), false, false, false, 0.0)
    3 -> FBPalette(fb(236, 118, 98), fb(252, 196, 130), fb(255, 228, 198), fb(242, 192, 164), fb(218, 146, 134), fb(198, 124, 116), fb(252, 214, 150), true,
        fb(106, 178, 108), fb(80, 148, 90), false, false, false, 0.05)
    4 -> FBPalette(fb(64, 54, 118), fb(194, 118, 150), fb(214, 164, 188), fb(176, 128, 162), fb(96, 80, 140), fb(80, 66, 122), fb(250, 214, 122), true,
        fb(62, 132, 102), fb(44, 102, 82), true, false, false, 0.15)
    5 -> FBPalette(fb(8, 58, 82), fb(10, 122, 138), fb(24, 108, 124), fb(44, 132, 142), fb(12, 76, 92), fb(8, 62, 78), fb(248, 214, 110), true,
        fb(26, 118, 86), fb(16, 90, 68), true, false, false, 0.25)
    6 -> FBPalette(fb(24, 30, 42), fb(64, 76, 90), fb(72, 84, 98), fb(94, 104, 116), fb(34, 42, 54), fb(26, 32, 44), fb(232, 200, 122), true,
        fb(40, 74, 58), fb(30, 56, 46), false, true, true, 0.35)
    else -> FBPalette(fb(34, 6, 14), fb(112, 26, 34), fb(94, 34, 42), fb(122, 50, 58), fb(48, 14, 22), fb(36, 10, 16), fb(255, 124, 92), true,
        fb(60, 30, 28), fb(44, 20, 18), false, true, true, 0.42)
}

private fun hash(n: Double): Double { val v = sin(n * 12.9898) * 43758.5453; return v - floor(v) }

/** Flappy's banded pipe colours as hard gradient stops. */
private fun bands(red: Boolean, x0: Double, x1: Double): Brush {
    val c = if (red) listOf(fb(250, 168, 112), fb(255, 212, 166), fb(240, 132, 84), fb(206, 88, 48), fb(232, 116, 72), fb(214, 80, 40), fb(150, 50, 22), fb(154, 56, 26))
    else listOf(fb(177, 236, 103), fb(216, 250, 132), fb(157, 231, 90), fb(126, 201, 58), fb(148, 223, 81), fb(116, 192, 45), fb(81, 127, 34), fb(84, 120, 34))
    val edges = listOf(Triple(0.0, 0.06, 0), Triple(0.06, 0.12, 1), Triple(0.12, 0.26, 2), Triple(0.26, 0.30, 3), Triple(0.30, 0.36, 4),
        Triple(0.36, 0.76, 5), Triple(0.76, 0.80, 6), Triple(0.80, 0.85, 5), Triple(0.85, 1.0, 7))
    val stops = edges.flatMap { (a, b, i) -> listOf(a.toFloat() to c[i], b.toFloat() to c[i]) }.toTypedArray()
    return Brush.horizontalGradient(*stops, startX = x0.f, endX = x1.f)
}

private fun DrawScope.pipe(midX: Double, top: Double, bottom: Double, pw: Double, lipAtBottom: Boolean, red: Boolean) {
    if (bottom - top <= 1) return
    val u = density.toDouble()
    val outline = if (red) fb(92, 38, 40) else fb(94, 73, 73)
    val shine = if (red) fb(255, 222, 176) else fb(231, 255, 142)
    val lipW = pw * 1.1; val lipH = min(bottom - top, pw * 0.46)
    val bx = midX - pw / 2
    val lx = midX - lipW / 2; val ly = if (lipAtBottom) bottom - lipH else top
    rect(bx, top, pw, bottom - top, bands(red, bx, bx + pw))
    rectStroke(bx + u, top - 2 * u, pw - 2 * u, bottom - top + 4 * u, outline, 2 * u)
    rect(lx, ly, lipW, lipH, bands(red, lx, lx + lipW))
    val rimY = if (lipAtBottom) ly + lipH - 5 * u else ly + 2 * u
    rect(lx + 2 * u, rimY, lipW - 4 * u, 3 * u, shine.op(0.9))
    rectStroke(lx + u, ly + u, lipW - 2 * u, lipH - 2 * u, outline, 2 * u)
}

private fun DrawScope.ground(gy: Double, scroll: Double, dim: Double) {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    fun d(c: Color) = if (dim > 0) c.mix(Color.Black, dim) else c
    val band = max(8 * u, w * 0.028); val period = max(14 * u, w * 0.048)
    rect(0.0, gy, w, h - gy, d(fb(221, 216, 148)))
    rect(0.0, gy, w, 2 * u, fb(84, 64, 64))
    rect(0.0, gy + 2 * u, w, 2 * u, d(fb(217, 244, 132)))
    val by = gy + 4 * u
    rect(0.0, by, w, band, d(fb(112, 190, 44)))
    val stripes = Path()
    var x = -(scroll % period) - period
    while (x < w + period) {
        stripes.m(x + band * 0.7, by); stripes.l(x + band * 0.7 + period * 0.5, by)
        stripes.l(x + period * 0.5, by + band); stripes.l(x, by + band); stripes.close()
        x += period
    }
    fillPath(stripes, d(fb(155, 229, 87)))
    rect(0.0, by + band, w, 2 * u, d(fb(93, 151, 39)))
    rect(0.0, by + band + 2 * u, w, 2 * u, d(fb(206, 170, 86)))
    rect(0.0, h - 6 * u, w, 6 * u, d(fb(200, 194, 128)))
}

private fun DrawScope.rain(now: Double) {
    val u = density.toDouble()
    val h = size.height.toDouble(); val w = size.width.toDouble()
    val p = Path()
    for (i in 0 until 46) {
        val k = i.toDouble()
        val speed = h * (1.3 + hash(k + 7) * 0.5)
        val len = (10 + hash(k + 3) * 12) * u
        val y = (hash(k) * h * 1.2 + now * speed) % (h * 1.2) - h * 0.1
        val x = (hash(k + 11) * w * 1.2 - y * 0.22) % (w * 1.2)
        val xx = if (x < 0) x + w * 1.2 else x
        p.m(xx, y); p.l(xx - len * 0.22, y + len)
    }
    strokePath(p, Color.White.op(0.32), 1.3 * u)
}

/** A banana lying like a smile, with Flappy's big eye, orange lips and a flapping wing. */
private fun DrawScope.bird(cx: Double, cy: Double, s: Double, angleDeg: Double, wing: Int) {
    withTransform({
        translate(cx.f, cy.f)
        rotate(angleDeg.f, Offset.Zero)
        scale(s.f, s.f, Offset.Zero)
    }) {
        val lw = 0.055
        val stem = Path(); stem.m(-0.6, -0.3); stem.q(-0.74, -0.32, -0.8, -0.46)
        strokePath(stem, ink, 0.19); strokePath(stem, fb(150, 118, 52), 0.1)
        oval(-0.87, -0.53, 0.12, 0.12, fb(74, 52, 30))
        val body = Path()
        body.m(-0.62, -0.26); body.c(-0.56, 0.64, 0.52, 0.6, 0.6, -0.3); body.c(0.36, -0.05, -0.36, -0.03, -0.62, -0.26); body.close()
        drawPath(body, vgrad(listOf(fb(255, 240, 128), fb(255, 214, 58), fb(236, 162, 22)), -0.2, 0.4))
        val ridge = Path(); ridge.m(-0.52, -0.12); ridge.c(-0.44, 0.4, 0.42, 0.38, 0.5, -0.16)
        strokePath(ridge, fb(214, 138, 20).op(0.75), 0.04)
        val shine = Path(); shine.m(-0.42, -0.13); shine.q(-0.24, 0.06, 0.04, 0.06)
        strokePath(shine, Color.White.op(0.6), 0.055)
        for ((x, y, r) in listOf(Triple(-0.34, 0.2, 0.03), Triple(-0.2, 0.3, 0.022), Triple(0.02, 0.33, 0.026))) circle(x, y, r, fb(170, 108, 28).op(0.7))
        strokePath(body, ink, lw)
        oval(0.55, -0.36, 0.11, 0.11, fb(74, 52, 30))
        rrect(0.33, 0.07, 0.31, 0.12, 0.06, fb(226, 76, 28)); rrectStroke(0.33, 0.07, 0.31, 0.12, 0.06, ink, lw * 0.8)
        rrect(0.36, -0.05, 0.36, 0.13, 0.06, fb(250, 128, 50)); rrectStroke(0.36, -0.05, 0.36, 0.13, 0.06, ink, lw * 0.8)
        circle(0.25, -0.15, 0.15, Color.White); circleStroke(0.25, -0.15, 0.15, ink, lw * 0.8)
        rrect(0.27, -0.23, 0.07, 0.15, 0.03, ink)
        val tilt = listOf(-30.0, 0.0, 26.0)[clampI(wing, 0, 2)]
        withTransform({ translate(-0.2f, 0.14f); rotate(tilt.f, Offset.Zero) }) {
            drawOval(vgrad(listOf(fb(255, 252, 238), fb(242, 226, 190)), -0.11, 0.1), off(-0.25, -0.11), sz(0.4, 0.21))
            ellipseStroke(-0.05, -0.005, 0.2, 0.105, ink, lw * 0.8)
        }
    }
}

private val glyphs = mapOf(
    '0' to listOf(".####.", "##..##", "##..##", "##..##", "##..##", "##..##", "##..##", ".####."),
    '1' to listOf(".##", "###", ".##", ".##", ".##", ".##", ".##", ".##"),
    '2' to listOf(".####.", "##..##", "....##", "...##.", "..##..", ".##...", "##....", "######"),
    '3' to listOf("#####.", "....##", "....##", ".####.", "....##", "....##", "....##", "#####."),
    '4' to listOf("...##.", "..###.", ".####.", "##.##.", "######", "...##.", "...##.", "...##."),
    '5' to listOf("######", "##....", "##....", "#####.", "....##", "....##", "##..##", ".####."),
    '6' to listOf(".####.", "##....", "##....", "#####.", "##..##", "##..##", "##..##", ".####."),
    '7' to listOf("######", "....##", "...##.", "...##.", "..##..", "..##..", ".##...", ".##..."),
    '8' to listOf(".####.", "##..##", "##..##", ".####.", "##..##", "##..##", "##..##", ".####."),
    '9' to listOf(".####.", "##..##", "##..##", "##..##", ".#####", "....##", "....##", ".####."),
    '/' to listOf("....##", "...##.", "...##.", "..##..", "..##..", ".##...", ".##...", "##...."),
)

private fun advance(text: String) = (text.sumOf { (glyphs[it]?.first()?.length ?: 6) + 1 } - 1).toDouble()

private fun pixels(text: String, ox: Double, oy: Double, px: Double): List<DoubleArray> {
    val out = mutableListOf<DoubleArray>()
    var x = ox
    for (ch in text) {
        val rows = glyphs[ch] ?: continue
        rows.forEachIndexed { r, row -> row.forEachIndexed { k, bit -> if (bit == '#') out.add(doubleArrayOf(x + k * px, oy + r * px, px)) } }
        x += px * (rows.first().length + 1)
    }
    return out
}

/** White pixel digits with a thick dark outline: big score + small "/target". */
private fun DrawScope.score(n: Int, target: Int, midX: Double, top: Double, px: Double) {
    val big = "$n"; val small = "/$target"
    val sp = px * 0.55
    val bigW = advance(big) * px; val smallW = advance(small) * sp
    val x0 = midX - (bigW + sp * 2 + smallW) / 2
    val lit = pixels(big, x0, top, px) + pixels(small, x0 + bigW + sp * 2, top + px * 8 - sp * 8, sp)
    val outline = Path(); val fill = Path()
    for (r in lit) {
        val o = px * 0.42
        outline.addRect(androidx.compose.ui.geometry.Rect((r[0] - o).f, (r[1] - o).f, (r[0] + r[2] + o).f, (r[1] + r[2] + o).f))
        fill.addRect(androidx.compose.ui.geometry.Rect((r[0] - 0.15).f, (r[1] - 0.15).f, (r[0] + r[2] + 0.15).f, (r[1] + r[2] + 0.15).f))
    }
    fillPath(outline, fb(40, 28, 34))
    fillPath(fill, Color.White)
}

/** The world that never moves: sky, stars, the cloud band, the city and bushes. */
private fun DrawScope.backdrop(pal: FBPalette) {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    val groundY = 0.88 * h
    val cloudTop = groundY - h * 0.2; val cityTop = groundY - h * 0.15; val bushTop = groundY - h * 0.065
    rect(0.0, 0.0, w, h, vgrad(listOf(pal.skyTop, pal.skyBottom), 0.0, cloudTop + h * 0.05))
    if (pal.stars) for (i in 0 until 42) {
        val k = i.toDouble(); val r = (0.6 + hash(k + 5) * 1.3) * u
        circle(hash(k) * w, hash(k + 2) * cloudTop * 0.95, r, Color.White.op(0.35 + hash(k + 9) * 0.5))
    }
    fun scallops(baseY: Double, rMin: Double, rVar: Double, step: Double, seed: Double, x0: Double): Path {
        val p = Path(); var x = x0; var i = 0.0
        while (x < w + 20 * u) {
            val r = h * (rMin + hash(i + seed) * rVar)
            p.addOval(androidx.compose.ui.geometry.Rect((x - r).f, (baseY - r).f, (x + r).f, (baseY + r).f))
            x += r * step; i++
        }
        p.addRect(androidx.compose.ui.geometry.Rect(0f, baseY.f, w.f, groundY.f))
        return p
    }
    val clouds = scallops(cloudTop + h * 0.03, 0.028, 0.022, 1.3, 31.0, -10 * u)
    fillPath(clouds, pal.cloudEdge)
    translate(0f, (2 * u).f) { fillPath(clouds, pal.cloud) }
    var x = 0.0; var i = 0.0
    while (x < w) {
        val bw = w * (0.06 + hash(i + 51) * 0.06)
        val bh = (bushTop - cityTop) * (0.45 + hash(i + 71) * 0.55) + h * 0.02
        val ry = bushTop + h * 0.02 - bh
        rect(x, ry, bw - u, bh, if (i.toInt() % 3 == 1) pal.cityShade else pal.city)
        val win = max(2.5 * u, w * 0.009)
        var wy = ry + win * 1.5; var row = 0.0
        while (wy < bushTop - win) {
            var wx = x + win; var col = 0.0
            while (wx < x + bw - u - win * 1.5) {
                val lit = pal.litWindows && hash(i * 17 + row * 5 + col) > 0.45
                rect(wx, wy, win, win, if (pal.litWindows) (if (lit) pal.window else pal.cityShade.op(0.9)) else pal.window)
                wx += win * 2; col++
            }
            wy += win * 2.2; row++
        }
        x += bw; i++
    }
    val bushes = scallops(bushTop + h * 0.02, 0.022, 0.016, 1.25, 91.0, -6 * u)
    fillPath(bushes, pal.bushEdge)
    translate(0f, (2 * u).f) { fillPath(bushes, pal.bush) }
}
