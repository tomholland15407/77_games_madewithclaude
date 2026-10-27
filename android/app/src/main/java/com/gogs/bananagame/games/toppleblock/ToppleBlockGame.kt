package com.gogs.bananagame.games.toppleblock

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.ArrowDropUp
import androidx.compose.material.icons.filled.ArrowLeft
import androidx.compose.material.icons.filled.ArrowRight
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
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Matrix
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/** Brain — Topple Block (was "Bloxorz"; iOS BloxorzGame.swift): roll a 1×2 block upright into the pit. */
object ToppleBlockGame {
    val definition = GameDefinition(
        id = "bloxorz",
        title = "Topple Block",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Use the d-pad to roll the 1×2 block end over end across the tiles.",
                "Upright it covers one square; tipped over it covers two.",
                "Land it standing exactly on the goal square to win.",
                "Roll off the board or over a hole and you drop to level 1.",
            ),
            bulletsVI = listOf(
                "Dùng d-pad để lăn khối 1×2 lộn đầu qua các ô.",
                "Đứng thẳng nó chiếm một ô; ngã ra nó chiếm hai ô.",
                "Cho nó đứng đúng trên ô mục tiêu để thắng.",
                "Lăn khỏi bàn hoặc qua một lỗ sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        prefetch = { level -> val p = params(level); BoardCache.prefetch(key(level)) { BloxGen.makePuzzle(p) } },
        content = { level, onWin, onFail -> ToppleBlockView(level, onWin, onFail) }
    )

    fun key(level: Int) = BoardCache.key("bloxorz", level)
    fun params(level: Int) = listOf(
        BloxParams(4, 4, 0, 6), BloxParams(5, 5, 1, 9), BloxParams(5, 6, 3, 12), BloxParams(6, 6, 4, 16),
        BloxParams(6, 7, 6, 20), BloxParams(7, 7, 8, 26), BloxParams(7, 8, 10, 32),
    )[min(level, 7) - 1]
    fun timeLimit(level: Int) = listOf(40.0, 50.0, 60.0, 70.0, 75.0, 80.0, 85.0)[min(level, 7) - 1]
}

data class BCell(val r: Int, val c: Int)
data class BloxParams(val w: Int, val h: Int, val holes: Int, val minMoves: Int)
class BloxPuzzle(val w: Int, val h: Int, val tiles: Set<BCell>, val start: BCell, val goal: BCell)

object BloxGen {
    private val order = compareBy<BCell>({ it.r }, { it.c })

    /** The cells the block occupies after rolling one step in (dr, dc). */
    fun roll(block: List<BCell>, dr: Int, dc: Int): List<BCell> {
        val s = block.sortedWith(order)
        if (s.size == 1) {
            val p = s[0]
            return when {
                dc == 1 -> listOf(BCell(p.r, p.c + 1), BCell(p.r, p.c + 2))
                dc == -1 -> listOf(BCell(p.r, p.c - 2), BCell(p.r, p.c - 1))
                dr == 1 -> listOf(BCell(p.r + 1, p.c), BCell(p.r + 2, p.c))
                else -> listOf(BCell(p.r - 2, p.c), BCell(p.r - 1, p.c))
            }
        }
        val a = s[0]; val b = s[1]
        return if (a.r == b.r) {
            when {
                dc == 1 -> listOf(BCell(a.r, a.c + 2))
                dc == -1 -> listOf(BCell(a.r, a.c - 1))
                dr == 1 -> listOf(BCell(a.r + 1, a.c), BCell(a.r + 1, a.c + 1))
                else -> listOf(BCell(a.r - 1, a.c), BCell(a.r - 1, a.c + 1))
            }
        } else {
            when {
                dr == 1 -> listOf(BCell(a.r + 2, a.c))
                dr == -1 -> listOf(BCell(a.r - 1, a.c))
                dc == 1 -> listOf(BCell(a.r, a.c + 1), BCell(a.r + 1, a.c + 1))
                else -> listOf(BCell(a.r, a.c - 1), BCell(a.r + 1, a.c - 1))
            }
        }
    }

    fun sorted(cells: List<BCell>) = cells.sortedWith(order)

    fun makePuzzle(p: BloxParams): BloxPuzzle {
        var best: BloxPuzzle? = null
        var bestMoves = -1
        repeat(300) {
            val cand = generate(p) ?: return@repeat
            val moves = solve(cand) ?: return@repeat
            if (moves >= p.minMoves) return cand
            if (moves > bestMoves) { bestMoves = moves; best = cand }
        }
        return best ?: fallback()
    }

