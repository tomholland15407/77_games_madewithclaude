package com.gogs.bananagame.games.headerduel

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowLeft
import androidx.compose.material.icons.automirrored.filled.ArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
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

/**
 * Reflex — Header Duel (iOS HeadSoccerGame.swift, id "head-soccer"): big-headed banana vs a tomato.
 * Hold ◄ ► to run, JUMP to leap; your head auto-heads the ball. First to `level` goals wins.
 */
object HeaderDuelGame {
    val definition = GameDefinition(
        id = "head-soccer",
        title = "Header Duel",
        genre = Genre.REFLEX,
        manual = GameManual(
            bullets = listOf(
                "Hold LEFT / RIGHT to run and tap JUMP to leap.",
                "Your big head auto-heads any ball it touches.",
                "Score in the AI's goal on the right while defending yours on the left.",
                "Reach the target goals first to win; if the AI does, or time runs out, you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Giữ TRÁI / PHẢI để chạy và chạm NHẢY để bật lên.",
                "Cái đầu to của bạn tự đánh đầu mọi quả bóng nó chạm phải.",
                "Ghi bàn vào khung thành AI bên phải trong khi bảo vệ khung của bạn bên trái.",
                "Đạt đủ bàn thắng trước để thắng; nếu AI đạt trước, hoặc hết giờ, bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> HeaderDuelView(level, onWin, onFail) }
    )
}

private const val GROUND = 0.80
private const val CEILING = 0.14
private const val HEAD_R = 0.09
private const val BALL_R = 0.042
private const val GOAL_TOP = 0.60
private const val GOAL_W = 0.05

private class Match(val level: Int, val isDemo: Boolean) {
    val goalsToWin = level
    val aiSpeed = 0.24 + level * 0.05
    val aiJumpChance = 0.01 + level * 0.006
    val ballSpeedCap = 1.0 + level * 0.12
    val timeLimit = 10.0 + level * 4.0 + (if (level >= 3) (level - 2) * 6.0 else 0.0)
    val gravity = 2.4
    val moveSpeed = 0.5
    val jumpV = 1.15

    var playing = true
    var bx = 0.5; var by = 0.4; var bvx = 0.3; var bvy = 0.0
    var px = 0.25; var py = GROUND; var pvy = 0.0
    var ax = 0.75; var ay = GROUND; var avy = 0.0
    var moveDir = 0.0
    var playerScore = 0; var aiScore = 0
    var timeLeft = timeLimit
    var serveCD = 0.0
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    fun reset(serveToward: Double) {
        px = 0.25; py = GROUND; pvy = 0.0
        ax = 0.75; ay = GROUND; avy = 0.0
        bx = 0.5; by = 0.35; bvx = 0.25 * serveToward; bvy = 0.0
        serveCD = 0.4
    }

    fun begin(serve: Double) { playing = true; playerScore = 0; aiScore = 0; moveDir = 0.0; reset(serve); timeLeft = timeLimit }

    fun step(dt: Double) {
        if (!playing) return
        if (serveCD > 0) serveCD -= dt
        px = clamp(px + moveDir * moveSpeed * dt, 0.05, 0.55)
        pvy += gravity * dt; py += pvy * dt; if (py >= GROUND) { py = GROUND; pvy = 0.0 }
        // The AI chases the ball and sometimes jumps at a high, near ball (never in the demo).
        val target = clamp(bx, 0.45, 0.95)
        val st = aiSpeed * dt
        ax += clamp(target - ax, -st, st)
        if (!isDemo && ay >= GROUND - 0.001 && by < 0.5 && abs(bx - ax) < 0.18 && Math.random() < aiJumpChance) avy = -jumpV
        avy += gravity * dt; ay += avy * dt; if (ay >= GROUND) { ay = GROUND; avy = 0.0 }
        // Ball.
        bvy += gravity * dt
        var nx = bx + bvx * dt; var ny = by + bvy * dt
        if (ny < CEILING + BALL_R) { ny = CEILING + BALL_R; bvy = abs(bvy) * 0.8 }
        if (ny > GROUND - BALL_R) { ny = GROUND - BALL_R; bvy = -abs(bvy) * 0.6; bvx *= 0.98 }
        val inMouth = ny > GOAL_TOP && ny < GROUND
        if (nx < BALL_R) {
            if (inMouth) { bx = nx; by = ny; scored(false); return }
            nx = BALL_R; bvx = abs(bvx) * 0.8
        }
        if (nx > 1 - BALL_R) {
            if (inMouth) { bx = nx; by = ny; scored(true); return }
            nx = 1 - BALL_R; bvx = -abs(bvx) * 0.8
        }
        bx = nx; by = ny
        headBounce(px, py, pvy)
        headBounce(ax, ay, avy)
        val sp = hypot(bvx, bvy)
        if (sp > ballSpeedCap) { val s = ballSpeedCap / sp; bvx *= s; bvy *= s }
    }

    /** Circle-circle bounce off a head, adding the head's motion. */
    private fun headBounce(hx: Double, hy: Double, vy: Double) {
        val minD = BALL_R + HEAD_R
        val dx = bx - hx; val dy = by - hy
        val d = hypot(dx, dy)
        if (d >= minD || d <= 0.0001) return
        val nx = dx / d; val ny = dy / d
        bx = hx + nx * minD; by = hy + ny * minD
        val dot = bvx * nx + bvy * ny
        if (dot < 0) { bvx -= 2 * dot * nx; bvy -= 2 * dot * ny }
        bvx += nx * 0.5
        bvy += ny * 0.5 + min(0.0, vy) * 0.6
        SoundManager.tap()
    }

    fun jump() {
        if (!playing || py < GROUND - 0.001) return
        pvy = -jumpV
        SoundManager.tap(); Haptics.tap()
    }

    private fun scored(player: Boolean) {
        if (player) { playerScore++; Haptics.tap(); SoundManager.tap() } else { aiScore++; SoundManager.error() }
        if (playerScore >= goalsToWin) { win(); return }
        if (aiScore >= goalsToWin) { fail(); return }
        reset(if (player) -1.0 else 1.0)
    }

    fun win() { if (!playing) return; playing = false; Haptics.tap(); SoundManager.tap(); onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }
}

@Composable
private fun HeaderDuelView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val m = remember { Match(level, isDemo).also { it.begin(if (rndBool()) 1.0 else -1.0) } }
    m.onWin = onWin; m.onFail = onFail
    var demoJump by remember { mutableStateOf(false) }
    var demoTick by remember { mutableIntStateOf(0) }
    val start = remember { nowSec() }
    val tick by rememberFrameLoop(running = !isDemo) { dt ->
        if (!m.playing) return@rememberFrameLoop
        m.timeLeft = max(0.0, m.timeLimit - (nowSec() - start))
        if (m.timeLeft <= 0) { m.fail(); return@rememberFrameLoop }
        m.step(dt)
    }

    LaunchedEffect(Unit) {
        if (!isDemo) return@LaunchedEffect
        val dt = 1.0 / 60.0
        while (isActive) {
            m.begin(-1.0); demoJump = false; demoTick++
            delay(600)
            var t = 0.0; var jumped = false; var flash = 0.0
            while (isActive && m.playing && t < 6) {
                t += dt
                m.moveDir = if (t >= 0.4 && t < 0.9) 1.0 else 0.0
                if (!jumped && t >= 0.35) { m.jump(); jumped = true; flash = 0.2 }
                demoJump = flash > 0
                flash -= dt
                m.step(dt)
                demoTick++
                delay(16)
            }
            m.moveDir = 0.0; demoJump = false; demoTick++
            delay(1300)
        }
    }

    Box(Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))) {
        Canvas(Modifier.fillMaxSize()) {
            tick; demoTick
            stadium()
            val w = size.width.toDouble(); val h = size.height.toDouble()
            player(m.px * w, m.py * h, HEAD_R * w, true, 1.0)
            player(m.ax * w, m.ay * h, HEAD_R * w, false, -1.0)
            ball(m.bx * w, m.by * h, BALL_R * w, m.bx * w / max(1.0, BALL_R * w))
            goalFront()
        }
        tick; demoTick
        Scoreboard(m, isDemo, Modifier.centerAt(0.5, 0.065))
        Column(Modifier.fillMaxSize()) {
            Spacer(Modifier.weight(1f))
            Row(Modifier.fillMaxWidth().padding(horizontal = if (isDemo) 10.dp else 16.dp).padding(bottom = if (isDemo) 4.dp else 18.dp),
                horizontalArrangement = Arrangement.spacedBy(if (isDemo) 8.dp else 12.dp), verticalAlignment = Alignment.CenterVertically) {
                val kw = if (isDemo) 58.dp else 76.dp; val kh = if (isDemo) 34.dp else 56.dp
                for (dir in listOf(-1.0, 1.0)) {
                    val pressed = m.moveDir == dir
                    FramedKey(kw, kh, pressed, Modifier.then(if (isDemo) Modifier else Modifier.pressDown(
                        onDown = { if (m.playing) m.moveDir = dir }, onUp = { if (m.moveDir == dir) m.moveDir = 0.0 }))) {
                        Icon(if (dir < 0) Icons.AutoMirrored.Filled.ArrowLeft else Icons.AutoMirrored.Filled.ArrowRight, null,
                            tint = if (pressed) rgb(1.0, 0.85, 0.3) else Color.White, modifier = Modifier.size(if (isDemo) 30.dp else 40.dp))
                    }
                }
                Spacer(Modifier.weight(1f))
                var held by remember { mutableStateOf(false) }
                val down = held || demoJump
                FramedKey(if (isDemo) 92.dp else 118.dp, kh, down, Modifier.then(if (isDemo) Modifier else Modifier.pressDown(
                    onDown = { held = true; m.jump() }, onUp = { held = false }))) {
                    Text(L("JUMP", "NHẢY"), style = ts(if (isDemo) 15.0 else 19.0, FontWeight.Black, if (down) rgb(1.0, 0.85, 0.3) else Color.White))
                }
            }
        }
    }
}

