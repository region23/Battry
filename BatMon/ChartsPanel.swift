import SwiftUI
import Charts

enum Timeframe: String, CaseIterable, Identifiable {
    case h24 = "24ч"
    case d7 = "7д"
    case d30 = "30д"
    var id: String { rawValue }
}

struct ChartsPanel: View {
    @ObservedObject var history: HistoryStore
    @State private var timeframe: Timeframe = .h24
    @State private var showPercent: Bool = true
    @State private var showTemp: Bool = false
    @State private var showVolt: Bool = false
    @State private var showDrain: Bool = false

    private func data() -> [BatteryReading] {
        switch timeframe {
        case .h24: return history.recent(hours: 24)
        case .d7: return history.recent(days: 7)
        case .d30: return history.recent(days: 30)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $timeframe) {
                ForEach(Timeframe.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)

            let readings = history.downsample(data(), maxPoints: 800)

			HStack(spacing: 8) {
				TogglePill(label: LocalizedStringKey("trends.series.charge"), isOn: showPercent, color: .blue) { showPercent.toggle() }
				TogglePill(label: LocalizedStringKey("trends.series.temperature"), isOn: showTemp, color: .red) { showTemp.toggle() }
				TogglePill(label: LocalizedStringKey("trends.series.voltage"), isOn: showVolt, color: .green) { showVolt.toggle() }
				TogglePill(label: LocalizedStringKey("trends.series.drain"), isOn: showDrain, color: .orange) { showDrain.toggle() }
			}

            ChartCard(title: titleForChart(readings: readings)) {
                let segments = chargingSegments(readings: readings)
                let raw = data()
				
                Chart {
                    // Charging shading
                    ForEach(segments.indices, id: \.self) { i in
                        let s = segments[i]
                        RectangleMark(
                            xStart: .value("Start", s.0),
                            xEnd: .value("End", s.1)
                        )
                        .foregroundStyle(Color.blue.opacity(0.08))
                    }
                    // Series
                    if showPercent {
                        ForEach(readings, id: \.timestamp) { r in
                            LineMark(x: .value("t", r.timestamp), y: .value("%", r.percentage))
                                .foregroundStyle(by: .value("series", "percent"))
                                .interpolationMethod(.monotone)
                        }
                    }
                    if showTemp {
                        ForEach(readings, id: \.timestamp) { r in
                            LineMark(x: .value("t", r.timestamp), y: .value("°C", r.temperature))
                                .foregroundStyle(by: .value("series", "temp"))
                                .interpolationMethod(.monotone)
                        }
                    }
                    if showVolt {
                        ForEach(readings, id: \.timestamp) { r in
                            LineMark(x: .value("t", r.timestamp), y: .value("V", r.voltage))
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
                    "drain": .orange
                ])
                .frame(height: 200)
            }
        }
    }

    private func titleForChart(readings: [BatteryReading]) -> String {
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
            extras.append(String(format: NSLocalizedString("avg.discharge.per.hour.short", comment: ""), String(format: "%.1f", avg)))
        }
        if showPercent {
            let trend = trendDrain(raw)
            if trend > 0 {
                extras.append(String(format: NSLocalizedString("trend.discharge.per.hour.short", comment: ""), String(format: "%.1f", trend)))
            }
        }
        let extraStr = extras.isEmpty ? "" : " • " + extras.joined(separator: " • ")
        if s.isEmpty { s = timeframe.rawValue } else { s += " — " + timeframe.rawValue }
        return s + extraStr
    }

    private func chargingSegments(readings: [BatteryReading]) -> [(Date, Date)] {
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
        if let st = start, let last = readings.last?.timestamp { out.append((st, last)) }
        return out
    }

    private func microDrops(_ raw: [BatteryReading]) -> [(Date, Int)] {
        guard raw.count >= 2 else { return [] }
        var out: [(Date, Int)] = []
        for i in 1..<raw.count {
            let prev = raw[i-1]
            let cur = raw[i]
            let dt = cur.timestamp.timeIntervalSince(prev.timestamp)
            let d = cur.percentage - prev.percentage
            if !cur.isCharging && !prev.isCharging && dt <= 120 && d <= -2 {
                out.append((cur.timestamp, cur.percentage))
            }
        }
        return out
    }

    private func regressionLine(_ raw: [BatteryReading]) -> ((Date, Int)?, (Date, Int)?) {
        let points = raw.filter { !$0.isCharging }
        guard points.count >= 2, let first = points.first, let last = points.last else { return (nil, nil) }
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
        let sumXX = xs.map { $0*$0 }.reduce(0, +)
        let denom = (n * sumXX - sumX * sumX)
        guard denom != 0 else { return (nil, nil) }
        let slope = (n * sumXY - sumX * sumY) / denom // % per hour change
        let hoursSpan = (last.timestamp.timeIntervalSince(first.timestamp)) / 3600.0
        let yStart = ys.first ?? Double(first.percentage)
        let yEnd = yStart + slope * hoursSpan
        return ((first.timestamp, Int(yStart.rounded())), (last.timestamp, Int(yEnd.rounded())))
    }

    private func drainSeries(_ raw: [BatteryReading]) -> [(Date, Double)] {
        guard raw.count >= 2 else { return [] }
        var out: [(Date, Double)] = []
        for i in 1..<raw.count {
            let prev = raw[i-1]
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
        let s = drainSeries(raw)
        guard !s.isEmpty else { return 0 }
        let avg = s.map { $0.1 }.reduce(0, +) / Double(s.count)
        return max(0, avg)
    }

    private func trendDrain(_ raw: [BatteryReading]) -> Double {
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
        let sumXX = xs.map { $0*$0 }.reduce(0, +)
        let denom = (n * sumXX - sumX * sumX)
        guard denom != 0 else { return 0 }
        let slope = (n * sumXY - sumX * sumY) / denom // % per hour change
        return max(0, -slope)
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                    .stroke(isOn ? color : Color.gray.opacity(0.4), lineWidth: 1)
            )
            .foregroundStyle(isOn ? color : .primary)
            .animation(.easeInOut(duration: 0.15), value: isOn)
    }
}
