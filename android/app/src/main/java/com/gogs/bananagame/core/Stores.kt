package com.gogs.bananagame.core

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

// ---------------------------------------------------------------------------------------------
// Localization (iOS Localization.swift): English / Vietnamese with an in-app toggle.
// ---------------------------------------------------------------------------------------------

enum class AppLanguage(val raw: String, val displayName: String) {
    EN("en", "English"), VI("vi", "Tiếng Việt");
}

object Localization {
    private const val KEY = "appLanguage"
    private var langState by mutableStateOf(AppLanguage.EN)

    var lang: AppLanguage
        get() = langState
        set(value) {
            if (value == langState) return
            langState = value
            Prefs.putString(KEY, value.raw)
        }

    fun init() {
        val saved = Prefs.getString(KEY)
        langState = AppLanguage.entries.firstOrNull { it.raw == saved }
            ?: if (Locale.getDefault().language.lowercase().startsWith("vi")) AppLanguage.VI else AppLanguage.EN
    }
}

/** Returns the string for the current language. Vietnamese falls back to English when empty. */
fun L(en: String, vi: String): String = when (Localization.lang) {
    AppLanguage.EN -> en
    AppLanguage.VI -> vi.ifEmpty { en }
}

// ---------------------------------------------------------------------------------------------
// FavoritesStore / ProgressStore / StatsStore
// ---------------------------------------------------------------------------------------------

object FavoritesStore {
    private const val KEY = "favoriteGameIDs"
    var ids by mutableStateOf(emptySet<String>())
        private set

    fun init() { ids = Prefs.getStringSet(KEY) }
    fun isFavorite(id: String) = id in ids
    fun toggle(id: String) {
        ids = if (id in ids) ids - id else ids + id
        Prefs.putStringSet(KEY, ids)
    }
}

object ProgressStore {
    private const val KEY = "masteredGameIDs"
    var mastered by mutableStateOf(emptySet<String>())
        private set

    fun init() { mastered = Prefs.getStringSet(KEY) }
    fun isMastered(id: String) = id in mastered
    fun markMastered(id: String) {
        if (id in mastered) return
        mastered = mastered + id
        Prefs.putStringSet(KEY, mastered)
    }
}

object StatsStore {
    var smartPoints by mutableIntStateOf(0); private set
    var freshPoints by mutableIntStateOf(0); private set
    var currentStreak by mutableIntStateOf(0); private set
    var bestStreak by mutableIntStateOf(0); private set
    private var lastActiveDay = -1

    fun init() {
        smartPoints = Prefs.getInt("statsSmartPoints") ?: 0
        freshPoints = Prefs.getInt("statsFreshPoints") ?: 0
        currentStreak = Prefs.getInt("statsCurrentStreak") ?: 0
        bestStreak = Prefs.getInt("statsBestStreak") ?: 0
        lastActiveDay = Prefs.getInt("statsLastActiveDay") ?: -1
    }

    val totalPoints get() = smartPoints + freshPoints

    /** Whole local days since the epoch. */
    private val today: Int
        get() {
            val c = Calendar.getInstance()
            val offset = TimeZone.getDefault().getOffset(c.timeInMillis)
            return ((c.timeInMillis + offset) / 86_400_000L).toInt()
        }

    /** Awards `10 × level` points (Smart for brain, Fresh for reflex) and advances the streak. */
    fun award(genre: Genre, level: Int) {
        val points = 10 * maxOf(1, level)
        when (genre) {
            Genre.BRAIN -> smartPoints += points
            Genre.REFLEX -> freshPoints += points
        }
        val day = today
        if (lastActiveDay == day) {
            // already counted today
        } else if (lastActiveDay == day - 1) currentStreak += 1 else currentStreak = 1
        lastActiveDay = day
        bestStreak = maxOf(bestStreak, currentStreak)
        Prefs.putInt("statsSmartPoints", smartPoints)
        Prefs.putInt("statsFreshPoints", freshPoints)
        Prefs.putInt("statsCurrentStreak", currentStreak)
        Prefs.putInt("statsBestStreak", bestStreak)
        Prefs.putInt("statsLastActiveDay", lastActiveDay)
    }
}

// ---------------------------------------------------------------------------------------------
// AppSettings: feed filter, genre weights, last game, remembered per-mode orders + positions.
// ---------------------------------------------------------------------------------------------

enum class FeedFilter(val raw: String) {
    ALL("all"), FAVORITES("favorites"), UNPLAYED("unplayed");

    val label: String
        get() = when (this) {
            ALL -> L("All", "Tất cả")
            FAVORITES -> L("Favorites", "Yêu thích")
            UNPLAYED -> L("Unplayed", "Chưa chơi")
        }
}

object AppSettings {
    const val NORMAL_WEIGHT = 2
    val weightRange = 0..3

    private var filterState by mutableStateOf(FeedFilter.ALL)
    var feedFilter: FeedFilter
        get() = filterState
        set(v) { filterState = v; Prefs.putString("feedFilter", v.raw) }

    val genreWeights = mutableStateMapOf<Genre, Int>()

    var lastGameID: String? = null
        set(v) { field = v; Prefs.putString("lastGameID", v) }

    private val orders = HashMap<String, List<String>>()
    private val positions = HashMap<String, String>()

    fun init() {
        val raw = Prefs.getString("feedFilter")
        filterState = FeedFilter.entries.firstOrNull { it.raw == raw } ?: FeedFilter.ALL
        lastGameID = Prefs.getString("lastGameID")
        orders.putAll(Prefs.getStringListMap("feedOrders"))
        positions.putAll(Prefs.getStringMap("feedPositions"))
        val saved = Prefs.getStringMap("genreWeights")
        for (g in Genre.entries) genreWeights[g] = saved[g.raw]?.toIntOrNull() ?: NORMAL_WEIGHT
    }

    fun weight(genre: Genre) = genreWeights[genre] ?: NORMAL_WEIGHT

    fun setWeight(value: Int, genre: Genre) {
        genreWeights[genre] = value.coerceIn(weightRange)
        Prefs.putStringMap("genreWeights", genreWeights.entries.associate { it.key.raw to it.value.toString() })
    }

    fun feedOrder(mode: FeedFilter): List<String>? = orders[mode.raw]
    fun setFeedOrder(mode: FeedFilter, ids: List<String>) {
        orders[mode.raw] = ids
        Prefs.putStringListMap("feedOrders", orders)
    }

    fun feedPosition(mode: FeedFilter): String? = positions[mode.raw]
    fun setFeedPosition(mode: FeedFilter, id: String?) {
        if (id == null) positions.remove(mode.raw) else positions[mode.raw] = id
        Prefs.putStringMap("feedPositions", positions)
    }
}
