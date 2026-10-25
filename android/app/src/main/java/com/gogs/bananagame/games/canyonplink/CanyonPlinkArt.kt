package com.gogs.bananagame.games.canyonplink

import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import com.gogs.bananagame.core.*
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** The hour's colours: midday → golden hour → sunset → dusk → moonlit canyon, one step per level. */
internal class RSPalette(
    val sand0: Color, val sand1: Color, val speck: Color,
    val rock: Color, val rockDark: Color, val rockLit: Color,
    val back0: Color, val back1: Color,
    val sight: Color, val tracer: Color,
    val shadow: Double,
    val sky0: Color, val sky1: Color, val mesa: Color,
)

/**
 * Canyon Plink's art (iOS RSArt, RSArena, RSBackdrop, RSBelt, RSFireFace): a red-rock canyon plinking
 * range. Drawn in points (see [inPoints]); strokes use SwiftUI's defaults (butt caps, miter joins).
 */
internal object RSArt {
    val cream = rgb(1.0, 0.93, 0.78)

    fun hash(n: Double): Double { val x = sin(n) * 43758.5453; return x - floor(x) }

    fun palette(level: Int): RSPalette {
        val c = { r: Double, g: Double, b: Double -> rgb(r, g, b) }
        val ink = c(0.34, 0.18, 0.09).op(0.72)
        val chalk = Color.White.op(0.78)
        return when (min(max(level, 1), 7)) {
            1 -> RSPalette(c(0.95, 0.83, 0.62), c(0.90, 0.75, 0.52), c(0.72, 0.55, 0.36), c(0.80, 0.42, 0.25), c(0.56, 0.26, 0.14), c(0.96, 0.66, 0.46),
                c(0.62, 0.30, 0.18), c(0.38, 0.17, 0.10), ink, c(1.0, 0.94, 0.72), 0.2, c(0.42, 0.70, 0.95), c(0.80, 0.90, 0.96), c(0.78, 0.50, 0.38))
            2 -> RSPalette(c(0.95, 0.80, 0.57), c(0.89, 0.71, 0.47), c(0.70, 0.52, 0.32), c(0.82, 0.44, 0.24), c(0.58, 0.27, 0.13), c(0.98, 0.67, 0.42),
                c(0.66, 0.32, 0.18), c(0.40, 0.18, 0.10), ink, c(1.0, 0.94, 0.72), 0.22, c(0.40, 0.64, 0.92), c(0.88, 0.86, 0.78), c(0.78, 0.47, 0.33))
            3 -> RSPalette(c(0.97, 0.76, 0.50), c(0.90, 0.64, 0.40), c(0.70, 0.46, 0.28), c(0.84, 0.40, 0.22), c(0.58, 0.23, 0.11), c(1.0, 0.66, 0.40),
                c(0.70, 0.30, 0.16), c(0.42, 0.15, 0.09), ink, c(1.0, 0.92, 0.66), 0.25, c(0.48, 0.58, 0.86), c(1.0, 0.80, 0.55), c(0.74, 0.40, 0.27))
            4 -> RSPalette(c(0.93, 0.66, 0.52), c(0.84, 0.54, 0.44), c(0.62, 0.36, 0.30), c(0.74, 0.31, 0.26), c(0.50, 0.19, 0.18), c(0.96, 0.56, 0.46),
                c(0.54, 0.21, 0.22), c(0.28, 0.11, 0.17), ink, c(1.0, 0.9, 0.7), 0.26, c(0.40, 0.34, 0.62), c(0.98, 0.58, 0.42), c(0.50, 0.24, 0.27))
            5 -> RSPalette(c(0.66, 0.52, 0.56), c(0.55, 0.42, 0.50), c(0.42, 0.30, 0.38), c(0.52, 0.28, 0.32), c(0.34, 0.17, 0.23), c(0.72, 0.46, 0.48),
                c(0.30, 0.15, 0.25), c(0.15, 0.07, 0.15), chalk, c(1.0, 0.9, 0.74), 0.28, c(0.20, 0.17, 0.40), c(0.62, 0.36, 0.48), c(0.30, 0.16, 0.25))
            6 -> RSPalette(c(0.40, 0.42, 0.56), c(0.32, 0.34, 0.48), c(0.24, 0.26, 0.38), c(0.32, 0.27, 0.40), c(0.19, 0.16, 0.27), c(0.52, 0.48, 0.64),
                c(0.13, 0.12, 0.24), c(0.06, 0.06, 0.13), chalk, c(0.9, 0.95, 1.0), 0.3, c(0.05, 0.07, 0.20), c(0.16, 0.18, 0.36), c(0.12, 0.11, 0.21))
            else -> RSPalette(c(0.31, 0.33, 0.47), c(0.23, 0.25, 0.38), c(0.17, 0.19, 0.30), c(0.24, 0.20, 0.31), c(0.13, 0.11, 0.20), c(0.42, 0.40, 0.56),
                c(0.08, 0.08, 0.16), c(0.03, 0.03, 0.08), chalk, c(0.9, 0.95, 1.0), 0.32, c(0.02, 0.03, 0.10), c(0.08, 0.09, 0.22), c(0.07, 0.06, 0.14))
        }
    }

