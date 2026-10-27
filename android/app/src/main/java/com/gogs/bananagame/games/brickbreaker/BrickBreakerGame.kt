package com.gogs.bananagame.games.brickbreaker

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AcUnit
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Looks3
import androidx.compose.material.icons.filled.LooksTwo
import androidx.compose.material.icons.filled.SlowMotionVideo
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
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
import kotlin.math.sqrt

/**
 * Reflex — Brick Breaker (iOS BrickBreakerGame.swift): drag the paddle, smash every brick before the
 * clock, catch power-up capsules (extra balls, fire, ice, wide, slow, laser). Lose every ball → level 1.
 */
object BrickBreakerGame {
    val definition = GameDefinition(
        id = "brick-breaker",
        title = "Brick Breaker",
        genre = Genre.REFLEX,
        locksFeed = true,
        manual = GameManual(
            bullets = listOf(
                "Drag the paddle left and right to keep the ball alive.",
                "Smash every brick before the clock runs out.",
                "Broken bricks may drop a power-up: extra balls, fire/ice, wider paddle, slow-mo, or a laser.",
                "Lose every ball and you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Kéo thanh đỡ trái phải để giữ bóng không rơi.",
                "Đập vỡ mọi viên gạch trước khi hết giờ.",
                "Gạch vỡ có thể rơi vật tăng lực: thêm bóng, lửa/băng, thanh rộng, chậm giờ, hoặc laser.",
                "Mất hết bóng sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> BrickBreakerView(level, onWin, onFail) }
    )
}

private val brickColors = listOf(rgb(0.84, 0.20, 0.18), rgb(0.95, 0.52, 0.13), rgb(0.97, 0.79, 0.16), rgb(0.32, 0.70, 0.26),
    rgb(0.13, 0.64, 0.72), rgb(0.24, 0.42, 0.88), rgb(0.60, 0.32, 0.80))

/** Power-ups; SF Symbols → Material (2/3 circles → Looks2/3, tortoise → slow-motion). */
private enum class Power(val color: Color) {
    DOUBLE_BALL(rgb(0.55, 0.90, 0.45)), TRIPLE_BALL(rgb(0.35, 0.85, 0.85)), FIRE(rgb(1.0, 0.50, 0.20)),
    ICE(rgb(0.55, 0.82, 1.0)), WIDE(BananaTheme.banana), SLOW(rgb(0.72, 0.60, 1.0)), LASER(rgb(1.0, 0.40, 0.55))
}

private class Brick(val cx: Double, val cy: Double, val hw: Double, val hh: Double, val color: Color) { var alive = true }
private class Ball(var x: Double, var y: Double, var vx: Double, var vy: Double)
private class Drop(var x: Double, var y: Double, val kind: Power)
private class Bolt(val x: Double, var y: Double)
private class Burst(val x: Double, val y: Double, val color: Color, val t0: Double, val seed: Int)

private const val BASE_BALL_R = 0.018
private const val PADDLE_Y = 0.93

private class BreakerWorld(val level: Int, val isDemo: Boolean) {
    private val li = min(level, 7) - 1
    val brickRows = listOf(4, 5, 6, 6, 7, 7, 8)[li]
    val ballSpeed = listOf(0.90, 1.05, 1.22, 1.40, 1.60, 1.82, 2.05)[li]
    val paddleHalf = max(0.05, 0.15 - level * 0.010)
    val timeLimit = listOf(55.0, 55.0, 58.0, 60.0, 62.0, 64.0, 66.0)[li]
    val dropChance = if (level <= 2) 0.26 else 0.20

    var bricks = listOf<Brick>()
    val balls = mutableListOf<Ball>()
    val drops = mutableListOf<Drop>()
    val bolts = mutableListOf<Bolt>()
    val bursts = mutableListOf<Burst>()
    var paddleX = 0.5
    var timeLeft = timeLimit
    var done = false
    var shakeT0 = -10.0
    var fireUntil = 0.0; var iceUntil = 0.0; var wideUntil = 0.0; var slowUntil = 0.0; var laserUntil = 0.0
    var lastBoltFire = 0.0
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    val fireActive get() = fireUntil > nowSec()
    val iceActive get() = iceUntil > nowSec()
    val wideActive get() = wideUntil > nowSec()
    val slowActive get() = slowUntil > nowSec()
    val laserActive get() = laserUntil > nowSec()
    val curPaddleHalf get() = if (wideActive) min(0.30, paddleHalf * 1.9) else paddleHalf
    val ballR get() = if (iceActive) BASE_BALL_R * 1.9 else BASE_BALL_R
    val effectiveSpeed get() = ballSpeed * (if (slowActive) 0.5 else 1.0)
    val remaining get() = bricks.count { it.alive }

    private fun clearEffects() { fireUntil = 0.0; iceUntil = 0.0; wideUntil = 0.0; slowUntil = 0.0; laserUntil = 0.0 }

    fun setup() {
        bricks = buildBricks(); paddleX = 0.5
        balls.clear(); balls.add(makeBall())
        drops.clear(); bolts.clear(); bursts.clear(); clearEffects()
        timeLeft = timeLimit; done = false
    }

    fun demoSetup() {
        val wall = listOf(doubleArrayOf(0.2, 0.156, 0.16, 0.052), doubleArrayOf(0.62, 0.156, 0.16, 0.052), doubleArrayOf(0.36, 0.204, 0.14, 0.040),
            doubleArrayOf(0.78, 0.204, 0.14, 0.040), doubleArrayOf(0.5, 0.25, 0.16, 0.052), doubleArrayOf(0.24, 0.294, 0.13, 0.040))
        bricks = wall.mapIndexed { i, b -> Brick(b[0], b[1], b[2] / 2 - 0.006, b[3] / 2 - 0.006, brickColors[(i * 2) % brickColors.size]) }
        paddleX = 0.5
        val a = PI * 0.62
        balls.clear(); balls.add(Ball(0.5, PADDLE_Y - 0.06, cos(a) * ballSpeed, -sin(a) * ballSpeed))
        drops.clear(); drops.add(Drop(0.5, 0.55, Power.FIRE))
        bolts.clear(); bursts.clear(); clearEffects()
        timeLeft = timeLimit; done = false
    }

    private fun makeBall(): Ball {
        val a = rnd(PI * 0.60, PI * 0.90)
        return Ball(paddleX, PADDLE_Y - 0.06, cos(a) * effectiveSpeed, -sin(a) * effectiveSpeed)
    }

    /** Mixed-size wall: random segment counts and widths per row, alternating row heights. */
    private fun buildBricks(): List<Brick> {
        val built = mutableListOf<Brick>()
        val gap = 0.006
        var y = 0.13
        for (r in 0 until brickRows) {
            val rowH = if (r % 2 == 0) 0.052 else 0.040
            val segCount = rndInt(4..7)
            val wts = List(segCount) { rnd(0.7, 1.6) }
            val sum = wts.sum()
            var x = 0.06
            wts.forEachIndexed { i, wt ->
                val segW = 0.88 * wt / sum
                built.add(Brick(x + segW / 2, y + rowH / 2, segW / 2 - gap, rowH / 2 - gap, brickColors[(r + i) % brickColors.size]))
                x += segW
            }
            y += rowH + 0.004
        }
        return built
    }

    fun step(dt: Double) {
        if (done) return
        val lost = mutableListOf<Ball>()
        for (b in balls) { advanceBall(b, dt); if (b.y > 1 + ballR) lost.add(b) }
        balls.removeAll(lost)
        if (lost.isNotEmpty()) shakeT0 = nowSec()
        if (balls.isEmpty()) { fail(); return }
        stepDrops(dt); stepBolts(dt)
        if (remaining == 0) win()
    }

    private fun renormalize(b: Ball) {
        val mag = sqrt(b.vx * b.vx + b.vy * b.vy)
        if (mag <= 0.0001) return
        b.vx = b.vx / mag * effectiveSpeed; b.vy = b.vy / mag * effectiveSpeed
    }

    private fun advanceBall(b: Ball, dt: Double) {
        renormalize(b)
        b.x += b.vx * dt; b.y += b.vy * dt
        val br = ballR
        if (b.x < br) { b.x = br; b.vx = abs(b.vx) }
        if (b.x > 1 - br) { b.x = 1 - br; b.vx = -abs(b.vx) }
        if (b.y < br) { b.y = br; b.vy = abs(b.vy) }
        if (b.vy > 0 && b.y >= PADDLE_Y - 0.02 && b.y <= PADDLE_Y + 0.02 && abs(b.x - paddleX) <= curPaddleHalf + br) {
            b.vy = -abs(b.vy)
            b.vx = (b.x - paddleX) / curPaddleHalf * effectiveSpeed * 0.75
            renormalize(b)
            b.y = PADDLE_Y - 0.02
            Haptics.tap(); SoundManager.tap()
        }
        val fire = fireActive
        for (i in bricks.indices) {
            val k = bricks[i]
            if (!k.alive) continue
            val ox = k.hw + br - abs(b.x - k.cx); val oy = k.hh + br - abs(b.y - k.cy)
            if (ox > 0 && oy > 0) {
                if (!fire) {
                    if (ox < oy) b.vx = if (b.x < k.cx) -abs(b.vx) else abs(b.vx)
                    else b.vy = if (b.y < k.cy) -abs(b.vy) else abs(b.vy)
                }
                breakBrick(k)
                if (!fire) break
            }
        }
    }

    private fun breakBrick(k: Brick) {
        if (!k.alive) return
        k.alive = false
        bursts.add(Burst(k.cx, k.cy, k.color, nowSec(), bursts.size * 5 + bricks.indexOf(k)))
        Haptics.tap(); SoundManager.tap()
        if (!isDemo && Math.random() < dropChance) drops.add(Drop(k.cx, k.cy, Power.entries.random()))
    }

    private fun stepDrops(dt: Double) {
        for (d in drops) d.y += 0.55 * dt
        val gone = mutableListOf<Drop>()
        for (d in drops) {
            if (d.y >= PADDLE_Y - 0.03 && d.y <= PADDLE_Y + 0.03 && abs(d.x - paddleX) <= curPaddleHalf + 0.03) { apply(d.kind); gone.add(d) }
            else if (d.y > 1.05) gone.add(d)
        }
        drops.removeAll(gone)
    }

    private fun stepBolts(dt: Double) {
        if (laserActive && nowSec() - lastBoltFire > 0.42) {
            lastBoltFire = nowSec()
            bolts.add(Bolt(paddleX, PADDLE_Y - 0.03))
            SoundManager.tap()
        }
        for (b in bolts) b.y -= 1.25 * dt
        val spent = mutableListOf<Bolt>()
        for (bolt in bolts) {
            if (bolt.y < -0.02) { spent.add(bolt); continue }
            val hit = bricks.firstOrNull { it.alive && abs(bolt.x - it.cx) <= it.hw && abs(bolt.y - it.cy) <= it.hh + 0.01 }
            if (hit != null) { breakBrick(hit); spent.add(bolt) }
        }
        bolts.removeAll(spent)
    }

    private fun apply(kind: Power) {
        Haptics.success(); SoundManager.tap()
        shakeT0 = nowSec()
        val now = nowSec()
        when (kind) {
            Power.DOUBLE_BALL -> if (balls.size < 6) balls.firstOrNull()?.let { balls.add(spawnFrom(it)) }
            Power.TRIPLE_BALL -> balls.firstOrNull()?.let { s -> repeat(2) { if (balls.size < 6) balls.add(spawnFrom(s)) } }
            Power.FIRE -> fireUntil = now + 6
            Power.ICE -> iceUntil = now + 6
            Power.WIDE -> wideUntil = now + 8
            Power.SLOW -> slowUntil = now + 5
            Power.LASER -> laserUntil = now + 6
        }
    }

    private fun spawnFrom(s: Ball): Ball {
        val a = rnd(PI * 0.60, PI * 0.90)
        val dir = if (rndBool()) 1.0 else -1.0
        return Ball(s.x, s.y, cos(a) * effectiveSpeed * dir, -sin(a) * effectiveSpeed)
    }

    /** Where the lead ball will cross the paddle line (straight line + wall bounces) and when. */
    private fun intercept(b: Ball, dt: Double): Pair<Double, Double> {
        var x = b.x; var y = b.y; var vx = b.vx; var vy = b.vy; var t = 0.0
        val br = ballR
        repeat(2000) {
            x += vx * dt; y += vy * dt; t += dt
            if (x < br) { x = br; vx = abs(vx) }
            if (x > 1 - br) { x = 1 - br; vx = -abs(vx) }
            if (y < br) { y = br; vy = abs(vy) }
            if (vy > 0 && y >= PADDLE_Y - 0.02) return x to t
        }
        return x to t
    }

    /** The demo finger: catch the drop if there's time to get back, else aim the return at the nearest brick. */
    fun demoPaddleTarget(dt: Double, fingerSpeed: Double): Double {
        val ball = balls.firstOrNull() ?: return paddleX
        val (xh, th) = intercept(ball, dt)
        drops.firstOrNull()?.let { d ->
            val tDrop = (PADDLE_Y - 0.03 - d.y) / 0.55
            if (tDrop < th - 0.1 && abs(d.x - xh) <= fingerSpeed * (th - tDrop) * 0.8) return d.x
        }
        val b = bricks.filter { it.alive }.minByOrNull { abs(it.cx - xh) } ?: return xh
        val ratio = (b.cx - xh) / ((PADDLE_Y - 0.02) - b.cy)
        val off = clamp(ratio / sqrt(1 + ratio * ratio) / 0.75, -0.85, 0.85)
        return xh - off * curPaddleHalf
    }

    fun win() { if (done) return; done = true; onWin() }
    fun fail() { if (done) return; done = true; SoundManager.error(); onFail() }
}

@Composable
private fun BrickBreakerView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { BreakerWorld(level, isDemo).also { if (isDemo) it.demoSetup() else it.setup() } }
    world.onWin = onWin; world.onFail = onFail
    var demoTick by remember { mutableIntStateOf(0) }
    val start = remember { nowSec() }
    val tick by rememberFrameLoop { dt ->
        if (isDemo || world.done) return@rememberFrameLoop
        world.timeLeft = max(0.0, world.timeLimit - (nowSec() - start))
        if (world.timeLeft <= 0) { world.fail(); return@rememberFrameLoop }
        world.step(dt)
    }
    val icons = listOf(Icons.Filled.LooksTwo, Icons.Filled.Looks3, Icons.Filled.LocalFireDepartment, Icons.Filled.AcUnit,
        Icons.Filled.SwapHoriz, Icons.Filled.SlowMotionVideo, Icons.Filled.Bolt).map { rememberVectorIcon(it) }
    val handP = rememberHand()
    var cardSize by remember { mutableStateOf(androidx.compose.ui.unit.IntSize.Zero) }
    val dens = androidx.compose.ui.platform.LocalDensity.current.density.toDouble()

    LaunchedEffect(Unit) {
        if (!isDemo) return@LaunchedEffect
        val dt = 1.0 / 60.0; val fingerSpeed = 1.6
        while (isActive) {
            world.demoSetup(); demoTick++
            delay(600)
            var t = 0.0
            while (isActive && !world.done && t < 15) {
                t += dt
                val target = world.demoPaddleTarget(dt, fingerSpeed)
                val stepMax = fingerSpeed * dt
                world.paddleX = clamp(world.paddleX + clamp(target - world.paddleX, -stepMax, stepMax), world.curPaddleHalf, 1 - world.curPaddleHalf)
                world.step(dt)
                demoTick++
                delay(16)
            }
            delay(1300)
        }
    }

    Column(Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp)).background(gunmetal)) {
        tick; demoTick
        if (!isDemo) {
            Column(Modifier.fillMaxWidth().padding(vertical = 10.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Canvas(Modifier.size(30.dp, 15.dp)) { brick(density.toDouble(), density.toDouble(), size.width - 2.0 * density, size.height - 2.0 * density, rgb(0.84, 0.2, 0.18)) }
                    Text(L("${world.remaining} left", "còn ${world.remaining}"), style = ts(26.0, FontWeight.Black, hudYellow).copy(
                        shadow = androidx.compose.ui.graphics.Shadow(Color.Black, androidx.compose.ui.geometry.Offset(1.5f * 3, 2f * 3), 0f)))
                }
                val f = world.timeLeft / world.timeLimit
                Canvas(Modifier.fillMaxWidth().padding(horizontal = 40.dp).height(8.dp)) { gauge(f) }
            }
        }
        Canvas(
            Modifier.fillMaxWidth().weight(1f)
                .graphicsLayer {
                    val t = nowSec() - world.shakeT0
                    if (t in 0.0..0.35) translationX = (7 * density * sin(t / 0.35 * PI * 3) * (1 - t / 0.35)).toFloat()
                }
                .onSizeChanged { cardSize = it }
                .then(if (isDemo) Modifier else Modifier.touchDrag(
                    onStart = { p -> movePaddle(world, p.x, cardSize.width.toDouble(), cardSize.height.toDouble(), dens) },
                    onMove = { _, p -> movePaddle(world, p.x, cardSize.width.toDouble(), cardSize.height.toDouble(), dens) }))
        ) {
            tick; demoTick
            val ft = frameWidth(size.width.toDouble(), size.height.toDouble(), density.toDouble())
            val w = max(1.0, size.width - ft * 2); val h = max(1.0, size.height - ft)
            hazardFrame(ft)
            clipPath(Path().apply { addRect(androidx.compose.ui.geometry.Rect(ft.f, ft.f, (ft + w).f, (ft + h).f)) }) {
                translate(ft.f, ft.f) {
                    floor(w, h)
                    for (b in world.bricks) if (b.alive) brick((b.cx - b.hw) * w, (b.cy - b.hh) * h, b.hw * 2 * w, b.hh * 2 * h, b.color)
                    drawAction(world, w, h, icons)
                    if (isDemo) hand(handP, world.paddleX * w + 10 * density - 13 * density, PADDLE_Y * h + 16 * density - 13 * density, 26.0 * density)
                    val now = nowSec()
                    world.bursts.removeAll { now - it.t0 > 0.6 }
                    for (b in world.bursts) particleBurst(b.x * w, b.y * h, now - b.t0, b.color, 9, 34.0, 30.0, b.seed)
                }
            }
        }
    }
}

