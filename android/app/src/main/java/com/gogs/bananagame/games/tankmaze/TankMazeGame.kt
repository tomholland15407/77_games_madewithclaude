package com.gogs.bananagame.games.tankmaze

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Reflex — Tank Maze (iOS TankMazeGame.swift): a top-down Tank Trouble duel in an open block
 * arena. Joystick drives, FIRE launches a ricocheting shell that stays live for seconds; any shell
 * kills any tank. Destroy every enemy to win.
 */
object TankMazeGame {
    val definition = GameDefinition(
        id = "tank-maze",
        title = "Tank Maze",
        genre = Genre.REFLEX,
        locksFeed = true,
        manual = GameManual(
            bullets = listOf(
                "Drive with the joystick; the turret points where you steer.",
                "Tap FIRE to launch a shell that ricochets off walls and stays live for seconds.",
                "Destroy every enemy tank to win.",
                "Any bouncing shell — even your own — is lethal.",
            ),
            bulletsVI = listOf(
                "Lái bằng cần điều khiển; nòng pháo hướng theo nơi bạn lái.",
                "Chạm BẮN để phóng đạn nảy khỏi tường và còn sống vài giây.",
                "Phá hủy mọi xe tăng địch để thắng.",
                "Mọi viên đạn đang nảy — kể cả của bạn — đều chết người.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> TankMazeView(level, onWin, onFail) }
    )
}

private const val COLS = 13
private const val ROWS = 17
private const val TRIM = 0.7

private data class TP(val r: Int, val c: Int)
private class Tank(var x: Double, var y: Double, var facing: Double, var fireCD: Double, var roam: TP, var repick: Double, var tint: Int = 0)
private class Shell(var x: Double, var y: Double, var vx: Double, var vy: Double, var life: Double, var arm: Double, val fromPlayer: Boolean)
private class Burst(val x: Double, val y: Double, val t0: Double = nowSec())

/** The whole duel as plain state, stepped by the frame loop. */
private class TankWorld(val level: Int) {
    val enemyCount = listOf(1, 2, 2, 3, 3, 4, 4)[min(level, 7) - 1]
    val enemySpeed = listOf(1.2, 1.4, 1.5, 1.7, 1.9, 2.1, 2.3)[min(level, 7) - 1]
    val enemyFire = listOf(2.2, 2.0, 1.7, 1.5, 1.3, 1.1, 0.95)[min(level, 7) - 1]
    val coverBlocks = 4 + level
    val baseTime = (30 + enemyCount * 12).toDouble()
    val playerSpeed = 3.4
    val playerShootCD = 0.5
    val maxPlayerShots = 4
    val shellSpeed = 5.0
    val shellLife = 6.0
    val shellArm = 0.12

    var playing = true
    var walls = Array(ROWS) { BooleanArray(COLS) }
    var enemies = mutableListOf<Tank>()
    var shells = mutableListOf<Shell>()
    var px = 1.5; var py = 1.5
    var playerFacing = 0.0
    var sx = 0.0; var sy = 0.0
    var shootCD = 0.0
    var timeLeft = baseTime
    var bursts = mutableListOf<Burst>()
    var shakeT0 = -10.0
    var scorches = mutableListOf<Pair<Double, Double>>()
    var killed = mutableListOf<Int>()
    var playerHit = false
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    fun isWall(r: Int, c: Int): Boolean = if (r < 0 || r >= ROWS || c < 0 || c >= COLS) true else walls[r][c]

    fun canStand(x: Double, y: Double): Boolean {
        val rad = 0.30
        for (cx in doubleArrayOf(x - rad, x + rad)) for (cy in doubleArrayOf(y - rad, y + rad))
            if (isWall(floor(cy).toInt(), floor(cx).toInt())) return false
        return true
    }

    fun angleDiff(a: Double, b: Double): Double {
        var d = a - b
        while (d > PI) d -= 2 * PI
        while (d < -PI) d += 2 * PI
        return d
    }

    fun losClear(ax: Double, ay: Double, bx: Double, by: Double): Boolean {
        val steps = (hypot(bx - ax, by - ay) / 0.15).toInt() + 1
        for (i in 0..steps) {
            val t = i.toDouble() / steps
            if (isWall(floor(ay + (by - ay) * t).toInt(), floor(ax + (bx - ax) * t).toInt())) return false
        }
        return true
    }

    fun randomOpenCell(): TP {
        repeat(40) {
            val r = rndInt(1 until ROWS - 1); val c = rndInt(1 until COLS - 1)
            if (!isWall(r, c)) return TP(r, c)
        }
        return TP(1, 1)
    }

    fun setup() {
        val w = Array(ROWS) { BooleanArray(COLS) }
        for (r in 0 until ROWS) { w[r][0] = true; w[r][COLS - 1] = true }
        for (c in 0 until COLS) { w[0][c] = true; w[ROWS - 1][c] = true }
        var placed = 0; var tries = 0
        while (placed < coverBlocks && tries < 300) {
            tries++
            val bw = rndInt(1..3); val bh = rndInt(1..3)
            val c0 = rndInt(2..(COLS - 2 - bw)); val r0 = rndInt(2..(ROWS - 2 - bh))
            var ok = true
            for (r in (r0 - 1)..(r0 + bh)) for (c in (c0 - 1)..(c0 + bw)) if (w[r][c]) ok = false
            if (!ok) continue
            for (r in r0 until r0 + bh) for (c in c0 until c0 + bw) w[r][c] = true
            placed++
        }
        walls = w
        val open = (0 until ROWS).flatMap { r -> (0 until COLS).mapNotNull { c -> if (w[r][c]) null else TP(r, c) } }
        val starts = mutableListOf<TP>()
        for (cand in open.shuffled()) {
            if (starts.all { manhattan(it, cand) >= 4 }) { starts.add(cand); if (starts.size == enemyCount) break }
        }
        while (starts.size < enemyCount) starts.add(open.pick())
        enemies = starts.map { s ->
            Tank(s.c + 0.5, s.r + 0.5, rnd(0.0, 2 * PI), rnd(0.6, enemyFire), randomOpenCell(), rnd(1.2, 2.6))
        }.toMutableList()
        val startCell = open.maxByOrNull { p -> starts.minOf { manhattan(it, p) } } ?: TP(1, 1)
        px = startCell.c + 0.5; py = startCell.r + 0.5
        playerFacing = 0.0
        sx = 0.0; sy = 0.0; shells.clear(); bursts.clear(); shootCD = 0.0
        enemies.forEachIndexed { i, e -> e.tint = i }
        scorches.clear(); killed.clear(); playerHit = false
        timeLeft = baseTime
        playing = true
    }

    fun demoSetup() {
        val w = Array(ROWS) { BooleanArray(COLS) }
        for (r in 0 until ROWS) { w[r][0] = true; w[r][COLS - 1] = true }
        for (c in 0 until COLS) { w[0][c] = true; w[ROWS - 1][c] = true }
        for ((r, c) in listOf(4 to 4, 4 to 5, 12 to 6, 12 to 7, 5 to 9)) w[r][c] = true
        walls = w
        px = 3.5; py = 8.5; playerFacing = 0.0
        enemies = mutableListOf(Tank(9.5, 8.5, PI, 9999.0, TP(8, 9), 9999.0))
        shells.clear(); bursts.clear(); sx = 0.0; sy = 0.0; shootCD = 0.0
        scorches.clear(); killed.clear(); playerHit = false
        timeLeft = baseTime
        playing = true
    }

    private fun manhattan(a: TP, b: TP) = abs(a.r - b.r) + abs(a.c - b.c)

    fun step(dt: Double) {
        if (!playing) return
        bursts.firstOrNull()?.let { if (nowSec() - it.t0 > 1.0) bursts.removeAt(0) }
        val vx = sx * playerSpeed * dt; val vy = sy * playerSpeed * dt
        if (canStand(px + vx, py)) px += vx
        if (canStand(px, py + vy)) py += vy
        if (hypot(sx, sy) > 0.08) {
            val target = atan2(sy, sx)
            playerFacing += angleDiff(target, playerFacing) * min(1.0, dt * 14.0)
        }
        shootCD = max(0.0, shootCD - dt)
        for (e in enemies) {
            roamStep(e, dt)
            e.fireCD -= dt
            if (e.fireCD <= 0 && losClear(e.x, e.y, px, py)) {
                val a = atan2(py - e.y, px - e.x)
                e.facing = a
                e.fireCD = enemyFire
                fire(e.x, e.y, a, false)
            }
        }
        if (!stepShells(dt)) return
        timeLeft -= dt
        if (timeLeft <= 0) { timeLeft = 0.0; fail() }
    }

    fun stepShells(dt: Double): Boolean {
        val survivors = mutableListOf<Shell>()
        for (s in shells) {
            s.arm = max(0.0, s.arm - dt)
            s.life -= dt
            if (s.life <= 0) continue
            val nx = s.x + s.vx * dt
            if (isWall(floor(s.y).toInt(), floor(nx).toInt())) s.vx = -s.vx else s.x = nx
            val ny = s.y + s.vy * dt
            if (isWall(floor(ny).toInt(), floor(s.x).toInt())) s.vy = -s.vy else s.y = ny
            if (s.arm <= 0) {
                if (hypot(px - s.x, py - s.y) < 0.5) {
                    bursts.add(Burst(px, py)); scorches.add(px to py)
                    playerHit = true; shakeT0 = nowSec()
                    fail(); return false
                }
                val hit = enemies.indexOfFirst { hypot(it.x - s.x, it.y - s.y) < 0.5 }
                if (hit >= 0) {
                    val e = enemies[hit]
                    bursts.add(Burst(e.x, e.y)); scorches.add(e.x to e.y)
                    killed.add(e.tint)
                    enemies.removeAt(hit)
                    shakeT0 = nowSec()
                    Haptics.tap(); SoundManager.tap()
                    continue
                }
            }
            survivors.add(s)
        }
        shells = survivors
        if (enemies.isEmpty()) { win(); return false }
        return true
    }

    fun shoot() {
        if (!playing || shootCD > 0) return
        if (shells.count { it.fromPlayer } >= maxPlayerShots) return
        shootCD = playerShootCD
        fire(px, py, playerFacing, true)
        SoundManager.tap(); Haptics.tap()
    }

    fun fire(x: Double, y: Double, angle: Double, fromPlayer: Boolean) {
        shells.add(Shell(x + cos(angle) * 0.55, y + sin(angle) * 0.55, cos(angle) * shellSpeed, sin(angle) * shellSpeed, shellLife, shellArm, fromPlayer))
    }

    fun win() { if (!playing) return; playing = false; Haptics.success(); SoundManager.tap(); onWin() }
    fun fail() { if (!playing) return; playing = false; Haptics.warning(); SoundManager.error(); onFail() }

    fun roamStep(e: Tank, dt: Double) {
        e.repick -= dt
        val tx = e.roam.c + 0.5; val ty = e.roam.r + 0.5
        val dx = tx - e.x; val dy = ty - e.y
        val d = hypot(dx, dy)
        if (d < 0.35 || e.repick <= 0) { e.roam = randomOpenCell(); e.repick = rnd(1.6, 3.2) }
        if (d <= 0.0001) return
        val sp = enemySpeed * dt
        val mx = dx / d * sp; val my = dy / d * sp
        var moved = false
        if (canStand(e.x + mx, e.y)) { e.x += mx; moved = true }
        if (canStand(e.x, e.y + my)) { e.y += my; moved = true }
        if (!moved) e.repick = 0.0
        e.facing += angleDiff(atan2(dy, dx), e.facing) * min(1.0, dt * 10.0)
    }
}

@Composable
private fun TankMazeView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { TankWorld(level).also { if (!isDemo) it.setup() } }
    world.onWin = onWin; world.onFail = onFail
    var demoFire by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    val tick by rememberFrameLoop(running = !isDemo) { dt -> world.step(dt) }
    var demoTick by remember { mutableStateOf(0) }

    LaunchedEffect(Unit) {
        if (!isDemo) return@LaunchedEffect
        while (isActive) {
            world.demoSetup(); demoTick++
            delay(700)
            demoFire = true
            world.shoot()
            scope.launch { delay(180); demoFire = false }
            var frames = 0
            while (world.playing && world.enemies.isNotEmpty() && frames < 260) {
                world.stepShells(0.016)
                demoTick++
                delay(16)
                frames++
            }
            demoTick++
            delay(1200)
        }
    }

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp)
            .clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp)).background(TankArt.card)
            .padding(horizontal = if (isDemo) 8.dp else 12.dp).padding(top = if (isDemo) 8.dp else 14.dp, bottom = if (isDemo) 8.dp else 12.dp),
        verticalArrangement = Arrangement.spacedBy(if (isDemo) 6.dp else 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // HUD: one tank icon per enemy, greyed once destroyed.
        tick; demoTick
        val icons = (world.enemies.map { it.tint to true } + world.killed.map { it to false }).sortedBy { it.first }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(if (isDemo) 0.dp else 8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(if (isDemo) 8.dp else 12.dp)) {
                for ((tint, alive) in icons) {
                    Canvas(Modifier.size(if (isDemo) 28.dp else 36.dp, if (isDemo) 20.dp else 26.dp).alpha(if (alive) 1f else 0.55f)) {
                        TankArt.tank(this, size.width * 0.44, size.height / 2.0, 0.0, size.height * 1.02, if (alive) TankArt.enemy(tint) else gray(0.72))
                    }
                }
            }
            if (!isDemo) {
                TimeBar(world.timeLeft / world.baseTime, Modifier.fillMaxWidth().padding(horizontal = 40.dp).height(6.dp)
                    .border(1.dp, Color.Black.op(0.15), RoundedCornerShape(50)), track = gray(0.8))
            }
        }
        // Arena.
        Canvas(
            Modifier.fillMaxWidth().weight(1f).clip(RoundedCornerShape(if (isDemo) 8.dp else 12.dp))
                .graphicsLayer {
                    val t = nowSec() - world.shakeT0
                    if (t in 0.0..0.35) {
                        val k = sin(t / 0.35 * PI * 3)
                        translationX = (6 * density * k).toFloat(); translationY = (6 * 0.6 * density * k).toFloat()
                    }
                }
        ) {
            tick; demoTick
            val spanX = COLS - 2 * TRIM
            val spanY = if (isDemo) 7.0 else ROWS - 2 * TRIM
            val top = if (isDemo) 5.0 else TRIM
            val cell = max(1.0, min(size.width / spanX, size.height / spanY))
            val ox = (size.width - cell * spanX) / 2 - TRIM * cell
            val oy = (size.height - cell * spanY) / 2 - top * cell
            drawArena(world.walls, cell, ox, oy)
            fun ptx(x: Double) = ox + x * cell
            fun pty(y: Double) = oy + y * cell
            for ((x, y) in world.scorches) TankArt.scorch(this, ptx(x), pty(y), cell)
            for (e in world.enemies) TankArt.tank(this, ptx(e.x), pty(e.y), e.facing, cell, TankArt.enemy(e.tint))
            if (!world.playerHit) TankArt.tank(this, ptx(world.px), pty(world.py), world.playerFacing, cell, TankArt.you)
            for (s in world.shells) TankArt.bullet(this, ptx(s.x), pty(s.y), cell)
            val now = nowSec()
            for (b in world.bursts) TankArt.explosion(this, ptx(b.x), pty(b.y), cell, now - b.t0)
        }
        // Controls: joystick + FIRE.
        Row(Modifier.fillMaxWidth().padding(horizontal = if (isDemo) 14.dp else 20.dp), verticalAlignment = Alignment.CenterVertically) {
            TankJoystick(if (isDemo) 74.0 else 120.0, enabled = !isDemo) { x, y -> world.sx = x; world.sy = y }
            Spacer(Modifier.weight(1f))
            val sc by animateFloatAsState(if (demoFire) 0.9f else 1f, tween(100), label = "f")
            Box(
                Modifier.scale(sc).size(if (isDemo) 78.dp else 100.dp, if (isDemo) 50.dp else 70.dp)
                    .shadow(if (demoFire) 1.dp else 4.dp, RoundedCornerShape(16.dp))
                    .background(if (demoFire) BananaTheme.banana else TankArt.wall, RoundedCornerShape(16.dp))
                    .border(if (demoFire) 3.dp else 1.5.dp, if (demoFire) Color.White else Color.Black.op(0.35), RoundedCornerShape(16.dp))
                    .pressDown(onDown = { if (!isDemo) world.shoot() }),
                contentAlignment = Alignment.Center
            ) {
                Text(L("FIRE", "BẮN"), style = ts(if (isDemo) 17.0 else 20.0, FontWeight.Black, if (demoFire) Color.Black else Color.White))
            }
        }
    }
}

