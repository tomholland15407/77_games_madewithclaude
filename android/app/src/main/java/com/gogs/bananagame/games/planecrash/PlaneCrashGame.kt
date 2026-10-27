package com.gogs.bananagame.games.planecrash

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.random.Random

/** Reflex — Plane Crash (iOS PlaneCrashGame.swift): a cash-out gamble; reach the 70M house. */
object PlaneCrashGame {
    val definition = GameDefinition(
        id = "plane-crash",
        title = "Plane Crash",
        genre = Genre.REFLEX,
        manual = GameManual(
            bullets = listOf(
                "A cash-out gamble. Set how much to INVEST, then FLY.",
                "A multiplier climbs as the plane rises — tap CASH OUT to bank bet × multiplier before it crashes.",
                "Or ABORT to watch a round risk-free; grow your cash to 70M to win.",
                "Go broke, or let the clock run out, and you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Trò cược rút tiền. Đặt số tiền ĐẦU TƯ, rồi BAY.",
                "Hệ số tăng khi máy bay lên — chạm RÚT để nhận cược × hệ số trước khi nó rơi.",
                "Hoặc BỎ QUA để xem một vòng không rủi ro; nâng tiền lên 70M để thắng.",
                "Cháy túi, hoặc hết giờ, sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> PlaneCrashView(level, onWin, onFail) }
    )
}

private const val START_CASH = 7
private const val GOAL = 70
private const val MIN_BET = 5
private const val GROWTH = 1.02

private enum class Phase { BETTING, FLYING, ABORTING, RESOLVING, DONE }

private object AviatorArt {
    val ink = rgb(0.055, 0.055, 0.07)
    val panel = rgb(0.11, 0.11, 0.125)
    val red = rgb(0.9, 0.02, 0.22)
    val green = rgb(0.2, 0.78, 0.08)
    val orange = rgb(0.86, 0.47, 0.04)
    val muted = gray(0.55)

    /** History pill colour: blue under 2×, purple to 10×, magenta above. */
    fun pill(m: Double) = if (m < 2) rgb(0.2, 0.7, 1.0) else if (m < 10) rgb(0.57, 0.24, 0.97) else rgb(0.75, 0.09, 0.71)

    /** The flight path: flat off the runway, then climbing ever more steeply. */
    fun point(p: Double, w: Double, h: Double): P {
        val q = max(0.0, min(1.0, p))
        return P(w * 0.07 + q * w * 0.66, h * 0.88 - q.pow(1.7) * h * 0.6)
    }

    /** Nose angle (radians, negative = up), softened so the plane never stands on its tail. */
    fun tilt(p: Double, w: Double, h: Double): Double {
        val q = max(0.001, min(1.0, p))
        return max(-0.55, atan2(-1.7 * q.pow(0.7) * h * 0.6, w * 0.66) * 0.7)
    }
}

private class Round(val level: Int) {
    val crashChance = 0.008 + (level - 1) * 0.0085
    val levelTime = max(55.0, 90.0 - level * 4.0)
    var phase by mutableStateOf(Phase.BETTING)
    var cash by mutableIntStateOf(START_CASH)
    var bet by mutableIntStateOf(MIN_BET)
    var multiplier by mutableDoubleStateOf(1.0)
    var planeProgress by mutableDoubleStateOf(0.0)
    var crashed by mutableStateOf(false)
    var message by mutableStateOf<String?>(null)
    var resolveTicks = 0
    var timeLeft by mutableDoubleStateOf(levelTime)
    val history = mutableStateListOf<Double>()
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    fun adjustBet(delta: Int) {
        if (phase != Phase.BETTING) return
        bet = min(cash, max(MIN_BET, bet + delta))
        SoundManager.tap(); Haptics.tap()
    }

    fun setAllIn() {
        if (phase != Phase.BETTING) return
        bet = max(MIN_BET, cash)
        SoundManager.tap(); Haptics.tap()
    }

    fun fly() {
        if (phase != Phase.BETTING) return
        SoundManager.tap(); Haptics.tap()
        startFlight(); phase = Phase.FLYING
    }

    fun abort() {
        if (phase != Phase.BETTING) return
        SoundManager.tap()
        startFlight(); phase = Phase.ABORTING
        message = null
    }

    private fun startFlight() { multiplier = 1.0; planeProgress = 0.0; crashed = false; message = null }

    fun cashOut() {
        if (phase != Phase.FLYING) return
        SoundManager.tap(); Haptics.tap()
        val profit = (bet * (multiplier - 1)).roundAway()
        cash += profit
        message = L("Banked +${profit}M", "Đã rút +${profit}M")
        beginResolve()
    }

    fun climb() { multiplier *= GROWTH; planeProgress = min(1.0, planeProgress + 0.016) }

    /** One 0.06 s game tick. */
    fun tick() {
        when (phase) {
            Phase.FLYING -> { climb(); if (Random.nextDouble() < crashChance) crash() }
            Phase.ABORTING -> {
                climb()
                // An abort flight always ends: it crashes on its own, or once the plane finishes its path.
                if (planeProgress >= 1.0 || Random.nextDouble() < crashChance) crash()
            }
            Phase.RESOLVING -> { resolveTicks++; if (resolveTicks >= 11) nextRound() }
            else -> {}
        }
    }

    fun crash() {
        crashed = true
        if (phase == Phase.FLYING) {
            cash -= bet
            message = L("CRASHED −${bet}M", "RƠI −${bet}M")
            SoundManager.error(); Haptics.warning()
        } else {
            message = L("Crashed at %.2f× — you sat out".format(multiplier), "Rơi ở %.2f× — bạn đã bỏ qua".format(multiplier))
        }
        beginResolve()
    }

    private fun beginResolve() {
        if (phase == Phase.FLYING || phase == Phase.ABORTING) {
            history.add(0, multiplier)
            if (history.size > 8) history.removeAt(history.size - 1)
        }
        resolveTicks = 0
        phase = Phase.RESOLVING
    }

    fun nextRound() {
        crashed = false; multiplier = 1.0; planeProgress = 0.0
        if (cash >= GOAL) { message = L("You beat the house!", "Bạn đã mua được nhà!"); win(); return }
        if (cash < MIN_BET) { message = L("Out of cash", "Hết tiền"); fail(); return }
        bet = min(cash, max(MIN_BET, bet))
        message = null
        phase = Phase.BETTING
    }

    fun win() { if (phase == Phase.DONE) return; phase = Phase.DONE; Haptics.tap(); SoundManager.tap(); onWin() }
    fun fail() { if (phase == Phase.DONE) return; phase = Phase.DONE; SoundManager.error(); onFail() }
}

@Composable
private fun PlaneCrashView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val r = remember { Round(level) }
    r.onWin = onWin; r.onFail = onFail
    var demoPress by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    // Presentation: the curve glides between ticks; the dive after a crash; the fireball when it lands.
    val progress = remember { Animatable(0f) }
    LaunchedEffect(r.planeProgress) {
        val target = r.planeProgress.toFloat()
        if (target < progress.value) progress.snapTo(target) else progress.animateTo(target, tween(60, easing = LinearEasing))
    }
    val fall = remember { Animatable(0f) }
    var boomT0 by remember { mutableDoubleStateOf(-10.0) }
    LaunchedEffect(r.crashed) {
        if (r.crashed) {
            launch { fall.animateTo(1f, tween(450, easing = FastOutSlowInEasing)) }
            delay(430)
            if (r.crashed) boomT0 = nowSec()
        } else { fall.snapTo(0f); boomT0 = -10.0 }
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            // Two real all-in rounds: 7M → cash out at 3.22× (59 ticks) → 23M → 3.09× (57 ticks) → 71M.
            suspend fun demoTap(key: String, action: () -> Unit): Boolean {
                demoPress = key
                delay(300)
                if (!isActive) return false
                action()
                demoPress = null
                delay(200)
                return isActive
            }
            while (isActive) {
                r.cash = START_CASH; r.bet = MIN_BET
                r.multiplier = 1.0; r.planeProgress = 0.0; r.crashed = false; r.message = null
                r.timeLeft = r.levelTime; r.history.clear()
                demoPress = null
                r.phase = Phase.BETTING
                for (ticks in listOf(59, 57)) {
                    delay(450)
                    if (!demoTap("allin") { r.setAllIn() }) return@LaunchedEffect
                    if (!demoTap("fly") { r.fly() }) return@LaunchedEffect
                    repeat(ticks) { delay(60); r.climb() }
                    if (!demoTap("cashout") { r.cashOut() }) return@LaunchedEffect
                    delay(700)
                    r.nextRound()
                }
                delay(1300)
            }
        } else {
            r.timeLeft = r.levelTime
            val start = nowSec()
            while (isActive && r.phase != Phase.DONE) {
                delay(60)
                r.timeLeft = max(0.0, r.levelTime - (nowSec() - start))
                if (r.timeLeft <= 0) { r.message = L("OUT OF TIME", "HẾT GIỜ"); r.fail(); return@LaunchedEffect }
                r.tick()
            }
        }
    }

