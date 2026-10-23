package com.gogs.bananagame.games.critterduel

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.font.FontWeight
import com.gogs.bananagame.core.*
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** Animation clocks for the field (iOS `CDFx`); times are nowSec() stamps. */
class CDFx {
    var lungeFoe = false
    var lungeAt = -1e9
    var effectType = CDType.NORMAL
    var effectHeals = false
    var effectFromFoe = false
    var effectAt = -1e9
    var hitFoe = false
    var hitAt = -1e9
    var badgeText: String? = null
    var badgeColor = Color.Gray
    var badgeOnFoe = false
    var badgeAt = -1e9
    var faintFoe = false
    var faintAt = -1e9
    var enterAt = -1e9
    var foeFainted = false

    fun use(fromFoe: Boolean, type: CDType, heals: Boolean, at: Double) {
        lungeFoe = fromFoe; lungeAt = if (heals) -1e9 else at
        effectType = type; effectHeals = heals; effectFromFoe = fromFoe; effectAt = at
    }
    fun hit(onFoe: Boolean, mult: Double, crit: Boolean, at: Double) {
        hitFoe = onFoe; hitAt = at
        when {
            mult > 1 -> { badgeText = "×2"; badgeColor = rgb(0.95, 0.38, 0.15) }
            mult < 1 -> { badgeText = "×½"; badgeColor = rgb(0.42, 0.48, 0.62) }
            crit -> { badgeText = "!"; badgeColor = rgb(0.95, 0.75, 0.15) }
            else -> badgeText = null
        }
        if (crit && mult != 1.0 && badgeText != null) badgeText += "!"
        badgeOnFoe = onFoe; badgeAt = at
    }
    fun miss(onFoe: Boolean, at: Double) { badgeText = L("MISS", "TRƯỢT"); badgeColor = gray(0.45); badgeOnFoe = onFoe; badgeAt = at }
    fun faint(foe: Boolean, at: Double) { faintFoe = foe; faintAt = at; if (foe) foeFainted = true }
    fun enter(at: Double) { enterAt = at; foeFainted = false; faintFoe = false; faintAt = -1e9 }
}

object CDArt {
    val ink = rgb(0.1, 0.08, 0.1)

    fun color(t: CDType): Color = when (t) {
        CDType.GRASS -> rgb(0.35, 0.72, 0.28)
        CDType.FIRE -> rgb(0.93, 0.42, 0.16)
        CDType.WATER -> rgb(0.25, 0.52, 0.9)
        CDType.ELECTRIC -> rgb(0.96, 0.76, 0.1)
        CDType.NORMAL -> rgb(0.62, 0.6, 0.48)
    }

    fun hash(n: Double): Double { val v = sin(n * 12.9898) * 43758.5453; return v - floor(v) }

    private fun st(w: Double, round: Boolean = false) =
        Stroke(w.toFloat(), cap = if (round) StrokeCap.Round else StrokeCap.Butt, join = StrokeJoin.Round)

    private fun ovalPath(cx: Double, cy: Double, rx: Double, ry: Double) =
        Path().apply { addOval(androidx.compose.ui.geometry.Rect((cx - rx).f, (cy - ry).f, (cx + rx).f, (cy + ry).f)) }

    private fun DrawScope.eye(cx: Double, cy: Double, r: Double, lookX: Double = 0.0, lookY: Double = 0.0, angry: Boolean = false, left: Boolean = true) {
        ellipse(cx, cy, r * 0.8, r, Color.White)
        ellipseStroke(cx, cy, r * 0.8, r, ink, max(1.0, r * 0.18))
        ellipse(cx + lookX * r * 0.3, cy + r * 0.1 + lookY * r * 0.3, r * 0.48, r * 0.6, ink)
        circle(cx - r * 0.15 + lookX * r * 0.3, cy - r * 0.18, r * 0.2, Color.White)
        if (angry) line(cx - r * 0.9, cy - r * (if (left) 1.25 else 0.85), cx + r * 0.9, cy - r * (if (left) 0.85 else 1.25), ink, max(1.5, r * 0.32))
    }

    private fun DrawScope.flame(bx: Double, by: Double, h: Double, w: Double, t: Double) {
        val k = 1 + 0.12 * sin(t * 13)
        val f = Path()
        f.m(bx - w / 2, by)
        f.q(bx - w * 0.6, by - h * 0.6 * k, bx + w * 0.05, by - h * k)
        f.q(bx + w * 0.65, by - h * 0.45 * k, bx + w / 2, by)
        f.close()
        drawPath(f, lin(listOf(rgb(1.0, 0.92, 0.4), rgb(1.0, 0.5, 0.1)), bx, by, bx, by - h))
        drawPath(f, rgb(0.75, 0.25, 0.05), style = Stroke(density))
    }

