package com.gogs.bananagame.games.lawndefense

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.rotateRad
import com.gogs.bananagame.core.*
import com.gogs.bananagame.games.lawndefense.LDPlants.ink
import com.gogs.bananagame.games.lawndefense.LDPlants.leafDark
import com.gogs.bananagame.games.lawndefense.LDPlants.melonBall
import com.gogs.bananagame.games.lawndefense.LDPlants.popcorn
import com.gogs.bananagame.games.lawndefense.LDPlants.snowflake
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** A copy of a swallowed zombie whose legs keep kicking in the flytrap's jaws. */
internal fun LDZombie.kickingCopy(): LDZombie {
    val z = LDZombie(id, kind, row, x, hp, armor, shield, 4.5, born)
    z.hit = hit; z.slowUntil = slowUntil; z.stunUntil = stunUntil; z.hopped = hopped
    return z
}

/** What a world's zombies wear. */
class LDOutfit(val coat: Color, val pants: Color, val shirt: Color?, val tie: Color?, val skin: Color, val hat: Hat, val pattern: Pattern) {
    enum class Hat { HAIR, WRAPS, BANDANA, COWBOY, FUR_HAT, ANTENNA }
    enum class Pattern { NONE, WRAPS, STRIPES, PONCHO, FUR, SUIT }

    companion object {
        fun of(s: LDScene): LDOutfit {
            val skin = rgb(0.58, 0.66, 0.5)
            return when (s) {
                LDScene.BACKYARD, LDScene.ROOFTOP -> LDOutfit(rgb(0.42, 0.3, 0.2), rgb(0.28, 0.22, 0.18), gray(0.92), rgb(0.82, 0.08, 0.08), skin, Hat.HAIR, Pattern.NONE)
                LDScene.DESERT -> LDOutfit(rgb(0.88, 0.82, 0.66), rgb(0.8, 0.73, 0.56), null, null, skin, Hat.WRAPS, Pattern.WRAPS)
                LDScene.PIRATE -> LDOutfit(gray(0.95), rgb(0.2, 0.22, 0.36), null, null, skin, Hat.BANDANA, Pattern.STRIPES)
                LDScene.FRONTIER -> LDOutfit(rgb(0.78, 0.44, 0.18), rgb(0.3, 0.36, 0.52), rgb(0.92, 0.88, 0.8), null, skin, Hat.COWBOY, Pattern.PONCHO)
                LDScene.GLACIER -> LDOutfit(rgb(0.48, 0.34, 0.24), rgb(0.36, 0.36, 0.4), null, null, rgb(0.6, 0.7, 0.62), Hat.FUR_HAT, Pattern.FUR)
                LDScene.FUTURE -> LDOutfit(rgb(0.78, 0.8, 0.88), rgb(0.6, 0.62, 0.72), null, null, rgb(0.62, 0.72, 0.62), Hat.ANTENNA, Pattern.SUIT)
            }
        }
    }
}

/** Draws [block] into a layer composited with a colour multiply (and an optional brightness lift). */
internal inline fun DrawScope.tinted(multiply: Color?, brighten: Double, block: DrawScope.() -> Unit) {
    if (multiply == null && brighten <= 0) { block(); return }
    val m = multiply ?: Color.White
    val add = (brighten * 255).toFloat()
    val cm = ColorMatrix(floatArrayOf(
        m.red, 0f, 0f, 0f, add,
        0f, m.green, 0f, 0f, add,
        0f, 0f, m.blue, 0f, add,
        0f, 0f, 0f, 1f, 0f))
    drawIntoCanvas { c ->
        c.saveLayer(Rect(-20000f, -20000f, 20000f, 20000f), Paint().apply { colorFilter = ColorFilter.colorMatrix(cm) })
        block()
        c.restore()
    }
}