/** The match scoreboard: both heads and the score, the clock, and the target. */
@Composable
private fun Scoreboard(m: Match, isDemo: Boolean, modifier: Modifier) {
    Box(modifier) {
        Column(
            Modifier.background(Brush.verticalGradient(listOf(rgb(0.2, 0.26, 0.42), rgb(0.1, 0.13, 0.24))), RoundedCornerShape(10.dp))
                .border(2.dp, rgb(0.95, 0.78, 0.3), RoundedCornerShape(10.dp)).padding(horizontal = 12.dp, vertical = 5.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Canvas(Modifier.size(22.dp)) { face(size.width / 2.0, size.height / 2.0, size.width * 0.42, true, 1.0) }
                Text(L("YOU", "BẠN"), style = ts(11.0, FontWeight.Black, BananaTheme.banana))
                Text("${m.playerScore} : ${m.aiScore}", style = ts(if (isDemo) 18.0 else 22.0, FontWeight.Black),
                    modifier = Modifier.background(rgb(0.1, 0.12, 0.2), RoundedCornerShape(5.dp)).padding(horizontal = 8.dp))
                Text(L("AI", "MÁY"), style = ts(11.0, FontWeight.Black, rgb(1.0, 0.5, 0.45)))
                Canvas(Modifier.size(22.dp)) { face(size.width / 2.0, size.height / 2.0, size.width * 0.42, false, -1.0) }
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (!isDemo) {
                    val t = max(0, ceil(m.timeLeft).toInt())
                    Text("%d:%02d".format(t / 60, t % 60), style = ts(13.0, FontWeight.Black, if (m.timeLeft < 5) rgb(1.0, 0.4, 0.35) else rgb(1.0, 0.85, 0.3), Mono))
                }
                Text(L("first to ${m.goalsToWin}", "về ${m.goalsToWin} trước"), style = ts(10.0, FontWeight.ExtraBold, Color.White.op(0.75)))
            }
        }
    }
}

