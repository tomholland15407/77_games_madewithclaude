package com.gogs.bananagame.games.lightsout

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.vector.VectorPainter
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/**
 * Brain — Lights Out (iOS LightsOutGame.swift): a tap flips a key and its four neighbours; turn every
 * key off before the clock runs out. Boards are scrambled from solved, so always solvable.
 */
object LightsOutGame {
    val definition = GameDefinition(
        id = "lights-out",
        title = "Lights Out",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Tapping a tile flips it and its four orthogonal neighbours (a plus shape).",
                "Turn every tile off before the clock runs out.",
                "Every board is solvable — the challenge is finding the order under time pressure.",
            ),
            bulletsVI = listOf(
                "Chạm một ô sẽ lật nó và bốn ô kề bên (hình dấu cộng).",
                "Tắt hết mọi ô trước khi hết giờ.",
                "Mọi bàn đều giải được — thử thách là tìm đúng thứ tự dưới áp lực thời gian.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> LightsOutView(level, onWin, onFail) }
    )
}

private val demoMoves = listOf(0 to 0, 1 to 2, 2 to 1)

private class Rc(val x: Double, val y: Double, val w: Double, val h: Double) {
    val maxX get() = x + w
    val maxY get() = y + h
    val midX get() = x + w / 2
    val midY get() = y + h / 2
    fun inset(dx: Double, dy: Double) = Rc(x + dx, y + dy, w - 2 * dx, h - 2 * dy)
}

/** Where everything sits on the handheld, as fractions of the key grid's side B. */
private class LOLayout(w0: Double, h0: Double, n: Int, demo: Boolean) {
    val caseRect: Rc; val mat: Rc; val board: Rc; val cell: Double; val spacing: Double
    val logo: Rc; val led: Rc; var slot: Rc? = null; var keys: Rc? = null
    init {
        val w = max(1.0, w0); val h = max(1.0, h0)
        val b: Double; val matPad: Double; val side: Double; val top: Double; val gap: Double
        val row1: Double; val row2: Double; val row3: Double; val bottom: Double
        if (demo) {
            b = max(40.0, min(h * 0.6, w * 0.6))
            matPad = b * 0.05; side = b * 0.09; top = b * 0.075; gap = b * 0.05
            row1 = b * 0.2; row2 = 0.0; row3 = 0.0; bottom = b * 0.075
        } else {
            b = max(40.0, min(w * 0.76, h * 0.52))
            matPad = b * 0.05; side = b * 0.07; top = b * 0.07; gap = b * 0.045
            row1 = b * 0.15; row2 = b * 0.055; row3 = b * 0.12; bottom = b * 0.07
        }
        val matSide = b + matPad * 2
        val caseW = matSide + side * 2
        var caseH = top + matSide + gap + row1 + bottom
        if (!demo) caseH += gap + row2 + gap + row3
        caseRect = Rc((w - caseW) / 2, (h - caseH) / 2, caseW, caseH)
        mat = Rc(caseRect.x + side, caseRect.y + top, matSide, matSide)
        board = mat.inset(matPad, matPad)
        var y = mat.maxY + gap
        logo = Rc(mat.x, y, matSide * 0.54, row1)
        led = Rc(mat.x + matSide * 0.58, y + row1 * 0.06, matSide * 0.42, row1 * 0.66)
        if (!demo) {
            y += row1 + gap
            slot = Rc(mat.x, y, matSide, row2)
            y += row2 + gap
            keys = Rc(mat.x, y, matSide, row3)
        }
        spacing = b * 0.035
        cell = (b - spacing * (n - 1)) / n
    }
}

