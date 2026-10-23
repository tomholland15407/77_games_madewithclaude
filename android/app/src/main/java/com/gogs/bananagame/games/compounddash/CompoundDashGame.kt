package com.gogs.bananagame.games.compounddash

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/** Brain — Compound Dash (was "Cover Fire"; iOS CoverFireGame.swift): sneak past sniper nests to the helipad. */
object CompoundDashGame {
    val definition = GameDefinition(
        id = "cover-fire",
        title = "Compound Dash",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Reach the exit without getting shot. Move with the d-pad.",
                "Snipers fire a charging beam the instant they see you.",
                "Break their line of sight before it completes — hide behind a wall or shove a crate into the gap.",
            ),
            bulletsVI = listOf(
                "Đến lối ra mà không bị bắn. Di chuyển bằng d-pad.",
                "Lính bắn tỉa nạp một tia sáng ngay khi nhìn thấy bạn.",
                "Cắt tầm nhìn của chúng trước khi nạp xong — nấp sau tường hoặc đẩy một thùng vào khe hở.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> CompoundDashView(level, onWin, onFail) }
    )
}

private const val COLS = 11
private const val ROWS = 15
private data class CP(val r: Int, val c: Int)
private class Sniper(val cell: CP) { var charge = 0.0 }

private class CompoundWorld(val level: Int) {
    val sniperCount = listOf(1, 1, 1, 2, 2, 3, 3)[min(level, 7) - 1]
    val chargeTime = listOf(2.4, 2.1, 1.8, 1.6, 1.4, 1.2, 1.0)[min(level, 7) - 1]
    val crateCount = listOf(8, 7, 6, 6, 5, 4, 3)[min(level, 7) - 1]
    val wallBlocks = listOf(3, 3, 2, 2, 2, 1, 1)[min(level, 7) - 1]
    val timeLimit = (40 - level * 2).toDouble()
    val moveInterval = 0.13
    var playing = true
    var walls = Array(ROWS) { BooleanArray(COLS) }
    val crates = HashSet<CP>()
    var snipers = listOf<Sniper>()
    var player = CP(1, 1)
    var exit = CP(1, 1)
    var moveDir = 0 to 0
    var stepCD = 0.0
    var timeLeft = timeLimit
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    fun isWall(r: Int, c: Int) = if (r !in 0 until ROWS || c !in 0 until COLS) true else walls[r][c]
    private fun manhattan(a: CP, b: CP) = abs(a.r - b.r) + abs(a.c - b.c)

    fun hasLOS(a: CP, b: CP): Boolean {
        val dr = b.r - a.r; val dc = b.c - a.c
        val steps = max(abs(dr), abs(dc))
        if (steps <= 0) return true
        for (i in 1 until steps) {
            val t = i.toDouble() / steps
            val r = (a.r + dr * t).roundHalfAway(); val c = (a.c + dc * t).roundHalfAway()
            if (isWall(r, c) || CP(r, c) in crates) return false
        }
        return true
    }

    private fun Double.roundHalfAway(): Int = if (this >= 0) (this + 0.5).toInt() else -((-this + 0.5).toInt())

    fun setup() {
        val w = Array(ROWS) { BooleanArray(COLS) }
        for (r in 0 until ROWS) { w[r][0] = true; w[r][COLS - 1] = true }
        for (c in 0 until COLS) { w[0][c] = true; w[ROWS - 1][c] = true }
        var placed = 0; var tries = 0
        while (placed < wallBlocks && tries < 120) {
            tries++
            val bw = rndInt(1..2); val bh = rndInt(1..2)
            val c0 = rndInt(2..(COLS - 2 - bw)); val r0 = rndInt(3..(ROWS - 4 - bh))
            var ok = true
            for (r in (r0 - 1)..(r0 + bh)) for (c in (c0 - 1)..(c0 + bw)) if (w[r][c]) ok = false
            if (!ok) continue
            for (r in r0 until r0 + bh) for (c in c0 until c0 + bw) w[r][c] = true
            placed++
        }
        walls = w
        player = CP(1, 1); exit = CP(ROWS - 2, COLS - 2)
        val open = ArrayList<CP>()
        for (r in 2 until ROWS - 2) for (c in 1 until COLS - 1) if (!w[r][c]) open.add(CP(r, c))
        val ss = ArrayList<Sniper>()
        for (cand in open.shuffled()) {
            if (!(manhattan(cand, player) >= 4 && cand != exit && (cand.c <= 2 || cand.c >= COLS - 3))) continue
            if (ss.all { manhattan(it.cell, cand) >= 4 }) { ss.add(Sniper(cand)); if (ss.size == sniperCount) break }
        }
        var guard = 0
        while (ss.size < sniperCount && guard++ < 1000) {
            val any = open.pick()
            if (ss.none { it.cell == any } && manhattan(any, player) >= 3) ss.add(Sniper(any))
        }
        snipers = ss
        val sniperCells = ss.map { it.cell }.toSet()
        crates.clear()
        val near = min(2, crateCount)
        for (cand in open.shuffled()) {
            if (!(manhattan(cand, player) in 1..3 && cand != exit && cand !in sniperCells)) continue
            if (crates.size >= near) break
            crates.add(cand)
        }
        for (cand in open.shuffled()) {
            if (cand == player || cand == exit || cand in sniperCells || cand in crates) continue
            if (crates.size >= crateCount) break
            if (crates.all { manhattan(it, cand) >= 2 }) crates.add(cand)
        }
        moveDir = 0 to 0; stepCD = 0.0; timeLeft = timeLimit; playing = true
    }