/** The framed keys from the Head Soccer HUD. */
@Composable
private fun FramedKey(w: Dp, h: Dp, pressed: Boolean, modifier: Modifier, content: @Composable () -> Unit) {
    val shape = RoundedCornerShape(12.dp)
    Box(
        modifier.scale(if (pressed) 0.92f else 1f).size(w, h)
            .background(Brush.verticalGradient(if (pressed) listOf(rgb(0.2, 0.2, 0.3), rgb(0.32, 0.3, 0.42))
                else listOf(rgb(0.36, 0.34, 0.48, 0.92), rgb(0.16, 0.15, 0.24, 0.92))), shape)
            .border(if (pressed) 3.dp else 2.dp, rgb(0.95, 0.76, 0.3), shape),
        contentAlignment = Alignment.Center
    ) {
        Box(Modifier.fillMaxSize().padding(3.dp).border(1.dp, Color.White.op(0.25), RoundedCornerShape(10.dp)))
        content()
    }
}

// Head Soccer art (iOS SoccerArt / Stadium).

private val ink = rgb(0.1, 0.07, 0.08)

private fun hash(n: Double): Double { val v = sin(n * 12.9898) * 43758.5453; return v - kotlin.math.floor(v) }

/** A big head (banana or tomato) with one boot under it. */
private fun DrawScope.player(cx: Double, cy: Double, r: Double, banana: Boolean, facing: Double) {
    val bootY = cy + r * 0.95
    val boot = Path()
    boot.m(cx - facing * r * 0.35, bootY - r * 0.28)
    boot.l(cx + facing * r * 0.05, bootY - r * 0.28)
    boot.q(cx + facing * r * 0.5, bootY - r * 0.26, cx + facing * r * 0.55, bootY + r * 0.02)
    boot.l(cx + facing * r * 0.55, bootY + r * 0.12)
    boot.l(cx - facing * r * 0.38, bootY + r * 0.12)
    boot.close()
    oval(cx - r * 0.6, bootY + r * 0.06, r * 1.2, r * 0.2, Color.Black.op(0.25))
    fillPath(boot, rgb(0.12, 0.12, 0.16))
    val stripes = Path()
    for (k in 0 until 3) {
        val x = cx - facing * r * (0.18 - k * 0.12)
        stripes.m(x, bootY - r * 0.24); stripes.l(x + facing * r * 0.06, bootY + r * 0.02)
    }
    strokePath(stripes, Color.White, max(density.toDouble(), r * 0.06), StrokeCap.Butt)
    rect(cx - r * 0.38 + (if (facing < 0) -r * 0.17 else 0.0), bootY + r * 0.1, r * 0.93, r * 0.05, gray(0.85))
    face(cx, cy, r, banana, facing)
}

