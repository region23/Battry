import Foundation

/// Нормализатор температуры для корректного сравнения тестов батареи
/// Реализует температурную коррекцию согласно рекомендациям профессора
struct TemperatureNormalizer {
    
    /// Эталонная температура для нормализации (°C)
    static let referenceTemperature: Double = 25.0
    
    /// Результат температурной нормализации
    struct NormalizationResult {
        /// Нормализованное значение SOH
        let normalizedSOH: Double
        /// Нормализованное внутреннее сопротивление (мОм)
        let normalizedDCIR: Double?
        /// Коэффициент температурной коррекции
        let temperatureCoefficient: Double
        /// Средняя температура во время теста
        let averageTemperature: Double
        /// Качество нормализации (0-100)
        let normalizationQuality: Double
    }
    
    /// Температурные коэффициенты для различных метрик батареи
    private struct TemperatureCoefficients {
        /// Коэффициент для SOH (%/°C) - емкость слегка увеличивается при нагреве
        static let sohPerDegree: Double = 0.15
        /// Коэффициент для DCIR (%/°C) - сопротивление уменьшается при нагреве  
        static let dcirPerDegree: Double = -2.5
        /// Минимально допустимая температура для коррекции
        static let minTemperature: Double = 10.0
        /// Максимально допустимая температура для коррекции
        static let maxTemperature: Double = 50.0
    }
    
    /// Нормализует результаты теста к эталонной температуре
    /// - Parameters:
    ///   - sohEnergy: SOH по энергии (%)
    ///   - dcirAt50: Внутреннее сопротивление при 50% SOC (мОм)
    ///   - averageTemperature: Средняя температура во время теста (°C)
    /// - Returns: Результат нормализации
    static func normalize(
        sohEnergy: Double,
        dcirAt50: Double? = nil,
        averageTemperature: Double
    ) -> NormalizationResult {
        
        // Проверка входных данных
        guard averageTemperature >= TemperatureCoefficients.minTemperature &&
              averageTemperature <= TemperatureCoefficients.maxTemperature else {
            // Для экстремальных температур возвращаем исходные значения с низким качеством
            return NormalizationResult(
                normalizedSOH: sohEnergy,
                normalizedDCIR: dcirAt50,
                temperatureCoefficient: 1.0,
                averageTemperature: averageTemperature,
                normalizationQuality: 20.0
            )
        }
        
        // Температурная разность от эталона
        let temperatureDelta = averageTemperature - referenceTemperature
        
        // Коррекция SOH
        let sohCorrection = temperatureDelta * TemperatureCoefficients.sohPerDegree
        let normalizedSOH = max(0, min(100, sohEnergy - sohCorrection))
        
        // Коррекция DCIR (если доступна)
        let normalizedDCIR: Double?
        if let dcir = dcirAt50 {
            let dcirCorrectionPercent = temperatureDelta * TemperatureCoefficients.dcirPerDegree / 100.0
            let correctedDCIR = dcir * (1.0 - dcirCorrectionPercent)
            normalizedDCIR = max(10, correctedDCIR) // минимум 10 мОм
        } else {
            normalizedDCIR = nil
        }
        
        // Температурный коэффициент (для информации)
        let tempCoeff = 1.0 + (temperatureDelta * TemperatureCoefficients.sohPerDegree / 100.0)
        
        // Качество нормализации (выше при температуре ближе к эталонной)
        let tempDistance = abs(temperatureDelta)
        let quality = max(50, 100 - tempDistance * 3) // -3 балла за каждый градус отклонения
        
        return NormalizationResult(
            normalizedSOH: normalizedSOH,
            normalizedDCIR: normalizedDCIR,
            temperatureCoefficient: tempCoeff,
            averageTemperature: averageTemperature,
            normalizationQuality: quality
        )
    }
    
    /// Сравнивает два теста с учетом температурной нормализации
    /// - Parameters:
    ///   - test1: Данные первого теста
    ///   - test2: Данные второго теста
    /// - Returns: Сравнительный анализ с температурной коррекцией
    static func compareTests(
        test1: (sohEnergy: Double, dcir: Double?, temperature: Double),
        test2: (sohEnergy: Double, dcir: Double?, temperature: Double)
    ) -> TestComparison {
        
        let normalized1 = normalize(
            sohEnergy: test1.sohEnergy,
            dcirAt50: test1.dcir,
            averageTemperature: test1.temperature
        )
        
        let normalized2 = normalize(
            sohEnergy: test2.sohEnergy,
            dcirAt50: test2.dcir,
            averageTemperature: test2.temperature
        )
        
        // Изменения после нормализации
        let sohChange = normalized2.normalizedSOH - normalized1.normalizedSOH
        
        let dcirChange: Double?
        if let dcir1 = normalized1.normalizedDCIR, let dcir2 = normalized2.normalizedDCIR {
            dcirChange = ((dcir2 - dcir1) / dcir1) * 100.0 // процентное изменение
        } else {
            dcirChange = nil
        }
        
        return TestComparison(
            sohChangePercent: sohChange,
            dcirChangePercent: dcirChange,
            temperatureDifference: test2.temperature - test1.temperature,
            normalizationQuality: min(normalized1.normalizationQuality, normalized2.normalizationQuality)
        )
    }
    
