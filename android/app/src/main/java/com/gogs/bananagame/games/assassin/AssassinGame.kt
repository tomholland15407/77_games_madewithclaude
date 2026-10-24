package com.gogs.bananagame.games.assassin

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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropUp
import androidx.compose.material.icons.filled.Circle
import androidx.compose.material.icons.filled.GpsFixed
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material3.Icon
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
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.offset
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sign
import kotlin.math.sin

/**
 * Brain/stealth — Assassin (iOS AssassinGame.swift): steer the banana with the joystick, SHOOT the
 * red targets before they see you. Stepping into a vision cone trips the alarm: reinforcements pour
 * through the red door and everyone shoots back. A hit, a timeout or an empty magazine fails.
 */
object AssassinGame {
    val definition = GameDefinition(
        id = "assassin",
        title = "Assassin",
        genre = Genre.BRAIN,
        locksFeed = true,
        manual = GameManual(
            bullets = listOf(
                "Steer with the joystick; your gun points where you head. Tap SHOOT to fire.",
                "Pick off the red targets — ideally before they see you.",
                "Step into a target's vision cone and the alarm trips: reinforcements storm in firing.",
                "Down every target to win; a bullet, a timeout, or running dry sends you to level 1.",
            ),
            bulletsVI = listOf(
                "Điều khiển bằng cần; súng hướng theo nơi bạn đi. Chạm BẮN để nổ súng.",
                "Hạ các mục tiêu đỏ — tốt nhất là trước khi chúng thấy bạn.",
                "Bước vào tầm nhìn của một mục tiêu là báo động: quân tiếp viện ập vào nổ súng.",
                "Hạ hết mọi mục tiêu để thắng; trúng đạn, hết giờ, hoặc hết đạn sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> AssassinView(level, onWin, onFail) }
    )
}

private const val COLS = 13
private const val ROWS = 17

private data class Cell(val r: Int, val c: Int)
private class Enemy(var x: Double, var y: Double, val path: List<Cell>, var idx: Int, var dir: Int,
                    var facing: Double, var alerted: Boolean, var fireCD: Double)
private class Shot(var x: Double, var y: Double, val vx: Double, val vy: Double, val friendly: Boolean, var life: Double)
private class Burst(val x: Double, val y: Double, val color: Color, val t0: Double, val seed: Int)

/** The whole simulation as a plain object (iOS AssassinView's @State + step). */
private class AssassinWorld(val level: Int) {
    private val li = min(level, 7) - 1
    val targetCount = listOf(1, 2, 2, 3, 3, 4, 4)[li]
    val patrolSpeed = listOf(1.4, 1.6, 1.8, 2.0, 2.2, 2.4, 2.6)[li]
    val chaseSpeed = patrolSpeed + 1.0
    val visionRange = 2 * listOf(3.0, 3.3, 3.6, 3.9, 4.2, 4.5, 4.8)[li]
    val visionHalf = listOf(24.0, 27.0, 30.0, 34.0, 38.0, 42.0, 46.0)[li] * PI / 180.0
    val reinforcements = listOf(1, 1, 2, 2, 3, 3, 4)[li]
    val guardFireInterval = listOf(1.7, 1.55, 1.4, 1.2, 1.0, 0.85, 0.7)[li]
    val coverBlocks = 4 + level
    val baseTime = (26 + targetCount * 10).toDouble()
    val alarmBoost = (12 + reinforcements * 6).toDouble()
    val bulletBudget = (targetCount + reinforcements) * 4 + 6

    val playerSpeed = 3.6
    val playerShootCD = 0.34
    val playerProjSpeed = 9.0
    val guardProjSpeed = 6.0
    val fireRange = 8.0

    var playing = true
    var walls = Array(ROWS) { BooleanArray(COLS) }
    var enemies = mutableListOf<Enemy>()
    var shots = mutableListOf<Shot>()
    var px = 1.5; var py = 1.5
    var playerFacing = 0.0
    var sx = 0.0; var sy = 0.0
    var shootCD = 0.0
    var timeLeft = 0.0
    var maxTime = 0.0
    var alarmRaised = false
    var ammo = 0
    var door = Cell(1, 1)
    val bursts = mutableListOf<Burst>()
    var shakeT0 = -10.0
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    fun isWall(r: Int, c: Int) = if (r < 0 || r >= ROWS || c < 0 || c >= COLS) true else walls[r][c]

    /** A disc of the mover's radius stays clear of walls. */
    fun canStand(x: Double, y: Double): Boolean {
        val rad = 0.28
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

    fun spots(e: Enemy): Boolean {
        val dx = px - e.x; val dy = py - e.y
        val d = hypot(dx, dy)
        if (d > visionRange || d <= 0.0001) return false
        if (abs(angleDiff(atan2(dy, dx), e.facing)) > visionHalf) return false
        return losClear(e.x, e.y, px, py)
    }

    fun center(p: Cell) = P(p.c + 0.5, p.r + 0.5)

    fun step(dt: Double) {
        if (!playing) return
        // 1) Player: analog stick, axis-separated wall collision; aim eases toward the stick.
        val vx = sx * playerSpeed * dt; val vy = sy * playerSpeed * dt
        if (canStand(px + vx, py)) px += vx
        if (canStand(px, py + vy)) py += vy
        if (hypot(sx, sy) > 0.08) playerFacing += angleDiff(atan2(sy, sx), playerFacing) * min(1.0, dt * 16.0)
        shootCD = max(0.0, shootCD - dt)
        // 2) Enemies patrol (calm) or chase + shoot (alerted).
        for (e in enemies) {
            if (e.alerted) chase(e, dt) else patrol(e, dt)
            e.fireCD -= dt
            if (e.alerted) {
                val d = hypot(px - e.x, py - e.y)
                if (e.fireCD <= 0 && d <= fireRange && losClear(e.x, e.y, px, py)) {
                    val a = atan2(py - e.y, px - e.x)
                    e.facing = a; e.fireCD = guardFireInterval
                    shots.add(Shot(e.x, e.y, cos(a) * guardProjSpeed, sin(a) * guardProjSpeed, false, 2.4))
                }
            }
        }
        // 3) The first detection trips the alarm.
        if (!alarmRaised && enemies.any { spots(it) }) raiseAlarm()
        // 4) Bullets.
        if (!stepShots(dt)) return
        // 5) Clock.
        timeLeft -= dt
        if (timeLeft <= 0) { timeLeft = 0.0; fail() }
    }

    private fun stepShots(dt: Double): Boolean {
        val survivors = mutableListOf<Shot>()
        for (s in shots) {
            s.x += s.vx * dt; s.y += s.vy * dt; s.life -= dt
            if (s.life <= 0) continue
            if (isWall(floor(s.y).toInt(), floor(s.x).toInt())) continue
            if (s.friendly) {
                val hit = enemies.indexOfFirst { hypot(it.x - s.x, it.y - s.y) < 0.5 }
                if (hit >= 0) {
                    val e = enemies[hit]
                    bursts.add(Burst(e.x, e.y, rgb(1.0, 0.3, 0.3), nowSec(), bursts.size * 7))
                    enemies.removeAt(hit)
                    shakeT0 = nowSec()
                    Haptics.tap(); SoundManager.tap()
                    continue
                }
            } else if (hypot(px - s.x, py - s.y) < 0.42) {
                shakeT0 = nowSec()
                fail(); return false
            }
            survivors.add(s)
        }
        shots = survivors
        if (enemies.isEmpty()) { win(); return false }
        if (ammo == 0 && shots.none { it.friendly }) { fail(); return false }
        return true
    }

    fun shoot() {
        if (!playing || shootCD > 0 || ammo <= 0) return
        shootCD = playerShootCD
        ammo -= 1
        shots.add(Shot(px, py, cos(playerFacing) * playerProjSpeed, sin(playerFacing) * playerProjSpeed, true, 2.0))
        SoundManager.tap(); Haptics.tap()
    }

    private fun raiseAlarm() {
        if (alarmRaised) return
        alarmRaised = true
        for (e in enemies) { e.alerted = true; e.fireCD = rnd(0.2, guardFireInterval) }
        val d = center(door)
        for (k in 0 until reinforcements)
            enemies.add(Enemy(d.x, d.y, listOf(door), 0, 1, atan2(py - d.y, px - d.x), true, k * 0.35 + 0.5))
        timeLeft += alarmBoost; maxTime += alarmBoost
        shakeT0 = nowSec()
        SoundManager.error(); Haptics.warning()
    }

    fun win() { if (!playing) return; playing = false; Haptics.success(); SoundManager.tap(); onWin() }
    fun fail() { if (!playing) return; playing = false; Haptics.warning(); SoundManager.error(); onFail() }

    private fun patrol(e: Enemy, dt: Double) {
        if (e.path.size < 2) return
        val wp = center(e.path[e.idx])
        val dx = wp.x - e.x; val dy = wp.y - e.y
        val d = hypot(dx, dy)
        val sd = patrolSpeed * dt
        if (d <= sd || d < 0.0001) {
            e.x = wp.x; e.y = wp.y
            var ni = e.idx + e.dir
            if (ni < 0 || ni >= e.path.size) { e.dir = -e.dir; ni = e.idx + e.dir }
            ni = clampI(ni, 0, e.path.size - 1)
            val nwp = center(e.path[ni])
            e.facing = atan2(nwp.y - e.y, nwp.x - e.x)
            e.idx = ni
        } else {
            e.x += dx / d * sd; e.y += dy / d * sd
            e.facing = atan2(dy, dx)
        }
    }

    private fun chase(e: Enemy, dt: Double) {
        val dx = px - e.x; val dy = py - e.y
        val d = hypot(dx, dy)
        if (d > 0.0001) e.facing = atan2(dy, dx)
        if (d <= 0.4) return
        val sp = chaseSpeed * dt
        val nx = dx / d * sp; val ny = dy / d * sp
        if (canStand(e.x + nx, e.y)) e.x += nx
        if (canStand(e.x, e.y + ny)) e.y += ny
    }

    private fun border() = Array(ROWS) { r -> BooleanArray(COLS) { c -> r == 0 || c == 0 || r == ROWS - 1 || c == COLS - 1 } }

    private fun reset() {
        shots = mutableListOf(); sx = 0.0; sy = 0.0; bursts.clear()
        alarmRaised = false; shootCD = 0.0; ammo = bulletBudget
        timeLeft = baseTime; maxTime = baseTime
        playing = true
    }

    /** Open arena with floating cover blocks, spaced patrols, the player far from every target. */
    fun setup() {
        val w = border()
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
        val open = (0 until ROWS).flatMap { r -> (0 until COLS).mapNotNull { c -> if (w[r][c]) null else Cell(r, c) } }
        fun neighbours(p: Cell) = listOf(Cell(p.r - 1, p.c), Cell(p.r + 1, p.c), Cell(p.r, p.c - 1), Cell(p.r, p.c + 1))
            .filter { it.r in 0 until ROWS && it.c in 0 until COLS && !w[it.r][it.c] }
        fun bfsPath(s: Cell, goal: Cell): List<Cell> {
            val prev = HashMap<Cell, Cell>(); val seen = hashSetOf(s); val q = ArrayDeque(listOf(s))
            while (q.isNotEmpty()) {
                val cur = q.removeFirst()
                if (cur == goal) break
                for (n in neighbours(cur)) if (seen.add(n)) { prev[n] = cur; q.addLast(n) }
            }
            val path = mutableListOf<Cell>(); var cur: Cell? = goal
            while (cur != null) { path.add(cur); if (cur == s) break; cur = prev[cur] }
            return path.reversed()
        }
        fun manhattan(a: Cell, b: Cell) = abs(a.r - b.r) + abs(a.c - b.c)
        val corner = Cell(ROWS - 2, COLS - 2)
        door = open.minByOrNull { manhattan(it, corner) } ?: Cell(1, 1)
        val starts = mutableListOf<Cell>()
        for (cand in open.shuffled()) {
            if (cand == door) continue
            if (starts.all { manhattan(it, cand) >= 4 }) { starts.add(cand); if (starts.size == targetCount) break }
        }
        while (starts.size < targetCount) starts.add(open.pick())
        enemies = starts.map { s ->
            var path = listOf(s, neighbours(s).firstOrNull() ?: s)
            for (goal in open.shuffled()) {
                if (goal == s) continue
                val p = bfsPath(s, goal)
                if (p.size >= 5) { path = p; break }
            }
            val f = if (path.size >= 2) atan2(center(path[1]).y - center(path[0]).y, center(path[1]).x - center(path[0]).x) else 0.0
            val c = center(s)
            Enemy(c.x, c.y, path, 0, 1, f, false, 0.0)
        }.toMutableList()
        val startCell = open.maxByOrNull { p -> starts.minOf { manhattan(it, p) } } ?: Cell(1, 1)
        center(startCell).let { px = it.x; py = it.y }
        playerFacing = 0.0
        reset()
    }

    /** Level 1 demo arena: one target patrolling row 3; you hold 4 rows below and lead the shot. */
    fun demoSetup() {
        val w = border()
        for ((r, c) in listOf(7 to 2, 7 to 3, 8 to 2, 8 to 3, 11 to 9, 11 to 10, 13 to 3, 14 to 3)) w[r][c] = true
        walls = w
        door = Cell(ROWS - 2, COLS - 2)
        val path = (2..10).map { Cell(3, it) }
        val c0 = center(path[0])
        enemies = mutableListOf(Enemy(c0.x, c0.y, path, 0, 1, 0.0, false, 0.0))
        center(Cell(14, 6)).let { px = it.x; py = it.y }
        playerFacing = -PI / 2
        reset()
    }
}

@Composable
private fun AssassinView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { AssassinWorld(level).also { if (isDemo) it.demoSetup() else it.setup() } }
    world.onWin = onWin; world.onFail = onFail
    var demoShoot by remember { mutableStateOf(false) }
    var demoTick by remember { mutableIntStateOf(0) }
    val tick by rememberFrameLoop(running = !isDemo) { dt -> world.step(dt) }
    val tm = rememberTextMeasurer()

    LaunchedEffect(Unit) {
        if (!isDemo) return@LaunchedEffect
        val dt = 1.0 / 60.0
        while (isActive) {
            world.demoSetup(); demoTick++
            delay(600)
            var t = 0.0; var fired = false; var flash = 0.0
            while (isActive && world.playing && t < 8) {
                t += dt
                val holdY = 3.5 + 4
                world.sy = if (world.py > holdY + 0.02) -1.0 else 0.0
                world.sx = 0.0
                val e = world.enemies.firstOrNull()
                if (!fired && world.sy == 0.0 && e != null && e.path.size >= 2) {
                    val wp = world.center(e.path[e.idx])
                    val vx = if (sign(wp.x - e.x) < 0) -world.patrolSpeed else world.patrolSpeed
                    val flight = (world.py - e.y) / world.playerProjSpeed
                    if (abs(e.x + vx * flight - world.px) < 0.12) { world.shoot(); fired = true; flash = 0.16 }
                }
                demoShoot = flash > 0
                flash -= dt
                world.step(dt)
                demoTick++
                delay(16)
            }
            world.sx = 0.0; world.sy = 0.0; demoShoot = false
            delay(1300)
        }
    }

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp)
            .clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp)).background(rgb(0.12, 0.13, 0.17))
            .padding(top = if (isDemo) 8.dp else 6.dp, bottom = if (isDemo) 0.dp else 6.dp),
        verticalArrangement = Arrangement.spacedBy(if (isDemo) 6.dp else 8.dp)
    ) {
        tick; demoTick
        if (!isDemo) Hud(world)
        Canvas(
            Modifier.fillMaxWidth().weight(1f).padding(horizontal = 12.dp)
                .graphicsLayer {
                    val t = nowSec() - world.shakeT0
                    if (t in 0.0..0.35) {
                        val k = sin(t / 0.35 * PI * 3) * (1 - t / 0.35)
                        translationX = (6 * density * k).toFloat()
                    }
                }
                .clip(RoundedCornerShape(14.dp)).border(2.dp, Color.Black, RoundedCornerShape(14.dp))
        ) {
            tick; demoTick
            val w = size.width.toDouble(); val h = size.height.toDouble()
            val cell = min(w / COLS, h / ROWS)
            val ox = (w - cell * COLS) / 2; val oy = (h - cell * ROWS) / 2
            hunterMap(world.walls, world.door, world.alarmRaised, cell, ox, oy)
            drawAction(world, tm, cell, ox, oy)
            val now = nowSec()
            world.bursts.removeAll { now - it.t0 > 0.6 }
            for (b in world.bursts) particleBurst(ox + b.x * cell, oy + b.y * cell, now - b.t0, b.color, 12, 44.0, seed = b.seed)
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = if (isDemo) 22.dp else 28.dp).padding(bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            HunterJoystick(if (isDemo) 80.0 else 120.0, !isDemo, if (isDemo) P(world.sx, world.sy) else null) { x, y -> world.sx = x; world.sy = y }
            Spacer(Modifier.weight(1f))
            ShootButton(if (isDemo) 70.0 else 92.0, demoShoot, isDemo) { world.shoot() }
        }
    }
}

