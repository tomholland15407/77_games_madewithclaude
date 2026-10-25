package com.gogs.bananagame.games.sniper

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GpsFixed
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material.icons.outlined.WaterDrop
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
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/**
 * Reflex — Sniper (iOS SniperGame.swift, id "sniper"): a scoped marksman game. Drag to pan the scope
 * across a wide vista, tap FIRE to hitscan whatever sits under the crosshair (exactly where the drawn
 * red dot is, sway and recoil included). Enemies can't draw on you until a beat after your first shot;
 * then a soldier now and then stops and raises its rifle, painting a thickening red beam at the scope,
 * and if it completes you lose a drop of blood. A miss startles the nearest soldier into aiming, and
 * the magazine is limited. Down every soldier to win; bleed out, run dry or time out and it's level 1.
 * Drag to aim → locks the feed while playing.
 */
object SniperGame {
    val definition = GameDefinition(
        id = "sniper",
        title = "Sniper",
        genre = Genre.REFLEX,
        locksFeed = true,
        manual = GameManual(
            bullets = listOf(
                "Drag to pan your scope across the vista; tap FIRE to hitscan whatever is under the crosshair.",
                "Red soldiers patrol; one periodically stops and paints a growing red beam at you.",
                "Drop it before the beam completes or you take a hit (you can survive a few).",
                "Missing startles the nearest enemy into aiming, and your magazine is limited.",
            ),
            bulletsVI = listOf(
                "Kéo để lia ống ngắm khắp cảnh; chạm BẮN để bắn trúng ngay thứ dưới tâm ngắm.",
                "Lính đỏ tuần tra; một tên thỉnh thoảng dừng lại và vẽ một tia đỏ lớn dần nhắm vào bạn.",
                "Hạ nó trước khi tia hoàn tất, nếu không bạn trúng đạn (bạn chịu được vài phát).",
                "Bắn trượt làm kẻ gần nhất giật mình giương súng, và băng đạn của bạn có hạn.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> SniperView(level, onWin, onFail) }
    )
}

// World geometry (world units; the scene is SCENE_W wide, 1.0 tall).
internal const val SCENE_W = 2.4
internal const val VIEW_H = 0.62        // world units of scene height visible through the scope
internal const val GROUND_V = 0.60      // horizon / where soldiers stand
internal const val TARGET_H = 0.085     // a soldier's height

class SniperWorld(val level: Int) {
    private val li = min(max(level, 1), 7) - 1
    val targetCount = listOf(2, 3, 3, 4, 5, 6, 7)[li]
    val walkSpeed = listOf(0.05, 0.06, 0.07, 0.08, 0.09, 0.10, 0.11)[li]        // world/sec
    /** Average seconds a soldier patrols before it decides to raise its rifle. */
    val aimEvery = listOf(6.5, 5.6, 4.8, 4.0, 3.3, 2.7, 2.2)[li]
    /** How long the raised-rifle telegraph lasts before it fires (your window to drop it). */
    val aimTime = listOf(3.0, 2.6, 2.3, 2.0, 1.7, 1.4, 1.1)[li]
    val swayAmp = listOf(0.004, 0.006, 0.008, 0.011, 0.014, 0.018, 0.022)[li]
    val ammo0 = targetCount + listOf(5, 5, 4, 4, 3, 2, 2)[li]
    val timeLimit = (16 + targetCount * 7).toDouble()
    /** Hits you can take before you're down — your "blood". */
    val maxHP = listOf(4, 4, 3, 3, 3, 2, 2)[li]
    /** Enemies can't draw on you until this long AFTER your first shot. */
    val armDelay0 = listOf(2.4, 2.2, 2.0, 1.8, 1.6, 1.4, 1.2)[li]

    class Target(
        var x: Double, val y: Double, var dir: Double, val minX: Double, val maxX: Double, var speed: Double, var aimCD: Double,
        var aiming: Boolean = false, var aimT: Double = 0.0, var pause: Double = 0.0,
    )
    class Ridge(val x: Double, val top: Double)
    class Building(val x: Double, val w: Double, val h: Double, val shade: Double)
    class Prop(val x: Double, val kind: Int)
    class Burst(val wx: Double, val wy: Double, val color: Color, val big: Boolean, val t0: Double, val seed: Int)
    /** A soldier just shot: it topples where it stood, then fades. */
    class Down(val wx: Double, val wy: Double, val facing: Double, val at: Double)

    var playing = true
    var aimX = 0.4; var aimY = 0.52
    val targets = mutableListOf<Target>()
    val bursts = mutableListOf<Burst>()
    val downed = mutableListOf<Down>()
    var ammo = 0
    var hp = 0
    var hasFired = false
    var armDelay = 0.0
    var hurt = 0.0                  // red hit-flash, decays
    var timeLeft = 0.0
    var recoil = 0.0
    var muzzle = 0.0
    var animT = 0.0
    var shakeT0 = -10.0
    var ridges = listOf<Ridge>()
    var midline = listOf<Ridge>()
    var buildings = listOf<Building>()
    var props = listOf<Prop>()
    /** The visible play area, in points (for the pan clamp and the shot's dot size). */
    var areaW = 1.0; var areaH = 1.0
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}
    private var burstSeed = 0

    val danger get() = targets.any { it.aiming }
    /** Enemies only start drawing on you a beat after your first shot. */
    val armed get() = hasFired && armDelay <= 0

    fun setup() {
        playing = true
        ammo = ammo0; hp = maxHP
        hasFired = false; armDelay = 0.0; hurt = 0.0
        timeLeft = timeLimit
        recoil = 0.0; muzzle = 0.0; animT = 0.0
        aimX = 0.4; aimY = 0.52
        bursts.clear()
        // Scenery (generated once so it never flickers).
        ridges = strideList(-0.3, SCENE_W + 0.3, 0.12).map { Ridge(it, GROUND_V - rnd(0.10, 0.20)) }
        midline = strideList(-0.3, SCENE_W + 0.3, 0.08).map { Ridge(it, GROUND_V - rnd(0.03, 0.10)) }
        buildings = List(7) { Building(rnd(0.1, SCENE_W - 0.1), rnd(0.08, 0.16), rnd(0.10, 0.22), rnd(0.1, 0.35)) }
        props = List(26) { Prop(rnd(0.05, SCENE_W - 0.05), if (rndInt(0..2) == 0) 0 else 1) }
        // Soldiers spread across the scene, each with its own patrol lane.
        targets.clear()
        val slot = (SCENE_W - 0.4) / targetCount
        for (i in 0 until targetCount) {
            val base = 0.2 + slot * (i + 0.5)
            val span = min(slot * 0.4, 0.22)
            targets.add(Target(base, GROUND_V + rnd(-0.005, 0.005), if (Random.nextBoolean()) 1.0 else -1.0,
                base - span, base + span, walkSpeed * rnd(0.85, 1.15), rnd(aimEvery * 0.4, aimEvery)))
        }
    }

    /** The manual clip's start: two stationary soldiers at fixed, in-view spots. */
    fun demoSetup() {
        playing = true
        ammo = ammo0; hp = maxHP
        hasFired = false; armDelay = 0.0; hurt = 0.0; recoil = 0.0; muzzle = 0.0
        bursts.clear()
        targets.clear()
        targets.add(Target(0.80, GROUND_V, -1.0, 0.80, 0.80, 0.0, Double.POSITIVE_INFINITY))
        targets.add(Target(1.62, GROUND_V, 1.0, 1.62, 1.62, 0.0, Double.POSITIVE_INFINITY))
        aimX = 0.44; aimY = 0.52
    }

    /** Grab-the-world: a drag (points) moves the vista under the fixed reticle. */
    fun pan(dx: Double, dy: Double) {
        if (!playing) return
        val s = areaH / VIEW_H
        val viewWx = VIEW_H * (areaW / max(1.0, areaH))
        val minX = viewWx / 2 + 0.02; val maxX = SCENE_W - viewWx / 2 - 0.02
        aimX = min(max(minX, aimX - dx / s), maxX)
        aimY = min(max(0.45, aimY - dy / s), 0.62)
    }

    /** The ambient clock alone (sway, recoil / muzzle / hurt decay): what the demo runs. */
    fun tickAmbient(dt: Double) {
        animT += dt
        if (recoil > 0) recoil = max(0.0, recoil - dt * 6)
        if (muzzle > 0) muzzle = max(0.0, muzzle - dt)
        if (hurt > 0) hurt = max(0.0, hurt - dt * 2.2)
    }

    fun step(dt: Double) {
        if (!playing) return
        tickAmbient(dt)
        if (hasFired && armDelay > 0) armDelay = max(0.0, armDelay - dt)
        for (t in targets) {
            if (t.aiming) {
                t.aimT -= dt
                if (t.aimT <= 0) {                  // the shot connects — you take a hit
                    t.aiming = false
                    t.aimCD = rnd(aimEvery * 0.6, aimEvery)
                    takeHit()
                    if (!playing) return
                }
                continue
            }
            // Patrol.
            if (t.pause > 0) {
                t.pause -= dt
            } else {
                t.x += t.dir * t.speed * dt
                if (t.x <= t.minX) { t.x = t.minX; t.dir = 1.0 }
                if (t.x >= t.maxX) { t.x = t.maxX; t.dir = -1.0 }
                if (Random.nextDouble() < dt * 0.4) t.pause = rnd(0.3, 1.0)
            }
            // Enemies only draw on you once armed.
            if (armed) {
                t.aimCD -= dt
                if (t.aimCD <= 0) raiseWeapon(t)
            }
        }
        timeLeft -= dt
        if (timeLeft <= 0) { timeLeft = 0.0; fail() }
    }

    private fun takeHit() {
        hp -= 1
        hurt = 1.0
        shakeT0 = nowSec()
        Haptics.warning(); SoundManager.error()
        if (hp <= 0) fail()
    }

    private fun raiseWeapon(t: Target) {
        t.aiming = true
        t.aimT = aimTime
        t.dir = -1.0   // turn to face the scope
        SoundManager.error(); Haptics.warning()
    }

    fun swayX() = cos(animT * 1.3) * swayAmp + sin(animT * 2.3) * swayAmp * 0.5
    fun swayY() = sin(animT * 1.7) * swayAmp

    /** The pose and facing a soldier is drawn with right now — shared by the art and the shot's hit test. */
    fun figure(t: Target): Pair<StickPose, Double> {
        val walking = t.speed > 0 && t.pause <= 0
        val f2 = ((animT + t.x * 5) * 6).toInt() % 2 == 1
        val pose = if (t.aiming) SNArt.aimPose else if (walking) (if (f2) SNArt.walkB else SNArt.walkA) else SNArt.standPose
        // A soldier drawing on you turns his rifle toward the scope.
        val facing = if (t.aiming) (if (t.x < aimX) 1.0 else -1.0) else (if (t.dir < 0) -1.0 else 1.0)
        return pose to facing
    }

    fun fire() {
        if (!playing || ammo <= 0) return
        ammo -= 1
        if (!hasFired) { hasFired = true; armDelay = armDelay0 }   // start the calm-then-armed clock
        recoil = 1.0; muzzle = 0.09; shakeT0 = nowSec()
        SoundManager.tap(); Haptics.tap()
        // The world point under the reticle's red dot, as drawn: the sway moves the reticle, and a
        // follow-up shot during the kick sees the scene still lifted by the recoil.
        val sx = aimX + swayX()
        val sy = aimY + swayY() + recoil * 0.02 * VIEW_H
        // A hit only if that dot touches the soldier's drawn body (limbs, vest, helmeted head).
        val dot = 2.0 / (max(1.0, areaH) / VIEW_H)          // the dot's 2 pt radius, in world units
        val idx = targets.indexOfFirst { t ->
            val (pose, facing) = figure(t)
            SNArt.touches(0.5 + (sx - t.x) / TARGET_H * facing, 0.97 + (sy - t.y) / TARGET_H, pose, dot / TARGET_H)
        }
        val now = nowSec()
        if (idx >= 0) {
            val t = targets[idx]
            bursts.add(Burst(t.x, t.y - TARGET_H / 2, rgb(0.95, 0.3, 0.25), true, now, burstSeed++))
            bursts.add(Burst(t.x, t.y - TARGET_H / 2, BananaTheme.banana, false, now, burstSeed++))
            downed.add(Down(t.x, t.y, t.dir, now))
            targets.removeAt(idx)
            if (targets.isEmpty()) { win(); return }
        } else {
            // Miss: a puff of dust; once armed, the nearest soldier is startled into aiming.
            bursts.add(Burst(sx, sy, gray(0.85), false, now, burstSeed++))
            val ni = targets.indices.minByOrNull { abs(sx - targets[it].x) }
            if (armed && ni != null && !targets[ni].aiming && abs(sx - targets[ni].x) < 0.22) raiseWeapon(targets[ni])
        }
        if (ammo <= 0 && targets.isNotEmpty()) fail()     // out of ammo with work left → over
    }

    private fun win() {
        if (!playing) return
        playing = false
        Haptics.success(); SoundManager.tap()
        onWin()
    }

    private fun fail() {
        if (!playing) return
        playing = false
        Haptics.warning(); SoundManager.error()
        onFail()
    }

    private fun strideList(from: Double, through: Double, by: Double): List<Double> {
        val out = mutableListOf<Double>()
        var i = 0
        while (from + i * by <= through + 1e-9) { out.add(from + i * by); i++ }
        return out
    }
}

@Composable
private fun SniperView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val world = remember { SniperWorld(level).also { it.setup() } }
    world.onWin = onWin; world.onFail = onFail
    var demoTick by remember { mutableIntStateOf(0) }
    var demoFire by remember { mutableStateOf(false) }
    val tick by rememberFrameLoop { dt -> if (!isDemo) world.step(dt) }

