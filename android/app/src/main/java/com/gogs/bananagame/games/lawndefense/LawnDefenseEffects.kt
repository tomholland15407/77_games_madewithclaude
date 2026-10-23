package com.gogs.bananagame.games.lawndefense

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.geometry.Offset
import com.gogs.bananagame.core.*
import com.gogs.bananagame.games.lawndefense.LDPlants.eyes
import com.gogs.bananagame.games.lawndefense.LDPlants.ink
import com.gogs.bananagame.games.lawndefense.LDPlants.leaf
import com.gogs.bananagame.games.lawndefense.LDPlants.leafDark
import com.gogs.bananagame.games.lawndefense.LDPlants.mixP
import com.gogs.bananagame.games.lawndefense.LDPlants.ramp
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** A zombie a flytrap has just snapped up: where it stood, how tall it's drawn and which world dresses it. */
class LDPrey(val zombie: LDZombie, val feet: P, val h: Double, val scene: LDScene)

// Flytrap, bombs and battle effects (iOS LawnDefenseArt.swift, second plant part and effects).
object LDFlytrap {
    /**
     * The flytrap: hinged jaws ringed with bristles. It strikes down over a zombie's head, hauls it back with
     * its legs kicking out of the jaws, gulps it down in three swallows and chews. A boss gets a lunge and snap.
     */
    fun flytrap(d: DrawScope, bx: Double, by: Double, s: Double, t: Double, seed: Double, chewing: Double, gulp: Double, prey: LDPrey?) = with(d) {
        val u = density.toDouble()
        val since = t - gulp
        val chew = 0.04 + 0.03 * abs(sin(t * 7))
        var open = if (chewing > 0) chew else if (since < 0.3) 0.05 else 0.5 + 0.06 * sin(t * 2.5 + seed)
        var bulge = if (chewing > 0) 1.12 else 1.0
        val rest = P(bx - s * 0.14, by - s * 0.5)
        var len = s * 0.5
        var jaw = 1.0
        var hinge = rest
        var aim = 0.0
        var mealFeet: P? = null; var mealTilt = 0.0; var mealScale = 1.0; var mealLips: P? = null
        if (chewing > 0 && since >= 0 && prey != null) {
            val a = since
            val biteAim = 1.1; val biteJaw = 1.5
            val chest = P(prey.feet.x - prey.h * 0.03, prey.feet.y - prey.h * 0.72)
            val biteHinge = P(chest.x - len * biteJaw * cos(biteAim), chest.y - len * biteJaw * sin(biteAim))
            val held = P(rest.x + s * 0.04, rest.y - s * 0.06)
            val strike = ramp(a, 0.0, 0.12); val snap = ramp(a, 0.12, 0.19); val grab = ramp(a, 0.13, 0.24)
            val haul = ramp(a, 0.2, 0.6); val settle = ramp(a, 1.35, 1.6)
            val gp = min(3.0, max(0.0, (a - 0.6) / 0.25)); val done = floor(gp)
            val swallowed = (done + ramp(gp - done, 0.0, 0.5)) / 3
            val jerk = if (gp < 3 && gp > 0) sin(min(1.0, (gp - done) / 0.5) * PI) else 0.0
            hinge = mixP(mixP(mixP(rest, biteHinge, strike), held, haul), rest, settle)
            hinge = P(hinge.x, hinge.y - jerk * s * 0.05)
            aim = biteAim * strike
            aim += (0.22 - aim) * haul
            aim += (0 - aim) * settle
            aim -= jerk * 0.12
            open = 0.5 + 0.5 * strike
            open += (0.4 - open) * snap
            open += jerk * 0.08
            open += (chew - open) * settle
            bulge = 1 + 0.12 * grab + 0.2 * swallowed
            bulge += (1.12 - bulge) * settle
            jaw = 1 + (biteJaw - 1) * strike - 0.2 * haul - 0.3 * swallowed
            len *= jaw
            if (a < 1.6) {
                val along = 0.72 - 0.17 * haul
                val reach = (along * (1 - swallowed) - 0.2 * swallowed) * prey.h
                val scale = 1 - 0.34 * haul
                val tilt = aim - PI / 2 + 0.1 * sin(t * 17) * (1 - swallowed) * grab
                val dx = cos(aim); val dy = sin(aim)
                val lips = P(hinge.x + dx * len, hinge.y + dy * len)
                val upx = sin(tilt); val upy = -cos(tilt)
                val hung = P(lips.x - upx * reach * scale, lips.y - upy * reach * scale)
                mealFeet = mixP(prey.feet, hung, grab)
                mealTilt = tilt * grab
                mealScale = 1 + (scale - 1) * grab
                mealLips = if (a >= 0.15) P(hinge.x + dx * len * 0.78, hinge.y + dy * len * 0.78) else null
            }
        } else if (chewing > 0 && since >= 0 && since < 0.45) {
            val strike = ramp(since, 0.0, 0.1); val snap = ramp(since, 0.1, 0.16); val back = ramp(since, 0.2, 0.45)
            hinge = mixP(mixP(rest, P(rest.x + s * 0.55, rest.y - s * 0.05), strike), rest, back)
            aim = 0.12 * strike * (1 - back)
            open = 0.5 + 0.5 * strike
            open += (chew - open) * snap
            jaw = 1 + 0.3 * (strike * (1 - back))
            len *= jaw
        }
        val stem = Path(); stem.m(bx, by)
        stem.q(bx + s * 0.08 + (hinge.x - rest.x) * 0.15, by - s * 0.25 + (hinge.y - rest.y) * 0.3, hinge.x, hinge.y)
        strokeR(stem, leafDark, s * 0.1); strokeR(stem, leaf, s * 0.05)
        for (side in listOf(-1.0, 1.0)) {
            val l = Path(); l.m(bx, by)
            l.q(bx + side * s * 0.2, by - s * 0.28, bx + side * s * 0.42, by - s * 0.16)
            l.q(bx + side * s * 0.3, by + s * 0.02, bx, by)
            drawPath(l, leaf); stroke(l, leafDark, 1.1 * u)
        }
        val mf = mealFeet
        if (mf != null && prey != null) {
            val drawMeal: DrawScope.() -> Unit = {
                translate(mf.x.f, mf.y.f) {
                    rotateRad(mealTilt.f, Offset.Zero) {
                        scale(mealScale.f, mealScale.f, Offset.Zero) {
                            val kicking = prey.zombie.kickingCopy()
                            LDZombies.figure(this, 0.0, 0.0, prey.h, kicking, t, prey.scene, LDOutfit.of(prey.scene), false)
                        }
                    }
                }
            }
            val lips = mealLips
            if (lips != null) {
                val gullet = Path(); gullet.m(hinge.x, hinge.y)
                for (side in listOf(-1.0, 1.0)) gullet.l(hinge.x + cos(aim + side * open) * len, hinge.y + sin(aim + side * open) * len)
                gullet.close()
                drawPath(gullet, rgb(0.36, 0.05, 0.1))
                val dx = cos(aim); val dy = sin(aim); val far = prey.h * 3
                val outside = polyPath(lips.x - dy * far, lips.y + dx * far, lips.x + dy * far, lips.y - dx * far,
                    lips.x + dy * far + dx * far, lips.y - dx * far + dy * far, lips.x - dy * far + dx * far, lips.y + dx * far + dy * far)
                clipPath(outside) { drawMeal() }
            } else drawMeal()
        }
        val depth = s * 0.17 * bulge * jaw
        for (side in listOf(-1.0, 1.0)) {
            val a = aim + side * open
            val dx = cos(a); val dy = sin(a)
            val nx = -dy * side; val ny = dx * side
            val tx = hinge.x + dx * len; val ty = hinge.y + dy * len
            val mx = hinge.x + dx * len * 0.5 - nx * depth; val my = hinge.y + dy * len * 0.5 - ny * depth
            val lobe = Path(); lobe.m(hinge.x, hinge.y)
            lobe.q(mx - nx * depth * 0.6, my - ny * depth * 0.6, tx, ty)
            lobe.q(hinge.x + dx * len * 0.55, hinge.y + dy * len * 0.55, hinge.x, hinge.y)
            drawPath(lobe, rgb(0.4, 0.72, 0.22)); stroke(lobe, leafDark, 1.3 * u)
            val inner = Path()
            inner.m(hinge.x + dx * len * 0.12, hinge.y + dy * len * 0.12)
            inner.q(hinge.x + dx * len * 0.52 - nx * depth * 0.55, hinge.y + dy * len * 0.52 - ny * depth * 0.55, hinge.x + dx * len * 0.92, hinge.y + dy * len * 0.92)
            inner.q(hinge.x + dx * len * 0.52, hinge.y + dy * len * 0.52, hinge.x + dx * len * 0.12, hinge.y + dy * len * 0.12)
            drawPath(inner, rgb(0.88, 0.22, 0.28))
            val br = Path()
            for (i in 1..6) {
                val f = i / 7.0
                val k = 1 - abs(f - 0.5) * 1.4
                val bxx = hinge.x + dx * len * f - nx * depth * 0.9 * k; val byy = hinge.y + dy * len * f - ny * depth * 0.9 * k
                br.m(bxx, byy); br.l(bxx - nx * s * 0.08 * jaw + dx * s * 0.03, byy - ny * s * 0.08 * jaw + dy * s * 0.03)
            }
            stroke(br, rgb(0.86, 0.95, 0.7), 1.3 * u, StrokeCap.Round)
        }
        val ex = len * 0.3; val ey = -s * 0.12 - open * s * 0.18
        val topX = hinge.x + ex * cos(aim) - ey * sin(aim); val topY = hinge.y + ex * sin(aim) + ey * cos(aim)
        val busy = since >= 0 && since < 1.6
        eyes(topX, topY, s * 0.045, s * 0.12, chewing > 0 && !busy && (t * 2).toInt() % 3 == 0)
    }