    Box(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp)
            .clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp)).background(AviatorArt.ink)
            .then(if (isDemo) Modifier else Modifier.tapAt { r.cashOut() })   // tap anywhere to cash out mid-flight
            .padding(if (isDemo) 8.dp else 12.dp)
    ) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(if (isDemo) 5.dp else 10.dp)) {
            BalanceBar(r, isDemo)
            if (!isDemo) TimeBar(r.timeLeft / r.levelTime, Modifier.fillMaxWidth().height(4.dp),
                fill = if (r.timeLeft / r.levelTime < 0.3) AviatorArt.red else Color.White.op(0.75), track = Color.White.op(0.1))
            HistoryRow(r, isDemo)
            FlightPanel(r, isDemo, progress.value.toDouble(), fall.value.toDouble(), boomT0, Modifier.fillMaxWidth().weight(1f))
            BetPanel(r, isDemo, demoPress)
        }
    }
}

@Composable
private fun BalanceBar(r: Round, isDemo: Boolean) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column {
            Text(L("BALANCE", "SỐ DƯ"), style = ts(if (isDemo) 9.0 else 11.0, FontWeight.ExtraBold, AviatorArt.muted, spacing = 1.0))
            Text("${r.cash}M", style = ts(if (isDemo) 20.0 else 28.0, FontWeight.Black, AviatorArt.green))
        }
        Spacer(Modifier.weight(1f).widthIn(min = 6.dp))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            val f = min(1.0, max(0.0, r.cash.toDouble() / GOAL))
            Canvas(Modifier.size(if (isDemo) 86.dp else 104.dp, if (isDemo) 7.dp else 9.dp)) {
                val w = size.width.toDouble(); val h = size.height.toDouble()
                rrect(0.0, 0.0, w, h, h / 2, Color.White.op(0.1))
                val fw = max(6 * density.toDouble(), w * f)
                rrect(0.0, 0.0, fw, h, h / 2, hgrad(listOf(AviatorArt.green.op(0.7), AviatorArt.green), 0.0, fw))
            }
            Icon(Icons.Filled.Home, null, tint = if (r.cash >= GOAL) AviatorArt.green else Color.White,
                modifier = Modifier.size(if (isDemo) 16.dp else 21.dp))
            Text("${GOAL}M", style = ts(if (isDemo) 13.0 else 16.0, FontWeight.Black, Color.White), softWrap = false)
        }
    }
}