private fun movePaddle(world: BreakerWorld, x: Double, cw: Double, ch: Double, u: Double) {
    if (world.done) return
    val t = frameWidth(cw, ch, u)
    val w = max(1.0, cw - t * 2)
    world.paddleX = clamp((x - t) / w, world.curPaddleHalf, 1 - world.curPaddleHalf)
}

// BlackBerry Brick Breaker art (iOS BBArt and friends).

private val gunmetal = rgb(0.15, 0.16, 0.19)
private val hudYellow = rgb(0.99, 0.8, 0.2)
private val hazard = rgb(0.99, 0.82, 0.12)
private val laserC = rgb(1.0, 0.2, 0.25)
private val laserDark = rgb(0.7, 0.08, 0.12)
private val paddleBlue = rgb(0.2, 0.38, 0.92)
private val ink = rgb(0.07, 0.08, 0.1)

private fun frameWidth(w: Double, h: Double, u: Double) = max(8.0 * u, min(w, h) * 0.034)

private fun hash(n: Double): Double { val v = sin(n * 12.9898) * 43758.5453; return v - floor(v) }

private fun DrawScope.gauge(f: Double) {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    rrect(0.0, 0.0, w, h, h / 2, Color.Black.op(0.45))
    rrectStroke(0.0, 0.0, w, h, h / 2, Color.White.op(0.12), u)
    if (f > 0) rrect(0.0, 0.0, w * clamp(f, 0.0, 1.0), h, h / 2,
        vgrad(if (f < 0.3) listOf(rgb(1.0, 0.45, 0.35), rgb(0.8, 0.12, 0.1)) else listOf(hudYellow.lit(0.3), hudYellow.shade(0.15)), 0.0, h))
}

