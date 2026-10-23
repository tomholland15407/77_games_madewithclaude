package com.gogs.bananagame.games.lawndefense

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.drawscope.translate
import com.gogs.bananagame.core.*
import com.gogs.bananagame.games.lawndefense.LDZombies.starShape
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

// Lawn Defense's seven bosses (iOS LawnDefenseBosses.swift), their telegraphs, shots and health-bar faces.

object LDBossArt {
    private val ink get() = LDPlants.ink

    /** Where a boss stands on screen. */
    private class Frame(val front: Double, val ground: Double, val top: Double, val cw: Double, val ch: Double) {
        val lanes get() = ground - top
    }

    private fun frame(b: LDBoss, lay: LDLayout): Frame {
        val span = b.kind.span.toDouble()
        return Frame(lay.point(b.x, 0.0).x, lay.point(0.0, b.y + span - 0.06).y, lay.point(0.0, b.y).y, lay.cellW, lay.cellH)
    }

    /** How far into its windup the boss is (0…1), or null. */
    private fun windup(b: LDBoss): Pair<LDBossMove, Double>? {
        val m = b.move ?: return null
        return m to max(0.0, min(1.0, 1 - b.windup / m.windup))
    }

    private fun DrawScope.st(p: Path, c: Color, w: Double, round: Boolean = true) =
        drawPath(p, c, style = Stroke(w.f, cap = if (round) StrokeCap.Round else StrokeCap.Butt, join = StrokeJoin.Round))

    // Drawing a boss

    fun draw(d: DrawScope, b: LDBoss, w: LDWorld, lay: LDLayout) = with(d) {
        val t = w.t
        var dx = 0.0
        var rot = 0.0
        var pivot = P(0.0, 0.0)
        var alpha = 1.0
        val died = b.died
        if (died != null) {
            val age = t - died
            if (age >= 2.8) return@with
            if (age < 0.9) dx = sin(age * 70) * lay.cellW * 0.06
            else {
                val k = min(1.0, (age - 0.9) / 1.1)
                pivot = if (b.kind.span == 1) lay.point(b.x + 0.5, b.y + 0.92) else lay.point(b.x + 2.2, b.y + b.kind.span)
                rot = k * 0.55
                alpha = max(0.0, 1 - max(0.0, age - 1.7) / 1.1)
            }
        }
        val stunned = b.died == null && t < b.stunUntil
        if (stunned) dx += sin(t * 18) * lay.cellW * 0.03
        withAlpha(alpha) {
            translate(dx.f, 0f) {
                rotateRad(rot.f, off(pivot.x, pivot.y)) {
                    tinted(null, if (t - b.hit < 0.06 && b.died == null) 0.1 else 0.0) { figure(b, lay, t) }
                }
            }
        }
        if (died != null) smoke(b, lay, t - died)
        if (stunned) {
            val head = if (b.kind.span == 1) lay.point(b.x + 0.45, b.y - 0.6) else lay.point(b.x + 0.9, b.y - 0.35)
            for (k in 0 until 4) {
                val a = t * 4 + k * 1.57
                starShape(head.x + cos(a) * lay.cellW * 0.45, head.y + sin(a) * lay.cellW * 0.12, lay.cellW * 0.1)
            }
        }
    }

    private fun DrawScope.figure(b: LDBoss, lay: LDLayout, t: Double) {
        when (b.kind) {
            LDBossKind.GROUNDSKEEPER -> groundskeeper(b, lay, t)
            LDBossKind.PHARAOH -> pharaoh(b, frame(b, lay), t)
            LDBossKind.CAPTAIN -> captain(b, frame(b, lay), t)
            LDBossKind.OUTLAW -> locomotive(b, frame(b, lay), t)
            LDBossKind.MAMMOTH -> mammoth(b, frame(b, lay), t)
            LDBossKind.MECH -> mech(b, frame(b, lay), t)
            LDBossKind.MEGABOT -> brainBot(b, frame(b, lay), t)
        }
    }

    /** Smoke and sparks while a beaten boss shakes apart. */
    private fun DrawScope.smoke(b: LDBoss, lay: LDLayout, age: Double) {
        val c = if (b.kind.span == 1) lay.point(b.x + 0.5, b.y - 0.1) else lay.point(b.x + 1.1, b.y + b.kind.span * 0.4)
        withAlpha(max(0.0, 1 - age / 2.6)) {
            for (i in 0 until 9) {
                val a = i * 0.7
                val rise = age * lay.cellW * (0.6 + 0.2 * (i % 3))
                circle(c.x + cos(a * 3) * lay.cellW * 0.9 * LDWorlds.hash(i.toDouble()), c.y - rise - i * lay.cellW * 0.1,
                    lay.cellW * (0.25 + 0.2 * age), gray(0.25 + 0.1 * (i % 3), 0.55))
            }
        }
        if (age < 0.9) for (i in 0 until 5) {
            starShape(c.x + (LDWorlds.hash(i + age) - 0.5) * lay.cellW * 2, c.y + (LDWorlds.hash(i * 2 + age) - 0.5) * lay.cellW * 2, lay.cellW * 0.07)
        }
    }

    /** A thick arm (sleeve then a big hand). */
    private fun DrawScope.limb(ax: Double, ay: Double, hx: Double, hy: Double, w: Double, cover: Color, skin: Color, lw: Double) {
        val ex = (ax + hx) / 2; val ey = (ay + hy) / 2 + w * 0.3
        val arm = Path(); arm.m(ax, ay); arm.l(ex, ey); arm.l(hx, hy)
        st(arm, ink, w + lw); st(arm, skin, w)
        line(ax, ay, ax + (ex - ax) * 0.5, ay + (ey - ay) * 0.5, cover, w * 1.05)
        circle(hx, hy, w * 0.62, ink)
        circle(hx, hy, w * 0.52, skin)
    }

    // The groundskeeper (backyard)

