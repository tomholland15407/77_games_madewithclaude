package com.gogs.bananagame.games.quickdraw

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** Reflex — Quick Draw (iOS QuickDrawGame.swift): a Western main-street duel; shoot on the third banana. */
object QuickDrawGame {
    val definition = GameDefinition(
        id = "quick-draw",
        title = "Quick Draw",
        genre = Genre.REFLEX,
        manual = GameManual(
            bullets = listOf(
                "A high-noon duel. Three bananas light up one at a time.",
                "The instant the THIRD one appears, tap anywhere to shoot before your rival.",
                "Tapping before the third banana means you drew too soon and lose.",
            ),
            bulletsVI = listOf(
                "Một cuộc đấu súng giữa trưa. Ba quả chuối sáng lên lần lượt.",
                "Ngay khi quả THỨ BA xuất hiện, chạm bất kỳ đâu để bắn trước đối thủ.",
                "Chạm trước quả chuối thứ ba nghĩa là bạn rút súng quá sớm và thua.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> QuickDrawView(level, onWin, onFail) }
    )
}

private enum class QPhase { COUNTING, DRAW, DONE }

private class QLayout(val w: Double, val h: Double, val demo: Boolean) {
    val baseY = h * (if (demo) 0.6 else 0.62)
    val feetY = h * 0.9
    val cowboyH = h * (if (demo) 0.44 else 0.37)
    val cowboyW = w * 0.3
    val cowboyY = feetY - cowboyH * 0.47
    val saloonTop = baseY - baseY * 0.56
    val lantern = min(w * 0.11, h * (if (demo) 0.15 else 0.085))
    val bannerY = h * (if (demo) 0.17 else 0.19)
    val ropeA = P(w * 0.32, saloonTop + h * 0.035)
    val ropeB = P(w * 0.68, saloonTop + h * 0.035)
    val sag = h * (if (demo) 0.05 else 0.04)
    fun ropePoint(t: Double): P {
        val cx = (ropeA.x + ropeB.x) / 2; val cy = ropeA.y + sag * 2
        val u = 1 - t
        return P(u * u * ropeA.x + 2 * u * t * cx + t * t * ropeB.x, u * u * ropeA.y + 2 * u * t * cy + t * t * ropeB.y)
    }
    fun lanternPoint(i: Int): P { val p = ropePoint(listOf(0.18, 0.5, 0.82)[i.coerceIn(0, 2)]); return P(p.x, p.y + lantern * 0.72) }
}

@Composable
private fun QuickDrawView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    var phase by remember { mutableStateOf(QPhase.COUNTING) }
    var bananas by remember { mutableIntStateOf(0) }
    var outcome by remember { mutableStateOf<String?>(null) }
    var shooter by remember { mutableStateOf<Boolean?>(null) }     // true = you
    var shotT0 by remember { mutableDoubleStateOf(-10.0) }
    var shakeT0 by remember { mutableDoubleStateOf(-10.0) }
    var tumbleStart by remember { mutableDoubleStateOf(nowSec()) }
    var lanternT0 by remember { mutableStateOf(DoubleArray(3) { -10.0 }) }
    var bannerT0 by remember { mutableDoubleStateOf(-10.0) }
    var rippleT0 by remember { mutableDoubleStateOf(-10.0) }
    val tm = rememberTextMeasurer()
    val tick by rememberFrameLoop(running = true)

    fun light(i: Int) { bananas = i; lanternT0 = lanternT0.copyOf().also { it[i - 1] = nowSec() } }
    fun win() { if (phase == QPhase.DONE) return; phase = QPhase.DONE; Haptics.tap(); SoundManager.tap(); onWin() }
    fun fail() { if (phase == QPhase.DONE) return; phase = QPhase.DONE; SoundManager.error(); onFail() }
    fun shoot() {
        when (phase) {
            QPhase.COUNTING -> { outcome = L("TOO SOON", "QUÁ SỚM"); bannerT0 = nowSec(); fail() }
            QPhase.DRAW -> { outcome = L("GOT HIM", "HẠ GỤC"); bannerT0 = nowSec(); shooter = true; shotT0 = nowSec(); shakeT0 = nowSec(); win() }
            QPhase.DONE -> {}
        }
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            val rhythm = listOf(0.75, 0.55, 0.85)
            while (isActive) {
                phase = QPhase.COUNTING; bananas = 0; outcome = null; shooter = null; tumbleStart = nowSec(); lanternT0 = DoubleArray(3) { -10.0 }
                delay(400)
                for (i in 1..3) { delay((rhythm[i - 1] * 1000).toLong()); light(i); SoundManager.tap(); Haptics.tap() }
                phase = QPhase.DRAW; bannerT0 = nowSec()
                delay(200)
                rippleT0 = nowSec()
                shoot()
                delay(1500)
            }
        } else {
            phase = QPhase.COUNTING; bananas = 0; outcome = null; shooter = null; tumbleStart = nowSec()
            val rhythms = listOf(
                listOf(0.60..0.90, 0.60..0.90, 0.60..0.90), listOf(0.90..1.40, 0.55..0.80, 0.25..0.45),
                listOf(0.25..0.45, 0.55..0.80, 0.90..1.40), listOf(0.30..0.50, 0.30..0.50, 1.00..1.55),
                listOf(1.00..1.55, 0.30..0.50, 0.30..0.50), listOf(0.50..0.80, 1.05..1.55, 0.35..0.60),
            )
            val rhythm = rhythms.pick()
            for (i in 1..3) {
                delay((rnd(rhythm[i - 1]) * 1000).toLong())
                if (phase != QPhase.COUNTING) return@LaunchedEffect
                light(i); SoundManager.tap(); Haptics.tap()
            }
            phase = QPhase.DRAW; bannerT0 = nowSec()
            val reaction = max(0.16, 0.66 - level * 0.07) + rnd(-0.03, 0.05)
            delay((reaction * 1000).toLong())
            if (phase == QPhase.DRAW) {
                outcome = L("TOO SLOW", "QUÁ CHẬM"); bannerT0 = nowSec()
                shooter = false; shotT0 = nowSec(); shakeT0 = nowSec()
                fail()
            }
        }
    }

