package com.gogs.bananagame.games.cratepush

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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Brain — Crate Push (iOS CratePushGame.swift, id "crate-push"): a Sokoban. D-pad the banana and
 * shove every crate onto a green ✕ before the clock runs out; push only, so a crate wedged into a
 * corner fails the level at once. Boards are generated and verified by a push-based BFS (bitmasks).
 */
object CratePushGame {
    val definition = GameDefinition(
        id = "crate-push",
        title = "Crate Push",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Nudge the banana with the d-pad and shove every crate onto a green target mark.",
                "You can only push, never pull — a crate wedged into a corner is lost.",
                "Plan before you shove.",
                "Park every crate before the clock runs out, or wedge one hopelessly, and you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Đẩy quả chuối bằng d-pad và đưa mọi thùng lên dấu mục tiêu màu xanh.",
                "Bạn chỉ đẩy được, không kéo — một thùng kẹt vào góc là hỏng.",
                "Hãy tính trước khi đẩy.",
                "Đặt hết mọi thùng trước khi hết giờ, hoặc kẹt một thùng vô vọng, sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        prefetch = { level -> BoardCache.prefetch(key(level)) { CrateGen.makePuzzle(params(level)) } },
        content = { level, onWin, onFail -> CratePushView(level, onWin, onFail) }
    )

    fun key(level: Int) = BoardCache.key("crate-push", level)
    fun timeLimit(level: Int) = listOf(50.0, 55.0, 65.0, 75.0, 85.0, 85.0, 95.0)[min(level, 7) - 1]

    /** Interior (w,h), crate count, interior walls, minimum pushes an optimal solution must need. */
    fun params(level: Int) = listOf(
        CPParams(4, 3, 1, 1, 4), CPParams(4, 4, 2, 1, 7), CPParams(5, 4, 2, 2, 10), CPParams(5, 5, 3, 2, 13),
        CPParams(6, 5, 3, 3, 16), CPParams(6, 5, 4, 4, 20), CPParams(6, 6, 4, 5, 24),
    )[min(level, 7) - 1]
}

data class CPParams(val iw: Int, val ih: Int, val crates: Int, val walls: Int, val minPushes: Int)
data class CPCell(val r: Int, val c: Int)
class CPPuzzle(val rows: Int, val cols: Int, val walls: Set<CPCell>, val targets: Set<CPCell>, val crates: Set<CPCell>, val player: CPCell)

object CrateGen {
    /** Try many random rooms; deal the first needing ≥ minPushes, else the hardest solvable, else a hand-built board. */
    fun makePuzzle(p: CPParams): CPPuzzle {
        var best: CPPuzzle? = null; var bestPushes = -1
        repeat(160) {
            val cand = generate(p) ?: return@repeat
            val pushes = solvePushes(cand) ?: return@repeat
            if (pushes >= p.minPushes) return cand
            if (pushes > bestPushes) { bestPushes = pushes; best = cand }
        }
        return best ?: fallback()
    }

    private fun border(rows: Int, cols: Int): MutableSet<CPCell> {
        val walls = HashSet<CPCell>()
        for (r in 0 until rows) { walls.add(CPCell(r, 0)); walls.add(CPCell(r, cols - 1)) }
        for (c in 0 until cols) { walls.add(CPCell(0, c)); walls.add(CPCell(rows - 1, c)) }
        return walls
    }

    private fun generate(p: CPParams): CPPuzzle? {
        val rows = p.ih + 2; val cols = p.iw + 2
        val floor = ArrayList<CPCell>()
        for (r in 1..p.ih) for (c in 1..p.iw) floor.add(CPCell(r, c))
        floor.shuffle()
        var idx = 0
        fun take(n: Int): List<CPCell>? { if (idx + n > floor.size) return null; val out = floor.subList(idx, idx + n).toList(); idx += n; return out }
        val walls = border(rows, cols)
        walls.addAll(take(p.walls) ?: return null)
        val crates = (take(p.crates) ?: return null).toSet()
        val targets = (take(p.crates) ?: return null).toSet()
        val player = take(1)?.first() ?: return null
        if (crates == targets) return null
        return CPPuzzle(rows, cols, walls, targets, crates, player)
    }