    fun cherry(d: DrawScope, bx: Double, by: Double, s: Double, fuse: Double, t: Double) = with(d) {
        val u = density.toDouble()
        val swell = 1 + max(0.0, fuse) * 0.28
        val jitter = sin(t * 60) * s * 0.02 * fuse
        val jx = bx + jitter; val jy = by - s * 0.78
        val berries = listOf(P(bx - s * 0.17 + jitter, by - s * 0.22), P(bx + s * 0.15 + jitter, by - s * 0.3))
        val stems = Path()
        for (c in berries) { stems.m(c.x, c.y); stems.q((c.x + jx) / 2, jy + s * 0.1, jx, jy) }
        strokeR(stems, leafDark, s * 0.05)
        val lf = Path(); lf.m(jx, jy); lf.q(jx + s * 0.1, jy - s * 0.14, jx + s * 0.24, jy - s * 0.04); lf.q(jx + s * 0.14, jy + s * 0.06, jx, jy)
        drawPath(lf, leaf); stroke(lf, leafDark, u)
        val red = rgb(min(1.0, 0.86 + 0.1 * fuse), 0.1, 0.1)
        for (c in berries) {
            val r = s * 0.2 * swell
            circle(c.x, c.y, r, radial(listOf(red.lit(0.35), red, red.shade(0.35)), c.x - r * 0.35, c.y - r * 0.4, r * 1.3))
            circleStroke(c.x, c.y, r, rgb(0.35, 0.02, 0.02), 1.4 * u)
            for (dx in listOf(-0.32, 0.32)) {
                val ex = c.x + dx * r; val ey = c.y - r * 0.05
                circle(ex, ey, r * 0.12, ink)
                val sg = if (dx < 0) 1.0 else -1.0
                line(ex - r * 0.2 * sg, ey - r * 0.32, ex + r * 0.16 * sg, ey - r * 0.16, ink, 1.5 * u, StrokeCap.Butt)
            }
            val m = Path(); m.arc(c.x, c.y + r * 0.45, r * 0.2, deg(200.0), deg(340.0), moveFirst = true)
            stroke(m, ink, 1.3 * u)
        }
    }