    fun generate(p: BloxParams): BloxPuzzle? {
        val all = ArrayList<BCell>()
        for (r in 0 until p.h) for (c in 0 until p.w) all.add(BCell(r, c))
        val start = all.pick()
        var goal = all.pick()
        var guard = 0
        while (goal == start && guard < 50) { goal = all.pick(); guard++ }
        if (goal == start) return null
        val tiles = all.toHashSet()
        val removable = all.filter { it != start && it != goal }.shuffled().toMutableList()
        repeat(min(p.holes, removable.size)) { tiles.remove(removable.removeAt(removable.size - 1)) }
        return BloxPuzzle(p.w, p.h, tiles, start, goal)
    }

    fun solve(p: BloxPuzzle): Int? {
        val start = listOf(p.start)
        val seen = hashSetOf(start)
        val queue = ArrayDeque<Pair<List<BCell>, Int>>(); queue.add(start to 0)
        var expanded = 0
        while (queue.isNotEmpty()) {
            val (cells, d) = queue.removeFirst()
            if (++expanded > 150_000) return null
            if (cells.size == 1 && cells[0] == p.goal) return d
            for ((dr, dc) in listOf(0 to 1, 0 to -1, 1 to 0, -1 to 0)) {
                val next = sorted(roll(cells, dr, dc))
                if (!next.all { it in p.tiles }) continue
                if (seen.add(next)) queue.add(next to d + 1)
            }
        }
        return null
    }

    fun fallback(): BloxPuzzle {
        val all = HashSet<BCell>()
        for (r in 0 until 4) for (c in 0 until 4) all.add(BCell(r, c))
        return BloxPuzzle(4, 4, all, BCell(0, 0), BCell(3, 3))
    }
}

private class RollAnim(val from: List<BCell>, val dc: Int, val dr: Int, val t0: Double)

