package com.gogs.bananagame.games.moontouchdown

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
import androidx.compose.material.icons.filled.LocalGasStation
import androidx.compose.material.icons.filled.RotateLeft
import androidx.compose.material.icons.filled.RotateRight
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material3.Icon
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
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Reflex — Moon Touchdown (iOS LunarLanderGame.swift, id "lunar-lander"): gravity pulls the lander
 * into the rocks; hold the thruster and the rotate keys to set it down on the lit pad slowly and
 * nearly upright. Too fast, too tilted, off the pad, out of time → crash. Atari vector look.
 */
object MoonTouchdownGame {
    val definition = GameDefinition(
        id = "lunar-lander",
        title = "Moon Touchdown",
        genre = Genre.REFLEX,
        manual = GameManual(
            bullets = listOf(
                "Gravity constantly pulls the lander down.",
                "Hold the thruster to fight it and the rotate buttons to turn.",
                "Touch down on the flat lit pad while nearly upright and moving slowly to win.",
                "Too fast, too tilted, off the pad, or out of fuel — and you crash back to level 1.",
            ),
            bulletsVI = listOf(
                "Trọng lực liên tục kéo tàu đáp xuống.",
                "Giữ nút đẩy để chống lại nó và các nút xoay để quay.",
                "Đáp xuống bệ phẳng sáng khi gần như thẳng đứng và di chuyển chậm để thắng.",
                "Quá nhanh, quá nghiêng, lệch bệ, hoặc hết nhiên liệu — bạn rơi về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> MoonTouchdownView(level, onWin, onFail) }
    )
}

private const val SHIP_R = 0.028
private val demoHills = listOf(0.02, 0.08, 0.11, 0.05, 0.09, 0.12, 0.04, 0.07, 0.10, 0.03, 0.06, 0.09, 0.02, 0.05, 0.11, 0.07, 0.10, 0.04,
    0.08, 0.12, 0.06, 0.03, 0.09, 0.05, 0.10)

private class LanderWorld(level: Int) {
    private val li = min(level, 7) - 1
    val gravity = listOf(0.17, 0.21, 0.25, 0.30, 0.35, 0.41, 0.47)[li]
    val padW = listOf(0.24, 0.20, 0.17, 0.14, 0.11, 0.09, 0.07)[li]
    val fuelMax = listOf(11.0, 10.0, 9.0, 8.0, 7.5, 7.0, 6.5)[li]
    val safeSpeed = listOf(0.32, 0.29, 0.26, 0.22, 0.19, 0.16, 0.13)[li]
    val maxTilt = listOf(0.55, 0.48, 0.42, 0.36, 0.30, 0.24, 0.19)[li]
    val timeLimit = listOf(36.0, 34.0, 32.0, 30.0, 28.0, 26.0, 24.0)[li]

    var playing = true
    var x = 0.5; var y = 0.12; var vx = 0.0; var vy = 0.0
    var angle = 0.0
    var rotDir = 0
    var thrusting = false
    var fuel = 0.0
    var terrain: List<P> = emptyList()
    var padCenter = 0.5
    var padY = 0.82
    var timeLeft = timeLimit
    var shakeT0 = -10.0
    var crashAt: Double? = null; var crashX = 0.0; var crashY = 0.0
    var landedAt: Double? = null
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    val speed get() = hypot(vx, vy)

    private fun buildTerrain(padHeight: Double, hill: (Int) -> Double) {
        val n = 24
        val lo = padCenter - padW / 2; val hi = padCenter + padW / 2
        val pts = ArrayList<P>()
        for (i in 0..n) {
            val tx = i.toDouble() / n
            pts.add(if (tx >= lo - 0.001 && tx <= hi + 0.001) P(tx, padHeight) else P(tx, min(0.94, max(0.6, padHeight - hill(i)))))
        }
        // Guarantee an exact pad sample so padY is well-defined.
        pts.add(P(padCenter, padHeight))
        pts.sortBy { it.x }
        terrain = pts
        padY = terrain.firstOrNull { abs(it.x - padCenter) < 0.001 }?.y ?: 0.82
    }

    private fun reset() {
        angle = 0.0; rotDir = 0; thrusting = false; fuel = fuelMax
        crashAt = null; landedAt = null
        timeLeft = timeLimit; playing = true
    }

    fun setup() {
        x = rnd(0.3, 0.7); y = 0.12; vx = rnd(-0.06, 0.06); vy = 0.02
        padCenter = rnd(0.2, 0.8)
        buildTerrain(rnd(0.74, 0.84)) { rnd(-0.06, 0.12) }
        reset()
    }

    /** Level 1 on a fixed site: start high on the left drifting right, pad at 0.68 among fixed hills. */
    fun demoSetup() {
        x = 0.28; y = 0.12; vx = 0.03; vy = 0.02
        padCenter = 0.68
        buildTerrain(0.80) { demoHills[it] }
        reset()
    }

    private fun groundY(at: Double): Double {
        if (terrain.size < 2) return 0.82
        for (i in 0 until terrain.size - 1) {
            val a = terrain[i]; val b = terrain[i + 1]
            if (at >= a.x && at <= b.x) {
                val t = if (b.x - a.x > 0.0001) (at - a.x) / (b.x - a.x) else 0.0
                return a.y + (b.y - a.y) * t
            }
        }
        return terrain.last().y
    }

    fun step(dt: Double) {
        if (!playing) return
        angle = clamp(angle + rotDir * 1.9 * dt, -1.4, 1.4)
        if (thrusting && fuel > 0) {
            fuel -= dt
            val power = gravity * 2.7
            vx += sin(angle) * power * dt; vy += -cos(angle) * power * dt
        }
        vy += gravity * dt
        x += vx * dt; y += vy * dt
        // Side walls bounce softly.
        if (x < 0.03) { x = 0.03; vx = abs(vx) * 0.4 }
        if (x > 0.97) { x = 0.97; vx = -abs(vx) * 0.4 }
        // Ground contact.
        val gy = groundY(x)
        if (y + SHIP_R >= gy) {
            y = gy - SHIP_R
            val onPad = abs(x - padCenter) < padW / 2
            if (onPad && speed < safeSpeed && abs(angle) < maxTilt) win()
            else { crashX = x; crashY = y; crashAt = nowSec(); crash() }
        }
    }

    fun win() { if (!playing) return; playing = false; landedAt = nowSec(); Haptics.tap(); onWin() }
    fun crash() { if (!playing) return; playing = false; shakeT0 = nowSec(); SoundManager.error(); onFail() }
}

@Composable
private fun MoonTouchdownView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { LanderWorld(level).also { if (isDemo) it.demoSetup() else it.setup() } }
    world.onWin = onWin; world.onFail = onFail
    var demoTick by remember { mutableIntStateOf(0) }
    val start = remember { nowSec() }
    val tick by rememberFrameLoop { dt ->
        if (isDemo || !world.playing) return@rememberFrameLoop
        world.timeLeft = max(0.0, world.timeLimit - (nowSec() - start))
        if (world.timeLeft <= 0) { world.crash(); return@rememberFrameLoop }
        world.step(dt)
    }

    // Demo autopilot (tuned on iOS): tilt toward a capped horizontal-speed target, burn whenever the
    // descent beats an altitude-scaled limit, flare upright near the pad; every press held ≥ 8 frames.
    LaunchedEffect(Unit) {
        if (!isDemo) return@LaunchedEffect
        val dt = 1.0 / 60.0
        while (isActive) {
            world.demoSetup()
            delay(400)
            var frame = 0; var lastRot = -9; var lastThr = -9
            while (isActive && world.playing && frame < 900) {
                frame++
                val alt = world.padY - (world.y + SHIP_R)
                val dx = world.padCenter - world.x
                val vxDes = clamp(1.0 * dx, -0.2, 0.2)
                var angDes = clamp(5 * (vxDes - world.vx), -0.45, 0.45)
                if (alt < 0.1) angDes = if (abs(dx) < 0.06) clamp(5 * (0 - world.vx), -0.12, 0.12) else angDes * 0.5
                val e = angDes - world.angle
                val wantRot = if (e > 0.03) 1 else if (e < -0.03) -1 else 0
                if (wantRot != world.rotDir && frame - lastRot >= 8) { world.rotDir = wantRot; lastRot = frame }
                val vyDes = clamp(0.8 * alt + 0.15, 0.04, 0.25)
                val wantThr = world.vy > vyDes || (abs(world.angle) > 0.12 && world.vy > vyDes - 0.05)
                if (wantThr != world.thrusting && frame - lastThr >= 8) { world.thrusting = wantThr; lastThr = frame }
                world.step(dt)
                demoTick++
                delay(16)
            }
            world.rotDir = 0; world.thrusting = false
            val end = nowSec()
            while (isActive && nowSec() - end < 1.3) { demoTick++; delay(16) }
        }
    }

    val pal = palette(level)
    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .drawBehind { space(level) },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        tick; demoTick
        // Speed against the safe touchdown limit (the tick), and the fuel left.
        Row(Modifier.padding(top = if (isDemo) 6.dp else 0.dp), horizontalArrangement = Arrangement.spacedBy(if (isDemo) 14.dp else 22.dp)) {
            Gauge(Icons.Filled.Speed, min(1.0, world.speed / max(0.01, world.safeSpeed * 2)), 0.5,
                if (world.speed < world.safeSpeed) LLSafe else LLDanger, isDemo)
            val ff = world.fuel / max(0.01, world.fuelMax)
            Gauge(Icons.Filled.LocalGasStation, ff, null, if (ff < 0.25) LLDanger else LLAmber, isDemo)
        }
        if (!isDemo) {
            val f = world.timeLeft / world.timeLimit
            TimeBar(f, Modifier.fillMaxWidth().padding(horizontal = 60.dp).height(5.dp), fill = if (f < 0.3) LLDanger else gray(0.9), track = Color.White.op(0.14))
        }
        Canvas(
            Modifier.fillMaxWidth().weight(1f).clipToBounds().graphicsLayer {
                val t = nowSec() - world.shakeT0
                if (t in 0.0..0.35) translationX = (7 * density * sin(t / 0.35 * PI * 3) * (1 - t / 0.35)).toFloat()
            }
        ) {
            tick; demoTick
            val w = size.width.toDouble(); val h = size.height.toDouble()
            val now = nowSec()
            terrainArt(world, level)
            padLights(world.padCenter * w, world.padY * h, world.padW * w, now, world.landedAt != null)
            world.landedAt?.let { dust(world.x * w, (world.y + SHIP_R) * h, SHIP_R * h, now - it) }
            val ca = world.crashAt
            if (ca != null) debris(world.crashX * w, world.crashY * h, SHIP_R * h, now - ca)
            else lander(world.x * w, world.y * h, SHIP_R * h, world.angle, world.thrusting && world.fuel > 0, now)
        }
        // The regolith runs on under the console keys.
        Row(Modifier.fillMaxWidth().background(pal.fill1).padding(top = 4.dp, bottom = if (isDemo) 6.dp else 8.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally)) {
            val kw = if (isDemo) 64.dp else 74.dp; val kh = if (isDemo) 38.dp else 54.dp
            ConsoleKey(Icons.Filled.RotateLeft, false, kw, kh, isDemo && world.rotDir == -1, isDemo,
                { if (world.playing) world.rotDir = -1 }, { if (world.rotDir == -1) world.rotDir = 0 })
            ConsoleKey(Icons.Filled.LocalFireDepartment, true, if (isDemo) 96.dp else 110.dp, kh, isDemo && world.thrusting, isDemo,
                { if (world.playing) world.thrusting = true }, { world.thrusting = false })
            ConsoleKey(Icons.Filled.RotateRight, false, kw, kh, isDemo && world.rotDir == 1, isDemo,
                { if (world.playing) world.rotDir = 1 }, { if (world.rotDir == 1) world.rotDir = 0 })
        }
    }
}

