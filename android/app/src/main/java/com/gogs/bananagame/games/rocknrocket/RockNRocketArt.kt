package com.gogs.bananagame.games.rocknrocket

import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.drawscope.translate
import com.gogs.bananagame.core.*
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Rock 'n' Rocket's art (iOS RKArt, RKTrack, RKFlagIcon, RKMedal, RKRocketIcon, RKKey): Rock n' Roll
 * Racing-style worlds seen from above. Drawn in points (see [inPoints]); strokes use SwiftUI's defaults
 * (butt caps, miter joins) unless the iOS code rounds them.
 */
internal object RKArt {
    enum class Face { LEFT, RIGHT, FIRE, GAS }

    fun hash(n: Double): Double { val x = sin(n) * 43758.5453; return x - floor(x) }

    private fun DrawScope.stroke(p: Path, c: Color, lw: Double, cap: StrokeCap = StrokeCap.Butt, join: StrokeJoin = StrokeJoin.Miter, dash: FloatArray? = null) =
        drawPath(p, c, style = Stroke(lw.f, miter = 10f, cap = cap, join = join, pathEffect = dash?.let { PathEffect.dashPathEffect(it, 0f) }))
    private fun Path.oval(x: Double, y: Double, w: Double, h: Double) = addOval(Rect(x.f, y.f, (x + w).f, (y + h).f))
    private fun Path.box(x: Double, y: Double, w: Double, h: Double) = addRect(Rect(x.f, y.f, (x + w).f, (y + h).f))
    private fun Path.rbox(x: Double, y: Double, w: Double, h: Double, r: Double) =
        addRoundRect(RoundRect(x.f, y.f, (x + w).f, (y + h).f, CornerRadius(r.f, r.f)))
    private fun oval(x: Double, y: Double, w: Double, h: Double) = Path().apply { oval(x, y, w, h) }

    /** Ground colours per world: desert, grassland, forest, ice planet, night city, volcanic, inferno. */
    fun ground(level: Int): Pair<Color, Color> = when (min(max(level, 1), 7)) {
        1 -> rgb(0.88, 0.76, 0.52) to rgb(0.76, 0.62, 0.40)
        2 -> rgb(0.44, 0.68, 0.32) to rgb(0.32, 0.54, 0.24)
        3 -> rgb(0.26, 0.5, 0.28) to rgb(0.15, 0.35, 0.19)
        4 -> rgb(0.88, 0.92, 0.97) to rgb(0.7, 0.78, 0.9)
        5 -> rgb(0.12, 0.14, 0.26) to rgb(0.06, 0.07, 0.16)
        6 -> rgb(0.27, 0.13, 0.12) to rgb(0.14, 0.06, 0.07)
        else -> rgb(0.33, 0.1, 0.06) to rgb(0.16, 0.04, 0.03)
    }

