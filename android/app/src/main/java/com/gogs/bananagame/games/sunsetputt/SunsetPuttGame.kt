package com.gogs.bananagame.games.sunsetputt

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

/**
 * Reflex — Sunset Putt (iOS DesertGolfGame.swift, id "desert-golf"), after Desert Golfing: a flat-shaded
 * side-view course of sand under a flat sky. Drag back from anywhere like a slingshot, let go to shoot,
 * and sink every hole of the level within its stroke budget; leaving the course costs a penalty stroke.
 * Every hole is generated and then verified with the game's own deterministic physics: a shot search
 * must find a robust hole-in-one. The palette slides from midday to night as the levels climb.
 */
object SunsetPuttGame {
    val definition = GameDefinition(
        id = "desert-golf",
        title = "Sunset Putt",
        genre = Genre.REFLEX,
        locksFeed = true,
        manual = GameManual(
            bullets = listOf(
                "Drag back anywhere to aim, like a slingshot; the dotted line shows direction and power.",
                "Let go to shoot, then sink the ball in the hole.",
                "Clear every hole of the level within the stroke budget; leaving the course costs a stroke.",
                "Run out of strokes, or time, and you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Kéo ngược ở bất kỳ đâu để nhắm như ná cao su; đường chấm cho thấy hướng và lực.",
                "Thả tay để đánh, rồi đưa bóng vào lỗ.",
                "Hoàn thành mọi lỗ của cấp trong số gậy cho phép; bóng ra ngoài sân bị phạt một gậy.",
                "Hết gậy, hoặc hết giờ, bạn về lại cấp 1.",
            ),
            liveDemo = true
        ),
        prefetch = { level -> BoardCache.prefetch(key(level)) { DGGen.course(DGGen.params(level), DGGen.holes(level)) } },
        content = { level, onWin, onFail -> SunsetPuttView(level, onWin, onFail) }
    )

    fun key(level: Int) = BoardCache.key("desert-golf", level)
}

/** One hole. Units: the play area's width is 1.0; y points UP from the bottom edge. */
class DGHole(
    val xs: DoubleArray, val ys: DoubleArray, val teeX: Double, val teeY: Double,
    val cupL: Double, val cupR: Double, val lipY: Double, val floorY: Double,
)

class DGBall(var x: Double, var y: Double, var vx: Double = 0.0, var vy: Double = 0.0, var rest: Double = 0.0, var time: Double = 0.0)

enum class DGOutcome { MOVING, REST, SUNK, OUT }

object DGPhysics {
    const val R = 0.013
    const val G = 1.8
    const val VMAX = 1.7
    const val DT = 1.0 / 60

