package com.gogs.bananagame.games.rocknrocket

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
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
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Reflex — Rock 'n' Rocket (iOS RockNRocketGame.swift, id "rock-n-rocket"): a top-down combat racer
 * in the Rock n' Roll Racing tradition. Three cars, three laps of a closed, curvy circuit: hold GAS,
 * steer ◄ ►, and FIRE rockets that spin a rival out for a second. Finish in front to win; come last or
 * run out the clock and it's back to level 1. On-screen buttons only, so it doesn't lock the feed.
 */
object RockNRocketGame {
    val definition = GameDefinition(
        id = "rock-n-rocket",
        title = "Rock 'n' Rocket",
        genre = Genre.REFLEX,
        manual = GameManual(
            bullets = listOf(
                "A top-down combat race: three laps around a closed circuit against two AI cars.",
                "Hold GAS and steer with ◄ ► through the corners.",
                "Tap FIRE to launch a rocket; land one on a rival and they spin out briefly.",
                "Finish the three laps in front to win; come last or time out and you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Đua chiến đấu nhìn từ trên: ba vòng quanh đường đua kín đấu với hai xe AI.",
                "Giữ GA và lái bằng ◄ ► qua các khúc cua.",
                "Chạm BẮN để phóng tên lửa; trúng một đối thủ khiến chúng xoay lộn một lúc.",
                "Về đích ba vòng ở phía trước để thắng; về chót hoặc hết giờ sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> RockNRocketView(level, onWin, onFail) }
    )
}

class RocketRace(val level: Int) {
    companion object {
        const val LAPS = 3
        const val MAX_SPEED = 0.30      // frac/sec
        const val ACCEL = 0.55
        const val COAST_DRAG = 0.22
        const val TURN_RATE = 2.7       // rad/sec at speed
        const val ROCKET_SPEED = 0.62
        const val CAR_RADIUS = 0.017    // half-size in min-dimension fractions (car-car bumps)
        const val N = 128               // centreline resolution
        val colors = listOf(BananaTheme.banana, rgb(0.9, 0.25, 0.28), rgb(0.30, 0.55, 0.95))
    }

    private val li = min(max(level, 1), 7) - 1
    val aiFactor = listOf(0.72, 0.79, 0.86, 0.93, 0.99, 1.04, 1.09)[li]
    val halfWidth = listOf(0.062, 0.058, 0.054, 0.050, 0.046, 0.042, 0.038)[li]
    val playerRockets = listOf(3, 3, 3, 2, 2, 1, 1)[li]
    val aiRockets = listOf(1, 2, 3, 3, 4, 5, 6)[li]
    val aiFireEvery = listOf(4.5, 4.0, 3.4, 2.9, 2.4, 2.0, 1.6)[li]
    /** Generous clock — the circuit is long and winding, so 3 laps take a while. */
    val timeLimit = 80.0

    class Car(
        val id: Int, var x: Double, var y: Double, var heading: Double, var speed: Double = 0.0,
        var lap: Int = 0, var idx: Int = 0, var lastIdx: Int = 0, var reachedHalf: Boolean = false,
        var spin: Double = 0.0, var rockets: Int, var fireCD: Double = 0.0,
        var bumpX: Double = 0.0, var bumpY: Double = 0.0, val color: Color, val isPlayer: Boolean,
    )
    class Rocket(var x: Double, var y: Double, val heading: Double, val vx: Double, val vy: Double, val owner: Int, var life: Double, var trailCD: Double = 0.0)
    class Burst(val x: Double, val y: Double, val color: Color, val big: Boolean, val t0: Double, val seed: Int)

    /**
     * A closed, long, curvy centreline: a low harmonic sets the big shape and higher ones add bends
     * (per-level shape). The radius stays positive, so the star-shaped loop never self-crosses.
     */
    val center: List<P> = run {
        val phases = listOf(
            doubleArrayOf(3.0, 4.0, 0.20, 0.17, 6.0, 0.10, 0.0), doubleArrayOf(4.0, 3.0, 0.24, 0.19, 7.0, 0.11, 0.6),
            doubleArrayOf(4.0, 5.0, 0.25, 0.21, 7.0, 0.12, 1.1), doubleArrayOf(5.0, 4.0, 0.27, 0.22, 8.0, 0.13, 0.3),
            doubleArrayOf(5.0, 6.0, 0.28, 0.24, 9.0, 0.13, 1.8), doubleArrayOf(6.0, 5.0, 0.30, 0.25, 9.0, 0.14, 0.9),
            doubleArrayOf(6.0, 7.0, 0.31, 0.27, 10.0, 0.15, 2.2),
        )
        val ph = phases[min(li, phases.size - 1)]
        val k1 = ph[0]; val k2 = ph[1]; val a1 = ph[2]; val a2 = ph[3]; val k3 = ph[4]; val a3 = ph[5]; val p = ph[6]
        val cx = 0.5; val cy = 0.50; val rx = 0.33; val ry = 0.28
        List(N) { i ->
            val t = i.toDouble() / N * 2 * PI
            val radx = rx * (1 + a1 * sin(k1 * t + p) + a3 * sin(k3 * t + p))
            val rady = ry * (1 + a2 * sin(k2 * t + p * 0.5) + a3 * sin(k3 * t + 1.7))
            P(cx + radx * cos(t), cy + rady * sin(t))
        }
    }

    var playing = true
    val cars = mutableListOf<Car>()
    val rockets = mutableListOf<Rocket>()
    val bursts = mutableListOf<Burst>()
    var steer = 0.0
    var gas = false
    var areaW = 0.0; var areaH = 0.0         // the play area, in points
    var timeLeft = timeLimit
    var animT = 0.0
    var shakeT0 = -10.0
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}
    private var burstSeed = 0

    val player get() = cars.firstOrNull { it.isPlayer }

    /** 1st / 2nd / 3rd: rivals on a later lap, or further round the same one. */
    val place: Int get() {
        val p = player ?: return 1
        return min(3, cars.count { !it.isPlayer && (it.lap > p.lap || (it.lap == p.lap && it.idx > p.idx)) } + 1)
    }

    /** A car on the centreline node `idx`, `lat` off it sideways, facing along the road. */
    private fun carAt(k: Int, idx: Int, lat: Double): Car {
        val si = ((idx % N) + N) % N
        val pa = center[si]; val pb = center[(si + 1) % N]
        val dx = pb.x - pa.x; val dy = pb.y - pa.y
        val dl = max(0.0001, hypot(dx, dy))
        return Car(k, pa.x - dy / dl * lat, pa.y + dx / dl * lat, atan2(dy, dx), idx = si, lastIdx = si,
            rockets = if (k == 0) playerRockets else aiRockets, fireCD = aiFireEvery, color = colors[k], isPlayer = k == 0)
    }

    /** Grid-start the three cars just behind the line, staggered two nodes apart on alternating sides. */
    fun setup() {
        cars.clear()
        for (k in 0 until 3) cars.add(carAt(k, N - 4 - k * 2, (if (k % 2 == 0) 1.0 else -1.0) * halfWidth * 0.45))
        rockets.clear(); bursts.clear()
        steer = 0.0; gas = false
        timeLeft = timeLimit; animT = 0.0; playing = true
    }

    /**
     * The manual clip: the closing stretch of level 1's final lap. The banana car on the lower-left bend,
     * red 14 nodes up the road and blue trailing; the AIs are "reloading" (no rockets).
     */
    fun demoSetup() {
        setup()
        cars.clear()
        cars.add(carAt(0, 44, 0.0).also { it.speed = 0.22 })
        cars.add(carAt(1, 58, -halfWidth * 0.35).also { it.speed = MAX_SPEED * aiFactor })
        cars.add(carAt(2, 36, halfWidth * 0.45).also { it.speed = MAX_SPEED * aiFactor })
        for (c in cars) { c.lap = LAPS - 1; c.reachedHalf = true; c.fireCD = 99.0; if (!c.isPlayer) c.rockets = 0 }
        gas = true
    }

    /**
     * One frame of the demo's autopilot: steer toward a point 7 nodes up the centreline (each press held
     * ≥5 frames), and fire once red is within 0.15 and dead ahead. Returns whether it fired.
     */
    fun demoDrive(frame: Int, lastSteer: IntArray, fired: Boolean): Boolean {
        val p = player ?: return false
        val tgt = center[(p.idx + 7) % N]
        val d = angleDiff(atan2(tgt.y - p.y, tgt.x - p.x), p.heading)
        val want = if (d > 0.10) 1.0 else if (d < -0.10) -1.0 else 0.0
        if (want != steer && frame - lastSteer[0] >= 5) { steer = want; lastSteer[0] = frame }
        if (fired) return false
        val red = cars.firstOrNull { it.id == 1 } ?: return false
        if (red.spin > 0) return false
        val dx = red.x - p.x; val dy = red.y - p.y
        if (hypot(dx, dy) < 0.15 && abs(angleDiff(atan2(dy, dx), p.heading)) < 0.10) { firePlayerRocket(); return true }
        return false
    }

    fun step(dt: Double) {
        if (!playing || center.size != N) return
        animT += dt
        for (c in cars) updateCar(c, dt)
        resolveCarCollisions()
        updateRockets(dt)
        // AI rocket fire.
        for ((i, c) in cars.withIndex()) {
            if (c.isPlayer) continue
            c.fireCD -= dt
            if (c.fireCD <= 0 && c.rockets > 0 && c.spin <= 0) {
                c.fireCD = aiFireEvery * rnd(0.8, 1.3)
                aiTarget(c)?.let { t ->
                    c.rockets -= 1
                    spawnRocket(i, atan2(t.y - c.y, t.x - c.x))
                }
            }
        }
        timeLeft -= dt
        if (timeLeft <= 0) { timeLeft = 0.0; fail() }
    }

    private fun updateCar(c: Car, dt: Double) {
        if (c.spin > 0) {
            c.spin -= dt
            c.heading += 11 * dt
            c.speed = max(0.0, c.speed - 0.9 * dt)
            advance(c, dt)
            return
        }
        val steerInput = if (c.isPlayer) steer else aiSteer(c)
        // Turn scales a little with speed so a stopped car doesn't pivot in place.
        val turnScale = min(1.0, 0.25 + c.speed / (MAX_SPEED * 0.6))
        c.heading += steerInput * TURN_RATE * dt * turnScale
        val vmax = if (c.isPlayer) MAX_SPEED else MAX_SPEED * aiFactor
        val accelerating = if (c.isPlayer) gas else true
        if (accelerating) c.speed += ACCEL * dt else c.speed -= COAST_DRAG * dt
        c.speed = min(vmax, max(0.0, c.speed))
        advance(c, dt)
    }

    private fun advance(c: Car, dt: Double) {
        // Drive along the heading plus any transient shove from a car-car bump (which decays).
        var nx = c.x + (cos(c.heading) * c.speed + c.bumpX) * dt
        var ny = c.y + (sin(c.heading) * c.speed + c.bumpY) * dt
        val decay = min(1.0, 7 * dt)
        c.bumpX -= c.bumpX * decay
        c.bumpY -= c.bumpY * decay
        // Keep the whole car on the tarmac: clamp its offset from the centreline to the track band
        // (in points, matching the drawn width) and scrub a little speed, never stopping it.
        if (areaW > 1 && areaH > 1) {
            val c0 = center[nearestIndex(nx, ny)]
            val minDim = min(areaW, areaH)
            val dxp = (nx - c0.x) * areaW; val dyp = (ny - c0.y) * areaH
            val distp = hypot(dxp, dyp)
            val maxp = halfWidth * minDim * 0.82
            if (distp > maxp && distp > 0.0001) {
                val k = maxp / distp
                nx = c0.x + (nx - c0.x) * k
                ny = c0.y + (ny - c0.y) * k
                c.speed = max(c.speed * 0.9, MAX_SPEED * 0.35)
            }
        }
        c.x = nx; c.y = ny
        // Lap tracking via centreline index crossings.
        val idx = nearestIndex(c.x, c.y)
        if (idx > N / 2) c.reachedHalf = true
        if (c.reachedHalf && c.lastIdx > N * 3 / 4 && idx < N / 4) {
            c.lap += 1
            c.reachedHalf = false
            if (c.isPlayer) { Haptics.tap(); SoundManager.tap() }
            if (c.lap >= LAPS) { if (c.isPlayer) win() else fail() }
        }
        c.lastIdx = idx
        c.idx = idx
    }

    /** Keep cars from overlapping and let them shove one another (round bodies, in points). */
    private fun resolveCarCollisions() {
        if (areaW <= 1 || areaH <= 1 || cars.size < 2) return
        val minPx = CAR_RADIUS * 2 * min(areaW, areaH)
        for (i in cars.indices) for (j in i + 1 until cars.size) {
            val a = cars[i]; val b = cars[j]
            val dxp = (b.x - a.x) * areaW; val dyp = (b.y - a.y) * areaH
            val distp = hypot(dxp, dyp)
            if (distp >= minPx || distp <= 0.0001) continue
            // Feedback only on the first frame of contact, so it doesn't machine-gun while they grind.
            val freshHit = hypot(a.bumpX, a.bumpY) < 0.02 && hypot(b.bumpX, b.bumpY) < 0.02
            val nxp = dxp / distp; val nyp = dyp / distp
            val overlap = minPx - distp
            val sx = nxp * overlap * 0.5; val sy = nyp * overlap * 0.5
            a.x -= sx / areaW; a.y -= sy / areaH
            b.x += sx / areaW; b.y += sy / areaH
            val nfx = b.x - a.x; val nfy = b.y - a.y
            val nl = max(0.0001, hypot(nfx, nfy))
            val ux = nfx / nl; val uy = nfy / nl
            val kick = 0.10 + 0.35 * (a.speed + b.speed)
            a.bumpX -= ux * kick; a.bumpY -= uy * kick
            b.bumpX += ux * kick; b.bumpY += uy * kick
            a.speed *= 0.9; b.speed *= 0.9
            if (freshHit) {
                shakeT0 = nowSec()
                if (a.isPlayer || b.isPlayer) { Haptics.tap(); SoundManager.tap() }
            }
        }
    }

    private fun updateRockets(dt: Double) {
        val now = nowSec()
        val it = rockets.iterator()
        while (it.hasNext()) {
            val r = it.next()
            r.x += r.vx * dt; r.y += r.vy * dt
            r.life -= dt
            r.trailCD -= dt
            if (r.trailCD <= 0) {
                r.trailCD = 0.06
                bursts.add(Burst(r.x, r.y, gray(0.7), false, now, burstSeed++))
            }
            if (r.life <= 0 || r.x < 0 || r.x > 1 || r.y < 0 || r.y > 1) { it.remove(); continue }
            // Hit any car that isn't the owner.
            val hit = cars.firstOrNull { c -> c.id != r.owner && c.spin <= 0 && hypot(c.x - r.x, c.y - r.y) < 0.024 }
            if (hit != null) {
                hit.spin = 1.0
                hit.speed *= 0.3
                bursts.add(Burst(r.x, r.y, rgb(1.0, 0.5, 0.2), true, now, burstSeed++))
                shakeT0 = now
                Haptics.warning(); SoundManager.error()
                it.remove()
            }
        }
    }

    fun firePlayerRocket() {
        if (!playing) return
        val pi = cars.indexOfFirst { it.isPlayer }
        if (pi < 0 || cars[pi].rockets <= 0 || cars[pi].spin > 0) return
        cars[pi].rockets -= 1
        spawnRocket(pi, cars[pi].heading)
        SoundManager.tap(); Haptics.tap()
    }

    /** Launched clear of the firer's own body (0.05 out), so a rocket can never hit its own car. */
    private fun spawnRocket(i: Int, heading: Double) {
        val c = cars[i]
        rockets.add(Rocket(c.x + cos(heading) * 0.05, c.y + sin(heading) * 0.05, heading,
            cos(heading) * ROCKET_SPEED, sin(heading) * ROCKET_SPEED, c.id, 1.6))
    }

    /** An AI picks the nearest rival within 0.4 to lob a rocket at. */
    private fun aiTarget(c: Car): Car? {
        var best: Car? = null
        var bestD = 0.4
        for (o in cars) {
            if (o.id == c.id) continue
            val d = hypot(o.x - c.x, o.y - c.y)
            if (d < bestD) { bestD = d; best = o }
        }
        return best
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

    /** Aim a few nodes ahead along the racing line. */
    private fun aiSteer(c: Car): Double {
        val target = center[(c.idx + max(4, N / 18)) % N]
        val d = angleDiff(atan2(target.y - c.y, target.x - c.x), c.heading)
        return max(-1.0, min(1.0, d * 2.5))
    }

    private fun angleDiff(a: Double, b: Double): Double {
        var d = a - b
        while (d > PI) d -= 2 * PI
        while (d < -PI) d += 2 * PI
        return d
    }

    private fun nearestIndex(x: Double, y: Double): Int {
        var best = 0
        var bestD = Double.MAX_VALUE
        for (i in 0 until N) {
            val dx = center[i].x - x; val dy = center[i].y - y
            val d = dx * dx + dy * dy
            if (d < bestD) { bestD = d; best = i }
        }
        return best
    }
}

@Composable
private fun RockNRocketView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val race = remember { RocketRace(level).also { it.setup() } }
    race.onWin = onWin; race.onFail = onFail
    var demoTick by remember { mutableIntStateOf(0) }
    var demoFire by remember { mutableIntStateOf(0) }      // demo: frames left on the FIRE press flash
    val tick by rememberFrameLoop { dt -> if (!isDemo) race.step(dt) }

    LaunchedEffect(Unit) {
        if (!isDemo) return@LaunchedEffect
        while (isActive) {
            race.demoSetup(); demoFire = 0
            delay(500)                                          // (also lets the area settle)
            var frame = 0
            val lastSteer = intArrayOf(-99)
            var fired = false
            while (isActive && race.playing && frame < 900) {
                frame++
                if (race.demoDrive(frame, lastSteer, fired)) { fired = true; demoFire = 8 }
                if (demoFire > 0) demoFire--
                race.step(1.0 / 60)
                demoTick++
                delay(16)
            }
            // Flag taken in 1st → the real win() ran (onWin is a no-op). Hold, then loop.
            race.steer = 0.0; race.gas = false; demoFire = 0
            delay(1300)
        }
    }

    val u = LocalDensity.current.density.toDouble()
    BoxWithConstraints(
        Modifier.fillMaxSize().clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp)).graphicsLayer {
            val t = nowSec() - race.shakeT0
            if (t in 0.0..0.35) {
                val k = sin(t / 0.35 * PI * 3)
                translationX = (6 * density * k).toFloat(); translationY = (6 * 0.6 * density * k).toFloat()
            }
        }
    ) {
        race.areaW = constraints.maxWidth / u; race.areaH = constraints.maxHeight / u
        // The circuit and its scenery never change during a race: cached. Cars, rockets and bursts on top.
        Canvas(Modifier.fillMaxSize().artBehind { w, h -> with(RKArt) { track(w, h, race.center, race.halfWidth, level) } }) {
            tick; demoTick
            val now = nowSec()
            inPoints { w, h -> with(RKArt) { race(race, w, h) } }
            race.bursts.removeAll { now - it.t0 > 0.6 }
            for (b in race.bursts) {
                particleBurst(b.x * size.width, b.y * size.height, now - b.t0, b.color, if (b.big) 18 else 9, if (b.big) 80.0 else 40.0, 10.0, b.seed)
            }
        }
        tick; demoTick
        val p = race.player
        Hud(min(RocketRace.LAPS, (p?.lap ?: 0) + 1), race.place, race.playerRockets, p?.rockets ?: 0,
            if (race.timeLimit > 0) race.timeLeft / race.timeLimit else 0.0, isDemo)
        Controls(race, isDemo, race.steer, race.gas, demoFire > 0, Modifier.align(Alignment.BottomCenter))
    }
}

