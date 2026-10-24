package com.gogs.bananagame.games.spacerubble

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.RotateLeft
import androidx.compose.material.icons.filled.RotateRight
import androidx.compose.material.icons.filled.WifiTethering
import androidx.compose.material3.Icon
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
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

/**
 * Reflex — Space Rubble (iOS AsteroidsGame.swift, id "asteroids"): hold ◄ ► to spin, hold the
 * thruster to drift, tap FIRE. Rocks split twice before shattering; the field wraps. Clear it to win;
 * a rock clipping the ship or the clock running out fails. Drawn as Atari's 1979 vector game.
 */
object SpaceRubbleGame {
    val definition = GameDefinition(
        id = "asteroids",
        title = "Space Rubble",
        genre = Genre.REFLEX,
        manual = GameManual(
            bullets = listOf(
                "Hold the rotate buttons to spin, hold the thruster to drift, and tap FIRE to shoot.",
                "Every rock you hit splits into two smaller ones; the smallest shatter for good.",
                "The screen wraps at every edge; clear the whole field to win.",
                "Get clipped by a rock, or run out of time, and you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Giữ nút xoay để quay tàu, giữ nút đẩy để trôi, và chạm BẮN để nổ súng.",
                "Mỗi tảng đá trúng đạn vỡ thành hai tảng nhỏ hơn; tảng nhỏ nhất thì vỡ hẳn.",
                "Màn hình nối vòng ở mọi mép; dọn sạch cả bãi để thắng.",
                "Bị đá va trúng, hoặc hết giờ, sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> SpaceRubbleView(level, onWin, onFail) }
    )
}

private const val SHIP_R = 0.03
private fun rockR(s: Int) = listOf(0.03, 0.05, 0.075)[max(0, min(2, s - 1))]
private fun wrap(v: Double) = if (v < 0) v + 1 else if (v > 1) v - 1 else v
private fun torusDist(ax: Double, ay: Double, bx: Double, by: Double): Double {
    var dx = abs(ax - bx); var dy = abs(ay - by)
    if (dx > 0.5) dx = 1 - dx; if (dy > 0.5) dy = 1 - dy
    return hypot(dx, dy)
}

private class Rock(val id: Int, var x: Double, var y: Double, var vx: Double, var vy: Double, val size: Int, var spin: Double = 0.0)
private class Bullet(var x: Double, var y: Double, val vx: Double, val vy: Double, var life: Double)
private class Burst(val x: Double, val y: Double, val t0: Double, val seed: Int)

private class RubbleWorld(val level: Int, val isDemo: Boolean) {
    val rockCount = listOf(3, 3, 4, 4, 5, 5, 6)[min(level, 7) - 1]
    val rockSpeed = listOf(0.11, 0.13, 0.16, 0.19, 0.22, 0.25, 0.29)[min(level, 7) - 1]
    val timeLimit = listOf(64.0, 60.0, 56.0, 52.0, 49.0, 46.0, 43.0)[min(level, 7) - 1]

    var playing = true
    var shipX = 0.5; var shipY = 0.5; var svx = 0.0; var svy = 0.0
    var heading = 0.0                     // 0 = pointing up
    var rocks = mutableListOf<Rock>()
    val bullets = mutableListOf<Bullet>()
    val bursts = mutableListOf<Burst>()
    var rotDir = 0
    var thrusting = false
    var fireCD = 0.0
    var invuln = 1.0
    var timeLeft = timeLimit
    var shakeT0 = -10.0
    private var nextId = 0
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    private fun rock(x: Double, y: Double, a: Double, spd: Double, size: Int) = Rock(nextId++, x, y, cos(a) * spd, sin(a) * spd, size)

    fun setup() {
        shipX = 0.5; shipY = 0.5; svx = 0.0; svy = 0.0; heading = 0.0
        rotDir = 0; thrusting = false; fireCD = 0.0; invuln = 1.2
        bullets.clear(); bursts.clear()
        rocks = MutableList(rockCount) {
            // Spawn away from the centre so the ship isn't born on a rock.
            var px = 0.5; var py = 0.5
            while (hypot(px - 0.5, py - 0.5) < 0.28) { px = Random.nextDouble(); py = Random.nextDouble() }
            rock(px, py, Random.nextDouble(2 * PI), rockSpeed, 3)
        }
        timeLeft = timeLimit; playing = true
    }

    /** The closing stretch of level 1 (one big rock, one small) for the manual's autopilot. */
    fun demoSetup() {
        shipX = 0.5; shipY = 0.5; svx = 0.0; svy = 0.0; heading = 0.0
        rotDir = 0; thrusting = false; fireCD = 0.0; invuln = 1.2
        bullets.clear(); bursts.clear()
        rocks = mutableListOf(rock(0.16, 0.72, 4.9, rockSpeed, 3), rock(0.78, 0.58, 0.93, rockSpeed, 1))
        timeLeft = timeLimit; playing = true
    }

    fun fire(): Boolean {
        if (!playing || fireCD > 0) return false
        fireCD = 0.26
        val dx = sin(heading); val dy = -cos(heading)
        bullets.add(Bullet(shipX + dx * SHIP_R * 1.4, shipY + dy * SHIP_R * 1.4, dx, dy, 0.95))
        SoundManager.tap(); Haptics.tap()
        return true
    }

    fun step(dt: Double) {
        if (!playing) return
        if (fireCD > 0) fireCD -= dt
        if (invuln > 0) invuln -= dt
        heading += rotDir * 3.2 * dt
        if (thrusting) { svx += sin(heading) * 0.9 * dt; svy += -cos(heading) * 0.9 * dt }
        val damp = exp(-0.7 * dt); svx *= damp; svy *= damp
        val sp = hypot(svx, svy)
        if (sp > 0.6) { svx *= 0.6 / sp; svy *= 0.6 / sp }
        shipX = wrap(shipX + svx * dt); shipY = wrap(shipY + svy * dt)

        for (b in bullets) { b.x = wrap(b.x + b.vx * dt); b.y = wrap(b.y + b.vy * dt); b.life -= dt }
        bullets.removeAll { it.life <= 0 }
        for (r in rocks) { r.x = wrap(r.x + r.vx * dt); r.y = wrap(r.y + r.vy * dt); r.spin += 0.6 * dt }

        // Bullet vs rock.
        val newRocks = mutableListOf<Rock>(); val hit = HashSet<Bullet>(); val survivors = mutableListOf<Rock>()
        for (r in rocks) {
            val rr = rockR(r.size)
            val b = bullets.firstOrNull { it !in hit && torusDist(it.x, it.y, r.x, r.y) < rr }
            if (b == null) { survivors.add(r); continue }
            hit.add(b)
            bursts.add(Burst(r.x, r.y, nowSec(), r.id))
            shakeT0 = nowSec()
            SoundManager.tap(); Haptics.tap()
            if (r.size > 1) for (k in 0 until 2) {
                // Demo: fixed split (parent heading ± 0.9 rad at 1.3×) instead of random.
                val base = atan2(r.vy, r.vx)
                val a = if (isDemo) base + (if (k == 0) 0.9 else -0.9) else Random.nextDouble(2 * PI)
                val spd = rockSpeed * (if (isDemo) 1.3 else rnd(1.1, 1.5))
                newRocks.add(rock(r.x, r.y, a, spd, r.size - 1))
            }
        }
        rocks = (survivors + newRocks).toMutableList()
        bullets.removeAll { it in hit }
        bursts.removeAll { nowSec() - it.t0 > 0.6 }

        // Ship vs rock — only a genuine overlap counts.
        if (invuln <= 0 && rocks.any { torusDist(shipX, shipY, it.x, it.y) < rockR(it.size) + SHIP_R * 0.35 }) { fail(); return }
        if (rocks.isEmpty()) win()
    }

    fun win() { if (!playing) return; playing = false; onWin() }
    fun fail() { if (!playing) return; playing = false; shakeT0 = nowSec(); SoundManager.error(); onFail() }
}

@Composable
private fun SpaceRubbleView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { RubbleWorld(level, isDemo).also { if (!isDemo) it.setup() else it.demoSetup() } }
    world.onWin = onWin; world.onFail = onFail
    var demoTick by remember { mutableIntStateOf(0) }
    var demoFire by remember { mutableIntStateOf(0) }
    val start = remember { nowSec() }
    val tick by rememberFrameLoop { dt ->
        if (isDemo || !world.playing) return@rememberFrameLoop
        world.timeLeft = max(0.0, world.timeLimit - (nowSec() - start))
        if (world.timeLeft <= 0) { world.fail(); return@rememberFrameLoop }
        world.step(dt)
    }

    // Demo autopilot: turn toward the nearest rock's lead-intercept bearing; fire once the nose is on it.
    LaunchedEffect(Unit) {
        if (!isDemo) return@LaunchedEffect
        val dt = 1.0 / 60.0
        while (isActive) {
            world.demoSetup(); demoFire = 0
            val lockedUntil = HashMap<Int, Double>()
            var t = 0.0
            while (isActive && world.playing && t < 15) {
                t += dt
                val target = world.rocks.minByOrNull { torusDist(world.shipX, world.shipY, it.x, it.y) }
                if (target != null) {
                    var dx = target.x - world.shipX; var dy = target.y - world.shipY
                    if (dx > 0.5) dx -= 1 else if (dx < -0.5) dx += 1
                    if (dy > 0.5) dy -= 1 else if (dy < -0.5) dy += 1
                    val vx = target.vx; val vy = target.vy
                    val qa = vx * vx + vy * vy - 1; val qb = 2 * (dx * vx + dy * vy); val qc = dx * dx + dy * dy
                    val disc = max(0.0, qb * qb - 4 * qa * qc)
                    var th = (-qb - sqrt(disc)) / (2 * qa)
                    if (th < 0) th = (-qb + sqrt(disc)) / (2 * qa)
                    val want = atan2(dx + vx * th, -(dy + vy * th))
                    var e = want - world.heading
                    while (e > PI) e -= 2 * PI
                    while (e < -PI) e += 2 * PI
                    world.rotDir = if (e > 0.03) 1 else if (e < -0.03) -1 else 0
                    if (abs(e) < 0.06 && world.fireCD <= 0 && th < 0.85 && (lockedUntil[target.id] ?: -1.0) < t) {
                        lockedUntil[target.id] = t + th + 0.05
                        world.fire(); demoFire = 8
                    }
                }
                if (demoFire > 0) demoFire--
                world.step(dt)
                demoTick++
                delay(16)
            }
            world.rotDir = 0; demoFire = 0
            delay(1300)
        }
    }

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .background(rgb(0.05, 0.05, 0.07)),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        tick; demoTick
        Row(Modifier.padding(top = if (isDemo) 6.dp else 0.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Canvas(Modifier.size(if (isDemo) 16.dp else 20.dp)) {
                val r = min(size.width, size.height) * 0.45
                translate(size.width / 2, size.height / 2) {
                    drawPath(rockShape(0, r.toDouble(), 0.3), Color.White, style = Stroke(1.4f * density, join = StrokeJoin.Round))
                }
            }
            Text("${world.rocks.size}", style = ts(if (isDemo) 15.0 else 20.0, FontWeight.ExtraBold, Color.White, Mono))
        }
        if (!isDemo) {
            val f = world.timeLeft / world.timeLimit
            TimeBar(f, Modifier.fillMaxWidth().padding(horizontal = 60.dp).height(5.dp), fill = if (f < 0.3) rgb(1.0, 0.3, 0.3) else Color.White)
        }
        Canvas(
            Modifier.fillMaxWidth().weight(1f).clipToBounds().graphicsLayer {
                val t = nowSec() - world.shakeT0
                if (t in 0.0..0.35) translationX = (5 * density * sin(t / 0.35 * PI * 3) * (1 - t / 0.35)).toFloat()
            }
        ) {
            tick; demoTick
            vectors(world, level)
        }
        Row(Modifier.padding(bottom = if (isDemo) 6.dp else 8.dp), horizontalArrangement = Arrangement.spacedBy(if (isDemo) 8.dp else 10.dp)) {
            val w = if (isDemo) 60.dp else 70.dp; val h = if (isDemo) 38.dp else 54.dp
            val steel = gray(0.82); val dark = Color.Black.op(0.75)
            ArcadeButton(Icons.Filled.RotateLeft, steel, dark, w, h, isDemo && world.rotDir == -1, isDemo,
                onDown = { if (world.playing) world.rotDir = -1 }, onUp = { if (world.rotDir == -1) world.rotDir = 0 })
            ArcadeButton(Icons.Filled.RotateRight, steel, dark, w, h, isDemo && world.rotDir == 1, isDemo,
                onDown = { if (world.playing) world.rotDir = 1 }, onUp = { if (world.rotDir == 1) world.rotDir = 0 })
            ArcadeButton(Icons.Filled.LocalFireDepartment, rgb(1.0, 0.62, 0.14), Color.Black, w, h, isDemo && world.thrusting, isDemo,
                onDown = { if (world.playing) world.thrusting = true }, onUp = { world.thrusting = false })
            ArcadeButton(Icons.Filled.WifiTethering, rgb(0.9, 0.14, 0.14), Color.White, if (isDemo) 66.dp else 76.dp, h, demoFire > 0, isDemo,
                onDown = { world.fire() })
        }
    }
}

/** A round arcade button in its bezel, centred in its rectangular hit frame. */
@Composable
private fun ArcadeButton(icon: ImageVector, color: Color, tint: Color, w: androidx.compose.ui.unit.Dp, h: androidx.compose.ui.unit.Dp,
                         lit: Boolean, isDemo: Boolean, onDown: () -> Unit, onUp: () -> Unit = {}) {
    Box(
        Modifier.scale(if (lit) 0.92f else 1f).size(w, h)
            .then(if (isDemo) Modifier else Modifier.pressDown(onDown = onDown, onUp = onUp)),
        contentAlignment = Alignment.Center
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val u = density.toDouble()
            val bw = size.width.toDouble(); val bh = size.height.toDouble()
            rrect(0.0, 0.0, bw, bh, 14 * u, gray(0.1))
            rrectStroke(0.0, 0.0, bw, bh, 14 * u, gray(0.26), u)
            val d = min(bw, bh) * 0.94
            circle(bw / 2, bh / 2, d / 2, gray(0.04))
            val r = d * 0.4
            circle(bw / 2, bh / 2, r, Brush.radialGradient(
                listOf(color.mix(Color.White, if (lit) 0.55 else 0.3), color, color.mix(Color.Black, 0.35)),
                center = Offset((bw / 2 - r + d * 0.8 * 0.4).f, (bh / 2 - r + d * 0.8 * 0.35).f), radius = (d * 0.55).f))
            if (lit) circleStroke(bw / 2, bh / 2, d * 0.43, Color.White.op(0.9), 2 * u)
        }
        Icon(icon, null, tint = tint, modifier = Modifier.size(if (isDemo) 17.dp else 20.dp))
    }
}

