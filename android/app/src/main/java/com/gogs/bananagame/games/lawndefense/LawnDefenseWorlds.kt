package com.gogs.bananagame.games.lawndefense

import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathOperation
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import com.gogs.bananagame.core.*
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.sin

// Lawn Defense's worlds (iOS LawnDefenseArt.swift, first part): colours, sky backdrop, lawn, seed bar.

/** A world's colours. */
class LDLook(
    val skyTop: Color, val skyBottom: Color, val tileLight: Color, val tileDark: Color, val tileMark: Color,
    val yardTop: Color, val yardBottom: Color, val bar: List<Color>, val barEdge: Color, val sprite: Color?,
) {
    companion object {
        fun of(s: LDScene): LDLook = when (s) {
            LDScene.BACKYARD -> LDLook(rgb(0.42, 0.7, 0.95), rgb(0.78, 0.9, 0.98), rgb(0.43, 0.74, 0.17), rgb(0.35, 0.64, 0.12),
                rgb(0.25, 0.5, 0.08), rgb(0.24, 0.52, 0.12), rgb(0.14, 0.36, 0.08), listOf(rgb(0.62, 0.4, 0.2), rgb(0.45, 0.27, 0.12)),
                rgb(0.24, 0.13, 0.05), null)
            LDScene.DESERT -> LDLook(rgb(0.55, 0.78, 0.95), rgb(0.98, 0.88, 0.66), rgb(0.93, 0.8, 0.55), rgb(0.86, 0.71, 0.45),
                rgb(0.66, 0.5, 0.28), rgb(0.9, 0.74, 0.47), rgb(0.78, 0.6, 0.35), listOf(rgb(0.86, 0.7, 0.45), rgb(0.7, 0.53, 0.3)),
                rgb(0.42, 0.28, 0.12), null)
            LDScene.PIRATE -> LDLook(rgb(0.36, 0.68, 0.95), rgb(0.75, 0.9, 1.0), rgb(0.72, 0.5, 0.3), rgb(0.62, 0.41, 0.23),
                rgb(0.36, 0.22, 0.1), rgb(0.12, 0.42, 0.62), rgb(0.06, 0.24, 0.42), listOf(rgb(0.42, 0.25, 0.13), rgb(0.3, 0.17, 0.08)),
                rgb(0.78, 0.6, 0.25), null)
            LDScene.FRONTIER -> LDLook(rgb(0.55, 0.4, 0.62), rgb(1.0, 0.66, 0.38), rgb(0.78, 0.66, 0.38), rgb(0.7, 0.57, 0.3),
                rgb(0.5, 0.38, 0.18), rgb(0.72, 0.5, 0.3), rgb(0.55, 0.34, 0.2), listOf(rgb(0.72, 0.56, 0.4), rgb(0.55, 0.4, 0.27)),
                rgb(0.32, 0.2, 0.1), rgb(1.0, 0.88, 0.8))
            LDScene.GLACIER -> LDLook(rgb(0.1, 0.18, 0.36), rgb(0.36, 0.55, 0.75), rgb(0.9, 0.96, 1.0), rgb(0.78, 0.88, 0.97),
                rgb(0.55, 0.72, 0.9), rgb(0.86, 0.93, 0.99), rgb(0.6, 0.75, 0.9), listOf(rgb(0.6, 0.78, 0.92), rgb(0.4, 0.58, 0.78)),
                rgb(0.16, 0.3, 0.5), rgb(0.9, 0.95, 1.0))
            LDScene.FUTURE -> LDLook(rgb(0.07, 0.03, 0.2), rgb(0.32, 0.12, 0.45), rgb(0.3, 0.34, 0.46), rgb(0.23, 0.26, 0.37),
                rgb(0.2, 0.95, 0.95), rgb(0.14, 0.1, 0.26), rgb(0.06, 0.04, 0.14), listOf(rgb(0.5, 0.54, 0.62), rgb(0.3, 0.33, 0.42)),
                rgb(0.2, 0.95, 0.95), rgb(0.88, 0.9, 1.0))
            LDScene.ROOFTOP -> LDLook(rgb(0.04, 0.05, 0.16), rgb(0.16, 0.18, 0.38), rgb(0.4, 0.36, 0.58), rgb(0.33, 0.29, 0.5),
                rgb(0.2, 0.17, 0.32), rgb(0.22, 0.18, 0.32), rgb(0.1, 0.08, 0.18), listOf(rgb(0.42, 0.28, 0.2), rgb(0.28, 0.17, 0.12)),
                rgb(0.14, 0.08, 0.05), rgb(0.78, 0.8, 1.0))
        }
    }
}

