import SwiftUI
import Combine

/// Главная точка входа в приложение Battry
@main
struct BattryApp: App {
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
                    calibrator.bind(to: battery.publisher)
                    calibrator.attachHistory(history)
                }
        } label: {
            if let iconName = getMenuBarIcon() {
                Image(iconName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "battery.100")
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .menuBarExtraStyle(.window)
        .onChange(of: battery.state) { oldValue, newValue in
            // На каждое обновление состояния добавляем точку в историю
            history.append(from: newValue)
        }
    }
    
    /// Выбирает иконку для строки меню
    private func getMenuBarIcon() -> String? {
        // Используем кастомные иконки в зависимости от состояния зарядки
        return battery.state.powerSource == .ac ? "charge-icon" : "battery-icon"
    }
    
}
