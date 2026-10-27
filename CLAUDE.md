# CLAUDE.md — GOGs (Game of Games)

Guidance for working in this repo. Read this before adding or changing a game.

> **Chat responses:** NEVER use Markdown tables — the Xcode assistant interface truncates them so
> the full table is never visible. Present comparisons/lists as headed bullet points or short
> numbered lists instead.

> **Adding a game?** Read **GAME_PATTERNS.md** — copy-paste code patterns (skeleton, timer,
> time-bar, win/fail, gotchas) so you don't have to re-read existing game files. The
> authoritative catalog is **`GameRegistry.all`** in `GameDefinition.swift`. Historical design
> notes (original vision, the 1–39 backlog, the pixel visual-design bible) are archived in
> **docs/HISTORY.md**.

> **Naming:** the splash (RootView) now reads **"GAME OF GAMES"** with the motto
> **"UNROT YOUR BRAIN"** underneath. The Home Screen display name (`CFBundleDisplayName`
> in Info.plist) is kept as **"GOGs"** (short enough to fit under the icon). The Xcode
> project/target/folder is still named "A Banana Game" internally; that hasn't been
> renamed (doing so needs Xcode UI steps). The banana theme + 🍌 mascot are kept.

## What this app is
A **"TikTok for micro-games"** framed as a **brain-refresh tool** ("UNROT YOUR BRAIN"):
a full-screen, vertical, swipeable feed where every page is a tiny game. Open the app →
you're instantly playing. Swipe up → a totally different game. Fast, frantic,
instant-reward. Black theme, banana-yellow accent, 🍌 mascot.

See `docs/HISTORY.md` for the original product vision and roadmap.

## Tech & conventions
- **SwiftUI app lifecycle** (`BananaGameApp`), no Storyboard/UIKit lifecycle.
- Modern SwiftUI only: `@Observable` (not ObservableObject/Combine), `async/await`
  (not Combine), `ScrollView` + `.scrollTargetBehavior(.paging)` for the feed.
- Deployment target is current (iOS 26+); new APIs are fair game. When unsure about
  an Apple API, use the `DocumentationSearch` tool rather than guessing.
- The Xcode project uses **file-system synchronized groups**: any `.swift` file added
  to the `A Banana Game/` folder is automatically part of the target. No project-file
  editing needed to add files.
- **Do NOT hand-edit `project.pbxproj` while Xcode is open** — it gets blocked and can
  corrupt the project. Ask the user to make target/build-setting changes in Xcode's UI.
- 4-space indentation; PascalCase types, camelCase members; comment non-obvious logic.
- Verify changes with the `BuildProject` tool before handing back.

## Architecture (3 layers)
1. **Feed** — `FeedView`: a vertical pager. Tracks the on-screen game via
   `.scrollPosition` and passes `isActive` to each page so off-screen games stay idle.
   It also owns the top controls (filter menu top-left; a **banana dropdown** top-right that
   spins one turn on tap and drops down the stats / search / settings buttons), the filter
   modes (All / Favorites / Unplayed), and the genre-weighted ordering.
2. **Page** — `GamePageView`: hosts one game and owns the shared lifecycle
   (countdown, win, fail, level, favorites ❤️, and the **book/manual button**). Games do
   NOT implement these themselves. On win it also **awards points** via `StatsStore`
   (based on `game.genre`). The manual button pauses the game (drops the game view so its
   loop stops) and shows `GameManualView`; closing it replays the current level from the
   3·2·1 countdown.
3. **Game** — each game is a self-contained view + a `GameDefinition` entry in
   `GameRegistry.all`. That's the only wiring needed to add a game.

Shared services: `SoundManager` (synthesized SFX + persisted mute), `FavoritesStore`
(persisted ❤️), `ProgressStore` (persisted "mastered" games — beat the final level),
`StatsStore` (persisted daily streak + best streak, and Smart/Fresh points),
`AppSettings` (persisted feed filter + genre weights), `Haptics`, `BananaTheme`,
`RewardBurstView`, `UpdateChecker`. All are `@Observable` and injected via the environment in
`BananaGameApp`.

Update check (`UpdateChecker.swift`): compares `CFBundleShortVersionString` with the iTunes Lookup
API (`itunes.apple.com/lookup?bundleId=…`, device storefront first, then US) using a numeric
`SemanticVersion` compare. RootView runs `checkAtLaunch()` silently during the splash; if a newer
version exists, `UpdatePromptView` (release notes + Update → `trackViewUrl` / Later) appears over
the feed on **every cold launch** until the player updates (nothing is persisted), and `FeedView`
pauses the game underneath while `launchPrompt` is set. Offline / not listed / 0 results = no
pop-up. SettingsView's button runs the same `check()` on demand ("Checking…" → pop-up, "You're up
to date", or an offline message). **DEBUG only:** env `GOGS_FAKE_STORE_VERSION=9.9` (Simulator:
`SIMCTL_CHILD_GOGS_FAKE_STORE_VERSION`, optional `…_GOGS_FAKE_STORE_NOTES`) fakes the store
answer. As of Sept 2026 the app isn't on the store yet, so the real lookup returns 0 results.