// Path builders in Double coordinates.
internal fun Path.rectD(x: Double, y: Double, w: Double, h: Double) = addRect(Rect(x.f, y.f, (x + w).f, (y + h).f))
internal fun Path.ovalD(x: Double, y: Double, w: Double, h: Double) = addOval(Rect(x.f, y.f, (x + w).f, (y + h).f))
internal fun Path.rrectD(x: Double, y: Double, w: Double, h: Double, r: Double) =
    addRoundRect(RoundRect(Rect(x.f, y.f, (x + w).f, (y + h).f), CornerRadius(r.f, r.f)))
internal fun DrawScope.stroke(p: Path, c: Color, lw: Double, cap: StrokeCap = StrokeCap.Butt) =
    drawPath(p, c, style = Stroke(lw.f, cap = cap, join = androidx.compose.ui.graphics.StrokeJoin.Round))

object LDWorlds {
    fun hash(n: Double): Double { val v = sin(n * 12.9898) * 43758.5453; return v - floor(v) }

    // Backdrop pieces

    fun DrawScope.clouds(w: Double, h: Double, alpha: Double) {
        val u = density.toDouble()
        val p = Path()
        for (i in 0 until 4) {
            val x = hash(i * 5.7) * w; val y = 20 * u + hash(i * 2.9) * h * 0.25
            for (k in 0 until 3) p.ovalD(x + k * 18 * u - 18 * u, y - (if (k == 1) 10 else 4) * u, 34 * u, 22 * u)
        }
        drawPath(p, Color.White.op(alpha))
    }

    fun DrawScope.hedge(w: Double, h: Double, color: Color) {
        val u = density.toDouble()
        val p = Path()
        var x = -10 * u
        while (x < w + 10 * u) { p.ovalD(x, h - 46 * u, 46 * u, 40 * u); x += 30 * u }
        p.rectD(0.0, h - 26 * u, w, 26 * u)
        drawPath(p, color)
    }

    fun DrawScope.stars(w: Double, h: Double, count: Int, alpha: Double) {
        val u = density.toDouble()
        val p = Path()
        for (i in 0 until count) {
            val x = hash(i * 3.3) * w; val y = hash(i * 7.1) * h * 0.5
            val r = (if (i % 5 == 0) 2.2 else 1.5) * u
            p.ovalD(x, y, r, r)
        }
        drawPath(p, Color.White.op(alpha))
    }

    fun DrawScope.waves(y: Double, width: Double, color: Color) {
        val u = density.toDouble()
        val p = Path()
        var x = 4 * u
        while (x < width) { p.m(x, y); p.q(x + 7 * u, y - 5 * u, x + 14 * u, y); x += 26 * u }
        stroke(p, color, 1.5 * u)
    }

    fun DrawScope.icicles(width: Double, top: Double, length: Double, color: Color) {
        val u = density.toDouble()
        val p = Path()
        var x = 0.0
        var i = 0.0
        while (x < width) {
            val w = (8 + hash(i) * 8) * u
            val l = length * (0.5 + hash(i + 0.5))
            p.m(x, top); p.l(x + w / 2, top + l); p.l(x + w, top); p.close()
            x += w + 2 * u; i += 1
        }
        drawPath(p, color)
    }

    fun DrawScope.aurora(w: Double, h: Double) {
        val u = density.toDouble()
        for ((k, col) in listOf(rgb(0.3, 1.0, 0.7), rgb(0.5, 0.7, 1.0)).withIndex()) {
            val y = h * (0.08 + k * 0.06)
            val p = Path(); p.m(-10 * u, y); p.c(w * 0.3, y - 26 * u, w * 0.6, y + 34 * u, w + 10 * u, y + 10 * u)
            stroke(p, col.op(0.3), 12 * u, StrokeCap.Round)
        }
    }

    fun DrawScope.skyline(w: Double, base: Double, height: Double, color: Color, lights: Color) {
        val u = density.toDouble()
        val towers = Path(); val windows = Path()
        var x = -4 * u
        var i = 0.0
        while (x < w) {
            val tw = (14 + hash(i * 1.7) * 16) * u
            val th = height * (0.45 + hash(i * 2.3) * 0.55)
            towers.rectD(x, base - th, tw, th)
            var wy = base - th + 5 * u
            while (wy < base - 4 * u) {
                val wyPt = wy / u
                if (hash(i * 9.1 + wyPt) > 0.55) windows.rectD(x + 3 * u, wy, 2.5 * u, 2.5 * u)
                if (hash(i * 4.3 + wyPt) > 0.6) windows.rectD(x + tw - 6 * u, wy, 2.5 * u, 2.5 * u)
                wy += 6 * u
            }
            x += tw + 2 * u; i += 1
        }
        drawPath(towers, color)
        drawPath(windows, lights.op(0.8))
    }

