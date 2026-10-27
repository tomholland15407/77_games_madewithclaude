package com.gogs.bananagame.games.airhockey

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** Reflex — Air Hockey (iOS AirHockeyGame.swift): first to N goals against the AI. */
object AirHockeyGame {
    val definition = GameDefinition(
        id = "air-hockey",
        title = "Air Hockey",
        genre = Genre.REFLEX,
        locksFeed = true,
        manual = GameManual(
            bullets = listOf(
                "Drag your paddle in the bottom half of the table to strike the puck.",
                "Flick it to launch the puck into the AI's goal up top.",
                "First to the target number of goals wins.",
                "If the AI gets there first, or the clock runs out, you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Kéo vợt của bạn ở nửa dưới bàn để đánh quả bóng.",
                "Búng nó để phóng bóng vào khung thành AI phía trên.",
                "Ai đạt đủ số bàn thắng mục tiêu trước sẽ thắng.",
                "Nếu AI đạt trước, hoặc hết giờ, bạn sẽ về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> AirHockeyView(level, onWin, onFail) }
    )
}

private const val PUCK_R = 0.035
private const val MOUTH_L = 0.3
private const val MOUTH_R = 0.7
private const val AI_R = 0.075

private class Rink(val level: Int) {
    val goalsToWin = level
    val playerR = max(0.06, 0.105 - level * 0.005)
    val baseSpeed = 0.48 + level * 0.06
    val maxSpeed = 1.35 + level * 0.14
    val aiSpeed = 0.26 + level * 0.05
    val timeLimit = 18.0 + level * 9.0
    var playing = true
    var px = 0.5; var py = 0.5
    var vx = 0.0; var vy = 0.5
    var pp = P(0.5, 0.82)
    var lastP = P(0.5, 0.82)
    var pvx = 0.0; var pvy = 0.0
    var ax = 0.5; var ay = 0.12
    var playerScore = 0; var aiScore = 0
    var timeLeft = timeLimit
    var serveCD = 0.0; var playerCD = 0.0; var aiCD = 0.0
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    fun serve(dir: Double) {
        px = 0.5; py = 0.5
        val a = rnd(-0.5, 0.5)
        vx = baseSpeed * sin(a); vy = baseSpeed * dir * abs(cos(a))
        serveCD = 0.5
    }

    fun step(dt: Double) {
        if (serveCD > 0) serveCD -= dt
        if (playerCD > 0) playerCD -= dt
        if (aiCD > 0) aiCD -= dt
        pvx = (pp.x - lastP.x) / dt; pvy = (pp.y - lastP.y) / dt
        lastP = pp
        val advancing = py < 0.32 && vy < 0
        val tY = if (advancing) min(0.34, py) else 0.13
        val tX = min(0.75, max(0.25, px))
        val s = aiSpeed * dt
        ax += max(-s, min(s, tX - ax)); ay += max(-s, min(s, tY - ay))
        var nx = px + vx * dt; var ny = py + vy * dt
        if (nx < PUCK_R) { nx = PUCK_R; vx = abs(vx) }
        if (nx > 1 - PUCK_R) { nx = 1 - PUCK_R; vx = -abs(vx) }
        if (ny < PUCK_R) {
            if (nx > MOUTH_L && nx < MOUTH_R) { px = nx; py = ny; scored(true); return } else { ny = PUCK_R; vy = abs(vy) }
        }
        if (ny > 1 - PUCK_R) {
            if (nx > MOUTH_L && nx < MOUTH_R) { if (ny > 1) { px = nx; py = ny; scored(false); return } }
            else { ny = 1 - PUCK_R; vy = -abs(vy) }
        }
        px = nx; py = ny
        collide(pp.x, pp.y, playerR, pvx, pvy, false)
        collide(ax, ay, AI_R, 0.0, 0.0, true)
        clamp()
    }

    fun collide(qx: Double, qy: Double, r: Double, qvx: Double, qvy: Double, isAI: Boolean) {
        if (if (isAI) aiCD > 0 else playerCD > 0) return
        val minD = PUCK_R + r
        val dx = px - qx; val dy = py - qy
        val d = hypot(dx, dy)
        if (d >= minD || d <= 0.0001) return
        val nx = dx / d; val ny = dy / d
        px = qx + nx * minD; py = qy + ny * minD
        val dot = vx * nx + vy * ny
        if (dot < 0) { vx -= 2 * dot * nx; vy -= 2 * dot * ny }
        val share = if (isAI) 0.5 else 1.1
        vx += qvx * share; vy += qvy * share
        val bounce = if (isAI) 1.0 else 1.7
        vx *= bounce; vy *= bounce
        val push = baseSpeed * (if (isAI) 0.2 else 0.95)
        vx += nx * push; vy += ny * push
        if (isAI) aiCD = 0.15 else playerCD = 0.15
    }

    fun clamp() {
        var sp = hypot(vx, vy)
        if (sp < baseSpeed * 0.7 && sp > 0.0001) { val k = baseSpeed * 0.7 / sp; vx *= k; vy *= k; sp = baseSpeed * 0.7 }
        if (sp > maxSpeed) { val k = maxSpeed / sp; vx *= k; vy *= k }
    }

    fun scored(player: Boolean) {
        if (player) { playerScore++; Haptics.tap(); SoundManager.tap() } else { aiScore++; SoundManager.error() }
        if (playerScore >= goalsToWin) { win(); return }
        if (aiScore >= goalsToWin) { fail(); return }
        serve(if (player) -1.0 else 1.0)
    }

    fun win() { if (!playing) return; playing = false; Haptics.tap(); SoundManager.tap(); onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }
}

private const val DEMO_ANGLE = 0.35
private val DEMO_START = P(0.5, 0.82)
private val DEMO_GUARD = P(0.53, 0.88)
private val DEMO_FLICK = P(0.05, -0.3)
private const val DEMO_STRIKE = 1.0
private const val DEMO_FLICK_DUR = 0.24

@Composable
private fun AirHockeyView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val rink = remember { Rink(level) }
    rink.onWin = onWin; rink.onFail = onFail
    var area by remember { mutableStateOf(P.zero) }
    var demoTick by remember { mutableStateOf(0) }
    val tm = rememberTextMeasurer()
    val handP = rememberHand()
    var started by remember { mutableStateOf(false) }
    val tick by rememberFrameLoop(running = !isDemo) { dt ->
        if (!rink.playing) return@rememberFrameLoop
        if (!started) { started = true; rink.serve(if (rndBool()) 1.0 else -1.0); rink.timeLeft = rink.timeLimit }
        rink.timeLeft = max(0.0, rink.timeLeft - dt)
        rink.step(max(dt, 0.001))
        if (rink.timeLeft <= 0) rink.fail()
    }

    LaunchedEffect(Unit) {
        if (!isDemo) return@LaunchedEffect
        fun demoPaddle(t: Double): P {
            val s = DEMO_START; val w = DEMO_GUARD
            if (t < DEMO_STRIKE - 0.35) {
                var f = min(1.0, t / max(0.01, DEMO_STRIKE - 0.35)); f = f * f * (3 - 2 * f)
                return P(s.x + (w.x - s.x) * f, s.y + (w.y - s.y) * f)
            }
            if (t < DEMO_STRIKE) return w
            var f = min(1.0, (t - DEMO_STRIKE) / DEMO_FLICK_DUR); f = 1 - (1 - f) * (1 - f)
            return P(min(1 - rink.playerR, max(rink.playerR, w.x + DEMO_FLICK.x * f)), min(1 - rink.playerR, max(0.52, w.y + DEMO_FLICK.y * f)))
        }
        val dt = 1.0 / 60
        while (isActive) {
            rink.playing = true; rink.playerScore = 0; rink.aiScore = 0
            rink.pp = DEMO_START; rink.lastP = DEMO_START; rink.pvx = 0.0; rink.pvy = 0.0
            rink.ax = 0.5; rink.ay = 0.12; rink.playerCD = 0.0; rink.aiCD = 0.0
            rink.px = 0.5; rink.py = 0.5
            rink.vx = rink.baseSpeed * sin(DEMO_ANGLE); rink.vy = rink.baseSpeed * abs(cos(DEMO_ANGLE))
            rink.serveCD = 0.5; rink.timeLeft = rink.timeLimit
            demoTick++
            delay(500)
            var t = 0.0
            while (isActive && rink.playing && t < 4.0) {
                t += dt
                rink.pp = demoPaddle(t)
                rink.step(dt)
                demoTick++
                delay(16)
            }
            delay(1300)
        }
    }

    Box(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 14.dp else 26.dp))
            .background(Brush.linearGradient(listOf(rgb(0.2, 0.26, 0.4), rgb(0.08, 0.11, 0.2))))
            .padding(if (isDemo) 7.dp else 9.dp)
    ) {
        Canvas(
            Modifier.fillMaxSize().onSizeChanged { area = P(it.width.toDouble(), it.height.toDouble()) }
                .then(if (isDemo) Modifier else Modifier.touchDrag(
                    onStart = { p -> movePaddle(rink, p, area) },
                    onMove = { _, p -> movePaddle(rink, p, area) }))
        ) {
            tick; demoTick
            val w = size.width.toDouble(); val h = size.height.toDouble()
            if (w <= 1 || h <= 1) return@Canvas
            table(w, h)
            score(tm, rink.aiScore, L("AI", "MÁY"), w * 0.8, h * 0.3, w * 0.2)
            score(tm, rink.playerScore, L("YOU", "BẠN"), w * 0.8, h * 0.7, w * 0.2)
            if (!isDemo) clock(tm, ceil(rink.timeLeft).toInt(), w * 0.12, h * 0.5, rink.timeLeft < rink.timeLimit * 0.3)
            puck(rink.px * w, rink.py * h, PUCK_R * w, rink.vx * w, rink.vy * h)
            mallet(rink.ax * w, rink.ay * h, AI_R * w, rgb(0.9, 0.16, 0.16))
            val pR = rink.playerR * w
            mallet(rink.pp.x * w, rink.pp.y * h, pR, BananaTheme.banana)
            if (isDemo) {
                val hs = 26.0 * density * 1.2
                hand(handP, rink.pp.x * w + pR * 0.7 - hs * 0.4, rink.pp.y * h + pR * 0.9 - hs * 0.3, hs)
            }
        }
    }
}