    /** Label colours for the cans (red, blue, green, yellow). */
    fun label(i: Int): Color = listOf(rgb(0.86, 0.18, 0.15), rgb(0.18, 0.40, 0.84), rgb(0.22, 0.62, 0.30), rgb(0.96, 0.76, 0.16))[abs(i) % 4]

    private fun Path.oval(x: Double, y: Double, w: Double, h: Double) = addOval(Rect(x.f, y.f, (x + w).f, (y + h).f))
    private fun Path.box(x: Double, y: Double, w: Double, h: Double) = addRect(Rect(x.f, y.f, (x + w).f, (y + h).f))
    private fun rbox(x: Double, y: Double, w: Double, h: Double, r: Double) =
        Path().apply { addRoundRect(RoundRect(x.f, y.f, (x + w).f, (y + h).f, CornerRadius(r.f, r.f))) }
    private fun DrawScope.fill(p: Path, c: Color) = drawPath(p, c)
    private fun DrawScope.fill(p: Path, b: Brush) = drawPath(p, b)
    private fun DrawScope.stroke(p: Path, c: Color, lw: Double, cap: StrokeCap = StrokeCap.Butt) =
        drawPath(p, c, style = Stroke(lw.f, miter = 10f, cap = cap))

    /** The floor, its shadows, and the sandstone walls (strata, sunlit tops, cracks). Drawn once per board. */
    fun DrawScope.arena(walls: Array<BooleanArray>, g: RSGrid, level: Int) {
        val pal = palette(level)
        val rows = RS_ROWS; val cols = RS_COLS
        fun wall(r: Int, c: Int) = r < 0 || r >= rows || c < 0 || c >= cols || walls[r][c]
        val cell = g.cell; val ox = g.ox; val oy = g.oy
        val fx = ox; val fy = oy; val fw = cell * cols; val fh = cell * rows

        // Sand, wind ripples, specks and pebbles.
        rect(fx, fy, fw, fh, lin(listOf(pal.sand1, pal.sand0, pal.sand1), fx, fy, fx + fw, fy + fh))
        val ripples = Path()
        for (k in 0 until 10) {
            val y0 = fy + fh * (k + 0.5) / 10
            var x = fx
            ripples.m(x, y0)
            var i = 0
            while (x < fx + fw) {
                val nx = x + cell * 1.7
                val bend = cell * 0.16 * (if ((i + k) % 2 == 0) 1 else -1)
                ripples.q(x + cell * 0.85, y0 - bend, nx, y0)
                x = nx; i++
            }
        }
        stroke(ripples, pal.speck.op(0.18), max(1.0, cell * 0.045))
        val specks = Path(); val pebbles = Path()
        for (i in 0 until 240) {
            val x = fx + hash(i * 12.9898) * fw
            val y = fy + hash(i * 78.233) * fh
            if (i % 12 == 0) {
                val d = cell * (0.1 + 0.08 * hash(i * 3.3))
                pebbles.oval(x, y, d, d * 0.72)
            } else {
                val d = cell * (0.035 + 0.04 * hash(i * 3.7))
                specks.oval(x, y, d, d * 0.8)
            }
        }
        fill(specks, pal.speck.op(0.5))
        fill(pebbles, pal.rockDark.op(0.55))

        // Shadows the rocks cast on the sand (light from the upper left).
        val shade = Path()
        for (r in 0 until rows) for (c in 0 until cols) {
            if (walls[r][c]) continue
            val x0 = ox + c * cell; val y0 = oy + r * cell
            if (wall(r - 1, c)) shade.box(x0, y0, cell, cell * 0.26)
            if (wall(r, c - 1)) shade.box(x0, y0, cell * 0.2, cell)
        }
        fill(shade, Color.Black.op(pal.shadow))

        // Sandstone mesas: a speckled top face, plus a cliff face with strata drawn INSIDE the wall cell
        // wherever the cell below is open, so the foot of the cliff is exactly the collision edge.
        val faceK = 0.3
        val tops = Path(); val faces = Path(); val rimLit = Path(); val rimDark = Path(); val strata = Path()
        val rockSpecks = Path(); val rockSpecksLit = Path(); val cracks = Path(); val edges = Path()
        for (r in 0 until rows) for (c in 0 until cols) {
            if (!walls[r][c]) continue
            val x0 = ox + c * cell; val y0 = oy + r * cell
            val hasFace = !wall(r + 1, c)
            val topH = if (hasFace) cell * (1 - faceK) else cell
            tops.box(x0, y0, cell + 0.5, topH + 0.5)
            if (hasFace) {
                val fy0 = y0 + topH
                faces.box(x0, fy0, cell + 0.5, cell * faceK)
                rimLit.box(x0, fy0 - cell * 0.035, cell + 0.5, cell * 0.05)
                for (k in 1..2) {
                    val sy = fy0 + cell * faceK * k / 3 + cell * 0.02 * (hash((c * 7 + k).toDouble()) - 0.5)
                    strata.m(x0, sy); strata.l(x0 + cell + 0.5, sy)
                }
                edges.m(x0, y0 + cell); edges.l(x0 + cell, y0 + cell)
            }
            if (!wall(r - 1, c)) {
                rimLit.box(x0, y0, cell + 0.5, cell * 0.06)
                edges.m(x0, y0); edges.l(x0 + cell, y0)
            }
            if (!wall(r, c - 1)) {
                rimLit.box(x0, y0, cell * 0.06, topH)
                edges.m(x0, y0); edges.l(x0, y0 + cell)
            }
            if (!wall(r, c + 1)) {
                rimDark.box(x0 + cell * 0.92, y0, cell * 0.08, cell)
                edges.m(x0 + cell, y0); edges.l(x0 + cell, y0 + cell)
            }
            for (i in 0 until 7) {
                val hx = hash((r * 131 + c * 17 + i) * 1.37)
                val hy = hash((r * 71 + c * 29 + i) * 2.11)
                val d = cell * (0.05 + 0.07 * hash((i + r * 3 + c) * 4.4))
                val rx = x0 + hx * (cell - d); val ry = y0 + hy * max(1.0, topH - d)
                if (i % 3 == 0) rockSpecksLit.oval(rx, ry, d, d * 0.8) else rockSpecks.oval(rx, ry, d, d * 0.8)
            }
            if (hash((r * 37 + c * 11) + 0.5) < 0.35) {
                val sx = x0 + cell * (0.2 + 0.45 * hash((r * 5 + c) + 2.1)); val sy = y0 + topH * 0.22
                cracks.m(sx, sy)
                cracks.q(sx + cell * 0.22, sy + topH * 0.08, sx + cell * 0.2, sy + topH * 0.45)
            }
        }
        fill(tops, pal.rock)
        fill(rockSpecks, pal.rockDark.op(0.32))
        fill(rockSpecksLit, pal.rockLit.op(0.42))
        stroke(cracks, pal.rockDark.op(0.7), max(0.8, cell * 0.035), StrokeCap.Round)
        fill(faces, pal.rockDark)
        stroke(strata, pal.rockDark.shade(0.35), max(1.0, cell * 0.04))
        fill(rimLit, pal.rockLit.op(0.85))
        fill(rimDark, pal.rockDark.op(0.5))
        stroke(edges, pal.rockDark.shade(0.35), max(1.0, cell * 0.04))
    }

