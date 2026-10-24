package com.gogs.bananagame.games.tiletrio

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

/**
 * Brain — Tile Trio (iOS TileTrioGame.swift, id "tile-trio"): tap free fruit tiles from layered
 * pyramids into a 7-slot tray; three alike pop. Clear the board to win; a full tray or the clock
 * fails. Boards are winnable by construction (kinds assigned along a legal uncovering order).
 */
object TileTrioGame {
    val definition = GameDefinition(
        id = "tile-trio",
        title = "Tile Trio",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Tap a free tile to move it into the tray; dimmed tiles are covered and can't be picked.",
                "Three matching tiles in the tray pop and free up space.",
                "Clear every tile from the board to win.",
                "If the tray fills with seven tiles, or time runs out, you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Chạm một ô trống để đưa vào khay; ô bị tối đang bị che và không chọn được.",
                "Ba ô giống nhau trong khay sẽ nổ và giải phóng chỗ.",
                "Dọn sạch mọi ô trên bàn để thắng.",
                "Nếu khay đầy bảy ô, hoặc hết giờ, bạn về lại cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> TileTrioView(level, onWin, onFail) }
    )
}

private const val SLOTS = 7

class TTTile(val id: Int, val x: Int, val y: Int, val z: Int, val kind: FruitKind)

object TTGen {
    /**
     * Base footprint in whole tiles, then one letter per upper layer: "o" = shifted half a tile
     * right+down (one tile smaller each way), "s" = an exact pile on the layer below.
     */
    class Params(val cols: Int, val rows: Int, val schedule: String, val count: Int, val kinds: Int, val maxLoad: Int, val pNew: Double)

    /** Kind order: clearly different fruit first, lookalikes join on later levels. */
    private val kindOrder = listOf(FruitKind.CHERRY, FruitKind.GRAPE, FruitKind.PEAR, FruitKind.MELON, FruitKind.DEKOPON, FruitKind.PEACH,
        FruitKind.WATERMELON, FruitKind.BANANA, FruitKind.STRAWBERRY, FruitKind.LEMON, FruitKind.APPLE, FruitKind.PINEAPPLE, FruitKind.PERSIMMON)

    fun overlaps(ax: Int, ay: Int, bx: Int, by: Int) = abs(ax - bx) < 2 && abs(ay - by) < 2

    private data class Pos(val x: Int, val y: Int, val z: Int)

    /** A symmetric layered pyramid following the schedule, trimmed symmetrically from the top layer. */
    private fun layout(p: Params): MutableList<Pos> {
        val pos = ArrayList<Pos>()
        var layer = ArrayList<Pair<Int, Int>>()
        for (y in 0 until p.rows) for (x in 0 until p.cols) layer.add(x * 2 to y * 2)
        pos.addAll(layer.map { Pos(it.first, it.second, 0) })
        for ((i, mode) in p.schedule.withIndex()) {
            if (mode == 'o') {
                // Every 2×2 block of the layer below gets a tile on its centre.
                val set = layer.toHashSet()
                layer = ArrayList(layer.filter { (x, y) -> (x + 2 to y) in set && (x to y + 2) in set && (x + 2 to y + 2) in set }.map { (x, y) -> x + 1 to y + 1 })
            }
            pos.addAll(layer.map { Pos(it.first, it.second, i + 1) })
        }
        val topZ = p.schedule.length
        val mirror = pos.minOf { it.x } + pos.maxOf { it.x }
        var guardCount = 0
        while (pos.size > p.count && guardCount < 200) {
            guardCount++
            val diff = pos.size - p.count
            val top = pos.indices.filter { pos[it].z == topZ }.shuffled()
            if (diff % 2 == 1) { val i = top.firstOrNull { pos[it].x * 2 == mirror }; if (i != null) { pos.removeAt(i); continue } }
            val i = top.firstOrNull { pos[it].x * 2 != mirror }
            if (i != null) {
                val j = pos.indexOfFirst { it.z == topZ && it.x == mirror - pos[i].x && it.y == pos[i].y }
                if (j >= 0) { pos.removeAt(max(i, j)); pos.removeAt(min(i, j)); continue }
            }
            val f = top.firstOrNull() ?: break
            pos.removeAt(f)
        }
        return pos
    }