    Box(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .graphicsLayer {
                val t = nowSec() - shakeT0
                if (t in 0.0..0.35) { val k = sin(t / 0.35 * PI * 3); translationX = (7 * density * k).toFloat(); translationY = (4.2 * density * k).toFloat() }
            }
            .tapAt { if (!isDemo) shoot() }
    ) {
        Canvas(Modifier.fillMaxSize()) {
            tick
            val w = size.width.toDouble(); val h = size.height.toDouble()
            val lay = QLayout(w, h, isDemo)
            val now = nowSec()
            street(tm, level, lay)
            if (phase == QPhase.COUNTING) tumbleweed(lay, now - tumbleStart)
            for (i in 0 until 3) {
                val p = lay.lanternPoint(i)
                val lit = i < bananas
                val k = if (lit) springK(now - lanternT0[i], 0.22) else 1.0
                lantern(p.x, p.y, lay.lantern, lit, k)
            }
            val youX = w * 0.24; val rivalX = w * 0.76
            gunslinger(youX, lay, true, shooter == true, shooter == false, now - shotT0)
            gunslinger(rivalX, lay, false, shooter == false, shooter == true, now - shotT0)
            shooter?.let { you ->
                val reach = 0.39 * lay.cowboyH
                val fx = if (you) youX + reach else rivalX - reach
                val fy = lay.cowboyY - 0.15 * lay.cowboyH
                muzzleFlash(fx, fy, lay.cowboyH * 0.3, you, now - shotT0)
                particleBurst(fx, fy, now - shotT0, rgb(1.0, 0.8, 0.3), 10, 40.0)
            }
            if (isDemo) tapRipple(w * 0.5, h * 0.66, now - rippleT0)
            val prompt = outcome ?: if (phase == QPhase.DRAW) L("DRAW!", "BẮN!") else ""
            if (prompt.isNotEmpty()) {
                val win = prompt == L("GOT HIM", "HẠ GỤC"); val go = phase == QPhase.DRAW && outcome == null
                val ink = if (go) rgb(1.0, 0.93, 0.75) else if (win) rgb(1.0, 0.85, 0.3) else rgb(1.0, 0.36, 0.3)
                val k = springK(now - bannerT0, 0.25)
                val sz = (if (isDemo) (if (go) 34.0 else 26.0) else (if (go) 52.0 else 38.0)) * density
                val sc = 1.6 - 0.6 * k
                translate((w / 2).f, lay.bannerY.f) {
                    scale(sc.f, sc.f, Offset.Zero) {
                        withAlpha(k.coerceIn(0.0, 1.0)) {
                            text(tm, prompt, 3.0 * density, 3.0 * density, sz, rgb(0.25, 0.1, 0.03), FontWeight.Black, FontFamily.Serif, spacing = (if (isDemo) 2.0 else 3.0) * density)
                            text(tm, prompt, 0.0, 0.0, sz, ink, FontWeight.Black, FontFamily.Serif, spacing = (if (isDemo) 2.0 else 3.0) * density)
                        }
                    }
                }
            }
        }
    }
}

/** A gentle spring-ish ease 0→1 (overshooting slightly) over roughly `dur` seconds. */
private fun springK(t: Double, dur: Double): Double {
    if (t <= 0) return 0.0
    val x = t / dur
    return 1 - exp(-4.5 * x) * cos(x * 3.2)
}

private val SKY_TOPS = listOf(rgb(0.45, 0.70, 0.95), rgb(0.62, 0.74, 0.90), rgb(0.95, 0.70, 0.42), rgb(0.90, 0.50, 0.30), rgb(0.40, 0.26, 0.42), rgb(0.16, 0.12, 0.28), rgb(0.28, 0.05, 0.08))
private val SKY_BOTTOMS = listOf(rgb(0.85, 0.72, 0.48), rgb(0.88, 0.72, 0.46), rgb(0.86, 0.56, 0.30), rgb(0.98, 0.62, 0.3), rgb(0.62, 0.34, 0.36), rgb(0.14, 0.12, 0.22), rgb(0.36, 0.06, 0.06))
private val SANDS = listOf(rgb(0.86, 0.70, 0.44), rgb(0.83, 0.66, 0.40), rgb(0.76, 0.55, 0.32), rgb(0.62, 0.42, 0.27), rgb(0.36, 0.28, 0.27), rgb(0.2, 0.17, 0.2), rgb(0.26, 0.11, 0.1))
private val DUSK = listOf(0.0, 0.04, 0.14, 0.36, 0.55, 0.68, 0.7)
private val HOURS = listOf(12.0, 2.0, 4.0, 6.0, 8.0, 10.0, 12.0)