@Composable
private fun HistoryRow(r: Round, isDemo: Boolean) {
    Row(Modifier.fillMaxWidth().height(if (isDemo) 17.dp else 22.dp), horizontalArrangement = Arrangement.spacedBy(5.dp),
        verticalAlignment = Alignment.CenterVertically) {
        for (m in r.history.take(if (isDemo) 5 else 7)) {
            Text("%.2fx".format(m), style = ts(if (isDemo) 10.0 else 12.0, FontWeight.ExtraBold, AviatorArt.pill(m)), softWrap = false,
                modifier = Modifier.background(Color.White.op(0.07), RoundedCornerShape(50)).padding(horizontal = 8.dp, vertical = 3.dp))
        }
    }
}

@Composable
private fun FlightPanel(r: Round, isDemo: Boolean, p: Double, fall: Double, boomT0: Double, modifier: Modifier) {
    val tm = rememberTextMeasurer()
    val loop by rememberFrameLoop(running = boomT0 > 0)
    val corner = if (isDemo) 12.dp else 18.dp
    Box(modifier.clip(RoundedCornerShape(corner)).border(1.dp, Color.White.op(0.06), RoundedCornerShape(corner))) {
        Canvas(Modifier.fillMaxSize()) { sky() }
        Canvas(Modifier.fillMaxSize()) {
            loop
            val w = size.width.toDouble(); val h = size.height.toDouble()
            val u = density.toDouble()
            // Area under the curve, then the curve.
            if (p > 0.001) {
                val curve = Path()
                for (k in 0..28) {
                    val pt = AviatorArt.point(p * k / 28.0, w, h)
                    if (k == 0) curve.m(pt.x, pt.y) else curve.l(pt.x, pt.y)
                }
                val area = Path().apply { addPath(curve) }
                val end = AviatorArt.point(p, w, h); val start = AviatorArt.point(0.0, w, h)
                area.l(end.x, start.y); area.close()
                drawPath(area, vgrad(listOf(AviatorArt.red.op(0.45), AviatorArt.red.op(0.12)), 0.0, h))
                strokePath(curve, AviatorArt.red, (if (isDemo) 3.0 else 4.0) * u)
            }
            // Readout: the round's result over the big multiplier.
            val multSize = (if (isDemo) 38.0 else 58.0) * u
            val multColor = if (r.crashed) AviatorArt.red else if (r.phase == Phase.BETTING) Color.White.op(0.35) else Color.White
            val msg = r.message
            val cy = h * 0.4
            if (msg != null) {
                var ms = (if (isDemo) 13.0 else 17.0) * u
                val mw = textWidth(tm, msg, ms, FontWeight.ExtraBold)
                if (mw > w - 20 * u) ms *= max(0.6, (w - 20 * u) / mw)
                val mc = if (r.crashed) AviatorArt.red else if (r.phase == Phase.DONE) AviatorArt.green else Color.White
                text(tm, msg, w / 2, cy - multSize * 0.62, ms, mc, FontWeight.ExtraBold)
            }
            val label = "%.2fx".format(r.multiplier)
            blurText(tm, label, w / 2, cy + (if (msg != null) ms0(isDemo, u) * 0.4 else 0.0), multSize, multColor)
            // The plane: on the curve's tip, or diving to the ground after a crash.
            val planeW = min(w * 0.24, h * 0.42)
            val tip = AviatorArt.point(p, w, h)
            val tilt = AviatorArt.tilt(p, w, h)
            val ground = P(min(w - planeW * 0.4, tip.x + w * 0.1), h * 0.9)
            val onCurve = P(tip.x + planeW * 0.36, tip.y - planeW * 0.12)
            val pos = P(lerp(onCurve.x, ground.x, fall), lerp(onCurve.y, ground.y, fall))
            val angle = lerp(tilt * 180 / PI, 68.0, fall)
            val bt = nowSec() - boomT0
            val boom = bt >= 0 && r.crashed
            val alpha = if (r.phase == Phase.BETTING) 0.35 else if (boom) 0.0 else 1.0
            withAlpha(alpha) {
                rot(angle, pos.x, pos.y) { plane(pos.x - planeW / 2, pos.y - planeW / 4, planeW, planeW * 0.5) }
            }
            if (boom && bt < 0.6) crashBlast(ground.x, ground.y, planeW, bt)
        }
    }
}

