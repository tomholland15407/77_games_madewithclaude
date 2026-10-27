package com.gogs.bananagame.ui

import com.gogs.bananagame.core.BananaMascot
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material.icons.filled.VerticalAlignTop
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import com.gogs.bananagame.core.AppSettings
import com.gogs.bananagame.core.BananaTheme
import com.gogs.bananagame.core.FavoritesStore
import com.gogs.bananagame.core.FeedFilter
import com.gogs.bananagame.core.GameDefinition
import com.gogs.bananagame.core.Haptics
import com.gogs.bananagame.core.L
import com.gogs.bananagame.core.ProgressStore
import com.gogs.bananagame.core.SoundManager
import com.gogs.bananagame.core.StatsStore
import com.gogs.bananagame.core.op
import com.gogs.bananagame.core.ts
import com.gogs.bananagame.games.GameRegistry
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.random.Random

private const val END_ID = "__gogs_end__"

/**
 * The TikTok-style feed (iOS FeedView): a full-screen vertical pager, one game per page, with the
 * filter menu (All / Favorites / Unplayed + Reshuffle), the banana dropdown (stats / search /
 * settings), per-mode remembered orderings and positions, genre-weighted shuffles, pull-to-reshuffle
 * at the top, and the end-of-feed page.
 */
@Composable
fun FeedView(initialGameID: String?) {
    val orders = remember { mutableStateMapOf<FeedFilter, List<GameDefinition>>() }
    val savedCurrent = remember { mutableStateMapOf<FeedFilter, String>() }
    var currentGameID by remember { mutableStateOf<String?>(null) }
    var showSearch by remember { mutableStateOf(false) }
    var showSettings by remember { mutableStateOf(false) }
    var showStats by remember { mutableStateOf(false) }
    var menuOpen by remember { mutableStateOf(false) }
    var filterMenuOpen by remember { mutableStateOf(false) }
    var bananaSpin by remember { mutableFloatStateOf(0f) }
    var initialized by remember { mutableStateOf(false) }
    var suppressModeRestore by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    val lifecycleState by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    val isAttendingFeed = lifecycleState.isAtLeast(Lifecycle.State.RESUMED) &&
        !showSearch && !showSettings && !showStats && UpdateChecker.launchPrompt == null


    fun displayedFor(mode: FeedFilter): List<GameDefinition> {
        val base = orders[mode] ?: emptyList()
        return when (mode) {
            FeedFilter.ALL -> base
            FeedFilter.UNPLAYED -> base.filter { it.id !in ProgressStore.mastered }
            FeedFilter.FAVORITES -> {
                val kept = base.filter { FavoritesStore.isFavorite(it.id) }
                val keptIds = kept.map { it.id }.toSet()
                kept + GameRegistry.all.filter { FavoritesStore.isFavorite(it.id) && it.id !in keptIds }
            }
        }
    }

    fun weightedShuffle(games: List<GameDefinition>): List<GameDefinition> =
        games.filter { AppSettings.weight(it.genre) > 0 }
            .map { it to Random.nextDouble() * AppSettings.weight(it.genre) }
            .sortedByDescending { it.second }
            .map { it.first }

    fun buildOrder(mode: FeedFilter): List<GameDefinition> = when (mode) {
        FeedFilter.ALL -> weightedShuffle(GameRegistry.all)
        FeedFilter.UNPLAYED -> weightedShuffle(GameRegistry.all.filter { !ProgressStore.isMastered(it.id) })
        FeedFilter.FAVORITES -> GameRegistry.all.filter { FavoritesStore.isFavorite(it.id) }.shuffled()
    }

    fun setOrder(list: List<GameDefinition>, mode: FeedFilter) {
        orders[mode] = list
        AppSettings.setFeedOrder(mode, list.map { it.id })
    }

    fun ensureOrder(mode: FeedFilter) {
        if (orders[mode] == null) setOrder(buildOrder(mode), mode)
    }

    fun rememberPosition(id: String?, mode: FeedFilter) {
        if (id == null) savedCurrent.remove(mode) else savedCurrent[mode] = id
        AppSettings.setFeedPosition(mode, id)
    }

    fun rehydrateOrders() {
        val byID = GameRegistry.all.associateBy { it.id }
        for (mode in FeedFilter.entries) {
            val ids = AppSettings.feedOrder(mode)
            if (ids.isNullOrEmpty()) continue
            var list = ids.mapNotNull { byID[it] }
            val have = list.map { it.id }.toSet()
            list = list + buildOrder(mode).filter { it.id !in have }
            if (list.isEmpty()) continue
            orders[mode] = list
            if (list.map { it.id } != ids) setOrder(list, mode)
        }
        for (mode in FeedFilter.entries) AppSettings.feedPosition(mode)?.let { savedCurrent[mode] = it }
    }

    fun reshuffleCurrentMode() {
        Haptics.tap(); SoundManager.tap()
        val mode = AppSettings.feedFilter
        setOrder(buildOrder(mode), mode)
        currentGameID = displayedFor(mode).firstOrNull()?.id
    }

    fun reshuffleBelowCurrent(mode: FeedFilter) {
        val order = orders[mode] ?: return
        val anchor = if (mode == AppSettings.feedFilter) currentGameID else savedCurrent[mode]
        val idx = order.indexOfFirst { it.id == anchor }
        if (anchor == null || idx < 0) {
            setOrder(buildOrder(mode), mode)
            if (mode == AppSettings.feedFilter) currentGameID = displayedFor(mode).firstOrNull()?.id
            return
        }
        val prefix = order.subList(0, idx + 1)
        val prefixIds = prefix.map { it.id }.toSet()
        val candidates = when (mode) {
            FeedFilter.UNPLAYED -> GameRegistry.all.filter { !ProgressStore.isMastered(it.id) && it.id !in prefixIds }
            else -> GameRegistry.all.filter { it.id !in prefixIds }
        }
        setOrder(prefix + weightedShuffle(candidates), mode)
    }

    fun skipToNext() {
        val list = displayedFor(AppSettings.feedFilter)
        val cur = currentGameID ?: return
        if (cur == END_ID) return
        val index = list.indexOfFirst { it.id == cur }
        if (index < 0) return
        currentGameID = if (index + 1 < list.size) list[index + 1].id else END_ID
    }

    fun switchMode(new: FeedFilter) {
        // The "mode changed" block below restores the new mode's remembered order + position.
        AppSettings.feedFilter = new
    }

    fun jumpTo(id: String) {
        val game = GameRegistry.all.firstOrNull { it.id == id } ?: return
        ensureOrder(AppSettings.feedFilter)
        if (displayedFor(AppSettings.feedFilter).none { it.id == id } && AppSettings.feedFilter != FeedFilter.ALL) {
            rememberPosition(currentGameID, AppSettings.feedFilter)
            suppressModeRestore = true
            AppSettings.feedFilter = FeedFilter.ALL
            ensureOrder(FeedFilter.ALL)
        }
        val mode = AppSettings.feedFilter
        val list = (orders[mode] ?: emptyList()).filter { it.id != id }.toMutableList()
        val curIdx = list.indexOfFirst { it.id == currentGameID }
        if (curIdx >= 0) list.add(curIdx + 1, game) else list.add(0, game)
        setOrder(list, mode)
        currentGameID = id
    }

    // First appearance: rehydrate saved orders, then open on the resume game or the top.
    if (!initialized) {
        initialized = true
        rehydrateOrders()
        ensureOrder(AppSettings.feedFilter)
        val resume = initialGameID
        if (resume != null && GameRegistry.all.any { it.id == resume }) {
            if (AppSettings.feedFilter != FeedFilter.ALL && orders[AppSettings.feedFilter]?.any { it.id == resume } != true) {
                AppSettings.feedFilter = FeedFilter.ALL
                ensureOrder(FeedFilter.ALL)
            }
            val list = displayedFor(AppSettings.feedFilter)
            currentGameID = if (list.any { it.id == resume }) resume else list.firstOrNull()?.id
        } else {
            currentGameID = displayedFor(AppSettings.feedFilter).firstOrNull()?.id
        }
    }

    val filter = AppSettings.feedFilter
    val displayed = displayedFor(filter)
    val displayedIds = displayed.map { it.id }

    // Frequency change: keep everything up to the current game, reshuffle the tail.
    val weightsKey = AppSettings.genreWeights.entries.sortedBy { it.key.ordinal }.joinToString { "${it.value}" }
    var lastWeightsKey by remember { mutableStateOf(weightsKey) }
    if (weightsKey != lastWeightsKey) {
        lastWeightsKey = weightsKey
        reshuffleBelowCurrent(FeedFilter.ALL)
        reshuffleBelowCurrent(FeedFilter.UNPLAYED)
    }

    // Mode changed from outside the filter menu (Settings' picker): restore that mode's spot.
    var lastFilter by remember { mutableStateOf(filter) }
    if (filter != lastFilter) {
        val old = lastFilter
        lastFilter = filter
        if (!suppressModeRestore) {
            rememberPosition(if (currentGameID == END_ID) null else currentGameID, old)
            ensureOrder(filter)
            val list = displayedFor(filter)
            val saved = savedCurrent[filter]
            currentGameID = if (saved != null && list.any { it.id == saved }) saved else list.firstOrNull()?.id
        }
        suppressModeRestore = false
    }

    // The current game dropped out of the filter (mastered / unfavorited): advance to the next survivor.
    var lastIds by remember { mutableStateOf(displayedIds) }
    var lastIdsFilter by remember { mutableStateOf(filter) }
    if (displayedIds != lastIds) {
        val oldIds = lastIds
        val sameMode = lastIdsFilter == filter
        lastIds = displayedIds
        lastIdsFilter = filter
        val cur = currentGameID
        if (sameMode) {
            if (cur == END_ID) {
                if (displayedIds.isEmpty()) currentGameID = null
            } else if (cur == null) {
                currentGameID = displayedIds.firstOrNull()
            } else if (cur !in displayedIds) {
                val oldIdx = oldIds.indexOf(cur)
                currentGameID = if (oldIdx >= 0) {
                    oldIds.drop(oldIdx + 1).firstOrNull { it in displayedIds }
                        ?: oldIds.take(oldIdx).lastOrNull { it in displayedIds } ?: displayedIds.firstOrNull()
                } else displayedIds.firstOrNull()
            }
        }
    }

    // Remember the on-screen game.
    LaunchedEffect(currentGameID) {
        val id = currentGameID
        if (id != null && id != END_ID) {
            AppSettings.lastGameID = id
            rememberPosition(id, AppSettings.feedFilter)
        }
    }

    val density = LocalDensity.current
    // iOS reads the insets from a GeometryReader that ignores the safe area, so they come through
    // as zero and the page's floors (60pt top, 12pt bottom) do the work. Mirror that exactly: the
    // floors clear a camera cutout, and the controls sit 16dp from the top like on iOS.
    val topInset = 0.dp
    val bottomInset = 0.dp

    // Pull-to-reshuffle state.
    val pullThresholdPx = with(density) { 130.dp.toPx() }
    var pullPx by remember { mutableFloatStateOf(0f) }
    val pullProgress = (pullPx / pullThresholdPx).coerceIn(0f, 1.5f)

    Box(Modifier.fillMaxSize().background(BananaTheme.background)) {
        if (displayed.isEmpty()) {
            EmptyState(filter)
        } else {
            key(filter) {
                val pageIds = displayedIds + END_ID
                val pageIdsState = rememberUpdatedState(pageIds)
                val startPage = pageIds.indexOf(currentGameID).coerceAtLeast(0)
                val pagerState = rememberPagerState(initialPage = startPage) { pageIdsState.value.size }

                // Pager → current game (once a swipe settles).
                LaunchedEffect(pagerState) {
                    snapshotFlow { pagerState.settledPage }.collect { p ->
                        val id = pageIdsState.value.getOrNull(p)
                        if (id != null && id != currentGameID) currentGameID = id
                    }
                }
                // Current game → pager (skip / search / reshuffle / drop-outs).
                LaunchedEffect(currentGameID, pageIds) {
                    val i = pageIds.indexOf(currentGameID)
                    if (i >= 0 && i != pagerState.currentPage) {
                        if (abs(i - pagerState.currentPage) > 2) pagerState.scrollToPage(i) else pagerState.animateScrollToPage(i)
                    }
                }
                val atTop = pagerState.currentPage == 0 && pagerState.currentPageOffsetFraction >= -0.001f
                val atTopState = rememberUpdatedState(atTop)
                val reshuffle = rememberUpdatedState { reshuffleCurrentMode() }
                val pullAnim = remember { Animatable(0f) }
                val connection = remember {
                    object : NestedScrollConnection {
                        override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                            if (source == NestedScrollSource.UserInput && pullPx > 0f && available.y < 0f) {
                                val take = maxOf(available.y, -pullPx * 2f)
                                pullPx = (pullPx + take * 0.5f).coerceAtLeast(0f)
                                return Offset(0f, take)
                            }
                            return Offset.Zero
                        }

                        override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
                            if (source == NestedScrollSource.UserInput && available.y > 0f && atTopState.value) {
                                pullPx += available.y * 0.5f
                                return Offset(0f, available.y)
                            }
                            return Offset.Zero
                        }

                        override suspend fun onPreFling(available: Velocity): Velocity {
                            if (pullPx <= 0f) return Velocity.Zero
                            if (pullPx >= pullThresholdPx) {
                                reshuffle.value()
                                Haptics.success()
                            }
                            pullAnim.snapTo(pullPx)
                            pullAnim.animateTo(0f, spring()) { pullPx = value }
                            pullPx = 0f
                            return available
                        }
                    }
                }

                VerticalPager(
                    state = pagerState,
                    modifier = Modifier.fillMaxSize().nestedScroll(connection),
                    // Never locked: drag games claim the swipes inside their play area (their drag
                    // handlers consume them), so a swipe anywhere else still moves to the next game,
                    // even mid-play. Feed-locking games keep their skip button too.
                    userScrollEnabled = true,
                    beyondViewportPageCount = 0,
                    key = { pageIdsState.value.getOrElse(it) { "x$it" } },
                ) { page ->
                    val id = pageIds.getOrNull(page)
                    if (id == END_ID || id == null) {
                        FeedEndPage(topInset, bottomInset,
                            onTop = { Haptics.tap(); SoundManager.tap(); currentGameID = displayedFor(AppSettings.feedFilter).firstOrNull()?.id },
                            onReshuffle = { reshuffleCurrentMode() })
                    } else {
                        val game = displayed.first { it.id == id }
                        GamePageView(
                            game = game,
                            isActive = currentGameID == game.id && isAttendingFeed && pagerState.settledPage == page,
                            topInset = topInset,
                            bottomInset = bottomInset,
                            onSkip = { skipToNext() },
                        )
                    }
                }
                if (pullProgress > 0.02f && currentGameID == displayedIds.firstOrNull()) {
                    PullBanana(pullProgress, topInset)
                }
            }
        }

        // Top controls: filter menu (left) and the banana dropdown (right).
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = maxOf(topInset, 12.dp) + 4.dp),
            verticalAlignment = Alignment.Top
        ) {
            Box {
                Row(
                    Modifier.background(Color.White.op(0.12), RoundedCornerShape(50)).clickable { filterMenuOpen = true }
                        .padding(horizontal = 14.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(filter.label, style = ts(15.0, FontWeight.Bold))
                    Spacer(Modifier.width(4.dp))
                    Icon(Icons.Filled.KeyboardArrowDown, null, tint = Color.White, modifier = Modifier.size(16.dp))
                }
                DropdownMenu(filterMenuOpen, { filterMenuOpen = false }) {
                    for (f in FeedFilter.entries) {
                        DropdownMenuItem(
                            text = { Text(f.label) },
                            leadingIcon = { if (f == filter) Icon(Icons.Filled.Check, null) else Spacer(Modifier.size(24.dp)) },
                            onClick = { filterMenuOpen = false; switchMode(f) }
                        )
                    }
                    HorizontalDivider()
                    DropdownMenuItem(
                        text = { Text(L("Reshuffle", "Xáo lại")) },
                        leadingIcon = { Icon(Icons.Filled.Shuffle, null) },
                        onClick = { filterMenuOpen = false; reshuffleCurrentMode() }
                    )
                }
            }
            Spacer(Modifier.weight(1f))
            val spin by animateFloatAsState(bananaSpin, tween(500), label = "spin")
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(
                    Modifier.size(40.dp).background(Color.White.op(0.12), CircleShape).clickable {
                        bananaSpin += 360f
                        menuOpen = !menuOpen
                        Haptics.tap(); SoundManager.tap()
                    },
                    contentAlignment = Alignment.Center
                ) { BananaMascot(Modifier.size(26.dp).rotate(spin)) }
                AnimatedVisibility(menuOpen, enter = fadeIn() + slideInVertically { -it / 2 }, exit = fadeOut() + slideOutVertically { -it / 2 }) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        MenuIcon(Icons.Filled.BarChart, L("Stats", "Thống kê")) { menuOpen = false; showStats = true }
                        MenuIcon(Icons.Filled.Search, L("Search", "Tìm kiếm")) { menuOpen = false; showSearch = true }
                        MenuIcon(Icons.Filled.Settings, L("Settings", "Cài đặt")) { menuOpen = false; showSettings = true }
                    }
                }
            }
        }

        SheetHost(showSearch) { SearchView(GameRegistry.all, onSelect = { jumpTo(it) }, onDone = { showSearch = false }) }
        SheetHost(showSettings) { SettingsView(onDone = { showSettings = false }) }
        SheetHost(showStats) { StatsView(onDone = { showStats = false }) }
    }
}