    /** The hot chili: a curled red pepper that gets angrier until it bursts into a lane of fire. */
    fun chili(d: DrawScope, bx: Double, by: Double, s: Double, fuse: Double, t: Double) = with(d) {
        val u = density.toDouble()
        val f = max(0.0, min(1.0, fuse))
        val jitter = sin(t * 70) * s * 0.025 * f
        val swell = 1 + f * 0.18
        val red = rgb(0.9, 0.12 + 0.25 * f, 0.08)
        val tx = bx + jitter; val ty = by - s * 0.78
        val pepper = Path()
        pepper.m(tx - s * 0.13 * swell, ty + s * 0.06)
        pepper.c(tx - s * 0.24 * swell, ty + s * 0.4, bx - s * 0.2 + jitter, by - s * 0.05, bx + s * 0.12 + jitter, by - s * 0.02)
        pepper.c(bx + s * 0.02 + jitter, by - s * 0.22, tx + s * 0.2 * swell, ty + s * 0.34, tx + s * 0.13 * swell, ty + s * 0.06)
        pepper.close()
        if (f > 0.3) circle(bx, by - s * 0.4, s * 0.42 * f, radial(listOf(rgb(1.0, 0.6, 0.1, 0.6), Color.Transparent), bx, by - s * 0.4, s * 0.42 * f))
        drawPath(pepper, hgrad(listOf(red.lit(0.25), red, red.shade(0.35)), tx - s * 0.15, tx + s * 0.15))
        stroke(pepper, rgb(0.35, 0.02, 0.02), 1.4 * u)
        val cap = Path().apply { ovalD(tx - s * 0.15 * swell, ty - s * 0.03, s * 0.3 * swell, s * 0.1) }
        drawPath(cap, leaf); stroke(cap, leafDark, 1.1 * u)
        val curl = Path(); curl.m(tx, ty); curl.q(tx - s * 0.04, ty - s * 0.14, tx + s * 0.12, ty - s * 0.12)
        strokeR(curl, leafDark, s * 0.04)
        val fx = tx - s * 0.01; val fy = ty + s * 0.28
        for (dx in listOf(-1.0, 1.0)) {
            val ex = fx + dx * s * 0.055
            circle(ex, fy, s * 0.028, ink)
            line(ex - dx * s * 0.05, fy - s * 0.06, ex + dx * s * 0.03, fy - s * 0.025, ink, 1.5 * u, StrokeCap.Butt)
        }
        line(fx - s * 0.06, fy + s * 0.09, fx + s * 0.06, fy + s * 0.08, ink, 1.6 * u, StrokeCap.Butt)
    }

