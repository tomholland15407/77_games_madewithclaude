package com.gogs.bananagame.games.breach

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
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

/** Brain — Breach (iOS BreachGame.swift): blast brick with limited C4 to reach the vault before the guards. */
object BreachGame {
    val definition = GameDefinition(
        id = "breach",
        title = "Breach",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Reach the vault. Move with the d-pad.",
                "Face a brick wall and tap BREACH to blast a hole — each blast costs one charge.",
                "Charges are limited, so pick the shortest route.",
                "Guards chase you through your holes; beat them and the clock to the vault.",
            ),
            bulletsVI = listOf(
                "Đến két sắt. Di chuyển bằng d-pad.",
                "Đối mặt tường gạch và chạm PHÁ để nổ một lỗ — mỗi lần nổ tốn một lượt.",
                "Số lần phá có hạn, nên hãy chọn đường ngắn nhất.",
                "Lính gác đuổi theo qua các lỗ của bạn; hãy vượt chúng và đồng hồ để tới két.",
            ),
            liveDemo = true
        ),
        prefetch = { level -> BoardCache.prefetch(key(level)) { BreachGen.generate(level) } },
        content = { level, onWin, onFail -> BreachView(level, onWin, onFail) }
    )

    fun key(level: Int) = BoardCache.key("breach", level)
}

const val B_COLS = 11
const val B_ROWS = 15
enum class BTile { FLOOR, SOLID, BRICK }
data class BP(val r: Int, val c: Int)
class BGuard(var x: Double, var y: Double)
class BBoard(val grid: Array<Array<BTile>>, val player: BP, val target: BP, val guards: List<BGuard>)

object BreachGen {
    fun brickDensity(level: Int) = listOf(0.35, 0.42, 0.48, 0.55, 0.62, 0.70, 0.78)[min(level, 7) - 1]
    fun breachBudget(level: Int) = listOf(7, 7, 6, 5, 5, 4, 4)[min(level, 7) - 1]
    fun guardCount(level: Int) = listOf(1, 1, 2, 2, 3, 3, 4)[min(level, 7) - 1]
    private fun manhattan(a: BP, b: BP) = abs(a.r - b.r) + abs(a.c - b.c)

    fun generate(level: Int): BBoard {
        repeat(200) { tryBuild(level)?.let { return it } }
        val g = Array(B_ROWS) { Array(B_COLS) { BTile.FLOOR } }
        for (r in 0 until B_ROWS) { g[r][0] = BTile.SOLID; g[r][B_COLS - 1] = BTile.SOLID }
        for (c in 0 until B_COLS) { g[0][c] = BTile.SOLID; g[B_ROWS - 1][c] = BTile.SOLID }
        for (c in 1 until B_COLS - 1) g[B_ROWS / 2][c] = BTile.BRICK
        return BBoard(g, BP(B_ROWS - 2, B_COLS / 2), BP(1, B_COLS / 2), listOf(BGuard(B_COLS / 2.0, 2.5)))
    }

    fun tryBuild(level: Int): BBoard? {
        val g = Array(B_ROWS) { Array(B_COLS) { BTile.FLOOR } }
        for (r in 0 until B_ROWS) { g[r][0] = BTile.SOLID; g[r][B_COLS - 1] = BTile.SOLID }
        for (c in 0 until B_COLS) { g[0][c] = BTile.SOLID; g[B_ROWS - 1][c] = BTile.SOLID }
        val start = BP(B_ROWS - 2, B_COLS / 2); val target = BP(1, B_COLS / 2)
        for (r in 2 until B_ROWS - 2) for (c in 1 until B_COLS - 1) {
            val p = BP(r, c)
            if (manhattan(p, start) <= 1 || manhattan(p, target) <= 1) continue
            if (rnd(0.0, 1.0) < brickDensity(level)) g[r][c] = BTile.BRICK
        }
        repeat(level) {
            val r = rndInt(3..(B_ROWS - 4)); val c = rndInt(2..(B_COLS - 3))
            val p = BP(r, c)
            if (manhattan(p, start) > 2 && manhattan(p, target) > 2) g[r][c] = BTile.SOLID
        }
        g[start.r][start.c] = BTile.FLOOR; g[target.r][target.c] = BTile.FLOOR
        val cost = minBreaches(start, target, g) ?: return null
        if (cost < 2 || cost > breachBudget(level)) return null
        return BBoard(g, start, target, placeGuards(start, target, g, guardCount(level)))
    }

