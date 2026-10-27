package com.gogs.bananagame.games.statuemaze

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropUp
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Brain — Statue Maze (was "Lolo"; iOS LoloGame.swift). An Adventures-of-Lolo room: collect every
 * heart, reach the door, never step into a statue's gaze; push blocks to break lines of sight.
 * Rooms are seeded then hill-climbed against a bitmask push-run solver.
 */
object StatueMazeGame {
    val definition = GameDefinition(
        id = "lolo",
        title = "Statue Maze",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Move the banana with the d-pad; collect every heart, then reach the door.",
                "Statues petrify their straight line of sight — red tiles are instant death.",
                "Push blocks (never pull) to break a statue's gaze and open a safe route.",
                "A gaze or the clock running out sends you back to level 1.",
            ),
            bulletsVI = listOf(
                "Di chuyển quả chuối bằng d-pad; nhặt hết trái tim rồi đến cửa.",
                "Tượng đá hóa đá theo đường nhìn thẳng — ô đỏ là chết ngay.",
                "Đẩy khối (chỉ đẩy, không kéo) để chặn tầm nhìn của tượng và mở lối an toàn.",
                "Bị tầm nhìn quét trúng hoặc hết giờ sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        prefetch = { level -> val p = params(level); BoardCache.prefetch(key(level)) { StatueSolver.makePuzzle(p) } },
        content = { level, onWin, onFail -> StatueMazeView(level, onWin, onFail) }
    )

    fun key(level: Int) = BoardCache.key("lolo", level)
    fun params(level: Int) = listOf(
        LoloParams(6, 4, 2, 1, 2, 1, 2, 1, 300),
        LoloParams(6, 5, 2, 2, 2, 1, 3, 2, 300),
        LoloParams(7, 5, 3, 2, 3, 2, 4, 2, 300),
        LoloParams(7, 6, 3, 2, 3, 2, 5, 2, 300),
        LoloParams(7, 6, 3, 3, 3, 3, 6, 3, 300),
        LoloParams(8, 6, 4, 3, 3, 3, 7, 3, 350),
        LoloParams(8, 7, 4, 3, 4, 4, 8, 3, 400),
    )[min(level, 7) - 1]

    fun timeLimit(level: Int) = listOf(40.0, 50.0, 60.0, 70.0, 80.0, 85.0, 90.0)[min(level, 7) - 1]
}

data class LCell(val r: Int, val c: Int)
data class LoloParams(val iw: Int, val ih: Int, val med: Int, val blk: Int, val hrt: Int, val walls: Int, val runs: Int, val must: Int, val steps: Int)
class LoloPuzzle(
    val rows: Int, val cols: Int, val walls: Set<LCell>, val medusas: Set<LCell>,
    val blocks: Set<LCell>, val hearts: Set<LCell>, val player: LCell, val exit: LCell,
)

/** Pure generation + the bitmask push-run verifier (same moves and gaze as the game). */
object StatueSolver {
    private val DIRS = listOf(0 to 1, 0 to -1, 1 to 0, -1 to 0)

    fun deadly(rows: Int, cols: Int, walls: Set<LCell>, medusas: Set<LCell>, exit: LCell, blocks: Set<LCell>): Set<LCell> {
        val out = HashSet<LCell>()
        for (m in medusas) for ((dr, dc) in DIRS) {
            var r = m.r + dr; var c = m.c + dc
            while (r in 0 until rows && c in 0 until cols) {
                val cell = LCell(r, c)
                if (cell in walls || cell in medusas || cell in blocks || cell == exit) break
                out.add(cell)
                r += dr; c += dc
            }
        }
        return out
    }

    fun makePuzzle(p: LoloParams): LoloPuzzle {
        var seed: Pair<LoloPuzzle, Triple<Int, Int, Int>>? = null
        for (i in 0 until 4000) {
            val cand = generate(p) ?: continue
            val r = rate(cand, p) ?: continue
            if (r.first <= 0) continue
            seed = cand to r; break
        }
        if (seed == null) return fallback()
        var room = seed.first; var cur = seed.second
        var best = room; var top = cur
        val deadline = System.currentTimeMillis() + 2000
        for (i in 0 until p.steps) {
            if ((top.first >= p.runs && top.second >= p.must) || System.currentTimeMillis() > deadline) break
            val cand = mutate(room)
            val r = rate(cand, p, cur.third) ?: continue
            if (r.third >= cur.third) { room = cand; cur = r }
            if (r.third > top.third) { best = cand; top = r }
        }
        return best
    }

