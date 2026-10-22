# HISTORY.md — GOGs design & build archive

> **Archived digest — not a live spec.** This condenses the three original planning docs
> (`GAME_PLAN.md`, `GAME_BACKLOG.md`, `GAMES_VISUAL_DESIGN.md`) into one place after their work
> shipped. The **living** docs are **CLAUDE.md** (rules/architecture) and **GAME_PATTERNS.md**
> (build patterns). The authoritative, ordered catalog is always **`GameRegistry.all` in
> `GameDefinition.swift`** — trust it over any game list written here. Full originals remain in
> git history.

---

## 1. Product vision (from GAME_PLAN.md)

**The soul:** TikTok, but every "video" is a tiny game. Open the app and you're *instantly*
playing; swipe up for a completely different game. Level 1 of everything is 5–10 seconds and
dopamine-first; keep going and it ramps. Black, minimal, a 🍌 mascot, and a ❤️ to collect
favorites. Later reframed as a brain-refresh tool ("UNROT YOUR BRAIN"). Current architecture and
rules live in CLAUDE.md; this is only the origin note.

**Roadmap — all shipped:**
- **Phase 0–4:** SwiftUI shell + black theme + banana splash → vertical paging feed + first game
  → all 10 original catalog games (incl. swipe/drag with paging lock) → favorites + filter modes
  → full binge catalog.
- **Checkpoint A — game feel:** safe-area fix, auto-start 3·2·1 countdown, fast difficulty ramp,
  harder-but-fair level 1, synthesized sound effects.
- **Checkpoint B — genres + favorites:** each game tagged; feed filter modes All / Favorites /
  Unplayed.
- **Checkpoint C — settings:** per-genre frequency (Off/Low/Normal/High), sound toggle, search by
  name, and the app rename to **GOGs**.
- **D+ :** catalog built out, then culled and refreshed. Genres collapsed to **two** (`reflex`
  absorbs old `fun`; `brain` absorbs old `memory`).

---

## 2. Backlog process & build order (from GAME_BACKLOG.md)

Games were handed off as specs and built in batches (≈5 per turn), each verified with
`BuildProject`. Global rules that still apply to any new game (see CLAUDE.md for the full set):
- No natural fail mechanism ⇒ **default fail is a per-level countdown**.
- **Randomness everywhere** — each play must vary.
- **Two genres only** — `reflex` / `brain`.
- Input `tap` = safe; `swipe/drag` ⇒ `locksFeed: true` (+ automatic skip button).

**Original 1–39 backlog: complete.** Built across Batches 1–8 (Cup Shuffle, Angry Librarian,
Dark Room, Sixseven, Dart Bananas, the Passpeek trio, Platepaste, Missing Number, Superfast
Runner, Crocoshut, Dragon vs Sheep, Homework Dodge, Shadow Fight, Line Connect, Penalty, Basket,
Air Hockey, Baseball, Badminton, Quick Draw, Dice Bet, Plane Crash, Hacker, Minesweeper,
Battleship, Millionaire, Average, Uncle Roger, Weight Balance, Spot the Difference, Pinpoint the
Country, Parking, Head Soccer, …). Cut during backlog: Pick the GOAT, Rock Paper Scissors, Chess,
Sudoku (too pointless or too ambitious).

**Post-backlog:** many more games were added outside the 1–39 spec (the arcade-classic pixel
batches, combat shooters, and the brain/strategy batch). Because specs drift, the per-game
paragraphs from the old backlog were dropped here — **`GameRegistry.all` is the source of truth**
for what currently ships.

**Later roster churn (for context):** Excitebike & Helix Jump were retired; Banana Commando was
built then replaced by **Sniper** (clean single-screen shooter); a cull removed 8 too-easy or
too-similar games (Cut the Rope, Bug Squash, Weight Balance, Tap the Banana, Catch!, Retro
Runner, Pixel Invaders, Spearman), replaced by the Batch 17 brain/strategy set (Laser Reflect,
Pipe Flow, Light Cycles, Banana Bomber, Guard Patrol, Rush Hour, Turret Defense, Artillery Duel).

---

## 3. Pixel visual-design principles (from GAMES_VISUAL_DESIGN.md)

The evergreen sprite/juice rules now live in **GAME_PATTERNS.md §G (Pixel art)**. Summary of the
approach that shipped with the pixel batches:

**`PixelSprite` draws flat opaque squares — appeal is not a renderer problem.** It comes from
three levers, in priority order:
1. **Sprite craft** — outline, a 3-step shade ramp per hue (base / `mix(black,0.4)` /
   `mix(white,0.4)`), one specular pixel, a readable silhouette, consistent top-left lighting,
   two purposeful animation frames.
2. **Environment layering** — SwiftUI gradient sky + 3 parallax bands (far/mid/near) + vignette
   + optional scanlines, layered behind the flat sprites (`PixelScene`).
3. **Juice** — squash/stretch, screen-shake, particle bursts, trails on every impact/collect/fail.

Shared toolkit lives in **`PixelFX.swift`**: `PixelSprite` `override` tint, `.pixelOutline`,
`.neonGlow`, `PixelScene`, and the juice kit (`ParticleBurst`, `.screenShake`, `.squash`).

**Anti-patterns that made early games look cheap:** no outline (sprites vanish on the black
feed); two-color sprites with no shading; flat single-fill scenery; motion with no weight; and
**every level looking identical, just faster** — hence each game gets a 7-step mood ramp
(day→night or biome shift) so climbing feels earned.