    /** 0-1 BFS: cost = bricks broken. */
    fun minBreaches(s: BP, t: BP, g: Array<Array<BTile>>): Int? {
        val best = Array(B_ROWS) { IntArray(B_COLS) { Int.MAX_VALUE } }
        best[s.r][s.c] = 0
        val dq = ArrayDeque<Pair<BP, Int>>(); dq.add(s to 0)
        while (dq.isNotEmpty()) {
            val (cur, cost) = dq.removeFirst()
            if (cost > best[cur.r][cur.c]) continue
            if (cur == t) return cost
            for (n in listOf(BP(cur.r - 1, cur.c), BP(cur.r + 1, cur.c), BP(cur.r, cur.c - 1), BP(cur.r, cur.c + 1))) {
                if (n.r !in 0 until B_ROWS || n.c !in 0 until B_COLS) continue
                val tile = g[n.r][n.c]
                if (tile == BTile.SOLID) continue
                val nc = cost + if (tile == BTile.BRICK) 1 else 0
                if (nc < best[n.r][n.c]) {
                    best[n.r][n.c] = nc
                    if (tile == BTile.BRICK) dq.addLast(n to nc) else dq.addFirst(n to nc)
                }
            }
        }
        return if (best[t.r][t.c] == Int.MAX_VALUE) null else best[t.r][t.c]
    }

    fun placeGuards(start: BP, target: BP, g: Array<Array<BTile>>, count: Int): List<BGuard> {
        val open = ArrayList<BP>()
        for (r in 1 until B_ROWS - 1) for (c in 1 until B_COLS - 1) if (g[r][c] == BTile.FLOOR) {
            val p = BP(r, c); if (manhattan(p, start) >= 4) open.add(p)
        }
        open.sortBy { manhattan(it, target) }
        val gs = ArrayList<BGuard>()
        for (p in open) {
            if (gs.all { hypot(it.x - (p.c + 0.5), it.y - (p.r + 0.5)) >= 2 }) {
                gs.add(BGuard(p.c + 0.5, p.r + 0.5)); if (gs.size == count) break
            }
        }
        while (gs.size < count) gs.add(BGuard(target.c + 0.5, target.r + 1.5))
        return gs
    }
}

private class Blast(val cell: BP, val t0: Double)

private class BreachWorld(val level: Int) {
    val budget = BreachGen.breachBudget(level)
    val guardSpeed = listOf(1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.2)[min(level, 7) - 1]
    val timeLimit = (46 - level * 3).toDouble()
    val moveInterval = 0.13
    var playing = true
    var grid = Array(B_ROWS) { Array(B_COLS) { BTile.SOLID } }
    var guards = mutableListOf<BGuard>()
    var player = BP(1, 1)
    var target = BP(1, 1)
    var facing = 0 to -1
    var moveDir = 0 to 0
    var stepCD = 0.0
    var charges = 0
    var timeLeft = timeLimit
    val rubble = HashSet<BP>()
    val blasts = ArrayList<Blast>()
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    fun load(b: BBoard) {
        grid = b.grid; player = b.player; target = b.target; guards = b.guards.toMutableList()
        rubble.clear(); blasts.clear(); charges = budget; facing = 0 to -1; moveDir = 0 to 0; stepCD = 0.0
        timeLeft = timeLimit; playing = true
    }

