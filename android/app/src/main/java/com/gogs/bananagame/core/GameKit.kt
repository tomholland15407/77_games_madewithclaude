package com.gogs.bananagame.core

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.drawText
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.Density
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.foundation.Canvas
import androidx.compose.runtime.withFrameNanos
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin
import kotlin.random.Random

// ---------------------------------------------------------------------------------------------
// Colour helpers — SwiftUI's Color(red:green:blue:), Color(white:), .opacity(), Color(hue:...).
// ---------------------------------------------------------------------------------------------

fun rgb(r: Double, g: Double, b: Double, a: Double = 1.0) =
    Color(r.toFloat().coerceIn(0f, 1f), g.toFloat().coerceIn(0f, 1f), b.toFloat().coerceIn(0f, 1f), a.toFloat().coerceIn(0f, 1f))

fun gray(w: Double, a: Double = 1.0) = rgb(w, w, w, a)

fun Color.op(a: Double): Color = copy(alpha = (alpha * a.toFloat()).coerceIn(0f, 1f))

/** SwiftUI `Color(hue:saturation:brightness:)` with hue in 0…1. */
fun hsb(h: Double, s: Double, b: Double, a: Double = 1.0): Color {
    var hh = h % 1.0
    if (hh < 0) hh += 1.0
    return Color.hsv((hh * 360).toFloat().coerceIn(0f, 359.999f), s.toFloat().coerceIn(0f, 1f), b.toFloat().coerceIn(0f, 1f), a.toFloat().coerceIn(0f, 1f))
}

fun hex(v: Long, a: Double = 1.0) = Color(((v shr 16) and 0xFF).toInt(), ((v shr 8) and 0xFF).toInt(), (v and 0xFF).toInt(), (a * 255).toInt())

fun lerpColor(a: Color, b: Color, t: Double): Color {
    val k = t.toFloat().coerceIn(0f, 1f)
    return Color(a.red + (b.red - a.red) * k, a.green + (b.green - a.green) * k, a.blue + (b.blue - a.blue) * k, a.alpha + (b.alpha - a.alpha) * k)
}

// ---------------------------------------------------------------------------------------------
// Number / random helpers.
// ---------------------------------------------------------------------------------------------

val Double.f: Float get() = toFloat()
val Int.f: Float get() = toFloat()

fun rnd(a: Double, b: Double): Double = if (b <= a) a else Random.nextDouble(a, b)
fun rnd(range: ClosedFloatingPointRange<Double>) = rnd(range.start, range.endInclusive)
fun rndInt(range: IntRange): Int = if (range.isEmpty()) range.first else Random.nextInt(range.first, range.last + 1)
fun rndBool() = Random.nextBoolean()
fun chance(p: Double) = Random.nextDouble() < p
fun <T> List<T>.pick(): T = this[Random.nextInt(size)]

fun clamp(v: Double, lo: Double, hi: Double) = if (v < lo) lo else if (v > hi) hi else v
fun clampI(v: Int, lo: Int, hi: Int) = if (v < lo) lo else if (v > hi) hi else v
fun lerp(a: Double, b: Double, t: Double) = a + (b - a) * t
fun dist(ax: Double, ay: Double, bx: Double, by: Double) = hypot(ax - bx, ay - by)
fun deg(d: Double) = d * PI / 180.0

/** Monotonic seconds, for wall-clock timers (Date().timeIntervalSince). */
fun nowSec(): Double = System.nanoTime() / 1e9

/** A small value type mirroring CGPoint (Double precision) for game logic. */
data class P(val x: Double, val y: Double) {
    operator fun plus(o: P) = P(x + o.x, y + o.y)
    operator fun minus(o: P) = P(x - o.x, y - o.y)
    operator fun times(k: Double) = P(x * k, y * k)
    val len get() = hypot(x, y)
    fun dist(o: P) = hypot(x - o.x, y - o.y)
    fun o() = Offset(x.toFloat(), y.toFloat())
    companion object { val zero = P(0.0, 0.0) }
}

