//
//  BottleOrderGame.swift
//  A Banana Game
//
//  Brain — deduction. A shelf of colored bottles hides a secret left-to-right order. Tap two
//  bottles to swap them, arrange your best guess, then tap CHECK: the game tells you only HOW MANY
//  bottles are standing in their correct spot — never which ones. Read the number, cross-reference
//  your past guesses, and zero in on the hidden order before your checks (or the clock) run out.
//
//  All colors are distinct, so the feedback is a pure fixed-point count — thinkier than it looks.
//  Levels add bottles (3 up to 6) and squeeze the number of checks, so level 1 is a warm-up and
//  levels 6–7 demand near-perfect deduction. The starting shelf is always scrambled off the answer.
//

import SwiftUI

enum BottleOrderGame {
    static let definition = GameDefinition(
        id: "bottle-order",
        title: "Bottle Order",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "A secret left-to-right order of colored bottles is hidden.",
                "Tap two bottles to swap them, then tap CHECK.",
                "CHECK reports only HOW MANY are in the right spot, not which — deduce from the history.",
                "Solve it before your checks or the clock run out.",
            ],
            bulletsVI: [
                "Một thứ tự bí mật từ trái sang phải của các chai màu bị giấu.",
                "Chạm vào hai chai để đổi chỗ, rồi chạm KIỂM TRA.",
                "KIỂM TRA chỉ báo BAO NHIÊU chai đúng vị trí, không nói chai nào — hãy suy luận từ lịch sử.",
                "Giải trước khi hết lượt kiểm tra hoặc hết giờ.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(BottleOrderView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct BottleOrderView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    private var count: Int { [3, 4, 4, 5, 5, 6, 6][min(level, 7) - 1] }
    private var maxChecks: Int { [8, 8, 7, 8, 7, 7, 6][min(level, 7) - 1] }
    private var timeLimit: Double { [55, 60, 60, 70, 70, 75, 75][min(level, 7) - 1] }

    private let palette: [Color] = [
        BananaTheme.banana,
        Color(red: 0.95, green: 0.30, blue: 0.32),
        Color(red: 0.30, green: 0.62, blue: 0.98),
        Color(red: 0.36, green: 0.82, blue: 0.48),
        Color(red: 0.78, green: 0.46, blue: 0.96),
        Color(red: 0.98, green: 0.56, blue: 0.20),
    ]

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var target: [Int] = []
    @State private var working: [Int] = []
    @State private var selected: Int? = nil
    @State private var history: [(arr: [Int], correct: Int)] = []
    @State private var checksLeft = 0
    @State private var timeLeft = 0.0
    @State private var loopTask: Task<Void, Never>?
    private enum DemoTarget: Equatable { case bottle(Int), check }
    @State private var demoFinger: DemoTarget? = nil

    var body: some View {
        GeometryReader { geo in
            let n = CGFloat(max(count, 1))
            // Smaller bottles + no time bar in the demo so the whole table fits the card.
            let bottleW = min(isDemo ? 34 : 64, (geo.size.width - 56) / n - 10)
            ZStack {
                BottleWall().equatable()
                VStack(spacing: isDemo ? 6 : 12) {
                    if !isDemo { timeBar.frame(height: 5).padding(.horizontal, 60) }
                    blackboard(dot: isDemo ? 11 : 15)
                    Spacer(minLength: 0)
                    VStack(spacing: isDemo ? 8 : 16) {
                        stage(bottleW: bottleW)
                        checkButton
                    }
                    .background(alignment: .top) {
                        // The table runs from behind the mystery box down past the bell.
                        BottleTable()
                            .equatable()
                            .padding(.top, bottleW * 2.4 * 0.5)
                            .padding(.horizontal, -40)
                            .padding(.bottom, -60)
                    }
                }
                .padding(.top, isDemo ? 8 : 14)
                .padding(.bottom, isDemo ? 10 : 18)
            }
            .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        }
        .padding(.horizontal, isDemo ? 0 : 8)
        .task { isDemo ? await runDemo() : start() }
        .onDisappear { loopTask?.cancel() }
    }

    // MARK: - Demo (live manual clip)

    /// A fixed 3-bottle puzzle. CHECK once (shows "1 correct"), swap the two ends to
    /// match the secret order, CHECK again (3 correct → win). Drives real `tapSlot`/`check`.
    private func runDemo() async {
        while !Task.isCancelled {
            target = [0, 1, 2]
            working = [2, 1, 0]
            selected = nil
            history = []
            checksLeft = maxChecks
            phase = .play
            timeLeft = timeLimit
            demoFinger = nil
            try? await Task.sleep(for: .seconds(0.7))
            demoFinger = .check
            try? await Task.sleep(for: .seconds(0.25))
            check()                                   // 1 correct → logged on the blackboard
            try? await Task.sleep(for: .seconds(0.9))
            guard !Task.isCancelled else { return }
            demoFinger = .bottle(0)
            try? await Task.sleep(for: .seconds(0.25))
            tapSlot(0)                                // select the left bottle
            try? await Task.sleep(for: .seconds(0.45))
            demoFinger = .bottle(2)
            try? await Task.sleep(for: .seconds(0.25))
            tapSlot(2)                                // swap with the right → [0,1,2]
            try? await Task.sleep(for: .seconds(0.6))
            demoFinger = .check
            try? await Task.sleep(for: .seconds(0.25))
            check()                                   // 3 correct → win
            try? await Task.sleep(for: .seconds(0.4))
            demoFinger = nil
            try? await Task.sleep(for: .seconds(1.1))
        }
    }

    /// The chalkboard: checks left, then every guess as chalk dots with the count it scored.
    private func blackboard(dot: CGFloat) -> some View {
        let shown = Array(history.suffix(isDemo ? 2 : 7))
        return VStack(alignment: .leading, spacing: isDemo ? 4 : 6) {
            Text(L("CHECKS LEFT  \(checksLeft)", "CÒN \(checksLeft) LƯỢT"))
                .font(.system(size: isDemo ? 13 : 16, weight: .heavy, design: .rounded))
                .foregroundStyle(checksLeft <= 2 ? Color(red: 1, green: 0.45, blue: 0.42) : Color(red: 1, green: 0.9, blue: 0.5))
                .frame(maxWidth: .infinity)
            ForEach(Array(shown.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: dot * 0.35) {
                    ForEach(entry.arr.indices, id: \.self) { i in
                        Circle()
                            .fill(palette[entry.arr[i]].opacity(0.9))
                            .overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 1))
                            .frame(width: dot, height: dot)
                    }
                    Spacer(minLength: 8)
                    Text("\(entry.correct)")
                        .font(.system(size: dot * 1.25, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                    Text(L("correct", "đúng"))
                        .font(.system(size: dot * 0.8, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, isDemo ? 12 : 16)
        .padding(.vertical, isDemo ? 7 : 10)
        .frame(maxWidth: isDemo ? 250 : 300)
        .background(ChalkboardShape().fill(Color(red: 0.14, green: 0.2, blue: 0.17)))
        .overlay(ChalkboardShape().stroke(Color(red: 0.55, green: 0.36, blue: 0.18), lineWidth: isDemo ? 5 : 7))
        .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 3)
        .padding(.horizontal, 24)
    }

    /// The mystery box hiding the secret order, with your bottles standing in front of it.
    private func stage(bottleW: CGFloat) -> some View {
        let bottleH = bottleW * 2.4
        let rowW = CGFloat(max(working.count, 1)) * (bottleW + 10)
        return ZStack(alignment: .bottom) {
            Canvas { ctx, s in BottleArt.mysteryBox(ctx, in: CGRect(origin: .zero, size: s)) }
                .frame(width: rowW + 16, height: bottleH * 0.82)
                .offset(y: -bottleH * 0.5)
            HStack(spacing: 10) {
                ForEach(working.indices, id: \.self) { i in
                    BottleView(color: palette[working[i]], width: bottleW, selected: selected == i)
                        .overlay(alignment: .bottomTrailing) {
                            if isDemo, case .bottle(let b) = demoFinger, b == i { finger(size: bottleW * 0.7) }
                        }
                        .onTapGesture { tapSlot(i) }
                }
            }
        }
        .frame(height: bottleH * 1.45, alignment: .bottom)
    }

    private func finger(size: CGFloat) -> some View {
        Image(systemName: "hand.point.up.left.fill")
            .font(.system(size: size))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.55), radius: 3)
            .offset(x: size * 0.35, y: size * 0.25)
            .allowsHitTesting(false)
    }

    private var checkButton: some View {
        Button { check() } label: {
            HStack(spacing: 10) {
                Image(systemName: "bell.fill")
                    .font(.system(size: isDemo ? 16 : 20, weight: .bold))
                Text(L("CHECK", "KIỂM TRA"))
                    .font(.system(size: isDemo ? 18 : 22, weight: .black, design: .rounded))
            }
            .foregroundStyle(Color(red: 0.3, green: 0.18, blue: 0.02))
            .frame(maxWidth: .infinity)
            .padding(.vertical, isDemo ? 10 : 15)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.5), Color(red: 0.85, green: 0.62, blue: 0.18)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 0.5, green: 0.32, blue: 0.06), lineWidth: 2))
                    .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: demoFinger == .check ? 1 : 4)
            }
            .scaleEffect(demoFinger == .check ? 0.95 : 1)
            .overlay(alignment: .trailing) {
                if isDemo && demoFinger == .check { finger(size: 26).padding(.trailing, 30) }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 40)
        // The demo is already non-interactive; keep its bell bright on the win.
        .disabled(phase != .play && !isDemo)
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.3))
                Capsule().fill(frac < 0.3 ? .red : BananaTheme.banana)
                    .frame(width: geo.size.width * frac)
            }
        }
    }
    // MARK: - Flow
    private func start() {
        let n = count
        target = Array(0..<n).shuffled()
        var w = Array(0..<n).shuffled()
        // Never start already solved (or trivially close): reshuffle off the answer.
        while w == target || zip(w, target).filter({ $0 == $1 }).count >= n - 1 {
            w.shuffle()
        }
        working = w
        selected = nil
        history = []
        checksLeft = maxChecks
        phase = .play
        timeLeft = timeLimit
        loopTask?.cancel()
        loopTask = Task {
            let startDate = Date()
            while !Task.isCancelled && phase == .play {
                try? await Task.sleep(for: .seconds(0.05))
                timeLeft = max(0, timeLimit - Date().timeIntervalSince(startDate))
                if timeLeft <= 0 { fail(); break }
            }
        }
    }

    private func tapSlot(_ i: Int) {
        guard phase == .play, i < working.count else { return }
        if let s = selected {
            if s == i { selected = nil }
            else { working.swapAt(s, i); selected = nil; SoundManager.shared.tap(); Haptics.tap() }
        } else {
            selected = i; SoundManager.shared.tap()
        }
    }

    private func check() {
        guard phase == .play else { return }
        selected = nil
        let correct = zip(working, target).filter { $0 == $1 }.count
        history.append((arr: working, correct: correct))
        if correct == working.count { win(); return }
        checksLeft -= 1
        SoundManager.shared.tap(); Haptics.tap()
        if checksLeft <= 0 { fail() }
    }

    private func win() {
        guard phase != .done else { return }
        phase = .done; loopTask?.cancel(); onWin()
    }

    private func fail() {
        guard phase != .done else { return }
        phase = .done; loopTask?.cancel(); SoundManager.shared.error(); onFail()
    }
}