    /** The sky behind the seed bar and the meter. */
    fun backdrop(d: DrawScope, scene: LDScene) = with(d) {
        val w = size.width.toDouble(); val h = size.height.toDouble()
        val u = density.toDouble()
        val look = LDLook.of(scene)
        drawRect(vgrad(listOf(look.skyTop, look.skyBottom), 0.0, h))
        when (scene) {
            LDScene.BACKYARD -> { clouds(w, h, 0.6); hedge(w, h, rgb(0.16, 0.42, 0.14)) }
            LDScene.DESERT -> {
                circle(w * 0.82, h * 0.06, 26 * u, rgb(1.0, 0.97, 0.8, 0.9))
                val dunes = Path()
                dunes.m(0.0, h); dunes.l(0.0, h - 40 * u)
                dunes.q(w * 0.2, h - 62 * u, w * 0.45, h - 30 * u)
                dunes.q(w * 0.75, h - 6 * u, w, h - 44 * u)
                dunes.l(w, h)
                drawPath(dunes, rgb(0.86, 0.68, 0.42))
            }
            LDScene.PIRATE -> {
                clouds(w, h, 0.7)
                rect(0.0, h - 44 * u, w, 44 * u, vgrad(listOf(rgb(0.12, 0.45, 0.68), rgb(0.05, 0.25, 0.45)), h - 44 * u, h))
                waves(h - 40 * u, w, Color.White.op(0.5))
            }
            LDScene.FRONTIER -> {
                circle(w * 0.2, h * 0.07, 22 * u, rgb(1.0, 0.85, 0.5, 0.85))
                val scrub = Path()
                scrub.rectD(0.0, h - 30 * u, w, 30 * u)
                var x = 12 * u
                while (x < w) { scrub.ovalD(x, h - 40 * u, 22 * u, 16 * u); x += 58 * u }
                drawPath(scrub, rgb(0.5, 0.32, 0.2))
            }
            LDScene.GLACIER -> {
                icicles(w, 0.0, 26 * u, rgb(0.75, 0.9, 1.0, 0.85))
                aurora(w, h)
                val snow = Path()
                var x = -10 * u
                while (x < w + 10 * u) { snow.ovalD(x, h - 40 * u, 60 * u, 40 * u); x += 44 * u }
                snow.rectD(0.0, h - 22 * u, w, 22 * u)
                drawPath(snow, rgb(0.92, 0.97, 1.0))
            }
            LDScene.FUTURE -> {
                stars(w, h, 30, 0.6)
                skyline(w, h, 46 * u, rgb(0.12, 0.06, 0.24), rgb(0.3, 1.0, 1.0))
            }
            LDScene.ROOFTOP -> {
                stars(w, h, 46, 0.8)
                val mx = w * 0.14; val my = h * 0.06
                val a = Path(); a.ovalD(mx - 18 * u, my - 18 * u, 36 * u, 36 * u)
                val b = Path(); b.ovalD(mx - 9 * u, my - 22 * u, 36 * u, 36 * u)
                drawPath(Path.combine(PathOperation.Difference, a, b), rgb(1.0, 0.97, 0.85))
                skyline(w, h, 34 * u, rgb(0.08, 0.06, 0.16), rgb(1.0, 0.85, 0.4))
            }
        }
    }

    /** The lawn between the house (left) and the street (right), dressed for each world. */
    fun lawn(d: DrawScope, scene: LDScene, rowsInPlay: List<Int>, shown: List<Int>) = with(d) {
        val w = size.width.toDouble(); val h = size.height.toDouble()
        val look = LDLook.of(scene)
        val lay = LDLayout(w, h, shown)
        val cw = lay.cellW; val ch = lay.cellH
        val top = lay.point(0.0, (shown.firstOrNull() ?: 0).toDouble()).y
        val bottom = top + ch * shown.size
        val left = lay.ox - cw * 0.62; val right = lay.ox + cw * 7.78
        val streetX = lay.ox + cw * 7
        val yardH = max(0.0, h - bottom)
        rect(0.0, bottom, w, yardH, vgrad(listOf(look.yardTop, look.yardBottom), bottom, bottom + yardH))
        yardDressing(scene, bottom, yardH, w, left, right, cw)
        topEdge(scene, left, right, top, cw)
        street(scene, streetX, right, top - 2 * density, max(bottom, h), cw)
        patio(scene, left, top, cw * 0.62, bottom - top, ch)
        for (r in shown) for (c in 0 until LDWorld.COLS) {
            val o = lay.point(c.toDouble(), r.toDouble())
            tile(scene, look, o.x, o.y, cw + 0.5, ch + 0.5, r, c, r in rowsInPlay)
        }
        val sh = 6 * density.toDouble()
        rect(lay.ox, top, cw * 7, sh, vgrad(listOf(Color.Black.op(0.22), Color.Transparent), top, top + sh))
    }