@Composable
private fun ToppleBlockView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val timeLimit = ToppleBlockGame.timeLimit(level)
    var playing by remember { mutableStateOf(true) }
    var ready by remember { mutableStateOf(false) }
    var w by remember { mutableIntStateOf(0) }
    var h by remember { mutableIntStateOf(0) }
    var tiles by remember { mutableStateOf(setOf<BCell>()) }
    var goal by remember { mutableStateOf(BCell(0, 0)) }
    var block by remember { mutableStateOf(listOf<BCell>()) }
    var timeLeft by remember { mutableDoubleStateOf(timeLimit) }
    var demoDir by remember { mutableStateOf<Pair<Int, Int>?>(null) }
    var moves by remember { mutableIntStateOf(0) }
    var rollAnim by remember { mutableStateOf<RollAnim?>(null) }
    var fallStart by remember { mutableStateOf<Double?>(null) }
    var sinkStart by remember { mutableStateOf<Double?>(null) }
    val shake = remember { Animatable(1f) }
    val scope = rememberCoroutineScope()

    fun win() { if (!playing) return; playing = false; onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }

    fun recordRoll(from: List<BCell>, dr: Int, dc: Int) {
        moves += 1
        val a = RollAnim(from, dc, dr, nowSec())
        rollAnim = a
        scope.launch { delay(200); if (rollAnim === a) rollAnim = null }
    }

    fun move(dr: Int, dc: Int) {
        if (!playing) return
        val next = BloxGen.sorted(BloxGen.roll(block, dr, dc))
        val before = block
        block = next
        recordRoll(before, dr, dc)
        if (next.all { it in tiles }) {
            SoundManager.tap(); Haptics.tap()
            if (block.size == 1 && block[0] == goal) { sinkStart = nowSec() + 0.16; win() }
        } else {
            playing = false
            fallStart = nowSec() + 0.16
            SoundManager.error(); Haptics.warning()
            scope.launch { shake.snapTo(0f); shake.animateTo(1f, tween(350)) }
            scope.launch { delay(350); onFail() }
        }
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            val seq = listOf(0 to 1, 0 to 1, 1 to 0, 1 to 0)
            while (isActive) {
                w = 4; h = 4
                tiles = (0 until 16).map { BCell(it / 4, it % 4) }.toSet()
                goal = BCell(3, 3); block = listOf(BCell(0, 0))
                moves = 0; rollAnim = null; fallStart = null; sinkStart = null
                ready = true; playing = true; timeLeft = timeLimit
                delay(700)
                for ((dr, dc) in seq) {
                    demoDir = dc to dr
                    move(dr, dc)
                    delay(400)
                    demoDir = null
                    delay(200)
                }
                delay(1300)
            }
        } else {
            val p = ToppleBlockGame.params(level)
            val t0 = System.currentTimeMillis()
            val puzzle = BoardCache.take(ToppleBlockGame.key(level)) { BloxGen.makePuzzle(p) }
            BoardCache.holdBrainstorm(t0, 0.7)
            w = puzzle.w; h = puzzle.h; tiles = puzzle.tiles; goal = puzzle.goal; block = listOf(puzzle.start)
            moves = 0; rollAnim = null; fallStart = null; sinkStart = null
            ready = true; playing = true; timeLeft = timeLimit
            val start = nowSec()
            while (isActive && playing) {
                delay(50)
                timeLeft = max(0.0, timeLimit - (nowSec() - start))
                if (timeLeft <= 0) { fail(); break }
            }
        }
    }

    if (!ready) { BrainstormingView(rgb(0.7, 0.16, 0.04), rgb(0.3, 0.04, 0.01)); return }

    val animating = rollAnim != null || fallStart != null || sinkStart != null
    val tick by rememberFrameLoop(running = animating)

    Box(Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))) {
        Canvas(Modifier.fillMaxSize()) { bloxSky() }
        Column(
            Modifier.fillMaxSize().padding(top = if (isDemo) 8.dp else 12.dp, bottom = if (isDemo) 8.dp else 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(if (isDemo) 4.dp else 8.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                val glow = Shadow(rgb(1.0, 0.45, 0.1, 0.9), androidx.compose.ui.geometry.Offset.Zero, 14f)
                Text(L("MOVES", "BƯỚC"), style = TextStyle(fontSize = (if (isDemo) 12 else 15).sp, fontWeight = FontWeight.ExtraBold,
                    fontFamily = Mono, color = rgb(1.0, 0.62, 0.3), shadow = glow))
                Spacer(Modifier.width(8.dp))
                Text("%03d".format(moves), style = TextStyle(fontSize = (if (isDemo) 18 else 24).sp, fontWeight = FontWeight.Black,
                    fontFamily = Mono, color = rgb(1.0, 0.88, 0.6), shadow = glow))
            }
            if (!isDemo) TimeBar(timeLeft / timeLimit, Modifier.fillMaxWidth().padding(horizontal = 60.dp).height(5.dp),
                fill = if (timeLeft / timeLimit < 0.3) rgb(1.0, 0.25, 0.15) else rgb(1.0, 0.7, 0.3), track = Color.Black.op(0.35))
            Canvas(Modifier.fillMaxWidth().weight(1f).graphicsLayer {
                val t = shake.value
                if (t < 1f) translationX = (5 * density * sin(t * PI * 3)).toFloat()
            }) {
                tick
                if (w <= 0) return@Canvas
                val pj = BloxProj.fit(w, h, size.width.toDouble(), size.height.toDouble(), 72.0 * density)
                for (t in tiles.sortedWith(compareBy<BCell>({ it.r }, { -it.c }))) BloxArt.slab(this, pj, t.c, t.r, t == goal)
                var box = BloxArt.box(block)
                var angle = 0.0
                var dir = 0 to 0
                val now = nowSec()
                rollAnim?.let { a ->
                    val k = min(1.0, (now - a.t0) / 0.16)
                    if (k < 1) { box = BloxArt.box(a.from); angle = (1 - (1 - k).pow(2)) * PI / 2; dir = a.dc to a.dr }
                }
                var dz = 0.0; var alpha = 1.0
                fallStart?.let { f -> val t = max(0.0, now - f); dz = -6 * t * t; alpha = max(0.0, 1 - t / 0.35) }
                sinkStart?.let { s -> val t = (now - s).coerceIn(0.0, 1.0 * 0.55) / 0.55; dz = -2.2 * t * t; alpha = 1 - t * 0.9 }
                BloxArt.block(this, pj, box, angle, dir, dz, alpha)
            }
            val rows = if (isDemo) listOf(listOf(-1 to 0, 0 to -1, 0 to 1, 1 to 0)) else listOf(listOf(0 to -1), listOf(-1 to 0, 0 to 1, 1 to 0))
            Column(Modifier.padding(bottom = if (isDemo) 0.dp else 4.dp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp)) {
                for (row in rows) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    for ((dc, dr) in row) ArrowKey(dc, dr, demoDir == (dc to dr), isDemo) { move(dr, dc) }
                }
            }
        }
    }
}

