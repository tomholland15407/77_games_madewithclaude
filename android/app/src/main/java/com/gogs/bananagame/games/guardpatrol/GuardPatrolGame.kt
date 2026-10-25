package com.gogs.bananagame.games.guardpatrol

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
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/**
 * Brain — Guard Patrol (iOS GuardPatrolGame.swift, id "guard-patrol"): creep the banana from the
 * entrance into the vault box at the top, threading the sentries' sweeping cones. Getting spotted
 * trips the alarm and the edge guns open fire; a bullet or the clock fails. A high-tech vault facility.
 */
object GuardPatrolGame {
    val definition = GameDefinition(
        id = "guard-patrol",
        title = "Guard Patrol",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Hold a direction button to creep the banana from the bottom into the vault box at the top.",
                "The whole banana must be inside the vault.",
                "Stay out of the red vision cones — get spotted and the alarm trips.",
                "Then the edge guns open a fierce curtain; a bullet or the clock sends you to level 1.",
            ),
            bulletsVI = listOf(
                "Giữ nút hướng để đưa quả chuối từ dưới lên vào ô két sắt ở trên.",
                "Cả quả chuối phải nằm trọn trong két.",
                "Tránh xa các tầm nhìn đỏ — bị phát hiện là báo động.",
                "Khi đó súng hai bên xả một màn đạn; trúng đạn hoặc hết giờ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> GuardPatrolView(level, onWin, onFail) }
    )
}

private const val PLAYER_SPEED = 0.36
private const val VAULT_CY = 0.09
private const val VAULT_HX = 0.11
private const val VAULT_HY = 0.07
private const val WALL_X = 0.12                      // invisible side walls just inside the gun columns
private val GUN_YS = listOf(0.14, 0.24, 0.34, 0.44, 0.54, 0.64, 0.74, 0.84)
private const val BULLET_SPEED = 0.85
private const val FIRE_INTERVAL = 0.16

private class Sentry(val cx: Double, val cy: Double, val baseFacing: Double, val swing: Double, val moving: Boolean, val patrolHalf: Double, var t: Double) {
    /** Pivoting guards sweep with sin; patrolling guards face along their motion. */
    fun facing(t: Double = this.t) = if (moving) (if (cos(t) >= 0) 0.0 else PI) else baseFacing + sin(t) * swing
    /** Patrolling guards slide horizontally around their (clamped) base; pivoting guards stay put. */
    fun center(t: Double = this.t): P {
        if (!moving) return P(cx, cy)
        val base = min(0.92 - patrolHalf, max(0.08 + patrolHalf, cx))
        return P(base + sin(t) * patrolHalf, cy)
    }
}
private class SideBullet(var x: Double, val y: Double, val vx: Double)

private class PatrolWorld(val level: Int) {
    private val li = min(level, 7) - 1
    val guardN = listOf(3, 3, 4, 4, 5, 5, 6)[li]
    val sweepSpeed = listOf(1.3, 1.5, 1.7, 1.9, 2.1, 2.3, 2.5)[li]
    val coneHalf = listOf(29.0, 32.0, 35.0, 38.0, 42.0, 45.0, 48.0)[li] * PI / 180
    val coneRange = listOf(0.30, 0.33, 0.36, 0.39, 0.43, 0.46, 0.50)[li]
    val movingN = min(guardN, level)
    val timeLimit = listOf(26.0, 24.0, 22.0, 20.0, 18.0, 17.0, 16.0)[li]
    val fireProb = min(0.75, 0.42 + level * 0.05)

