package com.gogs.bananagame.games.decoy

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.SettingsInputAntenna
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Brain — Decoy (iOS DecoyGame.swift, id "decoy"): d-pad the banana across a guarded room to the
 * exit; walk into a vision cone and you're caught. Tap to lob a noise decoy and the nearest patrolling
 * guard leaves its route to investigate. Decoys are limited and the clock runs. Soliton-radar look.
 */
object DecoyGame {
    val definition = GameDefinition(
        id = "decoy",
        title = "Decoy",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Steer with the d-pad to reach the exit.",
                "Guards sweep vision cones — get caught in one and you're back to level 1.",
                "Tap anywhere to throw a noise decoy: the nearest guard leaves its route to investigate.",
                "It looks around, then returns; decoys are limited, so beat the clock.",
            ),
            bulletsVI = listOf(
                "Điều khiển bằng d-pad để đến lối ra.",
                "Lính gác quét tầm nhìn — bị bắt trong một tầm nhìn là bạn về cấp 1.",
                "Chạm bất kỳ đâu để ném mồi nhử tiếng động: lính gần nhất rời tuyến đi kiểm tra.",
                "Nó nhìn quanh rồi quay lại; mồi nhử có hạn, nên hãy chạy đua với đồng hồ.",
            ),
            liveDemo = true
        ),
        prefetch = { level -> BoardCache.prefetch(key(level)) { DecoyGen.generate(4 + level, guardCount(level)) } },
        content = { level, onWin, onFail -> DecoyView(level, onWin, onFail) }
    )

    fun key(level: Int) = BoardCache.key("decoy", level)
    fun guardCount(level: Int) = listOf(3, 4, 5, 6, 7, 8, 10)[min(level, 7) - 1]
}

private const val COLS = 13
private const val ROWS = 17
private const val PLAYER_SPEED = 3.7

data class DCell(val r: Int, val c: Int)
private fun center(p: DCell) = P(p.c + 0.5, p.r + 0.5)
private fun manhattan(a: DCell, b: DCell) = abs(a.r - b.r) + abs(a.c - b.c)

class DecoyBoard(val walls: List<BooleanArray>, val paths: List<List<DCell>>, val start: DCell, val exit: DCell)

private class Guard(val path: List<DCell>) {
    var x = center(path[0]).x; var y = center(path[0]).y
    var idx = 0; var dir = 1
    var facing = if (path.size >= 2) atan2(center(path[1]).y - center(path[0]).y, center(path[1]).x - center(path[0]).x) else 0.0
    var investigating = false
    var lureX = 0.0; var lureY = 0.0
    var hold = 0.0
}

