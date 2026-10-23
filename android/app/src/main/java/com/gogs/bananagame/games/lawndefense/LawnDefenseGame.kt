package com.gogs.bananagame.games.lawndefense

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/** Reflex — Lawn Defense (iOS LawnDefenseGame.swift + LawnDefenseArt.swift + LawnDefenseBosses.swift). */
object LawnDefenseGame {
    val definition = GameDefinition(
        id = "lawn-defense",
        title = "Lawn Defense",
        genre = Genre.REFLEX,
        manual = GameManual(
            bullets = listOf(
                "Tap a seed packet, then a lawn tile to plant it. Tap the falling suns to pay for plants.",
                "Sunflowers make sun. Shooters fire down their lane: frost slows, corn fires twice, melons lob over shields. Walnuts block, peels trip, flytraps gulp, cherries and chilis blast.",
                "Every world ends with a boss: knock its health bar down while it wrecks your lawn.",
                "Each lane's lawn mower saves it once. A zombie that reaches the house sends you back to level 1.",
            ),
            bulletsVI = listOf(
                "Chạm một gói hạt, rồi chạm ô cỏ để trồng. Chạm những mặt trời rơi xuống để có tiền trồng cây.",
                "Hướng dương tạo mặt trời. Cây bắn bắn dọc hàng: việt quất băng làm chậm, bắp bắn hai phát, dưa hấu ném qua khiên. Óc chó chặn đường, vỏ chuối làm trượt ngã, cây bắt ruồi nuốt chửng, anh đào và ớt nổ tung.",
                "Mỗi thế giới kết thúc bằng một trùm: hạ hết thanh máu của nó khi nó phá bãi cỏ của bạn.",
                "Máy cắt cỏ ở mỗi hàng cứu bạn một lần. Zombie nào vào tới nhà sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> LawnDefenseView(level, onWin, onFail) }
    )

    /** The manual demo's world: the backyard on a fixed seed with three lanes and a short horde. */
    fun demoWorld(): LDWorld {
        val p = LDParams.level(1)
        p.rows = listOf(1, 2, 3)
        p.packets = listOf(LDPlantKind.SUNFLOWER, LDPlantKind.PEASHOOTER, LDPlantKind.POPPER, LDPlantKind.PEEL, LDPlantKind.CHERRY)
        val w = LDWorld(p, 7uL)
        w.schedule = mutableListOf(LDSpawn(0.7, 2, LDZombieKind.NORMAL), LDSpawn(1.3, 1, LDZombieKind.NORMAL), LDSpawn(1.9, 3, LDZombieKind.FLAG))
        w.sun = 225
        w.skyTimer = 1.2
        var id = 100
        for (r in p.rows) {
            w.plants += LDPlant(id, LDPlantKind.SUNFLOWER, r, 0, LDPlantKind.SUNFLOWER.bites, 1.6 + r * 0.7, -5.0); id++
            if (r != 2) for ((c, k) in listOf(1 to LDPlantKind.POPPER, 2 to LDPlantKind.PEASHOOTER)) {
                w.plants += LDPlant(id, k, r, c, k.bites, 0.4, -5.0); id++
            }
        }
        return w
    }
}

/** What the feedback watches between two ticks (iOS `Pulse`). */
private class Pulse(w: LDWorld) {
    val mowers = w.mowers.count { it.state == LDMower.READY }
    val boom = w.booms.lastOrNull()?.t ?: -1.0
    val blaze = w.blazes.lastOrNull()?.t ?: -1.0
    val crash = w.crashes.lastOrNull()?.t ?: -1.0
    val boss = w.boss != null
    val bossDown = w.boss?.died != null
}

private class LawnState(val level: Int) {
    var world = LDWorld(LDParams.level(level), 1uL)
    var playing = true
    var selected by mutableStateOf<LDPlantKind?>(null)
    var shakeT0 = -10.0
    var demoFinger: P? = null
    var demoTapT0 = -10.0
    var demoPacket by mutableStateOf<LDPlantKind?>(null)
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    /** One tick of the real world plus the sounds, the shakes and the outcome. */
    fun advance(dt: Double) {
        val before = Pulse(world)
        world.step(dt)
        val after = Pulse(world)
        if (after.mowers < before.mowers) { shakeT0 = nowSec(); SoundManager.error(); Haptics.warning() }
        if (after.boom > before.boom || after.blaze > before.blaze) { shakeT0 = nowSec(); Haptics.warning() }
        if (after.crash > before.crash) { shakeT0 = nowSec(); Haptics.tap() }
        if (after.boss && !before.boss) { shakeT0 = nowSec(); Haptics.warning() }
        if (after.bossDown && !before.bossDown) { shakeT0 = nowSec(); Haptics.success() }
        if (world.lost) fail() else if (world.won) win()
    }

    fun win() { if (!playing) return; playing = false; selected = null; SoundManager.tap(); Haptics.tap(); onWin() }
    fun fail() { if (!playing) return; playing = false; selected = null; SoundManager.error(); Haptics.warning(); onFail() }
}

@Composable
private fun LawnDefenseView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val st = remember {
        LawnState(level).also { if (!isDemo) it.world = LDWorld(LDParams.level(level), Random.nextLong().toULong() or 1uL) }
    }
    st.onWin = onWin; st.onFail = onFail
    var demoTick by remember { mutableIntStateOf(0) }
    val loop = rememberFrameLoop(running = !isDemo) { dt -> if (st.playing) st.advance(dt) }

    LaunchedEffect(Unit) {
        if (!isDemo) return@LaunchedEffect
        val dt = 1.0 / 60.0
        while (isActive) {
            st.world = LawnDefenseGame.demoWorld()
            st.selected = null; st.demoFinger = null; st.demoPacket = null
            st.playing = true
            val plan = mutableListOf(Triple(LDPlantKind.POPPER, 2, 1))
            var pressT = -1.0
            var frames = 0
            var bombed = false
            while (isActive && !st.world.won && !st.world.lost && frames < 60 * 30) {
                val w = st.world
                if (w.boss == null && w.t >= 2.2) {
                    w.boss = LDBoss(LDBossKind.GROUNDSKEEPER, 16.0, 16.0, 2, 2.0, LDWorld.COLS + 0.9).also { it.arrivedAt = w.t }
                }
                val landed = w.suns.firstOrNull { it.y >= it.landY && w.t - it.born > 0.9 }
                val b = w.boss
                if (landed != null) {
                    st.demoFinger = P(landed.x, landed.y); st.demoTapT0 = nowSec()
                    w.collect(landed.id)
                } else if (!bombed && b != null && b.mode == LDBossMode.WALKING && b.x < 6.4 && w.canPlant(LDPlantKind.CHERRY)) {
                    if (st.demoPacket != LDPlantKind.CHERRY) { st.demoPacket = LDPlantKind.CHERRY; pressT = w.t }
                    else if (w.t - pressT > 0.45) {
                        val col = max(0, min(LDWorld.COLS - 1, floor(b.x - 0.6).toInt()))
                        st.demoFinger = P(col + 0.5, b.row + 0.55); st.demoTapT0 = nowSec()
                        w.plant(LDPlantKind.CHERRY, b.row, col)
                        st.demoPacket = null
                        bombed = true
                    }
                } else if (plan.isNotEmpty()) {
                    val (kind, row, col) = plan.first()
                    if (st.demoPacket == null && w.t > 0.3 && w.canPlant(kind)) { st.demoPacket = kind; pressT = w.t }
                    else if (st.demoPacket == kind && w.t - pressT > 0.5) {
                        st.demoFinger = P(col + 0.5, row + 0.55); st.demoTapT0 = nowSec()
                        w.plant(kind, row, col)
                        st.demoPacket = null
                        plan.removeAt(0)
                    }
                }
                w.step(dt)
                frames++
                demoTick++
                delay(16)
            }
            st.demoFinger = null
            repeat(80) { if (!isActive) return@LaunchedEffect; demoTick++; delay(16) }
        }
    }

    val tickState: State<Long> = loop
    val scene = st.world.params.scene
    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp)
            .graphicsLayer {
                tickState.value
                val t = nowSec() - st.shakeT0
                if (t in 0.0..0.35) {
                    val k = sin(t / 0.35 * PI * 3)
                    translationX = (5 * density * k).toFloat(); translationY = (5 * 0.6 * density * k).toFloat()
                }
            }
            .clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .drawBehind { LDWorlds.backdrop(this, scene) },
        verticalArrangement = Arrangement.spacedBy(if (isDemo) 4.dp else 8.dp)
    ) {
        SeedBar(st, isDemo, tickState, demoTick)
        Lawn(st, isDemo, tickState, demoTick, Modifier.fillMaxWidth().weight(1f).padding(horizontal = if (isDemo) 4.dp else 6.dp))
        Canvas(Modifier.fillMaxWidth().height(if (isDemo) 14.dp else 22.dp).padding(horizontal = if (isDemo) 40.dp else 56.dp)) {
            tickState.value; demoTick
            val w = st.world
            val b = w.boss
            if (b != null) bossMeter(b, w.t)
            else {
                val n = w.schedule.size
                val rushAt = if (n == 0) 1.0 else (n - min(w.params.finalWave, n)).toDouble() / n
                flagMeter(w.progress, rushAt, w.params.boss)
            }
        }
        Spacer(Modifier.height(if (isDemo) 2.dp else 2.dp))
    }
}

