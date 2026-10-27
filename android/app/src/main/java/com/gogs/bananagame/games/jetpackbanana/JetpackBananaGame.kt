package com.gogs.bananagame.games.jetpackbanana

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.withTransform
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
 * Reflex — Jetpack Banana (iOS JetpackBananaGame.swift): hold anywhere to thrust; dodge the bobbing
 * lab mutants and fly the target distance. Mutant, ceiling or floor → level 1.
 */
object JetpackBananaGame {
    val definition = GameDefinition(
        id = "jetpack-banana",
        title = "Jetpack Banana",
        genre = Genre.REFLEX,
        manual = GameManual(
            bullets = listOf(
                "Hold anywhere to fire the jetpack and rise; release to fall under gravity.",
                "Little flying monsters drift in and bob up and down — dodge them.",
                "Fly the level's target distance to win.",
                "Touch a monster, the ceiling, or the floor and you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Giữ bất kỳ đâu để phụt phản lực bay lên; thả ra để rơi theo trọng lực.",
                "Những con quái bay nhỏ trôi vào và nhấp nhô lên xuống — hãy né chúng.",
                "Bay đủ quãng đường mục tiêu của cấp để thắng.",
                "Chạm quái, trần, hoặc sàn sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> JetpackBananaView(level, onWin, onFail) }
    )
}

private val monsterColors = listOf(rgb(0.86, 0.28, 0.34), rgb(0.55, 0.36, 0.85), rgb(0.25, 0.72, 0.74), rgb(0.85, 0.45, 0.24),
    rgb(0.80, 0.30, 0.62), rgb(0.40, 0.66, 0.35))
private val demoMonsters = listOf(doubleArrayOf(0.40, 0.07, 1.2, 0.0), doubleArrayOf(0.62, 0.08, 1.0, 1.5), doubleArrayOf(0.30, 0.06, 1.4, 3.0),
    doubleArrayOf(0.55, 0.08, 1.1, 0.7), doubleArrayOf(0.45, 0.07, 1.3, 2.2), doubleArrayOf(0.35, 0.08, 0.9, 4.0))

private const val BANANA_X = 0.28
private const val CEILING = 0.03
private const val FLOOR = 0.85
private const val BANANA_HY = 0.045
private const val BANANA_HX = 0.05
private const val MONSTER_HY = 0.045
private const val MONSTER_HX = 0.042
private const val GRAVITY = 1.8
private const val THRUST = 3.4
private const val MAX_V = 1.1

private class Monster(var x: Double, val baseY: Double, val amp: Double, val spd: Double, val phase: Double, val color: Color)

private class JetWorld(level: Int, val isDemo: Boolean) {
    private val li = min(level, 7) - 1
    val scrollSpeed = listOf(0.40, 0.46, 0.53, 0.60, 0.68, 0.77, 0.87)[li]
    val targetDist = listOf(4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0)[li]
    val spacing = listOf(0.85, 0.74, 0.65, 0.57, 0.50, 0.44, 0.39)[li]
    val bobAmp = listOf(0.08, 0.11, 0.14, 0.17, 0.20, 0.23, 0.26)[li]
    val bobSpeed = listOf(1.2, 1.4, 1.7, 2.0, 2.3, 2.7, 3.1)[li]
    val pairChance = listOf(0.0, 0.0, 0.10, 0.20, 0.32, 0.45, 0.60)[li]

    val monsters = mutableListOf<Monster>()
    var bananaY = 0.4; var vy = 0.0
    var thrusting = false
    var distance = 0.0
    var t = 0.0
    var done = false
    var demoSpawn = 0
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    fun monsterY(m: Monster) = clamp(m.baseY + m.amp * sin(t * m.spd + m.phase), CEILING + MONSTER_HY, FLOOR - MONSTER_HY)

    fun setup() { monsters.clear(); bananaY = 0.4; vy = 0.0; thrusting = false; distance = 0.0; t = 0.0; done = false; spawn(1.15) }

    private fun spawn(x: Double) {
        monsters.add(make(x, 0.20, FLOOR - 0.10))
        if (Math.random() < pairChance) {
            if (rndBool()) monsters.add(make(x + rnd(0.10, 0.20), 0.20, 0.45))
            else monsters.add(make(x + rnd(0.10, 0.20), FLOOR - 0.35, FLOOR - 0.10))
        }
    }

    private fun make(x: Double, lo: Double, hi: Double): Monster {
        if (isDemo) {
            val d = demoMonsters[demoSpawn % demoMonsters.size]
            demoSpawn++
            return Monster(x, d[0], d[1], d[2], d[3], monsterColors[demoSpawn % monsterColors.size])
        }
        return Monster(x, rnd(lo, hi), bobAmp * rnd(0.6, 1.0), bobSpeed * rnd(0.8, 1.2), rnd(0.0, 2 * PI), monsterColors.pick())
    }

    fun step(dt: Double) {
        if (done) return
        t += dt
        vy = clamp(vy + (if (thrusting) -THRUST else GRAVITY) * dt, -MAX_V, MAX_V)
        bananaY += vy * dt
        for (m in monsters) m.x -= scrollSpeed * dt
        distance += scrollSpeed * dt
        val last = monsters.maxOfOrNull { it.x }
        if (last != null && last < 1.15 - spacing) spawn(1.15)
        monsters.removeAll { it.x < -0.2 }
        if (bananaY <= CEILING + BANANA_HY || bananaY >= FLOOR - BANANA_HY) { fail(); return }
        for (m in monsters) if (abs(m.x - BANANA_X) < MONSTER_HX + BANANA_HX && abs(monsterY(m) - bananaY) < MONSTER_HY + BANANA_HY) { fail(); return }
        if (distance >= targetDist) win()
    }

    fun win() { if (done) return; done = true; onWin() }
    fun fail() { if (done) return; done = true; SoundManager.error(); onFail() }
}

@Composable
private fun JetpackBananaView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { JetWorld(level, isDemo).also { it.setup() } }
    world.onWin = onWin; world.onFail = onFail
    var demoTick by remember { mutableIntStateOf(0) }
    val tm = rememberTextMeasurer()
    val handP = rememberHand()
    val tick by rememberFrameLoop { dt -> if (!isDemo) world.step(dt) }

    LaunchedEffect(Unit) {
        if (!isDemo) return@LaunchedEffect
        val dt = 1.0 / 60.0
        while (isActive) {
            world.demoSpawn = 0; world.setup()
            delay(400)
            while (isActive && !world.done) {
                var targetY = 0.44
                world.monsters.filter { it.x + MONSTER_HX + BANANA_HX > BANANA_X }.minByOrNull { it.x }?.let { m ->
                    val arrive = max(0.0, (m.x - BANANA_X) / world.scrollSpeed)
                    val y = clamp(m.baseY + m.amp * sin((world.t + arrive) * m.spd + m.phase), CEILING + MONSTER_HY, FLOOR - MONSTER_HY)
                    targetY = if (y > 0.44) max(0.16, y - 0.22) else min(0.72, y + 0.22)
                }
                world.thrusting = world.bananaY + world.vy * 0.18 > targetY
                world.step(dt)
                demoTick++
                delay(16)
            }
            world.thrusting = false
            delay(1300)
        }
    }

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .background(rgb(0.08, 0.1, 0.15)),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        tick; demoTick
        if (!isDemo) Canvas(Modifier.fillMaxWidth().height(31.dp).padding(start = 16.dp)) {
            counter(tm, "${(min(world.distance, world.targetDist) / world.targetDist * 100).toInt()}%")
        }
        Canvas(
            Modifier.fillMaxWidth().weight(1f)
                .drawWithCache {
                    val m = module(size.width.toDouble(), density.toDouble())
                    val stripW = (m * 6).toInt().coerceAtLeast(1)
                    val bmp = ImageBitmap(stripW, size.height.toInt().coerceAtLeast(1))
                    CanvasDrawScope().draw(this, layoutDirection, androidx.compose.ui.graphics.Canvas(bmp),
                        androidx.compose.ui.geometry.Size(stripW.toFloat(), size.height)) { corridor(level) }
                    onDrawBehind {
                        val off = (world.distance * size.width) % (m * 3)
                        drawImage(bmp, topLeft = Offset((-off).toFloat(), 0f))
                    }
                }
                .then(if (isDemo) Modifier else Modifier.pressDown(onDown = { if (!world.done) world.thrusting = true }, onUp = { world.thrusting = false }))
        ) {
            tick; demoTick
            scene(world, level)
            if (isDemo) {
                val w = size.width.toDouble(); val h = size.height.toDouble(); val u = density.toDouble()
                val k = if (world.thrusting) 0.88 else 1.0
                val cx = w * 0.76; val cy = h * 0.6
                if (world.thrusting) circle(cx, cy, 23 * u * k, Color.White.op(0.28))
                val s = 28 * u * k
                withAlpha(if (world.thrusting) 1.0 else 0.6) { hand(handP, cx + 8 * u * k - s / 2, cy + 10 * u * k - s / 2, s) }
            }
            vignette(0.3)
        }
    }
}

