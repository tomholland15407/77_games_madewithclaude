package com.gogs.bananagame.games.pearlchain

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** Brain — Pearl Chain (was "Masyu"; iOS MasyuGame.swift): one closed loop through every pearl. */
object PearlChainGame {
    val definition = GameDefinition(
        id = "masyu",
        title = "Pearl Chain",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Tap between two cells to draw one closed loop through every pearl — it never crosses or branches.",
                "White pearls: the loop runs straight through but turns just before or after.",
                "Black pearls: the loop turns on them but runs straight one cell on both sides.",
                "Finish the loop before the clock runs out.",
            ),
            bulletsVI = listOf(
                "Chạm giữa hai ô để vẽ một vòng khép kín qua mọi hạt ngọc — không cắt nhau, không rẽ nhánh.",
                "Ngọc trắng: vòng đi thẳng qua nhưng phải rẽ ngay trước hoặc sau nó.",
                "Ngọc đen: vòng phải rẽ tại nó nhưng đi thẳng một ô ở cả hai bên.",
                "Hoàn thành vòng trước khi hết giờ.",
            ),
            liveDemo = true
        ),
        prefetch = { level -> BoardCache.prefetch(key(level)) { MasyuGen.generate(n(level), pearlTarget(level)) } },
        content = { level, onWin, onFail -> PearlChainView(level, onWin, onFail) }
    )

    fun key(level: Int) = BoardCache.key("masyu", level)
    fun n(level: Int) = listOf(5, 6, 6, 7, 7, 8, 8)[min(level, 7) - 1]
    fun pearlTarget(level: Int) = listOf(4, 5, 7, 8, 10, 12, 14)[min(level, 7) - 1]
    fun timeLimit(level: Int) = listOf(80.0, 85.0, 90.0, 95.0, 95.0, 90.0, 85.0)[min(level, 7) - 1]
}

data class MCell(val r: Int, val c: Int)

/** An undirected segment between adjacent cells, normalized so it hashes stably. */
data class MEdge private constructor(val a: MCell, val b: MCell) {
    val horizontal get() = a.r == b.r
    companion object {
        fun of(x: MCell, y: MCell): MEdge = if (x.r < y.r || (x.r == y.r && x.c <= y.c)) MEdge(x, y) else MEdge(y, x)
    }
}

class MasyuPuzzle(val n: Int, val whites: List<MCell>, val blacks: List<MCell>)

object MasyuGen {
    fun inBounds(c: MCell, n: Int) = c.r in 0 until n && c.c in 0 until n

    fun adjacency(links: Set<MEdge>): Map<MCell, List<MCell>> {
        val adj = HashMap<MCell, MutableList<MCell>>()
        for (e in links) {
            adj.getOrPut(e.a) { ArrayList() }.add(e.b)
            adj.getOrPut(e.b) { ArrayList() }.add(e.a)
        }
        return adj
    }

    fun isStraight(cell: MCell, nb: List<MCell>): Boolean {
        if (nb.size != 2) return false
        return (nb[0].r == cell.r && nb[1].r == cell.r) || (nb[0].c == cell.c && nb[1].c == cell.c)
    }

    fun turnAt(cell: MCell, adj: Map<MCell, List<MCell>>): Boolean {
        val nb = adj[cell] ?: return false
        return nb.size == 2 && !isStraight(cell, nb)
    }

    fun blackValid(cell: MCell, nbrs: List<MCell>, adj: Map<MCell, List<MCell>>): Boolean {
        for (nb in nbrs) {
            val beyond = MCell(nb.r + (nb.r - cell.r), nb.c + (nb.c - cell.c))
            val nn = adj[nb] ?: return false
            if (beyond !in nn) return false
        }
        return true
    }

    fun pearlSatisfied(p: MCell, isWhite: Boolean, adj: Map<MCell, List<MCell>>): Boolean {
        val nb = adj[p] ?: return false
        if (nb.size != 2) return false
        return if (isWhite) isStraight(p, nb) && nb.any { turnAt(it, adj) } else !isStraight(p, nb) && blackValid(p, nb, adj)
    }