private fun qh(n: Double): Double { val v = sin(n * 12.9898) * 43758.5453; return v - floor(v) }

private fun DrawScope.street(tm: TextMeasurer, level: Int, lay: QLayout) {
    val L = max(1, min(level, 7)) - 1
    val w = lay.w; val h = lay.h; val base = lay.baseY; val u = density.toDouble()
    val night = L >= 4
    val tint = if (L == 6) rgb(0.14, 0.02, 0.03) else rgb(0.07, 0.06, 0.12)
    val d = DUSK[L]
    fun tone(c: Color) = c.mix(tint, d)
    rect(0.0, 0.0, w, h, vgrad(listOf(SKY_TOPS[L], SKY_BOTTOMS[L]), 0.0, base))
    if (night) for (k in 0 until 50) circle(qh(k * 1.7) * w, qh(k * 3.1 + 0.5) * base * 0.8, (0.5 + qh(k * 5.3) * 1.1) * u, Color.White.op(0.75))
    sunOrMoon(L, w, h, base)
    mesas(tone(SKY_BOTTOMS[L].mix(rgb(0.55, 0.3, 0.2), 0.45)).shade(0.12), w, base, h)
    rect(0.0, base, w, h - base, vgrad(listOf(SANDS[L].shade(0.1), SANDS[L].lit(0.06)), base, h))
    listOf(lay.feetY - h * 0.1, lay.feetY + h * 0.035).forEachIndexed { k, y ->
        val rut = Path(); rut.m(0.0, y); rut.c(w * 0.3, y - h * 0.012, w * 0.7, y + h * 0.018, w, y + h * 0.01)
        strokePath(rut, SANDS[L].shade(0.18).op(0.55), h * (if (k == 0) 0.008 else 0.012))
    }
    for (k in 0 until 36) {
        val x = qh(k * 2.3 + 9) * w; val y = base + h * 0.03 + qh(k * 4.7 + 1) * (h - base - h * 0.03)
        val r = (0.8 + qh(k * 6.1) * 1.6) * u
        oval(x - r * 1.4, y - r, r * 2.8, r * 2, SANDS[L].shade(0.3).op(0.6))
    }
    val wood1 = tone(rgb(0.72, 0.45, 0.24)); val wood2 = tone(rgb(0.6, 0.36, 0.2)); val wood3 = tone(rgb(0.8, 0.58, 0.34)); val brick = tone(rgb(0.62, 0.28, 0.2))
    val trim = tone(rgb(0.92, 0.82, 0.62)); val deep = tone(rgb(0.25, 0.14, 0.08))
    val glass = if (night) rgb(1.0, 0.78, 0.4) else tone(SKY_TOPS[L].mix(Color.Black, 0.45))
    val store = Rect((-w * 0.04).f, (base - base * 0.38).f, (w * 0.09).f, base.f)
    val saloon = Rect((w * 0.08).f, lay.saloonTop.f, (w * 0.32).f, base.f)
    val bank = Rect((w * 0.68).f, lay.saloonTop.f, (w * 0.92).f, base.f)
    val jail = Rect((w * 0.91).f, (base - base * 0.4).f, (w * 1.04).f, base.f)
    facade(store, wood3, trim, deep)
    window(Rect(store.left + store.width * 0.4f, store.top + store.height * 0.42f, store.left + store.width * 0.84f, store.top + store.height * 0.7f), glass, night, trim)
    facade(jail, wood2, trim, deep)
    window(Rect(jail.left + jail.width * 0.18f, jail.top + jail.height * 0.42f, jail.left + jail.width * 0.6f, jail.top + jail.height * 0.7f), glass, night, trim, bars = true)
    val sg = Rect(jail.left + jail.width * 0.12f, jail.top + jail.height * 0.14f, jail.left + jail.width * 0.82f, jail.top + jail.height * 0.3f)
    sign(sg, deep); star(sg.center.x.toDouble(), sg.center.y.toDouble(), sg.height * 0.36, rgb(0.95, 0.78, 0.3))
    saloonFront(saloon, wood1, trim, deep, glass, night)
    bankFront(tm, bank, brick, trim, deep, glass, night, HOURS[L])
    for (r in listOf(Rect((-w * 0.04).f, (base - h * 0.012).f, (w * 0.33).f, (base + h * 0.016).f), Rect((w * 0.67).f, (base - h * 0.012).f, (w * 1.04).f, (base + h * 0.016).f))) {
        drawRect(tone(rgb(0.62, 0.42, 0.24)), r.topLeft, r.size)
        rect(r.left.toDouble(), r.bottom - r.height * 0.35, r.width.toDouble(), r.height * 0.35, deep.op(0.8))
        var x = r.left.toDouble()
        while (x < r.right) { line(x, r.top.toDouble(), x, r.bottom - r.height * 0.35, deep.op(0.35), 0.8 * u, StrokeCap.Butt); x += h * 0.025 }
    }
    hitchingRail(w * 0.1, w * 0.3, base + h * 0.05, h, tone(rgb(0.5, 0.32, 0.17)))
    barrel(w * 0.33, base - h * 0.055, h * 0.04, h * 0.055, tone(rgb(0.6, 0.38, 0.2)), deep)
    barrel(w * 0.33 + h * 0.035, base - h * 0.045, h * 0.036, h * 0.045, tone(rgb(0.55, 0.34, 0.18)), deep)
    val tx = w * 0.7; val ty = base + h * 0.022; val tw = w * 0.16; val th = h * 0.03
    rect(tx, ty, tw, th, tone(rgb(0.52, 0.33, 0.18)))
    rect(tx + 2 * u, ty + 1.5 * u, tw - 4 * u, th * 0.28, tone(rgb(0.35, 0.55, 0.7)))
    rectStroke(tx, ty, tw, th, tone(rgb(0.52, 0.33, 0.18)).shade(0.4), u)
    val rope = Path(); rope.m(lay.ropeA.x, lay.ropeA.y); rope.q((lay.ropeA.x + lay.ropeB.x) / 2, lay.ropeA.y + lay.sag * 2, lay.ropeB.x, lay.ropeB.y)
    strokePath(rope, tone(rgb(0.3, 0.2, 0.12)), max(1.2 * u, h * 0.004))
    for (i in 0 until 3) {
        val top = lay.ropePoint(listOf(0.18, 0.5, 0.82)[i])
        line(top.x, top.y, top.x, lay.lanternPoint(i).y - lay.lantern * 0.36, tone(rgb(0.3, 0.2, 0.12)), u, StrokeCap.Butt)
    }
    val cactus = tone(rgb(0.24, 0.48, 0.26))
    saguaro(w * 0.035, lay.feetY + h * 0.06, h * 0.24, cactus, false)
    saguaro(w * 0.965, lay.feetY + h * 0.07, h * 0.2, cactus, true)
}

