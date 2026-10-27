package com.gogs.bananagame.games.pyramidhop

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
import androidx.compose.material.icons.filled.NorthEast
import androidx.compose.material.icons.filled.NorthWest
import androidx.compose.material.icons.filled.SouthEast
import androidx.compose.material.icons.filled.SouthWest
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
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/**
 * Brain — Pyramid Hop (iOS QbertGame.swift, id "qbert"): four diagonal keys hop cube to cube; each
 * landing flips the top toward the target colour. Light every cube to win; hop off the edge, get
 * landed on by the coiled hunter, or time out → level 1. Drawn as Gottlieb's 1982 Q*bert.
 */
object PyramidHopGame {
    val definition = GameDefinition(
        id = "qbert",
        title = "Pyramid Hop",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Use the four diagonal buttons to hop from cube to cube.",
                "Each landing flips a cube's top toward the target color.",
                "Light up every cube to win.",
                "Hop into the void, get caught by the bouncing hunter, or time out, and you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Dùng bốn nút chéo để nhảy từ khối này sang khối khác.",
                "Mỗi lần đáp sẽ đổi mặt trên của khối tiến về màu mục tiêu.",
                "Thắp sáng mọi khối để thắng.",
                "Nhảy ra khoảng không, bị kẻ săn nảy bắt, hoặc hết giờ, sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> PyramidHopView(level, onWin, onFail) }
    )
}

private data class Cube(val r: Int, val c: Int)

private class HopWorld(val level: Int) {
    private val li = min(level, 7) - 1
    val rowsN = listOf(4, 4, 5, 5, 6, 6, 7)[li]
    val hopsNeeded = if (level >= 4) 2 else 1
    val enemyStep = listOf(1.5, 1.2, 0.95, 0.78, 0.64, 0.54, 0.46)[li]
    /** Seconds before the hunter starts moving — a longer breather on the gentle early levels. */
    val enemyGrace = listOf(2.0, 1.5, 1.0, 0.6, 0.4, 0.3, 0.2)[li]
    val cubes = rowsN * (rowsN + 1) / 2
    val timeLimit = cubes * hopsNeeded * listOf(2.4, 2.2, 1.9, 1.6, 1.35, 1.15, 0.98)[li]

    var playing = true
    val state = HashMap<Cube, Int>()
    var player = Cube(0, 0)
    var enemy: Cube? = null
    var enemyAcc = 0.0
    var timeLeft = timeLimit
    var shakeT0 = -10.0
    // Presentation: hop arcs, facing, the last direction tried, when the round was lost.
    var hopFrom: Cube? = null; var hopAt: Double? = null
    var coilyFrom: Cube? = null; var coilyAt: Double? = null
    var faceUp = false; var faceLeft = true
    var lastTry = Cube(1, 0)
    var lostAt: Double? = null
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    val coloredCount get() = state.values.count { it >= hopsNeeded }
    fun onPyramid(p: Cube) = p.r in 0 until rowsN && p.c >= 0 && p.c <= p.r

    fun setup() {
        state.clear()
        for (r in 0 until rowsN) for (c in 0..r) state[Cube(r, c)] = 0
        player = Cube(0, 0)
        state[player] = min(hopsNeeded, 1)
        enemy = Cube(rowsN - 1, if (Random.nextBoolean()) 0 else rowsN - 1)
        // Negative accumulator = the grace delay counts up to 0 before the first hop.
        enemyAcc = -enemyGrace
        hopFrom = null; hopAt = null; coilyFrom = null; coilyAt = null; lostAt = null
        faceUp = false; faceLeft = true
        timeLeft = timeLimit; playing = true
    }

    fun hop(dr: Int, dc: Int) {
        if (!playing) return
        lastTry = Cube(dr, dc)
        val dest = Cube(player.r + dr, player.c + dc)
        if (!onPyramid(dest)) { fail(); return }
        hopFrom = player; hopAt = nowSec()
        faceUp = dr < 0
        faceLeft = (dr < 0 && dc < 0) || (dr > 0 && dc == 0)
        player = dest
        state[dest] = min(hopsNeeded, (state[dest] ?: 0) + 1)
        SoundManager.tap(); Haptics.tap()
        if (enemy == dest) { fail(); return }
        if (coloredCount >= cubes) win()
    }

