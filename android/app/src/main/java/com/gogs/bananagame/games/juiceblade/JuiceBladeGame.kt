package com.gogs.bananagame.games.juiceblade

import androidx.compose.foundation.Canvas
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.IntSize
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
import kotlin.math.pow
import kotlin.math.sin

/**
 * Reflex — Juice Blade (iOS FruitNinjaGame.swift, id "fruit-ninja"): swipe across tossed fruit to
 * slice it, never a bomb. Slice the quota; a bomb or three dropped fruit → level 1.
 */
object JuiceBladeGame {
    val definition = GameDefinition(
        id = "fruit-ninja",
        title = "Juice Blade",
        genre = Genre.REFLEX,
        locksFeed = true,
        manual = GameManual(
            bullets = listOf(
                "Fruit is tossed up in arcs — swipe across it to slice.",
                "Never slice a bomb.",
                "Slice the level's quota of fruit to win.",
                "Slice a bomb, or let three fruit fall past unsliced, and you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Trái cây được tung lên theo vòng cung — vuốt ngang qua để chém.",
                "Đừng bao giờ chém trúng bom.",
                "Chém đủ số trái cây của cấp để thắng.",
                "Chém trúng bom, hoặc để ba quả rơi qua chưa chém, sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> JuiceBladeView(level, onWin, onFail) }
    )
}

/** Fruit kinds (iOS fruitColors order): watermelon, orange, apple, lemon, strawberry, pineapple. */
private val kinds = listOf(FruitKind.WATERMELON, FruitKind.DEKOPON, FruitKind.APPLE, FruitKind.LEMON, FruitKind.STRAWBERRY, FruitKind.PINEAPPLE)
private const val BOMB_R = 0.066
private fun radiusOf(k: Int) = listOf(0.085, 0.07, 0.07, 0.066, 0.062, 0.066)[k % 6]
private fun juice(k: Int) = listOf(rgb(0.9, 0.1, 0.16), rgb(1.0, 0.55, 0.08), rgb(0.98, 0.9, 0.62), rgb(1.0, 0.88, 0.24), rgb(0.94, 0.12, 0.24), rgb(1.0, 0.8, 0.2))[k % 6]

private const val GRAVITY = 1.5
private const val SLICE_R = 0.09
private const val MAX_MISSES = 3

private val demoTosses = listOf(
    listOf(Triple(0.38, 0.10, 1.35)),
    listOf(Triple(0.28, 0.12, 1.30), Triple(0.70, -0.10, 1.40)),
    listOf(Triple(0.62, -0.08, 1.33), Triple(0.34, 0.14, 1.38)),
)

private class Fruit(var x: Double, var y: Double, val vx: Double, var vy: Double, val isBomb: Boolean, val kind: Int, var rot: Double, val spin: Double)
private class Half(val kind: Int, val x0: Double, val y0: Double, val vx: Double, val vy: Double, val cut: Double, val side: Double, val spin: Double, val born: Double)
private class Splat(val kind: Int, val x: Double, val y: Double, val seed: Double, val born: Double)
private class Boom(val x: Double, val y: Double, val born: Double)

private class BladeWorld(level: Int, val isDemo: Boolean) {
    private val li = min(level, 7) - 1
    val target = listOf(5, 7, 9, 11, 13, 16, 20)[li]
    val spawnInterval = listOf(1.5, 1.35, 1.2, 1.05, 0.9, 0.78, 0.68)[li]
    val groupLo = listOf(1, 1, 1, 2, 2, 2, 3)[li]
    val groupHi = listOf(2, 2, 3, 3, 4, 4, 5)[li]
    val bombChance = listOf(0.0, 0.14, 0.22, 0.30, 0.38, 0.47, 0.56)[li]
    val launchSpeed = listOf(1.35, 1.42, 1.5, 1.58, 1.66, 1.74, 1.82)[li]

    val fruits = mutableListOf<Fruit>()
    val halves = mutableListOf<Half>()
    val splats = mutableListOf<Splat>()
    var boom: Boom? = null
    /** Blade trail in field fractions. */
    val trail = mutableListOf<P>()
    var sliced = 0; var misses = 0; var spawnAcc = 0.0
    var done = false
    var demoToss = 0
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    fun setup() { fruits.clear(); trail.clear(); sliced = 0; misses = 0; spawnAcc = 0.0; done = false; boom = null }

    fun step(dt: Double) {
        if (done) return
        for (f in fruits) { f.vy += GRAVITY * dt; f.x += f.vx * dt; f.y += f.vy * dt; f.rot += f.spin * dt }
        misses += fruits.count { it.y > 1.12 && !it.isBomb }
        fruits.removeAll { it.y > 1.12 }
        if (misses >= MAX_MISSES) { fail(); return }
        spawnAcc += dt
        if (spawnAcc >= spawnInterval) { spawnAcc -= spawnInterval; toss() }
    }

    private fun toss() {
        if (isDemo) {
            val group = demoTosses[demoToss % demoTosses.size]
            demoToss++
            group.forEachIndexed { i, (x, dx, up) -> fruits.add(Fruit(x, 1.1, dx, -up, false, (demoToss * 2 + i) % 6, 0.0, if (i == 0) 2.2 else -1.8)) }
            return
        }
        repeat(rndInt(groupLo..groupHi)) { k ->
            val bomb = k != 0 && Math.random() < bombChance
            fruits.add(Fruit(rnd(0.2, 0.8), 1.1, rnd(-0.22, 0.22), -launchSpeed * rnd(0.9, 1.05), bomb, rndInt(0..5), 0.0, rnd(-3.0, 3.0)))
        }
    }

    /** One blade point (field fractions); `aspect` = w/h to orient the halves like on screen. */
    fun sliceAt(fx: Double, fy: Double, aspect: Double) {
        val f = fruits.firstOrNull { !it.isBomb && hypot(fx - it.x, fy - it.y) < SLICE_R }
            ?: fruits.firstOrNull { it.isBomb && hypot(fx - it.x, fy - it.y) < SLICE_R } ?: return
        if (f.isBomb) {
            boom = Boom(f.x, f.y, nowSec())
            fail(); return
        }
        fruits.remove(f)
        sliced++
        Haptics.tap(); SoundManager.tap()
        spawnSlice(f, aspect)
        if (sliced >= target) win()
    }

    /** Two halves flying apart across the blade's line, a juice stain and a spray of drops. */
    private fun spawnSlice(f: Fruit, aspect: Double) {
        var ang = 0.3
        if (trail.size >= 2) {
            val a = trail[trail.size - 2]; val c = trail.last()
            val dx = (c.x - a.x) * aspect; val dy = c.y - a.y
            if (hypot(dx, dy) > 0.001) ang = atan2(dy, dx)
        }
        val now = nowSec()
        for (side in listOf(-1.0, 1.0)) {
            val nx = -sin(ang) * side; val ny = cos(ang) * side
            halves.add(Half(f.kind, f.x, f.y, nx * 0.22, ny * 0.22 - 0.12, ang, side, side * 2.4, now))
        }
        splats.add(Splat(f.kind, f.x, f.y, (splats.size % 97) + now % 13, now))
        halves.removeAll { now - it.born > 2.5 }; splats.removeAll { now - it.born > 2.5 }
    }

    fun win() { if (done) return; done = true; onWin() }
    fun fail() { if (done) return; done = true; SoundManager.error(); onFail() }
}

@Composable
private fun JuiceBladeView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { BladeWorld(level, isDemo).also { it.setup() } }
    world.onWin = onWin; world.onFail = onFail
    var demoTick by remember { mutableIntStateOf(0) }
    var field by remember { androidx.compose.runtime.mutableStateOf(IntSize.Zero) }
    val tm = rememberTextMeasurer()
    val handP = rememberHand()
    val tick by rememberFrameLoop { dt -> if (!isDemo) world.step(dt) }

    LaunchedEffect(Unit) {
        if (!isDemo) return@LaunchedEffect
        val dt = 1.0 / 60.0
        while (isActive) {
            world.setup(); world.demoToss = 0
            world.spawnAcc = world.spawnInterval - 0.4
            delay(300)
            var swipe: Triple<P, P, Int>? = null
            var linger = 0
            while (isActive && !world.done) {
                world.step(dt)
                val sw = swipe
                val aspect = if (field.height > 0) field.width.toDouble() / field.height else 0.5
                if (sw != null) {
                    val f = sw.third / 7.0
                    val p = P(sw.first.x + (sw.second.x - sw.first.x) * f, sw.first.y + (sw.second.y - sw.first.y) * f)
                    world.trail.add(p)
                    world.sliceAt(p.x, p.y, aspect)
                    swipe = if (sw.third >= 7) null else Triple(sw.first, sw.second, sw.third + 1)
                    if (swipe == null) linger = 8
                } else if (linger > 0) {
                    linger--
                    if (linger == 0) world.trail.clear()
                } else {
                    world.fruits.filter { !it.isBomb && it.vy > -0.35 && it.y < 0.85 }.minByOrNull { it.vy }?.let { f ->
                        val cx = f.x + f.vx * 0.06; val cy = f.y + f.vy * 0.06
                        swipe = Triple(P(cx - 0.14, cy + 0.07), P(cx + 0.14, cy - 0.07), 0)
                        world.trail.clear()
                    }
                }
                demoTick++
                delay(16)
            }
            delay(250)
            world.trail.clear()
            delay(1100)
        }
    }

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .drawBehind { dojo(level); vignette(0.35) },
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        tick; demoTick
        if (!isDemo) Hud(tm, world.sliced, world.target, world.misses, 1.0, Modifier.fillMaxWidth().height(51.dp))
        Box(Modifier.fillMaxWidth().weight(1f)) {
            Canvas(
                Modifier.fillMaxSize().onSizeChanged { field = it }
                    .then(if (isDemo) Modifier else Modifier.touchDrag(
                        onStart = { p -> blade(world, p, field) },
                        onMove = { _, p -> blade(world, p, field) },
                        onEnd = { _, _ -> world.trail.clear() }))
            ) {
                tick; demoTick
                scene(world, nowSec())
                if (isDemo && world.trail.size > 1) {
                    val tip = world.trail.last(); val s = 26.0 * density
                    hand(handP, tip.x * size.width + 10 * density - s / 2, tip.y * size.height + 14 * density - s / 2, s)
                }
            }
            if (isDemo) Hud(tm, world.sliced, world.target, world.misses, 0.62, Modifier.fillMaxWidth().height(34.dp).padding(horizontal = 6.dp).align(Alignment.TopCenter))
        }
    }
}