    private val dirs = listOf(0 to -1, 0 to 1, -1 to 0, 1 to 0)

    /** Push-based BFS over (crate layout, player region) with cells as bits of a Long (≤ 8×8). */
    fun solvePushes(p: CPPuzzle): Int? {
        if (p.crates == p.targets) return 0
        val R = p.rows; val C = p.cols
        if (R * C > 64) return null
        fun bit(r: Int, c: Int) = 1L shl (r * C + c)
        fun mask(s: Set<CPCell>) = s.fold(0L) { acc, x -> acc or bit(x.r, x.c) }
        val walls = mask(p.walls); val targets = mask(p.targets)
        val full = if (R * C == 64) -1L else (1L shl (R * C)) - 1
        var notLeft = 0L; var notRight = 0L
        for (r in 0 until R) for (c in 0 until C) { if (c > 0) notLeft = notLeft or bit(r, c); if (c < C - 1) notRight = notRight or bit(r, c) }

        fun region(start: Long, crates: Long): Long {
            val free = full and (walls or crates).inv()
            var reg = start
            while (true) {
                val grown = reg or ((reg and notRight) shl 1) or ((reg and notLeft) ushr 1) or ((reg shl C) and full) or (reg ushr C)
                val next = (grown and free) or start
                if (next == reg) return reg
                reg = next
            }
        }

        val c0 = mask(p.crates)
        val startRegion = region(bit(p.player.r, p.player.c), c0)
        val seen = HashSet<Pair<Long, Int>>(); seen.add(c0 to startRegion.countTrailingZeroBits())
        val qc = ArrayList<Long>(); val qr = ArrayList<Long>(); val qd = ArrayList<Int>()
        qc.add(c0); qr.add(startRegion); qd.add(0)
        var head = 0; var expanded = 0
        while (head < qc.size) {
            val cs = qc[head]; val reg = qr[head]; val d = qd[head]; head++
            expanded++
            if (expanded > 150_000) return null
            var boxes = cs
            while (boxes != 0L) {
                val i = boxes.countTrailingZeroBits()
                boxes = boxes and (boxes - 1)
                val br = i / C; val bc = i % C
                for ((dr, dc) in dirs) {
                    val fr = br - dr; val fc = bc - dc
                    val tr = br + dr; val tc = bc + dc
                    if (fr !in 0 until R || fc !in 0 until C || tr !in 0 until R || tc !in 0 until C) continue
                    val from = bit(fr, fc); val to = bit(tr, tc)
                    if ((walls or cs) and from != 0L || reg and from == 0L) continue
                    if ((walls or cs) and to != 0L) continue
                    val ncs = (cs and bit(br, bc).inv()) or to
                    if (ncs == targets) return d + 1
                    val nreg = region(bit(br, bc), ncs)
                    if (!seen.add(ncs to nreg.countTrailingZeroBits())) continue
                    qc.add(ncs); qr.add(nreg); qd.add(d + 1)
                }
            }
        }
        return null
    }

    /** Enclosed 5×3 with one crate one push from a target — always solvable. */
    private fun fallback() = CPPuzzle(3, 5, border(3, 5), setOf(CPCell(1, 1)), setOf(CPCell(1, 2)), CPCell(1, 3))

    // Demo: a 4×3 room with one pillar and one crate that needs 4 pushes (move-optimal 12).
    val demoPuzzle: CPPuzzle get() = CPPuzzle(5, 6, border(5, 6).apply { add(CPCell(1, 2)) }, setOf(CPCell(3, 1)), setOf(CPCell(2, 2)), CPCell(2, 1))
    val demoMoves: List<Pair<Int, Int>> = "RDRRUULDRDLL".map { when (it) { 'U' -> 0 to -1; 'D' -> 0 to 1; 'L' -> -1 to 0; else -> 1 to 0 } }
}

