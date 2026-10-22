package com.gogs.bananagame.games.pegsolitaire

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/**
 * Brain — Peg Solitaire (iOS PegSolitaireGame.swift). Jump a peg straight over an adjacent peg into
 * the empty hole beyond; clear down to one peg. Boards are built backwards from a lone survivor by
 * "un-jumping", so every layout is reducible to one peg.
 */
data class PCell(val r: Int, val c: Int)

class PegPuzzle(val w: Int, val h: Int, val pegs: Set<PCell>)

object PegSolitaireGame {
    val definition = GameDefinition(
        id = "peg-solitaire",
        title = "Peg Solitaire",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Tap a peg, then tap a highlighted hole two spaces away in a straight line.",
                "The peg leaps the one between them and removes it.",
                "Clear the board down to a single peg to win — before time runs out.",
            ),
            bulletsVI = listOf(
                "Chạm vào một quân cờ, rồi chạm vào ô trống được tô sáng cách hai ô theo đường thẳng.",
                "Quân cờ nhảy qua quân ở giữa và loại nó khỏi bàn.",
                "Giảm bàn cờ xuống chỉ còn một quân để thắng — trước khi hết giờ.",
            ),
            liveDemo = true
        ),
        prefetch = { level -> val p = params(level); BoardCache.prefetch(boardKey(level)) { makePuzzle(p) } },
        content = { level, onWin, onFail -> PegSolitaireView(level, onWin, onFail) }
    )

    fun params(level: Int): Triple<Int, Int, Int> =
        listOf(Triple(4, 4, 5), Triple(5, 4, 7), Triple(5, 5, 9), Triple(5, 5, 12), Triple(6, 5, 14), Triple(6, 6, 17), Triple(6, 6, 20))[min(level, 7) - 1]

    fun timeLimit(level: Int) = listOf(40.0, 50.0, 60.0, 70.0, 80.0, 90.0, 100.0)[min(level, 7) - 1]
    fun boardKey(level: Int) = BoardCache.key("peg-solitaire", level)

    // MARK: Generation (backward un-jumping)
    fun makePuzzle(p: Triple<Int, Int, Int>): PegPuzzle {
        var best = PegPuzzle(p.first, p.second, emptySet())
        repeat(40) {
            val cand = build(p)
            if (cand.pegs.size >= p.third) return cand
            if (cand.pegs.size > best.pegs.size) best = cand
        }
        return if (best.pegs.size >= 3) best else PegPuzzle(max(p.first, 3), max(p.second, 1), setOf(PCell(0, 0), PCell(0, 1)))
    }

    fun build(p: Triple<Int, Int, Int>): PegPuzzle {
        val (w, h, target) = p
        fun inb(c: PCell) = c.r in 0 until h && c.c in 0 until w
        val pegs = mutableSetOf(PCell(rndInt(0 until h), rndInt(0 until w)))
        var guardN = 0
        val dirs = listOf(1 to 0, -1 to 0, 0 to 1, 0 to -1)
        while (pegs.size < target && guardN < target * 60) {
            guardN++
            var did = false
            for (c in pegs.shuffled()) {
                for ((dr, dc) in dirs.shuffled()) {
                    val a = PCell(c.r + dr * 2, c.c + dc * 2)
                    val b = PCell(c.r + dr, c.c + dc)
                    if (inb(a) && inb(b) && a !in pegs && b !in pegs) {
                        pegs.remove(c); pegs.add(a); pegs.add(b)
                        did = true
                        break
                    }
                }
                if (did) break
            }
            if (!did) break
        }
        return PegPuzzle(w, h, pegs)
    }

    /** The jumped peg if `from` can legally leap to `to`, else null. */
    fun jumpMid(pegs: Set<PCell>, from: PCell, to: PCell): PCell? {
        if (from !in pegs || to in pegs) return null
        val dr = to.r - from.r; val dc = to.c - from.c
        val ok = (abs(dr) == 2 && dc == 0) || (abs(dc) == 2 && dr == 0)
        if (!ok) return null
        val mid = PCell(from.r + dr / 2, from.c + dc / 2)
        return if (mid in pegs) mid else null
    }

    fun isDead(pegs: Set<PCell>, w: Int, h: Int): Boolean {
        for (p in pegs) for ((dr, dc) in listOf(2 to 0, -2 to 0, 0 to 2, 0 to -2)) {
            val to = PCell(p.r + dr, p.c + dc)
            if (to.r in 0 until h && to.c in 0 until w && jumpMid(pegs, p, to) != null) return false
        }
        return true
    }
}

