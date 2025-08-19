import Charts
import SwiftUI

/// Диапазоны временных окон для графиков
enum Timeframe: String, CaseIterable, Identifiable {
    case session = "timeframe.session"
    case h24 = "timeframe.h24"
    case d7 = "timeframe.d7"
    case d30 = "timeframe.d30"

    var id: String { rawValue }

    func localizedTitle(using localization: Localization) -> String {
        localization.t(rawValue)
    }
}

/// Панель графиков по истории батареи
struct ChartsPanel: View {
    @ObservedObject var history: HistoryStore
    @ObservedObject var calibrator: CalibrationEngine
    let snapshot: BatterySnapshot
    @ObservedObject private var i18n = Localization.shared
    @State private var timeframe: Timeframe = .h24
    @State private var didSetInitialTimeframe: Bool = false
    @State private var showPercent: Bool = true
    @State private var showTemp: Bool = false
    @State private var showVolt: Bool = false
    @State private var showDrain: Bool = false
    @State private var showPower: Bool = false
    @State private var showHealthScore: Bool = false
    @State private var showOCV: Bool = false
    @State private var showDCIR: Bool = false

    private func data() -> [BatteryReading] {
        switch timeframe {
        case .session:
            // Активный сеанс: с начала до текущего времени; иначе последний завершённый
            switch calibrator.state {
            case .running(let start, _):
                return history.between(from: start, to: Date())
            default:
                if let last = calibrator.lastResult {
                    return history.between(
                        from: last.startedAt,
                        to: last.finishedAt
                    )
                } else {
                    return []
                }
            }
        case .h24: return history.recent(hours: 24)
        case .d7: return history.recent(days: 7)
        case .d30: return history.recent(days: 30)
        }
    }

    private var sessionAvailable: Bool {
        if case .running = calibrator.state { return true }
        return calibrator.lastResult != nil
    }

    private var availableTimeframes: [Timeframe] {
        var t: [Timeframe] = [.h24, .d7, .d30]
        if sessionAvailable { t.insert(.session, at: 0) }
        return t
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Объединенная компактная секция управления
            VStack(alignment: .leading, spacing: 12) {
                // Период времени
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    ForEach(availableTimeframes) { timeframe in
                        PeriodButton(
                            title: timeframe.localizedTitle(using: i18n),
                            isSelected: self.timeframe == timeframe
                        ) {
                            self.timeframe = timeframe
                        }
                    }
                    Spacer()
                }

                // Метрики в одну строку
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.accentColor)

                    MetricToggleButton(
                        title: i18n.t("trends.series.charge"),
                        color: .blue,
                        isSelected: showPercent
                    ) { showPercent.toggle() }

                    MetricToggleButton(
                        title: i18n.t("trends.series.temperature"),
                        color: .red,
                        isSelected: showTemp
                    ) { showTemp.toggle() }

                    MetricToggleButton(
                        title: i18n.t("trends.series.voltage"),
                        color: .green,
                        isSelected: showVolt
                    ) { showVolt.toggle() }

                    MetricToggleButton(
                        title: i18n.t("trends.series.power"),
                        color: .orange,
                        isSelected: showPower
                    ) { showPower.toggle() }

                    MetricToggleButton(
                        title: i18n.t("trends.series.health.score"),
                        color: .purple,
                        isSelected: showHealthScore
                    ) { showHealthScore.toggle() }

                    MetricToggleButton(
                        title: "OCV",
                        color: .teal,
                        isSelected: showOCV
                    ) { showOCV.toggle() }

                    MetricToggleButton(
                        title: "DCIR",
                        color: .pink,
                        isSelected: showDCIR
                    ) { showDCIR.toggle() }

