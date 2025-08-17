import SwiftUI
import AppKit

/// Extension to detect MacBook notch presence
extension NSScreen {
    /// Returns true if this screen has a notch (like MacBook Pro M2/M3 models)
    var hasNotch: Bool {
        guard #available(macOS 12, *) else { return false }
        return safeAreaInsets.top > 0
    }
}

/// Вкладки главного окна
enum Panel: String, CaseIterable, Identifiable {
    case overview
    case trends
    case test
    case settings
    case about
    var id: String { rawValue }
}

/// Главное содержимое окна из строки меню
struct MenuContent: View {
    @ObservedObject var battery: BatteryViewModel
    @ObservedObject var history: HistoryStore
    @ObservedObject var analytics: AnalyticsEngine
    @ObservedObject var calibrator: CalibrationEngine
    @ObservedObject var loadGenerator: LoadGenerator
    @ObservedObject var safetyGuard: LoadSafetyGuard
    @ObservedObject var i18n: Localization = .shared
    @State private var isAnalyzing = false
    @State private var panel: Panel = .overview
    @State private var overviewAnalysis: BatteryAnalysis? = nil
    @State private var hasNotch = false
    @State private var pulseScale: CGFloat = 1.0
    
    /// Вычисляет отступ сверху для корректного позиционирования под челкой
    private var topPadding: CGFloat {
        // Если есть челка, добавляем небольшой отступ для предотвращения залезания под неё
        return hasNotch ? 8 : 0
    }