private val FELT_TOP = rgb(0.12, 0.36, 0.27)
private val FELT_BOTTOM = rgb(0.04, 0.16, 0.12)

private class PegHop(val from: PCell, val to: PCell, val mid: PCell, val tint: Int, val midTint: Int, val slot: Int, val t0: Double)

@Composable
private fun PegSolitaireView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val timeLimit = PegSolitaireGame.timeLimit(level)
    var playing by remember { mutableStateOf(true) }
    var ready by remember { mutableStateOf(false) }
    var w by remember { mutableIntStateOf(0) }
    var h by remember { mutableIntStateOf(0) }
    var pegs by remember { mutableStateOf(emptySet<PCell>()) }
    var selected by remember { mutableStateOf<PCell?>(null) }
    var timeLeft by remember { mutableDoubleStateOf(timeLimit) }
    val tint = remember { mutableStateMapOf<PCell, Int>() }
    var captured by remember { mutableStateOf(listOf<Int>()) }
    var hop by remember { mutableStateOf<PegHop?>(null) }
    var demoCell by remember { mutableStateOf<PCell?>(null) }
    val scope = rememberCoroutineScope()
    val handPainter = rememberHand()

    fun assignTints(shuffled: Boolean) {
        val order = pegs.sortedWith(compareBy({ it.r }, { it.c }))
        val kinds = order.indices.map { it % PegArt.marbleCount }.let { if (shuffled) it.shuffled() else it }
        tint.clear()
        order.forEachIndexed { i, p -> tint[p] = kinds[i] }
        captured = emptyList()
        hop = null
    }

    fun win() { if (!playing) return; playing = false; onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }
    fun deadFail() {
        if (!playing) return
        playing = false
        SoundManager.error(); Haptics.warning()
        scope.launch { delay(400); onFail() }
    }

    fun recordHop(from: PCell, mid: PCell, to: PCell) {
        val t = tint[from] ?: 0; val mt = tint[mid] ?: 0
        tint.remove(from); tint.remove(mid); tint[to] = t
        captured = captured + mt
        val stamp = nowSec()
        hop = PegHop(from, to, mid, t, mt, captured.size - 1, stamp)
        scope.launch { delay(500); if (hop?.t0 == stamp) hop = null }
    }

    fun tapHole(cell: PCell) {
        if (!playing) return
        val s = selected
        if (s != null) {
            if (s == cell) { selected = null; return }
            val mid = PegSolitaireGame.jumpMid(pegs, s, cell)
            if (mid != null) {
                pegs = pegs - s - mid + cell
                selected = null
                recordHop(s, mid, cell)
                SoundManager.tap(); Haptics.tap()
                if (pegs.size == 1) { win(); return }
                if (PegSolitaireGame.isDead(pegs, w, h)) deadFail()
                return
            }
            if (cell in pegs) { selected = cell; SoundManager.tap(); return }
            selected = null
        } else if (cell in pegs) {
            selected = cell; SoundManager.tap()
        }
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            val jumps = listOf(PCell(0, 1) to PCell(2, 1), PCell(0, 2) to PCell(2, 2), PCell(2, 2) to PCell(2, 0))
            while (isActive) {
                w = 3; h = 3
                pegs = setOf(PCell(0, 1), PCell(1, 1), PCell(0, 2), PCell(1, 2))
                selected = null; demoCell = null
                assignTints(false)
                ready = true; playing = true; timeLeft = timeLimit
                delay(700)
                for ((from, to) in jumps) {
                    demoCell = from; delay(280)
                    tapHole(from); delay(450)
                    demoCell = to; delay(300)
                    tapHole(to); delay(600)
                }
                demoCell = null
                delay(1200)
            }
        } else {
            val p = PegSolitaireGame.params(level)
            val t0 = System.currentTimeMillis()
            val puzzle = BoardCache.take(PegSolitaireGame.boardKey(level)) { PegSolitaireGame.makePuzzle(p) }
            BoardCache.holdBrainstorm(t0, 0.6)
            w = puzzle.w; h = puzzle.h; pegs = puzzle.pegs
            selected = null
            assignTints(true)
            ready = true
            playing = true
            timeLeft = timeLimit
            val start = nowSec()
            while (isActive && playing) {
                delay(50)
                timeLeft = max(0.0, timeLimit - (nowSec() - start))
                if (timeLeft <= 0) { fail(); break }
            }
        }
    }

    if (!ready) { BrainstormingView(FELT_TOP, FELT_BOTTOM); return }

    val tick by rememberFrameLoop(running = hop != null)
    Box(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp)
            .clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .background(Brush.radialGradient(listOf(FELT_TOP, FELT_BOTTOM)))
    ) {
        Column(
            Modifier.fillMaxSize().padding(top = if (isDemo) 8.dp else 14.dp, bottom = if (isDemo) 4.dp else 10.dp,
                start = if (isDemo) 4.dp else 10.dp, end = if (isDemo) 4.dp else 10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(if (isDemo) 4.dp else 10.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Canvas(Modifier.size(if (isDemo) 18.dp else 22.dp)) {
                    PegArt.marble(this, size.width / 2.0, size.height / 2.0, size.width * 0.42, 3, shadow = false)
                }
                Spacer(Modifier.width(8.dp))
                val n = pegs.size
                Text(L("$n PEG${if (n == 1) "" else "S"} LEFT", "CÒN $n QUÂN"),
                    style = ts(if (isDemo) 17.0 else 20.0, FontWeight.Black, if (n == 1) BananaTheme.banana else Color.White))
            }
            if (!isDemo) TimeBar(timeLeft / timeLimit, Modifier.fillMaxWidth().padding(horizontal = 48.dp).height(6.dp), track = Color.Black.op(0.3))
            Canvas(
                Modifier.fillMaxWidth().weight(1f).pointerInput(w, h, isDemo) {
                    detectTapGestures { pos ->
                        if (isDemo) return@detectTapGestures
                        val lay = PegArt.layout(size.width.toDouble(), size.height.toDouble(), w, h)
                        lay.cellAt(pos.x.toDouble(), pos.y.toDouble())?.let { tapHole(it) }
                    }
                }
            ) {
                tick
                val lay = PegArt.layout(size.width.toDouble(), size.height.toDouble(), w, h)
                PegArt.drawBoard(this, lay)
                drawPieces(lay, pegs, selected, tint, captured, hop, w, h)
                val d = demoCell
                if (isDemo && d != null) {
                    val (cx, cy) = lay.center(d)
                    hand(handPainter, cx + lay.cell * 0.02, cy + lay.cell * 0.1, lay.cell * 0.55)
                }
            }
        }
    }
}

