//
//  FeedView.swift
//  GOGs
//
//  The TikTok-style feed: a full-screen vertical pager. Each page is one game;
//  swipe up for the next. A top control cluster lets the player filter the feed
//  (All / Favorites / Unplayed), reshuffle, search for a game, and open settings.
//
//  Modes are **independent libraries**. Each of All / Favorites / Unplayed keeps
//  its own ordering and remembers the game the player was last on. Switching modes
//  restores that mode's order and position — it never reshuffles. Reshuffling the
//  *current* mode (and jumping to the top) happens three ways: the filter-menu
//  reshuffle button, the end-of-feed page's Reshuffle button, and pull-to-reshuffle
//  (over-scroll down at the very top to spin a banana a full turn).
//
//  Every mode also ends on a synthetic end page (`endID`) showing a stats recap plus
//  Return-to-top / Reshuffle. Skipping off the last game lands here (it never wraps
//  back to the top), and it's not a game so it's excluded from ordering/persistence.
//

import SwiftUI

struct FeedView: View {
    /// If set, the feed opens on this game instead of the top of the list. Used
    /// by the splash's "Return to previous game?" button on a cold launch.
    var initialGameID: String? = nil

    @Environment(FavoritesStore.self) private var favorites
    @Environment(ProgressStore.self) private var progress
    @Environment(AppSettings.self) private var settings
    @Environment(StatsStore.self) private var stats
    // Whether the app itself is foregrounded. Used to pause the on-screen game
    // (and its sounds) when the app is backgrounded or interrupted.
    @Environment(\.scenePhase) private var scenePhase

    // Which game is currently on screen. A page only starts its countdown when
    // it's the active one, so off-screen games don't run at launch.
    @State private var currentGameID: String?

    // One independent, remembered ordering per mode. Built lazily the first time a
    // mode is entered, then kept stable — genre changes only touch the tail below
    // the current game, and mode switches restore (never rebuild) these.
    @State private var orders: [FeedFilter: [GameDefinition]] = [:]
    // The game each mode was last on, so switching back to a mode lands the player
    // exactly where they left it.
    @State private var savedCurrent: [FeedFilter: String] = [:]

    // Set true by the active page while a swipe/drag game is being played, so the
    // pager stops competing with the game's gestures. Unlocked otherwise.
    @State private var isPagingLocked = false

    @Environment(UpdateChecker.self) private var updater
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showStats = false
    // The compact banana dropdown (top-right): tapping the banana spins it one full
    // turn and reveals the stats / search / settings buttons.
    @State private var menuOpen = false
    @State private var bananaSpin = 0.0

    // Set true by `jumpTo` when a search selection has to switch the mode. It tells
    // the mode `onChange` to skip its usual restore-to-remembered-position so it
    // doesn't clobber the game we're jumping to.
    @State private var suppressModeRestore = false
    // Set true for the duration of a mode switch so the "current game dropped out
    // of the filter" handler doesn't mistake the whole-list swap for a removal and
    // fight the restore.
    @State private var isSwitchingMode = false

    // A game id the pager must scroll to once, after the lazy rows exist. Set on a
    // cold-launch resume so we can land on the game at its EXACT (possibly deep,
    // mid-list) position — `.scrollPosition` alone doesn't reliably reach an
    // unrealized LazyVStack row on first appear, so we also drive ScrollViewReader.
    @State private var pendingResumeScroll: String? = nil
    // True from when a resume is requested until its deep-row scroll has settled. While set, the
    // pager's transient position write-backs are ignored (see currentGameBinding) so landing on a
    // mid-list row can't momentarily snap the current game — and its persistence — back to the top.
    @State private var resumeSettling = false

    // The synthetic "end of feed" page appended after the last game in every mode. Landing here
    // (by swiping past the last game or skipping off it) shows the stats recap + return/reshuffle.
    private static let endID = "__gogs_end__"