                    Spacer()
                }
            }
            .padding(10)
            .background(
                .thinMaterial,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .onAppear {
                if sessionAvailable && timeframe == .h24 {
                    timeframe = .session
                    didSetInitialTimeframe = true
                }
            }
            .onChange(of: sessionAvailable) { _, available in
                if available {
                    if !didSetInitialTimeframe && timeframe == .h24 {
                        timeframe = .session
                        didSetInitialTimeframe = true
                    }
                } else if timeframe == .session {
                    timeframe = .h24
                }
            }

            // Уменьшаем число точек для плавной отрисовки
            let readings = history.downsample(data(), maxPoints: 800)

            // Информационная панель здоровья
            if !readings.isEmpty {
                BatteryHealthInfoPanel(readings: readings, snapshot: snapshot)
            }

            // График
            EnhancedChartCard(title: titleForChart(readings: readings)) {
                let segments = chargingSegments(readings: readings)
                let raw = data()
                let generatorEvents = getGeneratorEvents()

                Chart {
                    // Заштриховываем интервалы, когда устройство было на зарядке
                    ForEach(segments.indices, id: \.self) { i in
                        let s = segments[i]
                        RectangleMark(
                            xStart: .value("Start", s.0),
                            xEnd: .value("End", s.1)
                        )
                        .foregroundStyle(Color.blue.opacity(0.08))
                    }
                    
                    // Маркеры событий генератора нагрузки
                    ForEach(generatorEvents.indices, id: \.self) { i in
                        let event = generatorEvents[i]
                        RuleMark(
                            x: .value("Event", event.timestamp)
                        )
                        .foregroundStyle(event.type == .generatorStarted ? Color.orange.opacity(0.6) : Color.gray.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))
                    }
                    // Ряды данных
                    if showPercent {
                        ForEach(readings, id: \.timestamp) { r in
                            LineMark(
                                x: .value("t", r.timestamp),
                                y: .value("%", r.percentage)
                            )
                            .foregroundStyle(by: .value("series", "percent"))
                            .interpolationMethod(.monotone)
                        }
                    }
                    if showTemp {
                        ForEach(readings, id: \.timestamp) { r in
                            LineMark(
                                x: .value("t", r.timestamp),
                                y: .value("°C", r.temperature)
                            )
                            .foregroundStyle(by: .value("series", "temp"))
                            .interpolationMethod(.monotone)
                        }
                    }
                    if showVolt {
                        ForEach(readings, id: \.timestamp) { r in
                            LineMark(
                                x: .value("t", r.timestamp),
                                y: .value("V", r.voltage)
                            )
                            .foregroundStyle(by: .value("series", "volt"))
                            .interpolationMethod(.monotone)
                        }
                    }
                    // OCV overlay reconstructed from readings (requires DCIR points if available)
                    if showOCV {
                        let ocvAnalyzer = OCVAnalyzer(dcirPoints: [])
                        let ocvCurve = ocvAnalyzer.buildOCVCurve(from: raw, binSize: 2.0)
                        // Отобразим OCV как SOC vs Voltage, сопоставив SOC к времени через ближайшие точки
                        // Для простоты прорисуем как Voltage vs Time по ближайшему времени в бине
                        ForEach(ocvCurve.indices, id: \.self) { i in
                            let pt = ocvCurve[i]
                            LineMark(
                                x: .value("t", pt.timestamp),
                                y: .value("V_OC", pt.ocvVoltage)
                            )
                            .foregroundStyle(by: .value("series", "ocv"))
                            .interpolationMethod(.monotone)
                        }
                    }
                    if showPower {
                        let powers = powerSeries(raw)
                        ForEach(powers.indices, id: \.self) { i in
                            let p = powers[i]
                            LineMark(x: .value("t", p.0), y: .value("W", p.1))
                                .foregroundStyle(by: .value("series", "power"))
                                .interpolationMethod(.linear)
                        }
                    }
                    if showHealthScore {
                        let healthPoints = healthScoreSeries(raw)
                        ForEach(healthPoints.indices, id: \.self) { i in
                            let h = healthPoints[i]
                            LineMark(x: .value("t", h.0), y: .value("Score", h.1))
                                .foregroundStyle(by: .value("series", "health"))
                                .interpolationMethod(.monotone)
                        }
                    }
                    // DCIR vs SOC как точки на отдельной оси по времени: отобразим маркерами
                    if showDCIR {
                        // В AnalyticsEngine DCIR из истории может быть извлечён. Попытаемся рассчитать на лету
                        let engine = AnalyticsEngine()
                        let dcirPts = engine.analyze(history: raw, snapshot: snapshot).dcirAt50Percent != nil ? engine : nil
                        // Если в кеше уже посчитано в рамках healthScoreSeries — используем простую на лету оценку
                        // Упростим: вычислим DCIR по ступеням мощности (быстрая эвристика)
                        var plotted: [(Date, Double)] = []
                        for idx in 1..<raw.count {
                            let prev = raw[idx-1]
                            let cur = raw[idx]
                            let dt = cur.timestamp.timeIntervalSince(prev.timestamp)
                            if prev.isCharging || cur.isCharging || dt <= 0 || dt > 3 { continue }
                            let dP = abs(cur.power) - abs(prev.power)
                            if abs(dP) >= 3.0 {
                                if let pt = DCIRCalculator.estimateDCIR(samples: raw, pulseStartIndex: idx, windowSeconds: 3.0) {
                                    // Привяжем к текущему времени
                                    plotted.append((cur.timestamp, pt.resistanceMohm))
                                }
                            }
                        }
                        ForEach(plotted.indices, id: \.self) { i in
                            let p = plotted[i]
                            PointMark(x: .value("t", p.0), y: .value("mΩ", p.1))
                                .foregroundStyle(by: .value("series", "dcir"))
                        }
                    }
                    if showDrain {
                        let drains = drainSeries(raw)
                        ForEach(drains.indices, id: \.self) { i in
                            let d = drains[i]
                            LineMark(x: .value("t", d.0), y: .value("%/h", d.1))
                                .foregroundStyle(by: .value("series", "drain"))
                                .interpolationMethod(.linear)
                        }
                    }
                    
                    // Маркеры микро-дропов
                    let microDropEvents = microDrops(raw)
                    ForEach(microDropEvents.indices, id: \.self) { i in
                        let drop = microDropEvents[i]
                        PointMark(
                            x: .value("t", drop.0),
                            y: .value("%", Double(drop.1))
                        )
                        .foregroundStyle(.red)
                        .symbolSize(30)
                    }

                }
                .chartForegroundStyleScale([
                    "percent": .blue,
                    "temp": .red,
                    "volt": .green,
                    "ocv": .teal,
                    "power": .orange,
                    "health": .purple,
                    "dcir": .pink,
                    "drain": .yellow,
                ])
                .chartLegend(.hidden)
                .frame(height: 200)
            }
        }
    }

    private func titleForChart(readings: [BatteryReading]) -> String {
        // Заголовок: выбранные ряды + краткая статистика
        var parts: [String] = []
        if showPercent { parts.append("%") }
        if showTemp { parts.append("°C") }
        if showVolt { parts.append("V") }
        if showPower { parts.append("W") }
        if showHealthScore { parts.append("Health") }
        if showDrain { parts.append("%/h") }
        var s = parts.joined(separator: ", ")
        var extras: [String] = []
        let raw = data()
        if showPower {
            let avgPower = avgPower(raw)
            extras.append(
                String(
                    format: i18n.t("avg.power.watts"),
                    String(format: "%.1f", avgPower)
                )
            )
        }
        if showDrain {
            let avg = avgDrain(raw)
            extras.append(
                String(
                    format: i18n.t("avg.discharge.per.hour.short"),
                    String(format: "%.1f", avg)
                )
            )
        }
        if showPercent {
            let trend = trendDrain(raw)
            if trend > 0 {
                extras.append(
                    String(
                        format: i18n.t("trend.discharge.per.hour.short"),
                        String(format: "%.1f", trend)
                    )
                )
            }
        }
        let extraStr =
            extras.isEmpty ? "" : " • " + extras.joined(separator: " • ")
        if s.isEmpty {
            s = timeframe.localizedTitle(using: i18n)
        } else {
            s += " — " + timeframe.localizedTitle(using: i18n)
        }
        return s + extraStr
    }

    private func chargingSegments(readings: [BatteryReading]) -> [(Date, Date)]
    {
        // Находим непрерывные участки, когда шла зарядка
        var out: [(Date, Date)] = []
        var start: Date? = nil
        for r in readings {
            if r.isCharging {
                if start == nil { start = r.timestamp }
            } else if let st = start {
                out.append((st, r.timestamp))
                start = nil
            }
        }
        if let st = start, let last = readings.last?.timestamp {
            out.append((st, last))
        }
        return out
    }

    private func microDrops(_ raw: [BatteryReading]) -> [(Date, Int)] {
        // Быстрые падения процента без зарядки (≥2% за ≤120 сек)
        guard raw.count >= 2 else { return [] }
        var out: [(Date, Int)] = []
        for i in 1..<raw.count {
            let prev = raw[i - 1]
            let cur = raw[i]
            let dt = cur.timestamp.timeIntervalSince(prev.timestamp)
            let d = cur.percentage - prev.percentage
            if !cur.isCharging && !prev.isCharging && dt <= 120 && d <= -2 {
                out.append((cur.timestamp, cur.percentage))
            }
        }
        return out
    }

    private func regressionLine(_ raw: [BatteryReading]) -> (
        (Date, Int)?, (Date, Int)?
    ) {
        // Расчёт линии тренда по методу наименьших квадратов
        let points = raw.filter { !$0.isCharging }
        guard points.count >= 2, let first = points.first,
            let last = points.last
        else { return (nil, nil) }
        // Compute slope via simple least squares
        let t0 = points.first!.timestamp.timeIntervalSince1970
        var xs: [Double] = []
        var ys: [Double] = []
        for r in points {
            xs.append((r.timestamp.timeIntervalSince1970 - t0) / 3600.0)
            ys.append(Double(r.percentage))
        }
        let n = Double(xs.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).map(*).reduce(0, +)
        let sumXX = xs.map { $0 * $0 }.reduce(0, +)
        let denom = (n * sumXX - sumX * sumX)
        guard denom != 0 else { return (nil, nil) }
        let slope = (n * sumXY - sumX * sumY) / denom  // % per hour change
        let hoursSpan =
            (last.timestamp.timeIntervalSince(first.timestamp)) / 3600.0
        let yStart = ys.first ?? Double(first.percentage)
        let yEnd = yStart + slope * hoursSpan
        return (
            (first.timestamp, Int(yStart.rounded())),
            (last.timestamp, Int(yEnd.rounded()))
        )
    }

    private func drainSeries(_ raw: [BatteryReading]) -> [(Date, Double)] {
        // Серия разряда в %/ч между соседними точками без зарядки
        guard raw.count >= 2 else { return [] }
        var out: [(Date, Double)] = []
        for i in 1..<raw.count {
            let prev = raw[i - 1]
            let cur = raw[i]
            let dt = cur.timestamp.timeIntervalSince(prev.timestamp) / 3600.0
            guard dt > 0 else { continue }
            let dPercent = Double(prev.percentage - cur.percentage)
            if !prev.isCharging && !cur.isCharging && dPercent >= 0 {
                out.append((cur.timestamp, dPercent / dt))
            }
        }
        return out
    }

    private func avgDrain(_ raw: [BatteryReading]) -> Double {
        // Среднее значение разряда %/ч по серии
        let s = drainSeries(raw)
        guard !s.isEmpty else { return 0 }
        let avg = s.map { $0.1 }.reduce(0, +) / Double(s.count)
        return max(0, avg)
    }

    private func trendDrain(_ raw: [BatteryReading]) -> Double {
        // Тренд разряда %/ч по регрессии (без зарядки)
        let pts = raw.filter { !$0.isCharging }
        guard pts.count >= 2 else { return 0 }
        let t0 = pts.first!.timestamp.timeIntervalSince1970
        var xs: [Double] = []
        var ys: [Double] = []
        for r in pts {
            xs.append((r.timestamp.timeIntervalSince1970 - t0) / 3600.0)
            ys.append(Double(r.percentage))
        }
        let n = Double(xs.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).map(*).reduce(0, +)
        let sumXX = xs.map { $0 * $0 }.reduce(0, +)
        let denom = (n * sumXX - sumX * sumX)
        guard denom != 0 else { return 0 }
        let slope = (n * sumXY - sumX * sumY) / denom  // % per hour change
        return max(0, -slope)
    }
    
    private func powerSeries(_ raw: [BatteryReading]) -> [(Date, Double)] {
        // Серия мощности P = V × I в Вт из прямых измерений
        guard !raw.isEmpty else { return [] }
        var out: [(Date, Double)] = []
        for r in raw {
            let p = abs(r.power)
            if !r.isCharging && p >= 0 { out.append((r.timestamp, p)) }
        }
        return out
    }
    
    private func avgPower(_ raw: [BatteryReading]) -> Double {
        // Средняя мощность в Вт по серии
        let s = powerSeries(raw)
        guard !s.isEmpty else { return 0 }
        let avg = s.map { $0.1 }.reduce(0, +) / Double(s.count)
        return max(0, avg)
    }
    
    private func healthScoreSeries(_ raw: [BatteryReading]) -> [(Date, Double)] {
        guard raw.count >= 8 else { return [] }
        // Подбираем окно анализа в зависимости от выбранного периода
        let windowSeconds: TimeInterval = {
            switch timeframe {
            case .session: return 30 * 60 // 30 минут
            case .h24: return 2 * 3600    // 2 часа
            case .d7: return 6 * 3600     // 6 часов
            case .d30: return 12 * 3600   // 12 часов
            }
        }()
        let engine = AnalyticsEngine()
        var series: [(Date, Double)] = []
        // Ограничим число точек для производительности
        let maxPoints = 200
        let step = max(1, raw.count / maxPoints)
        for idx in stride(from: 0, to: raw.count, by: step) {
            let t = raw[idx].timestamp
            let start = t.addingTimeInterval(-windowSeconds)
            // Берем окно данных до текущей точки
            let window = raw.filter { $0.timestamp >= start && $0.timestamp <= t }
            guard window.count >= 4 else { continue }
            let analysis = engine.analyze(history: window, snapshot: snapshot)
            series.append((t, Double(analysis.healthScore)))
        }
        return series
    }
    
    /// Получает события генератора для текущего временного диапазона
    private func getGeneratorEvents() -> [HistoryEvent] {
        let readings = data()
        guard let firstReading = readings.first, let lastReading = readings.last else { return [] }
        return history.eventsBetween(from: firstReading.timestamp, to: lastReading.timestamp)
    }
}