private fun DrawScope.drawPieces(
    lay: PegLayout, pegs: Set<PCell>, selected: PCell?, tint: Map<PCell, Int>, captured: List<Int>, hop: PegHop?, w: Int, h: Int,
) {
    if (lay.cell <= 0) return
    val r = lay.cell * 0.36
    val now = nowSec()
    val hk = hop?.let { min(1.0, (now - it.t0) / 0.26) } ?: 1.0
    val ck = hop?.let { min(1.0, (now - it.t0) / 0.42) } ?: 1.0

    captured.forEachIndexed { i, k ->
        if (!(hop?.slot == i && ck < 1)) {
            val (gx, gy) = lay.groovePoint(i)
            PegArt.marble(this, gx, gy, lay.cell * 0.14, k)
        }
    }

    if (selected != null) {
        for ((dr, dc) in listOf(2 to 0, -2 to 0, 0 to 2, 0 to -2)) {
            val to = PCell(selected.r + dr, selected.c + dc)
            if (to.r < 0 || to.r >= h || to.c < 0 || to.c >= w || PegSolitaireGame.jumpMid(pegs, selected, to) == null) continue
            val (cx, cy) = lay.center(to)
            val rr = lay.cell * 0.3
            circle(cx, cy, rr, radial(listOf(BananaTheme.banana.op(0.55), BananaTheme.banana.op(0.0)), cx, cy, rr))
            circleStroke(cx, cy, rr, BananaTheme.banana, max(2.0, lay.cell * 0.05))
        }
    }

    for (p in pegs.sortedWith(compareBy({ it.r }, { it.c }))) {
        if (hop != null && hk < 1 && p == hop.to) continue
        val (cx, cy) = lay.center(p)
        if (p == selected) {
            circleStroke(cx, cy, lay.cell * 0.43, Color.White.op(0.9), max(2.0, lay.cell * 0.045))
            PegArt.marble(this, cx, cy - lay.cell * 0.07, r * 1.1, tint[p] ?: 0, lift = 1.0)
        } else PegArt.marble(this, cx, cy, r, tint[p] ?: 0)
    }

    if (hop != null) {
        if (ck < 1) {
            val (ax, ay) = lay.center(hop.mid); val (bx, by) = lay.groovePoint(hop.slot)
            val e = 1 - (1 - ck).pow(3)
            PegArt.marble(this, ax + (bx - ax) * e, ay + (by - ay) * e, r + (lay.cell * 0.14 - r) * e, hop.midTint)
        }
        if (hk < 1) {
            val (ax, ay) = lay.center(hop.from); val (bx, by) = lay.center(hop.to)
            val e = if (hk < 0.5) 2 * hk * hk else 1 - (-2 * hk + 2).pow(2) / 2
            val lift = sin(hk * PI)
            PegArt.marble(this, ax + (bx - ax) * e, ay + (by - ay) * e - lift * lay.cell * 0.45, r * (1 + 0.12 * lift), hop.tint, lift = lift)
        }
    }
}

