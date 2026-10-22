//
//  LiveDemoView.swift
//  GOGs
//
//  The manual's win "clip" is a LIVE, self-looping replay of the game's own view —
//  no bundled mp4. When a game view is rendered with `\.isDemo == true` it seeds a
//  fixed Level-1 setup, auto-plays a scripted winning move, holds on the final
//  moments, then resets and loops. It never calls onWin/onFail, so it can't touch
//  the real feed. This is muted and non-interactive.
//
//  A game opts in by setting `liveDemo: true` on its `GameManual`; until it does,
//  `GameManualView` falls back to the old mp4 path (or nothing), so the roll-out is
//  incremental.
//

import SwiftUI

extension EnvironmentValues {
    /// True when a game view is being rendered as a looping manual demo (not real
    /// play). Games read this to switch into their deterministic auto-play loop.
    @Entry var isDemo: Bool = false
}

/// Renders a game's own view as a muted, non-interactive, self-looping demo for the
/// manual. The game handles the seeding + looping internally when `\.isDemo` is true;
/// the empty `onWin`/`onFail` closures are never called in demo mode.
struct LiveDemoView: View {
    let game: GameDefinition

    var body: some View {
        game.makeView(1, {}, {})
            .environment(\.isDemo, true)
            .allowsHitTesting(false)
            // A demo may drive a game's real tap/win functions; keep it silent.
            .onAppear {
                SoundManager.shared.suppressed = true
                Haptics.suppressed = true
            }
            .onDisappear {
                SoundManager.shared.suppressed = false
                Haptics.suppressed = false
            }
    }
}

/// A one-shot expanding ring that plays once on appear — shows a "tap" in demos of games
/// that have no button (tap anywhere). Key each tap with an incrementing `.id(n)` so a new
/// ripple mounts per tap; don't gate it on a Bool or it rests as a static ring.
struct DemoTapRipple: View {
    @State private var go = false
    var body: some View {
        Circle()
            .stroke(.white.opacity(0.85), lineWidth: 3)
            .frame(width: 26, height: 26)
            .scaleEffect(go ? 3.6 : 0.7)
            .opacity(go ? 0 : 0.9)
            .allowsHitTesting(false)
            .onAppear { withAnimation(.easeOut(duration: 0.55)) { go = true } }
    }
}
