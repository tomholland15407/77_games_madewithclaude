package com.gogs.bananagame.games.turboracer

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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.SportsScore
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/** Reflex — Turbo Racer (iOS TurboRacerGame.swift): an OutRun-style pseudo-3D racer. */
object TurboRacerGame {
    val definition = GameDefinition(
        id = "turbo-racer",
        title = "Turbo Racer",
        genre = Genre.REFLEX,
        manual = GameManual(
            bullets = listOf(
                "Hold ◄ ► to steer down a curving pseudo-3D road.",
                "Hug the tarmac through bends and slalom past slower traffic.",
                "Reach the finish to win; a crash, sliding off, or the clock ends the run.",
            ),
            bulletsVI = listOf(
                "Giữ ◄ ► để lái trên con đường 3D uốn lượn.",
                "Bám mặt đường qua các khúc cua và luồn lách qua xe chậm.",
                "Về đích để thắng; va chạm, trượt khỏi đường, hoặc hết giờ là thua.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> TurboRacerView(level, onWin, onFail) }
    )
}

private const val HY = 0.32
private const val MAX_HALF = 0.42
private const val VIEW_RANGE = 18.0
private const val PLAYER_Y = 0.90
private const val STEER_RATE = 2.4
private const val DRIFT_RATE = 1.05

private val TRAFFIC_COLORS = listOf(rgb(0.90, 0.30, 0.32), rgb(0.35, 0.55, 0.95), rgb(0.45, 0.80, 0.45), rgb(0.85, 0.55, 0.95))

private class Car(val worldZ: Double, val roadX: Double, val color: Color) {
    var passed = false
    val kind = rndInt(0..3)
}

private class RacerWorld(val level: Int) {
    val speed = listOf(4.6, 5.6, 6.8, 8.0, 9.4, 10.8, 12.4)[min(level, 7) - 1]
    val finish = listOf(156.0, 196.0, 245.0, 296.0, 357.0, 421.0, 496.0)[min(level, 7) - 1]
    val curveAmp = listOf(0.35, 0.45, 0.6, 0.75, 0.9, 1.05, 1.2)[min(level, 7) - 1]
    val curveFreq = listOf(0.10, 0.11, 0.12, 0.13, 0.14, 0.15, 0.16)[min(level, 7) - 1]
    val spawnGap = listOf(7.0, 6.0, 5.0, 4.2, 3.6, 3.0, 2.6)[min(level, 7) - 1]
    val timeLimit = finish / speed + 10

    var playing = true
    var distance = 0.0
    var curve = 0.0
    var playerX = 0.0
    var steer = 0.0
    var cars = mutableListOf<Car>()
    var lastSpawn = 0.0
    var timeLeft = timeLimit
    var burst: Triple<Double, Double, Double>? = null   // x, y (fractions), t0
    var shakeT0 = -10.0
    var demoSteer = 0.0
    var start = nowSec()
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    fun setup() {
        distance = 0.0; curve = 0.0; playerX = 0.0; steer = 0.0
        cars.clear(); burst = null; lastSpawn = 0.0
        timeLeft = timeLimit; playing = true; start = nowSec()
    }

    fun step(dt: Double) {
        if (!playing) return
        timeLeft = max(0.0, timeLimit - (nowSec() - start))
        if (timeLeft <= 0) { fail(); return }
        distance += speed * dt
        curve = curveAmp * sin(distance * curveFreq)
        playerX += steer * STEER_RATE * dt
        playerX -= curve * DRIFT_RATE * dt
        if (abs(playerX) > 1.15) { crash(0.5 + playerX * MAX_HALF, 0.9); return }
        if (distance - lastSpawn >= spawnGap) {
            lastSpawn = distance
            cars.add(Car(distance + VIEW_RANGE, rnd(-0.7, 0.7), TRAFFIC_COLORS.pick()))
        }
        val tP = (PLAYER_Y - HY) / (1 - HY)
        val relPlayer = VIEW_RANGE * (1 - tP)
        val halfP = MAX_HALF * (0.08 + 0.92 * tP)
        val centerP = 0.5 + curve * 0.35 * (1 - tP)
        val carWP = 0.17 * (0.10 + 0.90 * tP)
        val playerScreenX = 0.5 + playerX * MAX_HALF
        val hitThresh = (carWP + 0.19) * 0.5 * 0.82
        for (c in cars) {
            val rel = c.worldZ - distance
            if (rel <= relPlayer && !c.passed) {
                c.passed = true
                val carScreenX = centerP + c.roadX * halfP
                if (abs(carScreenX - playerScreenX) < hitThresh) { crash(carScreenX, PLAYER_Y); return }
            }
        }
        cars.removeAll { it.worldZ - distance < -2 }
        if (distance >= finish) win()
    }

    fun crash(x: Double, y: Double) { burst = Triple(x, y, nowSec()); shakeT0 = nowSec(); fail() }
    fun win() { if (!playing) return; playing = false; Haptics.success(); SoundManager.tap(); onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); Haptics.warning(); onFail() }
}

@Composable
private fun TurboRacerView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { RacerWorld(level).also { it.setup() } }
    world.onWin = onWin; world.onFail = onFail
    val st = remember { OutRunArt.stage(level) }
    var demoTick by remember { mutableStateOf(0) }
    val tick by rememberFrameLoop(running = !isDemo) { dt -> world.step(dt) }
    val burstTick by rememberFrameLoop(running = world.burst != null)