@Composable
private fun LightsOutView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val li = min(level, 7) - 1
    val n = listOf(3, 4, 4, 5, 5, 6, 6)[li]
    val scramble = listOf(3, 5, 7, 10, 13, 17, 22)[li]
    val timeLimit = listOf(34.0, 32.0, 28.0, 26.0, 22.0, 18.0, 15.0)[li]
    var playing by remember { mutableStateOf(true) }
    var grid by remember { mutableStateOf(BooleanArray(0)) }
    var moves by remember { mutableIntStateOf(0) }
    var timeLeft by remember { mutableDoubleStateOf(timeLimit) }
    var pulse by remember { mutableIntStateOf(-1) }
    var chaseStart by remember { mutableStateOf<Double?>(null) }
    val scope = rememberCoroutineScope()
    val tm = rememberTextMeasurer()
    val handP = rememberHand()
    val frame by rememberFrameLoop(running = chaseStart != null)

    fun toggle(g: BooleanArray, r: Int, c: Int) {
        for ((dr, dc) in listOf(0 to 0, 1 to 0, -1 to 0, 0 to 1, 0 to -1)) {
            val nr = r + dr; val nc = c + dc
            if (nr in 0 until n && nc in 0 until n) g[nr * n + nc] = !g[nr * n + nc]
        }
    }
    fun win() { if (!playing) return; playing = false; chaseStart = nowSec(); Haptics.tap(); SoundManager.tap(); onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }
    fun tap(r: Int, c: Int) {
        if (!playing) return
        Haptics.tap(); SoundManager.tap()
        grid = grid.copyOf().also { toggle(it, r, c) }
        moves++
        pulse = r * n + c
        scope.launch { delay(100); pulse = -1 }
        if (grid.none { it }) win()
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (isActive) {
                grid = BooleanArray(n * n).also { g -> for ((r, c) in demoMoves) toggle(g, r, c) }
                moves = 0; timeLeft = timeLimit; playing = true; chaseStart = null
                delay(700)
                for ((r, c) in demoMoves) { pulse = r * n + c; delay(400); tap(r, c); delay(800) }
                delay(900)
            }
        } else {
            var g: BooleanArray
            var attempts = 0
            do {
                g = BooleanArray(n * n)
                repeat(scramble) { toggle(g, Random.nextInt(n), Random.nextInt(n)) }
                attempts++
            } while (g.none { it } && attempts < 8)
            grid = g; moves = 0; timeLeft = timeLimit
            val start = nowSec()
            while (isActive && playing) {
                delay(50)
                timeLeft = max(0.0, timeLimit - (nowSec() - start))
                if (timeLeft <= 0) { fail(); break }
            }
        }
    }

    GameBox { w, h ->
        val lay = remember(w, h, n, isDemo) { LOLayout(w, h, n, isDemo) }
        Canvas(Modifier.fillMaxSize().then(if (isDemo) Modifier else Modifier.tapAt(lay) { p ->
            val pitch = lay.cell + lay.spacing
            val lx = p.x - lay.board.x; val ly = p.y - lay.board.y
            val c = floor(lx / pitch).toInt(); val r = floor(ly / pitch).toInt()
            if (r in 0 until n && c in 0 until n && lx - c * pitch <= lay.cell && ly - r * pitch <= lay.cell) tap(r, c)
        })) {
            frame
            caseArt(tm, lay, L("MOVES", "NƯỚC"), L("LIGHTS ON", "ĐÈN SÁNG"))
            translate(lay.board.x.f, lay.board.y.f) { keypad(grid, n, pulse, isDemo, chaseStart, lay.cell, lay.spacing, handP) }
            translate(lay.led.x.f, lay.led.y.f) { readout(lay.led.w, lay.led.h, moves, grid.count { it }) }
            lay.slot?.let { timeBarArt(it, if (timeLimit > 0) timeLeft / timeLimit else 0.0, timeLeft) }
        }
    }
}

// Tiger handheld art (iOS LOArt and friends).

