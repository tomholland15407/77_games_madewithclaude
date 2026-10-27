package com.gogs.bananagame.games.memory

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/** Brain — Banana Memory (iOS MemoryGame.swift): a 1978 Simon. Watch the pads, repeat the sequence. */
object MemoryGame {
    val definition = GameDefinition(
        id = "banana-memory",
        title = "Banana Memory",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Watch the four pads flash a sequence.",
                "Tap them back in the exact same order.",
                "One wrong pad sends you back to level 1.",
            ),
            bulletsVI = listOf(
                "Xem bốn nút nhấp nháy theo một chuỗi.",
                "Chạm lại chúng theo đúng thứ tự.",
                "Một nút sai sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> MemoryView(level, onWin, onFail) }
    )
}

private val BACK_TOP = rgb(0.2, 0.21, 0.27)
private val BACK_BOTTOM = rgb(0.04, 0.04, 0.07)

@Composable
private fun MemoryView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val length = 2 + level
    val flashOn = max(0.28, 0.62 - level * 0.05)
    var sequence by remember { mutableStateOf(listOf<Int>()) }
    var inputIndex by remember { mutableIntStateOf(0) }
    var activePad by remember { mutableStateOf<Int?>(null) }
    var isPlayingBack by remember { mutableStateOf(true) }
    var done by remember { mutableStateOf(false) }
    var pressedPad by remember { mutableStateOf<Int?>(null) }
    var demoFinger by remember { mutableStateOf<Int?>(null) }
    val scope = rememberCoroutineScope()
    val tm = rememberTextMeasurer()
    val handP = rememberHand()

    suspend fun playback() {
        delay(600)
        for (pad in sequence) {
            if (done) return
            activePad = pad
            SoundManager.padTone(pad)
            delay((flashOn * 1000).toLong())
            activePad = null
            delay(180)
        }
        isPlayingBack = false
    }

    fun tapPad(index: Int) {
        if (isPlayingBack || done) return
        Haptics.tap()
        SoundManager.padTone(index)
        if (index == sequence[inputIndex]) {
            inputIndex += 1
            if (inputIndex >= sequence.size) { done = true; onWin() }
        } else {
            done = true; SoundManager.error(); onFail()
        }
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            val demoSeq = listOf(0, 3, 2)
            while (isActive) {
                done = false; inputIndex = 0; isPlayingBack = true
                sequence = demoSeq
                playback()
                delay(400)
                for (pad in demoSeq) {
                    demoFinger = pad; delay(160)
                    activePad = pad; inputIndex += 1; delay(280)
                    activePad = null; delay(160)
                }
                demoFinger = null
                delay(1000)
            }
        } else {
            done = false; inputIndex = 0; isPlayingBack = true
            sequence = List(length) { rndInt(0..3) }
            playback()
        }
    }

    Box(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp)
            .clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .background(Brush.radialGradient(listOf(BACK_TOP, BACK_BOTTOM)))
    ) {
        Column(
            Modifier.fillMaxSize().padding(vertical = if (isDemo) 8.dp else 20.dp, horizontal = if (isDemo) 8.dp else 14.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(if (isDemo) 4.dp else 16.dp)
        ) {
            val label = if (isDemo) (if (isPlayingBack) L("MEMORY", "GHI NHỚ") else L("REPEAT", "LẶP LẠI"))
            else (if (isPlayingBack) L("Watch…", "Xem…") else L("Your turn", "Đến lượt bạn"))
            Text(label, style = ts(if (isDemo) 19.0 else 24.0, FontWeight.Black, if (isPlayingBack) Color.White.op(0.55) else BananaTheme.banana))
            BoxWithConstraints(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                val d = min(maxWidth.value, maxHeight.value).dp
                Canvas(
                    Modifier.size(d).pointerInput(Unit) {
                        detectTapGestures { pos ->
                            if (isDemo) return@detectTapGestures
                            val q = SimonArt.quadrant(pos.x.toDouble(), pos.y.toDouble(), size.width.toDouble()) ?: return@detectTapGestures
                            if (!isPlayingBack && !done) {
                                pressedPad = q
                                scope.launch { delay(200); if (pressedPad == q) pressedPad = null }
                            }
                            tapPad(q)
                        }
                    }
                ) {
                    SimonArt.draw(this, tm, activePad ?: pressedPad, isPlayingBack, min(inputIndex, sequence.size), sequence.size,
                        if (isDemo) demoFinger else null, handP)
                }
            }
        }
    }
}

