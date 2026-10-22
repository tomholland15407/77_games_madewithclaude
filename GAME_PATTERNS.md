# GAME_PATTERNS.md — how to build a GOGs game (copy-paste patterns)

Read this instead of re-reading every existing game. It captures the exact code
patterns/APIs every game uses. Pair it with **CLAUDE.md** (the rules — 7 levels, fail→L1,
etc.); the live catalog is **`GameRegistry.all`** and archived design history is in
**docs/HISTORY.md**. If something here ever conflicts with an actual game file, the game file
wins — update this doc.

## The shape of one game
Each game is **one self-contained `.swift` file** in `A Banana Game/` (file-system
synchronized groups → it auto-joins the target, no `project.pbxproj` edit). A file has two
parts: an `enum` holding the `GameDefinition`, and the `View`.

Wire-up is a single line added to `GameRegistry.all` in `GameDefinition.swift`:
```swift
MyGame.definition,
```

## The contract
```swift
GameDefinition(
    id: "my-game",                 // stable, unique (used for favorites/progress)
    title: "My Game",              // display name
    emoji: "🍌",                   // only the banana is allowed
    genre: .reflex,                // two only: .reflex or .brain
    levelCount: 7,                 // always 7
    locksFeed: false,              // true ONLY for swipe/drag games (see below)
    manual: GameManual(            // required — 2–4 bullets + optional win clip
        bullets: ["Core rule + control.", "What wins.", "What fails you → level 1."],
        bulletsVI: ["Luật + điều khiển.", "Cách thắng.", "Cái gì khiến bạn thua → cấp 1."],
        demo: nil                  // "<id>-win" clip name (mp4 in target); nil = bullets only
    ),
    makeView: { level, onWin, onFail in
        AnyView(MyGameView(level: level, onWin: onWin, onFail: onFail))
    }
)
```
`onWin` / `onFail` are the ONLY ways a game talks back. The page owns countdown, the win
celebration + reward burst, level advancing, favorites, the fail overlay. Don't reimplement
those.