/** Speed or fuel as an icon and a bar; the speed bar's tick is the safe touchdown limit. */
@Composable
private fun Gauge(icon: ImageVector, fraction: Double, mark: Double?, color: Color, small: Boolean) {
    val bw = if (small) 58.dp else 84.dp; val bh = if (small) 6.dp else 8.dp
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(if (small) 5.dp else 7.dp)) {
        Icon(icon, null, tint = color, modifier = Modifier.size(if (small) 13.dp else 18.dp))
        Canvas(Modifier.size(bw, bh)) {
            val w = size.width.toDouble(); val h = size.height.toDouble()
            rrect(0.0, 0.0, w, h, h / 2, Color.White.op(0.14))
            rrect(0.0, 0.0, w * clamp(fraction, 0.0, 1.0), h, h / 2, color)
            if (mark != null) rect(w * mark - density, -3.0 * density, 2.0 * density, h + 6 * density, Color.White)
        }
    }
}

/** Console keys: gunmetal rotate keys, an amber engine key. */
@Composable
private fun ConsoleKey(icon: ImageVector, wide: Boolean, w: Dp, h: Dp, lit: Boolean, isDemo: Boolean, onDown: () -> Unit, onUp: () -> Unit) {
    Box(
        Modifier.scale(if (lit) 0.92f else 1f).size(w, h).then(if (isDemo) Modifier else Modifier.pressDown(onDown = onDown, onUp = onUp)),
        contentAlignment = Alignment.Center
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val u = density.toDouble(); val bw = size.width.toDouble(); val bh = size.height.toDouble()
            val cols = if (wide) (if (lit) listOf(rgb(1.0, 0.95, 0.66), rgb(1.0, 0.68, 0.24)) else listOf(rgb(0.92, 0.58, 0.2), rgb(0.72, 0.36, 0.08)))
            else listOf(gray(if (lit) 0.46 else 0.3), gray(if (lit) 0.28 else 0.16))
            rrect(0.0, 0.0, bw, bh, 14 * u, vgrad(cols, 0.0, bh))
            rrectStroke(u, u, bw - 2 * u, bh - 2 * u, 13 * u, Color.Black.op(0.6), 2 * u)
            rrectStroke(3.6 * u, 3.6 * u, bw - 7.2 * u, bh - 7.2 * u, 10.4 * u, Color.White.op(if (lit) 0.9 else 0.16), 1.2 * u)
        }
        Icon(icon, null, tint = if (wide) rgb(0.25, 0.1, 0.02) else gray(if (lit) 1.0 else 0.88), modifier = Modifier.size(if (isDemo) 20.dp else 24.dp))
    }
}

