package com.gogs.bananagame.core

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector

/** The two genre buckets: reflex (fast/twitch) and brain (thinking/memory). */
enum class Genre(val raw: String) {
    REFLEX("reflex"), BRAIN("brain");

    val label: String
        get() = when (this) {
            REFLEX -> L("Reflex", "Phản xạ")
            BRAIN -> L("Brain", "Trí tuệ")
        }

    val icon: ImageVector
        get() = when (this) {
            REFLEX -> Icons.Filled.Bolt
            BRAIN -> Icons.Filled.Psychology
        }

    val tint: Color
        get() = when (this) {
            REFLEX -> BananaTheme.cyan
            BRAIN -> BananaTheme.banana
        }
}

/** A genre's icon in its accent colour, read aloud as the genre's name. */
@Composable
fun GenreIcon(genre: Genre, modifier: Modifier = Modifier) {
    Icon(genre.icon, contentDescription = genre.label, tint = genre.tint, modifier = modifier)
}

/** The in-game manual: 2–4 short bullets plus an optional live demo. */
class GameManual(
    val bullets: List<String>,
    val bulletsVI: List<String> = emptyList(),
    val liveDemo: Boolean = false,
) {
    val resolvedBullets: List<String>
        get() = if (Localization.lang == AppLanguage.VI && bulletsVI.isNotEmpty()) bulletsVI else bullets
}

/** True when a game is rendered as a looping manual demo (not real play). */
val LocalIsDemo = compositionLocalOf { false }

typealias GameContent = @Composable (level: Int, onWin: () -> Unit, onFail: () -> Unit) -> Unit

class GameDefinition(
    /** Stable unique id (identical to the iOS id so data stays compatible). */
    val id: String,
    /** Display name (the NEW, trademark-free title). */
    val title: String,
    val genre: Genre,
    val levelCount: Int = 7,
    /** Swipe/drag games lock the feed's paging while actively playing. */
    val locksFeed: Boolean = false,
    val manual: GameManual? = null,
    /** Optional: start building a level's board ahead of time (see [BoardCache]). */
    val prefetch: ((Int) -> Unit)? = null,
    val content: GameContent,
)
