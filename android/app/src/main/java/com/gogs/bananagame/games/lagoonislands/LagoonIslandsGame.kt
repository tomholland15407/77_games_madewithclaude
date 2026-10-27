package com.gogs.bananagame.games.lagoonislands

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
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
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** Brain — Lagoon Islands (was "Nurikabe"; iOS NurikabeGame.swift): flood the sea, keep the islands dry. */
object LagoonIslandsGame {
    val definition = GameDefinition(
        id = "nurikabe",
        title = "Lagoon Islands",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Tap a cell to cycle land → sea → dotted land → land.",
                "Each numbered cell is an island of exactly that many land cells; islands never touch.",
                "All sea joins into one body — and no 2×2 block of sea is allowed.",
                "Solve the whole grid before the clock runs out.",
            ),
            bulletsVI = listOf(
                "Chạm một ô để luân chuyển đất → biển → đất chấm → đất.",
                "Mỗi ô có số là một đảo gồm đúng bấy nhiêu ô đất; các đảo không chạm nhau.",
                "Toàn bộ biển nối thành một khối — và không được có khối biển 2×2.",
                "Giải toàn bộ lưới trước khi hết giờ.",
            ),
            liveDemo = true
        ),
        prefetch = { level -> BoardCache.prefetch(key(level)) { NKGen.generate(n(level), islands(level), maxSize(level)) } },
        content = { level, onWin, onFail -> LagoonIslandsView(level, onWin, onFail) }
    )

    fun key(level: Int) = BoardCache.key("nurikabe", level)
    fun n(level: Int) = listOf(5, 6, 6, 7, 7, 8, 8)[min(level, 7) - 1]
    fun islands(level: Int) = listOf(2, 3, 3, 4, 4, 5, 5)[min(level, 7) - 1]
    fun maxSize(level: Int) = listOf(3, 3, 4, 4, 5, 5, 6)[min(level, 7) - 1]
    fun timeLimit(level: Int) = listOf(80.0, 85.0, 90.0, 95.0, 95.0, 90.0, 85.0)[min(level, 7) - 1]
}

class NKPuzzle(val n: Int, val clues: Map<Int, Int>)

object NKGen {
    fun orth(cell: Int, n: Int): List<Int> {
        val r = cell / n; val c = cell % n
        val out = ArrayList<Int>(4)
        if (r > 0) out.add((r - 1) * n + c); if (r < n - 1) out.add((r + 1) * n + c)
        if (c > 0) out.add(r * n + c - 1); if (c < n - 1) out.add(r * n + c + 1)
        return out
    }

    fun hasIslandNeighbor(cell: Int, id: IntArray, n: Int) = orth(cell, n).any { id[it] != 0 }
    fun hasOtherIslandNeighbor(cell: Int, thisId: Int, id: IntArray, n: Int) = orth(cell, n).any { id[it] != 0 && id[it] != thisId }

    fun has2x2Water(id: IntArray, n: Int): Boolean {
        for (r in 0 until n - 1) for (c in 0 until n - 1) {
            val a = r * n + c
            if (id[a] == 0 && id[a + 1] == 0 && id[a + n] == 0 && id[a + n + 1] == 0) return true
        }
        return false
    }

    fun waterConnected(water: List<Int>, n: Int): Boolean {
        if (water.isEmpty()) return false
        val set = water.toHashSet()
        val seen = hashSetOf(water[0]); val stack = arrayListOf(water[0])
        while (stack.isNotEmpty()) {
            val cur = stack.removeAt(stack.size - 1)
            for (nb in orth(cur, n)) if (nb in set && seen.add(nb)) stack.add(nb)
        }
        return seen.size == set.size
    }