object LDZombies {
    /** A cartoon zombie shambling left, feet at (fx, fy), `h` tall, dressed for its world. */
    fun zombie(d: DrawScope, fx0: Double, fy0: Double, h0: Double, z: LDZombie, t: Double, scene: LDScene, cell: Double) = with(d) {
        var fx = fx0; var fy = fy0
        var h = h0
        if (z.kind == LDZombieKind.IMP) h *= 0.66
        val look = LDOutfit.of(scene)
        if (z.hopped >= 0 && t - z.hopped < 0.45) {
            val p = (t - z.hopped) / 0.45
            fx += (1 - p) * cell
            fy -= sin(p * PI) * h * 0.55
        }
        var clipDesert = false
        val cfx = fx; val cfy = fy
        if (t - z.born < 0.5 && z.x < LDWorld.COLS - 0.2 && z.hopped < 0 && scene == LDScene.DESERT) {
            val p = (t - z.born) / 0.5
            clipDesert = true
            fy += h * (1 - p) * 0.9
        }
        val body: DrawScope.() -> Unit = body@{
            var alpha = 1.0
            var tilt = 0.0
            val died = z.died
            if (died != null) {
                val age = t - died
                if (z.eaten) return@body
                alpha = max(0.0, 1 - max(0.0, age - 0.9) / 0.6)
                if (z.burnt) { withAlpha(alpha) { charred(fx, fy, h, age) }; return@body }
                tilt = min(1.0, age / 0.55) * PI / 2.1
            }
            val stunned = z.died == null && t < z.stunUntil
            if (stunned) {
                val into = 2.5 - (z.stunUntil - t)
                val fall = min(1.0, into / 0.25) * min(1.0, (z.stunUntil - t) / 0.3)
                tilt += fall * PI / 2.05
            }
            val chilled = t < z.slowUntil && z.died == null
            val flashing = t - z.hit < 0.08
            withAlpha(alpha) {
                rotateRad(tilt.toFloat(), Offset(fx.toFloat(), fy.toFloat())) {
                    tinted(if (chilled) rgb(0.72, 0.86, 1.0) else null, if (flashing) 0.25 else 0.0) {
                        figure(this, fx, fy, h, z, t, scene, look, stunned)
                    }
                }
            }
            if (stunned) {
                val into = 2.5 - (z.stunUntil - t)
                val hx = fx + h * 0.75; val hy = fy - h * 0.12
                if (into > 0.2) for (k in 0 until 3) {
                    val a = t * 5 + k * 2.1
                    starShape(hx + cos(a) * h * 0.14, hy - h * 0.12 + sin(a) * h * 0.04, h * 0.035)
                }
            }
        }
        if (clipDesert) {
            val clip = Path().apply { rectD(cfx - h, cfy - h * 2, h * 2, h * 2) }
            clipPath(clip) { body() }
        } else body()
    }

