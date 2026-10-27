package com.gogs.bananagame.games.ledgebrawl

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
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
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Reflex — Ledge Brawl (iOS GunMayhemGame.swift, id "gun-mayhem"): a platform brawler with no
 * health bars; every hit builds knockback until the rival flies off the stage.
 */
object LedgeBrawlGame {
    val definition = GameDefinition(
        id = "gun-mayhem",
        title = "Ledge Brawl",
        genre = Genre.REFLEX,
        manual = GameManual(
            bullets = listOf(
                "A platform brawl with no health bars — every hit builds a rival's knockback.",
                "Move with ◄ ►, JUMP (tap again to double-jump), and SHOOT.",
                "Knock every rival off the stage to win.",
                "Fall off three times, or time out with rivals standing, and you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Ẩu đả trên bệ, không có thanh máu — mỗi phát trúng làm đối thủ bị hất mạnh hơn.",
                "Di chuyển bằng ◄ ►, NHẢY (chạm lần nữa để nhảy đúp), và BẮN.",
                "Hất mọi đối thủ khỏi sân để thắng.",
                "Rơi ba lần, hoặc hết giờ khi đối thủ còn đứng, sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> LedgeBrawlView(level, onWin, onFail) }
    )
}

// Physics constants (fractions of the play area).
private const val G = 2.2
private const val MAX_FALL = 1.6
private const val MOVE_SPEED = 0.45
private const val GROUND_ACCEL = 4.0
private const val AIR_ACCEL = 1.5
private const val JUMP_V = -1.0
private const val FW = 0.032
private const val FH = 0.050
private const val BULLET_SPEED = 1.4
private const val BULLET_LIFE = 0.85
private const val PLAYER_FIRE = 0.30
private const val HIT_DAMAGE = 0.14
private const val KNOCK_BASE = 0.35
private const val KNOCK_GROW = 1.1
private const val UP_KICK_BASE = 0.35
private const val UP_KICK_GROW = 0.5
private const val KEEP_NEAR = 0.14
private const val KEEP_FAR = 0.32

private class Plat(val x: Double, val y: Double, val w: Double)

private class Fighter(
    val id: Int, var x: Double, var y: Double, var lives: Int, val isPlayer: Boolean,
    val shirt: Color, val hat: Color, var aiTimer: Double = 0.0,
) {
    var vx = 0.0; var vy = 0.0
    var facing = 1.0
    var onGround = false
    var jumpsLeft = 2
    var damage = 0.0
    var shootCD = 0.0
    var invuln = 0.0
    var moveDir = 0.0
    var jumpReq = false
    var shootReq = false
    var paceTimer = 0.0
}

/** `lastX` is where this frame's sweep starts, so hits can't be skipped. */
private class Bullet(var x: Double, var y: Double, var lastX: Double, val vx: Double, val fromPlayer: Boolean, var life: Double)

private class Burst(val x: Double, val y: Double, val color: Color, val t0: Double, val seed: Int)

private fun buildPlats(level: Int): List<Plat> {
    val mainY = 0.80
    val ps = mutableListOf(Plat(0.14, mainY, 0.72))
    when (level) {
        1, 2, 3 -> { ps += Plat(0.04, 0.58, 0.24); ps += Plat(0.72, 0.58, 0.24); ps += Plat(0.39, 0.40, 0.22) }
        4, 5 -> { ps += Plat(0.06, 0.56, 0.22); ps += Plat(0.72, 0.56, 0.22) }
        else -> ps += Plat(0.40, 0.44, 0.20)
    }
    return ps
}

private class Brawl(val level: Int, val isDemo: Boolean) {
    private val li = min(level, 7) - 1
    val enemyCount = intArrayOf(1, 1, 2, 2, 3, 3, 3)[li]
    val enemyLives = intArrayOf(1, 2, 2, 2, 2, 3, 3)[li]
    val enemyFire = doubleArrayOf(1.5, 1.3, 1.15, 1.0, 0.9, 0.8, 0.7)[li]
    val timeLimit = (35 + enemyCount * 13).toDouble()

    val plats = buildPlats(level)
    var playing = true
    var fighters = mutableListOf<Fighter>()
    var bullets = mutableListOf<Bullet>()
    val bursts = mutableListOf<Burst>()
    var timeLeft = timeLimit
    var shakeT0 = -10.0
    var startT = 0.0
    var playerMoveDir = 0.0
    var playerJumpReq = false
    var playerShootReq = false
    private var burstSeed = 0
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    val enemiesLeft get() = fighters.count { !it.isPlayer }
    val playerLives get() = fighters.firstOrNull()?.lives ?: 0

    fun setup() {
        val mainTop = plats[0].y
        val fs = mutableListOf<Fighter>()
        fs += Fighter(0, 0.5, mainTop - FH, 3, true, BananaTheme.banana, rgb(0.16, 0.16, 0.28))
        val shirts = listOf(rgb(0.90, 0.30, 0.32), rgb(0.35, 0.55, 0.95), rgb(0.45, 0.80, 0.45))
        // Two rivals flank you on the rooftop; a third starts on the highest platform.
        val high = plats.drop(1).minByOrNull { it.y } ?: plats[0]
        val spots = listOf(P(0.22, mainTop - FH), P(0.78, mainTop - FH), P(high.x + high.w / 2, high.y - FH))
        for (k in 0 until enemyCount) {
            val s = spots[k % spots.size]
            val shirt = shirts[k % shirts.size]
            fs += Fighter(k + 1, s.x, s.y, enemyLives, false, shirt, shirt.shade(0.45),
                aiTimer = if (isDemo) 0.8 else rnd(0.3, 1.0))
        }
        fighters = fs
        bullets = mutableListOf(); bursts.clear()
        playerMoveDir = 0.0; playerJumpReq = false; playerShootReq = false
        timeLeft = timeLimit
        playing = true
    }

    fun step(dt: Double) {
        if (!playing) return
        if (fighters.isNotEmpty()) {
            val me = fighters[0]
            me.moveDir = playerMoveDir
            if (playerJumpReq) { me.jumpReq = true; playerJumpReq = false }
            if (playerShootReq) { me.shootReq = true; playerShootReq = false }
        }
        for (f in fighters) if (!f.isPlayer) aiThink(f, dt)
        for (f in fighters) physics(f, dt)
        separate()
        for (f in fighters) {
            if (!f.shootReq) continue
            f.shootReq = false
            if (f.shootCD > 0) continue
            f.shootCD = if (f.isPlayer) PLAYER_FIRE else enemyFire
            val dir = f.facing
            bullets += Bullet(f.x + dir * FW * 1.3, f.y - FH * 0.15, f.x + dir * FW, dir * BULLET_SPEED, f.isPlayer, BULLET_LIFE)
            SoundManager.tap()
        }
        stepBullets(dt)
        handleDeaths()
    }

    fun physics(f: Fighter, dt: Double) {
        f.shootCD = max(0.0, f.shootCD - dt)
        f.invuln = max(0.0, f.invuln - dt)
        if (f.jumpReq) {
            f.jumpReq = false
            if (f.jumpsLeft > 0) {
                f.vy = JUMP_V; f.jumpsLeft -= 1; f.onGround = false
                if (f.isPlayer) SoundManager.tap()
            }
        }
        // Horizontal control eases toward the desired speed; big knockback bleeds off slowly in the air.
        val accel = if (f.onGround) GROUND_ACCEL else AIR_ACCEL
        val dv = f.moveDir * MOVE_SPEED - f.vx
        val maxDV = accel * dt
        f.vx += max(-maxDV, min(maxDV, dv))
        f.vy = min(MAX_FALL, f.vy + G * dt)
        f.x += f.vx * dt
        f.y += f.vy * dt
        if (f.moveDir != 0.0) f.facing = if (f.moveDir > 0) 1.0 else -1.0
        // One-way platform landing (only while falling).
        f.onGround = false
        if (f.vy >= 0) {
            val feet = f.y + FH
            for (p in plats) {
                if (f.x < p.x - FW * 0.4 || f.x > p.x + p.w + FW * 0.4) continue
                if (feet >= p.y && feet <= p.y + 0.06 + f.vy * dt) {
                    f.y = p.y - FH; f.vy = 0.0; f.onGround = true; f.jumpsLeft = 2
                    break
                }
            }
        }
    }

    /** Bodies are solid on the ground: whoever walked in is held back; in the air you pass over. */
    private fun separate() {
        if (fighters.isEmpty()) return
        val me = fighters[0]
        for (i in 1 until fighters.size) {
            val r = fighters[i]
            if (!(me.onGround && r.onGround && abs(r.y - me.y) < FH)) continue
            val gap = r.x - me.x
            val overlap = 2 * FW - abs(gap)
            if (overlap <= 0) continue
            val side = if (gap != 0.0) (if (gap > 0) 1.0 else -1.0) else (if (me.x < 0.5) 1.0 else -1.0)
            val youIn = max(0.0, me.vx * side); val rivalIn = max(0.0, -r.vx * side)
            val yourShare = if (youIn + rivalIn > 0) youIn / (youIn + rivalIn) else 0.5
            me.x -= side * overlap * yourShare
            r.x += side * overlap * (1 - yourShare)
            if (youIn > 0) me.vx = 0.0
            if (rivalIn > 0) r.vx = 0.0
        }
    }

    private fun aiThink(e: Fighter, dt: Double) {
        val player = fighters.firstOrNull() ?: return
        e.aiTimer -= dt
        e.paceTimer -= dt
        val dx = player.x - e.x
        val dy = player.y - e.y
        val toward = if (dx >= 0) 1.0 else -1.0
        val level = abs(dy) < 0.07
        // Never stands still: it keeps striding and turns back every so often.
        var dir = e.moveDir
        if (dir == 0.0 || e.paceTimer <= 0) {
            dir = if (dir == 0.0) toward else -dir
            e.paceTimer = if (isDemo) 0.7 else rnd(0.4, 0.9)
        }
        if (level) {
            if (abs(dx) < KEEP_NEAR) dir = -toward else if (abs(dx) > KEEP_FAR) dir = toward
            if (e.shootCD <= 0 || e.shootCD > enemyFire - 0.25) dir = toward
        } else if (abs(dx) > 0.12) {
            dir = toward
        }
        // Don't walk off an edge unless we deliberately leap.
        if (e.onGround && !groundAhead(e.x + dir * 0.06, e.y)) {
            if (dir == toward && abs(dx) > 0.12 && (!isDemo && rndBool())) e.jumpReq = true
            else dir = -dir
        }
        e.moveDir = dir
        // Recover if knocked out past the stage edges.
        if (!e.onGround && e.jumpsLeft > 0 && (e.x < 0.10 || e.x > 0.90)) {
            e.jumpReq = true
            e.moveDir = if (e.x < 0.5) 1.0 else -1.0
        }
        if (level && e.moveDir == toward && e.shootCD <= 0) e.shootReq = true
        if (e.onGround && e.aiTimer <= 0) {
            e.aiTimer = if (isDemo) 1.0 else rnd(0.6, 1.4)
            if (dy < -0.06 || (!isDemo && rndBool())) e.jumpReq = true
        }
    }

    private fun groundAhead(x: Double, y: Double): Boolean {
        val feet = y + FH
        for (p in plats) {
            if (x < p.x || x > p.x + p.w) continue
            val drop = p.y - feet
            if (drop >= -0.03 && drop < 0.25) return true
        }
        return false
    }

    fun stepBullets(dt: Double) {
        val survivors = mutableListOf<Bullet>()
        val reach = FW + 0.012
        for (b in bullets) {
            val x0 = b.lastX
            b.x += b.vx * dt
            b.lastX = b.x
            b.life -= dt
            if (b.life <= 0 || b.x < -0.1 || b.x > 1.1 || b.y < -0.1 || b.y > 1.2) continue
            var hit = false
            for (f in fighters) {
                if (f.isPlayer == b.fromPlayer) continue
                if (f.invuln > 0) continue
                if (min(x0, b.x) < f.x + reach && max(x0, b.x) > f.x - reach && abs(b.y - f.y) < FH + 0.012) {
                    applyHit(f, b); hit = true; break
                }
            }
            if (!hit) survivors += b
        }
        bullets = survivors
    }

    private fun addBurst(x: Double, y: Double, c: Color) { bursts += Burst(x, y, c, nowSec(), burstSeed); burstSeed += 37 }

    private fun applyHit(f: Fighter, b: Bullet) {
        val dir = if (b.vx >= 0) 1.0 else -1.0
        f.damage += HIT_DAMAGE
        f.vx += dir * (KNOCK_BASE + f.damage * KNOCK_GROW)
        f.vy -= UP_KICK_BASE + f.damage * UP_KICK_GROW
        f.onGround = false
        addBurst(f.x, f.y, f.shirt)
        shakeT0 = nowSec()
        if (f.isPlayer) { Haptics.warning(); SoundManager.error() } else { Haptics.tap(); SoundManager.tap() }
    }

    private fun handleDeaths() {
        for (f in fighters) {
            if (f.x < -0.12 || f.x > 1.12 || f.y > 1.18 || f.y < -0.4) {
                f.lives -= 1
                addBurst(min(1.1, max(-0.1, f.x)), min(1.1, max(0.0, f.y)), f.shirt)
                shakeT0 = nowSec()
                SoundManager.error()
                if (f.lives > 0) {
                    f.x = 0.5; f.y = 0.06; f.vx = 0.0; f.vy = 0.0
                    f.damage = 0.0; f.invuln = 1.4; f.onGround = false; f.jumpsLeft = 2
                }
            }
        }
        // Keep the player even at 0 lives (we fail on that); drop defeated rivals.
        fighters = fighters.filter { it.isPlayer || it.lives > 0 }.toMutableList()
        if (fighters.isEmpty()) return
        if (fighters[0].lives <= 0) { fail(); return }
        if (enemiesLeft == 0) win()
    }

    fun win() { if (!playing) return; playing = false; onWin() }
    fun fail() { if (!playing) return; playing = false; SoundManager.error(); onFail() }
}

@Composable
private fun LedgeBrawlView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { Brawl(level, isDemo).also { if (!isDemo) { it.setup(); it.startT = nowSec() } } }
    world.onWin = onWin; world.onFail = onFail
    var demoTick by remember { mutableIntStateOf(0) }
    var demoMove by remember { mutableStateOf(0.0) }
    var demoJump by remember { mutableStateOf(false) }
    var demoFire by remember { mutableStateOf(false) }
    var heldDir by remember { mutableStateOf(0.0) }
    val tm = rememberTextMeasurer()

    val tickState = rememberFrameLoop(running = !isDemo) { dt ->
        if (!world.playing) return@rememberFrameLoop
        world.timeLeft = max(0.0, world.timeLimit - (nowSec() - world.startT))
        if (world.timeLeft <= 0) { world.fail(); return@rememberFrameLoop }
        world.step(dt)
    }
    val tick by tickState

    // Demo (live manual clip): level 1, one rival, fixed 1/60 s steps with a coin-flip-free rival.
    LaunchedEffect(Unit) {
        if (!isDemo) return@LaunchedEffect
        val dt = 1.0 / 60.0
        while (isActive) {
            world.setup()
            for (f in world.fighters) if (!f.isPlayer) f.shootCD = world.enemyFire
            demoMove = 0.0; demoJump = false; demoFire = false
            demoTick++
            delay(500)
            var t = 0.0; var nextFire = 0.0; var jumpFlash = 0.0; var fireFlash = 0.0
            while (isActive && world.playing && t < 8) {
                t += dt
                val me = world.fighters.firstOrNull()
                if (me != null) {
                    val frame = (t * 60).roundAway()
                    world.playerMoveDir = if (frame <= 8) -1.0 else 0.0
                    val incoming = world.bullets.any { b ->
                        !b.fromPlayer && abs(b.y - me.y) < FH + 0.02 && (b.x - me.x) * b.vx < 0 && abs(b.x - me.x) < 0.2
                    }
                    val inbound = world.bullets.any { !it.fromPlayer && (it.x - me.x) * (if (it.vx > 0) 1 else -1) < FW * 2 }
                    val launched = !inbound && world.fighters.drop(1).any { it.x < 0 || it.x > 1 }
                    if (me.onGround && (incoming || launched)) { world.playerJumpReq = true; jumpFlash = 0.18 }
                    if (me.onGround && t >= nextFire) { world.playerShootReq = true; fireFlash = 0.12; nextFire = t + 0.33 }
                    demoMove = world.playerMoveDir; demoJump = jumpFlash > 0; demoFire = fireFlash > 0
                }
                world.step(dt)
                jumpFlash -= dt; fireFlash -= dt
                demoTick++
                delay(16)
            }
            // The rival fell off: hold while you land your hop and the last bullets fly out, then loop.
            world.playerMoveDir = 0.0
            repeat(78) {
                if (!isActive) return@LaunchedEffect
                world.fighters.firstOrNull()?.let { world.physics(it, dt) }
                world.stepBullets(dt)
                jumpFlash -= dt; fireFlash -= dt
                demoMove = 0.0; demoJump = jumpFlash > 0; demoFire = fireFlash > 0
                demoTick++
                delay(16)
            }
        }
    }

    val btnW = if (isDemo) 54.0 else 72.0
    val btnH = if (isDemo) 42.0 else 58.0
    val corner = if (isDemo) 10.dp else 14.dp

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp)
            .clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .drawBehind { gunmetal() }
            .padding(vertical = if (isDemo) 6.dp else 10.dp),
        verticalArrangement = Arrangement.spacedBy(if (isDemo) 6.dp else 8.dp)
    ) {
        if (!isDemo) Hud(world, tickState)

        Box(
            Modifier.fillMaxWidth().weight(1f).padding(horizontal = if (isDemo) 6.dp else 10.dp)
                .graphicsLayer {
                    val t = nowSec() - world.shakeT0
                    if (t in 0.0..0.35) {
                        val k = sin(t / 0.35 * PI * 3)
                        translationX = (6 * density * k).toFloat(); translationY = (6 * 0.6 * density * k).toFloat()
                    }
                }
                .clip(RoundedCornerShape(corner))
        ) {
            // The static stage: drawn once (reads no per-frame state).
            Canvas(Modifier.fillMaxSize()) { MayhemArt.stage(this, level, world.plats) }
            Canvas(Modifier.fillMaxSize()) {
                tick; demoTick
                drawAction(world, tm)
                val now = nowSec()
                val w = size.width.toDouble(); val h = size.height.toDouble()
                world.bursts.removeAll { now - it.t0 > 0.6 }
                for (b in world.bursts) particleBurst(b.x * w, b.y * h, now - b.t0, b.color, 12, 46.0, seed = b.seed)
                rrectStroke(1.0, 1.0, w - 2, h - 2, corner.toPx() - 1.0, Color.Black, 2.0 * density)
            }
        }

        // Controls: riveted steel keys.
        Row(
            Modifier.fillMaxWidth().padding(horizontal = if (isDemo) 14.dp else 22.dp).padding(bottom = if (isDemo) 0.dp else 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(if (isDemo) 8.dp else 12.dp)) {
                for (dir in listOf(-1.0, 1.0)) {
                    val lit = heldDir == dir || (isDemo && demoMove == dir)
                    SteelKey(btnW, btnH, lit, false, if (dir < 0) Icons.Filled.ChevronLeft else Icons.Filled.ChevronRight, isDemo,
                        onDown = { if (!isDemo && world.playing) { heldDir = dir; world.playerMoveDir = dir } },
                        onUp = { if (heldDir == dir) { heldDir = 0.0; world.playerMoveDir = 0.0 } })
                }
            }
            Spacer(Modifier.weight(1f))
            Row(horizontalArrangement = Arrangement.spacedBy(if (isDemo) 8.dp else 12.dp)) {
                SteelKey(btnW, btnH, demoJump, false, Icons.Filled.ArrowUpward, isDemo,
                    onDown = { if (!isDemo) { world.playerJumpReq = true; Haptics.tap() } })
                SteelKey(btnW, btnH, demoFire, true, Icons.Filled.GpsFixed, isDemo,
                    onDown = { if (!isDemo) world.playerShootReq = true })
            }
        }
    }
}