    /** (runs, must, score) or null if no safe solution. */
    fun rate(p: LoloPuzzle, t: LoloParams, need: Int = 0): Triple<Int, Int, Int>? {
        val runs = pushRuns(p) ?: return null
        fun score(must: Int) = 3 * min(runs, t.runs + 2) + 4 * must
        var must = 0
        if (runs > 0 && score(p.blocks.size) >= need) {
            for (b in p.blocks) {
                val pinned = LoloPuzzle(p.rows, p.cols, p.walls + b, p.medusas, p.blocks - b, p.hearts, p.player, p.exit)
                if (pushRuns(pinned) == null) must++
            }
        }
        return Triple(runs, must, score(must))
    }

    fun generate(p: LoloParams): LoloPuzzle? {
        val rows = p.ih + 2; val cols = p.iw + 2
        val walls = HashSet<LCell>()
        for (r in 0 until rows) { walls.add(LCell(r, 0)); walls.add(LCell(r, cols - 1)) }
        for (c in 0 until cols) { walls.add(LCell(0, c)); walls.add(LCell(rows - 1, c)) }
        val floor = ArrayList<LCell>()
        for (r in 1..p.ih) for (c in 1..p.iw) floor.add(LCell(r, c))
        floor.shuffle()
        var idx = 0
        fun take(n: Int): List<LCell>? {
            if (idx + n > floor.size) return null
            val out = floor.subList(idx, idx + n).toList(); idx += n; return out
        }
        walls.addAll(take(p.walls) ?: return null)
        val meds = take(p.med) ?: return null
        val blks = take(p.blk) ?: return null
        val hrts = take(p.hrt) ?: return null
        val ex = take(1)?.first() ?: return null
        val gaze = deadly(rows, cols, walls, meds.toSet(), ex, blks.toSet())
        val pl = floor.subList(idx, floor.size).firstOrNull { it !in gaze } ?: return null
        return LoloPuzzle(rows, cols, walls, meds.toSet(), blks.toSet(), hrts.toSet(), pl, ex)
    }

    fun mutate(p: LoloPuzzle): LoloPuzzle {
        val walls = p.walls.toHashSet(); val meds = p.medusas.toHashSet(); val blks = p.blocks.toHashSet(); val hrts = p.hearts.toHashSet()
        var pl = p.player; var ex = p.exit
        val free = ArrayList<LCell>()
        for (r in 1 until p.rows - 1) for (c in 1 until p.cols - 1) {
            val x = LCell(r, c)
            if (x !in walls && x !in meds && x !in blks && x !in hrts && x != pl && x != ex) free.add(x)
        }
        if (free.isEmpty()) return p
        val to = free.pick()
        val rocks = walls.filter { it.r > 0 && it.c > 0 && it.r < p.rows - 1 && it.c < p.cols - 1 }
        val kinds = List(rocks.size) { 0 } + List(meds.size) { 1 } + List(blks.size) { 2 } + List(hrts.size) { 3 } + listOf(4, 5)
        when (kinds.pick()) {
            0 -> { walls.remove(rocks.pick()); walls.add(to) }
            1 -> { meds.remove(meds.toList().pick()); meds.add(to) }
            2 -> { blks.remove(blks.toList().pick()); blks.add(to) }
            3 -> { hrts.remove(hrts.toList().pick()); hrts.add(to) }
            4 -> pl = to
            else -> ex = to
        }
        return LoloPuzzle(p.rows, p.cols, walls, meds, blks, hrts, pl, ex)
    }

    private data class Key(val bs: Bits128, val x: Int)
    private class Node(val key: Key, val patch: Bits128)

