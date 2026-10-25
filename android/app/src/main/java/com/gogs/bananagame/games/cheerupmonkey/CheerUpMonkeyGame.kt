package com.gogs.bananagame.games.cheerupmonkey

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale as scaleDraw
import androidx.compose.ui.graphics.vector.VectorPainter
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

/**
 * Brain — Cheer Up Monkey (iOS CheerUpMonkeyGame.swift, id "cheer-up-monkey"): a point-and-tap stage
 * in the style of the Monkey GO Happy series. A sad monkey wants the banana shut in a chest whose lock
 * is a row of coloured symbol wheels. Mini monkeys peek out from behind cover or hide in barrels, pots
 * and crates (tap to open them); each holds up a placard in one wheel's colour with that wheel's
 * symbol, once, then hops into the basket, so the player has to remember it. From level 2 one wheel
 * shows dice pips: count the gems of its colour (some shut in containers, other colours are decoys).
 * Set every wheel, tap the banana, and the monkey jumps for joy; run out of time and it's level 1.
 *
 * The rules are [CMStage]; the view only animates what it reports. The art is in
 * CheerUpMonkeyArt.kt, drawn in points (the canvas is scaled by its density), so every iOS number
 * carries over unchanged.
 */
object CheerUpMonkeyGame {
    val definition = GameDefinition(
        id = "cheer-up-monkey",
        title = "Cheer Up Monkey",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Find the mini monkeys: tap them where they peek out, and tap barrels, pots and crates to look inside.",
                "Each mini monkey shows a symbol in one wheel's colour only once, so remember it; dice wheels mean counting the gems of that colour.",
                "Set every wheel to open the chest, then tap the banana to cheer the monkey up.",
                "If time runs out, you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Tìm các chú khỉ con: chạm vào chỗ chúng ló ra, và chạm thùng, hũ, hộp gỗ để xem bên trong.",
                "Mỗi chú khỉ con chỉ giơ ký hiệu cùng màu với một bánh xoay một lần, hãy nhớ kỹ; bánh có chấm xúc xắc là đếm số ngọc màu đó.",
                "Xoay đúng mọi bánh để mở rương, rồi chạm vào quả chuối để làm chú khỉ vui lên.",
                "Nếu hết giờ, bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> CheerUpMonkeyView(level, onWin, onFail) }
    )
}

// Rules.

/** Wheel and clue colours: each wheel has its own. Clear crystal is never a wheel's colour, only a decoy gem. */
enum class CMHue {
    RED, BLUE, GREEN, PURPLE, ORANGE, YELLOW, PINK, TEAL, CRYSTAL;

    companion object { val wheelHues = listOf(RED, BLUE, GREEN, PURPLE, ORANGE, YELLOW, PINK, TEAL) }
}

/** Scene props. Barrels, pots and crates open; the rest are cover to peek out from. */
enum class CMPropKind {
    BARREL, POT, CRATE, ROCK, BUSH, STUMP, SACK, CORAL;

    val opens: Boolean get() = ordinal <= 2
}

/** What a container holds. */
sealed class CMLoot {
    data object Nothing : CMLoot()
    data class Mini(val m: Int) : CMLoot()                  // that mini monkey
    data class Gems(val hue: CMHue, val n: Int) : CMLoot()  // that many clue gems
    data class Junk(val k: Int) : CMLoot()                  // a sock, a fish bone, an old boot
}

/** Where it stands, in scene fractions. */
class CMProp(val kind: CMPropKind, val x: Double, val y: Double, val scale: Double, var loot: CMLoot = CMLoot.Nothing, var open: Boolean = false)

/** `host`: the prop it peeks out from behind, or sits inside. `side`: −1 left, 1 right, 0 over the top. */
class CMMini(val hue: CMHue, val glyph: Int, val host: Int, val side: Int, val inside: Boolean, var found: Boolean = false)

/** Scene fractions (a gem inside a container sits by it once opened); `host` is the container it's shut in. */
class CMGem(val hue: CMHue, val x: Double, val y: Double, val host: Int?)

/** `count`: pips (count the gems) instead of symbols. `target`: the face that opens the lock (count wheels: pips − 1). */
class CMWheel(val hue: CMHue, val count: Boolean, val target: Int, var shown: Int)