    /** Assigns kinds along a random legal uncovering order so that order never loads the tray past maxLoad. */
    fun generate(p: Params): List<TTTile> {
        repeat(60) {
            val pos = layout(p)
            if (pos.size % 3 != 0 || pos.size < 3) return@repeat
            val remaining = pos.indices.toMutableList(); val order = ArrayList<Int>()
            while (remaining.isNotEmpty()) {
                val frees = remaining.filter { i -> remaining.none { j -> pos[j].z > pos[i].z && overlaps(pos[j].x, pos[j].y, pos[i].x, pos[i].y) } }
                val pick = frees.randomOrNull() ?: break
                order.add(pick); remaining.remove(pick)
            }
            if (order.size != pos.size) return@repeat
            val a = assign(order, kindOrder.take(p.kinds), p.maxLoad, p.pNew) ?: return@repeat
            return pos.indices.map { TTTile(it, pos[it].x, pos[it].y, pos[it].z, a[it]!!) }
        }
        return emptyList()
    }

    private class Open(val kind: FruitKind, var count: Int)

    private fun assign(order: List<Int>, kinds: List<FruitKind>, maxLoad: Int, pNew: Double): Map<Int, FruitKind>? {
        val n = order.size; val triples = n / 3
        val queue = (0 until triples).map { kinds[it % kinds.size] }.shuffled().toMutableList()
        val open = ArrayList<Open>()
        val result = HashMap<Int, FruitKind>()
        for ((i, tile) in order.withIndex()) {
            val left = n - i
            val need = open.sumOf { 3 - it.count }
            val load = open.sumOf { it.count }
            // Opening must never strand the plan at the cap with no pair left to finish.
            val canOpen = queue.isNotEmpty() && need + 3 <= left && (load + 1 < maxLoad || (load + 1 == maxLoad && open.any { it.count == 2 }))
            val continuable = open.indices.filter { open[it].count == 2 || load + 1 <= maxLoad }
            val wantNew = canOpen && (open.isEmpty() || Random.nextDouble() < pNew || continuable.isEmpty())
            if (wantNew && need < left) {
                // Prefer a kind that isn't already waiting in the tray.
                val k = queue.indexOfFirst { q -> open.none { it.kind == q } }.let { if (it < 0) 0 else it }
                val kind = queue.removeAt(k)
                result[tile] = kind; open.add(Open(kind, 1))
            } else {
                val j = continuable.randomOrNull() ?: return null
                result[tile] = open[j].kind
                open[j].count++
                if (open[j].count == 3) open.removeAt(j)
            }
        }
        return if (open.isEmpty() && queue.isEmpty()) result else null
    }

    fun params(level: Int) = listOf(
        Params(4, 3, "o", 18, 6, 3, 0.25), Params(4, 4, "oo", 27, 7, 4, 0.35), Params(5, 4, "oo", 36, 8, 4, 0.45),
        Params(4, 4, "osos", 42, 9, 5, 0.5), Params(5, 4, "oso", 48, 10, 5, 0.55), Params(5, 4, "osos", 54, 12, 6, 0.65),
        Params(5, 5, "ooso", 63, 13, 6, 0.75),
    )[min(level, 7) - 1]
}

private enum class TPhase { PLAY, WON, STUCK, DONE }
private class Fade(val tile: TTTile, val at: P, val size: Double, val t0: Double)
private class TBurst(val slot: Int, val color: Color, val t0: Double, val seed: Int)