    // Pull-to-reshuffle: at the very top, over-scrolling down drags a banana that rotates with the
    // pull and reshuffles the current mode once it completes a full turn.
    @State private var pullProgress: CGFloat = 0     // 0 = none, 1 = a full turn (armed)
    @State private var pullArmed = false
    private let pullThreshold: CGFloat = 130

    /// The app is "attending" the feed only when foregrounded AND no sheet is up.
    /// A presented sheet doesn't change `scenePhase`, so we must check it here too,
    /// otherwise the game behind Settings/Search keeps looping and making sound. The launch
    /// update pop-up counts too, so the first game doesn't run (and fail) underneath it.
    private var isAttendingFeed: Bool {
        scenePhase == .active && !showSearch && !showSettings && !showStats
            && updater.launchPrompt == nil
    }

    /// The current mode's library, as shown on screen. It's the mode's stored
    /// ordering with only the live, non-frequency membership rules applied:
    ///  - **Unplayed** hides games that have since been mastered.
    ///  - **Favorites** hides un-favorited games and appends any newly favorited
    ///    ones (favoriting overrides genre frequency).
    ///  - **All** shows the stored order as-is.
    /// Genre frequency is deliberately NOT filtered here — it only shapes how new
    /// games are *generated* into the order — so a game the player already scrolled
    /// past never vanishes when its genre is turned off.
    private var displayedGames: [GameDefinition] {
        let base = orders[settings.feedFilter] ?? []
        switch settings.feedFilter {
        case .all:
            return base
        case .unplayed:
            return base.filter { !progress.isMastered($0.id) }
        case .favorites:
            let kept = base.filter { favorites.isFavorite($0.id) }
            let keptIDs = Set(kept.map(\.id))
            let added = GameRegistry.all.filter {
                favorites.isFavorite($0.id) && !keptIDs.contains($0.id)
            }
            return kept + added
        }
    }

