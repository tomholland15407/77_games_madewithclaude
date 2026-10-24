package com.gogs.bananagame.games.spotthedifference

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BugReport
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.Eco
import androidx.compose.material.icons.filled.EmojiNature
import androidx.compose.material.icons.filled.Landscape
import androidx.compose.material.icons.filled.Park
import androidx.compose.material.icons.filled.Pets
import androidx.compose.material.icons.filled.SetMeal
import androidx.compose.material.icons.filled.Spa
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.vector.VectorPainter
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

/**
 * Brain — Spot the Difference (iOS SpotDifferenceGame.swift): two stacked pictures are identical
 * except one item (colour, size, symbol, position, or missing). Tap it before the clock runs out.
 */
object SpotTheDifferenceGame {
    val definition = GameDefinition(
        id = "spot-difference",
        title = "Spot the Difference",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Two stacked scenes are identical except for one detail.",
                "The difference may be a changed color, size, symbol, position, or a missing item.",
                "Tap the differing spot in either scene before the clock runs out.",
                "A wrong tap or a timeout sends you back to level 1.",
            ),
            bulletsVI = listOf(
                "Hai cảnh xếp chồng giống hệt nhau, chỉ khác đúng một chi tiết.",
                "Điểm khác có thể là màu, kích thước, biểu tượng, vị trí, hoặc một vật bị thiếu.",
                "Chạm vào điểm khác biệt ở một trong hai cảnh trước khi hết giờ.",
                "Chạm sai hoặc hết giờ sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> SpotTheDifferenceView(level, onWin, onFail) }
    )
}

/** SF Symbols → Material icons: tree, cloud, sun, leaf, bird (→ bee), mountains, ant (→ bug), tortoise (→ lotus), fish, paw. */
private const val SYMBOLS = 10
private val palette = listOf(SysColor.green, SysColor.mint, SysColor.teal, SysColor.yellow, SysColor.orange, Color.White, SysColor.cyan)

private data class SceneItem(val symbol: Int, val pos: P, val size: Double, val color: Color, val hidden: Boolean = false)