**Manual & localization.** Every game ships a `GameManual` — **2–4 short bullets** (`bullets`,
English) + their Vietnamese (`bulletsVI`), no per-level notes. `demo:` is an optional muted looping
win clip bundled as `<game.id>-win.mp4` (pass the name without extension); omit/`nil` for none.
Wrap any user-facing in-game status literal with the helper `L("English", "Tiếng Việt")` from
`Localization.swift` (e.g. `Text(L("AMMO \(n)", "ĐẠN \(n)"))`). Purely numeric status needs no
wrapping. Never localize the title (it's `game.title`) or the brand.

## Shared services & APIs (the whole surface you need)
- **Colors** — `BananaTheme.background` (black), `BananaTheme.banana` (yellow accent),
  `BananaTheme.subtle` (white 50%).
- **Sound** — `SoundManager.shared.tap()` on a good interaction; `SoundManager.shared.error()`
  on a mistake. **Do NOT** play success or the countdown — the page fires those.
- **Haptics** — `Haptics.tap()`, `Haptics.success()`, `Haptics.warning()`. Games typically
  only call `Haptics.tap()` (success is the page's job).
- **Reward burst** — page-owned; don't call it.

## The standard view skeleton
```swift
import SwiftUI

enum MyGame {
    static let definition = GameDefinition(
        id: "my-game", title: "My Game", emoji: "🍌",
        genre: .brain, levelCount: 7,
        manual: GameManual(
            bullets: ["Core rule + control.", "What wins.", "What fails you → level 1."],
            bulletsVI: ["Luật + điều khiển.", "Cách thắng.", "Cái gì khiến bạn thua → cấp 1."]
        ),
        makeView: { level, onWin, onFail in
            AnyView(MyGameView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct MyGameView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    // Difficulty is ALWAYS derived from `level` (1...7) via computed vars.
    // L1 winnable-but-meaningful; L6–7 near-impossible; ramp fast.
    private var target: Int { level + 2 }
    private var timeLimit: Double { max(2.0, 8.0 - Double(level) * 0.8) }

    private enum Phase { case play, done }   // add .peek/.reveal/etc. as needed

    @State private var phase: Phase = .play
    @State private var timeLeft = 0.0
    @State private var timerTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 20) {
            timeBar.frame(height: 6).padding(.horizontal, 48)
            // ...game content, laid out with fractions of the play area...
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)   // fill the page
        .task { await run() }            // auto-start; page's 3·2·1 gates it
        .onDisappear { timerTask?.cancel() }
    }

    // MARK: - Flow
    private func run() async {
        // build randomized state here (see "Randomness" below)
        phase = .play
        startTimer()
    }

    private func startTimer() {
        timeLeft = timeLimit
        let start = Date()
        timerTask = Task {
            while !Task.isCancelled && phase == .play {
                try? await Task.sleep(for: .seconds(0.05))
                timeLeft = max(0, timeLimit - Date().timeIntervalSince(start))
                if timeLeft <= 0 { fail() }
            }
        }
    }

    private func win() {
        guard phase != .done else { return }
        phase = .done
        timerTask?.cancel()
        Haptics.tap(); SoundManager.shared.tap()
        onWin()
    }

    private func fail() {
        guard phase != .done else { return }
        phase = .done
        timerTask?.cancel()
        SoundManager.shared.error()
        onFail()
    }
}
```

## The standard countdown time-bar
```swift
private var timeBar: some View {
    GeometryReader { geo in
        let fraction = timeLimit > 0 ? timeLeft / timeLimit : 0
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.15))
            Capsule().fill(fraction < 0.3 ? .red : BananaTheme.banana)
                .frame(width: geo.size.width * fraction)
        }
    }
}
```

## Timer pattern (important)
Drive time with wall-clock (`Date().timeIntervalSince(start)`), not by accumulating sleeps —
it stays accurate. Guard every terminal action with a `done`/`phase` check so win and fail
can't both fire.

**Prefer the timer loop *inside* the structured `.task { await run() }`** rather than a
manual `timerTask = Task { … }` cancelled in `.onDisappear`:

```swift
.task { await run() }   // SwiftUI cancels this reliably when the page removes the view

private func run() async {
    // …peek / setup…
    phase = .play
    timeLeft = timeLimit
    let start = Date()
    while !Task.isCancelled && phase == .play {
        try? await Task.sleep(for: .seconds(0.05))
        timeLeft = max(0, timeLimit - Date().timeIntervalSince(start))
        if timeLeft <= 0 { fail(); break }
    }
}
```

⚠️ **Why:** the page shows the game inside a conditional (`if !isCountingDown`) and recreates
it on every win/fail/level change. `onDisappear` on a conditionally-shown view is **not
reliably called** during that churn, so a manual `Task` timer can be **orphaned** and keep
ticking — later calling `onFail()` on the page and popping a spurious "FAILED" during the
*next* level's countdown. A structured `.task` is always cancelled on removal, so it can't
orphan. (This bit Line Connect + Passpeek Pattern.) If you must spawn a side `Task` (e.g. a
physics/animation loop), store it and cancel it in `.onDisappear` **and** guard its body with
`phase`/`Task.isCancelled`.

## Generated boards → prefetch them (`BoardCache`)
Any game that builds its level with a generate-and-verify loop (Rush Hour, Crate Push, Lolo,
Mirror Maze, Nurikabe, …) must NOT generate after the countdown. `GamePageView` calls
`GameDefinition.prefetch?(level)` (and `level + 1`) when the 3·2·1 starts, and again for the next
level on a win, so the board is ready the instant "GO" lands. Pattern (identical generator +
parameters as before — prefetching changes WHEN a board is built, never WHAT it contains):
```swift
// in the GameDefinition, right after makeView:
prefetch: { level in MyView(level: level, onWin: {}, onFail: {}).prefetchBoard() }

// in the view:
func prefetchBoard() {
    let p = params                                   // capture value-type inputs only
    BoardCache.prefetch(boardKey) { Self.makePuzzle(p) }
}
private var boardKey: String { BoardCache.key("my-id", level: level) }

private func run() async {
    let p = params
    let t0 = Date()
    let puzzle = await BoardCache.take(boardKey) { Self.makePuzzle(p) }   // prefetched, or built now
    guard !Task.isCancelled else { return }
    await BoardCache.holdBrainstorm(since: t0, minimum: 0.7)   // only holds if the wait page showed
    commit(puzzle); ready = true; …
}
```
Never touch `@Environment` inside `prefetchBoard()` (the view is constructed outside SwiftUI there).
Keep verifiers fast: BFS solvers use packed bitmask states (`UInt64`/`UInt128`) + `Set<Int>`-style
keys, not String keys or `Set<P>` churn — Rush Hour/Crate Push/Lolo were 30–130× slower with
strings, and a hard level took 10–36 s to deal.
- **Push puzzles:** make walking free. A search state is the block layout plus the whole patch of
  floor the player can reach (a bitmask flood fill), and only pushes are edges. Lolo's `pushRuns`
  does this and is ~5× faster than a per-tile BFS with the same answers.
- **Hard levels:** rejection sampling rarely finds them. Lolo instead hill-climbs a solvable seed:
  move one piece, keep it if the room stays solvable and isn't easier. Its difficulty measure is
  the fewest push runs a solution needs plus how many blocks must move.
- **Time limits:** cap the climb with a deadline. Debug builds are `-Onone`, about 30× slower on
  this code than Release.

## Randomness
Every play must vary (handoff rule). Randomize positions/values/order in `run()` with
`Int.random`, `Double.random`, `.shuffled()`, `.randomElement()`. Derive counts/speeds from
`level` but jitter the specifics.

## Fail mechanism
There must ALWAYS be a way to lose (CLAUDE.md). If the core rules can't fail, add a
**per-level countdown** (the default) — `timeLimit` shrinking with level. Wrong tap /
timeout / threshold are all valid fails; call `onFail()`.

## Layout rules
- Fill the page: `.frame(maxWidth: .infinity, maxHeight: .infinity)`. The page already
  applies safe-area insets — don't add your own top padding for the notch.
- Position with **fractions** of the play area (0...1) via `GeometryReader`, e.g.
  `.position(x: fx * geo.size.width, y: fy * geo.size.height)`. No hard-coded points for
  gameplay positions.
- Keep key UI out of the **top-center** strip (camera/Dynamic Island).

## Gesture rule (tap vs. swipe)
The feed pages with **vertical swipes**. So:
- **Tap games:** never use vertical drag/swipe gestures. `locksFeed: false` (default).
- **Swipe/drag games:** set `locksFeed: true`. The page then locks the pager while you're
  actively playing and shows a free skip button. Prefer horizontal drags; if you need
  vertical, `locksFeed` is mandatory.

## ⚠️ Gotchas learned the hard way
- **Don't index `@State` arrays in `body` before `.task` fills them.** `body` renders once
  before `.task`/`.onAppear` runs, so any `array[i]` over an empty array crashes with
  *Index out of range*. Guard it: `i < array.count ? array[i] : <default>`. (This bit both
  Passpeek games.)
- **Difficulty must actually ramp to near-impossible by L6–7**, but **L1 must be gentle**
  and instantly legible (e.g. Missing Number starts as a 3×3 grid, not 5×5).
- Only the **banana** emoji. Use clean text for states ("FAILED", etc.) — the page shows
  most of them anyway.
- **Chasing AIs + bullets spawned at the muzzle = a dead zone.** Gun Mayhem's rivals once walked to
  your x and parked there. The bullets spawned past the target, so neither side could hit the other.
  Fix: make bodies solid on the ground and hold back whoever walked in, so nobody gets shoved off a
  ledge. Sweep the hit test from the shooter's front edge. Give the AI a stand-off band, not a point.
- **Hit tests must match the drawing.** Sniper once used a box about 4× the stick figure, so shots
  beside a soldier killed him. Have the art and the hit test read the same pose and facing (one
  function), and the same stroke widths (shared constants). Test the reticle's dot against that shape.
- **A verifier must replay the real physics, with margin.** Ricochet Shot's verifier stepped coarser
  than `stepBullet` and counted grazing hits, so a third of its "solutions" failed in the game. Spare
  bullets hid it until the budget got tight. Trace with the game's own step and count only hits that
  survive a small aim error (±0.3°). Then replay the solution through the real code.

## Reference idioms (so you don't have to re-read game files)
These are the recurring patterns lifted from built games. Copy from here instead of opening
Badminton / Air Hockey / etc. — that's what keeps a build cheap.

### A. Physics / animation loop (a *side* `Task`, not the structured timer)
For games with continuous motion (Air Hockey, Head Soccer, Parking, Badminton), run a
frame loop that advances state by real `dt`. This is a **stored side `Task`** — so it needs
manual cancellation in `.onDisappear` **and** every terminal path (`win`/`fail`) must
`loopTask?.cancel()`. Guard the body with `phase`. (Pure tap/puzzle games with only a
countdown should still prefer the structured `.task` timer from earlier in this doc.)
```swift
@State private var loopTask: Task<Void, Never>?
// body: .task { await run() }  +  .onDisappear { loopTask?.cancel() }

private func run() async {
    phase = .play
    setup()                       // randomize positions/scores
    timeLeft = timeLimit
    let start = Date(); var last = start
    loopTask = Task {
        while !Task.isCancelled && phase == .play {
            try? await Task.sleep(for: .seconds(0.016))          // ~60fps
            let now = Date()
            let dt = CGFloat(min(0.05, now.timeIntervalSince(last))) // clamp big gaps
            last = now
            timeLeft = max(0, timeLimit - now.timeIntervalSince(start))
            if timeLeft <= 0 { fail(); break }
            step(dt: dt)
        }
    }
}
// win()/fail() both call loopTask?.cancel() in addition to the usual phase/sound/callback.
```

### B. Button controls (two flavors)
**Tap-step** (Badminton): each tap nudges by a fixed step.
```swift
Button { move(-1) } label: { Image(systemName: "chevron.left")
    .font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
    .frame(width: 80, height: 60)
    .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16)) }
// func move(_ d: CGFloat) { x = min(0.92, max(0.08, x + d * step)); SoundManager.shared.tap() }
```
**Press-and-hold** (Head Soccer): run continuously while the finger is down. Use a
0-distance `DragGesture` (a plain `Button` can't report press/release) and let the loop apply
`moveDir`. This stays tap-safe (finger sits on the button; it doesn't scroll the feed).
```swift
Image(systemName: icon).font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
    .frame(width: 80, height: 60)
    .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
    .gesture(DragGesture(minimumDistance: 0)
        .onChanged { _ in if phase == .play { moveDir = dir } }
        .onEnded   { _ in if moveDir == dir { moveDir = 0 } })
// in step(dt:):  x += moveDir * moveSpeed * dt
```

### C. Circle-circle bounce (puck/ball off a paddle/head)
Reflect velocity along the contact normal, push the ball clear, add a share of the mover's
velocity. Add gravity separately for ball games.
```swift
let minD = ballR + otherR
let dx = ball.x - other.x, dy = ball.y - other.y
let dist = hypot(dx, dy)
guard dist < minD && dist > 0.0001 else { return }
let nx = dx / dist, ny = dy / dist
ball = CGPoint(x: other.x + nx * minD, y: other.y + ny * minD)   // unstick
let dot = vel.dx * nx + vel.dy * ny
if dot < 0 { vel.dx -= 2 * dot * nx; vel.dy -= 2 * dot * ny }      // reflect (only if approaching)
vel.dx += nx * kick; vel.dy += ny * kick                          // outward push (anti-pinning)
// optional: += moverVel * share, and clamp total speed to a per-level cap.
```
⚠️ Corner-pinning: guard each collider with a short per-collider cooldown (`hitCD`) so it
can't re-hit every frame, and always apply the outward `kick`. (This bit Air Hockey.)

### D. First-to-N scoring (Air Hockey / Head Soccer shape)
`goalsToWin = level` (L1 first-to-1 … L7 first-to-7). On a score, bump the counter, then
check win/fail, then re-serve. Because higher levels need more goals, make the **clock grow**
with level (e.g. `8 + level*4.5`) instead of shrinking.
```swift
private var goalsToWin: Int { level }
private func scored(player: Bool) {
    if player { playerScore += 1; Haptics.tap(); SoundManager.shared.tap() }
    else      { aiScore += 1; SoundManager.shared.error() }
    if playerScore >= goalsToWin { win(); return }
    if aiScore   >= goalsToWin { fail(); return }
    serve(toward: player ? -1 : 1)
}
```

### E. Tap-to-target (Spot the Difference, Pinpoint the Country)
Get the tap location and compare to a target point with a per-level radius tolerance. Use
`onTapGesture(coordinateSpace: .local)` on a full-size `ZStack`.
```swift
.contentShape(Rectangle())
.onTapGesture(coordinateSpace: .local) { loc in
    guard phase == .play else { return }
    let tol = tolFrac * area.width                       // tolFrac shrinks with level
    let p = CGPoint(x: area.minX + target.x * area.width,
                    y: area.minY + target.y * area.height)
    if hypot(loc.x - p.x, loc.y - p.y) < tol { win() } else { fail() }
}
```

### F. Rotary steering wheel (Parking)
Turn a drag around a control into an accumulating −1…1 value via `atan2` + smallest-angle
delta (handles wrap-around). Full lock ≈ 2.2 rad of rotation.
```swift
@State private var lastWheelAngle: Double?
// on the wheel view (r = wheel radius, local coords):
.gesture(DragGesture(minimumDistance: 0)
    .onChanged { v in
        guard phase == .play else { return }
        let a = atan2(Double(v.location.y - r), Double(v.location.x - r))
        if let last = lastWheelAngle {
            steer = min(1, max(-1, steer + CGFloat(angleDelta(a, last)) / 2.2))
        }
        lastWheelAngle = a
    }
    .onEnded { _ in lastWheelAngle = nil })
// func angleDelta(_ a: Double,_ b: Double) -> Double { var d=a-b; while d>(.pi){d-=2 * .pi}; while d < -(.pi){d+=2 * .pi}; return d }
```
Car kinematics (auto-creep + reverse flips the wheel): `heading += steer*turnRate*dt*(v>=0 ?1:-1)`,
then `pos += (cos h, sin h) * v * dt`. Collide via the car's four **rotated corners** vs field
bounds and obstacle AABBs; win when all four corners are inside the spot rect.

### G. Pixel art (`PixelSprite`)
For lively, colorful games with **no image assets**, author sprites as data and draw them
through the shared `PixelSprite` view (`PixelSprite.swift`). A sprite is `rows: [String]`
(one character per pixel) + `palette: [Character: Color]`; characters missing from the
palette (e.g. `.`) are transparent. It scales to fill its frame, stays square, and closes
seams — so you just give it a `.frame(width:height:)`. (Used by Critter Pop, Sprite Match,
Pixel Invaders, Retro Runner, Bug Squash, Color the Pixel.)
```swift
private let critter = ["..oooo..", ".obbbbo.", "obbbbbbo", "obwbbwbo",
                       "obbbbbbo", "obmmmmbo", ".obbbbo.", "..o..o.."]
PixelSprite(rows: critter, palette: ["b": .green, "o": .black, "w": .white, "m": .black])
    .frame(width: size, height: size)
```
Idioms that keep the art cheap **and** detailed:
- **Recolor one shape into many** — keep the shape, swap the body color in the palette to
  get variants (Critter Pop's 5 critters, Bug Squash's beetles). A "kind" = (shape × color)
  multiplies variety from a few silhouettes (Sprite Match).
- **Shading for depth** — add a darker shade character and derive it with
  `color.mix(with: .black, by: 0.4)` (iOS 18+), rather than hand-picking a second color.
- **Frame animation** — store 2 frames and swap on a time index for life (walk cycles,
  legs): `let f2 = Int(t * 3) % 2 == 1; PixelSprite(rows: f2 ? frameB : frameA, …)`.
- **Moving tap-targets** — place sprites with `.position(x: fx*w, y: fy*h)` inside a
  `GeometryReader` and attach `.onTapGesture` per sprite; they stay tappable while a physics
  loop (idiom A) animates them. Keep everything in 0…1 fractions so it's screen-independent.
- **Convert a color-index grid to a sprite** — for picture/target thumbnails, map each cell
  index to a digit char and build the palette `["0": bg, "1": c1, …]` (Color the Pixel).

## Verify
Always finish with the `BuildProject` MCP tool; fix errors before handing back. For quick
type/API checks use `XcodeRefreshCodeIssuesInFile`.
```

## Patterns from Batch 19 (Canvas scenes, physics, verified generation)
Queens, Block Blast, Tile Trio, Fruit Merge, Flight Control and Desert Golf established these:
- **Dense scenes = one `Canvas` + manual hit-testing.** Draw the board/traffic in a single Canvas and
  resolve input yourself (`.onTapGesture { location in … }` or one `DragGesture(minimumDistance: 0)`
  over the scene). Put anything static (Flight Control's airfield) in its own `View, Equatable`
  struct and add `.equatable()` so it doesn't re-render every frame.
- **Card-style games** (their own full backdrop) wrap the scene in
  `.clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22)).padding(.horizontal, isDemo ? 0 : 8)`.
- **Disable input in demos** with `.gesture(g, including: isDemo ? .none : .all)` (`.gesture` can't
  take an optional).
- **Demos that need layout** (a finger dragging to a real board cell, a route to a runway): store the
  size with `.onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }` (attach it INSIDE any
  padding) and compute the same pure layout function in the demo loop as in `body`.
- **Heavy per-frame art**: pre-render once with `ImageRenderer` into a static `Image` cache and stamp it
  rotated each frame (Fruit Merge `FMArt`). `FruitArt.swift` is the shared vector fruit set.
- **Physics as `nonisolated` value types** (`FMWorld`, `DGPhysics`) stepped at a fixed 1/60 s with an
  accumulator in `run()` — deterministic, so demos replay identically and generators can verify
  levels with the exact in-game simulation.
- **Verify offline, then in code**: `sed`/`awk`-extract the generator or physics into a swiftc harness
  (`swiftc -O`) to check uniqueness/solvability/timing; calibrate difficulty with a simple bot
  (Fruit Merge clocks were tuned to ~100→13% bot wins across L1–7). Generators that search (Queens
  uniqueness + logic grading, Desert Golf robust hole-in-one search) use `BoardCache.prefetch`.
- **Static demo constants read by `nonisolated` helpers must be `nonisolated static let`** (the target
  defaults to MainActor isolation; otherwise you get isolation warnings that become Swift 6 errors).

## Patterns from the visual redesign (Batch 1: Peg Solitaire … Turbo Racer)
The redesign makes each game look like the real game it's named after, **without touching
gameplay**. What worked:
- **Research with real pictures, not memory.** Wikipedia's API gives game screenshots/photos
  (`action=query&prop=images` → `prop=imageinfo&iiprop=url`), App Store pages list screenshot URLs
  (`mzstatic.com/image/thumb/...`), open-source remakes ship sprites — download to the scratchpad
  and look at them with the image viewer before writing the brief. (Quick Math turned out to be
  white paper + cyan numerals, not the chalkboard guessed from memory.)
- **Presentation-only state lives beside the logic, never inside it.** Add `@State` for looks only
  (marble `tint` that travels with a peg + `captured` for the groove, `lastSolved`, `facingLeft`,
  `stoned`, `scorches`, `killed`, a `kind` on traffic cars) and set it with one clearly-commented
  line next to the real mutation (`recordHop(...)` after the jump). Diff every file against a
  pre-edit backup and check that only these lines touched logic functions.
- **Static art = `View, Equatable` + `.equatable()`**: `PegBoardWood`, `TankArena` (walls),
  `LoloRoom`, `StudioWall`/`StudioFloor`, `OutRunSky`. Dynamic pieces go in one Canvas on top.
- **Oversized layers go in an `.overlay`.** A 1.4×-wide parallax sky placed directly in a ZStack
  widened the whole stack: the road canvas was drawn 1.4× too wide and the HUD slid off-screen.
  Put it in `Color.clear.frame(w, h).overlay(alignment: .leading) { sky.frame(1.4w).offset(...) }`.
- **Keep visuals honest to collisions.** Draw walls exactly where the collision cells are; to get
  Tank Trouble's thin frame, only the reachable inner face of each *border* cell is drawn (the
  rest can never be touched). Traffic uses the exact projection the hit test uses.
- **Custom `ButtonStyle`s for press states** (`QMChoiceStyle`, `DPadArmStyle`, `CanPressStyle`) so
  a real finger press and the demo's `lit` flag render identically.
- **Text as art in a Canvas:** fit by resolving at a base size and scaling; measure per-letter
  x-ranges from prefix widths. Paint drips only hang from stem (B, D, E, N…) or round (O, G, C)
  letters — a drip under the point of V made "VÀNG" read "YÀNG".
- **60 fps scenes with many scaled sprites:** sort far → near, draw road bands as one polygon per
  run of same-colour rows (not one rect per scanline), and skip fine detail on small, far sprites
  (palm rings, frond ribs, coconuts).
- **Card look:** full-bleed themed backdrop inside
  `.clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22)).padding(.horizontal, isDemo ? 0 : 8)`;
  hide the time bar in demos; demo-only viewport crops are fine (Tank Maze shows rows 5–11).
- **Batch 2 additions:**
  - *Animated tiles over a logic grid* (2048): keep `grid` the source of truth and add a
    presentation layer of identified tiles (`SlideTile`) that replays each move — slide to the
    `collapse` destination, then pop merges and zoom in the spawn — and snaps back to `grid`
    whenever the replay disagrees. Hook it with one call after the real move.
  - *Disabled buttons dim by default* — a see-through cup gave the banana away during the
    shuffle. Hidden-information games need a custom `ButtonStyle` (no dimming) and must hide the
    secret in the drawing itself (banana drawn only while its cup is lifted).
  - *Squat demo cards:* crop the board to the rows the script uses (Breach rows 0–10, Cover Fire
    rows 1–12) and use a single-row ◄▲▼► d-pad in the demo, as in batch 7 of the demo work.
  - *Reference research:* the iTunes Search API (`itunes.apple.com/search?term=…&entity=software`)
    returns `screenshotUrls` for any App Store game — fastest way to see a mobile original.
- **Batch 3 additions:**
  - *Rolling a box about its edge* (Bloxorz): keep the 8 corners of the resting box, rotate them
    about the leading bottom edge by 0…π/2 for ~0.16 s after each move, and draw only faces whose
    rotated normal points at the camera (a convex box needs no depth sort). Map a texture onto a
    face by concatenating the affine transform built from the face's projected edges.
  - *Keep texture hashes irregular:* an integer-mod hash put Bloxorz's rust speckles in rows;
    `fract(sin(n) * 43758.5)` looks natural. Also keep long arithmetic `let`s typed — a one-line
    hash expression hit "unable to type-check this expression in reasonable time".
  - *Coastlines from a grid* (Nurikabe): per land cell, round each corner whose two neighbours are
    sea (`Path(roundedRect:cornerRadii:)`), union into one path, and stroke a slightly grown copy
    underneath as shallows.
  - *Rails outside the field:* when a table needs a frame (Air Hockey), pad the GeometryReader and
    draw the rail behind it, so the normalized physics walls stay exactly where they were.
  - *Disabled + demo:* `.disabled(phase != .play && !isDemo)` keeps a demo's final frame bright.
- **Batch 4 additions:**
  - *Smooth curves from a coarse clock* (Plane Crash): the game ticks every 0.06 s, so a Canvas
    redraw looks steppy. Make the curve and the area under it `Shape`s with
    `animatableData = progress`; the existing `withAnimation(.linear(0.06))` then glides them. And
    drop `.contentTransition(.numericText())` on a number that changes every tick — it blurs
    permanently. Use `.monospacedDigit()` plus `.transaction { $0.animation = nil }`.
  - *Presentation off `onChange`, not inside logic:* Plane Crash's dive, fireball and history pills
    all react to `onChange(of: crashed)` / `onChange(of: phase)`, so no game function gained a line.
  - *Stick figures in a dense Canvas* (Gun Mayhem): redraw `StickPose` joints yourself (outlined
    round-capped strokes, filled head) instead of one `StickFigure` view per fighter. A thicker
    torso stroke reads as a vest; add a per-game pose when the shared one doesn't fit (a chest-high
    aim so the pistol lines up with where bullets spawn). Draw name tags in a second pass and stack
    any that collide.
  - *Accessories in the StickFigure's own frame* (Quick Draw): a Canvas the same size as the figure,
    using the same mapping (`x = w/2 + (u - 0.5)·h`, `y = v·h`), places hats and bandanas on the
    joints. It then mirrors and topples with the figure, and the hat can animate off on its own.
  - *Pixel fonts without a font* (Minesweeper): 7×8 glyph bitmaps as strings, drawn by merging each
    row's runs into rects (overlap them 0.3 pt so no seams show); 7-segment digits as hexagon paths
    with dim unlit segments.
  - *Keep the signal clear:* anything that is the GO cue (Quick Draw's lanterns) must never sit
    under a banner. Put DRAW!/verdict text in open sky.
  - *Temporary fail-path demo builds:* to see a fail visual you can't reach without tapping (mine
    hit, crash, ACCESS DENIED, rival wins), snapshot the files, edit the demo script with a `// TEMP`
    marker, build, shoot, then copy the snapshots back and compare md5s.
