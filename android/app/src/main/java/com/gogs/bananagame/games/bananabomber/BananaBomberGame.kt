package com.gogs.bananagame.games.bananabomber

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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/**
 * Brain — Banana Bomber (iOS BananaBomberGame.swift, id "banana-bomber"): d-pad through pillars and
 * crates, drop a bomb, run; its + blast smashes crates and enemies (and you). Clear every enemy; a
 * blast, an enemy's touch or the clock fails. Drawn as Hudson's Bomberman.
 */
object BananaBomberGame {
    val definition = GameDefinition(
        id = "banana-bomber",
        title = "Banana Bomber",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Move with the d-pad. Tap BOMB to drop a banana bomb.",
                "After a short fuse it explodes in a + cross that destroys crates and enemies — and you too.",
                "So run clear of the blast, then clear every enemy to win.",
                "Caught in a blast, touched by an enemy, or timed out, and it's back to level 1.",
            ),
            bulletsVI = listOf(
                "Di chuyển bằng d-pad. Chạm BOM để thả một quả bom chuối.",
                "Sau ngòi nổ ngắn nó nổ thành hình dấu +, phá thùng và địch — và cả bạn nữa.",
                "Vậy nên hãy chạy khỏi vụ nổ, rồi dọn hết địch để thắng.",
                "Dính vụ nổ, bị địch chạm, hoặc hết giờ, sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> BananaBomberView(level, onWin, onFail) }
    )
}

private const val COLS = 11
private const val ROWS = 13
private const val BOMB_RANGE = 2

private data class Cell(val r: Int, val c: Int)
private class Enemy(var cell: Cell, var dir: Cell)
private class Bomb(val cell: Cell, var fuse: Double)

private fun hard(r: Int, c: Int) = r == 0 || c == 0 || r == ROWS - 1 || c == COLS - 1 || (r % 2 == 0 && c % 2 == 0)
private fun manhattan(a: Cell, b: Cell) = abs(a.r - b.r) + abs(a.c - b.c)
private val DIRS = listOf(Cell(-1, 0), Cell(1, 0), Cell(0, -1), Cell(0, 1))

private class BomberWorld(val level: Int, val isDemo: Boolean) {
    private val li = min(level, 7) - 1
    val crateCount = listOf(16, 22, 28, 32, 36, 40, 44)[li]
    val enemyN = listOf(2, 2, 3, 3, 4, 4, 5)[li]
    val fuse = listOf(2.2, 2.0, 1.9, 1.8, 1.7, 1.6, 1.5)[li]
    val enemyStep = listOf(0.55, 0.50, 0.45, 0.40, 0.35, 0.30, 0.26)[li]
    val chaseProb = listOf(0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6)[li]
    val timeLimit = listOf(50.0, 48.0, 46.0, 44.0, 42.0, 40.0, 38.0)[li]

    var playing = true
    val crates = HashSet<Cell>()
    var crateVersion by mutableIntStateOf(0)
    val enemies = mutableListOf<Enemy>()
    val bombs = mutableListOf<Bomb>()
    var blast = setOf<Cell>()
    var blastTimer = 0.0
    var player = Cell(1, 1)
    // Snapshot state, so the keys re-light when the demo script (or a finger) changes them.
    var moveDir by mutableStateOf<Cell?>(null)
    var moveAcc = 0.0; var enemyAcc = 0.0
    var timeLeft = timeLimit
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    fun walkable(c: Cell) = c.r in 0 until ROWS && c.c in 0 until COLS && !hard(c.r, c.c) && c !in crates && bombs.none { it.cell == c }

    private fun resetCommon() {
        bombs.clear(); blast = emptySet(); blastTimer = 0.0
        moveDir = null; moveAcc = 0.0; enemyAcc = 0.0
        timeLeft = timeLimit; playing = true; crateVersion++
    }

    fun setup() {
        player = Cell(1, 1)
        val safe = setOf(Cell(1, 1), Cell(1, 2), Cell(2, 1))
        val floor = ArrayList<Cell>()
        for (r in 1 until ROWS - 1) for (c in 1 until COLS - 1) if (!hard(r, c)) floor.add(Cell(r, c))
        crates.clear()
        for (cell in floor.shuffled()) { if (crates.size >= crateCount) break; if (cell !in safe) crates.add(cell) }
        enemies.clear()
        for (cell in floor.filter { it !in crates && abs(it.r - 1) + abs(it.c - 1) >= 6 }.shuffled()) {
            if (enemies.size >= enemyN) break
            enemies.add(Enemy(cell, listOf(Cell(0, 1), Cell(1, 0)).pick()))
        }
        resetCommon()
    }

