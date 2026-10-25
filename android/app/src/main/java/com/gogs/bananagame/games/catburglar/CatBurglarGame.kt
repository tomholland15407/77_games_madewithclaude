package com.gogs.bananagame.games.catburglar

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
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
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Dp
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
 * Brain / stealth — Cat Burglar (iOS CatBurglarGame.swift, id "cat-burglar"): a Monaco-style heist.
 * D-pad the burglar through a guarded mansion, grab every gold stash, then slip out of the exit
 * (it unlocks with the last coin). Stepping into a guard's cone outside the shadow tiles trips the
 * alarm: every guard turns hostile and reinforcements pour from the red door, firing. A bullet or
 * the clock sends you to level 1. Drawn as a mansion at night with a literal cat burglar.
 */
object CatBurglarGame {
    val definition = GameDefinition(
        id = "cat-burglar",
        title = "Cat Burglar",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Steer with the d-pad. Grab every gold stash, then reach the exit.",
                "The exit unlocks once all the loot is gone.",
                "Guards sweep vision cones — get seen in the open and the alarm trips a firing swarm.",
                "Dark shadow tiles hide you; a bullet or a timeout sends you to level 1.",
            ),
            bulletsVI = listOf(
                "Điều khiển bằng d-pad. Lấy hết mọi túi vàng, rồi đến lối ra.",
                "Lối ra mở khi đã lấy hết chiến lợi phẩm.",
                "Lính gác quét tầm nhìn — bị thấy ngoài trống là báo động và một bầy nổ súng.",
                "Ô bóng tối giúp bạn ẩn mình; trúng đạn hoặc hết giờ sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        prefetch = { level -> BoardCache.prefetch(key(level)) { CBGen.generate(level) } },
        content = { level, onWin, onFail -> CatBurglarView(level, onWin, onFail) }
    )

    fun key(level: Int) = BoardCache.key("cat-burglar", level)
}

internal const val CB_COLS = 13
internal const val CB_ROWS = 17

data class CBCell(val r: Int, val c: Int)

private fun center(p: CBCell) = P(p.c + 0.5, p.r + 0.5)
private fun manhattan(a: CBCell, b: CBCell) = abs(a.r - b.r) + abs(a.c - b.c)

/** Per-level tuning (all derived from `level`, as on iOS). */
class CBParams(level: Int) {
    private val li = min(level, 7) - 1
    val guardCount = listOf(1, 1, 2, 3, 3, 4, 4)[li]
    val lootCount = listOf(10, 12, 14, 16, 18, 20, 24)[li]
    val patrolSpeed = listOf(1.3, 1.5, 1.7, 1.9, 2.1, 2.4, 2.7)[li]
    val chaseSpeed = patrolSpeed + 1.1
    val visionRange = listOf(3.2, 3.6, 4.0, 4.4, 4.8, 5.2, 5.6)[li]
    val visionHalf = listOf(22.0, 26.0, 30.0, 34.0, 38.0, 42.0, 46.0)[li] * PI / 180.0
    val shadowFraction = listOf(0.30, 0.26, 0.22, 0.18, 0.14, 0.11, 0.08)[li]
    val coverBlocks = 4 + level
    val reinforcements = listOf(4, 5, 6, 7, 8, 9, 10)[li]
    val guardFireInterval = listOf(1.2, 1.1, 1.0, 0.9, 0.8, 0.7, 0.6)[li]
    val baseTime = (28 + lootCount * 3).toDouble()
    val alarmBoost = (10 + reinforcements * 3).toDouble()
}

class CBBoard(
    val walls: List<BooleanArray>, val paths: List<List<CBCell>>, val coins: List<CBCell>,
    val shadows: Set<CBCell>, val start: CBCell, val exit: CBCell, val door: CBCell,
)

object CBGen {
    fun generate(level: Int): CBBoard {
        val p = CBParams(level)
        return generate(p.coverBlocks, p.guardCount, p.lootCount, p.shadowFraction)
    }

    fun generate(coverBlocks: Int, guardCount: Int, lootCount: Int, shadowFraction: Double): CBBoard {
        val w = List(CB_ROWS) { BooleanArray(CB_COLS) }
        for (r in 0 until CB_ROWS) { w[r][0] = true; w[r][CB_COLS - 1] = true }
        for (c in 0 until CB_COLS) { w[0][c] = true; w[CB_ROWS - 1][c] = true }
        var placed = 0; var tries = 0
        while (placed < coverBlocks && tries < 300) {
            tries++
            val bw = rndInt(1..3); val bh = rndInt(1..3)
            val c0 = rndInt(2..(CB_COLS - 2 - bw)); val r0 = rndInt(2..(CB_ROWS - 2 - bh))
            var ok = true
            for (r in (r0 - 1)..(r0 + bh)) for (c in (c0 - 1)..(c0 + bw)) if (w[r][c]) ok = false
            if (!ok) continue
            for (r in r0 until r0 + bh) for (c in c0 until c0 + bw) w[r][c] = true
            placed++
        }
        val open = (0 until CB_ROWS).flatMap { r -> (0 until CB_COLS).mapNotNull { c -> if (w[r][c]) null else CBCell(r, c) } }
        fun neighbours(p: CBCell) = listOf(CBCell(p.r - 1, p.c), CBCell(p.r + 1, p.c), CBCell(p.r, p.c - 1), CBCell(p.r, p.c + 1))
            .filter { it.r in 0 until CB_ROWS && it.c in 0 until CB_COLS && !w[it.r][it.c] }
        fun bfsPath(s: CBCell, goal: CBCell): List<CBCell> {
            val prev = HashMap<CBCell, CBCell>(); val seen = hashSetOf(s); val q = ArrayList<CBCell>(); q.add(s); var head = 0
            while (head < q.size) {
                val cur = q[head++]
                if (cur == goal) break
                for (n in neighbours(cur)) if (seen.add(n)) { prev[n] = cur; q.add(n) }
            }
            val path = ArrayList<CBCell>(); var cur: CBCell? = goal
            while (cur != null) { path.add(cur); if (cur == s) break; cur = prev[cur] }
            return path.reversed()
        }
        val startCell = open.minByOrNull { manhattan(it, CBCell(1, 1)) } ?: CBCell(1, 1)
        val corner = CBCell(CB_ROWS - 2, CB_COLS - 2)
        val exitCell = open.filter { it != startCell }.minByOrNull { manhattan(it, corner) } ?: corner
        val doorCorner = CBCell(CB_ROWS - 2, 1)
        val doorCell = open.filter { it != startCell && it != exitCell }.minByOrNull { manhattan(it, doorCorner) } ?: CBCell(CB_ROWS - 2, 1)

        val starts = ArrayList<CBCell>()
        for (cand in open.shuffled()) {
            if (manhattan(cand, startCell) < 5 || cand == exitCell) continue
            if (starts.all { manhattan(it, cand) >= 4 }) { starts.add(cand); if (starts.size == guardCount) break }
        }
        while (starts.size < guardCount && open.isNotEmpty()) starts.add(open.pick())
        val paths = starts.map { s ->
            var path = listOf(s, neighbours(s).firstOrNull() ?: s)
            for (goal in open.shuffled()) {
                if (goal == s) continue
                val bp = bfsPath(s, goal)
                if (bp.size >= 5) { path = bp; break }
            }
            path
        }
        // Loot: lots of distinct open cells, off the start / exit / door / guard tiles.
        val blocked = (starts + listOf(startCell, exitCell, doorCell)).toSet()
        val loot = ArrayList<CBCell>()
        for (cand in open.shuffled()) {
            if (cand in blocked) continue
            loot.add(cand)
            if (loot.size == lootCount) break
        }
        // Shadow tiles.
        val shadowTarget = (open.size * shadowFraction).toInt()
        val sh = HashSet<CBCell>()
        for (cand in open.shuffled()) { if (cand == exitCell) continue; sh.add(cand); if (sh.size >= shadowTarget) break }
        sh.add(startCell)
        return CBBoard(w, paths, loot, sh, startCell, exitCell, doorCell)
    }