    /** One fixed 1/60 s frame (8 substeps) of flight / rolling against the course polyline. */
    fun step(b: DGBall, h: DGHole): DGOutcome {
        val sub = 8
        val hs = DT / sub
        var contact = false
        var slope = 0.0
        var wedged = false
        repeat(sub) {
            b.vy -= G * hs
            b.x += b.vx * hs
            b.y += b.vy * hs
            var touched = false
            var loNx = 9.0; var hiNx = -9.0     // the sideways lean of the ground pushing on the ball this substep
            for (i in 0 until h.xs.size - 1) {
                val x0 = h.xs[i]; val x1 = h.xs[i + 1]
                if (max(x0, x1) < b.x - R || min(x0, x1) > b.x + R) continue
                val y0 = h.ys[i]; val y1 = h.ys[i + 1]
                val dx = x1 - x0; val dy = y1 - y0
                val len2 = dx * dx + dy * dy
                var t = if (len2 > 0) ((b.x - x0) * dx + (b.y - y0) * dy) / len2 else 0.0
                t = min(max(t, 0.0), 1.0)
                val cx = x0 + t * dx; val cy = y0 + t * dy
                var nx = b.x - cx; var ny = b.y - cy
                val d = sqrt(nx * nx + ny * ny)
                if (d >= R) continue
                if (d > 1e-9) { nx /= d; ny /= d } else { val l = sqrt(len2); nx = -dy / l; ny = dx / l }
                b.x = cx + nx * R
                b.y = cy + ny * R
                val vn = b.vx * nx + b.vy * ny
                if (vn < 0) {
                    // Sand: a low bounce on hard hits, none on soft ones, plus impact drag.
                    val e = if (vn < -0.35) 0.32 else 0.0
                    b.vx -= (1 + e) * vn * nx
                    b.vy -= (1 + e) * vn * ny
                    val tx = -ny; val ty = nx
                    val vt = b.vx * tx + b.vy * ty
                    val loss = min(1.0, 0.3 * -vn / max(abs(vt), 1e-6))
                    b.vx -= tx * vt * loss
                    b.vy -= ty * vt * loss
                }
                touched = true
                slope = if (abs(dx) > 1e-9) abs(dy / dx) else 99.0
                if (ny > -0.05) { loNx = min(loNx, nx); hiNx = max(hiNx, nx) }
            }
            // Held from both sides (the walls of a crack, or the floor and the foot of a wall): gravity
            // can't roll it out. A ball tipping over one edge pushes against a single point, so it isn't.
            if (hiNx - loNx > 0.2 && loNx < 0.05 && hiNx > -0.05) wedged = true
            if (touched) {
                contact = true
                val k = 1 - 1.5 * hs          // rolling resistance in sand
                b.vx *= k
                b.vy *= k
            }
        }
        b.time += DT
        val speed = sqrt(b.vx * b.vx + b.vy * b.vy)
        // In the cup below the lip and slow enough: holed.
        if (b.x > h.cupL && b.x < h.cupR && b.y < h.lipY && speed < 0.9) return DGOutcome.SUNK
        if (b.x < -0.03 || b.x > 1.03) return DGOutcome.OUT
        // Static friction: a slow ball on a gentle slope, or wedged in a crack, comes to rest.
        if (contact && speed < 0.035 && (slope < 0.5 || wedged)) {
            if (slope < 0.5) { b.vx = 0.0; b.vy = 0.0 }
            b.rest += DT
            if (b.rest > 0.3) return DGOutcome.REST
        } else {
            b.rest = 0.0
        }
        if (b.time > 9) return DGOutcome.REST
        return DGOutcome.MOVING
    }

    fun launch(x: Double, y: Double, angle: Double, power: Double): DGBall {
        val v = VMAX * min(max(power, 0.0), 1.0)
        return DGBall(x, y, cos(angle) * v, sin(angle) * v)
    }

    fun simulate(h: DGHole, x: Double, y: Double, angle: Double, power: Double): DGOutcome {
        val b = launch(x, y, angle, power)
        while (true) {
            val o = step(b, h)
            if (o != DGOutcome.MOVING) return o
        }
    }
}

object DGGen {
    /** `features`: 0 none, 1 mound, 2 mound / wall / plateau, 3 plus pits and fall-offs. */
    class Params(val cupLo: Double, val cupHi: Double, val amp: Double, val features: Int)

    fun holes(level: Int) = listOf(2, 3, 3, 4, 4, 5, 5)[min(max(level, 1), 7) - 1]
    fun budget(level: Int) = listOf(6, 8, 7, 8, 7, 7, 6)[min(max(level, 1), 7) - 1]
    fun params(level: Int) = listOf(
        Params(0.55, 0.7, 0.04, 0), Params(0.6, 0.8, 0.06, 1), Params(0.65, 0.85, 0.08, 1),
        Params(0.7, 0.88, 0.1, 2), Params(0.72, 0.9, 0.12, 2), Params(0.75, 0.92, 0.14, 3), Params(0.78, 0.93, 0.16, 3),
    )[min(max(level, 1), 7) - 1]