@Composable
private fun SpotTheDifferenceView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val itemCount = 6 + level * 2
    val timeLimit = max(6.0, 15.0 - level * 1.3)
    val tolFrac = max(0.06, 0.15 - level * 0.012)
    var playing by remember { mutableStateOf(true) }
    var base by remember { mutableStateOf(listOf<SceneItem>()) }
    var changed by remember { mutableStateOf(SceneItem(3, P.zero, 0.1, SysColor.green)) }
    var diffIndex by remember { mutableIntStateOf(0) }
    var timeLeft by remember { mutableDoubleStateOf(timeLimit) }
    var demoCrosshair by remember { mutableStateOf(false) }
    var demoRing by remember { mutableStateOf(false) }
    var circled by remember { mutableStateOf(false) }
    var missAt by remember { mutableStateOf<P?>(null) }
    val icons = listOf(Icons.Filled.Park, Icons.Filled.Cloud, Icons.Filled.WbSunny, Icons.Filled.Eco, Icons.Filled.EmojiNature,
        Icons.Filled.Landscape, Icons.Filled.BugReport, Icons.Filled.Spa, Icons.Filled.SetMeal, Icons.Filled.Pets).map { rememberVectorPainter(it) }
    val check = rememberVectorPainter(Icons.Filled.Check)
    val handP = rememberHand()
    val ringAnim by animateFloatAsState(if (circled || (isDemo && demoRing)) 1f else 0f, spring(dampingRatio = 0.7f), label = "ring")
    val fingerAnim by animateFloatAsState(if (demoCrosshair) 1f else 0f, spring(dampingRatio = 0.7f), label = "finger")

    fun mutate(item: SceneItem): SceneItem {
        val strong = level <= 3
        return when (Random.nextInt(5)) {
            0 -> item.copy(color = palette.filter { it != item.color }.pick())
            1 -> {
                val f = if (strong) (if (rndBool()) 1.6 else 0.6) else (if (rndBool()) 1.22 else 0.82)
                item.copy(size = max(0.05, item.size * f))
            }
            2 -> item.copy(symbol = (0 until SYMBOLS).filter { it != item.symbol }.pick())
            3 -> item.copy(hidden = true)
            else -> {
                val d = if (strong) 0.14 else 0.07
                item.copy(pos = P(clamp(item.pos.x + rnd(-d, d), 0.08, 0.92), clamp(item.pos.y + rnd(-d, d), 0.12, 0.9)))
            }
        }
    }

    fun buildScene() {
        // A jittered grid keeps a big count spread out without collapsing into one clump.
        val cols = max(3, ceil(sqrt(itemCount * 1.5)).toInt())
        val rows = ceil(itemCount.toDouble() / cols).toInt()
        val cells = (0 until rows).flatMap { r -> (0 until cols).map { c -> c to r } }.shuffled()
        base = List(itemCount) { i ->
            val (c, r) = cells[i]
            val cx = (c + 0.5) / cols; val cy = (r + 0.5) / rows
            val p = P(clamp(cx + rnd(-0.35, 0.35) / cols, 0.07, 0.93), clamp(cy + rnd(-0.35, 0.35) / rows, 0.12, 0.9))
            SceneItem(Random.nextInt(SYMBOLS), p, rnd(0.07, 0.12), palette.pick())
        }
        diffIndex = Random.nextInt(base.size)
        changed = mutate(base[diffIndex])
    }

    fun demoScene() {
        val cols8 = listOf(SysColor.green, Color.White, SysColor.yellow, SysColor.mint, SysColor.cyan, SysColor.teal, SysColor.orange, SysColor.green)
        val syms = listOf(0, 1, 2, 3, 4, 5, 8, 9)
        base = List(8) { i -> SceneItem(syms[i], P((i % 4 + 0.5) / 4, (i / 4 + 0.5) / 2), 0.11, cols8[i]) }
        diffIndex = 5
        changed = base[5].copy(color = SysColor.orange)
    }

    fun win() { if (!playing) return; playing = false; Haptics.tap(); SoundManager.tap(); onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }

    LaunchedEffect(Unit) {
        if (isDemo) {
            demoScene(); playing = true; timeLeft = timeLimit
            while (isActive) {
                demoCrosshair = false; demoRing = false
                delay(700); demoCrosshair = true
                delay(850); demoRing = true
                delay(1300); demoCrosshair = false; demoRing = false
                delay(350)
            }
        } else {
            buildScene(); playing = true; timeLeft = timeLimit
            val start = nowSec()
            while (isActive && playing) {
                delay(50)
                timeLeft = max(0.0, timeLimit - (nowSec() - start))
                if (timeLeft <= 0) { fail(); break }
            }
        }
    }

    GameBox(Modifier.padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))) { w, h ->
        val topR = doubleArrayOf(w * 0.06, h * 0.14, w * 0.88, h * 0.36)
        val botR = doubleArrayOf(w * 0.06, h * 0.54, w * 0.88, h * 0.36)
        fun spot(r: DoubleArray, it: SceneItem) = P(r[0] + it.pos.x * r[2], r[1] + it.pos.y * r[3])
        Canvas(Modifier.fillMaxSize().then(if (isDemo) Modifier else Modifier.tapAt(base) { loc ->
            if (!playing || diffIndex >= base.size) return@tapAt
            val tol = tolFrac * topR[2]
            val a = spot(topR, base[diffIndex]); val b = spot(botR, changed)
            if (loc.dist(a) < tol || loc.dist(b) < tol) { circled = true; win() } else { missAt = loc; fail() }
        })) {
            val u = density.toDouble()
            puzzlePage()
            // The pencil clock and the found-it badge.
            val barY = h * 0.06; val pad = 30 * u; val badge = 24 * u
            at(pad, barY - 8 * u) { pencil(w - 2 * pad - badge - 12 * u, 16 * u, if (timeLimit > 0) timeLeft / timeLimit else 0.0) }
            foundBadge(w - pad - badge / 2, barY, badge / 2, circled || (isDemo && demoRing), check)
            val sceneB = base.toMutableList().also { if (diffIndex < it.size) it[diffIndex] = changed }
            picture(topR, base, icons)
            picture(botR, sceneB, icons)
            if (diffIndex < base.size && ringAnim > 0.01) {
                val ring = topR[2] * (tolFrac + 0.03) * 2
                val sc = 0.4 + 0.6 * ringAnim
                for (p in listOf(spot(topR, base[diffIndex]), spot(botR, changed))) withAlpha(ringAnim.toDouble().coerceIn(0.0, 1.0)) {
                    markerRing(p.x, p.y, ring * sc, ring * 0.9 * sc)
                }
            }
            missAt?.let { markerCross(it.x, it.y, topR[2] * 0.12) }
            if (isDemo && diffIndex < base.size && fingerAnim > 0.01) {
                val a = spot(topR, base[diffIndex])
                val s = 34 * u * (0.5 + 0.5 * fingerAnim)
                withAlpha(fingerAnim.toDouble().coerceIn(0.0, 1.0)) { hand(handP, a.x + topR[2] * 0.06 - s * 0.35, a.y + topR[3] * 0.12 - s * 0.2, s) }
            }
        }
    }
}