// MARK: - "Match the Bottles" art

/// A glass soda bottle: crown cap, long neck, round shoulders, a cream label and a glassy
/// highlight. Lifts and glows when selected.
private struct BottleView: View {
    let color: Color
    let width: CGFloat
    let selected: Bool

    var body: some View {
        let h = width * 2.4
        Canvas { ctx, s in BottleArt.bottle(ctx, in: CGRect(origin: .zero, size: s), color: color) }
            .frame(width: width, height: h)
            .background(alignment: .bottom) {
                Ellipse().fill(.black.opacity(0.35))
                    .frame(width: width * 1.1, height: width * 0.28)
                    .offset(y: width * 0.1 + (selected ? 14 : 0))
            }
            .offset(y: selected ? -14 : 0)
            .shadow(color: selected ? color.opacity(0.85) : .clear, radius: 10)
            .animation(.easeOut(duration: 0.15), value: selected)
            .contentShape(Rectangle())
    }
}

private enum BottleArt {
    static func bottle(_ ctx: GraphicsContext, in r: CGRect, color: Color) {
        let w = r.width, h = r.height, cx = r.midX
        let neckW = w * 0.34, bodyTop = r.minY + h * 0.42, neckTop = r.minY + h * 0.1
        var glass = Path()
        glass.move(to: CGPoint(x: cx - neckW / 2, y: neckTop))
        glass.addLine(to: CGPoint(x: cx - neckW / 2, y: r.minY + h * 0.24))
        glass.addCurve(to: CGPoint(x: r.minX + w * 0.02, y: bodyTop),
                       control1: CGPoint(x: cx - neckW / 2, y: r.minY + h * 0.32),
                       control2: CGPoint(x: r.minX + w * 0.02, y: r.minY + h * 0.33))
        glass.addLine(to: CGPoint(x: r.minX + w * 0.02, y: r.maxY - w * 0.12))
        glass.addQuadCurve(to: CGPoint(x: r.minX + w * 0.14, y: r.maxY), control: CGPoint(x: r.minX + w * 0.02, y: r.maxY))
        glass.addLine(to: CGPoint(x: r.maxX - w * 0.14, y: r.maxY))
        glass.addQuadCurve(to: CGPoint(x: r.maxX - w * 0.02, y: r.maxY - w * 0.12), control: CGPoint(x: r.maxX - w * 0.02, y: r.maxY))
        glass.addLine(to: CGPoint(x: r.maxX - w * 0.02, y: bodyTop))
        glass.addCurve(to: CGPoint(x: cx + neckW / 2, y: r.minY + h * 0.24),
                       control1: CGPoint(x: r.maxX - w * 0.02, y: r.minY + h * 0.33),
                       control2: CGPoint(x: cx + neckW / 2, y: r.minY + h * 0.32))
        glass.addLine(to: CGPoint(x: cx + neckW / 2, y: neckTop))
        glass.closeSubpath()
        ctx.fill(glass, with: .linearGradient(Gradient(stops: [.init(color: color.shade(0.35), location: 0),
                                                                .init(color: color.lit(0.2), location: 0.3),
                                                                .init(color: color, location: 0.6),
                                                                .init(color: color.shade(0.45), location: 1)]),
                                              startPoint: CGPoint(x: r.minX, y: 0), endPoint: CGPoint(x: r.maxX, y: 0)))
        // Label band.
        let label = CGRect(x: r.minX + w * 0.02, y: r.minY + h * 0.56, width: w * 0.96, height: h * 0.22)
        var g = ctx
        g.clip(to: glass)
        g.fill(Path(label), with: .linearGradient(Gradient(colors: [Color(red: 0.85, green: 0.82, blue: 0.74), Color(red: 0.99, green: 0.97, blue: 0.9),
                                                                    Color(red: 0.8, green: 0.77, blue: 0.7)]),
                                                  startPoint: CGPoint(x: label.minX, y: 0), endPoint: CGPoint(x: label.maxX, y: 0)))
        g.fill(Path(CGRect(x: label.minX, y: label.minY, width: label.width, height: label.height * 0.14)), with: .color(color.shade(0.2)))
        g.fill(Path(CGRect(x: label.minX, y: label.maxY - label.height * 0.14, width: label.width, height: label.height * 0.14)), with: .color(color.shade(0.2)))
        let dotR = min(label.width, label.height) * 0.26
        g.fill(Path(ellipseIn: CGRect(x: label.midX - dotR, y: label.midY - dotR, width: dotR * 2, height: dotR * 2)), with: .color(color))
        // Glass highlights.
        g.fill(Path(roundedRect: CGRect(x: r.minX + w * 0.16, y: bodyTop + h * 0.02, width: w * 0.12, height: h * 0.5), cornerRadius: w * 0.06),
               with: .color(.white.opacity(0.4)))
        g.fill(Path(roundedRect: CGRect(x: cx - neckW * 0.3, y: neckTop + h * 0.02, width: neckW * 0.16, height: h * 0.16), cornerRadius: w * 0.04),
               with: .color(.white.opacity(0.45)))
        ctx.stroke(glass, with: .color(color.shade(0.6).opacity(0.8)), lineWidth: max(1, w * 0.035))
        // Lip and crown cap.
        let lip = CGRect(x: cx - neckW * 0.62, y: neckTop - h * 0.015, width: neckW * 1.24, height: h * 0.03)
        ctx.fill(Path(roundedRect: lip, cornerRadius: lip.height / 2), with: .color(color.shade(0.25)))
        let cap = CGRect(x: cx - neckW * 0.66, y: r.minY, width: neckW * 1.32, height: h * 0.075)
        var crown = Path()
        let teeth = 7
        crown.move(to: CGPoint(x: cap.minX, y: cap.maxY))
        for k in 0...teeth {
            let x = cap.minX + cap.width * CGFloat(k) / CGFloat(teeth)
            crown.addLine(to: CGPoint(x: x, y: k % 2 == 0 ? cap.maxY : cap.maxY - cap.height * 0.3))
        }
        crown.addLine(to: CGPoint(x: cap.maxX, y: cap.minY + cap.height * 0.25))
        crown.addQuadCurve(to: CGPoint(x: cap.minX, y: cap.minY + cap.height * 0.25), control: CGPoint(x: cap.midX, y: cap.minY - cap.height * 0.3))
        crown.closeSubpath()
        ctx.fill(crown, with: .linearGradient(Gradient(colors: [Color(white: 0.55), Color(white: 0.95), Color(white: 0.6)]),
                                              startPoint: CGPoint(x: cap.minX, y: 0), endPoint: CGPoint(x: cap.maxX, y: 0)))
        ctx.stroke(crown, with: .color(Color(white: 0.35)), lineWidth: 0.8)
    }