/** A flag + lap count, a place medal and missile pips on a dark pill, and the clock. */
@Composable
private fun Hud(lap: Int, place: Int, total: Int, loaded: Int, frac: Double, isDemo: Boolean) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(
            Modifier.padding(horizontal = 8.dp).padding(top = 4.dp).fillMaxWidth()
                .background(Color.Black.op(0.35), RoundedCornerShape(50)).padding(horizontal = 18.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Canvas(Modifier.size(if (isDemo) 14.dp else 17.dp)) { inPoints { w, h -> with(RKArt) { flagIcon(w, h) } } }
                Text("$lap/${RocketRace.LAPS}", style = ts(if (isDemo) 13.0 else 16.0, FontWeight.Black))
            }
            Spacer(Modifier.weight(1f))
            val m = if (isDemo) 22.0 else 28.0
            Box(Modifier.size(m.dp), contentAlignment = Alignment.Center) {
                Canvas(Modifier.fillMaxSize()) { inPoints { w, h -> with(RKArt) { medal(w, h, place) } } }
                Text("$place", style = ts(16.0 * min(1.0, m / 28), FontWeight.Black, rgb(0.25, 0.16, 0.04)))
            }
            Spacer(Modifier.weight(1f))
            Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                for (i in 0 until max(1, total)) {
                    Canvas(Modifier.size(if (isDemo) 7.dp else 8.dp, if (isDemo) 14.dp else 17.dp)) {
                        inPoints { w, h -> with(RKArt) { rocketIcon(w, h, i < loaded) } }
                    }
                }
            }
        }
        if (!isDemo) {
            TimeBar(frac, Modifier.fillMaxWidth().padding(horizontal = 50.dp).height(4.dp),
                fill = if (frac < 0.25) rgb(1.0, 0.3, 0.25) else Color.White, track = Color.Black.op(0.35))
        }
    }
}