    var playing = true
    var guards = listOf<Sentry>()
    var px = 0.5; var py = 0.92
    // Snapshot state, so the keys re-light when the demo script (or a finger) changes them.
    var mdx by mutableDoubleStateOf(0.0)
    var mdy by mutableDoubleStateOf(0.0)
    var timeLeft = timeLimit
    var aw = 0.0; var ah = 0.0               // play area in px (cone reach scales with its short side)
    var alerted = false
    val bullets = mutableListOf<SideBullet>()
    var fireAcc = 0.0
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    fun setup() {
        px = 0.5; py = 0.92; mdx = 0.0; mdy = 0.0
        // Spread guards across the middle bands, and across nearly the full playable width.
        guards = (0 until guardN).map { i ->
            val band = i.toDouble() / max(1, guardN)
            val moving = i < movingN
            Sentry(rnd(WALL_X + 0.03, 1 - WALL_X - 0.03), 0.24 + band * 0.5 + rnd(-0.03, 0.03),
                if (moving) 0.0 else rnd(0.0, 2 * PI), if (moving) 0.0 else rnd(0.7, 1.1), moving, rnd(0.18, 0.30), rnd(0.0, 2 * PI))
        }
        alerted = false; bullets.clear(); fireAcc = 0.0
        timeLeft = timeLimit; playing = true
    }

    /** A fixed level-1 room: one patrolling guard, two pivoting. */
    fun demoSetup() {
        px = 0.5; py = 0.92; mdx = 0.0; mdy = 0.0
        guards = listOf(
            Sentry(0.2457, 0.2113, 0.0, 0.0, true, 0.251, 4.4174),
            Sentry(0.1688, 0.4021, 0.9688, 0.757, false, 0.2998, 5.9271),
            Sentry(0.5013, 0.549, 3.1613, 0.7753, false, 0.2389, 5.3294),
        )
        alerted = false; bullets.clear(); fireAcc = 0.0
        timeLeft = timeLimit; playing = true
    }

    private fun inCone(x: Double, y: Double, g: Sentry, t: Double, rangeK: Double, halfExtra: Double): Boolean {
        val c = g.center(t)
        val dx = (x - c.x) * aw; val dy = (y - c.y) * ah
        val d = hypot(dx, dy)
        if (d > coneRange * min(aw, ah) * rangeK || d < 0.0001) return false
        var diff = atan2(dy, dx) - g.facing(t)
        while (diff > PI) diff -= 2 * PI
        while (diff < -PI) diff += 2 * PI
        return abs(diff) <= coneHalf + halfExtra
    }

    /** Demo planner: would the banana at (x, y) be inside a margin-widened cone k frames from now? */
    fun demoSeen(x: Double, y: Double, k: Int) = guards.any { inCone(x, y, it, it.t + k / 60.0 * sweepSpeed, 1.12, 8 * PI / 180) }

    /** Climb if the next 0.45 s of climbing stays clear, else hold still if that's clear, else back off. */
    fun demoWant(): Double {
        fun clear(dy: Double): Boolean {
            for (k in 1..27) if (demoSeen(px, min(0.97, max(0.03, py + dy * PLAYER_SPEED * k / 60)), k)) return false
            return true
        }
        return if (clear(-1.0)) -1.0 else if (clear(0.0)) 0.0 else if (clear(1.0)) 1.0 else 0.0
    }

    fun step(dt: Double) {
        if (!playing) return
        for (g in guards) g.t += dt * sweepSpeed
        val mag = hypot(mdx, mdy)
        if (mag > 0) {
            px = min(1 - WALL_X, max(WALL_X, px + mdx / mag * PLAYER_SPEED * dt))
            py = min(0.97, max(0.03, py + mdy / mag * PLAYER_SPEED * dt))
        }
        if (aw <= 1 || ah <= 1) return
        // Win: the WHOLE banana must sit inside the vault box.
        val bananaHalf = min(aw, ah) * 0.03
        if (abs(px - 0.5) <= VAULT_HX - bananaHalf / aw && abs(py - VAULT_CY) <= VAULT_HY - bananaHalf / ah) { win(); return }
        // Detection raises the alarm (once) instead of failing outright.
        if (!alerted && guards.any { inCone(px, py, it, it.t, 1.0, 0.0) }) { alerted = true; SoundManager.error(); Haptics.warning() }
        if (!alerted) return
        // Once alerted, the flanking guns pour a fierce horizontal curtain across the field.
        fireAcc += dt
        if (fireAcc >= FIRE_INTERVAL) {
            fireAcc = 0.0
            for (gy in GUN_YS) {
                if (Random.nextDouble() < fireProb) bullets.add(SideBullet(0.03, gy, BULLET_SPEED))
                if (Random.nextDouble() < fireProb) bullets.add(SideBullet(0.97, gy, -BULLET_SPEED))
            }
            SoundManager.tap()
        }
        for (b in bullets) b.x += b.vx * dt
        bullets.removeAll { it.x < -0.05 || it.x > 1.05 }
        if (bullets.any { abs(it.x - px) < 0.028 && abs(it.y - py) < 0.03 }) fail()
    }