/** Targets left / alarm / ammo and the clock. */
@Composable
private fun Hud(world: AssassinWorld) {
    Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(Icons.Filled.GpsFixed, null, tint = rgb(0.95, 0.3, 0.28), modifier = Modifier.size(17.dp))
            val n = world.enemies.size
            Text(if (n == 0) L("ALL TARGETS DOWN", "ĐÃ HẠ HẾT MỤC TIÊU") else L("$n target${if (n == 1) "" else "s"} left", "còn $n mục tiêu"),
                style = ts(17.0, FontWeight.Black))
            if (world.alarmRaised && n > 0) {
                Text(L("ALARM", "BÁO ĐỘNG"), style = ts(13.0, FontWeight.Black),
                    modifier = Modifier.background(rgb(0.9, 0.15, 0.17), RoundedCornerShape(50)).border(2.dp, Color.Black, RoundedCornerShape(50))
                        .padding(horizontal = 8.dp, vertical = 3.dp))
            }
            Spacer(Modifier.weight(1f))
            Icon(Icons.Filled.Circle, null, tint = rgb(0.95, 0.78, 0.3), modifier = Modifier.size(6.dp))
            Text(L("AMMO ${world.ammo}", "ĐẠN ${world.ammo}"), style = ts(15.0, FontWeight.Black, if (world.ammo <= 3) rgb(1.0, 0.35, 0.3) else Color.White))
        }
        val frac = if (world.maxTime > 0) world.timeLeft / world.maxTime else 0.0
        TimeBar(frac, Modifier.fillMaxWidth().padding(horizontal = 44.dp).height(6.dp),
            fill = if (frac < 0.3) rgb(0.95, 0.25, 0.22) else rgb(0.95, 0.78, 0.3), track = Color.White.op(0.12))
    }
}