/** SplitMix64, bit-identical to the iOS `CMRandom`. */
class CMRandom(var state: ULong) {
    fun next(): ULong {
        state += 0x9E3779B97F4A7C15uL
        var z = state
        z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9uL
        z = (z xor (z shr 27)) * 0x94D049BB133111EBuL
        return z xor (z shr 31)
    }
    fun unit(): Double = (next() shr 11).toDouble() / (1uL shl 53).toDouble()
    fun int(n: Int): Int = (next() % max(1, n).toULong()).toInt()
    fun <T> shuffle(a: MutableList<T>) {
        if (a.size <= 1) return
        for (i in a.size - 1 downTo 1) { val j = int(i + 1); val t = a[i]; a[i] = a[j]; a[j] = t }
    }
}

class CMParams(
    val wheels: Int,        // code length
    val symbols: Int,       // faces per wheel
    val counts: Int,        // wheels whose clue is a gem count (the rest come from mini monkeys)
    val peeking: Int,       // mini monkeys in plain sight (the rest hide in containers)
    val containers: Int,    // barrels, pots and crates to search
    val hiddenGems: Int,    // clue gems shut in containers
    val decoyGems: Int,     // gems in colours no wheel uses
    val time: Double,
) {
    companion object {
        fun level(level: Int): CMParams {
            val i = min(max(level, 1), 7) - 1
            return CMParams(
                wheels = listOf(4, 5, 6, 6, 7, 7, 8)[i],
                symbols = listOf(4, 4, 5, 5, 6, 6, 6)[i],
                counts = listOf(0, 1, 1, 1, 1, 1, 1)[i],
                peeking = listOf(2, 2, 2, 2, 2, 2, 2)[i],
                containers = listOf(4, 5, 6, 7, 8, 9, 10)[i],
                hiddenGems = listOf(0, 0, 1, 1, 2, 2, 2)[i],
                decoyGems = listOf(0, 1, 1, 2, 2, 3, 3)[i],
                time = listOf(34.0, 36.0, 34.0, 32.0, 30.0, 24.0, 21.0)[i],
            )
        }
    }
}

/** One stage: the props, who hides where, the gems, and the lock. */
class CMStage(val props: List<CMProp>, val minis: List<CMMini>, val gems: List<CMGem>, val wheels: List<CMWheel>, val symbols: Int) {
    var bananaGiven = false

    val unlocked: Boolean get() = wheels.all { it.shown == it.target }
    val found: Int get() = minis.count { it.found }

    /** Tap a closed container: it opens. A mini monkey inside is found at once. */
    fun open(i: Int) {
        if (i !in props.indices || !props[i].kind.opens || props[i].open) return
        props[i].open = true
        (props[i].loot as? CMLoot.Mini)?.let { minis[it.m].found = true }
    }

    /** Tap a mini monkey peeking out. */
    fun collect(m: Int) {
        if (m !in minis.indices || minis[m].inside) return
        minis[m].found = true
    }

    /** Tap a wheel: the next face. */
    fun turn(w: Int) {
        if (w !in wheels.indices || unlocked) return
        wheels[w].shown = (wheels[w].shown + 1) % symbols
    }

    /** Tap the banana once the chest is open. */
    fun giveBanana() {
        if (!unlocked) return
        bananaGiven = true
    }

    class Slot(val x: Double, val y: Double, val s: Double)