private val caseHi = rgb(0.87, 0.86, 0.85)
private val caseLo = rgb(0.66, 0.65, 0.67)
private val caseInk = rgb(0.30, 0.29, 0.32)
private val matC = rgb(0.30, 0.27, 0.33)
private val offC = rgb(0.55, 0.50, 0.58)
private val offHi = rgb(0.68, 0.63, 0.70)
private val offLo = rgb(0.40, 0.36, 0.43)
private val onC = rgb(1.0, 0.30, 0.45)
private val onHi = rgb(1.0, 0.66, 0.74)
private val onLo = rgb(0.86, 0.16, 0.32)
private val glowC = rgb(1.0, 0.22, 0.40)
private val slotC = rgb(0.16, 0.06, 0.08)
private val ledGlass = rgb(0.13, 0.04, 0.06)
private val ledOn = rgb(1.0, 0.26, 0.33)
private val ledOff = rgb(0.22, 0.06, 0.08)
private val logoRed = rgb(0.89, 0.17, 0.21)
private val logoYellow = rgb(0.98, 0.80, 0.16)
private val logoBlue = rgb(0.22, 0.38, 0.86)
private val pillC = rgb(0.97, 0.78, 0.20)
private val selectC = rgb(0.43, 0.45, 0.82)

private fun rrPath(r: Rc, rad: Double) = Path().apply { addRoundRect(androidx.compose.ui.geometry.RoundRect(r.x.f, r.y.f, r.maxX.f, r.maxY.f, rad.f, rad.f)) }

/** One rubber key. Lit keys glow from inside; a pressed key sinks into the mat. */
private fun DrawScope.key(cellRect: Rc, lit: Boolean, glow: Double, pressed: Boolean) {
    var r = cellRect.inset(cellRect.w * 0.035, cellRect.w * 0.035)
    if (pressed) r = r.inset(r.w * 0.05, r.w * 0.05)
    val rad = r.w * 0.18
    if (!pressed) rrect(r.x, r.y + r.h * 0.05, r.w, r.h, rad, Color.Black.op(0.4))
    if (lit) {
        val k = glow
        rrect(r.x, r.y, r.w, r.h, rad, vgrad(listOf(onHi.mix(offHi, 1 - k), onC.mix(offC, 1 - k), onLo.mix(offLo, 1 - k)), r.y, r.maxY))
        clipPath(rrPath(r, rad)) {
            circle(r.midX, r.midY + r.h * 0.04, r.w * 0.55, radial(listOf(Color.White.op(0.55 * k), onHi.op(0.35 * k), Color.Transparent), r.midX, r.midY + r.h * 0.04, r.w * 0.55))
        }
    } else rrect(r.x, r.y, r.w, r.h, rad, vgrad(listOf(offHi, offC, offLo), r.y, r.maxY))
    val sh = r.h * 0.22
    rrect(r.x + r.w * 0.14, r.y + r.h * 0.08, r.w * 0.72, sh, sh / 2, Color.White.op(if (lit) 0.32 else 0.18))
    rrectStroke(r.x, r.y, r.w, r.h, rad, Color.Black.op(if (pressed) 0.55 else 0.4), max(density.toDouble(), r.w * 0.02))
}

/** A seven-segment digit (segments a…g), lit ones glowing. */
private fun DrawScope.digit(d: Int?, r: Rc) {
    val segs = listOf(listOf(0, 1, 2, 3, 4, 5), listOf(1, 2), listOf(0, 1, 3, 4, 6), listOf(0, 1, 2, 3, 6), listOf(1, 2, 5, 6),
        listOf(0, 2, 3, 5, 6), listOf(0, 2, 3, 4, 5, 6), listOf(0, 1, 2), listOf(0, 1, 2, 3, 4, 5, 6), listOf(0, 1, 2, 3, 5, 6))
    val on = d?.let { segs[it].toSet() } ?: emptySet()
    val t = r.w * 0.24
    val hw = r.w - t * 0.9; val vh = (r.h - t) / 2 - t * 0.35
    fun hSeg(y: Double) = Rc(r.x + t * 0.45, y, hw, t)
    fun vSeg(x: Double, y: Double) = Rc(x, y, t, vh)
    val rects = listOf(hSeg(r.y), vSeg(r.maxX - t, r.y + t * 0.6), vSeg(r.maxX - t, r.midY + t * 0.1), hSeg(r.maxY - t),
        vSeg(r.x, r.midY + t * 0.1), vSeg(r.x, r.y + t * 0.6), hSeg(r.midY - t / 2))
    rects.forEachIndexed { i, s ->
        if (i in on) {
            blurRRect(s.x, s.y, s.w, s.h, t * 0.45, glowC.op(0.9), t * 0.9)
            rrect(s.x, s.y, s.w, s.h, t * 0.45, ledOn)
        } else rrect(s.x, s.y, s.w, s.h, t * 0.45, ledOff)
    }
}