    /** A critter with its feet at (bx, by), about `s` tall. */
    fun critter(d: DrawScope, species: Int, bx: Double, by: Double, s: Double, back: Boolean, t: Double) = with(d) {
        when (species) {
            CDDex.BANANO -> banano(bx, by, s, t)
            CDDex.COCONUTTY -> coconutty(bx, by, s, t)
            CDDex.CHILIPEP -> chilipep(bx, by, s, t)
            CDDex.LEMONZAP -> lemonzap(bx, by, s, t)
            CDDex.MELONOX -> melonox(bx, by, s, t)
            CDDex.BLUBBERY -> blubbery(bx, by, s, t)
            else -> pepperoar(bx, by, s, t)
        }
    }

    /** Banano from behind: an upright banana with a leaf tuft by the stem, little arms and feet. */
    private fun DrawScope.banano(bx: Double, by: Double, s: Double, t: Double) {
        val lw = max(1.4 * density, s * 0.022)
        for (dx in listOf(-0.16, 0.12)) ellipse(bx + dx * s, by - s * 0.03, s * 0.1, s * 0.05, rgb(0.5, 0.32, 0.1))
        val body = Path()
        body.m(bx + s * 0.02, by - s * 0.05)
        body.c(bx - s * 0.5, by - s * 0.2, bx - s * 0.36, by - s * 0.86, bx + s * 0.12, by - s * 0.92)
        body.c(bx + s * 0.3, by - s * 0.7, bx + s * 0.34, by - s * 0.16, bx + s * 0.02, by - s * 0.05)
        body.close()
        for ((dx, dy) in listOf(-0.3 to -0.48, 0.26 to -0.44)) {
            ellipse(bx + dx * s, by + dy * s, s * 0.07, s * 0.1, rgb(1.0, 0.85, 0.25))
            ellipseStroke(bx + dx * s, by + dy * s, s * 0.07, s * 0.1, rgb(0.55, 0.38, 0.05), lw)
        }
        drawPath(body, lin(listOf(rgb(1.0, 0.95, 0.5), rgb(1.0, 0.83, 0.18), rgb(0.88, 0.64, 0.08)), bx - s * 0.3, by - s * 0.5, bx + s * 0.3, by - s * 0.4))
        val ridge = Path()
        ridge.m(bx + s * 0.06, by - s * 0.1)
        ridge.c(bx - s * 0.26, by - s * 0.3, bx - s * 0.14, by - s * 0.78, bx + s * 0.1, by - s * 0.86)
        drawPath(ridge, rgb(0.82, 0.6, 0.1, 0.7), style = st(lw))
        for ((dx, dy) in listOf(-0.16 to -0.36, -0.08 to -0.62, -0.2 to -0.5, 0.04 to -0.28))
            ellipse(bx + dx * s, by + dy * s, s * 0.018, s * 0.012, rgb(0.45, 0.3, 0.08))
        drawPath(body, rgb(0.5, 0.34, 0.04), style = st(lw))
        val sx = bx + s * 0.07; val sy = by - s * 1.0; val sw = s * 0.09; val sh = s * 0.12
        rrect(sx, sy, sw, sh, s * 0.02, rgb(0.42, 0.28, 0.08))
        val sway = sin(t * 2.2) * s * 0.02
        for (side in listOf(-1.0, 1.0)) {
            val rx = sx + sw / 2; val ry = sy + s * 0.02
            val leaf = Path()
            leaf.m(rx, ry)
            leaf.q(rx + side * s * 0.05, ry - s * 0.18, rx + side * s * 0.2 + sway, ry - s * 0.12)
            leaf.q(rx + side * s * 0.18, ry - s * 0.02, rx, ry)
            drawPath(leaf, rgb(0.36, 0.74, 0.24))
            drawPath(leaf, rgb(0.15, 0.4, 0.08), style = st(density.toDouble()))
        }
    }

