package com.gogs.bananagame.games.bottleorder

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
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
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.max
import kotlin.math.min

/** Brain — Bottle Order (iOS BottleOrderGame.swift): deduce a hidden order from "how many are right". */
object BottleOrderGame {
    val definition = GameDefinition(
        id = "bottle-order",
        title = "Bottle Order",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "A secret left-to-right order of colored bottles is hidden.",
                "Tap two bottles to swap them, then tap CHECK.",
                "CHECK reports only HOW MANY are in the right spot, not which — deduce from the history.",
                "Solve it before your checks or the clock run out.",
            ),
            bulletsVI = listOf(
                "Một thứ tự bí mật từ trái sang phải của các chai màu bị giấu.",
                "Chạm vào hai chai để đổi chỗ, rồi chạm KIỂM TRA.",
                "KIỂM TRA chỉ báo BAO NHIÊU chai đúng vị trí, không nói chai nào — hãy suy luận từ lịch sử.",
                "Giải trước khi hết lượt kiểm tra hoặc hết giờ.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> BottleOrderView(level, onWin, onFail) }
    )
}

private val PALETTE = listOf(BananaTheme.banana, rgb(0.95, 0.30, 0.32), rgb(0.30, 0.62, 0.98), rgb(0.36, 0.82, 0.48), rgb(0.78, 0.46, 0.96), rgb(0.98, 0.56, 0.20))

private sealed interface DemoTarget { data class Bottle(val i: Int) : DemoTarget; data object Check : DemoTarget }

@Composable
private fun BottleOrderView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val count = listOf(3, 4, 4, 5, 5, 6, 6)[min(level, 7) - 1]
    val maxChecks = listOf(8, 8, 7, 8, 7, 7, 6)[min(level, 7) - 1]
    val timeLimit = listOf(55.0, 60.0, 60.0, 70.0, 70.0, 75.0, 75.0)[min(level, 7) - 1]
    var playing by remember { mutableStateOf(true) }
    var target by remember { mutableStateOf(listOf<Int>()) }
    var working by remember { mutableStateOf(listOf<Int>()) }
    var selected by remember { mutableStateOf<Int?>(null) }
    var history by remember { mutableStateOf(listOf<Pair<List<Int>, Int>>()) }
    var checksLeft by remember { mutableIntStateOf(maxChecks) }
    var timeLeft by remember { mutableDoubleStateOf(timeLimit) }
    var demoFinger by remember { mutableStateOf<DemoTarget?>(null) }
    val tm = rememberTextMeasurer()

    fun win() { if (!playing) return; playing = false; onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }

    fun tapSlot(i: Int) {
        if (!playing || i >= working.size) return
        val s = selected
        if (s != null) {
            if (s == i) selected = null
            else {
                working = working.toMutableList().also { val t = it[s]; it[s] = it[i]; it[i] = t }
                selected = null; SoundManager.tap(); Haptics.tap()
            }
        } else { selected = i; SoundManager.tap() }
    }

    fun check() {
        if (!playing) return
        selected = null
        val correct = working.indices.count { working[it] == target[it] }
        history = history + (working to correct)
        if (correct == working.size) { win(); return }
        checksLeft -= 1
        SoundManager.tap(); Haptics.tap()
        if (checksLeft <= 0) fail()
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (isActive) {
                target = listOf(0, 1, 2); working = listOf(2, 1, 0); selected = null; history = emptyList()
                checksLeft = maxChecks; playing = true; timeLeft = timeLimit; demoFinger = null
                delay(700)
                demoFinger = DemoTarget.Check; delay(250); check(); delay(900)
                demoFinger = DemoTarget.Bottle(0); delay(250); tapSlot(0); delay(450)
                demoFinger = DemoTarget.Bottle(2); delay(250); tapSlot(2); delay(600)
                demoFinger = DemoTarget.Check; delay(250); check(); delay(400)
                demoFinger = null
                delay(1100)
            }
        } else {
            val n = count
            target = (0 until n).shuffled()
            var w = (0 until n).shuffled()
            while (w == target || w.indices.count { w[it] == target[it] } >= n - 1) w = w.shuffled()
            working = w
            selected = null; history = emptyList(); checksLeft = maxChecks; playing = true; timeLeft = timeLimit
            val start = nowSec()
            while (isActive && playing) {
                delay(50)
                timeLeft = max(0.0, timeLimit - (nowSec() - start))
                if (timeLeft <= 0) { fail(); break }
            }
        }
    }

    BoxWithConstraints(Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))) {
        val n = max(count, 1)
        val bottleW = min(if (isDemo) 34f else 64f, (maxWidth.value - 56) / n - 10).dp
        val bottleH = bottleW * 2.4f
        Canvas(Modifier.fillMaxSize()) { bottleWall() }
        Column(
            Modifier.fillMaxSize().padding(top = if (isDemo) 8.dp else 14.dp, bottom = if (isDemo) 10.dp else 18.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(if (isDemo) 6.dp else 12.dp)
        ) {
            if (!isDemo) TimeBar(timeLeft / timeLimit, Modifier.fillMaxWidth().padding(horizontal = 60.dp).height(5.dp), track = Color.Black.op(0.3))
            Blackboard(history.takeLast(if (isDemo) 2 else 7), checksLeft, if (isDemo) 11.0 else 15.0, isDemo)
            Spacer(Modifier.weight(1f))
            Box(Modifier.fillMaxWidth()) {
                // The table runs from behind the mystery box down past the bell.
                Canvas(Modifier.matchParentSize()) { bottleTable((bottleH * 0.5f).toPx().toDouble()) }
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(if (isDemo) 8.dp else 16.dp),
                    modifier = Modifier.fillMaxWidth()) {
                    // Stage: the mystery box with the bottles in front of it.
                    val rowW = (bottleW + 10.dp) * max(working.size, 1)
                    Box(Modifier.height(bottleH * 1.45f), contentAlignment = Alignment.BottomCenter) {
                        Canvas(Modifier.size(rowW + 16.dp, bottleH * 0.82f).offset(y = -bottleH * 0.5f)) { mysteryBox(tm) }
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            working.forEachIndexed { i, c ->
                                Box {
                                    Bottle(PALETTE[c], bottleW, selected == i, Modifier.clickable(remember { MutableInteractionSource() }, null, enabled = !isDemo) { tapSlot(i) })
                                    if (isDemo && demoFinger == DemoTarget.Bottle(i)) Finger(bottleW * 0.7f, Modifier.align(Alignment.BottomEnd))
                                }
                            }
                        }
                    }
                    CheckButton(isDemo, demoFinger == DemoTarget.Check, enabled = playing || isDemo) { if (!isDemo) check() }
                }
            }
        }
    }
}

