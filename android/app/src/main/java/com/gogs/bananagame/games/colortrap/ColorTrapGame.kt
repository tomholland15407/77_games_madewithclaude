package com.gogs.bananagame.games.colortrap

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.GenericShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.TextFields
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/** Brain — Color Trap (iOS ColorTrapGame.swift): a Stroop test in a paint studio. */
object ColorTrapGame {
    val definition = GameDefinition(
        id = "color-trap",
        title = "Color Trap",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "A color word is painted in a different ink.",
                "The prompt says whether to match the ink or the word — tap that swatch.",
                "A wrong tap or a timeout fails you back to level 1.",
            ),
            bulletsVI = listOf(
                "Một từ chỉ màu được viết bằng mực khác màu.",
                "Yêu cầu cho biết chọn theo màu mực hay theo nghĩa của từ — chạm ô màu đó.",
                "Chạm sai hoặc hết giờ sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> ColorTrapView(level, onWin, onFail) }
    )
}

private class ColorOption(val name: String, val color: Color)

private val PALETTE = listOf(
    ColorOption("RED", rgb(0.95, 0.26, 0.21)),
    ColorOption("GREEN", rgb(0.30, 0.80, 0.36)),
    ColorOption("BLUE", rgb(0.26, 0.53, 0.96)),
    ColorOption("YELLOW", BananaTheme.banana),
    ColorOption("ORANGE", rgb(1.0, 0.55, 0.10)),
    ColorOption("PURPLE", rgb(0.67, 0.38, 0.95)),
)

private fun displayName(name: String) = when (name) {
    "RED" -> L("RED", "ĐỎ"); "GREEN" -> L("GREEN", "XANH LÁ"); "BLUE" -> L("BLUE", "XANH DƯƠNG")
    "YELLOW" -> L("YELLOW", "VÀNG"); "ORANGE" -> L("ORANGE", "CAM"); "PURPLE" -> L("PURPLE", "TÍM")
    else -> name
}