    private fun repairPools(id: IntArray, next: IntArray, n: Int): Boolean {
        var guard = 0
        while (true) {
            if (++guard > n * n * 4) return false
            var pool = -1
            loop@ for (r in 0 until n - 1) for (c in 0 until n - 1) {
                val a = r * n + c
                if (id[a] == 0 && id[a + 1] == 0 && id[a + n] == 0 && id[a + n + 1] == 0) { pool = a; break@loop }
            }
            if (pool < 0) return true
            val cand = listOf(pool, pool + 1, pool + n, pool + n + 1).shuffled().firstOrNull { !hasIslandNeighbor(it, id, n) } ?: return false
            id[cand] = next[0]; next[0]++
        }
    }

    fun generate(n: Int, islandCount: Int, maxSize: Int): NKPuzzle {
        repeat(2500) {
            val id = IntArray(n * n)
            val next = intArrayOf(1)
            var ok = true
            for (k in 0 until islandCount) {
                val seeds = (0 until n * n).filter { id[it] == 0 && !hasIslandNeighbor(it, id, n) }
                if (seeds.isEmpty()) { ok = false; break }
                val seed = seeds.pick()
                val thisId = next[0]; next[0]++
                id[seed] = thisId
                val members = arrayListOf(seed)
                val size = rndInt(1..maxSize)
                var guard = 0
                while (members.size < size && guard < 200) {
                    guard++
                    val cands = ArrayList<Int>()
                    for (m in members) for (nb in orth(m, n)) if (id[nb] == 0 && !hasOtherIslandNeighbor(nb, thisId, id, n)) cands.add(nb)
                    if (cands.isEmpty()) break
                    val add = cands.pick()
                    id[add] = thisId; members.add(add)
                }
            }
            if (!ok) return@repeat
            if (!repairPools(id, next, n)) return@repeat
            val water = (0 until n * n).filter { id[it] == 0 }
            if (water.isEmpty() || !waterConnected(water, n) || has2x2Water(id, n)) return@repeat
            val byId = HashMap<Int, MutableList<Int>>()
            for (i in 0 until n * n) if (id[i] != 0) byId.getOrPut(id[i]) { ArrayList() }.add(i)
            if (byId.isEmpty()) return@repeat
            val clues = HashMap<Int, Int>()
            for ((_, cells) in byId) clues[cells.pick()] = cells.size
            return NKPuzzle(n, clues)
        }
        return fallback(n)
    }

    fun fallback(n: Int): NKPuzzle {
        val clues = HashMap<Int, Int>()
        var r = 1
        while (r < n) { var c = 1; while (c < n) { clues[r * n + c] = 1; c += 2 }; r += 2 }
        return NKPuzzle(n, clues)
    }

    /** mark: 0 land, 1 sea, 2 dotted land. */
    fun isSolved(mark: IntArray, clues: Map<Int, Int>, n: Int): Boolean {
        val total = n * n
        val sea = (0 until total).filter { mark[it] == 1 }
        val land = (0 until total).filter { mark[it] != 1 }
        if (sea.isEmpty()) return false
        val seaGrid = IntArray(total) { 1 }
        for (s in sea) seaGrid[s] = 0
        if (has2x2Water(seaGrid, n) || !waterConnected(sea, n)) return false
        val landSet = land.toHashSet()
        val seen = HashSet<Int>()
        for (cell in land) {
            if (cell in seen) continue
            val comp = ArrayList<Int>(); val stack = arrayListOf(cell); seen.add(cell)
            while (stack.isNotEmpty()) {
                val cur = stack.removeAt(stack.size - 1); comp.add(cur)
                for (nb in orth(cur, n)) if (nb in landSet && seen.add(nb)) stack.add(nb)
            }
            val clueCells = comp.filter { clues[it] != null }
            if (clueCells.size != 1 || comp.size != clues[clueCells[0]]) return false
        }
        return true
    }
}

private val DEMO_CLUES = mapOf(1 to 3, 8 to 3, 21 to 1)
private val DEMO_MOVES = listOf(16 to 1, 20 to 1, 22 to 1, 6 to 2, 11 to 2, 0 to 1, 2 to 1, 5 to 1, 7 to 1, 10 to 1, 12 to 1, 15 to 1, 17 to 1,
    13 to 2, 18 to 2, 3 to 1, 4 to 1, 9 to 1, 14 to 1, 19 to 1, 23 to 1, 24 to 1)