private fun hash(n: Double): Double { val v = sin(n * 12.9898) * 43758.5453; return v - kotlin.math.floor(v) }

/** One framed picture: a painted sky-and-meadow with every item as an ink-outlined sticker. */
private fun DrawScope.picture(r: DoubleArray, items: List<SceneItem>, icons: List<VectorPainter>) {
    val u = density.toDouble()
    val (x, y, w, h) = listOf(r[0], r[1], r[2], r[3])
    blurRRect(x - 3 * u, y - 3 * u + 3 * u, w + 6 * u, h + 6 * u, 16 * u, Color.Black.op(0.25), 6 * u)
    rrect(x - 3 * u, y - 3 * u, w + 6 * u, h + 6 * u, 16 * u, Color.White)
    val frame = Path().apply { addRoundRect(androidx.compose.ui.geometry.RoundRect(x.f, y.f, (x + w).f, (y + h).f, (14 * u).f, (14 * u).f)) }
    val ink = rgb(0.16, 0.13, 0.2)
    clipPath(frame) {
        scenery(x, y, w, h)
        for (item in items) {
            if (item.hidden) continue
            val s = w * item.size
            val bx = x + item.pos.x * w - s / 2; val by = y + item.pos.y * h - s / 2
            val p = icons[item.symbol]
            icon(p, bx + 1.5 * u, by + 2.5 * u, s, Color.Black.op(0.22))
            val o = max(1.2 * u, s * 0.045)
            for ((dx, dy) in listOf(-o to 0.0, o to 0.0, 0.0 to -o, 0.0 to o, -o * 0.7 to -o * 0.7, o * 0.7 to -o * 0.7, -o * 0.7 to o * 0.7, o * 0.7 to o * 0.7))
                icon(p, bx + dx, by + dy, s, ink)
            icon(p, bx, by, s, item.color)
        }
    }
    rrectStroke(x, y, w, h, 14 * u, Color.White, 6 * u)
    rrectStroke(x - 3 * u, y - 3 * u, w + 6 * u, h + 6 * u, 16 * u, Color.Black.op(0.12), u)
}

/** Light sky, two rows of soft hills and a meadow — the same painting in both pictures. */
private fun DrawScope.scenery(x: Double, y: Double, w: Double, h: Double) {
    val u = density.toDouble()
    rect(x, y, w, h, vgrad(listOf(rgb(0.62, 0.84, 0.98), rgb(0.88, 0.95, 1.0)), y, y + h * 0.55))
    fun hills(fy: Double, amp: Double, phase: Double, color: Color) {
        val p = Path(); p.m(x, y + h)
        for (k in 0..24) p.l(x + w * k / 24, y + h * fy - amp * h * sin(k / 24.0 * PI * 2.2 + phase))
        p.l(x + w, y + h); p.close()
        fillPath(p, color)
    }
    hills(0.5, 0.06, 0.4, rgb(0.62, 0.82, 0.62))
    hills(0.62, 0.05, 2.1, rgb(0.55, 0.78, 0.45))
    rect(x, y + h * 0.7, w, h * 0.3, vgrad(listOf(rgb(0.55, 0.78, 0.42), rgb(0.47, 0.7, 0.36)), y + h * 0.7, y + h))
    val grass = Path()
    for (k in 0 until 60) {
        val gx = x + hash(k * 1.9) * w; val gy = y + h * (0.66 + hash(k * 3.7) * 0.32)
        grass.m(gx, gy); grass.l(gx - 1.5 * u, gy - 4 * u)
        grass.m(gx + 2 * u, gy); grass.l(gx + 3 * u, gy - 5 * u)
    }
    strokePath(grass, rgb(0.33, 0.55, 0.25, 0.5), u, StrokeCap.Butt)
}

