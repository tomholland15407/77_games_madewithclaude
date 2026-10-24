package com.gogs.bananagame.games.artilleryduel

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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.GpsFixed
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
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
import kotlin.math.pow
import kotlin.math.sin

/**
 * Reflex — Artillery Duel (iOS ArtilleryDuelGame.swift, id "artillery-duel"): set angle and power,
 * mind the wind, and FIRE a banana shell over the hills at the enemy gun; a direct hit wins. The AI
 * fires back between your shots and sharpens each level. Out of shells or time → level 1. Scorched Earth look.
 */
object ArtilleryDuelGame {
    val definition = GameDefinition(
        id = "artillery-duel",
        title = "Artillery Duel",
        genre = Genre.REFLEX,
        manual = GameManual(
            bullets = listOf(
                "Set your angle and power with the sliders, and mind the wind arrow.",
                "Tap FIRE to lob a shell at the enemy gun across the terrain — a direct hit wins.",
                "The AI fires back between your shots and gets more accurate each level.",
                "Run out of shells or time and it's back to level 1.",
            ),
            bulletsVI = listOf(
                "Đặt góc và lực bằng các thanh trượt, và để ý mũi tên gió.",
                "Chạm BẮN để nã một quả đạn vào khẩu pháo địch bên kia địa hình — trúng thẳng là thắng.",
                "AI bắn trả giữa các lượt của bạn và ngày càng chính xác hơn qua mỗi cấp.",
                "Hết đạn hoặc hết giờ sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> ArtilleryDuelView(level, onWin, onFail) }
    )
}

private const val SAMPLES = 120
private const val GRAVITY = 0.55
private const val LAUNCH_K = 1.25          // power → speed scale

private enum class ADPhase { AIMING, PLAYER_FLY, ENEMY_FLY, FINISHING, DONE }
private class Explosion(val x: Double, val y: Double, val dur: Double, val mushroom: Boolean) { var age = 0.0 }

private class DuelWorld(val level: Int, val isDemo: Boolean) {
    private val li = min(level, 7) - 1
    val aiErrorDeg = listOf(16.0, 13.0, 10.0, 8.0, 6.0, 4.0, 2.0)[li]
    val windMax = listOf(0.0, 0.06, 0.12, 0.16, 0.22, 0.28, 0.34)[li]
    val terrainAmp = listOf(0.10, 0.12, 0.14, 0.17, 0.20, 0.23, 0.26)[li]
    val shells = listOf(8, 7, 6, 6, 5, 5, 4)[li]
    val timeLimit = listOf(45.0, 42.0, 40.0, 38.0, 35.0, 32.0, 30.0)[li]

    var phase = ADPhase.AIMING
    var angle by mutableDoubleStateOf(45.0)
    var power by mutableDoubleStateOf(0.6)
    var wind = 0.0
    var terrain = DoubleArray(0)
    var terrainVersion by mutableIntStateOf(0)
    var player = P(0.12, 0.5); var enemy = P(0.88, 0.5)
    var shell: P? = null
    var svx = 0.0; var svy = 0.0
    val tail = ArrayDeque<P>()
    var shotsLeft = 0
    var timeLeft = timeLimit
    val explosions = mutableListOf<Explosion>()
    var pendingWin: Boolean? = null
    var finishAt = 0.0
    var shakeT0 = -10.0
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    private fun buildTerrain(p1: Double, p2: Double) {
        terrain = DoubleArray(SAMPLES) { i ->
            val x = i.toDouble() / (SAMPLES - 1)
            // Base ground around 0.72; humps rise (smaller y). Edges kept higher for the gun hills.
            val hump = sin(x * PI * 2 + p1) * terrainAmp + sin(x * PI * 4 + p2) * terrainAmp * 0.4
            val edge = -0.06 * cos(x * PI * 2)
            min(0.9, max(0.28, 0.72 - hump - edge))
        }
        terrainVersion++
        player = P(0.12, groundY(0.12) - 0.01); enemy = P(0.88, groundY(0.88) - 0.01)
    }

    fun setup() {
        buildTerrain(rnd(0.0, 2 * PI), rnd(0.0, 2 * PI))
        wind = rnd(-windMax, windMax)
        shotsLeft = shells; shell = null; tail.clear(); explosions.clear(); pendingWin = null
        angle = 45.0; power = 0.6
        phase = ADPhase.AIMING; timeLeft = timeLimit
    }

    /** Level 1 (no wind, gentle hills) on fixed terrain for the manual clip. */
    fun demoSetup() {
        buildTerrain(2.499, 2.303)
        wind = 0.0
        shotsLeft = shells; shell = null; tail.clear(); explosions.clear(); pendingWin = null
        angle = 45.0; power = 0.6
        phase = ADPhase.AIMING; timeLeft = timeLimit
    }

    fun groundY(xf: Double): Double {
        if (terrain.size != SAMPLES) return 0.72
        val f = max(0.0, min(0.999, xf)) * (SAMPLES - 1)
        val i = floor(f).toInt(); val fr = f - i
        val a = terrain[i]; val b = if (i + 1 < SAMPLES) terrain[i + 1] else a
        return a + (b - a) * fr
    }

    fun fire() {
        if (phase != ADPhase.AIMING) return
        shotsLeft--
        launch(player, angle, power, true)
        phase = ADPhase.PLAYER_FLY
        SoundManager.tap(); Haptics.tap()
    }

    private fun launch(from: P, angleDeg: Double, pwr: Double, toRight: Boolean) {
        val a = angleDeg * PI / 180; val speed = pwr * LAUNCH_K
        shell = P(from.x + (if (toRight) 0.02 else -0.02), from.y - 0.02); tail.clear()
        svx = (if (toRight) 1 else -1) * cos(a) * speed; svy = -sin(a) * speed
    }

    fun ageExplosions(dt: Double) { for (e in explosions) e.age += dt; explosions.removeAll { it.age >= it.dur } }

    fun stepShell(dt: Double) {
        val s0 = shell ?: return
        svx += wind * dt; svy += GRAVITY * dt
        val s = P(s0.x + svx * dt, s0.y + svy * dt)
        shell = s
        tail.addLast(s); while (tail.size > 8) tail.removeFirst()
        if (s.x < -0.05 || s.x > 1.05 || s.y > 1.05) { resolveMiss(s); return }
        if (phase == ADPhase.PLAYER_FLY && hypot(s.x - enemy.x, s.y - enemy.y) < 0.045) { beginFinish(true, enemy); return }
        if (phase == ADPhase.ENEMY_FLY && hypot(s.x - player.x, s.y - player.y) < 0.045) { beginFinish(false, player); return }
        if (s.y >= groundY(s.x)) resolveMiss(P(s.x, groundY(s.x)))
    }

    private fun beginFinish(didWin: Boolean, at: P) {
        shell = null; tail.clear()
        explosions.add(Explosion(at.x, at.y, 1.1, true))
        shakeT0 = nowSec()
        pendingWin = didWin
        phase = ADPhase.FINISHING
        finishAt = nowSec() + 1.0
        if (didWin) { Haptics.success(); SoundManager.tap() } else { Haptics.warning(); SoundManager.error() }
    }

    private fun resolveMiss(at: P) {
        shell = null; tail.clear()
        explosions.add(Explosion(at.x, at.y, 0.5, false))
        shakeT0 = nowSec()
        if (phase == ADPhase.PLAYER_FLY) enemyTurn()
        else { if (shotsLeft <= 0) { fail(); return }; phase = ADPhase.AIMING }
    }

    /** Search the angle/power that lands nearest the player, then add the level's error. */
    private fun enemyTurn() {
        var bestAng = 50.0; var bestPwr = 0.6; var bestMiss = Double.MAX_VALUE
        var ang = 25.0
        while (ang <= 80.0) {
            var pwr = 0.3
            while (pwr <= 1.0 + 1e-9) {
                val miss = abs(simulateLandingX(enemy, ang, pwr, false) - player.x)
                if (miss < bestMiss) { bestMiss = miss; bestAng = ang; bestPwr = pwr }
                pwr += 0.05
            }
            ang += 5.0
        }
        // Demo: a fixed +12° error (inside L1's ±16°) — a clear miss mid-field.
        val jitter = if (isDemo) 12.0 else rnd(-aiErrorDeg, aiErrorDeg)
        phase = ADPhase.ENEMY_FLY
        launch(enemy, bestAng + jitter, bestPwr, false)
    }

    private fun simulateLandingX(from: P, angleDeg: Double, pwr: Double, toRight: Boolean): Double {
        val a = angleDeg * PI / 180; val speed = pwr * LAUNCH_K
        var x = from.x + (if (toRight) 0.02 else -0.02); var y = from.y - 0.02
        var vx = (if (toRight) 1 else -1) * cos(a) * speed; var vy = -sin(a) * speed
        repeat(1200) {
            vx += wind * 0.016; vy += GRAVITY * 0.016
            x += vx * 0.016; y += vy * 0.016
            if (x < -0.05 || x > 1.05 || y > 1.05) return x
            if (y >= groundY(x)) return x
        }
        return x
    }

    fun win() { if (phase == ADPhase.DONE) return; phase = ADPhase.DONE; Haptics.success(); SoundManager.tap(); onWin() }
    fun fail() { if (phase == ADPhase.DONE) return; phase = ADPhase.DONE; SoundManager.error(); onFail() }
}

@Composable
private fun ArtilleryDuelView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { DuelWorld(level, isDemo).also { if (isDemo) it.demoSetup() else it.setup() } }
    world.onWin = onWin; world.onFail = onFail
    var demoTick by remember { mutableIntStateOf(0) }
    var demoFire by remember { mutableStateOf(false) }
    var demoPower by remember { mutableStateOf(false) }
    val start = remember { nowSec() }
    val tick by rememberFrameLoop { dt ->
        if (isDemo || world.phase == ADPhase.DONE) return@rememberFrameLoop
        world.timeLeft = max(0.0, world.timeLimit - (nowSec() - start))
        if (world.timeLeft <= 0 && world.phase in listOf(ADPhase.AIMING, ADPhase.PLAYER_FLY, ADPhase.ENEMY_FLY)) { world.fail(); return@rememberFrameLoop }
        world.ageExplosions(dt)
        if (world.phase == ADPhase.PLAYER_FLY || world.phase == ADPhase.ENEMY_FLY) world.stepShell(dt)
        // Hold on the mushroom cloud, then resolve the round.
        if (world.phase == ADPhase.FINISHING && nowSec() >= world.finishAt) { if (world.pendingWin == true) world.win() else world.fail() }
    }

    // Demo: 45° / 60 overshoots, the AI's reply misses, the power eases down to 57, and the second
    // shell drops onto the red gun.
    LaunchedEffect(Unit) {
        if (!isDemo) return@LaunchedEffect
        val dt = 1.0 / 60.0
        suspend fun fly() {
            var frames = 0
            while (isActive && (world.phase == ADPhase.PLAYER_FLY || world.phase == ADPhase.ENEMY_FLY) && frames < 900) {
                frames++; world.ageExplosions(dt); world.stepShell(dt); demoTick++; delay(16)
            }
        }
        suspend fun press() { demoFire = true; world.fire(); delay(150); demoFire = false }
        while (isActive) {
            world.demoSetup(); demoFire = false; demoPower = false
            delay(800)
            press(); fly()
            delay(400)
            demoPower = true
            for (k in 1..24) { world.power = 0.6 + (0.576 - 0.6) * k / 24; delay(25) }
            delay(250)
            demoPower = false
            press(); fly()
            // Let the mushroom cloud bloom, then the real win().
            repeat(60) { world.ageExplosions(dt); demoTick++; delay(16) }
            if (world.phase == ADPhase.FINISHING) { if (world.pendingWin == true) world.win() else world.fail() }
            delay(1000)
        }
    }

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .background(rgb(0.07, 0.07, 0.1)),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        tick; demoTick
        // Shells left (pips) and the wind (a flag, its direction and strength).
        Row(Modifier.height(if (isDemo) 16.dp else 19.dp).padding(top = if (isDemo) 0.dp else 0.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            Canvas(Modifier.size((world.shells * (if (isDemo) 8 else 10)).dp, if (isDemo) 14.dp else 17.dp)) { shellPips(world.shells, world.shotsLeft) }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Canvas(Modifier.size(22.dp, 16.dp)) { windFlag(abs(world.wind), max(0.01, world.windMax), world.wind >= 0) }
                Icon(if (world.wind >= 0) Icons.AutoMirrored.Filled.ArrowForward else Icons.AutoMirrored.Filled.ArrowBack, null,
                    tint = if (abs(world.wind) > 0.18) Color.Red else Color.White, modifier = Modifier.size(if (isDemo) 14.dp else 17.dp))
                Text("%.0f".format(abs(world.wind) * 100), style = ts(if (isDemo) 13.0 else 16.0, FontWeight.Black, Color.White))
            }
        }
        if (!isDemo) {
            val f = world.timeLeft / world.timeLimit
            TimeBar(f, Modifier.fillMaxWidth().padding(horizontal = 56.dp).height(5.dp), fill = if (f < 0.3) rgb(1.0, 0.3, 0.25) else ADBanana)
        }
        Canvas(
            Modifier.fillMaxWidth().weight(1f).padding(horizontal = if (isDemo) 8.dp else 0.dp).clip(RoundedCornerShape(14.dp))
                .graphicsLayer {
                    val t = nowSec() - world.shakeT0
                    if (t in 0.0..0.35) translationX = (7 * density * sin(t / 0.35 * PI * 3) * (1 - t / 0.35)).toFloat()
                }
                .drawWithCache {
                    // Sky and terrain never change during a duel: rendered once.
                    world.terrainVersion
                    val tr = world.terrain.copyOf()
                    val bmp = ImageBitmap(size.width.toInt().coerceAtLeast(1), size.height.toInt().coerceAtLeast(1))
                    CanvasDrawScope().draw(this, layoutDirection, androidx.compose.ui.graphics.Canvas(bmp), size) { scenery(tr, level) }
                    onDrawBehind { drawImage(bmp) }
                }
        ) {
            tick; demoTick
            val w = size.width.toDouble(); val h = size.height.toDouble(); val md = min(w, h)
            tank(world.player.x * w, world.player.y * h, md, ADBanana, world.angle, true)
            tank(world.enemy.x * w, world.enemy.y * h, md, rgb(0.9, 0.3, 0.3), 50.0, false)
            world.shell?.let { s -> shellArt(s.x * w, s.y * h, world.svx * w, world.svy * h, md * 0.05, world.tail.map { P(it.x * w, it.y * h) }) }
            for (e in world.explosions) explosion(e, w, h)
        }
        // Controls: angle and power sliders, and FIRE.
        val aiming = world.phase == ADPhase.AIMING
        Box { Column(Modifier.padding(horizontal = 20.dp).padding(bottom = if (isDemo) 4.dp else 8.dp), verticalArrangement = Arrangement.spacedBy(if (isDemo) 2.dp else 6.dp)) {
            val sliderColors = SliderDefaults.colors(thumbColor = ADBanana, activeTrackColor = ADBanana, inactiveTrackColor = Color.White.op(0.2),
                disabledThumbColor = ADBanana.op(0.6), disabledActiveTrackColor = ADBanana.op(0.5), disabledInactiveTrackColor = Color.White.op(0.12))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Row(Modifier.width(if (isDemo) 92.dp else 110.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Canvas(Modifier.size(if (isDemo) 16.dp else 20.dp)) { angleIcon(world.angle) }
                    Text("${world.angle.toInt()}°", style = ts(if (isDemo) 12.0 else 14.0, FontWeight.Bold, Color.White).copy(fontFeatureSettings = "tnum"))
                }
                Slider(world.angle.toFloat(), { world.angle = it.toDouble() }, Modifier.weight(1f).height(if (isDemo) 24.dp else 36.dp),
                    enabled = aiming, valueRange = 10f..85f, colors = sliderColors)
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Row(Modifier.width(if (isDemo) 92.dp else 110.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Canvas(Modifier.size(if (isDemo) 16.dp else 20.dp)) { powerIcon(world.power) }
                    Text("${(world.power * 100).toInt()}", style = ts(if (isDemo) 12.0 else 14.0, FontWeight.Bold, if (demoPower) ADBanana else Color.White).copy(fontFeatureSettings = "tnum"))
                }
                Box(Modifier.weight(1f)) {
                    Slider(world.power.toFloat(), { world.power = it.toDouble() }, Modifier.fillMaxWidth().height(if (isDemo) 24.dp else 36.dp),
                        enabled = aiming, valueRange = 0.2f..1f, colors = sliderColors)
                    // Demo: a finger riding the power thumb while it's dragged.
                    if (demoPower) {
                        val handP = rememberHand()
                        Canvas(Modifier.matchParentSize()) {
                            val u = density.toDouble(); val s = 22 * u
                            val x = 14 * u + (size.width - 28 * u) * (world.power - 0.2) / 0.8 + 8 * u
                            hand(handP, x - s / 2, size.height / 2.0 + 14 * u - s / 2, s)
                        }
                    }
                }
            }
            val ready = aiming || demoFire
            Box(
                Modifier.fillMaxWidth().scale(if (demoFire) 0.94f else 1f).height(if (isDemo) 33.dp else 46.dp)
                    .then(if (isDemo) Modifier else Modifier.pressDown(onDown = { world.fire() })),
                contentAlignment = Alignment.Center
            ) {
                Canvas(Modifier.fillMaxSize()) {
                    val u = density.toDouble(); val w = size.width.toDouble(); val h = size.height.toDouble(); val r = 14 * u
                    rrect(0.0, 0.0, w, h, r, vgrad(if (ready) listOf(rgb(1.0, 0.9, 0.4), rgb(0.95, 0.68, 0.14)) else listOf(gray(0.34), gray(0.24)), 0.0, h))
                    val lw = (if (demoFire) 2.5 else 1.0) * u
                    rrectStroke(lw / 2, lw / 2, w - lw, h - lw, r - lw / 2, Color.White.op(if (demoFire) 0.95 else 0.2), lw)
                }
                Icon(Icons.Filled.GpsFixed, null, tint = if (ready) rgb(0.25, 0.1, 0.0) else gray(0.6), modifier = Modifier.size(if (isDemo) 19.dp else 22.dp))
            }
        }
            // The live demo is scripted: swallow touches so the sliders can't be dragged off its shot.
            if (isDemo) Box(Modifier.matchParentSize().pointerInput(Unit) {
                awaitPointerEventScope { while (true) awaitPointerEvent().changes.forEach { it.consume() } }
            })
        }
    }
}

// Artillery art (after Scorched Earth; iOS ADArt).

private val ADBanana = rgb(1.0, 0.84, 0.2)
private fun hashD(n: Double): Double { val x = sin(n) * 43758.5453; return x - floor(x) }

/** Sky top/bottom per level: day, afternoon, sunset, dusk, purple night, night, a red storm. */
private fun sky(level: Int) = when (min(max(level, 1), 7)) {
    1 -> rgb(0.34, 0.58, 0.92) to rgb(0.74, 0.87, 0.98)
    2 -> rgb(0.38, 0.54, 0.88) to rgb(0.96, 0.85, 0.7)
    3 -> rgb(0.36, 0.3, 0.6) to rgb(1.0, 0.62, 0.36)
    4 -> rgb(0.24, 0.2, 0.46) to rgb(0.86, 0.46, 0.46)
    5 -> rgb(0.12, 0.1, 0.3) to rgb(0.42, 0.24, 0.44)
    6 -> rgb(0.04, 0.05, 0.16) to rgb(0.18, 0.14, 0.3)
    else -> rgb(0.16, 0.03, 0.05) to rgb(0.5, 0.14, 0.1)
}

private fun DrawScope.explosion(e: Explosion, w: Double, h: Double) {
    val u = density.toDouble()
    val p = min(1.0, e.age / e.dur)
    val md = min(w, h)
    val bx = e.x * w; val by = e.y * h
    val fade = 1 - max(0.0, (p - 0.55) / 0.45)
    val hot = rgb(1.0, 0.55, 0.15)
    if (e.mushroom) {
        val ease = 1 - (1 - p).pow(2)
        val riseH = 0.24 * h * ease
        val capW = (0.05 + 0.15 * ease) * md
        val stemW = 0.055 * md
        val col = hot.mix(gray(0.55), min(1.0, p * 1.3))
        circle(bx, by, md * 0.12 * (0.5 + p), rgb(1.0, 0.92, 0.45, (1 - p) * 0.9))
        drawOval(radial(listOf(hot.op(0.45 * fade), hot.op(0.0)), bx, by - riseH, capW * 1.2), Offset((bx - capW * 1.2).f, (by - riseH - capW * 0.9).f),
            androidx.compose.ui.geometry.Size((capW * 2.4).f, (capW * 1.8).f))
        rrect(bx - stemW / 2, by - riseH, stemW, max(1.0, riseH), stemW / 2, col.op(0.85 * fade))
        for (i in 0 until 3) {
            val dx = listOf(-1.0, 0.0, 1.0)[i] * capW * 0.30
            val cw = capW * (if (i == 1) 1.0 else 0.72)
            oval(bx + dx - cw / 2, by - riseH - capW * 0.32, cw, capW * 0.64, col.op(0.9 * fade))
        }
        circle(bx, by - riseH, capW * 0.25, rgb(1.0, 0.82, 0.32, (1 - p) * fade))
    } else {
        val r = (0.02 + 0.12 * p) * md
        circleStroke(bx, by, r, hot.op(fade), 3 * u)
        circle(bx, by, r / 2, rgb(1.0, 0.82, 0.35, (1 - p) * 0.9))
        for (k in 0 until 6) {
            val a = PI * (1.1 + k * 0.16); val d = r * 1.2
            circle(bx + cos(a) * d, by + sin(a) * d, 2 * u, rgb(0.4, 0.28, 0.16, fade))
        }
    }
}

/** A Scorched Earth tank: treads, a dome, and the barrel at `barrelDeg`. */
private fun DrawScope.tank(bx: Double, by: Double, md: Double, color: Color, barrelDeg: Double, aimRight: Boolean) {
    val u = density.toDouble()
    val a = barrelDeg * PI / 180; val bl = md * 0.06
    val dx = bx; val dy = by - md * 0.006
    val ex = dx + cos(a) * bl * (if (aimRight) 1 else -1); val ey = dy - sin(a) * bl
    line(dx, dy, ex, ey, Color.Black.op(0.6), 6 * u)
    line(dx, dy, ex, ey, color.mix(Color.Black, 0.2), 3.5 * u)
    val r = md * 0.024
    val dome = Path(); dome.m(dx - r, dy)
    for (s in 0..20) { val t = PI + PI * s / 20; dome.l(dx + cos(t) * r, dy + sin(t) * r) }
    dome.close()
    drawPath(dome, vgrad(listOf(color.mix(Color.White, 0.35), color, color.mix(Color.Black, 0.3)), dy - r, dy))
    drawPath(dome, Color.Black.op(0.6), style = Stroke((1.2 * u).f))
    val tx = bx - md * 0.036; val ty = dy - 1; val tw = md * 0.072; val th = md * 0.018
    rrect(tx, ty, tw, th, th / 2, gray(0.2))
    for (k in 0 until 4) circle(tx + tw * (0.16 + k * 0.225), ty + th / 2, th * 0.3, gray(0.5))
}

/** The banana shell, pointing along its flight, with a short comet tail. */
private fun DrawScope.shellArt(px: Double, py: Double, vx: Double, vy: Double, s: Double, trail: List<P>) {
    for (i in 1 until trail.size) {
        val f = i.toDouble() / trail.size
        line(trail[i - 1].x, trail[i - 1].y, trail[i].x, trail[i].y, rgb(1.0, 0.92, 0.6, 0.7 * f), max(0.01, s * 0.3 * f))
    }
    translate(px.f, py.f) { rotateRad(atan2(vy, vx).f, Offset.Zero) { scale(s.f, s.f, Offset.Zero) {
        val b = Path(); b.m(-0.5, -0.1); b.q(0.0, 0.6, 0.5, -0.12); b.q(0.0, 0.1, -0.5, -0.1); b.close()
        drawPath(b, vgrad(listOf(rgb(1.0, 0.96, 0.55), rgb(0.98, 0.76, 0.14)), 0.0, 0.3))
        strokePath(b, rgb(0.3, 0.2, 0.03), 0.07)
        rrect(0.44, -0.22, 0.14, 0.14, 0.03, rgb(0.42, 0.27, 0.08))
    } } }
}

/** The banded sky (stars at night) and the terrain: a grassy rim over layered dirt. */
private fun DrawScope.scenery(terrain: DoubleArray, level: Int) {
    val u = density.toDouble(); val w = size.width.toDouble(); val h = size.height.toDouble()
    val (top, bottom) = sky(level)
    val bands = 12
    for (k in 0 until bands) rect(0.0, h * k / bands, w, h / bands + 1, top.mix(bottom, k.toDouble() / (bands - 1)))
    if (level >= 5) for (i in 0 until 50) {
        val d = (1 + hashD(i * 1.7) * 1.4) * u
        oval(hashD(i * 12.9) * w, hashD(i * 78.2) * h * 0.6, d, d, Color.White.op(0.7))
    }
    if (terrain.size < 2) return
    val ridge = Path()
    for (i in terrain.indices) { val x = i.toDouble() / (terrain.size - 1) * w; val y = terrain[i] * h; if (i == 0) ridge.m(x, y) else ridge.l(x, y) }
    val land = Path(); land.addPath(ridge); land.l(w, h); land.l(0.0, h); land.close()
    val night = level >= 5
    val dirt0 = if (night) rgb(0.3, 0.22, 0.2) else rgb(0.62, 0.44, 0.26)
    val dirt1 = if (night) rgb(0.14, 0.1, 0.1) else rgb(0.36, 0.24, 0.14)
    val topY = terrain.min() * h
    drawPath(land, vgrad(listOf(dirt0, dirt1), topY, h))
    clipPath(land) {
        var y = topY + 10 * u; var k = 0
        while (y < h) {
            val band = Path(); band.m(0.0, y); var x = 0.0
            while (x < w) { val nx = x + 40 * u; band.q(x + 20 * u, y + (hashD(k * 11.0 + x / u) - 0.5) * 8 * u, nx, y); x = nx }
            strokePath(band, Color.Black.op(0.12), 3 * u, StrokeCap.Butt)
            y += 14 * u; k++
        }
    }
    val grass = if (night) rgb(0.18, 0.3, 0.2) else rgb(0.36, 0.62, 0.26)
    strokePath(ridge, grass, 6 * u)
    strokePath(ridge, grass.mix(Color.White, 0.25), 1.5 * u)
}

/** Shells left as little rounds. */
private fun DrawScope.shellPips(total: Int, left: Int) {
    val w = size.width.toDouble(); val h = size.height.toDouble()
    val n = max(1, total); val slot = w / n
    for (i in 0 until n) {
        val x0 = i * slot + slot * 0.2; val rw = slot * 0.6; val y0 = h * 0.15; val rh = h * 0.8
        val p = Path(); p.m(x0, y0 + rh); p.l(x0, y0 + rw * 0.5); p.q(x0 + rw / 2, y0 - rw * 0.3, x0 + rw, y0 + rw * 0.5); p.l(x0 + rw, y0 + rh); p.close()
        if (i < left) fillPath(p, ADBanana) else drawPath(p, Color.White.op(0.3), style = Stroke(density))
    }
}

/** A wind flag that streams further in stronger wind. */
private fun DrawScope.windFlag(strength: Double, windMax: Double, toRight: Boolean) {
    val w = size.width.toDouble(); val h = size.height.toDouble()
    scale(if (toRight) 1f else -1f, 1f) {
        line(w * 0.1, h * 0.05, w * 0.1, h, Color.White, 1.5 * density, StrokeCap.Butt)
        val f = max(0.15, min(1.0, strength / windMax))
        fillPath(polyPath(w * 0.1, h * 0.1, w * 0.1 + w * 0.85 * f, h * (0.2 + 0.1 * (1 - f)), w * 0.1 + w * 0.85 * f, h * (0.42 - 0.1 * (1 - f)), w * 0.1, h * 0.52),
            rgb(1.0, 0.45, 0.25))
    }
}

/** The angle icon: a protractor arc with the barrel line at the current angle. */
private fun DrawScope.angleIcon(deg: Double) {
    val u = density.toDouble(); val w = size.width.toDouble(); val h = size.height.toDouble()
    val ox = w * 0.12; val oy = h * 0.88; val r = w * 0.78
    val arc = Path()
    for (s in 0..16) { val a = -deg * PI / 180 * (1 - s / 16.0); val x = ox + cos(a) * r * 0.6; val y = oy + sin(a) * r * 0.6; if (s == 0) arc.m(x, y) else arc.l(x, y) }
    strokePath(arc, Color.White.op(0.6), 1.5 * u, StrokeCap.Butt)
    val a = deg * PI / 180
    line(ox, oy, ox + r, oy, Color.White, 2 * u)
    line(ox, oy, ox + cos(a) * r, oy - sin(a) * r, Color.White, 2 * u)
}

/** The power icon: three rising bars, lit up to the current power. */
private fun DrawScope.powerIcon(level: Double) {
    val w = size.width.toDouble(); val h = size.height.toDouble()
    for (k in 0 until 3) {
        val bh = h * (0.35 + 0.3 * k)
        val on = level >= 0.2 + 0.8 * k / 3
        rrect(w * (0.08 + 0.32 * k), h - bh, w * 0.24, bh, 1.5 * density, if (on) ADBanana else Color.White.op(0.3))
    }
}