    fun stepEnemy(dt: Double) {
        val e = enemy ?: return
        enemyAcc += dt
        if (enemyAcc < enemyStep) return
        enemyAcc = 0.0
        // Greedy hop toward the player, staying on the pyramid.
        val best = listOf(Cube(e.r - 1, e.c - 1), Cube(e.r - 1, e.c), Cube(e.r + 1, e.c), Cube(e.r + 1, e.c + 1))
            .filter { onPyramid(it) }.minByOrNull { abs(it.r - player.r) + abs(it.c - player.c) } ?: return
        coilyFrom = e; coilyAt = nowSec()
        enemy = best
        if (best == player) fail()
    }

    fun win() { if (!playing) return; playing = false; onWin() }
    fun fail() {
        if (!playing) return
        playing = false; shakeT0 = nowSec()
        if (coloredCount < cubes) lostAt = nowSec()
        SoundManager.error(); onFail()
    }
}

private val demoHops = listOf("DL", "DR", "DL", "UR", "UR", "DR", "DR", "UL", "DL", "UL", "UL", "DL", "DL").map {
    when (it) { "UL" -> -1 to -1; "UR" -> -1 to 0; "DL" -> 1 to 0; else -> 1 to 1 }
}

@Composable
private fun PyramidHopView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { HopWorld(level).also { it.setup() } }
    world.onWin = onWin; world.onFail = onFail
    var demoTick by remember { mutableIntStateOf(0) }
    var demoKey by remember { mutableStateOf<Pair<Int, Int>?>(null) }
    val tm = rememberTextMeasurer()
    val start = remember { nowSec() }
    val tick by rememberFrameLoop(maxDt = 0.08) { dt ->
        if (isDemo || !world.playing) return@rememberFrameLoop
        world.timeLeft = max(0.0, world.timeLimit - (nowSec() - start))
        if (world.timeLeft <= 0) { world.fail(); return@rememberFrameLoop }
        world.stepEnemy(dt)
    }

    // Level 1 through the real hop/stepEnemy at 1/30 s: a DP-found route that lights the far side,
    // waits out the hunter, dodges its lunge and finishes on the corner it left.
    LaunchedEffect(Unit) {
        if (!isDemo) return@LaunchedEffect
        val dt = 1.0 / 30.0
        while (isActive) {
            world.setup(); world.enemy = Cube(world.rowsN - 1, 0); demoKey = null
            delay(400)
            var frame = 0; var next = 0
            while (isActive && world.playing && frame < 600) {
                frame++
                if (next < demoHops.size && frame == 24 + 13 * next) {
                    val h = demoHops[next]; demoKey = h; world.hop(h.first, h.second); next++
                }
                if (demoKey != null && next > 0 && frame == 24 + 13 * (next - 1) + 6) demoKey = null
                if (world.playing) world.stepEnemy(dt)
                demoTick++
                delay(33)
            }
            demoKey = null
            val end = nowSec()
            while (isActive && nowSec() - end < 1.3) { demoTick++; delay(33) }
        }
    }

    val pal = palette(level)
    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .background(Color.Black),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(if (isDemo) 4.dp else 6.dp)
    ) {
        tick; demoTick
        // The "change to" sample — the target colour between two arrows — and the count.
        Row(Modifier.padding(top = if (isDemo) 6.dp else 0.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Canvas(Modifier.size(if (isDemo) 50.dp else 64.dp, if (isDemo) 20.dp else 26.dp)) { changeTo(pal.target, pal.left, pal.right) }
            Text("${world.coloredCount}/${world.cubes}", style = ts(if (isDemo) 15.0 else 20.0, FontWeight.Black, Color.White).copy(fontFeatureSettings = "tnum"))
        }
        if (!isDemo) {
            val f = world.timeLeft / world.timeLimit
            TimeBar(f, Modifier.fillMaxWidth().padding(horizontal = 60.dp).height(5.dp), fill = if (f < 0.3) rgb(1.0, 0.3, 0.25) else QBOrange)
        }
        Canvas(
            Modifier.fillMaxWidth().weight(1f).clipToBounds().graphicsLayer {
                val t = nowSec() - world.shakeT0
                if (t in 0.0..0.35) translationX = (5 * density * sin(t / 0.35 * PI * 3) * (1 - t / 0.35)).toFloat()
            }
        ) {
            tick; demoTick
            field(world, pal, isDemo, tm)
        }
        Row(Modifier.padding(bottom = if (isDemo) 6.dp else 10.dp), horizontalArrangement = Arrangement.spacedBy(if (isDemo) 18.dp else 26.dp)) {
            val g = if (isDemo) 5.dp else 8.dp
            Column(verticalArrangement = Arrangement.spacedBy(g)) {
                HopKey(Icons.Filled.NorthWest, -1, -1, world, isDemo, demoKey); HopKey(Icons.Filled.SouthWest, 1, 0, world, isDemo, demoKey)
            }
            Column(verticalArrangement = Arrangement.spacedBy(g)) {
                HopKey(Icons.Filled.NorthEast, -1, 0, world, isDemo, demoKey); HopKey(Icons.Filled.SouthEast, 1, 1, world, isDemo, demoKey)
            }
        }
    }
}