    LaunchedEffect(Unit) {
        if (!isDemo) return@LaunchedEffect
        while (isActive) {
            world.setup()
            val rate = world.finish / 3.2
            var spawnT = 0.6
            var nextSide = 0.6
            while (world.distance < world.finish && isActive) {
                val dt = 0.016
                spawnT += dt
                world.distance = min(world.finish, world.distance + rate * dt)
                world.curve = world.curveAmp * sin(world.distance * world.curveFreq)
                if (spawnT >= 0.8) {
                    spawnT = 0.0
                    world.cars.add(Car(world.distance + VIEW_RANGE, nextSide, TRAFFIC_COLORS.pick()))
                    nextSide = -nextSide
                }
                var nearestX: Double? = null
                var nearestRel = Double.MAX_VALUE
                for (car in world.cars) {
                    val rel = car.worldZ - world.distance
                    if (rel > 0.2 && rel < 7 && rel < nearestRel) { nearestRel = rel; nearestX = car.roadX }
                }
                val targetX = nearestX?.let { if (it > 0) -0.55 else 0.55 } ?: 0.0
                world.playerX += (targetX - world.playerX) * 0.12
                world.demoSteer = if (abs(targetX - world.playerX) > 0.06) (if (targetX > world.playerX) 1.0 else -1.0) else 0.0
                world.cars.removeAll { it.worldZ - world.distance < -2 }
                demoTick++
                delay(16)
            }
            world.demoSteer = 0.0
            demoTick++
            delay(1200)
        }
    }

    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(if (isDemo) 8.dp else 12.dp)) {
        Box(
            Modifier.fillMaxWidth().weight(1f).padding(horizontal = if (isDemo) 0.dp else 8.dp)
                .clip(RoundedCornerShape(if (isDemo) 12.dp else 18.dp))
                .graphicsLayer {
                    val t = nowSec() - world.shakeT0
                    if (t in 0.0..0.35) {
                        val k = sin(t / 0.35 * PI * 3)
                        translationX = (6 * density * k).toFloat(); translationY = (3.6 * density * k).toFloat()
                    }
                }
        ) {
            Canvas(Modifier.fillMaxSize()) {
                tick; demoTick; burstTick
                val W = size.width.toDouble(); val H = size.height.toDouble()
                // Sky strip with parallax drift against the bends.
                clipRect(0f, 0f, W.f, (HY * H + 1).f) {
                    translate((-W * 0.2 - world.curve * W * 0.14).f, 0f) {
                        OutRunArt.sky(this, W * 1.4, HY * H, level)
                    }
                }
                drawWorld(world, st, level)
                world.burst?.let { (bx, by, t0) -> particleBurst(bx * W, by * H, nowSec() - t0, Color(0xFFFF9500), 16, 60.0) }
            }
            Hud(world.timeLeft, world.timeLimit, (min(world.distance, world.finish) / world.finish * 100).toInt(), world.speed, isDemo)
        }
        Row(Modifier.padding(bottom = if (isDemo) 4.dp else 8.dp), horizontalArrangement = Arrangement.spacedBy(if (isDemo) 28.dp else 40.dp)) {
            HoldButton(-1.0, world, isDemo, world.demoSteer)
            HoldButton(1.0, world, isDemo, world.demoSteer)
        }
    }
}

@Composable
private fun Hud(timeLeft: Double, timeLimit: Double, pct: Int, speed: Double, isDemo: Boolean) {
    val frac = timeLeft / timeLimit
    fun st(size: Double, color: Color) = TextStyle(fontSize = size.sp, fontWeight = FontWeight.Black, fontStyle = FontStyle.Italic,
        color = color, fontFamily = Rounded, shadow = Shadow(Color.Black, Offset(3f, 3f), 0f))
    Column(Modifier.fillMaxSize().padding(horizontal = if (isDemo) 10.dp else 12.dp, vertical = if (isDemo) 8.dp else 10.dp)) {
        Row(verticalAlignment = Alignment.Top) {
            if (!isDemo) Column {
                Text(L("TIME", "GIỜ"), style = st(13.0, rgb(1.0, 0.5, 0.2)))
                Text("${ceil(timeLeft).toInt()}", style = st(34.0, if (frac < 0.3) rgb(1.0, 0.25, 0.2) else rgb(1.0, 0.9, 0.2)))
            }
            Spacer(Modifier.weight(1f))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.SportsScore, null, tint = Color.White, modifier = Modifier.size(if (isDemo) 16.dp else 22.dp))
                Spacer(Modifier.width(5.dp))
                Text("$pct%", style = st(if (isDemo) 18.0 else 24.0, Color.White))
            }
        }
        Spacer(Modifier.weight(1f))
        Row(verticalAlignment = Alignment.Bottom) {
            Text("${(speed * 30 + 60).toInt()}", style = st(if (isDemo) 16.0 else 22.0, Color.White))
            Spacer(Modifier.width(3.dp))
            Text("km/h", style = st(if (isDemo) 10.0 else 12.0, rgb(1.0, 0.5, 0.2)))
        }
    }
}

@Composable
private fun HoldButton(dir: Double, world: RacerWorld, isDemo: Boolean, demoSteer: Double) {
    var held by remember { mutableStateOf(false) }
    val pressed = (isDemo && demoSteer == dir) || held
    val sc by animateFloatAsState(if (pressed) 0.9f else 1f, tween(120), label = "hb")
    Box(
        Modifier.scale(sc).size(if (isDemo) 84.dp else 100.dp, if (isDemo) 50.dp else 66.dp)
            .background(if (pressed) BananaTheme.banana.lit(0.3) else BananaTheme.banana, RoundedCornerShape(18.dp))
            .border(if (pressed) 3.dp else 2.dp, Color.White.op(if (pressed) 0.95 else 0.4), RoundedCornerShape(18.dp))
            .then(if (isDemo) Modifier else Modifier.pressDown(
                onDown = { held = true; if (world.playing) world.steer = dir },
                onUp = { held = false; if (world.steer == dir) world.steer = 0.0 })),
        contentAlignment = Alignment.Center
    ) {
        Icon(if (dir < 0) Icons.Filled.ChevronLeft else Icons.Filled.ChevronRight, null, tint = Color.Black,
            modifier = Modifier.size(if (isDemo) 32.dp else 40.dp))
    }
}

