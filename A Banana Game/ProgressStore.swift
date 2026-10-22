//
//  ProgressStore.swift
//  GOGs
//
//  Tracks which games the player has "mastered" — i.e. beaten every level
//  (won the final level). Used by the feed's "Unplayed" filter, which shows
//  only games not yet mastered. Persisted so progress survives relaunches.
//

import SwiftUI
import Observation

@Observable
final class ProgressStore {

    /// The ids of games whose last level has been beaten.
    private(set) var mastered: Set<String> = []

    private let key = "masteredGameIDs"

    init() {
        mastered = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    func isMastered(_ id: String) -> Bool {
        mastered.contains(id)
    }

    /// Marks a game as mastered (idempotent). Call when the final level is won.
    func markMastered(_ id: String) {
        guard !mastered.contains(id) else { return }
        mastered.insert(id)
        UserDefaults.standard.set(Array(mastered), forKey: key)
    }
}