/** Relative analog stick; snaps back on release. Reports a vector with length ≤ 1. */
@Composable
private fun TankJoystick(sizeDp: Double, enabled: Boolean, onVector: (Double, Double) -> Unit) {
    var knob by remember { mutableStateOf(P.zero) }
    val sizePx = sizeDp * androidx.compose.ui.platform.LocalDensity.current.density
    Box(
        Modifier.size(sizeDp.dp)
            .background(Brush.radialGradient(listOf(gray(0.74), gray(0.84))), CircleShape)
            .border(2.dp, gray(0.6), CircleShape)
            .then(if (enabled) Modifier.touchDrag(
                onMove = { s, n ->
                    val maxR = sizePx * 0.30
                    var dx = n.x - s.x; var dy = n.y - s.y
                    val len = hypot(dx, dy)
                    if (len > maxR) { dx = dx / len * maxR; dy = dy / len * maxR }
                    knob = P(dx, dy)
                    onVector(dx / maxR, dy / maxR)
                },
                onEnd = { _, _ -> knob = P.zero; onVector(0.0, 0.0) }
            ) else Modifier),
        contentAlignment = Alignment.Center
    ) {
        val b = BananaTheme.banana
        Box(
            Modifier.offset { IntOffset(knob.x.roundToInt(), knob.y.roundToInt()) }
                .size((sizeDp * 0.42).dp)
                .shadow(3.dp, CircleShape)
                .background(Brush.radialGradient(listOf(b.lit(0.35), b, b.shade(0.2))), CircleShape)
                .border(2.dp, b.shade(0.55), CircleShape)
        )
    }
}

