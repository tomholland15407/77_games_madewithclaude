//
//  SoloChessGame.swift
//  A Banana Game
//
//  Brain — Solo Chess. Every move must capture, and each piece may move at most twice. Clear the
//  board down to a single piece to win. Pieces move like real chess (knights jump, rooks/bishops/
//  queens slide and can't leap, kings step one square); a piece that has moved twice locks. Pick a
//  wrong order and you strand pieces with no captures left — that's a dead end, and a fail sends you
//  back to level 1. A clock keeps it honest.
//
//  Boards are built backwards from the winning position: starting with the lone survivor, the
//  generator repeatedly "un-captures" — sliding a piece to a legal source square and dropping the
//  piece it must have taken onto the vacated square. Because every un-capture is the exact inverse
//  of a legal capture on the live board, the forward solution is guaranteed to exist, and the start
//  is never already solved. Levels add pieces, board size, and stronger piece types.
//
//  Drawn like Chess.com's Solo Chess: the green-and-cream board with corner coordinates on the site's
//  dark panel, white pieces that turn black once they have made their two captures (a small "1"
//  badge marks a piece with one capture left), yellow selected/last-move squares, grey capture rings
//  on the pieces you can take, and a chess clock for the time limit.
//

import SwiftUI

private enum PType: Sendable {
    case king, knight, rook, bishop, queen
    var glyph: String {
        switch self {
        case .king: return "♚"; case .knight: return "♞"; case .rook: return "♜"
        case .bishop: return "♝"; case .queen: return "♛"
        }
    }
}

private nonisolated struct SoloPiece: Identifiable, Sendable {
    let id: Int
    var r: Int
    var c: Int
    let type: PType
    var movesMade: Int
}

enum SoloChessGame {
    static let definition = GameDefinition(
        id: "solo-chess",
        title: "Chess Sweep",
        emoji: "🍌",
        genre: .brain,
        levelCount: 7,
        manual: GameManual(
            bullets: [
                "Every move must capture another piece.",
                "Each piece can move at most twice, then it locks.",
                "Tap a piece to select it, then tap a piece it can legally capture.",
                "Reduce the board to a single piece to win; no captures left or a timeout fails you.",
            ],
            bulletsVI: [
                "Mỗi nước đi đều phải ăn một quân khác.",
                "Mỗi quân chỉ được đi tối đa hai lần, sau đó bị khóa.",
                "Chạm một quân để chọn, rồi chạm quân mà nó có thể ăn hợp lệ.",
                "Giảm bàn cờ xuống còn một quân để thắng; hết nước ăn hoặc hết giờ là thua.",
            ],
            liveDemo: true
        ),
        makeView: { level, onWin, onFail in
            AnyView(SoloChessView(level: level, onWin: onWin, onFail: onFail))
        },
        prefetch: { level in SoloChessView(level: level, onWin: {}, onFail: {}).prefetchBoard() }
    )
}

struct SoloChessView: View {
    let level: Int
    let onWin: () -> Void
    let onFail: () -> Void

    @Environment(\.isDemo) private var isDemo

    private var boardN: Int { [4, 4, 5, 5, 6, 6, 6][min(level, 7) - 1] }
    private var targetCount: Int { [3, 4, 5, 6, 7, 8, 9][min(level, 7) - 1] }
    private var timeLimit: Double { [35, 45, 55, 65, 75, 85, 95][min(level, 7) - 1] }

    private var skyTop: Color { SoloArt.panel }
    private var skyBottom: Color { SoloArt.panelDeep }

    private enum Phase { case play, done }
    @State private var phase: Phase = .play
    @State private var ready = false
    @State private var N = 0
    @State private var pieces: [SoloPiece] = []
    @State private var selectedID: Int? = nil
    @State private var timeLeft = 0.0
    @State private var loopTask: Task<Void, Never>?
    @State private var demoTapSq: Int? = nil     // demo: square being tapped (finger)
    @State private var lastMove: [Int] = []      // presentation only: the from/to squares of the last capture

