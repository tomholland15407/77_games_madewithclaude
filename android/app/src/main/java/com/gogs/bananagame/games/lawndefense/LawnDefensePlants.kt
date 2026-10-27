package com.gogs.bananagame.games.lawndefense

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Matrix
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import com.gogs.bananagame.core.*
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

// Lawn Defense's plants (iOS LawnDefenseArt.swift, plants): anchored at the bottom centre of their tile,
// sized by `s` (the tile width). Line widths given in points in iOS are scaled by the display density.

/** An ellipse of radii (rx, ry) rotated by `a` radians about (cx, cy), as a path. */
internal fun rotatedOval(cx: Double, cy: Double, rx: Double, ry: Double, a: Double): Path {
    val p = Path(); p.ovalD(-rx, -ry, rx * 2, ry * 2)
    val m = Matrix(); m.translate(cx.f, cy.f); m.rotateZ((a * 180 / PI).f)
    p.transform(m)
    return p
}

internal fun ovalAt(cx: Double, cy: Double, rx: Double, ry: Double) = Path().apply { ovalD(cx - rx, cy - ry, rx * 2, ry * 2) }
internal fun discAt(cx: Double, cy: Double, r: Double) = ovalAt(cx, cy, r, r)
internal fun DrawScope.strokeR(p: Path, c: Color, lw: Double) = drawPath(p, c, style = Stroke(lw.f, cap = StrokeCap.Round, join = StrokeJoin.Round))

object LDPlants {
    val ink = rgb(0.12, 0.1, 0.06)
    val leaf = rgb(0.36, 0.72, 0.16)
    val leafDark = rgb(0.16, 0.42, 0.08)

    /** A plant as drawn in its seed packet. */
    fun icon(d: DrawScope, kind: LDPlantKind, bx: Double, by: Double, s: Double) = with(d) {
        when (kind) {
            LDPlantKind.SUNFLOWER -> sunflower(bx, by, s, 0.0, 0.0, false)
            LDPlantKind.PEASHOOTER -> peashooter(bx, by, s, 0.0, 0.0, 9.0)
            LDPlantKind.POPPER -> popper(bx, by, s, 0.0, 0.0, 9.0)
            LDPlantKind.FROST -> frostBerry(bx, by, s, 0.0, 0.0, 9.0)
            LDPlantKind.LOBBER -> lobber(bx, by, s, 0.0, 0.0, 9.0)
            LDPlantKind.WALLNUT -> wallnut(bx, by, s, 1.0, false)
            LDPlantKind.PEEL -> peel(bx, by - s * 0.06, s * 1.25, 1.0, 0.0)
            LDPlantKind.FLYTRAP -> LDFlytrap.flytrap(this, bx, by, s, 0.0, 0.0, 0.0, -9.0, null)
            LDPlantKind.CHERRY -> LDFlytrap.cherry(this, bx, by, s, 0.0, 0.0)
            LDPlantKind.CHILI -> LDFlytrap.chili(this, bx, by, s, 0.0, 0.0)
        }
    }

    private fun DrawScope.groundLeaf(bx: Double, by: Double, s: Double, side: Double, tipDy: Double, ctrlDy: Double, back: Double, fill: Color, edge: Color, lw: Double) {
        val l = Path()
        l.m(bx, by)
        l.q(bx + side * s * (back * 0.5), by - s * ctrlDy, bx + side * s * back, by - s * tipDy)
        l.q(bx + side * s * (back * 0.65), by + s * 0.06, bx, by)
        drawPath(l, fill); stroke(l, edge, lw)
    }

