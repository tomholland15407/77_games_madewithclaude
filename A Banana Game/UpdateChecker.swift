//
//  UpdateChecker.swift
//  GOGs
//
//  Real "Check for Updates": compares the installed CFBundleShortVersionString against the
//  App Store version from the iTunes Lookup API. At launch it checks silently and, if a newer
//  version exists, RootView shows `UpdatePromptView` once the splash is gone — on every cold
//  launch until the player updates (nothing is persisted, so "Later" only lasts this session).
//  SettingsView runs the same check on demand.
//
//  DEBUG only: launch with env var GOGS_FAKE_STORE_VERSION=<version> (Simulator:
//  SIMCTL_CHILD_GOGS_FAKE_STORE_VERSION) to fake the store answer without the network, and
//  optionally GOGS_FAKE_STORE_NOTES=<text> for the release notes.
//

import SwiftUI

/// A newer App Store build the player can move to.
struct AppUpdate: Equatable, Identifiable {
    let version: String
    let releaseNotes: String?
    let storeURL: URL
    var id: String { version }
}

enum UpdateCheckResult: Equatable {
    case available(AppUpdate)
    case upToDate
    /// The lookup found no store listing (not released yet, or not in this storefront).
    case notListed
    /// Offline, timed out, or an unreadable response.
    case failed
}

@MainActor
@Observable
final class UpdateChecker {
    static let bundleID = "com.nguyenviethungchu3.A-Banana-Game"

    /// True while a lookup is in flight (drives Settings' "Checking…").
    private(set) var isChecking = false
    /// Set by the launch check when an update exists; RootView shows the pop-up while non-nil
    /// and the feed pauses its game underneath. "Later"/"Update" clear it.
    var launchPrompt: AppUpdate?

    private var didLaunchCheck = false

    var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// The silent launch check: never surfaces errors, runs at most once per process.
    func checkAtLaunch() async {
        guard !didLaunchCheck else { return }
        didLaunchCheck = true
        if case .available(let update) = await check() {
            launchPrompt = update
        }
    }

    func check() async -> UpdateCheckResult {
        isChecking = true
        defer { isChecking = false }

        #if DEBUG
        if let fake = ProcessInfo.processInfo.environment["GOGS_FAKE_STORE_VERSION"], !fake.isEmpty {
            try? await Task.sleep(for: .seconds(0.6))   // let "Checking…" be seen
            let notes = ProcessInfo.processInfo.environment["GOGS_FAKE_STORE_NOTES"]
                ?? "• 2 new games\n• Smoother feed scrolling\n• Bug fixes"
            let item = LookupItem(version: fake, releaseNotes: notes,
                                  trackViewUrl: "https://apps.apple.com", minimumOsVersion: nil)
            return evaluate(item)
        }
        #endif

        // Ask the device's own storefront first (an app can be listed in only some
        // countries), then fall back to the default (US) storefront.
        let region = Locale.current.region?.identifier.lowercased()
        do {
            var item = try await lookup(country: region)
            if item == nil, region != nil { item = try await lookup(country: nil) }
            guard let item else { return .notListed }
            return evaluate(item)
        } catch {
            return .failed
        }
    }

    // MARK: - Lookup

    private struct LookupResponse: Decodable {
        let resultCount: Int
        let results: [LookupItem]
    }

    private struct LookupItem: Decodable {
        let version: String
        let releaseNotes: String?
        let trackViewUrl: String
        let minimumOsVersion: String?
    }

    private func lookup(country: String?) async throws -> LookupItem? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [URLQueryItem(name: "bundleId", value: Self.bundleID)]
        if let country { components.queryItems?.append(URLQueryItem(name: "country", value: country)) }

        var request = URLRequest(url: components.url!, timeoutInterval: 10)
        request.cachePolicy = .reloadIgnoringLocalCacheData   // a stale cached answer hides a release

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(LookupResponse.self, from: data)
        return decoded.resultCount > 0 ? decoded.results.first : nil
    }

    private func evaluate(_ item: LookupItem) -> UpdateCheckResult {
        guard SemanticVersion.isNewer(item.version, than: installedVersion),
              let url = URL(string: item.trackViewUrl) else { return .upToDate }

        // A build this device's iOS can't install isn't an update for this player.
        if let minOS = item.minimumOsVersion {
            let os = ProcessInfo.processInfo.operatingSystemVersion
            let current = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
            if SemanticVersion.isNewer(minOS, than: current) { return .upToDate }
        }

        let notes = item.releaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .available(AppUpdate(version: item.version,
                                    releaseNotes: (notes?.isEmpty ?? true) ? nil : notes,
                                    storeURL: url))
    }
}

/// Numeric dotted-version comparison: "1.10" > "1.9", "1.0" == "1.0.0". Each component uses its
/// leading digits only, so "2.1b3" reads as 2.1.
enum SemanticVersion {
    static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = components(a), y = components(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0
            let r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}

// MARK: - Pop-up

/// The black/banana update card. Shown over the feed at launch and from Settings.
struct UpdatePromptView: View {
    let update: AppUpdate
    let onUpdate: () -> Void
    let onLater: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
                .onTapGesture {}   // swallow taps so the feed underneath can't be played

            VStack(spacing: 16) {
                Text(L("Update available", "Có bản cập nhật"))
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text(L("Version \(update.version) is here with new games and features.",
                       "Phiên bản \(update.version) đã có, với trò chơi và tính năng mới."))
                    .font(.headline)
                    .foregroundStyle(BananaTheme.banana)
                    .multilineTextAlignment(.center)

                if let notes = update.releaseNotes {
                    let notesText = Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Group {
                        // Short notes sit at their natural height; long ones scroll in a capped box
                        // (a bare ScrollView would always grab the full cap).
                        if Self.isLong(notes) {
                            ScrollView { notesText }.frame(height: 180)
                        } else {
                            notesText
                        }
                    }
                    .padding(12)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }

                Button(action: onUpdate) {
                    Text(L("Update", "Cập nhật"))
                        .font(.headline.bold())
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(BananaTheme.banana, in: Capsule())
                }

                Button(action: onLater) {
                    Text(L("Later", "Để sau"))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.12), in: Capsule())
                }
            }
            .padding(24)
            .background(BananaTheme.background, in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(BananaTheme.banana.opacity(0.6), lineWidth: 1.5))
            .padding(.horizontal, 28)
            .frame(maxWidth: 440)
        }
        .transition(.opacity)
    }

    /// Rough visual line count (~38 chars per wrapped line in the card).
    private static func isLong(_ notes: String) -> Bool {
        let lines = notes.split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(0) { $0 + max(1, ($1.count + 37) / 38) }
        return lines > 8
    }
}

extension View {
    /// Overlays `UpdatePromptView` while `update` is non-nil. "Update" opens the store page;
    /// both buttons dismiss it.
    func updatePrompt(_ update: Binding<AppUpdate?>) -> some View {
        modifier(UpdatePromptModifier(update: update))
    }
}

private struct UpdatePromptModifier: ViewModifier {
    @Binding var update: AppUpdate?
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content.overlay {
            if let current = update {
                UpdatePromptView(
                    update: current,
                    onUpdate: {
                        openURL(current.storeURL)
                        withAnimation { update = nil }
                    },
                    onLater: { withAnimation { update = nil } }
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: update)
    }
}
