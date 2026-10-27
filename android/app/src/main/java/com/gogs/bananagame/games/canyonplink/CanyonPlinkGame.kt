package com.gogs.bananagame.games.canyonplink

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GpsFixed
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
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Brain — Canyon Plink (iOS RicochetShotGame.swift, id "ricochet-shot"): a billiards-style bank shot.
 * A fixed six-shooter and a handful of bullets: tap the arena to aim, a dotted sight line traces the
 * ricochets, tap FIRE and the bullet banks round the room popping every can it grazes. Clear them all
 * before the bullets or the clock run out. Every board is verified (a greedy set cover over 360 traced
 * aims) to be clearable with the bullets given, with at most one to spare (none at levels 6–7).
 * Drawn as a red-rock canyon plinking range, midday at level 1 to moonlight at level 7.
 */
object CanyonPlinkGame {
    val definition = GameDefinition(
        id = "ricochet-shot",
        title = "Canyon Plink",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "You have FEWER bullets than targets, so each shot must pop several.",
                "Tap the arena to aim; the dotted line previews how the bullet banks off the walls.",
                "Line it up to sweep through as many targets as possible, then tap FIRE.",
                "Clear them all before your bullets or the clock run out.",
            ),
            bulletsVI = listOf(
                "Bạn có ÍT đạn hơn số mục tiêu, nên mỗi phát phải hạ nhiều mục tiêu.",
                "Chạm vào sân để nhắm; đường chấm cho xem viên đạn nảy khỏi tường ra sao.",
                "Canh sao cho quét qua càng nhiều mục tiêu càng tốt, rồi chạm BẮN.",
                "Dọn sạch tất cả trước khi hết đạn hoặc hết giờ.",
            ),
            liveDemo = true
        ),
        prefetch = { level -> BoardCache.prefetch(key(level)) { RSGen.generate(RSParams(level)) } },
        content = { level, onWin, onFail -> CanyonPlinkView(level, onWin, onFail) }
    )

    fun key(level: Int) = BoardCache.key("ricochet-shot", level)
}

internal const val RS_COLS = 11
internal const val RS_ROWS = 15
internal const val RS_SPEED = 13.0

data class RSCell(val r: Int, val c: Int)

class RSParams(level: Int) {
    private val li = min(max(level, 1), 7) - 1
    val targetCount = listOf(7, 9, 11, 13, 15, 17, 20)[li]
    val maxBounces = listOf(5, 5, 4, 4, 3, 3, 2)[li]
    val interiorWalls = listOf(0, 1, 2, 3, 4, 5, 6)[li]
    val timeLimit = (30 + targetCount * 5).toDouble()
    /** Far fewer bullets than cans: every board is verified so bank shots can still clear it… */
    val bulletBudget = listOf(3, 3, 4, 4, 5, 5, 6)[li]
    /** …and needs nearly all of them: the verified cover may leave at most this many to spare. */
    val spareShots = listOf(1, 1, 1, 1, 1, 0, 0)[li]
}

class RSBoard(val walls: Array<BooleanArray>, val targets: List<RSCell>)

/** The board generator (pure, so `BoardCache` can run it during the countdown) and the demo room. */
object RSGen {
    const val shooterX = RS_COLS / 2.0
    const val shooterY = RS_ROWS - 1.5

    fun borderWalls() = Array(RS_ROWS) { r -> BooleanArray(RS_COLS) { c -> r == 0 || r == RS_ROWS - 1 || c == 0 || c == RS_COLS - 1 } }

    /** A room, then cans dealt until a greedy cover over 360 aims clears them within the budget, but only just. */
    fun generate(p: RSParams): RSBoard {
        var hardest: RSBoard? = null
        var hardestShots = 0
        var last = RSBoard(borderWalls(), emptyList())
        repeat(30) {
            val w = borderWalls()
            // Interior wall blocks (kept off the bottom rows where the gun sits).
            var placed = 0; var tries = 0
            while (placed < p.interiorWalls && tries < 200) {
                tries++
                val bw = rndInt(1..2); val bh = rndInt(1..3)
                val c0 = rndInt(2..(RS_COLS - 2 - bw))
                val r0 = rndInt(2..(RS_ROWS - 5 - bh))
                var ok = true
                for (r in (r0 - 1)..(r0 + bh)) for (c in (c0 - 1)..(c0 + bw)) if (w[r][c]) ok = false
                if (!ok) continue
                for (r in r0 until r0 + bh) for (c in c0 until c0 + bw) w[r][c] = true
                placed++
            }
            // A shot's path depends only on the walls: trace the 360 aims once, as the cells each one pops.
            // A can only counts if the shot also pops it 0.3° either side, so a hand-tapped aim works too.
            val aims = (0 until 360).map { i ->
                val cells = listOf(-0.3, 0.0, 0.3).map { d -> shotCells((i + d) / 360 * 2 * PI, w, p.maxBounces) }
                BooleanArray(cells[0].size) { cells[0][it] && cells[1][it] && cells[2][it] }
            }
            repeat(40) {
                val chosen = placeTargets(w, p.targetCount)
                val need = greedyShots(chosen, aims)
                last = RSBoard(w, chosen)
                if (need <= p.bulletBudget && need >= p.bulletBudget - p.spareShots) return last
                if (need <= p.bulletBudget && need > hardestShots) { hardest = last; hardestShots = need }
            }
        }
        return hardest ?: last
    }

