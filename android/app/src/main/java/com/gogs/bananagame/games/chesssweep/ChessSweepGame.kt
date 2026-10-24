package com.gogs.bananagame.games.chesssweep

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.Schedule
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

/**
 * Brain — Chess Sweep (iOS SoloChessGame.swift, id "solo-chess"): every move must capture and each
 * piece moves at most twice; clear the board down to one piece. Boards are built backwards from the
 * lone survivor, so a solution always exists.
 */
object ChessSweepGame {
    val definition = GameDefinition(
        id = "solo-chess",
        title = "Chess Sweep",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Every move must capture another piece.",
                "Each piece can move at most twice, then it locks.",
                "Tap a piece to select it, then tap a piece it can legally capture.",
                "Reduce the board to a single piece to win; no captures left or a timeout fails you.",
            ),
            bulletsVI = listOf(
                "Mỗi nước đi đều phải ăn một quân khác.",
                "Mỗi quân chỉ được đi tối đa hai lần, sau đó bị khóa.",
                "Chạm một quân để chọn, rồi chạm quân mà nó có thể ăn hợp lệ.",
                "Giảm bàn cờ xuống còn một quân để thắng; hết nước ăn hoặc hết giờ là thua.",
            ),
            liveDemo = true
        ),
        prefetch = { level -> BoardCache.prefetch(key(level)) { SoloGen.generate(boardN(level), targetCount(level), allowedTypes(level)) } },
        content = { level, onWin, onFail -> ChessSweepView(level, onWin, onFail) }
    )

    fun key(level: Int) = BoardCache.key("solo-chess", level)
    fun boardN(level: Int) = listOf(4, 4, 5, 5, 6, 6, 6)[min(level, 7) - 1]
    fun targetCount(level: Int) = listOf(3, 4, 5, 6, 7, 8, 9)[min(level, 7) - 1]
    fun timeLimit(level: Int) = listOf(35.0, 45.0, 55.0, 65.0, 75.0, 85.0, 95.0)[min(level, 7) - 1]
    fun allowedTypes(level: Int) = when (level) {
        1, 2 -> listOf(PType.KING, PType.KNIGHT, PType.ROOK)
        3, 4 -> listOf(PType.KING, PType.KNIGHT, PType.ROOK, PType.BISHOP)
        else -> listOf(PType.KING, PType.KNIGHT, PType.ROOK, PType.BISHOP, PType.QUEEN)
    }
}

enum class PType { KING, KNIGHT, ROOK, BISHOP, QUEEN }
data class SoloPiece(val id: Int, val r: Int, val c: Int, val type: PType, val movesMade: Int)

/** Move geometry and the backward generator (iOS SoloChessView statics). */
object SoloGen {
    private val kingDirs = listOf(-1 to -1, -1 to 0, -1 to 1, 0 to -1, 0 to 1, 1 to -1, 1 to 0, 1 to 1)
    private val knightJumps = listOf(-2 to -1, -2 to 1, -1 to -2, -1 to 2, 1 to -2, 1 to 2, 2 to -1, 2 to 1)
    private val rookDirs = listOf(-1 to 0, 1 to 0, 0 to -1, 0 to 1)
    private val bishopDirs = listOf(-1 to -1, -1 to 1, 1 to -1, 1 to 1)

    private fun slideDirs(t: PType) = when (t) { PType.ROOK -> rookDirs; PType.BISHOP -> bishopDirs; PType.QUEEN -> rookDirs + bishopDirs; else -> null }

    /** Occupied squares reachable from (r, c) by `type` on the live board. */
    fun reachableCaptures(r: Int, c: Int, type: PType, n: Int, occupied: Set<Int>): Set<Int> {
        fun inb(rr: Int, cc: Int) = rr in 0 until n && cc in 0 until n
        fun occ(rr: Int, cc: Int) = (rr * n + cc) in occupied
        val res = HashSet<Int>()
        when (type) {
            PType.KING -> for ((dr, dc) in kingDirs) if (inb(r + dr, c + dc) && occ(r + dr, c + dc)) res.add((r + dr) * n + c + dc)
            PType.KNIGHT -> for ((dr, dc) in knightJumps) if (inb(r + dr, c + dc) && occ(r + dr, c + dc)) res.add((r + dr) * n + c + dc)
            else -> for ((dr, dc) in slideDirs(type)!!) {
                var rr = r + dr; var cc = c + dc
                while (inb(rr, cc)) { if (occ(rr, cc)) { res.add(rr * n + cc); break }; rr += dr; cc += dc }
            }
        }
        return res
    }