    /** The live layer: the sight line, cans, knocked cans, the bullet and its tracer, sparks, the six-shooter. */
    fun DrawScope.action(world: PlinkWorld, g: RSGrid, level: Int, now: Double) {
        val pal = palette(level)
        val cell = g.cell
        // The same polyline as `simulate`, dotted like a chalked sight line.
        if (world.phase == PlinkWorld.Phase.AIM) {
            val pts = world.simulate()
            if (pts.isNotEmpty()) {
                val line = Path()
                line.m(g.x(pts[0].x), g.y(pts[0].y))
                for (q in pts.drop(1)) line.l(g.x(q.x), g.y(q.y))
                drawPath(line, pal.sight, style = Stroke(max(2.5, cell * 0.11).f, cap = StrokeCap.Round,
                    pathEffect = PathEffect.dashPathEffect(floatArrayOf(0.1f, (cell * 0.36).f), 0f)))
            }
        }
        for (t in world.targets) can(g.x(t.c + 0.5), g.y(t.r + 0.5), cell, label(t.r * 7 + t.c * 3))
        world.knocked.removeAll { now - it.at > 0.8 }
        for (k in world.knocked) {
            val age = now - k.at
            if (age < 0 || age >= 0.8) continue
            val side = if (k.seed % 2 == 0) 1.0 else -1.0
            withAlpha(max(0.0, 1 - age / 0.8)) {
                translate((g.x(k.x) + side * age * cell * 2.2).f, (g.y(k.y) - age * cell * 3.2 + age * age * cell * 6).f) {
                    rotateRad((side * age * 9).f, Offset.Zero) {
                        can(0.0, 0.0, cell, label((k.seed / 11) * 7 + (k.seed % 11) * 3))
                    }
                }
            }
        }
        if (world.phase == PlinkWorld.Phase.FIRING) {
            val trail = world.trail
            for (i in 1 until trail.size) {
                val f = i.toDouble() / trail.size
                line(g.x(trail[i - 1].x), g.y(trail[i - 1].y), g.x(trail[i].x), g.y(trail[i].y), pal.tracer.op(0.75 * f), cell * 0.13 * f)
            }
            val bx = g.x(world.bx); val by = g.y(world.by)
            circle(bx, by, cell * 0.42, radial(listOf(pal.tracer.op(0.7), pal.tracer.op(0.0)), bx, by, cell * 0.42))
            circle(bx, by, cell * 0.1, rgb(1.0, 0.96, 0.82))
        }
        world.sparks.removeAll { now - it.at > 0.8 }
        for (s in world.sparks) {
            val age = now - s.at
            if (age < 0 || age >= 0.35) continue
            spark(g.x(s.x), g.y(s.y), cell, age, s.seed)
        }
        revolver(g.x(world.sx), g.y(world.sy), cell, world.aimAngle, world.ammo)
    }