    fun win() { if (!playing) return; playing = false; Haptics.success(); SoundManager.tap(); onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }
}

@Composable
private fun GuardPatrolView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { PatrolWorld(level).also { if (isDemo) it.demoSetup() else it.setup() } }
    world.onWin = onWin; world.onFail = onFail
    var demoTick by remember { mutableIntStateOf(0) }
    val start = remember { nowSec() }
    val tick by rememberFrameLoop { dt ->
        if (isDemo || !world.playing) return@rememberFrameLoop
        world.timeLeft = max(0.0, world.timeLimit - (nowSec() - start))
        if (world.timeLeft <= 0) { world.fail(); return@rememberFrameLoop }
        world.step(dt)
    }

    // Demo: creep ▲ up the middle; when a sweep is about to cross the lane, let go and freeze
    // (resuming only after ≥ 10 frames so the press reads), then slip into the vault.
    LaunchedEffect(Unit) {
        if (!isDemo) return@LaunchedEffect
        while (isActive) {
            world.demoSetup()
            delay(500)
            var frame = 0; var state: Double? = null; var last = 0
            while (isActive && world.playing && frame < 900) {
                frame++
                val want = world.demoWant()
                if (state == null) { state = want; last = frame }
                else if (want != state && (frame - last >= 10 || want != -1.0)) { state = want; last = frame }
                world.mdx = 0.0; world.mdy = state ?: 0.0
                world.step(1.0 / 60)
                demoTick++
                delay(16)
            }
            world.mdx = 0.0; world.mdy = 0.0
            delay(1300)
        }
    }

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .background(rgb(0.05, 0.06, 0.09)),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        tick; demoTick
        // The alarm lamp: dark until a cone catches the banana, then red.
        Canvas(Modifier.padding(top = if (isDemo) 6.dp else 0.dp).size(if (isDemo) 18.dp else 24.dp)) { alarmLamp(world.alerted) }
        if (!isDemo) {
            val f = world.timeLeft / world.timeLimit
            TimeBar(f, Modifier.fillMaxWidth().padding(horizontal = 56.dp).height(5.dp), fill = if (f < 0.3) rgb(1.0, 0.3, 0.26) else rgb(0.4, 0.85, 1.0))
        }
        Canvas(
            Modifier.fillMaxWidth().weight(1f).padding(horizontal = if (isDemo) 8.dp else 0.dp).clip(RoundedCornerShape(14.dp))
                .onSizeChanged { world.aw = it.width.toDouble(); world.ah = it.height.toDouble() }
                .drawWithCache { onDrawBehind { facility() } }
        ) {
            tick; demoTick
            scene(world)
        }
        val kw = if (isDemo) 56.dp else 62.dp; val kh = if (isDemo) 32.dp else 50.dp
        @Composable fun key(dx: Double, dy: Double, icon: ImageVector) = HoldKey(world, dx, dy, icon, isDemo, kw, kh)
        if (isDemo) {
            // The squat demo card can't spare a 2-row cross: same four buttons, one row.
            Row(Modifier.padding(bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                key(-1.0, 0.0, Icons.Filled.KeyboardArrowLeft); key(0.0, -1.0, Icons.Filled.KeyboardArrowUp)
                key(0.0, 1.0, Icons.Filled.KeyboardArrowDown); key(1.0, 0.0, Icons.Filled.KeyboardArrowRight)
            }
        } else {
            Column(Modifier.padding(bottom = 8.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                key(0.0, -1.0, Icons.Filled.KeyboardArrowUp)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    key(-1.0, 0.0, Icons.Filled.KeyboardArrowLeft); key(0.0, 1.0, Icons.Filled.KeyboardArrowDown); key(1.0, 0.0, Icons.Filled.KeyboardArrowRight)
                }
            }
        }
    }
}