/** The static handheld: case, key mat, logo, printed labels and the decorative keys. */
private fun DrawScope.caseArt(tm: TextMeasurer, lay: LOLayout, movesLabel: String, litLabel: String) {
    val u = density.toDouble()
    val c = lay.caseRect
    val rad = c.w * 0.09
    val shell = Path()
    shell.m(c.x, c.y + rad + c.h * 0.02)
    shell.q(c.x, c.y + c.h * 0.02, c.x + rad, c.y + c.h * 0.02)
    shell.c(c.x + c.w * 0.35, c.y + c.h * 0.035, c.x + c.w * 0.6, c.y - c.h * 0.012, c.maxX - rad, c.y)
    shell.q(c.maxX, c.y, c.maxX, c.y + rad)
    shell.l(c.maxX, c.maxY - rad)
    shell.q(c.maxX, c.maxY, c.maxX - rad, c.maxY)
    shell.l(c.x + rad, c.maxY)
    shell.q(c.x, c.maxY, c.x, c.maxY - rad)
    shell.close()
    translate(0f, (c.w * 0.02).f) { blurPath(shell, Color.Black.op(0.6), c.w * 0.03) }
    drawPath(shell, lin(listOf(caseHi, caseLo.mix(caseHi, 0.35), caseLo), c.x, c.y, c.maxX * 0.4 + c.x * 0.6, c.maxY))
    clipPath(shell) {
        val ex = c.x - c.w * 0.3; val ey = c.y - c.h * 0.25
        drawOval(radial(listOf(Color.White.op(0.35), Color.Transparent), c.x + c.w * 0.25, c.y + c.h * 0.02, c.w * 0.7), off(ex, ey), sz(c.w * 1.1, c.h * 0.55))
    }
    strokePath(shell, caseInk.op(0.9), 1.5 * u)
    translate(0f, (1.5 * u).f) { strokePath(shell, Color.White.op(0.35), u) }
    // Key mat: dark rubber sunk into the case.
    val m = lay.mat
    rrect(m.x, m.y + 1.5 * u, m.w, m.h, m.w * 0.06, Color.White.op(0.5))
    rrect(m.x, m.y, m.w, m.h, m.w * 0.06, vgrad(listOf(matC.shade(0.35), matC, matC.lit(0.06)), m.y, m.maxY))
    rrectStroke(m.x, m.y, m.w, m.h, m.w * 0.06, Color.Black.op(0.55), 1.2 * u)
    logo(tm, lay.logo)
    val fs = max(8.5 * u, lay.led.h * 0.3)
    val ly = lay.led.maxY + fs * 0.9
    for ((t, fx) in listOf(movesLabel to 0.27, litLabel to 0.73)) text(tm, t, lay.led.x + lay.led.w * fx, ly, fs, caseInk, FontWeight.ExtraBold)
    val bez = lay.led.inset(-3 * u, -3 * u)
    rrectStroke(bez.x, bez.y + 1.2 * u, bez.w, bez.h, bez.h * 0.22, Color.White.op(0.45), u)
    rrect(bez.x, bez.y, bez.w, bez.h, bez.h * 0.22, caseInk)
    lay.slot?.let { s ->
        val g = s.inset(-2 * u, -2 * u)
        rrect(g.x, g.y, g.w, g.h, g.h / 2, caseInk.op(0.9))
        rrectStroke(g.x, g.y + 1.2 * u, g.w, g.h, g.h / 2, Color.White.op(0.4), u)
    }
    lay.keys?.let { menuKeys(it) }
}