@Composable
private fun Finger(size: Dp, modifier: Modifier) {
    Icon(Icons.Filled.TouchApp, null, tint = Color.White, modifier = modifier.offset(size * 0.35f, size * 0.25f).size(size))
}

@Composable
private fun Bottle(color: Color, width: Dp, selected: Boolean, modifier: Modifier) {
    val lift by animateFloatAsState(if (selected) 1f else 0f, tween(150), label = "lift")
    Box(modifier.size(width, width * 2.4f)) {
        Canvas(Modifier.fillMaxSize()) {
            val w = size.width.toDouble(); val h = size.height.toDouble()
            val l = 14 * density * lift
            ellipse(w / 2, h + w * 0.1 - w * 0.14 + 0.0, w * 0.55, w * 0.14, Color.Black.op(0.35))
            if (lift > 0) blurRRect(w * 0.05, -l + h * 0.05, w * 0.9, h * 0.9, w * 0.2, color.op(0.85 * lift), 10.0 * density)
            at(0.0, -l.toDouble()) { bottle(w, h, color) }
        }
    }
}

@Composable
private fun Blackboard(shown: List<Pair<List<Int>, Int>>, checksLeft: Int, dot: Double, isDemo: Boolean) {
    Column(
        Modifier.padding(horizontal = 24.dp).widthIn(max = if (isDemo) 250.dp else 300.dp).fillMaxWidth()
            .shadow(3.dp, RoundedCornerShape(10.dp))
            .background(rgb(0.14, 0.2, 0.17), RoundedCornerShape(10.dp))
            .border(if (isDemo) 5.dp else 7.dp, rgb(0.55, 0.36, 0.18), RoundedCornerShape(10.dp))
            .padding(horizontal = if (isDemo) 12.dp else 16.dp, vertical = if (isDemo) 7.dp else 10.dp),
        verticalArrangement = Arrangement.spacedBy(if (isDemo) 4.dp else 6.dp)
    ) {
        Text(L("CHECKS LEFT  $checksLeft", "CÒN $checksLeft LƯỢT"), style = ts(if (isDemo) 13.0 else 16.0, FontWeight.ExtraBold,
            if (checksLeft <= 2) rgb(1.0, 0.45, 0.42) else rgb(1.0, 0.9, 0.5)), modifier = Modifier.align(Alignment.CenterHorizontally))
        for ((arr, correct) in shown) Row(verticalAlignment = Alignment.CenterVertically) {
            Row(horizontalArrangement = Arrangement.spacedBy((dot * 0.35).dp)) {
                for (c in arr) Box(Modifier.size(dot.dp).background(PALETTE[c].op(0.9), CircleShape).border(1.dp, Color.White.op(0.55), CircleShape))
            }
            Spacer(Modifier.weight(1f).widthIn(min = 8.dp))
            Text("$correct", style = ts(dot * 1.25, FontWeight.Black, Color.White.op(0.92)))
            Spacer(Modifier.width(4.dp))
            Text(L("correct", "đúng"), style = ts(dot * 0.8, FontWeight.SemiBold, Color.White.op(0.6)))
        }
    }
}

