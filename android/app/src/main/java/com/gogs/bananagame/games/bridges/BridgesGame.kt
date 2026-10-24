package com.gogs.bananagame.games.bridges

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
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
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.vector.VectorPainter
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/**
 * Brain — Bridges (iOS HashiGame.swift, id "hashi-bridges"): each island's number is how many bridges
 * touch it. Tap two aligned islands to bridge them (again to double, again to clear); no crossings;
 * join everything into one network before time runs out.
 */
object BridgesGame {
    val definition = GameDefinition(
        id = "hashi-bridges",
        title = "Bridges",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Each island's number is how many bridges must connect to it.",
                "Tap two islands in the same row or column to build; tap again to double, a third time to clear.",
                "Bridges are straight, never cross, and max two per pair.",
                "Match every number and join all islands into one network before time runs out.",
            ),
            bulletsVI = listOf(
                "Con số trên mỗi đảo là số cầu phải nối vào nó.",
                "Chạm hai đảo cùng hàng hoặc cột để nối; chạm lại thành cầu đôi, lần ba để xóa.",
                "Cầu đi thẳng, không cắt nhau, tối đa hai cầu mỗi cặp.",
                "Khớp mọi con số và nối tất cả các đảo thành một mạng trước khi hết giờ.",
            ),
            liveDemo = true
        ),
        prefetch = { level -> BoardCache.prefetch(key(level)) { HashiGen.make(gridSize(level), targetIslands(level)) } },
        content = { level, onWin, onFail -> BridgesView(level, onWin, onFail) }
    )

    fun key(level: Int) = BoardCache.key("hashi-bridges", level)
    fun targetIslands(level: Int) = listOf(4, 6, 8, 10, 12, 14, 16)[min(level, 7) - 1]
    fun gridSize(level: Int) = listOf(5, 6, 7, 7, 8, 8, 9)[min(level, 7) - 1]
    fun timeLimit(level: Int) = listOf(55.0, 75.0, 95.0, 115.0, 130.0, 140.0, 150.0)[min(level, 7) - 1]
}

data class HIsland(val r: Int, val c: Int, val need: Int)
class HashiPuzzle(val gridN: Int, val islands: List<HIsland>)
private data class HPair(val a: Int, val b: Int) { companion object { fun of(x: Int, y: Int) = HPair(min(x, y), max(x, y)) } }

/** Boards grown as a connected web, so the clues are one real solution's degrees (iOS makePuzzle). */
object HashiGen {
    fun make(gridN: Int, target: Int): HashiPuzzle {
        var best: HashiPuzzle? = null
        repeat(50) {
            val p = tryGenerate(gridN, target)
            if (p.islands.size >= max(3, target - 2)) return p
            if (best == null || p.islands.size > best!!.islands.size) best = p
        }
        return best ?: HashiPuzzle(3, listOf(HIsland(0, 0, 2), HIsland(0, 2, 2), HIsland(2, 0, 2), HIsland(2, 2, 2)))
    }