@Composable
private fun ArrowKey(dc: Int, dr: Int, lit: Boolean, isDemo: Boolean, onTap: () -> Unit) {
    HoldKey(Modifier, enabled = !isDemo, onDown = onTap) { held ->
        val on = lit || held
        val sc by animateFloatAsState(if (on) 0.93f else 1f, tween(80), label = "k")
        val icon = when { dr < 0 -> Icons.Filled.ArrowDropUp; dr > 0 -> Icons.Filled.ArrowDropDown; dc < 0 -> Icons.Filled.ArrowLeft; else -> Icons.Filled.ArrowRight }
        Box(
            Modifier.scale(sc).size(if (isDemo) 50.dp else 64.dp, if (isDemo) 34.dp else 48.dp)
                .shadow(if (on) 6.dp else 3.dp, RoundedCornerShape(9.dp), ambientColor = if (on) rgb(1.0, 0.5, 0.1) else Color.Black,
                    spotColor = if (on) rgb(1.0, 0.5, 0.1) else Color.Black)
                .background(if (on) Brush.verticalGradient(listOf(rgb(1.0, 0.78, 0.4), rgb(1.0, 0.5, 0.15))) else Brush.verticalGradient(listOf(gray(0.32), gray(0.16))),
                    RoundedCornerShape(9.dp))
                .border(1.dp, Color.Black.op(0.6), RoundedCornerShape(9.dp)),
            contentAlignment = Alignment.Center
        ) { Icon(icon, null, tint = if (on) rgb(0.25, 0.08, 0.0) else gray(0.85), modifier = Modifier.size(if (isDemo) 26.dp else 34.dp)) }
    }
}

/** The oblique camera: columns run right (slightly up), rows come toward you, height goes up. */
private class BloxProj(val s: Double, val ox: Double, val oy: Double) {
    fun pt(c: Double, r: Double, z: Double) = P(ox + s * (c * UX + r * VX), oy + s * (c * UY + r * VY - z * Z))

    companion object {
        const val UX = 1.0; const val UY = -0.1; const val VX = 0.3; const val VY = 0.7; const val Z = 0.9
        fun fit(w: Int, h: Int, sw: Double, sh: Double, cap: Double): BloxProj {
            if (w <= 0 || h <= 0 || sw <= 1 || sh <= 1) return BloxProj(1.0, 0.0, 0.0)
            var minX = Double.MAX_VALUE; var maxX = -Double.MAX_VALUE; var minY = Double.MAX_VALUE; var maxY = -Double.MAX_VALUE
            for (c in listOf(0, w)) for (r in listOf(0, h)) for (z in listOf(-0.18, 2.0)) {
                val x = c * UX + r * VX; val y = c * UY + r * VY - z * Z
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
            val s = minOf(sw * 0.94 / (maxX - minX), sh * 0.94 / (maxY - minY), cap)
            return BloxProj(s, (sw - (maxX - minX) * s) / 2 - minX * s, (sh - (maxY - minY) * s) / 2 - minY * s)
        }
    }
}

private object BloxArt {
    fun c(r: Double, g: Double, b: Double) = rgb(r, g, b)

