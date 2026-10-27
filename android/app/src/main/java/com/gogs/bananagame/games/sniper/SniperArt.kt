package com.gogs.bananagame.games.sniper

import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.drawscope.translate
import com.gogs.bananagame.core.*
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Sniper's art (iOS SNArt and the view's vista / scope drawing): a parallax mountain outpost from day
 * to a starry night, red stick-figure soldiers, and the crafted scope. Drawn in points (see
 * [inPoints]); strokes use SwiftUI's defaults (butt caps, miter joins) unless the iOS code rounds them.
 */
internal object SNArt {
    fun hash(n: Double): Double { val x = sin(n) * 43758.5453; return x - floor(x) }

    // Poses in the stick figure's unit box (facing right, feet at y ≈ 0.97).
    val standPose = StickPose(P(0.5, 0.15), 0.1, P(0.5, 0.27), P(0.5, 0.6),
        P(0.43, 0.41), P(0.44, 0.53), P(0.58, 0.4), P(0.6, 0.5), P(0.46, 0.78), P(0.44, 0.97), P(0.55, 0.78), P(0.57, 0.97))
    val walkA = StickPose(P(0.52, 0.15), 0.1, P(0.51, 0.27), P(0.49, 0.6),
        P(0.57, 0.41), P(0.62, 0.5), P(0.44, 0.41), P(0.4, 0.5), P(0.56, 0.78), P(0.62, 0.97), P(0.45, 0.79), P(0.38, 0.96))
    val walkB = StickPose(P(0.52, 0.15), 0.1, P(0.51, 0.27), P(0.49, 0.6),
        P(0.44, 0.41), P(0.4, 0.5), P(0.57, 0.41), P(0.62, 0.5), P(0.45, 0.79), P(0.38, 0.96), P(0.56, 0.78), P(0.62, 0.97))
    /** Rifle up at the shoulder, feet braced. */
    val aimPose = StickPose(P(0.5, 0.15), 0.1, P(0.5, 0.27), P(0.49, 0.6),
        P(0.6, 0.36), P(0.72, 0.31), P(0.56, 0.37), P(0.62, 0.3), P(0.43, 0.78), P(0.37, 0.97), P(0.57, 0.78), P(0.63, 0.97))
    /** Thrown back by the shot. */
    val hitPose = StickPose(P(0.46, 0.15), 0.1, P(0.47, 0.27), P(0.5, 0.6),
        P(0.38, 0.2), P(0.32, 0.1), P(0.58, 0.2), P(0.64, 0.1), P(0.45, 0.78), P(0.42, 0.97), P(0.57, 0.77), P(0.62, 0.95))

    // Stroke widths as fractions of the soldier's height, shared by the art and the hit test.
    const val limbW = 0.085
    const val outlineW = 0.04
    const val brimW = 0.03

    /**
     * Does a point in the figure's unit box (facing right, feet at y ≈ 0.97) touch the soldier as
     * [soldier] draws him — outlined limbs, vest, head and helmet — give or take `slack`? The rifle
     * doesn't count.
     */
    fun touches(px: Double, py: Double, pose: StickPose, slack: Double): Boolean {
        fun near(a: P, b: P, r: Double): Boolean {
            val dx = b.x - a.x; val dy = b.y - a.y
            val len2 = dx * dx + dy * dy
            val t = if (len2 > 0) max(0.0, min(1.0, ((px - a.x) * dx + (py - a.y) * dy) / len2)) else 0.0
            return hypot(px - (a.x + dx * t), py - (a.y + dy * t)) <= r + slack
        }
        val bones = listOf(pose.neck to pose.hip, pose.neck to pose.lElbow, pose.lElbow to pose.lHand,
            pose.neck to pose.rElbow, pose.rElbow to pose.rHand, pose.hip to pose.lKnee,
            pose.lKnee to pose.lFoot, pose.hip to pose.rKnee, pose.rKnee to pose.rFoot)
        if (bones.any { near(it.first, it.second, (limbW + outlineW) / 2) }) return true
        if (near(P(pose.neck.x, pose.neck.y + 0.05), P(pose.hip.x, pose.hip.y - 0.07), limbW * 2.1 / 2)) return true
        val h = pose.head; val hr = pose.headR
        if (near(h, h, hr + outlineW / 2)) return true          // the outlined head covers the helmet dome
        return near(P(h.x - hr * 1.1, h.y + hr * 0.1), P(h.x + hr * 1.45, h.y + hr * 0.1), brimW / 2)
    }