    /// A closed cardboard box with packing tape and a big "?" — the hidden answer is inside.
    static func mysteryBox(_ ctx: GraphicsContext, in r: CGRect) {
        let card = Color(red: 0.8, green: 0.6, blue: 0.36)
        let front = CGRect(x: r.minX, y: r.minY + r.height * 0.12, width: r.width, height: r.height * 0.88)
        var top = Path()
        top.move(to: CGPoint(x: front.minX, y: front.minY))
        top.addLine(to: CGPoint(x: front.minX + r.width * 0.05, y: r.minY))
        top.addLine(to: CGPoint(x: front.maxX - r.width * 0.05, y: r.minY))
        top.addLine(to: CGPoint(x: front.maxX, y: front.minY))
        top.closeSubpath()
        ctx.fill(top, with: .color(card.lit(0.15)))
        ctx.stroke(top, with: .color(card.shade(0.5)), lineWidth: 1)
        ctx.fill(Path(front), with: .linearGradient(Gradient(colors: [card, card.shade(0.18)]),
                                                    startPoint: CGPoint(x: 0, y: front.minY), endPoint: CGPoint(x: 0, y: front.maxY)))
        ctx.stroke(Path(front), with: .color(card.shade(0.5)), lineWidth: 1.2)
        // Tape down the middle, over the lid.
        let tape = CGRect(x: r.midX - r.width * 0.07, y: r.minY, width: r.width * 0.14, height: r.height * 0.4)
        ctx.fill(Path(tape), with: .color(Color(red: 0.9, green: 0.78, blue: 0.55).opacity(0.85)))
        // A big question mark on both sides of the tape.
        for fx: CGFloat in [0.27, 0.73] {
            let q = ctx.resolve(Text("?").font(.system(size: r.height * 0.48, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.36, green: 0.22, blue: 0.1)))
            ctx.draw(q, at: CGPoint(x: r.minX + r.width * fx, y: front.minY + front.height * 0.33))
        }
    }
}