private fun DrawScope.drawAction(world: BreakerWorld, w: Double, h: Double, icons: List<VectorIcon>) {
    val u = density.toDouble()
    for (b in world.bolts) {
        val x = b.x * w - 2.5 * u; val y = b.y * h - 10 * u
        rrect(x - 3 * u, y - 3 * u, 11 * u, 26 * u, 5 * u, laserC.op(0.35))
        rrect(x, y, 5 * u, 20 * u, 2.5 * u, laserC)
        rrect(x + 1.4 * u, y + 3 * u, 2.2 * u, 14 * u, u, Color.White.op(0.9))
    }
    for (d in world.drops) capsule(d.x * w, d.y * h, d.kind.color, icons[d.kind.ordinal])
    val fire = world.fireActive; val ice = world.iceActive
    for (b in world.balls) ball(b.x * w, b.y * h, world.ballR * w, b.vx * w, b.vy * h, fire, ice)
    paddle(world.paddleX * w, PADDLE_Y * h, world.curPaddleHalf * 2 * w, world.laserActive)
}

/** An embossed brick: bevels, a glossy face and the dark zig-zag motif. */
private fun DrawScope.brick(x: Double, y: Double, w: Double, h: Double, base: Color) {
    val u = density.toDouble()
    val rad = min(3 * u, h * 0.18)
    rrect(x + 1.2 * u, y + 1.8 * u, w, h, rad, Color.Black.op(0.28))
    rrect(x, y, w, h, rad, vgrad(listOf(base.lit(0.28), base, base.shade(0.22)), y, y + h))
    val dx = min(w * 0.12, h * 0.3); val dy = h * 0.27
    val fx = x + dx; val fy = y + dy; val fw = w - 2 * dx; val fh = h - 2 * dy
    if (fw > 4 * u && fh > 2 * u) {
        val zig = Path()
        val st = max(3 * u, fh * 0.95)
        var zx = fx; var up = true
        zig.m(zx, fy + fh)
        while (zx < fx + fw) { zx = min(fx + fw, zx + st); zig.l(zx, if (up) fy else fy + fh); up = !up }
        val lw = max(u, h * 0.12)
        translate(0f, (0.8 * u).f) { drawPath(zig, base.lit(0.35).op(0.7), style = Stroke((lw * 0.6).f, join = StrokeJoin.Round)) }
        strokePath(zig, base.shade(0.45), lw)
    }
    rrect(x + 1.5 * u, y + u, w - 3 * u, max(u, h * 0.12), u, Color.White.op(0.45))
    val bh = max(u, h * 0.1)
    rect(x + 1.5 * u, y + h - bh - 0.6 * u, w - 3 * u, bh, Color.Black.op(0.22))
    rrectStroke(x, y, w, h, rad, ink.op(0.6), u)
}