    /** A shot (angle, power) that sinks the hole AND keeps sinking under small nudges. */
    fun robustShot(h: DGHole, deterministic: Boolean = false): Pair<Double, Double>? {
        val x = h.teeX; val y = h.teeY + DGPhysics.R
        val angles = (0..35).map { 10.0 + it * 2.0 }.toMutableList()
        val powers = (0..20).map { 0.2 + it * 0.04 }.toMutableList()
        if (!deterministic) { angles.shuffle(); powers.shuffle() }
        for (a in angles) for (p in powers) {
            if (DGPhysics.simulate(h, x, y, a * PI / 180, p) != DGOutcome.SUNK) continue
            val nudges = listOf(a - 1 to p, a + 1 to p, a to p - 0.02, a to p + 0.02)
            val ok = nudges.count { DGPhysics.simulate(h, x, y, it.first * PI / 180, it.second) == DGOutcome.SUNK }
            if (ok >= 2) return a * PI / 180 to p
        }
        return null
    }

    fun hole(p: Params): DGHole {
        repeat(40) {
            val h = build(p)
            if (robustShot(h) != null) return h
        }
        return fallback()
    }

    fun build(p: Params): DGHole {
        val teeX = rnd(0.08, 0.13)
        val teeY = rnd(0.2, 0.36)
        val cupX = rnd(p.cupLo, p.cupHi)
        val cupW = 0.05; val depth = 0.032
        var greenY = rnd(0.18, 0.4)
        val xs = mutableListOf(-0.06, teeX + 0.055)
        val ys = mutableListOf(teeY, teeY)
        // Rolling middle ground.
        val startX = teeX + 0.1; val endX = cupX - 0.13
        val n = max(2, ((endX - startX) / 0.075).toInt())
        var feature = -1
        if (p.features >= 1 && n >= 3) feature = rndInt(1 until n - 1)
        val kind = if (p.features >= 2) rndInt(0..2) else 0     // 0 mound, 1 wall, 2 raised green
        if (p.features >= 2 && kind == 2) greenY = min(0.52, greenY + rnd(0.08, 0.16))
        for (k in 0 until n) {
            val f = k.toDouble() / max(1, n - 1)
            val x = startX + (endX - startX) * f
            // Random relief fades out toward the tee and the green so both sit on level ground.
            var y = teeY + (greenY - teeY) * f + rnd(-p.amp, p.amp) * sin(PI * min(1.0, 0.15 + f * 0.85))
            if (k == feature) {
                if (kind == 1) {
                    // A near-vertical wall: two close vertices, the far one tall.
                    xs.add(x); ys.add(max(0.08, y))
                    y = min(0.62, max(y, greenY) + rnd(0.12, 0.2))
                    xs.add(x + 0.012); ys.add(y)
                    continue
                }
                y = min(0.62, maxOf(y, teeY, greenY) + rnd(0.08, 0.16) + p.amp * 0.5)
            }
            if (p.features >= 3 && k == n - 1 && Random.nextBoolean()) {
                y = max(0.06, greenY - rnd(0.08, 0.15))     // a pit in front of the green
            }
            xs.add(x); ys.add(min(0.62, max(0.06, y)))
        }
        // Green with the cup notch.
        xs += listOf(cupX - 0.1, cupX - cupW / 2, cupX - cupW / 2, cupX + cupW / 2, cupX + cupW / 2, cupX + 0.09)
        ys += listOf(greenY, greenY, greenY - depth, greenY - depth, greenY, greenY)
        // Beyond the hole: a backstop on easy holes, flat or falling away on hard ones.
        val behind = if (p.features <= 1) rnd(0.06, 0.14) else if (p.features == 2) 0.0 else -rnd(0.05, 0.12)
        var x = cupX + 0.16
        while (x < 1.08) {
            xs.add(x)
            ys.add(min(0.66, max(0.05, greenY + behind * ((x - cupX) / 0.3) + rnd(-0.02, 0.02))))
            x += 0.08
        }
        xs.add(1.12); ys.add(ys.last())
        return DGHole(xs.toDoubleArray(), ys.toDoubleArray(), teeX, teeY, cupX - cupW / 2, cupX + cupW / 2, greenY, greenY - depth)
    }

    /** A gentle known-good hole (never needed in practice; the verifier almost always succeeds). */
    fun fallback() = DGHole(
        doubleArrayOf(-0.06, 0.18, 0.3, 0.45, 0.55, 0.575, 0.575, 0.625, 0.625, 0.7, 0.85, 1.12),
        doubleArrayOf(0.3, 0.3, 0.26, 0.24, 0.24, 0.24, 0.208, 0.208, 0.24, 0.24, 0.32, 0.36),
        0.11, 0.3, 0.575, 0.625, 0.24, 0.208)