- **Batch 5 additions:**
  - *Canvas boards with the old hit areas* (Slitherlink): when per-edge views become one Canvas,
    map taps by reproducing each view's exact hit rect and the old z-order (vertical edges were on
    top, so test them first). Input then feels identical.
  - *Decorate by chain analysis:* build dot adjacency from the drawn edges and split it into
    components. Degree-1 dots are chain ends, so each open chain gets a snake head and a tail, and
    an all-degree-2 component is a closed loop (the ouroboros). Branches get no head.
  - *Equatable snapshots for heavy art* (Spot the Difference): a picture of ~20 outlined SF Symbols
    is ~360 draws. Wrap it in an Equatable view fed a value snapshot, or the 20 Hz timer redraws it.
    Under default MainActor isolation write `items.map { Snapshot($0) }`, not
    `map(Snapshot.init)`: the unapplied init reference warns.
  - *Sticker outline for SF Symbols:* resolve the symbol, draw it 8× offset in an ink colour, then once in
    its colour; keep the aspect ratio from `resolvedImage.size`.
  - *Stage depth instead of moving physics* (Head Soccer): heads are centred on the ball's floor
    line, so boots go on the grass in front of that line. The picture reads as depth, and no
    collision changed.
  - *3/4-view stacks* (Tower of Hanoi): draw each ring as thick as the stack spacing so rings sit
    flush. Add a peg stub from the ring's hole up to its top face's back edge so the peg reads as
    passing through.
  - *Information parity:* keep vision cones the same shape (Assassin, not clipped by walls) and add
    no helper overlays (Hacker: no alphabet ring), because either changes what the player knows.
    Drawing figures larger than their hit disc (1.2×) is fine.
  - *Simulator boot race:* after `harness_off` shuts the simulator down, the first launches can fail
    with "Busy (Application failed preflight checks)". Run `simctl bootstatus <udid> -b` and
    reinstall before shooting.
