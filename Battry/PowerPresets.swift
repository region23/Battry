import Foundation
import SwiftUI

/// Пресеты мощности на основе рекомендаций профессора для стандартизации тестов
/// Использует C-rate (отношение тока разряда к номинальной емкости)
enum PowerPreset: String, CaseIterable, Identifiable {
    case light = "0.1C"    // ~5W для веб-серфинга, чтения
    case medium = "0.2C"   // ~10W для офисной работы
    case heavy = "0.3C"    // ~15W для разработки, видео
    
    var id: String { rawValue }
    
    /// Множитель C-rate для расчета мощности
    var cRate: Double {
        switch self {
        case .light: return 0.1
        case .medium: return 0.2
        case .heavy: return 0.3
        }
    }
    
    /// Описание пресета для UI
    var description: String {
        switch self {
        case .light: return "Quick test (web browsing, reading) - 2 pulses per SOC level"
        case .medium: return "Standard test (office work, development) - 3 pulses per SOC level"
        case .heavy: return "Intensive test (gaming, video editing) - 2 longer pulses per SOC level"
        }
    }
    
    /// Ключ локализации
    var localizationKey: String {
        switch self {
        case .light: return "preset.light"
        case .medium: return "preset.medium" 
        case .heavy: return "preset.heavy"
        }
    }
    
    /// Иконка для UI (соответствует дизайну из обзора)
    var icon: String {
        switch self {
        case .light: return "doc.text"             // Веб, документы
        case .medium: return "square.stack.3d.up"  // Приложения 
        case .heavy: return "gamecontroller"       // Игры, видео
        }
    }
    
    /// Цвет фона для UI (соответствует дизайну из обзора)
    var backgroundColor: Color {
        switch self {
        case .light: return .blue.opacity(0.1)
        case .medium: return .orange.opacity(0.1) 
        case .heavy: return .red.opacity(0.1)
        }
    }
}

/// Калькулятор мощности на основе характеристик батареи
struct PowerCalculator {
    
    /// Вычисляет целевую мощность для пресета на основе характеристик батареи
    /// - Parameters:
    ///   - preset: Пресет мощности
    ///   - designCapacityMah: Паспортная емкость батареи в мАч
    ///   - nominalVoltage: Номинальное напряжение батареи (по умолчанию 11.1В для MacBook)
    /// - Returns: Целевая мощность в Ваттах
    static func targetPower(
        for preset: PowerPreset,
        designCapacityMah: Int,
        nominalVoltage: Double = 11.1
    ) -> Double {
        guard designCapacityMah > 0 else { return 5.0 } // fallback
        
        // Энергоемкость батареи в Втч
        let energyCapacityWh = Double(designCapacityMah) * nominalVoltage / 1000.0
        
        // Целевая мощность = C-rate × Энергоемкость
        let targetPowerW = preset.cRate * energyCapacityWh
        
        // Ограничиваем разумными пределами
        return max(1.0, min(50.0, targetPowerW))
    }
    
    /// Вычисляет целевую мощность для всех пресетов
    static func allTargetPowers(
        designCapacityMah: Int,
        nominalVoltage: Double = 11.1
    ) -> [PowerPreset: Double] {
        var result: [PowerPreset: Double] = [:]
        
        for preset in PowerPreset.allCases {
            result[preset] = targetPower(
                for: preset,
                designCapacityMah: designCapacityMah,
                nominalVoltage: nominalVoltage
            )
        }
        
        return result
    }
    
    /// Определяет оптимальный пресет на основе текущего потребления мощности
    /// - Parameter currentPower: Текущая мощность потребления в Ваттах
    /// - Parameter designCapacityMah: Паспортная емкость батареи
    /// - Returns: Подходящий пресет или nil если мощность слишком низкая/высокая
    static func suggestPreset(
        for currentPower: Double,
        designCapacityMah: Int
    ) -> PowerPreset? {
        guard currentPower > 0.5 else { return nil }
        
        let presetPowers = allTargetPowers(designCapacityMah: designCapacityMah)
        
        // Находим ближайший пресет по мощности
        var bestPreset: PowerPreset?
        var bestDistance = Double.infinity
        
        for (preset, targetPower) in presetPowers {
            let distance = abs(currentPower - targetPower)
            if distance < bestDistance {
                bestDistance = distance
                bestPreset = preset
            }
        }
        
        return bestPreset
    }
    
    /// Оценивает эквивалентный C-rate для произвольной мощности
    /// - Parameters:
    ///   - power: Мощность в Ваттах
    ///   - designCapacityMah: Паспортная емкость батареи
    ///   - nominalVoltage: Номинальное напряжение
    /// - Returns: C-rate (например, 0.15 для мощности между 0.1C и 0.2C)
    static func equivalentCRate(
        power: Double,
        designCapacityMah: Int,
        nominalVoltage: Double = 11.1
    ) -> Double {
        guard designCapacityMah > 0, power > 0 else { return 0 }
        
        let energyCapacityWh = Double(designCapacityMah) * nominalVoltage / 1000.0
        return power / energyCapacityWh
    }
    
    /// Форматирует мощность с C-rate для отображения
    /// - Parameters:
    ///   - power: Мощность в Ваттах
    ///   - designCapacityMah: Паспортная емкость батареи
    /// - Returns: Строка вида "8.5W (0.17C)"
    static func formatPowerWithCRate(
        power: Double,
        designCapacityMah: Int
    ) -> String {
        let cRate = equivalentCRate(power: power, designCapacityMah: designCapacityMah)
        return String(format: "%.1fW (%.2fC)", power, cRate)
    }
}

/// Расширение BatterySnapshot для работы с пресетами
extension BatterySnapshot {
    
    /// Целевые мощности для всех пресетов на основе характеристик этой батареи
    var presetTargetPowers: [PowerPreset: Double] {
        return PowerCalculator.allTargetPowers(designCapacityMah: designCapacity)
    }
    
    /// Предлагаемый пресет на основе текущего потребления
    var suggestedPreset: PowerPreset? {
        return PowerCalculator.suggestPreset(
            for: abs(power),
            designCapacityMah: designCapacity
        )
    }
    
    /// Текущий эквивалентный C-rate
    var currentCRate: Double {
        return PowerCalculator.equivalentCRate(
            power: abs(power),
            designCapacityMah: designCapacity
        )
    }
    
    /// Форматированная строка текущей мощности с C-rate
    var formattedPowerWithCRate: String {
        return PowerCalculator.formatPowerWithCRate(
            power: abs(power),
            designCapacityMah: designCapacity
        )
    }
}