/** The head: a round banana (stem + sweatband) or a tomato (leaves), with a battle face. */
private fun DrawScope.face(cx: Double, cy: Double, r: Double, banana: Boolean, facing: Double) {
    val u = density.toDouble()
    val base = if (banana) rgb(1.0, 0.84, 0.24) else rgb(0.9, 0.2, 0.16)
    circle(cx, cy, r, ink)
    circle(cx, cy, r - 1.5 * u, radial(listOf(base.lit(0.35), base, base.shade(0.25)), cx - r * 0.35, cy - r * 0.4, r * 1.4))
    if (banana) {
        val stem = Path(); stem.m(cx - facing * r * 0.05, cy - r * 0.9); stem.q(cx, cy - r * 1.25, cx - facing * r * 0.3, cy - r * 1.35)
        strokePath(stem, ink, max(3 * u, r * 0.26))
        strokePath(stem, rgb(0.5, 0.42, 0.16), max(2 * u, r * 0.16))
        rect(cx - r * 0.95, cy - r * 0.55, r * 1.9, r * 0.2, rgb(0.16, 0.5, 0.9))
    } else {
        for (k in 0 until 5) {
            val a = -PI / 2 + (k - 2) * 0.5
            val tx = cx + cos(a) * r * 0.55; val ty = cy - r * 0.82 + (sin(a) + 1) * r * 0.12
            val leaf = Path(); leaf.m(cx, cy - r * 0.9); leaf.q((cx + tx) / 2, cy - r * 1.12, tx, ty)
            strokePath(leaf, rgb(0.2, 0.55, 0.2), max(2 * u, r * 0.14))
        }
    }
    for (dx in listOf(-0.34, 0.26)) {
        val ex = cx + facing * dx * r; val ey = cy - r * 0.12
        oval(ex - r * 0.18, ey - r * 0.22, r * 0.36, r * 0.44, Color.White)
        ellipseStroke(ex, ey, r * 0.18, r * 0.22, ink, max(u, r * 0.04))
        oval(ex + facing * r * 0.02 - r * 0.07, ey - r * 0.09, r * 0.14, r * 0.2, ink)
    }
    val brows = Path()
    brows.m(cx - facing * r * 0.52, cy - r * 0.44); brows.l(cx - facing * r * 0.14, cy - r * 0.36)
    brows.m(cx + facing * r * 0.1, cy - r * 0.36); brows.l(cx + facing * r * 0.44, cy - r * 0.44)
    strokePath(brows, ink, max(1.5 * u, r * 0.1))
    val mouth = Path()
    mouth.m(cx - r * 0.12 + facing * r * 0.05, cy + r * 0.42)
    mouth.q(cx + facing * r * 0.08, cy + r * 0.58, cx + r * 0.22 + facing * r * 0.05, cy + r * 0.38)
    strokePath(mouth, ink, max(1.5 * u, r * 0.08))
}