/** A glossy pill capsule carrying the power-up's icon. */
private fun DrawScope.capsule(cx: Double, cy: Double, color: Color, icon: VectorIcon) {
    val u = density.toDouble()
    val x = cx - 18 * u; val y = cy - 11 * u; val w = 36 * u; val h = 22 * u
    rrect(x + 1.5 * u, y + 2.5 * u, w, h, h / 2, Color.Black.op(0.3))
    rrect(x, y, w, h, h / 2, vgrad(listOf(color.lit(0.45), color, color.shade(0.35)), y, y + h))
    rrect(x + 6 * u, y + 2.5 * u, w - 12 * u, 5 * u, 2.5 * u, Color.White.op(0.55))
    rrectStroke(x, y, w, h, h / 2, ink.op(0.7), 1.3 * u)
    val s = 14 * u
    icon(icon, cx - s / 2, cy - s / 2 + u, s, Color.Black.op(0.85))
}

/** The ball: dark steel, a fireball with a flame trail, or a big frosted ice ball. */
private fun DrawScope.ball(cx: Double, cy: Double, rad: Double, dx: Double, dy: Double, fire: Boolean, ice: Boolean) {
    val u = density.toDouble()
    val len = max(0.0001, hypot(dx, dy))
    val ux = dx / len; val uy = dy / len
    if (fire) for (k in 5 downTo 1) {
        val d = k * rad * 0.85; val rr = rad * (1.05 - k * 0.14)
        circle(cx - ux * d, cy - uy * d, rr, rgb(1.0, 0.35 + 0.1 * k, 0.05, 0.85 - 0.14 * k))
    }
    val colors = when {
        fire -> listOf(Color.White, rgb(1.0, 0.9, 0.4), rgb(1.0, 0.5, 0.1), rgb(0.8, 0.15, 0.05))
        ice -> listOf(Color.White, rgb(0.78, 0.93, 1.0), rgb(0.4, 0.7, 0.97), rgb(0.2, 0.45, 0.8))
        else -> listOf(Color.White, rgb(0.62, 0.65, 0.7), rgb(0.25, 0.27, 0.3), rgb(0.08, 0.09, 0.1))
    }
    circle(cx + rad * 0.2, cy + rad * 0.3, rad, Color.Black.op(0.25))
    circle(cx, cy, rad, radial(colors, cx - rad * 0.35, cy - rad * 0.4, rad * 1.5))
    if (ice) for (k in 0 until 5) { val a = k * 1.26; circle(cx + cos(a) * rad * 0.55, cy + sin(a) * rad * 0.55, u, Color.White.op(0.85)) }
    circleStroke(cx, cy, rad, ink.op(if (fire) 0.2 else 0.5), u)
}

