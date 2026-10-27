package com.gogs.bananagame.core

import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.scale

/**
 * Draws in points: scales the canvas by its density and hands the block the size in points, so art
 * ported from a SwiftUI Canvas keeps every iOS number (line widths, offsets) unchanged.
 */
inline fun DrawScope.inPoints(crossinline block: DrawScope.(w: Double, h: Double) -> Unit) {
    val u = density
    val w = size.width / u.toDouble(); val h = size.height / u.toDouble()
    scale(u, u, Offset.Zero) { block(w, h) }
}

/** Static art behind the content, drawn in points once per size into a bitmap. */
fun Modifier.artBehind(draw: DrawScope.(w: Double, h: Double) -> Unit): Modifier = drawWithCache {
    val bmp = ImageBitmap(size.width.toInt().coerceAtLeast(1), size.height.toInt().coerceAtLeast(1))
    CanvasDrawScope().draw(this, layoutDirection, androidx.compose.ui.graphics.Canvas(bmp), size) { inPoints(draw) }
    onDrawBehind { drawImage(bmp) }
}