@Composable
private fun LagoonIslandsView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val timeLimit = LagoonIslandsGame.timeLimit(level)
    var playing by remember { mutableStateOf(true) }
    var ready by remember { mutableStateOf(false) }
    var boardN by remember { mutableIntStateOf(0) }
    var clues by remember { mutableStateOf(mapOf<Int, Int>()) }
    var mark by remember { mutableStateOf(IntArray(0)) }
    var timeLeft by remember { mutableDoubleStateOf(timeLimit) }
    var demoTap by remember { mutableStateOf<Int?>(null) }
    val tm = rememberTextMeasurer()
    val handP = rememberHand()
    val seaNeeded = boardN * boardN - clues.values.sum()
    val seaCount = mark.count { it == 1 }

    fun win() { if (!playing) return; playing = false; onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }
    fun tap(i: Int) {
        if (!playing || clues[i] != null || i >= mark.size) return
        mark = mark.copyOf().also { it[i] = (it[i] + 1) % 3 }
        SoundManager.tap(); Haptics.tap()
        if (mark.count { it == 1 } == boardN * boardN - clues.values.sum() && NKGen.isSolved(mark, clues, boardN)) win()
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (isActive) {
                boardN = 5; clues = DEMO_CLUES; mark = IntArray(25); demoTap = null
                timeLeft = timeLimit; playing = true; ready = true
                delay(600)
                for ((idx, taps) in DEMO_MOVES) {
                    demoTap = idx
                    repeat(taps) { delay(130); tap(idx) }
                    delay(120)
                }
                demoTap = null
                delay(1300)
            }
        } else {
            val n = LagoonIslandsGame.n(level); val ic = LagoonIslandsGame.islands(level); val ms = LagoonIslandsGame.maxSize(level)
            val t0 = System.currentTimeMillis()
            val pz = BoardCache.take(LagoonIslandsGame.key(level)) { NKGen.generate(n, ic, ms) }
            BoardCache.holdBrainstorm(t0, 0.7)
            boardN = pz.n; clues = pz.clues; mark = IntArray(pz.n * pz.n)
            ready = true; playing = true; timeLeft = timeLimit
            val start = nowSec()
            while (isActive && playing) {
                delay(50)
                timeLeft = max(0.0, timeLimit - (nowSec() - start))
                if (timeLeft <= 0) { fail(); break }
            }
        }
    }

    if (!ready) { BrainstormingView(rgb(0.05, 0.42, 0.62), rgb(0.02, 0.2, 0.38)); return }

    Box(Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))) {
        Canvas(Modifier.fillMaxSize()) { ocean() }
        Column(
            Modifier.fillMaxSize().padding(vertical = if (isDemo) 8.dp else 14.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(if (isDemo) 6.dp else 12.dp)
        ) {
            Text(L("$seaCount/$seaNeeded sea", "biển $seaCount/$seaNeeded"), style = TextStyle(fontSize = (if (isDemo) 15 else 20).sp,
                fontWeight = FontWeight.Black, color = if (seaCount == seaNeeded) rgb(1.0, 0.9, 0.5) else Color.White,
                shadow = Shadow(Color.Black.op(0.35), Offset(0f, 4f), 0f)))
            if (!isDemo) TimeBar(timeLeft / timeLimit, Modifier.fillMaxWidth().padding(horizontal = 50.dp).height(6.dp), track = Color.Black.op(0.25))
            Canvas(Modifier.fillMaxWidth().weight(1f).padding(horizontal = if (isDemo) 4.dp else 8.dp).tapIn(boardN) { p, w, h ->
                if (isDemo || boardN == 0) return@tapIn
                val cell = min(w, h) * 0.95 / boardN
                val ox = (w - cell * boardN) / 2; val oy = (h - cell * boardN) / 2
                val c = floor((p.x - ox) / cell).toInt(); val r = floor((p.y - oy) / cell).toInt()
                if (r in 0 until boardN && c in 0 until boardN) tap(r * boardN + c)
            }) {
                drawIslands(tm, boardN, mark, clues, demoTap)
                demoTap?.let { d ->
                    val n = boardN
                    val w = size.width.toDouble(); val h = size.height.toDouble()
                    val cell = min(w, h) * 0.95 / n
                    val ox = (w - cell * n) / 2; val oy = (h - cell * n) / 2
                    val x = ox + (d % n) * cell; val y = oy + (d / n) * cell
                    hand(handP, x + cell / 2, y + cell / 2 + cell * 0.05, cell * 0.55)
                }
            }
        }
    }
}

