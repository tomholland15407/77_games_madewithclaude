package com.gogs.bananagame.games.sketchhop

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
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
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
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
 * Reflex — Sketch Hop (iOS DoodleJumpGame.swift, id "doodle-jump"): the banana Doodler auto-bounces;
 * hold the left/right half to steer onto platforms (edges wrap). Reach the target height.
 */
object SketchHopGame {
    val definition = GameDefinition(
        id = "doodle-jump",
        title = "Sketch Hop",
        genre = Genre.REFLEX,
        locksFeed = true,
        manual = GameManual(
            bullets = listOf(
                "The critter auto-bounces upward.",
                "Hold the left or right half of the screen to steer onto platforms (edges wrap around).",
                "Climb to the level's target height to win.",
                "Miss the platforms and fall off the bottom and you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Con vật tự bật lên liên tục.",
                "Giữ nửa trái hoặc phải màn hình để lái lên các bệ (mép màn hình nối vòng).",
                "Leo tới độ cao mục tiêu của cấp để thắng.",
                "Hụt bệ và rơi khỏi đáy sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> SketchHopView(level, onWin, onFail) }
    )
}

private enum class Kind { NORMAL, MOVING, CRUMBLE, SPRING }
private class Platform(var x: Double, val baseX: Double, val y: Double, val kind: Kind, val amp: Double, val spd: Double, val phase: Double) {
    var alive = true
    var brokeAt = -1.0
}

private const val G = 1.5
private const val JUMP_V = 1.1
private const val SPRING_V = 1.95
private const val MOVE_SPEED = 0.95
private const val CHAR_HALF = 0.05

private val demoPads = listOf(Triple(0.5, 0.0, false), Triple(0.62, 0.30, true), Triple(0.3, 0.75, false), Triple(0.78, 1.05, false),
    Triple(0.38, 1.40, true), Triple(0.72, 2.0, false), Triple(0.2, 2.35, false), Triple(0.58, 2.55, true), Triple(0.86, 3.1, false),
    Triple(0.3, 3.45, false), Triple(0.42, 3.85, true), Triple(0.75, 4.4, false), Triple(0.2, 4.75, false), Triple(0.6, 5.1, false))
private val demoRoute = listOf(1, 4, 7, 10)

private class HopWorld(level: Int, val isDemo: Boolean) {
    private val li = min(level, 7) - 1
    val targetHeight = listOf(5.0, 7.0, 9.0, 12.0, 15.0, 19.0, 24.0)[li]
    val gapLo = listOf(0.18, 0.20, 0.22, 0.24, 0.26, 0.28, 0.30)[li]
    val platHalf = listOf(0.14, 0.13, 0.12, 0.11, 0.10, 0.09, 0.08)[li]
    val movingChance = listOf(0.0, 0.0, 0.15, 0.25, 0.35, 0.45, 0.55)[li]
    val crumbleChance = listOf(0.0, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35)[li]
    val springChance = listOf(0.12, 0.10, 0.10, 0.08, 0.08, 0.06, 0.05)[li]
    val timeLimit = max(60.0, targetHeight * 10)

    val platforms = mutableListOf<Platform>()
    var charX = 0.5; var charY = 0.2; var vy = 0.0
    var moveDir = 0.0
    var facingLeft = false
    var cameraY = -0.45; var charMaxY = 0.0; var highestY = 0.0
    var t = 0.0
    var timeLeft = timeLimit
    var done = false
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    fun steer(d: Double) { moveDir = d; if (d != 0.0) facingLeft = d < 0 }

    fun setup() {
        charX = 0.5; charY = 0.2; vy = 0.0; moveDir = 0.0
        cameraY = -0.45; charMaxY = 0.0; t = 0.0; done = false; timeLeft = timeLimit
        platforms.clear(); platforms.add(Platform(0.5, 0.5, 0.0, Kind.NORMAL, 0.0, 0.0, 0.0))
        highestY = 0.0
        fill()
    }

    private fun fill() {
        if (isDemo) return
        while (highestY < cameraY + 1.6) {
            val y = highestY + rnd(gapLo, gapLo + 0.06)
            val r = Math.random()
            val kind = when {
                r < springChance -> Kind.SPRING
                r < springChance + movingChance -> Kind.MOVING
                r < springChance + movingChance + crumbleChance -> Kind.CRUMBLE
                else -> Kind.NORMAL
            }
            val amp = if (kind == Kind.MOVING) rnd(0.12, 0.22) else 0.0
            val bx = rnd(platHalf + amp, 1 - platHalf - amp)
            platforms.add(Platform(bx, bx, y, kind, amp, rnd(1.0, 1.8), rnd(0.0, 2 * Math.PI)))
            highestY = y
        }
    }

    fun step(dt: Double) {
        if (done) return
        t += dt
        charX += moveDir * MOVE_SPEED * dt
        if (charX < 0) charX += 1.0
        if (charX > 1) charX -= 1.0
        vy -= G * dt; charY += vy * dt
        charMaxY = max(charMaxY, charY)
        for (p in platforms) if (p.kind == Kind.MOVING) p.x = clamp(p.baseX + p.amp * sin(t * p.spd + p.phase), platHalf, 1 - platHalf)
        if (vy < 0) for (p in platforms) {
            if (!p.alive) continue
            if (charY <= p.y + 0.012 && charY >= p.y - 0.05 && abs(charX - p.x) < platHalf + CHAR_HALF) {
                charY = p.y
                vy = if (p.kind == Kind.SPRING) SPRING_V else JUMP_V
                Haptics.tap(); SoundManager.tap()
                if (p.kind == Kind.CRUMBLE) { p.alive = false; p.brokeAt = t }
                break
            }
        }
        cameraY = max(cameraY, charY - 0.45)
        fill()
        platforms.removeAll { it.y < cameraY - 0.3 }
        if (charMaxY >= targetHeight) { win(); return }
        if (charY < cameraY - 0.06) fail()
    }

    fun win() { if (done) return; done = true; onWin() }
    fun fail() { if (done) return; done = true; SoundManager.error(); onFail() }
}

@Composable
private fun SketchHopView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { HopWorld(level, isDemo).also { it.setup() } }
    world.onWin = onWin; world.onFail = onFail
    var demoTick by remember { mutableIntStateOf(0) }
    val th = theme(level)
    val start = remember { nowSec() }
    val handP = rememberHand()
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
            world.platforms.clear()
            demoPads.forEach { (x, y, spring) -> world.platforms.add(Platform(x, x, y, if (spring) Kind.SPRING else Kind.NORMAL, 0.0, 0.0, 0.0)) }
            world.highestY = demoPads.last().second
            var leg = 0
            delay(500)
            while (isActive && !world.done) {
                if (leg < demoRoute.size && world.charY >= demoPads[demoRoute[leg]].second - 0.001 && world.vy > SPRING_V - 0.05) leg++
                if (leg < demoRoute.size && abs(demoPads[demoRoute[leg]].first - world.charX) > 0.03)
                    world.steer(if (demoPads[demoRoute[leg]].first > world.charX) 1.0 else -1.0)
                else world.steer(0.0)
                world.step(dt)
                demoTick++
                delay(16)
            }
            world.steer(0.0)
            delay(1300)
        }
    }

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp)).background(th.paper),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        tick; demoTick
        if (!isDemo) TopBar((min(world.charMaxY, world.targetHeight) / world.targetHeight * 100).toInt(), world.timeLeft / world.timeLimit, th)
        Box(Modifier.fillMaxWidth().weight(1f)) {
            Canvas(Modifier.fillMaxSize()) {
                tick; demoTick
                drawWorld(world, th)
                if (isDemo && world.moveDir != 0.0) {
                    val w = size.width.toDouble(); val h = size.height.toDouble()
                    val tint = if (th.space) Color.White.op(0.14) else rgb(0.2, 0.3, 0.55, 0.1)
                    rect(if (world.moveDir < 0) 0.0 else w / 2, 0.0, w / 2, h, tint)
                    val s = 30.0 * density
                    hand(handP, w * (if (world.moveDir < 0) 0.22 else 0.78) - s / 2, h * 0.84 - s / 2, s)
                }
            }
            if (!isDemo) Row(Modifier.fillMaxSize()) {
                for (d in listOf(-1.0, 1.0)) Box(Modifier.weight(1f).fillMaxHeight().pressDown(
                    onDown = { if (!world.done) world.steer(d) }, onUp = { if (world.moveDir == d) world.steer(0.0) }))
            }
        }
    }
}