// Vector lander art (after Atari's 1979 Lunar Lander; iOS LLArt).

private val LLSafe = rgb(0.36, 0.95, 0.52)
private val LLDanger = rgb(1.0, 0.33, 0.28)
private val LLAmber = rgb(1.0, 0.75, 0.32)

private fun hashD(n: Double): Double { val x = sin(n) * 43758.5453; return x - floor(x) }

private class LLPalette(val line: Color, val fill0: Color, val fill1: Color, val sky0: Color, val sky1: Color)

/** Moon grey (1–2) → Martian rust (3–5) → obsidian (6–7). */
private fun palette(level: Int) = when (min(max(level, 1), 7)) {
    1 -> LLPalette(rgb(0.93, 0.94, 0.98), rgb(0.21, 0.21, 0.25), rgb(0.09, 0.09, 0.11), rgb(0.0, 0.0, 0.02), rgb(0.03, 0.03, 0.07))
    2 -> LLPalette(rgb(0.90, 0.91, 0.96), rgb(0.23, 0.21, 0.25), rgb(0.10, 0.09, 0.11), rgb(0.0, 0.0, 0.02), rgb(0.04, 0.03, 0.08))
    3 -> LLPalette(rgb(1.0, 0.72, 0.52), rgb(0.36, 0.18, 0.12), rgb(0.15, 0.07, 0.05), rgb(0.02, 0.01, 0.02), rgb(0.14, 0.05, 0.04))
    4 -> LLPalette(rgb(1.0, 0.64, 0.44), rgb(0.38, 0.15, 0.10), rgb(0.16, 0.06, 0.04), rgb(0.02, 0.01, 0.02), rgb(0.18, 0.06, 0.04))
    5 -> LLPalette(rgb(1.0, 0.56, 0.40), rgb(0.33, 0.12, 0.10), rgb(0.13, 0.05, 0.04), rgb(0.02, 0.01, 0.02), rgb(0.16, 0.05, 0.06))
    6 -> LLPalette(rgb(0.78, 0.66, 1.0), rgb(0.14, 0.10, 0.21), rgb(0.05, 0.03, 0.08), rgb(0.01, 0.0, 0.03), rgb(0.06, 0.03, 0.12))
    else -> LLPalette(rgb(0.70, 0.58, 1.0), rgb(0.10, 0.07, 0.16), rgb(0.03, 0.02, 0.06), rgb(0.0, 0.0, 0.02), rgb(0.04, 0.02, 0.09))
}

