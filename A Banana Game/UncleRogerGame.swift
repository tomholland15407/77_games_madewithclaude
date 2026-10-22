//
//  UncleRogerGame.swift
//  A Banana Game
//
//  Uncle Roger Review — the steps to cook a dish are shown scrambled; put them back in
//  the right order using the ▲▼ arrows on each row, then tap SERVE. Get it right and
//  Uncle Roger (a banana chef) gives a thumbs-up; wrong is a thumbs-down. One recipe per
//  level, more steps each level, and a shrinking clock that fails you if it runs out.
//
//  Drawn as a TV-kitchen cooking review: subway tiles over a butcher-block counter, the steps as
//  recipe cards on a cutting board, the dish chalked on a menu board, a twist kitchen timer, a
//  silver cloche to SERVE, and the banana uncle judging with a big thumbs up or down.
//

import SwiftUI

enum UncleRogerGame {
    static let definition = GameDefinition(
        id: "uncle-roger", title: "Chef's Order", emoji: "🍌",
        genre: .brain, levelCount: 7,
        manual: GameManual(
            bullets: [
                "A recipe's steps are shown scrambled.",
                "Use the ▲▼ arrows on each row to put them in the correct cooking order.",
                "Tap SERVE; a wrong order or a timeout sends you back to level 1.",
            ],
            bulletsVI: [
                "Các bước của một công thức được xáo trộn.",
                "Dùng mũi tên ▲▼ trên mỗi dòng để sắp đúng thứ tự nấu.",
                "Chạm PHỤC VỤ; sai thứ tự hoặc hết giờ sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(UncleRogerView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

private struct Recipe {
    let dish: String
    let steps: [String]        // in the CORRECT order
}

struct UncleRogerView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    // A POOL of recipes per level (index level-1); step count grows 3 → 7. Multiple
    // recipes per level let a fail→restart serve a different dish each time.
    private static let recipesByLevel: [[Recipe]] = [
        // L1 — 3 steps
        [
            Recipe(dish: "Boiled Egg", steps: [
                "Fill a pot with water", "Boil the egg for 8 minutes", "Peel it and serve"]),
            Recipe(dish: "Cereal Bowl", steps: [
                "Pour cereal into a bowl", "Add cold milk", "Grab a spoon and eat"]),
            Recipe(dish: "Buttered Toast", steps: [
                "Toast a slice of bread", "Spread butter on top", "Serve on a plate"]),
        ],
        // L2 — 4 steps
        [
            Recipe(dish: "Cheese Sandwich", steps: [
                "Take two slices of bread", "Add cheese and ham", "Close the sandwich", "Cut it in half"]),
            Recipe(dish: "Jam Toast", steps: [
                "Toast two slices of bread", "Spread butter", "Spread the jam", "Stack and serve"]),
            Recipe(dish: "Ice Cream Sundae", steps: [
                "Scoop ice cream into a glass", "Pour over chocolate sauce", "Add sprinkles", "Top with a cherry"]),
        ],
        // L3 — 5 steps
        [
            Recipe(dish: "Instant Noodles", steps: [
                "Boil water in a pot", "Add the noodles", "Stir in the seasoning",
                "Cook for three minutes", "Pour into a bowl"]),
            Recipe(dish: "Grilled Cheese", steps: [
                "Butter two slices of bread", "Add cheese between them", "Heat a pan",
                "Grill until golden", "Slice and serve"]),
            Recipe(dish: "Fruit Smoothie", steps: [
                "Peel and chop the fruit", "Drop it in the blender", "Pour in the milk",
                "Blend until smooth", "Pour into a glass"]),
        ],
        // L4 — 6 steps
        [
            Recipe(dish: "Fried Rice", steps: [
                "Cook the rice and let it cool", "Heat oil in a wok", "Fry the beaten egg",
                "Add the rice and soy sauce", "Toss everything together", "Garnish and serve"]),
            Recipe(dish: "Omelette", steps: [
                "Crack and beat the eggs", "Season with salt", "Melt butter in the pan",
                "Pour in the eggs", "Add the filling and fold", "Slide onto a plate"]),
        ],
        // L5 — 7 steps
        [
            Recipe(dish: "Pancakes", steps: [
                "Mix flour, milk and eggs", "Whisk into a smooth batter", "Heat and grease the pan",
                "Pour in the batter", "Flip when bubbles form", "Cook the other side", "Stack and add syrup"]),
            Recipe(dish: "Sushi Rolls", steps: [
                "Cook the sushi rice", "Lay nori on the mat", "Spread the rice",
                "Add fish and cucumber", "Roll it up tightly", "Slice into pieces", "Serve with soy sauce"]),
        ],
        // L6 — 7 steps
        [
            Recipe(dish: "Pizza", steps: [
                "Knead the dough", "Let the dough rise", "Roll out the base", "Spread tomato sauce",
                "Add cheese and toppings", "Bake in the oven", "Slice and serve"]),
            Recipe(dish: "Beef Stew", steps: [
                "Brown the beef chunks", "Chop the vegetables", "Add stock to the pot",
                "Toss in the veg", "Simmer for two hours", "Season to taste", "Ladle into bowls"]),
        ],
        // L7 — 7 steps
        [
            Recipe(dish: "Roast Chicken", steps: [
                "Marinate the chicken", "Preheat the oven", "Season the skin", "Place in the roasting tray",
                "Roast until golden", "Rest the meat", "Carve and serve"]),
            Recipe(dish: "Chocolate Cake", steps: [
                "Cream butter and sugar", "Beat in the eggs", "Fold in flour and cocoa",
                "Pour into the tin", "Bake until risen", "Let it cool", "Spread the frosting"]),
        ],
    ]

    private var timeLimit: Double { max(11.0, 30.0 - Double(level) * 2.5) }

    private enum Phase { case play, reveal, done }
    @State private var phase: Phase = .play
    @State private var dish = ""
    @State private var correct: [String] = []
    @State private var order: [String] = []      // current arrangement
    @State private var thumbUp = false
    @State private var revealStart = Date()
    @State private var timeLeft = 0.0
    @State private var built = false
    @State private var demoPress: String? = nil   // demo: "<row>up" / "<row>down" / "serve"

    var body: some View {
        VStack(spacing: isDemo ? 8 : 14) {
            header

            VStack(spacing: isDemo ? 6 : 8) {
                ForEach(Array(order.enumerated()), id: \.element) { idx, step in
                    stepRow(idx: idx, step: step)
                }
            }
            .padding(.horizontal, isDemo ? 12 : 16)
            .padding(.vertical, isDemo ? 12 : 18)
            .background(CuttingBoard())
            .padding(.horizontal, isDemo ? 10 : 14)

            Button { submit() } label: {
                ClocheLabel(title: L("SERVE", "PHỤC VỤ"), height: isDemo ? 58 : 76)
            }
            .buttonStyle(KitchenPressStyle(lit: demoPress == "serve"))
            .disabled(phase != .play && !isDemo)
        }
        .padding(.vertical, isDemo ? 8 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KitchenBackdrop().equatable())
        .overlay { if phase == .reveal { chefReaction } }
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : await run() }
    }

    /// The judge watching from the corner, today's dish chalked on the menu board, the kitchen timer.
    private var header: some View {
        HStack(spacing: 10) {
            Canvas { ctx, s in
                KitchenArt.judge(ctx, in: CGRect(origin: .zero, size: s), mood: .watching)
            }
            .frame(width: isDemo ? 46 : 60, height: isDemo ? 52 : 68)
            Text(dish)
                .font(.custom("ChalkboardSE-Bold", size: isDemo ? 20 : 26))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, 14).padding(.vertical, isDemo ? 6 : 9)
                .frame(maxWidth: .infinity)
                .background(Chalkboard())
            if !isDemo {
                KitchenTimer(frac: timeLimit > 0 ? timeLeft / timeLimit : 0)
                    .frame(width: 60, height: 66)
            }
        }
        .padding(.horizontal, isDemo ? 12 : 16)
    }

    private func stepRow(idx: Int, step: String) -> some View {
        HStack(spacing: 10) {
            Text("\(idx + 1)")
                .font(.custom("ChalkboardSE-Bold", size: 17))
                .foregroundStyle(Color(red: 0.78, green: 0.14, blue: 0.12))
                .frame(width: 28, height: 28)
                .background(Circle().stroke(Color(red: 0.78, green: 0.14, blue: 0.12), lineWidth: 2))
            Text(step)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.2, green: 0.16, blue: 0.13))
                .frame(maxWidth: .infinity, alignment: .leading)
                // Wrap long steps instead of scaling them — scaling made longer (usually
                // lower) rows render at a smaller font. Now every step stays the same size.
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 3) {
                arrow("chevron.up", pressed: demoPress == "\(idx)up") { move(idx, by: -1) }
                    .opacity(idx == 0 ? 0.25 : 1)
                arrow("chevron.down", pressed: demoPress == "\(idx)down") { move(idx, by: 1) }
                    .opacity(idx == order.count - 1 ? 0.25 : 1)
            }
        }
        .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, isDemo ? 5 : 8)
        .background(RecipeCard())
    }

    private func arrow(_ symbol: String, pressed: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .black))
                .frame(width: 36, height: 22)
        }
        .buttonStyle(SteelKeyStyle(lit: pressed))
    }

    /// Uncle's verdict: a big thumbs up, or a thumbs down and a "Haiyaa".
    private var chefReaction: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
            VStack(spacing: 10) {
                Canvas { ctx, s in
                    KitchenArt.judge(ctx, in: CGRect(origin: .zero, size: s), mood: thumbUp ? .approve : .haiyaa)
                }
                .frame(width: 170, height: 190)
                .overlay(alignment: thumbUp ? .topTrailing : .bottomTrailing) {
                    Image(systemName: thumbUp ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                        .font(.system(size: 54, weight: .black))
                        .foregroundStyle(Color(red: 1, green: 0.84, blue: 0.3))
                        .shadow(color: .black.opacity(0.45), radius: 0, x: 2, y: 3)
                        .offset(x: 18, y: thumbUp ? -6 : 10)
                }
                Text(thumbUp ? L("Chef approves", "Đầu bếp tán thành") : L("Oh no… wrong order", "Ôi không… sai thứ tự"))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(thumbUp ? Color(red: 0.55, green: 1, blue: 0.55) : Color(red: 1, green: 0.5, blue: 0.45))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
            }
        }
        .transition(.opacity)
    }

    // MARK: - Demo (live manual clip)
    // A Level-1 recipe dealt fully reversed. The demo fixes it with the row arrows through the
    // real `move` (▼ "Peel" twice, then ▲ "Fill"), taps SERVE → the real thumbs-up reveal, holds
    // on it, then finishes it through the real `finish()` (onWin is a no-op).
    private static let demoMoves: [(Int, Int)] = [(0, 1), (1, 1), (1, -1)]   // (row, ▲-1 / ▼+1)

    private func runDemo() async {
        let recipe = Self.recipesByLevel[0][0]   // Boiled Egg
        while !Task.isCancelled {
            dish = recipe.dish
            correct = recipe.steps
            order = recipe.steps.reversed()
            thumbUp = false
            demoPress = nil
            timeLeft = timeLimit
            phase = .play
            built = true
            try? await Task.sleep(for: .seconds(1.0))    // read the scrambled steps
            for (row, delta) in Self.demoMoves {
                guard await demoTap("\(row)\(delta < 0 ? "up" : "down")", { move(row, by: delta) }) else { return }
                try? await Task.sleep(for: .seconds(0.25))
            }
            guard await demoTap("serve", submit) else { return }
            // Hold on Uncle Roger's thumbs-up (the reveal overlay), then close it out for real.
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    /// Visibly press a control (banana/ring + shrink), then fire its real action. False if cancelled.
    private func demoTap(_ key: String, _ action: () -> Void) async -> Bool {
        withAnimation(.easeOut(duration: 0.08)) { demoPress = key }
        try? await Task.sleep(for: .seconds(0.3))
        guard !Task.isCancelled else { return false }
        action()
        withAnimation(.easeOut(duration: 0.08)) { demoPress = nil }
        try? await Task.sleep(for: .seconds(0.2))
        return !Task.isCancelled
    }

    // MARK: - Flow

    private func run() async {
        if !built { build(); built = true }
        timeLeft = timeLimit
        let start = Date()
        while !Task.isCancelled && phase != .done {
            try? await Task.sleep(for: .seconds(0.05))
            if Task.isCancelled { return }
            switch phase {
            case .play:
                timeLeft = max(0, timeLimit - Date().timeIntervalSince(start))
                if timeLeft <= 0 { reveal(win: false) }
            case .reveal:
                if Date().timeIntervalSince(revealStart) >= 0.75 { finish() }
            case .done:
                break
            }
        }
    }

    private func build() {
        let pool = Self.recipesByLevel[min(level - 1, Self.recipesByLevel.count - 1)]
        // Shuffle bag so a fail→restart serves a different recipe at this level.
        let idx = ShuffleBag.shared.next(key: "uncle-roger-\(level)", count: pool.count)
        let recipe = pool[idx]
        dish = recipe.dish
        correct = recipe.steps
        // Shuffle to a scrambled start that isn't already solved.
        var shuffled = recipe.steps.shuffled()
        while shuffled == correct { shuffled = recipe.steps.shuffled() }
        order = shuffled
    }

    private func move(_ index: Int, by delta: Int) {
        guard phase == .play else { return }
        let target = index + delta
        guard target >= 0 && target < order.count else { return }
        SoundManager.shared.tap(); Haptics.tap()
        withAnimation(.snappy) { order.swapAt(index, target) }
    }

    private func submit() {
        guard phase == .play else { return }
        reveal(win: order == correct)
    }

    private func reveal(win: Bool) {
        guard phase == .play else { return }
        thumbUp = win
        if win { Haptics.tap(); SoundManager.shared.tap() }
        else { SoundManager.shared.error(); Haptics.warning() }
        revealStart = Date()
        withAnimation(.easeIn(duration: 0.15)) { phase = .reveal }
    }

    private func finish() {
        guard phase == .reveal else { return }
        let won = thumbUp
        phase = .done
        if won { onWin() } else { onFail() }
    }
}

// MARK: - Kitchen art

private enum KitchenArt {
    enum Mood { case watching, approve, haiyaa }

    /// The banana uncle: an upright banana with a mustache, brows that tell you what he thinks.
    static func judge(_ ctx: GraphicsContext, in r: CGRect, mood: Mood) {
        let radius = min(r.width, r.height) * 0.4
        let c = CGPoint(x: r.midX, y: r.midY + r.height * 0.05)
        FruitArt.draw(.banana, in: ctx, at: c, radius: radius, angle: .degrees(-62))
        let ink = Color(red: 0.2, green: 0.12, blue: 0.05)
        let s = radius
        let fc = CGPoint(x: c.x + s * 0.02, y: c.y - s * 0.05)
        // Eyes.
        for dx in [-0.22, 0.2] as [CGFloat] {
            let e = CGPoint(x: fc.x + dx * s, y: fc.y - s * 0.12)
            ctx.fill(Path(ellipseIn: CGRect(x: e.x - s * 0.1, y: e.y - s * 0.12, width: s * 0.2, height: s * 0.24)), with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: e.x - s * 0.05, y: e.y - s * 0.06, width: s * 0.1, height: s * 0.13)), with: .color(ink))
        }
        // Brows: level while watching, raised for approval, furrowed for "haiyaa".
        var brows = Path()
        let by = fc.y - s * 0.32
        switch mood {
        case .watching:
            brows.move(to: CGPoint(x: fc.x - s * 0.33, y: by)); brows.addLine(to: CGPoint(x: fc.x - s * 0.1, y: by - s * 0.02))
            brows.move(to: CGPoint(x: fc.x + s * 0.09, y: by - s * 0.02)); brows.addLine(to: CGPoint(x: fc.x + s * 0.31, y: by))
        case .approve:
            brows.move(to: CGPoint(x: fc.x - s * 0.33, y: by + s * 0.02)); brows.addQuadCurve(to: CGPoint(x: fc.x - s * 0.1, y: by - s * 0.02), control: CGPoint(x: fc.x - s * 0.22, y: by - s * 0.1))
            brows.move(to: CGPoint(x: fc.x + s * 0.09, y: by - s * 0.02)); brows.addQuadCurve(to: CGPoint(x: fc.x + s * 0.31, y: by + s * 0.02), control: CGPoint(x: fc.x + s * 0.2, y: by - s * 0.1))
        case .haiyaa:
            brows.move(to: CGPoint(x: fc.x - s * 0.33, y: by - s * 0.06)); brows.addLine(to: CGPoint(x: fc.x - s * 0.08, y: by + s * 0.06))
            brows.move(to: CGPoint(x: fc.x + s * 0.07, y: by + s * 0.06)); brows.addLine(to: CGPoint(x: fc.x + s * 0.31, y: by - s * 0.06))
        }
        ctx.stroke(brows, with: .color(ink), style: StrokeStyle(lineWidth: max(2, s * 0.07), lineCap: .round))
        // Mustache.
        var stache = Path()
        let my = fc.y + s * 0.13
        stache.move(to: CGPoint(x: fc.x, y: my))
        stache.addQuadCurve(to: CGPoint(x: fc.x - s * 0.3, y: my + s * 0.06), control: CGPoint(x: fc.x - s * 0.16, y: my - s * 0.08))
        stache.addQuadCurve(to: CGPoint(x: fc.x, y: my + s * 0.07), control: CGPoint(x: fc.x - s * 0.14, y: my + s * 0.1))
        stache.addQuadCurve(to: CGPoint(x: fc.x + s * 0.3, y: my + s * 0.06), control: CGPoint(x: fc.x + s * 0.14, y: my + s * 0.1))
        stache.addQuadCurve(to: CGPoint(x: fc.x, y: my), control: CGPoint(x: fc.x + s * 0.16, y: my - s * 0.08))
        ctx.fill(stache, with: .color(ink))
        // Mouth under the mustache.
        var mouth = Path()
        let mY = my + s * 0.2
        switch mood {
        case .watching:
            mouth.move(to: CGPoint(x: fc.x - s * 0.09, y: mY)); mouth.addLine(to: CGPoint(x: fc.x + s * 0.09, y: mY))
            ctx.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: max(1.5, s * 0.05), lineCap: .round))
        case .approve:
            mouth.move(to: CGPoint(x: fc.x - s * 0.14, y: mY - s * 0.02))
            mouth.addQuadCurve(to: CGPoint(x: fc.x + s * 0.14, y: mY - s * 0.02), control: CGPoint(x: fc.x, y: mY + s * 0.16))
            mouth.closeSubpath()
            ctx.fill(mouth, with: .color(Color(red: 0.55, green: 0.12, blue: 0.1)))
        case .haiyaa:
            ctx.fill(Path(ellipseIn: CGRect(x: fc.x - s * 0.09, y: mY - s * 0.05, width: s * 0.18, height: s * 0.16)),
                     with: .color(Color(red: 0.55, green: 0.12, blue: 0.1)))
        }
    }

    static func hash(_ n: Double) -> CGFloat {
        let v: Double = sin(n * 12.9898) * 43758.5453
        return CGFloat(v - floor(v))
    }
}