    private fun DrawScope.coconutty(bx: Double, by: Double, s: Double, t: Double) {
        val lw = max(1.3 * density, s * 0.022)
        val cx = bx; val cy = by - s * 0.4
        val r = s * 0.36
        for (dx in listOf(-0.17, 0.17)) ellipse(bx + dx * s, by - s * 0.03, s * 0.09, s * 0.045, rgb(0.35, 0.2, 0.1))
        for (side in listOf(-1.0, 1.0)) {
            val fin = Path()
            fin.m(cx + side * r * 0.85, cy - r * 0.1)
            fin.q(cx + side * r * 1.35, cy - r * 0.35, cx + side * r * 1.45, cy + r * 0.25)
            fin.q(cx + side * r * 1.1, cy + r * 0.4, cx + side * r * 0.85, cy + r * 0.3)
            drawPath(fin, rgb(0.4, 0.7, 0.98))
            drawPath(fin, rgb(0.1, 0.3, 0.6), style = st(lw))
        }
        circle(cx, cy, r, radial(listOf(rgb(0.66, 0.44, 0.24), rgb(0.44, 0.27, 0.12), rgb(0.3, 0.17, 0.07)), cx - r * 0.3, cy - r * 0.3, r * 1.4))
        val fibres = Path()
        for (k in 0 until 14) {
            val a = k / 14.0 * 2 * PI
            val px = cx + cos(a) * r * 0.82; val py = cy + sin(a) * r * 0.82
            fibres.m(px, py); fibres.l(px + r * 0.08, py + r * 0.1)
        }
        drawPath(fibres, rgb(0.25, 0.14, 0.05, 0.6), style = st(density.toDouble()))
        circleStroke(cx, cy, r, rgb(0.2, 0.1, 0.04), lw)
        val tx = cx; val ty = cy - r * 0.78
        ellipse(tx, ty, r * 0.58, r * 0.2, gray(0.96))
        ellipse(tx, ty + r * 0.02, r * 0.46, r * 0.13, rgb(0.35, 0.65, 0.98))
        ellipseStroke(tx, ty, r * 0.58, r * 0.2, rgb(0.2, 0.1, 0.04), lw)
        val hop = abs(sin(t * 2.6)) * r * 0.5
        ellipse(tx + r * 0.15, ty - r * 0.15 - hop, r * 0.07, r * 0.1, rgb(0.45, 0.75, 1.0))
        eye(cx - r * 0.35, cy - r * 0.05, r * 0.22)
        eye(cx + r * 0.35, cy - r * 0.05, r * 0.22)
        val smile = Path(); smile.arc(cx, cy + r * 0.25, r * 0.22, deg(20.0), deg(160.0), moveFirst = true)
        drawPath(smile, ink, style = st(lw, true))
    }

    private fun DrawScope.chilipep(bx: Double, by: Double, s: Double, t: Double) {
        val lw = max(1.3 * density, s * 0.022)
        val body = Path()
        body.m(bx - s * 0.24, by - s * 0.8)
        body.c(bx - s * 0.36, by - s * 0.4, bx - s * 0.1, by - s * 0.04, bx + s * 0.2, by - s * 0.02)
        body.q(bx + s * 0.2, by - s * 0.14, bx + s * 0.06, by - s * 0.16)
        body.c(bx + s * 0.26, by - s * 0.3, bx + s * 0.34, by - s * 0.62, bx + s * 0.24, by - s * 0.8)
        body.close()
        for ((dx, hh) in listOf(-0.13 to 0.28, 0.0 to 0.38, 0.13 to 0.26)) flame(bx + dx * s, by - s * 0.86, s * hh, s * 0.16, t + dx * 9)
        drawPath(body, lin(listOf(rgb(1.0, 0.32, 0.22), rgb(0.8, 0.06, 0.06)), bx - s * 0.2, by - s * 0.7, bx + s * 0.2, by - s * 0.2))
        ellipse(bx - s * 0.12, by - s * 0.6, s * 0.04, s * 0.12, Color.White.op(0.45))
        drawPath(body, rgb(0.35, 0.02, 0.02), style = st(lw))
        val cap = Path()
        cap.m(bx - s * 0.26, by - s * 0.78)
        for (k in 0 until 5) {
            val x = bx - s * 0.26 + s * 0.13 * k
            cap.q(x + s * 0.065, by - s * 0.68, x + s * 0.13, by - s * 0.78)
        }
        cap.q(bx, by - s * 0.94, bx - s * 0.26, by - s * 0.78)
        drawPath(cap, rgb(0.3, 0.66, 0.2))
        drawPath(cap, rgb(0.1, 0.32, 0.06), style = st(lw))
        val ex = bx; val ey = by - s * 0.56
        eye(ex - s * 0.09, ey, s * 0.06, -0.3, 0.0, true, true)
        eye(ex + s * 0.09, ey, s * 0.06, -0.3, 0.0, true, false)
        val grin = Path(); grin.m(ex - s * 0.1, ey + s * 0.12); grin.q(ex, ey + s * 0.2, ex + s * 0.1, ey + s * 0.11)
        drawPath(grin, ink, style = st(lw, true))
        drawPath(polyPath(ex + s * 0.03, ey + s * 0.145, ex + s * 0.055, ey + s * 0.19, ex + s * 0.075, ey + s * 0.14), Color.White)
    }