/** A relative analog stick: drag anywhere on the pad; the knob offset is a −1…1 vector. */
@Composable
private fun HunterJoystick(sizeDp: Double, enabled: Boolean, demoVector: P?, onVector: (Double, Double) -> Unit) {
    var knob by remember { mutableStateOf(P.zero) }
    val dens = androidx.compose.ui.platform.LocalDensity.current.density
    val sizePx = sizeDp * dens
    val k = demoVector?.let { P(it.x * sizePx * 0.3, it.y * sizePx * 0.3) } ?: knob
    Box(
        Modifier.size(sizeDp.dp)
            .background(Brush.radialGradient(listOf(gray(0.24), gray(0.1))), CircleShape)
            .border(3.dp, Color.Black, CircleShape)
            .then(if (enabled) Modifier.touchDrag(
                onMove = { s, n ->
                    val maxR = sizePx * 0.30
                    var dx = n.x - s.x; var dy = n.y - s.y
                    val len = hypot(dx, dy)
                    if (len > maxR) { dx = dx / len * maxR; dy = dy / len * maxR }
                    knob = P(dx, dy); onVector(dx / maxR, dy / maxR)
                },
                onEnd = { _, _ -> knob = P.zero; onVector(0.0, 0.0) }
            ) else Modifier),
        contentAlignment = Alignment.Center
    ) {
        Box(Modifier.fillMaxSize().padding(4.dp).border(1.5.dp, Color.White.op(0.18), CircleShape))
        for (q in 0 until 4) Box(Modifier.fillMaxSize().rotate(q * 90f), contentAlignment = Alignment.TopCenter) {
            Icon(Icons.Filled.ArrowDropUp, null, tint = Color.White.op(0.35), modifier = Modifier.padding(top = (sizeDp * 0.03).dp).size((sizeDp * 0.18).dp))
        }
        val b = BananaTheme.banana
        Box(
            Modifier.offset { IntOffset(k.x.roundToInt(), k.y.roundToInt()) }.size((sizeDp * 0.42).dp)
                .background(Brush.radialGradient(listOf(rgb(1.0, 0.93, 0.55), b, rgb(0.8, 0.58, 0.1))), CircleShape)
                .border(2.5.dp, Color.Black, CircleShape)
        )
        if (demoVector != null && (demoVector.x != 0.0 || demoVector.y != 0.0)) {
            Icon(Icons.Filled.TouchApp, null, tint = Color.White, modifier = Modifier
                .offset { IntOffset((k.x + sizePx * 0.1).roundToInt(), (k.y + sizePx * 0.14).roundToInt()) }.size((sizeDp * 0.3).dp))
        }
    }
}

