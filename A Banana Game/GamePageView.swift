//
//  GamePageView.swift
//  A Banana Game
//
//  One page in the feed. It hosts a game, shows the header + level, the ❤️ button,
//  runs a 3·2·1 auto-start countdown, celebrates wins (→ next level), and punishes
//  fails (→ back to level 1, "rage bait" style).
//

import SwiftUI

struct GamePageView: View {
    let game: GameDefinition
    /// True only when this is the game currently on screen in the feed.
    let isActive: Bool
    /// Safe-area insets handed down from the feed (page is full-bleed).
    let topInset: CGFloat
    let bottomInset: CGFloat
    /// The feed's shared paging lock. This page drives it (see `shouldLockFeed`)
    /// so a swipe/drag game's gestures don't fight the pager while playing.
    @Binding var isPagingLocked: Bool
    /// Advances the feed to the next game. Powers the skip button that lets a
    /// player leave a feed-locking game even while manual swipes are blocked.
    let onSkip: () -> Void

    @Environment(FavoritesStore.self) private var favorites
    @Environment(ProgressStore.self) private var progress
    @Environment(StatsStore.self) private var stats

    @State private var level = 1
    // Bumped on every fresh attempt (win→next, or fail→reset) so the game view
    // is recreated and the countdown re-runs — even when the level number repeats.
    @State private var runID = 0
    @State private var showReward = false
    @State private var showFail = false
    @State private var isCountingDown = true
    @State private var countdownValue = 3
    // True while the manual sheet is up. Opening it removes the game view (see
    // `gameArea`), which stops the game's loop; closing it restarts the level's
    // countdown from the top.
    @State private var showManual = false

    private var isLastLevel: Bool { level >= game.levelCount }

    /// True only while this page is actively playing a feed-locking game — i.e.
    /// past the countdown and not showing a win/fail overlay. The countdown and
    /// overlays deliberately leave the feed unlocked so the player can swipe away.
    private var shouldLockFeed: Bool {
        isActive && game.locksFeed && !isCountingDown && !showReward && !showFail && !showManual
    }