    /** Cans on open cells in the upper 2/3. */
    fun placeTargets(w: Array<BooleanArray>, count: Int): List<RSCell> {
        val cells = mutableListOf<RSCell>()
        for (r in 1 until RS_ROWS - 4) for (c in 1 until RS_COLS - 1) if (!w[r][c]) cells.add(RSCell(r, c))
        val chosen = mutableListOf<RSCell>()
        for (cand in cells.shuffled()) {
            if (cand in chosen) continue
            chosen.add(cand)
            if (chosen.size == count) break
        }
        return chosen
    }

    /**
     * Which cells a shot at `angle` pops a can in: the bullet's own path at 60 fps (6 sub-steps a frame,
     * so the bounces land where the bullet's do) and its 0.48 reach around each cell centre.
     */
    fun shotCells(angle: Double, walls: Array<BooleanArray>, maxBounces: Int): BooleanArray {
        fun wall(r: Int, c: Int) = r < 0 || r >= RS_ROWS || c < 0 || c >= RS_COLS || walls[r][c]
        val hit = BooleanArray(RS_ROWS * RS_COLS)
        // Every cell whose centre lies within the 0.48 reach of one straight run of the path.
        fun sweep(ax: Double, ay: Double, bx: Double, by: Double) {
            val dx = bx - ax; val dy = by - ay; val len2 = dx * dx + dy * dy
            for (r in max(0, floor(min(ay, by) - 0.48).toInt())..min(RS_ROWS - 1, floor(max(ay, by) + 0.48).toInt())) {
                for (c in max(0, floor(min(ax, bx) - 0.48).toInt())..min(RS_COLS - 1, floor(max(ax, bx) + 0.48).toInt())) {
                    val px = c + 0.5 - ax; val py = r + 0.5 - ay
                    val t = if (len2 > 0) max(0.0, min(1.0, (px * dx + py * dy) / len2)) else 0.0
                    val ex = px - dx * t; val ey = py - dy * t
                    if (ex * ex + ey * ey < 0.48 * 0.48) hit[r * RS_COLS + c] = true
                }
            }
        }
        var x = shooterX; var y = shooterY
        var sx = x; var sy = y
        var vx = cos(angle) * RS_SPEED; var vy = sin(angle) * RS_SPEED
        var left = maxBounces
        val sdt = 1.0 / 360
        var travel = 0.0
        while (left >= 0 && travel < 90) {
            val nx = x + vx * sdt; val ny = y + vy * sdt
            var bounced = false
            if (wall(floor(y).toInt(), floor(nx).toInt())) { vx = -vx; bounced = true }
            if (wall(floor(ny).toInt(), floor(x).toInt())) { vy = -vy; bounced = true }
            if (bounced) { sweep(sx, sy, x, y); sx = x; sy = y; left--; continue }
            x = nx; y = ny
            travel += RS_SPEED * sdt
        }
        sweep(sx, sy, x, y)
        return hit
    }

    /** Shots a greedy set cover over the traced aims needs to pop every can (Int.MAX_VALUE if one can't be hit). */
    fun greedyShots(targets: List<RSCell>, aims: List<BooleanArray>): Int {
        val masks = aims.map { hit ->
            var m = 0
            for (i in targets.indices) if (hit[targets[i].r * RS_COLS + targets[i].c]) m = m or (1 shl i)
            m
        }
        var left = (1 shl targets.size) - 1
        var shots = 0
        while (left != 0) {
            val best = masks.maxByOrNull { Integer.bitCount(it and left) } ?: 0
            if ((best and left) == 0) return Int.MAX_VALUE
            left = left and best.inv()
            shots++
        }
        return shots
    }

