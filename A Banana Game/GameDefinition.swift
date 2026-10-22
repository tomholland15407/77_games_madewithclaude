//
//  GameDefinition.swift
//  A Banana Game
//
//  The single contract every mini-game plugs into. The feed only ever talks to
//  this — so adding a brand new game means adding one entry to `GameRegistry`,
//  and the feed picks it up automatically.
//

import SwiftUI

/// The category of a game. Used to weight how often it appears in the feed
/// (Checkpoint C's frequency sliders) and to group favorites.
///
/// We use just **two** buckets: `reflex` (fast/twitch/fun games) and `brain`
/// (thinking/memory games). Earlier `fun`→`reflex` and `memory`→`brain`.
enum Genre: String, CaseIterable, Identifiable, Codable {
    case reflex, brain

    var id: String { rawValue }

    var label: String {
        switch self {
        case .reflex: return L("Reflex", "Phản xạ")
        case .brain:  return L("Brain", "Trí tuệ")
        }
    }

    /// The genre as an icon — shown instead of `label` wherever the UI can, so there's
    /// less to read. Keep `label` as the accessibility label.
    var icon: String {
        switch self {
        case .reflex: return "bolt.fill"
        case .brain:  return "brain.fill"
        }
    }

    /// The genre's accent: banana for brain (Smart points), cyan for reflex (Fresh points).
    var tint: Color {
        switch self {
        case .reflex: return Color(red: 0.4, green: 0.85, blue: 0.95)
        case .brain:  return BananaTheme.banana
        }
    }
}

/// A genre's icon in its accent colour, read aloud as the genre's name.
struct GenreIcon: View {
    let genre: Genre

    var body: some View {
        Image(systemName: genre.icon)
            .foregroundStyle(genre.tint)
            .accessibilityLabel(genre.label)
    }
}

/// An in-game manual, shown when the player taps the book button on a game page.
/// Every game ships one so the player can always look up how a game works.
///
/// The manual is now **2–4 short bullets** plus an **optional looping win clip**
/// (a short muted mp4 of an actual win) — no per-level notes. Tone: clean, no tiny
/// hint text, minimal emoji (only 🍌).
struct GameManual {
    /// 2–4 short English bullet points covering the core rules + controls.
    let bullets: [String]
    /// Vietnamese bullets. Empty = fall back to `bullets` (English).
    let bulletsVI: [String]
    /// Optional looping-win-clip asset name, WITHOUT extension (the file is
    /// `<name>.mp4` in the app target). `nil` = bullets only, no video.
    /// Convention: `<game.id>-win` (e.g. "mirror-maze-win").
    let demo: String?
    /// When true, the manual shows a LIVE self-looping replay of the game's own
    /// view (see `LiveDemoView` / `\.isDemo`) instead of a bundled mp4. Takes
    /// precedence over `demo`. The game must implement its `\.isDemo` auto-play.
    let liveDemo: Bool

    /// Primary initializer: bullets + optional Vietnamese + optional demo clip.
    init(bullets: [String], bulletsVI: [String] = [], demo: String? = nil, liveDemo: Bool = false) {
        self.bullets = bullets
        self.bulletsVI = bulletsVI
        self.demo = demo
        self.liveDemo = liveDemo
    }

    /// The bullets for the current language (Vietnamese if selected and non-empty,
    /// else English).
    var resolvedBullets: [String] {
        if Localization.shared.lang == .vi, !bulletsVI.isEmpty { return bulletsVI }
        return bullets
    }
}

struct GameDefinition: Identifiable {
    /// Stable unique id (used to save favorites).
    let id: String
    /// Display name, e.g. "Tap the Banana".
    let title: String
    /// A little icon. Per CLAUDE.md, the only emoji we use is the banana.
    let emoji: String
    /// The game's category.
    let genre: Genre
    /// How many levels this game has. Standard is 7 (see CLAUDE.md).
    let levelCount: Int
    /// Whether the feed's vertical paging should be locked while this game is
    /// actively playing. Swipe/drag games set this `true` so their gestures
    /// don't fight the pager; tap games leave it `false` (the default).
    var locksFeed: Bool = false
    /// The in-game manual (book button). Optional so the catalog keeps compiling
    /// while manuals are authored game-by-game; every game should end up with one.
    var manual: GameManual? = nil
    /// Builds the playable view for a given level.
    /// - Call `onWin` when the player beats the level — the feed celebrates and moves on.
    /// - Call `onFail` when the player fails — the feed sends them back to level 1.
    let makeView: (_ level: Int,
                   _ onWin: @escaping () -> Void,
                   _ onFail: @escaping () -> Void) -> AnyView
    /// Optional: start building the given level's board ahead of time (see `BoardCache`). The
    /// page calls it when the countdown starts and, on a win, for the next level. Games whose
    /// setup is instant leave it `nil`.
    var prefetch: ((_ level: Int) -> Void)? = nil
}