- **Batch 6 additions:**
  - *Frames outside the physics field* (Brick Breaker's hazard stripes, Laser Dodge's bezel): measure
    the whole area, give the field `size − 2t`, draw the frame in the margin, and put the drag on the
    outer view. Location-based drags map `(location.x − t) / w`; translation-based drags need no change.
  - *Stamp many identical sprites with `Canvas(symbols:)`* (Dodgeball): one pre-rendered ball view per
    colour, `ctx.resolveSymbol(id:)` per bullet. Hundreds of balls cost one draw each.
  - *Snap a sprite's turns while its position glides* (Pac-Man): put `.animation(nil, value: facing)`
    between `.rotationEffect` and the `.position` + `.animation(value: cell)` pair. Otherwise a
    180° → −90° turn animates as a 270° spin.
  - *Chomp without a timer:* an animatable `Shape` (`animatableData = open`) plus
    `.animation(.linear(duration: step), value: chomp)` opens and shuts the mouth once per grid step.
  - *Chess pieces:* Apple's Unicode chess glyphs render badly (a dark bishop head with a see-through
    cross, a spindly queen). Draw the pieces as vector paths in a unit box (Solo Chess `SoloArt.piece`).
  - *`Text + Text` is deprecated in iOS 26* (a new warning). Use interpolation instead:
    `Text("LIGHTS \(Text("OUT").foregroundColor(.red))")`.
  - *Shadow tiles that read as floor* (Cat Burglar): round only the corners a tile doesn't share
    (the Nurikabe trick), fill once blurred, then faintly again with a crisp 1 pt rim. The pools look
    soft, but each tile's exact edge stays readable.
  - *Presentation state from `onChange`:* the cat's facing comes from `.onChange(of: moveDir)` and
    the Lights Out chase from `.onChange(of: phase)`, so no logic function gains a line.
  - *Tall grids in the squat card, again:* put the d-pad beside the board in the demo (`HStack`).
    Cat Burglar's cells grew ~40%.
  - *Equatable views that carry a closure* (Lights Out keypad): leave the closure out of `==`, and
    hit-test with the old tile rects so taps in the gaps still do nothing.
  - *Sort shot sequences numerically* (`ls x_*.png | sort -t_ -k2 -n`). The default glob order is
    1, 10, 11, 2…, which scrambled a motion sequence and made Pac-Man look like he faced backwards.
  - *Automated logic check:* `logic_check.py` (in the harness folder) compares the definition block,
    each named logic declaration and the `@State` list against the pre-edit backups, and prints only
    the differences. Fill its `LOGIC` table per batch.