@Composable
private fun Hud(world: Brawl, tickState: androidx.compose.runtime.State<Long>) {
    tickState.value
    Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        FighterChip(BananaTheme.banana, 0, world.fighters.firstOrNull()?.hat ?: Color.Black, L("YOU", "BẠN"), world.playerLives)
        Spacer(Modifier.weight(1f).width(4.dp))
        val t = max(0, ceil(world.timeLeft).toInt())
        Box(Modifier.drawBehind { steelPlate(false, false) }.padding(horizontal = 14.dp, vertical = 5.dp)) {
            Text("%d:%02d".format(t / 60, t % 60),
                style = ts(20.0, FontWeight.Black, if (world.timeLeft < 10) rgb(1.0, 0.35, 0.3) else gray(0.12), Mono))
        }
        Spacer(Modifier.weight(1f).width(4.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (f in world.fighters) if (!f.isPlayer) FighterChip(f.shirt, f.id, f.hat, null, f.lives)
        }
    }
}

@Composable
private fun SteelKey(w: Double, h: Double, lit: Boolean, red: Boolean, icon: ImageVector, isDemo: Boolean, onDown: () -> Unit, onUp: () -> Unit = {}) {
    HoldKey(Modifier.size(w.dp, h.dp), enabled = !isDemo, onDown = onDown, onUp = onUp) { held ->
        val down = held || lit
        Box(Modifier.fillMaxSize().scale(if (down) 0.94f else 1f).drawBehind { steelPlate(down, red) }, contentAlignment = Alignment.Center) {
            val tint = if (red) Color.White else gray(if (down) 0.05 else 0.14)
            val shadow = if (red) Color.Black.op(0.4) else Color.White.op(0.5)
            val s = if (isDemo) 22.dp else 30.dp
            Icon(icon, null, tint = shadow, modifier = Modifier.size(s).graphicsLayer { translationY = density })
            Icon(icon, null, tint = tint, modifier = Modifier.size(s))
        }
    }
}

