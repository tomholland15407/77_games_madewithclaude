package com.gogs.bananagame.games.critterduel

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Circle
import androidx.compose.material.icons.filled.Eco
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/** Brain — Critter Duel (iOS CritterDuelGame.swift): a turn-based fruit-critter battle. */
object CritterDuelGame {
    val definition = GameDefinition(
        id = "critter-duel",
        title = "Critter Duel",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Tap a move to attack; the rival answers every turn, and the faster critter goes first.",
                "Grass beats water, water beats fire, fire beats grass, electric beats water: the right type does double damage.",
                "The banana Snack heals Banano, but only twice. Knock out every rival to win.",
                "If Banano faints or time runs out, you're back to level 1.",
            ),
            bulletsVI = listOf(
                "Chạm một chiêu để tấn công; đối thủ đánh trả mỗi lượt, con nào nhanh hơn ra đòn trước.",
                "Cỏ thắng nước, nước thắng lửa, lửa thắng cỏ, điện thắng nước: đúng hệ gây sát thương gấp đôi.",
                "Món Ăn Vặt chuối hồi máu cho Banano, nhưng chỉ hai lần. Hạ hết đối thủ để thắng.",
                "Nếu Banano gục hoặc hết giờ, bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> CritterDuelView(level, onWin, onFail) }
    )

    /** The demo's fixed seed (iOS 0xD0E1): two Leaf Cuts knock out the level-1 Coconutty. */
    const val DEMO_SEED: ULong = 0xD0E1uL
}

private fun typeIcon(t: CDType): ImageVector = when (t) {
    CDType.GRASS -> Icons.Filled.Eco
    CDType.FIRE -> Icons.Filled.LocalFireDepartment
    CDType.WATER -> Icons.Filled.WaterDrop
    CDType.ELECTRIC -> Icons.Filled.Bolt
    CDType.NORMAL -> Icons.Filled.Circle
}

private class DuelState(val level: Int, val isDemo: Boolean) {
    var battle by mutableStateOf(CDBattle.level(1, 1uL))
    var ver by mutableIntStateOf(0)          // bumped whenever the battle's plain fields change
    var playing = true
    var busy by mutableStateOf(false)
    var timeLeft by mutableDoubleStateOf(CDBattle.timeLimit(level))
    var shownFoe by mutableIntStateOf(0)
    var message by mutableStateOf("")
    val fx = CDFx()
    val youHP = Animatable(0f)
    val foeHP = Animatable(0f)
    var shakeT0 = -10.0
    var onWin: () -> Unit = {}
    var onFail: () -> Unit = {}

    val timeLimit = CDBattle.timeLimit(level)
    val foeOnScreen: CDCritter? get() = if (shownFoe < battle.foes.size) battle.foes[shownFoe] else battle.foes.lastOrNull()
    val prompt get() = L("What will ${battle.you.name} do?", "${battle.you.name} sẽ làm gì?")

    suspend fun start(seed: ULong) {
        battle = CDBattle.level(if (isDemo) 1 else level, seed)
        youHP.snapTo(battle.you.hp.toFloat())
        foeHP.snapTo(battle.foes[0].hp.toFloat())
        shownFoe = 0
        fx.enter(nowSec())
        playing = true; busy = false
        message = L("${battle.foes[0].name} appears!", "${battle.foes[0].name} xuất hiện!")
        ver++
    }

    /** Show a resolved turn one beat at a time, then hand control back (or end the level). */
    suspend fun playBack(events: List<CDEvent>, scope: CoroutineScope) {
        for (e in events) {
            if (!playing && !isDemo) return
            when (e) {
                is CDEvent.Use -> {
                    val m = CDMoves.all[e.move]
                    val who = if (e.foe) foeOnScreen?.name ?: "" else battle.you.name
                    message = if (m.heals) L("$who eats a banana!", "$who ăn chuối!") else L("$who used ${m.en}!", "$who dùng ${m.vi}!")
                    fx.use(e.foe, m.type, m.heals, nowSec())
                    delay(750)
                }
                is CDEvent.Hit -> {
                    fx.hit(e.foe, e.mult, e.crit, nowSec())
                    val a = if (e.foe) foeHP else youHP
                    val target = max(0f, a.targetValue - e.amount)
                    scope.launch { a.animateTo(target, tween(450, easing = LinearEasing)) }
                    if (e.mult > 1 || e.crit) shakeT0 = nowSec()
                    if (e.foe) SoundManager.tap() else { SoundManager.error(); Haptics.warning() }
                    delay(600)
                }
                is CDEvent.Miss -> { fx.miss(e.foe, nowSec()); delay(550) }
                is CDEvent.Heal -> {
                    val a = if (e.foe) foeHP else youHP
                    val target = a.targetValue + e.amount
                    scope.launch { a.animateTo(target, tween(450, easing = LinearEasing)) }
                    delay(550)
                }
                is CDEvent.Faint -> {
                    fx.faint(e.foe, nowSec())
                    val who = if (e.foe) foeOnScreen?.name ?: "" else battle.you.name
                    message = L("$who fainted!", "$who gục ngã!")
                    ver++
                    delay(900)
                }
                is CDEvent.Send -> {
                    shownFoe = e.index
                    foeHP.snapTo(battle.foes[e.index].hp.toFloat())
                    fx.enter(nowSec())
                    message = L("${battle.foes[e.index].name} appears!", "${battle.foes[e.index].name} xuất hiện!")
                    ver++
                    delay(1100)
                }
            }
        }
        if (battle.won) { win(); return }
        if (battle.lost) { fail(); return }
        message = prompt
        busy = false
    }