    private fun tryGenerate(n: Int, target: Int): HashiPuzzle {
        val pos = mutableListOf<Pair<Int, Int>>(); val need = mutableListOf<Int>()
        val islandAt = HashSet<Int>(); val bridgeCell = HashSet<Int>()
        fun key(r: Int, c: Int) = r * n + c
        val r0 = Random.nextInt(n); val c0 = Random.nextInt(n)
        pos.add(r0 to c0); need.add(0); islandAt.add(key(r0, c0))
        val dirs = listOf(0 to 1, 0 to -1, 1 to 0, -1 to 0)
        var tries = 0
        while (pos.size < target && tries < target * 80) {
            tries++
            val ai = Random.nextInt(pos.size)
            val (ar, ac) = pos[ai]
            val (dr, dc) = dirs.pick()
            val dist = rndInt(2..4)
            val nr = ar + dr * dist; val nc = ac + dc * dist
            if (nr !in 0 until n || nc !in 0 until n || key(nr, nc) in islandAt) continue
            val cells = mutableListOf<Int>(); var ok = true
            for (s in 1 until dist) { val ik = key(ar + dr * s, ac + dc * s); if (ik in islandAt || ik in bridgeCell) { ok = false; break }; cells.add(ik) }
            if (!ok) continue
            val cnt = rndInt(1..2)
            pos.add(nr to nc); need.add(0); islandAt.add(key(nr, nc))
            bridgeCell.addAll(cells)
            need[ai] += cnt; need[pos.size - 1] += cnt
        }
        val count = pos.size
        repeat(target * 6) {
            val i = Random.nextInt(count); val j = Random.nextInt(count)
            if (i == j) return@repeat
            val (ar, ac) = pos[i]; val (br, bc) = pos[j]
            val cells = mutableListOf<Int>(); var ok = true
            if (ar == br) {
                val c1 = min(ac, bc); val c2 = max(ac, bc)
                if (c2 - c1 < 2) return@repeat
                for (c in c1 + 1 until c2) { val ik = key(ar, c); if (ik in islandAt || ik in bridgeCell) { ok = false; break }; cells.add(ik) }
            } else if (ac == bc) {
                val r1 = min(ar, br); val r2 = max(ar, br)
                if (r2 - r1 < 2) return@repeat
                for (r in r1 + 1 until r2) { val ik = key(r, ac); if (ik in islandAt || ik in bridgeCell) { ok = false; break }; cells.add(ik) }
            } else return@repeat
            if (!ok || cells.isEmpty()) return@repeat
            val cnt = rndInt(1..2)
            if (need[i] + cnt > 8 || need[j] + cnt > 8) return@repeat
            bridgeCell.addAll(cells)
            need[i] += cnt; need[j] += cnt
        }
        return HashiPuzzle(n, pos.mapIndexed { k, (r, c) -> HIsland(r, c, need[k]) })
    }
}

private val demoPuzzle = HashiPuzzle(5, listOf(HIsland(0, 0, 3), HIsland(0, 4, 2), HIsland(4, 0, 4), HIsland(4, 4, 3)))
private val demoTaps = listOf(2, 0, 2, 0, 2, 3, 2, 3, 0, 1, 1, 3)