    companion object {
        val empty = CMStage(emptyList(), emptyList(), emptyList(), emptyList(), 3)

        /**
         * Spots a prop can stand on: feet in scene fractions and a size, back to front. The middle
         * bottom is the monkey's, the bottom corners hold the basket and the chest.
         */
        val slots = listOf(
            Slot(0.15, 0.36, 0.7), Slot(0.5, 0.35, 0.7), Slot(0.85, 0.36, 0.7),
            Slot(0.13, 0.5, 0.8), Slot(0.34, 0.5, 0.8), Slot(0.66, 0.5, 0.8), Slot(0.87, 0.5, 0.8),
            Slot(0.5, 0.47, 0.75),
            Slot(0.12, 0.64, 0.9), Slot(0.31, 0.65, 0.9), Slot(0.5, 0.6, 0.8), Slot(0.69, 0.65, 0.9), Slot(0.88, 0.64, 0.9),
            Slot(0.17, 0.79, 1.0), Slot(0.83, 0.79, 1.0),
        )

        /** Scenery kinds for a theme (0 cottage, 1 temple, 2 deck, 3 reef): cover to peek out from. */
        fun cover(theme: Int): List<CMPropKind> = when (theme) {
            1 -> listOf(CMPropKind.ROCK, CMPropKind.BUSH)
            2 -> listOf(CMPropKind.SACK, CMPropKind.ROCK)
            3 -> listOf(CMPropKind.CORAL, CMPropKind.ROCK)
            else -> listOf(CMPropKind.BUSH, CMPropKind.ROCK, CMPropKind.STUMP)
        }

        /** Deals a stage. A deal that runs out of room for a counting wheel's gems is thrown away and dealt again. */
        fun make(p: CMParams, theme: Int, seed: ULong): CMStage {
            var s = seed
            while (true) {
                attempt(p, theme, s)?.let { return it }
                s += 0x9E3779B97F4A7C15uL
            }
        }

        fun attempt(p: CMParams, theme: Int, seed: ULong): CMStage? {
            val rng = CMRandom(seed)
            // The lock: k colours, `counts` of them read from gems.
            val hues = CMHue.wheelHues.toMutableList()
            rng.shuffle(hues)
            val k = p.wheels
            val isCount = BooleanArray(k)
            val order = MutableList(k) { it }
            rng.shuffle(order)
            for (i in order.take(p.counts)) isCount[i] = true
            val wheels = mutableListOf<CMWheel>()
            for (i in 0 until k) {
                val target = if (isCount[i]) rng.int(min(p.symbols, 5)) else rng.int(p.symbols)
                wheels.add(CMWheel(hues[i], isCount[i], target, rng.int(p.symbols)))
            }
            if (wheels.all { it.shown == it.target }) wheels[0].shown = (wheels[0].shown + 1) % p.symbols

            // Props: containers and cover on shuffled spots, with a little jitter.
            val miniWheels = (0 until k).filter { !isCount[it] }
            val peeking = min(p.peeking, miniWheels.size)
            val coverCount = peeking + 1
            val spots = MutableList(slots.size) { it }
            rng.shuffle(spots)
            val kinds = cover(theme)
            val props = mutableListOf<CMProp>()
            for ((n, s) in spots.take(p.containers + coverCount).withIndex()) {
                val slot = slots[s]
                val kind = if (n < p.containers) listOf(CMPropKind.BARREL, CMPropKind.POT, CMPropKind.CRATE)[rng.int(3)] else kinds[rng.int(kinds.size)]
                props.add(CMProp(kind, slot.x + (rng.unit() - 0.5) * 0.04, slot.y + (rng.unit() - 0.5) * 0.02, slot.s))
            }
            val containers = MutableList(p.containers) { it }
            rng.shuffle(containers)
            val covers = (p.containers until props.size).toList()

            // Mini monkeys: one per symbol wheel, some peeking from behind cover, the rest shut inside.
            val minis = mutableListOf<CMMini>()
            var nextContainer = 0
            for ((n, w) in miniWheels.withIndex()) {
                val glyph = wheels[w].target
                if (n < peeking) {
                    // Peek over the top or out to a side, but never toward the scene's edge (cut off) and,
                    // in the front row beside the big monkey, only over the top.
                    val host = props[covers[n]]
                    val sides = if (host.y > 0.7) listOf(0) else if (host.x < 0.25) listOf(0, 1) else if (host.x > 0.75) listOf(0, -1) else listOf(0, -1, 1)
                    minis.add(CMMini(wheels[w].hue, glyph, covers[n], sides[rng.int(sides.size)], false))
                } else {
                    val c = containers[nextContainer]; nextContainer++
                    props[c].loot = CMLoot.Mini(minis.size)
                    minis.add(CMMini(wheels[w].hue, glyph, c, 0, true))
                }
            }

            // Gems: each count wheel's colour, as many as its answer; some shut in containers. Decoys in
            // colours no wheel uses lie about too.
            val gems = mutableListOf<CMGem>()
            var hiddenLeft = p.hiddenGems
            val spotsFree = freeGemSpots(props, rng)
            for (w in 0 until k) {
                if (!isCount[w]) continue
                var n = wheels[w].target + 1
                while (n > 0 && hiddenLeft > 0 && nextContainer < containers.size && rng.unit() < 0.7) {
                    val c = containers[nextContainer]; nextContainer++
                    val inside = min(n, 1 + rng.int(2))
                    props[c].loot = CMLoot.Gems(wheels[w].hue, inside)
                    for (g in 0 until inside) {
                        gems.add(CMGem(wheels[w].hue, props[c].x + (g - (inside - 1) / 2.0) * 0.05, props[c].y - 0.005, c))
                    }
                    n -= inside; hiddenLeft--
                }
                repeat(n) {
                    if (spotsFree.isEmpty()) return null
                    val s = spotsFree.removeAt(spotsFree.size - 1)
                    gems.add(CMGem(wheels[w].hue, s.first, s.second, null))
                }
            }
            val decoyHues = CMHue.entries.filter { h -> wheels.none { it.hue == h } }
            repeat(p.decoyGems) {
                if (spotsFree.isEmpty() || decoyHues.isEmpty()) return@repeat
                val s = spotsFree.removeAt(spotsFree.size - 1)
                gems.add(CMGem(decoyHues[rng.int(decoyHues.size)], s.first, s.second, null))
            }
            // The other containers hold junk.
            for (c in containers.subList(nextContainer, containers.size)) props[c].loot = CMLoot.Junk(rng.int(3))
            return CMStage(props, minis, gems, wheels, p.symbols)
        }

        /**
         * Open ground for loose gems: a jittered grid over the scene's floor, away from props, the
         * monkey, the basket and the chest; shuffled. (Swift's float stride: start + i × step.)
         */
        fun freeGemSpots(props: List<CMProp>, rng: CMRandom): MutableList<Pair<Double, Double>> {
            val out = mutableListOf<Pair<Double, Double>>()
            var iy = 0
            while (0.4 + iy * 0.067 <= 0.87) {
                val gy = 0.4 + iy * 0.067
                var ix = 0
                while (0.07 + ix * 0.072 <= 0.94) {
                    val gx = 0.07 + ix * 0.072
                    ix++
                    val x = gx + (rng.unit() - 0.5) * 0.02
                    val y = gy + (rng.unit() - 0.5) * 0.015
                    if (kotlin.math.abs(x - 0.5) < 0.2 && y > 0.6) continue                 // the monkey
                    if (y > 0.8 && (x < 0.3 || x > 0.7)) continue                          // basket and chest
                    if (props.any { kotlin.math.abs(it.x - x) < 0.1 * it.scale + 0.03 && y < it.y + 0.02 && y > it.y - 0.13 * it.scale }) continue
                    out.add(x to y)
                }
                iy++
            }
            rng.shuffle(out)
            return out
        }

        /**
         * The manual clip's small fixed stage: a red mini monkey peeks out from behind a rock and a blue
         * one over a bush, and a barrel and a pot hold only junk. Sized up for the small card.
         */
        fun demo(): CMStage {
            val props = listOf(
                CMProp(CMPropKind.BARREL, 0.3, 0.52, 1.25, CMLoot.Junk(0)),
                CMProp(CMPropKind.POT, 0.7, 0.52, 1.25, CMLoot.Junk(1)),
                CMProp(CMPropKind.ROCK, 0.15, 0.74, 1.4),
                CMProp(CMPropKind.BUSH, 0.85, 0.72, 1.4),
            )
            val minis = listOf(
                CMMini(CMHue.RED, 1, 2, 1, false),
                CMMini(CMHue.BLUE, 2, 3, 0, false),
            )
            val wheels = listOf(
                CMWheel(CMHue.RED, false, 1, 0),
                CMWheel(CMHue.BLUE, false, 2, 0),
            )
            return CMStage(props, minis, emptyList(), wheels, 3)
        }
    }
}

