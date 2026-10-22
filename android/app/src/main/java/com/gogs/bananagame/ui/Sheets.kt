package com.gogs.bananagame.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.gogs.bananagame.core.AppLanguage
import com.gogs.bananagame.core.AppSettings
import com.gogs.bananagame.core.BananaTheme
import com.gogs.bananagame.core.FeedFilter
import com.gogs.bananagame.core.GameDefinition
import com.gogs.bananagame.core.Genre
import com.gogs.bananagame.core.GenreIcon
import com.gogs.bananagame.core.L
import com.gogs.bananagame.core.Localization
import com.gogs.bananagame.core.SoundManager
import com.gogs.bananagame.core.StatsStore
import com.gogs.bananagame.core.op
import com.gogs.bananagame.core.ts
import kotlinx.coroutines.launch

/** The iOS sheet chrome: a black page with an inline title and a banana "Done" button. */
@Composable
fun SheetScaffold(title: String, onDone: () -> Unit, content: @Composable () -> Unit) {
    BackHandler(onBack = onDone)
    Column(Modifier.fillMaxSize().background(BananaTheme.background).safeDrawingPadding()) {
        Box(Modifier.fillMaxWidth().height(52.dp).padding(horizontal = 16.dp)) {
            Text(title, style = ts(17.0, FontWeight.SemiBold), modifier = Modifier.align(Alignment.Center))
            Text(L("Done", "Xong"), style = ts(17.0, FontWeight.SemiBold, BananaTheme.banana),
                modifier = Modifier.align(Alignment.CenterEnd).clickable(onClick = onDone).padding(8.dp))
        }
        Box(Modifier.weight(1f)) { content() }
    }
}

@Composable
private fun SectionHeader(text: String) {
    Text(text.uppercase(), style = ts(13.0, FontWeight.Medium, Color.White.op(0.5)),
        modifier = Modifier.padding(start = 16.dp, top = 22.dp, bottom = 6.dp))
}

@Composable
private fun SectionCard(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().background(Color.White.op(0.08), RoundedCornerShape(12.dp)).padding(horizontal = 16.dp, vertical = 6.dp)) {
        content()
    }
}

/** A segmented picker (SwiftUI `.pickerStyle(.segmented)` / menu picker). */
@Composable
fun Segmented(options: List<String>, selected: Int, modifier: Modifier = Modifier, onSelect: (Int) -> Unit) {
    Row(modifier.background(Color.White.op(0.10), RoundedCornerShape(9.dp)).padding(2.dp)) {
        options.forEachIndexed { i, label ->
            Box(
                Modifier.weight(1f)
                    .background(if (i == selected) Color.White.op(0.28) else Color.Transparent, RoundedCornerShape(7.dp))
                    .clickable { onSelect(i) }.padding(vertical = 7.dp),
                contentAlignment = Alignment.Center
            ) { Text(label, style = ts(13.0, if (i == selected) FontWeight.SemiBold else FontWeight.Normal), maxLines = 1) }
        }
    }
}

