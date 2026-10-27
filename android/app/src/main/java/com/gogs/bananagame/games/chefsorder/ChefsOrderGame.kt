package com.gogs.bananagame.games.chefsorder

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.clickable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.ThumbDown
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Brain — Chef's Order (iOS UncleRogerGame.swift, id "uncle-roger"): a recipe's steps are dealt
 * scrambled; put them back in cooking order with the ▲▼ keys, then SERVE before the timer rings.
 */
object ChefsOrderGame {
    val definition = GameDefinition(
        id = "uncle-roger",
        title = "Chef's Order",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "A recipe's steps are shown scrambled.",
                "Use the ▲▼ arrows on each row to put them in the correct cooking order.",
                "Tap SERVE; a wrong order or a timeout sends you back to level 1.",
            ),
            bulletsVI = listOf(
                "Các bước của một công thức được xáo trộn.",
                "Dùng mũi tên ▲▼ trên mỗi dòng để sắp đúng thứ tự nấu.",
                "Chạm PHỤC VỤ; sai thứ tự hoặc hết giờ sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> ChefsOrderView(level, onWin, onFail) }
    )
}

private class Recipe(val dish: String, val steps: List<String>)

/** A pool of recipes per level (index level-1); step count grows 3 → 7. */
private val recipesByLevel = listOf(
    listOf(
        Recipe("Boiled Egg", listOf("Fill a pot with water", "Boil the egg for 8 minutes", "Peel it and serve")),
        Recipe("Cereal Bowl", listOf("Pour cereal into a bowl", "Add cold milk", "Grab a spoon and eat")),
        Recipe("Buttered Toast", listOf("Toast a slice of bread", "Spread butter on top", "Serve on a plate")),
    ),
    listOf(
        Recipe("Cheese Sandwich", listOf("Take two slices of bread", "Add cheese and ham", "Close the sandwich", "Cut it in half")),
        Recipe("Jam Toast", listOf("Toast two slices of bread", "Spread butter", "Spread the jam", "Stack and serve")),
        Recipe("Ice Cream Sundae", listOf("Scoop ice cream into a glass", "Pour over chocolate sauce", "Add sprinkles", "Top with a cherry")),
    ),
    listOf(
        Recipe("Instant Noodles", listOf("Boil water in a pot", "Add the noodles", "Stir in the seasoning", "Cook for three minutes", "Pour into a bowl")),
        Recipe("Grilled Cheese", listOf("Butter two slices of bread", "Add cheese between them", "Heat a pan", "Grill until golden", "Slice and serve")),
        Recipe("Fruit Smoothie", listOf("Peel and chop the fruit", "Drop it in the blender", "Pour in the milk", "Blend until smooth", "Pour into a glass")),
    ),
    listOf(
        Recipe("Fried Rice", listOf("Cook the rice and let it cool", "Heat oil in a wok", "Fry the beaten egg", "Add the rice and soy sauce", "Toss everything together", "Garnish and serve")),
        Recipe("Omelette", listOf("Crack and beat the eggs", "Season with salt", "Melt butter in the pan", "Pour in the eggs", "Add the filling and fold", "Slide onto a plate")),
    ),
    listOf(
        Recipe("Pancakes", listOf("Mix flour, milk and eggs", "Whisk into a smooth batter", "Heat and grease the pan", "Pour in the batter", "Flip when bubbles form", "Cook the other side", "Stack and add syrup")),
        Recipe("Sushi Rolls", listOf("Cook the sushi rice", "Lay nori on the mat", "Spread the rice", "Add fish and cucumber", "Roll it up tightly", "Slice into pieces", "Serve with soy sauce")),
    ),
    listOf(
        Recipe("Pizza", listOf("Knead the dough", "Let the dough rise", "Roll out the base", "Spread tomato sauce", "Add cheese and toppings", "Bake in the oven", "Slice and serve")),
        Recipe("Beef Stew", listOf("Brown the beef chunks", "Chop the vegetables", "Add stock to the pot", "Toss in the veg", "Simmer for two hours", "Season to taste", "Ladle into bowls")),
    ),
    listOf(
        Recipe("Roast Chicken", listOf("Marinate the chicken", "Preheat the oven", "Season the skin", "Place in the roasting tray", "Roast until golden", "Rest the meat", "Carve and serve")),
        Recipe("Chocolate Cake", listOf("Cream butter and sugar", "Beat in the eggs", "Fold in flour and cocoa", "Pour into the tin", "Bake until risen", "Let it cool", "Spread the frosting")),
    ),
)