    private fun DrawScope.groundskeeper(b: LDBoss, lay: LDLayout, t: Double) {
        val f = lay.point(b.x + 0.45, b.y + 0.92)
        val H = min(lay.cellH * 1.22, lay.cellW * 1.9) * 1.55
        val walking = b.mode == LDBossMode.WALKING && b.windup <= 0 && b.died == null && t >= b.stunUntil
        val step = if (walking) sin(t * 2.2) else 0.0
        val lw = max(1.4 * density, H * 0.012)
        val skin = rgb(0.55, 0.64, 0.47); val denim = rgb(0.24, 0.38, 0.62); val shirt = rgb(0.88, 0.86, 0.74)
        val hipX = f.x + H * 0.02; val hipY = f.y - H * 0.4 - abs(step) * H * 0.015
        for ((i, s) in listOf(step, -step).withIndex()) {
            val fx = hipX + s * H * 0.09 - H * 0.02 + i * H * 0.07; val fy = f.y - H * 0.03
            val leg = Path(); leg.m(hipX, hipY); leg.l((hipX + fx) / 2 + H * 0.01, (hipY + fy) / 2); leg.l(fx, fy)
            st(leg, ink, H * 0.13 + lw); st(leg, if (i == 0) denim.shade(0.25) else denim, H * 0.13)
            rrect(fx - H * 0.1, fy - H * 0.02, H * 0.15, H * 0.06, H * 0.02, rgb(0.3, 0.18, 0.08))
        }
        val sx = hipX - H * 0.03; val sy = f.y - H * 0.8
        val body = Path()
        body.m(hipX - H * 0.2, hipY + H * 0.04)
        body.c(hipX - H * 0.34, hipY - H * 0.12, sx - H * 0.3, sy + H * 0.1, sx - H * 0.2, sy)
        body.l(sx + H * 0.2, sy)
        body.c(sx + H * 0.28, sy + H * 0.14, hipX + H * 0.26, hipY - H * 0.1, hipX + H * 0.2, hipY + H * 0.04)
        body.close()
        limb(sx + H * 0.14, sy + H * 0.04, sx + H * 0.18, sy + H * 0.34 + step * H * 0.02, H * 0.1, shirt.shade(0.2), skin, lw)
        drawPath(body, shirt)
        oval(sx - H * 0.1, sy + H * 0.08, H * 0.06, H * 0.04, rgb(0.6, 0.55, 0.35, 0.6))
        oval(sx + H * 0.06, sy + H * 0.15, H * 0.05, H * 0.035, rgb(0.6, 0.55, 0.35, 0.6))
        val bib = polyPath(hipX - H * 0.22, hipY - H * 0.08, sx - H * 0.12, sy + H * 0.17, sx + H * 0.12, sy + H * 0.17,
            hipX + H * 0.22, hipY - H * 0.08, hipX + H * 0.2, hipY + H * 0.04, hipX - H * 0.2, hipY + H * 0.04)
        val px = sx - H * 0.08; val py = sy + H * 0.24; val pw = H * 0.16; val ph = H * 0.1
        clipPath(body) {
            drawPath(bib, denim)
            val straps = Path()
            straps.m(sx - H * 0.1, sy + H * 0.17); straps.l(sx - H * 0.13, sy - H * 0.01)
            straps.m(sx + H * 0.1, sy + H * 0.17); straps.l(sx + H * 0.13, sy - H * 0.01)
            st(straps, denim, H * 0.04, false)
            circle(sx - H * 0.1, sy + H * 0.17, H * 0.018, rgb(0.95, 0.8, 0.3))
            circle(sx + H * 0.1, sy + H * 0.17, H * 0.018, rgb(0.95, 0.8, 0.3))
        }
        if (!b.threw) {
            val icx = px + pw / 2 - H * 0.01; val icy = py - H * 0.035
            ellipse(icx, icy, H * 0.045, H * 0.042, skin)
            ellipseStroke(icx, icy, H * 0.045, H * 0.042, ink, lw * 0.7)
            circle(icx - H * 0.015, icy - H * 0.005, H * 0.012, Color.White)
            circle(icx - H * 0.017, icy - H * 0.004, H * 0.005, ink)
            rect(icx - H * 0.05, icy - H * 0.045, H * 0.08, H * 0.02, rgb(0.8, 0.15, 0.1))
        }
        clipPath(body) {
            rrect(px, py, pw, ph, H * 0.01, denim.shade(0.15))
            rrectStroke(px, py, pw, ph, H * 0.01, ink.op(0.6), lw * 0.7)
        }
        stroke(body, ink, lw)
        val hcx = sx - H * 0.05; val hcy = sy - H * 0.08
        val hr = H * 0.1
        ellipse(hcx, hcy, hr, hr * 1.05, radial(listOf(skin.lit(0.15), skin, skin.shade(0.2)), hcx - hr * 0.3, hcy - hr * 0.3, hr * 1.4))
        ellipseStroke(hcx, hcy, hr, hr * 1.05, ink, lw)
        val ex = hcx - hr * 0.42; val ey = hcy - hr * 0.15
        circle(ex, ey, hr * 0.28, Color.White); circleStroke(ex, ey, hr * 0.28, ink, lw * 0.7)
        circle(ex - hr * 0.07, ey + hr * 0.03, hr * 0.1, ink)
        line(ex - hr * 0.35, ey - hr * 0.42, ex + hr * 0.4, ey - hr * 0.22, ink, lw * 1.2, StrokeCap.Butt)
        rrect(hcx - hr * 0.95, hcy + hr * 0.35, hr * 1.1, hr * 0.5, hr * 0.2, skin.shade(0.1))
        rrectStroke(hcx - hr * 0.95, hcy + hr * 0.35, hr * 1.1, hr * 0.5, hr * 0.2, ink, lw * 0.8)
        val teeth = Path()
        for (k in 0 until 3) {
            teeth.m(hcx - hr * 0.85 + k * hr * 0.35, hcy + hr * 0.4); teeth.l(hcx - hr * 0.78 + k * hr * 0.35, hcy + hr * 0.18); teeth.l(hcx - hr * 0.7 + k * hr * 0.35, hcy + hr * 0.4)
        }
        drawPath(teeth, gray(0.95))
        val brimY = hcy - hr * 0.65
        ellipse(hcx, brimY, hr * 2.1, hr * 0.32, rgb(0.92, 0.8, 0.45))
        ellipseStroke(hcx, brimY, hr * 2.1, hr * 0.32, rgb(0.55, 0.42, 0.15), lw * 0.8)
        rrect(hcx - hr * 0.85, brimY - hr * 0.75, hr * 1.7, hr * 0.8, hr * 0.35, rgb(0.95, 0.84, 0.5))
        rrectStroke(hcx - hr * 0.85, brimY - hr * 0.75, hr * 1.7, hr * 0.8, hr * 0.35, rgb(0.55, 0.42, 0.15), lw * 0.8)
        rect(hcx - hr * 0.85, brimY - hr * 0.22, hr * 1.7, hr * 0.16, rgb(0.75, 0.2, 0.15))
        val fray = Path()
        for (k in 0 until 6) { val x = hcx - hr * 2 + k * hr * 0.75; fray.m(x, brimY + hr * 0.2); fray.l(x - hr * 0.1, brimY + hr * 0.42) }
        stroke(fray, rgb(0.7, 0.55, 0.25), lw * 0.6)
        val rest = -0.35; val raised = 1.9; val slam = -0.8
        var angle = rest
        if (b.windup > 0) angle = rest + (raised - rest) * min(1.0, (0.8 - b.windup) / 0.6)
        if (t - b.smashed < 0.25) angle = slam
        val gx = sx - H * 0.14; val gy = sy + H * 0.06
        val hx = gx - H * 0.16 * cos(angle); val hy = gy + H * 0.16 * sin(-angle) + H * 0.1
        val dxx = -cos(angle); val dyy = -sin(angle)
        val endX = hx + dxx * H * 0.55; val endY = hy + dyy * H * 0.55
        line(hx - dxx * H * 0.15, hy - dyy * H * 0.15, endX, endY, ink, H * 0.035 + lw)
        line(hx - dxx * H * 0.15, hy - dyy * H * 0.15, endX, endY, rgb(0.65, 0.45, 0.22), H * 0.035)
        val nx = -dyy; val ny = dxx
        val blade = Path()
        blade.m(endX + nx * H * 0.07, endY + ny * H * 0.07)
        blade.l(endX + dxx * H * 0.2 + nx * H * 0.06, endY + dyy * H * 0.2 + ny * H * 0.06)
        blade.q(endX + dxx * H * 0.3, endY + dyy * H * 0.3, endX + dxx * H * 0.2 - nx * H * 0.06, endY + dyy * H * 0.2 - ny * H * 0.06)
        blade.l(endX - nx * H * 0.07, endY - ny * H * 0.07)
        blade.close()
        drawPath(blade, lin(listOf(gray(0.8), gray(0.5)), endX, endY, endX + dxx * H * 0.25, endY + dyy * H * 0.25))
        stroke(blade, ink, lw)
        limb(sx - H * 0.14, sy + H * 0.04, hx, hy, H * 0.1, shirt, skin, lw)
    }

    // The pharaoh (desert)

    private fun DrawScope.pharaoh(b: LDBoss, f: Frame, t: Double) {
        val u = density.toDouble()
        val cw = f.cw; val L = f.lanes
        val wu = windup(b)
        val bob = sin(t * 1.6) * f.ch * 0.03
        val cx = f.front + cw * 1.05
        val wrap = rgb(0.9, 0.84, 0.68); val wrapLine = rgb(0.6, 0.52, 0.38)
        val gold = rgb(0.98, 0.78, 0.22); val blue = rgb(0.12, 0.28, 0.72)
        val lw = max(1.5 * u, cw * 0.035)
        val waist = f.ground - L * 0.42 + bob
        val shoulders = f.ground - L * 0.82 + bob
        val robe = polyPath(cx - cw * 0.82, f.ground, cx - cw * 0.72, waist, cx + cw * 0.72, waist, cx + cw * 0.82, f.ground)
        drawPath(robe, wrap.shade(0.08))
        clipPath(robe) {
            val bands = Path()
            var y = waist + L * 0.05
            while (y < f.ground) { bands.m(cx - cw * 0.62, y); bands.l(cx + cw * 0.62, y - L * 0.03); y += L * 0.06 }
            stroke(bands, wrapLine, u)
            rect(cx - cw * 0.12, waist, cw * 0.24, f.ground - waist, vgrad(listOf(gold, blue, gold, blue, gold), waist, f.ground))
        }
        stroke(robe, ink, lw)
        val torso = polyPath(cx - cw * 0.72, waist, cx - cw * 1.0, shoulders, cx + cw * 1.0, shoulders, cx + cw * 0.72, waist)
        drawPath(torso, wrap)
        clipPath(torso) {
            val tb = Path()
            var y = shoulders
            while (y < waist) { tb.m(cx - cw, y + L * 0.02); tb.l(cx + cw, y - L * 0.02); y += L * 0.055 }
            stroke(tb, wrapLine, u)
        }
        stroke(torso, ink, lw)
        rect(cx - cw * 0.76, waist - L * 0.03, cw * 1.52, L * 0.05, gold)
        val collar = Path(); collar.arc(cx, shoulders, cw * 0.78, 0.0, PI, moveFirst = true); collar.close()
        drawPath(collar, gold)
        for ((k, col) in listOf(blue, rgb(0.8, 0.15, 0.15), blue).withIndex()) {
            val ring = Path(); ring.arc(cx, shoulders, cw * (0.3 + k * 0.17), deg(5.0), deg(175.0), moveFirst = true)
            st(ring, col, cw * 0.07, false)
        }
        stroke(collar, ink, lw)
        var raise = 0.0
        if (wu != null) {
            val (m, p) = wu
            raise = if (m == LDBossMove.GRAVES) (if (p < 0.85) p / 0.85 else 1 - (p - 0.85) / 0.15 * 1.2) else if (m == LDBossMove.AMBUSH) min(1.0, p * 1.5) else 0.3 * p
        }
        val fsx = cx - cw * 0.84; val fsy = shoulders + L * 0.05
        val fhx = fsx - cw * 0.35; val fhy = fsy + L * 0.2 - raise * L * 0.45
        val bsx = cx + cw * 0.84; val bsy = shoulders + L * 0.05
        val bRaise = if (wu?.first == LDBossMove.AMBUSH) raise else 0.0
        limb(bsx, bsy, bsx + cw * 0.3, bsy + L * 0.22 - bRaise * L * 0.5, cw * 0.36, wrap, wrap, lw)
        val staff = Path()
        staff.m(fhx, fhy + L * 0.32); staff.l(fhx, fhy - L * 0.32)
        staff.arc(fhx - cw * 0.14, fhy - L * 0.32, cw * 0.14, 0.0, deg(200.0), clockwise = true)
        st(staff, ink, cw * 0.1 + lw)
        drawPath(staff, vgrad(listOf(gold, blue, gold, blue, gold, blue), fhy - L * 0.4, fhy + L * 0.32), style = Stroke((cw * 0.1).f, cap = StrokeCap.Round))
        limb(fsx, fsy, fhx, fhy, cw * 0.36, wrap, wrap, lw)
        val hcx = cx - cw * 0.05; val hcy = shoulders - L * 0.15
        val hr = cw * 0.44
        val nemes = Path()
        nemes.m(hcx - hr * 1.0, hcy - hr * 0.7)
        nemes.q(hcx, hcy - hr * 1.6, hcx + hr * 1.0, hcy - hr * 0.7)
        nemes.l(hcx + hr * 1.45, shoulders + L * 0.1); nemes.l(hcx + hr * 0.75, shoulders + L * 0.12)
        nemes.l(hcx + hr * 0.7, hcy + hr * 0.4); nemes.l(hcx - hr * 0.7, hcy + hr * 0.4)
        nemes.l(hcx - hr * 0.75, shoulders + L * 0.12); nemes.l(hcx - hr * 1.45, shoulders + L * 0.1)
        nemes.close()
        drawPath(nemes, gold)
        clipPath(nemes) {
            val stp = Path()
            var y = hcy - hr * 1.6
            while (y < shoulders + L * 0.12) { stp.rectD(hcx - hr * 1.6, y, hr * 3.2, hr * 0.13); y += hr * 0.27 }
            drawPath(stp, blue)
        }
        stroke(nemes, ink, lw)
        val face = ovalAt(hcx, hcy, hr * 0.62, hr * 0.72)
        drawPath(face, wrap)
        clipPath(face) {
            val fb = Path()
            var y = hcy - hr
            while (y < hcy + hr) { fb.m(hcx - hr, y + hr * 0.1); fb.l(hcx + hr, y - hr * 0.08); y += hr * 0.24 }
            stroke(fb, wrapLine, u)
        }
        stroke(face, ink, lw)
        val glow = 0.6 + 0.4 * sin(t * 3) + (if (wu != null) 0.4 else 0.0)
        for (dx in listOf(-0.26, 0.22)) {
            val ex = hcx + dx * hr; val ey = hcy - hr * 0.12
            circle(ex, ey, hr * 0.3, radial(listOf(rgb(0.6, 1.0, 0.4, min(1.0, glow)), Color.Transparent), ex, ey, hr * 0.3))
            ellipse(ex, ey, hr * 0.12, hr * 0.08, rgb(0.75, 1.0, 0.5))
        }
        rrect(hcx - hr * 0.13, hcy + hr * 0.62, hr * 0.26, hr * 0.55, hr * 0.08, gold)
        rrectStroke(hcx - hr * 0.13, hcy + hr * 0.62, hr * 0.26, hr * 0.55, hr * 0.08, ink, lw * 0.8)
        rect(hcx - hr * 0.72, hcy - hr * 0.62, hr * 1.44, hr * 0.14, gold)
        circle(hcx, hcy - hr * 0.72, hr * 0.15, rgb(0.2, 0.75, 0.6))
        circleStroke(hcx, hcy - hr * 0.72, hr * 0.15, ink, lw * 0.7)
        if (wu != null && (wu.first == LDBossMove.AMBUSH || wu.first == LDBossMove.GRAVES)) {
            withAlpha(wu.second) {
                for (k in 0 until 10) {
                    val a = t * 5 + k * 0.63
                    val r = cw * (0.9 + 0.3 * (k % 3))
                    circle(cx + cos(a) * r, waist + sin(a) * r * 0.5, cw * 0.05, rgb(0.92, 0.78, 0.5))
                }
            }
        }
    }