    /** One piece of scenery for the world (drawn off the track only). */
    private fun DrawScope.prop(px: Double, py: Double, s: Double, level: Int, seed: Double) {
        val shadow = oval(px - s * 0.4, py + s * 0.2, s * 0.9, s * 0.3)
        when (min(max(level, 1), 7)) {
            1 -> if (seed < 0.55) {
                // Saguaro seen from above-front.
                drawPath(shadow, Color.Black.op(0.18))
                val cactus = Path()
                cactus.rbox(px - s * 0.1, py - s * 0.45, s * 0.2, s * 0.75, s * 0.1)
                cactus.rbox(px - s * 0.36, py - s * 0.2, s * 0.14, s * 0.3, s * 0.07)
                cactus.rbox(px + s * 0.22, py - s * 0.3, s * 0.14, s * 0.3, s * 0.07)
                cactus.box(px - s * 0.3, py - s * 0.02, s * 0.25, s * 0.1)
                cactus.box(px + s * 0.05, py - s * 0.08, s * 0.25, s * 0.1)
                drawPath(cactus, rgb(0.3, 0.55, 0.26))
            } else {
                drawPath(oval(px - s * 0.32, py - s * 0.18, s * 0.64, s * 0.42), rgb(0.62, 0.48, 0.32))
                drawPath(oval(px - s * 0.22, py - s * 0.16, s * 0.3, s * 0.18), rgb(0.78, 0.66, 0.5))
            }
            2, 3 -> {
                drawPath(shadow, Color.Black.op(0.2))
                val r = s * (if (level == 3) 0.42 else 0.3)
                val crown = if (level == 3) rgb(0.13, 0.36, 0.17) else rgb(0.28, 0.56, 0.22)
                circle(px, py, r, crown)
                drawPath(oval(px - r * 0.6, py - r * 0.7, r * 0.9, r * 0.8), crown.mix(Color.White, 0.18))
                if (level == 2 && seed > 0.7) {
                    for (k in 0 until 3) circle(px + (k - 1) * s * 0.3, py + s * 0.45, s * 0.05, if (k == 1) rgb(1.0, 0.85, 0.3) else Color.White)
                }
            }
            4 -> {
                // Snowy pine: a white-capped star seen from above.
                drawPath(shadow, rgb(0.3, 0.4, 0.6).op(0.25))
                val star = Path()
                for (k in 0 until 10) {
                    val a = k / 10.0 * 2 * PI
                    val rr = s * (if (k % 2 == 0) 0.42 else 0.2)
                    if (k == 0) star.m(px + cos(a) * rr, py + sin(a) * rr) else star.l(px + cos(a) * rr, py + sin(a) * rr)
                }
                star.close()
                drawPath(star, rgb(0.2, 0.42, 0.36))
                circle(px, py, s * 0.14, Color.White)
            }
            5 -> {
                // Street lamp pooling light on the ground.
                val glow = rgb(1.0, 0.85, 0.5)
                circle(px, py, s * 0.7, radial(listOf(glow.op(0.35), glow.op(0.0)), px, py, s * 0.7))
                circle(px, py, s * 0.08, rgb(1.0, 0.92, 0.7))
            }
            else -> if (seed < 0.5) {
                // A lava pool with a bright core.
                drawPath(oval(px - s * 0.42, py - s * 0.26, s * 0.84, s * 0.52), radial(listOf(rgb(1.0, 0.85, 0.3), rgb(1.0, 0.4, 0.1), rgb(0.5, 0.1, 0.04)), px, py, s * 0.44))
            } else {
                drawPath(oval(px - s * 0.3, py - s * 0.2, s * 0.6, s * 0.4), rgb(0.1, 0.06, 0.06))
                drawPath(oval(px - s * 0.18, py - s * 0.16, s * 0.26, s * 0.14), rgb(0.28, 0.16, 0.14))
            }
        }
    }