    /** The seed bar's background: planks, sandstone, ship's timber, ice or brushed metal. */
    fun seedBar(d: DrawScope, scene: LDScene) = with(d) {
        val w = size.width.toDouble(); val h = size.height.toDouble()
        val u = density.toDouble()
        val look = LDLook.of(scene)
        drawRect(vgrad(look.bar, 0.0, h))
        when (scene) {
            LDScene.DESERT -> {
                val j = Path()
                for (i in 1 until 3) { j.m(0.0, h * i / 3); j.l(w, h * i / 3) }
                for (i in 0 until 8) {
                    val row = i % 3
                    val x = w * (i / 8.0 + (if (row == 1) 0.06 else 0.0))
                    j.m(x, h * row / 3); j.l(x, h * (row + 1) / 3)
                }
                stroke(j, rgb(0.55, 0.4, 0.2, 0.45), u)
            }
            LDScene.FUTURE -> {
                val seams = Path()
                for (i in 1 until 4) { seams.m(w * i / 4, 0.0); seams.l(w * i / 4, h) }
                stroke(seams, Color.Black.op(0.25), u)
                for (i in 0..4) for (y in listOf(5 * u, h - 5 * u)) circle(w * i / 4, y, 2 * u, Color.White.op(0.35))
            }
            LDScene.GLACIER -> {
                val fr = Path()
                for (i in 0 until 9) {
                    val x = w * hash(i * 3.7); val y = h * hash(i * 5.3)
                    fr.m(x - 4 * u, y); fr.l(x + 4 * u, y); fr.m(x, y - 4 * u); fr.l(x, y + 4 * u)
                }
                stroke(fr, Color.White.op(0.5), u)
                icicles(w, h - u, -6 * u, Color.White.op(0.4))
            }
            else -> {
                val grain = Path()
                for (i in 0 until 6) {
                    val y = h * (i + 1) / 7
                    grain.m(0.0, y); grain.c(w * 0.3, y - 4 * u, w * 0.7, y + 5 * u, w, y + 3 * u)
                }
                stroke(grain, rgb(0.2, 0.1, 0.04, 0.3), u)
                if (scene == LDScene.PIRATE) for (i in 0..6) for (y in listOf(6 * u, h - 6 * u)) circle(w * i / 6, y, 2.5 * u, rgb(0.85, 0.68, 0.3))
            }
        }
    }

    // Lawn pieces

    private fun DrawScope.tile(scene: LDScene, look: LDLook, x: Double, y: Double, w: Double, h: Double, r: Int, c: Int, inPlay: Boolean) {
        val u = density.toDouble()
        val light = (r + c) % 2 == 0
        if (!inPlay) { rect(x, y, w, h, look.tileDark.mix(Color.Black, 0.35)); return }
        rect(x, y, w, h, if (light) look.tileLight else look.tileDark)
        val seed = (r * 31 + c * 7).toDouble()
        val maxX = x + w; val maxY = y + h
        when (scene) {
            LDScene.BACKYARD -> {
                val p = Path()
                for (b in 0 until 5) {
                    val bx = x + w * hash(seed + b); val by = y + h * hash((r * 13 + c * 17 + b) + 0.5)
                    p.m(bx, by); p.l(bx - 1.5 * u, by - 5 * u); p.m(bx, by); p.l(bx + 1.5 * u, by - 5 * u)
                }
                stroke(p, look.tileMark.op(0.55), u)
            }
            LDScene.ROOFTOP -> {
                val edges = Path(); val joints = Path()
                for (k in 0 until 3) {
                    val y0 = y + h * k / 3; val y1 = y + h * (k + 1) / 3
                    edges.rectD(x, y1 - 2.5 * u, w, 2.5 * u)
                    val sw = w / 3
                    var jx = x + (if (k % 2 == 0) sw * 0.5 else sw)
                    while (jx < maxX - 2 * u) { joints.m(jx, y0); joints.l(jx, y1); jx += sw }
                }
                drawPath(edges, look.tileMark.op(0.55))
                stroke(joints, look.tileMark.op(0.7), u)
            }
            LDScene.PIRATE -> {
                val seams = Path(); val nails = Path()
                val n = 4
                for (k in 1 until n) { val sx = x + w * k / n; seams.m(sx, y); seams.l(sx, maxY) }
                for (k in 0 until n) {
                    val x0 = x + w * k / n
                    val jy = y + h * (0.2 + 0.6 * hash(seed + k * 1.3))
                    seams.m(x0, jy); seams.l(x0 + w / n, jy)
                    val nx = x0 + w / n / 2
                    nails.ovalD(nx - u, jy - 4 * u, 2 * u, 2 * u)
                    nails.ovalD(nx - u, jy + 2 * u, 2 * u, 2 * u)
                }
                stroke(seams, look.tileMark.op(0.55), u)
                drawPath(nails, look.tileMark.op(0.8))
            }
            LDScene.DESERT -> {
                val cx = x + w * hash(seed + 0.3); val cy = y + h * hash(seed + 0.7)
                val cr = Path(); cr.m(cx, cy); cr.l(cx + 6 * u, cy + 4 * u); cr.l(cx + 9 * u, cy + 2 * u)
                stroke(cr, look.tileMark.op(0.5), u)
                val pb = Path()
                for (b in 0 until 3) pb.ovalD(x + w * hash(seed + b * 1.9), y + h * hash(seed + b * 2.3 + 0.4), 3.5 * u, 2.5 * u)
                drawPath(pb, look.tileMark.op(0.45))
            }
            LDScene.FRONTIER -> {
                val p = Path()
                for (b in 0 until 3) {
                    val bx = x + w * hash(seed + b); val by = y + h * hash((r * 13 + c * 17 + b) + 0.5)
                    p.m(bx, by); p.l(bx - 2 * u, by - 5 * u); p.m(bx, by); p.l(bx + 2 * u, by - 4 * u); p.m(bx, by); p.l(bx, by - 6 * u)
                }
                stroke(p, look.tileMark.op(0.55), u)
            }
            LDScene.GLACIER -> {
                val sp = Path()
                for (b in 0 until 2) {
                    val sx = x + w * hash(seed + b * 3.1); val sy = y + h * hash(seed + b * 1.7 + 0.2)
                    sp.m(sx - 3 * u, sy); sp.l(sx + 3 * u, sy); sp.m(sx, sy - 3 * u); sp.l(sx, sy + 3 * u)
                }
                stroke(sp, Color.White, u)
                val cx = x + w * hash(seed + 0.9); val cy = y + h * hash(seed + 0.1)
                val cr = Path(); cr.m(cx, cy); cr.l(cx + 8 * u, cy + 6 * u); cr.l(cx + 5 * u, cy + 12 * u)
                stroke(cr, look.tileMark.op(0.6), u)
            }
            LDScene.FUTURE -> {
                val i = 2.5 * u
                rrectStroke(x + i, y + i, w - 2 * i, h - 2 * i, 3 * u, look.tileMark.op(if (light) 0.35 else 0.22), u)
                for ((px, py) in listOf(x + i + 4 * u to y + i + 4 * u, maxX - i - 4 * u to y + i + 4 * u,
                    x + i + 4 * u to maxY - i - 4 * u, maxX - i - 4 * u to maxY - i - 4 * u)) circle(px, py, 1.2 * u, Color.White.op(0.3))
            }
        }
    }