    /** Empty squares from which `type` could have moved to `q` — the generator's inverse move. */
    private fun sourcesThatReach(q: Int, type: PType, n: Int, occ: Set<Int>): List<Int> {
        val qr = q / n; val qc = q % n
        fun inb(rr: Int, cc: Int) = rr in 0 until n && cc in 0 until n
        fun empty(rr: Int, cc: Int) = (rr * n + cc) !in occ
        val res = mutableListOf<Int>()
        when (type) {
            PType.KING -> for ((dr, dc) in kingDirs) if (inb(qr + dr, qc + dc) && empty(qr + dr, qc + dc)) res.add((qr + dr) * n + qc + dc)
            PType.KNIGHT -> for ((dr, dc) in knightJumps) if (inb(qr + dr, qc + dc) && empty(qr + dr, qc + dc)) res.add((qr + dr) * n + qc + dc)
            else -> for ((dr, dc) in slideDirs(type)!!) {
                var rr = qr + dr; var cc = qc + dc
                while (inb(rr, cc) && empty(rr, cc)) { res.add(rr * n + cc); rr += dr; cc += dc }
            }
        }
        return res
    }

    private class Gen(var sq: Int, val type: PType, var budget: Int)

    fun generate(n: Int, target: Int, types: List<PType>): List<SoloPiece> {
        var best = listOf<Gen>()
        repeat(60) {
            val list = mutableListOf(Gen(Random.nextInt(n * n), types.pick(), 2))
            val occ = hashSetOf(list[0].sq)
            var guard = 0
            while (list.size < target && guard < target * 40) {
                guard++
                var didUndo = false
                for (mi in list.indices.filter { list[it].budget >= 1 }.shuffled()) {
                    val q = list[mi].sq
                    val s = sourcesThatReach(q, list[mi].type, n, occ).shuffled().firstOrNull() ?: continue
                    list[mi].sq = s; list[mi].budget--
                    list.add(Gen(q, types.pick(), listOf(0, 1, 1, 2).pick()))
                    occ.add(s)
                    didUndo = true
                    break
                }
                if (!didUndo) break
            }
            if (list.size >= target) return convert(list, n)
            if (list.size > best.size) best = list.toList()
        }
        return convert(best, n)
    }

    private fun convert(list: List<Gen>, n: Int) = list.mapIndexed { i, g -> SoloPiece(i, g.sq / n, g.sq % n, g.type, 0) }
}

private val demoPieces = listOf(SoloPiece(0, 0, 0, PType.KING, 0), SoloPiece(1, 0, 3, PType.ROOK, 0), SoloPiece(2, 2, 1, PType.KNIGHT, 0))
private val demoTaps = listOf(2, 0, 1, 2)