    /** A tin can standing on the sand, seen from the front and a little above; fits inside the 0.48-cell hit radius. */
    fun DrawScope.can(cx: Double, cy: Double, cell: Double, label: Color) {
        val W = cell * 0.52; val H = cell * 0.48; val E = cell * 0.18
        val base = cy + cell * 0.24; val top = base - H
        val l = cx - W / 2; val r = cx + W / 2
        fill(Path().apply { oval(l, base - E * 0.3, W * 1.3, E * 0.95) }, Color.Black.op(0.22))
        val body = Path().apply {
            m(l, top); l(l, base)
            q(cx, base + E, r, base)
            l(r, top)
            close()
        }
        fill(body, Brush.horizontalGradient(
            0f to gray(0.48), 0.3f to gray(0.88), 0.42f to gray(0.98), 0.8f to gray(0.66), 1f to gray(0.44),
            startX = l.f, endX = r.f))
        val lt = top + H * 0.2; val lb = base - H * 0.14
        val band = Path().apply {
            m(l, lt)
            q(cx, lt + E, r, lt)
            l(r, lb)
            q(cx, lb + E, l, lb)
            close()
        }
        fill(band, hgrad(listOf(label.shade(0.4), label, label.lit(0.3), label.shade(0.45)), l, r))
        fill(Path().apply { oval(cx - W * 0.15, (lt + lb) / 2 - H * 0.05, W * 0.3, H * 0.2) }, Color.White.op(0.85))
        val lid = Path().apply { oval(l, top - E / 2, W, E) }
        fill(lid, gray(0.9))
        fill(Path().apply { oval(l + W * 0.09, top - E / 2 + E * 0.17, W * 0.82, E * 0.66) }, gray(0.68))
        fill(Path().apply { oval(cx - W * 0.12, top - E * 0.22, W * 0.24, E * 0.36) }, gray(0.86))
        val outline = Path().apply { addPath(body); oval(l, top - E / 2, W, E) }
        stroke(outline, Color.Black.op(0.5), max(0.7, cell * 0.028))
    }