    /** The fixed Level-1 vault of the manual clip. */
    fun demoBoard(): CBBoard {
        val w = List(CB_ROWS) { BooleanArray(CB_COLS) }
        for (r in 0 until CB_ROWS) { w[r][0] = true; w[r][CB_COLS - 1] = true }
        for (c in 0 until CB_COLS) { w[0][c] = true; w[CB_ROWS - 1][c] = true }
        for ((r, c) in listOf(3 to 2, 3 to 3, 4 to 2, 4 to 3, 7 to 10, 8 to 10, 7 to 11, 10 to 2, 11 to 2, 15 to 7)) w[r][c] = true
        val coins = listOf(1 to 3, 1 to 5, 4 to 5, 7 to 5, 10 to 5, 13 to 5, 13 to 7, 13 to 9, 13 to 11, 14 to 11).map { CBCell(it.first, it.second) }
        val shadows = listOf(1 to 1, 13 to 7, 13 to 8, 13 to 9, 6 to 3, 5 to 10, 9 to 7, 2 to 9, 12 to 3, 11 to 10, 15 to 4, 8 to 6)
            .map { CBCell(it.first, it.second) }.toSet()
        return CBBoard(w, listOf((4..12).map { CBCell(it, 8) }), coins, shadows, CBCell(1, 1), CBCell(15, 11), CBCell(15, 1))
    }

    /** The demo's d-pad legs: hold each arrow until the burglar reaches the leg's corner. */
    val demoLegs = listOf(Triple(1.0, 0.0, CBCell(1, 5)), Triple(0.0, 1.0, CBCell(13, 5)), Triple(1.0, 0.0, CBCell(13, 11)), Triple(0.0, 1.0, CBCell(15, 11)))
}

class CBGuard(var x: Double, var y: Double, val path: List<CBCell>, var facing: Double) {
    var idx = 0
    var dir = 1
    var alerted = false
    var fireCD = 0.0
}

class CBShot(var x: Double, var y: Double, val vx: Double, val vy: Double, var life: Double)

/** The heist simulation (positions in cells; iOS `step`, `patrol`, `chase`, `raiseAlarm`…). */
class CatWorld(level: Int) {
    val p = CBParams(level)
    var playing = true
    var walls: List<BooleanArray> = List(CB_ROWS) { BooleanArray(CB_COLS) }
    var shadows: Set<CBCell> = emptySet()
    var guards = mutableListOf<CBGuard>()
    var coins = mutableListOf<CBCell>()
    val shots = mutableListOf<CBShot>()
    var px = 1.5; var py = 1.5
    var exit = CBCell(1, 1)
    var door = CBCell(1, 1)
    var mdx = 0.0; var mdy = 0.0
    var alarmRaised = false
    var timeLeft = p.baseTime
    var maxTime = p.baseTime
    var catFacing = 0.0               // presentation only: which way the cat is turned
    var won = false
    /** Bumped whenever the mansion picture changes (layout, the exit lock, the alarm). */
    var mansionVersion by mutableIntStateOf(0)
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    val exitOpen get() = coins.isEmpty()

    fun commit(b: CBBoard) {
        walls = b.walls; shadows = b.shadows
        guards = b.paths.map { path ->
            val f = if (path.size >= 2) atan2(center(path[1]).y - center(path[0]).y, center(path[1]).x - center(path[0]).x) else 0.0
            CBGuard(center(path[0]).x, center(path[0]).y, path, f)
        }.toMutableList()
        coins = b.coins.toMutableList()
        exit = b.exit; door = b.door
        px = b.start.c + 0.5; py = b.start.r + 0.5
        shots.clear(); alarmRaised = false
        mdx = 0.0; mdy = 0.0; catFacing = 0.0
        timeLeft = p.baseTime; maxTime = p.baseTime
        playing = true; won = false
        mansionVersion++
    }

    fun setMove(dx: Double, dy: Double) {
        mdx = dx; mdy = dy
        // The cat turns to face where it's heading.
        if (dx != 0.0 || dy != 0.0) catFacing = atan2(dy, dx)
    }

    fun isWall(r: Int, c: Int) = r !in 0 until CB_ROWS || c !in 0 until CB_COLS || walls[r][c]
    private fun canStand(x: Double, y: Double): Boolean {
        val rad = 0.28
        for (cx in listOf(x - rad, x + rad)) for (cy in listOf(y - rad, y + rad)) if (isWall(floor(cy).toInt(), floor(cx).toInt())) return false
        return true
    }
    private fun losClear(ax: Double, ay: Double, bx: Double, by: Double): Boolean {
        val steps = (hypot(bx - ax, by - ay) / 0.15).toInt() + 1
        for (i in 0..steps) {
            val t = i.toDouble() / steps
            if (isWall(floor(ay + (by - ay) * t).toInt(), floor(ax + (bx - ax) * t).toInt())) return false
        }
        return true
    }
    private fun spots(g: CBGuard): Boolean {
        val dx = px - g.x; val dy = py - g.y
        val d = hypot(dx, dy)
        if (d > p.visionRange || d <= 0.0001) return false
        var off = atan2(dy, dx) - g.facing
        while (off > PI) off -= 2 * PI
        while (off < -PI) off += 2 * PI
        if (abs(off) > p.visionHalf) return false
        return losClear(g.x, g.y, px, py)
    }

    fun step(dt: Double) {
        if (!playing) return
        // Player movement (axis-separated wall collision).
        val vx = mdx * 3.7 * dt; val vy = mdy * 3.7 * dt
        if (canStand(px + vx, py)) px += vx
        if (canStand(px, py + vy)) py += vy
        // Guards patrol, or (once the alarm is up) chase and shoot.
        for (g in guards) {
            if (g.alerted) chase(g, dt) else patrol(g, dt)
            if (g.alerted) {
                g.fireCD -= dt
                val d = hypot(px - g.x, py - g.y)
                if (g.fireCD <= 0 && d <= 8.0 && losClear(g.x, g.y, px, py)) {
                    val a = atan2(py - g.y, px - g.x)
                    g.facing = a
                    g.fireCD = p.guardFireInterval
                    shots.add(CBShot(g.x, g.y, cos(a) * 6.0, sin(a) * 6.0, 2.4))
                }
            }
        }
        // Collect loot.
        val pc = CBCell(floor(py).toInt(), floor(px).toInt())
        val hit = coins.indexOf(pc)
        if (hit >= 0) {
            coins.removeAt(hit)
            Haptics.tap(); SoundManager.tap()
            if (coins.isEmpty()) mansionVersion++          // the exit door swings open
        }
        // Detection — trips the alarm the first time (unless hiding in shadow).
        if (!alarmRaised && pc !in shadows && guards.any { spots(it) }) raiseAlarm()
        // Bullets.
        if (!stepShots(dt)) return
        // Reach the exit once the loot is cleared.
        if (exitOpen && hypot(px - (exit.c + 0.5), py - (exit.r + 0.5)) < 0.5) { win(); return }
        timeLeft -= dt
        if (timeLeft <= 0) { timeLeft = 0.0; fail() }
    }

