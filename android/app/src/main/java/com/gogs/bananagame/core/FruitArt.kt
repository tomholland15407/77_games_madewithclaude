package com.gogs.bananagame.core

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/** The Suika evolution order (index = merge tier) plus tile-only kinds (iOS FruitKind). */
enum class FruitKind { CHERRY, STRAWBERRY, GRAPE, DEKOPON, PERSIMMON, APPLE, PEAR, PEACH, PINEAPPLE, MELON, WATERMELON, BANANA, LEMON }

/**
 * Shared vector fruit illustrations (iOS FruitArt.swift): glossy bodies lit from the upper-left, a
 * darker rim, stems/leaves and an optional kawaii face, all drawn in a unit circle and scaled.
 */
object FruitArt {
    fun color(k: FruitKind): Color = when (k) {
        FruitKind.CHERRY -> rgb(0.86, 0.10, 0.20)
        FruitKind.STRAWBERRY -> rgb(0.95, 0.25, 0.34)
        FruitKind.GRAPE -> rgb(0.55, 0.30, 0.80)
        FruitKind.DEKOPON -> rgb(1.00, 0.63, 0.14)
        FruitKind.PERSIMMON -> rgb(0.97, 0.43, 0.11)
        FruitKind.APPLE -> rgb(0.90, 0.12, 0.16)
        FruitKind.PEAR -> rgb(0.95, 0.87, 0.45)
        FruitKind.PEACH -> rgb(1.00, 0.69, 0.73)
        FruitKind.PINEAPPLE -> rgb(0.97, 0.75, 0.20)
        FruitKind.MELON -> rgb(0.67, 0.86, 0.44)
        FruitKind.WATERMELON -> rgb(0.18, 0.62, 0.26)
        FruitKind.BANANA -> rgb(1.00, 0.85, 0.24)
        FruitKind.LEMON -> rgb(1.00, 0.90, 0.32)
    }

    /** Draws `kind` centred at (cx, cy) with body radius `radius`, rotated by `angleDeg` degrees. */
    fun draw(d: DrawScope, kind: FruitKind, cx: Double, cy: Double, radius: Double, angleDeg: Double = 0.0, face: Boolean = false) = with(d) {
        if (radius <= 0.5) return@with
        translate(cx.f, cy.f) {
            rotate(angleDeg.f, Offset.Zero) {
                scale(radius.f, radius.f, Offset.Zero) {
                    when (kind) {
                        FruitKind.CHERRY -> cherry(); FruitKind.STRAWBERRY -> strawberry(); FruitKind.GRAPE -> grape()
                        FruitKind.DEKOPON -> dekopon(); FruitKind.PERSIMMON -> persimmon(); FruitKind.APPLE -> apple()
                        FruitKind.PEAR -> pear(); FruitKind.PEACH -> peach(); FruitKind.PINEAPPLE -> pineapple()
                        FruitKind.MELON -> melon(); FruitKind.WATERMELON -> watermelon(); FruitKind.BANANA -> banana()
                        FruitKind.LEMON -> lemon()
                    }
                    if (face) when (kind) {
                        FruitKind.STRAWBERRY -> drawFace(-0.1, 0.9)
                        FruitKind.GRAPE -> drawFace(0.0, 0.72)
                        FruitKind.PINEAPPLE -> drawFace(0.18, 0.9)
                        FruitKind.PERSIMMON -> drawFace(0.14, 1.0)
                        else -> drawFace(0.1, 1.0)
                    }
                }
            }
        }
    }

    private fun discP(x: Double, y: Double, r: Double) = Path().apply { addOval(androidx.compose.ui.geometry.Rect((x - r).f, (y - r).f, (x + r).f, (y + r).f)) }
    private fun ovalP(x: Double, y: Double, rx: Double, ry: Double) = Path().apply { addOval(androidx.compose.ui.geometry.Rect((x - rx).f, (y - ry).f, (x + rx).f, (y + ry).f)) }

    private fun DrawScope.body(p: Path, base: Color, far: Color? = null, rim: Double = 0.42, rimWidth: Double = 0.075) {
        drawPath(p, radial(listOf(base.lit(0.5), base, far ?: base.shade(0.25)), -0.38, -0.42, 1.6))
        drawPath(p, base.shade(rim), style = Stroke(rimWidth.f))
    }