/** The blue hover paddle with a chrome hump — a red cannon while the laser lasts. */
private fun DrawScope.paddle(cx: Double, cy: Double, w: Double, laser: Boolean) {
    val u = density.toDouble()
    val bx = cx - w / 2; val by = cy - 7 * u; val bh = 14 * u
    rrect(bx, by + 3 * u, w, bh, 7 * u, Color.Black.op(0.28))
    rrect(bx, by, w, bh, 7 * u, vgrad(listOf(paddleBlue.lit(0.35), paddleBlue, paddleBlue.shade(0.4)), by, by + bh))
    val pod = min(12 * u, w * 0.18)
    for (x in listOf(bx, bx + w - pod)) rrect(x, by, pod, bh, 7 * u, paddleBlue.shade(0.35))
    rrect(bx + 5 * u, by + 2 * u, w - 10 * u, 2.5 * u, 1.2 * u, Color.White.op(0.45))
    rrectStroke(bx, by, w, bh, 7 * u, rgb(0.04, 0.08, 0.3), 1.3 * u)
    val hw = min(w * 0.42, 44 * u)
    val hx = cx - hw / 2; val hy = by - 5 * u; val hh = 10 * u
    if (laser) {
        val rx = cx - 3 * u; val ry = hy - 8 * u
        rrect(rx, ry, 6 * u, 10 * u, 2 * u, laserDark)
        rrect(rx, ry, 6 * u, 3 * u, 1.5 * u, Color.White.op(0.9))
        rrectStroke(rx, ry, 6 * u, 10 * u, 2 * u, ink, u)
    }
    rrect(hx, hy, hw, hh, 5 * u, vgrad(listOf(Color.White, rgb(0.72, 0.74, 0.78), rgb(0.42, 0.44, 0.48)), hy, hy + hh))
    rrectStroke(hx, hy, hw, hh, 5 * u, ink.op(0.7), u)
    if (laser) circle(cx, hy + 5 * u, 3 * u, laserC)
}