/** The 1978 Simon: black round body, four coloured quadrant pads, brushed-silver hub. Pads: 0 TL, 1 TR, 2 BL, 3 BR. */
private object SimonArt {
    val pad = listOf(rgb(0.0, 0.55, 0.24), rgb(0.74, 0.07, 0.1), rgb(0.86, 0.7, 0.04), rgb(0.05, 0.32, 0.76))
    val glow = listOf(rgb(0.4, 1.0, 0.5), rgb(1.0, 0.4, 0.34), rgb(1.0, 0.96, 0.42), rgb(0.45, 0.78, 1.0))

    class Geo(val cx: Double, val cy: Double, val R: Double) {
        val rIn get() = R * 0.41
        val rOut get() = R * 0.9
        val gap get() = R * 0.04
        val hub get() = R * 0.34
    }

    fun geo(side: Double) = Geo(side / 2, side / 2, side / 2 * 0.94)

    fun quadrant(x: Double, y: Double, side: Double): Int? {
        val g = geo(side)
        val dx = x - g.cx; val dy = y - g.cy
        val d = hypot(dx, dy)
        if (d <= g.rIn * 0.92 || d >= g.R * 1.02) return null
        return (if (dy < 0) 0 else 2) + (if (dx < 0) 0 else 1)
    }

    fun sector(q: Int, g: Geo, r0: Double, r1: Double, h: Double): Path {
        val sx = if (q % 2 == 0) -1.0 else 1.0
        val sy = if (q < 2) -1.0 else 1.0
        val o = sqrt(max(0.0, r1 * r1 - h * h)); val i = sqrt(max(0.0, r0 * r0 - h * h))
        val p = Path()
        fun arc(r: Double, a0: Double, a1: Double) {
            for (k in 1..28) {
                val a = a0 + (a1 - a0) * k / 28
                p.l(g.cx + r * cos(a), g.cy + r * sin(a))
            }
        }
        p.m(g.cx + sx * i, g.cy + sy * h)
        p.l(g.cx + sx * o, g.cy + sy * h)
        arc(r1, atan2(sy * h, sx * o), atan2(sy * o, sx * h))
        p.l(g.cx + sx * h, g.cy + sy * i)
        arc(r0, atan2(sy * i, sx * h), atan2(sy * h, sx * i))
        p.close()
        return p
    }