    private fun DrawScope.lemonzap(bx: Double, by: Double, s: Double, t: Double) {
        val u = density.toDouble()
        val lw = max(1.3 * u, s * 0.022)
        val cx = bx; val cy = by - s * 0.36
        for (dx in listOf(-0.14, 0.14)) ellipse(bx + dx * s, by - s * 0.03, s * 0.08, s * 0.045, rgb(0.75, 0.55, 0.05))
        for (side in listOf(-1.0, 1.0)) {
            val rx = cx + side * s * 0.12; val ry = cy - s * 0.24
            val bolt = polyPath(rx, ry, rx + side * s * 0.1, ry - s * 0.14, rx + side * s * 0.03, ry - s * 0.15, rx + side * s * 0.16, ry - s * 0.34,
                rx + side * s * 0.12, ry - s * 0.2, rx + side * s * 0.18, ry - s * 0.19, rx + side * s * 0.04, ry + s * 0.02)
            drawPath(bolt, rgb(1.0, 0.9, 0.2))
            drawPath(bolt, rgb(0.55, 0.38, 0.0), style = st(lw))
        }
        val lemon = Path()
        lemon.m(cx - s * 0.42, cy)
        lemon.c(cx - s * 0.3, cy - s * 0.38, cx + s * 0.3, cy - s * 0.38, cx + s * 0.42, cy)
        lemon.c(cx + s * 0.3, cy + s * 0.36, cx - s * 0.3, cy + s * 0.36, cx - s * 0.42, cy)
        lemon.close()
        drawPath(lemon, radial(listOf(rgb(1.0, 0.98, 0.6), rgb(1.0, 0.88, 0.15), rgb(0.85, 0.68, 0.05)), cx - s * 0.1, cy - s * 0.12, s * 0.45))
        for (k in 0 until 9) {
            val px = cx + s * (hash(k.toDouble()) - 0.5) * 0.5; val py = cy + s * (hash(k + 3.0) - 0.5) * 0.36
            circle(px + u, py + u, u, rgb(0.8, 0.62, 0.05, 0.6))
        }
        drawPath(lemon, rgb(0.5, 0.36, 0.0), style = st(lw))
        eye(cx - s * 0.11, cy - s * 0.03, s * 0.065, -0.3, 0.0, true, true)
        eye(cx + s * 0.11, cy - s * 0.03, s * 0.065, -0.3, 0.0, true, false)
        val smirk = Path(); smirk.m(cx - s * 0.06, cy + s * 0.1); smirk.q(cx + s * 0.02, cy + s * 0.15, cx + s * 0.08, cy + s * 0.08)
        drawPath(smirk, ink, style = st(lw, true))
        val sparks = Path()
        for (k in 0 until 3) {
            val a = t * 3 + k * 2.1
            val px = cx + cos(a) * s * 0.5; val py = cy + sin(a) * s * 0.3
            sparks.m(px, py); sparks.l(px + 4 * u, py - 5 * u); sparks.l(px + u, py - 6 * u); sparks.l(px + 5 * u, py - 11 * u)
        }
        drawPath(sparks, rgb(1.0, 0.95, 0.5, 0.5 + 0.5 * abs(sin(t * 9))), style = st(1.6 * u))
    }

    private fun DrawScope.melonox(bx: Double, by: Double, s: Double, t: Double) {
        val u = density.toDouble()
        val lw = max(1.3 * u, s * 0.022)
        val cx = bx; val cy = by - s * 0.3
        for (dx in listOf(-0.32, -0.12, 0.12, 0.32)) rrect(bx + dx * s - s * 0.06, by - s * 0.16, s * 0.12, s * 0.16, s * 0.05, rgb(0.25, 0.55, 0.2))
        val face = Path(); face.arc(cx, cy - s * 0.02, s * 0.34, 0.0, PI, moveFirst = true); face.close()
        drawPath(face, vgrad(listOf(rgb(1.0, 0.4, 0.42), rgb(0.88, 0.18, 0.24)), cy, cy + s * 0.3))
        drawPath(face, rgb(0.4, 0.05, 0.08), style = st(lw))
        for ((dx, dy) in listOf(-0.22 to 0.12, -0.1 to 0.2, 0.12 to 0.2, 0.22 to 0.1, 0.0 to 0.26)) ellipse(cx + dx * s, cy + dy * s, 2 * u, 3 * u, ink)
        val shell = Path(); shell.arc(cx, cy, s * 0.4, PI, 2 * PI, moveFirst = true); shell.close()
        drawPath(shell, rgb(0.42, 0.74, 0.3))
        clipPath(shell) {
            for (k in -2..2) {
                val x = cx + k * s * 0.16
                val stp = Path(); stp.m(x, cy); stp.q(x + k * s * 0.05, cy - s * 0.25, x * 0.5 + cx * 0.5, cy - s * 0.42)
                drawPath(stp, rgb(0.12, 0.4, 0.1), style = st(s * 0.06))
            }
        }
        drawPath(shell, rgb(0.08, 0.3, 0.06), style = st(lw))
        for (dx in listOf(-0.12, 0.12)) {
            val lid = Path(); lid.arc(cx + dx * s, cy + s * 0.05, s * 0.05, 0.0, PI, moveFirst = true)
            drawPath(lid, ink, style = st(lw * 1.2, true))
        }
        val snore = sin(t * 1.5) * s * 0.01
        ellipse(cx, cy + s * 0.14 + snore, s * 0.04, s * 0.03, rgb(0.4, 0.05, 0.08))
    }