@Composable
private fun SeedBar(st: LawnState, isDemo: Boolean, tick: State<Long>, demoTick: Int) {
    tick.value; demoTick
    val w = st.world
    val scene = w.params.scene
    val packets = w.params.packets
    val perRow = if (packets.size > 6) (packets.size + 1) / 2 else max(1, packets.size)
    val lines = packets.chunked(perRow)
    val shape = RoundedCornerShape(10.dp)
    Row(
        Modifier.padding(horizontal = if (isDemo) 8.dp else 10.dp).padding(top = if (isDemo) 6.dp else 10.dp).fillMaxWidth()
            .clip(shape).drawBehind { LDWorlds.seedBar(this, scene) }.border(2.dp, LDLook.of(scene).barEdge, shape)
            .padding(horizontal = if (isDemo) 6.dp else 8.dp, vertical = if (isDemo) 4.dp else 6.dp),
        horizontalArrangement = Arrangement.spacedBy(if (isDemo) 5.dp else 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.width(if (isDemo) 46.dp else 58.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Canvas(Modifier.size(if (isDemo) 28.dp else 40.dp, if (isDemo) 26.dp else 38.dp)) {
                LDZombies.sun(this, size.width / 2.0, size.height / 2.0, min(size.width, size.height) * 0.36, w.t)
            }
            Text("${w.sun}", style = ts(if (isDemo) 13.0 else 17.0, FontWeight.Black, rgb(0.25, 0.15, 0.05)), maxLines = 1, softWrap = false,
                modifier = Modifier.background(rgb(0.96, 0.9, 0.72), RoundedCornerShape(50)).padding(horizontal = 6.dp))
        }
        Column(verticalArrangement = Arrangement.spacedBy(if (isDemo) 4.dp else 5.dp)) {
            for (line in lines) Row(horizontalArrangement = Arrangement.spacedBy(if (isDemo) 4.dp else 6.dp)) {
                for (kind in line) {
                    val ready = w.canPlant(kind)
                    val charge = w.recharge[kind.ordinal] / kind.recharge
                    val picked = st.selected == kind || (isDemo && st.demoPacket == kind)
                    PacketFace(kind, ready, charge, picked, isDemo) {
                        if (!st.playing || isDemo) return@PacketFace
                        if (st.selected == kind) st.selected = null
                        else if (st.world.canPlant(kind)) { st.selected = kind; SoundManager.tap() }
                        else SoundManager.error()
                    }
                }
            }
        }
        Spacer(Modifier.weight(1f))
    }
}

/** A seed packet: the plant on a pale card with its price; greyed while it recharges or can't be afforded. */
@Composable
private fun PacketFace(kind: LDPlantKind, ready: Boolean, charge: Double, picked: Boolean, isDemo: Boolean, onTap: () -> Unit) {
    val (src, pressed) = rememberPressed()
    val sc by animateFloatAsState(if (pressed.value) 0.94f else if (picked) 1.06f else 1f, tween(100), label = "pk")
    val shape = RoundedCornerShape(6.dp)
    Box(
        Modifier.size(if (isDemo) 38.dp else 50.dp, if (isDemo) 48.dp else 60.dp)
            .offset(y = if (picked) (-2).dp else 0.dp).scale(sc)
            .clickable(src, null, enabled = !isDemo, onClick = onTap)
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val u = density.toDouble()
            val w = size.width.toDouble(); val h = size.height.toDouble()
            rrect(0.0, 0.0, w, h, 6 * u, vgrad(listOf(rgb(0.98, 0.95, 0.8), rgb(0.88, 0.82, 0.62)), 0.0, h))
            val ix = 4 * u; val iy = 4 * u; val iw = w - 8 * u; val ih = h - 20 * u
            rrect(ix, iy, iw, ih, 4 * u, rgb(0.62, 0.82, 0.5))
            at(ix, iy) { LDPlants.icon(this, kind, iw / 2, ih * 0.95, min(iw, ih) * 0.95) }
        }
        Text("${kind.cost}", style = ts(12.0, FontWeight.Black, rgb(0.2, 0.12, 0.04)), modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 1.dp))
        if (!ready) {
            Canvas(Modifier.fillMaxSize().clip(shape)) {
                val h = size.height.toDouble(); val w = size.width.toDouble()
                val top = h * min(1.0, max(0.0, charge))
                rect(0.0, 0.0, w, top, Color.Black.op(0.5))
                rect(0.0, top, w, h - top, Color.Black.op(0.28))
            }
        }
        Box(Modifier.fillMaxSize().border(if (picked) 3.dp else 2.dp, if (picked) BananaTheme.banana else rgb(0.2, 0.36, 0.1), shape))
    }
}

