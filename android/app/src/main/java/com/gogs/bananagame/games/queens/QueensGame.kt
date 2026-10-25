package com.gogs.bananagame.games.queens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material3.Icon
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
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/**
 * Brain — Queens (iOS QueensGame.swift, id "queens"): the LinkedIn daily puzzle. One crown in every
 * row, column and colour region, and no two crowns may touch, not even diagonally. Tap a cell to cycle
 * empty → X → crown → empty; clashing crowns stripe their row / column / region red, and a clashing
 * crown costs one of three strikes. Boards are generated solution-first and repaired until a
 * backtracking solver proves the answer unique; early levels must also fall to pure deduction.
 */
object QueensGame {
    val definition = GameDefinition(
        id = "queens",
        title = "Queens",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Place one crown in every row, every column and every color region.",
                "Crowns can never touch each other, not even diagonally.",
                "Tap a cell once for an X note, twice for a crown, a third time to clear it.",
                "Three clashing crowns, or the clock running out, sends you back to level 1.",
            ),
            bulletsVI = listOf(
                "Đặt một vương miện ở mỗi hàng, mỗi cột và mỗi vùng màu.",
                "Các vương miện không bao giờ được chạm nhau, kể cả theo đường chéo.",
                "Chạm một ô một lần để ghi chú X, hai lần để đặt vương miện, lần ba để xóa.",
                "Đặt sai ba vương miện, hoặc hết giờ, bạn sẽ về lại cấp 1.",
            ),
            liveDemo = true
        ),
        prefetch = { level -> BoardCache.prefetch(key(level)) { QueensGen.generate(QueensGen.size(level), QueensGen.grade(level)) } },
        content = { level, onWin, onFail -> QueensView(level, onWin, onFail) }
    )

    fun key(level: Int) = BoardCache.key("queens", level)
}

/** `regions`: region id (0 until n) per cell, row-major; `solution`: the crown column for each row. */
class QueensBoard(val n: Int, val regions: IntArray, val solution: IntArray)

object QueensGen {
    fun size(level: Int) = listOf(5, 6, 7, 7, 8, 9, 10)[min(max(level, 1), 7) - 1]
    fun grade(level: Int) = listOf(1, 1, 2, 2, 2, 3, 3)[min(max(level, 1), 7) - 1]
    fun timeLimit(level: Int) = listOf(60.0, 70.0, 80.0, 65.0, 85.0, 95.0, 100.0)[min(max(level, 1), 7) - 1]

    fun neighbors(i: Int, n: Int): List<Int> {
        val r = i / n; val c = i % n
        val out = ArrayList<Int>(4)
        if (r > 0) out.add(i - n)
        if (r < n - 1) out.add(i + n)
        if (c > 0) out.add(i - 1)
        if (c < n - 1) out.add(i + 1)
        return out
    }

    /** A random legal crown layout: one per row / column, consecutive rows ≥ 2 columns apart. */
    fun randomSolution(n: Int): IntArray {
        val cols = IntArray(n) { -1 }
        val used = BooleanArray(n)
        fun place(r: Int): Boolean {
            if (r == n) return true
            for (c in (0 until n).shuffled()) {
                if (used[c]) continue
                if (r > 0 && abs(c - cols[r - 1]) < 2) continue
                cols[r] = c; used[c] = true
                if (place(r + 1)) return true
                used[c] = false
            }
            return false
        }
        place(0)
        return cols
    }

    /** Grows one region per crown by a weighted random flood fill, so sizes vary (pockets next to snakes). */
    fun grow(n: Int, solution: IntArray): IntArray {
        val reg = IntArray(n * n) { -1 }
        val weights = DoubleArray(n) { listOf(0.35, 1.0, 1.0, 1.6, 2.6).random() }
        val frontier = Array(n) { mutableListOf<Int>() }
        for ((r, c) in solution.withIndex()) {
            val i = r * n + c
            reg[i] = r
            frontier[r].addAll(neighbors(i, n))
        }
        var left = n * n - n
        while (left > 0) {
            val live = (0 until n).filter { frontier[it].isNotEmpty() }
            if (live.isEmpty()) break
            val total = live.sumOf { weights[it] }
            var pick = Random.nextDouble(total)
            var k = live[0]
            for (x in live) { pick -= weights[x]; if (pick < 0) { k = x; break } }
            val j = frontier[k].removeAt(Random.nextInt(frontier[k].size))
            if (reg[j] != -1) continue
            reg[j] = k
            left--
            frontier[k].addAll(neighbors(j, n).filter { reg[it] == -1 })
        }
        return reg
    }