    LaunchedEffect(Unit) {
        if (!isDemo) return@LaunchedEffect
        suspend fun wait(dur: Double) {
            repeat(max(1, (dur / 0.016).toInt())) { world.tickAmbient(0.016); demoTick++; delay(16) }
        }
        suspend fun panTo(gx: Double, gy: Double, dur: Double) {
            val sx = world.aimX; val sy = world.aimY
            val steps = max(1, (dur / 0.016).toInt())
            for (k in 1..steps) {
                val f = 0.5 - 0.5 * cos(PI * k / steps)        // ease in-out
                world.aimX = sx + (gx - sx) * f; world.aimY = sy + (gy - sy) * f
                world.tickAmbient(0.016); demoTick++
                delay(16)
            }
        }
        suspend fun shoot() { demoFire = true; world.fire(); wait(0.18); demoFire = false }
        // Pan onto each stationary soldier and fire the real hitscan (exact under the reticle).
        while (isActive) {
            world.demoSetup()
            val gy = GROUND_V - TARGET_H / 2
            wait(0.6)
            world.targets.firstOrNull()?.let { panTo(it.x, gy, 0.85) }
            wait(0.22); shoot(); wait(0.7)
            world.targets.firstOrNull()?.let { panTo(it.x, gy, 0.85) }
            wait(0.22); shoot(); wait(1.3)       // the last shot wins; hold on the cleared vista
        }
    }