// Jetpack Joyride art (iOS JBArt / JBCorridor / JBCounter).

private class JBPalette(val wallHi: Color, val wallLo: Color, val edge: Color, val seam: Color, val stripe: Color,
                        val wainscot: Color, val beam: Color, val windows: Boolean)

/** One wall module (two panels); the pattern repeats every three (a door in the third). */
private fun module(w: Double, u: Double) = max(160 * u, w * 0.62)

private fun palette(level: Int) = when (clampI(level, 1, 7)) {
    in 1..3 -> JBPalette(rgb(0.4, 0.5, 0.64), rgb(0.29, 0.37, 0.52), rgb(0.62, 0.72, 0.84), rgb(0.14, 0.18, 0.27),
        rgb(0.98, 0.8, 0.2), rgb(0.21, 0.26, 0.36), rgb(0.24, 0.27, 0.34), false)
    4, 5 -> JBPalette(rgb(0.46, 0.34, 0.4), rgb(0.33, 0.22, 0.28), rgb(0.7, 0.54, 0.58), rgb(0.18, 0.1, 0.13),
        rgb(0.95, 0.24, 0.2), rgb(0.25, 0.16, 0.2), rgb(0.26, 0.2, 0.24), false)
    else -> JBPalette(rgb(0.24, 0.29, 0.4), rgb(0.16, 0.2, 0.3), rgb(0.42, 0.5, 0.64), rgb(0.07, 0.09, 0.15),
        rgb(0.25, 0.88, 0.84), rgb(0.12, 0.15, 0.23), rgb(0.16, 0.18, 0.25), true)
}

