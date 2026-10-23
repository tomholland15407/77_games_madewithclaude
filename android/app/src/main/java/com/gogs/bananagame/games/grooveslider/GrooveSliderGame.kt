package com.gogs.bananagame.games.grooveslider

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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.vector.VectorPainter
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/** Brain — Groove Slider (was "Roll the Ball"; iOS RollTheBallGame.swift): slide pipe tiles into one track. */
object GrooveSliderGame {
    val definition = GameDefinition(
        id = "roll-the-ball",
        title = "Groove Slider",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Tap a pipe tile next to the empty space to slide it into the gap.",
                "Rearrange the tiles into one unbroken track from the ball to the goal.",
                "Connect them and the ball rolls home; the ball and goal tiles can't move.",
                "Run out of time and you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Chạm một ô ống cạnh ô trống để trượt nó vào khe.",
                "Sắp lại các ô thành một đường ống liền mạch từ quả bóng đến đích.",
                "Nối được thì bóng lăn về; ô bóng và ô đích không di chuyển được.",
                "Hết giờ sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        prefetch = { level -> BoardCache.prefetch(key(level)) { RollGen.makePuzzle(gridN(level), blockers(level), level) } },
        content = { level, onWin, onFail -> GrooveSliderView(level, onWin, onFail) }
    )

    fun key(level: Int) = BoardCache.key("roll-the-ball", level)
    fun gridN(level: Int) = listOf(3, 3, 4, 4, 5, 5, 5)[min(level, 7) - 1]
    fun blockers(level: Int) = listOf(0, 0, 0, 1, 1, 2, 3)[min(level, 7) - 1]
    fun timeLimit(level: Int) = listOf(45.0, 55.0, 70.0, 85.0, 100.0, 110.0, 120.0)[min(level, 7) - 1]
}

data class RCell(val r: Int, val c: Int)
enum class RKind { PIPE, SOURCE, GOAL, BLOCKER }
data class RTile(val openings: Int, val fixed: Boolean, val kind: RKind)
class RollPuzzle(val n: Int, val board: List<List<RTile?>>, val source: RCell, val goal: RCell)

object RollGen {
    val dirs = listOf(Triple(1, -1, 0), Triple(2, 0, 1), Triple(4, 1, 0), Triple(8, 0, -1))
    fun opposite(bit: Int) = when (bit) { 1 -> 4; 4 -> 1; 2 -> 8; else -> 2 }

    fun connected(board: List<List<RTile?>>, n: Int, source: RCell): Set<RCell> {
        if (n <= 0 || source.r >= board.size || board[source.r][source.c] == null) return emptySet()
        val seen = hashSetOf(source); val stack = arrayListOf(source)
        while (stack.isNotEmpty()) {
            val cur = stack.removeAt(stack.size - 1)
            val t = board[cur.r][cur.c] ?: continue
            for ((bit, dr, dc) in dirs) {
                if (t.openings and bit == 0) continue
                val nr = cur.r + dr; val nc = cur.c + dc
                if (nr !in 0 until n || nc !in 0 until n) continue
                val nt = board[nr][nc] ?: continue
                if (nt.openings and opposite(bit) == 0) continue
                val nb = RCell(nr, nc)
                if (seen.add(nb)) stack.add(nb)
            }
        }
        return seen
    }

    fun orderedPath(board: List<List<RTile?>>, n: Int, source: RCell, goal: RCell): List<RCell> {
        if (n <= 0 || board[source.r][source.c] == null) return emptyList()
        val parent = HashMap<RCell, RCell>()
        val seen = hashSetOf(source); val queue = ArrayDeque<RCell>(); queue.add(source)
        while (queue.isNotEmpty()) {
            val cur = queue.removeFirst()
            if (cur == goal) break
            val t = board[cur.r][cur.c] ?: continue
            for ((bit, dr, dc) in dirs) {
                if (t.openings and bit == 0) continue
                val nr = cur.r + dr; val nc = cur.c + dc
                if (nr !in 0 until n || nc !in 0 until n) continue
                val nt = board[nr][nc] ?: continue
                val nb = RCell(nr, nc)
                if (nt.openings and opposite(bit) == 0 || nb in seen) continue
                seen.add(nb); parent[nb] = cur; queue.add(nb)
            }
        }
        if (goal !in seen) return emptyList()
        val path = arrayListOf(goal); var cur = goal
        while (cur != source) { cur = parent[cur] ?: return emptyList(); path.add(cur) }
        return path.reversed()
    }