Stats ("UNROT YOUR BRAIN"): `StatsStore` tracks a **daily streak** (consecutive calendar
days you win at least one level) plus the **best streak** ever, and two point pools —
**Smart** (earned on `.brain` games) and **Fresh** (earned on `.reflex` games). Points are
awarded on every win and **scale with the level beaten** (10 × level). `StatsView` (opened from
the bar-chart item in the feed's banana dropdown) shows the streak + both pools. Award happens
in `GamePageView.handleWin`.

In-game manual: `GameDefinition.manual` is an optional `GameManual` — **2–4 short bullets**
(`bullets`, English) plus an **optional looping win clip** (`demo`). No per-level notes.
`GamePageView` shows a book button on any game that has a manual; every game ships one.
`GameManualView` renders the (optional) demo video in a 16:9 frame, then the bullets. The demo
is a short muted mp4 of an actual win, bundled as `<game.id>-win.mp4` and referenced by
`demo: "<game.id>-win"` (name without extension); `LoopingVideoView` plays it muted/looping and
renders nothing if the file is missing, so a game with no clip just shows its bullets.

Localization (English / Vietnamese): a central layer — `Localization.swift` — not a String
Catalog. `Localization.shared` (`@Observable`) holds `lang` (`AppLanguage.en`/`.vi`), defaults to
the device language on first launch and persists the in-app choice (`SettingsView` has a language
picker) under `appLanguage`. Wrap user-facing literals with the free helper `L("English",
"Tiếng Việt")` (Vietnamese falls back to English when empty). Because the helper reads
`Localization.shared.lang`, any SwiftUI `body` using it re-renders live on toggle. **Do NOT
localize:** game titles (rendered from `game.title`), the brand ("GAME OF GAMES" / "GOGs"), or the
word "UNROT" in the motto. Each game's manual carries `bullets` + `bulletsVI`; wrap in-game status
text (e.g. "REACH THE EXIT", "AMMO", score labels) with `L(...)`. Purely numeric status needs no
wrapping.

Generated boards (`BoardCache.swift`): games that generate-and-verify their level expose
`GameDefinition.prefetch` so `GamePageView` can build the board during the 3·2·1 countdown (plus the
next level's board during play/the win overlay). Same generators and parameters — it only moves the
work earlier. See GAME_PATTERNS.md "Generated boards → prefetch them" for the per-game wiring.

Feed modes & search: the feed can show **All / Favorites / Unplayed** games (Unplayed =
not yet mastered, i.e. final level not beaten). `SettingsView` (gear) toggles sound, the
filter, and per-genre frequency (Off/Low/Normal/High). `SearchView` (magnifier) finds a
game by name and jumps the feed to it. Genre weighting is a **weighted finite order**:
`FeedView` weighted-shuffles the catalog so higher-weight genres cluster near the top and
weight-0 genres are hidden. Ordering rules: **launch** = full shuffle. **Frequency change**
= the current game and everything above it stay put; only games *below* it reshuffle (newly
re-enabled genres join that tail); if the current game's genre was turned off, full reshuffle
→ top. **Leaving Favorites** for All/Unplayed = full reshuffle → top (so you don't land on a
random favorite deep in the list). It does **not** reshuffle on a favorite toggle. When the
current game **drops out of the active filter** (e.g. you master it in Unplayed, or unfavorite
it), the feed advances to the **next surviving game in order** — not back to the top.

## ⭐️ Standard properties EVERY game must follow
When adding a game, honor these so the feed feels consistent:

1. **7 levels.** `levelCount: 7`. Difficulty must ramp **quickly** to hold attention.
2. **Level 1 is meaningful but winnable** — hard enough that the player sees the point,
   not so hard it's unrewarding.
3. **Levels 6 & 7 approach impossibility.** They're meant to be nearly unbeatable.
4. **A fail mechanism → back to level 1.** No infinite play; there must always be a way
   to lose (time limit, threshold, wrong move, etc.). Call `onFail`. **This applies even
   to open-ended / puzzle games** (e.g. Slide/2048): if the core rules alone would let a
   player continue indefinitely, add a per-level countdown so time can always run out.
5. **Win → next level.** Call `onWin` when the level's goal is met. The page handles the
   celebration, reward burst, and advancing.
6. **Auto-start.** The page runs a 3·2·1 countdown; games begin on appear (in `onAppear`
   or `.task`). Never require a "press to start".
7. **Sound effects** via `SoundManager.shared`: `.tap()` on interactions, `.error()` on
   mistakes. (`success` and the countdown are fired by the page — don't duplicate them.)
8. **Haptics** via `Haptics` (`tap`/`success`/`warning`).
9. **Screen-independent layout.** Position with fractions of the play area (0...1), not
   hard-coded points. The page already handles safe-area insets (camera / home indicator).
10. **Genre tag** — one of **two** buckets: `reflex` (fast/twitch/fun) or `brain`
    (thinking/memory). Used to weight how often the game appears in the feed AND which point
    pool a win feeds (`.brain`→Smart, `.reflex`→Fresh). The old four-way split was collapsed:
    `fun`→`reflex`, `memory`→`brain`. In the UI a genre is an **icon, not a word**:
    `GenreIcon(genre:)` (GameDefinition.swift) draws `Genre.icon` (`brain.fill` / `bolt.fill`) in
    `Genre.tint` (banana / cyan) with `label` as its accessibility label. Search rows, the
    Settings frequency rows and the Stats point cards use it. Don't add the words
    "Brain"/"Reflex" back on screen; `label` is for VoiceOver.
11. **A manual.** Fill `GameDefinition.manual` with a `GameManual` — **2–4 short bullets**
    (`bullets`) covering the core rules + controls, plus their Vietnamese (`bulletsVI`) and an
    optional win clip (`demo:`). No per-level notes. The page's book button shows it. Match the
    tone/length of the existing manuals (DigDug is the template).
12. **Localize user-facing text.** Author `bullets` + `bulletsVI`, and wrap in-game status
    literals with `L("English", "Tiếng Việt")` (see the Localization note above). Titles/brand
    stay English.

## Tone & visual voice
- **No tiny / hard-to-read text.** Don't put small instructional hint text on the play
  screen ("Tap to jump", "Swipe to shoot", etc.) — the **manual** (book button) explains
  controls now. Prefer real, tappable buttons and big legible status (score, timer). Dynamic
  status/mode indicators are fine; static how-to hints are not.
- **Minimal emojis.** Heavy emoji use makes the app feel AI-generated; we want it to feel
  human and crafted. Prefer clean text (e.g. "FAILED", "You beat every level!").
- **The only emoji allowed is the banana 🍌** (the mascot). Never use 🎉/💥/😈/⚡️/etc.
  Use 🍌 sparingly and only where it's meaningful (the tappable object, the splash mascot,
  the reward burst).
- Full-bleed black, immersive: status bar is hidden. The feed is full-screen; each page
  insets its own content by the safe-area amounts passed from `FeedView` (never let the
  scroll view respect the safe area — it breaks one-game-per-screen paging).
- **iPad = a phone column.** `PhoneColumn` (wrapping `RootView` and the manual's full-screen
  cover) lays the app out in a centred column of the iPhone's aspect on black whenever the window
  is much wider than a phone, so games never stretch to 4:3. Anything presented full screen needs
  its own `PhoneColumn`.
- **Top-center camera cutout is universal** (Dynamic Island / notch / hole-punch). Never
  place titles or key UI in the top-center strip. The page floors its top inset at 60pt
  (`max(topInset, 60)`) so content always clears the island, even full-bleed.

## Visual redesign pass (done, Sept 2026 – Oct 2026)
Every game was redrawn so it **looks like the real game people see when they Google it**
(or, when the name promises something the old visuals didn't deliver, like it; or, for inherently
bland puzzles, a lively themed world). **Visuals only**: rules, generators, difficulty numbers,
timers and win/fail logic stayed untouched; demos keep working in the new look. Done in batches of 7
in `GameRegistry.all` order, each screenshot-checked at L1/L4/L7 + demo in the Simulator. New games
should arrive in this style (per-game vector art, icons over words, one Canvas per dense scene).
- **Batch 1 (done):** Peg Solitaire → marble solitaire (teak board, carved groove that collects
  captured glass marbles, hop animation). Quick Math → Shiny Things' Quick Math (white paper, thin
  cyan numerals, solved line scrolls up with a tick). Banana Memory → the 1978 Simon (colour
  quadrant pads, brushed-silver hub with LED counter). Tank Maze → Tank Trouble (light tiled floor,
  thin charcoal walls, flat tanks, black bullets, scorch marks). Color Trap → a paint studio
  (dripping painted word on an easel canvas, masking-tape prompt, paint-can swatches). Statue Maze
  (was Lolo) → Adventures of Lolo (sandstone blocks, brick floor, Emerald/Heart Framers, Medusa gaze
  beams, banana hero with Lolo eyes, NES cross d-pad). Turbo Racer → OutRun (7 stages from coast to
  neon, palms/props, drawn traffic, red Testarossa with a banana passenger, TIME/%/km/h HUD).
- **Batch 2 (done):** Slide → Cirulli's 2048 (exact palette, tiles slide / pop / zoom in). Cup
  Shuffle → the shell game (glossy red party cups upside down on casino felt, drawn banana). Nugget
  Hook (was Gold Miner) → the Flash classic (orange surface, blue dome, stick-figure prospector at a
  winch, sandy strata, Money/Goal/Time HUD, "+$" pop-ups). Breach → a bank heist (marble floor,
  brick blown by C4 into rubble, steel vault door, guards with flashlights, masked banana, detonator
  button). Compound Dash (was Cover Fire) → a desert compound (sandbags, ammo crates, sniper nests
  with red laser sights, scope gauges, helipad exit). Spiral Galaxies → deep space (nebula-lit
  galaxies, spiral arms on completion). Pearl Chain (was Masyu) → a jewellery box (quilted velvet,
  white/Tahitian pearls, gold chain loop).
- **Batch 3 (done):** Bottle Order → the "Match the Bottles" challenge (bar table, pendant lamp,
  glass soda bottles, mystery box, chalkboard history, brass bell CHECK). Topple Block (was Bloxorz)
  → the original Flash game (red sky, stone slabs in its oblique view, rusty block that tips over
  its edge, square pit goal, MOVES counter, arrow keys). Line Connect → a minefield (blinking mines,
  dirt trail, checkered flag, blast). Groove Slider (was Roll the Ball) → BitMango's wooden tiles
  with carved grooves, steel fixed tiles and a silver ball. Berry Balance (was Binairo) → a waffle
  (blueberries vs banana slices, cream-dollop clues, honey on finished lines). Lagoon Islands (was
  Nurikabe) → a lagoon (sand islands with coastlines, palm clues, shells). Air Hockey → an arcade
  table (air holes, rink lines, mallets, puck streaks, LED clock).
- **Batch 4 (done):** Free the Banana (was Klotski) → the wooden Huarong Dao set (beech tray with an
  exit notch, grained blocks with etched spear/glaive/shield motifs, red lacquer banana block that
  slides out on the win, incense-stick timer). Quick Draw → a Western main street (saloon, store,
  bank clock creeping from noon to midnight by level, sheriff's office; banana lanterns as the GO
  signal; hatted stick-figure gunslingers with a masked rival; tumbleweed). Color Tide (was Flood
  It) → Lab Pixies' Flood-It! (black, seamless flat squares in its 6 colours, round buttons, "Step n
  / budget", colour ripple from the corner). Ledge Brawl (was Gun Mayhem) → its night rooftops
  (skyline, rooftop / plank / girder platforms, stick-figure fighters in hats with tracers and name
  tags, riveted steel controls, fighter-chip HUD with a clock). Plane Crash → the Aviator crash-game
  look (sunburst, red plane on an animated red curve, big multiplier, history pills, green FLY /
  orange CASH OUT; the plane really dives and explodes). Hacker → a green CRT terminal (scanlines,
  digital rain, keycaps, red TRACE meter, ACCESS GRANTED/DENIED; replaced by Critter Duel in Oct
  2026). Minesweeper → classic Windows Minesweeper (teal desktop, bevels, pixel numbers, LED
  counters, reacting smiley, red hit mine, crossed-out wrong flags; replaced by Lawn Defense in Oct
  2026).
- **Batch 5 (done):** Jungle Loop (was Slitherlink) → a jungle snake (pebble dots, clue river stones
  that turn mossy or red, every drawn edge is scaly snake body with heads/tails per chain and an
  ouroboros when the loop closes, twig ✕s, bamboo timer). Chef's Order (was Uncle Roger Review) → a
  TV kitchen (subway tiles, butcher block, recipe cards on a cutting board, chalked dish, twist
  kitchen timer, silver cloche SERVE, mustached banana uncle with thumbs up / "Haiyaa"). Spot the
  Difference → app-style framed pictures (sky and meadow, ink-outlined sticker items, red marker
  circles, miss ✕, pencil timer). Assassin → Hunter Assassin (tiled floor, concrete walls, container
  cover, hazard door, flashlight cones, red-jacket guards, banana ninja, chunky joystick, round
  SHOOT). Parking → a top-down lot (asphalt, bays, hazard curbs, glowing P bay, parked cars, striped
  coupé with brake/reverse lights, dashboard wheel, D/R lever, brake pedal). Header Duel (was Head
  Soccer) → the real game's look (stadium, crowd, ad boards, nets, banana vs tomato heads with
  boots, spinning ball, scoreboard, framed keys). Tower of Hanoi → the wooden toy (plywood base,
  dowels, 3/4-view rainbow rings, brass goal peg with pennant, hourglass).