private class Lay(w: Double, h: Double, demo: Boolean, u: Double, minX: Int, maxX: Int, minY: Int, maxY: Int, layers: Int) {
    val pad = (if (demo) 8 else 14) * u
    val statusH = (if (demo) 24 else 56) * u
    val slot = min((w - pad * 2 - 16 * u) / SLOTS, (if (demo) 40 else 54) * u)
    val trayH = slot + 16 * u
    val trayW = slot * SLOTS + 16 * u
    val trayX = (w - trayW) / 2
    val trayY = h - pad - trayH
    private val spanX = (maxX - minX + 2) / 2.0
    private val spanY = (maxY - minY + 2) / 2.0
    private val availH = trayY - statusH - pad * 1.5
    private val depth = max(0, layers - 1) * 0.05 + 0.1     // layer lift + tile thickness
    val tile = max(10 * u, min(min((w - pad * 2) / spanX, availH / (spanY + depth)), (if (demo) 58 else 88) * u))
    val ox = (w - tile * spanX) / 2 - minX * tile / 2
    val oy = statusH + pad * 0.5 + (availH - tile * (spanY + depth)) / 2 + max(0, layers - 1) * tile * 0.05 - minY * tile / 2
    val statusY = statusH / 2 + (if (demo) 4 else 6) * u
    val liftX = -0.03 * tile
    val liftY = -0.05 * tile
    fun boardPoint(t: TTTile) = P(ox + (t.x + 1) * tile / 2 + t.z * liftX, oy + (t.y + 1) * tile / 2 + t.z * liftY)
    private val unit = u
    fun trayPoint(i: Int) = P(trayX + 8 * unit + (min(i, SLOTS - 1) + 0.5) * slot, trayY + trayH / 2 - 2 * unit)
}

private class TrioWorld(val level: Int) {
    val timeLimit = listOf(60.0, 70.0, 80.0, 85.0, 90.0, 90.0, 90.0)[min(level, 7) - 1]
    var phase = TPhase.PLAY
    val board = mutableListOf<TTTile>()
    val tray = mutableListOf<TTTile>()
    val matching = HashSet<Int>()
    val converge = HashMap<Int, Int>()          // tile id → tile id it merges into
    var total = 0
    var timeLeft = timeLimit
    var ext = intArrayOf(0, 2, 0, 2, 1)
    // Presentation: each tile eases from where it was drawn when its target last changed.
    val from = HashMap<Int, P>()
    val fromT0 = HashMap<Int, Double>()
    val fromDur = HashMap<Int, Double>()
    val fades = mutableListOf<Fade>()
    val bursts = mutableListOf<TBurst>()
    var lay: Lay? = null

    fun load(tiles: List<TTTile>) {
        board.clear(); board.addAll(tiles); tray.clear(); matching.clear(); converge.clear()
        from.clear(); fromT0.clear(); fromDur.clear(); fades.clear(); bursts.clear()
        total = tiles.size
        ext = intArrayOf(tiles.minOfOrNull { it.x } ?: 0, tiles.maxOfOrNull { it.x } ?: 2, tiles.minOfOrNull { it.y } ?: 0,
            tiles.maxOfOrNull { it.y } ?: 2, (tiles.maxOfOrNull { it.z } ?: 0) + 1)
    }

    fun blockedIds(): Set<Int> = board.filter { a -> board.any { it.z > a.z && TTGen.overlaps(it.x, it.y, a.x, a.y) } }.map { it.id }.toSet()

    /** Where a tile should sit now (tray tiles of a popping trio slide onto its middle tile). */
    fun target(t: TTTile, l: Lay): P {
        var i = tray.indexOfFirst { it.id == t.id }
        if (i < 0) return l.boardPoint(t)
        converge[t.id]?.let { into -> val j = tray.indexOfFirst { it.id == into }; if (j >= 0) i = j }
        return l.trayPoint(i)
    }

    fun displayed(t: TTTile, l: Lay, now: Double): P {
        val to = target(t, l)
        val f = from[t.id] ?: return to
        val k = clamp((now - (fromT0[t.id] ?: 0.0)) / (fromDur[t.id] ?: 0.2), 0.0, 1.0)
        val e = 1 - (1 - k) * (1 - k)
        return P(f.x + (to.x - f.x) * e, f.y + (to.y - f.y) * e)
    }