    /** A cherry bomb's blast across its 3×3 tiles. */
    fun boom(d: DrawScope, cx: Double, cy: Double, cell: Double, age: Double) = with(d) {
        val k = min(1.0, age / 0.35)
        val fade = max(0.0, 1 - age / 0.9)
        val r = cell * (0.6 + 1.3 * k)
        withAlpha(fade) {
            circle(cx, cy, r * 1.1, radial(listOf(rgb(1.0, 0.95, 0.6), rgb(1.0, 0.55, 0.1), rgb(0.6, 0.15, 0.05, 0.0)), cx, cy, r * 1.1))
            val star = polyPath((0 until 20).map { i ->
                val a = i / 20.0 * 2 * PI
                val rr = if (i % 2 == 0) r else r * 0.55
                P(cx + cos(a) * rr, cy + sin(a) * rr * 0.8)
            })
            drawPath(star, rgb(1.0, 0.78, 0.2, 0.85))
            circle(cx, cy, r * 0.35, Color.White.op(0.9))
        }
    }

    /** A hot chili's fire running the whole lane. */
    fun blaze(d: DrawScope, lay: LDLayout, row: Int, age: Double) = with(d) {
        val fade = max(0.0, 1 - max(0.0, age - 0.45) / 0.45)
        val grow = min(1.0, age / 0.18)
        val cw = lay.cellW; val ch = lay.cellH
        val baseY = lay.point(0.0, row + 0.92).y
        withAlpha(fade) {
            var x = -0.6
            var i = 0.0
            while (x < LDWorld.COLS + 0.6) {
                val p = lay.point(x, row.toDouble())
                val h = ch * (0.55 + 0.35 * LDWorlds.hash(i + 1.3)) * grow * (0.8 + 0.2 * sin(age * 30 + i))
                val w = cw * 0.42
                val fl = Path()
                fl.m(p.x - w / 2, baseY)
                fl.q(p.x - w * 0.6, baseY - h * 0.5, p.x + sin(age * 20 + i) * w * 0.2, baseY - h)
                fl.q(p.x + w * 0.6, baseY - h * 0.5, p.x + w / 2, baseY)
                fl.close()
                drawPath(fl, vgrad(listOf(rgb(1.0, 0.95, 0.5), rgb(1.0, 0.5, 0.08), rgb(0.85, 0.12, 0.05)), baseY, baseY - h))
                x += 0.32; i += 1
            }
        }
    }

