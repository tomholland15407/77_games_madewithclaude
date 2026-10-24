# GOGs Android port: porting notes

Native Android port of the iOS app ("A Banana Game" / GOGs) in Kotlin + Jetpack Compose.
The iOS sources are untouched; everything lives in `android/`.

## Build

- AGP 9.4.1 (built-in Kotlin), Kotlin 2.4.21 + Compose compiler plugin, Compose BOM 2026.09.00,
  Gradle 9.8.2 wrapper, compileSdk/targetSdk 37, minSdk 26, JDK 17 toolchain (run Gradle on JDK 17–21).
- `./gradlew assembleDebug` builds `app/build/outputs/apk/debug/app-debug.apk`.
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
  genre-weighted shuffle, drop-out advance, skip button for feed-locking games, end page,
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
39. Brick Breaker (`brick-breaker`): done (power-up icons: SF Symbols → Material)
40. Dodgeball (`dodgeball`): done
41. Chess Sweep (`solo-chess`): done (prefetched via BoardCache)
42. Banana Flutter (`flappy-banana`): done (static backdrop cached in a bitmap)
43. Stack (`stack`): done
44. Juice Blade (`fruit-ninja`): done
45. Sketch Hop (`doodle-jump`): done (Noteworthy → Android casual face)
46. Jetpack Banana (`jetpack-banana`): done (corridor strip pre-rendered to a bitmap and slid)
47. Square Sprint (`geometry-dash`): done
48. Prism Pass (`color-switch`): done
49. Log Darts (`knife-hit`): done
50. Rainbow Roll (`color-bump`): done
51. Bridges (`hashi-bridges`): done — archipelago art (sea swells, sandy palm islands, plank bridges with rope rails), same web generator via BoardCache prefetch, crossing check, connectivity win, scripted demo.
52. Tents & Trees (`tents-trees`): done — Frozax-style campsite card, same solved-first generator via BoardCache prefetch, perfect-matching win check, deduction demo; grid drawn in one Canvas and hit-tested with the iOS cell geometry.
53. Crate Push (`crate-push`): done — Sokoban warehouse (running-bond bricks, floorboards, ✕ targets, X-braced crates, banana keeper), same push-BFS verifier on Long bitmasks via BoardCache prefetch, corner-deadlock fail, steel d-pad, scripted 4-push demo.
54. Space Rubble (`asteroids`): done — Atari vector look (wrapping glowing rock outlines, arrow ship with flicker flame, dot bullets/bursts), same physics and torus collisions, round arcade hold buttons (RotateLeft/RotateRight/LocalFireDepartment/WifiTethering icons), lead-intercept demo autopilot.
55. Moon Touchdown (`lunar-lander`): done — Atari vector ridge over per-world rock, blinking pad lights, gold-foil Apollo lander, dust/debris effects, Earth / Mars moons / ringed giant skies, speed+fuel gauges (Speed/LocalGasStation icons), console hold keys, same physics and the iOS autopilot demo.

(Remaining games are listed as they are ported.)

### Deferred to a final higher-effort batch

These are skipped in the feed-order pass and ported last (the PR waits for them):

- Cheer Up Monkey (`cheer-up-monkey`)
- Sniper (`sniper`)
- Rock 'n' Rocket (`rock-n-rocket`)
- Canyon Plink (`ricochet-shot`)
- Cat Burglar (`cat-burglar`)
- Queens (`queens`)
- Banana Getaway (`rush-hour`)
- Sunset Putt (`desert-golf`)

Also in that batch: review these already-ported large, complicated games line by line against their
iOS source (rules, tuning numbers, demo scripts, art) and fix any drift:

- Lawn Defense (`lawn-defense`): LawnDefenseGame/Art/Bosses.swift → the `lawndefense` package
- Critter Duel (`critter-duel`)
- Turbo Racer (`turbo-racer`)
- Ledge Brawl (`gun-mayhem`)
- Statue Maze (`lolo`)
- Free the Banana (`klotski`)
- Assassin (`assassin`)
- Brick Breaker (`brick-breaker`)
- (any later port over ~850 lines of Swift is added here as it lands)

## Behaviour differences

- Update check: Google Play has no public lookup endpoint like iTunes', so the real check reports
  "not listed" (shown as "You're up to date"), which is also what iOS sees today because the app
  isn't on the store. The pop-up itself is ported and can be exercised with the fake-version hook.
- Fonts: SwiftUI's rounded system design has no Android twin; the default sans is used.
- Sounds overlap (SoundPool mixes) where AVAudioPlayerNode queued them back to back.
- Safe-area: like iOS (whose feed reads zero insets), pages floor the top at 60dp and the controls
  sit 16dp from the top; on phones with a tall cutout this matches the iOS layout.

## Needs manual testing on a device

- Feel of every game's controls (touch latency, joystick/drag sensitivity) on a real phone.
- Haptics strength (emulators have no vibrator).
- Pull-to-reshuffle at the top of the feed (nested-scroll overscroll).
- Language switch and persistence across launches.