    fun demoSetup() {
        val w = Array(ROWS) { BooleanArray(COLS) }
        for (r in 0 until ROWS) { w[r][0] = true; w[r][COLS - 1] = true }
        for (c in 0 until COLS) { w[0][c] = true; w[ROWS - 1][c] = true }
        for (c in 1..9) if (c != 6) w[9][c] = true
        walls = w
        player = CP(11, 2); exit = CP(11, 8)
        snipers = listOf(Sniper(CP(2, 6)))
        crates.clear(); crates.add(CP(5, 3)); crates.add(CP(6, 8))
        moveDir = 0 to 0; stepCD = 0.0; timeLeft = timeLimit; playing = true
    }

    fun step(dt: Double) {
        if (!playing) return
        stepCD -= dt
        if (moveDir != (0 to 0) && stepCD <= 0) { tryStep(moveDir.first, moveDir.second); stepCD = moveInterval }
        for (s in snipers) {
            if (hasLOS(s.cell, player)) {
                s.charge += dt
                if (s.charge >= chargeTime) { fail(); return }
            } else s.charge = max(0.0, s.charge - dt * 3)
        }
        if (player == exit) { win(); return }
        timeLeft -= dt
        if (timeLeft <= 0) { timeLeft = 0.0; fail() }
    }

    fun tryStep(dc: Int, dr: Int) {
        val t = CP(player.r + dr, player.c + dc)
        if (isWall(t.r, t.c)) return
        if (t in crates) {
            val b = CP(t.r + dr, t.c + dc)
            if (isWall(b.r, b.c) || b in crates) return
            crates.remove(t); crates.add(b); player = t
            SoundManager.tap(); Haptics.tap()
            return
        }
        player = t
        SoundManager.tap()
    }

    fun win() { if (!playing) return; playing = false; Haptics.success(); SoundManager.tap(); onWin() }
    fun fail() { if (!playing) return; playing = false; Haptics.warning(); SoundManager.error(); onFail() }
}