    private fun DrawScope.blubbery(bx: Double, by: Double, s: Double, t: Double) {
        val lw = max(1.3 * density, s * 0.022)
        val cx = bx; val cy = by - s * 0.38
        val r = s * 0.34
        for (dx in listOf(-0.14, 0.14)) ellipse(bx + dx * s, by - s * 0.03, s * 0.08, s * 0.04, rgb(0.2, 0.2, 0.5))
        circle(cx, cy, r, radial(listOf(rgb(0.45, 0.5, 0.95), rgb(0.22, 0.24, 0.7), rgb(0.12, 0.12, 0.4)), cx - r * 0.35, cy - r * 0.4, r * 1.4))
        ellipse(cx - r * 0.4, cy - r * 0.45, r * 0.25, r * 0.12, Color.White.op(0.35))
        circleStroke(cx, cy, r, rgb(0.06, 0.06, 0.25), lw)
        val ccx = cx; val ccy = cy - r * 0.92
        val pts = (0 until 10).map { k ->
            val a = k / 10.0 * 2 * PI - PI / 2
            val rr = if (k % 2 == 0) r * 0.3 else r * 0.13
            P(ccx + cos(a) * rr, ccy + sin(a) * rr * 0.6)
        }
        val crown = polyPath(pts)
        drawPath(crown, rgb(0.16, 0.14, 0.4))
        drawPath(crown, rgb(0.06, 0.06, 0.2), style = st(density.toDouble()))
        eye(cx - r * 0.35, cy, r * 0.24, -0.3)
        eye(cx + r * 0.32, cy, r * 0.24, -0.3)
        for (dx in listOf(-0.6, 0.58)) ellipse(cx + dx * r, cy + r * 0.35, r * 0.13, r * 0.07, rgb(1.0, 0.55, 0.75, 0.7))
        val m = Path(); m.arc(cx, cy + r * 0.3, r * 0.15, deg(20.0), deg(160.0), moveFirst = true)
        drawPath(m, Color.White, style = st(lw, true))
        for (k in 0 until 2) {
            val a = t * 1.6 + k * PI
            val px = cx + cos(a) * r * 1.35; val py = cy + sin(a) * r * 0.5
            val drop = Path()
            drop.m(px, py - r * 0.16)
            drop.q(px + r * 0.14, py, px, py + r * 0.08)
            drop.q(px - r * 0.14, py, px, py - r * 0.16)
            drawPath(drop, rgb(0.5, 0.78, 1.0, 0.85))
        }
    }

    /** The level-7 boss: a big bell-pepper dragon with leaf wings and stem horns. */
    private fun DrawScope.pepperoar(bx: Double, by: Double, s0: Double, t: Double) {
        val s = s0 * 1.15
        val lw = max(1.4 * density, s * 0.02)
        val cx = bx; val cy = by - s * 0.4
        val flap = sin(t * 4) * s * 0.04
        for (side in listOf(-1.0, 1.0)) {
            val wing = Path()
            wing.m(cx + side * s * 0.25, cy - s * 0.1)
            wing.q(cx + side * s * 0.36, cy - s * 0.45, cx + side * s * 0.62, cy - s * 0.38 - flap)
            wing.q(cx + side * s * 0.62, cy - s * 0.02, cx + side * s * 0.28, cy + s * 0.08)
            drawPath(wing, rgb(0.3, 0.62, 0.2))
            drawPath(wing, rgb(0.1, 0.3, 0.06), style = st(lw))
        }
        for (dx in listOf(-0.16, 0.16)) ellipse(bx + dx * s, by - s * 0.03, s * 0.1, s * 0.045, rgb(0.55, 0.12, 0.05))
        val body = Path()
        body.m(cx - s * 0.3, cy - s * 0.32)
        body.q(cx, cy - s * 0.46, cx + s * 0.3, cy - s * 0.32)
        body.c(cx + s * 0.46, cy - s * 0.1, cx + s * 0.4, cy + s * 0.32, cx + s * 0.18, cy + s * 0.36)
        body.q(cx + s * 0.08, cy + s * 0.44, cx - s * 0.02, cy + s * 0.36)
        body.q(cx - s * 0.12, cy + s * 0.44, cx - s * 0.2, cy + s * 0.36)
        body.c(cx - s * 0.42, cy + s * 0.32, cx - s * 0.46, cy - s * 0.1, cx - s * 0.3, cy - s * 0.32)
        body.close()
        drawPath(body, radial(listOf(rgb(1.0, 0.6, 0.25), rgb(0.95, 0.3, 0.08), rgb(0.65, 0.12, 0.04)), cx - s * 0.12, cy - s * 0.15, s * 0.55))
        val creases = Path()
        creases.m(cx - s * 0.08, cy - s * 0.3); creases.q(cx - s * 0.16, cy, cx - s * 0.06, cy + s * 0.36)
        creases.m(cx + s * 0.1, cy - s * 0.3); creases.q(cx + s * 0.2, cy, cx + s * 0.12, cy + s * 0.36)
        drawPath(creases, rgb(0.6, 0.12, 0.04, 0.6), style = st(lw))
        drawPath(body, rgb(0.35, 0.05, 0.02), style = st(lw))
        for (side in listOf(-1.0, 1.0)) {
            val horn = Path()
            horn.m(cx + side * s * 0.05, cy - s * 0.4)
            horn.q(cx + side * s * 0.02, cy - s * 0.56, cx + side * s * 0.2, cy - s * 0.62)
            drawPath(horn, rgb(0.1, 0.3, 0.06), style = st(s * 0.055 + lw, true))
            drawPath(horn, rgb(0.32, 0.6, 0.18), style = st(s * 0.055, true))
        }
        eye(cx - s * 0.11, cy - s * 0.1, s * 0.065, -0.3, 0.2, true, true)
        eye(cx + s * 0.11, cy - s * 0.1, s * 0.065, -0.3, 0.2, true, false)
        val jaw = Path(); jaw.m(cx - s * 0.12, cy + s * 0.06); jaw.q(cx, cy + s * 0.18, cx + s * 0.12, cy + s * 0.06); jaw.close()
        drawPath(jaw, rgb(0.3, 0.04, 0.02))
        for (dx in listOf(-0.07, 0.07))
            drawPath(polyPath(cx + dx * s - s * 0.02, cy + s * 0.06, cx + dx * s, cy + s * 0.1, cx + dx * s + s * 0.02, cy + s * 0.06), Color.White)
        flame(cx - s * 0.15, cy + s * 0.1, s * 0.14, s * 0.08, t)
    }