    // The captain (pirate ship)

    private fun DrawScope.captain(b: LDBoss, f: Frame, t: Double) {
        val u = density.toDouble()
        val cw = f.cw; val L = f.lanes
        val wu = windup(b)
        val rock = sin(t * 1.4) * f.ch * 0.03
        val deckY = f.ground - L * 0.5 + rock
        val wood = rgb(0.42, 0.24, 0.12); val dark = rgb(0.25, 0.13, 0.05); val gold = rgb(0.9, 0.72, 0.28)
        val lw = max(1.5 * u, cw * 0.035)
        val x0 = f.front
        val mastX = x0 + cw * 1.9
        rect(mastX - cw * 0.07, f.top - f.ch * 0.9, cw * 0.14, deckY - f.top + f.ch * 0.9, rgb(0.5, 0.32, 0.16))
        val sail = Path()
        sail.m(mastX - cw * 0.05, f.top - f.ch * 0.75)
        sail.q(mastX - cw * 1.0, (f.top + deckY) / 2, mastX - cw * 0.05, deckY - L * 0.2)
        sail.close()
        drawPath(sail, rgb(0.95, 0.9, 0.78)); stroke(sail, rgb(0.6, 0.52, 0.4), 1.2 * u)
        rect(mastX - cw * 0.45, (f.top + deckY) / 2 - cw * 0.1, cw * 0.18, cw * 0.15, rgb(0.8, 0.7, 0.5))
        val ftx = mastX; val fty = f.top - f.ch * 0.9
        drawPath(polyPath(ftx, fty, ftx - cw * 0.55, fty + cw * 0.12 + sin(t * 5) * cw * 0.05, ftx, fty + cw * 0.3), rgb(0.75, 0.1, 0.1))
        val hull = Path()
        hull.m(x0 + cw * 0.15, deckY)
        hull.q(x0 - cw * 0.1, deckY - L * 0.02, x0 - cw * 0.35, deckY - L * 0.12)
        hull.q(x0 - cw * 0.2, f.ground - L * 0.1, x0 + cw * 0.55, f.ground + rock)
        hull.l(x0 + cw * 3.4, f.ground + rock)
        hull.l(x0 + cw * 3.4, deckY)
        hull.close()
        drawPath(hull, vgrad(listOf(wood.lit(0.1), wood, dark), deckY, f.ground))
        clipPath(hull) {
            val planks = Path()
            var y = deckY + L * 0.08
            while (y < f.ground) { planks.m(x0 - cw, y); planks.l(x0 + cw * 4, y); y += L * 0.075 }
            stroke(planks, dark.op(0.6), u)
            rect(x0 - cw, deckY + L * 0.25, cw * 5, L * 0.035, gold)
        }
        stroke(hull, ink, lw)
        var kick = 0.0
        if (wu != null && wu.first == LDBossMove.BOMBARD) {
            val p = wu.second
            kick = if (p > 0.45) min(1.0, (p - 0.45) / 0.1) * max(0.0, 1 - (p - 0.55) / 0.45) else 0.0
        }
        val portX = x0 + cw * 0.35; val portY = deckY + L * 0.09; val portW = cw * 0.42; val portH = L * 0.12
        rrect(portX, portY, portW, portH, 3 * u, gray(0.08))
        val bx = portX - cw * 0.55 + kick * cw * 0.2; val by = portY + portH / 2 - L * 0.035; val bw = cw * 0.7; val bh = L * 0.07
        rrect(bx, by, bw, bh, L * 0.03, vgrad(listOf(gray(0.45), gray(0.15)), by, by + bh))
        rrect(bx - cw * 0.06, by - L * 0.012, cw * 0.12, bh + L * 0.024, 2 * u, gray(0.2))
        if (kick > 0.2) withAlpha(kick) {
            for (k in 0 until 4) circle(bx - cw * (0.15 + k * 0.12), by + bh / 2 - (k % 2) * cw * 0.08, cw * (0.14 + k * 0.03), gray(0.85))
        }
        rect(x0 + cw * 0.1, deckY - L * 0.06, cw * 3.3, L * 0.03, dark)
        val posts = Path()
        var x = x0 + cw * 0.2
        while (x < x0 + cw * 3.4) { posts.rectD(x, deckY - L * 0.06, cw * 0.06, L * 0.06); x += cw * 0.3 }
        drawPath(posts, wood.lit(0.15))
        val cx = x0 + cw * 1.05
        val coat = rgb(0.7, 0.1, 0.12); val skin = rgb(0.58, 0.66, 0.5)
        val shY = deckY - L * 0.32
        val body = polyPath(cx - cw * 0.42, deckY - L * 0.04, cx - cw * 0.36, shY, cx + cw * 0.36, shY, cx + cw * 0.42, deckY - L * 0.04)
        drawPath(body, coat)
        rect(cx - cw * 0.07, shY, cw * 0.14, deckY - shY - L * 0.04, gray(0.92))
        for (k in 0 until 3) oval(cx - cw * 0.16, shY + L * 0.04 + k * L * 0.06, cw * 0.05, cw * 0.05, gold)
        stroke(body, ink, lw)
        var point = 0.0
        if (wu != null && (wu.first == LDBossMove.AMBUSH || wu.first == LDBossMove.SUMMON)) point = min(1.0, wu.second * 2)
        val hhx = cx - cw * 0.55 - point * cw * 0.25; val hhy = shY + L * 0.12 - point * L * 0.16
        limb(cx - cw * 0.3, shY + L * 0.03, hhx, hhy, cw * 0.16, coat, coat, lw)
        val hook = Path(); hook.arc(hhx - cw * 0.06, hhy - cw * 0.06, cw * 0.09, deg(60.0), deg(330.0), moveFirst = true)
        st(hook, gray(0.8), cw * 0.04)
        val hx = cx - cw * 0.05; val hy = shY - L * 0.09
        val hr = cw * 0.28
        ellipse(hx, hy, hr, hr * 1.05, skin); ellipseStroke(hx, hy, hr, hr * 1.05, ink, lw)
        val beard = Path()
        beard.m(hx - hr * 0.95, hy + hr * 0.1)
        beard.q(hx - hr * 0.3, hy + hr * 1.6, hx + hr * 0.6, hy + hr * 0.2)
        beard.q(hx - hr * 0.2, hy + hr * 0.6, hx - hr * 0.95, hy + hr * 0.1)
        drawPath(beard, rgb(0.2, 0.12, 0.08))
        val ex = hx - hr * 0.45; val ey = hy - hr * 0.2
        circle(ex, ey, hr * 0.26, Color.White); circleStroke(ex, ey, hr * 0.26, ink, u)
        circle(ex - hr * 0.08, ey, hr * 0.1, ink)
        ellipse(hx + hr * 0.2, hy - hr * 0.2, hr * 0.22, hr * 0.2, ink)
        line(hx - hr * 0.9, hy - hr * 0.6, hx + hr * 0.95, hy + hr * 0.05, ink, 1.4 * u, StrokeCap.Butt)
        val brim = hy - hr * 0.62
        val tri = Path()
        tri.m(hx - hr * 1.5, brim + hr * 0.05)
        tri.q(hx, brim - hr * 1.6, hx + hr * 1.4, brim)
        tri.q(hx, brim - hr * 0.35, hx - hr * 1.5, brim + hr * 0.05)
        drawPath(tri, gray(0.1)); stroke(tri, gold, 1.6 * u)
        val ax = hx; val ay = brim - hr * 0.55
        val anchor = Path()
        anchor.m(ax, ay - hr * 0.18); anchor.l(ax, ay + hr * 0.16)
        anchor.m(ax - hr * 0.12, ay + hr * 0.06); anchor.q(ax, ay + hr * 0.28, ax + hr * 0.12, ay + hr * 0.06)
        anchor.m(ax - hr * 0.08, ay - hr * 0.08); anchor.l(ax + hr * 0.08, ay - hr * 0.08)
        stroke(anchor, gold, 1.4 * u)
    }