private fun DrawScope.sunOrMoon(L: Int, w: Double, h: Double, base: Double) {
    val cx = w * 0.5
    when (L) {
        0, 1, 2 -> {
            val y = listOf(h * 0.08, h * 0.11, h * 0.17)[L]; val r = w * 0.06
            val core = if (L == 2) rgb(1.0, 0.88, 0.55) else rgb(1.0, 0.97, 0.82)
            drawCircle(androidx.compose.ui.graphics.Brush.radialGradient(0f to core.op(0.55), 0.25f to core.op(0.55), 1f to core.op(0.0), center = off(cx, y), radius = (r * 4).f), (r * 4).f, off(cx, y))
            circle(cx, y, r, core)
        }
        3 -> {
            val y = base - h * 0.03; val r = w * 0.11
            drawCircle(androidx.compose.ui.graphics.Brush.radialGradient(0f to rgb(1.0, 0.6, 0.25, 0.6), 0.3f to rgb(1.0, 0.6, 0.25, 0.6), 1f to Color.Transparent, center = off(cx, y), radius = (r * 3.4).f), (r * 3.4).f, off(cx, y))
            circle(cx, y, r, vgrad(listOf(rgb(1.0, 0.8, 0.4), rgb(0.98, 0.38, 0.16)), y - r, y + r))
        }
        4 -> {
            rect(0.0, base - h * 0.12, w, h * 0.12, vgrad(listOf(Color.Transparent, rgb(1.0, 0.5, 0.3, 0.35)), base - h * 0.12, base))
            moon(cx + w * 0.05, h * 0.1, w * 0.035, gray(0.95), true)
        }
        5 -> moon(cx, h * 0.1, w * 0.055, rgb(0.95, 0.95, 0.88), false)
        else -> moon(cx, h * 0.13, w * 0.085, rgb(0.86, 0.18, 0.12), false)
    }
}

private fun DrawScope.moon(cx: Double, cy: Double, r: Double, color: Color, crescent: Boolean) {
    drawCircle(androidx.compose.ui.graphics.Brush.radialGradient(0f to color.op(0.35), 0.33f to color.op(0.35), 1f to color.op(0.0), center = off(cx, cy), radius = (r * 3).f), (r * 3).f, off(cx, cy))
    if (crescent) {
        val p = Path().apply {
            addOval(Rect((cx - r).f, (cy - r).f, (cx + r).f, (cy + r).f))
            addOval(Rect((cx - r * 0.55).f, (cy - r * 1.15).f, (cx - r * 0.55 + 2 * r).f, (cy - r * 1.15 + 2 * r).f))
            fillType = PathFillType.EvenOdd
        }
        drawPath(p, color); return
    }
    circle(cx, cy, r, color)
    for ((dx, dy, rr) in listOf(Triple(-0.3, -0.2, 0.22), Triple(0.25, 0.25, 0.16), Triple(0.2, -0.35, 0.1))) circle(cx + dx * r, cy + dy * r, rr * r, color.shade(0.14))
}

private fun DrawScope.mesas(color: Color, w: Double, base: Double, h: Double) {
    val p = Path(); p.m(0.0, base)
    for ((x0, height, width) in listOf(Triple(0.0, 0.06, 0.1), Triple(0.2, 0.1, 0.18), Triple(0.38, 0.13, 0.14), Triple(0.55, 0.08, 0.22), Triple(0.78, 0.12, 0.12))) {
        val x = x0 * w; val top = base - height * h; val ww = width * w
        p.l(x, base); p.l(x + ww * 0.12, top); p.l(x + ww * 0.88, top); p.l(x + ww, base)
    }
    p.l(w, base); p.close()
    drawPath(p, color)
}