    /** Counts solutions (stopping at 2) and returns the first one that differs from `intended`. */
    fun solve(n: Int, reg: IntArray, intended: IntArray): Pair<Int, IntArray?> {
        val cols = IntArray(n) { -1 }
        var count = 0
        var other: IntArray? = null
        fun bt(r: Int, colMask: Int, regMask: Int, prev: Int): Boolean {
            if (r == n) {
                count++
                if (other == null && !cols.contentEquals(intended)) other = cols.copyOf()
                return count >= 2
            }
            for (c in 0 until n) {
                if ((colMask shr c) and 1 == 1) continue
                if (prev >= 0 && abs(c - prev) < 2) continue
                val g = reg[r * n + c]
                if ((regMask shr g) and 1 == 1) continue
                cols[r] = c
                if (bt(r + 1, colMask or (1 shl c), regMask or (1 shl g), c)) return true
            }
            return false
        }
        bt(0, 0, 0, -1)
        return count to other
    }

    fun stillConnected(n: Int, reg: IntArray, removing: Int): Boolean {
        val k = reg[removing]
        val cells = (0 until n * n).filter { reg[it] == k && it != removing }
        val first = cells.firstOrNull() ?: return false
        val members = cells.toSet()
        val seen = mutableSetOf(first)
        val stack = mutableListOf(first)
        while (stack.isNotEmpty()) {
            val x = stack.removeAt(stack.size - 1)
            for (y in neighbors(x, n)) if (y in members && seen.add(y)) stack.add(y)
        }
        return seen.size == cells.size
    }

    /**
     * Human-style solver used to grade boards: singles (a row / column / region with one open cell) and
     * confinement (a region squeezed into one line clears the rest of it), plus — with `lookahead` —
     * "a crown here would leave some line or region with no room".
     */
    fun logicSolvable(n: Int, reg: IntArray, lookahead: Boolean): Boolean {
        val cellCount = n * n
        val units = mutableListOf<List<Int>>()
        for (r in 0 until n) units.add((0 until n).map { r * n + it })
        for (c in 0 until n) units.add((0 until n).map { it * n + c })
        for (k in 0 until n) units.add((0 until cellCount).filter { reg[it] == k })
        val unitsOf = (0 until cellCount).map { listOf(it / n, n + it % n, 2 * n + reg[it]) }
        val cand = BooleanArray(cellCount) { true }
        val done = BooleanArray(units.size)
        var placed = 0
        fun killSet(i: Int): Set<Int> {
            val s = HashSet<Int>()
            for (u in unitsOf[i]) s.addAll(units[u])
            val r = i / n; val c = i % n
            for (dr in -1..1) for (dc in -1..1) {
                val rr = r + dr; val cc = c + dc
                if (rr in 0 until n && cc in 0 until n) s.add(rr * n + cc)
            }
            return s
        }
        fun place(i: Int) {
            for (j in killSet(i)) cand[j] = false
            for (u in unitsOf[i]) done[u] = true
            placed++
        }
        while (placed < n) {
            var progress = false
            for (u in units.indices) {
                if (done[u]) continue
                var only = -1; var count = 0
                for (i in units[u]) if (cand[i]) { count++; only = i; if (count > 1) break }
                if (count == 0) return false
                if (count == 1) { place(only); progress = true; break }
            }
            if (progress) continue
            confine@ for (u in units.indices) {
                if (done[u]) continue
                val cs = units[u].filter { cand[it] }
                val first = cs.firstOrNull() ?: return false
                for (v in unitsOf[first]) {
                    if (v / n == u / n || done[v]) continue
                    if (cs.all { unitsOf[it].contains(v) }) {
                        val inU = cs.toSet()
                        var changed = false
                        for (j in units[v]) if (cand[j] && j !in inU) { cand[j] = false; changed = true }
                        if (changed) { progress = true; break@confine }
                    }
                }
            }
            if (progress) continue
            if (lookahead) {
                for (i in 0 until cellCount) {
                    if (!cand[i]) continue
                    val kill = killSet(i)
                    var dead = false
                    for (u in units.indices) {
                        if (done[u] || unitsOf[i].contains(u)) continue
                        if (units[u].none { cand[it] && it !in kill }) { dead = true; break }
                    }
                    if (dead) { cand[i] = false; progress = true; break }
                }
                if (progress) continue
            }
            return false
        }
        return true
    }