private fun DrawScope.drawWorld(w: RacerWorld, st: OutRunStage, level: Int) {
    val W = size.width.toDouble(); val H = size.height.toDouble()
    OutRunArt.road(this, W, H, HY, MAX_HALF, w.curve, w.distance, st)
    fun project(rel: Double, roadX: Double): Triple<Double, Double, Double> {
        val t = 1 - rel / VIEW_RANGE
        val half = MAX_HALF * (0.08 + 0.92 * t)
        val center = 0.5 + w.curve * 0.35 * (1 - t)
        return Triple((center + roadX * half) * W, (HY + t * (1 - HY)) * H, 0.10 + 0.90 * t)
    }
    class Sprite(val rel: Double, val k: Int, val side: Double, val car: Car?)
    val sprites = ArrayList<Sprite>()
    val gap = 2.4
    val k0 = ceil((w.distance + 0.25) / gap).toInt(); val k1 = floor((w.distance + VIEW_RANGE - 0.1) / gap).toInt()
    for (k in k0..k1) {
        if (st.prop == 6 && k % 2 != 0) continue
        sprites.add(Sprite(k * gap - w.distance, k, -1.0, null))
        sprites.add(Sprite(k * gap - w.distance + gap / 2, k, 1.0, null))
    }
    for (car in w.cars) {
        val rel = car.worldZ - w.distance
        if (rel > 0.2 && rel < VIEW_RANGE) sprites.add(Sprite(rel, 0, 0.0, car))
    }
    for (s in sprites.sortedByDescending { it.rel }) {
        if (s.rel <= 0.2 || s.rel >= VIEW_RANGE) continue
        if (s.car == null) {
            val jitter = ((s.k * 7919 + (if (s.side > 0) 31 else 0)) % 100).let { if (it < 0) it + 100 else it } / 100.0
            val (px, py, sc) = project(s.rel, s.side * (1.42 + 0.35 * jitter))
            OutRunArt.prop(this, st.prop, px, py, sc, H, s.side, s.k)
        } else {
            val (px, py, sc) = project(s.rel, s.car.roadX)
            OutRunArt.traffic(this, s.car.kind, px, py, 0.17 * W * sc, s.car.color, level >= 6)
        }
    }
    val lean = if (w.steer != 0.0) w.steer else w.demoSteer
    OutRunArt.playerCar(this, (0.5 + w.playerX * MAX_HALF) * W, PLAYER_Y * H, 0.19 * W, lean, level >= 6)
}

private class OutRunStage(
    val skyTop: Color, val skyBottom: Color, val groundA: Color, val groundB: Color,
    val roadA: Color, val roadB: Color, val rumbleA: Color, val rumbleB: Color, val lane: Color,
    val prop: Int, val scenery: Int,
)

private object OutRunArt {
    fun c(r: Double, g: Double, b: Double) = rgb(r, g, b)

    fun stage(level: Int): OutRunStage = when (min(max(level, 1), 7)) {
        1 -> OutRunStage(c(0.1, 0.44, 0.95), c(0.6, 0.83, 1.0), c(0.94, 0.86, 0.64), c(0.89, 0.8, 0.57), c(0.5, 0.5, 0.53), c(0.46, 0.46, 0.49), Color.White, c(0.88, 0.12, 0.12), Color.White, 0, 0)
        2 -> OutRunStage(c(0.22, 0.52, 0.95), c(0.74, 0.9, 1.0), c(0.42, 0.72, 0.3), c(0.36, 0.65, 0.26), c(0.48, 0.48, 0.5), c(0.44, 0.44, 0.46), Color.White, c(0.88, 0.12, 0.12), Color.White, 1, 1)
        3 -> OutRunStage(c(0.96, 0.6, 0.28), c(1.0, 0.87, 0.62), c(0.9, 0.64, 0.38), c(0.84, 0.58, 0.34), c(0.52, 0.46, 0.42), c(0.48, 0.42, 0.39), Color.White, c(0.85, 0.2, 0.1), c(1.0, 0.95, 0.85), 2, 2)
        4 -> OutRunStage(c(0.3, 0.17, 0.48), c(1.0, 0.52, 0.3), c(0.5, 0.34, 0.3), c(0.45, 0.3, 0.27), c(0.34, 0.3, 0.36), c(0.31, 0.27, 0.33), c(1.0, 0.85, 0.6), c(0.95, 0.35, 0.2), c(1.0, 0.9, 0.75), 3, 3)
        5 -> OutRunStage(c(0.16, 0.15, 0.4), c(0.72, 0.42, 0.55), c(0.2, 0.36, 0.3), c(0.17, 0.31, 0.26), c(0.3, 0.3, 0.35), c(0.27, 0.27, 0.32), Color.White, c(0.85, 0.15, 0.2), Color.White, 4, 4)
        6 -> OutRunStage(c(0.02, 0.03, 0.1), c(0.13, 0.11, 0.3), c(0.1, 0.11, 0.16), c(0.08, 0.09, 0.13), c(0.21, 0.21, 0.25), c(0.18, 0.18, 0.22), c(0.85, 0.85, 0.9), c(0.8, 0.15, 0.2), c(1.0, 0.85, 0.3), 5, 5)
        else -> OutRunStage(c(0.04, 0.0, 0.1), c(0.4, 0.03, 0.34), c(0.12, 0.02, 0.2), c(0.08, 0.01, 0.14), c(0.14, 0.08, 0.2), c(0.11, 0.06, 0.16), c(0.3, 1.0, 0.95), c(1.0, 0.2, 0.75), c(0.4, 1.0, 0.95), 6, 6)
    }

    fun hash(i: Int): Double {
        val v = sin(i * 12.9898 + 78.233) * 43758.5453
        return v - floor(v)
    }

    private class Row(val y: Double, val c: Double, val h: Double, val even: Boolean)