/** Steel d-pad keys (banana yellow while held). */
@Composable
private fun HoldKey(world: PatrolWorld, dx: Double, dy: Double, icon: ImageVector, isDemo: Boolean, w: androidx.compose.ui.unit.Dp, h: androidx.compose.ui.unit.Dp) {
    val lit = isDemo && world.mdx == dx && world.mdy == dy      // as on iOS, only the demo's presses light up
    Box(
        Modifier.scale(if (lit) 0.9f else 1f).size(w, h)
            .then(if (isDemo) Modifier else Modifier.pressDown(
                onDown = { if (world.playing) { world.mdx = dx; world.mdy = dy } },
                onUp = { world.mdx = 0.0; world.mdy = 0.0 })),
        contentAlignment = Alignment.Center
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val u = density.toDouble(); val bw = size.width.toDouble(); val bh = size.height.toDouble(); val r = 12 * u
            rrect(0.0, 0.0, bw, bh, r, vgrad(if (lit) listOf(rgb(1.0, 0.9, 0.45), rgb(0.95, 0.72, 0.16)) else listOf(rgb(0.3, 0.34, 0.42), rgb(0.16, 0.18, 0.24)), 0.0, bh))
            rrectStroke(u, u, bw - 2 * u, bh - 2 * u, r - u, Color.Black.op(0.5), 2 * u)
            rrectStroke(3.5 * u, 3.5 * u, bw - 7 * u, bh - 7 * u, r - 3 * u, Color.White.op(if (lit) 0.9 else 0.2), u)
        }
        Icon(icon, null, tint = if (lit) rgb(0.2, 0.12, 0.0) else Color.White, modifier = Modifier.size(if (isDemo) 22.dp else 28.dp))
    }
}

// Vault-facility art (iOS GPArt).

private val GPRed = rgb(1.0, 0.22, 0.22)

private fun DrawScope.scene(world: PatrolWorld) {
    val u = density.toDouble(); val w = size.width.toDouble(); val h = size.height.toDouble(); val m = min(w, h)
    val gunW = m * 0.045
    for (gy in GUN_YS) { turret(0.02 * w, gy * h, gunW, true, world.alerted); turret(0.98 * w, gy * h, gunW, false, world.alerted) }
    for (b in world.bullets) tracer(b.x * w, b.y * h, if (b.vx >= 0) 1.0 else -1.0, m)
    val range = world.coneRange * m
    for (g in world.guards) { val c = g.center(); cone(c.x * w, c.y * h, g.facing(), world.coneHalf, range) }
    for (g in world.guards) { val c = g.center(); sentry(c.x * w, c.y * h, g.facing(), m * 0.05, g.moving) }
    thief(world.px * w, world.py * h, m * 0.06)
    if (world.alerted) rrectStroke(2 * u, 2 * u, w - 4 * u, h - 4 * u, 12 * u, rgb(1.0, 0.2, 0.2, 0.8), 4 * u)
}

/** A wall-mounted sentry turret; it glows red once the alarm is up. */
private fun DrawScope.turret(px: Double, py: Double, s: Double, facingRight: Boolean, alerted: Boolean) {
    translate(px.f, py.f) { scale(if (facingRight) 1f else -1f, 1f, Offset.Zero) {
        rrect(-s * 0.5, -s * 0.5, s, s, s * 0.2, vgrad(listOf(gray(0.42), gray(0.2)), -s * 0.5, s * 0.5))
        rrect(s * 0.2, -s * 0.14, s * 0.9, s * 0.28, s * 0.08, gray(0.16))
        circle(0.0, 0.0, s * 0.18, if (alerted) GPRed else gray(0.35))
        if (alerted) circle(0.0, 0.0, s * 0.48, radial(listOf(GPRed.op(0.5), GPRed.op(0.0)), 0.0, 0.0, s * 0.5))
    } }
}