object DecoyGen {
    fun generate(coverBlocks: Int, guardCount: Int): DecoyBoard {
        val w = List(ROWS) { BooleanArray(COLS) }
        for (r in 0 until ROWS) { w[r][0] = true; w[r][COLS - 1] = true }
        for (c in 0 until COLS) { w[0][c] = true; w[ROWS - 1][c] = true }
        var placed = 0; var tries = 0
        while (placed < coverBlocks && tries < 300) {
            tries++
            val bw = rndInt(1..3); val bh = rndInt(1..3)
            val c0 = rndInt(2..(COLS - 2 - bw)); val r0 = rndInt(2..(ROWS - 2 - bh))
            var ok = true
            for (r in (r0 - 1)..(r0 + bh)) for (c in (c0 - 1)..(c0 + bw)) if (w[r][c]) ok = false
            if (!ok) continue
            for (r in r0 until r0 + bh) for (c in c0 until c0 + bw) w[r][c] = true
            placed++
        }
        val open = (0 until ROWS).flatMap { r -> (0 until COLS).mapNotNull { c -> if (w[r][c]) null else DCell(r, c) } }
        fun neighbours(p: DCell) = listOf(DCell(p.r - 1, p.c), DCell(p.r + 1, p.c), DCell(p.r, p.c - 1), DCell(p.r, p.c + 1))
            .filter { it.r in 0 until ROWS && it.c in 0 until COLS && !w[it.r][it.c] }
        fun bfsPath(s: DCell, goal: DCell): List<DCell> {
            val prev = HashMap<DCell, DCell>(); val seen = hashSetOf(s); val q = ArrayList<DCell>(); q.add(s); var head = 0
            while (head < q.size) {
                val cur = q[head++]
                if (cur == goal) break
                for (n in neighbours(cur)) if (seen.add(n)) { prev[n] = cur; q.add(n) }
            }
            val path = ArrayList<DCell>(); var cur: DCell? = goal
            while (cur != null) { path.add(cur); if (cur == s) break; cur = prev[cur] }
            return path.reversed()
        }
        val startCell = open.minByOrNull { manhattan(it, DCell(1, 1)) } ?: DCell(1, 1)
        val corner = DCell(ROWS - 2, COLS - 2)
        val exitCell = open.filter { it != startCell }.minByOrNull { manhattan(it, corner) } ?: corner
        // Guards patrol the middle band, between the player and the exit.
        val starts = ArrayList<DCell>()
        for (cand in open.shuffled()) {
            if (manhattan(cand, startCell) < 4 || cand == exitCell) continue
            if (starts.all { manhattan(it, cand) >= 3 }) { starts.add(cand); if (starts.size == guardCount) break }
        }
        while (starts.size < guardCount && open.isNotEmpty()) starts.add(open.pick())
        val paths = starts.map { s ->
            var path = listOf(s, neighbours(s).firstOrNull() ?: s)
            for (goal in open.shuffled()) {
                if (goal == s) continue
                val p = bfsPath(s, goal)
                if (p.size >= 5) { path = p; break }
            }
            path
        }
        return DecoyBoard(w, paths, startCell, exitCell)
    }
}

private class DecoyWorld(val level: Int) {
    private val li = min(level, 7) - 1
    val patrolSpeed = listOf(1.3, 1.5, 1.7, 1.9, 2.1, 2.4, 2.7)[li]
    val visionRange = listOf(3.4, 3.8, 4.2, 4.6, 5.0, 5.4, 5.8)[li]
    val visionHalf = listOf(24.0, 28.0, 32.0, 36.0, 40.0, 44.0, 48.0)[li] * PI / 180
    val decoyBudget = listOf(5, 4, 4, 3, 2, 2, 1)[li]
    val investigateHold = listOf(2.6, 2.4, 2.2, 2.0, 1.8, 1.6, 1.4)[li]
    val timeLimit = (34 - level).toDouble()

    var playing = true
    var walls: List<BooleanArray> = emptyList()
    var mapVersion by mutableIntStateOf(0)
    var guards = listOf<Guard>()
    var px = 1.5; var py = 1.5
    var exit = DCell(1, 1)
    var mdx = 0.0; var mdy = 0.0
    var decoys = 0
    var timeLeft = timeLimit
    var t = 0.0
    var pulse = 0.0
    var caught = false
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    fun commit(b: DecoyBoard) {
        walls = b.walls; mapVersion++
        guards = b.paths.map { Guard(it) }
        exit = b.exit
        px = b.start.c + 0.5; py = b.start.r + 0.5
        decoys = decoyBudget; mdx = 0.0; mdy = 0.0
        timeLeft = timeLimit; t = 0.0; pulse = 0.0; caught = false; playing = true
    }