    /** grade 1 = deduction only, 2 = deduction + one-step lookahead, 3 = any unique board. */
    fun generate(n: Int, grade: Int): QueensBoard {
        var fallback: QueensBoard? = null
        repeat(600) {
            val sol = randomSolution(n)
            val reg = grow(n, sol)
            val seeds = sol.withIndex().map { it.index * n + it.value }.toSet()
            for (step in 0 until 80) {
                val (count, other) = solve(n, reg, sol)
                if (count == 1) {
                    val board = QueensBoard(n, reg.copyOf(), sol)
                    if (grade >= 3 || logicSolvable(n, reg, grade >= 2)) return board
                    if (fallback == null) fallback = board
                    break
                }
                if (other == null) break
                // Break the rival solution: hand one of its crown cells to a neighbouring region. The
                // intended crowns are region seeds and never move, so the real answer survives.
                var moved = false
                for (r in (0 until n).shuffled()) {
                    if (other[r] == sol[r]) continue
                    val x = r * n + other[r]
                    if (x in seeds) continue
                    val targets = neighbors(x, n).map { reg[it] }.toSet() - reg[x]
                    if (targets.isNotEmpty() && stillConnected(n, reg, x)) { reg[x] = targets.random(); moved = true; break }
                }
                if (!moved) break
            }
        }
        return fallback ?: QueensBoard(5, demoRegions, demoSolution)
    }

    /**
     * The manual clip's 5×5 board, graded "pure deduction": regions 0 and 1 are 2-cell pockets in rows
     * 0 and 1, so X the rest of those rows; then region 2 is a single cell and the crowns fall in turn.
     */
    val demoRegions = intArrayOf(2, 2, 2, 0, 0, 2, 4, 1, 1, 3, 2, 4, 4, 3, 3, 4, 4, 3, 3, 4, 4, 4, 4, 4, 4)
    val demoSolution = intArrayOf(4, 2, 0, 3, 1)
    val demoColors = intArrayOf(3, 5, 1, 2, 0)          // pocket colours chosen to read clearly
    val demoNotes = listOf(0, 1, 2, 5, 6, 9)            // X'd cells (rows 0–1 outside the pockets)
    val demoCrowns = listOf(10, 21, 18, 4, 7)
}

/** The play state: marks (0 empty, 1 X, 2 crown), strikes, and the clashes the auto-check shows. */
class QueensPlay(board: QueensBoard, val colorOf: IntArray) {
    val n = board.n
    val regions = board.regions
    val marks = IntArray(n * n)
    var mistakes = 0
    /** Every crown placed with no clash: the run loop plays the crown wave, then reports the win. */
    var solved = false

    val crowns get() = marks.count { it == 2 }

