package com.gogs.bananagame.core

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke

/**
 * The 🍌 mascot, drawn as a bright, fresh banana (Apple's emoji look) instead of the device's emoji
 * font, whose banana is a duller, browner yellow on many Android phones. Size it with the modifier.
 */
@Composable
fun BananaMascot(modifier: Modifier) {
    Canvas(modifier) { banana(0.0, 0.0, size.minDimension.toDouble()) }
}

private val peelTop = rgb(1.0, 0.96, 0.52)
private val peel = rgb(1.0, 0.86, 0.16)
private val peelBottom = rgb(0.98, 0.74, 0.04)
private val edge = rgb(0.86, 0.6, 0.0)
private val stem = rgb(0.42, 0.29, 0.1)
private val tip = rgb(0.3, 0.2, 0.08)

/** A banana filling the square (x, y, s): a curved crescent from the tip (lower left) to the stem (upper right). */
fun DrawScope.banana(x: Double, y: Double, s: Double) {
    fun px(f: Double) = x + f * s
    fun py(f: Double) = y + f * s
    val body = Path().apply {
        m(px(0.08), py(0.56))
        c(px(0.16), py(0.95), px(0.72), py(1.0), px(0.88), py(0.3))
        l(px(0.79), py(0.22))
        c(px(0.7), py(0.7), px(0.3), py(0.78), px(0.08), py(0.56))
        close()
    }
    drawPath(body, Brush.verticalGradient(listOf(peelTop, peel, peelBottom), py(0.3).toFloat(), py(0.92).toFloat()))
    // A soft ridge along the belly and a glossy highlight under the inner curve.
    val ridge = Path().apply { m(px(0.14), py(0.65)); c(px(0.34), py(0.9), px(0.7), py(0.88), px(0.85), py(0.34)) }
    drawPath(ridge, edge.op(0.35), style = Stroke((s * 0.025).toFloat(), cap = StrokeCap.Round))
    val gloss = Path().apply { m(px(0.2), py(0.63)); c(px(0.36), py(0.76), px(0.6), py(0.74), px(0.75), py(0.38)) }
    drawPath(gloss, rgb(1.0, 1.0, 0.9).op(0.6), style = Stroke((s * 0.04).toFloat(), cap = StrokeCap.Round))
    drawPath(body, edge.op(0.7), style = Stroke((s * 0.02).toFloat()))
    // The stem and the dark tip.
    drawPath(polyPath(px(0.775), py(0.25), px(0.8), py(0.07), px(0.91), py(0.09), px(0.885), py(0.31)), stem)
    circle(px(0.09), py(0.565), s * 0.035, tip)
}