@Composable
private fun CratePushView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val timeLimit = CratePushGame.timeLimit(level)
    val scope = rememberCoroutineScope()
    var playing by remember { mutableStateOf(true) }
    var ready by remember { mutableStateOf(false) }
    var rows by remember { mutableIntStateOf(0) }
    var cols by remember { mutableIntStateOf(0) }
    var walls by remember { mutableStateOf(setOf<CPCell>()) }
    var targets by remember { mutableStateOf(setOf<CPCell>()) }
    var crates by remember { mutableStateOf(setOf<CPCell>()) }
    var player by remember { mutableStateOf(CPCell(0, 0)) }
    var facing by remember { mutableIntStateOf(1) }
    var timeLeft by remember { mutableDoubleStateOf(timeLimit) }
    var demoKey by remember { mutableStateOf<Pair<Int, Int>?>(null) }
    val shake = remember { Animatable(1f) }

    fun shakeNow() { scope.launch { shake.snapTo(0f); shake.animateTo(1f, tween(350)) } }
    fun win() { if (!playing) return; playing = false; onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }
    fun commit(p: CPPuzzle) { rows = p.rows; cols = p.cols; walls = p.walls; targets = p.targets; crates = p.crates; player = p.player }

    /** A crate off-target jammed against walls on two perpendicular sides can never move again. */
    fun isDeadlocked() = crates.any { cr ->
        cr !in targets && (CPCell(cr.r - 1, cr.c) in walls || CPCell(cr.r + 1, cr.c) in walls) &&
            (CPCell(cr.r, cr.c - 1) in walls || CPCell(cr.r, cr.c + 1) in walls)
    }

    fun deadlock() {
        if (!playing) return
        playing = false
        SoundManager.error(); Haptics.warning(); shakeNow()
        scope.launch { delay(400); onFail() }
    }

    fun move(dc: Int, dr: Int) {
        if (!playing) return
        if (dc > 0) facing = 1 else if (dc < 0) facing = -1
        val dest = CPCell(player.r + dr, player.c + dc)
        if (dest in walls) return
        if (dest in crates) {
            val beyond = CPCell(dest.r + dr, dest.c + dc)
            if (beyond in walls || beyond in crates) return
            crates = crates - dest + beyond
            player = dest
            SoundManager.tap(); Haptics.tap()
            if (beyond in targets) shakeNow()
            if (crates == targets) win() else if (isDeadlocked()) deadlock()
        } else {
            player = dest
            SoundManager.tap()
        }
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (isActive) {
                commit(CrateGen.demoPuzzle); facing = 1; demoKey = null
                timeLeft = timeLimit; playing = true; ready = true
                delay(800)
                for (m in CrateGen.demoMoves) {
                    demoKey = m; move(m.first, m.second)
                    delay(160); demoKey = null; delay(160)
                }
                delay(1300)
            }
        } else {
            val t0 = System.currentTimeMillis()
            val p = BoardCache.take(CratePushGame.key(level)) { CrateGen.makePuzzle(CratePushGame.params(level)) }
            BoardCache.holdBrainstorm(t0, 0.7)
            commit(p); ready = true; timeLeft = timeLimit; playing = true
            val start = nowSec()
            while (isActive && playing) {
                delay(50)
                timeLeft = max(0.0, timeLimit - (nowSec() - start))
                if (timeLeft <= 0) { fail(); break }
            }
        }
    }

    if (!ready) {
        val i = min(level, 7) - 1
        val top = listOf(rgb(0.16, 0.15, 0.20), rgb(0.15, 0.14, 0.20), rgb(0.14, 0.13, 0.20), rgb(0.13, 0.12, 0.19),
            rgb(0.12, 0.10, 0.18), rgb(0.10, 0.08, 0.16), rgb(0.08, 0.06, 0.14))
        val bottom = listOf(rgb(0.10, 0.09, 0.14), rgb(0.09, 0.08, 0.13), rgb(0.09, 0.07, 0.13), rgb(0.08, 0.06, 0.12),
            rgb(0.07, 0.05, 0.11), rgb(0.06, 0.04, 0.10), rgb(0.05, 0.03, 0.09))
        BrainstormingView(top[i], bottom[i])
        return
    }

    val gap = if (isDemo) 4.dp else 8.dp
    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .background(Brush.verticalGradient(listOf(rgb(0.17, 0.15, 0.15), rgb(0.09, 0.08, 0.08)))),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(gap)
    ) {
        Row(Modifier.padding(top = if (isDemo) 6.dp else 0.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Canvas(Modifier.size(if (isDemo) 16.dp else 20.dp)) { crate(0.0, 0.0, size.width.toDouble(), false) }
            Text("${(crates - targets).size}", style = ts(if (isDemo) 15.0 else 20.0, FontWeight.Black, BananaTheme.banana).copy(fontFeatureSettings = "tnum"))
        }
        if (!isDemo) {
            val f = timeLeft / timeLimit
            TimeBar(f, Modifier.fillMaxWidth().padding(horizontal = 60.dp).height(5.dp), fill = if (f < 0.3) rgb(0.95, 0.3, 0.25) else BananaTheme.banana)
        }
        Canvas(Modifier.fillMaxWidth().weight(1f).graphicsLayer {
            val k = shake.value.toDouble()
            if (k < 1) translationX = (4 * density * sin(k * PI * 3) * (1 - k)).toFloat()
        }) {
            val w = size.width.toDouble(); val h = size.height.toDouble()
            val cell = if (cols > 0 && rows > 0) min(w / cols, h / rows) else 0.0
            if (cell <= 0) return@Canvas
            val ox = (w - cell * cols) / 2; val oy = (h - cell * rows) / 2
            for (r in 0 until rows) for (c in 0 until cols) {
                val x = ox + c * cell; val y = oy + r * cell
                if (CPCell(r, c) in walls) bricks(x, y, cell, ox, oy)
                else floorTile(x, y, cell, CPCell(r - 1, c) in walls)
            }
            for (t in targets) target(ox + t.c * cell, oy + t.r * cell, cell)
            for (cr in crates) crate(ox + cr.c * cell, oy + cr.r * cell, cell, cr in targets)
            keeper(ox + (player.c + 0.5) * cell, oy + (player.r + 0.5) * cell, cell, facing)
        }
        Column(Modifier.padding(bottom = if (isDemo) 6.dp else 8.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(gap)) {
            ArrowKey(0, -1, isDemo, demoKey) { move(0, -1) }
            Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
                ArrowKey(-1, 0, isDemo, demoKey) { move(-1, 0) }
                ArrowKey(0, 1, isDemo, demoKey) { move(0, 1) }
                ArrowKey(1, 0, isDemo, demoKey) { move(1, 0) }
            }
        }
    }
}