/** ◄ ► on the left; FIRE (tap) and GAS (hold) on the right. In the demo the held controls light up. */
@Composable
private fun Controls(race: RocketRace, isDemo: Boolean, steer: Double, gas: Boolean, fireLit: Boolean, modifier: Modifier) {
    val kw = if (isDemo) 50.dp else 62.dp; val kh = if (isDemo) 40.dp else 54.dp
    val gap = if (isDemo) 8.dp else 10.dp
    @Composable
    fun hold(face: RKArt.Face, color: Color, active: Boolean, onPress: (Boolean) -> Unit) {
        val lit = isDemo && active
        Box(
            Modifier.size(kw, kh).scale(if (lit) 0.9f else 1f)
                .then(if (isDemo) Modifier else Modifier.pressDown(onDown = { onPress(true) }, onUp = { onPress(false) }))
        ) { Canvas(Modifier.fillMaxSize()) { inPoints { w, h -> with(RKArt) { key(w, h, face, color, lit) } } } }
    }
    Row(modifier.fillMaxWidth().padding(horizontal = if (isDemo) 12.dp else 20.dp).padding(bottom = if (isDemo) 6.dp else 10.dp),
        verticalAlignment = Alignment.Bottom) {
        Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
            hold(RKArt.Face.LEFT, gray(0.24), steer < 0) { d -> if (race.playing) race.steer = if (d) -1.0 else (if (race.steer < 0) 0.0 else race.steer) }
            hold(RKArt.Face.RIGHT, gray(0.24), steer > 0) { d -> if (race.playing) race.steer = if (d) 1.0 else (if (race.steer > 0) 0.0 else race.steer) }
        }
        Spacer(Modifier.weight(1f))
        Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
            Box(
                Modifier.size(kw, kh).scale(if (fireLit) 0.9f else 1f)
                    .clickable(remember { MutableInteractionSource() }, null, enabled = !isDemo) { race.firePlayerRocket() }
            ) { Canvas(Modifier.fillMaxSize()) { inPoints { w, h -> with(RKArt) { key(w, h, RKArt.Face.FIRE, rgb(0.9, 0.24, 0.24), fireLit) } } } }
            hold(RKArt.Face.GAS, rgb(0.2, 0.62, 0.3), gas) { d -> if (race.playing) race.gas = d }
        }
    }
}
