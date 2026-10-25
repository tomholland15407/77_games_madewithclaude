package com.gogs.bananagame.ui

import android.view.Window
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.Modifier
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
 * Lays the app out as if on the iPhone the iOS design targets: on a phone smaller than 393 × 852 dp the
 * density is scaled down so the whole design fits, every game in its entirety; larger phones keep their
 * density and simply get more room. Text ignores the system font scale for the same reason (the games
 * size their text to their art). Wrap each window's content (the activity, and any Dialog, which gets a
 * density of its own).
 */
@Composable
fun FitToDesign(content: @Composable () -> Unit) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val base = LocalDensity.current
        val k = minOf(1f, maxWidth.value / DESIGN_W, maxHeight.value / DESIGN_H).coerceAtLeast(0.5f)
        CompositionLocalProvider(LocalDensity provides Density(base.density * k, 1f)) { content() }
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