/// A chalkboard with a softly rounded frame.
private struct ChalkboardShape: Shape {
    func path(in rect: CGRect) -> Path { Path(roundedRect: rect, cornerRadius: 10) }
}

/// Warm bar wall behind the table (static).
private struct BottleWall: View, Equatable {
    var body: some View {
        Canvas { ctx, s in
            ctx.fill(Path(CGRect(origin: .zero, size: s)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.3, green: 0.16, blue: 0.14), Color(red: 0.16, green: 0.08, blue: 0.07)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height)))
            var x: CGFloat = 0
            var k = 0
            while x < s.width {
                if k % 2 == 0 { ctx.fill(Path(CGRect(x: x, y: 0, width: 22, height: s.height)), with: .color(.white.opacity(0.03))) }
                x += 22; k += 1
            }
            ctx.fill(Path(CGRect(origin: .zero, size: s)),
                     with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.8, blue: 0.5).opacity(0.22), .clear]),
                                           center: CGPoint(x: s.width / 2, y: s.height * 0.45), startRadius: 0, endRadius: s.width * 0.8))
            // A bar pendant lamp: cord, metal shade, bulb and a warm cone of light onto the table.
            let lamp = CGPoint(x: s.width / 2, y: s.height * 0.36)
            let sw = min(s.width * 0.3, 110)
            var cone = Path()
            cone.move(to: CGPoint(x: lamp.x - sw * 0.42, y: lamp.y + sw * 0.18))
            cone.addLine(to: CGPoint(x: lamp.x + sw * 0.42, y: lamp.y + sw * 0.18))
            cone.addLine(to: CGPoint(x: lamp.x + sw * 1.6, y: s.height))
            cone.addLine(to: CGPoint(x: lamp.x - sw * 1.6, y: s.height))
            cone.closeSubpath()
            ctx.fill(cone, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.85, blue: 0.55).opacity(0.3), Color(red: 1, green: 0.85, blue: 0.55).opacity(0)]),
                                                 startPoint: lamp, endPoint: CGPoint(x: lamp.x, y: s.height * 0.95)))
            ctx.stroke(Path { p in p.move(to: CGPoint(x: lamp.x, y: 0)); p.addLine(to: CGPoint(x: lamp.x, y: lamp.y - sw * 0.2)) },
                       with: .color(.black.opacity(0.6)), lineWidth: 2)
            var shade = Path()
            shade.move(to: CGPoint(x: lamp.x - sw * 0.12, y: lamp.y - sw * 0.22))
            shade.addLine(to: CGPoint(x: lamp.x + sw * 0.12, y: lamp.y - sw * 0.22))
            shade.addQuadCurve(to: CGPoint(x: lamp.x + sw * 0.46, y: lamp.y + sw * 0.18), control: CGPoint(x: lamp.x + sw * 0.4, y: lamp.y - sw * 0.1))
            shade.addLine(to: CGPoint(x: lamp.x - sw * 0.46, y: lamp.y + sw * 0.18))
            shade.addQuadCurve(to: CGPoint(x: lamp.x - sw * 0.12, y: lamp.y - sw * 0.22), control: CGPoint(x: lamp.x - sw * 0.4, y: lamp.y - sw * 0.1))
            shade.closeSubpath()
            ctx.fill(Path(ellipseIn: CGRect(x: lamp.x - sw * 0.16, y: lamp.y + sw * 0.08, width: sw * 0.32, height: sw * 0.24)),
                     with: .radialGradient(Gradient(colors: [.white, Color(red: 1, green: 0.85, blue: 0.5), Color(red: 1, green: 0.7, blue: 0.3).opacity(0)]),
                                           center: CGPoint(x: lamp.x, y: lamp.y + sw * 0.2), startRadius: 0, endRadius: sw * 0.22))
            ctx.fill(shade, with: .linearGradient(Gradient(colors: [Color(red: 0.2, green: 0.32, blue: 0.26), Color(red: 0.36, green: 0.52, blue: 0.42),
                                                                    Color(red: 0.16, green: 0.26, blue: 0.2)]),
                                                  startPoint: CGPoint(x: lamp.x - sw * 0.46, y: 0), endPoint: CGPoint(x: lamp.x + sw * 0.46, y: 0)))
            ctx.stroke(shade, with: .color(.black.opacity(0.5)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// The wooden tabletop the bottles stand on (static).
private struct BottleTable: View, Equatable {
    var body: some View {
        Canvas { ctx, s in
            let wood = Color(red: 0.55, green: 0.34, blue: 0.18)
            ctx.fill(Path(CGRect(origin: .zero, size: s)),
                     with: .linearGradient(Gradient(colors: [wood.lit(0.12), wood, wood.shade(0.3)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height)))
            ctx.fill(Path(CGRect(x: 0, y: 0, width: s.width, height: 3)), with: .color(wood.lit(0.35)))
            var y: CGFloat = 14
            while y < s.height {
                var grain = Path()
                grain.move(to: CGPoint(x: 0, y: y))
                grain.addCurve(to: CGPoint(x: s.width, y: y + 3), control1: CGPoint(x: s.width * 0.3, y: y - 4),
                               control2: CGPoint(x: s.width * 0.7, y: y + 6))
                ctx.stroke(grain, with: .color(.black.opacity(0.08)), lineWidth: 1)
                y += 18
            }
        }
        .allowsHitTesting(false)
    }
}