private enum class Phase { PLAY, REVEAL, DONE }
private enum class Mood { WATCHING, APPROVE, HAIYAA }

/** The demo's fixes on the reversed Boiled Egg: (row, ▲ -1 / ▼ +1). */
private val demoMoves = listOf(0 to 1, 1 to 1, 1 to -1)

/** iOS ChalkboardSE-Bold → Android's casual hand-lettered face. */
private val Chalk = FontFamily(android.graphics.Typeface.create("casual", android.graphics.Typeface.BOLD))
private val markerRed = rgb(0.78, 0.14, 0.12)

@Composable
private fun ChefsOrderView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val timeLimit = max(11.0, 30.0 - level * 2.5)
    var phase by remember { mutableStateOf(Phase.PLAY) }
    var dish by remember { mutableStateOf("") }
    var correct by remember { mutableStateOf(listOf<String>()) }
    var order by remember { mutableStateOf(listOf<String>()) }
    var thumbUp by remember { mutableStateOf(false) }
    var revealStart by remember { mutableDoubleStateOf(0.0) }
    var timeLeft by remember { mutableDoubleStateOf(timeLimit) }
    var demoPress by remember { mutableStateOf<String?>(null) }

    fun move(index: Int, delta: Int) {
        if (phase != Phase.PLAY) return
        val target = index + delta
        if (target < 0 || target >= order.size) return
        SoundManager.tap(); Haptics.tap()
        order = order.toMutableList().also { val t = it[index]; it[index] = it[target]; it[target] = t }
    }

    fun reveal(win: Boolean) {
        if (phase != Phase.PLAY) return
        thumbUp = win
        if (win) { Haptics.tap(); SoundManager.tap() } else { SoundManager.error(); Haptics.warning() }
        revealStart = nowSec()
        phase = Phase.REVEAL
    }

    fun submit() { if (phase == Phase.PLAY) reveal(order == correct) }

    fun finish() {
        if (phase != Phase.REVEAL) return
        val won = thumbUp
        phase = Phase.DONE
        if (won) onWin() else onFail()
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            val recipe = recipesByLevel[0][0]
            /** Visibly press a control, then fire its real action. */
            suspend fun demoTap(k: String, action: () -> Unit) {
                demoPress = k; delay(300); action(); demoPress = null; delay(200)
            }
            while (isActive) {
                dish = recipe.dish; correct = recipe.steps; order = recipe.steps.reversed()
                thumbUp = false; demoPress = null; timeLeft = timeLimit; phase = Phase.PLAY
                delay(1000)
                for ((row, d) in demoMoves) { demoTap("$row${if (d < 0) "up" else "down"}") { move(row, d) }; delay(250) }
                demoTap("serve") { submit() }
                delay(1500)
                finish()
            }
        } else {
            val pool = recipesByLevel[min(level - 1, recipesByLevel.size - 1)]
            val recipe = pool[ShuffleBag.next("uncle-roger-$level", pool.size)]
            dish = recipe.dish; correct = recipe.steps
            var shuffled = recipe.steps.shuffled()
            while (shuffled == correct) shuffled = recipe.steps.shuffled()
            order = shuffled
            timeLeft = timeLimit
            val start = nowSec()
            while (isActive && phase != Phase.DONE) {
                delay(50)
                when (phase) {
                    Phase.PLAY -> { timeLeft = max(0.0, timeLimit - (nowSec() - start)); if (timeLeft <= 0) reveal(false) }
                    Phase.REVEAL -> if (nowSec() - revealStart >= 0.75) finish()
                    Phase.DONE -> {}
                }
            }
        }
    }

    Box(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp)
            .clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .drawBehind { kitchenBackdrop() }
    ) {
        Column(
            Modifier.fillMaxSize().padding(vertical = if (isDemo) 8.dp else 12.dp),
            verticalArrangement = Arrangement.spacedBy(if (isDemo) 8.dp else 14.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Header: the judge watching, today's dish chalked on the menu board, the kitchen timer.
            Row(Modifier.fillMaxWidth().padding(horizontal = if (isDemo) 12.dp else 16.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Canvas(Modifier.size(if (isDemo) 46.dp else 60.dp, if (isDemo) 52.dp else 68.dp)) { judge(Mood.WATCHING) }
                Box(Modifier.weight(1f).drawBehind { chalkboard() }.padding(horizontal = 14.dp, vertical = if (isDemo) 6.dp else 9.dp),
                    contentAlignment = Alignment.Center) {
                    Text(dish, style = ts(if (isDemo) 20.0 else 26.0, FontWeight.Bold, Color.White.op(0.95), Chalk),
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                if (!isDemo) Canvas(Modifier.size(60.dp, 66.dp)) { kitchenTimer(if (timeLimit > 0) timeLeft / timeLimit else 0.0) }
            }
            // The steps as recipe cards on a cutting board.
            Column(
                Modifier.fillMaxWidth().padding(horizontal = if (isDemo) 10.dp else 14.dp)
                    .drawBehind { cuttingBoard() }
                    .padding(horizontal = if (isDemo) 12.dp else 16.dp, vertical = if (isDemo) 12.dp else 18.dp),
                verticalArrangement = Arrangement.spacedBy(if (isDemo) 6.dp else 8.dp)
            ) {
                order.forEachIndexed { idx, step ->
                    key(step) {
                        StepRow(idx, step, order.size, isDemo, demoPress) { d -> move(idx, d) }
                    }
                }
            }
            ClocheButton(L("SERVE", "PHỤC VỤ"), if (isDemo) 58.dp else 76.dp, lit = demoPress == "serve",
                enabled = phase == Phase.PLAY && !isDemo) { submit() }
        }
        AnimatedVisibility(phase == Phase.REVEAL, enter = fadeIn(tween(150)), exit = fadeOut(tween(150)), modifier = Modifier.fillMaxSize()) {
            ChefReaction(thumbUp)
        }
    }
}

@Composable
private fun StepRow(idx: Int, step: String, count: Int, isDemo: Boolean, demoPress: String?, onMove: (Int) -> Unit) {
    Row(
        Modifier.fillMaxWidth().drawBehind { recipeCard() }.padding(start = 12.dp, end = 8.dp, top = if (isDemo) 5.dp else 8.dp, bottom = if (isDemo) 5.dp else 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Box(Modifier.size(28.dp).border(2.dp, markerRed, CircleShape), contentAlignment = Alignment.Center) {
            Text("${idx + 1}", style = ts(17.0, FontWeight.Bold, markerRed, Chalk))
        }
        // Long steps wrap rather than shrink, so every row keeps the same font size.
        Text(step, style = ts(16.0, FontWeight.SemiBold, rgb(0.2, 0.16, 0.13)), modifier = Modifier.weight(1f))
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            SteelKey(true, demoPress == "${idx}up", enabled = !isDemo, Modifier.alpha(if (idx == 0) 0.25f else 1f)) { onMove(-1) }
            SteelKey(false, demoPress == "${idx}down", enabled = !isDemo, Modifier.alpha(if (idx == count - 1) 0.25f else 1f)) { onMove(1) }
        }
    }
}

/** Small brushed-steel keys for moving a card up or down. */
@Composable
private fun SteelKey(up: Boolean, lit: Boolean, enabled: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val src = remember { MutableInteractionSource() }
    val pressed by src.collectIsPressedAsState()
    val down = pressed || lit
    val shape = RoundedCornerShape(7.dp)
    Box(
        modifier.scale(if (down) 0.9f else 1f).size(36.dp, 22.dp)
            .background(androidx.compose.ui.graphics.Brush.verticalGradient(if (down) listOf(gray(0.7), gray(0.85)) else listOf(gray(0.95), gray(0.74))), shape)
            .border(if (down) 2.dp else 1.dp, if (down) markerRed else gray(0.5), shape)
            .clickable(src, null, enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Icon(if (up) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown, null,
            tint = if (down) markerRed else gray(0.25), modifier = Modifier.size(20.dp))
    }
}

/** SERVE: a silver cloche on its plate. */
@Composable
private fun ClocheButton(title: String, height: Dp, lit: Boolean, enabled: Boolean, onClick: () -> Unit) {
    val src = remember { MutableInteractionSource() }
    val pressed by src.collectIsPressedAsState()
    val sc by animateFloatAsState(if (pressed || lit) 0.92f else 1f, tween(80), label = "cloche")
    Box(Modifier.size(height * 2.6f, height).scale(sc).clickable(src, null, enabled = enabled, onClick = onClick), contentAlignment = Alignment.BottomCenter) {
        Canvas(Modifier.fillMaxSize()) { cloche() }
        Text(title, style = ts(height.value * 0.24, FontWeight.Black, rgb(0.22, 0.22, 0.26), spacing = 2.0),
            modifier = Modifier.padding(bottom = height * 0.3f))
        if (lit) Box(Modifier.fillMaxSize().padding(horizontal = 8.dp, vertical = 4.dp).border(3.dp, Color.White, RoundedCornerShape(50)))
    }
}

/** The verdict: a big thumbs up, or a thumbs down and a gasp. */
@Composable
private fun ChefReaction(thumbUp: Boolean) {
    Box(Modifier.fillMaxSize().background(Color.Black.op(0.62)), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.size(170.dp, 190.dp)) {
                Canvas(Modifier.fillMaxSize()) { judge(if (thumbUp) Mood.APPROVE else Mood.HAIYAA) }
                val thumb = if (thumbUp) Icons.Filled.ThumbUp else Icons.Filled.ThumbDown
                val align = if (thumbUp) Alignment.TopEnd else Alignment.BottomEnd
                val dy = if (thumbUp) (-6).dp else 10.dp
                Icon(thumb, null, tint = Color.Black.op(0.45), modifier = Modifier.align(align).offset(20.dp, dy + 3.dp).size(54.dp))
                Icon(thumb, null, tint = rgb(1.0, 0.84, 0.3), modifier = Modifier.align(align).offset(18.dp, dy).size(54.dp))
            }
            Text(
                if (thumbUp) L("Chef approves", "Đầu bếp tán thành") else L("Oh no… wrong order", "Ôi không… sai thứ tự"),
                style = ts(18.0, FontWeight.ExtraBold, if (thumbUp) rgb(0.55, 1.0, 0.55) else rgb(1.0, 0.5, 0.45)),
                modifier = Modifier.background(Color.Black.op(0.55), RoundedCornerShape(50)).padding(horizontal = 16.dp, vertical = 8.dp)
            )
        }
    }
}

// Kitchen art (iOS KitchenArt and friends).

private fun hash(n: Double): Double { val v = sin(n * 12.9898) * 43758.5453; return v - kotlin.math.floor(v) }

/** The banana chef: an upright banana with a mustache and brows that tell you what he thinks. */
private fun DrawScope.judge(mood: Mood) {
    val w = size.width.toDouble(); val h = size.height.toDouble()
    val s = min(w, h) * 0.4
    val cx = w / 2; val cy = h / 2 + h * 0.05
    FruitArt.draw(this, FruitKind.BANANA, cx, cy, s, -62.0)
    val ink = rgb(0.2, 0.12, 0.05)
    val fx = cx + s * 0.02; val fy = cy - s * 0.05
    for (dx in listOf(-0.22, 0.2)) {
        val ex = fx + dx * s; val ey = fy - s * 0.12
        oval(ex - s * 0.1, ey - s * 0.12, s * 0.2, s * 0.24, Color.White)
        oval(ex - s * 0.05, ey - s * 0.06, s * 0.1, s * 0.13, ink)
    }
    val brows = Path()
    val by = fy - s * 0.32
    when (mood) {
        Mood.WATCHING -> {
            brows.m(fx - s * 0.33, by); brows.l(fx - s * 0.1, by - s * 0.02)
            brows.m(fx + s * 0.09, by - s * 0.02); brows.l(fx + s * 0.31, by)
        }
        Mood.APPROVE -> {
            brows.m(fx - s * 0.33, by + s * 0.02); brows.q(fx - s * 0.22, by - s * 0.1, fx - s * 0.1, by - s * 0.02)
            brows.m(fx + s * 0.09, by - s * 0.02); brows.q(fx + s * 0.2, by - s * 0.1, fx + s * 0.31, by + s * 0.02)
        }
        Mood.HAIYAA -> {
            brows.m(fx - s * 0.33, by - s * 0.06); brows.l(fx - s * 0.08, by + s * 0.06)
            brows.m(fx + s * 0.07, by + s * 0.06); brows.l(fx + s * 0.31, by - s * 0.06)
        }
    }
    strokePath(brows, ink, max(2.0 * density, s * 0.07))
    val my = fy + s * 0.13
    val stache = Path()
    stache.m(fx, my)
    stache.q(fx - s * 0.16, my - s * 0.08, fx - s * 0.3, my + s * 0.06)
    stache.q(fx - s * 0.14, my + s * 0.1, fx, my + s * 0.07)
    stache.q(fx + s * 0.14, my + s * 0.1, fx + s * 0.3, my + s * 0.06)
    stache.q(fx + s * 0.16, my - s * 0.08, fx, my)
    fillPath(stache, ink)
    val mY = my + s * 0.2
    val lip = rgb(0.55, 0.12, 0.1)
    when (mood) {
        Mood.WATCHING -> line(fx - s * 0.09, mY, fx + s * 0.09, mY, ink, max(1.5 * density, s * 0.05))
        Mood.APPROVE -> {
            val mouth = Path(); mouth.m(fx - s * 0.14, mY - s * 0.02); mouth.q(fx, mY + s * 0.16, fx + s * 0.14, mY - s * 0.02); mouth.close()
            fillPath(mouth, lip)
        }
        Mood.HAIYAA -> oval(fx - s * 0.09, mY - s * 0.05, s * 0.18, s * 0.16, lip)
    }
}

/** White subway tiles over a butcher-block counter. */
private fun DrawScope.kitchenBackdrop() {
    val u = density.toDouble()
    val W = size.width.toDouble(); val H = size.height.toDouble()
    val counterY = H * 0.3
    rect(0.0, 0.0, W, counterY, rgb(0.93, 0.94, 0.93))
    val grout = Path()
    val th = 16 * u; val tw = 34 * u
    var y = 0.0; var row = 0
    while (y < counterY) {
        grout.m(0.0, y); grout.l(W, y)
        var x = if (row % 2 == 0) 0.0 else tw / 2
        while (x < W) { grout.m(x, y); grout.l(x, min(counterY, y + th)); x += tw }
        y += th; row++
    }
    strokePath(grout, rgb(0.72, 0.74, 0.74), 1.2 * u, androidx.compose.ui.graphics.StrokeCap.Butt)
    rect(0.0, 0.0, W, counterY, vgrad(listOf(Color.Transparent, Color.Black.op(0.12)), 0.0, counterY))
    rect(0.0, counterY, W, H - counterY, vgrad(listOf(rgb(0.72, 0.5, 0.3), rgb(0.52, 0.33, 0.18)), counterY, H))
    val strips = Path()
    var x = 0.0; var k = 0
    while (x < W) { x += (18 + hash(k.toDouble()) * 16) * u; strips.m(x, counterY); strips.l(x, H); k++ }
    strokePath(strips, rgb(0.38, 0.22, 0.1, 0.35), u, androidx.compose.ui.graphics.StrokeCap.Butt)
    rect(0.0, counterY, W, 5 * u, rgb(0.86, 0.66, 0.44))
    rect(0.0, counterY + 5 * u, W, 6 * u, vgrad(listOf(Color.Black.op(0.3), Color.Transparent), counterY + 5 * u, counterY + 11 * u))
}

/** A bamboo-coloured cutting board the recipe cards sit on. */
private fun DrawScope.cuttingBoard() {
    val u = density.toDouble()
    val x = 2 * u; val y = 2 * u; val w = size.width - 4 * u; val h = size.height - 4 * u
    val r = 18 * u
    blurRRect(x, y + 5 * u, w, h, r, Color.Black.op(0.4), 6 * u)
    rrect(x, y, w, h, r, hgrad(listOf(rgb(0.93, 0.78, 0.52), rgb(0.84, 0.66, 0.4)), x, x + w))
    val board = Path().apply { addRoundRect(androidx.compose.ui.geometry.RoundRect(x.f, y.f, (x + w).f, (y + h).f, r.f, r.f)) }
    clipPath(board) {
        val strips = Path()
        var sx = x + 22 * u
        while (sx < x + w) { strips.m(sx, y); strips.l(sx, y + h); sx += 22 * u }
        strokePath(strips, rgb(0.62, 0.44, 0.22, 0.3), u, androidx.compose.ui.graphics.StrokeCap.Butt)
    }
    rrectStroke(x, y, w, h, r, rgb(0.55, 0.38, 0.2), 2 * u)
}

/** A recipe index card: cream paper, a red margin rule, faint blue lines. */
private fun DrawScope.recipeCard() {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    rrect(u, 2 * u, w, h, 6 * u, Color.Black.op(0.18))
    rrect(0.0, 0.0, w, h, 6 * u, rgb(1.0, 0.98, 0.93))
    val lines = Path()
    var y = 14 * u
    while (y < h - 4 * u) { lines.m(6 * u, y); lines.l(w - 6 * u, y); y += 14 * u }
    strokePath(lines, rgb(0.55, 0.7, 0.9, 0.3), 0.8 * u, androidx.compose.ui.graphics.StrokeCap.Butt)
    rect(46 * u, 0.0, 1.4 * u, h, rgb(0.9, 0.4, 0.4, 0.5))
}

/** The menu board the dish is chalked on. */
private fun DrawScope.chalkboard() {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    rrect(0.0, 0.0, w, h, 8 * u, rgb(0.5, 0.33, 0.17))
    val sx = 5 * u; val sy = 5 * u; val sw = w - 10 * u; val sh = h - 10 * u
    rrect(sx, sy, sw, sh, 4 * u, vgrad(listOf(rgb(0.2, 0.26, 0.23), rgb(0.14, 0.18, 0.16)), sy, sy + sh))
    for (k in 0 until 5) {
        val x = sx + hash(k * 3.1) * sw
        oval(x, sy + hash(k * 5.3) * sh * 0.6, 30 * u, 8 * u, Color.White.op(0.05))
    }
}

/** The level clock as a twist kitchen timer: the red wedge is the time that's left. */
private fun DrawScope.kitchenTimer(frac: Double) {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    val d = min(w, h - 6 * u)
    val cx = w / 2; val cy = h - d / 2
    val r = d / 2
    rrect(cx - 5 * u, cy - r - 7 * u, 10 * u, 9 * u, 3 * u, gray(0.75))
    circle(cx, cy + 2 * u, r, Color.Black.op(0.3))
    circle(cx, cy, r, Color.White)
    val f = clamp(frac, 0.0, 1.0)
    if (f > 0) {
        val wedge = Path()
        wedge.m(cx, cy)
        wedge.arc(cx, cy, r * 0.82, deg(-90.0), deg(-90.0 + 360 * f))
        wedge.close()
        fillPath(wedge, if (frac < 0.3) rgb(0.9, 0.15, 0.12) else rgb(0.95, 0.35, 0.25))
    }
    val ticks = Path()
    for (k in 0 until 12) {
        val a = k / 12.0 * 2 * PI
        ticks.m(cx + sin(a) * r * 0.86, cy - cos(a) * r * 0.86)
        ticks.l(cx + sin(a) * r * 0.97, cy - cos(a) * r * 0.97)
    }
    strokePath(ticks, gray(0.3), 1.2 * u, androidx.compose.ui.graphics.StrokeCap.Butt)
    circleStroke(cx, cy, r, gray(0.55), 2 * u)
    circle(cx, cy, r * 0.22, gray(0.85))
    circleStroke(cx, cy, r * 0.22, gray(0.55), u)
}

/** The silver cloche on its plate (SERVE). */
private fun DrawScope.cloche() {
    val u = density.toDouble()
    val w = size.width.toDouble(); val h = size.height.toDouble()
    val px = w * 0.04; val py = h * 0.74; val pw = w * 0.92; val ph = h * 0.22
    oval(px, py + 3 * u, pw, ph, Color.Black.op(0.3))
    drawOval(vgrad(listOf(gray(0.98), gray(0.78)), py, py + ph), off(px, py), sz(pw, ph))
    val dome = Path()
    dome.m(w * 0.14, h * 0.8)
    dome.c(w * 0.16, h * 0.06, w * 0.84, h * 0.06, w * 0.86, h * 0.8)
    dome.close()
    drawPath(dome, lin(listOf(gray(0.97), gray(0.72), gray(0.55)), w * 0.3, h * 0.15, w * 0.75, h * 0.8))
    strokePath(dome, gray(0.45), 1.2 * u)
    val shine = Path(); shine.m(w * 0.28, h * 0.62); shine.q(w * 0.28, h * 0.34, w * 0.42, h * 0.26)
    strokePath(shine, Color.White.op(0.9), 3 * u)
    oval(w * 0.46, h * 0.12, w * 0.08, h * 0.12, gray(0.65))
    rect(w * 0.12, h * 0.78, w * 0.76, h * 0.05, gray(0.6))
}