    /** A fixed level-1 arena (16 crates, two wanderers) for the manual clip. */
    fun demoSetup() {
        player = Cell(1, 1)
        crates.clear()
        for ((r, c) in demoCrates) crates.add(Cell(r, c))
        enemies.clear()
        enemies.add(Enemy(Cell(1, 7), Cell(0, -1))); enemies.add(Enemy(Cell(8, 9), Cell(1, 0)))
        resetCommon()
    }

    fun dropBomb() {
        if (!playing || bombs.any { it.cell == player }) return
        bombs.add(Bomb(player, fuse))
        SoundManager.tap(); Haptics.tap()
    }

    fun tick(dt: Double) {
        if (!playing) return
        if (blastTimer > 0) { blastTimer -= dt; if (blastTimer <= 0) blast = emptySet() }
        for (b in bombs) b.fuse -= dt
        val exploding = bombs.filter { it.fuse <= 0 }
        if (exploding.isNotEmpty()) { bombs.removeAll { it.fuse <= 0 }; for (b in exploding) detonate(b.cell) }
        if (!playing) return
        // Player movement (hold to repeat).
        moveAcc += dt
        val mv = moveDir
        if (mv != null && moveAcc >= 0.13) {
            moveAcc = 0.0
            val dest = Cell(player.r + mv.r, player.c + mv.c)
            if (walkable(dest)) { player = dest; SoundManager.tap() }
        }
        if (checkPlayerDead()) return
        enemyAcc += dt
        if (enemyAcc >= enemyStep) {
            enemyAcc = 0.0
            for (e in enemies) moveEnemy(e)
            checkPlayerDead()
        }
    }

    private fun detonate(center: Cell) {
        val cells = hashSetOf(center)
        for (d in DIRS) for (step in 1..BOMB_RANGE) {
            val cell = Cell(center.r + d.r * step, center.c + d.c * step)
            if (hard(cell.r, cell.c)) break
            cells.add(cell)
            if (crates.remove(cell)) { crateVersion++; break }       // a crate absorbs the blast
        }
        blast = cells; blastTimer = 0.35
        Haptics.warning(); SoundManager.error()
        val before = enemies.size
        enemies.removeAll { it.cell in cells }
        if (enemies.size < before) SoundManager.tap()
        // Chain any other bombs the blast reaches.
        val chained = bombs.filter { it.cell in cells }
        bombs.removeAll { it.cell in cells }
        for (b in chained) detonate(b.cell)
        if (checkPlayerDead()) return
        if (enemies.isEmpty()) win()
    }

    private fun moveEnemy(e: Enemy) {
        // Chase: sometimes step toward the player if a move gets closer.
        if (!isDemo && Random.nextDouble() < chaseProb) {
            val best = DIRS.map { Cell(e.cell.r + it.r, e.cell.c + it.c) }.filter { walkable(it) }.minByOrNull { manhattan(it, player) }
            if (best != null) { e.dir = Cell(best.r - e.cell.r, best.c - e.cell.c); e.cell = best; return }
        }
        // Wander: straight on if possible, else a random open turn (demo: turn back when blocked).
        val ahead = Cell(e.cell.r + e.dir.r, e.cell.c + e.dir.c)
        if (walkable(ahead) && (isDemo || Random.nextDouble() > 0.2)) { e.cell = ahead; return }
        val turns = DIRS.map { Cell(e.cell.r + it.r, e.cell.c + it.c) }.filter { walkable(it) }
        val back = Cell(e.cell.r - e.dir.r, e.cell.c - e.dir.c)
        val pick = if (isDemo) (listOf(back) + turns).firstOrNull { walkable(it) } else turns.randomOrNull()
        if (pick != null) { e.dir = Cell(pick.r - e.cell.r, pick.c - e.cell.c); e.cell = pick }
    }

    fun checkPlayerDead(): Boolean {
        if (player in blast || enemies.any { it.cell == player }) { fail(); return true }
        return false
    }

    fun win() { if (!playing) return; playing = false; Haptics.success(); SoundManager.tap(); onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }
}