    // The outlaw's locomotive (frontier)

    private fun DrawScope.locomotive(b: LDBoss, f: Frame, t: Double) {
        val u = density.toDouble()
        val cw = f.cw; val L = f.lanes
        val wu = windup(b)
        val charging = b.mode == LDBossMode.CHARGING; val backing = b.mode == LDBossMode.RETREATING
        val rumble = (if (wu?.first == LDBossMove.CHARGE) sin(t * 50) * cw * 0.03 * wu.second else 0.0) + (if (charging) sin(t * 40) * cw * 0.02 else 0.0)
        val x0 = f.front + rumble
        val lw = max(1.5 * u, cw * 0.035)
        val black = gray(0.12); val brass = rgb(0.86, 0.68, 0.28); val red = rgb(0.72, 0.12, 0.1)
        val stx = x0 + cw * 0.85; val sty = f.ground - L * 0.95
        withAlpha(if (charging) 0.9 else 0.65) {
            for (k in 0 until 6) {
                val age = (t * (if (charging) 2.4 else 0.9) + k / 6.0) % 1.0
                circle(stx + age * cw * (if (charging) 2.6 else 1.2), sty - age * L * 0.35, cw * (0.14 + age * 0.3), gray(0.75 - age * 0.3))
            }
        }
        val cabX = x0 + cw * 2.05; val cabY = f.ground - L * 1.02; val cabW = cw * 1.1; val cabH = L * 0.82
        rect(cabX, cabY, cabW, cabH, red)
        rect(cabX - cw * 0.08, cabY - L * 0.06, cabW + cw * 0.16, L * 0.07, black)
        val wx = cabX + cw * 0.15; val wy = cabY + L * 0.1; val ww = cw * 0.55; val wh = L * 0.24
        rect(wx, wy, ww, wh, rgb(0.2, 0.15, 0.12))
        rectStroke(cabX, cabY, cabW, cabH, ink, lw)
        val hx = wx + ww / 2 - cw * 0.05; val hy = wy + wh / 2
        val hr = cw * 0.17
        circle(hx, hy, hr, rgb(0.58, 0.66, 0.5)); circleStroke(hx, hy, hr, ink, 1.2 * u)
        rect(hx - hr, hy + hr * 0.15, hr * 2, hr * 0.6, rgb(0.75, 0.15, 0.12))
        circle(hx - hr * 0.4, hy - hr * 0.2, hr * 0.25, Color.White)
        circle(hx - hr * 0.45, hy - hr * 0.18, hr * 0.1, ink)
        ellipse(hx, hy - hr * 0.75, hr * 1.6, hr * 0.25, rgb(0.45, 0.28, 0.14))
        rrect(hx - hr * 0.75, hy - hr * 1.5, hr * 1.5, hr * 0.8, hr * 0.3, rgb(0.52, 0.33, 0.17))
        if (wu != null && wu.first == LDBossMove.BOMBARD) {
            val p = wu.second
            val handX = hx - hr * 1.2; val handY = hy - hr * (0.5 + 1.8 * min(1.0, p * 1.4))
            line(hx - hr * 0.6, hy + hr * 0.6, handX, handY, rgb(0.58, 0.66, 0.5), hr * 0.4)
            if (p < 0.55) dynamite(this, handX, handY - hr * 0.3, cw * 0.35, -0.4, t)
        }
        val bX = x0 + cw * 0.38; val bY = f.ground - L * 0.82; val bW = cw * 1.8; val bH = L * 0.46
        rrect(bX, bY, bW, bH, L * 0.2, vgrad(listOf(gray(0.35), black, gray(0.05)), bY, bY + bH))
        for (k in 0 until 3) rect(bX + bW * (0.25 + k * 0.25) - cw * 0.04, bY, cw * 0.08, bH, brass)
        rrectStroke(bX, bY, bW, bH, L * 0.2, ink, lw)
        ellipse(bX + bW * 0.62, bY, cw * 0.2, L * 0.07, brass)
        val funnel = polyPath(stx - cw * 0.12, bY + L * 0.02, stx - cw * 0.12, sty + L * 0.12, stx - cw * 0.26, sty, stx + cw * 0.26, sty,
            stx + cw * 0.12, sty + L * 0.12, stx + cw * 0.12, bY + L * 0.02)
        drawPath(funnel, black); stroke(funnel, ink, lw)
        rect(stx - cw * 0.27, sty - L * 0.02, cw * 0.54, L * 0.03, brass)
        val fx = bX + cw * 0.05; val fy = bY + bH / 2
        ellipse(fx, fy, cw * 0.14, L * 0.22, gray(0.2))
        ellipseStroke(fx, fy, cw * 0.14, L * 0.22, brass, 2 * u)
        val lx = fx - cw * 0.05; val ly = bY - L * 0.05
        val lit = wu?.first == LDBossMove.CHARGE || charging
        val lr = cw * (if (lit) 0.4 else 0.22)
        circle(lx, ly, lr, radial(listOf(rgb(1.0, 0.95, 0.6, if (lit) 0.9 else 0.5), Color.Transparent), lx, ly, lr))
        rrect(lx - cw * 0.1, ly - cw * 0.09, cw * 0.2, cw * 0.18, 3 * u, brass)
        circle(lx, ly, cw * 0.06, rgb(1.0, 0.95, 0.6))
        val catcher = polyPath(x0 - cw * 0.05, f.ground, x0 + cw * 0.45, f.ground - L * 0.34, x0 + cw * 0.5, f.ground)
        drawPath(catcher, red)
        val bars = Path()
        for (k in 1 until 5) {
            val p = k / 5.0
            bars.m(x0 - cw * 0.05 + p * cw * 0.5, f.ground - p * L * 0.34); bars.l(x0 - cw * 0.05 + p * cw * 0.55, f.ground)
        }
        stroke(bars, ink.op(0.7), 1.2 * u)
        stroke(catcher, ink, lw)
        val spin = b.x * -2.2 + (if (charging || backing) t * (if (charging) -14 else 8) else 0.0)
        val big = L * 0.17
        for ((wxx, r) in listOf(x0 + cw * 0.75 to L * 0.1, x0 + cw * 1.45 to big, x0 + cw * 2.2 to big, x0 + cw * 2.85 to L * 0.12)) {
            val cy = f.ground - r
            circle(wxx, cy, r, red); circleStroke(wxx, cy, r, ink, lw)
            val spokes = Path()
            for (k in 0 until 6) { val a = spin + k * PI / 3; spokes.m(wxx, cy); spokes.l(wxx + cos(a) * r * 0.85, cy + sin(a) * r * 0.85) }
            stroke(spokes, rgb(0.4, 0.05, 0.05), 1.4 * u)
            circle(wxx, cy, r * 0.25, brass)
        }
        line(x0 + cw * 1.45 + cos(spin) * big * 0.6, f.ground - big + sin(spin) * big * 0.6,
            x0 + cw * 2.2 + cos(spin) * big * 0.6, f.ground - big + sin(spin) * big * 0.6, gray(0.75), cw * 0.07)
        if (charging) {
            val lines = Path()
            for (k in 0 until 4) {
                val y = f.ground - L * (0.15 + k * 0.22)
                lines.m(x0 + cw * 3.4, y); lines.l(x0 + cw * (4.4 + (k % 2) * 0.4), y)
            }
            stroke(lines, Color.White.op(0.6), 2 * u)
        }
    }

    fun dynamite(d: DrawScope, cx: Double, cy: Double, s: Double, angle: Double, t: Double) = with(d) {
        translate(cx.f, cy.f) {
            rotateRad(angle.f, Offset.Zero) {
                rrect(-s * 0.12, -s * 0.4, s * 0.24, s * 0.8, s * 0.05, rgb(0.85, 0.15, 0.12))
                rrectStroke(-s * 0.12, -s * 0.4, s * 0.24, s * 0.8, s * 0.05, ink, density.toDouble())
                rect(-s * 0.12, -s * 0.1, s * 0.24, s * 0.08, rgb(0.95, 0.85, 0.6))
                val fuse = Path(); fuse.m(0.0, -s * 0.4); fuse.q(-s * 0.08, -s * 0.55, s * 0.12, -s * 0.6)
                stroke(fuse, gray(0.3), 1.2 * density)
                circle(s * 0.12, -s * 0.6, s * (0.08 + 0.04 * abs(sin(t * 30))), rgb(1.0, 0.85, 0.3))
            }
        }
    }