    val u = LocalDensity.current.density.toDouble()
    BoxWithConstraints(
        Modifier.fillMaxSize().graphicsLayer {
            // Shake once per shot or hit (PixelFX screenShake: 5 pt, three swings over 0.35 s).
            val t = nowSec() - world.shakeT0
            if (t in 0.0..0.35) {
                val k = sin(t / 0.35 * PI * 3)
                translationX = (5 * density * k).toFloat(); translationY = (5 * 0.6 * density * k).toFloat()
            }
        }
    ) {
        world.areaW = constraints.maxWidth / u; world.areaH = constraints.maxHeight / u
        // The vista, the soldiers, the scope and its effects: one Canvas, in points. Below the HUD and
        // FIRE, so a drag anywhere else pans.
        var last by remember { mutableStateOf(P(0.0, 0.0)) }
        Canvas(
            Modifier.fillMaxSize().then(if (isDemo) Modifier else Modifier.touchDrag(
                onStart = { p -> last = p },
                onMove = { _, p -> world.pan((p.x - last.x) / u, (p.y - last.y) / u); last = p },
                onEnd = { _, _ -> }))
        ) {
            tick; demoTick
            val now = nowSec()
            // The scene kicks up with the recoil and jitters sideways, inside the round lens.
            val jx = world.recoil * rnd(-3.0, 3.0)
            val jy = -world.recoil * (size.height / u) * 0.02
            val W = size.width.toDouble(); val H = size.height.toDouble()
            val lens = androidx.compose.ui.graphics.Path().apply {
                val r = min(W, H) / 2
                addOval(androidx.compose.ui.geometry.Rect((W / 2 - r).toFloat(), (H / 2 - r).toFloat(), (W / 2 + r).toFloat(), (H / 2 + r).toFloat()))
            }
            clipPath(lens) {
                translate((jx * u).toFloat(), (jy * u).toFloat()) {
                    inPoints { w, h -> with(SNArt) { scene(world, w, h, now) } }
                    // Bursts ride the vista (world-anchored), drawn in pixels by the shared helper.
                    val s = H / VIEW_H
                    world.bursts.removeAll { now - it.t0 > 0.6 }
                    for (b in world.bursts) {
                        val x = W / 2 + (b.wx - world.aimX) * s; val y = H / 2 + (b.wy - world.aimY) * s
                        particleBurst(x, y, now - b.t0, b.color, if (b.big) 20 else 10, if (b.big) 70.0 else 34.0, 18.0, b.seed)
                    }
                }
            }
            inPoints { w, h -> with(SNArt) { overlay(world, w, h) } }
        }
        tick; demoTick
        Hud(world.ammo0, world.ammo, world.maxHP, world.hp, world.targets.size, if (world.timeLimit > 0) world.timeLeft / world.timeLimit else 0.0)
        FireKey(demoFire, !isDemo, Modifier.align(Alignment.BottomEnd).padding(end = 20.dp, bottom = 16.dp)) { world.fire() }
    }
}