- **Batch 6 (done):** Lights Out → Tiger Electronics' 1995 handheld (silver case, mauve rubber keys
  that glow pink-red, LIGHTS OUT logo, red LED moves/lights readout, LED clock bar, victory "show of
  lights" chase). Maze Muncher → arcade Pac-Man (#2121FF double-line walls and outlined blocks,
  peach pellets, a chomping yellow wedge, red Blinky whose eyes look where it goes, Namco pixel
  digits, the bonus-fruit level row, blue-rimmed arcade keys). Laser Dodge → a museum laser hallway
  (steel bezel, polished stone and red haze, white-hot beams, swinging wall turrets, prizes under
  glass on the plinths, masked banana; it steers with the `FloatingJoystick` since Oct 2026). Cat
  Burglar → a night mansion with a literal cat burglar (parquet, soft shadow pools, plum walls with
  gold molding, furniture on every cover block, coin stacks, guard dogs in caps with flashlight
  cones, a masked yellow tabby with a swag sack, green-lit exit). Brick Breaker → BlackBerry's Brick
  Breaker (metal floor plates, hazard frame drawn outside the field, embossed zig-zag bricks, blue
  hover paddle, steel/fire/ice ball, pill capsules). Dodgeball → a school gym (padded wall, amber
  scoreboard, maple court with a banana logo, open treasure chest, rubber playground balls,
  sweatband banana; joystick under the court since Oct 2026, now the `FloatingJoystick`). Chess
  Sweep (was Solo Chess) → Chess.com's Solo Chess (green board with coordinates, vector "neo" pieces
  that turn black when locked, "1" badges, yellow squares, capture rings, chess clock).