    // The woolly mammoth (glacier)

    private fun DrawScope.mammoth(b: LDBoss, f: Frame, t: Double) {
        val u = density.toDouble()
        val cw = f.cw; val L = f.lanes
        val wu = windup(b)
        val breathe = sin(t * 1.5) * L * 0.01
        val x0 = f.front
        val lw = max(1.5 * u, cw * 0.035)
        val fur = rgb(0.5, 0.32, 0.2); val furDark = rgb(0.32, 0.19, 0.1)
        val bx = x0 + cw * 1.45; val by = f.ground - L * 0.5 + breathe
        val brx = cw * 1.3; val bry = L * 0.36
        for ((i, lx) in listOf(x0 + cw * 2.3, x0 + cw * 0.9, x0 + cw * 2.0, x0 + cw * 0.65).withIndex()) {
            val rx = lx - cw * 0.22; val rw = cw * 0.44; val rh = f.ground - by
            rrect(rx, by, rw, rh, cw * 0.15, if (i < 2) furDark else fur)
            rrectStroke(rx, by, rw, rh, cw * 0.15, ink, lw)
            for (k in 0 until 3) oval(rx + cw * 0.04 + k * cw * 0.13, f.ground - cw * 0.09, cw * 0.1, cw * 0.07, rgb(0.92, 0.88, 0.78))
        }
        val shag = polyPath((0..40).map { i ->
            val a = i / 40.0 * 2 * PI
            val wob = if (i % 2 == 0) 1.0 else 0.92
            P(bx + cos(a) * brx * wob, by + sin(a) * bry * wob)
        })
        drawPath(shag, radial(listOf(fur.lit(0.2), fur, furDark), bx - brx * 0.3, by - bry * 0.4, brx * 1.3))
        stroke(shag, ink, lw)
        val hair = Path()
        for (k in 0 until 14) {
            val hx = bx - brx * 0.8 + k * brx * 0.12; val hy = by - bry * 0.2 + LDWorlds.hash(k.toDouble()) * bry * 0.8
            hair.m(hx, hy); hair.l(hx - cw * 0.04, hy + L * 0.06)
        }
        stroke(hair, furDark, 1.2 * u)
        for (k in 0 until 10) oval(bx - brx * 0.7 + LDWorlds.hash(k * 3.1) * brx * 1.4, by - bry * 0.9 + LDWorlds.hash(k * 1.3) * bry * 0.6, 3 * u, 3 * u, Color.White.op(0.85))
        val sx = bx + brx * 0.1; val sy = by - bry * 0.95
        val rh = L * 0.28
        val tunic = polyPath(sx - rh * 0.3, sy + rh * 0.05, sx - rh * 0.22, sy - rh * 0.55, sx + rh * 0.22, sy - rh * 0.55, sx + rh * 0.3, sy + rh * 0.05)
        drawPath(tunic, rgb(0.75, 0.55, 0.3))
        for (k in 0 until 3) oval(sx - rh * 0.15 + k * rh * 0.12, sy - rh * 0.4 + (k % 2) * rh * 0.15, rh * 0.08, rh * 0.06, rgb(0.4, 0.25, 0.12))
        stroke(tunic, ink, 1.2 * u)
        val rhx = sx - rh * 0.05; val rhy = sy - rh * 0.74
        ellipse(rhx, rhy, rh * 0.22, rh * 0.23, rgb(0.6, 0.7, 0.62)); ellipseStroke(rhx, rhy, rh * 0.22, rh * 0.23, ink, 1.2 * u)
        val mop = Path()
        mop.m(rhx - rh * 0.26, rhy - rh * 0.02)
        mop.q(rhx, rhy - rh * 0.5, rhx + rh * 0.26, rhy - rh * 0.05)
        mop.q(rhx, rhy - rh * 0.14, rhx - rh * 0.26, rhy - rh * 0.02)
        drawPath(mop, rgb(0.25, 0.15, 0.08))
        val rex = rhx - rh * 0.09; val rey = rhy + rh * 0.02
        circle(rex, rey, rh * 0.07, Color.White); circleStroke(rex, rey, rh * 0.07, ink, 0.8 * u)
        circle(rex - rh * 0.02, rey, rh * 0.03, ink)
        rrect(rhx - rh * 0.14, rhy + rh * 0.1, rh * 0.16, rh * 0.06, u, rgb(0.2, 0.08, 0.08))
        val swing = if (wu != null) sin(t * 10) * 0.3 else 0.0
        val chx = sx - rh * 0.4; val chy = sy - rh * 0.6
        line(chx, chy, chx - rh * 0.25 + swing * rh, chy - rh * 0.6, rgb(0.95, 0.92, 0.82), rh * 0.1)
        circle(chx - rh * 0.25 + swing * rh, chy - rh * 0.62, rh * 0.09, rgb(0.95, 0.92, 0.82))
        val hx = x0 + cw * 0.42; val hy = f.ground - L * 0.7 + breathe
        val hr = L * 0.22
        ellipse(hx, hy, hr * 1.05, hr, radial(listOf(fur.lit(0.2), fur), hx - hr * 0.3, hy - hr * 0.3, hr * 1.3))
        ellipseStroke(hx, hy, hr * 1.05, hr, ink, lw)
        ellipse(hx + hr * 0.7, hy - hr * 0.05, hr * 0.3, hr * 0.42, furDark)
        val ex = hx - hr * 0.35; val ey = hy - hr * 0.2
        circle(ex, ey, hr * 0.12, Color.White)
        circle(ex - hr * 0.03, ey, hr * 0.06, ink)
        line(ex - hr * 0.2, ey - hr * 0.2, ex + hr * 0.22, ey - hr * 0.08, ink, 1.8 * u, StrokeCap.Butt)
        val rx = hx - hr * 0.75; val ry = hy + hr * 0.15
        val trunk = Path(); trunk.m(rx, ry)
        val tip: P
        if (wu != null && wu.first == LDBossMove.FREEZE) {
            val k = min(1.0, wu.second * 1.6)
            tip = P(rx - hr * (0.6 + 0.7 * k), ry + hr * (0.9 - 1.3 * k))
            trunk.q(rx - hr * 0.7, ry + hr * 0.6, tip.x, tip.y)
        } else if (wu != null && wu.first == LDBossMove.ROLL) {
            tip = P(rx - hr * 0.5, f.ground - L * 0.1)
            trunk.q(rx - hr * 0.9, ry + hr * 0.4, tip.x, tip.y)
        } else {
            tip = P(rx - hr * 0.2 + sin(t * 1.2) * hr * 0.1, f.ground - L * 0.12)
            trunk.q(rx - hr * 0.55, ry + hr * 0.7, tip.x, tip.y)
        }
        st(trunk, ink, hr * 0.4 + lw); st(trunk, fur, hr * 0.4)
        for (k in 0 until 2) {
            val tx = hx - hr * (0.45 - k * 0.15); val ty = hy + hr * 0.45
            val tusk = Path(); tusk.m(tx, ty); tusk.q(tx - hr * 0.9, ty + hr * 0.75, tx - hr * (1.5 - k * 0.2), ty - hr * 0.35)
            st(tusk, ink, hr * 0.2 + lw); st(tusk, rgb(0.97, 0.94, 0.84), hr * 0.2)
        }
        if (wu != null && wu.first == LDBossMove.FREEZE) withAlpha(wu.second) {
            for (k in 0 until 6) { val a = t * 6 + k; circle(tip.x + cos(a) * hr * 0.3, tip.y + sin(a) * hr * 0.3, hr * 0.15, rgb(0.85, 0.95, 1.0, 0.8)) }
        }
        if (wu != null && wu.first == LDBossMove.ROLL) {
            val p = wu.second
            LDFlytrap.roller(this, tip.x - cw * 0.35 * p, f.ground - cw * 0.4 * p, cw * 0.42 * p, LDRollerKind.SNOWBALL, 0.0, t)
        }
    }

    // The mech (future)