private fun DrawScope.facade(r: Rect, wood: Color, trim: Color, deep: Color) {
    val u = density.toDouble()
    drawRect(vgrad(listOf(wood.lit(0.06), wood.shade(0.1)), r.top.toDouble(), r.bottom.toDouble()), r.topLeft, r.size)
    var x = r.left + r.width / 7.0
    while (x < r.right) { line(x, r.top.toDouble(), x, r.bottom.toDouble(), deep.op(0.35), 0.8 * u, StrokeCap.Butt); x += r.width / 7.0 }
    val ch = max(3 * u, r.height * 0.05)
    rect(r.left - 2 * u, r.top.toDouble(), r.width + 4 * u, ch, trim)
    rect(r.left - 2 * u, r.top + ch, r.width + 4 * u, 1.5 * u, deep.op(0.6))
    val dx = r.center.x - r.width * 0.14; val dy = r.bottom - r.height * 0.32
    rect(dx.toDouble(), dy.toDouble(), r.width * 0.28, r.height * 0.32, deep)
    rectStroke(dx.toDouble(), dy.toDouble(), r.width * 0.28, r.height * 0.32, trim.op(0.7), u)
}

private fun DrawScope.window(r: Rect, glass: Color, lit: Boolean, frame: Color, bars: Boolean = false) {
    val u = density.toDouble()
    if (lit) {
        val cx = r.center.x.toDouble(); val cy = r.center.y.toDouble()
        drawOval(radial(listOf(glass.op(0.35), glass.op(0.0)), cx, cy, max(r.width, r.height).toDouble()), Offset(r.left - r.width * 0.5f, r.top - r.height * 0.5f), androidx.compose.ui.geometry.Size(r.width * 2, r.height * 2))
    }
    drawRect(glass, r.topLeft, r.size)
    line(r.center.x.toDouble(), r.top.toDouble(), r.center.x.toDouble(), r.bottom.toDouble(), frame.shade(0.3), u, StrokeCap.Butt)
    line(r.left.toDouble(), r.center.y.toDouble(), r.right.toDouble(), r.center.y.toDouble(), frame.shade(0.3), u, StrokeCap.Butt)
    if (bars) for (k in 1 until 4) { val x = r.left + r.width * k / 4.0; line(x, r.top.toDouble(), x, r.bottom.toDouble(), frame.shade(0.3), u, StrokeCap.Butt) }
    drawRect(frame, r.topLeft, r.size, style = Stroke((1.5 * u).f))
}

private fun DrawScope.sign(r: Rect, board: Color) {
    rrect(r.left.toDouble(), r.top.toDouble(), r.width.toDouble(), r.height.toDouble(), 2.0 * density, board)
    rrectStroke(r.left.toDouble(), r.top.toDouble(), r.width.toDouble(), r.height.toDouble(), 2.0 * density, rgb(0.9, 0.8, 0.6, 0.6), density.toDouble())
}

private fun DrawScope.star(cx: Double, cy: Double, r: Double, color: Color) {
    val pts = (0 until 10).map { k -> val a = -PI / 2 + k * PI / 5; val rr = if (k % 2 == 0) r else r * 0.45; P(cx + cos(a) * rr, cy + sin(a) * rr) }
    drawPath(polyPath(pts), color)
}

private fun DrawScope.saloonFront(r: Rect, wood: Color, trim: Color, deep: Color, glass: Color, lit: Boolean) {
    val u = density.toDouble()
    facade(r, wood, trim, deep)
    val sx = r.center.x - r.width * 0.2; val sy = r.top - r.height * 0.06
    rect(sx.toDouble(), sy.toDouble(), r.width * 0.4, r.height * 0.06 + 2 * u, wood)
    rect(sx - 2 * u, sy.toDouble(), r.width * 0.4 + 4 * u, max(2.5 * u, r.height * 0.03), trim)
    val s = Rect(r.left + r.width * 0.1f, r.top + r.height * 0.09f, r.left + r.width * 0.9f, r.top + r.height * 0.22f)
    sign(s, deep)
    val mx = s.center.x - s.height * 0.3; val my = s.top + s.height * 0.25; val mw = s.height * 0.5; val mh = s.height * 0.6
    val beer = rgb(0.98, 0.75, 0.25)
    rrect(mx.toDouble(), my.toDouble(), mw.toDouble(), mh.toDouble(), 2 * u, beer)
    oval(mx - u, my - s.height * 0.14, mw + 2 * u, s.height * 0.26, Color.White)
    ellipseStroke(mx + mw - u + mw * 0.25, my + mh * 0.2 + mh * 0.25, mw * 0.25, mh * 0.25, beer, 1.5 * u)
    val balY = r.top + r.height * 0.52
    for (k in 0 until 2) window(Rect(r.left + r.width * (0.16f + k * 0.44f), r.top + r.height * 0.28f, r.left + r.width * (0.4f + k * 0.44f), r.top + r.height * 0.46f), glass, lit, trim)
    rect(r.left - r.width * 0.04, balY.toDouble(), r.width * 1.08, max(3 * u, r.height * 0.03), deep)
    val ry = balY - r.height * 0.07
    line(r.left - r.width * 0.04, ry.toDouble(), r.right + r.width * 0.04, ry.toDouble(), trim.op(0.85), 1.2 * u, StrokeCap.Butt)
    var x = r.left.toDouble()
    while (x <= r.right + 1) { line(x, ry.toDouble(), x, balY.toDouble(), trim.op(0.85), 1.2 * u, StrokeCap.Butt); x += r.width / 10.0 }
    for (px in listOf(r.left + r.width * 0.02, r.right - r.width * 0.02)) rect(px - 1.5 * u, balY.toDouble(), 3 * u, (r.bottom - balY).toDouble(), deep)
    val dx = r.center.x - r.width * 0.14; val dy = r.bottom - r.height * 0.32; val dw = r.width * 0.28; val dh = r.height * 0.32
    rect(dx.toDouble(), dy.toDouble(), dw.toDouble(), dh.toDouble(), if (lit) rgb(1.0, 0.72, 0.35) else deep)
    for (k in 0 until 2) {
        val bx = dx + k * dw * 0.5 + u; val by = dy + dh * 0.28; val bw = dw * 0.5 - 2 * u; val bh = dh * 0.42
        rrect(bx, by.toDouble(), bw, bh.toDouble(), 1.5 * u, wood.lit(0.12))
        var y = by + bh * 0.2
        while (y < by + bh) { line(bx + u, y.toDouble(), bx + bw - u, y.toDouble(), deep.op(0.6), 0.8 * u, StrokeCap.Butt); y += bh * 0.2f }
    }
    for (k in 0 until 2) {
        val wx = if (k == 0) r.left + r.width * 0.06f else r.right - r.width * 0.26f
        window(Rect(wx, r.bottom - r.height * 0.28f, wx + r.width * 0.2f, r.bottom - r.height * 0.12f), glass, lit, trim)
    }
}