    /** Fewest push runs over all safe solutions, or null. Walking is free; only pushes are edges. */
    fun pushRuns(p: LoloPuzzle): Int? {
        val rows = p.rows; val cols = p.cols
        fun mask(s: Set<LCell>): Bits128 { var m = Bits128.ZERO; for (c in s) m = m.set(c.r * cols + c.c); return m }
        val walls = mask(p.walls); val medusas = mask(p.medusas); val blocks0 = mask(p.blocks)
        val player = p.player.r * cols + p.player.c; val exit = p.exit.r * cols + p.exit.c
        val medusaList = p.medusas.map { it.r * cols + it.c }.sorted()
        val gazeCache = HashMap<Bits128, Bits128>()
        fun gaze(bs: Bits128): Bits128 = gazeCache.getOrPut(bs) {
            var out = Bits128.ZERO
            val stop = walls or medusas or bs or Bits128.bit(exit)
            for (m in medusaList) {
                val mr = m / cols; val mc = m % cols
                for ((dr, dc) in DIRS) {
                    var r = mr + dr; var c = mc + dc
                    while (r in 0 until rows && c in 0 until cols) {
                        val i = r * cols + c
                        if (stop.has(i)) break
                        out = out.set(i)
                        r += dr; c += dc
                    }
                }
            }
            out
        }
        if (gaze(blocks0).has(player)) return null
        val open = Bits128.ones(rows * cols) andNot (walls or medusas)
        val heartCells = p.hearts.map { it.r * cols + it.c }
        val heartTiles = (0 until (1 shl heartCells.size)).map { m ->
            var t = Bits128.ZERO
            heartCells.forEachIndexed { i, cell -> if (m and (1 shl i) != 0) t = t.set(cell) }
            t
        }
        fun node(t: Int, bs: Bits128, hs: Int): Node {
            val free = open andNot bs andNot gaze(bs)
            var patch = Bits128.bit(t)
            while (true) {
                val grown = (patch or (patch shl 1) or (patch shr 1) or (patch shl cols) or (patch shr cols)) and free
                if (grown == patch) break
                patch = grown
            }
            var left = hs
            heartCells.forEachIndexed { i, cell -> if (patch.has(cell)) left = left and (1 shl i).inv() }
            return Node(Key(bs, patch.trailingZeros() or (left shl 8)), patch)
        }
        val start = node(player, blocks0, heartTiles.size - 1)
        val seen = HashSet<Key>(); seen.add(start.key)
        var layer = listOf(start); var next = ArrayList<Node>()
        var runs = 0; var expanded = 0
        while (layer.isNotEmpty()) {
            for (s in layer) {
                expanded++
                if (expanded > 50_000) return null
                val hs = s.key.x shr 8
                if (hs == 0 && s.patch.has(exit)) return runs
                val stop = walls or medusas or heartTiles[hs] or Bits128.bit(exit)
                for (step in intArrayOf(1, -1, cols, -cols)) {
                    var from = s.patch and (if (step > 0) s.key.bs shr step else s.key.bs shl -step)
                    while (from.nonZero) {
                        var pl = from.trailingZeros()
                        from = from.dropLowest()
                        var bs = s.key.bs
                        while (true) {
                            val blk = pl + step; val dest = blk + step
                            if (dest < 0 || dest >= rows * cols || (stop or bs).has(dest)) break
                            bs = bs.clear(blk).set(dest)
                            pl = blk
                            if (gaze(bs).has(pl)) break
                            val n = node(pl, bs, hs)
                            if (seen.add(n.key)) next.add(n)
                        }
                    }
                }
            }
            layer = next; next = ArrayList(); runs++
        }
        return null
    }

    fun fallback(): LoloPuzzle {
        val rows = 3; val cols = 6
        val walls = HashSet<LCell>()
        for (r in 0 until rows) { walls.add(LCell(r, 0)); walls.add(LCell(r, cols - 1)) }
        for (c in 0 until cols) { walls.add(LCell(0, c)); walls.add(LCell(rows - 1, c)) }
        return LoloPuzzle(rows, cols, walls, emptySet(), emptySet(), setOf(LCell(1, 2)), LCell(1, 1), LCell(1, 4))
    }
}

private val SKY_TOP = rgb(0.36, 0.2, 0.11)
private val SKY_BOTTOM = rgb(0.14, 0.08, 0.04)