/** A chunky steel d-pad key; banana-lit while the demo presses it. */
@Composable
private fun ArrowKey(dc: Int, dr: Int, isDemo: Boolean, demoKey: Pair<Int, Int>?, onPress: () -> Unit) {
    var held by remember { mutableStateOf(false) }
    val pressed = (isDemo && demoKey == (dc to dr)) || held
    val sc by animateFloatAsState(if (pressed) 0.9f else 1f, tween(100), label = "k")
    val icon: ImageVector = when {
        dr < 0 -> Icons.Filled.KeyboardArrowUp; dr > 0 -> Icons.Filled.KeyboardArrowDown
        dc < 0 -> Icons.Filled.KeyboardArrowLeft; else -> Icons.Filled.KeyboardArrowRight
    }
    val shape = RoundedCornerShape(12.dp)
    Box(
        Modifier.scale(sc).size(if (isDemo) 50.dp else 66.dp, if (isDemo) 34.dp else 52.dp)
            .background(if (pressed) Brush.verticalGradient(listOf(BananaTheme.banana, BananaTheme.banana)) else Brush.verticalGradient(listOf(gray(0.42), gray(0.24))), shape)
            .border(2.dp, Color.Black.op(0.55), shape)
            .padding(2.dp).border(1.dp, Color.White.op(if (pressed) 0.9 else 0.22), RoundedCornerShape(10.dp))
            .then(if (isDemo) Modifier else Modifier.pressDown(onDown = { held = true; onPress() }, onUp = { held = false })),
        contentAlignment = Alignment.Center
    ) { Icon(icon, null, tint = if (pressed) Color.Black else Color.White, modifier = Modifier.size(if (isDemo) 22.dp else 28.dp)) }
}

