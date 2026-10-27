package com.gogs.bananagame.core

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/**
 * Pre-builds puzzle boards so generation-heavy games start the instant "GO" lands (iOS BoardCache).
 * Same generators, same parameters — only WHEN a board is built changes.
 */
object BoardCache {
    private class Entry(val job: Deferred<Any?>, val created: Long)

    private val entries = HashMap<String, Entry>()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    fun key(gameID: String, level: Int) = "$gameID#$level"

    @Synchronized
    fun <T> prefetch(key: String, make: () -> T) {
        if (entries[key] != null) return
        evictStale()
        entries[key] = Entry(scope.async { make() }, System.currentTimeMillis())
    }

    /** Claim the board for `key`: the prefetched one (awaiting it), else build it now off the main thread. */
    @Suppress("UNCHECKED_CAST")
    suspend fun <T> take(key: String, make: () -> T): T {
        val entry = synchronized(this) { entries.remove(key) }
        if (entry != null) {
            val v = runCatching { entry.job.await() }.getOrNull()
            if (v != null) return v as T
        }
        return withContext(Dispatchers.Default) { make() }
    }

    /** Keep the "brainstorming" page up for a minimum beat — only when it actually appeared. */
    suspend fun holdBrainstorm(sinceMillis: Long, minimum: Double) {
        val elapsed = (System.currentTimeMillis() - sinceMillis) / 1000.0
        if (elapsed > 0.05 && elapsed < minimum) delay(((minimum - elapsed) * 1000).toLong())
    }

    private fun evictStale() {
        val now = System.currentTimeMillis()
        entries.entries.removeAll { now - it.value.created > 120_000 }
    }
}

/** Per-key shuffle bag so restarts never serve the same curated item twice in a row (iOS ShuffleBag). */
object ShuffleBag {
    private val bags = HashMap<String, MutableList<Int>>()
    private val last = HashMap<String, Int>()

    @Synchronized
    fun next(key: String, count: Int): Int {
        if (count <= 1) return 0
        var bag = bags[key] ?: mutableListOf()
        if (bag.isEmpty()) {
            bag = (0 until count).shuffled().toMutableList()
            val previous = last[key]
            if (previous != null && bag.first() == previous) {
                val t = bag[0]; bag[0] = bag[bag.size - 1]; bag[bag.size - 1] = t
            }
        }
        val index = bag.removeAt(0)
        bags[key] = bag
        last[key] = index
        return index
    }
}