    fun DrawScope.sunflower(bx: Double, by: Double, s: Double, t: Double, seed: Double, wince: Boolean) {
        val u = density.toDouble()
        val bob = sin(t * 2.4 + seed) * s * 0.025
        val hx = bx + bob * 0.6; val hy = by - s * 0.7 + bob
        val stem = Path(); stem.m(bx, by); stem.q(bx + s * 0.08, by - s * 0.3, hx, hy + s * 0.2)
        strokeR(stem, leafDark, s * 0.11); strokeR(stem, leaf, s * 0.06)
        for (side in listOf(-1.0, 1.0)) {
            val rx = bx; val ry = by - s * 0.12
            val l = Path(); l.m(rx, ry)
            l.q(rx + side * s * 0.16, ry - s * 0.24, rx + side * s * 0.36, ry - s * 0.1)
            l.q(rx + side * s * 0.22, ry + s * 0.06, rx, ry)
            drawPath(l, leaf); stroke(l, leafDark, 1.2 * u)
        }
        val petals = Path()
        val pr = s * 0.38
        for (k in 0 until 13) {
            val a = k / 13.0 * 2 * PI + sin(t * 1.3 + seed) * 0.05
            petals.addPath(rotatedOval(hx + cos(a) * pr * 0.62, hy + sin(a) * pr * 0.62, pr * 0.36, pr * 0.17, a))
        }
        drawPath(petals, rgb(1.0, 0.82, 0.1)); stroke(petals, rgb(0.85, 0.5, 0.05), u)
        val fr = s * 0.21
        circle(hx, hy, fr, radial(listOf(rgb(0.72, 0.42, 0.14), rgb(0.5, 0.27, 0.08)), hx - fr * 0.3, hy - fr * 0.3, fr * 1.3))
        circleStroke(hx, hy, fr, rgb(0.35, 0.18, 0.05), 1.2 * u)
        for (dx in listOf(-0.38, 0.38)) {
            val ex = hx + dx * fr; val ey = hy - fr * 0.18
            if (wince) line(ex - fr * 0.14, ey, ex + fr * 0.14, ey, ink, 1.5 * u, StrokeCap.Butt)
            else { ellipse(ex, ey, fr * 0.13, fr * 0.2, ink); circle(ex - fr * 0.04, ey - fr * 0.07, fr * 0.05, Color.White) }
        }
        val smile = Path(); smile.arc(hx, hy + fr * 0.08, fr * 0.42, deg(25.0), deg(155.0), moveFirst = true)
        strokeR(smile, ink, 1.6 * u)
    }

    fun DrawScope.peashooter(bx: Double, by: Double, s: Double, t: Double, seed: Double, recoil: Double) {
        val u = density.toDouble()
        val sway = sin(t * 2 + seed) * s * 0.015
        val kick = max(0.0, 1 - recoil / 0.18)
        val hx = bx - s * 0.04 + sway - kick * s * 0.04; val hy = by - s * 0.6
        val hr = s * 0.24
        val stem = Path(); stem.m(bx, by); stem.q(bx - s * 0.06, by - s * 0.28, hx, hy + hr * 0.7)
        strokeR(stem, leafDark, s * 0.11); strokeR(stem, leaf, s * 0.06)
        for (side in listOf(-1.0, 1.0)) {
            val l = Path(); l.m(bx, by)
            l.q(bx + side * s * 0.2, by - s * 0.2, bx + side * s * 0.4, by - s * 0.03)
            l.q(bx + side * s * 0.26, by + s * 0.06, bx, by)
            drawPath(l, leaf); stroke(l, leafDark, 1.2 * u)
        }
        val g = listOf(rgb(0.7, 0.95, 0.35), rgb(0.36, 0.74, 0.14))
        val tuft = Path()
        tuft.m(hx - hr * 0.8, hy - hr * 0.3)
        tuft.q(hx - hr * 1.4, hy - hr * 0.2, hx - hr * 1.55, hy - hr * 0.9)
        tuft.q(hx - hr * 1.0, hy - hr * 1.0, hx - hr * 0.6, hy - hr * 0.75)
        drawPath(tuft, leaf); stroke(tuft, leafDark, 1.2 * u)
        val snoutL = hr * (1.05 - kick * 0.2)
        val sx = hx + hr * 0.3; val sy = hy - hr * 0.42; val sh = hr * 0.84
        rrect(sx, sy, snoutL, sh, hr * 0.3, vgrad(g, sy, sy + sh))
        rrectStroke(sx, sy, snoutL, sh, hr * 0.3, leafDark, 1.4 * u)
        val mx = sx + snoutL; val my = sy + sh / 2
        ellipse(mx, my, hr * 0.2, hr * 0.48, rgb(0.48, 0.82, 0.2))
        ellipseStroke(mx, my, hr * 0.2, hr * 0.48, leafDark, 1.4 * u)
        ellipse(mx, my, hr * 0.09, hr * 0.27, rgb(0.08, 0.2, 0.04))
        circle(hx, hy, hr, radial(g, hx - hr * 0.3, hy - hr * 0.4, hr * 1.5))
        circleStroke(hx, hy, hr, leafDark, 1.4 * u)
        val ex = hx + hr * 0.25; val ey = hy - hr * 0.22
        ellipse(ex, ey, hr * 0.24, hr * 0.3, Color.White)
        circle(ex + hr * 0.08, ey + hr * 0.02, hr * 0.15, ink)
        circle(ex + hr * 0.12, ey - hr * 0.05, hr * 0.05, Color.White)
    }

