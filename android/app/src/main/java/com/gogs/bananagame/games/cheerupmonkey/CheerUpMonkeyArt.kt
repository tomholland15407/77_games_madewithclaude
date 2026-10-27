package com.gogs.bananagame.games.cheerupmonkey

import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.drawscope.translate
import com.gogs.bananagame.core.*
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/**
 * Cheer Up Monkey's art (iOS CMArt, CMBackdrop, CMFrame, CMPlank, CMWheelFace): a painted, outlined
 * cartoon stage in the Monkey GO Happy style. Everything here is drawn in points (callers use
 * [inPoints]), so line widths and offsets are the iOS values unchanged. Strokes are SwiftUI's
 * defaults: butt caps, miter joins.
 */
internal object CMArt {
    val ink = rgb(0.16, 0.08, 0.03)
    val fur = rgb(0.98, 0.56, 0.1)
    val furDark = rgb(0.8, 0.38, 0.04)
    val peach = rgb(1.0, 0.84, 0.64)
    val iris = rgb(0.5, 0.32, 0.88)
    val yellow = rgb(1.0, 0.84, 0.08)

    fun color(h: CMHue): Color = when (h) {
        CMHue.RED -> rgb(0.92, 0.16, 0.16)
        CMHue.BLUE -> rgb(0.16, 0.42, 0.95)
        CMHue.GREEN -> rgb(0.15, 0.7, 0.24)
        CMHue.PURPLE -> rgb(0.62, 0.26, 0.86)
        CMHue.ORANGE -> rgb(1.0, 0.5, 0.06)
        CMHue.YELLOW -> rgb(0.98, 0.8, 0.0)
        CMHue.PINK -> rgb(0.98, 0.38, 0.72)
        CMHue.TEAL -> rgb(0.0, 0.74, 0.74)
        CMHue.CRYSTAL -> rgb(0.84, 0.95, 1.0)
    }

    fun hash(n: Double): Double { val v = sin(n * 12.9898) * 43758.5453; return v - floor(v) }

    // Small path and paint helpers.

    private fun ovalPath(cx: Double, cy: Double, rx: Double, ry: Double) =
        Path().apply { addOval(Rect((cx - rx).f, (cy - ry).f, (cx + rx).f, (cy + ry).f)) }
    private fun Path.oval(x: Double, y: Double, w: Double, h: Double) = addOval(Rect(x.f, y.f, (x + w).f, (y + h).f))
    private fun Path.box(x: Double, y: Double, w: Double, h: Double) = addRect(Rect(x.f, y.f, (x + w).f, (y + h).f))
    private fun Path.rbox(x: Double, y: Double, w: Double, h: Double, r: Double) =
        addRoundRect(RoundRect(x.f, y.f, (x + w).f, (y + h).f, CornerRadius(r.f, r.f)))
    private fun DrawScope.fill(p: Path, c: Color) = drawPath(p, c)
    private fun DrawScope.fill(p: Path, b: Brush) = drawPath(p, b)
    private fun DrawScope.stroke(p: Path, c: Color, lw: Double, cap: StrokeCap = StrokeCap.Butt) =
        drawPath(p, c, style = Stroke(lw.f, miter = 10f, cap = cap))
    private fun DrawScope.rect(r: CMRect, c: Color) = rect(r.x, r.y, r.w, r.h, c)
    private fun DrawScope.rect(r: CMRect, b: Brush) = rect(r.x, r.y, r.w, r.h, b)
    private fun DrawScope.rectStroke(r: CMRect, c: Color, lw: Double) = rectStroke(r.x, r.y, r.w, r.h, c, lw)
    private fun DrawScope.rrect(r: CMRect, rad: Double, c: Color) = rrect(r.x, r.y, r.w, r.h, rad, c)
    private fun DrawScope.rrect(r: CMRect, rad: Double, b: Brush) = rrect(r.x, r.y, r.w, r.h, rad, b)
    private fun DrawScope.rrectStroke(r: CMRect, rad: Double, c: Color, lw: Double) = rrectStroke(r.x, r.y, r.w, r.h, rad, c, lw)
    /** A radial glow that fades to the same colour, clear (no dark fringe). */
    private fun glow(colors: List<Color>, cx: Double, cy: Double, r: Double) = radial(colors + colors.last().op(0.0), cx, cy, r)

    // Symbols.

    /** Wheel and placard symbols: circle, triangle, square, star, heart, diamond. */
    fun glyph(i: Int, x: Double, y: Double, w: Double, h: Double): Path {
        val cx = x + w / 2; val cy = y + h / 2; val s = min(w, h) / 2
        val p = Path()
        when (i % 6) {
            0 -> p.oval(cx - s * 0.82, cy - s * 0.82, s * 1.64, s * 1.64)
            1 -> { p.m(cx, cy - s * 0.92); p.l(cx + s * 0.92, cy + s * 0.74); p.l(cx - s * 0.92, cy + s * 0.74); p.close() }
            2 -> p.rbox(cx - s * 0.74, cy - s * 0.74, s * 1.48, s * 1.48, s * 0.12)
            3 -> {
                for (k in 0 until 10) {
                    val a = k * PI / 5 - PI / 2
                    val rr = if (k % 2 == 0) s * 0.98 else s * 0.42
                    val qx = cx + cos(a) * rr; val qy = cy + 0.06 * s + sin(a) * rr
                    if (k == 0) p.m(qx, qy) else p.l(qx, qy)
                }
                p.close()
            }
            4 -> {
                p.m(cx, cy + s * 0.86)
                p.c(cx - s * 0.5, cy + s * 0.48, cx - s * 0.92, cy + s * 0.1, cx - s * 0.9, cy - s * 0.28)
                p.arc(cx - s * 0.45, cy - s * 0.32, s * 0.45, deg(175.0), deg(355.0))
                p.arc(cx + s * 0.45, cy - s * 0.32, s * 0.45, deg(185.0), deg(5.0))
                p.c(cx + s * 0.92, cy + s * 0.1, cx + s * 0.5, cy + s * 0.48, cx, cy + s * 0.86)
                p.close()
            }
            else -> { p.m(cx, cy - s * 0.96); p.l(cx + s * 0.7, cy); p.l(cx, cy + s * 0.96); p.l(cx - s * 0.7, cy); p.close() }
        }
        return p
    }

    /** Dice pips for 1…6 in a square. */
    fun pips(n: Int, x: Double, y: Double, w: Double, h: Double): Path {
        val cx = x + w / 2; val cy = y + h / 2; val s = min(w, h) / 2
        val d = s * 0.56; val pr = s * 0.2
        val layout = listOf(
            listOf(0 to 0), listOf(-1 to -1, 1 to 1), listOf(-1 to -1, 0 to 0, 1 to 1), listOf(-1 to -1, 1 to -1, -1 to 1, 1 to 1),
            listOf(-1 to -1, 1 to -1, 0 to 0, -1 to 1, 1 to 1), listOf(-1 to -1, 1 to -1, -1 to 0, 1 to 0, -1 to 1, 1 to 1),
        )
        val p = Path()
        for ((px, py) in layout[max(0, min(5, n - 1))]) p.oval(cx + px * d - pr, cy + py * d - pr, pr * 2, pr * 2)
        return p
    }

    /** A placard: a cream card with a coloured rim and the symbol painted in that colour. */
    fun DrawScope.placard(glyph: Int, hue: CMHue, cx: Double, cy: Double, s: Double) {
        val r = CMRect(cx - s / 2, cy - s / 2, s, s)
        rrect(r.x + s * 0.05, r.y + s * 0.07, s, s, s * 0.16, Color.Black.op(0.3))
        rrect(r, s * 0.16, rgb(1.0, 0.97, 0.86))
        rrectStroke(r.inset(s * 0.06, s * 0.06), s * 0.12, color(hue), max(1.5, s * 0.1))
        val g = r.inset(s * 0.24, s * 0.24)
        val gp = glyph(glyph, g.x, g.y, g.w, g.h)
        fill(gp, color(hue))
        stroke(gp, ink.op(0.8), max(0.8, s * 0.035))
        rrectStroke(r, s * 0.16, ink, max(1.0, s * 0.05))
    }

    /** A cut gem (wider than tall) with a bright crown facet and a glint. */
    fun DrawScope.gem(hue: CMHue, cx: Double, cy: Double, s: Double) {
        val base = color(hue)
        val top = cy - s * 0.32; val mid = cy - s * 0.05; val bot = cy + s * 0.42
        val body = polyPath(cx - s * 0.3, top, cx + s * 0.3, top, cx + s * 0.5, mid, cx, bot, cx - s * 0.5, mid)
        ellipse(cx, bot - s * 0.02, s * 0.36, s * 0.08, Color.Black.op(0.25))
        fill(body, lin(listOf(base.lit(0.35), base, base.shade(0.35)), cx, top, cx, bot))
        fill(polyPath(cx - s * 0.3, top, cx + s * 0.3, top, cx + s * 0.5, mid, cx - s * 0.5, mid), base.lit(0.45))
        val facets = Path().apply { m(cx - s * 0.15, mid); l(cx, bot); m(cx + s * 0.15, mid); l(cx, bot) }
        stroke(facets, base.shade(0.45).op(0.7), 0.8)
        stroke(body, ink, max(1.0, s * 0.07))
        circle(cx - s * 0.14, top + s * 0.1, s * 0.07, Color.White.op(0.95))
    }