@Composable
private fun BridgesView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val timeLimit = BridgesGame.timeLimit(level)
    var playing by remember { mutableStateOf(true) }
    var ready by remember { mutableStateOf(false) }
    var gridN by remember { mutableIntStateOf(0) }
    var islands by remember { mutableStateOf(listOf<HIsland>()) }
    var allowed by remember { mutableStateOf(setOf<HPair>()) }
    var interior by remember { mutableStateOf(mapOf<HPair, Set<Int>>()) }
    var bridges by remember { mutableStateOf(mapOf<HPair, Int>()) }
    var selected by remember { mutableStateOf<Int?>(null) }
    var timeLeft by remember { mutableDoubleStateOf(timeLimit) }
    var demoFinger by remember { mutableStateOf<Int?>(null) }
    val tm = rememberTextMeasurer()
    val handP = rememberHand()
    val dens = androidx.compose.ui.platform.LocalDensity.current.density.toDouble()

    fun degree(i: Int) = bridges.entries.sumOf { (p, c) -> if (p.a == i || p.b == i) c else 0 }
    fun win() { if (!playing) return; playing = false; onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }

    fun commit(p: HashiPuzzle) {
        gridN = p.gridN; islands = p.islands; bridges = emptyMap(); selected = null
        val allow = HashSet<HPair>(); val inter = HashMap<HPair, Set<Int>>()
        val isl = p.islands
        for (i in isl.indices) for (j in i + 1 until isl.size) {
            val a = isl[i]; val b = isl[j]
            if (a.r == b.r) {
                val c1 = min(a.c, b.c); val c2 = max(a.c, b.c)
                if (isl.none { it.r == a.r && it.c > c1 && it.c < c2 }) { val pr = HPair.of(i, j); allow.add(pr); inter[pr] = (c1 + 1 until c2).map { a.r * p.gridN + it }.toSet() }
            } else if (a.c == b.c) {
                val r1 = min(a.r, b.r); val r2 = max(a.r, b.r)
                if (isl.none { it.c == a.c && it.r > r1 && it.r < r2 }) { val pr = HPair.of(i, j); allow.add(pr); inter[pr] = (r1 + 1 until r2).map { it * p.gridN + a.c }.toSet() }
            }
        }
        allowed = allow; interior = inter
    }

    fun connected(): Boolean {
        if (islands.isEmpty()) return false
        val adj = List(islands.size) { mutableListOf<Int>() }
        for ((p, c) in bridges) if (c > 0) { adj[p.a].add(p.b); adj[p.b].add(p.a) }
        val seen = hashSetOf(0); val stack = ArrayDeque(listOf(0))
        while (stack.isNotEmpty()) for (nb in adj[stack.removeLast()]) if (seen.add(nb)) stack.addLast(nb)
        return seen.size == islands.size
    }

    fun tapIsland(i: Int) {
        if (!playing) return
        val s = selected
        if (s == null) { selected = i; SoundManager.tap(); return }
        if (s == i) { selected = null; return }
        selected = null
        val pair = HPair.of(s, i)
        if (pair !in allowed) { SoundManager.error(); Haptics.warning(); return }
        val cur = bridges[pair] ?: 0
        if (cur == 0) {
            val mine = interior[pair] ?: emptySet()
            if (bridges.any { (o, c) -> c > 0 && o != pair && (interior[o] ?: emptySet()).any { it in mine } }) { SoundManager.error(); Haptics.warning(); return }
        }
        bridges = when (cur) { 0 -> bridges + (pair to 1); 1 -> bridges + (pair to 2); else -> bridges - pair }
        SoundManager.tap(); Haptics.tap()
        if (islands.indices.all { degree(it) == islands[it].need } && connected()) win()
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (isActive) {
                commit(demoPuzzle); demoFinger = null; timeLeft = timeLimit; playing = true; ready = true
                delay(700)
                for (i in demoTaps) { demoFinger = i; delay(220); tapIsland(i); delay(300) }
                demoFinger = null
                delay(1300)
            }
        } else {
            val t0 = System.currentTimeMillis()
            val p = BoardCache.take(BridgesGame.key(level)) { HashiGen.make(BridgesGame.gridSize(level), BridgesGame.targetIslands(level)) }
            BoardCache.holdBrainstorm(t0, 0.7)
            commit(p); ready = true; playing = true; timeLeft = timeLimit
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
        val top = listOf(rgb(0.06, 0.13, 0.22), rgb(0.06, 0.12, 0.21), rgb(0.05, 0.11, 0.20), rgb(0.05, 0.10, 0.19),
            rgb(0.04, 0.09, 0.18), rgb(0.04, 0.08, 0.16), rgb(0.03, 0.07, 0.15))
        val bottom = listOf(rgb(0.03, 0.07, 0.13), rgb(0.03, 0.06, 0.12), rgb(0.02, 0.06, 0.12), rgb(0.02, 0.05, 0.11),
            rgb(0.02, 0.05, 0.10), rgb(0.01, 0.04, 0.09), rgb(0.01, 0.03, 0.08))
        BrainstormingView(top[i], bottom[i])
        return
    }

    val solved = islands.indices.count { degree(it) == islands[it].need }
    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp)).drawBehind { sea() },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(if (isDemo) 4.dp else 10.dp)
    ) {
        Row(Modifier.padding(top = if (isDemo) 6.dp else 0.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Canvas(Modifier.size(if (isDemo) 16.dp else 20.dp)) { islandIcon() }
            Text("$solved / ${islands.size}", style = ts(if (isDemo) 14.0 else 18.0, FontWeight.Black, if (solved == islands.size) BananaTheme.banana else Color.White)
                .copy(fontFeatureSettings = "tnum"))
        }
        if (!isDemo) {
            val f = timeLeft / timeLimit
            TimeBar(f, Modifier.fillMaxWidth().padding(horizontal = 60.dp).height(5.dp), fill = if (f < 0.3) rgb(1.0, 0.35, 0.3) else rgb(1.0, 0.9, 0.62), track = Color.White.op(0.2))
        }
        Canvas(Modifier.fillMaxWidth().weight(1f).then(if (isDemo) Modifier else Modifier.tapIn(islands) { p, w, h ->
            val side = min(w, h) - 16 * dens
            val cell = if (gridN > 0) side / gridN else 0.0
            val ox = (w - cell * gridN) / 2; val oy = (h - cell * gridN) / 2
            islands.indices.firstOrNull { i ->
                P(ox + (islands[i].c + 0.5) * cell, oy + (islands[i].r + 0.5) * cell).dist(p) <= cell * 0.36
            }?.let { tapIsland(it) }
        })) {
            val w = size.width.toDouble(); val h = size.height.toDouble(); val u = density.toDouble()
            val side = min(w, h) - 16 * u
            val cell = if (gridN > 0) side / gridN else 0.0
            val ox = (w - cell * gridN) / 2; val oy = (h - cell * gridN) / 2
            fun pos(i: Int) = P(ox + (islands[i].c + 0.5) * cell, oy + (islands[i].r + 0.5) * cell)
            for ((p, c) in bridges.entries.sortedWith(compareBy({ it.key.a }, { it.key.b }))) if (c > 0 && p.a < islands.size && p.b < islands.size) bridge(pos(p.a), pos(p.b), c, cell)
            for (i in islands.indices) island(tm, pos(i), cell, islands[i].need, degree(i), selected == i)
            demoFinger?.let { f -> if (f < islands.size) { val s = cell * 0.5; hand(handP, pos(f).x + cell * 0.3 - s / 2, pos(f).y + cell * 0.38 - s / 2, s) } }
        }
    }
}

