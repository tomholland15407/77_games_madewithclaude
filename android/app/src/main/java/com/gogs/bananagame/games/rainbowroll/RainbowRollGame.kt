package com.gogs.bananagame.games.rainbowroll

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Sync
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.VectorPainter
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Reflex — Rainbow Roll (iOS ColorBumpGame.swift, id "color-bump"): the ball auto-rolls; tap the
 * left/right half to steer through the band matching its colour. Gates repaint the ball.
 */
object RainbowRollGame {
    val definition = GameDefinition(
        id = "color-bump",
        title = "Rainbow Roll",
        genre = Genre.REFLEX,
        manual = GameManual(
            bullets = listOf(
                "The ball auto-rolls down the lane. Tap the left or right half to steer.",
                "Barriers split into color bands — only roll through the band matching your ball.",
                "Color gates repaint the ball, so re-read every barrier.",
                "Reach the target distance to win; a wrong color sends you back to level 1.",
            ),
            bulletsVI = listOf(
                "Quả bóng tự lăn xuống làn. Chạm nửa trái hoặc phải để lái.",
                "Rào chắn chia thành các dải màu — chỉ lăn qua dải khớp màu bóng của bạn.",
                "Cổng đổi màu tô lại màu bóng, nên hãy đọc kỹ mỗi rào chắn.",
                "Đạt quãng đường mục tiêu để thắng; sai màu sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> RainbowRollView(level, onWin, onFail) }
    )
}

private val palette = listOf(rgb(0.95, 0.30, 0.36), rgb(0.30, 0.62, 1.00), rgb(1.00, 0.82, 0.25), rgb(0.40, 0.82, 0.48))
private fun swatch(i: Int) = palette[clampI(i, 0, palette.size - 1)]

private const val LANE_LO = 0.14
private const val LANE_HI = 0.86
private const val BALL_SY = 0.74
private const val BALL_R = 0.05
private const val STEER = 0.17
private val demoLayout = listOf(listOf(1, 0), listOf(0, 1), listOf(1, 0), listOf(0, 1), listOf(1, 0))

private class Band(val lo: Double, val hi: Double, val color: Int)
private class Row(val z: Double, val gate: Int?, val bands: List<Band>) { var scattered = -1 }

private class RollWorld(val level: Int) {
    private val li = min(level, 7) - 1
    val rollSpeed = listOf(0.60, 0.70, 0.80, 0.92, 1.05, 1.20, 1.38)[li]
    val spacing = listOf(0.95, 0.85, 0.76, 0.68, 0.60, 0.54, 0.48)[li]
    val bandCount = listOf(2, 2, 3, 3, 4, 4, 5)[li]
    val gateEvery = listOf(5, 4, 4, 3, 3, 2, 2)[li]
    val targetDist = listOf(4.5, 5.5, 6.5, 7.5, 8.5, 10.0, 12.0)[li]
    val colorsUsed = min(4, 2 + level / 2)

    var rows = listOf<Row>()
    var nextRow = 0
    var distance = 0.0
    var ballX = 0.5; var targetX = 0.5
    var colorIndex = 0
    var done = false
    var burstT0 = -1.0
    var shakeT0 = -10.0
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    private fun barrier(matching: Int): List<Band> {
        val colors = MutableList(bandCount) { rndInt(0 until colorsUsed) }
        if (matching !in colors) colors[rndInt(0 until bandCount)] = matching
        val width = (LANE_HI - LANE_LO) / bandCount
        return (0 until bandCount).map { Band(LANE_LO + it * width, LANE_LO + (it + 1) * width, colors[it]) }
    }

    fun setup() {
        distance = 0.0; ballX = 0.5; targetX = 0.5; done = false; nextRow = 0; burstT0 = -1.0
        val built = mutableListOf<Row>()
        var z = 1.3
        var current = rndInt(0 until colorsUsed)
        colorIndex = current
        for (i in 0 until 5 + level * 2) {
            if (i > 0 && i % gateEvery == 0) {
                current = (0 until colorsUsed).filter { it != current }.randomOrNull() ?: current
                built.add(Row(z, current, emptyList()))
                z += spacing * 1.5
            }
            built.add(Row(z, null, barrier(current)))
            z += spacing
        }
        rows = built
    }

    fun demoSetup() {
        distance = 0.45; ballX = 0.5; targetX = 0.5; done = false; nextRow = 0; colorIndex = 0; burstT0 = -1.0
        val width = (LANE_HI - LANE_LO) / 2
        var z = 1.3
        rows = demoLayout.map { pair ->
            val r = Row(z, null, pair.mapIndexed { i, c -> Band(LANE_LO + i * width, LANE_LO + (i + 1) * width, c) })
            z += spacing; r
        }
    }

    fun steer(d: Double) {
        if (done) return
        targetX = clamp(targetX + d * STEER, LANE_LO + BALL_R, LANE_HI - BALL_R)
        SoundManager.tap(); Haptics.tap()
    }

    fun step(dt: Double) {
        if (done) return
        distance += rollSpeed * dt
        ballX += (targetX - ballX) * min(1.0, 18 * dt)
        while (nextRow < rows.size && distance >= rows[nextRow].z) {
            val row = rows[nextRow]; nextRow++
            if (row.gate != null) { colorIndex = row.gate; SoundManager.tap(); Haptics.tap() }
            else {
                val idx = row.bands.indexOfFirst { ballX >= it.lo && ballX < it.hi }.let { if (it < 0) row.bands.size - 1 else it }
                row.scattered = idx
                if (row.bands[idx].color != colorIndex) { shakeT0 = nowSec(); fail(); return }
            }
        }
        if (distance >= targetDist) win()
    }

    fun win() { if (done) return; done = true; onWin() }
    fun fail() { if (done) return; done = true; burstT0 = nowSec(); SoundManager.error(); onFail() }
}

@Composable
private fun RainbowRollView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { RollWorld(level).also { it.setup() } }
    world.onWin = onWin; world.onFail = onFail
    var demoSide by remember { mutableDoubleStateOf(0.0) }
    var demoTapT by remember { mutableDoubleStateOf(-10.0) }
    var demoTick by remember { mutableIntStateOf(0) }
    val sign = rememberVectorPainter(Icons.Filled.Sync)
    val handP = rememberHand()
    val stars = remember { Starfield(50) }
    val tick by rememberFrameLoop { dt -> if (!isDemo) world.step(dt) }

    LaunchedEffect(Unit) {
        if (!isDemo) return@LaunchedEffect
        val dt = 1.0 / 60.0
        while (isActive) {
            world.demoSetup(); demoSide = 0.0
            var steeredFor = -1
            val pending = ArrayDeque<Pair<Int, Double>>()
            var releaseAt = 0; var frame = 0
            while (isActive && !world.done && frame < 900) {
                frame++
                if (world.nextRow < world.rows.size && steeredFor < world.nextRow && world.rows[world.nextRow].z - world.distance < 0.55) {
                    val row = world.rows[world.nextRow]
                    val band = row.bands.firstOrNull { it.color == world.colorIndex }
                    if (row.gate == null && band != null) {
                        steeredFor = world.nextRow
                        val goal = (band.lo + band.hi) / 2
                        val side = if (goal < world.targetX) -1.0 else 1.0
                        val taps = (abs(goal - world.targetX) / STEER).roundAway()
                        for (k in 0 until taps) pending.addLast(frame + k * 11 to side)
                    }
                }
                val p = pending.firstOrNull()
                if (p != null && p.first <= frame) {
                    pending.removeFirst()
                    demoSide = p.second; world.steer(p.second); demoTapT = nowSec()
                    releaseAt = frame + 16
                }
                if (demoSide != 0.0 && frame >= releaseAt) demoSide = 0.0
                world.step(dt)
                demoTick++
                delay(16)
            }
            demoSide = 0.0
            delay(1300)
        }
    }

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .drawBehind { backdrop(level, stars) },
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        tick; demoTick
        Canvas(Modifier.fillMaxWidth().height(if (isDemo) 19.dp else 31.dp).padding(top = if (isDemo) 6.dp else 0.dp)) {
            progress(min(world.distance, world.targetDist) / world.targetDist, swatch(world.colorIndex), if (isDemo) 0.7 else 1.0)
        }
        Canvas(
            Modifier.fillMaxWidth().weight(1f)
                .graphicsLayer {
                    val t = nowSec() - world.shakeT0
                    if (t in 0.0..0.35) translationX = (7 * density * sin(t / 0.35 * PI * 3) * (1 - t / 0.35)).toFloat()
                }
                .then(if (isDemo) Modifier else Modifier.tapIn { p, w, _ -> world.steer(if (p.x < w / 2) -1.0 else 1.0) })
        ) {
            tick; demoTick
            course(world, sign)
            val w = size.width.toDouble(); val h = size.height.toDouble(); val u = density.toDouble()
            if (world.burstT0 >= 0) burst(world.ballX * w, BALL_SY * h, BALL_R * 2 * h, swatch(world.colorIndex), nowSec() - world.burstT0)
            if (isDemo && demoSide != 0.0) {
                val cx = if (demoSide < 0) w * 0.25 else w * 0.75
                rect(if (demoSide < 0) 0.0 else w / 2, 0.0, w / 2, h, rgb(0.2, 0.1, 0.3, 0.1))
                val s = 28 * u
                icon(handP, cx + 10 * u - s / 2, h * 0.9 + 14 * u - s / 2, s, rgb(0.16, 0.1, 0.24))
            }
            if (isDemo) tapRipple(if (demoSide < 0) w * 0.25 else w * 0.75, h * 0.9, nowSec() - demoTapT)
        }
    }
}