/// White subway tiles over a butcher-block counter (static).
private struct KitchenBackdrop: View, Equatable {
    var body: some View {
        Canvas { ctx, s in
            let counterY = s.height * 0.3
            let wall = CGRect(x: 0, y: 0, width: s.width, height: counterY)
            ctx.fill(Path(wall), with: .color(Color(red: 0.93, green: 0.94, blue: 0.93)))
            var grout = Path()
            let th: CGFloat = 16, tw: CGFloat = 34
            var y: CGFloat = 0
            var row = 0
            while y < counterY {
                grout.move(to: CGPoint(x: 0, y: y)); grout.addLine(to: CGPoint(x: s.width, y: y))
                var x: CGFloat = row % 2 == 0 ? 0 : tw / 2
                while x < s.width { grout.move(to: CGPoint(x: x, y: y)); grout.addLine(to: CGPoint(x: x, y: min(counterY, y + th))); x += tw }
                y += th; row += 1
            }
            ctx.stroke(grout, with: .color(Color(red: 0.72, green: 0.74, blue: 0.74)), lineWidth: 1.2)
            ctx.fill(Path(wall), with: .linearGradient(Gradient(colors: [.clear, .black.opacity(0.12)]),
                                                       startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: counterY)))
            // Butcher-block counter: strips of wood with a front edge.
            let counter = CGRect(x: 0, y: counterY, width: s.width, height: s.height - counterY)
            ctx.fill(Path(counter), with: .linearGradient(Gradient(colors: [Color(red: 0.72, green: 0.5, blue: 0.3), Color(red: 0.52, green: 0.33, blue: 0.18)]),
                                                          startPoint: CGPoint(x: 0, y: counterY), endPoint: CGPoint(x: 0, y: s.height)))
            var strips = Path()
            var x: CGFloat = 0
            var k = 0
            while x < s.width {
                x += 18 + KitchenArt.hash(Double(k)) * 16
                strips.move(to: CGPoint(x: x, y: counterY)); strips.addLine(to: CGPoint(x: x, y: s.height))
                k += 1
            }
            ctx.stroke(strips, with: .color(Color(red: 0.38, green: 0.22, blue: 0.1).opacity(0.35)), lineWidth: 1)
            ctx.fill(Path(CGRect(x: 0, y: counterY, width: s.width, height: 5)), with: .color(Color(red: 0.86, green: 0.66, blue: 0.44)))
            ctx.fill(Path(CGRect(x: 0, y: counterY + 5, width: s.width, height: 6)),
                     with: .linearGradient(Gradient(colors: [.black.opacity(0.3), .clear]), startPoint: CGPoint(x: 0, y: counterY + 5), endPoint: CGPoint(x: 0, y: counterY + 11)))
        }
        .allowsHitTesting(false)
    }
}

