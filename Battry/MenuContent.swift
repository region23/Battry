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
    @ObservedObject var videoLoadEngine: VideoLoadEngine
    @ObservedObject var safetyGuard: LoadSafetyGuard
    @ObservedObject var updateChecker: UpdateChecker
    @ObservedObject var i18n: Localization = .shared
    @Environment(\.colorScheme) var colorScheme
    @State private var isAnalyzing = false
    @State private var panel: Panel = .overview
    @State private var hasNotch = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var isWindowVisible = true
    
    /// Вычисляет отступ сверху для корректного позиционирования под челкой
    private var topPadding: CGFloat {
        // Если есть челка, добавляем небольшой отступ для предотвращения залезания под неё
        return hasNotch ? 8 : 0
    }

    var body: some View {
        VStack(spacing: 8) {
            // Заголовок с большой иконкой и краткой сводкой
            header
            
            // Уведомление о доступном обновлении
            updateNotificationView
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
                                            if isWindowVisible {
                                                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                                                    pulseScale = 1.3
                                                }
                                            }
                                        }
                                        .onChange(of: calibrator.state.isActive) { _, isActive in
                                            if isActive && isWindowVisible {
                                                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                                                    pulseScale = 1.3
                                                }
                                            } else {
                                                pulseScale = 1.0
                                            }
                                        }
                                        .onChange(of: isWindowVisible) { _, visible in
                                            // Управляем анимацией в зависимости от видимости окна
                                            if visible && calibrator.state.isActive {
                                                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                                                    pulseScale = 1.3
                                                }
                                            } else {
                                                pulseScale = calibrator.state.isActive ? 1.3 : 1.0
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
                    analytics: analytics, 
                    snapshot: battery.state,
                    loadGenerator: loadGenerator,
                    videoLoadEngine: videoLoadEngine,
                    safetyGuard: safetyGuard
                )
                case .settings: SettingsPanel(history: history, calibrator: calibrator)
                case .about: AboutPanel(updateChecker: updateChecker)
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
            // Проверяем наличие челки на текущем экране для корректного позиционирования окна
            // На MacBook'ах с челкой (M2+) окно может провалиться под челку при скрытом меню-баре
            hasNotch = NSScreen.main?.hasNotch ?? false
            
            // Подписываемся на изменения видимости окна для оптимизации производительности
            NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: nil,
                queue: .main
            ) { notification in
                if let window = notification.object as? NSWindow {
                    let wasVisible = isWindowVisible
                    isWindowVisible = window.occlusionState.contains(.visible)
                    
                    // Оптимизируем только UI обновления, не затрагивая сбор данных и анализ
                    if isWindowVisible && !wasVisible {
                        // Окно стало видимым - включаем fast mode для более отзывчивого UI
                        Task { @MainActor in
                            battery.enableFastMode()
                        }
                    } else if !isWindowVisible && wasVisible {
                        // Окно скрыто - отключаем fast mode для экономии ресурсов
                        Task { @MainActor in
                            battery.disableFastMode()
                        }
                    }
                }
            }
        }
        .onDisappear {
            // Отписываемся от уведомлений при уничтожении view
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didChangeOcclusionStateNotification,
                object: nil
            )
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
            
            // Generator active badges
            HStack(spacing: 6) {
                if videoLoadEngine.isRunning {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.blue)
                            .frame(width: 6, height: 6)
                            .animation(isWindowVisible ? .easeInOut(duration: 1).repeatForever(autoreverses: true) : .none, value: videoLoadEngine.isRunning)
                        Text("GPU")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.blue)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.1), in: Capsule())
                }
                
                if loadGenerator.isRunning {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 6, height: 6)
                            .animation(isWindowVisible ? .easeInOut(duration: 1).repeatForever(autoreverses: true) : .none, value: loadGenerator.isRunning)
                        Text("CPU")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.1), in: Capsule())
                }
            }
            
            Spacer()
            
			Image(colorScheme == .dark ? "battry-white" : "battry_logo_alpha_horizontal")
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



    private func discharge1hValueText() -> String {
        guard analytics.hasEnoughData1h(history: history.items) else { 
            return i18n.t("collecting.stats") 
        }
        let v = analytics.estimateDischargePerHour1h(history: history.items)
        // Если разряд близок к 0, показываем "копим статистику"
        if v < 0.1 {
            return i18n.t("collecting.stats")
        }
        if i18n.language == .ru {
            return String(format: "%.1f%% в час", v)
        } else {
            return String(format: "%.1f %%/h", v)
        }
    }
    
    private func discharge24hValueText() -> String {
        guard analytics.hasEnoughData24h(history: history.items) else { 
            return i18n.t("collecting.stats") 
        }
        let v = analytics.estimateDischargePerHour24h(history: history.items)
        // Если разряд близок к 0, показываем "копим статистику"
        if v < 0.1 {
            return i18n.t("collecting.stats")
        }
        if i18n.language == .ru {
            return String(format: "%.1f%% в час", v)
        } else {
            return String(format: "%.1f %%/h", v)
        }
    }
    
    private func discharge7dValueText() -> String {
        guard analytics.hasEnoughData7d(history: history.items) else { 
            return i18n.t("collecting.stats") 
        }
        let v = analytics.estimateDischargePerHour7d(history: history.items)
        // Если разряд близок к 0, показываем "копим статистику"
        if v < 0.1 {
            return i18n.t("collecting.stats")
        }
        if i18n.language == .ru {
            return String(format: "%.1f%% в час", v)
        } else {
            return String(format: "%.1f %%/h", v)
        }
    }
    
    /// Определяет цвет акцента для карточки "Разряд (1 час)" с учетом времени после теста
    private func get1hAccentColor() -> Color {
        guard analytics.hasEnoughData1h(history: history.items) else { 
            return .secondary 
        }
        
        let discharge = analytics.estimateDischargePerHour1h(history: history.items)
        
        // Если недавно был тест (менее часа назад), используем нейтральный цвет
        if !history.isMoreThanHourSinceLastTest() {
            return .secondary
        }
        
        // Обычная логика цветов для нормального использования
        return discharge >= 15 ? .orange : Color.accentColor
    }
    
    /// Определяет статус здоровья для карточки "Разряд (1 час)" с учетом времени после теста
    private func get1hHealthStatus() -> HealthStatus? {
        guard analytics.hasEnoughData1h(history: history.items) && 
              analytics.estimateDischargePerHour1h(history: history.items) >= 0.1 else { 
            return nil 
        }
        
        // Если недавно был тест (менее часа назад), показываем специальный статус
        if !history.isMoreThanHourSinceLastTest() {
            return .afterTest
        }
        
        // Обычная оценка статуса
        return analytics.evaluateDischargeStatus(ratePerHour: analytics.estimateDischargePerHour1h(history: history.items))
    }
    
    private func estimatedRuntimeText() -> String {
        let runtime = getEstimatedRuntime()
        guard runtime > 0 else { return i18n.t("collecting.stats") }
        if i18n.language == .ru {
            return String(format: "%.1f ч", runtime)
        } else {
            return String(format: "%.1f h", runtime)
        }
    }
    
    private func hasAnyDischargeData() -> Bool {
        return analytics.hasEnoughData1h(history: history.items) ||
               analytics.hasEnoughData24h(history: history.items) ||
               analytics.hasEnoughData7d(history: history.items)
    }
    
    private func isCollecting1h() -> Bool {
        return !analytics.hasEnoughData1h(history: history.items) || 
               analytics.estimateDischargePerHour1h(history: history.items) < 0.1
    }
    
    private func isCollecting24h() -> Bool {
        return !analytics.hasEnoughData24h(history: history.items) || 
               analytics.estimateDischargePerHour24h(history: history.items) < 0.1
    }
    
    private func isCollecting7d() -> Bool {
        return !analytics.hasEnoughData7d(history: history.items) || 
               analytics.estimateDischargePerHour7d(history: history.items) < 0.1
    }
    
    private func isCollectingRuntime() -> Bool {
        return getEstimatedRuntime() <= 0
    }
    
    private func getEstimatedRuntime() -> Double {
        // Пробуем получить наиболее точную оценку автономности
        if analytics.hasEnoughData24h(history: history.items) {
            let dischargeRate = analytics.estimateDischargePerHour24h(history: history.items)
            return dischargeRate > 0 ? 100.0 / dischargeRate : 0
        } else if analytics.hasEnoughData7d(history: history.items) {
            let dischargeRate = analytics.estimateDischargePerHour7d(history: history.items)
            return dischargeRate > 0 ? 100.0 / dischargeRate : 0
        } else if analytics.hasEnoughData1h(history: history.items) {
            let dischargeRate = analytics.estimateDischargePerHour1h(history: history.items)
            return dischargeRate > 0 ? 100.0 / dischargeRate : 0
        }
        return 0
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
                    .help(i18n.t("temperature.tooltip"))
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
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6)
                ], spacing: 6) {
                    EnhancedStatCard(
                        title: i18n.t("discharge.per.hour.1h"),
                        value: discharge1hValueText(),
                        icon: "chart.line.downtrend.xyaxis",
                        accentColor: get1hAccentColor(),
                        healthStatus: get1hHealthStatus(),
                        isCollectingData: isCollecting1h()
                    )
                    EnhancedStatCard(
                        title: i18n.t("discharge.per.hour.24h"),
                        value: discharge24hValueText(),
                        icon: "chart.line.downtrend.xyaxis",
                        accentColor: analytics.hasEnoughData24h(history: history.items) && analytics.estimateDischargePerHour24h(history: history.items) >= 12 ? .orange : (analytics.hasEnoughData24h(history: history.items) ? Color.accentColor : .secondary),
                        healthStatus: analytics.hasEnoughData24h(history: history.items) && analytics.estimateDischargePerHour24h(history: history.items) >= 0.1 ? analytics.evaluateDischargeStatus(ratePerHour: analytics.estimateDischargePerHour24h(history: history.items)) : nil,
                        isCollectingData: isCollecting24h()
                    )
                    EnhancedStatCard(
                        title: i18n.t("discharge.per.hour.7d"),
                        value: discharge7dValueText(),
                        icon: "chart.line.downtrend.xyaxis",
                        accentColor: analytics.hasEnoughData7d(history: history.items) && analytics.estimateDischargePerHour7d(history: history.items) >= 10 ? .orange : (analytics.hasEnoughData7d(history: history.items) ? Color.accentColor : .secondary),
                        healthStatus: analytics.hasEnoughData7d(history: history.items) && analytics.estimateDischargePerHour7d(history: history.items) >= 0.1 ? analytics.evaluateDischargeStatus(ratePerHour: analytics.estimateDischargePerHour7d(history: history.items)) : nil,
                        isCollectingData: isCollecting7d()
                    )
                    EnhancedStatCard(
                        title: i18n.t("runtime.estimated"),
                        value: estimatedRuntimeText(),
                        icon: "clock",
                        accentColor: hasAnyDischargeData() ? (getEstimatedRuntime() < 3 ? .red : Color.accentColor) : .secondary,
                        isCollectingData: isCollectingRuntime()
                    )
                }
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
    
    @ViewBuilder
    private var updateNotificationView: some View {
        if case .updateAvailable(let version, let url) = updateChecker.status, !updateChecker.isDismissed {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(i18n.t("update.available"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("v\(version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    if let downloadURL = URL(string: url) {
                        NSWorkspace.shared.open(downloadURL)
                    }
                } label: {
                    Text(i18n.t("update.download"))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.blue, in: Capsule())
                
                Button {
                    updateChecker.dismissUpdate()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.20, green: 0.60, blue: 0.86),  // Синий
                        Color(red: 0.14, green: 0.50, blue: 0.78)   // Более темный синий
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(0.15)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue.opacity(0.3), lineWidth: 0.5)
            )
            .cornerRadius(8)
            .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
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