struct ChartCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(10)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}

struct EnhancedChartCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }
            content()
        }
        .padding(12)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.accentColor.opacity(0.1), lineWidth: 1)
        )
    }
}

struct TogglePill: View {
    let label: LocalizedStringKey
    let isOn: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .lineLimit(1)
        }
        .buttonStyle(SelectablePillButtonStyle(isOn: isOn, color: color))
    }
}

struct SelectablePillButtonStyle: ButtonStyle {
    var isOn: Bool
    var color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isOn ? color.opacity(0.15) : Color.clear)
            )
            .overlay(
                Capsule()
                    .stroke(
                        isOn ? color : Color.gray.opacity(0.4),
                        lineWidth: 1
                    )
            )
            .foregroundStyle(isOn ? color : .primary)
            .animation(.easeInOut(duration: 0.15), value: isOn)
    }
}

struct BatteryHealthInfoPanel: View {
    let readings: [BatteryReading]
    let snapshot: BatterySnapshot
    @ObservedObject private var i18n = Localization.shared
    
    private var analytics: AnalyticsEngine {
        AnalyticsEngine()
    }
    
    private var analysis: BatteryAnalysis {
        analytics.analyze(history: readings, snapshot: snapshot)
    }
    
    private var healthColor: Color {
        let score = analysis.healthScore
        if score >= 85 { return .green }
        else if score >= 70 { return .orange }
        else { return .red }
    }
    