    fun road(d: DrawScope, W: Double, H: Double, hy: Double, maxHalf: Double, curve: Double, distance: Double, st: OutRunStage) = with(d) {
        val top = hy * H
        val rows = ArrayList<Row>()
        var y = top
        val stepY = 2.0 * density
        while (y <= H + 2) {
            val t = min(1.0, max(0.0, (y - top) / max(1.0, H - top)))
            val half = maxHalf * (0.08 + 0.92 * t) * W
            val center = (0.5 + curve * 0.35 * (1 - t)) * W
            val ph = distance * 1.1 + (1 - t).pow(2) * 26
            rows.add(Row(y, center, half, floor(ph).toInt() % 2 == 0))
            y += stepY
        }
        if (rows.size <= 1) return@with
        var i = 0
        while (i < rows.size - 1) {
            var j = i
            while (j + 1 < rows.size - 1 && rows[j + 1].even == rows[i].even) j++
            val seg = rows.subList(i, j + 2)
            val even = rows[i].even
            fun band(l: (Row) -> Double, r: (Row) -> Double): Path {
                val p = Path()
                p.m(l(seg[0]), seg[0].y)
                for (k in 1 until seg.size) p.l(l(seg[k]), seg[k].y)
                for (k in seg.indices.reversed()) p.l(r(seg[k]), seg[k].y)
                p.close()
                return p
            }
            rect(0.0, seg[0].y, W, seg.last().y - seg[0].y + 0.6, if (even) st.groundA else st.groundB)
            drawPath(band({ it.c - it.h * 1.14 }, { it.c + it.h * 1.14 }), if (even) st.rumbleA else st.rumbleB)
            drawPath(band({ it.c - it.h }, { it.c + it.h }), if (even) st.roadA else st.roadB)
            drawPath(band({ it.c - it.h * 0.97 }, { it.c - it.h * 0.935 }), st.lane.op(0.85))
            drawPath(band({ it.c + it.h * 0.935 }, { it.c + it.h * 0.97 }), st.lane.op(0.85))
            if (even) for (k in listOf(-1.0 / 3, 1.0 / 3)) drawPath(band({ it.c + it.h * (k - 0.018) }, { it.c + it.h * (k + 0.018) }), st.lane)
            i = j + 1
        }
        rect(0.0, top, W, (H - top) * 0.12, vgrad(listOf(st.skyBottom.op(0.55), st.skyBottom.op(0.0)), top, top + (H - top) * 0.12))
    }

    fun prop(d: DrawScope, kind: Int, gx: Double, gy: Double, s: Double, H: Double, side: Double, variant: Int) {
        when (kind) {
            0 -> palm(d, gx, gy, H * 0.5 * s, -side, c(0.62, 0.44, 0.26), c(0.16, 0.58, 0.22), 0)
            1 -> roundTree(d, gx, gy, H * 0.34 * s, variant)
            2 -> cactus(d, gx, gy, H * 0.3 * s, variant)
            3 -> palm(d, gx, gy, H * 0.5 * s, -side, c(0.16, 0.08, 0.14), c(0.14, 0.07, 0.12), 1)
            4 -> pine(d, gx, gy, H * 0.42 * s)
            5 -> lamp(d, gx, gy, H * 0.46 * s, side)
            else -> palm(d, gx, gy, H * 0.5 * s, -side, c(1.0, 0.25, 0.75), c(0.3, 1.0, 0.95), 2)
        }
    }

    fun palm(d: DrawScope, gx: Double, gy: Double, h: Double, lean: Double, trunk: Color, leaf: Color, style: Int) = with(d) {
        if (h <= 4) return@with
        val topX = gx + lean * h * 0.3; val topY = gy - h
        val cx = gx + lean * h * 0.02; val cy = gy - h * 0.6
        fun bez(t: Double): P { val u = 1 - t; return P(u * u * gx + 2 * u * t * cx + t * t * topX, u * u * gy + 2 * u * t * cy + t * t * topY) }
        val left = ArrayList<P>(); val right = ArrayList<P>()
        for (i in 0..10) {
            val t = i / 10.0
            val p = bez(t); val a = bez(max(0.0, t - 0.05)); val b = bez(min(1.0, t + 0.05))
            val len = max(0.001, hypot(b.x - a.x, b.y - a.y))
            val nx = -(b.y - a.y) / len; val ny = (b.x - a.x) / len
            val w = h * (0.048 - 0.022 * t)
            left.add(P(p.x + nx * w, p.y + ny * w)); right.add(P(p.x - nx * w, p.y - ny * w))
        }
        val stem = polyPath(left + right.reversed())
        if (style == 2) {
            strokePath(stem, trunk.op(0.3), max(2.0, h * 0.035))
            strokePath(stem, trunk, max(1.0, h * 0.01))
        } else {
            if (style == 0) oval(gx - h * 0.12, gy - h * 0.02, h * 0.24, h * 0.05, Color.Black.op(0.18))
            drawPath(stem, trunk)
            if (style == 0 && h > 60 * density / 2) {
                for (i in 1 until 10) {
                    val t = i / 10.0
                    val a = left[i]; val b = right[i]
                    val ring = Path(); ring.m(a.x, a.y)
                    ring.q((a.x + b.x) / 2 + (bez(t).x - bez(max(0.0, t - 0.1)).x), (a.y + b.y) / 2 + h * 0.012, b.x, b.y)
                    strokePath(ring, trunk.shade(0.35), max(0.5, h * 0.008))
                }
            }
        }
        listOf(-172.0, -142.0, -112.0, -78.0, -44.0, -14.0, 16.0).forEachIndexed { i, a ->
            val rad = a * PI / 180
            val L = h * (0.36 + 0.05 * (i % 2))
            val tx = topX + cos(rad) * L; val ty = topY + sin(rad) * L * 0.55 + L * 0.35
            val mx = (topX + tx) / 2; val my = min(topY, ty) - L * 0.16
            val frond = Path(); frond.m(topX, topY); frond.q(mx, my - L * 0.1, tx, ty); frond.q(mx, my + L * 0.12, topX, topY)
            when (style) {
                2 -> { strokePath(frond, leaf.op(0.3), max(2.0, h * 0.03)); strokePath(frond, leaf, max(1.0, h * 0.008)) }
                1 -> drawPath(frond, leaf)
                else -> {
                    drawPath(frond, if (i % 2 == 0) leaf else leaf.lit(0.15))
                    if (h > 50 * density / 2) {
                        val rib = Path(); rib.m(topX, topY); rib.q(mx, my, tx, ty)
                        strokePath(rib, leaf.shade(0.35), max(0.5, h * 0.006))
                    }
                }
            }
        }
        if (style == 0 && h > 30) for ((dx, dy) in listOf(-0.035 to 0.03, 0.03 to 0.035, 0.0 to 0.06)) {
            circle(topX + dx * h, topY + dy * h, h * 0.03, c(0.45, 0.28, 0.12))
        }
    }