private class PegLayout(val ox: Double, val oy: Double, val cell: Double, val w: Int, val h: Int) {
    val gx get() = ox; val gy get() = oy
    val gw get() = cell * w; val gh get() = cell * h
    // board = grid inset by -0.72 cell; groove = grid inset by -0.34 cell
    val bx get() = ox - cell * 0.72; val by get() = oy - cell * 0.72
    val bw get() = gw + cell * 1.44; val bh get() = gh + cell * 1.44
    val grx get() = ox - cell * 0.34; val gry get() = oy - cell * 0.34
    val grw get() = gw + cell * 0.68; val grh get() = gh + cell * 0.68
    val grooveRadius get() = min(cell * 0.45, min(grw, grh) / 2)

    fun center(p: PCell) = Pair(ox + (p.c + 0.5) * cell, oy + (p.r + 0.5) * cell)

    fun cellAt(x: Double, y: Double): PCell? {
        if (cell <= 0) return null
        val c = floor((x - ox) / cell).toInt(); val r = floor((y - oy) / cell).toInt()
        return if (r in 0 until h && c in 0 until w) PCell(r, c) else null
    }

    /** The i-th resting spot in the groove, clockwise from the top-left. */
    fun groovePoint(i: Int): Pair<Double, Double> {
        val rr = grooveRadius
        val minX = grx; val minY = gry; val maxX = grx + grw; val maxY = gry + grh
        val top = grw - 2 * rr; val side = grh - 2 * rr; val arc = PI * rr / 2
        val perimeter = 2 * top + 2 * side + 4 * arc
        if (perimeter <= 0) return Pair((minX + maxX) / 2, (minY + maxY) / 2)
        var s = (cell * 0.2 + i * cell * 0.31) % perimeter
        fun arcPoint(cx: Double, cy: Double, a0: Double): Pair<Double, Double> {
            val a = a0 + s / max(rr, 0.001)
            return Pair(cx + rr * cos(a), cy + rr * sin(a))
        }
        if (s < top) return Pair(minX + rr + s, minY); s -= top
        if (s < arc) return arcPoint(maxX - rr, minY + rr, -PI / 2); s -= arc
        if (s < side) return Pair(maxX, minY + rr + s); s -= side
        if (s < arc) return arcPoint(maxX - rr, maxY - rr, 0.0); s -= arc
        if (s < top) return Pair(maxX - rr - s, maxY); s -= top
        if (s < arc) return arcPoint(minX + rr, maxY - rr, PI / 2); s -= arc
        if (s < side) return Pair(minX, maxY - rr - s); s -= side
        return arcPoint(minX + rr, minY + rr, PI)
    }
}