    /** Two little round eyes looking right. */
    fun DrawScope.eyes(cx: Double, cy: Double, r: Double, gap: Double, blink: Boolean = false) {
        val u = density.toDouble()
        for (dx in listOf(-gap / 2, gap / 2)) {
            val ex = cx + dx
            if (blink) { line(ex - r, cy, ex + r, cy, ink, max(1.2 * u, r * 0.4), StrokeCap.Butt); continue }
            ellipse(ex, cy, r, r * 1.2, Color.White)
            ellipseStroke(ex, cy, r, r * 1.2, ink, u)
            circle(ex + r * 0.35, cy + r * 0.1, r * 0.55, ink)
            circle(ex + r * 0.45, cy - r * 0.2, r * 0.2, Color.White)
        }
    }

    /** The corn popper: an ear of corn in its husk with a popcorn tuft; fires two popcorn puffs a shot. */
    fun DrawScope.popper(bx: Double, by: Double, s: Double, t: Double, seed: Double, recoil: Double) {
        val u = density.toDouble()
        val sway = sin(t * 2.2 + seed) * s * 0.015
        val kick = max(0.0, 1 - recoil / 0.22)
        val cx = bx + sway - kick * s * 0.03; val cy = by - s * 0.5
        val rx = s * 0.17 * (1 + 0.08 * kick); val ry = s * 0.3 * (1 - 0.06 * kick)
        for (side in listOf(-1.0, 1.0)) {
            val l = Path(); l.m(bx, by)
            l.q(bx + side * s * 0.34, by - s * 0.08, bx + side * s * 0.36, by - s * 0.44)
            l.q(bx + side * s * 0.16, by - s * 0.28, bx + side * s * 0.05, by - s * 0.12)
            l.close()
            drawPath(l, rgb(0.55, 0.78, 0.3)); stroke(l, leafDark, 1.2 * u)
        }
        val cob = ovalAt(cx, cy, rx, ry)
        drawPath(cob, hgrad(listOf(rgb(1.0, 0.88, 0.3), rgb(0.96, 0.64, 0.08)), cx - rx, cx + rx))
        val kernels = Path()
        for (row in 0 until 8) {
            val y = cy - ry * 0.85 + row * ry * 0.24
            for (col in 0 until 4) {
                val x = cx - rx * 0.75 + col * rx * 0.5 + (if (row % 2 == 0) 0.0 else rx * 0.25)
                kernels.ovalD(x - rx * 0.17, y - ry * 0.08, rx * 0.34, ry * 0.16)
            }
        }
        clipPath(cob) { stroke(kernels, rgb(0.82, 0.5, 0.05, 0.7), 0.8 * u) }
        stroke(cob, rgb(0.6, 0.35, 0.05), 1.4 * u)
        for ((i, p) in listOf(P(cx - rx * 0.5, cy - ry * 1.02), P(cx + rx * 0.15, cy - ry * 1.14), P(cx + rx * 0.7, cy - ry * 0.95)).withIndex())
            popcorn(p.x, p.y, s * 0.06, i.toDouble())
        for (side in listOf(-1.0, 1.0)) {
            val l = Path(); l.m(bx + side * s * 0.02, by - s * 0.05)
            l.q(bx + side * s * 0.26, by - s * 0.2, cx + side * rx * 0.95, cy - ry * 0.05)
            l.q(cx + side * rx * 0.3, cy + ry * 0.5, bx, by - s * 0.1)
            l.close()
            drawPath(l, leaf); stroke(l, leafDark, 1.2 * u)
        }
        eyes(cx - rx * 0.05, cy - ry * 0.3, rx * 0.26, rx * 0.75)
        val mx = cx + rx * 0.62; val my = cy + ry * 0.05
        ellipse(mx, my, rx * (0.2 + 0.12 * kick), ry * (0.1 + 0.05 * kick), rgb(0.4, 0.18, 0.02))
        if (kick > 0.3) popcorn(mx + rx * 0.5, my, s * 0.05 * kick, t)
    }