    fun makePuzzle(n: Int, blockers: Int, level: Int): RollPuzzle {
        repeat(80) {
            val solved = buildSolved(n, blockers) ?: return@repeat
            val s = scramble(solved, n * n * 4 + level * 10)
            if (s.goal !in connected(s.board, n, s.source)) return s
        }
        return buildSolved(n, 0) ?: trivial(n)
    }

    private fun dirBit(a: RCell, b: RCell) = when { b.r == a.r - 1 -> 1; b.r == a.r + 1 -> 4; b.c == a.c + 1 -> 2; else -> 8 }

    fun buildSolved(n: Int, blockers: Int): RollPuzzle? {
        val all = (0 until n * n).map { RCell(it / n, it % n) }
        val source = all.pick()
        var goal = all.pick(); var g = 0
        while (goal == source && g < 50) { goal = all.pick(); g++ }
        if (goal == source) return null
        val path = findPath(source, goal, n) ?: return null
        if (n * n - path.size < blockers + 1) return null
        val board = MutableList(n) { MutableList<RTile?>(n) { null } }
        path.forEachIndexed { i, cell ->
            var o = 0
            if (i > 0) o = o or dirBit(cell, path[i - 1])
            if (i < path.size - 1) o = o or dirBit(cell, path[i + 1])
            val kind = if (i == 0) RKind.SOURCE else if (i == path.size - 1) RKind.GOAL else RKind.PIPE
            board[cell.r][cell.c] = RTile(o, kind != RKind.PIPE, kind)
        }
        val nonPath = all.filter { board[it.r][it.c] == null }.shuffled().toMutableList()
        repeat(blockers) { val b = nonPath.removeAt(nonPath.size - 1); board[b.r][b.c] = RTile(0, true, RKind.BLOCKER) }
        nonPath.removeAt(nonPath.size - 1)   // the gap
        val decoys = listOf(5, 10, 3, 6, 12, 9)
        for (cell in nonPath) board[cell.r][cell.c] = RTile(decoys.pick(), false, RKind.PIPE)
        return RollPuzzle(n, board, source, goal)
    }

    private fun findPath(source: RCell, goal: RCell, n: Int): List<RCell>? {
        val visited = hashSetOf(source); val path = arrayListOf(source)
        fun dfs(cur: RCell): Boolean {
            if (cur == goal) return true
            for ((_, dr, dc) in dirs.shuffled()) {
                val nr = cur.r + dr; val nc = cur.c + dc
                if (nr !in 0 until n || nc !in 0 until n) continue
                val nb = RCell(nr, nc)
                if (nb in visited) continue
                visited.add(nb); path.add(nb)
                if (dfs(nb)) return true
                path.removeAt(path.size - 1); visited.remove(nb)
            }
            return false
        }
        return if (dfs(source)) path.toList() else null
    }

    fun scramble(p: RollPuzzle, moves: Int): RollPuzzle {
        val n = p.n
        val board = p.board.map { it.toMutableList() }.toMutableList()
        var gap = RCell(0, 0)
        for (r in 0 until n) for (c in 0 until n) if (board[r][c] == null) gap = RCell(r, c)
        var lastMoved: RCell? = null
        repeat(moves) {
            var cands = ArrayList<RCell>()
            for ((_, dr, dc) in dirs) {
                val nr = gap.r + dr; val nc = gap.c + dc
                if (nr !in 0 until n || nc !in 0 until n) continue
                val t = board[nr][nc] ?: continue
                val cell = RCell(nr, nc)
                if (!t.fixed && cell != lastMoved) cands.add(cell)
            }
            if (cands.isEmpty()) for ((_, dr, dc) in dirs) {
                val nr = gap.r + dr; val nc = gap.c + dc
                if (nr !in 0 until n || nc !in 0 until n) continue
                val t = board[nr][nc] ?: continue
                if (!t.fixed) cands.add(RCell(nr, nc))
            }
            if (cands.isEmpty()) return@repeat
            val pick = cands.pick()
            board[gap.r][gap.c] = board[pick.r][pick.c]; board[pick.r][pick.c] = null
            lastMoved = gap; gap = pick
        }
        return RollPuzzle(n, board, p.source, p.goal)
    }