/** Settings: language, sound, feed filter, genre frequency, update check. */
@Composable
fun SettingsView(onDone: () -> Unit) {
    val scope = rememberCoroutineScope()
    var foundUpdate by remember { mutableStateOf<AppUpdate?>(null) }
    var message by remember { mutableStateOf<String?>(null) } // "upToDate" / "offline"
    val weightLabels = listOf(L("Off", "Tắt"), L("Low", "Thấp"), L("Normal", "Vừa"), L("High", "Cao"))

    SheetScaffold(L("Settings", "Cài đặt"), onDone) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp)) {
            SectionHeader(L("Language / Ngôn ngữ", "Ngôn ngữ / Language"))
            SectionCard {
                Segmented(AppLanguage.entries.map { it.displayName }, Localization.lang.ordinal, Modifier.padding(vertical = 8.dp)) {
                    Localization.lang = AppLanguage.entries[it]
                }
            }
            SectionHeader(L("Sound", "Âm thanh"))
            SectionCard {
                Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(L("Sound effects", "Hiệu ứng âm thanh"), style = ts(17.0), modifier = Modifier.weight(1f))
                    Switch(SoundManager.isEnabled, { SoundManager.isEnabled = it },
                        colors = SwitchDefaults.colors(checkedTrackColor = Color(0xFF34C759), checkedThumbColor = Color.White))
                }
            }
            SectionHeader(L("Feed", "Bảng tin"))
            SectionCard {
                Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(L("Show", "Hiển thị"), style = ts(17.0))
                    Spacer(Modifier.width(16.dp))
                    Segmented(FeedFilter.entries.map { it.label }, AppSettings.feedFilter.ordinal, Modifier.weight(1f)) {
                        AppSettings.feedFilter = FeedFilter.entries[it]
                    }
                }
            }
            SectionHeader(L("Genre frequency", "Tần suất thể loại"))
            SectionCard {
                for (genre in Genre.entries) {
                    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        GenreIcon(genre, Modifier.size(24.dp))
                        Spacer(Modifier.width(12.dp))
                        Segmented(weightLabels, AppSettings.weight(genre), Modifier.weight(1f)) { AppSettings.setWeight(it, genre) }
                    }
                }
            }
            Text(L("How often each genre appears in the feed. “Off” hides it.",
                "Mức độ xuất hiện của mỗi thể loại trong bảng tin. “Tắt” sẽ ẩn nó."),
                style = ts(13.0, color = Color.White.op(0.5)), modifier = Modifier.padding(start = 16.dp, top = 6.dp))
            Spacer(Modifier.height(22.dp))
            SectionCard {
                Row(
                    Modifier.fillMaxWidth().clickable(enabled = !UpdateChecker.isChecking) {
                        scope.launch {
                            when (val r = UpdateChecker.check()) {
                                is UpdateCheckResult.Available -> foundUpdate = r.update
                                UpdateCheckResult.UpToDate, UpdateCheckResult.NotListed -> message = "upToDate"
                                UpdateCheckResult.Failed -> message = "offline"
                            }
                        }
                    }.padding(vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(if (UpdateChecker.isChecking) L("Checking…", "Đang kiểm tra…") else L("Check for Updates", "Kiểm tra cập nhật"),
                        style = ts(17.0, color = BananaTheme.banana), modifier = Modifier.weight(1f))
                    if (UpdateChecker.isChecking) CircularProgressIndicator(Modifier.size(18.dp), color = BananaTheme.banana, strokeWidth = 2.dp)
                }
            }
            Text(L("Version ${UpdateChecker.installedVersion}", "Phiên bản ${UpdateChecker.installedVersion}"),
                style = ts(13.0, color = Color.White.op(0.5)), modifier = Modifier.padding(start = 16.dp, top = 6.dp))
        }
    }
    message?.let { m ->
        AlertDialog(
            onDismissRequest = { message = null },
            confirmButton = { TextButton({ message = null }) { Text(L("OK", "OK"), color = BananaTheme.banana) } },
            title = { Text(if (m == "offline") L("Couldn't check", "Không thể kiểm tra") else L("You're up to date", "Bạn đang dùng bản mới nhất")) },
            text = {
                Text(if (m == "offline") L("We couldn't reach the store. Check your connection and try again.",
                    "Không thể kết nối cửa hàng. Hãy kiểm tra kết nối mạng và thử lại.")
                else L("You have the latest version of GOGs.", "Bạn đang có phiên bản GOGs mới nhất."))
            }
        )
    }
    foundUpdate?.let { u -> UpdatePromptView(u) { foundUpdate = null } }
}