/** The round red SHOOT button (a real press and the demo's lit press look the same). */
@Composable
private fun ShootButton(sizeDp: Double, lit: Boolean, isDemo: Boolean, onShoot: () -> Unit) {
    var held by remember { mutableStateOf(false) }
    val down = held || lit
    val sc by animateFloatAsState(if (down) 0.9f else 1f, tween(80), label = "shoot")
    Box(
        Modifier.size(sizeDp.dp).scale(sc)
            .background(Brush.radialGradient(if (down) listOf(rgb(1.0, 0.45, 0.4), rgb(0.7, 0.1, 0.1)) else listOf(rgb(1.0, 0.38, 0.34), rgb(0.62, 0.08, 0.08))), CircleShape)
            .border(3.dp, Color.Black, CircleShape)
            .then(if (isDemo) Modifier else Modifier.pressDown(onDown = { held = true; onShoot() }, onUp = { held = false })),
        contentAlignment = Alignment.Center
    ) {
        Box(Modifier.fillMaxSize().padding(5.dp).border(if (down) 3.dp else 1.5.dp, Color.White.op(if (down) 0.95 else 0.35), CircleShape))
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Icon(Icons.Filled.GpsFixed, null, tint = Color.White, modifier = Modifier.size(if (isDemo) 24.dp else 32.dp))
            Text(L("SHOOT", "BẮN"), style = ts(if (isDemo) 11.0 else 13.0, FontWeight.Black))
        }
    }
}