/** The classic black-and-white ball, rolling. */
private fun DrawScope.ball(cx: Double, cy: Double, r: Double, spin: Double) {
    val u = density.toDouble()
    circle(cx, cy, r, ink)
    val ir = r - u
    circle(cx, cy, ir, radial(listOf(Color.White, gray(0.8)), cx - r * 0.3, cy - r * 0.35, r * 1.3))
    fun pentagon(px: Double, py: Double, s: Double, rot: Double): Path {
        val p = Path()
        for (k in 0 until 5) { val a = rot + k / 5.0 * 2 * PI; if (k == 0) p.m(px + cos(a) * s, py + sin(a) * s) else p.l(px + cos(a) * s, py + sin(a) * s) }
        p.close(); return p
    }
    val inner = Path().apply { addOval(androidx.compose.ui.geometry.Rect((cx - ir).f, (cy - ir).f, (cx + ir).f, (cy + ir).f)) }
    clipPath(inner) {
        fillPath(pentagon(cx, cy, r * 0.32, spin), ink)
        for (k in 0 until 5) {
            val a = spin + k / 5.0 * 2 * PI + PI / 5
            fillPath(pentagon(cx + cos(a) * r * 0.86, cy + sin(a) * r * 0.86, r * 0.3, a), ink)
        }
    }
}

/** Posts and crossbar in front of the play. */
private fun DrawScope.goalFront() {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    val top = GOAL_TOP * h; val bottom = GROUND * h; val depth = GOAL_W * w
    for (left in listOf(true, false)) {
        val postX = if (left) depth else w - depth
        val f = Path(); f.m(if (left) 0.0 else w, top); f.l(postX, top); f.l(postX, bottom)
        strokePath(f, ink.op(0.5), 6 * u)
        strokePath(f, Color.White, 4 * u)
    }
}

