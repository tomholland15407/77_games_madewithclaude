//
//  PlaneCrashGame.swift
//  A Banana Game
//
//  Plane Crash — a cash-out gambler. Each round you set how much to INVEST (min 5M),
//  then FLY: a multiplier climbs as the plane rises. Tap CASH OUT to bank your bet ×
//  multiplier before it randomly crashes. Or ABORT to sit the flight out — you simply
//  watch it play until it crashes, risking nothing (no artificial fly-away). Reach the
//  70M house to win. Go broke (can't cover the 5M minimum) or let the very lenient level
//  clock run out → fail. Tap-only.
//

import SwiftUI

enum PlaneCrashGame {
    static let definition = GameDefinition(
        id: "plane-crash", title: "Plane Crash", emoji: "🍌",
        genre: .reflex, levelCount: 7,
        manual: GameManual(
            bullets: [
                "A cash-out gamble. Set how much to INVEST, then FLY.",
                "A multiplier climbs as the plane rises — tap CASH OUT to bank bet × multiplier before it crashes.",
                "Or ABORT to watch a round risk-free; grow your cash to 70M to win.",
                "Go broke, or let the clock run out, and you're back to level 1.",
            ],
            bulletsVI: [
                "Trò cược rút tiền. Đặt số tiền ĐẦU TƯ, rồi BAY.",
                "Hệ số tăng khi máy bay lên — chạm RÚT để nhận cược × hệ số trước khi nó rơi.",
                "Hoặc BỎ QUA để xem một vòng không rủi ro; nâng tiền lên 70M để thắng.",
                "Cháy túi, hoặc hết giờ, sẽ đưa bạn về cấp 1.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(PlaneCrashView(level: level, onWin: onWin, onFail: onFail))
        }
    )
}

struct PlaneCrashView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    private let startCash = 7      // millions
    private let goal = 70          // the "house" you must reach
    private let minBet = 5

    // The multiplier climbs a fixed step each tick; the crash chance per tick ramps
    // hard with level so high levels crash almost immediately.
    private let growthPerTick = 1.02
    private var crashChance: Double { 0.008 + Double(level - 1) * 0.0085 }
    // Very lenient overall clock — the guaranteed fail, and it caps endless aborting.
    private var levelTime: Double { max(55.0, 90.0 - Double(level) * 4.0) }

    private enum Phase { case betting, flying, aborting, resolving, done }
    @State private var phase: Phase = .betting
    @State private var cash = 7
    @State private var bet = 5
    @State private var multiplier = 1.0
    @State private var planeProgress = 0.0   // 0…1 across the screen (visual)
    @State private var crashed = false
    @State private var message: String? = nil
    @State private var resolveTicks = 0
    @State private var timeLeft = 0.0
    @State private var started = false
    @State private var demoPress: String? = nil   // demo: the button being pressed ("allin"/"fly"/"cashout")

