//
//  BananaGameApp.swift
//  A Banana Game
//
//  The app's entry point. Uses the modern SwiftUI lifecycle: no storyboard,
//  no AppDelegate — just a WindowGroup showing our root view.
//

import SwiftUI

@main
struct BananaGameApp: App {

    // Shared app-wide services, injected into the environment so any view can use them.
    @State private var favorites = FavoritesStore()
    @State private var sound = SoundManager.shared
    @State private var settings = AppSettings()
    @State private var progress = ProgressStore()
    @State private var stats = StatsStore()
    @State private var updater = UpdateChecker()

    init() {
        // Resolve the display language early (device-default on first launch, else the
        // persisted in-app choice). Touching `shared` runs its init.
        _ = Localization.shared

        // Build Klotski's one-time distance map in the background at launch so scrolling to that
        // game never hitches on the first encounter.
        KlotskiGame.prewarm()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(favorites)
                .environment(sound)
                .environment(settings)
                .environment(progress)
                .environment(stats)
                .environment(updater)
                .preferredColorScheme(.dark)   // black, TikTok-style
        }
    }
}