/** Torn-paper strip: the height in handwriting and the clock as a pencil-hatched bar. */
@Composable
private fun TopBar(percent: Int, fraction: Double, th: Theme) {
    Box(Modifier.fillMaxWidth().height(41.dp)) {
        Canvas(Modifier.fillMaxSize()) {
            val w = size.width.toDouble(); val h = size.height.toDouble(); val u = density.toDouble()
            val strip = Path(); strip.m(0.0, 0.0); strip.l(w, 0.0)
            var x = w; var i = 0
            while (x > 0) { x -= 7 * u; i++; strip.l(max(0.0, x), h - (if (i % 2 == 0) 2 else 6) * u - hash(i.toDouble()) * 3 * u) }
            strip.close()
            fillPath(strip, th.strip)
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 3.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("$percent%", style = ts(25.0, FontWeight.Bold, th.stripInk, Hand).copy(fontFeatureSettings = "tnum"))
            Spacer(Modifier.weight(1f))
            Canvas(Modifier.size(104.dp, 14.dp)) {
                val u = density.toDouble()
                val bx = u; val by = u; val bw = size.width - 2 * u; val bh = size.height - 2 * u
                val fw = bw * clamp(fraction, 0.0, 1.0)
                clipRect(bx.f, by.f, (bx + fw).f, (by + bh).f) {
                    val hatch = Path(); var x = bx - bh
                    while (x < bx + fw) { hatch.m(x, by + bh); hatch.l(x + bh, by); x += 4 * u }
                    strokePath(hatch, if (fraction < 0.3) rgb(0.86, 0.12, 0.1) else th.stripInk, 1.6 * u, StrokeCap.Butt)
                }
                rrectStroke(bx, by, bw, bh, 3 * u, th.stripInk, 1.8 * u)
            }
        }
    }
}