    fun satisfiesAll(links: Set<MEdge>, whites: Collection<MCell>, blacks: Collection<MCell>): Boolean {
        if (links.isEmpty()) return false
        val adj = adjacency(links)
        if (adj.values.any { it.size != 2 }) return false
        if (whites.any { adj[it] == null } || blacks.any { adj[it] == null }) return false
        val start = adj.keys.first()
        var prev = start; var cur = adj[start]!!.first(); var visited = 1
        while (cur != start) {
            visited++
            val nb = adj[cur] ?: return false
            if (nb.size != 2) return false
            val next = if (nb[0] == prev) nb[1] else nb[0]
            prev = cur; cur = next
            if (visited > adj.size) break
        }
        if (visited != adj.size) return false
        if (whites.any { !pearlSatisfied(it, true, adj) }) return false
        if (blacks.any { !pearlSatisfied(it, false, adj) }) return false
        return true
    }

    fun growLoop(n: Int): Set<MEdge> {
        val links = LinkedHashSet<MEdge>()
        val inLoop = HashSet<MCell>()
        val sr = max(0, n / 2 - 1); val sc = max(0, n / 2 - 1)
        val c00 = MCell(sr, sc); val c01 = MCell(sr, sc + 1); val c10 = MCell(sr + 1, sc); val c11 = MCell(sr + 1, sc + 1)
        links.add(MEdge.of(c00, c01)); links.add(MEdge.of(c01, c11)); links.add(MEdge.of(c11, c10)); links.add(MEdge.of(c10, c00))
        inLoop.addAll(listOf(c00, c01, c10, c11))
        repeat(n * n * 6) {
            if (links.isEmpty()) return links
            val e = links.toList().pick()
            val a = e.a; val b = e.b
            val deltas = if (e.horizontal) listOf(-1 to 0, 1 to 0) else listOf(0 to -1, 0 to 1)
            for ((dr, dc) in deltas.shuffled()) {
                val a2 = MCell(a.r + dr, a.c + dc); val b2 = MCell(b.r + dr, b.c + dc)
                if (inBounds(a2, n) && inBounds(b2, n) && a2 !in inLoop && b2 !in inLoop) {
                    links.remove(e)
                    links.add(MEdge.of(a, a2)); links.add(MEdge.of(a2, b2)); links.add(MEdge.of(b2, b))
                    inLoop.add(a2); inLoop.add(b2)
                    break
                }
            }
        }
        return links
    }

    fun rectangleLoop(n: Int): Set<MEdge> {
        val links = HashSet<MEdge>()
        for (c in 0 until n - 1) { links.add(MEdge.of(MCell(0, c), MCell(0, c + 1))); links.add(MEdge.of(MCell(n - 1, c), MCell(n - 1, c + 1))) }
        for (r in 0 until n - 1) { links.add(MEdge.of(MCell(r, 0), MCell(r + 1, 0))); links.add(MEdge.of(MCell(r, n - 1), MCell(r + 1, n - 1))) }
        return links
    }

    fun pickPearls(adj: Map<MCell, List<MCell>>, target: Int): Pair<List<MCell>, List<MCell>> {
        val whiteCand = ArrayList<MCell>(); val blackCand = ArrayList<MCell>()
        for ((cell, nb) in adj) {
            if (nb.size != 2) continue
            if (isStraight(cell, nb)) { if (nb.any { turnAt(it, adj) }) whiteCand.add(cell) }
            else if (blackValid(cell, nb, adj)) blackCand.add(cell)
        }
        whiteCand.shuffle(); blackCand.shuffle()
        val whites = ArrayList<MCell>(); val blacks = ArrayList<MCell>()
        var wi = 0; var bi = 0
        while (whites.size + blacks.size < target) {
            val canB = bi < blackCand.size; val canW = wi < whiteCand.size
            if (!canB && !canW) break
            val pickBlack = canB && (!canW || blacks.size <= whites.size)
            if (pickBlack) blacks.add(blackCand[bi++]) else whites.add(whiteCand[wi++])
        }
        return whites to blacks
    }