private fun DrawScope.bankFront(tm: TextMeasurer, r: Rect, brick: Color, trim: Color, deep: Color, glass: Color, lit: Boolean, hour: Double) {
    val u = density.toDouble()
    drawRect(brick, r.topLeft, r.size)
    val course = max(3 * u, r.height * 0.035)
    var y = r.top + course; var row = 0
    while (y < r.bottom) {
        line(r.left.toDouble(), y, r.right.toDouble(), y, trim.op(0.22), 0.6 * u, StrokeCap.Butt)
        var x = r.left + (if (row % 2 == 0) 0.0 else course)
        while (x < r.right) { line(x, y - course, x, y, trim.op(0.22), 0.6 * u, StrokeCap.Butt); x += course * 2 }
        y += course; row++
    }
    drawPath(polyPath(r.left - 3 * u, r.top.toDouble(), r.center.x.toDouble(), r.top - r.height * 0.13, r.right + 3 * u, r.top.toDouble()), trim)
    rect(r.left - 3 * u, r.top.toDouble(), r.width + 6 * u, max(3 * u, r.height * 0.04), trim.shade(0.08))
    val cx = r.center.x.toDouble(); val cy = r.top + r.height * 0.1; val cr = r.width * 0.13
    circle(cx, cy, cr + 2 * u, deep)
    circle(cx, cy, cr, if (lit) rgb(1.0, 0.93, 0.7) else rgb(0.98, 0.95, 0.86))
    for (k in 0 until 12) {
        val a = k / 12.0 * 2 * PI
        line(cx + sin(a) * cr * 0.78, cy - cos(a) * cr * 0.78, cx + sin(a) * cr * 0.92, cy - cos(a) * cr * 0.92, deep, u, StrokeCap.Butt)
    }
    val ha = (hour % 12) / 12 * 2 * PI
    line(cx, cy, cx + sin(ha) * cr * 0.5, cy - cos(ha) * cr * 0.5, deep, max(1.2 * u, cr * 0.13))
    line(cx, cy, cx, cy - cr * 0.78, deep, max(1.2 * u, cr * 0.13))
    for (px in listOf(r.left + r.width * 0.06, r.right - r.width * 0.14)) rect(px.toDouble(), r.top + r.height * 0.22, r.width * 0.08, r.height * 0.78, trim.shade(0.05))
    for (k in 0 until 2) window(Rect(r.left + r.width * (0.22f + k * 0.34f), r.top + r.height * 0.3f, r.left + r.width * (0.44f + k * 0.34f), r.top + r.height * 0.54f), glass, lit, trim, bars = true)
    val dx = r.center.x - r.width * 0.12; val dy = r.bottom - r.height * 0.3
    rrect(dx.toDouble(), dy.toDouble(), r.width * 0.24, r.height * 0.3, u, deep)
    rectStroke(dx.toDouble(), dy.toDouble(), r.width * 0.24, r.height * 0.3, trim, 1.2 * u)
    val sh = Rect(r.center.x - r.width * 0.16f, r.top + r.height * 0.6f, r.center.x + r.width * 0.16f, r.top + r.height * 0.7f)
    sign(sh, deep)
    text(tm, "$", sh.center.x.toDouble(), sh.center.y.toDouble(), sh.height * 0.8, rgb(0.95, 0.78, 0.3), FontWeight.Black, FontFamily.Serif)
}

