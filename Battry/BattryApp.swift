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
        } label: {
            HStack(spacing: 6) {
                Image(systemName: getMenuBarIcon())
                    .symbolRenderingMode(.hierarchical)
                if shouldShowBatteryPercentage() {
                    // В строке меню показываем процент, если у устройства есть батарея
                    Text("\(battery.state.percentage)%")
                        .font(.system(size: 11))
                }
            }
            .task {
                // Стартуем периодический опрос и сбор истории при запуске
                battery.start()
                history.start()
                calibrator.bind(to: battery.publisher)
            }
        }
        .menuBarExtraStyle(.window)
        .onChange(of: battery.state) { oldValue, newValue in
            // На каждое обновление состояния добавляем точку в историю
            history.append(from: newValue)
        }
    }
    
    /// Выбирает символ для иконки в строке меню
    private func getMenuBarIcon() -> String {
        // Если устройство не имеет батареи, показываем иконку вилки
        if !battery.state.hasBattery {
            return "powerplug"
        }
        
        // Если устройство имеет батарею, используем обычную логику
        return battery.state.powerSource == .ac ? "powerplug" : battery.menuBarSymbol
    }
    
    /// Определяет, нужно ли показывать проценты рядом с иконкой
    private func shouldShowBatteryPercentage() -> Bool {
        // Показываем проценты только если устройство имеет батарею
        return battery.state.hasBattery
    }
}
