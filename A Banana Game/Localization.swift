//
//  Localization.swift
//  GOGs
//
//  A tiny central localization layer. We deliberately do NOT use a String Catalog:
//  this gives us (a) device-default language on first launch, (b) an instant in-app
//  toggle that overrides thereafter, and (c) the ability to localize the manual's
//  *data* strings — all with no project.pbxproj / knownRegions surgery.
//
//  Usage: wrap user-facing English literals with `L("English", "Tiếng Việt")`.
//  Because `Localization` is `@Observable` and the helper reads `.lang`, any SwiftUI
//  `body` that calls `L(...)` re-renders live when the language toggles.
//
//  Kept English on purpose (see CLAUDE.md): all game *titles*, the brand
//  ("GAME OF GAMES" / "GOGs"), and the word "UNROT" in the motto.
//

import SwiftUI

/// The languages the app can display. `en` is the base; `vi` is Vietnamese.
enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case en, vi

    var id: String { rawValue }

    /// The name shown in the Settings picker — each in its own language.
    var displayName: String {
        switch self {
        case .en: return "English"
        case .vi: return "Tiếng Việt"
        }
    }
}

/// Holds the current language and persists it. `@Observable` so reading `lang`
/// inside a SwiftUI body auto-tracks it and updates all visible text on toggle.
@Observable
final class Localization {
    static let shared = Localization()

    private static let key = "appLanguage"

    var lang: AppLanguage {
        didSet {
            guard lang != oldValue else { return }
            UserDefaults.standard.set(lang.rawValue, forKey: Self.key)
        }
    }

    private init() {
        // If the user has chosen a language before, honor it. Otherwise default to
        // the device language: Vietnamese if the top preferred language is Vietnamese,
        // else English.
        if let saved = UserDefaults.standard.string(forKey: Self.key),
           let lang = AppLanguage(rawValue: saved) {
            self.lang = lang
        } else if let first = Locale.preferredLanguages.first,
                  first.lowercased().hasPrefix("vi") {
            self.lang = .vi
        } else {
            self.lang = .en
        }
    }
}

/// Returns the string for the current language. Vietnamese falls back to English
/// when `vi` is empty (handy while translations are still being authored).
func L(_ en: String, _ vi: String) -> String {
    switch Localization.shared.lang {
    case .en: return en
    case .vi: return vi.isEmpty ? en : vi
    }
}
