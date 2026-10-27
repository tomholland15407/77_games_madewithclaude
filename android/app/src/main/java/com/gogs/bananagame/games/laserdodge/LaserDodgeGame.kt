package com.gogs.bananagame.games.laserdodge

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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.foundation.layout.size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Reflex — Laser Dodge (iOS LaserDodgeGame.swift): wall emitters sweep laser beams that stop at
 * solid plinths; steer the banana with the floating joystick and survive until the bar empties.
 */
object LaserDodgeGame {
    val definition = GameDefinition(
        id = "laser-dodge",
        title = "Laser Dodge",
        genre = Genre.REFLEX,
        locksFeed = true,
        manual = GameManual(
            bullets = listOf(
                "Steer the banana with the joystick; only the bright center dot is your hitbox.",
                "Wall emitters sweep lethal laser beams across the room.",
                "Solid blocks stop beams and cast moving safe shadows — duck behind them.",
                "Survive until the bar empties; one touch and you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Lái quả chuối bằng cần điều khiển; chỉ chấm sáng ở giữa mới là vùng trúng đòn.",
                "Các bộ phát trên tường quét những tia laser chết người khắp phòng.",
                "Các khối đặc chặn tia và tạo bóng an toàn di động — hãy nấp sau chúng.",
                "Sống sót đến khi thanh cạn; chạm một lần là về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> LaserDodgeView(level, onWin, onFail) }
    )
}

private class Emitter(val pos: P, var angle: Double, val vel: Double)
private class Box2(val x: Double, val y: Double, val w: Double, val h: Double) {
    val maxX get() = x + w
    val maxY get() = y + h
    fun contains(p: P) = p.x >= x && p.x <= maxX && p.y >= y && p.y <= maxY
    fun inset(d: Double) = Box2(x + d, y + d, w - 2 * d, h - 2 * d)
    fun intersects(o: Box2) = x < o.maxX && o.x < maxX && y < o.maxY && o.y < maxY
}

private val demoWander = listOf(P(0.5, 0.5), P(0.3, 0.42), P(0.52, 0.3), P(0.78, 0.5), P(0.45, 0.82), P(0.5, 0.55))

private class LaserWorld(level: Int) {
    private val li = min(level, 7) - 1
    val surviveTime = listOf(9.0, 10.0, 12.0, 13.0, 15.0, 17.0, 20.0)[li]
    val emitterCount = listOf(3, 4, 5, 6, 7, 8, 10)[li]
    val blockCount = listOf(4, 4, 5, 5, 6, 6, 7)[li]
    val spinSpeed = listOf(0.5, 0.65, 0.8, 1.0, 1.2, 1.4, 1.7)[li]
    val thickFrac = listOf(0.016, 0.018, 0.020, 0.022, 0.024, 0.027, 0.030)[li]
    val moveSpeed = 1.5

    var playing = true
    var w = 0.0; var h = 0.0
    var player = P.zero
    var emitters = listOf<Emitter>()
    var blocks = listOf<Box2>()
    var stick = P.zero
    var timeLeft = surviveTime
    var grace = 0.0
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    fun setup() {
        val minD = min(w, h)
        player = P(w / 2, h / 2)
        val bs = mutableListOf<Box2>()
        var tries = 0
        while (bs.size < blockCount && tries < 300) {
            tries++
            val bw = rnd(minD * 0.12, minD * 0.22); val bh = rnd(minD * 0.12, minD * 0.22)
            val r = Box2(rnd(w * 0.10, w * 0.90 - bw), rnd(h * 0.10, h * 0.90 - bh), bw, bh)
            if (r.inset(-minD * 0.10).contains(player)) continue
            if (bs.any { it.inset(-minD * 0.05).intersects(r) }) continue
            bs.add(r)
        }
        blocks = bs
        val es = mutableListOf<Emitter>()
        tries = 0
        while (es.size < emitterCount && tries < 400) {
            tries++
            val p = when (rndInt(0..3)) {
                0 -> P(rnd(w * 0.1, w * 0.9), h * 0.04)
                1 -> P(rnd(w * 0.1, w * 0.9), h * 0.96)
                2 -> P(w * 0.04, rnd(h * 0.1, h * 0.9))
                else -> P(w * 0.96, rnd(h * 0.1, h * 0.9))
            }
            if (blocks.any { it.contains(p) }) continue
            if (es.any { it.pos.dist(p) < minD * 0.22 }) continue
            es.add(Emitter(p, rnd(0.0, 2 * PI), spinSpeed * (if (rndBool()) 1 else -1)))
        }
        emitters = es
        timeLeft = surviveTime; grace = 0.8; playing = true
    }

    fun demoSetup() {
        val minD = min(w, h)
        player = P(w / 2, h / 2)
        blocks = listOf(0.16 to 0.18, 0.66 to 0.22, 0.20 to 0.64, 0.62 to 0.66).map { (fx, fy) -> Box2(w * fx, h * fy, minD * 0.17, minD * 0.15) }
        emitters = listOf(Emitter(P(w * 0.5, h * 0.04), 2.355, spinSpeed), Emitter(P(w * 0.04, h * 0.45), 4.71, -spinSpeed),
            Emitter(P(w * 0.96, h * 0.78), 3.14, spinSpeed))
        timeLeft = surviveTime; grace = 0.8; playing = true
    }

    fun step(dt: Double) {
        if (!playing) return
        val hb = min(w, h) * 0.014; val half = min(w, h) * thickFrac / 2
        val v = moveSpeed * min(w, h) * dt
        player = resolveBlocks(P(clamp(player.x + stick.x * v, 0.0, w), clamp(player.y + stick.y * v, 0.0, h)), hb)
        for (e in emitters) e.angle += e.vel * dt
        if (grace > 0) grace -= dt
        else for (e in emitters) if (distToSegment(player, e.pos, rayEnd(e.pos, e.angle)) < half + hb) { fail(); return }
        timeLeft -= dt
        if (timeLeft <= 0) win()
    }

    /** Marches a ray from `o` until it leaves the field or enters a block. */
    fun rayEnd(o: P, angle: Double): P {
        val st = max(2.0, min(w, h) * 0.012)
        val dx = cos(angle) * st; val dy = sin(angle) * st
        var px = o.x; var py = o.y
        var n = 0
        while (n < 3000) {
            n++
            val nx = px + dx; val ny = py + dy
            if (nx < 0 || nx > w || ny < 0 || ny > h) break
            val np = P(nx, ny)
            if (blocks.any { it.contains(np) }) break
            px = nx; py = ny
        }
        return P(px, py)
    }

    fun distToSegment(p: P, a: P, b: P): Double {
        val dx = b.x - a.x; val dy = b.y - a.y
        val len2 = dx * dx + dy * dy
        if (len2 < 0.0001) return p.dist(a)
        val t = clamp(((p.x - a.x) * dx + (p.y - a.y) * dy) / len2, 0.0, 1.0)
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /** Pushes the player out of any block (expanded by the hitbox) to the nearest edge. */
    fun resolveBlocks(pos: P, hb: Double): P {
        var x = pos.x; var y = pos.y
        for (b in blocks) {
            val bb = b.inset(-hb)
            if (!bb.contains(P(x, y))) continue
            val l = x - bb.x; val r = bb.maxX - x; val t = y - bb.y; val bo = bb.maxY - y
            val m = minOf(l, r, t, bo)
            when (m) { l -> x = bb.x; r -> x = bb.maxX; t -> y = bb.y; else -> y = bb.maxY }
        }
        return P(x, y)
    }

    /** The demo finger: predict beams ~0.5 s ahead and head for the wander lane through safe spots. */
    fun demoTarget(t: Double): P {
        val minD = min(w, h)
        val hb = minD * 0.014; val half = minD * thickFrac / 2
        val segs = mutableListOf<Pair<P, P>>()
        for (e in emitters) for (tau in listOf(0.0, 0.15, 0.3, 0.45, 0.6, 0.8)) segs.add(e.pos to rayEnd(e.pos, e.angle + e.vel * tau))
        fun clearance(c: P) = segs.minOfOrNull { distToSegment(c, it.first, it.second) } ?: Double.MAX_VALUE
        val lane = demoWander[(t / 1.5).toInt() % demoWander.size]
        val goal = P(lane.x * w, lane.y * h)
        val safe = half + hb + minD * 0.06
        val cands = mutableListOf(player)
        for (r in listOf(0.05, 0.1, 0.16, 0.22)) for (k in 0 until 16) {
            val a = k / 16.0 * 2 * PI
            val c = P(clamp(player.x + cos(a) * minD * r, w * 0.1, w * 0.9), clamp(player.y + sin(a) * minD * r, h * 0.1, h * 0.9))
            cands.add(resolveBlocks(c, hb))
        }
        val scored = cands.map { c -> c to min(clearance(c), clearance(P((c.x + player.x) / 2, (c.y + player.y) / 2))) }
        scored.filter { it.second >= safe }.minByOrNull { it.first.dist(goal) }?.let { return it.first }
        return scored.maxByOrNull { it.second }?.first ?: player
    }

    fun win() { if (!playing) return; playing = false; Haptics.success(); SoundManager.tap(); onWin() }
    fun fail() { if (!playing) return; playing = false; Haptics.warning(); SoundManager.error(); onFail() }
}

@Composable
private fun LaserDodgeView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { LaserWorld(level) }
    world.onWin = onWin; world.onFail = onFail
    var ready by remember { mutableStateOf(false) }
    var demoTick by remember { mutableIntStateOf(0) }
    val tick by rememberFrameLoop(running = ready && !isDemo) { dt -> world.step(dt) }

    LaunchedEffect(ready) {
        if (!ready || !isDemo) return@LaunchedEffect
        val dt = 1.0 / 60.0
        while (isActive) {
            world.demoSetup(); demoTick++
            delay(400)
            var t = 0.0
            while (isActive && world.playing) {
                t += dt
                val target = world.demoTarget(t)
                val dx = target.x - world.player.x; val dy = target.y - world.player.y; val d = hypot(dx, dy)
                val full = min(world.w, world.h) * world.moveSpeed * dt
                val k = if (d > 0.001) min(1.0, d / full) / d else 0.0
                world.stick = P(dx * k, dy * k)
                world.step(dt)
                demoTick++
                delay(16)
            }
            world.stick = P.zero; demoTick++
            delay(1300)
        }
    }

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .background(room).padding(top = if (isDemo) 0.dp else 8.dp),
        verticalArrangement = Arrangement.spacedBy(if (isDemo) 6.dp else 8.dp), horizontalAlignment = Alignment.CenterHorizontally
    ) {
        tick; demoTick
        Row(Modifier.padding(top = if (isDemo) 6.dp else 0.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            val ls = if (isDemo) 8.0 else 10.0
            Canvas(Modifier.size(ls.dp)) {
                blurCircle(size.width / 2.0, size.height / 2.0, size.width / 2.0, laserRed, 4 * density.toDouble())
                circle(size.width / 2.0, size.height / 2.0, size.width / 2.0, laserRed)
            }
            Text(L("SURVIVE", "SỐNG SÓT"), style = ts(if (isDemo) 15.0 else 22.0, FontWeight.Black, spacing = 2.0))
        }
        if (!isDemo) {
            val f = world.timeLeft / world.surviveTime
            TimeBar(f, Modifier.fillMaxWidth().padding(horizontal = 48.dp).height(6.dp), fill = if (f < 0.3) rgb(0.4, 0.95, 0.5) else rgb(1.0, 0.66, 0.16))
        }
        // The arena: a steel bezel drawn outside the field.
        val dens = androidx.compose.ui.platform.LocalDensity.current.density.toDouble()
        Canvas(Modifier.fillMaxWidth().weight(1f).padding(horizontal = 12.dp).onSizeChanged { sz ->
            if (ready || sz.width <= 0 || sz.height <= 0) return@onSizeChanged
            val t = (if (isDemo) 5.0 else 7.0) * dens
            world.w = max(1.0, sz.width - t * 2); world.h = max(1.0, sz.height - t * 2)
            if (!isDemo) world.setup()
            ready = true
        }) {
            tick; demoTick
            val u = density.toDouble()
            val t = (if (isDemo) 5.0 else 7.0) * u
            val fw = world.w; val fh = world.h
            bezel(t)
            val clip = Path().apply { addRoundRect(androidx.compose.ui.geometry.RoundRect(t.f, t.f, (t + fw).f, (t + fh).f, (10 * u).f, (10 * u).f)) }
            clipPath(clip) {
                translate(t.f, t.f) {
                    if (ready) { vault(fw, fh, world.blocks); drawAction(world, fw, fh) }
                }
            }
        }
        FloatingJoystick(
            Modifier.fillMaxWidth().height(if (isDemo) 70.dp else 112.dp).padding(bottom = 0.dp),
            if (isDemo) 70.0 else 112.0, isDemo, world.playing, world.stick, onVector = { world.stick = it },
            base = { push -> joystickBase(push) }, knob = { joystickKnob() }
        )
        androidx.compose.foundation.layout.Spacer(Modifier.height(if (isDemo) 6.dp else 10.dp))
    }
}

// Laser vault art (iOS LDArt and friends).

private val laserRed = rgb(1.0, 0.16, 0.2)
private val room = rgb(0.05, 0.055, 0.08)
private val ink = rgb(0.05, 0.05, 0.07)
private val gold = rgb(0.98, 0.78, 0.22)

private fun hash(n: Double): Double { val v = sin(n * 12.9898) * 43758.5453; return v - floor(v) }

private fun DrawScope.drawAction(world: LaserWorld, w: Double, h: Double) {
    val minD = min(w, h)
    val thick = minD * world.thickFrac
    for (e in world.emitters) beam(e.pos, world.rayEnd(e.pos, e.angle), thick)
    for (e in world.emitters) turret(e.pos, e.angle, max(6 * density.toDouble(), minD * 0.03))
    val p = if (world.player == P.zero) P(w / 2, h / 2) else world.player
    withAlpha(if (world.grace > 0) 0.5 else 1.0) {
        spyBanana(p, minD * 0.15)
        val hb = minD * 0.014
        val inner = (hb * 0.8 / (hb * 2.2)).toFloat()
        drawCircle(androidx.compose.ui.graphics.Brush.radialGradient(0f to Color.White.op(0.7), inner to Color.White.op(0.7), 1f to Color.White.op(0.0),
            center = p.o(), radius = (hb * 2.2).f), (hb * 2.2).f, p.o())
        circle(p.x, p.y, hb, Color.White)
        circleStroke(p.x, p.y, hb, Color.Black.op(0.5), 0.8 * density)
    }
}

/** A laser in haze: wide glow, the red beam at its true thickness, a white-hot core and a hot spot. */
private fun DrawScope.beam(a: P, b: P, thick: Double) {
    line(a.x, a.y, b.x, b.y, laserRed.op(0.1), thick * 5.5)
    line(a.x, a.y, b.x, b.y, laserRed.op(0.28), thick * 2.4)
    line(a.x, a.y, b.x, b.y, laserRed, thick)
    line(a.x, a.y, b.x, b.y, rgb(1.0, 0.86, 0.86), max(0.8 * density, thick * 0.32))
    val r = thick * 2.4
    circle(b.x, b.y, r, radial(listOf(Color.White, laserRed.op(0.7), laserRed.op(0.0)), b.x, b.y, r))
}

/** A wall turret seen from above: a bolted base and a head that swings with its beam. */
private fun DrawScope.turret(p: P, angle: Double, r: Double) {
    circle(p.x + r * 0.15, p.y + r * 0.25, r * 1.05, Color.Black.op(0.45))
    circle(p.x, p.y, r, radial(listOf(gray(0.52), gray(0.22)), p.x - r * 0.3, p.y - r * 0.3, r * 1.4))
    circleStroke(p.x, p.y, r, ink, 1.2 * density)
    for (k in 0 until 4) { val a = k * PI / 2 + PI / 4; circle(p.x + cos(a) * r * 0.72, p.y + sin(a) * r * 0.72, r * 0.1, gray(0.7)) }
    translate(p.x.f, p.y.f) {
        rotateRad(angle.f, androidx.compose.ui.geometry.Offset.Zero) {
            rrect(-r * 0.55, -r * 0.42, r * 1.7, r * 0.84, r * 0.3, vgrad(listOf(gray(0.6), gray(0.28)), -r * 0.42, r * 0.42))
            rrectStroke(-r * 0.55, -r * 0.42, r * 1.7, r * 0.84, r * 0.3, ink, density.toDouble())
            oval(r * 0.95, -r * 0.3, r * 0.34, r * 0.6, laserRed)
            oval(r * 1.01, -r * 0.22, r * 0.12, r * 0.16, Color.White.op(0.9))
        }
    }
}

/** The joystick base: steel bezel ring, dark rubber well and four red sensor-lamp arrows. */
private fun DrawScope.joystickBase(push: P) {
    val u = density.toDouble()
    val cx = size.width / 2.0; val cy = size.height / 2.0
    val r = min(size.width, size.height) / 2.0 - 2 * u
    circle(cx, cy + 3 * u, r, Color.Black.op(0.45))
    circle(cx, cy, r, vgrad(listOf(gray(0.62), gray(0.3), gray(0.16)), cy - r, cy + r))
    circleStroke(cx, cy, r - 0.5 * u, Color.White.op(0.25), u)
    val well = r * 0.8
    circle(cx, cy, well, radial(listOf(rgb(0.16, 0.08, 0.1), ink), cx, cy, well))
    circleStroke(cx, cy, well, Color.Black, 2 * u)
    for (k in 0 until 4) { val a = k * PI / 2 + PI / 4; circle(cx + cos(a) * r * 0.9, cy + sin(a) * r * 0.9, max(1.2 * u, r * 0.045), gray(0.78)) }
    for (k in 0 until 4) {
        val a = k * PI / 2 - PI / 2
        val dx = cos(a); val dy = sin(a)
        val glow = max(0.0, push.x * dx + push.y * dy)
        val tx = cx + dx * well * 0.9; val ty = cy + dy * well * 0.9
        val bx = cx + dx * well * 0.68; val by = cy + dy * well * 0.68
        if (glow > 0.05) {
            val mx = (tx + bx) / 2; val my = (ty + by) / 2
            circle(mx, my, well * 0.26, radial(listOf(laserRed.op(0.6 * glow), laserRed.op(0.0)), mx, my, well * 0.26))
        }
        fillPath(polyPath(tx, ty, bx - dy * well * 0.15, by + dx * well * 0.15, bx + dy * well * 0.15, by - dx * well * 0.15), laserRed.op(0.3 + 0.7 * glow))
    }
}

/** The joystick knob: black rubber with a grip ring and a red lens. */
private fun DrawScope.joystickKnob() {
    val u = density.toDouble()
    val cx = size.width / 2.0; val cy = size.height / 2.0
    val r = min(size.width, size.height) / 2.0 * 0.92
    circle(cx + r * 0.08, cy + r * 0.16, r, Color.Black.op(0.45))
    circle(cx, cy, r, radial(listOf(gray(0.4), gray(0.14), gray(0.06)), cx - r * 0.35, cy - r * 0.4, r * 1.5))
    circleStroke(cx, cy, r * 0.72, Color.Black.op(0.7), max(u, r * 0.08))
    circleStroke(cx, cy, r * 0.78, Color.White.op(0.12), u)
    circle(cx, cy, r * 0.3, radial(listOf(rgb(1.0, 0.75, 0.75), laserRed, rgb(0.45, 0.02, 0.05)), cx - r * 0.08, cy - r * 0.08, r * 0.32))
    circle(cx - r * 0.1, cy - r * 0.11, r * 0.08, Color.White.op(0.85))
    circleStroke(cx, cy, r, Color.Black, 1.2 * u)
}

/** The banana thief: a plump banana in a black mask whose body runs through the hitbox point. */
private fun DrawScope.spyBanana(p: P, w: Double) {
    val u = density.toDouble()
    val h = w * 0.45
    val cx = p.x; val cy = p.y - h * 0.043
    val body = Path()
    body.m(cx - w * 0.5, cy - h * 0.4)
    body.q(cx - w * 0.02, cy + h * 1.05, cx + w * 0.5, cy - h * 0.5)
    body.q(cx, cy + h * 0.02, cx - w * 0.5, cy - h * 0.4)
    body.close()
    translate((w * 0.04).f, (h * 0.2).f) { fillPath(body, Color.Black.op(0.45)) }
    drawPath(body, vgrad(listOf(rgb(1.0, 0.95, 0.5), rgb(1.0, 0.84, 0.2), rgb(0.86, 0.62, 0.08)), cy - h * 0.3, cy + h * 0.4))
    clipPath(body) { rect(cx - w * 0.37, cy - h, w * 0.16, h * 2, ink) }
    for (y in listOf(-0.24, -0.06)) oval(cx - w * 0.325, cy + h * y, w * 0.065, h * 0.13, Color.White)
    strokePath(body, rgb(0.4, 0.26, 0.04), max(1.2 * u, w * 0.035))
    rrect(cx - w * 0.6, cy - h * 0.5, w * 0.13, h * 0.2, w * 0.02, rgb(0.42, 0.28, 0.1))
    oval(cx + w * 0.45, cy - h * 0.57, w * 0.08, h * 0.15, rgb(0.3, 0.2, 0.05))
}

/** The prize on a plinth: diamond, golden banana idol, ruby, crown or jade vase. */
private fun DrawScope.treasure(kind: Int, cx: Double, cy: Double, s: Double) {
    val u = density.toDouble()
    when (kind % 5) {
        0 -> {
            val oct = polyPath((0 until 8).map { k -> val a = k * PI / 4 + PI / 8; P(cx + cos(a) * s * 0.5, cy + sin(a) * s * 0.5) })
            drawPath(oct, lin(listOf(rgb(0.85, 0.98, 1.0), rgb(0.35, 0.75, 0.95)), cx - s * 0.4, cy - s * 0.4, cx + s * 0.4, cy + s * 0.4))
            val facets = Path()
            for (k in 0 until 8) { val a = k * PI / 4 + PI / 8; facets.m(cx, cy); facets.l(cx + cos(a) * s * 0.5, cy + sin(a) * s * 0.5) }
            facets.addRect(androidx.compose.ui.geometry.Rect((cx - s * 0.18).f, (cy - s * 0.18).f, (cx + s * 0.18).f, (cy + s * 0.18).f))
            strokePath(facets, rgb(0.2, 0.5, 0.7, 0.7), 0.8 * u, StrokeCap.Butt)
            strokePath(oct, rgb(0.12, 0.35, 0.5), u)
        }
        1 -> {
            val h = s * 0.5
            val ban = Path()
            ban.m(cx - s * 0.5, cy - h * 0.3); ban.q(cx, cy + h * 1.1, cx + s * 0.5, cy - h * 0.4); ban.q(cx, cy + h * 0.35, cx - s * 0.5, cy - h * 0.3); ban.close()
            drawPath(ban, vgrad(listOf(rgb(1.0, 0.95, 0.6), gold, rgb(0.7, 0.48, 0.08)), cy - h * 0.3, cy + h * 0.6))
            strokePath(ban, rgb(0.45, 0.3, 0.04), u)
            circle(cx - s * 0.15, cy + h * 0.1, s * 0.05, Color.White.op(0.9))
        }
        2 -> translate(cx.f, cy.f) {
            rotate(45f, androidx.compose.ui.geometry.Offset.Zero) {
                rrect(-s * 0.34, -s * 0.34, s * 0.68, s * 0.68, s * 0.12, lin(listOf(rgb(1.0, 0.5, 0.55), rgb(0.75, 0.05, 0.15)), -s * 0.3, -s * 0.3, s * 0.3, s * 0.3))
                rrectStroke(-s * 0.16, -s * 0.16, s * 0.32, s * 0.32, s * 0.04, Color.White.op(0.5), 0.8 * u)
                rrectStroke(-s * 0.34, -s * 0.34, s * 0.68, s * 0.68, s * 0.12, rgb(0.4, 0.02, 0.08), u)
            }
        }
        3 -> {
            val crown = polyPath((0 until 10).map { k -> val a = k * PI / 5 - PI / 2; val rr = if (k % 2 == 0) s * 0.5 else s * 0.33; P(cx + cos(a) * rr, cy + sin(a) * rr) })
            fillPath(crown, gold)
            strokePath(crown, rgb(0.5, 0.34, 0.05), u)
            circle(cx, cy, s * 0.2, rgb(0.55, 0.1, 0.2))
            circle(cx, cy, s * 0.08, rgb(0.3, 0.6, 1.0))
        }
        else -> {
            circle(cx, cy, s * 0.48, radial(listOf(rgb(0.5, 0.85, 0.6), rgb(0.1, 0.45, 0.3)), cx - s * 0.15, cy - s * 0.15, s * 0.55))
            circleStroke(cx, cy, s * 0.48, rgb(0.05, 0.25, 0.15), u)
            circleStroke(cx, cy, s * 0.3, gold.op(0.8), 1.2 * u)
            circle(cx, cy, s * 0.16, rgb(0.03, 0.12, 0.08))
        }
    }
}

/** The vault's steel bezel with a row of little red sensor lamps. */
private fun DrawScope.bezel(t: Double) {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    rrect(0.0, 0.0, w, h, 14 * u, vgrad(listOf(gray(0.3), gray(0.12)), 0.0, h))
    rrectStroke(0.5 * u, 0.5 * u, w - u, h - u, 14 * u, Color.White.op(0.18), u)
    rrectStroke(t - 0.5 * u, t - 0.5 * u, w - 2 * t + u, h - 2 * t + u, 10.5 * u, Color.Black.op(0.8), 1.5 * u)
    var x = 26 * u
    while (x < w - 20 * u) {
        for (y in listOf(t / 2, h - t / 2)) circle(x, y, max(1.2 * u, t * 0.2), laserRed.op(0.85))
        x += 34 * u
    }
}

/** Polished dark stone, red haze, and a display plinth with a prize under glass on every block. */
private fun DrawScope.vault(w: Double, h: Double, blocks: List<Box2>) {
    val u = density.toDouble()
    rect(0.0, 0.0, w, h, vgrad(listOf(rgb(0.1, 0.11, 0.15), rgb(0.05, 0.055, 0.08)), 0.0, h))
    val tile = max(24 * u, min(w, h) / 4.5)
    val grid = Path()
    var gx = 0.0
    while (gx <= w) { grid.m(gx, 0.0); grid.l(gx, h); gx += tile }
    var gy = 0.0
    while (gy <= h) { grid.m(0.0, gy); grid.l(w, gy); gy += tile }
    strokePath(grid, rgb(0.17, 0.19, 0.25), u, StrokeCap.Butt)
    rect(0.0, 0.0, w, h, lin(listOf(Color.Transparent, Color.White.op(0.05), Color.Transparent), 0.0, h * 0.1, w, h * 0.7))
    for (k in 0 until 3) {
        val cx = w * hash(k * 3.7 + 1); val cy = h * hash(k * 5.1 + 2)
        val r = min(w, h) * (0.35 + 0.2 * hash(k + 9.0))
        circle(cx, cy, r, radial(listOf(laserRed.op(0.06), Color.Transparent), cx, cy, r))
    }
    blocks.forEachIndexed { i, b ->
        val m = min(b.w, b.h)
        rrect(b.x + m * 0.06, b.y + m * 0.09, b.w, b.h, m * 0.08, Color.Black.op(0.5))
        rrect(b.x, b.y, b.w, b.h, m * 0.08, lin(listOf(rgb(0.62, 0.6, 0.58), rgb(0.38, 0.37, 0.36)), b.x, b.y, b.maxX, b.maxY))
        val tp = b.inset(m * 0.1)
        rrect(tp.x, tp.y, tp.w, tp.h, m * 0.05, lin(listOf(rgb(0.95, 0.94, 0.92), rgb(0.8, 0.79, 0.77)), tp.x, tp.y, tp.maxX, tp.maxY))
        val vein = Path()
        vein.m(tp.x + tp.w * 0.1, tp.maxY - tp.h * 0.2)
        vein.q(tp.x + tp.w / 2 + tp.w * 0.1 * (hash(i.toDouble()) - 0.5), tp.y + tp.h / 2 + tp.h * 0.25, tp.maxX - tp.w * 0.15, tp.y + tp.h * 0.15)
        strokePath(vein, gray(0.55).op(0.5), 0.8 * u)
        rrectStroke(b.x, b.y, b.w, b.h, m * 0.08, ink, 1.2 * u)
        treasure(i, tp.x + tp.w / 2, tp.y + tp.h / 2, m * 0.46)
        val g = tp.inset(m * 0.05)
        rrectStroke(g.x, g.y, g.w, g.h, m * 0.04, rgb(0.7, 0.9, 1.0, 0.55), u)
        line(g.x + g.w * 0.12, g.y + g.h * 0.45, g.x + g.w * 0.45, g.y + g.h * 0.12, Color.White.op(0.45), 1.5 * u)
    }
    val minD = min(w, h); val maxD = max(w, h)
    drawRect(androidx.compose.ui.graphics.Brush.radialGradient(0f to Color.Transparent, (minD * 0.35 / (maxD * 0.75)).toFloat() to Color.Transparent,
        1f to Color.Black.op(0.45), center = off(w / 2, h / 2), radius = (maxD * 0.75).f), size = sz(w, h))
}