    /**
     * The manual clip's room: open 11×15, 7 cans in the generator's zone. Two bank shots clear it (found
     * offline with the real `fire`/`stepBullet` at 60 fps): the demo taps a rough aim first, then the two
     * true lines, firing each.
     */
    val demoTargets = listOf(RSCell(1, 6), RSCell(2, 8), RSCell(3, 1), RSCell(4, 3), RSCell(6, 4), RSCell(8, 9), RSCell(10, 4))
    val demoAims = listOf(-2.8681, -2.8181, -1.9866)
    fun demoBoard() = RSBoard(borderWalls(), demoTargets)
}

/** A spark or a knocked can: where (grid units), when (nowSec), and a small seed for its look. */
class RSFx(val x: Double, val y: Double, val at: Double, val seed: Int)

class PlinkWorld(level: Int) {
    enum class Phase { AIM, FIRING, DONE }

    val p = RSParams(level)
    var phase = Phase.AIM
    var walls = RSGen.borderWalls()
    /** Bumped when the walls change, so the cached arena redraws. */
    var wallsVersion by mutableIntStateOf(0)
    val targets = mutableListOf<RSCell>()
    val sx = RSGen.shooterX
    val sy = RSGen.shooterY
    var aimAngle = -PI / 2
    var bx = 0.0; var by = 0.0
    private var vx = 0.0; private var vy = 0.0
    private var travel = 0.0
    var bouncesLeft = 0
    var ammo = 0
    var timeLeft = 0.0
    // Presentation only: the bullet's recent path, ricochet sparks and cans knocked flying.
    val trail = mutableListOf<P>()
    val sparks = mutableListOf<RSFx>()
    val knocked = mutableListOf<RSFx>()
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    fun commit(b: RSBoard) {
        walls = b.walls; wallsVersion++
        targets.clear(); targets.addAll(b.targets)
        aimAngle = -PI / 2
        ammo = p.bulletBudget
        timeLeft = p.timeLimit
        phase = Phase.AIM
        trail.clear(); sparks.clear(); knocked.clear()
        simAngle = Double.NaN
    }

    fun isWall(r: Int, c: Int) = r < 0 || r >= RS_ROWS || c < 0 || c >= RS_COLS || walls[r][c]

    /** A tap on the arena (grid units): aim the gun at it. */
    fun aimAt(tx: Double, ty: Double) {
        if (phase != Phase.AIM) return
        aimAngle = atan2(ty - sy, tx - sx)
        SoundManager.tap()
    }

    fun fire() {
        if (phase != Phase.AIM || ammo <= 0) return
        ammo--
        bx = sx; by = sy
        vx = cos(aimAngle) * RS_SPEED; vy = sin(aimAngle) * RS_SPEED
        travel = 0.0
        bouncesLeft = p.maxBounces
        phase = Phase.FIRING
        SoundManager.tap(); Haptics.tap()
    }

    /** The play loop: the clock, and the bullet while one is in the air. */
    fun step(dt: Double) {
        if (phase == Phase.DONE) return
        timeLeft -= dt
        if (timeLeft <= 0) { timeLeft = 0.0; fail(); return }
        if (phase == Phase.FIRING) stepBullet(dt)
    }

    /** One frame of the bullet, plus what the iOS view reads off it: a spark per bounce frame, the trail. */
    fun stepBullet(dt: Double) {
        val before = bouncesLeft
        moveBullet(dt)
        if (bouncesLeft < before) sparks.add(RSFx(bx, by, nowSec(), Math.floorMod(bouncesLeft + 16, 7)))
        if (phase == Phase.FIRING) {
            trail.add(P(bx, by))
            if (trail.size > 12) trail.removeAt(0)
        } else trail.clear()
    }