// Color Bump 3D art (iOS CBArt and friends).

/** Perspective: 1 at the ball, shrinking ahead; tuned so dz ≈ 0.82 is the top edge. */
private fun depthScale(dz: Double) = 1.2 / (1.2 + max(-0.6, dz))

private class Proj(val w: Double, val h: Double) {
    fun y(dz: Double): Double { val horizon = -1.083 * h; return horizon + (BALL_SY * h - horizon) * depthScale(dz) }
    fun x(frac: Double, dz: Double) = w / 2 + (frac * w - w / 2) * depthScale(dz)
    fun p(frac: Double, dz: Double) = P(x(frac, dz), y(dz))
}

private fun quad(a: P, b: P, c: P, d: P) = polyPath(listOf(a, b, c, d))

private fun DrawScope.course(world: RollWorld, sign: VectorPainter) {
    val w = size.width.toDouble(); val h = size.height.toDouble()
    val pr = Proj(w, h)
    track(pr, world.distance)
    for (row in world.rows.asReversed()) {
        val dz = row.z - world.distance
        if (dz <= -0.35 || dz >= 0.9) continue
        if (row.gate != null) gate(pr, swatch(row.gate), dz, sign)
        else row.bands.forEachIndexed { bi, b ->
            cubes(pr, swatch(b.color), b.lo, b.hi, dz, if (row.scattered == bi) max(0.0, -dz) else 0.0, world.ballX)
        }
    }
    if (world.burstT0 < 0) ball(world.ballX * w, BALL_SY * h, BALL_R * h, swatch(world.colorIndex))
}

