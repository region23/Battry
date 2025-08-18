import Foundation
import Combine

/// Статус здоровья параметра батареи
enum HealthStatus: CaseIterable {
    case excellent  // отлично
    case normal     // нормально
    case acceptable // приемлемо
    case poor       // плохо
    case afterTest  // после теста
    
    /// Цвет для визуального отображения статуса
    var color: String {
        switch self {
        case .excellent: return "green"
        case .normal: return "blue"
        case .acceptable: return "orange" 
        case .poor: return "red"
        case .afterTest: return "gray"
        }
    }
    
    /// Локализационный ключ для текста
    var localizationKey: String {
        switch self {
        case .excellent: return "health.status.excellent"
        case .normal: return "health.status.normal"
        case .acceptable: return "health.status.acceptable"
        case .poor: return "health.status.poor"
        case .afterTest: return "after.test"
        }
    }
}

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
    
    /// Оценивает средний разряд (%/ч) за последний час
    func estimateDischargePerHour1h(history: [BatteryReading]) -> Double {
        return estimateDischargePerHour(history: history.filter { 
            $0.timestamp >= Date().addingTimeInterval(-3600) 
        })
    }
    
    /// Оценивает средний разряд (%/ч) за последние 24 часа
    func estimateDischargePerHour24h(history: [BatteryReading]) -> Double {
        return estimateDischargePerHour(history: history.filter { 
            $0.timestamp >= Date().addingTimeInterval(-24 * 3600) 
        })
    }
    
    /// Оценивает средний разряд (%/ч) за последние 7 дней
    func estimateDischargePerHour7d(history: [BatteryReading]) -> Double {
        return estimateDischargePerHour(history: history.filter { 
            $0.timestamp >= Date().addingTimeInterval(-7 * 24 * 3600) 
        })
    }
    
    /// Проверяет достаточность данных для расчета разряда за 1 час
    func hasEnoughData1h(history: [BatteryReading]) -> Bool {
        let discharging = history.filter { 
            !$0.isCharging && $0.timestamp >= Date().addingTimeInterval(-3600) 
        }
        guard discharging.count >= 2, let first = discharging.first, let last = discharging.last else { return false }
        let span = last.timestamp.timeIntervalSince(first.timestamp)
        let discharged = first.percentage - last.percentage
        // Требуем минимум 30 минут данных И хотя бы 1% разряда
        return span >= 1800 && discharged >= 1
    }
    
    /// Проверяет достаточность данных для расчета разряда за 24 часа
    func hasEnoughData24h(history: [BatteryReading]) -> Bool {
        let discharging = history.filter { 
            !$0.isCharging && $0.timestamp >= Date().addingTimeInterval(-24 * 3600) 
        }
        guard discharging.count >= 4, let first = discharging.first, let last = discharging.last else { return false }
        let span = last.timestamp.timeIntervalSince(first.timestamp)
        let discharged = first.percentage - last.percentage
        // Требуем минимум 3 часа данных за последние 24 часа И хотя бы 2% разряда
        return span >= 3 * 3600 && discharged >= 2
    }
    
    /// Проверяет достаточность данных для расчета разряда за 7 дней
    func hasEnoughData7d(history: [BatteryReading]) -> Bool {
        let discharging = history.filter { 
            !$0.isCharging && $0.timestamp >= Date().addingTimeInterval(-7 * 24 * 3600) 
        }
        guard discharging.count >= 6, let first = discharging.first, let last = discharging.last else { return false }
        let span = last.timestamp.timeIntervalSince(first.timestamp)
        let discharged = first.percentage - last.percentage
        // Требуем минимум 24 часа данных за последние 7 дней И хотя бы 5% разряда
        return span >= 24 * 3600 && discharged >= 5
    }

    /// Простая медианная фильтрация последовательности процентов (окно 3)
    private func medianFilter3(_ values: [Int]) -> [Int] {
        guard values.count >= 3 else { return values }
        var out = values
        for i in 1..<(values.count-1) {
            let a = values[i-1], b = values[i], c = values[i+1]
            let sorted = [a,b,c].sorted()
            out[i] = sorted[1]
        }
        return out
    }

    /// Линейная регрессия по точкам без зарядки для оценки тренда разряда (со сглаживанием)
    private func regressionDischargePerHour(history: [BatteryReading]) -> Double {
        let pointsRaw = history.filter { !$0.isCharging }
        let points: [BatteryReading]
        if pointsRaw.count >= 3 {
            // применим легкое сглаживание по процентам
            let smoothedPct = medianFilter3(pointsRaw.map { $0.percentage })
            points = zip(pointsRaw.indices, pointsRaw).map { (idx, r) in
                var rr = r
                rr.percentage = smoothedPct[idx]
                return rr
            }
        } else {
            points = pointsRaw
        }
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

    /// Подсчёт микро‑просадок: падение ≥2% за ≤120 секунд без зарядки (со сглаживанием окна 3)
    private func countMicroDrops(history: [BatteryReading]) -> Int {
        guard history.count >= 2 else { return 0 }
        // сгладим проценты для устойчивости к одиночным выбросам
        let smoothedPct = medianFilter3(history.map { $0.percentage })
        var cnt = 0
        for i in 1..<history.count {
            let prev = history[i-1]
            let cur = history[i]
            let dt = cur.timestamp.timeIntervalSince(prev.timestamp)
            let d = smoothedPct[i] - smoothedPct[i-1]
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
    
    // MARK: - Health Status Evaluation Functions
    
    /// Оценивает состояние износа батареи
    func evaluateWearStatus(wearPercent: Double) -> HealthStatus {
        switch wearPercent {
        case ..<5: return .excellent
        case 5..<15: return .normal
        case 15..<25: return .acceptable
        default: return .poor
        }
    }
    
    /// Оценивает состояние циклов зарядки
    func evaluateCyclesStatus(cycles: Int) -> HealthStatus {
        switch cycles {
        case ..<200: return .excellent
        case 200..<400: return .normal
        case 400..<600: return .acceptable
        default: return .poor
        }
    }
    
    /// Оценивает состояние температуры
    func evaluateTemperatureStatus(temperature: Double) -> HealthStatus {
        switch temperature {
        case ..<30: return .excellent
        case 30..<35: return .normal
        case 35..<40: return .acceptable
        default: return .poor
        }
    }
    
    /// Оценивает состояние скорости разряда
    func evaluateDischargeStatus(ratePerHour: Double) -> HealthStatus {
        switch ratePerHour {
        case ..<5: return .excellent
        case 5..<10: return .normal
        case 10..<20: return .acceptable
        default: return .poor
        }
    }
    
    /// Оценивает состояние емкости относительно паспортной
    func evaluateCapacityStatus(maxCapacity: Int, designCapacity: Int) -> HealthStatus {
        guard designCapacity > 0 else { return .excellent }
        let ratio = Double(maxCapacity) / Double(designCapacity) * 100
        switch ratio {
        case 95...: return .excellent
        case 85..<95: return .normal
        case 75..<85: return .acceptable
        default: return .poor
        }
    }
}