private fun movePaddle(r: Rink, p: P, area: P) {
    if (!r.playing || area.x <= 0) return
    val fx = min(1 - r.playerR, max(r.playerR, p.x / area.x))
    val fy = min(1 - r.playerR, max(0.52, p.y / area.y))
    r.pp = P(fx, fy)
}

private fun DrawScope.mallet(px: Double, py: Double, r: Double, color: Color) {
    circle(px + r * 0.12, py + r * 0.2, r, Color.Black.op(0.28))
    circle(px, py, r, radial(listOf(color.lit(0.35), color, color.shade(0.35)), px - r * 0.3, py - r * 0.35, r * 1.3))
    circleStroke(px, py, r, color.shade(0.55), max(1.0, r * 0.06))
    circleStroke(px, py, r * 0.78, color.shade(0.25).op(0.8), max(1.0, r * 0.05))
    circle(px + r * 0.05, py + r * 0.08, r * 0.5, Color.Black.op(0.25))
    circle(px, py, r * 0.46, radial(listOf(color.lit(0.55), color.lit(0.1), color.shade(0.3)), px - r * 0.15, py - r * 0.2, r * 0.55))
    circle(px - r * 0.16, py - r * 0.18, r * 0.14, Color.White.op(0.75))
}

private fun DrawScope.puck(px: Double, py: Double, r: Double, vx: Double, vy: Double) {
    if (hypot(vx, vy) > 1) {
        val tx = px - vx * 0.07; val ty = py - vy * 0.07
        drawLine(lin(listOf(gray(0.2).op(0.35), Color.Transparent), px, py, tx, ty), off(px, py), off(tx, ty), (r * 1.6).f,
            androidx.compose.ui.graphics.StrokeCap.Round)
    }
    circle(px + r * 0.12, py + r * 0.2, r, Color.Black.op(0.25))
    circle(px, py, r, radial(listOf(gray(0.3), gray(0.08)), px - r * 0.3, py - r * 0.3, r * 1.2))
    circleStroke(px, py, r * 0.68, Color.White.op(0.7), max(1.0, r * 0.12))
}