@Composable
private fun CompoundDashView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { CompoundWorld(level).also { if (!isDemo) it.setup() } }
    world.onWin = onWin; world.onFail = onFail
    var demoDir by remember { mutableStateOf<Pair<Int, Int>?>(null) }
    var tickD by remember { mutableStateOf(0) }
    val tm = rememberTextMeasurer()
    val tick by rememberFrameLoop(running = true) { dt -> if (!isDemo) world.step(dt) }

    LaunchedEffect(Unit) {
        if (!isDemo) return@LaunchedEffect
        suspend fun demoWait(dur: Double) {
            repeat(max(1, (dur / 0.016).toInt())) {
                for (s in world.snipers) {
                    if (world.hasLOS(s.cell, world.player)) s.charge = min(world.chargeTime * 0.7, s.charge + 0.016)
                    else s.charge = max(0.0, s.charge - 0.016 * 3)
                }
                tickD++
                delay(16)
            }
        }
        while (isActive) {
            world.demoSetup()
            demoWait(0.7)
            repeat(6) {
                demoDir = 1 to 0
                world.tryStep(1, 0)
                demoWait(0.3)
                demoDir = null
                demoWait(0.2)
            }
            if (world.player == world.exit) world.win()
            demoWait(1.2)
        }
    }

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .background(rgb(0.16, 0.17, 0.12))
            .padding(top = if (isDemo) 8.dp else 12.dp, bottom = if (isDemo) 8.dp else 10.dp, start = if (isDemo) 6.dp else 10.dp, end = if (isDemo) 6.dp else 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(if (isDemo) 6.dp else 10.dp)
    ) {
        tick; tickD
        Row(horizontalArrangement = Arrangement.spacedBy(if (isDemo) 8.dp else 12.dp)) {
            for (s in world.snipers) {
                Canvas(Modifier.size(if (isDemo) 20.dp else 26.dp)) {
                    tick; tickD
                    scopeGauge(min(1.0, s.charge / world.chargeTime), world.hasLOS(s.cell, world.player))
                }
            }
        }
        if (!isDemo) TimeBar(world.timeLeft / world.timeLimit, Modifier.fillMaxWidth().padding(horizontal = 50.dp).height(5.dp))
        Canvas(Modifier.fillMaxWidth().weight(1f).clip(RoundedCornerShape(if (isDemo) 8.dp else 12.dp))) {
            tick; tickD
            val w = size.width.toDouble(); val h = size.height.toDouble()
            val firstRow = if (isDemo) 1 else 0
            val shownRows = if (isDemo) 12 else ROWS
            val cell = min(w / COLS, h / shownRows)
            val ox = (w - cell * COLS) / 2; val oy = (h - cell * shownRows) / 2 - firstRow * cell
            ground(cell, ox, oy)
            drawCompound(world, tm, cell, ox, oy)
        }
        val keys = if (isDemo) listOf(listOf(-1 to 0, 0 to -1, 0 to 1, 1 to 0)) else listOf(listOf(0 to -1), listOf(-1 to 0, 1 to 0), listOf(0 to 1))
        Column(Modifier.padding(bottom = if (isDemo) 0.dp else 6.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            for (row in keys) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for ((dc, dr) in row) {
                    HoldKey(Modifier, enabled = !isDemo,
                        onDown = { if (world.playing && world.moveDir != (dc to dr)) { world.moveDir = dc to dr; world.stepCD = 0.0 } },
                        onUp = { if (world.moveDir == (dc to dr)) world.moveDir = 0 to 0 }) { held ->
                        val pressed = held || (demoDir == (dc to dr))
                        val sc by animateFloatAsState(if (pressed) 0.9f else 1f, tween(100), label = "k")
                        val icon = when { dr < 0 -> Icons.Filled.KeyboardArrowUp; dr > 0 -> Icons.Filled.KeyboardArrowDown
                            dc < 0 -> Icons.Filled.KeyboardArrowLeft; else -> Icons.Filled.KeyboardArrowRight }
                        androidx.compose.foundation.layout.Box(
                            Modifier.scale(sc).size(if (isDemo) 52.dp else 74.dp, if (isDemo) 34.dp else 52.dp)
                                .background(if (pressed) BananaTheme.banana else rgb(0.3, 0.34, 0.2), RoundedCornerShape(12.dp))
                                .border(1.5.dp, Color.Black.op(0.35), RoundedCornerShape(12.dp)),
                            contentAlignment = Alignment.Center
                        ) { Icon(icon, null, tint = if (pressed) Color.Black else rgb(0.92, 0.9, 0.8), modifier = Modifier.size(if (isDemo) 22.dp else 30.dp)) }
                    }
                }
            }
        }
    }
}

private val BAG = rgb(0.74, 0.66, 0.46)

private fun DrawScope.ground(cell: Double, ox: Double, oy: Double) {
    drawRect(rgb(0.16, 0.17, 0.12))
    val fw = cell * COLS; val fh = cell * ROWS
    rect(ox, oy, fw, fh, lin(listOf(rgb(0.86, 0.76, 0.55), rgb(0.78, 0.67, 0.46)), ox, oy, ox + fw, oy + fh))
    for (k in 0 until COLS * ROWS / 2) {
        val fx = abs((sin(k * 12.9898) * 43758.5453) % 1.0)
        val fy = abs((sin(k * 78.233) * 24634.6345) % 1.0)
        val r = cell * (if (k % 5 == 0) 0.5 else 0.07)
        oval(ox + fx * fw - r, oy + fy * fh - r * 0.6, r * 2, r * 1.2, rgb(0.6, 0.5, 0.32).op(if (k % 5 == 0) 0.12 else 0.35))
    }
}