// Doodle Jump art (iOS DJArt / DJTheme).

/** iOS Noteworthy-Bold → Android's casual hand-lettered face. */
private val Hand = FontFamily(android.graphics.Typeface.create("casual", android.graphics.Typeface.BOLD))

private class Theme(val paper: Color, val grid: Color, val platforms: List<Color>, val ink: Color, val space: Boolean, val strip: Color, val stripInk: Color)

private fun theme(level: Int): Theme = when (clampI(level, 1, 7)) {
    in 1..3 -> Theme(rgb(0.973, 0.941, 0.898), rgb(0.9, 0.66, 0.48, 0.38),
        listOf(rgb(0.46, 0.76, 0.2), rgb(0.44, 0.74, 0.96), rgb(0.62, 0.43, 0.23), rgb(0.46, 0.76, 0.2)),
        rgb(0.1, 0.08, 0.07), false, rgb(0.7, 0.79, 0.86, 0.92), rgb(0.1, 0.08, 0.07))
    4, 5 -> Theme(rgb(0.87, 0.9, 0.95), rgb(0.44, 0.56, 0.8, 0.3),
        listOf(rgb(0.4, 0.72, 0.3), rgb(0.4, 0.66, 0.98), rgb(0.58, 0.42, 0.26), rgb(0.4, 0.72, 0.3)),
        rgb(0.08, 0.09, 0.14), false, rgb(0.55, 0.64, 0.8, 0.92), rgb(0.08, 0.09, 0.14))
    else -> Theme(rgb(0.07, 0.09, 0.21), rgb(0.35, 0.48, 0.86, 0.22),
        listOf(rgb(0.3, 0.74, 0.62), rgb(0.46, 0.66, 1.0), rgb(0.6, 0.44, 0.3), rgb(0.3, 0.74, 0.62)),
        rgb(0.01, 0.02, 0.06), true, rgb(0.2, 0.25, 0.44, 0.95), Color.White)
}

private fun hash(n: Double): Double { val v = sin(n * 12.9898) * 43758.5453; return v - floor(v) }