    /** Cells to stripe (every line / region holding 2+ crowns, plus touching pairs) and the crowns involved. */
    fun conflicts(): Pair<Set<Int>, Set<Int>> {
        val crowns = marks.indices.filter { marks[it] == 2 }
        val striped = HashSet<Int>(); val bad = HashSet<Int>()
        if (crowns.size < 2) return striped to bad
        fun mark(group: List<Int>, cells: List<Int>) { if (group.size > 1) { bad.addAll(group); striped.addAll(cells) } }
        for (r in 0 until n) mark(crowns.filter { it / n == r }, (0 until n).map { r * n + it })
        for (c in 0 until n) mark(crowns.filter { it % n == c }, (0 until n).map { it * n + c })
        for (k in 0 until n) mark(crowns.filter { regions[it] == k }, (0 until n * n).filter { regions[it] == k })
        for (a in crowns) for (b in crowns) {
            if (b > a && abs(a / n - b / n) <= 1 && abs(a % n - b % n) <= 1) { bad.add(a); bad.add(b); striped.add(a); striped.add(b) }
        }
        return striped to bad
    }

    /** Cycles a cell; returns +1 for a clean move, -1 for a clashing crown (a strike), 0 if ignored. */
    fun tap(i: Int): Int {
        if (solved || i !in marks.indices) return 0
        marks[i] = (marks[i] + 1) % 3
        if (marks[i] != 2) return 1
        val (_, bad) = conflicts()
        if (i in bad) { mistakes++; return -1 }
        if (crowns == n && bad.isEmpty()) solved = true
        return 1
    }
}

private val palette = listOf(
    rgb(0.733, 0.639, 0.886),   // lavender
    rgb(1.000, 0.788, 0.573),   // apricot
    rgb(0.588, 0.745, 1.000),   // sky
    rgb(0.702, 0.875, 0.627),   // sage
    rgb(0.875, 0.875, 0.875),   // light grey
    rgb(1.000, 0.482, 0.376),   // coral
    rgb(0.902, 0.953, 0.533),   // lime
    rgb(0.725, 0.698, 0.620),   // khaki
    rgb(0.875, 0.627, 0.749),   // rose
    rgb(0.639, 0.824, 0.847),   // teal
)
private val INK = rgb(0.10, 0.10, 0.11)
private val CLASH = rgb(0.86, 0.16, 0.14)
private const val MAX_MISTAKES = 3