// Layout: where things sit in a scene of a given size (points). The drawing and the hit tests both use these.

internal class CMRect(val x: Double, val y: Double, val w: Double, val h: Double) {
    val maxX get() = x + w
    val maxY get() = y + h
    val midX get() = x + w / 2
    val midY get() = y + h / 2
    fun inset(dx: Double, dy: Double) = CMRect(x + dx, y + dy, w - 2 * dx, h - 2 * dy)
    fun contains(px: Double, py: Double) = px >= x && px < maxX && py >= y && py < maxY
}

internal object CMLayout {
    /** The prop size unit. */
    fun unit(w: Double, h: Double) = min(w, h * 0.62) / 5

    /** Height and width of a prop, as multiples of its scaled unit. */
    fun shape(k: CMPropKind): Pair<Double, Double> = when (k) {
        CMPropKind.BARREL -> 1.0 to 0.78
        CMPropKind.POT -> 0.95 to 0.82
        CMPropKind.CRATE -> 0.82 to 0.96
        CMPropKind.ROCK -> 0.72 to 1.4
        CMPropKind.BUSH -> 0.9 to 1.45
        CMPropKind.STUMP -> 0.62 to 1.05
        CMPropKind.SACK -> 0.86 to 0.9
        CMPropKind.CORAL -> 1.05 to 1.1
    }