- **Batch 7 (done):** Banana Flutter (was Flappy Banana) → the original Flappy Bird (flat teal sky,
  cream cloud band, pale city and bushes, banded green pipes with wide lips, striped scrolling
  ground, white outlined pixel score; a crescent banana with Flappy's eye, lips and wing; sunset,
  dusk, night city, then a rain storm with red pipes). Reflex Grid → a TV game-show number board
  (blue monitor tiles with gold numbers over empty tile sockets, drifting stage spotlights, a
  chasing marquee, podium counter and timer lights; one Canvas hit-tested with the old tile rects;
  replaced by Cheer Up Monkey in Oct 2026). Stack → Ketchapp's Stack (isometric slabs, hue drift,
  pastel sky, dust, thin score, falling offcuts, perfect-drop ring). Juice Blade (was Fruit Ninja) →
  Fruit Ninja Classic (dojo planks, FruitArt fruit that split into halves with flesh, juice stains,
  tapered blade, red-marked bombs with a sparking fuse and a white-out, watermelon score and three
  ✕). Sketch Hop (was Doodle Jump) → classic graph paper (sketchy pills, cracked platforms that
  snap, coiled springs, a banana Doodler, torn-paper strip, goal flag; dusk and space papers).
  Jetpack Banana → Jetpack Joyride's lab (riveted panels, doorways, walkway, red-alert beacons,
  space windows, machine-gun jetpack tracers, bat-winged lab mutants). Square Sprint (was Geometry
  Dash) → the real GD look (per-level colour, ground tiles and glow line, white-rimmed spikes and
  pillars, pink/green portals, GD cube that spins and snaps, GD ship, progress bar, crash burst).