@Composable
private fun FighterChip(color: Color, hat: Int, hatColor: Color, label: String?, lives: Int) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Canvas(Modifier.size(24.dp, 26.dp)) {
            MayhemArt.headIcon(this, size.width / 2.0, size.height * 0.58, size.height * 0.3, color, hat, hatColor)
        }
        if (label != null) Text(label, style = ts(12.0, FontWeight.Black, Color.White))
        Text("×${max(0, lives)}", style = ts(13.0, FontWeight.ExtraBold, gray(0.8)))
    }
}

private fun DrawScope.drawAction(world: Brawl, tm: androidx.compose.ui.text.TextMeasurer) {
    val w = size.width.toDouble(); val h = size.height.toDouble()
    val u = density.toDouble()
    // Tracer rounds.
    for (b in world.bullets) {
        val px = b.x * w; val py = b.y * h
        val dir = if (b.vx >= 0) 1.0 else -1.0
        val len = max(12 * u, w * 0.07)
        val tx = px - dir * len
        val col = if (b.fromPlayer) rgb(1.0, 0.93, 0.45) else rgb(1.0, 0.5, 0.28)
        drawLine(lin(listOf(col.op(0.0), col), tx, py, px, py), off(tx, py), off(px, py), (3 * u).f, StrokeCap.Round)
        circle(px, py, 2 * u, Color.White)
    }
    // Fighters.
    val figureH = FH * 2.3 * h
    val tagSize = max(8 * u, figureH * 0.24)
    var botNumber = 0
    val tags = mutableListOf<DoubleArray>()
    val labels = mutableListOf<Triple<String, Color, P>>()
    for (f in world.fighters) {
        if (!f.isPlayer) botNumber++
        val blink = f.invuln > 0 && (f.invuln * 12).toInt() % 2 == 0
        val fx = f.x * w; val fy = (f.y + FH) * h
        val reload = if (f.isPlayer) PLAYER_FIRE else world.enemyFire
        val justFired = f.shootCD > reload - 0.08
        val pose = when {
            !f.onGround -> StickPose.jumping
            justFired -> MayhemArt.aim
            abs(f.vx) > 0.08 -> if ((f.x * 90).toInt() % 2 == 0) StickPose.runA else StickPose.runB
            else -> StickPose.standing
        }
        MayhemArt.fighter(this, pose, fx, fy, figureH, f.facing, f.shirt, f.id, f.hat, if (blink) 0.35 else 1.0, justFired)
        val tag = if (f.isPlayer) L("YOU", "BẠN") else L("BOT $botNumber", "MÁY $botNumber")
        val tw = textWidth(tm, tag, tagSize, FontWeight.ExtraBold)
        val th = tagSize * 1.2
        var ay = fy - figureH * 1.14
        var box = doubleArrayOf(fx - tw / 2, ay - th / 2, tw, th)
        fun hits(a: DoubleArray, b: DoubleArray) = a[0] < b[0] + b[2] && b[0] < a[0] + a[2] && a[1] < b[1] + b[3] && b[1] < a[1] + a[3]
        while (tags.any { hits(it, box) }) {
            ay -= th + 1
            box = doubleArrayOf(box[0], box[1] - (th + 1), tw, th)
        }
        tags += box
        labels += Triple(tag, if (f.isPlayer) BananaTheme.banana else Color.White, P(fx, ay))
    }
    // Tags go on last, so no fighter is ever drawn over a name.
    for ((tag, c, at) in labels) {
        text(tm, tag, at.x + u, at.y + u, tagSize, Color.Black.op(0.7), FontWeight.ExtraBold)
        text(tm, tag, at.x, at.y, tagSize, c, FontWeight.ExtraBold)
    }
}