    fun course(p: Params, holes: Int): List<DGHole> = List(holes) { hole(p) }

    /** The manual clip's fixed level-1 hole. */
    val demoHole = DGHole(
        doubleArrayOf(-0.06, 0.17, 0.26, 0.36, 0.46, 0.55, 0.6, 0.675, 0.675, 0.725, 0.725, 0.8, 0.9, 1.12),
        doubleArrayOf(0.3, 0.3, 0.27, 0.33, 0.28, 0.24, 0.23, 0.23, 0.198, 0.198, 0.23, 0.23, 0.3, 0.34),
        0.11, 0.3, 0.675, 0.725, 0.23, 0.198)

    /** Found offline on iOS: 20°, power 0.57 — robust to ±1° / ±0.01. Used if it still sinks here. */
    fun verifiedDemoShot(): Pair<Double, Double> {
        val h = demoHole
        val a = 20.0 * PI / 180; val p = 0.57
        if (DGPhysics.simulate(h, h.teeX, h.teeY + DGPhysics.R, a, p) == DGOutcome.SUNK) return a to p
        return demoShot()
    }

    /** The robust hole-in-one with the lowest arc. */
    fun demoShot(): Pair<Double, Double> {
        val h = demoHole
        val x = h.teeX; val y = h.teeY + DGPhysics.R
        var best: Triple<Double, Double, Double>? = null
        for (ai in 0..40) for (pi in 0..60) {
            val a = 20.0 + ai; val p = 0.3 + pi * 0.01
            if (DGPhysics.simulate(h, x, y, a * PI / 180, p) != DGOutcome.SUNK) continue
            val nudged = listOf(a - 1 to p, a + 1 to p, a to p - 0.01, a to p + 0.01).count {
                DGPhysics.simulate(h, x, y, it.first * PI / 180, it.second) == DGOutcome.SUNK
            }
            if (nudged < 3) continue
            val v = DGPhysics.VMAX * p * sin(a * PI / 180)
            val apex = v * v / (2 * DGPhysics.G)
            if (best == null || apex < best.third) best = Triple(a * PI / 180, p, apex)
        }
        return best?.let { it.first to it.second } ?: (0.8 to 0.6)
    }
}

private enum class Phase { LOADING, AIM, FLYING, SINKING, SLIDING, WON, DONE }

/** Midday → dusk → night, like the original's slowly shifting desert: sky, sand, ink. */
private fun palette(level: Int): Triple<Color, Color, Color> = listOf(
    Triple(rgb(0.78, 0.86, 0.9), rgb(0.87, 0.63, 0.36), rgb(0.3, 0.22, 0.16)),
    Triple(rgb(0.82, 0.86, 0.86), rgb(0.85, 0.6, 0.35), rgb(0.3, 0.22, 0.16)),
    Triple(rgb(0.89, 0.84, 0.76), rgb(0.8, 0.54, 0.32), rgb(0.3, 0.2, 0.14)),
    Triple(rgb(0.95, 0.78, 0.62), rgb(0.74, 0.47, 0.3), rgb(0.32, 0.18, 0.12)),
    Triple(rgb(0.86, 0.62, 0.57), rgb(0.64, 0.4, 0.34), rgb(0.28, 0.14, 0.12)),
    Triple(rgb(0.52, 0.49, 0.66), rgb(0.52, 0.36, 0.42), gray(0.96)),
    Triple(rgb(0.25, 0.29, 0.47), rgb(0.4, 0.31, 0.44), gray(0.96)),
)[min(max(level, 1), 7) - 1]