/// A bamboo-coloured cutting board the recipe cards sit on.
private struct CuttingBoard: View {
    var body: some View {
        Canvas { ctx, s in
            let r = CGRect(origin: .zero, size: s).insetBy(dx: 2, dy: 2)
            let board = Path(roundedRect: r, cornerRadius: 18)
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 6))
                l.fill(board.offsetBy(dx: 0, dy: 5), with: .color(.black.opacity(0.4)))
            }
            ctx.fill(board, with: .linearGradient(Gradient(colors: [Color(red: 0.93, green: 0.78, blue: 0.52), Color(red: 0.84, green: 0.66, blue: 0.4)]),
                                                  startPoint: CGPoint(x: r.minX, y: 0), endPoint: CGPoint(x: r.maxX, y: 0)))
            var clip = ctx
            clip.clip(to: board)
            var strips = Path()
            var x = r.minX + 22
            while x < r.maxX { strips.move(to: CGPoint(x: x, y: r.minY)); strips.addLine(to: CGPoint(x: x, y: r.maxY)); x += 22 }
            clip.stroke(strips, with: .color(Color(red: 0.62, green: 0.44, blue: 0.22).opacity(0.3)), lineWidth: 1)
            ctx.stroke(board, with: .color(Color(red: 0.55, green: 0.38, blue: 0.2)), lineWidth: 2)
        }
    }
}