    fun draw(d: DrawScope, tm: TextMeasurer, lit: Int?, watching: Boolean, count: Int, total: Int, finger: Int?, handP: VectorIcon) = with(d) {
        val side = min(size.width, size.height).toDouble()
        if (side <= 20) return@with
        val g = geo(side)
        val R = g.R; val cx = g.cx; val cy = g.cy

        blurOval(cx - R * 0.97, cy - R * 0.9, R * 1.94, R * 1.94, Color.Black.op(0.7), R * 0.06)
        circle(cx, cy, R, radial(listOf(gray(0.17), gray(0.08), gray(0.03)), cx - R * 0.3, cy - R * 0.35, R * 1.4))
        drawCircle(vgrad(listOf(Color.White.op(0.28), Color.White.op(0.02), Color.Black.op(0.4)), cy - R, cy + R),
            (R * 0.975).f, off(cx, cy), style = Stroke((R * 0.035).f))

        if (lit != null) blurPath(sector(lit, g, g.rIn * 0.9, g.rOut * 1.06, 0.0), glow[lit].op(0.75), R * 0.09)

        val k = R * 0.03
        for (q in 0 until 4) {
            val on = lit == q
            val path = sector(q, g, g.rIn + k, g.rOut - k, g.gap + k)
            val mx = cx + (if (q % 2 == 0) -1 else 1) * R * 0.46
            val my = cy + (if (q < 2) -1 else 1) * R * 0.46
            val shading = if (on) radial(listOf(Color.White, glow[q], glow[q].mix(pad[q], 0.35)), mx, my, R * 0.62)
            else radial(listOf(pad[q].lit(0.22), pad[q], pad[q].shade(0.35)), mx - R * 0.12, my - R * 0.14, R * 0.7)
            drawPath(path, shading)
            drawPath(path, shading, style = Stroke((k * 2).f, join = StrokeJoin.Round))
            val emboss = sector(q, g, g.rIn + (g.rOut - g.rIn) * 0.34, g.rOut - (g.rOut - g.rIn) * 0.26, g.gap + (g.rOut - g.rIn) * 0.3)
            drawPath(emboss, (if (on) Color.White else pad[q].lit(0.35)).op(if (on) 0.55 else 0.4), style = Stroke(max(1.0, R * 0.012).f, join = StrokeJoin.Round))
            translate((R * 0.008).f, (R * 0.012).f) {
                drawPath(emboss, Color.Black.op(if (on) 0.08 else 0.22), style = Stroke(max(1.0, R * 0.01).f, join = StrokeJoin.Round))
            }
        }

        val hr = g.hub
        rotate(-20f, off(cx, cy)) {
            circle(cx, cy, hr, Brush.sweepGradient(listOf(gray(0.9), gray(0.66), gray(0.95), gray(0.6), gray(0.9), gray(0.7), gray(0.9)), off(cx, cy)))
        }
        var i = 0.2
        while (i < 1.0) { circleStroke(cx, cy, hr * i, Color.White.op(0.12), 0.6); i += 0.07 }
        circleStroke(cx, cy, hr, gray(0.3), max(1.0, R * 0.012))
        drawCircle(vgrad(listOf(Color.White.op(0.7), Color.Black.op(0.25)), cy - hr, cy + hr), (hr * 0.96).f, off(cx, cy), style = Stroke(max(1.0, R * 0.01).f))

        for (sx in listOf(-1.0, 1.0)) {
            val slx = cx + sx * hr * 0.5 - hr * 0.16; val sly = cy - hr * 0.58; val slw = hr * 0.32; val slh = hr * 0.13
            rrect(slx, sly, slw, slh, hr * 0.05, gray(0.22))
            val kx = slx + (if (sx < 0) 0.0 else slw * 0.45); val ky = sly - hr * 0.03
            val kw = slw * 0.55; val kh = slh + hr * 0.06
            rrect(kx, ky, kw, kh, hr * 0.04, vgrad(listOf(rgb(0.35, 0.55, 1.0), rgb(0.1, 0.28, 0.8)), ky, ky + kh))
        }
        val lamp = if (watching) rgb(1.0, 0.22, 0.18) else rgb(0.3, 1.0, 0.4)
        val lr = hr * 0.1
        val lcx = cx; val lcy = cy - hr * 0.52
        circle(lcx, lcy, lr * 2.2, radial(listOf(lamp.op(0.55), lamp.op(0.0)), lcx, lcy, lr * 2.2))
        circle(lcx, lcy, lr, radial(listOf(Color.White, lamp, lamp.shade(0.35)), lcx - lr * 0.3, lcy - lr * 0.3, lr * 1.2))

        val wx = cx - hr * 0.56; val wy = cy - hr * 0.2; val ww = hr * 1.12; val wh = hr * 0.52
        rrect(wx, wy, ww, wh, hr * 0.08, rgb(0.1, 0.02, 0.02))
        rrectStroke(wx, wy, ww, wh, hr * 0.08, Color.Black.op(0.6), 1.0)
        val led = rgb(1.0, 0.26, 0.2)
        glowText(tm, "$count/$total", wx + ww / 2, wy + wh / 2, hr * 0.36, led, led.lit(0.25), hr * 0.05, FontWeight.Bold, Mono)

        listOf(rgb(0.98, 0.82, 0.1), rgb(0.9, 0.12, 0.1), rgb(0.98, 0.82, 0.1)).forEachIndexed { idx, col ->
            val bx = cx + (idx - 1) * hr * 0.42; val by = cy + hr * 0.58; val br = hr * 0.1
            circle(bx, by, br * 1.3, gray(0.2))
            circle(bx, by, br, radial(listOf(col.lit(0.5), col, col.shade(0.35)), bx - br * 0.3, by - br * 0.35, br * 1.3))
        }

        circle(cx, cy, R, radial(listOf(Color.White.op(0.1), Color.Transparent), cx - R * 0.45, cy - R * 0.5, R * 0.9))

        if (finger != null) {
            val px = cx + (if (finger % 2 == 0) -1 else 1) * R * 0.46
            val py = cy + (if (finger < 2) -1 else 1) * R * 0.46
            val hw = R * 0.3
            hand(handP, px - hw * 0.05, py + hw * 0.02, hw)
        }
    }
}
