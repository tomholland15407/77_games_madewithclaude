//
//  SettingsView.swift
//  GOGs
//
//  Checkpoint C's settings sheet: language, sound on/off, the feed filter, per-genre
//  frequency, and a real App Store update check (UpdateChecker).
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SoundManager.self) private var sound
    @Environment(UpdateChecker.self) private var updater
    @Environment(\.dismiss) private var dismiss

    /// The on-demand check's outcome: an update shows the pop-up; anything else an alert.
    @State private var foundUpdate: AppUpdate?
    @State private var updateMessage: UpdateMessage?

    private enum UpdateMessage: Identifiable {
        case upToDate, offline
        var id: Self { self }
    }

    // The language holder isn't in the environment; read the shared instance
    // directly. It's @Observable, so this Picker updates it live.
    @Bindable private var localization = Localization.shared

    /// Labels for genre weights 0…3.
    private var weightLabels: [String] {
        [L("Off", "Tắt"), L("Low", "Thấp"), L("Normal", "Vừa"), L("High", "Cao")]
    }

    var body: some View {
        @Bindable var settings = settings
        @Bindable var sound = sound

        NavigationStack {
            Form {
                Section(L("Language / Ngôn ngữ", "Ngôn ngữ / Language")) {
                    Picker(L("Language", "Ngôn ngữ"), selection: $localization.lang) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                }

                Section(L("Sound", "Âm thanh")) {
                    Toggle(L("Sound effects", "Hiệu ứng âm thanh"), isOn: $sound.isEnabled)
                }

                Section(L("Feed", "Bảng tin")) {
                    Picker(L("Show", "Hiển thị"), selection: $settings.feedFilter) {
                        ForEach(FeedFilter.allCases) { filter in
                            Text(filter.label).tag(filter)
                        }
                    }
                }

                Section {
                    ForEach(Genre.allCases) { genre in
                        HStack(spacing: 12) {
                            GenreIcon(genre: genre)
                                .font(.title3.weight(.semibold))
                                .frame(width: 28)
                            Picker(genre.label, selection: weightBinding(genre)) {
                                ForEach(AppSettings.weightRange, id: \.self) { value in
                                    Text(weightLabels[value]).tag(value)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text(L("Genre frequency", "Tần suất thể loại"))
                } footer: {
                    Text(L("How often each genre appears in the feed. “Off” hides it.",
                           "Mức độ xuất hiện của mỗi thể loại trong bảng tin. “Tắt” sẽ ẩn nó."))
                }

                Section {
                    Button(action: checkForUpdates) {
                        HStack {
                            Text(updater.isChecking ? L("Checking…", "Đang kiểm tra…")
                                                    : L("Check for Updates", "Kiểm tra cập nhật"))
                            Spacer()
                            if updater.isChecking { ProgressView().tint(BananaTheme.banana) }
                        }
                    }
                    .foregroundStyle(BananaTheme.banana)
                    .disabled(updater.isChecking)
                } footer: {
                    Text(L("Version \(updater.installedVersion)", "Phiên bản \(updater.installedVersion)"))
                }
            }
            .scrollContentBackground(.hidden)
            .background(BananaTheme.background)
            .navigationTitle(L("Settings", "Cài đặt"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done", "Xong")) { dismiss() }
                        .foregroundStyle(BananaTheme.banana)
                }
            }
            .alert(updateMessage == .offline ? L("Couldn't check", "Không thể kiểm tra")
                                             : L("You're up to date", "Bạn đang dùng bản mới nhất"),
                   isPresented: Binding(get: { updateMessage != nil }, set: { if !$0 { updateMessage = nil } }),
                   presenting: updateMessage) { _ in
                Button(L("OK", "OK"), role: .cancel) { }
            } message: { message in
                switch message {
                case .upToDate:
                    Text(L("You have the latest version of GOGs.", "Bạn đang có phiên bản GOGs mới nhất."))
                case .offline:
                    Text(L("We couldn't reach the App Store. Check your connection and try again.",
                           "Không thể kết nối App Store. Hãy kiểm tra kết nối mạng và thử lại."))
                }
            }
        }
        .updatePrompt($foundUpdate)
        .preferredColorScheme(.dark)
    }

    /// Runs the same App Store check as launch, but reports every outcome.
    private func checkForUpdates() {
        Task {
            switch await updater.check() {
            case .available(let update): foundUpdate = update
            // Not listed yet means this build is the newest one that exists.
            case .upToDate, .notListed: updateMessage = .upToDate
            case .failed: updateMessage = .offline
            }
        }
    }

    /// Bridges a genre's weight (which has a controlled setter) to a Picker.
    private func weightBinding(_ genre: Genre) -> Binding<Int> {
        Binding(
            get: { settings.weight(for: genre) },
            set: { settings.setWeight($0, for: genre) }
        )
    }
}
