//
//  Theme.swift
//  A Banana Game
//
//  Shared colors and tiny helpers (haptics) used across every game.
//

import SwiftUI
import UIKit

/// The app's visual identity: black background, banana yellow accent.
enum BananaTheme {
    static let background = Color.black
    static let banana = Color(red: 1.0, green: 0.86, blue: 0.2)
    static let subtle = Color.white.opacity(0.5)
}

/// Small wrapper around haptic feedback so games can add "feel" in one line.
enum Haptics {
    /// Transient silence used while a manual's live demo is on screen, so a demo that
    /// drives a game's real functions doesn't buzz. Set by `LiveDemoView`.
    nonisolated(unsafe) static var suppressed = false

    /// A light bump — good for taps and hits.
    static func tap() {
        guard !suppressed else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// A celebratory buzz — good for beating a level.
    static func success() {
        guard !suppressed else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// A warning buzz — good for mistakes ("too soon!").
    static func warning() {
        guard !suppressed else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
