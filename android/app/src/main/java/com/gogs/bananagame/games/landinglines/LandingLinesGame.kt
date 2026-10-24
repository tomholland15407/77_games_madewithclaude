package com.gogs.bananagame.games.landinglines

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FlightLand
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Brain — Landing Lines (iOS FlightControlGame.swift, id "flight-control"): touch an aircraft and draw
 * its route; red jets to the red runway, yellow planes to the yellow one, helicopters to the pad.
 * Land the quota; any mid-air collision (or the clock) fails. Route drawing locks the feed.
 */
object LandingLinesGame {
    val definition = GameDefinition(
        id = "flight-control",
        title = "Landing Lines",
        genre = Genre.BRAIN,
        locksFeed = true,
        manual = GameManual(
            bullets = listOf(
                "Touch an aircraft and draw a route for it to follow.",
                "Red jets land on the red runway, yellow planes on the yellow one, helicopters on the helipad.",
                "Land the number of aircraft shown to win.",
                "Any two aircraft touching mid-air, or the clock running out, sends you back to level 1.",
            ),
            bulletsVI = listOf(
                "Chạm vào một máy bay và vẽ đường bay cho nó.",
                "Máy bay phản lực đỏ hạ cánh ở đường băng đỏ, máy bay vàng ở đường băng vàng, trực thăng ở bãi đáp.",
                "Hạ cánh đủ số máy bay yêu cầu để thắng.",
                "Hai máy bay va nhau trên không, hoặc hết giờ, bạn sẽ về lại cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> LandingLinesView(level, onWin, onFail) }
    )
}

private val KIND_COLORS = listOf(rgb(0.9, 0.2, 0.18), rgb(0.98, 0.8, 0.16), rgb(0.2, 0.5, 0.95))
private fun dist(a: P, b: P) = hypot(a.x - b.x, a.y - b.y)

/** World units: 1 unit = the play area's shorter side, so speeds/sizes feel the same on any screen. */
private class Zone(val kind: Int, val center: P, val heading: Double, val length: Double, val width: Double) {
    val dir = P(cos(heading), sin(heading))
    val entrance = if (kind == 2) center else P(center.x - dir.x * length / 2, center.y - dir.y * length / 2)
    val end = P(center.x + dir.x * length / 2, center.y + dir.y * length / 2)
    val zoneRadius = if (kind == 2) 0.07 else 0.075
}

private fun zonesFor(ww: Double, wh: Double) = listOf(
    Zone(0, P(0.45 * ww, 0.62 * wh), 20 * PI / 180, 0.42, 0.078),
    Zone(1, P(0.66 * ww, 0.3 * wh), -35 * PI / 180, 0.3, 0.06),
    Zone(2, P(0.78 * ww, 0.78 * wh), 0.0, 0.0, 0.065),
)

private class Plane(val id: Int, val kind: Int, var p: P, var heading: Double, val speed: Double) {
    val path = ArrayList<P>()
    var locked = false                // route ends in its landing zone
    var touchdown: Double? = null
    var spin = rnd(0.0, 6.0)
    val size = listOf(0.12, 0.105, 0.11)[kind]
}
private class Warning(val kind: Int, val point: P, val heading: Double, val at: Double)
private enum class LPhase { PLAY, WON, CRASHED, DONE }

private class AirWorld(val level: Int) {
    private val li = min(level, 7) - 1
    val quota = listOf(5, 7, 9, 11, 13, 15, 18)[li]
    val spawnEvery = listOf(5.0, 4.2, 3.6, 3.1, 2.7, 2.3, 2.0)[li]
    val speedK = listOf(1.0, 1.05, 1.1, 1.18, 1.26, 1.34, 1.42)[li]
    val kinds = if (level == 1) listOf(0, 1) else listOf(0, 1, 2)
    val timeLimit = quota * spawnEvery + 45

    var phase = LPhase.PLAY
    var pxW = 0.0; var pxH = 0.0                         // play area in px
    val unit get() = max(1.0, min(pxW, pxH))
    val ww get() = pxW / unit
    val wh get() = pxH / unit
    val zones get() = zonesFor(ww, wh)
    val planes = mutableListOf<Plane>()
    val warnings = mutableListOf<Warning>()
    var landed = 0
    var clock = 0.0
    var nextSpawn = 1.2
    var nextId = 0
    var drawingId: Int? = null
    var crashAt: P? = null; var crashT0 = 0.0
    var shakeT0 = -10.0
    var timeLeft = timeLimit

    fun beginRoute(p: P) {
        if (phase != LPhase.PLAY) return
        val pl = planes.filter { it.touchdown == null }.minByOrNull { dist(it.p, p) } ?: return
        if (dist(pl.p, p) >= 0.11) return
        drawingId = pl.id
        pl.path.clear(); pl.locked = false
        Haptics.tap()
    }

    fun extendRoute(p: P) {
        if (phase != LPhase.PLAY) return
        val pl = planes.firstOrNull { it.id == drawingId } ?: return
        if (pl.locked) return
        val last = pl.path.lastOrNull() ?: pl.p
        if (dist(last, p) <= 0.012) return
        pl.path.add(P(min(max(p.x, 0.01), ww - 0.01), min(max(p.y, 0.01), wh - 0.01)))
        // Reaching the matching landing zone locks the route onto the runway / pad.
        val z = zones[pl.kind]
        if (dist(p, z.entrance) < z.zoneRadius) {
            val aligned = z.kind == 2 || ((p.x - last.x) * z.dir.x + (p.y - last.y) * z.dir.y) > 0
            if (aligned) {
                pl.path.add(z.entrance)
                if (z.kind != 2) pl.path.add(z.end)
                pl.locked = true
                // drawingId stays set until the finger lifts so the rest of this drag can't re-grab it.
                SoundManager.tap(); Haptics.tap()
            }
        }
    }

    private fun advance(pl: Plane, d: Double) {
        var left = d
        while (left > 0 && pl.path.isNotEmpty()) {
            val next = pl.path[0]
            val dx = next.x - pl.p.x; val dy = next.y - pl.p.y
            val len = hypot(dx, dy)
            if (len > 0.0001) {
                // Turn smoothly toward the route instead of snapping.
                var diff = atan2(dy, dx) - pl.heading
                while (diff > PI) diff -= 2 * PI
                while (diff < -PI) diff += 2 * PI
                pl.heading += diff * 0.35
            }
            if (len <= left) { pl.p = next; pl.path.removeAt(0); left -= len }
            else { pl.p = P(pl.p.x + dx / len * left, pl.p.y + dy / len * left); left = 0.0 }
        }
        if (left > 0) pl.p = P(pl.p.x + cos(pl.heading) * left, pl.p.y + sin(pl.heading) * left)
    }

    /** An edge point (just inside the frame) plus an inward heading, away from current traffic. */
    private fun spawnSpot(): Pair<P, Double>? {
        repeat(12) {
            val f = rnd(0.18, 0.82)
            val edge = listOf(P(0.03, f * wh), P(ww - 0.03, f * wh), P(f * ww, 0.12), P(f * ww, wh - 0.03))[rndInt(0..3)]
            val aim = P(rnd(0.3, 0.7) * ww, rnd(0.3, 0.7) * wh)
            if (planes.any { dist(it.p, edge) < 0.28 }) return@repeat
            return edge to atan2(aim.y - edge.y, aim.x - edge.x)
        }
        return null
    }

    fun step(dt: Double) {
        clock += dt
        // Spawns (with a warning chevron first).
        if (phase == LPhase.PLAY) {
            if (clock >= nextSpawn) {
                nextSpawn = clock + spawnEvery * rnd(0.8, 1.2)
                spawnSpot()?.let { (edge, h) -> warnings.add(Warning(kinds.pick(), edge, h, clock)) }
            }
            for (wn in warnings) if (clock - wn.at >= 1.3) {
                planes.add(Plane(nextId++, wn.kind, P(wn.point.x - cos(wn.heading) * 0.06, wn.point.y - sin(wn.heading) * 0.06), wn.heading,
                    listOf(0.075, 0.06, 0.045)[wn.kind] * speedK))
            }
            warnings.removeAll { clock - it.at >= 1.3 }
        }
        val remove = HashSet<Int>()
        for (pl in planes) {
            pl.spin += dt * (if (pl.kind == 2) 22 else 30)
            val td = pl.touchdown
            if (td != null) {
                // Rolling out / settling on the pad.
                val t = clock - td
                if (pl.kind != 2) {
                    advance(pl, pl.speed * max(0.25, 1 - t * 0.6) * dt)
                    if (pl.path.isEmpty() || t > 1.3) remove.add(pl.id)
                } else if (t > 0.9) remove.add(pl.id)
                continue
            }
            if (pl.path.isNotEmpty()) {
                advance(pl, pl.speed * dt)
                val z = zones[pl.kind]
                if (pl.locked) {
                    val atGate = if (z.kind == 2) dist(pl.p, z.center) < 0.012 else (pl.path.size <= 1 && dist(pl.p, z.entrance) < 0.03)
                    if (atGate || (z.kind != 2 && pl.path.size == 1)) {
                        pl.touchdown = clock
                        landed++
                        SoundManager.tap(); Haptics.success()
                        if (landed >= quota && phase == LPhase.PLAY) phase = LPhase.WON
                    }
                }
            } else {
                // Straight on; turn back toward the field near an edge.
                var h = pl.heading; val p = pl.p; val m = 0.05
                val out = (p.x < m && cos(h) < 0) || (p.x > ww - m && cos(h) > 0) || (p.y < m && sin(h) < 0) || (p.y > wh - m && sin(h) > 0)
                if (out) {
                    var d = atan2(wh / 2 - p.y, ww / 2 - p.x) - h
                    while (d > PI) d -= 2 * PI
                    while (d < -PI) d += 2 * PI
                    h += max(-1.0, min(1.0, d)) * 1.8 * dt
                    pl.heading = h
                }
                pl.p = P(p.x + cos(h) * pl.speed * dt, p.y + sin(h) * pl.speed * dt)
            }
        }
        planes.removeAll { it.id in remove }
        // Collisions between airborne aircraft.
        if (phase == LPhase.PLAY) {
            val air = planes.filter { it.touchdown == null }
            loop@ for (a in air) for (b in air) {
                if (b.id <= a.id || dist(a.p, b.p) >= (a.size + b.size) * 0.5 * 0.82) continue
                crashAt = P((a.p.x + b.p.x) / 2, (a.p.y + b.p.y) / 2); crashT0 = clock
                planes.removeAll { it.id == a.id || it.id == b.id }
                phase = LPhase.CRASHED
                shakeT0 = nowSec()
                break@loop
            }
        }
    }
}

@Composable
private fun LandingLinesView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { AirWorld(level) }
    val tm = rememberTextMeasurer()
    val handP = rememberHand()
    val landP = rememberVectorPainter(Icons.Filled.FlightLand)
    val demo = remember { object { var finger: P? = null } }
    val tick by rememberFrameLoop()

    LaunchedEffect(Unit) {
        while (world.pxW == 0.0 && isActive) delay(20)
        if (isDemo) {
            suspend fun frames(n: Int) = repeat(n) { world.step(1.0 / 60); delay(16) }
            /** The finger presses the aircraft and traces a quadratic curve that meets the zone head-on. */
            suspend fun draw(planeId: Int, zone: Zone, bend: Double) {
                val pl = world.planes.firstOrNull { it.id == planeId } ?: return
                demo.finger = pl.p
                frames(10)
                world.beginRoute(pl.p)
                val a = world.planes.firstOrNull { it.id == planeId }?.p ?: pl.p
                val target = if (zone.kind == 2) zone.center else P(zone.entrance.x + zone.dir.x * 0.01, zone.entrance.y + zone.dir.y * 0.01)
                val ctrl = if (zone.kind == 2) P((a.x + target.x) / 2 - bend, (a.y + target.y) / 2)
                else P(zone.entrance.x - zone.dir.x * bend * 1.6, zone.entrance.y - zone.dir.y * bend * 1.6)
                for (s in 1..48) {
                    val t = s / 48.0
                    val q = P((1 - t) * (1 - t) * a.x + 2 * (1 - t) * t * ctrl.x + t * t * target.x, (1 - t) * (1 - t) * a.y + 2 * (1 - t) * t * ctrl.y + t * t * target.y)
                    demo.finger = q
                    world.extendRoute(q)
                    frames(1)
                }
                world.drawingId = null
            }
            // Level 1's closing stretch (3 of 5 landed): jet → red runway, then helicopter → pad.
            while (isActive) {
                val ww = world.ww; val wh = world.wh
                world.planes.clear()
                world.planes.add(Plane(1, 0, P(0.07, 0.3 * wh), 0.35, 0.1))
                world.planes.add(Plane(2, 2, P(0.97 * ww, 0.5 * wh), 2.8, 0.075))
                world.planes.add(Plane(3, 1, P(0.42 * ww, 0.13 * wh), 0.08, 0.07))
                world.warnings.clear(); world.landed = 3; world.clock = 0.0; world.nextSpawn = 999.0
                world.crashAt = null; world.phase = LPhase.PLAY; world.drawingId = null; demo.finger = null
                frames(30)
                draw(1, world.zones[0], 0.12)
                frames(20)
                draw(2, world.zones[2], -0.08)
                demo.finger = null
                var k = 0
                while (isActive && world.landed < 5 && k < 600) { frames(1); k++ }
                frames(80)
            }
        } else {
            world.phase = LPhase.PLAY; world.timeLeft = world.timeLimit
            val start = nowSec(); var last = nowSec(); var acc = 0.0
            while (isActive) {
                delay(16)
                val now = nowSec()
                acc += min(0.1, now - last); last = now
                while (acc >= 1.0 / 60) { acc -= 1.0 / 60; world.step(1.0 / 60) }
                when (world.phase) {
                    LPhase.PLAY -> {
                        world.timeLeft = max(0.0, world.timeLimit - (now - start))
                        if (world.timeLeft <= 0) { world.phase = LPhase.DONE; SoundManager.error(); onFail(); return@LaunchedEffect }
                    }
                    LPhase.WON -> { delay(900); world.phase = LPhase.DONE; onWin(); return@LaunchedEffect }
                    LPhase.CRASHED -> {
                        SoundManager.error(); Haptics.warning()
                        val t0 = nowSec()
                        while (isActive && nowSec() - t0 < 1.0) { delay(16); world.step(1.0 / 60) }
                        world.phase = LPhase.DONE; onFail(); return@LaunchedEffect
                    }
                    LPhase.DONE -> return@LaunchedEffect
                }
            }
        }
    }

    Canvas(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .onSizeChanged { world.pxW = it.width.toDouble(); world.pxH = it.height.toDouble() }
            .graphicsLayer {
                val t = nowSec() - world.shakeT0
                if (t in 0.0..0.35) translationX = (8 * density * sin(t / 0.35 * PI * 3) * (1 - t / 0.35)).toFloat()
            }
            .drawWithCache {
                // The static airfield, rendered once per size.
                val bmp = ImageBitmap(size.width.toInt().coerceAtLeast(1), size.height.toInt().coerceAtLeast(1))
                CanvasDrawScope().draw(this, layoutDirection, androidx.compose.ui.graphics.Canvas(bmp), size) { airfield(tm) }
                onDrawBehind { drawImage(bmp) }
            }
            .then(if (isDemo) Modifier else Modifier.touchDrag(
                onStart = { p -> world.beginRoute(P(p.x / world.unit, p.y / world.unit)) },
                onMove = { _, p -> world.extendRoute(P(p.x / world.unit, p.y / world.unit)) },
                onEnd = { _, _ -> world.drawingId = null },
            ))
    ) {
        tick
        traffic(world)
        hud(world, tm, landP, isDemo)
        demo.finger?.let { f ->
            val u = min(size.width, size.height).toDouble(); val s = u * 0.11
            hand(handP, f.x * u - s * 0.28, f.y * u - s * 0.08, s)
        }
    }
}

private fun DrawScope.hud(world: AirWorld, tm: TextMeasurer, landP: androidx.compose.ui.graphics.vector.VectorPainter, isDemo: Boolean) {
    val u = density.toDouble(); val w = size.width.toDouble()
    var y = (if (isDemo) 8 else 12) * u
    if (!isDemo) {
        val f = if (world.timeLimit > 0) world.timeLeft / world.timeLimit else 0.0
        rrect(40 * u, y, w - 80 * u, 6 * u, 3 * u, Color.Black.op(0.22))
        rrect(40 * u, y, (w - 80 * u) * clamp(f, 0.0, 1.0), 6 * u, 3 * u, if (f < 0.3) Color.Red else BananaTheme.banana)
        y += 12 * u
    }
    val fs = (if (isDemo) 15 else 20) * u
    val x = (if (isDemo) 12 else 18) * u
    val cy = y + fs * 0.6
    icon(landP, x, cy - fs * 0.55 + 2 * u, fs * 1.1, Color.Black.op(0.4))
    icon(landP, x, cy - fs * 0.55, fs * 1.1, Color.White)
    val s = "${min(world.landed, world.quota)} / ${world.quota}"
    text(tm, s, x + fs * 1.1 + 6 * u, cy + 2 * u, fs, Color.Black.op(0.4), FontWeight.Black, anchorX = 0.0)
    text(tm, s, x + fs * 1.1 + 6 * u, cy, fs, Color.White, FontWeight.Black, anchorX = 0.0)
}

private fun DrawScope.traffic(world: AirWorld) {
    val u = min(size.width, size.height).toDouble()
    val dp = density.toDouble()
    fun pt(p: P) = P(p.x * u, p.y * u)
    // Routes: dots in the aircraft colour; a locked route (it will land) is drawn brighter.
    for (pl in world.planes) {
        if (pl.path.isEmpty() || pl.touchdown != null) continue
        val route = Path(); val s = pt(pl.p); route.m(s.x, s.y)
        for (q in pl.path) { val r = pt(q); route.l(r.x, r.y) }
        val c = KIND_COLORS[pl.kind]
        val dash = PathEffect.dashPathEffect(floatArrayOf(0.1f, (u * 0.03).f))
        drawPath(route, Color.Black.op(0.18), style = Stroke((u * 0.014).f, cap = StrokeCap.Round, join = StrokeJoin.Round, pathEffect = dash))
        drawPath(route, if (pl.locked) c.lit(0.15) else c.lit(0.55).op(0.95),
            style = Stroke((u * (if (pl.locked) 0.012 else 0.01)).f, cap = StrokeCap.Round, join = StrokeJoin.Round, pathEffect = dash))
    }
    // Arrival warnings: a blinking chevron at the edge in the incoming aircraft's colour.
    if ((world.clock * 5).toInt() % 2 == 0) for (wn in world.warnings) {
        translate((wn.point.x * u).f, (wn.point.y * u).f) { rotateRad(wn.heading.f, Offset.Zero) {
            val tri = polyPath(u * 0.035, 0.0, -u * 0.02, -u * 0.03, -u * 0.02, u * 0.03)
            fillPath(tri, KIND_COLORS[wn.kind]); drawPath(tri, Color.White, style = Stroke((2 * dp).f))
        } }
    }
    // Proximity rings.
    val air = world.planes.filter { it.touchdown == null }
    val near = HashSet<Int>()
    for (a in air) for (b in air) if (b.id > a.id && dist(a.p, b.p) < (a.size + b.size) * 0.5 * 2.3) { near.add(a.id); near.add(b.id) }
    // Aircraft: shadow first, then body; landing aircraft shrink onto the ground.
    for (pl in world.planes.sortedBy { if (it.touchdown != null) 0 else 1 }) {
        val land = pl.touchdown?.let { min(1.0, (world.clock - it) / (if (pl.kind == 2) 0.9 else 1.3)) } ?: 0.0
        val c = pt(pl.p)
        aircraft(pl.kind, c.x, c.y, pl.heading, pl.size * u * (1 - 0.32 * land), 1 - land, pl.spin, if (land > 0.85) (1 - land) / 0.15 else 1.0)
        if (pl.id in near) circleStroke(c.x, c.y, pl.size * u * 0.85 * (0.85 + 0.15 * sin(world.clock * 14)), rgb(1.0, 0.15, 0.1, 0.9), 2.5 * dp)
    }
    // Crash.
    world.crashAt?.let { cp ->
        val t = world.clock - world.crashT0
        val p = pt(cp)
        val cols = listOf(rgb(1.0, 0.85, 0.3), rgb(1.0, 0.5, 0.1), rgb(0.85, 0.2, 0.1))
        for (k in 0 until 3) circle(p.x, p.y, u * (0.04 + t * (0.25 - k * 0.05)), cols[k].op(max(0.0, 0.9 - t * 0.9)))
        for (k in 0 until 7) {
            val a = k * 0.9; val d = u * (0.05 + t * 0.2)
            circle(p.x + cos(a) * d, p.y + sin(a) * d, u * (0.025 + t * 0.03), gray(0.25, max(0.0, 0.6 - t * 0.5)))
        }
    }
}

// Airfield (static background; iOS FCAirfield).

private fun DrawScope.airfield(tm: TextMeasurer) {
    val w = size.width.toDouble(); val h = size.height.toDouble(); val u = min(w, h)
    // Grass with mowing stripes.
    rect(0.0, 0.0, w, h, rgb(0.42, 0.68, 0.27))
    val band = u * 0.11
    var x = -h; var k = 0
    while (x < w + h) {
        if (k % 2 == 0) fillPath(polyPath(x, 0.0, x + band, 0.0, x + band + h * 0.35, h, x + h * 0.35, h), rgb(0.47, 0.73, 0.3))
        x += band; k++
    }
    // Soft darker patches.
    for ((i, f) in listOf(0.15 to 0.2, 0.8 to 0.12, 0.55 to 0.48, 0.2 to 0.88, 0.9 to 0.6, 0.45 to 0.95).withIndex()) {
        val r = u * (0.12 + (i % 3) * 0.04)
        oval(f.first * w - r, f.second * h - r * 0.7, r * 2, r * 1.4, rgb(0.3, 0.55, 0.2, 0.18))
    }
    for (z in zonesFor(w / u, h / u)) if (z.kind == 2) helipad(z, u, tm) else runway(z, u)
    // Trees along the margins.
    for ((i, f) in listOf(0.05 to 0.5, 0.93 to 0.9, 0.08 to 0.72, 0.95 to 0.42, 0.5 to 0.18, 0.18 to 0.12, 0.62 to 0.9).withIndex()) {
        tree(f.first * w, f.second * h, u * (0.045 + (i % 3) * 0.012))
    }
}

private fun DrawScope.runway(z: Zone, u: Double) {
    val dp = density.toDouble()
    translate((z.center.x * u).f, (z.center.y * u).f) { rotateRad(z.heading.f, Offset.Zero) {
        val L = z.length * u; val W = z.width * u
        val color = KIND_COLORS[z.kind]
        // Shoulder + asphalt.
        rrect(-L / 2 - W * 0.15, -W * 0.65, L + W * 0.3, W * 1.3, W * 0.2, rgb(0.75, 0.72, 0.62))
        rect(-L / 2, -W / 2, L, W, rgb(0.36, 0.37, 0.4))
        // Edge lines and dashed centre line.
        line(-L / 2, -W * 0.42, L / 2, -W * 0.42, Color.White.op(0.85), max(dp, W * 0.05), StrokeCap.Butt)
        line(-L / 2, W * 0.42, L / 2, W * 0.42, Color.White.op(0.85), max(dp, W * 0.05), StrokeCap.Butt)
        drawLine(Color.White.op(0.9), off(-L / 2 + W * 1.2, 0.0), off(L / 2 - W * 0.4, 0.0), max(dp, W * 0.06).f,
            pathEffect = PathEffect.dashPathEffect(floatArrayOf((W * 0.45).f, (W * 0.35).f)))
        // Threshold "piano keys" at the landing end.
        for (k in 0 until 5) rect(-L / 2 + W * 0.15, -W * 0.34 + k * W * 0.17 - W * 0.05, W * 0.6, W * 0.1, Color.White)
        // Coloured approach chevrons pointing down the runway, before the threshold.
        for (k in 0 until 3) {
            val cx = -L / 2 - W * (0.55 + k * 0.55)
            strokePath(polyPath(cx - W * 0.2, -W * 0.45, cx + W * 0.2, 0.0, cx - W * 0.2, W * 0.45, close = false), color.op(1 - k * 0.25), W * 0.16)
        }
        // The landing zone disc at the entrance.
        val r = z.zoneRadius * u
        circle(-L / 2, 0.0, r, color.op(0.28))
        drawCircle(color.op(0.9), r.f, off(-L / 2, 0.0), style = Stroke((2 * dp).f, pathEffect = PathEffect.dashPathEffect(floatArrayOf((5 * dp).f, (4 * dp).f))))
    } }
}

private fun DrawScope.helipad(z: Zone, u: Double, tm: TextMeasurer) {
    val cx = z.center.x * u; val cy = z.center.y * u; val r = z.width * u
    circle(cx, cy, r * 1.25, rgb(0.75, 0.72, 0.62))
    circle(cx, cy, r, KIND_COLORS[2])
    circleStroke(cx, cy, r * 0.82, Color.White, max(1.5 * density, r * 0.08))
    text(tm, "H", cx, cy, r * 1.05, Color.White, FontWeight.Black)
}

private fun DrawScope.tree(cx: Double, cy: Double, r: Double) {
    circle(cx + r * 0.35, cy + r * 0.45, r, Color.Black.op(0.2))
    circle(cx, cy, r, rgb(0.16, 0.45, 0.18))
    circle(cx - r * 0.15, cy - r * 0.2, r * 0.6, rgb(0.28, 0.6, 0.26))
    circle(cx - r * 0.225, cy - r * 0.325, r * 0.275, rgb(0.42, 0.72, 0.34))
}

// Aircraft art (iOS FCArt).

private fun jetBody(L: Double) = Path().apply {
    m(L * 0.52, 0.0); q(L * 0.46, -L * 0.07, L * 0.3, -L * 0.075); l(-L * 0.44, -L * 0.06); q(-L * 0.52, 0.0, -L * 0.44, L * 0.06)
    l(L * 0.3, L * 0.075); q(L * 0.46, L * 0.07, L * 0.52, 0.0)
}

private fun jetWings(L: Double) = Path().apply {
    for (s in listOf(-1.0, 1.0)) {
        m(L * 0.12, s * L * 0.06); l(-L * 0.16, s * L * 0.5); l(-L * 0.27, s * L * 0.5); l(-L * 0.12, s * L * 0.06); close()
        m(-L * 0.33, s * L * 0.05); l(-L * 0.46, s * L * 0.2); l(-L * 0.52, s * L * 0.2); l(-L * 0.45, s * L * 0.05); close()
    }
}

private fun propBody(L: Double) = Path().apply { m(L * 0.44, -L * 0.05); q(L * 0.52, 0.0, L * 0.44, L * 0.05); l(-L * 0.42, L * 0.025); l(-L * 0.42, -L * 0.025); close() }

private fun propWings(L: Double) = Path().apply {
    addRoundRect(androidx.compose.ui.geometry.RoundRect((-L * 0.02).f, (-L * 0.52).f, (L * 0.15).f, (L * 0.52).f, androidx.compose.ui.geometry.CornerRadius((L * 0.05).f)))
    addRoundRect(androidx.compose.ui.geometry.RoundRect((-L * 0.44).f, (-L * 0.18).f, (-L * 0.34).f, (L * 0.18).f, androidx.compose.ui.geometry.CornerRadius((L * 0.03).f)))
}

/** An aircraft pointing along `heading`; `altitude` 1…0 sets the ground shadow's offset. */
private fun DrawScope.aircraft(kind: Int, cx: Double, cy: Double, heading: Double, L: Double, altitude: Double, spin: Double, alpha: Double) {
    withAlpha(alpha) {
        translate((cx + L * 0.22 * altitude).f, (cy + L * 0.3 * altitude).f) { rotateRad(heading.f, Offset.Zero) {
            val sh = Color.Black.op(0.25)
            when (kind) {
                0 -> { fillPath(jetBody(L), sh); fillPath(jetWings(L), sh) }
                1 -> { fillPath(propBody(L), sh); fillPath(propWings(L), sh) }
                else -> { oval(-L * 0.12, -L * 0.14, L * 0.44, L * 0.28, sh); circle(0.0, 0.0, L * 0.55, Color.Black.op(0.25 * 0.25)) }
            }
        } }
        translate(cx.f, cy.f) { rotateRad(heading.f, Offset.Zero) {
            when (kind) { 0 -> jet(L); 1 -> prop(L, spin); else -> heli(L, spin) }
        } }
    }
}

private fun DrawScope.jet(L: Double) {
    val red = KIND_COLORS[0]; val outline = rgb(0.35, 0.05, 0.05)
    val lw = max(density.toDouble(), L * 0.025)
    fillPath(jetWings(L), red.shade(0.15)); strokePath(jetWings(L), outline, lw)
    // Engines under the wings.
    for (s in listOf(-1.0, 1.0)) rrect(-L * 0.06, s * L * 0.24 - L * 0.035, L * 0.16, L * 0.07, L * 0.03, gray(0.85))
    drawPath(jetBody(L), vgrad(listOf(red.lit(0.35), red, red.shade(0.2)), -L * 0.08, L * 0.08)); strokePath(jetBody(L), outline, lw)
    // White stripe + cockpit.
    rect(-L * 0.38, -L * 0.018, L * 0.7, L * 0.036, Color.White.op(0.75))
    oval(L * 0.33, -L * 0.045, L * 0.1, L * 0.09, rgb(0.12, 0.2, 0.35))
}

private fun DrawScope.prop(L: Double, spin: Double) {
    val yellow = KIND_COLORS[1]; val outline = rgb(0.45, 0.3, 0.02)
    val lw = max(density.toDouble(), L * 0.025)
    fillPath(propWings(L), yellow.shade(0.08)); strokePath(propWings(L), outline, lw)
    drawPath(propBody(L), vgrad(listOf(yellow.lit(0.4), yellow, yellow.shade(0.2)), -L * 0.06, L * 0.06)); strokePath(propBody(L), outline, lw)
    oval(L * 0.14, -L * 0.04, L * 0.14, L * 0.08, rgb(0.15, 0.25, 0.4))
    // Spinning propeller: a blur disc plus two blades.
    oval(L * 0.49, -L * 0.2, L * 0.05, L * 0.4, Color.White.op(0.3))
    val a = sin(spin) * L * 0.2
    line(L * 0.515, -a, L * 0.515, a, gray(0.2), max(1.5 * density, L * 0.035))
}

private fun DrawScope.heli(L: Double, spin: Double) {
    val blue = KIND_COLORS[2]; val outline = rgb(0.05, 0.15, 0.4)
    val dp = density.toDouble()
    // Skids.
    for (s in listOf(-1.0, 1.0)) line(-L * 0.12, s * L * 0.15, L * 0.3, s * L * 0.15, gray(0.25), max(dp, L * 0.03))
    // Tail boom + tail rotor.
    rrect(-L * 0.52, -L * 0.03, L * 0.45, L * 0.06, L * 0.03, blue.shade(0.1))
    val ta = sin(spin * 1.7) * L * 0.1
    line(-L * 0.5, -ta, -L * 0.5, ta, gray(0.2), max(dp, L * 0.025))
    // Cabin.
    drawOval(vgrad(listOf(blue.lit(0.35), blue, blue.shade(0.2)), -L * 0.15, L * 0.15), Offset((-L * 0.14).f, (-L * 0.15).f), androidx.compose.ui.geometry.Size((L * 0.46).f, (L * 0.3).f))
    drawOval(outline, Offset((-L * 0.14).f, (-L * 0.15).f), androidx.compose.ui.geometry.Size((L * 0.46).f, (L * 0.3).f), style = Stroke(max(dp, L * 0.025).f))
    oval(L * 0.14, -L * 0.1, L * 0.15, L * 0.2, rgb(0.7, 0.88, 1.0, 0.9))
    // Main rotor: a blur disc and two long blades.
    circle(L * 0.08, 0.0, L * 0.55, Color.White.op(0.12))
    for (k in 0 until 2) {
        val a = spin + k * PI / 2
        val dx = cos(a) * L * 0.55; val dy = sin(a) * L * 0.55
        line(L * 0.08 - dx, -dy, L * 0.08 + dx, dy, gray(0.18), max(1.5 * dp, L * 0.035))
    }
    circle(L * 0.08, 0.0, L * 0.04, gray(0.15))
}