@Composable
private fun StatueMazeView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val timeLimit = StatueMazeGame.timeLimit(level)
    var playing by remember { mutableStateOf(true) }
    var ready by remember { mutableStateOf(false) }
    var rows by remember { mutableIntStateOf(0) }
    var cols by remember { mutableIntStateOf(0) }
    var walls by remember { mutableStateOf(emptySet<LCell>()) }
    var medusas by remember { mutableStateOf(emptySet<LCell>()) }
    var blocks by remember { mutableStateOf(emptySet<LCell>()) }
    var hearts by remember { mutableStateOf(emptySet<LCell>()) }
    var player by remember { mutableStateOf(LCell(0, 0)) }
    var exit by remember { mutableStateOf(LCell(0, 0)) }
    var timeLeft by remember { mutableDoubleStateOf(timeLimit) }
    var demoDir by remember { mutableStateOf<Pair<Int, Int>?>(null) }
    var facingLeft by remember { mutableStateOf(false) }
    var heartTotal by remember { mutableIntStateOf(0) }
    var stoned by remember { mutableStateOf(false) }
    val shake = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()

    val deadlyNow = remember(rows, cols, walls, medusas, exit, blocks) { StatueSolver.deadly(rows, cols, walls, medusas, exit, blocks) }

    fun win() { if (!playing) return; playing = false; onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }
    fun petrified() {
        if (!playing) return
        playing = false
        stoned = true
        SoundManager.error(); Haptics.warning()
        scope.launch { shake.snapTo(0f); shake.animateTo(1f, tween(350)) }
        scope.launch { delay(400); onFail() }
    }

    fun move(dc: Int, dr: Int) {
        if (!playing) return
        if (dc != 0) facingLeft = dc < 0
        val dest = LCell(player.r + dr, player.c + dc)
        if (dest.r < 0 || dest.r >= rows || dest.c < 0 || dest.c >= cols) return
        if (dest in walls || dest in medusas) return
        if (dest in blocks) {
            val beyond = LCell(dest.r + dr, dest.c + dc)
            if (beyond.r < 0 || beyond.r >= rows || beyond.c < 0 || beyond.c >= cols) return
            if (beyond in walls || beyond in medusas || beyond in blocks || beyond in hearts || beyond == exit) return
            blocks = blocks - dest + beyond
            player = dest
        } else {
            player = dest
            if (dest in hearts) { hearts = hearts - dest; Haptics.tap() }
        }
        SoundManager.tap()
        if (player in StatueSolver.deadly(rows, cols, walls, medusas, exit, blocks)) { petrified(); return }
        if (hearts.isEmpty() && player == exit) win()
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (isActive) {
                val r = 5; val c = 7
                rows = r; cols = c
                val wl = HashSet<LCell>()
                for (rr in 0 until r) { wl.add(LCell(rr, 0)); wl.add(LCell(rr, c - 1)) }
                for (cc in 0 until c) { wl.add(LCell(0, cc)); wl.add(LCell(r - 1, cc)) }
                walls = wl; medusas = setOf(LCell(3, 5)); blocks = emptySet(); hearts = setOf(LCell(1, 3))
                heartTotal = 1; facingLeft = false; stoned = false
                player = LCell(1, 1); exit = LCell(1, 5)
                ready = true; playing = true; timeLeft = timeLimit
                delay(700)
                repeat(4) {
                    demoDir = 1 to 0
                    move(1, 0)
                    delay(300)
                    demoDir = null
                    delay(250)
                }
                delay(1100)
            }
        } else {
            val p = StatueMazeGame.params(level)
            val t0 = System.currentTimeMillis()
            val puzzle = BoardCache.take(StatueMazeGame.key(level)) { StatueSolver.makePuzzle(p) }
            BoardCache.holdBrainstorm(t0, 0.7)
            rows = puzzle.rows; cols = puzzle.cols
            walls = puzzle.walls; medusas = puzzle.medusas
            blocks = puzzle.blocks; hearts = puzzle.hearts
            player = puzzle.player; exit = puzzle.exit
            heartTotal = puzzle.hearts.size; stoned = false
            ready = true; playing = true
            timeLeft = timeLimit
            val start = nowSec()
            while (isActive && playing) {
                delay(50)
                timeLeft = max(0.0, timeLimit - (nowSec() - start))
                if (timeLeft <= 0) { fail(); break }
            }
        }
    }

    if (!ready) { BrainstormingView(SKY_TOP, SKY_BOTTOM); return }

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp)
            .clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp)).background(rgb(0.05, 0.04, 0.04))
            .padding(top = if (isDemo) 8.dp else 12.dp, bottom = if (isDemo) 8.dp else 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(if (isDemo) 6.dp else 10.dp)
    ) {
        Box(Modifier.height(if (isDemo) 20.dp else 26.dp), contentAlignment = Alignment.Center) {
            if (hearts.isEmpty()) {
                Text(L("REACH THE DOOR", "ĐẾN CỬA"), style = ts(if (isDemo) 16.0 else 18.0, FontWeight.Black, BananaTheme.banana))
            } else Row(horizontalArrangement = Arrangement.spacedBy(if (isDemo) 5.dp else 7.dp)) {
                for (i in 0 until max(heartTotal, hearts.size)) {
                    Canvas(Modifier.size(if (isDemo) 18.dp else 24.dp).alpha(if (i < hearts.size) 1f else 0.25f)) {
                        LoloArt.heartFramer(this, 0.0, 0.0, size.width.toDouble())
                    }
                }
            }
        }
        if (!isDemo) TimeBar(timeLeft / timeLimit, Modifier.fillMaxWidth().padding(horizontal = 60.dp).height(5.dp))
        // Board.
        BoxWithConstraints(
            Modifier.fillMaxWidth().weight(1f).clipToBounds().graphicsLayer {
                val t = shake.value
                if (t > 0f && t < 1f) translationX = (4 * density * sin(t * PI * 3)).toFloat()
            }
        ) {
            val w = constraints.maxWidth.toDouble(); val h = constraints.maxHeight.toDouble()
            val cell = if (cols > 0) min(w / cols, h / rows) else 0.0
            val ox = (w - cell * cols) / 2; val oy = (h - cell * rows) / 2
            val px by animateFloatAsState((ox + player.c * cell).toFloat(), tween(110), label = "px")
            val py by animateFloatAsState((oy + player.r * cell).toFloat(), tween(110), label = "py")
            Canvas(Modifier.fillMaxSize()) {
                if (cell <= 0) return@Canvas
                drawRoom(rows, cols, walls, cell, ox, oy)
                fun rx(c: LCell) = ox + c.c * cell
                fun ry(c: LCell) = oy + c.r * cell
                for (c in deadlyNow) rect(rx(c), ry(c), cell, cell, LoloArt.gaze.op(0.3))
                for (m in medusas) for ((dr, dc) in listOf(0 to 1, 0 to -1, 1 to 0, -1 to 0)) {
                    var last: LCell? = null
                    var r = m.r + dr; var c = m.c + dc
                    while (r in 0 until rows && c in 0 until cols) {
                        val cc = LCell(r, c)
                        if (cc in walls || cc in medusas || cc in blocks || cc == exit) break
                        last = cc; r += dr; c += dc
                    }
                    val end = last ?: continue
                    val ax = rx(m) + cell / 2 + dc * cell * 0.35; val ay = ry(m) + cell / 2 + dr * cell * 0.35
                    val bx = rx(end) + cell / 2 + dc * cell * 0.5; val by = ry(end) + cell / 2 + dr * cell * 0.5
                    line(ax, ay, bx, by, LoloArt.gaze.op(0.35), cell * 0.3)
                    line(ax, ay, bx, by, rgb(1.0, 0.55, 0.5, 0.9), max(1.5, cell * 0.06))
                }
                LoloArt.door(this, rx(exit), ry(exit), cell, hearts.isEmpty())
                for (hh in hearts) LoloArt.heartFramer(this, rx(hh) + cell * 0.1, ry(hh) + cell * 0.1, cell * 0.8)
                for (b in blocks) LoloArt.emeraldFramer(this, rx(b), ry(b), cell)
                for (m in medusas) LoloArt.medusa(this, rx(m), ry(m), cell)
                LoloArt.hero(this, px.toDouble(), py.toDouble(), cell, facingLeft, stoned)
            }
        }
        // NES d-pad.
        val a = if (isDemo) 32.0 else 46.0
        Box(Modifier.size((a * 3 + 4).dp).shadow(0.dp), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize()) {
                val s = size.width.toDouble()
                nesCross(0.0, 0.0, s, gray(0.42))
                val inset = 2 * density.toDouble()
                nesCross(inset, inset, s - inset * 2, null)
                circle(s / 2, s / 2, a * density * 0.55 / 2, gray(0.07))
            }
            for ((dc, dr) in listOf(0 to -1, -1 to 0, 1 to 0, 0 to 1)) {
                val lit = demoDir?.first == dc && demoDir?.second == dr
                DPadArm(a, dc, dr, lit, Modifier.offset((dc * a).dp, (dr * a).dp)) { if (!isDemo) move(dc, dr) }
            }
        }
    }
}

