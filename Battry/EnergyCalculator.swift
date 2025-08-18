import Foundation

/// Калькулятор энергии и энергетических метрик батареи
/// Реализует рекомендации эксперта по измерению реально отданной энергии
struct EnergyCalculator {
    
    /// Результат энергетического анализа
    struct EnergyAnalysis {
        /// Энергия, отданная батареей (Вт⋅ч)
        let energyDelivered: Double
        /// SOH по энергии (0-100%)
        let sohEnergy: Double
        /// Средняя мощность за период (Вт)
        let averagePower: Double
        /// Продолжительность измерения (часы)
        let durationHours: Double
    }
    
    /// Интегрирует энергию по выборкам батареи методом трапеций
    /// - Parameter samples: Упорядоченные по времени выборки
    /// - Returns: Энергия в Вт⋅ч (всегда положительная)
    static func integrateEnergy(samples: [BatteryReading]) -> Double {
        guard samples.count >= 2 else { return 0.0 }
        
        var totalJoules: Double = 0.0
        
        for i in 1..<samples.count {
            let prev = samples[i-1]
            let curr = samples[i]
            
            // Временной интервал в секундах
            let deltaTime = curr.timestamp.timeIntervalSince(prev.timestamp)
            guard deltaTime > 0 else { continue }
            
            // Мощность в Вт (V*I с конверсией из мА)
            let powerPrev = prev.voltage * (prev.amperage / 1000.0)
            let powerCurr = curr.voltage * (curr.amperage / 1000.0)
            
            // Средняя мощность за интервал (метод трапеций)
            let avgPower = (powerPrev + powerCurr) / 2.0
            
            // Энергия в джоулях (Вт⋅с)
            totalJoules += avgPower * deltaTime
        }
        
        // Конвертируем в Вт⋅ч и возвращаем абсолютное значение
        // (при разряде ток отрицательный, поэтому энергия получается отрицательной)
        return abs(totalJoules) / 3600.0
    }
    
    /// Анализирует энергетические характеристики батареи за заданный период
    /// - Parameters:
    ///   - samples: Выборки батареи за период измерения
    ///   - designCapacityWh: Паспортная энергоемкость батареи (Вт⋅ч)
    /// - Returns: Результаты энергетического анализа
    static func analyzeEnergyPerformance(
        samples: [BatteryReading],
        designCapacityWh: Double? = nil
    ) -> EnergyAnalysis? {
        guard samples.count >= 2,
              let firstSample = samples.first,
              let lastSample = samples.last else {
            return nil
        }
        
        let energyDelivered = integrateEnergy(samples: samples)
        let durationHours = lastSample.timestamp.timeIntervalSince(firstSample.timestamp) / 3600.0
        let averagePower = durationHours > 0 ? energyDelivered / durationHours : 0.0
        
        // Вычисляем SOH по энергии, если известна паспортная емкость
        var sohEnergy: Double = 100.0
        if let designWh = designCapacityWh, designWh > 0 {
            // Нормализуем на полный разряд (примерно)
            let socChange = abs(Double(firstSample.percentage - lastSample.percentage))
            if socChange > 0 {
                let estimatedFullEnergy = energyDelivered * (100.0 / socChange)
                sohEnergy = min(100.0, max(0.0, (estimatedFullEnergy / designWh) * 100.0))
            }
        }
        
        return EnergyAnalysis(
            energyDelivered: energyDelivered,
            sohEnergy: sohEnergy,
            averagePower: averagePower,
            durationHours: durationHours
        )
    }
    
    /// Вычисляет паспартную энергоемкость батареи (Вт⋅ч) из емкости (мА⋅ч) и напряжения
    /// - Parameters:
    ///   - designCapacityMah: Паспортная емкость в мА⋅ч
    ///   - nominalVoltage: Номинальное напряжение в В (по умолчанию 11.1В для MacBook)
    /// - Returns: Паспортная энергоемкость в Вт⋅ч
    static func designEnergyCapacity(fromCapacityMah designCapacityMah: Int, nominalVoltage: Double = 11.1) -> Double {
        return Double(designCapacityMah) * nominalVoltage / 1000.0
    }
    
    /// Быстрая оценка средней мощности за последний период
    /// - Parameters:
    ///   - samples: Выборки батареи
    ///   - periodMinutes: Период для анализа в минутах
    /// - Returns: Средняя мощность в Вт
    static func averagePowerOverPeriod(samples: [BatteryReading], periodMinutes: Int = 15) -> Double {
        let cutoffTime = Date().addingTimeInterval(-Double(periodMinutes * 60))
        let recentSamples = samples.filter { $0.timestamp >= cutoffTime }
        
        guard !recentSamples.isEmpty else { return 0 }
        
        let totalPower = recentSamples.reduce(0.0) { sum, sample in
            sum + abs(sample.power)
        }
        
        return totalPower / Double(recentSamples.count)
    }
    
    /// Оценивает оставшееся время работы на основе текущей мощности и емкости
    /// - Parameters:
    ///   - currentPercentage: Текущий заряд (%)
    ///   - currentPower: Текущая мощность потребления (Вт)
    ///   - maxCapacityMah: Максимальная емкость батареи (мА⋅ч)
    ///   - nominalVoltage: Номинальное напряжение (В)
    /// - Returns: Оценка времени в часах
    static func estimatedTimeRemaining(
        currentPercentage: Int,
        currentPower: Double,
        maxCapacityMah: Int,
        nominalVoltage: Double = 11.1
    ) -> Double? {
        guard currentPower > 0, currentPercentage > 0, maxCapacityMah > 0 else { return nil }
        
        let remainingEnergyWh = Double(maxCapacityMah) * nominalVoltage * Double(currentPercentage) / (1000.0 * 100.0)
        return remainingEnergyWh / currentPower
    }
}