private fun blade(world: BladeWorld, p: P, field: IntSize) {
    if (world.done || field.width <= 0) return
    val fx = p.x / field.width; val fy = p.y / field.height
    world.trail.add(P(fx, fy))
    if (world.trail.size > 14) world.trail.removeAt(0)
    world.sliceAt(fx, fy, field.width.toDouble() / field.height)
}

/** A sliced watermelon with the count in gold, and three ✕ that turn red as fruit falls. */
@Composable
private fun Hud(tm: TextMeasurer, sliced: Int, target: Int, misses: Int, scale: Double, modifier: Modifier) {
    Row(modifier.padding(horizontal = (14 * scale).dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy((8 * scale).dp)) {
        Canvas(Modifier.size((40 * scale).dp)) {
            translate(size.width / 2, size.height * 0.56f) { rotate(-24f, Offset.Zero) { drawHalf(0, size.width * 0.42, 1.0) } }
        }
        Canvas(Modifier.size((110 * scale).dp, (40 * scale).dp)) { scoreText(tm, "$sliced/$target", 30 * scale * density) }
        Spacer(Modifier.weight(1f))
        Canvas(Modifier.size((88 * scale).dp, (30 * scale).dp)) {
            var x = size.width.toDouble()
            for (i in (MAX_MISSES - 1) downTo 0) {
                val s = size.height * listOf(0.58, 0.78, 1.0)[min(2, i)]
                x -= s * 0.5
                cross(x, size.height / 2.0, s, i < misses)
                x -= s * 0.5 + 3 * density
            }
        }
    }
}

private fun DrawScope.cross(cx: Double, cy: Double, s: Double, used: Boolean) {
    val x = Path(); x.m(cx - s * 0.34, cy - s * 0.34); x.l(cx + s * 0.34, cy + s * 0.34); x.m(cx + s * 0.34, cy - s * 0.34); x.l(cx - s * 0.34, cy + s * 0.34)
    strokePath(x, rgb(0.08, 0.06, 0.14), s * 0.36)
    strokePath(x, if (used) rgb(0.95, 0.18, 0.12) else rgb(0.2, 0.4, 0.95), s * 0.22)
    strokePath(x, Color.White.op(0.35), s * 0.06)
}

/** Fruit Ninja's chunky gold numbers with a dark outline (left-aligned, vertically centred). */
private fun DrawScope.scoreText(tm: TextMeasurer, s: String, size: Double) {
    val y = this.size.height / 2.0
    for (i in 0 until 8) {
        val a = i * PI / 4
        text(tm, s, cos(a) * size * 0.07, y + sin(a) * size * 0.07, size, rgb(0.3, 0.13, 0.04), FontWeight.Black, anchorX = 0.0)
    }
    text(tm, s, 0.0, y, size, rgb(1.0, 0.8, 0.28), FontWeight.Black, anchorX = 0.0)
}

private fun hash(n: Double): Double { val v = sin(n * 12.9898) * 43758.5453; return v - floor(v) }

private fun DrawScope.scene(world: BladeWorld, now: Double) {
    val w = size.width.toDouble(); val h = size.height.toDouble()
    for (s in world.splats) stain(s, w, h, now)
    for (f in world.fruits) {
        val cx = f.x * w; val cy = f.y * h
        if (f.isBomb) {
            bombHalo(cx, cy, BOMB_R * w, now)
            translate(cx.f, cy.f) { rotateRad((f.rot * 0.4).f, Offset.Zero) { bomb(BOMB_R * w); fuseSpark(BOMB_R * w, now) } }
        } else translate(cx.f, cy.f) { rotateRad(f.rot.f, Offset.Zero) { FruitArt.draw(this, kinds[f.kind], 0.0, 0.0, radiusOf(f.kind) * w) } }
    }
    for (hf in world.halves) {
        val age = now - hf.born
        if (age < 0 || age >= 2.5) continue
        val px = (hf.x0 + hf.vx * age) * w; val py = (hf.y0 + hf.vy * age + 0.5 * GRAVITY * age * age) * h
        if (py >= h + 80 * density) continue
        translate(px.f, py.f) {
            rotateRad((hf.cut + hf.spin * age).f, Offset.Zero) {
                withAlpha(if (age > 1.8) clamp((2.5 - age) / 0.7, 0.0, 1.0) else 1.0) { drawHalf(hf.kind, radiusOf(hf.kind) * w, hf.side) }
            }
        }
    }
    for (s in world.splats) spray(s, w, h, now)
    bladeArt(world.trail.map { P(it.x * w, it.y * h) }, max(9.0 * density, w * 0.028))
    world.boom?.let { boomArt(it, w, h, now) }
}

private fun DrawScope.stain(s: Splat, w: Double, h: Double, now: Double) {
    val age = now - s.born
    if (age < 0 || age >= 2.5) return
    val a = if (age < 0.08) age / 0.08 else clamp(1 - (age - 0.7) / 1.8, 0.0, 1.0)
    val cx = s.x * w; val cy = s.y * h; val r = w * 0.07
    val p = Path(); p.addOval(androidx.compose.ui.geometry.Rect((cx - r).f, (cy - r * 0.8).f, (cx + r).f, (cy + r * 0.8).f))
    for (i in 0 until 8) {
        val k = s.seed * 7 + i
        val ang = hash(k) * 2 * PI; val dist = r * (0.8 + hash(k + 1) * 0.9); val rr = r * (0.1 + hash(k + 2) * 0.22)
        val qx = cx + cos(ang) * dist; val qy = cy + sin(ang) * dist
        p.addOval(androidx.compose.ui.geometry.Rect((qx - rr).f, (qy - rr).f, (qx + rr).f, (qy + rr).f))
    }
    fillPath(p, juice(s.kind).op(0.5 * a))
}

private fun DrawScope.spray(s: Splat, w: Double, h: Double, now: Double) {
    val t = now - s.born
    if (t < 0 || t >= 0.7) return
    val cx = s.x * w; val cy = s.y * h
    val p = Path()
    for (i in 0 until 14) {
        val k = s.seed * 11 + i
        val ang = hash(k) * 2 * PI; val sp = w * (0.35 + hash(k + 3) * 0.55)
        val qx = cx + cos(ang) * sp * t; val qy = cy + sin(ang) * sp * t + 0.5 * 1.5 * h * t * t
        val rr = (1.6 + hash(k + 5) * 2.6) * density
        p.addOval(androidx.compose.ui.geometry.Rect((qx - rr).f, (qy - rr).f, (qx + rr).f, (qy + rr).f))
    }
    fillPath(p, juice(s.kind).op(clamp(1 - t / 0.7, 0.0, 1.0)))
}

/** A half fruit at the origin: the fruit clipped to one side of the cut, its flesh showing. */
private fun DrawScope.drawHalf(k: Int, r: Double, side: Double) {
    val u = density.toDouble()
    val top = if (side > 0) -0.5 else -r * 2 + 0.5
    clipRect((-r * 2).f, top.f, (r * 2).f, (top + r * 2).f) {
        FruitArt.draw(this, kinds[k % 6], 0.0, 0.0, r)
        val flesh = juice(k)
        when (k % 6) {
            0 -> {
                ellipse(0.0, 0.0, r * 0.9, r * 0.38, rgb(0.88, 0.97, 0.72))
                ellipse(0.0, 0.0, r * 0.8, r * 0.3, vgrad(listOf(rgb(1.0, 0.36, 0.36), rgb(0.86, 0.08, 0.14)), -r * 0.3, r * 0.3))
                for (i in 0 until 6) {
                    val x = -r * 0.55 + r * 0.22 * i; val y = side * r * (0.1 + 0.06 * (i % 2))
                    oval(x - r * 0.04, y - r * 0.06, r * 0.08, r * 0.12, rgb(0.1, 0.06, 0.05))
                }
            }
            2 -> {
                ellipse(0.0, 0.0, r * 0.9, r * 0.38, rgb(1.0, 0.95, 0.8))
                ellipseStroke(0.0, 0.0, r * 0.9, r * 0.38, rgb(0.85, 0.1, 0.14), max(u, r * 0.08))
                for (x in listOf(-0.12, 0.12)) oval(r * x - r * 0.05, side * r * 0.12 - r * 0.07, r * 0.1, r * 0.14, rgb(0.4, 0.22, 0.08))
            }
            4 -> { ellipse(0.0, 0.0, r * 0.9, r * 0.38, flesh); ellipse(0.0, 0.0, r * 0.45, r * 0.18, rgb(1.0, 0.78, 0.8)) }
            5 -> { ellipse(0.0, 0.0, r * 0.9, r * 0.38, rgb(1.0, 0.86, 0.34)); ellipse(0.0, 0.0, r * 0.22, r * 0.12, rgb(1.0, 0.96, 0.72)) }
            else -> {
                ellipse(0.0, 0.0, r * 0.9, r * 0.38, rgb(1.0, 0.96, 0.84))
                ellipse(0.0, 0.0, r * 0.8, r * 0.3, flesh)
                val seg = Path()
                for (i in 0 until 6) { val a = i / 6.0 * PI * 2; seg.m(0.0, 0.0); seg.l(cos(a) * r * 0.8, sin(a) * r * 0.3) }
                strokePath(seg, Color.White.op(0.6), max(0.8 * u, r * 0.04))
            }
        }
        ellipseStroke(0.0, 0.0, r * 0.9, r * 0.38, Color.Black.op(0.18), u)
    }
}

/** The swoosh: pointed at both ends, widest near the finger, with a pale blue sheen. */
private fun DrawScope.bladeArt(pts: List<P>, width: Double) {
    val n = pts.size
    if (n < 2) return
    val left = mutableListOf<P>(); val right = mutableListOf<P>()
    for (i in 0 until n) {
        val a = pts[max(0, i - 1)]; val b = pts[min(n - 1, i + 1)]
        val len = max(0.001, hypot(b.x - a.x, b.y - a.y))
        val dx = (b.x - a.x) / len; val dy = (b.y - a.y) / len
        val f = i.toDouble() / (n - 1)
        val hw = width * 0.5 * sin(PI * f.pow(0.62))
        left.add(P(pts[i].x - dy * hw, pts[i].y + dx * hw)); right.add(P(pts[i].x + dy * hw, pts[i].y - dx * hw))
    }
    val poly = polyPath(left + right.reversed())
    drawPath(poly, rgb(0.7, 0.88, 1.0, 0.35), style = Stroke((width * 0.8).f, join = StrokeJoin.Round))
    fillPath(poly, Color.White)
}

private fun DrawScope.bombHalo(cx: Double, cy: Double, r: Double, now: Double) {
    val rr = r * (1.35 + 0.1 * sin(now * 9))
    val inner = (r * 0.8 / rr).toFloat().coerceIn(0f, 1f)
    drawCircle(androidx.compose.ui.graphics.Brush.radialGradient(0f to SysColor.red.op(0.55), inner to SysColor.red.op(0.55), 1f to SysColor.red.op(0.0),
        center = off(cx, cy), radius = rr.f), rr.f, off(cx, cy))
}

/** The bomb at the origin: a dark glossy ball, a red brush mark, an iron cap and a fuse. */
private fun DrawScope.bomb(r: Double) {
    val fuse = Path(); fuse.m(r * 0.62, -r * 0.84); fuse.q(r * 0.95, -r * 0.9, r * 0.92, -r * 1.22)
    strokePath(fuse, rgb(0.28, 0.2, 0.12), r * 0.14)
    strokePath(fuse, rgb(0.78, 0.62, 0.38), r * 0.07)
    translate((r * 0.5).f, (-r * 0.72).f) {
        rotate(38f, Offset.Zero) { rrect(-r * 0.2, -r * 0.13, r * 0.4, r * 0.26, r * 0.05, vgrad(listOf(gray(0.55), gray(0.22)), -r * 0.13, r * 0.13)) }
    }
    circle(0.0, 0.0, r, radial(listOf(rgb(0.36, 0.38, 0.48), rgb(0.1, 0.1, 0.15), rgb(0.02, 0.02, 0.04)), -r * 0.35, -r * 0.4, r * 1.5))
    for ((a, b) in listOf(P(-r * 0.52, -r * 0.3) to P(r * 0.5, r * 0.42), P(r * 0.36, -r * 0.5) to P(-r * 0.3, r * 0.5))) {
        val dx = b.x - a.x; val dy = b.y - a.y; val len = hypot(dx, dy)
        val nx = -dy / len * r * 0.13; val ny = dx / len * r * 0.13
        val st = Path(); st.m(a.x, a.y)
        st.q((a.x + b.x) / 2 + nx, (a.y + b.y) / 2 + ny, b.x, b.y)
        st.q((a.x + b.x) / 2 - nx, (a.y + b.y) / 2 - ny, a.x, a.y)
        fillPath(st, rgb(0.88, 0.08, 0.1))
    }
    circleStroke(0.0, 0.0, r, Color.Black, r * 0.07)
    oval(-r * 0.62, -r * 0.68, r * 0.42, r * 0.24, Color.White.op(0.35))
}

/** The flickering spark at the fuse tip, in the bomb's own (rotated) frame. */
private fun DrawScope.fuseSpark(r: Double, now: Double) {
    val tx = r * 0.92; val ty = -r * 1.22
    val flick = (now * 20).toInt()
    circle(tx, ty, r * 0.3, radial(listOf(rgb(1.0, 0.8, 0.3, 0.8), Color.Transparent), tx, ty, r * 0.3))
    val rays = Path()
    for (i in 0 until 7) {
        val a = i / 7.0 * 2 * PI + flick * 0.7
        val len = r * (0.16 + hash((flick * 7 + i).toDouble()) * 0.26)
        rays.m(tx, ty); rays.l(tx + cos(a) * len, ty + sin(a) * len)
    }
    strokePath(rays, rgb(1.0, 0.92, 0.5), max(density.toDouble(), r * 0.05))
    circle(tx, ty, r * 0.07, Color.White)
}

private fun DrawScope.boomArt(b: Boom, w: Double, h: Double, now: Double) {
    val age = now - b.born
    if (age < 0 || age >= 1.4) return
    val cx = b.x * w; val cy = b.y * h
    val fade = max(0.0, 1 - age / 1.4)
    val rays = Path(); val far = max(w, h) * 1.5
    for (i in 0 until 12) {
        val a = i / 12.0 * 2 * PI + age * 0.5
        rays.m(cx, cy); rays.l(cx + cos(a - 0.08) * far, cy + sin(a - 0.08) * far); rays.l(cx + cos(a + 0.08) * far, cy + sin(a + 0.08) * far); rays.close()
    }
    fillPath(rays, Color.White.op(0.6 * fade))
    drawRect(Color.White.op(max(0.0, 0.8 - age * 1.1)))
    circle(cx, cy, w * 0.3, radial(listOf(Color.White.op(fade), Color.White.op(0.0)), cx, cy, w * 0.3))
}

/** The dojo board: planks with grain, knots and knife scars, an ink wave, and a volcanic glow from level 5. */
private fun DrawScope.dojo(level: Int) {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    val heat = (clampI(level, 1, 7) - 1) / 6.0
    val base = rgb(0.66, 0.46, 0.27).mix(rgb(0.4, 0.17, 0.12), heat)
    val planks = 6; val pw = w / planks
    for (i in 0 until planks) {
        val k = i.toDouble()
        val tone = base.mix(if (hash(k + 3) > 0.5) Color.White else Color.Black, 0.04 + hash(k + 7) * 0.08)
        val rx = i * pw
        rect(rx, 0.0, pw + 0.5, h, hgrad(listOf(tone.mix(Color.White, 0.06), tone, tone.mix(Color.Black, 0.12)), rx, rx + pw))
        val grain = Path()
        for (j in 0 until 6) {
            val x0 = rx + pw * (0.12 + 0.15 * j) + hash(k * 13 + j) * 6 * u
            grain.m(x0, 0.0)
            var y = 0.0
            while (y < h) { y += 18 * u; grain.l(x0 + sin(y / u * 0.03 + k + j) * 2.5 * u, y) }
        }
        strokePath(grain, Color.Black.op(0.08), u, StrokeCap.Butt)
        if (hash(k + 21) > 0.35) {
            val kx = rx + pw / 2 + (hash(k + 5) - 0.5) * pw * 0.4; val ky = h * (0.15 + hash(k + 9) * 0.7)
            for (ring in 0 until 3) { val rr = (4 + ring * 4) * u; ellipseStroke(kx, ky, rr * 0.6, rr * 1.3, Color.Black.op(0.12), 1.2 * u) }
        }
        rect(rx, 0.0, 2 * u, h, Color.Black.op(0.35))
        rect(rx + 2 * u, 0.0, u, h, Color.White.op(0.1))
    }
    val wave = Path()
    for (s in 0 until 4) {
        val o = s * 14 * u
        wave.m(-20 * u, h * 0.92 - o)
        wave.c(w * 0.2, h * 0.9 - o, w * 0.28, h * 0.5 - o, w * 0.52, h * 0.56 - o * 0.4)
        wave.q(w * 0.62, h * 0.62 - o * 0.5, w * 0.44, h * 0.64 - o * 0.5)
    }
    strokePath(wave, rgb(0.12, 0.06, 0.03, 0.09), 3 * u)
    val dark = Path(); val light = Path()
    for (i in 0 until 9) {
        val k = i + 40.0
        val px = hash(k) * w; val py = hash(k + 1) * h
        val a = (if (hash(k + 2) > 0.5) 1.0 else -1.0) * (0.35 + hash(k + 3) * 0.6)
        val len = (30 + hash(k + 4) * 70) * u
        val qx = px + cos(a) * len; val qy = py + sin(a) * len
        dark.m(px, py); dark.l(qx, qy)
        light.m(px + u, py + 1.2 * u); light.l(qx + u, qy + 1.2 * u)
    }
    strokePath(dark, Color.Black.op(0.32), 1.6 * u)
    strokePath(light, Color.White.op(0.14), u)
    if (level >= 5) drawRect(radial(listOf(rgb(1.0, 0.32, 0.08, 0.18 * (level - 4)), Color.Transparent), w / 2, h * 1.05, h * 0.75))
}