/** Yellow-and-black hazard stripes round the top and sides of the field (the bottom is open). */
private fun DrawScope.hazardFrame(t: Double) {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    val clip = Path().apply {
        addRect(androidx.compose.ui.geometry.Rect(0f, 0f, w.f, t.f))
        addRect(androidx.compose.ui.geometry.Rect(0f, 0f, t.f, h.f))
        addRect(androidx.compose.ui.geometry.Rect((w - t).f, 0f, w.f, h.f))
    }
    clipPath(clip) {
        drawRect(hazard)
        val stripes = Path()
        var x = -h
        while (x < w + h) { stripes.m(x, h); stripes.l(x + h, 0.0); x += t * 1.25 }
        strokePath(stripes, ink, t * 0.55, StrokeCap.Butt)
        drawRect(lin(listOf(Color.White.op(0.18), Color.Transparent, Color.Black.op(0.18)), 0.0, 0.0, t, t))
    }
    val lip = Path(); lip.m(t, h); lip.l(t, t); lip.l(w - t, t); lip.l(w - t, h)
    strokePath(lip, Color.Black.op(0.6), 1.5 * u, StrokeCap.Butt)
}

/** Brushed grey floor plates with seams and rivets. */
private fun DrawScope.floor(w: Double, h: Double) {
    val u = density.toDouble()
    rect(0.0, 0.0, w, h, lin(listOf(rgb(0.86, 0.87, 0.89), rgb(0.74, 0.76, 0.79)), 0.0, 0.0, w * 0.3, h))
    val rowH = max(40 * u, h * 0.16)
    var y = -rowH * 0.3; var row = 0
    while (y < h) {
        var x = -hash(row * 3.1) * w * 0.3; var k = 0
        while (x < w) {
            val pw = w * (0.28 + 0.34 * hash((row * 13 + k) * 1.7))
            val px = x + 2 * u; val py = y + 2 * u; val pww = pw - 4 * u; val phh = rowH - 4 * u
            val shade = 0.03 * hash(row * 7 + k * 3 + 0.5) - 0.015
            rrect(px, py, pww, phh, 3 * u, if (shade > 0) Color.White.op(shade * 6) else Color.Black.op(-shade * 4))
            rrectStroke(px + u, py + u, pww, phh, 3 * u, Color.White.op(0.5), u)
            rrectStroke(px, py, pww, phh, 3 * u, rgb(0.55, 0.57, 0.6), u)
            for ((rx, ry) in listOf(px + 5 * u to py + 5 * u, px + pww - 5 * u to py + 5 * u, px + 5 * u to py + phh - 5 * u, px + pww - 5 * u to py + phh - 5 * u)) {
                circle(rx, ry, 1.6 * u, rgb(0.6, 0.62, 0.65))
                oval(rx - 1.1 * u, ry - 1.3 * u, 1.6 * u, 1.6 * u, Color.White.op(0.7))
            }
            x += pw; k++
        }
        y += rowH; row++
    }
    rect(0.0, 0.0, w, h, vgrad(listOf(Color.Transparent, Color.Black.op(0.18)), h * 0.55, h))
}