@Composable
private fun QueensView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    var play by remember { mutableStateOf<QueensPlay?>(null) }
    var ver by remember { mutableIntStateOf(0) }              // bumped on every tap, to redraw
    var timeLeft by remember { mutableDoubleStateOf(QueensGen.timeLimit(level)) }
    var celebrate by remember { mutableDoubleStateOf(-1.0) }   // win wave progress 0…1 (−1 = idle)
    var demoCell by remember { mutableStateOf<Int?>(null) }
    var shakeT0 by remember { mutableDoubleStateOf(-10.0) }
    var done by remember { mutableStateOf(false) }
    val handP = rememberHand()
    val tick by rememberFrameLoop(running = shakeT0 > 0 || celebrate >= 0)

    fun tap(i: Int) {
        val p = play ?: return
        if (done) return
        when (p.tap(i)) {
            -1 -> {
                shakeT0 = nowSec(); SoundManager.error(); Haptics.warning()
                if (p.mistakes >= MAX_MISTAKES && !isDemo) { done = true; SoundManager.error(); onFail() }
            }
            1 -> { SoundManager.tap(); Haptics.tap() }
        }
        ver++
    }
    suspend fun winWave() {
        val t0 = nowSec()
        while (true) {
            val t = (nowSec() - t0) / 0.75
            celebrate = min(1.0, t)
            if (t >= 1) break
            delay(16)
        }
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (isActive) {
                play = QueensPlay(QueensBoard(5, QueensGen.demoRegions, QueensGen.demoSolution), QueensGen.demoColors)
                celebrate = -1.0; demoCell = null; ver++
                delay(700)
                for (cell in QueensGen.demoNotes) { demoCell = cell; delay(160); tap(cell); delay(200) }
                for (cell in QueensGen.demoCrowns) { demoCell = cell; delay(220); tap(cell); delay(200); tap(cell); delay(300) }
                demoCell = null
                if (play?.solved == true) winWave()
                delay(1200)
            }
        } else {
            val t0 = System.currentTimeMillis()
            val board = BoardCache.take(QueensGame.key(level)) { QueensGen.generate(QueensGen.size(level), QueensGen.grade(level)) }
            BoardCache.holdBrainstorm(t0, 0.7)
            play = QueensPlay(board, (0 until board.n).shuffled().toIntArray())
            val limit = QueensGen.timeLimit(level)
            val start = nowSec()
            // Drives the clock and the win wave.
            while (isActive && !done) {
                delay(50)
                if (play?.solved == true) {
                    winWave()
                    done = true
                    onWin()
                    break
                }
                timeLeft = max(0.0, limit - (nowSec() - start))
                if (timeLeft <= 0) { done = true; SoundManager.error(); onFail() }
            }
        }
    }

    val p = play
    if (p == null) { BrainstormingView(gray(0.13), gray(0.05)); return }

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 12.dp else 18.dp, vertical = if (isDemo) 8.dp else 6.dp),
        verticalArrangement = Arrangement.spacedBy(if (isDemo) 8.dp else 14.dp)
    ) {
        if (!isDemo) TimeBar(timeLeft / QueensGen.timeLimit(level), Modifier.fillMaxWidth().padding(horizontal = 48.dp).height(6.dp))
        ver
        StatusRow(p.crowns, p.n, p.mistakes, isDemo)
        BoxWithConstraints(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
            val side = minOf(maxWidth, maxHeight)
            val corner = side * 0.025f
            Canvas(
                Modifier.size(side)
                    .graphicsLayer {
                        val t = nowSec() - shakeT0
                        if (t in 0.0..0.35) {
                            val k = sin(t / 0.35 * PI * 3)
                            translationX = (7 * density * k).toFloat(); translationY = (7 * 0.6 * density * k).toFloat()
                        }
                    }
                    .drawWithContent {
                        drawContent()
                        drawRoundRect(Color.White.op(0.14), cornerRadius = CornerRadius(corner.toPx()), style = Stroke(1.dp.toPx()))
                    }
                    .clip(RoundedCornerShape(corner))
                    .then(if (isDemo) Modifier else Modifier.tapIn { pt, w, _ ->
                        val cell = w / p.n
                        val c = (pt.x / cell).toInt(); val r = (pt.y / cell).toInt()
                        if (r in 0 until p.n && c in 0 until p.n) tap(r * p.n + c)
                    })
            ) {
                tick; ver
                inPoints { w, _ -> board(p, w, celebrate, if (isDemo) demoCell else null) }
                val d = demoCell
                if (isDemo && d != null) {
                    val cell = size.width / p.n.toDouble()
                    val mx = (d % p.n + 0.5) * cell; val my = (d / p.n + 0.5) * cell
                    val hw = cell * 0.62
                    hand(handP, mx + cell * 0.02, my + cell * 0.08, hw)
                }
            }
        }
    }
}

/** The crown count and the three strikes. */
@Composable
private fun StatusRow(crowns: Int, n: Int, mistakes: Int, isDemo: Boolean) {
    val fs = if (isDemo) 15.0 else 19.0
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Canvas(Modifier.size((fs * 1.15).dp, fs.dp)) { crown(0.0, 0.0, size.width.toDouble(), size.height.toDouble(), BananaTheme.banana) }
        Text("$crowns/$n", style = ts(fs, FontWeight.Black))
        Spacer(Modifier.weight(1f))
        for (i in 0 until MAX_MISTAKES) {
            Icon(Icons.Filled.Cancel, null, tint = if (i < mistakes) CLASH else Color.White.op(0.18), modifier = Modifier.size((fs * 1.1).dp))
        }
    }
}