private fun DrawScope.gunmetal() {
    drawRect(Brush.verticalGradient(listOf(rgb(0.16, 0.17, 0.2), rgb(0.08, 0.085, 0.1))))
    var y = 0f
    val step = 3f * density
    while (y < size.height) { drawLine(Color.White.op(0.025), Offset(0f, y), Offset(size.width, y), density); y += step }
}

/** A riveted steel plate, like the letters of the original logo. */
private fun DrawScope.steelPlate(pressed: Boolean, red: Boolean) {
    val u = density.toDouble()
    val x = u; val y = u; val w = size.width - 2 * u; val h = size.height - 2 * u
    val top = if (red) rgb(0.93, 0.36, 0.32) else rgb(0.84, 0.86, 0.89)
    val bottom = if (red) rgb(0.6, 0.14, 0.13) else rgb(0.52, 0.55, 0.6)
    rrect(x, y, w, h, 9 * u, vgrad(if (pressed) listOf(bottom, top.shade(0.1)) else listOf(top, bottom), y, y + h))
    rrectStroke(x + 2 * u, y + 2 * u, w - 4 * u, h - 4 * u, 7 * u, Color.White.op(if (pressed) 0.15 else 0.45), u)
    rrectStroke(x, y, w, h, 9 * u, MayhemArt.ink, 2 * u)
    for ((rx, ry) in listOf(x + 6 * u to y + 6 * u, x + w - 6 * u to y + 6 * u, x + 6 * u to y + h - 6 * u, x + w - 6 * u to y + h - 6 * u)) {
        circle(rx, ry, 2.2 * u, bottom.shade(0.35))
        circle(rx - 0.4 * u, ry - 0.8 * u, 0.8 * u, Color.White.op(0.7))
    }
}