    fun demoSetup() {
        val g = Array(B_ROWS) { Array(B_COLS) { BTile.BRICK } }
        for (r in 0 until B_ROWS) { g[r][0] = BTile.SOLID; g[r][B_COLS - 1] = BTile.SOLID }
        for (c in 0 until B_COLS) { g[0][c] = BTile.SOLID; g[B_ROWS - 1][c] = BTile.SOLID }
        for (r in 1 until B_ROWS - 1) g[r][5] = BTile.FLOOR
        g[4][5] = BTile.BRICK
        load(BBoard(g, BP(5, 5), BP(1, 5), listOf(BGuard(5.5, 12.5))))
    }

    fun step(dt: Double) {
        if (!playing) return
        stepCD -= dt
        if (moveDir != (0 to 0) && stepCD <= 0) { tryStep(moveDir.first, moveDir.second); stepCD = moveInterval }
        val px = player.c + 0.5; val py = player.r + 0.5
        for (g in guards) chase(g, px, py, dt)
        if (guards.any { hypot(it.x - px, it.y - py) < 0.6 }) { fail(); return }
        if (player == target) { win(); return }
        timeLeft -= dt
        if (timeLeft <= 0) { timeLeft = 0.0; fail() }
    }

    fun tryStep(dc: Int, dr: Int) {
        val t = BP(player.r + dr, player.c + dc)
        if (t.r !in 0 until B_ROWS || t.c !in 0 until B_COLS || grid[t.r][t.c] != BTile.FLOOR) return
        player = t
        SoundManager.tap()
    }

    fun breach() {
        if (!playing || charges <= 0) return
        val a = BP(player.r + facing.second, player.c + facing.first)
        if (a.r !in 0 until B_ROWS || a.c !in 0 until B_COLS || grid[a.r][a.c] != BTile.BRICK) { SoundManager.error(); return }
        grid[a.r][a.c] = BTile.FLOOR
        rubble.add(a)
        blasts.add(Blast(a, nowSec()))
        charges -= 1
        SoundManager.tap(); Haptics.warning()
    }

    fun canGuardStand(x: Double, y: Double): Boolean {
        val rad = 0.3
        for (cx in doubleArrayOf(x - rad, x + rad)) for (cy in doubleArrayOf(y - rad, y + rad)) {
            val r = floor(cy).toInt(); val c = floor(cx).toInt()
            if (r !in 0 until B_ROWS || c !in 0 until B_COLS) return false
            if (grid[r][c] != BTile.FLOOR) return false
        }
        return true
    }

    fun chase(e: BGuard, px: Double, py: Double, dt: Double) {
        val dx = px - e.x; val dy = py - e.y
        val d = hypot(dx, dy)
        if (d <= 0.05) return
        val sp = guardSpeed * dt
        val nx = dx / d * sp; val ny = dy / d * sp
        if (abs(dx) >= abs(dy)) {
            if (canGuardStand(e.x + nx, e.y)) e.x += nx else if (canGuardStand(e.x, e.y + ny)) e.y += ny
        } else {
            if (canGuardStand(e.x, e.y + ny)) e.y += ny else if (canGuardStand(e.x + nx, e.y)) e.x += nx
        }
    }

    fun win() { if (!playing) return; playing = false; Haptics.success(); SoundManager.tap(); onWin() }
    fun fail() { if (!playing) return; playing = false; Haptics.warning(); SoundManager.error(); onFail() }
}