private fun c(r: Double, g: Double, b: Double) = rgb(r, g, b)

private fun DrawScope.drawIslands(tm: TextMeasurer, n: Int, mark: IntArray, clues: Map<Int, Int>, demoTap: Int?) {
    if (n <= 0 || mark.size != n * n) return
    val w = size.width.toDouble(); val h = size.height.toDouble(); val u = density.toDouble()
    val cell = min(w, h) * 0.95 / n
    val ox = (w - cell * n) / 2; val oy = (h - cell * n) / 2
    val bs = cell * n
    fun land(r: Int, c: Int) = if (r < 0 || r >= n || c < 0 || c >= n) true else mark[r * n + c] != 1
    sea(ox, oy, bs, cell)
    fun shape(i: Int, grow: Double, p: Path) {
        val r = i / n; val c = i % n
        val x = ox + c * cell - grow; val y = oy + r * cell - grow; val s = cell + 2 * grow
        val k = (cell * 0.42).f
        val tl = !land(r - 1, c) && !land(r, c - 1); val tr = !land(r - 1, c) && !land(r, c + 1)
        val bl = !land(r + 1, c) && !land(r, c - 1); val br = !land(r + 1, c) && !land(r, c + 1)
        p.addRoundRect(RoundRect(x.f, y.f, (x + s).f, (y + s).f, CornerRadius(if (tl) k else 0f), CornerRadius(if (tr) k else 0f),
            CornerRadius(if (br) k else 0f), CornerRadius(if (bl) k else 0f)))
    }
    val shallows = Path(); val sand = Path()
    for (i in 0 until n * n) if (mark[i] != 1) { shape(i, cell * 0.09, shallows); shape(i, 0.3, sand) }
    drawPath(shallows, c(0.55, 0.92, 0.9).op(0.75))
    drawPath(sand, lin(listOf(c(0.98, 0.9, 0.68), c(0.92, 0.8, 0.55)), ox, oy, ox + bs, oy + bs))
    clipPath(sand) {
        for (k in 1 until n) {
            line(ox + k * cell, oy, ox + k * cell, oy + bs, c(0.7, 0.56, 0.34).op(0.45), u, androidx.compose.ui.graphics.StrokeCap.Butt)
            line(ox, oy + k * cell, ox + bs, oy + k * cell, c(0.7, 0.56, 0.34).op(0.45), u, androidx.compose.ui.graphics.StrokeCap.Butt)
        }
    }
    for (i in 0 until n * n) {
        val x = ox + (i % n) * cell; val y = oy + (i / n) * cell
        val v = clues[i]
        if (v != null) clue(tm, x, y, cell, v) else if (mark[i] == 2) shell(x + cell / 2, y + cell / 2, cell * 0.36)
    }
    rrectStroke(ox - 2 * u, oy - 2 * u, bs + 4 * u, bs + 4 * u, 10 * u, Color.White.op(0.35), 2 * u)
    if (demoTap != null && demoTap < n * n) {
        val x = ox + (demoTap % n) * cell + 2 * u; val y = oy + (demoTap / n) * cell + 2 * u
        rrectStroke(x, y, cell - 4 * u, cell - 4 * u, cell * 0.14, Color.White, 3 * u)
    }
}