    /** A popcorn puff: shot and tuft. */
    fun DrawScope.popcorn(cx: Double, cy: Double, r: Double, spin: Double) {
        val puff = Path()
        for (k in 0 until 4) {
            val a = k / 4.0 * 2 * PI + spin
            puff.ovalD(cx + cos(a) * r * 0.55 - r * 0.6, cy + sin(a) * r * 0.55 - r * 0.6, r * 1.2, r * 1.2)
        }
        drawPath(puff, rgb(1.0, 0.98, 0.9)); stroke(puff, rgb(0.75, 0.62, 0.4), 0.8 * density)
        circle(cx, cy, r * 0.28, rgb(1.0, 0.78, 0.2))
    }

    /** The frost berry: a big frosted blueberry whose star-shaped crown is its muzzle. */
    fun DrawScope.frostBerry(bx: Double, by: Double, s: Double, t: Double, seed: Double, recoil: Double) {
        val u = density.toDouble()
        val sway = sin(t * 1.8 + seed) * s * 0.015
        val kick = max(0.0, 1 - recoil / 0.18)
        val hx = bx + sway - kick * s * 0.04; val hy = by - s * 0.52
        val r = s * 0.27
        val stem = Path(); stem.m(bx, by); stem.q(bx - s * 0.05, by - s * 0.15, hx - r * 0.2, hy + r * 0.8)
        strokeR(stem, rgb(0.18, 0.36, 0.3), s * 0.1); strokeR(stem, rgb(0.36, 0.62, 0.5), s * 0.05)
        for (side in listOf(-1.0, 1.0)) {
            val l = Path(); l.m(bx, by)
            l.q(bx + side * s * 0.16, by - s * 0.22, bx + side * s * 0.36, by - s * 0.1)
            l.q(bx + side * s * 0.24, by + s * 0.05, bx, by)
            drawPath(l, rgb(0.4, 0.68, 0.56)); stroke(l, rgb(0.16, 0.34, 0.28), 1.2 * u)
        }
        circle(hx, hy, r, radial(listOf(rgb(0.5, 0.58, 0.98), rgb(0.24, 0.26, 0.66), rgb(0.14, 0.14, 0.42)), hx - r * 0.35, hy - r * 0.35, r * 1.4))
        circle(hx - r * 0.3, hy - r * 0.38, r * 0.42, radial(listOf(Color.White.op(0.45), Color.White.op(0.0)), hx - r * 0.3, hy - r * 0.38, r * 0.42))
        circleStroke(hx, hy, r, rgb(0.1, 0.08, 0.3), 1.4 * u)
        val rime = Path(); rime.arc(hx, hy, r * 0.92, deg(200.0), deg(320.0), moveFirst = true)
        drawPath(rime, rgb(0.85, 0.95, 1.0, 0.85), style = Stroke((r * 0.14).f, cap = StrokeCap.Round,
            pathEffect = PathEffect.dashPathEffect(floatArrayOf((r * 0.18).f, (r * 0.12).f))))
        val crx = hx + r * 0.86; val cry = hy + r * 0.05
        val star = polyPath((0 until 10).map { i ->
            val a = i / 10.0 * 2 * PI
            val rr = if (i % 2 == 0) r * 0.36 else r * 0.16
            P(crx + cos(a) * rr * 0.6, cry + sin(a) * rr)
        })
        drawPath(star, rgb(0.2, 0.2, 0.5)); stroke(star, rgb(0.08, 0.06, 0.25), u)
        ellipse(crx, cry, r * 0.08, r * 0.12, rgb(0.05, 0.04, 0.18))
        eyes(hx - r * 0.05, hy - r * 0.12, r * 0.2, r * 0.6)
        for (i in 0 until 3) {
            val a = t * 0.9 + i * 2.1 + seed
            snowflake(hx + cos(a) * r * 1.35, hy + sin(a) * r * 1.1, s * 0.045)
        }
        if (kick > 0.2) circle(crx + r * 0.35, cry, r * 0.3 * kick, rgb(0.85, 0.95, 1.0, 0.7))
    }

