package com.gogs.bananagame.games.parkking

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.background
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
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.PathOperation
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Reflex — Park King (iOS ParkingGame.swift, id "parking"): the car creeps on its own; turn the
 * wheel, flip REVERSE, tap BRAKE, and come to rest wholly inside the marked bay before time's up.
 */
object ParkKingGame {
    val definition = GameDefinition(
        id = "parking",
        title = "Park King",
        genre = Genre.REFLEX,
        locksFeed = true,
        manual = GameManual(
            bullets = listOf(
                "Your car creeps forward on its own. Turn the wheel to aim.",
                "Flip REVERSE to back up, and tap BRAKE to stop and line up a turn.",
                "Come to rest with the whole car inside the marked spot to win.",
                "Hit a wall or a parked car, or run out of time, and you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Xe của bạn tự bò về phía trước. Xoay vô lăng để nhắm hướng.",
                "Bật LÙI để đi lùi, và chạm PHANH để dừng và canh một cú rẽ.",
                "Dừng lại với cả xe nằm trọn trong ô đã đánh dấu để thắng.",
                "Đâm vào tường hay xe đang đỗ, hoặc hết giờ, sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> ParkKingView(level, onWin, onFail) }
    )
}

/** A rect in field fractions (x = fraction of width, y = fraction of height). */
private data class FR(val x: Double, val y: Double, val w: Double, val h: Double) {
    val maxX get() = x + w
    val maxY get() = y + h
    val midX get() = x + w / 2
    fun inset(dx: Double, dy: Double) = FR(x + dx, y + dy, w - 2 * dx, h - 2 * dy)
    fun contains(p: P) = p.x >= x && p.x <= maxX && p.y >= y && p.y <= maxY
    fun intersects(o: FR) = x < o.maxX && o.x < maxX && y < o.maxY && o.y < maxY
    fun corners() = listOf(P(x, y), P(maxX, y), P(maxX, maxY), P(x, maxY))
}

private const val CAR_L = 0.20
private const val CAR_W = 0.10
private const val FIELD_TOP = 0.06
private const val FIELD_BOTTOM = 0.74

private class ParkWorld(val level: Int) {
    val creep = 0.052
    val reverseCreep = 0.044
    val turnRate = 2.4
    val obstacleCount = level - 1
    val timeLimit = listOf(44.0, 41.0, 39.0, 37.0, 44.0, 48.0, 52.0)[min(level, 7) - 1]
    private val padLevel = max(level, 5)
    val spotPadW = max(0.010, 0.036 - padLevel * 0.0040)
    val spotPadL = max(0.014, 0.050 - padLevel * 0.0060)
    val neighborGap = max(0.012, 0.032 - level * 0.0028)

    var playing = true
    var px = 0.5; var py = 0.58
    var heading = -PI / 2
    var steer = 0.0
    var reverse = false
    var braking = false
    var spot = FR(0.4, 0.12, 0.2, 0.24)
    var obstacles = listOf<FR>()
    var timeLeft = timeLimit
    /** Width ÷ height: the car is drawn scaled by width on both axes, so y offsets convert by it. */
    var aspect = 0.5
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    fun buildLot(spotX: Double? = null) {
        val carYExtent = CAR_L * aspect
        val sw = CAR_W + spotPadW * 2
        val sh = carYExtent + spotPadL * 2
        val sx = spotX ?: rnd(0.24, 0.76)
        val cy = FIELD_TOP + sh / 2 + 0.04
        val s = FR(sx - sw / 2, cy - sh / 2, sw, sh)
        spot = s
        val obs = mutableListOf<FR>()
        if (obstacleCount >= 1) obs.add(FR(s.x - sw - neighborGap, s.y, sw, sh))
        if (obstacleCount >= 2) obs.add(FR(s.maxX + neighborGap, s.y, sw, sh))
        val start = FR(0.5 - CAR_W / 2, 0.63 - carYExtent / 2, CAR_W, carYExtent).inset(-0.05, -0.05)
        var tries = 0
        while (obs.size < obstacleCount && tries < 400) {
            tries++
            val r = FR(rnd(0.16, 0.68), rnd(0.30, 0.46), sw, sh)
            if (r.inset(-0.04, -0.04).intersects(s)) continue
            if (obs.any { it.inset(-0.06, -0.05).intersects(r) }) continue
            if (r.intersects(start)) continue
            obs.add(r)
        }
        obstacles = obs
    }

    fun begin() {
        playing = true; px = 0.5; py = 0.63; heading = -PI / 2
        steer = 0.0; reverse = false; braking = false
        buildLot(); timeLeft = timeLimit
    }

    fun step(dt: Double) {
        if (!playing) return
        val v = if (braking) 0.0 else if (reverse) -reverseCreep else creep
        if (v != 0.0) heading += steer * turnRate * dt * (if (v > 0) 1 else -1)
        val nx = px + cos(heading) * v * dt; val ny = py + sin(heading) * v * dt
        // Soft outer walls: the field edge just blocks the car.
        if (carCorners(nx, ny).none { it.x < 0.01 || it.x > 0.99 || it.y < FIELD_TOP || it.y > FIELD_BOTTOM }) { px = nx; py = ny }
        val corners = carCorners(px, py)
        val touchTol = 0.012
        for (ob in obstacles) {
            val hit = ob.inset(touchTol, touchTol)
            if (corners.any { hit.contains(it) }) { fail(); return }
            for (oc in hit.corners()) if (pointInPolygon(oc, corners)) { fail(); return }
        }
        if (corners.all { spot.contains(it) }) win()
    }

    fun carCorners(x: Double, y: Double): List<P> {
        val fx = cos(heading); val fy = sin(heading)
        val sx = -fy; val sy = fx
        val hl = CAR_L / 2; val hw = CAR_W / 2
        return listOf(hl to hw, hl to -hw, -hl to -hw, -hl to hw).map { (a, b) -> P(x + fx * a + sx * b, y + (fy * a + sy * b) * aspect) }
    }

    private fun pointInPolygon(pt: P, poly: List<P>): Boolean {
        var inside = false
        var j = poly.size - 1
        for (i in poly.indices) {
            val a = poly[i]; val b = poly[j]
            if ((a.y > pt.y) != (b.y > pt.y) && pt.x < (b.x - a.x) * (pt.y - a.y) / (b.y - a.y) + a.x) inside = !inside
            j = i
        }
        return inside
    }

    fun win() { if (!playing) return; playing = false; Haptics.tap(); SoundManager.tap(); onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }
}

private fun angleDelta(a: Double, b: Double): Double {
    var d = a - b
    while (d > PI) d -= 2 * PI
    while (d < -PI) d += 2 * PI
    return d
}

@Composable
private fun ParkKingView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { ParkWorld(level) }
    world.onWin = onWin; world.onFail = onFail
    var started by remember { androidx.compose.runtime.mutableStateOf(false) }
    var demoTick by remember { mutableIntStateOf(0) }
    val tm = rememberTextMeasurer()
    val handP = rememberHand()
    var start by remember { androidx.compose.runtime.mutableDoubleStateOf(0.0) }
    val tick by rememberFrameLoop(running = started && !isDemo) { dt ->
        if (!world.playing) return@rememberFrameLoop
        world.timeLeft = max(0.0, world.timeLimit - (nowSec() - start))
        if (world.timeLeft <= 0) { world.fail(); return@rememberFrameLoop }
        world.step(dt)
    }

    GameBox(Modifier.padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))) { w, h ->
        LaunchedEffect(Unit) {
            world.aspect = w / h
            if (!isDemo) { world.begin(); start = nowSec(); started = true; return@LaunchedEffect }
            val dt = 1.0 / 60.0
            while (isActive) {
                world.playing = true; world.px = 0.5; world.py = 0.58; world.heading = -PI / 2
                world.steer = 0.0; world.reverse = false; world.braking = false
                world.buildLot(0.62); world.timeLeft = world.timeLimit
                started = true; demoTick++
                delay(600)
                var t = 0.0
                while (isActive && world.playing && t < 14) {
                    t += dt
                    val desired = -PI / 2 + clamp(16 * (world.spot.midX - world.px), -0.6, 0.6)
                    val want = clamp((desired - world.heading) * 5, -1.0, 1.0)
                    world.steer += clamp(want - world.steer, -3 * dt, 3 * dt)
                    world.step(dt)
                    demoTick++
                    delay(16)
                }
                world.steer = 0.0; demoTick++
                delay(1300)
            }
        }
        if (!started) return@GameBox
        Box(Modifier.fillMaxSize()) {
            Canvas(Modifier.fillMaxSize()) {
                tick; demoTick
                parkingLot(tm, world.spot, world.obstacles)
                if (!isDemo) meter(world.timeLeft / world.timeLimit)
                val cw = CAR_L * size.width; val ch = CAR_W * size.width
                translate((world.px * size.width).f, (world.py * size.height).f) {
                    rotate((world.heading * 180 / PI).f, Offset.Zero) {
                        car(-cw / 2, -ch / 2, cw, ch, rgb(1.0, 0.84, 0.2), noseUp = false, brake = world.braking, reverse = world.reverse, stripes = true)
                    }
                }
            }
            // The steering wheel: drag round its centre; it turns further than the finger for a clear lock.
            val r = w * (if (isDemo) 0.095 else 0.13)
            var lastAngle by remember { androidx.compose.runtime.mutableStateOf<Double?>(null) }
            val dens = androidx.compose.ui.platform.LocalDensity.current.density
            Box(
                Modifier.centerAt(if (isDemo) 0.2 else 0.22, 0.87).size((r * 2 / dens).dp)
                    .then(if (isDemo) Modifier else Modifier.touchDrag(
                        onMove = { _, n ->
                            if (!world.playing) return@touchDrag
                            val a = atan2(n.y - r, n.x - r)
                            lastAngle?.let { world.steer = clamp(world.steer + angleDelta(a, it) / 0.9, -1.0, 1.0) }
                            lastAngle = a
                        },
                        onEnd = { _, _ -> lastAngle = null }
                    ))
            ) {
                Canvas(Modifier.fillMaxSize().rotate((world.steer * 2.6 * 180 / PI).toFloat().also { tick; demoTick })) {
                    wheel()
                    if (isDemo) { val s = r * 0.7; hand(handP, size.width / 2 + r * 0.18 - s * 0.3, size.height / 2 - r * 0.72 - s * 0.2, s) }
                }
            }
            tick; demoTick
            DashButton(Modifier.centerAt(if (isDemo) 0.84 else 0.84, if (isDemo) 0.87 else 0.88), isDemo, !isDemo,
                if (world.reverse) L("REVERSE", "LÙI") else L("DRIVE", "TIẾN"),
                if (world.reverse) rgb(1.0, 0.85, 0.4) else Color.White.op(0.85),
                onClick = { if (world.playing) { world.reverse = !world.reverse; SoundManager.tap(); Haptics.tap() } }) {
                Canvas(Modifier.size(if (isDemo) 44.dp else 56.dp, if (isDemo) 40.dp else 56.dp)) { gearLever(tm, world.reverse) }
            }
            DashButton(Modifier.centerAt(if (isDemo) 0.62 else 0.6, if (isDemo) 0.87 else 0.88), isDemo, !isDemo,
                if (world.braking) L("STOPPED", "ĐÃ DỪNG") else L("BRAKE", "PHANH"),
                if (world.braking) rgb(1.0, 0.4, 0.35) else Color.White.op(0.85),
                onClick = { if (world.playing) { world.braking = !world.braking; SoundManager.tap(); Haptics.tap() } }) {
                Canvas(Modifier.size(if (isDemo) 40.dp else 50.dp, if (isDemo) 40.dp else 56.dp)) { brakePedal(world.braking) }
            }
        }
    }
}