@Composable
private fun BreachView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { BreachWorld(level) }
    world.onWin = onWin; world.onFail = onFail
    var ready by remember { mutableStateOf(false) }
    var demoDir by remember { mutableStateOf<Pair<Int, Int>?>(null) }
    var demoPress by remember { mutableStateOf(false) }
    var tickD by remember { mutableStateOf(0) }

    val tick by rememberFrameLoop(running = ready && !isDemo) { dt -> world.step(dt) }
    val blastTick by rememberFrameLoop(running = ready)

    LaunchedEffect(Unit) {
        if (isDemo) {
            suspend fun demoWait(dur: Double) {
                val steps = max(1, (dur / 0.016).toInt())
                repeat(steps) {
                    val px = world.player.c + 0.5; val py = world.player.r + 0.5
                    for (g in world.guards) world.chase(g, px, py, 0.016)
                    tickD++
                    delay(16)
                }
            }
            while (isActive) {
                world.demoSetup(); ready = true
                demoWait(0.7)
                world.facing = 0 to -1; demoDir = 0 to -1
                demoWait(0.5)
                demoPress = true
                world.breach()
                demoWait(0.35)
                demoPress = false
                demoWait(0.3)
                repeat(3) {
                    demoDir = 0 to -1
                    world.tryStep(0, -1)
                    demoWait(0.28)
                    demoDir = null
                    demoWait(0.22)
                }
                if (world.player == world.target) world.win()
                demoWait(1.2)
            }
        } else {
            val t0 = System.currentTimeMillis()
            val board = BoardCache.take(BreachGame.key(level)) { BreachGen.generate(level) }
            BoardCache.holdBrainstorm(t0, 1.0)
            world.load(board)
            ready = true
        }
    }

    if (!ready) { BrainstormingView(gray(0.11), gray(0.04)); return }

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .background(rgb(0.1, 0.1, 0.12))
            .padding(top = if (isDemo) 8.dp else 12.dp, bottom = if (isDemo) 8.dp else 10.dp, start = if (isDemo) 6.dp else 10.dp, end = if (isDemo) 6.dp else 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(if (isDemo) 6.dp else 10.dp)
    ) {
        tick; tickD
        Row(horizontalArrangement = Arrangement.spacedBy(if (isDemo) 4.dp else 6.dp)) {
            for (i in 0 until world.budget) {
                Canvas(Modifier.size(if (isDemo) 22.dp else 28.dp, if (isDemo) 15.dp else 19.dp)) {
                    HeistArt.c4(this, 0.0, 0.0, size.width.toDouble(), size.height.toDouble(), i < world.charges)
                }
            }
        }
        if (!isDemo) TimeBar(world.timeLeft / world.timeLimit, Modifier.fillMaxWidth().padding(horizontal = 50.dp).height(5.dp))
        Canvas(Modifier.fillMaxWidth().weight(1f).clip(RoundedCornerShape(if (isDemo) 8.dp else 12.dp))) {
            tick; tickD; blastTick
            val w = size.width.toDouble(); val h = size.height.toDouble()
            val shownRows = if (isDemo) 11 else B_ROWS
            val cell = min(w / B_COLS, h / shownRows)
            val ox = (w - cell * B_COLS) / 2; val oy = (h - cell * shownRows) / 2
            heistFloor(cell, ox, oy)
            drawHeist(world, cell, ox, oy)
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = if (isDemo) 16.dp else 24.dp), verticalAlignment = Alignment.CenterVertically) {
            if (isDemo) {
                Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    for ((dc, dr) in listOf(-1 to 0, 0 to -1, 0 to 1, 1 to 0)) PadKey(dc, dr, world, true, demoDir)
                }
            } else {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    PadKey(0, -1, world, false, null)
                    Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) { PadKey(-1, 0, world, false, null); PadKey(1, 0, world, false, null) }
                    PadKey(0, 1, world, false, null)
                }
            }
            Spacer(Modifier.weight(1f))
            BreachButton(world, isDemo, demoPress)
        }
    }
}