    fun roundTree(d: DrawScope, gx: Double, gy: Double, h: Double, variant: Int) = with(d) {
        if (h <= 4) return@with
        oval(gx - h * 0.26, gy - h * 0.04, h * 0.52, h * 0.1, Color.Black.op(0.2))
        rect(gx - h * 0.05, gy - h * 0.46, h * 0.1, h * 0.46, c(0.42, 0.28, 0.15))
        val tint = if (variant % 3 == 0) 0.06 else 0.0
        val dark = c(0.1 + tint, 0.42, 0.16); val mid = c(0.18 + tint, 0.56, 0.22); val light = c(0.34 + tint, 0.72, 0.3)
        for ((p, col) in listOf(Triple(-0.15, -0.6, 0.24) to dark, Triple(0.15, -0.62, 0.24) to dark, Triple(0.0, -0.8, 0.28) to mid, Triple(-0.07, -0.86, 0.12) to light)) {
            circle(gx + p.first * h, gy + p.second * h, p.third * h, col)
        }
    }

    fun cactus(d: DrawScope, gx: Double, gy: Double, h: Double, variant: Int) = with(d) {
        if (h <= 4) return@with
        val w = h * 0.17
        val green = c(0.3, 0.58, 0.3); val dark = c(0.15, 0.36, 0.18)
        oval(gx - h * 0.22, gy - h * 0.03, h * 0.44, h * 0.08, Color.Black.op(0.2))
        val body = Path()
        fun rr(x: Double, y: Double, ww: Double, hh: Double) = body.addRoundRect(RoundRect(x.f, y.f, (x + ww).f, (y + hh).f, CornerRadius((w / 2).f)))
        val lh = if (variant % 2 == 0) 0.5 else 0.58
        rr(gx - w / 2, gy - h, w, h)
        rr(gx - w * 1.7, gy - h * lh - w * 0.5, w * 1.4, w)
        rr(gx - w * 1.7, gy - h * (lh + 0.28), w, h * 0.3)
        rr(gx + w * 0.3, gy - h * 0.62 - w * 0.5, w * 1.4, w)
        rr(gx + w * 0.7, gy - h * 0.86, w, h * 0.3)
        drawPath(body, hgrad(listOf(green.lit(0.2), green, dark), gx - w * 1.7, gx + w * 1.7))
        for (dx in listOf(-0.18, 0.18)) line(gx + dx * w, gy - h * 0.95, gx + dx * w, gy - h * 0.05, dark.op(0.6), max(0.5, w * 0.08), androidx.compose.ui.graphics.StrokeCap.Butt)
    }

    fun pine(d: DrawScope, gx: Double, gy: Double, h: Double) = with(d) {
        if (h <= 4) return@with
        rect(gx - h * 0.035, gy - h * 0.16, h * 0.07, h * 0.16, c(0.3, 0.2, 0.14))
        val greens = listOf(c(0.08, 0.26, 0.2), c(0.1, 0.31, 0.24), c(0.13, 0.36, 0.28))
        for (k in 0 until 3) {
            val bottom = gy - h * (0.12 + k * 0.22)
            val w = h * (0.34 - k * 0.08)
            drawPath(polyPath(gx - w, bottom, gx + w, bottom, gx, bottom - h * 0.42), greens[k])
            drawPath(polyPath(gx, bottom - h * 0.42, gx - w * 0.3, bottom - h * 0.3, gx + w * 0.3, bottom - h * 0.3), Color.White.op(0.85))
        }
    }

    fun lamp(d: DrawScope, gx: Double, gy: Double, h: Double, side: Double) = with(d) {
        if (h <= 4) return@with
        val hx = gx - side * h * 0.24; val hy = gy - h * 1.02
        circle(hx, hy, h * 0.3, radial(listOf(c(1.0, 0.86, 0.5).op(0.5), c(1.0, 0.86, 0.5).op(0.0)), hx, hy, h * 0.3))
        rect(gx - h * 0.016, gy - h, h * 0.032, h, c(0.42, 0.44, 0.5))
        val arm = Path(); arm.m(gx, gy - h * 0.98); arm.q(gx - side * h * 0.05, gy - h * 1.08, hx, hy)
        strokePath(arm, c(0.42, 0.44, 0.5), max(1.0, h * 0.022))
        rrect(hx - h * 0.06, hy - h * 0.01, h * 0.12, h * 0.035, h * 0.01, c(1.0, 0.95, 0.75))
    }

