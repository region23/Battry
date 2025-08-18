import Foundation
import Combine
import SwiftUI

/// ViewModel: периодически читает состояние батареи и публикует его для UI/аналитики
@MainActor
final class BatteryViewModel: ObservableObject {
    /// Снимок текущего состояния батареи
    @Published var state: BatterySnapshot = BatterySnapshot()

    /// Интервал опроса в секундах
    var refreshInterval: TimeInterval = 30
    /// Ускоренный интервал опроса для состояния ожидания
    var fastRefreshInterval: TimeInterval = 5
    private var timer: AnyCancellable?
    private var isFastMode: Bool = false

    /// Паблишер, на который подписываются другие компоненты (например, калибровка)
    let publisher = PassthroughSubject<BatterySnapshot, Never>()

    /// Символ для иконки в строке меню
    var menuBarSymbol: String {
        symbolForMenu(percent: state.percentage, charging: state.isCharging)
    }

    /// Символ для крупной иконки в заголовке
    var symbolForCurrentLevel: String {
        symbolForIcon(percent: state.percentage, charging: state.isCharging)
    }

    /// Цвет, отражающий состояние заряда/зарядки/температуры
    var tintColor: Color {
        if state.isCharging { return .green }
        switch state.percentage {
        case 0..<20: return .red
        case 20..<50: return .orange
        default: return .accentColor
        }
    }

    /// Текст с временем до разряда/зарядки по данным системы
    var timeRemainingText: String {
        let L = Localization.shared
        if let tte = state.timeToEmptyMin, state.powerSource == .battery {
            return String(format: L.t("time.remaining"), format(minutes: tte))
        }
        if let ttf = state.timeToFullMin, state.isCharging {
            return String(format: L.t("time.to.full"), format(minutes: ttf))
        }
        return ""
    }

    /// Запускает периодический опрос системы
    func start() {
        refresh()
        startTimer()
    }
    
    /// Переключает в быстрый режим опроса (для ожидания калибровки)
    func enableFastMode() {
        guard !isFastMode else { return }
        isFastMode = true
        restartTimer()
    }
    
    /// Переключает в обычный режим опроса
    func disableFastMode() {
        guard isFastMode else { return }
        isFastMode = false
        restartTimer()
    }
    
    private func startTimer() {
        let interval = isFastMode ? fastRefreshInterval : refreshInterval
        timer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }
    
    private func restartTimer() {
        timer?.cancel()
        startTimer()
    }

    /// Останавливает опрос
    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Считывает текущее состояние батареи и публикует его
    func refresh() {
        let snap = BatteryService.read()
        self.state = snap
        publisher.send(snap)
    }

    /// Форматирует минуты как HH:MM
    private func format(minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return String(format: "%d:%02d", h, m)
    }

    /// Подбор символа для строки меню (агрегированные шаги)
    private func symbolForMenu(percent: Int, charging: Bool) -> String {
        if charging { return "battery.100.bolt" }
        switch percent {
        case 0..<10: return "battery.0"
        case 10..<25: return "battery.25"
        case 25..<50: return "battery.50"
        case 50..<75: return "battery.75"
        default: return "battery.100"
        }
    }

    /// Символ для иконки в UI (пока совпадает с меню)
    private func symbolForIcon(percent: Int, charging: Bool) -> String {
        symbolForMenu(percent: percent, charging: charging)
    }
}

extension BatterySnapshot {
    /// Процент износа (0–100), где 0 — новая, 100 — полностью изношена
    var wearPercent: Double {
        guard designCapacity > 0 && maxCapacity > 0 else { return 0 }
        return max(0, (1.0 - Double(maxCapacity) / Double(designCapacity)) * 100.0)
    }
    
    /// Признак наличия батареи в устройстве
    var hasBattery: Bool {
        // Проверяем, есть ли у устройства батарея
        return BatteryService.hasBattery()
    }
}