/** The pale track in perspective, its rails, and stripes streaming toward the ball. */
private fun DrawScope.track(pr: Proj, distance: Double) {
    val u = density.toDouble()
    val near = -0.6; val far = 0.9
    drawPath(quad(pr.p(LANE_LO, far), pr.p(LANE_HI, far), pr.p(LANE_HI, near), pr.p(LANE_LO, near)),
        vgrad(listOf(rgb(0.84, 0.86, 0.9), rgb(0.97, 0.97, 0.99)), pr.y(far), pr.y(0.0)))
    val stripes = Path()
    val gap = 0.3
    var z = ceil(distance / gap) * gap - distance
    while (z < far) {
        if (z > near) stripes.addPath(quad(pr.p(LANE_LO, z), pr.p(LANE_HI, z), pr.p(LANE_HI, z - 0.02), pr.p(LANE_LO, z - 0.02)))
        z += gap
    }
    fillPath(stripes, Color.Black.op(0.05))
    for ((a, b) in listOf(LANE_LO - 0.03 to LANE_LO, LANE_HI to LANE_HI + 0.03)) {
        val rail = quad(pr.p(a, far), pr.p(b, far), pr.p(b, near), pr.p(a, near))
        fillPath(rail, Color.White); strokePath(rail, Color.Black.op(0.18), u)
    }
}

