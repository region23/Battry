import Foundation
import SwiftUI
import Combine

/// Состояние проверки обновлений
enum UpdateStatus: Equatable {
    case idle
    case checking
    case upToDate
    case updateAvailable(version: String, url: String)
    case error(String)
}

/// Класс для проверки обновлений через GitHub API
@MainActor
final class UpdateChecker: ObservableObject {
    @Published var status: UpdateStatus = .idle
    @Published var isDismissed = false
    
    private let repoURL = "https://api.github.com/repos/region23/Battry/releases/latest"
    private let checkInterval: TimeInterval = 24 * 60 * 60 // 24 часа
    private let i18n = Localization.shared
    
    init() {
        // Автоматическая проверка при запуске, если прошло больше суток
        Task {
            await checkForUpdatesIfNeeded()
        }
    }
    
    /// Проверяет обновления только если прошло достаточно времени
    func checkForUpdatesIfNeeded() async {
        let lastCheck = UserDefaults.standard.double(forKey: "lastUpdateCheck")
        let now = Date().timeIntervalSince1970
        
        // Проверяем только если прошло больше суток или это первый запуск
        if lastCheck == 0 || (now - lastCheck) >= checkInterval {
            await checkForUpdates()
        }
    }
    
    /// Принудительная проверка обновлений (вызывается из UI)
    func checkForUpdates() async {
        status = .checking
        
        do {
            guard let url = URL(string: repoURL) else {
                status = .error(i18n.t("update.error"))
                return
            }
            
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                status = .error(i18n.t("update.error.network"))
                return
            }
            
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latestVersion = cleanVersion(release.tagName)
            let currentVersion = cleanVersion(getCurrentVersion())
            
            // Сохраняем время последней проверки
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
            
            if isNewerVersion(latestVersion, than: currentVersion) {
                // Проверяем, не была ли эта версия уже отклонена пользователем
                let dismissedVersion = UserDefaults.standard.string(forKey: "dismissedUpdateVersion")
                if dismissedVersion != latestVersion {
                    status = .updateAvailable(version: latestVersion, url: release.htmlUrl)
                    isDismissed = false
                } else {
                    status = .upToDate
                    isDismissed = true
                }
            } else {
                status = .upToDate
            }
            
        } catch {
            print("Update check error: \(error)")
            
            // Более понятные сообщения об ошибках для пользователя
            let errorMessage: String
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet:
                    errorMessage = i18n.t("update.error.no.internet")
                case .cannotFindHost, .cannotConnectToHost:
                    errorMessage = i18n.t("update.error.cannot.reach.github")
                case .timedOut:
                    errorMessage = i18n.t("update.error.timeout")
                default:
                    errorMessage = i18n.t("update.error.network")
                }
            } else {
                errorMessage = i18n.t("update.error")
            }
            
            status = .error(errorMessage)
        }
    }
    
    /// Закрыть уведомление о доступном обновлении
    func dismissUpdate() {
        if case .updateAvailable(let version, _) = status {
            UserDefaults.standard.set(version, forKey: "dismissedUpdateVersion")
        }
        isDismissed = true
    }
    
    /// Получить текущую версию приложения
    private func getCurrentVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    /// Очистить версию от префиксов (v1.0.0 -> 1.0.0)
    private func cleanVersion(_ version: String) -> String {
        return version.hasPrefix("v") ? String(version.dropFirst()) : version
    }
    
    /// Сравнить версии (семантическое версионирование)
    private func isNewerVersion(_ newVersion: String, than currentVersion: String) -> Bool {
        let newComponents = newVersion.split(separator: ".").compactMap { Int($0) }
        let currentComponents = currentVersion.split(separator: ".").compactMap { Int($0) }
        
        let maxCount = max(newComponents.count, currentComponents.count)
        
        for i in 0..<maxCount {
            let newPart = i < newComponents.count ? newComponents[i] : 0
            let currentPart = i < currentComponents.count ? currentComponents[i] : 0
            
            if newPart > currentPart {
                return true
            } else if newPart < currentPart {
                return false
            }
        }
        
        return false
    }
}

/// Структура для парсинга GitHub Release API
private struct GitHubRelease: Codable {
    let tagName: String
    let htmlUrl: String
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
    }
}