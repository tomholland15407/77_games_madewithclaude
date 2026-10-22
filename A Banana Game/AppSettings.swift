//
//  AppSettings.swift
//  GOGs
//
//  User-tweakable settings that shape the feed: which games are shown
//  (the feed filter) and how often each genre appears (genre weights).
//  Persisted to UserDefaults so choices stick between launches.
//

import SwiftUI
import Observation

/// Which slice of the catalog the feed shows.
enum FeedFilter: String, CaseIterable, Identifiable {
    case all, favorites, unplayed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:       return L("All", "Tất cả")
        case .favorites: return L("Favorites", "Yêu thích")
        case .unplayed:  return L("Unplayed", "Chưa chơi")
        }
    }
}

@MainActor
@Observable
final class AppSettings {

    /// Normal weight — the default for every genre.
    static let normalWeight = 2
    /// Valid genre weights: 0 (hidden) … 3 (high).
    static let weightRange = 0...3

    /// Which games the feed shows.
    var feedFilter: FeedFilter {
        didSet { UserDefaults.standard.set(feedFilter.rawValue, forKey: filterKey) }
    }
    private let filterKey = "feedFilter"

    /// Per-genre weight (0 hides the genre, higher = appears nearer the top).
    private(set) var genreWeights: [Genre: Int]
    private let weightsKey = "genreWeights"

    /// The id of the game the player was last on. Persisted so a cold launch can
    /// offer to jump back to it ("Return to previous game?").
    var lastGameID: String? {
        didSet {
            if let lastGameID {
                UserDefaults.standard.set(lastGameID, forKey: lastGameKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastGameKey)
            }
        }
    }
    private let lastGameKey = "lastGameID"

    /// Each mode's remembered ordering, stored as game ids keyed by the mode's raw
    /// value. Persisted so the feed order survives a cold launch (otherwise every
    /// launch reshuffled and "return to previous game" landed in a new order).
    var feedOrders: [String: [String]] {
        didSet { UserDefaults.standard.set(feedOrders, forKey: ordersKey) }
    }
    private let ordersKey = "feedOrders"

    /// The game each mode was last on (mode raw value → game id). Persisted alongside
    /// `feedOrders` so switching back to a mode — or relaunching — restores the spot.
    var feedPositions: [String: String] {
        didSet { UserDefaults.standard.set(feedPositions, forKey: positionsKey) }
    }
    private let positionsKey = "feedPositions"

    init() {
        let rawFilter = UserDefaults.standard.string(forKey: filterKey) ?? FeedFilter.all.rawValue
        feedFilter = FeedFilter(rawValue: rawFilter) ?? .all
        lastGameID = UserDefaults.standard.string(forKey: lastGameKey)
        feedOrders = UserDefaults.standard.dictionary(forKey: ordersKey) as? [String: [String]] ?? [:]
        feedPositions = UserDefaults.standard.dictionary(forKey: positionsKey) as? [String: String] ?? [:]

        if let saved = UserDefaults.standard.dictionary(forKey: weightsKey) as? [String: Int] {
            var restored: [Genre: Int] = [:]
            for genre in Genre.allCases {
                restored[genre] = saved[genre.rawValue] ?? Self.normalWeight
            }
            genreWeights = restored
        } else {
            genreWeights = Dictionary(uniqueKeysWithValues:
                Genre.allCases.map { ($0, Self.normalWeight) })
        }
    }

    func weight(for genre: Genre) -> Int {
        genreWeights[genre] ?? Self.normalWeight
    }

    func setWeight(_ value: Int, for genre: Genre) {
        let clamped = min(Self.weightRange.upperBound, max(Self.weightRange.lowerBound, value))
        genreWeights[genre] = clamped
        let raw = Dictionary(uniqueKeysWithValues:
            genreWeights.map { ($0.key.rawValue, $0.value) })
        UserDefaults.standard.set(raw, forKey: weightsKey)
    }
}