- **Batch 8 (done):** Prism Pass (was Color Switch) → the real Color Switch (charcoal void, thick
  cyan / yellow / purple / pink rings drawn exactly on the collision band, quartered switcher disc,
  thin white score, the ball bursting into dots). Log Darts (was Knife Hit) → Ketchapp's Knife Hit
  (teal backdrop with light shafts, end-on log with growth rings, silver knives with orange handles,
  iron plates at their true angular width, knife column, clank tumble, the log splitting on a win).
  Rainbow Roll (was Color Bump) → Color Bump 3D (pale perspective track tuned to the old look-ahead,
  rows of 3D cubes that scatter where the ball rolls through, paint gates with a swap sign, progress
  bar, vivid per-level backdrops). Bridges → an archipelago (sandy palm islands with clue discs,
  plank bridges with rope rails). Tents & Trees → Frozax's Tents and Trees (peach card, dark plots,
  lime grass, low-poly trees, red tents, clue strips; the grid now fits the card at 6–8 columns).
  Crate Push → classic Sokoban (orange bricks, floorboards, green ✕ targets, X-braced crates, a
  banana keeper in a blue cap, steel d-pad keys). Space Rubble (was Asteroids) → Atari's 1979 vector
  game (black screen, glowing white rock outlines that wrap across the edges, yellow arrow ship, dot
  bullets, round arcade buttons).
- **Batch 9 (done):** Canyon Plink (was Ricochet Shot) → a red-rock canyon plinking range (sandy
  floor, sandstone mesas with cliff faces and cast shadows, tin cans knocked flying, a banana-grip
  six-shooter whose cylinder shows the rounds, tracer and ricochet sparks; midday to moonlight).
  Moon Touchdown (was Lunar Lander) → Atari's vector Lunar Lander (glowing ridge line, lit pad with
  landing lights, the Apollo module in gold foil, flickering flame, crash debris, speed/fuel gauges;
  Earth, Mars's moons, a ringed giant). Tunnel Pump (was Dig Dug) → Namco's Dig Dug (blue sky with a
  flower per level, stippled strata, round tunnels, boulders, red goggled Pookas, green Fygars, a
  banana digger in the white helmet, the pump hose). Pyramid Hop (was Q*bert) → Gottlieb's Q*bert
  (tri-coloured cubes, the orange hopper arcing cube to cube, coiled Coily, the "change to" sample,
  @!#?@! and a fall into the void). Slide Bots (was Ricochet Robots) → the board game (ivory
  squares, black walls, the yellow ringed-planet target, glossy robot pieces, sand timer). Decoy →
  Metal Gear Solid's Soliton radar (phosphor map, red blips with cones, "?"/"!" marks, sound rings,
  objective marker). Sniper → a mobile sniper scope over a mountain outpost (snowcaps, pines, huts,
  a watchtower, sandbags) with red stick-figure soldiers that shoulder rifles and topple when hit.
- **Batch 10 (done):** Rock 'n' Rocket → Rock n' Roll Racing worlds (desert, grassland, forest, ice
  planet, night city, volcanic and lava plains; red-and-white kerbs, asphalt exactly as wide as the
  physics allows, chequered line, vector race cars, flaming missiles; flag/medal/missile-pip HUD).
  Mirror Maze → Deflektor's optics lab (steel tiles, riveted walls, laser cannons, pivot-disc
  mirrors at the beam's exact angle, red beams with white-hot cores, green teleport exit). Pipe Flow
  → Pipe Mania plumbing (stone/steel/sewer tiles in an iron frame on a brick wall, flanged steel
  pipes, glowing banana juice, a feed tank and a drain grate instead of IN/OUT). Neon Trails (was
  Light Cycles) → TRON's grid (neon blue → violet → Clu's orange-red, light ribbons, sleek cycles,
  derezz bursts, rival bike icons). Banana Bomber → Hudson's Bomberman (checkered floors by world,
  stone pillars, brick blocks, sparking bombs, the flame cross, Ballom balloons, a banana in
  Bomberman's helmet). Guard Patrol → a high-tech vault facility (hazard walls with sentry turrets,
  robot sentries with the exact old scanner cones, a steel vault chamber that is exactly the win
  box, a masked banana thief, an alarm lamp that lights with red turrets and tracers). Banana
  Getaway (was Rush Hour) → ThinkFun's set (charcoal tray with an exit gap, plastic cars and trucks,
  the yellow banana car). Artillery Duel → Scorched Earth (banded skies from day to a red storm,
  layered dirt, domed tanks on treads, a spinning banana shell with a short comet tail, shell pips
  and a wind flag).
- **The pass is complete** (2026-10-01): batches 1–10 cover the 71 games that existed before Batch
  19. The six Batch 19 games (Queens … Desert Golf) were left out on purpose: they were built to
  mimic their originals.
- Patterns for this work (presentation-only state, overlay parallax, per-letter measuring,
  level of detail…) are in GAME_PATTERNS.md → "Patterns from the visual redesign".

## Gesture conflict (important)
The feed navigates with **vertical swipes**. So a tap game must NOT use vertical swipe
gestures — they'd fight the pager.

Swipe/drag games (Swipe It, Slide/2048, Catch) instead set `locksFeed: true` in their
`GameDefinition`. While such a game is *actively playing* (past the countdown, no win/fail
overlay), `GamePageView` locks the feed's paging (`FeedView`'s `.scrollDisabled`) so the
gestures drive the game, not the pager. The lock is released during the countdown and on
the win/fail overlays, so there's always a window to leave.

- **Skip button is mandatory for feed-locking games.** Because the paging lock blocks
  manual swipes, `GamePageView` shows a bottom-center down-chevron button (only when
  `game.locksFeed`) that programmatically advances to the next game. Any new
  `locksFeed: true` game gets this for free — don't remove it.