private fun hash(n: Double): Double { val v = sin(n * 12.9898) * 43758.5453; return v - floor(v) }

private fun DrawScope.scene(world: JetWorld, level: Int) {
    val w = size.width.toDouble(); val h = size.height.toDouble()
    if (level == 4 || level == 5) alarm(world.distance * w, module(w, density.toDouble()), CEILING * h, world.t)
    for (m in world.monsters) mutant(m.x * w, world.monsterY(m) * h, MONSTER_HX * w, MONSTER_HY * h, m.color, world.t * 13 + m.phase)
    val hx = BANANA_X * w; val hy = world.bananaY * h
    val bh = h * 0.1
    val tilt = clamp(world.vy * 20, -18.0, 22.0)
    val a = deg(tilt)
    val lx = -bh * 0.34; val ly = bh * 0.52
    val nx = hx + lx * cos(a) - ly * sin(a); val ny = hy + lx * sin(a) + ly * cos(a)
    if (world.thrusting) gunfire(nx, ny, FLOOR * h, world.t) else idleSmoke(nx, ny, world.t)
    banana(hx, hy, bh, tilt)
    if (world.thrusting) muzzleFlash(nx, ny, bh, world.t)
}

/** Red-alert beacons on the ceiling beam, scrolling with the wall, each sweeping two beams. */
private fun DrawScope.alarm(scroll: Double, m: Double, ceilY: Double, t: Double) {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    val gap = m * 1.5
    var x = -(scroll % gap) + gap * 0.3
    var k = 0.0
    while (x < w + gap) {
        for (beam in 0 until 2) {
            val a = t * 4 + k + beam * PI
            val dx = cos(a); val dy = abs(sin(a)) + 0.35
            val len = h * 0.7
            drawPath(polyPath(x, ceilY, x + (dx - 0.2) * len, ceilY + dy * len, x + (dx + 0.2) * len, ceilY + dy * len),
                lin(listOf(SysColor.red.op(0.28), SysColor.red.op(0.0)), x, ceilY, x + dx * len, ceilY + dy * len))
        }
        oval(x - 7 * u, ceilY - 4 * u, 14 * u, 11 * u, rgb(1.0, 0.2, 0.16))
        oval(x - 3 * u, ceilY - u, 5 * u, 4 * u, Color.White.op(0.8))
        x += gap; k += 1.7
    }
    drawRect(SysColor.red.op(0.05 + 0.04 * sin(t * 7)))
}

