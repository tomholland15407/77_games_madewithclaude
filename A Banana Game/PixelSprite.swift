//
//  PixelSprite.swift
//  A Banana Game
//
//  A tiny reusable pixel-art renderer. A sprite is authored as an array of
//  equal-length strings — one character per pixel — plus a palette that maps
//  each character to a color. Unmapped characters (e.g. ".") are transparent.
//
//  This lets the pixel-art games (Critter Pop, Sprite Match, Pixel Invaders)
//  hand-place crisp, chunky pixels with zero image assets: the art lives in
//  code as data. Drawing goes through a single `Canvas` so a whole sprite is
//  one lightweight view no matter how many pixels it has.
//

import SwiftUI

/// Draws a pixel-art sprite, scaled to fill its frame while staying square
/// (the art is centered and never stretched — pixels stay pixels).
struct PixelSprite: View {
    /// Rows of the sprite; each `Character` is one pixel.
    let rows: [String]
    /// Character → color. Characters missing from the map are transparent.
    let palette: [Character: Color]
    /// If set, every *mapped* (non-transparent) pixel draws in this flat color
    /// instead of its palette color. Used to render a solid silhouette (e.g. for
    /// the sticker outline in `OutlinedPixelSprite`). Transparency is preserved.
    var tint: Color? = nil

    var body: some View {
        Canvas { context, size in
            let height = rows.count
            let width = rows.map(\.count).max() ?? 0
            guard width > 0, height > 0 else { return }

            // Largest square cell that fits, so the sprite keeps its aspect.
            let cell = min(size.width / CGFloat(width),
                           size.height / CGFloat(height))
            let originX = (size.width - cell * CGFloat(width)) / 2
            let originY = (size.height - cell * CGFloat(height)) / 2

            for (r, row) in rows.enumerated() {
                for (c, ch) in row.enumerated() {
                    guard let color = palette[ch] else { continue }
                    // +0.6 overdraw closes hairline seams between cells.
                    let rect = CGRect(x: originX + CGFloat(c) * cell,
                                      y: originY + CGFloat(r) * cell,
                                      width: cell + 0.6,
                                      height: cell + 0.6)
                    context.fill(Path(rect), with: .color(tint ?? color))
                }
            }
        }
    }
}