    fun isWall(r: Int, c: Int) = r !in 0 until ROWS || c !in 0 until COLS || walls.size != ROWS || walls[r][c]
    fun canStand(x: Double, y: Double): Boolean {
        val rad = 0.28
        for (cx in listOf(x - rad, x + rad)) for (cy in listOf(y - rad, y + rad)) if (isWall(floor(cy).toInt(), floor(cx).toInt())) return false
        return true
    }
    private fun losClear(ax: Double, ay: Double, bx: Double, by: Double): Boolean {
        val steps = (hypot(bx - ax, by - ay) / 0.15).toInt() + 1
        for (i in 0..steps) {
            val k = i.toDouble() / steps
            if (isWall(floor(ay + (by - ay) * k).toInt(), floor(ax + (bx - ax) * k).toInt())) return false
        }
        return true
    }
    fun spots(g: Guard): Boolean {
        val dx = px - g.x; val dy = py - g.y
        val d = hypot(dx, dy)
        if (d > visionRange || d <= 0.0001) return false
        var off = atan2(dy, dx) - g.facing
        while (off > PI) off -= 2 * PI
        while (off < -PI) off += 2 * PI
        if (abs(off) > visionHalf) return false
        return losClear(g.x, g.y, px, py)
    }

    fun throwDecoy(rx: Double, ry: Double) {
        if (!playing || decoys <= 0) return
        // Clamp into the arena and only lure a guard already on patrol.
        val cx = min(COLS - 1.5, max(1.5, rx)); val cy = min(ROWS - 1.5, max(1.5, ry))
        val g = guards.filter { !it.investigating }.minByOrNull { hypot(it.x - cx, it.y - cy) }
        if (g == null) { SoundManager.error(); return }
        g.investigating = true; g.lureX = cx; g.lureY = cy; g.hold = 0.0
        decoys--
        SoundManager.tap(); Haptics.tap()
    }

    private fun patrol(g: Guard, dt: Double) {
        if (g.path.size < 2) return
        val wp = center(g.path[g.idx])
        val dx = wp.x - g.x; val dy = wp.y - g.y
        val d = hypot(dx, dy); val sd = patrolSpeed * dt
        if (d <= sd || d < 0.0001) {
            g.x = wp.x; g.y = wp.y
            var ni = g.idx + g.dir
            if (ni < 0 || ni >= g.path.size) { g.dir = -g.dir; ni = g.idx + g.dir }
            ni = max(0, min(g.path.size - 1, ni))
            val nwp = center(g.path[ni])
            g.facing = atan2(nwp.y - g.y, nwp.x - g.x)
            g.idx = ni
        } else {
            g.x += dx / d * sd; g.y += dy / d * sd
            g.facing = atan2(dy, dx)
        }
    }

    private fun investigate(g: Guard, dt: Double) {
        val dx = g.lureX - g.x; val dy = g.lureY - g.y
        val d = hypot(dx, dy); val sd = patrolSpeed * 1.15 * dt
        if (d > 0.35) {
            val nx = dx / d * sd; val ny = dy / d * sd
            if (canStand(g.x + nx, g.y)) g.x += nx
            if (canStand(g.x, g.y + ny)) g.y += ny
            g.facing = atan2(dy, dx)
        } else {
            // Arrived — look around, then resume patrol.
            g.hold += dt; g.facing += dt * 2.2
            if (g.hold >= investigateHold) g.investigating = false
        }
    }

    fun step(dt: Double) {
        if (!playing) return
        t += dt
        pulse = 0.25 + 0.25 * sin(t * 4)
        val vx = mdx * PLAYER_SPEED * dt; val vy = mdy * PLAYER_SPEED * dt
        if (canStand(px + vx, py)) px += vx
        if (canStand(px, py + vy)) py += vy
        for (g in guards) if (g.investigating) investigate(g, dt) else patrol(g, dt)
        if (guards.any { spots(it) }) { caught = true; fail(); return }
        if (hypot(px - (exit.c + 0.5), py - (exit.r + 0.5)) < 0.5) { win(); return }
        timeLeft -= dt
        if (timeLeft <= 0) { timeLeft = 0.0; fail() }
    }

    fun win() { if (!playing) return; playing = false; Haptics.success(); SoundManager.tap(); onWin() }
    fun fail() { if (!playing) return; playing = false; Haptics.warning(); SoundManager.error(); onFail() }
}