@Composable
private fun SheetHost(visible: Boolean, content: @Composable () -> Unit) {
    AnimatedVisibility(visible, enter = slideInVertically { it }, exit = slideOutVertically { it }) {
        Box(Modifier.fillMaxSize().blockTouches().background(BananaTheme.background)) { content() }
    }
}

@Composable
private fun MenuIcon(icon: ImageVector, label: String, onClick: () -> Unit) {
    Box(
        Modifier.size(40.dp).background(Color.White.op(0.12), CircleShape).clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) { Icon(icon, label, tint = Color.White, modifier = Modifier.size(20.dp)) }
}

@Composable
private fun EmptyState(filter: FeedFilter) {
    val title = when (filter) {
        FeedFilter.FAVORITES -> L("No favorites yet", "Chưa có mục yêu thích")
        FeedFilter.UNPLAYED -> L("All mastered!", "Đã thông thạo hết!")
        FeedFilter.ALL -> L("Nothing to show", "Không có gì để hiển thị")
    }
    val msg = when (filter) {
        FeedFilter.FAVORITES -> L("Tap the heart on a game to add it here.", "Chạm vào trái tim trên một trò chơi để thêm vào đây.")
        FeedFilter.UNPLAYED -> L("You've beaten every level of every game.", "Bạn đã vượt qua mọi cấp của mọi trò chơi.")
        FeedFilter.ALL -> L("All genres are turned off. Enable one in Settings.", "Tất cả thể loại đã tắt. Bật một thể loại trong Cài đặt.")
    }
    Column(Modifier.fillMaxSize().padding(40.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        BananaMascot(Modifier.size(72.dp))
        Spacer(Modifier.height(14.dp))
        Text(title, style = ts(22.0, FontWeight.Bold))
        Spacer(Modifier.height(14.dp))
        Text(msg, style = ts(15.0, color = BananaTheme.subtle), textAlign = TextAlign.Center)
    }
}

@Composable
private fun PullBanana(progress: Float, topInset: androidx.compose.ui.unit.Dp) {
    val armed = progress >= 1f
    Box(Modifier.fillMaxWidth().padding(top = maxOf(topInset, 12.dp) + 6.dp + (progress * 60).dp), contentAlignment = Alignment.TopCenter) {
        Box(Modifier.size(56.dp).alpha((progress / 0.3f).coerceAtMost(1f)), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize()) {
                val sw = 3.dp.toPx()
                drawCircle(Color.White.op(0.18), size.minDimension / 2 - sw / 2, style = Stroke(sw))
                drawArc(if (armed) Color.Green else BananaTheme.banana, -90f, 360f * progress.coerceAtMost(1f), false,
                    topLeft = Offset(sw / 2, sw / 2), size = Size(size.width - sw, size.height - sw), style = Stroke(sw, cap = StrokeCap.Round))
            }
            BananaMascot(Modifier.size(34.dp).rotate(progress * 360f))
        }
    }
}