    var body: some View {
        Group {
            if ready { gameBody } else { BrainstormingView(skyTop: skyTop, skyBottom: skyBottom) }
        }
        .task { isDemo ? await runDemo() : await run() }
        .onDisappear { loopTask?.cancel() }
    }

    private var gameBody: some View {
        // The HUD sits right on top of the board, and the pair is centred on the panel.
        GeometryReader { geo in
            let hudH: CGFloat = isDemo ? 22 : 40
            let gap: CGFloat = isDemo ? 2 : 6
            let s = max(40, min(geo.size.width, geo.size.height - hudH - gap))
            VStack(spacing: gap) {
                hud.frame(width: s - 12, height: hudH)
                boardView.frame(width: s, height: s)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(.vertical, isDemo ? 4 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SoloArt.panel)
        .clipShape(RoundedRectangle(cornerRadius: isDemo ? 12 : 22))
        .padding(.horizontal, isDemo ? 0 : 8)
    }

    /// Pieces left on the site's dark panel, and the chess clock (hidden in the manual demo).
    private var hud: some View {
        HStack(spacing: 10) {
            if isDemo { Spacer() }
            Image(systemName: "checkerboard.rectangle")
                .font(.system(size: isDemo ? 14 : 18, weight: .semibold))
                .foregroundStyle(SoloArt.green)
            Text(L("\(pieces.count) LEFT", "CÒN \(pieces.count)"))
                .font(.system(size: isDemo ? 15 : 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            if !isDemo { clock }
        }
    }

    private var boardView: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) - 12
            let cell = N > 0 ? side / CGFloat(N) : 0
            let ox = (geo.size.width - cell * CGFloat(N)) / 2
            let oy = (geo.size.height - cell * CGFloat(N)) / 2
            let selected = selectedID.flatMap { id in pieces.first { $0.id == id } }
            let targets = selected.map { targetSquares(of: $0) } ?? []
            let marked = Set(lastMove + (selected.map { [$0.r * N + $0.c] } ?? []))

            ZStack {
                // The board: squares, highlights, coordinates and capture rings (redrawn only when
                // the selection or the last move changes, not on every clock tick).
                SoloBoard(n: N, cell: cell, ox: ox, oy: oy, marked: marked, targets: targets).equatable()
                // Pieces.
                ForEach(pieces) { p in
                    pieceView(p, cell: cell)
                        .position(x: ox + (CGFloat(p.c) + 0.5) * cell,
                                  y: oy + (CGFloat(p.r) + 0.5) * cell)
                        .animation(.easeOut(duration: 0.18), value: p.r * 100 + p.c)
                }
                // Demo: a finger on the square being tapped.
                if let sq = demoTapSq, N > 0 {
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: cell * 0.42))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 3)
                        .position(x: ox + (CGFloat(sq % N) + 0.78) * cell, y: oy + (CGFloat(sq / N) + 0.84) * cell)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// A Chess.com-style piece: white until it has made its two captures, then black.
    /// A piece with one capture left wears a small "1" badge.
    private func pieceView(_ p: SoloPiece, cell: CGFloat) -> some View {
        let locked = p.movesMade >= 2
        return ZStack {
            SoloPieceArt(type: p.type, black: locked).equatable()
            if p.movesMade == 1 {
                Text("1")
                    .font(.system(size: cell * 0.17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: cell * 0.27, height: cell * 0.27)
                    .background(Circle().fill(SoloArt.panelDeep))
                    .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: max(1, cell * 0.02)))
                    .offset(x: cell * 0.33, y: -cell * 0.33)
            }
        }
        .frame(width: cell, height: cell)
        .contentShape(Rectangle())
        .onTapGesture { tap(p.id) }
    }

    /// The time limit as a Chess.com clock: white while there's time, red once it runs low.
    private var clock: some View {
        let frac = timeLimit > 0 ? timeLeft / timeLimit : 0
        let low = frac < 0.3
        let secs = Int(ceil(timeLeft))
        return HStack(spacing: 7) {
            Image(systemName: "clock.fill")
                .font(.system(size: 15, weight: .bold))
            Text(String(format: "%d:%02d", secs / 60, secs % 60))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(low ? .white : SoloArt.panelDeep)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(low ? SoloArt.lowClock : SoloArt.clockFace))
        .transaction { $0.animation = nil }
    }

    // MARK: - Flow
    /// Hands this level's board build to `BoardCache` so it can run during the countdown.
    func prefetchBoard() {
        let n = boardN, t = targetCount, types = allowedTypes
        BoardCache.prefetch(boardKey) { Self.generate(N: n, target: t, types: types) }
    }
    private var boardKey: String { BoardCache.key("solo-chess", level: level) }

    private func run() async {
        let n = boardN, t = targetCount, types = allowedTypes
        let t0 = Date()
        let built = await BoardCache.take(boardKey) { Self.generate(N: n, target: t, types: types) }
        guard !Task.isCancelled else { return }
        await BoardCache.holdBrainstorm(since: t0, minimum: 0.7)
        guard !Task.isCancelled else { return }
        N = n
        pieces = built
        selectedID = nil
        ready = true
        phase = .play
        timeLeft = timeLimit
        let start = Date()
        loopTask = Task {
            while !Task.isCancelled && phase == .play {
                try? await Task.sleep(for: .seconds(0.05))
                timeLeft = max(0, timeLimit - Date().timeIntervalSince(start))
                if timeLeft <= 0 { fail(); break }
            }
        }
    }

    private var allowedTypes: [PType] {
        switch level {
        case 1, 2: return [.king, .knight, .rook]
        case 3, 4: return [.king, .knight, .rook, .bishop]
        default:   return [.king, .knight, .rook, .bishop, .queen]
        }
    }

    // MARK: - Demo (live manual clip)
    // A fixed Level-1 board (4×4; king, knight, rook). The demo taps through the real `tap`:
    // select the knight (its capture squares light up) and take the king, then select the rook
    // and slide it along the row to take the knight — one piece left → the real win().
    private static let demoPieces = [
        SoloPiece(id: 0, r: 0, c: 0, type: .king, movesMade: 0),
        SoloPiece(id: 1, r: 0, c: 3, type: .rook, movesMade: 0),
        SoloPiece(id: 2, r: 2, c: 1, type: .knight, movesMade: 0),
    ]
    /// (piece id to tap) in order: select knight, capture king, select rook, capture knight.
    private static let demoTaps = [2, 0, 1, 2]

    private func runDemo() async {
        while !Task.isCancelled {
            N = 4
            pieces = Self.demoPieces
            selectedID = nil
            demoTapSq = nil
            lastMove = []
            timeLeft = timeLimit
            phase = .play
            ready = true
            try? await Task.sleep(for: .seconds(0.9))
            for id in Self.demoTaps {
                guard !Task.isCancelled else { return }
                guard let p = pieces.first(where: { $0.id == id }) else { continue }
                demoTapSq = p.r * N + p.c
                try? await Task.sleep(for: .seconds(0.3))
                guard !Task.isCancelled else { return }
                tap(id)
                try? await Task.sleep(for: .seconds(0.55))
            }
            demoTapSq = nil
            // One piece left → the real win() ran (onWin is a no-op). Hold, then loop.
            try? await Task.sleep(for: .seconds(1.3))
        }
    }

    // MARK: - Input
    private func tap(_ id: Int) {
        guard phase == .play, let idx = pieces.firstIndex(where: { $0.id == id }) else { return }
        if let selID = selectedID, selID != id,
           let selIdx = pieces.firstIndex(where: { $0.id == selID }) {
            let sq = pieces[idx].r * N + pieces[idx].c
            if targetSquares(of: pieces[selIdx]).contains(sq) {
                capture(moverIdx: selIdx, targetIdx: idx); return
            }
        }
        if selectedID == id { selectedID = nil; return }
        if pieces[idx].movesMade < 2 { selectedID = id; SoundManager.shared.tap() }
        else { selectedID = nil; SoundManager.shared.error() }
    }

    private func capture(moverIdx: Int, targetIdx: Int) {
        let tr = pieces[targetIdx].r, tc = pieces[targetIdx].c
        pieces.remove(at: targetIdx)
        // recompute mover index (array shifted if target was before it)
        guard let mi = pieces.firstIndex(where: { $0.id == selectedID }) else { return }
        lastMove = [pieces[mi].r * N + pieces[mi].c, tr * N + tc]   // presentation: highlight the move's squares
        pieces[mi].r = tr; pieces[mi].c = tc; pieces[mi].movesMade += 1
        selectedID = nil
        SoundManager.shared.tap(); Haptics.tap()
        if pieces.count == 1 { win(); return }
        if isDead() { deadFail() }
    }

    private func targetSquares(of p: SoloPiece) -> Set<Int> {
        let occ = Set(pieces.map { $0.r * N + $0.c })
        return Self.reachableCaptures(r: p.r, c: p.c, type: p.type, N: N, occupied: occ)
    }

    private func isDead() -> Bool {
        for p in pieces where p.movesMade < 2 {
            if !targetSquares(of: p).isEmpty { return false }
        }
        return true
    }

    private func deadFail() {
        guard phase == .play else { return }
        phase = .done; loopTask?.cancel()
        SoundManager.shared.error(); Haptics.warning()
        Task { try? await Task.sleep(for: .seconds(0.4)); onFail() }
    }

    private func win() {
        guard phase != .done else { return }
        phase = .done; loopTask?.cancel(); onWin()
    }

    private func fail() {
        guard phase != .done else { return }
        phase = .done; loopTask?.cancel(); SoundManager.shared.error(); onFail()
    }

    // MARK: - Move geometry (shared)
    private static let kingDirs = [(-1,-1),(-1,0),(-1,1),(0,-1),(0,1),(1,-1),(1,0),(1,1)]
    private static let knightJumps = [(-2,-1),(-2,1),(-1,-2),(-1,2),(1,-2),(1,2),(2,-1),(2,1)]
    private static let rookDirs = [(-1,0),(1,0),(0,-1),(0,1)]
    private static let bishopDirs = [(-1,-1),(-1,1),(1,-1),(1,1)]

    private static func slideDirs(_ type: PType) -> [(Int, Int)]? {
        switch type {
        case .rook: return rookDirs
        case .bishop: return bishopDirs
        case .queen: return rookDirs + bishopDirs
        default: return nil
        }
    }

    /// Squares occupied by a capturable piece reachable from (r,c) by `type` on the live board.
    private static func reachableCaptures(r: Int, c: Int, type: PType, N: Int, occupied: Set<Int>) -> Set<Int> {
        func inb(_ rr: Int, _ cc: Int) -> Bool { rr >= 0 && rr < N && cc >= 0 && cc < N }
        func occ(_ rr: Int, _ cc: Int) -> Bool { occupied.contains(rr * N + cc) }
        var res = Set<Int>()
        if type == .king {
            for (dr, dc) in kingDirs where inb(r + dr, c + dc) && occ(r + dr, c + dc) {
                res.insert((r + dr) * N + (c + dc))
            }
        } else if type == .knight {
            for (dr, dc) in knightJumps where inb(r + dr, c + dc) && occ(r + dr, c + dc) {
                res.insert((r + dr) * N + (c + dc))
            }
        } else if let dirs = slideDirs(type) {
            for (dr, dc) in dirs {
                var rr = r + dr, cc = c + dc
                while inb(rr, cc) {
                    if occ(rr, cc) { res.insert(rr * N + cc); break }
                    rr += dr; cc += dc
                }
            }
        }
        return res
    }

    /// Empty source squares from which `type` could have moved to `q` (path clear) — the generator's
    /// inverse move. `occ` is the current occupancy (q is occupied by the mover; endpoints allowed).
    private static func sourcesThatReach(q: Int, type: PType, N: Int, occ: Set<Int>) -> [Int] {
        let qr = q / N, qc = q % N
        func inb(_ rr: Int, _ cc: Int) -> Bool { rr >= 0 && rr < N && cc >= 0 && cc < N }
        func empty(_ rr: Int, _ cc: Int) -> Bool { !occ.contains(rr * N + cc) }
        var res = [Int]()
        if type == .king {
            for (dr, dc) in kingDirs where inb(qr + dr, qc + dc) && empty(qr + dr, qc + dc) {
                res.append((qr + dr) * N + (qc + dc))
            }
        } else if type == .knight {
            for (dr, dc) in knightJumps where inb(qr + dr, qc + dc) && empty(qr + dr, qc + dc) {
                res.append((qr + dr) * N + (qc + dc))
            }
        } else if let dirs = slideDirs(type) {
            for (dr, dc) in dirs {
                var rr = qr + dr, cc = qc + dc
                while inb(rr, cc) && empty(rr, cc) {   // path stays clear up to and including s
                    res.append(rr * N + cc)
                    rr += dr; cc += dc
                }
            }
        }
        return res
    }

    // MARK: - Generation (backward from the lone survivor)
    private nonisolated struct GenPiece { var sq: Int; var type: PType; var budget: Int }

    private nonisolated static func generate(N: Int, target: Int, types: [PType]) -> [SoloPiece] {
        var best: [GenPiece] = []
        for _ in 0..<60 {
            var list = [GenPiece(sq: Int.random(in: 0..<(N * N)),
                                 type: types.randomElement()!, budget: 2)]
            var occ: Set<Int> = [list[0].sq]
            var guardCount = 0
            while list.count < target && guardCount < target * 40 {
                guardCount += 1
                var didUndo = false
                for mi in list.indices.filter({ list[$0].budget >= 1 }).shuffled() {
                    let q = list[mi].sq
                    let sources = sourcesThatReach(q: q, type: list[mi].type, N: N, occ: occ).shuffled()
                    guard let s = sources.first else { continue }
                    list[mi].sq = s
                    list[mi].budget -= 1
                    let vb = [0, 1, 1, 2].randomElement()!
                    list.append(GenPiece(sq: q, type: types.randomElement()!, budget: vb))
                    occ.insert(s)
                    didUndo = true
                    break
                }
                if !didUndo { break }
            }
            if list.count >= target { return convert(list, N: N) }
            if list.count > best.count { best = list }
        }
        return convert(best, N: N)
    }

    private nonisolated static func convert(_ list: [GenPiece], N: Int) -> [SoloPiece] {
        list.enumerated().map { SoloPiece(id: $0.offset, r: $0.element.sq / N, c: $0.element.sq % N,
                                          type: $0.element.type, movesMade: 0) }
    }
}

/// The Chess.com board: squares, highlighted squares, coordinates and capture rings.
private struct SoloBoard: View, Equatable {
    let n: Int
    let cell: CGFloat
    let ox: CGFloat
    let oy: CGFloat
    let marked: Set<Int>
    let targets: Set<Int>