@Composable
private fun PadKey(dc: Int, dr: Int, world: BreachWorld, isDemo: Boolean, demoDir: Pair<Int, Int>?) {
    var held by remember { mutableStateOf(false) }
    val pressed = (demoDir?.first == dc && demoDir.second == dr) || held
    val sc by animateFloatAsState(if (pressed) 0.9f else 1f, tween(100), label = "k")
    val icon: ImageVector = when {
        dr < 0 -> Icons.Filled.KeyboardArrowUp; dr > 0 -> Icons.Filled.KeyboardArrowDown
        dc < 0 -> Icons.Filled.KeyboardArrowLeft; else -> Icons.Filled.KeyboardArrowRight
    }
    Box(
        Modifier.scale(sc).size(if (isDemo) 44.dp else 62.dp, if (isDemo) 34.dp else 44.dp)
            .background(if (pressed) BananaTheme.banana else gray(0.24), RoundedCornerShape(10.dp))
            .border(1.dp, Color.White.op(if (pressed) 0.0 else 0.12), RoundedCornerShape(10.dp))
            .then(if (isDemo) Modifier else Modifier.pressDown(
                onDown = {
                    held = true
                    if (world.playing) {
                        world.facing = dc to dr
                        if (world.moveDir != (dc to dr)) { world.moveDir = dc to dr; world.stepCD = 0.0 }
                    }
                },
                onUp = { held = false; if (world.moveDir == (dc to dr)) world.moveDir = 0 to 0 })),
        contentAlignment = Alignment.Center
    ) { Icon(icon, null, tint = if (pressed) Color.Black else Color.White, modifier = Modifier.size(if (isDemo) 20.dp else 28.dp)) }
}

@Composable
private fun BreachButton(world: BreachWorld, isDemo: Boolean, demoPress: Boolean) {
    val sc by animateFloatAsState(if (demoPress) 0.88f else 1f, tween(100), label = "b")
    val live = world.charges > 0
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp),
        modifier = if (isDemo) Modifier else Modifier.pressDown(onDown = { if (world.charges > 0) world.breach() })) {
        Canvas(Modifier.size(if (isDemo) 40.dp else 70.dp)) {
            val s = size.width.toDouble(); val c = s / 2
            val stripes = List(12) { if (it % 2 == 0) rgb(0.98, 0.8, 0.1) else gray(0.1) }
            circle(c, c, c, Brush.sweepGradient(stripes + stripes.first(), off(c, c)))
            val pad = (if (isDemo) 5.0 else 8.0) * density
            val r = (c - pad) * sc
            circle(c, c + (if (demoPress) 1.0 else 3.0) * density, r, Color.Black.op(0.4))
            circle(c, c, r, radial(if (live) listOf(rgb(1.0, 0.45, 0.4), rgb(0.8, 0.06, 0.06)) else listOf(gray(0.55), gray(0.3)),
                c - r * 0.2, c - r * 0.3, (if (isDemo) 16.0 else 28.0) * density))
            if (demoPress) circleStroke(c, c, c - 1.5 * density, Color.White, 3.0 * density)
        }
        if (!isDemo) Text(L("BREACH", "PHÁ"), style = ts(14.0, FontWeight.Black, if (live) Color.White else Color.White.op(0.4)))
    }
}

private fun DrawScope.heistFloor(cell: Double, ox: Double, oy: Double) {
    drawRect(rgb(0.12, 0.12, 0.14))
    for (r in 0 until B_ROWS) for (c in 0 until B_COLS) {
        val x = ox + c * cell; val y = oy + r * cell
        rect(x, y, cell, cell, if ((r + c) % 2 == 0) rgb(0.93, 0.91, 0.86) else rgb(0.8, 0.79, 0.76))
        val k = ((r * 17 + c * 29) % 10) / 10.0
        val vein = Path(); vein.m(x, y + cell * k); vein.q(x + cell / 2, y + cell * 0.3, x + cell, y + cell * (1 - k * 0.6))
        strokePath(vein, Color.Black.op(0.07), 0.8)
        rectStroke(x, y, cell, cell, Color.Black.op(0.08), 0.6)
    }
}

