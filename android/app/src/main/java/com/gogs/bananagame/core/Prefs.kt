package com.gogs.bananagame.core

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.stringSetPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

private val Context.gogsStore: DataStore<Preferences> by preferencesDataStore(name = "gogs")

/**
 * The UserDefaults/AppStorage replacement: a Preferences DataStore. The whole store is read once,
 * synchronously, at launch (it is tiny) into an in-memory snapshot, so the stores can initialise
 * like their iOS `init()`s did; every write updates the snapshot and is persisted asynchronously.
 */
object Prefs {
    private lateinit var store: DataStore<Preferences>
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var snapshot: Preferences? = null

    fun init(context: Context) {
        store = context.applicationContext.gogsStore
        snapshot = runBlocking(Dispatchers.IO) { store.data.first() }
    }

    private fun write(block: (MutablePreferences) -> Unit) {
        if (!::store.isInitialized) return
        snapshot = snapshot?.toMutablePreferences()?.also(block)
        scope.launch { store.edit { block(it) } }
    }

    fun getBool(key: String, default: Boolean): Boolean = snapshot?.get(booleanPreferencesKey(key)) ?: default
    fun putBool(key: String, value: Boolean) = write { it[booleanPreferencesKey(key)] = value }

    fun getInt(key: String): Int? = snapshot?.get(intPreferencesKey(key))
    fun putInt(key: String, value: Int) = write { it[intPreferencesKey(key)] = value }

    fun getString(key: String): String? = snapshot?.get(stringPreferencesKey(key))
    fun putString(key: String, value: String?) = write {
        if (value == null) it.remove(stringPreferencesKey(key)) else it[stringPreferencesKey(key)] = value
    }

    fun getStringSet(key: String): Set<String> = snapshot?.get(stringSetPreferencesKey(key)) ?: emptySet()
    fun putStringSet(key: String, value: Set<String>) = write { it[stringSetPreferencesKey(key)] = value }

    // Dictionaries (UserDefaults dictionaries on iOS) are encoded as simple delimited strings.
    // Game ids and mode names never contain the delimiters.

    fun getStringListMap(key: String): Map<String, List<String>> {
        val raw = getString(key) ?: return emptyMap()
        return raw.split('\n').filter { it.contains('=') }.associate { line ->
            val k = line.substringBefore('=')
            val v = line.substringAfter('=')
            k to (if (v.isEmpty()) emptyList() else v.split(','))
        }
    }

    fun putStringListMap(key: String, map: Map<String, List<String>>) =
        putString(key, map.entries.joinToString("\n") { "${it.key}=${it.value.joinToString(",")}" })

    fun getStringMap(key: String): Map<String, String> {
        val raw = getString(key) ?: return emptyMap()
        return raw.split('\n').filter { it.contains('=') }.associate { it.substringBefore('=') to it.substringAfter('=') }
    }

    fun putStringMap(key: String, map: Map<String, String>) =
        putString(key, map.entries.joinToString("\n") { "${it.key}=${it.value}" })
}