// Hunter Assassin art (iOS HunterArt / HunterMap).

private val ink = rgb(0.06, 0.06, 0.09)

private fun hash(n: Double): Double { val v = sin(n * 12.9898) * 43758.5453; return v - floor(v) }

private fun DrawScope.drawAction(world: AssassinWorld, tm: TextMeasurer, cell: Double, ox: Double, oy: Double) {
    val u = density.toDouble()
    fun x(v: Double) = ox + v * cell
    fun y(v: Double) = oy + v * cell
    // Flashlight cones (the geometry the guards see with): warm white, red on alarm.
    for (e in world.enemies) {
        val cx = x(e.x); val cy = y(e.y)
        val R = world.visionRange * cell
        val cone = Path(); cone.m(cx, cy)
        cone.arc(cx, cy, R, e.facing - world.visionHalf, e.facing + world.visionHalf)
        cone.close()
        val col = if (e.alerted) rgb(1.0, 0.22, 0.2) else rgb(1.0, 0.93, 0.62)
        val inner = (cell * 0.3 / R).toFloat().coerceIn(0f, 1f)
        drawPath(cone, Brush.radialGradient(0f to col.op(if (e.alerted) 0.55 else 0.6), inner to col.op(if (e.alerted) 0.55 else 0.6), 1f to col.op(0.18),
            center = off(cx, cy), radius = R.f.coerceAtLeast(0.01f)))
        strokePath(cone, col.op(0.85), 1.5 * u)
    }
    // Bullets as short tracers.
    for (s in world.shots) {
        val bx = x(s.x); val by = y(s.y)
        val sp = max(0.001, hypot(s.vx, s.vy))
        val tx = bx - s.vx / sp * cell * 0.55; val ty = by - s.vy / sp * cell * 0.55
        val col = if (s.friendly) rgb(1.0, 0.88, 0.3) else rgb(1.0, 0.4, 0.3)
        drawLine(lin(listOf(col.op(0.0), col), tx, ty, bx, by), off(tx, ty), off(bx, by), (cell * 0.16).f, StrokeCap.Round)
        circle(bx, by, cell * 0.09, Color.White)
    }
    for (e in world.enemies) guardFigure(tm, x(e.x), y(e.y), e.facing, cell, e.alerted)
    figure(x(world.px), y(world.py), world.playerFacing, cell, rgb(0.14, 0.14, 0.18), BananaTheme.banana, null, true)
}