// Demo: a fixed level-1 room; the banana runs ► along the top corridor and ▼ to the exit. Guard A
// would turn to face it as it passes, so at 4.3 s a decoy west of A draws it away (any throw 3.9–4.7 s works).
private val demoBlocks = listOf(intArrayOf(3, 3, 2, 3), intArrayOf(6, 8, 2, 1), intArrayOf(11, 5, 2, 2), intArrayOf(12, 9, 1, 1), intArrayOf(7, 2, 3, 1))
private val demoPaths = listOf(
    (7..11).reversed().map { DCell(9, it) },          // A: row 9, east → west
    (1..5).map { DCell(14, it) },                     // B: row 14
    (11..15).reversed().map { DCell(it, 1) },         // C: column 1, bottom → up
)
private const val DEMO_THROW_FRAME = 258
private val demoLure = P(4.5, 9.5)

private fun demoBoard(): DecoyBoard {
    val w = List(ROWS) { BooleanArray(COLS) }
    for (r in 0 until ROWS) { w[r][0] = true; w[r][COLS - 1] = true }
    for (c in 0 until COLS) { w[0][c] = true; w[ROWS - 1][c] = true }
    for (b in demoBlocks) for (r in b[0] until b[0] + b[2]) for (c in b[1] until b[1] + b[3]) w[r][c] = true
    return DecoyBoard(w, demoPaths, DCell(1, 1), DCell(ROWS - 2, COLS - 2))
}

private class DGeo(w: Double, h: Double) {
    val cell = min(w / COLS, h / ROWS)
    val ox = (w - cell * COLS) / 2
    val oy = (h - cell * ROWS) / 2
}