private object MayhemArt {
    val ink = rgb(0.05, 0.05, 0.09)
    /** Firing, with the pistol held at chest height — level with where the rounds leave. */
    val aim = StickPose(P(0.50, 0.15), 0.10, P(0.50, 0.27), P(0.50, 0.60),
        P(0.42, 0.40), P(0.37, 0.47), P(0.62, 0.39), P(0.76, 0.41),
        P(0.44, 0.78), P(0.38, 0.97), P(0.58, 0.78), P(0.64, 0.97))
    val skyTops = listOf(rgb(0.14, 0.20, 0.34), rgb(0.20, 0.18, 0.34), rgb(0.24, 0.16, 0.30), rgb(0.22, 0.13, 0.24),
        rgb(0.18, 0.10, 0.20), rgb(0.14, 0.07, 0.14), rgb(0.10, 0.04, 0.10))
    val skyBottoms = listOf(rgb(0.28, 0.40, 0.55), rgb(0.34, 0.32, 0.50), rgb(0.40, 0.28, 0.44), rgb(0.36, 0.22, 0.34),
        rgb(0.30, 0.16, 0.28), rgb(0.22, 0.10, 0.20), rgb(0.16, 0.06, 0.14))

    fun hash(n: Double): Double { val v = sin(n * 12.9898) * 43758.5453; return v - floor(v) }