private fun DrawScope.drawHeist(w: BreachWorld, cell: Double, ox: Double, oy: Double) {
    fun rx(c: Int) = ox + c * cell
    fun ry(r: Int) = oy + r * cell
    for (p in w.rubble) HeistArt.rubble(this, rx(p.c), ry(p.r), cell, p.r * 31 + p.c)
    for (r in 0 until B_ROWS) for (c in 0 until B_COLS) when (w.grid[r][c]) {
        BTile.FLOOR -> {}
        BTile.SOLID -> HeistArt.steel(this, rx(c), ry(r), cell)
        BTile.BRICK -> HeistArt.brick(this, rx(c), ry(r), cell, r)
    }
    HeistArt.vault(this, rx(w.target.c) + cell / 2, ry(w.target.r) + cell / 2, cell)
    val ppx = ox + (w.player.c + 0.5) * cell; val ppy = oy + (w.player.r + 0.5) * cell
    for (g in w.guards) HeistArt.guardman(this, ox + g.x * cell, oy + g.y * cell, ppx, ppy, cell)
    HeistArt.burglar(this, ppx, ppy, w.facing, cell)
    val now = nowSec()
    w.blasts.removeAll { now - it.t0 > 0.7 }
    for (b in w.blasts) HeistArt.blast(this, rx(b.cell.c), ry(b.cell.r), cell, now - b.t0)
}

private object HeistArt {
    fun c(r: Double, g: Double, b: Double) = rgb(r, g, b)
    val brickRed = c(0.72, 0.28, 0.17)

    fun steel(d: DrawScope, x: Double, y: Double, s: Double) = with(d) {
        rect(x - 0.3, y - 0.3, s + 0.6, s + 0.6, lin(listOf(c(0.42, 0.45, 0.5), c(0.26, 0.28, 0.32)), x, y, x + s, y + s))
        rectStroke(x + s * 0.06, y + s * 0.06, s * 0.88, s * 0.88, Color.White.op(0.1), 1.0)
        val rv = s * 0.07
        for ((fx, fy) in listOf(0.2 to 0.2, 0.8 to 0.2, 0.2 to 0.8, 0.8 to 0.8)) {
            val px = x + s * fx; val py = y + s * fy
            circle(px, py, rv, c(0.62, 0.64, 0.68))
            circle(px + rv * 0.3, py + rv * 0.3, rv * 0.6, c(0.2, 0.21, 0.24))
        }
    }

    fun brick(d: DrawScope, x: Double, y: Double, s: Double, row: Int) = with(d) {
        rect(x - 0.3, y - 0.3, s + 0.6, s + 0.6, c(0.5, 0.42, 0.36))
        clipRect(x.f, y.f, (x + s).f, (y + s).f) {
            val ch = s / 3; val bw = s / 2
            for (k in 0 until 3) {
                val yy = y + k * ch
                val shift = if ((row * 3 + k) % 2 == 0) 0.0 else bw / 2
                for (i in -1..2) {
                    val bx = x + i * bw + shift + 0.8; val by = yy + 0.8; val ww = bw - 1.6; val hh = ch - 1.6
                    val tone = ((row * 7 + k * 3 + i * 5 + 50) % 5) * 0.03
                    val base = brickRed.shade(tone)
                    rrect(bx, by, ww, hh, 1.0, base)
                    val e = max(0.8, ch * 0.16)
                    rect(bx, by, ww, e, base.lit(0.25))
                    rect(bx, by + hh - e, ww, e, base.shade(0.25))
                }
            }
        }
    }