    // Props.

    /** A prop standing with its base centre at the bottom middle of `r`. */
    fun DrawScope.prop(p: CMProp, r: CMRect, theme: Int, night: Boolean, openAge: Double) {
        val lw = max(1.2, r.h * 0.035)
        ellipse(r.midX, r.maxY - lw, r.w * 0.5, r.h * 0.08, Color.Black.op(0.28))
        when (p.kind) {
            CMPropKind.BARREL -> barrel(r, lw, p.open, openAge)
            CMPropKind.POT -> pot(r, lw, p.open, openAge)
            CMPropKind.CRATE -> crate(r, lw, p.open, openAge)
            CMPropKind.ROCK -> rock(r, lw, theme)
            CMPropKind.BUSH -> bush(r, lw, theme, night)
            CMPropKind.STUMP -> stump(r, lw)
            CMPropKind.SACK -> sack(r, lw)
            CMPropKind.CORAL -> coral(r, lw)
        }
    }

    /** How far a lid has come off, 0…1, with a little overshoot. */
    fun lift(age: Double): Double {
        if (age >= 0.35) return 1.0
        val k = age / 0.35
        return 1 - (1 - k).pow(3) + 0.15 * sin(k * PI)
    }

    private fun DrawScope.barrel(r: CMRect, lw: Double, open: Boolean, age: Double) {
        val wood = listOf(rgb(0.55, 0.33, 0.15), rgb(0.78, 0.52, 0.27), rgb(0.5, 0.3, 0.13))
        val topY = r.y + r.h * 0.1
        val body = Path().apply {
            m(r.x + r.w * 0.1, topY)
            q(r.x - r.w * 0.08, r.midY, r.x + r.w * 0.1, r.maxY - r.h * 0.06)
            l(r.maxX - r.w * 0.1, r.maxY - r.h * 0.06)
            q(r.maxX + r.w * 0.08, r.midY, r.maxX - r.w * 0.1, topY)
            close()
        }
        fill(body, hgrad(wood, r.x, r.maxX))
        val staves = Path()
        for (k in 1..3) {
            val x = r.x + r.w * k / 4
            staves.m(x, topY); staves.q(x + (x - r.midX) * 0.25, r.midY, x, r.maxY - r.h * 0.06)
        }
        stroke(staves, ink.op(0.35), 1.0)
        for (f in listOf(0.28, 0.72)) {
            val y = r.y + r.h * f
            val hoop = Path().apply { m(r.x + r.w * 0.02, y); q(r.midX, y + r.h * 0.05, r.maxX - r.w * 0.02, y) }
            stroke(hoop, gray(0.25), r.h * 0.07)
            stroke(hoop, gray(0.5), r.h * 0.02)
        }
        stroke(body, ink, lw)
        val tx = r.midX; val ty = topY
        if (open) {
            ellipse(tx, ty, r.w * 0.4, r.h * 0.07, rgb(0.12, 0.06, 0.02))
            stroke(ovalPath(tx, ty, r.w * 0.4, r.h * 0.07), ink, lw)
            // The lid, tipped off and leaning on the side.
            val k = lift(age)
            translate((tx + r.w * 0.5 * k).f, (ty - r.h * 0.25 * k).f) {
                rotate((70 * k).f, Offset.Zero) {
                    ellipse(0.0, 0.0, r.w * 0.4, r.h * 0.08, rgb(0.72, 0.48, 0.24))
                    stroke(ovalPath(0.0, 0.0, r.w * 0.4, r.h * 0.08), ink, lw)
                }
            }
        } else {
            ellipse(tx, ty, r.w * 0.4, r.h * 0.07, rgb(0.72, 0.48, 0.24))
            stroke(ovalPath(tx, ty, r.w * 0.26, r.h * 0.04), ink.op(0.35), 1.0)
            stroke(ovalPath(tx, ty, r.w * 0.4, r.h * 0.07), ink, lw)
        }
    }

    private fun DrawScope.pot(r: CMRect, lw: Double, open: Boolean, age: Double) {
        val clay = listOf(rgb(0.7, 0.3, 0.14), rgb(0.9, 0.5, 0.26), rgb(0.62, 0.25, 0.1))
        val neckY = r.y + r.h * 0.2
        val body = Path().apply {
            m(r.midX - r.w * 0.2, neckY)
            c(r.x - r.w * 0.1, r.y + r.h * 0.4, r.x, r.maxY - r.h * 0.05, r.midX - r.w * 0.2, r.maxY - r.h * 0.02)
            l(r.midX + r.w * 0.2, r.maxY - r.h * 0.02)
            c(r.maxX, r.maxY - r.h * 0.05, r.maxX + r.w * 0.1, r.y + r.h * 0.4, r.midX + r.w * 0.2, neckY)
            close()
        }
        fill(body, hgrad(clay, r.x, r.maxX))
        // A painted band of zigzags.
        val band = Path()
        val by = r.y + r.h * 0.55
        val n = 6
        for (k in 0..n) {
            val x = r.x + r.w * (0.12 + 0.76 * k / n)
            val y = by + if (k % 2 == 0) -r.h * 0.04 else r.h * 0.04
            if (k == 0) band.m(x, y) else band.l(x, y)
        }
        stroke(band, rgb(0.98, 0.88, 0.62).op(0.85), max(1.0, r.h * 0.03))
        stroke(body, ink, lw)
        val rim = CMRect(r.midX - r.w * 0.27, neckY - r.h * 0.07, r.w * 0.54, r.h * 0.1)
        rrect(rim, rim.h * 0.4, rgb(0.8, 0.4, 0.2))
        rrectStroke(rim, rim.h * 0.4, ink, lw)
        if (open) {
            ellipse(rim.midX, rim.y + 1, rim.w * 0.4, rim.h * 0.35, rgb(0.15, 0.05, 0.02))
            val k = lift(age)
            translate((rim.midX - r.w * 0.55 * k).f, (rim.y - r.h * 0.06 - r.h * 0.2 * sin(PI * min(1.0, k))).f) {
                rotate((-55 * k).f, Offset.Zero) { potLid(rim.w, lw) }
            }
        } else {
            translate(rim.midX.f, rim.y.f) { potLid(rim.w, lw) }
        }
    }

    private fun DrawScope.potLid(w: Double, lw: Double) {
        val dome = Path().apply { m(-w * 0.48, 0.0); q(0.0, -w * 0.42, w * 0.48, 0.0); close() }
        fill(dome, rgb(0.84, 0.45, 0.22))
        stroke(dome, ink, lw)
        circle(0.0, -w * 0.24, w * 0.09, rgb(0.6, 0.26, 0.1))
        stroke(ovalPath(0.0, -w * 0.24, w * 0.09, w * 0.09), ink, lw * 0.8)
    }

    private fun DrawScope.crate(r: CMRect, lw: Double, open: Boolean, age: Double) {
        val front = CMRect(r.x, r.y + r.h * 0.18, r.w, r.h * 0.82)
        val topH = r.h * 0.18
        val plank = rgb(0.86, 0.64, 0.36); val dark = rgb(0.6, 0.4, 0.18)
        rect(front, vgrad(listOf(plank, dark), front.y, front.maxY))
        val boards = Path()
        for (k in 1..2) { val y = front.y + front.h * k / 3; boards.m(front.x, y); boards.l(front.maxX, y) }
        stroke(boards, ink.op(0.4), 1.0)
        val brace = Path().apply {
            m(front.x + lw, front.y + lw); l(front.maxX - lw, front.maxY - lw)
            m(front.maxX - lw, front.y + lw); l(front.x + lw, front.maxY - lw)
        }
        stroke(brace, dark.shade(0.15), r.w * 0.09)
        stroke(brace, plank.lit(0.1), r.w * 0.05)
        rectStroke(front, ink, lw)
        // The top face in a little perspective.
        val topFace = polyPath(front.x, front.y, front.x + r.w * 0.12, front.y - topH, front.maxX - r.w * 0.12, front.y - topH, front.maxX, front.y)
        if (open) {
            fill(topFace, rgb(0.16, 0.08, 0.03))
            stroke(topFace, ink, lw)
            // The lid swung up and back on its hinge.
            val k = lift(age)
            val hingeY = front.y - topH
            val lid = polyPath(front.x + r.w * 0.12, hingeY, front.maxX - r.w * 0.12, hingeY,
                front.maxX - r.w * 0.04, hingeY - r.h * 0.42 * k, front.x + r.w * 0.04, hingeY - r.h * 0.42 * k)
            fill(lid, plank.shade(0.1))
            stroke(lid, ink, lw)
        } else {
            fill(topFace, plank.lit(0.15))
            val seams = Path().apply { m(r.midX, front.y); l(r.midX, front.y - topH) }
            stroke(seams, ink.op(0.4), 1.0)
            stroke(topFace, ink, lw)
        }
    }