@Composable
private fun ColorTrapView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val target = 2 + level
    val swatchCount = min(PALETTE.size, 2 + level)
    val timePerRound = max(1.1, 4.2 - level * 0.42)
    val canFlip = level >= 5
    var swatches by remember { mutableStateOf(listOf<ColorOption>()) }
    var wordText by remember { mutableStateOf("") }
    var inkColor by remember { mutableStateOf(Color.White) }
    var inkMode by remember { mutableStateOf(true) }
    var correctName by remember { mutableStateOf("") }
    var score by remember { mutableIntStateOf(0) }
    var timeLeft by remember { mutableDoubleStateOf(timePerRound) }
    var done by remember { mutableStateOf(false) }
    var demoFlash by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    var timerJob by remember { mutableStateOf<Job?>(null) }
    val tm = rememberTextMeasurer()

    fun startTimer() {
        timerJob?.cancel()
        timeLeft = timePerRound
        val start = nowSec()
        timerJob = scope.launch {
            while (isActive && !done) {
                delay(50)
                timeLeft = max(0.0, timePerRound - (nowSec() - start))
                if (timeLeft <= 0 && !done) { done = true; SoundManager.error(); onFail() }
            }
        }
    }

    fun newRound() {
        if (done) return
        val subset = PALETTE.shuffled().take(swatchCount)
        swatches = subset.shuffled()
        val wordOption = subset.pick()
        val inkOption = subset.filter { it.name != wordOption.name }.randomOrNull() ?: wordOption
        inkMode = !(canFlip && rndBool())
        wordText = wordOption.name
        inkColor = inkOption.color
        correctName = if (inkMode) inkOption.name else wordOption.name
        startTimer()
    }

    fun choose(o: ColorOption) {
        if (done || isDemo) return
        if (o.name == correctName) {
            Haptics.tap(); SoundManager.tap()
            score += 1
            if (score >= target) { done = true; timerJob?.cancel(); onWin() } else newRound()
        } else {
            done = true; timerJob?.cancel(); Haptics.warning(); SoundManager.error(); onFail()
        }
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (isActive) {
                done = false; score = 0
                repeat(target) {
                    val subset = PALETTE.shuffled().take(swatchCount)
                    swatches = subset.shuffled()
                    val wordOption = subset.pick()
                    val inkOption = subset.filter { it.name != wordOption.name }.randomOrNull() ?: wordOption
                    inkMode = true
                    wordText = wordOption.name; inkColor = inkOption.color; correctName = inkOption.name
                    timeLeft = timePerRound; demoFlash = null
                    delay(900)
                    demoFlash = correctName
                    delay(500)
                    score += 1
                    delay(200)
                }
                delay(900)
            }
        } else newRound()
    }

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
    ) {
        // The studio wall: score, clock and the easel.
        Box(Modifier.fillMaxWidth().weight(1f)) {
            Canvas(Modifier.fillMaxSize()) { studioWall() }
            Column(
                Modifier.fillMaxSize().padding(top = if (isDemo) 8.dp else 16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(if (isDemo) 4.dp else 12.dp)
            ) {
                if (!isDemo) {
                    Text("$score / $target", style = ts(34.0, FontWeight.Black))
                    TimeBar(timeLeft / timePerRound, Modifier.fillMaxWidth().padding(horizontal = 44.dp).height(8.dp))
                }
                BoxWithConstraints(Modifier.fillMaxWidth().weight(1f)) {
                    val wPx = constraints.maxWidth.toDouble(); val hPx = constraints.maxHeight.toDouble()
                    val dens = androidx.compose.ui.platform.LocalDensity.current.density.toDouble()
                    val cw = max(40 * dens, min(wPx - (if (isDemo) 44 else 52) * dens, (hPx - 34 * dens) * 1.75))
                    val ch = cw / 1.75
                    val rx = (wPx - cw) / 2; val ry = max(16 * dens, (hPx - ch) / 2 - 4 * dens)
                    Canvas(Modifier.fillMaxSize()) {
                        easel(rx, ry, cw, ch)
                        paintedWord(tm, displayName(wordText), inkColor, rx, ry, cw, ch)
                    }
                    // The masking-tape instruction across the top of the canvas.
                    Box(Modifier.fillMaxWidth().offset(y = (ry / dens).dp - (if (isDemo) 12 else 16).dp), contentAlignment = Alignment.TopCenter) {
                        Row(
                            Modifier.widthIn(max = (cw * 0.92 / dens).dp).rotate(-2.5f)
                                .shadow(2.dp, TapeShape)
                                .background(rgb(0.94, 0.88, 0.7, 0.97), TapeShape)
                                .padding(horizontal = if (isDemo) 14.dp else 18.dp, vertical = if (isDemo) 5.dp else 7.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            val ink = rgb(0.2, 0.18, 0.16)
                            Icon(if (inkMode) Icons.Filled.WaterDrop else Icons.Filled.TextFields, null, tint = ink,
                                modifier = Modifier.size(if (isDemo) 14.dp else 18.dp))
                            Spacer(Modifier.width(7.dp))
                            Text(if (inkMode) L("MATCH THE INK", "CHỌN THEO MÀU MỰC") else L("MATCH THE WORD", "CHỌN THEO NGHĨA TỪ"),
                                style = ts(if (isDemo) 13.0 else 17.0, FontWeight.ExtraBold, ink, spacing = 1.0), maxLines = 1)
                        }
                    }
                }
            }
        }
        // The wooden floor with the open paint cans.
        Box(Modifier.fillMaxWidth()) {
            Canvas(Modifier.matchParentSize()) { studioFloor() }
            val d = if (isDemo) 58.dp else 84.dp
            val cols = min(3, swatchCount)
            Column(
                Modifier.fillMaxWidth().padding(horizontal = if (isDemo) 26.dp else 28.dp)
                    .padding(top = if (isDemo) 12.dp else 22.dp, bottom = if (isDemo) 12.dp else 26.dp),
                verticalArrangement = Arrangement.spacedBy(if (isDemo) 10.dp else 18.dp)
            ) {
                swatches.chunked(cols).forEach { row ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        for (option in row) {
                            Box(Modifier.weight(1f), contentAlignment = Alignment.Center) { PaintCan(option, d, demoFlash == option.name, isDemo) { choose(option) } }
                        }
                        repeat(cols - row.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }
        }
    }
}

@Composable
private fun PaintCan(option: ColorOption, d: androidx.compose.ui.unit.Dp, picked: Boolean, isDemo: Boolean, onClick: () -> Unit) {
    val (src, pressed) = rememberPressed()
    val s by animateFloatAsState(if (pressed.value) 0.92f else if (picked) 1.08f else 1f, tween(80), label = "can")
    Box(Modifier.scale(s)) {
        Canvas(
            Modifier.size(d)
                .then(if (picked) Modifier.border(4.dp, Color.White, RoundedCornerShape(14.dp)) else Modifier)
                .clickable(src, null, onClick = onClick)
        ) { paintCan(option.color) }
        if (picked && isDemo) Icon(Icons.Filled.TouchApp, null, tint = Color.White, modifier = Modifier.align(Alignment.Center).offset(16.dp, 18.dp).size(28.dp))
    }
}

/** Masking tape with torn, zig-zag ends. */
private val TapeShape = GenericShape { s, _ ->
    val z = 4f * 2.6f
    val n = max(2, (s.height / 13f).toInt())
    moveTo(z, 0f); lineTo(s.width - z, 0f)
    for (i in 0 until n) {
        lineTo(s.width, s.height * (i + 0.5f) / n)
        lineTo(s.width - z, s.height * (i + 1f) / n)
    }
    lineTo(z, s.height)
    for (i in 0 until n) {
        lineTo(0f, s.height - s.height * (i + 0.5f) / n)
        lineTo(z, s.height - s.height * (i + 1f) / n)
    }
    close()
}

private val WOOD = rgb(0.62, 0.41, 0.22)
private val WOOD_DARK = rgb(0.4, 0.25, 0.13)

private fun DrawScope.easel(rx: Double, ry: Double, rw: Double, rh: Double) {
    val legW = max(6.0 * density, rw * 0.045)
    val apexX = rx + rw / 2; val apexY = ry - rh * 0.16
    fun leg(bottomX: Double, width: Double, color: Color) {
        val p = polyPath(apexX - width * 0.35, apexY, apexX + width * 0.35, apexY, bottomX + width / 2, size.height + 4.0, bottomX - width / 2, size.height + 4.0)
        drawPath(p, hgrad(listOf(color.lit(0.12), color, color.shade(0.2)), bottomX - width, bottomX + width))
    }
    leg(rx + rw / 2, legW * 0.85, WOOD_DARK)
    leg(rx + rw * 0.1, legW, WOOD)
    leg(rx + rw * 0.9, legW, WOOD)
    blurRRect(rx + 4 * density, ry + 7 * density, rw, rh, 0.0, Color.Black.op(0.5), 7.0 * density)
    rect(rx, ry, rw, rh, vgrad(listOf(gray(0.995), rgb(0.95, 0.94, 0.91)), ry, ry + rh))
    val step = 3.0 * density
    var y = ry + step
    while (y < ry + rh) { line(rx, y, rx + rw, y, Color.Black.op(0.025), 0.6, androidx.compose.ui.graphics.StrokeCap.Butt); y += step }
    var x = rx + step
    while (x < rx + rw) { line(x, ry, x, ry + rh, Color.Black.op(0.025), 0.6, androidx.compose.ui.graphics.StrokeCap.Butt); x += step }
    rectStroke(rx, ry, rw, rh, gray(0.78), 1.0)
    val lx = rx - rw * 0.07; val ly = ry + rh - 3; val lw = rw * 1.14; val lh = max(9.0 * density, rh * 0.075)
    rrect(lx, ly + 3, lw, lh, 3.0, Color.Black.op(0.3))
    rrect(lx, ly, lw, lh, 3.0, vgrad(listOf(WOOD.lit(0.2), WOOD, WOOD_DARK), ly, ly + lh))
}

/** A stable pseudo-random stream per word, so the drips don't move between frames. */
private class Stream(s: String) {
    var h: ULong = 1469598103934665603UL
    init { for (ch in s) h = (h xor ch.code.toULong()) * 1099511628211UL }
    fun next(): Double {
        h = h * 6364136223846793005UL + 1442695040888963407UL
        return ((h shr 33) % 10_000UL).toDouble() / 10_000
    }
}

private fun DrawScope.paintedWord(tm: TextMeasurer, word: String, ink: Color, rx: Double, ry: Double, rw: Double, rh: Double) {
    if (word.isEmpty() || rw <= 20) return
    val base = 100.0
    fun style(sz: Double) = TextStyle(fontSize = (sz / density / fontScale).sp, fontWeight = FontWeight.Black, fontFamily = Rounded)
    val probe = tm.measure(word, style(base), softWrap = false, maxLines = 1)
    val mW = probe.size.width.toDouble()
    val fs = min(base * rw * 0.84 / max(mW, 1.0), rh * 0.46)
    val cx = rx + rw / 2; val cy = ry + rh / 2 - fs * 0.12
    val textW = mW * fs / base
    val outline = rgb(0.12, 0.11, 0.13)
    val o = max(1.2, fs * 0.045)
    val layout = tm.measure(word, style(fs), softWrap = false, maxLines = 1)
    val tlx = cx - layout.size.width / 2.0; val tly = cy - layout.size.height / 2.0

    val letters = word.toList()
    val edges = mutableListOf(0.0)
    for (i in 1..letters.size) edges.add(tm.measure(word.substring(0, i), style(base), softWrap = false, maxLines = 1).size.width.toDouble())
    val stems = setOf('B', 'D', 'Đ', 'E', 'H', 'K', 'L', 'M', 'N', 'P', 'R', 'U', 'Ư', 'F')
    val rounds = setOf('O', 'Ô', 'Ơ', 'Ỏ', 'G', 'C', 'Q', 'S', 'Ó', 'Ò')
    val left = cx - textW / 2
    val rs = Stream(word)
    val drips = mutableListOf<Path>()
    letters.forEachIndexed { i, ch ->
        val roll = rs.next()
        if (!(ch in stems || ch in rounds) || roll >= 0.6) return@forEachIndexed
        val a = left + edges[i] * fs / base; val b = left + edges[i + 1] * fs / base
        val x = if (ch in stems) a + (b - a) * 0.27 else (a + b) / 2
        val w = fs * (0.09 + 0.05 * rs.next())
        val y0 = cy + fs * 0.27
        val len = min(fs * (0.2 + 0.46 * rs.next()), ry + rh - y0 - w * 1.4)
        if (len <= w) return@forEachIndexed
        val p = Path()
        p.addRoundRect(RoundRect((x - w / 2).f, y0.f, (x + w / 2).f, (y0 + len).f, CornerRadius((w / 2).f)))
        p.addOval(androidx.compose.ui.geometry.Rect((x - w * 0.62).f, (y0 + len - w * 0.62).f, (x + w * 0.62).f, (y0 + len + w * 0.62).f))
        drips.add(p)
    }
    for (k in 0 until 8) {
        val a = k * PI / 4
        drawText(layout, outline, Offset((tlx + cos(a) * o).f, (tly + sin(a) * o).f))
    }
    val paint = vgrad(listOf(ink.lit(0.2), ink, ink.shade(0.14)), cy - fs * 0.45, cy + fs * 0.6)
    clipRect(rx.f, (cy + fs * 0.3).f, (rx + rw).f, (ry + rh * 2).f) {
        for (d in drips) strokePath(d, outline, o * 2)
        for (d in drips) drawPath(d, paint)
    }
    drawText(layout, paint, Offset(tlx.f, tly.f))
    clipRect(rx.f, (cy - fs * 0.4).f, (rx + rw).f, (cy - fs * 0.2).f) {
        drawText(layout, Color.White.op(0.28), Offset(tlx.f, tly.f))
    }
}

private fun DrawScope.paintCan(paint: Color) {
    val d = min(size.width, size.height).toDouble()
    val cx = size.width / 2.0; val oy = (size.height - d) / 2
    val rx = d * 0.39; val ry = d * 0.13
    val topY = oy + d * 0.2; val botY = oy + d * 0.84
    fun front(p: Path, y: Double, reverse: Boolean = false) {
        for (k in 0..18) {
            val a = PI * (if (reverse) 18 - k else k) / 18
            p.l(cx - rx * cos(a), y + ry * sin(a))
        }
    }
    val metal = Brush.horizontalGradient(0f to gray(0.42), 0.28f to gray(0.93), 0.62f to gray(0.74), 1f to gray(0.4),
        startX = (cx - rx).f, endX = (cx + rx).f)
    blurOval(cx - rx * 1.08, botY + ry * 0.45 - ry * 0.95, rx * 2.16, ry * 1.9, Color.Black.op(0.55), d * 0.035)
    val body = Path(); body.m(cx - rx, topY); front(body, botY); body.l(cx + rx, topY); body.close()
    drawPath(body, metal)
    val l0 = topY + ry * 1.35; val l1 = botY - d * 0.03
    val label = Path(); label.m(cx - rx, l0); front(label, l0); front(label, l1, true); label.close()
    drawPath(label, Brush.horizontalGradient(0f to paint.shade(0.4), 0.3f to paint.lit(0.18), 0.62f to paint, 1f to paint.shade(0.4),
        startX = (cx - rx).f, endX = (cx + rx).f))
    val stripe = Path(); val sy = l0 + (l1 - l0) * 0.2; stripe.m(cx - rx, sy); front(stripe, sy)
    strokePath(stripe, Color.White.op(0.85), max(1.0, d * 0.02))
    strokePath(body, gray(0.3), 1.0)
    drawOval(metal, off(cx - rx, topY - ry), sz(rx * 2, ry * 2))
    ellipseStroke(cx, topY, rx, ry, gray(0.32), 1.0)
    val pcx = cx; val pcy = topY + ry * 0.05; val prx = rx * 0.86; val pry = ry * 0.76
    ellipse(pcx, pcy, prx, pry, lin(listOf(paint.lit(0.28), paint, paint.shade(0.18)), pcx - prx, pcy - pry, pcx + prx, pcy + pry))
    oval(pcx - prx + prx * 2 * 0.16, pcy - pry + pry * 2 * 0.18, prx * 2 * 0.3, pry * 2 * 0.3, Color.White.op(0.6))
    for ((fx, len) in listOf(0.3 to 0.3, -0.42 to 0.16)) {
        val x = cx + rx * fx
        val yTop = topY + ry * sqrt(max(0.0, 1 - fx * fx)) - d * 0.01
        val w = d * 0.075
        val drip = Path()
        drip.addRoundRect(RoundRect((x - w / 2).f, yTop.f, (x + w / 2).f, (yTop + d * len).f, CornerRadius((w / 2).f)))
        drip.addOval(androidx.compose.ui.geometry.Rect((x - w * 0.62).f, (yTop + d * len - w * 0.62).f, (x + w * 0.62).f, (yTop + d * len + w * 0.62).f))
        strokePath(drip, paint.shade(0.5), 1.2)
        drawPath(drip, hgrad(listOf(paint.lit(0.22), paint.shade(0.05)), x - w, x + w))
    }
}

private fun DrawScope.studioWall() {
    rect(0.0, 0.0, size.width.toDouble(), size.height.toDouble(), vgrad(listOf(rgb(0.2, 0.34, 0.38), rgb(0.11, 0.2, 0.24)), 0.0, size.height.toDouble()))
    val stripe = 16.0 * density
    var x = 0.0; var k = 0
    while (x < size.width) {
        if (k % 2 == 0) rect(x, 0.0, stripe, size.height.toDouble(), Color.White.op(0.035))
        x += stripe; k++
    }
    drawRect(radial(listOf(Color.White.op(0.18), Color.Transparent), size.width / 2.0, size.height * 0.55, size.width * 0.75))
}

private fun DrawScope.studioFloor() {
    val u = density.toDouble()
    val W = size.width.toDouble(); val H = size.height.toDouble()
    rect(0.0, 0.0, W, H, vgrad(listOf(rgb(0.5, 0.33, 0.19), rgb(0.37, 0.24, 0.13)), 0.0, H))
    rect(0.0, 0.0, W, 8 * u, rgb(0.23, 0.14, 0.08))
    rect(0.0, 8 * u, W, 3 * u, Color.Black.op(0.28))
    val plank = 26 * u
    var y = 11 * u; var row = 0
    while (y < H) {
        rect(0.0, y, W, 1.2 * u, Color.Black.op(0.3))
        var x = ((row * 61) % 113 - 20) * u
        while (x < W) { rect(x, y, 1.2 * u, plank, Color.Black.op(0.25)); x += 124 * u }
        for (g in 0 until 3) {
            val gy = y + plank * (0.3 + 0.2 * g)
            val grain = Path(); grain.m(0.0, gy); grain.c(W * 0.3, gy - 2 * u, W * 0.7, gy + 3 * u, W, gy + 2 * u)
            strokePath(grain, Color.Black.op(0.07), 1.0 * u)
        }
        y += plank; row++
    }
    for ((fx, fy, fr0) in listOf(Triple(0.12, 0.7, 7.0), Triple(0.86, 0.35, 5.0), Triple(0.55, 0.9, 6.0), Triple(0.3, 0.2, 4.0))) {
        val fr = fr0 * u
        oval(W * fx - fr, H * fy - fr * 0.6, fr * 2, fr * 1.2, Color.White.op(0.12))
    }
}