private val demoCrates = listOf(1 to 9, 3 to 3, 3 to 7, 3 to 9, 11 to 9, 7 to 1, 7 to 3, 9 to 2, 8 to 3, 9 to 5, 7 to 5, 10 to 5, 11 to 3, 11 to 6, 9 to 7, 8 to 1)
private sealed class DemoInput { class Hold(val d: Cell) : DemoInput(); object Release : DemoInput(); object Bomb : DemoInput() }
// Bomb the top-corridor enemy and duck round the corner; then bomb beside the right-hand shaft.
private val demoScript: List<Pair<Int, DemoInput>> = listOf(
    10 to DemoInput.Hold(Cell(0, 1)), 16 to DemoInput.Release, 17 to DemoInput.Bomb,
    18 to DemoInput.Hold(Cell(0, -1)), 23 to DemoInput.Release, 24 to DemoInput.Hold(Cell(1, 0)), 40 to DemoInput.Release,
    41 to DemoInput.Hold(Cell(0, 1)), 64 to DemoInput.Release, 67 to DemoInput.Bomb,
    68 to DemoInput.Hold(Cell(0, -1)), 80 to DemoInput.Release,
)

private class BGeo(w: Double, h: Double) {
    val cell = min(w / COLS, h / ROWS)
    val ox = (w - cell * COLS) / 2
    val oy = (h - cell * ROWS) / 2
    fun ctr(p: Cell) = P(ox + (p.c + 0.5) * cell, oy + (p.r + 0.5) * cell)
}

@Composable
private fun BananaBomberView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { BomberWorld(level, isDemo).also { if (isDemo) it.demoSetup() else it.setup() } }
    world.onWin = onWin; world.onFail = onFail
    var demoTick by remember { mutableIntStateOf(0) }
    var demoBomb by remember { mutableIntStateOf(0) }
    val start = remember { nowSec() }
    val acc = remember { doubleArrayOf(0.0) }
    val tick by rememberFrameLoop(maxDt = 0.08) { dt ->
        if (isDemo || !world.playing) return@rememberFrameLoop
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
            world.demoSetup(); demoBomb = 0
            delay(500)
            var frame = 0; var next = 0
            while (isActive && world.playing && frame < 600) {
                frame++
                while (next < demoScript.size && demoScript[next].first <= frame) {
                    when (val input = demoScript[next].second) {
                        is DemoInput.Hold -> world.moveDir = input.d
                        DemoInput.Release -> world.moveDir = null
                        DemoInput.Bomb -> { world.dropBomb(); demoBomb = 5 }
                    }
                    next++
                }
                if (demoBomb > 0) demoBomb--
                world.tick(dt)
                demoTick++
                delay(33)
            }
            world.moveDir = null; demoBomb = 0
            val end = nowSec()
            while (isActive && nowSec() - end < 1.3) { demoTick++; delay(33) }
        }
    }

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp).clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .background(floorPair(level).first.mix(Color.Black, 0.72)),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        tick; demoTick
        // Enemies left: a Ballom and its count.
        Row(Modifier.padding(top = if (isDemo) 6.dp else 0.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            Canvas(Modifier.size(if (isDemo) 17.dp else 22.dp)) {
                ballom(size.width / 2.0, size.height * 0.46, min(size.width, size.height) * 1.02, true)
            }
            Text("${world.enemies.size}", style = ts(if (isDemo) 15.0 else 20.0, FontWeight.Black, Color.White).copy(fontFeatureSettings = "tnum"))
        }
        if (!isDemo) {
            val f = world.timeLeft / world.timeLimit
            TimeBar(f, Modifier.fillMaxWidth().padding(horizontal = 56.dp).height(5.dp), fill = if (f < 0.3) rgb(1.0, 0.32, 0.24) else rgb(1.0, 0.8, 0.3), track = Color.Black.op(0.3))
        }
        Canvas(
            Modifier.fillMaxWidth().weight(1f).padding(horizontal = 6.dp)
                .drawWithCache {
                    // Floor, stone pillars and brick blocks: re-rendered only when a block is blasted.
                    world.crateVersion
                    val bmp = ImageBitmap(size.width.toInt().coerceAtLeast(1), size.height.toInt().coerceAtLeast(1))
                    val cr = HashSet(world.crates)
                    CanvasDrawScope().draw(this, layoutDirection, androidx.compose.ui.graphics.Canvas(bmp), size) { arena(cr, level) }
                    onDrawBehind { drawImage(bmp) }
                }
        ) {
            tick; demoTick
            val g = BGeo(size.width.toDouble(), size.height.toDouble())
            for (b in world.bombs) { val p = g.ctr(b.cell); bomb(p.x, p.y, g.cell, 1 + 0.12 * sin(b.fuse * 12), (b.fuse * 16).toInt() % 2 == 0) }
            flames(world.blast, g)
            for (e in world.enemies) { val p = g.ctr(e.cell); ballom(p.x, p.y, g.cell * 0.8, e.dir.c >= 0) }
            val pp = g.ctr(world.player)
            bomber(pp.x, pp.y, g.cell * 0.86)
        }
        Row(Modifier.padding(bottom = if (isDemo) 6.dp else 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(20.dp)) {
            val gp = if (isDemo) 4.dp else 6.dp
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(gp)) {
                DirKey(world, Cell(-1, 0), Icons.Filled.KeyboardArrowUp, isDemo)
                Row(horizontalArrangement = Arrangement.spacedBy(gp)) {
                    DirKey(world, Cell(0, -1), Icons.Filled.KeyboardArrowLeft, isDemo)
                    DirKey(world, Cell(1, 0), Icons.Filled.KeyboardArrowDown, isDemo)
                    DirKey(world, Cell(0, 1), Icons.Filled.KeyboardArrowRight, isDemo)
                }
            }
            val lit = demoBomb > 0
            Box(
                Modifier.scale(if (lit) 0.9f else 1f).size(if (isDemo) 66.dp else 78.dp, if (isDemo) 42.dp else 56.dp)
                    .then(if (isDemo) Modifier else Modifier.pressDown(onDown = { world.dropBomb() })),
                contentAlignment = Alignment.Center
            ) {
                Canvas(Modifier.fillMaxSize()) { key(true, lit) }
                Canvas(Modifier.size(if (isDemo) 30.dp else 36.dp)) {
                    val m = min(size.width, size.height).toDouble()
                    bomb(size.width / 2.0 - m * 0.04, size.height / 2.0 + m * 0.1, m * 1.2, 1.0, true)
                }
            }
        }
    }
}