    /** A ricochet: a flash and a star of sparks flying off the rock. */
    fun DrawScope.spark(px: Double, py: Double, cell: Double, age: Double, seed: Int) {
        val t = age / 0.35
        val fade = max(0.0, 1 - t)
        val fr = cell * 0.32 * (1 + t)
        circle(px, py, fr, radial(listOf(rgb(1.0, 0.95, 0.7).op(0.9 * fade), rgb(1.0, 0.8, 0.4).op(0.0)), px, py, fr))
        val rays = Path()
        for (k in 0 until 7) {
            val a = k * 0.9 + seed * 0.7
            val r0 = cell * (0.08 + 0.5 * t); val r1 = cell * (0.22 + 0.8 * t)
            rays.m(px + cos(a) * r0, py + sin(a) * r0)
            rays.l(px + cos(a) * r1, py + sin(a) * r1)
        }
        stroke(rays, rgb(1.0, 0.86, 0.42).op(fade), max(1.0, cell * 0.05), StrokeCap.Round)
    }

    /** The six-shooter seen from above, barrel along the aim, with a banana grip; the cylinder shows the rounds left. */
    fun DrawScope.revolver(px: Double, py: Double, cell: Double, angle: Double, loaded: Int) {
        val k = (cell * 1.15).f
        translate((px + cell * 0.07).f, (py + cell * 0.11).f) {
            rotateRad(angle.f, Offset.Zero) { scale(k, k, Offset.Zero) { gunParts(true, loaded) } }
        }
        translate(px.f, py.f) {
            rotateRad(angle.f, Offset.Zero) { scale(k, k, Offset.Zero) { gunParts(false, loaded) } }
        }
    }

    private fun DrawScope.gunParts(shadow: Boolean, loaded: Int) {
        val steel = rgb(0.40, 0.42, 0.47)
        val dark = rgb(0.15, 0.16, 0.19)
        val ink = Color.Black.op(0.7)
        val grip = Path().apply {
            m(-0.26, -0.13)
            q(-0.6, -0.26, -0.9, -0.04)
            q(-0.97, 0.04, -0.88, 0.1)
            q(-0.56, 0.2, -0.26, 0.13)
            close()
        }
        val frame = rbox(-0.38, -0.15, 0.64, 0.3, 0.08)
        val barrel = rbox(0.16, -0.085, 0.88, 0.17, 0.05)
        val drum = Path().apply { oval(-0.27, -0.25, 0.5, 0.5) }
        if (shadow) {
            for (part in listOf(grip, frame, barrel, drum)) fill(part, Color.Black.op(0.28))
            return
        }
        fill(grip, vgrad(listOf(rgb(1.0, 0.9, 0.4), rgb(0.93, 0.72, 0.16)), -0.2, 0.2))
        fill(Path().apply { oval(-0.95, -0.05, 0.12, 0.14) }, rgb(0.42, 0.28, 0.1))
        stroke(grip, ink, 0.035)
        fill(frame, dark)
        fill(barrel, vgrad(listOf(steel.lit(0.35), steel, steel.shade(0.35)), -0.085, 0.085))
        rect(1.0, -0.095, 0.07, 0.19, dark)
        rect(0.9, -0.03, 0.08, 0.06, dark.op(0.8))
        stroke(barrel, ink, 0.03)
        fill(rbox(-0.46, -0.045, 0.12, 0.09, 0.03), dark)
        fill(drum, radial(listOf(steel.lit(0.4), steel, steel.shade(0.4)), -0.1, -0.1, 0.32))
        stroke(drum, ink, 0.03)
        for (i in 0 until 6) {
            val a = i / 6.0 * 2 * Math.PI - Math.PI / 2
            val qx = -0.02 + cos(a) * 0.155; val qy = sin(a) * 0.155
            if (i < loaded) {
                circle(qx, qy, 0.058, rgb(0.93, 0.75, 0.33))
                circle(qx, qy, 0.022, rgb(0.62, 0.44, 0.18))
            } else {
                circle(qx, qy, 0.058, gray(0.08))
            }
        }
        circle(-0.02, 0.0, 0.04, steel.lit(0.5))
    }