    private fun DrawScope.topEdge(scene: LDScene, left: Double, right: Double, top: Double, cw: Double) {
        val u = density.toDouble()
        when (scene) {
            LDScene.ROOFTOP -> {
                rect(left, top - cw * 0.3, right - left, cw * 0.3, rgb(0.22, 0.18, 0.34))
                rect(left, top - cw * 0.33, right - left, cw * 0.06, rgb(0.4, 0.35, 0.55))
                val cx = left + (right - left) * 0.62; val cy = top - cw * 0.85; val cwd = cw * 0.55; val chh = cw * 0.6
                rect(cx, cy, cwd, chh, rgb(0.45, 0.22, 0.18))
                val br = Path()
                for (k in 1 until 4) { br.m(cx, cy + chh * k / 4); br.l(cx + cwd, cy + chh * k / 4) }
                stroke(br, Color.Black.op(0.3), u)
                rect(cx - 3 * u, cy - 4 * u, cwd + 6 * u, 5 * u, rgb(0.3, 0.16, 0.14))
            }
            LDScene.BACKYARD -> {
                val fenceTop = top - cw * 0.55
                val p = Path()
                var px = left
                while (px < right) {
                    p.m(px, top); p.l(px, fenceTop + 6 * u); p.l(px + cw * 0.12, fenceTop); p.l(px + cw * 0.24, fenceTop + 6 * u); p.l(px + cw * 0.24, top); p.close()
                    px += cw * 0.34
                }
                drawPath(p, rgb(0.97, 0.95, 0.9))
                stroke(p, rgb(0.6, 0.55, 0.48), u)
                rect(left, fenceTop + cw * 0.22, right - left, cw * 0.08, rgb(0.88, 0.85, 0.78))
            }
            LDScene.DESERT -> {
                val wy = top - cw * 0.5; val wh = cw * 0.5; val mid = wy + wh / 2
                rect(left, wy, right - left, wh, rgb(0.88, 0.72, 0.48))
                val j = Path()
                j.m(left, mid); j.l(right, mid)
                var x = left; var k = 0
                while (x < right) { j.m(x, if (k % 2 == 0) wy else mid); j.l(x, if (k % 2 == 0) mid else wy + wh); x += cw * 0.7; k++ }
                stroke(j, rgb(0.6, 0.44, 0.24), u)
                val g = Path()
                x = left + cw * 0.3
                var gi = 0
                while (x < right - cw * 0.2) {
                    val y = wy + wh * 0.25
                    when (gi % 3) {
                        0 -> g.ovalD(x - 3 * u, y - 2 * u, 6 * u, 4 * u)
                        1 -> { g.m(x - 3 * u, y + 2 * u); g.l(x, y - 3 * u); g.l(x + 3 * u, y + 2 * u) }
                        else -> { g.m(x - 3 * u, y); g.q(x, y - 5 * u, x + 3 * u, y) }
                    }
                    x += cw * 0.36; gi++
                }
                stroke(g, rgb(0.5, 0.34, 0.16), 1.2 * u)
                rect(left, wy - 2 * u, right - left, 3 * u, rgb(0.95, 0.82, 0.58))
            }
            LDScene.PIRATE -> {
                val railY = top - cw * 0.5
                val posts = Path()
                var x = left + 2 * u
                while (x < right) { posts.rrectD(x, railY + 4 * u, cw * 0.12, top - railY - 4 * u, 3 * u); x += cw * 0.3 }
                drawPath(posts, rgb(0.5, 0.3, 0.15))
                stroke(posts, rgb(0.25, 0.13, 0.05), u)
                rrect(left, railY, right - left, cw * 0.13, 3 * u, rgb(0.42, 0.24, 0.11))
                rrectStroke(left, railY, right - left, cw * 0.13, 3 * u, rgb(0.2, 0.1, 0.04), u)
                val rope = Path()
                rope.m(left, railY + cw * 0.2)
                var rx = left
                while (rx < right) { rope.q(rx + cw * 0.45, railY + cw * 0.38, rx + cw * 0.9, railY + cw * 0.2); rx += cw * 0.9 }
                stroke(rope, rgb(0.85, 0.72, 0.45), 2 * u)
            }
            LDScene.FRONTIER -> {
                val fenceTop = top - cw * 0.5
                val rails = Path()
                for (y in listOf(fenceTop + cw * 0.08, fenceTop + cw * 0.28)) rails.rectD(left, y, right - left, cw * 0.08)
                val posts = Path()
                var x = left + 3 * u
                while (x < right) { posts.rectD(x, fenceTop, cw * 0.1, top - fenceTop); x += cw * 1.1 }
                drawPath(rails, rgb(0.6, 0.42, 0.25))
                drawPath(posts, rgb(0.48, 0.32, 0.18))
                stroke(rails, rgb(0.3, 0.18, 0.08), 0.8 * u)
                stroke(posts, rgb(0.3, 0.18, 0.08), 0.8 * u)
            }
            LDScene.GLACIER -> {
                val wy = top - cw * 0.5; val wh = cw * 0.5
                rect(left, wy, right - left, wh, vgrad(listOf(rgb(0.8, 0.93, 1.0), rgb(0.6, 0.8, 0.95)), wy, wy + wh))
                val j = Path()
                var x = left
                while (x < right) { j.m(x, wy); j.l(x, wy + wh); x += cw * 0.8 }
                j.m(left, wy + wh / 2); j.l(right, wy + wh / 2)
                stroke(j, Color.White.op(0.8), u)
                icicles(right - left, wy + wh, 7 * u, rgb(0.85, 0.95, 1.0))
            }
            LDScene.FUTURE -> {
                val y = top - cw * 0.4
                line(left, y, right, y, rgb(0.2, 0.95, 0.95, 0.85), 2 * u, StrokeCap.Butt)
                line(left, y + cw * 0.18, right, y + cw * 0.18, rgb(1.0, 0.3, 0.85, 0.6), 1.5 * u, StrokeCap.Butt)
                val posts = Path()
                var x = left + 2 * u
                while (x < right) { posts.rrectD(x, y - cw * 0.08, cw * 0.1, top - y + cw * 0.08, 2 * u); x += cw * 1.2 }
                drawPath(posts, rgb(0.5, 0.55, 0.65))
            }
        }
    }

