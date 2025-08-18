import Foundation

/// Нормализатор температуры для корректного сравнения тестов батареи
/// Реализует температурную коррекцию согласно рекомендациям профессора
struct TemperatureNormalizer {
    
    /// Эталонная температура для нормализации (°C)
    static let referenceTemperature: Double = 25.0
    /// Максимальное число наблюдений, которые храним на диске для регрессии
    private static let maxStoredObservations: Int = 200
    
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
    private struct TemperatureCoefficients: Codable {
        /// Коэффициент для SOH (%/°C) - емкость слегка увеличивается при нагреве
        var sohPerDegree: Double = 0.15
        /// Коэффициент для DCIR (%/°C) - сопротивление уменьшается при нагреве
        var dcirPerDegree: Double = -2.5
        /// Минимально допустимая температура для коррекции
        var minTemperature: Double = 10.0
        /// Максимально допустимая температура для коррекции
        var maxTemperature: Double = 50.0
    }

    /// Текущие (самообучающиеся) коэффициенты
    private static var coefficients: TemperatureCoefficients = loadCoefficients()

    /// Наблюдение для самообучения
    private struct Observation: Codable {
        let timestamp: Date
        let temperature: Double
        let sohEnergy: Double
        let dcirAt50: Double?
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
        guard averageTemperature >= coefficients.minTemperature &&
              averageTemperature <= coefficients.maxTemperature else {
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
        let sohCorrection = temperatureDelta * coefficients.sohPerDegree
        let normalizedSOH = max(0, min(100, sohEnergy - sohCorrection))
        
        // Коррекция DCIR (если доступна)
        let normalizedDCIR: Double?
        if let dcir = dcirAt50 {
            let dcirCorrectionPercent = temperatureDelta * coefficients.dcirPerDegree / 100.0
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
    // MARK: - Self-learning storage paths
    private static var appSupportDir: URL {
        let fm = FileManager.default
        let base = try! fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("Battry", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private static var coeffsURL: URL { appSupportDir.appendingPathComponent("temperature_coeffs.json") }
    private static var observationsURL: URL { appSupportDir.appendingPathComponent("temperature_observations.json") }

    // MARK: - Load/Save
    private static func loadCoefficients() -> TemperatureCoefficients {
        if let data = try? Data(contentsOf: coeffsURL),
           let c = try? JSONDecoder().decode(TemperatureCoefficients.self, from: data) {
            return c
        }
        return TemperatureCoefficients()
    }
    private static func saveCoefficients(_ c: TemperatureCoefficients) {
        if let data = try? JSONEncoder().encode(c) {
            try? data.write(to: coeffsURL, options: .atomic)
        }
    }

    // MARK: - Public API for Settings UI
    /// Возвращает текущие коэффициенты температурной нормализации
    static func currentCoefficients() -> (sohPerDegree: Double, dcirPerDegree: Double, minTemperature: Double, maxTemperature: Double) {
        return (coefficients.sohPerDegree, coefficients.dcirPerDegree, coefficients.minTemperature, coefficients.maxTemperature)
    }
    /// Возвращает текущее число наблюдений в хранилище
    static func observationCount() -> Int {
        return loadObservations().count
    }
    /// Сбрасывает самообучающиеся коэффициенты и историю наблюдений
    static func resetSelfLearning() {
        let fm = FileManager.default
        try? fm.removeItem(at: coeffsURL)
        try? fm.removeItem(at: observationsURL)
        coefficients = TemperatureCoefficients()
        saveCoefficients(coefficients)
        saveObservations([])
    }
    private static func loadObservations() -> [Observation] {
        if let data = try? Data(contentsOf: observationsURL),
           let arr = try? JSONDecoder().decode([Observation].self, from: data) {
            return arr
        }
        return []
    }
    private static func saveObservations(_ arr: [Observation]) {
        if let data = try? JSONEncoder().encode(arr) {
            try? data.write(to: observationsURL, options: .atomic)
        }
    }

    /// Записывает наблюдение и, при наличии достаточного числа данных, перестраивает коэффициенты
    static func recordObservation(sohEnergy: Double, dcirAt50: Double?, temperature: Double) {
        guard sohEnergy > 0, temperature > -50, temperature < 100 else { return }
        var obs = loadObservations()
        obs.append(Observation(timestamp: Date(), temperature: temperature, sohEnergy: sohEnergy, dcirAt50: dcirAt50))
        if obs.count > maxStoredObservations { obs = Array(obs.suffix(maxStoredObservations)) }
        saveObservations(obs)
        // Регрессия при наличии > 8 наблюдений и хотя бы 4 с DCIR
        let dcirCount = obs.filter { $0.dcirAt50 != nil }.count
        if obs.count >= 8 && dcirCount >= 4 {
            regressCoefficients(using: obs)
        }
    }

    /// Выполняет линейную регрессию коэффициентов по истории наблюдений
    private static func regressCoefficients(using observations: [Observation]) {
        // SOH vs Temperature
        let xsS = observations.map { $0.temperature }
        let ysS = observations.map { $0.sohEnergy }
        if let slopeS = linearRegressionSlope(x: xsS, y: ysS) {
            // Ограничим разумными пределами: -1..1 %/°C
            coefficients.sohPerDegree = min(1.0, max(-1.0, slopeS))
        }
        // DCIR vs Temperature (в абсолютных мОм/°C)
        let dcirObs = observations.compactMap { o -> (Double, Double)? in
            guard let d = o.dcirAt50, d > 0 else { return nil }
            return (o.temperature, d)
        }
        if dcirObs.count >= 4 {
            let xsD = dcirObs.map { $0.0 }
            let ysD = dcirObs.map { $0.1 }
            if let slopeD = linearRegressionSlope(x: xsD, y: ysD) {
                let meanD = ysD.reduce(0, +) / Double(ysD.count)
                if meanD > 0 {
                    // Переводим в %/°C
                    let perDegree = (slopeD / meanD) * 100.0
                    // Ограничим в разумных пределах
                    coefficients.dcirPerDegree = min(10.0, max(-10.0, perDegree))
                }
            }
        }
        saveCoefficients(coefficients)
    }

    /// Возвращает наклон b линейной регрессии y = a + b x
    private static func linearRegressionSlope(x: [Double], y: [Double]) -> Double? {
        guard x.count == y.count, x.count >= 2 else { return nil }
        let n = Double(x.count)
        let sumX = x.reduce(0, +)
        let sumY = y.reduce(0, +)
        let sumXY = zip(x, y).map(*).reduce(0, +)
        let sumXX = x.map { $0 * $0 }.reduce(0, +)
        let denom = n * sumXX - sumX * sumX
        guard abs(denom) > 1e-12 else { return nil }
        let slope = (n * sumXY - sumX * sumY) / denom
        return slope
    }
    
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