    fun win() {
        if (!playing) return
        if (isDemo) { busy = false; return }
        playing = false
        Haptics.tap(); SoundManager.tap()
        onWin()
    }

    fun fail() {
        if (!playing) return
        if (isDemo) { busy = false; return }
        playing = false
        SoundManager.error(); Haptics.warning()
        onFail()
    }
}

@Composable
private fun CritterDuelView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val st = remember { DuelState(level, isDemo) }
    st.onWin = onWin; st.onFail = onFail
    val scope = rememberCoroutineScope()
    var demoPress by remember { mutableStateOf<Int?>(null) }
    var demoTapT0 by remember { mutableDoubleStateOf(-10.0) }
    val tick = rememberFrameLoop()

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (isActive) {
                st.start(CritterDuelGame.DEMO_SEED)
                delay(1200)
                st.message = st.prompt
                while (isActive && !st.battle.won && !st.battle.lost) {
                    delay(700)
                    demoPress = 0; demoTapT0 = nowSec()
                    delay(350)
                    demoPress = null
                    val events = st.battle.turn(0)
                    st.ver++
                    st.busy = true
                    st.playBack(events, scope)
                }
                delay(1400)
            }
        } else {
            st.start(Random.nextLong().toULong() or 1uL)
            scope.launch { delay(1100); if (!st.busy && st.playing) st.message = st.prompt }
            val start = nowSec()
            while (isActive && st.playing) {
                delay(50)
                st.timeLeft = max(0.0, st.timeLimit - (nowSec() - start))
                if (st.timeLeft <= 0) { st.fail(); break }
            }
        }
    }

    fun choose(i: Int) {
        if (!st.playing || st.busy) return
        val events = st.battle.turn(i)
        if (events.isEmpty()) return
        st.ver++
        st.busy = true
        SoundManager.tap(); Haptics.tap()
        scope.launch { st.playBack(events, scope) }
    }

    Column(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp)
            .graphicsLayer {
                tick.value
                val t = nowSec() - st.shakeT0
                if (t in 0.0..0.35) {
                    val k = sin(t / 0.35 * PI * 3)
                    translationX = (5 * density * k).toFloat(); translationY = (5 * 0.6 * density * k).toFloat()
                }
            }
            .clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
    ) {
        Field(st, level, isDemo, tick, Modifier.fillMaxWidth().weight(1f))
        Column(
            Modifier.fillMaxWidth().drawBehind { CDArt.panel(this) }
                .padding(horizontal = if (isDemo) 8.dp else 12.dp).padding(top = if (isDemo) 6.dp else 10.dp, bottom = if (isDemo) 8.dp else 12.dp),
            verticalArrangement = Arrangement.spacedBy(if (isDemo) 5.dp else 8.dp)
        ) {
            MessageBox(st.message, isDemo)
            if (!isDemo) {
                val frac = st.timeLeft / st.timeLimit
                TimeBar(frac, Modifier.fillMaxWidth().padding(horizontal = 30.dp).height(5.dp),
                    fill = if (frac < 0.25) rgb(1.0, 0.32, 0.25) else gray(0.85), track = Color.White.op(0.15))
            }
            st.ver
            val moves = st.battle.you.moves
            for (row in 0 until 2) {
                Row(horizontalArrangement = Arrangement.spacedBy(if (isDemo) 6.dp else 8.dp)) {
                    for (col in 0 until 2) {
                        val i = row * 2 + col
                        Box(Modifier.weight(1f).height(if (isDemo) 40.dp else 58.dp)) {
                            if (i < moves.size) {
                                val m = CDMoves.all[moves[i]]
                                val left = st.battle.you.pp[i]
                                val usable = left > 0 && st.playing
                                MoveButton(m, if (m.heals) left else null, isDemo, isDemo && demoPress == i,
                                    dim = !usable || (st.busy && !isDemo), enabled = usable && !st.busy && !isDemo,
                                    tapT0 = if (isDemo && i == 0) demoTapT0 else -10.0,
                                    showHand = isDemo && demoPress == i, tick = tick) { choose(i) }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Field(st: DuelState, level: Int, isDemo: Boolean, tick: State<Long>, modifier: Modifier) {
    val tm = rememberTextMeasurer()
    Box(modifier) {
        Canvas(Modifier.fillMaxSize()) { CDArt.field(this, level) }
        Canvas(Modifier.fillMaxSize()) {
            tick.value
            CDArt.scene(this, tm, st.battle.you, st.foeOnScreen, st.fx, nowSec())
        }
        st.ver
        val foe = st.foeOnScreen
        if (foe != null) {
            val party = (0 until st.battle.foes.size).map { i ->
                i < st.shownFoe || (i == st.shownFoe && st.battle.foes[i].hp <= 0 && st.fx.foeFainted)
            }
            HPBox(foe.name, foe.level, foe.type, st.foeHP.value.toDouble(), foe.maxHP.toDouble(), false, isDemo, party,
                Modifier.centerAt(0.31, if (isDemo) 0.13 else 0.12, 0.56))
        }
        val you = st.battle.you
        HPBox(you.name, you.level, you.type, st.youHP.value.toDouble(), you.maxHP.toDouble(), true, isDemo, emptyList(),
            Modifier.centerAt(0.7, if (isDemo) 0.66 else 0.68, 0.56))
    }
}

private val boxInk = rgb(0.22, 0.22, 0.24)

/** An HP box like the handheld games': cream panel, name and level, the type, and the HP bar. */
@Composable
private fun HPBox(name: String, level: Int, type: CDType, hp: Double, maxHP: Double, numbers: Boolean, compact: Boolean,
                  party: List<Boolean>, modifier: Modifier) {
    val frac = if (maxHP > 0) max(0.0, min(1.0, hp / maxHP)) else 0.0
    val bar = if (frac > 0.5) rgb(0.3, 0.82, 0.35) else if (frac > 0.2) rgb(0.98, 0.78, 0.15) else rgb(0.95, 0.25, 0.2)
    val shape = RoundedCornerShape(8.dp)
    Box(modifier) {
        Column(
            Modifier.drawBehind {
                val r = 8.dp.toPx().toDouble()
                rrect(3.dp.toPx().toDouble(), 3.dp.toPx().toDouble(), size.width.toDouble(), size.height.toDouble(), r, Color.Black.op(0.3))
                rrect(0.0, 0.0, size.width.toDouble(), size.height.toDouble(), r, vgrad(listOf(rgb(0.99, 0.99, 0.92), rgb(0.92, 0.93, 0.82)), 0.0, size.height.toDouble()))
            }.border(2.dp, rgb(0.3, 0.32, 0.34), shape)
                .padding(horizontal = if (compact) 7.dp else 10.dp, vertical = if (compact) 4.dp else 7.dp),
            verticalArrangement = Arrangement.spacedBy(if (compact) 2.dp else 4.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                val d = if (compact) 15.dp else 19.dp
                Box(Modifier.size(d).background(CDArt.color(type), CircleShape).border(1.dp, Color.Black.op(0.4), CircleShape), contentAlignment = Alignment.Center) {
                    Icon(typeIcon(type), null, tint = Color.White, modifier = Modifier.size(if (compact) 10.dp else 13.dp))
                }
                Text(name.uppercase(), style = ts(if (compact) 11.0 else 14.0, FontWeight.ExtraBold, boxInk), maxLines = 1,
                    softWrap = false, overflow = TextOverflow.Clip, modifier = Modifier.weight(1f))
                Text("Lv$level", style = ts(if (compact) 10.0 else 13.0, FontWeight.ExtraBold, boxInk), softWrap = false)
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("HP", style = ts(if (compact) 7.0 else 9.0, FontWeight.Black, rgb(1.0, 0.85, 0.3)),
                    modifier = Modifier.background(rgb(0.32, 0.26, 0.2), RoundedCornerShape(3.dp)).padding(horizontal = 3.dp))
                Canvas(Modifier.weight(1f).height(if (compact) 5.dp else 7.dp)) {
                    val w = size.width.toDouble(); val h = size.height.toDouble()
                    rrect(0.0, 0.0, w, h, h / 2, rgb(0.3, 0.3, 0.32))
                    if (frac > 0) rrect(0.0, 0.0, w * frac, h, h / 2, bar)
                }
            }
            if (numbers) {
                Text("${hp.roundAway()}/${maxHP.toInt()}", style = ts(if (compact) 10.0 else 13.0, FontWeight.ExtraBold, boxInk),
                    modifier = Modifier.fillMaxWidth(), textAlign = androidx.compose.ui.text.style.TextAlign.End)
            } else if (party.isNotEmpty()) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(if (compact) 3.dp else 4.dp, Alignment.End)) {
                    for (out in party) {
                        Canvas(Modifier.size(if (compact) 8.dp else 10.dp)) {
                            val r = size.width / 2.0
                            circle(r, r, r, if (out) gray(0.62) else rgb(0.95, 0.3, 0.25))
                            if (!out) circle(r - density, r - density, (if (compact) 1.25 else 1.75) * density, Color.White.op(0.45))
                            circleStroke(r, r, r - 0.6 * density, rgb(0.3, 0.32, 0.34), 1.2 * density)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun MessageBox(message: String, compact: Boolean) {
    Box(
        Modifier.fillMaxWidth().height(if (compact) 38.dp else 54.dp)
            .background(Brush.verticalGradient(listOf(rgb(0.24, 0.5, 0.58), rgb(0.15, 0.36, 0.44))), RoundedCornerShape(10.dp))
            .border(3.dp, rgb(0.88, 0.4, 0.22), RoundedCornerShape(10.dp))
            .padding(4.dp).border(1.dp, Color.White.op(0.5), RoundedCornerShape(7.dp))
            .padding(horizontal = 10.dp),
        contentAlignment = Alignment.CenterStart
    ) {
        Text(message, style = ts(if (compact) 13.0 else 16.0, FontWeight.ExtraBold, Color.White)
            .copy(shadow = Shadow(Color.Black.op(0.55), Offset(2f, 2f), 0f)), maxLines = 2)
    }
}

/** A move button: its type colour, type icon and name (the Snack shows the uses left). */
@Composable
private fun MoveButton(move: CDMove, left: Int?, compact: Boolean, lit: Boolean, dim: Boolean, enabled: Boolean,
                       tapT0: Double, showHand: Boolean, tick: State<Long>, onClick: () -> Unit) {
    val (src, pressed) = rememberPressed()
    val down = pressed.value || lit
    val sc by animateFloatAsState(if (down) 0.95f else 1f, tween(100), label = "mv")
    val tint = if (move.heals) rgb(0.93, 0.55, 0.68) else CDArt.color(move.type)
    val shape = RoundedCornerShape(12.dp)
    val hand = rememberHand()
    Box(
        Modifier.fillMaxSize().scale(sc).alpha(if (dim && !lit) 0.55f else 1f)
            .border(1.dp, Color.Black.op(0.35), shape)
            .padding(1.dp)
            .background(Brush.verticalGradient(listOf(tint.lit(0.18 + if (down) 0.08 else 0.0), tint.shade(0.12))), shape)
            .border(2.dp, Color.White.op(0.85), shape)
            .clickable(src, null, enabled = enabled, onClick = onClick)
    ) {
        Row(Modifier.fillMaxSize().padding(horizontal = if (compact) 8.dp else 12.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(if (compact) 5.dp else 8.dp)) {
            val d = if (compact) 22.dp else 30.dp
            Box(Modifier.size(d).background(Color.White, CircleShape), contentAlignment = Alignment.Center) {
                if (move.heals) Canvas(Modifier.fillMaxSize()) { CDArt.banana(this, size.width / 2.0, size.height / 2.0, size.width * 0.9) }
                else Icon(typeIcon(move.type), null, tint = tint, modifier = Modifier.size(if (compact) 14.dp else 19.dp))
            }
            Text(L(move.en, move.vi), style = ts(if (compact) 12.0 else 16.0, FontWeight.ExtraBold, Color.White)
                .copy(shadow = Shadow(Color.Black.op(0.35), Offset(2f, 2f), 0f)), maxLines = 1, softWrap = false,
                overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            if (left != null) Text("×$left", style = ts(if (compact) 11.0 else 14.0, FontWeight.Black, Color.White))
        }
        if (showHand || nowSec() - tapT0 < 0.6) {
            Canvas(Modifier.fillMaxSize()) {
                tick.value
                val cx = size.width / 2.0; val cy = size.height / 2.0
                tapRipple(cx, cy, nowSec() - tapT0)
                if (showHand) { val hs = 26.0 * density * 1.2; hand(hand, cx + 14 * density - hs * 0.3, cy + 16 * density - hs * 0.4, hs) }
            }
        }
    }
}