## Game titles: no other company's trademarks (Oct 2026)
Before launch every title that is a registered or pending trademark, a well-known game's name, a
real person's character, or a word Apple rejects ("Flappy") was renamed. Internal ids, type and file
names are unchanged (players never see them, and favourites/progress are keyed by id). **When adding
a game, pick an original title**: check the USPTO/EUIPO registers (Justia and trademarkelite
summaries work in a web search) and the App Store (iTunes Search API) before using it.
- Gold Miner → **Nugget Hook**
- Cover Fire → **Compound Dash**
- Roll the Ball → **Groove Slider**
- Head Soccer → **Header Duel**
- Fruit Ninja → **Juice Blade**
- Doodle Jump → **Sketch Hop**
- Geometry Dash → **Square Sprint**
- Color Switch → **Prism Pass**
- Asteroids → **Space Rubble**
- Lunar Lander → **Moon Touchdown**
- Dig Dug → **Tunnel Pump**
- Q*bert → **Pyramid Hop**
- Rush Hour → **Banana Getaway**
- Flight Control → **Landing Lines**
- Block Blast → **Grid Burst**
- Ricochet Shot → **Canyon Plink**
- Ricochet Robots → **Slide Bots**
- Klotski → **Free the Banana**
- Binairo → **Berry Balance**
- Flappy Banana → **Banana Flutter**
- Uncle Roger Review → **Chef's Order**
- Lolo → **Statue Maze**
- Light Cycles → **Neon Trails**
- Bloxorz → **Topple Block**
- Gun Mayhem → **Ledge Brawl**
- Knife Hit → **Log Darts**
- Color Bump → **Rainbow Roll**
- Desert Golf → **Sunset Putt**
- Solo Chess → **Chess Sweep**
- Flood It → **Color Tide**
- Fruit Merge → **Fruit Tumble**
- Slitherlink → **Jungle Loop**
- Nurikabe → **Lagoon Islands**
- Masyu → **Pearl Chain**
- Also changed with the renames: Chef's Order's verdicts ("Uncle Roger approves" / "Haiyaa…" → "Chef
  approves" / "Oh no… wrong order"), and Pyramid Hop's fall balloon ("@!#?@!" → a generic "#%&!").
- Kept, checked: generic or descriptive names (Peg Solitaire, Tower of Hanoi, Air Hockey, whose mark
  lapsed in 2004, Lights Out, cancelled 2003, Brick Breaker, Stack, Queens, Quick Math, Tents &
  Trees, Breach, Assassin, Quick Draw, Sniper, Decoy, Dodgeball…) and our own names.
- Still to consider: some art copies the originals' characters closely (that's copyright, not
  trademark), and the splash's "GAME OF GAMES" echoes NBC's "Ellen's Game of Games" (its old "THE
  GAME OF GAMES" registrations are cancelled).

## Current games (77, genres: reflex / brain — the only two)
The catalog has grown well past the original handful. **`GameRegistry.all` in
`GameDefinition.swift` is the single source of truth** for what ships and in what order —
this doc no longer enumerates every game (that list drifts). As of this pass there are
**77 games**, spanning the original tap games, the arcade-classic pixel batches, the two
combat shooters, the brain/strategy batch, and the Batch 19 set below. (A cull removed 8
too-easy/too-similar games — Cut the Rope, Bug Squash, Weight Balance, Tap the Banana, Catch!,
Retro Runner, Pixel Invaders, and Spearman — replaced by the Batch 17 brain/strategy set. A second
cull removed Dots and Boxes (the AI opponent took the fun away), Turret Defense (too repetitive),
Passpeek PIN, Passpeek Code and Missing Number (too boring) and Color the Pixel (too hard) —
replaced by Batch 19. A third, in Oct 2026, removed Minesweeper (too hard), Hacker and Reflex Grid
(too boring), replaced by Lawn Defense, Critter Duel and Cheer Up Monkey below.)

Newest additions (Oct 2026 — three hit games, renamed because their names are registered
trademarks; each modeled on the original's look from store screenshots):
- **Lawn Defense** — reflex — Plants vs. Zombies with Plants vs. Zombies 2-style worlds: tap a seed
  packet, then a lawn tile; tap falling suns to pay. Ten plants in a two-row seed bar: sunflower,
  peashooter, corn popper (two shots), frost berry (slows), melon lobber (arcs over shields and graves,
  splashes), walnut, banana peel (arms, then trips a zombie flat for 2.5 s), flytrap (swallows, then
  chews; since Oct 14 2026 the eating is animated in the 1.6 s the eaten zombie lingers: it strikes over
  the zombie's head, hauls it back with its legs kicking out of the jaws and gulps it down three times;
  a boss gets a lunge and snap), cherry bomb (3×3) and hot chili (the whole lane; thaws ice). One world per level, each ending
  with a boss whose health bar replaces the flag meter: backyard groundskeeper (walks a lane smashing
  plants, flings his imp), desert pharaoh (graves that block shots, mummies out of the sand), pirate
  captain (cannonballs, pirates swinging in), frontier locomotive (charges two lanes; a peel derails it,
  a sound walnut stops it), glacier mammoth (freezes a lane, rolls snowballs), future mech (lane laser,
  missiles), rooftop brain-bot at night (fire/ice balls, stomp, drops zombies; less sky sun). New
  zombies: shield bearers, spring-booted jumpers that vault the first plant, helmeted runners; every
  world dresses them (mummy wraps, pirate stripes, ponchos, parkas, silver suits). A standing boss
  blocks the last column of its lanes; lit bombs can't be squashed; the win waits 2 s for the boss to
  topple. Oct 9 2026: made harder on request ("level 5 should be the new level 1"): a look-ahead bot
  that won the old levels 97 / 68 / 55% at L5 / L6 / L7 wins the new ones 92 / 69 / 57 / 36 / 25 / 7 /
  1%. Oct 17 2026: the ramp made gentler on request ("level 2 is already too hard… make level 2 the new
  level 5"; L6 / L7 continue gently): the bot now wins 91 / 88 / 83 / 79 / 73 / 59 / 33%, so L5 plays
  like the Oct 9 L2, L6 like its L3 and L7 like its L4 (a slower bot: 47 / 40 / 31 / 34 / 28 / 16 / 8%).
  Worlds, bosses and the zombie kinds each level introduces are unchanged. `LDWorld` (plain value, fixed-dt `step`) is in LawnDefenseGame.swift; the art is in
  LawnDefenseArt.swift (`LDLawnArt`, worlds, plants, zombies) and LawnDefenseBosses.swift
  (`LDBossArt`). Plant and boss names are generic; the six new plants, the bosses and the world outfits
  are original designs, but the first four plants and the coat-and-tie zombie still follow the 2009
  game's look (see "Still to consider" under Game titles). Took Minesweeper's slot.
- **Critter Duel** — brain — a Pokémon-style battle with original fruit critters: Banano (a grass
  banana) faces 1–3 rivals and a bell-pepper boss at L7; four moves (three types + a banana Snack
  that heals twice), type chart, speed order, crits. Grass platforms, cream HP boxes (the rival's
  shows its line-up), teal message box, type-coloured move buttons. `CDBattle` resolves a turn into
  events the view plays back; a smart bot wins 100/99/94/80/68/24/3% of L1–7. Took Hacker's slot.
- **Cheer Up Monkey** — brain — Monkey GO Happy: a sad orange monkey wants the banana in a chest
  locked by coloured symbol wheels. Mini monkeys peek out from behind cover or hide in barrels, pots
  and crates (tap to open); each shows a placard (its wheel's colour + symbol) once, then hops into
  the basket with it, so the player must remember the sign (the item circles that kept the signs were
  removed on 2026-10-11). From L2 one dice wheel means "count the gems of my colour" (some shut in
  containers, other colours and crystal gems are decoys). Set every wheel, tap the banana, the monkey
  jumps for joy. Scenes: dusk cottage, temple, ship's deck, reef, then night / sunset / storm.
  Oct 11 2026, made harder on request: 4 wheels and 4 mini monkeys at L1 up to 8 wheels and 7 mini
  monkeys at L7 (was 2→5 wheels, 2–3 monkeys), eight wheel colours (yellow, pink, teal added), a
  two-row lock past five wheels, 15 prop spots; clocks 34/36/34/32/30/24/21 s. `CMStage` deals
  always-solvable stages (checked on 21k deals; a deal that can't fit every clue gem is re-dealt).
  Took Reflex Grid's slot.
- **`FloatingJoystick`** (`FloatingJoystick.swift`) — the shared one-thumb stick under the arena for
  Dodgeball and Laser Dodge (their old drags hid the action under the finger). Floating (centres
  under the thumb anywhere in the strip; the base rests where last used, clear of the page's skip
  button in the middle), short throw (full speed at 19% of the base), a 10% dead zone then a √
  response, and the centre follows the thumb past full push so reversals are instant. Each game
  draws its own base and knob. Never put a control at the bottom centre of a `locksFeed` game: the
  page's skip button sits there (the harness's play mode doesn't draw it; check with `MODE=page`).

Newest additions (Batch 19 — puzzle & physics, each modeled closely on a hit mobile game's look):
- **Queens** — brain — LinkedIn's daily puzzle: one crown per row, column and pastel colour region,
  no two touching. Tap cycles X → crown → empty; clashes stripe red (auto-check) and cost one of 3
  strikes. Boards are generated solution-first, repaired until a solver proves the answer UNIQUE,
  and L1–5 are graded by a small logic solver so they need no guessing. Prefetched via `BoardCache`.
- **Grid Burst** (was Block Blast) — brain — drag 3 dealt pieces onto an 8×8 navy board; full
  rows/columns blast. Bevelled glossy blocks, the dragged piece lifted above the finger, ghost +
  recolour preview of lines about to clear, praise banners. Fail when no tray piece fits.
  `locksFeed`.
- **Tile Trio** — brain — the Tile Master triple-match: layered pyramids of fruit tiles (covered
  tiles dim), a wooden 7-slot tray that groups twins and pops trios. Winnable by construction (kinds
  assigned along a random uncovering order with a capped tray load). Fail when the tray fills.
- **Fruit Tumble** (was Fruit Merge) — brain — Suika: drag to aim, drop fruit into the tub; touching
  twins merge up the chain to the level's goal fruit. `FMWorld` is a position-based circle solver
  (friction, fixed substeps). Fail if fruit sits above the rim. Clocks tuned with a headless bot.
  `locksFeed`.
- **Landing Lines** (was Flight Control) — brain — draw routes to land red jets / yellow planes /
  helicopters on the matching runway or pad; any mid-air collision fails. Painted airfield, top-down
  aircraft with shadows, spinning props/rotors, proximity rings. `locksFeed`.
- **Sunset Putt** (was Desert Golf) — reflex — Desert Golfing: flat sky, flat sand, slingshot shots,
  stroke budget per level; every generated hole is verified by a shot search to have a robust
  hole-in-one. Palette slides from midday to night by level. Prefetched via `BoardCache`.
  `locksFeed`. Oct 12 2026: the course is drawn raised (`lift`, about half a width on a phone) so
  the sand below leaves room to pull back; a ball wedged in a crack or at the foot of a wall now
  counts as at rest after 0.3 s (it used to sit there until the 9 s cap, ignoring drags).

Shared art: `FruitArt.swift` draws 13 vector fruits (Suika style, optional kawaii face) in a unit
circle — Fruit Merge uses them as rotating bodies (pre-rendered once via `ImageRenderer`), Tile
Trio as tile icons. Reuse it for any future fruit art instead of emoji.

Newest additions (Batch 17 — brain / strategy-and-action, in the Tank Maze / Assassin spirit):
- **Mirror Maze** — brain — a Deflektor-style laser room: tap mirrors to rotate them 15° and bend
  deadly beams out of your lane, then d-pad the banana to the exit. (Replaced Laser Reflect.)
- **Pipe Flow** — brain — rotate pipe tiles to connect source→drain before the clock; solvable
  boards laid on a carved path, then scrambled.
- **Neon Trails** (was Light Cycles) — reflex — a Tron duel; box the AI cycles into a trail (turn ◄
  ►) without crossing any wall. AI does survival lookahead + scalable aggression.
- **Banana Bomber** — brain — Bomberman on a pillar/crate grid; drop bombs, dodge the + blast,
  clear every enemy (bombs chain).
- **Guard Patrol** — brain/stealth — creep past sweeping/patrolling vision cones to the vault
  (the non-combat cousin of Assassin).
- **Banana Getaway** (was Rush Hour) — brain — a sliding-jam puzzle (drag cars) to free the banana
  car; boards are BFS-verified solvable with a per-level minimum move count. Uses the feed lock +
  skip button.
- **Artillery Duel** — reflex — Scorched-Earth angle/power lobbing over terrain vs. a return-firing
  AI that sharpens each level; wind pushes every shell.

Newest additions (Batch 16 — combat shooters):
- **Sniper** — reflex — a scoped marksman game. You look through a crafted SCOPE at a parallax
  vista; DRAG to pan, tap FIRE to hitscan whatever's under the crosshair (so aiming is exact — no
  collision guesswork). Red soldiers patrol between cover; one periodically stops and RAISES its
  weapon, painting a growing red beam at your scope — down it before the beam completes or you're
  hit. Missing startles the nearest enemy into aiming, and the magazine is limited. Down every
  target to win; get shot, run dry, or time out to fail. Uses the feed lock (drag to aim) + skip
  button. (This **replaced** Banana Commando, whose scrolling-lane collisions stayed too glitchy.)
- **Rock 'n' Rocket** — reflex — a top-down combat racer: 3 laps of a long, twisty circuit vs.
  2 AI cars, GAS/steer + a few rockets that spin rivals out. Cars are small, can't overlap, and
  physically bump/shove each other. Win by finishing in front.

`locksFeed` games use swipe/drag, so they lock the pager while playing and show a skip button —
see "Gesture conflict" below. Sniper drags to aim (so it locks the feed + shows the skip button);
Rock 'n' Rocket uses on-screen buttons, so it stays tap-safe and does **not** lock the feed.

## Contract
```swift
GameDefinition(
    id: "unique-id",
    title: "Display Name",
    emoji: "🍌",
    genre: .reflex,          // or .brain — sets feed weighting + point pool
    levelCount: 7,
    locksFeed: false,        // true for swipe/drag games (see "Gesture conflict")
    manual: GameManual(      // required — book button; see DigDug for the template
        bullets: [           // 2–4 short English bullets on the core rules + controls
            "Tap a peg, then a highlighted hole two spaces away in a line.",
            "The peg leaps the one between and removes it.",
            "Clear the board to a single peg to win before time runs out.",
        ],
        bulletsVI: [         // same, in Vietnamese (empty = fall back to English)
            "Chạm một quân, rồi ô trống cách hai ô theo đường thẳng.",
            "Quân nhảy qua quân ở giữa và loại nó.",
            "Giảm bàn còn một quân để thắng trước khi hết giờ.",
        ],
        demo: nil            // optional "<game.id>-win" clip name (mp4 in the target); nil = bullets only
    ),
    makeView: { level, onWin, onFail in AnyView(MyGameView(level: level, onWin: onWin, onFail: onFail)) }
)
```
`onWin`/`onFail` are the only ways a game talks back to the feed. Design each level's
difficulty from the `level` argument (1...7).

## Roadmap checkpoints (see docs/HISTORY.md)
- **A (done):** safe-area, auto-start countdown, fast difficulty ramp, sound effects,
  7 levels, fail→level-1, time limits.
- **B (done):** genre tagging + feed filter modes (All / Favorites / **Unplayed**).
- **C (done):** settings screen — per-genre frequency (Off/Low/Normal/High), sound
  on/off toggle, a real App Store update check (`UpdateChecker`). Plus search-by-name and the
  GOGs rename.
- **D+ (done):** the whole catalog was built out and expanded, then culled and refreshed — 77
  games now, including the arcade-classic pixel batches, the two combat shooters (Sniper, Rock
  'n' Rocket), the Batch 17 brain/strategy set, and the Batch 19 puzzle & physics set (Queens,
  Block Blast, Tile Trio, Fruit Merge, Flight Control, Desert Golf). See `GameRegistry.all`.
- **E (done):** manual redesign + Vietnamese localization. Manuals are now 2–4 bullets +
  optional looping win clip (no per-level notes); `Localization.swift` adds device-default +
  in-app English/Vietnamese toggle via `L(...)`. All 77 games + shared UI localized. Win clips
  (`<game.id>-win.mp4`) are recorded and dropped into the target incrementally — set each game's
  `demo:` as clips land.
