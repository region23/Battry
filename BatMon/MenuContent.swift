import SwiftUI
import AppKit

enum Panel: String, CaseIterable, Identifiable {
    case overview = "Обзор"
    case charts = "Графики"
    case calibration = "Калибровка"
    var id: String { rawValue }
}

struct MenuContent: View {
    @ObservedObject var battery: BatteryViewModel
    @ObservedObject var history: HistoryStore
    @ObservedObject var analytics: AnalyticsEngine
    @ObservedObject var calibrator: CalibrationEngine
    @State private var isAnalyzing = false
    @State private var panel: Panel = .overview

    var body: some View {
        VStack(spacing: 10) {
            header
            Picker("", selection: $panel) {
                ForEach(Panel.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.segmented)

            Divider()

            Group {
                switch panel {
                case .overview: overview
                case .charts: ChartsPanel(history: history)
                case .calibration: CalibrationPanel(calibrator: calibrator, history: history, snapshot: battery.state)
                }
            }

            Divider()
            controls
        }
        .padding(12)
        .frame(minWidth: 380)
        .animation(.default, value: battery.state)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: getBatteryIcon())
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(battery.tintColor)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(getBatteryPercentageText())
                        .font(.system(size: 20, weight: .semibold))
                    if battery.state.isCharging {
                        Label("Заряжается", systemImage: "bolt.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(getPowerSourceText())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(battery.timeRemainingText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
    
    private func getBatteryIcon() -> String {
        // Если устройство не имеет батареи, показываем иконку вилки при питании от сети
        if !battery.state.hasBattery {
            return battery.state.powerSource == .ac ? "powerplug" : "powerplug"
        }
        
        // Если устройство имеет батарею, используем обычную логику
        return battery.state.powerSource == .ac ? "powerplug" : battery.symbolForCurrentLevel
    }
    
    private func getBatteryPercentageText() -> String {
        // Если устройство не имеет батареи, не показываем проценты
        if !battery.state.hasBattery {
            return ""
        }
        
        // Если устройство имеет батарею, показываем проценты
        return "\(battery.state.percentage)%"
    }
    
    private func getPowerSourceText() -> String {
        // Если питание от сети, независимо от наличия батареи, показываем "Питание от сети"
        if battery.state.powerSource == .ac {
            return "Питание от сети"
        }
        
        // На Mac Mini даже при отключенном питании важно показать правильный статус
        // Если устройство не имеет батареи, показываем "Питание от сети" как основное состояние
        if !battery.state.hasBattery {
            return "Питание от сети"
        }
        
        // Если устройство имеет батарею и питание не от сети
        return "От батареи"
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StatCard(title: "Циклы", value: battery.state.cycleCount == 0 ? "—" : "\(battery.state.cycleCount)")
                StatCard(title: "Износ", value: String(format: "%.0f%%", battery.state.wearPercent))
                StatCard(title: "Напряжение", value: battery.state.voltage > 0 ? String(format: "%.2f V", battery.state.voltage) : "—")
            }
            HStack {
                StatCard(title: "Температура", value: battery.state.temperature > 0 ? String(format: "%.1f ℃", battery.state.temperature) : "—")
                StatCard(title: "Max/Design", value:
                         battery.state.designCapacity > 0 && battery.state.maxCapacity > 0
                         ? "\(battery.state.maxCapacity)/\(battery.state.designCapacity) mAh"
                         : "—")
                StatCard(title: "Разряд, %/ч", value: String(format: "%.1f", analytics.estimateDischargePerHour(history: history.recent(hours: 3))))
            }
            if let last = analytics.lastAnalysis {
                HealthSummary(analysis: last)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    isAnalyzing.toggle()
                    analytics.setSessionActive(isAnalyzing)
                    if isAnalyzing {
                        _ = analytics.analyze(history: history.recent(hours: 24), snapshot: battery.state)
                    }
                } label: {
                    Label(isAnalyzing ? "Остановить анализ" : "Анализ батареи",
                          systemImage: isAnalyzing ? "stop.circle" : "play.circle")
                }
                .buttonStyle(.bordered)

                Button {
                    let result = analytics.analyze(history: history.recent(days: 7), snapshot: battery.state)
                    if let url = ReportGenerator.generateHTML(result: result,
                                                              snapshot: battery.state,
                                                              history: history.recent(days: 7),
                                                              calibration: calibrator.lastResult) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Отчёт", systemImage: "doc.text.image")
                }
                .buttonStyle(.bordered)
                
                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Выйти", systemImage: "power")
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 15, weight: .semibold))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct HealthSummary: View {
    let analysis: BatteryAnalysis
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Итог анализа")
                .font(.headline)
            HStack {
                StatCard(title: "Здоровье", value: "\(analysis.healthScore)/100")
                StatCard(title: "Разряд", value: String(format: "%.1f %%/ч", analysis.avgDischargePerHour))
                StatCard(title: "Автономность", value: String(format: "%.1f ч", analysis.estimatedRuntimeFrom100To0Hours))
            }
            if !analysis.anomalies.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(analysis.anomalies, id: \.self) { a in
                        Label(a, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                    }
                }
            }
            Text(analysis.recommendation)
                .font(.subheadline)
        }
        .padding(8)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