@Composable
private fun DPadArm(a: Double, dc: Int, dr: Int, lit: Boolean, modifier: Modifier, onTap: () -> Unit) {
    var pressed by remember { mutableStateOf(false) }
    val on = lit || pressed
    val s by animateFloatAsState(if (on) 0.92f else 1f, tween(80), label = "arm")
    val angle = if (dr < 0) 0f else if (dr > 0) 180f else if (dc < 0) 270f else 90f
    Box(
        modifier.size(a.dp).scale(s)
            .background(if (on) BananaTheme.banana else Color.Transparent, RoundedCornerShape((a * 0.16).dp))
            .pressDown(onDown = { pressed = true; onTap() }, onUp = { pressed = false }),
        contentAlignment = Alignment.Center
    ) {
        Icon(Icons.Filled.ArrowDropUp, null, tint = if (on) Color.Black else gray(0.55), modifier = Modifier.size((a * 0.75).dp).rotate(angle))
    }
}

private fun DrawScope.nesCross(x: Double, y: Double, s: Double, fill: Color?) {
    val a = s / 3
    val p = Path()
    p.addRoundRect(RoundRect((x + a).f, y.f, (x + 2 * a).f, (y + s).f, CornerRadius((a * 0.2).f)))
    p.addRoundRect(RoundRect(x.f, (y + a).f, (x + s).f, (y + 2 * a).f, CornerRadius((a * 0.2).f)))
    if (fill != null) drawPath(p, fill) else drawPath(p, vgrad(listOf(gray(0.24), gray(0.1)), y, y + s))
}

private fun DrawScope.drawRoom(rows: Int, cols: Int, walls: Set<LCell>, cell: Double, ox: Double, oy: Double) {
    for (r in 0 until rows) for (c in 0 until cols) {
        val x = ox + c * cell; val y = oy + r * cell
        val here = LCell(r, c)
        if (here !in walls) LoloArt.floor(this, x, y, cell, r)
        else if (r == 0 || c == 0 || r == rows - 1 || c == cols - 1) LoloArt.block(this, x, y, cell)
        else { LoloArt.floor(this, x, y, cell, r); LoloArt.rock(this, x, y, cell) }
    }
}

