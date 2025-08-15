import Foundation
import Combine

/// Поддерживаемые языки приложения
enum AppLanguage: String, CaseIterable, Identifiable {
    case ru = "ru"
    case en = "en"
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

@MainActor
final class Localization: ObservableObject {
    static let shared = Localization()

    /// Выбранный язык приложения. По умолчанию подстраивается под системный.
    @Published var language: AppLanguage = {
        if let raw = UserDefaults.standard.string(forKey: "app.language"), let l = AppLanguage(rawValue: raw) {
            return l
        }
        // Default to system; if it starts with ru, pick ru, else en
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("ru") ? .ru : .en
    }() {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "app.language") }
    }

    /// Перевод строки по ключу с учётом выбранного языка
    func t(_ key: String) -> String {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"), let b = Bundle(path: path) else {
            return NSLocalizedString(key, comment: "")
        }
        return NSLocalizedString(key, tableName: nil, bundle: b, value: key, comment: "")
    }
}