private fun ms0(isDemo: Boolean, u: Double) = (if (isDemo) 13.0 else 17.0) * u

/** The big multiplier with a soft drop shadow. */
private fun DrawScope.blurText(tm: androidx.compose.ui.text.TextMeasurer, s: String, x: Double, y: Double, size: Double, c: Color) {
    glowText(tm, s, x, y, size, Color.Black.op(0.5), c, 6 * density.toDouble(), FontWeight.Black)
}

/** Dark sky with faint sunburst rays from the runway corner and the dotted axes. */
private fun DrawScope.sky() {
    val w = size.width.toDouble(); val h = size.height.toDouble()
    val u = density.toDouble()
    rect(0.0, 0.0, w, h, rgb(0.07, 0.07, 0.085))
    val ox = w * 0.02; val oy = h * 0.98
    val rr = hypot(w, h) * 1.1
    val rays = 18
    val fan = Path()
    for (k in 0 until rays step 2) {
        val a0 = -PI / 2 * k / rays; val a1 = -PI / 2 * (k + 1) / rays
        fan.m(ox, oy); fan.l(ox + rr * cos(a0), oy + rr * sin(a0)); fan.l(ox + rr * cos(a1), oy + rr * sin(a1)); fan.close()
    }
    drawPath(fan, radial(listOf(Color.White.op(0.05), Color.White.op(0.012)), ox, oy, rr * 0.8))
    val dot = rgb(0.3, 0.7, 1.0, 0.5)
    var x = w * 0.1
    while (x < w - 6 * u) { circle(x, h - 5.5 * u, 1.5 * u, dot); x += w * 0.1 }
    var y = h * 0.12
    while (y < h - 12 * u) { circle(6.5 * u, y, 1.5 * u, dot); y += h * 0.12 }
}