/** A dark slate d-pad key (banana yellow while held). */
@Composable
private fun DirKey(world: BomberWorld, d: Cell, icon: ImageVector, isDemo: Boolean) {
    val lit = isDemo && world.moveDir == d      // as on iOS, only the demo's presses light up
    Box(
        Modifier.scale(if (lit) 0.9f else 1f).size(if (isDemo) 46.dp else 56.dp, if (isDemo) 32.dp else 46.dp)
            .then(if (isDemo) Modifier else Modifier.pressDown(
                onDown = { if (world.playing) world.moveDir = d },
                onUp = { if (world.moveDir == d) world.moveDir = null })),
        contentAlignment = Alignment.Center
    ) {
        Canvas(Modifier.fillMaxSize()) { key(false, lit) }
        Icon(icon, null, tint = if (lit) rgb(0.2, 0.12, 0.0) else Color.White, modifier = Modifier.size(if (isDemo) 22.dp else 26.dp))
    }
}

// Bomberman art (after Hudson's Bomberman; iOS BBArt).

/** Floor pair per world: grass (1–2), desert (3–4), ice (5), volcanic rock (6–7). */
private fun floorPair(level: Int) = when (min(max(level, 1), 7)) {
    1, 2 -> rgb(0.38, 0.66, 0.3) to rgb(0.34, 0.6, 0.27)
    3, 4 -> rgb(0.88, 0.76, 0.5) to rgb(0.83, 0.7, 0.45)
    5 -> rgb(0.78, 0.9, 0.96) to rgb(0.7, 0.84, 0.93)
    else -> rgb(0.3, 0.22, 0.22) to rgb(0.26, 0.19, 0.19)
}

/** A lit bomb: black ball, highlight, a fuse with a spark. */
private fun DrawScope.bomb(px: Double, py: Double, cell: Double, pulse: Double, spark: Boolean) {
    val r = cell * 0.33 * pulse
    oval(px - r * 0.9, py + r * 0.6, r * 1.8, r * 0.5, Color.Black.op(0.3))
    circle(px, py + r * 0.1, r, radial(listOf(gray(0.4), gray(0.08)), px - r * 0.35, py - r * 0.4, r * 1.3))
    oval(px - r * 0.55, py - r * 0.6, r * 0.36, r * 0.26, Color.White.op(0.7))
    rrect(px + r * 0.2, py - r * 1.15, r * 0.4, r * 0.3, r * 0.08, gray(0.3))
    val fuse = Path(); fuse.m(px + r * 0.4, py - r * 1.1); fuse.q(px + r * 0.5, py - r * 1.55, px + r * 0.9, py - r * 1.5)
    strokePath(fuse, rgb(0.85, 0.75, 0.55), max(density.toDouble(), cell * 0.04))
    val tx = px + r * 0.9; val ty = py - r * 1.5
    val sr = cell * (if (spark) 0.14 else 0.09)
    circle(tx, ty, sr, radial(listOf(Color.White, rgb(1.0, 0.8, 0.2), rgb(1.0, 0.4, 0.1, 0.0)), tx, ty, sr))
}