    var body: some View {
        Canvas { ctx, _ in
            guard n > 0 else { return }
            let board = CGRect(x: ox, y: oy, width: cell * CGFloat(n), height: cell * CGFloat(n))
            var shadow = ctx
            shadow.addFilter(.shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 4))
            shadow.fill(Path(roundedRect: board, cornerRadius: 4), with: .color(SoloArt.darkSq))
            var sq = ctx
            sq.clip(to: Path(roundedRect: board, cornerRadius: 4))
            for r in 0..<n { for c in 0..<n {
                let rect = CGRect(x: ox + CGFloat(c) * cell, y: oy + CGFloat(r) * cell, width: cell, height: cell)
                let dark = (r + c) % 2 == 1
                sq.fill(Path(rect.insetBy(dx: -0.3, dy: -0.3)), with: .color(dark ? SoloArt.darkSq : SoloArt.lightSq))
                if marked.contains(r * n + c) {
                    sq.fill(Path(rect), with: .color(SoloArt.highlight))
                }
            }}
            // Rank numbers in the left file, file letters along the bottom rank, each in
            // the colour of the opposite square.
            let fs = cell * 0.17
            for r in 0..<n {
                let dark = r % 2 == 1
                ctx.draw(Text("\(n - r)").font(.system(size: fs, weight: .bold)).foregroundColor(dark ? SoloArt.lightSq : SoloArt.darkSq),
                         at: CGPoint(x: ox + cell * 0.05, y: oy + CGFloat(r) * cell + cell * 0.04), anchor: .topLeading)
            }
            let files = Array("abcdefgh")
            for c in 0..<min(n, files.count) {
                let dark = (n - 1 + c) % 2 == 1
                ctx.draw(Text(String(files[c])).font(.system(size: fs, weight: .bold)).foregroundColor(dark ? SoloArt.lightSq : SoloArt.darkSq),
                         at: CGPoint(x: ox + CGFloat(c + 1) * cell - cell * 0.05, y: oy + CGFloat(n) * cell - cell * 0.02), anchor: .bottomTrailing)
            }
            // Capture rings on every piece the selected one can take.
            for t in targets {
                let center = CGPoint(x: ox + (CGFloat(t % n) + 0.5) * cell, y: oy + (CGFloat(t / n) + 0.5) * cell)
                let rad = cell * 0.43
                ctx.stroke(Path(ellipseIn: CGRect(x: center.x - rad, y: center.y - rad, width: rad * 2, height: rad * 2)),
                           with: .color(.black.opacity(0.17)), lineWidth: cell * 0.1)
            }
        }
        .allowsHitTesting(false)
    }
}

