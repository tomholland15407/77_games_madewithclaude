package com.gogs.bananagame

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import com.gogs.bananagame.core.AppSettings
import com.gogs.bananagame.core.BananaTheme
import com.gogs.bananagame.core.FavoritesStore
import com.gogs.bananagame.core.Haptics
import com.gogs.bananagame.core.Localization
import com.gogs.bananagame.core.Prefs
import com.gogs.bananagame.core.ProgressStore
import com.gogs.bananagame.core.SoundManager
import com.gogs.bananagame.core.StatsStore
import com.gogs.bananagame.ui.FitToDesign
import com.gogs.bananagame.ui.RootView
import com.gogs.bananagame.ui.hideSystemBars
import com.gogs.bananagame.ui.UpdateChecker

/** The app's entry point (iOS `BananaGameApp`): initialises the shared services, then shows RootView. */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // Fully immersive, TikTok-style: the status and navigation bars are hidden, so nothing covers
        // the games (a swipe from the edge reveals them transiently).
        hideSystemBars(window)
        Prefs.init(this)
        Localization.init()
        FavoritesStore.init()
        ProgressStore.init()
        StatsStore.init()
        AppSettings.init()
        Haptics.init(this)
        com.gogs.bananagame.games.freethebanana.FreeTheBananaGame.prewarm()
        SoundManager.init(this)
        // Test hook (adb): `--es GOGS_START_GAME <game id>` skips the splash and opens that game.
        com.gogs.bananagame.ui.DebugLaunch.startGame = intent?.getStringExtra("GOGS_START_GAME")
        UpdateChecker.init(this, intent?.getStringExtra("GOGS_FAKE_STORE_VERSION"), intent?.getStringExtra("GOGS_FAKE_STORE_NOTES"))

        setContent {
            MaterialTheme(colorScheme = darkColorScheme(primary = BananaTheme.banana, background = BananaTheme.background, surface = BananaTheme.background)) {
                FitToDesign { RootView() }
            }
        }
    }

    /** The bars come back after a dialog, the notification shade or another app: hide them again. */
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemBars(window)
    }
}