    /** The zombie itself, once it's been placed, tilted and tinted. */
    fun figure(d: DrawScope, fx0: Double, fy0: Double, h: Double, z: LDZombie, t: Double, scene: LDScene, look: LDOutfit, stunned: Boolean) = with(d) {
        val u = density.toDouble()
        val fx = fx0; var fy = fy0
        val pace = if (z.kind == LDZombieKind.RUNNER) 5.5 else if (z.kind == LDZombieKind.IMP) 5.0 else 3.4
        val phase = t * pace * z.speedK + z.id
        val walking = !z.eating && z.died == null && !stunned
        val step = if (walking) sin(phase) else 0.0
        val chomp = if (z.eating) abs(sin(t * 9 + z.id)) else 0.0
        val lw = max(1.2 * u, h * 0.018)
        val springy = z.kind == LDZombieKind.JUMPER && z.hopped < 0
        if (springy && walking) fy -= abs(sin(phase)) * h * 0.06
        val lean = if (z.kind == LDZombieKind.RUNNER) -h * 0.1 else if (z.eating) -h * 0.05 else -h * 0.02
        val hipX = fx + h * 0.02; val hipY = fy - h * (if (springy) 0.48 else 0.42)
        for ((i, s) in listOf(step, -step).withIndex()) {
            val kx = hipX + s * h * 0.06 - h * 0.01; val ky = hipY + h * 0.21
            val ftx = hipX + s * h * (if (z.kind == LDZombieKind.RUNNER) 0.18 else 0.12) - h * 0.03 + i * h * 0.04; val fty = hipY + h * 0.4
            val leg = Path(); leg.m(hipX, hipY); leg.l(kx, ky); leg.l(ftx, fty)
            strokeR(leg, ink, h * 0.085 + lw)
            strokeR(leg, if (i == 0) look.pants.shade(0.2) else look.pants, h * 0.085)
            ellipse(ftx - h * 0.03, fty, h * 0.07, h * 0.035, ink)
            if (z.kind == LDZombieKind.JUMPER) {
                val coil = Path()
                val bx = ftx - h * 0.03
                val loose = z.hopped >= 0 && i == 1
                coil.m(ftx - h * 0.03, fty + h * 0.02)
                for (k in 1..4) {
                    val y = fty + h * 0.02 + k * h * 0.0125 * (if (loose) 1.8 else 1.0)
                    coil.l(bx + (if (k % 2 == 0) -1 else 1) * h * 0.035 + (if (loose) h * 0.03 * k else 0.0), y)
                }
                stroke(coil, gray(0.55), max(u, h * 0.012))
            }
        }
        val shX = hipX + lean; val shY = fy - h * (if (springy) 0.84 else 0.78)
        val torso = polyPath(hipX - h * 0.16, hipY + h * 0.04, shX - h * 0.19, shY, shX + h * 0.19, shY, hipX + h * 0.17, hipY + h * 0.04)
        val bsx = shX + h * 0.08; val bsy = shY + h * 0.05
        val reach = sin(phase * 0.5) * h * 0.02
        val pump = if (z.kind == LDZombieKind.RUNNER && walking) sin(phase) * h * 0.1 else 0.0
        val bhx = shX - h * 0.28 + pump; val bhy = shY + h * 0.12 + reach
        arm(bsx, bsy, bhx, bhy, h, look.coat.shade(0.18), look.skin, lw)
        if (z.kind == LDZombieKind.FLAG) flag(bhx, bhy, h, t, lw)
        drawPath(torso, look.coat)
        clipPath(torso) {
            when (look.pattern) {
                LDOutfit.Pattern.WRAPS -> {
                    val w = Path()
                    for (k in 0 until 7) { val y = shY + h * 0.05 + k * h * 0.055; w.m(hipX - h * 0.25, y + h * 0.02); w.l(hipX + h * 0.25, y - h * 0.015) }
                    stroke(w, rgb(0.62, 0.55, 0.4), max(0.8 * u, h * 0.008))
                }
                LDOutfit.Pattern.STRIPES -> {
                    val st = Path()
                    for (k in 0 until 5) st.rectD(hipX - h * 0.3, shY + h * 0.04 + k * h * 0.075, h * 0.6, h * 0.035)
                    drawPath(st, rgb(0.82, 0.12, 0.12))
                    rect(hipX - h * 0.3, hipY - h * 0.02, h * 0.6, h * 0.05, rgb(0.65, 0.1, 0.3))
                }
                LDOutfit.Pattern.PONCHO -> {
                    val y = shY + h * 0.2
                    val zig = Path(); zig.m(hipX - h * 0.3, y)
                    var x = hipX - h * 0.3; var up = true
                    while (x < hipX + h * 0.3) { x += h * 0.05; zig.l(x, y + (if (up) -h * 0.03 else h * 0.03)); up = !up }
                    stroke(zig, rgb(0.95, 0.85, 0.4), max(u, h * 0.016))
                    at(0.0, h * 0.12) { stroke(zig, rgb(0.2, 0.5, 0.5), max(u, h * 0.016)) }
                }
                LDOutfit.Pattern.FUR -> {
                    rect(hipX - h * 0.3, hipY - h * 0.04, h * 0.6, h * 0.1, rgb(0.92, 0.9, 0.84))
                    rect(hipX - h * 0.06, shY, h * 0.04, h * 0.4, rgb(0.3, 0.2, 0.14))
                }
                LDOutfit.Pattern.SUIT -> {
                    rect(shX - h * 0.03, shY, h * 0.06, h * 0.4, rgb(0.2, 0.9, 0.9))
                    rect(hipX - h * 0.3, hipY - h * 0.02, h * 0.6, h * 0.04, rgb(0.3, 0.32, 0.4))
                }
                LDOutfit.Pattern.NONE -> {}
            }
        }
        stroke(torso, ink, lw)
        look.shirt?.let { drawPath(polyPath(shX - h * 0.08, shY, shX + h * 0.08, shY, shX + h * 0.01, shY + h * 0.2), it) }
        val tieColor = look.tie
        if (tieColor != null && z.kind != LDZombieKind.IMP) {
            drawPath(polyPath(shX - h * 0.02, shY + h * 0.02, shX + h * 0.03, shY + h * 0.02, shX + h * 0.04, shY + h * 0.24,
                shX, shY + h * 0.28, shX - h * 0.03, shY + h * 0.23), tieColor)
        }
        if (look.pattern == LDOutfit.Pattern.FUR) ellipse(shX, shY + h * 0.01, h * 0.2, h * 0.04, rgb(0.92, 0.9, 0.84))
        val fsx = shX - h * 0.12; val fsy = shY + h * 0.05
        if (z.kind == LDZombieKind.SHIELD && z.shield > 0) {
            arm(fsx, fsy, shX - h * 0.3, shY + h * 0.16, h, look.coat, look.skin, lw)
        } else if (z.hp > z.kind.hp / 2) {
            arm(fsx, fsy, shX - h * 0.38 - pump, shY + h * 0.08 - reach - chomp * h * 0.03, h, look.coat, look.skin, lw)
        } else {
            line(fsx, fsy, fsx - h * 0.06, fsy + h * 0.06, ink, h * 0.07 + lw)
            line(fsx, fsy, fsx - h * 0.06, fsy + h * 0.06, look.coat, h * 0.07)
        }
        val hcx = shX - h * 0.05; val hcy = shY - h * 0.13
        val headScale = if (z.kind == LDZombieKind.IMP) 1.3 else 1.0
        zombieHead(hcx, hcy, h * headScale, look.skin, chomp, lw, look.hat == LDOutfit.Hat.WRAPS)
        val worn = if (z.kind.armor > 0) z.armor / z.kind.armor else 0.0
        when {
            z.kind == LDZombieKind.CONE && z.armor > 0 -> cone(hcx, hcy, h, worn, lw)
            z.kind == LDZombieKind.BUCKET && z.armor > 0 -> bucket(hcx, hcy, h, worn, lw, scene)
            z.kind == LDZombieKind.RUNNER && z.armor > 0 -> helmet(hcx, hcy, h, worn, lw)
            else -> hat(look.hat, hcx, hcy, h * headScale, lw, t, z.id)
        }
        if (z.kind == LDZombieKind.SHIELD && z.shield > 0) shield(shX - h * 0.33, shY + h * 0.16, h, z.shield / z.kind.shield, scene, lw)
    }

