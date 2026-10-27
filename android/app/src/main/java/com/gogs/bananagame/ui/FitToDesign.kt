package com.gogs.bananagame.ui

import android.view.Window
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.Density
import androidx.compose.ui.window.DialogWindowProvider
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat

/** The screen the iOS layouts were designed and checked on (iPhone 16 Pro, in points). */
private const val DESIGN_W = 393f
private const val DESIGN_H = 852f

/**
 * Lays the app out as if on the iPhone the iOS design targets.
 * - Phones: on a phone smaller than 393 × 852 dp the density is scaled down so the whole design fits,
 *   every game in its entirety; larger phones keep their density and simply get more room.
 * - Tablets, unfolded foldables and landscape (any window much wider than a phone; Android 16+ ignores
 *   the portrait lock there): a phone-shaped column, centred on black, scaled to the window's height.
 * Text ignores the system font scale (the games size their text to their art). Wrap each window's
 * content (the activity, and any Dialog, which gets a density of its own).
 */
@Composable
fun FitToDesign(content: @Composable () -> Unit) {
    BoxWithConstraints(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
        val base = LocalDensity.current
        val phoneWidth = maxHeight * (DESIGN_W / DESIGN_H)
        val column = maxWidth > phoneWidth * 1.3f
        // A column is exactly the design's aspect and its density makes it 393 dp wide. One layout
        // for both cases, so rotating or unfolding keeps the game and feed state.
        val width = if (column) phoneWidth else maxWidth
        val k = if (column) phoneWidth.value / DESIGN_W
            else minOf(1f, maxWidth.value / DESIGN_W, maxHeight.value / DESIGN_H).coerceAtLeast(0.5f)
        Box(Modifier.width(width).fillMaxHeight()) {
            CompositionLocalProvider(LocalDensity provides Density(base.density * k, 1f)) { content() }
        }
    }
}

/** Full screen, TikTok-style: the status and navigation bars are hidden (a swipe from an edge peeks them). */
fun hideSystemBars(window: Window) {
    WindowCompat.getInsetsController(window, window.decorView).apply {
        systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        hide(WindowInsetsCompat.Type.systemBars())
    }
}

/** Inside a Dialog: hide the bars of the dialog's own window too. */
@Composable
fun HideDialogSystemBars() {
    val view = LocalView.current
    SideEffect { (view.parent as? DialogWindowProvider)?.window?.let { hideSystemBars(it) } }
}