/** A dashboard control: art over a label, a small dip when pressed. */
@Composable
private fun DashButton(modifier: Modifier, isDemo: Boolean, enabled: Boolean, label: String, labelColor: Color, onClick: () -> Unit,
                       art: @Composable () -> Unit) {
    val src = remember { MutableInteractionSource() }
    val pressed by src.collectIsPressedAsState()
    Box(modifier) {
        Column(
            Modifier.size(if (isDemo) 70.dp else 96.dp, if (isDemo) 58.dp else 84.dp).scale(if (pressed) 0.94f else 1f)
                .clickable(src, null, enabled = enabled, onClick = onClick),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterVertically)
        ) {
            art()
            Text(label, style = ts(if (isDemo) 10.0 else 12.0, FontWeight.Black, labelColor))
        }
    }
}

// Parking-lot art (iOS ParkArt / ParkingLot / CoupeArt / WheelArt / GearLever / BrakePedal).

private val paint = rgb(0.96, 0.96, 0.92)
private val carColours = listOf(rgb(0.85, 0.2, 0.2), rgb(0.2, 0.45, 0.85), rgb(0.92, 0.92, 0.94), rgb(0.18, 0.2, 0.24),
    rgb(0.25, 0.65, 0.4), rgb(0.62, 0.64, 0.68), rgb(0.95, 0.55, 0.15))