    /** Sub-stepped for clean reflections at speed. */
    private fun moveBullet(dt: Double) {
        val sub = 6
        val sdt = dt / sub
        repeat(sub) {
            if (phase != Phase.FIRING) return
            val nx = bx + vx * sdt
            val ny = by + vy * sdt
            var bounced = false
            if (isWall(floor(by).toInt(), floor(nx).toInt())) { vx = -vx; bounced = true }
            if (isWall(floor(ny).toInt(), floor(bx).toInt())) { vy = -vy; bounced = true }
            if (bounced) {
                bouncesLeft--
                SoundManager.tap()
                if (bouncesLeft < 0) { endShot(); return }
                return@repeat
            }
            bx = nx; by = ny
            travel += RS_SPEED * sdt
            val hit = targets.indexOfFirst { hypot(bx - (it.c + 0.5), by - (it.r + 0.5)) < 0.48 }
            if (hit >= 0) {
                val c = targets.removeAt(hit)
                knocked.add(RSFx(c.c + 0.5, c.r + 0.5, nowSec(), c.r * 11 + c.c))
                Haptics.tap(); SoundManager.tap()
                if (targets.isEmpty()) { win(); return }
            }
            if (travel > 90) { endShot(); return }
        }
    }

    private fun endShot() {
        if (phase != Phase.FIRING) return
        if (targets.isEmpty()) { win(); return }
        if (ammo <= 0) { fail(); return }
        phase = Phase.AIM
    }

    private fun win() {
        if (phase == Phase.DONE) return
        phase = Phase.DONE
        Haptics.success(); SoundManager.tap()
        onWin()
    }

    private fun fail() {
        if (phase == Phase.DONE) return
        phase = Phase.DONE
        Haptics.warning(); SoundManager.error()
        onFail()
    }

    private var simAngle = Double.NaN
    private var simPts: List<P> = emptyList()

    /** The sight line: the polyline a shot at the current aim would trace (cached per aim). */
    fun simulate(): List<P> {
        if (aimAngle == simAngle) return simPts
        val pts = mutableListOf(P(sx, sy))
        var x = sx; var y = sy
        var vx = cos(aimAngle) * RS_SPEED; var vy = sin(aimAngle) * RS_SPEED
        var left = p.maxBounces
        val sdt = 0.004
        var travel = 0.0
        while (left >= 0 && travel < 90) {
            val nx = x + vx * sdt; val ny = y + vy * sdt
            var bounced = false
            if (isWall(floor(y).toInt(), floor(nx).toInt())) { vx = -vx; bounced = true }
            if (isWall(floor(ny).toInt(), floor(x).toInt())) { vy = -vy; bounced = true }
            if (bounced) { pts.add(P(x, y)); left--; continue }
            x = nx; y = ny
            travel += RS_SPEED * sdt
        }
        pts.add(P(x, y))
        simAngle = aimAngle; simPts = pts
        return pts
    }
}

@Composable
private fun CanyonPlinkView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { PlinkWorld(level) }
    world.onWin = onWin; world.onFail = onFail
    var ready by remember { mutableStateOf(false) }
    var demoTick by remember { mutableIntStateOf(0) }
    var demoFinger by remember { mutableStateOf<P?>(null) }
    var demoTapAt by remember { mutableStateOf(-10.0) }
    var demoFire by remember { mutableStateOf(false) }
    val handP = rememberHand()
    val tick by rememberFrameLoop(running = ready) { dt -> if (!isDemo) world.step(dt) }

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (isActive) {
                world.commit(RSGen.demoBoard()); ready = true
                demoFinger = null; demoFire = false
                delay(800)
                for ((k, a) in RSGen.demoAims.withIndex()) {
                    // Tap a point 4 cells out along the aim line (the real handler aims at the tap).
                    demoFinger = P(world.sx + cos(a) * 4, world.sy + sin(a) * 4); demoTapAt = nowSec()
                    world.aimAngle = a
                    SoundManager.tap()
                    delay(1000)
                    if (k == 0) continue        // the rough first aim is only looked at
                    demoFinger = null
                    demoFire = true
                    world.fire()
                    delay(150)
                    demoFire = false
                    while (isActive && world.phase == PlinkWorld.Phase.FIRING) {
                        world.stepBullet(1.0 / 60)
                        demoTick++
                        delay(16)
                    }
                }
                // Every can popped → the real win() ran (onWin is a no-op). Hold, then loop.
                delay(1300)
            }
        } else {
            val t0 = System.currentTimeMillis()
            val b = BoardCache.take(CanyonPlinkGame.key(level)) { RSGen.generate(RSParams(level)) }
            BoardCache.holdBrainstorm(t0, 0.6)
            world.commit(b); ready = true
        }
    }

    if (!ready) { BrainstormingView(gray(0.11), gray(0.04)); return }

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp)
            .clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .artBehind { w, h -> with(RSArt) { backdrop(w, h, level, if (isDemo) 26.0 else 40.0) } },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(if (isDemo) 5.dp else 8.dp)
    ) {
        tick; demoTick
        Header(world.targets.size, world.p.bulletBudget, world.ammo, isDemo)
        if (!isDemo) {
            val frac = if (world.p.timeLimit > 0) world.timeLeft / world.p.timeLimit else 0.0
            TimeBar(frac, Modifier.fillMaxWidth().padding(horizontal = 50.dp).height(5.dp),
                fill = if (frac < 0.3) rgb(0.96, 0.34, 0.22) else RSArt.cream, track = Color.Black.op(0.32))
        }
        val u = androidx.compose.ui.platform.LocalDensity.current.density.toDouble()
        Canvas(
            Modifier.weight(1f).fillMaxWidth().padding(horizontal = if (isDemo) 12.dp else 4.dp)
                .clip(RoundedCornerShape(16.dp))
                .artBehind { w, h ->
                    world.wallsVersion
                    val g = RSGrid(w, h)
                    with(RSArt) { arena(world.walls, g, level) }
                }
                .then(if (isDemo) Modifier else Modifier.tapIn { p, w, h ->
                    val g = RSGrid(w / u, h / u)
                    world.aimAt((p.x / u - g.ox) / g.cell, (p.y / u - g.oy) / g.cell)
                })
        ) {
            tick; demoTick
            val now = nowSec()
            inPoints { w, h -> with(RSArt) { action(world, RSGrid(w, h), level, now) } }
            demoFinger?.let { f ->
                val g = RSGrid(size.width / u, size.height / u)
                val x = (g.ox + f.x * g.cell) * u; val y = (g.oy + f.y * g.cell) * u
                tapRipple(x, y, now - demoTapAt)
                val s = g.cell * 1.3 * u
                hand(handP, x + g.cell * 0.55 * u - s / 2, y + g.cell * 0.75 * u - s / 2, s)
            }
        }
        FireButton(world.phase == PlinkWorld.Phase.AIM || demoFire, demoFire, isDemo,
            enabled = world.phase == PlinkWorld.Phase.AIM && !isDemo) { world.fire() }
    }
}