    /** Record every tile's current drawn position so the next state change animates from it. */
    fun snapshot(dur: Double) {
        val l = lay ?: return
        val now = nowSec()
        for (t in board + tray) { from[t.id] = displayed(t, l, now); fromT0[t.id] = now; fromDur[t.id] = dur }
    }

    fun tap(id: Int, launch: (suspend () -> Unit) -> Unit) {
        if (phase != TPhase.PLAY) return
        val idx = board.indexOfFirst { it.id == id }
        if (idx < 0 || id in blockedIds()) return
        val t = board[idx]
        SoundManager.tap(); Haptics.tap()
        // Land next to its twins (the tray keeps matching tiles together).
        val last = tray.indexOfLast { it.kind == t.kind && it.id !in matching }
        snapshot(0.2)
        board.removeAt(idx)
        tray.add(if (last >= 0) last + 1 else tray.size, t)
        val twins = tray.filter { it.kind == t.kind && it.id !in matching }
        if (twins.size >= 3) {
            val trio = twins.take(3)
            val ids = trio.map { it.id }.toSet()
            matching.addAll(ids)
            launch {
                delay(200)
                snapshot(0.12)
                for (x in trio) converge[x.id] = trio[1].id
                delay(130)
                val l = lay
                val slot = tray.indexOfFirst { it.id == trio[1].id }.coerceAtLeast(0)
                bursts.add(TBurst(slot, FruitArt.color(t.kind), nowSec(), trio[1].id))
                if (l != null) for (x in trio) fades.add(Fade(x, displayed(x, l, nowSec()), l.slot * 0.9, nowSec()))
                snapshot(0.22)
                tray.removeAll { it.id in ids }
                matching.removeAll(ids)
                for (x in trio) converge.remove(x.id)
                SoundManager.tap(); Haptics.success()
            }
        } else if (tray.size - matching.size >= SLOTS) {
            phase = TPhase.STUCK
            Haptics.warning()
        }
    }

    fun prune() {
        val now = nowSec()
        fades.removeAll { now - it.t0 > 0.25 }
        bursts.removeAll { now - it.t0 > 0.6 }
    }
}

private val demoTiles = listOf(
    TTTile(0, 1, 1, 1, FruitKind.CHERRY), TTTile(1, 3, 1, 1, FruitKind.GRAPE), TTTile(2, 2, 3, 1, FruitKind.GRAPE),
    TTTile(3, 0, 0, 0, FruitKind.MELON), TTTile(4, 2, 0, 0, FruitKind.MELON), TTTile(5, 4, 0, 0, FruitKind.DEKOPON),
    TTTile(6, 0, 2, 0, FruitKind.CHERRY), TTTile(7, 2, 2, 0, FruitKind.GRAPE), TTTile(8, 4, 2, 0, FruitKind.DEKOPON),
    TTTile(9, 0, 4, 0, FruitKind.CHERRY), TTTile(10, 2, 4, 0, FruitKind.DEKOPON), TTTile(11, 4, 4, 0, FruitKind.MELON),
)
private val demoOrder = listOf(0, 1, 9, 6, 2, 7, 3, 4, 11, 5, 8, 10)