/** The NES room art: sandstone blocks, brick floor, boulders, Heart/Emerald Framers, Medusas, door, hero. */
private object LoloArt {
    val sand = rgb(0.9, 0.73, 0.49)
    val sandLight = rgb(0.99, 0.88, 0.67)
    val sandDark = rgb(0.64, 0.45, 0.26)
    val mortar = rgb(0.25, 0.13, 0.06)
    val brick = rgb(0.5, 0.27, 0.14)
    val gaze = rgb(1.0, 0.16, 0.12)

    fun floor(d: DrawScope, x: Double, y: Double, s: Double, row: Int) = with(d) {
        rect(x, y, s, s, mortar)
        clipRect(x.f, y.f, (x + s).f, (y + s).f) {
            val h = s / 2; val bw = s / 2
            for (k in 0 until 2) {
                val yy = y + k * h
                val shift = if ((row * 2 + k) % 2 == 0) 0.0 else bw / 2
                for (i in -1..2) {
                    val bx = x + i * bw + shift + 0.7; val by = yy + 0.7; val w = bw - 1.4; val hh = h - 1.4
                    rrect(bx, by, w, hh, 1.2, vgrad(listOf(brick.lit(0.12), brick, brick.shade(0.15)), by, by + hh))
                    rect(bx + 1, by, w - 2, max(0.8, h * 0.1), brick.lit(0.3).op(0.6))
                }
            }
        }
    }

    fun block(d: DrawScope, x0: Double, y0: Double, s0: Double) = with(d) {
        val x = x0 + 0.6; val y = y0 + 0.6; val s = s0 - 1.2
        val e = s * 0.16
        val rr = s * 0.12
        rrect(x, y, s, s, rr, sand)
        val clip = Path().apply { addRoundRect(RoundRect(x.f, y.f, (x + s).f, (y + s).f, CornerRadius(rr.f))) }
        clipPath(clip) {
            drawPath(polyPath(x, y + s, x, y, x + s, y, x + s - e, y + e, x + e, y + e, x + e, y + s - e), sandLight)
            drawPath(polyPath(x + s, y, x + s, y + s, x, y + s, x + e, y + s - e, x + s - e, y + s - e, x + s - e, y + e), sandDark)
            circle(x + s * 0.62, y + s * 0.42, s * 0.05, sandDark.op(0.7))
            circle(x + s * 0.36, y + s * 0.64, s * 0.035, sandDark.op(0.6))
        }
        rrectStroke(x, y, s, s, rr, mortar, max(1.0, s0 * 0.035))
    }

    fun rock(d: DrawScope, x: Double, y: Double, s: Double) = with(d) {
        oval(x + s * 0.1, y + s * 0.62, s * 0.84, s * 0.3, Color.Black.op(0.3))
        for ((fx, fy, rr) in listOf(Triple(0.33, 0.4, 0.25), Triple(0.66, 0.42, 0.24), Triple(0.5, 0.63, 0.3))) {
            val cx = x + s * fx; val cy = y + s * fy
            circle(cx, cy, s * rr, radial(listOf(sandLight, sand, sandDark), cx - s * rr * 0.35, cy - s * rr * 0.4, s * rr * 1.25))
            circleStroke(cx, cy, s * rr, mortar, max(1.0, s * 0.035))
        }
    }

    fun heartPath(x: Double, y: Double, w: Double, h: Double): Path {
        val p = Path()
        val mx = x + w / 2
        p.m(mx, y + h * 0.26)
        p.c(mx - w * 0.1, y - h * 0.08, x, y - h * 0.02, x, y + h * 0.3)
        p.c(x, y + h * 0.62, mx - w * 0.22, y + h * 0.8, mx, y + h)
        p.c(mx + w * 0.22, y + h * 0.8, x + w, y + h * 0.62, x + w, y + h * 0.3)
        p.c(x + w, y - h * 0.02, mx + w * 0.1, y - h * 0.08, mx, y + h * 0.26)
        p.close()
        return p
    }

    fun heartFramer(d: DrawScope, x: Double, y: Double, s: Double) = with(d) {
        val fx = x + s * 0.04; val fy = y + s * 0.04; val fw = s * 0.92
        rrect(fx, fy + s * 0.05, fw, fw, s * 0.16, Color.Black.op(0.3))
        rrect(fx, fy, fw, fw, s * 0.16, vgrad(listOf(Color.White, rgb(0.93, 0.86, 0.9)), fy, fy + fw))
        rrectStroke(fx, fy, fw, fw, s * 0.16, rgb(0.55, 0.3, 0.4), max(1.0, s * 0.05))
        val ix = fx + s * 0.12; val iy = fy + s * 0.12; val iw = fw - s * 0.24
        rrect(ix, iy, iw, iw, s * 0.1, rgb(1.0, 0.84, 0.9))
        val heart = heartPath(ix + s * 0.05, iy + s * 0.07, iw - s * 0.1, iw - s * 0.14)
        drawPath(heart, vgrad(listOf(rgb(1.0, 0.42, 0.56), rgb(0.86, 0.1, 0.3)), iy, iy + iw))
        strokePath(heart, rgb(0.5, 0.05, 0.15), max(0.8, s * 0.035))
        circle(ix + iw * 0.32, iy + iw * 0.34, s * 0.05, Color.White.op(0.85))
    }