/// A recipe index card: cream paper, a red margin rule, faint blue lines.
private struct RecipeCard: View {
    var body: some View {
        Canvas { ctx, s in
            let r = CGRect(origin: .zero, size: s)
            let card = Path(roundedRect: r, cornerRadius: 6)
            ctx.fill(card.offsetBy(dx: 1, dy: 2), with: .color(.black.opacity(0.18)))
            ctx.fill(card, with: .color(Color(red: 1, green: 0.98, blue: 0.93)))
            var lines = Path()
            var y = r.minY + 14
            while y < r.maxY - 4 { lines.move(to: CGPoint(x: r.minX + 6, y: y)); lines.addLine(to: CGPoint(x: r.maxX - 6, y: y)); y += 14 }
            ctx.stroke(lines, with: .color(Color(red: 0.55, green: 0.7, blue: 0.9).opacity(0.3)), lineWidth: 0.8)
            ctx.fill(Path(CGRect(x: r.minX + 46, y: r.minY, width: 1.4, height: r.height)), with: .color(Color(red: 0.9, green: 0.4, blue: 0.4).opacity(0.5)))
        }
    }
}

/// The menu board the dish is chalked on.
private struct Chalkboard: View {
    var body: some View {
        Canvas { ctx, s in
            let r = CGRect(origin: .zero, size: s)
            ctx.fill(Path(roundedRect: r, cornerRadius: 8), with: .color(Color(red: 0.5, green: 0.33, blue: 0.17)))
            let slate = r.insetBy(dx: 5, dy: 5)
            ctx.fill(Path(roundedRect: slate, cornerRadius: 4),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.2, green: 0.26, blue: 0.23), Color(red: 0.14, green: 0.18, blue: 0.16)]),
                                           startPoint: CGPoint(x: 0, y: slate.minY), endPoint: CGPoint(x: 0, y: slate.maxY)))
            var smudge = Path()
            for k in 0..<5 {
                let x = slate.minX + KitchenArt.hash(Double(k) * 3.1) * slate.width
                smudge.addEllipse(in: CGRect(x: x, y: slate.minY + KitchenArt.hash(Double(k) * 5.3) * slate.height * 0.6, width: 30, height: 8))
            }
            ctx.fill(smudge, with: .color(.white.opacity(0.05)))
        }
    }
}

