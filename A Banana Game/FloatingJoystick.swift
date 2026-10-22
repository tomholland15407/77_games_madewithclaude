//
//  FloatingJoystick.swift
//  A Banana Game
//
//  A one-thumb joystick strip for the fast dodging games (Dodgeball, Laser Dodge). It sits under the
//  arena, so the thumb never covers the action, and it's tuned to feel sensitive:
//  - Floating: touch anywhere in the strip and the stick centres under your thumb. There's no jump on
//    the first touch and no small pad to aim for. Between touches the base rests where you last used
//    it, kept clear of the page's skip button in the middle of the strip.
//  - Short throw: full speed after `throwRadius` of thumb travel (about 22 pt in play).
//  - Brisk light pushes: a small dead zone (so a resting thumb doesn't drift), then a square-root
//    response, so a quarter push is already half speed while tiny nudges still allow fine dodges.
//  - Instant reversals: past a full push the centre follows the thumb, so turning around takes one
//    short flick instead of a trip back across the pad.
//
//  `vector` is the fraction of top speed per axis (length ≤ 1); the game moves its hero by it every
//  frame. Each game draws its own base and knob. In the manual demo the knob follows the scripted
//  `vector`, with a finger riding it, and touches are ignored.
//

import SwiftUI

struct FloatingJoystick<Base: View, Knob: View>: View {
    @Binding var vector: CGVector
    let baseSize: CGFloat
    var demo = false
    var active = true
    /// The base, given the current push (to light its arrows).
    @ViewBuilder var base: (CGVector) -> Base
    @ViewBuilder var knob: () -> Knob

    @State private var origin: CGPoint?        // the stick's centre while the thumb is down
    @State private var home: CGPoint?          // where the base rests between touches
    @State private var thumb: CGSize = .zero   // the knob's offset from the centre

    private var throwRadius: CGFloat { Self.throwRadius(baseSize) }
    private var knobSize: CGFloat { baseSize * 0.5 }

    /// Thumb travel for full speed.
    nonisolated static func throwRadius(_ baseSize: CGFloat) -> CGFloat { baseSize * 0.19 }
    /// Share of the throw that does nothing, so a resting thumb doesn't drift.
    nonisolated static var deadZone: CGFloat { 0.1 }

    /// Thumb offset → fraction of top speed: the dead zone, then a square root of the rest, so light
    /// pushes move briskly and a full push (or more) is top speed.
    nonisolated static func response(_ d: CGSize, throwRadius r: CGFloat) -> CGVector {
        let len = hypot(d.width, d.height)
        let m = min(1, len / max(1, r))
        guard m > deadZone, len > 0 else { return .zero }
        let k = ((m - deadZone) / (1 - deadZone)).squareRoot()
        return CGVector(dx: d.width / len * k, dy: d.height / len * k)
    }

    /// The thumb offset that gives `v` (the inverse of `response`), for the demo's knob.
    nonisolated static func thumbOffset(for v: CGVector, throwRadius r: CGFloat) -> CGSize {
        let k = min(1, hypot(v.dx, v.dy))
        guard k > 0.001 else { return .zero }
        let m = deadZone + k * k * (1 - deadZone)
        return CGSize(width: v.dx / k * m * r, height: v.dy / k * m * r)
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let c = origin ?? home ?? settle(CGPoint(x: size.width * 0.24, y: size.height / 2), in: size)
            let shown = demo ? Self.thumbOffset(for: vector, throwRadius: throwRadius) : thumb
            ZStack(alignment: .topLeading) {
                base(vector)
                    .frame(width: baseSize, height: baseSize)
                    .position(c)
                knob()
                    .frame(width: knobSize, height: knobSize)
                    .position(x: c.x + shown.width, y: c.y + shown.height)
                if demo && vector != .zero {
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: baseSize * 0.3))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 3)
                        .position(x: c.x + shown.width + baseSize * 0.1, y: c.y + shown.height + baseSize * 0.15)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(drag(in: size), including: demo ? .none : .all)
        }
        .onChange(of: active) { _, on in
            if !on { release() }
        }
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                guard active else { return }
                var o = origin ?? v.startLocation
                var d = CGSize(width: v.location.x - o.x, height: v.location.y - o.y)
                let len = hypot(d.width, d.height)
                if len > throwRadius {
                    // Past a full push the centre follows the thumb, so a reversal is one short flick.
                    let pull = (len - throwRadius) / len
                    o.x += d.width * pull
                    o.y += d.height * pull
                    d = CGSize(width: v.location.x - o.x, height: v.location.y - o.y)
                }
                origin = o
                thumb = d
                vector = Self.response(d, throwRadius: throwRadius)
            }
            .onEnded { _ in
                if let o = origin {
                    withAnimation(.spring(response: 0.25)) { home = settle(o, in: size) }
                }
                release()
            }
    }

    private func release() {
        origin = nil
        withAnimation(.spring(response: 0.2)) { thumb = .zero }
        vector = .zero
    }

    /// A resting spot for the base: inside the strip and clear of the skip button over its middle.
    private func settle(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let r = baseSize / 2
        var x = min(size.width - r - 4, max(r + 4, p.x))
        let y = min(max(r, size.height - r), max(r, p.y))
        let mid = size.width / 2, clear = r + 30
        if abs(x - mid) < clear { x = x < mid ? mid - clear : mid + clear }
        return CGPoint(x: x, y: y)
    }
}