    /** Dust and splinters where a plant got squashed. */
    fun crash(d: DrawScope, cx: Double, cy: Double, cell: Double, age: Double) = with(d) {
        val u = density.toDouble()
        val k = min(1.0, age / 0.25)
        withAlpha(max(0.0, 1 - age / 0.7)) {
            ellipse(cx, cy, cell * (0.3 + 0.5 * k), cell * (0.12 + 0.18 * k), rgb(0.55, 0.45, 0.35, 0.7))
            val bits = Path()
            for (i in 0 until 7) {
                val a = i / 7.0 * PI + 0.2
                val dd = cell * 0.55 * k
                val px = cx + cos(a) * dd * (if (i % 2 == 0) 1 else -1); val py = cy - sin(a) * dd * 0.8 + cell * 0.6 * age * age
                bits.rectD(px - 2 * u, py - 2 * u, 4 * u, 3 * u)
            }
            drawPath(bits, rgb(0.3, 0.5, 0.15))
        }
    }

    /** The ice a frozen plant is locked in. */
    fun iceBlock(d: DrawScope, bx: Double, by: Double, s: Double, left: Double) = with(d) {
        val u = density.toDouble()
        val x = bx - s * 0.42; val y = by - s * 0.95; val w = s * 0.84; val h = s * 0.95
        withAlpha(if (left < 1) 0.5 + 0.5 * left else 1.0) {
            rrect(x, y, w, h, s * 0.08, lin(listOf(rgb(0.85, 0.95, 1.0, 0.75), rgb(0.55, 0.78, 0.95, 0.6)), x, y, x + w, y + h))
            rrectStroke(x, y, w, h, s * 0.08, Color.White.op(0.9), 1.5 * u)
            line(x + s * 0.12, y + s * 0.15, x + s * 0.12, y + s * 0.45, Color.White.op(0.9), 2 * u)
            line(x + s * 0.22, y + s * 0.12, x + s * 0.22, y + s * 0.25, Color.White.op(0.9), 2 * u)
            if (left < 2.5) {
                val cr = Path(); cr.m(x + w / 2, y); cr.l(x + w / 2 + s * 0.08, y + s * 0.25); cr.l(x + w / 2 - s * 0.05, y + s * 0.42)
                stroke(cr, Color.White, 1.2 * u)
            }
        }
    }

