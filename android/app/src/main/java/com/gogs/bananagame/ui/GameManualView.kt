package com.gogs.bananagame.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.BananaTheme
import com.gogs.bananagame.core.GameDefinition
import com.gogs.bananagame.core.GameManual
import com.gogs.bananagame.core.Haptics
import com.gogs.bananagame.core.L
import com.gogs.bananagame.core.LocalIsDemo
import com.gogs.bananagame.core.SoundManager
import com.gogs.bananagame.core.op
import com.gogs.bananagame.core.ts

/** The in-game manual: a live self-looping demo (when the game has one) plus 2–4 bullets. */
@Composable
fun GameManualView(game: GameDefinition, manual: GameManual, onClose: () -> Unit) {
    BackHandler(onBack = onClose)
    Column(Modifier.fillMaxSize().background(BananaTheme.background).safeDrawingPadding()) {
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp)
        ) {
            Column(Modifier.padding(top = 20.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(L("MANUAL", "HƯỚNG DẪN"), style = ts(12.0, FontWeight.ExtraBold, BananaTheme.banana, spacing = 3.0))
                Text(game.title, style = ts(34.0, FontWeight.Black))
            }
            if (manual.liveDemo) {
                Box(
                    Modifier.fillMaxWidth().height(340.dp).clip(RoundedCornerShape(16.dp))
                        .background(BananaTheme.background)
                        .border(1.dp, Color.White.op(0.10), RoundedCornerShape(16.dp))
                        .blockTouches()
                ) { LiveDemoView(game) }
            }
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Text(L("HOW TO PLAY", "CÁCH CHƠI"), style = ts(15.0, FontWeight.ExtraBold, Color.White.op(0.55), spacing = 2.0))
                for (bullet in manual.resolvedBullets) {
                    Row(verticalAlignment = Alignment.Top) {
                        Text("•", style = ts(22.0, FontWeight.Black, BananaTheme.banana))
                        Spacer(Modifier.width(12.dp))
                        Text(bullet, style = ts(19.0, FontWeight.Medium), modifier = Modifier.weight(1f))
                    }
                }
            }
        }
        PillButton(L("Return to game", "Quay lại trò chơi"), filled = true,
            modifier = Modifier.fillMaxWidth().padding(start = 24.dp, end = 24.dp, top = 8.dp, bottom = 20.dp)) { onClose() }
    }
}

/**
 * Renders a game's own view as a muted, non-interactive, self-looping demo. The game seeds and
 * loops itself when [LocalIsDemo] is true; its onWin/onFail are never called in demo mode.
 */
@Composable
fun LiveDemoView(game: GameDefinition) {
    DisposableEffect(Unit) {
        SoundManager.suppressed = true
        Haptics.suppressed = true
        onDispose {
            SoundManager.suppressed = false
            Haptics.suppressed = false
        }
    }
    CompositionLocalProvider(LocalIsDemo provides true) {
        game.content(1, {}, {})
    }
}