    fun slab(d: DrawScope, pj: BloxProj, col: Int, row: Int, hole: Boolean) = with(d) {
        val g = 0.035; val t = 0.16
        val c0 = col + g; val c1 = col + 1 - g; val r0 = row + g; val r1 = row + 1 - g
        drawPath(polyPath(listOf(pj.pt(c0, r1, 0.0), pj.pt(c1, r1, 0.0), pj.pt(c1, r1, -t), pj.pt(c0, r1, -t))), c(0.34, 0.35, 0.37))
        drawPath(polyPath(listOf(pj.pt(c0, r0, 0.0), pj.pt(c0, r1, 0.0), pj.pt(c0, r1, -t), pj.pt(c0, r0, -t))), c(0.5, 0.51, 0.53))
        val tp = listOf(pj.pt(c0, r0, 0.0), pj.pt(c1, r0, 0.0), pj.pt(c1, r1, 0.0), pj.pt(c0, r1, 0.0))
        val top = polyPath(tp)
        if (hole) {
            drawPath(top, c(0.08, 0.06, 0.05))
            clipPath(top) {
                val dd = 0.7
                val a0 = pj.pt(c0, r0, 0.0); val a1 = pj.pt(c0, r0, -dd)
                drawPath(polyPath(listOf(pj.pt(c0, r0, 0.0), pj.pt(c1, r0, 0.0), pj.pt(c1, r0, -dd), pj.pt(c0, r0, -dd))),
                    lin(listOf(c(0.42, 0.4, 0.38), c(0.12, 0.1, 0.09)), a0.x, a0.y, a1.x, a1.y))
                val b0 = pj.pt(c1, r0, 0.0); val b1 = pj.pt(c1, r0, -dd)
                drawPath(polyPath(listOf(pj.pt(c1, r0, 0.0), pj.pt(c1, r1, 0.0), pj.pt(c1, r1, -dd), pj.pt(c1, r0, -dd))),
                    lin(listOf(c(0.3, 0.28, 0.26), c(0.08, 0.07, 0.06)), b0.x, b0.y, b1.x, b1.y))
            }
            strokePath(top, c(0.62, 0.62, 0.64), max(1.0, pj.s * 0.03))
        } else {
            drawPath(top, lin(listOf(c(0.86, 0.87, 0.88), c(0.74, 0.75, 0.77)), tp[0].x, tp[0].y, tp[2].x, tp[2].y))
            for (k in 0 until 5) {
                val hh = ((col * 73 + row * 31 + k * 17) % 97) / 97.0
                val h2 = ((col * 29 + row * 61 + k * 43) % 89) / 89.0
                val p = pj.pt(c0 + (c1 - c0) * (0.12 + 0.76 * hh), r0 + (r1 - r0) * (0.12 + 0.76 * h2), 0.0)
                val rr = pj.s * 0.035
                ellipse(p.x, p.y, rr, rr * 0.6, c(0.55, 0.56, 0.58).op(0.5))
            }
            strokePath(polyPath(listOf(tp[3], tp[0], tp[1]), close = false), Color.White.op(0.55), max(1.0, pj.s * 0.025))
            strokePath(top, c(0.45, 0.46, 0.48).op(0.7), max(0.6, pj.s * 0.012))
        }
    }

    class Box(val c0: Double, val c1: Double, val r0: Double, val r1: Double, val h: Double)

    fun box(cells: List<BCell>): Box {
        if (cells.isEmpty()) return Box(0.0, 1.0, 0.0, 1.0, 2.0)
        return Box(cells.minOf { it.c }.toDouble(), cells.maxOf { it.c } + 1.0, cells.minOf { it.r }.toDouble(), cells.maxOf { it.r } + 1.0,
            if (cells.size == 1) 2.0 else 1.0)
    }

    class V3(var c: Double, var r: Double, var z: Double)