@Composable
private fun CheckButton(isDemo: Boolean, fingered: Boolean, enabled: Boolean, onClick: () -> Unit) {
    val sc by animateFloatAsState(if (fingered) 0.95f else 1f, tween(100), label = "c")
    Box(Modifier.fillMaxWidth().padding(horizontal = 40.dp)) {
        Row(
            Modifier.fillMaxWidth().scale(sc).shadow(if (fingered) 1.dp else 4.dp, RoundedCornerShape(16.dp))
                .background(Brush.verticalGradient(listOf(rgb(1.0, 0.88, 0.5), rgb(0.85, 0.62, 0.18))), RoundedCornerShape(16.dp))
                .border(2.dp, rgb(0.5, 0.32, 0.06), RoundedCornerShape(16.dp))
                .clickable(enabled = enabled && !isDemo, onClick = onClick)
                .padding(vertical = if (isDemo) 10.dp else 15.dp),
            horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically
        ) {
            val ink = rgb(0.3, 0.18, 0.02)
            Icon(Icons.Filled.Notifications, null, tint = ink, modifier = Modifier.size(if (isDemo) 18.dp else 22.dp))
            Spacer(Modifier.width(10.dp))
            Text(L("CHECK", "KIỂM TRA"), style = ts(if (isDemo) 18.0 else 22.0, FontWeight.Black, ink))
        }
        if (isDemo && fingered) Finger(26.dp, Modifier.align(Alignment.CenterEnd).padding(end = 30.dp))
    }
}

private fun DrawScope.bottle(w: Double, h: Double, color: Color) {
    val cx = w / 2
    val neckW = w * 0.34; val bodyTop = h * 0.42; val neckTop = h * 0.1
    val glass = Path()
    glass.m(cx - neckW / 2, neckTop)
    glass.l(cx - neckW / 2, h * 0.24)
    glass.c(cx - neckW / 2, h * 0.32, w * 0.02, h * 0.33, w * 0.02, bodyTop)
    glass.l(w * 0.02, h - w * 0.12)
    glass.q(w * 0.02, h, w * 0.14, h)
    glass.l(w - w * 0.14, h)
    glass.q(w - w * 0.02, h, w - w * 0.02, h - w * 0.12)
    glass.l(w - w * 0.02, bodyTop)
    glass.c(w - w * 0.02, h * 0.33, cx + neckW / 2, h * 0.32, cx + neckW / 2, h * 0.24)
    glass.l(cx + neckW / 2, neckTop)
    glass.close()
    drawPath(glass, Brush.horizontalGradient(0f to color.shade(0.35), 0.3f to color.lit(0.2), 0.6f to color, 1f to color.shade(0.45), startX = 0f, endX = w.f))
    clipPath(glass) {
        val lx = w * 0.02; val ly = h * 0.56; val lw = w * 0.96; val lh = h * 0.22
        rect(lx, ly, lw, lh, hgrad(listOf(rgb(0.85, 0.82, 0.74), rgb(0.99, 0.97, 0.9), rgb(0.8, 0.77, 0.7)), lx, lx + lw))
        rect(lx, ly, lw, lh * 0.14, color.shade(0.2))
        rect(lx, ly + lh - lh * 0.14, lw, lh * 0.14, color.shade(0.2))
        circle(lx + lw / 2, ly + lh / 2, min(lw, lh) * 0.26, color)
        rrect(w * 0.16, bodyTop + h * 0.02, w * 0.12, h * 0.5, w * 0.06, Color.White.op(0.4))
        rrect(cx - neckW * 0.3, neckTop + h * 0.02, neckW * 0.16, h * 0.16, w * 0.04, Color.White.op(0.45))
    }
    strokePath(glass, color.shade(0.6).op(0.8), max(1.0, w * 0.035))
    val lipH = h * 0.03
    rrect(cx - neckW * 0.62, neckTop - h * 0.015, neckW * 1.24, lipH, lipH / 2, color.shade(0.25))
    val capX = cx - neckW * 0.66; val capW = neckW * 1.32; val capH = h * 0.075
    val crown = Path()
    crown.m(capX, capH)
    val teeth = 7
    for (k in 0..teeth) crown.l(capX + capW * k / teeth, if (k % 2 == 0) capH else capH - capH * 0.3)
    crown.l(capX + capW, capH * 0.25)
    crown.q(capX + capW / 2, -capH * 0.3, capX, capH * 0.25)
    crown.close()
    drawPath(crown, hgrad(listOf(gray(0.55), gray(0.95), gray(0.6)), capX, capX + capW))
    strokePath(crown, gray(0.35), 0.8)
}

