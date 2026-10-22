//
//  FavoritesStore.swift
//  A Banana Game
//
//  Keeps track of which games the user has ❤️'d. Persists to disk
//  (UserDefaults) so favorites survive relaunches.
//

import SwiftUI
import Observation

@Observable
final class FavoritesStore {

    /// The set of favorited game IDs. Private setter — change it via `toggle`.
    private(set) var ids: Set<String> = []

    private let key = "favoriteGameIDs"

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: key) ?? []
        ids = Set(saved)
    }

    func isFavorite(_ id: String) -> Bool {
        ids.contains(id)
    }

    func toggle(_ id: String) {
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        UserDefaults.standard.set(Array(ids), forKey: key)
    }
}