    private fun stepShots(dt: Double): Boolean {
        val it = shots.iterator()
        while (it.hasNext()) {
            val s = it.next()
            s.x += s.vx * dt; s.y += s.vy * dt; s.life -= dt
            if (s.life <= 0 || isWall(floor(s.y).toInt(), floor(s.x).toInt())) { it.remove(); continue }
            if (hypot(px - s.x, py - s.y) < 0.42) { fail(); return false }
        }
        return true
    }

    private fun raiseAlarm() {
        if (alarmRaised) return
        alarmRaised = true
        for (g in guards) { g.alerted = true; g.fireCD = rnd(0.2, p.guardFireInterval) }
        val d = center(door)
        for (k in 0 until p.reinforcements) {
            guards.add(CBGuard(d.x, d.y, listOf(door), atan2(py - d.y, px - d.x)).also { it.alerted = true; it.fireCD = k * 0.3 + 0.4 })
        }
        timeLeft += p.alarmBoost; maxTime += p.alarmBoost
        mansionVersion++
        SoundManager.error(); Haptics.warning()
    }

    private fun patrol(g: CBGuard, dt: Double) {
        if (g.path.size < 2) return
        val wp = center(g.path[g.idx])
        val dx = wp.x - g.x; val dy = wp.y - g.y
        val d = hypot(dx, dy); val sd = p.patrolSpeed * dt
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

    private fun chase(g: CBGuard, dt: Double) {
        val dx = px - g.x; val dy = py - g.y
        val d = hypot(dx, dy)
        if (d > 0.0001) g.facing = atan2(dy, dx)
        if (d <= 0.4) return
        val sp = p.chaseSpeed * dt
        val nx = dx / d * sp; val ny = dy / d * sp
        if (canStand(g.x + nx, g.y)) g.x += nx
        if (canStand(g.x, g.y + ny)) g.y += ny
    }

    fun win() { if (!playing) return; playing = false; won = true; Haptics.success(); SoundManager.tap(); onWin() }
    fun fail() { if (!playing) return; playing = false; Haptics.warning(); SoundManager.error(); onFail() }

    /** One frame of the manual clip's d-pad script; returns the next leg index. */
    fun demoDrive(leg: Int): Int {
        if (leg >= CBGen.demoLegs.size) return leg
        val (dx, dy, to) = CBGen.demoLegs[leg]
        val goal = center(to)
        // Release this arrow on reaching the leg's corner, then press the next one.
        return if (abs(px - goal.x) < 0.07 && abs(py - goal.y) < 0.07) { setMove(0.0, 0.0); leg + 1 } else { setMove(dx, dy); leg }
    }
}

@Composable
private fun CatBurglarView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { CatWorld(level) }
    world.onWin = onWin; world.onFail = onFail
    var ready by remember { mutableStateOf(false) }
    var demoTick by remember { mutableIntStateOf(0) }
    val tm = rememberTextMeasurer()
    val tick by rememberFrameLoop(running = ready) { dt -> if (!isDemo) world.step(dt) }

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (isActive) {
                world.commit(CBGen.demoBoard()); ready = true
                delay(600)
                var leg = 0
                while (isActive && world.playing) {
                    leg = world.demoDrive(leg)
                    world.step(1.0 / 60)
                    demoTick++
                    delay(16)
                }
                world.setMove(0.0, 0.0)
                // Loot cleared and out of the exit → the real win() ran (onWin is a no-op). Hold, loop.
                delay(1300)
            }
        } else {
            val t0 = System.currentTimeMillis()
            val b = BoardCache.take(CatBurglarGame.key(level)) { CBGen.generate(level) }
            BoardCache.holdBrainstorm(t0, 0.6)
            world.commit(b); ready = true
        }
    }

    if (!ready) { BrainstormingView(rgb(0.1, 0.09, 0.17), rgb(0.03, 0.03, 0.07)); return }

    val mod = Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
        .background(CBNight)
    if (isDemo) {
        // The squat manual card: the mansion on the left, a compact d-pad beside it.
        Row(mod.padding(horizontal = 10.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Board(world, tm, tick, demoTick, Modifier.weight(1f).fillMaxHeight())
            DPad(world, true, world.mdx, world.mdy)
        }
    } else {
        Column(mod.padding(top = 10.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            tick
            Header(world.coins.size, world.alarmRaised)
            val f = if (world.maxTime > 0) world.timeLeft / world.maxTime else 0.0
            TimeBar(f, Modifier.fillMaxWidth().padding(horizontal = 50.dp).height(5.dp), fill = if (f < 0.3) Color.Red else CBGold)
            Board(world, tm, tick, demoTick, Modifier.weight(1f).fillMaxWidth().padding(horizontal = 12.dp))
            DPad(world, false, world.mdx, world.mdy)
        }
    }
}

@Composable
private fun Header(left: Int, alarm: Boolean) {
    // Plain values, not the world: a skipped recomposition must still see the count change.
    Row(Modifier.fillMaxWidth().padding(horizontal = 22.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Canvas(Modifier.size(24.dp, 22.dp)) { coins(size.width / 2.0, size.height * 0.5, min(size.width, size.height) * 1.1) }
        val exitOpen = left == 0
        Text(if (exitOpen) L("REACH THE EXIT", "ĐẾN LỐI RA") else L("$left stash${if (left == 1) "" else "es"} left", "còn $left túi vàng"),
            style = ts(18.0, FontWeight.Black, if (exitOpen) CBExitGreen else CBGold))
        if (alarm) {
            Text(L("ALARM", "BÁO ĐỘNG"), style = ts(14.0, FontWeight.Black, Color.White),
                modifier = Modifier.background(rgb(0.9, 0.15, 0.17), RoundedCornerShape(50)).padding(horizontal = 8.dp, vertical = 3.dp))
        }
        Spacer(Modifier.weight(1f))
    }
}

@Composable
private fun Board(world: CatWorld, tm: TextMeasurer, tick: Long, demoTick: Int, modifier: Modifier) {
    Canvas(
        modifier.clip(RoundedCornerShape(14.dp)).drawWithCache {
            // The mansion: redrawn only when the layout, the exit lock or the alarm changes.
            world.mansionVersion
            val bmp = ImageBitmap(size.width.toInt().coerceAtLeast(1), size.height.toInt().coerceAtLeast(1))
            val walls = world.walls; val shadows = world.shadows; val exit = world.exit; val door = world.door
            val exitOpen = world.exitOpen; val alarm = world.alarmRaised
            CanvasDrawScope().draw(this, layoutDirection, androidx.compose.ui.graphics.Canvas(bmp), size) {
                mansion(walls, shadows, exit, door, exitOpen, alarm)
            }
            onDrawBehind { drawImage(bmp) }
        }
    ) {
        tick; demoTick
        action(world, tm)
    }
}

@Composable
private fun DPad(world: CatWorld, isDemo: Boolean, mdx: Double, mdy: Double) {
    // mdx / mdy are passed in so the held arrow re-lights when they change.
    val g = if (isDemo) 4.dp else 6.dp
    Column(Modifier.padding(bottom = if (isDemo) 0.dp else 6.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(g)) {
        PadKey(world, 0.0, -1.0, Icons.Filled.KeyboardArrowUp, isDemo, mdx == 0.0 && mdy == -1.0)
        Row(horizontalArrangement = Arrangement.spacedBy(g)) {
            PadKey(world, -1.0, 0.0, Icons.Filled.KeyboardArrowLeft, isDemo, mdx == -1.0 && mdy == 0.0)
            PadKey(world, 1.0, 0.0, Icons.Filled.KeyboardArrowRight, isDemo, mdx == 1.0 && mdy == 0.0)
        }
        PadKey(world, 0.0, 1.0, Icons.Filled.KeyboardArrowDown, isDemo, mdx == 0.0 && mdy == 1.0)
    }
}

/** A d-pad key; the held arrow lights up gold (the demo's too). */
@Composable
private fun PadKey(world: CatWorld, dx: Double, dy: Double, icon: ImageVector, isDemo: Boolean, pressed: Boolean) {
    val w: Dp = if (isDemo) 44.dp else 74.dp; val h: Dp = if (isDemo) 36.dp else 52.dp
    val shape = RoundedCornerShape(14.dp)
    Box(
        Modifier.scale(if (pressed) 0.9f else 1f).size(w, h)
            .background(if (pressed) CBGold else rgb(0.14, 0.11, 0.19), shape)
            .border(if (pressed) 3.dp else 1.5.dp, if (pressed) Color.White else CBGold.op(0.6), shape)
            .then(if (isDemo) Modifier else Modifier.pressDown(
                onDown = { if (world.playing) world.setMove(dx, dy) },
                onUp = { if (world.mdx == dx && world.mdy == dy) world.setMove(0.0, 0.0) })),
        contentAlignment = Alignment.Center
    ) { Icon(icon, null, tint = if (pressed) Color.Black else CBGold, modifier = Modifier.size(if (isDemo) 20.dp else 28.dp)) }
}

// Night mansion art (iOS CBArt / CBMansion).

private val CBNight = rgb(0.07, 0.06, 0.11)
private val CBGold = rgb(1.0, 0.8, 0.24)
private val CBExitGreen = rgb(0.45, 0.95, 0.5)
private val CBInk = rgb(0.07, 0.05, 0.08)
private val CBCatYellow = rgb(1.0, 0.83, 0.22)

private fun hashCB(n: Double): Double { val v = sin(n * 12.9898) * 43758.5453; return v - floor(v) }

private class Geo(w: Double, h: Double) {
    val cell = min(w / CB_COLS, h / CB_ROWS)
    val ox = (w - cell * CB_COLS) / 2
    val oy = (h - cell * CB_ROWS) / 2
    fun x(v: Double) = ox + v * cell
    fun y(v: Double) = oy + v * cell
}

private fun DrawScope.ovalC(cx: Double, cy: Double, rx: Double, ry: Double, c: Color) = oval(cx - rx, cy - ry, rx * 2, ry * 2, c)
private fun DrawScope.ovalStroke(cx: Double, cy: Double, rx: Double, ry: Double, c: Color, lw: Double) =
    drawOval(c, Offset((cx - rx).f, (cy - ry).f), androidx.compose.ui.geometry.Size((rx * 2).f, (ry * 2).f), style = Stroke(lw.f))
private fun ovalPath(cx: Double, cy: Double, rx: Double, ry: Double) = Path().apply { addOval(Rect((cx - rx).f, (cy - ry).f, (cx + rx).f, (cy + ry).f)) }

/** Loot, flashlight cones, bullets, guard dogs and the cat, in one pass. */
private fun DrawScope.action(world: CatWorld, tm: TextMeasurer) {
    val g = Geo(size.width.toDouble(), size.height.toDouble())
    val cell = g.cell; val u = density.toDouble()
    for (c in world.coins) coins(g.x(c.c + 0.5), g.y(c.r + 0.5), cell)
    // Flashlight cones: exactly the geometry the guards see with (not clipped by furniture).
    val R = world.p.visionRange * cell
    for (gd in world.guards) {
        val ox = g.x(gd.x); val oy = g.y(gd.y)
        val cone = Path().apply { m(ox, oy); arc(ox, oy, R, gd.facing - world.p.visionHalf, gd.facing + world.p.visionHalf); close() }
        val col = if (gd.alerted) rgb(1.0, 0.25, 0.22) else rgb(1.0, 0.93, 0.62)
        val k = (cell * 0.3 / R).toFloat().coerceIn(0f, 1f)
        drawPath(cone, Brush.radialGradient(0f to col.op(0.55), k to col.op(0.55), 1f to col.op(0.14), center = Offset(ox.f, oy.f), radius = R.f))
        drawPath(cone, col.op(0.85), style = Stroke((1.5 * u).f))
    }
    for (s in world.shots) {
        val x = g.x(s.x); val y = g.y(s.y)
        val sp = max(0.001, hypot(s.vx, s.vy))
        val tx = x - s.vx / sp * cell * 0.55; val ty = y - s.vy / sp * cell * 0.55
        drawLine(Brush.linearGradient(listOf(Color.Red.op(0.0), rgb(1.0, 0.35, 0.3)), Offset(tx.f, ty.f), Offset(x.f, y.f)),
            Offset(tx.f, ty.f), Offset(x.f, y.f), (cell * 0.16).f, StrokeCap.Round)
        circle(x, y, cell * 0.09, Color.White)
    }
    for (gd in world.guards) guardDog(g.x(gd.x), g.y(gd.y), gd.facing, cell, gd.alerted, tm)
    // The cat dims while it hides on a shadow tile.
    val here = CBCell(floor(world.py).toInt(), floor(world.px).toInt())
    cat(g.x(world.px), g.y(world.py), world.catFacing, cell, here in world.shadows)
}

/** A stack of three gold coins with a glint. */
private fun DrawScope.coins(px: Double, py: Double, cell: Double) {
    val u = density.toDouble()
    val rx = cell * 0.24; val ry = cell * 0.1
    ovalC(px + cell * 0.03, py + cell * 0.2, rx * 1.1, ry * 1.1, Color.Black.op(0.4))
    for ((k, dy) in listOf(0.16, 0.05, -0.06).withIndex()) {
        val cx = px + (if (k % 2 == 0) 0.0 else 0.03) * cell; val cy = py + dy * cell
        ovalC(cx, cy + ry * 0.45, rx, ry, rgb(0.7, 0.46, 0.08))
        drawOval(vgrad(listOf(rgb(1.0, 0.95, 0.6), CBGold), cy - ry, cy + ry), Offset((cx - rx).f, (cy - ry).f), androidx.compose.ui.geometry.Size((rx * 2).f, (ry * 2).f))
        ovalStroke(cx, cy, rx * 0.62, ry * 0.62, rgb(0.8, 0.55, 0.1), 0.7 * u)
    }
    val sx = px + cell * 0.2; val sy = py - cell * 0.16
    val star = Path()
    for (i in 0 until 8) {
        val a = i * PI / 4
        val r = if (i % 2 == 0) cell * 0.12 else cell * 0.03
        if (i == 0) star.m(sx + cos(a) * r, sy + sin(a) * r) else star.l(sx + cos(a) * r, sy + sin(a) * r)
    }
    star.close()
    fillPath(star, Color.White.op(0.9))
}

/** A guard dog from above in a navy harness and peaked cap, nose pointing where it faces. */
private fun DrawScope.guardDog(px: Double, py: Double, facing: Double, cell: Double, alerted: Boolean, tm: TextMeasurer) {
    val u = density.toDouble()
    val s = cell * 1.45
    val fur = rgb(0.8, 0.6, 0.38); val ear = rgb(0.5, 0.32, 0.17); val navy = rgb(0.14, 0.2, 0.45)
    ovalC(px + s * 0.04, py + s * 0.1, s * 0.38, s * 0.24, Color.Black.op(0.35))
    translate(px.f, py.f) { rotateRad(facing.f, Offset.Zero) {
        val lw = max(u, s * 0.04)
        line(-s * 0.28, 0.0, -s * 0.42, -s * 0.05, CBInk, s * 0.08 + lw)
        line(-s * 0.28, 0.0, -s * 0.42, -s * 0.05, fur, s * 0.08)
        val body = ovalPath(-s * 0.08, 0.0, s * 0.24, s * 0.18)
        fillPath(body, fur)
        drawPath(body, CBInk, style = Stroke(lw.f))
        // Harness band with the guard's badge.
        clipPath(body) { rect(-s * 0.06, -s * 0.2, s * 0.09, s * 0.4, navy) }
        circle(-s * 0.015, 0.0, s * 0.035, CBGold)
        // Floppy ears either side of the head, then the head, snout and nose.
        for (side in listOf(-1.0, 1.0)) {
            ovalC(s * 0.18, side * s * 0.17, s * 0.1, s * 0.065, ear)
            ovalStroke(s * 0.18, side * s * 0.17, s * 0.1, s * 0.065, CBInk, lw * 0.8)
        }
        circle(s * 0.22, 0.0, s * 0.17, fur.lit(0.12))
        circleStroke(s * 0.22, 0.0, s * 0.17, CBInk, lw)
        ovalC(s * 0.38, 0.0, s * 0.085, s * 0.075, fur.lit(0.4))
        ovalStroke(s * 0.38, 0.0, s * 0.085, s * 0.075, CBInk, lw * 0.8)
        circle(s * 0.45, 0.0, s * 0.035, CBInk)
        for (side in listOf(-1.0, 1.0)) circle(s * 0.3, side * s * 0.075, s * 0.025, CBInk)
        // The peaked cap: navy crown, gold badge, black visor toward the nose.
        val visor = Path().apply { arc(s * 0.17, 0.0, s * 0.1, -65 * PI / 180, 65 * PI / 180) }
        strokePath(visor, CBInk, s * 0.05)
        circle(s * 0.15, 0.0, s * 0.09, navy)
        circleStroke(s * 0.15, 0.0, s * 0.09, CBInk, lw * 0.7)
        circle(s * 0.2, 0.0, s * 0.025, CBGold)
    } }
    if (alerted) {
        val bx = px - cell * 0.18; val by = py - cell * 1.1; val bw = cell * 0.36; val bh = cell * 0.42
        rrect(bx - 1.5 * u, by - 1.5 * u, bw + 3 * u, bh + 3 * u, cell * 0.1, CBInk)
        rrect(bx, by, bw, bh, cell * 0.08, rgb(1.0, 0.85, 0.2))
        text(tm, "!", bx + bw / 2, by + bh / 2, cell * 0.36, CBInk, FontWeight.Black)
    }
}

/**
 * The cat burglar from above: a banana-yellow tabby in a black domino mask with a swag sack on its
 * back, turned to where it's heading. It dims while hiding in a shadow.
 */
private fun DrawScope.cat(px: Double, py: Double, facing: Double, cell: Double, hidden: Boolean) {
    val u = density.toDouble()
    val s = cell * 1.45
    withAlpha(if (hidden) 0.62 else 1.0) {
        ovalC(px + s * 0.04, py + s * 0.09, s * 0.34, s * 0.22, Color.Black.op(0.35))
        translate(px.f, py.f) { rotateRad(facing.f, Offset.Zero) {
            val lw = max(u, s * 0.04)
            val stripe = rgb(0.86, 0.5, 0.08)
            val tail = Path().apply { m(-s * 0.2, 0.0); c(-s * 0.42, -s * 0.06, -s * 0.46, s * 0.12, -s * 0.36, s * 0.2) }
            strokePath(tail, CBInk, s * 0.085 + lw)
            strokePath(tail, CBCatYellow, s * 0.085)
            circle(-s * 0.36, s * 0.2, s * 0.045, stripe)
            val body = ovalPath(-s * 0.06, 0.0, s * 0.21, s * 0.15)
            fillPath(body, CBCatYellow)
            val stripes = Path()
            for (x in listOf(-0.17, -0.09)) { stripes.m(s * x, -s * 0.15); stripes.q(s * (x - 0.04), 0.0, s * x, s * 0.15) }
            clipPath(body) { strokePath(stripes, stripe, s * 0.03) }
            drawPath(body, CBInk, style = Stroke(lw.f))
            // The swag sack slung over its back.
            circle(-s * 0.03, -s * 0.02, s * 0.1, radial(listOf(rgb(0.85, 0.8, 0.7), rgb(0.55, 0.5, 0.42)), -s * 0.06, -s * 0.05, s * 0.13))
            circleStroke(-s * 0.03, -s * 0.02, s * 0.1, CBInk, lw * 0.9)
            // Big head: pointed ears, black mask with white eyes, pink nose, whiskers.
            for (side in listOf(-1.0, 1.0)) {
                val ear = polyPath(s * 0.1, side * s * 0.07, s * 0.1, side * s * 0.24, s * 0.26, side * s * 0.14)
                fillPath(ear, CBCatYellow)
                strokePath(ear, CBInk, lw * 0.9)
            }
            val head = Path().apply { addOval(Rect((s * 0.22 - s * 0.17).f, (-s * 0.17).f, (s * 0.22 + s * 0.17).f, (s * 0.17).f)) }
            fillPath(head, CBCatYellow)
            clipPath(head) { rect(s * 0.23, -s * 0.2, s * 0.08, s * 0.4, CBInk) }
            drawPath(head, CBInk, style = Stroke(lw.f))
            for (side in listOf(-1.0, 1.0)) ovalC(s * 0.27, side * s * 0.07, s * 0.025, s * 0.035, Color.White)
            circle(s * 0.37, 0.0, s * 0.028, rgb(1.0, 0.55, 0.6))
            val whiskers = Path()
            for (side in listOf(-1.0, 1.0)) { whiskers.m(s * 0.35, side * s * 0.05); whiskers.l(s * 0.44, side * s * 0.13) }
            strokePath(whiskers, CBInk.op(0.7), max(0.6 * u, lw * 0.5))
        } }
    }
}

/**
 * The mansion at night: parquet floor, soft pools of shadow, plum walls with gold molding,
 * furniture on every block of cover, the exit door and the guards' red door.
 */
private fun DrawScope.mansion(walls: List<BooleanArray>, shadows: Set<CBCell>, exit: CBCell, door: CBCell, exitOpen: Boolean, alarm: Boolean) {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    val g = Geo(w, h); val cell = g.cell
    val rows = CB_ROWS; val cols = CB_COLS
    fun rx(c: Int) = g.ox + c * cell
    fun ry(r: Int) = g.oy + r * cell
    fun wall(r: Int, c: Int) = r < 0 || c < 0 || r >= rows || c >= cols || walls[r][c]
    fun shade(r: Int, c: Int) = r in 0 until rows && c in 0 until cols && CBCell(r, c) in shadows
    fun border(r: Int, c: Int) = r == 0 || c == 0 || r == rows - 1 || c == cols - 1

    // Basket-weave parquet: three planks per tile, alternating direction.
    for (r in 0 until rows) for (c in 0 until cols) {
        if (walls[r][c]) continue
        val vertical = (r + c) % 2 == 0
        for (k in 0 until 3) {
            val t = hashCB((r * 31 + c * 7 + k).toDouble())
            val wood = rgb(0.5 + 0.07 * t, 0.35 + 0.05 * t, 0.22 + 0.03 * t)
            val x0 = if (vertical) rx(c) + k * cell / 3 else rx(c)
            val y0 = if (vertical) ry(r) else ry(r) + k * cell / 3
            val pw = if (vertical) cell / 3 else cell
            val ph = if (vertical) cell else cell / 3
            rect(x0 - 0.25 * u, y0 - 0.25 * u, pw + 0.5 * u, ph + 0.5 * u, wood)
            rectStroke(x0, y0, pw, ph, rgb(0.22, 0.14, 0.08, 0.7), 0.6 * u)
        }
    }
    // Moonlight falling across the room from the top left.
    rect(g.ox, g.oy, cols * cell, rows * cell, lin(listOf(rgb(0.55, 0.65, 1.0, 0.14), Color.Transparent, Color.Black.op(0.18)),
        g.ox, g.oy, g.ox + cols * cell, g.oy + rows * cell))
    // Pools of shadow: each shadow tile rounds the corners it doesn't share, so touching tiles melt
    // into one dark pool.
    val pools = Path()
    val rad = cell * 0.38
    for (r in 0 until rows) for (c in 0 until cols) {
        if (!shade(r, c)) continue
        val tl = !shade(r - 1, c) && !shade(r, c - 1); val tr = !shade(r - 1, c) && !shade(r, c + 1)
        val bl = !shade(r + 1, c) && !shade(r, c - 1); val br = !shade(r + 1, c) && !shade(r, c + 1)
        fun cr(on: Boolean) = CornerRadius(if (on) rad.f else 0f)
        pools.addRoundRect(RoundRect((rx(c) - 0.4 * u).f, (ry(r) - 0.4 * u).f, (rx(c) + cell + 0.4 * u).f, (ry(r) + cell + 0.4 * u).f,
            cr(tl), cr(tr), cr(br), cr(bl)))
    }
    // A soft, feathered pool of dark, with a faint crisp rim so each tile's edge stays exact.
    blurPath(pools, rgb(0.02, 0.03, 0.13, 0.7), cell * 0.12)
    fillPath(pools, rgb(0.02, 0.03, 0.13, 0.35))
    drawPath(pools, rgb(0.35, 0.42, 0.85, 0.28), style = Stroke(u.f))

    // Walls: plum wallpaper tops with a gold molding where they meet the floor.
    val plum = rgb(0.27, 0.1, 0.15)
    val molding = Path()
    for (r in 0 until rows) for (c in 0 until cols) {
        if (!walls[r][c] || !border(r, c)) continue
        val x0 = rx(c); val y0 = ry(r)
        rect(x0 - 0.3 * u, y0 - 0.3 * u, cell + 0.6 * u, cell + 0.6 * u, plum)
        circle(x0 + cell / 2, y0 + cell / 2, cell * 0.07, plum.lit(0.12))
        if (!wall(r + 1, c)) { molding.m(x0, y0 + cell - u); molding.l(x0 + cell, y0 + cell - u) }
        if (!wall(r - 1, c)) { molding.m(x0, y0 + u); molding.l(x0 + cell, y0 + u) }
        if (!wall(r, c + 1)) { molding.m(x0 + cell - u, y0); molding.l(x0 + cell - u, y0 + cell) }
        if (!wall(r, c - 1)) { molding.m(x0 + u, y0); molding.l(x0 + u, y0 + cell) }
    }
    strokePath(molding, CBGold.op(0.75), max(u, cell * 0.07))

    // Furniture on each block of cover (blocks are rectangles; find each one's extent).
    val seen = HashSet<Int>()
    for (r in 0 until rows) for (c in 0 until cols) {
        if (!walls[r][c] || border(r, c) || (r * cols + c) in seen) continue
        val stack = ArrayDeque(listOf(r to c))
        var minR = r; var maxR = r; var minC = c; var maxC = c
        seen.add(r * cols + c)
        while (stack.isNotEmpty()) {
            val (cr, cc) = stack.removeLast()
            minR = min(minR, cr); maxR = max(maxR, cr); minC = min(minC, cc); maxC = max(maxC, cc)
            for ((nr, nc) in listOf(cr - 1 to cc, cr + 1 to cc, cr to cc - 1, cr to cc + 1)) {
                if (nr in 0 until rows && nc in 0 until cols && walls[nr][nc] && !border(nr, nc) && seen.add(nr * cols + nc)) stack.addLast(nr to nc)
            }
        }
        furniture(rx(minC), ry(minR), (maxC - minC + 1) * cell, (maxR - minR + 1) * cell, cell, maxC - minC + 1, maxR - minR + 1, (minR * 17 + minC).toDouble())
    }

    exitDoor(rx(exit.c), ry(exit.r), cell, exitOpen)
    guardDoor(rx(door.c), ry(door.r), cell, alarm)

    // The alarm bathes the room in red.
    val mn = min(w, h); val mx = max(w, h)
    if (alarm) {
        val k = (mn * 0.3 / (mx * 0.7)).toFloat()
        rect(0.0, 0.0, w, h, Brush.radialGradient(0f to Color.Transparent, k to Color.Transparent, 1f to rgb(1.0, 0.1, 0.1, 0.35),
            center = Offset((w / 2).f, (h / 2).f), radius = (mx * 0.7).f))
    }
    val k = (mn * 0.4 / (mx * 0.75)).toFloat()
    rect(0.0, 0.0, w, h, Brush.radialGradient(0f to Color.Transparent, k to Color.Transparent, 1f to Color.Black.op(0.3),
        center = Offset((w / 2).f, (h / 2).f), radius = (mx * 0.75).f))
}

/**
 * Picks a piece by the block's footprint: plants, armchairs and vases for single tiles, sofas and
 * cabinets for pairs, bookshelves for strips, a piano or a round table for 2×2, and a dining table,
 * a bed or a billiard table for the big ones.
 */
private fun DrawScope.furniture(bx: Double, by: Double, bw: Double, bh: Double, cell: Double, w: Int, h: Int, seed: Double) {
    val u = density.toDouble()
    val x = bx + cell * 0.07; val y = by + cell * 0.07; val rw = bw - cell * 0.14; val rh = bh - cell * 0.14
    val mxX = x + rw; val mxY = y + rh; val midX = x + rw / 2; val midY = y + rh / 2
    val pick = (hashCB(seed) * 97).toInt()
    rrect(x + cell * 0.08, y + cell * 0.12, rw, rh, cell * 0.14, Color.Black.op(0.4))
    val ink = CBInk
    val lw = max(u, cell * 0.05)
    val horizontal = w >= h
    if (w == 1 && h == 1) {
        val m = rw
        when (pick % 3) {
            0 -> {     // potted palm
                circle(midX, midY, m * 0.3, rgb(0.72, 0.38, 0.2))
                circleStroke(midX, midY, m * 0.3, ink, lw)
                for (k in 0 until 6) {
                    translate(midX.f, midY.f) { rotateRad((k * PI / 3 + 0.3).f, Offset.Zero) {
                        ovalC(m * 0.25, 0.0, m * 0.25, m * 0.09, rgb(0.2, 0.55, 0.3))
                        ovalStroke(m * 0.25, 0.0, m * 0.25, m * 0.09, rgb(0.05, 0.25, 0.12), lw * 0.7)
                    } }
                }
            }
            1 -> {     // armchair
                rrect(x + m * 0.08, y + m * 0.08, rw - m * 0.16, rh - m * 0.16, m * 0.2, rgb(0.55, 0.12, 0.18))
                rrectStroke(x + m * 0.08, y + m * 0.08, rw - m * 0.16, rh - m * 0.16, m * 0.2, ink, lw)
                rrect(x + m * 0.24, y + m * 0.3, m * 0.52, m * 0.52, m * 0.14, rgb(0.72, 0.2, 0.26))
            }
            else -> {  // a vase on a marble pedestal
                rrect(x + m * 0.1, y + m * 0.1, rw - m * 0.2, rh - m * 0.2, m * 0.08, rgb(0.86, 0.84, 0.8))
                rrectStroke(x + m * 0.1, y + m * 0.1, rw - m * 0.2, rh - m * 0.2, m * 0.08, ink, lw)
                circle(midX, midY, m * 0.26, rgb(0.25, 0.4, 0.8))
                circleStroke(midX, midY, m * 0.26, ink, lw * 0.8)
                circle(midX, midY, m * 0.1, rgb(0.08, 0.12, 0.3))
            }
        }
    } else if (w * h == 2 && pick % 2 == 0) {
        // A velvet sofa: back along one long side, arms at the ends, two cushions.
        rrect(x, y, rw, rh, cell * 0.18, rgb(0.36, 0.14, 0.3))
        rrectStroke(x, y, rw, rh, cell * 0.18, ink, lw)
        val ix = if (horizontal) x + cell * 0.14 else x + cell * 0.22
        val iy = if (horizontal) y + cell * 0.22 else y + cell * 0.14
        val iw = if (horizontal) rw - cell * 0.28 else rw - cell * 0.26
        val ih = if (horizontal) rh - cell * 0.26 else rh - cell * 0.28
        for (k in 0 until 2) {
            val cx = if (horizontal) ix + k * iw / 2 else ix
            val cy = if (horizontal) iy else iy + k * ih / 2
            val cw = if (horizontal) iw / 2 else iw
            val ch = if (horizontal) ih else ih / 2
            rrect(cx + u, cy + u, cw - 2 * u, ch - 2 * u, cell * 0.12, rgb(0.5, 0.22, 0.42))
            rrectStroke(cx + u, cy + u, cw - 2 * u, ch - 2 * u, cell * 0.12, ink.op(0.6), lw * 0.6)
        }
    } else if (min(w, h) == 1) {
        // Bookshelf / cabinet: a wooden case full of coloured book tops.
        rrect(x, y, rw, rh, cell * 0.08, rgb(0.36, 0.22, 0.12))
        val ix = x + cell * 0.1; val iy = y + cell * 0.1; val iw = rw - cell * 0.2; val ih = rh - cell * 0.2
        val bookColors = listOf(rgb(0.7, 0.15, 0.15), rgb(0.15, 0.35, 0.6), rgb(0.2, 0.5, 0.3), rgb(0.8, 0.6, 0.2), rgb(0.45, 0.2, 0.5))
        val n = ((if (horizontal) iw else ih) / (cell * 0.16)).toInt()
        val nn = max(1, n)
        for (k in 0 until nn) {
            val t = k.toDouble() / nn
            val col = bookColors[(hashCB(seed + k) * 5).toInt() % 5]
            if (horizontal) rect(ix + t * iw, iy, iw / nn - 0.8 * u, ih, col) else rect(ix, iy + t * ih, iw, ih / nn - 0.8 * u, col)
        }
        rrectStroke(x, y, rw, rh, cell * 0.08, ink, lw)
    } else if (w == 2 && h == 2) {
        val m = rw
        if (pick % 2 == 0) {
            // A grand piano: glossy black body with a curved tail, keys along the front.
            val piano = Path().apply {
                m(x, y + m * 0.1); l(mxX, y + m * 0.1); l(mxX, y + m * 0.36)
                q(mxX, y + m * 0.6, x + m * 0.62, y + m * 0.64)
                q(x + m * 0.5, y + m * 0.7, x + m * 0.46, mxY - m * 0.02)
                q(x + m * 0.12, mxY + m * 0.04, x, mxY - m * 0.18)
                close()
            }
            drawPath(piano, lin(listOf(gray(0.22), gray(0.05)), x, y, mxX, mxY))
            drawPath(piano, Color.Black, style = Stroke(lw.f))
            val kx = x + m * 0.06; val kw = m * 0.88; val kh = m * 0.13
            rect(kx, y, kw, kh, Color.White)
            var bxk = kx + m * 0.05
            while (bxk < kx + kw - m * 0.03) { rect(bxk, y, m * 0.025, kh * 0.6, Color.Black); bxk += m * 0.07 }
            rectStroke(kx, y, kw, kh, Color.Black, 0.8 * u)
            ovalC(midX + m * 0.08, midY, m * 0.18, m * 0.08, Color.White.op(0.12))
        } else {
            // A round table with four chairs and a candle.
            for (k in 0 until 4) {
                val a = k * PI / 2 + PI / 4
                val qx = midX + cos(a) * m * 0.36; val qy = midY + sin(a) * m * 0.36
                rrect(qx - m * 0.1, qy - m * 0.1, m * 0.2, m * 0.2, m * 0.05, rgb(0.45, 0.28, 0.15))
                rrectStroke(qx - m * 0.1, qy - m * 0.1, m * 0.2, m * 0.2, m * 0.05, ink, lw * 0.7)
            }
            circle(midX, midY, m * 0.33, rgb(0.93, 0.9, 0.84))
            circleStroke(midX, midY, m * 0.33, ink, lw)
            circle(midX, midY, m * 0.05, CBGold)
            circle(midX, midY, m * 0.16, radial(listOf(rgb(1.0, 0.85, 0.4, 0.5), Color.Transparent), midX, midY, m * 0.16))
        }
    } else if ((w >= 3 && h >= 3) || pick % 3 == 0) {
        // A billiard table: wooden rail, green felt, six pockets and a few balls.
        rrect(x, y, rw, rh, cell * 0.14, rgb(0.4, 0.22, 0.1))
        val fx = x + cell * 0.16; val fy = y + cell * 0.16; val fw = rw - cell * 0.32; val fh = rh - cell * 0.32
        rrect(fx, fy, fw, fh, cell * 0.06, rgb(0.1, 0.48, 0.3))
        val pockets = listOf(fx to fy, fx + fw to fy, fx to fy + fh, fx + fw to fy + fh,
            (if (horizontal) fx + fw / 2 else fx) to (if (horizontal) fy else fy + fh / 2),
            (if (horizontal) fx + fw / 2 else fx + fw) to (if (horizontal) fy + fh else fy + fh / 2))
        for ((ppx, ppy) in pockets) circle(ppx, ppy, cell * 0.09, Color.Black)
        for ((bxf, byf, col) in listOf(Triple(0.3, 0.4, Color.White), Triple(0.6, 0.55, rgb(0.9, 0.2, 0.2)), Triple(0.66, 0.35, rgb(0.95, 0.8, 0.2)))) {
            circle(fx + fw * bxf, fy + fh * byf, cell * 0.07, col)
        }
        rrectStroke(x, y, rw, rh, cell * 0.14, ink, lw)
    } else if (pick % 2 == 0) {
        // A dining table under a white cloth, plates and candlesticks down the middle.
        rrect(x + cell * 0.1, y + cell * 0.1, rw - cell * 0.2, rh - cell * 0.2, cell * 0.1, rgb(0.93, 0.91, 0.86))
        rrectStroke(x + cell * 0.1, y + cell * 0.1, rw - cell * 0.2, rh - cell * 0.2, cell * 0.1, ink, lw)
        val n = max(w, h)
        for (k in 0 until n) {
            val t = (k + 0.5) / n
            for (side in listOf(-1.0, 1.0)) {
                val ppx = if (horizontal) x + t * rw else midX + side * rw * 0.24
                val ppy = if (horizontal) midY + side * rh * 0.24 else y + t * rh
                circle(ppx, ppy, cell * 0.12, Color.White)
                circleStroke(ppx, ppy, cell * 0.12, gray(0.6), 0.8 * u)
            }
            circle(if (horizontal) x + t * rw else midX, if (horizontal) midY else y + t * rh, cell * 0.06, CBGold)
        }
    } else {
        // A four-poster bed: headboard, two pillows and a quilt.
        rrect(x, y, rw, rh, cell * 0.1, rgb(0.4, 0.24, 0.13))
        if (horizontal) rrect(x + rw * 0.3, y + cell * 0.08, rw * 0.66, rh - cell * 0.16, cell * 0.08, rgb(0.25, 0.35, 0.62))
        else rrect(x + cell * 0.08, y + rh * 0.3, rw - cell * 0.16, rh * 0.66, cell * 0.08, rgb(0.25, 0.35, 0.62))
        for (k in 0 until 2) {
            if (horizontal) rrect(x + cell * 0.12, y + k * rh / 2 + cell * 0.1, rw * 0.16, rh / 2 - cell * 0.2, cell * 0.08, Color.White)
            else rrect(x + k * rw / 2 + cell * 0.1, y + cell * 0.12, rw / 2 - cell * 0.2, rh * 0.16, cell * 0.08, Color.White)
        }
        rrectStroke(x, y, rw, rh, cell * 0.1, ink, lw)
    }
}

/** The way out: a locked door with a padlock, then a glowing green open doorway. */
private fun DrawScope.exitDoor(x0: Double, y0: Double, cell: Double, open: Boolean) {
    val u = density.toDouble()
    val dx = x0 + cell * 0.12; val dy = y0 + cell * 0.06; val dw = cell - cell * 0.24; val dh = cell - cell * 0.12
    val arch = Path().apply {
        m(dx, dy + dh); l(dx, dy + dw * 0.5)
        arc(dx + dw / 2, dy + dw * 0.5, dw * 0.5, PI, 2 * PI)
        l(dx + dw, dy + dh); close()
    }
    if (open) {
        val cx = x0 + cell / 2; val cy = y0 + cell / 2
        circle(cx, cy, cell * 1.3, radial(listOf(CBExitGreen.op(0.55), Color.Transparent), cx, cy, cell * 1.3))
        drawPath(arch, vgrad(listOf(rgb(0.85, 1.0, 0.85), CBExitGreen), dy, dy + dh))
        drawPath(arch, rgb(0.1, 0.4, 0.15), style = Stroke(max(1.2 * u, cell * 0.06).f))
    } else {
        fillPath(arch, rgb(0.36, 0.2, 0.1))
        drawPath(arch, CBInk, style = Stroke(max(u, cell * 0.05).f))
        val lx = dx + dw / 2 - cell * 0.13; val ly = dy + dh / 2; val lw = cell * 0.26; val lh = cell * 0.22
        val shackle = Path().apply { arc(lx + lw / 2, ly, cell * 0.08, PI, 2 * PI) }
        strokePath(shackle, gray(0.75), max(u, cell * 0.05), StrokeCap.Butt)
        rrect(lx, ly, lw, lh, cell * 0.04, CBGold)
        circle(lx + lw / 2, ly + lh / 2, cell * 0.03, CBInk)
    }
}

/** The guards' red steel door with its siren lamp — blazing once the alarm trips. */
private fun DrawScope.guardDoor(x0: Double, y0: Double, cell: Double, alarm: Boolean) {
    val u = density.toDouble()
    val cx = x0 + cell / 2; val cy = y0 + cell / 2
    if (alarm) circle(cx, cy, cell * 1.7, radial(listOf(rgb(1.0, 0.15, 0.1, 0.6), Color.Transparent), cx, cy, cell * 1.7))
    val dx = x0 + cell * 0.1; val dy = y0 + cell * 0.08; val dw = cell * 0.8; val dh = cell * 0.84
    rrect(dx, dy, dw, dh, cell * 0.06, lin(listOf(rgb(0.8, 0.16, 0.14), rgb(0.5, 0.06, 0.06)), dx, dy, dx + dw, dy + dh))
    rrectStroke(dx, dy, dw, dh, cell * 0.06, CBInk, max(u, cell * 0.05))
    for ((ppx, ppy) in listOf(dx + cell * 0.1 to dy + cell * 0.1, dx + dw - cell * 0.1 to dy + cell * 0.1,
        dx + cell * 0.1 to dy + dh - cell * 0.1, dx + dw - cell * 0.1 to dy + dh - cell * 0.1)) circle(ppx, ppy, cell * 0.035, gray(0.8))
    val lx = cx; val ly = cy - cell * 0.04
    circle(lx, ly, cell * 0.14, if (alarm) rgb(1.0, 0.3, 0.2) else rgb(0.35, 0.05, 0.05))
    circle(lx - cell * 0.04, ly - cell * 0.04, cell * 0.04, Color.White.op(if (alarm) 0.9 else 0.35))
    circleStroke(lx, ly, cell * 0.14, CBInk, u)
}