private fun poly(vararg pts: Double) = polyPath(*pts)

/** The Apollo-style lander in a unit where 1 = shipR of the field height (footpad soles at y = 1). */
private fun DrawScope.lander(px: Double, py: Double, u: Double, angle: Double, flame: Boolean, now: Double) {
    val lw = 1.3 * density / u
    val ink = rgb(0.04, 0.04, 0.07)
    translate(px.f, py.f) { rotateRad(angle.f, Offset.Zero) { scale(u.f, u.f, Offset.Zero) {
        if (flame) {
            val k = (now * 24).toLong()
            val f = 0.5 + 0.5 * sin(k * 2.3)
            val len = 0.9 + 0.55 * f
            drawPath(poly(-0.24, 0.6, 0.24, 0.6, 0.0, 0.6 + len),
                vgrad(listOf(rgb(1.0, 0.95, 0.7), rgb(1.0, 0.55, 0.15), rgb(1.0, 0.3, 0.1, 0.0)), 0.6, 0.6 + len))
            fillPath(poly(-0.1, 0.6, 0.1, 0.6, 0.0, 0.6 + len * 0.55), Color.White.op(0.9))
        }
        // Legs and footpads.
        val legs = Path()
        for (s in listOf(-1.0, 1.0)) { legs.m(s * 0.5, 0.18); legs.l(s * 0.98, 0.9); legs.m(s * 0.52, 0.4); legs.l(s * 0.86, 0.72) }
        strokePath(legs, ink, 0.16); strokePath(legs, gray(0.78), 0.09)
        for (s in listOf(-1.0, 1.0)) {
            oval(s - 0.19, 0.87, 0.38, 0.13, gray(0.82))
            drawOval(ink, Offset((s - 0.19).f, 0.87f), androidx.compose.ui.geometry.Size(0.38f, 0.13f), style = Stroke(lw.f))
        }
        // Engine bell and the gold-foil descent stage.
        val bell = poly(-0.14, 0.4, 0.14, 0.4, 0.23, 0.61, -0.23, 0.61)
        fillPath(bell, gray(0.3)); strokePath(bell, ink, lw, StrokeCap.Butt, StrokeJoin.Miter)
        val stage = poly(-0.55, -0.02, 0.55, -0.02, 0.63, 0.1, 0.63, 0.34, 0.55, 0.43, -0.55, 0.43, -0.63, 0.34, -0.63, 0.1)
        drawPath(stage, lin(listOf(rgb(1.0, 0.88, 0.46), rgb(0.86, 0.62, 0.16), rgb(0.62, 0.42, 0.1)), -0.4, -0.02, 0.4, 0.43))
        val foil = Path()
        for (q in listOf(doubleArrayOf(-0.4, 0.06, -0.2, 0.3), doubleArrayOf(-0.05, 0.02, 0.1, 0.24), doubleArrayOf(0.25, 0.12, 0.46, 0.36), doubleArrayOf(-0.52, 0.28, -0.36, 0.4))) {
            foil.m(q[0], q[1]); foil.l(q[2], q[3])
        }
        strokePath(foil, rgb(0.55, 0.36, 0.08, 0.7), 0.04, StrokeCap.Butt)
        strokePath(stage, ink, lw, StrokeCap.Butt, StrokeJoin.Miter)
        // The ascent stage: silver cabin, triangular window, antenna dish, thruster quads.
        val cabin = poly(-0.46, -0.02, -0.53, -0.36, -0.34, -0.63, 0.1, -0.7, 0.41, -0.58, 0.51, -0.3, 0.46, -0.02)
        drawPath(cabin, lin(listOf(gray(0.95), gray(0.72)), -0.4, -0.6, 0.4, 0.0))
        rect(0.1, -0.38, 0.26, 0.22, gray(0.58))
        fillPath(poly(-0.3, -0.44, -0.06, -0.52, -0.14, -0.24), rgb(0.1, 0.13, 0.2))
        fillPath(poly(-0.24, -0.44, -0.13, -0.48, -0.17, -0.4), Color.White.op(0.55))
        strokePath(cabin, ink, lw, StrokeCap.Butt, StrokeJoin.Miter)
        val mast = Path(); mast.m(0.3, -0.6); mast.l(0.42, -0.86)
        val quads = Path()
        for ((qx, qy) in listOf(-0.56 to -0.3, 0.54 to -0.28)) { quads.m(qx - 0.1, qy); quads.l(qx + 0.1, qy); quads.m(qx, qy - 0.1); quads.l(qx, qy + 0.1) }
        strokePath(mast, gray(0.8), 0.06, StrokeCap.Butt); strokePath(quads, gray(0.85), 0.06, StrokeCap.Butt)
        oval(0.33, -0.97, 0.2, 0.14, gray(0.9))
        drawOval(ink, Offset(0.33f, -0.97f), androidx.compose.ui.geometry.Size(0.2f, 0.14f), style = Stroke((lw * 0.8).f))
    } } }
}