@Composable
private fun Lawn(st: LawnState, isDemo: Boolean, tick: State<Long>, demoTick: Int, modifier: Modifier) {
    val handP = rememberHand()
    Box(modifier) {
        val scene = st.world.params.scene
        val rowsInPlay = st.world.params.rows
        val shown = if (isDemo) rowsInPlay else listOf(0, 1, 2, 3, 4)
        Canvas(Modifier.fillMaxSize()) { LDWorlds.lawn(this, scene, rowsInPlay, shown) }
        Canvas(
            Modifier.fillMaxSize().then(if (isDemo) Modifier else Modifier.tapIn { p, w, h -> tapLawn(st, p, LDLayout(w, h, shown)) })
        ) {
            tick.value; demoTick
            val w = st.world
            val lay = LDLayout(size.width.toDouble(), size.height.toDouble(), shown)
            scene(w, lay, st.selected ?: (if (isDemo) st.demoPacket else null))
            val f = st.demoFinger
            if (isDemo && f != null) {
                val p = lay.point(f.x, f.y)
                tapRipple(p.x, p.y, nowSec() - st.demoTapT0)
                val hs = lay.cellW * 0.7 * 1.25
                hand(handP, p.x + lay.cellW * 0.3 - hs * 0.35, p.y + lay.cellW * 0.42 - hs * 0.4, hs)
            }
        }
    }
}

