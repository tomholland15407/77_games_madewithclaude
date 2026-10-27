package com.gogs.bananagame.games.colortide

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/** Brain — Color Tide (was "Flood It"; iOS FloodItGame.swift): flood the board one colour within the budget. */
object ColorTideGame {
    val definition = GameDefinition(
        id = "flood-it",
        title = "Color Tide",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Your flood starts at the top-left cell.",
                "Tap a colour to repaint your whole flood, absorbing touching cells that match.",
                "Fill the entire board with one colour before your moves (or the clock) run out.",
            ),
            bulletsVI = listOf(
                "Vùng loang của bạn bắt đầu ở ô trên cùng bên trái.",
                "Chạm một màu để tô lại toàn bộ vùng loang, hút các ô liền kề cùng màu.",
                "Lấp cả bàn bằng một màu duy nhất trước khi hết lượt (hoặc hết giờ).",
            ),
            liveDemo = true
        ),
        prefetch = { level -> BoardCache.prefetch(key(level)) { FloodCore.build(n(level), colors(level)) } },
        content = { level, onWin, onFail -> ColorTideView(level, onWin, onFail) }
    )

    fun key(level: Int) = BoardCache.key("flood-it", level)
    fun n(level: Int) = listOf(5, 6, 6, 7, 7, 8, 8)[min(level, 7) - 1]
    fun colors(level: Int) = listOf(4, 4, 5, 5, 6, 6, 6)[min(level, 7) - 1]
    fun slack(level: Int) = listOf(3, 3, 2, 2, 1, 1, 0)[min(level, 7) - 1]
    fun timeLimit(level: Int) = listOf(45.0, 50.0, 55.0, 60.0, 60.0, 55.0, 50.0)[min(level, 7) - 1]
}

object FloodCore {
    fun region0(g: IntArray, n: Int): List<Int> {
        val target = g[0]
        val seen = BooleanArray(g.size); seen[0] = true
        val stack = arrayListOf(0); val out = ArrayList<Int>()
        while (stack.isNotEmpty()) {
            val cur = stack.removeAt(stack.size - 1); out.add(cur)
            val r = cur / n; val c = cur % n
            for ((nr, nc) in listOf(r - 1 to c, r + 1 to c, r to c - 1, r to c + 1)) {
                if (nr !in 0 until n || nc !in 0 until n) continue
                val ni = nr * n + nc
                if (!seen[ni] && g[ni] == target) { seen[ni] = true; stack.add(ni) }
            }
        }
        return out
    }

    fun isMono(g: IntArray) = g.all { it == g[0] }

    fun greedyMoves(start: IntArray, n: Int, colors: Int): Int {
        val g = start.copyOf()
        var moves = 0; var guard = 0
        while (!isMono(g)) {
            if (++guard > n * n * colors + 50) break
            val region = region0(g, n)
            val cur = g[0]
            var bestX = cur; var bestGain = -1
            for (x in (0 until colors).shuffled()) {
                if (x == cur) continue
                val gg = g.copyOf(); for (i in region) gg[i] = x
                val sz = region0(gg, n).size
                if (sz > bestGain) { bestGain = sz; bestX = x }
            }
            for (i in region) g[i] = bestX
            moves++
        }
        return moves
    }

    fun makeBoard(n: Int, colors: Int): IntArray {
        var g = IntArray(n * n) { rndInt(0 until colors) }
        var tries = 0
        while (isMono(g) && tries < 8) { g = IntArray(n * n) { rndInt(0 until colors) }; tries++ }
        return g
    }

    /** The board plus its greedy-solver baseline (budget = baseline + slack). */
    fun build(n: Int, colors: Int): Pair<IntArray, Int> {
        val g = makeBoard(n, colors)
        var best = Int.MAX_VALUE
        repeat(24) { best = min(best, greedyMoves(g, n, colors)) }
        return g to (if (best == Int.MAX_VALUE) n * n else best)
    }
}

private val PALETTE = listOf(rgb(0.984, 0.894, 0.200), rgb(0.122, 0.439, 0.965), rgb(0.957, 0.349, 0.490), rgb(0.227, 0.855, 0.173), rgb(0.573, 0.365, 0.749), rgb(0.945, 0.522, 0.098))
private val DEMO_BOARD = intArrayOf(0, 3, 1, 2, 0, 1, 3, 0, 3, 2, 1, 3, 0, 1, 3, 2, 1, 2, 2, 3, 3, 0, 0, 1, 2)
private val DEMO_MOVES = listOf(3, 1, 0, 1, 3, 2, 0)
private const val POP = 0.14

private class Ripple(val from: IntArray, val ring: Map<Int, Int>, val step: Double, val t0: Double)