/** Landing lights at the pad's ends: blinking red / white, steady green once landed. */
private fun DrawScope.padLights(cx: Double, cy: Double, width: Double, now: Double, landed: Boolean) {
    val u = density.toDouble()
    val on = (now * 2.4).toLong() % 2 == 0L
    for ((i, x) in listOf(cx - width / 2, cx + width / 2).withIndex()) {
        val lit = landed || (on == (i == 0))
        val col = if (landed) LLSafe else if (lit) rgb(1.0, 0.3, 0.25) else gray(0.35)
        val py = cy - 3 * u
        if (lit) circle(x, py, 7 * u, radial(listOf(col.op(0.7), col.op(0.0)), x, py, 7 * u))
        circle(x, py, 2.5 * u, col)
    }
}

/** Two puffs of regolith kicked out from under the footpads. */
private fun DrawScope.dust(fx: Double, fy: Double, u: Double, age: Double) {
    if (age >= 1.1) return
    val fade = max(0.0, 0.5 * (1 - age / 1.1))
    for (s in listOf(-1.0, 1.0)) {
        val cx = fx + s * (1 + age * 1.8) * u
        val wd = (0.6 + age * 1.8) * u; val hg = (0.25 + age * 0.5) * u
        oval(cx - wd / 2, fy - hg, wd, hg, gray(0.8).op(fade))
    }
}

