package com.gogs.bananagame.core

import android.graphics.BlurMaskFilter
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asAndroidPath
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight

// GraphicsContext `.blur` / `.shadow` filters → a native BlurMaskFilter on the draw.

private fun blurPaint(color: Color, radius: Double, stroke: Double = 0.0) =
    android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color.toArgb()
        if (stroke > 0) {
            style = android.graphics.Paint.Style.STROKE
            strokeWidth = stroke.toFloat()
            strokeCap = android.graphics.Paint.Cap.ROUND
            strokeJoin = android.graphics.Paint.Join.ROUND
        }
        if (radius > 0.5) maskFilter = BlurMaskFilter(radius.toFloat(), BlurMaskFilter.Blur.NORMAL)
    }

/** Fills [path] blurred by [radius] px (a soft glow / shadow). */
fun DrawScope.blurPath(path: Path, color: Color, radius: Double) =
    drawIntoCanvas { it.nativeCanvas.drawPath(path.asAndroidPath(), blurPaint(color, radius)) }

/** Strokes [path] blurred by [radius] px. */
fun DrawScope.blurStroke(path: Path, color: Color, lineWidth: Double, radius: Double) =
    drawIntoCanvas { it.nativeCanvas.drawPath(path.asAndroidPath(), blurPaint(color, radius, lineWidth)) }

/** A blurred oval in the rect (x, y, w, h). */
fun DrawScope.blurOval(x: Double, y: Double, w: Double, h: Double, color: Color, radius: Double) =
    drawIntoCanvas { it.nativeCanvas.drawOval(x.toFloat(), y.toFloat(), (x + w).toFloat(), (y + h).toFloat(), blurPaint(color, radius)) }

/** A blurred circle. */
fun DrawScope.blurCircle(cx: Double, cy: Double, r: Double, color: Color, radius: Double) =
    blurOval(cx - r, cy - r, r * 2, r * 2, color, radius)

/** A blurred rounded rect. */
fun DrawScope.blurRRect(x: Double, y: Double, w: Double, h: Double, r: Double, color: Color, radius: Double) =
    drawIntoCanvas {
        it.nativeCanvas.drawRoundRect(x.toFloat(), y.toFloat(), (x + w).toFloat(), (y + h).toFloat(), r.toFloat(), r.toFloat(), blurPaint(color, radius))
    }

/** A blurred line (glow beams, lasers). */
fun DrawScope.blurLine(x1: Double, y1: Double, x2: Double, y2: Double, color: Color, lineWidth: Double, radius: Double) =
    drawIntoCanvas { it.nativeCanvas.drawLine(x1.toFloat(), y1.toFloat(), x2.toFloat(), y2.toFloat(), blurPaint(color, radius, lineWidth)) }

/** Text with a bloom: a blurred copy under the crisp one. */
fun DrawScope.glowText(
    tm: TextMeasurer, s: String, x: Double, y: Double, size: Double, glow: Color, color: Color, radius: Double,
    weight: FontWeight = FontWeight.Bold, family: FontFamily = Rounded,
) {
    drawIntoCanvas { c ->
        val p = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            this.color = glow.toArgb()
            textSize = size.toFloat()
            textAlign = android.graphics.Paint.Align.CENTER
            typeface = android.graphics.Typeface.create(
                if (family == Mono) android.graphics.Typeface.MONOSPACE else android.graphics.Typeface.DEFAULT,
                if (weight.weight >= 600) android.graphics.Typeface.BOLD else android.graphics.Typeface.NORMAL)
            if (radius > 0.5) maskFilter = BlurMaskFilter(radius.toFloat(), BlurMaskFilter.Blur.NORMAL)
        }
        val fm = p.fontMetrics
        c.nativeCanvas.drawText(s, x.toFloat(), (y - (fm.ascent + fm.descent) / 2).toFloat(), p)
    }
    text(tm, s, x, y, size, color, weight, family)
}