private object PegArt {
    val glass = listOf(
        rgb(0.16, 0.38, 0.90) to rgb(0.85, 0.95, 1.00),
        rgb(0.86, 0.14, 0.20) to rgb(1.00, 0.90, 0.70),
        rgb(0.10, 0.62, 0.36) to rgb(0.95, 1.00, 0.75),
        rgb(0.98, 0.64, 0.10) to rgb(1.00, 0.98, 0.85),
        rgb(0.58, 0.32, 0.90) to rgb(1.00, 0.85, 1.00),
        rgb(0.10, 0.68, 0.76) to rgb(1.00, 1.00, 1.00),
    )
    val marbleCount get() = glass.size
    val teakLight = rgb(0.86, 0.58, 0.33)
    val teak = rgb(0.71, 0.43, 0.21)
    val teakDark = rgb(0.47, 0.26, 0.11)

    fun layout(sw: Double, sh: Double, w: Int, h: Int): PegLayout {
        if (w <= 0 || h <= 0 || sw <= 0 || sh <= 0) return PegLayout(0.0, 0.0, 0.0, 0, 0)
        val pad = 1.52
        val cell = min(sw / (w + pad), sh / (h + pad))
        val gw = cell * w; val gh = cell * h
        return PegLayout((sw - gw) / 2, (sh - gh) / 2, cell, w, h)
    }

    fun drawBoard(d: DrawScope, lay: PegLayout) = with(d) {
        val c = lay.cell
        if (c <= 0) return@with
        val corner = c * 0.75
        // Soft drop shadow (approximating the blur with stacked translucent plates).
        for (k in 0 until 4) {
            val g = c * 0.05 * k
            rrect(lay.bx - g, lay.by + c * 0.16 - g, lay.bw + 2 * g, lay.bh + 2 * g, corner + g, Color.Black.op(0.55 / (k + 1.6)))
        }
        rrect(lay.bx, lay.by, lay.bw, lay.bh, corner, lin(listOf(teakLight, teak, teakDark), lay.bx, lay.by, lay.bx + lay.bw, lay.by + lay.bh))
        val shape = Path().apply {
            addRoundRect(androidx.compose.ui.geometry.RoundRect(lay.bx.f, lay.by.f, (lay.bx + lay.bw).f, (lay.by + lay.bh).f,
                androidx.compose.ui.geometry.CornerRadius(corner.f, corner.f)))
        }
        clipPath(shape) {
            val lines = max(8, (lay.bh / (c * 0.1)).toInt())
            for (i in 0 until lines) {
                val y0 = lay.by + (i + 0.5) * lay.bh / lines
                val amp = c * (0.03 + 0.05 * ((i * 37) % 5) / 4.0)
                val phase = i * 1.7
                val p = Path()
                p.m(lay.bx - 2, y0)
                var x = lay.bx
                while (x <= lay.bx + lay.bw + c * 0.25) {
                    x += c * 0.22
                    p.l(x, y0 + amp * sin((x - lay.bx) / (c * 1.7) + phase))
                }
                val dark = (i * 7) % 3 == 0
                strokePath(p, teakDark.op(if (dark) 0.32 else 0.16), if (dark) max(1.0, c * 0.024) else max(0.6, c * 0.012))
            }
        }
        val ins = c * 0.035
        drawRoundRect(lin(listOf(Color.White.op(0.4), Color.Transparent, Color.Black.op(0.35)), lay.bx, lay.by, lay.bx + lay.bw, lay.by + lay.bh),
            off(lay.bx + ins, lay.by + ins), sz(lay.bw - 2 * ins, lay.bh - 2 * ins),
            androidx.compose.ui.geometry.CornerRadius((corner * 0.95).f), style = Stroke((c * 0.07).f))
        rrectStroke(lay.bx, lay.by, lay.bw, lay.bh, corner, teakDark.shade(0.35), max(1.0, c * 0.02))

        val gr = lay.grooveRadius
        rrectStroke(lay.grx, lay.gry, lay.grw, lay.grh, gr, teakDark.shade(0.12), c * 0.3)
        drawRoundRect(lin(listOf(Color.Black.op(0.3), Color.Transparent, teakLight.op(0.3)), lay.bx, lay.by, lay.bx + lay.bw, lay.by + lay.bh),
            off(lay.grx, lay.gry), sz(lay.grw, lay.grh), androidx.compose.ui.geometry.CornerRadius(gr.f), style = Stroke((c * 0.22).f))
        val e = c * 0.15
        rrectStroke(lay.grx + e, lay.gry + e, lay.grw - 2 * e, lay.grh - 2 * e, max(0.0, gr - e), teakLight.op(0.45), max(0.8, c * 0.02))
        rrectStroke(lay.grx - e, lay.gry - e, lay.grw + 2 * e, lay.grh + 2 * e, gr + e, teakDark.shade(0.4).op(0.6), max(0.8, c * 0.02))

        for (r in 0 until lay.h) for (col in 0 until lay.w) {
            val (x, y) = lay.center(PCell(r, col))
            hole(this, x, y, c * 0.2)
        }
    }