private fun hash(n: Double): Double { val v = sin(n * 12.9898) * 43758.5453; return v - kotlin.math.floor(v) }

/** The level clock as a parking-meter strip across the top. */
private fun DrawScope.meter(frac: Double) {
    val u = density.toDouble()
    val w = size.width - 96 * u; val x0 = 48 * u; val cy = size.height * FIELD_TOP * 0.5
    rrect(x0, cy - 8 * u, 16 * u, 16 * u, 3 * u, rgb(0.12, 0.4, 0.85))
    // "P" glyph drawn as strokes to avoid a text measurer here.
    val p = Path(); p.m(x0 + 5.5 * u, cy + 5 * u); p.l(x0 + 5.5 * u, cy - 5 * u); p.l(x0 + 9 * u, cy - 5 * u)
    p.q(x0 + 12 * u, cy - 5 * u, x0 + 12 * u, cy - 2 * u); p.q(x0 + 12 * u, cy + 1 * u, x0 + 9 * u, cy + 1 * u); p.l(x0 + 5.5 * u, cy + 1 * u)
    strokePath(p, Color.White, 2.2 * u)
    val bx = x0 + 22 * u; val bw = w - 22 * u
    rrect(bx, cy - 4 * u, bw, 8 * u, 4 * u, Color.Black.op(0.45))
    val f = clamp(frac, 0.0, 1.0)
    if (f > 0) rrect(bx, cy - 4 * u, bw * f, 8 * u, 4 * u, if (frac < 0.3) rgb(0.95, 0.3, 0.25) else rgb(0.35, 0.85, 0.45))
}