/** A diagonal hop key in Q*bert orange (white when pressed). */
@Composable
private fun HopKey(icon: ImageVector, dr: Int, dc: Int, world: HopWorld, isDemo: Boolean, demoKey: Pair<Int, Int>?) {
    var held by remember { mutableStateOf(false) }
    val lit = (isDemo && demoKey == (dr to dc)) || held
    Box(
        Modifier.scale(if (lit) 0.9f else 1f).size(if (isDemo) 60.dp else 74.dp, if (isDemo) 36.dp else 58.dp)
            .then(if (isDemo) Modifier else Modifier.pressDown(onDown = { held = true; world.hop(dr, dc) }, onUp = { held = false })),
        contentAlignment = Alignment.Center
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val u = density.toDouble(); val w = size.width.toDouble(); val h = size.height.toDouble()
            val cols = if (lit) listOf(Color.White, rgb(1.0, 0.88, 0.62)) else listOf(rgb(1.0, 0.66, 0.24), rgb(0.9, 0.4, 0.08))
            rrect(0.0, 0.0, w, h, 16 * u, vgrad(cols, 0.0, h))
            rrectStroke(u, u, w - 2 * u, h - 2 * u, 15 * u, Color.Black.op(0.5), 2 * u)
            rrectStroke(3.6 * u, 3.6 * u, w - 7.2 * u, h - 7.2 * u, 12.4 * u, Color.White.op(if (lit) 0.95 else 0.3), 1.2 * u)
        }
        Icon(icon, null, tint = rgb(0.3, 0.1, 0.0), modifier = Modifier.size(if (isDemo) 22.dp else 28.dp))
    }
}

// Q*bert art (after Gottlieb's 1982 arcade game; iOS QBArt).

private val QBOrange = rgb(1.0, 0.52, 0.1)

private class QBPalette(val base: Color, val mid: Color, val target: Color, val left: Color, val right: Color)

/** Tri-coloured cubes: a new top / side scheme each level (blue → yellow first). */
private fun palette(level: Int) = when (min(max(level, 1), 7)) {
    1 -> QBPalette(rgb(0.33, 0.42, 0.96), rgb(0.33, 0.42, 0.96), rgb(1.0, 0.9, 0.18), rgb(0.82, 0.7, 0.47), rgb(0.34, 0.33, 0.42))
    2 -> QBPalette(rgb(0.2, 0.62, 0.55), rgb(0.2, 0.62, 0.55), rgb(1.0, 0.62, 0.78), rgb(0.62, 0.66, 0.74), rgb(0.26, 0.28, 0.36))
    3 -> QBPalette(rgb(0.56, 0.3, 0.78), rgb(0.56, 0.3, 0.78), rgb(0.42, 0.92, 0.42), rgb(0.9, 0.8, 0.56), rgb(0.3, 0.22, 0.36))
    4 -> QBPalette(rgb(0.36, 0.4, 0.46), rgb(0.3, 0.64, 0.98), rgb(1.0, 0.88, 0.2), rgb(0.82, 0.54, 0.32), rgb(0.42, 0.24, 0.18))
    5 -> QBPalette(rgb(0.66, 0.2, 0.26), rgb(0.98, 0.56, 0.24), rgb(1.0, 0.96, 0.66), rgb(0.56, 0.62, 0.72), rgb(0.24, 0.27, 0.36))
    6 -> QBPalette(rgb(0.22, 0.48, 0.3), rgb(0.92, 0.86, 0.3), rgb(0.98, 0.42, 0.62), rgb(0.72, 0.72, 0.78), rgb(0.3, 0.3, 0.36))
    else -> QBPalette(rgb(0.38, 0.23, 0.52), rgb(0.3, 0.82, 0.88), rgb(1.0, 0.9, 0.2), rgb(0.86, 0.6, 0.4), rgb(0.4, 0.2, 0.2))
}

