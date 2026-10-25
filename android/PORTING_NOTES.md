# GOGs Android port: porting notes

Native Android port of the iOS app ("A Banana Game" / GOGs) in Kotlin + Jetpack Compose.
The iOS sources are untouched; everything lives in `android/`.

## Build

- AGP 9.4.1 (built-in Kotlin), Kotlin 2.4.21 + Compose compiler plugin, Compose BOM 2026.09.00,
  Gradle 9.8.2 wrapper, compileSdk/targetSdk 37, minSdk 26, JDK 17 toolchain (run Gradle on JDK 17–21).
- `./gradlew assembleDebug` builds `app/build/outputs/apk/debug/app-debug.apk`.
- `./gradlew assemblePlaytest` builds `app/build/outputs/apk/playtest/app-playtest.apk`: the release
  build (R8, no debug checks) signed with the debug key. Use it to judge speed on a phone: Compose
  runs several times slower in a debug build, which felt like lag in scrolling, search and settings.
- `./gradlew testDebugUnitTest` runs the pure-logic unit tests.
- Test hooks (adb): `--es GOGS_START_GAME <game id>` skips the splash and opens that game;
  `--es GOGS_FAKE_STORE_VERSION 9.9` (+ optional `GOGS_FAKE_STORE_NOTES`) fakes a newer store
  version for the update pop-up (the iOS DEBUG environment variables' equivalent).

## Framework mapping

- SwiftUI views → Compose; `Canvas`/`GraphicsContext` → Compose `Canvas`/`DrawScope` with small
  helpers in `core/GameKit.kt` (Double-precision rects, paths, gradients, text).
- `TimelineView` / side `Task` loops → `rememberFrameLoop` (a `withFrameNanos` loop with real dt).
- Structured `.task` timers → `LaunchedEffect` coroutines with `delay`.
- GraphicsContext blur/shadow filters → native `BlurMaskFilter` paints (`core/Blur.kt`).
- `UInt128` bitmask solvers → `core/Bits128.kt` (two longs).
- `UserDefaults` → a Preferences DataStore (`core/Prefs.kt`), read once at launch into a snapshot,
  written asynchronously. Same keys as iOS (`favoriteGameIDs`, `masteredGameIDs`, `feedFilter`,
  `genreWeights`, `feedOrders`, `feedPositions`, `lastGameID`, `soundEnabled`, `appLanguage`, stats).
- Haptics → `Vibrator` predefined effects (tick / double click / heavy click).
- Sound → the same synthesized tones (sine mixes, 5 ms attack, squared decay) rendered once to WAV
  files in the cache directory and played with `SoundPool`. No audio or image assets exist in the
  iOS project (the AppIcon set is empty), so there was nothing to convert; the launcher icon is a
  vector banana.
- SF Symbols → Material icons (extended set).
- SwiftUI's named system colours (`.green`, `.orange`, `.mint`…) → `core/SystemColors.kt` (`SysColor`).
- `ScrollView` paging feed → `VerticalPager`; sheets → full-screen slide-up overlays; the manual's
  `fullScreenCover` → a full-screen `Dialog`.
- Live manual demos (`\.isDemo`) → `LocalIsDemo` composition local; each game runs its scripted demo.
- Strong skipping (on by default in Kotlin 2.x) skips a composable whose arguments are unchanged, and a
  mutable game object compares by identity. So a sub-composable that receives the world and reads its
  plain fields (a HUD, a key that lights up) never redraws. Pass the changing values as parameters,
  make the fields snapshot state, or read the frame-tick `State` inside. A parameter the body never
  reads is left out of the skip check, so passing an unused tick doesn't help.

## Names

Kotlin packages/classes use the player-facing titles; internal ids are unchanged so data keys
match iOS. Renamed titles (old → new): Gold Miner → Nugget Hook (`gold-miner`), Cover Fire →
Compound Dash, Roll the Ball → Groove Slider, Head Soccer → Header Duel, Fruit Ninja → Juice Blade,
Doodle Jump → Sketch Hop, Geometry Dash → Square Sprint, Color Switch → Prism Pass, Asteroids →
Space Rubble, Lunar Lander → Moon Touchdown, Dig Dug → Tunnel Pump, Q*bert → Pyramid Hop, Rush Hour →
Banana Getaway, Flight Control → Landing Lines, Block Blast → Grid Burst, Ricochet Shot → Canyon
Plink, Ricochet Robots → Slide Bots, Klotski → Free the Banana, Binairo → Berry Balance, Flappy
Banana → Banana Flutter, Uncle Roger Review → Chef's Order, Lolo → Statue Maze (`lolo`), Light Cycles
→ Neon Trails, Bloxorz → Topple Block, Gun Mayhem → Ledge Brawl, Knife Hit → Log Darts, Color Bump →
Rainbow Roll, Desert Golf → Sunset Putt, Solo Chess → Chess Sweep, Flood It → Color Tide, Fruit Merge
→ Fruit Tumble, Slitherlink → Jungle Loop, Nurikabe → Lagoon Islands, Masyu → Pearl Chain.

The root-level Swift files (Flappy Banana, Stack, Fruit Ninja, Doodle Jump, Jetpack Banana,
Geometry Dash, Color Switch, Knife Hit, Color Bump, PixelFX) are in the Xcode target's Sources
phase and in `GameRegistry.all`, so they are ported too.

## Screens

- Splash (Return to … / Start Fresh): ported.
- Feed (pager, filter menu + reshuffle, banana dropdown, per-mode remembered order/position,
  genre-weighted shuffle, drop-out advance, skip button for feed-locking games (the pager isn't
  locked; see Behaviour differences), end page,
  pull-to-reshuffle): ported.
- Game page (countdown, win/fail overlays, reward burst, level, favorite, manual): ported.
- Manual (live demo + bullets): ported.
- Settings, Search, Stats, Update prompt: ported.

## Games (feed order)

Status legend: done = rules, levels, art and demo ported.

1. Peg Solitaire (`peg-solitaire`): done
2. Quick Math (`quick-math`): done
3. Banana Memory (`banana-memory`): done
4. Tank Maze (`tank-maze`): done
5. Color Trap (`color-trap`): done
6. Statue Maze (`lolo`): done
7. Turbo Racer (`turbo-racer`): done
8. Slide (`slide-2048`): done
9. Cup Shuffle (`cup-shuffle`): done
10. Nugget Hook (`gold-miner`): done
11. Breach (`breach`): done
12. Compound Dash (`cover-fire`): done
13. Spiral Galaxies (`spiral-galaxies`): done
14. Pearl Chain (`masyu`): done
15. Bottle Order (`bottle-order`): done
16. Topple Block (`bloxorz`): done
17. Line Connect (`line-connect`): done
18. Groove Slider (`roll-the-ball`): done
19. Berry Balance (`binairo`): done
20. Lagoon Islands (`nurikabe`): done
21. Air Hockey (`air-hockey`): done
22. Free the Banana (`klotski`): done
23. Quick Draw (`quick-draw`): done
24. Color Tide (`flood-it`): done
25. Ledge Brawl (`gun-mayhem`): done
26. Plane Crash (`plane-crash`): done
27. Critter Duel (`critter-duel`): done (battle rules + SplitMix RNG ported bit-for-bit; demo seed unit-tested)
28. Lawn Defense (`lawn-defense`): done (LDWorld sim ported 1:1 incl. SplitMix RNG; all 7 worlds, 10 plants, 7 bosses)
29. Jungle Loop (`slitherlink`): done
30. Chef's Order (`uncle-roger`): done (ChalkboardSE → Android's casual face)
31. Spot the Difference (`spot-difference`): done (sticker icons: SF Symbols → Material; bird → bee, ant → bug, tortoise → lotus)
32. Assassin (`assassin`): done
33. Park King (`parking`): done
34. Header Duel (`head-soccer`): done
35. Tower of Hanoi (`tower-of-hanoi`): done
36. Lights Out (`lights-out`): done
37. Maze Muncher (`maze-muncher`): done
38. Laser Dodge (`laser-dodge`): done (shared `core/FloatingJoystick.kt`)
39. Cat Burglar (`cat-burglar`): done (deferred batch) — night mansion (parquet, moonlight, soft shadow pools, plum walls with gold molding, furniture on every cover block, guard doors; cached to a bitmap redrawn only when the alarm or the exit lock changes), coin stacks, guard dogs in caps with flashlight cones and "!" bubbles, a masked tabby that fades on shadow tiles, reinforcement swarm and tracers on the alarm, same generator via BoardCache prefetch, same patrol / chase / fire rules, scripted demo; unit tests check every level's board and that the demo loots everything unseen and escapes.
40. Brick Breaker (`brick-breaker`): done (power-up icons: SF Symbols → Material)
41. Dodgeball (`dodgeball`): done
42. Chess Sweep (`solo-chess`): done (prefetched via BoardCache)
43. Banana Flutter (`flappy-banana`): done (static backdrop cached in a bitmap)
44. Cheer Up Monkey (`cheer-up-monkey`): done (deferred batch) — Monkey GO Happy stage (dusk cottage / temple / ship's deck / reef, then night, sunset and storm versions, cached to a bitmap), outlined props that open (barrel lids tip off, pot lids lift, crate lids swing up), peeking and hidden mini monkeys whose placard shows once before they hop into the wicker basket, gems with decoys, the chest with its padlock and glowing banana, the big monkey that sobs or jumps for joy, brass lock wheels on a nailed plank (two rows past five); same SplitMix64 `CMStage` dealer and timings, scripted demo. The art is drawn in points (the canvas is scaled by density) so every iOS number carries over; unit tests check the RNG against the SplitMix64 test vector, 3,500 deals for well-formedness and solvability, and the demo script.
45. Stack (`stack`): done
46. Juice Blade (`fruit-ninja`): done
47. Sketch Hop (`doodle-jump`): done (Noteworthy → Android casual face)
48. Jetpack Banana (`jetpack-banana`): done (corridor strip pre-rendered to a bitmap and slid)
49. Square Sprint (`geometry-dash`): done
50. Prism Pass (`color-switch`): done
51. Log Darts (`knife-hit`): done
52. Rainbow Roll (`color-bump`): done
53. Bridges (`hashi-bridges`): done — archipelago art (sea swells, sandy palm islands, plank bridges with rope rails), same web generator via BoardCache prefetch, crossing check, connectivity win, scripted demo.
54. Tents & Trees (`tents-trees`): done — Frozax-style campsite card, same solved-first generator via BoardCache prefetch, perfect-matching win check, deduction demo; grid drawn in one Canvas and hit-tested with the iOS cell geometry.
55. Crate Push (`crate-push`): done — Sokoban warehouse (running-bond bricks, floorboards, ✕ targets, X-braced crates, banana keeper), same push-BFS verifier on Long bitmasks via BoardCache prefetch, corner-deadlock fail, steel d-pad, scripted 4-push demo.
56. Space Rubble (`asteroids`): done — Atari vector look (wrapping glowing rock outlines, arrow ship with flicker flame, dot bullets/bursts), same physics and torus collisions, round arcade hold buttons (RotateLeft/RotateRight/LocalFireDepartment/WifiTethering icons), lead-intercept demo autopilot.
57. Canyon Plink (`ricochet-shot`): done (deferred batch) — red-rock canyon plinking range (rippled sand with specks and pebbles, sandstone mesas with cliff faces, strata, cracks and cast shadows, cached to a bitmap; buttes under the hour's sky from midday to moonlight), tin cans that get knocked flying, a dotted sight line from the same `simulate`, tracer, ricochet sparks, a banana-grip six-shooter whose cylinder shows the rounds, cartridge belt, brass-rimmed FIRE (GpsFixed icon); same generator (greedy set cover over 360 traced aims, budget band) via BoardCache prefetch and the same 6-sub-step bullet, scripted two-shot demo. Unit tests check that the demo clears the room in two shots and that boards fit the bullet budget. Shared `core/PointArt.kt` (`inPoints`, `artBehind`) now draws iOS-unit art for both deferred-batch art ports.
58. Moon Touchdown (`lunar-lander`): done — Atari vector ridge over per-world rock, blinking pad lights, gold-foil Apollo lander, dust/debris effects, Earth / Mars moons / ringed giant skies, speed+fuel gauges (Speed/LocalGasStation icons), console hold keys, same physics and the iOS autopilot demo.
59. Tunnel Pump (`dig-dug`): done — Namco Dig Dug look (sky with a flower per level, stippled per-level strata, round tunnels, bedrock, teetering boulders, Pooka with halo, Fygar, helmeted banana digger, hose harpoon), same rules / monster AI / boulder physics stepped at the iOS 30 Hz cadence, ground cached to a bitmap redrawn only when a cell is dug, scripted demo. (Reviewed against iOS in the final batch: 934 Swift lines.)
60. Pyramid Hop (`qbert`): done — Gottlieb look (tri-colour cubes per level, arcing orange hopper, coiled Coily, change-to sample, #%&! balloon and fall into the void), same rules / hunter grace / clock, diagonal keys (NorthWest/NorthEast/SouthWest/SouthEast icons), DP-route demo.
61. Slide Bots (`ricochet-robots`): done — board-game art (ivory bevelled squares, black walls, ringed-planet target, glossy robot pieces on blue felt), same BFS-verified generator (Long state keys) via BoardCache prefetch, robots ease along their slides, Start/Replay/HourglassBottom icons, scripted overshoot-reset-backstop demo.
62. Decoy (`decoy`): done — Soliton radar (phosphor grid on green glass, hatched walls, scanlines, red guard blips with cyan/amber cones, ?/! marks, sound rings, pulsing objective, banana blip; map cached to a bitmap), same generator via BoardCache prefetch, same guard AI / vision / LOS, SettingsInputAntenna icon for decoys, scripted demo with the 4.3 s throw.
63. Sniper (`sniper`, locksFeed): done (deferred batch) — mobile sniper scope over a parallax mountain outpost (stars or clouds, snowcapped ridge, pine treeline, huts / watchtower / flag, grass, sandbags; day → dusk → night), red stick-figure soldiers that walk, shoulder their rifle with a thickening aim beam, and topple when hit; dark mask, lens shading, glint, range ticks, rim, danger ring, mil-dot reticle with the sway, recoil kick, muzzle bloom, hurt flash and screen shake; cartridge / blood-drop (WaterDrop icons) / helmeted-head HUD, bottom-right FIRE key. Same patrol / arming / aim-up / miss-startles rules and the exact drawn-body hit test; drag pans, scripted two-shot demo (unit-tested).
64. Rock 'n' Rocket (`rock-n-rocket`): done (deferred batch) — Rock n' Roll Racing worlds from above (desert cacti, grassland, forest, ice planet, night city lamps, volcanic and lava plains; scenery kept off the tarmac), red-and-white kerbs, grained asphalt as wide as the physics allows, edge lines, dashed centre line, chequered start (cached to a bitmap), vector race cars with the banana car's black stripe, flaming missiles, smoke and screen shake; flag / medal / missile-pip HUD, drawn arrow / missile / pedal keys. Same circuit harmonics, car physics in play-area fractions with point-space clamps and bumps, rockets and AI, scripted final-lap demo; a unit test confirms the demo fires and takes the flag first at 12 card sizes.
65. Mirror Maze (`mirror-maze`): done — Deflektor optics lab (steel tiles, riveted walls, wall cannons, pivot-disc mirrors at the beam angle, red beams with white-hot cores, green teleport pad; room cached to a bitmap), same tracer and directed-greedy generator (Int cell indices) via BoardCache prefetch, scripted demo; unit tests check the demo opens after its taps.
66. Pipe Flow (`pipe-flow`): done — Pipe Mania plumbing (bevelled stone/steel/sewer tiles with screws in an iron frame on a brick wall, flanged steel pipes, glowing juice flow, feed tank and drain grate), same carve-and-scramble generator via BoardCache prefetch, scripted 13-tap demo.
67. Neon Trails (`light-cycles`): done — TRON grid (neon blue → violet → orange-red, glowing grid and border, light ribbons, sleek cycles, derezz bursts, rival bike icons), same tick/AI/lookahead/aggression, TurnLeft/TurnRight keys, scripted wall demo.
68. Banana Bomber (`banana-bomber`): done — Bomberman arena (checkered floors by world, bevelled stone pillars, brick blocks cached to a bitmap that re-renders when one is blasted, sparking bombs, flame cross, Balloms, helmeted banana), same rules / chain blasts / chase AI stepped at 30 Hz, scripted two-kill demo.
69. Guard Patrol (`guard-patrol`): done — vault facility (floor panels, hazard-edged walls, turrets, tracers, red scanner cones, sentry bots, vault chamber = win box, masked banana thief, alarm lamp), same cones / alarm curtain / win box in px, look-ahead demo planner.
70. Banana Getaway (`rush-hour`, locksFeed): done (deferred batch) — ThinkFun's Rush Hour (charcoal tray with a raised rim, recessed squares, exit gap with banana chevrons, cached to a bitmap), top-down plastic cars and trucks (windshields, roofs, cargo beds, lights) and the yellow banana car with its decal, drawn in one Canvas and hit-tested with the iOS car frames; same generator and packed-state BFS (Long keys, 60 000-state cap, iOS expansion order) via BoardCache prefetch, cell-snapping drags within the free range, scripted two-move demo with eased slides. Unit tests check the demo board needs 2 moves and that boards are solvable, in bounds and overlap-free.
71. Artillery Duel (`artillery-duel`): done — Scorched Earth look (banded skies day → red storm with stars at night, layered dirt with grassy rim cached to a bitmap, domed tanks on treads, spinning banana shell with comet tail, blasts and mushroom clouds, shell pips and wind flag), same ballistics / AI aim search / phases, Material3 sliders in banana, GpsFixed FIRE key, scripted overshoot-then-hit demo (touches swallowed so its sliders can't be dragged).
72. Queens (`queens`): done (deferred batch) — LinkedIn Queens look (pastel region palette, thin in-region lines and thick ink borders, red diagonal clash stripes, X notes, vector crowns since Material has no crown icon, Cancel-icon strikes, crown wave on the win, board shake on a strike); same solution-first generator (weighted region growth, uniqueness repair by the backtracking solver, logic grading by singles / confinement / lookahead) via BoardCache prefetch, scripted deduction demo. Unit tests check the demo board is unique and deduction-solvable, that the script solves it without a strike, and that generated boards are unique with one crown per region.
73. Grid Burst (`block-blast`, locksFeed): done — Block Blast look (navy recessed board on blue, glossy bevelled blocks, lifted dragged piece with a blurred shadow, ghost + recolour preview of finishing lines, burst clears, gradient praise banners with an outline), same shape tiers / deal / prefill / stuck rules, touchDrag from the tray, scripted three-drop demo.
74. Tile Trio (`tile-trio`): done — Tile Master look (teal backdrop, cream mahjong tiles on green bases with FruitArt fruit, covered tiles dimmed, wooden 7-slot tray, trios slide together and pop with a burst), same layered-pyramid generator with the guaranteed uncovering order, tiles ease between board and tray, scripted 12-tap demo; unit tests check every level's tile count/trios and the Pipe Flow demo.
75. Fruit Tumble (`fruit-merge`, locksFeed): done — Suika look (cream tub with a wooden rim on a peach backdrop, FruitArt fruit with faces pre-rendered once per tier and stamped rotated, aim guide, flashing danger line, juice splashes, evolution strip, GOAL/NEXT bubbles), same position-based physics (10 substeps, friction, merges) at fixed 1/60 s, touchDrag aiming, scripted demo; a unit test confirms the demo's chain ends in a pear.
76. Landing Lines (`flight-control`, locksFeed): done — Flight Control airfield (mown grass, patches, trees, painted runways with piano keys / dashed centre lines / approach chevrons / dashed landing discs, helipad; cached to a bitmap), cartoon top-down jets, props and helicopters with ground shadows and spinning blades, dotted routes, blinking arrival chevrons, proximity rings, crash bursts, FlightLand HUD icon; same spawn / route-lock / landing / collision rules at fixed 1/60 s, touchDrag routes, scripted two-landing demo.
77. Sunset Putt (`desert-golf`, locksFeed): done (deferred batch) — Desert Golfing look (flat sky and sand from midday to night, pole and pennant, dotted slingshot aim line, off-top ball marker, out-of-bounds flash, stroke count / budget and hole dots), course raised by `lift` so the sand leaves room to pull back, holes pan in from the right; same deterministic 8-substep physics (sand bounce, rolling resistance, wedge rest) and generator verified by the robust hole-in-one search via BoardCache prefetch, fixed-step 60 Hz loop, scripted slingshot demo. Unit tests check that the iOS-tuned demo shot (20°, 0.57) still sinks here and that generated holes have a robust hole-in-one.

(All 77 games are ported, numbered in the iOS feed order that `games/GameRegistry.kt` follows. The eight marked "deferred batch" were ported last, at higher effort.)

### The final batch (done)

Eight complicated games were held back from the feed-order pass and ported last: Cheer Up Monkey,
Sniper, Rock 'n' Rocket, Canyon Plink, Cat Burglar, Queens, Banana Getaway and Sunset Putt. Each now sits
at its iOS feed position in `games/GameRegistry.kt`, and each has headless checks in
`DeferredGamesTest` (generators, solvability, and that the scripted manual demo really wins with the
ported logic: e.g. Canyon Plink's two bank shots, Rock 'n' Rocket's final lap at 12 card sizes, Sunset
Putt's iOS-tuned 20° / 0.57 shot). Their art is drawn in points (`core/PointArt.kt`), so the iOS
numbers carry over unchanged.

The same batch reviewed ten large, earlier ports against their iOS source: Lawn Defense, Critter Duel,
Turbo Racer, Ledge Brawl, Statue Maze, Free the Banana, Assassin, Brick Breaker, Tunnel Pump and Mirror
Maze. How:

- Every numeric table in the Swift (level ramps, palettes, poses: 68 of them) was matched against the
  Kotlin. All match; Lawn Defense's all-2 `bossPower` table is a constant 2.
- Every numeric literal in the Swift was looked for in the port (after `dp` / `delay` unit
  normalisation). The few left over are ellipses written as centre and radius, `360°` arcs written as
  2π, `measure(in:)` bounds, or iOS values that iOS itself never uses (Klotski's `goldDark`, the
  skyline's `count`).
- Every Swift function has a Kotlin counterpart (some renamed: Klotski's distance map and state key,
  Brick Breaker's demo intercept, Dig Dug's carving and popping, Assassin's spacing).
- Drag / tap thresholds are cell-relative on both sides, so there is no point-versus-pixel drift.

Fixed in the review:

- A strong-skipping sweep of every sub-composable that receives a game object found frozen
  displays: the Turbo Racer HUD (TIME, %, km/h) and its demo steer keys, the Assassin HUD (targets,
  alarm, ammo, clock), the Header Duel scoreboard (score and clock), the Juice Blade HUD (sliced
  count and misses), the Breach button (never greyed out with no charges left), and the demo d-pads
  of Decoy, Mirror Maze, Guard Patrol, Banana Bomber and Tunnel Pump. They now take plain values or
  read snapshot state. On iOS, only the demo's presses light those d-pads; the Android keys match.

## Behaviour differences

- Update check: Google Play has no public lookup endpoint like iTunes', so the real check reports
  "not listed" (shown as "You're up to date"), which is also what iOS sees today because the app
  isn't on the store. The pop-up itself is ported and can be exercised with the fake-version hook.
- Fonts: SwiftUI's rounded system design has no Android twin; the default sans is used.
- Sounds overlap (SoundPool mixes) where AVAudioPlayerNode queued them back to back.
- Safe-area: like iOS (whose feed reads zero insets), pages floor the top at 60dp and the controls
  sit 16dp from the top; on phones with a tall cutout this matches the iOS layout.
- System bars: the status bar and the navigation bar (gesture pill or 3-button bar) are both hidden,
  in the activity and in the manual's dialog, so nothing covers a game's bottom controls; a swipe
  from an edge shows them for a moment, and they're hidden again whenever the app regains focus.
- Screen size (`ui/FitToDesign.kt`): the layouts were designed on a 393 × 852 pt iPhone. On a phone
  smaller than 393 × 852 dp the whole UI is scaled down (density × k, k = the smaller ratio, never
  below 0.5) so every game shows in its entirety; bigger phones keep their density. The system font
  scale is ignored for the same reason (game text is sized to the art). The manual's Dialog gets its
  own density, so it's wrapped too.
- Feed lock: iOS locks the pager while a `locksFeed` game plays. Here the pager stays scrollable:
  every `locksFeed` game's play area consumes its own drags (`touchDrag` / `pressDown`), so a swipe
  outside it (HUD, top and bottom margins) leaves the game mid-play. The skip button is kept.
- Overlays (sheets, win/fail, the manual's demo) swallow touches without consuming them, so taps
  on their own buttons (Done, settings rows, search results, Next) always register. The win
  overlay's Next acts once (a second tap while it fades no longer skips a level), and the countdown
  starts on the same frame the level changes.
- Mascot: the 🍌 emoji is drawn as a vector banana (`core/Mascot.kt`) in Apple's bright yellow,
  because Android emoji fonts draw a duller, browner banana; the launcher icon matches.

## Needs manual testing on a device

- Feel of every game's controls (touch latency, joystick/drag sensitivity) on a real phone.
- Haptics strength (emulators have no vibrator).
- Pull-to-reshuffle at the top of the feed (nested-scroll overscroll).
- Language switch and persistence across launches.