    fun DrawScope.snowflake(cx: Double, cy: Double, r: Double) {
        val f = Path()
        for (k in 0 until 3) {
            val a = k / 3.0 * PI
            f.m(cx - cos(a) * r, cy - sin(a) * r); f.l(cx + cos(a) * r, cy + sin(a) * r)
        }
        stroke(f, Color.White, 1.1 * density)
    }

    /** The melon lobber: a striped melon with a coiled vine arm that flings melon balls overhead. */
    fun DrawScope.lobber(bx: Double, by: Double, s: Double, t: Double, seed: Double, fired: Double) {
        val u = density.toDouble()
        val since = fired
        val swing = if (since < 0.14) -0.55 + (since / 0.14) * 1.55 else if (since < 0.8) 1.0 - (since - 0.14) / 0.66 * 1.55 else -0.55 + sin(t * 1.6 + seed) * 0.05
        for ((i, side) in listOf(-1.0, 1.0, -0.3).withIndex()) {
            val l = Path(); l.m(bx, by)
            l.q(bx + side * s * 0.2, by - s * 0.2, bx + side * s * 0.42, by - s * (if (i == 2) 0.16 else 0.04))
            l.q(bx + side * s * 0.28, by + s * 0.06, bx, by)
            drawPath(l, leaf); stroke(l, leafDark, 1.1 * u)
        }
        val cx = bx; val cy = by - s * 0.22
        val rx = s * 0.28; val ry = s * 0.21
        val melon = ovalAt(cx, cy, rx, ry)
        drawPath(melon, radial(listOf(rgb(0.5, 0.8, 0.3), rgb(0.2, 0.5, 0.12)), cx - rx * 0.3, cy - ry * 0.4, rx * 1.3))
        val stripes = Path()
        for (k in -2..2) {
            val x = cx + k * rx * 0.38
            stripes.m(x, cy - ry * 0.95); stripes.c(x + rx * 0.12, cy - ry * 0.3, x - rx * 0.12, cy + ry * 0.3, x, cy + ry * 0.95)
        }
        clipPath(melon) { stroke(stripes, rgb(0.12, 0.34, 0.08), rx * 0.14) }
        stroke(melon, rgb(0.08, 0.24, 0.05), 1.4 * u)
        eyes(cx + rx * 0.2, cy - ry * 0.15, rx * 0.15, rx * 0.45)
        val smile = Path(); smile.arc(cx + rx * 0.25, cy + ry * 0.2, rx * 0.18, deg(20.0), deg(160.0), moveFirst = true)
        strokeR(smile, ink, 1.4 * u)
        val px = cx - rx * 0.55; val py = cy - ry * 0.75
        val len = s * 0.46
        val tx = px + sin(swing) * len; val ty = py - cos(swing) * len
        val vine = Path(); vine.m(px, py)
        for (i in 1..10) {
            val f = i / 10.0
            val x = px + (tx - px) * f; val y = py + (ty - py) * f
            val wob = sin(i * 1.9) * s * 0.025 * (1 - f)
            vine.l(x + wob * cos(swing), y + wob * sin(swing))
        }
        strokeR(vine, leafDark, s * 0.1); strokeR(vine, leaf, s * 0.055)
        val coil = Path(); coil.arc(px, py, s * 0.05, 0.0, deg(300.0), moveFirst = true)
        stroke(coil, leafDark, 1.6 * u)
        val cup = Path(); cup.arc(tx, ty, s * 0.14, swing + PI * 0.1, swing + PI * 0.9, moveFirst = true); cup.close()
        drawPath(cup, leaf); stroke(cup, leafDark, 1.2 * u)
        if (since > 0.75 || since >= 8) melonBall(tx - sin(swing) * s * 0.03, ty - s * 0.08, s * 0.11)
    }

