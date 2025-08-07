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

            let readings = history.downsample(data(), maxPoints: 500)

            ChartCard(title: "Заряд (%) — \(timeframe.rawValue)") {
                Chart(readings, id: \.timestamp) { r in  // используем timestamp как id
                    LineMark(
                        x: .value("Время", r.timestamp),
                        y: .value("%", r.percentage)
                    )
                    .interpolationMethod(.monotone)
                }
                .chartYScale(domain: 0...100)
                .frame(height: 70)
            }

            ChartCard(title: "Температура (°C) — \(timeframe.rawValue)") {
                Chart(readings, id: \.timestamp) { r in
                    LineMark(
                        x: .value("Время", r.timestamp),
                        y: .value("°C", r.temperature)
                    )
                    .interpolationMethod(.monotone)
                }
                .frame(height: 60)
            }

            ChartCard(title: "Напряжение (V) — \(timeframe.rawValue)") {
                Chart(readings, id: \.timestamp) { r in
                    LineMark(
                        x: .value("Время", r.timestamp),
                        y: .value("V", r.voltage)
                    )
                    .interpolationMethod(.monotone)
                }
                .frame(height: 60)
            }
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
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