private fun DrawScope.sea(x: Double, y: Double, s: Double, cell: Double) {
    val u = density.toDouble()
    rrect(x, y, s, s, 8 * u, lin(listOf(c(0.12, 0.72, 0.8), c(0.05, 0.5, 0.7)), x, y, x + s, y + s))
    val clip = Path().apply { addRoundRect(RoundRect(x.f, y.f, (x + s).f, (y + s).f, CornerRadius((8 * u).f))) }
    clipPath(clip) {
        var yy = y + cell * 0.3; var row = 0
        while (yy < y + s) {
            var xx = x + (row % 2) * cell * 0.5
            while (xx < x + s) {
                val wv = Path(); wv.m(xx, yy); wv.q(xx + cell * 0.11, yy - cell * 0.08, xx + cell * 0.22, yy)
                strokePath(wv, Color.White.op(0.28), max(1.0, cell * 0.03))
                xx += cell
            }
            yy += cell * 0.5; row++
        }
    }
}

private fun DrawScope.clue(tm: TextMeasurer, x: Double, y: Double, s: Double, number: Int) {
    val bx = x + s * 0.26; val by = y + s * 0.72
    val tx = x + s * 0.34; val ty = y + s * 0.24
    val trunk = Path(); trunk.m(bx, by); trunk.q(x + s * 0.2, y + s * 0.45, tx, ty)
    strokePath(trunk, c(0.55, 0.36, 0.18), s * 0.06)
    for (a in listOf(-150.0, -110.0, -70.0, -30.0, 10.0)) {
        val rad = a * PI / 180
        val ex = tx + cos(rad) * s * 0.24; val ey = ty + sin(rad) * s * 0.16 + s * 0.06
        val f = Path(); f.m(tx, ty); f.q((tx + ex) / 2, min(ty, ey) - s * 0.06, ex, ey)
        strokePath(f, c(0.18, 0.6, 0.24), s * 0.07)
    }
    val px = x + s / 2 + s * 0.1; val py = y + s / 2 + s * 0.04
    for (k in 0 until 8) {
        val a = k * PI / 4
        text(tm, "$number", px + cos(a) * s * 0.035, py + sin(a) * s * 0.035, s * 0.5, Color.White, FontWeight.Black)
    }
    text(tm, "$number", px, py, s * 0.5, c(0.42, 0.24, 0.1), FontWeight.Black)
}

private fun DrawScope.shell(px: Double, py: Double, s: Double) {
    val fan = Path(); fan.m(px, py + s * 0.45); fan.l(px - s * 0.5, py - s * 0.05); fan.q(px, py - s * 0.75, px + s * 0.5, py - s * 0.05); fan.close()
    drawPath(fan, vgrad(listOf(c(1.0, 0.8, 0.78), c(0.95, 0.55, 0.55)), py - s * 0.4, py + s * 0.45))
    for (k in -2..2) line(px, py + s * 0.42, px + k * s * 0.18, py - s * 0.3 + abs(k.toDouble()) * s * 0.08, c(0.8, 0.4, 0.4), max(0.8, s * 0.05), androidx.compose.ui.graphics.StrokeCap.Butt)
    strokePath(fan, c(0.7, 0.32, 0.32), max(0.8, s * 0.05))
}

private fun DrawScope.ocean() {
    val W = size.width.toDouble(); val H = size.height.toDouble(); val u = density.toDouble()
    rect(0.0, 0.0, W, H, vgrad(listOf(c(0.06, 0.46, 0.66), c(0.02, 0.2, 0.4)), 0.0, H))
    for (k in 0 until 40) {
        val fx = abs((sin(k * 12.9898) * 43758.5453) % 1.0)
        val fy = abs((sin(k * 78.233) * 24634.6345) % 1.0)
        val px = fx * W; val py = fy * H
        val wv = Path(); wv.m(px, py); wv.q(px + 8 * u, py - 5 * u, px + 16 * u, py)
        strokePath(wv, Color.White.op(0.18), 1.5 * u)
    }
}
