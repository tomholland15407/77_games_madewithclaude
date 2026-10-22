package com.gogs.bananagame.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
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
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.gogs.bananagame.core.BananaTheme
import com.gogs.bananagame.core.FavoritesStore
import com.gogs.bananagame.core.GameDefinition
import com.gogs.bananagame.core.Haptics
import com.gogs.bananagame.core.L
import com.gogs.bananagame.core.ProgressStore
import com.gogs.bananagame.core.SoundManager
import com.gogs.bananagame.core.StatsStore
import com.gogs.bananagame.core.op
import com.gogs.bananagame.core.ts
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.cos
import kotlin.math.sin

/**
 * One page in the feed (iOS GamePageView): header + level, ❤️, book/manual button, the 3·2·1
 * auto-start countdown, the win celebration (→ next level) and the fail overlay (→ level 1).
 */
@Composable
fun GamePageView(
    game: GameDefinition,
    isActive: Boolean,
    topInset: Dp,
    bottomInset: Dp,
    onLockChange: (Boolean) -> Unit,
    onSkip: () -> Unit,
) {
    var level by remember { mutableIntStateOf(1) }
    var runID by remember { mutableIntStateOf(0) }
    var showReward by remember { mutableStateOf(false) }
    var showFail by remember { mutableStateOf(false) }
    var isCountingDown by remember { mutableStateOf(true) }
    var countdownValue by remember { mutableIntStateOf(3) }
    var showManual by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val isLastLevel = level >= game.levelCount

    LaunchedEffect(runID, isActive) {
        if (!isActive) {
            // Off-screen — stay idle and reset so it starts fresh on return (always level 1).
            level = 1
            showReward = false
            showFail = false
            countdownValue = 3
            isCountingDown = true
            return@LaunchedEffect
        }
        showReward = false
        showFail = false
        isCountingDown = true
        game.prefetch?.invoke(level)
        if (level < game.levelCount) game.prefetch?.invoke(level + 1)
        for (n in 3 downTo 1) {
            countdownValue = n
            SoundManager.countdownTick()
            delay(650)
        }
        isCountingDown = false
        SoundManager.countdownGo()
    }

    val shouldLock = isActive && game.locksFeed && !isCountingDown && !showReward && !showFail && !showManual
    var lastLock by remember { mutableStateOf(false) }
    LaunchedEffect(shouldLock) {
        if (shouldLock != lastLock) {
            lastLock = shouldLock
            onLockChange(shouldLock)
        }
    }

    val handleWin = rememberUpdatedState {
        if (!showReward && !showFail) {
            Haptics.success()
            SoundManager.success()
            StatsStore.award(game.genre, level)
            showReward = true
            if (!isLastLevel) game.prefetch?.invoke(level + 1)
            if (isLastLevel) {
                val id = game.id
                scope.launch { delay(1100); ProgressStore.markMastered(id) }
            }
        }
    }
    val handleFail = rememberUpdatedState {
        if (!showReward && !showFail) {
            Haptics.warning()
            SoundManager.error()
            showFail = true
            game.prefetch?.invoke(1)
            scope.launch {
                delay(1400)
                level = 1
                runID += 1
                showFail = false
            }
        }
    }
    val onWin = remember { { handleWin.value() } }
    val onFail = remember { { handleFail.value() } }

    Box(Modifier.fillMaxSize().background(BananaTheme.background)) {
        Column(
            Modifier.fillMaxSize()
                .padding(top = maxOf(topInset, 60.dp) + 8.dp, bottom = maxOf(bottomInset, 12.dp)),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Header: book · title · heart, then the level line.
            Column(Modifier.fillMaxWidth().padding(top = 8.dp, start = 16.dp, end = 16.dp),
                horizontalAlignment = Alignment.CenterHorizontally) {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                    if (game.manual != null) {
                        HeaderCircle(onClick = {
                            Haptics.tap(); SoundManager.tap(); showManual = true
                        }) { Icon(Icons.Filled.MenuBook, L("Manual", "Hướng dẫn"), tint = Color.White, modifier = Modifier.size(22.dp)) }
                    } else Spacer(Modifier.size(38.dp))
                    Text(
                        game.title, style = ts(22.0, FontWeight.Bold), maxLines = 1, overflow = TextOverflow.Ellipsis,
                        textAlign = TextAlign.Center, modifier = Modifier.weight(1f).padding(horizontal = 8.dp)
                    )
                    val faved = FavoritesStore.isFavorite(game.id)
                    val heartScale by animateFloatAsState(if (faved) 1.1f else 1f, spring(), label = "heart")
                    HeaderCircle(onClick = {
                        FavoritesStore.toggle(game.id); Haptics.tap(); SoundManager.tap()
                    }) {
                        Icon(
                            if (faved) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder, L("Favorite", "Yêu thích"),
                            tint = if (faved) BananaTheme.banana else Color.White, modifier = Modifier.size(24.dp).scale(heartScale)
                        )
                    }
                }
                Spacer(Modifier.height(6.dp))
                Text(L("LEVEL $level / ${game.levelCount}", "CẤP $level / ${game.levelCount}"),
                    style = ts(12.0, FontWeight.ExtraBold, BananaTheme.banana, spacing = 3.0))
            }
            // The play area. The game only exists past the countdown; recreated on each attempt.
            Box(Modifier.fillMaxWidth().weight(1f)) {
                if (!isCountingDown && !showManual) {
                    key(runID) {
                        game.content(level, onWin, onFail)
                    }
                }
            }
        }

        // Skip button — only for feed-locking games (their paging lock would otherwise trap the player).
        if (game.locksFeed && isActive && !showReward && !showFail) {
            Box(Modifier.align(Alignment.BottomCenter).padding(bottom = bottomInset + 24.dp)) {
                HeaderCircle(padding = 14.dp, onClick = { Haptics.tap(); SoundManager.tap(); onSkip() }) {
                    Icon(Icons.Filled.KeyboardArrowDown, L("Skip", "Bỏ qua"), tint = Color.White, modifier = Modifier.size(28.dp))
                }
            }
        }

        if (isCountingDown) CountdownOverlay(countdownValue)
        AnimatedVisibility(showReward, enter = fadeIn(), exit = fadeOut()) {
            Box(Modifier.fillMaxSize()) {
                RewardBurstView()
                CompletionOverlay(level, isLastLevel) {
                    level = if (isLastLevel) 1 else level + 1
                    runID += 1
                    showReward = false
                }
            }
        }
        AnimatedVisibility(showFail, enter = fadeIn(), exit = fadeOut()) { FailOverlay() }
    }

    if (showManual && game.manual != null) {
        Dialog(
            onDismissRequest = { showManual = false; if (isActive) { showReward = false; showFail = false; runID += 1 } },
            properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)
        ) {
            GameManualView(game, game.manual) {
                showManual = false
                if (isActive) { showReward = false; showFail = false; runID += 1 }
            }
        }
    }
}