/// The level clock as a twist kitchen timer: the red wedge is the time that's left.
private struct KitchenTimer: View {
    let frac: Double

    var body: some View {
        Canvas { ctx, s in
            let d = min(s.width, s.height - 6)
            let c = CGPoint(x: s.width / 2, y: s.height - d / 2)
            let r = d / 2
            ctx.fill(Path(roundedRect: CGRect(x: c.x - 5, y: c.y - r - 7, width: 10, height: 9), cornerRadius: 3), with: .color(Color(white: 0.75)))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: d, height: d).offsetBy(dx: 0, dy: 2)), with: .color(.black.opacity(0.3)))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: d, height: d)), with: .color(.white))
            var wedge = Path()
            let f = max(0, min(1, frac))
            wedge.move(to: c)
            wedge.addArc(center: c, radius: r * 0.82, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * f), clockwise: false)
            wedge.closeSubpath()
            ctx.fill(wedge, with: .color(frac < 0.3 ? Color(red: 0.9, green: 0.15, blue: 0.12) : Color(red: 0.95, green: 0.35, blue: 0.25)))
            var ticks = Path()
            for k in 0..<12 {
                let a = Double(k) / 12 * 2 * .pi
                ticks.move(to: CGPoint(x: c.x + CGFloat(sin(a)) * r * 0.86, y: c.y - CGFloat(cos(a)) * r * 0.86))
                ticks.addLine(to: CGPoint(x: c.x + CGFloat(sin(a)) * r * 0.97, y: c.y - CGFloat(cos(a)) * r * 0.97))
            }
            ctx.stroke(ticks, with: .color(Color(white: 0.3)), lineWidth: 1.2)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: d, height: d)), with: .color(Color(white: 0.55)), lineWidth: 2)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.22, y: c.y - r * 0.22, width: r * 0.44, height: r * 0.44)), with: .color(Color(white: 0.85)))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * 0.22, y: c.y - r * 0.22, width: r * 0.44, height: r * 0.44)), with: .color(Color(white: 0.55)), lineWidth: 1)
        }
    }
}