    /** Night rooftops: sky, moon, two rows of skyline with lit windows, the platforms, fog over the drop. */
    fun stage(d: DrawScope, level: Int, plats: List<Plat>) = with(d) {
        val li = max(1, min(level, 7)) - 1
        val w = size.width.toDouble(); val h = size.height.toDouble()
        val u = density.toDouble()
        drawRect(vgrad(listOf(skyTops[li], skyBottoms[li]), 0.0, h))
        val mcx = w * 0.8; val mcy = h * 0.15; val mr = min(w, h) * 0.07
        drawCircle(Brush.radialGradient(0f to Color.White.op(0.18), (1f / 3f) to Color.White.op(0.18), 1f to Color.Transparent,
            center = off(mcx, mcy), radius = (mr * 3).f), (mr * 3).f, off(mcx, mcy))
        circle(mcx, mcy, mr, rgb(0.95, 0.93, 0.84))
        skyline(w, h, h * 0.34, 3, skyBottoms[li].mix(rgb(0.1, 0.1, 0.14), 0.45), 0.25, u)
        skyline(w, h, h * 0.5, 17, skyTops[li].mix(Color.Black, 0.55), 0.45, u)
        // Platforms: the main one is a rooftop, high ones steel girders, the rest wooden planks.
        val mainW = plats.maxOf { it.w }
        for (p in plats) {
            val rx = p.x * w; val ry = p.y * h; val rw = p.w * w; val rh = max(10 * u, h * 0.03)
            when {
                p.w == mainW -> rooftop(rx, ry, rw, rh, h, u)
                p.y < 0.5 -> girder(rx, ry, rw, rh, u)
                else -> plank(rx, ry, rw, rh, u)
            }
        }
        // Fog over the drop, and a soft vignette.
        rect(0.0, h * 0.84, w, h * 0.16, vgrad(listOf(skyBottoms[li].lit(0.1).op(0.0), skyBottoms[li].lit(0.12).op(0.75)), h * 0.84, h))
        val r0 = min(w, h) * 0.4; val r1 = max(w, h) * 0.75
        drawRect(Brush.radialGradient(0f to Color.Transparent, (r0 / r1).f to Color.Transparent, 1f to Color.Black.op(0.4),
            center = off(w / 2, h / 2), radius = r1.f))
    }

    private fun DrawScope.skyline(w: Double, h: Double, top: Double, seed: Int, color: Color, lit: Double, u: Double) {
        var x = -w * 0.03
        var k = 0
        val windows = Path()
        while (x < w) {
            val s = (seed * 31 + k).toDouble()
            val bw = w * (0.08 + hash(s) * 0.1)
            val bh = (h - top) * (0.45 + hash(s + 1.3) * 0.55)
            val ry = h - bh
            rect(x, ry, bw, bh, color)
            if (hash(s + 2.7) > 0.6) {
                val tw = bw * 0.35
                rect(x + bw * 0.3, ry - tw * 0.9, tw, tw * 0.7, color)
                rect(x + bw * 0.3 + tw * 0.15, ry - tw * 0.25, tw * 0.7, tw * 0.25, color)
            } else if (hash(s + 4.1) > 0.5) {
                line(x + bw / 2, ry, x + bw / 2, ry - bh * 0.18, color, 1.5 * u, StrokeCap.Butt)
            }
            val cw = max(2.5 * u, bw * 0.12); val ch = max(3 * u, cw * 1.2)
            var yy = ry + ch
            var row = 0
            while (yy < h - ch) {
                var xx = x + cw * 0.8
                var col = 0
                while (xx < x + bw - cw) {
                    if (hash(s * 7 + row * 1.9 + col * 3.3) < lit) windows.addRect(androidx.compose.ui.geometry.Rect(xx.f, yy.f, (xx + cw).f, (yy + ch).f))
                    xx += cw * 2; col++
                }
                yy += ch * 2; row++
            }
            x += bw + w * 0.005
            k++
        }
        drawPath(windows, rgb(1.0, 0.84, 0.45, 0.55))
    }