/** "LIGHTS OUT" with the little grid of coloured squares. */
private fun DrawScope.logo(tm: TextMeasurer, r: Rc) {
    val e = r.h * 0.2
    val colors = listOf(logoRed, logoYellow, logoBlue, logoYellow, logoBlue, logoRed)
    val ox = r.x + e * 0.3; val oy = r.midY - e * 1.05
    for (i in 0 until 6) {
        val sx = ox + (i % 2) * e * 1.12; val sy = oy + (i / 2) * e * 0.72
        rrect(sx, sy, e, e * 0.62, e * 0.12, colors[i])
        rrectStroke(sx, sy, e, e * 0.62, e * 0.12, Color.Black.op(0.35), 0.6 * density)
    }
    // SF's expanded width → wide letter spacing.
    val fs = r.h * 0.4
    val sp = fs * 0.08
    val lightsW = textWidth(tm, "LIGHTS ", fs, FontWeight.Black) + sp * 7
    val totalW = lightsW + textWidth(tm, "OUT", fs, FontWeight.Black) + sp * 3
    val avail = r.w - e * 2.8
    val k = min(1.0, avail / max(1.0, totalW))
    val x0 = r.x + e * 2.8
    scale(k.f, k.f, off(x0, r.midY)) {
        text(tm, "LIGHTS OUT", x0, r.midY + 1.2 * density, fs, Color.White.op(0.55), FontWeight.Black, anchorX = 0.0, spacing = sp)
        text(tm, "LIGHTS ", x0, r.midY, fs, caseInk, FontWeight.Black, anchorX = 0.0, spacing = sp)
        text(tm, "OUT", x0 + lightsW, r.midY, fs, logoRed, FontWeight.Black, anchorX = 0.0, spacing = sp)
    }
}

/** The violet SELECT oval and four yellow pill keys. */
private fun DrawScope.menuKeys(r: Rc) {
    val u = density.toDouble()
    val o = Rc(r.x + r.w * 0.02, r.y + r.h * 0.1, r.w * 0.26, r.h * 0.8)
    oval(o.x, o.y + r.h * 0.08, o.w, o.h, Color.Black.op(0.35))
    drawOval(vgrad(listOf(selectC.lit(0.3), selectC, selectC.shade(0.3)), o.y, o.maxY), off(o.x, o.y), sz(o.w, o.h))
    oval(o.x + o.w * 0.18, o.y + o.h * 0.12, o.w * 0.5, o.h * 0.28, Color.White.op(0.35))
    ellipseStroke(o.midX, o.midY, o.w / 2, o.h / 2, Color.Black.op(0.45), u)
    val pw = r.w * 0.12; val ph = r.h * 0.34
    for (i in 0 until 4) {
        val x = r.x + r.w * 0.4 + i * r.w * 0.155
        val y = r.midY - ph / 2 + (if (i % 2 == 0) -r.h * 0.12 else r.h * 0.12)
        rrect(x, y + ph * 0.25, pw, ph, ph / 2, Color.Black.op(0.3))
        rrect(x, y, pw, ph, ph / 2, vgrad(listOf(pillC.lit(0.35), pillC, pillC.shade(0.25)), y, y + ph))
        rrectStroke(x, y, pw, ph, ph / 2, Color.Black.op(0.4), 0.8 * u)
    }
}