    private fun DrawScope.street(scene: LDScene, x: Double, right: Double, top: Double, bottom: Double, cw: Double) {
        val u = density.toDouble()
        val w = max(0.0, right - x)
        val hh = bottom - top
        when (scene) {
            LDScene.ROOFTOP -> { rect(x, top, w, hh, rgb(0.16, 0.14, 0.26)); rect(x, top, cw * 0.12, hh, rgb(0.45, 0.4, 0.6)) }
            LDScene.BACKYARD -> { rect(x, top, cw * 0.3, hh, gray(0.8)); rect(x + cw * 0.3, top, max(0.0, w - cw * 0.3), hh, gray(0.35)) }
            LDScene.DESERT -> { rect(x, top, w, hh, rgb(0.8, 0.64, 0.4)); rect(x, top, cw * 0.1, hh, rgb(0.66, 0.5, 0.28)) }
            LDScene.PIRATE -> {
                rect(x, top, w, hh, hgrad(listOf(rgb(0.12, 0.45, 0.68), rgb(0.06, 0.3, 0.5)), x, x + w))
                val foam = Path()
                var y = top + 10 * u
                while (y < bottom) { foam.m(x + 4 * u, y); foam.q(x + w / 2, y - 4 * u, x + w - 2 * u, y); y += 22 * u }
                stroke(foam, Color.White.op(0.45), 1.2 * u)
                rect(x, top, cw * 0.12, hh, rgb(0.3, 0.17, 0.08))
            }
            LDScene.FRONTIER -> {
                rect(x, top, w, hh, rgb(0.62, 0.48, 0.32))
                val ties = Path()
                var y = top + 4 * u
                while (y < bottom) { ties.rectD(x + u, y, w - 2 * u, 5 * u); y += 14 * u }
                drawPath(ties, rgb(0.4, 0.26, 0.14))
                for (rx in listOf(x + w * 0.28, x + w * 0.72)) rect(rx - 1.5 * u, top, 3 * u, hh, gray(0.55))
            }
            LDScene.GLACIER -> { rect(x, top, w, hh, rgb(0.7, 0.84, 0.95)); rect(x, top, cw * 0.1, hh, Color.White) }
            LDScene.FUTURE -> {
                rect(x, top, w, hh, rgb(0.1, 0.08, 0.2))
                val dashes = Path()
                var y = top + 6 * u
                while (y < bottom) { dashes.rectD(x + w / 2 - 1.5 * u, y, 3 * u, 9 * u); y += 18 * u }
                drawPath(dashes, rgb(1.0, 0.3, 0.85, 0.8))
                rect(x, top, 2 * u, hh, rgb(0.2, 0.95, 0.95))
            }
        }
    }