/** A top-down car filling (x, y, w, h); points right unless `noseUp`. */
private fun DrawScope.car(x: Double, y: Double, w: Double, h: Double, color: Color, noseUp: Boolean,
                          brake: Boolean = false, reverse: Boolean = false, stripes: Boolean = false) {
    val len = if (noseUp) h else w; val wid = if (noseUp) w else h
    translate((x + w / 2).f, (y + h / 2).f) {
        rotate(if (noseUp) -90f else 0f, Offset.Zero) {
            val shape = Path().apply {
                addRoundRect(androidx.compose.ui.geometry.RoundRect((-len / 2).f, (-wid / 2).f, (len / 2).f, (wid / 2).f, (len * 0.16).f, (wid * 0.32).f))
            }
            translate((wid * 0.06).f, (wid * 0.1).f) { drawPath(shape, Color.Black.op(0.35)) }
            drawPath(shape, vgrad(listOf(color.lit(0.25), color, color.shade(0.25)), -wid / 2, wid / 2))
            drawPath(shape, color.shade(0.55), style = Stroke(density))
            if (stripes) clipPath(shape) {
                for (s in listOf(-1.0, 1.0)) rect(-len * 0.47, s * wid * 0.07 - wid * 0.045, len * 0.94, wid * 0.09, rgb(0.12, 0.12, 0.14, 0.85))
            }
            val glass = rgb(0.16, 0.2, 0.28)
            rrect(len * 0.08, -wid * 0.36, len * 0.17, wid * 0.72, wid * 0.1, glass)
            rrect(-len * 0.24, -wid * 0.34, len * 0.12, wid * 0.68, wid * 0.08, glass)
            rrect(-len * 0.12, -wid * 0.36, len * 0.2, wid * 0.72, wid * 0.1, color.lit(0.1))
            for (s in listOf(-1.0, 1.0)) oval(len * 0.14, s * wid * 0.5 - wid * 0.07, len * 0.07, wid * 0.14, color.shade(0.2))
            val cr = 1.5 * density
            for (s in listOf(-1.0, 1.0)) {
                rrect(len * 0.43, s * wid * 0.3 - wid * 0.08, len * 0.06, wid * 0.16, cr, rgb(1.0, 0.97, 0.8))
                val tx = -len * 0.49; val ty = s * wid * 0.3 - wid * 0.08; val tw = len * 0.05; val th = wid * 0.16
                rrect(tx, ty, tw, th, cr, if (brake) rgb(1.0, 0.15, 0.1) else rgb(0.6, 0.08, 0.08))
                if (brake) oval(tx - len * 0.06, ty - wid * 0.1, tw + len * 0.12, th + wid * 0.2,
                    rgb(1.0, 0.2, 0.1, 0.35))
                if (reverse) rrect(-len * 0.49, s * wid * 0.12 - wid * 0.05, len * 0.04, wid * 0.1, density.toDouble(), Color.White)
            }
        }
    }
}

