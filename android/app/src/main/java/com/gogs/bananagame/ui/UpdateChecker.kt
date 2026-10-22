package com.gogs.bananagame.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.BananaTheme
import com.gogs.bananagame.core.L
import com.gogs.bananagame.core.op
import com.gogs.bananagame.core.ts
import kotlinx.coroutines.delay

/** A newer store build the player can move to. */
data class AppUpdate(val version: String, val releaseNotes: String?, val storeUrl: String)

sealed interface UpdateCheckResult {
    data class Available(val update: AppUpdate) : UpdateCheckResult
    data object UpToDate : UpdateCheckResult
    data object NotListed : UpdateCheckResult
    data object Failed : UpdateCheckResult
}

/**
 * The store update check (iOS UpdateChecker). Google Play has no public "lookup" endpoint like
 * iTunes', and the app is not listed yet, so the real lookup reports "not listed" (= up to date),
 * exactly what the iOS build sees today. For testing, launch with the intent extra
 * `GOGS_FAKE_STORE_VERSION` (and optional `GOGS_FAKE_STORE_NOTES`) — the analogue of the iOS
 * DEBUG environment variables — to fake a newer store version.
 */
object UpdateChecker {
    var isChecking by mutableStateOf(false)
        private set
    var launchPrompt by mutableStateOf<AppUpdate?>(null)
    var installedVersion = "1.0"
        private set
    private var packageName = ""
    private var fakeVersion: String? = null
    private var fakeNotes: String? = null
    private var didLaunchCheck = false

    fun init(context: Context, fakeVersion: String?, fakeNotes: String?) {
        packageName = context.packageName
        installedVersion = try {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "1.0"
        } catch (_: Throwable) { "1.0" }
        this.fakeVersion = fakeVersion?.takeIf { it.isNotBlank() }
        this.fakeNotes = fakeNotes
    }

    suspend fun checkAtLaunch() {
        if (didLaunchCheck) return
        didLaunchCheck = true
        val r = check()
        if (r is UpdateCheckResult.Available) launchPrompt = r.update
    }

    suspend fun check(): UpdateCheckResult {
        isChecking = true
        try {
            val fake = fakeVersion
            if (fake != null) {
                delay(600)
                val notes = fakeNotes ?: "• 2 new games\n• Smoother feed scrolling\n• Bug fixes"
                return if (SemanticVersion.isNewer(fake, installedVersion))
                    UpdateCheckResult.Available(AppUpdate(fake, notes, "https://play.google.com/store/apps/details?id=$packageName"))
                else UpdateCheckResult.UpToDate
            }
            delay(400)
            return UpdateCheckResult.NotListed
        } finally {
            isChecking = false
        }
    }
}

/** Numeric dotted-version comparison: "1.10" > "1.9", "1.0" == "1.0.0". */
object SemanticVersion {
    fun components(v: String): List<Int> = v.split('.').map { part -> part.takeWhile { it.isDigit() }.toIntOrNull() ?: 0 }
    fun isNewer(a: String, than: String): Boolean {
        val x = components(a); val y = components(than)
        for (i in 0 until maxOf(x.size, y.size)) {
            val l = x.getOrElse(i) { 0 }; val r = y.getOrElse(i) { 0 }
            if (l != r) return l > r
        }
        return false
    }
}

/** The black/banana update card shown over the feed at launch and from Settings. */
@Composable
fun UpdatePromptView(update: AppUpdate, onDismiss: () -> Unit) {
    val context = LocalContext.current
    Box(
        Modifier.fillMaxSize().background(Color.Black.op(0.7))
            .clickable(remember { MutableInteractionSource() }, null) {},
        contentAlignment = Alignment.Center
    ) {
        Column(
            Modifier.padding(horizontal = 28.dp).widthIn(max = 440.dp)
                .background(BananaTheme.background, RoundedCornerShape(28.dp))
                .border(1.5.dp, BananaTheme.banana.op(0.6), RoundedCornerShape(28.dp))
                .padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(L("Update available", "Có bản cập nhật"), style = ts(26.0, FontWeight.Black))
            Text(
                L("Version ${update.version} is here with new games and features.",
                    "Phiên bản ${update.version} đã có, với trò chơi và tính năng mới."),
                style = ts(17.0, FontWeight.SemiBold, BananaTheme.banana), textAlign = TextAlign.Center
            )
            update.releaseNotes?.let { notes ->
                val long = notes.split("\n").sumOf { maxOf(1, (it.length + 37) / 38) } > 8
                val m = Modifier.fillMaxWidth().background(Color.White.op(0.08), RoundedCornerShape(14.dp)).padding(12.dp)
                Box(if (long) m.height(180.dp).verticalScroll(rememberScrollState()) else m) {
                    Text(notes, style = ts(15.0, color = Color.White.op(0.85)))
                }
            }
            PillButton(L("Update", "Cập nhật"), filled = true) {
                try { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(update.storeUrl))) } catch (_: Throwable) {}
                onDismiss()
            }
            PillButton(L("Later", "Để sau"), filled = false) { onDismiss() }
        }
    }
}

@Composable
fun PillButton(title: String, filled: Boolean, modifier: Modifier = Modifier.fillMaxWidth(), onClick: () -> Unit) {
    Box(
        modifier
            .background(if (filled) BananaTheme.banana else Color.White.op(0.12), RoundedCornerShape(50))
            .clickable(onClick = onClick)
            .padding(vertical = 14.dp, horizontal = 24.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(title, style = ts(17.0, FontWeight.Bold, if (filled) Color.Black else Color.White))
    }
}
