package com.gogs.bananagame.games.quickmath

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.*
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.max

/** Brain — Quick Math (iOS QuickMathGame.swift): tap the right answer before each equation's clock. */
object QuickMathGame {
    val definition = GameDefinition(
        id = "quick-math",
        title = "Quick Math",
        genre = Genre.BRAIN,
        manual = GameManual(
            bullets = listOf(
                "Tap the correct answer to each equation before its clock expires.",
                "Chain enough right answers in a row to clear the level.",
                "One wrong tap or one timeout drops you to level 1.",
            ),
            bulletsVI = listOf(
                "Chạm vào đáp án đúng cho mỗi phép tính trước khi hết giờ.",
                "Trả lời đúng liên tiếp đủ số lần để qua cấp.",
                "Một lần chạm sai hoặc hết giờ sẽ đưa bạn về cấp 1.",
            ),
            liveDemo = true
        ),
        content = { level, onWin, onFail -> QuickMathView(level, onWin, onFail) }
    )

    data class MathProblem(val text: String, val answer: Int, val choices: List<Int>)

    fun makeProblem(level: Int): MathProblem {
        val maxVal = 5 + level * 3
        val ops = when (level) { in 1..2 -> listOf('+'); in 3..4 -> listOf('+', '-'); else -> listOf('+', '-', '×') }
        val op = ops.pick()
        var a = rndInt(1..maxVal)
        var b = rndInt(1..maxVal)
        val answer = when (op) {
            '+' -> a + b
            '-' -> { if (b > a) { val t = a; a = b; b = t }; a - b }
            else -> { a = rndInt(2..(3 + level)); b = rndInt(2..(3 + level)); a * b }
        }
        val choices = linkedSetOf(answer)
        while (choices.size < 4) {
            val cand = answer + rndInt(-6..6)
            if (cand >= 0 && cand != answer) choices.add(cand)
        }
        return MathProblem("$a $op $b", answer, choices.toList().shuffled())
    }
}

private val PAPER_TOP = rgb(0.98, 0.985, 0.99)
private val PAPER_BOTTOM = rgb(0.92, 0.935, 0.95)
private val CYAN = rgb(0.19, 0.71, 0.93)
private val CYAN_DEEP = rgb(0.12, 0.55, 0.86)
private val WASH = rgb(0.87, 0.95, 0.99)
private val EDGE = rgb(0.62, 0.85, 0.96)
private val PENCIL = rgb(0.66, 0.69, 0.73)
private val TICK = rgb(0.2, 0.76, 0.42)

