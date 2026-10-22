package com.gogs.bananagame.core

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.PointerInputChange
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Tracks a single touch from down to up (SwiftUI `DragGesture(minimumDistance: 0)`):
 * [onStart] at the touch-down point, [onMove] with (start, current) points, [onEnd] on release.
 * Every change is consumed so the feed's pager never sees it.
 */
fun Modifier.touchDrag(
    key: Any? = Unit,
    onStart: (P) -> Unit = {},
    onMove: (start: P, now: P) -> Unit = { _, _ -> },
    onEnd: (start: P, now: P) -> Unit = { _, _ -> },
): Modifier = pointerInput(key) {
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false)
        down.consume()
        val start = down.position.p()
        var last = start
        onStart(start)
        while (true) {
            val ev = awaitPointerEvent()
            val ch = ev.changes.firstOrNull { it.id == down.id } ?: break
            if (!ch.pressed) { ch.consume(); break }
            if (ch.positionChange() != androidx.compose.ui.geometry.Offset.Zero) {
                last = ch.position.p()
                onMove(start, last)
            }
            ch.consume()
        }
        onEnd(start, last)
    }
}

/** A tap that reports its position and doesn't need a release-without-move (SwiftUI onTapGesture with location). */
fun Modifier.tapAt(key: Any? = Unit, onTap: (P) -> Unit): Modifier = pointerInput(key) {
    detectTapGestures { onTap(it.p()) }
}

/** Fires on touch-down (no waiting for release) — for arcade buttons that should feel instant. */
fun Modifier.pressDown(key: Any? = Unit, onDown: () -> Unit, onUp: () -> Unit = {}): Modifier = pointerInput(key) {
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false)
        down.consume()
        onDown()
        while (true) {
            val ev = awaitPointerEvent()
            val ch = ev.changes.firstOrNull { it.id == down.id } ?: break
            ch.consume()
            if (!ch.pressed) break
        }
        onUp()
    }
}

@Composable
fun rememberPressed(): Pair<MutableInteractionSource, State<Boolean>> {
    val src = remember { MutableInteractionSource() }
    val pressed = src.collectIsPressedAsState()
    return src to pressed
}