    fun DrawScope.starShape(cx: Double, cy: Double, r: Double) {
        val s = polyPath((0 until 10).map { i ->
            val a = i / 10.0 * 2 * PI - PI / 2
            val rr = if (i % 2 == 0) r else r * 0.45
            P(cx + cos(a) * rr, cy + sin(a) * rr)
        })
        drawPath(s, rgb(1.0, 0.9, 0.2)); stroke(s, ink, 0.8 * density)
    }

    private fun DrawScope.flag(hx: Double, hy: Double, h: Double, t: Double, lw: Double) {
        line(hx, hy + h * 0.1, hx + h * 0.02, hy - h * 0.62, rgb(0.45, 0.3, 0.15), h * 0.025)
        val tx = hx + h * 0.02; val ty = hy - h * 0.62
        val wave = sin(t * 6) * h * 0.02
        val cloth = polyPath(tx, ty, tx + h * 0.32, ty + h * 0.03 + wave, tx + h * 0.27, ty + h * 0.12 + wave, tx + h * 0.31, ty + h * 0.21 + wave, tx, ty + h * 0.2)
        drawPath(cloth, rgb(0.82, 0.12, 0.1)); stroke(cloth, ink, lw * 0.8)
        val cx = tx + h * 0.14; val cy = ty + h * 0.11 + wave * 0.5
        val palm = Path(); palm.ovalD(cx - h * 0.035, cy - h * 0.01, h * 0.07, h * 0.06)
        for (k in 0 until 4) palm.rrectD(cx - h * 0.035 + k * h * 0.019, cy - h * 0.055, h * 0.013, h * 0.05, 2 * density.toDouble())
        drawPath(palm, rgb(0.62, 0.75, 0.5))
    }

    private fun DrawScope.cone(cx: Double, cy: Double, h: Double, worn: Double, lw: Double) {
        val cone = polyPath(cx - h * 0.15, cy - h * 0.07, cx + h * 0.02 + (if (worn < 0.5) h * 0.05 else 0.0), cy - h * 0.42, cx + h * 0.17, cy - h * 0.06)
        drawPath(cone, hgrad(listOf(rgb(1.0, 0.62, 0.2), rgb(0.9, 0.4, 0.05)), cx - h * 0.15, cx + h * 0.17))
        val st = Path()
        for (y in listOf(0.17, 0.27)) { st.m(cx - h * (0.12 - y * 0.25), cy - h * y); st.l(cx + h * (0.14 - y * 0.3), cy - h * y) }
        stroke(st, Color.White.op(0.85), h * 0.03)
        stroke(cone, ink, lw)
        ellipse(cx + h * 0.01, cy - h * 0.06, h * 0.2, h * 0.035, rgb(0.85, 0.35, 0.05))
    }

    private fun DrawScope.bucket(cx: Double, cy: Double, h: Double, worn: Double, lw: Double, scene: LDScene) {
        val top = cy - h * 0.3
        val pail = polyPath(cx - h * 0.17, cy - h * 0.02, cx - h * 0.13, top, cx + h * 0.13, top, cx + h * 0.17, cy - h * 0.02)
        val colors = if (scene == LDScene.FUTURE) listOf(rgb(0.6, 0.95, 1.0), rgb(0.3, 0.5, 0.7), rgb(0.5, 0.85, 0.95))
            else listOf(gray(0.82), gray(0.55), gray(0.72))
        drawPath(pail, hgrad(colors, cx - h * 0.17, cx + h * 0.17))
        stroke(pail, ink, lw)
        ellipse(cx, top, h * 0.13, h * 0.025, gray(0.45))
        if (worn < 0.5) {
            val dent = Path(); dent.m(cx - h * 0.06, top + h * 0.06); dent.l(cx - h * 0.01, top + h * 0.12); dent.l(cx + h * 0.05, top + h * 0.08)
            stroke(dent, gray(0.3), lw)
        }
    }