    var body: some View {
        VStack(spacing: 8) {
            // Заголовок с большой иконкой и краткой сводкой
            header
            HStack(spacing: 8) {
                // Переключение вкладок
                HStack(spacing: 0) {
                    ForEach(Panel.allCases.filter { $0 != .settings && $0 != .about }) { p in
                        Button {
                            panel = p
                        } label: {
                            HStack(spacing: 4) {
                                Text(i18n.t("panel.\(p.rawValue)"))
                                // Пульсирующая точка для активного теста
                                if p == .test && calibrator.state.isActive {
                                    Text(" ") // Дополнительный пробел
                                    Circle()
                                        .fill(.red)
                                        .frame(width: 6, height: 6)
                                        .scaleEffect(pulseScale)
                                        .onAppear {
                                            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                                                pulseScale = 1.3
                                            }
                                        }
                                        .onChange(of: calibrator.state.isActive) { _, isActive in
                                            if isActive {
                                                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                                                    pulseScale = 1.3
                                                }
                                            } else {
                                                pulseScale = 1.0
                                            }
                                        }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(panel == p ? Color.accentColor.opacity(0.2) : Color.clear)
                        )
                        .foregroundStyle(panel == p ? .primary : .secondary)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary.opacity(0.5))
                )
                Spacer(minLength: 8)
                // Открыть вкладку About
                Button {
                    panel = .about
                } label: {
                    Image(systemName: "info.circle")
                }
                .help(i18n.t("about"))
                // Открыть вкладку настроек
                Button {
                    panel = .settings
                } label: {
                    Image(systemName: "gearshape")
                }
                .help(i18n.t("settings"))
            }

            Divider()

            Group {
                switch panel {
                case .overview: overview
                case .trends: ChartsPanel(history: history, calibrator: calibrator, snapshot: battery.state)
                case .test: CalibrationPanel(
                    calibrator: calibrator, 
                    history: history, 
                    snapshot: battery.state,
                    loadGenerator: loadGenerator,
                    safetyGuard: safetyGuard
                )
                case .settings: SettingsPanel(history: history, calibrator: calibrator)
                case .about: AboutPanel()
                }
            }

            Divider()
            
            // Кнопки действий внизу интерфейса
            controls
        }
        .padding(10)
        .frame(minWidth: 380)
        .safeAreaPadding(.top, topPadding)
        .animation(.default, value: battery.state)
        .onAppear {
            // Считаем обзорную аналитику за 7 дней при открытии
            overviewAnalysis = analytics.analyze(history: history.recent(days: 7), snapshot: battery.state)
            // Проверяем наличие челки на текущем экране для корректного позиционирования окна
            // На MacBook'ах с челкой (M2+) окно может провалиться под челку при скрытом меню-баре
            hasNotch = NSScreen.main?.hasNotch ?? false
        }
        .onChange(of: battery.state) { _, _ in
            // Обновляем аналитику при изменении состояния
            overviewAnalysis = analytics.analyze(history: history.recent(days: 7), snapshot: battery.state)
        }
        .contextMenu {
            Button {
                panel = .settings
            } label: {
                Label(i18n.t("settings"), systemImage: "gearshape")
            }
            
            Button {
                panel = .about
            } label: {
                Label(i18n.t("about"), systemImage: "info.circle")
            }
            
            Divider()
            
            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label(i18n.t("quit"), systemImage: "power")
            }
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
                    // Процент заряда и подпись источника питания
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
                    .help(i18n.t("tooltip.time.remaining.header"))
                    .accessibilityLabel(i18n.t("time.remaining"))
            }
            Spacer()
			Image("battry_logo_alpha_horizontal")
				.resizable()
				.aspectRatio(contentMode: .fit)
				.frame(height: 24)
				.accessibilityLabel("Battry Logo")
				.accessibilityHidden(true)
        }
    }
    
    /// Выбирает иконку батареи для шапки
    private func getBatteryIcon() -> String {
        // Если устройство не имеет батареи, показываем иконку вилки при питании от сети
        if !battery.state.hasBattery {
            return battery.state.powerSource == .ac ? "powerplug" : "powerplug"
        }
        
        // Если устройство имеет батарею, используем обычную логику
        return battery.state.powerSource == .ac ? "powerplug" : battery.symbolForCurrentLevel
    }
    
    /// Строка с процентом заряда или пустая, если батареи нет
    private func getBatteryPercentageText() -> String {
        // Если устройство не имеет батареи, скрываем проценты
        if !battery.state.hasBattery {
            return ""
        }
        return "\(battery.state.percentage)%"
    }
    
    /// Текст о текущем источнике питания
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



    private func hasEnoughShortDischargeData() -> Bool {
        let discharging = history.recent(hours: 3).filter { !$0.isCharging }
        guard discharging.count >= 2, let first = discharging.first, let last = discharging.last else { return false }
        let span = last.timestamp.timeIntervalSince(first.timestamp)
        return span >= 3600
    }

    private func hasEnoughAnalysisData() -> Bool {
        let discharging = history.recent(days: 7).filter { !$0.isCharging }
        guard discharging.count >= 4, let first = discharging.first, let last = discharging.last else { return false }
        let span = last.timestamp.timeIntervalSince(first.timestamp)
        return span >= 6 * 3600
    }

    private func shortDischargeValueText() -> String {
        // Текст с краткосрочным разрядом в %/ч для последних 3 часов
        guard hasEnoughShortDischargeData() else { return i18n.t("dash") }
        let v = analytics.estimateDischargePerHour(history: history.recent(hours: 3))
        if i18n.language == .ru {
            return String(format: "%.1f %% в час", v)
        } else {
            return String(format: "%.1f %%/h", v)
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Секция основных характеристик батареи
            CardSection(title: i18n.t("overview.battery.info"), icon: "battery.100") {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6)
                ], spacing: 6) {
                    EnhancedStatCard(
                        title: i18n.t("cycles"),
                        value: battery.state.cycleCount == 0 ? i18n.t("dash") : "\(battery.state.cycleCount)",
                        icon: "repeat.circle",
                        healthStatus: battery.state.cycleCount > 0 ? analytics.evaluateCyclesStatus(cycles: battery.state.cycleCount) : nil
                    )
                    EnhancedStatCard(
                        title: i18n.t("wear"),
                        value: (battery.state.designCapacity > 0 && battery.state.maxCapacity > 0)
                               ? String(format: "%.0f%%", battery.state.wearPercent)
                               : i18n.t("dash"),
                        icon: "chart.line.downtrend.xyaxis",
                        accentColor: battery.state.wearPercent > 20 ? .orange : Color.accentColor,
                        healthStatus: (battery.state.designCapacity > 0 && battery.state.maxCapacity > 0) ? analytics.evaluateWearStatus(wearPercent: battery.state.wearPercent) : nil
                    )
                    EnhancedStatCard(
                        title: i18n.t("temperature"),
                        value: battery.state.temperature > 0 ? String(format: "%.1f°C", battery.state.temperature) : i18n.t("dash"),
                        icon: "thermometer",
                        accentColor: battery.state.temperature > 40 ? .red : Color.accentColor,
                        healthStatus: battery.state.temperature > 0 ? analytics.evaluateTemperatureStatus(temperature: battery.state.temperature) : nil
                    )
                    EnhancedStatCard(
                        title: i18n.t("capacity.fact.design"),
                        value: battery.state.designCapacity > 0 && battery.state.maxCapacity > 0
                               ? "\(battery.state.maxCapacity)/\(battery.state.designCapacity) mAh"
                               : i18n.t("dash"),
                        icon: "bolt",
                        healthStatus: (battery.state.designCapacity > 0 && battery.state.maxCapacity > 0) ? analytics.evaluateCapacityStatus(maxCapacity: battery.state.maxCapacity, designCapacity: battery.state.designCapacity) : nil
                    )
                }
            }
            
            // Секция производительности
            CardSection(title: i18n.t("overview.performance"), icon: "speedometer") {
                EnhancedStatCard(
                    title: i18n.t("discharge.per.hour.3h"),
                    value: shortDischargeValueText(),
                    icon: "chart.line.downtrend.xyaxis",
                    accentColor: hasEnoughShortDischargeData() && analytics.estimateDischargePerHour(history: history.recent(hours: 3)) >= 10 ? .orange : Color.accentColor,
                    healthStatus: hasEnoughShortDischargeData() ? analytics.evaluateDischargeStatus(ratePerHour: analytics.estimateDischargePerHour(history: history.recent(hours: 3))) : nil
                )
            }
            
            if let a = overviewAnalysis, hasEnoughAnalysisData() {
                // Итог аналитики за 7 дней при наличии достаточных данных
                EnhancedHealthSummary(analysis: a)
            }
        }
    }
    
    private var controls: some View {
        HStack {
            Spacer()
            
            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label(i18n.t("quit"), systemImage: "power")
            }
            .buttonStyle(.bordered)
        }
    }

}