// Atari vector art (iOS ASTArt).

/** The three classic rock outlines (unit radius), jagged with notches. */
private val shapes = listOf(
    doubleArrayOf(0.0, -1.0, 0.5, -0.9, 0.95, -0.45, 0.7, -0.05, 1.0, 0.35, 0.55, 0.95, 0.05, 0.7, -0.45, 0.95, -0.95, 0.5, -0.8, 0.05, -1.0, -0.4, -0.45, -0.95),
    doubleArrayOf(-0.2, -1.0, 0.35, -0.75, 0.85, -0.95, 1.0, -0.3, 0.6, 0.1, 0.95, 0.6, 0.4, 1.0, -0.3, 0.85, -0.7, 1.0, -1.0, 0.3, -0.7, -0.2, -0.9, -0.7),
    doubleArrayOf(0.0, -0.9, 0.6, -1.0, 1.0, -0.5, 0.8, 0.0, 1.0, 0.55, 0.45, 0.95, -0.1, 0.75, -0.6, 1.0, -1.0, 0.45, -0.85, -0.1, -1.0, -0.55, -0.55, -1.0),
)

private fun rockShape(k: Int, r: Double, spin: Double): Path {
    val pts = shapes[k % shapes.size]
    val cs = cos(spin); val sn = sin(spin)
    val p = Path()
    for (i in 0 until pts.size / 2) {
        val vx = pts[i * 2]; val vy = pts[i * 2 + 1]
        val qx = (vx * cs - vy * sn) * r; val qy = (vx * sn + vy * cs) * r
        if (i == 0) p.m(qx, qy) else p.l(qx, qy)
    }
    p.close(); return p
}