/** Warm paper with a polka-dot print behind the pictures. */
private fun DrawScope.puzzlePage() {
    val u = density.toDouble()
    val W = size.width.toDouble(); val H = size.height.toDouble()
    rect(0.0, 0.0, W, H, vgrad(listOf(rgb(1.0, 0.84, 0.5), rgb(1.0, 0.7, 0.42)), 0.0, H))
    val dots = Path()
    var y = 8 * u; var row = 0
    while (y < H) {
        var x = if (row % 2 == 0) 8 * u else 22 * u
        while (x < W) { dots.addOval(androidx.compose.ui.geometry.Rect((x - 3 * u).f, (y - 3 * u).f, (x + 3 * u).f, (y + 3 * u).f)); x += 28 * u }
        y += 24 * u; row++
    }
    fillPath(dots, Color.White.op(0.28))
}

/** The clock as a pencil: sharpened away from the tip end as time runs out. */
private fun DrawScope.pencil(width: Double, h: Double, frac: Double) {
    val u = density.toDouble()
    val midY = h / 2
    val eraser = h * 1.1; val ferrule = h * 0.7; val tipLen = h * 1.3
    val bodyLen = max(0.0, (width - eraser - ferrule - tipLen) * clamp(frac, 0.0, 1.0))
    val low = frac < 0.3
    rrect(0.0, u, eraser + 3 * u, h - 2 * u, h * 0.35, rgb(0.96, 0.56, 0.62))
    rect(eraser, 0.0, ferrule, h, vgrad(listOf(gray(0.92), gray(0.62)), 0.0, h))
    for (k in 1..2) { val bx = eraser + ferrule * k / 3; line(bx, 0.0, bx, h, gray(0.45), u, StrokeCap.Butt) }
    val bx = eraser + ferrule
    val paint = if (low) rgb(0.95, 0.3, 0.25) else rgb(1.0, 0.8, 0.2)
    rect(bx, 0.0, bodyLen, h, vgrad(listOf(paint.lit(0.25), paint, paint.shade(0.2)), 0.0, h))
    line(bx, midY, bx + bodyLen, midY, paint.shade(0.25).op(0.6), u, StrokeCap.Butt)
    val tx = bx + bodyLen
    fillPath(polyPath(tx, 0.0, tx + tipLen, midY, tx, h), rgb(0.93, 0.78, 0.56))
    fillPath(polyPath(tx + tipLen * 0.62, midY - h * 0.19, tx + tipLen, midY, tx + tipLen * 0.62, midY + h * 0.19), gray(0.2))
}

private fun DrawScope.foundBadge(cx: Double, cy: Double, r: Double, found: Boolean, check: VectorPainter) {
    val u = density.toDouble()
    circle(cx, cy, r, if (found) rgb(0.2, 0.72, 0.3) else Color.White.op(0.85))
    circleStroke(cx, cy, r - u, if (found) rgb(0.1, 0.45, 0.16) else rgb(0.7, 0.5, 0.3), 2 * u)
    if (found) icon(check, cx - r * 0.7, cy - r * 0.7, r * 1.4, Color.White)
}

/** A hand-drawn red marker circle (two slightly different loops). */
private fun DrawScope.markerRing(cx: Double, cy: Double, w: Double, h: Double) {
    val u = density.toDouble()
    val rw = w - 6 * u; val rh = h - 6 * u
    val red = rgb(0.9, 0.1, 0.12)
    ellipseStroke(cx, cy, rw / 2, rh / 2, red, 3 * u)
    ellipseStroke(cx + 1.5 * u, cy + u, rw / 2 - 1.5 * u, rh / 2 + u, red, 3 * u)
}

/** A red marker ✕ where a wrong tap landed. */
private fun DrawScope.markerCross(cx: Double, cy: Double, s: Double) {
    val u = density.toDouble()
    val k = s / 2 - 3 * u
    val x = Path(); x.m(cx - k, cy - k); x.l(cx + k, cy + k); x.m(cx + k, cy - k); x.l(cx - k, cy + k)
    strokePath(x, Color.White, 7 * u)
    strokePath(x, rgb(0.9, 0.1, 0.12), 4 * u)
}