@Composable
private fun DecoyView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { DecoyWorld(level) }
    world.onWin = onWin; world.onFail = onFail
    var ready by remember { mutableStateOf(false) }
    var demoTick by remember { mutableIntStateOf(0) }
    var demoTapAt by remember { mutableStateOf(-10.0) }
    var demoTapOn by remember { mutableStateOf(false) }
    val tm = rememberTextMeasurer()
    val handP = rememberHand()
    val tick by rememberFrameLoop(running = ready) { dt -> if (!isDemo) world.step(dt) }

    LaunchedEffect(Unit) {
        if (isDemo) {
            val dt = 1.0 / 60.0
            while (isActive) {
                world.commit(demoBoard()); demoTapOn = false; ready = true
                var frame = 0; var down = false
                while (isActive && world.playing && frame < 900) {
                    frame++
                    if (frame <= 30) { world.mdx = 0.0; world.mdy = 0.0 }
                    else if (!down) {
                        world.mdx = 1.0; world.mdy = 0.0                       // ► along the top corridor…
                        if (world.px >= 11.5) { world.px = 11.5; down = true }
                    }
                    if (down) { world.mdx = 0.0; world.mdy = 1.0 }             // …then ▼ to the exit
                    if (frame == DEMO_THROW_FRAME) { demoTapAt = nowSec(); demoTapOn = true; world.throwDecoy(demoLure.x, demoLure.y) }
                    if (frame == DEMO_THROW_FRAME + 45) demoTapOn = false
                    world.step(dt)
                    demoTick++
                    delay(16)
                }
                world.mdx = 0.0; world.mdy = 0.0; demoTapOn = false
                val end = nowSec()
                while (isActive && nowSec() - end < 1.3) { demoTick++; delay(16) }
            }
        } else {
            val t0 = System.currentTimeMillis()
            val b = BoardCache.take(DecoyGame.key(level)) { DecoyGen.generate(4 + level, DecoyGame.guardCount(level)) }
            BoardCache.holdBrainstorm(t0, 1.0)
            world.commit(b); ready = true
        }
    }

    if (!ready) { BrainstormingView(gray(0.10), gray(0.03)); return }

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .background(Brush.verticalGradient(listOf(rgb(0.1, 0.12, 0.11), rgb(0.03, 0.05, 0.04)))),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(if (isDemo) 4.dp else 8.dp)
    ) {
        tick; demoTick
        // Decoys left: a noise icon and the count.
        val hud = if (world.decoys == 0) DCAlert else DCCaution
        Row(Modifier.fillMaxWidth().padding(horizontal = 22.dp).padding(top = if (isDemo) 6.dp else 0.dp),
            horizontalArrangement = Arrangement.spacedBy(7.dp, Alignment.End), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.SettingsInputAntenna, null, tint = hud, modifier = Modifier.size(if (isDemo) 16.dp else 20.dp))
            Text("${world.decoys}", style = ts(if (isDemo) 16.0 else 20.0, FontWeight.Black, hud).copy(fontFeatureSettings = "tnum"))
        }
        if (!isDemo) {
            val f = world.timeLeft / world.timeLimit
            TimeBar(f, Modifier.fillMaxWidth().padding(horizontal = 50.dp).height(5.dp), fill = if (f < 0.3) DCAlert else DCPhosphor, track = DCPhosphor.op(0.15))
        }
        Canvas(
            Modifier.fillMaxWidth().weight(1f).padding(horizontal = if (isDemo) 12.dp else 4.dp).clip(RoundedCornerShape(16.dp))
                .drawWithCache {
                    // The radar map (grid and walls) never changes during a level: rendered once.
                    world.mapVersion
                    val bmp = ImageBitmap(size.width.toInt().coerceAtLeast(1), size.height.toInt().coerceAtLeast(1))
                    CanvasDrawScope().draw(this, layoutDirection, androidx.compose.ui.graphics.Canvas(bmp), size) { radarMap(world.walls) }
                    onDrawBehind { drawImage(bmp) }
                }
                .then(if (isDemo) Modifier else Modifier.tapIn { p, w, h ->
                    val g = DGeo(w, h)
                    world.throwDecoy((p.x - g.ox) / g.cell, (p.y - g.oy) / g.cell)
                })
        ) {
            tick; demoTick
            val g = DGeo(size.width.toDouble(), size.height.toDouble())
            entities(world, g, tm)
            if (demoTapOn) {
                val x = g.ox + demoLure.x * g.cell; val y = g.oy + demoLure.y * g.cell
                tapRipple(x, y, nowSec() - demoTapAt)
                val s = g.cell * 1.3
                hand(handP, x + g.cell * 0.55 - s / 2, y + g.cell * 0.75 - s / 2, s)
            }
        }
        val kw = if (isDemo) 56.dp else 74.dp; val kh = if (isDemo) 30.dp else 52.dp
        @Composable fun key(dx: Double, dy: Double, icon: ImageVector) = DCKey(world, dx, dy, icon, isDemo, kw, kh)
        if (isDemo) {
            // The squat demo card can't spare a 3-row cross: same four buttons, one row.
            Row(Modifier.padding(bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                key(-1.0, 0.0, Icons.Filled.KeyboardArrowLeft); key(0.0, -1.0, Icons.Filled.KeyboardArrowUp)
                key(0.0, 1.0, Icons.Filled.KeyboardArrowDown); key(1.0, 0.0, Icons.Filled.KeyboardArrowRight)
            }
        } else {
            Column(Modifier.padding(bottom = 6.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                key(0.0, -1.0, Icons.Filled.KeyboardArrowUp)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { key(-1.0, 0.0, Icons.Filled.KeyboardArrowLeft); key(1.0, 0.0, Icons.Filled.KeyboardArrowRight) }
                key(0.0, 1.0, Icons.Filled.KeyboardArrowDown)
            }
        }
    }
}

