//
//  StatsView.swift
//  GOGs
//
//  The "unrot your brain" scoreboard, reached from the feed's top controls.
//  Shows the daily streak (and best ever), plus the two point pools: Smart
//  (earned on brain games) and Fresh (earned on reflex games). Big, readable
//  type only — no tiny text.
//

import SwiftUI

struct StatsView: View {
    @Environment(StatsStore.self) private var stats
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    motto
                    streakCard
                    HStack(spacing: 16) {
                        pointCard(title: L("SMART", "THÔNG MINH"),
                                  genre: .brain,
                                  value: stats.smartPoints)
                        pointCard(title: L("FRESH", "TỈNH TÁO"),
                                  genre: .reflex,
                                  value: stats.freshPoints)
                    }
                    totalCard
                }
                .padding(24)
            }
            .scrollContentBackground(.hidden)
            .background(BananaTheme.background)
            .navigationTitle(L("Your Brain", "Não của bạn"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done", "Xong")) { dismiss() }
                        .foregroundStyle(BananaTheme.banana)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Pieces

    private var motto: some View {
        VStack(spacing: 8) {
            Text("🍌")
                .font(.system(size: 52))
            Text(L("UNROT YOUR BRAIN", "UNROT NÃO CỦA BẠN"))
                .font(.system(size: 22, weight: .black, design: .rounded))
                .tracking(2)
                .foregroundStyle(BananaTheme.banana)
        }
        .padding(.top, 8)
    }

    private var streakCard: some View {
        VStack(spacing: 6) {
            Text("\(stats.currentStreak)")
                .font(.system(size: 72, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text(L("DAY STREAK", "CHUỖI NGÀY"))
                .font(.subheadline.weight(.heavy))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.6))
            Text(L("Best: \(stats.bestStreak)", "Kỷ lục: \(stats.bestStreak)"))
                .font(.headline.weight(.bold))
                .foregroundStyle(BananaTheme.banana)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(RoundedRectangle(cornerRadius: 24).fill(.white.opacity(0.05)))
    }

    private func pointCard(title: String, genre: Genre, value: Int) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.heavy))
                .tracking(2)
                .foregroundStyle(genre.tint)
            Text("\(value)")
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            // Which games earn this pool, as the genre's icon.
            GenreIcon(genre: genre)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(RoundedRectangle(cornerRadius: 20).fill(.white.opacity(0.05)))
    }

    private var totalCard: some View {
        VStack(spacing: 4) {
            Text("\(stats.totalPoints)")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text(L("TOTAL POINTS", "TỔNG ĐIỂM"))
                .font(.subheadline.weight(.heavy))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(RoundedRectangle(cornerRadius: 20).fill(.white.opacity(0.05)))
    }
}
