import SwiftUI
import AppKit

enum Panel: String, CaseIterable, Identifiable {
    case overview = "Обзор"
    case charts = "Графики"
    case calibration = "Анализ"
    var id: String { rawValue }
}

struct MenuContent: View {
    @ObservedObject var battery: BatteryViewModel
    @ObservedObject var history: HistoryStore
    @ObservedObject var analytics: AnalyticsEngine
    @ObservedObject var calibrator: CalibrationEngine
    @ObservedObject var i18n: Localization = .shared
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
                        Label(i18n.t("charging"), systemImage: "bolt.fill")
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
        // Если устройство не имеет батареи, скрываем проценты
        if !battery.state.hasBattery {
            return ""
        }
        return "\(battery.state.percentage)%"
    }
    
    private func getPowerSourceText() -> String {
        // Если питание от сети, независимо от наличия батареи, показываем "Питание от сети"
        if battery.state.powerSource == .ac {
            return i18n.t("power.ac")
        }
        
        // На Mac Mini даже при отключенном питании важно показать правильный статус
        // Если устройство не имеет батареи, показываем "Питание от сети" как основное состояние
        if !battery.state.hasBattery {
            return i18n.t("power.ac")
        }
        
        // Если устройство имеет батарею и питание не от сети
        return i18n.t("power.battery")
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StatCard(title: i18n.t("cycles"), value: battery.state.cycleCount == 0 ? i18n.t("dash") : "\(battery.state.cycleCount)")
                StatCard(title: i18n.t("wear"), value: String(format: "%.0f%%", battery.state.wearPercent))
                StatCard(title: i18n.t("voltage"), value: battery.state.voltage > 0 ? String(format: "%.2f V", battery.state.voltage) : i18n.t("dash"))
            }
            HStack {
                StatCard(title: i18n.t("temperature"), value: battery.state.temperature > 0 ? String(format: "%.1f ℃", battery.state.temperature) : i18n.t("dash"))
                StatCard(title: i18n.t("max.design"), value:
                         battery.state.designCapacity > 0 && battery.state.maxCapacity > 0
                         ? "\(battery.state.maxCapacity)/\(battery.state.designCapacity) mAh"
                         : i18n.t("dash"))
                StatCard(title: i18n.t("discharge.per.hour"), value: String(format: "%.1f", analytics.estimateDischargePerHour(history: history.recent(hours: 3))))
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