    /** A sandstone grave marker: it rises out of the sand and crumbles as it's shot. */
    fun grave(d: DrawScope, bx: Double, by: Double, s: Double, health: Double, age: Double) = with(d) {
        val u = density.toDouble()
        val rise = min(1.0, age / 0.45)
        val w = s * 0.56; val h = s * 0.78 * rise
        if (h <= 1) return@with
        val x0 = bx - w / 2; val y0 = by - h; val x1 = x0 + w; val y1 = by
        val stone = Path()
        stone.m(x0, y1); stone.l(x0, y0 + w * 0.5)
        stone.arc(x0 + w / 2, y0 + w * 0.5, w / 2, PI, 2 * PI)
        stone.l(x1, y1); stone.close()
        drawPath(stone, hgrad(listOf(rgb(0.92, 0.78, 0.52), rgb(0.72, 0.55, 0.3)), x0, x1))
        stroke(stone, rgb(0.4, 0.26, 0.1), 1.4 * u)
        val ex = x0 + w / 2; val ey = y0 + w * 0.55
        val carve = Path()
        carve.m(ex - w * 0.22, ey); carve.q(ex, ey - w * 0.2, ex + w * 0.22, ey); carve.q(ex, ey + w * 0.2, ex - w * 0.22, ey)
        carve.m(ex - w * 0.25, ey + w * 0.42)
        for (i in 0 until 4) carve.q(ex - w * 0.25 + (i + 0.5) * w * 0.125, ey + w * 0.34, ex - w * 0.25 + (i + 1) * w * 0.125, ey + w * 0.42)
        stroke(carve, rgb(0.45, 0.3, 0.12), 1.3 * u)
        circle(ex, ey, w * 0.05, rgb(0.45, 0.3, 0.12))
        if (health < 0.6) {
            val cr = Path()
            cr.m(x0 + w * 0.2, y0 + w * 0.2); cr.l(x0 + w * 0.4, y0 + w * 0.45); cr.l(x0 + w * 0.3, y0 + w * 0.7)
            if (health < 0.3) { cr.m(x1 - w * 0.1, (y0 + y1) / 2); cr.l(x1 - w * 0.35, (y0 + y1) / 2 + w * 0.25) }
            stroke(cr, rgb(0.3, 0.18, 0.06), 1.4 * u)
        }
        ellipse(bx, by, w * 0.7, s * 0.06, rgb(0.86, 0.7, 0.45))
    }

    /** Snowballs, fireballs and iceballs (they roll, so their markings turn). */
    fun roller(d: DrawScope, cx: Double, cy: Double, r: Double, kind: LDRollerKind, spin: Double, t: Double) = with(d) {
        val u = density.toDouble()
        when (kind) {
            LDRollerKind.SNOWBALL -> {
                circle(cx, cy, r, radial(listOf(Color.White, rgb(0.82, 0.9, 0.98), rgb(0.6, 0.72, 0.88)), cx - r * 0.35, cy - r * 0.35, r * 1.4))
                val lumps = Path()
                for (k in 0 until 5) {
                    val a = spin + k * 1.26
                    lumps.ovalD(cx + cos(a) * r * 0.6 - r * 0.12, cy + sin(a) * r * 0.6 - r * 0.08, r * 0.24, r * 0.16)
                }
                drawPath(lumps, rgb(0.62, 0.72, 0.86))
                circleStroke(cx, cy, r, rgb(0.22, 0.32, 0.5), 2 * u)
            }
            else -> {
                val hot = kind == LDRollerKind.FIREBALL
                val core = if (hot) rgb(1.0, 0.9, 0.5) else rgb(0.85, 0.97, 1.0)
                val mid = if (hot) rgb(1.0, 0.45, 0.08) else rgb(0.35, 0.7, 1.0)
                val rim = if (hot) rgb(0.7, 0.1, 0.05) else rgb(0.15, 0.35, 0.75)
                for (k in 1..4) circle(cx + r * k * 0.55, cy + sin(t * 12 + k) * r * 0.12, r * (0.85 - k * 0.16), mid.op(0.45 - k * 0.09))
                circle(cx, cy, r, radial(listOf(core, mid, rim), cx - r * 0.25, cy - r * 0.25, r * 1.3))
                val marks = Path()
                for (k in 0 until 3) {
                    val a = spin + k * 2.09
                    if (hot) marks.ovalD(cx + cos(a) * r * 0.5 - r * 0.12, cy + sin(a) * r * 0.5 - r * 0.12, r * 0.24, r * 0.24)
                    else { marks.m(cx, cy); marks.l(cx + cos(a) * r * 0.85, cy + sin(a) * r * 0.85) }
                }
                if (hot) drawPath(marks, rgb(0.75, 0.2, 0.05, 0.7)) else stroke(marks, Color.White.op(0.8), 1.5 * u)
                circleStroke(cx, cy, r, rim, 1.4 * u)
            }
        }
    }
}