private fun DrawScope.score(tm: TextMeasurer, value: Int, label: String, x: Double, y: Double, s: Double) {
    val ink = rgb(0.12, 0.25, 0.55, 0.28)
    text(tm, "$value", x, y, s, ink, FontWeight.Black)
    text(tm, label, x, y + s * 0.62, s * 0.2, ink, FontWeight.ExtraBold)
}

private fun DrawScope.clock(tm: TextMeasurer, seconds: Int, x: Double, y: Double, low: Boolean) {
    val u = density.toDouble()
    rrect(x - 24 * u, y - 14 * u, 48 * u, 28 * u, 6 * u, rgb(0.08, 0.1, 0.16))
    rrectStroke(x - 24 * u, y - 14 * u, 48 * u, 28 * u, 6 * u, rgb(0.3, 0.35, 0.45), 1.5 * u)
    val led = if (low) rgb(1.0, 0.25, 0.2) else rgb(1.0, 0.62, 0.2)
    glowText(tm, "%02d".format(max(0, seconds)), x, y, 18 * u, led, led.lit(0.3), 2.5 * u, FontWeight.Bold, Mono)
}

private fun DrawScope.table(w: Double, h: Double) {
    val u = density.toDouble()
    drawRect(lin(listOf(rgb(0.93, 0.97, 1.0), rgb(0.84, 0.91, 0.98)), 0.0, 0.0, w, h))
    val step = max(12 * u, w / 24)
    var y = step / 2
    val hole = rgb(0.55, 0.65, 0.78, 0.7)
    while (y < h) { var x = step / 2; while (x < w) { circle(x, y, 0.9 * u, hole); x += step }; y += step }
    val red = rgb(0.88, 0.18, 0.2); val blue = rgb(0.2, 0.42, 0.85)
    rect(0.0, h / 2 - 2 * u, w, 4 * u, red.op(0.85))
    circleStroke(w / 2, h / 2, w * 0.16, red.op(0.85), 3 * u)
    circle(w / 2, h / 2, 5 * u, red)
    for (fy in listOf(0.3, 0.7)) rect(0.0, h * fy - 2 * u, w, 4 * u, blue.op(0.75))
    for (top in listOf(true, false)) {
        val gw = (MOUTH_R - MOUTH_L) * w; val gx = MOUTH_L * w
        val cy = if (top) 0.0 else h
        val crease = Path()
        crease.arc(gx + gw / 2, cy, gw * 0.6, if (top) 0.0 else PI, if (top) PI else 2 * PI, moveFirst = true)
        strokePath(crease, blue.op(0.75), 3 * u)
        rrect(gx, if (top) -6 * u else h - 6 * u, gw, 12 * u, 5 * u, rgb(0.05, 0.06, 0.1))
    }
}