    /// Результат сравнения двух тестов
    struct TestComparison {
        /// Изменение SOH (процентные пункты)
        let sohChangePercent: Double
        /// Изменение DCIR (процентное изменение)
        let dcirChangePercent: Double?
        /// Разность температур между тестами
        let temperatureDifference: Double
        /// Качество нормализации (0-100)
        let normalizationQuality: Double
        
        /// Тренд деградации
        var degradationTrend: DegradationTrend {
            if sohChangePercent < -2.0 {
                return .accelerating
            } else if sohChangePercent < -0.5 {
                return .normal
            } else if sohChangePercent > 1.0 {
                return .improving // возможно, ошибка измерения
            } else {
                return .stable
            }
        }
        
        /// Рекомендация на основе сравнения
        var recommendation: String {
            switch degradationTrend {
            case .accelerating:
                return "Accelerated degradation detected. Consider replacement planning."
            case .normal:
                return "Normal degradation rate. Continue monitoring."
            case .stable:
                return "Battery condition is stable."
            case .improving:
                return "Apparent improvement may indicate measurement variation."
            }
        }
    }
    
    enum DegradationTrend {
        case accelerating
        case normal
        case stable
        case improving
    }
    
    /// Оценивает необходимость температурной коррекции
    /// - Parameter temperatureRange: Диапазон температур в тестах
    /// - Returns: Рекомендация по коррекции
    static func shouldNormalize(temperatureRange: ClosedRange<Double>) -> Bool {
        let range = temperatureRange.upperBound - temperatureRange.lowerBound
        // Нормализация рекомендуется при разнице температур >2°C
        return range > 2.0
    }
    
    /// Качество температурных условий для тестирования
    /// - Parameter temperature: Температура во время теста
    /// - Returns: Оценка условий (0-100)
    static func temperatureQuality(_ temperature: Double) -> Double {
        let optimalRange: ClosedRange<Double> = 20.0...30.0
        
        if optimalRange.contains(temperature) {
            return 100.0
        } else if (15.0...35.0).contains(temperature) {
            let distance = min(abs(temperature - 20.0), abs(temperature - 30.0))
            return max(70, 100 - distance * 6)
        } else if (10.0...40.0).contains(temperature) {
            let distance = min(abs(temperature - 15.0), abs(temperature - 35.0))
            return max(40, 70 - distance * 6)
        } else {
            return 20.0 // экстремальные условия
        }
    }
}

/// Расширение для работы с историческими данными
extension TemperatureNormalizer {
    
    /// Анализирует температурные тренды в истории тестов
    /// - Parameter testHistory: История тестов с температурными данными
    /// - Returns: Температурный анализ
    static func analyzeTrends(testHistory: [(date: Date, soh: Double, dcir: Double?, temp: Double)]) -> TemperatureTrendAnalysis {
        guard testHistory.count >= 2 else {
            return TemperatureTrendAnalysis(
                averageTemperature: 25.0,
                temperatureVariation: 0.0,
                seasonalEffect: 0.0,
                recommendNormalization: false
            )
        }
        
        let temperatures = testHistory.map { $0.temp }
        let avgTemp = temperatures.reduce(0, +) / Double(temperatures.count)
        
        // Вариация температуры
        let tempVariance = temperatures.reduce(0) { sum, temp in
            sum + pow(temp - avgTemp, 2)
        } / Double(temperatures.count)
        let tempVariation = sqrt(tempVariance)
        
        // Оценка сезонного эффекта (упрощенно)
        let tempRange = temperatures.max()! - temperatures.min()!
        let seasonalEffect = tempRange > 10 ? tempRange / 10.0 : 0.0
        
        // Рекомендация нормализации
        let recommendNorm = tempVariation > 3.0 || tempRange > 8.0
        
        return TemperatureTrendAnalysis(
            averageTemperature: avgTemp,
            temperatureVariation: tempVariation,
            seasonalEffect: seasonalEffect,
            recommendNormalization: recommendNorm
        )
    }
    
    struct TemperatureTrendAnalysis {
        let averageTemperature: Double
        let temperatureVariation: Double
        let seasonalEffect: Double
        let recommendNormalization: Bool
        
        var qualityDescription: String {
            if temperatureVariation < 2.0 {
                return "Consistent test conditions"
            } else if temperatureVariation < 5.0 {
                return "Moderate temperature variation"
            } else {
                return "High temperature variation - normalization recommended"
            }
        }
    }
}