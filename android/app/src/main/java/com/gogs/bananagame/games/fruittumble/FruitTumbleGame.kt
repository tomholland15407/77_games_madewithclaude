package com.gogs.bananagame.games.fruittumble

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

/**
 * Brain — Fruit Tumble (iOS FruitMergeGame.swift, id "fruit-merge"): the Suika / watermelon game.
 * Drag to aim, let go to drop; touching twins merge up the chain. Make the goal fruit; fruit left
 * above the rim (or the clock) fails. Position-based circle physics; locks the feed while playing.
 */
object FruitTumbleGame {
    val definition = GameDefinition(
        id = "fruit-merge",
        title = "Fruit Tumble",
        genre = Genre.BRAIN,
        locksFeed = true,
        manual = GameManual(
            bullets = listOf(
                "Drag to aim, then let go to drop the fruit into the box.",
                "Two matching fruits that touch merge into the next fruit up the chain.",
                "Make the goal fruit shown at the top to win.",
                "If fruit stays piled above the rim, or time runs out, you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Kéo để nhắm, rồi thả tay để thả trái cây vào hộp.",
                "Hai trái giống nhau chạm vào nhau sẽ hợp thành trái lớn hơn trong chuỗi.",
                "Tạo ra trái mục tiêu hiện ở phía trên để thắng.",
                "Nếu trái cây chồng quá miệng hộp, hoặc hết giờ, bạn về lại cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> FruitTumbleView(level, onWin, onFail) }
    )
}

// Physics (iOS FMWorld): circles with area-weighted mass, Coulomb-style friction, 10 substeps per 1/60 s.

class FMFruit(val id: Int, val tier: Int, var x: Double, var y: Double, var r: Double, val targetR: Double) {
    var vx = 0.0; var vy = 0.0
    var angle = 0.0
    var age = 0.0
    var over = 0.0          // seconds spent above the rim
    var pop = 0.0           // merge bounce, 1 → 0
    fun copy() = FMFruit(id, tier, x, y, r, targetR).also { it.vx = vx; it.vy = vy; it.angle = angle; it.age = age; it.over = over; it.pop = pop }
}

class FMWorld {
    companion object {
        /** Radii as fractions of the box width, in Suika proportions. */
        val radii = doubleArrayOf(0.0375, 0.05, 0.0625, 0.0875, 0.1, 0.1125, 0.13125, 0.15, 0.2, 0.25, 0.3)
        const val BOX_H = 1.15
        const val GRAVITY = 4.0
        const val DROP_Y = -0.13
    }

    var fruits = mutableListOf<FMFruit>()
    var nextId = 0
    /** Merge events from the last step (new tier + position), for effects and win checks. */
    val merges = mutableListOf<Triple<Int, Double, Double>>()

    fun copy() = FMWorld().also { w -> w.fruits = fruits.map { it.copy() }.toMutableList(); w.nextId = nextId }

    fun add(tier: Int, x: Double, y: Double = DROP_Y) {
        val r = radii[tier]
        fruits.add(FMFruit(nextId++, tier, min(max(x, r), 1 - r), y, r, r))
    }

    /** Longest time any settled fruit has been sitting above the rim. */
    val maxOver get() = fruits.maxOfOrNull { it.over } ?: 0.0
    /** Is any fruit close to (or above) the rim? Drives the flashing danger line. */
    val nearRim get() = fruits.any { it.age > 0.8 && it.y - it.r < 0.08 }

    fun step(dt: Double) {
        merges.clear()
        val sub = 10; val h = dt / sub
        val muS = 0.55; val muK = 0.35
        repeat(sub) {
            val n = fruits.size
            val px = DoubleArray(n); val py = DoubleArray(n)
            for (i in 0 until n) {
                val f = fruits[i]
                if (f.r < f.targetR) f.r = min(f.targetR, f.r + 0.9 * h)     // grow into a merge
                px[i] = f.x; py[i] = f.y
                f.vy += GRAVITY * h
                f.x += f.vx * h; f.y += f.vy * h
            }
            // Fruit–fruit contacts: mass-weighted separation + friction on the relative slide.
            for (i in 0 until n - 1) for (j in i + 1 until n) {
                val a = fruits[i]; val b = fruits[j]
                val dx = b.x - a.x; val dy = b.y - a.y
                val minD = a.r + b.r
                val d2 = dx * dx + dy * dy
                if (d2 >= minD * minD || d2 <= 1e-14) continue
                val dist = sqrt(d2)
                val nx = dx / dist; val ny = dy / dist
                val pen = minD - dist
                val wi = 1 / (a.r * a.r); val wj = 1 / (b.r * b.r)
                val ki = wi / (wi + wj); val kj = wj / (wi + wj)
                a.x -= nx * pen * ki; a.y -= ny * pen * ki
                b.x += nx * pen * kj; b.y += ny * pen * kj
                val rx = (a.x - px[i]) - (b.x - px[j]); val ry = (a.y - py[i]) - (b.y - py[j])
                val dot = rx * nx + ry * ny
                val tx = rx - nx * dot; val ty = ry - ny * dot
                val tl = sqrt(tx * tx + ty * ty)
                if (tl > 1e-12) {
                    val k = if (tl < muS * pen) 1.0 else min(muK * pen / tl, 1.0)
                    a.x -= tx * k * ki; a.y -= ty * k * ki
                    b.x += tx * k * kj; b.y += ty * k * kj
                }
            }
            // Walls and floor (with friction along the surface).
            for (i in 0 until n) {
                val f = fruits[i]; val r = f.r
                if (f.x < r) {
                    val pen = r - f.x; f.x = r
                    val dy = f.y - py[i]; f.y -= if (abs(dy) < muS * pen) dy else dy * min(muK * pen / abs(dy), 1.0)
                }
                if (f.x > 1 - r) {
                    val pen = f.x - (1 - r); f.x = 1 - r
                    val dy = f.y - py[i]; f.y -= if (abs(dy) < muS * pen) dy else dy * min(muK * pen / abs(dy), 1.0)
                }
                if (f.y > BOX_H - r) {
                    val pen = f.y - (BOX_H - r); f.y = BOX_H - r
                    val dx = f.x - px[i]; f.x -= if (abs(dx) < muS * pen) dx else dx * min(muK * pen / abs(dx), 1.0)
                }
            }
            for (i in 0 until n) {
                val f = fruits[i]
                var vx = (f.x - px[i]) / h; var vy = (f.y - py[i]) / h
                val sp = sqrt(vx * vx + vy * vy)
                if (sp > 6) { vx *= 6 / sp; vy *= 6 / sp }
                f.vx = vx; f.vy = vy
            }
        }
        // Light air damping, rolling spin, ageing and the over-the-rim timer.
        val damp = 1 - 0.25 * dt
        for (f in fruits) {
            f.vx *= damp; f.vy *= damp
            f.angle += f.vx / f.r * dt
            f.age += dt
            f.pop = max(0.0, f.pop - dt / 0.28)
            if (f.age > 1.0 && f.y - f.r < 0 && abs(f.vy) < 0.6) f.over += dt else f.over = 0.0
        }
        // Merges: touching twins become the next fruit at their mass-weighted midpoint.
        val used = HashSet<Int>(); val born = ArrayList<FMFruit>()
        val n = fruits.size
        for (i in 0 until n - 1) {
            if (i in used) continue
            for (j in i + 1 until n) {
                if (j in used || fruits[j].tier != fruits[i].tier) continue
                val a = fruits[i]; val b = fruits[j]
                val dx = b.x - a.x; val dy = b.y - a.y
                val reach = a.r + b.r + 0.004
                if (dx * dx + dy * dy >= reach * reach) continue
                used.add(i); used.add(j)
                if (a.tier + 1 < radii.size) {
                    val ma = a.r * a.r; val mb = b.r * b.r
                    val x = (a.x * ma + b.x * mb) / (ma + mb); val y = (a.y * ma + b.y * mb) / (ma + mb)
                    val f = FMFruit(nextId++, a.tier + 1, x, y, max(a.r, b.r), radii[a.tier + 1])
                    f.vx = (a.vx + b.vx) * 0.25; f.vy = (a.vy + b.vy) * 0.25
                    f.age = max(a.age, b.age); f.pop = 1.0; f.angle = (a.angle + b.angle) / 2
                    born.add(f)
                    merges.add(Triple(a.tier + 1, x, y))
                } else merges.add(Triple(a.tier, (a.x + b.x) / 2, (a.y + b.y) / 2))   // two watermelons: both vanish
                break
            }
        }
        if (used.isNotEmpty()) fruits = (fruits.indices.filter { it !in used }.map { fruits[it] } + born).toMutableList()
    }
}

/** Each fruit kind rendered once (with its face) so the per-frame Canvas just stamps rotated images. */
private object FMArt {
    const val SPAN_K = 1.45            // image half-size in body radii (stems/crowns poke up)
    private val cache = HashMap<Int, ImageBitmap>()

    @Synchronized fun image(tier: Int): ImageBitmap = cache.getOrPut(tier) {
        val r = max(18.0, FMWorld.radii[tier] * 380) * 2
        val side = (r * SPAN_K * 2).toInt()
        val bmp = ImageBitmap(side, side)
        CanvasDrawScope().draw(Density(1f), LayoutDirection.Ltr, androidx.compose.ui.graphics.Canvas(bmp), Size(side.toFloat(), side.toFloat())) {
            FruitArt.draw(this, FruitKind.entries[tier], side / 2.0, side / 2.0, r, face = true)
        }
        bmp
    }
}

private fun DrawScope.stamp(tier: Int, cx: Double, cy: Double, r: Double, angle: Double, pop: Double, alpha: Double = 1.0) {
    val s = r * (1 + 0.16 * sin(pop * PI)) * FMArt.SPAN_K
    translate(cx.f, cy.f) { rotateRad(angle.f, Offset.Zero) {
        drawImage(FMArt.image(tier), dstOffset = IntOffset((-s).toInt(), (-s).toInt()), dstSize = IntSize((2 * s).toInt(), (2 * s).toInt()), alpha = alpha.f)
    } }
}

private enum class FPhase { LOADING, PLAY, WON, DONE }
private class Splash(val x: Double, val y: Double, val tier: Int, val t0: Double)

private class Lay(w: Double, h: Double, demo: Boolean, u: Double) {
    val pad = (if (demo) 8 else 18) * u
    // The squat demo card puts GOAL/NEXT beside the box and skips the strip, so the box is bigger.
    val hudH = (if (demo) 0 else 64) * u
    val stripH = (if (demo) 0 else 38) * u
    private val dropSpace = if (demo) 0.26 else 0.3     // box units above the rim for the hovering fruit
    private val wall = 0.03
    private val availH = h - hudH - stripH - pad * 1.5
    val unit = min((w - pad * 2) / (1 + wall * 2), availH / (FMWorld.BOX_H + dropSpace + wall))
    val bw = unit
    val bh = unit * FMWorld.BOX_H
    val by = hudH + (availH - bh - dropSpace * unit - wall * unit) / 2 + dropSpace * unit
    val bx = (w - bw) / 2
    val hudY = hudH / 2 + (if (demo) 2 else 4) * u
    val stripY = by + bh + wall * unit + stripH / 2 + pad * 0.4
    fun pt(x: Double, y: Double) = P(bx + x * unit, by + y * unit)
}

private class TumbleWorld(val level: Int) {
    private val li = min(level, 7) - 1
    val goal = listOf(5, 6, 7, 7, 8, 8, 9)[li]
    /** Fruit already in the box when the level starts (settled before play). */
    val seeds = listOf(listOf(), listOf(), listOf(6, 2, 1), listOf(5, 4, 2, 1, 0, 3, 2), listOf(7, 5, 3, 2, 1, 0, 4, 1),
        listOf(7, 4, 3, 2, 1, 0, 2, 1, 3, 0, 4, 2, 1, 0), listOf(8, 7, 5, 4, 3, 2, 1, 0, 2, 1, 3, 0))[li]
    // Tuned on iOS with a headless bot (1.4 s per drop, ±0.04 aim): ~100/100/97/85/45/18/13% wins.
    val timeLimit = listOf(60.0, 60.0, 70.0, 55.0, 60.0, 38.0, 45.0)[li]
    val overLimit = 1.6

    var phase = FPhase.LOADING
    var world = FMWorld()
    var current = 0
    var upcoming = 0
    var aimX = 0.5
    var lastDrop = -10.0
    var timeLeft = timeLimit
    var clock = 0.0
    val splashes = mutableListOf<Splash>()

    fun drop(isDemo: Boolean) {
        if (phase != FPhase.PLAY || (nowSec() - lastDrop <= 0.45 && !isDemo)) return
        lastDrop = nowSec()
        world.add(current, aimX)
        current = upcoming
        upcoming = Random.nextInt(5)
        SoundManager.tap(); Haptics.tap()
    }

    fun handleMerges(isDemo: Boolean) {
        for ((tier, x, y) in world.merges) {
            splashes.add(Splash(x, y, tier, clock))
            if (!isDemo) {
                SoundManager.tap(); Haptics.tap()
                if (tier >= goal && phase == FPhase.PLAY) phase = FPhase.WON
            }
        }
        splashes.removeAll { clock - it.t0 > 0.5 }
    }

    companion object {
        /** Drops the level's seed fruit in one by one and lets them settle. */
        fun seededWorld(seeds: List<Int>, goal: Int): FMWorld {
            repeat(20) {
                val w = FMWorld()
                var reached = false
                for (tier in seeds) {
                    w.add(tier, rnd(0.1, 0.9), 0.1)
                    repeat(24) { w.step(1.0 / 60); if (w.merges.any { it.first >= goal }) reached = true }
                }
                repeat(90) { w.step(1.0 / 60); if (w.merges.any { it.first >= goal }) reached = true }
                if (!reached && w.fruits.all { it.y - it.r > 0.05 }) { for (f in w.fruits) f.age = 2.0; return w }
            }
            return FMWorld()
        }

        /** Level 1 from a fixed, pre-settled box for the manual clip. */
        fun demoWorld(): FMWorld {
            val w = FMWorld()
            for ((tier, x) in listOf(5 to 0.14, 4 to 0.36, 1 to 0.62, 0 to 0.84, 2 to 0.9, 3 to 0.6)) {
                w.add(tier, x, 0.1); repeat(30) { w.step(1.0 / 60) }
            }
            repeat(120) { w.step(1.0 / 60) }
            for (f in w.fruits) f.age = 2.0
            return w
        }
    }
}

private val demoDrops = listOf(0 to 0.84, 4 to 0.36)

@Composable
private fun FruitTumbleView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val g = remember { TumbleWorld(level) }
    val tm = rememberTextMeasurer()
    val handP = rememberHand()
    val dens = LocalDensity.current.density.toDouble()
    val area = remember { doubleArrayOf(0.0, 0.0) }
    val demo = remember { object { var finger: P? = null; var pressed = false } }
    val tick by rememberFrameLoop()

    fun fail() { if (g.phase != FPhase.PLAY) return; g.phase = FPhase.DONE; SoundManager.error(); onFail() }

    LaunchedEffect(Unit) {
        if (isDemo) {
            val base = withContext(Dispatchers.Default) { TumbleWorld.demoWorld() }
            suspend fun frames(n: Int) = repeat(n) { g.world.step(1.0 / 60); g.clock += 1.0 / 60; g.handleMerges(true); delay(16) }
            while (isActive) {
                g.world = base.copy(); g.clock = 0.0; g.splashes.clear(); g.phase = FPhase.PLAY
                g.current = demoDrops[0].first; g.upcoming = demoDrops[1].first; g.aimX = 0.5; demo.finger = null
                delay(500)
                for ((k, d) in demoDrops.withIndex()) {
                    g.current = d.first
                    g.upcoming = if (k + 1 < demoDrops.size) demoDrops[k + 1].first else 2
                    // Finger slides over the target column, then lets go.
                    val fromX = g.aimX
                    demo.pressed = true
                    for (s in 1..24) {
                        val t = s / 24.0
                        g.aimX = fromX + (d.second - fromX) * (if (t < 0.5) 2 * t * t else 1 - (-2 * t + 2).pow(2) / 2)
                        demo.finger = P(g.aimX, FMWorld.DROP_Y + 0.12)
                        frames(1)
                    }
                    frames(8)
                    g.world.add(g.current, g.aimX)
                    g.current = g.upcoming
                    demo.pressed = false
                    frames(if (k == 0) 70 else 110)
                }
                demo.finger = null
                frames(60)
            }
        } else {
            g.world = withContext(Dispatchers.Default) { for (t in 0 until FMWorld.radii.size) FMArt.image(t); TumbleWorld.seededWorld(g.seeds, g.goal) }
            g.current = Random.nextInt(5); g.upcoming = Random.nextInt(5); g.aimX = 0.5
            g.phase = FPhase.PLAY; g.timeLeft = g.timeLimit
            val start = nowSec(); var last = nowSec(); var acc = 0.0
            while (isActive) {
                delay(16)
                val now = nowSec()
                acc += min(0.1, now - last); last = now
                // Fixed 1/60 s physics steps regardless of frame timing.
                while (acc >= 1.0 / 60) { acc -= 1.0 / 60; g.world.step(1.0 / 60); g.clock += 1.0 / 60; g.handleMerges(false) }
                when (g.phase) {
                    FPhase.PLAY -> {
                        g.timeLeft = max(0.0, g.timeLimit - (now - start))
                        if (g.world.maxOver > g.overLimit || g.timeLeft <= 0) { fail(); return@LaunchedEffect }
                    }
                    FPhase.WON -> { delay(700); g.phase = FPhase.DONE; onWin(); return@LaunchedEffect }
                    else -> {}
                }
            }
        }
    }

    Canvas(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .onSizeChanged { area[0] = it.width.toDouble(); area[1] = it.height.toDouble() }
            .then(if (isDemo) Modifier else Modifier.touchDrag(
                onStart = { p -> if (g.phase == FPhase.PLAY) { val l = Lay(area[0], area[1], false, dens); g.aimX = (p.x - l.bx) / l.unit } },
                onMove = { _, p -> if (g.phase == FPhase.PLAY) { val l = Lay(area[0], area[1], false, dens); g.aimX = (p.x - l.bx) / l.unit } },
                onEnd = { _, p -> if (g.phase == FPhase.PLAY) { val l = Lay(area[0], area[1], false, dens); g.aimX = (p.x - l.bx) / l.unit; g.drop(false) } },
            ))
    ) {
        tick
        val u = density.toDouble(); val w = size.width.toDouble(); val h = size.height.toDouble()
        val l = Lay(w, h, isDemo, u)
        rect(0.0, 0.0, w, h, vgrad(listOf(rgb(1.0, 0.87, 0.56), rgb(0.99, 0.70, 0.36)), 0.0, h))
        scene(g, l, isDemo)
        if (isDemo) demoHud(g, l, tm) else hud(g, l, tm)
        demo.finger?.let { f ->
            val s = l.unit * (if (demo.pressed) 0.13 else 0.145)
            val p = l.pt(f.x, f.y)
            hand(handP, p.x - s * 0.28, p.y - s * 0.1, s)
        }
    }
}

private val WOOD = rgb(0.76, 0.48, 0.24)
private val INK = rgb(0.45, 0.22, 0.06)

private fun DrawScope.scene(g: TumbleWorld, l: Lay, isDemo: Boolean) {
    val u = density.toDouble(); val uu = l.unit
    val wall = 0.03 * uu
    // The box: a cream tub with a chunky wooden rim, open at the top.
    val ox = l.bx - wall; val oy = l.by - wall * 0.5; val ow = l.bw + wall * 2; val oh = l.bh + wall * 1.5
    val tub = Path(); tub.m(ox, oy); tub.l(ox, oy + oh - wall * 2); tub.q(ox, oy + oh, ox + wall * 2, oy + oh)
    tub.l(ox + ow - wall * 2, oy + oh); tub.q(ox + ow, oy + oh, ox + ow, oy + oh - wall * 2); tub.l(ox + ow, oy)
    blurRRect(l.bx, l.by + 5 * u, l.bw, l.bh, wall, Color.Black.op(0.18), 8 * u)
    rrect(l.bx, l.by, l.bw, l.bh, wall, vgrad(listOf(rgb(1.0, 0.97, 0.86, 0.9), rgb(1.0, 0.92, 0.74, 0.95)), l.by, l.by + l.bh))
    strokePath(tub, WOOD.shade(0.25), wall * 1.35)
    strokePath(tub, WOOD, wall * 0.85)
    // Danger line at the rim, flashing when the pile gets close.
    val world = g.world
    if (world.nearRim || world.maxOver > 0) {
        val on = (g.clock * 6).toInt() % 2 == 0 || world.maxOver > 0
        drawLine(rgb(0.9, 0.15, 0.1, if (on) 0.9 else 0.35), off(l.bx, l.by), off(l.bx + l.bw, l.by), (3 * u).f,
            pathEffect = PathEffect.dashPathEffect(floatArrayOf((10 * u).f, (7 * u).f)))
    }
    // Aim guide + the hovering fruit.
    if (g.phase == FPhase.PLAY) {
        val r = FMWorld.radii[g.current]
        val x = min(max(g.aimX, r), 1 - r)
        var hitY = FMWorld.BOX_H
        for (f in world.fruits) if (abs(f.x - x) < f.r) { val dx = f.x - x; hitY = min(hitY, f.y - sqrt(f.r * f.r - dx * dx)) }
        val a = l.pt(x, FMWorld.DROP_Y + r); val b = l.pt(x, hitY)
        line(a.x, a.y, b.x, b.y, Color.White.op(0.85), 2 * u, StrokeCap.Butt)
        val canDrop = nowSec() - g.lastDrop > 0.45 || isDemo
        val c = l.pt(x, FMWorld.DROP_Y)
        stamp(g.current, c.x, c.y, r * uu, 0.0, 0.0, if (canDrop) 1.0 else 0.55)
    }
    for (f in world.fruits) { val c = l.pt(f.x, f.y); stamp(f.tier, c.x, c.y, f.r * uu, f.angle, f.pop) }
    // Juice splashes on merges.
    for (s in g.splashes) {
        val t = g.clock - s.t0
        if (t < 0 || t >= 0.45) continue
        val c = l.pt(s.x, s.y)
        val color = FruitArt.color(FruitKind.entries[s.tier])
        val base = FMWorld.radii[s.tier] * uu
        for (k in 0 until 10) {
            val a = k / 10.0 * 2 * PI + s.tier
            val d = base * (0.9 + t * 3.2)
            val sz = base * 0.22 * (1 - t / 0.45)
            circle(c.x + cos(a) * d, c.y + sin(a) * d + t * t * uu * 1.5, sz, color)
        }
        circleStroke(c.x, c.y, base * (1 + t * 2.5), Color.White.op(0.7 * (1 - t / 0.45)), 3 * u)
    }
    // Evolution strip: the whole chain, goal ringed, fruit past the goal dimmed.
    if (!isDemo) {
        val n = FMWorld.radii.size
        val cw = min(l.bw * 1.1 / n, 40 * u)
        val x0 = l.bx + l.bw / 2 - cw * n / 2
        for (t in 0 until n) {
            val cx = x0 + (t + 0.5) * cw
            if (t == g.goal) {
                circle(cx, l.stripY, cw * 0.52, Color.White.op(0.7))
                circleStroke(cx, l.stripY, cw * 0.52, rgb(0.62, 0.34, 0.1), 2 * u)
            }
            stamp(t, cx, l.stripY, cw * 0.34, 0.0, 0.0, if (t > g.goal) 0.3 else 1.0)
        }
    }
}

/** GOAL and NEXT bubbles (and the time bar) above the box. */
private fun DrawScope.hud(g: TumbleWorld, l: Lay, tm: TextMeasurer) {
    val u = density.toDouble(); val w = size.width.toDouble()
    val f = if (g.timeLimit > 0) g.timeLeft / g.timeLimit else 0.0
    rrect(40 * u, 10 * u, w - 80 * u, 6 * u, 3 * u, Color.Black.op(0.14))
    rrect(40 * u, 10 * u, (w - 80 * u) * clamp(f, 0.0, 1.0), 6 * u, 3 * u, if (f < 0.3) Color.Red else rgb(0.55, 0.3, 0.1))
    val y = 10 * u + 6 * u + 8 * u + 22 * u
    bubble(tm, L("GOAL", "MỤC TIÊU"), g.goal, 20 * u, y, true)
    bubble(tm, L("NEXT", "TIẾP"), g.upcoming, w - 20 * u, y, false)
}

private fun DrawScope.bubble(tm: TextMeasurer, title: String, tier: Int, edgeX: Double, cy: Double, leftAligned: Boolean) {
    val u = density.toDouble()
    val fs = 14 * u; val img = 38 * u
    val tw = textWidth(tm, title, fs, FontWeight.Black)
    val bw = 10 * u + tw + 6 * u + img + 10 * u; val bh = img + 6 * u
    val x = if (leftAligned) edgeX else edgeX - bw
    rrect(x, cy - bh / 2, bw, bh, bh / 2, Color.White.op(0.55))
    rrectStroke(x, cy - bh / 2, bw, bh, bh / 2, rgb(0.62, 0.36, 0.14, 0.5), 2 * u)
    text(tm, title, x + 10 * u, cy, fs, INK, FontWeight.Black, anchorX = 0.0)
    stamp(tier, x + 10 * u + tw + 6 * u + img / 2, cy, img / 2 / FMArt.SPAN_K, 0.0, 0.0)
}

/** The demo card's GOAL / NEXT tags beside the box. */
private fun DrawScope.demoHud(g: TumbleWorld, l: Lay, tm: TextMeasurer) {
    val u = density.toDouble(); val w = size.width.toDouble()
    for ((cx, pair) in listOf(l.bx / 2 to (L("GOAL", "MỤC TIÊU") to g.goal), (l.bx + l.bw + (w - l.bx - l.bw) / 2) to (L("NEXT", "TIẾP") to g.upcoming))) {
        val (title, tier) = pair
        val fs = 11 * u; val img = 34 * u
        val tw = max(textWidth(tm, title, fs, FontWeight.Black), img)
        val bw = tw + 16 * u; val bh = fs * 1.3 + 2 * u + img + 12 * u
        val cy = l.by + 30 * u
        rrect(cx - bw / 2, cy - bh / 2, bw, bh, 14 * u, Color.White.op(0.55))
        rrectStroke(cx - bw / 2, cy - bh / 2, bw, bh, 14 * u, rgb(0.62, 0.36, 0.14, 0.5), 2 * u)
        text(tm, title, cx, cy - bh / 2 + 6 * u + fs * 0.65, fs, INK, FontWeight.Black)
        stamp(tier, cx, cy + bh / 2 - 6 * u - img / 2, img / 2 / FMArt.SPAN_K, 0.0, 0.0)
    }
}