private fun tapLawn(st: LawnState, loc: P, lay: LDLayout) {
    if (!st.playing) return
    val w = st.world
    // Suns sit on top: a tap near one picks it up.
    val s = w.suns.minByOrNull { val q = lay.point(it.x, it.y); hypot(q.x - loc.x, q.y - loc.y) }
    if (s != null) {
        val q = lay.point(s.x, s.y)
        if (hypot(q.x - loc.x, q.y - loc.y) < lay.cellW * 0.62) {
            if (w.collect(s.id)) { SoundManager.tap(); Haptics.tap() }
            return
        }
    }
    val kind = st.selected ?: return
    val tl = lay.tile(loc.x, loc.y)
    if (w.plant(kind, floor(tl.y).toInt(), floor(tl.x).toInt())) {
        st.selected = null
        SoundManager.tap(); Haptics.tap()
    } else SoundManager.error()
}

// The live scene (iOS LDLawnArt.scene / sprites / meters).

private fun DrawScope.scene(w: LDWorld, lay: LDLayout, selected: LDPlantKind?) {
    val u = density.toDouble()
    val cw = lay.cellW; val ch = lay.cellH
    if (selected != null) {
        val hint = Path()
        for (r in w.params.rows) {
            if (r !in lay.rows) continue
            for (c in 0 until LDWorld.COLS) {
                if (w.plantAt(r, c) != null || w.graveAt(r, c) != null || w.bossCovers(r, c)) continue
                val p = lay.point(c.toDouble(), r.toDouble())
                hint.rrectD(p.x + 3 * u, p.y + 3 * u, cw - 6 * u, ch - 6 * u, 6 * u)
            }
        }
        drawPath(hint, Color.White.op(0.13))
    }
    w.boss?.let { LDBossArt.underlay(this, it, w, lay) }
    tinted(LDLook.of(w.params.scene).sprite, 0.0) { sprites(w, lay) }
    for (p in w.peas) if (p.row in lay.rows) { val q = lay.point(p.x, p.row + 0.36); LDZombies.pea(this, q.x, q.y, cw * 0.11, p.shot, w.t) }
    for (s in w.splats) if (s.row in lay.rows) { val q = lay.point(s.x, s.row + 0.36); LDZombies.splat(this, q.x, q.y, cw * 0.12, w.t - s.t, s.shot) }
    for (b in w.booms) if (b.row in lay.rows) { val q = lay.point(b.col + 0.5, b.row + 0.5); LDFlytrap.boom(this, q.x, q.y, cw, w.t - b.t) }
    for (f in w.blazes) if (f.row in lay.rows) LDFlytrap.blaze(this, lay, f.row, w.t - f.t)
    for (c in w.crashes) if (c.row in lay.rows) { val q = lay.point(c.col + 0.5, c.row + 0.85); LDFlytrap.crash(this, q.x, q.y, cw, w.t - c.t) }
    for (l in w.lobs) {
        val p = min(1.0, (w.t - l.t0) / LDWorld.LOB_TIME)
        val a = lay.point(l.x0, l.row + 0.3); val b = lay.point(l.x1, l.row + 0.4)
        with(LDPlants) { melonBall(a.x + (b.x - a.x) * p, a.y + (b.y - a.y) * p - sin(p * PI) * ch * 1.1, cw * 0.13) }
    }
    w.boss?.let { LDBossArt.overlay(this, it, w, lay) }
    for (s in w.suns) {
        val fade = if (s.life < 1.5) (if ((s.life * 8).toInt() % 2 == 0) 0.45 else 1.0) else 1.0
        val q = lay.point(s.x, s.y)
        LDZombies.sun(this, q.x, q.y, cw * 0.3, w.t + s.id, fade)
    }
}