@Composable
private fun TileTrioView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { TrioWorld(level) }
    val scope = rememberCoroutineScope()
    val tm = rememberTextMeasurer()
    val handP = rememberHand()
    val dens = LocalDensity.current.density.toDouble()
    val area = remember { doubleArrayOf(0.0, 0.0) }
    val demo = remember { object { var tap: Int? = null; var tapAt = -10.0 } }
    val tick by rememberFrameLoop()
    val launcher: (suspend () -> Unit) -> Unit = { block -> scope.launch { block() } }

    fun fail() {
        if (world.phase != TPhase.PLAY && world.phase != TPhase.STUCK) return
        world.phase = TPhase.DONE; SoundManager.error(); onFail()
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (isActive) {
                world.load(demoTiles); demo.tap = null; world.phase = TPhase.PLAY
                delay(700)
                for (id in demoOrder) { demo.tap = id; demo.tapAt = nowSec(); delay(220); world.tap(id, launcher); demo.tap = null; delay(300) }
                delay(1500)
            }
        } else {
            val tiles = withContext(Dispatchers.Default) { TTGen.generate(TTGen.params(level)) }
            world.load(tiles)
            world.phase = TPhase.PLAY; world.timeLeft = world.timeLimit
            val start = nowSec()
            while (isActive) {
                delay(50)
                world.prune()
                when (world.phase) {
                    TPhase.PLAY -> {
                        world.timeLeft = max(0.0, world.timeLimit - (nowSec() - start))
                        if (world.board.isEmpty() && world.tray.isEmpty() && world.total > 0) world.phase = TPhase.WON
                        else if (world.timeLeft <= 0) { fail(); return@LaunchedEffect }
                    }
                    TPhase.WON -> { delay(300); world.phase = TPhase.DONE; onWin(); return@LaunchedEffect }
                    TPhase.STUCK -> { delay(800); fail(); return@LaunchedEffect }
                    TPhase.DONE -> return@LaunchedEffect
                }
            }
        }
    }
    if (isDemo) LaunchedEffect(Unit) { while (isActive) { delay(50); world.prune() } }

    Canvas(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .onSizeChanged { area[0] = it.width.toDouble(); area[1] = it.height.toDouble() }
            .then(if (isDemo) Modifier else Modifier.tapAt { p ->
                val l = world.lay ?: return@tapAt
                val now = nowSec()
                // Topmost board tile under the finger.
                world.board.sortedByDescending { it.z * 1000 + it.y * 10 + it.x }.firstOrNull { t ->
                    val c = world.displayed(t, l, now); abs(p.x - c.x) <= l.tile / 2 && abs(p.y - c.y) <= l.tile / 2
                }?.let { world.tap(it.id, launcher) }
            })
    ) {
        tick
        val u = density.toDouble()
        val e = world.ext
        val l = Lay(size.width.toDouble(), size.height.toDouble(), isDemo, u, e[0], e[1], e[2], e[3], e[4])
        world.lay = l
        val now = nowSec()
        rect(0.0, 0.0, size.width.toDouble(), size.height.toDouble(), vgrad(listOf(rgb(0.40, 0.76, 0.74), rgb(0.16, 0.49, 0.55)), 0.0, size.height.toDouble()))
        statusBar(world, l, tm, isDemo)
        trayArt(l)
        val blocked = world.blockedIds()
        for (t in world.board.sortedBy { it.z * 1000 + it.y * 10 + it.x }) { val p = world.displayed(t, l, now); tile(t.kind, p.x, p.y, l.tile, t.id in blocked) }
        for (t in world.tray) { val p = world.displayed(t, l, now); tile(t.kind, p.x, p.y, l.slot * 0.9, false) }
        for (f in world.fades) {
            val k = clamp((now - f.t0) / 0.22, 0.0, 1.0)
            withAlpha(1 - k) { scale((1 + 0.35 * k).f, (1 + 0.35 * k).f, off(f.at.x, f.at.y)) { tile(f.tile.kind, f.at.x, f.at.y, f.size, false) } }
        }
        for (b in world.bursts) { val p = l.trayPoint(b.slot); particleBurst(p.x, p.y, now - b.t0, b.color, 16, l.slot * 1.3 / u, 6.0, b.seed) }
        demo.tap?.let { id ->
            world.board.firstOrNull { it.id == id }?.let { t ->
                val p = l.boardPoint(t)
                tapRipple(p.x, p.y, now - demo.tapAt)
                val s = l.tile * 0.5
                hand(handP, p.x + l.tile * 0.2 - s / 2, p.y + l.tile * 0.3 - s / 2, s)
            }
        }
    }
}

// Art (Tile Master style).