    private fun DrawScope.stroke(p: Path, c: Color, lw: Double, cap: StrokeCap = StrokeCap.Butt, join: StrokeJoin = StrokeJoin.Miter) =
        drawPath(p, c, style = Stroke(lw.f, miter = 10f, cap = cap, join = join))
    private fun Path.oval(x: Double, y: Double, w: Double, h: Double) = addOval(Rect(x.f, y.f, (x + w).f, (y + h).f))
    private fun Path.box(x: Double, y: Double, w: Double, h: Double) = addRect(Rect(x.f, y.f, (x + w).f, (y + h).f))
    private fun Path.rbox(x: Double, y: Double, w: Double, h: Double, r: Double) =
        addRoundRect(RoundRect(x.f, y.f, (x + w).f, (y + h).f, CornerRadius(r.f, r.f)))

    /**
     * A red soldier as a vector stick figure: red limbs over a dark contour, a darker vest, a dark helmet
     * and a rifle — carried across the chest, or shouldered (with a laser glint) when aiming.
     */
    fun DrawScope.soldier(fx: Double, fy: Double, H: Double, pose: StickPose, facing: Double, aiming: Boolean, tilt: Double = 0.0) {
        translate(fx.f, fy.f) {
            rotateRad(tilt.f, Offset.Zero) {
                fun mx(p: P) = (p.x - 0.5) * H * facing
                fun my(p: P) = (p.y - 0.97) * H
                val red = if (aiming) rgb(0.98, 0.34, 0.24) else rgb(0.84, 0.2, 0.2)
                val outline = rgb(0.08, 0.04, 0.05)
                val lw = H * limbW
                val limbs = Path()
                limbs.m(mx(pose.neck), my(pose.neck)); limbs.l(mx(pose.hip), my(pose.hip))
                fun chain(a: P, b: P, c: P) { limbs.m(mx(a), my(a)); limbs.l(mx(b), my(b)); limbs.l(mx(c), my(c)) }
                chain(pose.neck, pose.lElbow, pose.lHand)
                chain(pose.neck, pose.rElbow, pose.rHand)
                chain(pose.hip, pose.lKnee, pose.lFoot)
                chain(pose.hip, pose.rKnee, pose.rFoot)
                val rifle = Path()
                val muzzle: P
                if (aiming) {
                    rifle.m(mx(P(0.4, 0.31)), my(P(0.4, 0.31))); rifle.l(mx(P(0.95, 0.27)), my(P(0.95, 0.27)))
                    muzzle = P(mx(P(0.95, 0.27)), my(P(0.95, 0.27)))
                } else {
                    rifle.m(mx(P(0.34, 0.54)), my(P(0.34, 0.54))); rifle.l(mx(P(0.68, 0.27)), my(P(0.68, 0.27)))
                    muzzle = P(0.0, 0.0)
                }
                val hx = mx(pose.head); val hy = my(pose.head); val hr = pose.headR * H
                val ol = H * outlineW
                stroke(limbs, outline, lw + ol, StrokeCap.Round, StrokeJoin.Round)
                stroke(rifle, outline, lw * 0.75 + ol, StrokeCap.Round)
                circle(hx, hy, hr + ol / 2, outline)
                stroke(limbs, red, lw, StrokeCap.Round, StrokeJoin.Round)
                val vest = Path().apply {
                    m(mx(P(pose.neck.x, pose.neck.y + 0.05)), my(P(pose.neck.x, pose.neck.y + 0.05)))
                    l(mx(P(pose.hip.x, pose.hip.y - 0.07)), my(P(pose.hip.x, pose.hip.y - 0.07)))
                }
                stroke(vest, red.mix(Color.Black, 0.32), lw * 2.1, StrokeCap.Round)
                circle(hx, hy, hr, red)
                val helmet = Path().apply { arc(hx, hy + hr * 0.1, hr * 1.12, PI, 2 * PI, moveFirst = true); close() }
                drawPath(helmet, rgb(0.26, 0.09, 0.1))
                val brim = Path().apply { m(hx - hr * 1.1 * facing, hy + hr * 0.1); l(hx + hr * 1.45 * facing, hy + hr * 0.1) }
                stroke(brim, rgb(0.26, 0.09, 0.1), max(1.0, H * brimW), StrokeCap.Round)
                stroke(rifle, gray(0.14), lw * 0.75, StrokeCap.Round)
                if (aiming) {
                    val glow = rgb(1.0, 0.3, 0.2)
                    circle(muzzle.x, muzzle.y, H * 0.07, radial(listOf(glow.op(0.9), glow.op(0.0)), muzzle.x, muzzle.y, H * 0.07))
                    circle(muzzle.x, muzzle.y, H * 0.018, Color.White)
                }
            }
        }
    }