private fun DrawScope.field(world: HopWorld, pal: QBPalette, isDemo: Boolean, tm: TextMeasurer) {
    val w = size.width.toDouble(); val h = size.height.toDouble()
    val n = world.rowsN
    // The squat demo card: size the pyramid to the height too and drop the apex into frame.
    val cubeW = if (isDemo) min(w * 0.68 / n, h / (0.8 * (n - 1) + 1.55)) else w * 0.68 / n
    val topY = if (isDemo) cubeW * 0.82 else h * 0.14
    fun px(p: Cube) = w * 0.5 + (p.c - p.r / 2.0) * cubeW
    fun py(p: Cube) = topY + p.r * cubeW * 0.80
    fun top(s: Int) = if (s <= 0) pal.base else if (s >= world.hopsNeeded) pal.target else pal.mid
    for (r in 0 until n) for (c in 0..r) {
        val cell = Cube(r, c)
        cube(px(cell), py(cell), cubeW, top(world.state[cell] ?: 0), pal.left, pal.right)
    }
    fun stand(p: Cube) = P(px(p), py(p) - cubeW * 0.36)
    val now = nowSec()
    world.enemy?.let { e ->
        val at = hopPoint(world.coilyFrom?.let { stand(it) }, stand(e), world.coilyAt, now, cubeW * 0.45)
        coily(at.x, at.y, cubeW * 0.74, px(e) > px(world.player))
    }
    // Q*bert: hopping, or — once the round is lost — cursing (and falling, if he hopped off the edge).
    var at = hopPoint(world.hopFrom?.let { stand(it) }, stand(world.player), world.hopAt, now, cubeW * 0.5)
    var sc = 1.0
    var up = world.faceUp; var left = world.faceLeft
    val lost = world.lostAt
    if (lost != null) {
        val t = now - lost
        val off = Cube(world.player.r + world.lastTry.r, world.player.c + world.lastTry.c)
        var balloon = P(at.x, at.y - cubeW * 0.42)
        if (world.enemy != world.player && world.timeLeft > 0 && !world.onPyramid(off)) {
            // He jumped into the void: arc out, then drop away and shrink; the curse stays at the edge.
            up = world.lastTry.r < 0
            left = (world.lastTry.r < 0 && world.lastTry.c < 0) || (world.lastTry.r > 0 && world.lastTry.c == 0)
            at = arc(stand(world.player), stand(off), min(1.0, t / 0.2), cubeW * 0.5)
            val drop = max(0.0, t - 0.2)
            at = P(at.x, at.y + drop * drop * cubeW * 6)
            sc = max(0.35, 1 - drop * 0.7)
            val edge = stand(off)
            balloon = P(edge.x, edge.y - cubeW * 0.42)
        }
        qbert(at.x, at.y, cubeW * 0.74 * sc, up, left)
        grawlix(tm, balloon.x, balloon.y, cubeW)
        return
    }
    qbert(at.x, at.y, cubeW * 0.74, up, left)
}