/// One piece's art; Equatable so the clock's ticks don't redraw it.
private struct SoloPieceArt: View, Equatable {
    let type: PType
    let black: Bool

    var body: some View {
        Canvas { ctx, size in
            SoloArt.piece(ctx, type, black: black, in: CGRect(origin: .zero, size: size).insetBy(dx: size.width * 0.025, dy: size.height * 0.025))
        }
    }
}

// MARK: - Chess.com look

private enum SoloArt {
    static let lightSq = Color(red: 0.933, green: 0.933, blue: 0.824)    // #EEEED2
    static let darkSq = Color(red: 0.463, green: 0.588, blue: 0.337)     // #769656
    static let highlight = Color(red: 1, green: 1, blue: 0.2).opacity(0.5)
    static let panel = Color(red: 0.192, green: 0.180, blue: 0.169)      // #312E2B
    static let panelDeep = Color(red: 0.149, green: 0.141, blue: 0.129)  // #262421
    static let green = Color(red: 0.506, green: 0.714, blue: 0.298)      // #81B64C
    static let whiteBody = Color(red: 0.99, green: 0.99, blue: 0.98)
    static let whiteShade = Color(red: 0.84, green: 0.84, blue: 0.82)
    static let blackBody = Color(red: 0.27, green: 0.26, blue: 0.25)
    static let blackHi = Color(red: 0.42, green: 0.41, blue: 0.4)
    static let ink = Color(red: 0.2, green: 0.19, blue: 0.18)
    static let clockFace = Color(red: 0.97, green: 0.97, blue: 0.96)
    static let lowClock = Color(red: 0.85, green: 0.23, blue: 0.2)