    fun rubble(d: DrawScope, x: Double, y: Double, s: Double, seed: Int) = with(d) {
        val mx = x + s / 2; val my = y + s / 2
        circle(mx, my, s * 0.42, c(0.4, 0.38, 0.35).op(0.25))
        for (k in 0 until 6) {
            val a = (seed * 13 + k * 61).toDouble()
            val qx = mx + cos(a) * s * 0.3; val qy = my + sin(a * 1.3) * s * 0.3
            translate(qx.f, qy.f) {
                rotate((a * 180 / PI).f, androidx.compose.ui.geometry.Offset.Zero) {
                    val ss = s * (0.1 + 0.04 * (k % 3))
                    rect(-ss / 2, -ss * 0.3, ss, ss * 0.6, brickRed.shade(0.1))
                }
            }
        }
    }

    fun vault(d: DrawScope, px: Double, py: Double, cell: Double) = with(d) {
        val R = cell * 0.78
        circle(px, py, R * 1.9, radial(listOf(c(1.0, 0.85, 0.35).op(0.45), Color.Transparent), px, py, R * 1.9))
        circle(px, py, R * 1.1, c(0.2, 0.21, 0.24))
        circle(px, py, R, radial(listOf(c(0.9, 0.91, 0.93), c(0.62, 0.64, 0.68), c(0.4, 0.42, 0.46)), px - R * 0.3, py - R * 0.35, R * 1.3))
        circleStroke(px, py, R, c(0.25, 0.26, 0.3), max(1.0, R * 0.06))
        for (k in 0 until 10) {
            val a = k / 10.0 * 2 * PI
            circle(px + cos(a) * R * 0.82, py + sin(a) * R * 0.82, R * 0.06, c(0.3, 0.31, 0.35))
        }
        for (k in 0 until 6) {
            val a = k / 6.0 * 2 * PI + 0.3
            line(px, py, px + cos(a) * R * 0.55, py + sin(a) * R * 0.55, c(0.78, 0.62, 0.2), max(1.5, R * 0.1))
        }
        circleStroke(px, py, R * 0.5, c(0.85, 0.7, 0.25), max(1.5, R * 0.08))
        circle(px, py, R * 0.14, c(0.95, 0.8, 0.3))
    }

    fun guardman(d: DrawScope, px: Double, py: Double, tx: Double, ty: Double, cell: Double) = with(d) {
        val a = atan2(ty - py, tx - px)
        translate(px.f, py.f) {
            rotate((a * 180 / PI).f, androidx.compose.ui.geometry.Offset.Zero) {
                drawPath(polyPath(cell * 0.3, 0.0, cell * 2.3, -cell * 0.85, cell * 2.3, cell * 0.85),
                    hgrad(listOf(c(1.0, 0.96, 0.7).op(0.45), c(1.0, 0.96, 0.7).op(0.0)), cell * 0.3, cell * 2.3))
                val navy = c(0.14, 0.2, 0.44)
                oval(-cell * 0.18, -cell * 0.34, cell * 0.36, cell * 0.68, navy)
                ellipseStroke(0.0, 0.0, cell * 0.18, cell * 0.34, Color.Black.op(0.5), 1.0)
                rrect(cell * 0.05, cell * 0.12, cell * 0.3, cell * 0.1, cell * 0.04, navy.shade(0.2))
                rrect(cell * 0.3, cell * 0.1, cell * 0.12, cell * 0.14, cell * 0.03, c(0.7, 0.72, 0.76))
                circle(cell * 0.02, 0.0, cell * 0.15, navy.shade(0.35))
                oval(cell * 0.1, -cell * 0.1, cell * 0.14, cell * 0.2, navy.shade(0.5))
                circle(-cell * 0.02, -cell * 0.22, cell * 0.045, c(0.95, 0.8, 0.3))
            }
        }
    }