    /** A runner's sports helmet with a face guard. */
    private fun DrawScope.helmet(cx: Double, cy: Double, h: Double, worn: Double, lw: Double) {
        val shell = rgb(0.2, 0.3, 0.75)
        val dome = Path()
        dome.arc(cx + h * 0.01, cy - h * 0.02, h * 0.18, PI, 2 * PI, moveFirst = true)
        dome.l(cx + h * 0.19, cy + h * 0.05); dome.l(cx + h * 0.08, cy + h * 0.06); dome.l(cx - h * 0.17, cy - h * 0.02); dome.close()
        drawPath(dome, vgrad(listOf(shell.lit(0.3), shell, shell.shade(0.3)), cy - h * 0.2, cy + h * 0.05))
        stroke(dome, ink, lw)
        val stripe = Path(); stripe.m(cx - h * 0.12, cy - h * 0.14); stripe.q(cx + h * 0.04, cy - h * 0.22, cx + h * 0.16, cy - h * 0.08)
        stroke(stripe, Color.White, h * 0.025)
        val gb = Path()
        gb.m(cx - h * 0.16, cy); gb.l(cx - h * 0.2, cy + h * 0.1)
        gb.m(cx - h * 0.2, cy + h * 0.05); gb.l(cx - h * 0.04, cy + h * 0.07)
        stroke(gb, gray(0.85), max(density.toDouble(), h * 0.014))
        if (worn < 0.5) {
            val cr = Path(); cr.m(cx - h * 0.02, cy - h * 0.18); cr.l(cx + h * 0.03, cy - h * 0.1); cr.l(cx, cy - h * 0.05)
            stroke(cr, ink, lw * 0.8)
        }
    }

    /** The world's shield: a bin lid, a sarcophagus lid, a barrel end, a saloon door, an ice slab or an energy shield. */
    private fun DrawScope.shield(hx: Double, hy: Double, h: Double, health: Double, scene: LDScene, lw: Double) {
        val u = density.toDouble()
        val w = h * 0.2; val ht = h * 0.48
        val x0 = hx - w * 0.75; val y0 = hy - ht * 0.55; val x1 = x0 + w; val y1 = y0 + ht
        val midX = x0 + w / 2; val midY = y0 + ht / 2
        val shape = Path()
        val fill: Brush
        val edge: Color
        when (scene) {
            LDScene.DESERT -> { shape.rrectD(x0, y0, w, ht, w * 0.45); fill = hgrad(listOf(rgb(0.95, 0.78, 0.3), rgb(0.75, 0.55, 0.15)), x0, x1); edge = rgb(0.4, 0.25, 0.05) }
            LDScene.PIRATE -> { shape.ovalD(x0 - w * 0.1, midY - w * 0.9, w * 1.2, w * 1.8); fill = Brush.linearGradient(listOf(rgb(0.6, 0.38, 0.18), rgb(0.6, 0.38, 0.18))); edge = rgb(0.25, 0.14, 0.05) }
            LDScene.FRONTIER -> { shape.rrectD(x0, y0, w, ht, 2 * u); fill = Brush.linearGradient(listOf(rgb(0.62, 0.42, 0.22), rgb(0.62, 0.42, 0.22))); edge = rgb(0.3, 0.18, 0.06) }
            LDScene.GLACIER -> { shape.rrectD(x0, y0, w, ht, w * 0.15); fill = lin(listOf(rgb(0.85, 0.95, 1.0, 0.9), rgb(0.55, 0.78, 0.95, 0.85)), x0, y0, x1, y1); edge = Color.White }
            LDScene.FUTURE -> { shape.rrectD(x0, y0, w, ht, w * 0.3); fill = Brush.linearGradient(listOf(rgb(0.3, 0.95, 1.0, 0.45), rgb(0.3, 0.95, 1.0, 0.45))); edge = rgb(0.4, 1.0, 1.0) }
            LDScene.BACKYARD, LDScene.ROOFTOP -> { shape.ovalD(x0 - w * 0.1, midY - w * 0.95, w * 1.2, w * 1.9); fill = hgrad(listOf(gray(0.85), gray(0.55)), x0, x1); edge = ink }
        }
        drawPath(shape, fill)
        val det = Path()
        when (scene) {
            LDScene.DESERT -> {
                det.ovalD(midX - w * 0.25, y0 + ht * 0.18, w * 0.5, w * 0.5)
                det.m(x0 + w * 0.15, midY + ht * 0.1); det.l(x1 - w * 0.15, midY + ht * 0.1)
                det.m(x0 + w * 0.15, midY + ht * 0.25); det.l(x1 - w * 0.15, midY + ht * 0.25)
            }
            LDScene.PIRATE -> {
                det.m(x0 - w * 0.05, midY - w * 0.4); det.l(x1 + w * 0.05, midY - w * 0.4)
                det.m(x0 - w * 0.05, midY + w * 0.4); det.l(x1 + w * 0.05, midY + w * 0.4)
            }
            LDScene.FRONTIER -> for (k in 1 until 4) { det.m(x0 + 2 * u, y0 + ht * k / 4); det.l(x1 - 2 * u, y0 + ht * k / 4) }
            LDScene.BACKYARD, LDScene.ROOFTOP -> det.ovalD(midX - w * 0.2, midY - w * 0.12, w * 0.4, w * 0.24)
            else -> {}
        }
        stroke(det, edge.op(0.7), max(u, lw * 0.8))
        if (health < 0.67) {
            val cr = Path()
            cr.m(midX, y0 + ht * 0.1); cr.l(midX - w * 0.2, y0 + ht * 0.35); cr.l(midX + w * 0.1, midY)
            if (health < 0.34) { cr.m(x0 + w * 0.1, y1 - ht * 0.2); cr.l(midX, y1 - ht * 0.35) }
            stroke(cr, if (scene == LDScene.GLACIER || scene == LDScene.FUTURE) Color.White else ink, max(u, lw))
        }
        stroke(shape, edge, lw)
    }