    private fun DrawScope.rock(r: CMRect, lw: Double, theme: Int) {
        val base = if (theme == 1) rgb(0.82, 0.68, 0.42) else if (theme == 3) rgb(0.5, 0.45, 0.62) else rgb(0.62, 0.62, 0.64)
        val body = Path().apply {
            m(r.x, r.maxY)
            c(r.x - r.w * 0.02, r.y + r.h * 0.4, r.x + r.w * 0.15, r.y, r.midX - r.w * 0.05, r.y)
            c(r.maxX - r.w * 0.1, r.y - r.h * 0.05, r.maxX + r.w * 0.04, r.y + r.h * 0.5, r.maxX, r.maxY)
            close()
        }
        fill(body, lin(listOf(base.lit(0.2), base, base.shade(0.35)), r.x, r.y, r.maxX, r.maxY))
        val cracks = Path().apply { m(r.midX + r.w * 0.1, r.y + r.h * 0.2); l(r.midX + r.w * 0.02, r.y + r.h * 0.45); l(r.midX + r.w * 0.12, r.y + r.h * 0.6) }
        stroke(cracks, ink.op(0.4), 1.2)
        ellipse(r.midX - r.w * 0.18, r.y + r.h * 0.28, r.w * 0.12, r.h * 0.08, Color.White.op(0.25))
        stroke(body, ink, lw)
    }

    private fun DrawScope.bush(r: CMRect, lw: Double, theme: Int, night: Boolean) {
        val leaf = if (night) rgb(0.16, 0.42, 0.24) else if (theme == 1) rgb(0.3, 0.62, 0.16) else rgb(0.25, 0.6, 0.22)
        val blobs = listOf(Triple(0.22, 0.62, 0.26), Triple(0.5, 0.42, 0.32), Triple(0.78, 0.6, 0.26), Triple(0.36, 0.72, 0.28), Triple(0.64, 0.74, 0.28))
        val shape = Path()
        for ((bx, by, br) in blobs) shape.oval(r.x + r.w * (bx - br * 0.7), r.y + r.h * (by - br), r.w * br * 1.4, r.h * br * 2)
        fill(shape, vgrad(listOf(leaf.lit(0.18), leaf, leaf.shade(0.3)), r.y, r.maxY))
        val gloss = Path()
        for ((bx, by, br) in blobs.take(3)) gloss.oval(r.x + r.w * (bx - br * 0.3), r.y + r.h * (by - br * 0.7), r.w * br * 0.5, r.h * br * 0.4)
        fill(gloss, Color.White.op(0.18))
        stroke(shape, ink, lw)
    }

    private fun DrawScope.stump(r: CMRect, lw: Double) {
        val top = CMRect(r.x + r.w * 0.08, r.y, r.w * 0.84, r.h * 0.3)
        val bark = polyPath(top.x, top.midY, r.x, r.maxY, r.maxX, r.maxY, top.maxX, top.midY)
        fill(bark, hgrad(listOf(rgb(0.42, 0.26, 0.13), rgb(0.58, 0.38, 0.2), rgb(0.36, 0.22, 0.1)), r.x, r.maxX))
        val grain = Path()
        for (k in 1..3) { val x = r.x + r.w * k / 4; grain.m(x, top.midY + 2); grain.l(x + (x - r.midX) * 0.1, r.maxY - 2) }
        stroke(grain, ink.op(0.35), 1.0)
        stroke(bark, ink, lw)
        ellipse(top.midX, top.midY, top.w / 2, top.h / 2, rgb(0.86, 0.68, 0.42))
        for (k in 1..2) stroke(ovalPath(top.midX, top.midY, top.w / 2 - top.w * 0.13 * k, top.h / 2 - top.h * 0.13 * k), rgb(0.62, 0.44, 0.24), 1.0)
        stroke(ovalPath(top.midX, top.midY, top.w / 2, top.h / 2), ink, lw)
    }

    private fun DrawScope.sack(r: CMRect, lw: Double) {
        val nx = r.midX; val ny = r.y + r.h * 0.18
        val body = Path().apply {
            m(nx - r.w * 0.14, ny)
            c(r.x - r.w * 0.1, r.y + r.h * 0.5, r.x, r.maxY, r.midX, r.maxY)
            c(r.maxX, r.maxY, r.maxX + r.w * 0.1, r.y + r.h * 0.5, nx + r.w * 0.14, ny)
            close()
        }
        val burlap = rgb(0.8, 0.66, 0.42)
        fill(body, hgrad(listOf(burlap.lit(0.1), burlap, burlap.shade(0.3)), r.x, r.maxX))
        val weave = Path()
        for (k in 1..4) { val y = r.y + r.h * (0.3 + 0.15 * k); weave.m(r.x + r.w * 0.15, y); weave.q(r.midX, y + 3, r.maxX - r.w * 0.15, y) }
        stroke(weave, ink.op(0.2), 1.0)
        stroke(body, ink, lw)
        val tuft = polyPath(nx - r.w * 0.14, ny, nx - r.w * 0.22, r.y, nx, r.y + r.h * 0.06, nx + r.w * 0.22, r.y, nx + r.w * 0.14, ny)
        fill(tuft, burlap.shade(0.1))
        stroke(tuft, ink, lw)
        rectStroke(nx - r.w * 0.16, ny - 1.5, r.w * 0.32, 3.0, rgb(0.45, 0.25, 0.1), 2.5)
    }

    private fun DrawScope.coral(r: CMRect, lw: Double) {
        val pink = rgb(1.0, 0.45, 0.55)
        val arms = Path()
        val tips = listOf(-0.42 to 0.25, -0.18 to 0.02, 0.08 to 0.1, 0.3 to 0.0, 0.46 to 0.3)
        for ((tx, ty) in tips) {
            arms.m(r.midX, r.maxY)
            arms.q(r.midX + r.w * tx * 0.3, r.y + r.h * 0.6, r.midX + r.w * tx, r.y + r.h * ty)
        }
        stroke(arms, ink, r.w * 0.16 + lw * 2, StrokeCap.Round)
        stroke(arms, pink, r.w * 0.16, StrokeCap.Round)
        val dots = Path()
        for ((tx, ty) in tips) dots.oval(r.midX + r.w * tx - 2, r.y + r.h * ty - 2, 4.0, 4.0)
        fill(dots, Color.White.op(0.6))
    }

    /** Junk found in a container: an old sock, a fish bone, a boot. */
    fun DrawScope.junk(k: Int, cx: Double, cy: Double, s: Double) {
        val lw = max(1.0, s * 0.06)
        when (k % 3) {
            0 -> {
                val sock = Path().apply {
                    m(cx - s * 0.15, cy - s * 0.5); l(cx + s * 0.12, cy - s * 0.5); l(cx + s * 0.12, cy + s * 0.1)
                    q(cx + s * 0.45, cy + s * 0.05, cx + s * 0.45, cy + s * 0.25)
                    q(cx + s * 0.2, cy + s * 0.5, cx - s * 0.15, cy + s * 0.35)
                    close()
                }
                fill(sock, gray(0.92))
                rect(cx - s * 0.15, cy - s * 0.38, s * 0.27, s * 0.08, rgb(0.9, 0.2, 0.2))
                stroke(sock, ink, lw)
            }
            1 -> {
                val bone = Path().apply { m(cx - s * 0.45, cy); l(cx + s * 0.3, cy) }
                for (j in 0 until 4) {
                    val x = cx - s * 0.3 + j * s * 0.15
                    bone.m(x, cy - s * 0.18); bone.l(x + s * 0.04, cy + s * 0.18)
                }
                stroke(bone, gray(0.95), lw * 1.6)
                val head = polyPath(cx + s * 0.28, cy - s * 0.2, cx + s * 0.5, cy, cx + s * 0.28, cy + s * 0.2)
                fill(head, gray(0.95)); stroke(head, ink, lw)
                val tail = polyPath(cx - s * 0.45, cy, cx - s * 0.6, cy - s * 0.15, cx - s * 0.6, cy + s * 0.15)
                fill(tail, gray(0.95)); stroke(tail, ink, lw)
            }
            else -> {
                val boot = Path().apply {
                    m(cx - s * 0.2, cy - s * 0.45); l(cx + s * 0.1, cy - s * 0.45); l(cx + s * 0.1, cy + s * 0.05)
                    q(cx + s * 0.48, cy + s * 0.08, cx + s * 0.5, cy + s * 0.3)
                    l(cx - s * 0.2, cy + s * 0.3)
                    close()
                }
                fill(boot, rgb(0.42, 0.26, 0.14)); stroke(boot, ink, lw)
                ellipse(cx + s * 0.23, cy + s * 0.16, s * 0.05, s * 0.04, peach)
            }
        }
    }

