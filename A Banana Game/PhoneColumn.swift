//
//  PhoneColumn.swift
//  A Banana Game
//
//  Keeps the app phone-shaped on iPad. Every game is designed for a portrait iPhone
//  (393 × 852 pt); in a window much wider than a phone (iPad, landscape) the content sits
//  in a centred column of the iPhone's aspect, as tall as the window, on black. In a
//  phone-shaped window (iPhone, iPad Slide Over) it fills the window exactly as before.
//

import SwiftUI

struct PhoneColumn<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            // The column spans the whole screen height, safe areas included (the feed is full-bleed).
            let fullHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            let phoneWidth = fullHeight * 393 / 852
            // One layout for both cases (only the width changes), so rotating keeps the game's state.
            let width = proxy.size.width > phoneWidth * 1.3 ? phoneWidth : proxy.size.width
            content
                .frame(width: width, height: proxy.size.height)
                .frame(maxWidth: .infinity)
        }
        .background(Color.black.ignoresSafeArea())
    }
}