/** The key grid: bloom, keys, the victory chase round the rim, and the demo finger. */
private fun DrawScope.keypad(grid: BooleanArray, n: Int, pulse: Int, finger: Boolean, chaseStart: Double?, cell: Double, spacing: Double, handP: VectorPainter) {
    val count = n * n
    fun rect(i: Int) = Rc((i % n) * (cell + spacing), (i / n) * (cell + spacing), cell, cell)
    val chase = DoubleArray(count)
    if (chaseStart != null) {
        val e = nowSec() - chaseStart
        val rim = if (n <= 1) listOf(0) else buildList {
            for (c in 0 until n) add(c)
            for (row in 1 until n) add(row * n + n - 1)
            for (c in n - 2 downTo 0) add((n - 1) * n + c)
            for (row in n - 2 downTo 1) add(row * n)
        }
        if (e < 1.25) {
            val head = e / 1.25 * rim.size * 2
            for (k in 0 until 4) {
                val p = floor(head).toInt() - k
                if (p < 0) continue
                val idx = rim[p % rim.size]
                chase[idx] = max(chase[idx], 1 - k * 0.26)
            }
        }
    }
    fun level(i: Int) = max(if (i < grid.size && grid[i]) 1.0 else 0.0, chase[i])
    for (i in 0 until count) {
        val lv = level(i)
        if (lv <= 0) continue
        val r = rect(i)
        val inner = (0.2 / 0.8).toFloat()
        drawCircle(androidx.compose.ui.graphics.Brush.radialGradient(0f to glowC.op(0.55 * lv), inner to glowC.op(0.55 * lv), 1f to Color.Transparent,
            center = off(r.midX, r.midY), radius = (cell * 0.8).f), (cell * 0.8).f, off(r.midX, r.midY))
    }
    for (i in 0 until count) key(rect(i), level(i) > 0, level(i), i == pulse)
    if (finger && pulse in 0 until count) {
        val r = rect(pulse); val s = cell * 0.62
        hand(handP, r.midX - s * 0.2, r.midY - s * 0.02, s)
    }
}

/** The red LED readout: moves on the left, lights still on at the right. */
private fun DrawScope.readout(w: Double, h: Double, moves: Int, lit: Int) {
    val u = density.toDouble()
    rrect(0.0, 0.0, w, h, h * 0.2, ledGlass)
    rrect(2 * u, 2 * u, w - 4 * u, h * 0.4, h * 0.15, vgrad(listOf(Color.White.op(0.1), Color.Transparent), 0.0, h * 0.4))
    val dh = h * 0.68; val dw = dh * 0.58
    for ((value, fx) in listOf(min(99, moves) to 0.27, min(99, lit) to 0.73)) {
        val cx = w * fx
        digit(if (value >= 10) value / 10 else null, Rc(cx - dw * 1.12, (h - dh) / 2, dw, dh))
        digit(value % 10, Rc(cx + dw * 0.12, (h - dh) / 2, dw, dh))
    }
    rect(w * 0.5 - 0.5 * u, h * 0.2, u, h * 0.6, ledOff)
}

/** The clock as an LED bar in a slot on the case: pink-red, blinking once it runs low. */
private fun DrawScope.timeBarArt(s: Rc, frac: Double, timeLeft: Double) {
    val u = density.toDouble()
    rrect(s.x, s.y, s.w, s.h, s.h / 2, slotC)
    rrectStroke(s.x, s.y, s.w, s.h, s.h / 2, Color.Black.op(0.55), u)
    if (frac <= 0) return
    val blink = if (frac < 0.3) 0.45 + 0.55 * abs(sin(timeLeft * PI * 1.6)) else 1.0
    val pad = s.h * 0.16
    val bw = max(s.h, s.w * frac) - pad * 2; val bh = s.h - pad * 2
    withAlpha(blink) {
        blurRRect(s.x + pad, s.y + pad, bw, bh, bh / 2, glowC.op(0.8), s.h * 0.6)
        rrect(s.x + pad, s.y + pad, bw, bh, bh / 2, vgrad(listOf(onHi, onC, onLo), s.y + pad, s.y + pad + bh))
    }
}
