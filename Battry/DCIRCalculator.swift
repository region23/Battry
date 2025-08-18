import Foundation

/// Калькулятор внутреннего сопротивления батареи (DCIR)
/// Реализует алгоритм из рекомендаций эксперта для определения DCIR через пульс-тесты
struct DCIRCalculator {
    
    /// Точка измерения внутреннего сопротивления
    struct DCIRPoint: Codable, Equatable {
        /// Уровень заряда (%)
        let socPercent: Double
        /// Внутреннее сопротивление (мОм)
        let resistanceMohm: Double
        /// Время измерения
        let timestamp: Date
        /// Качество измерения (0-100%, где 100% - отличное)
        let quality: Double
        
        init(socPercent: Double, resistanceMohm: Double, timestamp: Date = Date(), quality: Double = 100.0) {
            self.socPercent = socPercent
            self.resistanceMohm = resistanceMohm
            self.timestamp = timestamp
            self.quality = quality
        }
    }
    
    /// Результат анализа DCIR
    struct DCIRAnalysis {
        /// Массив точек DCIR по SOC
        let dcirPoints: [DCIRPoint]
        /// Средний DCIR на 50% заряда (ключевая метрика)
        let dcirAt50Percent: Double?
        /// Средний DCIR на 20% заряда (критическая метрика)
        let dcirAt20Percent: Double?
        /// Тренд роста сопротивления (мОм/%SOC)
        let resistanceTrend: Double
        /// Оценка деградации (0-100, где 0 - критично)
        let degradationScore: Double
    }
    
    /// Оценивает DCIR на основе пульса нагрузки в выборках
    /// - Parameters:
    ///   - samples: Выборки батареи во время пульс-теста
    ///   - pulseStartIndex: Индекс начала пульса
    ///   - windowSeconds: Окно усреднения до и после пульса (сек)
    /// - Returns: Точка измерения DCIR или nil при недостатке данных
    static func estimateDCIR(
        samples: [BatteryReading],
        pulseStartIndex: Int,
        windowSeconds: Double = 3.0
    ) -> DCIRPoint? {
        guard pulseStartIndex > 0,
              pulseStartIndex < samples.count - 1,
              samples.count >= 6 else {
            return nil
        }
        
        let pulseTime = samples[pulseStartIndex].timestamp
        
        // Находим выборки до пульса (baseline)
        let prePulseSamples = samples.filter { sample in
            let timeDiff = pulseTime.timeIntervalSince(sample.timestamp)
            return timeDiff >= 0 && timeDiff <= windowSeconds
        }
        
        // Находим выборки после пульса (под нагрузкой)
        let postPulseSamples = samples.filter { sample in
            let timeDiff = sample.timestamp.timeIntervalSince(pulseTime)
            return timeDiff > 0 && timeDiff <= windowSeconds
        }
        
        guard prePulseSamples.count >= 2,
              postPulseSamples.count >= 2 else {
            return nil
        }
        
        // Усредняем показания до пульса
        let avgVoltageBeforeMv = prePulseSamples.map(\.voltage).reduce(0, +) / Double(prePulseSamples.count)
        let avgCurrentBeforeMa = prePulseSamples.map(\.amperage).reduce(0, +) / Double(prePulseSamples.count)
        let avgSocBefore = prePulseSamples.map { Double($0.percentage) }.reduce(0, +) / Double(prePulseSamples.count)
        
        // Усредняем показания после пульса
        let avgVoltageAfterMv = postPulseSamples.map(\.voltage).reduce(0, +) / Double(postPulseSamples.count)
        let avgCurrentAfterMa = postPulseSamples.map(\.amperage).reduce(0, +) / Double(postPulseSamples.count)
        let avgSocAfter = postPulseSamples.map { Double($0.percentage) }.reduce(0, +) / Double(postPulseSamples.count)
        
        // Вычисляем изменения напряжения и тока
        let deltaVoltageV = (avgVoltageBeforeMv - avgVoltageAfterMv) // падение напряжения под нагрузкой
        let deltaCurrentA = (avgCurrentAfterMa - avgCurrentBeforeMa) / 1000.0 // рост тока (в А)
        
        // Проверяем, что изменение тока достаточно значимо
        guard abs(deltaCurrentA) > 0.001 else { // минимум 1 мА изменения
            return nil
        }
        
        // Вычисляем внутреннее сопротивление по закону Ома: R = ΔV / ΔI
        let resistanceOhm = deltaVoltageV / deltaCurrentA
        let resistanceMohm = resistanceOhm * 1000.0
        
        // Убеждаемся, что сопротивление разумное (не отрицательное и не слишком большое)
        guard resistanceMohm > 0 && resistanceMohm < 10000 else {
            return nil
        }
        
        // Оцениваем качество измерения
        let currentChangePercent = abs(deltaCurrentA * 1000.0) // изменение тока в мА
        let voltageChangePercent = abs(deltaVoltageV * 1000.0) // изменение напряжения в мВ
        
        // Качество выше при больших изменениях тока/напряжения и стабильном SOC
        var quality = min(100.0, (currentChangePercent / 100.0) * (voltageChangePercent / 10.0) * 10.0)
        
        // Снижаем качество если SOC сильно изменился во время измерения
        let socChange = abs(avgSocAfter - avgSocBefore)
        if socChange > 1.0 {
            quality *= (1.0 - min(0.5, socChange / 10.0))
        }
        
        let avgSoc = (avgSocBefore + avgSocAfter) / 2.0
        
        return DCIRPoint(
            socPercent: avgSoc,
            resistanceMohm: resistanceMohm,
            timestamp: pulseTime,
            quality: max(0, quality)
        )
    }
    
