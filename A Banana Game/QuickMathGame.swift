//
//  QuickMathGame.swift
//  A Banana Game
//
//  Game #3 — brain. Solve the equation by tapping the right answer before the
//  timer runs out. Chain enough correct answers to win the level. A wrong tap
//  or running out of time fails you back to level 1. 7 levels: numbers grow,
//  operations get nastier (+, then −, then ×), and the clock shrinks.
//

import SwiftUI

enum QuickMathGame {
    static let definition = GameDefinition(
        id: "quick-math",
        title: "Quick Math",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Tap the correct answer to each equation before its clock expires.",
                "Chain enough right answers in a row to clear the level.",
                "One wrong tap or one timeout drops you to level 1.",
            ],
            bulletsVI: [
                "Chạm vào đáp án đúng cho mỗi phép tính trước khi hết giờ.",
                "Trả lời đúng liên tiếp đủ số lần để qua cấp.",
                "Một lần chạm sai hoặc hết giờ sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(QuickMathView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

private struct MathProblem {
    let text: String
    let answer: Int
    let choices: [Int]
}

struct QuickMathView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    private var target: Int { 2 + level }                          // L1=3 ... L7=9
    private var timePerQ: Double { max(1.6, 5.0 - Double(level) * 0.45) }

    @State private var problem = MathProblem(text: "", answer: 0, choices: [0, 0, 0, 0])
    @State private var score = 0
    @State private var timeLeft = 0.0
    @State private var done = false
    @State private var timerTask: Task<Void, Never>?
    @State private var demoTask: Task<Void, Never>?
    @State private var demoFlash: Int? = nil    // index of the auto-picked answer
    @State private var lastSolved: MathProblem? = nil   // presentation: the line above, ticked

    // Quick Math's look: white paper, thin sky-cyan numerals, a light-blue answer strip.
    private static let paperTop = Color(red: 0.98, green: 0.985, blue: 0.99)
    private static let paperBottom = Color(red: 0.92, green: 0.935, blue: 0.95)
    private static let cyan = Color(red: 0.19, green: 0.71, blue: 0.93)
    private static let cyanDeep = Color(red: 0.12, green: 0.55, blue: 0.86)
    private static let wash = Color(red: 0.87, green: 0.95, blue: 0.99)
    private static let edge = Color(red: 0.62, green: 0.85, blue: 0.96)
    private static let pencil = Color(red: 0.66, green: 0.69, blue: 0.73)
    private static let tick = Color(red: 0.2, green: 0.76, blue: 0.42)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Self.paperTop, Self.paperBottom], startPoint: .top, endPoint: .bottom)
            VStack(spacing: isDemo ? 8 : 18) {
                progressRow
                // The demo hides the clock so the equations and answers fit the card.
                if !isDemo {
                    timeBar
                        .frame(height: 6)
                        .padding(.horizontal, 30)
                }
                Spacer(minLength: 0)
                equationStack
                Spacer(minLength: 0)
                Grid(horizontalSpacing: isDemo ? 10 : 14, verticalSpacing: isDemo ? 10 : 14) {
                    GridRow { choiceButton(at: 0); choiceButton(at: 1) }
                    GridRow { choiceButton(at: 2); choiceButton(at: 3) }
                }
            }
            .padding(.horizontal, isDemo ? 16 : 22)
            .padding(.top, isDemo ? 12 : 20)
            .padding(.bottom, isDemo ? 12 : 22)
        }
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if isDemo { demoTask = Task { await runDemo() } } else { newProblem() }
        }
        .onDisappear { timerTask?.cancel(); demoTask?.cancel() }
    }

    /// One circle per answer needed; answered ones fill cyan with a tick.
    private var progressRow: some View {
        let d: CGFloat = isDemo ? 17 : 22
        return HStack(spacing: isDemo ? 5 : 7) {
            ForEach(0..<target, id: \.self) { i in
                ZStack {
                    if i < score {
                        Circle().fill(LinearGradient(colors: [Self.cyan, Self.cyanDeep], startPoint: .top, endPoint: .bottom))
                        Image(systemName: "checkmark")
                            .font(.system(size: d * 0.5, weight: .heavy))
                            .foregroundStyle(.white)
                    } else {
                        Circle().stroke(Color(white: 0.8), lineWidth: 2)
                    }
                }
                .frame(width: d, height: d)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: score)
    }

    private struct Row: Identifiable {
        let id: Int
        let problem: MathProblem
        let solved: Bool
    }

    /// The last solved equation (grey, ticked) above the live one — the stack scrolls up on a right answer.
    private var rows: [Row] {
        var out: [Row] = []
        if let prev = lastSolved { out.append(Row(id: score - 1, problem: prev, solved: true)) }
        if score < target && !problem.text.isEmpty { out.append(Row(id: score, problem: problem, solved: false)) }
        return out
    }

    private var equationStack: some View {
        VStack(spacing: isDemo ? 8 : 16) {
            ForEach(rows) { row in
                line(row.problem, solved: row.solved)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .opacity))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: score)
    }

    private static func pretty(_ text: String) -> String { text.replacingOccurrences(of: "-", with: "−") }

    /// One equation line. The live line sits in a white strip with an empty answer box; once solved
    /// the same line shrinks to grey pencil, shows its answer and a tick, and scrolls up.
    private func line(_ p: MathProblem, solved: Bool) -> some View {
        let size: CGFloat = solved ? (isDemo ? 24 : 32) : (isDemo ? 40 : 56)
        let shown: Int? = solved ? p.answer : demoFlash.flatMap { $0 < p.choices.count ? p.choices[$0] : nil }
        return HStack(spacing: size * 0.22) {
            Text("\(Self.pretty(p.text)) =")
                .font(.system(size: size, weight: .light))
                .foregroundStyle(solved ? Self.pencil : Self.cyan)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text(shown.map { "\($0)" } ?? " ")
                .font(.system(size: size * 0.78, weight: .regular))
                .foregroundStyle(solved ? Self.pencil : Self.cyanDeep)
                .frame(width: size * 1.12, height: size * 1.12)
                .background(solved ? Color(white: 0.9) : Self.wash, in: RoundedRectangle(cornerRadius: solved ? 4 : 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Self.edge.opacity(solved ? 0 : 0.7), lineWidth: 1))
            if solved {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: size * 0.72, weight: .bold))
                    .foregroundStyle(Self.tick)
            }
        }
        .padding(.horizontal, solved ? 0 : (isDemo ? 12 : 18))
        .padding(.vertical, solved ? 0 : (isDemo ? 10 : 16))
        .frame(maxWidth: .infinity)
        .background(solved ? Color.clear : Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Self.edge.opacity(solved ? 0 : 1), lineWidth: 2))
    }

    private func choiceButton(at index: Int) -> some View {
        let value = index < problem.choices.count ? problem.choices[index] : 0
        let picked = demoFlash == index
        return Button { choose(value) } label: {
            Text("\(value)")
                .font(.system(size: isDemo ? 28 : 34, weight: .regular))
                .frame(maxWidth: .infinity)
                .frame(height: isDemo ? 52 : 76)
        }
        .buttonStyle(QMChoiceStyle(lit: picked, cyan: Self.cyan, deep: Self.cyanDeep, edge: Self.edge))
        .overlay {
            if picked && isDemo {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 3)
                    .offset(x: 36, y: 24)
                    .allowsHitTesting(false)
            }
        }
        .disabled(done)
    }

    // MARK: - Demo (live manual clip)

    /// Auto-answer each equation correctly up to the win: the finger presses the right tile, the
    /// answer drops into the box, and the solved line scrolls up with a tick.
    private func runDemo() async {
        while !Task.isCancelled {
            done = false
            score = 0
            lastSolved = nil
            demoFlash = nil
            problem = Self.makeProblem(level: level)
            timeLeft = timePerQ                     // full bar (no live countdown in demo)
            while score < target {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(0.85))
                guard !Task.isCancelled else { return }
                if let idx = problem.choices.firstIndex(of: problem.answer) {
                    withAnimation(.easeOut(duration: 0.15)) { demoFlash = idx }
                }
                try? await Task.sleep(for: .seconds(0.55))
                lastSolved = problem
                demoFlash = nil
                score += 1                           // reaches target on the last round
                if score < target { problem = Self.makeProblem(level: level) }
            }
            try? await Task.sleep(for: .seconds(1.3))   // hold on the cleared score
        }
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let fraction = timePerQ > 0 ? timeLeft / timePerQ : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color(white: 0.86))
                Capsule()
                    .fill(fraction < 0.3 ? Color.red : Self.cyan)
                    .frame(width: geo.size.width * fraction)
            }
        }
    }

    // MARK: - Flow

    private func newProblem() {
        guard !done else { return }
        problem = Self.makeProblem(level: level)
        startTimer()
    }

    private func startTimer() {
        timerTask?.cancel()
        timeLeft = timePerQ
        let start = Date()
        timerTask = Task {
            while !Task.isCancelled && !done {
                try? await Task.sleep(for: .seconds(0.05))
                timeLeft = max(0, timePerQ - Date().timeIntervalSince(start))
                if timeLeft <= 0 && !done {
                    done = true
                    SoundManager.shared.error()
                    onFail()
                }
            }
        }
    }

    private func choose(_ n: Int) {
        guard !done else { return }
        if n == problem.answer {
            Haptics.tap()
            SoundManager.shared.tap()
            lastSolved = problem
            score += 1
            if score >= target {
                done = true
                timerTask?.cancel()
                onWin()
            } else {
                newProblem()
            }
        } else {
            done = true
            timerTask?.cancel()
            SoundManager.shared.error()
            onFail()
        }
    }

    private static func makeProblem(level: Int) -> MathProblem {
        let maxVal = 5 + level * 3
        let ops: [Character]
        switch level {
        case 1...2: ops = ["+"]
        case 3...4: ops = ["+", "-"]
        default:    ops = ["+", "-", "×"]
        }

        let op = ops.randomElement()!
        var a = Int.random(in: 1...maxVal)
        var b = Int.random(in: 1...maxVal)
        let answer: Int
        switch op {
        case "+":
            answer = a + b
        case "-":
            if b > a { swap(&a, &b) }   // no negative answers
            answer = a - b
        default:  // ×
            a = Int.random(in: 2...(3 + level))
            b = Int.random(in: 2...(3 + level))
            answer = a * b
        }

        // Three plausible wrong answers near the correct one.
        var choices: Set<Int> = [answer]
        while choices.count < 4 {
            let cand = answer + Int.random(in: -6...6)
            if cand >= 0 && cand != answer { choices.insert(cand) }
        }
        return MathProblem(text: "\(a) \(op) \(b)",
                           answer: answer,
                           choices: Array(choices).shuffled())
    }
}

/// Quick Math answer tile: white with a cyan outline; fills cyan while pressed (or lit by the demo).
private struct QMChoiceStyle: ButtonStyle {
    let lit: Bool
    let cyan: Color
    let deep: Color
    let edge: Color

    func makeBody(configuration: Configuration) -> some View {
        let on = lit || configuration.isPressed
        configuration.label
            .foregroundStyle(on ? .white : cyan)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(on ? AnyShapeStyle(LinearGradient(colors: [cyan, deep], startPoint: .top, endPoint: .bottom))
                             : AnyShapeStyle(Color.white))
            )
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? deep : edge, lineWidth: 2))
            .shadow(color: .black.opacity(on ? 0 : 0.06), radius: 0, x: 0, y: 3)
            .scaleEffect(on ? 0.95 : 1)
            .animation(.easeOut(duration: 0.1), value: on)
    }
}