    private fun DrawScope.gloss(x: Double = -0.42, y: Double = -0.42, rx: Double = 0.22, ry: Double = 0.12, opacity: Double = 0.75) {
        translate(x.f, y.f) {
            rotate(-38f, Offset.Zero) {
                drawPath(ovalP(0.0, 0.0, rx, ry), Color.White.op(opacity))
                drawPath(ovalP(rx * 1.35, ry * 0.4, rx * 0.22, ry * 0.45), Color.White.op(opacity * 0.8))
            }
        }
    }

    private val leafGreen = rgb(0.30, 0.70, 0.24)
    private val stemBrown = rgb(0.43, 0.28, 0.14)

    private fun DrawScope.leaf(ax: Double, ay: Double, bx: Double, by: Double, w: Double, color: Color = leafGreen) {
        val dx = bx - ax; val dy = by - ay
        val len = max(0.0001, hypot(dx, dy))
        val nx = -dy / len * w; val ny = dx / len * w
        val mx = (ax + bx) / 2; val my = (ay + by) / 2
        val p = Path(); p.m(ax, ay); p.q(mx + nx, my + ny, bx, by); p.q(mx - nx, my - ny, ax, ay); p.close()
        drawPath(p, lin(listOf(color.lit(0.3), color.shade(0.12)), mx + nx, my + ny, mx - nx, my - ny))
        drawPath(p, color.shade(0.5), style = Stroke(0.05f))
        drawLine(color.shade(0.4).op(0.8), off(ax, ay), off(ax + dx * 0.78, ay + dy * 0.78), 0.035f)
    }

    private fun DrawScope.stem(ax: Double, ay: Double, cx: Double, cy: Double, bx: Double, by: Double, w: Double = 0.1, color: Color = stemBrown) {
        val p = Path(); p.m(ax, ay); p.q(cx, cy, bx, by)
        drawPath(p, color.shade(0.35), style = Stroke((w + 0.05).f, cap = StrokeCap.Round))
        drawPath(p, color, style = Stroke(w.f, cap = StrokeCap.Round))
    }

    private fun scatter(seed: Long, count: Int, radius: Double, cy: Double = 0.0): List<P> {
        var s = seed.toULong()
        fun next(): Double { s = s * 6364136223846793005UL + 1442695040888963407UL; return ((s shr 33) % 10_000UL).toDouble() / 10_000 }
        val out = ArrayList<P>()
        while (out.size < count) {
            val px = (next() * 2 - 1) * radius; val py = (next() * 2 - 1) * radius
            if (hypot(px, py) < radius) out.add(P(px, py + cy))
        }
        return out
    }

    private val dekoponDimples = scatter(11, 16, 0.72, 0.1)
    private val pearSpecks = scatter(7, 18, 0.74, 0.06)
    private val lemonDimples = scatter(23, 12, 0.55)

    private fun DrawScope.drawFace(y: Double, s: Double) {
        val ink = rgb(0.14, 0.08, 0.08)
        drawPath(ovalP(-0.3 * s, y, 0.075 * s, 0.1 * s), ink)
        drawPath(ovalP(0.3 * s, y, 0.075 * s, 0.1 * s), ink)
        drawPath(discP(-0.325 * s, y - 0.035 * s, 0.03 * s), Color.White)
        drawPath(discP(0.275 * s, y - 0.035 * s, 0.03 * s), Color.White)
        val m = Path(); m.m(-0.1 * s, y + 0.16 * s); m.q(0.0, y + 0.28 * s, 0.1 * s, y + 0.16 * s)
        drawPath(m, ink, style = Stroke((0.05 * s).f, cap = StrokeCap.Round))
        val blush = rgb(1.0, 0.42, 0.5, 0.5)
        drawPath(ovalP(-0.52 * s, y + 0.15 * s, 0.13 * s, 0.075 * s), blush)
        drawPath(ovalP(0.52 * s, y + 0.15 * s, 0.13 * s, 0.075 * s), blush)
    }