/** One band of a barrier as a row of 3D cubes; `scatter` sends the band the ball rolled through flying. */
private fun DrawScope.cubes(pr: Proj, color: Color, lo: Double, hi: Double, dz: Double, scatter: Double, ballX: Double) {
    val n = max(1, ((hi - lo) / 0.085).roundAway())
    val cw = (hi - lo) / n
    val depth = 0.05; val height = pr.h * 0.045
    val fade = if (scatter > 0) max(0.0, 1 - scatter / 0.45) else 1.0
    if (fade <= 0) return
    val unit = max(1.0, pr.x(1.0, 0.0) - pr.x(0.0, 0.0))
    withAlpha(fade) {
        for (i in 0 until n) {
            var x0 = lo + i * cw + 0.006; var x1 = lo + (i + 1) * cw - 0.006
            var z0 = dz; var lift = 0.0
            if (scatter > 0) {
                val push = (if ((x0 + x1) / 2 < ballX) -1 else 1) * scatter * (0.9 + (i % 3) * 0.3)
                x0 += push; x1 += push
                z0 = dz + scatter * 0.6
                lift = sin(min(3.14, scatter * 7)) * height * 1.4
            }
            val z1 = z0 + depth
            val kf = pr.y(z0); val kb = pr.y(z1)
            val sF = (pr.x(x1, z0) - pr.x(x0, z0)) / max(0.0001, x1 - x0); val sB = (pr.x(x1, z1) - pr.x(x0, z1)) / max(0.0001, x1 - x0)
            val hF = height * sF / unit; val hB = height * sB / unit
            val fl = P(pr.x(x0, z0), kf - lift); val fr = P(pr.x(x1, z0), kf - lift)
            val bl = P(pr.x(x0, z1), kb - lift); val br = P(pr.x(x1, z1), kb - lift)
            val ftl = P(fl.x, fl.y - hF); val ftr = P(fr.x, fr.y - hF)
            val btl = P(bl.x, bl.y - hB); val btr = P(br.x, br.y - hB)
            if ((x0 + x1) / 2 < 0.5) fillPath(quad(ftr, btr, br, fr), color.shade(0.32)) else fillPath(quad(ftl, btl, bl, fl), color.shade(0.32))
            fillPath(quad(btl, btr, ftr, ftl), color.lit(0.32))
            drawPath(quad(ftl, ftr, fr, fl), vgrad(listOf(color, color.shade(0.18)), ftl.y, fl.y))
        }
    }
}

/** A paint gate: a glowing strip, two posts and a bar with a swap sign. */
private fun DrawScope.gate(pr: Proj, color: Color, dz: Double, sign: VectorPainter) {
    val u = density.toDouble()
    fillPath(quad(pr.p(LANE_LO, dz + 0.02), pr.p(LANE_HI, dz + 0.02), pr.p(LANE_HI, dz - 0.02), pr.p(LANE_LO, dz - 0.02)), color.op(0.9))
    val k = (pr.x(1.0, dz) - pr.x(0.0, dz)) / max(1.0, pr.x(1.0, 0.0) - pr.x(0.0, 0.0))
    val postH = pr.h * 0.14 * k; val postW = max(3 * u, 8 * u * k)
    val yb = pr.y(dz)
    for (fx in listOf(LANE_LO, LANE_HI)) rrect(pr.x(fx, dz) - postW / 2, yb - postH, postW, postH, postW / 2, color)
    val bx = pr.x(LANE_LO, dz) - postW / 2; val by = yb - postH - postW
    val bw = pr.x(LANE_HI, dz) - pr.x(LANE_LO, dz) + postW; val bh = postW * 1.4
    rrect(bx, by, bw, bh, postW * 0.7, color)
    rrect(bx + postW * 0.6, by + bh * 0.3 - bh * 0.12, bw - postW * 1.2, bh * 0.4, postW * 0.3, Color.White.op(0.45))
    val s = max(10 * u, 26 * u * k)
    val mx = (pr.x(LANE_LO, dz) + pr.x(LANE_HI, dz)) / 2; val my = yb - postH * 0.55
    circle(mx, my, s * 0.8, color)
    icon(sign, mx - s / 2, my - s / 2, s, Color.White)
}

