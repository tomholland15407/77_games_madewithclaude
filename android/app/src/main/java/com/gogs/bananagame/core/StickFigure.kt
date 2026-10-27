package com.gogs.bananagame.core

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max

/** A pose = joint points in a 0…1 unit box (x right, y down), authored facing right (iOS StickPose). */
data class StickPose(
    val head: P, val headR: Double, val neck: P, val hip: P,
    val lElbow: P, val lHand: P, val rElbow: P, val rHand: P,
    val lKnee: P, val lFoot: P, val rKnee: P, val rFoot: P,
) {
    companion object {
        val standing = StickPose(P(0.50, 0.15), 0.10, P(0.50, 0.27), P(0.50, 0.60),
            P(0.42, 0.40), P(0.40, 0.52), P(0.58, 0.40), P(0.61, 0.54),
            P(0.45, 0.78), P(0.42, 0.97), P(0.56, 0.78), P(0.60, 0.97))
        val firing = StickPose(P(0.50, 0.15), 0.10, P(0.50, 0.27), P(0.50, 0.60),
            P(0.42, 0.40), P(0.37, 0.46), P(0.62, 0.35), P(0.76, 0.35),
            P(0.44, 0.78), P(0.38, 0.97), P(0.58, 0.78), P(0.64, 0.97))
        val runA = StickPose(P(0.55, 0.14), 0.095, P(0.52, 0.27), P(0.47, 0.58),
            P(0.55, 0.40), P(0.63, 0.46), P(0.43, 0.38), P(0.37, 0.33),
            P(0.58, 0.72), P(0.66, 0.83), P(0.44, 0.74), P(0.34, 0.92))
        val runB = StickPose(P(0.55, 0.14), 0.095, P(0.52, 0.27), P(0.47, 0.58),
            P(0.43, 0.38), P(0.37, 0.33), P(0.55, 0.40), P(0.63, 0.46),
            P(0.44, 0.74), P(0.34, 0.92), P(0.58, 0.72), P(0.66, 0.83))
        val jumping = StickPose(P(0.56, 0.16), 0.095, P(0.52, 0.28), P(0.50, 0.56),
            P(0.44, 0.34), P(0.39, 0.26), P(0.60, 0.36), P(0.68, 0.28),
            P(0.46, 0.66), P(0.54, 0.64), P(0.58, 0.64), P(0.66, 0.60))
    }
}

/**
 * A vector stick figure in the frame (x, y, w, h): rounded strokes + a filled head with a dark
 * contour (iOS StickFigure). Height-driven and horizontally centred; `mirror` faces it left.
 */
fun DrawScope.stickFigure(
    pose: StickPose, x: Double, y: Double, w: Double, h: Double,
    color: Color = Color.Black, outline: Color = rgb(0.05, 0.05, 0.09), lineFrac: Double = 0.055,
    gun: Boolean = false, mirror: Boolean = false,
) {
    val cx = x + w / 2
    fun map(p: P): P = P(cx + (if (mirror) -1 else 1) * (p.x - 0.5) * h, y + p.y * h)
    val lw = h * lineFrac
    val headD = pose.headR * 2 * h
    val extra = h * 0.022
    val body = Path()
    fun seg(a: P, b: P) { val m = map(a); val n = map(b); body.m(m.x, m.y); body.l(n.x, n.y) }
    fun chain(a: P, b: P, c: P) { val m = map(a); val n = map(b); val o = map(c); body.m(m.x, m.y); body.l(n.x, n.y); body.l(o.x, o.y) }
    seg(pose.neck, pose.hip)
    chain(pose.neck, pose.lElbow, pose.lHand)
    chain(pose.neck, pose.rElbow, pose.rHand)
    chain(pose.hip, pose.lKnee, pose.lFoot)
    chain(pose.hip, pose.rKnee, pose.rFoot)
    val barrel = Path()
    if (gun) {
        val hand = pose.rHand; val elbow = pose.rElbow
        val dx = hand.x - elbow.x; val dy = hand.y - elbow.y
        val len = max(0.0001, hypot(dx, dy))
        val ux = dx / len; val uy = dy / len
        val tip = P(hand.x + ux * 0.13, hand.y + uy * 0.13)
        val grip = P(hand.x - uy * 0.06, hand.y + abs(ux) * 0.06 + 0.02)
        val mh = map(hand); val mt = map(tip); val mg = map(grip)
        barrel.m(mh.x, mh.y); barrel.l(mt.x, mt.y)
        barrel.m(mh.x, mh.y); barrel.l(mg.x, mg.y)
    }
    val hd = map(pose.head)
    drawPath(body, outline, style = Stroke((lw + extra).toFloat(), cap = StrokeCap.Round, join = StrokeJoin.Round))
    circle(hd.x, hd.y, (headD + extra) / 2, outline)
    if (gun) drawPath(barrel, outline, style = Stroke((lw * 0.9 + extra).toFloat(), cap = StrokeCap.Round, join = StrokeJoin.Round))
    drawPath(body, color, style = Stroke(lw.toFloat(), cap = StrokeCap.Round, join = StrokeJoin.Round))
    circle(hd.x, hd.y, headD / 2, color)
    if (gun) drawPath(barrel, gray(0.22), style = Stroke((lw * 0.9).toFloat(), cap = StrokeCap.Round, join = StrokeJoin.Round))
}