/** An escaped lab mutant: a bat-winged blob filling its hit box, glaring at the banana. */
private fun DrawScope.mutant(cx: Double, cy: Double, hw: Double, hh: Double, color: Color, flap: Double) {
    val u = density.toDouble()
    val ink = rgb(0.08, 0.05, 0.1)
    val lift = sin(flap) * hh * 0.5
    for (side in listOf(-1.0, 1.0)) {
        val wing = Path()
        val sx = cx + side * hw * 0.55; val sy = cy - hh * 0.25
        val tx = cx + side * hw * 2.0; val ty = cy - hh * 0.55 - lift
        wing.m(sx, sy); wing.q(cx + side * hw * 1.3, cy - hh * 0.95 - lift * 0.6, tx, ty)
        var fx = tx; var fy = ty
        for ((qx, qy) in listOf(cx + side * hw * 1.75 to cy - hh * 0.08 - lift * 0.7, cx + side * hw * 1.35 to cy + hh * 0.02 - lift * 0.45,
            cx + side * hw * 0.8 to cy + hh * 0.18)) {
            wing.q((fx + qx) / 2 - side * hw * 0.05, (fy + qy) / 2 - hh * 0.2, qx, qy); fx = qx; fy = qy
        }
        wing.close()
        fillPath(wing, color.shade(0.38)); strokePath(wing, ink, 1.3 * u)
    }
    for (side in listOf(-1.0, 1.0)) {
        val horn = polyPath(cx + side * hw * 0.25, cy - hh * 0.8, cx + side * hw * 0.5, cy - hh * 1.12, cx + side * hw * 0.62, cy - hh * 0.66)
        fillPath(horn, color.shade(0.2)); strokePath(horn, ink, 1.1 * u)
    }
    drawOval(radial(listOf(color.lit(0.4), color, color.shade(0.35)), cx - hw * 0.35, cy - hh * 0.45, hh * 1.6), off(cx - hw, cy - hh * 0.92), sz(hw * 2, hh * 1.84))
    oval(cx - hw * 0.62, cy + hh * 0.08, hw * 1.24, hh * 0.7, color.lit(0.3).op(0.55))
    ellipseStroke(cx, cy, hw, hh * 0.92, ink, 1.6 * u)
    for ((ex, er) in listOf(-0.38 to 0.3, 0.16 to 0.26)) {
        val x = cx + hw * ex - hw * er; val y = cy - hh * 0.5; val ew = hw * er * 2; val eh = hh * 0.42
        oval(x, y, ew, eh, Color.White); ellipseStroke(x + ew / 2, y + eh / 2, ew / 2, eh / 2, ink, u)
        oval(x + ew * 0.08, y + eh / 2 - eh * 0.2, ew * 0.5, eh * 0.5, ink)
    }
    val brows = Path()
    brows.m(cx - hw * 0.72, cy - hh * 0.62); brows.l(cx - hw * 0.12, cy - hh * 0.46)
    brows.m(cx + hw * 0.4, cy - hh * 0.6); brows.l(cx - hw * 0.02, cy - hh * 0.46)
    strokePath(brows, ink, 2 * u)
    rrect(cx - hw * 0.62, cy + hh * 0.12, hw * 1.1, hh * 0.3, hh * 0.12, rgb(0.25, 0.04, 0.08))
    val fangs = Path()
    for (fx in listOf(-0.46, -0.1, 0.26)) { fangs.m(cx + hw * fx, cy + hh * 0.12); fangs.l(cx + hw * (fx + 0.09), cy + hh * 0.27); fangs.l(cx + hw * (fx + 0.18), cy + hh * 0.12); fangs.close() }
    fillPath(fangs, Color.White)
}