    fun traffic(d: DrawScope, kind: Int, x: Double, py: Double, w: Double, color: Color, night: Boolean) = with(d) {
        if (w <= 2) return@with
        val h = w * 0.72
        val base = py + h * 0.5
        val glass = c(0.14, 0.18, 0.26)
        val outline = color.shade(0.55)
        val tail = c(1.0, 0.16, 0.12)
        val lw = max(0.6, w * 0.02)
        oval(x - w * 0.54, base - h * 0.12, w * 1.08, h * 0.24, Color.Black.op(0.3))
        for (sx in listOf(-1.0, 1.0)) rrect(x + sx * w * 0.36 - w * 0.09, base - h * 0.32, w * 0.18, h * 0.32, w * 0.03, c(0.08, 0.08, 0.09))
        val paint = vgrad(listOf(color.lit(0.3), color, color.shade(0.3)), base - h, base)
        val lights = ArrayList<DoubleArray>()
        when (kind) {
            0 -> {
                val body = Path(); body.m(x - w * 0.47, base - h * 0.14)
                body.c(x - w * 0.54, base - h * 1.2, x + w * 0.54, base - h * 1.2, x + w * 0.47, base - h * 0.14); body.close()
                drawPath(body, paint); strokePath(body, outline, lw)
                oval(x - w * 0.17, base - h * 0.84, w * 0.34, h * 0.2, glass)
                for (k in 0 until 3) rect(x - w * 0.1, base - h * (0.52 - k * 0.06), w * 0.2, max(0.5, h * 0.025), outline.op(0.7))
                lights.add(doubleArrayOf(x - w * 0.4, base - h * 0.44, w * 0.09, h * 0.13))
                lights.add(doubleArrayOf(x + w * 0.31, base - h * 0.44, w * 0.09, h * 0.13))
                rrect(x - w * 0.46, base - h * 0.22, w * 0.92, h * 0.07, h * 0.03, c(0.8, 0.82, 0.85))
            }
            1 -> {
                val cabin = polyPath(x - w * 0.42, base - h * 0.6, x - w * 0.3, base - h * 0.98, x + w * 0.3, base - h * 0.98, x + w * 0.42, base - h * 0.6)
                drawPath(cabin, color.shade(0.12)); strokePath(cabin, outline, lw)
                drawPath(polyPath(x - w * 0.35, base - h * 0.64, x - w * 0.26, base - h * 0.92, x + w * 0.26, base - h * 0.92, x + w * 0.35, base - h * 0.64), glass)
                rrect(x - w * 0.49, base - h * 0.64, w * 0.98, h * 0.5, h * 0.08, paint)
                rrectStroke(x - w * 0.49, base - h * 0.64, w * 0.98, h * 0.5, h * 0.08, outline, lw)
                lights.add(doubleArrayOf(x - w * 0.46, base - h * 0.54, w * 0.16, h * 0.12))
                lights.add(doubleArrayOf(x + w * 0.3, base - h * 0.54, w * 0.16, h * 0.12))
                rect(x - w * 0.1, base - h * 0.38, w * 0.2, h * 0.1, c(0.95, 0.95, 0.9))
                rrect(x - w * 0.48, base - h * 0.2, w * 0.96, h * 0.07, h * 0.03, c(0.18, 0.18, 0.2))
            }
            2 -> {
                rrect(x - w * 0.46, base - h * 1.38, w * 0.92, h * 1.24, w * 0.07, vgrad(listOf(color.lit(0.35), color, color.shade(0.3)), base - h * 1.4, base))
                rrectStroke(x - w * 0.46, base - h * 1.38, w * 0.92, h * 1.24, w * 0.07, outline, lw)
                for (sx in listOf(-1.0, 1.0)) rrect(x + (if (sx < 0) -w * 0.38 else w * 0.04), base - h * 1.24, w * 0.34, h * 0.3, w * 0.03, glass)
                line(x, base - h * 1.3, x, base - h * 0.24, outline, lw, androidx.compose.ui.graphics.StrokeCap.Butt)
                lights.add(doubleArrayOf(x - w * 0.45, base - h * 0.66, w * 0.07, h * 0.32))
                lights.add(doubleArrayOf(x + w * 0.38, base - h * 0.66, w * 0.07, h * 0.32))
                rrect(x - w * 0.48, base - h * 0.2, w * 0.96, h * 0.07, h * 0.03, c(0.18, 0.18, 0.2))
            }
            else -> {
                oval(x - w * 0.26, base - h * 0.92, w * 0.52, h * 0.52, color.shade(0.15))
                oval(x - w * 0.2, base - h * 0.86, w * 0.4, h * 0.34, glass)
                rrect(x - w * 0.5, base - h * 0.62, w, h * 0.48, h * 0.14, paint)
                rrectStroke(x - w * 0.5, base - h * 0.62, w, h * 0.48, h * 0.14, outline, lw)
                rect(x - w * 0.47, base - h * 0.78, w * 0.94, h * 0.07, c(0.1, 0.1, 0.12))
                for (sx in listOf(-1.0, 1.0)) rect(x + sx * w * 0.36 - w * 0.02, base - h * 0.74, w * 0.04, h * 0.14, c(0.1, 0.1, 0.12))
                lights.add(doubleArrayOf(x - w * 0.44, base - h * 0.5, w * 0.12, h * 0.12))
                lights.add(doubleArrayOf(x - w * 0.29, base - h * 0.5, w * 0.1, h * 0.12))
                lights.add(doubleArrayOf(x + w * 0.19, base - h * 0.5, w * 0.1, h * 0.12))
                lights.add(doubleArrayOf(x + w * 0.32, base - h * 0.5, w * 0.12, h * 0.12))
            }
        }
        for (l in lights) {
            if (night) {
                val cx = l[0] + l[2] / 2; val cy = l[1] + l[3] / 2
                circle(cx, cy, w * 0.16, radial(listOf(tail.op(0.6), tail.op(0.0)), cx, cy, w * 0.16))
            }
            rrect(l[0], l[1], l[2], l[3], min(l[2], l[3]) * 0.3, tail)
        }
    }