    fun propRect(p: CMProp, w: Double, h: Double): CMRect {
        val u = unit(w, h) * p.scale
        val (kh, kw) = shape(p.kind)
        // Kept whole inside the scene, whatever its shape.
        val half = u * kw / 2
        val fx = min(max(p.x * w, half + 4), w - half - 4)
        val fy = p.y * h
        return CMRect(fx - half, fy - u * kh, u * kw, u * kh)
    }

    fun miniR(w: Double, h: Double, scale: Double = 1.0) = unit(w, h) * 0.2 * scale

    /** A peeking mini monkey's head centre: just out from its cover's side, or over its top. */
    fun peekHead(m: CMMini, stage: CMStage, w: Double, h: Double): P {
        val host = stage.props[m.host]
        val r = propRect(host, w, h)
        val mr = miniR(w, h, host.scale)
        return when (m.side) {
            -1 -> P(r.x + mr * 0.15, r.y + r.h * 0.42)
            1 -> P(r.maxX - mr * 0.15, r.y + r.h * 0.42)
            else -> P(r.midX + r.w * 0.12, r.y + mr * 0.25)
        }
    }

    /** The big monkey: head radius and where its feet are. */
    fun monkeyR(w: Double, h: Double) = min(w * 0.135, h * 0.115)
    fun monkeyFeet(w: Double, h: Double) = P(w / 2, h - 4)

    fun chestRect(w: Double, h: Double): CMRect {
        val r = monkeyR(w, h)
        return CMRect(w * 0.83 - r * 0.95, h - 6 - r * 1.25, r * 1.9, r * 1.25)
    }

    fun basketRect(w: Double, h: Double): CMRect {
        val r = monkeyR(w, h)
        return CMRect(w * 0.17 - r * 1.0, h - 6 - r * 1.05, r * 2.0, r * 1.05)
    }

    /** The banana once the chest springs open: up over the chest. */
    fun bananaPoint(w: Double, h: Double): P {
        val c = chestRect(w, h)
        return P(c.midX, c.y - monkeyR(w, h) * 0.55)
    }
}

/** Animation clocks (nowSec): containers opening, mini monkeys found, the chest, the banana, the end. */
internal class CMFx {
    val openedAt = mutableMapOf<Int, Double>()
    val foundAt = mutableMapOf<Int, Double>()
    var unlockedAt: Double? = null
    var givenAt: Double? = null
    var failedAt: Double? = null
}

/** Draws in points: scales the canvas by its density and hands the block the size in points. */
internal inline fun DrawScope.inPoints(crossinline block: DrawScope.(w: Double, h: Double) -> Unit) {
    val u = density
    val w = size.width / u.toDouble(); val h = size.height / u.toDouble()
    scaleDraw(u, u, Offset.Zero) { block(w, h) }
}

/** Static art behind the content, drawn in points once per size into a bitmap. */
private fun Modifier.artBehind(draw: DrawScope.(w: Double, h: Double) -> Unit): Modifier = drawWithCache {
    val bmp = ImageBitmap(size.width.toInt().coerceAtLeast(1), size.height.toInt().coerceAtLeast(1))
    CanvasDrawScope().draw(this, layoutDirection, androidx.compose.ui.graphics.Canvas(bmp), size) { inPoints(draw) }
    onDrawBehind { drawImage(bmp) }
}