    /** The banana Snack (floating effect and the move-button icon). */
    fun banana(d: DrawScope, cx: Double, cy: Double, w: Double) = with(d) {
        val h = w * 0.45
        val ban = Path()
        ban.m(cx - w * 0.5, cy - h * 0.4)
        ban.q(cx - w * 0.02, cy + h * 1.05, cx + w * 0.5, cy - h * 0.5)
        ban.q(cx, cy + h * 0.02, cx - w * 0.5, cy - h * 0.4)
        ban.close()
        drawPath(ban, rgb(1.0, 0.86, 0.2))
        drawPath(ban, rgb(0.5, 0.34, 0.04), style = Stroke((1.4 * density).f))
        rect(cx + w * 0.45, cy - h * 0.6, w * 0.08, h * 0.18, rgb(0.42, 0.28, 0.08))
    }

    private fun DrawScope.effect(type: CDType, heals: Boolean, ax: Double, ay: Double, bx: Double, by: Double, k: Double, s: Double) {
        val u = density.toDouble()
        if (heals) {
            withAlpha(max(0.0, 1 - k)) {
                banana(this, ax, ay - s * 0.3 - k * s * 0.5, s * 0.36)
                for (i in 0 until 6) {
                    val ang = i / 6.0 * 2 * PI + k * 2
                    val qx = ax + cos(ang) * s * 0.4 * (0.5 + k); val qy = ay - s * 0.4 + sin(ang) * s * 0.3
                    line(qx - 4 * u, qy, qx + 4 * u, qy, rgb(0.4, 0.95, 0.4), 2.5 * u, StrokeCap.Butt)
                    line(qx, qy - 4 * u, qx, qy + 4 * u, rgb(0.4, 0.95, 0.4), 2.5 * u, StrokeCap.Butt)
                }
            }
            return
        }
        val travel = min(1.0, k / 0.75)
        fun along(f: Double, wobble: Double = 0.0) = P(ax + (bx - ax) * f, ay + (by - ay) * f - sin(f * PI) * s * 0.25 + wobble)
        when (type) {
            CDType.GRASS -> for (i in 0 until 4) {
                val f = travel - i * 0.12
                if (f <= 0 || f >= 1) continue
                val p = along(f, sin(f * 12 + i) * s * 0.05)
                rot((f * 14 + i) * 180 / PI, p.x, p.y) {
                    ellipse(p.x, p.y, s * 0.07, s * 0.03, rgb(0.4, 0.82, 0.25))
                    ellipseStroke(p.x, p.y, s * 0.07, s * 0.03, rgb(0.12, 0.4, 0.08), u)
                }
            }
            CDType.WATER -> for (i in 0 until 5) {
                val f = travel - i * 0.08
                if (f <= 0 || f >= 1) continue
                val p = along(f, sin(f * 18 + i * 2) * s * 0.06)
                val r = s * (0.05 + 0.015 * (i % 3))
                circle(p.x, p.y, r, rgb(0.55, 0.8, 1.0, 0.75))
                circleStroke(p.x, p.y, r, rgb(0.2, 0.45, 0.9), 1.2 * u)
                circle(p.x - r * 0.35, p.y - r * 0.35, r * 0.25, Color.White)
            }
            CDType.FIRE -> for (i in 0 until 3) {
                val f = travel - i * 0.15
                if (f <= 0 || f >= 1) continue
                val p = along(f)
                val r = s * 0.085
                circle(p.x, p.y, r * 1.6, radial(listOf(rgb(1.0, 0.6, 0.1, 0.6), Color.Transparent), p.x, p.y, r * 1.6))
                circle(p.x, p.y, r, radial(listOf(rgb(1.0, 0.95, 0.6), rgb(1.0, 0.5, 0.1)), p.x, p.y, r))
            }
            CDType.ELECTRIC -> if (k > 0.25 && k < 0.85) {
                val bolt = Path()
                var y = by - s * 1.6
                var x = bx + s * 0.05
                bolt.m(x, y)
                var flip = 1.0
                while (y < by - s * 0.4) { y += s * 0.16; x += flip * s * 0.1; flip = -flip; bolt.l(x, y) }
                drawPath(bolt, rgb(1.0, 0.95, 0.4), style = st(6 * u, true))
                drawPath(bolt, Color.White, style = st(2.5 * u, true))
            }
            CDType.NORMAL -> if (k > 0.25 && k < 0.7) {
                val ccx = bx; val ccy = by - s * 0.4
                val star = polyPath((0 until 12).map { i ->
                    val ang = i / 12.0 * 2 * PI
                    val rr = if (i % 2 == 0) s * 0.3 else s * 0.12
                    P(ccx + cos(ang) * rr, ccy + sin(ang) * rr)
                })
                drawPath(star, Color.White.op(0.9))
                drawPath(star, rgb(1.0, 0.8, 0.2), style = st(2 * u))
            }
        }
    }