/** The glossy ball with its shadow and white trail. */
private fun DrawScope.ball(cx: Double, cy: Double, r: Double, color: Color) {
    val h = size.height.toDouble()
    drawPath(polyPath(cx - r * 0.55, cy + r * 0.4, cx + r * 0.55, cy + r * 0.4, cx + r * 0.15, h, cx - r * 0.15, h),
        vgrad(listOf(Color.White.op(0.9), Color.White.op(0.0)), cy, h))
    oval(cx - r * 0.9, cy + r * 0.62, r * 1.8, r * 0.55, Color.Black.op(0.22))
    circle(cx, cy, r, radial(listOf(color.lit(0.55), color, color.shade(0.35)), cx - r * 0.35, cy - r * 0.4, r * 1.5))
    oval(cx - r * 0.55, cy - r * 0.62, r * 0.42, r * 0.3, Color.White.op(0.85))
}

/** Progress bar filled in the ball's colour between a start dot and a goal ring. */
private fun DrawScope.progress(f: Double, color: Color, scale: Double) {
    val u = density.toDouble()
    val barW = 190 * scale * u; val dot = 16 * scale * u; val gap = 6 * scale * u; val bh = 10 * scale * u; val lw = 2 * scale * u
    val total = dot * 2 + gap * 2 + barW
    val x0 = size.width / 2.0 - total / 2; val cy = size.height / 2.0
    circle(x0 + dot / 2, cy, dot / 2, color); circleStroke(x0 + dot / 2, cy, dot / 2, Color.White, lw)
    val bx = x0 + dot + gap
    rrect(bx, cy - bh / 2, barW, bh, bh / 2, Color.White.op(0.3))
    val ff = clamp(f, 0.0, 1.0)
    if (ff > 0) rrect(bx, cy - bh / 2, barW * ff, bh, bh / 2, color)
    rrectStroke(bx, cy - bh / 2, barW, bh, bh / 2, Color.White, lw)
    circleStroke(bx + barW + gap + dot / 2, cy, dot / 2, Color.White, lw)
}

/** A vivid backdrop per level (space at 7). */
private fun DrawScope.backdrop(level: Int, stars: Starfield) {
    val pairs = listOf(
        listOf(rgb(0.98, 0.36, 0.62), rgb(0.66, 0.16, 0.62)), listOf(rgb(0.2, 0.78, 0.9), rgb(0.12, 0.42, 0.82)),
        listOf(rgb(1.0, 0.56, 0.24), rgb(0.9, 0.26, 0.22)), listOf(rgb(0.62, 0.42, 0.98), rgb(0.34, 0.18, 0.7)),
        listOf(rgb(0.2, 0.82, 0.62), rgb(0.08, 0.46, 0.5)), listOf(rgb(0.92, 0.22, 0.3), rgb(0.46, 0.06, 0.2)),
        listOf(rgb(0.12, 0.1, 0.3), rgb(0.02, 0.02, 0.08)))
    drawRect(vgrad(pairs[clampI(level, 1, 7) - 1], 0.0, size.height.toDouble()))
    if (level >= 7) withAlpha(0.8) { stars.draw(this, scale = density.toDouble()) }
}

/** The ball bursting into shards (0.6 s ease-out). */
private fun DrawScope.burst(x: Double, y: Double, size: Double, color: Color, t: Double) {
    if (t < 0 || t > 0.6) return
    val k = t / 0.6; val e = 1 - (1 - k) * (1 - k)
    for (i in 0 until 16) {
        val a = i / 16.0 * 2 * PI
        val d = size * (1.3 + 0.5 * (i % 3)) * e
        val s = size * (0.22 + 0.06 * (i % 3))
        translate((x + cos(a) * d).f, (y + sin(a) * d).f) { rotate((i * 40 * e).f, androidx.compose.ui.geometry.Offset.Zero) { rrect(-s / 2, -s / 2, s, s, s * 0.2, color.op(1 - e)) } }
    }
}