    /** The main platform: a concrete rooftop with a ledge, its building dropping away into the fog. */
    private fun DrawScope.rooftop(x: Double, y: Double, rw: Double, rh: Double, h: Double, u: Double) {
        val bx = x + 4 * u; val bw = rw - 8 * u; val bh = h - y + 2 * u
        rect(bx, y, bw, bh, vgrad(listOf(rgb(0.24, 0.25, 0.3), rgb(0.13, 0.13, 0.17)), y, y + bh))
        val windows = Path()
        val cw = max(5 * u, rw * 0.045); val ch = cw * 1.3
        var yy = y + rh + ch
        var row = 0
        while (yy < h) {
            var xx = bx + cw
            var col = 0
            while (xx < bx + bw - cw) {
                if (hash(row * 5.1 + col * 2.3) > 0.55) windows.addRect(androidx.compose.ui.geometry.Rect(xx.f, yy.f, (xx + cw).f, (yy + ch).f))
                xx += cw * 2.2; col++
            }
            yy += ch * 2; row++
        }
        drawPath(windows, rgb(1.0, 0.82, 0.42, 0.5))
        rectStroke(bx, y, bw, bh, ink, 2 * u)
        rect(x, y, rw, rh, vgrad(listOf(rgb(0.62, 0.64, 0.68), rgb(0.42, 0.44, 0.49)), y, y + rh))
        rect(x, y, rw, 2 * u, Color.White.op(0.45))
        rectStroke(x, y, rw, rh, ink, 2 * u)
    }

    /** A wooden plank with seams and nails. */
    private fun DrawScope.plank(x: Double, y: Double, rw: Double, rh: Double, u: Double) {
        rect(x, y, rw, rh, vgrad(listOf(rgb(0.78, 0.53, 0.3), rgb(0.56, 0.35, 0.18)), y, y + rh))
        var sx = x + rw / 3
        while (sx < x + rw - 2 * u) { line(sx, y, sx, y + rh, ink.op(0.6), u, StrokeCap.Butt); sx += rw / 3 }
        for (k in 0 until 3) for (dx in listOf(4 * u, rw / 3 - 4 * u)) circle(x + k * rw / 3 + dx, y + rh / 2, u, ink.op(0.7))
        rect(x, y, rw, 1.5 * u, Color.White.op(0.35))
        rectStroke(x, y, rw, rh, ink, 2 * u)
    }

    /** A riveted steel I-beam. */
    private fun DrawScope.girder(x: Double, y: Double, rw: Double, rh: Double, u: Double) {
        val flange = rh * 0.3
        rect(x + rw * 0.02, y + flange, rw * 0.96, rh - flange * 2, rgb(0.34, 0.36, 0.4))
        for (fy in listOf(y, y + rh - flange)) {
            rect(x, fy, rw, flange, vgrad(listOf(rgb(0.7, 0.73, 0.78), rgb(0.42, 0.45, 0.5)), fy, fy + flange))
            rectStroke(x, fy, rw, flange, ink, 1.5 * u)
        }
        var rx = x + 6 * u
        while (rx < x + rw - 4 * u) { circle(rx, y + rh / 2, 1.2 * u, gray(0.75)); rx += 10 * u }
        rectStroke(x, y, rw, rh, ink, 2 * u)
    }

