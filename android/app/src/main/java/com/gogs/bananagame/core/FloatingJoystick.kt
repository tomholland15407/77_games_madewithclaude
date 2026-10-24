package com.gogs.bananagame.core

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.platform.LocalDensity
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * The one-thumb joystick strip for the fast dodging games (iOS FloatingJoystick.swift): touch
 * anywhere in the strip and the stick centres under the thumb; full speed after a short throw
 * (19% of the base), a 10% dead zone then a √ response, and past a full push the centre follows
 * the thumb so reversals are one flick. Between touches the base rests where it was last used,
 * clear of the page's skip button in the middle. Each game draws its own base and knob.
 *
 * [onVector] receives the fraction of top speed per axis (length ≤ 1). In the demo the knob follows
 * [demoVector] with a finger riding it, and touches are ignored.
 */
object FloatingJoystickMath {
    const val DEAD_ZONE = 0.1
    fun throwRadius(baseSize: Double) = baseSize * 0.19

    /** Thumb offset → fraction of top speed. */
    fun response(dx: Double, dy: Double, r: Double): P {
        val len = hypot(dx, dy)
        val m = min(1.0, len / max(1.0, r))
        if (m <= DEAD_ZONE || len <= 0) return P.zero
        val k = sqrt((m - DEAD_ZONE) / (1 - DEAD_ZONE))
        return P(dx / len * k, dy / len * k)
    }

    /** The thumb offset that gives `v` (the inverse of [response]), for the demo's knob. */
    fun thumbOffset(v: P, r: Double): P {
        val k = min(1.0, hypot(v.x, v.y))
        if (k <= 0.001) return P.zero
        val m = DEAD_ZONE + k * k * (1 - DEAD_ZONE)
        return P(v.x / k * m * r, v.y / k * m * r)
    }
}

@Composable
fun FloatingJoystick(
    modifier: Modifier,
    baseSizeDp: Double,
    demo: Boolean,
    active: Boolean,
    demoVector: P,
    onVector: (P) -> Unit,
    base: DrawScope.(push: P) -> Unit,
    knob: DrawScope.() -> Unit,
) {
    val baseSize = baseSizeDp * LocalDensity.current.density
    val r = FloatingJoystickMath.throwRadius(baseSize)
    var origin by remember { mutableStateOf<P?>(null) }
    var home by remember { mutableStateOf<P?>(null) }
    var thumb by remember { mutableStateOf(P.zero) }
    var push by remember { mutableStateOf(P.zero) }
    val act by rememberUpdatedState(active)
    val hand = rememberHand()

    LaunchedEffect(active) { if (!active) { origin = null; thumb = P.zero; push = P.zero; onVector(P.zero) } }

    fun settle(p: P, w: Double, h: Double): P {
        val rad = baseSize / 2
        var x = min(w - rad - 4, max(rad + 4, p.x))
        val y = min(max(rad, h - rad), max(rad, p.y))
        val mid = w / 2; val clear = rad + 30 * (baseSize / baseSizeDp)
        if (abs(x - mid) < clear) x = if (x < mid) mid - clear else mid + clear
        return P(x, y)
    }

    Canvas(modifier.then(if (demo) Modifier else Modifier.touchDrag(
        onStart = { },
        onMove = { s, now ->
            if (!act) return@touchDrag
            var o = origin ?: s
            var dx = now.x - o.x; var dy = now.y - o.y
            val len = hypot(dx, dy)
            if (len > r) {
                val pull = (len - r) / len
                o = P(o.x + dx * pull, o.y + dy * pull)
                dx = now.x - o.x; dy = now.y - o.y
            }
            origin = o
            thumb = P(dx, dy)
            push = FloatingJoystickMath.response(dx, dy, r)
            onVector(push)
        },
        onEnd = { s, _ ->
            val o = origin ?: s
            home = o   // settled when drawn (needs the strip's size)
            origin = null; thumb = P.zero; push = P.zero
            onVector(P.zero)
        },
    ))) {
        val w = size.width.toDouble(); val h = size.height.toDouble()
        val c = origin ?: settle(home ?: P(w * 0.24, h / 2), w, h)
        val v = if (demo) demoVector else push
        val shown = if (demo) FloatingJoystickMath.thumbOffset(demoVector, r) else thumb
        translate((c.x - baseSize / 2).f, (c.y - baseSize / 2).f) {
            withSize(baseSize) { base(v) }
        }
        val ks = baseSize * 0.5
        translate((c.x + shown.x - ks / 2).f, (c.y + shown.y - ks / 2).f) { withSize(ks) { knob() } }
        if (demo && (demoVector.x != 0.0 || demoVector.y != 0.0)) {
            val s = baseSize * 0.3
            hand(hand, c.x + shown.x + baseSize * 0.1 - s / 2, c.y + shown.y + baseSize * 0.15 - s / 2, s)
        }
    }
}

/** Runs [block] with the draw size temporarily set to a square of side [s] (for art that reads `size`). */
inline fun DrawScope.withSize(s: Double, block: DrawScope.() -> Unit) {
    val old = drawContext.size
    drawContext.size = androidx.compose.ui.geometry.Size(s.toFloat(), s.toFloat())
    try { block() } finally { drawContext.size = old }
}