/** Mowers, graves, plants, rolling balls, zombies and the boss, lane by lane from the back. */
private fun DrawScope.sprites(w: LDWorld, lay: LDLayout) {
    val cw = lay.cellW; val ch = lay.cellH
    val scene = w.params.scene
    val ps = min(cw * 1.05, ch * 0.74)
    val zh = min(ch * 1.22, cw * 1.9)
    val boss = w.boss
    val bossBottom: Int? = boss?.let { b -> if (b.kind.span > 1) ceil(b.y - 0.001).toInt() + b.kind.span - 1 else -1 }
    for (r in lay.rows) {
        val m = w.mowers[r]
        when (m.state) {
            LDMower.READY -> { val q = lay.point(-0.36, r + 0.66); LDZombies.mower(this, q.x, q.y, cw * 0.9) }
            LDMower.RUNNING -> { val q = lay.point(m.x, r + 0.66); LDZombies.mower(this, q.x, q.y, cw * 0.9) }
            else -> {}
        }
        for (gv in w.graves) if (gv.row == r) { val q = lay.point(gv.col + 0.5, r + 0.9); LDFlytrap.grave(this, q.x, q.y, ps, gv.hp / 8, w.t - gv.born) }
        for (p in w.plants) {
            if (p.row != r) continue
            val b = lay.point(p.col + 0.5, r + 0.9)
            val seed = p.id * 1.7
            val wince = w.t - p.bitten < 0.25
            val t = if (p.frozen > 0) p.planted else w.t
            with(LDPlants) {
                when (p.kind) {
                    LDPlantKind.SUNFLOWER -> sunflower(b.x, b.y, ps, t, seed, wince)
                    LDPlantKind.PEASHOOTER -> peashooter(b.x, b.y, ps, t, seed, w.t - p.fired)
                    LDPlantKind.POPPER -> popper(b.x, b.y, ps, t, seed, w.t - p.fired)
                    LDPlantKind.FROST -> frostBerry(b.x, b.y, ps, t, seed, w.t - p.fired)
                    LDPlantKind.LOBBER -> lobber(b.x, b.y, ps, t, seed, w.t - p.fired)
                    LDPlantKind.WALLNUT -> wallnut(b.x, b.y, ps, p.hp / LDPlantKind.WALLNUT.bites, wince)
                    LDPlantKind.PEEL -> peel(b.x, b.y, ps, if (p.timer <= 0) 1.0 else 1 - p.timer / LDWorld.PEEL_ARM, w.t)
                    LDPlantKind.FLYTRAP -> {
                        val prey = w.zombies.firstOrNull { it.eaten && it.row == r && it.died == p.gulp }?.let { z ->
                            val q = lay.point(z.x + 0.3, r + 0.92)
                            LDPrey(z, q, if (z.kind == LDZombieKind.IMP) zh * 0.66 else zh, scene)
                        }
                        LDFlytrap.flytrap(this@sprites, b.x, b.y, ps, t, seed, p.chewing, p.gulp, prey)
                    }
                    LDPlantKind.CHERRY -> LDFlytrap.cherry(this@sprites, b.x, b.y, ps, 1 - max(0.0, p.timer) / 1.1, w.t)
                    LDPlantKind.CHILI -> LDFlytrap.chili(this@sprites, b.x, b.y, ps, 1 - max(0.0, p.timer) / 0.8, w.t)
                }
            }
            if (p.frozen > 0) LDFlytrap.iceBlock(this, b.x, b.y, ps, p.frozen)
        }
        for (rl in w.rollers) {
            if (rl.row != r) continue
            val rr = cw * 0.42
            val c = lay.point(rl.x + 0.42, r + 0.9)
            ellipse(c.x, c.y, rr * 0.95, rr * 0.25, Color.Black.op(0.25))
            LDFlytrap.roller(this, c.x, c.y - rr, rr, rl.kind, -rl.x * 2.4, w.t)
        }
        val walkers = mutableListOf<Pair<Double, () -> Unit>>()
        for (z in w.zombies) if (z.row == r) walkers += z.x to {
            val q = lay.point(z.x + 0.3, r + 0.92)
            LDZombies.zombie(this, q.x, q.y, zh, z, w.t, scene, cw)
        }
        if (boss != null && boss.kind.span == 1 && boss.y.roundAway() == r) walkers += boss.x to { LDBossArt.draw(this, boss, w, lay) }
        for (item in walkers.sortedByDescending { it.first }) item.second()
        if (boss != null && boss.kind.span > 1 && bossBottom == r) LDBossArt.draw(this, boss, w, lay)
    }
    if (boss != null && boss.kind.span > 1 && bossBottom != null && bossBottom !in lay.rows) LDBossArt.draw(this, boss, w, lay)
    for (d in w.drops) {
        val p = min(1.0, (w.t - d.t0) / (d.lands - d.t0))
        val a = lay.point(d.fromX, d.row + 0.2); val b = lay.point(d.x + 0.3, d.row + 0.92)
        val cx = a.x + (b.x - a.x) * p; val cy = a.y + (b.y - a.y) * p - sin(p * PI) * ch * 1.6
        rotateRad((p * 4 * PI).toFloat(), off(cx, cy)) {
            val fake = LDZombie(d.id, LDZombieKind.IMP, d.row, d.x, 3.0, 0.0, 0.0, 1.0, -9.0)
            LDZombies.zombie(this, cx, cy + zh * 0.33, zh, fake, w.t, scene, cw)
        }
    }
}