private fun DrawScope.drawCompound(w: CompoundWorld, tm: TextMeasurer, cell: Double, ox: Double, oy: Double) {
    fun rx(c: Int) = ox + c * cell
    fun ry(r: Int) = oy + r * cell
    fun mid(p: CP) = P(ox + (p.c + 0.5) * cell, oy + (p.r + 0.5) * cell)
    for (r in 0 until ROWS) for (c in 0 until COLS) if (w.walls[r][c]) {
        val border = r == 0 || c == 0 || r == ROWS - 1 || c == COLS - 1
        if (border) barrier(rx(c), ry(r), cell) else sandbags(rx(c), ry(r), cell, r)
    }
    helipad(tm, rx(w.exit.c), ry(w.exit.r), cell)
    for (cr in w.crates) crate(rx(cr.c), ry(cr.r), cell)
    val now = nowSec()
    for (s in w.snipers) if (w.hasLOS(s.cell, w.player)) {
        val t = min(1.0, s.charge / w.chargeTime)
        val pulse = 0.75 + 0.25 * sin(now * (8 + 22 * t))
        val a = mid(s.cell); val b = mid(w.player)
        line(a.x, a.y, b.x, b.y, rgb(1.0, 0.1, 0.08).op(0.25 * pulse), cell * (0.12 + 0.2 * t))
        line(a.x, a.y, b.x, b.y, rgb(1.0, 0.25 + 0.5 * (1 - t), 0.2).op(pulse), max(1.0, cell * (0.03 + 0.07 * t)))
    }
    for (s in w.snipers) {
        val m = mid(s.cell)
        val aim = if (w.hasLOS(s.cell, w.player)) mid(w.player) else P(m.x, m.y + cell)
        sniperNest(m, aim, cell)
    }
    soldier(mid(w.player), cell, w.snipers.any { w.hasLOS(it.cell, w.player) })
}

private fun DrawScope.barrier(x: Double, y: Double, s: Double) {
    rect(x - 0.3, y - 0.3, s + 0.6, s + 0.6, lin(listOf(rgb(0.66, 0.65, 0.62), rgb(0.5, 0.49, 0.46)), x, y, x + s, y + s))
    rectStroke(x + s * 0.12, y + s * 0.12, s * 0.76, s * 0.76, Color.White.op(0.14), 1.0)
    oval(x + s * 0.3, y + s * 0.4, s * 0.12, s * 0.08, Color.Black.op(0.15))
}

private fun DrawScope.sandbags(x: Double, y: Double, s: Double, row: Int) {
    rect(x + s * 0.08, y + s * 0.1, s, s, Color.Black.op(0.18))
    val h = s / 2; val bw = s / 2
    clipRect((x - s * 0.06).f, (y - s * 0.02).f, (x + s * 1.06).f, (y + s * 1.02).f) {
        for (k in 0 until 2) {
            val shift = if ((row * 2 + k) % 2 == 0) 0.0 else bw / 2
            for (i in -1..2) {
                val bx = x + i * bw + shift + 0.5; val by = y + k * h + 0.8; val ww = bw - 1.0; val hh = h - 1.6
                rrect(bx, by, ww, hh, h * 0.45, vgrad(listOf(BAG.lit(0.18), BAG, BAG.shade(0.25)), by, by + hh))
                rrectStroke(bx, by, ww, hh, h * 0.45, BAG.shade(0.5), max(0.6, h * 0.06))
                line(bx + ww / 2, by + h * 0.2, bx + ww / 2, by + hh - h * 0.2, BAG.shade(0.4).op(0.6), max(0.5, h * 0.04))
            }
        }
    }
}

private fun DrawScope.crate(x: Double, y: Double, s: Double) {
    val bx = x + s * 0.08; val by = y + s * 0.08; val b = s * 0.84
    val olive = rgb(0.36, 0.42, 0.22)
    rrect(bx + s * 0.06, by + s * 0.08, b, b, 3.0, Color.Black.op(0.28))
    rrect(bx, by, b, b, 3.0, lin(listOf(olive.lit(0.15), olive.shade(0.12)), bx, by, bx + b, by + b))
    for (k in 1..2) { val yy = by + b * k / 3; line(bx, yy, bx + b, yy, olive.shade(0.45), max(0.8, s * 0.03), androidx.compose.ui.graphics.StrokeCap.Butt) }
    rrectStroke(bx, by, b, b, 3.0, olive.shade(0.6), max(1.0, s * 0.05))
    rect(bx + b / 2 - b * 0.22, by + b / 2 - b * 0.07, b * 0.44, b * 0.14, rgb(0.9, 0.86, 0.6, 0.85))
    for ((fx, fy) in listOf(0.0 to 0.0, 1.0 to 0.0, 0.0 to 1.0, 1.0 to 1.0)) rect(bx + b * fx - b * 0.09, by + b * fy - b * 0.09, b * 0.18, b * 0.18, rgb(0.55, 0.56, 0.52))
}