// Archipelago art (iOS HashiArt / HashiSea / HashiIslandIcon).

private val wood = rgb(0.62, 0.42, 0.22)
private val rope = rgb(0.9, 0.8, 0.56)

/** A plank bridge (or two side by side) from island to island; the islands cover its ends. */
private fun DrawScope.bridge(p1: P, p2: P, count: Int, cell: Double) {
    val horizontal = abs(p1.y - p2.y) < 0.5
    val off = cell * 0.11
    val offsets = if (count >= 2) listOf(-off, off) else listOf(0.0)
    val deck = if (count >= 2) cell * 0.1 else cell * 0.16
    val len = if (horizontal) abs(p2.x - p1.x) else abs(p2.y - p1.y)
    val start = if (horizontal) min(p1.x, p2.x) else min(p1.y, p2.y)
    for (o in offsets) {
        val tx = if (horizontal) start else p1.x + o; val ty = if (horizontal) p1.y + o else start
        translate(tx.f, ty.f) {
            rotate(if (horizontal) 0f else 90f, Offset.Zero) {
                rect(0.0, -deck / 2 + deck * 0.35, len, deck, Color.Black.op(0.2))
                val planks = Path(); var x = 0.0
                while (x < len) { planks.addRect(androidx.compose.ui.geometry.Rect(x.f, (-deck / 2).f, (x + min(cell * 0.07, len - x)).f, (deck / 2).f)); x += cell * 0.09 }
                drawPath(planks, vgrad(listOf(wood.mix(Color.White, 0.2), wood, wood.mix(Color.Black, 0.25)), -deck / 2, deck / 2))
                val rails = Path(); rails.m(0.0, -deck / 2); rails.l(len, -deck / 2); rails.m(0.0, deck / 2); rails.l(len, deck / 2)
                strokePath(rails, rope, max(density.toDouble(), cell * 0.022), StrokeCap.Butt)
            }
        }
    }
}

/** A smooth irregular coastline blob around (cx, cy), fixed by `seed`. */
private fun blob(cx: Double, cy: Double, r: Double, seed: Double): Path {
    val n = 12
    val pts = (0 until n).map { i ->
        val a = i.toDouble() / n * 2 * PI
        val k = 1 + 0.07 * sin(seed + i * 2.3) + 0.04 * cos(seed * 1.7 + i * 1.1)
        P(cx + cos(a) * k * r, cy + sin(a) * k * r)
    }
    fun mid(a: P, b: P) = P((a.x + b.x) / 2, (a.y + b.y) / 2)
    val p = Path(); val m0 = mid(pts[n - 1], pts[0]); p.m(m0.x, m0.y)
    for (i in 0 until n) { val m = mid(pts[i], pts[(i + 1) % n]); p.q(pts[i].x, pts[i].y, m.x, m.y) }
    p.close(); return p
}

