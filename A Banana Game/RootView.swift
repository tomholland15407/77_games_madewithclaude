//
//  RootView.swift
//  A Banana Game
//
//  Shows a quick banana splash, then drops the user into the feed. On a cold
//  launch where the player was mid-session, the splash also offers to jump back
//  to the game they were last on ("Return to previous game?").
//

import SwiftUI

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(UpdateChecker.self) private var updater

    @State private var showSplash = true
    // The game to open the feed on. Set when the player taps "Return", left nil
    // for a fresh start (top of the feed).
    @State private var resumeID: String? = nil

    /// The saved last game, but only if it still exists in the catalog.
    private var lastGame: GameDefinition? {
        guard let id = settings.lastGameID else { return nil }
        return GameRegistry.all.first { $0.id == id }
    }

    var body: some View {
        ZStack {
            BananaTheme.background.ignoresSafeArea()

            if showSplash {
                SplashView(resumeGame: lastGame,
                           onResume: { start(resume: lastGame?.id) },
                           onStart: { start(resume: nil) })
                    .transition(.opacity)
            } else {
                FeedView(initialGameID: resumeID)
                    .transition(.opacity)
            }
        }
        // The update pop-up waits until the splash is gone, then sits over the feed (which
        // pauses its game while `launchPrompt` is set).
        .updatePrompt(Binding(
            get: { showSplash ? nil : updater.launchPrompt },
            set: { updater.launchPrompt = $0 }
        ))
        // Silent App Store check, started during the splash; never blocks the feed.
        .task { await updater.checkAtLaunch() }
        .statusBarHidden()   // fully immersive, TikTok-style
    }

    /// Leaves the splash and opens the feed, optionally on a specific game.
    private func start(resume id: String?) {
        resumeID = id
        withAnimation(.easeInOut(duration: 0.5)) { showSplash = false }
    }
}

/// The banana mascot splash screen. Always offers a pill **Start Fresh** button into the
/// feed; when `resumeGame` is set it also shows a "Return to …" button above it.
struct SplashView: View {
    var resumeGame: GameDefinition? = nil
    var onResume: () -> Void = {}
    var onStart: () -> Void = {}

    @State private var pop = false

    var body: some View {
        VStack(spacing: 16) {
            Text("🍌")
                .font(.system(size: 96))
                .scaleEffect(pop ? 1 : 0.5)
                // Rest pose is UPRIGHT (0°) and it spins a full turn to 360°. This way a frozen
                // cold-launch first frame shows a normal banana (not one held mid-tilt, which read
                // as "waiting to rotate"); the spin fires the moment the main thread is free.
                .rotationEffect(.degrees(pop ? 360 : 0))

            Text("GAME OF GAMES")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            // Keep "UNROT" English (brand word); translate only the rest.
            Text(L("UNROT YOUR BRAIN", "UNROT NÃO CỦA BẠN"))
                .font(.headline.weight(.heavy))
                .tracking(3)
                .foregroundStyle(BananaTheme.banana)

            controls
                .padding(.top, 32)
        }
        .onAppear {
            // easeOut starts at full velocity, so the spin begins instantly instead of the
            // spring's slow ease-in (which made the banana look like it paused before rotating).
            withAnimation(.easeOut(duration: 0.55)) { pop = true }
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            // Resume comes first (banana pill) when there's a game to return to.
            if let game = resumeGame {
                Button(action: onResume) {
                    Text(L("Return to \(game.title)", "Quay lại \(game.title)"))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(BananaTheme.banana, in: Capsule())
                }
            }

            // The pill "Start Fresh" button — the way into the feed from the landing.
            Button(action: onStart) {
                Text(L("Start Fresh", "Bắt đầu mới"))
                    .font(.headline.bold())
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(.white.opacity(0.12), in: Capsule())
                    .foregroundStyle(.white)
            }
        }
    }
}