// Play state.

private class CMPlay(val params: CMParams, val theme: Int, val isDemo: Boolean) {
    var stage = if (isDemo) CMStage.empty else CMStage.make(params, theme, Random.nextLong().toULong() or 1uL)
    var fx = CMFx()
    var playing by mutableStateOf(true)
    var timeLeft by mutableDoubleStateOf(params.time)
    /** Bumped whenever the stage changes, so the lock panel recomposes. */
    var ver by mutableIntStateOf(0)
    var sceneW = 0.0; var sceneH = 0.0                 // the scene, in points
    // Demo-only: the finger, on a scene point or on a wheel, and when each last rippled.
    var demoPoint: P? = null
    var pointTapAt = -10.0
    var demoWheel by mutableStateOf<Int?>(null)
    var wheelTapAt = -10.0
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    /** A tap on the scene: the banana once the chest is open, a peeking mini monkey, or a closed container (front ones first). */
    fun tap(px: Double, py: Double) {
        if (!playing || stage.bananaGiven) return
        val w = sceneW; val h = sceneH
        if (stage.unlocked) {
            val b = CMLayout.bananaPoint(w, h)
            if (hypot(px - b.x, py - b.y) < max(30.0, CMLayout.monkeyR(w, h) * 0.8)) giveBanana()
            return
        }
        for ((i, m) in stage.minis.withIndex()) {
            if (m.found || m.inside) continue
            val hd = CMLayout.peekHead(m, stage, w, h)
            if (hypot(px - hd.x, py - hd.y) < max(20.0, CMLayout.miniR(w, h, stage.props[m.host].scale) * 1.6)) { collect(i); return }
        }
        for (i in stage.props.indices.sortedByDescending { stage.props[it].y }) {
            val p = stage.props[i]
            if (!p.kind.opens || p.open) continue
            if (CMLayout.propRect(p, w, h).inset(-6.0, -6.0).contains(px, py)) { open(i); return }
        }
    }

    fun collect(m: Int) {
        stage.collect(m)
        fx.foundAt[m] = nowSec()
        SoundManager.tap(); Haptics.tap()
        ver++
    }

    fun open(i: Int) {
        stage.open(i)
        fx.openedAt[i] = nowSec()
        (stage.props[i].loot as? CMLoot.Mini)?.let { fx.foundAt[it.m] = nowSec() }
        SoundManager.tap(); Haptics.tap()
        ver++
    }

    fun turn(w: Int) {
        if (!playing || stage.unlocked) return
        stage.turn(w)
        SoundManager.tap(); Haptics.tap()
        if (stage.unlocked) {
            fx.unlockedAt = nowSec()
            Haptics.success()
        }
        ver++
    }

    /** The run loop wins 1.1 s later, once the monkey has jumped for joy. */
    fun giveBanana() {
        stage.giveBanana()
        fx.givenAt = nowSec()
        SoundManager.tap()
        ver++
    }

    fun win() {
        if (!playing || isDemo) return
        playing = false
        Haptics.tap(); SoundManager.tap()
        onWin()
    }

    fun fail() {
        if (!playing || isDemo) return
        playing = false
        fx.failedAt = nowSec()
        SoundManager.error(); Haptics.warning()
        onFail()
    }

    suspend fun run() {
        val start = nowSec()
        while (currentCoroutineContext().isActive && playing) {
            delay(50)
            val given = fx.givenAt
            if (stage.bananaGiven && given != null) {           // the clock stops once the monkey has its banana
                if (nowSec() - given >= 1.1) win()
                continue
            }
            timeLeft = max(0.0, params.time - (nowSec() - start))
            if (timeLeft <= 0) { fail(); break }
        }
    }

    private fun point(p: P) { if (demoPoint == null) pointTapAt = nowSec(); demoPoint = p }
    private fun wheel(i: Int) { if (demoWheel != i) wheelTapAt = nowSec(); demoWheel = i }