    var body: some View {
        // The GeometryReader is full-bleed (ignores safe area) so paging is
        // pixel-perfect — one whole game per screen. We read the safe-area
        // insets here and hand them to each page, which insets its own content
        // so the title clears the camera / home indicator.
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            ZStack(alignment: .top) {
                if displayedGames.isEmpty {
                    emptyState
                } else {
                    feedScroll(insets: insets)
                    if pullProgress > 0.02 && currentGameID == displayedGames.first?.id {
                        pullBanana(insets: insets)
                    }
                }

                topControls(insets: insets)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(BananaTheme.background)
        .ignoresSafeArea()
        .onAppear {
            // Rebuild every mode's saved order/position from disk once, so a cold
            // launch keeps the SAME order (not a fresh shuffle).
            if orders.isEmpty { rehydrateOrders() }
            ensureOrder(for: settings.feedFilter)
            if let resume = initialGameID {
                // Resume: open ON that game, in place (see resumeTo).
                resumeTo(resume)
            } else {
                // Start fresh → top of the current mode.
                currentGameID = displayedGames.first?.id
            }
        }
        // On a frequency change, keep every mode's already-scrolled games (the
        // current game and everything above it) put, and reshuffle only the tail
        // beneath the current game. Favorites ignore genre frequency entirely.
        .onChange(of: settings.genreWeights) {
            reshuffleBelowCurrent(mode: .all)
            reshuffleBelowCurrent(mode: .unplayed)
        }
        // Switching modes restores that mode's own remembered order + position —
        // no reshuffle. The mode you left keeps its spot too (saved here).
        .onChange(of: settings.feedFilter) { old, new in
            if suppressModeRestore {
                suppressModeRestore = false
                return
            }
            isSwitchingMode = true
            rememberPosition(currentGameID == Self.endID ? nil : currentGameID, for: old)
            ensureOrder(for: new)
            let list = displayedGames   // reads the now-current mode
            if let saved = savedCurrent[new], list.contains(where: { $0.id == saved }) {
                currentGameID = saved
            } else {
                currentGameID = list.first?.id
            }
            // Clear the switch guard after this update pass so genuine drop-outs
            // (mastering / unfavoriting) resume advancing the feed.
            Task { @MainActor in isSwitchingMode = false }
        }
        // Remember the game the player is on, so a later cold launch can offer
        // to return to it. Moving to a different game also releases the paging
        // lock: the new game always starts in its countdown (unlocked) and re-locks
        // itself only if it's a feed-locking game — this prevents a lock left stuck
        // `true` when an actively-playing locksFeed game is removed from the list.
        .onChange(of: currentGameID) { _, id in
            isPagingLocked = false
            // Any navigation clears a stale pull banana (e.g. leaving the end page via its buttons).
            pullProgress = 0
            pullArmed = false
            if let id, id != Self.endID {
                settings.lastGameID = id
                rememberPosition(id, for: settings.feedFilter)
            }
        }
        // Keep the on-screen game valid as the filtered list changes *within* a mode.
        // If the game the player was on drops out (e.g. it just got mastered in
        // Unplayed, or was un-favorited in Favorites), advance to the *next* surviving
        // game in feed order — not the top — so mastering a game carries you onward.
        // Skipped during a mode switch, which swaps the whole list at once.
        .onChange(of: displayedGames.map(\.id)) { oldIDs, ids in
            if isSwitchingMode { return }
            // On the end page: stay there (it isn't a game), unless the whole list emptied out.
            if currentGameID == Self.endID {
                if ids.isEmpty { currentGameID = nil }
                return
            }
            guard let current = currentGameID else {
                isPagingLocked = false
                currentGameID = ids.first
                return
            }
            if !ids.contains(current) {
                isPagingLocked = false
                // Walk forward from where the dropped game sat to the next survivor;
                // if it was the last one, fall back to the nearest survivor above it.
                if let oldIdx = oldIDs.firstIndex(of: current) {
                    let next = oldIDs[(oldIdx + 1)...].first(where: { ids.contains($0) })
                        ?? oldIDs[..<oldIdx].last(where: { ids.contains($0) })
                    currentGameID = next ?? ids.first
                } else {
                    currentGameID = ids.first
                }
            }
        }
        .sheet(isPresented: $showSearch) {
            SearchView(games: GameRegistry.all, onSelect: jumpTo)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showStats) {
            StatsView()
        }
    }

    // MARK: - Pieces

    private func feedScroll(insets: EdgeInsets) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(displayedGames) { game in
                        GamePageView(game: game,
                                     // Only truly active when on-screen AND the app is
                                     // attending the feed (foregrounded, no sheet open) —
                                     // so backgrounding or opening a sheet pauses play.
                                     isActive: currentGameID == game.id && isAttendingFeed,
                                     topInset: insets.top,
                                     bottomInset: insets.bottom,
                                     isPagingLocked: $isPagingLocked,
                                     onSkip: skipToNext)
                            .containerRelativeFrame([.horizontal, .vertical])
                            .id(game.id)          // target for ScrollViewReader.scrollTo
                    }
                    feedEndPage(insets: insets)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(Self.endID)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)   // snap one full game at a time
            .scrollPosition(id: currentGameBinding)
            .scrollIndicators(.hidden)
            .scrollDisabled(isPagingLocked)  // swipe/drag games lock the pager while playing
            // Land a queued cold-launch resume on its exact row. onAppear covers the
            // usual case (queued before the pager exists); onChange covers a resume
            // queued while it's already on screen.
            .onAppear { performPendingScroll(proxy) }
            .onChange(of: pendingResumeScroll) { _, v in if v != nil { performPendingScroll(proxy) } }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in updatePull(y) }
            .onScrollPhaseChange { old, new, _ in handleScrollPhase(old, new) }
        }
        // Rebuild the pager when the mode changes so it re-lays-out around the new
        // set of games, re-anchored on the restored `currentGameID`.
        .id(settings.feedFilter)
    }

    /// Scrolls the pager to a queued resume target once — forcing the (possibly deep,
    /// not-yet-realized) LazyVStack row into place, which `.scrollPosition` misses on a
    /// cold launch. Runs an immediate best-effort jump plus one after the rows settle.
    private func performPendingScroll(_ proxy: ScrollViewProxy) {
        guard let target = pendingResumeScroll else { return }
        pendingResumeScroll = nil
        proxy.scrollTo(target, anchor: .top)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            proxy.scrollTo(target, anchor: .top)
            // Release the guard only after the row has settled, so late write-backs are dropped.
            try? await Task.sleep(for: .milliseconds(80))
            resumeSettling = false
        }
    }

    /// The pager's position binding, guarded so transient write-backs during a resume scroll can't
    /// hijack `currentGameID`. Normal swipes (no resume in flight) pass straight through.
    private var currentGameBinding: Binding<String?> {
        Binding(
            get: { currentGameID },
            set: { newValue in
                if resumeSettling { return }
                currentGameID = newValue
            }
        )
    }

    private func topControls(insets: EdgeInsets) -> some View {
        HStack(alignment: .top) {
            filterMenu
            Spacer()
            bananaMenu
        }
        .padding(.horizontal, 16)
        .padding(.top, max(insets.top, 12) + 4)
    }

    /// A tiny banana toggle that spins one full turn on tap and drops down the
    /// stats / search / settings buttons — collapsing the old three-icon cluster.
    private var bananaMenu: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.5)) { bananaSpin += 360 }
                withAnimation(.spring(duration: 0.32)) { menuOpen.toggle() }
                Haptics.tap()
                SoundManager.shared.tap()
            } label: {
                Text("🍌")
                    .font(.system(size: 22))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.12), in: Circle())
                    .rotationEffect(.degrees(bananaSpin))
            }

            if menuOpen {
                menuButton("chart.bar.fill") { showStats = true }
                menuButton("magnifyingglass") { showSearch = true }
                menuButton("gearshape") { showSettings = true }
            }
        }
    }

    /// One item in the banana dropdown: closes the menu, then runs its action.
    private func menuButton(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(duration: 0.25)) { menuOpen = false }
            action()
        } label: {
            controlIcon(name)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var filterMenu: some View {
        Menu {
            ForEach(FeedFilter.allCases) { filter in
                Button {
                    settings.feedFilter = filter
                } label: {
                    if settings.feedFilter == filter {
                        Label(filter.label, systemImage: "checkmark")
                    } else {
                        Text(filter.label)
                    }
                }
            }
            Divider()
            Button { reshuffleCurrentMode() } label: {
                Label(L("Reshuffle", "Xáo lại"), systemImage: "shuffle")
            }
        } label: {
            HStack(spacing: 4) {
                Text(settings.feedFilter.label)
                    .font(.subheadline.weight(.bold))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.white.opacity(0.12), in: Capsule())
        }
    }

    private func controlIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .padding(10)
            .background(.white.opacity(0.12), in: Circle())
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("🍌")
                .font(.system(size: 64))
            Text(emptyTitle)
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(BananaTheme.subtle)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        switch settings.feedFilter {
        case .favorites: return L("No favorites yet", "Chưa có mục yêu thích")
        case .unplayed:  return L("All mastered!", "Đã thông thạo hết!")
        case .all:       return L("Nothing to show", "Không có gì để hiển thị")
        }
    }

    private var emptyMessage: String {
        switch settings.feedFilter {
        case .favorites: return L("Tap the heart on a game to add it here.",
                                  "Chạm vào trái tim trên một trò chơi để thêm vào đây.")
        case .unplayed:  return L("You've beaten every level of every game.",
                                  "Bạn đã vượt qua mọi cấp của mọi trò chơi.")
        case .all:       return L("All genres are turned off. Enable one in Settings.",
                                  "Tất cả thể loại đã tắt. Bật một thể loại trong Cài đặt.")
        }
    }

    // MARK: - Flow

    /// A weighted shuffle: each game gets a random priority scaled by its genre's
    /// weight, so higher-weight genres cluster toward the top. Weight-0 genres are
    /// dropped. (Pass a subset to shuffle just that subset.)
    private func weightedShuffle(_ games: [GameDefinition]) -> [GameDefinition] {
        games
            .filter { settings.weight(for: $0.genre) > 0 }
            .map { ($0, Double.random(in: 0...1) * Double(settings.weight(for: $0.genre))) }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    /// Builds a mode's ordering from scratch (used the first time a mode is entered
    /// and by the reshuffle button). Favorites include every favorited game — even
    /// off-genre ones — since favoriting overrides frequency.
    private func buildOrder(for mode: FeedFilter) -> [GameDefinition] {
        switch mode {
        case .all:
            return weightedShuffle(GameRegistry.all)
        case .unplayed:
            return weightedShuffle(GameRegistry.all.filter { !progress.isMastered($0.id) })
        case .favorites:
            return GameRegistry.all.filter { favorites.isFavorite($0.id) }.shuffled()
        }
    }

    /// Ensures a mode has a stored ordering, building it once if not.
    private func ensureOrder(for mode: FeedFilter) {
        if orders[mode] == nil { setOrder(buildOrder(for: mode), for: mode) }
    }

    /// Stores a mode's ordering in memory AND mirrors it (as ids) to AppSettings so
    /// it survives a cold launch. The single choke-point for order changes.
    private func setOrder(_ list: [GameDefinition], for mode: FeedFilter) {
        orders[mode] = list
        settings.feedOrders[mode.rawValue] = list.map(\.id)
    }

    /// Remembers a mode's current game in memory AND persists it.
    private func rememberPosition(_ id: String?, for mode: FeedFilter) {
        savedCurrent[mode] = id
        if let id { settings.feedPositions[mode.rawValue] = id }
        else { settings.feedPositions.removeValue(forKey: mode.rawValue) }
    }

    /// Rebuilds the in-memory `orders` / `savedCurrent` from the persisted ids on a
    /// cold launch. Unknown ids (removed games) are dropped; brand-new catalog games
    /// are appended to the tail so a saved order still contains the whole catalog and
    /// the resumed game keeps its neighbours.
    private func rehydrateOrders() {
        let byID = Dictionary(GameRegistry.all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for mode in FeedFilter.allCases {
            guard let ids = settings.feedOrders[mode.rawValue], !ids.isEmpty else { continue }
            var list = ids.compactMap { byID[$0] }
            let have = Set(list.map(\.id))
            // buildOrder honors the mode's membership + current genre weights, so
            // newcomers are only currently-eligible games not already in the order.
            list += buildOrder(for: mode).filter { !have.contains($0.id) }
            guard !list.isEmpty else { continue }
            orders[mode] = list
            // Freeze the reconciliation: if the catalog changed since this order was saved
            // (newcomers appended, or removed games dropped), PERSIST the merged order now.
            // Otherwise every launch re-appends the newcomers with a fresh random shuffle — a
            // different tail each time — so a game you finished on (often a newcomer) never stays
            // at the end. Persisting here places newcomers once, then the order is stable.
            if list.map(\.id) != ids { setOrder(list, for: mode) }
        }
        for mode in FeedFilter.allCases {
            if let id = settings.feedPositions[mode.rawValue] { savedCurrent[mode] = id }
        }
    }

    /// Reshuffle the current mode from scratch and jump to the top. This is the
    /// only place a mode is deliberately reshuffled (mode switches never do).
    private func reshuffleCurrentMode() {
        Haptics.tap()
        SoundManager.shared.tap()
        let mode = settings.feedFilter
        setOrder(buildOrder(for: mode), for: mode)
        withAnimation { currentGameID = displayedGames.first?.id }
    }

    /// Frequency-change reshuffle for one mode: the current game and everything the
    /// player has already scrolled past (everything above it) stay EXACTLY as they
    /// are — nothing added or removed, even a game whose genre was just turned off.
    /// Only the games *below* the current one are regenerated so newly enabled
    /// genres join the tail and disabled ones leave it. If the mode has no stored
    /// order yet, it's left alone (it'll build fresh, honoring the new weights, when
    /// the player next enters it).
    private func reshuffleBelowCurrent(mode: FeedFilter) {
        guard let order = orders[mode] else { return }
        let anchor = (mode == settings.feedFilter) ? currentGameID : savedCurrent[mode]

        guard let anchor, let idx = order.firstIndex(where: { $0.id == anchor }) else {
            // No game to preserve — rebuild fresh; if it's the visible mode, top it.
            setOrder(buildOrder(for: mode), for: mode)
            if mode == settings.feedFilter { currentGameID = displayedGames.first?.id }
            return
        }

        let prefix = Array(order[...idx])
        let prefixIDs = Set(prefix.map(\.id))
        let candidates: [GameDefinition]
        switch mode {
        case .unplayed:
            candidates = GameRegistry.all.filter {
                !progress.isMastered($0.id) && !prefixIDs.contains($0.id)
            }
        default:
            candidates = GameRegistry.all.filter { !prefixIDs.contains($0.id) }
        }
        setOrder(prefix + weightedShuffle(candidates), for: mode)
    }

    /// Programmatically advances to the next game (wrapping around). Used by the
    /// on-screen skip button so a player can leave a feed-locking game even while
    /// its paging lock blocks manual swipes.
    private func skipToNext() {
        let list = displayedGames
        guard !list.isEmpty, let current = currentGameID, current != Self.endID,
              let index = list.firstIndex(where: { $0.id == current }) else { return }
        // Off the last game, skip lands on the end page (never wraps back to the top).
        let next = index + 1 < list.count ? list[index + 1].id : Self.endID
        withAnimation { currentGameID = next }
    }

    /// Cold-launch resume: open the feed ON `id`, at its EXACT position in the saved
    /// order (mid-list, neighbours intact — no rotation, no relocation). We set it as
    /// the current game AND queue `pendingResumeScroll` so the pager actually scrolls
    /// down to its row once the lazy list exists (see `performPendingScroll`). Hops to
    /// All if the saved mode can't show the game (e.g. it was mastered out of Unplayed).
    private func resumeTo(_ id: String) {
        guard GameRegistry.all.contains(where: { $0.id == id }) else {
            currentGameID = displayedGames.first?.id
            return
        }
        if settings.feedFilter != .all,
           !(orders[settings.feedFilter]?.contains(where: { $0.id == id }) ?? false) {
            suppressModeRestore = true          // don't let the mode-switch clobber our target
            settings.feedFilter = .all
            ensureOrder(for: .all)
        }
        guard displayedGames.contains(where: { $0.id == id }) else {
            currentGameID = displayedGames.first?.id
            return
        }
        resumeSettling = true
        currentGameID = id
        pendingResumeScroll = id
    }

    /// Brings a searched game to the player instead of yanking the feed to wherever
    /// it lives: the game is re-inserted directly *after* the one the player is on,
    /// so it becomes the very next page (and the new current game). The previously
    /// played game stays put right above it. If the current mode can't show the
    /// searched game, switch to All so it's reachable.
    private func jumpTo(_ id: String) {
        guard let game = GameRegistry.all.first(where: { $0.id == id }) else { return }
        ensureOrder(for: settings.feedFilter)

        if !displayedGames.contains(where: { $0.id == id }) && settings.feedFilter != .all {
            // Hop to All to reach the game — remember where we were, and suppress
            // the mode-restore so the switch honors this jump instead.
            rememberPosition(currentGameID, for: settings.feedFilter)
            suppressModeRestore = true
            settings.feedFilter = .all
            ensureOrder(for: .all)
        }

        let mode = settings.feedFilter
        var list = orders[mode] ?? []
        list.removeAll { $0.id == id }
        if let current = currentGameID,
           let curIdx = list.firstIndex(where: { $0.id == current }) {
            list.insert(game, at: curIdx + 1)
        } else {
            list.insert(game, at: 0)   // no current game — put it at the top
        }
        setOrder(list, for: mode)
        withAnimation { currentGameID = id }
    }

    // MARK: - Pull-to-reshuffle (top overscroll)

    /// Maps the scroll offset to the banana pull. Only acts at the very top; the resting offset is
    /// captured as a baseline (first sample) so a non-zero top inset doesn't fake a pull.
    private func updatePull(_ y: CGFloat) {
        // Only the top page's downward over-scroll (negative offset) counts as a pull; the feed is
        // full-bleed so the resting top offset is 0. Scrolling into the list (positive) never pulls.
        guard currentGameID == displayedGames.first?.id else {
            if pullProgress != 0 { pullProgress = 0 }
            pullArmed = false
            return
        }
        let pulled = max(0, -y)
        pullProgress = min(1.5, pulled / pullThreshold)
        pullArmed = pulled >= pullThreshold                    // ease back below the line to cancel
    }

    /// When the drag that crossed the threshold ends, fire the reshuffle; otherwise ease the banana
    /// back once the scroll settles.
    private func handleScrollPhase(_ old: ScrollPhase, _ new: ScrollPhase) {
        if old == .interacting && new != .interacting && pullArmed {
            pullArmed = false
            reshuffleCurrentMode()
            Haptics.success()
            withAnimation(.spring(duration: 0.3)) { pullProgress = 0 }
        } else if new == .idle {
            withAnimation(.spring(duration: 0.3)) { pullProgress = 0 }
        }
    }

    private func pullBanana(insets: EdgeInsets) -> some View {
        let armed = pullProgress >= 1
        return ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: 3)
            Circle().trim(from: 0, to: min(1, pullProgress))
                .stroke(armed ? Color.green : BananaTheme.banana,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("🍌")
                .font(.system(size: 30))
                .rotationEffect(.degrees(Double(pullProgress) * 360))
        }
        .frame(width: 56, height: 56)
        .opacity(Double(min(1, pullProgress / 0.3)))
        .padding(.top, max(insets.top, 12) + 6 + pullProgress * 60)
        .frame(maxWidth: .infinity, alignment: .center)
        .allowsHitTesting(false)
    }

    // MARK: - End-of-feed page

    private func feedEndPage(insets: EdgeInsets) -> some View {
        VStack(spacing: 26) {
            Spacer(minLength: 0)
            Text("🍌").font(.system(size: 60))
            Text(L("You've reached the end", "Bạn đã đến cuối"))
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                endStat(L("STREAK", "CHUỖI"), "\(stats.currentStreak)", BananaTheme.banana)
                endStat(L("SMART", "THÔNG MINH"), "\(stats.smartPoints)", BananaTheme.banana)
                endStat(L("FRESH", "TỈNH TÁO"), "\(stats.freshPoints)", Color(red: 0.4, green: 0.85, blue: 0.95))
            }

            VStack(spacing: 12) {
                Button {
                    Haptics.tap(); SoundManager.shared.tap()
                    withAnimation { currentGameID = displayedGames.first?.id }
                } label: {
                    endButton(L("Return to top", "Về đầu trang"), "arrow.up.to.line", filled: true)
                }
                Button { reshuffleCurrentMode() } label: {
                    endButton(L("Reshuffle", "Xáo lại"), "shuffle", filled: false)
                }
            }
            .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 30)
        .padding(.top, max(insets.top, 60))
        .padding(.bottom, max(insets.bottom, 24))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BananaTheme.background)
    }

    private func endStat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.05)))
    }

    private func endButton(_ title: String, _ icon: String, filled: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(filled ? .black : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(filled ? BananaTheme.banana : Color.white.opacity(0.12))
            )
    }
}