/** Asphalt, hazard-striped curbs, painted bays, the glowing target bay, parked cars and the dashboard. */
private fun DrawScope.parkingLot(tm: TextMeasurer, spot: FR, obstacles: List<FR>) {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    fun rx(r: FR) = doubleArrayOf(r.x * w, r.y * h, r.w * w, r.h * h)
    drawRect(rgb(0.62, 0.62, 0.6))
    val fx = w * 0.01; val fy = FIELD_TOP * h; val fw = w * 0.98; val fh = (FIELD_BOTTOM - FIELD_TOP) * h
    rect(fx, fy, fw, fh, vgrad(listOf(rgb(0.25, 0.26, 0.29), rgb(0.2, 0.21, 0.24)), fy, fy + fh))
    val grit = Path()
    for (k in 0 until 260) {
        val gx = fx + hash(k * 1.37) * fw; val gy = fy + hash(k * 2.71 + 3) * fh
        grit.addOval(androidx.compose.ui.geometry.Rect(gx.f, gy.f, (gx + 1.4 * u).f, (gy + 1.4 * u).f))
    }
    fillPath(grit, Color.White.op(0.07))
    for (k in 0 until 4) {
        val ox = fx + hash(k * 5.3) * fw; val oy = fy + fh * (0.35 + hash(k * 7.9) * 0.55)
        oval(ox, oy, (24 + hash(k.toDouble()) * 20) * u, (12 + hash(k + 1.0) * 8) * u, Color.Black.op(0.22))
    }
    // Curb with hazard stripes around the field.
    val curb = 5 * u
    val outer = Path().apply { addRect(androidx.compose.ui.geometry.Rect((fx - curb).f, (fy - curb).f, (fx + fw + curb).f, (fy + fh + curb).f)) }
    val inner = Path().apply { addRect(androidx.compose.ui.geometry.Rect(fx.f, fy.f, (fx + fw).f, (fy + fh).f)) }
    val ring = Path().apply { op(outer, inner, PathOperation.Difference) }
    clipPath(ring) {
        drawPath(ring, rgb(0.95, 0.78, 0.1))
        val diag = Path()
        var x = -h
        while (x < w + h) { diag.m(x, 0.0); diag.l(x + h, h); x += 14 * u }
        strokePath(diag, rgb(0.12, 0.12, 0.12), 6 * u, StrokeCap.Butt)
    }
    // Painted bays across the top row, keyed to the target bay.
    val sp = rx(spot)
    val pitch = obstacles.firstOrNull()?.let { abs(rx(it)[0] - sp[0]) } ?: (sp[2] * 1.35)
    val gap = max(4 * u, pitch - sp[2])
    val bays = Path()
    var bx = sp[0] - gap / 2
    while (bx > fx) { bays.m(bx, sp[1] - 4 * u); bays.l(bx, sp[1] + sp[3] + 4 * u); bx -= pitch }
    bx = sp[0] + sp[2] + gap / 2
    while (bx < fx + fw) { bays.m(bx, sp[1] - 4 * u); bays.l(bx, sp[1] + sp[3] + 4 * u); bx += pitch }
    bays.m(fx, sp[1] - 4 * u); bays.l(fx + fw, sp[1] - 4 * u)
    strokePath(bays, paint.op(0.75), 2.5 * u, StrokeCap.Butt)
    rect(sp[0], sp[1], sp[2], sp[3], rgb(0.3, 0.9, 0.45, 0.18))
    text(tm, "P", sp[0] + sp[2] / 2, sp[1] + sp[3] / 2, sp[2] * 0.62, paint.op(0.35), FontWeight.Black)
    rrectStroke(sp[0], sp[1], sp[2], sp[3], 3 * u, rgb(1.0, 0.85, 0.2), 3 * u)
    obstacles.forEachIndexed { i, ob ->
        val r = rx(ob)
        car(r[0] + r[2] * 0.08, r[1] + r[3] * 0.05, r[2] * 0.84, r[3] * 0.9, carColours[i % carColours.size], noseUp = true)
    }
    // Dashboard across the bottom.
    val dashTop = FIELD_BOTTOM * h + curb + 4 * u
    rrect(0.0, dashTop, w, h - dashTop, 18 * u, vgrad(listOf(rgb(0.2, 0.2, 0.23), rgb(0.08, 0.08, 0.1)), dashTop, h))
    drawLine(rgb(0.7, 0.55, 0.3, 0.6), off(12 * u, dashTop + 7 * u), off(w - 12 * u, dashTop + 7 * u), u.f,
        pathEffect = PathEffect.dashPathEffect(floatArrayOf((4 * u).f, (3 * u).f)))
}