    private var healthZoneText: String {
        let score = analysis.healthScore
        if score >= 85 { return i18n.t("health.zone.excellent") }
        else if score >= 70 { return i18n.t("health.zone.acceptable") }
        else { return i18n.t("health.zone.poor") }
    }
    
    private var recommendationText: String {
        let score = analysis.healthScore
        if score >= 85 { return i18n.t("health.recommendation.excellent") }
        else if score >= 70 { return i18n.t("health.recommendation.acceptable") }
        else if score >= 50 { return i18n.t("health.recommendation.poor") }
        else { return i18n.t("health.recommendation.critical") }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "heart.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(healthColor)
                Text(i18n.t("health.score.composite"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }
            
            HStack(spacing: 16) {
                // Health Score (крупно)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(analysis.healthScore)")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(healthColor)
                    Text(healthZoneText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Divider()
                    .frame(height: 40)
                
                // Ключевые метрики в две колонки
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        HealthMetricRow(
                            title: "SOH:",
                            value: String(format: "%.0f%%", analysis.sohEnergy),
                            color: analysis.sohEnergy >= 85 ? .green : analysis.sohEnergy >= 70 ? .orange : .red
                        )
                        HealthMetricRow(
                            title: i18n.t("avg.power.watts").replacingOccurrences(of: "%s", with: ""),
                            value: String(format: "%.1fW", analysis.averagePower),
                            color: analysis.averagePower <= 10 ? .green : analysis.averagePower <= 20 ? .orange : .red
                        )
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HealthMetricRow(
                            title: i18n.t("micro.drops.count").replacingOccurrences(of: "%d", with: ""),
                            value: "\(analysis.microDropEvents)",
                            color: analysis.microDropEvents == 0 ? .green : analysis.microDropEvents <= 2 ? .orange : .red
                        )
                        HealthMetricRow(
                            title: "\(i18n.t("temperature")):",
                            value: String(format: "%.1f°C", snapshot.temperature),
                            color: snapshot.temperature <= 30 ? .green : snapshot.temperature <= 35 ? .orange : .red
                        )
                    }
                }
                
                Spacer()
            }
            
            // Рекомендация
            Text(recommendationText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(healthColor.opacity(0.3), lineWidth: 1)
        )
    }
}

struct HealthMetricRow: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }
}