/** A top-down figure: shoulders across, head in the middle, both hands out front on the gun. */
private fun DrawScope.figure(px: Double, py: Double, facing: Double, cell: Double, jacket: Color, skin: Color, hair: Color?, band: Boolean) {
    translate(px.f, py.f) {
        rotateRad(facing.f, androidx.compose.ui.geometry.Offset.Zero) {
            val s = cell * 1.2
            val lw = max(1.5 * density, s * 0.07)
            rrect(s * 0.22 - lw * 0.5, -s * 0.06 - lw * 0.5, s * 0.5 + lw, s * 0.12 + lw, s * 0.04, ink)
            rrect(s * 0.22, -s * 0.06, s * 0.5, s * 0.12, s * 0.03, gray(0.3))
            val arms = Path()
            arms.m(0.0, -s * 0.24); arms.l(s * 0.28, -s * 0.05)
            arms.m(0.0, s * 0.24); arms.l(s * 0.28, s * 0.05)
            strokePath(arms, ink, s * 0.13 + lw)
            strokePath(arms, jacket, s * 0.13)
            for (yy in listOf(-s * 0.05, s * 0.05)) circle(s * 0.3, yy, s * 0.07, skin)
            drawRoundRect(ink, off(-s * 0.18, -s * 0.33), sz(s * 0.36, s * 0.66), androidx.compose.ui.geometry.CornerRadius((s * 0.16).f, (s * 0.2).f))
            drawRoundRect(hgrad(listOf(jacket.lit(0.2), jacket.shade(0.2)), -s * 0.2, s * 0.2), off(-s * 0.18 + lw * 0.5, -s * 0.33 + lw * 0.5),
                sz(s * 0.36 - lw, s * 0.66 - lw), androidx.compose.ui.geometry.CornerRadius((s * 0.14).f, (s * 0.18).f))
            val hr = s * 0.19
            circle(0.0, 0.0, hr + lw * 0.5, ink)
            circle(0.0, 0.0, hr, skin)
            if (hair != null) {
                val cap = Path(); cap.arc(0.0, 0.0, hr, deg(100.0), deg(260.0), moveFirst = true); cap.close()
                fillPath(cap, hair)
            }
            if (band) {
                rect(-hr * 0.3, -hr, hr * 0.55, hr * 2, ink)
                val tails = Path()
                tails.m(-hr * 0.2, -hr * 0.2); tails.q(-hr * 1.2, hr * 0.2, -hr * 2.1, -hr * 0.7)
                tails.m(-hr * 0.2, hr * 0.2); tails.q(-hr * 1.2, -hr * 0.1, -hr * 2.0, hr * 0.6)
                strokePath(tails, ink, s * 0.07)
            }
        }
    }
}