    fun DrawScope.melonBall(cx: Double, cy: Double, r: Double) {
        val ball = discAt(cx, cy, r)
        drawPath(ball, radial(listOf(rgb(0.55, 0.85, 0.35), rgb(0.2, 0.5, 0.12)), cx - r * 0.3, cy - r * 0.3, r * 1.3))
        val st = Path()
        for (k in -1..1) { st.m(cx + k * r * 0.5, cy - r); st.q(cx + k * r * 0.5 + r * 0.25, cy, cx + k * r * 0.5, cy + r) }
        clipPath(ball) { stroke(st, rgb(0.12, 0.34, 0.08), r * 0.22) }
        stroke(ball, rgb(0.08, 0.24, 0.05), density.toDouble())
    }

    fun DrawScope.wallnut(bx: Double, by: Double, s: Double, health: Double, wince: Boolean) {
        val u = density.toDouble()
        val w = s * 0.62; val h = s * 0.8
        val x0 = bx - w / 2; val y0 = by - h
        val midX = x0 + w / 2; val midY = y0 + h / 2; val maxY = y0 + h
        val shell = Path().apply { ovalD(x0, y0, w, h) }
        drawPath(shell, radial(listOf(rgb(0.9, 0.68, 0.4), rgb(0.66, 0.42, 0.18), rgb(0.45, 0.26, 0.1)), midX - w * 0.12, midY - h * 0.15, h * 0.7))
        stroke(shell, rgb(0.3, 0.16, 0.05), 1.6 * u)
        val ridge = Path(); ridge.m(midX + w * 0.28, y0 + h * 0.2); ridge.q(midX + w * 0.44, midY, midX + w * 0.3, maxY - h * 0.2)
        stroke(ridge, rgb(0.42, 0.24, 0.08, 0.6), 1.2 * u)
        if (health < 0.67) {
            val cr = Path()
            cr.m(midX - w * 0.1, y0 + h * 0.05); cr.l(midX + w * 0.02, y0 + h * 0.2); cr.l(midX - w * 0.08, y0 + h * 0.32); cr.l(midX + w * 0.05, y0 + h * 0.42)
            if (health < 0.34) { cr.m(x0 + w * 0.08, midY + h * 0.1); cr.l(x0 + w * 0.25, midY + h * 0.18); cr.l(x0 + w * 0.2, midY + h * 0.3) }
            stroke(cr, rgb(0.25, 0.12, 0.04), 1.6 * u)
        }
        for (dx in listOf(-0.18, 0.12)) {
            val ex = midX + dx * w - w * 0.05; val ey = y0 + h * 0.4
            ellipse(ex, ey, w * 0.13, h * 0.12, Color.White)
            ellipseStroke(ex, ey, w * 0.13, h * 0.12, ink, u)
            val look = if (wince) 0.0 else -w * 0.04
            circle(ex + look, ey + h * 0.01, w * 0.06, ink)
            if (health < 0.34 || wince) {
                line(ex - w * 0.12, ey - h * 0.13 + (if (dx < 0) h * 0.03 else 0.0), ex + w * 0.12, ey - h * 0.13 + (if (dx < 0) 0.0 else h * 0.03), ink, 1.4 * u, StrokeCap.Butt)
            }
        }
    }