    /** The live field: critters with lunges / entrance / faint / hit blink, the move effect, and the badge. */
    fun scene(d: DrawScope, tm: TextMeasurer, you: CDCritter, foe: CDCritter?, fx: CDFx, now: Double) = with(d) {
        val w = size.width.toDouble(); val h = size.height.toDouble()
        val u = density.toDouble()
        val t = now
        val foeS = min(w * 0.36, h * 0.4); val youS = min(w * 0.5, h * 0.58)
        var fX = w * 0.71; var fY = h * 0.44
        var yX = w * 0.25; var yY = h * 1.02
        val lunge = now - fx.lungeAt
        if (lunge < 0.3) {
            val k = sin(PI * lunge / 0.3) * w * 0.07
            if (fx.lungeFoe) { fX -= k; fY += k * 0.5 } else { yX += k; yY -= k * 0.5 }
        }
        val enter = now - fx.enterAt
        if (enter < 0.5) fX += (1 - enter / 0.5) * w * 0.6
        val faint = now - fx.faintAt
        var foeAlpha = 1.0; var youAlpha = 1.0
        if (faint >= 0 && faint < 10) {
            val k = min(1.0, faint / 0.5)
            if (fx.faintFoe) { fY += k * foeS * 0.5; foeAlpha = 1 - k } else { yY += k * youS * 0.5; youAlpha = 1 - k }
        }
        val hit = now - fx.hitAt
        if (hit < 0.45 && (hit * 14).toInt() % 2 == 0) { if (fx.hitFoe) foeAlpha *= 0.25 else youAlpha *= 0.25 }
        val bob = sin(t * 2.4) * h * 0.006
        if (foe != null) withAlpha(foeAlpha) { critter(this, foe.species, fX, fY + bob, foeS, false, t) }
        withAlpha(youAlpha) { critter(this, you.species, yX, yY - bob, youS, true, t) }
        val e = now - fx.effectAt
        if (e < 0.8) {
            val from = if (fx.effectHeals) (if (fx.effectFromFoe) P(fX, fY) else P(yX, yY - youS * 0.5))
                else if (fx.effectFromFoe) P(fX, fY - foeS * 0.45) else P(yX + youS * 0.1, yY - youS * 0.6)
            val to = if (fx.effectFromFoe) P(yX, yY - youS * 0.3) else P(fX, fY)
            effect(fx.effectType, fx.effectHeals, from.x, from.y, to.x, to.y, e / 0.8, if (fx.effectFromFoe) foeS else youS * 0.8)
        }
        val bAge = now - fx.badgeAt
        val badge = fx.badgeText
        if (badge != null && bAge < 1.1) {
            val ax = if (fx.badgeOnFoe) fX + foeS * 0.35 else yX + youS * 0.38
            val ay = if (fx.badgeOnFoe) fY - foeS * 0.95 else yY - youS * 0.9
            val rise = min(1.0, bAge / 0.25) * 10 * u
            val ts = 20 * u
            val tw = textWidth(tm, badge, ts, FontWeight.Black)
            val th = ts * 1.2
            val rw = tw + 18 * u; val rh = th + 6 * u
            val rx = max(4 * u, min(w - rw - 4 * u, ax - tw / 2 - 9 * u))
            val ry = max(4 * u, min(h - rh - 4 * u, ay - rise - th / 2 - 3 * u))
            withAlpha(if (bAge > 0.8) max(0.0, 1 - (bAge - 0.8) / 0.3) else 1.0) {
                rrect(rx, ry, rw, rh, rh / 2, fx.badgeColor)
                rrectStroke(rx, ry, rw, rh, rh / 2, Color.White, 2 * u)
                text(tm, badge, rx + rw / 2, ry + rh / 2, ts, Color.White, FontWeight.Black)
            }
        }
    }