    // Monkeys.

    /**
     * A monkey head in the Monkey GO Happy style: orange fur, round ears, a peach face over big purple
     * eyes. `mood`: 0 sad, 1 happy, 2 sobbing. Used for the big monkey and the mini ones.
     */
    fun DrawScope.monkeyHead(cx: Double, cy: Double, r: Double, mood: Int, t: Double, look: Double = 0.0) {
        val lw = max(1.0, r * 0.07)
        // Ears.
        for (side in listOf(-1.0, 1.0)) {
            val ex = cx + side * r * 0.98; val ey = cy + r * 0.05
            circle(ex, ey, r * 0.36, fur)
            stroke(ovalPath(ex, ey, r * 0.36, r * 0.36), ink, lw)
            circle(ex - side * r * 0.04, ey + r * 0.02, r * 0.21, peach)
        }
        // Head and tuft.
        val tuft = Path()
        for (k in 0 until 3) {
            val bx = cx + (k - 1) * r * 0.16
            tuft.m(bx - r * 0.1, cy - r * 0.9)
            tuft.q(bx - r * 0.1, cy - r * 1.15, bx + (k - 1) * r * 0.14 + r * 0.05, cy - r * 1.3)
            tuft.q(bx + r * 0.08, cy - r * 1.1, bx + r * 0.1, cy - r * 0.9)
        }
        fill(tuft, furDark)
        stroke(tuft, ink, lw * 0.8)
        circle(cx, cy, r, radial(listOf(fur.lit(0.2), fur, furDark), cx - r * 0.3, cy - r * 0.35, r * 1.3))
        stroke(ovalPath(cx, cy, r, r), ink, lw)
        // The peach face: two lobes round the eyes and a muzzle.
        val face = Path().apply {
            oval(cx - r * 0.8, cy - r * 0.5, r * 0.86, r * 0.86)
            oval(cx - r * 0.06, cy - r * 0.5, r * 0.86, r * 0.86)
            oval(cx - r * 0.55, cy + r * 0.08, r * 1.1, r * 0.76)
        }
        fill(face, peach)
        // Eyes.
        for (side in listOf(-1.0, 1.0)) {
            val ex = cx + side * r * 0.36; val ey = cy - r * 0.08
            if (mood == 1) {
                // Squeezed shut with joy.
                val happy = Path().apply { m(ex - r * 0.22, ey + r * 0.04); q(ex, ey - r * 0.26, ex + r * 0.22, ey + r * 0.04) }
                stroke(happy, ink, lw * 1.6, StrokeCap.Round)
                continue
            }
            val eye = ovalPath(ex, ey, r * 0.27, r * 0.33)
            fill(eye, Color.White)
            val icx = ex + look * r * 0.08; val icy = ey + r * 0.06
            ellipse(icx, icy, r * 0.2, r * 0.24, iris)
            ellipse(icx, icy + r * 0.02, r * 0.11, r * 0.14, rgb(0.12, 0.04, 0.2))
            circle(icx - r * 0.08, icy - r * 0.09, r * 0.065, Color.White)
            circle(icx + r * 0.07, icy + r * 0.08, r * 0.035, Color.White)
            // Sad lids droop toward the outside, with brows tilted up in the middle.
            val lid = polyPath(ex - r * 0.32, ey - r * 0.36, ex + r * 0.32, ey - r * 0.36, ex + side * r * 0.3, ey - r * 0.06, ex - side * r * 0.3, ey - r * 0.26)
            clipPath(eye) { fill(lid, peach.shade(0.08)) }
            stroke(eye, ink, lw * 0.8)
            val lidLine = Path().apply { m(ex - side * r * 0.28, ey - r * 0.25); l(ex + side * r * 0.28, ey - r * 0.07) }
            clipPath(ovalPath(ex, ey, r * 0.3, r * 0.36)) { stroke(lidLine, ink, lw) }
            val brow = Path().apply { m(ex - side * r * 0.24, ey - r * 0.5); l(ex + side * r * 0.2, ey - r * 0.38) }
            stroke(brow, furDark.shade(0.3), lw * 1.3, StrokeCap.Round)
        }
        // Nose.
        for (side in listOf(-1.0, 1.0)) ellipse(cx + side * r * 0.07, cy + r * 0.3, r * 0.035, r * 0.045, ink.op(0.8))
        // Mouth.
        if (mood == 1) {
            val grin = Path().apply {
                m(cx - r * 0.36, cy + r * 0.42)
                q(cx, cy + r * 0.46, cx + r * 0.36, cy + r * 0.42)
                q(cx, cy + r * 1.0, cx - r * 0.36, cy + r * 0.42)
                close()
            }
            fill(grin, rgb(0.55, 0.08, 0.1))
            clipPath(grin) {
                ellipse(cx, cy + r * 0.8, r * 0.22, r * 0.13, rgb(1.0, 0.45, 0.5))
                rect(cx - r * 0.3, cy + r * 0.42, r * 0.6, r * 0.08, Color.White)
            }
            stroke(grin, ink, lw)
        } else {
            val frown = Path().apply { m(cx - r * 0.18, cy + r * 0.6); q(cx, cy + r * (if (mood == 2) 0.38 else 0.47), cx + r * 0.18, cy + r * 0.6) }
            stroke(frown, ink, lw * 1.2, StrokeCap.Round)
            // Tears: one at a time when sad, streams when sobbing.
            val drops = if (mood == 2) 3 else 1
            for (k in 0 until drops) {
                val phase = (t * (if (mood == 2) 1.6 else 0.6) + k.toDouble() / drops).mod(1.0)
                for (side in if (mood == 2) listOf(-1.0, 1.0) else listOf(1.0)) {
                    val px = cx + side * r * 0.5; val py = cy + r * 0.2 + phase * r * 0.9
                    val drop = Path().apply { m(px, py - r * 0.12); q(px + r * 0.1, py, px, py + r * 0.06); q(px - r * 0.1, py, px, py - r * 0.12) }
                    val a = 1 - phase * 0.6
                    fill(drop, rgb(0.55, 0.8, 1.0).op(a))
                    stroke(drop, rgb(0.2, 0.4, 0.8).op(a), max(0.6, lw * 0.5))
                }
            }
        }
    }

    /** The big monkey, sitting with its feet at (fx, fy0). `jump` lifts it (the happy hop). */
    fun DrawScope.bigMonkey(fx: Double, fy0: Double, r: Double, mood: Int, t: Double, jump: Double) {
        val lw = max(1.4, r * 0.06)
        val fy = fy0 - jump
        ellipse(fx, fy0 - r * 0.04, r * 0.95 * (1 - jump / (r * 4)), r * 0.16, Color.Black.op(0.28))
        val hy = fy - r * 2.05 + (if (mood == 0) sin(t * 1.8) * r * 0.02 else 0.0)
        // Arms: hanging when sad, thrown up when happy.
        for (side in listOf(-1.0, 1.0)) {
            val arm = Path()
            val sx = fx + side * r * 0.5; val sy = fy - r * 1.05
            val hx: Double; val hdy: Double
            if (mood == 1) {
                hx = fx + side * r * 1.25; hdy = fy - r * 2.4 + sin(t * 14) * r * 0.06
                arm.m(sx, sy); arm.q(fx + side * r * 1.2, fy - r * 1.2, hx, hdy)
            } else {
                hx = fx + side * r * 0.95; hdy = fy - r * 0.12
                arm.m(sx, sy); arm.q(fx + side * r * 1.05, fy - r * 0.8, hx, hdy)
            }
            stroke(arm, ink, r * 0.24 + lw * 2, StrokeCap.Round)
            stroke(arm, fur, r * 0.24, StrokeCap.Round)
            circle(hx, hdy, r * 0.17, peach)
            stroke(ovalPath(hx, hdy, r * 0.17, r * 0.17), ink, lw)
        }
        // Body and belly.
        val body = Path().apply {
            m(fx - r * 0.45, fy - r * 1.3)
            c(fx - r * 0.95, fy - r * 0.9, fx - r * 0.8, fy - r * 0.08, fx, fy - r * 0.08)
            c(fx + r * 0.8, fy - r * 0.08, fx + r * 0.95, fy - r * 0.9, fx + r * 0.45, fy - r * 1.3)
            close()
        }
        fill(body, lin(listOf(fur, furDark), fx - r * 0.6, fy - r * 1.2, fx + r * 0.6, fy))
        stroke(body, ink, lw)
        ellipse(fx, fy - r * 0.55, r * 0.42, r * 0.4, peach)
        // Legs folded in front, feet up.
        for (side in listOf(-1.0, 1.0)) {
            val kx = fx + side * r * 0.42; val ky = fy - r * 0.2
            ellipse(kx, ky, r * 0.34, r * 0.22, fur)
            stroke(ovalPath(kx, ky, r * 0.34, r * 0.22), ink, lw)
            ellipse(kx + side * r * 0.14, ky + r * 0.03, r * 0.16, r * 0.13, peach)
        }
        monkeyHead(fx, hy, r, mood, t)
    }

