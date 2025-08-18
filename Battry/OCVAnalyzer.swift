import Foundation

/// Анализатор напряжения холостого хода (OCV) батареи
/// Реконструирует OCV кривые и определяет точки деградации согласно рекомендациям эксперта
struct OCVAnalyzer {
    
    /// Точка OCV кривой
    struct OCVPoint: Codable, Equatable {
        let socPercent: Double
        let ocvVoltage: Double // Напряжение холостого хода в В
        let timestamp: Date
        
        init(socPercent: Double, ocvVoltage: Double, timestamp: Date = Date()) {
            self.socPercent = socPercent
            self.ocvVoltage = ocvVoltage
            self.timestamp = timestamp
        }
    }
    
    /// Результат анализа OCV кривой
    struct OCVAnalysis {
        /// Реконструированная OCV кривая
        let ocvCurve: [OCVPoint]
        /// SOC точки "колена" кривой (%)
        let kneeSOC: Double?
        /// Индекс качества колена (0-100, где 100 - отлично)
        let kneeIndex: Double
        /// Средний градиент напряжения (мВ/% SOC)
        let voltageGradient: Double
        /// Признак ранней деградации
        let earlyDegradation: Bool
    }
    
    /// Интерполятор для получения DCIR по SOC
    private let dcirPoints: [DCIRCalculator.DCIRPoint]
    
    init(dcirPoints: [DCIRCalculator.DCIRPoint] = []) {
        self.dcirPoints = dcirPoints.sorted { $0.socPercent < $1.socPercent }
    }

    /// Вычисляет среднее напряжение холостого хода V_OC по данным выборок
    /// - Parameters:
    ///   - samples: Исторические выборки батареи
    ///   - dcirPoints: Точки DCIR для более точной реконструкции OCV (опционально)
    ///   - binSize: Размер бинов по SOC для усреднения
    /// - Returns: Среднее значение V_OC в Вольтах или nil, если данных недостаточно
    static func averageVOC(from samples: [BatteryReading], dcirPoints: [DCIRCalculator.DCIRPoint] = [], binSize: Double = 2.0) -> Double? {
        guard !samples.isEmpty else { return nil }
        let analyzer = OCVAnalyzer(dcirPoints: dcirPoints)
        let ocvCurve = analyzer.buildOCVCurve(from: samples, binSize: binSize)
        guard !ocvCurve.isEmpty else { return nil }
        let sum = ocvCurve.reduce(0.0) { $0 + $1.ocvVoltage }
        return sum / Double(ocvCurve.count)
    }
    
    /// Интерполирует значение DCIR для заданного SOC
    func interpolatedDCIR(at soc: Double) -> Double? {
        guard !dcirPoints.isEmpty else { return nil }
        
        // Если SOC за пределами диапазона, используем ближайшее значение
        if soc <= dcirPoints.first!.socPercent {
            return dcirPoints.first!.resistanceMohm
        }
        if soc >= dcirPoints.last!.socPercent {
            return dcirPoints.last!.resistanceMohm
        }
        
        // Поиск соседних точек для интерполяции
        for i in 1..<dcirPoints.count {
            let lower = dcirPoints[i-1]
            let upper = dcirPoints[i]
            
            if soc >= lower.socPercent && soc <= upper.socPercent {
                let range = upper.socPercent - lower.socPercent
                guard range > 0 else { return lower.resistanceMohm }
                
                let factor = (soc - lower.socPercent) / range
                return lower.resistanceMohm + factor * (upper.resistanceMohm - lower.resistanceMohm)
            }
        }
        
        return dcirPoints.last?.resistanceMohm
    }
    
    /// Реконструирует напряжение холостого хода с компенсацией внутреннего сопротивления
    /// - Parameter sample: Выборка батареи
    /// - Returns: Реконструированное OCV или nil если недостаточно данных
    func reconstructOCV(from sample: BatteryReading) -> Double? {
        guard let dcirMohm = interpolatedDCIR(at: Double(sample.percentage)) else {
            // Если нет данных DCIR, используем типовое значение
            return sample.voltage
        }
        
        // Компенсируем падение напряжения: V_OC = V_measured + I × R
        let dcirOhm = dcirMohm / 1000.0 // мОм -> Ом
        let currentA = sample.amperage / 1000.0 // мА -> А
        
        // При разряде ток отрицательный, поэтому добавляем I×R чтобы получить более высокое OCV
        let compensatedVoltage = sample.voltage + (currentA * dcirOhm)
        
        return compensatedVoltage
    }
    
    /// Строит OCV кривую из выборок батареи
    /// - Parameters:
    ///   - samples: Выборки батареи
    ///   - binSize: Размер бина для группировки по SOC (%)
    /// - Returns: Массив точек OCV кривой
    func buildOCVCurve(from samples: [BatteryReading], binSize: Double = 2.0) -> [OCVPoint] {
        guard !samples.isEmpty else { return [] }
        
        // Группируем выборки по SOC bins
        var bins: [Double: (voltageSum: Double, count: Int, avgTimestamp: TimeInterval)] = [:]
        
        for sample in samples {
            guard let ocv = reconstructOCV(from: sample) else { continue }
            
            let binCenter = floor(Double(sample.percentage) / binSize) * binSize + binSize / 2
            
            if var existing = bins[binCenter] {
                existing.voltageSum += ocv
                existing.count += 1
                existing.avgTimestamp += sample.timestamp.timeIntervalSince1970
                bins[binCenter] = existing
            } else {
                bins[binCenter] = (ocv, 1, sample.timestamp.timeIntervalSince1970)
            }
        }
        
        // Преобразуем bins в массив точек OCV
        var ocvPoints: [OCVPoint] = []
        
        for (socBin, data) in bins {
            let avgVoltage = data.voltageSum / Double(data.count)
            let avgTimestamp = Date(timeIntervalSince1970: data.avgTimestamp / Double(data.count))
            
            ocvPoints.append(OCVPoint(
                socPercent: socBin,
                ocvVoltage: avgVoltage,
                timestamp: avgTimestamp
            ))
        }
        
        return ocvPoints.sorted { $0.socPercent < $1.socPercent }
    }
    