    fun generate(n: Int, pearlTarget: Int): MasyuPuzzle {
        repeat(60) {
            val links = growLoop(n)
            val adj = adjacency(links)
            if (adj.size < 10) return@repeat
            val (w, b) = pickPearls(adj, pearlTarget)
            if (b.isEmpty() || w.isEmpty() || w.size + b.size < min(pearlTarget, 4)) return@repeat
            if (satisfiesAll(links, w, b)) return MasyuPuzzle(n, w, b)
        }
        val (w, b) = pickPearls(adjacency(rectangleLoop(n)), pearlTarget)
        return MasyuPuzzle(n, w, b)
    }

    fun perimeterEdges(n: Int): List<MEdge> {
        val e = ArrayList<MEdge>()
        for (c in 0 until n - 1) e.add(MEdge.of(MCell(0, c), MCell(0, c + 1)))
        for (r in 0 until n - 1) e.add(MEdge.of(MCell(r, n - 1), MCell(r + 1, n - 1)))
        for (c in n - 1 downTo 1) e.add(MEdge.of(MCell(n - 1, c), MCell(n - 1, c - 1)))
        for (r in n - 1 downTo 1) e.add(MEdge.of(MCell(r, 0), MCell(r - 1, 0)))
        return e
    }
}

@Composable
private fun PearlChainView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val timeLimit = PearlChainGame.timeLimit(level)
    var playing by remember { mutableStateOf(true) }
    var ready by remember { mutableStateOf(false) }
    var boardN by remember { mutableIntStateOf(0) }
    var whites by remember { mutableStateOf(setOf<MCell>()) }
    var blacks by remember { mutableStateOf(setOf<MCell>()) }
    var links by remember { mutableStateOf(setOf<MEdge>()) }
    var timeLeft by remember { mutableDoubleStateOf(timeLimit) }
    var demoEdge by remember { mutableStateOf<MEdge?>(null) }
    val handP = rememberHand()

    val adjNow = MasyuGen.adjacency(links)
    val pearlsLeft = whites.count { adjNow[it] == null } + blacks.count { adjNow[it] == null }

    fun isSolved() = MasyuGen.satisfiesAll(links, whites, blacks)
    fun win() { if (!playing) return; playing = false; onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (isActive) {
                val size = 5
                val (w, b) = MasyuGen.pickPearls(MasyuGen.adjacency(MasyuGen.rectangleLoop(size)), PearlChainGame.pearlTarget(level))
                boardN = size; whites = w.toSet(); blacks = b.toSet(); links = emptySet()
                ready = true; playing = true; timeLeft = timeLimit
                delay(700)
                for (e in MasyuGen.perimeterEdges(size)) {
                    demoEdge = e
                    links = links + e
                    delay(180)
                    if (isSolved()) break
                }
                demoEdge = null
                if (isSolved()) win()
                delay(1400)
            }
        } else {
            val size = PearlChainGame.n(level); val target = PearlChainGame.pearlTarget(level)
            val t0 = System.currentTimeMillis()
            val puzzle = BoardCache.take(PearlChainGame.key(level)) { MasyuGen.generate(size, target) }
            BoardCache.holdBrainstorm(t0, 0.7)
            boardN = puzzle.n; whites = puzzle.whites.toSet(); blacks = puzzle.blacks.toSet(); links = emptySet()
            ready = true; playing = true; timeLeft = timeLimit
            val start = nowSec()
            while (isActive && playing) {
                delay(50)
                timeLeft = max(0.0, timeLimit - (nowSec() - start))
                if (timeLeft <= 0) { fail(); break }
            }
        }
    }

    if (!ready) { BrainstormingView(rgb(0.2, 0.08, 0.14), rgb(0.08, 0.03, 0.06)); return }

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .background(Brush.verticalGradient(listOf(rgb(0.2, 0.08, 0.14), rgb(0.08, 0.03, 0.06))))
            .padding(vertical = if (isDemo) 8.dp else 14.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(if (isDemo) 6.dp else 12.dp)
    ) {
        Text(L("$pearlsLeft pearls to thread", "còn $pearlsLeft hạt ngọc"),
            style = ts(if (isDemo) 17.0 else 20.0, FontWeight.Black, if (pearlsLeft == 0) rgb(1.0, 0.84, 0.4) else Color.White))
        if (!isDemo) TimeBar(timeLeft / timeLimit, Modifier.fillMaxWidth().padding(horizontal = 50.dp).height(6.dp))
        Canvas(
            Modifier.fillMaxWidth().weight(1f).padding(horizontal = if (isDemo) 4.dp else 8.dp)
                .tapIn(boardN) { p, w, h ->
                    if (isDemo || !playing || boardN == 0) return@tapIn
                    val n = boardN
                    val cell = min(w, h) * 0.92 / n
                    val ox = (w - cell * n) / 2; val oy = (h - cell * n) / 2
                    var best: MEdge? = null
                    var bestD = cell * 0.5
                    for (r in 0 until n) for (c in 0 until n) {
                        if (c + 1 < n) {
                            val d = hypot(p.x - (ox + (c + 1) * cell), p.y - (oy + (r + 0.5) * cell))
                            if (d < bestD) { bestD = d; best = MEdge.of(MCell(r, c), MCell(r, c + 1)) }
                        }
                        if (r + 1 < n) {
                            val d = hypot(p.x - (ox + (c + 0.5) * cell), p.y - (oy + (r + 1) * cell))
                            if (d < bestD) { bestD = d; best = MEdge.of(MCell(r, c), MCell(r + 1, c)) }
                        }
                    }
                    val e = best ?: return@tapIn
                    links = if (e in links) links - e else links + e
                    SoundManager.tap(); Haptics.tap()
                    if (isSolved()) win()
                }
        ) {
            val n = boardN
            if (n == 0) return@Canvas
            val w = size.width.toDouble(); val h = size.height.toDouble()
            val cell = min(w, h) * 0.92 / n
            val ox = (w - cell * n) / 2; val oy = (h - cell * n) / 2
            jewelBox(n, cell, ox, oy)
            fun cx(c: Int) = ox + (c + 0.5) * cell
            fun cy(r: Int) = oy + (r + 0.5) * cell
            if (links.isNotEmpty()) {
                val line = Path()
                for (e in links) { line.m(cx(e.a.c), cy(e.a.r)); line.l(cx(e.b.c), cy(e.b.r)) }
                chain(line, cell)
            }
            for (pp in whites) pearl(cx(pp.c), cy(pp.r), cell * 0.3, false, MasyuGen.pearlSatisfied(pp, true, adjNow))
            for (pp in blacks) pearl(cx(pp.c), cy(pp.r), cell * 0.3, true, MasyuGen.pearlSatisfied(pp, false, adjNow))
            val de = demoEdge
            if (isDemo && de != null) {
                val mx = (cx(de.a.c) + cx(de.b.c)) / 2; val my = (cy(de.a.r) + cy(de.b.r)) / 2
                val hw = cell * 0.6
                hand(handP, mx - hw * 0.02, my + hw * 0.02, hw)
            }
        }
    }
}