/// The master list of games shown in the feed, in order.
/// Add new games here — that's the only wiring needed.
enum GameRegistry {
    static let all: [GameDefinition] = [
        PegSolitaireGame.definition,
        QuickMathGame.definition,
        MemoryGame.definition,
        TankMazeGame.definition,
        ColorTrapGame.definition,
        LoloGame.definition,
        TurboRacerGame.definition,
        Slide2048Game.definition,
        // Batch 1
        CupShuffleGame.definition,
        GoldMinerGame.definition,
        BreachGame.definition,
        // Batch 2
        CoverFireGame.definition,
        // Batch 3
        SpiralGalaxiesGame.definition,
        MasyuGame.definition,
        BottleOrderGame.definition,
        BloxorzGame.definition,
        // Batch 4 (swipe/drag — locksFeed)
        LineConnectGame.definition,
        RollTheBallGame.definition,
        BinairoGame.definition,
        NurikabeGame.definition,
        AirHockeyGame.definition,
        // Batch 5
        KlotskiGame.definition,
        QuickDrawGame.definition,
        FloodItGame.definition,
        GunMayhemGame.definition,
        // Batch 6
        PlaneCrashGame.definition,
        CritterDuelGame.definition,
        LawnDefenseGame.definition,
        SlitherlinkGame.definition,
        // Batch 7
        UncleRogerGame.definition,
        // Batch 8
        SpotDifferenceGame.definition,
        AssassinGame.definition,
        ParkingGame.definition,
        HeadSoccerGame.definition,
        // Batch 9 (pixel-art)
        TowerOfHanoiGame.definition,
        LightsOutGame.definition,
        // Batch 10 (arcade classics)
        MazeMuncherGame.definition,
        LaserDodgeGame.definition,
        CatBurglarGame.definition,
        BrickBreakerGame.definition,
        DodgeballGame.definition,
        // Batch 11 (arcade classics)
        SoloChessGame.definition,
        // Batch 12 (pixel arcade classics — polished with PixelFX)
        FlappyBananaGame.definition,
        CheerUpMonkeyGame.definition,
        StackGame.definition,
        FruitNinjaGame.definition,
        DoodleJumpGame.definition,
        JetpackBananaGame.definition,
        // Batch 13
        GeometryDashGame.definition,
        ColorSwitchGame.definition,
        KnifeHitGame.definition,
        ColorBumpGame.definition,
        HashiGame.definition,
        // Batch 14 (pixel arcade classics)
        TentsTreesGame.definition,
        CratePushGame.definition,
        AsteroidsGame.definition,
        RicochetShotGame.definition,
        LunarLanderGame.definition,
        // Batch 15 (pixel arcade classics)
        DigDugGame.definition,
        QbertGame.definition,
        RicochetRobotsGame.definition,
        DecoyGame.definition,
        // Batch 16 (combat shooters)
        SniperGame.definition,
        RockNRocketGame.definition,
        // Batch 17 (brain / strategy-and-action replacements)
        MirrorMazeGame.definition,
        PipeFlowGame.definition,
        LightCyclesGame.definition,
        BananaBomberGame.definition,
        GuardPatrolGame.definition,
        RushHourGame.definition,
        ArtilleryDuelGame.definition,
        // Batch 19 (puzzle & physics replacements)
        QueensGame.definition,
        BlockBlastGame.definition,
        TileTrioGame.definition,
        FruitMergeGame.definition,
        FlightControlGame.definition,
        DesertGolfGame.definition,
    ]
}