/** The machine-gun jetpack's spray: tracers raining to the walkway, sparking where they hit. */
private fun DrawScope.gunfire(nx: Double, ny: Double, floorY: Double, t: Double) {
    val u = density.toDouble()
    val drop = max(1.0, floorY - ny)
    val streaks = Path(); val sparks = Path()
    for (i in 0 until 9) {
        val k = i.toDouble()
        val ang = (-4 + hash(k + 1) * 22) * PI / 180
        val ph = (t * 7 + k * 0.111) % 1.0
        val dx = -sin(ang); val dy = cos(ang)
        val len = drop / dy
        val px = nx + dx * len * ph; val py = ny + dy * len * ph
        streaks.m(px, py); streaks.l(px - dx * 13 * u, py - dy * 13 * u)
        if (ph > 0.8) {
            val hx = nx + dx * len
            for (s in 0 until 4) {
                val sa = PI * (1.05 + 0.3 * s) + hash(k * 3 + s + floor(t * 20))
                sparks.m(hx, floorY); sparks.l(hx + cos(sa) * 7 * u, floorY + sin(sa) * 7 * u)
            }
        }
    }
    strokePath(streaks, rgb(1.0, 0.92, 0.55), 2.2 * u)
    strokePath(sparks, rgb(1.0, 0.8, 0.3), 1.4 * u)
}

private fun DrawScope.muzzleFlash(nx: Double, ny: Double, s: Double, t: Double) {
    val flick = 0.8 + hash(floor(t * 30)) * 0.5
    val star = polyPath((0 until 10).map { i ->
        val a = i / 10.0 * 2 * PI + PI / 2
        val r = if (i % 2 == 0) s * 0.26 * flick else s * 0.09
        P(nx + cos(a) * r * 0.8, ny + sin(a) * r + s * 0.06)
    })
    fillPath(star, rgb(1.0, 0.62, 0.14))
    oval(nx - s * 0.07, ny - s * 0.02, s * 0.14, s * 0.14, rgb(1.0, 0.97, 0.75))
}

private fun DrawScope.idleSmoke(nx: Double, ny: Double, t: Double) {
    val u = density.toDouble()
    val ph = (t * 1.6) % 1.0
    val r = (3 + ph * 7) * u
    circle(nx - ph * 10 * u, ny + ph * 8 * u, r, Color.White.op(0.22 * (1 - ph)))
}