    private fun sky(level: Int): Pair<Color, Color> = when (min(level, 7)) {
        1 -> rgb(0.50, 0.70, 0.92) to rgb(0.82, 0.88, 0.80)
        2 -> rgb(0.42, 0.60, 0.86) to rgb(0.86, 0.82, 0.62)
        3 -> rgb(0.58, 0.44, 0.52) to rgb(0.95, 0.66, 0.40)
        4 -> rgb(0.40, 0.30, 0.48) to rgb(0.78, 0.44, 0.42)
        5 -> rgb(0.16, 0.16, 0.30) to rgb(0.36, 0.28, 0.40)
        6 -> rgb(0.10, 0.10, 0.22) to rgb(0.24, 0.18, 0.30)
        else -> rgb(0.06, 0.07, 0.16) to rgb(0.16, 0.12, 0.22)
    }

    /**
     * Inside the lens: the vista with its parallax layers (sky 0.2, ridge 0.35, treeline + outpost 0.6,
     * ground 1), then the soldiers, their aim beams, and the ones just shot toppling over.
     */
    fun DrawScope.scene(world: SniperWorld, W: Double, H: Double, now: Double) {
        val level = world.level
        val s = H / VIEW_H
        val (sky0, sky1) = sky(level)
        val groundColor = sky1.shade(0.55)
        fun px(wx: Double, par: Double) = W / 2 + (wx - world.aimX) * par * s
        fun py(wy: Double, par: Double) = H / 2 + (wy - world.aimY) * par * s
        val night = level >= 5
        rect(0.0, 0.0, W, H, vgrad(listOf(sky0, sky1), 0.0, H))
        if (night) {
            val stars = Path()
            for (i in 0 until 70) {
                val d = 1 + hash(i * 1.9) * 1.6
                stars.oval(px(hash(i * 3.1) * SCENE_W, 0.15), py(0.02 + hash(i * 7.7) * 0.42, 0.15), d, d)
            }
            drawPath(stars, Color.White.op(0.8))
        }
        // Sun / moon disc with a soft glow.
        val dx = px(SCENE_W * 0.5, 0.2); val dy = py(0.24, 0.2)
        val dr = min(W, H) * 0.06
        val discCol = if (level >= 5) gray(0.96) else rgb(1.0, 0.95, 0.8)
        circle(dx, dy, dr * 2.4, Brush.radialGradient(0f to discCol.op(0.35), (1 / 2.4f) to discCol.op(0.35), 1f to discCol.op(0.0),
            center = off(dx, dy), radius = (dr * 2.4).f))
        circle(dx, dy, dr, discCol.op(0.9))
        if (!night) {
            val clouds = Path()
            for (i in 0 until 7) {
                val cx = px(hash(i * 5.3) * SCENE_W, 0.25); val cy = py(0.1 + hash(i * 2.3) * 0.16, 0.25)
                val cw = (0.06 + 0.05 * hash(i * 9.1)) * s * 0.25
                for (k in 0 until 3) {
                    val o = (k - 1) * cw * 0.55
                    clouds.oval(cx + o - cw * 0.5, cy - cw * (if (k == 1) 0.42 else 0.28), cw, cw * (if (k == 1) 0.7 else 0.5))
                }
            }
            drawPath(clouds, Color.White.op(if (level >= 3) 0.35 else 0.55))
        }

        // Far ridge (par 0.35) with snowcaps on the high peaks.
        val ridges = world.ridges
        if (ridges.isNotEmpty()) {
            val p = Path()
            p.m(0.0, H)
            p.l(px(ridges[0].x, 0.35), py(ridges[0].top, 0.35))
            for (r in ridges) p.l(px(r.x, 0.35), py(r.top, 0.35))
            p.l(W, py(GROUND_V, 0.35))
            p.l(W, H); p.close()
            drawPath(p, vgrad(listOf(sky1.shade(0.22), sky1.shade(0.42)), py(GROUND_V - 0.2, 0.35), py(GROUND_V, 0.35)))
            val snow = Path()
            for (i in 1 until ridges.size - 1) {
                val r = ridges[i]
                if (r.top >= GROUND_V - 0.165) continue
                val kx = px(r.x, 0.35); val ky = py(r.top, 0.35)
                val lx = px(ridges[i - 1].x, 0.35); val ly = py(ridges[i - 1].top, 0.35)
                val rx = px(ridges[i + 1].x, 0.35); val ry = py(ridges[i + 1].top, 0.35)
                snow.m(kx, ky)
                snow.l(kx + (lx - kx) * 0.3, ky + (ly - ky) * 0.3)
                snow.l(kx + (rx - kx) * 0.3, ky + (ry - ky) * 0.3)
                snow.close()
            }
            drawPath(snow, Color.White.op(if (night) 0.35 else 0.75))
        }
        // Mid treeline (par 0.6), crowned with pines.
        val midline = world.midline
        if (midline.isNotEmpty()) {
            val p = Path()
            p.m(0.0, H)
            for (r in midline) p.l(px(r.x, 0.6), py(r.top + 0.03, 0.6))
            p.l(W, H); p.close()
            val treeCol = sky1.shade(0.52)
            drawPath(p, treeCol)
            val pines = Path()
            for (r in midline) {
                val tx = px(r.x, 0.6); val ty = py(r.top, 0.6); val fy = py(r.top + 0.05, 0.6)
                val hw = 0.018 * s * 0.6
                pines.m(tx, ty); pines.l(tx + hw, fy); pines.l(tx - hw, fy); pines.close()
            }
            drawPath(pines, treeCol)
        }
        // Outpost (par 0.6): huts with a roof line and a door, every third one a watchtower.
        for ((i, b) in world.buildings.withIndex()) {
            val bx = px(b.x, 0.6); val by = py(GROUND_V, 0.6)
            val bw = b.w * s * 0.6; val bh = b.h * s * 0.6
            val wall = groundColor.shade(b.shade).lit(0.08)
            val lit = rgb(1.0, 0.85, 0.4).op(0.7)
            if (i % 3 == 0) {
                val legTop = by - bh * 0.72; val hutH = bh * 0.28
                val legs = Path()
                for (sx in listOf(-1.0, 1.0)) { legs.m(bx + sx * bw * 0.34, by); legs.l(bx + sx * bw * 0.24, legTop) }
                legs.m(bx - bw * 0.32, by); legs.l(bx + bw * 0.26, legTop + bh * 0.2)
                legs.m(bx + bw * 0.32, by); legs.l(bx - bw * 0.26, legTop + bh * 0.2)
                stroke(legs, wall.shade(0.2), max(1.5, bw * 0.06))
                val hx = bx - bw * 0.36; val hy = legTop - hutH; val hw = bw * 0.72
                rect(hx, hy, hw, hutH, wall)
                rect(hx + hw * 0.15, hy + hutH * 0.3, hw * 0.7, hutH * 0.3, if (night) lit else Color.Black.op(0.45))
                drawPath(polyPath(hx - bw * 0.08, hy, hx + hw / 2, hy - hutH * 0.5, hx + hw + bw * 0.08, hy), wall.shade(0.3))
            } else {
                val rx = bx - bw / 2; val ry = by - bh
                rect(rx, ry, bw, bh, wall)
                rect(rx - bw * 0.05, ry - bh * 0.06, bw * 1.1, bh * 0.08, wall.shade(0.3))
                rect(rx + bw / 2 - bw * 0.1, ry + bh - bh * 0.34, bw * 0.2, bh * 0.34, Color.Black.op(0.5))
                var wy = ry + bh * 0.18
                while (wy < ry + bh - bh * 0.45) {
                    for (wx in listOf(rx + bw * 0.16, rx + bw - bw * 0.34)) rect(wx, wy, bw * 0.18, bh * 0.12, if (night) lit else Color.Black.op(0.4))
                    wy += bh * 0.28
                }
                if (i == 1) {
                    val pole = Path().apply { m(rx + bw - bw * 0.1, ry); l(rx + bw - bw * 0.1, ry - bh * 0.7) }
                    stroke(pole, wall.shade(0.4), max(1.0, bw * 0.04))
                    rect(rx + bw - bw * 0.1, ry - bh * 0.7, bw * 0.3, bh * 0.18, rgb(0.78, 0.16, 0.16))
                }
            }
        }
        // Ground (par 1) with a lit rim and grass strokes.
        val horizon = py(GROUND_V, 1.0)
        rect(0.0, horizon, W, H - horizon, vgrad(listOf(groundColor.lit(0.06), groundColor.shade(0.3)), horizon, H))
        rect(0.0, horizon, W, 2.0, groundColor.lit(0.25))
        val grass = Path()
        for (i in 0 until 90) {
            val gx = px(hash(i * 4.1) * SCENE_W, 1.0); val gy = py(GROUND_V + 0.01 + hash(i * 6.7) * 0.12, 1.0)
            val gh = (0.008 + 0.006 * hash(i.toDouble())) * s
            grass.m(gx, gy); grass.l(gx - gh * 0.3, gy - gh)
            grass.m(gx, gy); grass.l(gx + gh * 0.3, gy - gh)
        }
        stroke(grass, groundColor.lit(0.18), 1.2)
        // Cover (par 1): sandbag walls and grass tufts.
        val bag = rgb(0.72, 0.64, 0.46).mix(sky1, if (night) 0.55 else 0.15)
        for (pr in world.props) {
            val gx = px(pr.x, 1.0); val gy = py(GROUND_V, 1.0)
            if (pr.kind == 0) {
                val cw = 0.05 * s; val ch = 0.045 * s
                val bags = Path()
                for ((bx, by, bwf) in listOf(Triple(-0.5, 0.5, 0.5), Triple(0.0, 0.5, 0.5), Triple(-0.28, 0.0, 0.56))) {
                    bags.rbox(gx + bx * cw, gy - ch + by * ch, cw * bwf, ch * 0.5, ch * 0.2)
                }
                drawPath(bags, bag)
                stroke(bags, Color.Black.op(0.4), 1.2)
            } else {
                val tw = 0.02 * s
                val tuft = Path()
                for (dxf in listOf(-0.35, 0.0, 0.35)) { tuft.m(gx, gy); tuft.l(gx + dxf * tw, gy - tw * (if (dxf == 0.0) 1.1 else 0.8)) }
                stroke(tuft, groundColor.lit(0.2), max(1.5, tw * 0.18), StrokeCap.Round)
            }
        }

        // The soldiers.
        val sh = TARGET_H * s
        world.downed.removeAll { now - it.at > 1.2 }
        for (d in world.downed) {
            val age = now - d.at
            if (age < 0 || age >= 1.2) continue
            val facing = if (d.facing < 0) -1.0 else 1.0
            val tilt = -facing * min(1.0, age / 0.35) * PI / 2
            withAlpha(if (age < 0.6) 1.0 else max(0.0, 1 - (age - 0.6) / 0.6)) {
                soldier(px(d.wx, 1.0), py(d.wy, 1.0), sh, hitPose, facing, false, tilt)
            }
        }
        for (t in world.targets) {
            val fx = px(t.x, 1.0); val fy = py(t.y, 1.0)
            if (t.aiming) {
                // Aim beam: a red line from the scope centre to the soldier, thickening as it charges.
                val prog = max(0.0, 1 - t.aimT / max(0.001, world.aimTime))
                val red = rgb(1.0, 0.25, 0.2)
                line(W / 2, H / 2, fx, fy - sh / 2, red.op(0.14 + 0.2 * prog), (1 + 3 * prog) * 4)
                line(W / 2, H / 2, fx, fy - sh / 2, red.op(0.35 + 0.55 * prog), 1 + 3 * prog)
            }
            val (pose, facing) = world.figure(t)
            soldier(fx, fy, sh, pose, facing, t.aiming)
        }
    }