/** A leather steering wheel with three silver spokes and a banana on the hub. */
private fun DrawScope.wheel() {
    val u = density.toDouble()
    val cx = size.width / 2.0; val cy = size.height / 2.0; val r = min(size.width, size.height) / 2.0
    val rim = r * 0.18
    circle(cx, cy + 3 * u, r, Color.Black.op(0.35))
    val spokes = Path()
    for (a in listOf(-90.0, 30.0, 150.0)) { spokes.m(cx, cy); spokes.l(cx + cos(deg(a)) * (r - rim * 0.5), cy + sin(deg(a)) * (r - rim * 0.5)) }
    strokePath(spokes, gray(0.2), r * 0.22)
    strokePath(spokes, gray(0.72), r * 0.14)
    circleStroke(cx, cy, r - rim / 2, rgb(0.12, 0.1, 0.1), rim)
    drawCircle(rgb(0.24, 0.2, 0.19), (r - rim / 2).f, off(cx, cy),
        style = Stroke((rim * 0.3).f, pathEffect = PathEffect.dashPathEffect(floatArrayOf((2 * u).f, (3 * u).f))))
    rrect(cx - rim * 0.35, cy - r, rim * 0.7, rim, 2 * u, rgb(1.0, 0.82, 0.2))
    circle(cx, cy, r * 0.3, gray(0.16))
    FruitArt.draw(this, FruitKind.BANANA, cx, cy + r * 0.02, r * 0.17)
}

/** The D / R gear lever: the knob sits on D, or pulled back to R. */
private fun DrawScope.gearLever(tm: TextMeasurer, reverse: Boolean) {
    val w = size.width.toDouble(); val h = size.height.toDouble()
    rrect(w * 0.1, 0.0, w * 0.8, h, 8 * density.toDouble(), gray(0.12))
    rrect(w * 0.44, h * 0.14, w * 0.12, h * 0.72, 3 * density.toDouble(), Color.Black)
    for ((label, y, on) in listOf(Triple("D", h * 0.2, !reverse), Triple("R", h * 0.8, reverse)))
        text(tm, label, w * 0.25, y, h * 0.2, if (on) rgb(1.0, 0.85, 0.4) else gray(0.5), FontWeight.Black)
    val ky = if (reverse) h * 0.78 else h * 0.22
    val kr = h * 0.17
    circle(w * 0.5, ky + 2 * density, kr, Color.Black.op(0.5))
    circle(w * 0.5, ky, kr, radial(listOf(gray(0.75), gray(0.25)), w * 0.5 - kr * 0.4, ky - kr * 0.5, kr * 1.4))
}

/** The brake pedal: grooved rubber, pushed down while you're stopped. */
private fun DrawScope.brakePedal(pressed: Boolean) {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    val px = w * 0.12; val py = if (pressed) h * 0.2 else h * 0.06; val pw = w * 0.76; val ph = h * (if (pressed) 0.72 else 0.78)
    rrect(px, py + 3 * u, pw, ph, 6 * u, Color.Black.op(0.5))
    rrect(px, py, pw, ph, 6 * u, vgrad(if (pressed) listOf(gray(0.2), gray(0.28)) else listOf(gray(0.38), gray(0.2)), py, py + ph))
    val grooves = Path()
    var y = py + ph * 0.18
    while (y < py + ph - 3 * u) { grooves.m(px + 5 * u, y); grooves.l(px + pw - 5 * u, y); y += ph * 0.16 }
    strokePath(grooves, Color.Black.op(0.55), 2 * u, StrokeCap.Butt)
    if (pressed) rrectStroke(px, py, pw, ph, 6 * u, rgb(1.0, 0.3, 0.25), 2 * u)
}