    private fun DrawScope.hat(hat: LDOutfit.Hat, cx: Double, cy: Double, h: Double, lw: Double, t: Double, id: Int) {
        val rx = h * 0.15; val ry = h * 0.165
        when (hat) {
            LDOutfit.Hat.HAIR -> {
                val hair = Path()
                for (k in 0 until 3) {
                    val x = cx - rx * 0.2 + k * rx * 0.25
                    hair.m(x, cy - ry * 0.95); hair.q(x - rx * 0.15, cy - ry * 1.25, x + rx * 0.2, cy - ry * 1.3)
                }
                stroke(hair, ink, lw * 0.8)
            }
            LDOutfit.Hat.WRAPS -> {}
            LDOutfit.Hat.BANDANA -> {
                val band = Path(); band.arc(cx, cy, rx * 1.02, deg(190.0), deg(350.0), moveFirst = true); band.close()
                drawPath(band, rgb(0.82, 0.12, 0.12)); stroke(band, ink, lw * 0.8)
                drawPath(polyPath(cx + rx * 0.95, cy - ry * 0.3, cx + rx * 1.5, cy - ry * 0.1 + sin(t * 5 + id) * ry * 0.1, cx + rx * 1.45, cy + ry * 0.2), rgb(0.7, 0.08, 0.08))
                for (k in 0 until 3) oval(cx - rx * 0.6 + k * rx * 0.45, cy - ry * 0.75, rx * 0.14, rx * 0.14, Color.White)
            }
            LDOutfit.Hat.COWBOY -> {
                val by = cy - ry * 0.7
                ellipse(cx, by, rx * 1.75, ry * 0.22, rgb(0.5, 0.32, 0.16))
                ellipseStroke(cx, by, rx * 1.75, ry * 0.22, ink, lw * 0.8)
                val crown = Path()
                crown.m(cx - rx * 0.85, by); crown.l(cx - rx * 0.7, by - ry * 0.85)
                crown.q(cx, by - ry * 0.6, cx + rx * 0.7, by - ry * 0.85); crown.l(cx + rx * 0.85, by); crown.close()
                drawPath(crown, rgb(0.58, 0.38, 0.2)); stroke(crown, ink, lw * 0.8)
                rect(cx - rx * 0.82, by - ry * 0.25, rx * 1.64, ry * 0.18, rgb(0.25, 0.15, 0.08))
            }
            LDOutfit.Hat.FUR_HAT -> {
                ellipse(cx, cy - ry * 0.75, rx * 1.12, ry * 0.55, rgb(0.55, 0.38, 0.24))
                ellipse(cx, cy - ry * 0.5, rx * 1.18, ry * 0.25, rgb(0.92, 0.9, 0.84))
                for (side in listOf(-1.0, 1.0)) ellipse(cx + side * rx * 0.95, cy - ry * 0.05, rx * 0.25, ry * 0.42, rgb(0.55, 0.38, 0.24))
            }
            LDOutfit.Hat.ANTENNA -> {
                rect(cx - rx * 1.02, cy - ry * 0.55, rx * 2.04, ry * 0.22, rgb(0.35, 0.38, 0.48))
                line(cx + rx * 0.3, cy - ry * 0.55, cx + rx * 0.45, cy - ry * 1.5, gray(0.4), max(density.toDouble(), lw * 0.8), StrokeCap.Butt)
                val blink = 0.5 + 0.5 * sin(t * 6 + id)
                circle(cx + rx * 0.45, cy - ry * 1.55, rx * 0.2, rgb(1.0, 0.25 + 0.3 * blink, 0.4))
            }
        }
    }