    /** A mini monkey: a tiny copy with a little body. `placard` (glyph, hue) is held up over its head. */
    fun DrawScope.miniMonkey(cx: Double, cy: Double, r: Double, t: Double, placard: Pair<Int, CMHue>?, wave: Boolean) {
        val lw = max(0.8, r * 0.09)
        val body = ovalPath(cx, cy + r * 1.35, r * 0.62, r * 0.65)
        fill(body, fur)
        stroke(body, ink, lw)
        ellipse(cx, cy + r * 1.4, r * 0.32, r * 0.36, peach)
        if (placard != null) {
            for (side in listOf(-1.0, 1.0)) {
                val arm = Path().apply { m(cx + side * r * 0.5, cy + r * 0.95); l(cx + side * r * 0.75, cy - r * 1.0) }
                stroke(arm, ink, r * 0.3 + lw * 2, StrokeCap.Round)
                stroke(arm, fur, r * 0.3, StrokeCap.Round)
            }
            monkeyHead(cx, cy, r, 1, t)
            placard(placard.first, placard.second, cx, cy - r * 1.9, r * 2.1)
        } else {
            if (wave) {
                val arm = Path().apply { m(cx + r * 0.5, cy + r * 0.95); l(cx + r * 1.05, cy + r * 0.1 + sin(t * 8) * r * 0.25) }
                stroke(arm, ink, r * 0.3 + lw * 2, StrokeCap.Round)
                stroke(arm, fur, r * 0.3, StrokeCap.Round)
            }
            monkeyHead(cx, cy, r, 0, t, sin(t * 0.9))
        }
    }

    /** The wicker basket the mini monkeys hop into. */
    fun DrawScope.basket(r: CMRect, heads: Int, t: Double) {
        val lw = max(1.2, r.h * 0.04)
        val rimY = r.y + r.h * 0.2
        val mr = r.h * 0.22
        for (k in 0 until heads) {
            val x = r.x + r.w * (0.24 + 0.26 * (k % 3)); val y = rimY - mr * 0.25 - (k / 3) * mr * 0.5
            monkeyHead(x, y, mr, 1, t + k)
        }
        val body = polyPath(r.x, rimY, r.maxX, rimY, r.maxX - r.w * 0.1, r.maxY, r.x + r.w * 0.1, r.maxY)
        val straw = rgb(0.86, 0.62, 0.3)
        fill(body, vgrad(listOf(straw, straw.shade(0.35)), rimY, r.maxY))
        clipPath(body) {
            val weave = Path()
            var x = r.x - r.h
            while (x < r.maxX + r.h) {
                weave.m(x, rimY); weave.l(x + r.h, r.maxY)
                weave.m(x + r.h, rimY); weave.l(x, r.maxY)
                x += r.h * 0.24
            }
            stroke(weave, straw.shade(0.45).op(0.6), 1.0)
        }
        stroke(body, ink, lw)
        val rim = CMRect(r.x - r.w * 0.03, rimY - r.h * 0.07, r.w * 1.06, r.h * 0.14)
        rrect(rim, rim.h / 2, straw.lit(0.1))
        rrectStroke(rim, rim.h / 2, ink, lw)
    }

    /** The chest: closed with a big brass padlock, or open with light pouring out. */
    fun DrawScope.chest(r: CMRect, openAge: Double?, t: Double) {
        val lw = max(1.4, r.h * 0.04)
        val wood = rgb(0.62, 0.34, 0.14); val band = rgb(0.95, 0.72, 0.2)
        val lidH = r.h * 0.36
        val body = CMRect(r.x, r.y + lidH, r.w, r.h - lidH)
        ellipse(r.midX, r.maxY - 1, r.w * 0.55, r.h * 0.08, Color.Black.op(0.3))
        val k = openAge?.let { min(1.0, it / 0.3) } ?: 0.0
        if (openAge != null) {
            // Light from inside.
            val gx = r.midX; val gy = body.y
            circle(gx, gy, r.w * (0.7 + 0.05 * sin(t * 5)), glow(listOf(rgb(1.0, 0.95, 0.6).op(0.8 * k)), gx, gy, r.w * 0.75))
            // The lid, thrown back.
            val lid = Path().apply {
                m(body.x, body.y); l(body.maxX, body.y)
                l(body.maxX - r.w * 0.06, body.y - lidH * 1.4 * k)
                q(r.midX, body.y - lidH * 1.9 * k, body.x + r.w * 0.06, body.y - lidH * 1.4 * k)
                close()
            }
            fill(lid, rgb(0.42, 0.08, 0.1))
            stroke(lid, ink, lw)
            rect(body.x + lw, body.y - lw, body.w - lw * 2, lw * 2.5, rgb(0.12, 0.05, 0.02))
        }
        rrect(body, r.w * 0.04, vgrad(listOf(wood.lit(0.12), wood.shade(0.25)), body.y, body.maxY))
        for (fx in listOf(0.08, 0.92)) rect(r.x + r.w * fx - r.w * 0.05, body.y, r.w * 0.1, body.h, band)
        rrectStroke(body, r.w * 0.04, ink, lw)
        if (openAge == null) {
            val lid = Path().apply {
                m(r.x, body.y); l(r.x, r.y + lidH * 0.45)
                q(r.midX, r.y - lidH * 0.35, r.maxX, r.y + lidH * 0.45)
                l(r.maxX, body.y)
                close()
            }
            fill(lid, vgrad(listOf(wood.lit(0.2), wood), r.y, body.y))
            clipPath(lid) { for (fx in listOf(0.08, 0.92)) rect(r.x + r.w * fx - r.w * 0.05, r.y - lidH, r.w * 0.1, lidH * 2, band) }
            stroke(lid, ink, lw)
            // Padlock.
            val lcx = r.midX; val lcy = body.y + body.h * 0.12
            val ls = r.w * 0.26
            val shackle = Path().apply { arc(lcx, lcy, ls * 0.32, PI, 2 * PI, moveFirst = true) }
            stroke(shackle, ink, ls * 0.2 + lw)
            stroke(shackle, gray(0.75), ls * 0.2)
            val lock = CMRect(lcx - ls * 0.5, lcy, ls, ls * 0.8)
            rrect(lock, ls * 0.15, vgrad(listOf(band.lit(0.3), band.shade(0.2)), lock.y, lock.maxY))
            rrectStroke(lock, ls * 0.15, ink, lw)
            circle(lock.midX, lock.midY - ls * 0.05, ls * 0.1, ink)
            rect(lock.midX - ls * 0.04, lock.midY - ls * 0.02, ls * 0.08, ls * 0.22, ink)
        }
    }

    /** A banana: crescent, stalk and tip, about `w` long. */
    fun DrawScope.banana(cx: Double, cy: Double, w: Double, angle: Double = -0.3) {
        translate(cx.f, cy.f) {
            rotateRad(angle.f, Offset.Zero) {
                val h = w * 0.42
                val ban = Path().apply {
                    m(-w * 0.5, -h * 0.35)
                    q(0.0, h * 1.15, w * 0.5, -h * 0.45)
                    q(0.0, h * 0.1, -w * 0.5, -h * 0.35)
                    close()
                }
                fill(ban, vgrad(listOf(rgb(1.0, 0.96, 0.5), yellow, rgb(0.9, 0.66, 0.08)), -h * 0.3, h * 0.6))
                stroke(ban, ink, max(1.2, w * 0.04))
                rrect(w * 0.44, -h * 0.62, w * 0.12, h * 0.26, w * 0.02, rgb(0.42, 0.28, 0.08))
                circle(-w * 0.5, -h * 0.35, w * 0.035, rgb(0.3, 0.2, 0.05))
            }
        }
    }

    // The live scene.