    private fun DrawScope.cherry() {
        val red = color(FruitKind.CHERRY)
        body(discP(0.0, 0.1, 0.88), red)
        drawPath(ovalP(0.02, -0.72, 0.13, 0.06), red.shade(0.45))
        stem(0.02, -0.72, 0.04, -1.08, 0.36, -1.22, 0.09, rgb(0.42, 0.52, 0.18))
        leaf(0.34, -1.2, 0.9, -1.02, 0.2)
        gloss(-0.38, -0.25)
    }

    private fun DrawScope.strawberry() {
        val red = color(FruitKind.STRAWBERRY)
        val p = Path(); p.m(-0.86, -0.4)
        p.c(-0.94, 0.32, -0.4, 0.9, 0.0, 0.98); p.c(0.4, 0.9, 0.94, 0.32, 0.86, -0.4); p.c(0.7, -0.98, -0.7, -0.98, -0.86, -0.4)
        body(p, red)
        val rows = listOf(-0.3 to listOf(-0.55, -0.2, 0.2, 0.55), 0.02 to listOf(-0.62, -0.28, 0.08, 0.44), 0.32 to listOf(-0.4, -0.05, 0.3), 0.6 to listOf(-0.17, 0.17))
        val seed = rgb(1.0, 0.92, 0.62)
        for ((y, xs) in rows) for (x in xs) {
            drawPath(ovalP(x, y, 0.045, 0.07), red.shade(0.45))
            drawPath(ovalP(x, y - 0.012, 0.035, 0.055), seed)
        }
        for (deg in listOf(200.0, 235.0, 270.0, 305.0, 340.0)) {
            val a = deg * PI / 180
            leaf(0.0, -0.7, cos(a) * 0.62, -0.7 + sin(a) * 0.42, 0.13)
        }
        stem(0.0, -0.78, 0.02, -0.98, 0.1, -1.1, 0.09, leafGreen.shade(0.1))
        gloss(-0.45, -0.32, 0.18, 0.1)
    }

    private fun DrawScope.grape() {
        val purple = color(FruitKind.GRAPE)
        stem(0.0, -0.7, 0.02, -1.0, 0.14, -1.14, 0.1)
        leaf(0.1, -1.02, 0.66, -1.12, 0.2)
        val spots = (0 until 6).map { i -> val a = i * PI / 3 - PI / 2; P(cos(a) * 0.56, sin(a) * 0.56) }.sortedBy { it.y }
        spots.forEachIndexed { i, p ->
            if (i == 3) berry(P.zero, purple)
            berry(p, purple)
        }
    }

    private fun DrawScope.berry(p: P, purple: Color) {
        translate(p.x.f, p.y.f) {
            body(discP(0.0, 0.0, 0.42), purple, rimWidth = 0.06)
            drawPath(ovalP(-0.14, -0.15, 0.1, 0.06), Color.White.op(0.7))
        }
    }

    private fun DrawScope.dekopon() {
        val orange = color(FruitKind.DEKOPON)
        body(discP(0.0, -0.74, 0.3), orange)
        body(discP(0.0, 0.12, 0.88), orange)
        for (p in dekoponDimples) drawPath(discP(p.x, p.y, 0.028), orange.shade(0.28).op(0.7))
        leaf(0.04, -0.98, 0.6, -1.16, 0.2)
        drawPath(discP(0.02, -1.0, 0.07), stemBrown)
        gloss(-0.4, -0.22)
    }

    private fun DrawScope.persimmon() {
        val orange = color(FruitKind.PERSIMMON)
        body(ovalP(0.0, 0.1, 0.96, 0.86), orange, rgb(0.82, 0.26, 0.08))
        for ((tx, ty) in listOf(-0.6 to -0.6, 0.6 to -0.6, -0.28 to -0.98, 0.28 to -0.98)) leaf(0.0, -0.7, tx, ty, 0.2, rgb(0.36, 0.58, 0.2))
        drawPath(discP(0.0, -0.76, 0.1), stemBrown)
        gloss(-0.45, -0.2)
    }