/** The banana in Barry's machine-gun jetpack, facing right; `s` ≈ the drawn banana's height. */
private fun DrawScope.banana(cx: Double, cy: Double, s: Double, tiltDeg: Double) {
    withTransform({ translate(cx.f, cy.f); rotate(tiltDeg.f, Offset.Zero); scale(s.f, s.f, Offset.Zero) }) {
        val ink = rgb(0.08, 0.07, 0.1)
        rrect(-0.5, -0.3, 0.3, 0.66, 0.1, hgrad(listOf(gray(0.78), gray(0.5), gray(0.34)), -0.5, -0.2))
        rrectStroke(-0.5, -0.3, 0.3, 0.66, 0.1, ink, 0.035)
        rrect(-0.4, 0.32, 0.12, 0.2, 0.03, gray(0.2)); rrectStroke(-0.4, 0.32, 0.12, 0.2, 0.03, ink, 0.03)
        for (i in 0 until 4) rrect(-0.19, 0.12 + i * 0.075, 0.1, 0.05, 0.02, rgb(0.86, 0.66, 0.24))
        val body = Path()
        body.m(0.04, -0.5); body.c(-0.42, -0.26, -0.36, 0.38, 0.14, 0.5); body.c(0.08, 0.26, 0.14, -0.24, 0.04, -0.5); body.close()
        drawPath(body, hgrad(listOf(rgb(1.0, 0.92, 0.4), rgb(1.0, 0.8, 0.2), rgb(0.9, 0.62, 0.1)), 0.1, -0.3))
        val ridge = Path(); ridge.m(-0.02, -0.36); ridge.q(-0.2, 0.0, 0.02, 0.36)
        strokePath(ridge, Color.White.op(0.5), 0.04)
        strokePath(body, ink, 0.04)
        val straps = Path(); straps.m(-0.24, -0.12); straps.l(0.07, -0.06); straps.m(-0.24, 0.16); straps.l(0.07, 0.2)
        strokePath(straps, rgb(0.22, 0.2, 0.24), 0.06)
        val stem = Path(); stem.m(0.04, -0.49); stem.q(0.04, -0.6, 0.14, -0.64)
        strokePath(stem, ink, 0.1); strokePath(stem, rgb(0.55, 0.42, 0.16), 0.055)
        oval(0.09, 0.46, 0.08, 0.08, rgb(0.3, 0.2, 0.1))
        oval(-0.08, -0.33, 0.17, 0.19, Color.White); ellipseStroke(0.005, -0.235, 0.085, 0.095, ink, 0.025)
        oval(0.01, -0.28, 0.07, 0.09, ink)
        val smile = Path(); smile.m(-0.06, -0.07); smile.q(0.02, 0.0, 0.07, -0.1)
        strokePath(smile, ink, 0.03)
    }
}

/** Jetpack Joyride's chunky white counter with a dark outline. */
private fun DrawScope.counter(tm: TextMeasurer, s: String) {
    val u = density.toDouble()
    val size = 28 * u; val y = this.size.height / 2.0
    for (i in 0 until 8) { val a = i * PI / 4; text(tm, s, cos(a) * 2.2 * u, y + sin(a) * 2.2 * u, size, rgb(0.1, 0.1, 0.16), FontWeight.Black, anchorX = 0.0) }
    text(tm, s, 0.0, y, size, rgb(0.95, 0.96, 0.99), FontWeight.Black, anchorX = 0.0)
}

private fun DrawScope.rivets(x: Double, y: Double, w: Double, h: Double, color: Color) {
    val u = density.toDouble()
    for ((qx, qy) in listOf(x + 6 * u to y + 6 * u, x + w - 6 * u to y + 6 * u, x + 6 * u to y + h - 6 * u, x + w - 6 * u to y + h - 6 * u)) circle(qx, qy, 2.2 * u, color)
}