@Composable
private fun ChessSweepView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val timeLimit = ChessSweepGame.timeLimit(level)
    var playing by remember { mutableStateOf(true) }
    var ready by remember { mutableStateOf(false) }
    var n by remember { mutableIntStateOf(0) }
    var pieces by remember { mutableStateOf(listOf<SoloPiece>()) }
    var selectedID by remember { mutableStateOf<Int?>(null) }
    var timeLeft by remember { mutableDoubleStateOf(timeLimit) }
    var demoTapSq by remember { mutableStateOf<Int?>(null) }
    var lastMove by remember { mutableStateOf(listOf<Int>()) }
    var moveAnim by remember { mutableStateOf<Triple<Int, Int, Double>?>(null) }   // (piece id, from square, t0)
    val scope = rememberCoroutineScope()
    val tm = rememberTextMeasurer()
    val handP = rememberHand()
    val anim by rememberFrameLoop(running = moveAnim != null)
    val dens = androidx.compose.ui.platform.LocalDensity.current.density.toDouble()

    fun targets(p: SoloPiece): Set<Int> = SoloGen.reachableCaptures(p.r, p.c, p.type, n, pieces.map { it.r * n + it.c }.toSet())
    fun win() { if (!playing) return; playing = false; onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }
    fun deadFail() {
        if (!playing) return
        playing = false
        SoundManager.error(); Haptics.warning()
        scope.launch { delay(400); onFail() }
    }

    fun tap(id: Int) {
        if (!playing) return
        val target = pieces.firstOrNull { it.id == id } ?: return
        val sel = selectedID?.let { s -> pieces.firstOrNull { it.id == s } }
        if (sel != null && sel.id != id && (target.r * n + target.c) in targets(sel)) {
            lastMove = listOf(sel.r * n + sel.c, target.r * n + target.c)
            moveAnim = Triple(sel.id, sel.r * n + sel.c, nowSec())
            pieces = pieces.filter { it.id != id }.map { if (it.id == sel.id) it.copy(r = target.r, c = target.c, movesMade = it.movesMade + 1) else it }
            selectedID = null
            SoundManager.tap(); Haptics.tap()
            if (pieces.size == 1) { win(); return }
            if (pieces.filter { it.movesMade < 2 }.all { targets(it).isEmpty() }) deadFail()
            return
        }
        if (selectedID == id) { selectedID = null; return }
        if (target.movesMade < 2) { selectedID = id; SoundManager.tap() } else { selectedID = null; SoundManager.error() }
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (isActive) {
                n = 4; pieces = demoPieces; selectedID = null; demoTapSq = null; lastMove = emptyList()
                timeLeft = timeLimit; playing = true; ready = true
                delay(900)
                for (id in demoTaps) {
                    val p = pieces.firstOrNull { it.id == id } ?: continue
                    demoTapSq = p.r * n + p.c
                    delay(300); tap(id); delay(550)
                }
                demoTapSq = null
                delay(1300)
            }
        } else {
            val t0 = System.currentTimeMillis()
            val built = BoardCache.take(ChessSweepGame.key(level)) {
                SoloGen.generate(ChessSweepGame.boardN(level), ChessSweepGame.targetCount(level), ChessSweepGame.allowedTypes(level))
            }
            BoardCache.holdBrainstorm(t0, 0.7)
            n = ChessSweepGame.boardN(level); pieces = built; selectedID = null
            ready = true; playing = true; timeLeft = timeLimit
            val start = nowSec()
            while (isActive && playing) {
                delay(50)
                timeLeft = max(0.0, timeLimit - (nowSec() - start))
                if (timeLeft <= 0) { fail(); break }
            }
        }
    }

    if (!ready) { BrainstormingView(panel, panelDeep); return }

    BoxWithConstraints(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .background(panel).padding(vertical = if (isDemo) 4.dp else 10.dp),
        contentAlignment = Alignment.Center
    ) {
        val hudH = if (isDemo) 22.dp else 40.dp
        val gap = if (isDemo) 2.dp else 6.dp
        val s = maxOf(40.dp, minOf(maxWidth, maxHeight - hudH - gap))
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(gap)) {
            Row(Modifier.size(s - 12.dp, hudH), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (isDemo) Spacer(Modifier.weight(1f))
                Icon(Icons.Filled.Apps, null, tint = green, modifier = Modifier.size(if (isDemo) 16.dp else 20.dp))
                Text(L("${pieces.size} LEFT", "CÒN ${pieces.size}"), style = ts(if (isDemo) 15.0 else 20.0, FontWeight.ExtraBold))
                Spacer(Modifier.weight(1f))
                if (!isDemo) Clock(timeLeft, timeLimit)
            }
            Canvas(Modifier.size(s).then(if (isDemo) Modifier else Modifier.tapIn(n) { p, w, h ->
                val side = min(w, h) - 12 * dens
                val cell = if (n > 0) side / n else 0.0
                val ox = (w - cell * n) / 2; val oy = (h - cell * n) / 2
                if (cell <= 0) return@tapIn
                val c = floor((p.x - ox) / cell).toInt(); val r = floor((p.y - oy) / cell).toInt()
                pieces.firstOrNull { it.r == r && it.c == c }?.let { tap(it.id) }
            })) {
                anim
                val w = size.width.toDouble(); val h = size.height.toDouble(); val u = density.toDouble()
                val side = min(w, h) - 12 * u
                val cell = if (n > 0) side / n else 0.0
                val ox = (w - cell * n) / 2; val oy = (h - cell * n) / 2
                val sel = selectedID?.let { id -> pieces.firstOrNull { it.id == id } }
                val tg = sel?.let { targets(it) } ?: emptySet()
                val marked = (lastMove + listOfNotNull(sel?.let { it.r * n + it.c })).toSet()
                board(tm, n, cell, ox, oy, marked, tg)
                val now = nowSec()
                for (p in pieces) {
                    var px = p.c.toDouble(); var py = p.r.toDouble()
                    val ma = moveAnim
                    if (ma != null && ma.first == p.id) {
                        val k = clamp((now - ma.third) / 0.18, 0.0, 1.0)
                        val e = 1 - (1 - k) * (1 - k)
                        px = lerp((ma.second % n).toDouble(), px, e); py = lerp((ma.second / n).toDouble(), py, e)
                        if (k >= 1) moveAnim = null
                    }
                    val x = ox + px * cell; val y = oy + py * cell
                    piece(p.type, p.movesMade >= 2, x + cell * 0.025, y + cell * 0.025, cell * 0.95)
                    if (p.movesMade == 1) {
                        val bx = x + cell * 0.83; val by = y + cell * 0.17; val br = cell * 0.135
                        circle(bx, by, br, panelDeep)
                        circleStroke(bx, by, br, Color.White.op(0.9), max(u, cell * 0.02))
                        text(tm, "1", bx, by, cell * 0.17, Color.White, FontWeight.ExtraBold)
                    }
                }
                demoTapSq?.let { sq -> val hs = cell * 0.42; hand(handP, ox + (sq % n + 0.78) * cell - hs * 0.3, oy + (sq / n + 0.84) * cell - hs * 0.2, hs) }
            }
        }
    }
}

