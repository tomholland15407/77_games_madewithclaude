//
//  BoardCache.swift
//  A Banana Game
//
//  Pre-builds puzzle boards so generation-heavy games start the instant "GO" lands.
//
//  `GamePageView` asks a game to `prefetch` its board when the 3·2·1 countdown starts (and, on a
//  win, the NEXT level's board while the reward overlay is up). The game's `run()` then `take`s
//  that board instead of generating it after the countdown, so the "brainstorming" page is only
//  shown when a build is genuinely still running. Boards come from the exact same generator with
//  the exact same parameters as before — only WHEN they are built changes, never what they hold.
//

import Foundation

enum BoardCache {
    private struct Entry {
        let task: Task<Any, Never>
        let created: Date
    }

    /// In-flight or finished-but-unclaimed builds, keyed by `key(_:level:)`.
    private static var entries: [String: Entry] = [:]

    /// Cache key for one game's level. Every level's parameters derive from the level number, so
    /// game id + level pins down the generator inputs.
    static func key(_ gameID: String, level: Int) -> String { "\(gameID)#\(level)" }

    /// Start building the board for `key` off the main actor. A no-op while a build for the same
    /// key is already running or waiting to be claimed. Low priority: it has the whole countdown
    /// (~2s) to finish and must never starve the countdown animation.
    static func prefetch<T>(_ key: String, _ make: @escaping @Sendable () -> T) {
        if entries[key] != nil { return }
        evictStale()
        entries[key] = Entry(task: Task.detached(priority: .utility) { make() as Any }, created: Date())
    }

    /// Claim the board for `key`: the prefetched one if there is one (waiting for it if it is still
    /// building), otherwise a fresh build right now at user-initiated priority. The entry is consumed.
    static func take<T>(_ key: String, _ make: @escaping @Sendable () -> T) async -> T {
        if let entry = entries.removeValue(forKey: key),
           let value = await entry.task.value as? T {
            return value
        }
        return await Task.detached(priority: .userInitiated) { make() }.value
    }

    /// Keep the "brainstorming" page up for a minimum beat — but only when it actually appeared.
    /// A prefetched board resolves in a few milliseconds, and holding the page then would be dead
    /// air between "GO" and the puzzle.
    static func holdBrainstorm(since t0: Date, minimum: Double) async {
        let elapsed = Date().timeIntervalSince(t0)
        if elapsed > 0.05 && elapsed < minimum {
            try? await Task.sleep(for: .seconds(minimum - elapsed))
        }
    }

    /// Drop builds nobody claimed (e.g. the player swiped away during the countdown).
    private static func evictStale() {
        let now = Date()
        entries = entries.filter { now.timeIntervalSince($0.value.created) < 120 }
    }
}