    fun playerCar(d: DrawScope, px: Double, py: Double, w: Double, lean: Double, night: Boolean) = with(d) {
        translate(px.f, py.f) {
            rotate((lean * 2.5).f, Offset.Zero) {
                val h = w * 0.62
                val base = h * 0.46
                val red = c(0.88, 0.06, 0.08)
                oval(-w * 0.56, base - h * 0.12, w * 1.12, h * 0.28, Color.Black.op(0.4))
                for (sx in listOf(-1.0, 1.0)) rrect(sx * w * 0.37 - w * 0.11, base - h * 0.44, w * 0.22, h * 0.44, w * 0.04, c(0.06, 0.06, 0.07))
                val screen = polyPath(-w * 0.32, -h * 0.3, -w * 0.25, -h * 0.62, w * 0.25, -h * 0.62, w * 0.32, -h * 0.3)
                drawPath(screen, c(0.7, 0.86, 0.96).op(0.35))
                strokePath(screen, c(0.15, 0.15, 0.18), max(1.0, w * 0.018))
                val shift = -lean * w * 0.02
                val dhx = -w * 0.14 + shift; val dhy = -h * 0.47
                oval(dhx - w * 0.11, dhy + w * 0.02, w * 0.22, w * 0.14, c(0.15, 0.2, 0.4))
                oval(dhx - w * 0.07, dhy - w * 0.08, w * 0.14, w * 0.15, c(0.32, 0.19, 0.1))
                val bx = w * 0.15 + shift; val by = -h * 0.44
                val nana = Path(); nana.m(bx - w * 0.02, by - w * 0.15)
                nana.q(bx - w * 0.12, by - w * 0.03, bx - w * 0.01, by + w * 0.08)
                nana.q(bx + w * 0.1, by - w * 0.03, bx - w * 0.02, by - w * 0.15); nana.close()
                drawPath(nana, hgrad(listOf(c(1.0, 0.93, 0.45), c(0.98, 0.78, 0.12)), bx - w * 0.1, bx + w * 0.1))
                strokePath(nana, c(0.45, 0.3, 0.05), max(0.8, w * 0.012))
                rect(bx - w * 0.03, by - w * 0.19, w * 0.025, w * 0.05, c(0.4, 0.26, 0.1))
                val body = Path()
                body.m(-w * 0.5, base - h * 0.12); body.l(-w * 0.5, -h * 0.14)
                body.q(-w * 0.5, -h * 0.3, -w * 0.36, -h * 0.32); body.l(w * 0.36, -h * 0.32)
                body.q(w * 0.5, -h * 0.3, w * 0.5, -h * 0.14); body.l(w * 0.5, base - h * 0.12); body.close()
                drawPath(body, vgrad(listOf(red.lit(0.35), red, red.shade(0.4)), -h * 0.32, base))
                strokePath(body, red.shade(0.6), max(1.0, w * 0.015))
                rect(-w * 0.34, -h * 0.3, w * 0.68, max(1.0, h * 0.03), Color.White.op(0.35))
                val gx = -w * 0.44; val gy = -h * 0.14; val gw = w * 0.88; val gh = h * 0.3
                rrect(gx, gy, gw, gh, h * 0.04, c(0.07, 0.05, 0.05))
                for (sx in listOf(-1.0, 1.0)) {
                    val lx = if (sx < 0) gx + w * 0.02 else gx + gw - w * 0.22
                    val ly = gy + h * 0.03; val lw2 = w * 0.2; val lh = gh - h * 0.06
                    if (night) {
                        val cx = lx + lw2 / 2; val cy = ly + lh / 2
                        circle(cx, cy, w * 0.2, radial(listOf(c(1.0, 0.2, 0.15).op(0.55), c(1.0, 0.2, 0.15).op(0.0)), cx, cy, w * 0.2))
                    }
                    rect(lx, ly, lw2, lh, c(0.95, 0.12, 0.1))
                }
                for (k in 0 until 5) {
                    val yy = gy + (k + 0.5) * gh / 5
                    rect(gx, yy - h * 0.013, gw, h * 0.026, red.shade(0.15))
                }
                rect(-w * 0.1, gy + gh + h * 0.03, w * 0.2, h * 0.11, c(0.97, 0.97, 0.92))
                rectStroke(-w * 0.1, gy + gh + h * 0.03, w * 0.2, h * 0.11, c(0.2, 0.2, 0.2), 0.8)
                for (sx in listOf(-1.0, 1.0)) {
                    oval(sx * w * 0.27 - w * 0.035, base - h * 0.2, w * 0.07, h * 0.08, c(0.25, 0.25, 0.27))
                    oval(sx * w * 0.27 - w * 0.022, base - h * 0.185, w * 0.044, h * 0.05, Color.Black)
                }
            }
        }
    }

    fun cumulus(d: DrawScope, x: Double, y: Double, size: Double) = with(d) {
        val puffs = listOf(Triple(-0.62, 0.14, 0.28), Triple(-0.3, -0.04, 0.38), Triple(0.06, -0.2, 0.46),
            Triple(0.42, -0.02, 0.36), Triple(0.72, 0.14, 0.26), Triple(0.02, 0.14, 0.4))
        val cloud = Path()
        for (p in puffs) cloud.addOval(androidx.compose.ui.geometry.Rect((x + p.first * size - p.third * size).f, (y + p.second * size - p.third * size).f,
            (x + p.first * size + p.third * size).f, (y + p.second * size + p.third * size).f))
        drawPath(cloud, Brush.verticalGradient(0f to Color.White, 0.5f to Color.White, 1f to c(0.8, 0.86, 0.96), startY = (y - size * 0.6).f, endY = (y + size * 0.55).f))
    }

    fun stars(d: DrawScope, W: Double, H: Double, count: Int) = with(d) {
        for (i in 0 until count) {
            val x = hash(i) * W; val y = hash(i + 500) * H * 0.85
            val r = 0.6 + hash(i + 900) * 1.2
            circle(x, y, r, Color.White.op(0.4 + 0.5 * hash(i + 1300)))
        }
    }

