import SwiftUI
import Combine
import AppKit

/// Главная точка входа в приложение Battry
@main
struct BattryApp: App {
    
    init() {
        // Проверяем и завершаем другие экземпляры приложения при запуске
        terminateOtherInstances()
    }
    /// ViewModel с текущим состоянием батареи
    @StateObject private var battery = BatteryViewModel()
    /// Хранилище истории измерений для графиков и аналитики
    @StateObject private var history = HistoryStore()
    /// Движок аналитики (оценки, тренды, рекомендации)
    @StateObject private var analytics = AnalyticsEngine()
    /// Движок калибровки/теста автономности
    @StateObject private var calibrator = CalibrationEngine()
    /// Локализация (переключение языка в UI)
    @StateObject private var i18n = Localization.shared

    var body: some Scene {
        MenuBarExtra {
            // Основное содержимое окна из строки меню
            MenuContent(battery: battery, history: history, analytics: analytics, calibrator: calibrator)
                .frame(width: 460)
                .task {
                    // Стартуем периодический опрос и сбор истории при запуске
                    battery.start()
                    history.start()
                    calibrator.bind(to: battery.publisher, viewModel: battery)
                    calibrator.attachHistory(history)
                }
        } label: {
            if battery.state.powerSource == .ac {
                Image(systemName: "battery.100.bolt")
                    .symbolRenderingMode(.hierarchical)
            } else {
                Image(systemName: battery.menuBarSymbol)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .menuBarExtraStyle(.window)
        .onChange(of: battery.state) { oldValue, newValue in
            // На каждое обновление состояния добавляем точку в историю
            history.append(from: newValue)
        }
    }
    
    
    /// Завершает другие запущенные экземпляры приложения
    private func terminateOtherInstances() {
        let bundleID = Bundle.main.bundleIdentifier ?? "region23.Battry"
        let runningApps = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            // Ищем другие экземпляры нашего приложения (не текущий процесс)
            if app.bundleIdentifier == bundleID && app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                app.terminate()
            }
        }
    }
}