    /// Анализирует массив точек DCIR для определения состояния батареи
    /// - Parameter dcirPoints: Точки измерения DCIR
    /// - Returns: Результаты анализа DCIR
    static func analyzeDCIR(dcirPoints: [DCIRPoint]) -> DCIRAnalysis {
        let sortedPoints = dcirPoints.sorted { $0.socPercent > $1.socPercent } // от высокого к низкому SOC
        
        // Найдем DCIR на ключевых уровнях заряда через интерполяцию
        let dcirAt50 = interpolateDCIR(points: sortedPoints, targetSOC: 50.0)
        let dcirAt20 = interpolateDCIR(points: sortedPoints, targetSOC: 20.0)
        
        // Рассчитаем тренд роста сопротивления с падением SOC
        let trend = calculateResistanceTrend(points: sortedPoints)
        
        // Оцениваем деградацию на основе абсолютных значений и тренда
        let degradationScore = calculateDegradationScore(
            dcirAt50: dcirAt50,
            dcirAt20: dcirAt20,
            trend: trend
        )
        
        return DCIRAnalysis(
            dcirPoints: sortedPoints,
            dcirAt50Percent: dcirAt50,
            dcirAt20Percent: dcirAt20,
            resistanceTrend: trend,
            degradationScore: degradationScore
        )
    }
    
    /// Интерполирует значение DCIR для заданного уровня SOC
    private static func interpolateDCIR(points: [DCIRPoint], targetSOC: Double) -> Double? {
        guard !points.isEmpty else { return nil }
        
        // Ищем ближайшие точки для интерполяции
        var lowerPoint: DCIRPoint?
        var upperPoint: DCIRPoint?
        
        for point in points {
            if point.socPercent <= targetSOC {
                if lowerPoint == nil || point.socPercent > lowerPoint!.socPercent {
                    lowerPoint = point
                }
            }
            if point.socPercent >= targetSOC {
                if upperPoint == nil || point.socPercent < upperPoint!.socPercent {
                    upperPoint = point
                }
            }
        }
        
        // Если есть точка ровно на целевом SOC
        if let lower = lowerPoint, lower.socPercent == targetSOC {
            return lower.resistanceMohm
        }
        if let upper = upperPoint, upper.socPercent == targetSOC {
            return upper.resistanceMohm
        }
        
        // Линейная интерполяция между соседними точками
        if let lower = lowerPoint, let upper = upperPoint, lower.socPercent != upper.socPercent {
            let socRange = upper.socPercent - lower.socPercent
            let resistanceRange = upper.resistanceMohm - lower.resistanceMohm
            let factor = (targetSOC - lower.socPercent) / socRange
            return lower.resistanceMohm + factor * resistanceRange
        }
        
        // Экстраполяция от ближайшей точки
        if let nearest = lowerPoint ?? upperPoint {
            return nearest.resistanceMohm
        }
        
        return nil
    }
    
    /// Вычисляет тренд изменения сопротивления с уровнем заряда
    private static func calculateResistanceTrend(points: [DCIRPoint]) -> Double {
        guard points.count >= 2 else { return 0.0 }
        
        // Простая линейная регрессия: DCIR = a * SOC + b
        let n = Double(points.count)
        let sumX = points.reduce(0) { $0 + $1.socPercent }
        let sumY = points.reduce(0) { $0 + $1.resistanceMohm }
        let sumXY = points.reduce(0) { $0 + $1.socPercent * $1.resistanceMohm }
        let sumXX = points.reduce(0) { $0 + $1.socPercent * $1.socPercent }
        
        let denominator = n * sumXX - sumX * sumX
        guard abs(denominator) > 1e-10 else { return 0.0 }
        
        let slope = (n * sumXY - sumX * sumY) / denominator
        return slope // мОм/%SOC (отрицательное значение означает рост сопротивления при падении SOC)
    }
    
    /// Вычисляет оценку деградации батареи на основе DCIR
    private static func calculateDegradationScore(dcirAt50: Double?, dcirAt20: Double?, trend: Double) -> Double {
        var score = 100.0
        
        // Штрафуем за высокие значения DCIR
        if let dcir50 = dcirAt50 {
            // Нормальный DCIR на 50% SOC: 50-150 мОм, критичный: >300 мОм
            if dcir50 > 300 {
                score -= 40
            } else if dcir50 > 200 {
                score -= 20
            } else if dcir50 > 150 {
                score -= 10
            }
        }
        
        if let dcir20 = dcirAt20 {
            // На низком SOC сопротивление обычно выше, но не должно быть катастрофическим
            if dcir20 > 500 {
                score -= 30
            } else if dcir20 > 350 {
                score -= 15
            } else if dcir20 > 250 {
                score -= 5
            }
        }
        
        // Штрафуем за резкий рост сопротивления с падением SOC
        let absTrend = abs(trend)
        if absTrend > 5.0 { // >5 мОм на процент SOC
            score -= 20
        } else if absTrend > 3.0 {
            score -= 10
        } else if absTrend > 2.0 {
            score -= 5
        }
        
        return max(0.0, min(100.0, score))
    }
}

/// Расширение для работы с DCIR в BatterySnapshot
extension BatterySnapshot {
    /// Добавляет удобную функцию для хранения дополнительных метрик
    var sohByEnergy: Double? {
        // Будет вычисляться в EnergyCalculator
        get { nil }
    }
}