private val accents = listOf(rgb(0.40, 0.85, 1.00), rgb(0.45, 0.95, 0.85), rgb(0.70, 1.00, 0.55), rgb(1.00, 0.85, 0.35),
    rgb(1.00, 0.62, 0.35), rgb(1.00, 0.42, 0.42), rgb(1.00, 0.35, 0.60))

private fun DrawScope.vectors(world: RubbleWorld, level: Int) {
    val w = size.width.toDouble(); val h = size.height.toDouble(); val u = density.toDouble()
    val s = min(w, h)
    rect(0.0, 0.0, w, h, Color.Black)
    // The level's accent only warms the void a little; the vectors stay phosphor white.
    rect(0.0, 0.0, w, h, radial(listOf(accents[min(level, 7) - 1].op(0.1), Color.Transparent), w / 2, h, h * 0.8))
    val glow = rgb(0.75, 0.88, 1.0, 0.2)
    for (rock in world.rocks) {
        val r = rockR(rock.size) * s
        val shape = rockShape(rock.id % 3, r, rock.spin)
        // Draw the copies that poke in across a wrapped edge too.
        for (dx in -1..1) for (dy in -1..1) {
            val cx = (rock.x + dx) * w; val cy = (rock.y + dy) * h
            if (cx <= -r || cx >= w + r || cy <= -r || cy >= h + r) continue
            translate(cx.f, cy.f) {
                drawPath(shape, glow, style = Stroke((5 * u).f, join = StrokeJoin.Round))
                drawPath(shape, Color.White, style = Stroke((1.6 * u).f, join = StrokeJoin.Round))
            }
        }
    }
    for (b in world.bullets) circle(b.x * w, b.y * h, 2 * u, Color.White)
    for (b in world.bursts) particleBurst(b.x * w, b.y * h, nowSec() - b.t0, Color.White, 12, 46.0, seed = b.seed)

    val dim = world.invuln > 0 && (world.invuln * 12).toInt() % 2 == 0
    ship(world.shipX * w, world.shipY * h, SHIP_R * 2.4 * s, world.heading, world.thrusting, dim)
}

/** The arrow ship outline (nose, two fins, a notch), with a flickering flame. */
private fun DrawScope.ship(cx: Double, cy: Double, S: Double, heading: Double, thrusting: Boolean, dim: Boolean) {
    val u = density.toDouble()
    val a = if (dim) 0.4 else 1.0
    translate(cx.f, cy.f) {
        rotateRad(heading.f, Offset.Zero) {
            val hull = polyPath(0.0, -S / 2, S / 2, S / 2, 0.0, S / 2 - S * 0.28, -S / 2, S / 2)
            val yellow = rgb(1.0, 0.88, 0.3)
            drawPath(hull, yellow.op(0.25 * a), style = Stroke((5 * u).f, join = StrokeJoin.Round))
            drawPath(hull, yellow.op(a), style = Stroke((1.8 * u).f, join = StrokeJoin.Round))
            if (thrusting && (nowSec() * 24).toLong() % 2 == 0L) {
                val flame = polyPath(-S * 0.16, S / 2 - S * 0.2, 0.0, S / 2 + S * 0.3, S * 0.16, S / 2 - S * 0.2, close = false)
                drawPath(flame, Color.White.op(a), style = Stroke((1.5 * u).f, join = StrokeJoin.Round))
            }
        }
    }
}