/** The time limit as a Chess.com clock: white while there's time, red once it runs low. */
@Composable
private fun Clock(timeLeft: Double, timeLimit: Double) {
    val low = timeLimit > 0 && timeLeft / timeLimit < 0.3
    val secs = ceil(timeLeft).toInt()
    val fg = if (low) Color.White else panelDeep
    Row(Modifier.background(if (low) lowClock else clockFace, RoundedCornerShape(6.dp)).padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
        Icon(Icons.Filled.Schedule, null, tint = fg, modifier = Modifier.size(16.dp))
        Text("%d:%02d".format(secs / 60, secs % 60), style = ts(22.0, FontWeight.Bold, fg).copy(fontFeatureSettings = "tnum"))
    }
}

// Chess.com look (iOS SoloArt / SoloBoard).

private val lightSq = rgb(0.933, 0.933, 0.824)
private val darkSq = rgb(0.463, 0.588, 0.337)
private val highlight = rgb(1.0, 1.0, 0.2, 0.5)
private val panel = rgb(0.192, 0.180, 0.169)
private val panelDeep = rgb(0.149, 0.141, 0.129)
private val green = rgb(0.506, 0.714, 0.298)
private val whiteBody = rgb(0.99, 0.99, 0.98)
private val whiteShade = rgb(0.84, 0.84, 0.82)
private val blackBody = rgb(0.27, 0.26, 0.25)
private val blackHi = rgb(0.42, 0.41, 0.4)
private val inkC = rgb(0.2, 0.19, 0.18)
private val clockFace = rgb(0.97, 0.97, 0.96)
private val lowClock = rgb(0.85, 0.23, 0.2)