    /** Cartridges in a belt: brass ones are left, dark sockets are spent. The last round glows red. */
    fun DrawScope.belt(w: Double, h: Double, total: Int, loaded: Int) {
        val n = max(1, total)
        val slot = w / n
        val bw = min(slot * 0.62, h * 0.34)
        for (i in 0 until n) {
            val x = slot * (i + 0.5)
            val cx = x - bw / 2; val cy = h * 0.38; val ch = h * 0.6
            val tip = Path().apply { m(x - bw / 2, h * 0.4); q(x, -h * 0.08, x + bw / 2, h * 0.4); close() }
            val case = rbox(cx, cy, bw, ch, bw * 0.2)
            if (i < loaded) {
                fill(tip, rgb(0.78, 0.45, 0.24))
                fill(case, hgrad(listOf(rgb(1.0, 0.86, 0.46), rgb(0.82, 0.6, 0.2)), cx, cx + bw))
                if (loaded <= 1) stroke(Path().apply { addPath(case); addPath(tip) }, rgb(1.0, 0.3, 0.2), 1.5)
            } else {
                val all = Path().apply { addPath(case); addPath(tip) }
                fill(all, Color.Black.op(0.3))
                stroke(all, Color.White.op(0.25), 1.0)
            }
        }
    }

    /** The FIRE button's face: red (grey while a shot flies) in a brass rim with an inner ring that lights when pressed. */
    fun DrawScope.fireFace(w: Double, h: Double, ready: Boolean, lit: Boolean) {
        rrect(0.0, 0.0, w, h, 16.0, vgrad(if (ready) listOf(rgb(0.88, 0.3, 0.2), rgb(0.6, 0.15, 0.1)) else listOf(gray(0.42), gray(0.28)), 0.0, h))
        rrectStroke(1.5, 1.5, w - 3, h - 3, 14.5, rgb(0.96, 0.8, 0.42), 3.0)
        rrectStroke(5.75, 5.75, w - 11.5, h - 11.5, 10.25, Color.White.op(if (lit) 0.9 else 0.18), 1.5)
    }

    /** Behind the arena: the sky of the hour over distant buttes, then the desert floor. */
    fun DrawScope.backdrop(w: Double, h: Double, level: Int, horizon: Double) {
        val pal = palette(level)
        rect(0.0, 0.0, w, horizon + 1, vgrad(listOf(pal.sky0, pal.sky1), 0.0, horizon))
        if (level >= 6) {
            val stars = Path()
            for (i in 0 until 34) {
                val x = hash(i * 9.1) * w
                val y = hash(i * 3.3) * horizon * 0.8
                val d = 1 + hash(i * 1.9) * 1.4
                stars.oval(x, y, d, d)
            }
            fill(stars, Color.White.op(0.75))
        }
        circle(w * 0.5, horizon * 0.22 + 8, 8.0, if (level >= 6) rgb(0.94, 0.95, 1.0) else rgb(1.0, 0.96, 0.8, 0.9))
        val buttes = Path()
        buttes.m(0.0, horizon + 1)
        var x = -10.0
        var i = 0
        while (x < w) {
            val gap = 14 + 36 * hash(i * 5.3)
            val bw = 34 + 54 * hash(i * 1.7)
            val bh = horizon * (0.22 + 0.3 * hash(i * 2.9))
            buttes.l(x + gap, horizon + 1)
            buttes.l(x + gap + 7, horizon - bh)
            buttes.l(x + gap + bw - 7, horizon - bh)
            buttes.l(x + gap + bw, horizon + 1)
            x += gap + bw
            i++
        }
        buttes.l(w, horizon + 1)
        buttes.close()
        fill(buttes, pal.mesa)
        rect(0.0, horizon, w, h - horizon, vgrad(listOf(pal.back0, pal.back1), horizon, h))
        val pebbles = Path()
        for (k in 0 until 60) {
            val px = hash(k * 4.7) * w
            val py = horizon + hash(k * 8.3) * (h - horizon)
            val d = 2 + 4 * hash(k * 2.2)
            pebbles.oval(px, py, d, d * 0.7)
        }
        fill(pebbles, Color.Black.op(0.18))
    }
}