private class Golf(val level: Int) {
    val holes = DGGen.holes(level)
    val budget = DGGen.budget(level)
    val timeLimit = holes * 26.0 + 20
    var phase = Phase.LOADING
    var course: List<DGHole> = emptyList()
    var index = 0
    var ball = DGBall(0.1, 0.3)
    var lastX = 0.1; var lastY = 0.3
    var strokes = 0
    var aim: Pair<Double, Double>? = null      // angle, power
    var slide = 0.0                            // 0…1 while panning to the next hole
    var sinkT = 0.0
    var flash = 0.0                            // out-of-bounds flash
    var timeLeft = timeLimit
    var onFail: () -> Unit = {}

    fun placeOnTee() {
        if (index >= course.size) return
        val h = course[index]
        ball = DGBall(h.teeX, h.teeY + DGPhysics.R)
        lastX = ball.x; lastY = ball.y
    }

    fun shoot() {
        val a = aim
        if (phase != Phase.AIM || a == null || a.second <= 0.06 || index >= course.size) { aim = null; return }
        ball = DGPhysics.launch(ball.x, ball.y, a.first, a.second)
        strokes++
        aim = null
        phase = Phase.FLYING
        SoundManager.tap(); Haptics.tap()
    }

    /** Advances one fixed physics frame; returns true when the level has failed. */
    fun tick(): Boolean {
        when (phase) {
            Phase.FLYING -> when (DGPhysics.step(ball, course[index])) {
                DGOutcome.MOVING -> {}
                DGOutcome.SUNK -> { phase = Phase.SINKING; sinkT = 0.0; SoundManager.tap(); Haptics.success() }
                DGOutcome.REST -> {
                    lastX = ball.x; lastY = ball.y
                    if (strokes >= budget) { fail(); return true }
                    phase = Phase.AIM
                }
                DGOutcome.OUT -> {
                    strokes++              // penalty, back to where it last rested
                    flash = 1.0
                    ball = DGBall(lastX, lastY)
                    SoundManager.error()
                    if (strokes >= budget) { fail(); return true }
                    phase = Phase.AIM
                }
            }
            Phase.SINKING -> {
                sinkT += DGPhysics.DT
                if (sinkT > 0.55) {
                    index++
                    if (index >= course.size) { phase = Phase.WON; return false }
                    phase = Phase.SLIDING; slide = 0.0
                }
            }
            Phase.SLIDING -> {
                slide = min(1.0, slide + DGPhysics.DT / 0.6)
                if (slide >= 1) { placeOnTee(); phase = Phase.AIM }
            }
            else -> {}
        }
        flash = max(0.0, flash - DGPhysics.DT * 3)
        return false
    }

    fun fail() {
        if (phase == Phase.DONE || phase == Phase.WON) return
        phase = Phase.DONE
        SoundManager.error()
        onFail()
    }
}

/**
 * How far the course is raised off the bottom edge, in widths: the sand below is room to pull the
 * slingshot back (a full pull is 0.34 widths), so a tall play area gets about half a width.
 */
private fun lift(w: Double, h: Double) = if (w <= 0) 0.0 else min(0.55, max(0.0, (h / w - 0.8) * 0.5))