private fun DrawScope.board(tm: TextMeasurer, n: Int, cell: Double, ox: Double, oy: Double, marked: Set<Int>, targets: Set<Int>) {
    if (n <= 0) return
    val u = density.toDouble()
    val bw = cell * n
    blurRRect(ox, oy + 4 * u, bw, bw, 4 * u, Color.Black.op(0.45), 8 * u)
    rrect(ox, oy, bw, bw, 4 * u, darkSq)
    clipPath(Path().apply { addRoundRect(androidx.compose.ui.geometry.RoundRect(ox.f, oy.f, (ox + bw).f, (oy + bw).f, (4 * u).f, (4 * u).f)) }) {
        for (r in 0 until n) for (c in 0 until n) {
            val x = ox + c * cell; val y = oy + r * cell
            rect(x - 0.3, y - 0.3, cell + 0.6, cell + 0.6, if ((r + c) % 2 == 1) darkSq else lightSq)
            if ((r * n + c) in marked) rect(x, y, cell, cell, highlight)
        }
    }
    val fs = cell * 0.17
    for (r in 0 until n) text(tm, "${n - r}", ox + cell * 0.05, oy + r * cell + cell * 0.04, fs, if (r % 2 == 1) lightSq else darkSq,
        FontWeight.Bold, anchorX = 0.0, anchorY = 0.0)
    val files = "abcdefgh"
    for (c in 0 until min(n, files.length)) text(tm, files[c].toString(), ox + (c + 1) * cell - cell * 0.05, oy + n * cell - cell * 0.02, fs,
        if ((n - 1 + c) % 2 == 1) lightSq else darkSq, FontWeight.Bold, anchorX = 1.0, anchorY = 1.0)
    for (t in targets) circleStroke(ox + (t % n + 0.5) * cell, oy + (t / n + 0.5) * cell, cell * 0.43, Color.Black.op(0.17), cell * 0.1)
}

