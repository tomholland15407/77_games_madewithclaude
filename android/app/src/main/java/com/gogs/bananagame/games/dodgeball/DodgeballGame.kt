package com.gogs.bananagame.games.dodgeball

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Reflex — Dodgeball (iOS DodgeballGame.swift): a bullet-hell dash for the treasure chest. Steer
 * with the floating joystick through rings, fans and spirals; touch the chest to win.
 */
object DodgeballGame {
    val definition = GameDefinition(
        id = "dodgeball",
        title = "Dodgeball",
        genre = Genre.REFLEX,
        locksFeed = true,
        manual = GameManual(
            bullets = listOf(
                "Steer the banana with the joystick; only the small bright center dot is a hit.",
                "The treasure chest at the top fires waves of bullets — rings, fans, and spirals.",
                "Weave up through the gaps and touch the chest to win.",
                "One touch, or the clock running out, sends you back to level 1.",
            ),
            bulletsVI = listOf(
                "Lái quả chuối bằng cần điều khiển; chỉ chấm sáng nhỏ ở giữa mới trúng đòn.",
                "Rương báu ở trên bắn từng đợt đạn — vòng, quạt và xoắn ốc.",
                "Luồn lên qua các khe hở và chạm vào rương để thắng.",
                "Chạm một lần, hoặc hết giờ, sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> DodgeballView(level, onWin, onFail) }
    )
}

private val palette = listOf(rgb(0.9, 0.16, 0.14), rgb(0.16, 0.42, 0.92), rgb(0.18, 0.68, 0.3), rgb(0.6, 0.3, 0.86))
private const val CHEST_X = 0.5
private const val CHEST_Y = 0.17

private class Bullet(var x: Double, var y: Double, val vx: Double, val vy: Double, val color: Int)

private class DodgeWorld(level: Int, val isDemo: Boolean) {
    private val li = min(level, 7) - 1
    val timeLimit = listOf(20.0, 19.0, 18.0, 17.0, 16.0, 15.0, 14.0)[li]
    val spawnInterval = listOf(0.85, 0.72, 0.60, 0.50, 0.42, 0.35, 0.28)[li]
    val waveSize = listOf(10, 13, 16, 20, 24, 28, 34)[li]
    val bulletSpeed = listOf(0.26, 0.30, 0.34, 0.39, 0.44, 0.50, 0.57)[li]
    val moveSpeed = 0.9

    var playing = true
    var w = 0.0; var h = 0.0
    var player = P.zero
    var bullets = mutableListOf<Bullet>()
    var stick = P.zero
    var timeLeft = timeLimit
    var spawnTimer = 0.0
    var spiralAngle = 0.0
    var t = 0.0
    var demoWaveIdx = 0
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    fun setup() {
        player = P(w / 2, h * 0.85); bullets = mutableListOf(); timeLeft = timeLimit
        spawnTimer = 0.5; spiralAngle = 0.0; playing = true
    }

    fun step(dt: Double) {
        if (!playing) return
        t += dt
        val margin = h * 0.08
        val hb = min(w, h) * 0.014; val br = min(w, h) * 0.015
        val v = moveSpeed * min(w, h) * dt
        player = P(clamp(player.x + stick.x * v, 0.0, w), clamp(player.y + stick.y * v, 0.0, h))
        val chest = P(CHEST_X * w, CHEST_Y * h)
        if (player.dist(chest) < min(w, h) * 0.22 * 0.42 + hb) { win(); return }
        val survivors = ArrayList<Bullet>(bullets.size)
        for (b in bullets) {
            b.x += b.vx * dt; b.y += b.vy * dt
            if (b.x < -margin || b.x > w + margin || b.y < -margin || b.y > h + margin) continue
            if (hypot(b.x - player.x, b.y - player.y) < hb + br * 0.6) { fail(); return }
            survivors.add(b)
        }
        bullets = survivors
        spawnTimer -= dt
        if (spawnTimer <= 0) { spawnTimer = spawnInterval; fireWave(chest) }
        timeLeft -= dt
        if (timeLeft <= 0) fail()
    }

    private fun fireWave(o: P) {
        val speed = bulletSpeed * h
        val color = if (isDemo) demoWaveIdx % palette.size else rndInt(0 until palette.size)
        val kind = if (isDemo) demoWaveIdx % 3 else rndInt(0..2)
        val demoBase = 0.3 + demoWaveIdx * 0.7
        if (isDemo) demoWaveIdx++
        fun add(a: Double) = bullets.add(Bullet(o.x, o.y, cos(a) * speed, sin(a) * speed, color))
        when (kind) {
            0 -> {
                val base = if (isDemo) demoBase else rnd(0.0, 2 * PI)
                for (i in 0 until waveSize) add(base + i.toDouble() / waveSize * 2 * PI)
            }
            1 -> {
                val aim = atan2(player.y - o.y, player.x - o.x)
                val n = max(5, waveSize / 2); val spread = 0.9
                for (i in 0 until n) add(aim - spread / 2 + spread * (if (n == 1) 0.5 else i.toDouble() / (n - 1)))
            }
            else -> {
                val arms = 3; val n = max(4, waveSize / arms)
                for (k in 0 until arms) for (i in 0 until n) add(spiralAngle + k.toDouble() / arms * 2 * PI + i * 0.12)
                spiralAngle += 0.5
            }
        }
        SoundManager.tap()
        if (bullets.size > 460) bullets = bullets.subList(bullets.size - 460, bullets.size).toMutableList()
    }

    /** The demo thumb: predict bullets ~0.45 s ahead and head for the goal through clear spots. */
    fun demoTarget(): P {
        val minD = min(w, h)
        val hb = minD * 0.014; val br = minD * 0.015
        val goal = if (t < 2.8) P(w * (0.5 + 0.28 * sin(t * 2.2)), h * 0.74) else P(CHEST_X * w, CHEST_Y * h)
        val speed = minD * moveSpeed
        val taus = listOf(0.0, 0.1, 0.2, 0.3, 0.45)
        fun clearance(c: P): Double {
            val dx = c.x - player.x; val dy = c.y - player.y; val d = hypot(dx, dy)
            var best = Double.MAX_VALUE
            for (tau in taus) {
                val k = if (d > 0.001) min(1.0, tau * speed / d) else 0.0
                val px = player.x + dx * k; val py = player.y + dy * k
                for (b in bullets) best = min(best, hypot(b.x + b.vx * tau - px, b.y + b.vy * tau - py))
            }
            return best
        }
        val safe = hb + br * 0.6 + minD * 0.035
        val cands = mutableListOf(player)
        for (r in listOf(0.03, 0.07, 0.12)) for (k in 0 until 16) {
            val a = k / 16.0 * 2 * PI
            cands.add(P(clamp(player.x + cos(a) * minD * r, w * 0.04, w * 0.96), clamp(player.y + sin(a) * minD * r, h * 0.04, h * 0.96)))
        }
        val scored = cands.map { it to clearance(it) }
        scored.filter { it.second >= safe }.minByOrNull { it.first.dist(goal) }?.let { return it.first }
        return scored.maxByOrNull { it.second }?.first ?: player
    }

    fun win() { if (!playing) return; playing = false; Haptics.success(); SoundManager.tap(); onWin() }
    fun fail() { if (!playing) return; playing = false; Haptics.warning(); SoundManager.error(); onFail() }
}

@Composable
private fun DodgeballView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { DodgeWorld(level, isDemo) }
    world.onWin = onWin; world.onFail = onFail
    var ready by remember { mutableStateOf(false) }
    var demoTick by remember { mutableIntStateOf(0) }
    val tick by rememberFrameLoop(running = ready && !isDemo) { dt -> world.step(dt) }

    LaunchedEffect(ready) {
        if (!ready || !isDemo) return@LaunchedEffect
        val dt = 1.0 / 60.0
        while (isActive) {
            world.demoWaveIdx = 0; world.t = 0.0; world.setup(); demoTick++
            delay(500)
            while (isActive && world.playing) {
                val target = world.demoTarget()
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
            .drawBehind { paddedWall() },
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        tick; demoTick
        // The gym scoreboard: the goal in amber lights over the clock.
        Column(
            Modifier.padding(top = if (isDemo) 6.dp else 10.dp, bottom = if (isDemo) 6.dp else 10.dp)
                .background(gray(0.07), RoundedCornerShape(8.dp)).border(2.dp, gray(0.4), RoundedCornerShape(8.dp))
                .padding(horizontal = 16.dp, vertical = if (isDemo) 5.dp else 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(L("REACH THE TREASURE", "ĐẾN CHỖ BÁU VẬT"), style = ts(if (isDemo) 13.0 else 17.0, FontWeight.Black, led, Mono).copy(
                shadow = Shadow(led.op(0.7), blurRadius = 8f)), maxLines = 1, overflow = TextOverflow.Clip)
            if (!isDemo) {
                val f = world.timeLeft / world.timeLimit
                Canvas(Modifier.size(190.dp, 6.dp)) {
                    val w = size.width.toDouble(); val h = size.height.toDouble()
                    rrect(0.0, 0.0, w, h, h / 2, led.op(0.15))
                    val c = if (f < 0.3) rgb(1.0, 0.25, 0.2) else led
                    if (f > 0) { blurRRect(0.0, 0.0, w * f, h, h / 2, c.op(0.7), 3 * density.toDouble()); rrect(0.0, 0.0, w * f, h, h / 2, c) }
                }
            }
        }
        Canvas(Modifier.fillMaxWidth().weight(1f).padding(horizontal = 12.dp).padding(bottom = if (isDemo) 6.dp else 10.dp)
            .clip(RoundedCornerShape(10.dp))
            .onSizeChanged { sz ->
                if (ready || sz.width <= 0) return@onSizeChanged
                world.w = sz.width.toDouble(); world.h = sz.height.toDouble(); world.setup(); ready = true
            }) {
            tick; demoTick
            if (!ready) return@Canvas
            val w = size.width.toDouble(); val h = size.height.toDouble(); val minD = min(w, h)
            val cx = CHEST_X * w; val cy = CHEST_Y * h
            court(cx, cy, minD * 0.22)
            sparkles(cx, cy, minD * 0.22, world.t)
            val br = minD * 0.015
            for (b in world.bullets) ballArt(b.x, b.y, br * 1.15, palette[b.color])
            val p = if (world.player == P.zero) P(w / 2, h * 0.85) else world.player
            sportyBanana(p, minD * 0.15)
            val hb = minD * 0.014
            val inner = (0.8 / 2.2).toFloat()
            drawCircle(androidx.compose.ui.graphics.Brush.radialGradient(0f to Color.White.op(0.75), inner to Color.White.op(0.75), 1f to Color.White.op(0.0),
                center = p.o(), radius = (hb * 2.2).f), (hb * 2.2).f, p.o())
            circle(p.x, p.y, hb, Color.White)
            circleStroke(p.x, p.y, hb, Color.Black.op(0.5), 0.8 * density)
        }
        FloatingJoystick(Modifier.fillMaxWidth().height(if (isDemo) 76.dp else 118.dp), if (isDemo) 76.0 else 118.0, isDemo, world.playing,
            world.stick, onVector = { world.stick = it }, base = { push -> joystickBase(push) },
            knob = { ballArt(size.width / 2.0, size.height / 2.0, size.width / 2.0, palette[0]) })
        Spacer(Modifier.height(if (isDemo) 8.dp else 12.dp))
    }
}

// Gym art (iOS DBArt and friends).

private val led = rgb(1.0, 0.72, 0.2)
private val pad = rgb(0.13, 0.3, 0.66)
private val lineC = rgb(0.1, 0.2, 0.45)
private val ink = rgb(0.12, 0.07, 0.03)
private val gold = rgb(1.0, 0.8, 0.22)

private fun hash(n: Double): Double { val v = sin(n * 12.9898) * 43758.5453; return v - floor(v) }

/** One rubber playground ball in a box of half-size `half` centred at (cx, cy). */
private fun DrawScope.ballArt(cx0: Double, cy0: Double, half: Double, color: Color) {
    val r = half * 0.86
    val cx = cx0 - r * 0.06; val cy = cy0 - r * 0.08
    circle(cx + r * 0.14, cy + r * 0.22, r, Color.Black.op(0.3))
    circle(cx, cy, r, radial(listOf(color.lit(0.45), color, color.shade(0.4)), cx - r * 0.35, cy - r * 0.4, r * 1.5))
    val seam = Path(); seam.arc(cx + r * 0.9, cy - r * 0.9, r * 1.45, deg(100.0), deg(172.0), moveFirst = true)
    strokePath(seam, color.shade(0.5), max(0.7 * density, r * 0.16), StrokeCap.Butt)
    oval(cx - r * 0.55, cy - r * 0.6, r * 0.45, r * 0.32, Color.White.op(0.75))
    circleStroke(cx, cy, r, Color.Black.op(0.55), 0.8 * density)
}

/** An open treasure chest heaped with gold, gems and spare dodgeballs. */
private fun DrawScope.chest(cx: Double, cy: Double, s: Double) {
    val u = density.toDouble()
    circle(cx, cy, s * 0.95, radial(listOf(gold.op(0.4), gold.op(0.0)), cx, cy, s * 0.95))
    oval(cx - s * 0.62, cy + s * 0.26, s * 1.24, s * 0.22, Color.Black.op(0.35))
    val woodA = rgb(0.66, 0.42, 0.2); val woodB = rgb(0.45, 0.27, 0.12)
    val iron = rgb(0.25, 0.24, 0.26)
    val lid = Path()
    lid.m(cx - s * 0.5, cy - s * 0.12); lid.l(cx - s * 0.46, cy - s * 0.56)
    lid.q(cx, cy - s * 0.72, cx + s * 0.46, cy - s * 0.56); lid.l(cx + s * 0.5, cy - s * 0.12); lid.close()
    drawPath(lid, vgrad(listOf(woodA, woodB), cy - s * 0.6, cy - s * 0.1))
    rrect(cx - s * 0.4, cy - s * 0.52, s * 0.8, s * 0.36, s * 0.05, rgb(0.5, 0.08, 0.12))
    strokePath(lid, ink, 1.5 * u)
    val heap = listOf(doubleArrayOf(-0.34, -0.1, 0.1), doubleArrayOf(-0.18, -0.16, 0.11), doubleArrayOf(0.0, -0.19, 0.12), doubleArrayOf(0.18, -0.15, 0.11),
        doubleArrayOf(0.34, -0.1, 0.1), doubleArrayOf(-0.26, -0.05, 0.1), doubleArrayOf(0.26, -0.05, 0.1), doubleArrayOf(-0.08, -0.08, 0.1), doubleArrayOf(0.1, -0.08, 0.1))
    heap.forEachIndexed { i, hp ->
        val px = cx + hp[0] * s; val py = cy + hp[1] * s; val rr = hp[2] * s
        circle(px, py, rr, radial(listOf(rgb(1.0, 0.96, 0.6), gold, rgb(0.75, 0.5, 0.08)), px - rr * 0.3, py - rr * 0.3, rr * 1.3))
        circleStroke(px, py, rr, rgb(0.55, 0.36, 0.05), 0.8 * u)
        if (i == 2) {
            circle(px - s * 0.13, py - s * 0.04, s * 0.09, rgb(0.88, 0.18, 0.15))
            circle(px + s * 0.15, py - s * 0.03, s * 0.08, rgb(0.2, 0.45, 0.92))
        }
    }
    drawPath(polyPath(cx + s * 0.33, cy - s * 0.31, cx + s * 0.4, cy - s * 0.23, cx + s * 0.33, cy - s * 0.14, cx + s * 0.26, cy - s * 0.23),
        vgrad(listOf(rgb(0.75, 0.96, 1.0), rgb(0.2, 0.6, 0.92)), cy - s * 0.31, cy - s * 0.14))
    val fx = cx - s * 0.52; val fy = cy - s * 0.08; val fw = s * 1.04; val fh = s * 0.42
    rrect(fx, fy, fw, fh, s * 0.05, vgrad(listOf(woodA, woodB), fy, fy + fh))
    val planks = Path()
    for (k in 1..2) { val y = fy + fh * k / 3; planks.m(fx + 2 * u, y); planks.l(fx + fw - 2 * u, y) }
    strokePath(planks, ink.op(0.45), u, StrokeCap.Butt)
    for (x in listOf(fx, fx + fw - s * 0.12)) {
        rrect(x, fy, s * 0.12, fh, s * 0.03, iron)
        circle(x + s * 0.06, fy + fh * 0.25, s * 0.022, gray(0.6))
        circle(x + s * 0.06, fy + fh * 0.75, s * 0.022, gray(0.6))
    }
    rect(fx, fy, fw, s * 0.07, gold.shade(0.1))
    val lx = cx - s * 0.09; val ly = fy + s * 0.02
    rrect(lx, ly, s * 0.18, s * 0.2, s * 0.03, gold)
    rrectStroke(lx, ly, s * 0.18, s * 0.2, s * 0.03, ink, u)
    circle(cx, ly + s * 0.1, s * 0.028, ink)
    rrectStroke(fx, fy, fw, fh, s * 0.05, ink, 1.5 * u)
}

/** Two twinkles over the gold, pulsing out of step. */
private fun DrawScope.sparkles(cx: Double, cy: Double, s: Double, t: Double) {
    val a = 0.5 + 0.5 * sin(t * 4)
    for ((d, k) in listOf(doubleArrayOf(-0.44, -0.46, 0.09) to a, doubleArrayOf(0.46, -0.02, 0.06) to 1 - a)) {
        val px = cx + d[0] * s; val py = cy + d[1] * s
        val star = polyPath((0 until 8).map { i -> val ang = i * PI / 4; val rr = if (i % 2 == 0) d[2] * s else d[2] * s * 0.28; P(px + cos(ang) * rr, py + sin(ang) * rr) })
        fillPath(star, Color.White.op(k))
    }
}

/** The joystick base: scoreboard-black rubber in a grey bezel with four amber arrow lights. */
private fun DrawScope.joystickBase(push: P) {
    val u = density.toDouble()
    val cx = size.width / 2.0; val cy = size.height / 2.0
    val r = min(size.width, size.height) / 2.0 - 2 * u
    circle(cx, cy + 3 * u, r, Color.Black.op(0.35))
    circle(cx, cy, r, radial(listOf(gray(0.2), gray(0.05)), cx, cy - r * 0.3, r * 1.2))
    circleStroke(cx, cy, r, Color.Black, 3 * u)
    circleStroke(cx, cy, r - 4 * u, gray(0.4), 1.5 * u)
    for (k in 0 until 4) {
        val a = k * PI / 2 - PI / 2
        val dx = cos(a); val dy = sin(a)
        val glow = max(0.0, push.x * dx + push.y * dy)
        val tx = cx + dx * r * 0.84; val ty = cy + dy * r * 0.84
        val bx = cx + dx * r * 0.66; val by = cy + dy * r * 0.66
        if (glow > 0.05) {
            val mx = (tx + bx) / 2; val my = (ty + by) / 2
            circle(mx, my, r * 0.2, radial(listOf(led.op(0.55 * glow), led.op(0.0)), mx, my, r * 0.2))
        }
        fillPath(polyPath(tx, ty, bx - dy * r * 0.13, by + dx * r * 0.13, bx + dy * r * 0.13, by - dx * r * 0.13), led.op(0.28 + 0.72 * glow))
    }
}

/** The banana player in a red sweatband, its body running through the hitbox. */
private fun DrawScope.sportyBanana(p: P, w: Double) {
    val u = density.toDouble()
    val h = w * 0.45
    val cx = p.x; val cy = p.y - h * 0.043
    val body = Path()
    body.m(cx - w * 0.5, cy - h * 0.4)
    body.q(cx - w * 0.02, cy + h * 1.05, cx + w * 0.5, cy - h * 0.5)
    body.q(cx, cy + h * 0.02, cx - w * 0.5, cy - h * 0.4)
    body.close()
    at(w * 0.04, h * 0.25) { fillPath(body, Color.Black.op(0.3)) }
    drawPath(body, vgrad(listOf(rgb(1.0, 0.95, 0.5), rgb(1.0, 0.84, 0.2), rgb(0.86, 0.62, 0.08)), cy - h * 0.3, cy + h * 0.4))
    clipPath(body) {
        rect(cx + w * 0.2, cy - h, w * 0.11, h * 2, rgb(0.9, 0.15, 0.15))
        rect(cx + w * 0.235, cy - h, w * 0.03, h * 2, Color.White)
    }
    for (y in listOf(-0.25, -0.07)) oval(cx + w * 0.1, cy + h * y, w * 0.06, h * 0.13, ink)
    strokePath(body, rgb(0.4, 0.26, 0.04), max(1.2 * u, w * 0.035))
    rrect(cx - w * 0.6, cy - h * 0.5, w * 0.13, h * 0.2, w * 0.02, rgb(0.42, 0.28, 0.1))
    oval(cx + w * 0.45, cy - h * 0.57, w * 0.08, h * 0.15, rgb(0.3, 0.2, 0.05))
}

/** The gym's blue padded wall. */
private fun DrawScope.paddedWall() {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    drawRect(pad.shade(0.25))
    val pw = 46 * u
    var x = -8 * u
    while (x < w) {
        val rx = x + 1.5 * u; val rw = pw - 3 * u
        rrect(rx, -10 * u, rw, h + 20 * u, 8 * u, hgrad(listOf(pad.lit(0.12), pad, pad.shade(0.18)), rx, rx + rw))
        rrect(rx + 5 * u, -10 * u, 3 * u, h + 20 * u, 1.5 * u, Color.White.op(0.12))
        x += pw
    }
}

/** Honey maple boards, painted lines, the banana logo and the treasure chest on the far baseline. */
private fun DrawScope.court(chestX: Double, chestY: Double, chestSize: Double) {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    drawRect(rgb(0.88, 0.7, 0.45))
    val bw = max(18 * u, w / 11)
    var x = 0.0; var k = 0
    while (x < w) {
        val tint = hash(k * 1.3)
        rect(x, 0.0, bw, h, rgb(0.86 + 0.06 * tint, 0.66 + 0.06 * tint, 0.4 + 0.05 * tint))
        val grain = Path()
        for (g in 0 until 3) {
            val gx = x + bw * (0.25 + 0.25 * g)
            grain.m(gx, 0.0); grain.c(gx - bw * 0.12, h * 0.35, gx + bw * 0.15, h * 0.65, gx + bw * 0.08, h)
        }
        strokePath(grain, rgb(0.62, 0.42, 0.2, 0.18), 0.8 * u, StrokeCap.Butt)
        val seam = Path(); seam.m(x, 0.0); seam.l(x, h)
        val jy = h * hash(k * 2.9 + 4); seam.m(x, jy); seam.l(x + bw, jy)
        strokePath(seam, rgb(0.55, 0.36, 0.16, 0.45), u, StrokeCap.Butt)
        x += bw; k++
    }
    drawRect(lin(listOf(Color.White.op(0.14), Color.Transparent, Color.White.op(0.08)), 0.0, 0.0, w, h))
    val inset = min(w, h) * 0.045
    rectStroke(inset, inset, w - 2 * inset, h - 2 * inset, lineC, 3 * u)
    line(inset, h * 0.5, w - inset, h * 0.5, lineC, 3 * u, StrokeCap.Butt)
    val cr = min(w, h) * 0.14
    circle(w / 2, h * 0.5, cr, rgb(0.95, 0.8, 0.3, 0.35))
    circleStroke(w / 2, h * 0.5, cr, lineC, 3 * u)
    val attack = Path()
    for (fy in listOf(0.3, 0.7)) { attack.m(inset, h * fy); attack.l(w - inset, h * fy) }
    drawPath(attack, rgb(0.85, 0.2, 0.15, 0.8), style = Stroke((2 * u).f, pathEffect = PathEffect.dashPathEffect(floatArrayOf((10 * u).f, (7 * u).f))))
    withAlpha(0.55) {
        val lw = cr * 1.2; val lh = lw * 0.42; val ccx = w / 2; val ccy = h * 0.5
        val ban = Path()
        ban.m(ccx - lw * 0.5, ccy - lh * 0.5); ban.q(ccx, ccy + lh * 1.1, ccx + lw * 0.5, ccy - lh * 0.6); ban.q(ccx, ccy + lh * 0.05, ccx - lw * 0.5, ccy - lh * 0.5); ban.close()
        fillPath(ban, rgb(1.0, 0.84, 0.1))
        strokePath(ban, lineC, 2 * u)
    }
    chest(chestX, chestY, chestSize)
    val minD = min(w, h); val maxD = max(w, h)
    drawRect(androidx.compose.ui.graphics.Brush.radialGradient(0f to Color.Transparent, (minD * 0.4 / (maxD * 0.75)).toFloat() to Color.Transparent,
        1f to Color.Black.op(0.28), center = off(w / 2, h * 0.45), radius = (maxD * 0.75).f))
}