@Composable
private fun SunsetPuttView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val golf = remember { Golf(level) }
    golf.onFail = onFail
    var area by remember { mutableStateOf(IntSize.Zero) }
    var ver by remember { mutableIntStateOf(0) }
    var demoFinger by remember { mutableStateOf<P?>(null) }      // px
    val tick by rememberFrameLoop()
    val handP = rememberHand()
    val u = LocalDensity.current.density.toDouble()
    val (sky, sand, ink) = palette(level)

    suspend fun runFrames(): Boolean {
        // A fixed-step 60 Hz loop: true once the level has ended.
        var last = nowSec(); var acc = 0.0
        val start = nowSec()
        while (true) {
            delay(16)
            val now = nowSec()
            acc += min(0.1, now - last); last = now
            while (acc >= DGPhysics.DT) {
                acc -= DGPhysics.DT
                if (golf.tick()) return true
            }
            ver++
            if (golf.phase == Phase.WON) {
                delay(400)
                golf.phase = Phase.DONE
                onWin()
                return true
            }
            if (golf.phase == Phase.DONE) return true
            golf.timeLeft = max(0.0, golf.timeLimit - (now - start))
            if (golf.timeLeft <= 0) { golf.fail(); return true }
        }
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (area.width == 0) delay(20)
            golf.course = listOf(DGGen.demoHole); golf.index = 0; golf.placeOnTee(); golf.phase = Phase.AIM
            val shot = withContext(Dispatchers.Default) { DGGen.verifiedDemoShot() }
            while (isActive) {
                golf.course = listOf(DGGen.demoHole); golf.index = 0; golf.strokes = 0
                golf.placeOnTee(); golf.phase = Phase.AIM; golf.aim = null
                demoFinger = null; ver++
                delay(600)
                // Drag back (a slingshot can start anywhere): from mid-screen, opposite the shot direction.
                val w = area.width.toDouble(); val h = area.height.toDouble()
                val lf = lift(w / u, h / u)
                val sx = (golf.ball.x + 0.3) * w; val sy = h - (golf.ball.y - 0.02 + lf) * w
                val pull = shot.second * w * 0.34
                val ex = sx - cos(shot.first) * pull; val ey = sy + sin(shot.first) * pull
                demoFinger = P(sx, sy)
                delay(250)
                for (k in 1..30) {
                    val t = k / 30.0
                    val e = 1 - (1 - t).pow(2)
                    demoFinger = P(sx + (ex - sx) * e, sy + (ey - sy) * e)
                    golf.aim = shot.first to shot.second * t
                    ver++
                    delay(20)
                }
                golf.aim = shot
                delay(300)
                golf.shoot()
                demoFinger = null
                for (f in 0 until 600) {
                    if (!isActive || golf.phase == Phase.WON || golf.phase == Phase.AIM) break
                    golf.tick(); ver++
                    delay(16)
                }
                delay(1400)
            }
        } else {
            val t0 = System.currentTimeMillis()
            val built = BoardCache.take(SunsetPuttGame.key(level)) { DGGen.course(DGGen.params(level), golf.holes) }
            BoardCache.holdBrainstorm(t0, 0.5)
            golf.course = built; golf.index = 0; golf.strokes = 0
            golf.placeOnTee(); golf.phase = Phase.AIM; golf.timeLeft = golf.timeLimit
            runFrames()
        }
    }

    Box(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp)
            .clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp)).background(sky)
            .onSizeChanged { area = it }
            .then(if (isDemo) Modifier else Modifier.touchDrag(
                onMove = { start, now ->
                    if (golf.phase != Phase.AIM || area.width <= 0) return@touchDrag
                    // Pull back: the shot flies opposite the drag (screen y is down, world y is up).
                    val dx = start.x - now.x; val dy = now.y - start.y
                    val power = min(1.0, sqrt(dx * dx + dy * dy) / (area.width * 0.34))
                    golf.aim = atan2(dy, dx) to power
                },
                onEnd = { _, _ -> golf.shoot() }))
    ) {
        Canvas(Modifier.fillMaxSize()) {
            tick; ver
            inPoints { w, h -> course(golf, w, h, sand, ink) }
            demoFinger?.let { f ->
                val s = size.width * 0.11
                hand(handP, f.x - s * 0.28, f.y - s * 0.08, s)
            }
        }
        ver
        // Plain values, not the mutable Golf: with strong skipping, Hud(golf) would never redraw.
        Hud(golf.strokes, golf.budget, golf.course.size, golf.index,
            if (golf.timeLimit > 0) golf.timeLeft / golf.timeLimit else 0.0, isDemo, ink)
    }
}

