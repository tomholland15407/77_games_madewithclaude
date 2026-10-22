//
//  StatsStore.swift
//  GOGs
//
//  The "unrot your brain" scoreboard. Tracks two point pools — Smart (earned on
//  .brain games) and Fresh (earned on .reflex games) — plus a daily streak and
//  the player's best streak ever. Points are awarded on every win and scale with
//  the level beaten (10 × level). Persisted so it all survives relaunches.
//

import SwiftUI
import Observation

@Observable
final class StatsStore {

    /// Points earned on brain games (thinking / memory).
    private(set) var smartPoints: Int = 0
    /// Points earned on reflex games (fast / twitch).
    private(set) var freshPoints: Int = 0
    /// Consecutive calendar days the player has won at least one level.
    private(set) var currentStreak: Int = 0
    /// The longest daily streak ever reached.
    private(set) var bestStreak: Int = 0

    /// The last day (in whole days since the reference date) the player won on.
    /// -1 means "never". Used to advance/reset the daily streak.
    private var lastActiveDay: Int = -1

    private enum Key {
        static let smart = "statsSmartPoints"
        static let fresh = "statsFreshPoints"
        static let streak = "statsCurrentStreak"
        static let best = "statsBestStreak"
        static let lastDay = "statsLastActiveDay"
    }

    init() {
        let d = UserDefaults.standard
        smartPoints = d.integer(forKey: Key.smart)
        freshPoints = d.integer(forKey: Key.fresh)
        currentStreak = d.integer(forKey: Key.streak)
        bestStreak = d.integer(forKey: Key.best)
        lastActiveDay = d.object(forKey: Key.lastDay) as? Int ?? -1
    }

    /// Total points across both pools.
    var totalPoints: Int { smartPoints + freshPoints }

    /// The number of whole days since the reference date, in the current calendar.
    private var today: Int {
        let start = Calendar.current.startOfDay(for: Date())
        return Int(start.timeIntervalSinceReferenceDate / 86_400)
    }

    /// Awards points for a win and advances the daily streak. Points scale with the
    /// level beaten: `10 × level`. Smart for brain games, Fresh for reflex games.
    func award(genre: Genre, level: Int) {
        let points = 10 * max(1, level)
        switch genre {
        case .brain:  smartPoints += points
        case .reflex: freshPoints += points
        }
        registerActivityToday()
        persist()
    }

    /// Updates the daily streak for a win happening "now". Same-day wins don't move
    /// it; a win the very next day extends it; any longer gap restarts it at 1.
    private func registerActivityToday() {
        let day = today
        if lastActiveDay == day {
            // already counted today
        } else if lastActiveDay == day - 1 {
            currentStreak += 1
        } else {
            currentStreak = 1
        }
        lastActiveDay = day
        bestStreak = max(bestStreak, currentStreak)
    }

    private func persist() {
        let d = UserDefaults.standard
        d.set(smartPoints, forKey: Key.smart)
        d.set(freshPoints, forKey: Key.fresh)
        d.set(currentStreak, forKey: Key.streak)
        d.set(bestStreak, forKey: Key.best)
        d.set(lastActiveDay, forKey: Key.lastDay)
    }
}
