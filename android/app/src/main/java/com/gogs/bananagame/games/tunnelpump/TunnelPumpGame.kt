package com.gogs.bananagame.games.tunnelpump

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
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/**
 * Reflex — Tunnel Pump (iOS DigDugGame.swift, id "dig-dug"): dig with the d-pad, PUMP a monster
 * down a clear tunnel until it bursts, or dig under a boulder to drop it on one. Bedrock can't be dug.
 * Clear every monster before the clock; caught or crushed fails. Drawn as Namco's 1982 Dig Dug.
 */
object TunnelPumpGame {
    val definition = GameDefinition(
        id = "dig-dug",
        title = "Tunnel Pump",
        genre = Genre.REFLEX,
        manual = GameManual(
            bullets = listOf(
                "Move with the d-pad to carve tunnels through the dirt.",
                "Tap PUMP to harpoon a monster down a clear tunnel and inflate it — keep pumping until it bursts.",
                "Dig out the dirt under a boulder to drop it and crush monsters beneath; grey bedrock can't be dug.",
                "Clear every monster before the clock runs out; caught, crushed, or timed out sends you to level 1.",
            ),
            bulletsVI = listOf(
                "Di chuyển bằng d-pad để đào đường hầm xuyên qua đất.",
                "Chạm BƠM để phóng lao vào quái trong đường hầm thông và bơm phồng nó — bơm liên tục đến khi nó nổ.",
                "Đào đất dưới một tảng đá để thả nó đè quái bên dưới; đá xám không đào được.",
                "Dọn hết quái trước khi hết giờ; bị bắt, bị đè, hoặc hết giờ sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> TunnelPumpView(level, onWin, onFail) }
    )
}

private const val COLS = 9
private const val ROWS = 13

private data class Cell(val r: Int, val c: Int)
private class Enemy(val id: Int, var cell: Cell, var inflate: Double, var deflateDelay: Double, val kind: Int, var left: Boolean? = null)
private class Burst(val cell: Cell, val color: Color, val t0: Double, val seed: Int)
private class Harpoon(val from: Cell, val dir: Cell, val len: Int)

private fun inBounds(p: Cell) = p.r in 0 until ROWS && p.c in 0 until COLS
private fun manhattan(a: Cell, b: Cell) = abs(a.r - b.r) + abs(a.c - b.c)
private val DIRS = listOf(Cell(-1, 0), Cell(1, 0), Cell(0, -1), Cell(0, 1))
private fun monsterColor(k: Int) = if (k == 0) rgb(0.93, 0.2, 0.16) else rgb(0.3, 0.74, 0.3)

private class DigWorld(val level: Int, val isDemo: Boolean) {
    private val li = min(level, 7) - 1
    val enemyN = listOf(2, 2, 3, 3, 4, 4, 5)[li]
    val enemyStep = listOf(0.62, 0.56, 0.50, 0.44, 0.39, 0.34, 0.30)[li]
    // The red monster ghosts THROUGH dirt toward the player: per-move chance to start a shortcut.
    val ghostChance = listOf(0.40, 0.50, 0.60, 0.68, 0.76, 0.84, 0.92)[li]
    val pumps = if (level >= 5) 4 else 3
    val rockN = listOf(1, 2, 2, 3, 3, 4, 4)[li]
    val bedrockN = listOf(0, 1, 2, 2, 3, 3, 4)[li]
    val timeLimit = listOf(46.0, 46.0, 44.0, 42.0, 40.0, 38.0, 36.0)[li]
    // How long a freshly-unsupported rock teeters before it drops.
    val wobbleTime = max(0.30, 0.70 - level * 0.05)

    var playing = true
    var started = false
    val dug = HashSet<Cell>()
    var rocks = HashSet<Cell>()
    val rockWobble = HashMap<Cell, Double>()
    var rockFalling = HashSet<Cell>()
    val bedrock = HashSet<Cell>()
    var player = Cell(1, 4)
    var facing = Cell(0, 1)
    val enemies = mutableListOf<Enemy>()
    val bursts = mutableListOf<Burst>()
    var moveDir: Cell? = null
    var harpoon: Harpoon? = null
    var harpoonTimer = 0.0
    var moveAcc = 0.0; var enemyAcc = 0.0; var rockAcc = 0.0
    var timeLeft = timeLimit
    var shakeT0 = -10.0
    /** Bumped whenever the ground (dug cells / bedrock) changes, so the cached ground redraws. */
    var groundVersion by mutableIntStateOf(0)
    private var nextId = 0
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    fun isOpen(p: Cell) = p in dug && p !in rocks && p !in bedrock
    fun isDirt(p: Cell) = p !in dug && p !in rocks && p !in bedrock
    private fun dig(p: Cell) { if (dug.add(p)) groundVersion++ }

    private fun baseTunnels() {
        dug.clear()
        for (c in 0 until COLS) { dug.add(Cell(0, c)); dug.add(Cell(1, c)) }
        for (r in 0 until 6) dug.add(Cell(r, 4))
    }

    private fun resetCommon() {
        rockWobble.clear(); rockFalling = HashSet(); bursts.clear()
        player = Cell(1, 4); facing = Cell(0, 1)
        moveDir = null; harpoon = null; harpoonTimer = 0.0
        moveAcc = 0.0; enemyAcc = 0.0; rockAcc = 0.0
        timeLeft = timeLimit; playing = true
        groundVersion++
    }

    fun setup() {
        baseTunnels()
        val used = HashSet<Cell>(dug); used.add(Cell(1, 4))
        // Bedrock (indestructible) in the lower dirt.
        val bed = HashSet<Cell>(); var tries = 0
        while (bed.size < bedrockN && tries < 80) {
            tries++
            val cell = Cell(Random.nextInt(4, ROWS), Random.nextInt(COLS))
            if (cell in used) continue
            bed.add(cell); used.add(cell)
        }
        // Rocks sit in dirt with dirt below them (upper-middle strata so they have room to fall).
        val rk = HashSet<Cell>(); tries = 0
        while (rk.size < rockN && tries < 120) {
            tries++
            val cell = Cell(Random.nextInt(3, 8), Random.nextInt(COLS))
            val below = Cell(cell.r + 1, cell.c)
            if (cell in used || below in used || below in dug) continue
            rk.add(cell); used.add(cell)
        }
        // Each monster gets its own carved room of at least 3 open cells.
        fun carvable(of: Cell) = DIRS.map { Cell(of.r + it.r, of.c + it.c) }.filter { n ->
            inBounds(n) && n.r >= 3 && n !in bed && n !in rk && Cell(n.r - 1, n.c) !in rk && n !in used
        }
        enemies.clear()
        for (i in 0 until enemyN) {
            var chosen: Cell? = null; var room = emptyList<Cell>(); var t = 0
            while (chosen == null && t < 160) {
                t++
                val cell = Cell(Random.nextInt(5, ROWS), Random.nextInt(COLS))
                if (cell in used || manhattan(cell, player) < 5) continue
                if (Cell(cell.r - 1, cell.c) in rk) continue
                val cv = carvable(cell)
                if (cv.size < 2) continue
                chosen = cell; room = cv.shuffled().take(min(3, cv.size))
            }
            if (chosen == null) {
                outer@ for (r in (5 until ROWS).shuffled()) for (c in (0 until COLS).shuffled()) {
                    val cell = Cell(r, c)
                    if (cell !in used && manhattan(cell, player) >= 3) { chosen = cell; break@outer }
                }
            }
            val cell = chosen ?: continue
            used.add(cell); dug.add(cell)
            for (n in room) { dug.add(n); used.add(n) }
            enemies.add(Enemy(nextId++, cell, 0.0, 0.0, i % 2))
        }
        rocks = rk; bedrock.clear(); bedrock.addAll(bed)
        started = false
        resetCommon()
    }

    /** A fixed level-1 dig: the red phaser to pump, the green one penned under the boulder. */
    fun demoSetup() {
        baseTunnels()
        for (cell in listOf(Cell(8, 4), Cell(8, 3), Cell(9, 4), Cell(5, 6), Cell(6, 6), Cell(7, 6))) dug.add(cell)
        rocks = hashSetOf(Cell(3, 6)); bedrock.clear()
        enemies.clear()
        enemies.add(Enemy(nextId++, Cell(8, 4), 0.0, 0.0, 0)); enemies.add(Enemy(nextId++, Cell(6, 6), 0.0, 0.0, 1))
        started = true
        resetCommon()
    }

    fun fire() {
        if (!playing || !started) return
        var len = 0; var hit: Enemy? = null; var pierced = false   // the pump can punch through ONE thin dirt wall
        for (step in 1..3) {
            val cell = Cell(player.r + facing.r * step, player.c + facing.c * step)
            if (!inBounds(cell)) break
            if (cell in rocks || cell in bedrock) break
            if (isDirt(cell)) { if (pierced) break; pierced = true; len = step; continue }
            len = step
            val e = enemies.firstOrNull { it.cell == cell }
            if (e != null) { hit = e; break }
        }
        harpoon = Harpoon(player, facing, max(1, len)); harpoonTimer = 0.16
        SoundManager.tap(); Haptics.tap()
        if (hit != null) {
            hit.inflate = min(pumps.toDouble(), hit.inflate + 1); hit.deflateDelay = 0.9
            if (hit.inflate >= pumps) pop(hit)
        }
    }

    private fun pop(e: Enemy) {
        bursts.add(Burst(e.cell, monsterColor(e.kind), nowSec(), e.id))
        enemies.remove(e)
        shakeT0 = nowSec()
        if (enemies.isEmpty()) win()
    }

    fun tick(dt: Double) {
        if (!playing) return
        if (harpoonTimer > 0) { harpoonTimer -= dt; if (harpoonTimer <= 0) harpoon = null }
        bursts.removeAll { nowSec() - it.t0 > 0.6 }
        // Deflate monsters that aren't being pumped.
        for (e in enemies) if (e.inflate > 0) {
            e.deflateDelay -= dt
            if (e.deflateDelay <= 0) e.inflate = max(0.0, e.inflate - 1.4 * dt)
        }
        // Player movement (hold to repeat).
        moveAcc += dt
        val mv = moveDir
        if (mv != null && moveAcc >= 0.13) {
            moveAcc = 0.0
            val dest = Cell(player.r + mv.r, player.c + mv.c)
            if (inBounds(dest) && dest !in rocks && dest !in bedrock) { player = dest; dig(dest); SoundManager.tap() }
        }
        if (checkCaught()) return
        // Rocks: an unsupported boulder teeters for a beat before it commits to falling.
        for (rock in rocks.toList()) {
            if (rock in rockFalling) continue
            val below = Cell(rock.r + 1, rock.c)
            val unsupported = inBounds(below) && below in dug && below !in rocks && below !in bedrock
            if (unsupported) {
                val w = rockWobble[rock]
                if (w == null) { rockWobble[rock] = wobbleTime; SoundManager.tap() }
                else { val nw = w - dt; if (nw <= 0) { rockWobble.remove(rock); rockFalling.add(rock) } else rockWobble[rock] = nw }
            } else rockWobble.remove(rock)
        }
        rockAcc += dt
        if (rockAcc >= 0.11) { rockAcc = 0.0; fallRocks() }
        if (!playing) return
        // Enemy movement.
        enemyAcc += dt
        if (enemyAcc >= enemyStep) {
            enemyAcc = 0.0
            for (e in enemies) moveEnemy(e)
            checkCaught()
        }
    }

    private fun fallRocks() {
        val rk = HashSet(rocks); val falling = HashSet(rockFalling)
        // Only rocks that finished wobbling drop; process bottom-up.
        for (rock in rocks.sortedByDescending { it.r }) {
            if (rock !in falling || rock !in rk) continue
            val below = Cell(rock.r + 1, rock.c)
            // A falling boulder smashes ANY monster beneath it, even one phasing through dirt.
            if (inBounds(below)) enemies.firstOrNull { it.cell == below }?.let { e ->
                bursts.add(Burst(below, monsterColor(e.kind), nowSec(), e.id)); enemies.remove(e); shakeT0 = nowSec()
            }
            if (!inBounds(below) || below !in dug || below in rk || below in bedrock) { falling.remove(rock); continue }
            rk.remove(rock); rk.add(below)
            falling.remove(rock); falling.add(below)
            dig(rock)                                         // vacated cell becomes tunnel
            shakeT0 = nowSec()
            SoundManager.tap()
            if (below == player) { rocks = rk; rockFalling = falling; fail(); return }
        }
        rocks = rk; rockFalling = falling
        if (enemies.isEmpty() && playing) win()
    }

    private fun moveEnemy(e: Enemy) {
        if (e.inflate > 0) return
        val oldC = e.cell.c
        val cur = manhattan(e.cell, player)
        val nbrs = DIRS.map { Cell(e.cell.r + it.r, e.cell.c + it.c) }.filter { inBounds(it) && it !in rocks && it !in bedrock }
        // Closest to the player, preferring a cell no other monster occupies (never stack into one blob).
        fun choose(cells: List<Cell>): Cell? {
            val free = cells.filter { c -> enemies.none { it.id != e.id && it.cell == c } }
            return (free.ifEmpty { cells }).minByOrNull { manhattan(it, player) }
        }
        val openBetter = choose(nbrs.filter { isOpen(it) && manhattan(it, player) < cur })
        var next: Cell? = null
        if (e.kind == 0) {
            // RED phaser: ghosts through dirt toward you; once in dirt it keeps going. Demo always phases.
            if (isDirt(e.cell) || isDemo || Random.nextDouble() < ghostChance) next = choose(nbrs.filter { manhattan(it, player) < cur })
            if (next == null) next = openBetter ?: choose(nbrs.filter { isOpen(it) }) ?: choose(nbrs)
        } else {
            // GREEN monster: tunnel-bound.
            next = openBetter ?: choose(nbrs.filter { isOpen(it) })
        }
        if (next != null) { e.cell = next; if (next.c != oldC) e.left = next.c < oldC }
    }

    fun checkCaught(): Boolean {
        if (enemies.any { it.cell == player && it.inflate == 0.0 }) { fail(); return true }
        return false
    }

    fun win() { if (!playing) return; playing = false; onWin() }
    fun fail() { if (!playing) return; playing = false; shakeT0 = nowSec(); SoundManager.error(); onFail() }
}

private sealed class DemoInput { class Hold(val d: Cell) : DemoInput(); object Release : DemoInput(); object Pump : DemoInput() }
private val demoScript: List<Pair<Int, DemoInput>> = listOf(
    6 to DemoInput.Hold(Cell(1, 0)), 9 to DemoInput.Release,                 // step down, face the shaft
    58 to DemoInput.Pump, 64 to DemoInput.Pump, 70 to DemoInput.Pump,        // red monster: pop
    72 to DemoInput.Hold(Cell(1, 0)), 79 to DemoInput.Release,               // down to row 4
    80 to DemoInput.Hold(Cell(0, 1)), 87 to DemoInput.Release,               // dig in under the boulder
    91 to DemoInput.Hold(Cell(0, -1)), 98 to DemoInput.Release,              // dash back to the shaft…
    99 to DemoInput.Hold(Cell(-1, 0)), 105 to DemoInput.Release,             // …and up, clear of the drop
)

@Composable
private fun TunnelPumpView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { DigWorld(level, isDemo).also { if (isDemo) it.demoSetup() else it.setup() } }
    world.onWin = onWin; world.onFail = onFail
    var demoTick by remember { mutableIntStateOf(0) }
    var demoPump by remember { mutableIntStateOf(0) }
    val start = remember { nowSec() }
    var acc = remember { doubleArrayOf(0.0) }
    val tick by rememberFrameLoop(maxDt = 0.08) { dt ->
        if (isDemo || !world.playing) return@rememberFrameLoop
        if (!world.started) world.started = true
        world.timeLeft = max(0.0, world.timeLimit - (nowSec() - start))
        if (world.timeLeft <= 0) { world.fail(); return@rememberFrameLoop }
        // The iOS loop ticks at ~30 Hz; keep that step so the hold-to-move cadence matches.
        acc[0] += dt
        while (acc[0] >= 1.0 / 30 && world.playing) { world.tick(1.0 / 30); acc[0] -= 1.0 / 30 }
    }

    LaunchedEffect(Unit) {
        if (!isDemo) return@LaunchedEffect
        val dt = 1.0 / 30.0
        while (isActive) {
            world.demoSetup(); demoPump = 0
            delay(500)
            var frame = 0; var next = 0
            while (isActive && world.playing && frame < 600) {
                frame++
                while (next < demoScript.size && demoScript[next].first <= frame) {
                    when (val input = demoScript[next].second) {
                        is DemoInput.Hold -> { world.moveDir = input.d; world.facing = input.d }
                        DemoInput.Release -> world.moveDir = null
                        DemoInput.Pump -> { world.fire(); demoPump = 4 }
                    }
                    next++
                }
                if (demoPump > 0) demoPump--
                world.tick(dt)
                demoTick++
                delay(33)
            }
            world.moveDir = null; demoPump = 0
            val end = nowSec()
            while (isActive && nowSec() - end < 1.3) { demoTick++; delay(33) }
        }
    }

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .background(gray(0.03)),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(if (isDemo) 4.dp else 6.dp)
    ) {
        tick; demoTick
        // Monsters left: a Pooka and its count.
        Row(Modifier.padding(top = if (isDemo) 6.dp else 0.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            Canvas(Modifier.size(if (isDemo) 17.dp else 22.dp)) {
                pooka(size.width / 2.0, size.height / 2.0, min(size.width, size.height) * 1.05, 0.0, false, halo = false)
            }
            Text("${world.enemies.size}", style = ts(if (isDemo) 15.0 else 20.0, FontWeight.Black, Color.White).copy(fontFeatureSettings = "tnum"))
        }
        if (!isDemo) {
            val f = world.timeLeft / world.timeLimit
            TimeBar(f, Modifier.fillMaxWidth().padding(horizontal = 60.dp).height(5.dp), fill = if (f < 0.3) rgb(1.0, 0.3, 0.25) else rgb(1.0, 0.74, 0.24))
        }
        Canvas(
            Modifier.fillMaxWidth().weight(1f).clipToBounds()
                .graphicsLayer {
                    val t = nowSec() - world.shakeT0
                    if (t in 0.0..0.35) translationX = (4 * density * sin(t / 0.35 * PI * 3) * (1 - t / 0.35)).toFloat()
                }
                .drawWithCache {
                    // Sky, strata, tunnels and bedrock: re-rendered only when a cell is dug.
                    world.groundVersion
                    val bw = size.width.toInt().coerceAtLeast(1); val bh = size.height.toInt().coerceAtLeast(1)
                    val bmp = ImageBitmap(bw, bh)
                    CanvasDrawScope().draw(this, layoutDirection, androidx.compose.ui.graphics.Canvas(bmp), size) { ground(world, level) }
                    onDrawBehind { drawRect(Color.Black); drawImage(bmp) }
                }
        ) {
            tick; demoTick
            actors(world)
        }
        Row(Modifier.padding(bottom = if (isDemo) 6.dp else 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(18.dp)) {
            val g = if (isDemo) 4.dp else 6.dp
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(g)) {
                DirKey(world, Cell(-1, 0), isDemo)
                Row(horizontalArrangement = Arrangement.spacedBy(g)) {
                    DirKey(world, Cell(0, -1), isDemo); DirKey(world, Cell(1, 0), isDemo); DirKey(world, Cell(0, 1), isDemo)
                }
            }
            val lit = demoPump > 0
            Box(
                Modifier.scale(if (lit) 0.9f else 1f).size(if (isDemo) 66.dp else 76.dp, if (isDemo) 42.dp else 54.dp)
                    .then(if (isDemo) Modifier else Modifier.pressDown(onDown = { world.fire() })),
                contentAlignment = Alignment.Center
            ) {
                Canvas(Modifier.fillMaxSize()) { key(true, lit) }
                Canvas(Modifier.size(if (isDemo) 30.dp else 36.dp)) { pumpIcon() }
            }
        }
    }
}

/** An earth-brown d-pad key (yellow while held). */
@Composable
private fun DirKey(world: DigWorld, d: Cell, isDemo: Boolean) {
    val lit = world.moveDir == d && (isDemo || world.playing)
    val icon: ImageVector = when {
        d.r < 0 -> Icons.Filled.KeyboardArrowUp; d.r > 0 -> Icons.Filled.KeyboardArrowDown
        d.c < 0 -> Icons.Filled.KeyboardArrowLeft; else -> Icons.Filled.KeyboardArrowRight
    }
    Box(
        Modifier.scale(if (lit) 0.9f else 1f).size(if (isDemo) 46.dp else 56.dp, if (isDemo) 32.dp else 46.dp)
            .then(if (isDemo) Modifier else Modifier.pressDown(
                onDown = { if (world.playing) { world.moveDir = d; world.facing = d } },
                onUp = { if (world.moveDir == d) world.moveDir = null })),
        contentAlignment = Alignment.Center
    ) {
        Canvas(Modifier.fillMaxSize()) { key(false, lit) }
        Icon(icon, null, tint = if (lit) rgb(0.2, 0.08, 0.02) else Color.White, modifier = Modifier.size(if (isDemo) 22.dp else 26.dp))
    }
}

// Dig Dug art (after Namco's 1982 arcade game; iOS DDArt).

private fun hashD(n: Double): Double { val x = sin(n) * 43758.5453; return x - floor(x) }

/** Four dirt layers per level: Dig Dug's yellow → maroon at L1, a new set of earths after (never grey). */
private fun layers(level: Int) = when (min(max(level, 1), 7)) {
    1 -> listOf(rgb(1.0, 0.74, 0.24), rgb(0.95, 0.52, 0.16), rgb(0.76, 0.27, 0.12), rgb(0.52, 0.13, 0.12))
    2 -> listOf(rgb(0.98, 0.82, 0.44), rgb(0.88, 0.62, 0.32), rgb(0.68, 0.40, 0.22), rgb(0.46, 0.24, 0.15))
    3 -> listOf(rgb(0.74, 0.88, 0.34), rgb(0.48, 0.72, 0.26), rgb(0.32, 0.52, 0.22), rgb(0.19, 0.33, 0.17))
    4 -> listOf(rgb(0.96, 0.64, 0.56), rgb(0.84, 0.42, 0.44), rgb(0.62, 0.25, 0.35), rgb(0.40, 0.15, 0.25))
    5 -> listOf(rgb(0.54, 0.78, 0.96), rgb(0.34, 0.54, 0.86), rgb(0.25, 0.35, 0.68), rgb(0.15, 0.19, 0.44))
    6 -> listOf(rgb(0.80, 0.62, 0.96), rgb(0.60, 0.42, 0.84), rgb(0.42, 0.27, 0.62), rgb(0.25, 0.15, 0.40))
    else -> listOf(rgb(0.50, 0.86, 0.80), rgb(0.30, 0.66, 0.66), rgb(0.20, 0.46, 0.50), rgb(0.12, 0.28, 0.34))
}

private fun layerIndex(r: Int) = max(0, min(3, (r - 2) / 3))

private class Geo(w: Double, h: Double) {
    val cell = min(w / COLS, h / ROWS)
    val ox = (w - cell * COLS) / 2
    val oy = (h - cell * ROWS) / 2
    fun cx(c: Int) = ox + (c + 0.5) * cell
    fun cy(r: Int) = oy + (r + 0.5) * cell
}

/** Sky, stippled strata, round black tunnels, grey bedrock, and one flower per level on the surface. */
private fun DrawScope.ground(world: DigWorld, level: Int) {
    val g = Geo(size.width.toDouble(), size.height.toDouble())
    val cell = g.cell; val ox = g.ox; val oy = g.oy
    val W = cell * COLS
    rect(ox, oy, W, cell * 2, vgrad(listOf(rgb(0.13, 0.28, 0.88), rgb(0.36, 0.58, 1.0)), oy, oy + cell * 2))
    val pal = layers(level)
    for (r in 2 until ROWS) rect(ox, oy + r * cell, W, cell + 0.5, pal[layerIndex(r)])
    val dark = List(4) { Path() }; val light = List(4) { Path() }
    for (r in 2 until ROWS) for (col in 0 until COLS) {
        val p = Cell(r, col)
        if (p in world.dug || p in world.bedrock) continue
        val li = layerIndex(r)
        val x0 = ox + col * cell; val y0 = oy + r * cell
        for (k in 0 until 7) {
            val hx = hashD((r * 97 + col * 13 + k) * 1.3); val hy = hashD((r * 31 + col * 57 + k) * 2.7)
            val d = cell * (0.06 + 0.05 * hashD((k + r + col) * 5.1))
            val rc = Rect((x0 + hx * (cell - d)).f, (y0 + hy * (cell - d)).f, (x0 + hx * (cell - d) + d * 1.3).f, (y0 + hy * (cell - d) + d).f)
            if (k < 5) dark[li].addOval(rc) else light[li].addOval(rc)
        }
    }
    for (li in 0 until 4) {
        fillPath(dark[li], pal[li].mix(Color.Black, 0.32).op(0.85))
        fillPath(light[li], pal[li].mix(Color.White, 0.3).op(0.7))
    }
    val seams = Path()
    for (r in listOf(5, 8, 11)) if (r < ROWS) { seams.m(ox, oy + r * cell); seams.l(ox + W, oy + r * cell) }
    strokePath(seams, Color.Black.op(0.18), max(density.toDouble(), cell * 0.04), StrokeCap.Butt)
    rect(ox, oy + cell * 2 - 0.5, W, max(1.5 * density, cell * 0.06), pal[0].mix(Color.White, 0.35))

    // Tunnels: round-ended, bridged to dug neighbours; the top row opens into the sky.
    val tunnels = Path()
    val ins = cell * 0.05
    for (p in world.dug) {
        if (p.r < 2) continue
        val x0 = ox + p.c * cell; val y0 = oy + p.r * cell
        tunnels.addRoundRect(RoundRect((x0 + ins).f, (y0 + ins).f, (x0 + cell - ins).f, (y0 + cell - ins).f, CornerRadius((cell * 0.34).f)))
        if (p.c + 1 < COLS && Cell(p.r, p.c + 1) in world.dug) tunnels.addRect(Rect((x0 + cell * 0.5).f, (y0 + ins).f, (x0 + cell * 1.5).f, (y0 + cell - ins).f))
        if (p.r + 1 < ROWS && Cell(p.r + 1, p.c) in world.dug) tunnels.addRect(Rect((x0 + ins).f, (y0 + cell * 0.5).f, (x0 + cell - ins).f, (y0 + cell * 1.5).f))
        if (p.r == 2) tunnels.addRect(Rect((x0 + ins).f, (y0 - 1).f, (x0 + cell - ins).f, (y0 + cell * 0.5).f))
    }
    fillPath(tunnels, rgb(0.02, 0.02, 0.03))

    // Bedrock: faceted grey stone.
    for (p in world.bedrock) {
        val x = ox + p.c * cell + cell * 0.03; val y = oy + p.r * cell + cell * 0.03; val s = cell * 0.94
        rrect(x, y, s, s, cell * 0.14, lin(listOf(gray(0.66), gray(0.36)), x, y, x + s, y + s))
        val facets = Path()
        facets.m(x + s * 0.18, y + s * 0.4); facets.l(x + s / 2, y + s * 0.18); facets.l(x + s - s * 0.15, y + s / 2)
        facets.m(x + s / 2, y + s * 0.18); facets.l(x + s / 2 - s * 0.05, y + s - s * 0.2)
        strokePath(facets, Color.White.op(0.3), max(density.toDouble(), cell * 0.04))
        rrectStroke(x, y, s, s, cell * 0.14, gray(0.14), max(density.toDouble(), cell * 0.05))
    }
    // One flower per level on the surface, counting the rounds like the arcade does.
    val surface = oy + cell * 2
    for (i in 0 until min(max(level, 1), 7)) flower(ox + W - cell * 0.32 - i * cell * 0.4, surface, cell)
}

private fun DrawScope.flower(px: Double, py: Double, cell: Double) {
    val s = cell * 0.4
    val green = rgb(0.18, 0.6, 0.2)
    line(px, py, px, py - s, green, max(density.toDouble(), cell * 0.05), StrokeCap.Butt)
    oval(px, py - s * 0.55, s * 0.3, s * 0.16, green)
    val hy = py - s
    for (k in 0 until 5) {
        val a = k / 5.0 * 2 * PI - PI / 2
        circle(px + cos(a) * s * 0.22, hy + sin(a) * s * 0.22, s * 0.17, Color.White)
    }
    circle(px, hy, s * 0.14, rgb(1.0, 0.62, 0.12))
}

/** Boulders, the pump's hose, the monsters and the digger. */
private fun DrawScope.actors(world: DigWorld) {
    val g = Geo(size.width.toDouble(), size.height.toDouble())
    val cell = g.cell
    for (rk in world.rocks) {
        // A fast rock back and forth while it's unsupported.
        val tilt = world.rockWobble[rk]?.let { sin(it * 42) * 8 } ?: 0.0
        rock(g.cx(rk.c), g.cy(rk.r), cell * 0.94, tilt, rk.r * 9 + rk.c)
    }
    world.harpoon?.let { hp ->
        val tip = Cell(hp.from.r + hp.dir.r * hp.len, hp.from.c + hp.dir.c * hp.len)
        harpoon(g.cx(hp.from.c), g.cy(hp.from.r), g.cx(tip.c), g.cy(tip.r), cell)
    }
    for (e in world.enemies) {
        val s = cell * (0.86 + e.inflate * 0.18)
        val left = e.left ?: (e.cell.c > world.player.c)
        val puff = min(1.0, e.inflate / max(1, world.pumps))
        if (e.kind == 0) pooka(g.cx(e.cell.c), g.cy(e.cell.r), s, puff, left) else fygar(g.cx(e.cell.c), g.cy(e.cell.r), s, puff, left)
    }
    for (b in world.bursts) particleBurst(g.cx(b.cell.c), g.cy(b.cell.r), nowSec() - b.t0, b.color, 12, 44.0, seed = b.seed)
    digger(g.cx(world.player.c), g.cy(world.player.r), cell * 0.9, world.facing.r, world.facing.c)
}

/** A lumpy orange boulder (tilted while it teeters). */
private fun DrawScope.rock(px: Double, py: Double, s: Double, tiltDeg: Double, seed: Int) {
    translate(px.f, py.f) { rotate(tiltDeg.f, Offset.Zero) {
        val n = 10
        val pts = (0 until n).map { i ->
            val a = i.toDouble() / n * 2 * PI
            val k = 0.4 + 0.07 * hashD((seed * 13 + i) * 1.7)
            P(cos(a) * k * s, sin(a) * k * 0.9 * s + s * 0.03)
        }
        fun mid(a: P, b: P) = P((a.x + b.x) / 2, (a.y + b.y) / 2)
        val blob = Path(); val m0 = mid(pts[n - 1], pts[0]); blob.m(m0.x, m0.y)
        for (i in 0 until n) { val m = mid(pts[i], pts[(i + 1) % n]); blob.q(pts[i].x, pts[i].y, m.x, m.y) }
        blob.close()
        drawPath(blob, radial(listOf(rgb(0.98, 0.74, 0.46), rgb(0.82, 0.5, 0.24), rgb(0.55, 0.3, 0.14)), -s * 0.14, -s * 0.16, s * 0.55))
        for ((x, y, d) in listOf(Triple(-0.14, 0.12, 0.08), Triple(0.16, -0.02, 0.06), Triple(0.04, 0.2, 0.05)))
            oval(x * s, y * s, d * s, d * s * 0.8, rgb(0.45, 0.24, 0.1, 0.7))
        val crack = Path(); crack.m(s * 0.08, -s * 0.3); crack.l(s * 0.16, -s * 0.14); crack.l(s * 0.1, -s * 0.04)
        strokePath(crack, rgb(0.4, 0.2, 0.08), max(0.8 * density, s * 0.04))
        strokePath(blob, rgb(0.24, 0.11, 0.04), max(density.toDouble(), s * 0.05))
    } }
}

/** The pump's hose with its harpoon tip. */
private fun DrawScope.harpoon(ax: Double, ay: Double, bx: Double, by: Double, cell: Double) {
    line(ax, ay, bx, by, Color.Black.op(0.55), cell * 0.12)
    line(ax, ay, bx, by, gray(0.96), cell * 0.06)
    val len = max(0.001, hypot(bx - ax, by - ay))
    val ux = (bx - ax) / len; val uy = (by - ay) / len
    val head = polyPath(bx + ux * cell * 0.2, by + uy * cell * 0.2, bx - uy * cell * 0.13, by + ux * cell * 0.13, bx + uy * cell * 0.13, by - ux * cell * 0.13)
    fillPath(head, gray(0.85))
    strokePath(head, Color.Black.op(0.7), max(0.8 * density, cell * 0.03))
}

/** Pooka: a red ball in yellow goggles that swells and pales as it's pumped; a steady red halo. */
private fun DrawScope.pooka(px: Double, py: Double, s: Double, puff: Double, left: Boolean, halo: Boolean = true) {
    if (halo) circle(px, py, s * 0.68, Brush.radialGradient(0f to Color.Transparent, (0.3 / 0.68).toFloat() to rgb(1.0, 0.3, 0.25, 0.5),
        1f to rgb(1.0, 0.3, 0.25, 0.0), center = Offset(px.f, py.f), radius = (s * 0.68).f))
    translate(px.f, py.f) { scale(if (left) -1f else 1f, 1f, Offset.Zero) {
        val body = rgb(0.93, 0.2, 0.16).mix(Color.White, puff * 0.45)
        val ink = rgb(0.2, 0.03, 0.03)
        for (sx in listOf(-0.18, 0.16)) oval(sx * s - s * 0.11, s * 0.3, s * 0.24, s * 0.14, body.mix(Color.Black, 0.35))
        val r = s * 0.42
        circle(0.0, 0.0, r, radial(listOf(body.mix(Color.White, 0.3), body, body.mix(Color.Black, 0.3)), -s * 0.14, -s * 0.18, r * 1.3))
        circleStroke(0.0, 0.0, r, ink, max(density.toDouble(), s * 0.045))
        rrect(-s * 0.3, -s * 0.24, s * 0.7, s * 0.28, s * 0.14, rgb(1.0, 0.84, 0.18))
        rrectStroke(-s * 0.3, -s * 0.24, s * 0.7, s * 0.28, s * 0.14, ink, max(0.8 * density, s * 0.035))
        for (lx in listOf(-0.06, 0.22)) {
            circle(lx * s, -s * 0.1, s * 0.11, Color.White)
            oval(lx * s - s * 0.01, -s * 0.14, s * 0.09, s * 0.1, ink)
        }
    } }
}

/** Fygar: a little green dragon with a white wing, facing where it walks. */
private fun DrawScope.fygar(px: Double, py: Double, s: Double, puff: Double, left: Boolean) {
    translate(px.f, py.f) { scale((if (left) -s else s).f, s.f, Offset.Zero) {
        val body = rgb(0.3, 0.74, 0.3).mix(Color.White, puff * 0.45)
        val dark = body.mix(Color.Black, 0.35)
        val ink = rgb(0.03, 0.15, 0.04)
        val lw = 0.045
        val tail = polyPath(-0.26, 0.02, -0.5, 0.22, -0.22, 0.2)
        fillPath(tail, dark); strokePath(tail, ink, lw)
        for (lx in listOf(-0.18, 0.1)) rrect(lx, 0.24, 0.13, 0.16, 0.04, dark)
        drawOval(vgrad(listOf(body.mix(Color.White, 0.2), body, dark), -0.24, 0.32), Offset(-0.36f, -0.24f), androidx.compose.ui.geometry.Size(0.64f, 0.56f))
        drawOval(ink, Offset(-0.36f, -0.24f), androidx.compose.ui.geometry.Size(0.64f, 0.56f), style = Stroke(lw.f))
        rrect(0.02, -0.34, 0.48, 0.34, 0.14, body)
        rrectStroke(0.02, -0.34, 0.48, 0.34, 0.14, ink, lw)
        val wing = polyPath(-0.16, -0.18, -0.4, -0.46, -0.04, -0.3)
        fillPath(wing, rgb(0.94, 0.96, 0.9)); strokePath(wing, ink, lw * 0.8)
        oval(0.12, -0.3, 0.17, 0.17, Color.White)
        oval(0.19, -0.25, 0.08, 0.09, ink)
        oval(0.42, -0.26, 0.05, 0.05, ink)
        line(0.3, -0.08, 0.48, -0.08, ink, lw)
    } }
}

/** The digger: a banana in Dig Dug's white helmet with a blue visor, pump nozzle forward. */
private fun DrawScope.digger(px: Double, py: Double, s: Double, dr: Int, dc: Int) {
    translate(px.f, py.f) {
        val rot = if (dr < 0) -90f else if (dr > 0) 90f else 0f
        rotate(rot, Offset.Zero) { scale((if (dr == 0 && dc < 0) -s else s).f, s.f, Offset.Zero) {
            val ink = rgb(0.12, 0.09, 0.04)
            rrect(0.14, 0.02, 0.32, 0.11, 0.04, gray(0.8))
            rrectStroke(0.14, 0.02, 0.32, 0.11, 0.04, ink, 0.035)
            val body = Path(); body.m(-0.02, -0.4); body.c(-0.46, -0.2, -0.4, 0.36, 0.08, 0.44); body.c(0.12, 0.2, 0.2, -0.18, -0.02, -0.4); body.close()
            drawPath(body, hgrad(listOf(rgb(0.95, 0.72, 0.14), rgb(1.0, 0.93, 0.42)), -0.35, 0.1))
            strokePath(body, ink, 0.04)
            val helmet = Path(); helmet.m(-0.26, -0.24); helmet.q(-0.04, -0.64, 0.22, -0.27); helmet.close()
            fillPath(helmet, gray(0.97))
            rrect(-0.27, -0.31, 0.52, 0.08, 0.04, rgb(0.2, 0.42, 0.95))
            strokePath(helmet, ink, 0.035)
            oval(-0.03, -0.2, 0.16, 0.17, Color.White)
            drawOval(ink, Offset(-0.03f, -0.2f), androidx.compose.ui.geometry.Size(0.16f, 0.17f), style = Stroke(0.025f))
            oval(0.05, -0.15, 0.06, 0.08, ink)
        } }
    }
}

/** The PUMP key's icon: a T-handle air pump with its hose. */
private fun DrawScope.pumpIcon() {
    val w = size.width.toDouble(); val h = size.height.toDouble()
    val ink = Color.Black.op(0.55)
    val hose = Path(); hose.m(w * 0.58, h * 0.84); hose.q(w * 0.95, h * 0.9, w * 0.9, h * 0.5)
    strokePath(hose, ink, w * 0.12); strokePath(hose, Color.White, w * 0.07)
    line(w * 0.48, h * 0.16, w * 0.48, h * 0.34, ink, w * 0.12, StrokeCap.Butt)
    line(w * 0.48, h * 0.16, w * 0.48, h * 0.34, Color.White, w * 0.07, StrokeCap.Butt)
    for (q in listOf(doubleArrayOf(0.36, 0.32, 0.24, 0.52, 0.05), doubleArrayOf(0.18, 0.08, 0.6, 0.1, 0.05), doubleArrayOf(0.22, 0.84, 0.52, 0.09, 0.04))) {
        rrectStroke(w * q[0], h * q[1], w * q[2], h * q[3], w * q[4], ink, w * 0.06)
        rrect(w * q[0], h * q[1], w * q[2], h * q[3], w * q[4], Color.White)
    }
}

/** Earth-brown d-pad keys (yellow when pressed) and the red PUMP key. */
private fun DrawScope.key(pump: Boolean, lit: Boolean) {
    val u = density.toDouble(); val w = size.width.toDouble(); val h = size.height.toDouble()
    val cols = if (pump) (if (lit) listOf(rgb(1.0, 0.5, 0.4), rgb(0.86, 0.22, 0.16)) else listOf(rgb(0.92, 0.24, 0.18), rgb(0.62, 0.1, 0.08)))
    else (if (lit) listOf(rgb(1.0, 0.84, 0.36), rgb(0.92, 0.62, 0.16)) else listOf(rgb(0.4, 0.27, 0.18), rgb(0.24, 0.15, 0.1)))
    val r = (if (pump) 14 else 12) * u
    rrect(0.0, 0.0, w, h, r, vgrad(cols, 0.0, h))
    rrectStroke(u, u, w - 2 * u, h - 2 * u, r - u, Color.Black.op(0.55), 2 * u)
    rrectStroke(3.6 * u, 3.6 * u, w - 7.2 * u, h - 7.2 * u, r - 3 * u, Color.White.op(if (lit) 0.9 else 0.2), 1.2 * u)
}