fun Offset.p() = P(x.toDouble(), y.toDouble())
fun off(x: Double, y: Double) = Offset(x.toFloat(), y.toFloat())
fun sz(w: Double, h: Double) = Size(w.toFloat(), h.toFloat())

// ---------------------------------------------------------------------------------------------
// Frame loop — the TimelineView / side-Task physics loop → withFrameNanos.
// ---------------------------------------------------------------------------------------------

/**
 * Runs [onFrame] every display frame with the real dt in seconds (clamped to [maxDt]) while
 * [running] is true. Returns a frame counter state that a Canvas can read to redraw.
 */
@Composable
fun rememberFrameLoop(running: Boolean = true, maxDt: Double = 0.05, key: Any? = Unit, onFrame: (dt: Double) -> Unit = {}): State<Long> {
    val tick = remember { mutableLongStateOf(0L) }
    val cb = rememberUpdatedState(onFrame)
    LaunchedEffect(running, key) {
        if (!running) return@LaunchedEffect
        var last = -1L
        while (isActive) {
            withFrameNanos { t ->
                if (last >= 0) {
                    val dt = ((t - last) / 1e9).coerceIn(0.0, maxDt)
                    cb.value(dt)
                }
                last = t
                tick.longValue = tick.longValue + 1
            }
        }
    }
    return tick
}

// ---------------------------------------------------------------------------------------------
// UI bits shared by games.
// ---------------------------------------------------------------------------------------------

/** The standard countdown time bar (capsule, banana → red under 30%). */
@Composable
fun TimeBar(fraction: Double, modifier: Modifier = Modifier, fill: Color? = null, track: Color = Color.White.op(0.15)) {
    val f = fraction.coerceIn(0.0, 1.0)
    Box(modifier.background(track, RoundedCornerShape(50))) {
        Box(
            Modifier.fillMaxHeight().fillMaxWidth(f.toFloat())
                .background(fill ?: if (f < 0.3) Color.Red else BananaTheme.banana, RoundedCornerShape(50))
        )
    }
}

/** SwiftUI's `.rounded` system design has no Android twin; the default sans is used everywhere. */
val Rounded: FontFamily = FontFamily.Default
val Mono: FontFamily = FontFamily.Monospace

fun ts(size: Double, weight: FontWeight = FontWeight.Normal, color: Color = Color.White, family: FontFamily = Rounded, spacing: Double = 0.0) =
    TextStyle(fontSize = size.sp, fontWeight = weight, color = color, fontFamily = family, letterSpacing = spacing.sp)

/**
 * Draws text centred at (x, y) in canvas pixels. `size` is in canvas pixels too (games size their
 * text from the play area, so this avoids sp→px conversions in drawing code).
 */
fun DrawScope.text(
    tm: TextMeasurer, s: String, x: Double, y: Double, size: Double, color: Color,
    weight: FontWeight = FontWeight.Bold, family: FontFamily = Rounded, anchorX: Double = 0.5, anchorY: Double = 0.5,
    spacing: Double = 0.0,
) {
    if (s.isEmpty() || size <= 0.5) return
    val style = TextStyle(fontSize = (size / density / fontScale).sp, fontWeight = weight, color = color, fontFamily = family,
        letterSpacing = (spacing / density / fontScale).sp)
    val layout = tm.measure(s, style, softWrap = false, maxLines = 1)
    drawText(layout, topLeft = Offset((x - layout.size.width * anchorX).toFloat(), (y - layout.size.height * anchorY).toFloat()))
}

/** Measures text width in canvas pixels for the given pixel size. */
fun DrawScope.textWidth(tm: TextMeasurer, s: String, size: Double, weight: FontWeight = FontWeight.Bold, family: FontFamily = Rounded): Double {
    val style = TextStyle(fontSize = (size / density / fontScale).sp, fontWeight = weight, fontFamily = family)
    return tm.measure(s, style, softWrap = false, maxLines = 1).size.width.toDouble()
}