/** The red propeller plane (facing right) in the box (x, y, w, h), with a banana at the controls. */
private fun DrawScope.plane(x: Double, y: Double, w: Double, h: Double) {
    fun px(fx: Double) = x + fx * w
    fun py(fy: Double) = y + fy * h
    val red = AviatorArt.red
    val dark = rgb(0.55, 0.0, 0.12)
    val fin = polyPath(px(0.06), py(0.52), px(0.0), py(0.1), px(0.14), py(0.12), px(0.26), py(0.46))
    drawPath(fin, red)
    drawPath(fin, dark, style = Stroke(max(1.0, w * 0.012).f))
    val body = Path()
    body.m(px(0.04), py(0.5))
    body.q(px(0.3), py(0.26), px(0.8), py(0.34))
    body.q(px(0.93), py(0.45), px(0.86), py(0.62))
    body.q(px(0.4), py(0.78), px(0.04), py(0.58))
    body.close()
    drawPath(body, lin(listOf(red.lit(0.25), red, dark), px(0.5), py(0.28), px(0.5), py(0.75)))
    drawPath(body, dark, style = Stroke(max(1.0, w * 0.012).f))
    val canopy = Path()
    canopy.m(px(0.46), py(0.34)); canopy.q(px(0.56), py(0.08), px(0.68), py(0.33)); canopy.close()
    drawPath(canopy, rgb(0.72, 0.88, 1.0, 0.9))
    FruitArt.draw(this, FruitKind.BANANA, px(0.565), py(0.27), w * 0.05, -70.0)
    drawPath(canopy, dark, style = Stroke(max(1.0, w * 0.01).f))
    drawPath(polyPath(px(0.36), py(0.56), px(0.7), py(0.54), px(0.6), py(0.84), px(0.42), py(0.86)), dark)
    oval(px(0.84), py(0.4), 0.1 * w, 0.2 * h, gray(0.85))
    drawOval(radial(listOf(Color.White.op(0.55), Color.White.op(0.08)), px(0.94), py(0.5), h * 0.5), off(px(0.9), py(0.02)), sz(0.08 * w, 0.96 * h))
    line(px(0.94), py(0.08), px(0.94), py(0.92), gray(0.2).op(0.55), max(1.5, w * 0.02), StrokeCap.Round)
}

/** Fireball, smoke and flying debris where the plane comes down (t = seconds since it landed). */
private fun DrawScope.crashBlast(x: Double, y: Double, s: Double, t: Double) {
    val k = min(1.0, t / 0.45)
    val e = 1 - (1 - k) * (1 - k)
    val fr = s * 0.5 * lerp(0.2, 1.3, e)
    withAlpha(1 - e) {
        circle(x, y, fr, radial(listOf(rgb(1.0, 0.95, 0.6), rgb(1.0, 0.5, 0.1), rgb(0.8, 0.1, 0.05, 0.0)), x, y, fr))
    }
    circle(x, y - s * 0.35 * e, s * 0.3 * lerp(0.3, 1.4, e), gray(0.25).op(0.7 * 0.8 * (1 - e)))
    particleBurst(x, y, t, rgb(1.0, 0.55, 0.1), 12, s * 0.7 / density)
}

@Composable
private fun BetPanel(r: Round, isDemo: Boolean, demoPress: String?) {
    Column(
        Modifier.fillMaxWidth().background(AviatorArt.panel, RoundedCornerShape(if (isDemo) 12.dp else 18.dp)).padding(if (isDemo) 8.dp else 12.dp),
        verticalArrangement = Arrangement.spacedBy(if (isDemo) 6.dp else 10.dp)
    ) {
        when (r.phase) {
            Phase.FLYING -> AviatorButton(AviatorArt.orange, Color.White, demoPress == "cashout", if (isDemo) 50.0 else 68.0, false,
                !isDemo, Modifier.fillMaxWidth(), { r.cashOut() }) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(L("CASH OUT", "RÚT TIỀN"), style = ts(if (isDemo) 16.0 else 21.0, FontWeight.Black, Color.White))
                    Text("+${(r.bet * (r.multiplier - 1)).roundAway()}M", style = ts(if (isDemo) 12.0 else 15.0, FontWeight.ExtraBold, Color.White))
                }
            }
            Phase.ABORTING -> Box(Modifier.fillMaxWidth().heightIn(min = if (isDemo) 50.dp else 68.dp), contentAlignment = Alignment.Center) {
                Text(L("WATCHING — you sat this one out", "ĐANG XEM — bạn bỏ qua vòng này"),
                    style = ts(if (isDemo) 13.0 else 16.0, FontWeight.ExtraBold, AviatorArt.muted), textAlign = TextAlign.Center)
            }
            else -> BetControls(r, isDemo, demoPress)
        }
    }
}

