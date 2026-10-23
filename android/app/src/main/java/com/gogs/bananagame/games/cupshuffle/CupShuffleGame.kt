package com.gogs.bananagame.games.cupshuffle

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/** Brain — Cup Shuffle (iOS CupShuffleGame.swift): the shell game with red party cups. */
object CupShuffleGame {
    val definition = GameDefinition(
        id = "cup-shuffle",
        title = "Cup Shuffle",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "A banana hides under one cup, shown to you before the shuffle.",
                "Watch the cups shuffle, then tap the one you think still hides it.",
                "A wrong pick or a timeout sends you back to level 1.",
            ),
            bulletsVI = listOf(
                "Quả chuối giấu dưới một cái cốc, được cho xem trước khi xáo.",
                "Theo dõi các cốc xáo trộn, rồi chạm vào cốc bạn nghĩ vẫn giấu nó.",
                "Chọn sai hoặc hết giờ sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> CupShuffleView(level, onWin, onFail) }
    )
}

private var cupIds = 0
private class Cup(val hasBanana: Boolean) {
    val id = ++cupIds
    var lifted by mutableStateOf(false)
    var picked by mutableStateOf(false)
}

private enum class CPhase { PEEK, SHUFFLE, PICK, DONE }

@Composable
private fun CupShuffleView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val cupCount = min(9, level + 2)
    val peekTime = max(0.6, 1.6 - level * 0.14)
    val swapCount = 3 + level * 3
    val swapInterval = max(0.12, 0.42 - level * 0.035)
    val pickTime = 5.0
    val cups = remember { mutableStateListOf<Cup>() }
    var phase by remember { mutableStateOf(CPhase.PEEK) }
    var pickLeft by remember { mutableDoubleStateOf(0.0) }
    var demoFinger by remember { mutableStateOf<Int?>(null) }
    val handP = rememberHand()

    fun revealAndFail() {
        if (phase != CPhase.PICK) return
        phase = CPhase.DONE
        cups.firstOrNull { it.hasBanana }?.lifted = true
        onFail()
    }

    fun pick(cup: Cup) {
        if (phase != CPhase.PICK) return
        cup.picked = true; cup.lifted = true
        if (cup.hasBanana) { phase = CPhase.DONE; Haptics.tap(); SoundManager.tap(); onWin() } else revealAndFail()
    }

    suspend fun peekAndShuffle(banana: Int, swaps: Int, sound: Boolean) {
        cups.clear()
        cups.addAll(List(cupCount) { Cup(it == banana) })
        phase = CPhase.PEEK
        cups.forEach { it.lifted = true }
        delay((peekTime * 1000).toLong())
        cups.forEach { it.lifted = false }
        delay(if (isDemo) 400 else 350)
        phase = CPhase.SHUFFLE
        repeat(swaps) {
            val a = rndInt(0 until cups.size)
            var b = rndInt(0 until cups.size)
            if (b == a) b = (b + 1) % cups.size
            val t = cups[a]; cups[a] = cups[b]; cups[b] = t
            if (sound) SoundManager.tap()
            delay((swapInterval * 1000).toLong())
        }
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (isActive) {
                peekAndShuffle(0, min(swapCount, 6), false)
                phase = CPhase.PICK
                pickLeft = pickTime
                delay(700)
                cups.firstOrNull { it.hasBanana }?.let { c ->
                    demoFinger = c.id
                    delay(300)
                    pick(c)
                }
                delay(1400)
                demoFinger = null
            }
        } else {
            peekAndShuffle(rndInt(0 until cupCount), swapCount, true)
            phase = CPhase.PICK
            pickLeft = pickTime
            val start = nowSec()
            while (isActive && phase == CPhase.PICK) {
                delay(50)
                pickLeft = max(0.0, pickTime - (nowSec() - start))
                if (pickLeft <= 0 && phase == CPhase.PICK) revealAndFail()
            }
        }
    }

    Box(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
    ) {
        Canvas(Modifier.fillMaxSize()) { felt() }
        Column(
            Modifier.fillMaxSize().padding(vertical = if (isDemo) 10.dp else 22.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(if (isDemo) 8.dp else 18.dp)
        ) {
            val prompt = when (phase) {
                CPhase.PEEK -> L("Watch the banana…", "Nhìn quả chuối…")
                CPhase.SHUFFLE -> L("Keep your eyes on it!", "Đừng rời mắt khỏi nó!")
                CPhase.PICK -> L("Which cup hides the banana?", "Cốc nào giấu quả chuối?")
                CPhase.DONE -> ""
            }
            Text(prompt, style = ts(if (isDemo) 16.0 else 19.0, FontWeight.ExtraBold, Color.White.op(0.92)), textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 24.dp).heightIn(min = if (isDemo) 20.dp else 26.dp))
            TimeBar(pickLeft / pickTime, Modifier.fillMaxWidth().padding(horizontal = 48.dp).height(6.dp).alpha(if (phase == CPhase.PICK && !isDemo) 1f else 0f),
                track = Color.Black.op(0.3))
            BoxWithConstraints(Modifier.fillMaxWidth().weight(1f)) {
                val dens = androidx.compose.ui.platform.LocalDensity.current.density.toDouble()
                val sw = constraints.maxWidth.toDouble(); val sh = constraints.maxHeight.toDouble()
                val n = max(1, cups.size)
                val cols = if (n <= 5) n else ceil(n / 2.0).toInt()
                val rows = (n + cols - 1) / cols
                val gapX = sw * 0.04
                val w = minOf((sw - gapX * (cols + 1)) / cols, sh / rows * 0.62, 118 * dens)
                val h = w / 0.82
                val stepX = w + gapX; val stepY = h * 1.25
                val blockH = (rows - 1) * stepY
                val ox = sw / 2; val oy = sh / 2 - blockH / 2 + h * 0.08
                fun center(i: Int): P {
                    val row = i / cols
                    val inRow = min(cols, n - row * cols)
                    val rowW = (inRow - 1) * stepX
                    return P(ox - rowW / 2 + (i % cols) * stepX, oy + row * stepY)
                }
                cups.forEachIndexed { i, cup ->
                    key(cup.id) {
                        val c = center(i)
                        val ax by animateFloatAsState((c.x - w / 2).toFloat(), tween((swapInterval * 900).toInt(), easing = FastOutSlowInEasing), label = "x")
                        val ay by animateFloatAsState((c.y - h / 2).toFloat(), tween((swapInterval * 900).toInt(), easing = FastOutSlowInEasing), label = "y")
                        val lift by animateFloatAsState(if (cup.lifted) 1f else 0f, spring(dampingRatio = 0.7f, stiffness = 300f), label = "l")
                        val (src, pressed) = rememberPressed()
                        val sc by animateFloatAsState(if (pressed.value) 0.95f else 1f, tween(80), label = "p")
                        Box(
                            Modifier.offset { IntOffset(ax.roundToInt(), ay.roundToInt()) }
                                .size((w / dens).dp, (h / dens).dp).scale(sc)
                                .clickable(src, null, enabled = phase == CPhase.PICK && !isDemo) { pick(cup) }
                        ) {
                            Canvas(Modifier.fillMaxSize()) { underCup(cup.hasBanana && cup.lifted, cup.lifted) }
                            Canvas(Modifier.fillMaxSize().graphicsLayer {
                                translationY = (-size.height * 0.58f * lift)
                                rotationZ = -5f * lift
                                transformOrigin = TransformOrigin(0.5f, 1f)
                            }) { cupShape() }
                            if (isDemo && demoFinger == cup.id) Canvas(Modifier.fillMaxSize()) {
                                val s = size.width * 0.42
                                hand(handP, size.width * 0.62 - s * 0.3, size.height * 0.62 - s * 0.2, s)
                            }
                        }
                    }
                }
            }
        }
    }
}