    /** A stick-figure gunner: outlined round-capped limbs, a vest torso, a hat, a pistol, and a muzzle flash. */
    fun fighter(d: DrawScope, pose: StickPose, fx: Double, fy: Double, hgt: Double, facing: Double, color: Color,
                hat: Int, hatColor: Color, alpha: Double, flash: Boolean) = with(d) {
        fun m(p: P) = P(fx + (p.x - 0.5) * hgt * facing, fy - (0.97 - p.y) * hgt)
        val lw = max(1.8 * density, hgt * 0.075)
        val ol = max(1.1 * density, hgt * 0.03)
        val dx = pose.rHand.x - pose.rElbow.x; val dy = pose.rHand.y - pose.rElbow.y
        val len = max(0.0001, hypot(dx, dy))
        val tip = P(pose.rHand.x + dx / len * 0.16, pose.rHand.y + dy / len * 0.16)
        withAlpha(alpha) {
            val limbs = Path()
            for ((a, b, e) in listOf(Triple(pose.neck, pose.lElbow, pose.lHand), Triple(pose.neck, pose.rElbow, pose.rHand),
                Triple(pose.hip, pose.lKnee, pose.lFoot), Triple(pose.hip, pose.rKnee, pose.rFoot))) {
                val ma = m(a); val mb = m(b); val me = m(e)
                limbs.m(ma.x, ma.y); limbs.l(mb.x, mb.y); limbs.l(me.x, me.y)
            }
            val torso = Path()
            m(pose.neck).let { torso.m(it.x, it.y) }; m(pose.hip).let { torso.l(it.x, it.y) }
            val grip = P(pose.rHand.x - dy / len * 0.06, pose.rHand.y + abs(dx / len) * 0.06 + 0.02)
            val gun = Path()
            val mh = m(pose.rHand); val mt = m(tip); val mg = m(grip)
            gun.m(mh.x, mh.y); gun.l(mt.x, mt.y); gun.m(mh.x, mh.y); gun.l(mg.x, mg.y)
            val hc = m(pose.head)
            val hr = pose.headR * hgt
            fun st(wd: Double) = Stroke(wd.f, cap = StrokeCap.Round, join = StrokeJoin.Round)
            drawPath(limbs, ink, style = st(lw + ol * 2))
            drawPath(torso, ink, style = st(lw * 2.2 + ol * 2))
            drawPath(gun, ink, style = st(lw * 0.9 + ol * 2))
            circle(hc.x, hc.y, hr + ol, ink)
            drawPath(limbs, color, style = st(lw))
            drawPath(torso, color.shade(0.12), style = st(lw * 2.2))
            drawPath(gun, gray(0.24), style = st(lw * 0.9))
            circle(hc.x, hc.y, hr, color)
            headwear(this, hc.x, hc.y, hr, hat, hatColor, facing, ol)
        }
        if (flash) {
            val f = m(tip)
            val fr = hgt * 0.16
            val star = Path()
            for (k in 0 until 8) {
                val a = k / 8.0 * 2 * PI
                val rr = if (k % 2 == 0) fr else fr * 0.4
                val px = f.x + cos(a) * rr * (if (cos(a) * facing > 0.5) 1.5 else 1.0); val py = f.y + sin(a) * rr
                if (k == 0) star.m(px, py) else star.l(px, py)
            }
            star.close()
            drawPath(star, Brush.radialGradient(listOf(Color.White, rgb(1.0, 0.85, 0.3), rgb(1.0, 0.5, 0.1)), off(f.x, f.y), (fr * 1.4).f))
        }
    }

    /** Crown for you; beanie, cap and top hat for the three rivals; shades on the cap and top hat. */
    fun headwear(d: DrawScope, cx: Double, cy: Double, hr: Double, hat: Int, hatColor: Color, facing: Double, ol: Double) = with(d) {
        val edge = Stroke(max(1.0, ol).f, join = StrokeJoin.Round)
        when (hat) {
            0 -> {
                val y0 = cy - hr * 0.55; val y1 = cy - hr * 1.45; val x0 = cx - hr * 0.8; val x1 = cx + hr * 0.8
                val crown = polyPath(x0, y0, x0, y1, cx - hr * 0.4, y0 - hr * 0.45, cx, y1 - hr * 0.1,
                    cx + hr * 0.4, y0 - hr * 0.45, x1, y1, x1, y0)
                drawPath(crown, rgb(1.0, 0.8, 0.2))
                drawPath(crown, ink, style = edge)
            }
            1 -> {
                val beanie = Path()
                beanie.arc(cx, cy - hr * 0.1, hr * 1.08, deg(190.0), deg(350.0), moveFirst = true)
                beanie.close()
                drawPath(beanie, hatColor)
                drawPath(beanie, ink, style = edge)
                val pr = hr * 0.32
                circle(cx, cy - hr * 1.28, pr, Color.White)
                circleStroke(cx, cy - hr * 1.28, pr, ink, max(1.0, ol))
            }
            2 -> {
                val cap = Path()
                cap.arc(cx, cy - hr * 0.15, hr * 1.02, deg(185.0), deg(355.0), moveFirst = true)
                cap.close()
                line(cx, cy - hr * 0.2, cx + facing * hr * 1.7, cy - hr * 0.1, ink, hr * 0.45 + ol)
                line(cx, cy - hr * 0.2, cx + facing * hr * 1.7, cy - hr * 0.1, hatColor, hr * 0.45)
                drawPath(cap, hatColor)
                drawPath(cap, ink, style = edge)
                shades(cx, cy, hr, facing)
            }
            else -> {
                val bx = cx - hr * 0.7; val by = cy - hr * 2.1; val bw = hr * 1.4; val bh = hr * 1.5
                rect(bx, by, bw, bh, gray(0.1))
                drawRect(ink, off(bx, by), sz(bw, bh), style = edge)
                rect(bx, by + bh - hr * 0.4, bw, hr * 0.25, hatColor.lit(0.2))
                line(cx - hr * 1.15, by + bh, cx + hr * 1.15, by + bh, ink, hr * 0.3 + ol)
                line(cx - hr * 1.15, by + bh, cx + hr * 1.15, by + bh, gray(0.12), hr * 0.3)
                shades(cx, cy, hr, facing)
            }
        }
    }

    private fun DrawScope.shades(cx: Double, cy: Double, hr: Double, facing: Double) {
        val lx = if (facing > 0) cx - hr * 0.05 else cx - hr * 0.95
        val ly = cy - hr * 0.25
        rrect(lx, ly, hr, hr * 0.42, hr * 0.15, gray(0.06))
        rect(lx + hr * 0.15, ly + hr * 0.08, hr * 0.25, hr * 0.08, Color.White.op(0.6))
    }

    /** A small head with its hat, for the HUD chips. */
    fun headIcon(d: DrawScope, cx: Double, cy: Double, r: Double, color: Color, hat: Int, hatColor: Color) = with(d) {
        val ol = 1.5 * density
        circle(cx, cy, r + ol, ink)
        circle(cx, cy, r, color)
        headwear(this, cx, cy, r, hat, hatColor, 1.0, ol)
    }
}