    fun burglar(d: DrawScope, px: Double, py: Double, facing: Pair<Int, Int>, s: Double) = with(d) {
        val a = atan2(facing.second.toDouble(), facing.first.toDouble())
        translate(px.f, py.f) {
            rotate((a * 180 / PI).f, androidx.compose.ui.geometry.Offset.Zero) {
                circle(-s * 0.24, 0.0, s * 0.17, c(0.55, 0.38, 0.2))
                circleStroke(-s * 0.24, 0.0, s * 0.17, c(0.3, 0.2, 0.08), 1.0)
                val body = Path()
                body.m(-s * 0.2, -s * 0.3)
                body.q(s * 0.2, -s * 0.36, s * 0.32, 0.0)
                body.q(s * 0.2, s * 0.36, -s * 0.2, s * 0.3)
                body.q(s * 0.05, 0.0, -s * 0.2, -s * 0.3)
                body.close()
                drawPath(body, vgrad(listOf(c(1.0, 0.93, 0.45), c(0.98, 0.78, 0.1)), -s * 0.3, s * 0.3))
                strokePath(body, c(0.45, 0.3, 0.05), max(1.0, s * 0.04))
                clipPath(body) { rect(s * 0.05, -s * 0.4, s * 0.14, s * 0.8, c(0.1, 0.1, 0.12)) }
                for (side in listOf(-1.0, 1.0)) {
                    circle(s * 0.13, side * s * 0.12, s * 0.05, Color.White)
                    circle(s * 0.15, side * s * 0.12, s * 0.025, Color.Black)
                }
                drawPath(polyPath(s * 0.52, 0.0, s * 0.4, -s * 0.08, s * 0.4, s * 0.08), Color.White)
            }
        }
    }

    fun blast(d: DrawScope, x: Double, y: Double, s: Double, t: Double) = with(d) {
        if (t < 0 || t >= 0.7) return@with
        val px = x + s / 2; val py = y + s / 2
        for (k in 0 until 5) {
            val a = k * 1.26 + 0.4
            circle(px + cos(a) * s * (0.2 + t * 0.9), py + sin(a) * s * (0.2 + t * 0.9), s * (0.22 + t * 0.4), c(0.5, 0.48, 0.45).op(max(0.0, 0.55 - t * 0.8)))
        }
        if (t < 0.35) {
            val k = t / 0.35
            val r = s * (0.4 + k * 0.7)
            circle(px, py, r, radial(listOf(Color.White, c(1.0, 0.85, 0.3), c(1.0, 0.4, 0.1), c(0.8, 0.1, 0.0).op(0.0)), px, py, r))
        }
        for (k in 0 until 8) {
            val a = k * 0.785 + 0.2
            val dd = s * (0.2 + t * 1.8)
            translate((px + cos(a) * dd).f, (py + sin(a) * dd).f) {
                rotate(((a * 3 + t * 8) * 180 / PI).f, androidx.compose.ui.geometry.Offset.Zero) {
                    val bs = s * 0.14 * max(0.0, 1 - t / 0.7)
                    rect(-bs, -bs * 0.5, bs * 2, bs, brickRed)
                }
            }
        }
    }

    fun c4(d: DrawScope, x: Double, y: Double, w: Double, h: Double, live: Boolean) = with(d) {
        withAlpha(if (live) 1.0 else 0.25) {
            val bx = x + w * 0.06; val by = y + h * 0.14; val bw = w * 0.88; val bh = h * 0.72
            rrect(bx, by, bw, bh, h * 0.12, c(0.86, 0.82, 0.7))
            rrectStroke(bx, by, bw, bh, h * 0.12, c(0.35, 0.32, 0.25), 1.0)
            rrect(bx + bw / 2 - bw * 0.18, by + bh * 0.18, bw * 0.36, bh * 0.64, 2.0, c(0.12, 0.12, 0.14))
            circle(bx + bw / 2, by + bh / 2, bh * 0.14, if (live) c(1.0, 0.2, 0.15) else c(0.4, 0.4, 0.4))
            val wire = Path(); wire.m(bx + bw * 0.12, by); wire.q(bx + bw / 2, y - h * 0.1, bx + bw - bw * 0.12, by)
            strokePath(wire, c(0.85, 0.15, 0.12), max(1.0, h * 0.08))
        }
    }
}