@Composable
private fun ColorTideView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val timeLimit = ColorTideGame.timeLimit(level)
    val slack = ColorTideGame.slack(level)
    var playing by remember { mutableStateOf(true) }
    var ready by remember { mutableStateOf(false) }
    var boardN by remember { mutableIntStateOf(0) }
    var colors by remember { mutableIntStateOf(0) }
    var grid by remember { mutableStateOf(IntArray(0)) }
    var budget by remember { mutableIntStateOf(0) }
    var moves by remember { mutableIntStateOf(0) }
    var timeLeft by remember { mutableDoubleStateOf(timeLimit) }
    var demoPress by remember { mutableStateOf<Int?>(null) }
    var ripple by remember { mutableStateOf<Ripple?>(null) }

    fun win() { if (!playing) return; playing = false; onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }

    fun play(x: Int) {
        if (!playing || grid.isEmpty() || grid[0] == x) return
        val before = grid
        val region = FloodCore.region0(grid, boardN)
        grid = grid.copyOf().also { g -> for (i in region) g[i] = x }
        val n = boardN
        val inRegion = region.toHashSet()
        val ring = HashMap<Int, Int>(); ring[0] = 0
        val q = ArrayDeque<Int>(); q.add(0)
        while (q.isNotEmpty()) {
            val cur = q.removeFirst()
            val r = cur / n; val c = cur % n
            for ((nr, nc) in listOf(r - 1 to c, r + 1 to c, r to c - 1, r to c + 1)) {
                if (nr !in 0 until n || nc !in 0 until n) continue
                val ni = nr * n + nc
                if (ni in inRegion && ni !in ring) { ring[ni] = ring[cur]!! + 1; q.add(ni) }
            }
        }
        val deepest = ring.values.maxOrNull() ?: 0
        ripple = Ripple(before, ring, min(0.035, 0.4 / max(1, deepest)), nowSec())
        moves++
        SoundManager.tap(); Haptics.tap()
        if (FloodCore.isMono(grid)) { win(); return }
        if (moves >= budget) fail()
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (isActive) {
                boardN = 5; colors = 4; grid = DEMO_BOARD.copyOf(); budget = 7 + slack; moves = 0
                demoPress = null; ripple = null; timeLeft = timeLimit; playing = true; ready = true
                delay(600)
                for (x in DEMO_MOVES) { demoPress = x; delay(300); play(x); delay(150); demoPress = null; delay(300) }
                delay(1300)
            }
        } else {
            val n = ColorTideGame.n(level); val cc = ColorTideGame.colors(level)
            val (board, base) = BoardCache.take(ColorTideGame.key(level)) { FloodCore.build(n, cc) }
            boardN = n; colors = cc; grid = board; budget = base + slack; moves = 0
            ready = true; playing = true; timeLeft = timeLimit
            val start = nowSec()
            while (isActive && playing) {
                delay(50)
                timeLeft = max(0.0, timeLimit - (nowSec() - start))
                if (timeLeft <= 0) { fail(); break }
            }
        }
    }

    val tick by rememberFrameLoop(running = ripple != null)
    Box(Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp)).background(Color.Black)) {
        if (!ready) return@Box
        BoxWithConstraints(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            val gap = if (isDemo) 9f else 16f
            val headH = if (isDemo) 20f else 28f
            val barH = if (isDemo) 0f else 4f
            val btn = if (isDemo) 38f else 50f
            val rows = if (isDemo) 3 else 4
            val side = max(40f, min(maxWidth.value - (if (isDemo) 24 else 36), maxHeight.value - headH - barH - btn - gap * rows - (if (isDemo) 12 else 24)))
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(gap.dp)) {
                Box(Modifier.width(side.dp).height(headH.dp), contentAlignment = Alignment.CenterStart) {
                    Text(L("Step $moves / $budget", "Bước $moves / $budget"), style = ts(if (isDemo) 16.0 else 22.0, FontWeight.Bold))
                }
                if (!isDemo) TimeBar(timeLeft / timeLimit, Modifier.width(side.dp).height(barH.dp).clip(RoundedCornerShape(0)),
                    fill = if (timeLeft / timeLimit < 0.3) PALETTE[2] else Color.White, track = gray(0.16))
                Canvas(Modifier.size(side.dp)) {
                    tick
                    val n = boardN
                    if (n == 0 || grid.size != n * n) return@Canvas
                    val cell = size.width.toDouble() / n
                    val now = nowSec()
                    val a = ripple?.takeIf { it.from.size == n * n }
                    for (i in 0 until n * n) {
                        val x = (i % n) * cell - 0.4; val y = (i / n) * cell - 0.4; val s = cell + 0.8
                        val ring = a?.ring?.get(i)
                        if (a != null && ring != null) {
                            val t = (now - a.t0 - ring * a.step) / POP
                            if (t < 1) {
                                rect(x, y, s, s, PALETTE[a.from[i]])
                                if (t <= 0) continue
                                val p = 1 - (1 - t).pow(2)
                                val k = cell * 0.5 * (1 - p)
                                if (k < 1) rect(x, y, s, s, PALETTE[grid[i]]) else rrect(x + k, y + k, s - 2 * k, s - 2 * k, k * 0.6, PALETTE[grid[i]])
                                continue
                            }
                        }
                        rect(x, y, s, s, PALETTE[grid[i]])
                    }
                    if (a != null && now - a.t0 > (a.ring.values.maxOrNull() ?: 0) * a.step + POP + 0.05) ripple = null
                }
                Row(Modifier.width((side + if (isDemo) 16 else 20).dp).height(btn.dp), verticalAlignment = Alignment.CenterVertically) {
                    for (x in 0 until colors) {
                        val (src, pressed) = rememberPressed()
                        val sc by animateFloatAsState(if (demoPress == x) 0.84f else if (pressed.value) 0.88f else 1f, tween(100), label = "b")
                        Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                            Box(
                                Modifier.size(btn.dp).scale(sc).background(PALETTE[x], CircleShape)
                                    .then(if (demoPress == x) Modifier.border(3.5.dp, Color.White, CircleShape) else Modifier)
                                    .clickable(src, null, enabled = !isDemo && playing && grid.firstOrNull() != x) { play(x) }
                            )
                        }
                    }
                }
            }
        }
    }
}