/** Military d-pad keys; phosphor green while held. */
@Composable
private fun DCKey(world: DecoyWorld, dx: Double, dy: Double, icon: ImageVector, isDemo: Boolean, w: androidx.compose.ui.unit.Dp, h: androidx.compose.ui.unit.Dp) {
    val lit = world.mdx == dx && world.mdy == dy && (isDemo || world.playing)
    val radius = if (isDemo) 9.0 else 14.0
    Box(
        Modifier.scale(if (lit) 0.92f else 1f).size(w, h)
            .then(if (isDemo) Modifier else Modifier.pressDown(
                onDown = { if (world.playing) { world.mdx = dx; world.mdy = dy } },
                onUp = { if (world.mdx == dx && world.mdy == dy) { world.mdx = 0.0; world.mdy = 0.0 } })),
        contentAlignment = Alignment.Center
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val u = density.toDouble(); val bw = size.width.toDouble(); val bh = size.height.toDouble(); val r = radius * u
            rrect(0.0, 0.0, bw, bh, r, vgrad(if (lit) listOf(DCPhosphor, rgb(0.2, 0.7, 0.35)) else listOf(rgb(0.17, 0.21, 0.18), rgb(0.08, 0.1, 0.09)), 0.0, bh))
            rrectStroke(0.75 * u, 0.75 * u, bw - 1.5 * u, bh - 1.5 * u, r - 0.75 * u, DCPhosphor.op(if (lit) 0.9 else 0.3), 1.5 * u)
        }
        Icon(icon, null, tint = if (lit) rgb(0.02, 0.12, 0.05) else DCPhosphor, modifier = Modifier.size(if (isDemo) 20.dp else 28.dp))
    }
}

// Soliton-radar art (after Metal Gear Solid; iOS DCArt).

private val DCPhosphor = rgb(0.42, 1.0, 0.56)
private val DCSight = rgb(0.62, 0.95, 1.0)
private val DCCaution = rgb(1.0, 0.8, 0.28)
private val DCAlert = rgb(1.0, 0.3, 0.28)

/** Exit, vision cones, noise rings, guard blips (with ? / !) and the banana blip. */
private fun DrawScope.entities(world: DecoyWorld, g: DGeo, tm: TextMeasurer) {
    val u = density.toDouble(); val cell = g.cell
    fun x(v: Double) = g.ox + v * cell
    fun y(v: Double) = g.oy + v * cell
    exitMarker(x(world.exit.c + 0.5), y(world.exit.r + 0.5), cell, world.pulse)
    val R = world.visionRange * cell
    for (gd in world.guards) {
        val ox = x(gd.x); val oy = y(gd.y)
        val col = if (gd.investigating) DCCaution else DCSight
        val cone = Path(); cone.m(ox, oy)
        val a0 = gd.facing - world.visionHalf; val a1 = gd.facing + world.visionHalf
        for (s in 0..24) { val a = a0 + (a1 - a0) * s / 24; cone.l(ox + cos(a) * R, oy + sin(a) * R) }
        cone.close()
        drawPath(cone, radial(listOf(col.op(0.34), col.op(0.12)), ox, oy, R))
        drawPath(cone, col.op(0.85), style = Stroke((1.5 * u).f))
    }
    for (gd in world.guards) if (gd.investigating) noise(x(gd.lureX), y(gd.lureY), cell, world.pulse)
    for (gd in world.guards) {
        guardBlip(x(gd.x), y(gd.y), cell, gd.facing)
        if (gd.investigating) mark(tm, "?", x(gd.x), y(gd.y), cell, DCCaution)
    }
    if (world.caught) for (gd in world.guards) if (world.spots(gd)) mark(tm, "!", x(gd.x), y(gd.y), cell, DCAlert)
    playerBlip(x(world.px), y(world.py), cell)
}

