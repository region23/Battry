import SwiftUI
import AppKit

enum Panel: String, CaseIterable, Identifiable {
    case overview
    case trends
    case test
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
    @State private var overviewAnalysis: BatteryAnalysis? = nil
    @State private var isOptionPressed: Bool = false
    @State private var flagsMonitorLocal: Any? = nil
    @State private var flagsMonitorGlobal: Any? = nil

    var body: some View {
        VStack(spacing: 10) {
            header
            if isOptionPressed {
                quickStats
            }
            HStack(spacing: 8) {
                Picker("", selection: $panel) {
                    ForEach(Panel.allCases) { p in
                        Text(i18n.t("panel.\(p.rawValue)")).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                Spacer(minLength: 8)
                Menu {
                    ForEach(AppLanguage.allCases) { lang in
                        Button(action: { i18n.language = lang }) {
                            Text(lang.label)
                            if i18n.language == lang { Image(systemName: "checkmark") }
                        }
                    }
                } label: {
                    Image(systemName: "globe")
                }
                .help("Language")
            }

            Divider()

            Group {
                switch panel {
                case .overview: overview
                case .trends: ChartsPanel(history: history)
                case .test: CalibrationPanel(calibrator: calibrator, history: history, snapshot: battery.state)
                }
            }

            Divider()
            controls
        }
        .padding(12)
        .frame(minWidth: 380)
        .animation(.default, value: battery.state)
        .onAppear {
            overviewAnalysis = analytics.analyze(history: history.recent(days: 7), snapshot: battery.state)
            // Track Option key for quick metrics
            flagsMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { e in
                isOptionPressed = e.modifierFlags.contains(.option)
                return e
            }
            flagsMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { e in
                isOptionPressed = e.modifierFlags.contains(.option)
            }
        }
        .onChange(of: battery.state) { _, _ in
            overviewAnalysis = analytics.analyze(history: history.recent(days: 7), snapshot: battery.state)
        }
        .onDisappear {
            if let m = flagsMonitorLocal { NSEvent.removeMonitor(m) }
            if let m = flagsMonitorGlobal { NSEvent.removeMonitor(m) }
            flagsMonitorLocal = nil
            flagsMonitorGlobal = nil
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: getBatteryIcon())
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(battery.tintColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(getBatteryPercentageText())
                        .font(.system(size: 20, weight: .semibold))
                        .accessibilityLabel(i18n.t("panel.overview"))
                        .accessibilityValue("\(battery.state.percentage)%")
                    if battery.state.isCharging {
                        Label(i18n.t("charging"), systemImage: "bolt.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(getPowerSourceText())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(i18n.t("power.battery"))
                    }
                }
                Text(battery.timeRemainingText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(i18n.t("time.remaining"))
            }
            Spacer()
            Circle()
                .fill(statusColor())
                .frame(width: 8, height: 8)
                .accessibilityLabel("Status")
                .accessibilityHidden(true)
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

    private func statusColor() -> Color {
        if battery.state.temperature > 40 { return .red }
        if battery.state.isCharging { return .green }
        switch battery.state.percentage {
        case 0..<20: return .red
        case 20..<50: return .orange
        default: return .accentColor
        }
    }

    private func temperatureBadge() -> (text: String?, color: Color) {
        guard battery.state.temperature > 0 else { return (nil, .secondary) }
        if battery.state.temperature >= 40 {
            return (i18n.t("badge.hot"), .red)
        }
        return (i18n.t("badge.normal"), .green)
    }

    private func dischargeBadge() -> (text: String?, color: Color) {
        let v = analytics.estimateDischargePerHour(history: history.recent(hours: 3))
        if v >= 10 {
            return (i18n.t("badge.high.load"), .orange)
        }
        return (i18n.t("badge.normal"), .green)
    }

    private var quickStats: some View {
        HStack(spacing: 8) {
            Label(String(format: "%.1f ℃", battery.state.temperature), systemImage: "thermometer")
                .foregroundStyle(.secondary)
                .font(.caption)
            Label(String(format: "%.2f V", battery.state.voltage), systemImage: "bolt")
                .foregroundStyle(.secondary)
                .font(.caption)
            let d = analytics.estimateDischargePerHour(history: history.recent(hours: 3))
            Label(String(format: "%.1f %%/ч", d), systemImage: "speedometer")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .transition(.opacity)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StatCard(title: i18n.t("health"), value: "\(overviewAnalysis?.healthScore ?? 100)/100")
                StatCard(title: i18n.t("cycles"), value: battery.state.cycleCount == 0 ? i18n.t("dash") : "\(battery.state.cycleCount)")
                StatCard(title: i18n.t("wear"), value: String(format: "%.0f%%", battery.state.wearPercent))
            }
            HStack {
                StatCard(title: i18n.t("temperature"), value: battery.state.temperature > 0 ? String(format: "%.1f ℃", battery.state.temperature) : i18n.t("dash"), badge: temperatureBadge().text, badgeColor: temperatureBadge().color)
                StatCard(title: i18n.t("capacity.fact.design"), value:
                         battery.state.designCapacity > 0 && battery.state.maxCapacity > 0
                         ? "\(battery.state.maxCapacity)/\(battery.state.designCapacity) mAh"
                         : i18n.t("dash"))
                StatCard(title: i18n.t("discharge.per.hour"), value: String(format: "%.1f", analytics.estimateDischargePerHour(history: history.recent(hours: 3))), badge: dischargeBadge().text, badgeColor: dischargeBadge().color)
            }
            if let a = overviewAnalysis {
                HealthSummary(analysis: a)
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
                Button {
                    panel = .test
                } label: {
                    Label(i18n.t("start.test"), systemImage: "target")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
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
    var badge: String? = nil
    var badgeColor: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityValue(value)
                if let b = badge {
                    Text(b)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(badgeColor)
                        .accessibilityLabel(b)
                }
            }
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
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