private val GOLD = rgb(0.95, 0.76, 0.3)

private fun DrawScope.chain(path: Path, cell: Double) {
    val w = cell * 0.13
    drawPath(path, Color.Black.op(0.35), style = Stroke((w * 1.5).f, cap = StrokeCap.Round, join = StrokeJoin.Round))
    drawPath(path, rgb(0.62, 0.44, 0.1), style = Stroke((w * 1.15).f, cap = StrokeCap.Round, join = StrokeJoin.Round))
    drawPath(path, GOLD, style = Stroke(w.f, cap = StrokeCap.Round, join = StrokeJoin.Round))
    drawPath(path, rgb(0.62, 0.44, 0.1, 0.85), style = Stroke((w * 0.4).f, cap = StrokeCap.Butt, join = StrokeJoin.Round,
        pathEffect = PathEffect.dashPathEffect(floatArrayOf((w * 0.9).f, (w * 0.55).f))))
    drawPath(path, rgb(1.0, 0.96, 0.75, 0.8), style = Stroke(max(0.8, w * 0.18).f, cap = StrokeCap.Round, join = StrokeJoin.Round))
}

private fun DrawScope.pearl(px: Double, py: Double, r: Double, black: Boolean, clasped: Boolean) {
    oval(px - r * 0.9, py - r * 0.55, r * 2, r * 1.9, Color.Black.op(0.35))
    if (clasped) {
        val cr = r * 1.22
        drawCircle(lin(listOf(rgb(1.0, 0.94, 0.65), GOLD, rgb(0.6, 0.42, 0.08)), px - cr, py - cr, px + cr, py + cr), cr.f, off(px, py),
            style = Stroke(max(2.0, r * 0.26).f))
        for (k in 0 until 4) {
            val a = k * PI / 2 + PI / 4
            circle(px + cos(a) * cr, py + sin(a) * cr, r * 0.14, GOLD)
        }
    }
    if (black) {
        circle(px, py, r, radial(listOf(rgb(0.42, 0.44, 0.5), rgb(0.12, 0.13, 0.17), rgb(0.03, 0.03, 0.05)), px - r * 0.35, py - r * 0.4, r * 1.4))
        circle(px, py, r, lin(listOf(rgb(0.3, 0.9, 0.6, 0.22), Color.Transparent, rgb(0.7, 0.3, 0.9, 0.28)), px - r, py + r, px + r, py - r))
    } else {
        circle(px, py, r, radial(listOf(Color.White, rgb(0.97, 0.94, 0.9), rgb(0.8, 0.76, 0.78)), px - r * 0.35, py - r * 0.4, r * 1.4))
        circle(px, py, r, radial(listOf(rgb(1.0, 0.8, 0.85, 0.35), Color.Transparent), px + r * 0.4, py + r * 0.45, r * 0.9))
    }
    circleStroke(px, py, r, Color.Black.op(if (black) 0.6 else 0.25), max(0.8, r * 0.05))
    oval(px - r * 0.55, py - r * 0.6, r * 0.5, r * 0.32, Color.White.op(if (black) 0.7 else 0.95))
    oval(px + r * 0.25, py + r * 0.3, r * 0.22, r * 0.14, Color.White.op(0.35))
}