    fun oct(x: Double, y: Double, w: Double, h: Double, cut: Double) =
        polyPath(x + cut, y, x + w - cut, y, x + w, y + cut, x + w, y + h - cut, x + w - cut, y + h, x + cut, y + h, x, y + h - cut, x, y + cut)

    fun emeraldFramer(d: DrawScope, x: Double, y: Double, s: Double) = with(d) {
        val bx = x + s * 0.07; val by = y + s * 0.07; val bw = s * 0.86
        val k = bw * 0.26
        drawPath(oct(bx, by + s * 0.06, bw, bw, k), Color.Black.op(0.35))
        drawPath(oct(bx, by, bw, bw, k), lin(listOf(rgb(0.55, 0.95, 0.55), rgb(0.1, 0.5, 0.22)), bx, by, bx + bw, by + bw))
        val fx = bx + bw * 0.2; val fy = by + bw * 0.2; val fw = bw * 0.6
        drawPath(oct(fx, fy, fw, fw, k * 0.5), lin(listOf(rgb(0.3, 0.8, 0.4), rgb(0.16, 0.6, 0.3)), fx, fy, fx + fw, fy + fw))
        strokePath(oct(fx, fy, fw, fw, k * 0.5), rgb(0.04, 0.3, 0.12, 0.7), max(0.8, s * 0.025))
        strokePath(oct(bx, by, bw, bw, k), rgb(0.03, 0.25, 0.1), max(1.0, s * 0.04))
        circle(fx + fw * 0.3, fy + fw * 0.3, s * 0.06, Color.White.op(0.75))
    }

    fun medusa(d: DrawScope, x: Double, y: Double, s: Double) = with(d) {
        val cx = x + s / 2; val cy = y + s / 2 + s * 0.06
        oval(cx - s * 0.36, cy + s * 0.18, s * 0.72, s * 0.2, Color.Black.op(0.35))
        val snake = rgb(0.24, 0.56, 0.3)
        val dark = rgb(0.06, 0.2, 0.08)
        listOf(-165.0, -130.0, -90.0, -50.0, -15.0).forEachIndexed { i, a ->
            val rad = a * PI / 180
            val bx = cx + cos(rad) * s * 0.24; val by = cy - s * 0.02 + sin(rad) * s * 0.24
            val tx = cx + cos(rad) * s * 0.44; val ty = cy - s * 0.02 + sin(rad) * s * 0.44
            val wob = (if (i % 2 == 0) 1.0 else -1.0) * s * 0.08
            val p = Path(); p.m(bx, by); p.q((bx + tx) / 2 - sin(rad) * wob, (by + ty) / 2 + cos(rad) * wob, tx, ty)
            strokePath(p, dark, s * 0.11)
            strokePath(p, snake, s * 0.065)
            circle(tx, ty, s * 0.06, snake.lit(0.15))
            circleStroke(tx, ty, s * 0.06, dark, max(0.8, s * 0.02))
        }
        val fcx = cx; val fcy = cy - s * 0.3 + s * 0.28
        ellipse(fcx, fcy, s * 0.29, s * 0.28, radial(listOf(rgb(0.74, 0.8, 0.7), rgb(0.5, 0.58, 0.5), rgb(0.32, 0.38, 0.32)), cx - s * 0.08, cy - s * 0.12, s * 0.4))
        ellipseStroke(fcx, fcy, s * 0.29, s * 0.28, rgb(0.14, 0.18, 0.14), max(1.0, s * 0.04))
        for (sx in listOf(-1.0, 1.0)) {
            val ex = cx + sx * s * 0.11; val ey = cy - s * 0.05
            circle(ex, ey, s * 0.1, radial(listOf(gaze.op(0.7), gaze.op(0.0)), ex, ey, s * 0.1))
            ellipse(ex, ey, s * 0.06, s * 0.04, rgb(1.0, 0.95, 0.6))
            circle(ex, ey, s * 0.028, rgb(0.9, 0.05, 0.05))
            line(ex - sx * s * 0.08, ey - s * 0.09, ex + sx * s * 0.06, ey - s * 0.05, rgb(0.14, 0.18, 0.14), max(1.0, s * 0.04))
        }
        val mouth = Path(); mouth.m(cx - s * 0.08, cy + s * 0.14); mouth.q(cx, cy + s * 0.08, cx + s * 0.08, cy + s * 0.14)
        strokePath(mouth, rgb(0.14, 0.18, 0.14), max(1.0, s * 0.035))
    }