    private fun DrawScope.apple() {
        val red = color(FruitKind.APPLE)
        val p = Path(); p.m(0.0, -0.62)
        p.c(-0.36, -0.98, -0.96, -0.78, -0.96, -0.08); p.c(-0.96, 0.62, -0.45, 0.98, 0.0, 0.96)
        p.c(0.45, 0.98, 0.96, 0.62, 0.96, -0.08); p.c(0.96, -0.78, 0.36, -0.98, 0.0, -0.62)
        body(p, red, rgb(0.62, 0.05, 0.1))
        stem(0.0, -0.6, 0.0, -0.9, 0.12, -1.06, 0.1)
        leaf(0.1, -0.9, 0.66, -1.06, 0.22)
        gloss(-0.46, -0.34)
    }

    private fun DrawScope.pear() {
        val yellow = color(FruitKind.PEAR)
        body(discP(0.0, 0.06, 0.93), yellow, rgb(0.8, 0.72, 0.3))
        for (p in pearSpecks) drawPath(discP(p.x, p.y, 0.025), rgb(0.62, 0.5, 0.22, 0.6))
        drawPath(ovalP(0.0, -0.82, 0.14, 0.06), yellow.shade(0.4))
        stem(0.0, -0.82, 0.0, -1.02, 0.1, -1.12, 0.1)
        gloss(-0.42, -0.38)
    }

    private fun DrawScope.peach() {
        val pink = color(FruitKind.PEACH)
        body(discP(0.0, 0.06, 0.93), pink, rgb(1.0, 0.56, 0.42), rim = 0.38)
        val cr = Path(); cr.m(0.08, -0.84); cr.q(-0.36, -0.22, -0.18, 0.5)
        drawPath(cr, rgb(0.9, 0.42, 0.48, 0.75), style = Stroke(0.07f, cap = StrokeCap.Round))
        leaf(0.06, -0.86, 0.64, -1.08, 0.22)
        leaf(0.02, -0.86, -0.36, -1.12, 0.16)
        gloss(-0.46, -0.32, opacity = 0.6)
    }

    private fun DrawScope.pineapple() {
        val gold = color(FruitKind.PINEAPPLE)
        val crown = rgb(0.26, 0.62, 0.26)
        for ((tx, ty) in listOf(-0.62 to -1.02, 0.62 to -1.02, -0.3 to -1.28, 0.3 to -1.28, 0.0 to -1.4)) leaf(0.0, -0.62, tx, ty, 0.15, crown)
        val shape = ovalP(0.0, 0.16, 0.84, 0.86)
        body(shape, gold, rgb(0.85, 0.52, 0.1))
        clipPath(shape) {
            val hatch = Path()
            for (i in -6..6) {
                val o = i * 0.3
                hatch.m(o - 1.2, -1.2); hatch.l(o + 1.2, 1.2)
                hatch.m(o + 1.2, -1.2); hatch.l(o - 1.2, 1.2)
            }
            drawPath(hatch, rgb(0.72, 0.45, 0.08, 0.75), style = Stroke(0.045f))
            for (i in -4..4) for (j in -4..4) if ((i + j) % 2 == 0) drawPath(discP(i * 0.212, j * 0.212 + 0.16, 0.03), rgb(0.6, 0.36, 0.06, 0.7))
        }
        drawPath(shape, gold.shade(0.45), style = Stroke(0.075f))
        gloss(-0.42, -0.26, opacity = 0.55)
    }

    private fun DrawScope.melon() {
        val green = color(FruitKind.MELON)
        val shape = discP(0.0, 0.04, 0.95)
        body(shape, green, rgb(0.45, 0.66, 0.3))
        clipPath(shape) {
            val net = Path()
            val jit = listOf(0.06, -0.05, 0.08, -0.07, 0.04, -0.06, 0.07)
            for (i in 0 until 7) {
                val y = -0.84 + i * 0.3
                net.m(-1.1, y); net.c(-0.4, y + jit[i] * 2.2, 0.4, y - jit[(i + 2) % 7] * 2.2, 1.1, y + jit[i] * 0.5)
                val x = -0.9 + i * 0.3
                net.m(x, -1.1); net.c(x * 1.18 + jit[(i + 3) % 7] * 2, -0.35, x * 1.12 - jit[i] * 2, 0.4, x * 0.7 + jit[i], 1.1)
            }
            drawPath(net, rgb(0.93, 0.97, 0.84, 0.8), style = Stroke(0.05f))
        }
        drawPath(shape, green.shade(0.45), style = Stroke(0.075f))
        stem(0.0, -0.86, 0.0, -1.0, 0.0, -1.12, 0.11, rgb(0.5, 0.55, 0.24))
        stem(-0.16, -1.12, 0.0, -1.15, 0.16, -1.12, 0.09, rgb(0.5, 0.55, 0.24))
        gloss(-0.44, -0.36, opacity = 0.6)
    }