/** A tracer round streaking across the floor. */
private fun DrawScope.tracer(px: Double, py: Double, dir: Double, m: Double) {
    val len = m * 0.06; val r = m * 0.013
    drawLine(hgrad(listOf(rgb(1.0, 0.6, 0.2, 0.0), rgb(1.0, 0.75, 0.3)), px - dir * len, px), off(px - dir * len, py), off(px, py), (r * 1.4).f, StrokeCap.Round)
    circle(px, py, r, rgb(1.0, 0.92, 0.7))
}

/** A red scanner cone — the detection apex, reach and angle. */
private fun DrawScope.cone(cx: Double, cy: Double, facing: Double, half: Double, range: Double) {
    val u = density.toDouble()
    val p = Path(); p.m(cx, cy)
    for (s in 0..24) { val a = facing - half + 2 * half * s / 24; p.l(cx + cos(a) * range, cy + sin(a) * range) }
    p.close()
    drawPath(p, radial(listOf(GPRed.op(0.42), GPRed.op(0.14)), cx, cy, range))
    line(cx, cy, cx + cos(facing) * range, cy + sin(facing) * range, GPRed.op(0.55), u, StrokeCap.Butt)
    drawPath(p, GPRed.op(0.7), style = Stroke((1.2 * u).f))
}

/** A sentry bot from above: a domed steel body with a red eye; patrolling bots ride a hover ring. */
private fun DrawScope.sentry(cx: Double, cy: Double, facing: Double, s: Double, moving: Boolean) {
    val u = density.toDouble(); val r = s / 2
    if (moving) circleStroke(cx, cy, r * 1.25, rgb(0.4, 0.85, 1.0, 0.5), 2 * u)
    circle(cx, cy, r, radial(listOf(gray(0.85), gray(0.5), gray(0.25)), cx - r * 0.3, cy - r * 0.3, r * 1.3))
    circleStroke(cx, cy, r, Color.Black.op(0.6), 1.5 * u)
    val ex = cx + cos(facing) * r * 0.55; val ey = cy + sin(facing) * r * 0.55
    circle(ex, ey, r * 0.45, radial(listOf(GPRed.op(0.8), GPRed.op(0.0)), ex, ey, r * 0.45))
    circle(ex, ey, r * 0.2, rgb(1.0, 0.5, 0.5))
}

/** The thief: a banana in a black eye-mask, drawn inside the same box the win check uses. */
private fun DrawScope.thief(px: Double, py: Double, s: Double) {
    translate(px.f, py.f) { scale(s.f, s.f, Offset.Zero) {
        val ink = rgb(0.14, 0.1, 0.03)
        val body = Path(); body.m(-0.06, -0.48); body.c(-0.5, -0.2, -0.44, 0.4, 0.1, 0.48); body.c(0.16, 0.2, 0.24, -0.2, -0.06, -0.48); body.close()
        drawPath(body, hgrad(listOf(rgb(0.95, 0.72, 0.14), rgb(1.0, 0.94, 0.45)), -0.35, 0.1))
        strokePath(body, ink, 0.05)
        rrect(-0.34, -0.24, 0.48, 0.14, 0.06, gray(0.08))
        for (x in listOf(-0.22, 0.0)) oval(x - 0.04, -0.21, 0.09, 0.08, Color.White)
        rrect(-0.1, -0.52, 0.08, 0.1, 0.02, rgb(0.42, 0.27, 0.08))
    } }
}