    fun trivial(n0: Int): RollPuzzle {
        val n = max(n0, 3)
        val board = MutableList(n) { MutableList<RTile?>(n) { null } }
        board[0][0] = RTile(2, true, RKind.SOURCE); board[0][1] = RTile(10, false, RKind.PIPE); board[0][2] = RTile(8, true, RKind.GOAL)
        return RollPuzzle(n, board, RCell(0, 0), RCell(0, 2))
    }
}

private val DEMO_SCRAMBLE = listOf(RCell(1, 1), RCell(1, 2), RCell(0, 2), RCell(0, 1), RCell(1, 1))
private val DEMO_SOLUTION = listOf(RCell(0, 1), RCell(0, 2), RCell(1, 2), RCell(1, 1), RCell(2, 1))

@Composable
private fun GrooveSliderView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val timeLimit = GrooveSliderGame.timeLimit(level)
    var playing by remember { mutableStateOf(true) }
    var ready by remember { mutableStateOf(false) }
    var n by remember { mutableIntStateOf(0) }
    var board by remember { mutableStateOf(listOf<List<RTile?>>()) }
    var source by remember { mutableStateOf(RCell(0, 0)) }
    var goal by remember { mutableStateOf(RCell(0, 0)) }
    var gap by remember { mutableStateOf(RCell(0, 0)) }
    var timeLeft by remember { mutableDoubleStateOf(timeLimit) }
    var flowPath by remember { mutableStateOf(listOf<RCell>()) }
    var flowIndex by remember { mutableDoubleStateOf(0.0) }
    var demoTap by remember { mutableStateOf<RCell?>(null) }
    var moves by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    val handP = rememberHand()

    fun adjacent(c: RCell) = (abs(c.r - gap.r) == 1 && c.c == gap.c) || (abs(c.c - gap.c) == 1 && c.r == gap.r)
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }

    fun rollBall() {
        if (!playing) return
        val path = RollGen.orderedPath(board, n, source, goal)
        if (path.size <= 1) { playing = false; onWin(); return }
        playing = false
        flowPath = path; flowIndex = 0.0
        SoundManager.tap()
        scope.launch {
            val total = 0.75
            val start = nowSec()
            while (true) {
                val e = nowSec() - start
                if (e >= total) break
                flowIndex = e / total * (path.size - 1)
                delay(16)
            }
            flowIndex = (path.size - 1).toDouble()
            Haptics.success()
            delay(120)
            onWin()
        }
    }

    fun slide(c: RCell) {
        if (!playing || !adjacent(c)) return
        val tile = board[c.r][c.c] ?: return
        if (tile.fixed) return
        board = board.mapIndexed { r, row -> row.mapIndexed { cc, t -> if (r == gap.r && cc == gap.c) tile else if (r == c.r && cc == c.c) null else t } }
        gap = c
        moves += 1
        SoundManager.tap(); Haptics.tap()
        if (goal in RollGen.connected(board, n, source)) rollBall()
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (isActive) {
                fun pipe(m: Int) = RTile(m, false, RKind.PIPE)
                val b = mutableListOf(
                    mutableListOf<RTile?>(RTile(4, true, RKind.SOURCE), pipe(5), pipe(6)),
                    mutableListOf<RTile?>(pipe(3), pipe(10), pipe(12)),
                    mutableListOf<RTile?>(pipe(9), null, RTile(1, true, RKind.GOAL)),
                )
                var g = RCell(2, 1)
                for (t in DEMO_SCRAMBLE) { b[g.r][g.c] = b[t.r][t.c]; b[t.r][t.c] = null; g = t }
                n = 3; board = b; gap = g; source = RCell(0, 0); goal = RCell(2, 2)
                flowPath = emptyList(); flowIndex = 0.0; demoTap = null; moves = 0
                timeLeft = timeLimit; playing = true; ready = true
                delay(700)
                for (cell in DEMO_SOLUTION) {
                    demoTap = cell; delay(350)
                    slide(cell); delay(200)
                    demoTap = null; delay(300)
                }
                delay(2200)
            }
        } else {
            val g = GrooveSliderGame.gridN(level); val bl = GrooveSliderGame.blockers(level)
            val t0 = System.currentTimeMillis()
            val p = BoardCache.take(GrooveSliderGame.key(level)) { RollGen.makePuzzle(g, bl, level) }
            BoardCache.holdBrainstorm(t0, 0.7)
            n = p.n; board = p.board; source = p.source; goal = p.goal
            for (r in 0 until n) for (c in 0 until n) if (p.board[r][c] == null) gap = RCell(r, c)
            moves = 0; ready = true; playing = true; timeLeft = timeLimit
            val start = nowSec()
            while (isActive && playing) {
                delay(50)
                timeLeft = max(0.0, timeLimit - (nowSec() - start))
                if (timeLeft <= 0) { fail(); break }
            }
        }
    }

    if (!ready) { BrainstormingView(rgb(0.42, 0.26, 0.14), rgb(0.2, 0.11, 0.05)); return }

    val conn = RollGen.connected(board, n, source)
    Box(Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))) {
        Canvas(Modifier.fillMaxSize()) { backdrop() }
        Column(
            Modifier.fillMaxSize().padding(top = if (isDemo) 8.dp else 12.dp, bottom = if (isDemo) 8.dp else 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(if (isDemo) 6.dp else 10.dp)
        ) {
            Row(
                Modifier.background(Brush.verticalGradient(listOf(RollArt.woodDark.lit(0.12), RollArt.woodDark)), RoundedCornerShape(10.dp))
                    .border(1.5.dp, Color.Black.op(0.45), RoundedCornerShape(10.dp))
                    .padding(horizontal = 18.dp, vertical = if (isDemo) 3.dp else 6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(L("MOVES", "BƯỚC"), style = ts(if (isDemo) 12.0 else 15.0, FontWeight.ExtraBold, rgb(1.0, 0.88, 0.62, 0.8)))
                Spacer(Modifier.width(8.dp))
                Text("$moves", style = ts(if (isDemo) 18.0 else 24.0, FontWeight.Black, rgb(1.0, 0.93, 0.75)))
            }
            if (!isDemo) TimeBar(timeLeft / timeLimit, Modifier.fillMaxWidth().padding(horizontal = 60.dp).height(5.dp), track = Color.Black.op(0.35))
            Canvas(Modifier.fillMaxWidth().weight(1f).tapIn(n) { p, w, h ->
                if (isDemo || n == 0) return@tapIn
                val cell = min(w * 0.92 / n, h * 0.92 / n)
                val ox = (w - cell * n) / 2; val oy = (h - cell * n) / 2
                val c = floor((p.x - ox) / cell).toInt(); val r = floor((p.y - oy) / cell).toInt()
                if (r in 0 until n && c in 0 until n) slide(RCell(r, c))
            }) {
                if (n == 0 || board.size != n) return@Canvas
                val w = size.width.toDouble(); val h = size.height.toDouble()
                val cell = min(w * 0.92 / n, h * 0.92 / n)
                val ox = (w - cell * n) / 2; val oy = (h - cell * n) / 2
                RollArt.frame(this, ox, oy, cell * n, cell)
                for (r in 0 until n) for (c in 0 until n) {
                    val tile = board[r][c] ?: continue
                    RollArt.tile(this, ox + c * cell, oy + r * cell, cell, tile, RCell(r, c) in conn, tile.kind == RKind.SOURCE && flowPath.size < 2, r * 7 + c * 13)
                }
                if (flowPath.size > 1) {
                    val i0 = min(floor(flowIndex).toInt(), flowPath.size - 1)
                    val i1 = min(i0 + 1, flowPath.size - 1)
                    val fr = flowIndex - i0
                    val ax = ox + (flowPath[i0].c + 0.5) * cell; val ay = oy + (flowPath[i0].r + 0.5) * cell
                    val bx = ox + (flowPath[i1].c + 0.5) * cell; val by = oy + (flowPath[i1].r + 0.5) * cell
                    RollArt.ball(this, ax + (bx - ax) * fr, ay + (by - ay) * fr, cell * 0.2)
                }
                for (r in 0 until n) for (c in 0 until n) {
                    val cc = RCell(r, c)
                    val x = ox + c * cell; val y = oy + r * cell
                    if (adjacent(cc) && board[r][c]?.fixed == false) rrectStroke(x + cell * 0.05, y + cell * 0.05, cell * 0.9, cell * 0.9, cell * 0.1, Color.White.op(0.55), 2.0 * density)
                    if (demoTap == cc) demoPress(handP, x, y, cell)
                }
            }
        }
    }
}

private fun DrawScope.demoPress(handP: VectorPainter, x: Double, y: Double, cell: Double) {
    val i = cell * 0.05 + cell * 0.045
    rrect(x + i, y + i, cell - 2 * i, cell - 2 * i, cell * 0.1, Color.White.op(0.18))
    rrectStroke(x + i, y + i, cell - 2 * i, cell - 2 * i, cell * 0.1, Color.White, 3.0 * density)
    val hs = cell * 0.36 * 1.3
    hand(handP, x + cell / 2 + cell * 0.22 - hs * 0.3, y + cell / 2 + cell * 0.26 - hs * 0.2, hs)
}

private object RollArt {
    val wood = rgb(0.86, 0.66, 0.42)
    val woodDark = rgb(0.36, 0.21, 0.1)
    val groove = rgb(0.4, 0.23, 0.1)
    val lit = rgb(1.0, 0.8, 0.3)

    fun frame(d: DrawScope, x: Double, y: Double, s: Double, cell: Double) = with(d) {
        val e = cell * 0.14
        rrect(x - e, y - e + cell * 0.06, s + 2 * e, s + 2 * e, cell * 0.2, Color.Black.op(0.45))
        rrect(x - e, y - e, s + 2 * e, s + 2 * e, cell * 0.2, lin(listOf(woodDark.lit(0.2), woodDark, woodDark.shade(0.3)), x - e, y - e, x + s + e, y + s + e))
        rrect(x, y, s, s, cell * 0.08, rgb(0.2, 0.11, 0.05))
        rrectStroke(x, y, s, s, cell * 0.08, Color.Black.op(0.5), 2.0 * density)
    }

    fun track(x: Double, y: Double, w: Double, h: Double, m: Int): Path {
        val cx = x + w / 2; val cy = y + h / 2
        val ends = listOf(1 to P(cx, y), 2 to P(x + w, cy), 4 to P(cx, y + h), 8 to P(x, cy))
        val open = ends.filter { m and it.first != 0 }
        val p = Path()
        if (open.size == 2 && (m == 5 || m == 10)) { p.m(open[0].second.x, open[0].second.y); p.l(open[1].second.x, open[1].second.y) }
        else if (open.size == 2) {
            val kx = if (m and 2 != 0) x + w else x; val ky = if (m and 1 != 0) y else y + h
            val a = open[0].second; val b = open[1].second
            p.m(a.x, a.y); p.q(a.x + b.x - kx, a.y + b.y - ky, b.x, b.y)
        } else for ((_, e) in open) { p.m(e.x, e.y); p.l(cx, cy) }
        return p
    }

    fun tile(d: DrawScope, cx0: Double, cy0: Double, s: Double, tile: RTile, isLit: Boolean, ball: Boolean, seed: Int) = with(d) {
        val i = s * 0.035
        val x = cx0 + i; val y = cy0 + i; val w = s - 2 * i
        val cr = s * 0.09
        val body = Path().apply { addRoundRect(RoundRect(x.f, y.f, (x + w).f, (y + w).f, CornerRadius(cr.f))) }
        if (tile.kind == RKind.BLOCKER) {
            steel(this, x, y, w, cr)
            val cross = Path()
            cross.m(x + s * 0.22, y + s * 0.22); cross.l(x + w - s * 0.22, y + w - s * 0.22)
            cross.m(x + w - s * 0.22, y + s * 0.22); cross.l(x + s * 0.22, y + w - s * 0.22)
            strokePath(cross, Color.Black.op(0.35), s * 0.07)
            strokePath(cross, Color.White.op(0.25), s * 0.025)
            return@with
        }
        drawPath(body, lin(listOf(wood.lit(0.1), wood, wood.shade(0.12)), x, y, x + w, y + w))
        clipPath(body) {
            for (k in 0 until 5) {
                val gy = y + w * (0.1 + 0.2 * k) + ((seed * 7 + k * 3) % 5 - 2) * density
                val g = Path(); g.m(x, gy); g.c(x + w * 0.35, gy - s * 0.05, x + w * 0.65, gy + s * 0.08, x + w, gy + s * 0.04)
                strokePath(g, wood.shade(0.3).op(0.35), max(0.6, s * 0.012))
            }
        }
        drawRoundRect(lin(listOf(Color.White.op(0.5), Color.Transparent, Color.Black.op(0.3)), x, y, x + w, y + w),
            off(x + s * 0.02, y + s * 0.02), sz(w - s * 0.04, w - s * 0.04), CornerRadius((s * 0.08).f), style = Stroke((s * 0.04).f))
        if (tile.fixed) steelFrame(this, x, y, w, s)
        val path = track(x, y, w, w, tile.openings)
        val gw = s * 0.34
        clipPath(body) {
            drawPath(path, wood.shade(0.45), style = Stroke((gw * 1.12).f, cap = StrokeCap.Round, join = StrokeJoin.Round))
            drawPath(path, if (isLit) lit else groove, style = Stroke(gw.f, cap = StrokeCap.Round, join = StrokeJoin.Round))
            translate(0f, (-gw * 0.18).f) {
                drawPath(path, Color.Black.op(if (isLit) 0.15 else 0.35), style = Stroke((gw * 0.45).f, cap = StrokeCap.Round, join = StrokeJoin.Round))
            }
            if (isLit) drawPath(path, Color.White.op(0.5), style = Stroke((gw * 0.18).f, cap = StrokeCap.Round, join = StrokeJoin.Round))
        }
        if (tile.kind == RKind.GOAL) {
            val px = x + w / 2; val py = y + w / 2
            circle(px, py, s * 0.22, vgrad(listOf(gray(0.85), gray(0.45)), py - s * 0.22, py + s * 0.22))
            circle(px, py, s * 0.16, radial(listOf(Color.Black, gray(0.12)), px, py + s * 0.04, s * 0.16))
        }
        if (ball) ball(this, x + w / 2, y + w / 2, s * 0.2)
    }

    private fun steel(d: DrawScope, x: Double, y: Double, w: Double, cr: Double) = with(d) {
        rrect(x, y, w, w, cr, lin(listOf(gray(0.78), gray(0.55), gray(0.68)), x, y, x + w, y + w))
        rrectStroke(x, y, w, w, cr, gray(0.3), 1.5 * density)
        screws(this, x, y, w, w)
    }

    private fun steelFrame(d: DrawScope, x: Double, y: Double, w: Double, s: Double) = with(d) {
        drawRoundRect(lin(listOf(gray(0.85), gray(0.5)), x, y, x + w, y + w), off(x + s * 0.04, y + s * 0.04), sz(w - s * 0.08, w - s * 0.08),
            CornerRadius((s * 0.07).f), style = Stroke((s * 0.08).f))
        screws(this, x, y, w, s)
    }

    private fun screws(d: DrawScope, x: Double, y: Double, w: Double, s: Double) = with(d) {
        for ((fx, fy) in listOf(0.13 to 0.13, 0.87 to 0.13, 0.13 to 0.87, 0.87 to 0.87)) {
            val px = x + w * fx; val py = y + w * fy
            val sr = s * 0.055
            circle(px, py, sr, radial(listOf(gray(0.95), gray(0.5)), px - sr * 0.3, py - sr * 0.3, sr * 1.2))
            line(px - sr * 0.6, py + sr * 0.3, px + sr * 0.6, py - sr * 0.3, gray(0.3), max(0.8, sr * 0.3), StrokeCap.Butt)
        }
    }

    fun ball(d: DrawScope, px: Double, py: Double, r: Double) = with(d) {
        circle(px + r * 0.15, py + r * 0.25, r, Color.Black.op(0.35))
        circle(px, py, r, radial(listOf(Color.White, gray(0.8), gray(0.45), gray(0.25)), px - r * 0.35, py - r * 0.4, r * 1.5))
        circleStroke(px, py, r, gray(0.2), max(0.8, r * 0.06))
        circle(px - r * 0.35, py - r * 0.38, r * 0.22, Color.White.op(0.9))
    }
}

private fun DrawScope.backdrop() {
    val W = size.width.toDouble(); val H = size.height.toDouble(); val u = density.toDouble()
    rect(0.0, 0.0, W, H, vgrad(listOf(rgb(0.55, 0.36, 0.2), rgb(0.36, 0.21, 0.1)), 0.0, H))
    val plank = 46 * u
    var x = 0.0; var k = 0
    while (x < W) {
        rect(x, 0.0, 1.5 * u, H, Color.Black.op(0.22))
        if (k % 2 == 1) rect(x, 0.0, plank, H, Color.White.op(0.03))
        x += plank; k++
    }
    val r = max(W, H) * 0.8
    drawRect(Brush.radialGradient(0f to Color.Transparent, (W * 0.3 / r).toFloat().coerceIn(0f, 1f) to Color.Transparent, 1f to Color.Black.op(0.35),
        center = off(W / 2, H / 2), radius = r.toFloat()))
}