/** The lab corridor strip (six modules wide): beam, riveted panels, doors or windows, walkway. */
private fun DrawScope.corridor(level: Int) {
    val u = density.toDouble()
    val W = size.width.toDouble(); val h = size.height.toDouble()
    val pal = palette(level)
    val m = W / 6
    val ceilY = 0.03 * h; val floorY = 0.85 * h
    val stripeY = h * 0.46; val lowY = h * 0.7
    rect(0.0, 0.0, W, floorY, vgrad(listOf(pal.wallLo, pal.wallHi, pal.wallLo), ceilY, floorY))
    for (k in 0 until 6) {
        val x0 = k * m
        val door = k % 3 == 2
        for (p in 0 until 2) {
            if (door && p == 1) continue
            val rx = x0 + p * m / 2 + 3 * u; val ry = ceilY + 8 * u; val rw = m / 2 - 6 * u; val rh = stripeY - ceilY - 14 * u
            if (pal.windows) {
                val wx = rx + 6 * u; val wy = ry + 8 * u; val ww = rw - 12 * u; val wh = rh - 16 * u
                rrect(wx, wy, ww, wh, 10 * u, vgrad(listOf(rgb(0.02, 0.03, 0.1), rgb(0.08, 0.1, 0.26)), wy, wy + wh))
                for (i in 0 until 9) {
                    val q = (k * 20 + p * 9 + i).toDouble()
                    circle(wx + hash(q) * ww, wy + hash(q + 0.5) * wh, (0.6 + hash(q + 0.7) * 1.2) * u, Color.White.op(0.8))
                }
                rrectStroke(wx, wy, ww, wh, 10 * u, pal.edge, 3 * u)
            } else {
                rect(rx, ry, rw, rh, lin(listOf(pal.wallHi, pal.wallLo), rx, ry, rx + rw, ry + rh))
                val bevel = Path(); bevel.m(rx, ry + rh); bevel.l(rx, ry); bevel.l(rx + rw, ry)
                strokePath(bevel, pal.edge.op(0.7), 1.5 * u, StrokeCap.Butt)
                rectStroke(rx, ry, rw, rh, pal.seam.op(0.8), u)
                rivets(rx, ry, rw, rh, pal.seam.op(0.9))
            }
        }
        val lx = x0 + 3 * u; val lw = m - 6 * u; val lh = floorY - lowY - 3 * u
        rect(lx, lowY, lw, lh, pal.wainscot)
        val vents = Path(); var vx = lx + 12 * u
        while (vx < lx + lw - 10 * u) { vents.m(vx, lowY + 10 * u); vents.l(vx, lowY + lh - 10 * u); vx += 9 * u }
        strokePath(vents, pal.seam.op(0.6), 2 * u, StrokeCap.Butt)
        rectStroke(lx, lowY, lw, lh, pal.seam, u)
        if (door) {
            val dx = x0 + m * 0.52; val dy = h * 0.3; val dw = m * 0.4; val dh = floorY - h * 0.3
            rect(dx - 5 * u, dy - 5 * u, dw + 10 * u, dh + 10 * u, pal.seam)
            rect(dx, dy, dw, dh, hgrad(listOf(gray(0.32), gray(0.18)), dx, dx + dw))
            line(dx + dw / 2, dy, dx + dw / 2, dy + dh, Color.Black.op(0.6), 2 * u, StrokeCap.Butt)
            rrect(dx + dw / 2 - dw * 0.3, dy + dh * 0.14, dw * 0.6, dh * 0.16, 3 * u, rgb(0.5, 0.85, 0.95, 0.5))
            val hx = dx - 5 * u; val hy = dy + dh - 12 * u; val hw = dw + 10 * u; val hh = 12 * u
            clipRect(hx.f, hy.f, (hx + hw).f, (hy + hh).f) {
                rect(hx, hy, hw, hh, rgb(0.98, 0.8, 0.2))
                val st = Path(); var sx = hx - 12 * u
                while (sx < hx + hw) { st.m(sx, hy + hh); st.l(sx + 6 * u, hy + hh); st.l(sx + 18 * u, hy); st.l(sx + 12 * u, hy); st.close(); sx += 12 * u }
                fillPath(st, rgb(0.1, 0.1, 0.1))
            }
            rrect(dx + dw / 2 - 14 * u, dy - 16 * u, 28 * u, 8 * u, 3 * u, if (level in 4..5) rgb(1.0, 0.3, 0.25) else rgb(0.4, 1.0, 0.55))
        }
    }
    rect(0.0, stripeY - 4 * u, W, 9 * u, pal.stripe)
    rect(0.0, stripeY + 5 * u, W, 2 * u, Color.Black.op(0.3))
    val pipeY = h * 0.6
    rect(0.0, pipeY - 4 * u, W, 8 * u, vgrad(listOf(pal.edge.op(0.55), pal.seam.op(0.7)), pipeY - 4 * u, pipeY + 4 * u))
    var fx = m * 0.25
    while (fx < W) { rect(fx - 3 * u, pipeY - 6 * u, 6 * u, 12 * u, pal.seam.op(0.75)); fx += m / 2 }
    if (!pal.windows) for (k in 0 until 6) {
        if (k % 3 == 2) continue
        val x0 = k * m
        if (k % 3 == 0) {
            val sx = x0 + m * 0.12; val sy = stripeY - h * 0.13; val sw = m * 0.22; val sh = h * 0.075
            rrect(sx - 3 * u, sy - 3 * u, sw + 6 * u, sh + 6 * u, 4 * u, pal.seam)
            rrect(sx, sy, sw, sh, 2 * u, rgb(0.04, 0.12, 0.1))
            val trace = Path()
            for (i in 0..16) { val px = sx + sw * i / 16; val py = sy + sh / 2 + sin(i * 1.1 + k) * sh * 0.28; if (i == 0) trace.m(px, py) else trace.l(px, py) }
            strokePath(trace, rgb(0.3, 1.0, 0.55, 0.8), 1.2 * u)
        } else {
            val cx = x0 + m * 0.75; val cy = pipeY - 17 * u
            line(cx, cy + 8 * u, cx, pipeY, pal.seam.op(0.8), 3 * u, StrokeCap.Butt)
            circle(cx, cy, 10 * u, gray(0.85).op(0.85)); circleStroke(cx, cy, 10 * u, pal.seam, 2.5 * u)
            line(cx, cy, cx + 5 * u, cy - 5 * u, rgb(0.75, 0.12, 0.1), 1.6 * u)
        }
    }
    rect(0.0, 0.0, W, ceilY, pal.beam)
    rect(0.0, ceilY - 2 * u, W, 2 * u, pal.edge.op(0.6))
    rect(0.0, ceilY, W, 10 * u, vgrad(listOf(Color.Black.op(0.35), Color.Transparent), ceilY, ceilY + 10 * u))
    rect(0.0, floorY, W, h - floorY, rgb(0.14, 0.15, 0.19))
    rect(0.0, floorY, W, 4 * u, rgb(0.72, 0.75, 0.8))
    rect(0.0, floorY + 4 * u, W, 9 * u, rgb(0.98, 0.8, 0.2))
    val haz = Path(); var hx = -20 * u
    while (hx < W) { haz.m(hx, floorY + 13 * u); haz.l(hx + 10 * u, floorY + 13 * u); haz.l(hx + 19 * u, floorY + 4 * u); haz.l(hx + 9 * u, floorY + 4 * u); haz.close(); hx += 20 * u }
    fillPath(haz, rgb(0.1, 0.1, 0.1))
    val grate = Path(); var gx = 0.0
    while (gx < W) { grate.m(gx, floorY + 16 * u); grate.l(gx, h); gx += 8 * u }
    var gy = floorY + 16 * u
    while (gy < h) { grate.m(0.0, gy); grate.l(W, gy); gy += 8 * u }
    strokePath(grate, Color.Black.op(0.4), 1.5 * u, StrokeCap.Butt)
}