    /** The scope over the scene: the dark mask, lens shading, rim, danger ring, mil-dot reticle, muzzle bloom, hurt flash. */
    fun DrawScope.overlay(world: SniperWorld, W: Double, H: Double) {
        val s = H / VIEW_H
        val r = min(W, H) * 0.46
        val cx = W / 2; val cy = H / 2
        // The reticle sits at the centre plus the current sway (a shot lands exactly here).
        val rx = cx + world.swayX() * s; val ry = cy + world.swayY() * s
        val mask = Path().apply {
            fillType = PathFillType.EvenOdd
            box(0.0, 0.0, W, H)
            oval(cx - r, cy - r, r * 2, r * 2)
        }
        drawPath(mask, Color.Black.op(0.94))
        circle(cx, cy, r, Brush.radialGradient(0f to Color.Black.op(0.0), 0.55f to Color.Black.op(0.0), 1f to Color.Black.op(0.55),
            center = off(cx, cy), radius = r.f))
        stroke(Path().apply { arc(cx, cy, r * 0.86, deg(200.0), deg(250.0), moveFirst = true) }, Color.White.op(0.18), r * 0.06)
        val ticks = Path()
        for (k in 0 until 36) {
            val a = k / 36.0 * 2 * PI
            val len = if (k % 3 == 0) r * 0.06 else r * 0.03
            ticks.m(cx + cos(a) * (r - 3), cy + sin(a) * (r - 3))
            ticks.l(cx + cos(a) * (r - 3 - len), cy + sin(a) * (r - 3 - len))
        }
        stroke(ticks, Color.White.op(0.3), 1.0)
        circleStroke(cx, cy, r - 5, rgb(0.4, 0.8, 1.0).op(0.16), 3.0)
        // Lens rim, and the danger ring while someone's drawing on you.
        circleStroke(cx, cy, r, Color.Black, 6.0)
        circleStroke(cx, cy, r, Color.White.op(0.22), 2.0)
        if (world.danger) circleStroke(cx, cy, r - 4, rgb(1.0, 0.25, 0.2).op(0.5 + 0.3 * sin(world.animT * 10)), 4.0)
        // Mil-dot crosshair.
        val col = Color.Black.op(0.85)
        val gap = r * 0.09
        val hair = Path().apply {
            m(rx - r, ry); l(rx - gap, ry)
            m(rx + gap, ry); l(rx + r, ry)
            m(rx, ry - r); l(rx, ry - gap)
            m(rx, ry + gap); l(rx, ry + r)
        }
        stroke(hair, col, 1.4)
        for (i in 1..4) {
            val d = gap + i * r * 0.18
            for ((qx, qy) in listOf(rx - d to ry, rx + d to ry, rx to ry - d, rx to ry + d)) circle(qx, qy, 1.6, col)
        }
        circle(rx, ry, 2.0, rgb(1.0, 0.3, 0.25))
        // Muzzle bloom and the hurt flash.
        if (world.muzzle > 0) {
            val k = min(1.0, world.muzzle / 0.09)
            val bloom = rgb(1.0, 0.9, 0.5)
            val br = min(W, H) * 0.5
            circle(cx, cy, br, radial(listOf(bloom.op(0.9 * k), bloom.op(0.0)), cx, cy, br))
        }
        if (world.hurt > 0) rect(0.0, 0.0, W, H, rgb(0.8, 0.05, 0.05).op(world.hurt * 0.38))
    }

