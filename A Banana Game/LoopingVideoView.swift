//
//  LoopingVideoView.swift
//  GOGs
//
//  A muted, controls-free, auto-looping video player for the manual's demo clip
//  (a short mp4 of an actual win). Loads a bundled clip by name; if the file is
//  missing it renders nothing, so games without a clip just show their bullets.
//
//  Naming convention: the clip file is `<game.id>-win.mp4` dropped into the app
//  target; the manual passes `demo:` = the name WITHOUT the extension.
//

import SwiftUI
import AVKit

struct LoopingVideoView: View {
    /// Asset name without extension, e.g. "mirror-maze-win".
    let name: String

    @State private var player: AVQueuePlayer?
    // Held so the looper isn't deallocated (AVPlayerLooper stops looping if released).
    @State private var looper: AVPlayerLooper?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .disabled(true)          // no controls, no hit-testing
                    .allowsHitTesting(false)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            } else {
                // File missing / not yet added — render nothing.
                Color.clear
            }
        }
        .task { setup() }
    }

    private func setup() {
        guard player == nil else { return }
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp4") else {
            return   // no clip for this game yet
        }
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer(playerItem: item)
        queue.isMuted = true
        queue.actionAtItemEnd = .advance
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue
        queue.play()
    }
}