private val RED = rgb(0.86, 0.1, 0.12)

private fun frontArc(p: Path, cx: Double, y: Double, rx: Double, ry: Double, reverse: Boolean = false) {
    for (k in 0..16) {
        val t = (if (reverse) 16 - k else k) / 16.0
        val a = PI * (1 - t)
        p.l(cx + rx * cos(a), y + ry * sin(a))
    }
}

private fun DrawScope.cupShape() {
    val w = size.width.toDouble(); val h = size.height.toDouble(); val cx = w / 2
    val topY = h * 0.14; val botY = h * 0.9
    val topRX = w * 0.3; val botRX = w * 0.45
    val ry = h * 0.045
    val body = Path(); body.m(cx - topRX, topY); body.l(cx - botRX, botY); frontArc(body, cx, botY, botRX, ry); body.l(cx + topRX, topY); body.close()
    drawPath(body, Brush.horizontalGradient(0f to RED.shade(0.45), 0.28f to RED.lit(0.25), 0.55f to RED, 1f to RED.shade(0.5), startX = (cx - botRX).f, endX = (cx + botRX).f))
    listOf(0.2, 0.27, 0.34).forEachIndexed { k, f ->
        val y = h * f
        val rx = topRX + (botRX - topRX) * (y - topY) / (botY - topY)
        val ring = Path(); ring.m(cx - rx, y); frontArc(ring, cx, y, rx, ry * 0.8)
        strokePath(ring, RED.shade(0.45).op(if (k == 1) 0.8 else 0.6), max(1.0, h * 0.012))
        val shine = Path(); shine.m(cx - rx, y + h * 0.012); frontArc(shine, cx, y + h * 0.012, rx, ry * 0.8)
        strokePath(shine, Color.White.op(0.18), max(0.8, h * 0.008))
    }
    val lip = Path(); lip.m(cx - botRX * 1.03, botY - h * 0.03)
    frontArc(lip, cx, botY - h * 0.03, botRX * 1.03, ry); frontArc(lip, cx, botY + h * 0.012, botRX * 1.03, ry, true); lip.close()
    drawPath(lip, hgrad(listOf(RED.shade(0.3), RED.lit(0.3), RED.shade(0.35)), cx - botRX, cx + botRX))
    ellipse(cx, topY, topRX, ry, lin(listOf(RED.shade(0.1), RED.shade(0.4)), cx - topRX, topY - ry, cx + topRX, topY + ry))
    ellipseStroke(cx, topY, topRX, ry, RED.shade(0.6), 1.0)
    val gloss = polyPath(cx - topRX * 0.55, topY + h * 0.05, cx - topRX * 0.3, topY + h * 0.05, cx - botRX * 0.42, botY - h * 0.08, cx - botRX * 0.7, botY - h * 0.08)
    drawPath(gloss, vgrad(listOf(Color.White.op(0.5), Color.White.op(0.05)), topY, botY))
    strokePath(body, RED.shade(0.65), max(1.0, w * 0.012))
}