    /**
     * The circuit, drawn once per race: the world's ground and scenery (kept off the tarmac), red and
     * white kerbs, textured asphalt the width the physics allows, white edge lines, a dashed centre line,
     * and the chequered start/finish across index 0.
     */
    fun DrawScope.track(W: Double, H: Double, center: List<P>, halfWidth: Double, level: Int) {
        val (g0, g1) = ground(level)
        rect(0.0, 0.0, W, H, vgrad(listOf(g0, g1), 0.0, H))
        if (level >= 5) {
            val stars = Path()
            for (i in 0 until 50) {
                val d = 1 + hash(i * 1.7) * 1.4
                stars.oval(hash(i * 12.9) * W, hash(i * 78.2) * H, d, d)
            }
            drawPath(stars, (if (level == 5) Color.White else rgb(1.0, 0.6, 0.4)).op(0.55))
        }
        // Ground speckle.
        val speck = Path()
        for (i in 0 until 160) {
            val d = 1.5 + hash(i * 3.3) * 2.5
            speck.oval(hash(i * 5.1) * W, hash(i * 9.7) * H, d, d * 0.7)
        }
        drawPath(speck, g1.mix(Color.Black, 0.25).op(0.5))
        if (center.size <= 2) return
        val minDim = min(W, H)
        val hw = halfWidth * minDim
        // Scenery away from the track.
        val clear = hw + minDim * 0.05
        for (i in 0 until 80) {
            val qx = hash(i * 17.3) * W; val qy = hash(i * 31.7) * H
            if (center.any { hypot(it.x * W - qx, it.y * H - qy) < clear }) continue
            prop(qx, qy, minDim * 0.055, level, hash(i * 2.9))
        }
        val path = Path()
        path.m(center[0].x * W, center[0].y * H)
        for (p in center.drop(1)) path.l(p.x * W, p.y * H)
        path.close()
        val lw = hw * 2
        // Kerbs: red with white blocks, just outside the tarmac.
        stroke(path, rgb(0.86, 0.16, 0.14), lw + 9, StrokeCap.Round, StrokeJoin.Round)
        stroke(path, Color.White, lw + 9, StrokeCap.Butt, StrokeJoin.Round, floatArrayOf(7f, 7f))
        // Tarmac with a faint grain, white edge lines, the dashed centre line.
        val tarmac = if (level >= 5) gray(0.2) else gray(0.3)
        stroke(path, tarmac, lw, StrokeCap.Round, StrokeJoin.Round)
        stroke(path, Color.White.op(0.05), lw * 0.6, StrokeCap.Round, StrokeJoin.Round, floatArrayOf(2f, 9f))
        stroke(path, Color.White.op(0.85), lw - 2, StrokeCap.Round, StrokeJoin.Round)
        stroke(path, tarmac, lw - 5, StrokeCap.Round, StrokeJoin.Round)
        stroke(path, Color.White.op(0.55), 2.0, StrokeCap.Butt, dash = floatArrayOf(10f, 12f))
        // Start / finish: a chequered band across the track at index 0.
        val a = center[0]; val b = center[1]
        val dx = b.x - a.x; val dy = b.y - a.y
        val dl = max(0.0001, hypot(dx, dy))
        val nx = -dy / dl; val ny = dx / dl
        val ax = dx / dl; val ay = dy / dl
        val squares = 8
        for (row in 0 until 2) for (s in 0 until squares) {
            val t0 = s.toDouble() / squares * 2 - 1
            val t1 = (s + 1).toDouble() / squares * 2 - 1
            val o = row * 4.5
            val c0x = a.x * W + nx * hw * t0 + ax * o; val c0y = a.y * H + ny * hw * t0 + ay * o
            val c1x = a.x * W + nx * hw * t1 + ax * o; val c1y = a.y * H + ny * hw * t1 + ay * o
            drawPath(polyPath(c0x, c0y, c1x, c1y, c1x + ax * 4.5, c1y + ay * 4.5, c0x + ax * 4.5, c0y + ay * 4.5),
                if ((s + row) % 2 == 0) Color.White else Color.Black)
        }
    }

    /** Rockets and cars, live. */
    fun DrawScope.race(race: RocketRace, w: Double, h: Double) {
        val flick = (race.animT * 22).toInt() % 2 == 0
        for (r in race.rockets) rocket(r.x * w, r.y * h, r.heading, h * 0.042, flick)
        for (c in race.cars) {
            val blink = c.spin > 0 && (c.spin * 16).toInt() % 2 == 0
            car(c.x * w, c.y * h, c.heading, h * 0.036, c.color, c.isPlayer, blink, c.spin > 0)
        }
    }