private fun DrawScope.drawWorld(world: HopWorld, th: Theme) {
    val w = size.width.toDouble(); val h = size.height.toDouble(); val u = density.toDouble()
    fun sy(y: Double) = (1 - (y - world.cameraY)) * h
    paper(th, world.cameraY * h)
    val gy = sy(world.targetHeight)
    if (gy > -40 * u && gy < h + 40 * u) goal(gy)
    val tk = max(11 * u, w * 0.042)
    for (p in world.platforms) {
        val cx = p.x * w; val cy = sy(p.y)
        if (cy <= -40 * u || cy >= h + 80 * u) continue
        if (p.alive) {
            val sprung = p.kind == Kind.SPRING && world.vy > JUMP_V + 0.1 && world.charY > p.y && world.charY - p.y < 0.45 &&
                abs(world.charX - p.x) < world.platHalf + CHAR_HALF
            platform(cx, cy, world.platHalf * w, tk, p.kind.ordinal, th, sprung)
        } else if (p.brokeAt >= 0) broken(cx, cy, world.platHalf * w, tk, world.t - p.brokeAt, h, th)
    }
    val fx = world.charX * w; val fy = sy(world.charY) - tk / 2
    val body = w * 0.14
    val stretch = clamp(world.vy * 0.07, -0.08, 0.12)
    for (dx in listOf(-w, 0.0, w)) if (abs(fx + dx - w / 2) < w / 2 + body) doodler(fx + dx, fy, body, world.facingLeft, stretch)
}

/** Graph paper that moves with the world (stars too, in space, at half speed). */
private fun DrawScope.paper(th: Theme, scroll: Double) {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    drawRect(th.paper)
    if (th.space) {
        val stars = Path()
        for (i in 0 until 34) {
            val k = i.toDouble()
            var y = (hash(k + 1) * h + scroll * 0.5) % h; if (y < 0) y += h
            val r = (0.7 + hash(k + 2) * 1.4) * u
            stars.addOval(androidx.compose.ui.geometry.Rect((hash(k) * w - r).f, (y - r).f, (hash(k) * w + r).f, (y + r).f))
        }
        fillPath(stars, Color.White.op(0.75))
    }
    val cell = max(14 * u, w * 0.045)
    val grid = Path()
    var x = cell * 0.5
    while (x < w) { grid.m(x, 0.0); grid.l(x, h); x += cell }
    var y = scroll % cell
    while (y < h) { grid.m(0.0, y); grid.l(w, y); y += cell }
    strokePath(grid, th.grid, 0.8 * u, StrokeCap.Butt)
}

/** A red scribble along the right edge with a pennant, like the game's score lines. */
private fun DrawScope.goal(y: Double) {
    val u = density.toDouble()
    val w = size.width.toDouble()
    val red = rgb(0.86, 0.12, 0.1); val ink = rgb(0.1, 0.08, 0.07)
    val line = Path(); line.m(w * 0.6, y)
    var x = w * 0.6; var i = 0
    while (x < w) { x += 9 * u; i++; line.l(x, y + (if (i % 2 == 0) -1.2 else 1.2) * u) }
    strokePath(line, red, 3 * u)
    val px = w * 0.66
    line(px, y, px, y - 26 * u, ink, 2 * u)
    val flag = polyPath(px, y - 26 * u, px + 17 * u, y - 20 * u, px, y - 14 * u)
    fillPath(flag, red); strokePath(flag, ink, 1.4 * u)
}

/** A sketchy pill: kind 0 normal, 1 moving, 2 crumbling (cracked), 3 with a spring. */
private fun DrawScope.platform(cx: Double, cy: Double, hw: Double, t: Double, kind: Int, th: Theme, sprung: Boolean) {
    val u = density.toDouble()
    val x = cx - hw; val y = cy - t / 2
    val col = th.platforms[clampI(kind, 0, 3)]
    rrect(x, y, hw * 2, t, t / 2, vgrad(listOf(col.mix(Color.White, 0.22), col, col.mix(Color.Black, 0.22)), y, y + t))
    if (kind == 2) {
        line(x + t * 0.6, cy + u, x + hw * 2 - t * 0.6, cy + u, Color.Black.op(0.2), u, StrokeCap.Butt)
        val crack = Path(); crack.m(cx - u, y); crack.l(cx + 2.5 * u, cy - t * 0.1); crack.l(cx - 2 * u, cy + t * 0.2); crack.l(cx + u, y + t)
        strokePath(crack, th.ink, 1.5 * u, StrokeCap.Butt)
    } else {
        val sc = Path()
        for (i in 0 until 3) { val x0 = x + t * 0.55 + i * t * 0.5; sc.m(x0, y + t * 0.72); sc.l(x0 + t * 0.34, y + t * 0.26) }
        strokePath(sc, Color.White.op(0.75), 1.4 * u)
    }
    rrectStroke(x, y, hw * 2, t, t / 2, th.ink, 1.8 * u)
    if (kind == 3) {
        val sx = cx + hw * 0.35
        val height = if (sprung) t * 2.4 else t * 0.9
        val turns = if (sprung) 6 else 4
        val coil = Path(); coil.m(sx, y)
        for (i in 1..turns) coil.l(sx + (if (i % 2 == 0) -t * 0.42 else t * 0.42), y - height * i / turns)
        strokePath(coil, th.ink, 2.6 * u, StrokeCap.Butt)
        strokePath(coil, gray(0.78), 1.2 * u, StrokeCap.Butt)
        rrect(sx - t * 0.7, y - height - t * 0.32, t * 1.4, t * 0.32, 1.5 * u, gray(0.82))
        rrectStroke(sx - t * 0.7, y - height - t * 0.32, t * 1.4, t * 0.32, 1.5 * u, th.ink, 1.4 * u)
    }
}