    /// Chunky "neo"-style Staunton pieces in a unit square: a soft left-lit fill, a dark contour,
    /// and every piece but the knight on the same two-step base.
    static func piece(_ ctx: GraphicsContext, _ t: PType, black: Bool, in r: CGRect) {
        let s = min(r.width, r.height)
        let o = CGPoint(x: r.midX - s / 2, y: r.midY - s / 2)
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
        let fill: GraphicsContext.Shading = black
            ? .linearGradient(Gradient(colors: [blackHi, blackBody]), startPoint: P(0.3, 0), endPoint: P(0.78, 0))
            : .linearGradient(Gradient(colors: [whiteBody, whiteShade]), startPoint: P(0.4, 0), endPoint: P(0.82, 0))
        let line = black ? Color(red: 0.08, green: 0.08, blue: 0.07) : ink
        let lw = s * 0.045
        func part(_ p: Path) {
            ctx.fill(p, with: fill)
            ctx.stroke(p, with: .color(line), style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
        }
        func box(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ rad: CGFloat) -> Path {
            Path(roundedRect: CGRect(x: o.x + x0 * s, y: o.y + y0 * s, width: (x1 - x0) * s, height: (y1 - y0) * s), cornerRadius: rad * s)
        }
        func poly(_ pts: [(CGFloat, CGFloat)]) -> Path {
            var p = Path(); p.addLines(pts.map { P($0.0, $0.1) }); p.closeSubpath(); return p
        }
        func ball(_ x: CGFloat, _ y: CGFloat, _ rad: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: o.x + (x - rad) * s, y: o.y + (y - rad) * s, width: rad * 2 * s, height: rad * 2 * s))
        }
        /// A body that narrows from the collar up to `top`, with gently pinched sides.
        func waist(top: CGFloat, halfTop: CGFloat) -> Path {
            var p = Path()
            p.move(to: P(0.5 - halfTop, top))
            p.addQuadCurve(to: P(0.3, 0.75), control: P(0.5 - halfTop + 0.01, 0.66))
            p.addLine(to: P(0.7, 0.75))
            p.addQuadCurve(to: P(0.5 + halfTop, top), control: P(0.5 + halfTop - 0.01, 0.66))
            p.closeSubpath()
            return p
        }
        // The two-step base.
        part(box(0.19, 0.8, 0.81, 0.91, 0.035))
        part(box(0.25, 0.735, 0.75, 0.81, 0.03))
        switch t {
        case .rook:
            part(poly([(0.33, 0.42), (0.67, 0.42), (0.7, 0.74), (0.3, 0.74)]))
            part(box(0.27, 0.36, 0.73, 0.43, 0.02))
            part(poly([(0.25, 0.13), (0.37, 0.13), (0.37, 0.21), (0.44, 0.21), (0.44, 0.13), (0.56, 0.13),
                       (0.56, 0.21), (0.63, 0.21), (0.63, 0.13), (0.75, 0.13), (0.75, 0.365), (0.25, 0.365)]))
        case .bishop:
            var body = Path()
            body.move(to: P(0.41, 0.6))
            body.addQuadCurve(to: P(0.3, 0.75), control: P(0.41, 0.7))
            body.addLine(to: P(0.7, 0.75))
            body.addQuadCurve(to: P(0.59, 0.6), control: P(0.59, 0.7))
            body.closeSubpath()
            part(body)
            part(box(0.32, 0.55, 0.68, 0.615, 0.032))
            part(ball(0.5, 0.135, 0.055))
            var mitre = Path()
            mitre.move(to: P(0.5, 0.18))
            mitre.addCurve(to: P(0.665, 0.45), control1: P(0.6, 0.25), control2: P(0.68, 0.35))
            mitre.addCurve(to: P(0.5, 0.56), control1: P(0.65, 0.53), control2: P(0.58, 0.56))
            mitre.addCurve(to: P(0.335, 0.45), control1: P(0.42, 0.56), control2: P(0.35, 0.53))
            mitre.addCurve(to: P(0.5, 0.18), control1: P(0.32, 0.35), control2: P(0.4, 0.25))
            mitre.closeSubpath()
            part(mitre)
            var slit = Path()
            slit.move(to: P(0.57, 0.3)); slit.addLine(to: P(0.47, 0.42))
            ctx.stroke(slit, with: .color(line), style: StrokeStyle(lineWidth: lw, lineCap: .round))
        case .queen:
            part(waist(top: 0.5, halfTop: 0.14))
            let tips: [(CGFloat, CGFloat)] = [(0.16, 0.24), (0.33, 0.18), (0.5, 0.15), (0.67, 0.18), (0.84, 0.24)]
            part(poly([(0.3, 0.52), tips[0], (0.35, 0.39), tips[1], (0.45, 0.37), tips[2], (0.55, 0.37),
                       tips[3], (0.65, 0.39), tips[4], (0.7, 0.52)]))
            for tip in tips { part(ball(tip.0, tip.1, 0.048)) }
            part(box(0.29, 0.47, 0.71, 0.54, 0.025))
        case .king:
            part(waist(top: 0.52, halfTop: 0.14))
            part(box(0.465, 0.05, 0.535, 0.3, 0.012))
            part(box(0.4, 0.105, 0.6, 0.17, 0.012))
            var head = Path()
            head.move(to: P(0.33, 0.51))
            head.addCurve(to: P(0.27, 0.27), control1: P(0.2, 0.45), control2: P(0.15, 0.31))
            head.addCurve(to: P(0.5, 0.33), control1: P(0.37, 0.22), control2: P(0.46, 0.25))
            head.addCurve(to: P(0.73, 0.27), control1: P(0.54, 0.25), control2: P(0.63, 0.22))
            head.addCurve(to: P(0.67, 0.51), control1: P(0.85, 0.31), control2: P(0.8, 0.45))
            head.closeSubpath()
            part(head)
            var stem = Path()
            stem.move(to: P(0.5, 0.33)); stem.addLine(to: P(0.5, 0.48))
            ctx.stroke(stem, with: .color(line), style: StrokeStyle(lineWidth: lw * 0.8, lineCap: .round))
            part(box(0.29, 0.48, 0.71, 0.55, 0.025))
        case .knight:
            var head = Path()
            head.move(to: P(0.71, 0.74))
            head.addCurve(to: P(0.67, 0.3), control1: P(0.77, 0.58), control2: P(0.77, 0.4))
            head.addCurve(to: P(0.53, 0.13), control1: P(0.63, 0.22), control2: P(0.59, 0.16))
            head.addLine(to: P(0.5, 0.05))
            head.addLine(to: P(0.43, 0.15))
            head.addCurve(to: P(0.19, 0.43), control1: P(0.3, 0.19), control2: P(0.21, 0.32))
            head.addCurve(to: P(0.22, 0.54), control1: P(0.15, 0.48), control2: P(0.16, 0.53))
            head.addCurve(to: P(0.39, 0.5), control1: P(0.28, 0.56), control2: P(0.34, 0.51))
            head.addCurve(to: P(0.29, 0.74), control1: P(0.44, 0.58), control2: P(0.3, 0.64))
            head.closeSubpath()
            part(head)
            var mane = Path()
            mane.move(to: P(0.58, 0.18))
            mane.addCurve(to: P(0.66, 0.66), control1: P(0.71, 0.3), control2: P(0.73, 0.5))
            ctx.stroke(mane, with: .color(line.opacity(0.55)), style: StrokeStyle(lineWidth: lw * 0.8, lineCap: .round))
            ctx.fill(ball(0.41, 0.3, 0.032), with: .color(line))
            ctx.fill(ball(0.22, 0.475, 0.016), with: .color(line))
        }
    }
}