private fun DrawScope.guardFigure(tm: TextMeasurer, px: Double, py: Double, facing: Double, cell: Double, alerted: Boolean) {
    figure(px, py, facing, cell, rgb(0.86, 0.2, 0.2), rgb(0.93, 0.76, 0.6), rgb(0.2, 0.14, 0.1), false)
    if (alerted) {
        val bx = px - cell * 0.18; val by = py - cell * 1.05; val bw = cell * 0.36; val bh = cell * 0.42
        val o = 1.5 * density
        rrect(bx - o, by - o, bw + 2 * o, bh + 2 * o, cell * 0.1, ink)
        rrect(bx, by, bw, bh, cell * 0.08, rgb(1.0, 0.85, 0.2))
        text(tm, "!", bx + bw / 2, by + bh / 2, cell * 0.36, ink, FontWeight.Black)
    }
}

/** Tiled floor, concrete border walls, shipping containers for cover, and the reinforcement door. */
private fun DrawScope.hunterMap(walls: Array<BooleanArray>, door: Cell, alarm: Boolean, cell: Double, ox: Double, oy: Double) {
    val u = density.toDouble()
    drawRect(rgb(0.16, 0.17, 0.21))
    fun rx(c: Int) = ox + c * cell
    fun ry(r: Int) = oy + r * cell
    for (r in 0 until ROWS) for (c in 0 until COLS) if (!walls[r][c])
        rect(rx(c) - 0.3, ry(r) - 0.3, cell + 0.6, cell + 0.6, if ((r + c) % 2 == 0) rgb(0.4, 0.46, 0.54) else rgb(0.36, 0.42, 0.5))
    val grout = Path()
    for (r in 0..ROWS) { grout.m(ox, ry(r)); grout.l(ox + COLS * cell, ry(r)) }
    for (c in 0..COLS) { grout.m(rx(c), oy); grout.l(rx(c), oy + ROWS * cell) }
    strokePath(grout, rgb(0.26, 0.3, 0.36), 0.8 * u, StrokeCap.Butt)
    fun isBorder(r: Int, c: Int) = r == 0 || c == 0 || r == ROWS - 1 || c == COLS - 1
    val seen = HashSet<Int>()
    for (r in 0 until ROWS) for (c in 0 until COLS) {
        if (!walls[r][c]) continue
        if (isBorder(r, c)) {
            rect(rx(c) - 0.3, ry(r) - 0.3, cell + 0.6, cell + 0.6, rgb(0.62, 0.64, 0.68))
            if (r + 1 < ROWS && !walls[r + 1][c]) rect(rx(c), ry(r) + cell - cell * 0.28, cell, cell * 0.28, rgb(0.42, 0.44, 0.5))
            continue
        }
        if (!seen.add(r * COLS + c)) continue
        // Flood the block to find its extent (blocks are rectangles).
        val stack = ArrayDeque(listOf(r to c)); val cells = mutableListOf<Pair<Int, Int>>()
        while (stack.isNotEmpty()) {
            val (cr, cc) = stack.removeLast()
            cells.add(cr to cc)
            for ((nr, nc) in listOf(cr - 1 to cc, cr + 1 to cc, cr to cc - 1, cr to cc + 1)) {
                if (nr in 0 until ROWS && nc in 0 until COLS && walls[nr][nc] && !isBorder(nr, nc) && seen.add(nr * COLS + nc)) stack.addLast(nr to nc)
            }
        }
        val minR = cells.minOf { it.first }; val maxR = cells.maxOf { it.first }
        val minC = cells.minOf { it.second }; val maxC = cells.maxOf { it.second }
        val bx = rx(minC) + cell * 0.05; val by = ry(minR) + cell * 0.05
        val bw = (maxC - minC + 1) * cell - cell * 0.1; val bh = (maxR - minR + 1) * cell - cell * 0.1
        val tint = listOf(rgb(0.2, 0.55, 0.55), rgb(0.72, 0.26, 0.2), rgb(0.85, 0.55, 0.2))
        val col = tint[(hash((minR * 17 + minC).toDouble()) * 3).toInt() % 3]
        rrect(bx + cell * 0.08, by + cell * 0.14, bw, bh, cell * 0.12, Color.Black.op(0.35))
        rrect(bx, by, bw, bh, cell * 0.1, ink)
        val ix = bx + cell * 0.06; val iy = by + cell * 0.06; val iw = bw - cell * 0.12; val ih = bh - cell * 0.12
        rrect(ix, iy, iw, ih, cell * 0.07, vgrad(listOf(col.lit(0.2), col.shade(0.15)), iy, iy + ih))
        val ridges = Path()
        val vertical = ih >= iw
        var k = cell * 0.22
        while (k < (if (vertical) ih else iw) - cell * 0.1) {
            if (vertical) { ridges.m(ix + 3 * u, iy + k); ridges.l(ix + iw - 3 * u, iy + k) }
            else { ridges.m(ix + k, iy + 3 * u); ridges.l(ix + k, iy + ih - 3 * u) }
            k += cell * 0.22
        }
        strokePath(ridges, col.shade(0.4).op(0.6), 1.2 * u, StrokeCap.Butt)
    }
    // The reinforcement door: steel with hazard stripes and a warning light.
    val dx = rx(door.c) + cell * 0.04; val dy = ry(door.r) + cell * 0.04; val dw = cell * 0.92
    rrect(dx, dy, dw, dw, cell * 0.08, ink)
    val px = dx + cell * 0.07; val py = dy + cell * 0.07; val pw = dw - cell * 0.14
    rect(px, py, pw, pw, rgb(0.95, 0.78, 0.1))
    clipPath(polyPath(px, py, px + pw, py, px + pw, py + pw, px, py + pw)) {
        val diag = Path()
        var x = px - pw
        while (x < px + pw) { diag.m(x, py + pw); diag.l(x + pw, py); x += cell * 0.26 }
        strokePath(diag, ink, cell * 0.1, StrokeCap.Butt)
    }
    val lx = dx + dw / 2; val ly = dy + dw / 2
    if (alarm) circle(lx, ly, cell * 1.1, radial(listOf(rgb(1.0, 0.15, 0.1, 0.55), Color.Transparent), lx, ly, cell * 1.1))
    circle(lx, ly, cell * 0.16, if (alarm) rgb(1.0, 0.2, 0.15) else rgb(0.45, 0.1, 0.1))
    circleStroke(lx, ly, cell * 0.16, ink, 1.5 * u)
    vignette(0.35)
}