    /** Rounds left as brass cartridges; spent ones are dark sockets. */
    fun DrawScope.ammoBelt(w: Double, h: Double, total: Int, loaded: Int) {
        val n = max(1, total)
        val slot = w / n
        val bw = min(slot * 0.62, h * 0.3)
        for (i in 0 until n) {
            val x = slot * (i + 0.5)
            val bx = x - bw / 2; val by = h * 0.36; val bh = h * 0.62
            val tip = Path().apply { m(x - bw / 2, h * 0.38); q(x, -h * 0.1, x + bw / 2, h * 0.38); close() }
            if (i < loaded) {
                drawPath(tip, rgb(0.74, 0.44, 0.24))
                rrect(bx, by, bw, bh, bw * 0.2, hgrad(listOf(rgb(1.0, 0.88, 0.5), rgb(0.8, 0.6, 0.2)), bx, bx + bw))
            } else {
                val all = Path().apply { rbox(bx, by, bw, bh, bw * 0.2); addPath(tip) }
                stroke(all, Color.White.op(0.25), 1.0)
            }
        }
    }

    /** The counter's soldier: a red head under a dark helmet. */
    fun DrawScope.headIcon(w: Double, h: Double) {
        val r = min(w, h) * 0.36
        val cx = w / 2; val cy = h * 0.56
        circle(cx, cy, r, rgb(0.9, 0.24, 0.22))
        val helmet = Path().apply { arc(cx, cy + r * 0.1, r * 1.15, PI, 2 * PI, moveFirst = true); close() }
        drawPath(helmet, rgb(0.3, 0.1, 0.1))
        circleStroke(cx, cy, r, Color.Black.op(0.6), 1.0)
    }

    /** FIRE: a red trigger key (the crosshair icon sits on top). */
    fun DrawScope.fireKey(w: Double, h: Double, lit: Boolean) {
        rrect(0.0, 0.0, w, h, 16.0, vgrad(if (lit) listOf(rgb(1.0, 0.52, 0.46), rgb(0.86, 0.22, 0.2)) else listOf(rgb(0.95, 0.3, 0.28), rgb(0.66, 0.12, 0.12)), 0.0, h))
        val lw = if (lit) 3.0 else 2.0
        rrectStroke(lw / 2, lw / 2, w - lw, h - lw, 16 - lw / 2, Color.White.op(if (lit) 0.95 else 0.5), lw)
    }
}
