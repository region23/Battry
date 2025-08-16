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
    @ObservedObject private var reportHistory = ReportHistory.shared
    @State private var timeframe: Timeframe = .h24
    @State private var didSetInitialTimeframe: Bool = false
    @State private var showPercent: Bool = true
    @State private var showTemp: Bool = false
    @State private var showVolt: Bool = false
    @State private var showDrain: Bool = false
    @State private var isGeneratingReport = false
    @State private var showSuccessAlert = false

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
            // Секция генерации и просмотра отчетов
            reportsSection
            
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
                        title: i18n.t("trends.series.drain"),
                        color: .orange,
                        isSelected: showDrain
                    ) { showDrain.toggle() }

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

            // График
            EnhancedChartCard(title: titleForChart(readings: readings)) {
                let segments = chargingSegments(readings: readings)
                let raw = data()

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
                    if showDrain {
                        let drains = drainSeries(raw)
                        ForEach(drains.indices, id: \.self) { i in
                            let d = drains[i]
                            LineMark(x: .value("t", d.0), y: .value("%/h", d.1))
                                .foregroundStyle(by: .value("series", "drain"))
                                .interpolationMethod(.linear)
                        }
                    }

                }
                .chartForegroundStyleScale([
                    "percent": .blue,
                    "temp": .red,
                    "volt": .green,
                    "drain": .orange,
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
        if showDrain { parts.append("%/h") }
        var s = parts.joined(separator: ", ")
        var extras: [String] = []
        let raw = data()
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
    
    // MARK: - Reports Section
    
    private var reportsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "doc.text.image")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text(i18n.t("reports.title"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                
                Button {
                    generateReport()
                } label: {
                    HStack(spacing: 4) {
                        if isGeneratingReport {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "plus.circle")
                        }
                        Text(i18n.t("reports.generate"))
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isGeneratingReport)
            }
            
            if !reportHistory.reports.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(reportHistory.reports.prefix(3)) { report in
                        ReportRowView(report: report, reportHistory: reportHistory)
                    }
                    
                    if reportHistory.reports.count > 3 {
                        Button {
                            // TODO: Показать все отчеты в отдельном окне
                        } label: {
                            HStack {
                                Text(i18n.t("reports.show.all"))
                                    .font(.caption)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(i18n.t("reports.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
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
        .alert(i18n.t("reports.success.title"), isPresented: $showSuccessAlert) {
            Button(i18n.t("ok")) { }
        } message: {
            Text(i18n.t("reports.success.message"))
        }
    }
    
    private func generateReport() {
        isGeneratingReport = true
        
        Task {
            // Выполняем анализ в main actor context
            let analytics = AnalyticsEngine()
            let recentHistory = history.recent(days: 7)
            let lastResult = calibrator.lastResult
            
            let analysis = analytics.analyze(
                history: recentHistory, 
                snapshot: snapshot
            )
            
            // Генерация HTML также должна быть в main actor context
            let url = ReportGenerator.generateHTML(
                result: analysis,
                snapshot: snapshot,
                history: recentHistory,
                calibration: lastResult
            )
            
            // Обновляем UI
            isGeneratingReport = false
            
            if let url = url {
                NSWorkspace.shared.open(url)
                showSuccessAlert = true
            }
        }
    }
}

struct ReportRowView: View {
    let report: ReportMetadata
    let reportHistory: ReportHistory
    @ObservedObject private var i18n = Localization.shared
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(report.displayTitle)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text("\(report.dataPoints) \(i18n.t("reports.data.points"))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 4) {
                Button {
                    reportHistory.openReport(report)
                } label: {
                    Image(systemName: "eye")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help(i18n.t("reports.open"))
                
                Button {
                    reportHistory.deleteReport(report)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .help(i18n.t("reports.delete"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary.opacity(0.5))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            reportHistory.openReport(report)
        }
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