/** One cube: a `w × 1.2w` box centred on (cx, cy), its top diamond `w/2` tall. */
private fun DrawScope.cube(cx: Double, cy: Double, w: Double, top: Color, left: Color, right: Color) {
    val x0 = cx - w / 2; val y0 = cy - w * 0.6
    val topH = w * 0.5; val sideH = w * 0.7
    val lFace = polyPath(x0, y0 + topH * 0.5, x0 + w / 2, y0 + topH, x0 + w / 2, y0 + topH + sideH, x0, y0 + topH * 0.5 + sideH)
    val rFace = polyPath(x0 + w, y0 + topH * 0.5, x0 + w / 2, y0 + topH, x0 + w / 2, y0 + topH + sideH, x0 + w, y0 + topH * 0.5 + sideH)
    val tFace = polyPath(x0 + w / 2, y0, x0 + w, y0 + topH / 2, x0 + w / 2, y0 + topH, x0, y0 + topH / 2)
    fillPath(lFace, left); fillPath(rFace, right); fillPath(tFace, top)
    // A thin inner bevel on the top keeps neighbouring tops apart.
    val inset = polyPath(x0 + w / 2, y0 + topH * 0.12, x0 + w * 0.88, y0 + topH / 2, x0 + w / 2, y0 + topH * 0.88, x0 + w * 0.12, y0 + topH / 2)
    val lw = max(density.toDouble(), w * 0.02)
    strokePath(inset, Color.White.op(0.18), lw)
    for (f in listOf(tFace, lFace, rFace)) strokePath(f, Color.Black.op(0.6), lw)
}

/** A point on a hop's arc (`t` 0…1). */
private fun arc(a: P, b: P, t: Double, lift: Double): P {
    val k = clamp(t, 0.0, 1.0)
    return P(a.x + (b.x - a.x) * k, a.y + (b.y - a.y) * k - lift * 4 * k * (1 - k))
}

/** Where a hopper is drawn: on its hop arc for 0.18 s after `since`, else on its cube. */
private fun hopPoint(a: P?, b: P, since: Double?, now: Double, lift: Double): P {
    if (a == null || since == null) return b
    val t = (now - since) / 0.18
    return if (t >= 1) b else arc(a, b, t, lift)
}

/** Q*bert: an orange ball with big eyes, a tube snout and black shoes, facing his hop. */
private fun DrawScope.qbert(px: Double, py: Double, s: Double, up: Boolean, left: Boolean) {
    translate(px.f, py.f) { scale((if (left) -s else s).f, s.f, Offset.Zero) {
        val ink = rgb(0.18, 0.06, 0.0)
        val body = QBOrange
        oval(-0.3, 0.38, 0.6, 0.12, Color.Black.op(0.3))
        val legs = Path(); legs.m(-0.1, 0.2); legs.l(-0.12, 0.38); legs.m(0.1, 0.2); legs.l(0.1, 0.38)
        strokePath(legs, body.mix(Color.Black, 0.2), 0.08)
        for (x in listOf(-0.12, 0.1)) oval(x - 0.08, 0.34, 0.26, 0.12, gray(0.08))
        drawOval(radial(listOf(rgb(1.0, 0.78, 0.45), body, body.mix(Color.Black, 0.3)), -0.1, -0.16, 0.42), Offset(-0.32f, -0.32f), androidx.compose.ui.geometry.Size(0.64f, 0.6f))
        drawOval(ink, Offset(-0.32f, -0.32f), androidx.compose.ui.geometry.Size(0.64f, 0.6f), style = Stroke(0.035f))
        // The tube snout: forward and down (or up when he hops away from you).
        val tipX = 0.44; val tipY = if (up) -0.2 else 0.14
        val rootY = if (up) -0.06 else 0.04
        line(0.14, rootY, tipX, tipY, ink, 0.2)
        line(0.14, rootY, tipX, tipY, body.mix(Color.White, 0.08), 0.14)
        oval(tipX - 0.05, tipY - 0.07, 0.1, 0.14, ink)
        // Big eyes.
        for ((x, r) in listOf(-0.02 to 0.1, 0.17 to 0.09)) {
            oval(x - r, -0.22 - r, r * 2, r * 2.2, Color.White)
            drawOval(ink, Offset((x - r).f, (-0.22 - r).f), androidx.compose.ui.geometry.Size((r * 2).f, (r * 2.2).f), style = Stroke(0.025f))
            oval(x - r * 0.1, (if (up) -0.3 else -0.2) - r * 0.4, r * 0.8, r * 0.9, Color.Black)
        }
    } }
}