    fun sky(d: DrawScope, W: Double, H: Double, level: Int) = with(d) {
        val st = stage(level)
        val u = density.toDouble()
        rect(0.0, 0.0, W, H, vgrad(listOf(st.skyTop, st.skyBottom), 0.0, H))
        when (st.scenery) {
            0 -> {
                cumulus(this, W * 0.17, H * 0.6, H * 0.5)
                cumulus(this, W * 0.52, H * 0.52, H * 0.68)
                cumulus(this, W * 0.86, H * 0.64, H * 0.48)
                val island = Path(); island.m(W * 0.62, H * 0.92); island.q(W * 0.7, H * 0.76, W * 0.8, H * 0.92); island.close()
                drawPath(island, c(0.24, 0.46, 0.4))
                rect(0.0, H * 0.9, W, H * 0.1, vgrad(listOf(c(0.12, 0.5, 0.78), c(0.2, 0.66, 0.82)), H * 0.9, H))
                for (k in 0 until 14) rect(hash(k + 40) * W, H * (0.92 + 0.07 * hash(k + 80)), W * 0.05, u, Color.White.op(0.55))
            }
            1 -> {
                cumulus(this, W * 0.25, H * 0.45, H * 0.42)
                cumulus(this, W * 0.74, H * 0.38, H * 0.5)
                for ((layer, col) in listOf(0 to c(0.38, 0.62, 0.42), 1 to c(0.26, 0.52, 0.3))) {
                    val hills = Path(); hills.m(0.0, H)
                    var x = 0.0
                    while (x <= W) {
                        val yy = H * (if (layer == 0) 0.76 else 0.86) - sin(x / W * (if (layer == 0) 9 else 14) + layer) * H * 0.07
                        hills.l(x, yy); x += W / 60
                    }
                    hills.l(W, H); hills.close()
                    drawPath(hills, col)
                }
            }
            2 -> {
                val sx = W * 0.72; val sy = H * 0.3
                circle(sx, sy, H * 0.3, radial(listOf(c(1.0, 0.97, 0.8), c(1.0, 0.9, 0.6).op(0.0)), sx, sy, H * 0.3))
                for ((x0, wd, ht) in listOf(Triple(0.02, 0.16, 0.3), Triple(0.22, 0.1, 0.44), Triple(0.36, 0.2, 0.24), Triple(0.6, 0.12, 0.36), Triple(0.8, 0.18, 0.28))) {
                    drawPath(polyPath(W * x0, H, W * (x0 + 0.02), H * (1 - ht), W * (x0 + wd - 0.02), H * (1 - ht), W * (x0 + wd), H),
                        vgrad(listOf(c(0.78, 0.4, 0.24), c(0.6, 0.28, 0.16)), H * (1 - ht), H))
                    rect(W * (x0 + 0.02), H * (1 - ht * 0.6), W * (wd - 0.04), max(1.0, H * 0.02), c(0.52, 0.24, 0.14).op(0.7))
                }
            }
            3 -> {
                val sx = W * 0.5; val sy = H * 0.88; val r = H * 0.42
                circle(sx, sy, r * 1.8, radial(listOf(c(1.0, 0.7, 0.35).op(0.5), Color.Transparent), sx, sy, r * 1.8))
                circle(sx, sy, r, vgrad(listOf(c(1.0, 0.92, 0.5), c(1.0, 0.45, 0.2)), sy - r, sy + r))
                for (k in 0 until 4) rect(W * (0.05 + 0.25 * k), H * (0.2 + 0.12 * hash(k)), W * 0.2, H * 0.03, c(0.55, 0.25, 0.5).op(0.55))
                rect(0.0, H * 0.9, W, H * 0.1, c(0.3, 0.16, 0.34))
                for (k in 0 until 6) {
                    val ww = W * 0.12 * (1 - k * 0.12)
                    rect(sx - ww / 2, H * (0.915 + k * 0.014), ww, 1.5 * u, c(1.0, 0.7, 0.35).op(0.8))
                }
            }
            4 -> {
                oval(W * 0.78, H * 0.16, H * 0.14, H * 0.14, c(0.98, 0.95, 0.85))
                for ((layer, col) in listOf(0 to c(0.36, 0.3, 0.56), 1 to c(0.24, 0.2, 0.4))) {
                    val ridge = Path(); ridge.m(0.0, H)
                    val peaks = ArrayList<P>()
                    val n = if (layer == 0) 7 else 10
                    for (k in 0..n) {
                        val x = W * k / n
                        val yy = H * (if (layer == 0) 0.42 else 0.66) + H * (if (layer == 0) 0.3 else 0.22) * hash(k * 3 + layer * 50)
                        val pnt = P(x, if (k % 2 == 0) yy else min(H * 0.97, yy + H * 0.16))
                        ridge.l(pnt.x, pnt.y)
                        if (k % 2 == 0) peaks.add(pnt)
                    }
                    ridge.l(W, H); ridge.close()
                    drawPath(ridge, col)
                    if (layer == 0) for (pk in peaks) drawPath(polyPath(pk.x, pk.y, pk.x - W * 0.035, pk.y + H * 0.08, pk.x + W * 0.035, pk.y + H * 0.08), Color.White.op(0.9))
                }
            }
            5 -> {
                stars(this, W, H, 70)
                oval(W * 0.2, H * 0.12, H * 0.16, H * 0.16, c(0.96, 0.94, 0.85))
                var x = 0.0; var k = 0
                while (x < W) {
                    val bw = W * (0.035 + 0.04 * hash(k + 7))
                    val bh = H * (0.16 + 0.36 * hash(k + 19))
                    rect(x, H - bh, bw, bh, c(0.05, 0.06, 0.15))
                    var wy = H - bh + 3 * u; var row = 0
                    while (wy < H - 3 * u) {
                        var wx = x + 2 * u; var col = 0
                        while (wx < x + bw - 3 * u) {
                            if (hash(k * 131 + row * 17 + col) > 0.55) rect(wx, wy, 2 * u, 2 * u, c(1.0, 0.85, 0.4).op(0.85))
                            wx += 5 * u; col++
                        }
                        wy += 6 * u; row++
                    }
                    x += bw + u; k++
                }
            }
            else -> {
                stars(this, W, H, 50)
                val sx = W * 0.5; val sy = H * 0.9; val r = H * 0.5
                val disc = Path().apply { addOval(androidx.compose.ui.geometry.Rect((sx - r).f, (sy - r).f, (sx + r).f, (sy + r).f)) }
                clipPath(disc) {
                    rect(sx - r, sy - r, r * 2, r * 2, vgrad(listOf(c(1.0, 0.92, 0.3), c(1.0, 0.45, 0.4), c(1.0, 0.15, 0.6)), sy - r, sy + r * 0.4))
                    for (k in 0 until 6) {
                        val yy = sy - r * 0.1 + k * r * 0.12
                        rect(sx - r, yy, r * 2, r * (0.02 + 0.012 * k), st.skyBottom)
                    }
                }
                val ridge = Path(); ridge.m(0.0, H)
                for (k in 0..12) {
                    val xx = W * k / 12
                    val far = abs(xx - sx) / W
                    ridge.l(xx, H - H * (if (k % 2 == 0) 0.1 else 0.2 + 0.4 * far) * (0.6 + 0.4 * hash(k + 3)))
                }
                ridge.l(W, H); ridge.close()
                drawPath(ridge, c(0.08, 0.0, 0.16))
                strokePath(ridge, c(1.0, 0.25, 0.8), 1.5 * u)
            }
        }
    }
}