    private fun DrawScope.mech(b: LDBoss, f: Frame, t: Double) {
        val u = density.toDouble()
        val cw = f.cw; val L = f.lanes
        val wu = windup(b)
        val bob = sin(t * 2.2) * L * 0.012
        val x0 = f.front
        val cx = x0 + cw * 1.25
        val lw = max(1.5 * u, cw * 0.035)
        val chrome = listOf(gray(0.85), gray(0.55), gray(0.7))
        val neon = rgb(0.2, 0.95, 0.95); val pink = rgb(1.0, 0.3, 0.85)
        val hip = f.ground - L * 0.42 + bob
        val shoulders = f.ground - L * 0.9 + bob
        for ((i, lx) in listOf(cx + cw * 0.45, cx - cw * 0.4).withIndex()) {
            val kx = lx - cw * 0.15; val ky = f.ground - L * 0.2
            val leg = Path(); leg.m(lx, hip); leg.l(kx, ky); leg.l(lx, f.ground - L * 0.04)
            st(leg, ink, cw * 0.3 + lw); st(leg, if (i == 0) gray(0.45) else gray(0.6), cw * 0.3)
            line(lx + cw * 0.12, hip + L * 0.04, kx + cw * 0.15, ky, gray(0.85), cw * 0.06, StrokeCap.Butt)
            rrect(lx - cw * 0.4, f.ground - L * 0.06, cw * 0.7, L * 0.06, 4 * u, gray(0.3))
            rrectStroke(lx - cw * 0.4, f.ground - L * 0.06, cw * 0.7, L * 0.06, 4 * u, ink, lw)
            rect(kx - cw * 0.1, ky - cw * 0.03, cw * 0.2, cw * 0.06, neon)
        }
        var open = 0.0
        if (wu != null && wu.first == LDBossMove.BOMBARD) open = min(1.0, wu.second * 2)
        val podX = cx + cw * 0.15; val podY = shoulders - L * 0.22; val podW = cw * 0.75; val podH = L * 0.2
        rrect(podX, podY, podW, podH, 4 * u, gray(0.35))
        for (k in 0 until 4) {
            val mx = podX + podW * (0.15 + k * 0.22)
            circle(mx, podY + podH * 0.45, podH * 0.17, gray(0.1))
            if (open > 0.2 && b.move != null) circle(mx, podY + podH * 0.45 - open * podH * 0.2, podH * 0.13, rgb(0.95, 0.2, 0.15))
        }
        rrectStroke(podX, podY, podW, podH, 4 * u, ink, lw)
        val torso = polyPath(cx - cw * 0.62, hip, cx - cw * 0.92, shoulders + L * 0.08, cx - cw * 0.7, shoulders, cx + cw * 0.7, shoulders,
            cx + cw * 0.92, shoulders + L * 0.08, cx + cw * 0.62, hip)
        drawPath(torso, lin(listOf(gray(0.9), gray(0.62), gray(0.45)), cx - cw * 0.6, shoulders, cx + cw * 0.8, hip))
        val trim = Path()
        trim.m(cx - cw * 0.55, hip - L * 0.03); trim.l(cx - cw * 0.8, shoulders + L * 0.09)
        trim.m(cx + cw * 0.55, hip - L * 0.03); trim.l(cx + cw * 0.8, shoulders + L * 0.09)
        stroke(trim, neon.op(0.9), 2 * u)
        val grille = Path()
        for (k in 0 until 4) { val y = hip - L * 0.05 - k * L * 0.035; grille.m(cx - cw * 0.35, y); grille.l(cx + cw * 0.35, y) }
        stroke(grille, gray(0.25), 2 * u)
        line(cx - cw * 0.75, shoulders + L * 0.14, cx + cw * 0.75, shoulders + L * 0.14, pink.op(0.85), 1.5 * u, StrokeCap.Butt)
        val corex = cx - cw * 0.05; val corey = shoulders + L * 0.27
        val pulse = 0.6 + 0.4 * sin(t * 4)
        circle(corex, corey, cw * 0.24, radial(listOf(Color.White, neon.op(pulse), neon.op(0.0)), corex, corey, cw * 0.24))
        circleStroke(corex, corey, cw * 0.13, gray(0.3), 2 * u)
        stroke(torso, ink, lw)
        for (side in listOf(-1.0, 1.0)) {
            val plx = cx + side * cw * 0.95 - cw * 0.3; val ply = shoulders - L * 0.03; val plw = cw * 0.6; val plh = L * 0.15
            rrect(plx, ply, plw, plh, cw * 0.12, vgrad(listOf(gray(0.85), gray(0.5)), ply, ply + plh))
            rrectStroke(plx, ply, plw, plh, cw * 0.12, ink, lw)
            rect(plx + cw * 0.08, ply + plh / 2 - 1.5 * u, plw - cw * 0.16, 3 * u, pink)
        }
        val dx = cx; val dy = shoulders - L * 0.02
        val dr = cw * 0.48
        val glass = Path(); glass.arc(dx, dy, dr, PI, 2 * PI, moveFirst = true); glass.close()
        val pxx = dx - dr * 0.05; val pyy = dy - dr * 0.4
        ellipse(pxx, pyy, dr * 0.32, dr * 0.34, rgb(0.62, 0.72, 0.62)); ellipseStroke(pxx, pyy, dr * 0.32, dr * 0.34, ink, 1.2 * u)
        circle(pxx - dr * 0.12, pyy - dr * 0.05, dr * 0.1, Color.White)
        circle(pxx - dr * 0.14, pyy - dr * 0.04, dr * 0.04, ink)
        rect(pxx - dr * 0.32, pyy - dr * 0.22, dr * 0.64, dr * 0.08, gray(0.35))
        drawPath(glass, neon.op(0.18)); stroke(glass, gray(0.9), lw)
        val shine = Path(); shine.arc(dx, dy, dr * 0.78, deg(200.0), deg(240.0), moveFirst = true)
        st(shine, Color.White.op(0.8), 2 * u)
        var heat = 0.0
        if (wu != null && wu.first == LDBossMove.LASER) heat = wu.second
        val shx = cx - cw * 0.75; val shy = shoulders + L * 0.12
        val mx = x0 - cw * 0.25; val my = shy + L * 0.1
        line(shx, shy, mx + cw * 0.3, my, ink, cw * 0.26 + lw)
        drawLine(vgrad(chrome, my - cw * 0.13, my + cw * 0.13), off(shx, shy), off(mx + cw * 0.3, my), (cw * 0.26).f, StrokeCap.Round)
        rrect(mx, my - cw * 0.08, cw * 0.4, cw * 0.16, 3 * u, gray(0.25))
        rrectStroke(mx, my - cw * 0.08, cw * 0.4, cw * 0.16, 3 * u, ink, lw)
        val gr = cw * (0.1 + 0.25 * heat)
        circle(mx, my, gr, radial(listOf(Color.White, rgb(1.0, 0.2, 0.2, 0.3 + 0.7 * heat), Color.Transparent), mx, my, gr))
    }

    // The brain-bot (rooftop)

    private fun DrawScope.brainBot(b: LDBoss, f: Frame, t: Double) {
        val u = density.toDouble()
        val cw = f.cw; val L = f.lanes
        val wu = windup(b)
        val bob = sin(t * 1.9) * L * 0.015
        val x0 = f.front
        val cx = x0 + cw * 1.3
        val lw = max(1.5 * u, cw * 0.035)
        val metal = rgb(0.42, 0.38, 0.55); val metalDark = rgb(0.24, 0.2, 0.34)
        val bcx = cx; val bcy = f.ground - L * 0.58 + bob
        var lift = 0.0
        if (wu != null && wu.first == LDBossMove.STOMP) { val p = wu.second; lift = if (p < 0.8) p / 0.8 else max(0.0, 1 - (p - 0.8) / 0.2) }
        for ((i, footX) in listOf(x0 + cw * 0.15, cx + cw * 0.2, cx + cw * 1.2).withIndex()) {
            val hpx = cx + (i - 1) * cw * 0.55; val hpy = bcy + L * 0.06
            val fx = footX - (if (i == 0) lift * cw * 0.3 else 0.0); val fy = f.ground - (if (i == 0) lift * L * 0.35 else 0.0)
            val kx = (hpx + fx) / 2 + (if (i == 0) -cw * 0.25 else cw * 0.2); val ky = min(hpy, fy) - L * 0.12
            val leg = Path(); leg.m(hpx, hpy); leg.l(kx, ky); leg.l(fx, fy)
            st(leg, ink, cw * 0.16 + lw); st(leg, if (i == 1) metalDark else metal, cw * 0.16)
            circle(kx, ky, cw * 0.1, rgb(1.0, 0.85, 0.3))
            rrect(fx - cw * 0.22, fy - cw * 0.08, cw * 0.44, cw * 0.12, 3 * u, metalDark)
        }
        val cbx = cx + cw * 0.8; val cby = bcy - L * 0.08
        val ctx = cbx + cw * 0.2; val cty = bcy - L * 0.5
        val clawArm = Path(); clawArm.m(cbx, cby); clawArm.l(cbx + cw * 0.45, cby - L * 0.25); clawArm.l(ctx, cty)
        st(clawArm, ink, cw * 0.12 + lw); st(clawArm, metal, cw * 0.12)
        val claw = Path(); claw.m(ctx - cw * 0.15, cty - cw * 0.2); claw.q(ctx, cty + cw * 0.1, ctx + cw * 0.15, cty - cw * 0.2)
        stroke(claw, gray(0.8), cw * 0.06)
        val chassis = ovalAt(bcx, bcy, cw * 1.15, L * 0.17)
        drawPath(chassis, vgrad(listOf(metal.lit(0.2), metal, metalDark), bcy - L * 0.17, bcy + L * 0.17))
        stroke(chassis, ink, lw)
        for (k in 0 until 5) {
            val on = ((t * 4).toInt() + k) % 3 == 0
            circle(bcx - cw * 0.8 + k * cw * 0.4, bcy + L * 0.05, cw * 0.06, if (on) rgb(1.0, 0.3, 0.3) else rgb(0.4, 0.1, 0.1))
        }
        val dmx = bcx; val dmy = bcy - L * 0.1
        val drx = cw * 0.95; val dry = L * 0.36
        val glass = Path().apply { arcTo(Rect((dmx - drx).f, (dmy - dry).f, (dmx + drx).f, (dmy + dry).f), 180f, 180f, true); close() }
        val brx = dmx; val bry = dmy - dry * 0.45
        val brain = polyPath((0..24).map { i ->
            val a = i / 24.0 * 2 * PI
            val wob = 1 + 0.08 * sin(a * 7)
            P(brx + cos(a) * drx * 0.72 * wob, bry + sin(a) * dry * 0.48 * wob)
        })
        drawPath(brain, radial(listOf(rgb(1.0, 0.78, 0.82), rgb(0.92, 0.5, 0.6)), brx - drx * 0.2, bry - dry * 0.2, drx))
        val folds = Path()
        folds.m(brx, bry - dry * 0.45); folds.l(brx, bry + dry * 0.3)
        for (k in 0 until 4) {
            val y = bry - dry * 0.3 + k * dry * 0.18
            folds.m(brx - drx * 0.55, y); folds.q(brx - drx * 0.32, y - dry * 0.12, brx - drx * 0.1, y)
            folds.m(brx + drx * 0.1, y + dry * 0.05); folds.q(brx + drx * 0.32, y + dry * 0.18, brx + drx * 0.55, y + dry * 0.05)
        }
        stroke(folds, rgb(0.75, 0.3, 0.42), 1.4 * u)
        stroke(brain, rgb(0.55, 0.2, 0.3), 1.4 * u)
        for (dx in listOf(-0.32, 0.05)) {
            val ex = brx + dx * drx; val ey = bry + dry * 0.05
            ellipse(ex, ey, drx * 0.13, dry * 0.11, Color.White); ellipseStroke(ex, ey, drx * 0.13, dry * 0.11, ink, 1.2 * u)
            circle(ex - drx * 0.04, ey + dry * 0.01, drx * 0.055, ink)
            line(ex - drx * 0.14, ey - dry * 0.16, ex + drx * 0.12, ey - dry * 0.08, ink, 2 * u, StrokeCap.Butt)
        }
        drawPath(glass, rgb(0.7, 0.9, 1.0, 0.22)); stroke(glass, gray(0.92), lw)
        val shine = Path(); shine.arc(dmx - drx * 0.35, dmy - dry * 0.6, drx * 0.25, deg(200.0), deg(270.0), moveFirst = true)
        st(shine, Color.White.op(0.8), 2.5 * u)
        var glowColor: Color? = null
        var heat = 0.0
        if (wu != null && wu.first == LDBossMove.ROLL) {
            heat = wu.second
            glowColor = if (b.moves % 2 == 0) rgb(1.0, 0.45, 0.1) else rgb(0.35, 0.75, 1.0)
        }
        val shx = cx - cw * 0.8; val shy = bcy
        val mx = x0 - cw * 0.2; val my = bcy + L * 0.12
        line(shx, shy, mx, my, ink, cw * 0.24 + lw); line(shx, shy, mx, my, metal, cw * 0.24)
        circle(mx, my, cw * 0.17, metalDark); circleStroke(mx, my, cw * 0.17, ink, lw)
        val gc = glowColor
        if (gc != null) { val r = cw * (0.15 + 0.3 * heat); circle(mx, my, r, radial(listOf(Color.White, gc, gc.op(0.0)), mx, my, r)) }
    }

