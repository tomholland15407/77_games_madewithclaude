package com.gogs.bananagame.core

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.vector.VectorPainter
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

// ---------------------------------------------------------------------------------------------
// Colour ramps (PixelFX.swift `shade` / `lit`).
// ---------------------------------------------------------------------------------------------

/** Darker shade — mix toward black. */
fun Color.shade(by: Double): Color = lerpColor(this, Color.Black.copy(alpha = alpha), by)

/** Lighter tint — mix toward white. */
fun Color.lit(by: Double): Color = lerpColor(this, Color.White.copy(alpha = alpha), by)

fun Color.mix(other: Color, by: Double): Color = lerpColor(this, other, by)

// ---------------------------------------------------------------------------------------------
// Drawing helpers for GraphicsContext idioms with no direct DrawScope twin.
// ---------------------------------------------------------------------------------------------

/** GraphicsContext.opacity: draws [block] into a layer composited at [alpha]. */
inline fun DrawScope.withAlpha(alpha: Double, block: DrawScope.() -> Unit) {
    if (alpha <= 0.0) return
    if (alpha >= 1.0) { block(); return }
    drawIntoCanvas { c ->
        c.saveLayer(Rect(Offset.Zero, size), Paint().apply { this.alpha = alpha.toFloat() })
        block()
        c.restore()
    }
}

/** The demo "finger": a white pointing hand with a soft shadow. Create the painter with [rememberHand]. */
fun DrawScope.hand(painter: VectorPainter, x: Double, y: Double, s: Double) {
    if (s <= 0) return
    translate((x + s * 0.04).toFloat(), (y + s * 0.05).toFloat()) {
        with(painter) { draw(Size(s.toFloat(), s.toFloat()), alpha = 0.45f, colorFilter = ColorFilter.tint(Color.Black)) }
    }
    translate(x.toFloat(), y.toFloat()) {
        with(painter) { draw(Size(s.toFloat(), s.toFloat()), colorFilter = ColorFilter.tint(Color.White)) }
    }
}

@Composable
fun rememberHand(): VectorPainter = rememberVectorPainter(Icons.Filled.TouchApp)

/** Draws any vector icon tinted, top-left at (x, y), square size s. */
fun DrawScope.icon(painter: VectorPainter, x: Double, y: Double, s: Double, tint: Color) {
    if (s <= 0) return
    translate(x.toFloat(), y.toFloat()) {
        with(painter) { draw(Size(s.toFloat(), s.toFloat()), colorFilter = ColorFilter.tint(tint)) }
    }
}

/** Radial darkening at the edges (PixelFX `VignetteOverlay`). */
fun DrawScope.vignette(strength: Double = 0.35) {
    val minD = minOf(size.width, size.height); val maxD = maxOf(size.width, size.height)
    val r = maxD * 0.75f
    val stop = (minD * 0.35f / r).coerceIn(0f, 1f)
    drawRect(Brush.radialGradient(0f to Color.Transparent, stop to Color.Transparent, 1f to Color.Black.op(strength),
        center = center, radius = r))
}

// ---------------------------------------------------------------------------------------------
// BrainstormingView — shown while a solver builds a board off-main (iOS CratePushGame.swift).
// ---------------------------------------------------------------------------------------------

@Composable
fun BrainstormingView(skyTop: Color, skyBottom: Color) {
    var dots by remember { mutableStateOf("") }
    GameBox { w, h ->
        val x = remember { Animatable((w * 0.5).toFloat()) }
        val y = remember { Animatable((h * 0.66).toFloat()) }
        val rot = remember { Animatable(0f) }
        LaunchedEffect(Unit) {
            launch {
                val seq = listOf("", ".", "..", "...")
                var i = 0
                while (isActive) { dots = seq[i % seq.size]; i++; delay(350) }
            }
            while (isActive) {
                val duckOut = chance(0.4)
                val (tx, ty) = if (duckOut) when (rndInt(0..3)) {
                    0 -> -90.0 * 3 to rnd(0.0, h)
                    1 -> w + 270 to rnd(0.0, h)
                    2 -> rnd(0.0, w) to -270.0
                    else -> rnd(0.0, w) to h + 270
                } else rnd(w * 0.15, w * 0.85) to rnd(h * 0.18, h * 0.82)
                val dur = (rnd(0.22, 0.7) * 1000).toInt()
                launch { x.animateTo(tx.toFloat(), tween(dur, easing = FastOutSlowInEasing)) }
                launch { y.animateTo(ty.toFloat(), tween(dur, easing = FastOutSlowInEasing)) }
                launch { rot.animateTo(rot.value + rnd(-200.0, 200.0).toFloat(), tween(dur, easing = FastOutSlowInEasing)) }
                delay(dur + (rnd(0.1, 0.8) * 1000).toLong())
            }
        }
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(skyTop, skyBottom)))) {
            Column(
                Modifier.align(Alignment.Center).padding(horizontal = 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text(L("I am brainstorming$dots", "Đang động não$dots"), style = ts(24.0, FontWeight.Black, BananaTheme.banana), textAlign = TextAlign.Center)
                Text(L("Even Elon Musk has to think!", "Ngay cả Elon Musk cũng phải suy nghĩ!"),
                    style = ts(16.0, FontWeight.SemiBold, Color.White.op(0.75)), textAlign = TextAlign.Center)
            }
            Text("🍌", style = ts(54.0), modifier = Modifier
                .offset { IntOffset((x.value - 27.dp.toPx()).roundToInt(), (y.value - 36.dp.toPx()).roundToInt()) }
                .rotate(rot.value))
        }
    }
}

/** A field of static twinkly dots (PixelFX `Starfield`): positions in 0…1 and radius in px. */
class Starfield(count: Int = 40) {
    val stars = List(count) { Triple(rnd(0.0, 1.0), rnd(0.0, 1.0), rnd(0.6, 2.0)) }
    fun draw(d: DrawScope, color: Color = Color.White, scale: Double = 1.0) {
        for ((x, y, r) in stars) {
            d.drawOval(color.op(r / 2.0 * 0.8), Offset((x * d.size.width).toFloat(), (y * d.size.height).toFloat()),
                Size((r * scale).toFloat(), (r * scale).toFloat()))
        }
    }
}