@Composable
private fun QuickMathView(level: Int, onWin: () -> Unit, onFail: () -> Unit) {
    val isDemo = LocalIsDemo.current
    val target = 2 + level
    val timePerQ = max(1.6, 5.0 - level * 0.45)
    var problem by remember { mutableStateOf(QuickMathGame.MathProblem("", 0, listOf(0, 0, 0, 0))) }
    var score by remember { mutableIntStateOf(0) }
    var timeLeft by remember { mutableDoubleStateOf(timePerQ) }
    var done by remember { mutableStateOf(false) }
    var demoFlash by remember { mutableStateOf<Int?>(null) }
    var lastSolved by remember { mutableStateOf<QuickMathGame.MathProblem?>(null) }
    val scope = rememberCoroutineScope()
    var timerJob by remember { mutableStateOf<Job?>(null) }

    fun startTimer() {
        timerJob?.cancel()
        timeLeft = timePerQ
        val start = nowSec()
        timerJob = scope.launch {
            while (isActive && !done) {
                delay(50)
                timeLeft = max(0.0, timePerQ - (nowSec() - start))
                if (timeLeft <= 0 && !done) { done = true; SoundManager.error(); onFail() }
            }
        }
    }

    fun newProblem() {
        if (done) return
        problem = QuickMathGame.makeProblem(level)
        startTimer()
    }

    fun choose(n: Int) {
        if (done || isDemo) return
        if (n == problem.answer) {
            Haptics.tap(); SoundManager.tap()
            lastSolved = problem
            score += 1
            if (score >= target) { done = true; timerJob?.cancel(); onWin() } else newProblem()
        } else {
            done = true; timerJob?.cancel(); SoundManager.error(); onFail()
        }
    }

    LaunchedEffect(Unit) {
        if (isDemo) {
            while (isActive) {
                done = false; score = 0; lastSolved = null; demoFlash = null
                problem = QuickMathGame.makeProblem(level)
                timeLeft = timePerQ
                while (score < target) {
                    delay(850)
                    val idx = problem.choices.indexOf(problem.answer)
                    if (idx >= 0) demoFlash = idx
                    delay(550)
                    lastSolved = problem
                    demoFlash = null
                    score += 1
                    if (score < target) problem = QuickMathGame.makeProblem(level)
                }
                delay(1300)
            }
        } else newProblem()
    }

    Box(
        Modifier.fillMaxSize().padding(horizontal = if (isDemo) 0.dp else 8.dp)
            .clip(RoundedCornerShape(if (isDemo) 12.dp else 22.dp))
            .background(Brush.verticalGradient(listOf(PAPER_TOP, PAPER_BOTTOM)))
    ) {
        Column(
            Modifier.fillMaxSize().padding(horizontal = if (isDemo) 16.dp else 22.dp)
                .padding(top = if (isDemo) 12.dp else 20.dp, bottom = if (isDemo) 12.dp else 22.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(if (isDemo) 8.dp else 18.dp)
        ) {
            // Progress circles.
            val d = if (isDemo) 17.dp else 22.dp
            Row(horizontalArrangement = Arrangement.spacedBy(if (isDemo) 5.dp else 7.dp)) {
                for (i in 0 until target) {
                    val on = i < score
                    val s by animateFloatAsState(if (on) 1f else 0.85f, spring(dampingRatio = 0.6f, stiffness = 500f), label = "c")
                    Box(
                        Modifier.size(d).scale(if (on) s else 1f).then(
                            if (on) Modifier.background(Brush.verticalGradient(listOf(CYAN, CYAN_DEEP)), CircleShape)
                            else Modifier.border(2.dp, gray(0.8), CircleShape)
                        ),
                        contentAlignment = Alignment.Center
                    ) { if (on) Icon(Icons.Filled.Check, null, tint = Color.White, modifier = Modifier.size(d * 0.6f)) }
                }
            }
            if (!isDemo) TimeBar(timeLeft / timePerQ, Modifier.fillMaxWidth().padding(horizontal = 30.dp).height(6.dp), fill = if (timeLeft / timePerQ < 0.3) Color.Red else CYAN, track = gray(0.86))
            Spacer(Modifier.weight(1f))
            // The solved line above the live one; the stack scrolls up on a right answer.
            AnimatedContent(
                targetState = score,
                transitionSpec = { (slideInVertically { it / 2 } + fadeIn(tween(250))) togetherWith fadeOut(tween(150)) },
                label = "eq"
            ) { sc ->
                Column(verticalArrangement = Arrangement.spacedBy(if (isDemo) 8.dp else 16.dp)) {
                    val prev = if (sc == score) lastSolved else null
                    if (prev != null) EquationLine(prev, solved = true, isDemo = isDemo, flash = null)
                    if (sc < target && problem.text.isNotEmpty()) EquationLine(problem, solved = false, isDemo = isDemo, flash = demoFlash)
                }
            }
            Spacer(Modifier.weight(1f))
            Column(verticalArrangement = Arrangement.spacedBy(if (isDemo) 10.dp else 14.dp)) {
                for (row in 0..1) Row(horizontalArrangement = Arrangement.spacedBy(if (isDemo) 10.dp else 14.dp)) {
                    for (col in 0..1) {
                        val idx = row * 2 + col
                        val value = problem.choices.getOrElse(idx) { 0 }
                        ChoiceTile(value, lit = demoFlash == idx, isDemo = isDemo, modifier = Modifier.weight(1f)) { choose(value) }
                    }
                }
            }
        }
    }
}

@Composable
private fun EquationLine(p: QuickMathGame.MathProblem, solved: Boolean, isDemo: Boolean, flash: Int?) {
    val size = if (solved) (if (isDemo) 24.0 else 32.0) else (if (isDemo) 40.0 else 56.0)
    val shown: Int? = if (solved) p.answer else flash?.let { p.choices.getOrNull(it) }
    Row(
        Modifier.fillMaxWidth()
            .then(if (solved) Modifier else Modifier.background(Color.White, RoundedCornerShape(12.dp)).border(2.dp, EDGE, RoundedCornerShape(12.dp)))
            .padding(horizontal = if (solved) 0.dp else if (isDemo) 12.dp else 18.dp, vertical = if (solved) 0.dp else if (isDemo) 10.dp else 16.dp),
        horizontalArrangement = Arrangement.spacedBy((size * 0.22).dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text("${p.text.replace("-", "−")} =", style = ts(size, FontWeight.Light, if (solved) PENCIL else CYAN), maxLines = 1)
        Box(
            Modifier.size((size * 1.12).dp)
                .background(if (solved) gray(0.9) else WASH, RoundedCornerShape(if (solved) 4.dp else 6.dp))
                .then(if (solved) Modifier else Modifier.border(1.dp, EDGE.op(0.7), RoundedCornerShape(6.dp))),
            contentAlignment = Alignment.Center
        ) {
            Text(shown?.toString() ?: " ", style = ts(size * 0.78, FontWeight.Normal, if (solved) PENCIL else CYAN_DEEP), maxLines = 1)
        }
        if (solved) Icon(Icons.Filled.CheckCircle, null, tint = TICK, modifier = Modifier.size((size * 0.9).dp))
    }
}

@Composable
private fun ChoiceTile(value: Int, lit: Boolean, isDemo: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val src = remember { MutableInteractionSource() }
    val pressed by src.collectIsPressedAsState()
    val on = lit || pressed
    val scale by animateFloatAsState(if (on) 0.95f else 1f, tween(100), label = "s")
    Box(modifier.scale(scale)) {
        Box(
            Modifier.fillMaxWidth().height(if (isDemo) 52.dp else 76.dp)
                .shadow(if (on) 0.dp else 2.dp, RoundedCornerShape(14.dp))
                .background(if (on) Brush.verticalGradient(listOf(CYAN, CYAN_DEEP)) else Brush.verticalGradient(listOf(Color.White, Color.White)), RoundedCornerShape(14.dp))
                .border(2.dp, if (on) CYAN_DEEP else EDGE, RoundedCornerShape(14.dp))
                .clickable(src, null, onClick = onClick),
            contentAlignment = Alignment.Center
        ) {
            Text("$value", style = ts(if (isDemo) 28.0 else 34.0, FontWeight.Normal, if (on) Color.White else CYAN), textAlign = TextAlign.Center)
        }
        if (lit && isDemo) {
            Icon(Icons.Filled.TouchApp, null, tint = Color.White, modifier = Modifier.align(Alignment.Center).offset(36.dp, 24.dp).size(30.dp))
        }
    }
}