    private fun DrawScope.watermelon() {
        val green = color(FruitKind.WATERMELON)
        val shape = discP(0.0, 0.0, 0.97)
        body(shape, green.lit(0.1), rgb(0.08, 0.38, 0.14))
        val dark = rgb(0.07, 0.33, 0.12)
        clipPath(shape) {
            listOf(-0.86, -0.52, -0.18, 0.18, 0.52, 0.86).forEachIndexed { i, s ->
                val st = Path()
                var y = -1.0; var first = true
                while (y <= 1.0001) {
                    val zig = (if (((y + 1) * 10).toInt() % 2 == 0) 1 else -1) * 0.055 * (if (i % 2 == 0) 1 else -1)
                    val px = s * sqrt(max(0.0, 1 - y * y)) + zig
                    if (first) { st.m(px, y); first = false } else st.l(px, y)
                    y += 0.1
                }
                drawPath(st, dark, style = Stroke(0.13f, join = StrokeJoin.Round))
            }
        }
        drawPath(shape, dark.shade(0.3), style = Stroke(0.075f))
        drawPath(discP(0.0, -0.95, 0.08), stemBrown)
        gloss(-0.44, -0.44, opacity = 0.55)
    }

    private fun DrawScope.banana() {
        val yellow = color(FruitKind.BANANA)
        val p = Path(); p.m(-0.95, -0.36)
        p.c(-0.8, 0.95, 0.66, 0.98, 0.86, -0.62); p.l(0.7, -0.44); p.c(0.42, 0.22, -0.52, 0.24, -0.8, -0.2); p.close()
        body(p, yellow, rgb(0.92, 0.64, 0.08), rim = 0.5)
        val ridge = Path(); ridge.m(-0.8, -0.1); ridge.c(-0.6, 0.62, 0.5, 0.66, 0.72, -0.4)
        drawPath(ridge, Color.White.op(0.4), style = Stroke(0.07f, cap = StrokeCap.Round))
        stem(0.8, -0.54, 0.9, -0.66, 0.92, -0.8, 0.15, rgb(0.52, 0.44, 0.16))
        drawPath(discP(-0.9, -0.3, 0.075), rgb(0.32, 0.2, 0.08))
    }

    private fun DrawScope.lemon() {
        val yellow = color(FruitKind.LEMON)
        rotate(-24f, Offset.Zero) {
            val shape = Path(); shape.m(-1.0, 0.0)
            shape.c(-0.9, -0.34, -0.52, -0.66, 0.0, -0.66); shape.c(0.52, -0.66, 0.9, -0.34, 1.0, 0.0)
            shape.c(0.9, 0.34, 0.52, 0.66, 0.0, 0.66); shape.c(-0.52, 0.66, -0.9, 0.34, -1.0, 0.0); shape.close()
            body(shape, yellow, rgb(0.88, 0.72, 0.1), rim = 0.45)
            for (p in lemonDimples) drawPath(discP(p.x * 1.3, p.y, 0.025), yellow.shade(0.3).op(0.6))
            leaf(0.66, -0.26, 0.96, -0.8, 0.18)
            gloss(-0.36, -0.28, 0.24, 0.1)
        }
    }
}

/** A single fruit as a small composable icon (iOS FruitIcon). */
@Composable
fun FruitIcon(kind: FruitKind, modifier: Modifier, face: Boolean = false, scale: Double = 0.36) {
    Canvas(modifier) {
        val r = min(size.width, size.height) * scale
        FruitArt.draw(this, kind, size.width / 2.0, size.height / 2.0 + r * 0.12, r, face = face)
    }
}