/// SERVE: a silver cloche on its plate.
private struct ClocheLabel: View {
    let title: String
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            Canvas { ctx, s in
                let w = s.width, h = s.height
                let plate = CGRect(x: w * 0.04, y: h * 0.74, width: w * 0.92, height: h * 0.22)
                ctx.fill(Path(ellipseIn: plate.offsetBy(dx: 0, dy: 3)), with: .color(.black.opacity(0.3)))
                ctx.fill(Path(ellipseIn: plate), with: .linearGradient(Gradient(colors: [Color(white: 0.98), Color(white: 0.78)]),
                                                                        startPoint: CGPoint(x: 0, y: plate.minY), endPoint: CGPoint(x: 0, y: plate.maxY)))
                var dome = Path()
                dome.move(to: CGPoint(x: w * 0.14, y: h * 0.8))
                dome.addCurve(to: CGPoint(x: w * 0.86, y: h * 0.8), control1: CGPoint(x: w * 0.16, y: h * 0.06), control2: CGPoint(x: w * 0.84, y: h * 0.06))
                dome.closeSubpath()
                ctx.fill(dome, with: .linearGradient(Gradient(colors: [Color(white: 0.97), Color(white: 0.72), Color(white: 0.55)]),
                                                     startPoint: CGPoint(x: w * 0.3, y: h * 0.15), endPoint: CGPoint(x: w * 0.75, y: h * 0.8)))
                ctx.stroke(dome, with: .color(Color(white: 0.45)), lineWidth: 1.2)
                var shine = Path()
                shine.move(to: CGPoint(x: w * 0.28, y: h * 0.62)); shine.addQuadCurve(to: CGPoint(x: w * 0.42, y: h * 0.26), control: CGPoint(x: w * 0.28, y: h * 0.34))
                ctx.stroke(shine, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: w * 0.46, y: h * 0.12, width: w * 0.08, height: h * 0.12)), with: .color(Color(white: 0.65)))
                ctx.fill(Path(CGRect(x: w * 0.12, y: h * 0.78, width: w * 0.76, height: h * 0.05)), with: .color(Color(white: 0.6)))
            }
            Text(title)
                .font(.system(size: height * 0.24, weight: .black, design: .rounded))
                .tracking(2)
                .foregroundStyle(Color(red: 0.22, green: 0.22, blue: 0.26))
                .padding(.bottom, height * 0.3)
        }
        .frame(width: height * 2.6, height: height)
    }
}

/// Small brushed-steel keys for moving a card up or down.
private struct SteelKeyStyle: ButtonStyle {
    var lit: Bool
    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed || lit
        return configuration.label
            .foregroundStyle(down ? Color(red: 0.78, green: 0.14, blue: 0.12) : Color(white: 0.25))
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(LinearGradient(colors: down ? [Color(white: 0.7), Color(white: 0.85)] : [Color(white: 0.95), Color(white: 0.74)],
                                     startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(down ? Color(red: 0.78, green: 0.14, blue: 0.12) : Color(white: 0.5), lineWidth: down ? 2 : 1))
            .scaleEffect(down ? 0.9 : 1)
    }
}

/// The cloche takes a real press (and the demo's) without the default dimming.
private struct KitchenPressStyle: ButtonStyle {
    var lit: Bool
    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed || lit
        return configuration.label
            .scaleEffect(down ? 0.92 : 1)
            .overlay { if lit { Capsule().stroke(.white, lineWidth: 3).padding(.horizontal, 8).padding(.vertical, 4) } }
    }
}