private fun DrawScope.hitchingRail(x0: Double, x1: Double, y: Double, h: Double, color: Color) {
    val lw = max(2.0 * density, h * 0.007)
    line(x0, y - h * 0.045, x1, y - h * 0.045, color, lw)
    for (x in listOf(x0 + 2 * density, x1 - 2 * density)) line(x, y - h * 0.05, x, y, color, lw)
}

private fun DrawScope.barrel(x: Double, y: Double, w: Double, h: Double, wood: Color, hoop: Color) {
    rrect(x, y, w, h, w * 0.3, wood)
    for (f in listOf(0.22, 0.78)) line(x, y + h * f, x + w, y + h * f, hoop, 1.5 * density, StrokeCap.Butt)
}

private fun DrawScope.saguaro(bx: Double, by: Double, height: Double, color: Color, flip: Boolean) {
    val s = if (flip) -1.0 else 1.0
    val lw = height * 0.16
    val trunk = Path(); trunk.m(bx, by); trunk.l(bx, by - height)
    val arms = Path()
    arms.m(bx, by - height * 0.45); arms.q(bx + s * height * 0.26, by - height * 0.45, bx + s * height * 0.26, by - height * 0.72)
    arms.m(bx, by - height * 0.6); arms.q(bx - s * height * 0.2, by - height * 0.6, bx - s * height * 0.2, by - height * 0.85)
    val outline = color.shade(0.45)
    strokePath(trunk, outline, lw + 3 * density); strokePath(arms, outline, lw * 0.72 + 3 * density)
    strokePath(trunk, color, lw); strokePath(arms, color, lw * 0.72)
    line(bx - lw * 0.18, by, bx - lw * 0.18, by - height * 0.95, color.shade(0.25), density.toDouble(), StrokeCap.Butt)
    line(bx + lw * 0.18, by, bx + lw * 0.18, by - height * 0.95, color.shade(0.25), density.toDouble(), StrokeCap.Butt)
}

private fun DrawScope.lantern(cx: Double, cy: Double, size: Double, lit: Boolean, k: Double) {
    val sc = if (lit) 0.9 + 0.22 * k else 0.9
    translate(cx.f, cy.f) {
        scale(sc.f, sc.f, Offset.Zero) {
            if (lit) {
                val gs = 0.5 + 0.5 * k
                circle(0.0, 0.0, size * gs, radial(listOf(rgb(1.0, 0.9, 0.4, 0.85 * min(1.0, k)), rgb(1.0, 0.8, 0.2, 0.0)), 0.0, 0.0, size * gs))
            }
            val r = size * 0.42
            if (lit) FruitArt.draw(this, FruitKind.BANANA, 0.0, r * 0.12, r)
            else drawIntoCanvas { c ->
                val m = ColorMatrix().apply { setToSaturation(0.15f) }
                val b = -0.38f * 255f
                val dim = ColorMatrix(floatArrayOf(1f, 0f, 0f, 0f, b, 0f, 1f, 0f, 0f, b, 0f, 0f, 1f, 0f, b, 0f, 0f, 0f, 0.85f, 0f))
                m.timesAssign(dim)
                c.saveLayer(Rect(-size.f, -size.f, size.f, size.f), Paint().apply { colorFilter = ColorFilter.colorMatrix(m) })
                FruitArt.draw(this, FruitKind.BANANA, 0.0, r * 0.12, r)
                c.restore()
            }
        }
    }
}

private fun DrawScope.tumbleweed(lay: QLayout, t: Double) {
    val r = lay.h * 0.035
    val x = lay.w + r * 2 - t * lay.w / 3.6
    if (x <= -r * 2) return
    val hop = abs(sin(t * 5)) * r * 0.5
    val cx = x; val cy = lay.feetY - lay.h * 0.07 - r - hop
    oval(cx - r, lay.feetY - lay.h * 0.07 - r * 0.25, r * 2, r * 0.5, Color.Black.op(0.15))
    translate(cx.f, cy.f) {
        rotate((-x / r * 180 / PI).f, Offset.Zero) {
            for (k in 0 until 8) rotate((k * 0.8 * 180 / PI).f, Offset.Zero) {
                ellipseStroke(0.0, 0.0, r * 0.95, r * 0.45, rgb(0.55, 0.4, 0.22), max(1.0, r * 0.07))
            }
            circleStroke(0.0, 0.0, r, rgb(0.45, 0.32, 0.17), max(1.0, r * 0.05))
        }
    }
}