@Composable
private fun Hud(strokes: Int, budget: Int, holes: Int, index: Int, frac: Double, isDemo: Boolean, ink: Color) {
    Column(Modifier.fillMaxWidth().padding(top = if (isDemo) 4.dp else 10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (!isDemo) {
            TimeBar(frac, Modifier.fillMaxWidth().padding(horizontal = 40.dp).height(5.dp),
                fill = if (frac < 0.3) Color.Red else ink.op(0.7), track = ink.op(0.15))
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = if (isDemo) 12.dp else 20.dp), verticalAlignment = Alignment.Top) {
            Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("$strokes", style = ts(if (isDemo) 34.0 else 54.0, FontWeight.ExtraBold, ink), modifier = Modifier.alignByBaseline())
                Text("/$budget", style = ts(if (isDemo) 15.0 else 22.0, FontWeight.Bold, ink.op(0.6)), modifier = Modifier.alignByBaseline())
            }
            Spacer(Modifier.weight(1f))
            Row(Modifier.padding(top = if (isDemo) 10.dp else 16.dp), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                for (i in 0 until max(holes, 1)) {
                    Box(Modifier.size(if (isDemo) 8.dp else 10.dp).background(if (i < index) ink.op(0.8) else ink.op(0.18), CircleShape))
                }
            }
        }
    }
}

/** The course in points: the hole (or two while panning), the aim line, the ball, the out-of-bounds flash. */
private fun DrawScope.course(golf: Golf, w: Double, h: Double, sand: Color, ink: Color) {
    val course = golf.course
    if (course.isEmpty() || (golf.index >= course.size && golf.phase != Phase.WON)) return
    val lf = lift(w, h)
    fun sx(x: Double, shift: Double = 0.0) = (x + shift) * w
    fun sy(y: Double) = h - (y + lf) * w
    fun hole(hl: DGHole, shift: Double) {
        // The sand runs down past the bottom edge, however high the course is raised.
        val ground = Path()
        ground.m(sx(hl.xs[0], shift), h + 2)
        for (i in hl.xs.indices) ground.l(sx(hl.xs[i], shift), sy(hl.ys[i]))
        ground.l(sx(hl.xs[hl.xs.size - 1], shift), h + 2)
        ground.close()
        drawPath(ground, sand)
        // Flag: a thin pole from the cup floor and a small pennant.
        val cx = (hl.cupL + hl.cupR) / 2
        val bx = sx(cx, shift); val by = sy(hl.floorY)
        val ty = sy(hl.lipY + 0.12)
        line(bx, by, bx, ty, ink.op(0.85), max(1.5, w * 0.004), StrokeCap.Butt)
        drawPath(polyPath(bx, ty, bx + w * 0.05, ty + w * 0.017, bx, ty + w * 0.034), rgb(0.9, 0.28, 0.2))
    }
    // While sliding, the finished hole pans out left and the next one comes in from the right.
    if (golf.phase == Phase.SLIDING && golf.index > 0) {
        hole(course[golf.index - 1], -golf.slide)
        if (golf.index < course.size) hole(course[golf.index], 1 - golf.slide)
        return
    }
    val hi = min(golf.index, course.size - 1)
    hole(course[hi], 0.0)
    // Aim line: dotted, from the ball, length = power.
    val a = golf.aim
    if (golf.phase == Phase.AIM && a != null && a.second > 0.02) {
        val px = sx(golf.ball.x); val py = sy(golf.ball.y)
        val len = (0.06 + 0.2 * a.second) * w
        val p = Path().apply { m(px, py); l(px + cos(a.first) * len, py - sin(a.first) * len) }
        drawPath(p, Color.White.op(0.9), style = Stroke(max(2.0, w * 0.007).toFloat(), cap = StrokeCap.Round,
            pathEffect = PathEffect.dashPathEffect(floatArrayOf(0.1f, (w * 0.02).toFloat()), 0f)))
    }
    // Ball (off the top? a marker at the edge instead).
    if (golf.phase != Phase.WON) {
        val r = DGPhysics.R * w
        var bx = sx(golf.ball.x); var by = sy(golf.ball.y)
        if (golf.phase == Phase.SINKING) {
            val hl = course[hi]
            bx = sx((hl.cupL + hl.cupR) / 2); by = sy(hl.floorY + DGPhysics.R * (1 - min(1.0, golf.sinkT / 0.25)))
        }
        if (by < -r) drawPath(polyPath(bx, 4.0, bx - 6, 14.0, bx + 6, 14.0), Color.White)
        else circle(bx, by, r, Color.White)
    }
    if (golf.flash > 0) rect(0.0, 0.0, w, h, Color.White.op(golf.flash * 0.5))
}