    // Presentation only: the dive after a crash, the fireball when it lands, and the strip of past
    // rounds along the top — all driven by onChange of the game's own state.
    @State private var falling = false
    @State private var boom = false
    @State private var history: [Double] = []

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: isDemo ? 5 : 10) {
                balanceBar
                if !isDemo { timeBar.frame(height: 4) }
                historyRow
                flightPanel
                betPanel
            }
            .padding(isDemo ? 8 : 12)
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture { cashOut() }   // tap anywhere to cash out mid-flight
        }
        .background(AviatorArt.ink)
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
        .onChange(of: crashed) { _, now in
            if now {
                withAnimation(.easeIn(duration: 0.45)) { falling = true }
                Task { try? await Task.sleep(for: .seconds(0.43)); if crashed { boom = true } }
            } else {
                falling = false; boom = false
            }
        }
        .onChange(of: phase) { old, new in
            if new == .resolving && (old == .flying || old == .aborting) {
                history.insert(multiplier, at: 0)
                if history.count > 8 { history.removeLast() }
            }
        }
        .task { isDemo ? await runDemo() : await run() }
    }

    // MARK: - Header

    /// Balance on the left; on the right, how far it is to the 70M house.
    private var balanceBar: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(L("BALANCE", "SỐ DƯ"))
                    .font(.system(size: isDemo ? 9 : 11, weight: .heavy)).tracking(1)
                    .foregroundStyle(AviatorArt.muted)
                Text("\(cash)M")
                    .font(.system(size: isDemo ? 20 : 28, weight: .black, design: .rounded))
                    .foregroundStyle(AviatorArt.green)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 6)
            HStack(spacing: 7) {
                GeometryReader { g in
                    let f = CGFloat(min(1, max(0, Double(cash) / Double(goal))))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.1))
                        Capsule().fill(LinearGradient(colors: [AviatorArt.green.opacity(0.7), AviatorArt.green],
                                                      startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(6, g.size.width * f))
                    }
                }
                .frame(width: isDemo ? 86 : 104, height: isDemo ? 7 : 9)
                Image(systemName: "house.fill")
                    .font(.system(size: isDemo ? 14 : 18, weight: .bold))
                    .foregroundStyle(cash >= goal ? AviatorArt.green : .white)
                Text("\(goal)M")
                    .font(.system(size: isDemo ? 13 : 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize()
            }
        }
    }

    /// The strip of past rounds, coloured like the crash-game history bar.
    private var historyRow: some View {
        HStack(spacing: 5) {
            ForEach(Array(history.prefix(isDemo ? 5 : 7).enumerated()), id: \.offset) { _, m in
                Text(String(format: "%.2fx", m))
                    .font(.system(size: isDemo ? 10 : 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(AviatorArt.pill(m))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
            }
            Spacer(minLength: 0)
        }
        .frame(height: isDemo ? 17 : 22)
    }

    private var timeBar: some View {
        GeometryReader { geo in
            let fraction = levelTime > 0 ? timeLeft / levelTime : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                Capsule().fill(fraction < 0.3 ? AviatorArt.red : Color.white.opacity(0.75))
                    .frame(width: geo.size.width * max(0, fraction))
            }
        }
    }

    // MARK: - Flight

    private var flightPanel: some View {
        GeometryReader { g in
            let s = g.size
            let p = planeProgress
            let tip = AviatorArt.point(p, in: s)
            let tilt = AviatorArt.tilt(p, in: s)
            let planeW: CGFloat = min(s.width * 0.24, s.height * 0.42)
            let ground = CGPoint(x: min(s.width - planeW * 0.4, tip.x + s.width * 0.1), y: s.height * 0.9)
            ZStack {
                AviatorSky().equatable()
                FlightArea(progress: p)
                    .fill(LinearGradient(colors: [AviatorArt.red.opacity(0.45), AviatorArt.red.opacity(0.12)],
                                         startPoint: .top, endPoint: .bottom))
                FlightCurve(progress: p)
                    .stroke(AviatorArt.red, style: StrokeStyle(lineWidth: isDemo ? 3 : 4, lineCap: .round, lineJoin: .round))
                readout(s)
                PlaneArt()
                    .equatable()
                    .frame(width: planeW, height: planeW * 0.5)
                    .rotationEffect(falling ? .degrees(68) : .radians(Double(tilt)))
                    .opacity(phase == .betting ? 0.35 : (boom ? 0 : 1))
                    .position(falling ? ground : CGPoint(x: tip.x + planeW * 0.36, y: tip.y - planeW * 0.12))
                if boom { CrashBlast(size: planeW).position(ground) }
            }
            .frame(width: s.width, height: s.height)
        }
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 18))
        .overlay(RoundedRectangle(cornerRadius: isDemo ? 12 : 18).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    /// The big multiplier, with the round's result above it once there is one.
    private func readout(_ s: CGSize) -> some View {
        VStack(spacing: 2) {
            if let message {
                Text(message)
                    .font(.system(size: isDemo ? 13 : 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(crashed ? AviatorArt.red : (phase == .done ? AviatorArt.green : .white))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.horizontal, 10)
            }
            Text(String(format: "%.2fx", multiplier))
                .font(.system(size: isDemo ? 38 : 58, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(crashed ? AviatorArt.red : (phase == .betting ? .white.opacity(0.35) : .white))
                .shadow(color: .black.opacity(0.5), radius: 6)
                .transaction { $0.animation = nil }
        }
        .position(x: s.width / 2, y: s.height * 0.4)
    }

    // MARK: - Bet panel

    private var betPanel: some View {
        VStack(spacing: isDemo ? 6 : 10) {
            switch phase {
            case .flying:
                Button { cashOut() } label: {
                    VStack(spacing: 0) {
                        Text(L("CASH OUT", "RÚT TIỀN"))
                            .font(.system(size: isDemo ? 16 : 21, weight: .black, design: .rounded))
                        Text("+\(Int((Double(bet) * (multiplier - 1)).rounded()))M")
                            .font(.system(size: isDemo ? 12 : 15, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .transaction { $0.animation = nil }
                    }
                }
                .buttonStyle(AviatorButtonStyle(fill: AviatorArt.orange, lit: demoPress == "cashout", height: isDemo ? 50 : 68))
            case .aborting:
                Text(L("WATCHING — you sat this one out", "ĐANG XEM — bạn bỏ qua vòng này"))
                    .font(.system(size: isDemo ? 13 : 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(AviatorArt.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: isDemo ? 50 : 68)
            case .betting, .resolving, .done:
                betControls
                    .opacity(phase == .betting ? 1 : 0.4)
                    .allowsHitTesting(phase == .betting)
            }
        }
        .padding(isDemo ? 8 : 12)
        .background(RoundedRectangle(cornerRadius: isDemo ? 12 : 18).fill(AviatorArt.panel))
    }

    private var betControls: some View {
        VStack(spacing: isDemo ? 6 : 10) {
            HStack(spacing: isDemo ? 6 : 10) {
                stepButton("minus") { adjustBet(-minBet) }
                VStack(spacing: -1) {
                    Text(L("INVEST", "ĐẦU TƯ"))
                        .font(.system(size: isDemo ? 8 : 10, weight: .heavy)).tracking(1)
                        .foregroundStyle(AviatorArt.muted)
                    Text("\(bet)M")
                        .font(.system(size: isDemo ? 16 : 20, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                .frame(minWidth: isDemo ? 58 : 76)
                stepButton("plus") { adjustBet(minBet) }
                Spacer(minLength: 4)
                Button { setAllIn() } label: {
                    Text(L("ALL IN", "TẤT TAY"))
                        .font(.system(size: isDemo ? 12 : 15, weight: .black, design: .rounded))
                        .padding(.horizontal, isDemo ? 12 : 16)
                }
                .buttonStyle(AviatorButtonStyle(fill: Color.white.opacity(0.14), text: .white, lit: demoPress == "allin",
                                                height: isDemo ? 30 : 40, capsule: true))
                .fixedSize()
            }
            HStack(spacing: isDemo ? 8 : 10) {
                Button { fly() } label: {
                    VStack(spacing: 0) {
                        Text(L("FLY", "BAY")).font(.system(size: isDemo ? 17 : 22, weight: .black, design: .rounded))
                        Text("\(bet)M").font(.system(size: isDemo ? 11 : 14, weight: .heavy, design: .rounded))
                    }
                }
                .buttonStyle(AviatorButtonStyle(fill: AviatorArt.green, lit: demoPress == "fly", height: isDemo ? 44 : 60))
                Button { abort() } label: {
                    Text(L("ABORT", "BỎ QUA")).font(.system(size: isDemo ? 13 : 16, weight: .heavy, design: .rounded))
                }
                .buttonStyle(AviatorButtonStyle(fill: Color.white.opacity(0.12), text: .white, lit: false, height: isDemo ? 44 : 60))
                .frame(width: isDemo ? 88 : 116)
            }
        }
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: isDemo ? 13 : 16, weight: .black))
        }
        .buttonStyle(AviatorButtonStyle(fill: Color.white.opacity(0.14), text: .white, lit: false,
                                        height: isDemo ? 30 : 40, capsule: true))
        .frame(width: isDemo ? 30 : 40)
    }

    // MARK: - Demo (live manual clip)
    // Two real all-in rounds at the game's own tick rate and growth: 7M → cash out at 3.22×
    // (59 ticks, +16M) → 23M → cash out at 3.09× (57 ticks, +48M) → 71M ≥ the 70M house. The
    // demo presses ALL IN → FLY → CASH OUT through the real functions; only the per-tick crash
    // roll is skipped (the flights that make this clip are the ones that didn't crash).
    private func runDemo() async {
        while !Task.isCancelled {
            cash = startCash; bet = minBet; started = true
            multiplier = 1.0; planeProgress = 0; crashed = false; message = nil
            timeLeft = levelTime
            demoPress = nil
            phase = .betting
            for ticks in [59, 57] {
                try? await Task.sleep(for: .seconds(0.45))
                guard await demoTap("allin", setAllIn) else { return }
                guard await demoTap("fly", fly) else { return }
                for _ in 0..<ticks {
                    try? await Task.sleep(for: .seconds(0.06))
                    guard !Task.isCancelled else { return }
                    withAnimation(.linear(duration: 0.06)) {
                        multiplier *= growthPerTick
                        planeProgress = min(1.0, planeProgress + 0.016)
                    }
                }
                guard await demoTap("cashout", cashOut) else { return }
                try? await Task.sleep(for: .seconds(0.7))       // the real ~0.7s result read
                guard !Task.isCancelled else { return }
                nextRound()   // round 2's check → "You beat the house!" + the real win() (no-op onWin)
            }
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    /// Visibly press a control (ring + shrink), then fire its real action. False if cancelled.
    private func demoTap(_ key: String, _ action: () -> Void) async -> Bool {
        withAnimation(.easeOut(duration: 0.1)) { demoPress = key }
        try? await Task.sleep(for: .seconds(0.3))
        guard !Task.isCancelled else { return false }
        action()
        withAnimation(.easeOut(duration: 0.1)) { demoPress = nil }
        try? await Task.sleep(for: .seconds(0.2))
        return !Task.isCancelled
    }

    // MARK: - Flow

    private func run() async {
        if !started { cash = startCash; bet = minBet; started = true }
        timeLeft = levelTime
        let start = Date()
        while !Task.isCancelled && phase != .done {
            try? await Task.sleep(for: .seconds(0.06))
            if Task.isCancelled { return }
            timeLeft = max(0, levelTime - Date().timeIntervalSince(start))
            if timeLeft <= 0 { message = L("OUT OF TIME", "HẾT GIỜ"); fail(); return }

            switch phase {
            case .flying:
                withAnimation(.linear(duration: 0.06)) {
                    multiplier *= growthPerTick
                    planeProgress = min(1.0, planeProgress + 0.016)
                }
                if Double.random(in: 0..<1) < crashChance {
                    crash()
                }
            case .aborting:
                withAnimation(.linear(duration: 0.06)) {
                    multiplier *= growthPerTick
                    planeProgress = min(1.0, planeProgress + 0.016)
                }
                // An abort flight plays out risk-free like a normal flight, then always
                // ends: it crashes on its own, or once the plane completes its path across
                // the screen (so it can't linger at the top climbing forever).
                if planeProgress >= 1.0 || Double.random(in: 0..<1) < crashChance {
                    crash()
                }
            case .resolving:
                resolveTicks += 1
                if resolveTicks >= 11 { nextRound() }   // ~0.7s to read the result
            case .betting, .done:
                break
            }
        }
    }

    private func adjustBet(_ delta: Int) {
        guard phase == .betting else { return }
        bet = min(cash, max(minBet, bet + delta))
        SoundManager.shared.tap(); Haptics.tap()
    }

    private func setAllIn() {
        guard phase == .betting else { return }
        bet = max(minBet, cash)
        SoundManager.shared.tap(); Haptics.tap()
    }

    private func fly() {
        guard phase == .betting else { return }
        SoundManager.shared.tap(); Haptics.tap()
        startFlight(); phase = .flying
    }

    private func abort() {
        guard phase == .betting else { return }
        SoundManager.shared.tap()
        startFlight(); phase = .aborting
        message = nil
    }

    private func startFlight() {
        multiplier = 1.0
        planeProgress = 0
        crashed = false
        message = nil
    }

    private func cashOut() {
        guard phase == .flying else { return }
        SoundManager.shared.tap(); Haptics.tap()
        let profit = Int((Double(bet) * (multiplier - 1)).rounded())
        cash += profit
        message = L("Banked +\(profit)M", "Đã rút +\(profit)M")
        beginResolve()
    }

    private func crash() {
        crashed = true
        withAnimation(.easeIn(duration: 0.2)) { planeProgress = min(1, planeProgress) }
        if phase == .flying {
            cash -= bet
            message = L("CRASHED −\(bet)M", "RƠI −\(bet)M")
            SoundManager.shared.error(); Haptics.warning()
        } else {
            message = L(String(format: "Crashed at %.2f× — you sat out", multiplier),
                        String(format: "Rơi ở %.2f× — bạn đã bỏ qua", multiplier))
        }
        beginResolve()
    }

    private func beginResolve() {
        resolveTicks = 0
        phase = .resolving
    }

    private func nextRound() {
        crashed = false
        multiplier = 1.0
        planeProgress = 0
        if cash >= goal { message = L("You beat the house!", "Bạn đã mua được nhà!"); win(); return }
        if cash < minBet { message = L("Out of cash", "Hết tiền"); fail(); return }
        bet = min(cash, max(minBet, bet))
        message = nil
        phase = .betting
    }

    private func win() {
        guard phase != .done else { return }
        phase = .done
        Haptics.tap(); SoundManager.shared.tap()
        onWin()
    }

    private func fail() {
        guard phase != .done else { return }
        phase = .done
        SoundManager.shared.error()
        onFail()
    }
}

// MARK: - Crash-game art

private enum AviatorArt {
    static let ink = Color(red: 0.055, green: 0.055, blue: 0.07)
    static let panel = Color(red: 0.11, green: 0.11, blue: 0.125)
    static let red = Color(red: 0.9, green: 0.02, blue: 0.22)
    static let green = Color(red: 0.2, green: 0.78, blue: 0.08)
    static let orange = Color(red: 0.86, green: 0.47, blue: 0.04)
    static let muted = Color(white: 0.55)

    /// History pill colour by size: blue under 2×, purple to 10×, magenta above.
    static func pill(_ m: Double) -> Color {
        m < 2 ? Color(red: 0.2, green: 0.7, blue: 1) : (m < 10 ? Color(red: 0.57, green: 0.24, blue: 0.97) : Color(red: 0.75, green: 0.09, blue: 0.71))
    }

    /// The flight path: flat off the runway, then climbing ever more steeply.
    static func point(_ p: Double, in s: CGSize) -> CGPoint {
        let q = CGFloat(max(0, min(1, p)))
        let x: CGFloat = s.width * 0.07 + q * s.width * 0.66
        let y: CGFloat = s.height * 0.88 - pow(q, 1.7) * s.height * 0.6
        return CGPoint(x: x, y: y)
    }

    /// Nose angle (radians, negative = up) along the path, softened so the plane never stands on its tail.
    static func tilt(_ p: Double, in s: CGSize) -> CGFloat {
        let q = CGFloat(max(0.001, min(1, p)))
        let dx: CGFloat = s.width * 0.66
        let dy: CGFloat = -1.7 * pow(q, 0.7) * s.height * 0.6
        return max(-0.55, atan2(dy, dx) * 0.7)
    }
}

/// The red curve from the runway to the plane (animatable, so it glides between the game's ticks).
private struct FlightCurve: Shape {
    var progress: Double
    var animatableData: Double { get { progress } set { progress = newValue } }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard progress > 0.001 else { return p }
        let steps = 28
        for k in 0...steps {
            let pt = AviatorArt.point(progress * Double(k) / Double(steps), in: rect.size)
            if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

/// The shaded area under the curve.
private struct FlightArea: Shape {
    var progress: Double
    var animatableData: Double { get { progress } set { progress = newValue } }

    func path(in rect: CGRect) -> Path {
        var p = FlightCurve(progress: progress).path(in: rect)
        guard progress > 0.001 else { return p }
        let end = AviatorArt.point(progress, in: rect.size)
        let start = AviatorArt.point(0, in: rect.size)
        p.addLine(to: CGPoint(x: end.x, y: start.y))
        p.closeSubpath()
        return p
    }
}

/// Dark sky with faint sunburst rays from the runway corner and the dotted axes (static).
private struct AviatorSky: View, Equatable {
    var body: some View {
        Canvas { ctx, s in
            ctx.fill(Path(CGRect(origin: .zero, size: s)), with: .color(Color(red: 0.07, green: 0.07, blue: 0.085)))
            let o = CGPoint(x: s.width * 0.02, y: s.height * 0.98)
            let R = hypot(s.width, s.height) * 1.1
            let rays = 18
            var fan = Path()
            for k in stride(from: 0, to: rays, by: 2) {
                let a0 = -Double.pi / 2 * Double(k) / Double(rays)
                let a1 = -Double.pi / 2 * Double(k + 1) / Double(rays)
                fan.move(to: o)
                fan.addLine(to: CGPoint(x: o.x + R * CGFloat(cos(a0)), y: o.y + R * CGFloat(sin(a0))))
                fan.addLine(to: CGPoint(x: o.x + R * CGFloat(cos(a1)), y: o.y + R * CGFloat(sin(a1))))
                fan.closeSubpath()
            }
            ctx.fill(fan, with: .radialGradient(Gradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0.012)]),
                                                center: o, startRadius: 0, endRadius: R * 0.8))
            // Axis dots along the bottom and the left edge.
            var dots = Path()
            var x: CGFloat = s.width * 0.1
            while x < s.width - 6 { dots.addEllipse(in: CGRect(x: x - 1.5, y: s.height - 7, width: 3, height: 3)); x += s.width * 0.1 }
            var y: CGFloat = s.height * 0.12
            while y < s.height - 12 { dots.addEllipse(in: CGRect(x: 5, y: y - 1.5, width: 3, height: 3)); y += s.height * 0.12 }
            ctx.fill(dots, with: .color(Color(red: 0.3, green: 0.7, blue: 1).opacity(0.5)))
        }
        .allowsHitTesting(false)
    }
}

/// The red propeller plane (facing right), with a banana at the controls. Drawn once.
private struct PlaneArt: View, Equatable {
    var body: some View {
        Canvas { ctx, s in
            let w = s.width, h = s.height
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
            let red = AviatorArt.red
            let dark = Color(red: 0.55, green: 0.0, blue: 0.12)
            // Tail fin and stabiliser.
            var fin = Path()
            fin.move(to: pt(0.06, 0.52)); fin.addLine(to: pt(0.0, 0.1)); fin.addLine(to: pt(0.14, 0.12)); fin.addLine(to: pt(0.26, 0.46)); fin.closeSubpath()
            ctx.fill(fin, with: .color(red))
            ctx.stroke(fin, with: .color(dark), lineWidth: max(1, w * 0.012))
            // Fuselage.
            var body = Path()
            body.move(to: pt(0.04, 0.5))
            body.addQuadCurve(to: pt(0.8, 0.34), control: pt(0.3, 0.26))
            body.addQuadCurve(to: pt(0.86, 0.62), control: pt(0.93, 0.45))
            body.addQuadCurve(to: pt(0.04, 0.58), control: pt(0.4, 0.78))
            body.closeSubpath()
            ctx.fill(body, with: .linearGradient(Gradient(colors: [red.lit(0.25), red, dark]),
                                                 startPoint: pt(0.5, 0.28), endPoint: pt(0.5, 0.75)))
            ctx.stroke(body, with: .color(dark), lineWidth: max(1, w * 0.012))
            // Canopy with the banana pilot.
            var canopy = Path()
            canopy.move(to: pt(0.46, 0.34)); canopy.addQuadCurve(to: pt(0.68, 0.33), control: pt(0.56, 0.08)); canopy.closeSubpath()
            ctx.fill(canopy, with: .color(Color(red: 0.72, green: 0.88, blue: 1).opacity(0.9)))
            FruitArt.draw(.banana, in: ctx, at: pt(0.565, 0.27), radius: w * 0.05, angle: .degrees(-70))
            ctx.stroke(canopy, with: .color(dark), lineWidth: max(1, w * 0.01))
            // Wing.
            var wing = Path()
            wing.move(to: pt(0.36, 0.56)); wing.addLine(to: pt(0.7, 0.54)); wing.addLine(to: pt(0.6, 0.84)); wing.addLine(to: pt(0.42, 0.86)); wing.closeSubpath()
            ctx.fill(wing, with: .color(dark))
            // Nose hub and the blurred propeller disc.
            ctx.fill(Path(ellipseIn: CGRect(x: 0.84 * w, y: 0.4 * h, width: 0.1 * w, height: 0.2 * h)), with: .color(Color(white: 0.85)))
            ctx.fill(Path(ellipseIn: CGRect(x: 0.9 * w, y: 0.02 * h, width: 0.08 * w, height: 0.96 * h)),
                     with: .radialGradient(Gradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.08)]),
                                           center: pt(0.94, 0.5), startRadius: 0, endRadius: h * 0.5))
            var blade = Path()
            blade.move(to: pt(0.94, 0.08)); blade.addLine(to: pt(0.94, 0.92))
            ctx.stroke(blade, with: .color(Color(white: 0.2).opacity(0.55)), style: StrokeStyle(lineWidth: max(1.5, w * 0.02), lineCap: .round))
        }
        .allowsHitTesting(false)
    }
}

/// Fireball and flying debris where the plane comes down.
private struct CrashBlast: View {
    let size: CGFloat
    @State private var go = false

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.95, blue: 0.6), Color(red: 1, green: 0.5, blue: 0.1),
                                              Color(red: 0.8, green: 0.1, blue: 0.05).opacity(0)],
                                     center: .center, startRadius: 0, endRadius: size * 0.5))
                .frame(width: size, height: size)
                .scaleEffect(go ? 1.3 : 0.2)
                .opacity(go ? 0 : 1)
            Circle()
                .fill(Color(white: 0.25).opacity(0.7))
                .frame(width: size * 0.6, height: size * 0.6)
                .scaleEffect(go ? 1.4 : 0.3)
                .offset(y: go ? -size * 0.35 : 0)
                .opacity(go ? 0 : 0.8)
            ParticleBurstView(color: Color(red: 1, green: 0.55, blue: 0.1), count: 12, spread: size * 0.7)
        }
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeOut(duration: 0.45)) { go = true } }
    }
}

/// Crash-game buttons: flat, rounded, a real press dips them; the demo's `lit` press looks the same.
private struct AviatorButtonStyle: ButtonStyle {
    var fill: Color
    var text: Color = .white
    var lit: Bool
    var height: CGFloat
    var capsule = false

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed || lit
        return configuration.label
            .foregroundStyle(text)
            .frame(maxWidth: capsule ? nil : .infinity)
            .frame(height: height)
            .frame(maxWidth: capsule ? .infinity : nil)
            .background(RoundedRectangle(cornerRadius: capsule ? height / 2 : 14).fill(fill.lit(down ? 0.12 : 0)))
            .overlay(RoundedRectangle(cornerRadius: capsule ? height / 2 : 14).stroke(Color.white.opacity(down ? 0.9 : 0.1), lineWidth: down ? 2.5 : 1))
            .scaleEffect(down ? 0.95 : 1)
    }
}