    fun archPath(x: Double, y: Double, w: Double, h: Double): Path {
        val p = Path()
        p.m(x, y + h)
        p.l(x, y + w / 2)
        p.arc(x + w / 2, y + w / 2, w / 2, PI, 0.0, clockwise = false)
        p.l(x + w, y + h)
        p.close()
        return p
    }

    fun door(d: DrawScope, x: Double, y: Double, s: Double, open: Boolean) = with(d) {
        val ax = x + s * 0.1; val ay = y + s * 0.06; val aw = s * 0.8; val ah = s * 0.9
        drawPath(archPath(ax, ay, aw, ah), lin(listOf(sandLight, sandDark), ax, ay, ax + aw, ay + ah))
        strokePath(archPath(ax, ay, aw, ah), mortar, max(1.0, s * 0.035))
        val ix = ax + s * 0.1; val iy = ay + s * 0.05; val iw = aw - s * 0.2; val ih = ah - s * 0.05
        val inside = archPath(ix, iy, iw, ih)
        if (open) {
            drawPath(inside, rgb(0.06, 0.03, 0.02))
            drawPath(inside, radial(listOf(BananaTheme.banana.op(0.95), BananaTheme.banana.op(0.0)), ix + iw / 2, iy + ih - s * 0.1, s * 0.5))
        } else {
            drawPath(inside, lin(listOf(rgb(0.55, 0.33, 0.16), rgb(0.36, 0.2, 0.09)), ix, iy, ix + iw, iy + ih))
            for (k in 1..2) {
                val px = ix + iw * k / 3
                line(px, iy + s * 0.04, px, iy + ih, Color.Black.op(0.35), max(0.8, s * 0.025), StrokeCap.Butt)
            }
            for (fy in listOf(0.42, 0.78)) rect(ix, iy + ih * fy - s * 0.03, iw, s * 0.06, gray(0.3))
            circle(ix + iw / 2, iy + ih * 0.6, s * 0.045, BananaTheme.banana)
        }
    }

    /** The banana hero in Lolo's style; (x, y) is the cell's top-left. */
    fun hero(d: DrawScope, x: Double, y: Double, s: Double, facingLeft: Boolean, stone: Boolean) = with(d) {
        translate((x + s / 2).f, (y + s / 2).f) {
            scale(if (facingLeft) -1f else 1f, 1f, androidx.compose.ui.geometry.Offset.Zero) {
                val peel = if (stone) gray(0.62) else rgb(1.0, 0.86, 0.2)
                val peelDark = if (stone) gray(0.4) else rgb(0.86, 0.62, 0.08)
                val ink = rgb(0.25, 0.15, 0.04)
                val feet = if (stone) gray(0.5) else rgb(0.88, 0.18, 0.14)
                oval(-s * 0.3, s * 0.3, s * 0.6, s * 0.14, Color.Black.op(0.35))
                for (fx in listOf(-0.17, 0.09)) {
                    oval(fx * s, s * 0.27, s * 0.2, s * 0.12, feet)
                    ellipseStroke(fx * s + s * 0.1, s * 0.33, s * 0.1, s * 0.06, ink, max(1.0, s * 0.03))
                }
                val body = Path()
                body.m(-0.06 * s, -0.42 * s)
                body.q(-0.42 * s, -0.02 * s, -0.08 * s, 0.3 * s)
                body.q(0.46 * s, 0.04 * s, -0.06 * s, -0.42 * s)
                body.close()
                drawPath(body, lin(listOf(peel.lit(0.35), peel, peelDark), -0.3 * s, -0.3 * s, 0.3 * s, 0.3 * s))
                val ridge = Path(); ridge.m(-0.05 * s, -0.36 * s); ridge.q(0.2 * s, 0.0, -0.06 * s, 0.24 * s)
                strokePath(ridge, peelDark.op(0.55), max(1.0, s * 0.03))
                strokePath(body, ink, max(1.0, s * 0.04))
                rrect(-s * 0.1, -s * 0.5, s * 0.09, s * 0.12, s * 0.02, if (stone) gray(0.35) else rgb(0.42, 0.28, 0.1))
                circle(-0.075 * s, 0.29 * s, s * 0.035, ink)
                for ((ex, ey) in listOf(-0.1 to -0.1, 0.07 to -0.08)) {
                    val cx = ex * s; val cy = ey * s - s * 0.01
                    ellipse(cx, cy, s * 0.085, s * 0.11, Color.White)
                    ellipseStroke(cx, cy, s * 0.085, s * 0.11, ink, max(1.0, s * 0.03))
                    oval(cx - s * 0.005, cy - s * 0.06, s * 0.07, s * 0.1, if (stone) gray(0.3) else Color.Black)
                }
            }
        }
    }
}