    fun DrawScope.scene(w: Double, h: Double, stage: CMStage, fx: CMFx, now: Double, theme: Int, night: Boolean) {
        val t = now
        if (stage.wheels.isEmpty()) return
        val u = CMLayout.unit(w, h)
        // Props back to front, each with any mini monkey peeking out from behind it first.
        for (i in stage.props.indices.sortedBy { stage.props[it].y }) {
            val p = stage.props[i]
            val rect = CMLayout.propRect(p, w, h)
            for ((m, mini) in stage.minis.withIndex()) {
                if (mini.host != i || mini.inside || mini.found) continue
                val hd = CMLayout.peekHead(mini, stage, w, h)
                miniMonkey(hd.x, hd.y, CMLayout.miniR(w, h, p.scale), t + m, null, mini.side != 0)
            }
            val age = fx.openedAt[i]?.let { now - it } ?: 99.0
            prop(p, rect, theme, night, age)
            if (p.open) (p.loot as? CMLoot.Junk)?.let { junk(it.k, rect.midX, rect.y - u * 0.12 * p.scale, u * 0.42 * p.scale) }
        }
        // Gems: loose ones, and the ones in containers once those are open.
        for (gm in stage.gems) {
            val cx = gm.x * w
            var cy = gm.y * h
            val host = gm.host
            if (host != null) {
                if (!stage.props[host].open) continue
                val r = CMLayout.propRect(stage.props[host], w, h)
                val age = fx.openedAt[host]?.let { now - it } ?: 99.0
                cy = r.y - u * 0.14 - u * 0.25 * max(0.0, 1 - age / 0.3)
            }
            gem(gm.hue, cx, cy, u * 0.3)
        }
        // The basket with the mini monkeys already in it.
        val landed = stage.minis.indices.count { m -> stage.minis[m].found && (fx.foundAt[m]?.let { now - it > 1.5 } ?: true) }
        basket(CMLayout.basketRect(w, h), landed, t)
        // The chest, and the banana once it's open.
        val chestAge = fx.unlockedAt?.let { now - it }
        chest(CMLayout.chestRect(w, h), if (stage.unlocked) (chestAge ?: 99.0) else null, t)
        val mr = CMLayout.monkeyR(w, h)
        val feet = CMLayout.monkeyFeet(w, h)
        if (stage.unlocked) {
            val rise = min(1.0, (chestAge ?: 99.0) / 0.45)
            val b0 = CMLayout.bananaPoint(w, h)
            val c = CMLayout.chestRect(w, h)
            val given = fx.givenAt
            if (given != null) {
                val k = min(1.0, (now - given) / 0.4)
                if (k < 1) {
                    val mx = feet.x; val my = feet.y - mr * 1.7
                    val px = b0.x + (mx - b0.x) * k; val py = b0.y + (my - b0.y) * k - sin(PI * k) * mr * 0.8
                    banana(px, py, mr * 1.1 * (1 - k * 0.4), -0.3 - k * 3)
                }
            } else {
                val px = b0.x; val py = c.y + (b0.y - c.y) * rise + sin(t * 3) * mr * 0.06
                circle(px, py, mr * 0.75, glow(listOf(rgb(1.0, 0.95, 0.5).op(0.55)), px, py, mr * 0.75))
                banana(px, py, mr * 1.1)
            }
        }
        // The big monkey: sad, jumping for joy once fed, sobbing if time ran out.
        val happyAge = fx.givenAt?.let { now - it - 0.4 } ?: -1.0
        val mood = if (happyAge >= 0) 1 else if (fx.failedAt != null) 2 else 0
        val jump = if (mood == 1) abs(sin(happyAge * 7)) * mr * 0.55 else 0.0
        bigMonkey(feet.x, feet.y, mr, mood, t, jump)
        if (mood == 1) {
            for (k in 0 until 6) {
                val a = k / 6.0 * 2 * PI + happyAge * 2
                val d = mr * (1.6 + 0.4 * min(1.0, happyAge * 2))
                val px = feet.x + cos(a) * d; val py = feet.y - mr * 2 - jump + sin(a) * d * 0.7
                fill(glyph(3, px - mr * 0.16, py - mr * 0.16, mr * 0.32, mr * 0.32), yellow.op(max(0.0, 1 - happyAge / 1.4)))
            }
        }
        // Mini monkeys just found: pop up holding the placard, then hop into the basket. The placard is
        // only shown this once, so the player has to remember it.
        val basketTop = CMLayout.basketRect(w, h)
        for ((m, mini) in stage.minis.withIndex()) {
            if (!mini.found) continue
            val at = fx.foundAt[m] ?: continue
            val age = now - at
            if (age >= 1.5) continue
            val host = stage.props[mini.host]
            val hr = CMLayout.miniR(w, h, host.scale)
            val start = if (mini.inside) {
                val r = CMLayout.propRect(host, w, h)
                P(r.midX, r.y - hr * 1.2)
            } else CMLayout.peekHead(mini, stage, w, h)
            val pop = min(1.0, age / 0.25)
            val sx = start.x; val sy = start.y - hr * 1.0 * pop
            if (age < 1.05) {
                miniMonkey(sx, sy, hr * (1 + 0.3 * pop), t, mini.glyph to mini.hue, false)
            } else {
                val k = (age - 1.05) / 0.45
                val ex = basketTop.midX; val ey = basketTop.y
                val px = sx + (ex - sx) * k; val py = sy + (ey - sy) * k - sin(PI * k) * h * 0.12
                miniMonkey(px, py, hr * 1.3 * (1 - 0.3 * k), t, null, false)
            }
        }
    }

    // Static pieces.

    /** The painted stage behind everything: a cottage, a jungle temple, a ship's deck, a reef. Static for the level. */
    fun DrawScope.backdrop(w: Double, h: Double, theme: Int, night: Boolean) {
        when (theme) {
            1 -> temple(w, h, night)
            2 -> deck(w, h, night)
            3 -> reef(w, h)
            else -> cottage(w, h, night)
        }
    }

    private fun DrawScope.sky(w: Double, colors: List<Color>, horizon: Double) = rect(0.0, 0.0, w, horizon + 2, vgrad(colors, 0.0, horizon))

    private fun DrawScope.stars(w: Double, below: Double) {
        val dots = Path()
        for (k in 0 until 28) {
            val x = w * hash(k * 3.1); val y = below * hash(k * 7.3) * 0.9
            val r = if (k % 5 == 0) 1.6 else 1.0
            dots.oval(x - r, y - r, r * 2, r * 2)
        }
        fill(dots, Color.White.op(0.85))
    }

    private fun DrawScope.cottage(w: Double, h: Double, night: Boolean) {
        val hz = h * 0.34
        sky(w, if (night) listOf(rgb(0.04, 0.05, 0.18), rgb(0.12, 0.16, 0.4), rgb(0.26, 0.3, 0.55))
               else listOf(rgb(0.36, 0.28, 0.55), rgb(0.95, 0.5, 0.32), rgb(1.0, 0.86, 0.45)), hz)
        if (night) {
            stars(w, hz)
            val mx = w * 0.8; val my = h * 0.09
            // The halo starts a third of the way out (SwiftUI's startRadius).
            val halo = rgb(1.0, 0.98, 0.85, 0.5)
            circle(mx, my, h * 0.06, Brush.radialGradient(0f to halo, (1f / 3f) to halo, 1f to halo.op(0.0), center = off(mx, my), radius = (h * 0.09).f))
            circle(mx, my, h * 0.035, rgb(1.0, 0.97, 0.82))
            circle(mx + h * 0.015, my - h * 0.008, h * 0.03, rgb(0.12, 0.16, 0.4))
        } else {
            val sx = w * 0.74; val sy = hz - h * 0.04
            circle(sx, sy, h * 0.16, glow(listOf(rgb(1.0, 0.96, 0.7), rgb(1.0, 0.85, 0.4).op(0.5)), sx, sy, h * 0.16))
            val streaks = Path()
            for ((fx, fy, fw) in listOf(Triple(0.1, 0.1, 0.3), Triple(0.5, 0.06, 0.25), Triple(0.62, 0.16, 0.35))) {
                streaks.rbox(w * fx, h * fy, w * fw, h * 0.018, h * 0.009)
            }
            fill(streaks, rgb(0.55, 0.35, 0.6).op(0.5))
        }
        // Pines along the horizon, far then near.
        for (layer in 0 until 2) {
            val pines = Path()
            var x = -10.0
            var k = 0
            while (x < w + 20) {
                val ph = h * (if (layer == 0) 0.1 else 0.14) * (0.7 + 0.5 * hash(k * 1.7 + layer * 9))
                val pw = ph * 0.5
                val base = hz + if (layer == 0) 0.0 else h * 0.01
                pines.m(x - pw / 2, base); pines.l(x, base - ph); pines.l(x + pw / 2, base); pines.close()
                x += pw * (if (layer == 0) 0.6 else 0.9); k++
            }
            val col = if (night) (if (layer == 0) rgb(0.1, 0.16, 0.24) else rgb(0.06, 0.12, 0.14))
                      else (if (layer == 0) rgb(0.35, 0.32, 0.4) else rgb(0.15, 0.3, 0.2))
            fill(pines, col)
        }
        // Ground: grass with a dirt path from the cottage down to the monkey.
        val grass = if (night) listOf(rgb(0.12, 0.26, 0.2), rgb(0.06, 0.16, 0.12)) else listOf(rgb(0.42, 0.62, 0.22), rgb(0.22, 0.42, 0.14))
        rect(0.0, hz, w, h - hz, vgrad(grass, hz, h))
        val path = Path().apply {
            m(w * 0.36, hz + h * 0.02); l(w * 0.42, hz + h * 0.02)
            q(w * 0.42, h * 0.7, w * 0.7, h)
            l(w * 0.3, h)
            q(w * 0.36, h * 0.7, w * 0.36, hz + h * 0.02)
        }
        fill(path, if (night) rgb(0.24, 0.22, 0.24) else rgb(0.62, 0.46, 0.28))
        tufts(w, h, hz, if (night) rgb(0.2, 0.36, 0.26) else rgb(0.3, 0.52, 0.16))
        // The cottage: green clapboard, a red shingle roof, a chimney, door and window.
        val cw = w * 0.3; val ch = h * 0.12
        val house = CMRect(w * 0.24, hz + h * 0.015 - ch, cw, ch)
        rect(house, if (night) rgb(0.22, 0.38, 0.36) else rgb(0.4, 0.66, 0.5))
        val boards = Path()
        var by = house.y + ch * 0.18
        while (by < house.maxY) { boards.m(house.x, by); boards.l(house.maxX, by); by += ch * 0.16 }
        stroke(boards, ink.op(0.25), 1.0)
        rectStroke(house, ink, 1.6)
        val chim = CMRect(house.maxX - cw * 0.25, house.y - ch * 0.75, cw * 0.1, ch * 0.5)
        rect(chim, rgb(0.55, 0.3, 0.24))
        rectStroke(chim, ink, 1.4)
        val roof = polyPath(house.x - cw * 0.1, house.y + 2, house.midX, house.y - ch * 0.75, house.maxX + cw * 0.1, house.y + 2)
        fill(roof, vgrad(listOf(rgb(0.82, 0.36, 0.2), rgb(0.6, 0.22, 0.12)), house.y - ch * 0.75, house.y))
        clipPath(roof) {
            val rows = Path()
            var ry = house.y - ch * 0.6
            while (ry < house.y) { rows.m(house.x - cw * 0.2, ry); rows.l(house.maxX + cw * 0.2, ry); ry += ch * 0.14 }
            stroke(rows, ink.op(0.3), 1.0)
        }
        stroke(roof, ink, 1.6)
        val door = CMRect(house.x + cw * 0.18, house.maxY - ch * 0.62, cw * 0.2, ch * 0.62)
        rrect(door, door.w * 0.4, rgb(0.42, 0.24, 0.12))
        rrectStroke(door, door.w * 0.4, ink, 1.4)
        val win = CMRect(house.x + cw * 0.55, house.y + ch * 0.25, cw * 0.26, ch * 0.4)
        rect(win, if (night) rgb(1.0, 0.85, 0.4) else rgb(0.3, 0.45, 0.6))
        val mullion = Path().apply { m(win.midX, win.y); l(win.midX, win.maxY); m(win.x, win.midY); l(win.maxX, win.midY) }
        stroke(mullion, ink, 1.2)
        rectStroke(win, ink, 1.4)
        // A picket fence along the horizon.
        val pickets = Path()
        var px = 0.0
        while (px < w) {
            if (px < house.x - 6 || px > house.maxX + 6) pickets.box(px, hz - h * 0.03, w * 0.022, h * 0.04)
            px += w * 0.04
        }
        pickets.box(0.0, hz - h * 0.022, house.x - 6, h * 0.008)
        pickets.box(house.maxX + 6, hz - h * 0.022, w - house.maxX - 6, h * 0.008)
        fill(pickets, if (night) rgb(0.55, 0.58, 0.68) else rgb(0.96, 0.88, 0.75))
        stroke(pickets, ink.op(0.7), 0.8)
    }