@Composable
fun HeaderCircle(padding: Dp = 8.dp, onClick: () -> Unit, content: @Composable () -> Unit) {
    Box(
        Modifier.background(Color.White.op(0.08), CircleShape).clickable(onClick = onClick).padding(padding),
        contentAlignment = Alignment.Center
    ) { content() }
}

/** Swallows every touch (the iOS overlays sit over a `.disabled` game). */
fun Modifier.blockTouches(): Modifier = pointerInput(Unit) {
    awaitPointerEventScope { while (true) { awaitPointerEvent().changes.forEach { it.consume() } } }
}

@Composable
private fun CountdownOverlay(value: Int) {
    val pop = remember(value) { Animatable(1.6f) }
    LaunchedEffect(value) { pop.animateTo(1f, spring(dampingRatio = 0.7f, stiffness = 600f)) }
    Box(Modifier.fillMaxSize().background(Color.Black.op(0.55)), contentAlignment = Alignment.Center) {
        Text("$value", style = ts(130.0, FontWeight.Black, BananaTheme.banana),
            modifier = Modifier.scale(pop.value).alpha((2.2f - pop.value).coerceIn(0f, 1f)))
    }
}

@Composable
private fun CompletionOverlay(level: Int, isLastLevel: Boolean, onNext: () -> Unit) {
    Column(
        Modifier.fillMaxSize().background(Color.Black.op(0.75)).blockTouches().padding(40.dp),
        verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            if (isLastLevel) L("You beat every level!", "Bạn đã vượt qua mọi cấp!") else L("Level $level complete!", "Hoàn thành cấp $level!"),
            style = ts(28.0, FontWeight.Bold), textAlign = TextAlign.Center
        )
        Spacer(Modifier.height(22.dp))
        Box(
            Modifier.background(BananaTheme.banana, RoundedCornerShape(50)).clickable(onClick = onNext)
                .padding(horizontal = 32.dp, vertical = 16.dp)
        ) {
            Text(if (isLastLevel) L("Play again", "Chơi lại") else L("Next Level  ▶", "Cấp tiếp theo  ▶"),
                style = ts(17.0, FontWeight.Bold, Color.Black))
        }
    }
}

@Composable
private fun FailOverlay() {
    Column(
        Modifier.fillMaxSize().background(Color.Black.op(0.8)).blockTouches(),
        verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(L("FAILED", "THẤT BẠI"), style = ts(46.0, FontWeight.Black, Color.Red))
        Spacer(Modifier.height(14.dp))
        Text(L("Back to Level 1", "Về cấp 1"), style = ts(20.0, FontWeight.Bold))
    }
}

/** A quick burst of bananas flying outward — the "instant reward" pop. */
@Composable
fun RewardBurstView() {
    val t = remember { Animatable(0f) }
    LaunchedEffect(Unit) { t.animateTo(1f, tween(900, easing = LinearOutSlowInEasing)) }
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        val count = 16
        for (i in 0 until count) {
            val angle = i.toDouble() / count * 2 * Math.PI
            Text(
                "🍌", style = ts(32.0),
                modifier = Modifier
                    .offset(x = (cos(angle) * 190 * t.value).dp, y = (sin(angle) * 190 * t.value).dp)
                    .scale(0.3f + t.value)
                    .alpha(1f - t.value)
            )
        }
    }
}