// Shape helpers in Double coordinates.
fun DrawScope.rect(x: Double, y: Double, w: Double, h: Double, c: Color) =
    drawRect(c, Offset(x.f, y.f), Size(w.f, h.f))

fun DrawScope.rect(x: Double, y: Double, w: Double, h: Double, brush: Brush) =
    drawRect(brush, Offset(x.f, y.f), Size(w.f, h.f))

fun DrawScope.rrect(x: Double, y: Double, w: Double, h: Double, r: Double, c: Color) =
    drawRoundRect(c, Offset(x.f, y.f), Size(w.f, h.f), CornerRadius(r.f, r.f))

fun DrawScope.rrect(x: Double, y: Double, w: Double, h: Double, r: Double, brush: Brush) =
    drawRoundRect(brush, Offset(x.f, y.f), Size(w.f, h.f), CornerRadius(r.f, r.f))

fun DrawScope.rrectStroke(x: Double, y: Double, w: Double, h: Double, r: Double, c: Color, lw: Double) =
    drawRoundRect(c, Offset(x.f, y.f), Size(w.f, h.f), CornerRadius(r.f, r.f), style = Stroke(lw.f))

fun DrawScope.rectStroke(x: Double, y: Double, w: Double, h: Double, c: Color, lw: Double) =
    drawRect(c, Offset(x.f, y.f), Size(w.f, h.f), style = Stroke(lw.f))

fun DrawScope.circle(cx: Double, cy: Double, r: Double, c: Color) = drawCircle(c, r.f, Offset(cx.f, cy.f))
fun DrawScope.circle(cx: Double, cy: Double, r: Double, brush: Brush) = drawCircle(brush, r.f, Offset(cx.f, cy.f))
fun DrawScope.circleStroke(cx: Double, cy: Double, r: Double, c: Color, lw: Double) =
    drawCircle(c, r.f, Offset(cx.f, cy.f), style = Stroke(lw.f))

fun DrawScope.ellipse(cx: Double, cy: Double, rx: Double, ry: Double, c: Color) =
    drawOval(c, Offset((cx - rx).f, (cy - ry).f), Size((rx * 2).f, (ry * 2).f))

fun DrawScope.ellipse(cx: Double, cy: Double, rx: Double, ry: Double, brush: Brush) =
    drawOval(brush, Offset((cx - rx).f, (cy - ry).f), Size((rx * 2).f, (ry * 2).f))

fun DrawScope.ellipseStroke(cx: Double, cy: Double, rx: Double, ry: Double, c: Color, lw: Double) =
    drawOval(c, Offset((cx - rx).f, (cy - ry).f), Size((rx * 2).f, (ry * 2).f), style = Stroke(lw.f))

/** Oval in a rect (SwiftUI `Ellipse().path(in: rect)`). */
fun DrawScope.oval(x: Double, y: Double, w: Double, h: Double, c: Color) = drawOval(c, Offset(x.f, y.f), Size(w.f, h.f))

fun DrawScope.line(x1: Double, y1: Double, x2: Double, y2: Double, c: Color, lw: Double, cap: StrokeCap = StrokeCap.Round) =
    drawLine(c, Offset(x1.f, y1.f), Offset(x2.f, y2.f), lw.f, cap)

fun DrawScope.strokePath(p: Path, c: Color, lw: Double, cap: StrokeCap = StrokeCap.Round, join: StrokeJoin = StrokeJoin.Round) =
    drawPath(p, c, style = Stroke(lw.f, cap = cap, join = join))

fun DrawScope.fillPath(p: Path, c: Color) = drawPath(p, c)

inline fun DrawScope.at(x: Double, y: Double, block: DrawScope.() -> Unit) = translate(x.f, y.f, block)
inline fun DrawScope.rot(degrees: Double, px: Double, py: Double, block: DrawScope.() -> Unit) =
    rotate(degrees.f, Offset(px.f, py.f), block)