private fun DrawScope.drawArena(walls: Array<BooleanArray>, cell: Double, ox: Double, oy: Double) {
    drawRect(TankArt.card)
    fun rect(r: Int, c: Int): DoubleArray {
        var x = ox + c * cell; var y = oy + r * cell; var w = cell; var h = cell
        val keep = cell * (1 - TRIM)
        if (r == 0) { y = y + h - keep; h = keep }
        if (r == ROWS - 1) h = keep
        if (c == 0) { x = x + w - keep; w = keep }
        if (c == COLS - 1) w = keep
        return doubleArrayOf(x, y, w, h)
    }
    for (r in 0 until ROWS) for (c in 0 until COLS) if (!walls[r][c]) {
        val q = rect(r, c)
        rect(q[0] - 0.3, q[1] - 0.3, q[2] + 0.6, q[3] + 0.6, if ((r + c) % 2 == 0) gray(0.97) else gray(0.935))
    }
    for (r in 0 until ROWS) for (c in 0 until COLS) if (walls[r][c]) {
        val q = rect(r, c)
        rect(q[0] + cell * 0.1, q[1] + cell * 0.14, q[2], q[3], Color.Black.op(0.1))
    }
    for (r in 0 until ROWS) for (c in 0 until COLS) if (walls[r][c]) {
        val q = rect(r, c)
        rect(q[0] - 0.3, q[1] - 0.3, q[2] + 0.6, q[3] + 0.6, TankArt.wall)
        if (r == 0 || !walls[r - 1][c]) rect(q[0] - 0.3, q[1] - 0.3, q[2] + 0.6, max(1.5, cell * 0.09), gray(0.45))
    }
}