    private fun DrawScope.patio(scene: LDScene, px: Double, py: Double, pw: Double, ph: Double, ch: Double) {
        val (fill, ln) = when (scene) {
            LDScene.BACKYARD -> rgb(0.78, 0.72, 0.6) to rgb(0.6, 0.54, 0.44)
            LDScene.DESERT -> rgb(0.82, 0.66, 0.42) to rgb(0.6, 0.45, 0.25)
            LDScene.PIRATE -> rgb(0.45, 0.27, 0.13) to rgb(0.25, 0.13, 0.05)
            LDScene.FRONTIER -> rgb(0.62, 0.45, 0.28) to rgb(0.4, 0.27, 0.14)
            LDScene.GLACIER -> rgb(0.78, 0.9, 1.0) to rgb(0.55, 0.72, 0.9)
            LDScene.FUTURE -> rgb(0.36, 0.4, 0.52) to rgb(0.2, 0.95, 0.95)
            LDScene.ROOFTOP -> rgb(0.3, 0.26, 0.4) to rgb(0.18, 0.15, 0.26)
        }
        rect(px, py, pw, ph, fill)
        val flags = Path()
        var y = py
        var k = 0
        while (y < py + ph) { flags.rectD(px + (if (k % 2 == 0) 0.0 else pw * 0.4), y, pw * 0.6, ch * 0.33); y += ch * 0.33; k++ }
        clipRect(px.f, py.f, (px + pw).f, (py + ph).f) { stroke(flags, ln.op(if (scene == LDScene.FUTURE) 0.5 else 1.0), density.toDouble()) }
    }