/** The exit as a pulsing objective marker. */
private fun DrawScope.exitMarker(cx: Double, cy: Double, cell: Double, pulse: Double) {
    val u = density.toDouble()
    circle(cx, cy, cell * 0.95, radial(listOf(DCPhosphor.op(0.35), DCPhosphor.op(0.0)), cx, cy, cell * 0.95))
    rect(cx - cell * 0.36, cy - cell * 0.36, cell * 0.72, cell * 0.72, DCPhosphor.op(0.35))
    rectStroke(cx - cell * 0.36, cy - cell * 0.36, cell * 0.72, cell * 0.72, DCPhosphor, 2 * u)
    val d = cell * (0.5 + pulse * 0.5); val k = cell * 0.2
    val br = Path()
    for ((sx, sy) in listOf(-1.0 to -1.0, 1.0 to -1.0, 1.0 to 1.0, -1.0 to 1.0)) {
        val qx = cx + sx * d; val qy = cy + sy * d
        br.m(qx - sx * k, qy); br.l(qx, qy); br.l(qx, qy - sy * k)
    }
    strokePath(br, DCPhosphor, 2 * u)
}

/** Sound rings where a decoy landed. */
private fun DrawScope.noise(cx: Double, cy: Double, cell: Double, pulse: Double) {
    for ((i, base) in listOf(0.35, 0.8, 1.25).withIndex()) circleStroke(cx, cy, cell * (base + pulse * 0.9), DCCaution.op(0.8 - i * 0.24), 2 * density.toDouble())
    circle(cx, cy, cell * 0.12, DCCaution)
}

/** A guard: a red blip with a halo and a tick for where it faces. */
private fun DrawScope.guardBlip(cx: Double, cy: Double, cell: Double, facing: Double) {
    val u = density.toDouble()
    circle(cx, cy, cell * 0.5, radial(listOf(DCAlert.op(0.45), DCAlert.op(0.0)), cx, cy, cell * 0.5))
    val r = cell * 0.28
    circle(cx, cy, r, radial(listOf(rgb(1.0, 0.6, 0.55), DCAlert, rgb(0.6, 0.08, 0.08)), cx - r * 0.3, cy - r * 0.3, r * 1.3))
    circleStroke(cx, cy, r, Color.Black.op(0.6), 1.5 * u)
    line(cx + cos(facing) * r * 0.4, cy + sin(facing) * r * 0.4, cx + cos(facing) * cell * 0.62, cy + sin(facing) * cell * 0.62,
        Color.White.op(0.9), max(1.5 * u, cell * 0.08))
}

/** Metal Gear's "?" (heard something) or "!" (spotted you) over a guard. */
private fun DrawScope.mark(tm: TextMeasurer, glyph: String, cx: Double, cy: Double, cell: Double, color: Color) {
    val u = density.toDouble()
    val fs = max(12 * u, cell * 0.8)
    val py = cy - cell * 0.78
    for ((dx, dy) in listOf(-1.5 to 0.0, 1.5 to 0.0, 0.0 to -1.5, 0.0 to 1.5)) text(tm, glyph, cx + dx * u, py + dy * u, fs, Color.Black, FontWeight.Black)
    text(tm, glyph, cx, py, fs, color, FontWeight.Black)
}

/** The banana on the radar: a tilted yellow banana in a white ring, with a soft glow. */
private fun DrawScope.playerBlip(cx: Double, cy: Double, cell: Double) {
    val u = density.toDouble()
    circle(cx, cy, cell * 0.7, radial(listOf(rgb(1.0, 0.9, 0.3, 0.4), rgb(1.0, 0.9, 0.3, 0.0)), cx, cy, cell * 0.7))
    val ring = cell * 0.46
    circle(cx, cy, ring, Color.Black.op(0.45))
    circleStroke(cx, cy, ring, Color.White.op(0.9), 1.5 * u)
    translate(cx.f, (cy + cell * 0.05).f) { rotate(-28f, Offset.Zero) { scale((cell * 0.9).f, (cell * 0.9).f, Offset.Zero) {
        val b = Path(); b.m(-0.44, -0.08); b.q(0.0, 0.62, 0.44, -0.1); b.q(0.0, 0.1, -0.44, -0.08); b.close()
        drawPath(b, vgrad(listOf(rgb(1.0, 0.96, 0.55), rgb(0.98, 0.76, 0.14)), 0.0, 0.3))
        strokePath(b, rgb(0.2, 0.14, 0.02), 0.06)
        oval(-0.48, -0.12, 0.08, 0.08, rgb(0.3, 0.2, 0.05))
        rrect(0.4, -0.2, 0.12, 0.12, 0.03, rgb(0.42, 0.27, 0.08))
    } } }
}

