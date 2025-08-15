import Foundation
import Combine

/// Результаты анализа состояния батареи
struct BatteryAnalysis: Equatable {
    /// Средний разряд в %/ч по выборке
    var avgDischargePerHour: Double = 0
    /// Тренд разряда (по линейной регрессии) в %/ч
    var trendDischargePerHour: Double = 0
    /// Оценка автономности от 100 до 0 в часах
    var estimatedRuntimeFrom100To0Hours: Double = 0
    /// Список обнаруженных аномалий
    var anomalies: [String] = []
    /// Интегральная оценка здоровья (0–100)
    var healthScore: Int = 100
    /// Итоговая рекомендация пользователю
    var recommendation: String = "Замена не требуется"
    /// Количество микро‑просадок (быстрых падений процента)
    var microDropEvents: Int = 0
}

@MainActor
final class AnalyticsEngine: ObservableObject {
    /// Флаг "идёт сессия" (для реактивного UI)
    @Published private(set) var sessionActive = false
    /// Последний вычисленный анализ
    @Published private(set) var lastAnalysis: BatteryAnalysis?

    let objectWillChange = PassthroughSubject<Void, Never>()
    
    // Make the objectWillChange publisher available to the ObservableObject protocol
    var willChange: AnyPublisher<Void, Never> {
        objectWillChange.eraseToAnyPublisher()
    }

    /// Устанавливает статус активности сессии и оповещает подписчиков
    func setSessionActive(_ active: Bool) {
        sessionActive = active
        objectWillChange.send()
    }

    /// Оценивает средний разряд (%/ч) на интервале без зарядки
    func estimateDischargePerHour(history: [BatteryReading]) -> Double {
        let discharging = history.filter { !$0.isCharging }
        guard discharging.count >= 2,
              let first = discharging.first,
              let last = discharging.last,
              first != last else { return 0 }
        let dt = last.timestamp.timeIntervalSince(first.timestamp) / 3600.0
        guard dt > 0 else { return 0 }
        let dPercent = Double(first.percentage - last.percentage)
        return max(0, dPercent / dt)
    }

    /// Линейная регрессия по точкам без зарядки для оценки тренда разряда
    private func regressionDischargePerHour(history: [BatteryReading]) -> Double {
        let points = history.filter { !$0.isCharging }
        guard points.count >= 4 else { return 0 }
        let t0 = points.first!.timestamp.timeIntervalSince1970
        var xs: [Double] = []
        var ys: [Double] = []
        for r in points {
            xs.append((r.timestamp.timeIntervalSince1970 - t0) / 3600.0) // hours
            ys.append(Double(r.percentage))
        }
        let n = Double(xs.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).map(*).reduce(0, +)
        let sumXX = xs.map { $0*$0 }.reduce(0, +)
        let denom = (n * sumXX - sumX * sumX)
        guard denom != 0 else { return 0 }
        let slope = (n * sumXY - sumX * sumY) / denom // % per hour change
        return max(0, -slope) // discharge rate is negative slope
    }

    /// Подсчёт микро‑просадок: падение ≥2% за ≤120 секунд без зарядки
    private func countMicroDrops(history: [BatteryReading]) -> Int {
        guard history.count >= 2 else { return 0 }
        var cnt = 0
        for i in 1..<history.count {
            let prev = history[i-1]
            let cur = history[i]
            let dt = cur.timestamp.timeIntervalSince(prev.timestamp)
            let d = cur.percentage - prev.percentage
            if !cur.isCharging && !prev.isCharging && dt <= 120 && d <= -2 {
                cnt += 1
            }
        }
        return cnt
    }

    /// Строит итоговую аналитику по истории и текущему снимку
    func analyze(history: [BatteryReading], snapshot: BatterySnapshot) -> BatteryAnalysis {
        var result = BatteryAnalysis()

        result.avgDischargePerHour = estimateDischargePerHour(history: history)
        result.trendDischargePerHour = regressionDischargePerHour(history: history)

        if result.trendDischargePerHour > 0 {
            result.estimatedRuntimeFrom100To0Hours = 100.0 / result.trendDischargePerHour
        } else if result.avgDischargePerHour > 0 {
            result.estimatedRuntimeFrom100To0Hours = 100.0 / result.avgDischargePerHour
        }

        let wear = snapshot.wearPercent
        var health = 100 - Int(round(wear * 1.2)) // усиленно штрафуем износ

        if snapshot.cycleCount > 500 {
            health -= min(30, (snapshot.cycleCount - 500) / 10)
        }

        // Температура за последний час
        let hour = history.filter { $0.timestamp >= Date().addingTimeInterval(-3600) }
        let avgTemp = hour.map(\.temperature).reduce(0, +) / Double(max(1, hour.count))
        if avgTemp > 40 { health -= 10 }

        // Микро‑просадки
        let micro = countMicroDrops(history: history)
        result.microDropEvents = micro
        if micro >= 1 { health -= min(20, micro * 2) }

        // Границы
        result.healthScore = max(0, min(100, health))

        // Аномалии
        var anomalies: [String] = []
        if snapshot.cycleCount > 800 { anomalies.append("Высокое число циклов (\(snapshot.cycleCount)).") }
        if wear > 20 { anomalies.append(String(format: "Сильный износ аккумулятора (%.0f%%).", wear)) }
        if avgTemp > 45 { anomalies.append("Повышенная температура за последний час (\(String(format: "%.1f", avgTemp))°C).") }
        if micro >= 3 { anomalies.append("Замечены частые микро‑просадки заряда (\(micro)).") }
        result.anomalies = anomalies

        // Рекомендация
        if result.healthScore < 40 || wear > 40 || micro >= 3 {
            result.recommendation = "Рекомендуется замена в ближайшее время."
        } else if result.healthScore < 60 || wear > 25 {
            result.recommendation = "Понаблюдайте: возможна деградация, снизьте тепловую нагрузку."
        } else {
            result.recommendation = "Состояние хорошее. Замена не требуется."
        }

        lastAnalysis = result
        objectWillChange.send()
        return result
    }
}