/** Rounds left, blood drops, soldiers left, and the clock. */
@Composable
private fun Hud(ammo0: Int, ammo: Int, maxHP: Int, hp: Int, left: Int, frac: Double) {
    Column(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 18.dp).padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Canvas(Modifier.width((max(1, ammo0) * 7).dp).height(18.dp)) { inPoints { w, h -> with(SNArt) { ammoBelt(w, h, max(1, ammo0), ammo) } } }
            Spacer(Modifier.weight(1f))
            Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                for (i in 0 until max(1, maxHP)) {
                    Icon(if (i < hp) Icons.Filled.WaterDrop else Icons.Outlined.WaterDrop, null,
                        tint = if (i < hp) rgb(0.92, 0.16, 0.16) else Color.White.op(0.25), modifier = Modifier.size(16.dp))
                }
            }
            Spacer(Modifier.weight(1f))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Canvas(Modifier.size(16.dp)) { inPoints { w, h -> with(SNArt) { headIcon(w, h) } } }
                Text("$left", style = ts(16.0, FontWeight.Black))
            }
        }
        TimeBar(frac, Modifier.fillMaxWidth().padding(horizontal = 50.dp).padding(top = 2.dp).height(4.dp),
            fill = if (frac < 0.25) rgb(1.0, 0.3, 0.25) else gray(0.85), track = Color.White.op(0.15))
    }
}

/** FIRE: a red trigger key with a crosshair, bottom-right so it clears the page's skip chevron. */
@Composable
private fun FireKey(lit: Boolean, enabled: Boolean, modifier: Modifier, onFire: () -> Unit) {
    Box(
        modifier.size(96.dp, 56.dp).scale(if (lit) 0.9f else 1f)
            .clickable(remember { androidx.compose.foundation.interaction.MutableInteractionSource() }, null, enabled = enabled, onClick = onFire),
        contentAlignment = Alignment.Center
    ) {
        Canvas(Modifier.fillMaxSize()) { inPoints { w, h -> with(SNArt) { fireKey(w, h, lit) } } }
        Icon(Icons.Filled.GpsFixed, null, tint = Color.White, modifier = Modifier.size(28.dp))
    }
}