/** The blast as Bomberman's flame cross: orange arms, a white-hot core, a burst in each cell. */
private fun DrawScope.flames(cells: Set<Cell>, g: BGeo) {
    if (cells.isEmpty()) return
    val cell = g.cell
    for ((col, rad, arm) in listOf(Triple(rgb(1.0, 0.45, 0.1), 0.42, 0.7), Triple(rgb(1.0, 0.9, 0.4), 0.24, 0.34))) {
        for (c in cells) {
            val p = g.ctr(c)
            circle(p.x, p.y, cell * rad, col)
            for (d in listOf(Cell(0, 1), Cell(1, 0))) {
                val n = Cell(c.r + d.r, c.c + d.c)
                if (n in cells) { val q = g.ctr(n); line(p.x, p.y, q.x, q.y, col, cell * arm) }
            }
        }
    }
    for (c in cells) { val p = g.ctr(c); circle(p.x, p.y, cell * 0.12, Color.White) }
}

/** Ballom: an orange-pink balloon creature with big eyes. */
private fun DrawScope.ballom(px: Double, py: Double, s: Double, lookRight: Boolean) {
    val r = s * 0.46
    oval(px - r * 0.8, py + r * 0.7, r * 1.6, r * 0.4, Color.Black.op(0.25))
    drawOval(radial(listOf(rgb(1.0, 0.78, 0.62), rgb(0.98, 0.52, 0.34), rgb(0.8, 0.3, 0.2)), px - r * 0.3, py - r * 0.4, r * 1.3),
        Offset((px - r).f, (py - r).f), androidx.compose.ui.geometry.Size((r * 2).f, (r * 1.9).f))
    drawOval(rgb(0.4, 0.12, 0.06), Offset((px - r).f, (py - r).f), androidx.compose.ui.geometry.Size((r * 2).f, (r * 1.9).f), style = Stroke(max(density.toDouble(), s * 0.04).f))
    val look = if (lookRight) 1.0 else -1.0
    for (dx in listOf(-0.34, 0.24)) {
        val ex = px + dx * r + look * r * 0.05; val ey = py - r * 0.18
        oval(ex - r * 0.2, ey - r * 0.26, r * 0.4, r * 0.52, Color.White)
        oval(ex - r * 0.08 + look * r * 0.07, ey - r * 0.12, r * 0.16, r * 0.24, Color.Black)
    }
    val mouth = Path(); mouth.m(px - r * 0.3, py + r * 0.35); mouth.q(px, py + r * 0.62, px + r * 0.3, py + r * 0.35)
    strokePath(mouth, rgb(0.4, 0.1, 0.06), max(density.toDouble(), s * 0.05))
}

/** The bomber: a banana in Bomberman's white helmet with the pink antenna ball. */
private fun DrawScope.bomber(px: Double, py: Double, s: Double) {
    translate(px.f, py.f) { scale(s.f, s.f, Offset.Zero) {
        val ink = rgb(0.14, 0.1, 0.04)
        oval(-0.32, 0.36, 0.64, 0.14, Color.Black.op(0.28))
        val body = Path(); body.m(-0.02, -0.36); body.c(-0.44, -0.18, -0.4, 0.36, 0.1, 0.44); body.c(0.14, 0.2, 0.22, -0.16, -0.02, -0.36); body.close()
        drawPath(body, hgrad(listOf(rgb(0.95, 0.72, 0.14), rgb(1.0, 0.94, 0.45)), -0.35, 0.1))
        strokePath(body, ink, 0.04)
        drawOval(radial(listOf(Color.White, gray(0.8)), -0.1, -0.4, 0.4), Offset(-0.32f, -0.52f), androidx.compose.ui.geometry.Size(0.6f, 0.5f))
        drawOval(ink, Offset(-0.32f, -0.52f), androidx.compose.ui.geometry.Size(0.6f, 0.5f), style = Stroke(0.035f))
        rrect(-0.2, -0.34, 0.36, 0.22, 0.1, rgb(1.0, 0.86, 0.72))
        for (x in listOf(-0.1, 0.05)) rrect(x - 0.025, -0.3, 0.05, 0.12, 0.025, ink)
        line(-0.02, -0.52, -0.02, -0.66, ink, 0.04, StrokeCap.Butt)
        circle(-0.02, -0.72, 0.08, rgb(1.0, 0.4, 0.6))
    } }
}