/** Gunslinger at x: stick figure, gear and hat; topples away when hit, recoils when firing. */
private fun DrawScope.gunslinger(x: Double, lay: QLayout, you: Boolean, fired: Boolean, hit: Boolean, t: Double) {
    val h = lay.cowboyH; val w = lay.cowboyW
    val flip = if (you) 1.0 else -1.0
    val color = if (you) BananaTheme.banana else rgb(0.88, 0.26, 0.28)
    val fallK = if (hit) springK(t, 0.35).coerceIn(0.0, 1.1) else 0.0
    val hatK = if (hit) min(1.0, t / 0.55).let { 1 - (1 - it) * (1 - it) } else 0.0
    val recoil = if (fired) -flip * 6 * density * min(1.0, t / 0.12) else 0.0
    val top = lay.cowboyY - h / 2
    val bottomY = top + h
    withAlpha(if (hit) 1 - 0.3 * min(1.0, fallK) else 1.0) {
        translate((x + recoil).f, bottomY.f) {
            rotate((flip * 82 * fallK).f, Offset.Zero) {
                scale(flip.f, 1f, Offset.Zero) {
                    translate(0f, (-h).f) {
                        val fx = -w / 2
                        stickFigure(if (fired) StickPose.firing else StickPose.standing, fx, 0.0, w, h, color, gun = true)
                        gear(h, !you)
                        if (hatK < 1) withAlpha(1 - hatK) {
                            translate((-h * 0.3 * hatK).f, (-h * 0.32 * hatK).f) {
                                rotate((-150 * hatK).f, off(0.0, h * 0.08)) { hat(h, !you) }
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun DrawScope.hat(h: Double, outlaw: Boolean) {
    fun p(x: Double, y: Double) = P(x * h, y * h)
    val felt = if (outlaw) rgb(0.14, 0.12, 0.13) else rgb(0.86, 0.74, 0.54)
    val band = if (outlaw) rgb(0.75, 0.75, 0.8) else rgb(0.4, 0.24, 0.12)
    val edge = rgb(0.05, 0.05, 0.09)
    val crown = Path()
    p(-0.085, 0.1).let { crown.m(it.x, it.y) }; p(-0.078, 0.028).let { crown.l(it.x, it.y) }
    crown.q(-0.04 * h, 0.0, 0.0, 0.042 * h); crown.q(0.04 * h, 0.0, 0.078 * h, 0.028 * h); crown.l(0.085 * h, 0.1 * h); crown.close()
    val brim = Path(); brim.m(-0.2 * h, 0.078 * h); brim.q(0.0, 0.14 * h, 0.2 * h, 0.078 * h); brim.q(0.0, 0.1 * h, -0.2 * h, 0.078 * h); brim.close()
    for (s in listOf(crown, brim)) drawPath(s, edge, style = Stroke((h * 0.022).f, join = StrokeJoin.Round))
    drawPath(crown, felt); drawPath(brim, felt.shade(0.08))
    rect(-0.084 * h, 0.078 * h, 0.168 * h, 0.016 * h, band)
}

private fun DrawScope.gear(h: Double, outlaw: Boolean) {
    val edge = rgb(0.05, 0.05, 0.09)
    val cloth = Path()
    if (outlaw) { cloth.m(-0.1 * h, 0.155 * h); cloth.l(0.1 * h, 0.155 * h); cloth.q(0.1 * h, 0.24 * h, 0.02 * h, 0.3 * h); cloth.l(-0.09 * h, 0.22 * h); cloth.close() }
    else { cloth.m(-0.06 * h, 0.24 * h); cloth.l(0.06 * h, 0.24 * h); cloth.l(0.015 * h, 0.31 * h); cloth.close() }
    drawPath(cloth, edge, style = Stroke((h * 0.018).f, join = StrokeJoin.Round))
    drawPath(cloth, if (outlaw) rgb(0.2, 0.17, 0.2) else rgb(0.82, 0.14, 0.16))
    if (outlaw) for ((x, y) in listOf(-0.04 to 0.19, 0.04 to 0.2, 0.0 to 0.24, 0.05 to 0.25)) circle(x * h, y * h, 0.008 * h, Color.White.op(0.75))
    line(-0.05 * h, 0.585 * h, 0.05 * h, 0.585 * h, edge, h * 0.04)
    line(-0.05 * h, 0.585 * h, 0.05 * h, 0.585 * h, rgb(0.42, 0.25, 0.12), h * 0.026)
    rect(-0.012 * h, 0.575 * h, 0.024 * h, 0.02 * h, rgb(0.95, 0.78, 0.3))
    rrect(0.035 * h, 0.59 * h, 0.035 * h, 0.085 * h, 0.01 * h, rgb(0.42, 0.25, 0.12))
    rrectStroke(0.035 * h, 0.59 * h, 0.035 * h, 0.085 * h, 0.01 * h, edge, h * 0.01)
}

private fun DrawScope.muzzleFlash(cx: Double, cy: Double, size: Double, facingRight: Boolean, t: Double) {
    if (t < 0 || t > 0.5) return
    val k = 1 - (1 - t / 0.5) * (1 - t / 0.5)
    val dir = if (facingRight) 1.0 else -1.0
    val sc = 0.4 + 0.75 * k
    withAlpha(1 - k) {
        translate(cx.f, cy.f) {
            scale(sc.f, sc.f, Offset.Zero) {
                val pts = (0 until 12).map { i ->
                    val a = i / 12.0 * 2 * PI
                    val long = if (abs(cos(a)) > 0.9 && cos(a) * dir > 0) 1.0 else 0.62
                    val rr = (if (i % 2 == 0) long else 0.28) * size * 0.5
                    P(cos(a) * rr, sin(a) * rr * 0.8)
                }
                drawPath(polyPath(pts), radial(listOf(Color.White, rgb(1.0, 0.88, 0.35), rgb(1.0, 0.45, 0.1)), 0.0, 0.0, size * 0.5))
            }
        }
    }
    val ss = 0.6 + 1.0 * k
    circle(cx + dir * (size * 0.1 + size * 0.45 * k), cy - size * 0.35 * k, size * 0.25 * ss, gray(0.85).op(0.55 * 0.8 * (1 - k)))
}