    /** The battle backdrop: sky, a far tree line, the meadow, and the two grass platforms. */
    fun field(d: DrawScope, level: Int) = with(d) {
        val w = size.width.toDouble(); val h = size.height.toDouble()
        val u = density.toDouble()
        val dusk = level >= 6
        val skyTop = if (dusk) rgb(0.98, 0.62, 0.42) else rgb(0.55, 0.8, 0.98)
        val skyBottom = if (dusk) rgb(1.0, 0.85, 0.62) else rgb(0.88, 0.96, 1.0)
        rect(0.0, 0.0, w, h * 0.5, vgrad(listOf(skyTop, skyBottom), 0.0, h * 0.5))
        for ((fx, fy, r0) in listOf(Triple(0.18, 0.1, 22.0), Triple(0.58, 0.06, 18.0), Triple(0.86, 0.16, 15.0))) {
            val r = r0 * u
            for (k in 0 until 3) oval(w * fx + (k - 1) * r * 0.9 - r, h * fy - (if (k == 1) r * 0.4 else 0.0), r * 2, r * 1.3, Color.White.op(0.85))
        }
        val trees = Path()
        trees.m(0.0, h * 0.5)
        var x = 0.0
        var k = 0
        val step = 22 * u
        while (x <= w + 20 * u) {
            val top = h * (0.4 + 0.05 * hash(k.toDouble()))
            trees.q(x + step / 2, top - h * 0.03, x + step, h * 0.47)
            x += step; k++
        }
        trees.l(w, h * 0.52); trees.l(0.0, h * 0.52); trees.close()
        drawPath(trees, if (dusk) rgb(0.32, 0.42, 0.3) else rgb(0.3, 0.58, 0.32))
        rect(0.0, h * 0.5, w, h * 0.5, vgrad(listOf(rgb(0.58, 0.82, 0.42), rgb(0.44, 0.72, 0.3)), h * 0.5, h))
        val tufts = Path()
        for (i in 0 until 26) {
            val px = w * hash(i * 3.7); val py = h * (0.55 + 0.45 * hash(i * 1.9))
            tufts.m(px, py); tufts.l(px - 2 * u, py - 6 * u)
            tufts.m(px, py); tufts.l(px + 2 * u, py - 6 * u)
        }
        drawPath(tufts, rgb(0.28, 0.55, 0.2, 0.6), style = Stroke((1.2 * u).f))
        for ((c, rx, ry) in listOf(Triple(P(w * 0.71, h * 0.445), w * 0.26, h * 0.06), Triple(P(w * 0.25, h * 1.0), w * 0.36, h * 0.09))) {
            ellipse(c.x, c.y + ry * 0.35, rx, ry, rgb(0.3, 0.52, 0.2))
            ellipse(c.x, c.y, rx, ry, vgrad(listOf(rgb(0.62, 0.86, 0.42), rgb(0.46, 0.72, 0.3)), c.y - ry, c.y + ry))
            ellipseStroke(c.x, c.y, rx, ry, rgb(0.25, 0.45, 0.16), 2 * u)
        }
    }

    /** The dark lower screen behind the message box and the moves. */
    fun panel(d: DrawScope) = with(d) {
        val w = size.width.toDouble(); val h = size.height.toDouble()
        val u = density.toDouble()
        rect(0.0, 0.0, w, h, vgrad(listOf(rgb(0.2, 0.24, 0.3), rgb(0.11, 0.13, 0.17)), 0.0, h))
        var y = 0.0
        while (y < h) { line(0.0, y, w, y, Color.White.op(0.03), u, StrokeCap.Butt); y += 6 * u }
        rect(0.0, 0.0, w, 3 * u, rgb(0.88, 0.4, 0.22))
    }
}