private fun DrawScope.statusBar(world: TrioWorld, l: Lay, tm: TextMeasurer, isDemo: Boolean) {
    val u = density.toDouble(); val w = size.width.toDouble()
    var y = l.statusY
    if (!isDemo) {
        val f = if (world.timeLimit > 0) world.timeLeft / world.timeLimit else 0.0
        val by = y - 18 * u
        rrect(40 * u, by, w - 80 * u, 6 * u, 3 * u, Color.Black.op(0.18))
        rrect(40 * u, by, (w - 80 * u) * clamp(f, 0.0, 1.0), 6 * u, 3 * u, if (f < 0.3) Color.Red else BananaTheme.banana)
        y += 8 * u
    }
    val fs = (if (isDemo) 15 else 20) * u
    val sq = (if (isDemo) 11 else 14) * u
    val s = "${world.board.size + world.tray.size - world.matching.size}"
    val tw = textWidth(tm, s, fs, FontWeight.Black)
    val x0 = (w - (sq + 6 * u + tw)) / 2
    rrect(x0, y - sq / 2, sq, sq, 3 * u, rgb(1.0, 0.97, 0.9))
    rrectStroke(x0, y - sq / 2, sq, sq, 3 * u, rgb(0.29, 0.6, 0.44), 2 * u)
    text(tm, s, x0 + sq + 6 * u, y + 1.5 * u, fs, Color.Black.op(0.25), FontWeight.Black, anchorX = 0.0)
    text(tm, s, x0 + sq + 6 * u, y, fs, Color.White, FontWeight.Black, anchorX = 0.0)
}

/** The wooden 7-slot tray. */
private fun DrawScope.trayArt(l: Lay) {
    val u = density.toDouble()
    blurRRect(l.trayX, l.trayY + 4 * u, l.trayW, l.trayH, 16 * u, Color.Black.op(0.3), 6 * u)
    rrect(l.trayX, l.trayY, l.trayW, l.trayH, 16 * u, vgrad(listOf(rgb(0.55, 0.36, 0.2), rgb(0.38, 0.23, 0.12)), l.trayY, l.trayY + l.trayH))
    rrectStroke(l.trayX, l.trayY, l.trayW, l.trayH, 16 * u, rgb(0.26, 0.15, 0.07), 3 * u)
    for (i in 0 until SLOTS) {
        val x = l.trayX + 8 * u + i * l.slot + 3 * u; val y = l.trayY + (l.trayH - l.slot) / 2 + 3 * u; val s = l.slot - 6 * u
        rrect(x, y, s, s, 9 * u, rgb(0.3, 0.18, 0.09, 0.75))
        rrectStroke(x, y, s, s, 9 * u, Color.Black.op(0.25), u)
    }
}

/** A mahjong-style tile: green base peeking out below a cream face with the fruit; covered tiles dim. */
private fun DrawScope.tile(kind: FruitKind, cx: Double, cy: Double, s: Double, blocked: Boolean) {
    val r = s * 0.17
    val x = cx - s / 2; val y = cy - s / 2
    blurRRect(x, y + s * 0.12, s, s + s * 0.1, r, Color.Black.op(0.28), s * 0.05)
    rrect(x, y + s * 0.1, s, s, r, vgrad(listOf(rgb(0.36, 0.7, 0.5), rgb(0.2, 0.5, 0.36)), y + s * 0.1, y + s * 1.1))
    rrect(x, y, s, s, r, vgrad(listOf(rgb(1.0, 0.99, 0.95), rgb(0.95, 0.91, 0.8)), y, y + s))
    rrectStroke(x, y, s, s, r, rgb(0.82, 0.74, 0.58), max(density.toDouble(), s * 0.025))
    val fr = s * 0.92 * 0.33
    FruitArt.draw(this, kind, cx, cy + fr * 0.12, fr)
    if (blocked) {
        rrect(x, y, s, s * 1.1, r, gray(0.35, 0.3))
        rrect(x, y, s, s * 1.1, r, Color.Black.op(0.3))
    }
}