private fun DrawScope.underCup(banana: Boolean, lifted: Boolean) {
    val w = size.width.toDouble(); val h = size.height.toDouble()
    oval(w * 0.03 + w * 0.02, h * 0.86 + h * 0.012, w * 0.94, h * 0.11, Color.Black.op(if (lifted) 0.18 else 0.4))
    if (banana) bananaOnFelt(w * 0.5, h * 0.82, w * 0.7)
}

private fun DrawScope.bananaOnFelt(cx: Double, cy: Double, w: Double) {
    val h = w * 0.4
    oval(cx - w * 0.45, cy + h * 0.12, w * 0.9, h * 0.4, Color.Black.op(0.3))
    val p = Path(); p.m(cx - w * 0.5, cy - h * 0.4)
    p.q(cx - w * 0.02, cy + h * 1.05, cx + w * 0.5, cy - h * 0.5)
    p.q(cx, cy + h * 0.3, cx - w * 0.5, cy - h * 0.4); p.close()
    drawPath(p, vgrad(listOf(rgb(1.0, 0.95, 0.5), rgb(1.0, 0.84, 0.2), rgb(0.85, 0.62, 0.08)), cy - h * 0.3, cy + h * 0.6))
    val ridge = Path(); ridge.m(cx - w * 0.42, cy - h * 0.25); ridge.q(cx, cy + h * 0.62, cx + w * 0.42, cy - h * 0.33)
    strokePath(ridge, rgb(0.85, 0.6, 0.1, 0.6), max(1.0, w * 0.02))
    strokePath(p, rgb(0.45, 0.3, 0.05), max(1.0, w * 0.025))
    rrect(cx - w * 0.58, cy - h * 0.5, w * 0.12, h * 0.2, w * 0.02, rgb(0.42, 0.28, 0.1))
    oval(cx + w * 0.46, cy - h * 0.56, w * 0.07, h * 0.14, rgb(0.3, 0.2, 0.05))
}

private fun DrawScope.felt() {
    val W = size.width.toDouble(); val H = size.height.toDouble()
    drawRect(radial(listOf(rgb(0.13, 0.5, 0.3), rgb(0.06, 0.3, 0.17), rgb(0.02, 0.13, 0.08)), W / 2, H * 0.52, max(W, H) * 0.72))
    val u = density.toDouble()
    var y = 0.0; var k = 0
    while (y < H) {
        var x = ((k * 37) % 11) * u
        while (x < W) { rect(x, y, u, u, Color.White.op(0.05)); x += 11 * u }
        y += 5 * u; k++
    }
}
