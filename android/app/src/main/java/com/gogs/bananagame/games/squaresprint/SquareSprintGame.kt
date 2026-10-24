package com.gogs.bananagame.games.squaresprint

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
import androidx.compose.ui.geometry.Offset
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
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Reflex — Square Sprint (iOS GeometryDashGame.swift, id "geometry-dash"): the cube auto-runs; tap
 * to jump spikes, hold to fly through portal sections. Reach the end of the track.
 */
object SquareSprintGame {
    val definition = GameDefinition(
        id = "geometry-dash",
        title = "Square Sprint",
        genre = Genre.REFLEX,
        locksFeed = true,
        manual = GameManual(
            bullets = listOf(
                "The cube auto-runs to the right. Tap to jump the spikes on the beat.",
                "Coloured portals flip you into flight sections — hold to thrust up and thread the gaps.",
                "A portal flips you back to the cube; reach the end of the track to win.",
                "One touch on a spike, a gap wall, or a ceiling/floor in flight sends you to level 1.",
            ),
            bulletsVI = listOf(
                "Khối lập phương tự chạy sang phải. Chạm để nhảy qua gai theo nhịp.",
                "Cổng màu chuyển bạn sang đoạn bay — giữ để đẩy lên và luồn qua các khe di động.",
                "Một cổng đưa bạn về lại khối lập phương; đến cuối đường đua để thắng.",
                "Chạm gai, tường khe, hay trần/sàn khi bay sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> SquareSprintView(level, onWin, onFail) }
    )
}

private const val CAM_X = 0.26
private const val VIEW_SPAN = 1.5
private const val FLOOR_Y = 0.80
private const val CEIL_Y = 0.12
private const val HS = 0.042
private const val HS_WORLD = 0.028
private const val GRAVITY = 7.0
private const val JUMP_V = 1.85
private const val SHIP_THRUST = 4.6
private const val SHIP_GRAV = 3.4
private const val SHIP_MAX_V = 1.0

private enum class ObKind { SPIKE, BAR, TO_SHIP, TO_CUBE }
private class Ob(val kind: ObKind, val x: Double, val w: Double = 0.0, val gapCenter: Double = 0.0)

private class SprintWorld(val level: Int) {
    private val li = min(level, 7) - 1
    val scrollSpeed = listOf(0.55, 0.62, 0.70, 0.78, 0.87, 0.97, 1.08)[li]
    val beatGap = listOf(0.62, 0.56, 0.50, 0.45, 0.41, 0.37, 0.34)[li]
    val shipSegments = listOf(0, 1, 1, 2, 2, 3, 3)[li]
    val shipGapHalf = listOf(0.26, 0.24, 0.22, 0.20, 0.18, 0.16, 0.14)[li]
    val shipBarGap = listOf(0.75, 0.70, 0.64, 0.58, 0.52, 0.47, 0.42)[li]

    var obstacles = listOf<Ob>()
    var shipZones = listOf<Pair<Double, Double>>()
    var trackEnd = 6.0
    var distance = 0.0
    var y = FLOOR_Y; var vy = 0.0
    var grounded = true
    var holding = false
    var done = false
    var spin = 0.0
    var takeoff = 0.0
    var deathAt: P? = null
    var deathT0 = 0.0
    var shakeT0 = -10.0
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    val inShip get() = shipZones.any { distance >= it.first && distance < it.second }

    /** Degrees turned since takeoff: 180° over one full jump at this level's speed. */
    val airSpin get() = (distance - takeoff) * 180 / max(0.01, scrollSpeed * 2 * JUMP_V / GRAVITY)

    private fun landed(g: Boolean) {
        if (g == grounded) return
        if (g) spin = Math.round((spin + airSpin) / 90.0) * 90.0 else takeoff = distance
        grounded = g
    }

    fun setup() {
        distance = 0.0; y = FLOOR_Y; vy = 0.0; grounded = true; holding = false; done = false; deathAt = null
        val obs = mutableListOf<Ob>(); val zones = mutableListOf<Pair<Double, Double>>()
        var x = 1.4
        var shipLeft = shipSegments
        for (seg in 0 until 3 + level) {
            if (shipLeft > 0 && seg % 2 == 1) {
                shipLeft--
                val portalX = x
                obs.add(Ob(ObKind.TO_SHIP, portalX))
                x += 0.75
                var gc = (CEIL_Y + FLOOR_Y) / 2
                repeat(2 + level / 3) {
                    obs.add(Ob(ObKind.BAR, x, gapCenter = gc))
                    gc = clamp(gc + rnd(-0.10, 0.10), CEIL_Y + shipGapHalf + 0.03, FLOOR_Y - shipGapHalf - 0.03)
                    x += shipBarGap
                }
                zones.add(portalX to x)
                obs.add(Ob(ObKind.TO_CUBE, x))
                x += 0.6
            } else repeat(3 + level) { obs.add(Ob(ObKind.SPIKE, x, w = 0.05)); x += beatGap }
        }
        trackEnd = x + 1.0
        obstacles = obs; shipZones = zones
    }

    fun press() {
        if (done) return
        if (inShip) holding = true
        else if (grounded) { vy = -JUMP_V; landed(false); SoundManager.tap(); Haptics.tap() }
    }

    fun step(dt: Double) {
        if (done) return
        distance += scrollSpeed * dt
        if (inShip) {
            vy = clamp(vy + (if (holding) -SHIP_THRUST else SHIP_GRAV) * dt, -SHIP_MAX_V, SHIP_MAX_V)
            y += vy * dt
            landed(false)
            if (y <= CEIL_Y + HS || y >= FLOOR_Y - HS) { fail(); return }
        } else {
            vy += GRAVITY * dt; y += vy * dt
            if (y >= FLOOR_Y) { y = FLOOR_Y; vy = 0.0; landed(true) } else landed(false)
        }
        for (ob in obstacles) {
            if (abs(ob.x - distance) >= 0.5) continue
            when (ob.kind) {
                ObKind.SPIKE -> if (distance > ob.x - HS_WORLD && distance < ob.x + ob.w + HS_WORLD && y + HS > FLOOR_Y - 0.10 + 0.01) { fail(); return }
                ObKind.BAR -> if (abs(ob.x - distance) < 0.02 + HS_WORLD && (y - HS < ob.gapCenter - shipGapHalf || y + HS > ob.gapCenter + shipGapHalf)) { fail(); return }
                else -> {}
            }
        }
        if (distance >= trackEnd) win()
    }

    fun win() { if (done) return; done = true; onWin() }
    fun fail() {
        if (done) return
        done = true
        deathAt = P(CAM_X, y); deathT0 = nowSec(); shakeT0 = nowSec()
        SoundManager.error(); onFail()
    }
}

@Composable
private fun SquareSprintView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { SprintWorld(level).also { it.setup() } }
    world.onWin = onWin; world.onFail = onFail
    var demoTapT by remember { mutableDoubleStateOf(-10.0) }
    var demoTick by remember { mutableIntStateOf(0) }
    val tm = rememberTextMeasurer()
    val tick by rememberFrameLoop { dt -> if (!isDemo) world.step(dt) }

    LaunchedEffect(Unit) {
        if (!isDemo) return@LaunchedEffect
        val dt = 1.0 / 60.0
        while (isActive) {
            world.setup(); world.distance = world.trackEnd - 4.4
            delay(400)
            while (isActive && !world.done) {
                if (world.grounded) {
                    val next = world.obstacles.filter { it.kind == ObKind.SPIKE && it.x - world.distance > -0.2 }.minOfOrNull { it.x }
                    if (next != null && next - world.distance in 0.0..0.12) { world.press(); demoTapT = nowSec() }
                }
                world.step(dt)
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
                if (t in 0.0..0.35) translationX = (7 * density * sin(t / 0.35 * PI * 3) * (1 - t / 0.35)).toFloat()
            }
            .then(if (isDemo) Modifier else Modifier.pressDown(onDown = { world.press() }, onUp = { world.holding = false }))
    ) {
        tick; demoTick
        drawTrack(world, level)
        progress(tm, min(world.distance, world.trackEnd) / world.trackEnd, if (isDemo) 0.72 else 1.0, size.width / 2.0, CEIL_Y * size.height * 0.5)
        world.deathAt?.let { death(it.x * size.width, it.y * size.height, HS * 2 * size.height, nowSec() - world.deathT0) }
        if (isDemo) tapRipple(size.width * 0.7, size.height * 0.5, nowSec() - demoTapT)
    }
}

// Geometry Dash art (iOS GDArt and friends).

private val primary = rgb(1.0, 0.86, 0.16)
private val secondary = rgb(0.25, 0.95, 1.0)
private val ink = rgb(0.02, 0.02, 0.04)

private class Pal(val top: Color, val bottom: Color, val ground: Color)

private fun palette(level: Int) = when (clampI(level, 1, 7)) {
    1 -> Pal(rgb(0.16, 0.42, 1.0), rgb(0.05, 0.22, 0.78), rgb(0.03, 0.15, 0.6))
    2 -> Pal(rgb(0.86, 0.24, 0.82), rgb(0.52, 0.08, 0.56), rgb(0.38, 0.04, 0.44))
    3 -> Pal(rgb(0.16, 0.72, 0.38), rgb(0.05, 0.42, 0.2), rgb(0.03, 0.3, 0.14))
    4 -> Pal(rgb(0.52, 0.28, 0.96), rgb(0.27, 0.1, 0.62), rgb(0.19, 0.06, 0.48))
    5 -> Pal(rgb(1.0, 0.46, 0.14), rgb(0.72, 0.2, 0.05), rgb(0.5, 0.11, 0.03))
    6 -> Pal(rgb(0.86, 0.12, 0.28), rgb(0.46, 0.03, 0.13), rgb(0.32, 0.02, 0.08))
    else -> Pal(rgb(0.18, 0.15, 0.36), rgb(0.07, 0.05, 0.16), rgb(0.04, 0.03, 0.1))
}

private fun hash(n: Double): Double { val v = sin(n * 12.9898) * 43758.5453; return v - floor(v) }

private fun DrawScope.drawTrack(world: SprintWorld, level: Int) {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    val pal = palette(level)
    fun sx(wx: Double) = (CAM_X + (wx - world.distance) / VIEW_SPAN) * w
    val cube = HS * 2 * h
    val groundTop = (FLOOR_Y + HS) * h
    val scroll = world.distance / VIEW_SPAN * w
    backdrop(pal, scroll)
    ground(groundTop, pal, scroll)
    for ((a, b) in world.shipZones) thorns(sx(a), sx(b), FLOOR_Y * h, groundTop)
    rect(0.0, 0.0, w, CEIL_Y * h, vgrad(listOf(pal.ground.mix(Color.Black, 0.45), pal.ground), 0.0, CEIL_Y * h))
    glowLine(CEIL_Y * h)
    for (ob in world.obstacles) {
        val x = sx(ob.x)
        if (x <= -90 * u || x >= w + 90 * u) continue
        when (ob.kind) {
            ObKind.SPIKE -> spike(sx(ob.x + ob.w / 2), groundTop, (FLOOR_Y - 0.10) * h, cube * 0.48)
            ObKind.BAR -> {
                val half = 0.03 / VIEW_SPAN * w
                pillar(x, half, CEIL_Y * h, (ob.gapCenter - world.shipGapHalf) * h)
                pillar(x, half, (ob.gapCenter + world.shipGapHalf) * h, groundTop)
            }
            else -> portal(x, CEIL_Y * h, FLOOR_Y * h, ob.kind == ObKind.TO_SHIP)
        }
    }
    val fx = sx(world.trackEnd)
    if (fx > -40 * u && fx < w + 40 * u) finish(fx, CEIL_Y * h, groundTop)
    if (world.deathAt != null) return
    val px = CAM_X * w; val py = world.y * h
    if (world.inShip) ship(px, py, cube, clamp(world.vy * 40, -40.0, 40.0))
    else {
        if (world.grounded) dust(px, cube, groundTop, world.distance)
        translate(px.f, py.f) { rotate((if (world.grounded) world.spin else world.spin + world.airSpin).f, Offset.Zero) { icon(cube) } }
    }
}

/** Sky gradient with big faint squares drifting at a fifth of the track speed. */
private fun DrawScope.backdrop(p: Pal, scroll: Double) {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    rect(0.0, 0.0, w, h, vgrad(listOf(p.top, p.bottom), 0.0, h))
    val tile = h * 0.22
    val off = (scroll * 0.2) % (tile * 4)
    val light = Path(); val dark = Path()
    var col = 0.0; var x = -off - tile
    while (x < w + tile) {
        for (row in 0 until 5) {
            val k = col * 7 + row + floor(scroll * 0.2 / (tile * 4)) * 29
            val r = hash(k)
            val rect = androidx.compose.ui.geometry.Rect(x.f, (row * tile - tile * 0.3).f, (x + tile * (if (r > 0.5) 2 else 1) - 3 * u).f, (row * tile - tile * 0.3 + tile - 3 * u).f)
            if (r < 0.3) light.addRect(rect) else if (r > 0.75) dark.addRect(rect)
        }
        x += tile; col++
    }
    fillPath(light, Color.White.op(0.06)); fillPath(dark, Color.Black.op(0.08))
}

private fun DrawScope.ground(top: Double, p: Pal, scroll: Double) {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    rect(0.0, top, w, h - top, vgrad(listOf(p.ground, p.ground.mix(Color.Black, 0.45)), top, h))
    val tile = max(24 * u, h * 0.1)
    val grid = Path()
    var x = -(scroll % tile)
    while (x < w) { grid.m(x, top); grid.l(x, h); x += tile }
    var y = top + tile
    while (y < h) { grid.m(0.0, y); grid.l(w, y); y += tile }
    strokePath(grid, Color.White.op(0.1), 1.5 * u, StrokeCap.Butt)
    glowLine(top)
}

/** GD's floor line: brightest in the middle, fading toward both edges. */
private fun DrawScope.glowLine(y: Double) {
    val u = density.toDouble(); val w = size.width.toDouble()
    rect(0.0, y - 3 * u, w, 6 * u, Brush.horizontalGradient(0f to Color.White.op(0.0), 0.5f to Color.White.op(0.22), 1f to Color.White.op(0.0), startX = 0f, endX = w.f))
    rect(0.0, y - u, w, 2 * u, Brush.horizontalGradient(0f to Color.White.op(0.0), 0.5f to Color.White, 1f to Color.White.op(0.0), startX = 0f, endX = w.f))
}

private fun DrawScope.spike(x: Double, base: Double, apex: Double, hw: Double) {
    val u = density.toDouble()
    val tri = polyPath(x, apex, x + hw, base, x - hw, base)
    strokePath(tri, Color.White.op(0.25), 6 * u)
    drawPath(tri, vgrad(listOf(ink, ink, gray(0.16)), apex, base))
    strokePath(tri, Color.White, 2 * u)
}

private fun DrawScope.thorns(x0: Double, x1: Double, tips: Double, base: Double) {
    val u = density.toDouble(); val w = size.width.toDouble()
    val a = max(-20 * u, x0); val b = min(w + 20 * u, x1)
    if (b <= a) return
    val step = max(10 * u, (base - tips) * 0.7)
    val path = Path()
    var x = x0 + step / 2
    while (x < b) {
        if (x > a - step) { path.m(x - step / 2, base); path.l(x, tips); path.l(x + step / 2, base); path.close() }
        x += step
    }
    fillPath(path, ink)
    strokePath(path, Color.White.op(0.9), 1.4 * u)
}

private fun DrawScope.pillar(x: Double, hw: Double, top: Double, bottom: Double) {
    if (bottom - top <= 1) return
    val u = density.toDouble()
    rect(x - hw, top, hw * 2, bottom - top, hgrad(listOf(gray(0.02), gray(0.12)), x - hw, x + hw))
    val seams = Path()
    var y = top + hw * 2
    while (y < bottom - 2 * u) { seams.m(x - hw, y); seams.l(x + hw, y); y += hw * 2 }
    strokePath(seams, Color.White.op(0.28), u, StrokeCap.Butt)
    rectStroke(x - hw, top, hw * 2, bottom - top, Color.White.op(0.25), 5 * u)
    rectStroke(x - hw, top, hw * 2, bottom - top, Color.White, 1.8 * u)
}

private fun DrawScope.portal(x: Double, top: Double, bottom: Double, ship: Boolean) {
    val u = density.toDouble()
    val c1 = if (ship) rgb(1.0, 0.45, 0.85) else rgb(0.5, 1.0, 0.45)
    val c2 = if (ship) rgb(0.72, 0.1, 0.82) else rgb(0.1, 0.66, 0.2)
    val h = bottom - top
    val cy = top + h * 0.5; val rx = h * 0.09; val ry = h * 0.46
    ellipseStroke(x, cy, rx, ry, c1.op(0.3), 14 * u)
    ellipse(x, cy, rx - 4 * u, ry - 8 * u, c2.op(0.25))
    drawOval(vgrad(listOf(c1, c2, c1), cy - ry, cy + ry), off(x - rx, cy - ry), sz(rx * 2, ry * 2), style = androidx.compose.ui.graphics.drawscope.Stroke((6 * u).f))
    ellipseStroke(x, cy, rx - 5 * u, ry - 10 * u, Color.White.op(0.7), 1.5 * u)
    for (i in 0 until 6) { val a = i / 6.0 * 2 * PI; circle(x + cos(a) * rx * 2 * 0.72, cy + sin(a) * ry * 2 * 0.52, 2.5 * u, c1) }
}

private fun DrawScope.finish(x: Double, top: Double, bottom: Double) {
    val u = density.toDouble()
    val sq = 8 * u
    rect(x - sq - 4 * u, top, sq * 2 + 8 * u, bottom - top, Color.White.op(0.25))
    var y = top; var row = 0
    while (y < bottom) {
        for (col in 0 until 2) rect(x - sq + col * sq, y, sq, min(sq, bottom - y), if ((row + col) % 2 == 0) Color.White else ink)
        y += sq; row++
    }
}

/** GD's default icon in banana yellow with a cyan face, centred at the origin. */
private fun DrawScope.icon(s: Double) {
    rrect(-s / 2, -s / 2, s, s, s * 0.06, vgrad(listOf(primary.mix(Color.White, 0.25), primary), -s / 2, s / 2))
    rrectStroke(-s / 2, -s / 2, s, s, s * 0.06, ink, s * 0.08)
    rect(-s * 0.27, -s * 0.27, s * 0.54, s * 0.54, secondary)
    rectStroke(-s * 0.27, -s * 0.27, s * 0.54, s * 0.54, ink, s * 0.06)
    rect(-s * 0.19, -s * 0.18, s * 0.12, s * 0.12, ink)
    rect(s * 0.07, -s * 0.18, s * 0.12, s * 0.12, ink)
    rect(-s * 0.19, s * 0.07, s * 0.38, s * 0.09, ink)
}

/** The GD ship: a hull with a tail fin, the mini icon riding on top, and a fading streak. */
private fun DrawScope.ship(cx: Double, cy: Double, s: Double, tiltDeg: Double) {
    translate(cx.f, cy.f) {
        rotate(tiltDeg.f, Offset.Zero) {
            drawLine(lin(listOf(secondary.op(0.8), secondary.op(0.0)), -s * 0.85, 0.0, -s * 2.6, 0.0), off(-s * 0.85, s * 0.18), off(-s * 2.6, s * 0.18), (s * 0.22).f, StrokeCap.Round)
            translate((-s * 0.08).f, (-s * 0.2).f) { icon(s * 0.52) }
            val hull = Path()
            hull.m(-s * 0.86, -s * 0.02); hull.l(s * 0.38, -s * 0.02)
            hull.q(s * 0.82, -s * 0.02, s * 0.92, s * 0.2); hull.q(s * 0.8, s * 0.44, s * 0.3, s * 0.44)
            hull.l(-s * 0.8, s * 0.44); hull.close()
            fillPath(hull, primary); strokePath(hull, ink, s * 0.07)
            rect(-s * 0.66, s * 0.14, s * 1.18, s * 0.11, secondary)
            val fin = polyPath(-s * 0.86, -s * 0.02, -s * 0.96, -s * 0.36, -s * 0.6, -s * 0.02)
            fillPath(fin, secondary); strokePath(fin, ink, s * 0.06)
        }
    }
}

/** Square dust kicked up behind the running cube. */
private fun DrawScope.dust(cx: Double, s: Double, ground: Double, scroll: Double) {
    val u = density.toDouble()
    val p = Path()
    for (i in 0 until 5) {
        val f = (scroll * 6 + i * 0.2) % 1.0
        val x = cx - s * 0.5 - f * s * 1.1
        val y = ground - 2 * u - f * s * 0.35 - hash(i + 3.0) * 3 * u
        val q = s * 0.1 * (1 - f * 0.6)
        p.addRect(androidx.compose.ui.geometry.Rect(x.f, (y - q).f, (x + q).f, y.f))
    }
    fillPath(p, primary.op(0.75))
}

/** GD's progress bar and percentage, in the ceiling. */
private fun DrawScope.progress(tm: TextMeasurer, fraction: Double, scale: Double, cx: Double, cy: Double) {
    val u = density.toDouble()
    val f = clamp(fraction, 0.0, 1.0)
    val barW = 170 * scale * u; val barH = 11 * scale * u; val gap = 8 * scale * u; val labelW = 52 * scale * u
    val x0 = cx - (barW + gap + labelW) / 2
    rrect(x0, cy - barH / 2, barW, barH, barH / 2, Color.Black.op(0.35))
    if (f > 0) rrect(x0, cy - barH / 2, max(0.0, barW * f), barH, barH / 2, vgrad(listOf(rgb(0.6, 1.0, 0.45), rgb(0.3, 0.9, 0.3)), cy - barH / 2, cy + barH / 2))
    rrectStroke(x0, cy - barH / 2, barW, barH, barH / 2, Color.White, 2 * u)
    val s = "${(f * 100).toInt()}%"; val fs = 18 * scale * u; val tx = x0 + barW + gap
    for (i in 0 until 8) { val a = i * PI / 4; text(tm, s, tx + cos(a) * 1.6 * u, cy + sin(a) * 1.6 * u, fs, Color.Black, FontWeight.Black, anchorX = 0.0) }
    text(tm, s, tx, cy, fs, Color.White, FontWeight.Black, anchorX = 0.0)
}

/** The crash: the icon bursts into squares inside an expanding white ring (0.65 s ease-out). */
private fun DrawScope.death(x: Double, y: Double, size: Double, t: Double) {
    if (t < 0 || t > 0.65) return
    val u = density.toDouble()
    val k = t / 0.65; val e = 1 - (1 - k) * (1 - k)
    circleStroke(x, y, size / 2 * (0.3 + 3.1 * e), Color.White.op(1 - e), 3 * u)
    for (i in 0 until 14) {
        val a = i / 14.0 * 2 * PI + (i % 3) * 0.25
        val d = size * (1.1 + 0.25 * (i % 4)) * e
        val q = size * 0.2
        translate((x + cos(a) * d).f, (y + sin(a) * d).f) {
            rotate((i * 47 * e).f, Offset.Zero) { rect(-q / 2, -q / 2, q, q, (if (i % 3 == 0) secondary else primary).op(1 - e)) }
        }
    }
}