private fun DrawScope.mysteryBox(tm: TextMeasurer) {
    val W = size.width.toDouble(); val H = size.height.toDouble()
    val card = rgb(0.8, 0.6, 0.36)
    val fy = H * 0.12; val fh = H * 0.88
    val top = polyPath(0.0, fy, W * 0.05, 0.0, W - W * 0.05, 0.0, W, fy)
    drawPath(top, card.lit(0.15)); strokePath(top, card.shade(0.5), 1.0)
    rect(0.0, fy, W, fh, vgrad(listOf(card, card.shade(0.18)), fy, fy + fh))
    rectStroke(0.0, fy, W, fh, card.shade(0.5), 1.2)
    rect(W / 2 - W * 0.07, 0.0, W * 0.14, H * 0.4, rgb(0.9, 0.78, 0.55, 0.85))
    for (fx in listOf(0.27, 0.73)) text(tm, "?", W * fx, fy + fh * 0.33, H * 0.48, rgb(0.36, 0.22, 0.1), FontWeight.Black)
}

private fun DrawScope.bottleWall() {
    val W = size.width.toDouble(); val H = size.height.toDouble(); val u = density.toDouble()
    rect(0.0, 0.0, W, H, vgrad(listOf(rgb(0.3, 0.16, 0.14), rgb(0.16, 0.08, 0.07)), 0.0, H))
    var x = 0.0; var k = 0
    while (x < W) { if (k % 2 == 0) rect(x, 0.0, 22 * u, H, Color.White.op(0.03)); x += 22 * u; k++ }
    drawRect(radial(listOf(rgb(1.0, 0.8, 0.5, 0.22), Color.Transparent), W / 2, H * 0.45, W * 0.8))
    val lx = W / 2; val ly = H * 0.36
    val sw = min(W * 0.3, 110 * u)
    drawPath(polyPath(lx - sw * 0.42, ly + sw * 0.18, lx + sw * 0.42, ly + sw * 0.18, lx + sw * 1.6, H, lx - sw * 1.6, H),
        vgrad(listOf(rgb(1.0, 0.85, 0.55, 0.3), rgb(1.0, 0.85, 0.55, 0.0)), ly, H * 0.95))
    line(lx, 0.0, lx, ly - sw * 0.2, Color.Black.op(0.6), 2 * u, androidx.compose.ui.graphics.StrokeCap.Butt)
    val shade = Path()
    shade.m(lx - sw * 0.12, ly - sw * 0.22); shade.l(lx + sw * 0.12, ly - sw * 0.22)
    shade.q(lx + sw * 0.4, ly - sw * 0.1, lx + sw * 0.46, ly + sw * 0.18)
    shade.l(lx - sw * 0.46, ly + sw * 0.18)
    shade.q(lx - sw * 0.4, ly - sw * 0.1, lx - sw * 0.12, ly - sw * 0.22)
    shade.close()
    ellipse(lx, ly + sw * 0.2, sw * 0.16, sw * 0.12, radial(listOf(Color.White, rgb(1.0, 0.85, 0.5), rgb(1.0, 0.7, 0.3, 0.0)), lx, ly + sw * 0.2, sw * 0.22))
    drawPath(shade, hgrad(listOf(rgb(0.2, 0.32, 0.26), rgb(0.36, 0.52, 0.42), rgb(0.16, 0.26, 0.2)), lx - sw * 0.46, lx + sw * 0.46))
    strokePath(shade, Color.Black.op(0.5), u)
}

private fun DrawScope.bottleTable(top: Double) {
    val u = density.toDouble()
    val ex = 40 * u
    translate((-ex).toFloat(), top.toFloat()) { tableBody(size.width + 2 * ex, size.height - top + 60 * u, u) }
}

private fun DrawScope.tableBody(W: Double, H: Double, u: Double) {
    val wood = rgb(0.55, 0.34, 0.18)
    rect(0.0, 0.0, W, H, vgrad(listOf(wood.lit(0.12), wood, wood.shade(0.3)), 0.0, min(H, 400 * u)))
    rect(0.0, 0.0, W, 3 * u, wood.lit(0.35))
    var y = 14 * u
    while (y < H) {
        val g = Path(); g.m(0.0, y); g.c(W * 0.3, y - 4 * u, W * 0.7, y + 6 * u, W, y + 3 * u)
        strokePath(g, Color.Black.op(0.08), u)
        y += 18 * u
    }
}