/** Keys: dark slate d-pad (banana yellow while held) and a yellow BOMB key. */
private fun DrawScope.key(bomb: Boolean, lit: Boolean) {
    val u = density.toDouble(); val w = size.width.toDouble(); val h = size.height.toDouble()
    val cols = if (bomb) (if (lit) listOf(Color.White, rgb(1.0, 0.88, 0.5)) else listOf(rgb(1.0, 0.85, 0.35), rgb(0.95, 0.62, 0.14)))
    else (if (lit) listOf(rgb(1.0, 0.9, 0.45), rgb(0.95, 0.72, 0.16)) else listOf(gray(0.34), gray(0.18)))
    val r = (if (bomb) 14 else 12) * u
    rrect(0.0, 0.0, w, h, r, vgrad(cols, 0.0, h))
    rrectStroke(u, u, w - 2 * u, h - 2 * u, r - u, Color.Black.op(0.5), 2 * u)
    rrectStroke(3.5 * u, 3.5 * u, w - 7 * u, h - 7 * u, r - 3 * u, Color.White.op(if (lit) 0.9 else 0.25), u)
}

/** The arena: a checkered floor, bevelled stone pillars and brick soft blocks. */
private fun DrawScope.arena(crates: Set<Cell>, level: Int) {
    val u = density.toDouble()
    val g = BGeo(size.width.toDouble(), size.height.toDouble())
    val cell = g.cell
    val (f0, f1) = floorPair(level)
    val light = Path(); val dark = Path(); val stone = Path(); val stoneLit = Path(); val stoneDark = Path()
    val bricks = Path(); val mortar = Path(); val shade = Path()
    fun rc(x: Double, y: Double, w: Double, h: Double) = Rect(x.f, y.f, (x + w).f, (y + h).f)
    for (r in 0 until ROWS) for (c in 0 until COLS) {
        val x = g.ox + c * cell; val y = g.oy + r * cell
        if (hard(r, c)) {
            stone.addRect(rc(x, y, cell + 0.5, cell + 0.5))
            stoneLit.addRect(rc(x, y, cell, cell * 0.14)); stoneLit.addRect(rc(x, y, cell * 0.12, cell))
            stoneDark.addRect(rc(x, y + cell + 0.5 - cell * 0.16, cell, cell * 0.16)); stoneDark.addRect(rc(x + cell + 0.5 - cell * 0.14, y, cell * 0.14, cell))
        } else {
            (if ((r + c) % 2 == 0) light else dark).addRect(rc(x, y, cell + 0.5, cell + 0.5))
            if (Cell(r, c) in crates) {
                val bx = x + cell * 0.03; val by = y + cell * 0.03; val bs = cell + 0.5 - cell * 0.06
                bricks.addRect(rc(bx, by, bs, bs))
                shade.addRect(rc(bx, by + bs - cell * 0.1, bs, cell * 0.1))
                for (k in 1..3) { val yy = by + bs * k / 4; mortar.m(bx, yy); mortar.l(bx + bs, yy) }
                for (k in 0 until 4) {
                    val y0 = by + bs * k / 4
                    for (fx in if (k % 2 == 0) listOf(0.5) else listOf(0.25, 0.75)) { mortar.m(bx + bs * fx, y0); mortar.l(bx + bs * fx, y0 + bs / 4) }
                }
            }
        }
    }
    fillPath(light, f0); fillPath(dark, f1)
    fillPath(stone, if (level >= 6) gray(0.3) else gray(0.62))
    fillPath(stoneLit, Color.White.op(0.3)); fillPath(stoneDark, Color.Black.op(0.3))
    val brick = if (level == 5) rgb(0.62, 0.78, 0.9) else rgb(0.78, 0.44, 0.24)
    fillPath(bricks, brick); fillPath(shade, Color.Black.op(0.2))
    strokePath(mortar, brick.mix(Color.Black, 0.45), max(u, cell * 0.035), StrokeCap.Butt)
    drawPath(bricks, Color.Black.op(0.45), style = Stroke(u.f))
}