/** The facility: floor panels, hazard-edged side walls, the vault chamber (the win box), the lift. */
private fun DrawScope.facility() {
    val u = density.toDouble(); val w = size.width.toDouble(); val h = size.height.toDouble()
    rect(0.0, 0.0, w, h, rgb(0.1, 0.12, 0.17))
    val seams = Path(); val tile = min(w, h) * 0.1
    var x = WALL_X * w
    while (x < (1 - WALL_X) * w) { seams.m(x, 0.0); seams.l(x, h); x += tile }
    var y = 0.0
    while (y < h) { seams.m(WALL_X * w, y); seams.l((1 - WALL_X) * w, y); y += tile }
    strokePath(seams, rgb(0.4, 0.7, 1.0, 0.12), u, StrokeCap.Butt)
    for ((x0, x1) in listOf(0.0 to WALL_X * w, (1 - WALL_X) * w to w)) {
        rect(x0, 0.0, x1 - x0, h, hgrad(listOf(gray(0.2), gray(0.12)), x0, x1))
        val edgeX = if (x0 == 0.0) x1 - 4 * u else x0
        clipRect(edgeX.f, 0f, (edgeX + 4 * u).f, h.f) {
            var k = -8 * u
            while (k < h) { rect(edgeX, k, 4 * u, 6 * u, rgb(1.0, 0.78, 0.1)); k += 12 * u }
        }
    }
    // Vault chamber — exactly the region the banana must fit inside.
    val vx = w * (0.5 - VAULT_HX); val vy = h * (VAULT_CY - VAULT_HY); val vw = w * VAULT_HX * 2; val vh = h * VAULT_HY * 2
    rrect(vx - 6 * u, vy - 6 * u, vw + 12 * u, vh + 12 * u, 12 * u, gray(0.3))
    rrect(vx, vy, vw, vh, 8 * u, radial(listOf(rgb(1.0, 0.85, 0.3, 0.45), rgb(0.2, 0.16, 0.06)), vx + vw / 2, vy + vh / 2, vw * 0.6))
    rrectStroke(vx, vy, vw, vh, 8 * u, rgb(1.0, 0.84, 0.3), 2 * u)
    for (k in 0 until 8) {
        val a = k / 8.0 * 2 * PI
        circle(vx + vw / 2 + cos(a) * (vw / 2 + 3 * u), vy + vh / 2 + sin(a) * (vh / 2 + 3 * u), 2 * u, gray(0.6))
    }
    // A golden banana on its plinth in the vault's back corner.
    val gx = vx + vw - vw * 0.22; val gy = vy + vh * 0.3
    val gold = Path(); gold.m(gx - 7 * u, gy - 2 * u); gold.q(gx, gy + 8 * u, gx + 7 * u, gy - 3 * u); gold.q(gx, gy + 2 * u, gx - 7 * u, gy - 2 * u); gold.close()
    fillPath(gold, rgb(1.0, 0.84, 0.3))
    // Entrance lift at the bottom.
    rrect(w * 0.2, 0.945 * h, w * 0.6, h * 0.05, 6 * u, rgb(0.4, 0.85, 1.0, 0.12))
    val lift = Path().apply { addRoundRect(androidx.compose.ui.geometry.RoundRect((w * 0.2).f, (0.945 * h).f, (w * 0.8).f, (0.995 * h).f, androidx.compose.ui.geometry.CornerRadius((6 * u).f))) }
    drawPath(lift, rgb(0.4, 0.85, 1.0, 0.5), style = Stroke((1.5 * u).f, pathEffect = PathEffect.dashPathEffect(floatArrayOf((6 * u).f, (4 * u).f))))
}

/** The header's alarm lamp. */
private fun DrawScope.alarmLamp(on: Boolean) {
    val w = size.width.toDouble(); val h = size.height.toDouble()
    if (on) circle(w / 2, h / 2, w / 2, radial(listOf(GPRed.op(0.6), GPRed.op(0.0)), w / 2, h / 2, w / 2))
    val dx = w * 0.2; val dw = w * 0.6; val dBottom = h * 0.82
    val dome = Path(); dome.m(dx, dBottom)
    for (s in 0..20) { val a = PI + PI * s / 20; dome.l(dx + dw / 2 + cos(a) * dw / 2, dBottom + sin(a) * dw / 2) }
    dome.close()
    fillPath(dome, if (on) GPRed else gray(0.35))
    rrect(w * 0.14, dBottom, w * 0.72, h * 0.14, 2 * density.toDouble(), gray(0.55))
}