    fun hole(d: DrawScope, x: Double, y: Double, r: Double) = with(d) {
        circle(x, y, r, radial(listOf(rgb(0.09, 0.04, 0.02), rgb(0.2, 0.1, 0.04), teakDark), x - r * 0.2, y - r * 0.25, r * 1.15))
        clipRect((x - r * 1.3).f, (y + r * 0.1).f, (x + r * 1.3).f, (y + r * 1.4).f) {
            circleStroke(x, y, r, teakLight.lit(0.25).op(0.6), max(1.0, r * 0.12))
        }
    }

    /** A glossy glass marble with a swirl, lit from the upper-left. `lift` (0…1) raises it. */
    fun marble(d: DrawScope, cx: Double, cy: Double, r: Double, k: Int, lift: Double = 0.0, shadow: Boolean = true) = with(d) {
        val m = glass[((k % glass.size) + glass.size) % glass.size]
        val base = m.first; val swirl = m.second
        if (shadow) {
            val off = r * (0.2 + 0.55 * lift)
            oval(cx - r * 0.88 + off * 0.45, cy - r * 0.7 + off, r * 1.76, r * 1.55, Color.Black.op(0.42 - 0.17 * lift))
        }
        circle(cx, cy, r, radial(listOf(base.lit(0.5), base, base.shade(0.5)), cx - r * 0.35, cy - r * 0.4, r * 1.55))
        val body = Path().apply { addOval(androidx.compose.ui.geometry.Rect((cx - r).f, (cy - r).f, (cx + r).f, (cy + r).f)) }
        clipPath(body) {
            translate(cx.f, cy.f) {
                rotate(((k * 1.9 + 0.4) * 180 / PI).f, androidx.compose.ui.geometry.Offset.Zero) {
                    val sw = Path()
                    sw.m(-r, r * 0.3)
                    sw.c(-r * 0.3, -r * 0.55, r * 0.25, r * 0.6, r, -r * 0.25)
                    strokePath(sw, swirl.op(0.55), r * 0.32, StrokeCap.Round)
                    strokePath(sw, swirl.op(0.9), r * 0.08, StrokeCap.Round)
                }
            }
        }
        circle(cx, cy, r, radial(listOf(base.lit(0.6).op(0.55), Color.Transparent), cx + r * 0.35, cy + r * 0.45, r * 0.55))
        circleStroke(cx, cy, r, base.shade(0.65).op(0.6), max(0.7, r * 0.06))
        translate((cx - r * 0.38).f, (cy - r * 0.44).f) {
            rotate(-35f, androidx.compose.ui.geometry.Offset.Zero) {
                oval(-r * 0.3, -r * 0.17, r * 0.6, r * 0.34, Color.White.op(0.85))
            }
        }
        oval(cx + r * 0.3, cy + r * 0.42, r * 0.2, r * 0.12, Color.White.op(0.4))
    }
}