// Warehouse art (classic Sokoban; iOS CPArt).

/** Orange bricks in running bond, aligned to the whole room so neighbouring walls join up. */
private fun DrawScope.bricks(x: Double, y0: Double, cell: Double, originX: Double, originY: Double) {
    rect(x, y0, cell, cell, rgb(0.8, 0.38, 0.2))
    clipRect(x.f, y0.f, (x + cell).f, (y0 + cell).f) {
        val course = cell / 3; val brick = cell / 2
        val mortar = Path(); val light = Path()
        var y = originY + floor((y0 - originY) / course) * course
        while (y < y0 + cell) {
            val k = ((y - originY) / course).roundToInt()
            mortar.m(x, y); mortar.l(x + cell, y)
            light.m(x, y + 1.5 * density); light.l(x + cell, y + 1.5 * density)
            var bx = originX + (if (k % 2 == 0) 0.0 else brick / 2) - brick
            while (bx < x + cell) {
                if (bx > x - 1) { mortar.m(bx, y); mortar.l(bx, y + course) }
                bx += brick
            }
            y += course
        }
        strokePath(light, rgb(0.96, 0.6, 0.4, 0.6), density.toDouble(), androidx.compose.ui.graphics.StrokeCap.Butt)
        strokePath(mortar, rgb(0.42, 0.2, 0.12), max(density.toDouble(), cell * 0.035), androidx.compose.ui.graphics.StrokeCap.Butt)
    }
}

/** Floorboards; a strip of shade under any wall above. */
private fun DrawScope.floorTile(x: Double, y: Double, cell: Double, wallAbove: Boolean) {
    rect(x, y, cell, cell, rgb(0.56, 0.39, 0.23))
    val board = cell / 4
    val seams = Path()
    for (i in 0 until 4) {
        val sy = y + i * board
        seams.m(x, sy); seams.l(x + cell, sy)
        val jx = x + cell * (if (i % 2 == 0) 0.3 else 0.75)
        seams.m(jx, sy); seams.l(jx, sy + board)
    }
    strokePath(seams, rgb(0.36, 0.24, 0.13), max(0.8 * density, cell * 0.02), androidx.compose.ui.graphics.StrokeCap.Butt)
    if (wallAbove) rect(x, y, cell, cell * 0.22, vgrad(listOf(Color.Black.op(0.35), Color.Transparent), y, y + cell * 0.22))
}

/** A painted green ✕ on the boards. */
private fun DrawScope.target(x: Double, y: Double, w: Double) {
    val s = w * 0.22; val mx = x + w / 2; val my = y + w / 2
    val p = Path(); p.m(mx - s, my - s); p.l(mx + s, my + s); p.m(mx + s, my - s); p.l(mx - s, my + s)
    strokePath(p, rgb(0.1, 0.24, 0.08, 0.6), w * 0.16)
    strokePath(p, rgb(0.36, 0.86, 0.3), w * 0.1)
}