    fun block(d: DrawScope, pj: BloxProj, b: Box, rollAngle: Double, dir: Pair<Int, Int>, dz: Double, alpha: Double) = with(d) {
        if (alpha <= 0.01) return@with
        val corners = ArrayList<V3>()
        for (zi in 0..1) for (yi in 0..1) for (xi in 0..1) corners.add(V3(if (xi == 0) b.c0 else b.c1, if (yi == 0) b.r0 else b.r1, if (zi == 0) 0.0 else b.h))
        val ca = cos(rollAngle); val sa = sin(rollAngle)
        val (ddc, ddr) = dir
        fun rot(p: V3): V3 {
            val q = V3(p.c, p.r, p.z)
            if (ddc == 1) { val e = p.c - b.c1; q.c = b.c1 + e * ca + p.z * sa; q.z = -e * sa + p.z * ca }
            if (ddc == -1) { val e = p.c - b.c0; q.c = b.c0 + e * ca - p.z * sa; q.z = e * sa + p.z * ca }
            if (ddr == 1) { val e = p.r - b.r1; q.r = b.r1 + e * ca + p.z * sa; q.z = -e * sa + p.z * ca }
            if (ddr == -1) { val e = p.r - b.r0; q.r = b.r0 + e * ca - p.z * sa; q.z = e * sa + p.z * ca }
            return q
        }
        fun rotN(n: V3): V3 {
            val q = V3(n.c, n.r, n.z)
            if (ddc == 1) { q.c = n.c * ca + n.z * sa; q.z = -n.c * sa + n.z * ca }
            if (ddc == -1) { q.c = n.c * ca - n.z * sa; q.z = n.c * sa + n.z * ca }
            if (ddr == 1) { q.r = n.r * ca + n.z * sa; q.z = -n.r * sa + n.z * ca }
            if (ddr == -1) { q.r = n.r * ca - n.z * sa; q.z = n.r * sa + n.z * ca }
            return q
        }
        val pts = corners.map { rot(it) }.map { pj.pt(it.c, it.r, it.z + dz) }
        val faces = listOf(
            listOf(4, 5, 7, 6) to V3(0.0, 0.0, 1.0), listOf(2, 3, 7, 6) to V3(0.0, 1.0, 0.0), listOf(0, 2, 6, 4) to V3(-1.0, 0.0, 0.0),
            listOf(1, 3, 7, 5) to V3(1.0, 0.0, 0.0), listOf(0, 1, 5, 4) to V3(0.0, -1.0, 0.0), listOf(0, 1, 3, 2) to V3(0.0, 0.0, -1.0),
        )
        val view = V3(-0.3, 1.0, 0.811)
        val light = V3(-0.34, 0.42, 0.84)
        withAlpha(alpha) {
            faces.forEachIndexed { fi, (idx, nrm) ->
                val n = rotN(nrm)
                if (n.c * view.c + n.r * view.r + n.z * view.z <= 0.001) return@forEachIndexed
                val q = idx.map { pts[it] }
                val shape = polyPath(q)
                clipPath(shape) {
                    val m = Matrix()
                    m.values[0] = (q[1].x - q[0].x).f; m.values[1] = (q[1].y - q[0].y).f
                    m.values[4] = (q[3].x - q[0].x).f; m.values[5] = (q[3].y - q[0].y).f
                    m.values[12] = q[0].x.f; m.values[13] = q[0].y.f
                    withTransform({ transform(m) }) { rust(fi) }
                }
                val bright = 0.38 + 0.62 * max(0.0, n.c * light.c + n.r * light.r + n.z * light.z)
                drawPath(shape, Color.Black.op(0.78 * (1 - bright)))
                strokePath(shape, c(0.16, 0.08, 0.05), max(1.0, pj.s * 0.025))
            }
        }
    }

    private fun DrawScope.rust(seed: Int) {
        rect(0.0, 0.0, 1.0, 1.0, lin(listOf(c(0.58, 0.3, 0.2), c(0.44, 0.22, 0.15)), 0.0, 0.0, 1.0, 1.0))
        fun h(a: Int, m: Int): Double { val v = sin(a * 12.9898 + m * 78.233 + seed * 37.719) * 43758.5453; return v - floor(v) }
        for (k in 0 until 22) {
            val x = h(37 + k, k); val y = h(53 + k * 3, k + 5); val sz = 0.05 + 0.12 * h(11 + k * 5, k + 9)
            val col = if (k % 3 == 0) c(0.46, 0.49, 0.56) else if (k % 3 == 1) c(0.84, 0.44, 0.16) else c(0.28, 0.13, 0.08)
            oval(x - sz / 2, y - sz * 0.4, sz, sz * 0.8, col.op(0.42))
        }
        for (k in 0 until 40) {
            val x = h(19 + k * 7, k + 2); val y = h(7 + k * 11, k + 4)
            oval(x, y, 0.025, 0.02, (if (k % 2 == 0) c(0.95, 0.6, 0.28) else c(0.2, 0.1, 0.06)).op(0.6))
        }
    }
}

private fun DrawScope.bloxSky() {
    val W = size.width.toDouble(); val H = size.height.toDouble()
    rect(0.0, 0.0, W, H, vgrad(listOf(rgb(0.84, 0.24, 0.04), rgb(0.66, 0.13, 0.03), rgb(0.36, 0.05, 0.01)), 0.0, H))
    val blur = max(W, H) * 0.04
    for (f in listOf(doubleArrayOf(0.1, 0.62, 0.7, 0.16, 0.5), doubleArrayOf(0.7, 0.75, 0.8, 0.2, 0.55), doubleArrayOf(0.3, 0.9, 0.9, 0.2, 0.6),
        doubleArrayOf(0.85, 0.12, 0.5, 0.14, 0.35), doubleArrayOf(0.05, 0.08, 0.4, 0.12, 0.3), doubleArrayOf(0.5, 0.45, 0.5, 0.1, 0.25))) {
        blurOval(W * (f[0] - f[2] / 2), H * (f[1] - f[3] / 2), W * f[2], H * f[3], rgb(0.16, 0.01, 0.0, f[4]), blur)
    }
    drawRect(radial(listOf(rgb(1.0, 0.5, 0.15, 0.25), Color.Transparent), W * 0.5, H * 0.3, W * 0.8))
}
