//
//  SearchView.swift
//  GOGs
//
//  A sheet for finding a specific game by name. Picking a result jumps the
//  feed straight to that game.
//

import SwiftUI

struct SearchView: View {
    /// The full catalog to search.
    let games: [GameDefinition]
    /// Called with the chosen game's id; the feed scrolls to it.
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var results: [GameDefinition] {
        let matched = query.isEmpty
            ? games
            : games.filter { $0.title.localizedCaseInsensitiveContains(query) }
        return matched.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List(results) { game in
                Button {
                    onSelect(game.id)
                    dismiss()
                } label: {
                    HStack {
                        Text(game.title)
                            .foregroundStyle(.white)
                        Spacer()
                        GenreIcon(genre: game.genre)
                            .font(.body.weight(.semibold))
                            .frame(width: 28)
                    }
                }
                .listRowBackground(Color.white.opacity(0.06))
            }
            .overlay {
                if results.isEmpty {
                    Text(L("No games match “\(query)”", "Không có trò chơi khớp “\(query)”"))
                        .foregroundStyle(BananaTheme.subtle)
                }
            }
            .scrollContentBackground(.hidden)
            .background(BananaTheme.background)
            .navigationTitle(L("Search", "Tìm kiếm"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: L("Game name", "Tên trò chơi"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Done", "Xong")) { dismiss() }
                        .foregroundStyle(BananaTheme.banana)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