/** Search: find a game by name; picking one brings it to the player. */
@Composable
fun SearchView(games: List<GameDefinition>, onSelect: (String) -> Unit, onDone: () -> Unit) {
    var query by remember { mutableStateOf("") }
    val results = (if (query.isEmpty()) games else games.filter { it.title.contains(query, ignoreCase = true) })
        .sortedBy { it.title.lowercase() }
    SheetScaffold(L("Search", "Tìm kiếm"), onDone) {
        Column(Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
            Row(
                Modifier.fillMaxWidth().padding(vertical = 8.dp).background(Color.White.op(0.12), RoundedCornerShape(10.dp))
                    .padding(horizontal = 10.dp, vertical = 9.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(Icons.Filled.Search, null, tint = Color.White.op(0.5), modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(6.dp))
                Box(Modifier.weight(1f)) {
                    if (query.isEmpty()) Text(L("Game name", "Tên trò chơi"), style = ts(17.0, color = Color.White.op(0.4)))
                    BasicTextField(query, { query = it }, singleLine = true, textStyle = ts(17.0),
                        cursorBrush = SolidColor(BananaTheme.banana), modifier = Modifier.fillMaxWidth())
                }
            }
            if (results.isEmpty()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(L("No games match “$query”", "Không có trò chơi khớp “$query”"), style = ts(17.0, color = BananaTheme.subtle))
                }
            } else {
                LazyColumn(Modifier.fillMaxSize().padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    items(results, key = { it.id }) { game ->
                        Row(
                            Modifier.fillMaxWidth().background(Color.White.op(0.06), RoundedCornerShape(4.dp))
                                .clickable { onSelect(game.id); onDone() }.padding(horizontal = 16.dp, vertical = 14.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(game.title, style = ts(17.0), modifier = Modifier.weight(1f))
                            GenreIcon(game.genre, Modifier.size(22.dp))
                        }
                    }
                }
            }
        }
    }
}

/** The "unrot your brain" scoreboard: streak + best, Smart and Fresh pools, total. */
@Composable
fun StatsView(onDone: () -> Unit) {
    SheetScaffold(L("Your Brain", "Não của bạn"), onDone) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(28.dp), horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(top = 8.dp)) {
                Text("🍌", style = ts(52.0))
                Spacer(Modifier.height(8.dp))
                Text(L("UNROT YOUR BRAIN", "UNROT NÃO CỦA BẠN"), style = ts(22.0, FontWeight.Black, BananaTheme.banana, spacing = 2.0))
            }
            Column(
                Modifier.fillMaxWidth().background(Color.White.op(0.05), RoundedCornerShape(24.dp)).padding(vertical = 28.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text("${StatsStore.currentStreak}", style = ts(72.0, FontWeight.Black))
                Text(L("DAY STREAK", "CHUỖI NGÀY"), style = ts(15.0, FontWeight.ExtraBold, Color.White.op(0.6), spacing = 3.0))
                Spacer(Modifier.height(4.dp))
                Text(L("Best: ${StatsStore.bestStreak}", "Kỷ lục: ${StatsStore.bestStreak}"), style = ts(17.0, FontWeight.Bold, BananaTheme.banana))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                PointCard(L("SMART", "THÔNG MINH"), Genre.BRAIN, StatsStore.smartPoints, Modifier.weight(1f))
                PointCard(L("FRESH", "TỈNH TÁO"), Genre.REFLEX, StatsStore.freshPoints, Modifier.weight(1f))
            }
            Column(
                Modifier.fillMaxWidth().background(Color.White.op(0.05), RoundedCornerShape(20.dp)).padding(vertical = 20.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text("${StatsStore.totalPoints}", style = ts(34.0, FontWeight.Black))
                Text(L("TOTAL POINTS", "TỔNG ĐIỂM"), style = ts(15.0, FontWeight.ExtraBold, Color.White.op(0.6), spacing = 2.0))
            }
        }
    }
}

@Composable
private fun PointCard(title: String, genre: Genre, value: Int, modifier: Modifier) {
    Column(
        modifier.background(Color.White.op(0.05), RoundedCornerShape(20.dp)).padding(vertical = 22.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text(title, style = ts(15.0, FontWeight.ExtraBold, genre.tint, spacing = 2.0), textAlign = TextAlign.Center)
        Text("$value", style = ts(40.0, FontWeight.Black))
        GenreIcon(genre, Modifier.size(24.dp))
    }
}
