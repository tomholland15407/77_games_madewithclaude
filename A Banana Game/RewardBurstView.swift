//
//  RewardBurstView.swift
//  A Banana Game
//
//  A quick burst of bananas flying outward — the "instant reward" pop when you
//  beat a level.
//

import SwiftUI

struct RewardBurstView: View {
    @State private var animate = false
    private let count = 16

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let angle = Double(i) / Double(count) * 2 * .pi
                Text("🍌")
                    .font(.system(size: 32))
                    .scaleEffect(animate ? 1.3 : 0.3)
                    .offset(
                        x: animate ? cos(angle) * 190 : 0,
                        y: animate ? sin(angle) * 190 : 0
                    )
                    .opacity(animate ? 0 : 1)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { animate = true }
        }
    }
}
