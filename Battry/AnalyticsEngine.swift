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
    
    // Новые энергетические и DCIR метрики
    /// SOH по энергии (0-100%)
    var sohEnergy: Double = 100.0
    /// Средняя мощность за анализируемый период (Вт)
    var averagePower: Double = 0
    /// DCIR на 50% заряда (мОм)
    var dcirAt50Percent: Double? = nil
    /// DCIR на 20% заряда (мОм)  
    var dcirAt20Percent: Double? = nil
    /// Индекс качества OCV колена (0-100)
    var kneeIndex: Double = 100.0
    /// Позиция колена OCV кривой (% SOC)
    var kneeSOC: Double? = nil
    
    // Температурная нормализация (согласно рекомендациям профессора)
    /// Средняя температура во время анализа (°C)
    var averageTemperature: Double = 25.0
    /// Температурно-нормализованный SOH (%)
    var temperatureNormalizedSOH: Double = 100.0
    /// Температурно-нормализованный DCIR (мОм) 
    var temperatureNormalizedDCIR: Double? = nil
    /// Качество температурной нормализации (0-100)
    var temperatureNormalizationQuality: Double = 100.0
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

        // Энергетический анализ
        if snapshot.designCapacity > 0 {
            let designEnergyWh = EnergyCalculator.designEnergyCapacity(fromCapacityMah: snapshot.designCapacity)
            if let energyAnalysis = EnergyCalculator.analyzeEnergyPerformance(samples: history, designCapacityWh: designEnergyWh) {
                result.sohEnergy = energyAnalysis.sohEnergy
                result.averagePower = energyAnalysis.averagePower
            }
        }
        
        // Микро‑просадки
        let micro = countMicroDrops(history: history)
        result.microDropEvents = micro
        
        // Пытаемся получить DCIR из истории (если есть пульс-тесты)
        let dcirPoints = extractDCIRFromHistory(history: history)
        if !dcirPoints.isEmpty {
            let dcirAnalysis = DCIRCalculator.analyzeDCIR(dcirPoints: dcirPoints)
            result.dcirAt50Percent = dcirAnalysis.dcirAt50Percent
            result.dcirAt20Percent = dcirAnalysis.dcirAt20Percent
            
            // OCV анализ
            let ocvAnalyzer = OCVAnalyzer(dcirPoints: dcirPoints)
            let ocvAnalysis = ocvAnalyzer.analyzeOCV(from: history)
            result.kneeIndex = ocvAnalysis.kneeIndex
            result.kneeSOC = ocvAnalysis.kneeSOC
        }
        
        // Температурная нормализация (согласно рекомендациям профессора)
        let temperatures = history.compactMap { $0.temperature }.filter { $0 > 0 }
        let avgTemperature = temperatures.isEmpty ? 25.0 : temperatures.reduce(0, +) / Double(temperatures.count)
        
        // Композитный health score по формуле эксперта
        result.healthScore = Int(calculateCompositeHealthScore(
            sohEnergy: result.sohEnergy,
            sohCapacity: Double(100 - Int(snapshot.wearPercent)),
            dcirAt50: result.dcirAt50Percent,
            dcirAt20: result.dcirAt20Percent,
            kneeIndex: result.kneeIndex,
            microDrops: micro,
            avgTemperature: avgTemperature,
            cycleCount: snapshot.cycleCount
        ))

        // Аномалии
        var anomalies: [String] = []
        let wear = snapshot.wearPercent
        if snapshot.cycleCount > 800 { anomalies.append("Высокое число циклов (\(snapshot.cycleCount)).") }
        if wear > 20 { anomalies.append(String(format: "Сильный износ аккумулятора (%.0f%%).", wear)) }
        if result.averagePower > 25 { anomalies.append(String(format: "Высокое энергопотребление (%.1f Вт).", result.averagePower)) }
        if micro >= 3 { anomalies.append("Замечены частые микро‑просадки заряда (\(micro)).") }
        if let kneeSOC = result.kneeSOC, kneeSOC > 40 { anomalies.append("Раннее колено OCV кривой (\(String(format: "%.0f", kneeSOC))% SOC).") }
        result.anomalies = anomalies

        // Рекомендация на основе композитного скора
        if result.healthScore < 50 {
            result.recommendation = "Требуется замена батареи в ближайшее время."
        } else if result.healthScore < 70 {
            result.recommendation = "Планируйте замену батареи. Избегайте высоких нагрузок."
        } else if result.healthScore < 85 {
            result.recommendation = "Состояние приемлемое. Мониторьте регулярно."
        } else {
            result.recommendation = "Батарея в отличном состоянии."
        }
        result.averageTemperature = avgTemperature
        
        if result.sohEnergy > 0 {
            let tempNormalization = TemperatureNormalizer.normalize(
                sohEnergy: result.sohEnergy,
                dcirAt50: result.dcirAt50Percent,
                averageTemperature: result.averageTemperature
            )
            
            result.temperatureNormalizedSOH = tempNormalization.normalizedSOH
            result.temperatureNormalizedDCIR = tempNormalization.normalizedDCIR
            result.temperatureNormalizationQuality = tempNormalization.normalizationQuality
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
    
    // MARK: - Composite Health Score Calculation
    
    /// Вычисляет композитный health score по формуле эксперта
    /// Формула: 40% SOH_energy + 25% DCIR + 20% SOH_capacity + 10% стабильность + 5% температура
    private func calculateCompositeHealthScore(
        sohEnergy: Double,
        sohCapacity: Double,
        dcirAt50: Double?,
        dcirAt20: Double?,
        kneeIndex: Double,
        microDrops: Int,
        avgTemperature: Double,
        cycleCount: Int
    ) -> Double {
        
        // 40% - SOH по энергии
        let energyScore = sohEnergy * 0.4
        
        // 25% - DCIR оценка
        var dcirScore: Double = 100.0
        if let dcir50 = dcirAt50 {
            // Нормальный DCIR: 50-150 мОм, плохой: >300 мОм
            if dcir50 > 300 {
                dcirScore = max(0, 100 - (dcir50 - 150) / 5)
            } else if dcir50 > 150 {
                dcirScore = 100 - (dcir50 - 150) / 10
            }
        }
        if let dcir20 = dcirAt20 {
            var dcir20Score: Double = 100.0
            if dcir20 > 500 {
                dcir20Score = max(0, 100 - (dcir20 - 250) / 8)
            } else if dcir20 > 250 {
                dcir20Score = 100 - (dcir20 - 250) / 15
            }
            dcirScore = (dcirScore + dcir20Score) / 2.0
        }
        
        // 20% - SOH по емкости 
        let capacityScore = sohCapacity * 0.2
        
        // 10% - стабильность (микро-дропы)
        let stabilityScore: Double
        if microDrops == 0 {
            stabilityScore = 100.0
        } else if microDrops <= 2 {
            stabilityScore = 80.0
        } else if microDrops <= 5 {
            stabilityScore = 50.0
        } else {
            stabilityScore = max(0, 50 - Double(microDrops - 5) * 10)
        }
        
        // 5% - температурная терпимость
        let temperatureScore: Double
        if avgTemperature <= 30 {
            temperatureScore = 100.0
        } else if avgTemperature <= 35 {
            temperatureScore = 90.0
        } else if avgTemperature <= 40 {
            temperatureScore = 70.0
        } else {
            temperatureScore = max(0, 70 - (avgTemperature - 40) * 5)
        }
        
        // Дополнительные штрафы за циклы и колено
        var cyclesPenalty: Double = 0
        if cycleCount > 800 {
            cyclesPenalty = min(15, Double(cycleCount - 800) / 50)
        } else if cycleCount > 600 {
            cyclesPenalty = Double(cycleCount - 600) / 100
        }
        
        let kneePenalty = max(0, (100 - kneeIndex) / 10)
        
        let finalScore = energyScore + dcirScore * 0.25 + capacityScore + stabilityScore * 0.1 + temperatureScore * 0.05 - cyclesPenalty - kneePenalty
        
        return max(0, min(100, finalScore))
    }
    
    /// Извлекает DCIR точки из истории (простейшая реализация)
    /// В реальности это будет работать только если в истории есть данные от пульс-тестов
    private func extractDCIRFromHistory(history: [BatteryReading]) -> [DCIRCalculator.DCIRPoint] {
        // Пока возвращаем пустой массив - DCIR будет работать только через QuickHealthTest
        // В будущем можно добавить логику поиска резких изменений тока в истории
        return []
    }
    
    // MARK: - Public Health Score API
    
    /// Получает актуальный Health Score для UI (0-100)
    func getHealthScore(history: [BatteryReading], snapshot: BatterySnapshot) -> Int {
        // Если есть кешированный анализ, используем его
        if let cached = lastAnalysis {
            return cached.healthScore
        }
        
        // Иначе быстрый расчет только Health Score без полного анализа
        let sohCapacity = Double(100 - Int(snapshot.wearPercent))
        let simpleScore = calculateCompositeHealthScore(
            sohEnergy: snapshot.designCapacity > 0 ? Double(snapshot.maxCapacity) / Double(snapshot.designCapacity) * 100 : 100,
            sohCapacity: sohCapacity,
            dcirAt50: nil,
            dcirAt20: nil,
            kneeIndex: 100.0,
            microDrops: 0,
            avgTemperature: snapshot.temperature,
            cycleCount: snapshot.cycleCount
        )
        
        return Int(simpleScore)
    }
    
    /// Получает статус здоровья на основе Health Score
    func getHealthStatusFromScore(_ score: Int) -> HealthStatus {
        switch score {
        case 85...100: return .excellent
        case 70..<85: return .normal
        case 55..<70: return .acceptable
        default: return .poor
        }
    }
    
    /// Получает среднюю мощность за последние 15 минут
    func getAveragePowerLast15Min(history: [BatteryReading]) -> Double {
        let now = Date()
        let cutoff = now.addingTimeInterval(-15 * 60) // 15 минут назад
        let recent = history.filter { $0.timestamp >= cutoff && abs($0.power) > 0.1 }
        
        guard !recent.isEmpty else { return 0 }
        
        return recent.map { abs($0.power) }.reduce(0, +) / Double(recent.count)
    }
}
