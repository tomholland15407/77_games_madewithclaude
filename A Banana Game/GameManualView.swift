//
//  GameManualView.swift
//  GOGs
//
//  The in-game manual, shown when the player taps the book button on a game page.
//  It shows an optional looping win clip plus 2–4 bullets on how to play. Big,
//  readable type only — no tiny hint text, no per-level notes.
//

import SwiftUI

struct GameManualView: View {
    let game: GameDefinition
    let manual: GameManual
    let onClose: () -> Void

    var body: some View {
        ZStack {
            BananaTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        if manual.liveDemo {
                            liveDemo
                        } else if let demo = manual.demo {
                            demoVideo(demo)
                        }
                        howToPlaySection
                    }
                    .padding(24)
                    .padding(.bottom, 8)
                }

                closeButton
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("MANUAL", "HƯỚNG DẪN"))
                .font(.caption.weight(.heavy))
                .tracking(3)
                .foregroundStyle(BananaTheme.banana)
            // Title stays English on purpose (see CLAUDE.md).
            Text(game.title)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.top, 20)
    }

    /// A live, self-looping replay of the game itself (no mp4). Shown in a portrait
    /// card that mirrors the real play area; the game auto-plays its Level-1 win.
    private var liveDemo: some View {
        LiveDemoView(game: game)
            .frame(maxWidth: .infinity)
            .frame(height: 340)
            .background(BananaTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            )
    }

    private func demoVideo(_ name: String) -> some View {
        LoopingVideoView(name: name)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            )
    }

    private var howToPlaySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("HOW TO PLAY", "CÁCH CHƠI"))
                .font(.subheadline.weight(.heavy))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.55))

            ForEach(Array(manual.resolvedBullets.enumerated()), id: \.offset) { _, bullet in
                HStack(alignment: .top, spacing: 12) {
                    Text("•")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(BananaTheme.banana)
                    Text(bullet)
                        .font(.system(size: 19, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Text(L("Return to game", "Quay lại trò chơi"))
                .font(.headline.bold())
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(BananaTheme.banana, in: Capsule())
        }
    }
}