@Composable
private fun FeedEndPage(topInset: androidx.compose.ui.unit.Dp, bottomInset: androidx.compose.ui.unit.Dp, onTop: () -> Unit, onReshuffle: () -> Unit) {
    Column(
        Modifier.fillMaxSize().background(BananaTheme.background).padding(horizontal = 30.dp)
            .padding(top = maxOf(topInset, 60.dp), bottom = maxOf(bottomInset, 24.dp)),
        verticalArrangement = Arrangement.spacedBy(26.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        BananaMascot(Modifier.size(68.dp))
        Text(L("You've reached the end", "Bạn đã đến cuối"), style = ts(24.0, FontWeight.Black), textAlign = TextAlign.Center)
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            EndStat(L("STREAK", "CHUỖI"), "${StatsStore.currentStreak}", BananaTheme.banana, Modifier.weight(1f))
            EndStat(L("SMART", "THÔNG MINH"), "${StatsStore.smartPoints}", BananaTheme.banana, Modifier.weight(1f))
            EndStat(L("FRESH", "TỈNH TÁO"), "${StatsStore.freshPoints}", BananaTheme.cyan, Modifier.weight(1f))
        }
        Column(verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.padding(top = 6.dp)) {
            EndButton(L("Return to top", "Về đầu trang"), Icons.Filled.VerticalAlignTop, true, onTop)
            EndButton(L("Reshuffle", "Xáo lại"), Icons.Filled.Shuffle, false, onReshuffle)
        }
    }
}

@Composable
private fun EndStat(title: String, value: String, color: Color, modifier: Modifier) {
    Column(modifier.background(Color.White.op(0.05), RoundedCornerShape(18.dp)).padding(vertical = 18.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(value, style = ts(30.0, FontWeight.Black, color), maxLines = 1)
        Text(title, style = ts(11.0, FontWeight.ExtraBold, Color.White.op(0.6), spacing = 1.0), maxLines = 1)
    }
}

@Composable
private fun EndButton(title: String, icon: ImageVector, filled: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().background(if (filled) BananaTheme.banana else Color.White.op(0.12), RoundedCornerShape(16.dp))
            .clickable(onClick = onClick).padding(vertical = 15.dp),
        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically
    ) {
        val c = if (filled) Color.Black else Color.White
        Icon(icon, null, tint = c, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(8.dp))
        Text(title, style = ts(17.0, FontWeight.Bold, c))
    }
}