    /**
     * The manual clip: the finger taps the red mini monkey and, once it has hopped into the basket with
     * its sign, turns the red wheel to the triangle; then the blue one, and the blue wheel to the square.
     * The chest springs open and it hands the banana over. Every step is the real stage call.
     */
    suspend fun runDemo() {
        while (sceneW <= 0) delay(20)
        while (currentCoroutineContext().isActive) {
            stage = CMStage.demo(); fx = CMFx(); playing = true
            demoPoint = null; demoWheel = null
            ver++
            delay(700)
            // Spot each mini monkey, then set its wheel from memory: red one turn (circle → triangle), blue two (→ square).
            for ((m, turns) in listOf(0 to 1, 1 to 2)) {
                point(CMLayout.peekHead(stage.minis[m], stage, sceneW, sceneH))
                delay(350)
                pointTapAt = nowSec()
                collect(m)
                delay(1250)
                demoPoint = null
                repeat(turns) {
                    wheel(m)
                    delay(300)
                    wheelTapAt = nowSec()
                    turn(m)
                    delay(300)
                }
                demoWheel = null
            }
            delay(800)
            // Hand over the banana.
            point(CMLayout.bananaPoint(sceneW, sceneH))
            delay(400)
            pointTapAt = nowSec()
            stage.giveBanana(); fx.givenAt = nowSec(); ver++
            delay(400)
            demoPoint = null
            delay(1600)
        }
    }
}

// View.

@Composable
private fun CheerUpMonkeyView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val li = min(max(level, 1), 7) - 1
    // Cottage, temple, deck, reef, then the cottage by night, the temple at sunset, the deck in a storm.
    val theme = listOf(0, 1, 2, 3, 0, 1, 2)[li]
    val night = level >= 5
    val g = remember { CMPlay(CMParams.level(level), theme, isDemo) }
    g.onWin = onWin; g.onFail = onFail
    val tick = rememberFrameLoop()
    val handP = rememberHand()

    LaunchedEffect(Unit) { if (isDemo) g.runDemo() else g.run() }

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp)
            .clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .artBehind { w, h -> with(CMArt) { frame(w, h) } }
    ) {
        if (!isDemo) {
            Canvas(Modifier.fillMaxWidth().padding(horizontal = 36.dp).padding(top = 10.dp, bottom = 8.dp).height(6.dp)) {
                val frac = if (g.params.time > 0) g.timeLeft / g.params.time else 0.0
                val w = size.width.toDouble(); val h = size.height.toDouble()
                rrect(0.0, 0.0, w, h, h / 2, Color.Black.op(0.45))
                val fw = w * max(0.0, frac)
                if (fw > 0) rrect(0.0, 0.0, fw, h, min(h, fw) / 2, if (frac < 0.25) rgb(1.0, 0.3, 0.2) else rgb(1.0, 0.82, 0.1))
                rrectStroke(0.0, 0.0, w, h, h / 2, Color.Black.op(0.6), density.toDouble())
            }
        }
        Scene(g, theme, night, isDemo, tick, handP,
            Modifier.weight(1f).fillMaxWidth().padding(horizontal = if (isDemo) 6.dp else 8.dp).padding(top = if (isDemo) 6.dp else 0.dp))
        LockPanel(g, isDemo, tick, handP,
            Modifier.padding(horizontal = if (isDemo) 6.dp else 8.dp).padding(top = if (isDemo) 6.dp else 8.dp, bottom = if (isDemo) 6.dp else 10.dp))
    }
}

/** The painted stage (cached to a bitmap) with the live scene on top, a ruled outline, and the demo finger. */
@Composable
private fun Scene(g: CMPlay, theme: Int, night: Boolean, isDemo: Boolean, tick: State<Long>, handP: VectorPainter, modifier: Modifier) {
    val corner = if (isDemo) 8.dp else 12.dp
    val u = LocalDensity.current.density.toDouble()
    Canvas(
        modifier
            .drawWithContent {
                drawContent()
                val r = corner.toPx()
                drawRoundRect(Color.Black.op(0.8), cornerRadius = CornerRadius(r, r), style = Stroke(2.dp.toPx()))
            }
            .clip(RoundedCornerShape(corner))
            .onSizeChanged { g.sceneW = it.width / u; g.sceneH = it.height / u }
            .artBehind { w, h -> with(CMArt) { backdrop(w, h, theme, night) } }
            .then(if (isDemo) Modifier else Modifier.tapAt { p -> g.tap(p.x / u, p.y / u) })
    ) {
        tick.value
        val now = nowSec()
        inPoints { w, h -> with(CMArt) { scene(w, h, g.stage, g.fx, now, theme, night) } }
        val p = g.demoPoint
        if (isDemo && p != null) {
            val x = p.x * u; val y = p.y * u
            tapRipple(x, y, now - g.pointTapAt)
            val s = 26 * u
            hand(handP, x + 12 * u - s / 2, y + 15 * u - s / 2, s)
        }
    }
}