    /** A top-down race car along its heading: wheels, a tapered body with a racing stripe, the cockpit, a rear wing. */
    fun DrawScope.car(px: Double, py: Double, heading: Double, L: Double, color: Color, player: Boolean, dim: Boolean, spinning: Boolean) {
        translate(px.f, py.f) {
            rotateRad(heading.f, Offset.Zero) {
                withAlpha(if (dim) 0.55 else 1.0) {
                    val W = L * 0.62
                    rrect(-L * 0.46 + 1.5, -W * 0.46 + 2, L * 0.96, W * 0.96, W * 0.3, Color.Black.op(0.35))
                    for ((x, y) in listOf(-0.3 to -0.52, -0.3 to 0.52, 0.28 to -0.5, 0.28 to 0.5)) {
                        rrect(x * L - L * 0.1, y * W - W * 0.13, L * 0.2, W * 0.26, W * 0.06, gray(0.1))
                    }
                    val body = Path().apply {
                        m(-L * 0.46, -W * 0.42)
                        l(L * 0.2, -W * 0.42)
                        q(L * 0.5, -W * 0.34, L * 0.5, 0.0)
                        q(L * 0.5, W * 0.34, L * 0.2, W * 0.42)
                        l(-L * 0.46, W * 0.42)
                        close()
                    }
                    drawPath(body, vgrad(listOf(color.mix(Color.White, 0.3), color, color.mix(Color.Black, 0.3)), -W * 0.42, W * 0.42))
                    rect(-L * 0.46, -W * 0.08, L * 0.9, W * 0.16, if (player) gray(0.1).op(0.85) else Color.White.op(0.75))
                    rrect(-L * 0.02, -W * 0.24, L * 0.22, W * 0.48, W * 0.14, rgb(0.12, 0.18, 0.26))
                    rrect(L * 0.04, -W * 0.16, L * 0.08, W * 0.14, W * 0.05, Color.White.op(0.5))
                    rrect(-L * 0.52, -W * 0.52, L * 0.1, W * 1.04, W * 0.04, color.mix(Color.Black, 0.45))
                    stroke(body, Color.Black.op(0.6), max(0.8, L * 0.04))
                }
                if (spinning) {
                    val W = L * 0.62
                    withAlpha(0.6) { for (k in 0 until 3) circle(-L * (0.6 + k * 0.18), (if (k % 2 == 0) -1 else 1) * W * 0.3, W * 0.3, gray(0.85)) }
                }
            }
        }
    }

    /** A missile along its heading: white body, red nose, fins, a flickering flame. */
    fun DrawScope.rocket(px: Double, py: Double, heading: Double, L: Double, flick: Boolean) {
        translate(px.f, py.f) {
            rotateRad(heading.f, Offset.Zero) {
                val W = L * 0.34
                val flame = if (flick) L * 0.55 else L * 0.38
                drawPath(polyPath(-L * 0.42, -W * 0.35, -L * 0.42 - flame, 0.0, -L * 0.42, W * 0.35),
                    Brush.horizontalGradient(listOf(rgb(1.0, 0.95, 0.6), rgb(1.0, 0.5, 0.1).op(0.0)), (-L * 0.42).f, (-L * 0.42 - flame).f))
                drawPath(polyPath(-L * 0.3, 0.0, -L * 0.46, -W * 0.85, -L * 0.46, W * 0.85), rgb(0.75, 0.18, 0.16))
                val body = Path().apply { rbox(-L * 0.42, -W / 2, L * 0.72, W, W * 0.3) }
                drawPath(body, vgrad(listOf(gray(0.98), gray(0.7)), -W / 2, W / 2))
                val nose = Path().apply {
                    m(L * 0.3, -W / 2); q(L * 0.46, -W * 0.45, L * 0.5, 0.0)
                    q(L * 0.46, W * 0.45, L * 0.3, W / 2); close()
                }
                drawPath(nose, rgb(0.9, 0.2, 0.18))
                stroke(body, Color.Black.op(0.5), max(0.6, L * 0.03))
            }
        }
    }