/** An island: shallows, sandy coast, grass cap with a palm, and its clue on a painted disc. */
private fun DrawScope.island(tm: TextMeasurer, p: P, cell: Double, need: Int, degree: Int, selected: Boolean) {
    val u = density.toDouble()
    val seed = p.x / u * 0.37 + p.y / u * 0.11
    if (selected) {
        val inner = (0.36 / 0.52).toFloat()
        drawCircle(androidx.compose.ui.graphics.Brush.radialGradient(0f to rgb(1.0, 0.85, 0.3, 0.6), inner to rgb(1.0, 0.85, 0.3, 0.6), 1f to Color.Transparent,
            center = p.o(), radius = (cell * 0.52).f), (cell * 0.52).f, p.o())
    }
    fillPath(blob(p.x, p.y, cell * 0.46, seed + 3), rgb(0.36, 0.82, 0.82, 0.33))
    val sand = blob(p.x, p.y, cell * 0.37, seed)
    drawPath(sand, radial(listOf(rgb(0.99, 0.91, 0.7), rgb(0.88, 0.74, 0.48)), p.x - cell * 0.1, p.y - cell * 0.12, cell * 0.42))
    strokePath(sand, Color.White.op(0.5), max(u, cell * 0.02))
    drawPath(blob(p.x, p.y - cell * 0.015, cell * 0.315, seed + 7), vgrad(listOf(rgb(0.42, 0.8, 0.36), rgb(0.22, 0.56, 0.26)), p.y - cell * 0.3, p.y + cell * 0.3))
    val trunk = Path(); trunk.m(p.x - cell * 0.12, p.y - cell * 0.12); trunk.q(p.x - cell * 0.26, p.y - cell * 0.16, p.x - cell * 0.3, p.y - cell * 0.36)
    strokePath(trunk, rgb(0.5, 0.34, 0.18), max(1.2 * u, cell * 0.05))
    val tx = p.x - cell * 0.3; val ty = p.y - cell * 0.36
    val fronds = Path()
    for ((dx, dy) in listOf(-0.16 to 0.06, 0.14 to 0.04, -0.08 to -0.12, 0.1 to -0.1, -0.02 to 0.12)) {
        fronds.m(tx, ty); fronds.q(tx + cell * dx * 0.5, ty + cell * (dy - 0.06), tx + cell * dx, ty + cell * dy)
    }
    strokePath(fronds, rgb(0.2, 0.62, 0.24), max(1.2 * u, cell * 0.04))
    val white = degree < need
    val face = if (degree == need) rgb(0.3, 0.74, 0.4) else if (degree > need) rgb(0.92, 0.3, 0.28) else Color.White
    circle(p.x, p.y, cell * 0.23, face)
    circleStroke(p.x, p.y, cell * 0.23, rgb(0.16, 0.24, 0.14, 0.75), max(u, cell * 0.02))
    if (selected) circleStroke(p.x, p.y, cell * 0.44, rgb(1.0, 0.85, 0.3), 3 * u)
    text(tm, "$need", p.x, p.y, cell * 0.29, if (white) rgb(0.08, 0.2, 0.3) else Color.White, FontWeight.Black)
}

/** Deep teal sea with long swell lines. */
private fun DrawScope.sea() {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    rect(0.0, 0.0, w, h, vgrad(listOf(rgb(0.05, 0.4, 0.54), rgb(0.02, 0.2, 0.34)), 0.0, h))
    val swell = Path()
    var y = 20 * u; var row = 0
    while (y < h) {
        var x = -40 * u + (row % 2) * 30 * u
        while (x < w) { swell.m(x, y); swell.q(x + 22 * u, y - 6 * u, x + 44 * u, y); x += 70 * u }
        y += 34 * u; row++
    }
    strokePath(swell, Color.White.op(0.07), 2 * u)
}

/** The counter's little island: sand, a palm and its fronds. */
private fun DrawScope.islandIcon() {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    oval(w * 0.05, h * 0.62, w * 0.9, h * 0.34, rgb(0.95, 0.85, 0.6))
    val trunk = Path(); trunk.m(w * 0.5, h * 0.72); trunk.q(w * 0.42, h * 0.5, w * 0.56, h * 0.28)
    strokePath(trunk, rgb(0.55, 0.38, 0.2), max(1.5 * u, w * 0.1))
    val fronds = Path()
    for ((dx, dy) in listOf(-0.4 to 0.1, 0.4 to 0.12, -0.25 to -0.18, 0.3 to -0.16)) {
        fronds.m(w * 0.56, h * 0.28); fronds.q(w * (0.56 + dx * 0.5), h * (0.28 + dy - 0.1), w * (0.56 + dx), h * (0.28 + dy + 0.12))
    }
    strokePath(fronds, rgb(0.3, 0.78, 0.38), max(1.5 * u, w * 0.1))
}