/** The crash: a flash, then the lander's pieces (gold and silver strokes) flung out and falling. */
private fun DrawScope.debris(px: Double, py: Double, u: Double, age: Double) {
    if (age < 0.45) {
        val r = (0.6 + age * 5) * u
        circle(px, py, r, radial(listOf(rgb(1.0, 0.95, 0.75, 0.9 * (1 - age / 0.45)), rgb(1.0, 0.5, 0.1, 0.0)), px, py, r))
    }
    if (age >= 1.4) return
    val fade = max(0.0, 1 - age / 1.4)
    for (i in 0 until 14) {
        val dir = i / 14.0 * 2 * PI + hashD(i * 3.1) * 0.5 - PI / 2
        val v = 2.4 + 2.6 * hashD(i * 7.7)
        val qx = px + cos(dir) * v * age * u; val qy = py + sin(dir) * v * age * u + 2.2 * age * age * u
        val spin = i * 0.8 + age * (4 + (i % 3) * 3)
        val len = u * (0.25 + 0.3 * hashD(i * 1.3))
        val col = if (i % 3 == 0) gray(0.9) else rgb(1.0, 0.78, 0.3)
        line(qx - cos(spin) * len, qy - sin(spin) * len, qx + cos(spin) * len, qy + sin(spin) * len, col.op(fade), max(1.2 * density, u * 0.1))
    }
}