    private fun DrawScope.temple(w: Double, h: Double, night: Boolean) {
        val hz = h * 0.34
        sky(w, if (night) listOf(rgb(0.45, 0.1, 0.22), rgb(0.95, 0.38, 0.18), rgb(1.0, 0.72, 0.32))
               else listOf(rgb(0.92, 0.78, 0.22), rgb(1.0, 0.92, 0.5), rgb(1.0, 0.97, 0.75)), hz)
        val sx = w * 0.5; val sy = h * 0.12
        circle(sx, sy, h * 0.2, glow(listOf(Color.White.op(0.9), rgb(1.0, 0.95, 0.6).op(0.5)), sx, sy, h * 0.2))
        // Jungle canopy on both sides.
        val canopy = Path()
        for (k in 0 until 14) {
            val x = w * k / 13
            if (abs(x - w / 2) < w * 0.24) continue
            val r = h * (0.05 + 0.03 * hash(k * 2.3))
            canopy.oval(x - r, hz - r * 1.7, r * 2, r * 2)
        }
        canopy.box(0.0, hz - h * 0.05, w, h * 0.05)
        fill(canopy, if (night) rgb(0.2, 0.16, 0.12) else rgb(0.2, 0.42, 0.14))
        // The stepped temple with a carved monkey face over the door.
        val stone = if (night) rgb(0.72, 0.48, 0.3) else rgb(0.9, 0.74, 0.42)
        val tiers = 4
        for (k in 0 until tiers) {
            val tw = w * (0.56 - 0.1 * k); val th = h * 0.045
            val r = CMRect(w / 2 - tw / 2, hz - th * (k + 1), tw, th)
            rect(r, vgrad(listOf(stone.lit(0.15), stone.shade(0.15)), r.y, r.maxY))
            val blocks = Path()
            var bx = r.x + th * 1.2
            while (bx < r.maxX) { blocks.m(bx, r.y); blocks.l(bx, r.maxY); bx += th * 1.6 }
            stroke(blocks, ink.op(0.3), 1.0)
            rectStroke(r, ink, 1.4)
        }
        val shrine = CMRect(w / 2 - w * 0.12, hz - h * 0.045 * tiers - h * 0.1, w * 0.24, h * 0.1)
        rect(shrine, stone)
        rectStroke(shrine, ink, 1.6)
        val fcx = shrine.midX; val fcy = shrine.y + shrine.h * 0.42
        val fr = shrine.h * 0.3
        for (side in listOf(-1.0, 1.0)) circle(fcx + side * fr, fcy, fr * 0.38, stone.shade(0.25))
        circle(fcx, fcy, fr, stone.shade(0.2))
        stroke(ovalPath(fcx, fcy, fr, fr), ink, 1.2)
        for (side in listOf(-1.0, 1.0)) ellipse(fcx + side * fr * 0.38, fcy - fr * 0.1, fr * 0.18, fr * 0.24, ink)
        rect(shrine.midX - shrine.w * 0.14, shrine.maxY - shrine.h * 0.28, shrine.w * 0.28, shrine.h * 0.28, ink)
        // Vines.
        val vines = Path()
        for ((fx, len) in listOf(0.3 to 0.12, 0.62 to 0.09, 0.69 to 0.14)) {
            vines.m(w * fx, hz - h * 0.18)
            vines.c(w * fx + 8, hz - h * 0.14, w * fx - 8, hz - h * 0.1, w * fx + 4, hz - h * 0.18 + h * len)
        }
        stroke(vines, rgb(0.18, 0.5, 0.14), 2.5, StrokeCap.Round)
        // Courtyard flagstones in perspective.
        val floor = if (night) listOf(rgb(0.62, 0.42, 0.3), rgb(0.42, 0.26, 0.18)) else listOf(rgb(0.86, 0.74, 0.5), rgb(0.66, 0.52, 0.32))
        rect(0.0, hz, w, h - hz, vgrad(floor, hz, h))
        val grid = Path()
        var gy = hz
        var step = h * 0.03
        while (gy < h) { grid.m(0.0, gy); grid.l(w, gy); gy += step; step *= 1.25 }
        for (k in -6..6) {
            grid.m(w / 2 + k * w * 0.06, hz)
            grid.l(w / 2 + k * w * 0.3, h)
        }
        stroke(grid, ink.op(0.22), 1.0)
    }