/** A crown like SF Symbols' crown.fill: three ball-tipped points over a band, filling (x, y, w, h). */
private fun DrawScope.crown(x: Double, y: Double, w: Double, h: Double, color: Color) {
    val body = polyPath(
        x + w * 0.12, y + h * 0.74, x + w * 0.05, y + h * 0.28, x + w * 0.32, y + h * 0.5,
        x + w * 0.5, y + h * 0.14, x + w * 0.68, y + h * 0.5, x + w * 0.95, y + h * 0.28, x + w * 0.88, y + h * 0.74,
    )
    drawPath(body, color)
    for ((px, py) in listOf(0.05 to 0.24, 0.5 to 0.1, 0.95 to 0.24)) circle(x + w * px, y + h * py, w * 0.075, color)
    rrect(x + w * 0.12, y + h * 0.8, w * 0.76, h * 0.14, w * 0.04, color)
}

private fun DrawScope.board(p: QueensPlay, side: Double, celebrate: Double, demoCell: Int?) {
    val n = p.n
    val cell = side / n
    val (striped, bad) = p.conflicts()
    // Region fills.
    for (i in 0 until n * n) rect((i % n) * cell, (i / n) * cell, cell, cell, palette[p.colorOf[p.regions[i]] % palette.size])
    // Auto-check: red diagonal stripes over every clashing line / region / pair.
    for (i in striped) {
        val x0 = (i % n) * cell; val y0 = (i / n) * cell
        clipRect(x0.f, y0.f, (x0 + cell).f, (y0 + cell).f) {
            val stripes = Path()
            val step = cell / 4.2
            var x = x0 - cell
            while (x < x0 + cell) { stripes.m(x, y0 + cell); stripes.l(x + cell, y0); x += step }
            drawPath(stripes, CLASH.op(0.55), style = Stroke(max(1.5, cell * 0.07).f))
        }
    }
    // Thin lines inside regions, thick ink where regions meet.
    val thin = Path(); val thick = Path()
    for (r in 0 until n) for (c in 0 until n) {
        val i = r * n + c
        if (c < n - 1) {
            val target = if (p.regions[i] == p.regions[i + 1]) thin else thick
            target.m((c + 1) * cell, r * cell); target.l((c + 1) * cell, (r + 1) * cell)
        }
        if (r < n - 1) {
            val target = if (p.regions[i] == p.regions[i + n]) thin else thick
            target.m(c * cell, (r + 1) * cell); target.l((c + 1) * cell, (r + 1) * cell)
        }
    }
    drawPath(thin, INK.op(0.28), style = Stroke(max(0.8, cell * 0.018).f))
    val thickW = max(2.2, cell * 0.075)
    drawPath(thick, INK, style = Stroke(thickW.f, cap = StrokeCap.Square))
    rectStroke(thickW / 2, thickW / 2, side - thickW, side - thickW, INK, thickW)
    // Marks.
    for (i in 0 until n * n) {
        val mx = (i % n + 0.5) * cell; val my = (i / n + 0.5) * cell
        when (p.marks[i]) {
            1 -> {
                val d = cell * 0.13
                val x = Path().apply { m(mx - d, my - d); l(mx + d, my + d); m(mx + d, my - d); l(mx - d, my + d) }
                drawPath(x, INK.op(0.62), style = Stroke(max(1.2, cell * 0.045).f, cap = StrokeCap.Round))
            }
            2 -> {
                // Win wave: crowns pop row by row.
                var scale = 1.0
                if (celebrate >= 0) {
                    val t = celebrate * 1.6 - (i / n) * 0.09
                    scale = 1 + 0.32 * sin(min(max(t, 0.0), 1.0) * PI)
                }
                val w = cell * 0.6 * scale
                crown(mx - w / 2, my - w * 0.46, w, w * 0.86, if (i in bad) CLASH else INK)
            }
        }
    }
    // Demo: a ring on the cell being tapped (the finger is drawn on top in pixels).
    if (demoCell != null && demoCell < n * n) {
        val x0 = (demoCell % n) * cell + 2; val y0 = (demoCell / n) * cell + 2
        drawPath(Path().apply { addRoundRect(RoundRect(x0.f, y0.f, (x0 + cell - 4).f, (y0 + cell - 4).f, CornerRadius(4f))) },
            Color.White, style = Stroke(2.5f))
    }
}