    /** A chequered flag (the lap counter). */
    fun DrawScope.flagIcon(w: Double, h: Double) {
        line(w * 0.14, h * 0.05, w * 0.14, h * 0.98, Color.White, max(1.5, w * 0.1), StrokeCap.Butt)
        val fx = w * 0.2; val fy = h * 0.08; val fw = w * 0.76; val fh = h * 0.5
        rect(fx, fy, fw, fh, Color.White)
        for (r in 0 until 3) for (c in 0 until 4) if ((r + c) % 2 == 0) rect(fx + c * fw / 4, fy + r * fh / 3, fw / 4, fh / 3, Color.Black)
    }

    /** The player's place on a gold, silver or bronze medal (the number is a Text on top). */
    fun DrawScope.medal(w: Double, h: Double, place: Int) {
        val metal = when (place) {
            1 -> listOf(rgb(1.0, 0.88, 0.4), rgb(0.86, 0.62, 0.12))
            2 -> listOf(gray(0.92), gray(0.62))
            else -> listOf(rgb(0.92, 0.62, 0.4), rgb(0.66, 0.38, 0.2))
        }
        val r = min(w, h) / 2
        circle(w / 2, h / 2, r, vgrad(metal, h / 2 - r, h / 2 + r))
        circleStroke(w / 2, h / 2, r - 0.75, Color.Black.op(0.4), 1.5)
    }

    /** A rocket pip for the HUD (lit = still in the rack). */
    fun DrawScope.rocketIcon(w: Double, h: Double, lit: Boolean) {
        withAlpha(if (lit) 1.0 else 0.28) { rocket(w / 2, h / 2, -PI / 2, h * 0.9, false) }
    }

    /** The driving keys: ◄ ►, the red FIRE key (a missile) and the green GAS key (a pedal). */
    fun DrawScope.key(w: Double, h: Double, face: Face, color: Color, lit: Boolean) {
        rrect(0.0, 0.0, w, h, 14.0, vgrad(if (lit) listOf(rgb(1.0, 0.92, 0.5), rgb(0.96, 0.74, 0.2))
            else listOf(color.mix(Color.White, 0.18), color.mix(Color.Black, 0.25)), 0.0, h))
        val bw = if (lit) 2.5 else 1.5
        rrectStroke(bw / 2, bw / 2, w - bw, h - bw, 14 - bw / 2, Color.White.op(if (lit) 0.95 else 0.3), bw)
        val ink = if (lit) rgb(0.2, 0.12, 0.0) else Color.White
        val m = min(w, h)
        val cx = w / 2; val cy = h / 2
        when (face) {
            Face.LEFT, Face.RIGHT -> {
                val s = if (face == Face.LEFT) -1.0 else 1.0
                drawPath(polyPath(cx + s * m * 0.2, cy, cx - s * m * 0.14, cy - m * 0.2, cx - s * m * 0.14, cy + m * 0.2), ink)
            }
            Face.FIRE -> rocket(cx, cy, -PI / 4, m * 0.62, true)
            Face.GAS -> translate(cx.f, (cy + m * 0.02).f) {
                // An accelerator pedal in perspective: a ribbed pad leaning back on its arm and hinge.
                drawPath(polyPath(-m * 0.1, -m * 0.28, m * 0.1, -m * 0.28, m * 0.17, m * 0.08, -m * 0.17, m * 0.08), ink)
                val ribs = Path()
                for (k in 0 until 4) {
                    val y = -m * 0.2 + k * m * 0.08
                    val hw = m * (0.07 + 0.017 * k)
                    ribs.m(-hw, y); ribs.l(hw, y)
                }
                stroke(ribs, if (lit) Color.White.op(0.7) else Color.Black.op(0.45), max(1.2, m * 0.04))
                line(0.0, m * 0.08, -m * 0.08, m * 0.24, ink, m * 0.07)
                drawPath(oval(-m * 0.15, m * 0.19, m * 0.14, m * 0.11), ink)
            }
        }
    }
}