/** Coily: a purple snake on its coiled spring body, big eyes on whoever it's after. */
private fun DrawScope.coily(px: Double, py: Double, s: Double, left: Boolean) {
    translate(px.f, py.f) { scale((if (left) -s else s).f, s.f, Offset.Zero) {
        val purple = rgb(0.62, 0.3, 0.86)
        val ink = rgb(0.12, 0.02, 0.2)
        oval(-0.3, 0.38, 0.6, 0.12, Color.Black.op(0.3))
        for ((y, w) in listOf(0.3 to 0.5, 0.16 to 0.44, 0.03 to 0.38)) {
            drawOval(vgrad(listOf(purple.mix(Color.White, 0.25), purple.mix(Color.Black, 0.25)), y - 0.08, y + 0.1),
                Offset((-w / 2).f, (y - 0.08).f), androidx.compose.ui.geometry.Size(w.f, 0.18f))
            drawOval(ink, Offset((-w / 2).f, (y - 0.08).f), androidx.compose.ui.geometry.Size(w.f, 0.18f), style = Stroke(0.03f))
        }
        drawOval(radial(listOf(purple.mix(Color.White, 0.3), purple, purple.mix(Color.Black, 0.3)), -0.04, -0.36, 0.34),
            Offset(-0.22f, -0.46f), androidx.compose.ui.geometry.Size(0.5f, 0.42f))
        drawOval(ink, Offset(-0.22f, -0.46f), androidx.compose.ui.geometry.Size(0.5f, 0.42f), style = Stroke(0.03f))
        for (x in listOf(-0.05, 0.14)) {
            oval(x - 0.08, -0.4, 0.16, 0.18, Color.White)
            oval(x - 0.01, -0.34, 0.08, 0.09, Color.Black)
        }
        val brows = Path(); brows.m(-0.14, -0.44); brows.l(0.02, -0.4); brows.m(0.07, -0.4); brows.l(0.23, -0.45)
        strokePath(brows, ink, 0.04)
        val tongue = Path(); tongue.m(0.24, -0.16); tongue.l(0.4, -0.12); tongue.m(0.4, -0.12); tongue.l(0.46, -0.16); tongue.m(0.4, -0.12); tongue.l(0.46, -0.08)
        strokePath(tongue, rgb(0.95, 0.15, 0.2), 0.035)
    } }
}

/** A comic curse balloon (a generic grawlix), kept inside the field. */
private fun DrawScope.grawlix(tm: TextMeasurer, ax: Double, ay: Double, cubeW: Double) {
    val u = density.toDouble()
    val fs = max(9 * u, cubeW * 0.3)
    val tw = textWidth(tm, "#%&!", fs, FontWeight.Black); val th = fs * 1.2
    val px = min(max(ax, tw / 2 + 12 * u), size.width - tw / 2 - 12 * u)
    val py = max(ay, th + 16 * u)
    val bx = px - tw / 2 - 8 * u; val by = py - th - 12 * u; val bw = tw + 16 * u; val bh = th + 8 * u
    rrect(bx, by, bw, bh, bh / 2, Color.White)
    fillPath(polyPath(px - 4 * u, by + bh - u, px + 2 * u, by + bh + 7 * u, px + 6 * u, by + bh - u), Color.White)
    rrectStroke(bx, by, bw, bh, bh / 2, Color.Black, 1.5 * u)
    text(tm, "#%&!", bx + bw / 2, by + bh / 2, fs, Color.Black, FontWeight.Black)
}

/** "Change to": the target colour on a little cube, with an arrow pointing at it from each side. */
private fun DrawScope.changeTo(top: Color, left: Color, right: Color) {
    val w = size.width.toDouble(); val h = size.height.toDouble()
    val cw = h * 0.95
    cube(w / 2, h / 2 + cw * 0.02, cw * 0.82, top, left, right)
    for (s in listOf(-1.0, 1.0)) {
        val tipX = w / 2 - s * cw * 0.6
        fillPath(polyPath(tipX, h / 2, tipX - s * h * 0.34, h / 2 - h * 0.24, tipX - s * h * 0.34, h / 2 + h * 0.24), QBOrange)
    }
}