/** Floodlit stadium, ad boards, the striped pitch and the nets behind the goal frames. */
private fun DrawScope.stadium() {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    val boards = h * 0.55
    rect(0.0, 0.0, w, h, vgrad(listOf(rgb(0.24, 0.52, 0.9), rgb(0.6, 0.82, 1.0)), 0.0, boards))
    val standTop = h * 0.2
    val stand = Path()
    stand.m(0.0, standTop + h * 0.04); stand.q(w / 2, standTop - h * 0.03, w, standTop + h * 0.04)
    stand.l(w, boards); stand.l(0.0, boards); stand.close()
    fillPath(stand, rgb(0.2, 0.22, 0.3))
    val palette = listOf(SysColor.red, Color.White, SysColor.yellow, SysColor.blue, SysColor.orange, rgb(0.4, 0.8, 0.4), SysColor.pink)
    clipPath(stand) {
        var y = standTop; var row = 0
        while (y < boards) {
            var x = if (row % 2 == 0) 3 * u else 7 * u
            var k = 0
            while (x < w) {
                val col = palette[(hash((row * 97 + k).toDouble()) * palette.size).toInt() % palette.size]
                oval(x, y + hash((k + row).toDouble()) * 2 * u, 4.5 * u, 5 * u, col.op(0.85))
                x += 8 * u; k++
            }
            y += 7 * u; row++
            if (row % 5 == 0) { rect(0.0, y, w, 2.5 * u, rgb(0.55, 0.58, 0.64)); y += 3 * u }
        }
    }
    val roof = Path(); roof.m(0.0, standTop + h * 0.02); roof.q(w / 2, standTop - h * 0.05, w, standTop + h * 0.02)
    strokePath(roof, rgb(0.85, 0.87, 0.9), 5 * u, StrokeCap.Butt)
    for (fx in listOf(w * 0.12, w * 0.88)) {
        rect(fx - 1.5 * u, standTop - h * 0.06, 3 * u, h * 0.07, gray(0.75))
        val lx = fx - 14 * u; val ly = standTop - h * 0.09
        rrect(lx, ly, 28 * u, 12 * u, 3 * u, gray(0.3))
        for (k in 0 until 4) oval(lx + 2 * u + k * 6.5 * u, ly + 3 * u, 5 * u, 5 * u, rgb(1.0, 0.98, 0.8))
    }
    val boardH = h * 0.04
    val colours = listOf(rgb(0.95, 0.8, 0.2), rgb(0.2, 0.5, 0.9), rgb(0.9, 0.25, 0.2), rgb(0.15, 0.6, 0.35))
    var bx = 0.0; var k = 0
    while (bx < w) {
        val bw = w * 0.24
        rect(bx, boards, bw, boardH, colours[k % colours.size])
        rrect(bx + bw * 0.3, boards + boardH * 0.28, bw * 0.4, boardH * 0.44, 3 * u, Color.White.op(0.85))
        bx += bw; k++
    }
    val pitchTop = boards + boardH
    rect(0.0, pitchTop, w, h - pitchTop, rgb(0.28, 0.62, 0.24))
    var stripe = pitchTop; var i = 0
    while (stripe < h) {
        val band = h * 0.035 * (1 + i * 0.25)
        if (i % 2 == 0) rect(0.0, stripe, w, band, rgb(0.34, 0.7, 0.3))
        stripe += band; i++
    }
    val gy = GROUND * h
    rect(0.0, gy - u, w, 2.5 * u, Color.White.op(0.85))
    rect(w / 2 - 1.2 * u, pitchTop, 2.4 * u, gy - pitchTop, Color.White.op(0.55))
    ellipseStroke(w / 2, gy, w * 0.12, h * 0.035, Color.White.op(0.55), 2 * u)
    val top = GOAL_TOP * h; val depth = GOAL_W * w
    for (left in listOf(true, false)) {
        val rx = if (left) 0.0 else w - depth
        rect(rx, top, depth, gy - top, Color.White.op(0.18))
        val net = Path()
        var nx = rx
        while (nx <= rx + depth) { net.m(nx, top); net.l(nx, gy); nx += 5 * u }
        var ny = top
        while (ny <= gy) { net.m(rx, ny); net.l(rx + depth, ny); ny += 5 * u }
        strokePath(net, Color.White.op(0.6), 0.8 * u, StrokeCap.Butt)
    }
}