    private fun DrawScope.arm(ax: Double, ay: Double, hx: Double, hy: Double, h: Double, coat: Color, skin: Color, lw: Double) {
        val ex = (ax + hx) / 2; val ey = (ay + hy) / 2 + h * 0.03
        val sl = Path(); sl.m(ax, ay); sl.l(ex, ey); sl.l(hx, hy)
        strokeR(sl, ink, h * 0.075 + lw); strokeR(sl, coat, h * 0.075)
        ellipse(hx, hy, h * 0.045, h * 0.038, ink)
        ellipse(hx, hy, h * 0.036, h * 0.03, skin)
    }

    private fun DrawScope.zombieHead(cx: Double, cy: Double, h: Double, skin: Color, chomp: Double, lw: Double, wraps: Boolean) {
        val rx = h * 0.15; val ry = h * 0.165
        val head = ovalAt(cx, cy, rx, ry)
        drawPath(head, radial(listOf(skin.lit(0.15), skin, skin.shade(0.2)), cx - rx * 0.3, cy - ry * 0.4, ry * 1.4))
        if (wraps) {
            clipPath(head) {
                drawPath(head, rgb(0.9, 0.85, 0.7))
                val ln = Path()
                for (k in 0 until 6) { val y = cy - ry + k * ry * 0.38; ln.m(cx - rx * 1.2, y + ry * 0.12); ln.l(cx + rx * 1.2, y - ry * 0.08) }
                stroke(ln, rgb(0.62, 0.55, 0.4), max(0.8 * density, lw * 0.7))
            }
        }
        stroke(head, ink, lw)
        val bx = cx - rx * 0.42; val by = cy - ry * 0.2
        circle(bx, by, rx * 0.34, Color.White); circleStroke(bx, by, rx * 0.34, ink, lw * 0.8)
        circle(bx - rx * 0.08, by + rx * 0.04, rx * 0.09, ink)
        if (!wraps) {
            val sx = cx + rx * 0.22; val sy = cy - ry * 0.16
            ellipse(sx, sy, rx * 0.24, rx * 0.2, Color.White); ellipseStroke(sx, sy, rx * 0.24, rx * 0.2, ink, lw * 0.8)
            circle(sx - rx * 0.05, sy + rx * 0.05, rx * 0.07, ink)
            line(sx - rx * 0.26, sy - rx * 0.06, sx + rx * 0.26, sy - rx * 0.1, ink, lw, StrokeCap.Butt)
        }
        val mt = cy + ry * 0.38
        val open = ry * (0.2 + 0.25 * chomp)
        rrect(cx - rx * 0.62, mt, rx * 0.7, open, rx * 0.15, rgb(0.2, 0.08, 0.08))
        rect(cx - rx * 0.5, mt, rx * 0.14, open * 0.4, gray(0.95))
        rect(cx - rx * 0.24, mt, rx * 0.12, open * 0.35, gray(0.95))
        rrectStroke(cx - rx * 0.62, mt, rx * 0.7, open, rx * 0.15, ink, lw * 0.8)
    }

    /** A zombie caught in a blast: a charred silhouette that crumbles to ash. */
    private fun DrawScope.charred(fx: Double, fy: Double, h: Double, age: Double) {
        val crumble = min(1.0, max(0.0, (age - 0.4) / 0.6))
        val ash = gray(0.12)
        val top = fy - h * 0.95 * (1 - crumble * 0.85)
        rrect(fx - h * 0.16, top, h * 0.34, fy - top, h * 0.08, ash)
        if (crumble < 0.5) {
            circle(fx - h * 0.06, top + h * 0.12, h * 0.035, Color.White.op(0.9))
            circle(fx + h * 0.04, top + h * 0.12, h * 0.028, Color.White.op(0.9))
        }
        ellipse(fx, fy, h * 0.25 * (0.5 + crumble), h * 0.05, ash.op(0.7))
    }

    // Small things

    fun pea(d: DrawScope, cx: Double, cy: Double, r: Double, shot: LDShot, t: Double) = with(d) {
        when (shot) {
            LDShot.PEA -> {
                circle(cx, cy, r, radial(listOf(rgb(0.75, 1.0, 0.45), rgb(0.36, 0.78, 0.12)), cx - r * 0.35, cy - r * 0.35, r * 1.3))
                circleStroke(cx, cy, r, leafDark, 1.2 * density)
            }
            LDShot.POPCORN -> popcorn(cx, cy, r * 1.05, t * 8)
            LDShot.FROST -> {
                val k = 0.5 / 1.5
                drawCircle(Brush.radialGradient(0f to rgb(0.8, 0.95, 1.0, 0.6), k.toFloat() to rgb(0.8, 0.95, 1.0, 0.6), 1f to Color.Transparent,
                    center = off(cx, cy), radius = (r * 1.5).f), (r * 1.5).f, off(cx, cy))
                circle(cx, cy, r, radial(listOf(rgb(0.75, 0.85, 1.0), rgb(0.3, 0.36, 0.85)), cx - r * 0.35, cy - r * 0.35, r * 1.3))
                snowflake(cx, cy, r * 0.6)
            }
            LDShot.MELON -> melonBall(cx, cy, r * 1.2)
        }
    }