/** The flag meter: a zombie head creeps along as the horde arrives; the flag marks the final rush. */
private fun DrawScope.flagMeter(progress: Double, rushAt: Double, boss: LDBossKind?) {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    val bx = h * 0.6; val by = h * 0.22; val bw = w - h * 1.1; val bh = h * 0.56
    rrect(bx, by, bw, bh, bh / 2, rgb(0.16, 0.1, 0.05))
    val fx0 = bx + bw - bw * progress
    rrect(fx0, by, bw * progress, bh, bh / 2, vgrad(listOf(rgb(0.55, 0.9, 0.2), rgb(0.25, 0.6, 0.08)), by, by + bh))
    rrectStroke(bx, by, bw, bh, bh / 2, rgb(0.55, 0.38, 0.18), 1.5 * u)
    val fx = bx + bw - bw * rushAt
    line(fx, by + bh, fx, 0.0, gray(0.85), 1.2 * u, androidx.compose.ui.graphics.StrokeCap.Butt)
    drawPath(polyPath(fx, 0.0, fx + h * 0.6, h * 0.12, fx, h * 0.32), rgb(0.86, 0.14, 0.1))
    if (boss != null) LDBossArt.icon(this, boss, bx - h * 0.05, h / 2, h * 0.48)
    val hx = bx + bw - bw * progress
    val hr = h * 0.48; val hy = h / 2
    circle(hx, hy, hr, rgb(0.58, 0.66, 0.5))
    circleStroke(hx, hy, hr, LDPlants.ink, 1.2 * u)
    circle(hx - hr * 0.35, hy - hr * 0.15, hr * 0.3, Color.White)
    circle(hx - hr * 0.38, hy - hr * 0.12, hr * 0.1, LDPlants.ink)
    rect(hx - hr * 0.5, hy + hr * 0.35, hr * 0.6, hr * 0.18, LDPlants.ink)
}

/** The boss's health bar: red draining to the left, its face at the end. */
private fun DrawScope.bossMeter(b: LDBoss, t: Double) {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    val bx = h * 0.7; val by = h * 0.18; val bw = w - h * 0.9; val bh = h * 0.64
    rrect(bx, by, bw, bh, bh / 2, rgb(0.16, 0.05, 0.05))
    val k = max(0.0, b.hp / b.maxHP)
    val flash = t - b.hit < 0.08
    if (k > 0) rrect(bx, by, bw * k, bh, bh / 2, vgrad(if (flash) listOf(Color.White, rgb(1.0, 0.7, 0.6)) else listOf(rgb(1.0, 0.42, 0.3), rgb(0.75, 0.08, 0.08)), by, by + bh))
    rrectStroke(bx, by, bw, bh, bh / 2, rgb(0.95, 0.8, 0.4), 1.5 * u)
    LDBossArt.icon(this, b.kind, bx - h * 0.05, h / 2, h * 0.48)
}

@Suppress("unused") private val keepBrush: Brush? = null
@Suppress("unused") private fun keep() = mutableDoubleStateOf(0.0)