/** The ground as a glowing vector ridge line over dark rock, with the flat pad lit up. */
private fun DrawScope.terrainArt(world: LanderWorld, level: Int) {
    val t = world.terrain
    if (t.isEmpty()) return
    val w = size.width.toDouble(); val h = size.height.toDouble(); val u = density.toDouble()
    val pal = palette(level)
    val ridge = Path(); ridge.m(t[0].x * w, t[0].y * h)
    for (pt in t) ridge.l(pt.x * w, pt.y * h)
    val ground = Path(); ground.addPath(ridge); ground.l(w, h); ground.l(t[0].x * w, h); ground.close()
    val top = (t.minOf { it.y }) * h
    drawPath(ground, vgrad(listOf(pal.fill0, pal.fill1), top, h))
    // Faint scan lines in the rock: the vector-display feel.
    clipPath(ground) {
        val lines = Path(); var y = top
        while (y < h) { lines.m(0.0, y); lines.l(w, y); y += 5 * u }
        strokePath(lines, pal.line.op(0.05), u, StrokeCap.Butt)
    }
    strokePath(ridge, pal.line.op(0.14), 7 * u)
    strokePath(ridge, pal.line.op(0.3), 3.5 * u)
    strokePath(ridge, pal.line, 1.5 * u)
    val px0 = (world.padCenter - world.padW / 2) * w; val px1 = (world.padCenter + world.padW / 2) * w; val py = world.padY * h
    val padCol = rgb(1.0, 0.92, 0.55)
    line(px0, py, px1, py, padCol.op(0.25), 10 * u)
    line(px0, py, px1, py, padCol, 3.5 * u)
    val posts = Path()
    for (x in listOf(px0 + 2 * u, px1 - 2 * u)) { posts.m(x, py); posts.l(x, py + 7 * u) }
    strokePath(posts, padCol.op(0.8), 1.5 * u, StrokeCap.Butt)
}