    fun splat(d: DrawScope, cx: Double, cy: Double, r: Double, age: Double, shot: LDShot) = with(d) {
        if (shot == LDShot.MELON) { melonSplash(cx, cy, r * 1.6, age); return@with }
        val k = 0.6 + age * 2.5
        val color = when (shot) {
            LDShot.PEA -> rgb(0.5, 0.85, 0.2)
            LDShot.POPCORN -> rgb(1.0, 0.95, 0.8)
            LDShot.FROST -> rgb(0.75, 0.9, 1.0)
            LDShot.MELON -> rgb(0.95, 0.3, 0.35)
        }
        withAlpha(max(0.0, 1 - age / 0.35)) {
            for (i in 0 until 6) {
                val a = i / 6.0 * 2 * PI + 0.4
                circle(cx + cos(a) * r * k, cy + sin(a) * r * k * 0.8, r * 0.35, color)
            }
            circle(cx, cy, r * 0.6, color.lit(0.2))
        }
    }

    private fun DrawScope.melonSplash(cx: Double, cy: Double, r: Double, age: Double) {
        val k = 0.6 + age * 3
        withAlpha(max(0.0, 1 - age / 0.35)) {
            for (i in 0 until 8) {
                val a = i / 8.0 * 2 * PI
                circle(cx + cos(a) * r * k, cy + sin(a) * r * k * 0.7, r * 0.32, rgb(0.95, 0.3, 0.35))
            }
            circle(cx, cy, r * 0.7, rgb(0.98, 0.45, 0.45))
            val seeds = Path()
            for (i in 0 until 4) seeds.ovalD(cx + (i - 2) * r * 0.3, cy - r * 0.1 + (i % 2) * r * 0.2, r * 0.14, r * 0.2)
            drawPath(seeds, ink)
        }
    }

    fun sun(d: DrawScope, cx: Double, cy: Double, r: Double, t: Double, fade: Double = 1.0) = with(d) {
        withAlpha(fade) {
            val k = (0.5 / 1.7).toFloat()
            drawCircle(Brush.radialGradient(0f to rgb(1.0, 0.95, 0.4, 0.55), k to rgb(1.0, 0.95, 0.4, 0.55), 1f to rgb(1.0, 0.85, 0.2, 0.0),
                center = off(cx, cy), radius = (r * 1.7).f), (r * 1.7).f, off(cx, cy))
            val rays = Path()
            for (i in 0 until 12) {
                val a = i / 12.0 * 2 * PI + t * 0.7
                rays.m(cx + cos(a - 0.12) * r * 0.85, cy + sin(a - 0.12) * r * 0.85)
                rays.l(cx + cos(a) * r * 1.35, cy + sin(a) * r * 1.35)
                rays.l(cx + cos(a + 0.12) * r * 0.85, cy + sin(a + 0.12) * r * 0.85)
                rays.close()
            }
            drawPath(rays, rgb(1.0, 0.85, 0.15))
            circle(cx, cy, r, radial(listOf(rgb(1.0, 1.0, 0.75), rgb(1.0, 0.85, 0.15), rgb(1.0, 0.62, 0.05)), cx - r * 0.3, cy - r * 0.3, r * 1.3))
        }
    }

    fun mower(d: DrawScope, cx: Double, cy: Double, s: Double) = with(d) {
        val u = density.toDouble()
        val handle = Path(); handle.m(cx - s * 0.2, cy - s * 0.05); handle.l(cx - s * 0.5, cy - s * 0.42); handle.l(cx - s * 0.42, cy - s * 0.48)
        strokeR(handle, ink, s * 0.06)
        val bx = cx - s * 0.28; val by = cy - s * 0.16; val bw = s * 0.56; val bh = s * 0.24
        rrect(bx, by, bw, bh, s * 0.08, vgrad(listOf(rgb(1.0, 0.32, 0.25), rgb(0.7, 0.06, 0.05)), by, by + bh))
        rrectStroke(bx, by, bw, bh, s * 0.08, ink, 1.2 * u)
        rrect(cx - s * 0.1, by - s * 0.12, s * 0.22, s * 0.14, s * 0.03, gray(0.55))
        rrectStroke(cx - s * 0.1, by - s * 0.12, s * 0.22, s * 0.14, s * 0.03, ink, u)
        for (dx in listOf(-0.18, 0.2)) { circle(cx + dx * s, by + bh, s * 0.1, ink); circle(cx + dx * s, by + bh, s * 0.04, gray(0.6)) }
    }
}