/** The arena's cell size and the field's offset inside a board of w × h points. */
internal class RSGrid(w: Double, h: Double) {
    val cell = min(w / RS_COLS, h / RS_ROWS)
    val ox = (w - cell * RS_COLS) / 2
    val oy = (h - cell * RS_ROWS) / 2
    fun x(gx: Double) = ox + gx * cell
    fun y(gy: Double) = oy + gy * cell
}

/** Cans left (a can and its count) and the cartridges left in the belt. */
@Composable
private fun Header(cans: Int, total: Int, loaded: Int, isDemo: Boolean) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 22.dp).padding(top = if (isDemo) 6.dp else 0.dp), verticalAlignment = Alignment.CenterVertically) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            Canvas(Modifier.size(if (isDemo) 13.dp else 16.dp, if (isDemo) 17.dp else 21.dp)) {
                inPoints { w, h -> with(RSArt) { can(w / 2, h / 2, h / 0.7, RSArt.label(0)) } }
            }
            Text("$cans", style = ts(if (isDemo) 16.0 else 20.0, FontWeight.Black, RSArt.cream))
        }
        Spacer(Modifier.weight(1f))
        Canvas(Modifier.width((total * (if (isDemo) 9 else 11)).dp).height(if (isDemo) 17.dp else 21.dp)) {
            inPoints { w, h -> with(RSArt) { belt(w, h, total, loaded) } }
        }
    }
}

/** FIRE: a red button in a brass rim with a crosshair; greyed while a shot is in the air. */
@Composable
private fun FireButton(ready: Boolean, lit: Boolean, isDemo: Boolean, enabled: Boolean, onFire: () -> Unit) {
    val (src, pressed) = rememberPressed()
    Box(
        Modifier.padding(bottom = if (isDemo) 6.dp else 8.dp)
            .size(if (isDemo) 130.dp else 160.dp, if (isDemo) 40.dp else 56.dp)
            .scale(if (pressed.value || lit) 0.92f else 1f)
            .clickable(src, null, enabled = enabled, onClick = onFire),
        contentAlignment = Alignment.Center
    ) {
        Canvas(Modifier.fillMaxSize()) { inPoints { w, h -> with(RSArt) { fireFace(w, h, ready, lit) } } }
        Icon(Icons.Filled.GpsFixed, null, tint = Color.White.op(if (ready) 1.0 else 0.5), modifier = Modifier.size(24.dp))
    }
}