    private fun DrawScope.yardDressing(scene: LDScene, yTop: Double, yH: Double, yW: Double, left: Double, right: Double, cw: Double) {
        if (yH <= cw * 0.6) return
        val u = density.toDouble()
        when (scene) {
            LDScene.BACKYARD -> {
                val bushes = Path()
                var bx = left - cw * 0.3
                while (bx < right) { bushes.ovalD(bx, yTop + cw * 0.15, cw * 0.9, cw * 0.55); bx += cw * 0.62 }
                drawPath(bushes, rgb(0.18, 0.45, 0.12))
                val blooms = Path()
                for (i in 0 until 14) blooms.ovalD(left + (right - left) * hash(i * 4.3), yTop + cw * (0.2 + 0.4 * hash(i * 9.1)), 5 * u, 5 * u)
                drawPath(blooms, rgb(1.0, 0.85, 0.3))
            }
            LDScene.DESERT -> {
                for ((i, px) in listOf(left + cw * 1.2, left + cw * 2.6).withIndex()) {
                    val h = cw * (if (i == 0) 0.9 else 0.6)
                    val by = yTop + cw * 1.05
                    drawPath(polyPath(px - h, by, px, by - h, px + h, by), rgb(0.8, 0.6, 0.34))
                    drawPath(polyPath(px, by - h, px + h, by, px + h * 0.3, by), rgb(0.62, 0.44, 0.24))
                }
                palm(right - cw * 1.4, yTop + cw * 1.2, cw * 1.0)
            }
            LDScene.PIRATE -> {
                waves(yTop + cw * 0.35, right + cw, Color.White.op(0.5))
                waves(yTop + cw * 0.85, right + cw, Color.White.op(0.35))
                rect(0.0, yTop, right, cw * 0.16, rgb(0.32, 0.18, 0.08))
                rect(0.0, yTop + cw * 0.16, right, cw * 0.05, rgb(0.8, 0.62, 0.25))
            }
            LDScene.FRONTIER -> {
                cactus(left + cw * 1.3, yTop + cw * 1.1, cw * 0.9)
                cactus(right - cw * 1.6, yTop + cw * 0.95, cw * 0.65)
                val rocks = Path()
                for (i in 0 until 5) rocks.ovalD(left + (right - left) * hash(i * 6.1), yTop + cw * (0.4 + 0.5 * hash(i * 2.2)), 10 * u, 6 * u)
                drawPath(rocks, rgb(0.45, 0.3, 0.2))
            }
            LDScene.GLACIER -> {
                val drifts = Path()
                var x = left - cw * 0.4
                while (x < right) { drifts.ovalD(x, yTop + cw * 0.1, cw * 1.1, cw * 0.5); x += cw * 0.8 }
                drawPath(drifts, Color.White.op(0.8))
            }
            LDScene.FUTURE -> {
                val g = Path()
                var x = left
                while (x < right) { g.m(x, yTop); g.l(x - cw * 0.4, yTop + yH); x += cw * 0.8 }
                var y = yTop + cw * 0.3
                while (y < yTop + yH) { g.m(0.0, y); g.l(yW, y); y += cw * 0.45 }
                stroke(g, rgb(1.0, 0.3, 0.85, 0.35), u)
            }
            LDScene.ROOFTOP -> {
                val eaves = Path()
                var x = left - cw * 0.5
                var i = 0.0
                while (x < right) {
                    val w = cw * (1.2 + hash(i) * 0.8)
                    eaves.m(x, yTop + cw * 1.1); eaves.l(x + w / 2, yTop + cw * 0.5); eaves.l(x + w, yTop + cw * 1.1); eaves.close()
                    x += w * 0.8; i += 1
                }
                drawPath(eaves, rgb(0.14, 0.11, 0.24))
            }
        }
    }

    private fun DrawScope.palm(bx: Double, by: Double, h: Double) {
        val trunk = Path(); trunk.m(bx, by); trunk.q(bx - h * 0.1, by - h * 0.5, bx + h * 0.15, by - h)
        stroke(trunk, rgb(0.5, 0.34, 0.18), h * 0.09, StrokeCap.Round)
        val tx = bx + h * 0.15; val ty = by - h
        val fronds = Path()
        for (a in listOf(-2.6, -2.0, -1.2, -0.6, 0.1)) {
            val px = tx + cos(a) * h * 0.5; val py = ty + sin(a) * h * 0.3 + h * 0.12
            fronds.m(tx, ty); fronds.q((tx + px) / 2, ty - h * 0.15, px, py)
        }
        stroke(fronds, rgb(0.2, 0.5, 0.18), h * 0.08, StrokeCap.Round)
    }

    private fun DrawScope.cactus(bx: Double, by: Double, h: Double) {
        val c = Path()
        c.rrectD(bx - h * 0.1, by - h, h * 0.2, h, h * 0.1)
        c.rrectD(bx - h * 0.34, by - h * 0.65, h * 0.12, h * 0.36, h * 0.06)
        c.rectD(bx - h * 0.3, by - h * 0.35, h * 0.25, h * 0.09)
        c.rrectD(bx + h * 0.22, by - h * 0.8, h * 0.12, h * 0.4, h * 0.06)
        c.rectD(bx + h * 0.05, by - h * 0.47, h * 0.25, h * 0.09)
        drawPath(c, rgb(0.3, 0.55, 0.25))
    }
}

/** Maps lawn coordinates (x in tiles from the house, y in rows) to pixels, and back (iOS `LDLayout`). */
class LDLayout(val width: Double, val height: Double, val rows: List<Int>) {
    val cellW: Double
    val cellH: Double
    val ox: Double
    val oy: Double

    init {
        val byWidth = width / 8.4
        val byHeight = height / (rows.size * 1.36 + 0.7)
        cellW = minOf(byWidth, byHeight)
        cellH = minOf(cellW * 1.62, maxOf(cellW * 1.36, (height - cellW * 0.7) / rows.size))
        val lawnW = cellW * 8.4; val lawnH = cellH * rows.size
        val spare = maxOf(0.0, height - lawnH - cellW * 0.6)
        ox = (width - lawnW) / 2 + cellW * 0.62
        oy = cellW * 0.6 + spare * 0.3
    }

    fun point(x: Double, y: Double) = P(ox + x * cellW, oy + (y - (rows.firstOrNull() ?: 0)) * cellH)
    fun tile(px: Double, py: Double) = P((px - ox) / cellW, (py - oy) / cellH + (rows.firstOrNull() ?: 0))
}