    private fun DrawScope.deck(w: Double, h: Double, night: Boolean) {
        val hz = h * 0.34
        sky(w, if (night) listOf(rgb(0.14, 0.16, 0.2), rgb(0.3, 0.36, 0.38), rgb(0.46, 0.52, 0.5))
               else listOf(rgb(0.32, 0.62, 0.95), rgb(0.62, 0.84, 1.0), rgb(0.86, 0.95, 1.0)), hz)
        if (night) {
            val rain = Path()
            for (k in 0 until 40) {
                val x = w * hash(k * 2.7); val y = hz * hash(k * 5.9)
                rain.m(x, y); rain.l(x - 6, y + 16)
            }
            stroke(rain, Color.White.op(0.35), 1.0)
        } else {
            val clouds = Path()
            for ((fx, fy, r) in listOf(Triple(0.2, 0.08, 0.05), Triple(0.8, 0.14, 0.04))) {
                for (k in 0 until 3) clouds.oval(w * fx + (k - 1) * h * r * 1.1 - h * r, h * fy - (if (k == 1) h * r * 0.5 else 0.0), h * r * 2, h * r * 1.4)
            }
            fill(clouds, Color.White.op(0.9))
        }
        // The sea.
        rect(0.0, hz - h * 0.07, w, h * 0.07, if (night) rgb(0.12, 0.24, 0.28) else rgb(0.12, 0.42, 0.75))
        val waves = Path()
        for (k in 0 until 12) { val x = w * k / 11; waves.m(x - 8, hz - h * 0.04); waves.q(x, hz - h * 0.05, x + 8, hz - h * 0.04) }
        stroke(waves, Color.White.op(0.5), 1.2)
        // Mast, yard, sail and rigging.
        val mastX = w * 0.5
        val shrouds = Path()
        for (k in 0 until 4) {
            val f = k / 3.0
            shrouds.m(mastX, h * 0.04); shrouds.l(w * (0.08 + 0.1 * f), hz)
            shrouds.m(mastX, h * 0.04); shrouds.l(w * (0.92 - 0.1 * f), hz)
        }
        stroke(shrouds, rgb(0.3, 0.22, 0.14), 1.4)
        val sail = Path().apply {
            m(mastX - w * 0.26, h * 0.06)
            l(mastX + w * 0.26, h * 0.06)
            q(mastX + w * 0.32, h * 0.15, mastX + w * 0.22, h * 0.24)
            q(mastX, h * 0.28, mastX - w * 0.22, h * 0.24)
            q(mastX - w * 0.32, h * 0.15, mastX - w * 0.26, h * 0.06)
        }
        fill(sail, hgrad(listOf(rgb(0.98, 0.94, 0.84), rgb(0.82, 0.74, 0.6)), mastX - w * 0.2, mastX + w * 0.25))
        stroke(sail, ink, 1.4)
        rect(mastX - w * 0.018, 0.0, w * 0.036, hz, hgrad(listOf(rgb(0.5, 0.32, 0.16), rgb(0.7, 0.48, 0.26), rgb(0.45, 0.28, 0.13)), mastX - w * 0.018, mastX + w * 0.018))
        rectStroke(mastX - w * 0.018, 0.0, w * 0.036, hz, ink, 1.2)
        rrect(mastX - w * 0.28, h * 0.045, w * 0.56, h * 0.018, 3.0, rgb(0.5, 0.32, 0.16))
        // Deck planks running toward you, and the rail at the far edge.
        val plank = if (night) listOf(rgb(0.42, 0.3, 0.2), rgb(0.26, 0.18, 0.12)) else listOf(rgb(0.74, 0.52, 0.3), rgb(0.52, 0.34, 0.18))
        rect(0.0, hz, w, h - hz, vgrad(plank, hz, h))
        val seams = Path()
        for (k in -8..8) { seams.m(w / 2 + k * w * 0.05, hz); seams.l(w / 2 + k * w * 0.17, h) }
        stroke(seams, ink.op(0.35), 1.0)
        val rail = Path()
        rail.box(0.0, hz - h * 0.035, w, h * 0.012)
        var px = w * 0.02
        while (px < w) { rail.box(px, hz - h * 0.035, w * 0.014, h * 0.035); px += w * 0.07 }
        fill(rail, rgb(0.55, 0.36, 0.18))
        stroke(rail, ink.op(0.8), 0.8)
    }

    private fun DrawScope.reef(w: Double, h: Double) {
        val hz = h * 0.36
        sky(w, listOf(rgb(0.2, 0.62, 0.78), rgb(0.16, 0.3, 0.62), rgb(0.3, 0.18, 0.5)), hz)
        val rays = Path()
        for (k in 0 until 5) {
            val x = w * (0.1 + 0.2 * k)
            rays.m(x, 0.0); rays.l(x + w * 0.06, 0.0); rays.l(x + w * 0.16, hz); rays.l(x + w * 0.06, hz); rays.close()
        }
        fill(rays, Color.White.op(0.07))
        // Far coral silhouettes.
        val far = Path()
        for (k in 0 until 9) {
            val x = w * k / 8; val r = h * (0.04 + 0.03 * hash(k * 4.1))
            far.oval(x - r, hz - r * 1.5, r * 2, r * 2.2)
        }
        fill(far, rgb(0.3, 0.14, 0.4))
        // Sea floor.
        rect(0.0, hz, w, h - hz, vgrad(listOf(rgb(0.62, 0.46, 0.66), rgb(0.42, 0.3, 0.5)), hz, h))
        val ripples = Path()
        for (k in 0 until 10) {
            val y = hz + (h - hz) * k / 10 + 6; val x = w * hash(k * 1.9)
            ripples.m(x - 20, y); ripples.q(x, y - 4, x + 20, y)
        }
        stroke(ripples, Color.White.op(0.18), 1.2)
        // Seaweed and bubbles.
        val weed = Path()
        for ((fx, len) in listOf(0.06 to 0.2, 0.12 to 0.14, 0.94 to 0.22, 0.88 to 0.12)) {
            weed.m(w * fx, hz + h * 0.04)
            weed.c(w * fx + 12, hz - h * len * 0.3, w * fx - 12, hz - h * len * 0.6, w * fx + 4, hz + h * 0.04 - h * len)
        }
        stroke(weed, rgb(0.2, 0.6, 0.4), 4.0, StrokeCap.Round)
        val bubbles = Path()
        for (k in 0 until 12) {
            val x = w * hash(k * 6.1); val y = hz * hash(k * 3.3); val r = 2 + 4 * hash(k.toDouble())
            bubbles.oval(x - r, y - r, r * 2, r * 2)
        }
        stroke(bubbles, Color.White.op(0.5), 1.2)
    }

    private fun DrawScope.tufts(w: Double, h: Double, y0: Double, color: Color) {
        val t = Path()
        for (k in 0 until 30) {
            val x = w * hash(k * 2.9); val y = y0 + (h - y0) * hash(k * 5.7)
            t.m(x - 3, y); t.l(x - 1, y - 6)
            t.m(x + 1, y); t.l(x + 3, y - 7)
        }
        stroke(t, color, 1.4)
    }

    /** The card behind the scene and the lock: dark stained wood. */
    fun DrawScope.frame(w: Double, h: Double) {
        rect(0.0, 0.0, w, h, vgrad(listOf(rgb(0.24, 0.14, 0.08), rgb(0.13, 0.07, 0.04)), 0.0, h))
        val grain = Path()
        for (k in 0 until 18) {
            val y = h * hash(k * 3.3)
            grain.m(0.0, y); grain.c(w * 0.3, y - 5, w * 0.7, y + 9, w, y + 6)
        }
        stroke(grain, Color.Black.op(0.2), 1.0)
    }

    /** The lock panel's wooden plank with nails. */
    fun DrawScope.plank(w: Double, h: Double) {
        val wood = rgb(0.62, 0.4, 0.2)
        rect(0.0, 0.0, w, h, vgrad(listOf(wood.lit(0.12), wood.shade(0.2)), 0.0, h))
        stroke(Path().apply { m(0.0, h / 2); l(w, h / 2) }, Color.Black.op(0.3), 1.5)
        val grain = Path()
        for (k in 0 until 8) {
            val y = h * hash(k * 7.7)
            grain.m(0.0, y); grain.q(w / 2, y - 4, w, y + 3)
        }
        stroke(grain, Color.Black.op(0.12), 1.0)
        for ((x, y) in listOf(8.0 to 8.0, w - 8 to 8.0, 8.0 to h - 8, w - 8 to h - 8)) {
            circle(x, y, 2.6, gray(0.3))
            circle(x - 0.6, y - 0.6, 1.0, gray(0.8))
        }
    }

    /**
     * One lock wheel: a brass bezel, a frame in the wheel's colour, and a cream drum showing the current
     * symbol (or dice pips) painted in that colour. `down` (pressed) brightens it a touch.
     */
    fun DrawScope.wheelFace(w: Double, h: Double, hue: CMHue, count: Boolean, face: Int, open: Boolean, compact: Boolean, down: Boolean) {
        val r = CMRect(1.0, 1.0, w - 2, h - 2)
        val brass = rgb(0.92, 0.72, 0.3)
        rrect(r.x + 1.5, r.y + 2.5, r.w, r.h, r.w * 0.18, Color.Black.op(0.4))
        rrect(r, r.w * 0.18, vgrad(listOf(brass.lit(0.35), brass, brass.shade(0.35)), r.y, r.maxY))
        val frame = r.inset(r.w * 0.09, r.h * 0.07)
        rrect(frame, frame.w * 0.14, color(hue))
        val drum = frame.inset(frame.w * 0.12, frame.h * 0.08)
        rrect(drum, drum.w * 0.1, vgrad(listOf(rgb(0.72, 0.66, 0.56), rgb(1.0, 0.98, 0.9), rgb(1.0, 0.98, 0.9), rgb(0.72, 0.66, 0.56)), drum.y, drum.maxY))
        val side = min(drum.w, drum.h) * 0.72
        val bx = drum.midX - side / 2; val by = drum.midY - side / 2
        val mark = if (count) pips(face + 1, bx, by, side, side) else glyph(face, bx, by, side, side)
        fill(mark, color(hue))
        stroke(mark, ink.op(0.85), if (compact) 1.0 else 1.4)
        rrectStroke(drum, drum.w * 0.1, ink.op(0.7), 1.0)
        rrectStroke(r, r.w * 0.18, ink, if (compact) 1.4 else 2.0)
        if (open) rrectStroke(frame, frame.w * 0.14, rgb(0.6, 1.0, 0.5), if (compact) 2.0 else 3.0)
        if (down) rrect(r, r.w * 0.18, Color.White.op(0.06))
    }
}