/** Flat Tank Trouble tanks, tiny black bullets, fireballs and scorch marks. */
private object TankArt {
    val card = rgb(0.9, 0.9, 0.89)
    val wall = rgb(0.27, 0.28, 0.3)
    val you = rgb(0.98, 0.79, 0.16)
    fun enemy(i: Int) = listOf(rgb(0.86, 0.13, 0.1), rgb(0.33, 0.64, 0.25), rgb(0.17, 0.32, 0.93), rgb(0.95, 0.5, 0.1))[((i % 4) + 4) % 4]

    fun tank(d: DrawScope, x: Double, y: Double, facing: Double, c: Double, color: Color) = with(d) {
        translate(x.f, y.f) {
            rotate((facing * 180 / PI).f, androidx.compose.ui.geometry.Offset.Zero) {
                val L = c * 0.94; val W = c * 0.74
                val outline = color.shade(0.6)
                rrect(-L / 2 + c * 0.05, -W / 2 + c * 0.08, L, W, c * 0.12, Color.Black.op(0.2))
                for (top in listOf(true, false)) {
                    val ty = if (top) -W / 2 else W / 2 - W * 0.26
                    val th = W * 0.26
                    rrect(-L / 2, ty, L, th, c * 0.06, color.shade(0.5))
                    var mx = -L / 2 + c * 0.09
                    while (mx < L / 2 - c * 0.05) {
                        line(mx, ty + 1, mx, ty + th - 1, Color.Black.op(0.3), max(0.5, c * 0.025), androidx.compose.ui.graphics.StrokeCap.Butt)
                        mx += c * 0.13
                    }
                }
                val hx = -L / 2 + c * 0.05; val hy = -W / 2 + W * 0.17; val hw = L - c * 0.1; val hh = W * 0.66
                rrect(hx, hy, hw, hh, c * 0.07, vgrad(listOf(color.lit(0.18), color, color.shade(0.12)), hy, hy + hh))
                rrectStroke(hx, hy, hw, hh, c * 0.07, outline, max(1.0, c * 0.035))
                rrect(0.0, -c * 0.07, c * 0.64, c * 0.14, c * 0.03, color.shade(0.28))
                rrectStroke(0.0, -c * 0.07, c * 0.64, c * 0.14, c * 0.03, outline, max(1.0, c * 0.03))
                val tr = c * 0.23; val tcx = -c * 0.03
                circle(tcx, 0.0, tr, radial(listOf(color.lit(0.25), color.shade(0.12), color.shade(0.3)), tcx - tr * 0.3, -tr * 0.35, tr * 1.3))
                circleStroke(tcx, 0.0, tr, outline, max(1.0, c * 0.035))
            }
        }
    }