/** The radar map: phosphor grid on dark green glass, hatched walls with bright edges, scanlines, brackets. */
private fun DrawScope.radarMap(walls: List<BooleanArray>) {
    if (walls.size != ROWS) return
    val u = density.toDouble()
    val g = DGeo(size.width.toDouble(), size.height.toDouble())
    val cell = g.cell; val ox = g.ox; val oy = g.oy
    val mw = cell * COLS; val mh = cell * ROWS
    rect(ox, oy, mw, mh, radial(listOf(rgb(0.03, 0.17, 0.1), rgb(0.01, 0.07, 0.04)), ox + mw / 2, oy + mh / 2, max(mw, mh) * 0.7))
    val grid = Path(); val major = Path()
    for (c in 0..COLS) { val x = ox + c * cell; val p = if (c % 4 == 0) major else grid; p.m(x, oy); p.l(x, oy + mh) }
    for (r in 0..ROWS) { val y = oy + r * cell; val p = if (r % 4 == 0) major else grid; p.m(ox, y); p.l(ox + mw, y) }
    strokePath(grid, DCPhosphor.op(0.07), u, StrokeCap.Butt)
    strokePath(major, DCPhosphor.op(0.14), u, StrokeCap.Butt)
    fun wall(r: Int, c: Int) = r !in 0 until ROWS || c !in 0 until COLS || walls[r][c]
    val blocks = Path(); val edges = Path()
    for (r in 0 until ROWS) for (c in 0 until COLS) {
        if (!walls[r][c]) continue
        val x0 = ox + c * cell; val y0 = oy + r * cell
        blocks.addRect(androidx.compose.ui.geometry.Rect(x0.f, y0.f, (x0 + cell + 0.5).f, (y0 + cell + 0.5).f))
        if (!wall(r - 1, c)) { edges.m(x0, y0); edges.l(x0 + cell, y0) }
        if (!wall(r + 1, c)) { edges.m(x0, y0 + cell); edges.l(x0 + cell, y0 + cell) }
        if (!wall(r, c - 1)) { edges.m(x0, y0); edges.l(x0, y0 + cell) }
        if (!wall(r, c + 1)) { edges.m(x0 + cell, y0); edges.l(x0 + cell, y0 + cell) }
    }
    fillPath(blocks, rgb(0.05, 0.25, 0.13))
    clipPath(blocks) {
        val diag = Path(); var d = -mh
        while (d < mw) { diag.m(ox + d, oy + mh); diag.l(ox + d + mh, oy); d += 7 * u }
        strokePath(diag, DCPhosphor.op(0.1), u, StrokeCap.Butt)
    }
    strokePath(edges, DCPhosphor.op(0.35), 4 * u)
    strokePath(edges, DCPhosphor, 1.5 * u)
    val scan = Path(); var y = oy
    while (y < oy + mh) { scan.m(ox, y); scan.l(ox + mw, y); y += 3 * u }
    strokePath(scan, Color.Black.op(0.14), u, StrokeCap.Butt)
    val k = cell * 0.9; val i = 3 * u
    val corners = Path()
    for (q in listOf(doubleArrayOf(ox, oy, 1.0, 1.0), doubleArrayOf(ox + mw, oy, -1.0, 1.0), doubleArrayOf(ox + mw, oy + mh, -1.0, -1.0), doubleArrayOf(ox, oy + mh, 1.0, -1.0))) {
        val (x, yy, sx, sy) = q.toList()
        corners.m(x + sx * i, yy + sy * (i + k)); corners.l(x + sx * i, yy + sy * i); corners.l(x + sx * (i + k), yy + sy * i)
    }
    strokePath(corners, Color.White.op(0.7), 2 * u)
}