    // Telegraphs and shots

    /** Marked on the lawn under everything: target tiles, lanes about to freeze, aim lines, stomp shadows. */
    fun underlay(d: DrawScope, b: LDBoss, w: LDWorld, lay: LDLayout) = with(d) {
        if (b.died != null) return@with
        val u = density.toDouble()
        val cw = lay.cellW; val ch = lay.cellH
        val t = w.t
        val wu = windup(b)
        if (wu != null) {
            val (m, p) = wu
            when (m) {
                LDBossMove.BOMBARD -> for (tile in b.targets) {
                    val c = lay.point(tile.col + 0.5, tile.row + 0.6)
                    val r = cw * (0.42 - 0.12 * p) * (1 + 0.08 * sin(t * 12))
                    val ring = Path()
                    ring.ovalD(c.x - r, c.y - r * 0.7, r * 2, r * 1.4)
                    ring.m(c.x - r * 1.25, c.y); ring.l(c.x - r * 0.55, c.y)
                    ring.m(c.x + r * 0.55, c.y); ring.l(c.x + r * 1.25, c.y)
                    ring.m(c.x, c.y - r); ring.l(c.x, c.y - r * 0.4)
                    ring.m(c.x, c.y + r * 0.4); ring.l(c.x, c.y + r)
                    stroke(ring, rgb(1.0, 0.15, 0.1, 0.5 + 0.5 * p), 2.2 * u)
                    ellipse(c.x, c.y + ch * 0.25, cw * 0.35 * p, cw * 0.1 * p, Color.Black.op(0.25))
                }
                LDBossMove.GRAVES, LDBossMove.AMBUSH -> for (tile in b.targets) {
                    val c = lay.point(tile.col + 0.5, tile.row + 0.8)
                    if (w.params.scene == LDScene.DESERT) {
                        withAlpha(0.35 + 0.65 * p) {
                            ellipse(c.x, c.y, cw * 0.42, ch * 0.1, rgb(0.55, 0.38, 0.18, 0.45))
                            for (k in 0 until 9) {
                                val a = t * 9 + k * 0.8
                                val r = cw * (0.12 + 0.045 * k) * (0.5 + 0.5 * p)
                                circle(c.x + cos(a) * r, c.y - k * ch * 0.06 + sin(a) * r * 0.3, cw * 0.065, rgb(0.62, 0.44, 0.2))
                            }
                        }
                    } else ellipse(c.x, c.y, cw * 0.4 * p, cw * 0.12 * p, Color.Black.op(0.3))
                }
                LDBossMove.FREEZE, LDBossMove.ROLL -> b.targets.firstOrNull()?.row?.let { row ->
                    val a = lay.point(-0.6, row.toDouble()); val z = lay.point(b.x, row + 1.0)
                    val col = if (m == LDBossMove.FREEZE) rgb(0.6, 0.85, 1.0) else if (b.kind == LDBossKind.MEGABOT && b.moves % 2 == 0) rgb(1.0, 0.5, 0.2) else rgb(0.6, 0.85, 1.0)
                    rect(a.x, a.y, z.x - a.x, z.y - a.y, col.op(0.12 + 0.25 * p))
                    val arrows = Path()
                    var x = b.x - 0.7
                    while (x > -0.2) {
                        val c = lay.point(x, row + 0.5)
                        arrows.m(c.x + cw * 0.12, c.y - ch * 0.12); arrows.l(c.x - cw * 0.08, c.y); arrows.l(c.x + cw * 0.12, c.y + ch * 0.12)
                        x -= 1
                    }
                    st(arrows, Color.White.op(0.35 + 0.4 * p), 2 * u)
                }
                LDBossMove.LASER -> for (tile in b.targets) {
                    val a = lay.point(-0.6, tile.row + 0.45); val z = lay.point(b.x - 0.3, tile.row + 0.45)
                    val aim = Path(); aim.m(a.x, a.y); aim.l(z.x, z.y)
                    drawPath(aim, rgb(1.0, 0.15, 0.15, 0.35 + 0.5 * p), style = Stroke(((1.5 + 2 * p) * u).f,
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf((6 * u).f, (5 * u).f), (t * 40 * u % (11 * u)).f)))
                }
                LDBossMove.STOMP -> for (tile in b.targets) {
                    val c = lay.point(tile.col + 0.5, tile.row + 0.75)
                    ellipse(c.x, c.y, cw * 0.48 * (0.4 + 0.6 * p), ch * 0.2 * (0.4 + 0.6 * p), Color.Black.op(0.18 + 0.25 * p))
                }
                LDBossMove.CHARGE -> for (r in b.rows) {
                    val ch2 = Path()
                    var x = b.x - 0.5
                    while (x > LDWorld.CHARGE_STOP) {
                        val c = lay.point(x, r + 0.5)
                        ch2.m(c.x + cw * 0.15, c.y - ch * 0.15); ch2.l(c.x - cw * 0.1, c.y); ch2.l(c.x + cw * 0.15, c.y + ch * 0.15)
                        x -= 0.7
                    }
                    st(ch2, rgb(1.0, 0.25, 0.1, 0.3 + 0.6 * p * (0.6 + 0.4 * sin(t * 14))), 3 * u)
                }
                LDBossMove.SUMMON -> {}
            }
        }
        if (b.last == LDBossMove.FREEZE && t - b.lastAt < 0.8) {
            b.lastTargets.firstOrNull()?.row?.let { row ->
                val a = lay.point(-0.6, row.toDouble()); val z = lay.point(b.x, row + 1.0)
                rect(a.x, a.y, z.x - a.x, z.y - a.y, rgb(0.85, 0.95, 1.0, 0.5 * (1 - (t - b.lastAt) / 0.8)))
            }
        }
    }

    /** Drawn over everything: shots in flight, beams and breath at the moment they land. */
    fun overlay(d: DrawScope, b: LDBoss, w: LDWorld, lay: LDLayout) = with(d) {
        if (b.died != null) return@with
        val u = density.toDouble()
        val cw = lay.cellW; val ch = lay.cellH
        val t = w.t
        val wu = windup(b)
        if (wu != null) {
            val (m, p) = wu
            when {
                m == LDBossMove.BOMBARD && p > 0.45 -> {
                    val k = (p - 0.45) / (1 - 0.45)
                    val from = when (b.kind) {
                        LDBossKind.CAPTAIN -> lay.point(b.x - 0.45, b.y + 2.3)
                        LDBossKind.OUTLAW -> lay.point(b.x + 2.1, b.y - 0.1)
                        else -> lay.point(b.x + 1.6, b.y - 0.3)
                    }
                    for ((i, tile) in b.targets.withIndex()) {
                        val to = lay.point(tile.col + 0.5, tile.row + 0.6)
                        val kk = max(0.0, min(1.0, k * 1.15 - i * 0.05))
                        val cx = from.x + (to.x - from.x) * kk; val cy = from.y + (to.y - from.y) * kk - sin(kk * PI) * ch * 1.8
                        when (b.kind) {
                            LDBossKind.CAPTAIN -> circle(cx, cy, cw * 0.15, radial(listOf(gray(0.5), gray(0.08)), cx - cw * 0.05, cy - cw * 0.05, cw * 0.2))
                            LDBossKind.OUTLAW -> dynamite(this, cx, cy, cw * 0.35, kk * 9, t)
                            else -> missile(cx, cy, to.x, to.y, cw * 0.4, t)
                        }
                    }
                }
                m == LDBossMove.AMBUSH && b.kind == LDBossKind.CAPTAIN -> {
                    val zh = min(ch * 1.22, cw * 1.9)
                    val top = (lay.rows.firstOrNull() ?: 0).toDouble()
                    for (tile in b.targets) {
                        val anchor = lay.point(tile.col + 0.35, top - 1.3)
                        val start = lay.point(tile.col + 2.4, tile.row - 0.9)
                        val end = lay.point(tile.col + 0.9, tile.row + 0.92)
                        val a0 = atan2(start.y - anchor.y, start.x - anchor.x); val a1 = atan2(end.y - anchor.y, end.x - anchor.x)
                        val r0 = hypot(start.x - anchor.x, start.y - anchor.y); val r1 = hypot(end.x - anchor.x, end.y - anchor.y)
                        val a = a0 + (a1 - a0) * p
                        val r = r0 + (r1 - r0) * p
                        val fx = anchor.x + cos(a) * r; val fy = anchor.y + sin(a) * r
                        line(anchor.x, anchor.y, fx - zh * 0.25, fy - zh * 0.7, rgb(0.85, 0.72, 0.45), 2 * u, StrokeCap.Butt)
                        val fake = LDZombie(tile.row * 10 + tile.col, LDWorld.ambusher(tile), tile.row, 0.0, 6.0, 8.0, 0.0, 1.0, -9.0)
                        LDZombies.zombie(this, fx, fy, zh, fake, t, w.params.scene, cw)
                    }
                }
                m == LDBossMove.AMBUSH && b.kind == LDBossKind.MEGABOT -> for (tile in b.targets) {
                    val c = lay.point(tile.col + 0.9, tile.row + 0.92)
                    val fall = p * p
                    ellipse(c.x, c.y, cw * 0.35 * fall, cw * 0.1 * fall, Color.Black.op(0.3))
                    val zh = min(ch * 1.22, cw * 1.9)
                    val top = lay.point(0.0, (lay.rows.firstOrNull() ?: 0) - 1.5).y
                    val fake = LDZombie(tile.row * 10 + tile.col, LDWorld.ambusher(tile), tile.row, 0.0, 6.0, 8.0, 0.0, 1.0, -9.0)
                    LDZombies.zombie(this, c.x, top + (c.y - top) * fall, zh, fake, t, w.params.scene, cw)
                }
                else -> {}
            }
        }
        val since = t - b.lastAt
        when {
            b.last == LDBossMove.LASER && since < 0.35 -> for (tile in b.lastTargets) {
                val a = lay.point(-0.6, tile.row + 0.45); val z = lay.point(b.x - 0.3, tile.row + 0.45)
                val k = 1 - since / 0.35
                line(a.x, a.y, z.x, z.y, rgb(1.0, 0.2, 0.2, 0.6 * k), ch * 0.3, StrokeCap.Butt)
                line(a.x, a.y, z.x, z.y, Color.White.op(k), ch * 0.08, StrokeCap.Butt)
            }
            b.last == LDBossMove.FREEZE && since < 0.6 -> b.lastTargets.firstOrNull()?.row?.let { row ->
                withAlpha(1 - since / 0.6) {
                    var x = b.x - 0.2
                    var i = 0.0
                    while (x > -0.6) {
                        val c = lay.point(x, row + 0.5)
                        circle(c.x, c.y + sin(i * 2 + t * 8) * ch * 0.12, cw * (0.3 + 0.1 * LDWorlds.hash(i)), rgb(0.85, 0.95, 1.0, 0.75))
                        x -= 0.45; i += 1
                    }
                }
            }
            b.last == LDBossMove.STOMP && since < 0.5 -> for (tile in b.lastTargets) {
                val c = lay.point(tile.col + 0.5, tile.row + 0.8)
                val k = since / 0.5
                val rr = Path(); rr.ovalD(c.x - cw * (0.3 + 0.5 * k), c.y - ch * (0.1 + 0.15 * k), cw * (0.6 + k), ch * (0.2 + 0.3 * k))
                stroke(rr, Color.White.op((1 - k) * 0.8), 2 * u)
            }
            else -> {}
        }
    }

    private fun DrawScope.missile(cx: Double, cy: Double, tx: Double, ty: Double, s: Double, t: Double) {
        translate(cx.f, cy.f) {
            rotateRad(atan2(ty - cy, tx - cx).f, Offset.Zero) {
                ellipse(-s * 0.55, 0.0, s * 0.3 * (0.8 + 0.2 * sin(t * 40)), s * 0.1, rgb(1.0, 0.7, 0.2))
                rrect(-s * 0.35, -s * 0.08, s * 0.6, s * 0.16, s * 0.08, gray(0.92))
                drawPath(polyPath(s * 0.25, -s * 0.08, s * 0.42, 0.0, s * 0.25, s * 0.08), rgb(0.9, 0.15, 0.15))
                val fins = Path()
                fins.m(-s * 0.35, -s * 0.08); fins.l(-s * 0.45, -s * 0.18); fins.l(-s * 0.25, -s * 0.08)
                fins.m(-s * 0.35, s * 0.08); fins.l(-s * 0.45, s * 0.18); fins.l(-s * 0.25, s * 0.08)
                drawPath(fins, rgb(0.9, 0.15, 0.15))
            }
        }
    }

    // Health-bar faces

    fun icon(d: DrawScope, kind: LDBossKind, cx: Double, cy: Double, r: Double) = with(d) {
        val u = density.toDouble()
        circle(cx, cy, r, rgb(0.15, 0.08, 0.05))
        circleStroke(cx, cy, r, rgb(0.95, 0.8, 0.4), 1.4 * u)
        val skin = rgb(0.58, 0.66, 0.5)
        clipPath(discAt(cx, cy, r * 0.92)) {
            when (kind) {
                LDBossKind.GROUNDSKEEPER -> {
                    ellipse(cx, cy + r * 0.2, r * 0.6, r * 0.62, skin)
                    ellipse(cx, cy - r * 0.25, r * 1.1, r * 0.22, rgb(0.92, 0.8, 0.45))
                    rrect(cx - r * 0.5, cy - r * 0.75, r, r * 0.5, r * 0.2, rgb(0.95, 0.84, 0.5))
                    circle(cx - r * 0.2, cy + r * 0.12, r * 0.13, Color.White)
                }
                LDBossKind.PHARAOH -> {
                    rect(cx - r, cy - r, r * 2, r * 2, vgrad(listOf(rgb(0.98, 0.78, 0.22), rgb(0.12, 0.28, 0.72), rgb(0.98, 0.78, 0.22), rgb(0.12, 0.28, 0.72)), cy - r, cy + r))
                    ellipse(cx, cy + r * 0.1, r * 0.5, r * 0.6, rgb(0.9, 0.84, 0.68))
                    circle(cx - r * 0.18, cy, r * 0.1, rgb(0.6, 1.0, 0.4))
                    circle(cx + r * 0.18, cy, r * 0.1, rgb(0.6, 1.0, 0.4))
                }
                LDBossKind.CAPTAIN -> {
                    ellipse(cx, cy + r * 0.25, r * 0.6, r * 0.6, skin)
                    val hat = Path(); hat.m(cx - r, cy - r * 0.05); hat.q(cx, cy - r * 1.3, cx + r, cy - r * 0.05)
                    drawPath(hat, gray(0.08))
                    ellipse(cx + r * 0.15, cy + r * 0.15, r * 0.18, r * 0.16, gray(0.05))
                }
                LDBossKind.OUTLAW -> {
                    rect(cx - r, cy - r * 0.1, r * 2, r, gray(0.15))
                    rect(cx - r * 0.25, cy - r * 0.85, r * 0.5, r * 0.8, gray(0.2))
                    circle(cx - r * 0.5, cy + r * 0.1, r * 0.22, rgb(1.0, 0.9, 0.5))
                    rect(cx - r, cy + r * 0.55, r * 2, r * 0.2, rgb(0.72, 0.12, 0.1))
                }
                LDBossKind.MAMMOTH -> {
                    ellipse(cx + r * 0.1, cy, r * 0.8, r * 0.7, rgb(0.5, 0.32, 0.2))
                    val tusk = Path(); tusk.m(cx - r * 0.2, cy + r * 0.3); tusk.q(cx - r * 0.8, cy + r * 0.7, cx - r * 0.9, cy - r * 0.1)
                    st(tusk, rgb(0.97, 0.94, 0.84), r * 0.18)
                    circle(cx - r * 0.15, cy - r * 0.15, r * 0.1, Color.White)
                }
                LDBossKind.MECH -> {
                    rrect(cx - r * 0.7, cy - r * 0.5, r * 1.4, r, r * 0.2, gray(0.7))
                    rect(cx - r * 0.55, cy - r * 0.12, r * 1.1, r * 0.24, rgb(0.2, 0.95, 0.95))
                    circle(cx - r * 0.2, cy, r * 0.1, rgb(1.0, 0.2, 0.2))
                }
                LDBossKind.MEGABOT -> {
                    ellipse(cx, cy + r * 0.05, r * 0.75, r * 0.55, rgb(0.95, 0.6, 0.7))
                    line(cx, cy - r * 0.4, cx, cy + r * 0.5, rgb(0.7, 0.3, 0.4), 1.2 * u, StrokeCap.Butt)
                    circle(cx - r * 0.3, cy, r * 0.13, Color.White)
                    circle(cx + r * 0.1, cy, r * 0.13, Color.White)
                }
            }
        }
    }

    @Suppress("unused") private fun unusedCeil(x: Double) = ceil(x)
}