    /// Находит точку "колена" в OCV кривой методом кусочно-линейной аппроксимации
    /// - Parameter ocvCurve: OCV кривая
    /// - Returns: SOC точки колена или nil если не найдено
    static func findKneeSOC(in ocvCurve: [OCVPoint]) -> Double? {
        guard ocvCurve.count >= 8 else { return nil }
        
        let sortedCurve = ocvCurve.sorted { $0.socPercent < $1.socPercent }
        
        var bestKneeSOC: Double?
        var bestError = Double.infinity
        
        // Ищем оптимальную точку разделения на два линейных сегмента
        for i in 3..<(sortedCurve.count - 3) {
            let kneeSOC = sortedCurve[i].socPercent
            
            // Пропускаем точки на краях (не характерные для деградации)
            guard kneeSOC >= 10 && kneeSOC <= 90 else { continue }
            
            // Левый сегмент (низкие SOC)
            let leftSegment = Array(sortedCurve[0...i])
            let leftFit = linearFit(points: leftSegment)
            
            // Правый сегмент (высокие SOC)
            let rightSegment = Array(sortedCurve[i...])
            let rightFit = linearFit(points: rightSegment)
            
            // Суммарная ошибка аппроксимации + штраф за различие наклонов
            let totalError = leftFit.sse + rightFit.sse + 0.001 * abs(leftFit.slope - rightFit.slope)
            
            if totalError < bestError {
                bestError = totalError
                bestKneeSOC = kneeSOC
            }
        }
        
        return bestKneeSOC
    }
    
    /// Выполняет линейную регрессию для массива OCV точек
    private static func linearFit(points: [OCVPoint]) -> (slope: Double, intercept: Double, sse: Double) {
        guard points.count >= 2 else { return (0, 0, Double.infinity) }
        
        let n = Double(points.count)
        let sumX = points.reduce(0) { $0 + $1.socPercent }
        let sumY = points.reduce(0) { $0 + $1.ocvVoltage }
        let sumXY = points.reduce(0) { $0 + $1.socPercent * $1.ocvVoltage }
        let sumXX = points.reduce(0) { $0 + $1.socPercent * $1.socPercent }
        
        let denominator = n * sumXX - sumX * sumX
        guard abs(denominator) > 1e-12 else { return (0, sumY / n, Double.infinity) }
        
        let slope = (n * sumXY - sumX * sumY) / denominator
        let intercept = (sumY - slope * sumX) / n
        
        // Вычисляем сумму квадратов остатков
        let sse = points.reduce(0) { sum, point in
            let predicted = slope * point.socPercent + intercept
            let residual = point.ocvVoltage - predicted
            return sum + residual * residual
        }
        
        return (slope, intercept, sse)
    }
    
    /// Вычисляет индекс качества колена (0-100)
    static func calculateKneeIndex(kneeSOC: Double?) -> Double {
        guard let kneeSOC = kneeSOC else { return 0 }
        
        // Хорошее колено должно быть в диапазоне 20-30% SOC
        // Колено на 50%+ SOC указывает на серьезную деградацию
        let normalizedKnee = max(0, min(1, (kneeSOC - 20.0) / 30.0))
        return (1.0 - normalizedKnee) * 100.0
    }
    
    /// Анализирует OCV кривую и возвращает полный анализ
    /// - Parameter samples: Выборки батареи
    /// - Returns: Результаты анализа OCV
    func analyzeOCV(from samples: [BatteryReading]) -> OCVAnalysis {
        let ocvCurve = buildOCVCurve(from: samples, binSize: 2.0)
        let kneeSOC = Self.findKneeSOC(in: ocvCurve)
        let kneeIndex = Self.calculateKneeIndex(kneeSOC: kneeSOC)
        
        // Вычисляем средний градиент напряжения
        let voltageGradient = calculateVoltageGradient(ocvCurve: ocvCurve)
        
        // Определяем признаки ранней деградации
        let earlyDegradation = (kneeSOC ?? 25.0) > 40.0 || kneeIndex < 50.0
        
        return OCVAnalysis(
            ocvCurve: ocvCurve,
            kneeSOC: kneeSOC,
            kneeIndex: kneeIndex,
            voltageGradient: voltageGradient,
            earlyDegradation: earlyDegradation
        )
    }
    
    /// Вычисляет средний градиент напряжения по кривой OCV
    private func calculateVoltageGradient(ocvCurve: [OCVPoint]) -> Double {
        guard ocvCurve.count >= 2 else { return 0 }
        
        let sortedCurve = ocvCurve.sorted { $0.socPercent < $1.socPercent }
        guard let first = sortedCurve.first, let last = sortedCurve.last else { return 0 }
        
        let voltageRange = (last.ocvVoltage - first.ocvVoltage) * 1000.0 // В -> мВ
        let socRange = last.socPercent - first.socPercent
        
        guard socRange > 0 else { return 0 }
        return voltageRange / socRange // мВ/%SOC
    }
}