/**
 * The lock: one brass-framed wheel per colour on a wooden plank. Past five wheels they go on two rows,
 * every wheel as wide as one in the longer row and the shorter row centred.
 */
@Composable
private fun LockPanel(g: CMPlay, isDemo: Boolean, tick: State<Long>, handP: VectorPainter, modifier: Modifier) {
    g.ver
    val stage = g.stage
    val n = stage.wheels.size
    val gap = if (isDemo) 6.dp else 8.dp
    val twoRows = n > 5
    val rows = if (twoRows) listOf((0 until (n + 1) / 2).toList(), ((n + 1) / 2 until n).toList()) else listOf((0 until n).toList())
    val shape = RoundedCornerShape(if (isDemo) 8.dp else 12.dp)
    val unlocked = stage.unlocked
    val enabled = g.playing && !unlocked
    val height = if (twoRows) 56.dp else if (isDemo) 46.dp else 70.dp
    BoxWithConstraints(
        modifier.fillMaxWidth()
            .drawWithContent {
                drawContent()
                val r = (if (isDemo) 8.dp else 12.dp).toPx()
                drawRoundRect(Color.Black.op(0.75), cornerRadius = CornerRadius(r, r), style = Stroke(2.dp.toPx()))
            }
            .clip(shape)
            .artBehind { w, h -> with(CMArt) { plank(w, h) } }
            .padding(if (isDemo) 6.dp else 10.dp)
    ) {
        val perRow = (n + 1) / 2
        val width: Dp? = if (twoRows) maxOf(24.dp, (maxWidth - gap * (perRow - 1)) / perRow) else null
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(gap), horizontalAlignment = Alignment.CenterHorizontally) {
            for (row in rows) {
                Row(if (width == null) Modifier.fillMaxWidth() else Modifier, horizontalArrangement = Arrangement.spacedBy(gap)) {
                    for (i in row) {
                        val w = stage.wheels[i]
                        val demoHand = isDemo && g.demoWheel == i
                        Wheel(w.hue, w.count, w.shown, unlocked, isDemo, demoHand, enabled, tick, handP, g,
                            (if (width == null) Modifier.weight(1f) else Modifier.width(width)).height(height)) { g.turn(i) }
                    }
                }
            }
        }
    }
}

/** One wheel button: pressed (or the demo's finger on it) it sinks to 93% and brightens a touch. */
@Composable
private fun Wheel(
    hue: CMHue, count: Boolean, face: Int, open: Boolean, compact: Boolean, demoHand: Boolean, enabled: Boolean,
    tick: State<Long>, handP: VectorPainter, g: CMPlay, modifier: Modifier, onTap: () -> Unit,
) {
    val (src, pressed) = rememberPressed()
    val down = pressed.value || demoHand
    Box(modifier.scale(if (down) 0.93f else 1f).clickable(src, null, enabled = enabled, onClick = onTap)) {
        Canvas(Modifier.fillMaxSize()) { inPoints { w, h -> with(CMArt) { wheelFace(w, h, hue, count, face, open, compact, down) } } }
        if (demoHand) {
            Canvas(Modifier.fillMaxSize()) {
                tick.value
                val u = density.toDouble()
                val cx = size.width / 2.0; val cy = size.height / 2.0
                tapRipple(cx, cy, nowSec() - g.wheelTapAt)
                val s = 24 * u
                hand(handP, cx + 11 * u - s / 2, cy + 14 * u - s / 2, s)
            }
        }
    }
}