    /** A banana peel: a standing banana slowly unpeeling; armed, the empty peel with drooping flaps. */
    fun DrawScope.peel(bx: Double, by: Double, s: Double, arm: Double, t: Double) {
        val u = density.toDouble()
        val yellow = rgb(1.0, 0.87, 0.25); val deep = rgb(0.9, 0.64, 0.1); val brown = rgb(0.42, 0.25, 0.07)
        val open = min(1.0, max(0.0, arm))
        val armed = arm >= 1
        val rx = bx; val ry = by - s * (if (armed) 0.24 else 0.5 - 0.1 * open)
        ellipse(bx, by, s * (0.28 + 0.14 * open), s * 0.05, Color.Black.op(0.18))
        if (!armed) {
            val fy = ry - s * 0.3 * (1 - open * 0.6)
            val fh = s * 0.32 * (1 - open * 0.6) + (by - ry)
            rrect(rx - s * 0.09, fy, s * 0.18, fh, s * 0.09, rgb(0.99, 0.95, 0.75))
            rrectStroke(rx - s * 0.09, fy, s * 0.18, fh, s * 0.09, rgb(0.8, 0.7, 0.4), u)
        }
        val cup = Path().apply { ovalD(rx - s * 0.13, ry - s * 0.02, s * 0.26, by - ry + s * 0.02) }
        drawPath(cup, hgrad(listOf(yellow, deep), rx - s * 0.13, rx + s * 0.13))
        stroke(cup, brown, 1.2 * u)
        rrect(bx - s * 0.03, by - s * 0.035, s * 0.06, s * 0.05, 2 * u, brown)
        for ((i, side) in listOf(-1.0, -0.45, 0.45, 1.0).withIndex()) {
            val len = s * (if (abs(side) > 0.5) 0.42 else 0.36)
            val up = -PI / 2 + side * 0.12
            val down = if (side < 0) PI * (0.62 + 0.08 * abs(side)) else PI * (0.38 - 0.08 * abs(side))
            val a = up + (down - up) * open
            val fx = rx + side * s * 0.07; val fy = ry + s * 0.02
            val tx = fx + cos(a) * len; val ty = min(by, fy + sin(a) * len)
            val bxx = (fx + tx) / 2 + cos(a - PI / 2) * len * 0.25 * side; val byy = (fy + ty) / 2 - len * 0.18 * open
            val flap = Path()
            flap.m(fx - s * 0.05, fy)
            flap.q(bxx - s * 0.04, byy, tx, ty)
            flap.q(bxx + s * 0.05, byy + s * 0.05, fx + s * 0.05, fy)
            flap.close()
            drawPath(flap, lin(listOf(if (i % 2 == 0) yellow else yellow.mix(deep, 0.3), deep), fx, fy, tx, ty))
            stroke(flap, brown, 1.1 * u)
            circle(tx, ty, s * 0.028, brown)
        }
        if (armed) {
            val glow = 0.5 + 0.5 * sin(t * 4)
            val gx = bx + s * 0.2; val gy = by - s * 0.22
            val gl = Path(); gl.m(gx - s * 0.06, gy); gl.l(gx + s * 0.06, gy); gl.m(gx, gy - s * 0.06); gl.l(gx, gy + s * 0.06)
            stroke(gl, Color.White.op(0.4 + 0.6 * glow), 1.4 * u)
        }
    }

    internal fun ramp(x: Double, a: Double, b: Double): Double { val k = min(1.0, max(0.0, (x - a) / (b - a))); return k * k * (3 - 2 * k) }
    internal fun mixP(p: P, q: P, k: Double) = P(p.x + (q.x - p.x) * k, p.y + (q.y - p.y) * k)
    @Suppress("unused") internal fun dist2(a: P, b: P) = hypot(a.x - b.x, a.y - b.y)
}