// Path builders in Double coordinates.
fun Path.m(x: Double, y: Double) = moveTo(x.f, y.f)
fun Path.l(x: Double, y: Double) = lineTo(x.f, y.f)
fun Path.q(cx: Double, cy: Double, x: Double, y: Double) = quadraticTo(cx.f, cy.f, x.f, y.f)
fun Path.c(c1x: Double, c1y: Double, c2x: Double, c2y: Double, x: Double, y: Double) = cubicTo(c1x.f, c1y.f, c2x.f, c2y.f, x.f, y.f)

/** Adds an arc like SwiftUI `addArc(center:radius:startAngle:endAngle:clockwise:)` (angles in radians, y-down). */
fun Path.arc(cx: Double, cy: Double, r: Double, start: Double, end: Double, clockwise: Boolean = false, moveFirst: Boolean = false) {
    // SwiftUI's "clockwise" flag is in flipped (y-up) terms: clockwise=false sweeps with increasing angle on screen.
    var sweep = end - start
    if (!clockwise) { while (sweep < 0) sweep += 2 * PI } else { while (sweep > 0) sweep -= 2 * PI }
    val rect = Rect((cx - r).f, (cy - r).f, (cx + r).f, (cy + r).f)
    val startDeg = (start * 180 / PI).f
    val sweepDeg = (sweep * 180 / PI).f
    if (moveFirst) moveTo((cx + r * cos(start)).f, (cy + r * sin(start)).f)
    if (kotlin.math.abs(sweepDeg) >= 359.99f) {
        arcTo(rect, startDeg, if (sweepDeg > 0) 180f else -180f, false)
        arcTo(rect, startDeg + if (sweepDeg > 0) 180f else -180f, if (sweepDeg > 0) 179.99f else -179.99f, false)
    } else arcTo(rect, startDeg, sweepDeg, false)
}

fun polyPath(vararg pts: Double, close: Boolean = true): Path {
    val p = Path()
    var i = 0
    while (i + 1 < pts.size) {
        if (i == 0) p.m(pts[0], pts[1]) else p.l(pts[i], pts[i + 1])
        i += 2
    }
    if (close) p.close()
    return p
}

fun polyPath(pts: List<P>, close: Boolean = true): Path {
    val p = Path()
    pts.forEachIndexed { i, q -> if (i == 0) p.m(q.x, q.y) else p.l(q.x, q.y) }
    if (close) p.close()
    return p
}

fun angleOf(dx: Double, dy: Double) = atan2(dy, dx)

/** A simple linear gradient between two points (Double coords). */
fun lin(colors: List<Color>, x0: Double, y0: Double, x1: Double, y1: Double) =
    Brush.linearGradient(colors, Offset(x0.f, y0.f), Offset(x1.f, y1.f))

fun vgrad(colors: List<Color>, top: Double, bottom: Double) =
    Brush.verticalGradient(colors, top.f, bottom.f)

fun hgrad(colors: List<Color>, left: Double, right: Double) =
    Brush.horizontalGradient(colors, left.f, right.f)

fun radial(colors: List<Color>, cx: Double, cy: Double, r: Double) =
    Brush.radialGradient(colors, Offset(cx.f, cy.f), r.toFloat().coerceAtLeast(0.01f))

/** Fill the rest of a game page and measure it (SwiftUI GeometryReader). */
@Composable
fun GameBox(modifier: Modifier = Modifier, content: @Composable (w: Double, h: Double) -> Unit) {
    BoxWithConstraints(modifier.fillMaxSize()) {
        val d = LocalDensity.current
        val w = with(d) { maxWidth.toPx() }.toDouble()
        val h = with(d) { maxHeight.toPx() }.toDouble()
        content(w, h)
    }
}

/** px → dp in a composable. */
@Composable
fun Double.pxToDp(): Dp = with(LocalDensity.current) { this@pxToDp.toFloat().toDp() }

@Composable
fun Double.pxToSp(): TextUnit = with(LocalDensity.current) { this@pxToSp.toFloat().toSp() }