    fun bullet(d: DrawScope, x: Double, y: Double, c: Double) = with(d) {
        val r = max(2.0, c * 0.12)
        circle(x + r * 0.25, y + r * 0.35, r, Color.Black.op(0.18))
        circle(x, y, r, radial(listOf(gray(0.45), gray(0.08)), x - r * 0.35, y - r * 0.35, r * 1.3))
    }

    fun scorch(d: DrawScope, x: Double, y: Double, c: Double) = with(d) {
        listOf(0.0 to 0.62, 1.3 to 0.42, 2.6 to 0.38, 4.1 to 0.46, 5.2 to 0.34).forEachIndexed { k, f ->
            val o = if (k == 0) 0.0 else c * 0.26
            circle(x + cos(f.first) * o, y + sin(f.first) * o, c * f.second, Color.Black.op(0.1))
        }
    }

    fun explosion(d: DrawScope, x: Double, y: Double, c: Double, t: Double) = with(d) {
        if (t < 0 || t >= 0.9) return@with
        for (k in 0 until 7) {
            val a = k * 0.9 + 0.3
            val dd = c * (0.2 + t * 1.0)
            circle(x + cos(a) * dd, y + sin(a) * dd - t * c * 0.35, c * (0.2 + t * 0.42), gray(0.4).op(max(0.0, 0.6 - t * 0.66)))
        }
        if (t < 0.42) {
            val k = t / 0.42
            val r = c * (0.4 + k * 0.65)
            circle(x, y, r, radial(listOf(Color.White, rgb(1.0, 0.88, 0.35), rgb(1.0, 0.45, 0.1), rgb(0.85, 0.15, 0.05, 0.0)), x, y, r))
        }
        for (k in 0 until 8) {
            val a = k * 0.785 + 0.2
            val dd = c * (0.3 + t * 2.1)
            val qx = x + cos(a) * dd; val qy = y + sin(a) * dd + t * t * c * 0.8
            val s = c * 0.08 * max(0.0, 1 - t / 0.9)
            rect(qx - s, qy - s, s * 2, s * 2, gray(0.22))
        }
    }
}