/** Chunky "neo"-style Staunton pieces in a square at (x, y) of side s. */
private fun DrawScope.piece(t: PType, black: Boolean, x: Double, y: Double, s: Double) {
    fun px(fx: Double) = x + fx * s
    fun py(fy: Double) = y + fy * s
    val fill: Brush = if (black) hgrad(listOf(blackHi, blackBody), px(0.3), px(0.78)) else hgrad(listOf(whiteBody, whiteShade), px(0.4), px(0.82))
    val line = if (black) rgb(0.08, 0.08, 0.07) else inkC
    val lw = s * 0.045
    fun part(p: Path) { drawPath(p, fill); strokePath(p, line, lw) }
    fun box(x0: Double, y0: Double, x1: Double, y1: Double, rad: Double) = Path().apply {
        addRoundRect(androidx.compose.ui.geometry.RoundRect(px(x0).f, py(y0).f, px(x1).f, py(y1).f, (rad * s).f, (rad * s).f))
    }
    fun poly(vararg pts: Pair<Double, Double>) = polyPath(pts.map { P(px(it.first), py(it.second)) })
    fun ball(bx: Double, by: Double, rad: Double) = Path().apply {
        addOval(androidx.compose.ui.geometry.Rect(px(bx - rad).f, py(by - rad).f, px(bx + rad).f, py(by + rad).f))
    }
    fun waist(top: Double, halfTop: Double) = Path().apply {
        m(px(0.5 - halfTop), py(top)); q(px(0.5 - halfTop + 0.01), py(0.66), px(0.3), py(0.75))
        l(px(0.7), py(0.75)); q(px(0.5 + halfTop - 0.01), py(0.66), px(0.5 + halfTop), py(top)); close()
    }
    part(box(0.19, 0.8, 0.81, 0.91, 0.035))
    part(box(0.25, 0.735, 0.75, 0.81, 0.03))
    when (t) {
        PType.ROOK -> {
            part(poly(0.33 to 0.42, 0.67 to 0.42, 0.7 to 0.74, 0.3 to 0.74))
            part(box(0.27, 0.36, 0.73, 0.43, 0.02))
            part(poly(0.25 to 0.13, 0.37 to 0.13, 0.37 to 0.21, 0.44 to 0.21, 0.44 to 0.13, 0.56 to 0.13,
                0.56 to 0.21, 0.63 to 0.21, 0.63 to 0.13, 0.75 to 0.13, 0.75 to 0.365, 0.25 to 0.365))
        }
        PType.BISHOP -> {
            part(Path().apply { m(px(0.41), py(0.6)); q(px(0.41), py(0.7), px(0.3), py(0.75)); l(px(0.7), py(0.75)); q(px(0.59), py(0.7), px(0.59), py(0.6)); close() })
            part(box(0.32, 0.55, 0.68, 0.615, 0.032))
            part(ball(0.5, 0.135, 0.055))
            part(Path().apply {
                m(px(0.5), py(0.18))
                c(px(0.6), py(0.25), px(0.68), py(0.35), px(0.665), py(0.45))
                c(px(0.65), py(0.53), px(0.58), py(0.56), px(0.5), py(0.56))
                c(px(0.42), py(0.56), px(0.35), py(0.53), px(0.335), py(0.45))
                c(px(0.32), py(0.35), px(0.4), py(0.25), px(0.5), py(0.18))
                close()
            })
            line(px(0.57), py(0.3), px(0.47), py(0.42), line, lw)
        }
        PType.QUEEN -> {
            part(waist(0.5, 0.14))
            val tips = listOf(0.16 to 0.24, 0.33 to 0.18, 0.5 to 0.15, 0.67 to 0.18, 0.84 to 0.24)
            part(poly(0.3 to 0.52, tips[0], 0.35 to 0.39, tips[1], 0.45 to 0.37, tips[2], 0.55 to 0.37, tips[3], 0.65 to 0.39, tips[4], 0.7 to 0.52))
            for ((tx, ty) in tips) part(ball(tx, ty, 0.048))
            part(box(0.29, 0.47, 0.71, 0.54, 0.025))
        }
        PType.KING -> {
            part(waist(0.52, 0.14))
            part(box(0.465, 0.05, 0.535, 0.3, 0.012))
            part(box(0.4, 0.105, 0.6, 0.17, 0.012))
            part(Path().apply {
                m(px(0.33), py(0.51))
                c(px(0.2), py(0.45), px(0.15), py(0.31), px(0.27), py(0.27))
                c(px(0.37), py(0.22), px(0.46), py(0.25), px(0.5), py(0.33))
                c(px(0.54), py(0.25), px(0.63), py(0.22), px(0.73), py(0.27))
                c(px(0.85), py(0.31), px(0.8), py(0.45), px(0.67), py(0.51))
                close()
            })
            line(px(0.5), py(0.33), px(0.5), py(0.48), line, lw * 0.8)
            part(box(0.29, 0.48, 0.71, 0.55, 0.025))
        }
        PType.KNIGHT -> {
            part(Path().apply {
                m(px(0.71), py(0.74))
                c(px(0.77), py(0.58), px(0.77), py(0.4), px(0.67), py(0.3))
                c(px(0.63), py(0.22), px(0.59), py(0.16), px(0.53), py(0.13))
                l(px(0.5), py(0.05)); l(px(0.43), py(0.15))
                c(px(0.3), py(0.19), px(0.21), py(0.32), px(0.19), py(0.43))
                c(px(0.15), py(0.48), px(0.16), py(0.53), px(0.22), py(0.54))
                c(px(0.28), py(0.56), px(0.34), py(0.51), px(0.39), py(0.5))
                c(px(0.44), py(0.58), px(0.3), py(0.64), px(0.29), py(0.74))
                close()
            })
            strokePath(Path().apply { m(px(0.58), py(0.18)); c(px(0.71), py(0.3), px(0.73), py(0.5), px(0.66), py(0.66)) }, line.op(0.55), lw * 0.8)
            fillPath(ball(0.41, 0.3, 0.032), line)
            fillPath(ball(0.22, 0.475, 0.016), line)
        }
    }
}