@Composable
private fun BetControls(r: Round, isDemo: Boolean, demoPress: String?) {
    val active = r.phase == Phase.BETTING && !isDemo
    Column(Modifier.alpha(if (r.phase == Phase.BETTING) 1f else 0.4f), verticalArrangement = Arrangement.spacedBy(if (isDemo) 6.dp else 10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(if (isDemo) 6.dp else 10.dp)) {
            val sh = if (isDemo) 30.0 else 40.0
            StepButton(Icons.Filled.Remove, sh, active, isDemo) { r.adjustBet(-MIN_BET) }
            Column(Modifier.widthIn(min = if (isDemo) 58.dp else 76.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(L("INVEST", "ĐẦU TƯ"), style = ts(if (isDemo) 8.0 else 10.0, FontWeight.ExtraBold, AviatorArt.muted, spacing = 1.0))
                Text("${r.bet}M", style = ts(if (isDemo) 16.0 else 20.0, FontWeight.Black, Color.White))
            }
            StepButton(Icons.Filled.Add, sh, active, isDemo) { r.adjustBet(MIN_BET) }
            Spacer(Modifier.weight(1f).widthIn(min = 4.dp))
            AviatorButton(Color.White.op(0.14), Color.White, demoPress == "allin", sh, true, active, Modifier, { r.setAllIn() }) {
                Text(L("ALL IN", "TẤT TAY"), style = ts(if (isDemo) 12.0 else 15.0, FontWeight.Black, Color.White),
                    modifier = Modifier.padding(horizontal = if (isDemo) 12.dp else 16.dp), softWrap = false)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(if (isDemo) 8.dp else 10.dp)) {
            val bh = if (isDemo) 44.0 else 60.0
            AviatorButton(AviatorArt.green, Color.White, demoPress == "fly", bh, false, active, Modifier.weight(1f), { r.fly() }) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(L("FLY", "BAY"), style = ts(if (isDemo) 17.0 else 22.0, FontWeight.Black, Color.White))
                    Text("${r.bet}M", style = ts(if (isDemo) 11.0 else 14.0, FontWeight.ExtraBold, Color.White))
                }
            }
            AviatorButton(Color.White.op(0.12), Color.White, false, bh, false, active, Modifier.width(if (isDemo) 88.dp else 116.dp), { r.abort() }) {
                Text(L("ABORT", "BỎ QUA"), style = ts(if (isDemo) 13.0 else 16.0, FontWeight.ExtraBold, Color.White), softWrap = false)
            }
        }
    }
}

@Composable
private fun StepButton(icon: ImageVector, h: Double, enabled: Boolean, isDemo: Boolean, onClick: () -> Unit) {
    AviatorButton(Color.White.op(0.14), Color.White, false, h, true, enabled, Modifier.width(h.dp), onClick) {
        Icon(icon, null, tint = Color.White, modifier = Modifier.size(if (isDemo) 15.dp else 19.dp))
    }
}

/** Crash-game buttons: flat, rounded; a real press dips them, and the demo's `lit` press looks the same. */
@Composable
private fun AviatorButton(
    fill: Color, text: Color, lit: Boolean, height: Double, capsule: Boolean, enabled: Boolean, modifier: Modifier,
    onClick: () -> Unit, content: @Composable BoxScope.() -> Unit,
) {
    val (src, pressed) = rememberPressed()
    val down = pressed.value || lit
    val sc by animateFloatAsState(if (down) 0.95f else 1f, tween(100), label = "press")
    val shape = RoundedCornerShape(if (capsule) (height / 2).dp else 14.dp)
    Box(
        modifier.height(height.dp).scale(sc)
            .background(fill.lit(if (down) 0.12 else 0.0), shape)
            .border(if (down) 2.5.dp else 1.dp, Color.White.op(if (down) 0.9 else 0.1), shape)
            .clickable(src, null, enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center, content = content
    )
}