    var body: some View {
        ZStack {
            BananaTheme.background

            VStack(spacing: 12) {
                header
                gameArea
            }
            // Use the real safe-area inset, but never less than 60pt so the
            // title always clears the Dynamic Island / notch on any phone.
            .padding(.top, max(topInset, 60) + 8)
            .padding(.bottom, max(bottomInset, 12))

            // Skip button — only for feed-locking games, whose paging lock would
            // otherwise trap the player. Bottom-center, clear of the ❤️ (bottom-right).
            if game.locksFeed && isActive && !showReward && !showFail {
                VStack {
                    Spacer()
                    skipButton
                }
                .padding(.bottom, bottomInset + 24)
            }

            if isCountingDown {
                countdownOverlay
            }
            if showReward {
                RewardBurstView()
                    .allowsHitTesting(false)
                completionOverlay
                    .transition(.opacity)
            }
            if showFail {
                failOverlay
                    .transition(.opacity)
            }
        }
        // Runs when this page becomes active, and on every fresh attempt (runID).
        .task(id: "\(runID)-\(isActive)") {
            guard isActive else {
                // Off-screen — stay idle and reset so it starts fresh on return.
                // Always drop back to level 1: no game should remember its level.
                level = 1
                showReward = false
                showFail = false
                countdownValue = 3
                isCountingDown = true
                return
            }
            await runCountdown()
        }
        // Keep the feed's paging lock in sync with this page's play state.
        // Only the active, playing page ever changes `shouldLockFeed`, so idle
        // pages never clobber the shared lock.
        .onChange(of: shouldLockFeed) { _, locked in
            isPagingLocked = locked
        }
        // The manual. Opening it stops the game (the game view is dropped from
        // `gameArea`); closing it restarts the current level from its countdown.
        .fullScreenCover(isPresented: $showManual, onDismiss: restartLevel) {
            if let manual = game.manual {
                GameManualView(game: game, manual: manual) {
                    showManual = false
                }
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 6) {
            // Title + ❤️ inline, so the heart never sits on top of a game's
            // controls (it used to float bottom-right and block some buttons).
            HStack(spacing: 10) {
                // Book on the left, heart on the right — equal-size circles flanking the
                // title so it stays centered. (Reserve the left slot even when a game has
                // no manual, so the title never shifts off-center.)
                if game.manual != nil { manualButton } else { headerSlot }
                Spacer(minLength: 8)
                Text(game.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                favoriteButton
            }
            Text(L("LEVEL \(level) / \(game.levelCount)", "CẤP \(level) / \(game.levelCount)"))
                .font(.caption.weight(.heavy))
                .tracking(3)
                .foregroundStyle(BananaTheme.banana)
        }
        .padding(.top, 8)
    }

    /// The play area. The game is only created once the countdown ends, so it
    /// can't start early. Recreated on each attempt via `.id(runID)`.
    @ViewBuilder
    private var gameArea: some View {
        ZStack {
            // Dropping the game view while the manual is open stops its loop.
            if !isCountingDown && !showManual {
                game.makeView(level, { handleWin() }, { handleFail() })
                    .id(runID)
                    .disabled(showReward || showFail)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var favoriteButton: some View {
        let faved = favorites.isFavorite(game.id)
        return Button {
            favorites.toggle(game.id)
            Haptics.tap()
            SoundManager.shared.tap()
        } label: {
            Image(systemName: faved ? "heart.fill" : "heart")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(faved ? BananaTheme.banana : .white)
                .padding(8)
                .background(.white.opacity(0.08), in: Circle())
                .scaleEffect(faved ? 1.1 : 1.0)
                .animation(.spring(duration: 0.3), value: faved)
        }
    }

    /// An empty circle the size of the book/heart buttons, used to balance the header
    /// when a game has no manual so the centered title doesn't drift.
    private var headerSlot: some View {
        Color.clear.frame(width: 38, height: 38)
    }

    private var manualButton: some View {
        Button {
            Haptics.tap()
            SoundManager.shared.tap()
            showManual = true
        } label: {
            Image(systemName: "book.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .padding(8)
                .background(.white.opacity(0.08), in: Circle())
        }
    }

    private var skipButton: some View {
        Button {
            Haptics.tap()
            SoundManager.shared.tap()
            onSkip()
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .padding(14)
                .background(.white.opacity(0.08), in: Circle())
        }
    }

    private var countdownOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
            Text("\(countdownValue)")
                .font(.system(size: 130, weight: .black, design: .rounded))
                .foregroundStyle(BananaTheme.banana)
                .id(countdownValue)   // replace the view each tick so it pops
                .transition(.scale(scale: 1.6).combined(with: .opacity))
        }
        .ignoresSafeArea()
    }

    private var completionOverlay: some View {
        VStack(spacing: 22) {
            Text(isLastLevel
                 ? L("You beat every level!", "Bạn đã vượt qua mọi cấp!")
                 : L("Level \(level) complete!", "Hoàn thành cấp \(level)!"))
                .font(.title.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Button {
                advance()
            } label: {
                Text(isLastLevel
                     ? L("Play again", "Chơi lại")
                     : L("Next Level  ▶", "Cấp tiếp theo  ▶"))
                    .font(.headline.bold())
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(BananaTheme.banana, in: Capsule())
                    .foregroundStyle(.black)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.75))
    }

    private var failOverlay: some View {
        VStack(spacing: 14) {
            Text(L("FAILED", "THẤT BẠI"))
                .font(.system(size: 46, weight: .black, design: .rounded))
                .foregroundStyle(.red)
            Text(L("Back to Level 1", "Về cấp 1"))
                .font(.title3.bold())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.8))
    }

    // MARK: - Flow

    private func runCountdown() async {
        showReward = false
        showFail = false
        isCountingDown = true
        // Build this level's board while the 3·2·1 runs so the game opens on "GO", and start the
        // next level's too — it has the whole play session to finish, so even the slowest
        // generators are ready by the time the player wins.
        game.prefetch?(level)
        if level < game.levelCount { game.prefetch?(level + 1) }
        for n in stride(from: 3, through: 1, by: -1) {
            withAnimation(.spring(duration: 0.25)) { countdownValue = n }
            SoundManager.shared.countdownTick()
            try? await Task.sleep(for: .seconds(0.65))
        }
        withAnimation(.easeOut(duration: 0.2)) { isCountingDown = false }
        SoundManager.shared.countdownGo()
    }

    private func handleWin() {
        guard !showReward, !showFail else { return }
        Haptics.success()
        SoundManager.shared.success()
        // Award points for the win (scales with the level beaten) and advance the
        // daily streak. Smart for brain games, Fresh for reflex games.
        stats.award(genre: game.genre, level: level)
        withAnimation(.spring(duration: 0.4)) { showReward = true }
        // Start the next level's board now, under the celebration.
        if !isLastLevel { game.prefetch?(level + 1) }
        // Beating the final level means the game is "mastered" (leaves Unplayed).
        // Mark it after a short beat so the "You beat every level!" celebration is
        // seen before the Unplayed feed removes this game and auto-advances.
        if isLastLevel {
            Task {
                try? await Task.sleep(for: .seconds(1.1))
                progress.markMastered(game.id)
            }
        }
    }

    private func handleFail() {
        guard !showReward, !showFail else { return }
        Haptics.warning()
        SoundManager.shared.error()
        withAnimation(.spring(duration: 0.3)) { showFail = true }
        game.prefetch?(1)   // the retry starts at level 1 — build it under the FAILED overlay
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            // The level and the fresh game view (runID) must change in the same update. withAnimation
            // flushes pending changes first, so a level change on its own would re-render the outgoing
            // game once with the new level but its old state (Tower of Hanoi crashed on exactly that).
            level = 1
            runID += 1   // fresh attempt: recreate game + re-run countdown
            withAnimation(.easeInOut) { showFail = false }
        }
    }

    private func advance() {
        level = isLastLevel ? 1 : level + 1
        runID += 1   // in the same update as the level change (see handleFail)
        withAnimation(.easeInOut) { showReward = false }
    }

    /// Called after the manual sheet is dismissed: replay the current level from
    /// its 3·2·1 countdown (a fresh attempt, same level).
    private func restartLevel() {
        guard isActive else { return }
        showReward = false
        showFail = false
        runID += 1   // recreates the game view and re-runs the countdown
    }
}