- **Batch 7 additions:**
  - *A Canvas in a `TimelineView` must read the timeline's date* (Fruit Ninja). With `Date()` alone
    the halves and the bomb flash froze as soon as the game loop stopped; reading `tl.date` inside
    the Canvas closure is what makes each tick redraw. Use `max(tl.date, Date())` when you also need
    live time while the timeline is paused (`.animation(paused: effects.isEmpty)`), and prune the
    effects with a `.task(id: fxSerial)` so the timeline pauses again.
  - *Effects from bursts the logic already appends*: Fruit Ninja spawns halves and juice from
    `onChange(of: bursts.count)` (each burst carries the slice position and the fruit's colour), then
    clears `bursts` as the old ParticleBurstView's `onDone` did. Stack reads the perfect drop from the
    burst's particle count, and derives the sliced overhang from the two top slabs (the sliding slab
    always has the width of the slab below it).
  - *Colour as a kind key* (Fruit Ninja): `fruitColors.firstIndex(of: f.color)` picks a FruitArt kind
    without adding a field to the logic struct.
  - *1-D logic on an isometric screen* (Stack): project the logic's x onto one iso diagonal and keep
    the depth constant, so what overlaps on screen is exactly what the logic keeps.
  - *Draw the ground where the body rests* (Geometry Dash): the cube's centre sits on `floorY`, so the
    drawn ground is `floorY + hs`, spikes reach the lethal height and ship-zone thorns end on the
    ship's lethal floor line. Honest geometry also exposed a latent rule: entering a flight portal on
    the ground is an instant crash (the thorns now show it).
  - *Canvas taps with per-view hit shapes* (Reflex Grid): walk the array in reverse (later views were
    on top), test each tile's rounded rect at its pulse scale plus half the old stroke width.
  - *Pre-drawn scrolling strips* (Jetpack Banana): one Equatable strip two pattern periods wide in an
    `.overlay`, offset by `-(distance·w mod period)`; nothing redraws per frame.
  - *Keep the original's signals honest*: a yellow "!" sign means "missile incoming" in Jetpack
    Joyride, so the lab wall got a pressure gauge instead. Also make demo controls visible on light
    art (Doodle Jump's paper hid the white finger and tint; use ink and a soft tint there).
  - *Chunky pixel digits* (Flappy Banana): 2-pixel-stroke glyph bitmaps, outline = the union of
    grown pixel rects, white fill on top.
  - *Capture tears*: a simulator screenshot of a scrolling grid can mix two frames (dashed ghost
    lines). Re-capture before fixing; one bad frame in 16 is the capture, not the renderer.
  - *`logic_check.py` handles repo-root files*: list them in `AT_ROOT` (batch 7 has six).
- **Batch 8 additions:**
  - *Draw the collision band itself* (Color Switch): each ring is stroked centred on `ringRadius` with
    `lineWidth = 2 × ringThick`, exactly the band `step()` tests. The old ring was thinner and sat
    inside the band, so what you saw wasn't quite what could kill you.
  - *Perspective that keeps the look-ahead* (Color Bump): `scale(dz) = k / (k + dz)`, lanes scaled
    about the centre line, and a horizon chosen so rows enter at the same `dz` where the old flat view
    showed them (≈ 0.82) and reach the ball at `dz = 0` with scale 1. Draw far rows first.
  - *Presentation from an index the logic advances* (Color Bump): `onChange(of: nextRow)` records
    which band each judged row was rolled through (its cubes scatter). No logic line changed.
  - *Full-palette render, again* (Color Switch): rendering goes through a clamped `swatch(_:)` over
    the whole palette, never the level-sized `colorsUsed` slice (see the ColorBump crash note).
  - *Canvas boards that keep old tap views* (Bridges): draw the islands in one Canvas and lay invisible
    `Color.clear` circles (0.72 cell, `.contentShape(Circle())`) over them. A negative
    `.padding(.horizontal, -8)` on the board inside the 8 pt card inset keeps the old cell size exactly.
  - *Restyled buttons keep their rectangles* (Asteroids, Crate Push): a round cap drawn inside the old
    frame gets `.contentShape(RoundedRectangle(cornerRadius: 14))`, so the whole old rectangle still
    takes the tap.
  - *Wrap copies on a torus* (Asteroids): draw each rock again at ±w / ±h when it pokes across an edge.
    The collisions already used torus distance, so the picture now shows what can hit you.
  - *Keep manuals true to the art*: when new art replaces something a bullet names (wooden block →
    iron plate, the "SWITCH" label → a swap icon, glowing pad → green ✕), reword that bullet in both
    languages and say so in the report.
  - *`logic_check.py` fix (2026-09-30)*: the extractor stopped at a first line ending in `(`, so a
    `static let definition = GameDefinition(` block was compared by its first line only, and a
    `let x: [T] = [` list stopped at the type's `]`. It now matches the bracket that ends the first
    line. Batches 7–8 were re-run in full and batches 4–6's definitions re-checked: all identical
    except batch 8's three deliberate wording edits.
- **Batch 9 additions:**
  - *Hop arcs from `onChange`* (Q*bert): remember the old cell and a start time when the logic moves a
    piece one step, and draw it along `lerp − lift·4t(1−t)` for 0.18 s. A jump of more than one row is a
    reset, so snap. Gate the `TimelineView` with an `fxLive` flag that a `.task(id: fxSerial)` clears
    after the effect, so it pauses again once the game has stopped.
  - *A fail you can't see from state* (Q*bert's hop into the void doesn't move the player): record the
    direction in the button action (`lastTry = …` before the logic call, a presentation-only line),
    then animate from it when `phase` goes to done.
  - *Keep effect labels inside the field*: the apex sits near the top edge, so clamp a speech balloon's
    anchor so the whole balloon fits.
  - *Cliff faces inside the wall cell* (Ricochet Shot): draw a mesa's top face in the upper 70 % of the
    cell and its strata face in the bottom 30 %, so the foot of the cliff is exactly the collision edge.
  - *Size a sprite from its contact rule* (Lunar Lander): contact is `pos.y + shipR` of the field
    height, so draw the module in units of `shipR · h` with the footpad soles on `y = 1`.
  - *Read a pure logic function for presentation* (Decoy): the "!" goes over each guard where the
    logic's own `spots(g, target:)` is true once the round is lost. It's a read-only call; no logic
    changed.
  - *Equatable layers when the logic's cell type is private* (Dig Dug): pass `Set<Int>` (`r·cols + c`)
    into the static ground view instead of `Set<P>`.
  - *Removed-from-list effects* (Sniper): `onChange(of: targets.map { SNSeen(id:…) })` finds the soldier
    that was just shot; it topples in the scene Canvas, a `TimelineView` finishes the fall after the
    loop stops, and a `.task(id: downed.count)` prunes it.
  - *Capture a fail without a TEMP build when the game allows it*: an untouched lander falls and
    crashes on its own in play mode.
  - *Scratch Swift snippets*: keep them as `.swiftpart` in the scratchpad; a `.swift` file there
    triggers a flood of SourceKit diagnostics.
- **Batch 10 additions** (the last batch; the pass is complete):
  - *Swap a header for something of the same height* when the field's size matters: Guard Patrol's
    cone reach is `coneRange · min(w, h)`, so "REACH THE VAULT" became a 24 pt alarm lamp (18 pt in the
    demo), and Artillery Duel's FIRE icon and shell pips sit in frames as tall as the old words.
  - *Physics in points means no card inset*: Rock 'n' Rocket clamps and bumps cars in points, so its
    card only gets the rounded clip, at full width.
  - *Card inset without a smaller field*: take the 8 pt card inset back from the field's own padding
    (Guard Patrol / Rush Hour / Artillery Duel 8 → 0, Mirror Maze 12 → 4, Pipe Flow 10 → 2). Grid games
    whose logic is in cells (Light Cycles, Banana Bomber) can shrink a little.
  - *Effects from a logic flag flipping* (Light Cycles): `onChange(of: cycles.map(\.alive))` appends a
    derez burst where a cycle died; a `TimelineView(.animation(paused: derez.isEmpty))` animates it and
    a `.task(id: derez.count)` prunes it, so nothing ticks once the bursts are gone.
  - *A short motion tail, not a lasting trace* (Artillery Duel): `onChange(of: shell)` keeps the last
    8 positions and clears them when the shell is gone; a long arc would hand the player a free
    aiming line.
  - *Static layers from logic data*: pass derived `Set<Int>`s into the Equatable view (Banana Bomber's
    `BBArena(hard:crates:)` redraws only when a crate is blasted; Mirror Maze passes `walls`).
  - *Draw the hero inside its win box* (Guard Patrol): the thief is sized from the same
    `min(w, h) · 0.03` half-size the vault check uses, and the vault chamber is exactly that box.
  - *Cars stay views when a drag animates them* (Rush Hour): only their art changed, and
    `.contentShape(RoundedRectangle(cornerRadius: 8))` keeps the old hit shape.
  - *Force a state at the demo's reset line for a TEMP check*: steering the demo banana into a cone
    missed the alarm in the captures, while `alerted = true // TEMP` in `runDemo`'s reset showed it at
    once. Restore by md5 as usual.
  - *Declaration-level diff*: a small script that lists added / removed / changed declarations per
    file (by nesting path) makes the "read the diff" step fast. Only view and art declarations should
    show up as changed.

## Patterns from the tweaking phase (Oct 2026)
Game names in this file are the titles from before the Oct 2026 renames; CLAUDE.md → "Game titles"
maps old to new (ids and file names didn't change).
- **Naming a game (trademarks):** check a candidate three ways before using it: the trademark
  registers (web searches pull Justia/trademarkelite summaries; USPTO's own search is behind a bot
  wall), the App Store (`curl "https://itunes.apple.com/search?term=…&entity=software"`; Python's
  certificate store isn't set up here, so fetch with curl), and a general web search for a game of the
  same type (the API missed "Snake Loop" and "Paint Spill", both real puzzle games). Avoid any word
  that is the main part of a registered game mark ("Waffle", "Gaze", "Ricochet", "Flappy"); generic
  names of a game type (Peg Solitaire, Air Hockey, Brick Breaker) are fine.
- **Joysticks for dodging games: `FloatingJoystick`** (shared file; Dodgeball, Laser Dodge). Put it in
  a full-width strip under the arena, never a drag on the arena (the thumb hides the action). It
  floats (centres under the thumb anywhere in the strip), has a short throw, a small dead zone and a
  √ response (a quarter push is half speed), and drags its centre along past full push so a reversal
  is one flick. The game moves its hero by `vector × topSpeed × dt` inside `step`, and its demo sets
  `vector` (the knob shows the inverse of the response curve). Pass per-game art for the base/knob.
- **The page's skip button sits over the bottom centre of every `locksFeed` game.** A control there
  is half covered and a touch on it skips the game. The harness's `MODE=play` doesn't draw page
  chrome; check controls with `MODE=page` (the real `GamePageView`).
- **Bots that set a stick vector can't see sensitivity**: they act like a perfect thumb. Use them to
  pick the top speed and to compare with the old control (a drag ≈ a bot at finger speed), and argue
  sensitivity from throw / curve / reversal distance instead.
- **Beam-dodging bots** (Laser Dodge): sample the path finely (beams sweep past a point between
  0.1 s samples), rank unsafe spots by *when* the first hit comes (a flat "unsafe" makes the bot
  freeze), test the beam's actual segment with its end cap, and copy the game's ray quirks (rays are
  marched in ~4 pt steps, so they skip thin block corners). Each of these bugs alone made the bot
  look as if faster movement were worse.
- **Clue generators must place every clue or re-deal** (Cheer Up Monkey): a placement loop that
  silently drops a gem when the ground runs out makes a counting clue wrong. Make `attempt` return
  nil and loop over seeds; check thousands of deals offline (each clue present exactly once).
- **Fair hiding**: clues and hidden characters never sit under always-on-top art (the big monkey, the
  chest, the basket), never peek out toward the scene's edge, and props are clamped inside the scene
  in the shared layout function that both the drawing and the hit tests use.
- **Clocks for search-and-solve games with no opponent**: build a player model on real deals (look,
  spot, open, count, click times with ±40–60% jitter; expert / steady / casual speeds) and pick the
  per-level limits from its win rates. Cheer Up Monkey: casual players clear L1–3, steady ones up to
  L5, and L7 needs expert speed.
- **Swift gotchas from this round**: a parameter named like a static draw helper (`placard:`, `glyph:`)
  shadows it inside that helper ("cannot call value of non-function type"); call `CMArt.placard`.
  `nonisolated static` generators calling helpers of a (default MainActor) struct raise isolation
  warnings; leave the generator MainActor unless it really runs off-main.
- **Turn-based battles as event lists** (Critter Duel): one `turn(_:)` call resolves the whole turn
  into `[CDEvent]` (use, hit, miss, heal, faint, send), and the view plays them back one beat at a
  time; the demo and the balance bot drive the same rules value.
- **Balance bots that look ahead by copying the world** (Lawn Defense): when the rules are a plain value
  (`LDWorld`), the bot's "eyes" can be a copy of it stepped 25–40 s ahead with arrivals switched off
  (`spawned = schedule.count`, sky sun and boss moves parked). Try each candidate move in its own copy
  and keep the one that avoids a mower firing or the house falling at the lowest cost; count what a
  stall leaves alive (zombie HP) and what a plant still standing will keep earning, or the bot buys
  cheap stalls and one-shot bombs and starves. Fall back to the best move it can actually make now
  (a recharging packet is not an answer). Calibrate a "make it harder" request by running the same bot
  on the OLD levels rebuilt in the new rules (old L5 → new L1 meant matching its 97%).
- **`GraphicsContext.addFilter` applies to every later draw call.** For a world tint over all the
  sprites, a hit flash or a frost tint, add the filter and draw the sprites inside `drawLayer { }`, so
  the filter runs once on the composited layer instead of on each stroke.
- **Rest detection on polyline ground: count contacts, not the last segment's slope.** Sunset Putt
  stopped a ball only on a "gentle slope", judged by whichever segment was touched last, so a ball
  wedged in a V-crack or against a wall's foot jiggled until the 9 s cap (21–45% of stops at L2–7)
  and ignored drags. A ball is also at rest when the contact normals of one substep lean opposite
  ways (it's held from both sides). One edge (a ridge, a cup lip) gives agreeing normals, so a
  tipping ball still rolls off. Prove a physics fix by replaying identical shots through the old
  and new step: outcomes and resting spots should match except for the stuck cases.
- **Inside `drawLayer { layer in … }`, draw only into `layer`.** Touching the outer context from inside
  the closure (e.g. passing `ctx` down so a helper can draw something "unrotated") is a RenderBox
  precondition failure: SIGABRT, "current layer doesn't match drawing state". Draw that extra on the
  outer context after the closure returns. It only crashes when the layer path actually runs (Lawn
  Defense: a peeled, stunned zombie that was also hit or chilled), so stage that exact combination.
- **Staging scenes for screenshots**: a TEMP `TMP…Stage.swift` that builds a busy world (every plant,
  every zombie kind, the boss mid-windup at a given progress) from `SIMCTL_CHILD_` env vars, plus a
  TEMP line in `run()` that can freeze stepping, gets every telegraph and effect on screen without
  playing for two minutes. Kept for Lawn Defense in
  `~/Library/Caches/GOGs-redesign-backups/tweaks/2026-10-09-lawn-defense-worlds/staging/`.
- **A death or capture that "just vanishes" usually still has a linger window.** Lawn Defense keeps a
  dead zombie for 1.6 s (it topples), but an `eaten` one returned before drawing. Animate inside that
  window from the art alone: have the actor look up its victim (Lawn Defense: `eaten`, same row,
  `died == p.gulp`) and draw it inside its own call, between its back and front parts, so the layering is
  right. Pose the victim in the jaws' frame (feet = lips − axis × length outside, tilt = jaw heading −
  90°), clip to the half-plane past the lips, blend from its standing pose over ~0.1 s so it doesn't pop,
  and reuse the walk cycle (a copy with `died = nil`, faster `speedK`) for kicking legs. Check frozen
  phases from a staged `since`, then the real logic in slow motion (`advance(dt * k)`), then real speed
  from `xcrun simctl io <UDID> recordVideo` plus an AVAssetImageGenerator frame grabber (no ffmpeg here;
  the durable harness has `frames.swift`).
- **Softening a difficulty ramp ("level 2 should be the new level 5"):** interpolating the raw numbers
  between two levels doesn't interpolate difficulty (Lawn Defense's in-between waves came out easier than
  L1). Blend each level's own row with a gentle version of it (`f` from 0 to 1), sweep `f` per level
  against the target win rates, then round to clean values and re-measure. Tune and check on separate
  game seeds (rates on 300 games move ±3 points between seed sets), and compare old and new tables on the
  same seeds. Check a slower player model as well: the strong bot barely noticed the final rush, but it
  decided the slower bot's L1→L2 step. Bot overrides that touch the zombie mix reorder the quota list,
  which reshuffles the horde; validate the final numbers on the real table, not through overrides.
- **Name clashes across files:** a game's `private enum XYArt` in one file and an internal `XYArt` in
  another give "invalid redeclaration". Lawn Defense's art is `LDLawnArt` because Laser Dodge already
  has a private `LDArt`.