struct StatCard: View {
    let title: String
    let value: String
    var iconSystemName: String? = nil
    var badge: String? = nil
    var badgeColor: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let icon = iconSystemName {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .layoutPriority(1)
                    .accessibilityValue(value)
                if let b = badge {
                    Text(b)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(badgeColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityLabel(b)
                }
            }
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
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
    @ObservedObject var i18n: Localization = .shared
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(i18n.t("analysis.summary"))
                .font(.headline)
            HStack {
                StatCard(title: i18n.t("health"), value: "\(analysis.healthScore)/100")
                StatCard(title: i18n.t("avg.discharge.per.hour.7d"), value: i18n.language == .ru ? String(format: "%.1f %% в час", analysis.avgDischargePerHour) : String(format: "%.1f %%/h", analysis.avgDischargePerHour))
                StatCard(title: i18n.t("runtime"), value: i18n.language == .ru ? String(format: "%.1f ч", analysis.estimatedRuntimeFrom100To0Hours) : String(format: "%.1f h", analysis.estimatedRuntimeFrom100To0Hours))
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

struct EnhancedHealthSummary: View {
    let analysis: BatteryAnalysis
    @ObservedObject var i18n: Localization = .shared
    
    private var healthColor: Color {
        switch analysis.healthScore {
        case 80...100: return .green
        case 60..<80: return .orange
        default: return .red
        }
    }
    
    var body: some View {
        CardSection(title: i18n.t("analysis.summary"), icon: "heart.text.square") {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6)
            ], spacing: 6) {
                EnhancedStatCard(
                    title: i18n.t("health"),
                    value: "\(analysis.healthScore)/100",
                    icon: "heart",
                    accentColor: healthColor
                )
                EnhancedStatCard(
                    title: i18n.t("avg.discharge.per.hour.7d"),
                    value: i18n.language == .ru ? String(format: "%.1f %%/ч", analysis.avgDischargePerHour) : String(format: "%.1f %%/h", analysis.avgDischargePerHour),
                    icon: "chart.line.downtrend.xyaxis",
                    accentColor: analysis.avgDischargePerHour > 15 ? .orange : Color.accentColor
                )
                EnhancedStatCard(
                    title: i18n.t("runtime"),
                    value: i18n.language == .ru ? String(format: "%.1f ч", analysis.estimatedRuntimeFrom100To0Hours) : String(format: "%.1f h", analysis.estimatedRuntimeFrom100To0Hours),
                    icon: "clock",
                    accentColor: analysis.estimatedRuntimeFrom100To0Hours < 3 ? .red : Color.accentColor
                )
            }
            
            if !analysis.anomalies.isEmpty {
                SpacedDivider()
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(i18n.t("overview.anomalies"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    ForEach(analysis.anomalies, id: \.self) { anomaly in
                        HStack(alignment: .top, spacing: 6) {
                            Circle()
                                .fill(.orange)
                                .frame(width: 4, height: 4)
                                .padding(.top, 6)
                            Text(anomaly)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            SpacedDivider()
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "lightbulb")
                        .foregroundStyle(Color.accentColor)
                    Text(i18n.t("overview.recommendation"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                }
                Text(analysis.recommendation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
