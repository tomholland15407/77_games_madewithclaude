package com.gogs.bananagame.core

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.min
import kotlin.math.sin

/** A tiny deterministic noise in 0…1 (the `hash` helper several iOS games use). */
fun hash01(i: Int): Double {
    val v = sin(i * 12.9898 + 78.233) * 43758.5453
    return v - floor(v)
}

/** The demo "tap" ring (iOS DemoTapRipple): a 26 pt ring growing ×0.7→×3.6 and fading over 0.55 s. */
fun DrawScope.tapRipple(x: Double, y: Double, t: Double) {
    if (t < 0 || t > 0.55) return
    val k = t / 0.55
    val e = 1 - (1 - k) * (1 - k)
    val r = 13.0 * density * (0.7 + (3.6 - 0.7) * e)
    circleStroke(x, y, r, androidx.compose.ui.graphics.Color.White.op(0.85 * (1 - e)), 3.0 * density)
}

/**
 * A fire-and-forget burst of tiny squares (PixelFX `ParticleBurstView`): squares fly out over
 * 0.5 s with an ease-out, fall by `gravity` points and fade. Driven by elapsed time `t` so it can
 * be drawn from any Canvas; `seed` varies the jitter between bursts. Sizes are in points.
 */
fun DrawScope.particleBurst(x: Double, y: Double, t: Double, color: Color, count: Int = 12, spread: Double = 60.0, gravity: Double = 24.0, seed: Int = 0) {
    if (t < 0 || t > 0.55) return
    val k = min(1.0, t / 0.5)
    val e = 1 - (1 - k) * (1 - k)
    val u = density.toDouble()
    for (i in 0 until count) {
        val a = i.toDouble() / count * 2 * PI + hash01(i * 7 + 3 + seed) * 0.7 - 0.35
        val d = spread * u * (0.45 + 0.55 * hash01(i * 13 + 5 + seed)) * e
        val s = (2 + 2 * hash01(i * 17 + 1 + seed)) * u
        rect(x + cos(a) * d - s, y + sin(a) * d + gravity * u * e - s, s * 2, s * 2, color.op(1 - e))
    }
}
