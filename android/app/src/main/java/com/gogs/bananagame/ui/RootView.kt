package com.gogs.bananagame.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.AppSettings
import com.gogs.bananagame.core.BananaTheme
import com.gogs.bananagame.core.GameDefinition
import com.gogs.bananagame.core.L
import com.gogs.bananagame.core.ts
import com.gogs.bananagame.games.GameRegistry

/** A quick banana splash, then the feed; on a cold launch it offers to return to the last game. */
/** Test hook set from the launch intent (see MainActivity). */
object DebugLaunch { var startGame: String? = null }

@Composable
fun RootView() {
    val debugStart = remember { DebugLaunch.startGame }
    var showSplash by rememberSaveable { mutableStateOf(debugStart == null) }
    var resumeID by rememberSaveable { mutableStateOf(debugStart) }
    val lastGame = remember { AppSettings.lastGameID?.let { id -> GameRegistry.all.firstOrNull { it.id == id } } }

    LaunchedEffect(Unit) { UpdateChecker.checkAtLaunch() }

    Box(Modifier.fillMaxSize().background(BananaTheme.background)) {
        AnimatedContent(
            targetState = showSplash,
            transitionSpec = { fadeIn(tween(500)) togetherWith fadeOut(tween(500)) },
            label = "root"
        ) { splash ->
            if (splash) {
                SplashView(
                    resumeGame = lastGame,
                    onResume = { resumeID = lastGame?.id; showSplash = false },
                    onStart = { resumeID = null; showSplash = false },
                )
            } else {
                FeedView(initialGameID = resumeID)
            }
        }
        val prompt = UpdateChecker.launchPrompt
        if (!showSplash && prompt != null) {
            UpdatePromptView(prompt) { UpdateChecker.launchPrompt = null }
        }
    }
}

/** The banana mascot splash: Start Fresh, plus "Return to …" when there is a game to resume. */
@Composable
fun SplashView(resumeGame: GameDefinition?, onResume: () -> Unit, onStart: () -> Unit) {
    val pop = remember { Animatable(0f) }
    LaunchedEffect(Unit) { pop.animateTo(1f, tween(550, easing = LinearOutSlowInEasing)) }
    Column(
        Modifier.fillMaxSize().padding(horizontal = 24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            "🍌", style = ts(96.0),
            modifier = Modifier.scale(0.5f + 0.5f * pop.value).rotate(360f * pop.value)
        )
        Spacer(Modifier.height(16.dp))
        Text("GAME OF GAMES", style = ts(34.0, FontWeight.Black), textAlign = TextAlign.Center)
        Spacer(Modifier.height(16.dp))
        Text(L("UNROT YOUR BRAIN", "UNROT NÃO CỦA BẠN"), style = ts(17.0, FontWeight.ExtraBold, BananaTheme.banana, spacing = 3.0))
        Spacer(Modifier.height(48.dp))
        if (resumeGame != null) {
            PillButton(L("Return to ${resumeGame.title}", "Quay lại ${resumeGame.title}"), filled = true,
                modifier = Modifier.wrapContentWidth(), onClick = onResume)
            Spacer(Modifier.height(14.dp))
        }
        PillButton(L("Start Fresh", "Bắt đầu mới"), filled = false, modifier = Modifier.wrapContentWidth(), onClick = onStart)
    }
}