/** A used crumbling platform: the two halves tip outward and drop. */
private fun DrawScope.broken(cx: Double, cy: Double, hw: Double, t: Double, age: Double, h: Double, th: Theme) {
    if (age < 0 || age >= 0.9) return
    val u = density.toDouble()
    val fall = 0.5 * 2.4 * h * age * age
    for (side in listOf(-1.0, 1.0)) withAlpha(max(0.0, 1 - age / 0.9)) {
        withTransform({ translate((cx + side * age * 22 * u).f, (cy + fall).f); rotate((side * age * 70).f, Offset.Zero) }) {
            val x = if (side < 0) -hw else 0.0
            rrect(x, -t / 2, hw, t, t / 2, th.platforms[2])
            rrectStroke(x, -t / 2, hw, t, t / 2, th.ink, 1.8 * u)
        }
    }
}

/** The banana Doodler with its feet at (fx, fy): striped shorts, four legs, a snout and a stem. */
private fun DrawScope.doodler(fx: Double, fy: Double, hh: Double, left: Boolean, stretch: Double) {
    withTransform({
        translate(fx.f, fy.f)
        scale(((if (left) -1 else 1) * (1 - stretch * 0.5) * hh).f, ((1 + stretch) * hh).f, Offset.Zero)
    }) {
        val ink = rgb(0.08, 0.07, 0.06); val lw = 0.04
        val legs = Path()
        for (x in listOf(-0.2, -0.07, 0.07, 0.2)) { legs.m(x, -0.2); legs.l(x, -0.015); legs.l(x + 0.07, -0.015) }
        strokePath(legs, ink, 0.045)
        val body = Path()
        body.m(-0.3, -0.2); body.l(-0.31, -0.74); body.c(-0.3, -1.08, 0.3, -1.08, 0.29, -0.76); body.l(0.3, -0.2); body.close()
        drawPath(body, lin(listOf(rgb(1.0, 0.92, 0.38), rgb(0.96, 0.78, 0.16)), -0.3, -0.9, 0.3, -0.3))
        val ridge = Path(); ridge.m(-0.2, -0.86); ridge.q(-0.25, -0.66, -0.2, -0.46)
        strokePath(ridge, Color.White.op(0.55), 0.04)
        val shorts = Path().apply { addRoundRect(androidx.compose.ui.geometry.RoundRect(-0.31f, -0.42f, 0.31f, -0.19f, 0.04f, 0.04f)) }
        fillPath(shorts, rgb(0.46, 0.66, 0.2))
        clipPath(shorts) { for (y in listOf(-0.39, -0.31, -0.23)) rect(-0.4, y, 0.8, 0.045, rgb(0.16, 0.36, 0.12)) }
        strokePath(shorts, ink, lw)
        strokePath(body, ink, lw)
        val snout = polyPath(0.24, -0.8, 0.5, -0.8, 0.58, -0.86, 0.58, -0.6, 0.5, -0.66, 0.24, -0.66)
        fillPath(snout, rgb(0.98, 0.86, 0.28)); strokePath(snout, ink, lw)
        oval(0.545, -0.84, 0.06, 0.22, ink.op(0.85))
        oval(0.08, -0.87, 0.085, 0.085, ink)
        oval(0.1, -0.86, 0.025, 0.025, Color.White)
        val stem = Path(); stem.m(-0.02, -0.98); stem.q(-0.02, -1.1, -0.12, -1.13)
        strokePath(stem, ink, 0.1); strokePath(stem, rgb(0.55, 0.42, 0.16), 0.055)
    }
}