/** An X-braced wooden crate; a parked one gets a green-lit frame. */
private fun DrawScope.crate(cx: Double, cy: Double, cw: Double, parked: Boolean) {
    val x = cx + cw * 0.06; val y = cy + cw * 0.06; val s = cw * 0.88
    val frameCol = if (parked) rgb(0.34, 0.72, 0.3) else rgb(0.6, 0.4, 0.2)
    if (parked) {
        val k = (0.4 / 0.62).toFloat()
        rrect(x - s * 0.08, y - s * 0.08, s * 1.16, s * 1.16, s * 0.14,
            Brush.radialGradient(0f to Color.Transparent, k to rgb(0.4, 1.0, 0.4, 0.5), 1f to Color.Transparent, center = Offset((x + s / 2).f, (y + s / 2).f), radius = (s * 0.62).f))
    }
    rrect(x, y, s, s, s * 0.07, frameCol)
    val ix = x + s * 0.14; val iy = y + s * 0.14; val iw = s * 0.72
    rect(ix, iy, iw, iw, lin(listOf(rgb(0.92, 0.72, 0.44), rgb(0.8, 0.58, 0.32)), ix, iy, ix + iw, iy + iw))
    clipRect(ix.f, iy.f, (ix + iw).f, (iy + iw).f) {
        val brace = Path(); brace.m(ix, iy); brace.l(ix + iw, iy + iw); brace.m(ix + iw, iy); brace.l(ix, iy + iw)
        strokePath(brace, frameCol, s * 0.13, androidx.compose.ui.graphics.StrokeCap.Butt)
    }
    for ((nx, ny) in listOf(x to y, x + s to y, x to y + s, x + s to y + s)) {
        circle(nx + (if (nx < x + s / 2) s * 0.07 else -s * 0.07), ny + (if (ny < y + s / 2) s * 0.07 else -s * 0.07), s * 0.025, rgb(0.25, 0.18, 0.12))
    }
    rrectStroke(x, y, s, s, s * 0.07, rgb(0.24, 0.14, 0.07), max(density.toDouble(), s * 0.04))
}

/** The warehouse keeper: an upright banana in a blue cap, facing where it last walked. */
private fun DrawScope.keeper(cx: Double, cy: Double, cell: Double, facing: Int) {
    val s = cell * 0.98
    val ink = rgb(0.12, 0.09, 0.05)
    translate(cx.f, cy.f) {
        scale((if (facing < 0) -s else s).f, s.f, Offset.Zero) {
            oval(-0.3, 0.38, 0.6, 0.12, Color.Black.op(0.25))
            val body = Path(); body.m(-0.02, -0.4); body.c(-0.46, -0.2, -0.4, 0.36, 0.08, 0.44); body.c(0.12, 0.2, 0.2, -0.18, -0.02, -0.4); body.close()
            drawPath(body, hgrad(listOf(rgb(0.95, 0.72, 0.14), rgb(1.0, 0.92, 0.4)), -0.35, 0.1))
            strokePath(body, ink, 0.04)
            val cap = Path(); cap.m(-0.2, -0.3); cap.q(-0.04, -0.56, 0.14, -0.32); cap.close()
            fillPath(cap, rgb(0.2, 0.42, 0.86))
            rrect(0.06, -0.34, 0.24, 0.06, 0.03, rgb(0.14, 0.3, 0.66))
            strokePath(cap, ink, 0.035)
            oval(-0.07, -0.2, 0.15, 0.16, Color.White)
            drawOval(ink, Offset((-0.07).f, (-0.2).f), androidx.compose.ui.geometry.Size(0.15f, 0.16f), style = androidx.compose.ui.graphics.drawscope.Stroke(0.025f))
            oval(0.01, -0.15, 0.06, 0.08, ink)
            val smile = Path(); smile.m(-0.06, 0.02); smile.q(0.02, 0.09, 0.07, 0.0)
            strokePath(smile, ink, 0.03)
        }
    }
}