/** Deep space over the whole card: stars, and each world's sky — Earth, Mars's moons, a ringed giant. */
private fun DrawScope.space(level: Int) {
    val w = size.width.toDouble(); val h = size.height.toDouble(); val u = density.toDouble()
    val pal = palette(level)
    rect(0.0, 0.0, w, h, vgrad(listOf(pal.sky0, pal.sky1), 0.0, h))
    for (i in 0 until 80) {
        val x = hashD(i * 12.99) * w; val y = hashD(i * 78.23) * h * 0.75
        val d = (0.8 + hashD(i * 3.3) * 1.4) * u
        if (i % 9 == 0) oval(x, y, d + 0.8 * u, d + 0.8 * u, Color.White.op(0.95)) else oval(x, y, d, d, Color.White.op(0.55))
    }
    val m = min(w, h)
    when (min(max(level, 1), 7)) {
        1, 2 -> {
            // Earth, half lit.
            val r = m * 0.075; val cx = w * 0.8; val cy = h * 0.2
            circle(cx, cy, r * 1.25, Brush.radialGradient(0f to Color.Transparent, 0.72f to rgb(0.4, 0.7, 1.0, 0.3), 1f to Color.Transparent,
                center = Offset(cx.f, cy.f), radius = (r * 1.25).f))
            circle(cx, cy, r, rgb(0.18, 0.42, 0.82))
            val disc = Path().apply { addOval(androidx.compose.ui.geometry.Rect((cx - r).f, (cy - r).f, (cx + r).f, (cy + r).f)) }
            clipPath(disc) {
                oval(cx - r * 0.6, cy - r * 0.55, r * 0.7, r * 0.5, rgb(0.32, 0.55, 0.3))
                oval(cx + r * 0.05, cy + r * 0.05, r * 0.5, r * 0.7, rgb(0.32, 0.55, 0.3))
                oval(cx - r * 0.9, cy - r * 0.15, r * 1.1, r * 0.22, Color.White.op(0.8))
                oval(cx - r * 0.2, cy - r * 0.8, r * 0.9, r * 0.2, Color.White.op(0.8))
                oval(cx - r * 0.35, cy - r * 1.1, r * 2.2, r * 2.3, Color.Black.op(0.62))
            }
        }
        3, 4, 5 -> {
            // Phobos and Deimos, and a dusty glow over the horizon.
            rect(0.0, h * 0.45, w, h * 0.55, vgrad(listOf(Color.Transparent, rgb(0.6, 0.25, 0.12, 0.22)), h * 0.45, h * 0.8))
            val r = m * 0.032; val cx = w * 0.78; val cy = h * 0.17
            oval(cx - r * 1.2, cy - r * 0.85, r * 2.4, r * 1.7, rgb(0.62, 0.54, 0.48))
            oval(cx - r * 0.3, cy - r * 0.9, r * 1.6, r * 1.8, Color.Black.op(0.45))
            oval(w * 0.26, h * 0.1, m * 0.022, m * 0.02, rgb(0.75, 0.68, 0.6))
        }
        else -> {
            // A ringed giant and a violet haze.
            val r = m * 0.11; val cx = w * 0.2; val cy = h * 0.15
            val k = (1 / 2.2).toFloat()
            drawOval(Brush.radialGradient(0f to Color.Transparent, k to rgb(0.5, 0.3, 0.9, 0.18), 1f to Color.Transparent, center = Offset(cx.f, cy.f), radius = (r * 2.2).f),
                Offset((cx - r * 2.2).f, (cy - r * 1.6).f), androidx.compose.ui.geometry.Size((r * 4.4).f, (r * 3.2).f))
            ellipseStroke(cx, cy, r * 1.9, r * 0.38, rgb(0.8, 0.7, 1.0, 0.5), 2 * u)
            circle(cx, cy, r, vgrad(listOf(rgb(0.62, 0.46, 0.9), rgb(0.34, 0.2, 0.56)), cy - r, cy + r))
            val disc = Path().apply { addOval(androidx.compose.ui.geometry.Rect((cx - r).f, (cy - r).f, (cx + r).f, (cy + r).f)) }
            clipPath(disc) {
                for (b in 0 until 4) rect(cx - r, cy - r * 0.7 + b * r * 0.42, r * 2, r * 0.12, Color.White.op(0.12))
                oval(cx - r * 0.2, cy - r * 1.2, r * 2.2, r * 2.4, Color.Black.op(0.4))
            }
            // The near half of the ring passes in front of the planet.
            val front = Path()
            for (s in 0..32) {
                val a = s / 32.0 * PI
                val x = cx + cos(a) * r * 1.9; val y = cy + sin(a) * r * 0.38
                if (s == 0) front.m(x, y) else front.l(x, y)
            }
            strokePath(front, rgb(0.86, 0.78, 1.0, 0.8), 2.5 * u, StrokeCap.Butt)
        }
    }
}
