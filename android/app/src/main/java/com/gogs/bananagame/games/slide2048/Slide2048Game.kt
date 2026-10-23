package com.gogs.bananagame.games.slide2048

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/** Brain — Slide (iOS Slide2048Game.swift): a pint-sized 2048 in Cirulli's palette. */
object Slide2048Game {
    val definition = GameDefinition(
        id = "slide-2048",
        title = "Slide",
        genre = Genre.BRAIN,
        locksFeed = true,
        manual = GameManual(
            bullets = listOf(
                "Swipe to slide every tile; matching numbers merge into double.",
                "Reach the target tile to win the level.",
                "A full board with no moves — or the clock running out — drops you to level 1.",
            ),
            bulletsVI = listOf(
                "Vuốt để trượt mọi ô; hai số giống nhau gộp thành gấp đôi.",
                "Đạt tới ô mục tiêu để qua cấp.",
                "Bàn đầy không còn nước đi — hoặc hết giờ — sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> Slide2048View(level, onWin, onFail) }
    )

    enum class Dir { UP, DOWN, LEFT, RIGHT }

    /** Compacts a line toward the start and merges equal neighbours once each. */
    fun collapse(line: List<Int>): List<Int> {
        val tiles = line.filter { it != 0 }
        val merged = ArrayList<Int>()
        var i = 0
        while (i < tiles.size) {
            if (i + 1 < tiles.size && tiles[i] == tiles[i + 1]) { merged.add(tiles[i] * 2); i += 2 } else { merged.add(tiles[i]); i += 1 }
        }
        while (merged.size < line.size) merged.add(0)
        return merged
    }

    fun transpose(g: List<List<Int>>): List<List<Int>> = List(g.size) { c -> List(g.size) { r -> g[r][c] } }

    fun apply(grid: List<List<Int>>, dir: Dir): List<List<Int>> = when (dir) {
        Dir.LEFT -> grid.map { collapse(it) }
        Dir.RIGHT -> grid.map { collapse(it.reversed()).reversed() }
        Dir.UP -> transpose(transpose(grid).map { collapse(it) })
        Dir.DOWN -> transpose(transpose(grid).map { collapse(it.reversed()).reversed() })
    }

    fun hasMoves(g: List<List<Int>>): Boolean {
        val n = g.size
        for (r in 0 until n) for (c in 0 until n) {
            if (g[r][c] == 0) return true
            if (c + 1 < n && g[r][c] == g[r][c + 1]) return true
            if (r + 1 < n && g[r][c] == g[r + 1][c]) return true
        }
        return false
    }
}

private object SlideArt {
    val page = rgb(0.98, 0.973, 0.937)
    val board = rgb(0.733, 0.678, 0.627)
    val slot = rgb(0.804, 0.757, 0.706)
    val ink = rgb(0.467, 0.431, 0.396)
    val light = rgb(0.976, 0.965, 0.949)
    fun color(v: Int) = when (v) {
        2 -> rgb(0.933, 0.894, 0.855); 4 -> rgb(0.929, 0.878, 0.784); 8 -> rgb(0.949, 0.694, 0.475)
        16 -> rgb(0.961, 0.584, 0.388); 32 -> rgb(0.965, 0.486, 0.373); 64 -> rgb(0.965, 0.369, 0.231)
        128 -> rgb(0.929, 0.812, 0.447); 256 -> rgb(0.929, 0.8, 0.38); 512 -> rgb(0.929, 0.784, 0.314)
        1024 -> rgb(0.929, 0.773, 0.247); 2048 -> rgb(0.929, 0.761, 0.18)
        else -> rgb(0.235, 0.227, 0.196)
    }
}

/** One tile as a moving piece: slides from (fr, fc) to (r, c); merged tiles pop, new ones zoom in. */
private class Tile(val value: Int, val fr: Int, val fc: Int, val r: Int, val c: Int, val kind: Int, val t0: Double)  // kind 0 slide, 1 born, 2 merged

@Composable
private fun Slide2048View(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val side = if (level <= 4) 4 else 3
    val target = listOf(0, 16, 32, 64, 128, 128, 256, 512)[min(level, 7)]
    val timeLimit = max(8.0, 26 - level * 2.5)
    var grid by remember { mutableStateOf(List(side) { List(side) { 0 } }) }
    var timeLeft by remember { mutableDoubleStateOf(timeLimit) }
    var done by remember { mutableStateOf(false) }
    var tiles by remember { mutableStateOf(listOf<Tile>()) }
    var lastMove by remember { mutableDoubleStateOf(-10.0) }
    var demoFinger by remember { mutableStateOf<P?>(null) }
    val tm = rememberTextMeasurer()
    val handP = rememberHand()
    val bestTile = grid.flatten().maxOrNull() ?: 0

    fun spawn(g: List<List<Int>>): List<List<Int>> {
        val empties = ArrayList<Pair<Int, Int>>()
        for (r in g.indices) for (c in g.indices) if (g[r][c] == 0) empties.add(r to c)
        if (empties.isEmpty()) return g
        val (r, c) = empties.pick()
        return g.mapIndexed { rr, row -> row.mapIndexed { cc, v -> if (rr == r && cc == c) (if (rndInt(0..9) == 0) 4 else 2) else v } }
    }

    fun rebuild() {
        val now = nowSec()
        tiles = grid.flatMapIndexed { r, row -> row.mapIndexedNotNull { c, v -> if (v != 0) Tile(v, r, c, r, c, 0, now - 1) else null } }
    }

    /** Replays a move for the eye: slides, merge pops and the newly spawned tile zooming in. */
    fun animateMove(before: List<List<Int>>, after: List<List<Int>>, dir: Slide2048Game.Dir) {
        val n = before.size
        val now = nowSec()
        val out = ArrayList<Tile>()
        val covered = HashSet<Int>()
        for (line in 0 until n) {
            val cells = (0 until n).map { k ->
                when (dir) {
                    Slide2048Game.Dir.LEFT -> line to k
                    Slide2048Game.Dir.RIGHT -> line to n - 1 - k
                    Slide2048Game.Dir.UP -> k to line
                    Slide2048Game.Dir.DOWN -> n - 1 - k to line
                }
            }
            val run = cells.filter { before[it.first][it.second] != 0 }
            var i = 0; var slot = 0
            while (i < run.size) {
                val dest = cells[slot]
                val v = before[run[i].first][run[i].second]
                if (i + 1 < run.size && v == before[run[i + 1].first][run[i + 1].second]) {
                    for (k in 0..1) out.add(Tile(v, run[i + k].first, run[i + k].second, dest.first, dest.second, 0, now))
                    out.add(Tile(v * 2, dest.first, dest.second, dest.first, dest.second, 2, now + 0.1))
                    i += 2
                } else {
                    out.add(Tile(v, run[i].first, run[i].second, dest.first, dest.second, 0, now))
                    i += 1
                }
                covered.add(dest.first * n + dest.second)
                slot++
            }
        }
        for (r in 0 until n) for (c in 0 until n) if (after[r][c] != 0 && (r * n + c) !in covered) out.add(Tile(after[r][c], r, c, r, c, 1, now + 0.1))
        tiles = out
        lastMove = now
    }

    fun handleSwipe(dx: Double, dy: Double) {
        if (done) return
        val dir = if (abs(dx) > abs(dy)) (if (dx > 0) Slide2048Game.Dir.RIGHT else Slide2048Game.Dir.LEFT)
        else (if (dy > 0) Slide2048Game.Dir.DOWN else Slide2048Game.Dir.UP)
        val before = grid
        val moved = Slide2048Game.apply(grid, dir)
        if (moved == before) return
        Haptics.tap(); SoundManager.tap()
        grid = spawn(moved)
        animateMove(before, grid, dir)
        if ((grid.flatten().maxOrNull() ?: 0) >= target) { done = true; onWin() }
        else if (!Slide2048Game.hasMoves(grid)) { done = true; Haptics.warning(); SoundManager.error(); onFail() }
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            val swipes = listOf(Slide2048Game.Dir.LEFT to P(-1.0, 0.0), Slide2048Game.Dir.UP to P(0.0, -1.0), Slide2048Game.Dir.UP to P(0.0, -1.0))
            while (isActive) {
                done = false
                grid = listOf(listOf(2, 2, 0, 0), listOf(2, 2, 0, 0), listOf(8, 0, 0, 0), listOf(0, 0, 0, 0))
                rebuild(); timeLeft = timeLimit; demoFinger = null
                delay(800)
                for ((dir, v) in swipes) {
                    demoFinger = P(-v.x * 0.28, -v.y * 0.28)
                    delay(200)
                    val steps = 12
                    for (k in 1..steps) {
                        val t = k.toDouble() / steps
                        val e = 1 - (1 - t) * (1 - t)
                        demoFinger = P(-v.x * 0.28 + v.x * 0.56 * e, -v.y * 0.28 + v.y * 0.56 * e)
                        delay(17)
                    }
                    val before = grid
                    grid = Slide2048Game.apply(grid, dir)
                    animateMove(before, grid, dir)
                    delay(150)
                    demoFinger = null
                    delay(550)
                }
                delay(1100)
            }
        } else {
            var g = List(side) { List(side) { 0 } }
            g = spawn(spawn(g))
            grid = g
            rebuild()
            timeLeft = timeLimit
            val start = nowSec()
            while (isActive && !done) {
                delay(50)
                timeLeft = max(0.0, timeLimit - (nowSec() - start))
                if (timeLeft <= 0 && !done) { done = true; Haptics.warning(); SoundManager.error(); onFail() }
            }
        }
    }

    val animTick by rememberFrameLoop(running = true)
    val swipeMin = with(LocalDensity.current) { 24.dp.toPx() }.toDouble()
    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .background(SlideArt.page)
            .touchDrag(onEnd = { s, e -> if (!isDemo && (e - s).len >= swipeMin) handleSwipe(e.x - s.x, e.y - s.y) })
            .padding(horizontal = if (isDemo) 12.dp else 18.dp, vertical = if (isDemo) 10.dp else 18.dp),
        verticalArrangement = Arrangement.spacedBy(if (isDemo) 8.dp else 14.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Column {
                Text(L("GOAL", "MỤC TIÊU"), style = ts(if (isDemo) 11.0 else 13.0, FontWeight.ExtraBold, SlideArt.ink.op(0.75), spacing = 1.5))
                Text("$target", style = ts(if (isDemo) 38.0 else 56.0, FontWeight.ExtraBold, SlideArt.ink))
            }
            Spacer(Modifier.weight(1f))
            Column(
                Modifier.widthIn(min = if (isDemo) 64.dp else 84.dp).background(SlideArt.board, RoundedCornerShape(5.dp))
                    .padding(vertical = if (isDemo) 4.dp else 7.dp, horizontal = 10.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(L("BEST", "CAO NHẤT"), style = ts(if (isDemo) 10.0 else 12.0, FontWeight.ExtraBold, rgb(0.93, 0.89, 0.85), spacing = 1.0))
                Text("$bestTile", style = ts(if (isDemo) 20.0 else 26.0, FontWeight.ExtraBold, Color.White))
            }
        }
        if (!isDemo) TimeBar(timeLeft / timeLimit, Modifier.fillMaxWidth().padding(horizontal = 30.dp).height(8.dp),
            fill = if (timeLeft / timeLimit < 0.3) rgb(0.9, 0.25, 0.2) else SlideArt.color(16), track = SlideArt.slot)
        BoxWithConstraints(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
            val s = min(maxWidth.value, maxHeight.value)
            Canvas(Modifier.size(s.dp)) {
                animTick
                drawBoard(tm, side, tiles)
                demoFinger?.let { f ->
                    val sz = size.width.toDouble()
                    val gap = sz / (side * 7.2 + 1); val cell = (sz - gap * (side + 1)) / side
                    hand(handP, sz / 2 + f.x * sz - cell * 0.15, sz / 2 + f.y * sz - cell * 0.1, cell * 0.55)
                }
            }
        }
    }
}

private fun DrawScope.drawBoard(tm: TextMeasurer, n: Int, tiles: List<Tile>) {
    val s = size.width.toDouble()
    rrect(0.0, 0.0, s, s, s * 0.02, SlideArt.board)
    val gap = s / (n * 7.2 + 1)
    val cell = (s - gap * (n + 1)) / n
    fun cx(c: Double) = gap + (cell + gap) * c + cell / 2
    for (r in 0 until n) for (c in 0 until n) rrect(gap + (cell + gap) * c, gap + (cell + gap) * r, cell, cell, cell * 0.06, SlideArt.slot)
    val now = nowSec()
    // Slides first, then born/merged tiles on top.
    for (pass in 0..1) for (t in tiles) {
        if ((pass == 0) != (t.kind == 0)) continue
        val e = now - t.t0
        when (t.kind) {
            0 -> {
                // A sliding tile under a merge disappears once the merged tile appears.
                val k = (e / 0.1).coerceIn(0.0, 1.0)
                val ease = if (k < 0.5) 2 * k * k else 1 - (-2 * k + 2).pow(2) / 2
                val merging = tiles.any { it.kind == 2 && it.r == t.r && it.c == t.c }
                if (merging && e >= 0.1) continue
                val x = cx(t.fc + (t.c - t.fc) * ease); val y = cx(t.fr + (t.r - t.fr) * ease)
                tile(tm, t.value, x, y, cell, 1.0, 1.0)
            }
            else -> {
                if (e < 0) continue
                val k = (e / 0.2).coerceIn(0.0, 1.0)
                // Springy settle: merged pops from 1.22, born zooms from 0.1.
                val from = if (t.kind == 2) 1.22 else 0.1
                val spring = 1 - (1 - k) * (1 - k) * (1 + 2.2 * k)
                val sc = from + (1 - from) * spring.coerceIn(0.0, 1.15)
                tile(tm, t.value, cx(t.c.toDouble()), cx(t.r.toDouble()), cell, sc, if (t.kind == 1) min(1.0, k * 2) else 1.0)
            }
        }
    }
}

private fun DrawScope.tile(tm: TextMeasurer, value: Int, x: Double, y: Double, size: Double, scale: Double, alpha: Double) {
    val s = size * scale
    withAlpha(alpha) {
        if (value >= 128) blurRRect(x - s / 2, y - s / 2, s, s, s * 0.06, rgb(0.95, 0.8, 0.3, 0.55), size * 0.12)
        rrect(x - s / 2, y - s / 2, s, s, s * 0.06, SlideArt.color(value))
        val digits = value.toString().length
        val fs = s * (if (digits <= 2) 0.5 else if (digits == 3) 0.42 else 0.33)
        text(tm, "$value", x, y, fs, if (value <= 4) SlideArt.ink else SlideArt.light, FontWeight.ExtraBold)
    }
}