private fun DrawScope.helipad(tm: TextMeasurer, x: Double, y: Double, s: Double) {
    val px = x + s / 2; val py = y + s / 2; val R = s * 0.62
    circle(px, py, R * 1.25, radial(listOf(rgb(0.4, 1.0, 0.5).op(0.4), Color.Transparent), px, py, R * 1.25))
    circle(px, py, R, rgb(0.24, 0.26, 0.24))
    circleStroke(px, py, R * 0.84, rgb(0.98, 0.84, 0.2), max(1.0, R * 0.1))
    text(tm, "H", px, py, R * 1.05, Color.White, FontWeight.Black)
}

private fun DrawScope.sniperNest(p: P, aim: P, s: Double) {
    for (k in 0 until 8) {
        val a = k / 8.0 * 2 * PI
        val qx = p.x + cos(a) * s * 0.42; val qy = p.y + sin(a) * s * 0.42
        ellipse(qx, qy, s * 0.16, s * 0.11, BAG.shade(0.1))
        ellipseStroke(qx, qy, s * 0.16, s * 0.11, BAG.shade(0.5), 0.8)
    }
    val a = atan2(aim.y - p.y, aim.x - p.x)
    translate(p.x.f, p.y.f) {
        rotate((a * 180 / PI).f, androidx.compose.ui.geometry.Offset.Zero) {
            rrect(0.0, -s * 0.04, s * 0.62, s * 0.08, s * 0.02, rgb(0.12, 0.12, 0.12))
            oval(-s * 0.2, -s * 0.24, s * 0.34, s * 0.48, rgb(0.3, 0.34, 0.22))
            circle(-s * 0.02, 0.0, s * 0.17, radial(listOf(rgb(0.45, 0.5, 0.32), rgb(0.22, 0.26, 0.15)), -s * 0.06, -s * 0.05, s * 0.2))
            circle(s * 0.2, 0.0, s * 0.04, rgb(1.0, 0.2, 0.15))
        }
    }
}

private fun DrawScope.soldier(p: P, s: Double, targeted: Boolean) {
    oval(p.x - s * 0.36, p.y - s * 0.12, s * 0.8, s * 0.56, Color.Black.op(0.22))
    val body = Path(); body.m(p.x - s * 0.16, p.y - s * 0.44)
    body.q(p.x + s * 0.62, p.y, p.x - s * 0.12, p.y + s * 0.44)
    body.q(p.x + s * 0.06, p.y, p.x - s * 0.16, p.y - s * 0.44); body.close()
    strokePath(body, Color.Black.op(0.55), max(2.0, s * 0.1))
    drawPath(body, hgrad(listOf(rgb(1.0, 0.95, 0.5), rgb(0.98, 0.78, 0.12)), p.x - s * 0.1, p.x + s * 0.34))
    strokePath(body, rgb(0.45, 0.3, 0.05), max(1.0, s * 0.04))
    ellipse(p.x + s * 0.01, p.y - s * 0.31, s * 0.21, s * 0.15, radial(listOf(rgb(0.5, 0.56, 0.32), rgb(0.25, 0.3, 0.15)), p.x - s * 0.02, p.y - s * 0.38, s * 0.24))
    ellipseStroke(p.x + s * 0.01, p.y - s * 0.31, s * 0.21, s * 0.15, rgb(0.12, 0.15, 0.06), max(1.0, s * 0.035))
    if (targeted) {
        circle(p.x + s * 0.12, p.y + s * 0.08, s * 0.13, rgb(1.0, 0.1, 0.1, 0.3))
        circle(p.x + s * 0.12, p.y + s * 0.08, s * 0.05, rgb(1.0, 0.15, 0.1))
    }
}

private fun DrawScope.scopeGauge(t: Double, locked: Boolean) {
    val px = size.width / 2.0; val py = size.height / 2.0
    val R = min(size.width, size.height) / 2.0 - 1.5 * density
    circle(px, py, R, Color.Black.op(0.35))
    if (t > 0) drawArc(rgb(1.0, 0.18, 0.12, 0.85), -90f, (360 * t).f, true, off(px - R, py - R), sz(R * 2, R * 2))
    circleStroke(px, py, R, if (locked) rgb(1.0, 0.3, 0.25) else Color.White.op(0.7), 2.0 * density)
    line(px - R, py, px + R, py, Color.White.op(0.75), density.toDouble(), androidx.compose.ui.graphics.StrokeCap.Butt)
    line(px, py - R, px, py + R, Color.White.op(0.75), density.toDouble(), androidx.compose.ui.graphics.StrokeCap.Butt)
}
