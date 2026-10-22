//
//  ShuffleBag.swift
//  A Banana Game
//
//  A per-key "shuffle bag" used by the curated-content games (Millionaire, Average,
//  Uncle Roger, …) so that failing and restarting at level 1 never serves the same
//  question again. Each key hands out every index of its pool in random order, and only
//  reshuffles once the whole pool is exhausted — and it avoids repeating the just-used
//  index across a reshuffle. In-memory only (resets on app relaunch), which is all we need
//  to keep a single session's restarts feeling fresh.
//

import Foundation

@MainActor
final class ShuffleBag {
    static let shared = ShuffleBag()
    private init() {}

    private var bags: [String: [Int]] = [:]
    private var last: [String: Int] = [:]

    /// Returns the next index in `0..<count` for `key`, drawing without repeats until the
    /// pool is used up, then reshuffling (never immediately repeating the last index).
    func next(key: String, count: Int) -> Int {
        guard count > 1 else { return 0 }
        var bag = bags[key] ?? []
        if bag.isEmpty {
            bag = Array(0..<count).shuffled()
            if let previous = last[key], bag.first == previous {
                bag.swapAt(0, bag.count - 1)   // don't repeat the last handed-out item
            }
        }
        let index = bag.removeFirst()
        bags[key] = bag
        last[key] = index
        return index
    }
}