private fun DrawScope.jewelBox(n: Int, cell: Double, ox: Double, oy: Double) {
    val side = cell * n
    val rx = ox - cell * 0.18; val ry = oy - cell * 0.18; val rs = side + cell * 0.36
    rrect(rx, ry + cell * 0.08, rs, rs, cell * 0.3, Color.Black.op(0.5))
    rrect(rx, ry, rs, rs, cell * 0.3, lin(listOf(rgb(1.0, 0.9, 0.55), GOLD, rgb(0.55, 0.38, 0.08)), rx, ry, rx + rs, ry + rs))
    rrect(ox, oy, side, side, cell * 0.18, radial(listOf(rgb(0.2, 0.24, 0.5), rgb(0.09, 0.1, 0.26)), ox + side / 2, oy + side * 0.35, side * 0.8))
    val tray = Path().apply { addRoundRect(RoundRect(ox.f, oy.f, (ox + side).f, (oy + side).f, CornerRadius((cell * 0.18).f))) }
    clipPath(tray) {
        val st = Path()
        for (k in -n..(2 * n)) {
            val x0 = ox + (k + 0.5) * cell
            st.m(x0, oy - cell * 0.5); st.l(x0 + side + cell, oy + side + cell * 0.5)
            st.m(x0, oy - cell * 0.5); st.l(x0 - side - cell, oy + side + cell * 0.5)
        }
        drawPath(st, rgb(0.05, 0.06, 0.16, 0.7), style = Stroke(max(1.0, cell * 0.035).f))
        drawPath(st, rgb(0.45, 0.5, 0.8, 0.15), style = Stroke(max(0.6, cell * 0.015).f,
            pathEffect = PathEffect.dashPathEffect(floatArrayOf((cell * 0.08).f, (cell * 0.06).f))))
        for (r in 0 until n) for (c in 0 until n) {
            val px = ox + (c + 0.5) * cell; val py = oy + (r + 0.5) * cell
            val br = cell * 0.07
            circle(px, py, br * 1.8, radial(listOf(Color.Black.op(0.45), Color.Transparent), px, py, br * 1.8))
            circle(px, py, br, radial(listOf(rgb(0.4, 0.45, 0.75), rgb(0.12, 0.13, 0.32)), px - br * 0.3, py - br * 0.3, br * 1.3))
        }
    }
}
