package com.gogs.bananagame.core

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.compose.ui.graphics.Color

/** The app's visual identity: black background, banana yellow accent (iOS `BananaTheme`). */
object BananaTheme {
    val background = Color.Black
    val banana = Color(1.0f, 0.86f, 0.2f)
    val subtle = Color.White.copy(alpha = 0.5f)
    /** The reflex genre tint (cyan). */
    val cyan = Color(0.4f, 0.85f, 0.95f)
}

/**
 * Small wrapper around haptic feedback so games can add "feel" in one line
 * (iOS `Haptics`: UIImpactFeedbackGenerator / UINotificationFeedbackGenerator → Vibrator).
 */
object Haptics {
    /** Transient silence used while a manual's live demo is on screen. */
    @Volatile var suppressed = false
    private var vibrator: Vibrator? = null

    fun init(context: Context) {
        vibrator = if (Build.VERSION.SDK_INT >= 31) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    private fun play(predefined: Int, fallbackMs: Long, amplitude: Int) {
        if (suppressed) return
        val v = vibrator ?: return
        if (!v.hasVibrator()) return
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                v.vibrate(VibrationEffect.createPredefined(predefined))
            } else {
                v.vibrate(VibrationEffect.createOneShot(fallbackMs, amplitude))
            }
        } catch (_: Throwable) {
        }
    }

    /** A light bump — good for taps and hits. */
    fun tap() = play(VibrationEffect.EFFECT_TICK, 10, 60)

    /** A celebratory buzz — good for beating a level. */
    fun success() = play(VibrationEffect.EFFECT_DOUBLE_CLICK, 30, 160)

    /** A warning buzz — good for mistakes. */
    fun warning() = play(VibrationEffect.EFFECT_HEAVY_CLICK, 45, 255)
}
